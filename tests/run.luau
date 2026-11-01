--!strict
-- Run with: lune run tests/run.luau
local process = require("@lune/process")

local TestKit = require("./TestKit")

-- Add each new spec module here.
local specs = {
	require("./Config.spec"),
	require("./Rng.spec"),
	require("./Pieces.spec"),
	require("./Board.spec"),
	require("./Scoring.spec"),
	require("./Generator.spec"),
	require("./GameSession.spec"),
	require("./Simulation.spec"),
	require("./DragMath.spec"),
	require("./Lockstep.spec"),
	require("./ServerUtil.spec"),
	require("./GameRuns.spec"),
	require("./PlayerData.spec"),
	require("./Tutorial.spec"),
	require("./Telemetry.spec"),
	require("./Progression.spec"),
	require("./Leaderboards.spec"),
}

for _, spec in specs do
	spec(TestKit)
end

if not TestKit.report() then
	process.exit(1)
end
