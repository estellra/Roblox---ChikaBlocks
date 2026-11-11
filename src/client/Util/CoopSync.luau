--!strict
-- The client's copy of a Co-op run, as pure logic so Lune can test it. Two layers:
--   confirmed  what the server has told us, applied move by move in the server's order (`seq`)
--   pending    this player's own moves and turns that were sent and not confirmed yet (usually none or one)
-- What is shown is the confirmed layer with the pending ones played on top, so the player's own pieces land and
-- turn at once. When an event of the partner's arrives it goes into the confirmed layer and the pending ones are
-- played again on top; any that no longer fit (the partner got there first) are dropped at once, which sends the
-- piece back to its tray without waiting for the server's CoopReject. The server decides the score and the sets;
-- a gap in `seq`, a move or turn that doesn't fit our copy or a score that differs means we are out of step, and
-- the caller asks for the full state. A move and a turn both take a `seq`: a turn changes the piece in a tray slot,
-- which the partner's copy needs to know before the move that places it.
-- The shared modules are passed in because shared and client code sit in different places on disk and in the
-- DataModel.

export type Deps = { CoopSession: any, Pieces: any }

-- What CoopState carries (see CoopRuns.State).
export type State = {
	runId: number,
	seq: number,
	seat: number,
	session: any, -- CoopSession.Snapshot
	takeOverAt: number?, -- server time (workspace:GetServerTimeNow) when the player may take over, if they may
}

-- An accepted move as the server announces it (see CoopRuns.Move), with when this player may take over.
export type Move = {
	runId: number,
	seq: number,
	seat: number,
	moveId: number,
	slot: number,
	x: number,
	y: number,
	score: number,
	set: { string }?,
	isOver: boolean,
	takeOverAt: number?,
}

-- A piece turned, as the server announces it (see CoopRuns.Turn).
export type Turn = {
	runId: number,
	seq: number,
	seat: number,
	moveId: number,
	slot: number,
	charged: ("free" | "paid")?,
}

-- An own event not confirmed yet: a move (x and y), or a turn of the piece in `slot`.
export type Pending = { moveId: number, slot: number, x: number?, y: number?, turn: boolean? }

export type Applied =
	{ kind: "applied", mine: boolean, result: any?, dropped: { Pending } } -- result: the move's effect, for the partner's
	| { kind: "ignored" } -- a move we have already, or from an older run
	| { kind: "resync", reason: string }

local CoopSync = {}
CoopSync.__index = CoopSync

export type CoopSync = typeof(setmetatable(
	{} :: {
		deps: Deps,
		runId: number,
		seat: number,
		seq: number, -- the last confirmed event (a move or a turn)
		confirmed: any, -- CoopSession
		pending: { Pending },
		shown: any?, -- confirmed + pending; nil until it has to be built again
		nextMoveId: number,
		takeOverAt: number?, -- from the last message: when the player may take over, if they may
	},
	CoopSync
))

-- The client never deals: new sets arrive with the move that used the last piece.
local function noSet(_board: any, _score: number, _reason: any): any
	return nil
end

function CoopSync.new(deps: Deps, state: State): CoopSync
	return setmetatable({
		deps = deps,
		runId = state.runId,
		seat = state.seat,
		seq = state.seq,
		confirmed = deps.CoopSession.fromSnapshot(state.session, noSet),
		pending = {},
		shown = nil,
		nextMoveId = 0,
		takeOverAt = state.takeOverAt,
	}, CoopSync)
end

-- The server's full state replaces everything, e.g. after a resync or when the partner has gone. Moves still on
-- their way are not lost: they come back confirmed.
function CoopSync.reset(self: CoopSync, state: State)
	self.runId = state.runId
	self.seat = state.seat
	self.seq = state.seq
	self.confirmed = self.deps.CoopSession.fromSnapshot(state.session, noSet)
	table.clear(self.pending)
	self.shown = nil
	self.takeOverAt = state.takeOverAt
end

-- Builds the shown layer: the confirmed one with the pending moves and turns played again, in the order they were
-- made. Ones that no longer fit are taken out of `pending` and returned. A turn is replayed with every rotation
-- paid for: it was only made because the player could pay, and which wallet it came out of comes out the same.
local function rebuild(self: CoopSync): { Pending }
	local CoopSession = self.deps.CoopSession
	local shown = CoopSession.fromSnapshot(self.confirmed:snapshot(), noSet)
	local dropped: { Pending } = {}
	local kept: { Pending } = {}
	for _, move in self.pending do
		local fits = if move.turn
			then shown:rotate(self.seat, move.slot, math.huge) ~= nil
			else shown:place(self.seat, move.slot, move.x, move.y) ~= nil
		if fits then
			table.insert(kept, move)
		else
			table.insert(dropped, move)
		end
	end
	self.pending = kept
	self.shown = shown
	return dropped
end

-- What is on screen: the confirmed state with this player's unconfirmed moves on top.
function CoopSync.session(self: CoopSync): any
	if not self.shown then
		rebuild(self)
	end
	return self.shown
end

-- Whether the piece in `slot` may be picked up by this player.
function CoopSync.canDrag(self: CoopSync, slot: number): boolean
	local shown = self:session()
	return shown.session.tray[slot] ~= nil and shown.session.tray[slot] ~= false and shown:mayPlace(self.seat, slot)
end

-- Plays a move on the shown layer and keeps it as pending. Returns the move's effect and its id (to send), or
-- nil when it isn't valid (nothing changes).
function CoopSync.place(self: CoopSync, slot: unknown, x: unknown, y: unknown): (any?, number?)
	local shown = self:session()
	local result = shown:place(self.seat, slot, x, y)
	if not result then
		return nil, nil
	end
	self.nextMoveId += 1
	table.insert(self.pending, { moveId = self.nextMoveId, slot = result.slot, x = result.x, y = result.y })
	return result, self.nextMoveId
end

-- Turns the piece in `slot` on the shown layer and keeps it as pending. `paidAvailable` is how many rotations the
-- player has bought and not used (the first turn of a piece takes the free one, else a bought one). Returns the
-- turn's effect (what it cost, in `charged`) and its id (to send), or nil when it isn't possible (nothing changes).
function CoopSync.rotate(self: CoopSync, slot: unknown, paidAvailable: unknown): (any?, number?)
	local shown = self:session()
	local result = shown:rotate(self.seat, slot, paidAvailable)
	if not result then
		return nil, nil
	end
	self.nextMoveId += 1
	table.insert(self.pending, { moveId = self.nextMoveId, slot = result.slot, turn = true })
	return result, self.nextMoveId
end

-- The free rotations this player has left, counting the ones they have turned and not heard back about.
function CoopSync.freeRotations(self: CoopSync): number
	return self:session():freeRotationsOf(self.seat)
end

-- A piece turned, from the server. It has to be the next event: anything else means we missed one. Like a move it
-- goes into the confirmed layer and the player's own pending events are played again on top.
function CoopSync.applyTurn(self: CoopSync, turn: Turn): Applied
	if turn.runId ~= self.runId or turn.seq <= self.seq then
		return { kind = "ignored" }
	elseif turn.seq ~= self.seq + 1 then
		return { kind = "resync", reason = `expected move {self.seq + 1}, got {turn.seq}` }
	end
	-- The wallet the server charged is not ours to know (a bought rotation is in the partner's saved data), so the
	-- turn is made with just enough to pay in the way it says, and has to cost what the server says it cost.
	local result = self.confirmed:rotate(turn.seat, turn.slot, if turn.charged == "paid" then 1 else 0)
	if not result or result.charged ~= turn.charged then
		return { kind = "resync", reason = "the turn does not fit the confirmed state" }
	end

	self.seq = turn.seq
	local mine = turn.seat == self.seat
	if mine then
		for index, pending in self.pending do
			if pending.moveId == turn.moveId then
				table.remove(self.pending, index)
				break
			end
		end
	end
	return { kind = "applied", mine = mine, result = if mine then nil else result, dropped = rebuild(self) }
end

-- An accepted move from the server. It has to be the next one: anything else means we missed one.
function CoopSync.applyMove(self: CoopSync, move: Move): Applied
	if move.runId ~= self.runId or move.seq <= self.seq then
		return { kind = "ignored" }
	elseif move.seq ~= self.seq + 1 then
		return { kind = "resync", reason = `expected move {self.seq + 1}, got {move.seq}` }
	end
	local confirmed = self.confirmed
	local result = confirmed:place(move.seat, move.slot, move.x, move.y)
	if not result then
		return { kind = "resync", reason = "the move does not fit the confirmed board" }
	end
	if confirmed.session.score ~= move.score then
		return { kind = "resync", reason = `score {confirmed.session.score} here, {move.score} there` }
	end
	if move.set then
		local pieces = {}
		for i, id in move.set do
			pieces[i] = self.deps.Pieces.BY_ID[id]
		end
		if not confirmed:receiveSet(pieces) then
			return { kind = "resync", reason = "a set arrived that we were not waiting for" }
		end
	elseif confirmed.session.awaitingSet then
		return { kind = "resync", reason = "the set never came" }
	end
	if confirmed.session.isOver ~= move.isOver then
		return { kind = "resync", reason = "game over differs" }
	end

	self.seq = move.seq
	self.takeOverAt = move.takeOverAt
	local mine = move.seat == self.seat
	if mine then
		for index, pending in self.pending do
			if pending.moveId == move.moveId then
				table.remove(self.pending, index)
				break
			end
		end
	end
	return { kind = "applied", mine = mine, result = if mine then nil else result, dropped = rebuild(self) }
end

-- The server turned a move down (the partner got there first): it stops being pending. Returns the other pending
-- moves that no longer fit without it.
function CoopSync.reject(self: CoopSync, runId: number, moveId: number): { Pending }
	if runId ~= self.runId then
		return {}
	end
	for index, pending in self.pending do
		if pending.moveId == moveId then
			table.remove(self.pending, index)
			return rebuild(self)
		end
	end
	return {} -- already dropped here when the partner's move arrived
end

-- How many of this player's moves are waiting for the server.
function CoopSync.pendingCount(self: CoopSync): number
	return #self.pending
end

-- The partner's seat.
function CoopSync.partnerSeat(self: CoopSync): number
	return 3 - self.seat
end

return CoopSync
