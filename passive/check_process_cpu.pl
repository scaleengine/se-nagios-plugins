#!/usr/bin/env perl
use warnings;
use strict;

use JSON;
use Getopt::Std;
use Data::Dumper;
use POSIX qw(sysconf);

###############################################################################
###############################################################################
##                           check_proc_cpu.pl                               ##
## Checks the cpu usage of a named process.                                  ##
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
## V. 1.0.0: Initial release                                        20181005 ##
## V. 1.0.1: Round off perfdata since nagiosgraph can't use DDERIVE 20181012 ##
## V. 1.1.0: Add linux support with /proc                           20190228 ##
###############################################################################
my $version = '1.1.0';
my $version_date = '2019-02-28';


###############################################################################
## Global variables
###############################################################################

my %opt;
my %conf = (
	debug 			=> 0,
	service			=> 'PROC_CPU',
	hostname		=> qx(hostname).'',
	multiplexer		=> qx(which nsca_multiplexer.sh).'',
	crit			=> 100,
	warn			=> 10, 
	program			=> '',
	tmpdir			=> '/var/tmp/',
	file			=> '',
	sudo			=> '',
	clk_tck			=> 100,
);
chomp $conf{hostname};
chomp $conf{multiplexer};

my $ret = 3;
my $pids;
my ( $oldutime, $oldstime );
my $utime = 0;
my $stime = 0;
my $delta = 0;
my $data;
my $rawdata;


###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n$0 [-v|-d] -P process_name [-w warn] [-c crit] [-s service] [-S]\n";
	print "\t-v         Verbose.\n";
	print "\t-d         Debug.\n";
	print "\t-P name    The name of the process to check\n";
	print "\t-w warn    The number of cpu seconds in one check interval to warn on\n";
	print "\t-c crit    The number of cpu seconds in one check interval to critical on\n";
	print "\t-s service The service name to report to nagios\n";
	print "\t-S         Run pgrep and procstat with sudo\n";
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

sub report ($$@)
{
	#Args: return code, output text, perfdata
	my $ret = shift;
	my $text = shift;
	my @perf = @_;
	my $perfstring = '|';
	my $prefix;

	$ret == 0 and $prefix = 'OK: ';
	$ret == 1 and $prefix = 'WARN: ';
	$ret == 2 and $prefix = 'CRIT: ';
	$ret == 3 and $prefix = 'UNKNOWN: ';

	for my $p (@perf)
	{
		$perfstring .= ' '.$p.";;;;";
	}
	
	#printout
	print join "\t", $conf{hostname}, $conf{service}, $ret, $prefix.$text.$perfstring."\n";
	open MX, '|-', $conf{multiplexer} or return $!;
	print MX join "\t", $conf{hostname}, $conf{service}, $ret, $prefix.$text.$perfstring."\n";
	close MX;
	return 0;
}

sub str2sec ($)
{
	my $days = 0;
	my @bits;
	my $rawtime;
	my $result = -1;
	my $input = $_[0];

	#"user time": "00:00:00.000000",
	#"system time": "4 days 10:44:26.594162",
	if ( $input =~ /^(\d+ days? )?([\d:.]+)$/ )
	{
		if ( defined $1 and $1 )
		{
			$days = $1 =~ s/^(\d+).*$/$1/r
		}
		$rawtime = $2;
		 
		verb 1, "Working with:", $days, "days and", $rawtime, "raw";
		@bits = split /:/, $rawtime;
		$result = (((((( $days * 24 ) + $bits[0] ) * 60 ) + $bits[1] ) * 60  ) + $bits[2] );
		verb 1, "Got result:", $result;
	}
	else
	{
		verb 0, "ERROR: could not get time from input:", $input;
	}
	return $result;
}
	

##############################################################################
## Getopts
##############################################################################

getopts 'hvVdSw:c:P:s:', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;

defined $opt{w} and $conf{warn} = $opt{w};
defined $opt{c} and $conf{crit} = $opt{c};

defined $opt{s} and $conf{service} = $opt{s};
defined $opt{S} and $conf{sudo} = 'sudo ';

defined $opt{P} ? $conf{program} = $opt{P} : die "No process name was given!\n";
$conf{file} = $conf{tmpdir}.$conf{program}.'_cputime.tmp';
verb 1, "Got args";


##############################################################################
## Main program
##############################################################################

verb 1, "Get pids of", $conf{program};
verb 2, "cmd: ($conf{sudo}pgrep $conf{program})";
$pids = qx($conf{sudo}pgrep $conf{program});
$pids =~ s/\n/ /g;
verb 1, "Pids are:", $pids;

if ( qx(uname) =~ /FreeBSD/ )
{
	verb 1, "Getting data...";
	verb 2, "cmd: ($conf{sudo}procstat --libxo json -r ${pids})";
	$rawdata = qx($conf{sudo}procstat --libxo json -r ${pids});
	$rawdata =~ s/\n//g;
	$data = decode_json($rawdata);
	verb 1, "...Done";
	verb 2, Dumper $data;

	for my $pid (sort keys %{$data->{procstat}{rusage}})
	{
		my ( $utime_p, $stime_p );
		#get current time counter:
		$utime_p = str2sec($data->{procstat}{rusage}{$pid}{'user time'});
		$utime_p and $utime += $utime_p;
		$stime_p = str2sec($data->{procstat}{rusage}{$pid}{'system time'});
		$stime_p and $stime += $stime_p;
		verb 1, "Got times for process:", $pid, $stime_p, $utime_p;
	}
}
else
{
	for my $pid (split / /, $pids)
	{
		my ( $utime_p, $stime_p, @statline );
		$conf{clk_tck} = POSIX::sysconf(POSIX::_SC_CLK_TCK());
		verb 2, "Tick rate:", $conf{clk_tck};
		open FH, '<', '/proc/'.$pid.'/stat';
		@statline = split(' ', readline(FH));
		$utime_p = $statline[13] / $conf{clk_tck};
		$utime_p and $utime += $utime_p;
		$stime_p = $statline[14] / $conf{clk_tck};
		$stime_p and $stime += $stime_p;
		verb 1, "Got times for process:", $pid, $stime_p, $utime_p;
	}
}

#get old times:
if ( -e $conf{file} )
{
	verb 1, "Read in saved times from file";
	open FH, '<', $conf{file} or die "Could not open tmp file for reading: $!\n";
	while (<FH>)
	{
		/^utime: ([\d\.]+)$/ and $oldutime = $1;
		/^stime: ([\d\.]+)$/ and $oldstime = $1;
	}
}
else
{
	verb 1, "No saved times, counting from 0";
	$oldutime = 0;
	$oldstime = 0;
}
verb 1, "Got old times:", $oldutime, $oldstime;
verb 1, "Writing times to file...";
#write current times to file
open FH, '>', $conf{file} or die "Could not open tmp file for writing $!\n";
print FH "utime: ${utime}\n";
print FH "stime: ${stime}\n";
close FH;
verb 1, "...Done";

$delta = $utime - $oldutime + $stime - $oldstime;
verb 1, "Compare: ${delta};$conf{warn};$conf{crit};;";

if ( $delta >= $conf{crit} )
{
	$ret = 2;
}
elsif ( $delta >= $conf{warn} )
{
	$ret = 1;
}
else
{
	$ret = 0;
}
#round off for perfdata
$utime =~ s/^(\d+)(?:\.\d+)$/$1/;
$stime =~ s/^(\d+)(?:\.\d+)$/$1/;

report($ret, "CPU used by $conf{program} was ${delta}s", "utime=${utime}c", "stime=${stime}c");
