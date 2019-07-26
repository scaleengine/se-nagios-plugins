#!/usr/bin/env perl
use warnings;
use strict;

use Data::Dumper;
use Getopt::Std;

###############################################################################
###############################################################################
##                            check_smart.pl                                 ##
## Checks the output of smartctl and reports it to nagios                    ##
## Written by Andrew Fengler                                                 ##
###############################################################################
## Copyright (c) 2017, Andrew Fengler <andrew.fengler@scaleengine.com>       ##
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
## V. 1.0.0: Initial release                                        20171027 ##
## V. 1.1.0: Add logic to parse SMART data from SAS drives          20171110 ##
## V. 1.2.0: Add type flag to support passing -d to smartctl        20181129 ##
## V. 2.0.0: Add support for sysutils/smart                         20190716 ##
###############################################################################
## TODO                                                                      ##
## Handle SAS counters using sysutils/smart                                  ##
###############################################################################
my $version = '2.0.0';
my $version_date = '2019-07-16';


###############################################################################
## Global variables
###############################################################################

$ENV{PATH} = '/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/home/nagmon/tools';

my %conf = (
	warn		=> 45,
	crit		=> 75,
	iwarn		=> 100,
	icrit		=> 300,
	debug		=> 0,
	disks		=> [],
	hostname	=> qx(hostname),
	service		=> 'SMART',
	type		=> '',
);
chomp $conf{hostname};

my %opt;
my $sudo = qx(which sudo);
chomp $sudo;
my $smartcmd = '';
my $multiplexer = qx(which nsca_multiplexer.sh);
chomp $multiplexer;

my $warning = 0;
my $critical = 0;
my $unknown = 0;
my @perfdata = ();
my @errors = ();

###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] [-H hostname] [-S servicename] [-w warn_temp] [-c crit_temp] [-t controller_type] [-s smart_command] -D ada1,da0,...\n";
	exit;
}

sub VERSION_MESSAGE
{
	print "$0 version $version by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n";
	exit;
}

sub verb ($@)
{
	local $, = ' ';
	local $\ = "\n";
	shift @_ <= $conf{debug} and print STDERR @_;
	return 1;
}

sub get_smartctl ($) 
{
	my %value;
	my $dev = $_[0];
	my $command = qq($sudo $smartcmd $conf{type} -a $dev);
	my $r;

	verb 1, "\nGetting smart data for $dev...";
	$r = open ( SMART, '-|', $command );
	if ( ! $r )
	{ 
		verb 0, qq(ERROR getting smart data from disk $dev);
		return (); 
	}

	while ( <SMART> ) 
	{
		verb 2, "Line:", $_;
		if ( /SMART overall-health self-assessment test result: (.*)$/ or /^SMART Health Status: (.*)$/ )
		{
			verb 1, "Found overall health test: $1";
			$value{'health'} = $1;
		} 
		elsif ( /Temperature_Celsius\s+\w+(?:\s+\d+){3}(?:\s+[\w\-]+){3}\s+(\d+)/  or /Current Drive Temperature:\s+(\d+) C/ )
		{
			#$value{'temp'} = (split(/\s+/))[9];
			$value{'temp'} = $1;
			verb 1, "Found temperature: $value{temp}";
		} 
		elsif ( /^\s*(5|196|197|198)\s+(\w+).*\s+(\d+)\s+(\d+)\s+(\d+)\s+[\w\-]+\s+[\w\-]+\s+[\w\-]+\s+(\d+)/ ) 
		{
			# 5,196,197,198 are the smart values we consider to be failure indicators
			verb 1, qq(found pre-fail smart value: $1 $2 $6\n);
			$value{v}{$1}{name} = $2;
			$value{v}{$1}{value} = $3;
			$value{v}{$1}{worst} = $4;
			$value{v}{$1}{thresh} = $5;
			$value{v}{$1}{raw} = $6;
		} 
		elsif ( /Elements in grown defect list:\s+(\d+)/ ) #SAS reallocated sectors
		{
			$value{v}{dl}{name} = 'Defect List';
			$value{v}{dl}{raw} = $1;
			verb 1, "Found SAS defect list: $1 items";
		}
		elsif ( /^(read|write|verify):(?:\s+[\d\.]+){6}\s+(\d+)/ ) #SAS ECC list, last column is uncorrectable
		{
			$value{v}{unc}{name} = 'Uncorrectable Errors';
			defined $value{v}{unc}{raw} or $value{v}{unc}{raw} = 0;
			$value{v}{unc}{raw} += $2;
			verb 1, "Found SAS $1 errors: $2 uncorrectable";
		}
	}

	close SMART;
	verb 1, "...Done\n";
	return %value;
}

sub get_smart ($)
{
	my %value;
	my $dev = $_[0];
	my $command = qq($sudo $smartcmd $conf{type} $dev);
	my $r;

	verb 1, "\nGetting smart data for $dev...";
	$r = open ( SMART, '-|', $command );
	if ( ! $r )
	{ 
		verb 0, qq(ERROR getting smart data from disk $dev);
		return (); 
	}

	while ( <SMART> ) 
	{
		verb 2, "Line:", $_;
		chomp;
		my @row = split / /, $_;
		# smart does not do an overall health check (yet)
		$value{'health'} = 'OK';
		
		if ( $row[1] eq '194' or $row[1] eq '190' )
		{
			$value{'temp'} = ($row[2] % 256); # Temperature is a packed value with the lowest byte being the current temp.
			verb 1, "Found temperature: $value{temp}";
		} 
		if ( $row[1] eq '5' or $row[1] eq '196' or $row[1] eq '197' or $row[1] eq '198' )
		{
			# 5,196,197,198 are the smart values we consider to be failure indicators
			verb 1, qq(found pre-fail smart value:), $row[1], $row[2];
			$value{v}{$row[1]}{name} = $row[1];
			# Sometimes these could also be a packed value, assume anything over 2^16 is packed
			verb 1, "Unpacked value:", ($row[2] % 65536) if ( $row[2] >= 65536 );
			$value{v}{$row[1]}{raw} = $row[2] % 65536;
		} 
		#elsif ( /Elements in grown defect list:\s+(\d+)/ ) #SAS reallocated sectors
		#{
		#	$value{v}{dl}{name} = 'Defect List';
		#	$value{v}{dl}{raw} = $1;
		#	verb 1, "Found SAS defect list: $1 items";
		#}
		#elsif ( /^(read|write|verify):(?:\s+[\d\.]+){6}\s+(\d+)/ ) #SAS ECC list, last column is uncorrectable
		#{
		#	$value{v}{unc}{name} = 'Uncorrectable Errors';
		#	defined $value{v}{unc}{raw} or $value{v}{unc}{raw} = 0;
		#	$value{v}{unc}{raw} += $2;
		#	verb 1, "Found SAS $1 errors: $2 uncorrectable";
		#}
	}

	close SMART;
	verb 1, "...Done\n";
	return %value;
}

sub submit_nsca ($$) 
{
	my $ret = $_[0];
	my $string = $_[1];
	verb 1, join "\t", $conf{hostname}, $conf{service}, $ret, $string;
	open MX, '|-', $multiplexer;
	print MX join "\t", $conf{hostname}, $conf{service}, $ret, $string;
	close MX;
}

##############################################################################
## Getopts
##############################################################################

getopts 'hvVdw:c:D:H:S:W:C:T:s:', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;

defined $opt{w} and $conf{warn} = $opt{w};
defined $opt{c} and $conf{crit} = $opt{c};
defined $opt{W} and $conf{iwarn} = $opt{W};
defined $opt{C} and $conf{icrit} = $opt{C};

defined $opt{H} and $conf{hostname} = $opt{H};
defined $opt{S} and $conf{service} = $opt{S};

defined $opt{T} and $conf{type} = '-d '.$opt{T};
defined $opt{s} and $smartcmd = $opt{s};

defined $opt{D} or die "ERROR: You must specify a list of disks to check with -D\n";
verb 1, "Got disks: $opt{D}";
for my $d (split /,/, $opt{D})
{
	if ( $d eq 'cd0' )
	{
		verb 2, "Skipping cd drive";
		next;
	}
	if (-c "/dev/${d}" or -b "/dev/${d}" )
	{
		verb 2, "Adding /dev/${d} to list of disks";
		push @{$conf{disks}}, "/dev/${d}"; 
	}
	else
	{
		die "ERROR: disk /dev/${d} is not a character or block device\n";
	}
}
verb 1, "Read %conf from args";

if ( $smartcmd eq '' and substr(qx(uname), 0, 7) eq 'FreeBSD' )
{
	$smartcmd = qx(which smart);
	chomp $smartcmd;
	verb 1, "found smart:", $smartcmd;
}
if ( $smartcmd eq '' )
{
	$smartcmd = qx(which smartctl);
	chomp $smartcmd;
	verb 1, "found smartctl:", $smartcmd;
}

##############################################################################
## Main program
##############################################################################


foreach my $disk (@{$conf{disks}})
{
	my %vals;
	if ( $smartcmd =~ /smart$/ )
	{
		verb 1, "Smart comamnd is $smartcmd, running get_smart";
		%vals = get_smart($disk);
	}
	else
	{
		verb 1, "Smart comamnd is $smartcmd, running get_smartctl";
		%vals = get_smartctl($disk);
	}
	my $perf = "$disk=";

	if ( ! scalar %vals )
	{
		verb 1, "UNKNOWN: no smart data from $disk";
		$unknown = 1;
		push @errors, qq($disk: no smart data);
		push @perfdata, qq($disk=0); 
		next;
	}

	if ( $vals{health} !~ /PASSED|OK/ )
	{
		verb 1, "Overall health check returned $vals{health}";
		$warning = 1;
		push @errors, qq($disk: health $vals{health});
	}

	if ( $vals{temp} )
	{
		$perf .= qq(temp:$vals{temp}); 
		if ( $vals{temp} >= $conf{warn} )
		{
			$warning = 1;
			push @errors, qq($disk temp is $vals{temp}, warn: $conf{warn});
		}
		elsif ( $vals{temp} >= $conf{crit} )
		{
			$critical = 1;
			push @errors, qq($disk temp is $vals{temp}, crit $conf{crit});
		}
		
	}
	else
	{
		$perf .= qq(temp:00);
		verb 1, qq(Could not read temp for $disk);
	}

	for my $item ( sort keys %{$vals{v}} )
	{
		if ( $vals{v}{$item}{raw} >= $conf{icrit} )
		{
			verb 1, qq(Item $vals{v}{$item}{name} on disk $disk is over icrit ($vals{v}{$item}{raw}/$conf{icrit}));
			$critical = 1;
			push @errors, qq($disk: $item - $vals{v}{$item}{raw});
		}
		elsif ( $vals{v}{$item}{raw} >= $conf{iwarn} )
		{
			verb 1, qq(Item $vals{v}{$item}{name} on disk $disk is over iwarn ($vals{v}{$item}{raw}/$conf{iwarn}));
			$warning = 1;
			push @errors, qq($disk: $item - $vals{v}{$item}{raw});
		}
		$perf .= ",${item}:$vals{v}{$item}{raw}";
	}
	push @perfdata, $perf;
}

verb 0, "warning:", $warning, "critical:", $critical, "unknown:", $unknown;
verb 0, (scalar @errors) ? join ' ', @errors : "OK";
verb 0, join ' ', @perfdata;

submit_nsca ( 
	( $critical ? 2 : ( $warning ? 1 : ( $unknown ? 3 : 0 ) ) ),
	( (scalar @errors) ? join ' ', @errors : "SMART OK" ) . '|' . join ( ' ', @perfdata )
);

exit 0;
