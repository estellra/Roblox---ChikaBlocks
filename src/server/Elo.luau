--!strict
-- Rank points for one ranked match (docs/PHASE6.md, "Công thức (BN)"). Pure: numbers in, numbers out. The numbers
-- come in as Config.PVP.RATING (passed in: server and shared code sit in different places in the DataModel).

-- The part of Config.PVP.RATING this module reads.
export type Settings = {
	FLOOR: number,
	SCALE: number,
	K_PLACEMENT: number,
	PLACEMENT_GAMES: number,
	K: number,
	K_HIGH: number,
	K_HIGH_FROM: number,
}

-- What a player stands to gain or lose, worked out when the match starts: one change per result.
export type Stakes = { win: number, draw: number, loss: number }

local Elo = {}
Elo.__index = Elo

export type Elo = typeof(setmetatable({} :: { settings: Settings }, Elo))

-- Rounds half away from zero, so a win for one player is exactly the other's loss when both use the same K.
local function round(value: number): number
	return if value >= 0 then math.floor(value + 0.5) else -math.floor(-value + 0.5)
end

function Elo.new(settings: Settings): Elo
	return setmetatable({ settings = settings }, Elo)
end

--- Expected result (0 to 1) of a player with `own` points against one with `opponent` points.
function Elo.expected(self: Elo, own: number, opponent: number): number
	return 1 / (1 + 10 ^ ((opponent - own) / self.settings.SCALE))
end

--- The K factor of a player with these points who has played `rankedGames` ranked games before this one.
function Elo.kFactor(self: Elo, rating: number, rankedGames: number): number
	local settings = self.settings
	if rankedGames < settings.PLACEMENT_GAMES then
		return settings.K_PLACEMENT
	elseif rating >= settings.K_HIGH_FROM then
		return settings.K_HIGH
	end
	return settings.K
end

--- The change in points for result `score` (1 win, 0.5 draw, 0 loss), never taking the player below FLOOR.
function Elo.change(self: Elo, own: number, opponent: number, k: number, score: number): number
	local delta = round(k * (score - self:expected(own, opponent)))
	return math.max(own + delta, self.settings.FLOOR) - own
end

--- The three possible changes for a player, from both players' points before the match.
function Elo.stakes(self: Elo, own: number, opponent: number, rankedGames: number): Stakes
	local k = self:kFactor(own, rankedGames)
	return {
		win = self:change(own, opponent, k, 1),
		draw = self:change(own, opponent, k, 0.5),
		loss = self:change(own, opponent, k, 0),
	}
end

return Elo
