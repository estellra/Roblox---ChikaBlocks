--!strict
-- Score display, gains floating over the board after line clears, and the game over panel with what the
-- run earned (EXP bar, level up, new titles), shown once the server's RunRewards arrive.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameSession = require(ReplicatedStorage.Shared.GameSession)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Theme = require("./Theme")
local create = require("./Create")

local PANEL_MARGIN = 8 -- pixels kept free above and below the game over panel when it has to shrink

local RESTART_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.Space] = true,
}

local Hud = {}
Hud.__index = Hud

-- What a finished run earned (sent by the server with RunRewards; see GameService.RunRewards).
export type RunRewards = {
	expGained: number,
	levelBefore: number,
	expBefore: number,
	level: number,
	exp: number,
	titles: { string },
}

export type Hud = typeof(setmetatable(
	{} :: {
		scoreLabel: TextLabel,
		bestLabel: TextLabel,
		popups: Frame, -- floating gain labels, over the board
		overlay: ScreenGui, -- game over panel (safe area)
		backdrop: ScreenGui, -- full-screen dimmer under the panel
		finalScoreLabel: TextLabel,
		newBestLabel: TextLabel,
		finalBestLabel: TextLabel,
		rewards: Frame, -- hidden until the run's rewards arrive
		expLabel: TextLabel,
		expFill: Frame,
		levelUpLabel: TextLabel,
		titlesLabel: TextLabel,
		rewardsToken: number, -- bumped to stop a running EXP bar animation
		restartButton: TextButton,
		menuButton: TextButton,
		onRestart: () -> (),
		keyConnection: RBXScriptConnection?, -- Enter / Space restart while the panel is open
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

function Hud.new(
	hudArea: GuiObject,
	popupArea: GuiObject,
	overlay: ScreenGui,
	backdrop: ScreenGui,
	onRestart: () -> (),
	onMenu: () -> ()
): Hud
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
	local newBestLabel = label("NewBest", "New best!", fonts.Title, sizes.Label + 2, colors.Combo, 3)
	newBestLabel.Visible = false
	local finalBestLabel = label("FinalBest", "Best 0", fonts.Body, sizes.Label, colors.TextMuted, 4)
	local expLabel = label("Exp", "", fonts.Body, sizes.Label, colors.TextMuted, 1)
	local expFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = colors.ExpFill,
		BorderSizePixel = 0,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local levelUpLabel = label("LevelUp", "", fonts.Title, sizes.Label + 2, colors.Combo, 3)
	local titlesLabel = label("Titles", "", fonts.Title, sizes.Label, colors.Title, 4)
	titlesLabel.TextWrapped = true
	local rewards = create("Frame", {
		Name = "Rewards",
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
		expLabel,
		create("Frame", {
			Name = "ExpBar",
			LayoutOrder = 2,
			Size = UDim2.new(0.8, 0, 0, 10),
			BackgroundColor3 = colors.ExpTrack,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), expFill }),
		levelUpLabel,
		titlesLabel,
	})
	local restartButton = create("TextButton", {
		Name = "PlayAgain",
		LayoutOrder = 6,
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
	local menuButton = create("TextButton", {
		Name = "Menu",
		LayoutOrder = 7,
		Size = UDim2.new(0.8, 0, 0, 52),
		BackgroundColor3 = colors.ButtonSecondary,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		FontFace = fonts.Title,
		TextSize = sizes.Button,
		TextColor3 = colors.ButtonSecondaryText,
		Text = "Menu",
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UISizeConstraint", { MinSize = Theme.MinTouchTarget }),
	})
	-- The dimmer covers the whole screen; the panel lives in the safe-area overlay above it.
	create("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Overlay,
		BackgroundTransparency = Theme.Transparency.Overlay,
		BorderSizePixel = 0,
		Active = true, -- swallow clicks so nothing under the panel reacts
		Parent = backdrop,
	})
	-- The panel grows with what the run earned; on short screens (phones held sideways) it shrinks to fit.
	local panelScale = create("UIScale", { Scale = 1 })
	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
		Parent = overlay,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }),
		panelScale,
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
		newBestLabel,
		finalBestLabel,
		rewards,
		restartButton,
		menuButton,
	})

	-- Size the panel would have unscaled, against the room the overlay has. Setting the same scale again
	-- changes nothing, so this settles after one adjustment.
	local function fitPanel()
		local scale = panelScale.Scale
		local height = panel.AbsoluteSize.Y / scale
		local available = overlay.AbsoluteSize.Y - 2 * PANEL_MARGIN
		local fitted = if height > 0 and available > 0 then math.min(1, available / height) else 1
		if math.abs(fitted - scale) > 0.001 then
			panelScale.Scale = fitted
		end
	end

	return setmetatable({
		scoreLabel = scoreLabel,
		bestLabel = bestLabel,
		popups = popups,
		overlay = overlay,
		backdrop = backdrop,
		finalScoreLabel = finalScoreLabel,
		newBestLabel = newBestLabel,
		finalBestLabel = finalBestLabel,
		rewards = rewards,
		expLabel = expLabel,
		expFill = expFill,
		levelUpLabel = levelUpLabel,
		titlesLabel = titlesLabel,
		rewardsToken = 0,
		restartButton = restartButton,
		menuButton = menuButton,
		onRestart = onRestart,
		keyConnection = nil,
		connections = {
			restartButton.Activated:Connect(onRestart),
			menuButton.Activated:Connect(onMenu),
			panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel),
			overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel),
		},
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

-- Opens the game over panel. "Play again" works by click/tap, Enter or Space, and the gamepad A button
-- (the button is selected when a gamepad is in use); "Menu" goes back to the main menu.
function Hud.showGameOver(self: Hud, score: number, best: number, isNewBest: boolean)
	self.finalScoreLabel.Text = `Score {score}`
	self.finalBestLabel.Text = `Best {best}`
	self.newBestLabel.Visible = isNewBest
	self.backdrop.Enabled = true
	self.overlay.Enabled = true
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.restartButton
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and RESTART_KEYS[input.KeyCode] then
				self.onRestart()
			end
		end)
	end
end

-- Fills in what the run earned on the open panel: the EXP bar fills from where the run started (up to full
-- and over again on a level up), then level up and new titles.
function Hud.showRewards(self: Hud, rewards: RunRewards)
	self.rewardsToken += 1
	local token = self.rewardsToken
	local leveledUp = rewards.level > rewards.levelBefore
	self.expLabel.Text = `Level {rewards.level}  ·  +{rewards.expGained} EXP`
	self.levelUpLabel.Text = `Level up! You're level {rewards.level}`
	self.levelUpLabel.Visible = leveledUp
	self.titlesLabel.Text = (if #rewards.titles == 1 then "New title: " else "New titles: ")
		.. table.concat(rewards.titles, ", ")
	self.titlesLabel.Visible = #rewards.titles > 0
	self.rewards.Visible = true

	local before = rewards.expBefore / Progression.expToNext(rewards.levelBefore)
	local after = rewards.exp / Progression.expToNext(rewards.level)
	local info = TweenInfo.new(Theme.Motion.ExpFill, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self.expFill.Size = UDim2.fromScale(before, 1)
	if not leveledUp then
		TweenService:Create(self.expFill, info, { Size = UDim2.fromScale(after, 1) }):Play()
		return
	end
	local toFull = TweenService:Create(self.expFill, info, { Size = UDim2.fromScale(1, 1) })
	toFull.Completed:Once(function()
		if token == self.rewardsToken then
			self.expFill.Size = UDim2.fromScale(0, 1)
			TweenService:Create(self.expFill, info, { Size = UDim2.fromScale(after, 1) }):Play()
		end
	end)
	toFull:Play()
end

function Hud.isGameOverOpen(self: Hud): boolean
	return self.overlay.Enabled
end

function Hud.hideGameOver(self: Hud)
	self.rewardsToken += 1
	self.rewards.Visible = false
	self.overlay.Enabled = false
	self.backdrop.Enabled = false
	local selected = GuiService.SelectedObject
	if selected == self.restartButton or selected == self.menuButton then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

-- Whether Enter / Space currently restart; for the Studio debug bridge.
function Hud.isListeningForRestartKeys(self: Hud): boolean
	return self.keyConnection ~= nil
end

function Hud.destroy(self: Hud)
	self:hideGameOver()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return Hud
