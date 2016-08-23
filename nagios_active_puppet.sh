#!/bin/sh

###############################################################################
###############################################################################
##                         nagios_active_puppet.sh                           ##
## Checks a puppetmaster's REST API to see if it is running                  ##
## Known to work with puppet 3.7.x and 3.8.x                                 ##
## Note: requires a certificate pair from the puppetmaster in                ##
## /var/spool/nagios/ssl/                                                    ##
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
## V. 1.0.0  Initial release                                        20150722 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
###############################################################################
## TODO:                                                                     ##
## Improve SSL cert finding.                                                 ##
###############################################################################
version="1.0.1"
version_date='2016-07-21'

###############################################################################
## Global Variables
###############################################################################

hostname=$(hostname)
target=""
curl=$(which curl)
private="/var/spool/nagios/ssl/$hostname.private.pem"
cert="/var/spool/nagios/ssl/$hostname.cert.pem"
ca_cert="/var/spool/nagios/ssl/ca.pem"

response=""
status=""

###############################################################################
## Function declarations
###############################################################################

printversion ()
{
	echo "$0 version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date"
}

printhelp ()
{
	printversion
	echo -e "Usage:\n\t$0 -H puppetmaster.hostname.tld"
}

###############################################################################
## Getopts
###############################################################################

while getopts "H:hv" opt; do
	case $opt in
		H)
			target=$OPTARG
			;;
		h)
			printhelp
			exit 3
			;;
		v)
			printversion
			exit 3
			;;
	esac
done

[ "$curl" = "" ] && { echo "ERROR: curl not found in \$PATH" ; exit 3 ; }
[ -z $target ] && { echo "ERROR: No puppetmaster to check was specified.  Exiting" ; exit 3 ; }
[ -r $private -a -r $cert -a -r $ca_cert ] || { echo "ERROR: One or more of the SSL certificates for this host were not found or are not readable by this user.  Exiting" ; exit 3 ; }

###############################################################################
## Main Program
###############################################################################

response=$($curl -sS --request GET --cert $cert --key $private --cacert $ca_cert -H 'Accept: pson' "https://$target:8140/production/status/$hostname")

status=$(echo $response | sed s/{// | sed s/}// | tr ',' "\n" | grep "is_alive" | cut -d : -f 2)

if [ $status ]
then
	echo "OK: Puppetmaster returned $response"
	exit 0
else
	echo "CRITICAL: Puppetmaster returned $response"
	exit 2
fi
