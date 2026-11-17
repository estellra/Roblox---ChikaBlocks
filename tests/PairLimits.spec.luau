--!strict
local PairLimits = require("../src/server/PairLimits")
local TestKit = require("./TestKit")

local DAY = 24 * 60 * 60
local LIMIT = 2

type Harness = {
	limits: PairLimits.PairLimits,
	clock: { now: number },
	data: { [string]: PairLimits.Record },
	broken: { on: boolean },
	errors: { string },
}

-- A store that keeps records in a table, and can be made to fail.
local function harness(): Harness
	local clock = { now = 1_800_000_000 }
	local data: { [string]: PairLimits.Record } = {}
	local broken = { on = false }
	local errors: { string } = {}
	local limits = PairLimits.new({
		store = {
			get = function(key: string): (boolean, PairLimits.Record?)
				if broken.on then
					return false, nil
				end
				return true, data[key]
			end,
			update = function(key: string, transform: (PairLimits.Record?) -> PairLimits.Record, _ttl: number): boolean
				if broken.on then
					return false
				end
				data[key] = transform(data[key])
				return true
			end,
		},
		clock = function(): number
			return clock.now
		end,
		limit = LIMIT,
		windowSeconds = DAY,
		onStoreError = function(what: string)
			table.insert(errors, what)
		end,
	})
	return { limits = limits, clock = clock, data = data, broken = broken, errors = errors }
end

return function(t: TestKit.TestKit)
	t.describe("PairLimits", function()
		t.it("keys a pair the same way whichever order it comes in", function()
			t.expect(PairLimits.pairKey(20, 3)).toBe("3_20")
			t.expect(PairLimits.pairKey(3, 20)).toBe("3_20")
			t.expect(PairLimits.pairKey(-5, 7)).toBe("-5_7")
		end)

		t.it("rates a pair's first two matches in a day, then not the third", function()
			local h = harness()
			t.expect(h.limits:isRated(1, 2)).toBe(true)
			h.limits:record(1, 2)
			t.expect(h.limits:isRated(2, 1)).toBe(true)
			h.limits:record(2, 1)
			t.expect(h.limits:isRated(1, 2)).toBe(false)
			t.expect(h.limits:isRated(1, 3)).toBe(true) -- other pairs are not affected
		end)

		t.it("rates the pair again once the day since its first match is over", function()
			local h = harness()
			h.limits:record(1, 2)
			h.limits:record(1, 2)
			h.clock.now += DAY - 1
			t.expect(h.limits:isRated(1, 2)).toBe(false)
			h.clock.now += 1
			t.expect(h.limits:isRated(1, 2)).toBe(true)
			h.limits:record(1, 2)
			t.expect(h.data["1_2"]).toEqual({ n = 1, since = h.clock.now })
		end)

		t.it("counts in the server when the store fails, and says so", function()
			local h = harness()
			h.broken.on = true
			h.limits:record(1, 2)
			h.limits:record(1, 2)
			t.expect(h.limits:isRated(1, 2)).toBe(false)
			t.expect(h.errors).toEqual({ "update", "update", "get" })
			h.clock.now += DAY
			h.limits:sweep()
			t.expect(h.limits:isRated(1, 2)).toBe(true)
		end)
	end)
end
