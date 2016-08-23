<?php

###############################################################################
###############################################################################
##                               get_bytes.php                               ##
## Checks bandwidth used since last rollover date and returns a percentage,  ##
## with dynamically gernerated warn and critical values.  Information is     ##
## pulled from an RTG MySQL database.                                        ##
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
## V. 1.0.0:  Initial version.                                      20150724 ##
## V. 1.0.1: Release under ISC license                              20160721 ##
###############################################################################
## TODO:                                                                     ##
## Set MySQL username and password with a variable rather than hardcoded     ##
###############################################################################
$version = "1.0.1";
$version_date = '2016-07-21';


class get_bytes
{
	protected $sqldb;

	function __construct()
	{
	}

	function next_rollover($rollover_day) {
        	$now = time();
        	$next = strtotime(date('Y-m-').$rollover_day);
        	if ($next > $now) {
        	        return strtotime('-1 month', $next);
        	} else {
        	        return $next;
        	}
	}

	public function run($host, $interface, $direction, $rollover)
	{
		$upbytes = 0;
		$downbytes = 0;


		// find timestamp of last rollover date
		$lastrollover = $this->next_rollover($rollover);
		
		// Connect to the database
		// XXX Set username and password here
		echo "XXX Set the username and password for the database, then comment out this line\n"; exit(99);
		$this->sqldb = new PDO("mysql:host=127.0.0.1;dbname=rtg;charset=utf8",
					"USERNAME",
					"PASSWORD",
					array(
						PDO::ATTR_TIMEOUT => 5,
						PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
					));

		// Get RID from the hostname, then get the interface id of the specified interface on that host
		//
		$ridget = $this->sqldb->prepare("SELECT rid FROM router WHERE name = :host");
		$ridget->bindValue(':host', "$host", PDO::PARAM_STR);
		$ridget->execute();
		$arr_router = $ridget->fetch(PDO::FETCH_ASSOC);
		$rid = intval($arr_router['rid']);

		$idget = $this->sqldb->prepare("SELECT id FROM interface WHERE rid = :rid AND name = :name");
		$idget->bindValue(':rid', $rid, PDO::PARAM_INT);
		$idget->bindValue(':name', $interface, PDO::PARAM_STR);
		$idget->execute();
		$arr_interface = $idget->fetch(PDO::FETCH_ASSOC);
		$ifid = intval($arr_interface['id']);

		//Fetch the byte total for each direction (if we care about that direction) since the last rollover
		//
		if ( $direction == "up" || $direction == "both" )
		{
			$upbytesget = $this->sqldb->prepare("SELECT SUM(`counter`) as bw FROM ifOutOctets_{$rid} WHERE id = :if and UNIX_TIMESTAMP(`dtime`) > :lastroll");
			$upbytesget->bindValue(':if', $ifid, PDO::PARAM_INT);
			$upbytesget->bindValue(':lastroll', $lastrollover, PDO::PARAM_INT);
			$upbytesget->execute();
			$arr_upbytes = $upbytesget->fetch(PDO::FETCH_ASSOC);
			$upbytes = intval($arr_upbytes['bw']);
		}

		if ( $direction == "down" || $direction == "both" )
		{
			$downbytesget = $this->sqldb->prepare("SELECT SUM(`counter`) as bw FROM ifInOctets_{$rid} WHERE id = :if and UNIX_TIMESTAMP(`dtime`) > :lastroll");
			$downbytesget->bindValue(':if', $ifid, PDO::PARAM_INT);
			$downbytesget->bindValue(':lastroll', $lastrollover, PDO::PARAM_INT);
			$downbytesget->execute();
			$arr_downbytes = $downbytesget->fetch(PDO::FETCH_ASSOC);
			$downbytes = intval($arr_downbytes['bw']);
		}

		// Close database handles
		
		$this->sqldb = null;

		return array("up" => $upbytes, "down" => $downbytes);
	}

	public function output ($upbytes, $downbytes, $quota, $rollover, $warn, $crit)
	{

		$lastrollover = $this->next_rollover($rollover);
		// This gets the last rollover date
		$lastroll = date("Y-m-d", $lastrollover);

		$upgb = ( $upbytes / 1024 / 1024 / 1024 );
		$downgb = ( $downbytes / 1024 / 1024 / 1024 );

		$bytes = $upbytes + $downbytes;
		$gb = $upgb + $downgb;
		$percentage = ( $gb / $quota * 100 );
		
		// Set warn/crit if needed
		//
		if ( $percentage > $crit )
		{
			$retval = 2;
			$retstr = "CRITICAL: ";
		}
		elseif ( $percentage > $warn )
		{
			$retval = 1;
			$retstr = "WARNING: ";
		}
		elseif ( $percentage <= $warn )
		{
			$retval = 0;
			$retstr = "OK: ";
		}
		else
		{
			$retval = 3;
			$retstr = "UNKNOWN: ";
		}

		//round off
		//Quota changes from GB to B here, use quotagb from now on
		$quotagb = $quota;
		$quota = ( $quota * 1024 * 1024 * 1024 );
		$upgb = round($upgb);
		$downgb = round($downgb);
		$gb = round($gb);
		$bytes = round($bytes);
		$percentage = round($percentage);
		$warnb = round((( $warn / 100 ) * $quota ));
		$critb = round((( $crit / 100 ) * $quota ));

		echo "$retstr Since $lastroll this server has used $percentage% of its quota ($gb/$quotagb GB, $downgb GB down, $upgb GB up).  Warn at $warn%, Critical at $crit%. | used=$bytes;quota=$quota;warn=$warnb;crit=$critb;\n";
		return $retval;
	}

	function printhelp ()
	{
		global $argv;
		$name = $argv['0'];
		$this->printversion();
		print "Usage:\n\n";
		print "$name [ -h | --help ]\n\tPrint help and exit\n\n";
		print "$name [ -v | -V | --version ]\n\tPrint version info and exit\n\n";
		print "$name { -H hostname -i interface -r rollover_date } [ -d direction ] [ -q quota_GB ]\n";
		print "\t[ -w { warn% | dyn } [ --wb dyn_warnbuffer% ] [ --wp dyn_warnplay% ] ]\n";
		print "\t[ -c { crit% | dyn } [ --cb dyn_critbuffer% ] [ --cp dyn_critplay% ] ]\n";
		print "\nIf 'dyn' is selected for either warn or crit, the play and buffer settings can be used\n";
		print "Dynamic warn/crit is set to ( 100/# of days in the month ) * day\n";
		print "Buffer is a reserved amount of bandwidth, i.e on the last day of the month value will be 100 - buffer\n";
		print "Play is an amount added at the start of the month for some extra wiggle room\n";
		print "The full formula is: (((100 - play - buffer)/days_in_month) * day_of_month ) + play\n";
	}

	function printversion ()
	{
		global $argv;
		$name = $argv['0'];
		global $version;
		global $version_date;
		print "$name version $version by Andrew Fengler (andrew.fengler@scaleengine.com), $version_date\n";
	}

	public function parse ( $opts )
	{
		if ( array_key_exists('h', $opts) || array_key_exists('help', $opts) )
		{
			$this->printhelp();
			exit(3);
		}
		elseif ( array_key_exists('v', $opts) || array_key_exists('V', $opts) || array_key_exists('version', $opts) )
		{
			$this->printversion();
			exit(3);
		}

		if ( array_key_exists('H', $opts) )
		{}
		else
		{
			echo "Required parameter -H hostname not found, exiting.\n";
			exit(3);
		}

		if ( array_key_exists('i', $opts) )
		{}
		else
		{
			echo "Required parameter -i not found, exiting.\n";
			exit(3);
		}

		if ( array_key_exists('r', $opts) )
		{
			if ( intval($opts['r']) < 1 || intval($opts['r']) > 31 ) { echo "Invald date for argument -r, use a 2 digit day of the month, exiting.\n"; exit(3); }
		}
		else
		{
			echo "Required parameter -r not found, exiting.\n";
			exit(3);
		}

		if ( array_key_exists('d', $opts) )
		{
			if ($opts['d'] != "up" && $opts['d'] != "down" && $opts['d'] != "both"){ echo "Invalid direction for argument -d, use 'up', 'down', or 'both'\n"; exit(3); }
		}
		else
		{
			$opts['d'] = "both";
		}

		if ( array_key_exists('q', $opts) )
		{
			if ( intval($opts['q']) < 1 ) { echo "Invalid quota for argument -q, enter a integer (gigabytes)\n"; exit(3); }
		}
		else
		{
			$opts['q'] = "10000";
		}

		if ( array_key_exists('w', $opts) )
		{
			if ( $opts['w'] != "dyn" && ( intval($opts['w']) < 1 || intval($opts['w']) > 100 ) ) { echo "Invalid value for -w, enter either 'dyn' or an integer between 1 and 100 (percent)\n"; exit(3); }
		}
		else
		{
			$opts['w'] = "dyn";
		}

		if ( array_key_exists('c', $opts) )
		{
			if ( $opts['c'] != "dyn" && ( intval($opts['c']) < 1 || intval($opts['c']) > 100 ) ) { echo "Invalid value for -c, enter either 'dyn' or an integer between 1 and 100 (percent)\n"; exit(3); }
		}
		else
		{
			$opts['c'] = "dyn";
		}

		if ( array_key_exists('wb', $opts) )
		{
			
			if ( intval($opts['wb']) < 1 || intval($opts['wb']) > 100 ) { echo "Invalid value for -wb, enter an integer between 1 and 100 (percent)\n"; exit(3); }
		}
		else
		{
			$opts['wb'] = "25";
		}
	
		if ( array_key_exists('wp', $opts) )
		{
			
			if ( intval($opts['wp']) < 1 || intval($opts['wp']) > 100 ) { echo "Invalid value for -wp, enter an integer between 1 and 100 (percent)\n"; exit(3); }
		}
		else
		{
			$opts['wp'] = "5";
		}
	
		if ( array_key_exists('cb', $opts) )
		{
			
			if ( intval($opts['cb']) < 1 || intval($opts['cb']) > 100 ) { echo "Invalid value for -cb, enter an integer between 1 and 100 (percent)\n"; exit(3); }
		}
		else
		{
			$opts['cb'] = "10";
		}
	
		if ( array_key_exists('cp', $opts) )
		{
			
			if ( intval($opts['cp']) < 1 || intval($opts['cp']) > 100 ) { echo "Invalid value for -cp, enter an integer between 1 and 100 (percent)\n"; exit(3); }
		}
		else
		{
			$opts['cp'] = "10";
		}

		return $opts;
	
	}

	public function dyngen ($buff, $play, $roll)
	{
		$lastroll = $this->next_rollover($roll);
		
		$dtot = intval(date("t", $lastroll));
		$dcur = intval(( ( ( time() - $lastroll ) / ( 60 * 60 * 24 ) ) + 1 ));

		$b = intval($buff);
		$p = intval($play);

		$ret = intval(( ( ( 100 - $b - $p ) * ( $dcur / $dtot ) ) + $p ));

		return $ret;
	}

}
date_default_timezone_set('UTC');

// Default values
$host = "";
$direction = "";					//Which direction to measure trafic in - upload, download, or both
$interface = "";					//interface will be passed by nagios
$rollover = "";						//Date the quota rolls over
$quota = "";						//Quota in GB
$warnmode = "";
$warnbuff = 0;
$warnplay = 0;
$critmode = "";
$critbuff = 0;
$critplay = 0;

$fw = new get_bytes();

$opts = getopt("hvVH:d:i:r:q:w:c:", array("version","help","wb:","wp:","cb:","cp:"));
$args = $fw->parse($opts);

$host = $args['H'];
$direction = $args['d'];
$interface = $args['i'];
$rollover = $args['r'];
$quota = $args['q'];
$warnmode = $args['w'];
$warnbuff = $args['wb'];
$warnplay = $args['wp'];
$critmode = $args['c'];
$critbuff = $args['cb'];
$critplay = $args['cp'];

if ( $warnmode == "dyn" ) { $warn = $fw->dyngen($warnbuff, $warnplay, $rollover); } else { $warn = $warnmode; }
if ( $critmode == "dyn" ) { $crit = $fw->dyngen($critbuff, $critplay, $rollover); } else { $crit = $critmode; }

$bytearr = $fw->run($host, $interface, $direction, $rollover);
$retval = intval($fw->output($bytearr['up'], $bytearr['down'], $quota, $rollover, $warn, $crit));

exit($retval);
