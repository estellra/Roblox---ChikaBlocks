--!strict
local Config = require("../src/shared/Config")
local CoopProgress = require("../src/server/CoopProgress")
local PlayerData = require("../src/server/PlayerData")
local Progression = require("../src/shared/Progression")
local TestKit = require("./TestKit")

-- A new player's data, copied deeply as ProfileStore does.
local function fresh(): PlayerData.PlayerData
	local data = table.clone(PlayerData.TEMPLATE) :: any
	data.milestonesClaimed = {}
	data.badgesAwarded = {}
	data.weekly = table.clone(PlayerData.TEMPLATE.weekly)
	data.purchaseIds = {}
	data.reviveTokens = { 0, 0, 0 }
	return data
end

return function(t: TestKit.TestKit)
	t.describe("CoopProgress", function()
		t.it("gives each player half the EXP a solo run with the same score would earn", function()
			t.expect(Config.COOP.EXP_SHARE).toBe(0.5)
			t.expect(Progression.expForCoopScore(0)).toBe(0)
			t.expect(Progression.expForCoopScore(1000)).toBe(50)
			t.expect(Progression.expForCoopScore(1795)).toBe(89) -- rounded down, as the solo EXP is
			t.expect(Progression.expForCoopScore(-5)).toBe(0)
			-- Two players together earn about what one solo run does.
			t.expect(2 * Progression.expForCoopScore(1795) >= Progression.expForScore(1795) - 1).toBe(true)
			t.expect(2 * Progression.expForCoopScore(1795) <= Progression.expForScore(1795)).toBe(true)
		end)

		t.it("credits EXP as the team's score grows, never twice for the same points", function()
			local data = fresh()
			local progress = CoopProgress.start(data)
			t.expect(CoopProgress.credit(Progression, progress, data, 10, 10)).toBe(0) -- 10 points are not an EXP yet
			t.expect(CoopProgress.credit(Progression, progress, data, 60, 60)).toBe(3)
			t.expect(CoopProgress.credit(Progression, progress, data, 60, 60)).toBe(0) -- no new points
			t.expect(CoopProgress.credit(Progression, progress, data, 260, 260)).toBe(10)
			t.expect(progress.expGranted).toBe(13)
			t.expect(data.exp).toBe(13)
			t.expect(data.level).toBe(1)
		end)

		t.it("levels the player up and reports what the run earned", function()
			local data = fresh()
			data.exp = 90
			local progress = CoopProgress.start(data)
			-- 400 points are 20 EXP each: 90 + 20 passes the 100 a level costs.
			t.expect(CoopProgress.credit(Progression, progress, data, 400, 400)).toBe(20)
			local rewards = CoopProgress.rewards(progress, data)
			t.expect(rewards.expGained).toBe(20)
			t.expect(rewards.levelBefore).toBe(1)
			t.expect(rewards.expBefore).toBe(90)
			t.expect(rewards.level).toBe(2)
			t.expect(rewards.exp).toBe(10)
			t.expect(rewards.titles).toEqual({})
		end)

		t.it("raises the Co-op best with the score that counts, and leaves the solo record alone", function()
			local data = fresh()
			local progress = CoopProgress.start(data)
			CoopProgress.credit(Progression, progress, data, 800, 800)
			t.expect(data.coopBest).toBe(800)
			-- The partner left at 800: the team plays on to 1,200 but only 800 counts.
			CoopProgress.credit(Progression, progress, data, 1200, 800)
			t.expect(data.coopBest).toBe(800)
			t.expect(progress.expGranted).toBe(60) -- EXP still follows the team's score
			t.expect(data.bestScore).toBe(0)
			t.expect(data.gamesPlayed).toBe(0)

			-- A worse run later doesn't lower it; a better one raises it.
			local next = CoopProgress.start(data)
			CoopProgress.credit(Progression, next, data, 300, 300)
			t.expect(data.coopBest).toBe(800)
			CoopProgress.credit(Progression, next, data, 1500, 1500)
			t.expect(data.coopBest).toBe(1500)
		end)

		t.it("counts a Co-op game once per run, whichever comes first: game over or the partner leaving", function()
			local data = fresh()
			local progress = CoopProgress.start(data)
			t.expect(CoopProgress.countGame(progress, data)).toBe(true) -- the partner left
			t.expect(CoopProgress.countGame(progress, data)).toBe(false) -- and then game over
			t.expect(data.coopGamesPlayed).toBe(1)
			t.expect(data.gamesPlayed).toBe(0)
			t.expect(CoopProgress.countGame(CoopProgress.start(data), data)).toBe(true) -- the next run
			t.expect(data.coopGamesPlayed).toBe(2)
		end)
	end)
end
