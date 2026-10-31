--!strict
-- Owns every player's run on the server. The rules (validation, rate limits, outcomes) live in GameRuns;
-- this service wires them to the remotes and to player lifetime.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameRuns = require("../GameRuns")
local Net = require(ReplicatedStorage.Shared.Net)

local IS_STUDIO = RunService:IsStudio()

local GameService = {}

local runs: GameRuns.GameRuns

function GameService.init(_self: any)
	local Shared = ReplicatedStorage.Shared
	runs = GameRuns.new({
		GameSession = require(Shared.GameSession),
		Generator = require(Shared.Generator),
		Rng = require(Shared.Rng),
		clock = os.clock,
		newSeed = function(): number
			return Random.new():NextInteger(1, 2 ^ 31 - 1)
		end,
	})
end

function GameService.start(_self: any)
	Net.StartGame.OnServerEvent:Connect(function(player: Player)
		local state = runs:start(player)
		if state then
			Net.GameState:FireClient(player, state, "start")
		end
	end)

	Net.PlacePiece.OnServerEvent:Connect(
		function(player: Player, runId: unknown, moveIndex: unknown, slot: unknown, x: unknown, y: unknown)
			local outcome = runs:place(player, runId, moveIndex, slot, x, y)
			if outcome.kind == "accepted" then
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
	end)
end

-- For the Studio debug bridge.
function GameService.getRuns(): GameRuns.GameRuns
	return runs
end

return GameService
