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

-- Everything to delete for `userId`, as (store, key) pairs.
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
