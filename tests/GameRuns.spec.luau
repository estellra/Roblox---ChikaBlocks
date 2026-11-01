--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local GameRuns = require("../src/server/GameRuns")
local GameSession = require("../src/shared/GameSession")
local Generator = require("../src/shared/Generator")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")
local Tutorial = require("../src/shared/Tutorial")

local SIZE = Config.GRID_SIZE
local PLAYER = "player-1" -- GameRuns works with any key; in the game it's the Player

local function noSet(_board: Board.Board, _score: number, _reason: Generator.DealReason): { Pieces.Piece }?
	return nil
end

-- Runs with a controllable clock. `generator` defaults to the real one.
local function newRuns(generator: any?): (GameRuns.GameRuns, (seconds: number) -> ())
	local now = 0
	local seed = 0
	local runs = GameRuns.new({
		GameSession = GameSession,
		Generator = generator or Generator,
		Rng = Rng,
		Tutorial = Tutorial,
		clock = function(): number
			return now
		end,
		newSeed = function(): number
			seed += 1
			return seed
		end,
	})
	return runs, function(seconds: number)
		now += seconds
	end
end

-- A generator that always deals three 3x3 squares, so a run ends after four moves.
local SQUARES = {
	newSource = function(_rng: any)
		return function(): { Pieces.Piece }?
			local O3 = Pieces.BY_ID.O3
			return { O3, O3, O3 }
		end
	end,
}

-- The first valid move for the server's current state.
local function anyMove(state: GameRuns.RunState): (number, number, number)
	local session = GameSession.fromSnapshot(state.session, noSet)
	for slot, piece in session.tray do
		if piece then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if session:canPlace(slot, x, y) then
						return slot, x, y
					end
				end
			end
		end
	end
	error("no valid move")
end

return function(t: TestKit.TestKit)
	t.describe("GameRuns", function()
		t.it("starts a run with an empty board and three pieces", function()
			local runs = newRuns()
			local state = runs:start(PLAYER)
			assert(state)
			t.expect(state.runId).toBe(1)
			t.expect(state.best).toBe(0)
			t.expect(state.session.score).toBe(0)
			t.expect(#state.session.tray).toBe(3)
			t.expect(state.session.awaitingSet).toBe(false)
		end)

		t.it("accepts a valid move and reports the new score", function()
			local runs = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local slot, x, y = anyMove(state)
			local outcome = runs:place(PLAYER, state.runId, 0, slot, x, y)
			t.expect(outcome.kind).toBe("accepted")
			if outcome.kind == "accepted" then
				t.expect(outcome.moveIndex).toBe(0)
				t.expect(outcome.score > 0).toBe(true)
				t.expect(outcome.set).toBe(nil)
			end
		end)

		t.it("sends the next set with the move that empties the tray", function()
			local runs, advance = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local last
			for move = 0, 2 do
				local current = runs:peek(PLAYER) :: GameRuns.RunState
				local slot, x, y = anyMove(current)
				last = runs:place(PLAYER, state.runId, move, slot, x, y)
				advance(0.2)
			end
			t.expect(last.kind).toBe("accepted")
			if last.kind == "accepted" then
				t.expect(last.set).toEqual((runs:peek(PLAYER) :: GameRuns.RunState).session.tray)
			end
		end)

		t.it("ignores malformed run ids and move indexes", function()
			local runs, advance = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local slot, x, y = anyMove(state)
			local badRunIds: { any } = { "1", 1.5, 0 / 0, math.huge, {}, false, 2 }
			for _, runId in badRunIds do
				t.expect(runs:place(PLAYER, runId, 0, slot, x, y).kind).toBe("ignored")
				advance(0.2)
			end
			t.expect(runs:place(PLAYER, nil, 0, slot, x, y).kind).toBe("ignored")
			advance(0.2)
			local badIndexes: { any } = { "0", -1, 0.5, 0 / 0, 1e9 }
			for _, index in badIndexes do
				t.expect(runs:place(PLAYER, state.runId, index, slot, x, y).kind).toBe("ignored")
				advance(0.2)
			end
			t.expect((runs:peek(PLAYER) :: GameRuns.RunState).session.moveCount).toBe(0)
		end)

		t.it("answers an invalid placement with the full state and changes nothing", function()
			local runs, advance = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local garbage: { { any } } = { { "1", 0, 0 }, { 1, 0 / 0, 0 }, { 1, -1, 0 }, { 4, 0, 0 }, { 1, 99, 99 } }
			for _, args in garbage do
				local outcome = runs:place(PLAYER, state.runId, 0, args[1], args[2], args[3])
				t.expect(outcome.kind).toBe("resync")
				advance(0.2)
			end
			t.expect((runs:peek(PLAYER) :: GameRuns.RunState).session).toEqual(state.session)
		end)

		t.it("drops stale moves and resyncs a client that got ahead", function()
			local runs, advance = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local slot, x, y = anyMove(state)
			t.expect(runs:place(PLAYER, state.runId, 0, slot, x, y).kind).toBe("accepted")
			advance(0.2)
			t.expect(runs:place(PLAYER, state.runId, 0, slot, x, y).kind).toBe("ignored") -- already applied
			advance(0.2)
			t.expect(runs:place(PLAYER, state.runId, 5, slot, x, y).kind).toBe("resync") -- ahead of the server
		end)

		t.it("ignores moves for an older run after a restart", function()
			local runs, advance = newRuns()
			local first = runs:start(PLAYER) :: GameRuns.RunState
			advance(1)
			local second = runs:start(PLAYER) :: GameRuns.RunState
			t.expect(second.runId).toBe(first.runId + 1)
			local slot, x, y = anyMove(second)
			t.expect(runs:place(PLAYER, first.runId, 0, slot, x, y).kind).toBe("ignored")
		end)

		t.it("rate limits a flood of moves and recovers after a second", function()
			local runs, advance = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local limited = 0
			for _ = 1, 20 do
				local outcome = runs:place(PLAYER, state.runId, 99, 1, 0, 0) -- would be a resync if processed
				if outcome.kind == "ignored" and outcome.reason == "rate limited" then
					limited += 1
				end
			end
			t.expect(limited).toBe(12) -- 8 in the burst got through
			advance(1)
			local slot, x, y = anyMove(state)
			t.expect(runs:place(PLAYER, state.runId, 0, slot, x, y).kind).toBe("accepted")
		end)

		t.it("rate limits restarts and state requests", function()
			local runs, advance = newRuns()
			t.expect(runs:start(PLAYER)).toBeTruthy()
			t.expect(runs:start(PLAYER)).toBe(nil)
			advance(0.5)
			t.expect(runs:start(PLAYER)).toBeTruthy()
			t.expect(runs:state(PLAYER)).toBeTruthy()
			t.expect(runs:state(PLAYER)).toBeTruthy()
			t.expect(runs:state(PLAYER)).toBe(nil)
		end)

		t.it("ends a run, rejects moves after it and keeps the best across runs", function()
			local runs, advance = newRuns(SQUARES)
			local state = runs:start(PLAYER) :: GameRuns.RunState
			local positions = { { 0, 0 }, { 3, 0 }, { 0, 3 }, { 3, 3 } }
			local last
			for move, position in positions do
				local slot = ((move - 1) % 3) + 1
				last = runs:place(PLAYER, state.runId, move - 1, slot, position[1], position[2])
				advance(0.2)
			end
			t.expect(last.kind).toBe("accepted")
			if last.kind == "accepted" then
				t.expect(last.isOver).toBe(true)
				t.expect(last.best).toBe(36)
			end
			t.expect(runs:place(PLAYER, state.runId, 4, 2, 5, 5).kind).toBe("resync")

			advance(1)
			local nextRun = runs:start(PLAYER) :: GameRuns.RunState
			t.expect(nextRun.best).toBe(36)
			t.expect(nextRun.session.score).toBe(0)
		end)

		t.it("starts a tutorial run on the fixed opening and lets the hinted move clear a line", function()
			local runs = newRuns()
			local state = runs:start(PLAYER, "tutorial") :: GameRuns.RunState
			t.expect(state.mode).toBe("tutorial")
			t.expect(state.session.cells).toEqual(Tutorial.newBoard().cells)
			t.expect(state.session.tray).toEqual({ "I3_H", "O2", "L3_1" })

			local hint = Tutorial.HINT
			local outcome = runs:place(PLAYER, state.runId, 0, hint.slot, hint.x, hint.y)
			t.expect(outcome.kind).toBe("accepted")
			if outcome.kind == "accepted" then
				t.expect(outcome.mode).toBe("tutorial")
				t.expect(outcome.score).toBe(3 + 10) -- three cells placed, one line cleared
				t.expect(outcome.linesCleared).toBe(1)
			end
			t.expect(runs:summary(PLAYER))
				.toEqual({ mode = "tutorial", score = 13, moves = 1, maxCombo = 1, isOver = false })
		end)

		t.it("sums up a run for analytics and has nothing for a player without one", function()
			local runs, advance = newRuns(SQUARES)
			t.expect(runs:summary(PLAYER)).toBe(nil)
			local state = runs:start(PLAYER) :: GameRuns.RunState
			t.expect(runs:summary(PLAYER))
				.toEqual({ mode = "normal", score = 0, moves = 0, maxCombo = 0, isOver = false })
			local positions = { { 0, 0 }, { 3, 0 }, { 0, 3 }, { 3, 3 } }
			for move, position in positions do
				local outcome =
					runs:place(PLAYER, state.runId, move - 1, ((move - 1) % 3) + 1, position[1], position[2])
				if outcome.kind == "accepted" then
					t.expect(outcome.linesCleared).toBe(0)
				end
				advance(0.2)
			end
			t.expect(runs:summary(PLAYER))
				.toEqual({ mode = "normal", score = 36, moves = 4, maxCombo = 0, isOver = true })
			runs:remove(PLAYER)
			t.expect(runs:summary(PLAYER)).toBe(nil)
		end)

		t.it("starts normal runs by default and refuses unknown modes", function()
			local runs, advance = newRuns()
			t.expect((runs:start(PLAYER) :: GameRuns.RunState).mode).toBe("normal")
			advance(1)
			local badModes: { any } = { "hard", 1, {}, true }
			for _, mode in badModes do
				t.expect(runs:start(PLAYER, mode)).toBe(nil)
			end
			t.expect((runs:start(PLAYER, "normal") :: GameRuns.RunState).mode).toBe("normal")
		end)

		t.it("forgets a player who leaves", function()
			local runs = newRuns()
			local state = runs:start(PLAYER) :: GameRuns.RunState
			runs:remove(PLAYER)
			t.expect(runs:peek(PLAYER)).toBe(nil)
			t.expect(runs:getBest(PLAYER)).toBe(0)
			local slot, x, y = anyMove(state)
			t.expect(runs:place(PLAYER, state.runId, 0, slot, x, y).kind).toBe("ignored")
		end)
	end)
end
