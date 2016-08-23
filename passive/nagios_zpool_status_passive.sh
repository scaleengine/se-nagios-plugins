#!/bin/sh

###############################################################################
###############################################################################
##                     nagios_zpool_status_passive.sh                        ##
## A Nagios passive check that reports zfs pool health using 'zpool status'. ##
## Requires nsca_client and nsca_multiplexer.sh                              ##
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
## V. 1.0.0: Initial version                                        20150805 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
###############################################################################
version="1.0.1"
version_date='2016-07-21'


multiplexer=$(which nsca_multiplexer.sh)
service=""
pool=""
hostname=$(hostname)
message=""
retcode=""


while getopts "s:p:H:hv" opt ; do
	case $opt in
		v)
			echo "$0 version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date"
			exit 0
			;;
		h)
			echo "Usage:\n\t$0 -s servicename -p poolname [ -H hostname ]\n\t$0 -h|-v"
			exit 0
			;;
		s)
			if [ -n $OPTARG ]
			then service=$OPTARG 
			else echo "Option -s requires a service name as an argument" ; exit 4
			fi
			;;
		p)
			if [ -n $OPTARG ]
			then pool=$OPTARG 
			else echo "Option -p requires a zfs pool name as an argument" ; exit 4
			fi
			;;
		H)
			if [ -n $OPTARG ]
			then hostname=$OPTARG 
			else echo "Option -H requires a hostname as an argument" ; exit 4
			fi
			;;
	esac
done

[ -n "$service" ] || { echo "Required option servicename not found.  Exiting." && exit 4 ; }
[ -n "$pool" ] || { echo "Required option poolname not found.  Exiting." && exit 4 ; }

feed=$(zpool status -x $pool)
ret=$?

if [ $ret -gt 0 ] 
then
	message="UNKNOWN: $pool not found"
	retcode=3
else
	cond=$(echo $feed | cut -d \' -f 3)
	if [ "$cond" = " is healthy" ]
	then
		retcode=0
		message="OK: zfs pool $pool is healthy"
	elif [ "$(echo $feed | cut -d : -f 3 | cut -w -f 2 | tr -d "\n")" = "DEGRADED" ]
	then
		retcode=2
		message="CRITICAL: zfs pool $pool is in a degraded state"
	elif [ "$(echo $feed | cut -d : -f 3 | cut -w -f 2 | tr -d "\n")" = "UNAVAIL" ]
	then
		retcode=2
		message="CRITICAL: zfs pool $pool is unavailible"
	else
		i=$(echo $feed | cut -d : -f 4 | wc -w | cut -w -f 2)
		zstatus=$(echo $feed | cut -d : -f 4 | cut -w -f 2-$i | tr "\t" " ")
		retcode=2
		message="CRITICAL: zfs pool $pool is in an unknown non-healthy state.  'zpool status' returned status: $zstatus"
	fi
fi

printf "%s\t%s\t%s\t%s\n" $hostname $service $retcode "$message" | $multiplexer
