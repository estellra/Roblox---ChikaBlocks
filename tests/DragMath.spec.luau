--!strict
local DragMath = require("../src/client/Util/DragMath")
local TestKit = require("./TestKit")

local GRID: DragMath.Grid = { x = 100, y = 50, size = 400, cells = 8 } -- 50 px cells
local CELL = 50

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
				local pointerX, pointerY = DragMath.pointerFor(GRID, 2, 5, 3, 2, isTouch, 1.5)
				local left, top = DragMath.pieceTopLeft(pointerX, pointerY, 3, 2, CELL, isTouch, 1.5)
				t.expect({ DragMath.snap(left, top, GRID, inBounds(3, 2), 0.75) }).toEqual({ 2, 5 })
			end
		end)
	end)
end
