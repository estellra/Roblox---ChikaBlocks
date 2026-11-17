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

-- How a run ended for a player. "coop": they left their solo run to join a Co-op room. For a Co-op run: "gameover"
-- with the partner still in it, "partner_left" for game over after the partner had left (the score no longer
-- counted), "left" when the player left it, "takeover" when the partner put them out for being idle.
export type RunEnd = "gameover" | "left" | "restart" | "coop" | "partner_left" | "takeover" | "pvp"

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

-- Funnel "CoopInvite": an invitation sent, accepted, the Co-op run started, and the run finished (the session is
-- the invitation's id; each step is logged for the player who invited).
local COOP_INVITE_STEPS = table.freeze({ "Sent", "Accepted", "RunStarted", "RunFinished" })

-- Funnel "PvpQueue": joined the ranked queue, matched, the match started, the match finished (the session is the
-- queue ticket).
local PVP_QUEUE_STEPS = table.freeze({ "Queued", "Matched", "Started", "Finished" })

-- How a PVP match ended for the analytics: by time, a forfeit, a player leaving or dropping, or voided by the server.
export type PvpEnd = "time" | "forfeit" | "disconnect" | "void"

-- One player's finished PVP match.
export type PvpMatchSummary = {
	kind: string, -- "ranked", "friendly" or "bot"
	result: string, -- "win", "loss", "draw" or "void"
	score: number,
	margin: number, -- the player's score minus the opponent's
	how: PvpEnd,
	sent: number,
	cancelled: number,
	taken: number,
	stuck: number,
	pendingAtEnd: number,
}

local Telemetry = {}
Telemetry.__index = Telemetry

Telemetry.STEPS = STEPS
Telemetry.REVIVE_STEPS = REVIVE_STEPS
Telemetry.ROTATION_STEPS = ROTATION_STEPS
Telemetry.DONATE_STEPS = DONATE_STEPS
Telemetry.COOP_INVITE_STEPS = COOP_INVITE_STEPS

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

-- One step of the revive funnel for a Co-op run, kept apart from the solo one: both players are offered it and
-- either may pay, which is a different decision. `attempt` identifies the offer (the run and its revives so far).
function Telemetry.coopReviveStep(self: Telemetry, player: any, attempt: string, step: number)
	self.sink.funnel(player, "CoopReviveOffer", attempt, step, REVIVE_STEPS[step])
end

-- One step of the rotation funnel; `attempt` identifies the run it happened in.
function Telemetry.rotationStep(self: Telemetry, player: any, attempt: string, step: number)
	self.sink.funnel(player, "RotationOffer", attempt, step, ROTATION_STEPS[step])
end

-- One step of the donation funnel; `attempt` tells the prompts apart.
function Telemetry.donateStep(self: Telemetry, player: any, attempt: string, step: number)
	self.sink.funnel(player, "DonateOffer", attempt, step, DONATE_STEPS[step])
end

-- One step of the Co-op invitation funnel; `invite` is the invitation's id.
function Telemetry.coopInviteStep(self: Telemetry, player: any, invite: string, step: number)
	self.sink.funnel(player, "CoopInvite", invite, step, COOP_INVITE_STEPS[step])
end

-- A Co-op move was turned down because the partner's move got there first (how often players clash).
function Telemetry.coopConflict(self: Telemetry, player: any)
	self.sink.custom(player, "CoopConflict", 1, {})
end

-- A donation was granted: the Robux it counts for, split by the tier of the product.
function Telemetry.donated(self: Telemetry, player: any, robux: number, tier: number)
	self.sink.custom(player, "Donated", robux, { tostring(tier) })
end

-- A piece was unlocked for turning; `how` is what it cost: "free" or "paid" (a bought rotation). A Co-op turn adds
-- "coop" as the second field, so the two can be told apart.
function Telemetry.rotationUsed(self: Telemetry, player: any, how: string, coop: boolean?)
	self.sink.custom(player, "RotationUsed", 1, if coop then { how, "coop" } else { how })
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

-- One step of the ranked queue funnel; `ticket` tells one wait apart from the next.
function Telemetry.pvpQueueStep(self: Telemetry, player: any, ticket: string, step: number)
	self.sink.funnel(player, "PvpQueue", ticket, step, PVP_QUEUE_STEPS[step])
end

-- How long a player waited in the queue, and how the wait ended: "matched", "cancelled", "bot" (they chose practice)
-- or "left" (the server).
function Telemetry.pvpQueueWait(self: Telemetry, player: any, seconds: number, how: string)
	self.sink.custom(player, "PvpQueueWait", math.floor(seconds), { how })
end

-- A PVP match is over for the player. No user ids or names in any field.
function Telemetry.pvpMatchEnded(self: Telemetry, player: any, match: PvpMatchSummary)
	local kind = { match.kind }
	self.sink.custom(player, "PvpMatchScore", match.score, { match.kind, match.result })
	self.sink.custom(player, "PvpMargin", match.margin, kind)
	self.sink.custom(player, "PvpEnd", 1, { match.how })
	self.sink.custom(player, "PvpGarbageSent", match.sent, kind)
	self.sink.custom(player, "PvpGarbageCancelled", match.cancelled, kind)
	self.sink.custom(player, "PvpGarbageTaken", match.taken, kind)
	self.sink.custom(player, "PvpStuck", match.stuck, kind)
	self.sink.custom(player, "PvpPendingAtEnd", match.pendingAtEnd, kind)
end

-- A ranked pair was made: how far apart their points were, and whether the match is unrated (the pair's daily limit).
function Telemetry.pvpMatched(self: Telemetry, player: any, ratingGap: number, unrated: boolean)
	self.sink.custom(player, "PvpRatingGap", math.floor(math.abs(ratingGap)), {})
	if unrated then
		self.sink.custom(player, "PvpUnratedPair", 1, {})
	end
end

-- A season rolled over for the player: the highest tier they reached in it.
function Telemetry.pvpSeasonTier(self: Telemetry, player: any, tier: string)
	self.sink.custom(player, "PvpSeasonTier", 1, { tier })
end

-- `data` may be nil when the player is leaving and their data is already gone; only game over needs it.
function Telemetry.runEnded(self: Telemetry, player: any, data: Progress?, summary: RunSummary, how: RunEnd)
	-- A Co-op game over is not the onboarding one: the step is about a solo run.
	if how == "gameover" and data and summary.mode ~= "coop" then
		advance(self, player, data, 5)
	end
	local fields = { summary.mode, how }
	self.sink.custom(player, "RunScore", summary.score, fields)
	self.sink.custom(player, "RunMoves", summary.moves, fields)
	self.sink.custom(player, "RunMaxCombo", summary.maxCombo, fields)
end

return Telemetry
