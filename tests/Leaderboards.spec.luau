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

		t.it("keys a Co-op row by the two user ids, the smaller first, whichever way round", function()
			t.expect(Leaderboards.pairKey(45, 12)).toBe("12_45")
			t.expect(Leaderboards.pairKey(12, 45)).toBe("12_45")
			t.expect(Leaderboards.pairKey(7, 7)).toBe("7_7")
			-- Studio's test players have negative ids.
			t.expect(Leaderboards.pairKey(-1, -2)).toBe("-2_-1")
			-- The biggest ids a player can have make a key well under the 50 characters a key may have.
			t.expect(#Leaderboards.pairKey(9999999999999, 9999999999998) <= 27).toBe(true)
		end)

		t.it("splits a Co-op row back into its two ids, and refuses a key that isn't one", function()
			t.expect(Leaderboards.pairIds("12_45")).toEqual({ low = 12, high = 45 })
			t.expect(Leaderboards.pairIds("-2_-1")).toEqual({ low = -2, high = -1 })
			t.expect(Leaderboards.pairIds(Leaderboards.pairKey(11894223600, 5)))
				.toEqual({ low = 5, high = 11894223600 })
			for _, bad in { "", "12", "12_", "_45", "12_45_7", "a_b", "12.5_3", "1e5_2", " 1_2" } do
				t.expect(Leaderboards.pairIds(bad)).toBe(nil)
			end
		end)

		t.it(
			"keeps the Co-op board in its own store, the same in every week, apart from the per-player boards",
			function()
				t.expect(Leaderboards.COOP_KEY).toBe("Coop_all")
				t.expect(Leaderboards.storeName(Leaderboards.COOP_KEY, NOV_2_2026, false)).toBe("Coop")
				t.expect(Leaderboards.storeName(Leaderboards.COOP_KEY, NOV_1_2026, true)).toBe("Coop_Dev")
				t.expect(table.find(Leaderboards.BOARDS, "Coop")).toBe(nil)
				-- A player's own values never include a Co-op row: those are written for the pair.
				local values = Leaderboards.values(stats(1000, 3, "", 0, 0), 0, NOV_2_2026)
				t.expect(values[Leaderboards.COOP_KEY]).toBe(nil)
			end
		)

		t.it("puts the Rank board in a store per season", function()
			t.expect(Leaderboards.storeName(Leaderboards.RANK_KEY, 1796083200, false)).toBe("Rank_2026M12")
			t.expect(Leaderboards.storeName(Leaderboards.RANK_KEY, 1796083200, true)).toBe("Rank_2026M12_Dev")
		end)

		t.it("writes a player's rank points once they have played enough ranked games this season", function()
			local time = 1796083200 -- December 2026
			local stats: any = {
				bestScore = 0,
				level = 1,
				weekly = { week = "", bestScore = 0, exp = 0 },
				robuxDonated = 0,
				pvp = { rating = 1320, season = "2026M12", seasonGames = 4 },
			}
			t.expect(Leaderboards.values(stats, 2, time, 5)[Leaderboards.RANK_KEY]).toBe(nil)
			stats.pvp.seasonGames = 5
			t.expect(Leaderboards.values(stats, 2, time, 5)[Leaderboards.RANK_KEY]).toBe(Leaderboards.encode(1320, 2))
			-- Points from another season don't belong on this season's board.
			stats.pvp.season = "2026M11"
			t.expect(Leaderboards.values(stats, 2, time, 5)[Leaderboards.RANK_KEY]).toBe(nil)
			-- Without the minimum (callers that don't write ranks), no Rank value.
			stats.pvp.season = "2026M12"
			t.expect(Leaderboards.values(stats, 2, time)[Leaderboards.RANK_KEY]).toBe(nil)
		end)

		t.it("keeps one all-time Rank board with seasons off", function()
			local time = 1796083200
			t.expect(Leaderboards.storeName(Leaderboards.RANK_KEY, time, false, false)).toBe("Rank_all")
			t.expect(Leaderboards.storeName(Leaderboards.RANK_KEY, time, true, false)).toBe("Rank_all_Dev")
			local stats: any = {
				bestScore = 0,
				level = 1,
				weekly = { week = "", bestScore = 0, exp = 0 },
				robuxDonated = 0,
				pvp = { rating = 1320, season = "", seasonGames = 0, games = 4 },
			}
			t.expect(Leaderboards.values(stats, 2, time, 5, false)[Leaderboards.RANK_KEY]).toBe(nil)
			stats.pvp.games = 5
			local value = Leaderboards.values(stats, 2, time, 5, false)[Leaderboards.RANK_KEY]
			t.expect(value).toBe(Leaderboards.encode(1320, 2))
		end)

		t.it("writes again only what changed", function()
			local written = { Highscore_all = 100, Level_all = 200 }
			local changes = Leaderboards.changes({ Highscore_all = 100, Level_all = 300, Level_week = 5 }, written)
			t.expect(changes).toEqual({ Level_all = 300, Level_week = 5 })
		end)
	end)
end
