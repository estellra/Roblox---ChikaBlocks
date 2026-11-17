--!strict
-- Ranked seasons and tiers (docs/PHASE6.md, "Mùa và hạng"). A season is a calendar month in UTC, worked out from the
-- clock: nothing to configure or schedule. Pure, so Lune can test it. Tiers come in as Config.PVP.TIERS (passed in:
-- server and shared code sit in different places in the DataModel).

-- Config.PVP.TIERS: lowest first; a player is in the last tier whose `from` their points reach.
export type Tiers = { { id: string, from: number } }

local Seasons = {}

--- The season id of a Unix time, such as "2026M12".
function Seasons.id(time: number): string
	local date = os.date("!*t", time) :: any
	return string.format("%dM%02d", date.year, date.month)
end

--- The tier id for these points.
function Seasons.tier(tiers: Tiers, rating: number): string
	local id = tiers[1].id
	for _, tier in tiers do
		if rating >= tier.from then
			id = tier.id
		end
	end
	return id
end

--- The position of a tier (1 is the lowest), or nil for an unknown id.
function Seasons.tierIndex(tiers: Tiers, tierId: string): number?
	for i, tier in tiers do
		if tier.id == tierId then
			return i
		end
	end
	return nil
end

return Seasons
