--!strict
local Leaderboards = require("../src/server/Leaderboards")
local TestKit = require("./TestKit")

local DAY = 86400
local JAN_1_2026 = 1767225600 -- 2026-01-01 00:00 UTC, a Thursday
local NOV_1_2026 = JAN_1_2026 + 304 * DAY -- a Sunday, last day of week 44
local NOV_2_2026 = NOV_1_2026 + DAY -- Monday, week 45 starts

local function stats(
	bestScore: number,
	level: number,
	week: string,
	weekBest: number,
	weekExp: number,
	robuxDonated: number?
): Leaderboards.Stats
	return {
		bestScore = bestScore,
		level = level,
		weekly = { week = week, bestScore = weekBest, exp = weekExp },
		robuxDonated = robuxDonated or 0,
	}
end

return function(t: TestKit.TestKit)
	t.describe("Leaderboards", function()
		t.it("names ISO weeks, which start on Monday, across year ends", function()
			t.expect(Leaderboards.weekKey(JAN_1_2026)).toBe("2026W01")
			t.expect(Leaderboards.weekKey(JAN_1_2026 - 3 * DAY)).toBe("2026W01") -- Monday 2025-12-29
			t.expect(Leaderboards.weekKey(JAN_1_2026 - 4 * DAY)).toBe("2025W52") -- Sunday 2025-12-28
			t.expect(Leaderboards.weekKey(NOV_1_2026 + DAY - 1)).toBe("2026W44") -- Sunday 23:59:59
			t.expect(Leaderboards.weekKey(NOV_2_2026)).toBe("2026W45")
			t.expect(Leaderboards.weekKey(JAN_1_2026 + 365 * DAY)).toBe("2026W53") -- Friday 2027-01-01
		end)

		t.it("puts weekly boards in a store per week and Studio boards in separate stores", function()
			t.expect(Leaderboards.storeName("Highscore_all", NOV_2_2026, false)).toBe("Highscore")
			t.expect(Leaderboards.storeName("Level_week", NOV_2_2026, false)).toBe("Level_2026W45")
			t.expect(Leaderboards.storeName("Highscore_week", NOV_1_2026, true)).toBe("Highscore_2026W44_Dev")
		end)

		t.it("stores the title with the stat without changing the order", function()
			local value = Leaderboards.encode(2094, 3)
			t.expect({ Leaderboards.decode(value) }).toEqual({ 2094, 3 })
			t.expect({ Leaderboards.decode(Leaderboards.encode(5, 0)) }).toEqual({ 5, 0 })
			-- One more point beats the best title.
			t.expect(Leaderboards.encode(2095, 0) > Leaderboards.encode(2094, Leaderboards.TITLE_SLOTS - 1)).toBe(true)
		end)

		t.it("keeps the week's best score and adds up its EXP, starting over each week", function()
			local weekly = { week = "", bestScore = 0, exp = 0 }
			Leaderboards.recordRun(weekly, NOV_1_2026, 400, 40)
			Leaderboards.recordRun(weekly, NOV_1_2026, 300, 30)
			t.expect(weekly).toEqual({ week = "2026W44", bestScore = 400, exp = 70 })
			Leaderboards.recordRun(weekly, NOV_2_2026, 120, 12)
			t.expect(weekly).toEqual({ week = "2026W45", bestScore = 120, exp = 12 })
			Leaderboards.recordRun(weekly, NOV_2_2026, 50, -5)
			t.expect(weekly.exp).toBe(12)
		end)

		t.it("writes only boards where the player has something to show", function()
			t.expect(Leaderboards.values(stats(0, 1, "", 0, 0), 0, NOV_2_2026)).toEqual({})
			t.expect(Leaderboards.values(stats(2094, 5, "2026W45", 900, 90), 2, NOV_2_2026)).toEqual({
				Highscore_all = Leaderboards.encode(2094, 2),
				Level_all = Leaderboards.encode(5, 2),
				Highscore_week = Leaderboards.encode(900, 2),
				Level_week = Leaderboards.encode(90, 2),
			})
			-- Last week's numbers never reach this week's boards.
			t.expect(Leaderboards.values(stats(2094, 5, "2026W44", 900, 90), 2, NOV_2_2026)).toEqual({
				Highscore_all = Leaderboards.encode(2094, 2),
				Level_all = Leaderboards.encode(5, 2),
			})
		end)

		t.it("keeps the Supporters board in its own store, the same in every week", function()
			t.expect(Leaderboards.storeName(Leaderboards.SUPPORTERS_KEY, NOV_2_2026, false)).toBe("RobuxDonated")
			t.expect(Leaderboards.storeName(Leaderboards.SUPPORTERS_KEY, NOV_1_2026, true)).toBe("RobuxDonated_Dev")
		end)

		t.it("writes the Robux donated as they are, only once there is something to show", function()
			t.expect(Leaderboards.values(stats(0, 1, "", 0, 0, 0), 0, NOV_2_2026)).toEqual({})
			t.expect(Leaderboards.values(stats(0, 1, "", 0, 0, 125), 3, NOV_2_2026)).toEqual({
				Supporters_all = 125, -- no title mixed in
			})
			t.expect(Leaderboards.values(stats(2094, 5, "2026W45", 900, 90, 30), 2, NOV_2_2026).Supporters_all).toBe(30)
		end)

		t.it("writes again only what changed", function()
			local written = { Highscore_all = 100, Level_all = 200 }
			local changes = Leaderboards.changes({ Highscore_all = 100, Level_all = 300, Level_week = 5 }, written)
			t.expect(changes).toEqual({ Level_all = 300, Level_week = 5 })
		end)
	end)
end
