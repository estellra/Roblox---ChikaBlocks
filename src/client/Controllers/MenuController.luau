--!strict
-- Main menu flow: shown when the game loads and whenever the player picks Menu on the game over panel.
-- Play starts the tutorial run until the player has finished it once, then normal runs; How to play always
-- starts the tutorial run.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameController = require("./GameController")
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

function MenuController.show()
	if not menu then
		return
	end
	if GameController.getProfile() then
		menu:setReady(GameController.getBest()) -- the best may have gone up during the last run
	end
	menu:show()
end

function MenuController.hide()
	if menu then
		menu:hide()
	end
end

function MenuController.isOpen(): boolean
	return menu ~= nil and menu:isOpen()
end

function MenuController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = MenuView.new(playerGui, function()
		MenuController.play()
	end, function()
		MenuController.play("tutorial")
	end)
	menu = view
	GameController.onProfileChanged(function()
		view:setReady(GameController.getBest())
	end)
	GameController.onMenuRequested(MenuController.show)
	if GameController.getProfile() then
		view:setReady(GameController.getBest()) -- arrived before this controller started
	end
	MenuController.show()
	Net.ClientReady:FireServer()
end

return MenuController
