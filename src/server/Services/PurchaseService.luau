--!strict
-- Paid revives. After a game over the player is offered a revive: for a revive bought earlier it is free, else
-- Revive opens Roblox's purchase prompt for the product that fits the run (10, 15, then 25 Robux). The
-- purchase arrives in ProcessReceipt, which grants one revive, waits until it is saved (see Purchases) and
-- then uses it on the run that was waiting. A revive that cannot be used right away (the player left the run,
-- the connection dropped) stays in their data for the next game over. Everything about money is decided
-- here: the client only asks, and never picks a product. The same goes for the pack of rotations the player
-- can buy when they have none left, and for donations: the Support screen sends only which tier was chosen.
--
-- A revive is for whichever run the player is in, a solo run or a Co-op one (contextOf). In a Co-op run both players
-- are offered it and either can pay; it revives the run for both. The one whose purchase is granted first uses it. A
-- revive that arrives after the partner's has already revived the run is not used and stays in the buyer's data for
-- the next game over, as one that arrives with nothing to revive always has.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require("./DataService")
local CoopService = require("./CoopService")
local GameService = require("./GameService")
local LeaderboardService = require("./LeaderboardService")
local PlayerData = require("../PlayerData")
local Purchases = require("../Purchases")
local RateLimiter = require("../Util/RateLimiter")

local IS_STUDIO = RunService:IsStudio()
local DATA_WAIT_SECONDS = 20 -- how long a receipt waits for the player's data
local PROMPT_TIMEOUT_SECONDS = 180 -- a prompt nobody answered stops blocking new requests after this

-- What the player is buying right now: for which run (a solo or a Co-op run, which number their runs separately),
-- and which product.
type Pending = { kind: "solo" | "coop", runId: number, productId: number, token: number }

local PurchaseService = {}

local pending: { [Player]: Pending } = {} -- the open prompt for a revive
local promptPending: { [Player]: number } = {} -- the open prompt for a rotation pack or a donation, by token
local prices: { [number]: number } = {} -- Robux price of each product, read from Roblox
local requestLimiter = RateLimiter.new(1, 1, os.clock)
local promptLimiter = RateLimiter.new(1, 2, os.clock)
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
	local donation = if productId ~= 0 then table.find(Config.DONATE_PRODUCTS, productId) else nil
	if donation then
		return { kind = "donation", tier = donation }
	end
	return nil
end

-- The run the player is in: a Co-op run first (a player in a Co-op room has no solo run), else a solo run that is
-- not the tutorial. Nil when they have none.
local function contextOf(player: Player): Purchases.RunContext?
	local coop = CoopService.summaryOf(player)
	if coop then
		return { kind = "coop", runId = coop.runId, isOver = coop.isOver, revives = coop.revives }
	end
	local solo = GameService.getRuns():summary(player)
	if solo and solo.mode == "normal" then
		return { kind = "solo", runId = solo.runId, isOver = solo.isOver, revives = solo.revives }
	end
	return nil
end

-- The price tier of the run's next revive.
local function nextTier(context: Purchases.RunContext): number
	return Purchases.reviveTier(context.revives, #Config.REVIVE_PRODUCTS)
end

-- One step of the revive funnel; a Co-op run has a funnel of its own.
local function logRevive(player: Player, context: Purchases.RunContext?, step: number)
	if not context then
		return
	elseif context.kind == "coop" then
		GameService.logCoopRevive(player, `c{context.runId}.{context.revives}`, step)
	else
		GameService.logRevive(player, step)
	end
end

-- One step of the rotation funnel.
local function logRotation(player: Player, context: Purchases.RunContext?, step: number)
	if not context then
		return
	elseif context.kind == "coop" then
		GameService.logCoopRotation(player, context.runId, step)
	else
		GameService.logRotation(player, step)
	end
end

-- Reads the prices once (cached for the server's lifetime); a failed read just means no price is shown. The
-- rotation pack's and the donation tiers' prices are published as attributes of ReplicatedStorage for the clients'
-- buttons (RotationPrice, DonatePrice1 ... DonatePrice9).
local function fetchPrices()
	local productIds = table.clone(Config.REVIVE_PRODUCTS)
	if Config.ROTATION_PRODUCT ~= 0 then
		table.insert(productIds, Config.ROTATION_PRODUCT)
	end
	for _, productId in Config.DONATE_PRODUCTS do
		if productId ~= 0 then
			table.insert(productIds, productId)
		end
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
	for tier, productId in Config.DONATE_PRODUCTS do
		local price = prices[productId]
		if price then
			ReplicatedStorage:SetAttribute(`DonatePrice{tier}`, price)
		end
	end
end

-- The Robux price Roblox lists for a product (nil until it has been read); for the Studio debug bridge.
function PurchaseService.priceOf(productId: number): number?
	return prices[productId]
end

-- Offers a revive on the game over panel: the price of the next one, or that one is already paid for. In a Co-op run
-- this goes to each player still in it.
function PurchaseService.sendOffer(player: Player, runId: number)
	local data = DataService.get(player)
	local context = contextOf(player)
	if not data or not context or not context.isOver or context.runId ~= runId then
		return
	end
	local productId = Purchases.reviveProduct(Config.REVIVE_PRODUCTS, context.revives)
	local tokens = PlayerData.reviveTokenCount(data, nextTier(context))
	Net.ReviveOffer:FireClient(player, runId, { tokens = tokens, price = prices[productId] })
	logRevive(player, context, 1)
end

-- Uses a paid revive on the run (of that kind: a solo and a Co-op run may share an id), one bought at the price of
-- this revive or a higher one. False (and nothing spent) when there is none, or the run can't be revived right now:
-- it is not the player's run any more, or not over (a Co-op partner revived it first).
local function reviveWithToken(
	player: Player,
	data: PlayerData.PlayerData,
	kind: "solo" | "coop",
	runId: number
): boolean
	local context = contextOf(player)
	if not context or not Purchases.reviveApplies(context, kind, runId) then
		return false
	end
	local tier = nextTier(context)
	if PlayerData.reviveTokenCount(data, tier) <= 0 then
		return false
	end
	local revived = if kind == "coop" then CoopService.revive(player, runId) else GameService.revive(player, runId)
	if not revived then
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
	local context = contextOf(player)
	if not data or not context or not context.isOver or context.runId ~= runId then
		Net.ReviveResult:FireClient(player, runId, false)
		return
	end
	if pending[player] then
		return -- the purchase prompt is open already
	end
	logRevive(player, context, 2)

	if PlayerData.reviveTokenCount(data, nextTier(context)) > 0 then
		if not reviveWithToken(player, data, context.kind, runId) then
			Net.ReviveResult:FireClient(player, runId, false)
		end
		return
	end

	local productId = Purchases.reviveProduct(Config.REVIVE_PRODUCTS, context.revives)
	pendingCounter += 1
	local token = pendingCounter
	pending[player] = { kind = context.kind, runId = runId, productId = productId, token = token }
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

-- Opens the purchase prompt for a product that isn't tied to a run (a rotation pack or a donation) and
-- remembers it until it is answered or times out. Returns the prompt's token, or nil when it could not open.
local function openPrompt(player: Player, productId: number): number?
	pendingCounter += 1
	local token = pendingCounter
	promptPending[player] = token
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		warn(`[ChikaBlock] couldn't open the purchase prompt for {player.Name}: {err}`)
		promptPending[player] = nil
		return nil
	end
	task.delay(PROMPT_TIMEOUT_SECONDS, function()
		if promptPending[player] == token then
			promptPending[player] = nil
		end
	end)
	return token
end

-- The player is out of rotations and pressed rotate during a run (solo or Co-op): open the prompt for the pack. The
-- granted purchase comes back through ProcessReceipt, which adds the rotations and sends the profile.
local function onRequestRotations(player: Player)
	if not promptLimiter:allow(player) or Config.ROTATION_PRODUCT == 0 or promptPending[player] then
		return
	end
	local context = contextOf(player)
	if not context or context.isOver then
		return
	end
	logRotation(player, context, 1)
	openPrompt(player, Config.ROTATION_PRODUCT)
end

-- A tier was chosen on the Support screen: open the prompt for its product. The client only says which tier
-- (1 is the smallest); the granted purchase comes back through ProcessReceipt, which adds what the player really
-- paid to their total.
local function onRequestDonate(player: Player, tier: unknown)
	if not promptLimiter:allow(player) or typeof(tier) ~= "number" or tier ~= math.floor(tier) then
		return
	end
	local productId = Config.DONATE_PRODUCTS[tier]
	if not productId or productId == 0 or promptPending[player] or not DataService.get(player) then
		return
	end
	local token = openPrompt(player, productId)
	if token then
		GameService.logDonate(player, tostring(token), 1)
	end
end

-- After a purchase is granted and saved: use it on the run that was waiting, if that run still can be revived.
local function afterGrant(playerId: number, data: PlayerData.PlayerData, product: Purchases.Product, donated: number)
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	if product.kind == "rotation" then
		promptPending[player] = nil
		logRotation(player, contextOf(player), 2)
		GameService.sendProfile(player) -- the new count
		return
	end
	if product.kind == "donation" then
		GameService.logDonate(player, tostring(promptPending[player] or 0), 2)
		promptPending[player] = nil
		GameService.logDonated(player, donated, product.tier)
		LeaderboardService.flush(player, data) -- onto the Supporters board right away
		LeaderboardService.refreshSoon()
		GameService.sendProfile(player) -- the new total
		Net.Donated:FireClient(player, donated, data.robuxDonated)
		return
	end
	logRevive(player, contextOf(player), 3)
	local entry = pending[player]
	pending[player] = nil
	if entry and reviveWithToken(player, data, entry.kind, entry.runId) then
		return
	end
	-- Nothing to revive right now (or the partner revived first): the revive stays in the data. Show the player they
	-- have it if there is a finished run to use it on.
	local context = contextOf(player)
	if context and context.isOver then
		PurchaseService.sendOffer(player, context.runId)
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
	CoopService.onGameOver(function(player: Player, runId: number)
		PurchaseService.sendOffer(player, runId)
	end)
	Net.RequestRevive.OnServerEvent:Connect(onRequestRevive)
	Net.RequestRotations.OnServerEvent:Connect(onRequestRotations)
	Net.RequestDonate.OnServerEvent:Connect(onRequestDonate)

	-- Closing a prompt frees the Revive button, or the next rotation or donation request, again.
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, bought: boolean)
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				return
			end
			if productId == Config.ROTATION_PRODUCT or table.find(Config.DONATE_PRODUCTS, productId) then
				promptPending[player] = nil
				return
			end
			if bought then
				return -- ProcessReceipt takes it from here
			end
			local entry = pending[player]
			if entry and entry.productId == productId then
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
			CurrencySpent = if info.CurrencyType == Enum.CurrencyType.Robux then info.CurrencySpent else nil,
		})
		return if decision == "granted"
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
		promptPending[player] = nil
		requestLimiter:forget(player)
		promptLimiter:forget(player)
	end)
end

return PurchaseService
