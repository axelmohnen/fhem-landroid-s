// --------------------------------------------------------------------------------------------
// Landroid Node.js Web Server
// version 1.4
// --------------------------------------------------------------------------------------------	
	"use strict";
	var http = require('http');
	var url = require('url');
	var fs = require('fs');
	var LandroidCloud = require('./node_modules/iobroker.landroid-s/lib/mqttCloud');
	var LandroidConf = require('./LandroidConf.json');
	var landroid;
	var data;
	var pingTimeout = null;
	var connected = false;
	var WSRunning = false;
	var server;
	var mowerId;
	
	// Get Mower ID
	function getMoverId(){
		var mowerId = process.argv[2]; //We only expect one value
  		return mowerId;
	}

	// Build Timestamp
	function getTimestamp() {
		var date = new Date();
		return date.toUTCString();
	}
	
	// Start Landroid web server
	function startWebServer(){
		server = http.createServer(function(request, response){
			console.log(getTimestamp() + " --> Landroid WebServer: Request recieved");
			// Get HTTP request parts
			var parts = url.parse(request.url, true);
			// Get HTTP path
			var path  = parts.pathname;
			// Get HTPP parameters
			var query = parts.query;

			switch(path){
				case "/getMessage":
					var jsonData = JSON.stringify(data);
					response.writeHead(200, {"Content-Type": "text/plain"});
					response.end(jsonData);
					console.log(getTimestamp() + " --> Landroid WebServer: Response send");
					break;
				case "/startMower":
					fireCmd(1,query.value,response);
					break;
				
				case "/stopMower":
					fireCmd(2,query.value,response);
					break;
							
				case "/changeCfgCalendar":
					fireCmd(3,query.value,response);
					break;
					
				case "/changeCfgTimeExtend":
					fireCmd(4,query.value,response);
					break;
				
				case "/changeCfgArea":
					fireCmd(5,query.value,response);
					break;
					
				case "/startSequences":
					fireCmd(6,query.value,response);
					break;
				
				case "/changeRainDelay":
					fireCmd(7,query.value,response);
					break;
					
				case "/pauseMower":
					fireCmd(8,query.value,response);
					break;
				
				default:
					response.writeHead(500, {"Content-Type": "text/plain"});
					response.end("Invalid path: " + path);
					console.log(getTimestamp() + " --> Landroid WebServer: Invalid path received: " + path);
			}
		}).listen(LandroidConf[mowerId].port);
		console.log(getTimestamp() + " --> Landroid WebServer: server initialized");

	}
	
	//Autoupdate Push
	var updateListener = function (status) {
		if (status) { // We got some data from the Landroid
			clearTimeout(pingTimeout);
			pingTimeout = null;
			
			// Check AWS connection
			if (!connected) {
				connected = true;
				console.log(getTimestamp() + " --> Connected to mower");
				// Start Landroid web server
				startWebServer();
			}
			data = status; // Set new Data to var data
			
			// Check Landroid WebServer connection
			if (!WSRunning){
				if (server.address() !== null){
					WSRunning = true;
					console.log(getTimestamp() + " --> Landroid WebServer: server running");
				}
			}
  
		} else {
			console.log(getTimestamp() + " --> Error getting update!");
		}
	};

	function fireCmd(cmdCode, value, response){
		var cmdStatus;
		var httpCode;
		
		// Handle command
		switch(cmdCode){
			case 1:
				cmdStatus = startMower();
				break;
			case 2:
				cmdStatus = stopMower();
				break;
			case 3:
				cmdStatus = changeCfgCalendar(value);
				break;
			case 4:
				cmdStatus = changeCfgTimeExtend(value);
				break;
			case 5:
				cmdStatus = changeCfgArea(value);
				break;
			case 6:
				cmdStatus = startSequences(value);
				break;
			case 7:
				cmdStatus = changeRainDelay(value);
				break;
			case 8:
				cmdStatus = pauseMower();
				break;
		}
		
		// Check result
		if (cmdStatus.cmdState){
			httpCode = "200";
		}
		else {
			httpCode = "500";	
		}
		
		// Send HTTP response
		response.writeHead(httpCode, {"Content-Type": "text/plain"});
		response.end(cmdStatus.msg);
		
		console.log(getTimestamp() + " --> " + cmdStatus.msg);
	}
	
	function startMower() {
		var cmdStatus = { cmdState: false, msg: "" };
		var state = (data.dat && data.dat.ls ? data.dat.ls : 0);
		var error = (data.dat && data.dat.le ? data.dat.le : 0);

		if ((state === 1 || state === 34) && error == 0) {
			// Fire MQTT Message
			landroid.sendMessage('{"cmd":1}'); //start code for mower
			
			// Set return status
			cmdStatus.cmdState = true;
			cmdStatus.msg = "Mower has been started";
			return cmdStatus;
		} 
		else {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "Can not start mover because he is not at home or he has an issue, please take a look at the mover";
			return cmdStatus;
		}
	}

	function stopMower() {
		var cmdStatus = { cmdState: false, msg: "" };
		var state = (data.dat && data.dat.ls ? data.dat.ls : 0);
		var error = (data.dat && data.dat.le ? data.dat.le : 0);
		if (state === 7 && error == 0) {
			// Fire MQTT Message
			landroid.sendMessage('{"cmd":3}'); //"Back to home" code for mower
			
			// Set return status
			cmdStatus.cmdState = true;
			cmdStatus.msg = "Mower has been stopped, Mower going back home";
			return cmdStatus;

		} 
		else {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "Can not stop mover, because he is not mowing or he has an issue, please take a look at the mover";
			return cmdStatus
		}
	}

	function pauseMower() {
		var cmdStatus = { cmdState: false, msg: "" };

		// Fire MQTT Message
		landroid.sendMessage('{"cmd":2}'); //pause code for mower
			
		// Set return status
		cmdStatus.cmdState = true;
		cmdStatus.msg = "Mower has been paused";
		return cmdStatus;
	}

	function changeCfgCalendar(value) {
		var cmdStatus = { cmdState: false, msg: "" };
		var val = value.split(",");
		var message = data.cfg.sc.d; // set actual values
		var dayId = val[0];
		var startTime;
		var workTime;
		var borderCut;

		try {
			// Validate weekday
			if (isNaN(dayId) || dayId < 0 || dayId > 6){
				// Set return status
				cmdStatus.cmdState = false;
				cmdStatus.msg = "Weekday ID must be between 0 (Sunday) and 6 (Saturday)";
				return cmdStatus;
			}
			
			// Validate and set start time
			var h = val[1].split(':')[0];
			var m = val[1].split(':')[1];
			if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
				startTime = val[1];
			}
			else {
				// Set return status
				cmdStatus.cmdState = false;
				cmdStatus.msg = "Start-Time is out of range: e.g 10:00";
				return cmdStatus;
			}
		
			// Validate and set work time
			if (val[2] >= 0 && val[2] <= 720) {
				workTime = parseInt(val[2]);
			}
			else {
				// Set return status
				cmdStatus.cmdState = false;
				cmdStatus.msg = "Work-Time is out of range: 0 min > time < 720 min.";
				return cmdStatus;
			}
		
			// Validate and set border cut
			if (val[3] == 1 || val[3] == 0){
				borderCut = parseInt(val[3]);
			}
			else{
				// Set return status
				cmdStatus.cmdState = false;
				cmdStatus.msg = "Border cut value must be 0 or 1";
				return cmdStatus;
			}
		}
		catch (e) {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "Error while setting mowers config: " + e;
			return cmdStatus;
		}
		
		// Set and send new config 
		message[dayId][0] = startTime;
		message[dayId][1] = workTime;
		message[dayId][2] = borderCut;
			
		// Fire MQTT Message
		landroid.sendMessage('{"sc":{"d":' + JSON.stringify(message) + '}}');
			
		// Set return status
		cmdStatus.cmdState = true;
		cmdStatus.msg = "Mow time changed to: " + JSON.stringify(message);
		return cmdStatus;	
	}

	function changeCfgTimeExtend(value) {
		var cmdStatus = { cmdState: false, msg: "" };
		var val = parseInt(value);
		var message = data.cfg.sc; // set actual values

		// Validate and set Mower Time Extend
		if (!isNaN(val) && val >= -100 && val <= 100) {
			message.p = val;
			// Fire MQTT Message
			landroid.sendMessage('{"sc":' + JSON.stringify(message) + '}');
			
			// Set return status
			cmdStatus.cmdState = true;
			cmdStatus.msg = "MowerTimeExtend set to : " + message.p;
			return cmdStatus;
		} 
		else {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "MowerTimeExtend must be a value between -100 and 100";
			return cmdStatus;
		}
	}

	function changeCfgArea(value) {
		var cmdStatus = { cmdState: false, msg: "" };
		var val = value.split(",");
		var message = data.cfg.mz; // set actual values
		var areaID = val[0];
		val[1] = parseInt(val[1]);

		try {
			if (!isNaN(val[1]) && val[1] >= 0 && val[1] <= 500) {
				message[areaID] = val[1];
				// Fire MQTT Message
				landroid.sendMessage('{"mz":' + JSON.stringify(message) + '}');

				// Set return status
				cmdStatus.cmdState = true;
				cmdStatus.msg = "Change Area " + (areaID + 1) + " : " + JSON.stringify(message);
				return cmdStatus;
			}
			else {
				// Set return status
				cmdStatus.cmdState = false;
				cmdStatus.msg = "Area Value ist not correct, please type in a val between 0 and 500";
				return cmdStatus;
			}
		}
		catch (e) {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "Error while setting mowers areas: " + e;
			return cmdStatus;
		}
	}

	function startSequences(value) {
		var cmdStatus = { cmdState: false, msg: "" };
		var val = value;
		var seq = [];
		
		try {
			seq = JSON.parse("[" + val + "]");

			for (var i = 0; i < 10; i++) {
				if (seq[i] != undefined) {
					seq[i] = parseInt(seq[i]);
					if (isNaN(seq[i]) || seq[i] < 0 || seq[i] > 3) {
						// Set return status
						cmdStatus.cmdState = false;
						cmdStatus.msg = "Wrong start sequence, for val " + i + " , please type in a val between 0 and 3";
						return cmdStatus;
					}

				} 
				else {
					// Array ist too short, filling up with start point 0
					seq[i] = 0;
				}
			}
			// Fire MQTT Message
			landroid.sendMessage('{"mzv":' + JSON.stringify(seq) + '}');
			
			// Set return status
			cmdStatus.cmdState = true;
			cmdStatus.msg = "new Array is: " + JSON.stringify(seq);
			return cmdStatus;

		}
		catch (e) {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "Error while setting start sequence: " + e;
			return cmdStatus;
		}
	}
	
	function changeRainDelay(value) {
		var cmdStatus = { cmdState: false, msg: "" };
		var val = parseInt(value);
		var message = data.cfg.rd; // set actual values

		// Validate and set Mower rain delay time in minutes
		if (!isNaN(val) && val >= 0 && val <= 300) {
			message = val;
			// Fire MQTT Message
			landroid.sendMessage('{"rd":' + JSON.stringify(message) + '}');
			
			// Set return status
			cmdStatus.cmdState = true;
			cmdStatus.msg = "MowerRainDelay set to : " + message;
			return cmdStatus;
		} 
		else {
			// Set return status
			cmdStatus.cmdState = false;
			cmdStatus.msg = "MowerRainDelay must be a value between 0 and 300";
			return cmdStatus;
		}
	}
	
	function main() {
		// Create landroid handler 
		landroid = new mqttCloud(adapter);
	
		// Check password
		if (adapter.config.pwd === "PASSWORD") {
			console.log(getTimestamp() + " --> Please enter username and password");
		}
		else {
		
			// Set debug log
			adapter.log.debug(getTimestamp() + " --> mail address: " + adapter.config.email);
			adapter.log.debug(getTimestamp() + " --> password were set to: " + adapter.config.pwd);
		
			// Start-up Landroid AWS MQTT Broker connection 
			landroid.init(updateListener);
		
			// Uncomment in case you need further process information
			//console.log(getTimestamp() + " --> " + adapter.log.info);
			//console.log(getTimestamp() + " --> " + adapter.log.error);
			//console.log(getTimestamp() + " --> " + adapter.log.debug);
		}
	}
	
	// Retrieve mover ID
	mowerId = getMoverId();
	
	if (mowerId){
	// Set adapter configuration
	var adapter = { config: LandroidConf[mowerId],
				log: { 	info: function(msg) { adapter.msg.info.push(msg);},
					error: function(msg) { adapter.msg.error.push(msg);},
					debug: function(msg) { adapter.msg.debug.push(msg);},
					warn: function(msg) { adapter.msg.warn.push(msg);}},
				msg: { 	info: [],
					error: [],
					debug: [],
		       			warn: [] }};
	
		// Establishh connection to MQTT Broker
		main();
	}
	else{
		console.log("Mower ID is missing!");

	}
