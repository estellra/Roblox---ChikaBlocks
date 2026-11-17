--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Generator = require("../src/shared/Generator")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local PvpSession = require("../src/shared/PvpSession")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local PVP = Config.PVP
local P = Pieces.BY_ID
local SIZE = Config.GRID_SIZE

local SEED = 1234
local START, FINISH = 0, PVP.MATCH_SECONDS
local NOW = 10 -- a moment inside the match

-- Empty cells on both diagonals: every row and column keeps two holes, and nothing bigger than a Dot fits.
local DIAGONALS = {
	".######.",
	"#.####.#",
	"##.##.##",
	"###..###",
	"###..###",
	"##.##.##",
	"#.####.#",
	".######.",
}

local function newServer(seat: number?): PvpSession.PvpSession
	return PvpSession.new(SEED, seat or 1, START, FINISH)
end

-- Replaces the board and the tray, as if the match had led there.
local function arrange(session: PvpSession.PvpSession, rows: { string }?, trayIds: { string })
	local game = session.game
	if rows then
		game.board = Helpers.boardFromRows(rows)
	end
	local tray = {}
	for i, id in trayIds do
		tray[i] = P[id]
	end
	game.tray = tray
	game.unlocked = table.create(#trayIds, false)
	game.awaitingSet = false
	game.isOver = false
end

-- The first valid move for the first piece left in the tray.
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

-- The last valid move (from the bottom right) for the last piece left in the tray.
local function lastMove(session: PvpSession.PvpSession): (number, number, number)
	for slot = #session.game.tray, 1, -1 do
		local piece = session.game.tray[slot]
		if piece then
			for y = SIZE - piece.height, 0, -1 do
				for x = SIZE - piece.width, 0, -1 do
					if Board.canPlace(session.game.board, piece, x, y) then
						return slot, x, y
					end
				end
			end
		end
	end
	error("no move")
end

-- Places the rest of the current set; returns the last result (the one that refilled the tray).
local function finishSet(session: PvpSession.PvpSession, now: number): PvpSession.PlaceResult
	local last: PvpSession.PlaceResult? = nil
	repeat
		local slot, x, y = firstMove(session)
		last = session:place(slot, x, y, now)
		assert(last, "move refused")
	until last.refill ~= nil or last.stuck ~= nil
	return last :: PvpSession.PlaceResult
end

return function(t: TestKit.TestKit)
	t.describe("PvpSession", function()
		t.describe("attackFor", function()
			t.it("follows the attack table", function()
				t.expect(PvpSession.attackFor(0, 5, false)).toBe(0)
				t.expect(PvpSession.attackFor(1, 1, false)).toBe(0)
				t.expect(PvpSession.attackFor(2, 1, false)).toBe(1)
				t.expect(PvpSession.attackFor(3, 1, false)).toBe(2)
				t.expect(PvpSession.attackFor(4, 1, false)).toBe(3)
				t.expect(PvpSession.attackFor(6, 1, false)).toBe(3)
			end)

			t.it("adds the combo bonus from ATTACK_COMBO_FROM and the board clear bonus", function()
				local from = PVP.ATTACK_COMBO_FROM
				t.expect(PvpSession.attackFor(1, from - 1, false)).toBe(0)
				t.expect(PvpSession.attackFor(1, from, false)).toBe(PVP.ATTACK_COMBO_BONUS)
				t.expect(PvpSession.attackFor(2, from, true))
					.toBe(1 + PVP.ATTACK_COMBO_BONUS + PVP.ATTACK_BOARD_CLEAR_BONUS)
			end)
		end)

		t.describe("junk lines", function()
			-- Row 7 is a garbage line with its hole at column 3; row 6 is pieces with one gap at column 3.
			local function withGarbageRow(session: PvpSession.PvpSession)
				arrange(session, {
					"#.......", -- keeps the board from being cleared
					"........",
					"........",
					"........",
					"........",
					"........",
					"###.####",
					"........",
				}, { "Dot", "I2_V", "Dot" })
				for x = 0, SIZE - 1 do
					if x ~= 3 then
						session.game.board.cells[Board.index(x, 7)] = PVP.GARBAGE_COLOR
					end
				end
			end

			t.it("clears a mostly garbage line without points, combo or attack", function()
				local session = newServer()
				withGarbageRow(session)
				session.game.combo = { combo = 2, movesSinceClear = 0 }
				local result = session:place(1, 3, 7, NOW)
				assert(result)
				t.expect(result.move.clearedRows).toEqual({ 7 })
				t.expect(result.junkLines).toBe(1)
				t.expect(result.move.points).toBe(1 * Config.SCORE_PER_CELL)
				t.expect(session.game.score).toBe(1 * Config.SCORE_PER_CELL)
				t.expect(session.game.combo).toEqual({ combo = 2, movesSinceClear = 1 })
				t.expect(result.attack).toBe(0)
				t.expect(Board.get(session.game.board, 0, 7)).toBe(0)
			end)

			t.it("still scores the other lines of the same move", function()
				local session = newServer()
				withGarbageRow(session)
				-- An upright I2 in column 3 fills both gaps: row 6 (pieces) and row 7 (garbage) clear together.
				local result = session:place(2, 3, 6, NOW)
				assert(result)
				t.expect(result.move.clearedRows).toEqual({ 6, 7 })
				t.expect(result.junkLines).toBe(1)
				t.expect(result.move.points).toBe(2 * Config.SCORE_PER_CELL + Config.CLEAR_POINTS[1])
				t.expect(result.move.combo).toBe(1)
				t.expect(result.attack).toBe(PvpSession.attackFor(1, 1, false))
			end)

			t.it("scores a line with garbage in no more than half its cells as usual", function()
				local session = newServer()
				arrange(session, {
					"#.......", -- keeps the board from being cleared
					"........",
					"........",
					"........",
					"........",
					"........",
					"........",
					"###.####",
				}, { "Dot", "Dot", "Dot" })
				for _, x in { 0, 1, 2, 4 } do
					session.game.board.cells[Board.index(x, 7)] = PVP.GARBAGE_COLOR -- 4 garbage cells of 8
				end
				local result = session:place(1, 3, 7, NOW)
				assert(result)
				t.expect(result.junkLines).toBe(0)
				t.expect(result.move.points).toBe(1 * Config.SCORE_PER_CELL + Config.CLEAR_POINTS[1])
			end)
		end)

		t.describe("sets", function()
			t.it("deals both seats the same first set, and the same sets for the same moves", function()
				local a, b = newServer(1), newServer(2)
				for _ = 1, 6 do
					t.expect(Helpers.ids(a.game.tray)).toEqual(Helpers.ids(b.game.tray))
					local ra, rb = finishSet(a, NOW), finishSet(b, NOW)
					t.expect(ra.refill and ra.refill.set).toEqual(rb.refill and rb.refill.set)
				end
				t.expect(a.setIndex).toBe(7)
			end)

			t.it("deals set k from its own stream whatever the board", function()
				-- Plays set 1 and two pieces of set 2, then works out set 3 from the board the last move leaves.
				local a = newServer()
				finishSet(a, NOW)
				local slot, x, y = firstMove(a)
				a:place(slot, x, y, NOW)
				slot, x, y = firstMove(a)
				a:place(slot, x, y, NOW)
				slot, x, y = firstMove(a)
				local boardBefore = Board.clone(a.game.board)
				local result = a:place(slot, x, y, NOW)
				assert(result and result.refill)
				local piece = result.move.piece
				Board.place(boardBefore, piece, x, y, piece.color)
				Board.clearLines(boardBefore, Board.findCompleteLines(boardBefore))
				local expected = Generator.nextSet(
					boardBefore,
					2 * PVP.DIFFICULTY_SCORE_PER_SET,
					Rng.new(Rng.mix(SEED, "set", 3)),
					"Normal",
					Config.PIECES_PER_SET,
					PVP.GENERATOR
				)
				t.expect(result.refill.set).toEqual(Helpers.ids(expected))
				t.expect(a.setIndex).toBe(3)
			end)

			t.it("gives different boards the same first candidate when it fits both", function()
				-- Set 2 is drawn on two different, nearly empty boards; there the first candidate passes on both.
				local a, b = newServer(1), newServer(2)
				local ra = finishSet(a, NOW)
				local rb: PvpSession.PlaceResult? = nil
				for _ = 1, Config.PIECES_PER_SET do
					local slot, x, y = lastMove(b)
					rb = b:place(slot, x, y, NOW)
				end
				assert(rb and ra.refill and rb.refill)
				t.expect(Board.get(a.game.board, 0, 0) ~= Board.get(b.game.board, 0, 0)).toBe(true)
				t.expect(ra.refill.set).toEqual(rb.refill.set)
			end)
		end)

		t.describe("garbage", function()
			t.it("cancels the nearest waiting lines first and sends the rest", function()
				local session = newServer()
				session.pending = { 1, 2, 3 }
				-- Rows 0 to 2 are full but for column 0: an upright I3 there clears three rows (attack 2).
				arrange(session, {
					".#######",
					".#######",
					".#######",
					"........",
					"........",
					"........",
					"........",
					"#.......",
				}, { "I3_V", "Dot", "Dot" })
				local result = session:place(1, 0, 0, NOW)
				assert(result)
				t.expect(result.attack).toBe(2)
				t.expect(result.cancelled).toBe(2)
				t.expect(result.sent).toBe(0)
				t.expect(session.pending).toEqual({ 3 })
				t.expect(session.blockedTotal).toBe(2)
			end)

			t.it("sends what is left after cancelling", function()
				local session = newServer()
				session.pending = { 2 }
				arrange(session, {
					".#######",
					".#######",
					".#######",
					"........",
					"........",
					"........",
					"........",
					"#.......",
				}, { "I3_V", "Dot", "Dot" })
				local result = session:place(1, 0, 0, NOW)
				assert(result)
				t.expect(result.cancelled).toBe(1)
				t.expect(result.sent).toBe(1)
				t.expect(#session.pending).toBe(0)
				t.expect(session.sentTotal).toBe(1)
			end)

			t.it("caps the queue, dropping the newest lines", function()
				local session = newServer()
				t.expect(session:receiveAttack(2)).toBe(2)
				local first = table.clone(session.pending)
				t.expect(session:receiveAttack(PVP.GARBAGE_QUEUE_MAX)).toBe(PVP.GARBAGE_QUEUE_MAX - 2)
				t.expect(#session.pending).toBe(PVP.GARBAGE_QUEUE_MAX)
				t.expect(session.pending[1]).toBe(first[1])
				t.expect(session.pending[2]).toBe(first[2])
				t.expect(session:receiveAttack(1)).toBe(0)
				for _, side in session.pending do
					t.expect(side >= 1 and side <= 3).toBe(true)
				end
			end)

			t.it("rejects a bad attack and runs only on the server", function()
				local session = newServer()
				t.expect(function()
					session:receiveAttack(-1)
				end).toThrow()
				t.expect(function()
					session:receiveAttack(0.5)
				end).toThrow()
				local client = PvpSession.fromSnapshot(session:snapshot())
				t.expect(function()
					client:receiveAttack(1)
				end).toThrow()
			end)

			t.it("enters one line per new set, from the side announced when it was queued", function()
				local session = newServer()
				session:receiveAttack(3)
				local announced = session.pending[1]
				local result = finishSet(session, NOW)
				assert(result.refill)
				t.expect(#result.refill.garbage).toBe(PVP.GARBAGE_PER_SET)
				t.expect(result.refill.garbage[1].side).toBe(announced)
				t.expect(#session.pending).toBe(3 - PVP.GARBAGE_PER_SET)
				t.expect(session.takenTotal).toBe(1)
			end)

			t.it("pushes the garbage in from that side, leaving one hole", function()
				for side = 1, 3 do
					local session = newServer()
					session.pending = { side }
					local result = finishSet(session, NOW)
					assert(result.refill)
					local hole = result.refill.garbage[1].hole
					for i = 0, SIZE - 1 do
						local x, y
						if side == 1 then
							x, y = i, SIZE - 1
						elseif side == 2 then
							x, y = 0, i
						else
							x, y = SIZE - 1, i
						end
						local cell = Board.get(session.game.board, x, y)
						if i == hole then
							t.expect(cell).toBe(0)
						else
							-- Garbage, unless a full line through it was cleared after the push.
							t.expect(cell == PVP.GARBAGE_COLOR or cell == 0).toBe(true)
						end
					end
				end
			end)

			t.it("deals a set with a move after garbage enters", function()
				for seed = 1, 40 do
					local session = PvpSession.new(seed, 1, START, FINISH)
					for _ = 1, 4 do
						session:receiveAttack(1)
						local result = finishSet(session, NOW)
						if result.refill then
							t.expect(session.game.isOver).toBe(false)
							t.expect(Board.findCompleteLines(session.game.board)).toEqual({ rows = {}, cols = {} })
						end
					end
				end
			end)
		end)

		t.describe("stuck", function()
			t.it("clears the middle, resets the combo, deals a set and locks the tray", function()
				local session = newServer()
				session.pending = { 1, 2 }
				arrange(session, DIAGONALS, { "Dot", "O3", "O3" })
				session.game.combo = { combo = 2, movesSinceClear = 0 }
				local result = session:place(1, 0, 0, NOW)
				assert(result and result.stuck)
				t.expect(result.refill).toBe(nil)
				t.expect(result.stuck.lockedUntil).toBe(NOW + PVP.STUCK_LOCK_SECONDS)
				t.expect(#result.stuck.set).toBe(Config.PIECES_PER_SET)
				t.expect(session.game.isOver).toBe(false)
				t.expect(session.game.combo.combo).toBe(0)
				t.expect(session.stuckCount).toBe(1)
				t.expect(session.pending).toEqual({ 1, 2 }) -- waiting garbage stays and doesn't enter
				t.expect(session.setIndex).toBe(1)
				for y = 2, 5 do
					for x = 2, 5 do
						t.expect(Board.get(session.game.board, x, y)).toBe(0)
					end
				end
			end)

			t.it("refuses moves and rotations while the tray is locked", function()
				local session = newServer()
				arrange(session, DIAGONALS, { "Dot", "O3", "O3" })
				local result = session:place(1, 0, 0, NOW)
				assert(result and result.stuck)
				local unlock = result.stuck.lockedUntil
				t.expect(session:isLocked(unlock - 0.1)).toBe(true)
				local slot, x, y = firstMove(session)
				t.expect(session:place(slot, x, y, unlock - 0.1)).toBe(nil)
				for i = 1, Config.PIECES_PER_SET do
					t.expect(session:rotate(i, unlock - 0.1)).toBe(nil)
				end
				t.expect(session:isLocked(unlock)).toBe(false)
				t.expect(session:place(slot, x, y, unlock) ~= nil).toBe(true)
			end)

			t.it("keeps the set numbers: the next normal set is set 2", function()
				local session = newServer()
				arrange(session, DIAGONALS, { "Dot", "O3", "O3" })
				local stuck = session:place(1, 0, 0, NOW)
				assert(stuck and stuck.stuck)
				-- Play the set dealt after being stuck on a fresh board, so nothing gets stuck again.
				arrange(session, {}, { "Dot", "Dot", "Dot" })
				local after = finishSet(session, stuck.stuck.lockedUntil)
				assert(after.refill)
				t.expect(session.setIndex).toBe(2)
				local expected = Generator.nextSet(
					Helpers.boardFromRows({ "###....." }),
					PVP.DIFFICULTY_SCORE_PER_SET,
					Rng.new(Rng.mix(SEED, "set", 2)),
					"Normal",
					Config.PIECES_PER_SET,
					PVP.GENERATOR
				)
				t.expect(after.refill.set).toEqual(Helpers.ids(expected))
			end)
		end)

		t.describe("timing and rotation", function()
			t.it("accepts moves from startAt to endAt plus the grace period", function()
				local session = PvpSession.new(SEED, 1, 100, 280)
				local slot, x, y = firstMove(session)
				t.expect(session:place(slot, x, y, 99.9)).toBe(nil)
				t.expect(session:place(slot, x, y, 280 + PVP.END_GRACE_SECONDS + 0.01)).toBe(nil)
				t.expect(session:place(slot, x, y, 0 / 0)).toBe(nil)
				t.expect(session:place(slot, x, y, "100" :: any)).toBe(nil)
				t.expect(session:place(slot, x, y, 280 + PVP.END_GRACE_SECONDS) ~= nil).toBe(true)
			end)

			t.it("rotates with the match's free rotations only", function()
				local session = newServer()
				arrange(session, nil, { "L3_1", "L3_1", "Dot" })
				t.expect(session.game.freeRotations).toBe(PVP.FREE_ROTATIONS)
				local first = session:rotate(1, NOW)
				assert(first)
				t.expect(first.charged).toBe("free")
				t.expect(session:rotate(1, NOW) ~= nil).toBe(true) -- an unlocked piece keeps turning
				t.expect(session:rotate(2, NOW)).toBe(nil) -- nothing left to pay with
			end)
		end)

		t.describe("client", function()
			t.it("round-trips a snapshot", function()
				local session = newServer()
				session:receiveAttack(2)
				finishSet(session, NOW)
				local snapshot = session:snapshot()
				t.expect(PvpSession.fromSnapshot(snapshot):snapshot()).toEqual(snapshot)
			end)

			t.it("replays the server's refills and unsticks cell for cell", function()
				local server = newServer()
				local client = PvpSession.fromSnapshot(server:snapshot())
				server:receiveAttack(2)
				t.expect(client:setPending(server.pending)).toBe(true)
				for _ = 1, 8 do
					local slot, x, y = firstMove(server)
					local result = server:place(slot, x, y, NOW)
					assert(result)
					local predicted = client:place(slot, x, y, NOW)
					assert(predicted)
					t.expect(predicted.attack).toBe(result.attack)
					if result.refill then
						t.expect(client:deliver(result.refill.garbage, result.refill.set)).toBe(true)
					end
					if result.stuck then
						t.expect(client:applyStuck(result.stuck.set, result.stuck.lockedUntil)).toBe(true)
					end
					t.expect(client:setPending(server.pending)).toBe(true)
					t.expect(client:snapshot()).toEqual(server:snapshot())
				end
			end)

			t.it("replays a stuck board", function()
				local server = newServer()
				arrange(server, DIAGONALS, { "Dot", "O3", "O3" })
				local client = PvpSession.fromSnapshot(server:snapshot())
				local result = server:place(1, 0, 0, NOW)
				assert(result and result.stuck)
				t.expect(client:place(1, 0, 0, NOW) ~= nil).toBe(true)
				t.expect(client.game.isOver).toBe(true)
				t.expect(client:applyStuck(result.stuck.set, result.stuck.lockedUntil)).toBe(true)
				t.expect(client:snapshot()).toEqual(server:snapshot())
			end)

			t.it("never deals on its own and rejects malformed server values", function()
				local server = newServer()
				local client = PvpSession.fromSnapshot(server:snapshot())
				local predicted: PvpSession.PlaceResult? = nil
				for _ = 1, Config.PIECES_PER_SET do
					local slot, x, y = firstMove(client)
					predicted = client:place(slot, x, y, NOW)
				end
				assert(predicted)
				t.expect(predicted.refill).toBe(nil)
				t.expect(client.game.awaitingSet).toBe(true)

				local before = client:snapshot()
				t.expect(client:deliver({}, { "Dot", "Dot" })).toBe(false)
				t.expect(client:deliver({}, { "Dot", "Nope", "Dot" })).toBe(false)
				t.expect(client:deliver({ { side = 4, hole = 0 } }, { "Dot", "Dot", "Dot" })).toBe(false)
				t.expect(client:deliver({ { side = 1, hole = 8 } }, { "Dot", "Dot", "Dot" })).toBe(false)
				t.expect(client:deliver("x", { "Dot", "Dot", "Dot" })).toBe(false)
				t.expect(client:applyStuck({ "Dot", "Dot", "Dot" }, 20)).toBe(false) -- not stuck
				t.expect(client:setPending({ 1, 2, 3, 1, 2 })).toBe(false)
				t.expect(client:setPending({ 0 })).toBe(false)
				t.expect(client:setPending("1")).toBe(false)
				t.expect(client:snapshot()).toEqual(before)

				t.expect(client:deliver({ { side = 1, hole = 3 } }, { "Dot", "Dot", "Dot" })).toBe(true)
				t.expect(client.game.awaitingSet).toBe(false)
				t.expect(Board.get(client.game.board, 3, SIZE - 1)).toBe(0)
				t.expect(Board.get(client.game.board, 4, SIZE - 1)).toBe(PVP.GARBAGE_COLOR)
			end)
		end)
	end)
end
