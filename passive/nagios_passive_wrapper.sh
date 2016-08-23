#!/bin/sh

###############################################################################
###############################################################################
##                       nagios_passive_wrapper.sh                           ##
## Runs a nagios check, then formats and feeds the output to                 ##
## nsca_multiplexer.                                                         ##
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
## V. 1.0.0: Initial release                                        20150723 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
###############################################################################


multiplexer=$(which nsca_multiplexer.sh)
hostname=$(hostname)

service=$( echo "$*" | cut -d % -f 1)
cmd=$( echo "$*" | cut -d % -f 1)

output=$($cmd)
extcode=$?

printf "%s\t%s\t%s\t%s" "$hostname" "$service" "$extcode" "$output" | $multiplexer
