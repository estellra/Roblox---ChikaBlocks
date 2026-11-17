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
	require("./Purchases.spec"),
	require("./Erasure.spec"),
	require("./SetSize.spec"),
	require("./CoopSession.spec"),
	require("./CoopSimulation.spec"),
	require("./Rooms.spec"),
	require("./CoopRuns.spec"),
	require("./CoopSync.spec"),
	require("./CoopLockstep.spec"),
	require("./CoopProgress.spec"),
	require("./CoopTurns.spec"),
	require("./CoopTurnsLockstep.spec"),
	require("./PvpSession.spec"),
	require("./PvpSimulation.spec"),
	require("./Elo.spec"),
	require("./Seasons.spec"),
	require("./PvpRating.spec"),
	require("./PvpBoardCodec.spec"),
	require("./PvpMatches.spec"),
	require("./PvpSync.spec"),
	require("./PvpLockstep.spec"),
	require("./Matchmaker.spec"),
	require("./PairLimits.spec"),
	require("./RankedRules.spec"),
}

for _, spec in specs do
	spec(TestKit)
end

if not TestKit.report() then
	process.exit(1)
end
