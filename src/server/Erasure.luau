--!strict
-- Where a player's data lives, so it can all be erased on request (right to erasure). Pure Luau: the game's
-- ErasureService and scripts/erase-user.luau both use it, and Lune tests it.
--
-- Everything is keyed by the player's UserId:
-- - the ProfileStore profile "User_<id>" in the "PlayerData" DataStore (also linked to the id with AddUserId, so
--   Roblox's own erasure tooling can find it);
-- - one entry "<id>" in each leaderboard OrderedDataStore. An OrderedDataStore entry cannot carry user ids, so
--   Roblox cannot link these itself; the weekly boards have a store per week, and this lists every week since
--   the first publish.
-- - the Co-op board is the exception: its rows are pairs "<id>_<id>" in the "Coop" store, so a row can't be found by
--   one id. scripts/erase-user.luau lists the store page by page and deletes the rows pairKeyMatches() accepts. The
--   profile does not keep who a player played with, so those rows are the only trace of a pairing, and erasing
--   either player removes the row for both.
-- Studio's "_Dev" stores are left out: they only ever hold the developer's own test data.
local Leaderboards = require("./Leaderboards")

local WEEK_SECONDS = 7 * 86400

export type Target = { store: string, key: string }
export type Plan = { dataStores: { Target }, orderedStores: { Target } }

local Erasure = {}

Erasure.TOPIC = "EraseUser" -- the MessagingService topic live servers listen on (see ErasureService)
Erasure.PROFILE_STORE = "PlayerData"
-- 2026-10-30 00:00 UTC, the day the project began. No leaderboard store is older than this.
Erasure.FIRST_WEEK_TIME = 1793318400
Erasure.COOP_STORE = "Coop" -- the Co-op board's OrderedDataStore, kept apart from orderedStoreNames() (see above)
Erasure.MAX_USER_ID = 1e13 -- far above today's ids; also keeps tostring() from switching to exponent notation

function Erasure.profileKey(userId: number): string
	return `User_{userId}`
end

-- A UserId sent as a message: whole digits only, so nothing but a plausible id gets through.
function Erasure.parseUserId(message: unknown): number?
	if type(message) ~= "string" or not string.match(message, "^%d+$") or #message > 13 then
		return nil
	end
	local userId = tonumber(message)
	if userId == nil or userId < 1 or userId > Erasure.MAX_USER_ID then
		return nil
	end
	return userId
end

-- The names of every leaderboard OrderedDataStore that has existed at `now`: the all-time stores, the Supporters
-- store, and a weekly store for each week from FIRST_WEEK_TIME on.
function Erasure.orderedStoreNames(now: number): { string }
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(name: string)
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	for _, board in Leaderboards.BOARDS do
		add(Leaderboards.storeName(`{board}_all`, now, false))
	end
	add(Leaderboards.storeName(Leaderboards.SUPPORTERS_KEY, now, false))
	-- One step a week from the first week reaches every week's store; `now` itself covers the current one.
	local time = Erasure.FIRST_WEEK_TIME
	while time <= now do
		for _, board in Leaderboards.BOARDS do
			add(Leaderboards.storeName(`{board}_week`, time, false))
		end
		time += WEEK_SECONDS
	end
	for _, board in Leaderboards.BOARDS do
		add(Leaderboards.storeName(`{board}_week`, now, false))
	end
	return names
end

-- Whether a row of the Co-op store has `userId` as one of its two players. The ids are compared whole, so
-- user 12 owns "12_45" and "45_12" but not "123_45" or "45_312".
function Erasure.pairKeyMatches(key: string, userId: number): boolean
	local ids = Leaderboards.pairIds(key)
	return ids ~= nil and (ids.low == userId or ids.high == userId)
end

-- The rows among `keys` to delete when erasing `userId`.
function Erasure.pairKeysFor(keys: { string }, userId: number): { string }
	local matching: { string } = {}
	for _, key in keys do
		if Erasure.pairKeyMatches(key, userId) then
			table.insert(matching, key)
		end
	end
	return matching
end

-- Everything to delete for `userId`, as (store, key) pairs (the Co-op rows aside; see above).
function Erasure.plan(userId: number, now: number): Plan
	local ordered: { Target } = {}
	for _, store in Erasure.orderedStoreNames(now) do
		table.insert(ordered, { store = store, key = tostring(userId) })
	end
	return {
		dataStores = { { store = Erasure.PROFILE_STORE, key = Erasure.profileKey(userId) } },
		orderedStores = ordered,
	}
end

return Erasure
