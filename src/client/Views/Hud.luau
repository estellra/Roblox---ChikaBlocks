--!strict
-- Score display, gains floating over the board after line clears, and the game over panel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameSession = require(ReplicatedStorage.Shared.GameSession)
local Theme = require("./Theme")
local create = require("./Create")

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable(
	{} :: {
		scoreLabel: TextLabel,
		bestLabel: TextLabel,
		popups: Frame, -- floating gain labels, over the board
		overlay: ScreenGui,
		finalScoreLabel: TextLabel,
		finalBestLabel: TextLabel,
		restartButton: TextButton,
		connections: { RBXScriptConnection },
	},
	Hud
))

local function label(name: string, text: string, font: Font, textSize: number, color: Color3, order: number): TextLabel
	return create("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = textSize,
		TextColor3 = color,
		Text = text,
	})
end

function Hud.new(hudArea: GuiObject, popupArea: GuiObject, overlay: ScreenGui, onRestart: () -> ()): Hud
	local colors, fonts, sizes = Theme.Colors, Theme.Fonts, Theme.TextSize

	-- The score scales with the HUD area (it is much taller on a phone in portrait than in landscape),
	-- bounded so it stays readable and never huge.
	local scoreLabel = create("TextLabel", {
		Name = "Score",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0.62),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextScaled = true,
		TextColor3 = colors.Text,
		Text = "0",
	}, {
		create("UITextSizeConstraint", { MinTextSize = sizes.ScoreMin, MaxTextSize = sizes.ScoreMax }),
	})
	local bestLabel = create("TextLabel", {
		Name = "Best",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0.28),
		BackgroundTransparency = 1,
		FontFace = fonts.Body,
		TextScaled = true,
		TextColor3 = colors.TextMuted,
		Text = "Best 0",
	}, {
		create("UITextSizeConstraint", { MinTextSize = sizes.HudLabelMin, MaxTextSize = sizes.HudLabelMax }),
	})
	create("Frame", {
		Name = "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = hudArea,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		scoreLabel,
		bestLabel,
	})
	local popups = create("Frame", {
		Name = "Popups",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = popupArea,
	})

	local finalScoreLabel = label("FinalScore", "Score 0", fonts.Title, sizes.Label + 6, colors.Text, 2)
	local finalBestLabel = label("FinalBest", "Best 0", fonts.Body, sizes.Label, colors.TextMuted, 3)
	local restartButton = create("TextButton", {
		Name = "PlayAgain",
		LayoutOrder = 4,
		Size = UDim2.new(0.8, 0, 0, 52),
		BackgroundColor3 = colors.Button,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		FontFace = fonts.Title,
		TextSize = sizes.Button,
		TextColor3 = colors.ButtonText,
		Text = "Play again",
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UISizeConstraint", { MinSize = Theme.MinTouchTarget }),
	})
	create("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Overlay,
		BackgroundTransparency = Theme.Transparency.Overlay,
		BorderSizePixel = 0,
		Parent = overlay,
	}, {
		create("Frame", {
			Name = "Panel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = colors.Panel,
			BorderSizePixel = 0,
		}, {
			create("UICorner", { CornerRadius = Theme.Radius.Panel }),
			create("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 24),
				PaddingBottom = UDim.new(0, 24),
				PaddingLeft = UDim.new(0, 20),
				PaddingRight = UDim.new(0, 20),
			}),
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 12),
			}),
			label("Title", "Game Over", fonts.Title, sizes.Title, colors.Text, 1),
			finalScoreLabel,
			finalBestLabel,
			restartButton,
		}),
	})

	return setmetatable({
		scoreLabel = scoreLabel,
		bestLabel = bestLabel,
		popups = popups,
		overlay = overlay,
		finalScoreLabel = finalScoreLabel,
		finalBestLabel = finalBestLabel,
		restartButton = restartButton,
		connections = { restartButton.Activated:Connect(onRestart) },
	}, Hud)
end

function Hud.setScore(self: Hud, score: number, best: number)
	local scoreText, bestText = tostring(score), `Best {best}`
	if self.scoreLabel.Text ~= scoreText then
		self.scoreLabel.Text = scoreText
	end
	if self.bestLabel.Text ~= bestText then
		self.bestLabel.Text = bestText
	end
end

-- Floats "+points" up over the board after a line clear, with the combo or a board clear noted.
function Hud.showGain(self: Hud, result: GameSession.PlaceResult)
	local linesCleared = #result.clearedRows + #result.clearedCols
	if linesCleared == 0 then
		return
	end
	local text = `+{result.points}`
	if result.boardCleared then
		text ..= "  Board clear!"
	elseif result.combo >= 2 then
		text ..= `  Combo x{result.combo}`
	end
	local gain = create("TextLabel", {
		Name = "Gain",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.12),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Title,
		TextScaled = true,
		TextColor3 = if result.combo >= 2 or result.boardCleared then Theme.Colors.Combo else Theme.Colors.Gain,
		Text = text,
		Parent = self.popups,
	}, {
		create("UITextSizeConstraint", {
			MinTextSize = Theme.TextSize.GainMin,
			MaxTextSize = Theme.TextSize.GainMax,
		}),
	})
	local float = TweenService:Create(
		gain,
		TweenInfo.new(Theme.Motion.Gain, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.36), TextTransparency = 1 }
	)
	float.Completed:Once(function()
		gain:Destroy()
	end)
	float:Play()
end

function Hud.showGameOver(self: Hud, score: number, best: number)
	self.finalScoreLabel.Text = `Score {score}`
	self.finalBestLabel.Text = `Best {best}`
	self.overlay.Enabled = true
end

function Hud.hideGameOver(self: Hud)
	self.overlay.Enabled = false
end

function Hud.destroy(self: Hud)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return Hud
