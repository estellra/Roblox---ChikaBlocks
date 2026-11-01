--!strict
-- Level, EXP and milestone rewards. Pure Luau shared by both sides: the server changes saved data with it,
-- the client uses it to draw the EXP bar and the player's title. Numbers and milestones live in Config.
--
-- Milestones are worked out from the saved best score and level, never from events, so a milestone or a
-- reward added later is also given to players who reached it before.
local Config = require("./Config")

export type Milestone = {
	id: string,
	kind: "score" | "level",
	threshold: number,
	title: string,
	badgeId: number, -- 0 until the badge is created in Creator Hub
}

-- The parts of PlayerData this module reads and changes.
export type ProgressData = {
	bestScore: number,
	level: number,
	exp: number, -- progress toward the next level
	milestonesClaimed: { [string]: boolean },
	badgesAwarded: { [string]: boolean },
}

local Progression = {}

Progression.MILESTONES = Config.MILESTONES :: { Milestone }

-- EXP a run has earned once its score reaches `score`.
function Progression.expForScore(score: number): number
	return math.floor(math.max(score, 0) / Config.EXP_SCORE_DIVISOR)
end

-- EXP needed to go from `level` to the next one.
function Progression.expToNext(level: number): number
	return Config.LEVEL_EXP_BASE + Config.LEVEL_EXP_STEP * (level - 1)
end

-- Adds EXP, levelling up as many times as it covers. Returns how many levels were gained.
function Progression.addExp(data: ProgressData, amount: number): number
	if amount <= 0 then
		return 0
	end
	local gained = 0
	data.exp += amount
	while data.exp >= Progression.expToNext(data.level) do
		data.exp -= Progression.expToNext(data.level)
		data.level += 1
		gained += 1
	end
	return gained
end

local function reached(data: ProgressData, milestone: Milestone): boolean
	local value = if milestone.kind == "score" then data.bestScore else data.level
	return value >= milestone.threshold
end

-- Claims every milestone the player has reached but not claimed yet; returns those, in table order.
function Progression.claimMilestones(data: ProgressData): { Milestone }
	local claimed = {}
	for _, milestone in Progression.MILESTONES do
		if not data.milestonesClaimed[milestone.id] and reached(data, milestone) then
			data.milestonesClaimed[milestone.id] = true
			table.insert(claimed, milestone)
		end
	end
	return claimed
end

-- Position in MILESTONES of the title to show: the claimed milestone that comes last (the table is ordered
-- by rank). 0 when nothing is claimed. Leaderboards store this number next to the stat.
function Progression.titleIndex(milestonesClaimed: { [string]: boolean }): number
	local index = 0
	for i, milestone in Progression.MILESTONES do
		if milestonesClaimed[milestone.id] then
			index = i
		end
	end
	return index
end

-- The title to show, if any.
function Progression.title(milestonesClaimed: { [string]: boolean }): string?
	local milestone = Progression.MILESTONES[Progression.titleIndex(milestonesClaimed)]
	return if milestone then milestone.title else nil
end

-- Claimed milestones whose badge exists but hasn't been awarded yet (a failed award is retried later).
function Progression.pendingBadges(data: ProgressData): { Milestone }
	local pending = {}
	for _, milestone in Progression.MILESTONES do
		if data.milestonesClaimed[milestone.id] and milestone.badgeId > 0 and not data.badgesAwarded[milestone.id] then
			table.insert(pending, milestone)
		end
	end
	return pending
end

return Progression
