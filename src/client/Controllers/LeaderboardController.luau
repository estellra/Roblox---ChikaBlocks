--!strict
-- Opens the leaderboard screen from the menu and fills it with what the server last read (it refreshes
-- once a minute). Each opening asks for the latest copy; until it arrives the previous one stays up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local LeaderboardView = require("../Views/LeaderboardView")

local LeaderboardController = {}

local view: LeaderboardView.LeaderboardView? = nil
local onClosed: (() -> ())? = nil

function LeaderboardController.close()
	if view and view:isOpen() then
		view:close()
		local callback = onClosed
		onClosed = nil
		if callback then
			callback()
		end
	end
end

-- Opens the screen; `closed` runs when the player goes back.
function LeaderboardController.open(closed: () -> ())
	if not view then
		return
	end
	onClosed = closed
	view:open()
	Net.RequestLeaderboard:FireServer()
end

function LeaderboardController.isOpen(): boolean
	return view ~= nil and view:isOpen()
end

-- For the Studio debug bridge.
function LeaderboardController.describe(): string
	return if view then view:describe() else "not started"
end

function LeaderboardController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local leaderboard = LeaderboardView.new(playerGui, LeaderboardController.close)
	view = leaderboard
	-- The Rank tab shows where ranked is open (the server says; see PvpService).
	local function refreshRank()
		leaderboard:setRankVisible(ReplicatedStorage:GetAttribute("RankedOpen") == true)
	end
	refreshRank()
	ReplicatedStorage:GetAttributeChangedSignal("RankedOpen"):Connect(refreshRank)
	Net.Leaderboard.OnClientEvent:Connect(function(snapshot: LeaderboardView.Snapshot)
		leaderboard:setSnapshot(snapshot)
	end)
end

return LeaderboardController
