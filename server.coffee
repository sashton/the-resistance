http = require("http")
fs = require("fs")
express = require("express")
crypto = require("crypto")
mongoskin = require("mongoskin")
_ = require("underscore")
db = mongoskin.db("localhost/david?auto_reconnect")

games = db.collection("games")
names = db.collection("names")

app = express(
    express.cookieParser(),
    express.session(),
)

app.use "/static", express.static(__dirname + "/static")

app.get "/", (request, response) ->
  fs.readFile __dirname + "/static/index.html", (err, text) ->
      response.end text

app.get "/game/:gameid", (request, response) ->
  fs.readFile __dirname + "/static/game.html", (err, text) ->
      response.end text

server = http.createServer(app)
io = require("socket.io").listen(server)

io.set "log level", 2 # 3 for debug

hash = (msg) -> crypto.createHash('md5').update(msg || "").digest("hex")

rules =
    version: 0
    badplayers:
        5: 2
        6: 2
        7: 3
        8: 3
        9: 3
        10: 4
    rounds:
        5: [2, 3, 2, 3, 3]
        6: [2, 3, 4, 3, 4]
        7: [2, 3, 3, 4, 4]
        8: [3, 4, 4, 5, 5]
        9: [3, 4, 4, 5, 5]
        10: [3, 4, 4, 5, 5]
    twotofailrounds:
        [7, 8, 9, 10]

loadGameData = (data, callback) ->
    games.findOne _id: new db.ObjectID(data.gameid), (err, obj) ->
        if err
            console.error "Error loading game:", err
            return
        if not obj
            console.error "Game not found:", data
            return
        callback err, obj

saveGameData = (obj) ->
    games.save obj
    
newLeader = (obj) ->
    leader = obj.players[obj.leader]
    io.sockets.in(obj.gameid).emit "newleader",
        session: leader.session
        name: leader.name
        count: rules.rounds[obj.players.length][obj.rounds.length]

# handle the creation of a new socket (i.e. a new browser connecting)
io.sockets.on "connection", (socket) ->
    
    socket.session = ""
    socket.name = "Guest" + Math.random().toString()[3..7]
    socket.rooms = io.sockets.manager.roomClients[socket.id]
    
    sendGameData = (obj, sockets) ->
        if obj not instanceof Object
            return
        if not sockets
            sockets = io.sockets.clients(obj._id.toString())
        if sockets not instanceof Array
            sockets = [sockets]
        for s in sockets
            data = {started: false}
            if obj.started
                data =
                    started: true
                    players: obj.players
                    rounds: obj.rounds
                    leader: obj.players[obj.leader]
                    counts: rules.rounds[obj.players.length]
                if s.session in obj.badplayers
                    data.badplayers = obj.badplayers
            s.emit "gamedata", data
    
    proposeIfLeader = (obj) ->
        console.log obj.started, obj.stage, socket.session, obj.players?[obj.leader]?.session
        if obj.started and socket.session is obj.players[obj.leader].session and obj.stage is "proposing"
            socket.emit "proposing", count: rules.rounds[obj.players.length][obj.rounds.length]
    
    # handle incoming "msg" events, and emit them back out to all connected clients
    socket.on "msg", (data) ->
        if data.message[0...35] is "https://plus.google.com/hangouts/_/"
            games.save _id: new db.ObjectID(data.gameid), hangoutUrl: data.message
            io.sockets.in(data.gameid).emit "hangout", url: data.message
        else
            message = "<b>" + socket.name + ":</b> " + data.message
            io.sockets.in(data.gameid).emit "msg", message

    socket.on "session", (data) ->
        socket.session = hash(data.sessionid)
        names.findOne _id: socket.session, (err, obj) ->
            if obj?.name
                socket.name = obj.name
            else
                names.save _id: socket.session, name: socket.name
            socket.emit "name", session: socket.session, name: socket.name

    socket.on "changename", (data) ->
        if not socket.session then return
        socket.name = data.name
        names.save _id: socket.session, name: socket.name
        for room of socket.rooms
            if room and socket.rooms[room]
                gameid = room[1..]
                updateObj = {}
                updateObj["visitors." + socket.session] = socket.name
                console.log "updateObj", updateObj
                games.update {_id: new db.ObjectID(gameid)}, updateObj
                io.sockets.in(gameid).emit "name", session: socket.session, name: socket.name

    socket.on "creategame", ->
        games.save {}, (err, obj) ->
            socket.emit "showgame", obj._id

    socket.on "joingame", (data) ->
        if not socket.session then return
        loadGameData data, (err, obj) ->
            obj.visitors or= {}
            obj.visitors[socket.session] = socket.name
            io.sockets.in(data.gameid).emit "visitorjoined", session: socket.session, name: socket.name
            socket.join(data.gameid)
            # send all the cached game data to the client, to initialize it
            for s, n of obj.visitors
                socket.emit "visitorjoined", session: s, name: n
            if obj.hangoutUrl
                socket.emit "hangout", url: obj.hangoutUrl
            sendGameData obj, socket
            saveGameData obj
            proposeIfLeader obj
            
    socket.on "propose", (data) ->
        loadGameData data, (err, obj) ->
            socket.name + " proposes the team: " + (player.name for player in data.players)
            obj.proposal =
                players: data.players
                leader:
                    name: socket.name
                    session: socket.session
                votes: []
                votecount: 0
                upcount: 0
                projectvotes: []
                projectvotecount: 0
                sabotagecount: 0
            saveGameData obj
            io.sockets.in(data.gameid).emit "voting", proposal: proposal
            
    socket.on "vote", (data) ->
        loadGameData data, (err, obj) ->
            obj.proposal.votes[socket.session] = obj.vote
            obj.proposal.votecount += 1
            if obj.vote is "up"
                obj.proposal.upcount += 1
            if obj.proposal.votecount == obj.players.length
                if obj.proposal.upcount / obj.proposal.votecount > 0.5
                    obj.stage = "project"
                    obj.proposal.votedup = true
                else
                    obj.stage = "proposing"
                    obj.proposal.votedup = false
                    obj.leader = (obj.leader + 1) % obj.players.length
                    newLeader obj
                io.sockets.in(data.gameid).emit "votecomplete",
                    votes: obj.proposal.votes
                    votedup: obj.proposal.votedup
            saveGameData obj

    socket.on "projectvote", (data) ->
        loadGameData data, (err, obj) ->
            obj.proposal.projectvotes[socket.session] = obj.vote
            obj.proposal.projectvotecount += 1
            if obj.vote is "sabotage"
                obj.proposal.sabotagecount += 1
            if obj.proposal.projectvotecount == obj.proposal.players.length
                if obj.rounds.length == 3 and obj.players.length in rules.twotofailrounds
                    failsneeded = 2
                else
                    failsneeded = 1
                obj.proposal.sabotaged = obj.proposal.sabotagecount >= failsneeded
                obj.rounds.append obj.proposal
                io.sockets.in(data.gameid).emit "projectcomplete",
                    votes: obj.proposal.projectvotes
                    sabotaged: obj.proposal.sabotaged
            saveGameData obj

                
    socket.on "startgame", (data) ->
        loadGameData data, (err, obj) ->
            # if obj.started
            #     return
            obj.started = true
            obj.players = ({session: s, name: n} for s, n of obj.visitors)
            numBad = rules.badplayers[obj.players.length]
            obj.badplayers = (p.session for p in _.shuffle(obj.players)[0...numBad])
            obj.rulesversion = rules.version
            obj.leader = Math.floor(Math.random() * obj.players.length)
            obj.stage = "proposing"
            obj.rounds = []
            obj.log = []
            sendGameData obj
            saveGameData obj
            newLeader obj
    
    socket.on "disconnect", ->
        for room of socket.rooms
            if room and socket.rooms[room]
                gameid = room[1..]
                updateObj = {$unset: {}}
                updateObj["$unset"]["visitors." + socket.session] = 1
                console.log "updateObj", {_id: gameid}, updateObj
                games.update {_id: new db.ObjectID(gameid)}, updateObj, (err, obj) ->
                    console.log "err", err
                io.sockets.in(gameid).emit "visitorleft", session: socket.session, name: socket.name
            

server.listen 2020