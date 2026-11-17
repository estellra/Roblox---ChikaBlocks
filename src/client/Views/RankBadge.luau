--!strict
-- A rank tier's badge: the shield of the Figma mockups (component set "RankBadge" 81:6639 on Foundations, exported to
-- assets/rank/ and uploaded; ids in Theme.Images). The badge is a transparent frame holding the image, so it sits in
-- layouts like any frame.
local Theme = require("./Theme")
local create = require("./Create")

local RankBadge = {}

--- A badge `size` pixels across, showing `tier` (a Config.PVP.TIERS id, or "Top10" / "Champion").
function RankBadge.new(size: number, tier: string?, order: number?): Frame
	local badge = create("Frame", {
		Name = "RankBadge",
		LayoutOrder = order or 0,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, {
		create("ImageLabel", {
			Name = "Image",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Image = Theme.Images.RankBronze,
		}),
	})
	if tier then
		RankBadge.paint(badge, tier)
	end
	return badge
end

--- Shows `tier`'s badge.
function RankBadge.paint(badge: Frame, tier: string)
	local image = badge:FindFirstChild("Image") :: ImageLabel?
	if image then
		image.Image = Theme.Images[`Rank{tier}`] or Theme.Images.RankBronze
	end
end

return RankBadge
