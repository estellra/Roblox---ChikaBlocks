--!strict
-- Every piece the generator can deal. Pieces can't be rotated, so each orientation is its own entry.

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

return table.freeze({
	ALL = table.freeze(all),
	BY_ID = table.freeze(byId),
})
