--!strict
-- A greedy bot plays whole games solo (three pieces per set) and as a Co-op pair (four pieces, two players) with
-- the real generator, to see how much harder Co-op is. Also plays runs where one player leaves, and checks that a
-- client copy of a Co-op run, fed the same moves, stays identical to the server's.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local CoopSession = require("../src/shared/CoopSession")
local GameSession = require("../src/shared/GameSession")
local Generator = require("../src/shared/Generator")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local GAMES = 200
local MIRRORED_GAMES = 100
local MAX_MOVES = 2000
local SIZE = Config.GRID_SIZE

-- What Config.COOP.GENERATOR is tuned for: the bot's median Co-op game lasts as many moves as its median solo
-- game, give or take this share.
local LENGTH_TOLERANCE = 0.3

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function noSet(_board: Board.Board, _score: number, _reason: Generator.DealReason): { Pieces.Piece }?
	return nil
end

-- Edges of the piece that touch a wall or a filled cell; higher means a tidier fit.
local function contact(board: Board.Board, piece: Pieces.Piece, x: number, y: number): number
	local own: { [string]: boolean } = {}
	for _, cell in piece.cells do
		own[`{x + cell.x},{y + cell.y}`] = true
	end
	local count = 0
	for _, cell in piece.cells do
		for _, offset in NEIGHBOURS do
			local nx, ny = x + cell.x + offset[1], y + cell.y + offset[2]
			local outside = nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE
			if outside or (not own[`{nx},{ny}`] and Board.get(board, nx, ny) ~= 0) then
				count += 1
			end
		end
	end
	return count
end

-- Picks the move (over every piece in the tray) that completes the most lines, then the tidiest fit; ties are
-- broken at random. The same bot as Simulation.spec, so solo and Co-op numbers are comparable.
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
					local lines = Board.previewLines(session.board, piece, x, y)
					local value = (#lines.rows + #lines.cols) * 100 + contact(session.board, piece, x, y)
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

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[(#sorted + 1) // 2]
end

-- Percentage of the values that reach `threshold`.
local function percentAtLeast(values: { number }, threshold: number): number
	local count = 0
	for _, value in values do
		if value >= threshold then
			count += 1
		end
	end
	return count * 100 / #values
end

-- Seat that places a move: the owner of the slot, or whoever is left once the other player has gone.
local function seatFor(run: CoopSession.CoopSession, slot: number): number
	if run.present[1] and run.present[2] then
		return CoopSession.seatOf(slot) or error(`slot {slot} has no seat`)
	end
	return if run.present[1] then 1 else 2
end

return function(t: TestKit.TestKit)
	t.describe("Co-op simulation", function()
		t.it(`plays {GAMES} bot games solo and in Co-op, and Co-op lasts about as long`, function()
			local soloMoves: { number }, soloScores: { number } = {}, {}
			for seed = 1, GAMES do
				local session = GameSession.new(Generator.newSource(Rng.new(seed)))
				local rng = Rng.new(seed + 100000)
				while not session.isOver and session.moveCount < MAX_MOVES do
					local move = chooseMove(session, rng)
					assert(move, "something fits, so the bot has a move")
					session:place(move[1], move[2], move[3])
				end
				table.insert(soloMoves, session.moveCount)
				table.insert(soloScores, session.score)
			end

			local coopMoves: { number }, coopScores: { number } = {}, {}
			local dealSeconds: { number } = {}
			local capped = 0
			for seed = 1, GAMES do
				local source = CoopSession.newSource(Rng.new(seed))
				local run = CoopSession.new(function(board: Board.Board, score: number, reason: Generator.DealReason)
					local started = os.clock()
					local set = source(board, score, reason)
					table.insert(dealSeconds, os.clock() - started)
					return set
				end)
				local session = run.session
				local rng = Rng.new(seed + 100000)
				while not session.isOver and session.moveCount < MAX_MOVES do
					local move = chooseMove(session, rng)
					assert(move, "something fits, so the bot has a move")
					local scoreBefore = session.score
					t.expect(run:place(seatFor(run, move[1]), move[1], move[2], move[3])).toBeTruthy()

					t.expect(session.score >= scoreBefore).toBe(true)
					t.expect(Board.findCompleteLines(session.board)).toEqual({ rows = {}, cols = {} })
					t.expect(session.isOver).toBe(not anyTrayPieceFits(session))
					t.expect(run.contribution[1] + run.contribution[2]).toBe(session.score)
					t.expect(run.countedScore).toBe(session.score)
				end
				if session.moveCount >= MAX_MOVES then
					capped += 1
				end
				table.insert(coopMoves, session.moveCount)
				table.insert(coopScores, session.score)
			end

			local soloMedian, coopMedian = median(soloMoves), median(coopMoves)
			local totalDeal, worstDeal = 0, 0
			for _, seconds in dealSeconds do
				totalDeal += seconds
				worstDeal = math.max(worstDeal, seconds)
			end
			local function report(name: string, moves: { number }, scores: { number })
				print(
					string.format(
						"    bot, no revives, %s: median %d moves / score %d, reached 1500: %.0f%%, reached 5000: %.0f%%",
						name,
						median(moves),
						median(scores),
						percentAtLeast(scores, 1500),
						percentAtLeast(scores, 5000)
					)
				)
			end
			report("solo", soloMoves, soloScores)
			report("Co-op", coopMoves, coopScores)
			print(string.format("    Co-op games last %.0f%% of solo's moves (median)", coopMedian * 100 / soloMedian))
			print(
				string.format(
					"    Co-op deals in those games: %d, avg %.3f ms, worst %.3f ms",
					#dealSeconds,
					totalDeal / #dealSeconds * 1000,
					worstDeal * 1000
				)
			)

			t.expect(capped * 10 <= GAMES).toBe(true) -- the medians mean little if most games hit the move cap
			t.expect(coopMedian >= soloMedian * (1 - LENGTH_TOLERANCE)).toBe(true)
			t.expect(coopMedian <= soloMedian * (1 + LENGTH_TOLERANCE)).toBe(true)
			t.expect(worstDeal < 0.1).toBe(true) -- 5x the 20 ms a solo deal is meant to stay under
		end)

		t.it(`plays {GAMES} runs where one player leaves, and the leaver can no longer place`, function()
			local left, countedFrozen = 0, 0
			for seed = 1, GAMES do
				local run = CoopSession.new(CoopSession.newSource(Rng.new(seed)))
				local session = run.session
				local rng = Rng.new(seed + 200000)
				local leaveAt = 5 + seed % 30
				local leaver = seed % 2 + 1
				local frozen: number? = nil
				local leaverShare = 0

				while not session.isOver and session.moveCount < MAX_MOVES do
					if frozen == nil and session.moveCount >= leaveAt then
						t.expect(run:release(leaver)).toBe(true)
						frozen, leaverShare = session.score, run.contribution[leaver]
						left += 1
					end
					local move = chooseMove(session, rng)
					assert(move, "something fits, so the bot has a move")

					if frozen ~= nil then
						-- Nothing the leaver sends changes the run any more.
						local before = run:snapshot()
						t.expect(run:place(leaver, move[1], move[2], move[3])).toBe(nil)
						t.expect(run:snapshot()).toEqual(before)
					end
					t.expect(run:place(seatFor(run, move[1]), move[1], move[2], move[3])).toBeTruthy()

					t.expect(run.contribution[1] + run.contribution[2]).toBe(session.score)
					t.expect(run.countedScore).toBe(if frozen ~= nil then frozen else session.score)
					t.expect(run.contribution[leaver] >= leaverShare).toBe(true)
					t.expect(session.isOver).toBe(not anyTrayPieceFits(session))
				end
				if frozen ~= nil then
					t.expect(run.contribution[leaver]).toBe(leaverShare)
					if session.score > frozen then
						countedFrozen += 1
					end
				end
			end
			-- Most games run past the move where the player leaves, and in most the run then scores more.
			t.expect(left * 10 >= GAMES * 8).toBe(true)
			t.expect(countedFrozen * 2 >= left).toBe(true)
		end)

		t.it(`keeps a client copy identical over {MIRRORED_GAMES} runs, also after a player leaves`, function()
			local totalMoves, sets, leaves = 0, 0, 0
			for seed = 1, MIRRORED_GAMES do
				local server = CoopSession.new(CoopSession.newSource(Rng.new(seed)))
				local client = CoopSession.fromSnapshot(server:snapshot(), noSet)
				local rng = Rng.new(seed + 300000)
				local leaveAt = if seed % 2 == 0 then 3 + seed % 40 else math.huge
				local leaver = if seed % 4 == 0 then 1 else 2

				t.expect(client:snapshot()).toEqual(server:snapshot())
				while not server.session.isOver and server.session.moveCount < MAX_MOVES do
					if server.present[leaver] and server.session.moveCount >= leaveAt then
						t.expect(client:release(leaver)).toBe(server:release(leaver))
						leaves += 1
					end
					local move = chooseMove(server.session, rng)
					assert(move, "something fits, so the bot has a move")
					local seat = seatFor(server, move[1])
					local predicted = client:place(seat, move[1], move[2], move[3])
					local actual = server:place(seat, move[1], move[2], move[3])
					assert(predicted and actual, "both copies accept the move")

					if actual.refilled then
						sets += 1
						t.expect(predicted.awaitingSet).toBe(true)
						t.expect(client:receiveSet(server.session.tray :: { Pieces.Piece })).toBe(true)
					else
						t.expect(predicted.awaitingSet).toBe(false)
					end
					t.expect(predicted.points).toBe(actual.points)
					t.expect(client:snapshot()).toEqual(server:snapshot())
				end
				totalMoves += server.session.moveCount
			end
			t.expect(leaves > 0).toBe(true)
			print(
				string.format(
					"    Co-op lockstep: %d moves, %d sets delivered, %d players left, no divergence",
					totalMoves,
					sets,
					leaves
				)
			)
		end)
	end)
end
