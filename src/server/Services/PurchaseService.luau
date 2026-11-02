--!strict
-- Paid revives. After a game over the player is offered a revive: for a revive bought earlier it is free, else
-- Revive opens Roblox's purchase prompt for the product that fits the run (10, 15, then 25 Robux). The
-- purchase arrives in ProcessReceipt, which grants one revive, waits until it is saved (see Purchases) and
-- then uses it on the run that was waiting. A revive that cannot be used right away (the player left the run,
-- the connection dropped) stays in their data for the next game over. Everything about money is decided
-- here: the client only asks, and never picks a product. The same goes for the pack of rotations the player
-- can buy when they have none left.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require("./DataService")
local GameRuns = require("../GameRuns")
local GameService = require("./GameService")
local PlayerData = require("../PlayerData")
local Purchases = require("../Purchases")
local RateLimiter = require("../Util/RateLimiter")

local IS_STUDIO = RunService:IsStudio()
local DATA_WAIT_SECONDS = 20 -- how long a receipt waits for the player's data
local PROMPT_TIMEOUT_SECONDS = 180 -- a prompt nobody answered stops blocking new requests after this

-- What the player is buying right now: for which run, and which product.
type Pending = { runId: number, productId: number, token: number }

local PurchaseService = {}

local pending: { [Player]: Pending } = {}
local prices: { [number]: number } = {} -- Robux price of each product, read from Roblox
local requestLimiter = RateLimiter.new(1, 1, os.clock)
local rotationLimiter = RateLimiter.new(1, 2, os.clock)
local rotationPending: { [Player]: number } = {} -- the open prompt for a pack of rotations, by token
local pendingCounter = 0

-- What a product gives, nil for a product the game doesn't sell.
local function productOf(productId: number): Purchases.Product?
	local tier = table.find(Config.REVIVE_PRODUCTS, productId)
	if tier then
		return { kind = "revive", tier = tier }
	end
	if Config.ROTATION_PRODUCT ~= 0 and productId == Config.ROTATION_PRODUCT then
		return { kind = "rotation", count = Config.ROTATION_PACK }
	end
	return nil
end

-- The price tier of the run's next revive.
local function nextTier(summary: GameRuns.RunSummary): number
	return Purchases.reviveTier(summary.revives, #Config.REVIVE_PRODUCTS)
end

-- Reads the prices once (cached for the server's lifetime); a failed read just means no price is shown. The
-- rotation pack's price is published as an attribute of ReplicatedStorage for the clients' button.
local function fetchPrices()
	local productIds = table.clone(Config.REVIVE_PRODUCTS)
	if Config.ROTATION_PRODUCT ~= 0 then
		table.insert(productIds, Config.ROTATION_PRODUCT)
	end
	for _, productId in productIds do
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			prices[productId] = info.PriceInRobux
		elseif IS_STUDIO then
			warn(`[ChikaBlock] couldn't read the price of product {productId}: {info}`)
		end
	end
	local rotationPrice = prices[Config.ROTATION_PRODUCT]
	if rotationPrice then
		ReplicatedStorage:SetAttribute("RotationPrice", rotationPrice)
	end
end

-- Offers a revive on the game over panel: the price of the next one, or that one is already paid for.
function PurchaseService.sendOffer(player: Player, runId: number)
	local data = DataService.get(player)
	local summary = GameService.getRuns():summary(player)
	if not data or not summary or not summary.isOver or summary.mode ~= "normal" or summary.runId ~= runId then
		return
	end
	local productId = Purchases.reviveProduct(Config.REVIVE_PRODUCTS, summary.revives)
	local tokens = PlayerData.reviveTokenCount(data, nextTier(summary))
	Net.ReviveOffer:FireClient(player, runId, { tokens = tokens, price = prices[productId] })
	GameService.logRevive(player, 1)
end

-- Uses a paid revive on the run, one bought at the price of this revive or a higher one. False (and nothing
-- spent) when there is none or the run can't be revived right now.
local function reviveWithToken(player: Player, data: PlayerData.PlayerData, runId: number): boolean
	local summary = GameService.getRuns():summary(player)
	if not summary then
		return false
	end
	local tier = nextTier(summary)
	if PlayerData.reviveTokenCount(data, tier) <= 0 or not GameService.revive(player, runId) then
		return false
	end
	PlayerData.useReviveToken(data, tier)
	return true
end

local function clearPending(player: Player, runId: number?)
	local entry = pending[player]
	if entry and (runId == nil or entry.runId == runId) then
		pending[player] = nil
	end
end

local function onRequestRevive(player: Player, runId: unknown)
	if not requestLimiter:allow(player) or typeof(runId) ~= "number" then
		return
	end
	local data = DataService.get(player)
	local summary = GameService.getRuns():summary(player)
	if not data or not summary or not summary.isOver or summary.mode ~= "normal" or summary.runId ~= runId then
		Net.ReviveResult:FireClient(player, runId, false)
		return
	end
	if pending[player] then
		return -- the purchase prompt is open already
	end
	GameService.logRevive(player, 2)

	if PlayerData.reviveTokenCount(data, nextTier(summary)) > 0 then
		if not reviveWithToken(player, data, runId) then
			Net.ReviveResult:FireClient(player, runId, false)
		end
		return
	end

	local productId = Purchases.reviveProduct(Config.REVIVE_PRODUCTS, summary.revives)
	pendingCounter += 1
	local token = pendingCounter
	pending[player] = { runId = runId, productId = productId, token = token }
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		warn(`[ChikaBlock] couldn't open the purchase prompt for {player.Name}: {err}`)
		clearPending(player, runId)
		Net.ReviveResult:FireClient(player, runId, false)
		return
	end
	task.delay(PROMPT_TIMEOUT_SECONDS, function()
		local entry = pending[player]
		if entry and entry.token == token then
			pending[player] = nil
			Net.ReviveResult:FireClient(player, runId, false)
		end
	end)
end

-- The player is out of rotations and pressed rotate during a run: open the prompt for the pack. The granted
-- purchase comes back through ProcessReceipt, which adds the rotations and sends the profile.
local function onRequestRotations(player: Player)
	if not rotationLimiter:allow(player) or Config.ROTATION_PRODUCT == 0 or rotationPending[player] then
		return
	end
	local summary = GameService.getRuns():summary(player)
	if not summary or summary.isOver or summary.mode ~= "normal" then
		return
	end
	GameService.logRotation(player, 1)
	pendingCounter += 1
	local token = pendingCounter
	rotationPending[player] = token
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, Config.ROTATION_PRODUCT)
	end)
	if not ok then
		warn(`[ChikaBlock] couldn't open the purchase prompt for {player.Name}: {err}`)
		rotationPending[player] = nil
		return
	end
	task.delay(PROMPT_TIMEOUT_SECONDS, function()
		if rotationPending[player] == token then
			rotationPending[player] = nil
		end
	end)
end

-- After a purchase is granted and saved: use it on the run that was waiting, if that run still can be revived.
local function afterGrant(playerId: number, data: PlayerData.PlayerData, product: Purchases.Product)
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	if product.kind == "rotation" then
		rotationPending[player] = nil
		GameService.logRotation(player, 2)
		GameService.sendProfile(player) -- the new count
		return
	end
	GameService.logRevive(player, 3)
	local entry = pending[player]
	pending[player] = nil
	if entry and reviveWithToken(player, data, entry.runId) then
		return
	end
	-- Nothing to revive right now: the revive stays in the data. Show the player they have it.
	local summary = GameService.getRuns():summary(player)
	if summary and summary.isOver then
		PurchaseService.sendOffer(player, summary.runId)
	end
end

local receiptDeps: Purchases.Deps = {
	productOf = productOf,
	getData = function(playerId: number): PlayerData.PlayerData?
		local player = Players:GetPlayerByUserId(playerId)
		return if player then DataService.waitForData(player, DATA_WAIT_SECONDS) else nil
	end,
	confirmSaved = function(playerId: number, purchaseId: string): boolean
		local player = Players:GetPlayerByUserId(playerId)
		if not player then
			return false
		end
		return DataService.waitUntilSaved(player, function(saved: any): boolean
			return typeof(saved.purchaseIds) == "table" and table.find(saved.purchaseIds, purchaseId) ~= nil
		end)
	end,
	afterGrant = afterGrant,
	warn = function(message: string)
		warn(`[ChikaBlock] {message}`)
	end,
}

-- Handles one receipt (also called by the Studio debug bridge with a made-up one).
function PurchaseService.process(receipt: Purchases.Receipt): Purchases.Decision
	return Purchases.process(receipt, receiptDeps)
end

function PurchaseService.start(_self: any)
	task.spawn(fetchPrices)

	GameService.onGameOver(function(player: Player, runId: number)
		PurchaseService.sendOffer(player, runId)
	end)
	Net.RequestRevive.OnServerEvent:Connect(onRequestRevive)
	Net.RequestRotations.OnServerEvent:Connect(onRequestRotations)

	-- Closing the prompt without buying frees the Revive button again.
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, bought: boolean)
			if productId == Config.ROTATION_PRODUCT then
				local rotationPlayer = Players:GetPlayerByUserId(userId)
				if rotationPlayer then
					rotationPending[rotationPlayer] = nil
				end
				return
			end
			if bought then
				return -- ProcessReceipt takes it from here
			end
			local player = Players:GetPlayerByUserId(userId)
			local entry = player and pending[player]
			if player and entry and entry.productId == productId then
				pending[player] = nil
				Net.ReviveResult:FireClient(player, entry.runId, false)
			end
		end
	)

	MarketplaceService.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
		local decision = PurchaseService.process({
			PlayerId = info.PlayerId,
			ProductId = info.ProductId,
			PurchaseId = info.PurchaseId,
		})
		return if decision == "granted"
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
		rotationPending[player] = nil
		requestLimiter:forget(player)
		rotationLimiter:forget(player)
	end)
end

return PurchaseService
