--!strict
-- The top bar (see HudBar), gains floating over the board after line clears, and the two panels over the
-- game: game over, with what the run earned (EXP bar, level up, new titles) once the server's RunRewards
-- arrive, and pause. Both panels share one overlay; only one is open at a time.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameSession = require(ReplicatedStorage.Shared.GameSession)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Clay = require("./Clay")
local Format = require("./Format")
local HudBar = require("./HudBar")
local Theme = require("./Theme")
local create = require("./Create")

local PANEL_MARGIN = 8 -- pixels kept free above and below a panel when it has to shrink
local COMPACT_HEIGHT = 480 -- below this (phones held sideways) the game over panel goes two columns

local RESTART_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.Space] = true,
}
local RESUME_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.ButtonB] = true,
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

export type Callbacks = {
	onRestart: () -> (),
	onMenu: () -> (),
	onPause: () -> (),
	onResume: () -> (),
	onRevive: (() -> ())?, -- the Revive button (M8); nothing shows until setRevive() is given an offer
}

export type Hud = typeof(setmetatable(
	{} :: {
		bar: HudBar.HudBar,
		popups: Frame, -- floating gain labels, over the board
		overlay: ScreenGui, -- panels (safe area)
		backdrop: ScreenGui, -- full-screen dimmer under the panels
		gameOverPanel: Frame,
		pausePanel: Frame,
		mascot: ImageLabel,
		titleLabel: TextLabel,
		finalScoreLabel: TextLabel,
		finalBestPill: Frame,
		reviveRoot: Frame,
		reviveButton: TextButton,
		reviveHint: TextLabel,
		layoutPanels: () -> (), -- one column or two, depending on the screen's height
		rewards: Frame, -- hidden until the run's rewards arrive
		expLabel: TextLabel,
		expFill: Frame,
		levelUpLabel: TextLabel,
		titlesLabel: TextLabel,
		rewardsToken: number, -- bumped to stop a running EXP bar animation
		restartButton: TextButton,
		menuButton: TextButton,
		resumeButton: TextButton,
		pauseRestartButton: TextButton,
		pauseMenuButton: TextButton,
		callbacks: Callbacks,
		keyConnection: RBXScriptConnection?, -- Enter / Space restart while game over is open
		pauseKeyConnection: RBXScriptConnection?, -- Enter / Space / Backspace / B resume while paused
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

-- A panel in the overlay that grows with its content; on short screens (phones held sideways) it shrinks to
-- fit. Returns the panel and the function that re-fits it.
local function newPanel(name: string, overlay: ScreenGui, children: { Instance }): (Frame, () -> ())
	local scale = create("UIScale", { Scale = 1 })
	local panel = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		Visible = false,
		Parent = overlay,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = Theme.Colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }),
		scale,
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
	})
	for _, child in children do
		child.Parent = panel
	end

	-- Size the panel would have unscaled, against the room the overlay has. Setting the same scale again
	-- changes nothing, so this settles after one adjustment.
	local function fit()
		local current = scale.Scale
		local height = panel.AbsoluteSize.Y / current
		local available = overlay.AbsoluteSize.Y - 2 * PANEL_MARGIN
		local fitted = if height > 0 and available > 0 then math.min(1, available / height) else 1
		if math.abs(fitted - current) > 0.001 then
			scale.Scale = fitted
		end
	end
	return panel, fit
end

function Hud.new(
	hudArea: GuiObject,
	popupArea: GuiObject,
	overlay: ScreenGui,
	backdrop: ScreenGui,
	callbacks: Callbacks
): Hud
	local colors, fonts, sizes = Theme.Colors, Theme.Fonts, Theme.TextSize

	local bar = HudBar.new(hudArea, callbacks.onPause)
	local popups = create("Frame", {
		Name = "Popups",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = popupArea,
	})

	-- The dimmer covers the whole screen; the panels live in the safe-area overlay above it.
	create("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Overlay,
		BackgroundTransparency = Theme.Transparency.Overlay,
		BorderSizePixel = 0,
		Active = true, -- swallow clicks so nothing under the panels reacts
		Parent = backdrop,
	})

	-- Game over
	local mascot = create("ImageLabel", {
		Name = "Mascot",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(96, 96),
		BackgroundTransparency = 1,
		Image = Theme.Images.MascotSad,
	})
	local titleLabel = label("Title", "No more moves!", fonts.Title, sizes.Title, colors.Text, 2)
	local scoreCaption = label("Caption", "SCORE", fonts.Label, 15, colors.TextMuted, 3)
	local finalScoreLabel = label("FinalScore", "0", fonts.Title, 52, colors.Text, 4)
	local finalBestPill = Clay.pill({ name = "Best", text = "Best 0", icon = Theme.Images.Crown, order = 5 })
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
		LayoutOrder = 6,
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
	local lip = Theme.Spacing.ButtonLip
	local buttonSize = UDim2.new(0.8, 0, 0, 52 + lip) -- the pause panel's buttons
	local wideButton = UDim2.new(1, 0, 0, 56 + lip)
	local reviveRoot = Clay.button({ name = "Revive", text = "Revive", style = "reward", order = 1, size = wideButton })
	reviveRoot.Visible = false -- until M8 offers a revive (see setRevive)
	local reviveHint = label("ReviveHint", "", fonts.Body, 13, colors.TextMuted, 2)
	reviveHint.Visible = false
	local restartRoot =
		Clay.button({ name = "PlayAgain", text = "Play again", style = "primary", order = 3, size = wideButton })
	local menuRoot = Clay.button({ name = "Menu", text = "Menu", style = "secondary", order = 4, size = wideButton })
	local function column(name: string, order: number): Frame
		return create("Frame", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
		}) :: Frame
	end
	local info = column("Info", 1)
	local choices = column("Choices", 2)
	for _, child in { mascot, titleLabel, scoreCaption, finalScoreLabel, finalBestPill, rewards } do
		child.Parent = info
	end
	for _, child in { reviveRoot, reviveHint, restartRoot, menuRoot } do
		child.Parent = choices
	end
	local gameOverPanel, fitGameOver = newPanel("GameOverPanel", overlay, { info, choices })

	-- What happened beside what to do next on short screens (phones held sideways); stacked otherwise.
	local panelLayout = gameOverPanel:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local panelLimit = gameOverPanel:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local function layoutGameOver()
		local size = overlay.AbsoluteSize
		local compact = size.Y > 0 and size.X > size.Y and size.Y < COMPACT_HEIGHT
		panelLayout.FillDirection = if compact then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		panelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		panelLayout.Padding = UDim.new(0, if compact then 20 else 12)
		panelLimit.MaxSize = Vector2.new(if compact then 720 else 420, math.huge)
		gameOverPanel.Size = UDim2.fromScale(if compact then 0.92 else 0.8, 0)
		local share = if compact then UDim2.new(0.5, -10, 0, 0) else UDim2.fromScale(1, 0)
		info.Size, choices.Size = share, share
		local mascotSize = if compact then 56 else 96
		mascot.Size = UDim2.fromOffset(mascotSize, mascotSize)
	end
	layoutGameOver()

	-- Pause
	local resumeRoot =
		Clay.button({ name = "Resume", text = "Resume", style = "primary", order = 2, size = buttonSize })
	local pauseRestartRoot =
		Clay.button({ name = "PlayAgain", text = "Play again", style = "secondary", order = 3, size = buttonSize })
	local pauseMenuRoot =
		Clay.button({ name = "Menu", text = "Menu", style = "secondary", order = 4, size = buttonSize })
	local pausePanel, fitPause = newPanel("PausePanel", overlay, {
		label("Title", "Paused", fonts.Title, sizes.Title, colors.Text, 1),
		resumeRoot,
		pauseRestartRoot,
		pauseMenuRoot,
	})

	local restartButton, menuButton = Clay.face(restartRoot), Clay.face(menuRoot)
	local resumeButton = Clay.face(resumeRoot)
	local pauseRestartButton, pauseMenuButton = Clay.face(pauseRestartRoot), Clay.face(pauseMenuRoot)

	return setmetatable({
		bar = bar,
		popups = popups,
		overlay = overlay,
		backdrop = backdrop,
		gameOverPanel = gameOverPanel,
		pausePanel = pausePanel,
		mascot = mascot,
		titleLabel = titleLabel,
		finalScoreLabel = finalScoreLabel,
		finalBestPill = finalBestPill,
		reviveRoot = reviveRoot,
		reviveButton = Clay.face(reviveRoot),
		reviveHint = reviveHint,
		layoutPanels = layoutGameOver,
		rewards = rewards,
		expLabel = expLabel,
		expFill = expFill,
		levelUpLabel = levelUpLabel,
		titlesLabel = titlesLabel,
		rewardsToken = 0,
		restartButton = restartButton,
		menuButton = menuButton,
		resumeButton = resumeButton,
		pauseRestartButton = pauseRestartButton,
		pauseMenuButton = pauseMenuButton,
		callbacks = callbacks,
		keyConnection = nil,
		pauseKeyConnection = nil,
		connections = {
			restartButton.Activated:Connect(callbacks.onRestart),
			menuButton.Activated:Connect(callbacks.onMenu),
			Clay.face(reviveRoot).Activated:Connect(function()
				local onRevive = callbacks.onRevive
				if onRevive then
					onRevive()
				end
			end),
			resumeButton.Activated:Connect(callbacks.onResume),
			pauseRestartButton.Activated:Connect(callbacks.onRestart),
			pauseMenuButton.Activated:Connect(callbacks.onMenu),
			gameOverPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGameOver),
			pausePanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPause),
			overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				layoutGameOver()
				fitGameOver()
				fitPause()
			end),
		},
	}, Hud)
end

function Hud.setScore(self: Hud, score: number, best: number)
	self.bar:setScore(score, best)
end

function Hud.setCombo(self: Hud, combo: number)
	self.bar:setCombo(combo)
end

function Hud.setLayout(self: Hud, mode: HudBar.Mode)
	self.bar:setLayout(mode)
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

-- Shows `panel` (and hides the other) over the dimmer.
local function openOverlay(self: Hud, panel: Frame)
	self.gameOverPanel.Visible = panel == self.gameOverPanel
	self.pausePanel.Visible = panel == self.pausePanel
	self.backdrop.Enabled = true
	self.overlay.Enabled = true
end

-- Opens the game over panel. "Play again" works by click/tap, Enter or Space, and the gamepad A button
-- (the button is selected when a gamepad is in use); "Menu" goes back to the main menu.
function Hud.showGameOver(self: Hud, score: number, best: number, isNewBest: boolean)
	self.finalScoreLabel.Text = Format.withCommas(score)
	Clay.pillLabel(self.finalBestPill).Text = `Best {Format.withCommas(best)}`
	self.titleLabel.Text = if isNewBest then "New best!" else "No more moves!"
	self.mascot.Image = if isNewBest then Theme.Images.MascotCheer else Theme.Images.MascotSad
	self.layoutPanels()
	openOverlay(self, self.gameOverPanel)
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.restartButton
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and RESTART_KEYS[input.KeyCode] then
				self.callbacks.onRestart()
			end
		end)
	end
end

-- Opens the pause panel. Resume works by click/tap, Enter, Space, Backspace and the gamepad B button.
function Hud.showPause(self: Hud)
	openOverlay(self, self.pausePanel)
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.resumeButton
	end
	if not self.pauseKeyConnection then
		self.pauseKeyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and RESUME_KEYS[input.KeyCode] then
				self.callbacks.onResume()
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
	return self.overlay.Enabled and self.gameOverPanel.Visible
end

function Hud.isPauseOpen(self: Hud): boolean
	return self.overlay.Enabled and self.pausePanel.Visible
end

-- Offers a revive on the game over panel, e.g. { text = "Revive · R$ 25", hint = "Clears the center 4×4 · 1 of 2 left" }, or
-- takes the offer away (nil).
function Hud.setRevive(self: Hud, offer: { text: string, hint: string }?)
	self.reviveRoot.Visible = offer ~= nil
	self.reviveHint.Visible = offer ~= nil
	if offer then
		self.reviveButton.Text = offer.text
		self.reviveHint.Text = offer.hint
	end
end

-- Closes whichever panel is open.
function Hud.hideGameOver(self: Hud)
	self.rewardsToken += 1
	self.rewards.Visible = false
	self.overlay.Enabled = false
	self.backdrop.Enabled = false
	self.gameOverPanel.Visible = false
	self.pausePanel.Visible = false
	local selected = GuiService.SelectedObject
	if
		selected == self.restartButton
		or selected == self.menuButton
		or selected == self.resumeButton
		or selected == self.pauseRestartButton
		or selected == self.pauseMenuButton
		or selected == self.reviveButton
	then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
	if self.pauseKeyConnection then
		self.pauseKeyConnection:Disconnect()
		self.pauseKeyConnection = nil
	end
end

function Hud.hidePause(self: Hud)
	self:hideGameOver()
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
