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

--- When season `id` starts (Unix time, UTC).
function Seasons.startOf(id: string): number
	local year, month = string.match(id, "^(%d+)M(%d+)$")
	assert(year and month, `bad season id {id}`)
	return os.time({
		year = tonumber(year) :: number,
		month = tonumber(month) :: number,
		day = 1,
		hour = 0,
		min = 0,
		sec = 0,
		isdst = false,
	}) - Seasons.utcOffset()
end

--- How many seconds local time is ahead of UTC on this machine (os.time reads a date as local time).
function Seasons.utcOffset(): number
	local now = os.time()
	local utc = os.date("!*t", now) :: any
	utc.isdst = false
	return now - os.time(utc)
end

--- The season after `id`.
function Seasons.following(id: string): string
	local year, month = string.match(id, "^(%d+)M(%d+)$")
	assert(year and month, `bad season id {id}`)
	local y, m = tonumber(year) :: number, tonumber(month) :: number
	m += 1
	if m > 12 then
		y, m = y + 1, 1
	end
	return string.format("%dM%02d", y, m)
end

--- The season before `id`.
function Seasons.previous(id: string): string
	local year, month = string.match(id, "^(%d+)M(%d+)$")
	assert(year and month, `bad season id {id}`)
	local y, m = tonumber(year) :: number, tonumber(month) :: number
	m -= 1
	if m < 1 then
		y, m = y - 1, 12
	end
	return string.format("%dM%02d", y, m)
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

--- The last day of season `id`, as the Rank tab says it: "Dec 31".
function Seasons.lastDayText(id: string): string
	local last = os.date("!*t", Seasons.startOf(Seasons.following(id)) - 1) :: any
	return `{MONTHS[last.month]} {last.day}`
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
