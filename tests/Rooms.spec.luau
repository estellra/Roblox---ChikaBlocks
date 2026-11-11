--!strict
local Rng = require("../src/shared/Rng")
local Rooms = require("../src/server/Rooms")
local TestKit = require("./TestKit")

local LIMITS: Rooms.Limits = { inviteSeconds = 30, cooldownSeconds = 60, maxIncoming = 3 }
local START = 100

type Harness = {
	rooms: Rooms.Rooms,
	clock: { now: number },
	events: { Rooms.Event },
	ready: { [string]: boolean }, -- who can play; players are plain strings here
}

-- A Rooms with a fake clock, a fake "can play" list and a recorder of everything it emits.
local function harness(players: { string }): Harness
	local clock = { now = START }
	local events: { Rooms.Event } = {}
	local ready: { [string]: boolean } = {}
	for _, name in players do
		ready[name] = true
	end
	local rooms = Rooms.new({
		clock = function(): number
			return clock.now
		end,
		canPlay = function(player: any): boolean
			return ready[player] == true
		end,
		emit = function(event: Rooms.Event)
			table.insert(events, event)
		end,
		limits = LIMITS,
	})
	return { rooms = rooms, clock = clock, events = events, ready = ready }
end

local function roomText(room: Rooms.Room): string
	local names: { string } = {}
	for seat, player in room.players do
		table.insert(names, `{player}{if room.present[seat] then "" else "-"}`)
	end
	return `{room.id}:{table.concat(names, ",")}`
end

-- Every event as one short line, e.g. "A hears B:declined" or "B room 1:A,B".
local function lines(events: { Rooms.Event }): { string }
	local out: { string } = {}
	for _, event in events do
		if event.kind == "invited" then
			table.insert(out, `{event.to} invited by {event.from} until {event.expiresAt}`)
		elseif event.kind == "result" then
			table.insert(out, `{event.to} hears {event.other}:{event.result}`)
		elseif event.kind == "room" then
			table.insert(out, `{event.to} room {if event.room then roomText(event.room) else "none"}`)
		elseif event.kind == "formed" then
			table.insert(out, `formed {roomText(event.room)}`)
		elseif event.kind == "memberLeft" then
			table.insert(out, `left {event.player} seat{event.seat} {roomText(event.room)}`)
		else
			table.insert(out, `closed {roomText(event.room)}`)
		end
	end
	return out
end

-- The id of the invitation a "formed" event came from, if one was emitted.
local function formedInvite(events: { Rooms.Event }): number?
	for _, event in events do
		if event.kind == "formed" then
			return event.inviteId
		end
	end
	return nil
end

-- Invites and returns the invitation's id (it has to be sent).
local function send(h: Harness, from: string, to: string): number
	local outcome = h.rooms:invite(from, to)
	if outcome.kind ~= "sent" then
		error(`{from} -> {to} was not sent: {outcome.kind}`)
	end
	return outcome.inviteId
end

-- Invites and answers yes: the pair is in a room afterwards.
local function pair(h: Harness, from: string, to: string)
	h.rooms:reply(to, send(h, from, to), true)
end

return function(t: TestKit.TestKit)
	t.describe("Rooms", function()
		t.it("sends an invitation and tells both sides", function()
			local h = harness({ "A", "B" })
			local id = send(h, "A", "B")
			t.expect(lines(h.events)).toEqual({ "B invited by A until 130", "A hears B:sent" })
			local sent = h.rooms:outgoingOf("A")
			assert(sent, "A has an invitation out")
			t.expect(sent.id).toBe(id)
			t.expect(sent.to).toBe("B")
			t.expect(sent.expiresAt).toBe(130)
			t.expect(h.rooms:incomingOf("B")).toEqual({ { id = id, from = "A", expiresAt = 130 } })
		end)

		t.it("makes a room when the invitation is accepted, with the inviter in seat 1", function()
			local h = harness({ "A", "B" })
			local id = send(h, "A", "B")
			table.clear(h.events)
			local outcome = h.rooms:reply("B", id, true)
			t.expect(outcome.kind).toBe("joined")
			t.expect(lines(h.events)).toEqual({ "formed 1:A,B", "A room 1:A,B", "B room 1:A,B" })
			local room = h.rooms:roomOf("B")
			assert(room, "B is in a room")
			t.expect(room.players).toEqual({ "A", "B" })
			t.expect(room.present).toEqual({ true, true })
			t.expect(room.mode).toBe("coop")
			t.expect(h.rooms:roomOf("A")).toEqual(room)
			t.expect(h.rooms:outgoingOf("A")).toBe(nil)
			t.expect(h.rooms:incomingOf("B")).toEqual({})
		end)

		t.it("tells the inviter about a decline and rests the pair for a minute, in both directions", function()
			local h = harness({ "A", "B" })
			local outcome = h.rooms:reply("B", send(h, "A", "B"), false)
			t.expect(outcome.kind).toBe("declined")
			t.expect(lines(h.events)).toEqual({
				"B invited by A until 130",
				"A hears B:sent",
				"A hears B:declined",
			})
			t.expect(h.rooms:roomOf("A")).toBe(nil)

			table.clear(h.events)
			t.expect(h.rooms:invite("A", "B")).toEqual({ kind = "refused", reason = "cooldown" })
			t.expect(h.rooms:invite("B", "A")).toEqual({ kind = "refused", reason = "cooldown" })
			t.expect(lines(h.events)).toEqual({ "A hears B:cooldown", "B hears A:cooldown" })

			h.clock.now = START + 59
			t.expect(h.rooms:invite("A", "B").kind).toBe("refused")
			h.clock.now = START + 60
			t.expect(h.rooms:invite("A", "B").kind).toBe("sent")
		end)

		t.it("lets an invitation run out after 30 seconds and rests the pair", function()
			local h = harness({ "A", "B" })
			send(h, "A", "B")
			table.clear(h.events)
			h.clock.now = START + 29
			h.rooms:sweep()
			t.expect(lines(h.events)).toEqual({})
			h.clock.now = START + 30
			h.rooms:sweep()
			t.expect(lines(h.events)).toEqual({ "A hears B:expired", "B hears A:expired" })
			t.expect(h.rooms:outgoingOf("A")).toBe(nil)
			t.expect(h.rooms:incomingOf("B")).toEqual({})
			t.expect(h.rooms:invite("A", "B")).toEqual({ kind = "refused", reason = "cooldown" })
		end)

		t.it("does not accept an answer that comes after the invitation ran out, even before a sweep", function()
			local h = harness({ "A", "B" })
			local id = send(h, "A", "B")
			table.clear(h.events)
			h.clock.now = START + 31
			t.expect(h.rooms:reply("B", id, true)).toEqual({ kind = "ignored", reason = "unknownInvite" })
			t.expect(h.rooms:roomOf("B")).toBe(nil)
			t.expect(lines(h.events)).toEqual({ "A hears B:expired", "B hears A:expired" })
		end)

		t.it("refuses invitations that make no sense, telling the inviter only when it is useful", function()
			local h = harness({ "A", "B", "C", "D" })
			t.expect(h.rooms:invite("A", "A")).toEqual({ kind = "refused", reason = "self" })
			t.expect(h.rooms:invite("A", "B", "pvp")).toEqual({ kind = "refused", reason = "badMode" })
			t.expect(h.rooms:invite("A", "B", 5)).toEqual({ kind = "refused", reason = "badMode" })
			h.ready.D = false
			t.expect(h.rooms:invite("D", "A")).toEqual({ kind = "refused", reason = "inviterNotReady" })
			t.expect(lines(h.events)).toEqual({}) -- all silent: a client that works never sends these

			t.expect(h.rooms:invite("A", "D")).toEqual({ kind = "refused", reason = "targetNotReady" })
			pair(h, "B", "C")
			table.clear(h.events)
			t.expect(h.rooms:invite("A", "B")).toEqual({ kind = "refused", reason = "targetInRoom" })
			t.expect(h.rooms:invite("B", "A")).toEqual({ kind = "refused", reason = "inviterInRoom" })
			t.expect(lines(h.events)).toEqual({ "A hears B:busy" })
		end)

		t.it("takes an invitation to someone who invited you as a yes, and the first inviter hosts", function()
			local h = harness({ "A", "B" })
			send(h, "A", "B")
			table.clear(h.events)
			local outcome = h.rooms:invite("B", "A")
			t.expect(outcome.kind).toBe("joined")
			t.expect(lines(h.events)).toEqual({ "formed 1:A,B", "A room 1:A,B", "B room 1:A,B" })
			local room = h.rooms:roomOf("A")
			assert(room, "A is in a room")
			t.expect(room.players).toEqual({ "A", "B" })
			t.expect(h.rooms:outgoingOf("B")).toBe(nil)
		end)

		t.it("allows one invitation out at a time, and lets the inviter take it back", function()
			local h = harness({ "A", "B", "C" })
			send(h, "A", "B")
			table.clear(h.events)
			t.expect(h.rooms:invite("A", "C")).toEqual({ kind = "refused", reason = "outgoingPending" })
			t.expect(lines(h.events)).toEqual({ "A hears C:busy" })

			table.clear(h.events)
			t.expect(h.rooms:cancel("A")).toBe(true)
			t.expect(lines(h.events)).toEqual({ "B hears A:cancelled" })
			t.expect(h.rooms:cancel("A")).toBe(false)
			t.expect(h.rooms:incomingOf("B")).toEqual({})
			t.expect(h.rooms:invite("A", "C").kind).toBe("sent") -- taking it back is no reason to rest
		end)

		t.it("keeps at most three invitations waiting for one player", function()
			local h = harness({ "A", "B", "C", "D", "E" })
			send(h, "A", "B")
			send(h, "C", "B")
			local third = send(h, "D", "B")
			t.expect(#h.rooms:incomingOf("B")).toBe(3)
			table.clear(h.events)
			t.expect(h.rooms:invite("E", "B")).toEqual({ kind = "refused", reason = "targetBusy" })
			t.expect(lines(h.events)).toEqual({ "E hears B:busy" })

			h.rooms:reply("B", third, false)
			t.expect(h.rooms:invite("E", "B").kind).toBe("sent")
		end)

		t.it("lets only the invited player answer, and ignores answers that are not even well formed", function()
			local h = harness({ "A", "B", "C" })
			local id = send(h, "A", "B")
			table.clear(h.events)
			local footprint = h.rooms:footprint()

			t.expect(h.rooms:reply("C", id, true)).toEqual({ kind = "ignored", reason = "notInvited" })
			t.expect(h.rooms:reply("A", id, true)).toEqual({ kind = "ignored", reason = "notInvited" })
			t.expect(h.rooms:reply("B", id + 99, true)).toEqual({ kind = "ignored", reason = "unknownInvite" })
			local badIds: { any } = { 0 / 0, "1", {}, true, math.huge, -1, 0.5 }
			for _, bad in badIds do
				t.expect(h.rooms:reply("B", bad, true).kind).toBe("ignored")
			end
			t.expect(h.rooms:reply("B", nil, true).kind).toBe("ignored")
			local badAnswers: { any } = { "yes", 1, 0, {} }
			for _, bad in badAnswers do
				t.expect(h.rooms:reply("B", id, bad)).toEqual({ kind = "ignored", reason = "badArguments" })
			end
			t.expect(h.rooms:reply("B", id)).toEqual({ kind = "ignored", reason = "badArguments" })

			t.expect(lines(h.events)).toEqual({})
			t.expect(h.rooms:footprint()).toBe(footprint)
			t.expect(h.rooms:reply("B", id, true).kind).toBe("joined")
		end)

		t.it("ends everything else both players had going when a room forms", function()
			local h = harness({ "A", "B", "C", "D", "E" })
			send(h, "B", "C") -- B's own invitation out
			send(h, "D", "B") -- one waiting for B
			send(h, "E", "A") -- one waiting for A
			local id = send(h, "A", "B") -- the one B accepts
			table.clear(h.events)
			t.expect(h.rooms:reply("B", id, true).kind).toBe("joined")
			t.expect(lines(h.events)).toEqual({
				"E hears A:busy",
				"A hears E:cancelled",
				"C hears B:cancelled",
				"D hears B:busy",
				"B hears D:cancelled",
				"formed 1:A,B",
				"A room 1:A,B",
				"B room 1:A,B",
			})
			for _, name in { "A", "B", "C", "D", "E" } do
				t.expect(h.rooms:outgoingOf(name)).toBe(nil)
				t.expect(h.rooms:incomingOf(name)).toEqual({})
			end
		end)

		t.it("keeps a room around for the player who stays and closes it when the last one leaves", function()
			local h = harness({ "A", "B", "C" })
			pair(h, "A", "B")
			table.clear(h.events)

			t.expect(h.rooms:leave("A")).toBe(true)
			t.expect(lines(h.events)).toEqual({ "A room none", "left A seat1 1:A-,B", "B room 1:A-,B" })
			t.expect(h.rooms:roomOf("A")).toBe(nil)
			local room = h.rooms:roomOf("B")
			assert(room, "B is still in the room")
			t.expect(room.present).toEqual({ false, true })
			t.expect(h.rooms:leave("A")).toBe(false)

			-- B still counts as being in a room, A is free again.
			table.clear(h.events)
			t.expect(h.rooms:invite("C", "B")).toEqual({ kind = "refused", reason = "targetInRoom" })
			t.expect(h.rooms:invite("A", "C").kind).toBe("sent")

			table.clear(h.events)
			t.expect(h.rooms:leave("B")).toBe(true)
			t.expect(lines(h.events)).toEqual({ "B room none", "left B seat2 1:A-,B-", "closed 1:A-,B-" })
			t.expect(h.rooms:roomOf("B")).toBe(nil)
			h.rooms:cancel("A")
			t.expect(h.rooms:footprint()).toBe(0)
		end)

		t.it("withdraws what a player who left the server had out, and answers what was waiting for them", function()
			local h = harness({ "A", "B", "C" })
			send(h, "A", "B")
			table.clear(h.events)
			h.rooms:remove("A")
			t.expect(lines(h.events)).toEqual({ "B hears A:cancelled" })
			t.expect(h.rooms:footprint()).toBe(0)

			table.clear(h.events)
			send(h, "C", "B")
			table.clear(h.events)
			h.rooms:remove("B")
			t.expect(lines(h.events)).toEqual({ "C hears B:left" })
			t.expect(h.rooms:outgoingOf("C")).toBe(nil)
			t.expect(h.rooms:invite("C", "A").kind).toBe("sent") -- C isn't stuck behind an invitation to nobody
		end)

		t.it("tells the partner when a player leaves the server from a room, and tells the leaver nothing", function()
			local h = harness({ "A", "B" })
			pair(h, "A", "B")
			table.clear(h.events)
			h.rooms:remove("A")
			t.expect(lines(h.events)).toEqual({ "left A seat1 1:A-,B", "B room 1:A-,B" })
			table.clear(h.events)
			h.rooms:remove("B")
			t.expect(lines(h.events)).toEqual({ "left B seat2 1:A-,B-", "closed 1:A-,B-" })
			t.expect(h.rooms:footprint()).toBe(0)
			h.rooms:remove("nobody") -- someone who never did anything
			t.expect(h.rooms:footprint()).toBe(0)
		end)

		t.it("forgets rests when a player leaves the server, and lets them run out otherwise", function()
			local h = harness({ "A", "B", "C" })
			h.rooms:reply("B", send(h, "A", "B"), false)
			h.rooms:reply("C", send(h, "A", "C"), false)
			t.expect(h.rooms:footprint() > 0).toBe(true)
			h.rooms:remove("A")
			t.expect(h.rooms:footprint()).toBe(0)

			h.rooms:reply("B", send(h, "A", "B"), false)
			h.clock.now = START + 59
			h.rooms:sweep()
			t.expect(h.rooms:footprint() > 0).toBe(true)
			h.clock.now = START + 60
			h.rooms:sweep()
			t.expect(h.rooms:footprint()).toBe(0)
		end)

		t.it("names the invitation that formed a room, also when it was answered by inviting back", function()
			local h = harness({ "A", "B", "C", "D" })
			local id = send(h, "A", "B")
			table.clear(h.events)
			h.rooms:reply("B", id, true)
			t.expect(formedInvite(h.events)).toBe(id)

			local first = send(h, "C", "D")
			table.clear(h.events)
			h.rooms:invite("D", "C") -- takes C's invitation as a yes
			t.expect(formedInvite(h.events)).toBe(first)
		end)

		t.it("describes what it holds for the debug bridge", function()
			local h = harness({ "A", "B", "C", "D" })
			pair(h, "A", "B")
			send(h, "C", "D")
			h.rooms:reply("D", h.rooms:incomingOf("D")[1].id, false)
			local text = h.rooms:describe(tostring)
			t.expect(string.find(text, "room 1 (coop): A, B", 1, true) ~= nil).toBe(true)
			t.expect(string.find(text, "rest C / D: 60 s left", 1, true) ~= nil).toBe(true)
			t.expect(Rooms.new(h.rooms.deps):describe(tostring)).toBe("no invitations, rooms or rests")
		end)

		t.it("keeps its invariants over 300 random actions by six players, and leaves nothing behind", function()
			local PLAYERS = { "A", "B", "C", "D", "E", "F" }
			local rng = Rng.new(19)
			local h = harness(PLAYERS)
			local here: { [string]: boolean } = {}
			for _, name in PLAYERS do
				here[name] = true
			end
			local seen = { sent = 0, joined = 0, declined = 0, left = 0, rejoined = 0 }

			local function pick(): string?
				local present: { string } = {}
				for _, name in PLAYERS do
					if here[name] then
						table.insert(present, name)
					end
				end
				return if #present > 0 then present[rng:nextInt(1, #present)] else nil
			end

			local function checkInvariants()
				for _, name in PLAYERS do
					if not here[name] then
						t.expect(h.rooms:roomOf(name)).toBe(nil)
						t.expect(h.rooms:outgoingOf(name)).toBe(nil)
						t.expect(h.rooms:incomingOf(name)).toEqual({})
						continue
					end
					local room = h.rooms:roomOf(name)
					local sent = h.rooms:outgoingOf(name)
					local waiting = h.rooms:incomingOf(name)
					t.expect(#waiting <= LIMITS.maxIncoming).toBe(true)
					if room then
						-- Whoever is in a room has no invitations going either way.
						t.expect(sent).toBe(nil)
						t.expect(#waiting).toBe(0)
						t.expect(table.find(room.players, name) ~= nil).toBe(true)
					end
					if sent then
						t.expect(here[sent.to]).toBe(true)
						t.expect(h.rooms:incomingOf(sent.to)[1] ~= nil).toBe(true)
					end
					for _, invite in waiting do
						t.expect(here[invite.from]).toBe(true)
						local theirs = h.rooms:outgoingOf(invite.from)
						assert(theirs, "an invitation waiting for someone is out from someone")
						t.expect(theirs.id).toBe(invite.id)
					end
				end
			end

			for _ = 1, 300 do
				-- Now and then someone who left comes back (a new player under an old name).
				if rng:nextInt(1, 6) == 1 then
					for _, name in PLAYERS do
						if not here[name] then
							here[name] = true
							seen.rejoined += 1
							break
						end
					end
				end
				local actor = pick()
				if not actor then
					continue
				end
				local action = rng:nextInt(1, 20)
				if action <= 8 then
					local target = pick()
					if target then
						local outcome = h.rooms:invite(actor, target)
						if outcome.kind == "sent" then
							seen.sent += 1
						elseif outcome.kind == "joined" then
							seen.joined += 1
						end
					end
				elseif action <= 12 then
					local waiting = h.rooms:incomingOf(actor)
					if #waiting > 0 then
						local accept = rng:nextInt(1, 2) == 1
						local outcome = h.rooms:reply(actor, waiting[rng:nextInt(1, #waiting)].id, accept)
						if outcome.kind == "joined" then
							seen.joined += 1
						elseif outcome.kind == "declined" then
							seen.declined += 1
						end
					end
				elseif action == 13 then
					h.rooms:cancel(actor)
				elseif action <= 15 then
					h.rooms:leave(actor)
				elseif action <= 18 then
					h.clock.now += rng:nextInt(1, 45)
					h.rooms:sweep()
				else
					h.rooms:remove(actor)
					here[actor] = false
					seen.left += 1
				end
				checkInvariants()
			end
			-- Make sure the run actually exercised the interesting paths.
			t.expect(seen.sent > 20).toBe(true)
			t.expect(seen.joined > 3).toBe(true)
			t.expect(seen.declined > 3).toBe(true)
			t.expect(seen.left > 3).toBe(true)
			t.expect(seen.rejoined > 3).toBe(true)

			for _, name in PLAYERS do
				h.rooms:remove(name)
			end
			h.clock.now += LIMITS.cooldownSeconds
			h.rooms:sweep()
			t.expect(h.rooms:footprint()).toBe(0)
		end)
	end)
end
