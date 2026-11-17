--!strict
-- Who may join the ranked queue, and what a ranked match does to the players' rank data (docs/PHASE6.md, M27, BO and
-- BP). Pure Luau so Lune can test it.

local PlayerData = require("./PlayerData")
local PvpRating = require("./PvpRating")

-- Why a player can't queue, as the queue screen says it.
export type Refusal = "off" | "private" | "tutorial" | "level" | "busy" | "loading"

export type Eligibility = {
	enabled: boolean, -- PVP and ranked are on (or Studio)
	privateServer: boolean,
	data: PlayerData.PlayerData?, -- nil while it loads
	minLevel: number,
	busy: boolean, -- in a room or a match
}

local RankedRules = {}

--- Whether the player may join the queue now, and if not, why.
function RankedRules.canQueue(info: Eligibility): (boolean, Refusal?)
	if not info.enabled then
		return false, "off"
	elseif info.privateServer then
		return false, "private" -- a private server could match its owner with their own second account
	end
	local data = info.data
	if not data then
		return false, "loading"
	elseif not data.tutorialDone then
		return false, "tutorial"
	elseif data.level < info.minLevel then
		return false, "level"
	elseif info.busy then
		return false, "busy"
	end
	return true, nil
end

--- Whether a match of this kind changes rank: only ranked matches, and only while the pair's daily count allows.
function RankedRules.isRated(kind: string, pairRated: boolean): boolean
	return kind == "ranked" and pairRated
end

--- Settles a player's rated match `matchId` as it ended: a cancelled match is voided, any other is closed with the
--- player's result. Returns the change in points (nil when nothing was pending for it, or it was voided).
function RankedRules.settle(
	rating: PvpRating.PvpRating,
	pvp: PlayerData.PvpData,
	matchId: string,
	reason: string,
	result: PvpRating.Result?
): number?
	if reason == "cancelled" or result == nil then
		rating:void(pvp, matchId)
		return nil
	end
	return rating:close(pvp, matchId, result)
end

return RankedRules
