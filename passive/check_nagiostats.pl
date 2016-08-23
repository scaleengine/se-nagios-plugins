#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Std;

###############################################################################
###############################################################################
##                        check_nagiostats.pl                                ##
## Nagios plugin to check nagiostats output.                                 ##
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
## Changelog:                                                                ##
## V. 1.0.0: Initial version                                        20160318 ##
## V. 1.1.0: Removed extra 'perfdata:', increased window to 15 min  20160318 ##
## V. 1.2.0: Set percentages to round off to 2 decimal places       20160318 ##
## V. 1.2.1: Removed eroneous spaces in output string               20160318 ##
## V. 1.2.2: Publish under ISC license                              20160721 ##
###############################################################################
my $version = '1.2.2';
my $version_date = '2016-07-21';

###############################################################################
## Global variables
###############################################################################

my $columns = 'AVGACTSVCLAT,AVGPSVSVCLAT,NUMSERVICES,NUMSVCPROB,NUMSVCUNKN,NUMSVCACTCHK15M,NUMSVCPSVCHK15M';
my $svc_desc = 'NAGIOS_STATS';
my $output = '';
my $warn = 5;
my $crit = 10;
my $alert_on = 'checked';
my $nagiostats = '/usr/local/bin/nagiostats';
my %arg = ();
my $verbose = 0;
my @out = ();
my %stats = ();
my $retval = 3;
my $multiplexer = '/usr/local/bin/nsca_multiplexer.sh';
my $hostname = '';
my $perfdata = '';
my $message = '';
my $measure = '';

###############################################################################
## Subroutines
###############################################################################

sub HELP_MESSAGE 
{
	print "check_nagiostats.pl:\nSubmits a passive check via nsca_multiplexer.sh containing nagios stats>\n\n\tUsage:\n\tcheck_nagiostats.pl [-v] [-S service] [-w warn] [-c crit] \n\t\t[-o check_on] [-b nagiostats] [-m nsca_multiplexer.sh] [-H hostname]\n\n";
	exit;
}

sub VERSION_MESSAGE 
{
	print "check_nagiostats.pl, version $version  Written 2016-03-10 by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n";
	exit;
}

sub generate_retval 
{
	#Generate a return code
	my $state = '';
	my $exit = 3;
	my $text = '';
	my $type = $_['0'];
	my $w = $_['1'];
	my $c = $_['2'];
	my $stats_ref = $_['3'];

	if ( $alert_on eq 'latency' ) 
	{ 
		$state = ${$stats_ref}{'alat'}; 
		$text = "average service check latency was ${$stats_ref}{'alat'}";
	}
	elsif ( $alert_on eq 'status' ) 
	{ 
		$state = ( ${$stats_ref}{'psvc'} * 100 / ${$stats_ref}{'nsvc'} ); 
		$state = sprintf "%.2f", $state;
		$text = "Problems were found in ${$stats_ref}{'psvc'} out of ${$stats_ref}{'nsvc'} checks ($state%)";
	}
	elsif ( $alert_on = 'checked' ) 
	{ 
		$state = (( ${$stats_ref}{'nsvc'} - ${$stats_ref}{'achk'} - ${$stats_ref}{'pchk'} ) * 100 / ${$stats_ref}{'nsvc'} ); 
		$state = sprintf "%.2f", $state;
		$text = "In the last 15 minutes there were ${$stats_ref}{'achk'} active and ${$stats_ref}{'pchk'} passive checks ($state% not checked)";
	}

	$state >= $w and $state < $c and $exit = 1, $text = "WARNING: $text";
	$state >= $c and $exit = 2, $text = "CRITICAL: $text";
	$state < $w and $exit = 0, $text = "OK: $text";

	return $exit, $text, $state;
}

sub generate_perfdata
{
	#Create the output text
	my $exit = '';
	my $w = $_['0'];
	my $c = $_['1'];
	my $m = $_['2'];
	my $stats_ref = $_['3'];
	
	$exit = "|alat=${$stats_ref}{'alat'}ms plat=${$stats_ref}{'plat'}ms nsvc=${$stats_ref}{'nsvc'} psvc=${$stats_ref}{'psvc'} usvc=${$stats_ref}{'usvc'} achk=${$stats_ref}{'achk'} pchk=${$stats_ref}{'achk'} measure=$m ;$w;$c;;";

	return $exit;
}

###############################################################################
## Getopts
###############################################################################

getopts 'vhVS:w:c:o:b:m:H:', \%arg;

defined $arg{'h'} and $arg{'h'} eq 1 and HELP_MESSAGE;
defined $arg{'V'} and $arg{'V'} eq 1 and VERSION_MESSAGE;
defined $arg{'v'} and $arg{'v'} eq 1 and $verbose = 1;
defined $arg{'S'} and $arg{'S'} and $svc_desc = $arg{'S'};
defined $arg{'w'} and $arg{'w'} =~ /^\d+$/ and $warn = $arg{'w'};
defined $arg{'c'} and $arg{'c'} =~ /^\d+$/ and $crit = $arg{'c'};
defined $arg{'o'} and $arg{'o'} =~ /^(?:checked)|(?:latency)|(?:status)$/ and $alert_on = $arg{'o'};
defined $arg{'b'} and -x $arg{'b'} and $nagiostats = $arg{'b'};
defined $arg{'m'} and -x $arg{'m'} and $multiplexer = $arg{'m'};
$hostname = ( defined $arg{'H'} and $arg{'H'} =~ /^[A-Za-z0-9\-\.]+?\.[A-Za-z]+?$/ )? $arg{'H'} : qx(hostname);
chomp $hostname;


###############################################################################
## Main Program
###############################################################################

@out = split /;/, qx(${nagiostats} -m -D ';' -d ${columns});
%stats = (
	'alat' 	=> $out[0],
	'plat'	=> $out[1],
	'nsvc'	=> $out[2],
	'psvc'	=> $out[3] - $out[4],
	'usvc'	=> $out[4],
	'achk'	=> $out[5],
	'pchk'	=> $out[6]
);

($retval, $message, $measure) = generate_retval $alert_on, $warn, $crit, \%stats;
$perfdata = generate_perfdata $warn, $crit, $measure, \%stats;

print join "\t", $hostname, $svc_desc, $retval, "${message} ${perfdata}\n" if $verbose > 0;

open MX, "| $multiplexer" or die "Unable to access multiplexer!\n";
print MX join "\t", $hostname, $svc_desc, $retval, "${message} ${perfdata}\n";
#printf MX "%s\t%s\t%s\t%s\n", $hostname, $svc_desc, $retval, "${message}${perfdata}";
