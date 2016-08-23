#!/bin/sh

###############################################################################
###############################################################################
##                         passive_coretemp.sh                               ##
## Sends coretemp info to nagios via nsca_multiplexer.sh                     ##
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
## V. 1.0.0: Inital release                                         20150716 ##
## V. 1.0.1: Fixed passive_coretemps.sh to use multiplexer          20150807 ##
## V. 1.1.0: added coretemp support for linux hosts                 20160315 ##
## V. 1.1.1: Release under ISC license                              20160721 ##
###############################################################################

numcpu=`sysctl -n hw.ncpu`
pointer=0
desc="Core Temperatures:"
perf=""
service="CORETEMP"
hostname=$(hostname)
multiplexer=$(which nsca_multiplexer.sh)
os=$(uname)
retval=""
output=""

if [ "$os" == "FreeBSD" ]
then
	while [ "$pointer" -lt "$numcpu" ]
	do
		temp=`sysctl -n dev.cpu.${pointer}.temperature`
		retval=$?
		desc="$desc $temp"
		perf="$perf cpu.${pointer}=${temp}"
		pointer=`expr $pointer + 1`
	done
elif [ "$os" == "Linux" ]
then
	#perf=$(sensors | perl -nw -e '/^Core (\d+):\s+?\+([\d\.]+).*?$/ and print " cpu.${1}=${2}C"')
	perf=$(sensors | perl -w -e 'my $i = 0; while (<>) { /Core (\d+):\s+?\+([\d\.]+).*?$/ and print " cpu.${i}=${2}C" and $i ++; }')

	desc="Core Temperatures:$(echo $perf | perl -nw -e 'my @a = split " "; for (@a) { /cpu\.\d+=([\d\.]+)C/ and print " $1" ; }')"
	retval=0
	[ "$perf" == '' ] && retval=1
fi

output="$desc |$perf"

printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "$retval" "$output" | $multiplexer
