--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Generator = require("../src/shared/Generator")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local SETTINGS = Config.GENERATOR
local ALL_PIECES = Pieces.ALL

-- Straightforward exhaustive search on Board cells, used to check the generator's faster solver.
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

local function near(actual: number, expected: number, tolerance: number): boolean
	return math.abs(actual - expected) <= tolerance
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

local function groupFrequencies(score: number, sets: number, seed: number): { [string]: number }
	local rng = Rng.new(seed)
	local board = Board.new()
	local counts = { Small = 0, Medium = 0, Large = 0, Huge = 0 }
	for _ = 1, sets do
		for _, piece in Generator.nextSet(board, score, rng, "Normal") do
			counts[piece.size] += 1
		end
	end
	local total = sets * Config.PIECES_PER_SET
	for group, count in counts do
		counts[group] = count / total
	end
	return counts
end

return function(t: TestKit.TestKit)
	t.describe("Generator", function()
		t.describe("groupShares", function()
			t.it("moves from the easy to the hard shares as the score rises", function()
				local easy = Generator.groupShares(0, 0)
				local hard = Generator.groupShares(SETTINGS.DIFFICULTY_MAX_SCORE * 2, 0)
				local middle = Generator.groupShares(SETTINGS.DIFFICULTY_MAX_SCORE / 2, 0)
				for group, share in SETTINGS.GROUP_SHARES_EASY do
					local hardShare = SETTINGS.GROUP_SHARES_HARD[group]
					t.expect(near(easy[group], share, 1e-9)).toBe(true)
					t.expect(near(hard[group], hardShare, 1e-9)).toBe(true)
					t.expect(near(middle[group], (share + hardShare) / 2, 1e-9)).toBe(true)
				end
			end)

			t.it("doubles small pieces on a crowded board and still sums to 1", function()
				local shares = Generator.groupShares(0, 0.7)
				local easy = SETTINGS.GROUP_SHARES_EASY
				local total = easy.Small * 2 + easy.Medium + easy.Large + easy.Huge
				t.expect(near(shares.Small, easy.Small * 2 / total, 1e-9)).toBe(true)
				t.expect(near(shares.Small + shares.Medium + shares.Large + shares.Huge, 1, 1e-9)).toBe(true)
			end)
		end)

		t.it("picks the fairness tier from the score, and the strictest one for revives", function()
			t.expect(Generator.fairnessTier(0, "Normal")).toBe("WholeSet")
			t.expect(Generator.fairnessTier(1499, "Normal")).toBe("WholeSet")
			t.expect(Generator.fairnessTier(1500, "Normal")).toBe("EachPiece")
			t.expect(Generator.fairnessTier(4999, "Normal")).toBe("EachPiece")
			t.expect(Generator.fairnessTier(5000, "Normal")).toBe("AnyPiece")
			t.expect(Generator.fairnessTier(99999, "Revive")).toBe("WholeSet")
		end)

		t.it("agrees with an exhaustive search on whether a set can be placed", function()
			local rng = Rng.new(2024)
			local solvable, unsolvable = 0, 0
			for _ = 1, 200 do
				local board = Helpers.randomBoard(rng, 0.45 + rng:nextFloat() * 0.3)
				local set = {}
				for i = 1, 3 do
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
			-- Make sure both outcomes were actually exercised.
			t.expect(solvable > 20 and unsolvable > 20).toBe(true)
		end)

		t.it("deals the same sets for the same seed", function()
			local board = Helpers.randomBoard(Rng.new(1), 0.4)
			local a, b = Rng.new(5), Rng.new(5)
			for _ = 1, 50 do
				t.expect(Helpers.ids(Generator.nextSet(board, 2000, a, "Normal")))
					.toEqual(Helpers.ids(Generator.nextSet(board, 2000, b, "Normal")))
			end
		end)

		t.it("meets its fairness tier on 10,000 random boards", function()
			local rng = Rng.new(77)
			for _ = 1, 10000 do
				local board = Helpers.randomBoard(rng, rng:nextFloat() * 0.75)
				local score = rng:nextInt(0, 9999)
				local reason: Generator.DealReason = if rng:nextFloat() < 0.1 then "Revive" else "Normal"
				local set = Generator.nextSet(board, score, rng, reason)

				t.expect(#set).toBe(Config.PIECES_PER_SET)
				t.expect(countHuge(set) <= SETTINGS.MAX_HUGE_PER_SET).toBe(true)
				local tier = Generator.fairnessTier(score, reason)
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

		t.it("still deals a placeable set when only single cells fit", function()
			local board = Helpers.boardFromRows({
				"#.#.#.#.",
				".#.#.#.#",
				"#.#.#.#.",
				".#.#.#.#",
				"#.#.#.#.",
				".#.#.#.#",
				"#.#.#.#.",
				".#.#.#.#",
			})
			local set = Generator.nextSet(board, 0, Rng.new(3), "Normal")
			t.expect(referenceSolvable(board, set)).toBe(true)
		end)

		t.it("matches the configured group shares on an empty board", function()
			for _, case in
				{
					{ score = 0, shares = SETTINGS.GROUP_SHARES_EASY },
					{ score = 9000, shares = SETTINGS.GROUP_SHARES_HARD },
				}
			do
				local frequencies = groupFrequencies(case.score, 20000, 11)
				for group, share in case.shares do
					t.expect(near(frequencies[group], share, 0.03)).toBe(true)
				end
			end
		end)

		t.it("deals a set in under 2 ms on average and 20 ms at worst (fails only at 5x)", function()
			local rng = Rng.new(500)
			local total, worst = 0, 0
			local runs = 2000
			for i = 1, runs do
				local board = Helpers.randomBoard(rng, 0.3 + rng:nextFloat() * 0.4)
				-- Cycle through the three tiers.
				local score = ({ 500, 3000, 7000 })[i % 3 + 1]
				local started = os.clock()
				Generator.nextSet(board, score, rng, "Normal")
				local elapsed = os.clock() - started
				total += elapsed
				worst = math.max(worst, elapsed)
			end
			local average = total / runs
			print(
				string.format(
					"    nextSet: avg %.3f ms, worst %.3f ms over %d boards",
					average * 1000,
					worst * 1000,
					runs
				)
			)
			t.expect(average < 0.010).toBe(true)
			t.expect(worst < 0.100).toBe(true)
		end)
	end)
end
