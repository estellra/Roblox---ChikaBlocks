--!strict
-- Geometry for drag and drop. Plain numbers only (no Roblox types) so Lune can test it.
-- Positions are pixels in one screen space; the grid is a square given by its top-left corner and side.

export type Grid = { x: number, y: number, size: number, cells: number }

local DragMath = {}

-- Top-left corner of the dragged piece. With a mouse the piece is centered on the pointer; with touch it
-- sits above the finger, its bottom edge `liftCells` cells higher, so the finger doesn't cover it.
function DragMath.pieceTopLeft(
	pointerX: number,
	pointerY: number,
	widthCells: number,
	heightCells: number,
	cell: number,
	isTouch: boolean,
	liftCells: number
): (number, number)
	local width, height = widthCells * cell, heightCells * cell
	local left = pointerX - width / 2
	local top = if isTouch then pointerY - liftCells * cell - height else pointerY - height / 2
	return left, top
end

-- Board cell for a piece whose top-left corner is at (left, top), or nil.
-- Takes the nearest cell when canPlace accepts it; otherwise the nearest acceptable cell among the four
-- around the exact position, as long as it is no more than `assistCells` away on either axis.
function DragMath.snap(
	left: number,
	top: number,
	grid: Grid,
	canPlace: (x: number, y: number) -> boolean,
	assistCells: number
): (number?, number?)
	local cell = grid.size / grid.cells
	local exactX, exactY = (left - grid.x) / cell, (top - grid.y) / cell
	local baseX, baseY = math.floor(exactX), math.floor(exactY)

	local candidates: { { number } } = {}
	for x = baseX, baseX + 1 do
		for y = baseY, baseY + 1 do
			local distance = math.max(math.abs(x - exactX), math.abs(y - exactY))
			if distance <= assistCells then
				table.insert(candidates, { x, y, distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a[3] < b[3]
	end)

	for _, candidate in candidates do
		if canPlace(candidate[1], candidate[2]) then
			return candidate[1], candidate[2]
		end
	end
	return nil, nil
end

-- Pointer position that drops a piece of the given size at board cell (x, y): the inverse of
-- pieceTopLeft for the cell's exact corner. Used by tests and the Studio debug bridge.
function DragMath.pointerFor(
	grid: Grid,
	x: number,
	y: number,
	widthCells: number,
	heightCells: number,
	isTouch: boolean,
	liftCells: number
): (number, number)
	local cell = grid.size / grid.cells
	local left, top = grid.x + x * cell, grid.y + y * cell
	local pointerX = left + widthCells * cell / 2
	local pointerY = if isTouch then top + heightCells * cell + liftCells * cell else top + heightCells * cell / 2
	return pointerX, pointerY
end

return DragMath
