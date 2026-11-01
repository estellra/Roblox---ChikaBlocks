--!strict
-- Main menu flow: shown when the game loads and whenever the player picks Menu on the game over panel.
-- Play starts the tutorial run until the player has finished it once, then normal runs; How to play always
-- starts the tutorial run.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameController = require("./GameController")
local LeaderboardController = require("./LeaderboardController")
local MenuView = require("../Views/MenuView")

local MenuController = {}

local menu: MenuView.MenuView? = nil

-- Leaves the menu and starts a run: `mode` if given, otherwise the tutorial until it has been done once.
function MenuController.play(mode: GameController.RunMode?)
	local profile = GameController.getProfile()
	local runMode: GameController.RunMode = mode or if profile and profile.tutorialDone then "normal" else "tutorial"
	MenuController.hide()
	GameController.startRun(runMode)
end

local function refresh(view: MenuView.MenuView)
	local profile = GameController.getProfile()
	if profile then
		view:setReady(GameController.getBest(), profile.level, profile.title)
	end
end

function MenuController.show()
	if not menu then
		return
	end
	refresh(menu) -- the best may have gone up during the last run
	menu:show()
end

function MenuController.hide()
	if menu then
		menu:hide()
	end
end

-- Swaps the menu for the leaderboard screen; going back brings the menu back.
function MenuController.openLeaderboard()
	MenuController.hide()
	LeaderboardController.open(MenuController.show)
end

-- True on the menu and on screens opened from it (the leaderboard).
function MenuController.isOpen(): boolean
	return (menu ~= nil and menu:isOpen()) or LeaderboardController.isOpen()
end

function MenuController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = MenuView.new(
		playerGui,
		function()
			MenuController.play()
		end,
		MenuController.openLeaderboard,
		function()
			MenuController.play("tutorial")
		end
	)
	menu = view
	GameController.onProfileChanged(function()
		refresh(view)
	end)
	GameController.onMenuRequested(MenuController.show)
	refresh(view) -- the profile may have arrived before this controller started
	MenuController.show()
	Net.ClientReady:FireServer()
end

return MenuController
