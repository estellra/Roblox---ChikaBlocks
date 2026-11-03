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
	-- This week's best score and EXP for the weekly leaderboards; reset when the week changes (see Leaderboards).
	weekly: { week: string, bestScore: number, exp: number },
	reviveTokens: { number }, -- paid revives not used yet, counted per price tier 1..3 (see Purchases)
	rotations: number, -- bought rotations not used yet
	robuxDonated: number, -- Robux given through donation products, for the Supporters board
	purchaseIds: { string }, -- receipts already handled, the latest 100, newest last
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
-- v2 -> v3: paid revives are counted per price tier. Before, one number counted them all; those go to the
-- highest tier, which can be used for any revive.
MIGRATIONS[2] = function(data)
	local old = data.reviveTokens
	data.reviveTokens = { 0, 0, if type(old) == "number" then old else 0 }
end
local CURRENT_VERSION = #MIGRATIONS + 1

local MAX_REMEMBERED_PURCHASES = 100
local MAX_DONATED = 1e9 -- far beyond any real total; keeps the board's integer safe

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
	weekly = table.freeze({ week = "", bestScore = 0, exp = 0 }),
	reviveTokens = table.freeze({ 0, 0, 0 }),
	rotations = 0,
	robuxDonated = 0,
	purchaseIds = table.freeze({}),
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

-- Whether this receipt has been handled already.
function PlayerData.hasPurchase(data: PlayerData, purchaseId: string): boolean
	return table.find(data.purchaseIds, purchaseId) ~= nil
end

-- Remembers a handled receipt, forgetting the oldest beyond the latest 100.
function PlayerData.rememberPurchase(data: PlayerData, purchaseId: string)
	table.insert(data.purchaseIds, purchaseId)
	while #data.purchaseIds > MAX_REMEMBERED_PURCHASES do
		table.remove(data.purchaseIds, 1)
	end
end

-- Adds a revive bought at price tier `tier` (1 is the cheapest product).
function PlayerData.addReviveToken(data: PlayerData, tier: number)
	data.reviveTokens[tier] = (data.reviveTokens[tier] or 0) + 1
end

-- How many paid revives can be used for a revive that costs tier `required`: those bought at that tier or a
-- higher one. A cheaper revive can't be used for a dearer one, or buying the cheapest product again and again
-- would get every revive at its price.
function PlayerData.reviveTokenCount(data: PlayerData, required: number): number
	local count = 0
	for tier = required, #data.reviveTokens do
		count += data.reviveTokens[tier]
	end
	return count
end

-- Spends a paid revive for a revive that costs tier `required`: the lowest tier that is allowed. False when
-- there is none.
function PlayerData.useReviveToken(data: PlayerData, required: number): boolean
	for tier = required, #data.reviveTokens do
		if data.reviveTokens[tier] > 0 then
			data.reviveTokens[tier] -= 1
			return true
		end
	end
	return false
end

-- Adds bought rotations.
function PlayerData.addRotations(data: PlayerData, count: number)
	data.rotations += count
end

-- Adds Robux the player gave through a donation product.
function PlayerData.addDonation(data: PlayerData, robux: number)
	data.robuxDonated = math.min(data.robuxDonated + math.max(robux, 0), MAX_DONATED)
end

-- Spends one bought rotation. False when there is none.
function PlayerData.useRotation(data: PlayerData): boolean
	if data.rotations <= 0 then
		return false
	end
	data.rotations -= 1
	return true
end

return PlayerData
