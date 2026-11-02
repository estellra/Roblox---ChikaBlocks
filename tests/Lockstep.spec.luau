--!strict
-- The client predicts every move (and every turn of a piece) on its own session and only receives new sets
-- from the server. If both sides apply the same actions they must stay identical; this plays whole games to
-- prove it.
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
local SET_SIZE = Config.PIECES_PER_SET

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
			local totalMoves, refills, turns = 0, 0, 0
			for seed = 1, GAMES do
				local server = GameSession.new(Generator.newSource(Rng.new(seed)))
				local client = GameSession.fromSnapshot(server:snapshot(), noSet)
				local rng = Rng.new(seed + 50000)
				local greedy = seed % 4 == 0
				local bought = 3 -- rotations the player has bought, spent as the server says

				-- Both sides turn the piece in `slot`; they must agree on whether it worked and what it cost.
				local function turn(slot: number)
					local predicted = client:rotate(slot, bought)
					local actual = server:rotate(slot, bought)
					t.expect(predicted == nil).toBe(actual == nil)
					if predicted and actual then
						turns += 1
						t.expect(predicted.charged).toBe(actual.charged)
						t.expect(predicted.piece).toBe(actual.piece)
						if actual.charged == "paid" then
							bought -= 1
						end
					end
					t.expect(client:snapshot()).toEqual(server:snapshot())
				end

				while not server.isOver and server.moveCount < MAX_MOVES do
					if rng:nextFloat() < 0.3 then
						turn(rng:nextInt(1, SET_SIZE))
					end
					local move = chooseMove(client, rng, greedy)
					if not move then
						-- Not over, so a piece that was paid for fits in another turn.
						for slot = 1, SET_SIZE do
							for _ = 1, 3 do
								local piece = client.tray[slot]
								if
									piece
									and client.unlocked[slot]
									and not Board.hasAnyPlacement(client.board, piece)
								then
									turn(slot)
								end
							end
						end
						move = chooseMove(client, rng, greedy)
					end
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
			t.expect(turns > 0).toBe(true)
			print(
				string.format(
					"    lockstep: %d moves, %d sets delivered, %d turns, no divergence",
					totalMoves,
					refills,
					turns
				)
			)
		end)
	end)
end
