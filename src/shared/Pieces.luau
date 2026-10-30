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
}

-- "#" is a filled cell, "." is empty. Rows go top to bottom.
local SHAPES: { { id: string, rows: { string } } } = {
	-- Small (1-3 cells)
	{ id = "Dot", rows = { "#" } },
	{ id = "I2_H", rows = { "##" } },
	{ id = "I2_V", rows = { "#", "#" } },
	{ id = "I3_H", rows = { "###" } },
	{ id = "I3_V", rows = { "#", "#", "#" } },
	{ id = "L3_1", rows = { "##", "#." } },
	{ id = "L3_2", rows = { "##", ".#" } },
	{ id = "L3_3", rows = { "#.", "##" } },
	{ id = "L3_4", rows = { ".#", "##" } },

	-- Medium (4 cells)
	{ id = "I4_H", rows = { "####" } },
	{ id = "I4_V", rows = { "#", "#", "#", "#" } },
	{ id = "O2", rows = { "##", "##" } },
	{ id = "L4_1", rows = { "#.", "#.", "##" } },
	{ id = "L4_2", rows = { "###", "#.." } },
	{ id = "L4_3", rows = { "##", ".#", ".#" } },
	{ id = "L4_4", rows = { "..#", "###" } },
	{ id = "J4_1", rows = { ".#", ".#", "##" } },
	{ id = "J4_2", rows = { "#..", "###" } },
	{ id = "J4_3", rows = { "##", "#.", "#." } },
	{ id = "J4_4", rows = { "###", "..#" } },
	{ id = "T4_1", rows = { "###", ".#." } },
	{ id = "T4_2", rows = { ".#.", "###" } },
	{ id = "T4_3", rows = { "#.", "##", "#." } },
	{ id = "T4_4", rows = { ".#", "##", ".#" } },
	{ id = "S_H", rows = { ".##", "##." } },
	{ id = "S_V", rows = { "#.", "##", ".#" } },
	{ id = "Z_H", rows = { "##.", ".##" } },
	{ id = "Z_V", rows = { ".#", "##", "#." } },

	-- Large (5-6 cells)
	{ id = "I5_H", rows = { "#####" } },
	{ id = "I5_V", rows = { "#", "#", "#", "#", "#" } },
	{ id = "R2x3", rows = { "##", "##", "##" } },
	{ id = "R3x2", rows = { "###", "###" } },
	{ id = "L5_1", rows = { "#..", "#..", "###" } },
	{ id = "L5_2", rows = { "###", "#..", "#.." } },
	{ id = "L5_3", rows = { "###", "..#", "..#" } },
	{ id = "L5_4", rows = { "..#", "..#", "###" } },

	-- Huge (9 cells)
	{ id = "O3", rows = { "###", "###", "###" } },
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

local function parse(id: string, rows: { string }): Piece
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
	})
end

local all: { Piece } = {}
local byId: { [string]: Piece } = {}
for _, shape in SHAPES do
	local piece = parse(shape.id, shape.rows)
	table.insert(all, piece)
	byId[piece.id] = piece
end

return table.freeze({
	ALL = table.freeze(all),
	BY_ID = table.freeze(byId),
})
