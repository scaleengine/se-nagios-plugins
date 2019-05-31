#!/bin/sh
###############################################################################
###############################################################################
##                        check_ns_slave.sh                                  ##
## Checks the serial of a zone against the master                            ##
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
## V. 1.0.0: Initial version                                        20160715 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
## V. 1.1.0: fix host command for getting master serial             20190531 ##
###############################################################################
version='1.1.0'
version_date='2019-05-31'

###############################################################################
## Global variables
###############################################################################

host=''
zone=''
verbose=0
line=''
master=''
serial=''
mserial=''
mline=''
diff=-1
warn=1
crit=2

##############################################################################
## Getopts
##############################################################################


while getopts "w:c:H:z:vhV" opt
do
	case $opt in
		V)	echo "$0 version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date"
			;;
		h)	echo "Usage: $0 [-v] -H host -z zone [-w warn] [-c crit]"
			;;
		z)	zone=$OPTARG
			;;
		H)	host=$OPTARG
			;;
		v)	verbose=1
			;;
		w)	warn=$OPTARG
			;;
		w)	crit=$OPTARG
			;;
	esac
done

if [ "$zone" = '' -o "$host" = '' ] 
then
	echo "-z and -H are mandatory"
	exit 3
fi


##############################################################################
## Main program
##############################################################################

line=$(host -s -t SOA $zone $host | tail -n 1)
[ $verbose -gt 0 ] && echo "got response: $line"
if [ "$line" = '' ] 
then 
	echo "ZONE: CRITICAL: could not contact server"
	exit 2
fi
master=$(echo $line | cut -d ' ' -f 5)
[ $verbose -gt 0 ] && echo "master for zone is $master"
serial=$(echo $line | cut -d ' ' -f 7)
[ $verbose -gt 0 ] && echo "serial for zone is $serial"

mline=$(host -s -t SOA $zone $master | tail -n 1)
[ $verbose -gt 0 ] && echo "got response from master: $mline"
if [ "$mline" = '' ] 
then 
	echo "ZONE: CRITICAL: could not contact master"
	exit 2
fi
mserial=$(echo $mline | cut -d ' ' -f 7)
[ $verbose -gt 0 ] && echo "serial for master is $mserial"

diff=$(($mserial - $serial))
[ $verbose -gt 0 ] && echo "difference in zones is $diff"

echo "ZONE: $zone is $diff versions from master $master|serial=$serial mserial=$mserial diff=$diff ;$warn;$crit;;"

if [ $diff -ge $crit ] 
then 
	exit 2
elif [ $diff -ge $warn ] 
then 
	exit 1
elif [ $diff -lt $warn ]
then
	exit 0
else 
	exit 3
fi
