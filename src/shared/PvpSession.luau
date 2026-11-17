--!strict
-- One player's side of a PVP match (see docs/PHASE6.md): a GameSession whose sets are dealt here instead of by
-- a set source, plus the attack table, the garbage queue, garbage entering the board, and the "stuck" rule.
--
-- The server builds it with new() and is the authority: it knows the match seed, draws sets, garbage sides and holes,
-- and after a placement refills the tray or unsticks the board itself, reporting what it did in the PlaceResult. The
-- client builds it with fromSnapshot(), predicts its own placements with the same place(), and replays what the
-- server reports with deliver(), applyStuck() and setPending(). Both run the same code, so they stay cell for cell
-- equal.
--
-- Sets: set k of both players is drawn from Rng.mix(seed, "set", k) with the difficulty of a solo run at score
-- (k - 1) * DIFFICULTY_SCORE_PER_SET and mercy off, so both players start set k with the same candidates; each takes
-- the first one that passes the fairness check on their own board. A set dealt after being stuck comes from a
-- separate stream per seat, so it doesn't shift the set numbers.
--
-- Times (startAt, endAt, lockedUntil, now) are seconds on whatever clock the caller uses, as long as it is one clock.

local Board = require("./Board")
local Config = require("./Config")
local GameSession = require("./GameSession")
local Generator = require("./Generator")
local Pieces = require("./Pieces")
local Rng = require("./Rng")
local Scoring = require("./Scoring")

type Piece = Pieces.Piece
type Rng = Rng.Rng

local PVP = Config.PVP
local SIZE = Config.GRID_SIZE

-- Wire codes for the edge a garbage line comes in from: 1 bottom, 2 left, 3 right.
local SIDES: { Board.PushSide } = { "bottom", "left", "right" }

-- One garbage line as it enters a board: `side` is a wire code (1 bottom, 2 left, 3 right), `hole` 0 to 7.
export type Garbage = { side: number, hole: number }

-- What the server did after the third piece of a set: garbage that entered the board, then the new set (piece ids).
export type Refill = { garbage: { Garbage }, set: { string } }

-- What the server did when no piece fit: cleared the middle, dealt `set` and locked the tray until `lockedUntil`.
export type Stuck = { set: { string }, lockedUntil: number }

export type PlaceResult = {
	move: GameSession.PlaceResult, -- points and combo already exclude junk lines
	junkLines: number, -- cleared lines that were mostly garbage (no points, combo or attack)
	attack: number, -- garbage lines this move earned
	cancelled: number, -- of those, lines taken off this player's own queue
	sent: number, -- the rest, for the opponent's queue
	refill: Refill?, -- server only
	stuck: Stuck?, -- server only
}

-- Plain-data copy, safe to send through a remote. Never holds the match seed.
export type Snapshot = {
	game: GameSession.Snapshot,
	seat: number,
	setIndex: number,
	pending: { number }, -- garbage waiting, as side codes; the first entry enters next
	startAt: number,
	endAt: number,
	lockedUntil: number,
	sentTotal: number,
	blockedTotal: number,
	takenTotal: number,
	stuckCount: number,
}

local PvpSession = {}
PvpSession.__index = PvpSession

export type PvpSession = typeof(setmetatable(
	{} :: {
		game: GameSession.GameSession,
		seed: number?, -- nil on the client
		garbageRng: Rng?, -- nil on the client
		seat: number,
		setIndex: number, -- sets dealt so far, not counting the ones dealt after being stuck
		pending: { number },
		startAt: number,
		endAt: number,
		lockedUntil: number,
		sentTotal: number,
		blockedTotal: number, -- garbage cancelled by this player's own attacks
		takenTotal: number, -- garbage that entered this player's board
		stuckCount: number,
	},
	PvpSession
))

-- The tray waits for this module to deal; GameSession never draws a set itself.
local function noSource(): { Piece }?
	return nil
end

local function isInteger(value: unknown): boolean
	return typeof(value) == "number" and value == math.floor(value)
end

local function idsOf(set: { Piece }): { string }
	local ids = table.create(#set)
	for i, piece in set do
		ids[i] = piece.id
	end
	return ids
end

-- Pieces for wire ids, or nil when the list isn't a whole set of known pieces.
local function piecesOf(ids: unknown, setSize: number): { Piece }?
	if typeof(ids) ~= "table" or #(ids :: { any }) ~= setSize then
		return nil
	end
	local pieces = table.create(setSize)
	for i = 1, setSize do
		local id = (ids :: { any })[i]
		local piece = if typeof(id) == "string" then Pieces.BY_ID[id] else nil
		if not piece then
			return nil
		end
		pieces[i] = piece
	end
	return pieces
end

local function isGarbageList(garbage: unknown): boolean
	if typeof(garbage) ~= "table" then
		return false
	end
	for _, line in garbage :: { any } do
		if typeof(line) ~= "table" or not isInteger(line.side) or not isInteger(line.hole) then
			return false
		end
		if line.side < 1 or line.side > #SIDES or line.hole < 0 or line.hole >= SIZE then
			return false
		end
	end
	return true
end

local function isPendingList(pending: unknown): boolean
	if typeof(pending) ~= "table" or #(pending :: { any }) > PVP.GARBAGE_QUEUE_MAX then
		return false
	end
	for _, side in pending :: { any } do
		if not isInteger(side) or side < 1 or side > #SIDES then
			return false
		end
	end
	return true
end

-- Garbage enters the board line by line; lines left full by a push clear at once, without points or a combo change.
local function applyGarbage(self: PvpSession, garbage: { Garbage })
	local board = self.game.board
	for _, line in garbage do
		local full = Board.pushLine(board, SIDES[line.side], line.hole, PVP.GARBAGE_COLOR)
		Board.clearLines(board, full)
		self.takenTotal += 1
	end
end

-- How many of the lines the move cleared were junk: more than JUNK_LINE_GARBAGE_SHARE of their cells were garbage
-- on the board before the move.
local function countJunk(before: Board.Board, move: GameSession.PlaceResult): number
	local limit = SIZE * PVP.JUNK_LINE_GARBAGE_SHARE
	local junk = 0
	for _, row in move.clearedRows do
		local garbage = 0
		for x = 0, SIZE - 1 do
			if Board.get(before, x, row) == PVP.GARBAGE_COLOR then
				garbage += 1
			end
		end
		if garbage > limit then
			junk += 1
		end
	end
	for _, col in move.clearedCols do
		local garbage = 0
		for y = 0, SIZE - 1 do
			if Board.get(before, col, y) == PVP.GARBAGE_COLOR then
				garbage += 1
			end
		end
		if garbage > limit then
			junk += 1
		end
	end
	return junk
end

local function drawSet(self: PvpSession, k: number, rng: Rng, reason: Generator.DealReason): { Piece }
	local score = (k - 1) * PVP.DIFFICULTY_SCORE_PER_SET
	return Generator.nextSet(self.game.board, score, rng, reason, Config.PIECES_PER_SET, PVP.GENERATOR)
end

-- Server: takes up to GARBAGE_PER_SET lines off the queue, draws their holes, pushes them in, then deals the next set.
local function refill(self: PvpSession): Refill
	local seed, garbageRng = self.seed :: number, self.garbageRng :: Rng
	local garbage: { Garbage } = {}
	for _ = 1, PVP.GARBAGE_PER_SET do
		local side = table.remove(self.pending, 1)
		if side == nil then
			break
		end
		table.insert(garbage, { side = side, hole = garbageRng:nextInt(0, SIZE - 1) })
	end
	applyGarbage(self, garbage)
	self.setIndex += 1
	local set = drawSet(self, self.setIndex, Rng.new(Rng.mix(seed, "set", self.setIndex)), "Normal")
	self.game:receiveSet(set)
	return { garbage = garbage, set = idsOf(set) }
end

-- Clears the middle like a revive and resets the combo, deals the set `makeSet` returns for the cleared board, and
-- locks the tray. Garbage waiting stays in the queue.
local function unstickWith(self: PvpSession, makeSet: () -> { Piece }, lockedUntil: number)
	self.game:revive()
	self.stuckCount += 1
	self.game:receiveSet(makeSet())
	self.lockedUntil = lockedUntil
end

local function unstick(self: PvpSession, now: number): Stuck
	local seed = self.seed :: number
	local set: { Piece } = {}
	unstickWith(self, function()
		local rng = Rng.new(Rng.mix(seed, "stuck", self.seat, self.stuckCount))
		set = drawSet(self, self.setIndex, rng, "Revive")
		return set
	end, now + PVP.STUCK_LOCK_SECONDS)
	return { set = idsOf(set), lockedUntil = self.lockedUntil }
end

--- Garbage lines one placement earns: by lines cleared at once, plus the combo bonus when the combo after the move is
--- at ATTACK_COMBO_FROM or more, plus the board clear bonus. A move that clears nothing earns nothing.
function PvpSession.attackFor(linesCleared: number, combo: number, boardCleared: boolean): number
	if linesCleared <= 0 then
		return 0
	end
	local byLines = PVP.ATTACK_BY_LINES
	local attack = byLines[math.min(linesCleared, #byLines)]
	if combo >= PVP.ATTACK_COMBO_FROM then
		attack += PVP.ATTACK_COMBO_BONUS
	end
	if boardCleared then
		attack += PVP.ATTACK_BOARD_CLEAR_BONUS
	end
	return attack
end

--- Server: a new side for `seat` (1 or 2) of the match with this secret `seed`, playable from `startAt` to `endAt`.
--- Deals the first set right away.
function PvpSession.new(seed: number, seat: number, startAt: number, endAt: number): PvpSession
	local game = GameSession.new(noSource)
	game.freeRotations = PVP.FREE_ROTATIONS
	local self = setmetatable({
		game = game,
		seed = seed,
		garbageRng = Rng.new(Rng.mix(seed, "garbage", seat)),
		seat = seat,
		setIndex = 1,
		pending = {},
		startAt = startAt,
		endAt = endAt,
		lockedUntil = -math.huge,
		sentTotal = 0,
		blockedTotal = 0,
		takenTotal = 0,
		stuckCount = 0,
	}, PvpSession)
	self.game:receiveSet(drawSet(self, 1, Rng.new(Rng.mix(seed, "set", 1)), "Normal"))
	return self
end

--- Client: rebuilds a side from snapshot() output (the server's state). It can predict placements but never deals.
function PvpSession.fromSnapshot(snapshot: Snapshot): PvpSession
	return setmetatable({
		game = GameSession.fromSnapshot(snapshot.game, noSource),
		seed = nil,
		garbageRng = nil,
		seat = snapshot.seat,
		setIndex = snapshot.setIndex,
		pending = table.clone(snapshot.pending),
		startAt = snapshot.startAt,
		endAt = snapshot.endAt,
		lockedUntil = snapshot.lockedUntil,
		sentTotal = snapshot.sentTotal,
		blockedTotal = snapshot.blockedTotal,
		takenTotal = snapshot.takenTotal,
		stuckCount = snapshot.stuckCount,
	}, PvpSession)
end

function PvpSession.snapshot(self: PvpSession): Snapshot
	return {
		game = self.game:snapshot(),
		seat = self.seat,
		setIndex = self.setIndex,
		pending = table.clone(self.pending),
		startAt = self.startAt,
		endAt = self.endAt,
		lockedUntil = self.lockedUntil,
		sentTotal = self.sentTotal,
		blockedTotal = self.blockedTotal,
		takenTotal = self.takenTotal,
		stuckCount = self.stuckCount,
	}
end

--- Whether the tray is locked after being stuck.
function PvpSession.isLocked(self: PvpSession, now: number): boolean
	return now < self.lockedUntil
end

--- Whether a move made at `now` counts: the match has started, isn't past its end plus the grace period, and the tray
--- isn't locked. (The client stops dragging at endAt itself; the grace is for moves still on their way to the server.)
function PvpSession.canAct(self: PvpSession, now: unknown): boolean
	if typeof(now) ~= "number" or now ~= now then
		return false
	end
	return now >= self.startAt and now <= self.endAt + PVP.END_GRACE_SECONDS and now >= self.lockedUntil
end

--- Places a piece (values may come from a remote; invalid moves return nil and change nothing). Junk lines (mostly
--- garbage, see Config.PVP.JUNK_LINE_GARBAGE_SHARE) clear without points, combo or attack. The attack the move earns
--- first cancels garbage waiting on this player, nearest first; the rest is `sent`. On the server, a placement that
--- empties the tray also refills it (garbage first) and one that leaves no move unsticks the board; the result says so.
function PvpSession.place(self: PvpSession, slot: unknown, x: unknown, y: unknown, now: unknown): PlaceResult?
	if not self:canAct(now) then
		return nil
	end
	local game = self.game
	local before, comboBefore, scoreBefore = Board.clone(game.board), game.combo, game.score
	local move = game:place(slot, x, y)
	if not move then
		return nil
	end

	-- Junk lines clear without points, combo or attack: score the move again as if they hadn't been lines.
	local junk = countJunk(before, move)
	local lines = #move.clearedRows + #move.clearedCols - junk
	if junk > 0 then
		local rescored = Scoring.scoreMove(comboBefore, #move.piece.cells, lines, move.boardCleared and lines > 0)
		game.score = scoreBefore + rescored.total
		game.combo = rescored.nextCombo
		move.points = rescored.total
		move.combo = rescored.nextCombo.combo
	end

	local attack = PvpSession.attackFor(lines, move.combo, move.boardCleared)
	local cancelled = math.min(attack, #self.pending)
	for _ = 1, cancelled do
		table.remove(self.pending, 1)
	end
	local sent = attack - cancelled
	self.blockedTotal += cancelled
	self.sentTotal += sent

	local refilled: Refill?, stuck: Stuck? = nil, nil
	if self.seed ~= nil then
		if self.game.awaitingSet then
			refilled = refill(self)
		end
		if self.game.isOver then
			stuck = unstick(self, now :: number)
		end
	end
	return {
		move = move,
		junkLines = junk,
		attack = attack,
		cancelled = cancelled,
		sent = sent,
		refill = refilled,
		stuck = stuck,
	}
end

--- Turns the piece in `slot`, paying with the match's free rotations only (bought rotations don't work in PVP).
function PvpSession.rotate(self: PvpSession, slot: unknown, now: unknown): GameSession.RotateResult?
	if not self:canAct(now) then
		return nil
	end
	return self.game:rotate(slot, 0)
end

--- Server: `lines` of attack from the opponent join the end of the queue, each with a side drawn now so the player sees
--- it coming. Lines past GARBAGE_QUEUE_MAX are dropped. Returns how many joined.
function PvpSession.receiveAttack(self: PvpSession, lines: number): number
	local garbageRng = self.garbageRng
	if garbageRng == nil then
		error("receiveAttack runs on the server only", 2)
	end
	if not isInteger(lines) or lines < 0 then
		error(`lines must be a whole number, got {lines}`, 2)
	end
	local joined = 0
	for _ = 1, lines do
		if #self.pending >= PVP.GARBAGE_QUEUE_MAX then
			break
		end
		table.insert(self.pending, garbageRng:nextInt(1, #SIDES))
		joined += 1
	end
	return joined
end

--- Client: replaces the garbage queue with the server's. False, and nothing changes, if the list is malformed.
function PvpSession.setPending(self: PvpSession, pending: unknown): boolean
	if not isPendingList(pending) then
		return false
	end
	self.pending = table.clone(pending :: { number })
	return true
end

--- Client: replays a refill the server reported. False, and nothing changes, unless the tray is awaiting a set and
--- the values are well formed.
function PvpSession.deliver(self: PvpSession, garbage: unknown, set: unknown): boolean
	local pieces = piecesOf(set, self.game.setSize)
	if not self.game.awaitingSet or not pieces or not isGarbageList(garbage) then
		return false
	end
	applyGarbage(self, garbage :: { Garbage })
	self.setIndex += 1
	self.game:receiveSet(pieces)
	return true
end

--- Client: replays an unstick the server reported. False, and nothing changes, unless no piece fits and the values
--- are well formed.
function PvpSession.applyStuck(self: PvpSession, set: unknown, lockedUntil: unknown): boolean
	local pieces = piecesOf(set, self.game.setSize)
	if not self.game.isOver or not pieces or typeof(lockedUntil) ~= "number" or lockedUntil ~= lockedUntil then
		return false
	end
	unstickWith(self, function()
		return pieces
	end, lockedUntil :: number)
	return true
end

return PvpSession
