--!strict
-- The cheer after a big move: the mascot pops up on the board's top right corner with a speech bubble
-- ("Combo x3!", "Board clear!"), and sparkles fly over the board. All of it is over within about a second and a
-- half, and a new one replaces the one still showing.
local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")
local create = require("./Create")

local HOLD_SECONDS = 1.1
local SPARKLES = 5

local ComboPopup = {}
ComboPopup.__index = ComboPopup

export type ComboPopup = typeof(setmetatable(
	{} :: {
		area: GuiObject, -- the board's area; the popup is drawn over it
		current: Frame?,
		random: Random,
	},
	ComboPopup
))

function ComboPopup.new(area: GuiObject): ComboPopup
	return setmetatable({ area = area, current = nil, random = Random.new() }, ComboPopup)
end

-- Pops the mascot and a bubble saying `text` onto the board's top right corner.
function ComboPopup.show(self: ComboPopup, text: string)
	if self.current then
		self.current:Destroy()
	end
	local mascotSize = math.clamp(math.floor(self.area.AbsoluteSize.X * 0.17), 52, 96)
	local bubble = create("Frame", {
		Name = "Bubble",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, math.floor(mascotSize * 0.58)),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = Theme.Colors.Outline, Thickness = Theme.Stroke.Pill }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
		create("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			FontFace = Theme.Fonts.Title,
			TextSize = math.floor(mascotSize * 0.3),
			TextColor3 = Theme.Colors.Text,
			Text = text,
		}),
	})
	local mascot = create("ImageLabel", {
		Name = "Mascot",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(mascotSize, mascotSize),
		BackgroundTransparency = 1,
		Image = Theme.Images.MascotCheer,
	})
	local pop = create("UIScale", { Scale = 0.4 })
	local popup = create("Frame", {
		Name = "ComboPopup",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -8), -- straddles the board's top edge
		Size = UDim2.fromOffset(0, mascotSize),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = self.area,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
		}),
		pop,
		bubble,
		mascot,
	})
	self.current = popup

	TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(HOLD_SECONDS, function()
		if self.current ~= popup then
			return
		end
		local out =
			TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		out.Completed:Once(function()
			popup:Destroy()
			if self.current == popup then
				self.current = nil
			end
		end)
		out:Play()
	end)
end

-- Sparkles that pop up at random places on the board, spin and vanish.
function ComboPopup.sparkle(self: ComboPopup)
	local size = self.area.AbsoluteSize
	for index = 1, SPARKLES do
		local side = math.floor(self.random:NextNumber(18, 32))
		local spark = create("ImageLabel", {
			Name = "Sparkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(
				self.random:NextNumber(0.1, 0.9) * size.X,
				self.random:NextNumber(0.1, 0.9) * size.Y
			),
			Size = UDim2.fromOffset(side, side),
			BackgroundTransparency = 1,
			Image = Theme.Images.Sparkle,
			ZIndex = 19,
			Rotation = self.random:NextNumber(-20, 20),
			Parent = self.area,
		}, { create("UIScale", { Scale = 0 }) })
		local scale = spark:FindFirstChildOfClass("UIScale") :: UIScale
		task.delay((index - 1) * 0.08, function()
			local grow = TweenService:Create(
				scale,
				TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			)
			grow.Completed:Once(function()
				local shrink = TweenService:Create(
					scale,
					TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Scale = 0 }
				)
				shrink.Completed:Once(function()
					spark:Destroy()
				end)
				shrink:Play()
			end)
			grow:Play()
			TweenService:Create(spark, TweenInfo.new(0.6), { Rotation = spark.Rotation + 90 }):Play()
		end)
	end
end

return ComboPopup
