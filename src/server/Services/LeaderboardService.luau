--!strict
-- Global leaderboards on OrderedDataStores (rules in Leaderboards). Each server:
-- - writes a player's values when they change: after a game over, every refresh while they play, and as
--   they leave (the last one may be skipped if their data is already gone; the next session catches up);
-- - reads the top of every board once a minute, resolves display names in one batch, and keeps the result
--   for clients, who ask with RequestLeaderboard. Clients never touch the DataStores.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local DataService = require("./DataService")
local Leaderboards = require("../Leaderboards")
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require("../PlayerData")
local Progression = require(ReplicatedStorage.Shared.Progression)
local RateLimiter = require("../Util/RateLimiter")

local IS_STUDIO = RunService:IsStudio()
local REFRESH_SECONDS = 60
local REFRESH_SOON_SECONDS = 3 -- how long refreshSoon() waits, for a write to show up in the sorted read
local SHUTDOWN_WAIT_SECONDS = 20 -- how long a closing server waits for leaderboard writes (the limit is 30)

export type Entry = { rank: number, userId: number, name: string, title: string?, value: number }

-- What a client receives: the boards by key ("Highscore_all", ...) and the player's own values.
export type Snapshot = {
	boards: { [string]: { Entry } },
	updatedAt: number, -- os.time() of the last read
	you: { best: number, level: number, weekBest: number, weekExp: number, donated: number },
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

local function storeFor(key: string, time: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(Leaderboards.storeName(key, time, IS_STUDIO))
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
	local values = Leaderboards.values(data, Progression.titleIndex(data.milestonesClaimed), now)
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

-- Reads the top of every board: the competitive ones, then the Supporters board (a shorter list of plain Robux
-- totals). A board that fails to load keeps its last good copy.
function LeaderboardService.refresh()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			LeaderboardService.flush(player, data)
		end
	end

	local now = os.time()
	local reads: { { key: string, top: number } } = {}
	for _, board in Leaderboards.BOARDS do
		for _, period in Leaderboards.PERIODS do
			table.insert(reads, { key = `{board}_{period}`, top = Leaderboards.TOP })
		end
	end
	table.insert(reads, { key = Leaderboards.SUPPORTERS_KEY, top = Leaderboards.SUPPORTERS_TOP })

	local raw: { [string]: { { userId: number, value: number } } } = {}
	local userIds: { number } = {}
	for _, read in reads do
		local key = read.key
		local ok, page = pcall(function()
			return storeFor(key, now):GetSortedAsync(false, read.top):GetCurrentPage()
		end)
		if ok then
			local items = {}
			for _, item in page do
				local userId = tonumber(item.key)
				if userId then
					table.insert(items, { userId = userId, value = item.value })
					table.insert(userIds, userId)
				end
			end
			raw[key] = items
		elseif IS_STUDIO then
			warn(`[ChikaBlock] leaderboard read {key} failed: {page}`)
		end
	end

	resolveNames(userIds)
	for key, items in raw do
		local plain = key == Leaderboards.SUPPORTERS_KEY -- Robux as they are, no title mixed in
		local entries = table.create(#items)
		for rank, item in items do
			local stat, titleIndex = item.value, 0
			if not plain then
				stat, titleIndex = Leaderboards.decode(item.value)
			end
			entries[rank] = {
				rank = rank,
				userId = item.userId,
				name = names[item.userId] or "Player",
				title = titleFor(titleIndex),
				value = stat,
			}
		end
		boards[key] = entries
	end
	updatedAt = now
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
	local supporters = boards[Leaderboards.SUPPORTERS_KEY]
	local parts = {}
	for _, entry in supporters or {} do
		table.insert(parts, `{entry.rank}. {entry.name} {entry.value}`)
	end
	table.insert(lines, `Supporters: {if supporters then table.concat(parts, " | ") else "not loaded"}`)
	return table.concat(lines, "\n")
end

local function snapshotFor(data: PlayerData.PlayerData): Snapshot
	Leaderboards.rollWeek(data.weekly, os.time())
	return {
		boards = boards,
		updatedAt = updatedAt,
		you = {
			best = data.bestScore,
			level = data.level,
			weekBest = data.weekly.bestScore,
			weekExp = data.weekly.exp,
			donated = data.robuxDonated,
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
		local deadline = os.clock() + SHUTDOWN_WAIT_SECONDS
		while writesInFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			LeaderboardService.refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
