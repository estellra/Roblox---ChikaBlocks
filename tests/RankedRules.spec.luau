--!strict
local Config = require("../src/shared/Config")
local PlayerData = require("../src/server/PlayerData")
local PvpRating = require("../src/server/PvpRating")
local RankedRules = require("../src/server/RankedRules")
local TestKit = require("./TestKit")

local MIN_LEVEL = Config.PVP.MIN_LEVEL

local function data(level: number, tutorialDone: boolean): PlayerData.PlayerData
	local copy = table.clone(PlayerData.TEMPLATE) :: any
	copy.level = level
	copy.tutorialDone = tutorialDone
	copy.pvp = table.clone(PlayerData.TEMPLATE.pvp)
	copy.pvp.medals = {}
	return copy
end

local function eligibility(overrides: { [string]: any }): RankedRules.Eligibility
	local info: any = {
		enabled = true,
		privateServer = false,
		data = data(MIN_LEVEL, true),
		minLevel = MIN_LEVEL,
		busy = false,
	}
	for key, value in overrides do
		info[key] = value
	end
	return info
end

return function(t: TestKit.TestKit)
	t.describe("RankedRules", function()
		t.it("lets a free player who finished the tutorial and reached the level queue", function()
			t.expect(RankedRules.canQueue(eligibility({}))).toBe(true)
		end)

		t.it("says why a player can't queue", function()
			local function reason(overrides: { [string]: any }): string?
				local _, why = RankedRules.canQueue(eligibility(overrides))
				return why
			end
			t.expect(reason({ enabled = false })).toBe("off")
			t.expect(reason({ privateServer = true })).toBe("private")
			t.expect(reason({ data = false })).toBe("loading")
			t.expect(reason({ data = data(MIN_LEVEL, false) })).toBe("tutorial")
			t.expect(reason({ data = data(MIN_LEVEL - 1, true) })).toBe("level")
			t.expect(reason({ busy = true })).toBe("busy")
		end)

		t.it("rates only ranked matches the pair's count allows", function()
			t.expect(RankedRules.isRated("ranked", true)).toBe(true)
			t.expect(RankedRules.isRated("ranked", false)).toBe(false)
			t.expect(RankedRules.isRated("friendly", true)).toBe(false)
			t.expect(RankedRules.isRated("bot", true)).toBe(false)
		end)

		t.it("closes a rated match with the player's result and voids a cancelled one", function()
			local rating = PvpRating.new(Config.PVP.RATING, Config.PVP.TIERS)
			local winner, loser = data(5, true).pvp, data(5, true).pvp
			rating:open(winner, "m1", loser.rating, 0)
			rating:open(loser, "m1", winner.rating, 0)
			t.expect(RankedRules.settle(rating, winner, "m1", "time", "win")).toBe(20)
			t.expect(RankedRules.settle(rating, loser, "m1", "forfeit", "loss")).toBe(-20)
			t.expect(winner.rating).toBe(1020)
			t.expect(loser.rating).toBe(980)

			local cancelled = data(5, true).pvp
			rating:open(cancelled, "m2", 1000, 0)
			t.expect(RankedRules.settle(rating, cancelled, "m2", "cancelled", nil)).toBe(nil)
			t.expect(cancelled.pending).toBe(false)
			t.expect(cancelled.rating).toBe(1000)
			t.expect(cancelled.games).toBe(0)
		end)

		t.it("changes nothing for an unrated match (nothing pending)", function()
			local rating = PvpRating.new(Config.PVP.RATING, Config.PVP.TIERS)
			local pvp = data(5, true).pvp
			t.expect(RankedRules.settle(rating, pvp, "m3", "time", "win")).toBe(nil)
			t.expect(pvp.rating).toBe(1000)
			t.expect(pvp.games).toBe(0)
		end)
	end)
end
