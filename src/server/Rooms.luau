--!strict
-- Invitations and two-player rooms. It knows nothing about the game played in a room: a room only carries a
-- `mode` ("coop" now, "pvp" later) and who is in it. Pure Luau so Lune can test it with fake players and a fake
-- clock; RoomService wires it to the remotes and to Players.
--
-- Rules:
--   * A player has at most one invitation out and `maxIncoming` waiting for an answer. An invitation lasts
--     `inviteSeconds`; one that is declined or runs out puts the pair on a `cooldownSeconds` rest.
--   * Nobody can invite themselves, someone in a room, or someone who can't play yet (`canPlay`); the inviter has
--     to be able to play and be out of a room too.
--   * If A invites B while B's invitation to A is open, that counts as A accepting it.
--   * Whoever joins a room drops everything else: the invitations they sent are withdrawn and the ones waiting
--     for them are answered "busy".
--   * A room outlives the first player to leave; it is gone when the last one leaves. Seat 1 is whoever invited.
--
-- Everything that has to reach a player goes out through `deps.emit` as an event addressed to them (`to`).
-- Players are opaque keys (Player instances in the game, strings in tests).

export type Mode = "coop" -- "pvp" arrives with phase 6

export type Limits = { inviteSeconds: number, cooldownSeconds: number, maxIncoming: number }

-- A copy of a room as it is right now: both players by seat, and who of them is still in it.
export type Room = { id: number, mode: Mode, players: { any }, present: { boolean } }

-- How an invitation ended, as told to the player on the other end. The inviter hears sent, declined, expired,
-- busy, cooldown or left; the invitee hears expired or cancelled (the invitation is gone from their screen).
export type Result = "sent" | "declined" | "expired" | "busy" | "cooldown" | "left" | "cancelled"

export type Event =
	{ kind: "invited", to: any, from: any, inviteId: number, expiresAt: number } -- expiresAt is on deps.clock
	| { kind: "result", to: any, other: any, result: Result } -- tell `to` how its invitation with `other` stands
	| { kind: "room", to: any, room: Room? } -- tell `to` its room is this one now, or that it has none
	| { kind: "formed", room: Room, inviteId: number } -- for other services: a room was formed, from this invitation
	| { kind: "memberLeft", room: Room, player: any, seat: number } -- room is as it is after they left
	| { kind: "closed", room: Room } -- the last member left; room is as it was just before

export type Deps = {
	clock: () -> number,
	canPlay: (player: any) -> boolean, -- in the server with their data loaded and the tutorial done
	emit: (event: Event) -> (),
	limits: Limits,
}

export type Refusal =
	"self"
	| "badMode"
	| "inviterNotReady"
	| "inviterInRoom"
	| "targetNotReady"
	| "targetInRoom"
	| "outgoingPending"
	| "targetBusy"
	| "cooldown"

export type InviteOutcome =
	{ kind: "sent", inviteId: number }
	| { kind: "joined", room: Room } -- the invitation answered one the target had sent
	| { kind: "refused", reason: Refusal }

export type ReplyOutcome = { kind: "joined", room: Room } | { kind: "declined" } | { kind: "ignored", reason: string }

type Invite = { id: number, from: any, to: any, mode: Mode, expiresAt: number }
type InternalRoom = { id: number, mode: Mode, players: { any }, present: { boolean } }

local MODES: { [string]: boolean } = { coop = true }

local Rooms = {}
Rooms.__index = Rooms

export type Rooms = typeof(setmetatable(
	{} :: {
		deps: Deps,
		invites: { [number]: Invite },
		outgoing: { [any]: Invite }, -- by inviter
		incoming: { [any]: { Invite } }, -- by invitee
		cooldowns: { [any]: { [any]: number } }, -- by either player of the pair: when the rest ends
		rooms: { [number]: InternalRoom },
		membership: { [any]: InternalRoom }, -- by player
		nextInviteId: number,
		nextRoomId: number,
	},
	Rooms
))

function Rooms.new(deps: Deps): Rooms
	return setmetatable({
		deps = deps,
		invites = {},
		outgoing = {},
		incoming = {},
		cooldowns = {},
		rooms = {},
		membership = {},
		nextInviteId = 1,
		nextRoomId = 1,
	}, Rooms)
end

local function snapshotOf(room: InternalRoom): Room
	return { id = room.id, mode = room.mode, players = table.clone(room.players), present = table.clone(room.present) }
end

local function emit(self: Rooms, event: Event)
	self.deps.emit(event)
end

local function say(self: Rooms, to: any, other: any, result: Result)
	emit(self, { kind = "result", to = to, other = other, result = result })
end

-- Takes an invitation out of every table; telling anyone is up to the caller.
local function drop(self: Rooms, invite: Invite)
	self.invites[invite.id] = nil
	if self.outgoing[invite.from] == invite then
		self.outgoing[invite.from] = nil
	end
	local waiting = self.incoming[invite.to]
	if waiting then
		local index = table.find(waiting, invite)
		if index then
			table.remove(waiting, index)
		end
		if #waiting == 0 then
			self.incoming[invite.to] = nil
		end
	end
end

local function startCooldown(self: Rooms, a: any, b: any)
	local resumesAt = self.deps.clock() + self.deps.limits.cooldownSeconds
	for _, pair in { { a, b }, { b, a } } do
		local rests = self.cooldowns[pair[1]]
		if not rests then
			rests = {}
			self.cooldowns[pair[1]] = rests
		end
		rests[pair[2]] = resumesAt
	end
end

local function isResting(self: Rooms, a: any, b: any): boolean
	local rests = self.cooldowns[a]
	local resumesAt = if rests then rests[b] else nil
	return resumesAt ~= nil and resumesAt > self.deps.clock()
end

local function forgetCooldowns(self: Rooms, player: any)
	local rests = self.cooldowns[player]
	if not rests then
		return
	end
	for other in rests do
		local theirs = self.cooldowns[other]
		if theirs then
			theirs[player] = nil
			if next(theirs) == nil then
				self.cooldowns[other] = nil
			end
		end
	end
	self.cooldowns[player] = nil
end

-- The ways an invitation ends without a room.
local function decline(self: Rooms, invite: Invite)
	drop(self, invite)
	startCooldown(self, invite.from, invite.to)
	say(self, invite.from, invite.to, "declined")
end

local function expire(self: Rooms, invite: Invite)
	drop(self, invite)
	startCooldown(self, invite.from, invite.to)
	say(self, invite.from, invite.to, "expired")
	say(self, invite.to, invite.from, "expired")
end

local function withdraw(self: Rooms, invite: Invite) -- the inviter took it back, or left, or joined a room
	drop(self, invite)
	say(self, invite.to, invite.from, "cancelled")
end

local function inviteeLeft(self: Rooms, invite: Invite)
	drop(self, invite)
	say(self, invite.from, invite.to, "left")
end

local function inviteeBusy(self: Rooms, invite: Invite) -- the invitee joined a room by another way
	drop(self, invite)
	say(self, invite.from, invite.to, "busy")
	say(self, invite.to, invite.from, "cancelled")
end

local function expireDue(self: Rooms)
	local now = self.deps.clock()
	local due: { Invite } = {}
	for _, invite in self.invites do
		if invite.expiresAt <= now then
			table.insert(due, invite)
		end
	end
	table.sort(due, function(a: Invite, b: Invite): boolean
		return a.id < b.id
	end)
	for _, invite in due do
		expire(self, invite)
	end
end

-- Makes a room of the invitation's two players and ends everything else either of them had going.
local function formRoom(self: Rooms, invite: Invite): Room
	drop(self, invite)
	local host, guest = invite.from, invite.to
	local room: InternalRoom = {
		id = self.nextRoomId,
		mode = invite.mode,
		players = { host, guest },
		present = { true, true },
	}
	self.nextRoomId += 1
	self.rooms[room.id] = room
	self.membership[host] = room
	self.membership[guest] = room

	for _, player in room.players do
		local sent = self.outgoing[player]
		if sent then
			withdraw(self, sent)
		end
		local waiting = self.incoming[player]
		if waiting then
			for _, other in table.clone(waiting) do
				inviteeBusy(self, other)
			end
		end
	end

	local snapshot = snapshotOf(room)
	emit(self, { kind = "formed", room = snapshot, inviteId = invite.id })
	emit(self, { kind = "room", to = host, room = snapshot })
	emit(self, { kind = "room", to = guest, room = snapshot })
	return snapshot
end

-- Invites `to` to a room in `mode` (default "coop"). Refusals that the inviter should hear about are emitted as
-- results ("busy", "cooldown"); the others come from a client that shouldn't have asked, and are silent.
function Rooms.invite(self: Rooms, from: any, to: any, mode: unknown?): InviteOutcome
	expireDue(self)
	local roomMode: Mode = "coop"
	if mode ~= nil then
		if typeof(mode) ~= "string" or not MODES[mode :: string] then
			return { kind = "refused", reason = "badMode" }
		end
		roomMode = mode :: any
	end
	if from == to then
		return { kind = "refused", reason = "self" }
	elseif not self.deps.canPlay(from) then
		return { kind = "refused", reason = "inviterNotReady" }
	elseif self.membership[from] then
		return { kind = "refused", reason = "inviterInRoom" }
	end

	-- The target already invited the inviter: say yes to that one instead of sending a second.
	for _, theirs in self.incoming[from] or {} do
		if theirs.from == to then
			return { kind = "joined", room = formRoom(self, theirs) }
		end
	end

	local reason: Refusal? = nil
	if not self.deps.canPlay(to) then
		reason = "targetNotReady"
	elseif self.membership[to] then
		reason = "targetInRoom"
	elseif self.outgoing[from] then
		reason = "outgoingPending"
	elseif #(self.incoming[to] or {}) >= self.deps.limits.maxIncoming then
		reason = "targetBusy"
	end
	if reason then
		say(self, from, to, "busy")
		return { kind = "refused", reason = reason }
	end
	if isResting(self, from, to) then
		say(self, from, to, "cooldown")
		return { kind = "refused", reason = "cooldown" }
	end

	local invite: Invite = {
		id = self.nextInviteId,
		from = from,
		to = to,
		mode = roomMode,
		expiresAt = self.deps.clock() + self.deps.limits.inviteSeconds,
	}
	self.nextInviteId += 1
	self.invites[invite.id] = invite
	self.outgoing[from] = invite
	local waiting = self.incoming[to]
	if not waiting then
		waiting = {}
		self.incoming[to] = waiting
	end
	table.insert(waiting, invite)
	emit(self, { kind = "invited", to = to, from = from, inviteId = invite.id, expiresAt = invite.expiresAt })
	say(self, from, to, "sent")
	return { kind = "sent", inviteId = invite.id }
end

-- `player` answers invitation `inviteId`. Only the invited player can, and only while it is open.
function Rooms.reply(self: Rooms, player: any, inviteId: unknown, accept: unknown): ReplyOutcome
	expireDue(self)
	if typeof(inviteId) ~= "number" or typeof(accept) ~= "boolean" then
		return { kind = "ignored", reason = "badArguments" }
	end
	local invite = self.invites[inviteId :: number]
	if not invite then
		return { kind = "ignored", reason = "unknownInvite" }
	elseif invite.to ~= player then
		return { kind = "ignored", reason = "notInvited" }
	end
	if accept == false then
		decline(self, invite)
		return { kind = "declined" }
	end
	return { kind = "joined", room = formRoom(self, invite) }
end

-- The inviter takes back their open invitation. False when they had none.
function Rooms.cancel(self: Rooms, player: any): boolean
	local invite = self.outgoing[player]
	if not invite then
		return false
	end
	withdraw(self, invite)
	return true
end

local function leaveRoom(self: Rooms, player: any, tellThem: boolean): boolean
	local room = self.membership[player]
	if not room then
		return false
	end
	local seat = table.find(room.players, player) :: number
	room.present[seat] = false
	self.membership[player] = nil
	if tellThem then
		emit(self, { kind = "room", to = player, room = nil })
	end
	emit(self, { kind = "memberLeft", room = snapshotOf(room), player = player, seat = seat })
	local other = room.players[3 - seat]
	if room.present[3 - seat] then
		emit(self, { kind = "room", to = other, room = snapshotOf(room) })
	else
		self.rooms[room.id] = nil
		emit(self, { kind = "closed", room = snapshotOf(room) })
	end
	return true
end

-- `player` leaves their room. False when they weren't in one.
function Rooms.leave(self: Rooms, player: any): boolean
	return leaveRoom(self, player, true)
end

-- `player` is gone (left the server): nothing may refer to them afterwards, and nobody is told anything on
-- their behalf. Their open invitation is withdrawn, the ones waiting for them are answered "left", and their
-- partner hears they left the room.
function Rooms.remove(self: Rooms, player: any)
	local sent = self.outgoing[player]
	if sent then
		withdraw(self, sent)
	end
	for _, invite in table.clone(self.incoming[player] or {}) do
		inviteeLeft(self, invite)
	end
	leaveRoom(self, player, false)
	forgetCooldowns(self, player)
end

-- Ends the invitations that have run out and forgets rests that are over. Call it about once a second.
function Rooms.sweep(self: Rooms)
	expireDue(self)
	local now = self.deps.clock()
	for player, rests in self.cooldowns do
		for other, resumesAt in rests do
			if resumesAt <= now then
				rests[other] = nil
			end
		end
		if next(rests) == nil then
			self.cooldowns[player] = nil
		end
	end
end

-- The player's room as it is right now, or nil.
function Rooms.roomOf(self: Rooms, player: any): Room?
	local room = self.membership[player]
	return if room then snapshotOf(room) else nil
end

-- The invitation `player` has out, as { id, to, expiresAt }, or nil.
function Rooms.outgoingOf(self: Rooms, player: any): { id: number, to: any, expiresAt: number }?
	local invite = self.outgoing[player]
	return if invite then { id = invite.id, to = invite.to, expiresAt = invite.expiresAt } else nil
end

-- The invitations waiting for `player`'s answer, oldest first.
function Rooms.incomingOf(self: Rooms, player: any): { { id: number, from: any, expiresAt: number } }
	local list = {}
	for _, invite in self.incoming[player] or {} do
		table.insert(list, { id = invite.id, from = invite.from, expiresAt = invite.expiresAt })
	end
	return list
end

-- How many entries every table holds; zero once everyone is gone and the rests have run out.
function Rooms.footprint(self: Rooms): number
	local count = 0
	for _ in self.invites do
		count += 1
	end
	for _ in self.outgoing do
		count += 1
	end
	for _, list in self.incoming do
		count += 1 + #list
	end
	for _, rests in self.cooldowns do
		count += 1
		for _ in rests do
			count += 1
		end
	end
	for _ in self.rooms do
		count += 1
	end
	for _ in self.membership do
		count += 1
	end
	return count
end

-- For the Studio debug bridge: open invitations, rooms and rests, one per line.
function Rooms.describe(self: Rooms, nameOf: (player: any) -> string): string
	local now = self.deps.clock()
	local lines: { string } = {}
	for _, invite in self.invites do
		table.insert(
			lines,
			`invite {invite.id}: {nameOf(invite.from)} -> {nameOf(invite.to)} ({invite.mode}) expires in {math.max(
				0,
				invite.expiresAt - now
			)} s`
		)
	end
	for _, room in self.rooms do
		local names: { string } = {}
		for seat, player in room.players do
			table.insert(names, `{nameOf(player)}{if room.present[seat] then "" else " (left)"}`)
		end
		table.insert(lines, `room {room.id} ({room.mode}): {table.concat(names, ", ")}`)
	end
	for player, rests in self.cooldowns do
		for other, resumesAt in rests do
			table.insert(lines, `rest {nameOf(player)} / {nameOf(other)}: {math.max(0, resumesAt - now)} s left`)
		end
	end
	table.sort(lines)
	return if #lines > 0 then table.concat(lines, "\n") else "no invitations, rooms or rests"
end

return Rooms
