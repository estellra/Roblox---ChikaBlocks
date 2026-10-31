--!strict
-- The client predicts every move on its own session and only receives new sets from the server. If both
-- sides apply the same moves they must stay identical; this plays whole games to prove it.
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

local function noSet(_board: Board.Board, _score: number, _reason: Generator.DealReason): { Pieces.Piece }?
	return nil
end

-- A random valid move, or (when `greedy`) the one clearing the most lines.
local function chooseMove(session: GameSession.GameSession, rng: Rng.Rng, greedy: boolean): { number }?
	local moves: { { number } } = {}
	local best: { number }? = nil
	local bestLines = -1
	for slot, piece in session.tray do
		if not piece then
			continue
		end
		for y = 0, SIZE - piece.height do
			for x = 0, SIZE - piece.width do
				if session:canPlace(slot, x, y) then
					table.insert(moves, { slot, x, y })
					if greedy then
						local lines = Board.previewLines(session.board, piece, x, y)
						if #lines.rows + #lines.cols > bestLines then
							best, bestLines = { slot, x, y }, #lines.rows + #lines.cols
						end
					end
				end
			end
		end
	end
	if greedy then
		return best
	end
	return if #moves > 0 then moves[rng:nextInt(1, #moves)] else nil
end

return function(t: TestKit.TestKit)
	t.describe("Lockstep", function()
		t.it(`keeps client and server identical over {GAMES} games`, function()
			local totalMoves, refills = 0, 0
			for seed = 1, GAMES do
				local server = GameSession.new(Generator.newSource(Rng.new(seed)))
				local client = GameSession.fromSnapshot(server:snapshot(), noSet)
				local rng = Rng.new(seed + 50000)
				local greedy = seed % 4 == 0

				while not server.isOver and server.moveCount < MAX_MOVES do
					local move = chooseMove(client, rng, greedy)
					t.expect(move).toBeTruthy()
					assert(move)
					local predicted = client:place(move[1], move[2], move[3])
					local actual = server:place(move[1], move[2], move[3])
					t.expect(predicted ~= nil and actual ~= nil).toBe(true)
					assert(predicted and actual)

					if actual.refilled then
						refills += 1
						t.expect(predicted.awaitingSet).toBe(true)
						t.expect(client:receiveSet(server.tray :: { Pieces.Piece })).toBe(true)
					else
						t.expect(predicted.awaitingSet).toBe(false)
					end
					t.expect(predicted.points).toBe(actual.points)
					t.expect(client:snapshot()).toEqual(server:snapshot())
				end
				totalMoves += server.moveCount
			end
			print(string.format("    lockstep: %d moves, %d sets delivered, no divergence", totalMoves, refills))
		end)
	end)
end
