--!strict
-- Token bucket per key: up to `capacity` actions in a burst, refilling at capacity / windowSeconds per second.
-- The clock is passed in so tests can control time.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { tokens: number, last: number }

export type RateLimiter = typeof(setmetatable(
	{} :: {
		capacity: number,
		refillPerSecond: number,
		clock: () -> number,
		buckets: { [any]: Bucket },
	},
	RateLimiter
))

function RateLimiter.new(capacity: number, windowSeconds: number, clock: () -> number): RateLimiter
	return setmetatable({
		capacity = capacity,
		refillPerSecond = capacity / windowSeconds,
		clock = clock,
		buckets = {},
	}, RateLimiter)
end

-- Spends one token for `key`; false when none are left.
function RateLimiter.allow(self: RateLimiter, key: any): boolean
	local now = self.clock()
	local bucket = self.buckets[key]
	if bucket then
		bucket.tokens = math.min(self.capacity, bucket.tokens + (now - bucket.last) * self.refillPerSecond)
		bucket.last = now
	else
		bucket = { tokens = self.capacity, last = now }
		self.buckets[key] = bucket
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

-- Drops the key's bucket (call when a player leaves so Player keys don't leak).
function RateLimiter.forget(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
