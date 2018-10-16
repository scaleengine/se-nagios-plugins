#!/usr/bin/env perl
use warnings;
use strict;

use Getopt::Std;

###############################################################################
###############################################################################
##                           check_mdadm.pl                                  ##
## Checks health of mdadm devices                                            ##
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
## V. 1.0.0: Initial release                                        20160913 ##
## V. 1.0.1: Fix to handle resyncing arrays.                        20161031 ##
###############################################################################
my $version = '1.0.1';
my $version_date = '2016-10-31';


###############################################################################
## Global variables
###############################################################################

my %conf;
my %opt;
my %mds;

my $ret;
$conf{service} = 'MDADM';
my @retlabel = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN');

$conf{hostname} = qx(hostname);
chomp $conf{hostname};
my $multiplexer = qx(which nsca_multiplexer.sh);
chomp $multiplexer;

# mdadm
# my $mdadm = qx(which mdadm);
# chomp $mdadm;
# $mdadm .= ' --detail';
my $mdadm = 'sudo /usr/local/bin/mdinfo';
# Using mdadm directly will only work as root, see bottom of file for mdinfo

my $output = '';
my $perf = '';
my $default_output = " MD devices are healthy";

$conf{debug} = 0;

###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] [-s service] [-H hostname]\n";
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

sub parse_opts
{
	defined $opt{h} and HELP_MESSAGE;
	defined $opt{V} and VERSION_MESSAGE;

	defined $opt{v} and $conf{debug} = 1;
	defined $opt{d} and $conf{debug} = 2;
	$conf{debug} and print STDERR "read %conf from args\n";

	defined $opt{s} and $conf{service} = $opt{s};
	defined $opt{H} and $conf{hostname} = $opt{H};
}

sub getstatus
{
	my $out;
	my $md;
	verb 1, "Begining search for MD devices";
	opendir DEV, '/dev' or die "can't open /dev!  Error is: $!\n";
	while (readdir DEV)
	{
		verb 2, "Found device: $_";
		/^md\d+$/ or next;
		verb 1, "Device $_ matches";
		$mds{$_}{name} = $_;
	}
	verb 1, "Finished search, begin probing";
	for $md (keys %mds)
	{
		$mds{$md}{state} = '';
		verb 1, "Get detail for md device $md";
		verb 2, "$mdadm --detail /dev/$md";
		$out = qx($mdadm /dev/$md);
		for (split /\n/, $out)
		{
			verb 2, "Line: $_";
			/State : ([A-Za-z]+)(, resyncing)?[\s].?$/ and $mds{$md}{state} = $1 and verb 1, "Found state: $1";
			/Resync Status : (\d+)% complete/ and $mds{$md}{resync} = $1 and verb 1, "Found resync: $1";
			/Active Devices : (\d+)$/ and $mds{$md}{active} = $1 and verb 1, "Found active devices: $1";
			/Working Devices : (\d+)$/ and $mds{$md}{working} = $1 and verb 1, "Found working devices: $1";
		}
	}
	verb 1, "Finished probing";
}


##############################################################################
## Getopts
##############################################################################

getopts 's:H:hvVd', \%opt;
parse_opts;


##############################################################################
## Main program
##############################################################################

getstatus();
$ret = 0;
for (keys %mds)
{
	verb 1, "Generate output info for $_";
	defined $mds{$_}{active} or $mds{$_}{active} = '?';
	defined $mds{$_}{working} or $mds{$_}{working} = '?';

	$perf .= "$_=$mds{$_}{working}/$mds{$_}{active} ";
	verb 1, "$_=$mds{$_}{working}/$mds{$_}{active} ";

	if ( defined $mds{$_}{resync} )
	{
		verb 1, "$_ resyncing";
		$output .= " $_ is resyncing, $mds{$_}{resync}% complete";
		$ret != 2 and $ret = 1;
	}

	$mds{$_}{state} =~ /^(clean(, checking)?|active)$/ and next; #ok states
	if ( $mds{$_}{state} =~ /degraded/ )
	{
		verb 1, "$_ is degraded";
		$ret != 2 and $ret = 1;
		$output .= " $_ is degraded";
	}
	if ( $mds{$_}{state} =~ /fail/ )
	{
		verb 1, "$_ is failing";
		$ret = 2;
		$output .= " $_ is failing!";
	}
	if ( $mds{$_}{state} eq '' )
	{
		verb 1, " $_ is unknown!";
		$ret == 0 and $ret = 3;
		$output .= " Unable to get state for $_";
	}
}

$output eq '' and $output = $default_output;
$perf .= ";;;;";
	

verb 1, join "\t", $conf{hostname}, $conf{service}, $ret, "$retlabel[$ret]:${output}|${perf}\n";

#printout
open MX, '|-', $multiplexer;
print MX join "\t", $conf{hostname}, $conf{service}, $ret, "$retlabel[$ret]:${output}|${perf}\n";
close MX;


##############################################################################
## mdinfo
##############################################################################
# You will need a wrapper to allow an unprivledged user to run mdadm.
# Here is a simple one that can be run with sudo:
#
# #!/usr/bin/env perl
# use warnings;
# use strict;
# my $dev = $ARGV[0];
# $dev =~ /^\/dev\/md\d+$/ or die "Not a MD device!\n";
# print qx(mdadm --detail $dev);
#
##############################################################################
