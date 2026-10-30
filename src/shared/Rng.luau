--!strict
-- Seeded xorshift32. Pure Luau so the server, the client and Lune tests all get the same sequence
-- for the same seed (Roblox's Random isn't available outside Roblox).

local UINT32_RANGE = 2 ^ 32
local FALLBACK_STATE = 0x9E3779B9 -- xorshift gets stuck at 0, so a zero seed uses this instead
local WARMUP_STEPS = 8 -- small seeds produce similar first outputs; skip them

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number): Rng
	local state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if state == 0 then
		state = FALLBACK_STATE
	end
	local self = setmetatable({ state = state }, Rng)
	for _ = 1, WARMUP_STEPS do
		self:nextUInt32()
	end
	return self
end

-- Integer in [1, 2^32 - 1].
function Rng.nextUInt32(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Float in [0, 1).
function Rng.nextFloat(self: Rng): number
	return self:nextUInt32() / UINT32_RANGE
end

-- Integer in [min, max], both inclusive.
function Rng.nextInt(self: Rng, min: number, max: number): number
	return min + math.floor(self:nextFloat() * (max - min + 1))
end

return Rng
