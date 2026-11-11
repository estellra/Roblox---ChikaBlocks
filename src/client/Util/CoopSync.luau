--!strict
-- The client's copy of a Co-op run, as pure logic so Lune can test it. Two layers:
--   confirmed  what the server has told us, applied move by move in the server's order (`seq`)
--   pending    this player's own moves that were sent and not confirmed yet (usually none or one)
-- What is shown is the confirmed layer with the pending moves played on top, so the player's own pieces land
-- at once. When a move of the partner's arrives it goes into the confirmed layer and the pending moves are
-- played again on top; any that no longer fit (the partner got there first) are dropped at once, which sends the
-- piece back to its tray without waiting for the server's CoopReject. The server decides the score and the sets;
-- a gap in `seq`, a move that doesn't fit our copy or a score that differs means we are out of step, and the
-- caller asks for the full state.
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

export type Pending = { moveId: number, slot: number, x: number, y: number }

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
		seq: number, -- the last confirmed move
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

-- Builds the shown layer: the confirmed one with the pending moves played again. Moves that no longer fit are
-- taken out of `pending` and returned.
local function rebuild(self: CoopSync): { Pending }
	local CoopSession = self.deps.CoopSession
	local shown = CoopSession.fromSnapshot(self.confirmed:snapshot(), noSet)
	local dropped: { Pending } = {}
	local kept: { Pending } = {}
	for _, move in self.pending do
		if shown:place(self.seat, move.slot, move.x, move.y) then
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
