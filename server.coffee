http = require("http")
fs = require("fs")
express = require("express")
crypto = require("crypto")
mongoskin = require("mongoskin")
uuid = require("node-uuid")
_ = require("underscore")
db = mongoskin.db("localhost/david?auto_reconnect")

games = db.collection("games")
names = db.collection("names")

app = express()

app.configure ->
    app.use express.cookieParser('secret stuff!')
    app.use express.session({ secret: 'asdfg', cookie: { maxAge: 60 * 60 * 10000 }})

app.use "/static", express.static(__dirname + "/static")

app.get "/", (request, response) ->
    fs.readFile __dirname + "/static/index.html", (err, text) ->
        response.end text

ensureSessionCookie = (request, response) ->
    cookies = {}
    for cookie in request.headers.cookie?.split(";") or []
        parts = cookie.split("=");
        cookies[parts[0].trim()] = (parts[1] || "").trim()
    if not cookies.session
        response.writeHead 200,
            'Set-Cookie': 'session=' + uuid().replace("-", "")

app.get "/game/:gameid", (request, response) ->
    ensureSessionCookie request, response
    fs.readFile __dirname + "/static/newgame.html", (err, text) ->
        response.end text

app.get "/oldgame/:gameid", (request, response) ->
    ensureSessionCookie request, response
    fs.readFile __dirname + "/static/game.html", (err, text) ->
        response.end text

server = http.createServer(app)
io = require("socket.io").listen(server)

io.set "log level", 1 # 3 for debug

hash = (msg) -> crypto.createHash('md5').update(msg || "").digest("hex")

rules =
    version: 0
    badplayers:
        2: 1
        3: 1
        4: 1
        5: 2
        6: 2
        7: 3
        8: 3
        9: 3
        10: 4
    rounds:
        2: [1, 1, 1, 1, 1]
        3: [1, 1, 1, 1, 1]
        4: [1, 1, 1, 1, 1]
        5: [2, 3, 2, 3, 3]
        6: [2, 3, 4, 3, 4]
        7: [2, 3, 3, 4, 4]
        8: [3, 4, 4, 5, 5]
        9: [3, 4, 4, 5, 5]
        10: [3, 4, 4, 5, 5]
    twotofailrounds:
        [7, 8, 9, 10]

loadGameData = (data, callback) ->
    games.findOne _id: new db.ObjectID(data.gameid.toString()), (err, obj) ->
        if err
            console.error "Error loading game:", err
            return
        if not obj
            console.error "Game not found:", data
            return
        callback err, obj
        

saveGameData = (obj) ->
    console.log "saving"
    console.log obj.leadername
    games.save obj
    

       
sendMessage = (data, message) ->
    io.sockets.in(data.gameid).emit "msg", message

addToLog = (data, eventtype, params={}, save=false) ->
    gameid = data.gameid or data._id.toString()
    if not gameid
        console.error "Cannot add to log (no gameid): " + data
        return
    newdata = 
        eventtype: eventtype
        params: params
        timestamp: new Date()
    if save
        loadGameData gameid: gameid, (err, obj) ->
            obj.log.push newdata
            console.log "addToLog"
            saveGameData obj
    else
        data.log.push newdata
    console.log "(#{gameid}) Event '#{eventtype}'" +
        (if params.name then " by '#{params.name}'" else "")
    if eventtype is "illegalmove"
        sendMessage {gameid: gameid}, "<i style='color: red;'>#{params.description}</i>"

# handle the creation of a new socket (i.e. a new browser connecting)
io.sockets.on "connection", (socket) ->
    
    socket.session = ""
    socket.name = "Guest" + Math.random().toString()[3..7]
    socket.rooms = io.sockets.manager.roomClients[socket.id]
    
    newLeader = (obj) ->
        sendGameData obj
        #io.sockets.in(obj.gameid).emit "newleader", obj
    
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
                all = if obj.proposal then obj.proposal.votes else undefined
                data =
                    all: all
                    started: true
                    stage: obj.stage
                    players: obj.players
                    rounds: obj.rounds
                    leader: obj.players[obj.leader]
                    counts: rules.rounds[obj.players.length]
                    badplayercount: obj.badplayers.length
                    playercount: obj.players.length
                    missionteamsize: obj.missionteamsize
                    roleReady: !_.isUndefined(obj.roleReady[s.session])
                if s.session in obj.badplayers
                    data.badplayers = obj.badplayers
                    data.role = "spy"
                else 
                    data.role = "resistance"
                if obj.stage == "voting"
                    data.proposal = obj.proposal
                    data.voted = !_.isUndefined(obj.proposal.votes[s.session])
                    data.myvote = obj.proposal.votes[s.session]
                if obj.stage == "mission"
                    data.proposal = obj.proposal
                    data.voted = !_.isUndefined(obj.proposal.missionvotes[s.session])
                    data.myvote = obj.proposal.missionvotes[s.session]
                if obj.stage == "gameover"
                    data.badplayers = obj.badplayers
                    data.gameResult = obj.gameResult
            s.emit "gamedata", data
        sendVisitors obj

    sendVisitors = (obj, sockets) ->
        if obj not instanceof Object
            return
        if not sockets
            sockets = io.sockets.clients(obj._id.toString())
        if sockets not instanceof Array
            sockets = [sockets]
        for s in sockets
            s.emit "visitors", visitors: obj.visitors
    
    proposeIfLeader = (obj) ->
        if obj.started and socket.session is obj.players[obj.leader].session and obj.stage is "proposing"
            socket.emit "proposing", count: rules.rounds[obj.players.length][obj.rounds.length]
    
    listContainsSession = (playerList, session=socket.session) ->
        for player in playerList
            if player is session or player.session is session
                return true
        return false
    
    # handle incoming "msg" events, and emit them back out to all connected clients
    socket.on "msg", (data) ->
        if data.message[0...35] is "https://plus.google.com/hangouts/_/"
            games.save _id: new db.ObjectID(data.gameid.toString()), hangoutUrl: data.message
            io.sockets.in(data.gameid).emit "hangout", url: data.message
        else
            message = "<b>" + socket.name + ":</b> " + _.escape data.message
            addToLog data, "message", name: socket.name, session: socket.session, msg: data.message, true
            sendMessage data, message

    socket.on "session", (data) ->
        socket.session = hash(data.sessionid)
        socket.emit "session", session: socket.session
        names.findOne _id: socket.session, (err, obj) ->
            if obj?.name
                socket.name = obj.name
            else
                names.save _id: socket.session, name: socket.name
            socket.emit "name", session: socket.session, name: socket.name

    socket.on "changename", (data) ->
        console.log "changing name: " + data.name
        if not socket.session then return
        socket.name = _.escape data.name
        names.save _id: socket.session, name: socket.name
        for room of socket.rooms
            if room and socket.rooms[room]
                gameid = room[1..]
                loadGameData gameid: gameid, (err, obj) ->
                    obj.visitors[socket.session] = socket.name
                    saveGameData obj
                    io.sockets.in(gameid).emit "name", session: socket.session, name: socket.name

    socket.on "creategame", (data={}) ->
        gamedata =
            log: []
            roleReady: {}
            readyCount: 0
            stage: "unstarted"
            failedProposalCount: 0
            hangoutUrl: data.hangoutUrl or ""
        games.save gamedata, (err, obj) ->
            if err
                console.error err
                return
            if not obj
                console.warn "Game creation did not return an object; MongoDB issue?"
            if data.gameid
                console.log "gameid $data.gameid"
                io.sockets.in(data.gameid).emit "showgame", gameid: obj._id
            else
                socket.emit "showgame", gameid: obj._id

    socket.on "joingame", (data) ->
        if not socket.session then return
        console.log "joining game: " + data.gameid
        loadGameData data, (err, obj) ->
            obj.visitors or= {}
            obj.visitors[socket.session] = socket.name
            sendVisitors obj
            socket.join(data.gameid)
            # send all the cached game data to the client, to initialize it
            if obj.hangoutUrl
                socket.emit "hangout", url: obj.hangoutUrl
            sendGameData obj, socket
            console.log "joingame"
            saveGameData obj
            proposeIfLeader obj
            if obj.stage is "voting" and not obj.proposal.votes[socket.session]
                socket.emit "voting", proposal: obj.proposal.text
            if obj.stage is "mission" and not obj.proposal.missionvotes[socket.session]
                socket.emit "mission", players: obj.proposal.players
            
    socket.on "propose", (data) ->
        loadGameData data, (err, obj) ->
            if obj.stage isnt "proposing"
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to propose a mission team prematurely.", true
                return
            if socket.session isnt obj.players[obj.leader].session
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to propose a mission team, but isn't the leader.", true
                return
            obj.proposal =
                players: data.players
                leader:
                    name: socket.name
                    session: socket.session
                votes: {}
                votecount: 0
                upcount: 0
                missionvotes: {}
                missionvotecount: 0
                failcount: 0
                text: socket.name + " proposes the team: " + (player.name for player in data.players).toString().replace(/,/g, ", ")
            obj.stage = "voting"
            addToLog obj, "proposal", name: socket.name, session: socket.session, players: data.players
            saveGameData obj
            #io.sockets.in(data.gameid).emit "voting", proposal: obj.proposal.text
            sendGameData obj
            
    socket.on "vote", (data) ->
        loadGameData data, (err, obj) ->
            if obj.stage isnt "voting"
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to vote on a non-existent proposal.", true
                return
            if not listContainsSession(obj.players)
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to vote on a proposal, but isn't in the game.", true
                return
            if obj.proposal.votes[socket.session]
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to vote on the proposal AGAIN.", true
                return                
            addToLog obj, "vote", name: socket.name, session: socket.session, vote: data.vote
            obj.proposal.votes[socket.session] = {name: socket.name, vote: data.vote}
            obj.proposal.votecount += 1
            if data.vote is "up"
                obj.proposal.upcount += 1
            if obj.proposal.votecount == obj.players.length
                obj.proposal.votedup = obj.proposal.upcount / obj.proposal.votecount > 0.5
                if obj.proposal.votedup
                    obj.failedProposalCount = 0
                    obj.stage = "mission"
                    addToLog obj, "votepassed", votes: obj.proposal.votes
                else
                    obj.failedProposalCount += 1
                    if obj.failedProposalCount == 5 
                        obj.stage = "gameover"
                        obj.gameResult = "The spies have won. There were five failed team proposals.";
                    else
                        obj.stage = "proposing"
                        obj.leader = (obj.leader + 1) % obj.players.length
                        addToLog obj, "votefailed", votes: obj.proposal.votes
                        obj.missionteamsize = rules.rounds[obj.players.length][obj.rounds.length]
            saveGameData obj
            sendGameData obj

    socket.on "roleReady", (data) ->
        loadGameData data, (err, obj) ->
            if obj.stage isnt "roles"
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to set role ready, not time.", true
                return
            if not listContainsSession(obj.players)
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to set role ready, but isn't in the game.", true
                return
            if obj.roleReady[socket.session]
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to set role ready AGAIN.", true
                return                
            addToLog obj, "roleReady", name: socket.name, session: socket.session
            obj.roleReady[socket.session] = true
            obj.readyCount +=1
            console.log "roleReady: " + obj.readyCount + " of " + obj.players.length
            if obj.readyCount == obj.players.length
                obj.stage = "proposing"
                newLeader obj
            saveGameData obj

    socket.on "missionvote", (data) ->
        loadGameData data, (err, obj) ->
            if obj.stage isnt "mission"
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to vote on a non-existent mission.", true
                return
            if not listContainsSession(obj.proposal.players)
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to vote on a mission s/he's not on.", true
                return
            if obj.proposal.missionvotes[socket.session]
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to vote on the mission AGAIN.", true
                return                
            addToLog obj, "missionvote", name: socket.name, session: socket.session, vote: data.vote
            sendMessage obj, "<i>" + socket.name + " has participated in the mission!</i>"
            obj.proposal.missionvotes[socket.session] = {name: socket.name, vote: data.vote}
            obj.proposal.missionvotecount += 1
            if data.vote is "fail"
                obj.proposal.failcount += 1
            if obj.proposal.missionvotecount == obj.proposal.players.length
                if obj.rounds.length == 3 and obj.players.length in rules.twotofailrounds
                    obj.proposal.failsneeded = 2
                else
                    obj.proposal.failsneeded = 1
                if obj.proposal.failcount >= obj.proposal.failsneeded
                    obj.proposal.failed = true
                    obj.totalfailures += 1
                    addToLog obj, "missionfailed", failcount: obj.proposal.failcount
                else
                    obj.proposal.failed = false
                    obj.totalsuccesses += 1
                    addToLog obj, "missionpassed", failcount: obj.proposal.failcount
                obj.rounds.push obj.proposal
                #io.sockets.in(data.gameid).emit "missioncomplete",
                #    failcount: obj.proposal.failcount
                #    failed: obj.proposal.failed
                #    round: obj.rounds.length - 1
                if obj.totalfailures == 3
                    obj.stage = "gameover"
                    obj.result = "The spies have won. Three missions have failed."
                    #sendMessage obj, "<div style='color: red;'>The bad guys won... :(</div>"
                    #io.sockets.in(data.gameid).emit "gameover", badplayers: obj.badplayers
                else if obj.totalsuccesses == 3
                    obj.stage = "gameover"
                    obj.result = "The resistance has won. Three missions succeeded."
                    #sendMessage obj, "<div style='color: blue;'>The good guys won!</div>"
                    #io.sockets.in(data.gameid).emit "gameover", badplayers: obj.badplayers
                else
                    obj.stage = "proposing"
                    obj.leader = (obj.leader + 1) % obj.players.length
                    obj.missionteamsize = rules.rounds[obj.players.length][obj.rounds.length]
                    #newLeader obj
                delete obj.proposal
            saveGameData obj
            sendGameData obj
                
    socket.on "startgame", (data) ->
        console.log "startgame recieved"
        loadGameData data, (err, obj) ->
            if obj.stage isnt "unstarted"
                console.log "invalid action"
                addToLog obj, "illegalmove", description: "Player '#{socket.name}' attempted to start the game, but it's already started.", true
                return
            obj.started = true
            obj.players = ({session: s, name: n} for s, n of obj.visitors)
            numBad = rules.badplayers[obj.players.length]
            obj.badplayers = (p.session for p in _.shuffle(obj.players)[0...numBad])
            obj.rulesversion = rules.version
            obj.leader = Math.floor(Math.random() * obj.players.length)
            obj.totalfailures = 0
            obj.totalsuccesses = 0
            obj.timestarted = new Date()
            obj.stage = "roles"
            obj.rounds = []
            for s in io.sockets.clients(data.gameid)
                s.emit "roles"
            sendGameData obj
            addToLog obj, "gamestart"
            obj.missionteamsize = rules.rounds[obj.players.length][obj.rounds.length]
            console.log "startgame"
            saveGameData obj
            #sendRoles
            #for s in io.sockets.clients(data.gameid)
            #    if listContainsSession(obj.badplayers, s.session)
            #        s.emit "roles", 
            ##            role: "spy"
            #            spies: obj.badplayers
            #    else if listContainsSession(obj.players, s.session)
            #        s.emit "roles", 
            #            role: "resistance"
            #newLeader obj
    
    socket.on "disconnect", ->
        for room of socket.rooms
            if room and socket.rooms[room]
                loadGameData gameid: room[1..], (err, obj) ->
                    delete obj.visitors[socket.session]
                    saveGameData obj
                    sendVisitors obj
                    
server.listen 2020
