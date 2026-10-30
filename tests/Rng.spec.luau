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
	end)
end
