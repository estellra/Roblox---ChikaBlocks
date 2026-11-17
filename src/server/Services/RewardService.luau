--!strict
-- Milestone rewards: claims the milestones a player has reached (Progression decides which) and awards their
-- Roblox badges. A badge award that fails is retried the next time sync() runs for that player, which is at
-- least every time they join.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerData = require("../PlayerData")
local Progression = require(ReplicatedStorage.Shared.Progression)

local IS_STUDIO = RunService:IsStudio()

local RewardService = {}

local awarding: { [Player]: { [string]: boolean } } = {} -- badge awards in flight, by milestone id

local function award(player: Player, data: PlayerData.PlayerData, milestone: Progression.Milestone)
	local ok, result = pcall(function(): boolean
		if BadgeService:UserHasBadgeAsync(player.UserId, milestone.badgeId) then
			return true
		end
		return BadgeService:AwardBadgeAsync(player.UserId, milestone.badgeId)
	end)
	if ok and result then
		data.badgesAwarded[milestone.id] = true
	elseif IS_STUDIO then
		warn(`[ChikaBlock] badge for {milestone.id} not awarded yet: {if ok then "refused" else result}`)
	end
end

-- Awards badge `badgeId` for `key` (e.g. "rank_Gold") unless the data says it was awarded already or it is on its
-- way; remembered in data.badgesAwarded[key] once Roblox confirms. A badgeId of 0 (not created yet) does nothing.
function RewardService.awardBadge(player: Player, data: PlayerData.PlayerData, key: string, badgeId: number)
	if badgeId == 0 or data.badgesAwarded[key] then
		return
	end
	local inFlight = awarding[player]
	if not inFlight then
		inFlight = {}
		awarding[player] = inFlight
	end
	if inFlight[key] then
		return
	end
	inFlight[key] = true
	task.spawn(function()
		award(player, data, { id = key, badgeId = badgeId } :: any)
		inFlight[key] = nil
	end)
end

-- Claims newly reached milestones and starts awarding any badge still owed. Returns the milestones claimed
-- by this call, in rank order.
function RewardService.sync(player: Player, data: PlayerData.PlayerData): { Progression.Milestone }
	local claimed = Progression.claimMilestones(data)
	local inFlight = awarding[player]
	if not inFlight then
		inFlight = {}
		awarding[player] = inFlight
	end
	for _, milestone in Progression.pendingBadges(data) do
		if not inFlight[milestone.id] then
			inFlight[milestone.id] = true
			task.spawn(function()
				award(player, data, milestone)
				inFlight[milestone.id] = nil
			end)
		end
	end
	return claimed
end

function RewardService.start(_self: any)
	Players.PlayerRemoving:Connect(function(player: Player)
		awarding[player] = nil
	end)
end

return RewardService
