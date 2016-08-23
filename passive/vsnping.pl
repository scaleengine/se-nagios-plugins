#!/usr/bin/env perl 
use warnings;
use strict;
use Getopt::Std;

###############################################################################
###############################################################################
##                                 vsnping.pl                                ##
## Pings all servers in a given list, and returns each ping as a seperate    ##
## check to nagios via nsca_multiplexer.sh.                                  ##
## Written by Andrew Fengler                                                 ##
###############################################################################
## Copyright (c) 2016, Andrew Fengler <andrew.fengler@scaleengine.com>       ##
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
## V. 1.0.0: Inital version                                         20160426 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
###############################################################################
my $version = '1.0.1';
my $version_date = '2016-07-21';

###############################################################################
## Variables and defaults
###############################################################################

my $count = 4;
my $timeout = 10;
my $warn = 100;
my $crit = 300;
my $hostname = qx(hostname);
chomp $hostname;

my $os = qx(uname);
chomp $os;
my $tflag = ( $os eq 'FreeBSD' ) ? 't' : 'W';
my $prefix = ( $os eq 'FreeBSD' ) ? '/sbin/' : '/bin/';

my $multiplexer = qx(which nsca_vsn_multiplexer.sh);
die "No nsca_multiplexer.sh found in \$PATH\n" if $multiplexer eq "\n";
chomp $multiplexer;

my %opt;
my $servername;
my $losspkt;
my ( $rta_min, $rta_avg, $rta_max );
my ( $losspkt_p, $rta_p );
my $results;
my %data;
my $status;
my $status_human;

###############################################################################
## Subroutine declarations
###############################################################################

sub VERSION_MESSAGE { print "vsnping.pl version $version by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n", exit; }
sub HELP_MESSAGE { print "vsnping.pl [-v] -f conf_file [-w warn] [-c crit] [-t timeout] [-C count] [-H hostname]\n", exit; }

###############################################################################
## Getopts and validation
###############################################################################

getopts 'f:vVht:C:', \%opt;

defined $opt{'V'} and VERSION_MESSAGE;
defined $opt{'h'} and HELP_MESSAGE;

die "Cannot open config file!" unless defined $opt{'f'} and -r $opt{'f'};
open CONF, '<', $opt{'f'};

defined $opt{'w'} and $opt{'w'} =~ /^\d+$/ and $warn = $opt{'w'};
defined $opt{'c'} and $opt{'c'} =~ /^\d+$/ and $crit = $opt{'c'};
defined $opt{'t'} and $opt{'t'} =~ /^\d+$/ and $timeout = $opt{'t'};
defined $opt{'C'} and $opt{'C'} =~ /^\d+$/ and $count = $opt{'C'};
defined $opt{'H'} and $opt{'H'} =~ /^[a-zA-Z0-9\._-]+$/ and $count = $opt{'C'};

$warn = $warn * 1000;
$crit = $crit * 1000;

###############################################################################
## Main program
###############################################################################

#loop through server list
SERVER: while (<CONF>)
{
	( $servername, $losspkt, $rta_min, $rta_avg, $rta_max, $losspkt_p, $rta_p, $results, $status, $status_human ) = (0,0,0,0,0,0,0,0,0,0);
	$servername = $_;
	chomp $servername;
	$results = qx(${prefix}ping -c $count -${tflag} $timeout $servername);
	foreach (split /\n/, $results)
	{
		/([\d\.]+)% packet loss/ and $losspkt = $1;
		/([\d\.]+)\/([\d\.]+)\/([\d\.]+)\/([\d\.]+) ms/ and $rta_min = $1, $rta_avg = $2, $rta_max = $3;
	}
	$losspkt_p = $losspkt =~ s/\.//r;
	$rta_p = $rta_avg =~ s/\.//r;
	print "$rta_p, $losspkt_p\n";

	if ( $rta_p == 0 )
	{
		$data{$servername}{'status'} = 3;
		$data{$servername}{'status_human'} = 'UNKNOWN';
		$data{$servername}{'output'} = $results;
		next SERVER;
	}
	if ( $losspkt_p >= $crit )
	{
		$status = 2;
		$status_human = "CRITICAL";
	}
	elsif ( $losspkt_p >= $warn )
	{
		$status = 1;
		$status_human = "WARNING";
	}
	elsif ( $losspkt_p < $warn )
	{
		$status = 0;
		$status_human = "OK";
	}
	else
	{
		$status = 3;
		$status_human = 'UNKNOWN';
		$data{"$servername"}{"output"} = $results;
		next SERVER;
	}

	$data{$servername}{'status_human'} = $status_human;
	$data{$servername}{'status'} = $status;
	$data{$servername}{'losspkt'} = $losspkt;
	$data{$servername}{'rta_min'} = $rta_min;
	$data{$servername}{'rta_avg'} = $rta_avg;
	$data{$servername}{'rta_max'} = $rta_max;
}

#dump output to multiplexer
open MPLX, "| $multiplexer";

foreach (keys %data)
{
	if ( $data{$_}{'status'} < 3 )
	{
		print MPLX "$hostname\tICMP_$_\t$data{$_}{'status'}\t$data{$_}{'status_human'}: $_ $data{$_}{'losspkt'} lost, $data{$_}{'rta_avg'} RTA |losspkt=$data{$_}{'losspkt'} rta_min=$data{$_}{'rta_min'} rta_avg=$data{$_}{'rta_avg'}  rta_max=$data{$_}{'rta_max'} ;$warn;$crit;;\x17"
	}
	else 
	{
		print MPLX "$hostname\tICMP_$_\t$data{$_}{'status'}\t$data{$_}{'status_human'}: Ping returned - $data{$_}{'output'}\x17";
	}
}

print MPLX "\n";
close MPLX;
