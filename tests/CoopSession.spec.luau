--!strict
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local CoopSession = require("../src/shared/CoopSession")
local GameSession = require("../src/shared/GameSession")
local Generator = require("../src/shared/Generator")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local FOUR_DOTS = { "Dot", "Dot", "Dot", "Dot" }

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

-- No 2x2 gap anywhere, so a 2x2 block fits nowhere, but a dot at the top right completes row 0. Once that row is
-- cleared, row 0 and the gap in row 1 make room for a 2x2 block in the top left corner.
local BLOCKED_UNTIL_A_CLEAR = {
	"#######.",
	"..######",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
	"#.#.#.#.",
	".#.#.#.#",
}

local KNOWN_OVERRIDES: { [string]: boolean } = {
	DIFFICULTY_MAX_SCORE = true,
	WHOLE_SET_BELOW_SCORE = true,
	EACH_PIECE_BELOW_SCORE = true,
	SOLVER_NODE_BUDGET = true,
}

local function noSet(_board: Board.Board, _score: number, _reason: Generator.DealReason): { Pieces.Piece }?
	return nil
end

local function newRun(sets: { { string } }, board: Board.Board?): CoopSession.CoopSession
	return CoopSession.new((Helpers.queueSource(sets)), board)
end

-- Places a move that has to be valid and returns its result.
local function mustPlace(run: CoopSession.CoopSession, seat: number, slot: number, x: number, y: number)
	local result = run:place(seat, slot, x, y)
	assert(result, `seat {seat} could not place slot {slot} at {x},{y}`)
	return result
end

return function(t: TestKit.TestKit)
	t.describe("CoopSession", function()
		t.it("splits a set of four between two players", function()
			t.expect(Config.COOP.SET_SIZE).toBe(4)
			for slot, seat in { 1, 1, 2, 2 } do
				t.expect(CoopSession.seatOf(slot)).toBe(seat)
			end
			local notSlots: { any } = { 0, 5, -1, 1.5, "1", 0 / 0, math.huge, true, {} }
			for _, value in notSlots do
				t.expect(CoopSession.seatOf(value)).toBe(nil)
			end
			t.expect(CoopSession.seatOf(nil)).toBe(nil)
			t.expect(CoopSession.slotsOf(1)).toEqual({ 1, 2 })
			t.expect(CoopSession.slotsOf(2)).toEqual({ 3, 4 })
		end)

		t.it("only overrides generator numbers that exist", function()
			for key, value in Config.COOP.GENERATOR do
				t.expect(KNOWN_OVERRIDES[key]).toBe(true)
				t.expect(typeof(value)).toBe("number")
			end
		end)

		t.it("starts with four pieces, both players in and nothing scored", function()
			local run = newRun({ { "Dot", "O2", "I3_H", "I2_V" } })
			t.expect(run.session.setSize).toBe(4)
			t.expect(Helpers.ids(run.session.tray)).toEqual({ "Dot", "O2", "I3_H", "I2_V" })
			t.expect(run.present).toEqual({ true, true })
			t.expect(run.countedScore).toBe(0)
			t.expect(run.contribution).toEqual({ 0, 0 })

			local source = CoopSession.newSource(Rng.new(1))
			local set = source(Board.new(), 0, "Normal")
			assert(set, "the source deals right away")
			t.expect(#set).toBe(4)
		end)

		t.it("lets a player place only from their own slots", function()
			local run = newRun({ FOUR_DOTS })
			local before = run:snapshot()
			t.expect(run:place(1, 3, 0, 0)).toBe(nil)
			t.expect(run:place(1, 4, 0, 0)).toBe(nil)
			t.expect(run:place(2, 1, 0, 0)).toBe(nil)
			t.expect(run:place(2, 2, 0, 0)).toBe(nil)
			t.expect(run:canPlace(1, 3, 0, 0)).toBe(false)
			t.expect(run:canPlace(2, 1, 0, 0)).toBe(false)
			t.expect(run:snapshot()).toEqual(before)

			t.expect(run:canPlace(1, 1, 0, 0)).toBe(true)
			mustPlace(run, 1, 1, 0, 0)
			mustPlace(run, 2, 3, 1, 0)
		end)

		t.it("refuses seats and slots that are not real, and moves that do not fit", function()
			local run = newRun({ FOUR_DOTS })
			local before = run:snapshot()
			local badSeats: { any } = { 0, 3, -1, 1.5, "1", 0 / 0, math.huge, true, {} }
			for _, seat in badSeats do
				t.expect(run:place(seat, 1, 0, 0)).toBe(nil)
				t.expect(run:canPlace(seat, 1, 0, 0)).toBe(false)
				t.expect(run:hasMove(seat)).toBe(false)
				t.expect(run:release(seat)).toBe(false)
			end
			local badSlots: { any } = { 0, 5, 1.5, "1", 0 / 0, math.huge, {} }
			for _, slot in badSlots do
				t.expect(run:place(1, slot, 0, 0)).toBe(nil)
			end
			t.expect(run:place(nil, nil, nil, nil)).toBe(nil)
			t.expect(run:place(1, 1, 8, 0)).toBe(nil) -- off the board
			t.expect(run:place(1, 1, "0", 0)).toBe(nil)
			t.expect(run:snapshot()).toEqual(before)
		end)

		t.it("deals a new set only once all four pieces are placed", function()
			local run = newRun({ FOUR_DOTS, { "O2", "O2", "O2", "O2" } })
			for _, move in { { 1, 1, 0, 0 }, { 1, 2, 1, 0 }, { 2, 3, 2, 0 } } do
				t.expect(mustPlace(run, move[1], move[2], move[3], move[4]).refilled).toBe(false)
			end
			t.expect(Helpers.ids(run.session.tray)).toEqual({ false, false, false, "Dot" })

			-- Seat 1 has placed both pieces and waits for seat 2, but the run goes on.
			t.expect(run.session.isOver).toBe(false)
			t.expect(run:hasMove(1)).toBe(false)
			t.expect(run:hasMove(2)).toBe(true)
			t.expect(run:place(1, 1, 5, 5)).toBe(nil)

			t.expect(mustPlace(run, 2, 4, 3, 0).refilled).toBe(true)
			t.expect(Helpers.ids(run.session.tray)).toEqual({ "O2", "O2", "O2", "O2" })
			t.expect(run:hasMove(1)).toBe(true)
			t.expect(run:hasMove(2)).toBe(true)
		end)

		t.it("credits each move to the player who made it, and the credits add up to the team score", function()
			local run = newRun({ { "Dot", "Dot", "Dot", "O2" } }, Helpers.boardFromRows({ "######.." }))
			local first = mustPlace(run, 1, 1, 6, 0)
			local second = mustPlace(run, 2, 3, 7, 0) -- completes row 0
			local third = mustPlace(run, 1, 2, 0, 3)
			t.expect(#second.clearedRows).toBe(1)
			t.expect(second.points > first.points).toBe(true)
			t.expect(run.contribution).toEqual({ first.points + third.points, second.points })
			t.expect(run.contribution[1] + run.contribution[2]).toBe(run.session.score)
			t.expect(run.countedScore).toBe(run.session.score)
		end)

		t.it("lets the player who stays place the leaver's pieces, and nobody place for the leaver", function()
			for leaver = 1, 2 do
				local stayer = 3 - leaver
				local run = newRun({ FOUR_DOTS, FOUR_DOTS })
				t.expect(run:release(leaver)).toBe(true)
				t.expect(run.present[leaver]).toBe(false)
				t.expect(run.present[stayer]).toBe(true)
				t.expect(run:hasMove(leaver)).toBe(false)
				t.expect(run:hasMove(stayer)).toBe(true)

				for slot = 1, 4 do
					t.expect(run:canPlace(leaver, slot, 0, 0)).toBe(false)
					t.expect(run:place(leaver, slot, 0, 0)).toBe(nil)
				end
				for slot = 1, 3 do
					t.expect(mustPlace(run, stayer, slot, slot, 0).refilled).toBe(false)
				end
				t.expect(mustPlace(run, stayer, 4, 4, 0).refilled).toBe(true)
				t.expect(run.contribution[leaver]).toBe(0)
				t.expect(run.contribution[stayer]).toBe(run.session.score)
			end
		end)

		t.it("lets a leaver go only once", function()
			local run = newRun({ FOUR_DOTS })
			t.expect(run:release(2)).toBe(true)
			t.expect(run:release(2)).toBe(false)
			t.expect(run.present).toEqual({ true, false })
			t.expect(run:release(1)).toBe(true)
			t.expect(run.present).toEqual({ false, false })
			t.expect(run:release(1)).toBe(false)
		end)

		t.it("stops counting the score once the partner has left", function()
			for leaver = 1, 2 do
				local stayer = 3 - leaver
				local run = newRun({ FOUR_DOTS, FOUR_DOTS })
				mustPlace(run, 1, 1, 0, 0)
				mustPlace(run, 2, 3, 1, 0)
				local atLeave = run.session.score
				t.expect(atLeave > 0).toBe(true)
				t.expect(run.countedScore).toBe(atLeave)

				run:release(leaver)
				t.expect(run.countedScore).toBe(atLeave)
				mustPlace(run, stayer, 2, 2, 0)
				mustPlace(run, stayer, 4, 3, 0)
				t.expect(run.session.score > atLeave).toBe(true)
				t.expect(run.countedScore).toBe(atLeave)
				t.expect(run.contribution[1] + run.contribution[2]).toBe(run.session.score)

				-- The last player leaving doesn't move it either.
				run:release(stayer)
				t.expect(run.countedScore).toBe(atLeave)
			end
		end)

		t.it("is not over while the partner's pieces still fit, and a clear can free the other player's", function()
			local run = newRun({ { "O2", "O2", "Dot", "Dot" } }, Helpers.boardFromRows(BLOCKED_UNTIL_A_CLEAR))
			t.expect(run.session.isOver).toBe(false)
			t.expect(run:hasMove(1)).toBe(false)
			t.expect(run:hasMove(2)).toBe(true)

			local cleared = mustPlace(run, 2, 3, 7, 0)
			t.expect(#cleared.clearedRows).toBe(1)
			t.expect(cleared.isOver).toBe(false)
			t.expect(run:hasMove(1)).toBe(true)
			mustPlace(run, 1, 1, 0, 0)
		end)

		t.it("is over once no piece of either player fits", function()
			local run = newRun({ { "O2", "O2", "Dot", "Dot" } }, Helpers.boardFromRows(CHECKERBOARD))
			t.expect(run.session.isOver).toBe(false)
			t.expect(mustPlace(run, 2, 3, 1, 0).isOver).toBe(false)
			t.expect(mustPlace(run, 2, 4, 3, 0).isOver).toBe(true)
			t.expect(run.session.isOver).toBe(true)
			t.expect(run:hasMove(1)).toBe(false)
			t.expect(run:hasMove(2)).toBe(false)
			t.expect(run:place(1, 1, 0, 0)).toBe(nil)
		end)

		t.it("gives the player who stays the leaver's pieces when their own do not fit", function()
			local run = newRun({ { "O2", "O2", "Dot", "Dot" } }, Helpers.boardFromRows(CHECKERBOARD))
			t.expect(run:hasMove(1)).toBe(false)
			run:release(2)
			t.expect(run:hasMove(1)).toBe(true)
			mustPlace(run, 1, 3, 1, 0)
		end)

		t.it("round-trips through a snapshot, after a player has left, and keeps playing identically", function()
			local sets = { { "Dot", "O2", "I3_H", "I2_V" }, { "T4_1", "L3_1", "I2_V", "Dot" } }
			local run = newRun(sets, Helpers.boardFromRows({ "######.." }))
			mustPlace(run, 1, 1, 6, 0)
			mustPlace(run, 2, 3, 3, 3)
			run:release(2)
			mustPlace(run, 1, 4, 7, 5)
			local snapshot = run:snapshot()
			t.expect(snapshot.present).toEqual({ true, false })
			t.expect(snapshot.countedScore < run.session.score).toBe(true)

			local copy = CoopSession.fromSnapshot(snapshot, (Helpers.queueSource({ sets[2] })))
			t.expect(copy:snapshot()).toEqual(snapshot)
			t.expect(copy.contribution).toEqual(run.contribution)

			local expected = mustPlace(run, 1, 2, 0, 6)
			local actual = mustPlace(copy, 1, 2, 0, 6)
			t.expect(actual.points).toBe(expected.points)
			t.expect(actual.refilled).toBe(true)
			t.expect(copy:snapshot()).toEqual(run:snapshot())
			t.expect(copy:place(2, 1, 0, 0)).toBe(nil) -- the leaver is still out in the copy
		end)

		t.it("refuses snapshots that are not a Co-op run", function()
			local snapshot = newRun({ FOUR_DOTS }):snapshot()
			local threePieces = table.clone(snapshot)
			threePieces.game = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot" } }))):snapshot()
			local oneSeat = table.clone(snapshot)
			oneSeat.present = { true }
			local oneShare = table.clone(snapshot)
			oneShare.contribution = { 0 }
			local noScore = table.clone(snapshot)
			noScore.countedScore = nil :: any
			local textShare = table.clone(snapshot)
			textShare.contribution = { "5" :: any, 0 }
			for _, broken in { threePieces, oneSeat, oneShare, noScore, textShare } do
				t.expect(function()
					CoopSession.fromSnapshot(broken, noSet)
				end).toThrow()
			end
		end)
	end)
end
