--!strict
-- Gameplay numbers that get tuned live in this one module.

local Config = {
	GRID_SIZE = 8,
	PIECES_PER_SET = 3,
	MAX_REVIVES_PER_RUN = math.huge, -- no limit: from the third revive on, each one costs the last price

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

	-- Developer products for a revive, by how many revives the run has used already (the last one is used from
	-- then on): 10, 15 and 25 Robux.
	REVIVE_PRODUCTS = table.freeze({ 3727116317, 3727116434, 3727116486 }),

	-- Rotating a piece in the tray: each run starts with this many free rotations, then rotations bought earlier
	-- are used. One rotation unlocks one piece (it turns freely until it is placed). The developer product sells
	-- ROTATION_PACK rotations; 0 means it isn't on sale yet.
	FREE_ROTATIONS_PER_RUN = 1,
	ROTATION_PRODUCT = 3727205638,
	ROTATION_PACK = 5,

	-- Donations: developer products that give nothing but a place on the Supporters board, in order of price
	-- (5, 10, 25, 50, 100, 200, 500, 1000 and 2500 Robux). 0 would mean a tier whose product doesn't exist yet;
	-- it is left out of the Support screen. Prices are read from Roblox, never written here.
	DONATE_PRODUCTS = table.freeze({
		3727223223,
		3727223687,
		3727223870,
		3727224068,
		3727724626,
		3727725321,
		3727725778,
		3727726113,
		3727726800,
	}),

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

	-- Co-op (see CoopSession): two players share one board and take two pieces each from every set of four.
	COOP = table.freeze({
		-- The Co-op button and the remotes work only in Studio while this is off. M21 made a Co-op game playable, so it
		-- is on; the data, EXP and leaderboard for Co-op come with M22.
		ENABLED = true,
		SET_SIZE = 4,

		-- Invitations (see Rooms): how long one stays open, how long a pair rests after one was declined or left
		-- unanswered, and how many unanswered invitations one player can have waiting. Each player can have one
		-- invitation out at a time.
		INVITE_SECONDS = 30,
		INVITE_COOLDOWN_SECONDS = 60,
		MAX_PENDING_INVITES = 3,

		-- Each player of a Co-op run earns this share of the EXP a solo run with the same score would earn, so the two
		-- of them together earn what one solo run would (a share of 1 would make Co-op a way to level twice as fast).
		EXP_SHARE = 0.5,

		-- A player who has no move while the partner has one may take over the partner's pieces once nobody has
		-- moved for this long (the partner is put out of the run).
		AFK_SECONDS = 45,

		-- Replaces numbers in GENERATOR for Co-op's sets (Generator.Overrides). Proving that all four pieces can be
		-- placed takes much longer than for three: one or two deals in a thousand took over 5 ms, the slowest 10 to
		-- 50 ms. A budget of 500 placements cuts the slowest to about 3 to 10 ms and makes bot games about 5% longer
		-- (measured with tests/CoopSimulation.spec; see docs/PHASE5.md, "Kết quả M20").
		GENERATOR = table.freeze({
			SOLVER_NODE_BUDGET = 500,
		}),
	}),

	-- PVP (see PvpSession and docs/PHASE6.md): two players, one board each, race for score against a clock and push
	-- garbage lines onto each other. The numbers marked "M24" are starting points that tests/PvpSimulation.spec reports
	-- on; see docs/PHASE6.md, "Kết quả M24".
	PVP = table.freeze({
		-- Off outside Studio until M27 (ranked queue); M26 makes a friendly match playable in Studio.
		ENABLED = false,

		-- A match lasts this long; moves the server receives later than END_GRACE_SECONDS after the end are dropped.
		MATCH_SECONDS = 180,
		END_GRACE_SECONDS = 0.3,

		-- Free rotations per player per match. Bought rotations and paid revives can't be used in PVP.
		FREE_ROTATIONS = 1,

		-- Attack, in garbage lines, for one placement: by lines cleared at once (the last entry for that many or
		-- more), plus a bonus when the move clears lines with the combo at COMBO_BONUS_FROM or more, plus a bonus
		-- for clearing the board. M24: a bonus from combo 3 sent 21 lines per player per match (the greedy bot keeps long
		-- combos); from combo 8 it sends 8.
		ATTACK_BY_LINES = table.freeze({ 0, 1, 2, 3 }),
		ATTACK_COMBO_FROM = 8,
		ATTACK_COMBO_BONUS = 1,
		ATTACK_BOARD_CLEAR_BONUS = 2,

		-- Garbage waiting to enter a board: at most GARBAGE_QUEUE_MAX lines (more are dropped, newest first), and at
		-- most GARBAGE_PER_SET of them enter each time a new set is dealt.
		GARBAGE_QUEUE_MAX = 4,
		GARBAGE_PER_SET = 1,

		-- Color id of a garbage cell: one past the piece colors (Config.COLOR_COUNT + 1).
		GARBAGE_COLOR = 9,

		-- A cleared line in which more than this share of the cells were garbage is a "junk" line: it clears but earns
		-- no clear points, no combo and no attack. Without this rule garbage helped its victim (an almost full line is
		-- easy points): bot scores went up 7% with garbage; with it they go down 10% (M24).
		JUNK_LINE_GARBAGE_SHARE = 0.5,

		-- When no piece in the tray fits, the board's middle is cleared (like a revive), a new set is dealt and the
		-- tray stays locked for this long. M24.
		STUCK_LOCK_SECONDS = 5,

		-- Both players draw set k with the difficulty of a solo run at score (k - 1) * DIFFICULTY_SCORE_PER_SET, so the
		-- piece mix depends on how far the match is, not on either player's score. M24.
		DIFFICULTY_SCORE_PER_SET = 100,

		-- Replaces numbers in GENERATOR for PVP's sets. Mercy depends on how full one player's board is, which would
		-- make the two players' draws differ, so it is off.
		GENERATOR = table.freeze({
			MERCY_SMALL_MULTIPLIER = 1,
		}),

		-- Rank points for ranked matches (see Elo and PvpRating). A player's change is
		-- round(K * (S - E)) with E = 1 / (1 + 10 ^ ((opponent - own) / SCALE)) and S 1 for a win, 0.5 for a draw,
		-- 0 for a loss. K is K_PLACEMENT for the first PLACEMENT_GAMES ranked games of the account, K_HIGH from
		-- K_HIGH_FROM points up, K otherwise. Points never go below FLOOR.
		RATING = table.freeze({
			START = 1000,
			FLOOR = 100,
			SCALE = 400,
			K_PLACEMENT = 40,
			PLACEMENT_GAMES = 10,
			K = 24,
			K_HIGH = 16,
			K_HIGH_FROM = 1800,

			-- A season is a calendar month (UTC). When a new one starts, points move this share of the way back to
			-- START, and a player who played at least MEDAL_MIN_GAMES ranked games in the old one gets its medal
			-- (their highest tier that season).
			SEASON_PULL = 0.5,
			MEDAL_MIN_GAMES = 1,
		}),

		-- Rank tiers, lowest first: a player is in the last tier whose `from` their points reach. Never rename an id
		-- once shipped (season medals are saved by tier id).
		TIERS = table.freeze({
			table.freeze({ id = "Bronze", from = 0 }),
			table.freeze({ id = "Silver", from = 1000 }),
			table.freeze({ id = "Gold", from = 1200 }),
			table.freeze({ id = "Platinum", from = 1400 }),
			table.freeze({ id = "Diamond", from = 1600 }),
			table.freeze({ id = "Master", from = 1800 }),
		}),
	}),
}

return table.freeze(Config)
