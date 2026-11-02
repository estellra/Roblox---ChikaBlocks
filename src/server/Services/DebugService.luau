--!strict
-- Studio-only test hook. Creates ServerStorage.ChikaServerDebug (a BindableFunction) so playtests driven
-- through Studio MCP can read the server's copy of a run and compare it with the client's. Does nothing
-- outside Studio.
--
-- Commands: state [userId] | data [userId] | resetdata [userId] | events | addexp [userId] <exp>
--           | setbest [userId] <score>  (userId defaults to the first player; pass nil to skip it)
-- events lists the latest analytics events (onboarding steps and run summaries).
-- resetdata wipes the player's PlayerData_Dev profile (Studio's store) to replay the first-time flow.
-- addexp and setbest change progress the way a run would, claiming milestones and sending the profile.
-- fakepurchase [userId] [productId] [purchaseId] hands the real receipt handler a made-up receipt (default: the first
-- revive product); the same purchaseId twice shows that a purchase is granted once.
-- boards writes the player's values, reads every leaderboard now (instead of within a minute) and lists them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require("./DataService")
local GameService = require("./GameService")
local LeaderboardService = require("./LeaderboardService")
local PurchaseService = require("./PurchaseService")
local Progression = require(ReplicatedStorage.Shared.Progression)
local RewardService = require("./RewardService")

local SIZE = Config.GRID_SIZE

local DebugService = {}

local debugReceipts = 0

local function keys(set: { [string]: boolean }): string
	local list = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return table.concat(list, ",")
end

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
	bridge.OnInvoke = function(command: string, userId: number?, value: number?, extra: string?): string
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
			return `{DataService.describeStore()} | version={data.version} best={data.bestScore} games={data.gamesPlayed} tutorialDone={data.tutorialDone} onboardingStep={data.onboardingStep} level={data.level} exp={data.exp}/{Progression.expToNext(
				data.level
			)} milestones={keys(data.milestonesClaimed)} badges={keys(data.badgesAwarded)} reviveTokens={data.reviveTokens} purchases={#data.purchaseIds} title={Progression.title(
				data.milestonesClaimed
			)}`
		elseif command == "resetdata" then
			local data = DataService.get(player)
			if not data then
				return "no data loaded"
			end
			data.bestScore, data.gamesPlayed, data.tutorialDone, data.onboardingStep = 0, 0, false, 0
			data.level, data.exp = 1, 0
			table.clear(data.milestonesClaimed)
			table.clear(data.badgesAwarded)
			data.reviveTokens = 0
			table.clear(data.purchaseIds)
			data.weekly.week, data.weekly.bestScore, data.weekly.exp = "", 0, 0
			GameService.getRuns():setBest(player, 0)
			GameService.sendProfile(player)
			return `reset {player.Name}: best=0 games=0 tutorialDone=false onboardingStep=0 level=1 exp=0 milestones=none`
		elseif command == "fakepurchase" then
			local productId = value or Config.REVIVE_PRODUCTS[1]
			debugReceipts += 1
			local decision = PurchaseService.process({
				PlayerId = player.UserId,
				ProductId = productId,
				PurchaseId = extra or `debug-{debugReceipts}`,
			})
			local data = DataService.get(player)
			return `{decision} reviveTokens={if data then data.reviveTokens else "?"}`
		elseif command == "boards" then
			local data = DataService.get(player)
			if data then
				LeaderboardService.flush(player, data)
				task.wait(2) -- the writes run on their own threads
			end
			LeaderboardService.refresh()
			return LeaderboardService.describe()
		elseif command == "addexp" or command == "setbest" then
			local data = DataService.get(player)
			if not data or not value then
				return "no data loaded, or no value given"
			end
			if command == "addexp" then
				Progression.addExp(data, value)
			else
				data.bestScore = value
				GameService.getRuns():setBest(player, value)
			end
			local claimed = {}
			for _, milestone in RewardService.sync(player, data) do
				table.insert(claimed, milestone.id)
			end
			GameService.sendProfile(player)
			return `level={data.level} exp={data.exp} best={data.bestScore} claimed now={table.concat(claimed, ",")}`
		end
		return `unknown command "{command}"`
	end
	bridge.Parent = ServerStorage
end

return DebugService
