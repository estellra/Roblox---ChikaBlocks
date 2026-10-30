--!strict
-- Points for a single placement. Pure: takes the combo state in, returns the next one.

local Config = require("./Config")

export type ComboState = {
	combo: number, -- consecutive clearing placements (with grace moves in between)
	movesSinceClear: number,
}

export type MoveScore = {
	placementPoints: number,
	clearPoints: number,
	bonusPoints: number,
	total: number,
	nextCombo: ComboState,
}

local Scoring = {}

function Scoring.newCombo(): ComboState
	return { combo = 0, movesSinceClear = 0 }
end

-- Base points for clearing this many lines at once (before the combo multiplier).
function Scoring.clearBase(lineCount: number): number
	if lineCount <= 0 then
		return 0
	end
	local points = Config.CLEAR_POINTS
	return points[math.min(lineCount, #points)]
end

function Scoring.scoreMove(
	state: ComboState,
	cellsPlaced: number,
	linesCleared: number,
	boardCleared: boolean
): MoveScore
	local placementPoints = cellsPlaced * Config.SCORE_PER_CELL

	if linesCleared <= 0 then
		local movesSinceClear = state.movesSinceClear + 1
		return {
			placementPoints = placementPoints,
			clearPoints = 0,
			bonusPoints = 0,
			total = placementPoints,
			nextCombo = {
				combo = if movesSinceClear >= Config.COMBO_GRACE_MOVES then 0 else state.combo,
				movesSinceClear = movesSinceClear,
			},
		}
	end

	local combo = state.combo + 1
	local multiplier = 1 + Config.COMBO_STEP * (combo - 1)
	local clearPoints = math.floor(Scoring.clearBase(linesCleared) * multiplier)
	local bonusPoints = if boardCleared then Config.BOARD_CLEAR_BONUS else 0
	return {
		placementPoints = placementPoints,
		clearPoints = clearPoints,
		bonusPoints = bonusPoints,
		total = placementPoints + clearPoints + bonusPoints,
		nextCombo = { combo = combo, movesSinceClear = 0 },
	}
end

return Scoring
