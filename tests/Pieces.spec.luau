--!strict
local Pieces = require("../src/shared/Pieces")
local TestKit = require("./TestKit")

local function signature(piece: Pieces.Piece): string
	local keys = {}
	for _, cell in piece.cells do
		table.insert(keys, `{cell.x},{cell.y}`)
	end
	table.sort(keys)
	return table.concat(keys, ";")
end

return function(t: TestKit.TestKit)
	t.describe("Pieces", function()
		t.it("has 37 pieces split 9 / 19 / 8 / 1 by size", function()
			t.expect(#Pieces.ALL).toBe(37)
			local counts = { Small = 0, Medium = 0, Large = 0, Huge = 0 }
			for _, piece in Pieces.ALL do
				counts[piece.size] += 1
			end
			t.expect(counts).toEqual({ Small = 9, Medium = 19, Large = 8, Huge = 1 })
		end)

		t.it("has unique ids that BY_ID resolves", function()
			local seen = {}
			for _, piece in Pieces.ALL do
				t.expect(seen[piece.id]).toBe(nil)
				seen[piece.id] = true
				t.expect(Pieces.BY_ID[piece.id]).toBe(piece)
			end
		end)

		t.it("normalizes every piece to its top-left corner", function()
			for _, piece in Pieces.ALL do
				local minX, minY, maxX, maxY = math.huge, math.huge, -1, -1
				for _, cell in piece.cells do
					minX, minY = math.min(minX, cell.x), math.min(minY, cell.y)
					maxX, maxY = math.max(maxX, cell.x), math.max(maxY, cell.y)
				end
				t.expect(minX).toBe(0)
				t.expect(minY).toBe(0)
				t.expect(piece.width).toBe(maxX + 1)
				t.expect(piece.height).toBe(maxY + 1)
			end
		end)

		t.it("never repeats a cell inside a piece or a shape across pieces", function()
			local shapes = {}
			for _, piece in Pieces.ALL do
				local key = signature(piece)
				local cellsSeen = {}
				for _, cell in piece.cells do
					local cellKey = `{cell.x},{cell.y}`
					t.expect(cellsSeen[cellKey]).toBe(nil)
					cellsSeen[cellKey] = true
				end
				t.expect(shapes[key]).toBe(nil)
				shapes[key] = piece.id
			end
		end)

		t.it("is read-only", function()
			t.expect(table.isfrozen(Pieces.ALL)).toBe(true)
			t.expect(table.isfrozen(Pieces.BY_ID.O3)).toBe(true)
			t.expect(table.isfrozen(Pieces.BY_ID.O3.cells)).toBe(true)
		end)
	end)
end
