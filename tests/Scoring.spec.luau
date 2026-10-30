--!strict
local Scoring = require("../src/shared/Scoring")
local TestKit = require("./TestKit")

-- Plays a list of moves ({ cells, lines }) from a fresh combo; returns each move's score.
local function play(moves: { { number } }): { Scoring.MoveScore }
	local state = Scoring.newCombo()
	local results = {}
	for _, move in moves do
		local result = Scoring.scoreMove(state, move[1], move[2], false)
		table.insert(results, result)
		state = result.nextCombo
	end
	return results
end

return function(t: TestKit.TestKit)
	t.describe("Scoring", function()
		t.it("gives one point per placed cell", function()
			local result = Scoring.scoreMove(Scoring.newCombo(), 4, 0, false)
			t.expect(result.total).toBe(4)
			t.expect(result.clearPoints).toBe(0)
			t.expect(result.nextCombo).toEqual({ combo = 0, movesSinceClear = 1 })
		end)

		t.it("uses the clear table and caps it at six lines", function()
			local expected = { 10, 30, 60, 100, 150, 210, 210 }
			for lines, points in expected do
				t.expect(Scoring.clearBase(lines)).toBe(points)
			end
			t.expect(Scoring.clearBase(0)).toBe(0)
		end)

		t.it("starts a combo on the first clear without a multiplier", function()
			local result = Scoring.scoreMove(Scoring.newCombo(), 3, 1, false)
			t.expect(result.clearPoints).toBe(10)
			t.expect(result.total).toBe(13)
			t.expect(result.nextCombo).toEqual({ combo = 1, movesSinceClear = 0 })
		end)

		t.it("raises the multiplier by 0.5 per consecutive clear", function()
			local results = play({ { 1, 1 }, { 1, 1 }, { 1, 1 }, { 1, 2 } })
			t.expect(results[1].clearPoints).toBe(10) -- x1
			t.expect(results[2].clearPoints).toBe(15) -- x1.5
			t.expect(results[3].clearPoints).toBe(20) -- x2
			t.expect(results[4].clearPoints).toBe(75) -- 30 x2.5
		end)

		t.it("keeps the combo through two misses and drops it on the third", function()
			local kept = play({ { 1, 1 }, { 1, 0 }, { 1, 0 }, { 1, 1 } })
			t.expect(kept[4].nextCombo.combo).toBe(2)
			t.expect(kept[4].clearPoints).toBe(15)

			local dropped = play({ { 1, 1 }, { 1, 0 }, { 1, 0 }, { 1, 0 }, { 1, 1 } })
			t.expect(dropped[4].nextCombo.combo).toBe(0)
			t.expect(dropped[5].nextCombo.combo).toBe(1)
			t.expect(dropped[5].clearPoints).toBe(10)
		end)

		t.it("adds the board clear bonus only on a clearing move", function()
			t.expect(Scoring.scoreMove(Scoring.newCombo(), 2, 1, true).bonusPoints).toBe(300)
			t.expect(Scoring.scoreMove(Scoring.newCombo(), 2, 0, true).bonusPoints).toBe(0)
		end)

		t.it("does not change the state it is given", function()
			local state = Scoring.newCombo()
			Scoring.scoreMove(state, 3, 2, false)
			t.expect(state).toEqual({ combo = 0, movesSinceClear = 0 })
		end)
	end)
end
