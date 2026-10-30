--!strict
-- Gameplay numbers that get tuned live in this one module.

local Config = {
	GRID_SIZE = 8,
	PIECES_PER_SET = 3,
	MAX_REVIVES_PER_RUN = 2,

	-- Scoring
	SCORE_PER_CELL = 1,
	CLEAR_POINTS = table.freeze({ 10, 30, 60, 100, 150, 210 }), -- by lines cleared at once
	COMBO_STEP = 0.5, -- clear multiplier grows by this per combo level
	COMBO_GRACE_MOVES = 3, -- placements without a clear before the combo resets
	BOARD_CLEAR_BONUS = 300,
}

return table.freeze(Config)
