#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Std;

###############################################################################
###############################################################################
##                          check_rpdu_load.pl                               ##
## Nagios plugin to check power load on an APC rPDU                          ##
## Uses snmpget and snmpwalk from net-snmp                                   ##
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
my $version = '1.0.2';
my $version_date = '2016-08-22';

###############################################################################
## Variable declaration                                                      ##
###############################################################################
my $snmpwalk = qx(which snmpwalk);
chomp $snmpwalk;
$snmpwalk !~ /\s/ or $snmpwalk = '/usr/local/bin/snmpwalk';

my $snmpget = qx(which snmpget);
chomp $snmpget;
$snmpget !~ /\s/ or $snmpget = '/usr/local/bin/snmpget';

my $oid_main_load = '1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.1';
my $oid_outlet_status_table = '1.3.6.1.4.1.318.1.1.12.3.5.1.1.7';

my %opt;
my $host;
my $community = 'public';

my @data;
my @table;
my $total_load_raw;
my $total_load;
my $total_load_amps;

my $id = 0;
my $verbose = 0;
my $warn = 10;
my $crit = 15;
my $perfdata;
my $port;


###############################################################################
## Subroutine declaration                                                    ##
###############################################################################
sub HELP_MESSAGE
{
	print "Usage: $0 [-v] -H host [-C snmp_community] [-w warn] [-c crit]\n";
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
## Getopts                                                                   ##
###############################################################################
getopts 'H:C:w:c:vVh', \%opt;

defined $opt{'H'} and $host = $opt{'H'};
defined $opt{'C'} and $community = $opt{'C'};
defined $opt{'v'} and $verbose = 1;
defined $opt{'c'} and $crit = $opt{'c'};
defined $opt{'w'} and $warn = $opt{'w'};
defined $opt{'V'} and VERSION_MESSAGE;
defined $opt{'h'} and HELP_MESSAGE;

HELP_MESSAGE unless defined $opt{'H'};


###############################################################################
## Get data out of SNMP, exit unknown if unable to.                          ##
###############################################################################
verb 1, "fetching SNMP data";
@data = qx( $snmpwalk -v 2c -c $community $host $oid_outlet_status_table );
unless (@data) { print 'UNKNOWN: unable to talk to host\n'; exit 3; }
$total_load_raw = qx( $snmpget -v 2c -c $community $host $oid_main_load );
unless (defined $total_load_raw) { print 'UNKNOWN: unable to talk to host\n'; exit 3; }
chomp $total_load_raw;
verb 1, "Data:\n$total_load_raw\n", join '\n', @data, "\n";


###############################################################################
## Parse and handle data                                                     ##
###############################################################################
$total_load = $total_load_raw =~ s/.*?(\d+)$/$1/r;
verb 1, "Parsed total load: $total_load";
$total_load_amps = $total_load / 10;
foreach (@data)
{
	/.*?(\d+)$/;
	push @table, $1;
}

$perfdata = '|';
for ( $id = 0; $id < @table; $id ++ ) 
{ 
	$port = $id + 1;
	verb 1, "Append load for port $port to perfdata string: table[id] = $table[$id]";
	$perfdata = "$perfdata port${port}=$table[$id]";
}
$perfdata = "$perfdata total_load=${total_load} ;${warn};${crit};;";


###############################################################################
## Print output and status                                                   ##
###############################################################################
if ( $total_load_amps >= $crit )
{
	print "CRITICAL: Total load is ${total_load_amps}A $perfdata\n";
	exit 2;
}
elsif ( $total_load_amps >= $warn )
{
	print "WARNING: Total load is ${total_load_amps}A $perfdata\n";
	exit 1;
}
elsif ( $total_load_amps < $warn )
{
	print "OK: Total load is ${total_load_amps}A $perfdata\n";
	exit 0;
}

print "UNKNOWN: Total load is ${total_load_amps}A $perfdata\n";
exit 3;
