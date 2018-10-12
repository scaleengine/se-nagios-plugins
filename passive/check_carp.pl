#!/usr/bin/env perl
use warnings;
use strict;

use Getopt::Std;
use IPC::Open2;
use POSIX ":sys_wait_h";

###############################################################################
###############################################################################
##                           check_carp.pl                                   ##
## Checks the status of carp IPs                                             ##
## Written by Andrew Fengler                                                 ##
###############################################################################
## Copyright (c) 2018, Andrew Fengler <andrew.fengler@scaleengine.com>       ##
##                                                                           ##
## Permission to use, copy, modify, and/or distribute this software for any  ##
## purpose with or without fee is hereby granted, provided that the above    ##
## copyright notice and this permission notice appear in all copies.         ##
##                                                                           ##
## THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES  ##
## WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF          ##
## MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR   ##
## ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES    ##
## WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN     ##
## ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF   ##
## OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE             ##
###############################################################################
## V. 1.0.0: Initial release                                        20180202 ##
## V. 1.0.1: Fix wording of error states, critical on failover      20180208 ##
###############################################################################
my $version = '1.0.1';
my $version_date = '2018-02-08';


###############################################################################
## Global variables
###############################################################################

my %conf = (
	debug		=> 0,
	hostname	=> '',
	service		=> 'CARP_STATUS',
	multiplexer	=> qx(which nsca_multiplexer.sh),
	hostname	=> qx(hostname),
);
chomp $conf{hostname};
chomp $conf{multiplexer};

my %opt;

my %exit = (
     EX_OK		=> 0,
     EX_USAGE 		=> 64, #The command was used incorrectly
     EX_DATAERR		=> 65, #The user input data was incorrect 
     EX_NOINPUT		=> 66, #An input file (not a system file) did not exist or was not readable.
     EX_NOUSER		=> 67, #The user specified did not exist.
     EX_NOHOST		=> 68, #The host specified did not exist.
     EX_UNAVAILABLE	=> 69, #A service is unavailable.
     EX_SOFTWARE	=> 70, #An internal software error has been detected.
     EX_OSERR		=> 71, #An operating system error has been detected: “cannot fork”, “cannot create pipe”, etc.
     EX_OSFILE		=> 72, #Some system file (e.g., /etc/passwd, /var/run/utx.active, etc.) does not exist, cannot be opened, or has some sort of error 
     EX_CANTCREAT	=> 73, #A (user specified) output file cannot be created.
     EX_IOERR		=> 74, #An error occurred while doing I/O on some file.
     EX_TEMPFAIL	=> 75, #Temporary failure, indicating something that is not really an error.
     EX_PROTOCOL	=> 76, #The remote system returned something that was “not possible” during a protocol exchange.
     EX_NOPERM		=> 77, #You did not have sufficient permission to perform the operation. 
     EX_CONFIG		=> 78, #Something was found in an unconfigured or miscon‐ figured state.
);

my ( $ipset, @s, @carps, $output );
my  $retval = 0; 
my @netif_output = '';

###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] IP,is_master ...\n";
	print "\tis_master should be 1 if master, 0 if slave.\n";
	exit;
}

sub VERSION_MESSAGE
{
	print "$0 version $version by Andrew Fengler (andrew.fengler\@scaleengine.net), $version_date\n";
	exit;
}

sub verb ($@)
{
	local $, = ' ';
	local $\ = "\n";
	shift @_ <= $conf{debug} and print STDERR @_;
	return 1;
}

sub submit_nsca ($$) 
{
	my $ret = $_[0];
	my $string = $_[1];
	verb 0, join "\t", $conf{hostname}, $conf{service}, $ret, $string;
	open MX, '|-', $conf{multiplexer};
	print MX join "\t", $conf{hostname}, $conf{service}, $ret, $string;
	close MX;
}

##############################################################################
## Getopts
##############################################################################

getopts 'f:hvVd', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;
verb 1, "Read %conf from args";


##############################################################################
## Main program
##############################################################################

for $ipset (@ARGV)
{
	verb 1, "processing $ipset";
	@s = split /,/, $ipset;
	push @carps, {ip => $s[0], is_master => $s[1], vhid => 0, state => 0};
}

if ( ! scalar @carps )
{
	verb 0, "ERROR: no carps were given!";
	submit_nsca 3, "UNKNOWN: no carps given\n";
	exit $exit{EX_USAGE};
}

@netif_output = qx(ifconfig -a);

if ( @? )
{
	verb 0, "ERROR: ifconfig returned $?";
	submit_nsca 3, "UNKNOWN: unable to exec ifconfig\n";
	exit $exit{EX_UNAVAILABLE};
}

IPS: for (my $entry = 0; $entry < scalar @carps; $entry++)
{
	verb 1, "Testing $carps[$entry]{ip}";
	for my $line (@netif_output)
	{
		$line =~ /inet $carps[$entry]{ip} / or next;
		if ( $line =~ /vhid (\d+)(?: |$)/ )
		{
			verb 1, "Got vhid: $1";
			$carps[$entry]{vhid} = $1;
			last;
		}
		else
		{
			verb 1, "Couldn't match vhid";
			$output .= "$carps[$entry]{ip}: UNKNOWN: could not get vhid ";
			$retval = ( $retval == 0 ? 3 : $retval );
			next IPS;
		}
	}
	if ( ! $carps[$entry]{vhid} )
	{
		verb 0, "No IPs matched!";
		$output .= "$carps[$entry]{ip}: UNKNOWN: could not find IP ";
		$retval = ( $retval == 0 ? 3 : $retval );
		next IPS;
	}
	for my $line (@netif_output)
	{
		$line =~ /carp: (.+?) vhid $carps[$entry]{vhid} / or next;
		$carps[$entry]{state} = $1;
		verb 1, "Got state: $1";
		last;
	}
	if ( ! $carps[$entry]{state} )
	{
		verb 0, "No carps matched!";
		$output .= "$carps[$entry]{ip}: UNKNOWN: could not find carp ";
		$retval = ( $retval == 0 ? 3 : $retval );
		next IPS;
	}
	if ( $carps[$entry]{state} eq 'MASTER' )
	{
		if ( $carps[$entry]{is_master} )
		{
			verb 1, "Ok, is master";
			$output .= "$carps[$entry]{ip}: MASTER ";
		}
		else
		{
			verb 1, "Warning, is master, but should be backup";
			$output .= "$carps[$entry]{ip}: CRITICAL - MASTER ";
			$retval = 2;
		}
	}
	elsif ( $carps[$entry]{state} eq 'BACKUP' )
	{
		if ( ! $carps[$entry]{is_master} )
		{
			verb 1, "Ok, is backup";
			$output .= "$carps[$entry]{ip}: BACKUP ";
		}
		else
		{
			verb 1, "Warning, is backup, but should be master";
			$output .= "$carps[$entry]{ip}: CRITICAL - BACKUP ";
			$retval = 2;
		}
	}
	else
	{
		verb 1, "Critical, state is $carps[$entry]{state}";
		$output .= "$carps[$entry]{ip}: CRITICAL: $carps[$entry]{state}";
		$retval = 2;
	}
}

verb 0, "Submitting results";
submit_nsca $retval, $output;
