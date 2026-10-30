--!strict
-- Deals sets of pieces. Each piece's size group is drawn by share (bigger pieces as the score rises), and
-- each set must pass a fairness check that loosens as the score rises:
--   WholeSet  - all pieces can be placed in some order, counting line clears in between (also for revives)
--   EachPiece - every piece fits somewhere on the current board
--   AnyPiece  - at least one piece fits
-- The fairness checks visit many positions, so they work on 8-bit row masks instead of Board cells.

local Board = require("./Board")
local Config = require("./Config")
local Pieces = require("./Pieces")
local Rng = require("./Rng")

type Board = Board.Board
type Piece = Pieces.Piece
type SizeGroup = Pieces.SizeGroup
type Rng = Rng.Rng

export type DealReason = "Normal" | "Revive"
export type FairnessTier = "WholeSet" | "EachPiece" | "AnyPiece"
export type GroupShares = { [SizeGroup]: number }
export type SetSource = (board: Board, score: number, reason: DealReason) -> { Piece }

type Rows = { number } -- one mask per board row; bit x is set when cell x is filled
type Masks = { number } -- one mask per piece row

local SETTINGS = Config.GENERATOR
local SIZE = Config.GRID_SIZE
local FULL_ROW = 2 ^ SIZE - 1
local GROUPS: { SizeGroup } = { "Small", "Medium", "Large", "Huge" }
local SMALL_ONLY: GroupShares = { Small = 1, Medium = 0, Large = 0, Huge = 0 }

local piecesByGroup: { [SizeGroup]: { Piece } } = { Small = {}, Medium = {}, Large = {}, Huge = {} }
local masksByPiece: { [Piece]: Masks } = {}
for _, piece in Pieces.ALL do
	table.insert(piecesByGroup[piece.size], piece)
	local masks = table.create(piece.height, 0)
	for _, cell in piece.cells do
		masks[cell.y + 1] = bit32.bor(masks[cell.y + 1], bit32.lshift(1, cell.x))
	end
	masksByPiece[piece] = masks
end

local function toRows(board: Board): Rows
	local rows = table.create(SIZE, 0)
	for y = 0, SIZE - 1 do
		local mask = 0
		for x = 0, SIZE - 1 do
			if Board.get(board, x, y) ~= 0 then
				mask = bit32.bor(mask, bit32.lshift(1, x))
			end
		end
		rows[y + 1] = mask
	end
	return rows
end

local function fits(rows: Rows, masks: Masks, x: number, y: number): boolean
	for r, mask in masks do
		if bit32.band(rows[y + r], bit32.lshift(mask, x)) ~= 0 then
			return false
		end
	end
	return true
end

local function fitsAnywhere(rows: Rows, piece: Piece): boolean
	local masks = masksByPiece[piece]
	for y = 0, SIZE - piece.height do
		for x = 0, SIZE - piece.width do
			if fits(rows, masks, x, y) then
				return true
			end
		end
	end
	return false
end

-- Places the piece on a copy of the rows, then clears full rows and columns together.
-- Returns the new rows and whether anything was cleared.
local function placeAndClear(rows: Rows, masks: Masks, x: number, y: number): (Rows, boolean)
	local nextRows = table.clone(rows)
	for r, mask in masks do
		nextRows[y + r] = bit32.bor(nextRows[y + r], bit32.lshift(mask, x))
	end
	local fullCols = FULL_ROW
	local anyFullRow = false
	for _, row in nextRows do
		fullCols = bit32.band(fullCols, row)
		if row == FULL_ROW then
			anyFullRow = true
		end
	end
	if not anyFullRow and fullCols == 0 then
		return nextRows, false
	end
	local keep = bit32.band(bit32.bnot(fullCols), FULL_ROW)
	for i, row in nextRows do
		nextRows[i] = if row == FULL_ROW then 0 else bit32.band(row, keep)
	end
	return nextRows, true
end

-- Depth-first search for an order and positions that place every piece. Gives up (returns false) once it
-- has tried nodeBudget placements, which only makes the caller draw another set.
local function solvable(rows: Rows, pieces: { Piece }, nodeBudget: number): boolean
	local count = #pieces
	if count == 0 then
		return true
	end
	local used = table.create(count, false)
	local nodes = 0
	local exhausted = false

	local function search(current: Rows, remaining: number): boolean
		-- A piece that fits nowhere ("stuck") can only fit after some line clears, because filling cells
		-- never makes room. So a placement that clears nothing is pointless when every other remaining
		-- piece is stuck: none of them could clear a line afterwards.
		local stuckCount = 0
		for i, piece in pieces do
			if not used[i] and not fitsAnywhere(current, piece) then
				stuckCount += 1
			end
		end
		if remaining == 1 then
			return stuckCount == 0
		end
		local needsClear = stuckCount > 0 and stuckCount == remaining - 1

		local tried: { [Piece]: boolean } = {}
		for i, piece in pieces do
			if used[i] or tried[piece] then
				continue
			end
			tried[piece] = true
			used[i] = true
			local masks = masksByPiece[piece]
			for y = 0, SIZE - piece.height do
				for x = 0, SIZE - piece.width do
					if not fits(current, masks, x, y) then
						continue
					end
					nodes += 1
					if nodes > nodeBudget then
						exhausted = true
					end
					if exhausted then
						used[i] = false
						return false
					end
					local nextRows, cleared = placeAndClear(current, masks, x, y)
					if (cleared or not needsClear) and search(nextRows, remaining - 1) then
						used[i] = false
						return true
					end
				end
			end
			used[i] = false
		end
		return false
	end

	return search(rows, count)
end

local function drawGroup(rng: Rng, shares: GroupShares, allowHuge: boolean): SizeGroup
	local total = 0
	for _, group in GROUPS do
		if group ~= "Huge" or allowHuge then
			total += shares[group]
		end
	end
	local roll = rng:nextFloat() * total
	local lastWithShare: SizeGroup = "Small"
	for _, group in GROUPS do
		if (group ~= "Huge" or allowHuge) and shares[group] > 0 then
			lastWithShare = group
			roll -= shares[group]
			if roll < 0 then
				return group
			end
		end
	end
	return lastWithShare -- floating point leftovers
end

local function drawSet(rng: Rng, shares: GroupShares): { Piece }
	local set = table.create(Config.PIECES_PER_SET)
	local hugeCount = 0
	for i = 1, Config.PIECES_PER_SET do
		local group = drawGroup(rng, shares, hugeCount < SETTINGS.MAX_HUGE_PER_SET)
		if group == "Huge" then
			hugeCount += 1
		end
		local candidates = piecesByGroup[group]
		set[i] = candidates[rng:nextInt(1, #candidates)]
	end
	return set
end

local function meetsTier(rows: Rows, set: { Piece }, tier: FairnessTier): boolean
	if tier == "WholeSet" then
		return solvable(rows, set, SETTINGS.SOLVER_NODE_BUDGET)
	elseif tier == "EachPiece" then
		for _, piece in set do
			if not fitsAnywhere(rows, piece) then
				return false
			end
		end
		return true
	end
	for _, piece in set do
		if fitsAnywhere(rows, piece) then
			return true
		end
	end
	return false
end

local Generator = {}

-- Normalized share of each size group for one draw.
function Generator.groupShares(score: number, fillRatio: number): GroupShares
	local t = math.clamp(score / SETTINGS.DIFFICULTY_MAX_SCORE, 0, 1)
	local shares: GroupShares = {}
	local total = 0
	for _, group in GROUPS do
		local easy = SETTINGS.GROUP_SHARES_EASY[group]
		local share = easy + (SETTINGS.GROUP_SHARES_HARD[group] - easy) * t
		if group == "Small" and fillRatio > SETTINGS.MERCY_FILL_RATIO then
			share *= SETTINGS.MERCY_SMALL_MULTIPLIER
		end
		shares[group] = share
		total += share
	end
	for _, group in GROUPS do
		shares[group] /= total
	end
	return shares
end

function Generator.fairnessTier(score: number, reason: DealReason): FairnessTier
	if reason == "Revive" or score < SETTINGS.WHOLE_SET_BELOW_SCORE then
		return "WholeSet"
	elseif score < SETTINGS.EACH_PIECE_BELOW_SCORE then
		return "EachPiece"
	end
	return "AnyPiece"
end

function Generator.isSetSolvable(board: Board, pieces: { Piece }, nodeBudget: number?): boolean
	return solvable(toRows(board), pieces, nodeBudget or SETTINGS.SOLVER_NODE_BUDGET)
end

function Generator.nextSet(board: Board, score: number, rng: Rng, reason: DealReason): { Piece }
	local tier = Generator.fairnessTier(score, reason)
	local rows = toRows(board)
	-- A revive should feel like a fresh start, so it draws with the easy shares.
	local shares = Generator.groupShares(if reason == "Revive" then 0 else score, Board.fillRatio(board))

	for _ = 1, SETTINGS.MAX_ATTEMPTS do
		local set = drawSet(rng, shares)
		if meetsTier(rows, set, tier) then
			return set
		end
	end
	for _ = 1, SETTINGS.FALLBACK_ATTEMPTS do
		local set = drawSet(rng, SMALL_ONLY)
		if meetsTier(rows, set, tier) then
			return set
		end
	end
	-- Always placeable: full lines are cleared after every move, so each row keeps at least one empty cell.
	return table.create(Config.PIECES_PER_SET, Pieces.BY_ID.Dot)
end

function Generator.newSource(rng: Rng): SetSource
	return function(board: Board, score: number, reason: DealReason): { Piece }
		return Generator.nextSet(board, score, rng, reason)
	end
end

return Generator
