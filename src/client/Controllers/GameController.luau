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
local Theme = require("../Views/Theme")
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
local bestBeforeRun = 0 -- best when the current run started, to tell a new best apart
local gameOverToken = 0 -- bumped on restart so a pending game over panel for the old run never opens
local sessionReplacedListeners: { () -> () } = {}

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
end

-- Dims the board with "No moves left" right away, then opens the panel after `delaySeconds`, so the last
-- move's effects stay visible and the player can see why the run ended.
local function presentGameOver(delaySeconds: number)
	if not views then
		return
	end
	gameOverToken += 1
	local token = gameOverToken
	views.board:setNoMoves(true)
	task.delay(delaySeconds, function()
		if token ~= gameOverToken or not views or not session.isOver then
			return
		end
		local isNewBest = bestBeforeRun > 0 and session.score > bestBeforeRun
		views.hud:showGameOver(session.score, best, isNewBest)
	end)
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
		hud = Hud.new(gui.hudArea, gui.boardArea, gui.overlay, gui.overlayBackdrop, function()
			GameController.restart()
		end),
	}
	render()
	if session.isOver then
		presentGameOver(0)
	end
end

-- Plays a move from the tray. Returns nil (and changes nothing) when the move is invalid.
function GameController.tryPlace(slot: unknown, x: unknown, y: unknown): GameSession.PlaceResult?
	local result = session:place(slot, x, y)
	if result then
		best = math.max(best, session.score)
		if views then
			views.board:playMoveEffects(result) -- needs the board as drawn before this move
		end
		render()
		if views then
			views.hud:showGain(result)
		end
		if result.isOver then
			presentGameOver(Theme.Motion.GameOverDelay)
		end
	end
	return result
end

function GameController.restart()
	session = newSession()
	bestBeforeRun = best
	gameOverToken += 1
	if views then
		views.board:setNoMoves(false)
		views.hud:hideGameOver()
	end
	render()
	for _, listener in sessionReplacedListeners do
		task.spawn(listener)
	end
end

-- Called after restart() replaces the session (e.g. so an in-progress drag can be cancelled).
function GameController.onSessionReplaced(callback: () -> ())
	table.insert(sessionReplacedListeners, callback)
end

function GameController.getSession(): GameSession.GameSession
	return session
end

-- nil until start() has built the UI.
function GameController.getViews(): Views?
	return views
end

return GameController
