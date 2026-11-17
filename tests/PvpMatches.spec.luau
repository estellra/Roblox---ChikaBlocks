--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local PvpMatches = require("../src/server/PvpMatches")
local PvpSession = require("../src/shared/PvpSession")
local TestKit = require("./TestKit")

local PVP = Config.PVP
local SIZE = Config.GRID_SIZE
local T0 = 50

type Harness = { matches: PvpMatches.PvpMatches, clock: { now: number } }

local function harness(): Harness
	local clock = { now = T0 }
	local seed = 0
	local matches = PvpMatches.new({
		PvpSession = PvpSession,
		settings = PVP,
		clock = function(): number
			return clock.now
		end,
		newSeed = function(): number
			seed += 1
			return seed
		end,
	})
	return { matches = matches, clock = clock }
end

-- Starts a match between A and B and moves the clock past the countdown.
local function started(kind: string?): (Harness, number)
	local h = harness()
	local states = h.matches:start({ players = { "A", "B" } }, kind or "friendly")
	assert(states)
	h.clock.now = states[1].startAt
	return h, states[1].matchId
end

local function sessionOf(h: Harness, key: string): PvpSession.PvpSession
	local match = (h.matches :: any).matchOf[key]
	return match.sides[if match.sides[1].key == key then 1 else 2].session
end

-- The first valid move for the player.
local function firstMove(session: PvpSession.PvpSession): (number, number, number)
	for slot, piece in session.game.tray do
		if piece then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if Board.canPlace(session.game.board, piece, x, y) then
						return slot, x, y
					end
				end
			end
		end
	end
	error("no move")
end

local function play(h: Harness, key: string, matchId: number): PvpMatches.PlaceOutcome
	local session = sessionOf(h, key)
	local slot, x, y = firstMove(session)
	return h.matches:place(key, matchId, session.game.moveCount, slot, x, y)
end

-- Rows 0 to 1 full but for column 0: an upright I2 there clears two rows (attack 1).
local function setUpDoubleClear(session: PvpSession.PvpSession)
	session.game.board = Helpers.boardFromRows({
		".#######",
		".#######",
		"........",
		"........",
		"........",
		"........",
		"........",
		"#.......",
	})
	session.game.tray = { Pieces.BY_ID.I2_V, Pieces.BY_ID.Dot, Pieces.BY_ID.Dot }
	session.game.unlocked = { false, false, false }
	session.game.awaitingSet = false
	session.game.isOver = false
end

return function(t: TestKit.TestKit)
	t.describe("PvpMatches", function()
		t.describe("start", function()
			t.it("starts both seats after the countdown, with the same first set", function()
				local h = harness()
				local states = h.matches:start({ players = { "A", "B" } }, "ranked")
				assert(states)
				local a, b = states[1], states[2]
				t.expect(a.seat).toBe(1)
				t.expect(b.seat).toBe(2)
				t.expect(a.matchId).toBe(b.matchId)
				t.expect(a.kind).toBe("ranked")
				t.expect(a.startAt).toBe(T0 + PVP.COUNTDOWN_SECONDS)
				t.expect(a.endAt).toBe(a.startAt + PVP.MATCH_SECONDS)
				t.expect(a.you.game.tray).toEqual(b.you.game.tray)
				t.expect(a.opponent.cells).toEqual(table.create(SIZE * SIZE, 0))
				t.expect(a.you.seed).toBe(nil) -- the seed never leaves the server
			end)

			t.it("refuses a bad kind, one player twice, or a player whose match is still going", function()
				local h = harness()
				t.expect(h.matches:start({ players = { "A", "B" } }, "casual")).toBe(nil)
				t.expect(h.matches:start({ players = { "A", "B" } }, nil)).toBe(nil)
				t.expect(h.matches:start({ players = { "A", "A" } }, "friendly")).toBe(nil)
				t.expect(h.matches:start({ players = { "A" } }, "friendly")).toBe(nil)
				assert(h.matches:start({ players = { "A", "B" } }, "friendly"))
				t.expect(h.matches:start({ players = { "A", "C" } }, "friendly")).toBe(nil)
			end)
		end)

		t.describe("place", function()
			t.it("accepts a move after the countdown and reports the score", function()
				local h, id = started()
				local outcome = play(h, "A", id)
				assert(outcome.kind == "accepted")
				t.expect(outcome.moveIndex).toBe(0)
				t.expect(outcome.score).toBe(sessionOf(h, "A").game.score)
				t.expect(outcome.opponent).toBe("B")
				t.expect(sessionOf(h, "B").game.moveCount).toBe(0)
			end)

			t.it("sends the state back for a move during the countdown", function()
				local h = harness()
				local states = h.matches:start({ players = { "A", "B" } }, "friendly")
				assert(states)
				t.expect(play(h, "A", states[1].matchId).kind).toBe("resync")
			end)

			t.it("drops stale moves and sends the state for moves from the future", function()
				local h, id = started()
				play(h, "A", id)
				local session = sessionOf(h, "A")
				local slot, x, y = firstMove(session)
				t.expect(h.matches:place("A", id, 0, slot, x, y)).toEqual({ kind = "ignored", reason = "stale move" })
				t.expect(h.matches:place("A", id, 5, slot, x, y).kind).toBe("resync")
			end)

			t.it("ignores junk match ids and move indexes, and sends the state for junk positions", function()
				local h, id = started()
				for _, bad in { nil, "1", 0 / 0, math.huge, -math.huge, {}, 2 ^ 40, id + 1, 1.5 } do
					t.expect(h.matches:place("A", bad, 0, 1, 0, 0).kind).toBe("ignored")
				end
				h.clock.now += 1
				for _, bad in { nil, "0", 0 / 0, -1, 0.5, math.huge, {} } do
					t.expect(h.matches:place("A", id, bad, 1, 0, 0).kind).toBe("ignored")
				end
				h.clock.now += 1
				for _, bad in { { 9, 0, 0 }, { 1, 0 / 0, 0 }, { 1, 0, "0" }, { "1", 0, 0 }, { 1, 99, 0 }, { {}, 0, 0 } } do
					t.expect(h.matches:place("A", id, 0, bad[1], bad[2], bad[3]).kind).toBe("resync")
				end
				t.expect(h.matches:place("C", id, 0, 1, 0, 0)).toEqual({ kind = "ignored", reason = "no match" })
			end)

			t.it("rate limits moves", function()
				local h, id = started()
				local limited = 0
				for _ = 1, 9 do
					if h.matches:place("A", id, 99, 1, 0, 0).kind == "ignored" then
						limited += 1
					end
				end
				t.expect(limited).toBe(1)
			end)

			t.it("takes moves until the end plus the grace period, then drops them", function()
				local h, id = started()
				local state = h.matches:peek("A")
				assert(state)
				h.clock.now = state.endAt + PVP.END_GRACE_SECONDS
				t.expect(play(h, "A", id).kind).toBe("accepted")
				h.clock.now += 0.01
				t.expect(play(h, "A", id)).toEqual({ kind = "ignored", reason = "too late" })
			end)

			t.it("sends the state back for a move while the tray is locked", function()
				local h, id = started()
				local session = sessionOf(h, "A")
				session.lockedUntil = h.clock.now + 2
				t.expect(play(h, "A", id).kind).toBe("resync")
				h.clock.now += 2
				t.expect(play(h, "A", id).kind).toBe("accepted")
			end)
		end)

		t.describe("garbage", function()
			t.it("puts the attack in the opponent's queue and tells who to send it to", function()
				local h, id = started()
				local a = sessionOf(h, "A")
				setUpDoubleClear(a)
				local versionBefore = (h.matches:board("B") :: PvpMatches.BoardView).version
				local outcome = h.matches:place("A", id, 0, 1, 0, 0)
				assert(outcome.kind == "accepted")
				t.expect(outcome.attack).toBe(1)
				t.expect(outcome.sent).toBe(1)
				t.expect(outcome.opponent).toBe("B")
				local b = sessionOf(h, "B")
				t.expect(#b.pending).toBe(1)
				t.expect(outcome.incoming).toEqual(b.pending)
				local board = h.matches:board("B")
				assert(board)
				t.expect(board.pending).toBe(1)
				t.expect(board.version).toBe(versionBefore + 1)
			end)

			t.it("lets the victim's attack cancel what is waiting", function()
				local h, id = started()
				setUpDoubleClear(sessionOf(h, "A"))
				h.matches:place("A", id, 0, 1, 0, 0)
				setUpDoubleClear(sessionOf(h, "B"))
				local outcome = h.matches:place("B", id, 0, 1, 0, 0)
				assert(outcome.kind == "accepted")
				t.expect(outcome.cancelled).toBe(1)
				t.expect(outcome.sent).toBe(0)
				t.expect(outcome.pending).toEqual({})
				t.expect(outcome.incoming).toBe(nil)
				t.expect(#sessionOf(h, "A").pending).toBe(0)
			end)

			t.it("shows a player's moves in the board the opponent sees", function()
				local h, id = started()
				local before = h.matches:board("A")
				assert(before)
				play(h, "A", id)
				local after = h.matches:board("A")
				assert(after)
				t.expect(after.version).toBe(before.version + 1)
				t.expect(after.cells).toEqual(sessionOf(h, "A").game.board.cells)
				t.expect(after.score).toBe(sessionOf(h, "A").game.score)
				t.expect(h.matches:opponentOf("A")).toBe("B")
			end)
		end)

		t.describe("ending", function()
			t.it("ends on time: the higher score wins", function()
				local h, id = started()
				play(h, "A", id)
				local state = h.matches:peek("A")
				assert(state)
				h.clock.now = state.endAt + PVP.END_GRACE_SECONDS
				t.expect(#h.matches:sweep()).toBe(0)
				h.clock.now += 0.1
				local ended = h.matches:sweep()
				t.expect(#ended).toBe(1)
				t.expect(ended[1].reason).toBe("time")
				t.expect(ended[1].results).toEqual({ "win", "loss" })
				t.expect(ended[1].players).toEqual({ "A", "B" })
				t.expect(#h.matches:sweep()).toBe(0)
				t.expect(play(h, "B", id)).toEqual({ kind = "ignored", reason = "ended" })
			end)

			t.it("calls equal scores a draw", function()
				local h = started()
				local state = h.matches:peek("A")
				assert(state)
				h.clock.now = state.endAt + 1
				t.expect(h.matches:sweep()[1].results).toEqual({ "draw", "draw" })
			end)

			t.it("gives the win to the other player when one forfeits, whatever the score", function()
				local h, id = started()
				play(h, "A", id)
				local info = h.matches:forfeit("A", id)
				assert(info)
				t.expect(info.reason).toBe("forfeit")
				t.expect(info.results).toEqual({ "loss", "win" })
				t.expect(h.matches:forfeit("B", id)).toBe(nil)
				t.expect(h.matches:forfeit("A", 999)).toBe(nil)
			end)

			t.it("counts leaving a match still going as a loss, and leaving an ended one as nothing", function()
				local h = started()
				local info = h.matches:leave("B")
				assert(info)
				t.expect(info.reason).toBe("left")
				t.expect(info.results).toEqual({ "win", "loss" })
				t.expect(h.matches:leave("A")).toBe(nil)
				t.expect(h.matches:footprint()).toBe(0) -- the match is gone once both have left it
				t.expect(h.matches:peek("A")).toBe(nil)
			end)

			t.it("cancels matches still going without a result", function()
				local h = started()
				local ended = h.matches:cancelAll()
				t.expect(#ended).toBe(1)
				t.expect(ended[1].reason).toBe("cancelled")
				t.expect(ended[1].results).toBe(nil)
				t.expect(#h.matches:cancelAll()).toBe(0)
			end)

			t.it("reports garbage sent and blocked at the end", function()
				local h, id = started()
				setUpDoubleClear(sessionOf(h, "A"))
				h.matches:place("A", id, 0, 1, 0, 0)
				setUpDoubleClear(sessionOf(h, "B"))
				h.matches:place("B", id, 0, 1, 0, 0)
				local info = h.matches:forfeit("A", id)
				assert(info)
				t.expect(info.sent).toEqual({ 1, 0 })
				t.expect(info.blocked).toEqual({ 0, 1 })
			end)
		end)

		t.describe("rematch", function()
			t.it("starts again once both vote, for a friendly match", function()
				local h, id = started("friendly")
				h.matches:forfeit("A", id)
				local first = h.matches:rematch("A", id)
				t.expect(first).toEqual({ votes = { true, false }, ready = false })
				local second = h.matches:rematch("B", id)
				t.expect(second).toEqual({ votes = { true, true }, ready = true })
				local states = h.matches:start({ players = { "A", "B" } }, "friendly")
				assert(states)
				t.expect(states[1].matchId).toBe(id + 1)
				t.expect(states[1].ended).toBe(nil)
			end)

			t.it("has no rematch for ranked, a match still going, or when the other player left", function()
				local h, id = started("ranked")
				t.expect(h.matches:rematch("A", id)).toBe(nil)
				h.matches:forfeit("A", id)
				t.expect(h.matches:rematch("A", id)).toBe(nil)
				local f, fid = started("friendly")
				t.expect(f.matches:rematch("A", fid)).toBe(nil)
				f.matches:forfeit("A", fid)
				f.matches:leave("B")
				t.expect(f.matches:rematch("A", fid)).toBe(nil)
			end)
		end)

		t.it("rotates with the free rotation only", function()
			local h, id = started()
			local session = sessionOf(h, "A")
			session.game.tray = { Pieces.BY_ID.L3_1, Pieces.BY_ID.L3_1, Pieces.BY_ID.Dot }
			t.expect(h.matches:rotate("A", id, 0, 1)).toEqual({ kind = "accepted", matchId = id, charged = "free" })
			t.expect(h.matches:rotate("A", id, 0, 2).kind).toBe("resync")
			t.expect(h.matches:rotate("A", id, 0, 9).kind).toBe("resync")
			t.expect(h.matches:rotate("A", "x", 0, 1).kind).toBe("ignored")
		end)

		t.it("summarises a player's match", function()
			local h, id = started("bot")
			play(h, "A", id)
			local summary = h.matches:summary("A")
			assert(summary)
			t.expect(summary.kind).toBe("bot")
			t.expect(summary.seat).toBe(1)
			t.expect(summary.moves).toBe(1)
			t.expect(summary.ended).toBe(false)
			t.expect(h.matches:summary("C")).toBe(nil)
		end)
	end)
end
