--!strict
local Config = require("../src/shared/Config")
local Seasons = require("../src/server/Seasons")
local TestKit = require("./TestKit")

local TIERS = Config.PVP.TIERS
local DEC_1_2026 = 1796083200 -- 2026-12-01 00:00:00 UTC
local JAN_1_2027 = 1798761600 -- 2027-01-01 00:00:00 UTC
local MAR_1_2028 = 1835481600 -- 2028-03-01 00:00:00 UTC (after a leap day)

return function(t: TestKit.TestKit)
	t.describe("Seasons", function()
		t.it("names a season after its UTC month, changing on the first second of the month", function()
			t.expect(Seasons.id(DEC_1_2026 - 1)).toBe("2026M11")
			t.expect(Seasons.id(DEC_1_2026)).toBe("2026M12")
			t.expect(Seasons.id(JAN_1_2027 - 1)).toBe("2026M12")
			t.expect(Seasons.id(JAN_1_2027)).toBe("2027M01")
			t.expect(Seasons.id(MAR_1_2028 - 1)).toBe("2028M02")
			t.expect(Seasons.id(MAR_1_2028)).toBe("2028M03")
		end)

		t.it("gives ids that sort in time order", function()
			t.expect(Seasons.id(DEC_1_2026) < Seasons.id(JAN_1_2027)).toBe(true)
			t.expect(Seasons.id(JAN_1_2027) < Seasons.id(MAR_1_2028)).toBe(true)
		end)

		t.it("puts points in tiers at the thresholds", function()
			t.expect(Seasons.tier(TIERS, 100)).toBe("Bronze")
			t.expect(Seasons.tier(TIERS, 999)).toBe("Bronze")
			t.expect(Seasons.tier(TIERS, 1000)).toBe("Silver")
			t.expect(Seasons.tier(TIERS, 1199)).toBe("Silver")
			t.expect(Seasons.tier(TIERS, 1200)).toBe("Gold")
			t.expect(Seasons.tier(TIERS, 1400)).toBe("Platinum")
			t.expect(Seasons.tier(TIERS, 1600)).toBe("Diamond")
			t.expect(Seasons.tier(TIERS, 1799)).toBe("Diamond")
			t.expect(Seasons.tier(TIERS, 1800)).toBe("Master")
			t.expect(Seasons.tier(TIERS, 3000)).toBe("Master")
		end)

		t.it("orders tiers from Bronze to Master", function()
			t.expect(Seasons.tierIndex(TIERS, "Bronze")).toBe(1)
			t.expect(Seasons.tierIndex(TIERS, "Master")).toBe(#TIERS)
			t.expect(Seasons.tierIndex(TIERS, "Wood")).toBe(nil)
			for i = 2, #TIERS do
				t.expect(TIERS[i].from > TIERS[i - 1].from).toBe(true)
			end
		end)
	end)
end
