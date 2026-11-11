--!strict
-- One run of the game: board, tray, score, combo, rotation, game over and revive.
-- Where piece sets come from is injected (SetSource), so tests, the server and the client can each supply
-- their own. The server's source deals right away; the client's returns nil, leaving the tray empty
-- ("awaiting a set") until receiveSet() delivers what the server dealt. Moves arrive as untrusted values and
-- are validated here; invalid moves return nil and leave the session unchanged.

local Board = require("./Board")
local Config = require("./Config")
local Generator = require("./Generator")
local Pieces = require("./Pieces")
local Scoring = require("./Scoring")

type Board = Board.Board
type Piece = Pieces.Piece
type DealReason = Generator.DealReason
type SetSource = Generator.SetSource

export type PlaceResult = {
	slot: number,
	piece: Piece,
	x: number,
	y: number,
	clearedRows: { number },
	clearedCols: { number },
	cellsCleared: number,
	points: number,
	combo: number,
	boardCleared: boolean,
	refilled: boolean, -- the tray ran out and a new set was dealt right away
	awaitingSet: boolean, -- the tray ran out and the set source has none yet
	isOver: boolean,
}

export type RotateResult = {
	slot: number,
	piece: Piece, -- the piece now in the slot
	charged: ("free" | "paid")?, -- what the rotation cost; nil when the piece was already unlocked
}

-- Plain-data copy of a session, safe to send through a remote.
export type Snapshot = {
	cells: { number },
	tray: { string | false }, -- piece ids; one entry per slot, so its length is the set size
	unlocked: { boolean }, -- slots whose piece has been paid to rotate (it turns freely until placed)
	freeRotations: number, -- free rotations left in this run
	score: number,
	combo: number,
	movesSinceClear: number,
	isOver: boolean,
	awaitingSet: boolean,
	revivesUsed: number,
	moveCount: number,
}

local GameSession = {}
GameSession.__index = GameSession

export type GameSession = typeof(setmetatable(
	{} :: {
		board: Board,
		setSize: number, -- pieces per set: Config.PIECES_PER_SET for a solo run, more for Co-op
		tray: { Piece | false }, -- false marks a slot already played this set
		unlocked: { boolean },
		freeRotations: number,
		score: number,
		combo: Scoring.ComboState,
		isOver: boolean,
		awaitingSet: boolean,
		revivesUsed: number,
		moveCount: number,
		setSource: SetSource,
	},
	GameSession
))

local function emptyTray(setSize: number): { Piece | false }
	return table.create(setSize, false) :: any
end

local function lockedSlots(setSize: number): { boolean }
	return table.create(setSize, false)
end

local function checkSetSize(setSize: number)
	if setSize ~= math.floor(setSize) or setSize < 1 then
		error(`set size must be a positive integer, got {setSize}`)
	end
end

-- Whether the piece fits somewhere in the orientation it has now, or (once its rotation is paid for) in any.
local function canFit(board: Board.Board, piece: Piece, unlocked: boolean): boolean
	local current = piece
	for _ = 1, if unlocked then 4 else 1 do
		if Board.hasAnyPlacement(board, current) then
			return true
		end
		current = Pieces.rotateCW(current)
	end
	return false
end

local function deal(session: GameSession, reason: DealReason)
	local set = session.setSource(session.board, session.score, reason)
	local tray = emptyTray(session.setSize)
	if set == nil then
		session.tray = tray
		session.unlocked = lockedSlots(session.setSize)
		session.awaitingSet = true
		return
	end
	if #set ~= session.setSize then
		error(`set source returned {#set} pieces, expected {session.setSize}`)
	end
	for i, piece in set do
		tray[i] = piece
	end
	session.tray = tray
	session.unlocked = lockedSlots(session.setSize)
	session.awaitingSet = false
end

local function refreshGameOver(session: GameSession)
	if session.awaitingSet then
		session.isOver = false
		return
	end
	for slot, piece in session.tray do
		if piece and canFit(session.board, piece, session.unlocked[slot]) then
			session.isOver = false
			return
		end
	end
	session.isOver = true
end

local function isTrayEmpty(session: GameSession): boolean
	for _, piece in session.tray do
		if piece then
			return false
		end
	end
	return true
end

local function isSlot(session: GameSession, value: unknown): boolean
	return typeof(value) == "number" and value == math.floor(value) and value >= 1 and value <= session.setSize
end

-- `setSize` is how many pieces each set holds (default Config.PIECES_PER_SET); Co-op deals 4.
function GameSession.new(setSource: SetSource, initialBoard: Board?, setSize: number?): GameSession
	local size = setSize or Config.PIECES_PER_SET
	checkSetSize(size)
	local self = setmetatable({
		board = if initialBoard then Board.clone(initialBoard) else Board.new(),
		setSize = size,
		tray = emptyTray(size),
		unlocked = lockedSlots(size),
		freeRotations = Config.FREE_ROTATIONS_PER_RUN,
		score = 0,
		combo = Scoring.newCombo(),
		isOver = false,
		awaitingSet = false,
		revivesUsed = 0,
		moveCount = 0,
		setSource = setSource,
	}, GameSession)
	deal(self, "Normal")
	refreshGameOver(self)
	return self
end

-- Rebuilds a session from snapshot() output (e.g. the server's state, received by the client). The set size is
-- the length of the snapshot's tray.
function GameSession.fromSnapshot(snapshot: Snapshot, setSource: SetSource): GameSession
	if #snapshot.cells ~= Config.GRID_SIZE * Config.GRID_SIZE then
		error(`snapshot has {#snapshot.cells} cells`)
	end
	local setSize = #snapshot.tray
	checkSetSize(setSize)
	local tray = emptyTray(setSize)
	for i = 1, setSize do
		local id = snapshot.tray[i]
		if id then
			tray[i] = Pieces.BY_ID[id] or error(`snapshot has unknown piece {id}`)
		end
	end
	local unlocked = lockedSlots(setSize)
	for i = 1, setSize do
		unlocked[i] = snapshot.unlocked[i] == true
	end
	return setmetatable({
		board = { cells = table.clone(snapshot.cells) },
		setSize = setSize,
		tray = tray,
		unlocked = unlocked,
		freeRotations = snapshot.freeRotations,
		score = snapshot.score,
		combo = { combo = snapshot.combo, movesSinceClear = snapshot.movesSinceClear },
		isOver = snapshot.isOver,
		awaitingSet = snapshot.awaitingSet,
		revivesUsed = snapshot.revivesUsed,
		moveCount = snapshot.moveCount,
		setSource = setSource,
	}, GameSession)
end

function GameSession.snapshot(self: GameSession): Snapshot
	local tray: { string | false } = table.create(self.setSize)
	for i, piece in self.tray do
		tray[i] = if piece then piece.id else false
	end
	return {
		cells = table.clone(self.board.cells),
		tray = tray,
		unlocked = table.clone(self.unlocked),
		freeRotations = self.freeRotations,
		score = self.score,
		combo = self.combo.combo,
		movesSinceClear = self.combo.movesSinceClear,
		isOver = self.isOver,
		awaitingSet = self.awaitingSet,
		revivesUsed = self.revivesUsed,
		moveCount = self.moveCount,
	}
end

-- Fills an empty tray that is awaiting a set. Returns false (and changes nothing) otherwise.
function GameSession.receiveSet(self: GameSession, pieces: { Piece }): boolean
	if not self.awaitingSet or #pieces ~= self.setSize then
		return false
	end
	local tray = emptyTray(self.setSize)
	for i, piece in pieces do
		tray[i] = piece
	end
	self.tray = tray
	self.unlocked = lockedSlots(self.setSize)
	self.awaitingSet = false
	refreshGameOver(self)
	return true
end

function GameSession.canPlace(self: GameSession, slot: unknown, x: unknown, y: unknown): boolean
	if self.isOver or not isSlot(self, slot) or typeof(x) ~= "number" or typeof(y) ~= "number" then
		return false
	end
	local piece = self.tray[slot :: number]
	return piece ~= false and Board.canPlace(self.board, piece, x, y)
end

-- Whether the piece in `slot` fits somewhere on the board: as it lies, or turned any way once its rotation is paid for.
-- This is the test game over is made of: the run ends when no slot has a placement.
function GameSession.hasPlacement(self: GameSession, slot: unknown): boolean
	if not isSlot(self, slot) then
		return false
	end
	local slotIndex = slot :: number
	local piece = self.tray[slotIndex]
	return piece ~= false and canFit(self.board, piece, self.unlocked[slotIndex])
end

function GameSession.place(self: GameSession, slot: unknown, x: unknown, y: unknown): PlaceResult?
	if not self:canPlace(slot, x, y) then
		return nil
	end
	local slotIndex, px, py = slot :: number, x :: number, y :: number
	local piece = self.tray[slotIndex] :: Piece

	Board.place(self.board, piece, px, py, piece.color)
	local lines = Board.findCompleteLines(self.board)
	local cellsCleared = Board.clearLines(self.board, lines)
	local lineCount = #lines.rows + #lines.cols
	local boardCleared = lineCount > 0 and Board.isEmpty(self.board)

	local move = Scoring.scoreMove(self.combo, #piece.cells, lineCount, boardCleared)
	self.score += move.total
	self.combo = move.nextCombo
	self.moveCount += 1
	self.tray[slotIndex] = false
	self.unlocked[slotIndex] = false

	local refilled = false
	if isTrayEmpty(self) then
		deal(self, "Normal")
		refilled = not self.awaitingSet
	end
	refreshGameOver(self)

	return {
		slot = slotIndex,
		piece = piece,
		x = px,
		y = py,
		clearedRows = lines.rows,
		clearedCols = lines.cols,
		cellsCleared = cellsCleared,
		points = move.total,
		combo = move.nextCombo.combo,
		boardCleared = boardCleared,
		refilled = refilled,
		awaitingSet = self.awaitingSet,
		isOver = self.isOver,
	}
end

-- Turns the piece in `slot` a quarter clockwise, paying from the wallet the caller passes in: `free` rotations the
-- player has left and `paid` ones they bought earlier. The first turn of a piece costs a rotation, a free one if
-- there is any, else a bought one; after that the piece turns freely until it is placed. This only turns the piece
-- and says what it cost ("free" or "paid"); taking that from the wallet is up to the caller (a Co-op run has one
-- wallet per player, so the session can't keep it). Nil, and nothing changes, when the piece looks the same
-- turned, the run is over, or the wallet can't pay.
function GameSession.rotateWith(self: GameSession, slot: unknown, free: unknown, paid: unknown): RotateResult?
	if self.isOver or self.awaitingSet or not isSlot(self, slot) then
		return nil
	end
	local slotIndex = slot :: number
	local piece = self.tray[slotIndex]
	if not piece or not Pieces.canRotate(piece) then
		return nil
	end

	local charged: ("free" | "paid")? = nil
	if not self.unlocked[slotIndex] then
		if typeof(free) == "number" and free > 0 then
			charged = "free"
		elseif typeof(paid) == "number" and paid > 0 then
			charged = "paid"
		else
			return nil
		end
		self.unlocked[slotIndex] = true
	end

	local turned = Pieces.rotateCW(piece)
	self.tray[slotIndex] = turned
	return { slot = slotIndex, piece = turned, charged = charged }
end

-- A solo turn: the run's own free rotations first, then one of the `paidAvailable` the player bought earlier (the
-- caller spends that one when the result says "paid"). See rotateWith.
function GameSession.rotate(self: GameSession, slot: unknown, paidAvailable: unknown): RotateResult?
	local result = GameSession.rotateWith(self, slot, self.freeRotations, paidAvailable)
	if result and result.charged == "free" then
		self.freeRotations -= 1
	end
	return result
end

-- Clears the middle of the board, resets the combo and deals a set that can all be placed.
-- Only allowed after game over and at most Config.MAX_REVIVES_PER_RUN times. Payment is checked elsewhere.
function GameSession.revive(self: GameSession): boolean
	if not self.isOver or self.revivesUsed >= Config.MAX_REVIVES_PER_RUN then
		return false
	end
	local size = Config.REVIVE_CLEAR_SIZE
	local start = (Config.GRID_SIZE - size) // 2
	Board.clearRect(self.board, start, start, size, size)
	self.revivesUsed += 1
	self.combo = Scoring.newCombo()
	deal(self, "Revive")
	refreshGameOver(self)
	return true
end

return GameSession
