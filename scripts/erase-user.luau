--!strict
-- Erases one player's data from ChikaBlocks (right to erasure): their profile, and their entry in every leaderboard
-- store. It talks to Open Cloud, so it works for players who are offline.
--
--   lune run scripts/erase-user.luau <userId> [--dry-run] [--no-kick]
--
-- Needs two environment variables:
--   ROBLOX_UNIVERSE_ID   the experience's universe id (Creator Hub -> Experience -> ... -> Universe ID)
--   ROBLOX_API_KEY       an Open Cloud API key for that experience with: DataStore entries (delete),
--                        Ordered DataStore entries (delete) and Messaging Service (publish)
--
-- Steps: (1) publish the id on the "EraseUser" topic, so a server that has the player online removes them and
-- lets their last save land (otherwise that save would bring the profile back); wait for it; (2) delete the
-- profile and the leaderboard entries; (3) print what was deleted and what failed (non-zero exit code).
-- --dry-run lists the deletes without making any request. --no-kick skips step 1 (the player is known offline).
-- Studio's "_Dev" stores are not touched.
--
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

print(`done: {deleted} deleted, {missing} had nothing, {failed} failed`)
if failed > 0 then
	print("run it again for the failed ones; the rest are already gone")
	process.exit(1)
end
