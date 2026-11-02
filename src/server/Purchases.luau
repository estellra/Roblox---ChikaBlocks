--!strict
-- Developer product purchases, without Roblox: which product a revive costs and how a receipt is handled.
-- Pure Luau so Lune can test it; PurchaseService passes in the real services.
--
-- A receipt is handled so that a purchase is never granted twice and never reported as granted before it is
-- safely saved:
--   - every handled PurchaseId is remembered in the player's data, so Roblox calling again (it does, until
--     it hears "granted", even after the player rejoins) never pays out a second time;
--   - the grant counts as done only once the data holding it is known to be saved; if that cannot be
--     confirmed, the answer is "notProcessedYet" and Roblox asks again later.
local PlayerData = require("./PlayerData")

export type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

export type Decision = "granted" | "notProcessedYet"

export type Deps = {
	-- The price tier of a revive product (1 is the cheapest), nil for any other product.
	tierOf: (productId: number) -> number?,
	-- The player's loaded data; nil when they have left or it didn't load in time.
	getData: (playerId: number) -> PlayerData.PlayerData?,
	-- Yields until the data holding `purchaseId` is saved; false if that can't be confirmed (session ended).
	confirmSaved: (playerId: number, purchaseId: string) -> boolean,
	-- Runs once, after the first grant is saved: use the new revive on the run waiting for it.
	afterGrant: (playerId: number, data: PlayerData.PlayerData) -> (),
	warn: (message: string) -> (),
}

local Purchases = {}

-- The price tier of the player's next revive: one per revive already used in the run, the last from then on.
function Purchases.reviveTier(revivesUsed: number, tiers: number): number
	return math.clamp(revivesUsed + 1, 1, tiers)
end

-- The product for the player's next revive: one per revive already used in the run, the last one from then on.
function Purchases.reviveProduct(products: { number }, revivesUsed: number): number
	return products[Purchases.reviveTier(revivesUsed, #products)]
end

function Purchases.process(receipt: Receipt, deps: Deps): Decision
	local tier = deps.tierOf(receipt.ProductId)
	if not tier then
		deps.warn(`no handler for product {receipt.ProductId} (purchase {receipt.PurchaseId})`)
		return "notProcessedYet"
	end
	local data = deps.getData(receipt.PlayerId)
	if not data then
		return "notProcessedYet" -- asked again when the player is back
	end

	local purchaseId = receipt.PurchaseId
	local isNew = not PlayerData.hasPurchase(data, purchaseId)
	if isNew then
		PlayerData.addReviveToken(data, tier)
		PlayerData.rememberPurchase(data, purchaseId)
	end
	if not deps.confirmSaved(receipt.PlayerId, purchaseId) then
		return "notProcessedYet"
	end
	if isNew then
		deps.afterGrant(receipt.PlayerId, data)
	end
	return "granted"
end

return Purchases
