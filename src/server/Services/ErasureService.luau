--!strict
-- Part of erasing a player's data (see Erasure and scripts/erase-user.luau). The data itself is deleted from
-- outside through Open Cloud, which works for players who are offline. A player who is in a game right now would
-- save their data again as they leave, bringing it back, so before deleting, the script publishes the player's
-- UserId on the "EraseUser" MessagingService topic; each server that has the player removes them with a message
-- and, as they leave, ProfileStore saves one last time. The script waits for that before it deletes.
-- Only Open Cloud with the owner's API key can publish on the topic; a message that is not a plain UserId is ignored.
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Erasure = require("../Erasure")

local KICK_MESSAGE = "Your data is being erased at your request. You can rejoin to start over."

local ErasureService = {}

local function onMessage(message: { Data: unknown })
	local userId = Erasure.parseUserId(message.Data)
	if not userId then
		warn("[ChikaBlock] ignored a malformed erase message")
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		print(`[ChikaBlock] erasing {userId}: removing the player so the last save lands before the delete`)
		player:Kick(KICK_MESSAGE)
	end
end

function ErasureService.start(_self: any)
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Erasure.TOPIC, onMessage)
	end)
	if not ok and not RunService:IsStudio() then
		warn(`[ChikaBlock] could not listen for erase requests: {err}`)
	end
end

return ErasureService
