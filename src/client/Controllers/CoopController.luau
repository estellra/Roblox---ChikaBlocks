--!strict
-- The client side of Co-op rooms: the Co-op screen opened from the menu, and the invitation notices that can
-- appear anywhere. It keeps what the server has told it (the invitations waiting for an answer, the one the
-- player sent, the room they are in) and who else is in the server (the other Players and the CoopBusy and Level
-- attributes the server publishes on them), and hands the views a fresh state whenever any of it changes. The
-- player only ever sends numbers: who to invite, which invitation to answer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local CoopInviteView = require("../Views/CoopInviteView")
local CoopView = require("../Views/CoopView")
local GameController = require("./GameController")
local Net = require(ReplicatedStorage.Shared.Net)

local STATUS_SECONDS = 6 -- how long "Alex declined" stays up
local SENT_TIMEOUT_SECONDS = 3 -- an invitation the server hasn't confirmed by then was dropped (sent too fast)
local NOTICE_CORNER_WIDTH = 300 -- the invitation card while the Co-op screen is open: this wide, in the top right corner
local NOTICE_CORNER_MARGIN = 12

-- The room as the server describes it (see Net.CoopRoom).
type Room = { id: number, mode: string, you: number, present: { boolean }, userIds: { number } }
type Invite = { id: number, fromUserId: number }
type Outgoing = { userId: number, confirmed: boolean }

-- The room kinds an invitation can ask for, as Net.CoopInvite codes them.
local MODE_CODES = { coop = 1, pvp = 2 }

local CoopController = {}

local view: CoopView.CoopView? = nil
local notices: CoopInviteView.CoopInviteView? = nil
local onClosed: (() -> ())? = nil
local room: Room? = nil
local outgoing: Outgoing? = nil
local invites: { [number]: Invite } = {}
local status: string? = nil
local statusToken = 0
local canInviteFriends = false
local watchers: { [Player]: { RBXScriptConnection } } = {}
local roomListeners: { (room: Room?) -> () } = {}
local pretendPeople: { CoopView.Person }? = nil -- for the Studio debug bridge: stands in for the other players
local placeNotices: () -> () = function() end -- puts the invitation card where it covers nothing (see start)

-- What the inviter is told when their invitation ends without a room.
local MESSAGES: { [string]: (name: string) -> string } = {
	declined = function(name: string): string
		return `{name} declined your invite.`
	end,
	expired = function(name: string): string
		return `{name} didn't answer in time.`
	end,
	busy = function(name: string): string
		return `{name} is busy right now.`
	end,
	cooldown = function(name: string): string
		return `Give {name} a minute before inviting again.`
	end,
	left = function(name: string): string
		return `{name} is no longer here.`
	end,
}

-- The Co-op button shows, and the server answers, only once the mode is playable (or in Studio).
function CoopController.isAvailable(): boolean
	return Config.COOP.ENABLED or RunService:IsStudio()
end

-- Whether Duel invitations (friendly PVP matches) can be sent: once PVP is playable (or in Studio).
function CoopController.canDuel(): boolean
	return Config.PVP.ENABLED or RunService:IsStudio()
end

local function nameOf(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else nil
end

-- The display name of a player in the server, or nil (they left, or it is a practice partner).
CoopController.nameOf = nameOf

local function peopleList(): { CoopView.Person }
	if pretendPeople then
		return pretendPeople
	end
	local people: { CoopView.Person } = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			local level, busy = player:GetAttribute("Level"), player:GetAttribute("CoopBusy")
			table.insert(people, {
				userId = player.UserId,
				name = player.DisplayName,
				level = if typeof(level) == "number" then level else nil,
				busy = if typeof(busy) == "string" then busy else nil,
			})
		end
	end
	table.sort(people, function(a: CoopView.Person, b: CoopView.Person): boolean
		local first, second = string.lower(a.name), string.lower(b.name)
		return if first == second then a.userId < b.userId else first < second
	end)
	return people
end

local function render()
	if not view then
		return
	end
	local partnerName: string? = nil
	local partnerLeft = false
	if room then
		local seat = 3 - room.you
		partnerLeft = room.present[seat] ~= true
		partnerName = nameOf(room.userIds[seat])
	end
	local mine = Players.LocalPlayer:GetAttribute("CoopBusy")
	view:setState({
		people = peopleList(),
		inRoom = room ~= nil,
		partnerName = partnerName,
		partnerLeft = partnerLeft,
		invitingUserId = if outgoing then outgoing.userId else nil,
		myBusy = if mine == "tutorial" or mine == "loading" then mine else nil,
		status = status,
		canInviteFriends = canInviteFriends,
		canDuel = CoopController.canDuel(),
	})
end

local function setStatus(message: string?)
	status = message
	statusToken += 1
	local token = statusToken
	if message then
		task.delay(STATUS_SECONDS, function()
			if token == statusToken then
				status = nil
				render()
			end
		end)
	end
end

-- Whether the Roblox invite dialog can be used; asked each time the screen opens.
local function refreshFriends()
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		canInviteFriends = ok and can == true
		render()
	end)
end

local function inviteFriends()
	pcall(function()
		SocialService:PromptGameInvite(Players.LocalPlayer)
	end)
end

-- Invites the player with this UserId to a room of `mode` (default Co-op): the Invite and Duel buttons, and what the
-- Studio debug bridge presses.
local function invite(userId: number, mode: ("coop" | "pvp")?)
	if outgoing or room then
		return
	end
	local sent: Outgoing = { userId = userId, confirmed = false }
	outgoing = sent
	setStatus(nil)
	Net.CoopInvite:FireServer(userId, MODE_CODES[mode or "coop"])
	render()
	task.delay(SENT_TIMEOUT_SECONDS, function()
		if outgoing == sent and not sent.confirmed then
			outgoing = nil
			render()
		end
	end)
end

local function cancelInvite()
	if outgoing then
		outgoing = nil
		Net.CoopCancelInvite:FireServer()
		render()
	end
end

local function answer(inviteId: number, accept: boolean)
	invites[inviteId] = nil
	Net.CoopInviteReply:FireServer(inviteId, accept)
end

-- Someone invited the player (to Co-op, or to a Duel): show a notice that runs out when the invitation does.
function CoopController.onInvited(inviteId: unknown, fromUserId: unknown, expiresAt: unknown, mode: unknown)
	if typeof(inviteId) ~= "number" or typeof(fromUserId) ~= "number" or typeof(expiresAt) ~= "number" then
		return
	end
	if not notices then
		return
	end
	invites[inviteId] = { id = inviteId, fromUserId = fromUserId }
	notices:add(inviteId, nameOf(fromUserId) or "Someone", expiresAt - workspace:GetServerTimeNow(), mode == "pvp")
end

-- How an invitation with `otherUserId` stands: either the one the player sent or one they were sent.
function CoopController.onInviteResult(otherUserId: unknown, result: unknown)
	if typeof(otherUserId) ~= "number" or typeof(result) ~= "string" then
		return
	end
	local mine = outgoing
	if mine and mine.userId == otherUserId then
		if result == "sent" then
			mine.confirmed = true
		else
			outgoing = nil
			local describe = MESSAGES[result]
			setStatus(if describe then describe(nameOf(otherUserId) or "That player") else nil)
		end
	else
		-- An invitation the player was sent is over (expired, or the sender took it back).
		for id, theirs in table.clone(invites) do
			if theirs.fromUserId == otherUserId then
				invites[id] = nil
				if notices then
					notices:remove(id)
				end
			end
		end
	end
	render()
end

-- The player's room changed: they have one now, it lost its other player, or it is gone (nil).
function CoopController.onRoom(payload: unknown)
	if payload == nil then
		room = nil
	elseif
		typeof(payload) == "table"
		and typeof((payload :: any).you) == "number"
		and typeof((payload :: any).present) == "table"
		and typeof((payload :: any).userIds) == "table"
	then
		room = payload :: any
		-- Whoever is in a room has no invitations going either way.
		outgoing = nil
		table.clear(invites)
		if notices then
			notices:clear()
		end
		setStatus(nil)
	else
		return
	end
	render()
	for _, listener in roomListeners do
		task.spawn(listener, room)
	end
end

-- The room the player is in, as the server last described it; nil when they have none.
function CoopController.getRoom(): Room?
	return room
end

-- Called with the new room (or nil) whenever it changes: the player joined one, it lost its other player, or it is gone.
function CoopController.onRoomChanged(callback: (room: Room?) -> ())
	table.insert(roomListeners, callback)
end

-- Closes the Co-op screen without going back to the menu (a Co-op game is starting over it).
function CoopController.dismiss()
	onClosed = nil
	if view and view:isOpen() then
		view:close()
	end
	placeNotices()
end

CoopController.invite = invite
CoopController.cancel = cancelInvite

function CoopController.close()
	if view and view:isOpen() then
		view:close()
		placeNotices()
		local callback = onClosed
		onClosed = nil
		if callback then
			callback()
		end
	end
end

-- Opens the screen; `closed` runs when the player goes back.
function CoopController.open(closed: () -> ())
	if not view then
		return
	end
	onClosed = closed
	setStatus(nil)
	view:open()
	placeNotices()
	refreshFriends()
end

function CoopController.isOpen(): boolean
	return view ~= nil and view:isOpen()
end

-- For the Studio debug bridge.
function CoopController.describe(): string
	local shown = if notices then notices:describe() else "not started"
	local mine = if view then view:describe() else "not started"
	return `{mine}\nnotices: {shown}`
end

-- For the Studio debug bridge: shows `count` made-up people instead of the other players (0 = the real ones).
function CoopController.pretendPeople(count: number)
	if count <= 0 then
		pretendPeople = nil
	else
		local reasons = { "", "room", "tutorial", "loading" } -- "" is free
		local people: { CoopView.Person } = {}
		for i = 1, count do
			local reason = reasons[i % 4 + 1]
			table.insert(people, {
				userId = -1000 - i,
				name = `Player {i}`,
				level = i * 3,
				busy = if reason == "" then nil else reason,
			})
		end
		pretendPeople = people
	end
	render()
end

-- Re-renders whenever somebody else's CoopBusy or Level changes, and forgets players who leave.
local function watch(player: Player)
	if watchers[player] then
		return
	end
	local function changed()
		render()
	end
	watchers[player] = {
		player:GetAttributeChangedSignal("CoopBusy"):Connect(changed),
		player:GetAttributeChangedSignal("Level"):Connect(changed),
	}
end

local function unwatch(player: Player)
	for _, connection in watchers[player] or {} do
		connection:Disconnect()
	end
	watchers[player] = nil
end

function CoopController.start(_self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	view = CoopView.new(playerGui, {
		onClose = CoopController.close,
		onInvite = function(userId: number)
			invite(userId, "coop")
		end,
		onDuel = function(userId: number)
			invite(userId, "pvp")
		end,
		onCancel = cancelInvite,
		onLeave = function()
			Net.CoopLeave:FireServer()
		end,
		onInviteFriends = inviteFriends,
	})
	local cards = CoopInviteView.new(playerGui, answer)
	notices = cards
	-- The invitation card goes over the score area, which is wherever the layout puts it (top of the screen in
	-- portrait, above the tray in landscape), so it never covers the board or the pieces. While the Co-op screen is
	-- open the score area is hidden under it and the card would cover its close button, so the card moves to the
	-- top right corner of the screen instead.
	task.spawn(function()
		local views = GameController.getViews()
		while not views do
			task.wait()
			views = GameController.getViews()
		end
		local hud = views.gui.hudArea
		local screen = cards.gui
		placeNotices = function()
			if view and view:isOpen() then
				local width = math.min(NOTICE_CORNER_WIDTH, screen.AbsoluteSize.X - 2 * NOTICE_CORNER_MARGIN)
				local corner = Vector2.new(screen.AbsoluteSize.X - width - NOTICE_CORNER_MARGIN, NOTICE_CORNER_MARGIN)
				cards:setAnchor(corner, Vector2.new(width, 0))
			else
				cards:setAnchor(hud.AbsolutePosition, hud.AbsoluteSize)
			end
		end
		hud:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeNotices)
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeNotices)
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeNotices)
		placeNotices()
	end)

	Net.CoopInvited.OnClientEvent:Connect(CoopController.onInvited)
	Net.CoopInviteResult.OnClientEvent:Connect(CoopController.onInviteResult)
	Net.CoopRoom.OnClientEvent:Connect(CoopController.onRoom)

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		watch(player)
		render()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		unwatch(player)
		task.defer(render) -- the player is still in the list until this frame ends
	end)
	render()
end

return CoopController
