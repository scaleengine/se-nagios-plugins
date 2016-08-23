#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Std;

###############################################################################
###############################################################################
##                      check_network_status.pl                              ##
## Nagios plugin to check network speed for a given NIC                      ##
## Uses binaries from Net-SNMP                                               ##
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
## Changelog:                                                                ##
## V. 1.0.0: Initial version                                        20160418 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
## V. 1.0.2: Add 'verb' sub for debug lines                         20160822 ##
###############################################################################
## Todo:                                                                     ##
## Consider adapting to use Net::SNMP                                        ##
###############################################################################
my $version = '1.0.2';
my $version_date = '2016-08-22';

###############################################################################
## Global Variables
###############################################################################

my $snmptable = qx(which snmptable);
chomp $snmptable;
$snmptable !~ /\s/ or $snmptable = '/usr/local/bin/snmptable';

my $oid = '1.3.6.1.2.1.2.2';

my %opt;
my $hostname;
my $nic;
my $community = 'public';
my $id = 0;
my $data;
my @table;
my $verbose = 0;
my $speed;
my $warn = 1; #Warn does nothing.
my $crit = 1000; #1 Gb/s by default.

###############################################################################
## Subroutines
###############################################################################

sub HELP_MESSAGE
{
	print "Usage: $0 [-v] -H hostname -N nic [-C snmp_community] [-w warn] [-c crit]\n";
	exit 0;
}

sub VERSION_MESSAGE
{
	print "$0 version $version by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n";
	exit 0;
}

sub verb
{
	local $, = ' ';
	local $\ = "\n";
	shift @_ <= $verbose and print STDERR @_;
	return 1;
}

###############################################################################
## Getopts
###############################################################################

getopts 'H:N:C:w:c:vVh', \%opt;

defined $opt{'H'} and $hostname = $opt{'H'};
defined $opt{'N'} and $nic = $opt{'N'};
defined $opt{'C'} and $community = $opt{'C'};
defined $opt{'v'} and $verbose = 1;
defined $opt{'c'} and $crit = $opt{'c'};
defined $opt{'w'} and $warn = $opt{'w'};

HELP_MESSAGE unless defined $opt{'H'} and defined $opt{'N'};


###############################################################################
## Main Program
###############################################################################

verb 1, "fetching SNMP data";
$data = qx( $snmptable -Cf '#' -CH -v 2c -c $community $hostname $oid);
verb 1, "Data: \n$data\n";

foreach my $line (split /\n/, $data)
{
	my @tmp = split /#/, $line;
	push @table, \@tmp; 
}

for ( $id = 0; $id < @table; $id ++ ) 
{ 
	verb 1, "Compare nic = $nic to table[id][1] = $table[$id][1]";
	if ("$nic" eq "$table[$id][1]") 
	{
		$speed = $table[$id][4] / 1000000;
		verb 1, "Found NIC in entry $id: $table[$id][1]";
		if ( $speed >= $crit )
		{
			print "OK: Link $nic speed is $speed Mb/s | speed=$table[$id][4] ;$warn;$crit;;\n";
			exit 0;
		}
		elsif ( $speed < $crit )
		{
			print "CRITICAL: Link $nic speed is $speed Mb/s | speed=$table[$id][4] ;$warn;$crit;;\n";
			exit 2;
		}
	}
}

print "UNKNOWN: NIC $nic could not be found | speed=0 ;$warn;$crit;;\n";
exit 3;
