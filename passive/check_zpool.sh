#!/bin/sh

###############################################################################
###############################################################################
##                              check_zpool.sh                               ##
## A Nagios passive check that reports zfs pool health using 'zpool list'.   ##
## Requires nsca_client and nsca_multiplexer.sh                              ##
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
## V. 1.0.0: Initial version                                        20190627 ##
###############################################################################
version="1.0.0"
version_date='2019-06-27'


multiplexer=$(which nsca_multiplexer.sh)
service="ZPOOL"
hostname=$(hostname)
message_f=''
debug=0
shifts=0


while getopts "s:H:hvV" opt ; do
	case $opt in
		V)	echo "$0 version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date"
			exit 0
			;;
		v)	debug=1
			shifts=$(($shifts + 1))
			;;
		h)	echo "Usage:"
			echo "	$0 [-s servicename] [ -H hostname ] poolname [poolname ...]"
			echo "	$0 -h|-v"
			exit 0
			;;
		s)	if [ -n $OPTARG ]
			then service=$OPTARG 
			else echo "Option -s requires a service name as an argument" ; exit 4
			fi
			shifts=$(($shifts + 2))
			;;
		H)	if [ -n $OPTARG ]
			then hostname=$OPTARG 
			else echo "Option -H requires a hostname as an argument" ; exit 4
			fi
			shifts=$(($shifts + 2))
			;;
	esac
done

[ $shifts -gt 0 ] && shift $shifts

[ "$#" = '0' ] && { echo "No pools provided.  Exiting." && exit 4 ; }

i=0

for pool in $@
do
	i=$(( $i + 1 ))
	service_l="${service}${i}"
	message=""
	retcode=0

	feed=$(zpool list -Hp -o name,health,free,frag,cap $pool)
	ret=$?

	if [ $ret -gt 0 ] 
	then
		[ $debug -eq 1 ] && echo "$pool not found, retval was $ret"
		message="$pool not found!"
		retcode=3
	else
		cond=$(printf "%s\n" "$feed" | cut -f 2)
		if [ "$cond" = "ONLINE" ]
		then
			message="$pool ONLINE"
		elif [ "$cond" = "DEGRADED" ]
		then
			retcode=2
			message="$pool DEGRADED"
		elif [ "$cond" = "UNAVAIL" ]
		then
			retcode=2
			message="$pool unavailible"
		else
			retcode=2
			message="$pool is in an unknown non-healthy state - ($cond)"
		fi
	fi

	printf "%s\t%s\t%s\t%s\n" $hostname $service_l $retcode "$message"
	# 0x17 (VTB) is the seperator to submit multiple checks to NSCA
	[ -n "$message_f" ] && message_f=${message_f}$'\x17'
	message_f="${message_f}$hostname	$service_l	$retcode	$message"
done

[ $debug -eq 1 ] && echo $message_f
echo "$message_f" | $multiplexer
