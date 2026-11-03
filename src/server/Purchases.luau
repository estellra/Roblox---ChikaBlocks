--!strict
-- Developer product purchases, without Roblox: which product a revive costs and how a receipt is handled
-- (a revive bought at some price, a pack of rotations, or a donation).
-- Pure Luau so Lune can test it; PurchaseService passes in the real services.
--
-- A receipt is handled so that a purchase is never granted twice and never reported as granted before it is
-- safely saved:
--   - every handled PurchaseId is remembered in the player's data, so Roblox calling again (it does, until
--     it hears "granted", even after the player rejoins) never pays out a second time;
--   - the grant counts as done only once the data holding it is known to be saved; if that cannot be
--     confirmed, the answer is "notProcessedYet" and Roblox asks again later.
local PlayerData = require("./PlayerData")

-- CurrencySpent is what the player really paid in Robux (regional prices make it differ from the list
-- price); nil when they paid with anything else.
export type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string, CurrencySpent: number? }

export type Decision = "granted" | "notProcessedYet"

-- What a product gives: a revive at a price tier (1 is the cheapest), a number of rotations, or a donation
-- (tier 1 is the smallest).
export type Product =
	{ kind: "revive", tier: number }
	| { kind: "rotation", count: number }
	| { kind: "donation", tier: number }

export type Deps = {
	-- What a product gives, nil for a product the game doesn't sell.
	productOf: (productId: number) -> Product?,
	-- The player's loaded data; nil when they have left or it didn't load in time.
	getData: (playerId: number) -> PlayerData.PlayerData?,
	-- Yields until the data holding `purchaseId` is saved; false if that can't be confirmed (session ended).
	confirmSaved: (playerId: number, purchaseId: string) -> boolean,
	-- Runs once, after the first grant is saved: e.g. use the new revive on the run waiting for it.
	afterGrant: (playerId: number, data: PlayerData.PlayerData, product: Product, donated: number) -> (),
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

-- The Robux a donation counts for: what the player paid, in whole Robux. Nothing for a missing, negative
-- or otherwise unusable number.
function Purchases.donationAmount(spent: unknown): number
	if typeof(spent) ~= "number" or spent ~= spent or spent < 0 or spent == math.huge then
		return 0
	end
	return math.floor(spent)
end

function Purchases.process(receipt: Receipt, deps: Deps): Decision
	local product = deps.productOf(receipt.ProductId)
	if not product then
		deps.warn(`no handler for product {receipt.ProductId} (purchase {receipt.PurchaseId})`)
		return "notProcessedYet"
	end
	local data = deps.getData(receipt.PlayerId)
	if not data then
		return "notProcessedYet" -- asked again when the player is back
	end

	local donated = if product.kind == "donation" then Purchases.donationAmount(receipt.CurrencySpent) else 0
	local purchaseId = receipt.PurchaseId
	local isNew = not PlayerData.hasPurchase(data, purchaseId)
	if isNew then
		if product.kind == "revive" then
			PlayerData.addReviveToken(data, product.tier)
		elseif product.kind == "rotation" then
			PlayerData.addRotations(data, product.count)
		else
			PlayerData.addDonation(data, donated)
		end
		PlayerData.rememberPurchase(data, purchaseId)
	end
	if not deps.confirmSaved(receipt.PlayerId, purchaseId) then
		return "notProcessedYet"
	end
	if isNew then
		deps.afterGrant(receipt.PlayerId, data, product, donated)
	end
	return "granted"
end

return Purchases
