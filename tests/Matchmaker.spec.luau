--!strict
local Config = require("../src/shared/Config")
local Matchmaker = require("../src/server/Matchmaker")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local QUEUE = Config.PVP.QUEUE

local function harness(): (Matchmaker.Matchmaker, { now: number })
	local clock = { now = 0 }
	local queue = Matchmaker.new({
		clock = function(): number
			return clock.now
		end,
		settings = QUEUE,
	})
	return queue, clock
end

local function names(pairs: { { any } }): { string }
	local out = {}
	for _, pair in pairs do
		table.insert(out, `{pair[1]}+{pair[2]}`)
	end
	return out
end

return function(t: TestKit.TestKit)
	t.describe("Matchmaker", function()
		t.it("widens each player's window as they wait, up to the maximum", function()
			local queue, clock = harness()
			queue:enqueue("A", 1000)
			t.expect(queue:window("A")).toBe(QUEUE.WINDOW_BASE)
			clock.now = 5
			t.expect(queue:window("A")).toBe(QUEUE.WINDOW_BASE + 5 * QUEUE.WINDOW_PER_SECOND)
			clock.now = 1000
			t.expect(queue:window("A")).toBe(QUEUE.WINDOW_MAX)
		end)

		t.it("matches two players only when each is within the other's window", function()
			local queue, clock = harness()
			queue:enqueue("A", 1000)
			clock.now = 10 -- A accepts 300 points now
			queue:enqueue("B", 1250) -- B only 100
			t.expect(queue:tick()).toEqual({})
			clock.now = 18 -- B accepts 260
			t.expect(names(queue:tick())).toEqual({ "A+B" })
			t.expect(queue:isQueued("A")).toBe(false)
			t.expect(queue:isQueued("B")).toBe(false)
		end)

		t.it("never matches beyond the maximum window", function()
			local queue, clock = harness()
			queue:enqueue("A", 1000)
			queue:enqueue("B", 1000 + QUEUE.WINDOW_MAX + 1)
			clock.now = 10000
			t.expect(queue:tick()).toEqual({})
		end)

		t.it("serves the longest waiting first, with the longest waiting who fits", function()
			local queue, clock = harness()
			queue:enqueue("A", 1000)
			clock.now = 1
			queue:enqueue("B", 1050)
			clock.now = 2
			queue:enqueue("C", 1040)
			clock.now = 3
			queue:enqueue("D", 1300)
			t.expect(names(queue:tick())).toEqual({ "A+B" })
			t.expect(queue:isQueued("C")).toBe(true)
			t.expect(queue:isQueued("D")).toBe(true)
		end)

		t.it("prefers someone the player hasn't just played", function()
			local queue, clock = harness()
			queue:enqueue("A", 1000)
			queue:enqueue("B", 1000)
			t.expect(names(queue:tick())).toEqual({ "A+B" })
			queue:enqueue("A", 1000)
			queue:enqueue("B", 1000)
			queue:enqueue("C", 1000)
			t.expect(names(queue:tick())).toEqual({ "A+C" })
			t.expect(queue:isQueued("B")).toBe(true)
			-- With nobody else, they are matched again anyway.
			queue:enqueue("A", 1000)
			t.expect(names(queue:tick())).toEqual({ "B+A" })
			clock.now = QUEUE.RECENT_SECONDS + 1
			t.expect(queue:footprint()).toBe(4) -- A-B and A-C, both ways
			queue:tick()
			t.expect(queue:footprint()).toBe(0) -- old meetings are forgotten
		end)

		t.it("lets players cancel, refuses a second entry and forgets those who leave", function()
			local queue = harness()
			t.expect(queue:enqueue("A", 1000)).toBe(true)
			t.expect(queue:enqueue("A", 1200)).toBe(false)
			t.expect(queue:cancel("A")).toBe(true)
			t.expect(queue:cancel("A")).toBe(false)
			t.expect(queue:waited("A")).toBe(nil)
			queue:enqueue("A", 1000)
			queue:enqueue("B", 1000)
			queue:tick()
			queue:remove("A")
			queue:remove("B")
			t.expect(queue:footprint()).toBe(0)
		end)

		t.it("keeps its invariants over 300 random actions", function()
			local queue, clock = harness()
			local rng = Rng.new(27)
			local players = { "A", "B", "C", "D", "E", "F" }
			local ratings: { [string]: number } = {}
			for _ = 1, 300 do
				local who = players[rng:nextInt(1, #players)]
				local action = rng:nextInt(1, 10)
				if action <= 4 then
					local rating = 800 + rng:nextInt(0, 800)
					if queue:enqueue(who, rating) then
						ratings[who] = rating
					end
				elseif action == 5 then
					queue:cancel(who)
				elseif action == 6 then
					queue:remove(who)
				elseif action <= 8 then
					clock.now += rng:nextInt(1, 30)
				else
					for _, pair in queue:tick() do
						t.expect(pair[1] ~= pair[2]).toBe(true)
						t.expect(queue:isQueued(pair[1]) or queue:isQueued(pair[2])).toBe(false)
						t.expect(math.abs(ratings[pair[1]] - ratings[pair[2]]) <= QUEUE.WINDOW_MAX).toBe(true)
					end
				end
				local count = 0
				for _, name in players do
					if queue:isQueued(name) then
						count += 1
					end
				end
				t.expect(queue:count()).toBe(count)
			end
			for _, name in players do
				queue:remove(name)
			end
			t.expect(queue:footprint()).toBe(0)
		end)
	end)
end
