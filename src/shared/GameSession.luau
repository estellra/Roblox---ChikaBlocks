--!strict
-- One run of the game: board, tray, score, combo, game over and revive.
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

local SET_SIZE = Config.PIECES_PER_SET

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

-- Plain-data copy of a session, safe to send through a remote.
export type Snapshot = {
	cells: { number },
	tray: { string | false }, -- piece ids
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
		tray: { Piece | false }, -- false marks a slot already played this set
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

local function emptyTray(): { Piece | false }
	return table.create(SET_SIZE, false) :: any
end

local function deal(session: GameSession, reason: DealReason)
	local set = session.setSource(session.board, session.score, reason)
	local tray = emptyTray()
	if set == nil then
		session.tray = tray
		session.awaitingSet = true
		return
	end
	if #set ~= SET_SIZE then
		error(`set source returned {#set} pieces, expected {SET_SIZE}`)
	end
	for i, piece in set do
		tray[i] = piece
	end
	session.tray = tray
	session.awaitingSet = false
end

local function refreshGameOver(session: GameSession)
	if session.awaitingSet then
		session.isOver = false
		return
	end
	for _, piece in session.tray do
		if piece and Board.hasAnyPlacement(session.board, piece) then
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

local function isSlot(value: unknown): boolean
	return typeof(value) == "number" and value == math.floor(value) and value >= 1 and value <= SET_SIZE
end

function GameSession.new(setSource: SetSource, initialBoard: Board?): GameSession
	local self = setmetatable({
		board = if initialBoard then Board.clone(initialBoard) else Board.new(),
		tray = emptyTray(),
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

-- Rebuilds a session from snapshot() output (e.g. the server's state, received by the client).
function GameSession.fromSnapshot(snapshot: Snapshot, setSource: SetSource): GameSession
	if #snapshot.cells ~= Config.GRID_SIZE * Config.GRID_SIZE then
		error(`snapshot has {#snapshot.cells} cells`)
	end
	local tray = emptyTray()
	for i = 1, SET_SIZE do
		local id = snapshot.tray[i]
		if id then
			tray[i] = Pieces.BY_ID[id] or error(`snapshot has unknown piece {id}`)
		end
	end
	return setmetatable({
		board = { cells = table.clone(snapshot.cells) },
		tray = tray,
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
	local tray: { string | false } = table.create(SET_SIZE)
	for i, piece in self.tray do
		tray[i] = if piece then piece.id else false
	end
	return {
		cells = table.clone(self.board.cells),
		tray = tray,
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
	if not self.awaitingSet or #pieces ~= SET_SIZE then
		return false
	end
	local tray = emptyTray()
	for i, piece in pieces do
		tray[i] = piece
	end
	self.tray = tray
	self.awaitingSet = false
	refreshGameOver(self)
	return true
end

function GameSession.canPlace(self: GameSession, slot: unknown, x: unknown, y: unknown): boolean
	if self.isOver or not isSlot(slot) or typeof(x) ~= "number" or typeof(y) ~= "number" then
		return false
	end
	local piece = self.tray[slot :: number]
	return piece ~= false and Board.canPlace(self.board, piece, x, y)
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
