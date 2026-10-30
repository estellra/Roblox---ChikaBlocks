--!strict
-- Run with: lune run tests/run.luau
local process = require("@lune/process")

local TestKit = require("./TestKit")

-- Add each new spec module here.
local specs = {
	require("./Config.spec"),
}

for _, spec in specs do
	spec(TestKit)
end

if not TestKit.report() then
	process.exit(1)
end
