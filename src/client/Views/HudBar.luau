--!strict
-- The bar above the board: pause button, score, best score and combo. In landscape it sits on a card in the
-- side column; in portrait it floats on the sky across the top. All sizes are shares of the HUD area, so it
-- keeps its proportions on any screen.
local Clay = require("./Clay")
local Format = require("./Format")
local Theme = require("./Theme")
local create = require("./Create")

export type Mode = "Portrait" | "Landscape"

local SCORE_MIN, SCORE_MAX = 22, 56
local PILL_GAP = 6
local PILL_MIN, PILL_MAX = 22, 32

local HudBar = {}
HudBar.__index = HudBar

export type HudBar = typeof(setmetatable(
	{} :: {
		card: Frame,
		cardStroke: UIStroke,
		pauseButton: TextButton,
		pills: Frame,
		scoreLabel: TextLabel,
		bestPill: Frame,
		comboPill: Frame,
	},
	HudBar
))

function HudBar.new(hudArea: GuiObject, onPause: () -> ()): HudBar
	local colors, fonts = Theme.Colors, Theme.Fonts

	local pauseButton = Clay.iconButton({ name = "Pause", image = Theme.Images.Pause })
	pauseButton.AnchorPoint = Vector2.new(0, 0.5)
	pauseButton.Size = UDim2.fromScale(0.16, 0.56) -- fitted to a square within this
	create("UISizeConstraint", {
		MinSize = Theme.MinTouchTarget,
		MaxSize = Vector2.new(64, 64),
		Parent = pauseButton,
	})

	local scoreLabel = create("TextLabel", {
		Name = "Score",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0.68),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextScaled = true,
		TextColor3 = colors.Text,
		Text = "0",
	}, { create("UITextSizeConstraint", { MinTextSize = SCORE_MIN, MaxTextSize = SCORE_MAX }) })
	local scoreBlock = create("Frame", {
		Name = "ScoreBlock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.43, 0.5),
		Size = UDim2.fromScale(0.3, 0.86),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		create("TextLabel", {
			Name = "Caption",
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 0.26),
			BackgroundTransparency = 1,
			FontFace = fonts.Label,
			TextScaled = true,
			TextColor3 = colors.TextMuted,
			Text = "SCORE",
		}, { create("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = 16 }) }),
		scoreLabel,
	})

	local bestPill = Clay.pill({ name = "Best", text = "0", icon = Theme.Images.Crown, order = 1 })
	local comboPill = Clay.pill({ name = "Combo", text = "Combo x2", style = "reward", order = 2 })
	comboPill.Visible = false
	local pills = create("Frame", {
		Name = "Pills",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromScale(0.3, 0.86),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, PILL_GAP),
		}),
		bestPill,
		comboPill,
	})

	local cardStroke = create("UIStroke", {
		Color = colors.Outline,
		Thickness = Theme.Stroke.Panel,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local card = create("Frame", {
		Name = "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
		Parent = hudArea,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		cardStroke,
		pauseButton,
		scoreBlock,
		pills,
	})
	pauseButton.Activated:Connect(onPause)

	-- The two pills stack, so they shrink with the bar when it is short (a phone held sideways).
	local function fitPills()
		local room = card.AbsoluteSize.Y * 0.86 - PILL_GAP
		local height = math.clamp(math.floor(room / 2), PILL_MIN, PILL_MAX)
		Clay.setPillHeight(bestPill, height)
		Clay.setPillHeight(comboPill, height)
	end
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPills)

	local bar = setmetatable({
		card = card,
		cardStroke = cardStroke,
		pauseButton = pauseButton,
		pills = pills,
		scoreLabel = scoreLabel,
		bestPill = bestPill,
		comboPill = comboPill,
	}, HudBar)
	bar:setLayout("Portrait")
	return bar
end

-- Landscape puts the bar on a card; portrait lets it float on the sky.
function HudBar.setLayout(self: HudBar, mode: Mode)
	local card = mode == "Landscape"
	self.card.BackgroundTransparency = if card then 0 else 1
	self.cardStroke.Enabled = card
	self.pauseButton.Position = UDim2.fromScale(if card then 0.07 else 0.04, 0.5)
	self.pills.Position = UDim2.fromScale(if card then 0.93 else 0.965, 0.5)
end

function HudBar.setScore(self: HudBar, score: number, best: number)
	local scoreText, bestText = Format.withCommas(score), Format.withCommas(best)
	if self.scoreLabel.Text ~= scoreText then
		self.scoreLabel.Text = scoreText
	end
	local bestLabel = Clay.pillLabel(self.bestPill)
	if bestLabel.Text ~= bestText then
		bestLabel.Text = bestText
	end
end

-- The combo pill shows from a combo of 2.
function HudBar.setCombo(self: HudBar, combo: number)
	local show = combo >= 2
	self.comboPill.Visible = show
	if show then
		Clay.pillLabel(self.comboPill).Text = `Combo x{combo}`
	end
end

return HudBar
