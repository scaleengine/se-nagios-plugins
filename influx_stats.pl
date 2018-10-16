#!/usr/bin/env perl
use warnings;
use strict;

use LWP;
use JSON;
use Getopt::Std;


###############################################################################
###############################################################################
##                           influx_stats.pl                                 ##
## Get statistics out of influxdb and format them for nagios                 ##
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
## V. 1.0.0: Initial release                                        20170124 ##
## V. 1.1.0: Remove depricated push/shift on scalar                 20181016 ##
###############################################################################
my $version = '1.1.0';
my $version_date = '2018-10-16';


###############################################################################
## Global variables
###############################################################################

my %conf = (
	warn		=> 16000000000,
	crit		=> 32000000000,
	debug		=> 0,
	host		=> 'influxdb.mydomain.net',
	port		=> 8086,
	user		=> 'nagios',
	pass		=> 'password',
);
my %opt;
my $json;
my $json_data;
my %stats;
my $perfdata = '|';

# Settings for InfluxDB.  Change based on your specifix setup
my $url = "https://$conf{host}:$conf{port}/query?u=$conf{user}&p=$conf{pass}&db=_internal";
my $data = 'SELECT * FROM "runtime" limit 1'; 

###############################################################################
## Subroutine definitions
###############################################################################

sub HELP_MESSAGE
{
	print "$0 usage:\n\t$0 [-v|-d] [-w warn] [-c crit] [-u username] [-p password] [-P port] -H host\n";
	print "\t Warn and crit are in GB\n";
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

sub influx_post ($$)
{
	my ( $browser, $response, $response_clean, $error_msg );
	my $target = $_[0];
	my $post_data = $_[1];

	$browser = LWP::UserAgent->new();
	$response = $browser->post ( $target, [ 'q' => $post_data ] );
	if ( ! $response->is_success )
	{
		verb 1, "fetch.pl: ERROR: post ( $target, [ 'q' => $post_data ] ) responded: ", $response->status_line; 
		$error_msg = $response->status_line;
		return qq({"error":"$error_msg"});
	}
	verb 2, "Response:\n", $response->content;
	return $response->content;
}

sub data_scrape ($$)
{
	# Reformat data from influx to a usable format
	my $in_ref = $_[0];
	my $out_ref = $_[1];
	my $i = 99; #loop breaker;
	my ( $key, $value );


	while ( $i )
	{
		$i--;
		$key = shift %{$in_ref->{results}[0]{series}[0]{columns}} or last;
		$value = shift %{$in_ref->{results}[0]{series}[0]{values}[0]} or last;

		verb 1, "Got datapoint: $key => $value";
		
		$out_ref->{$key} = $value;
	}
}


##############################################################################
## Getopts
##############################################################################

getopts 'hvVdH:w:c:P:u:p:', \%opt;
defined $opt{h} and HELP_MESSAGE;
defined $opt{V} and VERSION_MESSAGE;

defined $opt{H} and $conf{host} = $opt{H};
defined $opt{w} and $conf{warn} = $opt{w} * 1024 * 1024 * 1024;
defined $opt{c} and $conf{crit} = $opt{c} * 1024 * 1024 * 1024;
defined $opt{P} and $conf{port} = $opt{P};
defined $opt{u} and $conf{user} = $opt{u};
defined $opt{p} and $conf{pass} = $opt{p};

if ( $conf{warn} !~ /^\d+$/ or $conf{crit} !~ /^\d+$/ )
{
	print "Warn and Crit must be integers\n";
	exit 3;
}

defined $opt{v} and $conf{debug} = 1;
defined $opt{d} and $conf{debug} = 2;
verb 1, "read %conf from args";


##############################################################################
## Main program
##############################################################################

	
verb 1, "Get data from influx";
$json = influx_post ( $url, $data );

verb 1, "Decode JSON";
$json_data = decode_json ( $json );

if ( $json_data->{error} )
{
	print "CRITICAL: There was an error getting data from influx.  Error is:\n$json_data->{error}\n";
	exit 2; 
}

verb 1, "Reformating data";
data_scrape ( $json_data, \%stats );

# Build perfdata
for ( sort ( keys %stats ) )
{
	$perfdata .= "$_=$stats{$_} ";
}
$perfdata .= ";$conf{warn};$conf{crit};;\n";

if ( $stats{HeapInUse} )
{
	if ( $stats{HeapInUse} >= $conf{crit})
	{
		print "CRITICAL: Influxdb Heap usage is $stats{HeapInUse}", $perfdata;
		exit 2;
	}
	if ( $stats{HeapInUse} >= $conf{warn})
	{
		print "WARNING: Influxdb Heap usage is $stats{HeapInUse}", $perfdata;
		exit 1;
	}
	else
	{
		print "OK: Influxdb is responsive", $perfdata;
		exit 0;
	}
}
else
{
	print "WARNING: Unable to find heap usage data!", $perfdata;
	exit 1;
}
