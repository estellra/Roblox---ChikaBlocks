--!strict
local Config = require("../src/shared/Config")
local PlayerData = require("../src/server/PlayerData")
local PvpRating = require("../src/server/PvpRating")
local TestKit = require("./TestKit")

local RATING = Config.PVP.RATING
local NOW = 1796083200

-- A new player's rank data, copied deeply as ProfileStore does.
local function fresh(): PlayerData.PvpData
	local pvp = table.clone(PlayerData.TEMPLATE.pvp) :: any
	pvp.medals = {}
	return pvp
end

return function(t: TestKit.TestKit)
	t.describe("PvpRating", function()
		local rating = PvpRating.new(RATING, Config.PVP.TIERS)

		t.describe("matches", function()
			t.it("writes the three possible changes when a match opens", function()
				local pvp = fresh()
				local pending = rating:open(pvp, "m1", 1000, NOW)
				t.expect(pending).toEqual({ id = "m1", win = 20, draw = 0, loss = -20, at = NOW })
				t.expect(pvp.pending).toEqual(pending)
				t.expect(pvp.rating).toBe(1000)
			end)

			t.it("applies a win, a draw and a loss and counts each", function()
				local pvp = fresh()
				rating:open(pvp, "m1", 1000, NOW)
				t.expect(rating:close(pvp, "m1", "win")).toBe(20)
				t.expect(pvp.rating).toBe(1020)
				t.expect(pvp.peak).toBe(1020)
				rating:open(pvp, "m2", 1020, NOW)
				t.expect(rating:close(pvp, "m2", "draw")).toBe(0)
				rating:open(pvp, "m3", 1020, NOW)
				t.expect(rating:close(pvp, "m3", "loss")).toBe(-20)
				t.expect(pvp.rating).toBe(1000)
				t.expect(pvp.peak).toBe(1020) -- the peak stays at the season's highest
				t.expect(pvp.games).toBe(3)
				t.expect(pvp.seasonGames).toBe(3)
				t.expect({ pvp.wins, pvp.draws, pvp.losses }).toEqual({ 1, 1, 1 })
				t.expect(pvp.pending).toBe(false)
			end)

			t.it("refuses to open a second match while one is pending", function()
				local pvp = fresh()
				rating:open(pvp, "m1", 1000, NOW)
				t.expect(rating:open(pvp, "m2", 1500, NOW)).toBe(nil)
				t.expect((pvp.pending :: any).id).toBe("m1")
			end)

			t.it("never settles the same match twice", function()
				local pvp = fresh()
				rating:open(pvp, "m1", 1000, NOW)
				rating:close(pvp, "m1", "win")
				t.expect(rating:close(pvp, "m1", "win")).toBe(nil)
				t.expect(rating:forfeit(pvp, "m1")).toBe(nil)
				t.expect(pvp.rating).toBe(1020)
				t.expect(pvp.games).toBe(1)
			end)

			t.it("changes nothing for an unrated match or another match's id", function()
				local pvp = fresh()
				local before = table.clone(pvp)
				t.expect(rating:close(pvp, "unrated", "win")).toBe(nil)
				t.expect(pvp).toEqual(before)
				rating:open(pvp, "m1", 1000, NOW)
				t.expect(rating:close(pvp, "m2", "win")).toBe(nil)
				t.expect(pvp.rating).toBe(1000)
				t.expect(pvp.pending ~= false).toBe(true)
			end)

			t.it("counts leaving as a loss", function()
				local pvp = fresh()
				rating:open(pvp, "m1", 1000, NOW)
				t.expect(rating:forfeit(pvp, "m1")).toBe(-20)
				t.expect(pvp.losses).toBe(1)
				t.expect(pvp.pending).toBe(false)
			end)

			t.it("voids a cancelled match without changing anything else", function()
				local pvp = fresh()
				local before = table.clone(pvp)
				rating:open(pvp, "m1", 1000, NOW)
				t.expect(rating:void(pvp, "m2")).toBe(false)
				t.expect(rating:void(pvp, "m1")).toBe(true)
				t.expect(pvp).toEqual(before)
				t.expect(rating:void(pvp, "m1")).toBe(false)
			end)

			t.it("settles a match left pending in saved data as a loss the next time it loads", function()
				local pvp = fresh()
				t.expect(rating:settleStale(pvp)).toBe(nil)
				rating:open(pvp, "m1", 1000, NOW)
				t.expect(rating:settleStale(pvp)).toBe(-20)
				t.expect(pvp.rating).toBe(980)
				t.expect(pvp.losses).toBe(1)
				t.expect(rating:settleStale(pvp)).toBe(nil)
			end)

			t.it("keeps the changes written at the start", function()
				local pvp = fresh()
				rating:open(pvp, "m1", 1400, NOW)
				local pending = pvp.pending :: PlayerData.PvpPending
				t.expect(rating:close(pvp, "m1", "win")).toBe(pending.win)
			end)
		end)

		t.describe("seasons", function()
			t.it("gives data that never played ranked the season id without a pull", function()
				local pvp = fresh()
				t.expect(rating:rollSeason(pvp, "2026M12")).toBe(true)
				t.expect(pvp.season).toBe("2026M12")
				t.expect(pvp.rating).toBe(1000)
				t.expect(pvp.lastSeason).toBe(false)
			end)

			t.it("rolls over once: records the season, gives its medal and pulls points halfway back", function()
				local pvp = fresh()
				rating:rollSeason(pvp, "2026M12")
				pvp.rating, pvp.peak, pvp.seasonGames, pvp.games = 1300, 1450, 5, 9
				t.expect(rating:rollSeason(pvp, "2027M01")).toBe(true)
				t.expect(pvp.lastSeason)
					.toEqual({ id = "2026M12", rating = 1300, peak = 1450, games = 5, tier = "Platinum" })
				t.expect(pvp.medals).toEqual({ ["2026M12"] = { tier = "Platinum" } })
				t.expect(pvp.rating).toBe(1150)
				t.expect(pvp.peak).toBe(1150)
				t.expect(pvp.seasonGames).toBe(0)
				t.expect(pvp.games).toBe(9) -- all-time counts stay
				t.expect(pvp.season).toBe("2027M01")
				t.expect(rating:rollSeason(pvp, "2027M01")).toBe(false)
				t.expect(pvp.rating).toBe(1150)
			end)

			t.it("ignores an earlier season id from a server whose clock is behind", function()
				local pvp = fresh()
				rating:rollSeason(pvp, "2027M01")
				pvp.rating = 1300
				t.expect(rating:rollSeason(pvp, "2026M12")).toBe(false)
				t.expect(pvp.season).toBe("2027M01")
				t.expect(pvp.rating).toBe(1300)
			end)

			t.it("pulls low points up too, and pulls once across several skipped months", function()
				local pvp = fresh()
				rating:rollSeason(pvp, "2026M12")
				pvp.rating, pvp.peak = 801, 1000
				t.expect(rating:rollSeason(pvp, "2027M05")).toBe(true)
				t.expect(pvp.rating).toBe(900) -- 1000 + round(-99.5)
				t.expect((pvp.lastSeason :: any).id).toBe("2026M12")
			end)

			t.it("gives no medal for a season without enough ranked games", function()
				local pvp = fresh()
				rating:rollSeason(pvp, "2026M12")
				pvp.seasonGames = RATING.MEDAL_MIN_GAMES - 1
				rating:rollSeason(pvp, "2027M01")
				t.expect(pvp.medals["2026M12"]).toBe(nil)
				t.expect((pvp.lastSeason :: any).games).toBe(RATING.MEDAL_MIN_GAMES - 1)
			end)

			t.it("tells the tier from the points", function()
				local pvp = fresh()
				t.expect(rating:tier(pvp)).toBe("Silver")
				pvp.rating = 1250
				t.expect(rating:tier(pvp)).toBe("Gold")
			end)
		end)
	end)
end
