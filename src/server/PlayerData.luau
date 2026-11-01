--!strict
-- What is saved per player and the rules for changing it. Pure Luau so Lune can test it; DataService keeps
-- the live copy in a ProfileStore profile.

export type PlayerData = {
	version: number,
	bestScore: number,
	gamesPlayed: number, -- runs that ended in game over
	tutorialDone: boolean,
	onboardingStep: number, -- last onboarding funnel step logged (see Telemetry)
	level: number,
	exp: number, -- progress toward the next level (see Progression)
	milestonesClaimed: { [string]: boolean }, -- milestone id -> true
	badgesAwarded: { [string]: boolean }, -- milestone id -> true once its badge is awarded
}

-- MIGRATIONS[n] upgrades version n data to version n + 1. Never delete a field in the same release that
-- stops writing it, and never reuse a field name for a different meaning.
local MIGRATIONS: { (data: { [string]: any }) -> () } = {
	-- v1 -> v2: onboarding funnel progress. Players from before it have already been through what they played;
	-- anyone with a finished run counts as past all six steps, so they don't enter the funnel late.
	[1] = function(data)
		if (data.gamesPlayed or 0) > 0 then
			data.onboardingStep = 6
		elseif data.tutorialDone then
			data.onboardingStep = 3
		else
			data.onboardingStep = 0
		end
	end,
}
local CURRENT_VERSION = #MIGRATIONS + 1

local PlayerData = {}

PlayerData.VERSION = CURRENT_VERSION

-- Defaults for a new player. ProfileStore's Reconcile also copies fields added here later into old profiles
-- (deep-copying the tables), so a field whose default fits old players needs no migration.
PlayerData.TEMPLATE = table.freeze({
	version = CURRENT_VERSION,
	bestScore = 0,
	gamesPlayed = 0,
	tutorialDone = false,
	onboardingStep = 0,
	level = 1,
	exp = 0,
	milestonesClaimed = table.freeze({}),
	badgesAwarded = table.freeze({}),
})

-- Brings saved data up to the current version in place. Run before Reconcile.
function PlayerData.migrate(data: { [string]: any }): PlayerData
	local version = data.version or 1
	while version < CURRENT_VERSION do
		MIGRATIONS[version](data)
		version += 1
	end
	data.version = CURRENT_VERSION
	return data :: any
end

-- Keeps the higher of the saved best and `score`. Returns whether the best went up.
function PlayerData.recordScore(data: PlayerData, score: number): boolean
	if score > data.bestScore then
		data.bestScore = score
		return true
	end
	return false
end

function PlayerData.recordRunEnd(data: PlayerData, finalScore: number)
	PlayerData.recordScore(data, finalScore)
	data.gamesPlayed += 1
end

-- Returns whether this changed anything (false when the tutorial was already done).
function PlayerData.markTutorialDone(data: PlayerData): boolean
	if data.tutorialDone then
		return false
	end
	data.tutorialDone = true
	return true
end

return PlayerData
