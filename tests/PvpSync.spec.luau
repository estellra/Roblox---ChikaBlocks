--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local PvpSession = require("../src/shared/PvpSession")
local PvpSync = require("../src/client/Util/PvpSync")
local TestKit = require("./TestKit")

local PVP = Config.PVP
local SIZE = Config.GRID_SIZE
local MATCH_ID = 7
local NOW = 10

-- Empty cells on both diagonals: nothing bigger than a Dot fits.
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

local function stateOf(server: PvpSession.PvpSession): PvpSync.State
	return {
		matchId = MATCH_ID,
		kind = "friendly",
		seat = 1,
		startAt = 0,
		endAt = PVP.MATCH_SECONDS,
		you = server:snapshot(),
		opponent = {},
		ended = nil,
	}
end

local function setUp(): (PvpSession.PvpSession, PvpSync.PvpSync)
	local server = PvpSession.new(99, 1, 0, PVP.MATCH_SECONDS)
	return server, PvpSync.new({ PvpSession = PvpSession }, stateOf(server))
end

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

-- The server's answer to the move, as PvpEvent("result") carries it.
local function answer(
	server: PvpSession.PvpSession,
	moveIndex: number,
	slot: number,
	x: number,
	y: number
): PvpSync.Result
	local result = server:place(slot, x, y, NOW)
	assert(result, "the server refused the move")
	return {
		matchId = MATCH_ID,
		moveIndex = moveIndex,
		score = server.game.score,
		sent = result.sent,
		cancelled = result.cancelled,
		pending = table.clone(server.pending),
		refill = result.refill,
		stuck = result.stuck,
	}
end

return function(t: TestKit.TestKit)
	t.describe("PvpSync", function()
		t.it("shows the player's move at once and matches the server once it answers", function()
			local server, sync = setUp()
			for _ = 1, 7 do -- across two refills
				local slot, x, y = firstMove(sync.session)
				local predicted, moveIndex = sync:place(slot, x, y, NOW)
				assert(predicted and moveIndex)
				t.expect(sync.session.game.moveCount).toBe(moveIndex + 1)
				local applied = sync:onResult(answer(server, moveIndex, slot, x, y))
				t.expect(applied.kind).toBe("applied")
				t.expect(sync.session:snapshot()).toEqual(server:snapshot())
			end
			t.expect(sync.session.setIndex).toBe(3)
		end)

		t.it("replays garbage and a new set at the end of a set", function()
			local server, sync = setUp()
			server:receiveAttack(2)
			t.expect(sync:onIncoming(MATCH_ID, server.pending)).toBe(true)
			local last: PvpSync.Applied? = nil
			for _ = 1, Config.PIECES_PER_SET do
				local slot, x, y = firstMove(sync.session)
				local _, moveIndex = sync:place(slot, x, y, NOW)
				last = sync:onResult(answer(server, moveIndex :: number, slot, x, y))
			end
			assert(last and last.kind == "applied")
			t.expect(last.refill ~= nil).toBe(true)
			t.expect(sync.session.takenTotal).toBe(1)
			t.expect(sync.session:snapshot()).toEqual(server:snapshot())
		end)

		t.it("replays the board being cleared when nothing fits", function()
			local server, sync = setUp()
			for _, session in { server, sync.session } do
				session.game.board = Helpers.boardFromRows(DIAGONALS)
				session.game.tray = { Pieces.BY_ID.Dot, Pieces.BY_ID.O3, Pieces.BY_ID.O3 }
			end
			local _, moveIndex = sync:place(1, 0, 0, NOW)
			t.expect(sync:canDrag(NOW)).toBe(false) -- stuck until the server says how it was cleared
			local applied = sync:onResult(answer(server, moveIndex :: number, 1, 0, 0))
			assert(applied.kind == "applied")
			t.expect(applied.stuck ~= nil).toBe(true)
			t.expect(sync:canDrag(NOW)).toBe(false)
			t.expect(sync:canDrag(NOW + PVP.STUCK_LOCK_SECONDS)).toBe(true)
			t.expect(sync.session:snapshot()).toEqual(server:snapshot())
		end)

		t.it("asks for the state when the score differs or a move was skipped", function()
			local server, sync = setUp()
			local slot, x, y = firstMove(sync.session)
			local _, moveIndex = sync:place(slot, x, y, NOW)
			local message = answer(server, moveIndex :: number, slot, x, y)
			message.score += 1
			t.expect(sync:onResult(message).kind).toBe("resync")

			local server2, sync2 = setUp()
			slot, x, y = firstMove(sync2.session)
			sync2:place(slot, x, y, NOW)
			local skipped = answer(server2, 0, slot, x, y)
			skipped.moveIndex = 1
			t.expect(sync2:onResult(skipped).kind).toBe("resync")
		end)

		t.it("takes the server's count of garbage sent and cancelled when its queue was newer", function()
			local server, sync = setUp()
			-- The server already holds an attack the client hasn't heard of; the client's double clear cancels nothing.
			server:receiveAttack(1)
			for _, session in { server, sync.session } do
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
			end
			local predicted, moveIndex = sync:place(1, 0, 0, NOW)
			assert(predicted)
			t.expect(predicted.sent).toBe(1)
			t.expect(sync:onResult(answer(server, moveIndex :: number, 1, 0, 0)).kind).toBe("applied")
			t.expect(sync.session.sentTotal).toBe(0)
			t.expect(sync.session.blockedTotal).toBe(1)
			t.expect(sync.session:snapshot()).toEqual(server:snapshot())
		end)

		t.it("asks for the state when the server finished a set it didn't send", function()
			local server, sync = setUp()
			local message: PvpSync.Result? = nil
			for i = 1, Config.PIECES_PER_SET do
				local slot, x, y = firstMove(sync.session)
				local _, moveIndex = sync:place(slot, x, y, NOW)
				message = answer(server, moveIndex :: number, slot, x, y)
				if i < Config.PIECES_PER_SET then
					sync:onResult(message :: PvpSync.Result)
				end
			end
			assert(message)
			message.refill = nil
			t.expect(sync:onResult(message).kind).toBe("resync")
		end)

		t.it("ignores a result it has already and one from another match", function()
			local server, sync = setUp()
			local slot, x, y = firstMove(sync.session)
			local _, moveIndex = sync:place(slot, x, y, NOW)
			local message = answer(server, moveIndex :: number, slot, x, y)
			local other = table.clone(message)
			other.matchId = MATCH_ID + 1
			t.expect(sync:onResult(other).kind).toBe("ignored")
			t.expect(sync:onResult(message).kind).toBe("applied")
			t.expect(sync:onResult(message).kind).toBe("ignored")
			t.expect(sync:onIncoming(MATCH_ID + 1, { 1 })).toBe(false)
			t.expect(sync:onIncoming(MATCH_ID, { 7 })).toBe(false)
		end)

		t.it("lets the player drag only while the match is on", function()
			local _, sync = setUp()
			t.expect(sync:canDrag(-0.1)).toBe(false)
			t.expect(sync:canDrag(0)).toBe(true)
			t.expect(sync:canDrag(PVP.MATCH_SECONDS - 0.01)).toBe(true)
			t.expect(sync:canDrag(PVP.MATCH_SECONDS)).toBe(false) -- the client stops at the end; no grace
			local slot, x, y = firstMove(sync.session)
			t.expect(sync:place(slot, x, y, PVP.MATCH_SECONDS)).toBe(nil)
			sync:onEnd({ matchId = MATCH_ID })
			t.expect(sync:canDrag(NOW)).toBe(false)
		end)

		t.it("notices a move the server never answered", function()
			local _, sync = setUp()
			local slot, x, y = firstMove(sync.session)
			sync:place(slot, x, y, NOW)
			t.expect(sync:overdue(NOW + 2, 2)).toBe(false)
			t.expect(sync:overdue(NOW + 2.1, 2)).toBe(true)
		end)

		t.it("forgets unanswered moves when it gets the state", function()
			local server, sync = setUp()
			local slot, x, y = firstMove(sync.session)
			sync:place(slot, x, y, NOW)
			sync:reset(stateOf(server))
			t.expect(sync.session.game.moveCount).toBe(0)
			t.expect(sync:overdue(NOW + 100, 2)).toBe(false)
		end)
	end)
end
