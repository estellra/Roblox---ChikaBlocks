--!strict
local RateLimiter = require("../src/server/Util/RateLimiter")
local TestKit = require("./TestKit")
local Validate = require("../src/server/Util/Validate")

return function(t: TestKit.TestKit)
	t.describe("Validate", function()
		t.it("accepts numbers in range and rejects everything else", function()
			t.expect(Validate.number(3, 0, 5)).toBe(3)
			t.expect(Validate.number(6, 0, 5)).toBe(nil)
			t.expect(Validate.number(0 / 0, 0, 5)).toBe(nil)
			t.expect(Validate.number(math.huge, 0, 5)).toBe(nil)
			t.expect(Validate.number("3", 0, 5)).toBe(nil)
			t.expect(Validate.number(nil, 0, 5)).toBe(nil)
			t.expect(Validate.number({}, 0, 5)).toBe(nil)
		end)

		t.it("accepts only whole numbers as integers", function()
			t.expect(Validate.integer(4, 0, 5)).toBe(4)
			t.expect(Validate.integer(4.5, 0, 5)).toBe(nil)
			t.expect(Validate.integer(-1, 0, 5)).toBe(nil)
		end)
	end)

	t.describe("RateLimiter", function()
		t.it("allows a burst, then refills over time", function()
			local now = 0
			local limiter = RateLimiter.new(3, 1, function()
				return now
			end)
			t.expect(limiter:allow("a")).toBe(true)
			t.expect(limiter:allow("a")).toBe(true)
			t.expect(limiter:allow("a")).toBe(true)
			t.expect(limiter:allow("a")).toBe(false)
			t.expect(limiter:allow("b")).toBe(true) -- keys are independent
			now += 1 / 3
			t.expect(limiter:allow("a")).toBe(true)
			t.expect(limiter:allow("a")).toBe(false)
			now += 10
			for _ = 1, 3 do
				t.expect(limiter:allow("a")).toBe(true) -- refills only up to capacity
			end
			t.expect(limiter:allow("a")).toBe(false)
		end)

		t.it("forgets a key", function()
			local limiter = RateLimiter.new(1, 1, function()
				return 0
			end)
			limiter:allow("a")
			t.expect(limiter:allow("a")).toBe(false)
			limiter:forget("a")
			t.expect(limiter:allow("a")).toBe(true)
		end)
	end)
end
