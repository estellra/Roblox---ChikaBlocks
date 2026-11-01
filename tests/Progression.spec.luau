--!strict
local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local TestKit = require("./TestKit")

local function player(bestScore: number, level: number): Progression.ProgressData
	return { bestScore = bestScore, level = level, exp = 0, milestonesClaimed = {}, badgesAwarded = {} }
end

local function ids(milestones: { Progression.Milestone }): { string }
	local result = {}
	for i, milestone in milestones do
		result[i] = milestone.id
	end
	return result
end

-- Milestones with a fake table, to test badges and milestones added later.
local function withMilestones(milestones: { Progression.Milestone }, test: () -> ())
	local original = Progression.MILESTONES
	Progression.MILESTONES = milestones
	local ok, err = pcall(test)
	Progression.MILESTONES = original
	if not ok then
		error(err, 0)
	end
end

return function(t: TestKit.TestKit)
	t.describe("Progression", function()
		t.it("earns one EXP per ten points, rounded down", function()
			t.expect(Progression.expForScore(0)).toBe(0)
			t.expect(Progression.expForScore(9)).toBe(0)
			t.expect(Progression.expForScore(3129)).toBe(312)
			t.expect(Progression.expForScore(-5)).toBe(0)
		end)

		t.it("needs 100 EXP for level 2, then 50 more for each level", function()
			t.expect(Progression.expToNext(1)).toBe(100)
			t.expect(Progression.expToNext(2)).toBe(150)
			t.expect(Progression.expToNext(10)).toBe(550)
		end)

		t.it("levels up as many times as the EXP covers and keeps the rest", function()
			local data = player(0, 1)
			t.expect(Progression.addExp(data, 99)).toBe(0)
			t.expect(data.level).toBe(1)
			t.expect(Progression.addExp(data, 1)).toBe(1)
			t.expect(data.level).toBe(2)
			t.expect(data.exp).toBe(0)
			-- 150 (to level 3) + 200 (to level 4) + 30 left over
			t.expect(Progression.addExp(data, 380)).toBe(2)
			t.expect(data.level).toBe(4)
			t.expect(data.exp).toBe(30)
			t.expect(Progression.addExp(data, 0)).toBe(0)
			t.expect(Progression.addExp(data, -10)).toBe(0)
			t.expect(data.exp).toBe(30)
		end)

		t.it("paces levels by score: ten runs of 1,000 points reach level 6, of 3,000 points level 10", function()
			for _, case in { { score = 1000, level = 6 }, { score = 3000, level = 10 } } do
				local data = player(0, 1)
				for _ = 1, 10 do
					Progression.addExp(data, Progression.expForScore(case.score))
				end
				t.expect(data.level).toBe(case.level)
			end
		end)

		t.it("claims score and level milestones once each, in rank order", function()
			local data = player(5200, 10)
			t.expect(ids(Progression.claimMilestones(data))).toEqual({ "score1000", "level5", "score5000", "level10" })
			t.expect(ids(Progression.claimMilestones(data))).toEqual({})
			data.level = 20
			t.expect(ids(Progression.claimMilestones(data))).toEqual({ "level20" })
		end)

		t.it("shows the highest ranked title claimed", function()
			local data = player(0, 1)
			t.expect(Progression.title(data.milestonesClaimed)).toBe(nil)
			data.bestScore = 1000
			Progression.claimMilestones(data)
			t.expect(Progression.title(data.milestonesClaimed)).toBe("Block Rookie")
			data.level = 5
			Progression.claimMilestones(data)
			t.expect(Progression.title(data.milestonesClaimed)).toBe("Regular")
		end)

		t.it("gives a milestone added later to players who already reached it", function()
			local data = player(2000, 3)
			Progression.claimMilestones(data)
			withMilestones({
				{ id = "score1000", kind = "score", threshold = 1000, title = "Block Rookie", badgeId = 0 },
				{ id = "level3", kind = "level", threshold = 3, title = "New Title", badgeId = 0 },
			}, function()
				t.expect(ids(Progression.claimMilestones(data))).toEqual({ "level3" })
			end)
		end)

		t.it("owes the badges of claimed milestones until they are awarded", function()
			withMilestones({
				{ id = "a", kind = "score", threshold = 10, title = "A", badgeId = 111 },
				{ id = "b", kind = "score", threshold = 20, title = "B", badgeId = 0 }, -- badge not created yet
				{ id = "c", kind = "score", threshold = 99999, title = "C", badgeId = 333 }, -- not reached
			}, function()
				local data = player(50, 1)
				Progression.claimMilestones(data)
				t.expect(ids(Progression.pendingBadges(data))).toEqual({ "a" })
				data.badgesAwarded.a = true
				t.expect(ids(Progression.pendingBadges(data))).toEqual({})
			end)
		end)

		t.it("ships milestones with unique ids, increasing thresholds per kind and no badges yet", function()
			local seen: { [string]: boolean } = {}
			local last: { [string]: number } = {}
			for _, milestone in Config.MILESTONES do
				t.expect(seen[milestone.id]).toBe(nil)
				seen[milestone.id] = true
				t.expect(milestone.threshold > (last[milestone.kind] or 0)).toBe(true)
				last[milestone.kind] = milestone.threshold
				t.expect(milestone.badgeId >= 0).toBe(true)
			end
			t.expect(#Config.MILESTONES).toBe(9)
		end)
	end)
end
