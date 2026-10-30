--!strict
-- One run of the game: board, tray, score, combo, game over and revive.
-- Where piece sets come from is injected (SetSource), so tests, the local prototype and later the server
-- can each supply their own. Moves arrive as untrusted values and are validated here; invalid moves return
-- nil and leave the session unchanged.

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
	refilled: boolean, -- the tray was empty and a new set was dealt
	isOver: boolean,
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
		revivesUsed: number,
		moveCount: number,
		setSource: SetSource,
	},
	GameSession
))

local function deal(session: GameSession, reason: DealReason)
	local set = session.setSource(session.board, session.score, reason)
	if #set ~= Config.PIECES_PER_SET then
		error(`set source returned {#set} pieces, expected {Config.PIECES_PER_SET}`)
	end
	local tray: { Piece | false } = table.create(Config.PIECES_PER_SET)
	for i, piece in set do
		tray[i] = piece
	end
	session.tray = tray
end

local function refreshGameOver(session: GameSession)
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
	return typeof(value) == "number" and value == math.floor(value) and value >= 1 and value <= Config.PIECES_PER_SET
end

function GameSession.new(setSource: SetSource, initialBoard: Board?): GameSession
	local self = setmetatable({
		board = if initialBoard then Board.clone(initialBoard) else Board.new(),
		tray = {},
		score = 0,
		combo = Scoring.newCombo(),
		isOver = false,
		revivesUsed = 0,
		moveCount = 0,
		setSource = setSource,
	}, GameSession)
	deal(self, "Normal")
	refreshGameOver(self)
	return self
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

	local refilled = isTrayEmpty(self)
	if refilled then
		deal(self, "Normal")
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
