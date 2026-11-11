--!strict
-- One Co-op run: a GameSession that deals four pieces per set to two players ("seats"). Slots 1-2 belong to
-- seat 1 (the player who invited), slots 3-4 to seat 2. A player may only place from their own slots, and a new
-- set comes only once all four are placed. The loss rule is the plain one: the run ends when no piece, of either
-- player, fits.
--
-- A player can leave mid-run (release). The one who stays takes over the leaver's pieces and plays on, but the
-- run's score stops counting for records and boards the moment the partner leaves (countedScore), so a second
-- account can't be used to climb the Co-op board alone.
--
-- Shared by both sides like GameSession: the server's source deals right away, the client's returns nil and waits
-- for receiveSet(). This module only holds the rules; who is in which seat, timers and remotes live elsewhere.

local Board = require("./Board")
local Config = require("./Config")
local GameSession = require("./GameSession")
local Generator = require("./Generator")
local Pieces = require("./Pieces")
local Rng = require("./Rng")

type Board = Board.Board
type Piece = Pieces.Piece
type Rng = Rng.Rng
type SetSource = Generator.SetSource

local SEATS = 2
local SET_SIZE = Config.COOP.SET_SIZE
local SLOTS_PER_SEAT = SET_SIZE // SEATS

-- Plain-data copy of a run, safe to send through a remote.
export type Snapshot = {
	game: GameSession.Snapshot, -- the shared board, tray, score and combo
	present: { boolean }, -- by seat: the player is still in the run
	countedScore: number,
	contribution: { number }, -- by seat: points the player's own placements earned
}

local CoopSession = {}
CoopSession.__index = CoopSession

export type CoopSession = typeof(setmetatable(
	{} :: {
		session: GameSession.GameSession,
		present: { boolean },
		countedScore: number, -- the score that counts for records: follows `score` while both are in, then stops
		contribution: { number }, -- sums to session.score, so the Game Over screen can split the team's points
	},
	CoopSession
))

if SET_SIZE % SEATS ~= 0 then
	error(`Config.COOP.SET_SIZE ({SET_SIZE}) must split evenly between {SEATS} players`)
end

-- A source that deals Co-op sets: four pieces, with the generator tuned in Config.COOP.GENERATOR.
function CoopSession.newSource(rng: Rng): SetSource
	return Generator.newSource(rng, SET_SIZE, Config.COOP.GENERATOR)
end

-- The seat a slot belongs to (1 or 2), or nil when it isn't a slot.
function CoopSession.seatOf(slot: unknown): number?
	if typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > SET_SIZE then
		return nil
	end
	local slotIndex = slot :: number
	return (slotIndex - 1) // SLOTS_PER_SEAT + 1
end

-- The slots a seat owns at the start of every set.
function CoopSession.slotsOf(seat: number): { number }
	local slots = table.create(SLOTS_PER_SEAT)
	for i = 1, SLOTS_PER_SEAT do
		slots[i] = (seat - 1) * SLOTS_PER_SEAT + i
	end
	return slots
end

function CoopSession.new(setSource: SetSource, initialBoard: Board?): CoopSession
	return setmetatable({
		session = GameSession.new(setSource, initialBoard, SET_SIZE),
		present = table.create(SEATS, true),
		countedScore = 0,
		contribution = table.create(SEATS, 0),
	}, CoopSession)
end

-- Rebuilds a run from snapshot() output (e.g. the server's state, received by the client).
function CoopSession.fromSnapshot(snapshot: Snapshot, setSource: SetSource): CoopSession
	local session = GameSession.fromSnapshot(snapshot.game, setSource)
	if session.setSize ~= SET_SIZE then
		error(`snapshot deals {session.setSize} pieces per set, expected {SET_SIZE}`)
	end
	if #snapshot.present ~= SEATS or #snapshot.contribution ~= SEATS then
		error(`snapshot has {#snapshot.present} seats and {#snapshot.contribution} contributions, expected {SEATS}`)
	end
	if typeof(snapshot.countedScore) ~= "number" then
		error("snapshot has no counted score")
	end
	local present, contribution = table.create(SEATS, false), table.create(SEATS, 0)
	for seat = 1, SEATS do
		present[seat] = snapshot.present[seat] == true
		if typeof(snapshot.contribution[seat]) ~= "number" then
			error(`snapshot has no contribution for seat {seat}`)
		end
		contribution[seat] = snapshot.contribution[seat]
	end
	return setmetatable({
		session = session,
		present = present,
		countedScore = snapshot.countedScore,
		contribution = contribution,
	}, CoopSession)
end

function CoopSession.snapshot(self: CoopSession): Snapshot
	return {
		game = self.session:snapshot(),
		present = table.clone(self.present),
		countedScore = self.countedScore,
		contribution = table.clone(self.contribution),
	}
end

-- Fills an empty tray that is awaiting a set (the client's, once the server has dealt one).
function CoopSession.receiveSet(self: CoopSession, pieces: { Piece }): boolean
	return self.session:receiveSet(pieces)
end

-- Whether `seat` may place the piece in `slot`: they are still in the run, and the slot is theirs or the other
-- player has left. (Whether there is a piece there, and whether it fits, is another matter.)
function CoopSession.mayPlace(self: CoopSession, seat: unknown, slot: unknown): boolean
	local owner = CoopSession.seatOf(slot)
	if owner == nil or typeof(seat) ~= "number" or self.present[seat] ~= true then
		return false
	end
	return owner == seat or self.present[owner] ~= true
end

function CoopSession.canPlace(self: CoopSession, seat: unknown, slot: unknown, x: unknown, y: unknown): boolean
	return CoopSession.mayPlace(self, seat, slot) and self.session:canPlace(slot, x, y)
end

-- Places a piece for `seat`. Nil, and nothing changes, when the seat or slot is wrong or the move is invalid.
function CoopSession.place(
	self: CoopSession,
	seat: unknown,
	slot: unknown,
	x: unknown,
	y: unknown
): GameSession.PlaceResult?
	if not CoopSession.mayPlace(self, seat, slot) then
		return nil
	end
	local result = self.session:place(slot, x, y)
	if result == nil then
		return nil
	end
	local seatIndex = seat :: number
	self.contribution[seatIndex] += result.points
	if self.present[1] and self.present[2] then
		self.countedScore = self.session.score
	end
	return result
end

-- Whether `seat` has a piece they may place that fits somewhere right now.
function CoopSession.hasMove(self: CoopSession, seat: unknown): boolean
	for slot = 1, SET_SIZE do
		if CoopSession.mayPlace(self, seat, slot) and self.session:hasPlacement(slot) then
			return true
		end
	end
	return false
end

-- The player in `seat` leaves the run. The other player can place every slot from now on, and the score that
-- counts is whatever it is right now. False when that seat isn't in the run (so a second call changes nothing).
function CoopSession.release(self: CoopSession, seat: unknown): boolean
	if typeof(seat) ~= "number" or self.present[seat] ~= true then
		return false
	end
	if self.present[1] and self.present[2] then
		self.countedScore = self.session.score
	end
	self.present[seat :: number] = false
	return true
end

return CoopSession
