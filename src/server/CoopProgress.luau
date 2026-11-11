--!strict
-- What a Co-op run gives each of its players, as pure rules for Lune to test; CoopService applies them as moves
-- arrive. EXP is credited as the team's score grows, so a run left halfway still counts; each player earns a share
-- of what a solo run with that score would (Config.COOP.EXP_SHARE). The score that counts for the player's Co-op
-- best is the run's counted score, which stops growing once the partner has left. None of it touches the solo
-- record, the solo games played or the solo weekly best.
local PlayerData = require("./PlayerData")

type PlayerData = PlayerData.PlayerData

-- One player's progress through one Co-op run.
export type Progress = {
	expGranted: number, -- EXP credited so far in this run
	levelBefore: number, -- level and EXP when the run started, for the Game Over bar
	expBefore: number,
	titles: { string }, -- unlocked during the run, in rank order
	counted: boolean, -- the run has been counted in coopGamesPlayed
}

-- What the Game Over panel shows (the same shape as a solo run's rewards).
export type Rewards = {
	expGained: number,
	levelBefore: number,
	expBefore: number,
	level: number,
	exp: number,
	titles: { string },
}

local CoopProgress = {}

function CoopProgress.start(data: PlayerData): Progress
	return { expGranted = 0, levelBefore = data.level, expBefore = data.exp, titles = {}, counted = false }
end

-- A move was accepted: the team is at `teamScore`, of which `countedScore` counts for records. Credits the EXP the
-- score has earned since the last move, raises the Co-op best, and returns the EXP credited now. `progression` is
-- the shared Progression module (passed in: server and shared code sit in different places in the DataModel).
function CoopProgress.credit(
	progression: any,
	progress: Progress,
	data: PlayerData,
	teamScore: number,
	countedScore: number
): number
	local earned = progression.expForCoopScore(teamScore)
	local gained = 0
	if earned > progress.expGranted then
		gained = earned - progress.expGranted
		progression.addExp(data, gained)
		progress.expGranted = earned
	end
	PlayerData.recordCoopScore(data, countedScore)
	return gained
end

-- The run has ended for this player, or its score has been fixed by the partner leaving: it counts as a Co-op
-- game played, once per run. False when it had already been counted.
function CoopProgress.countGame(progress: Progress, data: PlayerData): boolean
	if progress.counted then
		return false
	end
	progress.counted = true
	PlayerData.recordCoopGame(data)
	return true
end

function CoopProgress.rewards(progress: Progress, data: PlayerData): Rewards
	return {
		expGained = progress.expGranted,
		levelBefore = progress.levelBefore,
		expBefore = progress.expBefore,
		level = data.level,
		exp = data.exp,
		titles = progress.titles,
	}
end

return CoopProgress
