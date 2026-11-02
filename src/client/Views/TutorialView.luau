--!strict
-- Tutorial overlay, as in the mockups: a card with the mascot and what to do, a Skip button, the cells the
-- hinted piece would fill, a dotted arrow from the tray slot to them, and a hand that keeps sliding along it.
-- Positions are recomputed on every pass, so everything keeps up with rotation and layout changes.
local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")
local create = require("./Create")

local HAND_SIZE = 56
local HAND_TIP = Vector2.new(0.42, 0.1) -- where the fingertip is in the hand image
local PATH_DOTS = 16
local MAX_TARGET_CELLS = 5
local ARROW_LENGTH = 13

export type Rect = { x: number, y: number, width: number, height: number } -- screen pixels

export type Hint = {
	copy: () -> (string, string), -- title and subtitle; read on every pass so they follow the input device
	from: () -> Vector2, -- where the hand starts (the hinted tray slot), screen pixels
	to: () -> Vector2, -- where it ends (the piece's place on the board)
	targets: () -> { Rect }, -- the cells the piece would fill
	area: () -> (Vector2, Vector2), -- top left and size of the area the card sits in (the HUD's)
}

type Card = { frame: Frame, mascot: ImageLabel, title: TextLabel, subtitle: TextLabel }

local TutorialView = {}
TutorialView.__index = TutorialView

export type TutorialView = typeof(setmetatable(
	{} :: {
		layer: GuiObject, -- full-screen layer everything is drawn in (pixel positions)
		hint: Card,
		tip: Card,
		skip: TextButton,
		hand: ImageLabel,
		dots: { Frame },
		arrow: { Frame },
		targets: { Frame },
		hintToken: number, -- bumped to stop the loop
		tipToken: number,
	},
	TutorialView
))

local function buildCard(name: string, mascotImage: string): Card
	local mascot = create("ImageLabel", {
		Name = "Mascot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Image = mascotImage,
	})
	local title = create("TextLabel", {
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Title,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextColor3 = Theme.Colors.Text,
		Text = "",
	})
	local subtitle = create("TextLabel", {
		Name = "Subtitle",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "",
	})
	local frame = create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(280, 72),
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 20) }),
		create("UIStroke", { Color = Theme.Colors.Outline, Thickness = Theme.Stroke.Panel }),
		mascot,
		create("Frame", {
			Name = "Text",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 72, 0.5, 0),
			Size = UDim2.new(1, -84, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			title,
			subtitle,
		}),
	})
	return { frame = frame, mascot = mascot, title = title, subtitle = subtitle }
end

local function dot(): Frame
	return create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Theme.Colors.Outline,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

function TutorialView.new(layer: GuiObject, onSkip: () -> ()): TutorialView
	local hint = buildCard("HintCard", Theme.Images.MascotHappy)
	local tip = buildCard("TipCard", Theme.Images.MascotCheer)

	local skip = create("TextButton", {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(68, 44),
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Theme.Fonts.Label,
		TextSize = 16,
		TextColor3 = Theme.Colors.Text,
		Text = "Skip",
		Visible = false,
		ZIndex = 5,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", {
			Color = Theme.Colors.Outline,
			Thickness = Theme.Stroke.Pill,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border, -- not the text
		}),
	})
	skip.Activated:Connect(onSkip)

	local hand = create("ImageLabel", {
		Name = "Hand",
		AnchorPoint = HAND_TIP,
		Size = UDim2.fromOffset(HAND_SIZE, HAND_SIZE),
		BackgroundTransparency = 1,
		Image = Theme.Images.Hand,
		Visible = false,
		ZIndex = 8,
	})

	local dots, arrow, targets = {}, {}, {}
	for i = 1, PATH_DOTS do
		dots[i] = dot()
	end
	for i = 1, 2 do
		arrow[i] = create("Frame", {
			Name = "ArrowHead",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(ARROW_LENGTH, 3),
			BackgroundColor3 = Theme.Colors.Outline,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 6,
		}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	for i = 1, MAX_TARGET_CELLS do
		targets[i] = create("Frame", {
			Name = "Target",
			BackgroundColor3 = Theme.Colors.Pieces[5],
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 4,
		}, {
			create("UICorner", { CornerRadius = Theme.Radius.Cell }),
			create("UIStroke", { Color = Theme.Colors.PieceOutlines[5], Thickness = 2 }),
		})
	end

	for _, object in { hint.frame, tip.frame, skip, hand } do
		object.Parent = layer
	end
	for _, group in { dots, arrow, targets } do
		for _, object in group do
			object.Parent = layer
		end
	end
	return setmetatable({
		layer = layer,
		hint = hint,
		tip = tip,
		skip = skip,
		hand = hand,
		dots = dots,
		arrow = arrow,
		targets = targets,
		hintToken = 0,
		tipToken = 0,
	}, TutorialView)
end

local function toLayer(self: TutorialView, point: Vector2): Vector2
	return point - self.layer.AbsolutePosition
end

-- Puts a card in the top left of `area`: as wide as fits (leaving room for Skip), or, with `cover`, exactly over it.
local function placeCard(self: TutorialView, card: Card, area: () -> (Vector2, Vector2), cover: boolean)
	local position, size = area()
	local local_ = toLayer(self, position)
	card.frame.Position = UDim2.fromOffset(local_.X, local_.Y)
	if cover then
		card.frame.Size = UDim2.fromOffset(size.X, size.Y)
	else
		card.frame.Size = UDim2.fromOffset(math.clamp(size.X - 84, 200, 300), math.clamp(size.Y, 64, 84))
	end
end

-- Draws the dotted arrow from `from` to `to`, curving a little upward.
local function drawPath(self: TutorialView, from: Vector2, to: Vector2)
	local a, c = toLayer(self, from), toLayer(self, to)
	local chord = c - a
	local length = chord.Magnitude
	if length < 1 then
		return
	end
	local normal = Vector2.new(chord.Y, -chord.X) / length
	if normal.Y > 0 then
		normal = -normal
	end
	local b = (a + c) / 2 + normal * length * 0.22
	local function at(t: number): Vector2
		return a * (1 - t) ^ 2 + b * 2 * t * (1 - t) + c * t ^ 2
	end
	for i, d in self.dots do
		local p = at(0.12 + 0.78 * (i - 1) / (PATH_DOTS - 1))
		d.Position = UDim2.fromOffset(p.X, p.Y)
		d.Visible = true
	end
	-- The arrowhead sits at the end, its two strokes swept back from the direction of travel.
	local tangent = (c - b).Unit
	local tip = at(0.97)
	for i, head in self.arrow do
		local angle = math.atan2(tangent.Y, tangent.X) + math.rad(if i == 1 then 150 else -150)
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		local center = tip + direction * ARROW_LENGTH / 2
		head.Position = UDim2.fromOffset(center.X, center.Y)
		head.Rotation = math.deg(angle)
		head.Visible = true
	end
end

local function drawTargets(self: TutorialView, rects: { Rect })
	for i, frame in self.targets do
		local rect = rects[i]
		frame.Visible = rect ~= nil
		if rect then
			local p = toLayer(self, Vector2.new(rect.x, rect.y))
			frame.Position = UDim2.fromOffset(p.X, p.Y)
			frame.Size = UDim2.fromOffset(rect.width, rect.height)
		end
	end
end

local function hideDrawing(self: TutorialView)
	for _, group in { self.dots, self.arrow, self.targets } do
		for _, object in group do
			object.Visible = false
		end
	end
end

-- Shows the card, the target cells and the arrow, and loops the hand along it until hideHint().
function TutorialView.showHint(self: TutorialView, hint: Hint)
	self.hintToken += 1
	local token = self.hintToken
	self.hint.frame.Visible = true
	self.hand.Visible = true
	task.spawn(function()
		local info = TweenInfo.new(Theme.Motion.HandMove, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		while token == self.hintToken do
			local title, subtitle = hint.copy()
			self.hint.title.Text, self.hint.subtitle.Text = title, subtitle
			placeCard(self, self.hint, hint.area, false)
			local from, to = hint.from(), hint.to()
			drawTargets(self, hint.targets())
			drawPath(self, from, to)
			local start, finish = toLayer(self, from), toLayer(self, to)
			self.hand.Position = UDim2.fromOffset(start.X, start.Y)
			TweenService:Create(self.hand, info, { Position = UDim2.fromOffset(finish.X, finish.Y) }):Play()
			task.wait(Theme.Motion.HandMove + Theme.Motion.HandPause)
		end
	end)
end

function TutorialView.hideHint(self: TutorialView)
	self.hintToken += 1
	self.hint.frame.Visible = false
	self.hand.Visible = false
	hideDrawing(self)
end

function TutorialView.isHintVisible(self: TutorialView): boolean
	return self.hand.Visible
end

function TutorialView.setSkipVisible(self: TutorialView, visible: boolean)
	self.skip.Visible = visible
end

-- Shows a short message over the score bar's place for `seconds`.
function TutorialView.showTip(
	self: TutorialView,
	title: string,
	subtitle: string,
	area: () -> (Vector2, Vector2),
	seconds: number
)
	self.tipToken += 1
	local token = self.tipToken
	self.tip.title.Text, self.tip.subtitle.Text = title, subtitle
	placeCard(self, self.tip, area, true)
	self.tip.frame.Visible = true
	task.delay(seconds, function()
		if token == self.tipToken then
			self.tip.frame.Visible = false
		end
	end)
end

function TutorialView.hideTip(self: TutorialView)
	self.tipToken += 1
	self.tip.frame.Visible = false
end

function TutorialView.destroy(self: TutorialView)
	self:hideHint()
	self:hideTip()
	self.hint.frame:Destroy()
	self.tip.frame:Destroy()
	self.skip:Destroy()
	self.hand:Destroy()
	for _, group in { self.dots, self.arrow, self.targets } do
		for _, object in group do
			object:Destroy()
		end
	end
end

return TutorialView
