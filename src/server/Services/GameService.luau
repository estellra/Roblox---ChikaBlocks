--!strict
-- Owns every player's run on the server. The rules (validation, rate limits, outcomes) live in GameRuns;
-- this service wires them to the remotes, to player lifetime, to the saved data (best score, games
-- played, tutorial progress, EXP and level), to milestone rewards (RewardService) and to analytics
-- (Telemetry decides what to log). A run's EXP is credited as its score grows, so a run left halfway
-- still counts.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DataService = require("./DataService")
local GameRuns = require("../GameRuns")
local LeaderboardService = require("./LeaderboardService")
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require("../PlayerData")
local Progression = require(ReplicatedStorage.Shared.Progression)
local RateLimiter = require("../Util/RateLimiter")
local RewardService = require("./RewardService")
local Telemetry = require("../Telemetry")

local IS_STUDIO = RunService:IsStudio()
local DATA_WAIT_SECONDS = 15 -- how long a request waits for the player's saved data to load
local MAX_RECENT_EVENTS = 50 -- analytics events kept in Studio for the debug bridge
local RUN_FLUSH_GAP_SECONDS = 20 -- at least this long between a player's leaderboard writes after runs
local CUSTOM_FIELDS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

export type Profile = {
	best: number,
	gamesPlayed: number,
	tutorialDone: boolean,
	level: number,
	exp: number,
	rotations: number, -- bought rotations left
	donated: number, -- Robux given through donation products
	title: string?,
}

-- What a finished run earned, for the game over panel.
export type RunRewards = {
	expGained: number,
	levelBefore: number,
	expBefore: number,
	level: number,
	exp: number,
	titles: { string }, -- unlocked during the run, in rank order
}

-- Progress during the player's current run.
type RunProgress = { expGranted: number, levelBefore: number, expBefore: number, titles: { string } }

local GameService = {}

local runs: GameRuns.GameRuns
local telemetry: Telemetry.Telemetry
local profileLimiter = RateLimiter.new(2, 1, os.clock)
local readyLimiter = RateLimiter.new(1, 5, os.clock)
local skipLimiter = RateLimiter.new(1, 2, os.clock)
local runProgress: { [Player]: RunProgress } = {}
local gameOverListeners: { (player: Player, runId: number) -> () } = {}
local recentEvents: { string } = {}

local function remember(line: string)
	if IS_STUDIO then
		table.insert(recentEvents, line)
		if #recentEvents > MAX_RECENT_EVENTS then
			table.remove(recentEvents, 1)
		end
	end
end

-- Analytics calls must never break the game, so failures are only reported in Studio.
local function logSafely(what: string, call: () -> ())
	local ok, err = pcall(call)
	if not ok and IS_STUDIO then
		warn(`[ChikaBlock] analytics {what} failed: {err}`)
	end
end

local analyticsSink: Telemetry.Sink = {
	onboardingStep = function(player: Player, step: number, name: string)
		remember(`onboarding {step} {name} ({player.Name})`)
		logSafely(name, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
		end)
	end,
	funnel = function(player: Player, funnel: string, session: string, step: number, name: string)
		remember(`{funnel} {step} {name} [{session}] ({player.Name})`)
		logSafely(funnel, function()
			AnalyticsService:LogFunnelStepEvent(player, funnel, session, step, name)
		end)
	end,
	custom = function(player: Player, name: string, value: number, fields: { string })
		local customFields = {}
		for i, field in fields do
			customFields[CUSTOM_FIELDS[i]] = field
		end
		remember(`{name}={value} [{table.concat(fields, ",")}] ({player.Name})`)
		logSafely(name, function()
			AnalyticsService:LogCustomEvent(player, name, value, customFields)
		end)
	end,
}

local function profileOf(player: Player, data: PlayerData.PlayerData): Profile
	return {
		best = math.max(runs:getBest(player), data.bestScore),
		gamesPlayed = data.gamesPlayed,
		tutorialDone = data.tutorialDone,
		level = data.level,
		exp = data.exp,
		rotations = data.rotations,
		donated = data.robuxDonated,
		title = Progression.title(data.milestonesClaimed),
	}
end

-- Credits the EXP the run's score has earned since the last move and claims any milestone reached.
local function creditProgress(player: Player, data: PlayerData.PlayerData, score: number)
	local progress = runProgress[player]
	local gained = 0
	if progress then
		local earned = Progression.expForScore(score)
		if earned > progress.expGranted then
			gained = earned - progress.expGranted
			Progression.addExp(data, gained)
			progress.expGranted = earned
		end
	end
	LeaderboardService.recordRun(data, score, gained)
	for _, milestone in RewardService.sync(player, data) do
		if progress then
			table.insert(progress.titles, milestone.title)
		end
	end
end

local function rewardsOf(progress: RunProgress, data: PlayerData.PlayerData): RunRewards
	return {
		expGained = progress.expGranted,
		levelBefore = progress.levelBefore,
		expBefore = progress.expBefore,
		level = data.level,
		exp = data.exp,
		titles = progress.titles,
	}
end

local function notifyGameOver(player: Player, runId: number)
	for _, listener in gameOverListeners do
		task.spawn(listener, player, runId)
	end
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
	telemetry = Telemetry.new(analyticsSink)
end

function GameService.start(_self: any)
	Net.RequestProfile.OnServerEvent:Connect(function(player: Player)
		if not profileLimiter:allow(player) then
			return
		end
		local data = DataService.waitForData(player, DATA_WAIT_SECONDS)
		if data then
			RewardService.sync(player, data) -- milestones reached before they existed; badges owed
			Net.Profile:FireClient(player, profileOf(player, data))
		end
	end)

	Net.SkipTutorial.OnServerEvent:Connect(function(player: Player)
		if not skipLimiter:allow(player) then
			return
		end
		local data = DataService.get(player)
		if data and PlayerData.markTutorialDone(data) then
			telemetry:tutorialSkipped(player)
			Net.Profile:FireClient(player, profileOf(player, data))
		end
	end)

	Net.ClientReady.OnServerEvent:Connect(function(player: Player)
		if not readyLimiter:allow(player) then
			return
		end
		local data = DataService.waitForData(player, DATA_WAIT_SECONDS)
		if data then
			telemetry:menuShown(player, data)
		end
	end)

	Net.StartGame.OnServerEvent:Connect(function(player: Player, mode: unknown)
		-- The saved best decides "New best!", so the run starts once the data is in.
		local data = DataService.waitForData(player, DATA_WAIT_SECONDS)
		if not data then
			return -- left, or kicked because the data couldn't load
		end
		runs:setBest(player, math.max(runs:getBest(player), data.bestScore))
		local previous = runs:summary(player)
		local state = runs:start(player, mode)
		if state then
			-- A run left without a move is a retried request rather than a real restart.
			if previous and not previous.isOver and previous.moves > 0 then
				telemetry:runEnded(player, data, previous, "restart")
			end
			telemetry:runStarted(player, data)
			runProgress[player] = { expGranted = 0, levelBefore = data.level, expBefore = data.exp, titles = {} }
			Net.GameState:FireClient(player, state, "start")
		end
	end)

	Net.PlacePiece.OnServerEvent:Connect(
		function(player: Player, runId: unknown, moveIndex: unknown, slot: unknown, x: unknown, y: unknown)
			local outcome = runs:place(player, runId, moveIndex, slot, x, y)
			if outcome.kind == "accepted" then
				local data = DataService.get(player)
				if data then
					-- A run counts as played once, even if it is revived and ends again.
					if outcome.endsRun then
						PlayerData.recordRunEnd(data, outcome.score)
					else
						PlayerData.recordScore(data, outcome.score)
					end
					-- The tutorial counts as done once its first move lands.
					if outcome.mode == "tutorial" and PlayerData.markTutorialDone(data) then
						Net.Profile:FireClient(player, profileOf(player, data))
					end
					creditProgress(player, data, outcome.score)
					telemetry:moveAccepted(player, data, outcome.linesCleared)
				end
				local summary = if outcome.endsRun then runs:summary(player) else nil
				if summary then
					telemetry:runEnded(player, data, summary, "gameover")
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
				local progress = runProgress[player]
				if outcome.isOver and data and progress then
					Net.RunRewards:FireClient(player, outcome.runId, rewardsOf(progress, data))
					Net.Profile:FireClient(player, profileOf(player, data))
					LeaderboardService.flush(player, data, RUN_FLUSH_GAP_SECONDS)
				end
				if outcome.isOver then
					notifyGameOver(player, outcome.runId)
				end
			elseif outcome.kind == "resync" then
				if IS_STUDIO then
					warn(`[ChikaBlock] rejected a move from {player.Name}; sending the full state`)
				end
				Net.GameState:FireClient(player, outcome.state, "resync")
			end
		end
	)

	Net.RotatePiece.OnServerEvent:Connect(function(player: Player, runId: unknown, moveIndex: unknown, slot: unknown)
		local data = DataService.get(player)
		local outcome = runs:rotate(player, runId, moveIndex, slot, if data then data.rotations else 0)
		if outcome.kind == "accepted" then
			if outcome.charged then
				telemetry:rotationUsed(player, outcome.charged)
			end
			if outcome.charged == "paid" and data and PlayerData.useRotation(data) then
				Net.Profile:FireClient(player, profileOf(player, data))
			end
		elseif outcome.kind == "resync" then
			if IS_STUDIO then
				warn(`[ChikaBlock] rejected a rotation from {player.Name}; sending the full state`)
			end
			Net.GameState:FireClient(player, outcome.state, "resync")
			if data then
				Net.Profile:FireClient(player, profileOf(player, data)) -- the client may be wrong about its rotations
			end
		end
	end)

	Net.RequestState.OnServerEvent:Connect(function(player: Player)
		local state = runs:state(player)
		if state then
			Net.GameState:FireClient(player, state, "resync")
			if state.session.isOver then
				notifyGameOver(player, state.runId) -- the client may have missed the revive offer
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local summary = runs:summary(player)
		if summary and not summary.isOver then
			telemetry:runEnded(player, DataService.get(player), summary, "left")
		end
		runs:remove(player)
		runProgress[player] = nil
		profileLimiter:forget(player)
		readyLimiter:forget(player)
		skipLimiter:forget(player)
	end)
end

-- Called with the player and the run's id every time a run ends in game over (again after each revive).
function GameService.onGameOver(callback: (player: Player, runId: number) -> ())
	table.insert(gameOverListeners, callback)
end

-- One step of the revive funnel for the player's current offer.
function GameService.logRevive(player: Player, step: number)
	local summary = runs:summary(player)
	if summary then
		telemetry:reviveStep(player, `{summary.runId}.{summary.revives}`, step)
	end
end

-- One step of the rotation funnel for the player's current run.
function GameService.logRotation(player: Player, step: number)
	local summary = runs:summary(player)
	if summary then
		telemetry:rotationStep(player, tostring(summary.runId), step)
	end
end

-- One step of the donation funnel; `attempt` tells the purchase prompts apart.
function GameService.logDonate(player: Player, attempt: string, step: number)
	telemetry:donateStep(player, attempt, step)
end

-- A donation was granted: the Robux it counts for and the tier of its product.
function GameService.logDonated(player: Player, robux: number, tier: number)
	telemetry:donated(player, robux, tier)
end

-- Revives the player's finished run and sends them the new state. False when it can't be revived (the caller
-- has not spent anything yet).
function GameService.revive(player: Player, runId: number): boolean
	local before = runs:summary(player)
	local state = runs:revive(player, runId)
	if not before or not state then
		return false
	end
	telemetry:reviveStep(player, `{before.runId}.{before.revives}`, 4)
	Net.GameState:FireClient(player, state, "revive")
	return true
end

-- Sends the player's current profile, e.g. after the Studio debug bridge resets it.
function GameService.sendProfile(player: Player)
	local data = DataService.get(player)
	if data then
		Net.Profile:FireClient(player, profileOf(player, data))
	end
end

-- For the Studio debug bridge: the latest analytics events, oldest first.
function GameService.getRecentEvents(): { string }
	return recentEvents
end

-- For the Studio debug bridge.
function GameService.getRuns(): GameRuns.GameRuns
	return runs
end

return GameService
