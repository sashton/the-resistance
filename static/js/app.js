var app = angular.module('myApp', []);

app.factory('socket', function ($rootScope) {
	var socket = io.connect("/", {
    	"max reconnection attempts": 5000
	});	

  return {
    on: function (eventName, callback) {
      socket.on(eventName, function () {  
        var args = arguments;
        $rootScope.$apply(function () {
          callback.apply(socket, args);
        });
      });
    },
    emit: function (eventName, data, callback) {
      socket.emit(eventName, data, function () {
        var args = arguments;
        $rootScope.$apply(function () {
          if (callback) {
            callback.apply(socket, args);
          }
        });
      })
    }
  };
});


app.controller('AppCtrl', function($scope, socket){
	var gameid = /game\/(\w+)/.exec(window.location.pathname).slice(-1)[0];
	var session = "";
    var roleReady = false;
	var gamedata = {};
    var selectedPlayers = [];

	function emit(channel, data) {
        if (!data) {
            data = {};
        }
        data.gameid = gameid;
        socket.emit(channel, data);
    }

    function getCookie(key) {
        var cookies = document.cookie.split(";");
        for (var i = 0; i < cookies.length; i++) {
            var parts = cookies[i].trim().split("=");
            if (parts[0]===key) {
                return parts[1];
            }
        }
    }



	$scope.msg = "Waiting for players to join";
	$scope.stage = "unstarted";
            
    socket.on("session", function(data) {
        session = data.session;
        console.log('new session:' + session);
    });

    socket.on("connect", function() {
        console.log('connected');
        emit("session", {sessionid: getCookie("session") || Math.random().toString().slice(2)});
        emit("joingame");
    });

    socket.on("name", function(data) {
    	console.log('name: ' + data.name);
        var foo = _;
        var p = _.findWhere($scope.players, {session:data.session});
        if(!_.isUndefined(p)){
            p.name = data.name;
        }
        if(session == data.session) {
            $scope.playerName = data.name;
        }
    });

    socket.on("gamedata", function(data) {
    	console.log('game data:');
    	console.log(data);
    	gamedata = data;
    	$scope.stage = gamedata.stage || "unstarted";
        roleReady = gamedata.roleReady;
        $scope.votes = [];

        if(gamedata.stage == "proposing" || gamedata.stage == "mission") {
            // $scope.votes = gamedata.proposal.votes;
        }

    	onStateChange();
    });
	
	socket.on("visitors", function(data) {
        $scope.players = [];
        _.each(data.visitors, function(n, s) {
            var p = {name:n, session:s};
            $scope.players.push(p);
        });
        updatePlayerList();
    });

    // socket.on("roles", function(data) {
    // 	$scope.stage = 'roles';

    // });






	socket.on("newleader", function(data) {
    	console.log('newleader:');
    	console.log(data);
    	gamedata = data;
    	$scope.stage = gamedata.stage;
    	onStateChange();
    });

    socket.on("roles", function() {
        roleReady = false;
    });



	$scope.personClass = function(p) {
		var foo = {
			proposed: p.selected,
            'vote-up': (p.vote == "up"),
            'vote-down': (p.vote == "down")
		};
		return foo;
	};

	$scope.yesClass = function() {
        return {
            'btn-disabled': !$scope.yesEnabled
        };
    };

    $scope.noClass = function() {
		return {
			'btn-disabled': !$scope.noEnabled
		};
	};

    $scope.clickChangeName = function() {
        emit("changename",{name:$scope.playerName});
    };

    $scope.clickYes = function() {
    	if($scope.stage == "unstarted") {
    		emit("startgame");
    	} else if($scope.stage == "roles") {
            roleReady = true;
            emit("roleReady");
            onStateChange();
        } else if($scope.stage == "proposing") {
            var team = _.chain(selectedPlayers)
                .map(function(playerSession){
                    return _.findWhere(gamedata.players, {session:playerSession});
                })
                .compact()
                .value();
            emit("propose", {players:team});
        } else if($scope.stage == "voting") {
            gamedata.voted = true;
            emit("vote", {vote: 'up'});
            onStateChange();
        } else if($scope.stage == "mission") {
            gamedata.voted = true;
            emit("missionvote", {vote: 'succeed'});
            onStateChange();
        }
    };

    $scope.clickNo = function() {
        if($scope.stage == "voting") {
            gamedata.voted = true;
            emit("vote", {vote: 'down'});
            onStateChange();
        } else if($scope.stage == "mission") {
            gamedata.voted = true;
            emit("missionvote", {vote: 'fail'});
            onStateChange();
        }
    };

    

    $scope.clickPlayer = function(player) {
    	if($scope.stage == "proposing" && gamedata.leader.session === session) {
    		if(_.contains(selectedPlayers, player.session)) {
    			selectedPlayers = _.without(selectedPlayers, player.session);
    		}
    		else {
    			selectedPlayers.push(player.session);
    		}
    		onStateChange();
    	}
    };



    function onStateChange() {


    	if($scope.stage == "unstarted") {
    		$scope.showYes = true;
    		$scope.yesText = "Start Game";
    		$scope.yesEnabled = true;
    		$scope.showNo = false;
    		$scope.noEnabled = true;
    	}
        else if($scope.stage == "roles") {
            if(gamedata.role == "spy") {
                var spies = _.chain(gamedata.badplayers)
                    .map(function(playerSession){
                        return _.findWhere(gamedata.players, {session:playerSession});
                    })
                    .compact()
                    .map(function(player){return player.name;})
                    .value()
                    .join(", ");
                var flat = _.without([1,2,undefined],[undefined]);
                $scope.msg = "You are a spy. (" + spies + ")";
            }
            else {
                $scope.msg = "You are a member of the Resistance"
            }
            $scope.showYes = !roleReady;
            $scope.showNo = false;
            $scope.yesEnabled = true
            $scope.yesText = "Ready"
        }
    	else if($scope.stage == "proposing") {
    		if (gamedata.leader.session === session) {
    			$scope.msg = "You are the leader. Select " + gamedata.missionteamsize + " players for the mission";
    			$scope.yesText = "Propose";
    			$scope.showYes = true;
	    		$scope.showNo = false;
	    		$scope.yesEnabled = gamedata.missionteamsize == selectedPlayers.length;
            } else {
                $scope.msg = gamedata.leader.name + " is now the leader, and is choosing " + gamedata.missionteamsize + " players for the next mission.";
                $scope.showYes = false;
	    		$scope.showNo = false;
	    		selectedPlayers = [];
            }
    	}
        else if($scope.stage == "voting") {
            if(gamedata.voted) {
                $scope.msg = "Waiting for the rest of the votes";
            }
            else {
                $scope.msg = gamedata.proposal.leader.name + " has proposed a team. Do you accept the team?";
            }
            $scope.showYes = !gamedata.voted;
            $scope.showNo = !gamedata.voted;
            $scope.yesText = "Accept";
            $scope.noText = "Reject";
            $scope.yesEnabled = true;
            $scope.noEnabled = true;
        }
        else if($scope.stage == "mission") {
            console.log("mission proposal");
            console.log(gamedata);
            var maybePlayer = _.findWhere(gamedata.proposal.players, {session:session});
            if(_.isUndefined(maybePlayer)) {
                $scope.msg = "The team has been approved. Waiting for the mission team to vote."
                $scope.showYes = false;
                $scope.showNo = false;
            }
            else {
                if(gamedata.voted) {
                    $scope.msg = "Waiting for the rest of the votes";
                }
                else {
                    $scope.msg = "The team has been approved. Vote on the mission."
                }
                $scope.showYes = !gamedata.voted;
                $scope.showNo = !gamedata.voted;
                $scope.yesEnabled = true;
                $scope.noEnabled = (gamedata.role == "spy");
                $scope.yesText = "Succeed";
                $scope.noText = "Fail";
            }
            // $scope.msg = gamedata.proposal.leader.name + " has proposed a team. Do you accept the team?";
            // $scope.showYes = true;
            // $scope.showNo = true;
            // $scope.yesText = "Accept";
            // $scope.noText = "Reject";
            // $scope.yesEnabled = true;
            // $scope.noEnabled = gamedata.role == "spy";
        }



    	updatePlayerList();
    };


    function updatePlayerList() {
        _.each($scope.players, function(p) {
            if(!_.isUndefined(gamedata.leader)) {
                p.isleader = gamedata.leader.session === p.session;
            }
            else {
                p.isleader = false;
            }
            p.selected = _.contains(selectedPlayers, p.session);
            if(gamedata.stage == "voting" || gamedata.stage == "mission") {
                var proposedPlayer = _.findWhere(gamedata.proposal.players, {session:p.session});
                p.selected = !_.isUndefined(proposedPlayer);
            }
            if(gamedata.stage == "proposing" || gamedata.stage == "mission") {
                // var playerVote = _.findWhere(gamedata.proposal.votes, {session:p.session});
                // p.vote = playerVote.vote;
            }
        });
    }


    onStateChange();
});



