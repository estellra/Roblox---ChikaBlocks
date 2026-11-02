--!strict
local Board = require("../src/shared/Board")
local GameSession = require("../src/shared/GameSession")
local Helpers = require("./Helpers")
local Pieces = require("../src/shared/Pieces")
local TestKit = require("./TestKit")

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

return function(t: TestKit.TestKit)
	t.describe("GameSession", function()
		t.it("deals the first set when created", function()
			local source, reasons = Helpers.queueSource({ { "Dot", "O2", "I3_H" } })
			local session = GameSession.new(source)
			t.expect(Helpers.ids(session.tray)).toEqual({ "Dot", "O2", "I3_H" })
			t.expect(reasons).toEqual({ "Normal" })
			t.expect(session.score).toBe(0)
			t.expect(session.isOver).toBe(false)
		end)

		t.it("places a piece, scores it and marks the slot as used", function()
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "O2", "I3_H" } })))
			local result = session:place(2, 3, 4)
			t.expect(result).toBeTruthy()
			assert(result)
			t.expect(result.slot).toBe(2)
			t.expect(result.piece.id).toBe("O2")
			t.expect(result.points).toBe(4)
			t.expect(result.refilled).toBe(false)
			t.expect(result.isOver).toBe(false)
			t.expect(Helpers.ids(session.tray)).toEqual({ "Dot", false, "I3_H" })
			t.expect(session.score).toBe(4)
			t.expect(session.moveCount).toBe(1)
			t.expect(Board.get(session.board, 4, 5)).toBe(Pieces.BY_ID.O2.color)
		end)

		t.it("rejects malformed moves without changing anything", function()
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "O2", "I3_H" } })))
			local cases: { { any } } = {
				{ "1", 0, 0 },
				{ 0, 0, 0 },
				{ 4, 0, 0 },
				{ 1.5, 0, 0 },
				{ 0 / 0, 0, 0 },
				{ math.huge, 0, 0 },
				{ {}, 0, 0 },
				{ 1, "0", 0 },
				{ 1, 0.5, 0 },
				{ 1, 0 / 0, 0 },
				{ 1, math.huge, 0 },
				{ 1, -1, 0 },
				{ 1, 8, 0 },
				{ 3, 6, 0 }, -- I3_H would stick out on the right
			}
			for _, case in cases do
				t.expect(session:place(case[1], case[2], case[3])).toBe(nil)
			end
			t.expect(session:place(nil, nil, nil)).toBe(nil)
			t.expect(session:place(1, 0, nil)).toBe(nil)
			t.expect(session.score).toBe(0)
			t.expect(session.moveCount).toBe(0)
			t.expect(Helpers.ids(session.tray)).toEqual({ "Dot", "O2", "I3_H" })
			t.expect(Board.isEmpty(session.board)).toBe(true)
		end)

		t.it("refuses a slot that was already played", function()
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot" } })))
			t.expect(session:place(1, 0, 0)).toBeTruthy()
			t.expect(session:place(1, 5, 5)).toBe(nil)
		end)

		t.it("deals a new set after the last slot is played", function()
			local source, reasons = Helpers.queueSource({ { "Dot", "Dot", "Dot" }, { "O2", "T4_1", "I4_V" } })
			local session = GameSession.new(source)
			t.expect((session:place(1, 0, 0) :: any).refilled).toBe(false)
			t.expect((session:place(3, 2, 2) :: any).refilled).toBe(false)
			t.expect((session:place(2, 4, 4) :: any).refilled).toBe(true)
			t.expect(Helpers.ids(session.tray)).toEqual({ "O2", "T4_1", "I4_V" })
			t.expect(reasons).toEqual({ "Normal", "Normal" })
		end)

		t.it("clears lines, scores the clear and the board-clear bonus", function()
			local board = Helpers.boardFromRows({ "#######." })
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot" } })), board)
			local result = session:place(1, 7, 0)
			assert(result)
			t.expect(result.clearedRows).toEqual({ 0 })
			t.expect(result.clearedCols).toEqual({})
			t.expect(result.cellsCleared).toBe(8)
			t.expect(result.boardCleared).toBe(true)
			t.expect(result.points).toBe(1 + 10 + 300)
			t.expect(result.combo).toBe(1)
			t.expect(Board.isEmpty(session.board)).toBe(true)
			-- The board passed in is copied, not modified.
			t.expect(Board.get(board, 0, 0)).toBe(1)
		end)

		t.it("ends the game once nothing left in the tray fits", function()
			local session =
				GameSession.new((Helpers.queueSource({ { "O2", "I2_H", "Dot" } })), Helpers.boardFromRows(CHECKERBOARD))
			t.expect(session.isOver).toBe(false)
			local result = session:place(3, 1, 0)
			assert(result)
			t.expect(result.isOver).toBe(true)
			t.expect(session.isOver).toBe(true)
			t.expect(session:place(1, 1, 2)).toBe(nil)
		end)

		t.it("can be over as soon as it starts", function()
			local session =
				GameSession.new((Helpers.queueSource({ { "O2", "O2", "I2_V" } })), Helpers.boardFromRows(CHECKERBOARD))
			t.expect(session.isOver).toBe(true)
		end)

		t.it("revives only after game over, as often as asked", function()
			local source, reasons = Helpers.queueSource({
				{ "O2", "O2", "O2" },
				{ "O2", "Dot", "Dot" },
				{ "Dot", "Dot", "Dot" },
				{ "Dot", "Dot", "O2" },
			})
			local session = GameSession.new(source, Helpers.boardFromRows(CHECKERBOARD))
			t.expect(session.isOver).toBe(true)
			session.combo = { combo = 3, movesSinceClear = 1 }

			t.expect(session:revive()).toBe(true)
			for y = 2, 5 do
				for x = 2, 5 do
					t.expect(Board.get(session.board, x, y)).toBe(0)
				end
			end
			t.expect(Board.get(session.board, 0, 0)).toBe(1)
			t.expect(Board.get(session.board, 7, 7)).toBe(1)
			t.expect(session.revivesUsed).toBe(1)
			t.expect(session.combo).toEqual({ combo = 0, movesSinceClear = 0 })
			t.expect(session.isOver).toBe(false)
			t.expect(reasons).toEqual({ "Normal", "Revive" })

			t.expect(session:revive()).toBe(false) -- not over
			session.isOver = true -- pretend the run ended again
			t.expect(session:revive()).toBe(true)
			t.expect(session.revivesUsed).toBe(2)
			session.isOver = true
			t.expect(session:revive()).toBe(true) -- the number of revives is not limited
			t.expect(session.revivesUsed).toBe(3)
			t.expect(#reasons).toBe(4)
		end)

		t.it("waits for a set when the source has none, then plays on after receiveSet", function()
			local dealt = false
			local function source(): { Pieces.Piece }?
				if dealt then
					return nil
				end
				dealt = true
				return { Pieces.BY_ID.Dot, Pieces.BY_ID.Dot, Pieces.BY_ID.Dot }
			end
			local session = GameSession.new(source)
			session:place(1, 0, 0)
			session:place(2, 2, 2)
			local last = session:place(3, 4, 4)
			assert(last)
			t.expect(last.refilled).toBe(false)
			t.expect(last.awaitingSet).toBe(true)
			t.expect(last.isOver).toBe(false)
			t.expect(Helpers.ids(session.tray)).toEqual({ false, false, false })
			t.expect(session:canPlace(1, 6, 6)).toBe(false)

			local O2 = Pieces.BY_ID.O2
			t.expect(session:receiveSet({ O2, O2, O2 })).toBe(true)
			t.expect(session.awaitingSet).toBe(false)
			t.expect(Helpers.ids(session.tray)).toEqual({ "O2", "O2", "O2" })
			t.expect(session:receiveSet({ O2, O2, O2 })).toBe(false) -- not awaiting any more
		end)

		t.it("starts out awaiting when the source has nothing yet", function()
			local session = GameSession.new(function(): { Pieces.Piece }?
				return nil
			end)
			t.expect(session.awaitingSet).toBe(true)
			t.expect(session.isOver).toBe(false)
			t.expect(session:receiveSet({ Pieces.BY_ID.Dot })).toBe(false) -- wrong count
		end)

		t.it("ends the game when a received set doesn't fit", function()
			local session = GameSession.new(function(): { Pieces.Piece }?
				return nil
			end, Helpers.boardFromRows(CHECKERBOARD))
			local O2 = Pieces.BY_ID.O2
			t.expect(session:receiveSet({ O2, O2, O2 })).toBe(true)
			t.expect(session.isOver).toBe(true)
		end)

		t.it("round-trips through a snapshot and keeps playing identically", function()
			local sets = { { "Dot", "O2", "I3_H" }, { "T4_1", "L3_1", "I2_V" } }
			local session = GameSession.new((Helpers.queueSource(sets)), Helpers.boardFromRows({ "######.." }))
			session:place(1, 6, 0) -- row 0 now has 7 of 8 cells
			session:place(2, 3, 3)
			local copy = GameSession.fromSnapshot(session:snapshot(), (Helpers.queueSource({ sets[2] })))
			t.expect(copy:snapshot()).toEqual(session:snapshot())

			session:place(3, 0, 6)
			copy:place(3, 0, 6)
			t.expect(copy:snapshot()).toEqual(session:snapshot())
			t.expect(session.score).toBe(copy.score)
		end)

		t.it("refuses snapshots with a bad board or unknown pieces", function()
			local snapshot = GameSession.new((Helpers.queueSource({ { "Dot", "Dot", "Dot" } }))):snapshot()
			local badCells = table.clone(snapshot)
			badCells.cells = { 0, 0 }
			local badPiece = table.clone(snapshot)
			badPiece.tray = { "NotAPiece", false, false }
			local noSet = function(): { Pieces.Piece }?
				return nil
			end
			t.expect(function()
				GameSession.fromSnapshot(badCells, noSet)
			end).toThrow()
			t.expect(function()
				GameSession.fromSnapshot(badPiece, noSet)
			end).toThrow()
		end)

		t.it("charges the first turn of a piece (free, then bought) and lets it turn freely after that", function()
			local session = GameSession.new((Helpers.queueSource({ { "T4_1", "I3_H", "Dot" } })))
			t.expect(session.freeRotations).toBe(1)

			local first = session:rotate(1, 0)
			assert(first)
			t.expect(first.charged).toBe("free")
			t.expect(first.piece.id).toBe("T4_4")
			t.expect(Helpers.ids(session.tray)).toEqual({ "T4_4", "I3_H", "Dot" })
			t.expect(session.freeRotations).toBe(0)

			local again = session:rotate(1, 0) -- the piece is unlocked now
			assert(again)
			t.expect(again.charged).toBe(nil)
			t.expect(again.piece.id).toBe("T4_2")

			t.expect(session:rotate(2, 0)).toBe(nil) -- nothing free left and nothing bought
			t.expect(session.tray[2]).toBe(Pieces.BY_ID.I3_H)

			local bought = session:rotate(2, 3)
			assert(bought)
			t.expect(bought.charged).toBe("paid")
			t.expect(bought.piece.id).toBe("I3_V")
			t.expect(session.freeRotations).toBe(0)
			t.expect(session.moveCount).toBe(0)
			t.expect(session.score).toBe(0)
		end)

		t.it("refuses to turn a piece that looks the same, a missing piece, a bad slot or a finished run", function()
			local session = GameSession.new((Helpers.queueSource({ { "Dot", "O2", "I3_H" } })))
			session:place(3, 0, 0)
			local before = session:snapshot()
			local cases: { { any } } = {
				{ 1, 5 }, -- dot
				{ 2, 5 }, -- square
				{ 3, 5 }, -- already placed
				{ 0, 5 },
				{ 4, 5 },
				{ 1.5, 5 },
				{ "1", 5 },
				{ 0 / 0, 5 },
				{ {}, 5 },
			}
			for _, case in cases do
				t.expect(session:rotate(case[1], case[2])).toBe(nil)
			end
			t.expect(session:snapshot()).toEqual(before)

			local over = GameSession.new(
				(Helpers.queueSource({ { "I2_H", "I2_H", "I2_H" } })),
				Helpers.boardFromRows(CHECKERBOARD)
			)
			t.expect(over.isOver).toBe(true)
			t.expect(over:rotate(1, 5)).toBe(nil)
		end)

		t.it("doesn't take a bought rotation from anything but a positive number", function()
			local session = GameSession.new((Helpers.queueSource({ { "I2_H", "I3_H", "L3_1" } })))
			session:rotate(1, 0) -- spends the free one
			for _, paid in { -1, 0, "5", true, {}, 0 / 0 } do
				t.expect(session:rotate(2, paid)).toBe(nil)
			end
			t.expect(session.unlocked[2]).toBe(false)
		end)

		t.it("locks the pieces again when they are placed, when a set is dealt and after a revive", function()
			local session =
				GameSession.new((Helpers.queueSource({ { "T4_1", "I3_H", "Dot" }, { "L3_1", "I2_H", "Dot" } })))
			session:rotate(1, 0)
			t.expect(session.unlocked).toEqual({ true, false, false })
			session:place(1, 0, 0)
			t.expect(session.unlocked).toEqual({ false, false, false })
			session:rotate(2, 1) -- bought
			t.expect(session.unlocked).toEqual({ false, true, false })
			session:place(2, 0, 5)
			session:place(3, 7, 7) -- the tray runs out: a new set
			t.expect(Helpers.ids(session.tray)).toEqual({ "L3_1", "I2_H", "Dot" })
			t.expect(session.unlocked).toEqual({ false, false, false })
			t.expect(session.freeRotations).toBe(0) -- free turns are per run, not per set
		end)

		t.it("counts a paid-for piece as playable in any turn when deciding game over", function()
			local board = {
				"..#.#.#.",
				".#.#.#.#",
				"..#.#.#.",
				".#.#.#.#",
				"#.#.#.#.",
				".#.#.#.#",
				"#.#.#.#.",
				".#.#.#.#",
			}
			local function newSession()
				return GameSession.new(
					(Helpers.queueSource({ { "I3_H", "Dot", "Dot" }, { "Dot", "Dot", "Dot" } })),
					Helpers.boardFromRows(board)
				)
			end

			local plain = newSession()
			plain:place(2, 6, 7)
			plain:place(3, 4, 7)
			t.expect(plain.isOver).toBe(true) -- the bar doesn't fit and was never turned

			local paid = newSession()
			paid:rotate(1, 0) -- now vertical
			paid:rotate(1, 0) -- and horizontal again, where it doesn't fit
			paid:place(2, 6, 7)
			paid:place(3, 4, 7)
			t.expect(paid.isOver).toBe(false)
			t.expect(paid:canPlace(1, 0, 0)).toBe(false)
			paid:rotate(1, 0)
			t.expect(paid.tray[1]).toBe(Pieces.BY_ID.I3_V)
			t.expect(paid:place(1, 0, 0)).toBeTruthy()
		end)

		t.it("keeps the rotation state through a snapshot", function()
			local sets = { { "T4_1", "I3_H", "Dot" }, { "L3_1", "I2_H", "Dot" } }
			local session = GameSession.new((Helpers.queueSource(sets)))
			session:rotate(1, 0)
			local copy = GameSession.fromSnapshot(session:snapshot(), (Helpers.queueSource({ sets[2] })))
			t.expect(copy:snapshot()).toEqual(session:snapshot())
			t.expect(copy.freeRotations).toBe(0)
			t.expect(copy.unlocked).toEqual({ true, false, false })
			t.expect(copy:rotate(1, 0)).toBeTruthy() -- still turns freely
			t.expect(copy:rotate(2, 0)).toBe(nil) -- and still has nothing free left
		end)

		t.it("throws when the set source deals the wrong number of pieces", function()
			t.expect(function()
				GameSession.new((Helpers.queueSource({ { "Dot", "Dot" } })))
			end).toThrow()
		end)
	end)
end
