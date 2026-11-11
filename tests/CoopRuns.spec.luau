--!strict
local Config = require("../src/shared/Config")
local CoopRuns = require("../src/server/CoopRuns")
local CoopSession = require("../src/shared/CoopSession")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local SIZE = Config.GRID_SIZE
local AFK = 45
local A, B = "A", "B" -- CoopRuns works with any key; in the game they are Players
local ROOM = { id = 1, players = { A, B }, present = { true, true } }

-- A CoopSession that always deals four 3x3 squares, so a run ends after a handful of moves.
local SQUARES = {
	new = CoopSession.new,
	seatOf = CoopSession.seatOf,
	newSource = function(_rng: any)
		return function(): { Pieces.Piece }?
			local O3 = Pieces.BY_ID.O3
			return { O3, O3, O3, O3 }
		end
	end,
}

type Harness = { runs: CoopRuns.CoopRuns, advance: (seconds: number) -> () }

local function harness(coopSession: any?): Harness
	local now = 0
	local seed = 0
	local runs = CoopRuns.new({
		CoopSession = coopSession or CoopSession,
		Rng = Rng,
		clock = function(): number
			return now
		end,
		newSeed = function(): number
			seed += 1
			return seed
		end,
		afkSeconds = AFK,
	})
	return {
		runs = runs,
		advance = function(seconds: number)
			now += seconds
		end,
	}
end

-- Starts the room's run and returns the states of the two seats.
local function started(h: Harness): (CoopRuns.State, CoopRuns.State)
	local states = h.runs:start(ROOM)
	assert(states, "the room can start a run")
	return states[1], states[2]
end

-- A valid move for `player` on the server's current board, from the pieces they may place.
local function legalMove(h: Harness, player: string): (number, number, number)
	local view = h.runs:peek(player)
	assert(view, `{player} is in a run`)
	local coop = view.coop
	for slot, piece in coop.session.tray do
		if piece then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if coop:canPlace(view.seat, slot, x, y) then
						return slot, x, y
					end
				end
			end
		end
	end
	error(`{player} has no valid move`)
end

local nextMoveId = 0
-- Places a legal move for `player` and returns the outcome (it has to be accepted).
local function play(h: Harness, player: string, runId: number): CoopRuns.PlaceOutcome
	local slot, x, y = legalMove(h, player)
	nextMoveId += 1
	local outcome = h.runs:place(player, runId, nextMoveId, slot, x, y)
	assert(outcome.kind == "accepted", `{player}'s legal move was {outcome.kind}`)
	return outcome
end

return function(t: TestKit.TestKit)
	t.describe("CoopRuns", function()
		t.it("starts a run with an empty board and four pieces, a state for each seat", function()
			local h = harness()
			local first, second = started(h)
			t.expect(first.runId).toBe(1)
			t.expect(first.seat).toBe(1)
			t.expect(second.seat).toBe(2)
			t.expect(first.seq).toBe(0)
			t.expect(first.takeOverIn).toBe(nil)
			t.expect(#first.session.game.tray).toBe(4)
			t.expect(first.session.game.score).toBe(0)
			t.expect(first.session.present).toEqual({ true, true })
			t.expect(second.session).toEqual(first.session)
			t.expect(h.runs:start(ROOM)).toBeTruthy()
			local again = h.runs:peek(A)
			assert(again, "A is in the new run")
			t.expect(again.runId).toBe(2)
			t.expect(h.runs:start({ id = 5, players = { "C", "D" }, present = { true, false } })).toBe(nil)
		end)

		t.it("accepts a move, numbers it, and tells both players", function()
			local h = harness()
			local state = started(h)
			local slot, x, y = legalMove(h, A)
			local outcome = h.runs:place(A, state.runId, 7, slot, x, y)
			assert(outcome.kind == "accepted", "the move is valid")
			local move = outcome.move
			t.expect(move.runId).toBe(state.runId)
			t.expect(move.seq).toBe(1)
			t.expect(move.seat).toBe(1)
			t.expect(move.moveId).toBe(7)
			t.expect(move.slot).toBe(slot)
			t.expect(move.x).toBe(x)
			t.expect(move.y).toBe(y)
			t.expect(move.score > 0).toBe(true)
			t.expect(move.set).toBe(nil)
			t.expect(move.isOver).toBe(false)
			t.expect(outcome.players).toEqual({ A, B })
			t.expect(outcome.endsRun).toBe(false)

			local second = play(h, B, state.runId)
			assert(second.kind == "accepted", "B's move is valid")
			t.expect(second.move.seq).toBe(2)
			t.expect(second.move.seat).toBe(2)
			t.expect(second.move.score > move.score).toBe(true)
		end)

		t.it("deals the next set with the move that uses the last piece", function()
			local h = harness()
			local state = started(h)
			for turn = 1, 4 do
				local outcome = play(h, if turn % 2 == 1 then A else B, state.runId)
				assert(outcome.kind == "accepted", "valid")
				if turn < 4 then
					t.expect(outcome.move.set).toBe(nil)
				else
					assert(outcome.move.set, "the fourth move brings a new set")
					t.expect(#outcome.move.set).toBe(4)
				end
			end
			local after = h.runs:state(A)
			assert(after, "the state is available")
			t.expect(after.seq).toBe(4)
		end)

		t.it("rejects a move that clashes with the partner's, and a piece that is already placed", function()
			local h = harness()
			local state = started(h)
			local slot, x, y = legalMove(h, A)
			t.expect(h.runs:place(A, state.runId, 1, slot, x, y).kind).toBe("accepted")

			-- B aims a piece at the cells A just filled.
			local clash = h.runs:place(B, state.runId, 9, 3, x, y)
			t.expect(clash).toEqual({ kind = "rejected", runId = state.runId, moveId = 9 })
			-- A places the same piece again.
			t.expect(h.runs:place(A, state.runId, 2, slot, x, y).kind).toBe("rejected")
			local summary = h.runs:summary(A)
			assert(summary, "A has a run")
			t.expect(summary.moves).toBe(1)

			-- The rejected move used no number: the next accepted one is seq 2.
			local next = play(h, B, state.runId)
			assert(next.kind == "accepted", "valid")
			t.expect(next.move.seq).toBe(2)
		end)

		t.it("lets a player place only their own pieces", function()
			local h = harness()
			local state = started(h)
			t.expect(h.runs:place(A, state.runId, 1, 3, 0, 0).kind).toBe("rejected")
			t.expect(h.runs:place(B, state.runId, 1, 1, 0, 0).kind).toBe("rejected")
			t.expect(h.runs:summary(A).moves).toBe(0)
		end)

		t.it("ignores requests that are not even well formed, and changes nothing", function()
			local h = harness()
			local state = started(h)
			local runId = state.runId
			local slot, x, y = legalMove(h, A)
			local before = h.runs:peek(A).coop:snapshot()
			local junk: { any } = { 0 / 0, math.huge, "1", {}, true, 1.5, -100 } -- (-1 is a whole number: just off the board)
			for _, bad in junk do
				h.advance(1) -- clear of the rate limit
				t.expect(h.runs:place(A, runId, bad, slot, x, y).kind).toBe("ignored")
				h.advance(1)
				t.expect(h.runs:place(A, bad, 1, slot, x, y).kind).toBe("ignored")
				h.advance(1)
				t.expect(h.runs:place(A, runId, 1, bad, x, y).kind).toBe("ignored")
				h.advance(1)
				t.expect(h.runs:place(A, runId, 1, slot, bad, y).kind).toBe("ignored")
				h.advance(1)
				t.expect(h.runs:place(A, runId, 1, slot, x, bad).kind).toBe("ignored")
			end
			h.advance(1)
			t.expect(h.runs:place(A, runId, nil, nil, nil, nil).kind).toBe("ignored")
			h.advance(1)
			t.expect(h.runs:place(A, runId, 1, 0, x, y).kind).toBe("ignored") -- not a slot
			h.advance(1)
			t.expect(h.runs:place(A, runId, 1, 5, x, y).kind).toBe("ignored")
			h.advance(1)
			t.expect(h.runs:place("stranger", runId, 1, slot, x, y)).toEqual({ kind = "ignored", reason = "no run" })
			h.advance(1)
			t.expect(h.runs:place(A, runId + 1, 1, slot, x, y).kind).toBe("ignored") -- a run that isn't theirs
			t.expect(h.runs:peek(A).coop:snapshot()).toEqual(before)
		end)

		t.it("limits placements to eight a second per player", function()
			local h = harness()
			local state = started(h)
			for _ = 1, 8 do
				t.expect(h.runs:place(A, state.runId, 1, 3, 0, 0).kind).toBe("rejected")
			end
			t.expect(h.runs:place(A, state.runId, 1, 3, 0, 0)).toEqual({ kind = "ignored", reason = "rate limited" })
			t.expect(h.runs:place(B, state.runId, 1, 1, 0, 0).kind).toBe("rejected") -- B has a bucket of their own
			h.advance(1)
			t.expect(h.runs:place(A, state.runId, 1, 3, 0, 0).kind).toBe("rejected")
		end)

		t.it(
			"hands every piece to the player who stays when the other leaves, and freezes the counted score",
			function()
				local h = harness()
				local state = started(h)
				play(h, A, state.runId)
				play(h, B, state.runId)
				local atLeave = h.runs:summary(A).score
				h.advance(1)

				local outcome = h.runs:leave(A)
				assert(outcome, "A was in the run")
				t.expect(outcome.seat).toBe(1)
				t.expect(outcome.stayer).toBe(B)
				assert(outcome.state, "the stayer gets a state")
				t.expect(outcome.state.seat).toBe(2)
				t.expect(outcome.state.session.present).toEqual({ false, true })
				t.expect(outcome.state.session.countedScore).toBe(atLeave)
				t.expect(outcome.state.takeOverIn).toBe(nil)

				t.expect(h.runs:place(A, state.runId, 99, 1, 0, 0)).toEqual({ kind = "ignored", reason = "no run" })
				t.expect(h.runs:state(A)).toBe(nil)
				-- B may now place the pieces that were A's.
				local view = h.runs:peek(B)
				assert(view, "B is still in the run")
				local placed = false
				for slot = 1, 2 do
					if view.coop.session.tray[slot] then
						local piece = view.coop.session.tray[slot]
						for y = 0, SIZE - piece.height do
							for x = 0, SIZE - piece.width do
								if not placed and view.coop:canPlace(2, slot, x, y) then
									t.expect(h.runs:place(B, state.runId, 5, slot, x, y).kind).toBe("accepted")
									placed = true
								end
							end
						end
					end
				end
				t.expect(placed).toBe(true)
				local summary = h.runs:summary(B)
				assert(summary, "B has a run")
				t.expect(summary.score > atLeave).toBe(true)
				t.expect(summary.countedScore).toBe(atLeave)

				t.expect(h.runs:leave(A)).toBe(nil)
				local last = h.runs:leave(B)
				assert(last, "B was still in the run")
				t.expect(last.stayer).toBe(nil)
			end
		)

		t.it("lets a stuck player take over from a partner who stays idle for 45 seconds", function()
			local h = harness()
			local state = started(h)
			play(h, A, state.runId)
			h.advance(10)
			local lastOwn = play(h, A, state.runId) -- A has placed both pieces and waits for B
			assert(lastOwn.kind == "accepted", "valid")
			t.expect(lastOwn.takeOverIn[1]).toBe(AFK)
			t.expect(lastOwn.takeOverIn[2]).toBe(nil) -- B has moves, so they are not the one waiting

			h.advance(30)
			t.expect(h.runs:takeOver(A, state.runId).kind).toBe("ignored") -- 15 seconds early
			local waiting = h.runs:state(A)
			assert(waiting, "state")
			t.expect(waiting.takeOverIn).toBe(15)

			-- B moving starts the wait over.
			h.advance(1)
			local between = play(h, B, state.runId)
			assert(between.kind == "accepted", "valid")
			t.expect(between.takeOverIn[1]).toBe(AFK)
			h.advance(AFK - 1)
			t.expect(h.runs:takeOver(A, state.runId).kind).toBe("ignored")
			h.advance(1)
			t.expect(h.runs:takeOver(B, state.runId).kind).toBe("ignored") -- B still has a piece to place

			h.advance(AFK)
			local outcome = h.runs:takeOver(A, state.runId)
			assert(outcome.kind == "tookOver", "A may take over now")
			t.expect(outcome.evicted).toBe(B)
			t.expect(outcome.state.seat).toBe(1)
			t.expect(outcome.state.session.present).toEqual({ true, false })
			t.expect(h.runs:place(B, state.runId, 50, 3, 0, 0)).toEqual({ kind = "ignored", reason = "no run" })
			t.expect(h.runs:leave(B)).toBe(nil) -- already out; the room's leave event changes nothing
			local view = h.runs:peek(A)
			assert(view, "A carries on")
			t.expect(view.coop:hasMove(1)).toBe(true) -- B's piece is theirs now
		end)

		t.it("does not allow taking over from the wrong run, or when the run is not stuck", function()
			local h = harness()
			local state = started(h)
			h.advance(1000)
			t.expect(h.runs:takeOver(A, state.runId)).toEqual({
				kind = "ignored",
				reason = "not waiting for a partner who can move",
			})
			h.advance(5)
			t.expect(h.runs:takeOver(A, state.runId + 1).kind).toBe("ignored")
			local garbage: { any } = { 0 / 0, "1", {}, nil }
			for _, bad in garbage do
				h.advance(5)
				t.expect(h.runs:takeOver(A, bad).kind).toBe("ignored")
			end
			t.expect(h.runs:takeOver("stranger", state.runId).kind).toBe("ignored")
		end)

		t.it("restarts the room's run once both have asked to play again after game over", function()
			local h = harness(SQUARES)
			local state = started(h)
			t.expect(h.runs:rematch(A)).toEqual({ kind = "ignored", reason = "the run is not over" })

			local over = false
			local guard = 0
			while not over and guard < 40 do
				guard += 1
				for _, player in { A, B } do
					local view = h.runs:peek(player)
					assert(view, "in the run")
					if not view.coop.session.isOver and view.coop:hasMove(view.seat) then
						local outcome = play(h, player, state.runId)
						assert(outcome.kind == "accepted", "valid")
						over = over or outcome.move.isOver
					end
				end
				h.advance(1)
			end
			t.expect(over).toBe(true)
			t.expect(h.runs:summary(A).isOver).toBe(true)

			h.advance(1)
			local first = h.runs:rematch(A)
			assert(first.kind == "waiting", "B hasn't asked yet")
			t.expect(first.votes).toEqual({ true, false })
			h.advance(1)
			t.expect(h.runs:rematch(A).kind).toBe("waiting") -- asking twice is not asking for two
			h.advance(1)
			local second = h.runs:rematch(B)
			assert(second.kind == "restarted", "both asked")
			t.expect(second.players).toEqual({ A, B })
			t.expect(second.states[1].runId).toBe(state.runId + 1)
			t.expect(second.states[1].seq).toBe(0)
			t.expect(second.states[2].seat).toBe(2)
			-- The old run is dead: a move that was still on its way is ignored.
			h.advance(1)
			t.expect(h.runs:place(A, state.runId, 1, 1, 0, 0).kind).toBe("ignored")
		end)

		t.it("does not restart when the partner has left", function()
			local h = harness(SQUARES)
			local state = started(h)
			local guard = 0
			while not h.runs:summary(A).isOver and guard < 60 do
				guard += 1
				for _, player in { A, B } do
					local view = h.runs:peek(player)
					if view and not view.coop.session.isOver and view.coop:hasMove(view.seat) then
						play(h, player, state.runId)
					end
				end
			end
			t.expect(h.runs:summary(A).isOver).toBe(true)
			h.runs:leave(B)
			h.advance(1)
			t.expect(h.runs:rematch(A)).toEqual({ kind = "ignored", reason = "the partner has left" })
		end)

		t.it("answers a request for the state, but not more than twice a second", function()
			local h = harness()
			local state = started(h)
			play(h, A, state.runId)
			local first = h.runs:state(B)
			assert(first, "the state")
			t.expect(first.seq).toBe(1)
			t.expect(first.seat).toBe(2)
			t.expect(first.session.game.moveCount).toBe(1)
			t.expect(h.runs:state(B)).toBeTruthy()
			t.expect(h.runs:state(B)).toBe(nil)
			t.expect(h.runs:state("stranger")).toBe(nil)
			h.advance(1)
			t.expect(h.runs:state(B)).toBeTruthy()
		end)

		t.it("passes on where a player is aiming a piece, and when they stop", function()
			local h = harness()
			started(h)
			local slot, x, y = legalMove(h, A)
			t.expect(h.runs:hover(A, slot, x, y)).toEqual({ to = B, slot = slot, x = x, y = y })
			t.expect(h.runs:hover(A)).toEqual({ to = B })
			local otherSlot, otherX, otherY = legalMove(h, B)
			t.expect(h.runs:hover(B, otherSlot, otherX, otherY)).toEqual({
				to = A,
				slot = otherSlot,
				x = otherX,
				y = otherY,
			})
		end)

		t.it("drops an aim that makes no sense, and one with nobody to see it", function()
			local h = harness()
			local state = started(h)
			local piece = h.runs:peek(A).coop.session.tray[1]
			t.expect(h.runs:hover(A, 3, 0, 0)).toBe(nil) -- the partner's piece
			t.expect(h.runs:hover(B, 1, 0, 0)).toBe(nil)
			t.expect(h.runs:hover(A, 1, 9 - piece.width, 0)).toBe(nil) -- over the right edge
			t.expect(h.runs:hover(A, 1, 0, 9 - piece.height)).toBe(nil) -- over the bottom edge
			t.expect(h.runs:hover(A, 1, -1, 0)).toBe(nil)
			t.expect(h.runs:hover("stranger", 1, 0, 0)).toBe(nil)
			local junk: { any } = { 0 / 0, math.huge, "1", {}, true, 1.5 }
			for _, bad in junk do
				h.advance(1)
				t.expect(h.runs:hover(A, bad, 0, 0)).toBe(nil)
				t.expect(h.runs:hover(A, 1, bad, 0)).toBe(nil)
				t.expect(h.runs:hover(A, 1, 0, bad)).toBe(nil)
			end

			-- A piece that is already placed can't be aimed.
			h.advance(1)
			local slot, x, y = legalMove(h, A)
			play(h, A, state.runId)
			t.expect(h.runs:hover(A, slot, x, y)).toBe(nil)

			-- And with the partner gone there is nobody to tell.
			h.advance(1)
			local otherSlot, otherX, otherY = legalMove(h, B)
			t.expect(h.runs:hover(B, otherSlot, otherX, otherY)).toBeTruthy()
			h.runs:leave(A)
			h.advance(1)
			t.expect(h.runs:hover(B, otherSlot, otherX, otherY)).toBe(nil)
		end)

		t.it("limits aims to twelve a second per player", function()
			local h = harness()
			started(h)
			for _ = 1, 12 do
				t.expect(h.runs:hover(A)).toEqual({ to = B })
			end
			t.expect(h.runs:hover(A)).toBe(nil)
			h.advance(1)
			t.expect(h.runs:hover(A)).toEqual({ to = B })
		end)

		t.it("forgets everything once the room is closed and the players are gone", function()
			local h = harness()
			local state = started(h)
			play(h, A, state.runId)
			h.runs:state(B)
			t.expect(h.runs:footprint() > 0).toBe(true)
			h.runs:leave(A)
			h.runs:remove(A)
			h.runs:close(ROOM.id)
			h.runs:remove(B)
			t.expect(h.runs:footprint()).toBe(0)
			t.expect(h.runs:summary(B)).toBe(nil)
			h.runs:close(99) -- a room that never had a run
			t.expect(h.runs:footprint()).toBe(0)
		end)
	end)
end
