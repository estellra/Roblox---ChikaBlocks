--!strict
-- Owns every player's run on the server. The rules (validation, rate limits, outcomes) live in GameRuns;
-- this service wires them to the remotes, to player lifetime and to the saved data (best score, games
-- played, tutorial progress).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DataService = require("./DataService")
local GameRuns = require("../GameRuns")
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require("../PlayerData")
local RateLimiter = require("../Util/RateLimiter")

local IS_STUDIO = RunService:IsStudio()
local DATA_WAIT_SECONDS = 15 -- how long a request waits for the player's saved data to load

export type Profile = { best: number, gamesPlayed: number, tutorialDone: boolean }

local GameService = {}

local runs: GameRuns.GameRuns
local profileLimiter = RateLimiter.new(2, 1, os.clock)

local function profileOf(player: Player, data: PlayerData.PlayerData): Profile
	return {
		best = math.max(runs:getBest(player), data.bestScore),
		gamesPlayed = data.gamesPlayed,
		tutorialDone = data.tutorialDone,
	}
end

function GameService.init(_self: any)
	local Shared = ReplicatedStorage.Shared
	runs = GameRuns.new({
		GameSession = require(Shared.GameSession),
		Generator = require(Shared.Generator),
		Rng = require(Shared.Rng),
		Tutorial = require(Shared.Tutorial),
		clock = os.clock,
		newSeed = function(): number
			return Random.new():NextInteger(1, 2 ^ 31 - 1)
		end,
	})
end

function GameService.start(_self: any)
	Net.RequestProfile.OnServerEvent:Connect(function(player: Player)
		if not profileLimiter:allow(player) then
			return
		end
		local data = DataService.waitForData(player, DATA_WAIT_SECONDS)
		if data then
			Net.Profile:FireClient(player, profileOf(player, data))
		end
	end)

	Net.StartGame.OnServerEvent:Connect(function(player: Player, mode: unknown)
		-- The saved best decides "New best!", so the run starts once the data is in.
		local data = DataService.waitForData(player, DATA_WAIT_SECONDS)
		if not data then
			return -- left, or kicked because the data couldn't load
		end
		runs:setBest(player, math.max(runs:getBest(player), data.bestScore))
		local state = runs:start(player, mode)
		if state then
			Net.GameState:FireClient(player, state, "start")
		end
	end)

	Net.PlacePiece.OnServerEvent:Connect(
		function(player: Player, runId: unknown, moveIndex: unknown, slot: unknown, x: unknown, y: unknown)
			local outcome = runs:place(player, runId, moveIndex, slot, x, y)
			if outcome.kind == "accepted" then
				local data = DataService.get(player)
				if data then
					if outcome.isOver then
						PlayerData.recordRunEnd(data, outcome.score)
					else
						PlayerData.recordScore(data, outcome.score)
					end
					-- The tutorial counts as done once its first move lands.
					if outcome.mode == "tutorial" and PlayerData.markTutorialDone(data) then
						Net.Profile:FireClient(player, profileOf(player, data))
					end
				end
				Net.MoveResult:FireClient(
					player,
					outcome.runId,
					outcome.moveIndex,
					outcome.score,
					outcome.set,
					outcome.isOver,
					outcome.best
				)
			elseif outcome.kind == "resync" then
				if IS_STUDIO then
					warn(`[ChikaBlock] rejected a move from {player.Name}; sending the full state`)
				end
				Net.GameState:FireClient(player, outcome.state, "resync")
			end
		end
	)

	Net.RequestState.OnServerEvent:Connect(function(player: Player)
		local state = runs:state(player)
		if state then
			Net.GameState:FireClient(player, state, "resync")
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		runs:remove(player)
		profileLimiter:forget(player)
	end)
end

-- Sends the player's current profile, e.g. after the Studio debug bridge resets it.
function GameService.sendProfile(player: Player)
	local data = DataService.get(player)
	if data then
		Net.Profile:FireClient(player, profileOf(player, data))
	end
end

-- For the Studio debug bridge.
function GameService.getRuns(): GameRuns.GameRuns
	return runs
end

return GameService
