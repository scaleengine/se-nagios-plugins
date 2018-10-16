#!/usr/bin/env perl
use warnings;
use strict;

use Getopt::Std;

###############################################################################
###############################################################################
##                           check_java_threads.pl                           ##
## Checks the state of the threads of a named java process using jstack      ##
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
## V. 1.0.0: Initial release                                        20181015 ##
## V. 1.0.1: Add timout and skip own pid                            20181016 ##
###############################################################################
my $version = '1.0.1';
my $version_date = '2018-10-16';


###############################################################################
## Global variables
###############################################################################

my %opt;
my %conf = (
	debug 			=> 0,
	service			=> 'JAVA_THREADS',
	hostname		=> qx(hostname).'',
	multiplexer		=> qx(which nsca_multiplexer.sh).'',
	crit			=> 10,
	warn			=> 2, 
	program			=> '',
	tmpdir			=> '/var/tmp/',
	file			=> '',
	sudo			=> '',
	timeout			=> 60,
);
chomp $conf{hostname};
chomp $conf{multiplexer};

my $ret = 3;
my $pids;
my %data = (
	blocked			=> 0,
	runnable		=> 0,
	waiting			=> 0,
	timed_waiting	=> 0,
);


###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n$0 [-v|-d] -P process_name [-w warn] [-c crit] [-s service] [-S] [-t timeout]\n";
	print "\t-v         Verbose.\n";
	print "\t-d         Debug.\n";
	print "\t-P name    The name of the process to check\n";
	print "\t-w warn    The number of threads to warn on\n";
	print "\t-c crit    The number of threads to critical on\n";
	print "\t-s service The service name to report to nagios\n";
	print "\t-S         Run pgrep and jstack with sudo\n";
	print "\t-t timeout Timout in seconds\n";
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

sub report ($$;@)
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


##############################################################################
## Signal handlers
##############################################################################

%SIG = (
	ALRM	=> sub {
		verb 1, "Timeout reached!";
		report(3, "Check timed out");
		exit;
	},
);

##############################################################################
## Getopts
##############################################################################

getopts 'hvVdSw:c:P:s:t:', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;

defined $opt{w} and $conf{warn} = $opt{w};
defined $opt{c} and $conf{crit} = $opt{c};

defined $opt{s} and $conf{service} = $opt{s};
defined $opt{S} and $conf{sudo} = 'sudo ';
defined $opt{t} and $conf{timeout} = $opt{t};

defined $opt{P} ? $conf{program} = $opt{P} : die "No process name was given!\n";
$conf{file} = $conf{tmpdir}.$conf{program}.'.stack';
verb 1, "Got args";


##############################################################################
## Main program
##############################################################################

verb 1, "Setting alarm for $conf{timeout} seconds";
alarm $conf{timeout};

verb 1, "Get pids of", $conf{program};
verb 2, "cmd: ($conf{sudo}pgrep -f $conf{program})";
$pids = qx($conf{sudo}pgrep -f $conf{program});
$pids =~ s/\n/ /g;
verb 1, "Pids are:", $pids;

for my $pid (split ' ', $pids)
{
	verb 1, "Check pid $pid against perl pid $$";
	$pid == $$ and next;
	verb 1, "Get stack dump for pid $pid";
	verb 2, "cmd: ($conf{sudo}jstack -l $pid > $conf{file})";
	qx($conf{sudo}jstack -l $pid > $conf{file});
	if ( $? == 0 )
	{
		open FH, '<', $conf{file} or report(3, "Unable to read stack file!");
		while (readline FH)
		{
			/java\.lang\.Thread\.State:\sBLOCKED/ and $data{blocked} ++;
			/java\.lang\.Thread\.State:\sRUNNABLE/ and $data{runnable} ++;
			/java\.lang\.Thread\.State:\sWAITING/ and $data{waiting} ++;
			/java\.lang\.Thread\.State:\sTIMED_WAITING/ and $data{timed_waiting} ++;
		}
		close FH;
	}
	else
	{
		report(3, "Could not find a pid for java!  Exit: $?");
	}
}

verb 1, "Compare: $data{blocked};$conf{warn};$conf{crit};;";
if ( $data{blocked} >= $conf{crit} )
{
	$ret = 2;
}
elsif ( $data{blocked} >= $conf{warn} )
{
	$ret = 1;
}
else
{
	$ret = 0;
}

report($ret, "Java running, $data{runnable} running, $data{blocked} blocked", "blocked=$data{blocked}", "runnable=$data{runnable}", "waiting=$data{waiting}", "timed_waiting=$data{timed_waiting}");

