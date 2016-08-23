#!/bin/sh

###############################################################################
###############################################################################
##                         nsca_multiplexer.sh                               ##
## Submits a passive check to multiple NSCA servers                          ##
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
## V. 1.0.0: Inital release                                         20150721 ##
## V. 1.0.1: Added newline to work with older nsca_client's         20160315 ##
## V. 1.0.2: Fixed printf to not choke on %'s                       20160321 ##
## V. 1.0.3: Release under ISC license                              20160721 ##
###############################################################################

#Get the data we've been piped
input=$(cat)

#space seperated list of Nagioses with $suffix ommitted
nagioses="monitor1 monitor2 monitor3"

suffix="example.tld"
cmd=$(which send_nsca)
conf="/$HOME/send_nsca.cfg"

[ -x $cmd ] || ( echo "send_nsca not found.  Exiting" && exit 3 )
[ -r $conf ] || ( echo "send_nsca.cfg not found in $HOME  Exiting" && exit 3 )

for nagios in $nagioses
do
	printf "%s\n" "$input" | $cmd -H $nagios.$suffix -c $conf
done
