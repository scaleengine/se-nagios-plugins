#!/usr/bin/env perl
use warnings;
use strict;

use Data::Dumper;
use Getopt::Std;

###############################################################################
###############################################################################
##                            bind_stats.pl                                  ##
## Parses the output of rndc stats and formats as a passive check for nagios ##
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
## V. 1.0.0: Initial version                                        20160718 ##
## V. 1.0.1: Added default totals of 0 to prevent empty values      20160718 ##
## V. 1.0.2: Fixed defaults                                         20160719 ##
## V. 1.0.3: Added default 0 for xfer                               20160719 ##
## V. 1.0.4: Release under ISC license                              20160721 ##
###############################################################################
my $version = '1.0.4';
my $version_date = '2016-07-21';

###############################################################################
## Global variables
###############################################################################

my %conf;
my %opt;
my $ret;
my %stats;

###############################################################################
## Defaults
###############################################################################

%conf = (
	stats_dir			=> '/usr/local/etc/namedb/working',
	rndc				=> '/usr/local/sbin/rndc',
	nsca_multiplexer	=> '/home/nagmon/tools/nsca_multiplexer.sh',
	stats_file			=> 'named.stats',
	service				=> 'BIND_STATS',
	debug				=> 0
);
$conf{'hostname'} = qx(/bin/hostname);
chomp $conf{'hostname'};

%stats = (
	req_v4  => 0,	req_v6  => 0,   
	total   => 0,	xfer	=> 0,
);
$stats{'queries'} = {   
	A       => 0,   NS		=> 0,   
	CNAME   => 0,   SOA		=> 0,   
	PTR     => 0,   MX		=> 0,   
	TXT     => 0,   AAAA	=> 0,
	LOC     => 0,   EID		=> 0,   
	SRV     => 0,   NAPTR	=> 0,
	A6      => 0,   DS		=> 0,
	SSHFP   => 0,   RRSIG	=> 0,
	DNSKEY  => 0,   SPF		=> 0,
	ANY     => 0,   
};


###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] ..\n";
	exit;
}

sub VERSION_MESSAGE
{
	print "$0 version $version by Andrew Fengler (andrew.fengler\@scaleengine.net), $version_date\n";
	exit;
}

sub parse_opts
{
	defined $opt{'h'} and HELP_MESSAGE;
	defined $opt{'V'} and VERSION_MESSAGE;

	defined $opt{'W'} and $conf{'stats_dir'} = $opt{'W'};
	defined $opt{'f'} and $conf{'stats_file'} = $opt{'f'};
	defined $opt{'r'} and $conf{'rndc'} = $opt{'r'};
	defined $opt{'n'} and $conf{'nsca_multiplexer'} = $opt{'n'};
	defined $opt{'H'} and $conf{'hostname'} = $opt{'H'};
	defined $opt{'s'} and $conf{'service'} = $opt{'s'};

	defined $opt{'v'} and $conf{'debug'} = 1;
	defined $opt{'d'} and $conf{'debug'} = 2;
	$conf{'debug'} and print STDERR "parse.pl: read %conf from STDIN\n";
}

sub verb
{
	if ( $_[0] <= $conf{debug} )
	{
		print STDERR $_[1]."\n";
	}
}

sub submit
{
	verb 1, "$conf{'hostname'}\t$conf{'service'}\t$_[1]\t$_[2]\n";
	print { $_[0] } "$conf{'hostname'}\t$conf{'service'}\t$_[1]\t$_[2]\n";
}

sub wipe
{
	verb 1, "wiping $_[0]";
	open BYE, '>', $_[0] or return 2;
	print BYE '';
	close BYE;
	return 1;
}


sub get_stats
{
	chdir $conf{'stats_dir'};
	if ( -s $conf{'stats_file'} ) 
	{ 
		verb 1, "removing old stats file $conf{'stats_file'}";
		my $retcode = wipe($conf{'stats_file'}); 
		$retcode == 2 and return 3;
	}

	if ( qx(sudo $conf{'rndc'} status) =~ /server is up and running/ )
	{
		verb 1, "dumping stats file";
		system "sudo $conf{'rndc'} stats";
		-r $conf{'stats_file'} or return 3;
		verb 1, "Stats file $conf{'stats_file'} created";
		return 1;
	}
	else
	{
		verb 1, "ERROR: named not running";
		return 2;
	}
}

sub tally_stats
{
	while (readline $_[0])
	{
		/^\+\+/ and return;
		/(\d+) ([A-Z0-9]+)$/ and $stats{'queries'}{$2} = $1;
	}
}
	


##############################################################################
## Getopts
##############################################################################

getopts 'hvVdr:f:W:n:H:s:', \%opt;
parse_opts;


##############################################################################
## Main program
##############################################################################

$ret = get_stats();

open MPLX, '|-', $conf{'nsca_multiplexer'} or die "Cannot open nsca_multiplexer $conf{'nsca_multiplexer'}: $!\n";

if ( $ret == 2 ) 
{
	submit(\*MPLX, 2, "Named not running!");
}
elsif ( $ret == 3 ) 
{
	submit(\*MPLX, 3, "Cannot access stats file!");
} 
elsif ( $ret == 1 ) 
{
	open STATS, '<', $conf{'stats_file'};
	readline STATS;
	readline STATS;
	$stats{'total'} = readline STATS;
	$stats{'total'} =~ s/^\s+(\d+) .+$/$1/;
	chomp $stats{'total'};
	while (readline STATS)
	{
		/\+\+ Incoming Queries \+\+/ and tally_stats(\*STATS);
		/(\d+) IPv4 requests received/ and $stats{'req_v4'} = $1;
		/(\d+) IPv6 requests received/ and $stats{'req_v6'} = $1;
		/(\d+) transfer requests succeeded/ and $stats{'xfer'} = $1;
	}
	close STATS;

	submit(\*MPLX, 0, "Named has processed $stats{'total'} queries since program start.|total=$stats{'total'} req_v4=$stats{'req_v4'} req_v6=$stats{'req_v6'} xfer=$stats{'xfer'} A=$stats{'queries'}{'A'} AAAA=$stats{'queries'}{'AAAA'} CNAME=$stats{'queries'}{'CNAME'} MX=$stats{'queries'}{'MX'} NS=$stats{'queries'}{'NS'} SOA=$stats{'queries'}{'SOA'} PTR=$stats{'queries'}{'PTR'} TXT=$stats{'queries'}{'TXT'} SRV=$stats{'queries'}{'SRV'} DS=$stats{'queries'}{'DS'} DNSKEY=$stats{'queries'}{'DNSKEY'} RRSIG=$stats{'queries'}{'RRSIG'} SSHFP=$stats{'queries'}{'SSHFP'} SPF=$stats{'queries'}{'SPF'} EID=$stats{'queries'}{'EID'} NAPTR=$stats{'queries'}{'NAPTR'} A6=$stats{'queries'}{'A6'} ANY=$stats{'queries'}{'ANY'} ;;;;");
}


###############################################################################
## Cleanup
###############################################################################


close MPLX;
wipe("$conf{'stats_file'}");

