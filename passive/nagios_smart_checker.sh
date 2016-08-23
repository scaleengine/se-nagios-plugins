#!/bin/sh

###############################################################################
###############################################################################
##                       nagios_smart_checker.sh                             ##
## A Nagios passive check that uses the check_smartmon to get data on each   ##
## drive, the submits it as a single check through nsca_multiplexer.sh       ##
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
## V. 1.0.0: Inital version                                         20150813 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
###############################################################################
## Todo: This check has not been implemented, YMMV                           ##
###############################################################################
version="1.0.1"
version_date='2016-07-21'

devlist=""
devtype=""
devname=""
message="OK: all drives report SMART status ok"
errorlist=""
warnlist=""
critlist=""

warn="50"
crit="60"
service="smart_status"
hostname=$(hostname)
perfdata=""
retval=0


while getopts "w:c:s:p:H:hv" opt ; do
	case $opt in
		v)
			echo "$0 version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date"
			exit 0
			;;
		h)
			echo "Usage:\n\t$0 [ -s servicename ] [ -H hostname ] [ -w warn_temp ] [ -c crit_temp ]\n\t$0 -h|-v"
			exit 0
			;;
		s)
			if [ -n $OPTARG ]
			then service=$OPTARG 
			else echo "Option -s requires a service name as an argument" ; exit 4
			fi
			;;
		H)
			if [ -n $OPTARG ]
			then hostname=$OPTARG 
			else echo "Option -H requires a hostname as an argument" ; exit 4
			fi
			;;
		w)
			if [ -n $OPTARG ] && [ $OPTARG -gt 0 ]
			then warn=$OPTARG
			else echo "Option -w requires a positive integer as an argument" ; exit 4
			fi
			;;
		c)
			if [ -n $OPTARG ] && [ $OPTARG -gt 0 ]
			then crit=$OPTARG
			else echo "Option -c requires a positive integer as an argument" ; exit 4
			fi
			;;
	esac
done


devlist=$(smartctl --scan | cut -w -f 1,6 | tr "\t" "#")

for i in $devlist
do
	devname=$(echo $i | cut -d "#" -f 1)
	devtype=$(echo $i | cut -d "#" -f 2 | tr "[:upper:]" "[:lower:]")
	devhname=$(echo $devname | cut -d '/' -f 3)
	echo "$i     $devtype     $devname    $devhname"

	out=$(/usr/local/libexec/nagios/check_smartmon -d $devname -t $devtype -w $warn -c $crit)

	if [ "$(echo $out | cut -w -f 1)" = "WARNING:" ]
	then
		warnlist="$warnlist; $devhname - $(echo $out | cut -w -f 2- | tr "\t" " ")"

		temp=$(echo $out | cut -w -f 4 | tr -d "()")

	elif [ "$(echo $out | cut -w -f 1)" = "CRITICAL:" ]
	then
		critlist="$critlist; $devhname - $(echo $out | cut -w -f 2- | tr "\t" " ")"

		temp=$(echo $out | cut -w -f 4 | tr -d "()")

	else
		temp=$(echo $out | cut -w -f 8 | tr -d ")")

	fi

	perfdata="$perfdata $devhname=$temp;"

done

if [ "$critlist" != "" ]
then
	message="CRITICAL: the following critical errors were found$critlist"
	retval=2
	if [ "$warnlist" != "" ]
	then
		message="$message.  The following warnings were found$warnlist"
	fi
	
elif [ "$warnlist" != "" ]
then
	message="WARNING: the following warnings were found$warnlist"
	retval=1
fi

printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "$retval" "$message | $perfdata"

#WARNING: device temperature (43) exceeds warning temperature threshold (10)
#CRITICAL: device temperature (43) exceeds critical temperature threshold (10)
#OK: device is functional and stable (temperature: 43)

