--!strict
-- Owns the local GameSession (phase 1 runs entirely on the client) and keeps the views in sync with it.
-- Other controllers drive the game through tryPlace() and restart().
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSession = require(ReplicatedStorage.Shared.GameSession)
local Generator = require(ReplicatedStorage.Shared.Generator)
local Rng = require(ReplicatedStorage.Shared.Rng)

local BoardView = require("../Views/BoardView")
local Gui = require("../Views/Gui")
local Hud = require("../Views/Hud")
local TrayView = require("../Views/TrayView")

export type Views = {
	gui: Gui.Gui,
	board: BoardView.BoardView,
	tray: TrayView.TrayView,
	hud: Hud.Hud,
}

local GameController = {}

local session: GameSession.GameSession
local views: Views? = nil
local best = 0 -- best score this play session; saved scores come in phase 2

local function newSession(): GameSession.GameSession
	-- Phase 1 seeds on the client; in phase 2 the server keeps the seed.
	local seed = Random.new():NextInteger(1, 2 ^ 31 - 1)
	return GameSession.new(Generator.newSource(Rng.new(seed)))
end

local function render()
	if not views then
		return
	end
	views.board:render(session.board)
	views.tray:render(session.tray)
	views.hud:setScore(session.score, best)
	if session.isOver then
		views.hud:showGameOver(session.score, best)
	else
		views.hud:hideGameOver()
	end
end

function GameController.init(_self: any)
	session = newSession()
end

function GameController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local gui = Gui.create(playerGui)
	views = {
		gui = gui,
		board = BoardView.new(gui.boardArea),
		tray = TrayView.new(gui.trayArea),
		hud = Hud.new(gui.hudArea, gui.overlay, function()
			GameController.restart()
		end),
	}
	render()
end

-- Plays a move from the tray. Returns nil (and changes nothing) when the move is invalid.
function GameController.tryPlace(slot: unknown, x: unknown, y: unknown): GameSession.PlaceResult?
	local result = session:place(slot, x, y)
	if result then
		best = math.max(best, session.score)
		render()
	end
	return result
end

function GameController.restart()
	session = newSession()
	render()
end

function GameController.getSession(): GameSession.GameSession
	return session
end

-- nil until start() has built the UI.
function GameController.getViews(): Views?
	return views
end

return GameController
