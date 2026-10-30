--!strict
-- A greedy bot plays whole games with the real generator, checking invariants after every move.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local GameSession = require("../src/shared/GameSession")
local Generator = require("../src/shared/Generator")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local GAMES = 200
local MAX_MOVES = 2000
local SIZE = Config.GRID_SIZE

-- How many rows and columns placing the piece would complete (the move must be valid).
local function linesCompleted(board: Board.Board, piece: Pieces.Piece, x: number, y: number): number
	local covered = {}
	for _, cell in piece.cells do
		covered[Board.index(x + cell.x, y + cell.y)] = true
	end
	local function isFilled(col: number, row: number): boolean
		local index = Board.index(col, row)
		return board.cells[index] ~= 0 or covered[index] == true
	end
	local count = 0
	for row = y, y + piece.height - 1 do
		local full = true
		for col = 0, SIZE - 1 do
			if not isFilled(col, row) then
				full = false
				break
			end
		end
		if full then
			count += 1
		end
	end
	for col = x, x + piece.width - 1 do
		local full = true
		for row = 0, SIZE - 1 do
			if not isFilled(col, row) then
				full = false
				break
			end
		end
		if full then
			count += 1
		end
	end
	return count
end

-- Edges of the piece that touch a wall or a filled cell; higher means a tidier fit.
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function contact(board: Board.Board, piece: Pieces.Piece, x: number, y: number): number
	local own = {}
	for _, cell in piece.cells do
		own[`{x + cell.x},{y + cell.y}`] = true
	end
	local count = 0
	for _, cell in piece.cells do
		for _, offset in NEIGHBOURS do
			local nx, ny = x + cell.x + offset[1], y + cell.y + offset[2]
			if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE then
				count += 1
			elseif not own[`{nx},{ny}`] and Board.get(board, nx, ny) ~= 0 then
				count += 1
			end
		end
	end
	return count
end

-- Picks the move that completes the most lines, then the tidiest fit; ties are broken at random.
local function chooseMove(session: GameSession.GameSession, rng: Rng.Rng): { number }?
	local best: { number }? = nil
	local bestValue, ties = -1, 0
	for slot, piece in session.tray do
		if not piece then
			continue
		end
		for y = 0, SIZE - piece.height do
			for x = 0, SIZE - piece.width do
				if Board.canPlace(session.board, piece, x, y) then
					local value = linesCompleted(session.board, piece, x, y) * 100 + contact(session.board, piece, x, y)
					if value > bestValue then
						best, bestValue, ties = { slot, x, y }, value, 1
					elseif value == bestValue then
						ties += 1
						if rng:nextInt(1, ties) == 1 then
							best = { slot, x, y }
						end
					end
				end
			end
		end
	end
	return best
end

local function anyTrayPieceFits(session: GameSession.GameSession): boolean
	for _, piece in session.tray do
		if piece and Board.hasAnyPlacement(session.board, piece) then
			return true
		end
	end
	return false
end

return function(t: TestKit.TestKit)
	t.describe("Simulation", function()
		t.it(`plays {GAMES} greedy games without breaking an invariant`, function()
			local started = os.clock()
			local totalScore, totalMoves, capped = 0, 0, 0
			local past1500, past5000, revives = 0, 0, 0

			for seed = 1, GAMES do
				local session = GameSession.new(Generator.newSource(Rng.new(seed)))
				local botRng = Rng.new(seed + 100000)
				local mayRevive = seed % 4 == 0

				while true do
					if session.isOver then
						if mayRevive and session:revive() then
							revives += 1
							continue
						end
						break
					end
					if session.moveCount >= MAX_MOVES then
						capped += 1
						break
					end

					local move = chooseMove(session, botRng)
					t.expect(move).toBeTruthy() -- not over, so something must fit
					assert(move)
					local scoreBefore = session.score
					local result = session:place(move[1], move[2], move[3])
					t.expect(result).toBeTruthy()

					t.expect(session.score >= scoreBefore).toBe(true)
					t.expect(Board.findCompleteLines(session.board)).toEqual({ rows = {}, cols = {} })
					t.expect(session.isOver).toBe(not anyTrayPieceFits(session))
				end

				t.expect(session.revivesUsed <= Config.MAX_REVIVES_PER_RUN).toBe(true)
				totalScore += session.score
				totalMoves += session.moveCount
				if session.score >= 1500 then
					past1500 += 1
				end
				if session.score >= 5000 then
					past5000 += 1
				end
			end

			print(
				string.format(
					"    bot: avg score %d, avg moves %d, reached 1500: %d%%, reached 5000: %d%%, revives %d, capped %d, %.1fs",
					totalScore // GAMES,
					totalMoves // GAMES,
					past1500 * 100 // GAMES,
					past5000 * 100 // GAMES,
					revives,
					capped,
					os.clock() - started
				)
			)
		end)
	end)
end
