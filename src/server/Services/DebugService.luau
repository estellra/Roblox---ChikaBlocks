--!strict
-- Studio-only test hook. Creates ServerStorage.ChikaServerDebug (a BindableFunction) so playtests driven
-- through Studio MCP can read the server's copy of a run and compare it with the client's. Does nothing
-- outside Studio.
--
-- Commands: state [userId] | data [userId] | resetdata [userId] | events  (default to the first player)
-- events lists the latest analytics events (onboarding steps and run summaries).
-- resetdata wipes the player's PlayerData_Dev profile (Studio's store) to replay the first-time flow.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require("./DataService")
local GameService = require("./GameService")

local SIZE = Config.GRID_SIZE

local DebugService = {}

local function describe(player: Player): string
	local state = GameService.getRuns():peek(player)
	if not state then
		return `no run for {player.Name}`
	end
	local snapshot = state.session
	local rows = {}
	for y = 0, SIZE - 1 do
		local row = table.create(SIZE)
		for x = 0, SIZE - 1 do
			row[x + 1] = if snapshot.cells[y * SIZE + x + 1] == 0 then "." else "#"
		end
		rows[y + 1] = table.concat(row)
	end
	local tray = {}
	for i, id in snapshot.tray do
		tray[i] = if id then id else "-"
	end
	return `run={state.runId} score={snapshot.score} over={snapshot.isOver} moves={snapshot.moveCount} best={state.best} tray={table.concat(
		tray,
		","
	)}\n{table.concat(rows, "\n")}`
end

function DebugService.start(_self: any)
	if not RunService:IsStudio() then
		return
	end
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ChikaServerDebug"
	bridge.OnInvoke = function(command: string, userId: number?): string
		if command == "events" then -- needs no player: it also shows what was logged as one left
			local events = GameService.getRecentEvents()
			return if #events > 0 then table.concat(events, "\n") else "no analytics events yet"
		end
		local player = if userId then Players:GetPlayerByUserId(userId) else Players:GetPlayers()[1]
		if not player then
			return "no player"
		end
		if command == "state" then
			return describe(player)
		elseif command == "data" then
			local data = DataService.get(player)
			if not data then
				return `{DataService.describeStore()} | no data loaded for {player.Name}`
			end
			return `{DataService.describeStore()} | version={data.version} best={data.bestScore} games={data.gamesPlayed} tutorialDone={data.tutorialDone} onboardingStep={data.onboardingStep}`
		elseif command == "resetdata" then
			local data = DataService.get(player)
			if not data then
				return "no data loaded"
			end
			data.bestScore, data.gamesPlayed, data.tutorialDone, data.onboardingStep = 0, 0, false, 0
			GameService.getRuns():setBest(player, 0)
			GameService.sendProfile(player)
			return `reset {player.Name}: best=0 games=0 tutorialDone=false onboardingStep=0`
		end
		return `unknown command "{command}"`
	end
	bridge.Parent = ServerStorage
end

return DebugService
