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
			t.expect(#names).toBe(3 + 2 * 3)
		end)

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
			for _, key in { "Highscore_all", "Highscore_week", "Level_all", "Level_week", Leaderboards.SUPPORTERS_KEY } do
				t.expect(has(names, Leaderboards.storeName(key, NOV_10_2026, false))).toBe(true)
			end
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
