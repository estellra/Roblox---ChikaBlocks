--!strict
-- Every player's run on the server: starts runs with a secret seed, applies moves, and decides what each
-- client is told. Pure Luau so Lune can test it with fake players and a fake clock. The shared modules are
-- passed in because server and shared code sit in different places on disk and in the DataModel.
-- Everything a client sends is untrusted: requests are rate limited and arguments validated.
local RateLimiter = require("./Util/RateLimiter")
local Validate = require("./Util/Validate")

export type Limit = { capacity: number, windowSeconds: number }

export type Deps = {
	GameSession: any,
	Generator: any,
	Rng: any,
	Tutorial: any?, -- needed only for tutorial runs
	clock: () -> number,
	newSeed: () -> number,
	limits: { place: Limit, start: Limit, state: Limit, rotate: Limit? }?,
}

-- "tutorial" runs open with Tutorial's fixed board and tray, then continue like normal runs.
export type RunMode = "normal" | "tutorial"

-- What the client needs to (re)build its copy of the run.
export type RunState = {
	runId: number,
	mode: RunMode,
	best: number,
	session: any, -- GameSession.Snapshot
}

export type PlaceOutcome =
	{
		kind: "accepted",
		runId: number,
		mode: RunMode,
		moveIndex: number,
		score: number,
		linesCleared: number, -- rows plus columns this move cleared
		endsRun: boolean, -- game over, and the first one of this run (a revived run can end again)
		set: { string }?,
		isOver: boolean,
		best: number,
	}
	| { kind: "resync", state: RunState }
	| { kind: "ignored", reason: string }

export type RotateOutcome =
	{ kind: "accepted", runId: number, charged: ("free" | "paid")? }
	| { kind: "resync", state: RunState }
	| { kind: "ignored", reason: string }

-- A run in a few numbers, for analytics.
export type RunSummary = {
	runId: number,
	mode: RunMode,
	score: number,
	moves: number,
	maxCombo: number,
	isOver: boolean,
	revives: number,
}

type Run = { id: number, mode: RunMode, session: any, maxCombo: number, endCounted: boolean }

local MODES: { [string]: boolean } = { normal = true, tutorial = true }

local DEFAULT_LIMITS = {
	place = { capacity = 8, windowSeconds = 1 }, -- no human places more than 8 pieces a second
	start = { capacity = 1, windowSeconds = 0.5 },
	state = { capacity = 2, windowSeconds = 1 },
	rotate = { capacity = 12, windowSeconds = 1 }, -- tapping to look at each turn of a piece
}
local MAX_RUN_ID = 2 ^ 31
local MAX_MOVE_INDEX = 1e6

local GameRuns = {}
GameRuns.__index = GameRuns

export type GameRuns = typeof(setmetatable(
	{} :: {
		deps: Deps,
		runs: { [any]: Run },
		bests: { [any]: number },
		nextRunId: number,
		placeLimiter: RateLimiter.RateLimiter,
		startLimiter: RateLimiter.RateLimiter,
		stateLimiter: RateLimiter.RateLimiter,
		rotateLimiter: RateLimiter.RateLimiter,
	},
	GameRuns
))

local function ignored(reason: string): any
	return { kind = "ignored", reason = reason }
end

function GameRuns.new(deps: Deps): GameRuns
	local limits = deps.limits or DEFAULT_LIMITS
	local function limiter(limit: Limit): RateLimiter.RateLimiter
		return RateLimiter.new(limit.capacity, limit.windowSeconds, deps.clock)
	end
	return setmetatable({
		deps = deps,
		runs = {},
		bests = {},
		nextRunId = 1,
		placeLimiter = limiter(limits.place),
		startLimiter = limiter(limits.start),
		stateLimiter = limiter(limits.state),
		rotateLimiter = limiter(limits.rotate or DEFAULT_LIMITS.rotate),
	}, GameRuns)
end

local function stateOf(self: GameRuns, key: any, run: Run): RunState
	return { runId = run.id, mode = run.mode, best = self.bests[key] or 0, session = run.session:snapshot() }
end

-- Starts (or restarts) the player's run; `mode` is "normal" (or nil) or "tutorial". Nil when the mode is
-- unknown or the player asks too often.
function GameRuns.start(self: GameRuns, key: any, mode: unknown?): RunState?
	local runMode: RunMode = "normal"
	if mode ~= nil then
		if typeof(mode) ~= "string" or not MODES[mode :: string] then
			return nil
		end
		runMode = mode :: any
	end
	if not self.startLimiter:allow(key) then
		return nil
	end

	local deps = self.deps
	local dealNext = deps.Generator.newSource(deps.Rng.new(deps.newSeed()))
	local session
	if runMode == "tutorial" then
		local tutorial = deps.Tutorial :: any
		local openingDealt = false
		session = deps.GameSession.new(function(board: any, score: number, reason: any): any
			if not openingDealt then
				openingDealt = true
				return tutorial.tray()
			end
			return dealNext(board, score, reason)
		end, tutorial.newBoard())
	else
		session = deps.GameSession.new(dealNext)
	end
	local run = { id = self.nextRunId, mode = runMode, session = session, maxCombo = 0, endCounted = false }
	self.nextRunId += 1
	self.runs[key] = run
	return stateOf(self, key, run)
end

-- Applies a move. `moveIndex` is how many moves the client had made before this one: an older index is a
-- leftover from before a resync and is dropped; a newer one means the client got ahead of the server.
function GameRuns.place(
	self: GameRuns,
	key: any,
	runId: unknown,
	moveIndex: unknown,
	slot: unknown,
	x: unknown,
	y: unknown
): PlaceOutcome
	if not self.placeLimiter:allow(key) then
		return ignored("rate limited")
	end
	local run = self.runs[key]
	if not run then
		return ignored("no run")
	end
	if Validate.integer(runId, 1, MAX_RUN_ID) ~= run.id then
		return ignored("stale or malformed run id")
	end
	local index = Validate.integer(moveIndex, 0, MAX_MOVE_INDEX)
	if index == nil then
		return ignored("malformed move index")
	end
	local session = run.session
	if index < session.moveCount then
		return ignored("stale move")
	elseif index > session.moveCount then
		return { kind = "resync", state = stateOf(self, key, run) }
	end

	-- GameSession validates slot, x and y itself (types, integers, bounds, overlap, game over).
	local result = session:place(slot, x, y)
	if not result then
		return { kind = "resync", state = stateOf(self, key, run) }
	end

	run.maxCombo = math.max(run.maxCombo, result.combo)
	local best = math.max(self.bests[key] or 0, session.score)
	self.bests[key] = best
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
	return {
		kind = "accepted",
		runId = run.id,
		mode = run.mode,
		moveIndex = index,
		score = session.score,
		linesCleared = #result.clearedRows + #result.clearedCols,
		endsRun = endsRun,
		set = set,
		isOver = session.isOver,
		best = best,
	}
end

-- Turns a piece in the tray. `moveIndex` works as in place(): rotations happen between two moves. A
-- rotation that costs one of the player's bought rotations says so ("paid"); spending it is up to the caller.
-- `paidAvailable` is how many the player has bought and not used.
function GameRuns.rotate(
	self: GameRuns,
	key: any,
	runId: unknown,
	moveIndex: unknown,
	slot: unknown,
	paidAvailable: number
): RotateOutcome
	if not self.rotateLimiter:allow(key) then
		return ignored("rate limited")
	end
	local run = self.runs[key]
	if not run then
		return ignored("no run")
	end
	if run.mode ~= "normal" then
		return ignored("rotating is for normal runs")
	end
	if Validate.integer(runId, 1, MAX_RUN_ID) ~= run.id then
		return ignored("stale or malformed run id")
	end
	local index = Validate.integer(moveIndex, 0, MAX_MOVE_INDEX)
	if index == nil then
		return ignored("malformed move index")
	end
	local session = run.session
	if index < session.moveCount then
		return ignored("stale rotation")
	elseif index > session.moveCount then
		return { kind = "resync", state = stateOf(self, key, run) }
	end

	local result = session:rotate(slot, paidAvailable)
	if not result then
		return { kind = "resync", state = stateOf(self, key, run) }
	end
	return { kind = "accepted", runId = run.id, charged = result.charged }
end

-- The full state, for a client that noticed it disagrees with the server. Nil when asked too often.
function GameRuns.state(self: GameRuns, key: any): RunState?
	local run = self.runs[key]
	if not run or not self.stateLimiter:allow(key) then
		return nil
	end
	return stateOf(self, key, run)
end

-- Read-only access for the Studio debug bridge; no rate limit.
function GameRuns.peek(self: GameRuns, key: any): RunState?
	local run = self.runs[key]
	return if run then stateOf(self, key, run) else nil
end

-- Revives the player's finished run: the middle of the board is cleared and a fresh set dealt. Nil when
-- there is nothing to revive (no such run, a tutorial run, not over). Paying for it is the caller's business.
function GameRuns.revive(self: GameRuns, key: any, runId: unknown): RunState?
	local run = self.runs[key]
	if not run or run.mode ~= "normal" then
		return nil
	end
	if Validate.integer(runId, 1, MAX_RUN_ID) ~= run.id then
		return nil
	end
	if not run.session:revive() then
		return nil
	end
	return stateOf(self, key, run)
end

-- The player's current run in a few numbers, or nil when they have none.
function GameRuns.summary(self: GameRuns, key: any): RunSummary?
	local run = self.runs[key]
	if not run then
		return nil
	end
	local session = run.session
	return {
		runId = run.id,
		mode = run.mode,
		score = session.score,
		moves = session.moveCount,
		maxCombo = run.maxCombo,
		isOver = session.isOver,
		revives = session.revivesUsed,
	}
end

function GameRuns.getBest(self: GameRuns, key: any): number
	return self.bests[key] or 0
end

function GameRuns.setBest(self: GameRuns, key: any, best: number)
	self.bests[key] = best
end

-- Forgets everything about the player (call when they leave).
function GameRuns.remove(self: GameRuns, key: any)
	self.runs[key] = nil
	self.bests[key] = nil
	self.placeLimiter:forget(key)
	self.startLimiter:forget(key)
	self.stateLimiter:forget(key)
	self.rotateLimiter:forget(key)
end

return GameRuns
