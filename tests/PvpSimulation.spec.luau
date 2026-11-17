--!strict
-- Bots play whole PVP matches on a fake clock (docs/PHASE6.md, M24 "Mô phỏng"). Checks invariants after every move,
-- replays every server event on a client copy that must match cell for cell, and prints the numbers M24 tunes
-- Config.PVP with: how much garbage hurts, garbage sent per match, how often players get stuck, whether getting
-- stuck on purpose pays, how often both players get the same set, and how long a deal takes.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Pieces = require("../src/shared/Pieces")
local PvpSession = require("../src/shared/PvpSession")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local PVP = Config.PVP
local SIZE = Config.GRID_SIZE
local MATCHES = 200
local SUICIDE_MATCHES = 100
local PACE_SECONDS = 2 -- average time a bot takes per move; each move takes 75% to 125% of it

type Session = PvpSession.PvpSession
type BotKind = "greedy" | "suicide"

-- How many rows and columns placing the piece would complete (the move must be valid).
local function linesCompleted(board: Board.Board, piece: Pieces.Piece, x: number, y: number): number
	local preview = Board.previewLines(board, piece, x, y)
	return #preview.rows + #preview.cols
end

-- Edges of the piece that touch a wall or a filled cell; higher means a tidier fit.
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function contact(board: Board.Board, piece: Pieces.Piece, x: number, y: number): number
	local own = {}
	for _, cell in piece.cells do
		own[(y + cell.y) * SIZE + x + cell.x] = true
	end
	local count = 0
	for _, cell in piece.cells do
		for _, offset in NEIGHBOURS do
			local nx, ny = x + cell.x + offset[1], y + cell.y + offset[2]
			if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE then
				count += 1
			elseif not own[ny * SIZE + nx] and Board.get(board, nx, ny) ~= 0 then
				count += 1
			end
		end
	end
	return count
end

-- The greedy bot of Simulation.spec: most lines, then the tidiest fit. The suicide bot wants to get stuck: fewest
-- lines, then the loosest fit. Ties are broken at random.
local function chooseMove(session: Session, kind: BotKind, rng: Rng.Rng): (number, number, number)
	local best: { number }? = nil
	local bestValue, ties = -math.huge, 0
	for slot, piece in session.game.tray do
		if not piece then
			continue
		end
		for y = 0, SIZE - piece.height do
			for x = 0, SIZE - piece.width do
				if Board.canPlace(session.game.board, piece, x, y) then
					local value = linesCompleted(session.game.board, piece, x, y) * 100
						+ contact(session.game.board, piece, x, y)
					if kind == "suicide" then
						value = -value
					end
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
	assert(best, "the server never leaves a player without a move")
	return best[1], best[2], best[3]
end

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return 0
	end
	return if n % 2 == 1 then sorted[(n + 1) // 2] else (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

local function setKey(set: { string }): string
	return table.concat(set, ",")
end

type MatchOptions = {
	seed: number,
	garbage: boolean, -- false: attacks are counted but never reach the opponent
	kinds: { BotKind },
	mirror: boolean, -- replay every event on a client copy and compare
}

type MatchResult = {
	scores: { number },
	sent: { number },
	stuck: { number },
	sets: number, -- set numbers both players were dealt
	sameSets: number, -- of those, how many were the same pieces
	dealTimes: { number },
	divergences: number,
}

local function playMatch(t: TestKit.TestKit, options: MatchOptions): MatchResult
	local sides = {
		PvpSession.new(options.seed, 1, 0, PVP.MATCH_SECONDS),
		PvpSession.new(options.seed, 2, 0, PVP.MATCH_SECONDS),
	}
	local clients: { Session } = {}
	if options.mirror then
		clients = { PvpSession.fromSnapshot(sides[1]:snapshot()), PvpSession.fromSnapshot(sides[2]:snapshot()) }
	end
	local botRngs = { Rng.new(options.seed * 2 + 7), Rng.new(options.seed * 2 + 8) }
	local nextAt = { PACE_SECONDS * botRngs[1]:nextFloat(), PACE_SECONDS * botRngs[2]:nextFloat() }
	local setsDealt: { { [number]: string } } = { { [1] = setKey({}) }, { [1] = setKey({}) } }
	local dealTimes: { number } = {}
	local divergences = 0

	local function compare(i: number)
		if not options.mirror then
			return
		end
		local same = pcall(function()
			t.expect(clients[i]:snapshot()).toEqual(sides[i]:snapshot())
		end)
		if not same then
			divergences += 1
		end
	end

	while true do
		local i = if nextAt[1] <= nextAt[2] then 1 else 2
		local now = nextAt[i]
		if now > PVP.MATCH_SECONDS then
			break
		end
		local side, other = sides[i], sides[3 - i]
		if side:isLocked(now) then
			nextAt[i] = side.lockedUntil
			continue
		end

		local slot, x, y = chooseMove(side, options.kinds[i], botRngs[i])
		local scoreBefore = side.game.score
		local started = os.clock()
		local result = side:place(slot, x, y, now)
		local elapsed = os.clock() - started
		assert(result, "a valid move was refused")
		if result.refill then
			table.insert(dealTimes, elapsed)
			setsDealt[i][side.setIndex] = setKey(result.refill.set)
		end

		t.expect(side.game.score >= scoreBefore).toBe(true)
		t.expect(side.game.isOver).toBe(false)
		t.expect(side.game.awaitingSet).toBe(false)
		t.expect(Board.findCompleteLines(side.game.board)).toEqual({ rows = {}, cols = {} })
		t.expect(#side.pending <= PVP.GARBAGE_QUEUE_MAX).toBe(true)
		t.expect(result.cancelled + result.sent).toBe(result.attack)

		if options.mirror then
			local client = clients[i]
			local predicted = client:place(slot, x, y, now)
			if not predicted or predicted.attack ~= result.attack then
				divergences += 1
			end
			if result.refill then
				client:deliver(result.refill.garbage, result.refill.set)
			end
			if result.stuck then
				client:applyStuck(result.stuck.set, result.stuck.lockedUntil)
			end
			client:setPending(side.pending)
			compare(i)
		end

		if options.garbage and result.sent > 0 then
			other:receiveAttack(result.sent)
			if options.mirror then
				clients[3 - i]:setPending(other.pending)
				compare(3 - i)
			end
		end

		nextAt[i] = now + PACE_SECONDS * (0.75 + 0.5 * botRngs[i]:nextFloat())
	end

	local sets, sameSets = 0, 0
	for k, key in setsDealt[1] do
		local otherKey = setsDealt[2][k]
		if k > 1 and otherKey then
			sets += 1
			if otherKey == key then
				sameSets += 1
			end
		end
	end

	return {
		scores = { sides[1].game.score, sides[2].game.score },
		sent = { sides[1].sentTotal, sides[2].sentTotal },
		stuck = { sides[1].stuckCount, sides[2].stuckCount },
		sets = sets,
		sameSets = sameSets,
		dealTimes = dealTimes,
		divergences = divergences,
	}
end

return function(t: TestKit.TestKit)
	t.describe("PvpSimulation", function()
		t.it(`plays {MATCHES} greedy matches, a client copy matching the server cell for cell`, function()
			local started = os.clock()
			local withGarbage, withoutGarbage, sent, stuck = {}, {}, {}, {}
			local sets, sameSets, divergences = 0, 0, 0
			local dealTimes: { number } = {}

			for seed = 1, MATCHES do
				local match =
					playMatch(t, { seed = seed, garbage = true, kinds = { "greedy", "greedy" }, mirror = true })
				local calm =
					playMatch(t, { seed = seed, garbage = false, kinds = { "greedy", "greedy" }, mirror = false })
				for i = 1, 2 do
					table.insert(withGarbage, match.scores[i])
					table.insert(withoutGarbage, calm.scores[i])
					table.insert(sent, match.sent[i])
					table.insert(stuck, match.stuck[i])
				end
				sets += match.sets
				sameSets += match.sameSets
				divergences += match.divergences
				table.move(match.dealTimes, 1, #match.dealTimes, #dealTimes + 1, dealTimes)
			end

			t.expect(divergences).toBe(0)

			local worst, total = 0, 0
			for _, elapsed in dealTimes do
				worst = math.max(worst, elapsed)
				total += elapsed
			end
			local medianWith, medianWithout = median(withGarbage), median(withoutGarbage)
			print(
				string.format(
					"    PVP: median score %d with garbage, %d without (%+.1f%%); garbage sent per player median %.1f; "
						.. "stuck per player median %.1f (max %d); same set %d%% of %d; deal avg %.3f ms, worst %.3f ms; %.1fs",
					medianWith,
					medianWithout,
					(medianWith - medianWithout) * 100 / medianWithout,
					median(sent),
					median(stuck),
					math.max(table.unpack(stuck)),
					sameSets * 100 // math.max(sets, 1),
					sets,
					total * 1000 / math.max(#dealTimes, 1),
					worst * 1000,
					os.clock() - started
				)
			)
		end)

		t.it(`pits a bot that gets stuck on purpose against a greedy one ({SUICIDE_MATCHES} matches)`, function()
			local greedyWins, ties, suicideStuck = 0, 0, {}
			for seed = 1, SUICIDE_MATCHES do
				local match = playMatch(
					t,
					{ seed = 5000 + seed, garbage = true, kinds = { "suicide", "greedy" }, mirror = false }
				)
				if match.scores[2] > match.scores[1] then
					greedyWins += 1
				elseif match.scores[2] == match.scores[1] then
					ties += 1
				end
				table.insert(suicideStuck, match.stuck[1])
			end
			print(
				string.format(
					"    PVP: greedy beats the suicide bot in %d%% of matches (%d ties); suicide bot stuck median %.1f",
					greedyWins * 100 // SUICIDE_MATCHES,
					ties,
					median(suicideStuck)
				)
			)
		end)
	end)
end
