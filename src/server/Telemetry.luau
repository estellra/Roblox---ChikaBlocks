--!strict
-- What the game reports to Roblox's analytics, decided from server-side events. Pure Luau so Lune can test it:
-- the sink that actually calls AnalyticsService is passed in.
--
-- Onboarding funnel: each step is logged once per player, and only right after the step before it, so the
-- funnel shows how far new players get. Progress is saved in PlayerData.onboardingStep.
--
-- Every run that ends (game over, the player leaving mid-run, or a restart) logs its score, its moves and its
-- highest combo as custom events, split by run mode and by how it ended.

export type Sink = {
	onboardingStep: (player: any, step: number, name: string) -> (),
	custom: (player: any, name: string, value: number, fields: { string }) -> (),
	-- A step of a funnel that can happen again and again; `session` tells attempts apart.
	funnel: (player: any, funnel: string, session: string, step: number, name: string) -> (),
}

export type RunEnd = "gameover" | "left" | "restart" | "coop" -- "coop": the player left their solo run to join a Co-op room

export type RunSummary = { mode: string, score: number, moves: number, maxCombo: number, isOver: boolean }

type Progress = { onboardingStep: number }

local STEPS = table.freeze({
	"MenuShown", -- 1: the client finished loading and shows the menu
	"RunStarted", -- 2: started a run (the tutorial, for a new player)
	"MovePlaced", -- 3: a move was accepted
	"LineCleared", -- 4: a move cleared at least one row or column
	"GameOver", -- 5: a run ended in game over
	"NextRunStarted", -- 6: started another run after that
})

-- Funnel "ReviveOffer": the offer shown on the game over panel, Revive pressed, the purchase granted (not for a
-- revive already paid for), the run revived.
local REVIVE_STEPS = table.freeze({ "Offered", "Requested", "Paid", "Revived" })

-- Funnel "RotationOffer": the player ran out of rotations and pressed rotate, the purchase was granted.
local ROTATION_STEPS = table.freeze({ "Requested", "Paid" })

-- Funnel "DonateOffer": a tier chosen on the Support screen, the donation granted.
local DONATE_STEPS = table.freeze({ "Requested", "Paid" })

local Telemetry = {}
Telemetry.__index = Telemetry

Telemetry.STEPS = STEPS
Telemetry.REVIVE_STEPS = REVIVE_STEPS
Telemetry.ROTATION_STEPS = ROTATION_STEPS
Telemetry.DONATE_STEPS = DONATE_STEPS

export type Telemetry = typeof(setmetatable({} :: { sink: Sink }, Telemetry))

function Telemetry.new(sink: Sink): Telemetry
	return setmetatable({ sink = sink }, Telemetry)
end

-- Logs onboarding `step` if the player has just finished the step before it.
local function advance(self: Telemetry, player: any, data: Progress, step: number)
	if data.onboardingStep == step - 1 then
		data.onboardingStep = step
		self.sink.onboardingStep(player, step, STEPS[step])
	end
end

function Telemetry.menuShown(self: Telemetry, player: any, data: Progress)
	advance(self, player, data, 1)
end

-- The player pressed Skip on the tutorial (only logged the first time).
function Telemetry.tutorialSkipped(self: Telemetry, player: any)
	self.sink.custom(player, "TutorialSkipped", 1, {})
end

-- One step of the revive funnel; `attempt` identifies the offer (the run and how many revives it had used).
function Telemetry.reviveStep(self: Telemetry, player: any, attempt: string, step: number)
	self.sink.funnel(player, "ReviveOffer", attempt, step, REVIVE_STEPS[step])
end

-- One step of the rotation funnel; `attempt` identifies the run it happened in.
function Telemetry.rotationStep(self: Telemetry, player: any, attempt: string, step: number)
	self.sink.funnel(player, "RotationOffer", attempt, step, ROTATION_STEPS[step])
end

-- One step of the donation funnel; `attempt` tells the prompts apart.
function Telemetry.donateStep(self: Telemetry, player: any, attempt: string, step: number)
	self.sink.funnel(player, "DonateOffer", attempt, step, DONATE_STEPS[step])
end

-- A donation was granted: the Robux it counts for, split by the tier of the product.
function Telemetry.donated(self: Telemetry, player: any, robux: number, tier: number)
	self.sink.custom(player, "Donated", robux, { tostring(tier) })
end

-- A piece was unlocked for turning; `how` is what it cost: "free" or "paid" (a bought rotation).
function Telemetry.rotationUsed(self: Telemetry, player: any, how: string)
	self.sink.custom(player, "RotationUsed", 1, { how })
end

function Telemetry.runStarted(self: Telemetry, player: any, data: Progress)
	advance(self, player, data, 2)
	advance(self, player, data, 6)
end

function Telemetry.moveAccepted(self: Telemetry, player: any, data: Progress, linesCleared: number)
	advance(self, player, data, 3)
	if linesCleared > 0 then
		advance(self, player, data, 4)
	end
end

-- `data` may be nil when the player is leaving and their data is already gone; only game over needs it.
function Telemetry.runEnded(self: Telemetry, player: any, data: Progress?, summary: RunSummary, how: RunEnd)
	if how == "gameover" and data then
		advance(self, player, data, 5)
	end
	local fields = { summary.mode, how }
	self.sink.custom(player, "RunScore", summary.score, fields)
	self.sink.custom(player, "RunMoves", summary.moves, fields)
	self.sink.custom(player, "RunMaxCombo", summary.maxCombo, fields)
end

return Telemetry
