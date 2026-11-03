--!strict
local Config = require("../src/shared/Config")
local TestKit = require("./TestKit")

return function(t: TestKit.TestKit)
	t.describe("Config", function()
		t.it("uses an 8x8 board with 3 pieces per set", function()
			t.expect(Config.GRID_SIZE).toBe(8)
			t.expect(Config.PIECES_PER_SET).toBe(3)
		end)

		t.it("sells every developer product under one purpose", function()
			local seen: { [number]: string } = {}
			local function add(productId: number, purpose: string)
				t.expect(typeof(productId)).toBe("number")
				t.expect(productId > 0).toBe(true)
				t.expect(seen[productId]).toBe(nil) -- a product ID can only mean one thing
				seen[productId] = purpose
			end
			for tier, productId in Config.REVIVE_PRODUCTS do
				add(productId, `revive {tier}`)
			end
			add(Config.ROTATION_PRODUCT, "rotation")
			t.expect(#Config.DONATE_PRODUCTS).toBe(9)
			for tier, productId in Config.DONATE_PRODUCTS do
				add(productId, `donate {tier}`)
			end
		end)

		t.it("is frozen", function()
			t.expect(table.isfrozen(Config)).toBe(true)
		end)
	end)
end
