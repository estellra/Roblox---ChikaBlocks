--!strict
local DragMath = require("../src/client/Util/DragMath")
local TestKit = require("./TestKit")

local GRID: DragMath.Grid = { x = 100, y = 50, size = 400, cells = 8 } -- 50 px cells
local CELL = 50
local ROOMY_BOTTOM = 1000 -- screen bottom far below the grid (phone held upright: the tray is underneath)
local TIGHT_BOTTOM = 470 -- screen bottom 20 px under the grid (phone held sideways)

local function inBounds(width: number, height: number): (number, number) -> boolean
	return function(x, y)
		return x >= 0 and y >= 0 and x + width <= 8 and y + height <= 8
	end
end

return function(t: TestKit.TestKit)
	t.describe("DragMath", function()
		t.it("centers the piece on the mouse", function()
			local left, top = DragMath.pieceTopLeft(300, 200, 2, 1, CELL, false, 1.5)
			t.expect(left).toBe(250)
			t.expect(top).toBe(175)
		end)

		t.it("lifts the piece above a finger", function()
			local left, top = DragMath.pieceTopLeft(300, 400, 1, 2, CELL, true, 1.5)
			t.expect(left).toBe(275)
			t.expect(top).toBe(400 - 75 - 100)
		end)

		t.it("snaps an exact position to its cell", function()
			t.expect({ DragMath.snap(250, 250, GRID, inBounds(1, 1), 0.75) }).toEqual({ 3, 4 })
		end)

		t.it("rounds to the nearest cell", function()
			-- 3.4 rounds down, 4.6 rounds up.
			t.expect({ DragMath.snap(100 + 3.4 * CELL, 50 + 4.6 * CELL, GRID, inBounds(1, 1), 0.75) }).toEqual({ 3, 5 })
		end)

		t.it("prefers the nearest cell when its neighbour is also free", function()
			local x, y = DragMath.snap(100 + 3.3 * CELL, 50 + 4 * CELL, GRID, inBounds(1, 1), 0.75)
			t.expect(x).toBe(3)
			t.expect(y).toBe(4)
		end)

		t.it("falls back to a neighbouring cell within the assist distance", function()
			local onlyFour = function(x: number, y: number): boolean
				return x == 4 and y == 4
			end
			t.expect({ DragMath.snap(100 + 3.3 * CELL, 50 + 4 * CELL, GRID, onlyFour, 0.75) }).toEqual({ 4, 4 })
			-- 3.1 is 0.9 cells away from column 4: too far.
			t.expect({ DragMath.snap(100 + 3.1 * CELL, 50 + 4 * CELL, GRID, onlyFour, 0.75) }).toEqual({})
		end)

		t.it("finds nothing when the piece is off the board", function()
			t.expect({ DragMath.snap(-500, 50, GRID, inBounds(1, 1), 0.75) }).toEqual({})
			-- A 3-wide piece hanging one cell past the right edge.
			t.expect({ DragMath.snap(100 + 6 * CELL, 50, GRID, inBounds(3, 1), 0.75) }).toEqual({})
		end)

		t.it("gives back the pointer that drops a piece on a cell, for mouse and touch", function()
			for _, isTouch in { false, true } do
				local pointerX, pointerY = DragMath.pointerFor(GRID, 2, 5, 3, 2, isTouch, 1.5, ROOMY_BOTTOM)
				local lift = if isTouch then DragMath.touchLift(pointerY, GRID, 1.5, ROOMY_BOTTOM) else 0
				local left, top = DragMath.pieceTopLeft(pointerX, pointerY, 3, 2, CELL, isTouch, lift)
				t.expect({ DragMath.snap(left, top, GRID, inBounds(3, 2), 0.75) }).toEqual({ 2, 5 })
			end
		end)

		t.it("keeps the full touch lift when there is room below the grid", function()
			for pointerY = 0, ROOMY_BOTTOM, 10 do
				t.expect(DragMath.touchLift(pointerY, GRID, 1.5, ROOMY_BOTTOM)).toBe(1.5)
			end
		end)

		t.it("lets a finger reach every row when the grid nearly touches the screen's bottom", function()
			local reach = TIGHT_BOTTOM - 0.25 * CELL
			for _, height in { 1, 2, 3 } do
				for y = 0, 8 - height do
					local pointerX, pointerY = DragMath.pointerFor(GRID, 3, y, 1, height, true, 1.5, TIGHT_BOTTOM)
					t.expect(pointerY <= reach + 1e-9).toBe(true)
					local lift = DragMath.touchLift(pointerY, GRID, 1.5, TIGHT_BOTTOM)
					local left, top = DragMath.pieceTopLeft(pointerX, pointerY, 1, height, CELL, true, lift)
					t.expect({ DragMath.snap(left, top, GRID, inBounds(1, height), 0.75) }).toEqual({ 3, y })
				end
			end
			-- With the full lift, the last row would need the finger below the screen.
			local _, fullLift = DragMath.pointerFor(GRID, 3, 7, 1, 1, true, 1.5, ROOMY_BOTTOM)
			t.expect(fullLift > TIGHT_BOTTOM).toBe(true)
		end)

		t.it("still reaches the last row with the finger on the edge when the grid touches it", function()
			local screenBottom = GRID.y + GRID.size
			local lift = DragMath.touchLift(screenBottom, GRID, 1.5, screenBottom)
			t.expect(lift).toBe(0)
			local left, top = DragMath.pieceTopLeft(275, screenBottom, 1, 1, CELL, true, lift)
			t.expect({ DragMath.snap(left, top, GRID, inBounds(1, 1), 0.75) }).toEqual({ 3, 7 })
		end)

		t.it("moves an eased piece steadily with the finger, never below it", function()
			local previous = -math.huge
			for pointerY = 0, TIGHT_BOTTOM, 0.5 do
				local lift = DragMath.touchLift(pointerY, GRID, 1.5, TIGHT_BOTTOM)
				t.expect(lift >= 0 and lift <= 1.5).toBe(true)
				local _, top = DragMath.pieceTopLeft(300, pointerY, 1, 1, CELL, true, lift)
				t.expect(top >= previous).toBe(true) -- follows the finger down, never jumps back up
				t.expect(top - previous <= 1.5 or previous == -math.huge).toBe(true) -- at most 3x the finger's speed
				previous = top
			end
		end)
	end)
end
