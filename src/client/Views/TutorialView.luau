--!strict
-- Tutorial overlay: a pointer that keeps sliding from a tray slot to the suggested board cell, a line of
-- instructions above the board, and a short tip. Positions are recomputed on every pass, so the hint keeps
-- up with rotation and layout changes. A gray-box placeholder until the mockups arrive.
local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")
local create = require("./Create")

local HAND_SIZE = 36

local TutorialView = {}
TutorialView.__index = TutorialView

export type TutorialView = typeof(setmetatable(
	{} :: {
		layer: GuiObject, -- full-screen layer the pointer moves in (pixel positions)
		hand: Frame,
		instruction: TextLabel,
		tip: TextLabel,
		hintToken: number, -- bumped to stop the pointer loop
		tipToken: number,
	},
	TutorialView
))

local function banner(name: string, color: Color3): TextLabel
	return create("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0), -- positioned by its top edge; width set when shown
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Label,
		TextWrapped = true,
		TextColor3 = color,
		Visible = false,
		ZIndex = 5,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		create("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
	})
end

function TutorialView.new(layer: GuiObject): TutorialView
	local hand = create("Frame", {
		Name = "Hand",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(HAND_SIZE, HAND_SIZE),
		BackgroundColor3 = Theme.Colors.Hand,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = Theme.Colors.Background, Thickness = 3 }),
	})
	local instruction = banner("Instruction", Theme.Colors.Text)
	local tip = banner("Tip", Theme.Colors.Combo)
	hand.Parent = layer
	instruction.Parent = layer
	tip.Parent = layer
	return setmetatable({
		layer = layer,
		hand = hand,
		instruction = instruction,
		tip = tip,
		hintToken = 0,
		tipToken = 0,
	}, TutorialView)
end

local function toLayer(self: TutorialView, point: Vector2): UDim2
	local origin = self.layer.AbsolutePosition
	return UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
end

-- Puts a banner's top middle at `at` (screen pixels), `width` pixels wide.
local function placeBanner(self: TutorialView, label: TextLabel, at: Vector2, width: number)
	label.Position = toLayer(self, at)
	label.Size = UDim2.fromOffset(width, 0)
end

-- Loops the pointer from `from()` to `to()` (screen pixels) and shows `text()` in the banner until hideHint();
-- `bannerAt()` gives the banner's top middle and width. `text` is read on every pass too, so it can follow
-- the input device in use.
function TutorialView.showHint(
	self: TutorialView,
	text: () -> string,
	from: () -> Vector2,
	to: () -> Vector2,
	bannerAt: () -> (Vector2, number)
)
	self.hintToken += 1
	local token = self.hintToken
	self.instruction.Visible = true
	self.hand.Visible = true
	task.spawn(function()
		local info = TweenInfo.new(Theme.Motion.HandMove, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		while token == self.hintToken do
			self.instruction.Text = text()
			placeBanner(self, self.instruction, bannerAt())
			self.hand.Position = toLayer(self, from())
			TweenService:Create(self.hand, info, { Position = toLayer(self, to()) }):Play()
			task.wait(Theme.Motion.HandMove + Theme.Motion.HandPause)
		end
	end)
end

function TutorialView.hideHint(self: TutorialView)
	self.hintToken += 1
	self.hand.Visible = false
	self.instruction.Visible = false
end

function TutorialView.isHintVisible(self: TutorialView): boolean
	return self.hand.Visible
end

-- Shows `text` for `seconds`, its top middle at `at` (screen pixels), `width` pixels wide.
function TutorialView.showTip(self: TutorialView, text: string, at: Vector2, width: number, seconds: number)
	self.tipToken += 1
	local token = self.tipToken
	self.tip.Text = text
	placeBanner(self, self.tip, at, width)
	self.tip.Visible = true
	task.delay(seconds, function()
		if token == self.tipToken then
			self.tip.Visible = false
		end
	end)
end

function TutorialView.hideTip(self: TutorialView)
	self.tipToken += 1
	self.tip.Visible = false
end

function TutorialView.destroy(self: TutorialView)
	self:hideHint()
	self:hideTip()
	self.hand:Destroy()
	self.instruction:Destroy()
	self.tip:Destroy()
end

return TutorialView
