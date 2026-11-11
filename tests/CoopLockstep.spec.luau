--!strict
-- Two simulated clients and the real CoopRuns play whole Co-op games. Both clients place at once and every
-- message takes a random time to arrive (but stays in order, like a RemoteEvent), so moves clash, cross each
-- other and come back rejected. Once every message has arrived the two clients and the server have to agree
-- exactly, nothing may be left pending, and no client may have needed a resync (that is what a normal game
-- must never need). Some games have a player leave halfway.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local CoopRuns = require("../src/server/CoopRuns")
local CoopSession = require("../src/shared/CoopSession")
local CoopSync = require("../src/client/Util/CoopSync")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local GAMES = 200
local MAX_TICKS = 1500
local TICK_SECONDS = 0.2 -- the server's clock per tick: a client acts at most 5 times a second
local MAX_DELAY_TICKS = 6
local CONFIRM_TIMEOUT_TICKS = 10 -- a move unanswered for this long makes the client ask for the state
local SIZE = Config.GRID_SIZE
local A, B = "A", "B"

type Message = { due: number, kind: string, a: any?, b: any?, c: any?, d: any?, e: any? }
type Channel = { Message }

type Client = {
	name: string,
	seat: number,
	sync: CoopSync.CoopSync,
	toServer: Channel,
	toClient: Channel,
	gone: boolean,
	needState: boolean, -- asked for the state and waiting for it
	oldestPending: number?, -- the tick since which a move has gone unanswered
}

-- Delivers in order: a later message never overtakes an earlier one.
local function send(channel: Channel, tick: number, delay: number, message: Message)
	local last = channel[#channel]
	message.due = math.max(tick + delay, if last then last.due else 0)
	table.insert(channel, message)
end

local function legalMoves(sync: CoopSync.CoopSync): { { number } }
	local shown = sync:session()
	local moves: { { number } } = {}
	for slot, piece in shown.session.tray do
		if piece and shown:mayPlace(sync.seat, slot) then
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if shown:canPlace(sync.seat, slot, x, y) then
						table.insert(moves, { slot, x, y })
					end
				end
			end
		end
	end
	return moves
end

return function(t: TestKit.TestKit)
	t.describe("Co-op lockstep", function()
		t.it(
			`keeps two clients and the server identical over {GAMES} games with delayed messages and clashes`,
			function()
				local totals = { moves = 0, rejected = 0, dropped = 0, resyncs = 0, leaves = 0, sets = 0 }

				for seed = 1, GAMES do
					local now = 0
					local runs = CoopRuns.new({
						CoopSession = CoopSession,
						Rng = Rng,
						clock = function(): number
							return now
						end,
						newSeed = function(): number
							return seed
						end,
						afkSeconds = 45,
					})
					local states = runs:start({ id = 1, players = { A, B }, present = { true, true } })
					assert(states, "the run starts")
					local rng = Rng.new(seed + 9000)
					local deps: CoopSync.Deps = { CoopSession = CoopSession, Pieces = Pieces }
					local clients: { Client } = {}
					for seat, name in { A, B } do
						table.insert(clients, {
							name = name,
							seat = seat,
							sync = CoopSync.new(deps, states[seat]),
							toServer = {},
							toClient = {},
							gone = false,
							needState = false,
							oldestPending = nil,
						})
					end
					local byName = { [A] = clients[1], [B] = clients[2] }
					local leaveAt = if seed % 4 == 0 then rng:nextInt(5, 60) else math.huge
					local leaver = if seed % 8 == 0 then clients[1] else clients[2]
					local eager = 0.25 + rng:nextFloat() * 0.6 -- how often a client moves

					local function deliverToServer(client: Client, message: Message)
						if message.kind == "place" then
							local outcome =
								runs:place(client.name, message.a, message.b, message.c, message.d, message.e)
							if outcome.kind == "accepted" then
								totals.moves += 1
								for seat, name in outcome.players do
									local target = byName[name]
									if not target.gone then
										send(target.toClient, message.due, rng:nextInt(0, MAX_DELAY_TICKS), {
											due = 0,
											kind = "move",
											a = outcome.move,
											b = outcome.takeOverIn[seat],
										})
									end
								end
							elseif outcome.kind == "rejected" then
								totals.rejected += 1
								send(client.toClient, message.due, rng:nextInt(0, MAX_DELAY_TICKS), {
									due = 0,
									kind = "reject",
									a = outcome.runId,
									b = outcome.moveId,
								})
							end
						elseif message.kind == "state" then
							local state = runs:state(client.name)
							if state then
								send(client.toClient, message.due, rng:nextInt(0, MAX_DELAY_TICKS), {
									due = 0,
									kind = "state",
									a = state,
								})
							end
						end
					end

					local function deliverToClient(client: Client, message: Message, tick: number)
						if message.kind == "move" then
							local move = message.a :: CoopSync.Move
							local full = table.clone(move)
							full.takeOverAt = message.b
							local applied = client.sync:applyMove(full)
							if applied.kind == "resync" then
								totals.resyncs += 1
								client.needState = true
							elseif applied.kind == "applied" then
								totals.dropped += #applied.dropped
							end
						elseif message.kind == "reject" then
							client.sync:reject(message.a, message.b)
						elseif message.kind == "state" then
							client.sync:reset(message.a)
							client.needState = false
						end
						client.oldestPending = if client.sync:pendingCount() > 0
							then client.oldestPending or tick
							else nil
					end

					local tick = 0
					local function quiet(): boolean
						for _, client in clients do
							if #client.toServer > 0 or #client.toClient > 0 or client.needState then
								return false
							end
						end
						return true
					end

					-- Plays until the run is over (or a cap), then lets every message arrive.
					local over = false
					local settle = 0
					while tick < MAX_TICKS and settle < 80 do
						tick += 1
						now += TICK_SECONDS
						if tick == leaveAt and not leaver.gone then
							leaver.gone = true
							totals.leaves += 1
							local outcome = runs:leave(leaver.name)
							-- The messages already on their way to the leaver are lost with them.
							table.clear(leaver.toClient)
							table.clear(leaver.toServer)
							if outcome and outcome.stayer and outcome.state then
								local stayer = byName[outcome.stayer]
								send(stayer.toClient, tick, rng:nextInt(0, MAX_DELAY_TICKS), {
									due = 0,
									kind = "state",
									a = outcome.state,
								})
							end
						end

						for _, client in clients do
							if client.gone then
								continue
							end
							-- Messages that are due, in order.
							while client.toClient[1] and client.toClient[1].due <= tick do
								deliverToClient(client, table.remove(client.toClient, 1) :: Message, tick)
							end
							-- A client that is behind, or has waited too long for an answer, asks for the state.
							local oldest = client.oldestPending
							if
								(client.needState or (oldest and tick - oldest > CONFIRM_TIMEOUT_TICKS)) and not over
							then
								send(
									client.toServer,
									tick,
									rng:nextInt(0, MAX_DELAY_TICKS),
									{ due = 0, kind = "state" }
								)
								client.oldestPending = if client.sync:pendingCount() > 0 then tick else nil
							end
							-- Play: place a random legal move from the pieces on screen.
							if not over and not client.needState and rng:nextFloat() < eager then
								local moves = legalMoves(client.sync)
								if #moves > 0 then
									local pick = moves[rng:nextInt(1, #moves)]
									local result, moveId = client.sync:place(pick[1], pick[2], pick[3])
									assert(result and moveId, "a legal move on screen is valid")
									client.oldestPending = client.oldestPending or tick
									send(client.toServer, tick, rng:nextInt(0, MAX_DELAY_TICKS), {
										due = 0,
										kind = "place",
										a = client.sync.runId,
										b = moveId,
										c = pick[1],
										d = pick[2],
										e = pick[3],
									})
								end
							end
						end
						for _, client in clients do
							while client.toServer[1] and client.toServer[1].due <= tick do
								deliverToServer(client, table.remove(client.toServer, 1) :: Message)
							end
						end

						local summary = runs:summary(A) or runs:summary(B)
						over = summary == nil or summary.isOver
						if over and quiet() then
							settle += 1
						end
					end

					-- Everything has arrived: every client that is still here agrees with the server.
					local view = runs:peek(A) or runs:peek(B)
					assert(view, "the run is still on the server")
					for _, client in clients do
						if client.gone then
							continue
						end
						t.expect(client.sync:pendingCount()).toBe(0)
						t.expect(client.sync.confirmed:snapshot()).toEqual(view.coop:snapshot())
						t.expect(client.sync:session():snapshot()).toEqual(view.coop:snapshot())
						t.expect(client.sync.seq).toBe(view.coop.session.moveCount)
						totals.sets += view.coop.session.moveCount // 4
					end
					-- Without anybody leaving, a game never needs a resync.
					if leaveAt == math.huge then
						t.expect(totals.resyncs).toBe(0)
					end
					local board = view.coop.session.board
					t.expect(Board.findCompleteLines(board)).toEqual({ rows = {}, cols = {} })
				end

				t.expect(totals.moves > 1000).toBe(true)
				t.expect(totals.rejected > 20).toBe(true) -- the delays really do make moves clash
				t.expect(totals.leaves > 10).toBe(true)
				print(
					string.format(
						"    Co-op lockstep (delayed): %d moves accepted, %d rejected, %d dropped early on the client, %d players left, %d resyncs",
						totals.moves,
						totals.rejected,
						totals.dropped,
						totals.leaves,
						totals.resyncs
					)
				)
			end
		)
	end)
end
