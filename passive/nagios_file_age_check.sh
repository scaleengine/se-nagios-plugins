#!/bin/sh

###############################################################################
###############################################################################
##                        Nagios_file_age_check.sh                           ##
## Nagios plugin to monitor file age                                         ##
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
## V. 1.0.0: Initial write                                          20150713 ##
## V. 1.0.2: Fixed formatting and sanity checks                              ##
## V. 1.0.3: Added service name to output                                    ##
## V. 1.0.4: Use nsca_multiplexer.sh instead of doing it ourselves           ##
## V. 1.0.5: Release under ISC license                              20160721 ##
###############################################################################
version="1.0.5"
version_date='2016-07-21'

program=$(basename $0)

hostname=$(hostname)
#sender=$(which send_nsca)
multiplexer=$(which nsca_multiplexer.sh)
now=$(date +%s)
age=""
mtime=""
code=""
htime=""
i=""

warn=""
crit=""
filename=""
service=""
output=""

printhelp () {

echo "	$0 Usage:"
echo "	$0 -h"
echo "			Print this help and exit"
echo ""
echo "	$0 -v "
echo "			Print program version and exit"
echo ""
echo "	$0 -w warn_age -c crit_age -s service_name -f filename"
echo "			Get the age of \`filename' and report it back to Nagios"
echo "			All ages are in seconds"
echo ""

}



##### GETOPTS #####

while test -n "$1"; do

	case "$1" in

		-[vV])
			echo "$program version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date"
			exit 4
			;;
		-w)
			warn=$2
			;;
		-c)
			crit=$2
			;;
		-f)
			filename=$2
			;;
		-s)
			service=$2
			;;
		*)
			printhelp
			exit 4
			;;

	esac

	shift 2

done

# ensure all options were recieved

{ [ -z $service ] || [ -z $warn ] || [ -z $crit ] || [ -z $filename ] ; } && printhelp && exit 4


##### MAIN PART ####

# Sanity checks

[ $warn -gt 0 ] || { echo "The -w argument must be followed by a non-zero integer for a warning value" && exit 5 ; }

[ $crit -gt 0 ] || { echo "The -c argument must be followed by a non-zero integer for a critical value" && exit 5 ; }

# Once we know we have nsca, check file's existance.  Return unknown to nagios if not found.
if [ ! -e $filename ]
then
	echo "Error: File to be checked, $filename does not exist.  Exiting."
	output="$service - UNKNOWN: File $filename not found"
	printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "3" "$output" | $multiplexer
	exit 4
fi


##### Arithmetic #####

# Get file age

mtime=$(stat -f %m $filename)
age=$(($now - $mtime))

# generate human readable time string

i=$age

s=$(($i % 60))
i=$(($i/60))
m=$(($i % 60))
h=$(($i/60))

htime="$h hours $m minutes $s seconds"

output="$service - File age: $htime | $service=$age"


if [ $age -lt $warn ]
then 
	code=0
elif [ $age -lt $crit ] 
then 
	code=1
elif [ $age -ge $crit ]
then
	code=2
else
	echo -e "Age measuring arithmetic failed, an invalid option seems to have slipped through sanity checks\nPlease review your command options and try again" 
	code=3
	output="$service - UNKNOWN:  Age measurement failed, check your arguments"
fi


##### Send results to NSCA #####

printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "$code" "$output" | $multiplexer

exit $code
