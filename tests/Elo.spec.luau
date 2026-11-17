--!strict
local Config = require("../src/shared/Config")
local Elo = require("../src/server/Elo")
local TestKit = require("./TestKit")

local RATING = Config.PVP.RATING
local AFTER_PLACEMENT = RATING.PLACEMENT_GAMES -- ranked games played once placement is over

return function(t: TestKit.TestKit)
	t.describe("Elo", function()
		local elo = Elo.new(RATING)

		t.it("gives equal players half of K for a win or a loss and nothing for a draw", function()
			t.expect(elo:stakes(1000, 1000, AFTER_PLACEMENT)).toEqual({ win = 12, draw = 0, loss = -12 })
			t.expect(elo:stakes(1000, 1000, 0)).toEqual({ win = 20, draw = 0, loss = -20 })
		end)

		t.it("expects 10 to 1 across a 400 point gap", function()
			t.expect(math.abs(elo:expected(1400, 1000) - 10 / 11) < 1e-12).toBe(true)
			-- K 24: the favourite gains round(2.18) or loses round(21.8); the underdog the other way round.
			t.expect(elo:stakes(1400, 1000, AFTER_PLACEMENT)).toEqual({ win = 2, draw = -10, loss = -22 })
			t.expect(elo:stakes(1000, 1400, AFTER_PLACEMENT)).toEqual({ win = 22, draw = 10, loss = -2 })
		end)

		t.it("uses the placement K for the first games, then K, then the high K from K_HIGH_FROM", function()
			t.expect(elo:kFactor(1000, 0)).toBe(RATING.K_PLACEMENT)
			t.expect(elo:kFactor(1000, AFTER_PLACEMENT - 1)).toBe(RATING.K_PLACEMENT)
			t.expect(elo:kFactor(RATING.K_HIGH_FROM + 100, AFTER_PLACEMENT - 1)).toBe(RATING.K_PLACEMENT)
			t.expect(elo:kFactor(1000, AFTER_PLACEMENT)).toBe(RATING.K)
			t.expect(elo:kFactor(RATING.K_HIGH_FROM - 1, AFTER_PLACEMENT)).toBe(RATING.K)
			t.expect(elo:kFactor(RATING.K_HIGH_FROM, AFTER_PLACEMENT)).toBe(RATING.K_HIGH)
		end)

		t.it("rounds halves away from zero", function()
			local settings = table.clone(RATING) :: any
			settings.K = 25
			local odd = Elo.new(settings)
			t.expect(odd:stakes(1000, 1000, AFTER_PLACEMENT)).toEqual({ win = 13, draw = 0, loss = -13 })
		end)

		t.it("never takes a player below the floor", function()
			local stakes = elo:stakes(RATING.FLOOR + 5, RATING.FLOOR + 5, AFTER_PLACEMENT)
			t.expect(stakes.loss).toBe(-5)
			t.expect(elo:stakes(RATING.FLOOR, 2000, AFTER_PLACEMENT).loss).toBe(0)
		end)

		t.it("takes from the loser what the winner gains when both use the same K", function()
			for a = 600, 2200, 137 do
				for b = 600, 2200, 211 do
					local k = 24
					t.expect(elo:change(a, b, k, 1) + elo:change(b, a, k, 0)).toBe(0)
					t.expect(elo:change(a, b, k, 0.5) + elo:change(b, a, k, 0.5)).toBe(0)
				end
			end
		end)
	end)
end
