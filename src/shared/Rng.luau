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

-- a * b modulo 2^32, exact (a plain product of two 32-bit numbers can exceed a double's 53 bits).
local function mul32(a: number, b: number): number
	local aLo, aHi = bit32.band(a, 0xFFFF), bit32.rshift(a, 16)
	local bLo, bHi = bit32.band(b, 0xFFFF), bit32.rshift(b, 16)
	local cross = (aHi * bLo + aLo * bHi) % 0x10000
	return (aLo * bLo + cross * 0x10000) % UINT32_RANGE
end

-- MurmurHash3's finalizer: spreads every input bit over the whole output.
local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

local function hashString(text: string): number
	local h = 0x811C9DC5 -- FNV-1a
	for i = 1, #text do
		h = mul32(bit32.bxor(h, string.byte(text, i)), 0x01000193)
	end
	return h
end

-- A seed for a separate stream, derived from `seed` and a list of numbers or strings naming the stream, e.g.
-- Rng.mix(matchSeed, "set", k). The same inputs always give the same seed; different ones give unrelated seeds.
function Rng.mix(seed: number, ...: number | string): number
	local h = fmix32(bit32.band(math.floor(seed), 0xFFFFFFFF))
	for i = 1, select("#", ...) do
		local part = select(i, ...)
		local value = if typeof(part) == "string" then hashString(part) else bit32.band(math.floor(part), 0xFFFFFFFF)
		h = fmix32(bit32.bxor(mul32(h, 0x01000193), fmix32(bit32.bxor(value, 0x9E3779B9))))
	end
	return h
end

return Rng
