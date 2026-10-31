--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Pieces = require("../src/shared/Pieces")
local TestKit = require("./TestKit")
local Tutorial = require("../src/shared/Tutorial")

return function(t: TestKit.TestKit)
	t.describe("Tutorial", function()
		t.it("opens with a board that has no full lines yet", function()
			local board = Tutorial.newBoard()
			t.expect(#board.cells).toBe(Config.GRID_SIZE * Config.GRID_SIZE)
			t.expect(Board.isEmpty(board)).toBe(false)
			t.expect(Board.findCompleteLines(board)).toEqual({ rows = {}, cols = {} })
		end)

		t.it("deals a full tray of real pieces", function()
			local tray = Tutorial.tray()
			t.expect(#tray).toBe(Config.PIECES_PER_SET)
			for _, piece in tray do
				t.expect(Pieces.BY_ID[piece.id]).toBe(piece)
			end
		end)

		t.it("suggests a first move that clears a line without emptying the board", function()
			local board = Tutorial.newBoard()
			local hint = Tutorial.HINT
			local piece = Tutorial.tray()[hint.slot]
			t.expect(Board.canPlace(board, piece, hint.x, hint.y)).toBe(true)
			local lines = Board.previewLines(board, piece, hint.x, hint.y)
			t.expect(#lines.rows + #lines.cols >= 1).toBe(true)

			Board.place(board, piece, hint.x, hint.y, 1)
			Board.clearLines(board, Board.findCompleteLines(board))
			t.expect(Board.isEmpty(board)).toBe(false) -- a clear, but not the board-clear bonus
		end)

		t.it("returns a fresh board every time", function()
			local filled = Board.index(0, 6)
			local first = Tutorial.newBoard()
			t.expect(first.cells[filled] ~= 0).toBe(true)
			first.cells[filled] = 0
			t.expect(Tutorial.newBoard().cells[filled] ~= 0).toBe(true)
		end)
	end)
end
