#!/bin/sh
# Nagios plugin to monitor Puppet agent state
#
# Copyright (c) 2011 Alexander Swen <a@swen.nu>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
#
# Example configuration
#
# Typical this check is placed on a client and runs via nrpe
# So add this to nrpe.cfg:
#  command[check_puppet_agent]=/usr/lib/nagios/plugins/check_puppet -w 3600 -c 7200 -s /var/lib/puppet/state/last_run_summary.yaml -d 0
# This should warn when the agent hasnt run for an hour and go critical after two hours
#  if you have dont_blame_nrpe=1 set you can choose to
#  command[check_puppet_agent]=/usr/lib/nagios/plugins/check_puppet -w $ARG1$ -c $ARG2$ -s $ARG3$ -d $ARG4$
#
# define service {
#  use generic-service
#  service_description Puppet agent
#  check_command check_nrpe!check_puppet_agent
# or
#  check_command check_nrpe!check_puppet_agent!3600!7200
#}
#
# CHANGELOG:
# 20120126	A.Swen	    created.
# 20120214  trey85stang Modified, added getopts, usage, defaults
# 20120220  A.Swen      lastrunfile can be overriden
# 20130717  A.Swen      Moved finding lastrunfile to after getopts and made it conditional to param -s
#                       Added option to tell script if puppet agent is started from cron or as a daemon (-d)
#                       Switched to use awk to filter values from lastrunfile and set them as params
#                       Updated some comments
#                       Removed bug in search for process (that would previously always find something because grep find it's processline)
#                       "puppet config print lastrunfile" has to be run as root. As normal user it yields ~/.puppet/var/state.
#                       Based on feedback Михайло Масик updated:
#                       - Puppet --configprint => puppet config print (version 3 has new way of printing config)
#                       - Added new pattern to search for process
#                       - Added test kill -0 to see if process is still there
# 20130725  A.Swen      Based on feedback Михайло Масик updated a test (removed ! from test)
# 20130725  A.Swen      Added sudo to puppet config print pidfile.
# 20131209  Mark Ruys   Issue warning when last_run_report.yaml contain errors.
# 20141015  A.Swen      Add show disabled status.
# 20141127  KissT       Remove requirement to have sudo custom rule 
#
# Andrew Fengler
# Some changes to make this script work with FreeBSD
# 2015-07-09   Changed references to `/usr/bin/puppet' to `$PUPPET'
#              removed unnecesary sudo calls
#              Removed unnecesary extra steps with the pidfile
#              Made the date call work on FreeBSD
#              Changed interpreter to /bin/sh
#              Set check to submit passively
# 2015-07-21   Added puppet runtime to perfdata and message
# 2015-07-23   Changed passive check to run through nsca_multiplexer.sh
# 2016-03-04   Added selection structures to allow date and paths to work on both FreeBSD and Linux
#              Fixed time_taken check to use awk
# 2016-04-05   Added perfdata to warning and critical states (results 2,3,6)
#              Moved result 2 and 3 to after yaml parsing
# 2019-02-07   Fix puppet config print command to use --section agent so you actually get the agent's pid
#              Try a couple different possible pidfile locations to avoid relying on puppet config print


# SETTINGS
CRIT=7200
WARN=3600
service=""
hostname=$(hostname)
multiplexer=$(which nsca_multiplexer.sh)

# FUNCTIONS
result () {
  case $1 in
    0) output="OK: Puppet agent ${version} running catalogversion ${config} executed at ${last_run_human} for ${time_taken} seconds | lastrun=${last_run};timetaken=${time_taken}";rc=0 ;;
    1) output="UNKNOWN: last_run_summary.yaml not found, not readable or incomplete";rc=3 ;;
    2) output="WARNING: Last run was ${time_since_last} seconds ago. warn is ${WARN} | lastrun=${last_run};timetaken=${time_taken}";rc=1 ;;
    3) output="CRITICAL: Last run was ${time_since_last} seconds ago. crit is ${CRIT} | lastrun=${last_run};timetaken=${time_taken}";rc=2 ;;
    4) output="CRITICAL: Puppet daemon not running or something wrong with process";rc=2 ;;
    5) output="UNKNOWN: no WARN or CRIT parameters were sent to this check";rc=3 ;;
    6) output="CRITICAL: Last run had 1 or more errors. Check the logs | lastrun=${last_run};timetaken=${time_taken}";rc=2 ;;
    7) output="DISABLED: Reason: $(sed -e 's/{"disabled_message":"//' -e 's/"}//' ${agent_disabled_lockfile})";rc=3 ;;
  esac
  #exit $rc
  #printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "$rc" "$output" | /usr/local/sbin/send_nsca -H monitor2.scaleengine.net -c /usr/home/nagmon/send_nsca.cfg
  printf "%s\t%s\t%s\t%s\n" "$hostname" "$service" "$rc" "$output" | $multiplexer
  echo "Success! - $output"
  exit 0
}

usage () {
  echo ""
  echo "USAGE: "
  echo "  $0 -s service [-w 3600] [-c 7200] [-s lastrunfile] [-d0] [-H hostname]"
  echo "    -s service_name"
  echo "    -w warning threshold (default 3600 seconds)"
  echo "    -c critical threshold (default 7200 seconds)"
  echo "    -r lastrunfile (default: /var/lib/puppet/state/last_run_summary.yaml)"
  echo "    -l agent_disabled_lockfile (default: /var/lib/puppet/state/agent_disabled.lock)"
  echo "    -d 0|1: puppet agent should be a daemon(1) or not (0).(default 1)"
  echo ""
  exit 1
}

while getopts "c:d:s:w:H:l:r:" opt; do
  case $opt in
    c)
      if ! echo $OPTARG | grep -q "[A-Za-z]" && [ -n "$OPTARG" ]
      then
        CRIT=$OPTARG
      else
        usage
      fi
    ;;
    d)
      # argument should be 0 or 1
      if [ ${OPTARG} -eq 0 -o ${OPTARG} -eq 1 ];then
        daemonized=${OPTARG}
      else
        usage
      fi
    ;;
    r) lastrunfile=${OPTARG} ;;
    l) agent_disabled_lockfile=${OPTARG} ;;
    w)
      if ! echo $OPTARG | grep -q "[A-Za-z]" && [ -n "$OPTARG" ]
      then
        WARN=$OPTARG
      else
        usage
      fi
    ;;
	s) service=$OPTARG ;;
	H) hostname=$OPTARG ;;
    *)
      usage
    ;;
  esac
done


PUPPET=$(which puppet)


# If there's a disabled.lock file don't look any further.
[ -z "${agent_disabled_lockfile}" ] && agent_disabled_lockfile=$($PUPPET config print agent_disabled_lockfile)
[ -f "${agent_disabled_lockfile}" ] && result 7

if [ "$(uname)" = "Linux" ]
then
	lastrunfile="/var/lib/puppet/state/last_run_summary.yaml"
elif [ "$(uname)" = "FreeBSD" ]
then
	lastrunfile="/var/puppet/state/last_run_summary.yaml"
fi
# if the lastrunfile is not given as a param try to find it ourselves
[ -z "${lastrunfile}" ] && lastrunfile=$($PUPPET config print lastrunfile)
# check if state file exists
[ -s ${lastrunfile} -a -r ${lastrunfile} ] || result 1

# check if daemonized was sent, else set default
[ -n "${daemonized}" ] || daemonized=1
# if Puppet agent runs as a daemon there should be a process. We can't check so much when it is triggered by cron.
if [ ${daemonized} -eq 1 ];then
  pidfile=/var/run/puppet/agent.pid
  [ -f ${pidfile} ]||pidfile=/var/lib/puppet/run/agent.pid
  # This will probably lie to you if you're not root
  [ -f ${pidfile} ]||pidfile=$($PUPPET config print pidfile --section agent)
  # if there is a pidfile tell me the pid, else fail
  [ -f ${pidfile} ]&&pid=$(cat ${pidfile})||result 4

  # see if the process is running
  #[ "$(ps -p ${pid} | wc -l)" = "2" ] ||result 4
  # test if the pid we found in the pidfile is puppet:
  #grep -q puppet /proc/${pid}/cmdline ||result 4
fi

# check when last run happened
last_run=$(awk '/last_run:/ {print $2}' ${lastrunfile})
#last_run_human=$(date -d @${last_run} +%c)
if [ "$(uname)" = "Linux" ]
then
	last_run_human=$(date -d @${last_run} +%c)
elif [ "$(uname)" = "FreeBSD" ]
then
	last_run_human=$(date -j -f %s ${last_run} +%c)
fi
now=$(date +%s)
time_since_last=$((now-last_run))

# get some more info from the yaml file
config=$(awk '/config:/ {print $2}' ${lastrunfile})
version=$(awk '/puppet:/ {print $2}' ${lastrunfile})
failed=$(awk '/failed:/ {print $2}' ${lastrunfile})
failure=$(awk '/failure:/ {print $2}' ${lastrunfile})
failed_to_restart=$(awk '/failed_to_restart:/ {print $2}' ${lastrunfile})
#i=$(grep -n 'time: $' /var/puppet/state/last_run_summary.yaml | cut -d : -f 1 )
time_taken=$(awk '/total:/ {print $2 }' ${lastrunfile} | sed -n 2p )

[ ${time_since_last} -ge ${CRIT} ] && result 3
[ ${time_since_last} -ge ${WARN} ] && result 2

# if any of the values above doesn't return raise an error
[ -z "${last_run}" -o -z "${config}" -o -z "${version}" -o -z "${failed}" -o -z "${failure}" -o -z "${failed_to_restart}" ] && result 1
# if anything went wrong last run => crit
[ ${failed} -gt 0 -o  ${failure} -gt 0 -o ${failed_to_restart} -gt 0 ] && result 6

# if we come here it works!
result 0

# END

