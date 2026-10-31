--!strict
-- Geometry for drag and drop. Plain numbers only (no Roblox types) so Lune can test it.
-- Positions are pixels in one screen space; the grid is a square given by its top-left corner and side.

export type Grid = { x: number, y: number, size: number, cells: number }

local REACH_MARGIN_CELLS = 0.25 -- the last row must be reachable this far above the screen's bottom edge
local EASE_CELLS = 3 -- how far above that point the touch lift starts easing off

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

-- How the touch lift eases off near the bottom of the screen, in pixels: where the ease starts and ends, and
-- how much of the lift is gone at its end. Nothing to ease when the finger can get low enough with the full
-- lift to drop on the last row (`amount` is 0), as on phones held upright.
local function liftEase(grid: Grid, liftCells: number, screenBottom: number): (number, number, number)
	local cell = grid.size / grid.cells
	local reach = screenBottom - REACH_MARGIN_CELLS * cell
	local shortfall = grid.y + grid.size + liftCells * cell - reach
	return reach - EASE_CELLS * cell, reach, math.clamp(shortfall, 0, liftCells * cell)
end

-- Lift for a touch drag with the finger at `pointerY`, in cells: normally `liftCells`. When the grid ends so
-- close to the bottom of the screen (phones held sideways) that the finger would have to go below it to drop
-- on the last row, the lift shrinks steadily over the lowest few cells the finger can reach, so the piece
-- catches up with the finger by the time it gets there.
function DragMath.touchLift(pointerY: number, grid: Grid, liftCells: number, screenBottom: number): number
	local from, to, amount = liftEase(grid, liftCells, screenBottom)
	local progress = math.clamp((pointerY - from) / (to - from), 0, 1)
	return liftCells - amount * progress / (grid.size / grid.cells)
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
-- pieceTopLeft (with touchLift for touch) for the cell's exact corner. Used by tests and the Studio debug bridge.
function DragMath.pointerFor(
	grid: Grid,
	x: number,
	y: number,
	widthCells: number,
	heightCells: number,
	isTouch: boolean,
	liftCells: number,
	screenBottom: number
): (number, number)
	local cell = grid.size / grid.cells
	local left, top = grid.x + x * cell, grid.y + y * cell
	local pointerX = left + widthCells * cell / 2
	if not isTouch then
		return pointerX, top + heightCells * cell / 2
	end
	-- The finger sits `touchLift` below the piece's bottom edge; that lift is constant above the ease, shrinks
	-- linearly inside it, and stays at its smallest below it.
	local bottom, lift = top + heightCells * cell, liftCells * cell
	local from, to, amount = liftEase(grid, liftCells, screenBottom)
	if bottom + lift <= from then
		return pointerX, bottom + lift
	end
	local pointerY = (bottom + lift + amount * from / (to - from)) / (1 + amount / (to - from))
	if pointerY <= to then
		return pointerX, pointerY
	end
	return pointerX, bottom + lift - amount
end

return DragMath
