--!strict
-- Leaderboard rules: which boards exist, the OrderedDataStore each one uses, the weekly stats behind the
-- "This week" boards, and how a stat and the player's title share one integer. Pure Luau so Lune can test
-- it; LeaderboardService makes the DataStore calls.
--
-- Boards are "<Board>_<period>": Highscore_all, Highscore_week, Level_all, Level_week. The weekly Level board
-- ranks the EXP earned this week (a level never resets). Weekly stores carry the ISO week in their name
-- ("Highscore_2026W45"), so a new week starts with empty boards on its own.
--
-- A stored value is stat * TITLE_SLOTS + title index (0 = no title; see Progression.titleIndex): the title
-- shows next to the name without reading every player's profile, and the order is still by stat.

export type Weekly = { week: string, bestScore: number, exp: number }

-- The parts of PlayerData this module reads and changes.
export type Stats = { bestScore: number, level: number, weekly: Weekly }

local TITLE_SLOTS = 100
local DAY = 86400

local Leaderboards = {}

Leaderboards.BOARDS = table.freeze({ "Highscore", "Level" })
Leaderboards.PERIODS = table.freeze({ "all", "week" })
Leaderboards.TOP = 50 -- entries shown per board
Leaderboards.TITLE_SLOTS = TITLE_SLOTS

-- ISO 8601 week of a UTC time, like "2026W45". Weeks start on Monday; week 1 holds the year's first Thursday.
function Leaderboards.weekKey(time: number): string
	local date = os.date("!*t", time) :: any
	local weekday = (date.wday + 5) % 7 + 1 -- 1 = Monday ... 7 = Sunday
	local thursday = os.date("!*t", time + (4 - weekday) * DAY) :: any
	return string.format("%dW%02d", thursday.year, math.floor((thursday.yday - 1) / 7) + 1)
end

-- The store behind a board key at `time`. Studio uses separate stores so tests never reach live boards.
function Leaderboards.storeName(key: string, time: number, isStudio: boolean): string
	local board, period = string.match(key, "^(%a+)_(%a+)$")
	assert(board and period, `bad board key {key}`)
	local name = if period == "week" then `{board}_{Leaderboards.weekKey(time)}` else board
	return if isStudio then `{name}_Dev` else name
end

function Leaderboards.encode(stat: number, titleIndex: number): number
	return math.floor(stat) * TITLE_SLOTS + math.clamp(titleIndex, 0, TITLE_SLOTS - 1)
end

-- Returns the stat and the title index.
function Leaderboards.decode(value: number): (number, number)
	return value // TITLE_SLOTS, value % TITLE_SLOTS
end

-- Starts the weekly stats over when the week has changed.
function Leaderboards.rollWeek(weekly: Weekly, time: number)
	local week = Leaderboards.weekKey(time)
	if weekly.week ~= week then
		weekly.week = week
		weekly.bestScore = 0
		weekly.exp = 0
	end
end

-- Counts a run's current score and newly earned EXP toward this week.
function Leaderboards.recordRun(weekly: Weekly, time: number, score: number, expGained: number)
	Leaderboards.rollWeek(weekly, time)
	weekly.bestScore = math.max(weekly.bestScore, score)
	weekly.exp += math.max(expGained, 0)
end

-- What each board should hold for this player now, by board key. Boards where the player has nothing to
-- show (no score, still level 1, nothing this week) are left out so they don't fill up with zeros.
function Leaderboards.values(stats: Stats, titleIndex: number, time: number): { [string]: number }
	local values: { [string]: number } = {}
	if stats.bestScore > 0 then
		values.Highscore_all = Leaderboards.encode(stats.bestScore, titleIndex)
	end
	if stats.level > 1 then
		values.Level_all = Leaderboards.encode(stats.level, titleIndex)
	end
	local weekly = stats.weekly
	if weekly.week == Leaderboards.weekKey(time) then
		if weekly.bestScore > 0 then
			values.Highscore_week = Leaderboards.encode(weekly.bestScore, titleIndex)
		end
		if weekly.exp > 0 then
			values.Level_week = Leaderboards.encode(weekly.exp, titleIndex)
		end
	end
	return values
end

-- The values that differ from what was last written, i.e. the writes to make.
function Leaderboards.changes(values: { [string]: number }, written: { [string]: number }): { [string]: number }
	local changes: { [string]: number } = {}
	for key, value in values do
		if written[key] ~= value then
			changes[key] = value
		end
	end
	return changes
end

return Leaderboards
