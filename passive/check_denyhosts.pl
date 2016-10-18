#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Std;

###############################################################################
###############################################################################
##                            check_denyhosts.pl                             ##
## Counts the number of hosts blocked in the denyhosts file (hosts.deny on   ##
## Linux, hosts.deniedssh on FreeBSD)                                        ##
## Idea based on Frank4DD's check_fail2ban.sh script:                        ##
## http://nagios.fm4dd.com/plugins/manual/check_fail2ban.htm                 ##
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
## V. 1.0.0: Initial version                                        20160314 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
## V. 1.1.0: Test if denyhosts is running, go critical if not       20160907 ##
## V. 1.1.1: Adjust the syslog facility to work on centos 7         20160908 ##
## V. 1.1.2: Added debug lines                                      20160927 ##
###############################################################################
my $version = '1.1.2';
my $version_date = '2016-09-27';

###############################################################################
## Global Variables
###############################################################################

my $deny_file = (qx(uname) eq qq(FreeBSD\n)) ? '/etc/hosts.deniedssh' : '/etc/hosts.deny' ;
my $syslog_facility = (qx(uname) eq qq(FreeBSD\n)) ? 'auth' : 'authpriv';
my $offset_file = '/usr/local/share/denyhosts/data/offset';
my $blocked = 0;

my $multiplexer = qx(which nsca_multiplexer.sh);
die "No nsca_multiplexer.sh found in \$PATH\n" if $multiplexer eq "\n";
chomp $multiplexer;

my $hostname = qx(hostname);
chomp $hostname;

my $warn = 50;
my $crit = 100;
my $svc = 'DENYHOSTS';
my $verbose = 0;
my %arg;
my ($status, $rc);
my ($offset1, $offset2);
my $error = '';

###############################################################################
## Subroutine Declarations
###############################################################################

sub VERSION_MESSAGE
{
	print "check_denyhosts.pl version $version by Andrew Fengler (andrew.fengler\@scaleengine.com), $version_date\n";
	exit;
}

sub HELP_MESSAGE 
{
	print "check_denyhosts.pl: Check how many IP addresses have been blocked by denyhosts.\n\nUsage:\n\tcheck_denyhosts.pl [-w warn] [-c crit] [-H hostname] [-s servicename]\n";
	exit;
}

sub verb
{
	local $, = ' ';
	local $\ = "\n";
	shift @_ <= $verbose and print STDERR @_;
	return 1;
}

###############################################################################
## Getopts
###############################################################################

getopts 'w:c:H:vd', \%arg;

$arg{'H'} and $arg{'H'} =~ /^[\.a-zA-Z0-9-]+$/ and $hostname = $arg{'H'};
$arg{'w'} and $arg{'w'} =~ /^\d+$/ and $warn = $arg{'w'};
$arg{'c'} and $arg{'c'} =~ /^\d+$/ and $crit = $arg{'c'};
$arg{'v'} and $verbose = 1;
$arg{'d'} and $verbose = 2;
$arg{'h'} and HELP_MESSAGE;
$arg{'V'} and VERSION_MESSAGE;

###############################################################################
## Main Program
###############################################################################

$verbose > 0 and print "Deny File: $deny_file\n";

open FH, '<', $deny_file;

while (<FH>)
{
	chomp;
	/^# DenyHosts:.*?| sshd: (?:\d{1-3}\.){3}(?:\d{1-3})}$/
		and $blocked ++;
	verb 2, "Blocked host: $_";
}

close FH;

$status = "OK: ";
$rc = 0;
$blocked >= $warn and $rc = 1 and $status = "WARNING: ";
$blocked >= $crit and $rc = 2 and $status = "CRITICAL: ";

#Check that denyhosts is running
#This stalls the script for 60s
{
	open OFF, '<', $offset_file 
		or ( $error = $! and last );
	$/ = '';
	$offset1 = <OFF>;
	verb 1, "Offset: $offset1";
	close OFF;
	qx(logger -p ${syslog_facility}.info "Test if denyhosts is running for Nagios check");
	verb 1, "Inserted test line, sleeping";
	sleep 61;
	open OFF, '<', $offset_file
		or ( $error = $! and last );
	$offset2 = <OFF>;
	verb 1, "Offset: $offset2";
	close OFF;
	$/ = "\n";
	if ( $offset1 eq $offset2 ) 
	{ 
		verb 1, "Offset unchanged";
		$status = "CRITICAL: Denyhosts is not running: "; 
		$rc = 2; 
	}
}
if ( $error ne '' )
{
	$status = "WARNING: unable to read offset file - $error: ";
	$rc = 1;
}

open MPLX, '|-', $multiplexer or die "Could not open multiplexer!\n";

print MPLX "${hostname}\t${svc}\t${rc}\t${status}${blocked} hosts have been blocked on this server|blocked=${blocked};${warn};${crit};;\n";
verb 1, "${hostname}\t${svc}\t${rc}\t${status}${blocked} hosts have been blocked on this server|blocked=${blocked};${warn};${crit};;";
