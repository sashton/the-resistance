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


_.mixin({
  isDefined: function(value) {
    return !_.isUndefined(value);
  }
});


app.controller('AppCtrl', function($scope, socket){
	var gameid = /game\/(\w+)/.exec(window.location.pathname).slice(-1)[0];
	var session = "";
    var roleReady = false;
	var gamedata = {};
    $scope.game = {
        stage: "unstarted",
        players: []
    }; // to save typing $scope everywhere
    $scope.game.stage = "unstarted";
    $scope.showSelectedPlayers = false;

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

    function getPlayer(sessionid) {
        return _.findWhere($scope.game.players, {session:sessionid});
    }



	
            
    socket.on("session", function(data) {
        session = data.session;
        console.log('new session:' + session);
    });

    socket.on("connect", function() {
        console.log('connected');
        emit("session", {sessionid: getCookie("session") || Math.random().toString().slice(2)});
        emit("join-game");
    });

    socket.on("name", function(data) {
    	console.log('name: ' + data.name);
        var foo = _;
        var p = getPlayer(data.session);
        if(!_.isUndefined(p)){
            p.name = data.name;
        }
        if(session == data.session) {
            $scope.playerName = data.name;
        }
    });

    socket.on("showgame", function(data) {
        $scope.game.stage = "waiting";
        $scope.msg = "Waiting for players to join";
        $scope.showYes = true;
        $scope.yesText = "Start Game";
        $scope.yesEnabled = true;
        $scope.showNo = false;
        $scope.noEnabled = true;
        $scope.clickYes = function() {
            emit("start-game");
        };
    });

    socket.on("game-data", function(data) {
        // copy new values into scope object
        _.extend($scope.game, data); 
        // $scope.game = data;
        // $scope.stage = game.stage || "unstarted";
        // roleReady = gamedata.roleReady;
        // $scope.votes = [];

        // if(gamedata.stage == "proposing" || gamedata.stage == "mission") {
            // $scope.votes = gamedata.proposal.votes;
        // }

    	// onStateChange();
    });
	
	socket.on("visitors", function(data) {
        // $scope.game.players = [];
        _.each(data.visitors, function(n, s) {
            if(_.isUndefined(getPlayer(s))) {
                var p = {name:n, session:s};
                $scope.game.players.push(p);
            }
        });
    });



    socket.on("new-role", function(data) {
        $scope.game.stage = "role-assign";
        $scope.game.role = data.role;
        $scope.game.spies = data.spies;
        $scope.game.roleReady = data.roleReady;

        if($scope.game.role == "spy") {
            var spies = _.chain($scope.game.spies)
                .map(function(spySession){
                    return _.findWhere($scope.game.players, {session:spySession});
                })
                .compact()
                .map(function(player){return player.name;})
                .value()
                .join(", ");
            $scope.msg = "You are a spy. (" + spies + ")";
        }
        else {
            $scope.msg = "You are a member of the Resistance"
        }
        $scope.showYes = !$scope.game.roleReady;
        $scope.showNo = false;
        $scope.yesEnabled = true
        $scope.yesText = "Ready"

        function setReadyState(){
            $scope.showYes = false;
            $scope.clickYes = undefined;
            $scope.msg = "Waiting for remaining players to start";
        }

        $scope.clickYes = function() {
            emit("role-ready");
            setReadyState();
        };
       
        if ($scope.game.roleReady) {
            setReadyState();
        }
    });

    socket.on("new-leader", function(data) {
        $scope.game.stage = "proposing";
        $scope.game.leader = data.leader;
        $scope.game.missionteamsize = data.missionteamsize
        $scope.selectedPlayers = [];
        $scope.failedProposal = data.failedProposal;
        if(_.isDefined($scope.failedProposal)) {
            var team = _.chain($scope.failedProposal.players)
                .map(function(player){return player.name;})
                .value()
                .join(", ");
            $scope.msg2 = "The team was rejected (" + team + ")";        
        }
        else if(_.isDefined($scope.lastMission)){
            var result = $scope.lastMission.failed ? "failed" : "succeeded";
            var failCount = $scope.lastMission.failcount;
            var successCount = $scope.lastMission.players.length - failCount;
            $scope.msg2 = "The mission " + result + ". Success: " + successCount + ", Fail: " + failCount;
        }
        else {
            $scope.msg2 = undefined;
        }

        if ($scope.game.leader.session === session) {
            $scope.msg = "You are the leader. Select " + $scope.game.missionteamsize + " players for the mission";
            $scope.yesText = "Propose";
            $scope.showYes = true;
            $scope.showNo = false;
            $scope.yesEnabled = false;

            $scope.clickYes = function() {
                $scope.clickYes = undefined; // unregister "listener"
                var team = _.chain($scope.selectedPlayers)
                    .map(getPlayer)
                    .compact()
                    .value();
                emit("propose", {players:team});
            };    
        } else {
            $scope.msg = $scope.game.leader.name + " is now the leader, and is choosing " + $scope.game.missionteamsize + " players for the next mission.";
            $scope.showYes = false;
            $scope.showNo = false;
            $scope.selectedPlayers = [];
        }
    });

    
    socket.on("team-rejected", function(data) {
        $scope.game.stage = "proposing";
        $scope.game.leader = data.leader;
        $scope.selectedPlayers = [];
        $scope.msg2 = "FAILED!";

        if ($scope.game.leader.session === session) {
            $scope.msg = "You are the leader. Select " + $scope.game.missionteamsize + " players for the mission";
            $scope.yesText = "Propose";
            $scope.showYes = true;
            $scope.showNo = false;
            $scope.yesEnabled = false;

            $scope.clickYes = function() {
                $scope.clickYes = undefined; // unregister "listener"
                var team = _.chain($scope.selectedPlayers)
                    .map(getPlayer)
                    .compact()
                    .value();
                emit("propose", {players:team});
            };    
        } else {
            $scope.msg = $scope.game.leader.name + " is now the leader, and is choosing " + $scope.game.missionteamsize + " players for the next mission.";
            $scope.showYes = false;
            $scope.showNo = false;
            $scope.selectedPlayers = [];
        }
    });


    socket.on("proposal", function(data) {
        $scope.game.stage = "voting";
        $scope.game.proposal = data.proposal;
        $scope.game.voted = data.voted;

        if($scope.game.voted) {
            $scope.msg = "Waiting for the rest of the votes";
        }
        else {
            $scope.msg = $scope.game.proposal.leader.name + " has proposed a team. Do you accept the team?";
        }
        $scope.showYes = !$scope.game.voted;
        $scope.showNo = !$scope.game.voted;
        $scope.yesText = "Accept";
        $scope.noText = "Reject";
        $scope.yesEnabled = true;
        $scope.noEnabled = true;

        $scope.clickYes = function() {
            $scope.showYes = false;
            $scope.showNo = false;
            $scope.clickYes = undefined;
            $scope.game.voted = true;
            $scope.msg = "Waiting for the rest of the votes";
            emit("vote", {vote: 'up'});
        };

        $scope.clickNo = function() {
            $scope.showYes = false;
            $scope.showNo = false;
            $scope.clickNo = undefined;
            $scope.game.voted = true;
            $scope.msg = "Waiting for the rest of the votes";
            emit("vote", {vote: 'down'});
        };
    });

    
    socket.on("start-mission", function(data) {
        $scope.game.stage = "mission";
        $scope.game.voted = data.voted;
        $scope.proposal = data.proposal;

        var onteam = _.isDefined(_.findWhere($scope.proposal.players, {session:session}));

        if(onteam) {
            if($scope.game.voted) {
                $scope.msg = "Waiting for remaining mission team votes.";
            }
            else {
                $scope.msg = "The mission team was accepted. Vote on the mission.";
            }
        }
        else {
            $scope.msg = "The mission team was accepted. Waiting on the team to vote.";
        }
        $scope.showYes = onteam && !$scope.game.voted;
        $scope.showNo = onteam && !$scope.game.voted;
        $scope.yesText = "Succeed";
        $scope.noText = "Fail";
        $scope.yesEnabled = true;
        $scope.noEnabled = $scope.role == 'spy';

        $scope.clickYes = function() {
            $scope.showYes = false;
            $scope.showNo = false;
            $scope.clickYes = undefined;
            $scope.game.voted = true;
            $scope.msg = "Waiting for remaining mission team votes.";
            emit("missionvote", {vote: 'succeed'});
        };

        $scope.clickNo = function() {
            $scope.showYes = false;
            $scope.showNo = false;
            $scope.clickNo = undefined;
            $scope.game.voted = true;
            $scope.msg = "Waiting for remaining mission team votes.";
            emit("missionvote", {vote: 'fail'});
        };
    });


    socket.on("gameover", function(data) {
        $scope.game.stage = "gameover";
        $scope.msg = data.result;
        $scope.showYes = false;
        $scope.showNo = false;
    });

        




    $scope.clickPlayer = function(p) {
        var player = getPlayer(p.session);
        if($scope.game.stage == "proposing" && $scope.game.leader.session === session) {
            if(_.contains($scope.selectedPlayers, player.session)) {
                $scope.selectedPlayers = _.without($scope.selectedPlayers, player.session);
            }
            else {
                $scope.selectedPlayers.push(player.session);
            }
        }
    };

    $scope.$watch('selectedPlayers', function () {
        if ($scope.game.stage === "proposing" && $scope.game.leader.session === session) {
            $scope.yesEnabled = $scope.game.missionteamsize == $scope.selectedPlayers.length;
        }
    }, true);


        // else if($scope.stage == "proposing") {
       
     //        }
        // }



	$scope.personClass = function(player) {
        var p = getPlayer(player.session);
		var foo = {
            leader: ($scope.game.leader !== undefined) && ($scope.game.leader.session === p.session)
		};

        if($scope.showProposedPlayers && _.isDefined($scope.game.proposal)) {
            foo.team = _.isDefined(_.findWhere($scope.game.proposal.players, {session:p.session}));
        }
        if($scope.showSelectedPlayers) {
            foo.selected = _.contains($scope.selectedPlayers, p.session);
        }
        if($scope.showPreviousProposal) {
            foo['vote-up'] = $scope.failedProposal.votes[p.session].vote == "up";
            foo['vote-down'] = $scope.failedProposal.votes[p.session].vote == "down";
            foo.team = _.isDefined(_.findWhere($scope.failedProposal.players, {session:p.session}));
        }


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

    // $scope.clickYes = function() {
    // 	} else if($scope.stage == "roles") {
    //         roleReady = true;
    //         emit("roleReady");
    //         onStateChange();
    //     } else if($scope.stage == "proposing") {
    //         var team = _.chain(selectedPlayers)
    //             .map(function(playerSession){
    //                 return _.findWhere(game.players, {session:playerSession});
    //             })
    //             .compact()
    //             .value();
    //         emit("propose", {players:team});
    //     
    //     } else if($scope.stage == "mission") {
    //         game.voted = true;
    //         emit("missionvote", {vote: 'succeed'});
    //         onStateChange();
    //     }
    // };

    // $scope.clickNo = function() {
    //     if($scope.stage == "voting") {
    //         game.voted = true;
    //         emit("vote", {vote: 'down'});
    //         onStateChange();
    //     } else if($scope.stage == "mission") {
    //         game.voted = true;
    //         emit("missionvote", {vote: 'fail'});
    //         onStateChange();
    //     }
    // };

    

    



    function onStateChange() {


    	// if($scope.stage == "unstarted") {
    	// 	$scope.showYes = true;
    	// 	$scope.yesText = "Start Game";
    	// 	$scope.yesEnabled = true;
    	// 	$scope.showNo = false;
    	// 	$scope.noEnabled = true;
    	// }
     //    else if($scope.stage == "roles") {
     //        if(game.role == "spy") {
     //            var spies = _.chain(game.spies)
     //                .map(function(playerSession){
     //                    return _.findWhere(game.players, {session:playerSession});
     //                })
     //                .compact()
     //                .map(function(player){return player.name;})
     //                .value()
     //                .join(", ");
     //            var flat = _.without([1,2,undefined],[undefined]);
     //            $scope.msg = "You are a spy. (" + spies + ")";
     //        }
     //        else {
     //            $scope.msg = "You are a member of the Resistance"
     //        }
     //        $scope.showYes = !roleReady;
     //        $scope.showNo = false;
     //        $scope.yesEnabled = true
     //        $scope.yesText = "Ready"
     //    }

     
     //    else if($scope.stage == "mission") {
     //        console.log("mission proposal");
     //        console.log(game);
     //        var maybePlayer = _.findWhere(game.proposal.players, {session:session});
     //        if(_.isUndefined(maybePlayer)) {
     //            $scope.msg = "The team has been approved. Waiting for the mission team to vote."
     //            $scope.showYes = false;
     //            $scope.showNo = false;
     //        }
     //        else {
     //            if(game.voted) {
     //                $scope.msg = "Waiting for the rest of the votes";
     //            }
     //            else {
     //                $scope.msg = "The team has been approved. Vote on the mission."
     //            }
     //            $scope.showYes = !game.voted;
     //            $scope.showNo = !game.voted;
     //            $scope.yesEnabled = true;
     //            $scope.noEnabled = (game.role == "spy");
     //            $scope.yesText = "Succeed";
     //            $scope.noText = "Fail";
     //        }
     //        // $scope.msg = game.proposal.leader.name + " has proposed a team. Do you accept the team?";
     //        // $scope.showYes = true;
     //        // $scope.showNo = true;
     //        // $scope.yesText = "Accept";
     //        // $scope.noText = "Reject";
     //        // $scope.yesEnabled = true;
     //        // $scope.noEnabled = game.role == "spy";
     //    }



    	// updatePlayerList();
    };


    $scope.$watch('players', function () { updatePlayerList() }, true);
    $scope.$watch('leader', function () { updatePlayerList() }, true);
    $scope.$watch('stage', function () { updatePlayerList() }, true);
    $scope.$watch('selectedPlayers', function () { updatePlayerList() }, true);
    $scope.$watch('proposal', function () { updatePlayerList() }, true);

    $scope.$watch('[game.proposal, game.stage]', function () { 
        $scope.showProposedPlayers = $scope.game.stage == "voting";
    }, true);
    
    $scope.$watch('selectedPlayers', function () { 
        $scope.showSelectedPlayers = $scope.game.stage == "proposing";
    });

    $scope.$watch('[game.stage, failedProposal]', function () { 
        $scope.showPreviousProposal = $scope.game.stage == "proposing" && _.isDefined($scope.failedProposal);

        

    }, true);



    function updatePlayerList() {
        // _.each($scope.game.players, function(p) {
        //     // if(!_.isUndefined($scope.game.leader)) {
        //     //     p.isleader = $scope.game.leader.session === p.session;
        //     // }
        //     // else {
        //     //     p.isleader = false;
        //     // }
        //     p.selected = _.contains($scope.selectedPlayers, p.session);
        //     if($scope.game.stage == "voting" || $scope.game.stage == "mission") {
        //         var proposedPlayer = _.findWhere($scope.game.proposal.players, {session:p.session});
        //         p.selected = !_.isUndefined(proposedPlayer);
        //     }
        //     if($scope.game.stage == "proposing" || $scope.game.stage == "mission") {
        //         // var playerVote = _.findWhere(game.proposal.votes, {session:p.session});
        //         // p.vote = playerVote.vote;
        //     }
        // });
    }


    onStateChange();
});



