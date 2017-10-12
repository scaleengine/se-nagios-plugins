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
## V. 1.0.0: Initial release                                        20171012 ##
###############################################################################
my $version = '1.0.0';
my $version_date = '2017-10-12';


###############################################################################
## Global variables
###############################################################################

my %conf = (
	warn		=> 35,
	crit		=> 40,
	debug		=> 0,
	disks		=> [],
	hostname	=> qx(hostname),
	service		=> 'SMART',
);
chomp $conf{hostname};

my %opt;
my $smartctl = qx(which smartctl);
chomp $smartctl;
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
	print "$0 usage:\n\t$0 [-v|-d] [-H hostname] [-S servicename] [-w warn_temp] [-c crit_temp] -D ada1,da0,...\n";
	exit;
}

sub VERSION_MESSAGE
{
	print "$0 version $version by Andrew Fengler (andrew.fengler\@scaleengine.net), $version_date\n";
	exit;
}

sub verb ($@)
{
	local $, = ' ';
	local $\ = "\n";
	shift @_ <= $conf{debug} and print STDERR @_;
	return 1;
}

sub get_smart ($) {
    my %value;
	my $dev = $_[0];
	my $command = qq($smartctl -a $dev);
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
        if ( /SMART overall-health self-assessment test result: (.*)$/ ) 
		{
			verb 1, "Found overall health test: $1";
            $value{'health'} = $1;
		} 
		elsif ( /Temperature_Celsius/ ) 
		{
	    	$value{'temp'} = (split(/\s+/))[9];
			verb 1, "Found temperature: $value{temp}";
        } 
		elsif ( /\d+\s+(\w+).*\s+(\d+)\s+(\d+)\s+(\d+)\s+Pre-fail/ ) 
		{
	    	verb 1, qq(found pre-fail smart value: $1 $2 $3 $4\n);
	    	$value{v}{$1}{value} = $2;
	    	$value{v}{$1}{worst} = $3;
	    	$value{v}{$1}{thresh} = $4;
		} 
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

getopts 'hvVdw:c:D:H:S:', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;

defined $opt{w} and $conf{warn} = $opt{w};
defined $opt{c} and $conf{crit} = $opt{c};

defined $opt{H} and $conf{hostname} = $opt{H};
defined $opt{S} and $conf{service} = $opt{S};

defined $opt{D} or die "ERROR: You must specify a list of disks to check with -D\n";
verb 1, "Got disks: $opt{D}";
for my $d (split /,/, $opt{D})
{
	if (-c "/dev/${d}")
	{
		verb 2, "Adding /dev/${d} to list of disks";
		push @{$conf{disks}}, "/dev/${d}"; 
	}
	else
	{
		die "ERROR: disk /dev/${d} is not a character device\n";
	}
}
verb 1, "Read %conf from args";


##############################################################################
## Main program
##############################################################################


foreach my $disk (@{$conf{disks}})
{
	my %vals = get_smart($disk);

	if ( ! scalar %vals )
	{
		verb 1, "UNKNOWN: no smart data from $disk";
		$unknown = 1;
		push @errors, qq($disk: no smart data);
		push @perfdata, qq($disk=0); 
		next;
	}

	if ( $vals{health} ne "PASSED" )
	{
		verb 1, "Overall health check returned $vals{health}";
		$warning = 1;
		push @errors, qq($disk: health $vals{health});
	}

	if ( $vals{temp} )
	{
		push @perfdata, qq($disk=$vals{temp}); 
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
		push @perfdata, qq($disk=00);
		$warning = 1;
		push @errors, qq(Could not read temp for $disk);
	}

	for my $item ( keys %{$vals{v}} )
	{
		if ( $vals{v}{$item}{value} <= $vals{v}{$item}{thresh} )
		{
			verb 1, qq(Item $item on disk $disk is over the threshold ($vals{v}{$item}{value}/$vals{v}{$item}{thresh}));
			$critical = 1;
			push @errors, qq($disk: $item - $vals{v}{$item}{value});
		}
	}
}

verb 0, "warning:", $warning, "critical:", $critical, "unknown:", $unknown;
verb 0, (scalar @errors) ? join ' ', @errors : "OK";
verb 0, join ' ', @perfdata;

submit_nsca ( 
	( $critical ? 2 : ( $warning ? 1 : ( $unknown ? 3 : 0 ) ) ),
	( (scalar @errors) ? join ' ', @errors : "SMART OK" ) . '|' . join ( ' ', @perfdata )
);

exit 0;
