--!strict
-- Every PVP match on the server (docs/PHASE6.md, M26): two PvpSessions with a secret seed, the clock, moves, attacks
-- passed to the other side, the end of a match and who won. Pure Luau so Lune can test it with fake players and a
-- fake clock; PvpService wires it to the remotes, rooms, data and analytics. The shared PvpSession module is passed
-- in because server and shared code sit in different places on disk and in the DataModel.
--
-- Everything a client sends is untrusted: requests are rate limited and arguments validated. Outcomes follow
-- GameRuns: "accepted", "resync" (the client's copy is wrong: send it the state) or "ignored" (send nothing).
-- Times are on deps.clock; PvpService turns them into server time for the clients.
--
-- A player is attached to at most one match. A match stays after it ends, so the players see the result and can ask
-- for a rematch; it is forgotten once both players have left it.
local RateLimiter = require("./Util/RateLimiter")
local Validate = require("./Util/Validate")

export type Kind = "ranked" | "friendly" | "bot"
export type Result = "win" | "draw" | "loss"
-- How a match ended: the clock ran out, a player forfeited, a player left (or dropped), or the server cancelled it.
export type EndReason = "time" | "forfeit" | "left" | "cancelled"

export type Limit = { capacity: number, windowSeconds: number }

-- The part of Config.PVP this module reads.
export type Settings = { MATCH_SECONDS: number, COUNTDOWN_SECONDS: number, END_GRACE_SECONDS: number }

export type Deps = {
	PvpSession: any,
	settings: Settings,
	clock: () -> number,
	newSeed: () -> number,
	limits: { place: Limit, rotate: Limit, state: Limit, forfeit: Limit, rematch: Limit }?,
}

-- What a player sees of the other's board (see PvpBoardCodec): no tray, no piece ids.
export type BoardView = { cells: { number }, score: number, pending: number, version: number }

export type EndInfo = {
	matchId: number,
	kind: Kind,
	players: { any }, -- by seat
	reason: EndReason,
	results: { Result }?, -- by seat; nil when cancelled
	scores: { number },
	sent: { number }, -- garbage lines each sent
	blocked: { number }, -- garbage lines each cancelled with their own attacks
}

-- What a client needs to (re)build its copy of the match.
export type MatchState = {
	matchId: number,
	kind: Kind,
	seat: number,
	startAt: number,
	endAt: number,
	you: any, -- PvpSession.Snapshot
	opponent: BoardView,
	ended: EndInfo?,
}

export type PlaceOutcome =
	{
		kind: "accepted",
		matchId: number,
		moveIndex: number,
		score: number,
		attack: number,
		cancelled: number,
		sent: number,
		junkLines: number,
		pending: { number }, -- the mover's garbage queue after the move (and the refill)
		refill: any?, -- PvpSession.Refill
		stuck: any?, -- PvpSession.Stuck
		opponent: any, -- the other player's key
		incoming: { number }?, -- the opponent's garbage queue, when this move added to it
	}
	| { kind: "resync", state: MatchState }
	| { kind: "ignored", reason: string }

export type RotateOutcome =
	{ kind: "accepted", matchId: number, charged: ("free" | "paid")? }
	| { kind: "resync", state: MatchState }
	| { kind: "ignored", reason: string }

export type RematchVotes = { votes: { boolean }, ready: boolean }

-- A player's match in a few numbers, for analytics.
export type Summary = {
	matchId: number,
	kind: Kind,
	seat: number,
	score: number,
	moves: number,
	maxCombo: number,
	sent: number,
	blocked: number,
	taken: number,
	stuck: number,
	ended: boolean,
}

type Side = {
	key: any,
	session: any, -- PvpSession
	version: number, -- grows with every change the opponent can see (BoardView.version)
	present: boolean, -- still attached to the match
	rematch: boolean,
	maxCombo: number,
}

type Match = {
	id: number,
	kind: Kind,
	sides: { Side },
	startAt: number,
	endAt: number,
	ended: EndInfo?,
}

local KINDS: { [string]: boolean } = { ranked = true, friendly = true, bot = true }

local DEFAULT_LIMITS = {
	place = { capacity = 8, windowSeconds = 1 },
	rotate = { capacity = 12, windowSeconds = 1 },
	state = { capacity = 2, windowSeconds = 1 },
	forfeit = { capacity = 1, windowSeconds = 2 },
	rematch = { capacity = 2, windowSeconds = 1 },
}
local MAX_MATCH_ID = 2 ^ 31
local MAX_MOVE_INDEX = 1e6

local PvpMatches = {}
PvpMatches.__index = PvpMatches

export type PvpMatches = typeof(setmetatable(
	{} :: {
		deps: Deps,
		matches: { [number]: Match },
		matchOf: { [any]: Match },
		nextMatchId: number,
		placeLimiter: RateLimiter.RateLimiter,
		rotateLimiter: RateLimiter.RateLimiter,
		stateLimiter: RateLimiter.RateLimiter,
		forfeitLimiter: RateLimiter.RateLimiter,
		rematchLimiter: RateLimiter.RateLimiter,
	},
	PvpMatches
))

local function ignored(reason: string): any
	return { kind = "ignored", reason = reason }
end

function PvpMatches.new(deps: Deps): PvpMatches
	local limits = deps.limits or DEFAULT_LIMITS
	local function limiter(limit: Limit): RateLimiter.RateLimiter
		return RateLimiter.new(limit.capacity, limit.windowSeconds, deps.clock)
	end
	return setmetatable({
		deps = deps,
		matches = {},
		matchOf = {},
		nextMatchId = 1,
		placeLimiter = limiter(limits.place),
		rotateLimiter = limiter(limits.rotate),
		stateLimiter = limiter(limits.state),
		forfeitLimiter = limiter(limits.forfeit),
		rematchLimiter = limiter(limits.rematch),
	}, PvpMatches)
end

local function seatOf(match: Match, key: any): number
	return if match.sides[1].key == key then 1 else 2
end

local function boardOf(side: Side): BoardView
	local session = side.session
	return {
		cells = table.clone(session.game.board.cells),
		score = session.game.score,
		pending = #session.pending,
		version = side.version,
	}
end

local function stateOf(match: Match, seat: number): MatchState
	return {
		matchId = match.id,
		kind = match.kind,
		seat = seat,
		startAt = match.startAt,
		endAt = match.endAt,
		you = match.sides[seat].session:snapshot(),
		opponent = boardOf(match.sides[3 - seat]),
		ended = match.ended,
	}
end

local function finish(match: Match, reason: EndReason, loserSeat: number?): EndInfo
	local scores = { match.sides[1].session.game.score, match.sides[2].session.game.score }
	local results: { Result }? = nil
	if reason ~= "cancelled" then
		if loserSeat then
			results = if loserSeat == 1 then { "loss", "win" } else { "win", "loss" }
		elseif scores[1] > scores[2] then
			results = { "win", "loss" }
		elseif scores[1] < scores[2] then
			results = { "loss", "win" }
		else
			results = { "draw", "draw" }
		end
	end
	local info: EndInfo = {
		matchId = match.id,
		kind = match.kind,
		players = { match.sides[1].key, match.sides[2].key },
		reason = reason,
		results = results,
		scores = scores,
		sent = { match.sides[1].session.sentTotal, match.sides[2].session.sentTotal },
		blocked = { match.sides[1].session.blockedTotal, match.sides[2].session.blockedTotal },
	}
	match.ended = info
	return info
end

-- The player's match when `matchId` names it; otherwise nil and why.
local function matchFor(self: PvpMatches, key: any, matchId: unknown): (Match?, string?)
	local match = self.matchOf[key]
	if not match then
		return nil, "no match"
	end
	if Validate.integer(matchId, 1, MAX_MATCH_ID) ~= match.id then
		return nil, "stale or malformed match id"
	end
	if match.ended then
		return nil, "ended"
	end
	return match, nil
end

local function detach(self: PvpMatches, key: any)
	local match = self.matchOf[key]
	if not match then
		return
	end
	self.matchOf[key] = nil
	local side = match.sides[seatOf(match, key)]
	side.present = false
	side.rematch = false
	if not match.sides[1].present and not match.sides[2].present then
		self.matches[match.id] = nil
	end
end

--- Starts a match of `kind` between the room's two players (seat 1 is room.players[1]); the clock starts after the
--- countdown. A player still attached to an ended match (a rematch) leaves it first. Returns each seat's state, or
--- nil, and nothing changes, when the kind is unknown, the players are the same, or either is in a match still going.
function PvpMatches.start(self: PvpMatches, room: { players: { any } }, kind: unknown): { MatchState }?
	if typeof(kind) ~= "string" or not KINDS[kind :: string] then
		return nil
	end
	local a, b = room.players[1], room.players[2]
	if a == nil or b == nil or a == b then
		return nil
	end
	for _, key in { a, b } do
		local current = self.matchOf[key]
		if current and not current.ended then
			return nil
		end
	end
	detach(self, a)
	detach(self, b)

	local deps, settings = self.deps, self.deps.settings
	local startAt = deps.clock() + settings.COUNTDOWN_SECONDS
	local endAt = startAt + settings.MATCH_SECONDS
	local seed = deps.newSeed()
	local function side(key: any, seat: number): Side
		local session = deps.PvpSession.new(seed, seat, startAt, endAt)
		return { key = key, session = session, version = 1, present = true, rematch = false, maxCombo = 0 }
	end
	local match: Match = {
		id = self.nextMatchId,
		kind = kind :: Kind,
		sides = { side(a, 1), side(b, 2) },
		startAt = startAt,
		endAt = endAt,
		ended = nil,
	}
	self.nextMatchId += 1
	self.matches[match.id] = match
	self.matchOf[a] = match
	self.matchOf[b] = match
	return { stateOf(match, 1), stateOf(match, 2) }
end

--- Applies a move. `moveIndex` is how many moves the player had made before this one (as in GameRuns). The attack it
--- sends joins the opponent's garbage queue. A move that arrives after the end plus the grace period is dropped.
function PvpMatches.place(
	self: PvpMatches,
	key: any,
	matchId: unknown,
	moveIndex: unknown,
	slot: unknown,
	x: unknown,
	y: unknown
): PlaceOutcome
	if not self.placeLimiter:allow(key) then
		return ignored("rate limited")
	end
	local match, reason = matchFor(self, key, matchId)
	if not match then
		return ignored(reason :: string)
	end
	local index = Validate.integer(moveIndex, 0, MAX_MOVE_INDEX)
	if index == nil then
		return ignored("malformed move index")
	end
	local now = self.deps.clock()
	if now > match.endAt + self.deps.settings.END_GRACE_SECONDS then
		return ignored("too late")
	end
	local seat = seatOf(match, key)
	local side, other = match.sides[seat], match.sides[3 - seat]
	local session = side.session
	if index < session.game.moveCount then
		return ignored("stale move")
	elseif index > session.game.moveCount then
		return { kind = "resync", state = stateOf(match, seat) }
	end

	-- PvpSession checks the time window, the lock, and the slot and position (types, integers, bounds, overlap).
	local result = session:place(slot, x, y, now)
	if not result then
		return { kind = "resync", state = stateOf(match, seat) }
	end
	side.version += 1
	side.maxCombo = math.max(side.maxCombo, result.move.combo)

	local incoming: { number }? = nil
	if result.sent > 0 and other.session:receiveAttack(result.sent) > 0 then
		other.version += 1
		incoming = table.clone(other.session.pending)
	end
	return {
		kind = "accepted",
		matchId = match.id,
		moveIndex = index,
		score = session.game.score,
		attack = result.attack,
		cancelled = result.cancelled,
		sent = result.sent,
		junkLines = result.junkLines,
		pending = table.clone(session.pending),
		refill = result.refill,
		stuck = result.stuck,
		opponent = other.key,
		incoming = incoming,
	}
end

--- Turns a piece with the match's free rotations. `moveIndex` works as in place().
function PvpMatches.rotate(
	self: PvpMatches,
	key: any,
	matchId: unknown,
	moveIndex: unknown,
	slot: unknown
): RotateOutcome
	if not self.rotateLimiter:allow(key) then
		return ignored("rate limited")
	end
	local match, reason = matchFor(self, key, matchId)
	if not match then
		return ignored(reason :: string)
	end
	local index = Validate.integer(moveIndex, 0, MAX_MOVE_INDEX)
	if index == nil then
		return ignored("malformed move index")
	end
	local seat = seatOf(match, key)
	local session = match.sides[seat].session
	if index < session.game.moveCount then
		return ignored("stale rotation")
	elseif index > session.game.moveCount then
		return { kind = "resync", state = stateOf(match, seat) }
	end
	local result = session:rotate(slot, self.deps.clock())
	if not result then
		return { kind = "resync", state = stateOf(match, seat) }
	end
	return { kind = "accepted", matchId = match.id, charged = result.charged }
end

--- The full state, for a client that noticed it disagrees with the server. Nil when asked too often.
function PvpMatches.state(self: PvpMatches, key: any): MatchState?
	local match = self.matchOf[key]
	if not match or not self.stateLimiter:allow(key) then
		return nil
	end
	return stateOf(match, seatOf(match, key))
end

--- Read-only access for the Studio debug bridge and the service; no rate limit.
function PvpMatches.peek(self: PvpMatches, key: any): MatchState?
	local match = self.matchOf[key]
	return if match then stateOf(match, seatOf(match, key)) else nil
end

--- The player's own board as their opponent sees it, or nil when they are in no match.
function PvpMatches.board(self: PvpMatches, key: any): BoardView?
	local match = self.matchOf[key]
	return if match then boardOf(match.sides[seatOf(match, key)]) else nil
end

--- The other player of the player's match (still attached or not), or nil.
function PvpMatches.opponentOf(self: PvpMatches, key: any): any
	local match = self.matchOf[key]
	return if match then match.sides[3 - seatOf(match, key)].key else nil
end

--- The player gives up: they lose and the other wins. Nil when there is nothing to give up or it is asked too often.
function PvpMatches.forfeit(self: PvpMatches, key: any, matchId: unknown): EndInfo?
	if not self.forfeitLimiter:allow(key) then
		return nil
	end
	local match = matchFor(self, key, matchId)
	if not match then
		return nil
	end
	return finish(match, "forfeit", seatOf(match, key))
end

--- Ends every match whose clock ran out (plus the grace period): the higher score wins, equal scores draw. In match
--- id order.
function PvpMatches.sweep(self: PvpMatches): { EndInfo }
	local now = self.deps.clock()
	local due: { Match } = {}
	for _, match in self.matches do
		if not match.ended and now > match.endAt + self.deps.settings.END_GRACE_SECONDS then
			table.insert(due, match)
		end
	end
	table.sort(due, function(a: Match, b: Match): boolean
		return a.id < b.id
	end)
	local ended: { EndInfo } = {}
	for _, match in due do
		table.insert(ended, finish(match, "time"))
	end
	return ended
end

--- The server is shutting down: ends every match still going without a result. In match id order.
function PvpMatches.cancelAll(self: PvpMatches): { EndInfo }
	local going: { Match } = {}
	for _, match in self.matches do
		if not match.ended then
			table.insert(going, match)
		end
	end
	table.sort(going, function(a: Match, b: Match): boolean
		return a.id < b.id
	end)
	local ended: { EndInfo } = {}
	for _, match in going do
		table.insert(ended, finish(match, "cancelled"))
	end
	return ended
end

--- The player votes for a rematch of their ended match (not ranked: ranked players queue again). Returns the votes by
--- seat and whether both agree, after which the caller starts the next match with start(). Nil when there is no
--- such match, it is ranked, the other player has left, or it is asked too often.
function PvpMatches.rematch(self: PvpMatches, key: any, matchId: unknown): RematchVotes?
	if not self.rematchLimiter:allow(key) then
		return nil
	end
	local match = self.matchOf[key]
	if not match or not match.ended or match.kind == "ranked" then
		return nil
	end
	if Validate.integer(matchId, 1, MAX_MATCH_ID) ~= match.id then
		return nil
	end
	local sides = match.sides
	if not sides[1].present or not sides[2].present then
		return nil
	end
	sides[seatOf(match, key)].rematch = true
	return { votes = { sides[1].rematch, sides[2].rematch }, ready = sides[1].rematch and sides[2].rematch }
end

--- The player leaves their match (the room, or the server): a match still going ends with them losing ("left").
--- Returns how it ended when this ended it.
function PvpMatches.leave(self: PvpMatches, key: any): EndInfo?
	local match = self.matchOf[key]
	if not match then
		return nil
	end
	local info: EndInfo? = nil
	if not match.ended then
		info = finish(match, "left", seatOf(match, key))
	end
	detach(self, key)
	return info
end

--- Forgets everything about the player (call when they leave the server). See leave().
function PvpMatches.remove(self: PvpMatches, key: any): EndInfo?
	local info = self:leave(key)
	self.placeLimiter:forget(key)
	self.rotateLimiter:forget(key)
	self.stateLimiter:forget(key)
	self.forfeitLimiter:forget(key)
	self.rematchLimiter:forget(key)
	return info
end

--- The player's match in a few numbers, or nil when they are in none.
function PvpMatches.summary(self: PvpMatches, key: any): Summary?
	local match = self.matchOf[key]
	if not match then
		return nil
	end
	local seat = seatOf(match, key)
	local side = match.sides[seat]
	local session = side.session
	return {
		matchId = match.id,
		kind = match.kind,
		seat = seat,
		score = session.game.score,
		moves = session.game.moveCount,
		maxCombo = side.maxCombo,
		sent = session.sentTotal,
		blocked = session.blockedTotal,
		taken = session.takenTotal,
		stuck = session.stuckCount,
		ended = match.ended ~= nil,
	}
end

--- The player's own PvpSession, for the server's practice bot to look at (never hand it to a client). Nil when the
--- player is in no match.
function PvpMatches.sessionOf(self: PvpMatches, key: any): any
	local match = self.matchOf[key]
	return if match then match.sides[seatOf(match, key)].session else nil
end

--- For the Studio debug bridge: `lines` of garbage join the player's own queue, as if the opponent had sent them.
--- Returns the queue afterwards, or nil when the player has no match going.
function PvpMatches.addGarbage(self: PvpMatches, key: any, lines: number): { number }?
	local match = self.matchOf[key]
	if not match or match.ended then
		return nil
	end
	local side = match.sides[seatOf(match, key)]
	if side.session:receiveAttack(lines) > 0 then
		side.version += 1
	end
	return table.clone(side.session.pending)
end

--- For the Studio debug bridge: leaves the player one move from being stuck. Their board keeps a single empty cell in
--- each corner and two per row and column (nothing bigger than a single cell fits) and their tray is a Dot and two
--- 3x3 squares, so placing the Dot leaves no move. Returns the state to send them, or nil when no match is going.
function PvpMatches.corner(self: PvpMatches, key: any, pieces: any): MatchState?
	local match = self.matchOf[key]
	if not match or match.ended then
		return nil
	end
	local seat = seatOf(match, key)
	local side = match.sides[seat]
	local game = side.session.game
	local size = math.sqrt(#game.board.cells)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local open = x == y or x + y == size - 1
			game.board.cells[y * size + x + 1] = if open then 0 else 1 + (x + y) % 8
		end
	end
	game.tray = { pieces.BY_ID.Dot, pieces.BY_ID.O3, pieces.BY_ID.O3 }
	game.unlocked = { false, false, false }
	game.awaitingSet = false
	game.isOver = false
	side.version += 1
	return stateOf(match, seat)
end

--- For the Studio debug bridge: ends the player's match now, as if the clock had run out.
function PvpMatches.finishNow(self: PvpMatches, key: any): EndInfo?
	local match = self.matchOf[key]
	if not match or match.ended then
		return nil
	end
	return finish(match, "time")
end

--- How many entries the tables hold (matches, players, rate limiter buckets); 0 once everyone has left.
function PvpMatches.footprint(self: PvpMatches): number
	local count = 0
	for _ in self.matches do
		count += 1
	end
	for _ in self.matchOf do
		count += 1
	end
	for _, limiter in
		{ self.placeLimiter, self.rotateLimiter, self.stateLimiter, self.forfeitLimiter, self.rematchLimiter }
	do
		for _ in limiter.buckets do
			count += 1
		end
	end
	return count
end

return PvpMatches
