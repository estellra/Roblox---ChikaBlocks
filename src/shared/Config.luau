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

	-- Piece colors are fixed per shape family (see Pieces); the client maps 1..COLOR_COUNT to its palette.
	COLOR_COUNT = 8,

	-- Revive clears a square of this size in the middle of the board.
	REVIVE_CLEAR_SIZE = 4,

	-- Progression (see Progression): a run earns floor(score / EXP_SCORE_DIVISOR) EXP; going from level n
	-- to n + 1 takes LEVEL_EXP_BASE + LEVEL_EXP_STEP * (n - 1) EXP.
	EXP_SCORE_DIVISOR = 10,
	LEVEL_EXP_BASE = 100,
	LEVEL_EXP_STEP = 50,

	-- Rewards for reaching a best score or a level. Ordered by rank: the player's title is the last one they
	-- have claimed. badgeId is 0 until the badge is created in Creator Hub. Never change an id once shipped
	-- (saved data refers to it); a cosmetic reward per milestone comes with phase 4.
	MILESTONES = table.freeze({
		table.freeze({ id = "score1000", kind = "score", threshold = 1000, title = "Block Rookie", badgeId = 0 }),
		table.freeze({ id = "level5", kind = "level", threshold = 5, title = "Regular", badgeId = 0 }),
		table.freeze({ id = "score5000", kind = "score", threshold = 5000, title = "Line Clearer", badgeId = 0 }),
		table.freeze({ id = "level10", kind = "level", threshold = 10, title = "Puzzler", badgeId = 0 }),
		table.freeze({ id = "score10000", kind = "score", threshold = 10000, title = "Combo Master", badgeId = 0 }),
		table.freeze({ id = "level20", kind = "level", threshold = 20, title = "Block Smith", badgeId = 0 }),
		table.freeze({ id = "score25000", kind = "score", threshold = 25000, title = "Grid Legend", badgeId = 0 }),
		table.freeze({ id = "level30", kind = "level", threshold = 30, title = "Veteran", badgeId = 0 }),
		table.freeze({ id = "level50", kind = "level", threshold = 50, title = "Block Master", badgeId = 0 }),
	}),

	GENERATOR = table.freeze({
		-- Share of each size group per piece drawn, interpolated from EASY at score 0 to HARD at this score.
		DIFFICULTY_MAX_SCORE = 8000,
		GROUP_SHARES_EASY = table.freeze({ Small = 0.30, Medium = 0.45, Large = 0.20, Huge = 0.05 }),
		GROUP_SHARES_HARD = table.freeze({ Small = 0.15, Medium = 0.40, Large = 0.33, Huge = 0.12 }),
		MAX_HUGE_PER_SET = 1,

		-- Mercy: on a crowded board, small pieces get more likely.
		MERCY_FILL_RATIO = 0.6,
		MERCY_SMALL_MULTIPLIER = 2,

		-- Fairness: below the first score the whole set must be placeable, below the second every piece
		-- must fit somewhere, above that at least one piece must fit.
		WHOLE_SET_BELOW_SCORE = 1500,
		EACH_PIECE_BELOW_SCORE = 5000,

		MAX_ATTEMPTS = 30, -- normal draws before falling back
		FALLBACK_ATTEMPTS = 10, -- small-only draws before dealing three dots
		SOLVER_NODE_BUDGET = 20000, -- placements the whole-set check may try before giving up
	}),
}

return table.freeze(Config)
