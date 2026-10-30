--!strict
local Config = require("../src/shared/Config")
local TestKit = require("./TestKit")

return function(t: TestKit.TestKit)
	t.describe("Config", function()
		t.it("uses an 8x8 board with 3 pieces per set", function()
			t.expect(Config.GRID_SIZE).toBe(8)
			t.expect(Config.PIECES_PER_SET).toBe(3)
		end)

		t.it("is frozen", function()
			t.expect(table.isfrozen(Config)).toBe(true)
		end)
	end)
end
