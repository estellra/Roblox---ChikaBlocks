--!strict
-- Opens the Support screen from the menu and fills it with what the server last read (the Supporters board is
-- read together with the leaderboards). Each opening asks for the latest copy; until it arrives the previous one
-- stays up. Choosing a tier only tells the server which one: it opens the purchase prompt and, once the donation
-- is granted, says so with Donated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SupportView = require("../Views/SupportView")

local REFRESH_AFTER_DONATION_SECONDS = 5 -- the board is read again a few seconds after a donation

local SupportController = {}

local view: SupportView.SupportView? = nil
local onClosed: (() -> ())? = nil

function SupportController.close()
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
function SupportController.open(closed: () -> ())
	if not view then
		return
	end
	onClosed = closed
	view:open()
	Net.RequestLeaderboard:FireServer()
end

function SupportController.isOpen(): boolean
	return view ~= nil and view:isOpen()
end

-- For the Studio debug bridge.
function SupportController.describe(): string
	return if view then view:describe() else "not started"
end

function SupportController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local support = SupportView.new(playerGui, SupportController.close, function(tier: number)
		Net.RequestDonate:FireServer(tier)
	end)
	view = support
	Net.Leaderboard.OnClientEvent:Connect(function(snapshot: SupportView.Snapshot)
		support:setSnapshot(snapshot)
	end)
	Net.Donated.OnClientEvent:Connect(function(amount: number, total: number)
		support:showThanks(amount, total)
		task.delay(REFRESH_AFTER_DONATION_SECONDS, function()
			if support:isOpen() then
				Net.RequestLeaderboard:FireServer()
			end
		end)
	end)
end

return SupportController
