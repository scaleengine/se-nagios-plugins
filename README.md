# se-nagios-plugins
ScaleEngine's Custom Nagios Plugins

Our nagios plugins we've developed to monitor our infrastructure.  All are known to work on nagios 4.1.1, though they should all work on 3.x.x.

All passive checks run through our nsca_multiplexer.sh script, that submits check results to multiple nagios servers via NSCA.  Obviously, this requires NSCA functioning on both the servers and the client.

Most of our checks offer help text if run with -h.  If it doesn't, it's usually short enough to read easily.

Unless otherwise specified, all scripts are freely available under a permissive licence (ISC).  Copyright and licences are in the top of each script.

## Active Checks

Active checks are known to work on FreeBSD 9.3 - 11.0 RC1

### check_network_status.pl 

Checks the link speed of a given NIC.  Will throw an error in nagios if one of your NICs has decided to not work as hard as it should be.

### check_ns_slave.sh 

Compares the serial number of a DNS slave against the master for a zone.

### check_rpdu_load.pl 

Checks the load on an APC rPDU.  Werks for our device ("apc854262" according to SNMP OID enterprises.318.1.1.12.1.1.0), YYMV.  

Requires Net-SNMP

### get_bytes.php 

Connects to an RTG's MySQL database and gets bandwidth quota usage information.  The code is a bit of a mess.

Requires PHP and  MySQL dbd

### influx_stats.pl

Pulls status information from influxdb.  Checks heap memory usage.

### nagios_active_puppet.sh 

Uses the REST API to check if a puppetmaster is running.  Works with Puppet 3.x.x, has not been tested against 4.x.x

## Passive Checks 

Passive checks run through NSCA (use nsca_multiplexer.sh by default)

Checks are known to work on FreeBSD 9.3 - 11.0 RC1, some are tested on CentOS 7.

check_gpu_stats.pl is only tested on CentOS 7.

### bind_stats.pl 

Gets the output of 'rndc stats' and submits to nagios.

### check_carp.pl

Checks the status of CARPed IPs.  Makes sure they are up and in the desired state (master/slave).  Because this check relies on parsing ifconfig, it will only work on FreeBSD.

### check_denyhosts.pl 

Gets a count of the number of IP's blocked by denyhosts

### check_gpu_stats.pl 

Gets utilization information from nvidia-smi.  Known to work with a Grid K20, K4000, and M4000

### check_java_threads.pl

Gets a stack dump of a matching java process with jstack, and reports the states of the threads.  Will warn/crit if too many threads are blocked.

### check_mdadm.pl

Gets the status of all md devices on the host.  Works on CentOS 7, should work on any linux AFAIK.

Requires a wrapper around mdadm --status to run as non-priviledged user, see the bottom of the script for an example.

### check_nagiostats.pl 

Parses the output of nagiostats and submits as a passive check.  Note that this must be run on the nagios server itself.  Running it passively is done to get stats from other nagioses via the multiplexer.

### check_process_cpu.pl

Gets cpu usage information out of procstat for a named process.  Can use sudo to run as non-root, but monitor processes belonging to root.  Uses --libxo options that require FreeBSD 10+ if run on FreeBSD.  Uses /proc on Linux.

### check_puppet.sh 

Parses puppet's last_run_state.yaml file to determine if the run failed.  Note that puppet occasionally mangles this file for no discernable reason so you will in all likelyhood get intermittent false negatives.

This check is not our original work.  The author is Alexander Swen (a@swen.nu).  We've modified it to run as a passive check, and to work on FreeBSD in keeping with the terms of the original licence (ISC)

### check_smart.pl

Checks the output of smartctl and reports it to nagios

### nagios_file_age_check.sh 

Checks the age of a file using stat, warns if the mtime is too old.  Useful for watching replication by changing a file on the master from cron, and watching the age on the slave.

### nagios_passive_wrapper.sh 

Runs a regular nagios check and reformats the output to feed to nsca_multiplexer.sh

### nagios_smart_checker.sh 

Checks SMART information on drives.  This check has yet to be used in production, so it may or may not work as described.

### nagios_zfs_snapshot_check.sh 

Checks the age of a zfs snapshot.  This check has yet to be used in production, so it may or may not work as described.

### nagios_zpool_status_passive.sh 

Checks on the health of a zpool.

### netspeed_passive.pl

Checks the speed of an interface.  Will report the aggregate speed of an LACP interface.
Created because net-snmp sometimes fails to report when an interface is negotiated to reduced speed.

### nsca_multiplexer.sh 

The multiplexer.  Given a list of servers, will send a check via NSCA to each.  Expects nsca.cfg to be in the current user's home directory.

### passive_coretemp.sh 

Gets coretemp information.  Requires 'lm-sensors' on CentOS 7

### vsnping.pl 

Pings every server in a list of servers, then submits each ping as a seperate ICMP check to nagios.
