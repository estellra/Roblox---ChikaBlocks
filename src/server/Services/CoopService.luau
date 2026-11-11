--!strict
-- Runs the Co-op games. Rooms (RoomService) say who is playing with whom; CoopRuns holds each room's run and
-- decides every move; this service wires them to the remotes and to the room's life: a run starts when a room is
-- formed (the players' solo runs end), a player who leaves the room leaves the run (the partner carries on with
-- every piece), and the run is forgotten when the room closes. Data, EXP and leaderboards come with M22.
--
-- For the Studio debug bridge it can also pair a player with a practice partner that plays on the server (see
-- bot()), so one Studio window is enough to play a whole Co-op game.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CoopRuns = require("../CoopRuns")
local CoopSession = require(ReplicatedStorage.Shared.CoopSession)
local GameService = require("./GameService")
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local RoomService = require("./RoomService")
local Rooms = require("../Rooms")

local IS_STUDIO = RunService:IsStudio()
local SIZE = Config.GRID_SIZE
local BOT_FIRST_USER_ID = -7001

type Bot = { rate: number, afk: boolean, nextMoveId: number }

local CoopService = {}

local runs: CoopRuns.CoopRuns
local bots: { [any]: Bot } = {}
local botCount = 0

local function isPlayer(who: any): boolean
	return typeof(who) == "Instance"
end

-- Sends to a real player who is still in the server; the practice partner hears nothing.
local function fire(who: any, remote: RemoteEvent | UnreliableRemoteEvent, ...: any)
	if isPlayer(who) and (who :: Player).Parent == Players then
		remote:FireClient(who :: Player, ...)
	end
end

-- A state as the client wants it: the moment the take over button opens is in server time.
local function wireState(state: CoopRuns.State): any
	local at: number? = nil
	if state.takeOverIn then
		at = workspace:GetServerTimeNow() + state.takeOverIn
	end
	local userIds = {}
	for seat, member in state.players do
		userIds[seat] = (member :: Player).UserId
	end
	return {
		runId = state.runId,
		seq = state.seq,
		seat = state.seat,
		userIds = userIds,
		session = state.session,
		takeOverAt = at,
	}
end

local function sendStates(players: { any }, states: { CoopRuns.State }, reason: string)
	for seat, player in players do
		fire(player, Net.CoopState, wireState(states[seat]), reason)
	end
end

-- Applies a move from `player` (a client, or the practice partner) and tells the clients what happened.
function CoopService.place(player: any, runId: unknown, moveId: unknown, slot: unknown, x: unknown, y: unknown)
	local outcome = runs:place(player, runId, moveId, slot, x, y)
	if outcome.kind == "accepted" then
		local move = outcome.move
		local now = workspace:GetServerTimeNow()
		for seat, member in outcome.players do
			local wait = outcome.takeOverIn[seat]
			fire(
				member,
				Net.CoopMove,
				move.runId,
				move.seq,
				move.seat,
				move.moveId,
				move.slot,
				move.x,
				move.y,
				move.score,
				move.set,
				move.isOver,
				if wait then now + wait else nil
			)
		end
	elseif outcome.kind == "rejected" then
		fire(player, Net.CoopReject, outcome.runId, outcome.moveId)
	end
end

-- "Play again": both players have to ask.
local function rematch(player: any)
	local outcome = runs:rematch(player)
	if outcome.kind == "waiting" then
		for _, member in outcome.players do
			fire(member, Net.CoopRematchVotes, outcome.votes)
		end
	elseif outcome.kind == "restarted" then
		sendStates(outcome.players, outcome.states, "start")
		for _, member in outcome.players do
			fire(member, Net.CoopRematchVotes, { false, false })
		end
	end
end

local function onRoomFormed(room: Rooms.Room)
	if room.mode ~= "coop" then
		return
	end
	for _, member in room.players do
		if isPlayer(member) then
			GameService.abandonRun(member :: Player) -- one thing at a time: the solo run is over
		end
	end
	local states = runs:start({ id = room.id, players = room.players, present = room.present })
	if states then
		sendStates(room.players, states, "start")
	end
end

local function onMemberLeft(room: Rooms.Room, player: Player, _seat: number)
	local outcome = runs:leave(player)
	if outcome and outcome.stayer and outcome.state then
		fire(outcome.stayer, Net.CoopState, wireState(outcome.state), "takeover")
	end
	-- A practice partner has nothing to do alone: it leaves when the player does.
	for seat, member in room.players do
		if bots[member] and room.present[seat] and member ~= player then
			RoomService.leave(member)
		end
	end
	bots[player :: any] = nil
end

local function onRoomClosed(room: Rooms.Room)
	runs:close(room.id)
	for _, member in room.players do
		bots[member] = nil
	end
end

function CoopService.init(_self: any)
	runs = CoopRuns.new({
		CoopSession = CoopSession,
		Rng = Rng,
		clock = os.clock,
		newSeed = function(): number
			return Random.new():NextInteger(1, 2 ^ 31 - 1)
		end,
		afkSeconds = Config.COOP.AFK_SECONDS,
	})
end

function CoopService.start(_self: any)
	RoomService.onRoomFormed(onRoomFormed)
	RoomService.onMemberLeft(onMemberLeft)
	RoomService.onRoomClosed(onRoomClosed)

	Net.CoopPlace.OnServerEvent:Connect(
		function(player: Player, runId: unknown, moveId: unknown, slot: unknown, x: unknown, y: unknown)
			CoopService.place(player, runId, moveId, slot, x, y)
		end
	)

	Net.CoopRequestState.OnServerEvent:Connect(function(player: Player)
		local state = runs:state(player)
		if state then
			fire(player, Net.CoopState, wireState(state), "resync")
		end
	end)

	Net.CoopTakeOver.OnServerEvent:Connect(function(player: Player, runId: unknown)
		local outcome = runs:takeOver(player, runId)
		if outcome.kind == "tookOver" then
			fire(player, Net.CoopState, wireState(outcome.state), "takeover")
			RoomService.leave(outcome.evicted) -- the idle partner goes back to the menu
		end
	end)

	Net.CoopRematch.OnServerEvent:Connect(rematch)

	-- Where the player is aiming a piece, for the partner to see. Checked and rate limited in CoopRuns.
	Net.CoopHover.OnServerEvent:Connect(function(player: Player, slot: unknown, x: unknown, y: unknown)
		local outcome = runs:hover(player, slot, x, y)
		if outcome then
			fire(outcome.to, Net.CoopPartnerHover, outcome.slot, outcome.x, outcome.y)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		runs:remove(player) -- the room's own events have taken them out of the run already
	end)
end

-- The practice partner's legal moves right now, or none.
local function botMoves(bot: any): ({ { number } }, number?)
	local view = runs:peek(bot)
	if not view then
		return {}, nil
	end
	local coop = view.coop
	local moves: { { number } } = {}
	for slot, piece in coop.session.tray do
		if piece and coop:mayPlace(view.seat, slot) then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if coop:canPlace(view.seat, slot, x, y) then
						table.insert(moves, { slot, x, y })
					end
				end
			end
		end
	end
	return moves, view.runId
end

local function playBot(bot: any, state: Bot)
	local random = Random.new()
	while bots[bot] == state do
		task.wait(1 / state.rate)
		if state.afk or bots[bot] ~= state then
			continue
		end
		local view = runs:peek(bot)
		if view and view.coop.session.isOver then
			rematch(bot) -- a practice partner is always up for another game
		else
			local moves, runId = botMoves(bot)
			if #moves > 0 and runId then
				local move = moves[random:NextInteger(1, #moves)]
				-- Like a person, it holds the piece over the cell for a moment before letting go.
				local aim = runs:hover(bot, move[1], move[2], move[3])
				if aim then
					fire(aim.to, Net.CoopPartnerHover, aim.slot, aim.x, aim.y)
					task.wait(math.min(0.5, 0.4 / state.rate))
				end
				if bots[bot] == state and not state.afk then
					state.nextMoveId += 1
					CoopService.place(bot, runId, state.nextMoveId, move[1], move[2], move[3])
				end
			end
		end
	end
end

-- For the Studio debug bridge. Pairs the player with a practice partner that plays random legal moves
-- (`rate` a second), or changes the one they have: "afk" stops it moving (so the take over button can be tried),
-- "back" lets it move again, "leave" takes it out of the room. Returns a line saying what happened.
function CoopService.bot(player: Player, action: string, rate: number?): string
	if not IS_STUDIO then
		return "practice partners are for Studio only"
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
			return "no practice partner in the player's room"
		elseif action == "leave" then
			RoomService.leave(partner)
			return "the partner left"
		end
		(bots[partner] :: Bot).afk = action == "afk"
		return `the partner is {if action == "afk" then "idle" else "playing"}`
	end

	if partner then
		RoomService.leave(partner)
	end
	RoomService.leave(player)
	botCount += 1
	local bot = { UserId = BOT_FIRST_USER_ID - botCount, Name = "CoopBot", DisplayName = "Coop bot", IsBot = true }
	local state: Bot = { rate = math.max(0.2, rate or 1), afk = false, nextMoveId = 0 }
	bots[bot] = state
	if not RoomService.pairWithBot(player, bot) then
		bots[bot] = nil
		return "could not make a room: the player must have finished the tutorial"
	end
	task.spawn(playBot, bot, state)
	return `playing with a practice partner ({state.rate} moves a second)`
end

-- For the Studio debug bridge: the player's run in a few numbers, and what the server thinks is possible.
function CoopService.describe(player: Player): string
	local summary = runs:summary(player)
	if not summary then
		return `no Co-op run for {player.Name}`
	end
	local view = runs:peek(player)
	local stuck = ""
	if view then
		stuck = ` hasMove={view.coop:hasMove(view.seat)} partnerHasMove={view.coop:hasMove(3 - view.seat)}`
	end
	return `run={summary.runId} room={summary.roomId} score={summary.score} counted={summary.countedScore} moves={summary.moves} over={summary.isOver} present={table.concat(
		{ tostring(summary.present[1]), tostring(summary.present[2]) },
		","
	)} contribution={table.concat(summary.contribution, "/")}{stuck}`
end

return CoopService
