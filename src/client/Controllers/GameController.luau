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

local Config = require(ReplicatedStorage.Shared.Config)
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
export type Profile = {
	best: number,
	gamesPlayed: number,
	tutorialDone: boolean,
	level: number,
	exp: number,
	rotations: number, -- bought rotations left
	donated: number, -- Robux given through donation products
	title: string?,
}
export type RunRewards = Hud.RunRewards

-- What the server sends with GameState (see GameRuns.RunState).
type RunState = { runId: number, mode: RunMode, best: number, session: GameSession.Snapshot }
type Prediction = { score: number, isOver: boolean }

local IS_STUDIO = RunService:IsStudio()
local REVIVE_WAIT_SECONDS = 20 -- how long Revive shows "Please wait…" without an answer
local START_RETRY_SECONDS = 3 -- ask again if the server hasn't answered StartGame by then
local ROTATIONS_ASK_GAP_SECONDS = 2 -- the purchase prompt for rotations opens at most this often
local CONFIRM_TIMEOUT_SECONDS = 2 -- ask for the full state if a move is still unconfirmed by then

local GameController = {}

local session: GameSession.GameSession
local runId = 0 -- 0 until the server starts the first run
local runMode: RunMode = "normal"
local views: Views? = nil
local profile: Profile? = nil
local runRewards: RunRewards? = nil -- what the current run earned, once it is over and the server said
local reviveWaitToken = 0 -- identifies the latest Revive press, for its timeout
local rotationsAskedAt = -math.huge -- when the player last asked to buy rotations
local reviveOffer: { runId: number, tokens: number, price: number? }? = nil -- what the server offered after game over
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

-- Tells the tray which pieces can be turned: in a normal run that isn't over, those that look different turned.
local function refreshRotatable()
	if not views then
		return
	end
	local playing = runId > 0 and runMode == "normal" and not session.isOver
	local rotatable: { boolean } = {}
	for slot = 1, Config.PIECES_PER_SET do
		local piece = session.tray[slot]
		rotatable[slot] = playing and piece and Pieces.canRotate(piece) or false
	end
	views.tray:setRotatable(rotatable)
end

local function render()
	if not views then
		return
	end
	views.board:render(session.board)
	views.tray:render(session.tray)
	refreshRotatable()
	views.hud:setScore(session.score, best)
	views.hud:setCombo(session.combo.combo)
end

-- Dims the board with "No moves left" right away, then opens the panel after `delaySeconds`, so the last
-- move's effects stay visible and the player can see why the run ended.
-- Shows the Revive button on the game over panel with what the server offered: a revive already paid for is free,
-- else the price of the next one. No offer (yet) means no button.
local function applyReviveOffer()
	if not views then
		return
	end
	local offer = reviveOffer
	if not offer or offer.runId ~= runId or not session.isOver then
		views.hud:setRevive(nil)
		return
	end
	local text, hint
	if offer.tokens > 0 then
		text = "Revive · Free"
		hint = `You have {offer.tokens} · Clears the center 4×4`
	else
		text = if offer.price then `Revive · R$ {offer.price}` else "Revive"
		hint = "Clears the center 4×4"
	end
	views.hud:setRevive({ text = text, hint = hint })
end

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
		applyReviveOffer()
		if runRewards then
			views.hud:showRewards(runRewards)
		end
	end)
end

local function hideGameOver()
	gameOverToken += 1
	reviveOffer = nil
	if views then
		views.board:setNoMoves(false)
		views.hud:hideGameOver()
		views.hud:setRevive(nil)
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
		runRewards = nil
	elseif reason == "revive" then
		runRewards = nil -- the run goes on; the next game over brings its own rewards
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

-- Usually arrives before the game over panel opens (which waits for the last move's effects).
local function onRunRewards(rewardsRunId: number, rewards: RunRewards)
	if rewardsRunId ~= runId then
		return
	end
	runRewards = rewards
	if views and views.hud:isGameOverOpen() then
		views.hud:showRewards(rewards)
	end
end

-- The server's offer after a game over: how many revives are already paid for, and the price of the next.
local function onReviveOffer(offerRunId: number, offer: { tokens: number, price: number? })
	if offerRunId ~= runId then
		return
	end
	reviveOffer = { runId = offerRunId, tokens = offer.tokens, price = offer.price }
	if views and views.hud:isGameOverOpen() then
		applyReviveOffer()
	end
end

-- The revive did not happen (the purchase was cancelled, or it was not possible): the button is free again.
local function onReviveResult(resultRunId: number, ok: boolean)
	if resultRunId == runId and not ok then
		applyReviveOffer()
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
		tray = TrayView.new(gui.trayArea, function(slot: number)
			GameController.tryRotate(slot)
		end),
		hud = Hud.new(gui.hudArea, gui.boardArea, gui.overlay, gui.overlayBackdrop, {
			onRestart = GameController.restart,
			onMenu = GameController.requestMenu,
			onPause = GameController.pause,
			onResume = GameController.resume,
			onRevive = GameController.requestRevive,
		}),
	}
	local hud = views.hud
	hud:setLayout(gui.getMode())
	gui.onLayoutChanged(function(mode)
		hud:setLayout(mode)
	end)
	Net.GameState.OnClientEvent:Connect(onGameState)
	Net.MoveResult.OnClientEvent:Connect(onMoveResult)
	Net.Profile.OnClientEvent:Connect(onProfile)
	Net.RunRewards.OnClientEvent:Connect(onRunRewards)
	Net.ReviveOffer.OnClientEvent:Connect(onReviveOffer)
	Net.ReviveResult.OnClientEvent:Connect(onReviveResult)
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

-- Asks the server to revive the finished run: free with a revive already paid for, else it opens Roblox's purchase
-- prompt. The server decides the product; nothing happens on screen until it answers.
function GameController.requestRevive()
	local offer = reviveOffer
	if not views or not offer or offer.runId ~= runId or not session.isOver then
		return
	end
	views.hud:setReviveBusy(true)
	Net.RequestRevive:FireServer(runId)
	-- The server answers a refused request, but not one that got lost; the button comes back after a while. (If
	-- the purchase prompt is open, pressing it again is ignored there.)
	reviveWaitToken += 1
	local token = reviveWaitToken
	task.delay(REVIVE_WAIT_SECONDS, function()
		if token == reviveWaitToken then
			applyReviveOffer()
		end
	end)
end

-- Asks the server to open the purchase prompt for a pack of rotations. The server decides everything; the new
-- count arrives with the next Profile.
function GameController.requestRotations()
	local now = os.clock()
	if Config.ROTATION_PRODUCT == 0 or runMode ~= "normal" or now - rotationsAskedAt < ROTATIONS_ASK_GAP_SECONDS then
		return
	end
	rotationsAskedAt = now
	Net.RequestRotations:FireServer()
end

-- Turns the piece in `slot` a quarter clockwise, on the board right away and on the server by request. The
-- first turn of a piece costs a rotation: the run's free one, else one bought earlier; with none left it
-- opens the purchase prompt instead. Returns whether the piece turned.
function GameController.tryRotate(slot: unknown): boolean
	local ui = views
	if not ui or runId == 0 or runMode ~= "normal" or ui.tray:isHeld() then
		return false
	end
	local bought = if profile then profile.rotations else 0
	local moveIndex = session.moveCount
	local result = session:rotate(slot, bought)
	if not result then
		local piece = if typeof(slot) == "number" then session.tray[slot :: number] else nil
		if
			piece
			and Pieces.canRotate(piece)
			and not session.isOver
			and not session.unlocked[slot :: number]
			and session.freeRotations == 0
			and bought == 0
		then
			GameController.requestRotations()
		end
		return false
	end
	if result.charged == "paid" and profile then
		local updated = table.clone(profile)
		updated.rotations -= 1
		profile = updated
	end
	Net.RotatePiece:FireServer(runId, moveIndex, slot)
	ui.tray:markTurned(result.slot)
	render()
	return true
end

-- A line for under the tray: how many rotations the player has, or what a pack costs when none are left.
-- Empty when rotating isn't part of what is on screen (menu, tutorial, game over).
function GameController.getRotationText(): string
	if runId == 0 or runMode ~= "normal" or session.isOver then
		return ""
	end
	local free = session.freeRotations
	local bought = if profile then profile.rotations else 0
	if free > 0 and bought > 0 then
		return `Rotate: {free} free · {bought} owned`
	elseif free > 0 then
		return `Rotate: {free} free`
	elseif bought > 0 then
		return `Rotate: {bought} owned`
	elseif Config.ROTATION_PRODUCT ~= 0 then
		local price = ReplicatedStorage:GetAttribute("RotationPrice")
		return if typeof(price) == "number"
			then `Rotate: {Config.ROTATION_PACK} for R$ {price}`
			else `Rotate: get {Config.ROTATION_PACK}`
	end
	return "Rotate: none left"
end

-- Opens the pause panel while a run is being played. The run has no clock, so nothing else changes.
function GameController.pause()
	if views and runId > 0 and not session.isOver then
		views.hud:showPause()
	end
end

function GameController.resume()
	if views then
		views.hud:hidePause()
	end
end

function GameController.isPaused(): boolean
	return views ~= nil and views.hud:isPauseOpen()
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

-- What the current run earned; nil until it is over and the server has said.
function GameController.getRunRewards(): RunRewards?
	return runRewards
end

function GameController.getBest(): number
	return best
end

-- nil until start() has built the UI.
function GameController.getViews(): Views?
	return views
end

return GameController
