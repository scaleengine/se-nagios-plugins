#!/bin/sh

###############################################################################
##                              check_zfs.sh                                 ##
## Nagios plugin to check zfs snapshot age                                   ##
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
## V. 1.0.0:  Initial commit                                        20150715 ##
## V. 1.0.1:  Use -r dataset instead of grep, ensure all times are UTC       ##
## V. 1.0.2:  Added dataset (service) name to output data, send unknown      ##
##            values to NSCA                                                 ##
## V. 1.0.3:  Use nsca_multiplexer instead of handling NSCA ourselves        ##
## V. 1.0.4: Release under ISC license                              20160721 ##
###############################################################################
version="1.0.4"
version_date='2016-07-21'

program=$(basename $0)

hostname=$(hostname)
sender=$(which send_nsca)
zfs_cmd=$(which zfs)
now=$(date -u +%s)
multiplexer=$(which nsca_multiplexer.sh)
age=""
deltat=""
code=""
htime=""
i=""
s=""

warn=""
crit=""
zfsname=""
service=""
output=""

printhelp () {

echo "  $program Usage:"
echo "  $0 -h"
echo "                  Print this help and exit"
echo ""
echo "  $0 -v "
echo "                  Print program version and exit"
echo ""
echo "  $0 -H nsca_hostname -n nsca_configfile -w warn_age -c crit_age \\"
echo "     -s service_name -z zfs_set_name [ -H2 nsca_hostname_2 [ -n2 nsca_config_2 ]]"
echo "                  Get the age of \`filename' and report it back to Nagios"
echo "                  All ages are in seconds"

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
                -z)
                        zfsname=$2
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

#{ [ -z $service ] || [ -z $nscahost ] || [ -z $nscaconf ] || [ -z $warn ] || [ -z $crit ] || [ -z $zfsname ] ; } && printhelp && exit 4
{ [ -z $service ] || [ -z $warn ] || [ -z $crit ] || [ -z $zfsname ] ; } && printhelp && exit 4


##### MAIN PART ####

# Sanity checks

[ $(echo "$sender" | wc -w | cut -f 2 -w) -ne 1 ] && echo -e "send_nsca not found in \$PATH [$PATH]\nFix this and try again." && exit 5

[ $(echo "$zfs_cmd" | wc -w | cut -f 2 -w) -ne 1 ] && echo -e "zfs not found in \$PATH [$PATH]\nFix this and try again." && exit 5

if [ $(zfs list $zfsname | wc -l | cut -w -f 2) -ne 2 ] 
then
	echo "Error: Dataset to be checked, $zfsname does not exist.  Exiting." 
	code="3"
	output="$service - UNKNOWN: Dataset not found"
	printf "%s\t22\t%s\t%s\n" "$hostname" "$service" "$code" "$output" | $multiplexer
	exit $code 
fi

#### Get snapshot age #####

s=$(zfs list -t snapshot -o name -H -d 1 $zfsname | tail -n 1 | cut -d '@' -f 2)

s="$s-00"

deltat=$(date -j -u -f "auto-%Y-%m-%d_%H.%M-%S" "$s" +%s)

age=$(($now - $deltat))

# generate human readable time string

i=$age

s=$(($i % 60))
i=$(($i/60))
m=$(($i % 60))
h=$(($i/60))

htime="$h hours $m minutes $s seconds"

output="$service - Dataset age: $htime | $service=$age"


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
		output="$service - UNKNOWN:  Age measurement failed, check your arguments"
		code="3"
fi

printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "$code" "$output" | $multiplexer

exit $code
