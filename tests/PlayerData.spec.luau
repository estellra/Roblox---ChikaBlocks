--!strict
local PlayerData = require("../src/server/PlayerData")
local TestKit = require("./TestKit")

local function fresh(): PlayerData.PlayerData
	return table.clone(PlayerData.TEMPLATE) :: any
end

return function(t: TestKit.TestKit)
	t.describe("PlayerData", function()
		t.it("starts new players at zero with the current version", function()
			t.expect(PlayerData.TEMPLATE).toEqual({
				version = PlayerData.VERSION,
				bestScore = 0,
				gamesPlayed = 0,
				tutorialDone = false,
			})
			t.expect(table.isfrozen(PlayerData.TEMPLATE)).toBe(true)
		end)

		t.it("stamps the current version on data saved without one", function()
			local data = PlayerData.migrate({ bestScore = 120 })
			t.expect(data.version).toBe(PlayerData.VERSION)
			t.expect(data.bestScore).toBe(120)
		end)

		t.it("keeps only a higher best", function()
			local data = fresh()
			t.expect(PlayerData.recordScore(data, 300)).toBe(true)
			t.expect(PlayerData.recordScore(data, 200)).toBe(false)
			t.expect(PlayerData.recordScore(data, 300)).toBe(false)
			t.expect(data.bestScore).toBe(300)
		end)

		t.it("counts finished runs and records their score", function()
			local data = fresh()
			PlayerData.recordRunEnd(data, 450)
			PlayerData.recordRunEnd(data, 100)
			t.expect(data.gamesPlayed).toBe(2)
			t.expect(data.bestScore).toBe(450)
		end)
	end)
end
