--!strict
-- What is saved per player and the rules for changing it. Pure Luau so Lune can test it; DataService keeps
-- the live copy in a ProfileStore profile.

export type PlayerData = {
	version: number,
	bestScore: number,
	gamesPlayed: number, -- runs that ended in game over
	tutorialDone: boolean,
}

-- MIGRATIONS[n] upgrades version n data to version n + 1. Never delete a field in the same release that
-- stops writing it, and never reuse a field name for a different meaning.
local MIGRATIONS: { (data: { [string]: any }) -> () } = {}
local CURRENT_VERSION = #MIGRATIONS + 1

local PlayerData = {}

PlayerData.VERSION = CURRENT_VERSION

-- Defaults for a new player. ProfileStore's Reconcile also copies fields added here later into old profiles.
PlayerData.TEMPLATE = table.freeze({
	version = CURRENT_VERSION,
	bestScore = 0,
	gamesPlayed = 0,
	tutorialDone = false,
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

return PlayerData
