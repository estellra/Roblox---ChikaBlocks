--!strict
-- Global leaderboards on OrderedDataStores (rules in Leaderboards). Each server:
-- - writes a player's values when they change: after a game over, every refresh while they play, and as
--   they leave (the last one may be skipped if their data is already gone; the next session catches up);
-- - writes the score of each Co-op pair it has seen: a row for the pair, kept at the higher of what is stored and
--   what this server has (UpdateAsync), so a pair's old record is never lowered by a server that doesn't know it;
-- - reads the top of every board once a minute, resolves display names in one batch, and keeps the result
--   for clients, who ask with RequestLeaderboard. Clients never touch the DataStores.
-- - once a season is over (and FINAL_TOP_DELAY_SECONDS later, so its last writes have landed), reads its final top
--   TOP_REWARD from that season's Rank store, which nobody writes any more, so PvpService can give the Top 10 medals.
--   Every server reads it once on its own; no scheduled job is needed.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require("./DataService")
local Leaderboards = require("../Leaderboards")
local Seasons = require("../Seasons")
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require("../PlayerData")
local Progression = require(ReplicatedStorage.Shared.Progression)
local RateLimiter = require("../Util/RateLimiter")

local IS_STUDIO = RunService:IsStudio()
-- With PVP off the Rank tab is hidden, so the Rank board and the season's final top aren't read.
local PVP_ON = Config.PVP.ENABLED or IS_STUDIO
local SEASONS = Config.PVP.SEASONS_ENABLED
local REFRESH_SECONDS = 60
local REFRESH_SOON_SECONDS = 3 -- how long refreshSoon() waits, for a write to show up in the sorted read
local SHUTDOWN_WAIT_SECONDS = 20 -- how long a closing server waits for leaderboard writes (the limit is 30)
local PAIR_WRITE_GAP_SECONDS = 20 -- a pair's row is written at most this often after a run or a leave

-- A Co-op board entry is a pair: `name` reads "A & B", `userId` is the smaller id and `userIds` has both.
export type Entry = { rank: number, userId: number, userIds: { number }?, name: string, title: string?, value: number }

-- What a client receives: the boards by key ("Highscore_all", ..., "Coop_all") and the player's own values.
export type Snapshot = {
	boards: { [string]: { Entry } },
	updatedAt: number, -- os.time() of the last read
	you: {
		best: number,
		level: number,
		weekBest: number,
		weekExp: number,
		donated: number,
		coopBest: number,
		rank: {
			rating: number,
			wins: number,
			losses: number,
			draws: number,
			seasonGames: number,
			season: string, -- the season now
			seasonEnds: string, -- "Dec 31"
			minGames: number, -- ranked games this season before the player shows on the board
			medals: { string }, -- "2026M12 Gold", "2026M11 Champion", newest first
		},
	},
}

-- A season's final top, read once it is over: user ids in order (first place first).
export type FinalTop = { season: string, userIds: { number } }

-- What this server knows of one pair's score on the Co-op board.
type Pair = {
	ids: { number }, -- the two user ids
	score: number, -- the highest score that counted for them seen here
	written: number, -- the highest score known to be in the store
	lastWrite: number, -- when a write was last started (os.clock)
	inFlight: boolean,
}

local LeaderboardService = {}

local written: { [Player]: { [string]: number } } = {} -- last value written per board key
local boards: { [string]: { Entry } } = {}
local updatedAt = 0
local names: { [number]: string } = {} -- display names by user id, kept for the server's lifetime
local requestLimiter = RateLimiter.new(1, 2, os.clock)
local refreshQueued = false -- a refreshSoon() is waiting to run
local writesInFlight = 0 -- DataStore writes started and not finished, so shutdown can wait for them
local lastFlush: { [Player]: number } = {} -- when each player's boards were last written
local coopPairs: { [string]: Pair } = {} -- the Co-op pairs this server has a score for, by row key
local finalTop: FinalTop? = nil
local finalTopListeners: { (top: FinalTop) -> () } = {}

local function storeFor(key: string, time: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(Leaderboards.storeName(key, time, IS_STUDIO, SEASONS))
end

local function titleFor(index: number): string?
	local milestone = Progression.MILESTONES[index]
	return if milestone then milestone.title else nil
end

-- Writes whatever changed since the last write. A failed write is left out of `written`, so the next
-- flush tries it again. With `minGap`, a player flushed less than that many seconds ago waits for the next
-- refresh, so quick runs cannot spend the write budget.
function LeaderboardService.flush(player: Player, data: PlayerData.PlayerData, minGap: number?)
	local clock = os.clock()
	local previous = lastFlush[player]
	if minGap and previous and clock - previous < minGap then
		return
	end
	lastFlush[player] = clock
	local now = os.time()
	Leaderboards.rollWeek(data.weekly, now)
	local done = written[player]
	if not done then
		done = {}
		written[player] = done
	end
	local titleIndex = Progression.titleIndex(data.milestonesClaimed)
	local values = Leaderboards.values(data, titleIndex, now, Config.PVP.RANK_MIN_GAMES, SEASONS)
	for key, value in Leaderboards.changes(values, done) do
		writesInFlight += 1
		task.spawn(function()
			local ok, err = pcall(function()
				storeFor(key, now):SetAsync(tostring(player.UserId), value)
			end)
			writesInFlight -= 1
			if ok then
				done[key] = value
			elseif IS_STUDIO then
				warn(`[ChikaBlock] leaderboard write {key} failed: {err}`)
			end
		end)
	end
end

-- Counts a move's score and EXP toward the weekly boards (written at the next flush).
function LeaderboardService.recordRun(data: PlayerData.PlayerData, score: number, expGained: number)
	Leaderboards.recordRun(data.weekly, os.time(), score, expGained)
end

-- Writes the pair's score if it is higher than what this server knows is stored. UpdateAsync keeps the higher of that
-- and what is in the store, so a pair's record from another server or an earlier session is never lowered; and the
-- one row is shared by both players, so it is written once for the pair. With `minGap`, a pair written less than
-- that many seconds ago waits for the next refresh. A failed write is tried again then.
local function flushPair(key: string, pair: Pair, minGap: number?)
	if pair.inFlight or pair.score <= pair.written then
		return
	end
	local clock = os.clock()
	if minGap and clock - pair.lastWrite < minGap then
		return
	end
	pair.lastWrite = clock
	pair.inFlight = true
	writesInFlight += 1
	local score = pair.score
	task.spawn(function()
		local ok, err = pcall(function()
			storeFor(Leaderboards.COOP_KEY, os.time()):UpdateAsync(key, function(stored: number?): number?
				if stored ~= nil and stored >= score then
					return nil -- the store already has a better one
				end
				return score
			end)
		end)
		writesInFlight -= 1
		pair.inFlight = false
		if ok then
			pair.written = math.max(pair.written, score)
		elseif IS_STUDIO then
			warn(`[ChikaBlock] co-op board write {key} failed: {err}`)
		end
	end)
end

-- A Co-op pair's score that counts is now `countedScore` (it only ever grows while both are in the run, and stops when
-- one leaves). Remembered here and written by the next refresh; `writeNow` writes it at once, as long as the pair
-- wasn't written within the last 20 seconds (a game over, a player leaving).
function LeaderboardService.recordCoop(a: number, b: number, countedScore: number, writeNow: boolean)
	if countedScore <= 0 then
		return
	end
	local key = Leaderboards.pairKey(a, b)
	local pair = coopPairs[key]
	if not pair then
		pair = {
			ids = { math.min(a, b), math.max(a, b) },
			score = 0,
			written = 0,
			lastWrite = -math.huge,
			inFlight = false,
		}
		coopPairs[key] = pair
	end
	pair.score = math.max(pair.score, math.floor(countedScore))
	if writeNow then
		flushPair(key, pair, PAIR_WRITE_GAP_SECONDS)
	end
end

-- Writes every pair whose score isn't stored yet, and forgets the ones that are stored and gone from this server.
local function flushPairs()
	for key, pair in coopPairs do
		flushPair(key, pair, nil)
		local here = false
		for _, userId in pair.ids do
			here = here or Players:GetPlayerByUserId(userId) ~= nil
		end
		if not here and not pair.inFlight and pair.written >= pair.score then
			coopPairs[key] = nil
		end
	end
end

local function resolveNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if not names[userId] then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				names[userId] = player.DisplayName
			else
				table.insert(missing, userId)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	elseif IS_STUDIO then
		warn(`[ChikaBlock] leaderboard names failed: {infos}`)
	end
end

type RawItem = { userId: number, partnerId: number?, value: number }

-- Reads the top of every board: the competitive ones, the Co-op board (rows by pair), then the Supporters board (a
-- shorter list of plain Robux totals). A board that fails to load keeps its last good copy.
function LeaderboardService.refresh()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			LeaderboardService.flush(player, data)
		end
	end
	flushPairs()

	local now = os.time()
	local reads: { { key: string, top: number } } = {}
	for _, board in Leaderboards.BOARDS do
		for _, period in Leaderboards.PERIODS do
			table.insert(reads, { key = `{board}_{period}`, top = Leaderboards.TOP })
		end
	end
	table.insert(reads, { key = Leaderboards.COOP_KEY, top = Leaderboards.COOP_TOP })
	if PVP_ON then
		table.insert(reads, { key = Leaderboards.RANK_KEY, top = Leaderboards.RANK_TOP })
	end
	table.insert(reads, { key = Leaderboards.SUPPORTERS_KEY, top = Leaderboards.SUPPORTERS_TOP })

	local raw: { [string]: { RawItem } } = {}
	local userIds: { number } = {}
	for _, read in reads do
		local key = read.key
		local ok, page = pcall(function()
			return storeFor(key, now):GetSortedAsync(false, read.top):GetCurrentPage()
		end)
		if ok then
			local items: { RawItem } = {}
			for _, item in page do
				if key == Leaderboards.COOP_KEY then
					local ids = Leaderboards.pairIds(item.key)
					if ids then
						table.insert(items, { userId = ids.low, partnerId = ids.high, value = item.value })
						table.insert(userIds, ids.low)
						table.insert(userIds, ids.high)
					end
				else
					local userId = tonumber(item.key)
					if userId then
						table.insert(items, { userId = userId, value = item.value })
						table.insert(userIds, userId)
					end
				end
			end
			raw[key] = items
		elseif IS_STUDIO then
			warn(`[ChikaBlock] leaderboard read {key} failed: {page}`)
		end
	end

	resolveNames(userIds)
	for key, items in raw do
		-- Robux and Co-op scores are stored as they are, no title mixed in.
		local plain = key == Leaderboards.SUPPORTERS_KEY or key == Leaderboards.COOP_KEY
		local entries = table.create(#items)
		for rank, item in items do
			local stat, titleIndex = item.value, 0
			if not plain then
				stat, titleIndex = Leaderboards.decode(item.value)
			end
			local name = names[item.userId] or "Player"
			local pairIds: { number }? = nil
			if item.partnerId then
				name = `{name} & {names[item.partnerId] or "Player"}`
				pairIds = { item.userId, item.partnerId }
			end
			entries[rank] = {
				rank = rank,
				userId = item.userId,
				userIds = pairIds,
				name = name,
				title = titleFor(titleIndex),
				value = stat,
			}
		end
		boards[key] = entries
	end
	updatedAt = now
end

-- Reads the final top of the season that ended, once it has been over for FINAL_TOP_DELAY_SECONDS. Trial seasons give
-- no rewards, so they are not read.
local function readFinalTop()
	if not PVP_ON or not SEASONS then
		return
	end
	local now = os.time()
	local current = Seasons.id(now)
	local ended = Seasons.previous(current)
	if finalTop and finalTop.season == ended then
		return
	end
	if ended < Config.PVP.RATING.REWARDS_FROM_SEASON then
		return
	end
	if now - Seasons.startOf(current) < Config.PVP.FINAL_TOP_DELAY_SECONDS then
		return
	end
	local store = DataStoreService:GetOrderedDataStore(if IS_STUDIO then `Rank_{ended}_Dev` else `Rank_{ended}`)
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, Config.PVP.TOP_REWARD):GetCurrentPage()
	end)
	if not ok then
		if IS_STUDIO then
			warn(`[ChikaBlock] final top of {ended} not read: {page}`)
		end
		return -- tried again at the next refresh
	end
	local userIds: { number } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(userIds, userId)
		end
	end
	local top: FinalTop = { season = ended, userIds = userIds }
	finalTop = top
	for _, listener in finalTopListeners do
		task.spawn(listener, top)
	end
end

-- The final top of the season that ended, once it has been read; nil before.
function LeaderboardService.finalTop(): FinalTop?
	return finalTop
end

-- Called when a season's final top has been read.
function LeaderboardService.onFinalTop(callback: (top: FinalTop) -> ())
	table.insert(finalTopListeners, callback)
end

-- Reads the boards again in a few seconds, e.g. after a donation so the Supporters board shows it. Asking
-- again meanwhile changes nothing.
function LeaderboardService.refreshSoon()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(REFRESH_SOON_SECONDS, function()
		refreshQueued = false
		LeaderboardService.refresh()
	end)
end

-- For the Studio debug bridge: every board as "key: rank. name [title] value" lines.
function LeaderboardService.describe(): string
	local lines = { `updatedAt={updatedAt}` }
	for _, board in Leaderboards.BOARDS do
		for _, period in Leaderboards.PERIODS do
			local key = `{board}_{period}`
			local entries = boards[key]
			local parts = {}
			for _, entry in entries or {} do
				table.insert(parts, `{entry.rank}. {entry.name} [{entry.title or "-"}] {entry.value}`)
			end
			table.insert(lines, `{key}: {if entries then table.concat(parts, " | ") else "not loaded"}`)
		end
	end
	local coop = boards[Leaderboards.COOP_KEY]
	local coopParts = {}
	for _, entry in coop or {} do
		table.insert(coopParts, `{entry.rank}. {entry.name} {entry.value}`)
	end
	table.insert(lines, `Coop: {if coop then table.concat(coopParts, " | ") else "not loaded"}`)
	local rank = boards[Leaderboards.RANK_KEY]
	local rankParts = {}
	for _, entry in rank or {} do
		table.insert(rankParts, `{entry.rank}. {entry.name} {entry.value}`)
	end
	table.insert(
		lines,
		`Rank ({Leaderboards.storeName(Leaderboards.RANK_KEY, os.time(), IS_STUDIO, SEASONS)}): {if rank
			then table.concat(rankParts, " | ")
			else "not loaded"}`
	)
	table.insert(
		lines,
		`final top: {if finalTop then `{finalTop.season} {table.concat(finalTop.userIds, ",")}` else "not read"}`
	)
	local supporters = boards[Leaderboards.SUPPORTERS_KEY]
	local parts = {}
	for _, entry in supporters or {} do
		table.insert(parts, `{entry.rank}. {entry.name} {entry.value}`)
	end
	table.insert(lines, `Supporters: {if supporters then table.concat(parts, " | ") else "not loaded"}`)
	local pending = {}
	for key, pair in coopPairs do
		table.insert(pending, `{key}={pair.score} (stored {pair.written})`)
	end
	table.sort(pending)
	table.insert(lines, `pairs here: {if #pending > 0 then table.concat(pending, ", ") else "none"}`)
	return table.concat(lines, "\n")
end

-- The player's season medals for the Rank tab, newest first: "2026M12 Gold", "2026M11 Champion".
local function medalLines(pvp: PlayerData.PvpData): { string }
	local seasons = {}
	for season in pvp.medals do
		table.insert(seasons, season)
	end
	table.sort(seasons, function(a: string, b: string): boolean
		return a > b
	end)
	local lines = {}
	for _, season in seasons do
		local medal = pvp.medals[season]
		local top = if medal.top == 1 then "Champion" elseif medal.top then `Top {medal.top}` else nil
		table.insert(lines, if top then `{season} {medal.tier} · {top}` else `{season} {medal.tier}`)
	end
	return lines
end

local function snapshotFor(data: PlayerData.PlayerData): Snapshot
	local now = os.time()
	local season = Seasons.id(now)
	local pvp = data.pvp
	local current = pvp.season == season
	-- With seasons off the board counts every ranked game, and there is no season or medal to show.
	local seasonGames = if not SEASONS then pvp.games elseif current then pvp.seasonGames else 0
	Leaderboards.rollWeek(data.weekly, now)
	return {
		boards = boards,
		updatedAt = updatedAt,
		you = {
			best = data.bestScore,
			level = data.level,
			weekBest = data.weekly.bestScore,
			weekExp = data.weekly.exp,
			donated = data.robuxDonated,
			coopBest = data.coopBest,
			rank = {
				rating = pvp.rating,
				wins = pvp.wins,
				losses = pvp.losses,
				draws = pvp.draws,
				seasonGames = seasonGames,
				season = if SEASONS then season else "",
				seasonEnds = if SEASONS then Seasons.lastDayText(season) else "",
				minGames = Config.PVP.RANK_MIN_GAMES,
				medals = if SEASONS then medalLines(pvp) else {},
			},
		},
	}
end

function LeaderboardService.start(_self: any)
	Net.RequestLeaderboard.OnServerEvent:Connect(function(player: Player)
		if not requestLimiter:allow(player) then
			return
		end
		local data = DataService.get(player)
		if data then
			Net.Leaderboard:FireClient(player, snapshotFor(data))
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local data = DataService.get(player)
		if data then
			LeaderboardService.flush(player, data)
		end
		written[player] = nil
		lastFlush[player] = nil
		requestLimiter:forget(player)
	end)

	-- A closing server writes what its players have and waits for the writes to finish.
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data then
				LeaderboardService.flush(player, data)
			end
		end
		for key, pair in coopPairs do
			flushPair(key, pair, nil)
		end
		local deadline = os.clock() + SHUTDOWN_WAIT_SECONDS
		while writesInFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			LeaderboardService.refresh()
			readFinalTop()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
