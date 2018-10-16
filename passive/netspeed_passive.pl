#!/usr/bin/env perl
use warnings;
use strict;

use Data::Dumper;
use Getopt::Std;

###############################################################################
###############################################################################
##                         netspeed_passive.pl                               ##
## Check the speed of an interface.  If it's an LACP interface, or a vlan on ##
## top of an LACP interface, aggregate the speeds of the slaves              ##
## Uses nsca_multiplexer.sh                                                  ##
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
## V. 1.0.0: Initial release                                        20170117 ##
## V. 1.0.1: Fix regexes for non-autoselect interfaces              20170120 ##
## V. 1.0.2: Remove push on reference - deprecated                  20170626 ##
## V. 1.0.3: Fix regex for new FreeBSD versions                     20170721 ##
## V. 1.0.4: Fix regex for drivers that use the wrong case          20170814 ##
## V. 1.0.5: Ensure laggports are marked ACTIVE                     20170831 ##
###############################################################################
## TODO: input validation                                                    ##
## TODO: check status reported by ifconfig/ethtool                           ##
## TODO: Failover interfaces will always show as having a slave down         ##
###############################################################################
my $version = '1.0.5';
my $version_date = '2017-08-31';


###############################################################################
## Global variables
###############################################################################

my %conf = (
	service		=> 'NET_SPEED',
	warn		=> 1000,
	crit		=> 1000,
);
my %opt;
my $hostname = qx(hostname);
chomp $hostname;
my $os = qx(uname);
chomp $os;
my $ifconfig = qx(which ifconfig);
chomp $ifconfig;
my $multiplexer = qx(which nsca_multiplexer.sh);
chomp $multiplexer;
my @lines;
my $int;
my %interface;
my $tmp;

###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] [-s service] [-w warn] [-c crit] -i interface\n";
	exit;
}

sub VERSION_MESSAGE
{
	print "$0 version $version by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n";
	exit;
}

sub verb
{
	local $, = ' ';
	local $\ = "\n";
	shift @_ <= $conf{debug} and print STDERR @_;
	return 1;
}

sub message ($$)
{
	my $retval = $_[0];
	my $message = $_[1];

	open MX, '|-', $multiplexer;
	printf MX "%s\t%s\t%s\t%s\n", $hostname, $conf{service}, $retval, $message;
	verb 1, sprintf ( "%s\t%s\t%s\t%s\n", $hostname, $conf{service}, $retval, $message );
	close MX;
}

sub speed_check ($)
{
	my $speed = $_[0];
	my $message = "Interface $conf{int} operating at $speed Mb/s";
	my $state = 3;
	my $state_m = 'UNKNOWN: ';
	verb 1, "Checking speed $speed...";

	if ( $speed < $conf{crit} )
	{
		verb 1, "CRITICAL";
		$state = 2;
		$state_m = "CRITICAL: ";
	}
	elsif ( $speed < $conf{warn} )
	{
		verb 1, "WARNING";
		$state = 1;
		$state_m = "WARNING: ";
	}
	else
	{
		verb 1, "OK";
		$state = 0;
		$state_m = "OK: ";
	}

	if ( $interface{$conf{int}}{slavestate} == 2 )
	{
		$message .= " - Slave is down";
		$state = 2;
		$state_m = "CRITICAL: ";
	}
	elsif ( $interface{$conf{int}}{slavestate} == 1 )
	{
		$message .= " - Slave is below warning speed";
		if ( $interface{$conf{int}}{slavestate} > $state )
		{
			$state = 1;
			$state_m = "WARNING: ";
		}
	}

	message ( $state, $state_m . $message );
}

sub total (@)
{
	my $speed = 0;
	my $warn = 0;
	verb 1, "Summarizing interfaces:", @_;
	for (@_)
	{
		if ( defined $interface{$_}{speed} )
		{
			verb 1, "Adding speed of slave $_: $interface{$_}{speed}";
			$speed += $interface{$_}{speed};
			if ( $interface{$_}{speed} < $conf{warn} )
			{
				$warn = 1;
				verb 1, "Warning: slave $_ speed is below warn of $conf{warn}";
			}
		}
		else
		{
			$warn = 2;
			verb 1, "Critical: slave $_ speed not found";
		}
	}

	verb 1, "Total speed: $speed";
	return $speed, $warn;
}

##############################################################################
## Getopts
##############################################################################

getopts 'hvVdi:w:c:s:', \%opt;

defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;
defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;
$conf{debug} and print STDERR "parse.pl: read %conf from STDIN\n";

defined $opt{w} and $conf{warn} = $opt{w};
defined $opt{c} and $conf{crit} = $opt{c};
defined $opt{i} and $conf{int} = $opt{i};
defined $opt{s} and $conf{service} = $opt{s};

defined $conf{int} or die "An interface must be provided\n";


##############################################################################
## Main program
##############################################################################

# If we're linux, use ethtool:
if ( $os eq 'Linux' )
{
	@lines = qx(ethtool $conf{int});
	for (@lines)
	{
		/Speed: (\d+)Mb\/s/ and $interface{$conf{int}}{speed} = $1;
		verb 1, "Found speed for $conf{int}: $_";
		#TODO: check status
	}

	if ( defined $interface{$conf{int}}{speed} )
	{
		speed_check ( $interface{$conf{int}}{speed} );
		exit;
	}
	else
	{
		die "Could not find a speed for $conf{int}\n";
	}	
}

# Get interface information
@lines = qx($ifconfig -a);
$int = "NONE";

for (@lines)
{
	if ( /^([a-zA-Z0-9]*?):/ )
	{
		$int = $1;
		$interface{$int}{speed} = '';
		$interface{$int}{status} = '';
		$interface{$int}{slavestate} = 0;
		$interface{$int}{parent} = '';
		$interface{$int}{slave} = [];
		verb 1, "Found interface: $int";
	}
	elsif ( /media: Ethernet (?:autoselect .*?\()?(\d+)G[bB]ase/ )
	{
		#10Gb interfaces report as '10Gbase...'
		$interface{$int}{speed} = ( $1 * 1000 );
		verb 1, "$int speed is ${1}G";
	}
	elsif ( /media: Ethernet (?:autoselect .*?\()?(\d+)[bB]ase/ )
	{
		$interface{$int}{speed} = $1;
		verb 1, "$int speed is $1";
	}
	elsif ( /status: (.*?)/ )
	{
		$interface{$int}{status} = $1;
		verb 1, "$int status is $1";
	}
	elsif ( /vlan: \d+ parent interface: ([a-zA-Z0-9]+)/ )
	{
		#vlan: 43 parent interface: lagg0
		$interface{$int}{parent} = $1;
		verb 1, "$int parent is $1";
	}
	elsif ( /laggport: ([a-zA-Z0-9]+) flags=.*?<(.*?)>/ )
	{
		$tmp = $1;	
		if ( $2 =~ /ACTIVE/ )
		{
			verb 1, "$int slave is $tmp";
			push @{$interface{$int}{slave}}, $tmp;
		}
	}
}

if ( $conf{debug} )
{
	printf "%20s%20s%20s%20s%20s\n", 'Interface', 'Status', 'Speed', 'Parent', 'Slave';
	for ( keys %interface )
	{
		printf "%20s%20s%20s%20s%20s\n", $_, $interface{$_}{status}, $interface{$_}{speed}, $interface{$_}{parent}, join ( ',', @{$interface{$_}{slave}} ) ;
	}
}


#Check informatin for our interface

if ( ! defined $interface{$conf{int}} )
{
	message ( 3, "Interface $conf{int} not found!" );
	exit;
}

# Look for parents of a lacp interface
if ( scalar @{$interface{$conf{int}}{slave}} )
{
	verb 1, "Found LACP interface";
	 ( $interface{$conf{int}}{speed}, $interface{$conf{int}}{slavestate} ) = total ( @{$interface{$conf{int}}{slave}} );
}

# Look to see if we're a vlan on top of an LACP interface
if ( $interface{$conf{int}}{parent} ne '' and scalar @{$interface{$interface{$conf{int}}{parent}}{slave}} )
{
	verb 1, "Found VLAN on top of LACP interface";
	( $interface{$conf{int}}{speed}, $interface{$conf{int}}{slavestate} ) = total ( @{$interface{$interface{$conf{int}}{parent}}{slave}} )
}

#TODO: check status

if ( defined $interface{$conf{int}}{speed} )
{
	#it's just a single interface
	speed_check ( $interface{$conf{int}}{speed} );
	exit;
}

