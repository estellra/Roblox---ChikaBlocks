--!strict
-- Runs PVP matches (docs/PHASE6.md, M26). Rooms (RoomService) say who plays whom; PvpMatches holds every match and
-- decides every move; this service wires them to the remotes and to the room's life: a match starts when a "pvp" room
-- is formed (the players' solo runs end), leaving the room or the server during a match loses it, and Play again
-- starts the next one once both have pressed it. Every ordered message of a match goes through one remote
-- (Net.PvpEvent), so it arrives in the order it was sent; the opponent's board goes unreliably (Net.PvpOpponentBoard)
-- after each change and again every second. Times are kept on os.clock() and sent to clients in server time.
--
-- Friendly matches (a Duel invitation) and practice matches against the bot change no rank; ranked matches, the rank
-- data and the queue come with M27. For the Studio debug bridge it can pair a player with a practice bot that plays on
-- the server (see bot()), so one Studio window is enough to play a whole match.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local GameService = require("./GameService")
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

type Bot = { rate: number, afk: boolean }

local PvpService = {}

local matches: PvpMatches.PvpMatches
local bots: { [any]: Bot } = {}
local botCount = 0

local function enabled(): boolean
	return PVP.ENABLED or IS_STUDIO
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

local function sendEnd(info: PvpMatches.EndInfo)
	local wire = wireEnd(info)
	for _, member in info.players do
		fire(member, Net.PvpEvent, "end", wire)
	end
end

local function startMatch(room: Rooms.Room)
	local kind = "friendly"
	for _, member in room.players do
		if bots[member] then
			kind = "bot"
		end
	end
	local states = matches:start(room, kind)
	if not states then
		return
	end
	for seat, member in room.players do
		if isPlayer(member) then
			GameService.abandonRun(member :: Player) -- one thing at a time: the solo run is over
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
		startMatch(room)
	end
end

local function onRoomFormed(room: Rooms.Room, _inviteId: number?)
	if room.mode == "pvp" then
		startMatch(room)
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

function PvpService.init(_self: any)
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

	Players.PlayerRemoving:Connect(function(player: Player)
		local info = matches:remove(player) -- the room's own events may have ended the match already
		if info then
			sendEnd(info)
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

-- For the Studio debug bridge. Pairs the player with a practice bot that places the greedy move `rate` times a
-- second, or changes the one they have: "afk" stops it moving, "back" lets it move again, "leave" takes it out of the
-- room (the player wins). Returns a line saying what happened.
function PvpService.bot(player: Player, action: string, rate: number?): string
	if not IS_STUDIO then
		return "practice bots are for Studio only"
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
	botCount += 1
	local bot = { UserId = BOT_FIRST_USER_ID - botCount, Name = "PvpBot", DisplayName = "Bot", IsBot = true }
	local state: Bot = { rate = math.max(0.2, rate or 0.6), afk = false }
	bots[bot] = state
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
