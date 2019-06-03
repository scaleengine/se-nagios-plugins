#!/usr/bin/env perl
use warnings;
use strict;

use LWP;
use JSON::XS;
use Data::Dumper;
use Getopt::Std;
use Sys::Syslog;

###############################################################################
###############################################################################
##                           gdnsd_stats.pl                                  ##
## Get the stats out of the gdnsd json interface and pass them to nagios     ##
## Written by Andrew Fengler                                                 ##
###############################################################################
## Copyright (c) 2019, Andrew Fengler <andrew.fengler@scaleengine.com>       ##
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
## V. 1.0.0: Initial release                                        20190603 ##
###############################################################################
## TODO: do some local handling to suport warn/crit states                   ##
###############################################################################
my $version = '1.0.0';
my $version_date = '2019-06-03';


###############################################################################
## Global variables
###############################################################################

my %conf = (
	hostname	=> qx(hostname),
	debug		=> 0,
	port		=> 13506,
	uri			=> '/json',
	alert_human	=> [ 'OK', 'WARN', 'CRIT', 'UNKNOWN' ],
	service		=> 'GDNSD_STATS',
	warn		=> '',
	crit		=> '',
	multiplexer	=> '/usr/local/bin/nsca_multiplexer.sh',
);
chomp $conf{hostname};

my %opt;

my %loglevel = (
     -5 => 'LOG_EMERG',
     -4	=> 'LOG_ALERT',
     -3	=> 'LOG_CRIT',
     -2 => 'LOG_ERR',
     -1	=> 'LOG_WARNING',
     0	=> 'LOG_NOTICE',
     1	=> 'LOG_INFO',
     2, => 'LOG_DEBUG',
);

my ( $message, @perfdata, $retval );
my ( $data_s, $data_o );

###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] [-s servicename] [-u json_uri] [-p port]\n";
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
	my $level = shift @_;
	$level <= $conf{debug} and print STDERR 'DEBUG('.$level.'): ', @_;
	syslog($loglevel{$level}, '%s', join(' ', @_)."\n");
	return 1;
}

sub curl ($$;$$$$$)
{
	my $host = shift;
	my $uri = shift;
	my $ssl = shift;
	my $port = shift;
	my $realm = shift;
	my $user = shift;
	my $pass = shift;
	
	my ( $browser, $response );

	my $proto = $ssl ? 'https://' : 'http://';
	$port = $ssl ? 443 : 80 unless defined $port;
	verb 1, "Curling $proto$host:$port$uri";

	$browser = LWP::UserAgent->new();

	$browser->credentials($host.':'.$port, $realm, "$user" => "$pass") if defined $realm;
	verb 1, ($host.':'.$port, $realm, "$user" => "$pass") if defined $realm;

	$browser->add_handler("request_send",  sub { shift->dump; return }) if $conf{debug} ge 2;
	$browser->add_handler("response_done", sub { shift->dump; return }) if $conf{debug} ge 2;

	$response = $browser->get($proto.$host.':'.$port.$uri);
	verb 2, $response->content;

	if ( ! $response->is_success ) 
	{
		verb 0, "ERROR: curl responded:\n", $response->status_line, "\nEOT"; 
		return "ERROR: ".$response->status_line;
	}
	else
	{
		return $response->content;
	}
}

sub submit_check ($$@)
{
	my $ret = shift;
	my $msg = shift;
	my $perf = join ' ', @_;
	open MPLX, '|-', $conf{multiplexer} or die "Could not open multiplexer!\n";
	print MPLX "$conf{hostname}\t$conf{service}\t${ret}\t$conf{alert_human}[$ret]: ${msg}|${perf}\n";
	verb 1, "$conf{hostname}\t$conf{service}\t${ret}\t$conf{alert_human}[$ret]: ${msg}|${perf}\n";
}


##############################################################################
## Getopts
##############################################################################

getopts 'hvVdw:c:s:u:p:', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;
defined $opt{w} and $conf{warn} = $opt{w};
defined $opt{c} and $conf{crit} = $opt{c};

defined $opt{s} and $conf{service} = $opt{s};
defined $opt{u} and $conf{uri} = $opt{u};
defined $opt{p} and $conf{port} = $opt{p};

verb 1, "Read %conf from args";

verb 1, "Opening syslog connection";
openlog($0, "ndelay,pid", "local4");


##############################################################################
## Main program
##############################################################################

#Get the stat data:
$data_s = curl('localhost', $conf{uri}, 0, $conf{port});
if ( substr($data_s, 0, 5) eq 'ERROR' )
{
	verb 0, "Errored out fetching json";
	exit 1;
}

$data_o = decode_json $data_s;

for my $i ( sort keys %{$data_o->{stats}} )
{
	verb 1, "Got datapoint: $i = $data_o->{stats}{$i}";
	push @perfdata, $i.'='.$data_o->{stats}{$i}.'c;;;;';
}

submit_check(0, "gdnsd stats", @perfdata);

#TODO: check the queries/second to have something to show to the user, and do nxdomain/s for warn/crit
