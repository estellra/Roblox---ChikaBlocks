--!strict
-- Erases one player's data from ChikaBlocks (right to erasure): their profile, their entry in every leaderboard
-- store, and the Co-op rows they are in. It talks to Open Cloud, so it works for players who are offline.
--
--   lune run scripts/erase-user.luau <userId> [--dry-run] [--no-kick]
--
-- Needs two environment variables:
--   ROBLOX_UNIVERSE_ID   the experience's universe id (Creator Hub -> Experience -> ... -> Universe ID)
--   ROBLOX_API_KEY       an Open Cloud API key for that experience with: DataStore entries (delete),
--                        Ordered DataStore entries (read, to list the Co-op rows; and delete) and Messaging
--                        Service (publish)
--
-- Steps: (1) publish the id on the "EraseUser" topic, so a server that has the player online removes them and
-- lets their last save land (otherwise that save would bring the profile back); wait for it; (2) delete the
-- profile and the leaderboard entries, then lists the whole Co-op store (a page of 100 rows at a time) and deletes
-- every row that has the id in it (a pair "12_45" is the row of both 12 and 45, so it goes for both); (3) print
-- what was deleted and what failed (non-zero exit code).
-- The Co-op rows are pairs, so no key says whose they are: the profile does not remember who a player played with
-- and the only way to find the rows is to read them all. That costs one request per 100 rows (1,000 pairs, 10
-- requests) each time somebody is erased; far past tens of thousands of pairs it wants an index of its own.
-- --dry-run lists the deletes without making any request. --no-kick skips step 1 (the player is known offline).
-- Studio's "_Dev" stores are not touched.
-- The leaderboard stores include the Rank board's store of every ranked season ("Rank_2026M11", ...). Not scanned:
-- the ranked queue's pair counts ("PvpPairs" in MemoryStore, keyed by a pair of ids) expire on their own within 24
-- hours, and nothing else of PVP is kept (no match history, no opponent ids).
--
-- The Co-op scan reads the list response as documented ("orderedDataStoreEntries" with an "id" each, and a
-- "nextPageToken"); that shape was not seen live, so the script says how many rows it scanned and warns when a page
-- has no list.
-- Not tested against the live API (needs a real key): run it with --dry-run first, then on a throwaway test
-- account's id (and check that the data is gone) before relying on it for a real request.
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

local Erasure = require("../src/server/Erasure")

local API = "https://apis.roblox.com/cloud/v2/universes"
local KICK_WAIT_SECONDS = 20 -- a leaving player's last save takes a few seconds
local MAX_TRIES = 5
local DEFAULT_RETRY_SECONDS = 5

local function fail(message: string): never
	print(message)
	process.exit(2)
end

local userId: number? = nil
local dryRun, noKick = false, false
for _, argument in process.args do
	if argument == "--dry-run" then
		dryRun = true
	elseif argument == "--no-kick" then
		noKick = true
	elseif userId == nil then
		userId = Erasure.parseUserId(argument)
		if userId == nil then
			fail(`"{argument}" is not a UserId (digits only)`)
		end
	else
		fail(`unexpected argument "{argument}"`)
	end
end
if userId == nil then
	fail("usage: lune run scripts/erase-user.luau <userId> [--dry-run] [--no-kick]")
end
local targetUser: number = userId :: number

local plan = Erasure.plan(targetUser, os.time())
if dryRun then
	print(`would erase user {targetUser}:`)
	for _, target in plan.dataStores do
		print(`  DataStore {target.store}  key {target.key}`)
	end
	for _, target in plan.orderedStores do
		print(`  OrderedDataStore {target.store}  key {target.key}`)
	end
	print(`  OrderedDataStore {Erasure.COOP_STORE}  every row with {targetUser} in it (found by listing the store)`)
	if not noKick then
		print(`  (first publishing "{targetUser}" on topic {Erasure.TOPIC} and waiting {KICK_WAIT_SECONDS} s)`)
	end
	return
end

local universeId = process.env.ROBLOX_UNIVERSE_ID
local apiKey = process.env.ROBLOX_API_KEY
if not universeId or not string.match(universeId, "^%d+$") then
	fail("set ROBLOX_UNIVERSE_ID to the experience's universe id (digits only)")
end
if not apiKey or apiKey == "" then
	fail("set ROBLOX_API_KEY to an Open Cloud API key (see the top of this script for its permissions)")
end

-- Sends a request, waiting and trying again when Open Cloud says to slow down (429) or has a hiccup (5xx).
-- Returns the final status code and body.
local function send(method: string, url: string, body: string?): (number, string)
	local status, text = 0, ""
	for attempt = 1, MAX_TRIES do
		local response = net.request({
			url = url,
			method = method,
			headers = { ["x-api-key"] = apiKey :: string, ["Content-Type"] = "application/json" },
			body = body,
		})
		status, text = response.statusCode, response.body
		if status ~= 429 and status < 500 then
			break
		end
		local wait = tonumber(response.headers["retry-after"]) or DEFAULT_RETRY_SECONDS * attempt
		print(`  status {status}; trying again in {wait} s`)
		task.wait(wait)
	end
	return status, text
end

if not noKick then
	print(`telling live servers to remove user {targetUser}...`)
	local status, text = send(
		"POST",
		`{API}/{universeId}:publishMessage`,
		net.jsonEncode({ topic = Erasure.TOPIC, message = tostring(targetUser) })
	)
	if status < 200 or status >= 300 then
		fail(
			`could not publish the message (status {status}): {text}\nfix the key, or pass --no-kick if the player is offline`
		)
	end
	print(`waiting {KICK_WAIT_SECONDS} s for a leaving player's last save...`)
	task.wait(KICK_WAIT_SECONDS)
end

local deleted, missing, failed = 0, 0, 0
local function erase(kind: string, collection: string, target: Erasure.Target)
	local store, key = net.urlEncode(target.store), net.urlEncode(target.key)
	local status, text = send("DELETE", `{API}/{universeId}/{collection}/{store}/scopes/global/entries/{key}`, nil)
	if status >= 200 and status < 300 then
		deleted += 1
		print(`deleted  {kind} {target.store} / {target.key}`)
	elseif status == 404 then
		missing += 1 -- nothing there: the player never reached this store (or it was erased already)
	else
		failed += 1
		print(`FAILED   {kind} {target.store} / {target.key}: status {status} {text}`)
	end
end

for _, target in plan.dataStores do
	erase("DataStore", "data-stores", target)
end
for _, target in plan.orderedStores do
	erase("OrderedDataStore", "ordered-data-stores", target)
end

-- The Co-op board's rows are pairs "<id>_<id>": list the store, then delete the rows with this user in them (after
-- listing, so the deletes don't disturb the paging).
local COOP_PAGE_SIZE = 100
local coopKeys: { string } = {}
local coopPages = 0
local pageToken: string? = nil
repeat
	local url = `{API}/{universeId}/ordered-data-stores/{net.urlEncode(Erasure.COOP_STORE)}/scopes/global/entries`
		.. `?maxPageSize={COOP_PAGE_SIZE}`
	if pageToken then
		url ..= `&pageToken={net.urlEncode(pageToken)}`
	end
	local status, text = send("GET", url, nil)
	if status == 404 then
		break -- no Co-op store yet: nobody has a pair row
	elseif status < 200 or status >= 300 then
		failed += 1
		print(`FAILED   listing the {Erasure.COOP_STORE} store: status {status} {text}`)
		break
	end
	local ok, body = pcall(net.jsonDecode, text)
	if not ok or type(body) ~= "table" then
		failed += 1
		print(`FAILED   the {Erasure.COOP_STORE} store's list was not JSON: {string.sub(text, 1, 200)}`)
		break
	end
	coopPages += 1
	if body.orderedDataStoreEntries == nil then
		-- An empty store, or a response shaped differently from the documented one: say so, so an empty scan is not trusted blindly.
		print(
			`note: page {coopPages} of the {Erasure.COOP_STORE} store has no "orderedDataStoreEntries" list: {string.sub(
				text,
				1,
				120
			)}`
		)
	end
	for _, entry in body.orderedDataStoreEntries or {} do
		-- The row's key is its id (or the end of its path, ".../entries/<key>").
		local key = entry.id
		if type(key) ~= "string" and type(entry.path) == "string" then
			key = string.match(entry.path, "/entries/([^/]+)$")
		end
		if type(key) == "string" then
			table.insert(coopKeys, key)
		end
	end
	local nextToken = body.nextPageToken
	pageToken = if type(nextToken) == "string" and nextToken ~= "" then nextToken else nil
until pageToken == nil
print(`scanned the {Erasure.COOP_STORE} store: {#coopKeys} rows in {coopPages} page(s)`)
for _, key in Erasure.pairKeysFor(coopKeys, targetUser) do
	erase("OrderedDataStore", "ordered-data-stores", { store = Erasure.COOP_STORE, key = key })
end

print(`done: {deleted} deleted, {missing} had nothing, {failed} failed`)
if failed > 0 then
	print("run it again for the failed ones; the rest are already gone")
	process.exit(1)
end
