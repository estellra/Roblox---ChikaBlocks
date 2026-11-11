--!strict
-- Like CoopLockstep, with turns and revives added: two simulated clients and the real CoopRuns play whole Co-op
-- games where both place AND turn pieces at once (some turns cost a bought rotation, from a wallet the server keeps),
-- messages take a random time to arrive in order, and the run is revived once it is over. When every message has
-- arrived the two clients and the server have to agree exactly, nothing may be left pending, and (with nobody
-- leaving) no client may have needed a resync. Some games have a player leave halfway.
local Config = require("../src/shared/Config")
local CoopRuns = require("../src/server/CoopRuns")
local CoopSession = require("../src/shared/CoopSession")
local CoopSync = require("../src/client/Util/CoopSync")
local Pieces = require("../src/shared/Pieces")
local Rng = require("../src/shared/Rng")
local TestKit = require("./TestKit")

local GAMES = 200
local MAX_TICKS = 4000
local TICK_SECONDS = 0.2
local MAX_DELAY_TICKS = 6
local CONFIRM_TIMEOUT_TICKS = 10
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
	needState: boolean,
	oldestPending: number?,
	paid: number, -- the bought rotations this client thinks it has; the server's Profile corrects it
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

-- The slots whose piece this client could turn right now.
local function turnable(client: Client): { number }
	local shown = client.sync:session()
	local slots: { number } = {}
	if shown.session.isOver or shown.session.awaitingSet then
		return slots
	end
	for slot, piece in shown.session.tray do
		if
			piece
			and shown:mayPlace(client.seat, slot)
			and Pieces.canRotate(piece)
			and (shown.session.unlocked[slot] or client.sync:freeRotations() > 0 or client.paid > 0)
		then
			table.insert(slots, slot)
		end
	end
	return slots
end

return function(t: TestKit.TestKit)
	t.describe("Co-op lockstep with turns and revives", function()
		t.it(
			`keeps two clients and the server identical over {GAMES} games with turns, bought rotations and revives`,
			function()
				local totals = {
					moves = 0,
					turns = 0,
					paidTurns = 0,
					rejectedTurns = 0,
					rejected = 0,
					revives = 0,
					resyncs = 0,
					leaves = 0,
				}

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
					local rng = Rng.new(seed + 4000)
					local deps: CoopSync.Deps = { CoopSession = CoopSession, Pieces = Pieces }
					local clients: { Client } = {}
					local wallet: { [string]: number } = {} -- the bought rotations the server has for each player
					for seat, name in { A, B } do
						local paid = rng:nextInt(0, 2)
						wallet[name] = paid
						table.insert(clients, {
							name = name,
							seat = seat,
							sync = CoopSync.new(deps, states[seat]),
							toServer = {},
							toClient = {},
							gone = false,
							needState = false,
							oldestPending = nil,
							paid = paid,
						})
					end
					local byName = { [A] = clients[1], [B] = clients[2] }
					local leaveAt = if seed % 5 == 0 then rng:nextInt(5, 120) else math.huge
					local leaver = if seed % 10 == 0 then clients[1] else clients[2]
					local eager = 0.25 + rng:nextFloat() * 0.6
					local turnChance = 0.1 + rng:nextFloat() * 0.3
					local revivesWanted = seed % 3
					local revivesDone = 0

					local function toPresent(
						outcomePlayers: { any },
						present: { boolean },
						tick: number,
						build: (seat: number) -> Message
					)
						for seat, name in outcomePlayers do
							local target = byName[name]
							if present[seat] and not target.gone then
								send(target.toClient, tick, rng:nextInt(0, MAX_DELAY_TICKS), build(seat))
							end
						end
					end

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
						elseif message.kind == "turn" then
							local outcome =
								runs:rotate(client.name, message.a, message.b, message.c, wallet[client.name])
							if outcome.kind == "accepted" then
								totals.turns += 1
								if outcome.turn.charged == "paid" then
									totals.paidTurns += 1
									wallet[client.name] -= 1 -- spent in the same breath, as CoopService does
								end
								toPresent(
									outcome.players,
									outcome.present,
									message.due,
									function(_seat: number): Message
										return { due = 0, kind = "turned", a = outcome.turn }
									end
								)
								if outcome.turn.charged == "paid" then
									-- The server sends the player's profile with the new count, as GameService does.
									send(client.toClient, message.due, rng:nextInt(0, MAX_DELAY_TICKS), {
										due = 0,
										kind = "profile",
										a = wallet[client.name],
									})
								end
							elseif outcome.kind == "rejected" then
								totals.rejectedTurns += 1
								send(client.toClient, message.due, rng:nextInt(0, MAX_DELAY_TICKS), {
									due = 0,
									kind = "reject",
									a = outcome.runId,
									b = outcome.moveId,
								})
								-- And the profile again: the client may have been wrong about its rotations.
								send(client.toClient, message.due, rng:nextInt(0, MAX_DELAY_TICKS), {
									due = 0,
									kind = "profile",
									a = wallet[client.name],
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
							local full = table.clone(message.a :: CoopSync.Move)
							full.takeOverAt = message.b
							local applied = client.sync:applyMove(full)
							if applied.kind == "resync" then
								totals.resyncs += 1
								client.needState = true
							end
						elseif message.kind == "turned" then
							local applied = client.sync:applyTurn(message.a :: CoopSync.Turn)
							if applied.kind == "resync" then
								totals.resyncs += 1
								client.needState = true
							end
						elseif message.kind == "reject" then
							client.sync:reject(message.a, message.b)
						elseif message.kind == "profile" then
							client.paid = message.a
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

					local over = false
					local settle = 0
					while tick < MAX_TICKS and settle < 80 do
						tick += 1
						now += TICK_SECONDS
						if tick == leaveAt and not leaver.gone then
							leaver.gone = true
							totals.leaves += 1
							local outcome = runs:leave(leaver.name)
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
							while client.toClient[1] and client.toClient[1].due <= tick do
								deliverToClient(client, table.remove(client.toClient, 1) :: Message, tick)
							end
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
							if not over and not client.needState and rng:nextFloat() < eager then
								local slots = turnable(client)
								if #slots > 0 and rng:nextFloat() < turnChance then
									local slot = slots[rng:nextInt(1, #slots)]
									local result, moveId = client.sync:rotate(slot, client.paid)
									assert(result and moveId, "a turn that is allowed on screen is valid")
									if result.charged == "paid" then
										client.paid -= 1
									end
									client.oldestPending = client.oldestPending or tick
									send(client.toServer, tick, rng:nextInt(0, MAX_DELAY_TICKS), {
										due = 0,
										kind = "turn",
										a = client.sync.runId,
										b = moveId,
										c = slot,
									})
								else
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
							-- Over and everything has arrived: somebody pays for a revive, and the game goes on.
							if settle == 10 and revivesDone < revivesWanted and summary then
								local payer = if not byName[A].gone then A else B
								local outcome = runs:revive(payer, summary.runId)
								if outcome then
									revivesDone += 1
									totals.revives += 1
									for seat, name in outcome.players do
										local target = byName[name]
										if outcome.present[seat] and not target.gone then
											send(target.toClient, tick, rng:nextInt(0, MAX_DELAY_TICKS), {
												due = 0,
												kind = "state",
												a = outcome.states[seat],
											})
										end
									end
									settle = 0
									over = false
								end
							end
						else
							settle = 0
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
						t.expect(client.sync.seq).toBe(view.seq)
						t.expect(client.paid).toBe(wallet[client.name]) -- the wallet the client keeps is the server's
					end
					if leaveAt == math.huge then
						t.expect(totals.resyncs).toBe(0)
					end
				end

				t.expect(totals.moves > 1000).toBe(true)
				t.expect(totals.turns > 200).toBe(true)
				t.expect(totals.paidTurns > 20).toBe(true)
				t.expect(totals.revives > 50).toBe(true)
				t.expect(totals.leaves > 10).toBe(true)
				print(
					string.format(
						"    Co-op lockstep (turns, revives): %d moves, %d turns (%d bought, %d refused), %d moves rejected, %d revives, %d players left, %d resyncs",
						totals.moves,
						totals.turns,
						totals.paidTurns,
						totals.rejectedTurns,
						totals.rejected,
						totals.revives,
						totals.leaves,
						totals.resyncs
					)
				)
			end
		)
	end)
end
