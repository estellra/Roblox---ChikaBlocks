--!strict
local Board = require("../src/shared/Board")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local TestKit = require("./TestKit")

local P = Pieces.BY_ID

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

return function(t: TestKit.TestKit)
	t.describe("Board", function()
		t.it("starts empty", function()
			local board = Board.new()
			t.expect(#board.cells).toBe(64)
			t.expect(Board.isEmpty(board)).toBe(true)
			t.expect(Board.fillRatio(board)).toBe(0)
		end)

		t.describe("canPlace", function()
			t.it("accepts positions inside the board", function()
				local board = Board.new()
				t.expect(Board.canPlace(board, P.O3, 0, 0)).toBe(true)
				t.expect(Board.canPlace(board, P.O3, 5, 5)).toBe(true)
				t.expect(Board.canPlace(board, P.I5_H, 3, 7)).toBe(true)
			end)

			t.it("rejects positions that stick out of the board", function()
				local board = Board.new()
				t.expect(Board.canPlace(board, P.O3, 6, 0)).toBe(false)
				t.expect(Board.canPlace(board, P.O3, 0, 6)).toBe(false)
				t.expect(Board.canPlace(board, P.Dot, -1, 0)).toBe(false)
				t.expect(Board.canPlace(board, P.Dot, 0, -1)).toBe(false)
				t.expect(Board.canPlace(board, P.I5_V, 0, 4)).toBe(false)
			end)

			t.it("rejects non-integer and NaN positions", function()
				local board = Board.new()
				t.expect(Board.canPlace(board, P.Dot, 0.5, 0)).toBe(false)
				t.expect(Board.canPlace(board, P.Dot, 0, 0 / 0)).toBe(false)
			end)

			t.it("rejects overlaps but allows touching", function()
				local board = Board.new()
				Board.place(board, P.Dot, 1, 1, 2)
				t.expect(Board.canPlace(board, P.O2, 0, 0)).toBe(false)
				t.expect(Board.canPlace(board, P.O2, 2, 1)).toBe(true)
				-- L3_4 is ".#" / "##": its empty top-left corner may sit on a filled cell.
				t.expect(Board.canPlace(board, P.L3_4, 1, 1)).toBe(true)
			end)
		end)

		t.describe("place", function()
			t.it("fills the piece's cells with its color", function()
				local board = Board.new()
				Board.place(board, P.T4_1, 2, 3, 5)
				t.expect(Board.get(board, 2, 3)).toBe(5)
				t.expect(Board.get(board, 3, 3)).toBe(5)
				t.expect(Board.get(board, 4, 3)).toBe(5)
				t.expect(Board.get(board, 3, 4)).toBe(5)
				t.expect(Board.get(board, 2, 4)).toBe(0)
				t.expect(Board.fillRatio(board)).toBe(4 / 64)
			end)

			t.it("throws on an invalid move or color", function()
				local board = Board.new()
				t.expect(function()
					Board.place(board, P.O3, 7, 7, 1)
				end).toThrow()
				t.expect(function()
					Board.place(board, P.Dot, 0, 0, 0)
				end).toThrow()
			end)
		end)

		t.describe("lines", function()
			t.it("finds a full row and a full column", function()
				local board = Helpers.boardFromRows({
					"#.......",
					"#.......",
					"########",
					"#.......",
					"#.......",
					"#.......",
					"#.......",
					"#.......",
				})
				t.expect(Board.findCompleteLines(board)).toEqual({ rows = { 2 }, cols = { 0 } })
			end)

			t.it("counts the crossing cell once when clearing", function()
				local board = Helpers.boardFromRows({
					".....#..",
					".....#..",
					"########",
					".....#..",
					".....#..",
					".....#..",
					".....#..",
					".....#..",
				})
				local cleared = Board.clearLines(board, Board.findCompleteLines(board))
				t.expect(cleared).toBe(15)
				t.expect(Board.isEmpty(board)).toBe(true)
			end)

			t.it("finds nothing on a board without full lines", function()
				t.expect(Board.findCompleteLines(Helpers.boardFromRows(CHECKERBOARD))).toEqual({ rows = {}, cols = {} })
			end)

			t.it("previews lines a move would complete without changing the board", function()
				local board = Helpers.boardFromRows({
					"#######.",
					".......#",
					".......#",
					".......#",
					".......#",
					".......#",
					".......#",
					".......#",
				})
				t.expect(Board.previewLines(board, P.Dot, 7, 0)).toEqual({ rows = { 0 }, cols = { 7 } })
				t.expect(Board.get(board, 7, 0)).toBe(0)
				t.expect(Board.previewLines(board, P.O2, 6, 0)).toEqual({ rows = {}, cols = {} })
			end)
		end)

		t.it("knows whether a piece fits anywhere", function()
			local board = Helpers.boardFromRows(CHECKERBOARD)
			t.expect(Board.fillRatio(board)).toBe(0.5)
			t.expect(Board.hasAnyPlacement(board, P.Dot)).toBe(true)
			t.expect(Board.hasAnyPlacement(board, P.I2_H)).toBe(false)
			t.expect(Board.hasAnyPlacement(board, P.O2)).toBe(false)
		end)

		t.it("clears a rectangle and ignores the part outside the board", function()
			local board = Helpers.boardFromRows({
				"#######.",
				"#######.",
				"#######.",
				"#######.",
				"#######.",
				"#######.",
				"#######.",
				"#######.",
			})
			Board.clearRect(board, 2, 2, 4, 4)
			t.expect(Board.get(board, 2, 2)).toBe(0)
			t.expect(Board.get(board, 5, 5)).toBe(0)
			t.expect(Board.get(board, 1, 2)).toBe(1)
			t.expect(Board.get(board, 6, 5)).toBe(1)
			t.expect(Board.fillRatio(board)).toBe((56 - 16) / 64)
			Board.clearRect(board, 6, -2, 5, 3)
			t.expect(Board.get(board, 6, 0)).toBe(0)
			t.expect(Board.get(board, 6, 1)).toBe(1)
		end)

		t.it("clones without sharing cells", function()
			local board = Board.new()
			local copy = Board.clone(board)
			Board.place(copy, P.Dot, 0, 0, 1)
			t.expect(Board.get(board, 0, 0)).toBe(0)
		end)
	end)
end
