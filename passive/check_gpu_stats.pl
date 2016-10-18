#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Std;

###############################################################################
###############################################################################
##                           check_gpu_stats.pl                              ##
## This check pulls data from nvidia-smi and submits it to nagios            ##
##                                                                           ##
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
## V. 1.0.0: Inital version                                         20160506 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
## V. 1.0.2: Fix to work with cards that have fans (M4000 Quadro)   20160901 ##
## V. 1.1.0: Changed to use nvidia-smi -q, measure encoder util     20160901 ##
## V. 1.1.1: Bugfix - fix -w and -c in getopts                      20160912 ##
###############################################################################
my $version = '1.1.1';
my $version_date = '2016-09-12';

###############################################################################
## Variables and defaults
###############################################################################

my $nvidiasmi = qx(which nvidia-smi);
chomp $nvidiasmi;
my $verbose = 0;
my $hostname = qx(hostname);
my $multiplexer = '/usr/local/bin/nsca_multiplexer.sh';
chomp $hostname;
my $service = 'GPU';
my ( %opt, @wopt, @copt );

my $i = 0;
my $j = 0;
my $rammax; #ram numbers are in the wrong order 
my $ngpus = 0;
my @stats;

my %tot = ( 'temp' => 0, 'pwr' => 0, 'pwr_pct' => 0, 'ram' => 0, 'ram_pct' => 0, 'util' => 0 );
my %avg = ( 'temp' => 0, 'pwr' => 0, 'pwr_pct' => 0, 'ram' => 0, 'ram_pct' => 0, 'util' => 0 );
my %perf = ( 'pwr' => '|', 'temp' => '|', 'ram' => '|', 'util' => '|' );
my %warn = ( 'pwr' => 75, 'temp' => 50, 'ram' => 75, 'util' => 75 );
my %crit = ( 'pwr' => 90, 'temp' => 75, 'ram' => 90, 'util' => 90 );
my %ret = ( 'pwr' => 3, 'temp' => 3, 'ram' => 3, 'util' => 3 );
my @ret_human = ( 'OK', 'WARNING', 'CRITICAL', 'UNKNOWN' );


###############################################################################
## Subroutine declarations
###############################################################################

sub VERSION_MESSAGE { print "get_gpu_stats.pl version $version by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n", exit; }
sub HELP_MESSAGE { print "get_gpu_stats.pl [-v] [-w warnp,warnr,warnt,warnu] [-c critp,critr,critt,critu] [-H hostname] [-S service]\n", exit; }

###############################################################################
## Getopts and validation
###############################################################################

getopts 'f:vVht:C:w:c:', \%opt;
defined $opt{'v'} and $verbose = 1;
defined $opt{'H'} and $hostname = $opt{'H'};
defined $opt{'S'} and $hostname = $opt{'S'};
if ( defined $opt{'w'} )
{
	@wopt = split /,/, $opt{'w'};
	die "Wrong number of parameters for warnings!\n" unless @wopt == 4;
	$warn{'pwr'} = $wopt[0];
	$warn{'ram'} = $wopt[1];
	$warn{'temp'} = $wopt[2];
	$warn{'util'} = $wopt[3];
}
if ( defined $opt{'c'} )
{
	@copt = split /,/, $opt{'c'};
	die "Wrong number of parameters for criticals!\n" unless @copt == 4;
	$crit{'pwr'} = $copt[0];
	$crit{'ram'} = $copt[1];
	$crit{'temp'} = $copt[2];
	$crit{'util'} = $copt[3];
}



###############################################################################
## Main program
###############################################################################

# Retrieve and handle data
my @data = split /\n/, qx($nvidiasmi -q);

for (@data)
{
	#( $temp, $watts_draw, $watts_pct, $ram_used, $ram_pct, $util ) = ('','','','','','');
	if ( /\| (?:N\/A|\d+%).*?(\d+)C.*?(\d+)W \/ (\d+)W.*?(\d+)MiB.*?(\d+)MiB.*?(\d+)%/ )
	{
		$verbose and print STDERR "GPU ${i}: $1 degrees, $2/$3 watts used, $4/$5 MB ram used, $6% utilized\n";
		$stats[$i]{'temp'} = $1;
		$stats[$i]{'pwr'} = $2;
		$stats[$i]{'pwr_pct'} = $2/$3;
		$stats[$i]{'ram'} = $4;
		$stats[$i]{'ram_pct'} = $4/$5;
		$stats[$i]{'util'} = $6;
		$i+=1; 
	}
	/Attached GPUs.*?: (\d+)/ and $i = -1 and $ngpus = $1; #If we find this line, nvidia-smi is running with -q
	/GPU [0-9:\.]+$/ and $i++;
	/GPU Current Temp.*?: (\d+) C/ and $stats[$i]{'temp'} = $1;
	/Power Draw.*?: ([\d\.]+) W/ and $stats[$i]{'pwr'} = $1;
	/Power Limit.*?: ([\d\.]+) W/ and $stats[$i]{'pwr_pct'} = $stats[$i]{'pwr'}/$1;
	/Used.*?: ([\d\.]+) MiB/ and ! defined $stats[$i]{'ram'} and $stats[$i]{'ram'} = $1 and $stats[$i]{'ram_pct'} = $1/$rammax;
	/Total.*?: ([\d\.]+) MiB/ and $rammax = $1;
	/Encoder.*?: ([\d\.]+) %/ and $stats[$i]{'util'} = $1;
}
#if we used -q, $i will be 1 lower than the number of gpus.
$ngpus and $i = $ngpus;

#total
for ( my $j = 0; $j < $i; $j ++ )
{
	$tot{'temp'} += $stats[$j]{'temp'};
	$tot{'pwr'} += $stats[$j]{'pwr'};
	$tot{'pwr_pct'} += $stats[$j]{'pwr_pct'};
	$tot{'ram'} += $stats[$j]{'ram'};
	$tot{'ram_pct'} += $stats[$j]{'ram_pct'};
	$tot{'util'} += $stats[$j]{'util'};

	$perf{'pwr'} .= "gpu${j}=$stats[$j]{'pwr'} ";
	$perf{'temp'} .= "gpu${j}=$stats[$j]{'temp'} ";
	$perf{'ram'} .= "gpu${j}=$stats[$j]{'ram'} ";
	$perf{'util'} .= "gpu${j}=$stats[$j]{'util'} ";
}

#append warn and crit
$perf{'pwr'} .= ";$warn{'pwr'};$crit{'pwr'};;";
$perf{'temp'} .= ";$warn{'temp'};$crit{'temp'};;";
$perf{'ram'} .= ";$warn{'ram'};$crit{'ram'};;";
$perf{'util'} .= ";$warn{'util'};$crit{'util'};;";

#Average
$avg{'temp'} = $tot{'temp'} / $i;
$avg{'pwr'} = $tot{'pwr'} / $i;
$avg{'pwr_pct'} = $tot{'pwr_pct'} / $i;
$avg{'ram'} = $tot{'ram'} / $i;
$avg{'ram_pct'} = $tot{'ram_pct'} / $i;
$avg{'util'} = $tot{'util'} / $i;

#Generate return codes
for my $key (keys %perf)
{
	my $measure = (defined $avg{"${key}_pct"}) ? $avg{"${key}_pct"} : $avg{"$key"};
	$verbose and print STDERR "measure of $key is $measure\n";
	$measure >= $crit{"$key"} and $ret{"$key"} = 2 and next;
	$measure >= $warn{"$key"} and $ret{"$key"} = 1 and next;
	$measure < $warn{"$key"} and $ret{"$key"} = 0 and next;
}

#Truncate decimal places
for my $key (keys %avg)
{
	$avg{"$key"} =~ s/(\d+\.\d\d)\d+/$1/;
}

#debug output of final lines.
$verbose and print join "\t", ${hostname}, "${service}_POWER", $ret{'pwr'}, "$ret_human[$ret{'pwr'}]: average power usage is $avg{'pwr'}W ($avg{'pwr_pct'}%)$perf{'pwr'}\n";
$verbose and print join "\t", ${hostname}, "${service}_TEMP", $ret{'temp'}, "$ret_human[$ret{'temp'}]: average temperature is $avg{'temp'}C$perf{'temp'}\n";
$verbose and print join "\t", ${hostname}, "${service}_MEM", $ret{'ram'}, "$ret_human[$ret{'ram'}]: average memory usage is $avg{'ram'}MB ($avg{'ram_pct'}%)$perf{'ram'}\n";
$verbose and print join "\t", ${hostname}, "${service}_UTIL", $ret{'util'}, "$ret_human[$ret{'util'}]: average GPU utilization is $avg{'util'}%$perf{'util'}\n";

#printout
open MX, "| $multiplexer";

# 0x17 (VTB) is the seperator to submit multiple checks to NSCA
print MX join "\t", ${hostname}, "${service}_POWER", $ret{'pwr'}, "$ret_human[$ret{'pwr'}]: average power usage is $avg{'pwr'}W ($avg{'pwr_pct'}%)$perf{'pwr'}\n\x17";
print MX join "\t", ${hostname}, "${service}_TEMP", $ret{'temp'}, "$ret_human[$ret{'temp'}]: average temperature is $avg{'temp'}C$perf{'temp'}\n\x17";
print MX join "\t", ${hostname}, "${service}_MEM", $ret{'ram'}, "$ret_human[$ret{'ram'}]: average memory usage is $avg{'ram'}MB ($avg{'ram_pct'}%)$perf{'ram'}\n\x17";
print MX join "\t", ${hostname}, "${service}_UTIL", $ret{'util'}, "$ret_human[$ret{'util'}]: average GPU utilization is $avg{'util'}%$perf{'util'}\n";

close MX;
