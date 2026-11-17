--!strict
-- Loads each player's saved data into a session-locked ProfileStore profile when they join and releases it
-- when they leave; ProfileStore autosaves and saves on shutdown. Other services change the data in memory
-- through get(). If a profile can't be loaded, the player is kicked with a message to rejoin rather than
-- playing without saving.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Erasure = require("../Erasure")
local PlayerData = require("../PlayerData")
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore) :: any

-- Studio playtests write to a separate store so they never touch live players' data.
local STORE_NAME = if RunService:IsStudio() then "PlayerData_Dev" else "PlayerData"
local LOAD_FAILED_MESSAGE = "We couldn't load your saved data. Please rejoin."
local SESSION_TAKEN_MESSAGE = "Your data was opened on another server. Please rejoin."

local DataService = {}

local store: any
local profiles: { [Player]: any } = {}
local releaseCallbacks: { (player: Player, data: PlayerData.PlayerData) -> () } = {}

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(Erasure.profileKey(player.UserId), {
		Cancel = function(): boolean
			return player.Parent ~= Players -- stop waiting if the player already left
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			player:Kick(LOAD_FAILED_MESSAGE)
		end
		return
	end

	profile:AddUserId(player.UserId) -- lets Roblox erase this data on a right-to-be-forgotten request
	PlayerData.migrate(profile.Data)
	profile:Reconcile() -- adds fields introduced to the template since this profile was saved
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick(SESSION_TAKEN_MESSAGE)
		end
	end)

	if player.Parent == Players then
		profiles[player] = profile
	else
		profile:EndSession() -- left while loading
	end
end

function DataService.init(_self: any)
	store = ProfileStore.New(STORE_NAME, table.clone(PlayerData.TEMPLATE))
end

function DataService.start(_self: any)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		if profile then
			for _, callback in releaseCallbacks do
				local ok, err = pcall(callback, player, profile.Data)
				if not ok then
					warn(`DataService: a beforeRelease callback failed for {player.UserId}: {err}`)
				end
			end
			profile:EndSession() -- saves and releases the session lock
		end
	end)
end

-- Registers `callback` to run when a player leaves, with their live data, right before it is saved and released (for
-- example, to settle a ranked match they left). It must not yield. It doesn't run when the data was taken by another
-- server: PvpRating.settleStale covers that case the next time the data loads.
function DataService.beforeRelease(callback: (player: Player, data: PlayerData.PlayerData) -> ())
	table.insert(releaseCallbacks, callback)
end

-- The player's live data, or nil while it loads (or if they're leaving). Changes are saved automatically.
function DataService.get(player: Player): PlayerData.PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Yields until the player's data is loaded. Nil if they leave or it takes longer than `timeoutSeconds`.
function DataService.waitForData(player: Player, timeoutSeconds: number): PlayerData.PlayerData?
	local deadline = os.clock() + timeoutSeconds
	while not profiles[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.get(player)
end

-- Yields until `isSaved(lastSavedData)` holds for the player's profile, saving it now and again every ten
-- seconds. False when the session ends first (the player left, or the data went to another server).
function DataService.waitUntilSaved(player: Player, isSaved: (saved: any) -> boolean): boolean
	local profile = profiles[player]
	while profile and profile:IsActive() do
		if isSaved(profile.LastSavedData or {}) then
			return true
		end
		local before = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == before then
			profile.OnAfterSave:Wait()
		end
		if isSaved(profile.LastSavedData or {}) then
			return true
		end
		if profile:IsActive() then
			task.wait(10)
		end
	end
	return false
end

-- For the Studio debug bridge: store name and whether ProfileStore can reach the DataStore API
-- ("Access") or is using an in-memory mock ("NoAccess", "NoInternet").
function DataService.describeStore(): string
	return `store={STORE_NAME} dataStoreState={ProfileStore.DataStoreState}`
end

return DataService
