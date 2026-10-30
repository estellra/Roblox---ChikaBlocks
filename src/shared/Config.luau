--!strict
-- Gameplay numbers that get tuned live in this one module.

local Config = {
	GRID_SIZE = 8,
	PIECES_PER_SET = 3,
	MAX_REVIVES_PER_RUN = 2,
}

return table.freeze(Config)
