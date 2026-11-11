--!strict
-- Every Co-op run on the server, one per room: starts runs with a secret seed, puts the two players' moves in a
-- single order, and decides what each client is told. Pure Luau so Lune can test it with fake players and a
-- fake clock; CoopService wires it to the remotes and to the rooms. The shared modules are passed in because
-- server and shared code sit in different places on disk and in the DataModel.
--
-- Both players place at once, so two moves can clash. The server takes them in the order they arrive: the first
-- is accepted and numbered (`seq`, counting every accepted move of the run), the second no longer fits and is
-- rejected, which sends the piece back to its tray. `moveId` is the sending client's own counter and only lets
-- it recognise its own moves.
-- Everything a client sends is untrusted: requests are rate limited and arguments validated.
local RateLimiter = require("./Util/RateLimiter")
local Validate = require("./Util/Validate")

export type Limit = { capacity: number, windowSeconds: number }

export type Deps = {
	CoopSession: any,
	Rng: any,
	clock: () -> number,
	newSeed: () -> number,
	afkSeconds: number, -- how long nobody may move before a stuck player can take over from their partner
	limits: { place: Limit, state: Limit, takeOver: Limit, rematch: Limit, hover: Limit? }?,
}

-- The two players of a run by seat, as Rooms hands them out (seat 1 invited).
export type Room = { id: number, players: { any }, present: { boolean }? }

-- What a client needs to (re)build its copy of the run.
export type State = {
	runId: number,
	seq: number, -- accepted moves so far; the next move will be seq + 1
	seat: number, -- the receiving player's seat
	players: { any }, -- both players by seat
	session: any, -- CoopSession.Snapshot
	takeOverIn: number?, -- seconds until the player may take over from an idle partner; nil when they can't
}

-- An accepted move, as both clients hear of it.
export type Move = {
	runId: number,
	seq: number,
	seat: number,
	moveId: number,
	slot: number,
	x: number,
	y: number,
	score: number, -- the team score after the move
	set: { string }?, -- the new piece ids when the move used the last piece of the set
	isOver: boolean,
}

export type PlaceOutcome =
	{
		kind: "accepted",
		move: Move,
		players: { any }, -- who to tell, by seat
		linesCleared: number,
		endsRun: boolean, -- game over, the first time for this run
		takeOverIn: { [number]: number }, -- by seat: when that player may take over, for those who may
	}
	| { kind: "rejected", runId: number, moveId: number } -- clashed or no longer valid; tell only the sender
	| { kind: "ignored", reason: string }

-- Where a player is aiming a piece, to be passed on to their partner: slot, x and y are nil when the aim is gone.
export type HoverOutcome = { to: any, slot: number?, x: number?, y: number? }

export type LeaveOutcome = {
	runId: number,
	seat: number,
	stayer: any?, -- the player left in the run
	state: State?, -- what the stayer needs to carry on (every piece is theirs now)
}

export type TakeOverOutcome =
	{ kind: "tookOver", runId: number, evicted: any, state: State }
	| { kind: "ignored", reason: string }

export type RematchOutcome =
	{ kind: "waiting", players: { any }, votes: { boolean } }
	| { kind: "restarted", players: { any }, states: { State } }
	| { kind: "ignored", reason: string }

-- A run in a few numbers, for analytics and the debug bridge.
export type Summary = {
	runId: number,
	roomId: number,
	score: number,
	countedScore: number,
	contribution: { number },
	moves: number,
	maxCombo: number,
	isOver: boolean,
	present: { boolean },
}

type Run = {
	id: number,
	roomId: number,
	players: { any }, -- by seat
	coop: any, -- CoopSession
	lastMoveAt: number, -- when the run started or a move was last accepted
	maxCombo: number,
	endCounted: boolean,
	rematch: { boolean }, -- by seat: pressed Play again
}

local DEFAULT_LIMITS = {
	place = { capacity = 8, windowSeconds = 1 }, -- no human places more than 8 pieces a second
	state = { capacity = 2, windowSeconds = 1 },
	takeOver = { capacity = 1, windowSeconds = 2 },
	rematch = { capacity = 2, windowSeconds = 2 },
	hover = { capacity = 12, windowSeconds = 1 }, -- clients send at most 10 a second
}
local MAX_RUN_ID = 2 ^ 31
local MAX_MOVE_ID = 1e9
local MAX_COORDINATE = 64 -- GameSession checks the board's bounds; this only keeps absurd numbers out

local CoopRuns = {}
CoopRuns.__index = CoopRuns

export type CoopRuns = typeof(setmetatable(
	{} :: {
		deps: Deps,
		runs: { [number]: Run }, -- by room id
		runOf: { [any]: Run }, -- by player, for the players still in their run
		nextRunId: number,
		placeLimiter: RateLimiter.RateLimiter,
		stateLimiter: RateLimiter.RateLimiter,
		takeOverLimiter: RateLimiter.RateLimiter,
		rematchLimiter: RateLimiter.RateLimiter,
		hoverLimiter: RateLimiter.RateLimiter,
	},
	CoopRuns
))

local function ignored(reason: string): any
	return { kind = "ignored", reason = reason }
end

function CoopRuns.new(deps: Deps): CoopRuns
	local limits = deps.limits or DEFAULT_LIMITS
	local function limiter(limit: Limit): RateLimiter.RateLimiter
		return RateLimiter.new(limit.capacity, limit.windowSeconds, deps.clock)
	end
	return setmetatable({
		deps = deps,
		runs = {},
		runOf = {},
		nextRunId = 1,
		placeLimiter = limiter(limits.place),
		stateLimiter = limiter(limits.state),
		takeOverLimiter = limiter(limits.takeOver),
		rematchLimiter = limiter(limits.rematch),
		hoverLimiter = limiter(limits.hover or DEFAULT_LIMITS.hover),
	}, CoopRuns)
end

-- Seconds until `seat` may take over from the partner: only while the player has no move and the partner has one,
-- and nobody has moved for `afkSeconds`. Nil when taking over isn't possible (yet), 0 when it is possible now.
local function takeOverIn(self: CoopRuns, run: Run, seat: number): number?
	local coop = run.coop
	if not (coop.present[1] and coop.present[2]) or coop.session.isOver then
		return nil
	end
	if coop:hasMove(seat) or not coop:hasMove(3 - seat) then
		return nil
	end
	return math.max(0, run.lastMoveAt + self.deps.afkSeconds - self.deps.clock())
end

local function stateFor(self: CoopRuns, run: Run, seat: number): State
	return {
		runId = run.id,
		seq = run.coop.session.moveCount,
		seat = seat,
		players = run.players,
		session = run.coop:snapshot(),
		takeOverIn = takeOverIn(self, run, seat),
	}
end

local function seatOf(run: Run, player: any): number
	return table.find(run.players, player) :: number
end

local function forgetPlayer(self: CoopRuns, player: any, run: Run)
	if self.runOf[player] == run then
		self.runOf[player] = nil
	end
	self.placeLimiter:forget(player)
	self.stateLimiter:forget(player)
	self.takeOverLimiter:forget(player)
	self.rematchLimiter:forget(player)
	self.hoverLimiter:forget(player)
end

-- Starts a run for the room (its players are both in), replacing the room's last one. Returns each seat's state.
function CoopRuns.start(self: CoopRuns, room: Room): { State }?
	local present = room.present
	if present and not (present[1] and present[2]) then
		return nil
	end
	local previous = self.runs[room.id]
	if previous then
		for _, player in previous.players do
			if self.runOf[player] == previous then
				self.runOf[player] = nil
			end
		end
	end

	local deps = self.deps
	local CoopSession = deps.CoopSession
	local run: Run = {
		id = self.nextRunId,
		roomId = room.id,
		players = table.clone(room.players),
		coop = CoopSession.new(CoopSession.newSource(deps.Rng.new(deps.newSeed()))),
		lastMoveAt = deps.clock(),
		maxCombo = 0,
		endCounted = false,
		rematch = { false, false },
	}
	self.nextRunId += 1
	self.runs[room.id] = run
	for _, player in run.players do
		self.runOf[player] = run
	end
	return { stateFor(self, run, 1), stateFor(self, run, 2) }
end

-- Applies a move from `player`. A move that no longer fits (the partner got there first, or the piece is
-- already placed) is rejected rather than ignored, so the client can put the piece back.
function CoopRuns.place(
	self: CoopRuns,
	player: any,
	runId: unknown,
	moveId: unknown,
	slot: unknown,
	x: unknown,
	y: unknown
): PlaceOutcome
	if not self.placeLimiter:allow(player) then
		return ignored("rate limited")
	end
	local run = self.runOf[player]
	if not run then
		return ignored("no run")
	end
	if Validate.integer(runId, 1, MAX_RUN_ID) ~= run.id then
		return ignored("stale or malformed run id")
	end
	local id = Validate.integer(moveId, 0, MAX_MOVE_ID)
	if id == nil then
		return ignored("malformed move id")
	end
	local CoopSession = self.deps.CoopSession
	if
		CoopSession.seatOf(slot) == nil
		or Validate.integer(x, -MAX_COORDINATE, MAX_COORDINATE) == nil
		or Validate.integer(y, -MAX_COORDINATE, MAX_COORDINATE) == nil
	then
		return ignored("malformed move")
	end

	local coop = run.coop
	local seat = seatOf(run, player)
	local result = coop:place(seat, slot, x, y)
	if not result then
		return { kind = "rejected", runId = run.id, moveId = id }
	end

	run.lastMoveAt = self.deps.clock()
	run.maxCombo = math.max(run.maxCombo, result.combo)
	local session = coop.session
	local endsRun = session.isOver and not run.endCounted
	if endsRun then
		run.endCounted = true
	end
	local set: { string }? = nil
	if result.refilled then
		local ids = {}
		for i, piece in session.tray do
			ids[i] = piece.id
		end
		set = ids
	end
	local wait: { [number]: number } = {}
	for seatIndex = 1, 2 do
		local seconds = takeOverIn(self, run, seatIndex)
		if seconds then
			wait[seatIndex] = seconds
		end
	end
	return {
		kind = "accepted",
		move = {
			runId = run.id,
			seq = session.moveCount,
			seat = seat,
			moveId = id,
			slot = result.slot,
			x = result.x,
			y = result.y,
			score = session.score,
			set = set,
			isOver = session.isOver,
		},
		players = run.players,
		linesCleared = #result.clearedRows + #result.clearedCols,
		endsRun = endsRun,
		takeOverIn = wait,
	}
end

-- `player` says where they are aiming one of their pieces (a board cell, the piece's top left), or that they no
-- longer are (no arguments). Returns what to tell the partner, or nil when there is nobody to tell or the aim
-- makes no sense (not the player's own piece, off the board, too often): it is only a shadow for the partner to
-- see, so a bad one is dropped quietly.
function CoopRuns.hover(self: CoopRuns, player: any, slot: unknown, x: unknown, y: unknown): HoverOutcome?
	if not self.hoverLimiter:allow(player) then
		return nil
	end
	local run = self.runOf[player]
	if not run then
		return nil
	end
	local seat = seatOf(run, player)
	local partner = run.players[3 - seat]
	if not run.coop.present[3 - seat] or self.runOf[partner] ~= run then
		return nil
	end
	if slot == nil and x == nil and y == nil then
		return { to = partner }
	end
	local coop = run.coop
	if self.deps.CoopSession.seatOf(slot) == nil or not coop:mayPlace(seat, slot) then
		return nil
	end
	local piece = coop.session.tray[slot :: number]
	if not piece then
		return nil
	end
	local size = math.floor(math.sqrt(#coop.session.board.cells) + 0.5)
	local cellX = Validate.integer(x, 0, size - piece.width)
	local cellY = Validate.integer(y, 0, size - piece.height)
	if cellX == nil or cellY == nil then
		return nil
	end
	return { to = partner, slot = slot :: number, x = cellX, y = cellY }
end

-- The full state, for a client that noticed it disagrees with the server. Nil when asked too often, or with no run.
function CoopRuns.state(self: CoopRuns, player: any): State?
	local run = self.runOf[player]
	if not run or not self.stateLimiter:allow(player) then
		return nil
	end
	return stateFor(self, run, seatOf(run, player))
end

-- `player` is out of their run (left the room or the server): the partner, if any, carries on with every piece.
-- Nil when they weren't in a run (any more).
function CoopRuns.leave(self: CoopRuns, player: any): LeaveOutcome?
	local run = self.runOf[player]
	if not run then
		return nil
	end
	local seat = seatOf(run, player)
	forgetPlayer(self, player, run)
	if not run.coop:release(seat) then
		return nil
	end
	run.rematch[seat] = false
	run.rematch[3 - seat] = false
	local stayerSeat = 3 - seat
	local stayer = if run.coop.present[stayerSeat] then run.players[stayerSeat] else nil
	return {
		runId = run.id,
		seat = seat,
		stayer = stayer,
		state = if stayer then stateFor(self, run, stayerSeat) else nil,
	}
end

-- `player` is stuck and the partner hasn't moved for the idle time: the partner is put out of the run (the caller
-- takes them out of the room too) and every piece is the player's.
function CoopRuns.takeOver(self: CoopRuns, player: any, runId: unknown): TakeOverOutcome
	if not self.takeOverLimiter:allow(player) then
		return ignored("rate limited")
	end
	local run = self.runOf[player]
	if not run then
		return ignored("no run")
	end
	if Validate.integer(runId, 1, MAX_RUN_ID) ~= run.id then
		return ignored("stale or malformed run id")
	end
	local seat = seatOf(run, player)
	local wait = takeOverIn(self, run, seat)
	if wait == nil then
		return ignored("not waiting for a partner who can move")
	elseif wait > 0 then
		return ignored("partner has not been idle long enough")
	end
	local evicted = run.players[3 - seat]
	run.coop:release(3 - seat)
	forgetPlayer(self, evicted, run)
	return { kind = "tookOver", runId = run.id, evicted = evicted, state = stateFor(self, run, seat) }
end

-- "Play again" from `player`. The run restarts once both have asked, after it is over, and both are still in it.
function CoopRuns.rematch(self: CoopRuns, player: any): RematchOutcome
	if not self.rematchLimiter:allow(player) then
		return ignored("rate limited")
	end
	local run = self.runOf[player]
	if not run then
		return ignored("no run")
	end
	if not run.coop.session.isOver then
		return ignored("the run is not over")
	end
	if not (run.coop.present[1] and run.coop.present[2]) then
		return ignored("the partner has left")
	end
	run.rematch[seatOf(run, player)] = true
	if run.rematch[1] and run.rematch[2] then
		local players = run.players
		local states = self:start({ id = run.roomId, players = players, present = { true, true } })
		return if states
			then { kind = "restarted", players = players, states = states }
			else ignored("could not restart")
	end
	return { kind = "waiting", players = run.players, votes = table.clone(run.rematch) }
end

-- The room is gone: forget its run.
function CoopRuns.close(self: CoopRuns, roomId: number)
	local run = self.runs[roomId]
	if not run then
		return
	end
	for _, player in run.players do
		forgetPlayer(self, player, run)
	end
	self.runs[roomId] = nil
end

-- A player left the server: forget their limits and any run they were still in.
function CoopRuns.remove(self: CoopRuns, player: any)
	local run = self.runOf[player]
	if run then
		forgetPlayer(self, player, run)
	else
		self.placeLimiter:forget(player)
		self.stateLimiter:forget(player)
		self.takeOverLimiter:forget(player)
		self.rematchLimiter:forget(player)
		self.hoverLimiter:forget(player)
	end
end

-- The player's current run in a few numbers, or nil when they are not in one.
function CoopRuns.summary(self: CoopRuns, player: any): Summary?
	local run = self.runOf[player]
	if not run then
		return nil
	end
	local coop = run.coop
	return {
		runId = run.id,
		roomId = run.roomId,
		score = coop.session.score,
		countedScore = coop.countedScore,
		contribution = table.clone(coop.contribution),
		moves = coop.session.moveCount,
		maxCombo = run.maxCombo,
		isOver = coop.session.isOver,
		present = table.clone(coop.present),
	}
end

-- Read-only access to the player's run for the Studio debug bridge and the practice partner: the run's id, the
-- player's seat and the live CoopSession (do not change it). No rate limit.
function CoopRuns.peek(self: CoopRuns, player: any): { runId: number, seat: number, coop: any }?
	local run = self.runOf[player]
	if not run then
		return nil
	end
	return { runId = run.id, seat = seatOf(run, player), coop = run.coop }
end

-- How many entries every table holds; zero once every room is closed and every player gone.
function CoopRuns.footprint(self: CoopRuns): number
	local count = 0
	for _ in self.runs do
		count += 1
	end
	for _ in self.runOf do
		count += 1
	end
	for _, limiter in
		{
			self.placeLimiter,
			self.stateLimiter,
			self.takeOverLimiter,
			self.rematchLimiter,
			self.hoverLimiter,
		}
	do
		for _ in limiter.buckets do
			count += 1
		end
	end
	return count
end

return CoopRuns
