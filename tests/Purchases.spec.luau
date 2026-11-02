--!strict
local PlayerData = require("../src/server/PlayerData")
local Purchases = require("../src/server/Purchases")
local TestKit = require("./TestKit")

local PRODUCTS = { 111, 222, 333 }
local ROTATION_PRODUCT = 444
local ROTATION_PACK = 5
local PLAYER_ID = 7

local function newData(): PlayerData.PlayerData
	local data = table.clone(PlayerData.TEMPLATE) :: any
	data.milestonesClaimed = {}
	data.badgesAwarded = {}
	data.weekly = table.clone(PlayerData.TEMPLATE.weekly)
	data.purchaseIds = {}
	data.reviveTokens = { 0, 0, 0 }
	data.rotations = 0
	return data
end

-- A world for one receipt: the player's data (or none), whether saving works, and what afterGrant saw.
local function world(data: PlayerData.PlayerData?, saves: boolean)
	local state = {
		data = data,
		saves = saves,
		afterGrants = 0,
		lastKind = nil :: string?,
		warnings = {} :: { string },
	}
	local deps: Purchases.Deps = {
		productOf = function(productId: number): Purchases.Product?
			local tier = table.find(PRODUCTS, productId)
			if tier then
				return { kind = "revive", tier = tier }
			end
			if productId == ROTATION_PRODUCT then
				return { kind = "rotation", count = ROTATION_PACK }
			end
			return nil
		end,
		getData = function(_playerId: number): PlayerData.PlayerData?
			return state.data
		end,
		confirmSaved = function(_playerId: number, _purchaseId: string): boolean
			return state.saves
		end,
		afterGrant = function(_playerId: number, _data: PlayerData.PlayerData, product: Purchases.Product)
			state.afterGrants += 1
			state.lastKind = product.kind
		end,
		warn = function(message: string)
			table.insert(state.warnings, message)
		end,
	}
	return state, deps
end

local function total(data: PlayerData.PlayerData): number
	return data.reviveTokens[1] + data.reviveTokens[2] + data.reviveTokens[3]
end

local function receipt(productId: number, purchaseId: string): Purchases.Receipt
	return { PlayerId = PLAYER_ID, ProductId = productId, PurchaseId = purchaseId }
end

return function(t: TestKit.TestKit)
	t.describe("Purchases", function()
		t.it("charges 10, then 15, then 25 for the revives of one run", function()
			t.expect(Purchases.reviveProduct(PRODUCTS, 0)).toBe(111)
			t.expect(Purchases.reviveProduct(PRODUCTS, 1)).toBe(222)
			t.expect(Purchases.reviveProduct(PRODUCTS, 2)).toBe(333)
			t.expect(Purchases.reviveProduct(PRODUCTS, 3)).toBe(333)
			t.expect(Purchases.reviveProduct(PRODUCTS, 40)).toBe(333)
		end)

		t.it("picks the tier of a revive: the run's revives so far, at most the last tier", function()
			t.expect(Purchases.reviveTier(0, 3)).toBe(1)
			t.expect(Purchases.reviveTier(1, 3)).toBe(2)
			t.expect(Purchases.reviveTier(2, 3)).toBe(3)
			t.expect(Purchases.reviveTier(9, 3)).toBe(3)
		end)

		t.it("files a purchase under the tier of its product, so cheap ones cannot pay for dear revives", function()
			local data = newData()
			local _, deps = world(data, true)
			Purchases.process(receipt(111, "a"), deps)
			Purchases.process(receipt(333, "b"), deps)
			t.expect(data.reviveTokens).toEqual({ 1, 0, 1 })
		end)

		t.it("adds a pack of rotations for the rotation product, once per purchase", function()
			local data = newData()
			local state, deps = world(data, true)
			t.expect(Purchases.process(receipt(ROTATION_PRODUCT, "r1"), deps)).toBe("granted")
			t.expect(data.rotations).toBe(ROTATION_PACK)
			t.expect(total(data)).toBe(0) -- no revive came with it
			t.expect(state.lastKind).toBe("rotation")
			t.expect(state.afterGrants).toBe(1)

			t.expect(Purchases.process(receipt(ROTATION_PRODUCT, "r1"), deps)).toBe("granted") -- asked again
			t.expect(data.rotations).toBe(ROTATION_PACK)
			t.expect(state.afterGrants).toBe(1)

			t.expect(Purchases.process(receipt(ROTATION_PRODUCT, "r2"), deps)).toBe("granted")
			t.expect(data.rotations).toBe(2 * ROTATION_PACK)
		end)

		t.it("grants a rotation pack only once the purchase is saved", function()
			local data = newData()
			local state, deps = world(data, false)
			t.expect(Purchases.process(receipt(ROTATION_PRODUCT, "r1"), deps)).toBe("notProcessedYet")
			t.expect(data.rotations).toBe(ROTATION_PACK)
			t.expect(state.afterGrants).toBe(0)
			state.saves = true
			t.expect(Purchases.process(receipt(ROTATION_PRODUCT, "r1"), deps)).toBe("granted")
			t.expect(data.rotations).toBe(ROTATION_PACK) -- not paid out twice
		end)

		t.it("grants a revive once the purchase is saved and uses it", function()
			local data = newData()
			local state, deps = world(data, true)
			t.expect(Purchases.process(receipt(111, "a"), deps)).toBe("granted")
			t.expect(total(data)).toBe(1)
			t.expect(data.purchaseIds).toEqual({ "a" })
			t.expect(state.afterGrants).toBe(1)
		end)

		t.it("never grants the same purchase twice, however often Roblox asks", function()
			local data = newData()
			local state, deps = world(data, true)
			for _ = 1, 3 do
				t.expect(Purchases.process(receipt(111, "a"), deps)).toBe("granted")
			end
			t.expect(total(data)).toBe(1)
			t.expect(state.afterGrants).toBe(1)
			-- A different purchase is a different grant.
			t.expect(Purchases.process(receipt(222, "b"), deps)).toBe("granted")
			t.expect(total(data)).toBe(2)
		end)

		t.it("doesn't say granted until the data is saved, and doesn't grant twice when asked again", function()
			local data = newData()
			local state, deps = world(data, false)
			t.expect(Purchases.process(receipt(111, "a"), deps)).toBe("notProcessedYet")
			t.expect(total(data)).toBe(1)
			t.expect(state.afterGrants).toBe(0)

			t.expect(Purchases.process(receipt(111, "a"), deps)).toBe("notProcessedYet") -- still unsaved
			t.expect(total(data)).toBe(1)

			state.saves = true
			t.expect(Purchases.process(receipt(111, "a"), deps)).toBe("granted")
			t.expect(total(data)).toBe(1)
			-- The revive was already counted on the first try, so the second does not use it on a run.
			t.expect(state.afterGrants).toBe(0)
		end)

		t.it("asks again later when the player's data isn't there", function()
			local state, deps = world(nil, true)
			t.expect(Purchases.process(receipt(111, "a"), deps)).toBe("notProcessedYet")
			t.expect(state.afterGrants).toBe(0)
		end)

		t.it("asks again later, with a warning, for a product it doesn't know", function()
			local data = newData()
			local state, deps = world(data, true)
			t.expect(Purchases.process(receipt(999, "a"), deps)).toBe("notProcessedYet")
			t.expect(total(data)).toBe(0)
			t.expect(#state.warnings).toBe(1)
		end)

		t.it("remembers only the latest 100 purchases", function()
			local data = newData()
			local _, deps = world(data, true)
			for i = 1, 105 do
				Purchases.process(receipt(111, `p{i}`), deps)
			end
			t.expect(#data.purchaseIds).toBe(100)
			t.expect(data.purchaseIds[1]).toBe("p6")
			t.expect(data.purchaseIds[100]).toBe("p105")
			t.expect(total(data)).toBe(105)
		end)
	end)
end
