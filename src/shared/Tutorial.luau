--!strict
-- The first-time tutorial run: a fixed opening where the suggested first move clears a line. Shared so the
-- server deals exactly this and the client points its hint at the same move. After the first set the run
-- goes on like any other.
local Board = require("./Board")
local Pieces = require("./Pieces")

-- "#" is a filled cell. The bottom row has a three-cell gap that the first tray piece fills.
local ROWS = {
	"........",
	"........",
	"........",
	"........",
	"........",
	"........",
	"#.......",
	"###...##",
}
local FILLED_COLOR = 4
local TRAY = { "I3_H", "O2", "L3_1" }

local Tutorial = {}

-- The move the hint shows: tray slot, and the board cell for the piece's top-left corner.
Tutorial.HINT = table.freeze({ slot = 1, x = 3, y = 7 })

function Tutorial.newBoard(): Board.Board
	local board = Board.new()
	for y, row in ROWS do
		for x = 1, #row do
			if string.sub(row, x, x) == "#" then
				board.cells[Board.index(x - 1, y - 1)] = FILLED_COLOR
			end
		end
	end
	return board
end

function Tutorial.tray(): { Pieces.Piece }
	local pieces = {}
	for i, id in TRAY do
		pieces[i] = Pieces.BY_ID[id]
	end
	return pieces
end

return Tutorial
