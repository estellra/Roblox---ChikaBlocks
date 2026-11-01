--!strict
local PlayerData = require("../src/server/PlayerData")
local TestKit = require("./TestKit")

-- A new player's data, copied deeply as ProfileStore does.
local function fresh(): PlayerData.PlayerData
	local data = table.clone(PlayerData.TEMPLATE) :: any
	data.milestonesClaimed = {}
	data.badgesAwarded = {}
	data.weekly = table.clone(PlayerData.TEMPLATE.weekly)
	return data
end

return function(t: TestKit.TestKit)
	t.describe("PlayerData", function()
		t.it("starts new players at zero with the current version", function()
			t.expect(PlayerData.TEMPLATE).toEqual({
				version = PlayerData.VERSION,
				bestScore = 0,
				gamesPlayed = 0,
				tutorialDone = false,
				onboardingStep = 0,
				level = 1,
				exp = 0,
				milestonesClaimed = {},
				badgesAwarded = {},
				weekly = { week = "", bestScore = 0, exp = 0 },
			})
			t.expect(table.isfrozen(PlayerData.TEMPLATE)).toBe(true)
			-- Nested defaults are frozen too, so no code can change the template through a shallow copy.
			t.expect(table.isfrozen(PlayerData.TEMPLATE.milestonesClaimed)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.badgesAwarded)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.weekly)).toBe(true)
		end)

		t.it("places version 1 players in the onboarding funnel by what they had already played", function()
			local veteran = PlayerData.migrate({ version = 1, bestScore = 500, gamesPlayed = 3, tutorialDone = true })
			t.expect(veteran.version).toBe(2)
			t.expect(veteran.onboardingStep).toBe(6)
			t.expect(veteran.bestScore).toBe(500)
			local midTutorial =
				PlayerData.migrate({ version = 1, bestScore = 13, gamesPlayed = 0, tutorialDone = true })
			t.expect(midTutorial.onboardingStep).toBe(3)
			local newcomer = PlayerData.migrate({ version = 1, bestScore = 0, gamesPlayed = 0, tutorialDone = false })
			t.expect(newcomer.onboardingStep).toBe(0)
		end)

		t.it("leaves current data alone", function()
			local data = PlayerData.migrate({
				version = 2,
				bestScore = 10,
				gamesPlayed = 1,
				tutorialDone = true,
				onboardingStep = 4,
			})
			t.expect(data.onboardingStep).toBe(4)
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

		t.it("marks the tutorial done once", function()
			local data = fresh()
			t.expect(PlayerData.markTutorialDone(data)).toBe(true)
			t.expect(data.tutorialDone).toBe(true)
			t.expect(PlayerData.markTutorialDone(data)).toBe(false)
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
