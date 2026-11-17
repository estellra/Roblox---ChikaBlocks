--!strict
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

return function(t: TestKit.TestKit)
	t.describe("Rng", function()
		t.it("repeats the same sequence for the same seed", function()
			local a, b = Rng.new(42), Rng.new(42)
			for _ = 1, 100 do
				t.expect(a:nextUInt32()).toBe(b:nextUInt32())
			end
		end)

		t.it("matches the sequence Roblox Studio produces for seed 42", function()
			-- Recorded from Studio; the server and clients must agree with Lune.
			local rng = Rng.new(42)
			t.expect(rng:nextUInt32()).toBe(3120216979)
			t.expect(rng:nextUInt32()).toBe(1067267639)
			t.expect(rng:nextUInt32()).toBe(2989017562)
		end)

		t.it("gives different sequences for neighbouring seeds", function()
			local a, b = Rng.new(1), Rng.new(2)
			local same = 0
			for _ = 1, 100 do
				if a:nextUInt32() == b:nextUInt32() then
					same += 1
				end
			end
			t.expect(same).toBe(0)
		end)

		t.it("works with zero, negative and fractional seeds", function()
			for _, seed in { 0, -1, -123456, 3.75 } do
				local value = Rng.new(seed):nextUInt32()
				t.expect(value >= 1 and value < 2 ^ 32).toBe(true)
			end
		end)

		t.it("keeps nextFloat in [0, 1)", function()
			local rng = Rng.new(99)
			for _ = 1, 10000 do
				local value = rng:nextFloat()
				t.expect(value >= 0 and value < 1).toBe(true)
			end
		end)

		t.it("keeps nextInt in bounds and spreads values evenly", function()
			local rng = Rng.new(7)
			local counts = { 0, 0, 0, 0, 0, 0 }
			local draws = 6000
			for _ = 1, draws do
				local value = rng:nextInt(1, 6)
				t.expect(value >= 1 and value <= 6 and value == math.floor(value)).toBe(true)
				counts[value] += 1
			end
			for _, count in counts do
				-- Each face expects 1000; allow 15% either way.
				t.expect(count > 850 and count < 1150).toBe(true)
			end
		end)

		t.describe("mix", function()
			t.it("gives the same seed for the same inputs", function()
				t.expect(Rng.mix(42, "set", 3)).toBe(Rng.mix(42, "set", 3))
				t.expect(Rng.mix(42)).toBe(Rng.mix(42))
			end)

			t.it("gives different seeds when any input changes", function()
				local seen: { [number]: boolean } = {}
				local count = 0
				local function add(value: number)
					t.expect(value >= 0 and value < 2 ^ 32 and value == math.floor(value)).toBe(true)
					t.expect(seen[value]).toBe(nil)
					seen[value] = true
					count += 1
				end
				for seed = 1, 20 do
					add(Rng.mix(seed))
					for k = 1, 20 do
						add(Rng.mix(seed, "set", k))
						add(Rng.mix(seed, "stuck", 1, k))
						add(Rng.mix(seed, "stuck", 2, k))
					end
					add(Rng.mix(seed, "garbage", 1))
					add(Rng.mix(seed, "garbage", 2))
				end
				t.expect(count).toBe(20 * 63)
			end)

			t.it("feeds streams that start differently", function()
				local a = Rng.new(Rng.mix(7, "set", 1))
				local b = Rng.new(Rng.mix(7, "set", 2))
				t.expect(a:nextUInt32() ~= b:nextUInt32()).toBe(true)
			end)
		end)
	end)
end
