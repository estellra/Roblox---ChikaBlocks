--!strict
local CoopSession = require("../src/shared/CoopSession")
local CoopSync = require("../src/client/Util/CoopSync")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local TestKit = require("./TestKit")

local DEPS: CoopSync.Deps = { CoopSession = CoopSession, Pieces = Pieces }

-- The sets the fake server deals: four dots each, so every move is worth one point and clears nothing.
local DOTS = { "Dot", "Dot", "Dot", "Dot" }
local SECOND_SET = { "O2", "O2", "O2", "O2" }

-- A server-side run and a client for `seat` that starts from its state.
local function pair(seat: number): (CoopSession.CoopSession, CoopSync.CoopSync)
	local server = CoopSession.new((Helpers.queueSource({ DOTS, SECOND_SET })))
	local sync = CoopSync.new(DEPS, { runId = 1, seq = 0, seat = seat, session = server:snapshot() })
	return server, sync
end

-- The server accepts a move and announces it, as CoopRuns would.
local function serverMove(
	server: CoopSession.CoopSession,
	seat: number,
	moveId: number,
	slot: number,
	x: number,
	y: number
): CoopSync.Move
	local result = server:place(seat, slot, x, y)
	assert(result, "the server accepts the move")
	local set: { string }? = nil
	if result.refilled then
		set = {}
		for i, piece in server.session.tray do
			(set :: { string })[i] = piece.id
		end
	end
	return {
		runId = 1,
		seq = server.session.moveCount,
		seat = seat,
		moveId = moveId,
		slot = slot,
		x = x,
		y = y,
		score = server.session.score,
		set = set,
		isOver = server.session.isOver,
		takeOverAt = nil,
	}
end

return function(t: TestKit.TestKit)
	t.describe("CoopSync", function()
		t.it("shows the player's own move at once and keeps it pending", function()
			local _, sync = pair(1)
			local result, moveId = sync:place(1, 0, 0)
			assert(result, "the move is valid")
			t.expect(moveId).toBe(1)
			t.expect(sync:pendingCount()).toBe(1)
			t.expect(Helpers.ids(sync:session().session.tray)).toEqual({ false, "Dot", "Dot", "Dot" })
			t.expect(sync.confirmed.session.score).toBe(0) -- only the server confirms
			t.expect(sync:session().session.score).toBe(1)

			local _, second = sync:place(2, 1, 0)
			t.expect(second).toBe(2)
			t.expect(sync:pendingCount()).toBe(2)
		end)

		t.it("refuses moves that are not valid and leaves everything as it was", function()
			local _, sync = pair(1)
			sync:place(1, 0, 0)
			local before = sync:session():snapshot()
			t.expect(sync:place(1, 1, 0)).toBe(nil) -- the piece is placed
			t.expect(sync:place(3, 1, 0)).toBe(nil) -- the partner's piece
			t.expect(sync:place(2, 0, 0)).toBe(nil) -- the cell is taken
			t.expect(sync:place(2, 8, 0)).toBe(nil) -- off the board
			t.expect(sync:place("2", 1, 0)).toBe(nil)
			t.expect(sync:session():snapshot()).toEqual(before)
			t.expect(sync:pendingCount()).toBe(1)
		end)

		t.it("lets the player drag only their own pieces, and all of them once the partner has gone", function()
			local _, sync = pair(2)
			t.expect(sync:canDrag(1)).toBe(false)
			t.expect(sync:canDrag(3)).toBe(true)
			t.expect(sync:canDrag(4)).toBe(true)
			sync:place(3, 0, 0)
			t.expect(sync:canDrag(3)).toBe(false) -- nothing left in that slot

			local server = CoopSession.new((Helpers.queueSource({ DOTS })))
			server:release(1)
			sync:reset({ runId = 1, seq = 0, seat = 2, session = server:snapshot() })
			t.expect(sync:canDrag(1)).toBe(true)
			t.expect(sync:canDrag(3)).toBe(true)
			t.expect(sync:pendingCount()).toBe(0)
		end)

		t.it("confirms the player's own move without changing what is shown", function()
			local server, sync = pair(1)
			sync:place(1, 0, 0)
			local shownBefore = sync:session():snapshot()
			local applied = sync:applyMove(serverMove(server, 1, 1, 1, 0, 0))
			assert(applied.kind == "applied", "the move applies")
			t.expect(applied.mine).toBe(true)
			t.expect(applied.dropped).toEqual({})
			t.expect(sync:pendingCount()).toBe(0)
			t.expect(sync.confirmed.session.score).toBe(1)
			t.expect(sync:session():snapshot()).toEqual(shownBefore)
		end)

		t.it("puts the partner's move under the pending ones", function()
			local server, sync = pair(1)
			sync:place(1, 0, 0)
			local applied = sync:applyMove(serverMove(server, 2, 1, 3, 5, 5))
			assert(applied.kind == "applied", "the move applies")
			t.expect(applied.mine).toBe(false)
			assert(applied.result, "the partner's move comes with its effect")
			t.expect(applied.result.slot).toBe(3)
			t.expect(applied.dropped).toEqual({})
			t.expect(sync:pendingCount()).toBe(1)
			t.expect(sync:session().session.score).toBe(2) -- the partner's point and our pending one
			t.expect(sync.confirmed.session.score).toBe(1)
		end)

		t.it(
			"drops a pending move that the partner's move made impossible, and ignores the reject that follows",
			function()
				local server, sync = pair(1)
				sync:place(1, 0, 0)
				-- The server saw the partner's move first: it takes the cell, and our move will be rejected.
				local applied = sync:applyMove(serverMove(server, 2, 1, 3, 0, 0))
				assert(applied.kind == "applied", "the move applies")
				t.expect(#applied.dropped).toBe(1)
				t.expect(applied.dropped[1].moveId).toBe(1)
				t.expect(sync:pendingCount()).toBe(0)
				t.expect(Helpers.ids(sync:session().session.tray)).toEqual({ "Dot", "Dot", false, "Dot" }) -- our piece is back
				t.expect(sync:reject(1, 1)).toEqual({}) -- nothing left to do
			end
		)

		t.it("takes a rejected move out of pending and shows the piece in its tray again", function()
			local _, sync = pair(1)
			sync:place(1, 0, 0)
			sync:place(2, 1, 0)
			t.expect(sync:reject(1, 1)).toEqual({}) -- the second move does not depend on the first
			t.expect(sync:pendingCount()).toBe(1)
			t.expect(Helpers.ids(sync:session().session.tray)).toEqual({ "Dot", false, "Dot", "Dot" })
			t.expect(sync:reject(2, 2)).toEqual({}) -- another run: not ours
			t.expect(sync:pendingCount()).toBe(1)
		end)

		t.it("asks for the state when a move is missing, doesn't fit, or has another score", function()
			local server, sync = pair(1)
			local first = serverMove(server, 2, 1, 3, 0, 0)
			local second = serverMove(server, 2, 2, 4, 1, 0)
			-- The first move never arrived.
			t.expect(sync:applyMove(second)).toEqual({ kind = "resync", reason = "expected move 1, got 2" })

			local _, other = pair(1)
			local wrongScore = table.clone(first)
			wrongScore.score = 99
			t.expect(other:applyMove(wrongScore).kind).toBe("resync")

			local _, third = pair(1)
			local nowhere = table.clone(first)
			nowhere.x = 20
			t.expect(third:applyMove(nowhere).kind).toBe("resync")

			local _, fourth = pair(1)
			local wrongOver = table.clone(first)
			wrongOver.isOver = true
			t.expect(fourth:applyMove(wrongOver).kind).toBe("resync")
		end)

		t.it("ignores a move it already has and a move of another run", function()
			local server, sync = pair(1)
			local move = serverMove(server, 2, 1, 3, 0, 0)
			t.expect(sync:applyMove(move).kind).toBe("applied")
			t.expect(sync:applyMove(move)).toEqual({ kind = "ignored" })
			local older = table.clone(move)
			older.runId = 2
			older.seq = 2
			t.expect(sync:applyMove(older)).toEqual({ kind = "ignored" })
			t.expect(sync.seq).toBe(1)
		end)

		t.it("receives the next set with the move that uses the last piece, and not otherwise", function()
			local server, sync = pair(1)
			local moves = {
				serverMove(server, 1, 1, 1, 0, 0),
				serverMove(server, 2, 1, 3, 1, 0),
				serverMove(server, 1, 2, 2, 2, 0),
				serverMove(server, 2, 2, 4, 3, 0),
			}
			for index, move in moves do
				t.expect(sync:applyMove(move).kind).toBe("applied")
				t.expect(sync.confirmed.session.awaitingSet).toBe(false)
				if index < 4 then
					t.expect(move.set).toBe(nil)
				end
			end
			assert(moves[4].set, "the last move of a set brings the next")
			t.expect(Helpers.ids(sync:session().session.tray)).toEqual({ "O2", "O2", "O2", "O2" })

			-- A move that empties the tray without a set is a gap in what we were told.
			local _, bare = pair(1)
			for index = 1, 3 do
				bare:applyMove(moves[index])
			end
			local noSet = table.clone(moves[4])
			noSet.set = nil
			t.expect(bare:applyMove(noSet).kind).toBe("resync")
			-- And a set that comes with a move that doesn't empty it is just as wrong.
			local _, early = pair(1)
			local withSet = table.clone(moves[1])
			withSet.set = SECOND_SET
			t.expect(early:applyMove(withSet).kind).toBe("resync")
		end)

		t.it("replaces everything with the server's state", function()
			local server, sync = pair(1)
			sync:place(1, 0, 0)
			sync:applyMove(serverMove(server, 2, 1, 3, 4, 4))
			server:release(2)
			sync:reset({ runId = 3, seq = 7, seat = 1, session = server:snapshot(), takeOverAt = 12 })
			t.expect(sync.runId).toBe(3)
			t.expect(sync.seq).toBe(7)
			t.expect(sync:pendingCount()).toBe(0)
			t.expect(sync.takeOverAt).toBe(12)
			t.expect(sync:session():snapshot()).toEqual(server:snapshot())
		end)
	end)
end
