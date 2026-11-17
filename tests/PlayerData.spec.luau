--!strict
local Config = require("../src/shared/Config")
local PlayerData = require("../src/server/PlayerData")
local TestKit = require("./TestKit")

-- A new player's data, copied deeply as ProfileStore does.
local function fresh(): PlayerData.PlayerData
	local data = table.clone(PlayerData.TEMPLATE) :: any
	data.milestonesClaimed = {}
	data.badgesAwarded = {}
	data.weekly = table.clone(PlayerData.TEMPLATE.weekly)
	data.purchaseIds = {}
	data.reviveTokens = { 0, 0, 0 }
	data.rotations = 0
	data.robuxDonated = 0
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
				reviveTokens = { 0, 0, 0 },
				rotations = 0,
				robuxDonated = 0,
				purchaseIds = {},
				coopBest = 0,
				coopGamesPlayed = 0,
				pvp = {
					rating = 1000,
					peak = 1000,
					games = 0,
					wins = 0,
					losses = 0,
					draws = 0,
					season = "",
					seasonGames = 0,
					pending = false,
					lastSeason = false,
					medals = {},
				},
			})
			t.expect(table.isfrozen(PlayerData.TEMPLATE)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.pvp)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.pvp.medals)).toBe(true)
			-- Nested defaults are frozen too, so no code can change the template through a shallow copy.
			t.expect(table.isfrozen(PlayerData.TEMPLATE.milestonesClaimed)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.badgesAwarded)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.weekly)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.purchaseIds)).toBe(true)
			t.expect(table.isfrozen(PlayerData.TEMPLATE.reviveTokens)).toBe(true)
		end)

		t.it("keeps the highest Co-op score that counted, and counts Co-op games apart from solo ones", function()
			local data = fresh()
			t.expect(PlayerData.recordCoopScore(data, 400)).toBe(true)
			t.expect(PlayerData.recordCoopScore(data, 300)).toBe(false)
			t.expect(PlayerData.recordCoopScore(data, 400)).toBe(false)
			t.expect(PlayerData.recordCoopScore(data, 900)).toBe(true)
			t.expect(data.coopBest).toBe(900)
			PlayerData.recordCoopGame(data)
			PlayerData.recordCoopGame(data)
			t.expect(data.coopGamesPlayed).toBe(2)
			-- Nothing of it reaches the solo record, the games played, or the weekly boards' numbers.
			t.expect(data.bestScore).toBe(0)
			t.expect(data.gamesPlayed).toBe(0)
			t.expect(data.weekly.bestScore).toBe(0)
		end)

		t.it("gives profiles from before Co-op zero Co-op fields without a migration", function()
			-- ProfileStore's Reconcile copies the template's new fields in, so the version stays as it was.
			local old = PlayerData.migrate({ version = PlayerData.VERSION, bestScore = 120, gamesPlayed = 4 })
			t.expect(old.version).toBe(PlayerData.VERSION)
			t.expect(PlayerData.TEMPLATE.coopBest).toBe(0)
			t.expect(PlayerData.TEMPLATE.coopGamesPlayed).toBe(0)
			t.expect(PlayerData.VERSION).toBe(3)
		end)

		t.it("gives profiles from before PVP starting rank data without a migration", function()
			-- Reconcile copies the whole `pvp` table in; the version stays 3.
			local old = PlayerData.migrate({ version = PlayerData.VERSION, bestScore = 120, coopBest = 50 })
			t.expect(old.version).toBe(3)
			t.expect(PlayerData.TEMPLATE.pvp.rating).toBe(Config.PVP.RATING.START)
			t.expect(PlayerData.TEMPLATE.pvp.peak).toBe(Config.PVP.RATING.START)
		end)

		t.it("places version 1 players in the onboarding funnel by what they had already played", function()
			local veteran = PlayerData.migrate({ version = 1, bestScore = 500, gamesPlayed = 3, tutorialDone = true })
			t.expect(veteran.version).toBe(PlayerData.VERSION)
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

		t.it("keeps paid revives until they are used", function()
			local data = fresh()
			t.expect(PlayerData.useReviveToken(data, 1)).toBe(false)
			PlayerData.addReviveToken(data, 1)
			PlayerData.addReviveToken(data, 1)
			t.expect(PlayerData.reviveTokenCount(data, 1)).toBe(2)
			t.expect(PlayerData.useReviveToken(data, 1)).toBe(true)
			t.expect(data.reviveTokens).toEqual({ 1, 0, 0 })
			t.expect(PlayerData.useReviveToken(data, 1)).toBe(true)
			t.expect(PlayerData.useReviveToken(data, 1)).toBe(false)
		end)

		t.it("lets a dearer revive stand in for a cheaper one but never the other way round", function()
			local data = fresh()
			PlayerData.addReviveToken(data, 1) -- bought at 10 Robux
			t.expect(PlayerData.reviveTokenCount(data, 2)).toBe(0) -- no use for the 15 Robux revive
			t.expect(PlayerData.useReviveToken(data, 3)).toBe(false)
			PlayerData.addReviveToken(data, 3) -- bought at 25 Robux
			t.expect(PlayerData.reviveTokenCount(data, 1)).toBe(2)
			t.expect(PlayerData.reviveTokenCount(data, 2)).toBe(1)
			t.expect(PlayerData.useReviveToken(data, 1)).toBe(true) -- the cheapest allowed goes first
			t.expect(data.reviveTokens).toEqual({ 0, 0, 1 })
			t.expect(PlayerData.useReviveToken(data, 2)).toBe(true)
			t.expect(data.reviveTokens).toEqual({ 0, 0, 0 })
		end)

		t.it("keeps bought rotations until they are used", function()
			local data = fresh()
			t.expect(PlayerData.useRotation(data)).toBe(false)
			PlayerData.addRotations(data, 5)
			t.expect(data.rotations).toBe(5)
			for _ = 1, 5 do
				t.expect(PlayerData.useRotation(data)).toBe(true)
			end
			t.expect(PlayerData.useRotation(data)).toBe(false)
			t.expect(data.rotations).toBe(0)
		end)

		t.it("adds up the Robux donated, never going down and never past the cap", function()
			local data = fresh()
			PlayerData.addDonation(data, 25)
			PlayerData.addDonation(data, 5)
			t.expect(data.robuxDonated).toBe(30)
			PlayerData.addDonation(data, -100)
			t.expect(data.robuxDonated).toBe(30)
			PlayerData.addDonation(data, 5e9)
			t.expect(data.robuxDonated).toBe(1e9)
		end)

		t.it("moves the old single revive count to the highest tier", function()
			local old = PlayerData.migrate({ version = 2, bestScore = 5, reviveTokens = 4 })
			t.expect(old.reviveTokens).toEqual({ 0, 0, 4 })
			local none = PlayerData.migrate({ version = 2 })
			t.expect(none.reviveTokens).toEqual({ 0, 0, 0 })
		end)

		t.it("remembers handled purchases, the latest hundred", function()
			local data = fresh()
			t.expect(PlayerData.hasPurchase(data, "a")).toBe(false)
			PlayerData.rememberPurchase(data, "a")
			t.expect(PlayerData.hasPurchase(data, "a")).toBe(true)
			for i = 1, 100 do
				PlayerData.rememberPurchase(data, `p{i}`)
			end
			t.expect(#data.purchaseIds).toBe(100)
			t.expect(PlayerData.hasPurchase(data, "a")).toBe(false) -- forgotten
			t.expect(PlayerData.hasPurchase(data, "p100")).toBe(true)
		end)
	end)
end
