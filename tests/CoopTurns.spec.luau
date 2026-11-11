--!strict
-- Turning pieces and reviving a run in Co-op (M23): the rules (GameSession.rotateWith, CoopSession), the server's
-- side (CoopRuns), the client's copy (CoopSync) and the two small pieces that decide money and analytics
-- (Purchases.reviveApplies, Telemetry).
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local CoopRuns = require("../src/server/CoopRuns")
local CoopSession = require("../src/shared/CoopSession")
local CoopSync = require("../src/client/Util/CoopSync")
local GameSession = require("../src/shared/GameSession")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local Purchases = require("../src/server/Purchases")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")
local Telemetry = require("../src/server/Telemetry")

local SIZE = Config.GRID_SIZE
local AFK = 45
local A, B = "A", "B"
local ROOM = { id = 1, players = { A, B }, present = { true, true } }
local DEPS: CoopSync.Deps = { CoopSession = CoopSession, Pieces = Pieces }

local BARS = { "I3_H", "I3_H", "I3_H", "I3_H" }
local DOTS = { "Dot", "Dot", "Dot", "Dot" }

-- Column 7 is open for four cells and nothing else is: a horizontal bar fits nowhere, a vertical one fits in the gap.
local ONLY_A_VERTICAL_GAP = {
	"#######.",
	"#######.",
	"#######.",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
}

-- No gap of two in a row or a column, so nothing but a single cell fits.
local CHECKERBOARD = {
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
}

local function newRun(sets: { { string } }, board: Board.Board?): CoopSession.CoopSession
	return CoopSession.new((Helpers.queueSource(sets)), board)
end

-- A CoopSession module that deals the same four pieces to every set (and revive), on an empty board or on `rows`.
local function scripted(set: { string }, rows: { string }?)
	local sets = {}
	for i = 1, 40 do
		sets[i] = set
	end
	return {
		new = function(source: any)
			return CoopSession.new(source, if rows then Helpers.boardFromRows(rows) else nil)
		end,
		seatOf = CoopSession.seatOf,
		newSource = function(_rng: any)
			return (Helpers.queueSource(sets))
		end,
	}
end

-- Four bars on an empty board: pieces that can be turned, and a run that goes on.
local function barsOnly()
	return scripted(BARS)
end

-- Four 3x3 squares: they fill the top left corner in four moves and nothing fits after that, so the run ends at once.
local function squaresOnly()
	return scripted({ "O3", "O3", "O3", "O3" })
end

-- Bars on a board where nothing but a single cell fits: the run is over before the first move.
local function alreadyOver()
	return scripted(BARS, CHECKERBOARD)
end

type Harness = { runs: CoopRuns.CoopRuns, advance: (seconds: number) -> () }

local function harness(coopSession: any?): Harness
	local now = 0
	local seed = 0
	local runs = CoopRuns.new({
		CoopSession = coopSession or barsOnly(),
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

local function started(h: Harness): CoopRuns.State
	local states = h.runs:start(ROOM)
	assert(states, "the room can start a run")
	return states[1]
end

local nextMoveId = 0

-- A legal move for `player` on the server's current board.
local function legalMove(h: Harness, player: string): (number?, number?, number?)
	local view = h.runs:peek(player)
	assert(view, `{player} is in a run`)
	for slot, piece in view.coop.session.tray do
		if piece and view.coop:mayPlace(view.seat, slot) then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if view.coop:canPlace(view.seat, slot, x, y) then
						return slot, x, y
					end
				end
			end
		end
	end
	return nil
end

local function play(h: Harness, player: string, runId: number): CoopRuns.PlaceOutcome
	local slot, x, y = legalMove(h, player)
	assert(slot and x and y, `{player} has no valid move`)
	nextMoveId += 1
	local outcome = h.runs:place(player, runId, nextMoveId, slot, x, y)
	assert(outcome.kind == "accepted", `{player}'s legal move was {outcome.kind}`)
	return outcome
end

-- Both players place until the run is over. Returns how many of those moves said they ended the run.
local function playUntilOver(h: Harness, runId: number): number
	local ends = 0
	for _ = 1, 200 do
		local summary = h.runs:summary(A) or h.runs:summary(B)
		if summary == nil or summary.isOver then
			return ends
		end
		h.advance(1) -- a player places at most eight pieces a second
		for _, player in { A, B } do
			if h.runs:peek(player) and legalMove(h, player) then
				local outcome = play(h, player, runId)
				if outcome.kind == "accepted" and outcome.endsRun then
					ends += 1
				end
			end
		end
	end
	error("the run never ended")
end

local function turn(h: Harness, player: string, runId: number, slot: number, paid: number): CoopRuns.RotateOutcome
	nextMoveId += 1
	return h.runs:rotate(player, runId, nextMoveId, slot, paid)
end

-- The server accepts a turn and announces it, as CoopRuns would.
local function serverTurn(
	server: CoopSession.CoopSession,
	seq: number,
	seat: number,
	moveId: number,
	slot: number,
	paid: number
): CoopSync.Turn
	local result = server:rotate(seat, slot, paid)
	assert(result, "the server accepts the turn")
	return { runId = 1, seq = seq, seat = seat, moveId = moveId, slot = slot, charged = result.charged }
end

local function pair(seat: number): (CoopSession.CoopSession, CoopSync.CoopSync)
	local server = newRun({ BARS, BARS })
	local sync = CoopSync.new(DEPS, { runId = 1, seq = 0, seat = seat, session = server:snapshot() })
	return server, sync
end

return function(t: TestKit.TestKit)
	t.describe("GameSession.rotateWith", function()
		t.it("pays from the wallet it is given and leaves the session's own counter alone", function()
			local session = GameSession.new((Helpers.queueSource({ BARS })), nil, 4)
			local result = session:rotateWith(1, 1, 0)
			assert(result, "the piece turns")
			t.expect(result.charged).toBe("free")
			t.expect(result.piece.id).toBe("I3_V")
			t.expect(session.unlocked[1]).toBe(true)
			t.expect(session.freeRotations).toBe(Config.FREE_ROTATIONS_PER_RUN)

			local again = session:rotateWith(1, 0, 0) -- turned already, so turning it again is free
			assert(again, "it turns again")
			t.expect(again.charged).toBe(nil)
			t.expect(again.piece.id).toBe("I3_H")
		end)

		t.it("takes a free rotation before a bought one, and a bought one when none is free", function()
			local session = GameSession.new((Helpers.queueSource({ BARS })), nil, 4)
			local first = session:rotateWith(1, 1, 5)
			assert(first, "turns")
			t.expect(first.charged).toBe("free")
			local second = session:rotateWith(2, 0, 5)
			assert(second, "turns")
			t.expect(second.charged).toBe("paid")
			t.expect(session:rotateWith(3, 0, 0)).toBe(nil)
			local before = session:snapshot()
			local junk: { any } = { -1, 0 / 0, "1", true, {}, nil }
			for _, wallet in junk do
				t.expect(session:rotateWith(3, wallet, wallet)).toBe(nil)
			end
			t.expect(session:snapshot()).toEqual(before)
		end)

		t.it("still lets the solo rotate spend the run's own free rotation", function()
			local session = GameSession.new((Helpers.queueSource({ { "I3_H", "I3_H", "I3_H" } })))
			t.expect(session:rotate(1, 0).charged).toBe("free")
			t.expect(session.freeRotations).toBe(Config.FREE_ROTATIONS_PER_RUN - 1)
			t.expect(session:rotate(2, 0)).toBe(nil)
		end)
	end)

	t.describe("CoopSession turns and revives", function()
		t.it("gives each player their own free rotation and keeps the session's counter out of it", function()
			local run = newRun({ BARS })
			t.expect(run:freeRotationsOf(1)).toBe(Config.FREE_ROTATIONS_PER_RUN)
			t.expect(run:freeRotationsOf(2)).toBe(Config.FREE_ROTATIONS_PER_RUN)
			t.expect(run:freeRotationsOf(3)).toBe(0)
			t.expect(run:freeRotationsOf("1")).toBe(0)
			t.expect(run.session.freeRotations).toBe(0)
			t.expect(run:snapshot().freeRotations)
				.toEqual({ Config.FREE_ROTATIONS_PER_RUN, Config.FREE_ROTATIONS_PER_RUN })
		end)

		t.it("takes a player's turn from their own free rotation and leaves the partner's", function()
			local run = newRun({ BARS })
			local first = run:rotate(1, 1, 0)
			assert(first, "turns")
			t.expect(first.charged).toBe("free")
			t.expect(Helpers.ids(run.session.tray)).toEqual({ "I3_V", "I3_H", "I3_H", "I3_H" })
			t.expect(run:freeRotationsOf(1)).toBe(Config.FREE_ROTATIONS_PER_RUN - 1)
			t.expect(run:freeRotationsOf(2)).toBe(Config.FREE_ROTATIONS_PER_RUN)

			local before = run:snapshot()
			t.expect(run:rotate(1, 2, 0)).toBe(nil) -- nothing free left and nothing bought
			t.expect(run:snapshot()).toEqual(before)
			local theirs = run:rotate(2, 3, 0)
			assert(theirs, "the partner still has theirs")
			t.expect(theirs.charged).toBe("free")
		end)

		t.it("takes a bought rotation once the free one is gone, and never charges a piece twice", function()
			local run = newRun({ BARS })
			run:rotate(1, 1, 0)
			local bought = run:rotate(1, 2, 2)
			assert(bought, "turns")
			t.expect(bought.charged).toBe("paid")
			t.expect(run:freeRotationsOf(1)).toBe(0) -- a bought rotation does not touch the free ones
			local again = run:rotate(1, 2, 0)
			assert(again, "an unlocked piece turns freely")
			t.expect(again.charged).toBe(nil)
			t.expect(Helpers.ids(run.session.tray)).toEqual({ "I3_V", "I3_H", "I3_H", "I3_H" })
		end)

		t.it("turns only a player's own pieces, or the leaver's once the partner has gone", function()
			local run = newRun({ BARS })
			local before = run:snapshot()
			t.expect(run:rotate(1, 3, 9)).toBe(nil)
			t.expect(run:rotate(2, 1, 9)).toBe(nil)
			t.expect(run:rotate(3, 1, 9)).toBe(nil)
			t.expect(run:rotate(1, 5, 9)).toBe(nil)
			t.expect(run:snapshot()).toEqual(before)

			run:release(2)
			local theirs = run:rotate(1, 3, 0)
			assert(theirs, "the player who stays turns the leaver's piece")
			t.expect(theirs.charged).toBe("free") -- paid from the stayer's own wallet
			t.expect(run:freeRotationsOf(1)).toBe(Config.FREE_ROTATIONS_PER_RUN - 1)
			t.expect(run:rotate(2, 4, 9)).toBe(nil) -- the one who left can no longer do anything
		end)

		t.it("leaves a piece that looks the same turned, and a finished run, alone", function()
			local run = newRun({ { "O2", "O2", "O2", "O2" } })
			local before = run:snapshot()
			t.expect(run:rotate(1, 1, 9)).toBe(nil)
			t.expect(run:snapshot()).toEqual(before)

			local over = newRun({ BARS }, Helpers.boardFromRows(CHECKERBOARD))
			t.expect(over.session.isOver).toBe(true)
			t.expect(over:rotate(1, 1, 9)).toBe(nil)
		end)

		t.it("counts a piece that fits only once turned as a move, and lets it be placed turned", function()
			local run = newRun({ { "Dot", "I3_H", "Dot", "Dot" } }, Helpers.boardFromRows(ONLY_A_VERTICAL_GAP))
			t.expect(run.session.isOver).toBe(false)
			t.expect(run.session:hasPlacement(2)).toBe(false) -- the bar does not fit as it lies
			t.expect(run:canPlace(1, 2, 7, 0)).toBe(false)
			local result = run:rotate(1, 2, 0)
			assert(result, "turns")
			t.expect(result.piece.id).toBe("I3_V")
			t.expect(run.session:hasPlacement(2)).toBe(true)
			t.expect(run:canPlace(1, 2, 7, 0)).toBe(true)
		end)

		t.it("revives a finished run: the middle is cleared, a new set dealt, the wallets stay as they are", function()
			local board = Helpers.boardFromRows(CHECKERBOARD)
			local run = newRun({ BARS, DOTS }, board)
			t.expect(run.session.isOver).toBe(true)
			run.freeRotations = { 0, 1 }
			t.expect(run:revive()).toBe(true)
			t.expect(run.session.isOver).toBe(false)
			t.expect(run.session.revivesUsed).toBe(1)
			t.expect(Helpers.ids(run.session.tray)).toEqual(DOTS)
			for y = 2, 5 do
				for x = 2, 5 do
					t.expect(run.session.board.cells[Board.index(x, y)]).toBe(0)
				end
			end
			t.expect(run.session.board.cells[Board.index(0, 0)]).toBe(1) -- outside the middle, untouched
			t.expect(run.freeRotations).toEqual({ 0, 1 })
		end)

		t.it("does not revive a run that is not over", function()
			local run = newRun({ BARS, DOTS })
			local before = run:snapshot()
			t.expect(run:revive()).toBe(false)
			t.expect(run:snapshot()).toEqual(before)
		end)

		t.it("keeps the free rotations through a snapshot, and refuses one without them", function()
			local run = newRun({ BARS, BARS })
			run:rotate(2, 3, 0)
			local snapshot = run:snapshot()
			t.expect(snapshot.freeRotations)
				.toEqual({ Config.FREE_ROTATIONS_PER_RUN, Config.FREE_ROTATIONS_PER_RUN - 1 })
			local copy = CoopSession.fromSnapshot(snapshot, (Helpers.queueSource({ BARS })))
			t.expect(copy:snapshot()).toEqual(snapshot)
			t.expect(copy:rotate(2, 4, 0)).toBe(nil) -- still has nothing free left

			local function noSet(): { Pieces.Piece }?
				return nil
			end
			local missing: any = table.clone(snapshot)
			missing.freeRotations = nil
			t.expect(function()
				CoopSession.fromSnapshot(missing, noSet)
			end).toThrow()
			local short: any = table.clone(snapshot)
			short.freeRotations = { 1 }
			t.expect(function()
				CoopSession.fromSnapshot(short, noSet)
			end).toThrow()
			local wrong: any = table.clone(snapshot)
			wrong.freeRotations = { 1, "1" }
			t.expect(function()
				CoopSession.fromSnapshot(wrong, noSet)
			end).toThrow()
		end)
	end)

	t.describe("CoopRuns turns and revives", function()
		t.it("turns a piece for its owner, numbers the turn like a move and tells both players", function()
			local h = harness()
			local state = started(h)
			local outcome = turn(h, A, state.runId, 1, 0)
			assert(outcome.kind == "accepted", "the turn is accepted")
			t.expect(outcome.turn).toEqual({
				runId = state.runId,
				seq = 1,
				seat = 1,
				moveId = nextMoveId,
				slot = 1,
				charged = "free",
			})
			t.expect(outcome.players).toEqual({ A, B })
			t.expect(outcome.present).toEqual({ true, true })

			local now = h.runs:state(A)
			assert(now, "state")
			t.expect(now.seq).toBe(1)
			t.expect(now.session.game.tray[1]).toBe("I3_V")
			t.expect(now.session.freeRotations)
				.toEqual({ Config.FREE_ROTATIONS_PER_RUN - 1, Config.FREE_ROTATIONS_PER_RUN })
			local summary = h.runs:summary(A)
			assert(summary, "summary")
			t.expect(summary.moves).toBe(0) -- a turn is not a move

			local moved = play(h, A, state.runId)
			assert(moved.kind == "accepted", "valid")
			t.expect(moved.move.seq).toBe(2)
		end)

		t.it("charges the free rotation, then a bought one, then refuses; each player has their own", function()
			local h = harness()
			local state = started(h)
			t.expect(turn(h, A, state.runId, 1, 0).kind).toBe("accepted")
			t.expect(turn(h, A, state.runId, 2, 0).kind).toBe("rejected") -- A's free rotation is spent
			local before = h.runs:state(A)
			assert(before, "state")
			t.expect(before.seq).toBe(1) -- a refused turn is not an event

			h.advance(1)
			local bought = turn(h, A, state.runId, 2, 1)
			assert(bought.kind == "accepted", "a bought rotation pays")
			t.expect(bought.turn.charged).toBe("paid")
			t.expect(bought.turn.seq).toBe(2)

			local theirs = turn(h, B, state.runId, 3, 0)
			assert(theirs.kind == "accepted", "B's free rotation is B's own")
			t.expect(theirs.turn.charged).toBe("free")
			t.expect(theirs.turn.seq).toBe(3)

			h.advance(1)
			local again = turn(h, A, state.runId, 1, 0) -- the piece is turned already
			assert(again.kind == "accepted", "turning it again costs nothing")
			t.expect(again.turn.charged).toBe(nil)
		end)

		t.it("rejects a turn of the partner's piece and changes nothing", function()
			local h = harness()
			local state = started(h)
			local outcome = turn(h, A, state.runId, 3, 9)
			t.expect(outcome).toEqual({ kind = "rejected", runId = state.runId, moveId = nextMoveId })
			local now = h.runs:state(A)
			assert(now, "state")
			t.expect(now.seq).toBe(0)
			t.expect(now.session.game.tray[3]).toBe("I3_H")
		end)

		t.it("ignores turns that are not even well formed", function()
			local h = harness()
			local state = started(h)
			t.expect(h.runs:rotate(A, state.runId + 1, 1, 1, 0).kind).toBe("ignored")
			t.expect(h.runs:rotate("stranger", state.runId, 1, 1, 0).kind).toBe("ignored")
			local junk: { any } = { 0 / 0, "1", {}, -5, 1.5, 1e12, math.huge }
			for _, bad in junk do
				t.expect(h.runs:rotate(A, bad, 1, 1, 0).kind).toBe("ignored")
				t.expect(h.runs:rotate(A, state.runId, bad, 1, 0).kind).toBe("ignored")
			end
			local notSlots: { any } = { 0, 5, "1", 1.5, 0 / 0, {}, true }
			for _, bad in notSlots do
				h.advance(1)
				t.expect(h.runs:rotate(A, state.runId, 1, bad, 0).kind).toBe("ignored")
			end
			h.advance(1)
			local now = h.runs:state(A)
			assert(now, "state")
			t.expect(now.seq).toBe(0)
		end)

		t.it("limits turns to twelve a second per player", function()
			local h = harness()
			local state = started(h)
			for _ = 1, 12 do
				t.expect(turn(h, A, state.runId, 1, 0).kind).toBe("accepted") -- the same piece turns as often as you like
			end
			t.expect(turn(h, A, state.runId, 1, 0)).toEqual({ kind = "ignored", reason = "rate limited" })
			t.expect(turn(h, B, state.runId, 3, 0).kind).toBe("accepted") -- B has their own allowance
			h.advance(1)
			t.expect(turn(h, A, state.runId, 1, 0).kind).toBe("accepted")
		end)

		t.it("does not let turning pieces hold back the partner's Take over", function()
			local h = harness()
			local state = started(h)
			play(h, A, state.runId)
			h.advance(10)
			local lastOwn = play(h, A, state.runId) -- A has placed both pieces and waits for B
			assert(lastOwn.kind == "accepted", "valid")
			t.expect(lastOwn.takeOverIn[1]).toBe(AFK)

			h.advance(30)
			t.expect(turn(h, B, state.runId, 3, 0).kind).toBe("accepted") -- B fiddles with a piece
			h.advance(AFK - 30)
			local outcome = h.runs:takeOver(A, state.runId)
			t.expect(outcome.kind).toBe("tookOver") -- 45 seconds after the last move, not after the last turn
		end)

		t.it("refuses to turn once the run is over, and says who is still present", function()
			local over = harness(alreadyOver())
			local first = started(over)
			t.expect(first.session.game.isOver).toBe(true)
			t.expect(turn(over, A, first.runId, 1, 9).kind).toBe("rejected") -- a bar that could turn, but the run is over

			local h = harness()
			local second = started(h)
			h.runs:leave(B)
			local outcome = turn(h, A, second.runId, 3, 0) -- A may turn B's piece now
			assert(outcome.kind == "accepted", "the stayer turns the leaver's piece")
			t.expect(outcome.present).toEqual({ true, false })
			t.expect(outcome.turn.slot).toBe(3)
		end)

		t.it("revives a finished run for both players, with a new set and the wallets as they were", function()
			local h = harness(squaresOnly())
			local state = started(h)
			local view = h.runs:peek(A)
			assert(view, "A is in the run")
			view.coop.freeRotations[1] = 0 -- as if A had used their free rotation
			t.expect(h.runs:revive(A, state.runId)).toBe(nil) -- not over yet
			playUntilOver(h, state.runId)
			t.expect(h.runs:revive(A, state.runId + 1)).toBe(nil)
			t.expect(h.runs:revive("stranger", state.runId)).toBe(nil)
			t.expect(h.runs:revive(A, "1")).toBe(nil)

			local outcome = h.runs:revive(B, state.runId) -- either player may
			assert(outcome, "the run is revived")
			t.expect(outcome.runId).toBe(state.runId)
			t.expect(outcome.players).toEqual({ A, B })
			t.expect(outcome.present).toEqual({ true, true })
			t.expect(outcome.revives).toBe(1)
			t.expect(#outcome.states).toBe(2)
			for seat, seatState in outcome.states do
				t.expect(seatState.seat).toBe(seat)
				t.expect(seatState.session.game.isOver).toBe(false)
				t.expect(seatState.session.game.revivesUsed).toBe(1)
				t.expect(seatState.session.freeRotations)
					.toEqual({ Config.FREE_ROTATIONS_PER_RUN - 1, Config.FREE_ROTATIONS_PER_RUN })
			end
			local summary = h.runs:summary(A)
			assert(summary, "summary")
			t.expect(summary.revives).toBe(1)
			t.expect(summary.isOver).toBe(false)
			t.expect(h.runs:revive(A, state.runId)).toBe(nil) -- over no longer, so nothing to revive
		end)

		t.it("lets a revived run go on and end again without counting the run twice", function()
			local h = harness(squaresOnly())
			local state = started(h)
			t.expect(playUntilOver(h, state.runId)).toBe(1)
			assert(h.runs:revive(A, state.runId), "revived")
			local second = playUntilOver(h, state.runId)
			t.expect(second).toBe(0) -- it ended again, but the run was counted already
			local summary = h.runs:summary(A)
			assert(summary, "summary")
			t.expect(summary.isOver).toBe(true)
			local again = h.runs:revive(A, state.runId)
			assert(again, "a revived run can be revived again")
			t.expect(again.revives).toBe(2)
			t.expect(h.runs:summary(A).revives).toBe(2)
		end)

		t.it("revives for the player who stays when the partner has left, and says so", function()
			local h = harness(alreadyOver())
			local state = started(h)
			h.runs:leave(A)
			local outcome = h.runs:revive(B, state.runId)
			assert(outcome, "the stayer revives the run")
			t.expect(outcome.present).toEqual({ false, true })
			t.expect(outcome.states[2].session.present).toEqual({ false, true })
			t.expect(h.runs:revive(A, state.runId)).toBe(nil) -- A is out of the run
		end)

		t.it("forgets a player's turn limiter with the rest once everyone is gone", function()
			local h = harness()
			local state = started(h)
			turn(h, A, state.runId, 1, 0)
			turn(h, B, state.runId, 3, 0)
			h.runs:close(1)
			h.runs:remove(A)
			h.runs:remove(B)
			t.expect(h.runs:footprint()).toBe(0)
		end)
	end)

	t.describe("CoopSync turns", function()
		t.it(
			"turns the player's own piece at once, keeps it pending and spends their free rotation on screen",
			function()
				local _, sync = pair(1)
				t.expect(sync:freeRotations()).toBe(Config.FREE_ROTATIONS_PER_RUN)
				local result, moveId = sync:rotate(1, 0)
				assert(result, "the turn is valid")
				t.expect(result.charged).toBe("free")
				t.expect(moveId).toBe(1)
				t.expect(sync:pendingCount()).toBe(1)
				t.expect(Helpers.ids(sync:session().session.tray)).toEqual({ "I3_V", "I3_H", "I3_H", "I3_H" })
				t.expect(Helpers.ids(sync.confirmed.session.tray)).toEqual(BARS) -- only the server confirms
				t.expect(sync:freeRotations()).toBe(Config.FREE_ROTATIONS_PER_RUN - 1)

				t.expect(sync:rotate(2, 0)).toBe(nil) -- no free rotation left and none bought
				local before = sync:session():snapshot()
				t.expect(sync:rotate(3, 9)).toBe(nil) -- the partner's piece
				t.expect(sync:rotate("2", 9)).toBe(nil)
				t.expect(sync:session():snapshot()).toEqual(before)
				local bought = sync:rotate(2, 1)
				assert(bought, "a bought rotation pays")
				t.expect(bought.charged).toBe("paid")
				t.expect(sync:pendingCount()).toBe(2)
			end
		)

		t.it("confirms the player's own turn without changing what is shown", function()
			local server, sync = pair(1)
			sync:rotate(1, 0)
			local shownBefore = sync:session():snapshot()
			local applied = sync:applyTurn(serverTurn(server, 1, 1, 1, 1, 0))
			assert(applied.kind == "applied", "the turn applies")
			t.expect(applied.mine).toBe(true)
			t.expect(applied.dropped).toEqual({})
			t.expect(sync:pendingCount()).toBe(0)
			t.expect(sync.seq).toBe(1)
			t.expect(sync.confirmed:snapshot()).toEqual(server:snapshot())
			t.expect(sync:session():snapshot()).toEqual(shownBefore)
		end)

		t.it("applies the partner's turn, whether it cost them a free rotation or a bought one", function()
			local server, sync = pair(1)
			local free = sync:applyTurn(serverTurn(server, 1, 2, 1, 3, 0))
			assert(free.kind == "applied", "applies")
			t.expect(free.mine).toBe(false)
			t.expect(free.result.slot).toBe(3)
			t.expect(sync:session().session.tray[3].id).toBe("I3_V")
			t.expect(sync:freeRotations()).toBe(Config.FREE_ROTATIONS_PER_RUN) -- our own are not touched

			local paid = sync:applyTurn(serverTurn(server, 2, 2, 2, 4, 1))
			assert(paid.kind == "applied", "a turn paid for with a bought rotation applies too")
			t.expect(sync:session().session.tray[4].id).toBe("I3_V")
			t.expect(sync.confirmed:snapshot()).toEqual(server:snapshot())
		end)

		t.it("asks for the state when a turn costs something other than what the server says", function()
			local _, fresh = pair(1)
			local forged: CoopSync.Turn = { runId = 1, seq = 1, seat = 2, moveId = 1, slot = 3, charged = "paid" }
			t.expect(fresh:applyTurn(forged).kind).toBe("resync") -- the partner still has a free rotation: not paid
			t.expect(fresh.seq).toBe(0)

			local server, sync = pair(1)
			sync:applyTurn(serverTurn(server, 1, 2, 1, 3, 0))
			local broke: CoopSync.Turn = { runId = 1, seq = 2, seat = 2, moveId = 2, slot = 4, charged = "free" }
			t.expect(sync:applyTurn(broke).kind).toBe("resync") -- their free rotation is spent
			t.expect(sync.seq).toBe(1)
		end)

		t.it("asks for the state when a turn is missing, and ignores one it has or from another run", function()
			local server, sync = pair(1)
			local turned = serverTurn(server, 1, 2, 1, 3, 0)
			local later = table.clone(turned)
			later.seq = 2
			t.expect(sync:applyTurn(later)).toEqual({ kind = "resync", reason = "expected move 1, got 2" })
			t.expect(sync:applyTurn(turned).kind).toBe("applied")
			t.expect(sync:applyTurn(turned)).toEqual({ kind = "ignored" })
			local other = table.clone(turned)
			other.runId = 2
			other.seq = 2
			t.expect(sync:applyTurn(other)).toEqual({ kind = "ignored" })
		end)

		t.it("keeps its own turn turned when the partner's move arrives", function()
			local server, sync = pair(1)
			sync:rotate(1, 0)
			local result = server:place(2, 3, 0, 0)
			assert(result, "the partner places")
			local applied = sync:applyMove({
				runId = 1,
				seq = 1,
				seat = 2,
				moveId = 1,
				slot = 3,
				x = 0,
				y = 0,
				score = server.session.score,
				set = nil,
				isOver = false,
				takeOverAt = nil,
			})
			assert(applied.kind == "applied", "applies")
			t.expect(applied.dropped).toEqual({})
			t.expect(sync:pendingCount()).toBe(1)
			t.expect(sync:session().session.tray[1].id).toBe("I3_V")
		end)

		t.it("takes a rejected turn out of pending and shows the piece as it was", function()
			local _, sync = pair(1)
			local _, moveId = sync:rotate(1, 0)
			assert(moveId, "turned")
			t.expect(sync:reject(1, moveId)).toEqual({})
			t.expect(sync:pendingCount()).toBe(0)
			t.expect(sync:session().session.tray[1].id).toBe("I3_H")
			t.expect(sync:freeRotations()).toBe(Config.FREE_ROTATIONS_PER_RUN)
		end)

		t.it("plays a turn and the move that places the turned piece, in that order, and confirms both", function()
			local server, sync = pair(1)
			sync:rotate(1, 0)
			local placed = sync:place(1, 0, 0) -- vertical bar at the top left
			assert(placed, "the turned piece can be placed")
			t.expect(sync:pendingCount()).toBe(2)

			t.expect(sync:applyTurn(serverTurn(server, 1, 1, 1, 1, 0)).kind).toBe("applied")
			local result = server:place(1, 1, 0, 0)
			assert(result, "the server places it too")
			local applied = sync:applyMove({
				runId = 1,
				seq = 2,
				seat = 1,
				moveId = 2,
				slot = 1,
				x = 0,
				y = 0,
				score = server.session.score,
				set = nil,
				isOver = false,
				takeOverAt = nil,
			})
			assert(applied.kind == "applied", "applies")
			t.expect(sync:pendingCount()).toBe(0)
			t.expect(sync.confirmed:snapshot()).toEqual(server:snapshot())
			t.expect(sync:session():snapshot()).toEqual(server:snapshot())
		end)
	end)

	t.describe("Purchases.reviveApplies", function()
		local function context(kind: "solo" | "coop", runId: number, isOver: boolean): Purchases.RunContext
			return { kind = kind, runId = runId, isOver = isOver, revives = 0 }
		end

		t.it("applies to the very run it was asked for, while it is over", function()
			t.expect(Purchases.reviveApplies(context("coop", 3, true), "coop", 3)).toBe(true)
			t.expect(Purchases.reviveApplies(context("solo", 3, true), "solo", 3)).toBe(true)
		end)

		t.it("does not apply to another run, another kind of run, a run that is not over, or no run", function()
			t.expect(Purchases.reviveApplies(context("coop", 4, true), "coop", 3)).toBe(false)
			t.expect(Purchases.reviveApplies(context("solo", 3, true), "coop", 3)).toBe(false) -- the two count runs separately
			t.expect(Purchases.reviveApplies(context("coop", 3, true), "solo", 3)).toBe(false)
			t.expect(Purchases.reviveApplies(context("coop", 3, false), "coop", 3)).toBe(false) -- the partner revived it first
			t.expect(Purchases.reviveApplies(nil, "coop", 3)).toBe(false)
			t.expect(Purchases.reviveApplies(context("coop", 3, true), "coop", "3")).toBe(false)
		end)
	end)

	t.describe("Co-op analytics", function()
		type Logged = {
			kind: string,
			name: string,
			step: number?,
			session: string?,
			fields: { string }?,
			funnel: string?,
		}
		local function newTelemetry(): (Telemetry.Telemetry, { Logged })
			local logged: { Logged } = {}
			local telemetry = Telemetry.new({
				onboardingStep = function() end,
				custom = function(_player: any, name: string, _value: number, fields: { string })
					table.insert(logged, { kind = "custom", name = name, fields = fields })
				end,
				funnel = function(_player: any, funnel: string, session: string, step: number, name: string)
					table.insert(
						logged,
						{ kind = "funnel", name = name, step = step, session = session, funnel = funnel }
					)
				end,
			})
			return telemetry, logged
		end

		t.it("logs the Co-op revive funnel apart from the solo one", function()
			local telemetry, logged = newTelemetry()
			telemetry:coopReviveStep("p", "c3.0", 1)
			telemetry:coopReviveStep("p", "c3.0", 4)
			t.expect(logged).toEqual({
				{ kind = "funnel", name = "Offered", step = 1, session = "c3.0", funnel = "CoopReviveOffer" },
				{ kind = "funnel", name = "Revived", step = 4, session = "c3.0", funnel = "CoopReviveOffer" },
			})
		end)

		t.it("tells Co-op rotations from solo ones by a second field", function()
			local telemetry, logged = newTelemetry()
			telemetry:rotationUsed("p", "free")
			telemetry:rotationUsed("p", "paid", true)
			t.expect(logged).toEqual({
				{ kind = "custom", name = "RotationUsed", fields = { "free" } },
				{ kind = "custom", name = "RotationUsed", fields = { "paid", "coop" } },
			})
		end)
	end)
end
