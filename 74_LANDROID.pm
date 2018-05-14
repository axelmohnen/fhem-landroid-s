# -------------------------------------------------------------------------------------------------
# Developed with Notepad++ 
#
#  (c) 2017-2018 Copyright: Axel Mohnen (axel.mohnen at freenet dot de)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
# -------------------------------------------------------------------------------------------------
#  74_LANDROID.pm
#  v1.1
# -------------------------------------------------------------------------------------------------

package main;

# ---------- Load dependent Perl- or FHEM-Modules -------------------------------------------------
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use HttpUtils;
use Blocking;
use JSON qw( decode_json );


# ---------- FHEM Modules -------------------------------------------------------------------------
# ---------- Initialization -----------------------------------------------------------------------
sub LANDROID_Initialize($) {
	my ($hash) = @_;

    $hash->{SetFn}		= "LANDROID_Set";
    $hash->{DefFn}		= "LANDROID_Define";
    $hash->{UndefFn}		= "LANDROID_Undef";
    $hash->{AttrFn}		= "LANDROID_Attr";
    
    $hash->{AttrList} 		= 	"disable:1,0 " .
							"interval " .
							"port " .
							$readingFnAttributes;
}

# ---------- Definition ---------------------------------------------------------------------------
sub LANDROID_Define($$) {
    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
	
    return "too few parameters: define <name> LANDROID" if( @a != 3 );

    my $name    	= $a[0];
    my $host    	= $a[2];
    my $port		= 8001;
    my $interval  	= 180;
	
	$hash->{HOST} 	= $host;
    $hash->{PORT} 	= $port;
    $hash->{INTERVAL} 	= $interval;
    $hash->{helper}{requestErrorCounter} = 0;
    $hash->{helper}{setErrorCounter} = 0;

	Log3 $name, 3, "LANDROID ($name) - defined with host $hash->{HOST} on port $hash->{PORT} and interval $hash->{INTERVAL} (sec)";
	
	readingsSingleUpdate ( $hash, "state", "initialized", 1 );
	
	InternalTimer( gettimeofday()+$hash->{INTERVAL}, "LANDROID_Get_stateRequest", $hash);
	
	$modules{LANDROID}{defptr}{$hash->{HOST}} = $hash;
		
	return undef;
}

# ---------- Re-definition ------------------------------------------------------------------------
sub LANDROID_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
	delete $modules{LANDROID}{defptr}{$hash->{HOST}};
	RemoveInternalTimer( $hash );

    return undef;
}

# ---------- Handle Attribute update --------------------------------------------------------------
sub LANDROID_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

	# ---------- Set Attribute "disable" --------------------------------------------------------------
    if( $attrName eq "disable" ) {
		if( $cmd eq "set" ) {
			if( $attrVal eq "0" ) {
				RemoveInternalTimer( $hash );
				InternalTimer( gettimeofday()+2, "LANDROID_Get_stateRequest", $hash) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
				readingsSingleUpdate ( $hash, "state", "active", 1 );
				Log3 $name, 3, "LANDROID ($name) - enabled";
			} 
			else {
				readingsSingleUpdate ( $hash, "state", "disabled", 1 );
				RemoveInternalTimer( $hash );
				Log3 $name, 3, "LANDROID ($name) - disabled";
			}
		}
		elsif( $cmd eq "del" ) {
			RemoveInternalTimer( $hash );
			InternalTimer( gettimeofday()+2, "LANDROID_Get_stateRequest", $hash) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
			readingsSingleUpdate ( $hash, "state", "active", 1 );
			Log3 $name, 3, "LANDROID ($name) - enabled";
		} 
		else {
			if($cmd eq "set") {
				$attr{$name}{$attrName} = $attrVal;
				Log3 $name, 3, "LANDROID ($name) - $attrName : $attrVal";
			}
			elsif( $cmd eq "del" ) {
			}
		}
    }

# ---------- Set Attribute "interval" --------------------------------------------------------------	
    if( $attrName eq "interval" ) {
		if( $cmd eq "set" ) {
			if( $attrVal < 60 ) {
				Log3 $name, 3, "LANDROID ($name) - interval too small, please use something > 60 (sec), default is 180 (sec)";
				return "interval too small, please use something > 60 (sec), default is 180 (sec)";
			} 
			else {
				$hash->{INTERVAL} = $attrVal;
				Log3 $name, 3, "LANDROID ($name) - set interval to $attrVal";
			}
		}
		elsif( $cmd eq "del" ) {
			$hash->{INTERVAL} = 180;
			Log3 $name, 3, "LANDROID ($name) - set interval to default";
		} 
		else {
			if( $cmd eq "set" ) {
				$attr{$name}{$attrName} = $attrVal;
				Log3 $name, 3, "LANDROID ($name) - $attrName : $attrVal";
			}
			elsif( $cmd eq "del" ) {
			}
		}
    }

# ---------- Set Attribute "port" --------------------------------------------------------------	
    if( $attrName eq "port" ) {
		if( $cmd eq "set" ) {
			$hash->{PORT} = $attrVal;
			Log3 $name, 3, "LANDROID ($name) - set port to $attrVal";

		}
		elsif( $cmd eq "del" ) {
			$hash->{PORT} = 8001;
			Log3 $name, 3, "LANDROID ($name) - set port to default";
		} 
    }
    
    return undef;
	
}

# ---------- Handle Set command -------------------------------------------------------------------
sub LANDROID_Set($$$@) {
    
    my ( $hash, $name, $cmd, @val ) = @_;
    	
# ---------- Build set command list ---------------------------------------------------------------
    my $list = "";
	$list .= "startMower:noArg "; 						# no Value needed
	$list .= "stopMower:noArg ";						# no Value needed
	$list .= "changeCfgCalendar:textField "; 			# [weekday 0-6],[starttime e.g 10:00],[worktime in min.],[bordercut 0 or 1]
	$list .= "changeCfgTimeExtend:slider,-100,1,100 ";  # [percentage value -100 to 100]
	$list .= "changeCfgArea:textField ";				# [area ID 0-3], [Starting point 0-500]
	$list .= "startSequences:textField ";				# [start sequence 0-3 up to 10 sequences possible]
	$list .= "changeRainDelay:slider,0,1,300 ";  		# [minutes 0 to 300]
	
	if( $cmd eq 'startMower' 			||
	    $cmd eq 'stopMower' 			||
	    $cmd eq 'changeCfgCalendar' 	||
	    $cmd eq 'changeCfgTimeExtend' 	||
	    $cmd eq 'changeCfgArea' 		||
	    $cmd eq 'startSequences' 		||
		$cmd eq 'changeRainDelay' ) {

	    Log3 $name, 5, "LANDROID ($name) - set $name $cmd ".join(" ", @val);

	    my $val = join( " ", @val );
	    my $wordlenght = length($val);
	
# ---------- Check Landroid status ----------------------------------------------------------------
		if( AttrVal( $name, "disable", 0 ) eq "1" ){
			return "LANDROID ($name) is disabled";
		}

# ---------- Check mandatory values ---------------------------------------------------------------		
		if( $cmd eq 'changeCfgCalendar' && $val eq ""){
			return "Please enter argument (e.g.: 0,10:00,300,1 --> [weekday 0-6],[starttime e.g 10:00],[worktime in min.],[bordercut 0 or 1])";
		}
		if( $cmd eq 'changeCfgTimeExtend' && $val eq ""){
			return "Please enter argument (e.g.: 60 --> [percentage value -100 to 100])";
		}
		if( $cmd eq 'changeCfgArea' && $val eq ""){
			return "Please enter argument (e.g.: 0,450 --> [area ID 0-3], [Starting point 0-500])";
		}
		if( $cmd eq 'startSequences' && $val eq ""){
			return "Please enter argument (e.g.: 1,3,0 --> [start sequence 0-3 up to 10 sequences possible])";
		}
		if( $cmd eq 'changeRainDelay' && $val eq ""){
			return "Please enter argument (e.g.: 180 --> [Rain delay in minutes 0-300 sequences possible])";
		}
		
# ---------- Fire Landoid command -----------------------------------------------------------------	
	    return LANDROID_FireSetCmd( $hash, $cmd, $val );
	}

	return "Unknown argument $cmd, bearword as argument or wrong parameter(s), choose one of $list";

}

# ---------- Handle Fire landroid commands --------------------------------------------------------
sub LANDROID_FireSetCmd($$$) {

    my ( $hash, $cmd, $param ) = @_;
	my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};
	
	my $url = "http://" . $host . ":" . $port . "/" . $cmd . "?value=" . $param;
	
	HttpUtils_NonblockingGet(
		{
			url			=> $url,
			timeout		=> 10,
			hash		=> $hash,
			method		=> "GET",
			header     	=> "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
			callback	=> \&LANDROID_ResponseSetCmd
		}
	);
	
	Log3 $name, 4, "LANDROID ($name) - NonblockingGet get URL";
    Log3 $name, 4, "LANDROID ($name) - LANDROID_ResponseSetCmd: calling Host: $host";
	
	return undef;
}

# ---------- Check state --------------------------------------------------------------------------
sub LANDROID_Get_stateRequest($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    
# ---------- Request readings from Landroid -------------------------------------------------------
    LANDROID_GetReadings( $hash ) if( AttrVal( $name, "disable", 0 ) ne "1" );

    InternalTimer( gettimeofday()+$hash->{INTERVAL}, "LANDROID_Get_stateRequest", $hash);
    
    Log3 $name, 4, "LANDROID ($name) - LANDROID_Get_stateRequest";

    return 1;
}

# ---------- Check state (local) ------------------------------------------------------------------
sub LANDROID_Get_stateRequestLocal($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    
# ---------- Request readings from Landroid -------------------------------------------------------
    LANDROID_GetReadings( $hash ) if( AttrVal( $name, "disable", 0 ) ne "1" );

    return 0;
}

# ---------- Get Readings from Worx Landroid Amazon Web Service (AWS Cloud Service - MQTT Broker) -
sub LANDROID_GetReadings($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};
	
	my $url = "http://" . $host . ":" . $port . "/getMessage";
	
	HttpUtils_NonblockingGet(
		{
			url			=> $url,
			timeout		=> 10,
			hash		=> $hash,
			method		=> "GET",
			header     	=> "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
			callback	=> \&LANDROID_RetrieveReadings
		}
	);
	
	Log3 $name, 4, "LANDROID ($name) - NonblockingGet get URL";
    Log3 $name, 4, "LANDROID ($name) - LANDROID_RetrieveReadings: calling Host: $host";
	
	return undef;
}

# ---------- Callback function -> retieve data from Amazon MQTT broker ----------------------------
sub LANDROID_RetrieveReadings($){
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	 Log3 $name, 4, "LANDROID ($name) - LANDROID_RetrieveReadings: processed response data";
	 
# ---------- Begin Error Handling -----------------------------------------------------------------
    if( $hash->{helper}{setErrorCounter} > 1 ) {
	
		readingsSingleUpdate( $hash, "lastStatusRequestState", "statusRequest_error", 1 );
	
	
		if( $hash->{helper}{setErrorCounter} > 1 ) {
	
            Log3 $name, 3, "LANDROID ($name) - Connecting Problem, will check Node HTTP Server";
        }
        
        readingsBeginUpdate( $hash );
	
		if( $hash->{helper}{requestErrorCounter} > 6 && $hash->{helper}{setErrorCounter} > 2 ) {
			readingsBulkUpdate($hash, "lastStatusRequestError", "unknown error, please contact the developer" );
	    
			Log3 $name, 4, "LANDROID ($name) - UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
	    
			$attr{$name}{disable} = 1;
			readingsBulkUpdate( $hash, "state", "Unknown Error" );
			$hash->{helper}{requestErrorCounter} = 0;
			$hash->{helper}{setErrorCounter} = 0;
	    
			return;
		}

		elsif( $hash->{helper}{setErrorCounter} > 3 ) {
			readingsBulkUpdate( $hash, "lastStatusRequestError", "to many errors, check your network or device configuration" );
	    
			Log3 $name, 4, "LANDROID ($name) - To many Errors please check your Network or Device Configuration";

			readingsBulkUpdate( $hash, "state", "To many Errors" );
	    
			$hash->{helper}{setErrorCounter} = 0;
			$hash->{helper}{requestErrorCounter} = 0;
		}
		readingsEndUpdate( $hash, 1 );
    }
	 
	 
	if( defined( $err ) && $err ne "" ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate ( $hash, "state", "$err") if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
        $hash->{helper}{requestErrorCounter} = ( $hash->{helper}{requestErrorCounter} + 1 );

        readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
        readingsBulkUpdate($hash, "lastStatusRequestError", $err );

		readingsEndUpdate( $hash, 1 );
	
		Log3 $name, 4, "LANDROID ($name) - LANDROID_RetrieveReadings: error while request: $err";
		return;
    }
	elsif( $data eq "" and exists( $param->{code} ) ) {
		readingsBeginUpdate( $hash );
		readingsBulkUpdate ( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
		$hash->{helper}{requestErrorCounter} = ( $hash->{helper}{requestErrorCounter} + 1 );
    
		readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
		if( $param->{code} ne 200 ) {
			readingsBulkUpdate( $hash," lastStatusRequestError", "http Error ".$param->{code} );
		}
	
		readingsBulkUpdate( $hash, "lastStatusRequestError", "empty response" );
		readingsEndUpdate( $hash, 1 );
    
		Log3 $name, 4, "LANDROID ($name) - LANDROID_RetrieveReadings: received http code ".$param->{code}." without any data after requesting LANDROID Device";

		return;
    }
	elsif( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
		readingsBeginUpdate( $hash );
		readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state" ,0) ne "initialized" );
		$hash->{helper}{requestErrorCounter} = ( $hash->{helper}{requestErrorCounter} + 1 );

		readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
		
		readingsBulkUpdate( $hash, "lastStatusRequestError", "http error ".$param->{code} );

		readingsEndUpdate( $hash, 1 );
    
		Log3 $name, 4, "LANDROID ($name) - LANDROID_RetrieveReadings: received http code ".$param->{code}." receive Error after requesting LANDROID";

		return;
    }
	
	$hash->{helper}{requestErrorCounter} = 0;
    $hash->{helper}{setErrorCounter} = 0;
	
# ---------- Begin Parse Processing ---------------------------------------------------------------
    	readingsSingleUpdate( $hash, "state", "active", 1) if( ReadingsVal( $name, "state", 0 ) ne "initialized" or ReadingsVal( $name, "state", 0 ) ne "active" );
	
	Log3 $name, 4, "LANDROID ($name) - execute data parsing";
	
# ---------- Parse JSON String to Hash ------------------------------------------------------------
	my $data_decoded = eval{decode_json($data)};
    if($@){
        Log3 $name, 4, "LANDROID ($name) - JSON error while request: $@";
        readingsSingleUpdate($hash, 'JSON_Error', $@, 1);
        return;
	}
	else{
		readingsSingleUpdate($hash, 'JSON_Error', "", 1);
    }
	
# ---------- Set readings to device ---------------------------------------------------------------
	LANDROID_Set_Readings( $hash, $data_decoded );
	
	return undef;
}

 sub LANDROID_Set_Readings($$) {

     my ( $hash, $data_decoded ) = @_;
	 my $name = $hash->{NAME};
	
	 my %stateCodes = (
		 0 => "Idle",
		 1 => "Home",
		 2 => "Start sequence",
		 3 => "Leaving home",
		 4 => "Follow wire",
		 5 => "Searching home",
		 6 => "Searching wire",
		 7 => "Mowing",
		 8 => "Lifted",
		 9 => "Trapped",
		 10 => "Blade blocked",
		 11 => "Debug",
		 12 => "Remote control"
	 );
	
	 my %errorCodes = (
		 0 => "No error",
		 1 => "Trapped",
		 2 => "Lifted",
		 3 => "Wire missing",
		 4 => "Outside wire",
		 5 => "Raining",
		 6 => "Close door to mow",
		 7 => "Close door to go home",
		 8 => "Blade motor blocked",
		 9 => "Wheel motor blocked",
		 10 => "Trapped timeout",
		 11 => "Upside down",
		 12 => "Battery low",
		 13 => "Reverse wire",
		 14 => "Charge error",
		 15 => "Timeout finding home"
	 );

	 my $t;      # for Readings Name
     	 my $v;      # for Readings Value
	 my $error;
	 my $status;
	 my $sequence;
	 my @calendar;
	 my @area;
	 my @areaAct;
	
	 readingsBeginUpdate( $hash );

# ---------- Set Readings ------------------------------------------------------------------------
	# Mowing Statistics
	 $t = "totalTime";
	 $v = $data_decoded->{'dat'}{'st'} && $data_decoded->{'dat'}{'st'}{'wt'} ? $data_decoded->{'dat'}{'st'}{'wt'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
 
	 $t = "totalDistance";
	 $v = $data_decoded->{'dat'}{'st'} && $data_decoded->{'dat'}{'st'}{'d'} ? $data_decoded->{'dat'}{'st'}{'d'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 
	 $t = "totalBladeTime";
	 $v = $data_decoded->{'dat'}{'st'} && $data_decoded->{'dat'}{'st'}{'b'} ? $data_decoded->{'dat'}{'st'}{'b'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 
	# Battery Status
	 $t = "batteryChargeCycle";
	 $v = $data_decoded->{'dat'}{'bt'} && $data_decoded->{'dat'}{'bt'}{'nr'} ? $data_decoded->{'dat'}{'bt'}{'nr'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 
	 $t = "batteryCharging";
	 $v = $data_decoded->{'dat'}{'bt'} && $data_decoded->{'dat'}{'bt'}{'c'} ? "true" : "false";
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 
	 $t = "batteryVoltage";
	 $v = $data_decoded->{'dat'}{'bt'} && $data_decoded->{'dat'}{'bt'}{'v'} ? $data_decoded->{'dat'}{'bt'}{'v'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 
	 $t = "batteryTemperature";
	 $v = $data_decoded->{'dat'}{'bt'} && $data_decoded->{'dat'}{'bt'}{'t'} ? $data_decoded->{'dat'}{'bt'}{'t'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 
	 $t = "batteryLevel";
	 $v = $data_decoded->{'dat'}{'bt'} && $data_decoded->{'dat'}{'bt'}{'p'} ? $data_decoded->{'dat'}{'bt'}{'p'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );

	#Mower Error Code
	 $t = "mowerError";
	 $error = $data_decoded->{'dat'} && $data_decoded->{'dat'}{'le'} ? $data_decoded->{'dat'}{'le'} : 0;
	 $v = $error;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Mower Error Description
	 $t = "mowerErrorTxt";
	 $v = $errorCodes{$error};
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Mower Status Code
	 $t = "mowerStatus";
	 $status = $data_decoded->{'dat'} && $data_decoded->{'dat'}{'ls'} ? $data_decoded->{'dat'}{'ls'} : 0;
	 $v = $status;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Mower Status description
	 $t = "mowerStatusTxt";
	 $v = $stateCodes{$status};
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Mower state
	 if (($status eq 7 || $status eq 9) && $error eq 0) {
		 $t = "mowerState";
		 $v = "true";
		 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
     } 
	 else {
		 $t = "mowerState";
		 $v = "false";
		 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
     }

	#WIFI 
	 $t = "wifiQuality";
	 $v = $data_decoded->{'dat'} && $data_decoded->{'dat'}{'rsi'} ? $data_decoded->{'dat'}{'rsi'} : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Firmware
	 $t = "firmware";
	 $v = $data_decoded->{'dat'} && $data_decoded->{'dat'}{'fw'} ? $data_decoded->{'dat'}{'fw'} : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Config data
	#Mower Active
	 $t = "mowerActive";
	 $v = $data_decoded->{'cfg'}{'sc'} && $data_decoded->{'cfg'}{'sc'}{'m'} ? "true" : "false";
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Mower waiting rain
	 $t = "mowerWaitRain";
	 $v = $data_decoded->{'cfg'} && $data_decoded->{'cfg'}{'rd'} ? $data_decoded->{'cfg'}{'rd'} : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Mow time extention
	 $t = "mowTimeExtend";
	 $v = $data_decoded->{'cfg'}{'sc'} && $data_decoded->{'cfg'}{'sc'}{'p'} ? $data_decoded->{'cfg'}{'sc'}{'p'} : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Calendar
	 @calendar = @{ $data_decoded->{'cfg'}{'sc'}{'d'} };
	 for my $i ( 0 .. $#calendar ) {
		 $t = "calendar" . "Weekday" . $i . "StartTime";
		 $v = $calendar[$i][0];
		 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
		
		 $t = "calendar" . "Weekday" . $i . "WorkTime";
		 $v = $calendar[$i][1];
		 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
		
		 $t = "calendar" . "Weekday" . $i . "BorderCut";
		 $v = $calendar[$i][2] eq 1 ? "true" : "false";
		 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	 }
	
	#Areas
	 @area = @{ $data_decoded->{'cfg'}{'mz'} };
	 @areaAct = @{ $data_decoded->{'cfg'}{'mzv'} };
	 $sequence = join(",", @areaAct);
	
	 $t = "areasArea1";
	 $v = @area && $area[0] ? $area[0] : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	 $t = "areasArea2";
	 $v = @area && $area[1] ? $area[1] : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	 $t = "areasArea3";
	 $v = @area && $area[2] ? $area[2] : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	 $t = "areasArea4";
	 $v = @area && $area[3] ? $area[3] : 0;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	 $t = "areasAreaAct";
	 $v = $data_decoded->{'dat'} && $areaAct[$data_decoded->{'dat'}{'lz'}] ? $areaAct[$data_decoded->{'dat'}{'lz'}] : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	 $t = "areasAreaActInd";
	 $v = $data_decoded->{'dat'} && $data_decoded->{'dat'}{'lz'} ? $data_decoded->{'dat'}{'lz'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	 $t = "areasStartSequence";
	 $v = $sequence;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	#Serial number
	 $t = "serialNumber";
	 $v = $data_decoded->{'cfg'} && $data_decoded->{'cfg'}{'sn'} ? $data_decoded->{'cfg'}{'sn'} : undef;
	 readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
	
	
	 readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_done" );
    
     $hash->{helper}{requestErrorCounter} = 0;
	
     readingsBulkUpdate( $hash, "state", "active" ) if( ReadingsVal( $name, "state", 0 ) eq "initialized" );
	
	 readingsEndUpdate( $hash, 1 );
     return;
 }
 
 # ---------- Get Readings from Worx Landroid Amazon Web Service (AWS Cloud Service - MQTT Broker) -
sub LANDROID_GetReadings($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};
	
	my $url = "http://" . $host . ":" . $port . "/getMessage";
	
	HttpUtils_NonblockingGet(
		{
			url			=> $url,
			timeout		=> 10,
			hash		=> $hash,
			method		=> "GET",
			header     	=> "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
			callback	=> \&LANDROID_RetrieveReadings
		}
	);
	
	Log3 $name, 4, "LANDROID ($name) - NonblockingGet get URL";
    Log3 $name, 4, "LANDROID ($name) - LANDROID_RetrieveReadings: calling Host: $host";
	
	return undef;
}

# ---------- Callback function -> retieve data from Amazon MQTT broker ----------------------------
sub LANDROID_ResponseSetCmd($){
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	 Log3 $name, 4, "LANDROID ($name) - LANDROID_ResponseSetCmd: processed response data";
	 
	 
# ---------- Begin Error Handling -----------------------------------------------------------------
    if( $hash->{helper}{setErrorCounter} > 1 ) {
	
		readingsSingleUpdate( $hash, "lastSetCommandState", "statusRequest_error", 1 );
	
	
		if( $hash->{helper}{setErrorCounter} > 1 ) {
	
            Log3 $name, 3, "LANDROID ($name) - Connecting Problem, will check Node HTTP Server";
        }
        
        readingsBeginUpdate( $hash );
	
		if( $hash->{helper}{requestErrorCounter} > 6 && $hash->{helper}{setErrorCounter} > 2 ) {
			readingsBulkUpdate($hash, "lastSetCommandMsg", "unknown error, please contact the developer" );
	    
			Log3 $name, 4, "LANDROID ($name) - UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
	    
			$attr{$name}{disable} = 1;
			readingsBulkUpdate( $hash, "state", "Unknown Error" );
			$hash->{helper}{requestErrorCounter} = 0;
			$hash->{helper}{setErrorCounter} = 0;
	    
			return;
		}

		elsif( $hash->{helper}{setErrorCounter} > 3 ) {
			readingsBulkUpdate( $hash, "lastSetCommandMsg", "to many errors, check your network or device configuration" );
	    
			Log3 $name, 4, "LANDROID ($name) - To many Errors please check your Network or Device Configuration";

			readingsBulkUpdate( $hash, "state", "To many Errors" );
	    
			$hash->{helper}{setErrorCounter} = 0;
			$hash->{helper}{requestErrorCounter} = 0;
		}
		readingsEndUpdate( $hash, 1 );
    }
	 
	 
	if( defined( $err ) && $err ne "" ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate ( $hash, "state", "$err") if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
        $hash->{helper}{setErrorCounter} = ( $hash->{helper}{setErrorCounter} + 1 );

        readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_error" );
        readingsBulkUpdate($hash, "lastSetCommandMsg", $err );

		readingsEndUpdate( $hash, 1 );
	
		Log3 $name, 4, "LANDROID ($name) - LANDROID_ResponseSetCmd: error while request: $err";
		return;
    }
	
	
	if( exists( $param->{code} ) && $param->{code} ne 200 ) {
		readingsBeginUpdate( $hash );
		readingsBulkUpdate( $hash, "state", $param->{code} . ":" . $data ) if( ReadingsVal( $hash, "state", 0 ) ne "initialized" );
	
		$hash->{helper}{setErrorCounter} = ( $hash->{helper}{setErrorCounter} + 1 );

		readingsBulkUpdate($hash, "lastSetCommandState", "cmd_error" );
		readingsBulkUpdate($hash, "lastSetCommandMsg", "http Error ".$param->{code} . ":" . $data );
		readingsEndUpdate( $hash, 1 );
    
		Log3 $name, 5, "LANDROID ($name) - LANDROID_ResponseSetCmd: received http code ".$param->{code} . ":" . $data;

		return;
    }
	elsif( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
		readingsBeginUpdate( $hash );
		readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state" ,0) ne "initialized" );
		$hash->{helper}{setErrorCounter} = ( $hash->{helper}{setErrorCounter} + 1 );

		readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_error" );
		readingsBulkUpdate( $hash, "lastSetCommandMsg", "http error ".$param->{code} );

		readingsEndUpdate( $hash, 1 );
    
		Log3 $name, 4, "LANDROID ($name) - LANDROID_ResponseSetCmd: received http code ".$param->{code}." receive Error after requesting LANDROID";

		return;
    }
	
# ---------- Set command was successfully -> set state --------------------------------------------
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_done" );
	readingsBulkUpdate( $hash, "lastSetCommandMsg", $data );
	readingsEndUpdate( $hash, 1 );
	
	$hash->{helper}{requestErrorCounter} = 0;
    $hash->{helper}{setErrorCounter} = 0;

# ---------- Request readings from Landroid -------------------------------------------------------
	LANDROID_Get_stateRequestLocal( $hash );
	 
	return undef;
}

# ---------- Eval return value for successfully loaded modules ------------------------------------
1;


# Beginn der Commandref
