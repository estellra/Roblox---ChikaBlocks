--!strict
-- Shared fixtures for specs.
local Board = require("../src/shared/Board")
local Generator = require("../src/shared/Generator")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")

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

-- Random board that keeps the in-game invariant: no full row or column is left on it.
function Helpers.randomBoard(rng: Rng.Rng, density: number): Board.Board
	local board = Board.new()
	for i = 1, #board.cells do
		if rng:nextFloat() < density then
			board.cells[i] = 1
		end
	end
	Board.clearLines(board, Board.findCompleteLines(board))
	return board
end

-- A SetSource that deals the given sets (piece ids) in order. Also returns the list of reasons it was called with.
function Helpers.queueSource(sets: { { string } }): (Generator.SetSource, { Generator.DealReason })
	local reasons: { Generator.DealReason } = {}
	local function source(_board: Board.Board, _score: number, reason: Generator.DealReason): { Pieces.Piece }
		local ids = sets[#reasons + 1]
		if not ids then
			error(`queueSource ran out of sets after {#reasons}`)
		end
		table.insert(reasons, reason)
		local set = {}
		for i, id in ids do
			set[i] = Pieces.BY_ID[id]
		end
		return set
	end
	return source, reasons
end

-- Ids of a set, for readable comparisons.
function Helpers.ids(pieces: { Pieces.Piece | false }): { string | false }
	local ids: { string | false } = {}
	for i, piece in pieces do
		ids[i] = if piece then piece.id else false
	end
	return ids
end

return Helpers
