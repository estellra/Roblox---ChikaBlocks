--!strict
-- The rules for changing a player's rank data (`data.pvp`, see PlayerData) around ranked matches and seasons
-- (docs/PHASE6.md, M25). Pure, so Lune can test it; the PVP service calls it with the live data.
--
-- Leaving a match can't dodge a loss: when a ranked match starts, open() writes the change each result would bring
-- into `pending`. A match that ends normally is settled with close(); a player who leaves is settled with forfeit()
-- before their data is released; data that left the server with `pending` still in it (a crash, or the session taken
-- by another server) is settled as a loss by settleStale() the next time it loads. A match cancelled by a planned
-- shutdown is voided: no change. Settling needs the match id, so the same match is never counted twice.
--
-- Seasons are rolled over lazily: rollSeason() runs when data with an older season id is next used.

local Elo = require("./Elo")
local PlayerData = require("./PlayerData")
local Seasons = require("./Seasons")

type PvpData = PlayerData.PvpData
type PvpPending = PlayerData.PvpPending

export type Result = "win" | "draw" | "loss"

-- Config.PVP.RATING.
export type Settings = Elo.Settings & {
	START: number,
	SEASON_PULL: number,
	MEDAL_MIN_GAMES: number,
}

local PvpRating = {}
PvpRating.__index = PvpRating

export type PvpRating =
	typeof(setmetatable({} :: { settings: Settings, tiers: Seasons.Tiers, elo: Elo.Elo }, PvpRating))

local function round(value: number): number
	return if value >= 0 then math.floor(value + 0.5) else -math.floor(-value + 0.5)
end

--- `settings` is Config.PVP.RATING and `tiers` Config.PVP.TIERS (passed in: server and shared code sit in different
--- places in the DataModel).
function PvpRating.new(settings: Settings, tiers: Seasons.Tiers): PvpRating
	return setmetatable({ settings = settings, tiers = tiers, elo = Elo.new(settings) }, PvpRating)
end

--- The player's tier now.
function PvpRating.tier(self: PvpRating, pvp: PvpData): string
	return Seasons.tier(self.tiers, pvp.rating)
end

--- Starts season `seasonId` for this data if it holds an earlier one: records the old season in `lastSeason`, gives
--- its medal (highest tier reached) to a player who played at least MEDAL_MIN_GAMES ranked games in it, and moves the
--- points SEASON_PULL of the way back to START. Data that never played ranked just takes the id. Returns whether the
--- season changed; an id earlier than the data's (another server's clock a little behind) changes nothing.
function PvpRating.rollSeason(self: PvpRating, pvp: PvpData, seasonId: string): boolean
	if pvp.season ~= "" and seasonId <= pvp.season then
		return false
	end
	local settings = self.settings
	local old = pvp.season
	if old ~= "" then
		local tier = Seasons.tier(self.tiers, pvp.peak)
		pvp.lastSeason = { id = old, rating = pvp.rating, peak = pvp.peak, games = pvp.seasonGames, tier = tier }
		if pvp.seasonGames >= settings.MEDAL_MIN_GAMES then
			pvp.medals[old] = { tier = tier }
		end
		pvp.rating = settings.START + round((pvp.rating - settings.START) * settings.SEASON_PULL)
		pvp.peak = pvp.rating
	end
	pvp.season = seasonId
	pvp.seasonGames = 0
	return true
end

--- A ranked match `matchId` starts against an opponent with `opponentRating` points: writes what each result would
--- change into `pending` and returns it. Nil, and nothing changes, while another match is pending (settle it first).
function PvpRating.open(
	self: PvpRating,
	pvp: PvpData,
	matchId: string,
	opponentRating: number,
	now: number
): PvpPending?
	if pvp.pending then
		return nil
	end
	local stakes = self.elo:stakes(pvp.rating, opponentRating, pvp.games)
	local pending = { id = matchId, win = stakes.win, draw = stakes.draw, loss = stakes.loss, at = now }
	pvp.pending = pending
	return pending
end

--- Settles match `matchId` with `result`: applies the change written when it started, counts the game and clears
--- `pending`. Returns the change, or nil (nothing changes) when that match isn't the one pending: an unrated match,
--- or one already settled.
function PvpRating.close(_self: PvpRating, pvp: PvpData, matchId: string, result: Result): number?
	local pending = pvp.pending
	if not pending or pending.id ~= matchId then
		return nil
	end
	local delta = if result == "win" then pending.win elseif result == "draw" then pending.draw else pending.loss
	pvp.rating += delta
	pvp.peak = math.max(pvp.peak, pvp.rating)
	pvp.games += 1
	pvp.seasonGames += 1
	if result == "win" then
		pvp.wins += 1
	elseif result == "draw" then
		pvp.draws += 1
	else
		pvp.losses += 1
	end
	pvp.pending = false
	return delta
end

--- The player left match `matchId` (or dropped): a loss. See close().
function PvpRating.forfeit(self: PvpRating, pvp: PvpData, matchId: string): number?
	return self:close(pvp, matchId, "loss")
end

--- Match `matchId` was cancelled (planned shutdown): clears `pending` without changing anything else. Returns
--- whether that match was pending.
function PvpRating.void(_self: PvpRating, pvp: PvpData, matchId: string): boolean
	local pending = pvp.pending
	if not pending or pending.id ~= matchId then
		return false
	end
	pvp.pending = false
	return true
end

--- Data just loaded: a match still pending was left without being settled, so it counts as a loss. Returns the
--- change, or nil when nothing was pending.
function PvpRating.settleStale(self: PvpRating, pvp: PvpData): number?
	local pending = pvp.pending
	if not pending then
		return nil
	end
	return self:close(pvp, pending.id, "loss")
end

return PvpRating
