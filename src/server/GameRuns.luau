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
	clock: () -> number,
	newSeed: () -> number,
	limits: { place: Limit, start: Limit, state: Limit }?,
}

-- What the client needs to (re)build its copy of the run.
export type RunState = {
	runId: number,
	best: number,
	session: any, -- GameSession.Snapshot
}

export type PlaceOutcome =
	{ kind: "accepted", runId: number, moveIndex: number, score: number, set: { string }?, isOver: boolean, best: number }
	| { kind: "resync", state: RunState }
	| { kind: "ignored", reason: string }

type Run = { id: number, session: any }

local DEFAULT_LIMITS = {
	place = { capacity = 8, windowSeconds = 1 }, -- no human places more than 8 pieces a second
	start = { capacity = 1, windowSeconds = 0.5 },
	state = { capacity = 2, windowSeconds = 1 },
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
	},
	GameRuns
))

local function ignored(reason: string): PlaceOutcome
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
	}, GameRuns)
end

local function stateOf(self: GameRuns, key: any, run: Run): RunState
	return { runId = run.id, best = self.bests[key] or 0, session = run.session:snapshot() }
end

-- Starts (or restarts) the player's run. Nil when asked too often.
function GameRuns.start(self: GameRuns, key: any): RunState?
	if not self.startLimiter:allow(key) then
		return nil
	end
	local deps = self.deps
	local source = deps.Generator.newSource(deps.Rng.new(deps.newSeed()))
	local run = { id = self.nextRunId, session = deps.GameSession.new(source) }
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

	local best = math.max(self.bests[key] or 0, session.score)
	self.bests[key] = best
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
		moveIndex = index,
		score = session.score,
		set = set,
		isOver = session.isOver,
		best = best,
	}
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
end

return GameRuns
