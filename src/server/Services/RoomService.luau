--!strict
-- Connects Rooms (invitations and two-player rooms) to the remotes and to player lifetime, and tells the rest of
-- the server when a room is formed, loses a player or closes (M21's CoopService listens). Who may be invited
-- is published on each Player as attributes, so the Co-op screen needs no remote to list people:
--   CoopBusy  "room" (in a room), "tutorial" (hasn't finished it), "loading" (data not in yet), or nil (free)
--   Level     the player's level
-- Everything a client sends is rate limited and checked here before Rooms sees it: the client names a player by
-- UserId (a number), never by an instance, and there is no text to filter.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require("./DataService")
local GameService = require("./GameService")
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require("../Util/RateLimiter")
local Rooms = require("../Rooms")
local Validate = require("../Util/Validate")

local COOP = Config.COOP
local IS_STUDIO = RunService:IsStudio()
local DATA_WAIT_SECONDS = 15
local SWEEP_SECONDS = 1 -- how often invitations that ran out are noticed (answers are checked against the clock anyway)
local MAX_USER_ID = 2 ^ 53 -- Studio's test players have negative ids, so the range goes both ways

local RoomService = {}

local rooms: Rooms.Rooms
local inviteLimiter = RateLimiter.new(1, 2, os.clock) -- one invitation every two seconds
local replyLimiter = RateLimiter.new(4, 2, os.clock)
local cancelLimiter = RateLimiter.new(1, 1, os.clock)
local leaveLimiter = RateLimiter.new(1, 1, os.clock)
local formedListeners: { (room: Rooms.Room, inviteId: number?) -> () } = {}
local leftListeners: { (room: Rooms.Room, player: Player, seat: number) -> () } = {}
local closedListeners: { (room: Rooms.Room) -> () } = {}

-- The Co-op remotes do nothing until the mode is playable, except in Studio where it is being built. Duels likewise.
local function enabled(): boolean
	return COOP.ENABLED or IS_STUDIO
end

local function pvpEnabled(): boolean
	return Config.PVP.ENABLED or IS_STUDIO
end

-- The room kind an invitation asks for: 1 (or nothing) is Co-op, 2 a Duel. Nil for anything else.
local function modeOf(code: unknown): Rooms.Mode?
	if code == nil or code == 1 then
		return "coop"
	elseif code == 2 and pvpEnabled() then
		return "pvp"
	end
	return nil
end

local function isHere(player: Player): boolean
	return player.Parent == Players
end

-- Publishes whether the player can be invited, and their level.
local function refreshStatus(player: Player)
	if not isHere(player) then
		return
	end
	local data = DataService.get(player)
	local busy: string? = nil
	if rooms:roomOf(player) then
		busy = "room"
	elseif not data then
		busy = "loading"
	elseif not data.tutorialDone then
		busy = "tutorial"
	end
	player:SetAttribute("CoopBusy", busy)
	if data then
		player:SetAttribute("Level", data.level)
	end
end

-- The room as one player's client sees it: their seat, and who is in it by seat.
local function payloadOf(room: Rooms.Room, player: Player): any
	local userIds = {}
	for seat, member in room.players do
		userIds[seat] = (member :: Player).UserId
	end
	return {
		id = room.id,
		mode = room.mode,
		you = table.find(room.players, player),
		present = room.present,
		userIds = userIds,
	}
end

local function emit(event: Rooms.Event)
	if event.kind == "invited" then
		if event.mode == "coop" then
			GameService.logCoopInvite(event.from, event.inviteId, 1) -- Sent
		end
		local to = event.to :: Player
		if isHere(to) then
			-- Rooms counts in os.clock(); the client needs a time it shares with the server.
			local expiresAt = workspace:GetServerTimeNow() + (event.expiresAt - os.clock())
			Net.CoopInvited:FireClient(to, event.inviteId, (event.from :: Player).UserId, expiresAt, event.mode)
		end
	elseif event.kind == "result" then
		local to = event.to :: Player
		if isHere(to) then
			Net.CoopInviteResult:FireClient(to, (event.other :: Player).UserId, event.result)
		end
	elseif event.kind == "room" then
		local to = event.to :: Player
		if isHere(to) then
			Net.CoopRoom:FireClient(to, if event.room then payloadOf(event.room, to) else nil)
			refreshStatus(to)
		end
	elseif event.kind == "formed" then
		if event.inviteId and event.room.mode == "coop" then
			GameService.logCoopInvite(event.room.players[1], event.inviteId, 2) -- Accepted
		end
		for _, listener in formedListeners do
			task.spawn(listener, event.room, event.inviteId)
		end
	elseif event.kind == "memberLeft" then
		for _, listener in leftListeners do
			task.spawn(listener, event.room, event.player :: Player, event.seat)
		end
	else
		for _, listener in closedListeners do
			task.spawn(listener, event.room)
		end
	end
end

function RoomService.init(_self: any)
	rooms = Rooms.new({
		clock = os.clock,
		canPlay = function(player: any): boolean
			if typeof(player) ~= "Instance" then
				return (player :: any).IsBot == true -- the practice partner of the Studio debug bridge
			end
			local data = DataService.get(player :: Player)
			return data ~= nil and data.tutorialDone
		end,
		emit = emit,
		limits = {
			inviteSeconds = COOP.INVITE_SECONDS,
			cooldownSeconds = COOP.INVITE_COOLDOWN_SECONDS,
			maxIncoming = COOP.MAX_PENDING_INVITES,
		},
	})
end

local function onPlayerAdded(player: Player)
	refreshStatus(player) -- "loading" until the saved data is in
	if DataService.waitForData(player, DATA_WAIT_SECONDS) then
		refreshStatus(player)
	end
end

function RoomService.start(_self: any)
	Net.CoopInvite.OnServerEvent:Connect(function(player: Player, targetUserId: unknown, modeCode: unknown)
		if not enabled() or not inviteLimiter:allow(player) then
			return
		end
		local mode = modeOf(modeCode)
		if not mode then
			return
		end
		local userId = Validate.integer(targetUserId, -MAX_USER_ID, MAX_USER_ID)
		if not userId then
			return
		end
		local target = Players:GetPlayerByUserId(userId)
		if not target then
			Net.CoopInviteResult:FireClient(player, userId, "left") -- not in this server (any more)
			return
		end
		rooms:invite(player, target, mode)
	end)

	Net.CoopInviteReply.OnServerEvent:Connect(function(player: Player, inviteId: unknown, accept: unknown)
		if enabled() and replyLimiter:allow(player) then
			rooms:reply(player, inviteId, accept)
		end
	end)

	Net.CoopCancelInvite.OnServerEvent:Connect(function(player: Player)
		if enabled() and cancelLimiter:allow(player) then
			rooms:cancel(player)
		end
	end)

	Net.CoopLeave.OnServerEvent:Connect(function(player: Player)
		if enabled() and leaveLimiter:allow(player) then
			rooms:leave(player)
		end
	end)

	-- A player is in one thing at a time: starting a solo run leaves the room.
	Net.StartGame.OnServerEvent:Connect(function(player: Player)
		rooms:leave(player)
	end)

	GameService.onTutorialDone(refreshStatus)
	GameService.onGameOver(refreshStatus) -- a run may have raised the level

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		rooms:remove(player)
		inviteLimiter:forget(player)
		replyLimiter:forget(player)
		cancelLimiter:forget(player)
		leaveLimiter:forget(player)
	end)

	while true do
		task.wait(SWEEP_SECONDS)
		rooms:sweep()
	end
end

-- Called with the room when two players have formed one (players are Player instances, seat 1 invited) and the id of
-- the invitation that made it (nil for a room the ranked queue formed without one).
function RoomService.onRoomFormed(callback: (room: Rooms.Room, inviteId: number?) -> ())
	table.insert(formedListeners, callback)
end

-- Called with the room (as it is after) when a player leaves it, by leaving or by leaving the server.
function RoomService.onMemberLeft(callback: (room: Rooms.Room, player: Player, seat: number) -> ())
	table.insert(leftListeners, callback)
end

-- Called with the room (as it was) when its last player has left.
function RoomService.onRoomClosed(callback: (room: Rooms.Room) -> ())
	table.insert(closedListeners, callback)
end

function RoomService.roomOf(player: Player): Rooms.Room?
	return rooms:roomOf(player)
end

-- Takes the player out of their room, if they are in one.
function RoomService.leave(player: Player): boolean
	return rooms:leave(player)
end

-- For the Studio debug bridge (and, later, practice against a bot): puts the player in a room of `mode` (default
-- "coop") with a practice partner (a table with UserId, Name and IsBot, which is not in Players and hears nothing).
-- False when the player can't be invited.
function RoomService.pairWithBot(player: Player, bot: any, mode: Rooms.Mode?): boolean
	local outcome = rooms:invite(player, bot, mode or "coop")
	if outcome.kind ~= "sent" then
		return false
	end
	return rooms:reply(bot, outcome.inviteId, true).kind == "joined"
end

-- Publishes the player's status again, e.g. after the Studio debug bridge resets their data.
function RoomService.refresh(player: Player)
	refreshStatus(player)
end

-- For the Studio debug bridge: open invitations, rooms, rests, and what each player's attributes say.
function RoomService.describe(): string
	local lines = {
		rooms:describe(function(player: any): string
			return (player :: Player).Name
		end),
	}
	for _, player in Players:GetPlayers() do
		table.insert(
			lines,
			`{player.Name} ({player.UserId}): CoopBusy={player:GetAttribute("CoopBusy")} Level={player:GetAttribute(
				"Level"
			)}`
		)
	end
	return table.concat(lines, "\n")
end

return RoomService
