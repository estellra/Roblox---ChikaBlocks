--!strict
-- Shows and plays the player's run. The server owns the run (GameService); this controller predicts each
-- move on a local copy of the session so the board reacts instantly, sends the move, and checks the
-- server's answer. Sets of pieces only come from the server. When the two disagree, the server's full
-- state replaces the local copy.
-- Runs start on request (startRun, from the menu or "Play again"). Other controllers drive the game through
-- tryPlace() and listen through the on* functions.
-- A Co-op run has its own protocol (CoopRunController) but is drawn and played with the same views and controls:
-- it attaches itself as the run's Source, and from then on this controller asks it for the session to draw,
-- which pieces can be picked up and how a move is made, until it detaches. A PVP match (PvpRunController) attaches
-- the same way, as a Source marked isMatch: it has no game over panel, revive or rotation purchase (it ends on its
-- own result screen), and the pause panel's other choice is to forfeit.
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

-- What a Co-op run gives this controller in place of a solo run's own protocol.
export type Source = {
	session: () -> GameSession.GameSession, -- what to draw: the confirmed state with the player's unconfirmed moves on top
	runId: () -> number,
	canDrag: (slot: number) -> boolean, -- the player's pieces, or all of them once the partner is gone
	tryPlace: (slot: unknown, x: unknown, y: unknown) -> GameSession.PlaceResult?,
	rotate: (slot: unknown, bought: number) -> GameSession.RotateResult?, -- turns a piece (`bought`: the player's bought rotations)
	freeRotations: () -> number, -- the player's own free rotations left in this run
	partnerLeft: () -> boolean,
	statusText: () -> string, -- the line under the tray: who the player waits for, or that the partner left
	gameOver: () -> Hud.CoopGameOver,
	leave: () -> (), -- Menu / Leave run
	playAgain: () -> (),
	takeOver: () -> (),
	isMatch: boolean?, -- a PVP match (see above)
	rotationText: (() -> string)?, -- the line under the tray, in place of the one worked out here
	forfeit: (() -> ())?, -- the pause panel's Forfeit (a match)
	slotCount: number?, -- pieces per set; default Co-op's
}
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
local source: Source? = nil -- the Co-op run being played, or nil for a solo run
local gameOverPresented = false -- the game over panel is open or about to open
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
local pieceTurnedListeners: { (slot: number) -> () } = {}

local function notify<T...>(listeners: { (T...) -> () }, ...: T...)
	for _, listener in listeners do
		task.spawn(listener, ...)
	end
end

-- The client never deals: new sets arrive from the server with MoveResult.
local function noSet(_board: any, _score: number, _reason: any): { Pieces.Piece }?
	return nil
end

-- What is on screen: the Co-op run's, when one is attached, else the solo run's.
local function current(): GameSession.GameSession
	return if source then source.session() else session
end

local function activeRunId(): number
	return if source then source.runId() else runId
end

-- Tells the tray which pieces can be turned: in a normal run that isn't over, those that look different turned. In a
-- Co-op run only the player's own pieces (the partner's can be looked at but not touched).
local function refreshRotatable()
	if not views then
		return
	end
	local shown = current()
	local playing = if source then not shown.isOver else runId > 0 and runMode == "normal" and not shown.isOver
	local rotatable: { boolean } = {}
	for slot = 1, shown.setSize do
		local piece = shown.tray[slot]
		local own = source == nil or source.canDrag(slot)
		rotatable[slot] = playing and own and piece and Pieces.canRotate(piece) or false
	end
	views.tray:setRotatable(rotatable)
end

local function render()
	if not views then
		return
	end
	local shown = current()
	views.board:render(shown.board)
	views.tray:render(shown.tray)
	-- The tray is out of pieces and the server has not dealt the next set yet.
	views.tray:setWaiting(activeRunId() > 0 and shown.awaitingSet and not shown.isOver)
	refreshRotatable()
	views.hud:setScore(shown.score, best)
	views.hud:setCombo(shown.combo.combo)
	if source then
		-- The partner's pieces can be looked at but not picked up (until they have gone).
		for slot = 1, shown.setSize do
			views.tray:setLocked(slot, not source.canDrag(slot) and shown.tray[slot] ~= false)
		end
		views.tray:setPartnerLeft(source.partnerLeft())
	end
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
	if not offer or offer.runId ~= activeRunId() or not current().isOver then
		views.hud:setRevive(nil)
		return
	end
	-- Either Co-op player can pay, and it revives the run for both.
	local clears = if source then "Clears the center 4×4 for both of you" else "Clears the center 4×4"
	local text, hint
	if offer.tokens > 0 then
		text = "Revive · Free"
		hint = `You have {offer.tokens} · {clears}`
	else
		text = if offer.price then `Revive · R$ {offer.price}` else "Revive"
		hint = clears
	end
	views.hud:setRevive({ text = text, hint = hint })
end

local function presentGameOver(delaySeconds: number)
	if not views then
		return
	end
	gameOverToken += 1
	gameOverPresented = true
	local token = gameOverToken
	views.board:setNoMoves(true)
	task.delay(delaySeconds, function()
		if token ~= gameOverToken or not views or not current().isOver then
			return
		end
		if source then
			views.hud:showCoopGameOver(source.gameOver())
			applyReviveOffer() -- either player may pay for it; the offer comes from the server
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
	gameOverPresented = false
	reviveOffer = nil
	if views then
		views.board:setNoMoves(false)
		views.hud:hideGameOver()
		views.hud:setRevive(nil)
	end
end

-- Whether a run that is over gets the game over panel: not a PVP match, which ends on its own result screen.
local function endsWithGameOver(): boolean
	return source == nil or source.isMatch ~= true
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
	if offerRunId ~= activeRunId() then
		return
	end
	reviveOffer = { runId = offerRunId, tokens = offer.tokens, price = offer.price }
	if views and views.hud:isGameOverOpen() then
		applyReviveOffer()
	end
end

-- The revive did not happen (the purchase was cancelled, or it was not possible): the button is free again.
local function onReviveResult(resultRunId: number, ok: boolean)
	if resultRunId == activeRunId() and not ok then
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
			onTakeOver = function()
				if source then
					source.takeOver()
				end
			end,
		}),
	}
	local hud, tray = views.hud, views.tray
	-- A match lays the tray out as a row, as the portrait layout does, whatever the screen.
	local function trayMode(mode: Gui.LayoutMode): Gui.LayoutMode
		return if gui.getVariant() == "match" then "Portrait" else mode
	end
	hud:setLayout(gui.getMode())
	tray:setLayout(trayMode(gui.getMode()))
	gui.onLayoutChanged(function(mode)
		hud:setLayout(mode)
		tray:setLayout(trayMode(mode))
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
	if source then
		source.playAgain()
		return
	end
	GameController.startRun("normal")
end

-- Closes the game over panel and asks for the main menu (MenuController listens).
function GameController.requestMenu()
	if source and source.isMatch and source.forfeit then
		-- The pause panel of a match: Forfeit. The match's result screen comes next, not the menu.
		source.forfeit()
		if views then
			views.hud:hidePause()
		end
		return
	end
	if source then
		source.leave() -- leaves the room and detaches
	end
	hideGameOver()
	notify(menuRequestedListeners)
end

-- Asks the server to revive the finished run: free with a revive already paid for, else it opens Roblox's purchase
-- prompt. The server decides the product; nothing happens on screen until it answers.
function GameController.requestRevive()
	local offer = reviveOffer
	if not views or not offer or offer.runId ~= activeRunId() or not current().isOver then
		return
	end
	views.hud:setReviveBusy(true)
	Net.RequestRevive:FireServer(offer.runId)
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
	local normal = source ~= nil or runMode == "normal" -- a Co-op run is always a normal one
	local match = source ~= nil and source.isMatch == true -- bought rotations don't work in PVP
	if Config.ROTATION_PRODUCT == 0 or not normal or match or now - rotationsAskedAt < ROTATIONS_ASK_GAP_SECONDS then
		return
	end
	rotationsAskedAt = now
	Net.RequestRotations:FireServer()
end

-- Turns the piece in `slot` a quarter clockwise, on the board right away and on the server by request. The
-- first turn of a piece costs a rotation: the player's free one, else one bought earlier; with none left it
-- opens the purchase prompt instead (not while a piece is in hand: a purchase window mid-drag would interrupt
-- it; the line under the tray already says what a pack costs). While a piece is in hand only that piece can be
-- turned. In a Co-op run only the player's own pieces turn, and the Co-op run sends the request itself. Returns
-- whether the piece turned.
function GameController.tryRotate(slot: unknown): boolean
	local ui = views
	if not ui or activeRunId() == 0 or (source == nil and runMode ~= "normal") then
		return false
	end
	local inHand = ui.tray:heldSlot()
	if inHand and inHand ~= slot then
		return false
	end
	local shown = current()
	local bought = if profile then profile.rotations else 0
	local free = if source then source.freeRotations() else shown.freeRotations
	local moveIndex = shown.moveCount
	local result = if source then source.rotate(slot, bought) else session:rotate(slot, bought)
	if not result then
		local piece = if typeof(slot) == "number" then shown.tray[slot :: number] else nil
		if
			not inHand
			and piece
			and Pieces.canRotate(piece)
			and not shown.isOver
			and not shown.unlocked[slot :: number]
			and free == 0
			and bought == 0
			and (source == nil or source.canDrag(slot :: number))
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
	if not source then
		Net.RotatePiece:FireServer(runId, moveIndex, slot)
	end
	ui.tray:markTurned(result.slot)
	render()
	notify(pieceTurnedListeners, result.slot)
	return true
end

-- "Rotate: 1 free · 2 owned", or what a pack costs when none are left.
local function rotationLine(free: number, bought: number): string
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

-- A line for under the tray: how many rotations the player has, or what a pack costs when none are left (in a Co-op
-- run followed by who the player waits for). Empty when rotating isn't part of what is on screen (menu, tutorial,
-- game over).
function GameController.getRotationText(): string
	local bought = if profile then profile.rotations else 0
	if source and source.rotationText then
		return source.rotationText()
	end
	if source then
		local status = source.statusText()
		if source.session().isOver then
			return status
		end
		-- With no piece of their own left to turn (waiting for the partner), only the waiting line is left.
		local hasPiece = false
		for slot = 1, source.session().setSize do
			hasPiece = hasPiece or source.canDrag(slot)
		end
		if not hasPiece then
			return status
		end
		local line = rotationLine(source.freeRotations(), bought)
		return if status ~= "" then `{line}  ·  {status}` else line
	end
	if runId == 0 or runMode ~= "normal" or session.isOver then
		return ""
	end
	return rotationLine(session.freeRotations, bought)
end

-- Opens the pause panel while a run is being played. The run has no clock, so nothing else changes.
function GameController.pause()
	if views and activeRunId() > 0 and not current().isOver then
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
	if source then
		return source.tryPlace(slot, x, y)
	end
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

-- A Co-op run takes over the screen: the tray is rearranged (the player's two pieces and the partner's, small),
-- the bar says who the player is with, and the run is asked for everything from now on. A PVP match passes no tray
-- arrangement (its three pieces are all the player's).
function GameController.attachSource(newSource: Source, tray: TrayView.Coop?)
	source = newSource
	startToken += 1 -- a StartGame still waiting for its retry must not start a solo run over this
	reviveOffer = nil
	hideGameOver()
	if views then
		views.tray:configure(tray)
		views.hud:setPartner(if tray then tray.partnerName else nil)
		views.hud:setMatchPause(newSource.isMatch == true)
		views.hud:setRevive(nil)
	end
	render()
	notify(sessionReplacedListeners)
end

-- The Co-op run is over for this player (they left, or were put out): back to the solo screen.
function GameController.detachSource()
	if not source then
		return
	end
	source = nil
	hideGameOver()
	if views then
		views.board:clearPartnerAim()
		views.tray:configure(nil)
		views.hud:setPartner(nil)
		views.hud:setMatchPause(false)
		views.hud:setTimer(nil)
		views.gui.setVariant("normal")
		for slot = 1, Config.COOP.SET_SIZE do
			views.tray:setLocked(slot, false) -- every piece of a solo run can be picked up
		end
	end
	render()
	notify(sessionReplacedListeners)
end

-- Shows the shadow of the piece the Co-op partner is holding over the board at (x, y), or removes it (no piece).
function GameController.showPartnerAim(piece: Pieces.Piece?, x: number?, y: number?)
	local ui = views
	if not ui then
		return
	end
	if piece and x and y and source then
		ui.board:showPartnerAim(piece, x, y)
	else
		ui.board:clearPartnerAim()
	end
end

-- The Co-op run's state was replaced wholesale (a start, a resync, the partner leaving).
function GameController.sourceReplaced()
	if not source then
		return
	end
	hideGameOver()
	GameController.showPartnerAim(nil)
	render()
	notify(sessionReplacedListeners)
	if current().isOver and endsWithGameOver() then
		presentGameOver(0)
	end
end

-- The Co-op run's state changed by one move. `result` is that move: it is played out on the board, and the
-- partner's gets a colored outline for a moment so the player can see who placed it.
function GameController.sourceChanged(result: GameSession.PlaceResult?, mine: boolean)
	local ui = views
	if not ui or not source then
		return
	end
	if result then
		ui.board:playMoveEffects(result) -- needs the board as drawn before this move
	end
	render()
	if result then
		ui.hud:showGain(result)
		if mine then
			notify(movePlayedListeners, result)
		else
			ui.board:accent(result, Theme.Colors.Title)
		end
	end
	if current().isOver and not gameOverPresented and endsWithGameOver() then
		presentGameOver(Theme.Motion.GameOverDelay)
	end
end

-- Called whenever the session is replaced (new run or resync), e.g. so an in-progress drag is cancelled.
function GameController.onSessionReplaced(callback: () -> ())
	table.insert(sessionReplacedListeners, callback)
end

-- Called after each move the player makes (before the server confirms it).
function GameController.onMovePlayed(callback: (result: GameSession.PlaceResult) -> ())
	table.insert(movePlayedListeners, callback)
end

-- Called after a piece in the tray turned (the session already holds the turned piece). DragController uses it to
-- swap the piece in hand.
function GameController.onPieceTurned(callback: (slot: number) -> ())
	table.insert(pieceTurnedListeners, callback)
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
	return current()
end

function GameController.getRunId(): number
	return activeRunId()
end

-- Whether the piece in `slot` may be picked up (in Co-op, the partner's may not).
function GameController.canDrag(slot: number): boolean
	if source then
		return source.canDrag(slot)
	end
	return slot >= 1 and slot <= Config.PIECES_PER_SET
end

-- How many pieces a set has in the run being played.
function GameController.getSlotCount(): number
	return if source then source.slotCount or Config.COOP.SET_SIZE else Config.PIECES_PER_SET
end

function GameController.isCoop(): boolean
	return source ~= nil
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
