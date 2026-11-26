--!strict
local Erasure = require("../src/server/Erasure")
local Leaderboards = require("../src/server/Leaderboards")
local TestKit = require("./TestKit")

local DAY = 86400
local NOV_10_2026 = Erasure.FIRST_WEEK_TIME + 11 * DAY -- 2026-11-10, a Tuesday in week 46

local function has(list: { string }, name: string): boolean
	return table.find(list, name) ~= nil
end

return function(t: TestKit.TestKit)
	t.describe("Erasure", function()
		t.it("starts the weekly stores on the day the project began", function()
			t.expect(os.date("!%Y-%m-%d", Erasure.FIRST_WEEK_TIME)).toBe("2026-10-30")
		end)

		t.it("keys the profile the way DataService does", function()
			t.expect(Erasure.profileKey(1234)).toBe("User_1234")
		end)

		t.it("accepts only whole-digit user ids as messages", function()
			t.expect(Erasure.parseUserId("123456789")).toBe(123456789)
			t.expect(Erasure.parseUserId("0")).toBe(nil)
			t.expect(Erasure.parseUserId("")).toBe(nil)
			t.expect(Erasure.parseUserId("-5")).toBe(nil)
			t.expect(Erasure.parseUserId("12.5")).toBe(nil)
			t.expect(Erasure.parseUserId("1e5")).toBe(nil)
			t.expect(Erasure.parseUserId(" 7")).toBe(nil)
			t.expect(Erasure.parseUserId("12345678901234")).toBe(nil) -- too long to be an id
			t.expect(Erasure.parseUserId(42)).toBe(nil)
			t.expect(Erasure.parseUserId(nil)).toBe(nil)
		end)

		t.it("lists every leaderboard store that exists, with a weekly store for each week since the start", function()
			local names = Erasure.orderedStoreNames(NOV_10_2026)
			for _, expected in { "Highscore", "Level", "RobuxDonated" } do
				t.expect(has(names, expected)).toBe(true)
			end
			-- 2026-10-30 is a Friday of week 44; week 46 is the current one.
			for _, week in { "2026W44", "2026W45", "2026W46" } do
				t.expect(has(names, `Highscore_{week}`)).toBe(true)
				t.expect(has(names, `Level_{week}`)).toBe(true)
			end
			t.expect(has(names, "Highscore_2026W43")).toBe(false)
			t.expect(has(names, "Highscore_2026W47")).toBe(false)
			-- Plus one Rank store per season since ranked began (November 2026), after all the others.
			t.expect(names[#names]).toBe("Rank_2026M11")
			t.expect(has(names, "Rank_all")).toBe(true)
			t.expect(#names).toBe(3 + 2 * 3 + 2)
		end)

		t.it(
			"lists a Rank store for every season since the first, in order, without moving the older stores",
			function()
				local before = Erasure.orderedStoreNames(NOV_10_2026)
				local later = Erasure.orderedStoreNames(NOV_10_2026 + 100 * DAY) -- February 2027
				local ranks = {}
				for _, name in later do
					if string.sub(name, 1, 5) == "Rank_" then
						table.insert(ranks, name)
					end
				end
				t.expect(ranks).toEqual({ "Rank_all", "Rank_2026M11", "Rank_2026M12", "Rank_2027M01", "Rank_2027M02" })
				for index, name in before do
					if string.sub(name, 1, 5) ~= "Rank_" then
						t.expect(later[index]).toBe(name)
					end
				end
			end
		)

		t.it("lists no store twice and none of Studio's", function()
			local names = Erasure.orderedStoreNames(Erasure.FIRST_WEEK_TIME + 400 * DAY)
			local seen: { [string]: boolean } = {}
			for _, name in names do
				t.expect(seen[name]).toBe(nil)
				seen[name] = true
				t.expect(string.find(name, "_Dev", 1, true)).toBe(nil)
			end
		end)

		t.it("names exactly the stores the boards write to", function()
			local names = Erasure.orderedStoreNames(NOV_10_2026)
			for _, key in
				{
					"Highscore_all",
					"Highscore_week",
					"Level_all",
					"Level_week",
					Leaderboards.SUPPORTERS_KEY,
					Leaderboards.RANK_KEY,
				}
			do
				t.expect(has(names, Leaderboards.storeName(key, NOV_10_2026, false))).toBe(true)
			end
		end)

		t.it("finds the Co-op rows of a user by whole ids, never by a prefix or a suffix", function()
			t.expect(Erasure.pairKeyMatches("12_45", 12)).toBe(true)
			t.expect(Erasure.pairKeyMatches("12_45", 45)).toBe(true)
			t.expect(Erasure.pairKeyMatches("5_12", 12)).toBe(true)
			t.expect(Erasure.pairKeyMatches("123_45", 12)).toBe(false)
			t.expect(Erasure.pairKeyMatches("45_312", 12)).toBe(false)
			t.expect(Erasure.pairKeyMatches("112_12345", 12)).toBe(false)
			t.expect(Erasure.pairKeyMatches("12", 12)).toBe(false) -- not a pair
			t.expect(Erasure.pairKeyMatches("12_45_7", 12)).toBe(false)
			t.expect(Erasure.pairKeyMatches("Highscore", 12)).toBe(false)
			t.expect(Erasure.pairKeyMatches("", 12)).toBe(false)
		end)

		t.it("picks the Co-op rows to delete out of a page of the store", function()
			local keys = { "12_45", "123_45", "45_312", "7_12", "100_200", "bad" }
			t.expect(Erasure.pairKeysFor(keys, 12)).toEqual({ "12_45", "7_12" })
			t.expect(Erasure.pairKeysFor(keys, 45)).toEqual({ "12_45", "123_45", "45_312" })
			t.expect(Erasure.pairKeysFor(keys, 999)).toEqual({})
			t.expect(Erasure.pairKeysFor({}, 12)).toEqual({})
		end)

		t.it("leaves the Co-op store out of the per-id plan, which the script scans instead", function()
			t.expect(Erasure.COOP_STORE).toBe("Coop")
			t.expect(has(Erasure.orderedStoreNames(NOV_10_2026), Erasure.COOP_STORE)).toBe(false)
			t.expect(Erasure.COOP_STORE).toBe(Leaderboards.storeName(Leaderboards.COOP_KEY, NOV_10_2026, false))
			t.expect(Erasure.plan(12, NOV_10_2026).orderedStores[1].store ~= Erasure.COOP_STORE).toBe(true)
		end)

		t.it("plans the profile and one entry per leaderboard store for the user", function()
			local plan = Erasure.plan(555, NOV_10_2026)
			t.expect(plan.dataStores).toEqual({ { store = "PlayerData", key = "User_555" } })
			t.expect(#plan.orderedStores).toBe(#Erasure.orderedStoreNames(NOV_10_2026))
			for _, target in plan.orderedStores do
				t.expect(target.key).toBe("555")
			end
		end)
	end)
end
