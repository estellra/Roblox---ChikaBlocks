--!strict
-- Checks for values that arrive from clients. Treat every remote argument as `unknown` until it passes one.

local Validate = {}

-- A number within [min, max]. Rejects NaN (which fails every comparison) and anything that isn't a number.
function Validate.number(value: unknown, min: number, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n < min or n > max then
		return nil
	end
	return n
end

function Validate.integer(value: unknown, min: number, max: number): number?
	local n = Validate.number(value, min, max)
	return if n and n == math.floor(n) then n else nil
end

return Validate
