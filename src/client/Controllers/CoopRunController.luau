--!strict
-- The client side of a Co-op run: it listens to the server (CoopState, CoopEvent, CoopReject, CoopRematchVotes),
-- keeps the run in a CoopSync (the confirmed state plus this player's unconfirmed moves) and hands GameController
-- what it needs to draw and play it, as a Source. GameController does the drawing, the drag and drop and the
-- panels exactly as for a solo run; what differs lives here: which pieces are the player's, sending moves and
-- recognising the server's answer, the partner's moves arriving on their own, waiting for the partner, taking
-- over when they have gone idle, and playing again together.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoopController = require("./CoopController")
local CoopSession = require(ReplicatedStorage.Shared.CoopSession)
local CoopSync = require("../Util/CoopSync")
local DragController = require("./DragController")
local Format = require("../Views/Format")
local GameController = require("./GameController")
local MenuController = require("./MenuController")
local Net = require(ReplicatedStorage.Shared.Net)
local Pieces = require(ReplicatedStorage.Shared.Pieces)

local IS_STUDIO = RunService:IsStudio()
local CONFIRM_TIMEOUT_SECONDS = 2 -- ask for the full state if a move is still unconfirmed by then
local STATE_GAP_SECONDS = 1 -- the full state is asked for at most this often
local CLOCK_SECONDS = 0.25 -- how often the Take over button is checked
local AIM_GAP_SECONDS = 0.1 -- where the player aims a piece is sent at most this often (10 a second)
local AIM_RENEW_SECONDS = 0.5 -- and sent again this often while it stays put, so the partner's shadow doesn't expire
local PARTNER_AIM_EXPIRES_SECONDS = 1.2 -- the partner's shadow goes if it isn't renewed by then (a lost message)

local CoopRunController = {}

local sync: CoopSync.CoopSync? = nil
local userIds: { number } = {} -- by seat
local votes: { boolean } = { false, false } -- by seat: pressed Play again
local stateAskedAt = -math.huge
local clockToken = 0
local rewards: GameController.RunRewards? = nil -- what the run earned the player, once the server has said
local aimWanted: { slot: number, x: number, y: number }? = nil -- where the player is aiming a piece now
local aimSent: { slot: number, x: number, y: number }? = nil -- what the server was last told
local aimSentAt = -math.huge
local aimFlushToken = 0 -- identifies the latest delayed send
local partnerAimToken = 0 -- identifies the latest shadow of the partner's, for its expiry

local DEPS: CoopSync.Deps = { CoopSession = CoopSession, Pieces = Pieces }

local function partnerName(): string
	local run = sync
	local userId = if run then userIds[run.seat == 1 and 2 or 1] else nil
	return (if userId then CoopController.nameOf(userId) else nil) or "Partner"
end

local function partnerLeft(): boolean
	local run = sync
	return run ~= nil and run:session().present[run:partnerSeat()] ~= true
end

local function requestState(reason: string)
	local now = os.clock()
	if now - stateAskedAt < STATE_GAP_SECONDS then
		return
	end
	stateAskedAt = now
	if IS_STUDIO then
		warn(`[ChikaBlock] asking for the Co-op state: {reason}`)
	end
	Net.CoopRequestState:FireServer()
end

-- What the Play again button says, given who has pressed it.
local function refreshPlayAgain()
	local views = GameController.getViews()
	local run = sync
	if not views or not run then
		return
	end
	local name = partnerName()
	if votes[run.seat] then
		views.hud:setPlayAgain(false, `Waiting for {name}…`)
	elseif votes[run:partnerSeat()] then
		views.hud:setPlayAgain(true, `{name} wants to play again`)
	else
		views.hud:setPlayAgain(true, nil)
	end
end

-- The line under the tray.
local function statusText(): string
	local run = sync
	if not run then
		return ""
	end
	local shown = run:session()
	if partnerLeft() then
		return "Partner left · score no longer counts for Co-op"
	elseif shown.session.isOver then
		return ""
	elseif not shown:hasMove(run.seat) and shown:hasMove(run:partnerSeat()) then
		return `Waiting for {partnerName()}…`
	end
	return ""
end

-- Whether the player may take over now, and the button's text, checked on a clock while the run goes on.
local function refreshTakeOver()
	local views = GameController.getViews()
	local run = sync
	if not views or not run then
		return
	end
	local shown = run:session()
	local opensAt = run.takeOverAt
	local open = opensAt ~= nil
		and workspace:GetServerTimeNow() >= opensAt
		and not shown.session.isOver
		and not shown:hasMove(run.seat)
		and shown:hasMove(run:partnerSeat())
	views.hud:setTakeOver(if open then `Take over from {partnerName()}` else nil)
end

local function sameAim(a: { slot: number, x: number, y: number }?, b: { slot: number, x: number, y: number }?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.slot == b.slot and a.x == b.x and a.y == b.y
end

-- Tells the server where the player is aiming a piece (or that they no longer are), for the partner's shadow: only
-- when it changed, at most ten times a second (the newest aim waits for its turn), and again every half second
-- while it stays put when `renew` is set.
local function sendAim(renew: boolean)
	local run = sync
	if not run then
		return
	end
	local wanted = aimWanted
	if not renew and sameAim(wanted, aimSent) then
		return
	end
	local wait = aimSentAt + AIM_GAP_SECONDS - os.clock()
	if wait > 0 then
		aimFlushToken += 1
		local token = aimFlushToken
		task.delay(wait, function()
			if token == aimFlushToken then
				sendAim(renew)
			end
		end)
		return
	end
	aimFlushToken += 1 -- a delayed send that is still waiting is out of date
	aimSent = wanted
	aimSentAt = os.clock()
	if wanted then
		Net.CoopHover:FireServer(wanted.slot, wanted.x, wanted.y)
	else
		Net.CoopHover:FireServer()
	end
end

local function onAim(slot: number?, x: number?, y: number?)
	if not sync then
		return
	end
	aimWanted = if slot and x and y then { slot = slot, x = x, y = y } else nil
	sendAim(false)
end

local function startClock(run: CoopSync.CoopSync)
	clockToken += 1
	local token = clockToken
	task.spawn(function()
		while token == clockToken and sync == run do
			refreshTakeOver()
			if aimWanted and os.clock() - aimSentAt > AIM_RENEW_SECONDS then
				sendAim(true)
			end
			task.wait(CLOCK_SECONDS)
		end
	end)
end

-- The partner is aiming a piece over the board (or has stopped): their shadow is drawn there for a moment.
local function onPartnerAim(slot: unknown, x: unknown, y: unknown)
	local run = sync
	if not run then
		return
	end
	partnerAimToken += 1
	local token = partnerAimToken
	local piece = if typeof(slot) == "number" then run:session().session.tray[slot :: number] else nil
	if not piece or typeof(x) ~= "number" or typeof(y) ~= "number" or CoopSession.seatOf(slot) ~= run:partnerSeat() then
		GameController.showPartnerAim(nil)
		return
	end
	GameController.showPartnerAim(piece :: Pieces.Piece, x :: number, y :: number)
	task.delay(PARTNER_AIM_EXPIRES_SECONDS, function()
		if token == partnerAimToken then
			GameController.showPartnerAim(nil)
		end
	end)
end

local function detach()
	if not sync then
		return
	end
	sync = nil
	clockToken += 1
	aimWanted, aimSent = nil, nil
	partnerAimToken += 1
	GameController.detachSource()
end

-- Watches a move the player sent: if the server hasn't answered by then, the state is asked for.
local function watch(run: CoopSync.CoopSync, moveId: number)
	task.delay(CONFIRM_TIMEOUT_SECONDS, function()
		if sync ~= run then
			return
		end
		for _, pending in run.pending do
			if pending.moveId == moveId then
				requestState("a move was not answered")
				return
			end
		end
	end)
end

-- The pieces that were the player's before the partner left are still theirs: the seat's own two slots.
local source: GameController.Source = {
	session = function()
		local run = sync :: CoopSync.CoopSync
		return run:session().session
	end,
	runId = function()
		return if sync then sync.runId else 0
	end,
	canDrag = function(slot: number): boolean
		return sync ~= nil and sync:canDrag(slot)
	end,
	tryPlace = function(slot: unknown, x: unknown, y: unknown)
		local run = sync
		if not run then
			return nil
		end
		local result, moveId = run:place(slot, x, y)
		if not result or not moveId then
			return nil
		end
		Net.CoopPlace:FireServer(run.runId, moveId, result.slot, result.x, result.y)
		watch(run, moveId)
		GameController.sourceChanged(result, true)
		return result
	end,
	rotate = function(slot: unknown, bought: number)
		local run = sync
		if not run then
			return nil
		end
		local result, moveId = run:rotate(slot, bought)
		if not result or not moveId then
			return nil
		end
		Net.CoopRotate:FireServer(run.runId, moveId, result.slot)
		watch(run, moveId)
		return result
	end,
	freeRotations = function(): number
		return if sync then sync:freeRotations() else 0
	end,
	partnerLeft = partnerLeft,
	statusText = statusText,
	gameOver = function()
		local run = sync :: CoopSync.CoopSync
		local shown = run:session()
		local mine, theirs = shown.contribution[run.seat], shown.contribution[run:partnerSeat()]
		local name = partnerName()
		local left = partnerLeft()
		return {
			score = shown.session.score,
			shares = `You {Format.withCommas(mine)}  ·  {name} {Format.withCommas(theirs)}`,
			note = if left then `{name} left: {Format.withCommas(shown.countedScore)} counts for Co-op` else nil,
			canPlayAgain = not left,
			rewards = rewards,
		}
	end,
	leave = function()
		Net.CoopLeave:FireServer()
		detach()
	end,
	playAgain = function()
		local run = sync
		if not run or votes[run.seat] then
			return
		end
		votes[run.seat] = true
		Net.CoopRematch:FireServer()
		refreshPlayAgain()
	end,
	takeOver = function()
		local run = sync
		if run then
			Net.CoopTakeOver:FireServer(run.runId)
		end
	end,
}

-- A run starts (or starts again): the screen is the Co-op run's from now on.
local function enter(state: CoopSync.State, players: { number })
	local run = CoopSync.new(DEPS, state)
	sync = run
	userIds = players
	votes = { false, false }
	rewards = nil
	MenuController.leaveForGame()
	GameController.attachSource(source, { own = CoopSession.slotsOf(run.seat), partnerName = partnerName() })
	GameController.sourceReplaced()
	refreshPlayAgain()
	startClock(run)
end

local function onState(state: any, reason: unknown)
	if
		typeof(state) ~= "table"
		or typeof(state.runId) ~= "number"
		or typeof(state.seq) ~= "number"
		or typeof(state.seat) ~= "number"
		or typeof(state.session) ~= "table"
		or typeof(state.userIds) ~= "table"
	then
		return
	end
	if reason == "start" then
		enter(state, state.userIds)
		return
	end
	local run = sync
	if not run then
		return -- not in a run (any more): a late answer
	end
	if reason == "revive" then
		rewards = nil -- the run goes on; its next game over brings what it has earned by then
	end
	userIds = state.userIds
	votes = { false, false }
	run:reset(state)
	GameController.sourceReplaced()
	refreshPlayAgain()
	refreshTakeOver()
end

local function onMove(
	runId: number,
	seq: number,
	seat: number,
	moveId: number,
	slot: number,
	x: number,
	y: number,
	score: number,
	set: { string }?,
	isOver: boolean,
	takeOverAt: number?
)
	local run = sync
	if not run then
		return
	end
	local applied = run:applyMove({
		runId = runId,
		seq = seq,
		seat = seat,
		moveId = moveId,
		slot = slot,
		x = x,
		y = y,
		score = score,
		set = set,
		isOver = isOver,
		takeOverAt = takeOverAt,
	})
	if applied.kind == "resync" then
		requestState(applied.reason)
	elseif applied.kind == "applied" then
		if not applied.mine then
			partnerAimToken += 1 -- the partner has placed the piece they were aiming
			GameController.showPartnerAim(nil)
		end
		GameController.sourceChanged(applied.result, applied.mine)
		refreshTakeOver()
	end
end

-- A piece was turned, by the player (the server confirms it) or by the partner (their tray shows it from now on).
local function onTurn(
	runId: number,
	seq: number,
	seat: number,
	moveId: number,
	slot: number,
	charged: ("free" | "paid")?
)
	local run = sync
	if not run then
		return
	end
	local applied = run:applyTurn({
		runId = runId,
		seq = seq,
		seat = seat,
		moveId = moveId,
		slot = slot,
		charged = charged,
	})
	if applied.kind == "resync" then
		requestState(applied.reason)
	elseif applied.kind == "applied" then
		GameController.sourceChanged(nil, applied.mine) -- draws the partner's turned piece
		refreshTakeOver()
	end
end

-- Everything that happens in the run, in the order the server took it (one remote, so the order is kept).
local function onEvent(kind: unknown, ...: any)
	if kind == "move" then
		onMove(...)
	elseif kind == "turn" then
		onTurn(...)
	end
end

local function onReject(runId: number, moveId: number)
	local run = sync
	if run then
		run:reject(runId, moveId)
		GameController.sourceChanged(nil, true) -- the piece goes back to its tray
	end
end

-- What the finished run earned: shown on the Game Over panel, which may open a moment later.
local function onRewards(runId: number, earned: GameController.RunRewards)
	local run = sync
	if not run or runId ~= run.runId then
		return
	end
	rewards = earned
	local views = GameController.getViews()
	if views and views.hud:isGameOverOpen() then
		views.hud:showRewards(earned)
	end
end

local function onVotes(newVotes: { boolean })
	if sync and typeof(newVotes) == "table" then
		votes = { newVotes[1] == true, newVotes[2] == true }
		refreshPlayAgain()
	end
end

-- Presses Take over for the player (the button does the same); for the Studio debug bridge.
function CoopRunController.takeOver()
	source.takeOver()
end

-- Whether a Co-op run is on this player's screen.
function CoopRunController.isActive(): boolean
	return sync ~= nil
end

-- For the Studio debug bridge.
function CoopRunController.describe(): string
	local run = sync
	if not run then
		return "no Co-op run"
	end
	local shown = run:session()
	return `run={run.runId} seat={run.seat} seq={run.seq} pending={run:pendingCount()} partner="{partnerName()}" left={partnerLeft()} score={shown.session.score} counted={shown.countedScore} over={shown.session.isOver} revives={shown.session.revivesUsed} free={table.concat(
		shown.freeRotations,
		"/"
	)} votes={tostring(votes[1])}/{tostring(votes[2])} takeOverAt={run.takeOverAt} status="{statusText()}"`
end

function CoopRunController.start(_self: any)
	Net.CoopState.OnClientEvent:Connect(onState)
	Net.CoopEvent.OnClientEvent:Connect(onEvent)
	Net.CoopReject.OnClientEvent:Connect(onReject)
	Net.CoopRematchVotes.OnClientEvent:Connect(onVotes)
	Net.CoopRewards.OnClientEvent:Connect(onRewards)
	Net.CoopPartnerHover.OnClientEvent:Connect(onPartnerAim)
	DragController.onAim(onAim)
	-- Leaving the room (or being put out of it) ends the run on this screen; the menu comes back.
	CoopController.onRoomChanged(function(room)
		if room == nil and sync then
			detach()
			MenuController.show()
		end
	end)
end

return CoopRunController
