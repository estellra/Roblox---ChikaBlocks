--!strict
-- The client's copy of its own side of a PVP match (docs/PHASE6.md, M26), as pure logic so Lune can test it. The
-- player's moves are predicted on a PvpSession at once and sent; the server answers each in order with a "result"
-- that carries the score it worked out, the garbage queue, and, at the end of a set, the garbage that went in and the
-- next set (or, when nothing fit, the cleared board's new set). Garbage the opponent sends arrives as "incoming".
-- Each side has its own board, so unlike CoopSync there is a single layer: own moves are applied at once, and the
-- server's results only add what the client can't know (sets, garbage holes) and check the score.
-- A result for a move we didn't make, a score that differs, or a set we expected and didn't get means we are out of
-- step: the caller asks for the full state. So does a move the server hasn't answered for a while (it was dropped).
-- The shared PvpSession module is passed in because shared and client code sit in different places on disk and in
-- the DataModel. Times are on the clock the caller uses for `now` (server time in the game).

export type Deps = { PvpSession: any }

-- What PvpEvent("start") and PvpEvent("state") carry (see PvpMatches.MatchState), times in server time.
export type State = {
	matchId: number,
	kind: string,
	seat: number,
	startAt: number,
	endAt: number,
	you: any, -- PvpSession.Snapshot
	opponent: any,
	ended: any?,
}

-- What PvpEvent("result") carries (see PvpMatches.PlaceOutcome).
export type Result = {
	matchId: number,
	moveIndex: number,
	score: number,
	sent: number, -- garbage this move sent and cancelled, as the server worked it out: our copy may have had an
	cancelled: number, -- older garbage queue when it predicted the move (an "incoming" was still on its way)
	pending: { number },
	refill: { garbage: { { side: number, hole: number } }, set: { string } }?,
	stuck: { set: { string }, lockedUntil: number }?,
}

export type Applied =
	{ kind: "applied", refill: any?, stuck: any? }
	| { kind: "ignored" } -- a result we have already, or from another match
	| { kind: "resync", reason: string }

type Unconfirmed = { moveIndex: number, score: number, sent: number, cancelled: number, sentAt: number }

local PvpSync = {}
PvpSync.__index = PvpSync

export type PvpSync = typeof(setmetatable(
	{} :: {
		deps: Deps,
		matchId: number,
		kind: string,
		seat: number,
		startAt: number,
		endAt: number,
		session: any, -- PvpSession
		unconfirmed: { Unconfirmed },
		ended: any?,
	},
	PvpSync
))

function PvpSync.new(deps: Deps, state: State): PvpSync
	local self = setmetatable({}, PvpSync) :: any
	self.deps = deps
	PvpSync.reset(self, state)
	return self
end

--- Rebuilds the copy from the server's state; moves not answered yet are forgotten.
function PvpSync.reset(self: PvpSync, state: State)
	self.matchId = state.matchId
	self.kind = state.kind
	self.seat = state.seat
	self.startAt = state.startAt
	self.endAt = state.endAt
	self.session = self.deps.PvpSession.fromSnapshot(state.you)
	self.unconfirmed = {}
	self.ended = state.ended
end

--- Whether the player may drag a piece now: the match has started and not ended, the tray isn't locked or empty,
--- and something in it fits. The client stops at endAt itself; the server's grace period is for moves on their way.
function PvpSync.canDrag(self: PvpSync, now: number): boolean
	local game = self.session.game
	return self.ended == nil
		and now >= self.startAt
		and now < self.endAt
		and not self.session:isLocked(now)
		and not game.awaitingSet
		and not game.isOver
end

--- Predicts a move. Returns the session's PlaceResult and the move index to send with it, or nil when the move
--- isn't possible now.
function PvpSync.place(self: PvpSync, slot: number, x: number, y: number, now: number): (any?, number?)
	if not self:canDrag(now) then
		return nil, nil
	end
	local moveIndex = self.session.game.moveCount
	local result = self.session:place(slot, x, y, now)
	if not result then
		return nil, nil
	end
	table.insert(self.unconfirmed, {
		moveIndex = moveIndex,
		score = self.session.game.score,
		sent = result.sent,
		cancelled = result.cancelled,
		sentAt = now,
	})
	return result, moveIndex
end

--- Turns a piece. Returns the RotateResult and the move index to send with it, or nil.
function PvpSync.rotate(self: PvpSync, slot: number, now: number): (any?, number?)
	if self.ended ~= nil or now >= self.endAt then
		return nil, nil
	end
	local moveIndex = self.session.game.moveCount
	local result = self.session:rotate(slot, now)
	if not result then
		return nil, nil
	end
	return result, moveIndex
end

--- Applies the server's answer to one of our moves.
function PvpSync.onResult(self: PvpSync, message: Result): Applied
	if message.matchId ~= self.matchId then
		return { kind = "ignored" }
	end
	local first = self.unconfirmed[1]
	if not first or message.moveIndex < first.moveIndex then
		if message.moveIndex < self.session.game.moveCount then
			return { kind = "ignored" }
		end
		return { kind = "resync", reason = "a result for a move we didn't make" }
	elseif message.moveIndex > first.moveIndex then
		return { kind = "resync", reason = "a move was skipped" }
	end
	table.remove(self.unconfirmed, 1)
	if message.score ~= first.score then
		return { kind = "resync", reason = "score differs" }
	end

	local session = self.session
	if typeof(message.sent) ~= "number" or typeof(message.cancelled) ~= "number" then
		return { kind = "resync", reason = "malformed result" }
	end
	session.sentTotal += message.sent - first.sent
	session.blockedTotal += message.cancelled - first.cancelled
	local refill, stuck = message.refill, message.stuck
	if (refill or stuck) and #self.unconfirmed > 0 then
		return { kind = "resync", reason = "moved past the end of a set" }
	end
	if refill and not session:deliver(refill.garbage, refill.set) then
		return { kind = "resync", reason = "refill doesn't apply" }
	end
	if stuck and not session:applyStuck(stuck.set, stuck.lockedUntil) then
		return { kind = "resync", reason = "unstick doesn't apply" }
	end
	if not session:setPending(message.pending) then
		return { kind = "resync", reason = "malformed garbage queue" }
	end
	if #self.unconfirmed == 0 and (session.game.awaitingSet or session.game.isOver) then
		return { kind = "resync", reason = "expected a new set" }
	end
	return { kind = "applied", refill = refill, stuck = stuck }
end

--- The opponent's attack changed our garbage queue. False when it is for another match or malformed.
function PvpSync.onIncoming(self: PvpSync, matchId: number, pending: unknown): boolean
	return matchId == self.matchId and self.session:setPending(pending)
end

--- The match ended (PvpEvent("end")); moves are no longer possible.
function PvpSync.onEnd(self: PvpSync, info: any)
	if info and info.matchId == self.matchId then
		self.ended = info
	end
end

--- Whether a move has waited more than `seconds` for its result (it was dropped: ask for the state).
function PvpSync.overdue(self: PvpSync, now: number, seconds: number): boolean
	local first = self.unconfirmed[1]
	return first ~= nil and now - first.sentAt > seconds
end

return PvpSync
