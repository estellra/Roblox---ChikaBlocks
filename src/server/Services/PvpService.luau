--!strict
-- Runs PVP matches (docs/PHASE6.md, M26). Rooms (RoomService) say who plays whom; PvpMatches holds every match and
-- decides every move; this service wires them to the remotes and to the room's life: a match starts when a "pvp" room
-- is formed (the players' solo runs end), leaving the room or the server during a match loses it, and Play again
-- starts the next one once both have pressed it. Every ordered message of a match goes through one remote
-- (Net.PvpEvent), so it arrives in the order it was sent; the opponent's board goes unreliably (Net.PvpOpponentBoard)
-- after each change and again every second. Times are kept on os.clock() and sent to clients in server time.
--
-- Three kinds of match: "friendly" (a Duel invitation), "bot" (practice against a bot that plays on the server) and
-- "ranked" (M27): the queue (Matchmaker) pairs players of this server and forms their room without an invitation. A
-- ranked match changes rank (PvpRating) unless the pair has had PAIR_RATED_LIMIT rated matches today (PairLimits, in a
-- MemoryStore shared by servers); its loss is written into the players' data when it starts, so leaving can't dodge it
-- (settled before the data is released, or the next time it loads). For the Studio debug bridge the practice bot can
-- also be put in the queue (see bot()), so one Studio window is enough to play a ranked match.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MemoryStoreService = game:GetService("MemoryStoreService")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require("./DataService")
local GameService = require("./GameService")
local HttpService = game:GetService("HttpService")
local LeaderboardService = require("./LeaderboardService")
local RewardService = require("./RewardService")
local Matchmaker = require("../Matchmaker")
local PairLimits = require("../PairLimits")
local PvpRating = require("../PvpRating")
local RankedRules = require("../RankedRules")
local RateLimiter = require("../Util/RateLimiter")
local Seasons = require("../Seasons")
local Net = require(ReplicatedStorage.Shared.Net)
local PvpBoardCodec = require(ReplicatedStorage.Shared.PvpBoardCodec)
local PvpMatches = require("../PvpMatches")
local Pieces = require(ReplicatedStorage.Shared.Pieces)
local PvpSession = require(ReplicatedStorage.Shared.PvpSession)
local RoomService = require("./RoomService")
local Rooms = require("../Rooms")

local PVP = Config.PVP
local SIZE = Config.GRID_SIZE
local IS_STUDIO = RunService:IsStudio()
local SWEEP_SECONDS = 0.1 -- how often matches whose clock ran out are ended
local BOT_FIRST_USER_ID = -8001
local BOT_RATE = 0.6 -- moves a second of the practice bot
local PAIRS_MAP = "PvpPairs"
local DATA_WAIT_SECONDS = 15

type Bot = { rate: number, afk: boolean, rating: number }

-- A ranked match: whether it counts, the id its players' pending loss was written under, and the points each had.
type RankedMatch = { rated: boolean, pendingId: string, ratings: { number } }

local PvpService = {}

local matches: PvpMatches.PvpMatches
local rating = PvpRating.new(PVP.RATING, PVP.TIERS)
local matchmaker: Matchmaker.Matchmaker
local pairLimits: PairLimits.PairLimits
local bots: { [any]: Bot } = {}
local botCount = 0
local rankedOf: { [number]: RankedMatch } = {} -- by match id
local pairRated: { [any]: boolean } = {} -- set by the queue for the room it is about to form
local queueLimiter = RateLimiter.new(2, 1, os.clock)
local tickets: { [any]: { id: string, since: number } } = {} -- the queue ticket of each waiting player (analytics)
local seasonShift = 0 -- months added to the clock's season, for the Studio debug bridge
local RANK_WRITE_GAP_SECONDS = 20 -- the Rank board is written at most this often per player
local practiceLimiter = RateLimiter.new(1, 2, os.clock)

local function enabled(): boolean
	return PVP.ENABLED or IS_STUDIO
end

local function rankedEnabled(): boolean
	return enabled() and PVP.RANKED_ENABLED
end

-- A private server could match its owner with their own second account.
local function isPrivateServer(): boolean
	return game.PrivateServerOwnerId ~= 0
end

local function isPlayer(who: any): boolean
	return typeof(who) == "Instance"
end

-- Sends to a real player who is still in the server; the practice bot hears nothing.
local function fire(who: any, remote: RemoteEvent | UnreliableRemoteEvent, ...: any)
	if isPlayer(who) and (who :: Player).Parent == Players then
		remote:FireClient(who :: Player, ...)
	end
end

-- A time on os.clock() as server time (workspace:GetServerTimeNow), which the clients share.
local function serverTime(time: number): number
	return workspace:GetServerTimeNow() + (time - os.clock())
end

local function nameOf(who: any): string
	if isPlayer(who) then
		return (who :: Player).DisplayName
	end
	return (who :: any).DisplayName or "Bot"
end

local function userIdOf(who: any): number
	return (who :: any).UserId
end

-- A player's rank points: their saved data's, or the practice bot's own.
local function ratingOf(who: any): number
	if isPlayer(who) then
		local data = DataService.get(who :: Player)
		return if data then data.pvp.rating else PVP.RATING.START
	end
	local bot = bots[who]
	return if bot then bot.rating else PVP.RATING.START
end

local function telemetry(): any
	return GameService.getTelemetry()
end

-- The season now (shifted by the Studio debug bridge's `pvp season`).
local function seasonNow(): string
	local season = Seasons.id(os.time())
	for _ = 1, seasonShift do
		season = Seasons.following(season)
	end
	return season
end

-- Gives the player the Top 10 medal of the season that just ended, if they finished in it (once; see
-- PvpRating.awardTop). Returns whether it gave one.
local function awardFinalTop(player: Player, data: any): boolean
	local top = LeaderboardService.finalTop()
	if not top then
		return false
	end
	local place = table.find(top.userIds, player.UserId)
	return place ~= nil and rating:awardTop(data.pvp, top.season, place, PVP.TOP_REWARD)
end

-- Roblox badges for the tiers the player has reached this season (first time ever; see Config.PVP.TIER_BADGES).
local function awardTierBadges(player: Player, data: any)
	local reached = Seasons.tierIndex(PVP.TIERS, rating:peakTier(data.pvp)) or 1
	for tier, badgeId in PVP.TIER_BADGES do
		local index = Seasons.tierIndex(PVP.TIERS, tier)
		if index and reached >= index then
			RewardService.awardBadge(player, data, `rank_{tier}`, badgeId)
		end
	end
end

-- Brings the player's rank data up to date: a match left pending in saved data is a loss, a new season rolls over,
-- and a finished season's Top 10 medal is given.
local function prepareRank(data: any, player: Player?)
	rating:settleStale(data.pvp)
	if not PVP.SEASONS_ENABLED then
		return
	end
	if rating:rollSeason(data.pvp, seasonNow()) and player and data.pvp.lastSeason then
		telemetry():pvpSeasonTier(player, data.pvp.lastSeason.tier)
	end
	if player then
		awardFinalTop(player, data)
	end
end

local function wireSnapshot(snapshot: any): any
	local copy = table.clone(snapshot)
	copy.startAt = serverTime(snapshot.startAt)
	copy.endAt = serverTime(snapshot.endAt)
	-- Never locked yet is -inf on the server; any moment in the past says the same.
	copy.lockedUntil = if snapshot.lockedUntil == -math.huge then 0 else serverTime(snapshot.lockedUntil)
	return copy
end

-- How a match ended, as the clients get it (without the players' instances).
local function wireEnd(info: PvpMatches.EndInfo): any
	return {
		matchId = info.matchId,
		kind = info.kind,
		reason = info.reason,
		results = info.results,
		scores = info.scores,
		sent = info.sent,
		blocked = info.blocked,
	}
end

-- A match state as the client wants it: times in server time, and who is playing by seat.
local function wireState(state: PvpMatches.MatchState, me: any): any
	local opponent = matches:opponentOf(me)
	local seated = { me, opponent }
	if state.seat == 2 then
		seated = { opponent, me }
	end
	local ranked = rankedOf[state.matchId]
	local userIds, names = {}, {}
	for seat, member in seated do
		userIds[seat] = if member then userIdOf(member) else 0
		names[seat] = if member then nameOf(member) else "Opponent"
	end
	return {
		matchId = state.matchId,
		kind = state.kind,
		seat = state.seat,
		startAt = serverTime(state.startAt),
		endAt = serverTime(state.endAt),
		you = wireSnapshot(state.you),
		opponent = state.opponent,
		ended = if state.ended then wireEnd(state.ended) else nil,
		userIds = userIds,
		names = names,
		ranked = if ranked
			then {
				rated = ranked.rated,
				ratings = ranked.ratings,
				tiers = { Seasons.tier(PVP.TIERS, ranked.ratings[1]), Seasons.tier(PVP.TIERS, ranked.ratings[2]) },
			}
			else nil,
	}
end

-- Sends `owner`'s board to their opponent.
local function sendBoard(owner: any)
	local opponent = matches:opponentOf(owner)
	local view = matches:board(owner)
	if opponent ~= nil and view then
		fire(opponent, Net.PvpOpponentBoard, PvpBoardCodec.encode(view))
	end
end

-- Tells both players how the match ended. A ranked match is settled first: each player's pending change is applied
-- (or voided, if the server cancelled it), and each hears what it did to their points.
local function sendEnd(info: PvpMatches.EndInfo)
	local ranked = rankedOf[info.matchId]
	rankedOf[info.matchId] = nil
	for seat, member in info.players do
		local wire = wireEnd(info)
		if isPlayer(member) then
			-- Analytics: this player's match in numbers (the session is gone for a player who left).
			local session = matches:sessionOf(member)
			local result = if info.results then info.results[seat] else "void"
			local scores = info.scores
			telemetry():pvpMatchEnded(
				member,
				{
					kind = info.kind,
					result = result,
					score = scores[seat],
					margin = scores[seat] - scores[3 - seat],
					how = if info.reason == "cancelled"
						then "void"
						elseif info.reason == "left" then "disconnect"
						else info.reason,
					sent = info.sent[seat],
					cancelled = info.blocked[seat],
					taken = if session then session.takenTotal else 0,
					stuck = if session then session.stuckCount else 0,
					pendingAtEnd = if session then #session.pending else 0,
				} :: any
			)
			local ticket = tickets[member]
			if ticket and info.kind == "ranked" then
				telemetry():pvpQueueStep(member, ticket.id, 4) -- Finished
				tickets[member] = nil
			end
		end
		if ranked then
			local before = ranked.ratings[seat]
			local after = before
			local data = if isPlayer(member) then DataService.get(member :: Player) else nil
			if data and ranked.rated then
				local result = if info.results then info.results[seat] else nil
				RankedRules.settle(rating, data.pvp, ranked.pendingId, info.reason, result :: any)
				after = data.pvp.rating
			end
			wire.rating = {
				rated = ranked.rated,
				before = before,
				after = after,
				tierBefore = Seasons.tier(PVP.TIERS, before),
				tier = Seasons.tier(PVP.TIERS, after),
			}
			if data then
				awardTierBadges(member :: Player, data)
				LeaderboardService.flush(member :: Player, data, RANK_WRITE_GAP_SECONDS)
				GameService.sendProfile(member :: Player)
			end
		end
		fire(member, Net.PvpEvent, "end", wire)
	end
end

-- A ranked match starts: when it counts, each player's loss is written into their data now (PvpRating.open) and the
-- pair's daily count goes up.
local function openRanked(matchId: number, players: { any }): RankedMatch
	local ratings = { ratingOf(players[1]), ratingOf(players[2]) }
	local rated = RankedRules.isRated("ranked", pairRated[players[1]] == true and pairRated[players[2]] == true)
	pairRated[players[1]], pairRated[players[2]] = nil, nil
	local ranked: RankedMatch = { rated = rated, pendingId = `{game.JobId}:{matchId}`, ratings = ratings }
	if rated then
		for seat, member in players do
			local data = if isPlayer(member) then DataService.get(member :: Player) else nil
			if data then
				prepareRank(data, member :: Player)
				rating:open(data.pvp, ranked.pendingId, ratings[3 - seat], os.time())
			end
		end
		task.spawn(function()
			pairLimits:record(userIdOf(players[1]), userIdOf(players[2]))
		end)
	end
	return ranked
end

local function startMatch(room: Rooms.Room, kind: string)
	local states = matches:start(room, kind)
	if not states then
		return
	end
	if kind == "ranked" then
		rankedOf[states[1].matchId] = openRanked(states[1].matchId, room.players)
	end
	for seat, member in room.players do
		if isPlayer(member) then
			GameService.abandonRun(member :: Player, "pvp") -- one thing at a time: the solo run is over
			local ticket = tickets[member]
			if ticket and kind == "ranked" then
				telemetry():pvpQueueStep(member, ticket.id, 3) -- Started
			end
		end
		fire(member, Net.PvpEvent, "start", wireState(states[seat], member))
	end
	for _, member in room.players do
		sendBoard(member)
	end
end

-- Applies a move from `player` (a client, or the practice bot) and tells the clients what happened.
function PvpService.place(player: any, matchId: unknown, moveIndex: unknown, slot: unknown, x: unknown, y: unknown)
	local outcome = matches:place(player, matchId, moveIndex, slot, x, y)
	if outcome.kind == "accepted" then
		local stuck = outcome.stuck
		fire(player, Net.PvpEvent, "result", {
			matchId = outcome.matchId,
			moveIndex = outcome.moveIndex,
			score = outcome.score,
			sent = outcome.sent,
			cancelled = outcome.cancelled,
			pending = outcome.pending,
			refill = outcome.refill,
			stuck = if stuck then { set = stuck.set, lockedUntil = serverTime(stuck.lockedUntil) } else nil,
		})
		sendBoard(player)
		if outcome.incoming then
			fire(outcome.opponent, Net.PvpEvent, "incoming", outcome.matchId, outcome.incoming)
			sendBoard(outcome.opponent)
		end
	elseif outcome.kind == "resync" then
		fire(player, Net.PvpEvent, "state", wireState(outcome.state, player))
	end
end

local function rematch(player: any, matchId: unknown)
	local votes = matches:rematch(player, matchId)
	if not votes then
		return
	end
	local room = RoomService.roomOf(player)
	if not room then
		return
	end
	for _, member in room.players do
		fire(member, Net.PvpEvent, "votes", matchId, votes.votes)
	end
	if votes.ready then
		startMatch(room, if bots[room.players[1]] or bots[room.players[2]] then "bot" else "friendly")
	end
end

-- The queue state as the player's queue screen shows it.
local function sendQueueState(player: any, refusal: RankedRules.Refusal?)
	local waited = matchmaker:waited(player)
	local others = matchmaker:count() - (if waited then 1 else 0)
	fire(player, Net.PvpQueueState, {
		queued = waited ~= nil,
		since = if waited then workspace:GetServerTimeNow() - waited else nil,
		others = others,
		refusal = refusal,
	})
end

-- Takes the player out of the queue; `how` is how the wait ended for the analytics ("cancelled", "bot", "left"),
-- nil when a match was made (logged when the pair is made).
local function leaveQueue(player: any, how: string?)
	local waited = matchmaker:waited(player)
	if matchmaker:cancel(player) and isPlayer(player) then
		RoomService.setQueued(player :: Player, false)
		local ticket = tickets[player]
		if how and waited then
			telemetry():pvpQueueWait(player, waited, how)
		end
		if how and ticket then
			tickets[player] = nil
		end
	end
end

-- A "pvp" room was formed: by the queue (no invitation: ranked), by a Duel invitation (friendly), or with the bot.
local function onRoomFormed(room: Rooms.Room, inviteId: number?)
	if room.mode ~= "pvp" then
		return
	end
	for _, member in room.players do
		leaveQueue(member)
	end
	local kind = "friendly"
	if inviteId == nil then
		kind = "ranked"
	elseif bots[room.players[1]] or bots[room.players[2]] then
		kind = "bot"
	end
	startMatch(room, kind)
	for _, member in room.players do
		sendQueueState(member)
	end
end

local function onMemberLeft(room: Rooms.Room, player: Player, _seat: number)
	if room.mode ~= "pvp" then
		return
	end
	local info = matches:leave(player)
	if info then
		sendEnd(info) -- leaving a match still going loses it
	end
	-- The practice bot has nothing to do alone: it leaves when the player does.
	for seat, member in room.players do
		if bots[member] and room.present[seat] and member ~= player then
			RoomService.leave(member)
		end
	end
end

local function onRoomClosed(room: Rooms.Room)
	if room.mode ~= "pvp" then
		return
	end
	for _, member in room.players do
		if not isPlayer(member) then
			matches:remove(member)
			bots[member] = nil
		end
	end
end

-- PairLimits' store: the MemoryStore hash map every server shares, keyed by pair.
local function pairStore(): PairLimits.Store
	local map = MemoryStoreService:GetHashMap(PAIRS_MAP)
	return {
		get = function(key: string): (boolean, PairLimits.Record?)
			local ok, value = pcall(function()
				return map:GetAsync(key)
			end)
			return ok, if ok and typeof(value) == "table" then value else nil
		end,
		update = function(key: string, transform: (PairLimits.Record?) -> PairLimits.Record, ttl: number): boolean
			local ok = pcall(function()
				map:UpdateAsync(key, function(old: any): any
					return transform(if typeof(old) == "table" then old else nil)
				end, ttl)
			end)
			return ok
		end,
	}
end

-- Whether the player may join the queue now, and why not.
local function eligibility(player: Player): (boolean, RankedRules.Refusal?)
	return RankedRules.canQueue({
		enabled = rankedEnabled(),
		privateServer = isPrivateServer(),
		data = DataService.get(player),
		minLevel = PVP.MIN_LEVEL,
		busy = RoomService.roomOf(player) ~= nil,
	})
end

local function joinQueue(player: Player)
	local ok, refusal = eligibility(player)
	if not ok then
		sendQueueState(player, refusal)
		return
	end
	local data = DataService.get(player)
	if data then
		prepareRank(data, player)
	end
	if matchmaker:enqueue(player, ratingOf(player)) then
		GameService.abandonRun(player, "pvp")
		RoomService.setQueued(player, true)
		local ticket = { id = HttpService:GenerateGUID(false), since = os.clock() }
		tickets[player] = ticket
		telemetry():pvpQueueStep(player, ticket.id, 1) -- Queued
	end
	sendQueueState(player)
end

-- Pairs whoever the queue can match and forms each pair's room; the match starts when it is formed (onRoomFormed).
local function matchQueue()
	for _, pair in matchmaker:tick() do
		local a, b = pair[1], pair[2]
		for _, member in pair do
			if isPlayer(member) then
				RoomService.setQueued(member :: Player, false)
			end
		end
		local here = (not isPlayer(a) or (a :: Player).Parent == Players)
			and (not isPlayer(b) or (b :: Player).Parent == Players)
		local rated = here and pairLimits:isRated(userIdOf(a), userIdOf(b))
		pairRated[a], pairRated[b] = rated, rated
		for index, member in pair do
			local ticket = tickets[member]
			if isPlayer(member) and ticket then
				telemetry():pvpQueueStep(member, ticket.id, 2) -- Matched
				telemetry():pvpQueueWait(member, os.clock() - ticket.since, "matched")
				telemetry():pvpMatched(member, ratingOf(member) - ratingOf(pair[3 - index]), not rated)
			end
		end
		if not here or not RoomService.form(a, b, "pvp") then
			pairRated[a], pairRated[b] = nil, nil
			for _, member in pair do
				sendQueueState(member) -- out of the queue; the screen lets them join again
			end
		end
	end
	for _, player in Players:GetPlayers() do
		if matchmaker:isQueued(player) then
			sendQueueState(player) -- who else is waiting changes
		end
	end
end

function PvpService.init(_self: any)
	matchmaker = Matchmaker.new({ clock = os.clock, settings = PVP.QUEUE })
	pairLimits = PairLimits.new({
		store = pairStore(),
		clock = os.time,
		limit = PVP.PAIR_RATED_LIMIT,
		windowSeconds = PVP.PAIR_WINDOW_SECONDS,
		onStoreError = function(what: string)
			warn(`PvpService: the pair count store failed ({what}); counting in this server`)
		end,
	})
	matches = PvpMatches.new({
		PvpSession = PvpSession,
		settings = PVP,
		clock = os.clock,
		newSeed = function(): number
			return Random.new():NextInteger(1, 2 ^ 31 - 1)
		end,
	})
end

function PvpService.start(_self: any)
	-- Clients can't tell a private server apart; the Ranked button follows this.
	ReplicatedStorage:SetAttribute("RankedOpen", rankedEnabled() and not isPrivateServer())
	RoomService.onRoomFormed(onRoomFormed)
	RoomService.onMemberLeft(onMemberLeft)
	RoomService.onRoomClosed(onRoomClosed)

	Net.PvpPlace.OnServerEvent:Connect(
		function(player: Player, matchId: unknown, moveIndex: unknown, slot: unknown, x: unknown, y: unknown)
			if enabled() then
				PvpService.place(player, matchId, moveIndex, slot, x, y)
			end
		end
	)
	Net.PvpRotate.OnServerEvent:Connect(function(player: Player, matchId: unknown, moveIndex: unknown, slot: unknown)
		if not enabled() then
			return
		end
		local outcome = matches:rotate(player, matchId, moveIndex, slot)
		if outcome.kind == "resync" then
			fire(player, Net.PvpEvent, "state", wireState(outcome.state, player))
		end
	end)
	Net.PvpRequestState.OnServerEvent:Connect(function(player: Player)
		local state = if enabled() then matches:state(player) else nil
		if state then
			fire(player, Net.PvpEvent, "state", wireState(state, player))
		end
	end)
	Net.PvpForfeit.OnServerEvent:Connect(function(player: Player, matchId: unknown)
		local info = if enabled() then matches:forfeit(player, matchId) else nil
		if info then
			sendEnd(info)
		end
	end)
	Net.PvpRematch.OnServerEvent:Connect(function(player: Player, matchId: unknown)
		if enabled() then
			rematch(player, matchId)
		end
	end)

	Net.PvpQueue.OnServerEvent:Connect(function(player: Player, join: unknown)
		if not enabled() or not queueLimiter:allow(player) or typeof(join) ~= "boolean" then
			return
		end
		if join then
			joinQueue(player)
		else
			leaveQueue(player, "cancelled")
			sendQueueState(player)
		end
	end)
	Net.PvpPractice.OnServerEvent:Connect(function(player: Player)
		if enabled() and practiceLimiter:allow(player) then
			PvpService.practice(player)
		end
	end)
	-- A player is in one thing at a time: starting a solo run leaves the queue.
	Net.StartGame.OnServerEvent:Connect(function(player: Player)
		leaveQueue(player, "cancelled")
	end)

	-- Rank data is brought up to date when it loads (a match left pending counts as lost, a new season rolls over).
	local function onPlayerAdded(player: Player)
		local data = DataService.waitForData(player, DATA_WAIT_SECONDS)
		if data then
			prepareRank(data, player)
			awardTierBadges(player, data)
			GameService.sendProfile(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	-- Leaving during a match loses it; settled while the player's data is still here.
	DataService.beforeRelease(function(player: Player)
		local info = matches:remove(player)
		if info then
			sendEnd(info)
		end
		leaveQueue(player, "left")
		matchmaker:remove(player)
	end)
	-- A season's final top was read: players here who finished in it get their medal now.
	LeaderboardService.onFinalTop(function()
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data and awardFinalTop(player, data) then
				GameService.sendProfile(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local info = matches:remove(player) -- the room's own events may have ended the match already
		if info then
			sendEnd(info)
		end
		leaveQueue(player, "left")
		matchmaker:remove(player)
		tickets[player] = nil
		queueLimiter:forget(player)
		practiceLimiter:forget(player)
	end)
	task.spawn(function()
		while true do
			task.wait(PVP.QUEUE.TICK_SECONDS)
			matchQueue()
			pairLimits:sweep()
		end
	end)
	-- A planned shutdown cancels the matches still going: nobody wins or loses.
	game:BindToClose(function()
		for _, info in matches:cancelAll() do
			sendEnd(info)
		end
	end)

	local nextResend = 0
	while true do
		task.wait(SWEEP_SECONDS)
		for _, info in matches:sweep() do
			sendEnd(info)
		end
		local now = os.clock()
		if now >= nextResend then
			nextResend = now + PVP.OPPONENT_BOARD_RESEND_SECONDS
			for _, player in Players:GetPlayers() do
				sendBoard(player)
			end
			for bot in bots do
				sendBoard(bot)
			end
		end
	end
end

-- Edges of the piece that touch a wall or a filled cell; higher means a tidier fit.
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function contact(board: Board.Board, piece: any, x: number, y: number): number
	local own = {}
	for _, cell in piece.cells do
		own[(y + cell.y) * SIZE + x + cell.x] = true
	end
	local count = 0
	for _, cell in piece.cells do
		for _, offset in NEIGHBOURS do
			local nx, ny = x + cell.x + offset[1], y + cell.y + offset[2]
			local wall = nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE
			if wall or (not own[ny * SIZE + nx] and Board.get(board, nx, ny) ~= 0) then
				count += 1
			end
		end
	end
	return count
end

-- The bot's move: the one completing the most lines, then the tidiest fit.
local function botMove(session: any): { number }?
	local best: { number }? = nil
	local bestValue = -1
	local board = session.game.board
	for slot, piece in session.game.tray do
		if piece then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if Board.canPlace(board, piece, x, y) then
						local lines = Board.previewLines(board, piece, x, y)
						local value = (#lines.rows + #lines.cols) * 100 + contact(board, piece, x, y)
						if value > bestValue then
							best, bestValue = { slot, x, y }, value
						end
					end
				end
			end
		end
	end
	return best
end

local function playBot(bot: any, state: Bot)
	while bots[bot] == state do
		task.wait(1 / state.rate)
		if state.afk or bots[bot] ~= state then
			continue
		end
		local summary = matches:summary(bot)
		if not summary then
			continue
		end
		if summary.ended then
			if summary.kind == "ranked" then
				RoomService.leave(bot) -- no rematch in ranked: the bot's work is done
				bots[bot] = nil
				break
			end
			rematch(bot, summary.matchId) -- the bot is always up for another match
			continue
		end
		local session = matches:sessionOf(bot)
		local now = os.clock()
		if session and session:canAct(now) and not session.game.awaitingSet and not session.game.isOver then
			local move = botMove(session)
			if move then
				PvpService.place(bot, summary.matchId, session.game.moveCount, move[1], move[2], move[3])
			end
		end
	end
end

local function newBot(rate: number?, points: number?): (any, Bot)
	botCount += 1
	local bot = { UserId = BOT_FIRST_USER_ID - botCount, Name = "PvpBot", DisplayName = "Bot", IsBot = true }
	local state: Bot = { rate = math.max(0.2, rate or BOT_RATE), afk = false, rating = points or PVP.RATING.START }
	bots[bot] = state
	return bot, state
end

--- Practice against the bot (the queue screen offers it when nobody else is there): the player leaves the queue and
--- whatever room they are in, and plays an unranked match against a bot that plays on the server.
function PvpService.practice(player: Player): boolean
	leaveQueue(player, "bot")
	RoomService.leave(player)
	local bot, state = newBot(BOT_RATE)
	if not RoomService.pairWithBot(player, bot, "pvp") then
		bots[bot] = nil
		sendQueueState(player)
		return false
	end
	task.spawn(playBot, bot, state)
	return true
end

-- For the Studio debug bridge. Pairs the player with a practice bot that places the greedy move `rate` times a
-- second, or changes the one they have: "afk" stops it moving, "back" lets it move again, "leave" takes it out of the
-- room (the player wins). "queue" puts a bot with `rate` rank points (default 1000) in the ranked queue instead, so a
-- ranked match can be played alone (only in Studio does a bot's match count). Returns a line saying what happened.
function PvpService.bot(player: Player, action: string, rate: number?): string
	if not IS_STUDIO then
		return "practice bots are for Studio only"
	end
	if action == "queue" then
		for other in bots do
			if matchmaker:isQueued(other) then
				return "a bot is already waiting in the queue" -- two bots would only play each other
			end
		end
		local bot, state = newBot(BOT_RATE, rate)
		matchmaker:enqueue(bot, state.rating)
		task.spawn(playBot, bot, state)
		return `a bot with {state.rating} points is in the queue ({matchmaker:count()} queued)`
	end
	local room = RoomService.roomOf(player)
	local partner: any = nil
	if room then
		for _, member in room.players do
			if bots[member] then
				partner = member
			end
		end
	end
	if action == "afk" or action == "back" or action == "leave" then
		if not partner then
			return "no practice bot in the player's room"
		elseif action == "leave" then
			RoomService.leave(partner)
			return "the bot left"
		end
		(bots[partner] :: Bot).afk = action == "afk"
		return `the bot is {if action == "afk" then "idle" else "playing"}`
	end

	if partner then
		RoomService.leave(partner)
	end
	RoomService.leave(player)
	local bot, state = newBot(rate)
	if not RoomService.pairWithBot(player, bot, "pvp") then
		bots[bot] = nil
		return "could not make a room: the player must have finished the tutorial"
	end
	task.spawn(playBot, bot, state)
	return `playing a practice match against the bot ({state.rate} moves a second)`
end

-- For the Studio debug bridge: "garbage <n>" puts n garbage lines in the player's queue, "cornered" leaves them one
-- move from being stuck (see PvpMatches.corner), "end" ends the match as if the clock had run out; anything else
-- describes the player's match.
function PvpService.debug(player: Player, command: string?, value: number?): string
	if command == "garbage" then
		local pending = matches:addGarbage(player, math.clamp(math.floor(value or 1), 1, PVP.GARBAGE_QUEUE_MAX))
		if not pending then
			return "no match going"
		end
		local summary = matches:summary(player) :: PvpMatches.Summary
		fire(player, Net.PvpEvent, "incoming", summary.matchId, pending)
		sendBoard(player)
		return `garbage waiting: {table.concat(pending, ",")} (1 bottom, 2 left, 3 right)`
	elseif command == "cornered" then
		local state = matches:corner(player, Pieces)
		if not state then
			return "no match going"
		end
		fire(player, Net.PvpEvent, "state", wireState(state, player))
		sendBoard(player)
		return "cornered: place the Dot (slot 1) on a corner and nothing else fits"
	elseif command == "season" then
		-- Moves the season clock on `value` months (Studio only) and rolls the player's data over, as a new month would.
		if not IS_STUDIO then
			return "only in Studio"
		elseif not PVP.SEASONS_ENABLED then
			return "seasons are off (Config.PVP.SEASONS_ENABLED)"
		end
		seasonShift = math.max(0, seasonShift + math.floor(value or 1))
		local data = DataService.get(player)
		if data then
			prepareRank(data, player)
			GameService.sendProfile(player)
		end
		local pvp = data and data.pvp
		return `season now {seasonNow()}: rating={pvp and pvp.rating} last={pvp and pvp.lastSeason and pvp.lastSeason.id} medals={pvp and HttpService:JSONEncode(
			pvp.medals
		)}`
	elseif command == "end" then
		local info = matches:finishNow(player)
		if not info then
			return "no match going"
		end
		sendEnd(info)
		return `ended: {table.concat(info.results or {}, "/")} {table.concat(info.scores, "-")}`
	end
	local summary = matches:summary(player)
	if not summary then
		return `no match for {player.Name}`
	end
	local session = matches:sessionOf(player)
	return `match={summary.matchId} kind={summary.kind} seat={summary.seat} score={summary.score} moves={summary.moves} sent={summary.sent} blocked={summary.blocked} taken={summary.taken} stuck={summary.stuck} ended={summary.ended} pending={table.concat(
		session.pending,
		","
	)} set={session.setIndex} lockedFor={math.max(0, session.lockedUntil - os.clock())} endsIn={math.max(
		0,
		session.endAt - os.clock()
	)}`
end

return PvpService
