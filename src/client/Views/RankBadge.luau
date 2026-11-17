--!strict
-- A rank tier's badge: a round token in the tier's color with an outline and a shine. It stands in for the RankBadge
-- images of the Figma mockups (component set "RankBadge" on Foundations) until those are uploaded to Roblox.
local Theme = require("./Theme")
local create = require("./Create")

local RankBadge = {}

--- A badge `size` pixels across, painted for `tier` (a Config.PVP.TIERS id).
function RankBadge.new(size: number, tier: string?, order: number?): Frame
	local badge = create("Frame", {
		Name = "RankBadge",
		LayoutOrder = order or 0,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.Tiers.Bronze,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = Theme.Colors.Outline, Thickness = math.max(1.5, size / 14) }),
		create("Frame", {
			Name = "Shine",
			Position = UDim2.fromScale(0.22, 0.18),
			Size = UDim2.fromScale(0.3, 0.16),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }),
	})
	if tier then
		RankBadge.paint(badge, tier)
	end
	return badge
end

--- Colors the badge for `tier`.
function RankBadge.paint(badge: Frame, tier: string)
	badge.BackgroundColor3 = Theme.Colors.Tiers[tier] or Theme.Colors.Tiers.Bronze
end

return RankBadge
