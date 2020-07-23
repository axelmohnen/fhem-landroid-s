// --------------------------------------------------------------------------------------------
// Landroid Node.js Web Server
// version 1.8
// --------------------------------------------------------------------------------------------	
	"use strict";
	var http = require('http');
	var url = require('url');
	var fs = require('fs');
	const worx = require('./node_modules/iobroker.worx/lib/api');
	var LandroidConf = require('./LandroidConf.json');
	var config;
	var worxCloud;
	var data;
	var pingTimeout = null;
	var connected = false;
	var WSRunning = false;
	var server;
	var mowerId;
	var edgeCuttingTrig = false;
	var oMower;
	
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
				
				case "/edgeCutting":
					fireCmd(9,query.value,response);
					break;
				
				default:
					response.writeHead(500, {"Content-Type": "text/plain"});
					response.end("Invalid path: " + path);
					console.log(getTimestamp() + " --> Landroid WebServer: Invalid path received: " + path);
			}
		}).listen(LandroidConf[mowerId].port);
		console.log(getTimestamp() + " --> Landroid WebServer: server initialized");

	}

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
			case 9:
				cmdStatus = edgeCutting();
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
			worxCloud.sendMessage('{"cmd":1}', oMower.serial); //start code for mower
			
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
		if ((state === 7 || state === 34) && error == 0) {
			// Fire MQTT Message
			worxCloud.sendMessage('{"cmd":3}', oMower.serial); //"Back to home" code for mower
			
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
		worxCloud.sendMessage('{"cmd":2}', oMower.serial); //pause code for mower
			
		// Set return status
		cmdStatus.cmdState = true;
		cmdStatus.msg = "Mower has been paused";
		return cmdStatus;
	}
	
	function edgeCutting() {
		var cmdStatus = { cmdState: false, msg: "" };
		//Edge cutting for mower
		//--> Start Mower (cmd:1)
		//--> wait 5 sec
		//--> Pause Mower (cmd:2)
		//--> wait 5 sec
		//--> Stop Mower (cmd:3)
		
		// Fire MQTT Message
		worxCloud.sendMessage('{"cmd":1}', oMower.serial); //Start Mower
		edgeCuttingTrig = true;
				
		// Set return status
		cmdStatus.cmdState = true;
		cmdStatus.msg = "Edge cutting has been triggered";
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
		worxCloud.sendMessage('{"sc":{"d":' + JSON.stringify(message) + '}}', oMower.serial);
			
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
			delete message.ots;
			// Fire MQTT Message
			worxCloud.sendMessage('{"sc":' + JSON.stringify(message) + '}', oMower.serial);
			
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
				worxCloud.sendMessage('{"mz":' + JSON.stringify(message) + '}', oMower.serial);

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
			worxCloud.sendMessage('{"mzv":' + JSON.stringify(seq) + '}', oMower.serial);
			
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
			worxCloud.sendMessage('{"rd":' + JSON.stringify(message) + '}', oMower.serial);
			
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
	
	function edgeCuttingHandler() {
		//Check for edge cutting mode
		if(!edgeCuttingTrig){
			return;
		}
		
		//Get actual mower state
		var state = (data.dat && data.dat.ls ? data.dat.ls : 0);
		
        	if (state === 1 || state === 3){
			console.log(getTimestamp() + " --> " + "Edgecut Start section :" + state);
        	} else if (state === 2 || state === 7 || state === 33) { //Start squence || Mowing || Searching Zone
            		setTimeout(function(){
				console.log(getTimestamp() + " --> " + "Edcut send cmd:2");
                		worxCloud.sendMessage('{"cmd":2}', oMower.serial); //Pause Mower
            		}, 5000);
 
        	} else if (state === 34) { //Pause
			setTimeout(function(){
				console.log(getTimestamp() + " --> " + "Edcut send cmd:3");
                		worxCloud.sendMessage('{"cmd":3}', oMower.serial); //Stop Mower (go home)
				edgeCuttingTrig = false;
            		}, 5000);
            
        	} else if (state !== 2 && state !== 7 && state !== 33 && state !== 34) {
            		edgeCuttingTrig = false;
			console.log(getTimestamp() + " --> " + "Something went wrong at edgeCutting");
        	}
	}
	
	function main() {
		
		worxCloud = new worx(config.email, config.pwd);

        worxCloud.on('connect', worxc => {
            console.log(getTimestamp() + " --> " + "sucessfully connected!");
			// Start Landroid web server
			startWebServer();
        });

        worxCloud.on('found', function (mower) {
            console.log(getTimestamp() + " --> " + 'found!' + JSON.stringify(mower));
	    //Set mower instance
		oMower = mower;
            });

        worxCloud.on('mqtt', (mower, mower_data) => {
		console.log(getTimestamp() + " --> New data arrived");
		//Get data
                data = mower_data;
				
		//Run edge cutting handler
		edgeCuttingHandler();
				
		if (!WSRunning){
			if (server.address() !== null){
				WSRunning = true;
				console.log(getTimestamp() + " --> Landroid WebServer: server running");
			}
		}
        });

        worxCloud.on('error', err => {
            console.log(getTimestamp() + " --> 'ERROR: " + err);
        });
	}
	
	// Retrieve mover ID
	mowerId = getMoverId();
	
	if (mowerId){
		//Get landroid config
		config = LandroidConf[mowerId];
		
		// Establishh connection to MQTT Broker
		main();
	}
	else{
		console.log("Mower ID is missing!");

	}
