--!strict
-- GameSession and Generator with a set size other than the default three (Co-op deals four).
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local GameSession = require("../src/shared/GameSession")
local Generator = require("../src/shared/Generator")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local ALL_PIECES = Pieces.ALL
local DOT = Pieces.BY_ID.Dot
local MAX_HUGE = Config.GENERATOR.MAX_HUGE_PER_SET

local CHECKERBOARD = {
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
}

local function noSet(_board: Board.Board, _score: number, _reason: Generator.DealReason): { Pieces.Piece }?
	return nil
end

-- Same exhaustive search as Generator.spec uses, to check the generator's faster solver on four pieces.
local function referenceSolvable(board: Board.Board, pieces: { Pieces.Piece }): boolean
	if #pieces == 0 then
		return true
	end
	for i, piece in pieces do
		local rest = table.clone(pieces)
		table.remove(rest, i)
		for y = 0, Config.GRID_SIZE - 1 do
			for x = 0, Config.GRID_SIZE - 1 do
				if Board.canPlace(board, piece, x, y) then
					local nextBoard = Board.clone(board)
					Board.place(nextBoard, piece, x, y, 1)
					Board.clearLines(nextBoard, Board.findCompleteLines(nextBoard))
					if referenceSolvable(nextBoard, rest) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function countHuge(set: { Pieces.Piece }): number
	local count = 0
	for _, piece in set do
		if piece.size == "Huge" then
			count += 1
		end
	end
	return count
end

local function near(actual: number, expected: number): boolean
	return math.abs(actual - expected) <= 1e-9
end

return function(t: TestKit.TestKit)
	t.describe("GameSession with four pieces per set", function()
		t.it("deals four pieces and refills only once all four are placed", function()
			local source, reasons =
				Helpers.queueSource({ { "Dot", "O2", "I3_H", "I2_V" }, { "Dot", "Dot", "Dot", "Dot" } })
			local session = GameSession.new(source, nil, 4)
			t.expect(session.setSize).toBe(4)
			t.expect(Helpers.ids(session.tray)).toEqual({ "Dot", "O2", "I3_H", "I2_V" })

			local moves = { { 1, 0, 0 }, { 2, 2, 0 }, { 3, 0, 4 }, { 4, 7, 0 } }
			for i, move in moves do
				local result = session:place(move[1], move[2], move[3])
				assert(result, "the move is valid")
				t.expect(result.refilled).toBe(i == 4)
			end
			t.expect(Helpers.ids(session.tray)).toEqual({ "Dot", "Dot", "Dot", "Dot" })
			t.expect(reasons).toEqual({ "Normal", "Normal" })
			t.expect(session.moveCount).toBe(4)
		end)

		t.it("keeps three pieces per set unless told otherwise", function()
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot" } })))
			t.expect(session.setSize).toBe(Config.PIECES_PER_SET)
			t.expect(#session.tray).toBe(3)
			t.expect(session:place(4, 0, 0)).toBe(nil)
		end)

		t.it("accepts slot 4 and refuses slot 5", function()
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot", "Dot" } })), nil, 4)
			t.expect(session:canPlace(5, 0, 0)).toBe(false)
			t.expect(session:place(5, 0, 0)).toBe(nil)
			t.expect(session:canPlace(4, 0, 0)).toBe(true)
			t.expect(session:place(4, 0, 0)).toBeTruthy()
			t.expect(session:canPlace(4, 1, 0)).toBe(false) -- slot 4 is spent
		end)

		t.it("refuses a source that deals the wrong number of pieces", function()
			t.expect(function()
				GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot" } })), nil, 4)
			end).toThrow()
			t.expect(function()
				GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot", "Dot" } })))
			end).toThrow()
		end)

		t.it("refuses set sizes that are not positive whole numbers", function()
			for _, size in { 0, -1, 2.5, 0 / 0 } do
				t.expect(function()
					GameSession.new(noSet, nil, size)
				end).toThrow()
			end
		end)

		t.it("waits for a set of four when the source has none yet", function()
			local session = GameSession.new(noSet, nil, 4)
			t.expect(session.awaitingSet).toBe(true)
			t.expect(#session.tray).toBe(4)
			t.expect(session:receiveSet({ DOT, DOT, DOT })).toBe(false)
			t.expect(session.awaitingSet).toBe(true)
			t.expect(session:receiveSet({ DOT, DOT, DOT, DOT })).toBe(true)
			t.expect(session.awaitingSet).toBe(false)
			t.expect(Helpers.ids(session.tray)).toEqual({ "Dot", "Dot", "Dot", "Dot" })
		end)

		t.it("is over only when none of the four pieces fits", function()
			local source = Helpers.queueSource({ { "O2", "O2", "O2", "Dot" } })
			local session = GameSession.new(source, Helpers.boardFromRows(CHECKERBOARD), 4)
			t.expect(session.isOver).toBe(false)
			t.expect(session:hasPlacement(1)).toBe(false)
			t.expect(session:hasPlacement(4)).toBe(true)

			local result = session:place(4, 1, 0)
			assert(result, "the dot fits")
			t.expect(result.isOver).toBe(true)
			t.expect(session.isOver).toBe(true)
			t.expect(session:hasPlacement(4)).toBe(false)
		end)

		t.it("starts over at once when none of a fresh set of four fits", function()
			local source = Helpers.queueSource({ { "O2", "O2", "O2", "O2" } })
			local session = GameSession.new(source, Helpers.boardFromRows(CHECKERBOARD), 4)
			t.expect(session.isOver).toBe(true)
		end)

		t.it("round-trips a four-piece snapshot and keeps playing identically", function()
			local sets = { { "Dot", "O2", "I3_H", "I2_V" }, { "T4_1", "L3_1", "I2_V", "Dot" } }
			local session = GameSession.new((Helpers.queueSource(sets)), Helpers.boardFromRows({ "######.." }), 4)
			session:place(1, 6, 0)
			session:place(3, 3, 3)
			local snapshot = session:snapshot()
			t.expect(#snapshot.tray).toBe(4)

			local copy = GameSession.fromSnapshot(snapshot, (Helpers.queueSource({ sets[2] })))
			t.expect(copy.setSize).toBe(4)
			t.expect(copy:snapshot()).toEqual(snapshot)

			for _, move in { { 2, 0, 6 }, { 4, 6, 6 } } do
				local expected = session:place(move[1], move[2], move[3])
				local actual = copy:place(move[1], move[2], move[3])
				assert(expected and actual, "both sessions accept the move")
				t.expect(actual.points).toBe(expected.points)
				t.expect(actual.refilled).toBe(expected.refilled)
			end
			t.expect(copy:snapshot()).toEqual(session:snapshot())
			t.expect(Helpers.ids(copy.tray)).toEqual({ "T4_1", "L3_1", "I2_V", "Dot" })
		end)

		t.it("refuses a snapshot without a tray", function()
			local snapshot = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot", "Dot" } })), nil, 4)
				:snapshot()
			local noTray = table.clone(snapshot)
			noTray.tray = {}
			t.expect(function()
				GameSession.fromSnapshot(noTray, noSet)
			end).toThrow()
		end)
	end)

	t.describe("Generator with four pieces per set", function()
		t.it("deals the requested number of pieces and meets the fairness tier on 4,000 random boards", function()
			local rng = Rng.new(404)
			for i = 1, 4000 do
				local board = Helpers.randomBoard(rng, rng:nextFloat() * 0.75)
				local score = rng:nextInt(0, 9999)
				local reason: Generator.DealReason = if rng:nextFloat() < 0.1 then "Revive" else "Normal"
				-- Co-op deals with its own tuning; the default tuning has to hold up on four pieces too.
				local overrides = if i % 2 == 0 then Config.COOP.GENERATOR else nil
				local set = Generator.nextSet(board, score, rng, reason, 4, overrides)

				t.expect(#set).toBe(4)
				t.expect(countHuge(set) <= MAX_HUGE).toBe(true)
				local tier = Generator.fairnessTier(score, reason, overrides)
				if tier == "WholeSet" then
					t.expect(Generator.isSetSolvable(board, set, math.huge)).toBe(true)
				elseif tier == "EachPiece" then
					for _, piece in set do
						t.expect(Board.hasAnyPlacement(board, piece)).toBe(true)
					end
				else
					local anyFits = false
					for _, piece in set do
						anyFits = anyFits or Board.hasAnyPlacement(board, piece)
					end
					t.expect(anyFits).toBe(true)
				end
			end
		end)

		t.it("agrees with an exhaustive search on whether four pieces can be placed", function()
			local rng = Rng.new(4242)
			local solvable, unsolvable = 0, 0
			for _ = 1, 80 do
				local board = Helpers.randomBoard(rng, 0.5 + rng:nextFloat() * 0.3)
				local set = {}
				for i = 1, 4 do
					set[i] = ALL_PIECES[rng:nextInt(1, #ALL_PIECES)]
				end
				local expected = referenceSolvable(board, set)
				t.expect(Generator.isSetSolvable(board, set, math.huge)).toBe(expected)
				if expected then
					solvable += 1
				else
					unsolvable += 1
				end
			end
			t.expect(solvable > 10 and unsolvable > 10).toBe(true)
		end)

		t.it("deals three pieces by default, drawing exactly as it did before set sizes existed", function()
			local board = Helpers.randomBoard(Rng.new(1), 0.4)
			local a, b = Rng.new(5), Rng.new(5)
			for _ = 1, 50 do
				local set = Generator.nextSet(board, 2000, a, "Normal")
				t.expect(#set).toBe(3)
				t.expect(Helpers.ids(set)).toEqual(Helpers.ids(Generator.nextSet(board, 2000, b, "Normal", 3)))
			end
		end)

		t.it("builds a source that deals sets of the requested size", function()
			local board = Board.new()
			local three = Generator.newSource(Rng.new(1))
			local four = Generator.newSource(Rng.new(1), 4)
			for _ = 1, 20 do
				local small, big = three(board, 0, "Normal"), four(board, 0, "Normal")
				assert(small and big, "the source deals right away")
				t.expect(#small).toBe(3)
				t.expect(#big).toBe(4)
			end
		end)

		t.it("lets overrides move the thresholds, the shares and the node budget", function()
			t.expect(Generator.fairnessTier(2000, "Normal")).toBe("EachPiece")
			t.expect(Generator.fairnessTier(2000, "Normal", { WHOLE_SET_BELOW_SCORE = 3000 })).toBe("WholeSet")
			t.expect(Generator.fairnessTier(2000, "Normal", { EACH_PIECE_BELOW_SCORE = 1800 })).toBe("AnyPiece")
			t.expect(Generator.fairnessTier(99999, "Revive", { WHOLE_SET_BELOW_SCORE = 0 })).toBe("WholeSet")

			local hard = Generator.groupShares(Config.GENERATOR.DIFFICULTY_MAX_SCORE * 2, 0)
			local sooner = Generator.groupShares(4000, 0, { DIFFICULTY_MAX_SCORE = 4000 })
			for group, share in hard do
				t.expect(near(sooner[group], share)).toBe(true)
			end

			-- A budget of nothing can never prove a set placeable, so a whole-set deal falls back to dots.
			local set = Generator.nextSet(Board.new(), 0, Rng.new(1), "Normal", 4, { SOLVER_NODE_BUDGET = 0 })
			t.expect(Helpers.ids(set)).toEqual({ "Dot", "Dot", "Dot", "Dot" })
			local allDots = true
			for _, piece in Generator.nextSet(Board.new(), 0, Rng.new(1), "Normal", 4) do
				allDots = allDots and piece == DOT
			end
			t.expect(allDots).toBe(false)
		end)

		t.it("deals a Co-op set in under 1 ms on average and 10 ms at worst (fails only at 5x)", function()
			local rng = Rng.new(500)
			local total, worst = 0, 0
			local runs = 2000
			for i = 1, runs do
				local board = Helpers.randomBoard(rng, 0.3 + rng:nextFloat() * 0.4)
				-- Half the deals are whole-set ones, the slow kind.
				local score = ({ 500, 1200, 3000, 7000 })[i % 4 + 1]
				local started = os.clock()
				Generator.nextSet(board, score, rng, "Normal", Config.COOP.SET_SIZE, Config.COOP.GENERATOR)
				local elapsed = os.clock() - started
				total += elapsed
				worst = math.max(worst, elapsed)
			end
			local average = total / runs
			print(
				string.format(
					"    Co-op nextSet: avg %.3f ms, worst %.3f ms over %d boards",
					average * 1000,
					worst * 1000,
					runs
				)
			)
			t.expect(average < 0.005).toBe(true)
			t.expect(worst < 0.050).toBe(true)
		end)
	end)
end
