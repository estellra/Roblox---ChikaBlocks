--!strict
-- Minimal describe/it/expect for running pure-Luau specs under Lune.

local TestKit = {}

local scope: { string } = {}
local passed = 0
local failures: { string } = {}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function TestKit.describe(name: string, fn: () -> ())
	table.insert(scope, name)
	fn()
	table.remove(scope)
end

function TestKit.it(name: string, fn: () -> ())
	local fullName = table.concat(scope, " > ") .. " > " .. name
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		table.insert(failures, `{fullName}\n    {err}`)
	end
end

function TestKit.expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(`expected {tostring(expected)}, got {tostring(actual)}`, 2)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				error("values are not deeply equal", 2)
			end
		end,
		toBeTruthy = function()
			if not actual then
				error(`expected a truthy value, got {tostring(actual)}`, 2)
			end
		end,
	}
end

-- Prints the summary; returns true when every test passed.
function TestKit.report(): boolean
	for _, failure in failures do
		print(`FAIL {failure}`)
	end
	print(`{passed} passed, {#failures} failed`)
	return #failures == 0
end

export type TestKit = typeof(TestKit)

return TestKit
