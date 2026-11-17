--!strict
-- The client side of the ranked queue (docs/PHASE6.md, M27): the queue screen opened from the menu's Ranked button.
-- Opening it asks the server to put the player in the queue (Net.PvpQueue); closing it takes them out. The server
-- answers with Net.PvpQueueState (queued since when, how many others are waiting, or why the player can't join). When
-- a pair is made the match starts and PvpRunController takes over the screen (the menu's screens are dismissed).
-- After QUEUE_OFFER_SECONDS with nobody to play, the screen offers practice against the bot and inviting friends.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require("../Views/Format")
local GameController = require("./GameController")
local Net = require(ReplicatedStorage.Shared.Net)
local QueueView = require("../Views/QueueView")

local PVP = Config.PVP
local CLOCK_SECONDS = 0.25

-- Why a player can't queue, as the screen says it (see RankedRules.Refusal).
local REFUSALS: { [string]: string } = {
	off = "Ranked isn't open yet.",
	private = "Ranked isn't available in private servers.",
	tutorial = "Finish the tutorial to play ranked.",
	level = `Reach level {PVP.MIN_LEVEL} to play ranked.`,
	busy = "Leave your room first.",
	loading = "Loading your data…",
}

type QueueState = { queued: boolean, since: number?, others: number, refusal: string? }

local QueueController = {}

local view: QueueView.QueueView? = nil
local onClosed: (() -> ())? = nil
local state: QueueState = { queued = false, since = nil, others = 0, refusal = nil }
local offerDismissed = false
local canInviteFriends = false
local clockToken = 0

--- Whether the Ranked button shows: the server says ranked is open here (on, and not a private server, which only the
--- server can tell).
function QueueController.isAvailable(): boolean
	return ReplicatedStorage:GetAttribute("RankedOpen") == true
end

--- Calls `callback` when isAvailable() may have changed (the server's attribute arrives after the client starts).
function QueueController.onAvailabilityChanged(callback: () -> ())
	ReplicatedStorage:GetAttributeChangedSignal("RankedOpen"):Connect(callback)
end

-- "0:12"
local function clockText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- The season now, as Seasons.id names it (for a player who hasn't played ranked yet).
local function seasonNow(): string
	local date = os.date("!*t", math.floor(workspace:GetServerTimeNow())) :: any
	return string.format("%dM%02d", date.year, date.month)
end

local function render()
	local ui = view
	if not ui then
		return
	end
	local profile = GameController.getProfile()
	local rank = profile and (profile :: any).rank
	local tier = if rank then rank.tier else "Silver"
	local points = if rank then rank.rating else PVP.RATING.START
	local season = if rank and rank.season ~= "" then rank.season else seasonNow()
	local wins = if rank then rank.wins else 0
	local losses = if rank then rank.losses else 0
	local now = workspace:GetServerTimeNow()
	local waited = if state.queued and state.since then now - state.since else 0
	local status
	if state.refusal then
		status = REFUSALS[state.refusal] or "You can't play ranked right now."
	elseif state.queued then
		status = "Finding an opponent…"
	else
		status = "Joining the queue…"
	end
	local others = state.others
	ui:setState({
		tier = tier,
		rankLine = `{tier} · {Format.withCommas(points)}`,
		recordLine = `{wins}W {losses}L · Season {season}`,
		searching = state.queued,
		status = status,
		waitedLine = if state.queued
			then `Waited {clockText(waited)} · {others} other {if others == 1 then "player" else "players"} can be matched here`
			else "",
		offer = waited >= PVP.QUEUE_OFFER_SECONDS and not offerDismissed,
		canInviteFriends = canInviteFriends,
	})
end

local function startClock()
	clockToken += 1
	local token = clockToken
	task.spawn(function()
		while token == clockToken and view and view:isOpen() do
			render()
			task.wait(CLOCK_SECONDS)
		end
	end)
end

local function onQueueState(newState: unknown)
	if typeof(newState) ~= "table" then
		return
	end
	local value = newState :: any
	state = {
		queued = value.queued == true,
		since = if typeof(value.since) == "number" then value.since else nil,
		others = if typeof(value.others) == "number" then value.others else 0,
		refusal = if typeof(value.refusal) == "string" then value.refusal else nil,
	}
	render()
end

--- Opens the screen and joins the queue; `closed` runs when the player goes back.
function QueueController.open(closed: () -> ())
	local ui = view
	if not ui then
		return
	end
	onClosed = closed
	offerDismissed = false
	state = { queued = false, since = nil, others = 0, refusal = nil }
	ui:open()
	render()
	startClock()
	Net.PvpQueue:FireServer(true)
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		canInviteFriends = ok and can == true
		render()
	end)
end

--- Leaves the queue and the screen (the X, Cancel, Escape); the menu comes back.
function QueueController.close()
	local ui = view
	if not ui or not ui:isOpen() then
		return
	end
	Net.PvpQueue:FireServer(false)
	ui:close()
	clockToken += 1
	local callback = onClosed
	onClosed = nil
	if callback then
		callback()
	end
end

--- Closes the screen without going back to the menu: a match is starting over it (the server has taken the player
--- out of the queue already).
function QueueController.dismiss()
	onClosed = nil
	clockToken += 1
	if view and view:isOpen() then
		view:close()
	end
end

function QueueController.isOpen(): boolean
	return view ~= nil and view:isOpen()
end

--- For the Studio debug bridge.
function QueueController.describe(): string
	return if view
		then `{view:describe()} queued={state.queued} others={state.others} refusal={state.refusal}`
		else "not started"
end

--- Presses a button for the Studio debug bridge: "keep", "practice" or "close".
function QueueController.press(button: string)
	if button == "keep" then
		offerDismissed = true
		render()
	elseif button == "practice" then
		Net.PvpPractice:FireServer()
	elseif button == "close" then
		QueueController.close()
	end
end

function QueueController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	view = QueueView.new(playerGui, {
		onClose = QueueController.close,
		onKeepWaiting = function()
			QueueController.press("keep")
		end,
		onPractice = function()
			QueueController.press("practice")
		end,
		onInviteFriends = function()
			pcall(function()
				SocialService:PromptGameInvite(Players.LocalPlayer)
			end)
		end,
	})
	Net.PvpQueueState.OnClientEvent:Connect(onQueueState)
	GameController.onProfileChanged(function()
		render()
	end)
end

return QueueController
