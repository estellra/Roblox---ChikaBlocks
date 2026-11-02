--!strict
-- Every piece the generator can deal. Each orientation is its own entry; rotateCW() maps one to the next.

export type Cell = { x: number, y: number }
export type SizeGroup = "Small" | "Medium" | "Large" | "Huge"
export type Piece = {
	id: string,
	cells: { Cell }, -- offsets from the top-left corner of the piece's bounding box
	width: number,
	height: number,
	size: SizeGroup,
	color: number, -- fixed per shape family, 1..Config.COLOR_COUNT
}

local COLORS = {
	Dot = 1,
	Bar = 2,
	Corner = 3,
	Block = 4,
	L = 5,
	T = 6,
	Zigzag = 7,
	BigCorner = 8,
}

-- "#" is a filled cell, "." is empty. Rows go top to bottom.
local SHAPES: { { id: string, color: number, rows: { string } } } = {
	-- Small (1-3 cells)
	{ id = "Dot", color = COLORS.Dot, rows = { "#" } },
	{ id = "I2_H", color = COLORS.Bar, rows = { "##" } },
	{ id = "I2_V", color = COLORS.Bar, rows = { "#", "#" } },
	{ id = "I3_H", color = COLORS.Bar, rows = { "###" } },
	{ id = "I3_V", color = COLORS.Bar, rows = { "#", "#", "#" } },
	{ id = "L3_1", color = COLORS.Corner, rows = { "##", "#." } },
	{ id = "L3_2", color = COLORS.Corner, rows = { "##", ".#" } },
	{ id = "L3_3", color = COLORS.Corner, rows = { "#.", "##" } },
	{ id = "L3_4", color = COLORS.Corner, rows = { ".#", "##" } },

	-- Medium (4 cells)
	{ id = "I4_H", color = COLORS.Bar, rows = { "####" } },
	{ id = "I4_V", color = COLORS.Bar, rows = { "#", "#", "#", "#" } },
	{ id = "O2", color = COLORS.Block, rows = { "##", "##" } },
	{ id = "L4_1", color = COLORS.L, rows = { "#.", "#.", "##" } },
	{ id = "L4_2", color = COLORS.L, rows = { "###", "#.." } },
	{ id = "L4_3", color = COLORS.L, rows = { "##", ".#", ".#" } },
	{ id = "L4_4", color = COLORS.L, rows = { "..#", "###" } },
	{ id = "J4_1", color = COLORS.L, rows = { ".#", ".#", "##" } },
	{ id = "J4_2", color = COLORS.L, rows = { "#..", "###" } },
	{ id = "J4_3", color = COLORS.L, rows = { "##", "#.", "#." } },
	{ id = "J4_4", color = COLORS.L, rows = { "###", "..#" } },
	{ id = "T4_1", color = COLORS.T, rows = { "###", ".#." } },
	{ id = "T4_2", color = COLORS.T, rows = { ".#.", "###" } },
	{ id = "T4_3", color = COLORS.T, rows = { "#.", "##", "#." } },
	{ id = "T4_4", color = COLORS.T, rows = { ".#", "##", ".#" } },
	{ id = "S_H", color = COLORS.Zigzag, rows = { ".##", "##." } },
	{ id = "S_V", color = COLORS.Zigzag, rows = { "#.", "##", ".#" } },
	{ id = "Z_H", color = COLORS.Zigzag, rows = { "##.", ".##" } },
	{ id = "Z_V", color = COLORS.Zigzag, rows = { ".#", "##", "#." } },

	-- Large (5-6 cells)
	{ id = "I5_H", color = COLORS.Bar, rows = { "#####" } },
	{ id = "I5_V", color = COLORS.Bar, rows = { "#", "#", "#", "#", "#" } },
	{ id = "R2x3", color = COLORS.Block, rows = { "##", "##", "##" } },
	{ id = "R3x2", color = COLORS.Block, rows = { "###", "###" } },
	{ id = "L5_1", color = COLORS.BigCorner, rows = { "#..", "#..", "###" } },
	{ id = "L5_2", color = COLORS.BigCorner, rows = { "###", "#..", "#.." } },
	{ id = "L5_3", color = COLORS.BigCorner, rows = { "###", "..#", "..#" } },
	{ id = "L5_4", color = COLORS.BigCorner, rows = { "..#", "..#", "###" } },

	-- Huge (9 cells)
	{ id = "O3", color = COLORS.Block, rows = { "###", "###", "###" } },
}

local function sizeGroupFor(cellCount: number): SizeGroup
	if cellCount <= 3 then
		return "Small"
	elseif cellCount == 4 then
		return "Medium"
	elseif cellCount <= 6 then
		return "Large"
	end
	return "Huge"
end

local function parse(id: string, color: number, rows: { string }): Piece
	local cells: { Cell } = {}
	local width = 0
	for y, row in rows do
		for x = 1, #row do
			if string.sub(row, x, x) == "#" then
				table.insert(cells, table.freeze({ x = x - 1, y = y - 1 }))
				width = math.max(width, x)
			end
		end
	end
	return table.freeze({
		id = id,
		cells = table.freeze(cells),
		width = width,
		height = #rows,
		size = sizeGroupFor(#cells),
		color = color,
	})
end

local all: { Piece } = {}
local byId: { [string]: Piece } = {}
for _, shape in SHAPES do
	local piece = parse(shape.id, shape.color, shape.rows)
	table.insert(all, piece)
	byId[piece.id] = piece
end

-- The cells of a piece in reading order as text, to tell whether two entries have the same shape.
local function shapeKey(cells: { Cell }): string
	local sorted = table.clone(cells)
	table.sort(sorted, function(a: Cell, b: Cell): boolean
		return if a.y ~= b.y then a.y < b.y else a.x < b.x
	end)
	local parts = table.create(#sorted)
	for i, cell in sorted do
		parts[i] = `{cell.x},{cell.y}`
	end
	return table.concat(parts, ";")
end

local byShape: { [string]: Piece } = {}
for _, piece in all do
	byShape[shapeKey(piece.cells)] = piece
end

-- The piece one quarter turn clockwise from each piece that looks different when turned; the dot and the
-- squares are left out (they look the same in every orientation).
local rotated: { [string]: Piece } = {}
for _, piece in all do
	local turned: { Cell } = {}
	for i, cell in piece.cells do
		turned[i] = { x = piece.height - 1 - cell.y, y = cell.x }
	end
	local match = byShape[shapeKey(turned)]
	if not match then
		error(`no piece looks like {piece.id} turned a quarter`)
	end
	if match ~= piece then
		rotated[piece.id] = match
	end
end

local Pieces = {
	ALL = table.freeze(all),
	BY_ID = table.freeze(byId),
}

-- Whether turning the piece changes how it looks.
function Pieces.canRotate(piece: Piece): boolean
	return rotated[piece.id] ~= nil
end

-- The piece a quarter turn clockwise from `piece`; the piece itself when turning changes nothing.
function Pieces.rotateCW(piece: Piece): Piece
	return rotated[piece.id] or piece
end

return table.freeze(Pieces)
