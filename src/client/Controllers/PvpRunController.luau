--!strict
-- The client side of a PVP match (docs/PHASE6.md, M26): it listens to the server (Net.PvpEvent, and the opponent's
-- board on Net.PvpOpponentBoard), keeps the player's side of the match in a PvpSync, and hands GameController what it
-- needs to draw and play it, as a Source marked isMatch. GameController does the board, the drag and drop and the
-- tray as for a solo run; what is only a match's lives here and in PvpView / OpponentBoardView: the VS screen, the
-- countdown, the clock, the garbage queue, being stuck with the tray locked, the opponent's card, forfeiting, and the
-- result with Play again (or, after a ranked match, its rank change and Queue again).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CoopController = require("./CoopController")
local Format = require("../Views/Format")
local GameController = require("./GameController")
local MenuController = require("./MenuController")
local Net = require(ReplicatedStorage.Shared.Net)
local OpponentBoardView = require("../Views/OpponentBoardView")
local PvpBoardCodec = require(ReplicatedStorage.Shared.PvpBoardCodec)
local PvpSession = require(ReplicatedStorage.Shared.PvpSession)
local PvpSync = require("../Util/PvpSync")
local PvpView = require("../Views/PvpView")
local Theme = require("../Views/Theme")

local PVP = Config.PVP
local IS_STUDIO = RunService:IsStudio()
local CLOCK_SECONDS = 0.1 -- how often the clock, the countdown and the locks are refreshed
local CONFIRM_TIMEOUT_SECONDS = 2 -- ask for the full state if a move is still unanswered by then
local STATE_GAP_SECONDS = 1 -- the full state is asked for at most this often
local NOTE_SECONDS = 2.5 -- how long "+1 garbage from Mia" stays under the tray
local RESULT_DELAY_SECONDS = 0.6 -- from the end of a match to its result panel, so the last move can be seen

type MatchInfo = {
	kind: string,
	names: { string }, -- by seat
	userIds: { number },
	ranked: { rated: boolean, ratings: { number }, tiers: { string } }?, -- a ranked match, by seat
}

local PvpRunController = {}

local sync: PvpSync.PvpSync? = nil
local info: MatchInfo? = nil
local view: PvpView.PvpView? = nil
local opponentView: OpponentBoardView.OpponentBoardView? = nil
local boardVersion: number? = nil -- the newest opponent board seen this match
local votes: { boolean } = { false, false }
local note: string? = nil -- a passing line under the tray
local noteToken = 0
local stateAskedAt = -math.huge
local clockToken = 0
local vsShownFor: number? = nil -- the match whose VS screen has been shown
local lastCanDrag = false

local DEPS: PvpSync.Deps = { PvpSession = PvpSession }

local function now(): number
	return workspace:GetServerTimeNow()
end

local function opponentSeat(run: PvpSync.PvpSync): number
	return 3 - run.seat
end

local function opponentName(): string
	local run, match = sync, info
	if not run or not match then
		return "Opponent"
	end
	return match.names[opponentSeat(run)] or "Opponent"
end

local function requestState(reason: string)
	local at = os.clock()
	if at - stateAskedAt < STATE_GAP_SECONDS then
		return
	end
	stateAskedAt = at
	if IS_STUDIO then
		warn(`[ChikaBlock] asking for the match state: {reason}`)
	end
	Net.PvpRequestState:FireServer()
end

local function showNote(text: string)
	note = text
	noteToken += 1
	local token = noteToken
	task.delay(NOTE_SECONDS, function()
		if token == noteToken then
			note = nil
		end
	end)
end

-- "2:41"
local function clockText(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- The line under the tray: the tray's lock, else a passing note, else the match's free rotations.
local function rotationText(): string
	local run = sync
	if not run then
		return ""
	end
	local session = run.session
	local at = now()
	if session:isLocked(at) then
		return `Tray unlocks in {math.ceil(session.lockedUntil - at)}`
	elseif note then
		return note
	end
	local free = session.game.freeRotations
	return if free > 0 then `Rotate: {free} free (this match)` else "Rotate: none left (this match)"
end

local function leaveRoom()
	Net.CoopLeave:FireServer()
end

local function detach()
	if not sync then
		return
	end
	sync = nil
	info = nil
	clockToken += 1
	noteToken += 1
	note = nil
	if view then
		view:setActive(false)
	end
	GameController.detachSource()
end

local function renderRematch()
	local run, ui = sync, view
	if not run or not ui or not ui:isResultOpen() then
		return
	end
	if run.kind == "ranked" then
		ui:setRematch(true, true, nil) -- Queue again: no votes in ranked
		return
	end
	local room = CoopController.getRoom()
	local here = room ~= nil and room.present[opponentSeat(run)] == true
	local name = opponentName()
	if not here then
		ui:setRematch(false, false, `{name} left`)
	elseif votes[run.seat] then
		ui:setRematch(true, false, `Waiting for {name}…`)
	elseif votes[opponentSeat(run)] then
		ui:setRematch(true, true, `{name} wants a rematch`)
	else
		ui:setRematch(true, true, nil)
	end
end

-- The result panel for how the match ended.
local function showResult(ended: any)
	local run, ui = sync, view
	if not run or not ui then
		return
	end
	local me, them = run.seat, opponentSeat(run)
	local name = opponentName()
	local results = ended.results
	local mine = if results then results[me] else nil
	local title = if mine == "win"
		then "You win!"
		elseif mine == "loss" then `{name} wins`
		elseif mine == "draw" then "Draw!"
		else "Match cancelled"
	local kindText = if run.kind == "ranked"
		then "higher score wins"
		elseif run.kind == "bot" then "practice match, no rank change"
		else "friendly duel, no rank change"
	local reason = ended.reason
	local how = if reason == "time"
		then "Time's up"
		elseif reason == "forfeit" then (if mine == "loss" then "You forfeited" else `{name} forfeited`)
		elseif reason == "left" then (if mine == "loss" then "You left" else `{name} left`)
		else "The server is restarting"
	local scores = ended.scores or { 0, 0 }
	local sent = if ended.sent then ended.sent[me] else 0
	local blocked = if ended.blocked then ended.blocked[me] else 0
	ui:hideVs()
	ui:setCountdown(nil)
	ui:setStuck(false)
	ui:setTrayLock(nil)
	ui:showResult({
		title = title,
		mood = if mine == "win" then "win" elseif mine == "loss" then "loss" else "draw",
		subtitle = `{how} · {kindText}`,
		youName = "You",
		opponentName = name,
		scores = { scores[me] or 0, scores[them] or 0 },
		garbage = `Garbage sent {sent} · blocked {blocked}`,
		canPlayAgain = reason ~= "cancelled" or run.kind == "ranked",
		playAgainText = if run.kind == "ranked" then "Queue again" else "Play again",
		rating = if typeof(ended.rating) == "table"
			then {
				tierBefore = ended.rating.tierBefore,
				tier = ended.rating.tier,
				before = ended.rating.before,
				after = ended.rating.after,
				rated = ended.rating.rated == true,
			}
			else nil,
	})
	renderRematch()
	local views = GameController.getViews()
	if views then
		views.hud:hidePause()
	end
end

-- Refreshes everything that follows the clock: the VS screen and the countdown, the match clock, the tray's lock, and
-- whether the tray can be used (the board is redrawn when that changes).
local function tick()
	local run, ui = sync, view
	local views = GameController.getViews()
	if not run or not ui or not views then
		return
	end
	local at = now()
	local session = run.session
	local vsUntil = run.startAt - (PVP.COUNTDOWN_SECONDS - PVP.VS_SECONDS)
	if run.ended == nil and at < vsUntil then
		if vsShownFor ~= run.matchId and not ui:isVsOpen() then
			local match = info :: MatchInfo
			local profile = GameController.getProfile()
			local opponentId = match.userIds[opponentSeat(run)]
			local opponent = Players:GetPlayerByUserId(opponentId)
			local level = if opponent then opponent:GetAttribute("Level") else nil
			local name = opponentName()
			local ranked = match.ranked
			local me, them = run.seat, opponentSeat(run)
			local function rankLine(seat: number): string
				local points = (ranked :: any).ratings[seat]
				return `{(ranked :: any).tiers[seat]} · {Format.withCommas(points)}`
			end
			ui:showVs({
				label = if ranked
					then (if ranked.rated
						then "Ranked match"
						else "Ranked match · unrated (you two already played twice today)")
					elseif run.kind == "bot" then "Practice match · no rank change"
					else "Friendly duel · no rank change",
				you = {
					name = "You",
					initial = string.upper(string.sub(Players.LocalPlayer.DisplayName, 1, 1)),
					subtitle = if ranked then rankLine(me) elseif profile then `Level {profile.level}` else "",
					color = Theme.Colors.Button,
					tier = if ranked then ranked.tiers[me] else nil,
				},
				opponent = {
					name = name,
					initial = string.upper(string.sub(name, 1, 1)),
					subtitle = if ranked
						then rankLine(them)
						elseif run.kind == "bot" then "Practice bot"
						elseif typeof(level) == "number" then `Level {level}`
						else "",
					subtitleColor = if run.kind == "bot" then Theme.Colors.Title else nil,
					color = Theme.Colors.ButtonSecondary,
					tier = if ranked then ranked.tiers[them] else nil,
				},
			})
		end
	elseif ui:isVsOpen() then
		ui:hideVs()
		vsShownFor = run.matchId
	end
	if run.ended == nil and at >= vsUntil and at < run.startAt then
		ui:setCountdown(math.clamp(math.ceil(run.startAt - at), 1, 3))
	else
		ui:setCountdown(nil)
	end
	if run.ended == nil then -- the clock stops where the match ended
		views.hud:setTimer(clockText(math.min(run.endAt - math.max(at, run.startAt), PVP.MATCH_SECONDS)))
	end

	local locked = run.ended == nil and session:isLocked(at)
	ui:setStuck(locked)
	ui:setTrayLock(if locked then math.ceil(session.lockedUntil - at) else nil)

	if run.ended == nil and run:overdue(at, CONFIRM_TIMEOUT_SECONDS) then
		requestState("a move was not answered")
	end
	local canDrag = run:canDrag(at)
	if canDrag ~= lastCanDrag then
		lastCanDrag = canDrag
		GameController.sourceChanged(nil, true) -- the tray's pieces become (un)available
	end
end

local function startClock(run: PvpSync.PvpSync)
	clockToken += 1
	local token = clockToken
	task.spawn(function()
		while token == clockToken and sync == run do
			tick()
			task.wait(CLOCK_SECONDS)
		end
	end)
end

local source: GameController.Source = {
	session = function()
		local run = sync :: PvpSync.PvpSync
		return run.session.game
	end,
	runId = function()
		return if sync then sync.matchId else 0
	end,
	canDrag = function(slot: number): boolean
		return sync ~= nil and slot >= 1 and slot <= Config.PIECES_PER_SET and sync:canDrag(now())
	end,
	tryPlace = function(slot: unknown, x: unknown, y: unknown)
		local run = sync
		if not run or typeof(slot) ~= "number" or typeof(x) ~= "number" or typeof(y) ~= "number" then
			return nil
		end
		local result, moveIndex = run:place(slot :: number, x :: number, y :: number, now())
		if not result then
			return nil
		end
		Net.PvpPlace:FireServer(run.matchId, moveIndex, slot, x, y)
		GameController.sourceChanged(result.move, true)
		return result.move
	end,
	rotate = function(slot: unknown, _bought: number)
		local run = sync
		if not run or typeof(slot) ~= "number" then
			return nil
		end
		local result, moveIndex = run:rotate(slot :: number, now())
		if not result then
			return nil
		end
		Net.PvpRotate:FireServer(run.matchId, moveIndex, slot)
		return result
	end,
	freeRotations = function(): number
		return if sync then sync.session.game.freeRotations else 0
	end,
	partnerLeft = function(): boolean
		return false
	end,
	statusText = function(): string
		return ""
	end,
	gameOver = function()
		return { score = 0, shares = "", canPlayAgain = false }
	end,
	leave = function()
		leaveRoom()
		detach()
	end,
	playAgain = function() end,
	takeOver = function() end,
	isMatch = true,
	rotationText = rotationText,
	forfeit = function()
		local run = sync
		if run and run.ended == nil then
			Net.PvpForfeit:FireServer(run.matchId)
		end
	end,
	slotCount = Config.PIECES_PER_SET,
}

-- A match starts (or starts again after Play again): the screen is the match's from now on.
local function enter(state: any)
	local run = PvpSync.new(DEPS, state)
	sync = run
	info = {
		kind = state.kind,
		names = state.names or {},
		userIds = state.userIds or {},
		ranked = if typeof(state.ranked) == "table" then state.ranked else nil,
	}
	votes = { false, false }
	boardVersion = nil
	lastCanDrag = false
	note = nil
	MenuController.leaveForGame()
	local views = GameController.getViews()
	if views then
		views.gui.setVariant("match")
	end
	GameController.attachSource(source, nil)
	if view then
		view:hideResult()
		view:setActive(true)
		view:setPending(run.session.pending)
	end
	if opponentView then
		opponentView:setName(opponentName())
		opponentView:reset()
		if typeof(state.opponent) == "table" then
			opponentView:render(state.opponent)
		end
	end
	GameController.sourceReplaced()
	startClock(run)
	tick()
end

local function valid(state: any): boolean
	return typeof(state) == "table"
		and typeof(state.matchId) == "number"
		and typeof(state.seat) == "number"
		and typeof(state.startAt) == "number"
		and typeof(state.endAt) == "number"
		and typeof(state.you) == "table"
end

local function onStart(state: any)
	if valid(state) then
		enter(state)
	end
end

local function onState(state: any)
	local run = sync
	if not run or not valid(state) or state.matchId ~= run.matchId then
		return
	end
	run:reset(state)
	if view then
		view:setPending(run.session.pending)
	end
	GameController.sourceReplaced()
	if state.ended and view and not view:isResultOpen() then
		showResult(state.ended)
	end
end

local function onResult(message: any)
	local run = sync
	if not run or typeof(message) ~= "table" then
		return
	end
	local applied = run:onResult(message)
	if applied.kind == "resync" then
		requestState(applied.reason)
		return
	elseif applied.kind ~= "applied" then
		return
	end
	GameController.sourceChanged(nil, true)
	local ui = view
	if ui then
		ui:setPending(run.session.pending)
		local refill = applied.refill
		if refill and #refill.garbage > 0 then
			ui:pushBoard(refill.garbage[1].side)
			showNote(`+{#refill.garbage} garbage from {opponentName()}`)
		end
	end
end

local function onIncoming(matchId: any, pending: any)
	local run = sync
	if run and typeof(matchId) == "number" and run:onIncoming(matchId, pending) and view then
		view:setPending(run.session.pending)
	end
end

local function onEnd(ended: any)
	local run = sync
	if not run or typeof(ended) ~= "table" or ended.matchId ~= run.matchId then
		return
	end
	run:onEnd(ended)
	GameController.sourceChanged(nil, true)
	task.delay(RESULT_DELAY_SECONDS, function()
		if sync == run and run.ended == ended then
			showResult(ended)
		end
	end)
end

local function onVotes(matchId: any, newVotes: any)
	local run = sync
	if run and matchId == run.matchId and typeof(newVotes) == "table" then
		votes = { newVotes[1] == true, newVotes[2] == true }
		renderRematch()
	end
end

-- Everything about a match, in the order the server sent it (one remote, so the order is kept).
local function onEvent(kind: unknown, ...: any)
	if kind == "start" then
		onStart(...)
	elseif kind == "state" then
		onState(...)
	elseif kind == "result" then
		onResult(...)
	elseif kind == "incoming" then
		onIncoming(...)
	elseif kind == "end" then
		onEnd(...)
	elseif kind == "votes" then
		onVotes(...)
	end
end

-- The opponent's board: kept only when newer than the one on show (the remote may lose or reorder them).
local function onOpponentBoard(data: unknown)
	local board = PvpBoardCodec.decode(data)
	if not board or not sync or not opponentView then
		return
	end
	if boardVersion and not PvpBoardCodec.isNewer(board.version, boardVersion) then
		return
	end
	boardVersion = board.version
	opponentView:render(board)
end

-- Whether a match is on this player's screen.
function PvpRunController.isActive(): boolean
	return sync ~= nil
end

-- For the Studio debug bridge.
function PvpRunController.describe(): string
	local run = sync
	if not run then
		return "no PVP match"
	end
	local game = run.session.game
	local at = now()
	return `match={run.matchId} kind={run.kind} seat={run.seat} vs={opponentName()} score={game.score} moves={game.moveCount} unconfirmed={#run.unconfirmed} pending={table.concat(
		run.session.pending,
		","
	)} startsIn={string.format("%.1f", run.startAt - at)} endsIn={string.format("%.1f", run.endAt - at)} locked={run.session:isLocked(
		at
	)} canDrag={run:canDrag(at)} ended={if run.ended then run.ended.reason else "no"} opponentBoard={boardVersion} | {if view
		then view:describe()
		else "no view"}`
end

-- Presses the result panel's buttons for the Studio debug bridge: "again" or "menu".
function PvpRunController.press(button: string)
	if button == "again" then
		local run = sync
		if run and run.ended and run.kind == "ranked" then
			-- Queue again: out of this room, and back in the queue.
			leaveRoom()
			detach()
			MenuController.openRanked()
		elseif run and run.ended and not votes[run.seat] then
			votes[run.seat] = true
			Net.PvpRematch:FireServer(run.matchId)
			renderRematch()
		end
	elseif button == "menu" then
		leaveRoom()
		detach()
		MenuController.show()
	end
end

function PvpRunController.start(_self: any)
	local views = GameController.getViews()
	while not views do
		task.wait()
		views = GameController.getViews()
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	view = PvpView.new(
		playerGui,
		views.gui.boardArea,
		views.board.frame,
		views.board.grid,
		views.gui.trayArea,
		views.gui.dragLayer,
		{
			onPlayAgain = function()
				PvpRunController.press("again")
			end,
			onMenu = function()
				PvpRunController.press("menu")
			end,
		}
	)
	opponentView = OpponentBoardView.new(views.gui.opponentArea)

	Net.PvpEvent.OnClientEvent:Connect(onEvent)
	Net.PvpOpponentBoard.OnClientEvent:Connect(onOpponentBoard)
	-- Leaving the room (or being put out of it) ends the match on this screen, unless its result is still showing.
	CoopController.onRoomChanged(function(room)
		if not sync then
			return
		end
		if room == nil then
			if not (view and view:isResultOpen()) then
				detach()
				MenuController.show()
			end
		else
			renderRematch()
		end
	end)
end

return PvpRunController
