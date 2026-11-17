--!strict
-- Grid logic. Cells are a flat array indexed by y * size + x + 1; 0 means empty, anything else is a color.
-- x is the column (0 = left), y is the row (0 = top).

local Config = require("./Config")
local Pieces = require("./Pieces")

type Piece = Pieces.Piece

export type Board = { cells: { number } }
export type Lines = { rows: { number }, cols: { number } }
-- The edge a garbage line is pushed in from (PVP).
export type PushSide = "bottom" | "left" | "right"

local SIZE = Config.GRID_SIZE
local CELL_COUNT = SIZE * SIZE

local Board = {}

function Board.new(): Board
	return { cells = table.create(CELL_COUNT, 0) }
end

function Board.clone(board: Board): Board
	return { cells = table.clone(board.cells) }
end

function Board.index(x: number, y: number): number
	return y * SIZE + x + 1
end

function Board.get(board: Board, x: number, y: number): number
	return board.cells[y * SIZE + x + 1]
end

-- Rejects out-of-bounds, overlapping and non-integer positions (the server will reuse this to validate moves).
function Board.canPlace(board: Board, piece: Piece, x: number, y: number): boolean
	if x ~= math.floor(x) or y ~= math.floor(y) then
		return false
	end
	if x < 0 or y < 0 or x + piece.width > SIZE or y + piece.height > SIZE then
		return false
	end
	local cells = board.cells
	for _, cell in piece.cells do
		if cells[(y + cell.y) * SIZE + x + cell.x + 1] ~= 0 then
			return false
		end
	end
	return true
end

function Board.place(board: Board, piece: Piece, x: number, y: number, color: number)
	if color < 1 then
		error(`color must be at least 1, got {color}`, 2)
	end
	if not Board.canPlace(board, piece, x, y) then
		error(`cannot place {piece.id} at ({x}, {y})`, 2)
	end
	local cells = board.cells
	for _, cell in piece.cells do
		cells[(y + cell.y) * SIZE + x + cell.x + 1] = color
	end
end

function Board.findCompleteLines(board: Board): Lines
	local cells = board.cells
	local rows, cols = {}, {}
	for y = 0, SIZE - 1 do
		local full = true
		for x = 0, SIZE - 1 do
			if cells[y * SIZE + x + 1] == 0 then
				full = false
				break
			end
		end
		if full then
			table.insert(rows, y)
		end
	end
	for x = 0, SIZE - 1 do
		local full = true
		for y = 0, SIZE - 1 do
			if cells[y * SIZE + x + 1] == 0 then
				full = false
				break
			end
		end
		if full then
			table.insert(cols, x)
		end
	end
	return { rows = rows, cols = cols }
end

-- Rows and columns clear together; a cell where a row meets a column counts once. Returns cells cleared.
function Board.clearLines(board: Board, lines: Lines): number
	local cells = board.cells
	local cleared = 0
	local function clearAt(index: number)
		if cells[index] ~= 0 then
			cells[index] = 0
			cleared += 1
		end
	end
	for _, y in lines.rows do
		for x = 0, SIZE - 1 do
			clearAt(y * SIZE + x + 1)
		end
	end
	for _, x in lines.cols do
		for y = 0, SIZE - 1 do
			clearAt(y * SIZE + x + 1)
		end
	end
	return cleared
end

-- Empties a rectangle; the parts outside the board are ignored.
function Board.clearRect(board: Board, x: number, y: number, width: number, height: number)
	local cells = board.cells
	for row = math.max(y, 0), math.min(y + height, SIZE) - 1 do
		for col = math.max(x, 0), math.min(x + width, SIZE) - 1 do
			cells[row * SIZE + col + 1] = 0
		end
	end
end

-- Pushes a garbage line in from one edge (PVP). The whole board moves one cell away from that edge, the row or
-- column pushed off the opposite edge is lost, and the new edge line gets `color` in every cell except `hole`
-- (0 to GRID_SIZE - 1, counted left to right for "bottom", top to bottom for "left" and "right"). Returns the lines
-- that are full afterwards; clearing them is up to the caller. Only the server and its client-side copy call this,
-- never with values straight from a remote, so bad arguments are errors.
function Board.pushLine(board: Board, side: PushSide, hole: number, color: number): Lines
	if side ~= "bottom" and side ~= "left" and side ~= "right" then
		error(`unknown side {side}`, 2)
	end
	if typeof(hole) ~= "number" or hole ~= math.floor(hole) or hole < 0 or hole >= SIZE then
		error(`hole must be an integer from 0 to {SIZE - 1}, got {hole}`, 2)
	end
	if typeof(color) ~= "number" or color ~= math.floor(color) or color < 1 then
		error(`color must be a positive integer, got {color}`, 2)
	end
	local cells = board.cells
	if side == "bottom" then
		for y = 0, SIZE - 2 do
			for x = 0, SIZE - 1 do
				cells[y * SIZE + x + 1] = cells[(y + 1) * SIZE + x + 1]
			end
		end
		for x = 0, SIZE - 1 do
			cells[(SIZE - 1) * SIZE + x + 1] = if x == hole then 0 else color
		end
	elseif side == "left" then
		for y = 0, SIZE - 1 do
			for x = SIZE - 1, 1, -1 do
				cells[y * SIZE + x + 1] = cells[y * SIZE + x]
			end
			cells[y * SIZE + 1] = if y == hole then 0 else color
		end
	else
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 2 do
				cells[y * SIZE + x + 1] = cells[y * SIZE + x + 2]
			end
			cells[y * SIZE + SIZE] = if y == hole then 0 else color
		end
	end
	return Board.findCompleteLines(board)
end

-- Lines that placing the piece would complete, without changing the board. Empty if the move is invalid.
function Board.previewLines(board: Board, piece: Piece, x: number, y: number): Lines
	if not Board.canPlace(board, piece, x, y) then
		return { rows = {}, cols = {} }
	end
	local preview = Board.clone(board)
	Board.place(preview, piece, x, y, 1)
	return Board.findCompleteLines(preview)
end

function Board.hasAnyPlacement(board: Board, piece: Piece): boolean
	for y = 0, SIZE - piece.height do
		for x = 0, SIZE - piece.width do
			if Board.canPlace(board, piece, x, y) then
				return true
			end
		end
	end
	return false
end

function Board.fillRatio(board: Board): number
	local filled = 0
	for _, value in board.cells do
		if value ~= 0 then
			filled += 1
		end
	end
	return filled / CELL_COUNT
end

function Board.isEmpty(board: Board): boolean
	for _, value in board.cells do
		if value ~= 0 then
			return false
		end
	end
	return true
end

return Board
