--!strict
-- The bar above the board: pause button, score, best score (in Co-op: who the player is with) and combo. In landscape it sits on a card in the
-- side column; in portrait it floats on the sky across the top. All sizes are shares of the HUD area, so it
-- keeps its proportions on any screen. The score counts up to each new value instead of jumping.
local TweenService = game:GetService("TweenService")

local Clay = require("./Clay")
local Format = require("./Format")
local Theme = require("./Theme")
local create = require("./Create")

export type Mode = "Portrait" | "Landscape"

local SCORE_MIN, SCORE_MAX = 22, 56
local PILL_GAP = 6
local PILL_MIN, PILL_MAX = 22, 32
local SCORE_POP_SCALE = 1.1 -- the score swells to this as it goes up
local COMBO_POP_SCALE = 0.7 -- the combo pill grows from this

local HudBar = {}
HudBar.__index = HudBar

export type HudBar = typeof(setmetatable(
	{} :: {
		card: Frame,
		cardStroke: UIStroke,
		pauseButton: TextButton,
		pills: Frame,
		scoreLabel: TextLabel,
		scorePop: UIScale,
		scoreCounter: NumberValue, -- the number on show, tweened toward the score
		scoreTween: Tween?,
		score: number,
		bestPill: Frame,
		comboPill: Frame,
		comboPop: UIScale,
		combo: number, -- the combo on show; 0 when the pill is hidden
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

	local caption = create("TextLabel", {
		Name = "Caption",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0.26),
		BackgroundTransparency = 1,
		FontFace = fonts.Label,
		TextScaled = true,
		TextColor3 = colors.TextMuted,
		Text = "SCORE",
	}, { create("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = 16 }) })

	local scoreCounter = create("NumberValue", {})
	scoreCounter:GetPropertyChangedSignal("Value"):Connect(function()
		scoreLabel.Text = Format.withCommas(math.round(scoreCounter.Value))
	end)
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
		caption,
		scoreLabel,
	})
	local scorePop = create("UIScale", { Parent = scoreBlock })

	local bestPill = Clay.pill({ name = "Best", text = "0", icon = Theme.Images.Crown, order = 1 })
	local comboPill = Clay.pill({ name = "Combo", text = "Combo x2", style = "reward", order = 2 })
	comboPill.Visible = false
	local comboPop = create("UIScale", { Parent = comboPill })
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
		scorePop = scorePop,
		scoreCounter = scoreCounter,
		scoreTween = nil,
		score = 0,
		caption = caption,
		partner = nil,
		bestPill = bestPill,
		comboPill = comboPill,
		comboPop = comboPop,
		combo = 0,
	}, HudBar)
	bar:setLayout("Portrait")
	return bar
end

function HudBar.setVisible(self: HudBar, visible: boolean)
	self.card.Visible = visible
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
	if score ~= self.score then
		local rising = score > self.score
		self.score = score
		if self.scoreTween then
			self.scoreTween:Cancel()
			self.scoreTween = nil
		end
		if rising then
			local info = TweenInfo.new(Theme.Motion.ScoreCount, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(self.scoreCounter, info, { Value = score })
			self.scoreTween = tween
			tween:Play()
			Clay.popIn(self.scorePop, SCORE_POP_SCALE, Theme.Motion.ScorePop)
		else
			self.scoreCounter.Value = score -- a new run starts from where it is, at once
		end
	end
	local bestText = if self.partner then `With {self.partner}` else Format.withCommas(best)
	local bestLabel = Clay.pillLabel(self.bestPill)
	if bestLabel.Text ~= bestText then
		bestLabel.Text = bestText
	end
end

-- In Co-op the score is the team's and the best-score pill says who the player is with; nil goes back to solo.
function HudBar.setPartner(self: HudBar, name: string?)
	self.partner = name
	self.caption.Text = if name then "TEAM SCORE" else "SCORE"
	local icon = self.bestPill:FindFirstChild("Icon") :: ImageLabel?
	if icon then
		icon.Visible = name == nil
	end
	if name then
		Clay.pillLabel(self.bestPill).Text = `With {name}`
	end
end

-- The combo pill shows from a combo of 2.
function HudBar.setCombo(self: HudBar, combo: number)
	local show = combo >= 2
	self.comboPill.Visible = show
	if show then
		Clay.pillLabel(self.comboPill).Text = `Combo x{combo}`
		if combo ~= self.combo then
			Clay.popIn(self.comboPop, COMBO_POP_SCALE, Theme.Motion.ScorePop)
		end
	end
	self.combo = if show then combo else 0
end

return HudBar
