--!strict
-- Two fake clients (PvpSync) play whole matches against the real PvpMatches (docs/PHASE6.md, M26). Every message in
-- both directions is late by 0 to MAX_DELAY ticks but keeps its order, as on one RemoteEvent; the opponent's board
-- goes over a channel that loses and reorders messages, as an UnreliableRemoteEvent does, and is sent again every
-- second. Some matches end with a forfeit, the rest on time. Once every message has arrived, each client must match
-- the server cell for cell without ever having asked for the state. How many clients still showed an old opponent
-- board when the match ended (every message about it lost since the last change) is printed: the next resend heals it.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local PvpBoardCodec = require("../src/shared/PvpBoardCodec")
local PvpMatches = require("../src/server/PvpMatches")
local PvpSession = require("../src/shared/PvpSession")
local PvpSync = require("../src/client/Util/PvpSync")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local PVP = Config.PVP
local SIZE = Config.GRID_SIZE
local MATCHES = 200
local TICK = 0.05 -- seconds
local MAX_DELAY = 6 -- ticks: 0.3 s, the server's grace period, so a move made before the end always counts
local BOARD_DROP = 0.2 -- share of opponent board messages lost
local BOARD_MAX_DELAY = 10 -- ticks; these may overtake each other
local MOVE_CHANCE = 0.04 -- per tick: about one move every 1.25 s
local TURN_CHANCE = 0.01
local OVERDUE_SECONDS = 2
local PLAYERS = { "A", "B" }

type Message = { at: number, kind: string, data: any }

-- A queue whose messages arrive in the order they were sent, each at least as late as the one before.
type Channel = { queue: { Message }, last: number }

local function newChannel(): Channel
	return { queue = {}, last = 0 }
end

local function push(channel: Channel, rng: Rng.Rng, tick: number, kind: string, data: any)
	local at = math.max(channel.last, tick + rng:nextInt(0, MAX_DELAY))
	channel.last = at
	table.insert(channel.queue, { at = at, kind = kind, data = data })
end

local function due(channel: Channel, tick: number): { Message }
	local out = {}
	while channel.queue[1] and channel.queue[1].at <= tick do
		table.insert(out, table.remove(channel.queue, 1))
	end
	return out
end

local function randomMove(session: PvpSession.PvpSession, rng: Rng.Rng): (number?, number?, number?)
	local moves: { { number } } = {}
	for slot, piece in session.game.tray do
		if piece then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if Board.canPlace(session.game.board, piece, x, y) then
						table.insert(moves, { slot, x, y })
					end
				end
			end
		end
	end
	if #moves == 0 then
		return nil, nil, nil
	end
	local move = moves[rng:nextInt(1, #moves)]
	return move[1], move[2], move[3]
end

return function(t: TestKit.TestKit)
	t.describe("PvpLockstep", function()
		t.it(`keeps {MATCHES} matches identical on both clients and the server, with late messages`, function()
			local stats = { moves = 0, refills = 0, stuck = 0, garbage = 0, turns = 0, forfeits = 0, dropped = 0 }
			local resyncs, divergences, staleBoards = 0, 0, 0

			for seed = 1, MATCHES do
				local clock = { now = 0 }
				local matches = PvpMatches.new({
					PvpSession = PvpSession,
					settings = PVP,
					clock = function(): number
						return clock.now
					end,
					newSeed = function(): number
						return seed
					end,
				})
				local rng = Rng.new(seed + 4242)
				local toServer: { [string]: Channel } = { A = newChannel(), B = newChannel() }
				local toClient: { [string]: Channel } = { A = newChannel(), B = newChannel() }
				local boards: { [string]: { Message } } = { A = {}, B = {} } -- unreliable, by receiver
				local syncs: { [string]: PvpSync.PvpSync? } = {}
				local seen: { [string]: PvpBoardCodec.View? } = {} -- newest opponent board each client has
				local ended = false
				local cutOff: { [string]: boolean } = {} -- the server dropped an action because the match had ended
				local forfeitAt = if seed % 10 == 0 then rng:nextInt(200, 3000) else math.huge
				local nextResend = 0

				local states = matches:start({ players = PLAYERS }, "friendly")
				assert(states)
				for seat, key in PLAYERS do
					push(toClient[key], rng, 0, "start", states[seat])
				end

				local function sendBoard(owner: string, tick: number)
					local view = matches:board(owner)
					if not view or rng:nextFloat() < BOARD_DROP then
						return
					end
					local receiver = if owner == "A" then "B" else "A"
					local at = tick + rng:nextInt(0, BOARD_MAX_DELAY)
					table.insert(boards[receiver], { at = at, kind = "board", data = PvpBoardCodec.encode(view) })
				end

				local function endBoth(info: PvpMatches.EndInfo, tick: number)
					ended = true
					for _, key in PLAYERS do
						push(toClient[key], rng, tick, "end", info)
					end
				end

				local tick = 0
				while true do
					clock.now = tick * TICK

					-- The server handles what has arrived.
					for _, key in PLAYERS do
						for _, message in due(toServer[key], tick) do
							local data = message.data
							if message.kind == "place" then
								local outcome = matches:place(key, data[1], data[2], data[3], data[4], data[5])
								if outcome.kind == "accepted" then
									push(toClient[key], rng, tick, "result", {
										matchId = outcome.matchId,
										moveIndex = outcome.moveIndex,
										score = outcome.score,
										sent = outcome.sent,
										cancelled = outcome.cancelled,
										pending = outcome.pending,
										refill = outcome.refill,
										stuck = outcome.stuck,
									})
									if outcome.incoming then
										push(toClient[outcome.opponent], rng, tick, "incoming", outcome.incoming)
										sendBoard(outcome.opponent, tick)
									end
									sendBoard(key, tick)
								elseif outcome.kind == "resync" then
									push(toClient[key], rng, tick, "state", outcome.state)
								elseif outcome.reason == "ended" then
									cutOff[key] = true
								end
							elseif message.kind == "rotate" then
								local outcome = matches:rotate(key, data[1], data[2], data[3])
								if outcome.kind == "resync" then
									push(toClient[key], rng, tick, "state", outcome.state)
								elseif outcome.kind == "ignored" and outcome.reason == "ended" then
									cutOff[key] = true
								end
							elseif message.kind == "forfeit" then
								local info = matches:forfeit(key, data)
								if info then
									endBoth(info, tick)
								end
							elseif message.kind == "state" then
								local state = matches:state(key)
								if state then
									push(toClient[key], rng, tick, "state", state)
								end
							end
						end
					end
					for _, info in matches:sweep() do
						endBoth(info, tick)
					end
					if clock.now >= nextResend then
						nextResend += PVP.OPPONENT_BOARD_RESEND_SECONDS
						sendBoard("A", tick)
						sendBoard("B", tick)
					end

					-- The clients handle what has arrived, then maybe act.
					for _, key in PLAYERS do
						for _, message in due(toClient[key], tick) do
							local sync = syncs[key]
							if message.kind == "start" then
								syncs[key] = PvpSync.new({ PvpSession = PvpSession }, message.data)
							elseif message.kind == "state" then
								resyncs += 1
								if sync then
									sync:reset(message.data)
								end
							elseif sync and message.kind == "result" then
								local applied = sync:onResult(message.data)
								if applied.kind == "resync" then
									resyncs += 1
									push(toServer[key], rng, tick, "state", nil)
								elseif applied.kind == "applied" then
									if applied.refill then
										stats.refills += 1
										stats.garbage += #applied.refill.garbage
									end
									if applied.stuck then
										stats.stuck += 1
									end
								end
							elseif sync and message.kind == "incoming" then
								sync:onIncoming(sync.matchId, message.data)
							elseif sync and message.kind == "end" then
								sync:onEnd(message.data)
							end
						end
						local arrived = {}
						for i = #boards[key], 1, -1 do
							if boards[key][i].at <= tick then
								table.insert(arrived, table.remove(boards[key], i))
							end
						end
						for _, message in arrived do
							local view = PvpBoardCodec.decode(message.data)
							assert(view, "a board that doesn't decode")
							local current = seen[key]
							if not current or PvpBoardCodec.isNewer(view.version, current.version) then
								seen[key] = view
							end
						end

						local sync = syncs[key]
						if sync and not ended then
							if sync:overdue(clock.now, OVERDUE_SECONDS) then
								resyncs += 1
								push(toServer[key], rng, tick, "state", nil)
							end
							if key == "A" and tick >= forfeitAt and sync:canDrag(clock.now) then
								forfeitAt = math.huge
								stats.forfeits += 1
								push(toServer[key], rng, tick, "forfeit", sync.matchId)
							elseif rng:nextFloat() < TURN_CHANCE then
								local slot = rng:nextInt(1, Config.PIECES_PER_SET)
								local turned, moveIndex = sync:rotate(slot, clock.now)
								if turned then
									stats.turns += 1
									push(toServer[key], rng, tick, "rotate", { sync.matchId, moveIndex, slot })
								end
							elseif sync:canDrag(clock.now) and rng:nextFloat() < MOVE_CHANCE then
								local slot, x, y = randomMove(sync.session, rng)
								if slot then
									local predicted, moveIndex = sync:place(slot, x :: number, y :: number, clock.now)
									if predicted then
										stats.moves += 1
										push(toServer[key], rng, tick, "place", { sync.matchId, moveIndex, slot, x, y })
									end
								end
							end
						end
					end

					local quiet = ended and #boards.A == 0 and #boards.B == 0
					for _, key in PLAYERS do
						quiet = quiet and #toServer[key].queue == 0 and #toClient[key].queue == 0
					end
					if quiet then
						break
					end
					tick += 1
				end

				-- Once everything has arrived: each client equals the server (moves the server dropped because the
				-- match had ended are the only difference allowed), and sees the opponent's latest board.
				for _, key in PLAYERS do
					local sync = syncs[key]
					assert(sync)
					local state = matches:peek(key)
					assert(state)
					if cutOff[key] then
						stats.dropped += 1
					elseif
						not pcall(function()
							t.expect(sync.session:snapshot()).toEqual(state.you)
						end)
					then
						divergences += 1
					end
					local view = seen[key]
					local actual = matches:board(if key == "A" then "B" else "A")
					assert(actual)
					if
						not view
						or not pcall(function()
							t.expect(view.cells).toEqual(actual.cells)
						end)
						or view.score ~= actual.score
						or view.pending ~= actual.pending
					then
						staleBoards += 1
					end
				end
				matches:remove("A")
				matches:remove("B")
				t.expect(matches:footprint()).toBe(0)
			end

			t.expect(divergences).toBe(0)
			t.expect(resyncs).toBe(0)
			t.expect(stats.refills > 0 and stats.stuck > 0 and stats.garbage > 0).toBe(true)
			print(
				string.format(
					"    PVP lockstep: %d moves, %d sets, %d garbage lines, %d stuck, %d turns, %d forfeits, "
						.. "%d players cut off by the end, %d resyncs, %d stale opponent boards",
					stats.moves,
					stats.refills,
					stats.garbage,
					stats.stuck,
					stats.turns,
					stats.forfeits,
					stats.dropped,
					resyncs,
					staleBoards
				)
			)
		end)
	end)
end
