--!strict
-- Shows and plays the player's run. The server owns the run (GameService); this controller predicts each
-- move on a local copy of the session so the board reacts instantly, sends the move, and checks the
-- server's answer. Sets of pieces only come from the server. When the two disagree, the server's full
-- state replaces the local copy.
-- Runs start on request (startRun, from the menu or "Play again"). Other controllers drive the game through
-- tryPlace() and listen through the on* functions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameSession = require(ReplicatedStorage.Shared.GameSession)
local Net = require(ReplicatedStorage.Shared.Net)
local Pieces = require(ReplicatedStorage.Shared.Pieces)

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

export type RunMode = "normal" | "tutorial"
-- What the server sends with Profile (see GameService.Profile).
export type Profile = { best: number, gamesPlayed: number, tutorialDone: boolean }

-- What the server sends with GameState (see GameRuns.RunState).
type RunState = { runId: number, mode: RunMode, best: number, session: GameSession.Snapshot }
type Prediction = { score: number, isOver: boolean }

local IS_STUDIO = RunService:IsStudio()
local START_RETRY_SECONDS = 3 -- ask again if the server hasn't answered StartGame by then
local CONFIRM_TIMEOUT_SECONDS = 2 -- ask for the full state if a move is still unconfirmed by then

local GameController = {}

local session: GameSession.GameSession
local runId = 0 -- 0 until the server starts the first run
local runMode: RunMode = "normal"
local views: Views? = nil
local profile: Profile? = nil
local best = 0
local bestBeforeRun = 0 -- best when the current run started, to tell a new best apart
local gameOverToken = 0 -- bumped whenever the session is replaced so a pending game over panel never opens
local startToken = 0 -- identifies the latest StartGame request, for the retry
local predictions: { [number]: Prediction } = {} -- by move index, until the server confirms the move

local sessionReplacedListeners: { () -> () } = {}
local movePlayedListeners: { (result: GameSession.PlaceResult) -> () } = {}
local profileListeners: { (profile: Profile) -> () } = {}
local menuRequestedListeners: { () -> () } = {}

local function notify<T...>(listeners: { (T...) -> () }, ...: T...)
	for _, listener in listeners do
		task.spawn(listener, ...)
	end
end

-- The client never deals: new sets arrive from the server with MoveResult.
local function noSet(_board: any, _score: number, _reason: any): { Pieces.Piece }?
	return nil
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

local function hideGameOver()
	gameOverToken += 1
	if views then
		views.board:setNoMoves(false)
		views.hud:hideGameOver()
	end
end

local function replaceSession(newSession: GameSession.GameSession)
	session = newSession
	table.clear(predictions)
	hideGameOver()
	render()
	notify(sessionReplacedListeners)
	if session.isOver then
		presentGameOver(0)
	end
end

local function requestStart(mode: RunMode)
	startToken += 1
	local token = startToken
	Net.StartGame:FireServer(mode)
	task.delay(START_RETRY_SECONDS, function()
		if token == startToken then
			requestStart(mode)
		end
	end)
end

local function onGameState(state: RunState, reason: string)
	if reason == "start" then
		startToken += 1 -- answered; cancels the retry
		bestBeforeRun = state.best
	elseif IS_STUDIO then
		warn(`[ChikaBlock] resynced with the server at move {state.session.moveCount}`)
	end
	runId = state.runId
	runMode = state.mode
	best = math.max(best, state.best, state.session.score)
	replaceSession(GameSession.fromSnapshot(state.session, noSet))
end

local function onMoveResult(
	resultRunId: number,
	moveIndex: number,
	score: number,
	set: { string }?,
	isOver: boolean,
	serverBest: number
)
	if resultRunId ~= runId then
		return -- answer for an older run
	end
	best = math.max(best, serverBest)
	local predicted = predictions[moveIndex]
	predictions[moveIndex] = nil

	local expectedOver = predicted and predicted.isOver
	if set then
		local pieces = {}
		for i, id in set do
			pieces[i] = Pieces.BY_ID[id]
		end
		if not session:receiveSet(pieces) then
			Net.RequestState:FireServer()
			return
		end
		render()
		expectedOver = session.isOver -- the new set decides whether the run goes on
		if session.isOver then
			presentGameOver(Theme.Motion.GameOverDelay)
		end
	end
	if not predicted or predicted.score ~= score or expectedOver ~= isOver then
		Net.RequestState:FireServer()
	end
end

local function onProfile(newProfile: Profile)
	profile = newProfile
	best = math.max(best, newProfile.best)
	render()
	notify(profileListeners, newProfile)
end

function GameController.init(_self: any)
	-- Placeholder until the server's first state arrives: empty board, waiting for a set.
	session = GameSession.new(noSet)
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
		end, function()
			GameController.requestMenu()
		end),
	}
	Net.GameState.OnClientEvent:Connect(onGameState)
	Net.MoveResult.OnClientEvent:Connect(onMoveResult)
	Net.Profile.OnClientEvent:Connect(onProfile)
	render()
	Net.RequestProfile:FireServer()
end

-- Asks the server for a new run in `mode`; the board switches over when its state arrives.
function GameController.startRun(mode: RunMode)
	hideGameOver()
	requestStart(mode)
end

-- "Play again": a normal run, also after the tutorial.
function GameController.restart()
	GameController.startRun("normal")
end

-- Closes the game over panel and asks for the main menu (MenuController listens).
function GameController.requestMenu()
	hideGameOver()
	notify(menuRequestedListeners)
end

-- Plays a move from the tray right away and sends it to the server. Returns nil (and changes nothing)
-- when the move is invalid.
function GameController.tryPlace(slot: unknown, x: unknown, y: unknown): GameSession.PlaceResult?
	local moveIndex = session.moveCount
	local result = session:place(slot, x, y)
	if result then
		local prediction = { score = session.score, isOver = session.isOver }
		predictions[moveIndex] = prediction
		Net.PlacePiece:FireServer(runId, moveIndex, slot, x, y)
		-- A dropped move (e.g. rate limited) would otherwise leave the client waiting forever, for instance
		-- for a set the server never deals.
		task.delay(CONFIRM_TIMEOUT_SECONDS, function()
			if predictions[moveIndex] == prediction then
				Net.RequestState:FireServer()
			end
		end)
		best = math.max(best, session.score)
		if views then
			views.board:playMoveEffects(result) -- needs the board as drawn before this move
		end
		render()
		if views then
			views.hud:showGain(result)
		end
		notify(movePlayedListeners, result)
		if result.isOver then
			presentGameOver(Theme.Motion.GameOverDelay)
		end
	end
	return result
end

-- Called whenever the session is replaced (new run or resync), e.g. so an in-progress drag is cancelled.
function GameController.onSessionReplaced(callback: () -> ())
	table.insert(sessionReplacedListeners, callback)
end

-- Called after each move the player makes (before the server confirms it).
function GameController.onMovePlayed(callback: (result: GameSession.PlaceResult) -> ())
	table.insert(movePlayedListeners, callback)
end

-- Called whenever the server sends the saved profile.
function GameController.onProfileChanged(callback: (profile: Profile) -> ())
	table.insert(profileListeners, callback)
end

-- Called when the player asks for the main menu.
function GameController.onMenuRequested(callback: () -> ())
	table.insert(menuRequestedListeners, callback)
end

function GameController.getSession(): GameSession.GameSession
	return session
end

function GameController.getRunId(): number
	return runId
end

function GameController.getRunMode(): RunMode
	return runMode
end

-- nil until the server's first Profile arrives.
function GameController.getProfile(): Profile?
	return profile
end

function GameController.getBest(): number
	return best
end

-- nil until start() has built the UI.
function GameController.getViews(): Views?
	return views
end

return GameController
