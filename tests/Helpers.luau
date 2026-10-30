--!strict
-- Shared fixtures for specs.
local Board = require("../src/shared/Board")

local Helpers = {}

-- Builds a board from rows of "#" (filled, color 1) and "." (empty), top row first.
function Helpers.boardFromRows(rows: { string }): Board.Board
	local board = Board.new()
	for y, row in rows do
		for x = 1, #row do
			if string.sub(row, x, x) == "#" then
				board.cells[Board.index(x - 1, y - 1)] = 1
			end
		end
	end
	return board
end

return Helpers
