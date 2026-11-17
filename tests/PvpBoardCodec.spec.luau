--!strict
local Config = require("../src/shared/Config")
local PvpBoardCodec = require("../src/shared/PvpBoardCodec")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local CELLS = Config.GRID_SIZE * Config.GRID_SIZE
local GARBAGE = Config.PVP.GARBAGE_COLOR

local function randomView(rng: Rng.Rng): PvpBoardCodec.View
	local cells = table.create(CELLS, 0)
	for i = 1, CELLS do
		cells[i] = rng:nextInt(0, GARBAGE)
	end
	return {
		cells = cells,
		score = rng:nextInt(0, 2 ^ 31),
		pending = rng:nextInt(0, Config.PVP.GARBAGE_QUEUE_MAX),
		version = rng:nextInt(0, 2 ^ 16 - 1),
	}
end

return function(t: TestKit.TestKit)
	t.describe("PvpBoardCodec", function()
		t.it("packs a board into 39 bytes and back", function()
			local rng = Rng.new(5)
			for _ = 1, 200 do
				local view = randomView(rng)
				local data = PvpBoardCodec.encode(view)
				t.expect(buffer.len(data)).toBe(39)
				t.expect(PvpBoardCodec.decode(data)).toEqual(view)
			end
		end)

		t.it("clamps values that don't fit and wraps the version", function()
			local cells = table.create(CELLS, 0)
			cells[1] = 99
			cells[2] = -3
			local view = PvpBoardCodec.decode(
				PvpBoardCodec.encode({ cells = cells, score = -10, pending = 400, version = 2 ^ 16 + 5 })
			)
			assert(view)
			t.expect(view.cells[1]).toBe(GARBAGE)
			t.expect(view.cells[2]).toBe(0)
			t.expect(view.score).toBe(0)
			t.expect(view.pending).toBe(255)
			t.expect(view.version).toBe(5)
		end)

		t.it("rejects anything that isn't a well-formed board", function()
			t.expect(PvpBoardCodec.decode(nil)).toBe(nil)
			t.expect(PvpBoardCodec.decode("x")).toBe(nil)
			t.expect(PvpBoardCodec.decode(buffer.create(38))).toBe(nil)
			t.expect(PvpBoardCodec.decode(buffer.create(40))).toBe(nil)
			local bad = buffer.create(PvpBoardCodec.SIZE)
			buffer.writeu8(bad, 3, 0xF0) -- a cell with color 15
			t.expect(PvpBoardCodec.decode(bad)).toBe(nil)
		end)

		t.it("tells a newer version, across the wrap", function()
			t.expect(PvpBoardCodec.isNewer(6, 5)).toBe(true)
			t.expect(PvpBoardCodec.isNewer(5, 5)).toBe(false)
			t.expect(PvpBoardCodec.isNewer(4, 5)).toBe(false)
			t.expect(PvpBoardCodec.isNewer(2, 2 ^ 16 - 3)).toBe(true)
			t.expect(PvpBoardCodec.isNewer(2 ^ 16 - 3, 2)).toBe(false)
		end)
	end)
end
