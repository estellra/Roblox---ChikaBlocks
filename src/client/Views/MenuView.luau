--!strict
-- Main menu, as in the mockups: the two-line logo and the mascot, a Best pill and a level pill, Play and
-- Leaderboard (with Co-op beside it when that is on), a "?" button for How to play, a small Support us button in
-- the other top corner, and blocks floating on the sky behind. Landscape puts the logo
-- and mascot beside the buttons; portrait stacks them.
-- Play works by click/tap, Enter or Space, and the gamepad A button (Play is selected for gamepads).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Pieces = require(ReplicatedStorage.Shared.Pieces)
local Clay = require("./Clay")
local Format = require("./Format")
local PieceView = require("./PieceView")
local Theme = require("./Theme")
local create = require("./Create")

local PLAY_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.Space] = true,
}

local LANDSCAPE_MIN_RATIO = 1.1 -- width / height of the safe area
local DECOR_CELL = 26 -- pixels per cell of the floating blocks
local OPEN_START_SCALE = 0.96 -- the menu grows from this as it opens
-- Floating blocks: piece, position (share of the screen), tilt in degrees.
local DECOR = {
	{ id = "L3_2", x = 0.12, y = 0.24, tilt = -8 },
	{ id = "I3_H", x = 0.42, y = 0.19, tilt = 6 },
	{ id = "T4_2", x = 0.87, y = 0.34, tilt = -10 },
	{ id = "O2", x = 0.09, y = 0.93, tilt = 8 },
}

local MenuView = {}
MenuView.__index = MenuView

export type MenuView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		content: Frame,
		main: Frame,
		pop: UIScale,
		heroLayout: UIListLayout,
		logoLayout: UIListLayout,
		logoTop: TextLabel,
		logoBottom: TextLabel,
		mascot: ImageLabel,
		actions: Frame,
		bestPill: Frame,
		levelPill: Frame,
		playButton: TextButton,
		leaderboardButton: TextButton,
		coopButton: TextButton,
		rankedButton: TextButton,
		leaderboardRoot: Frame,
		coopRoot: Frame,
		rankedRoot: Frame,
		modeRow: Frame,
		helpButton: TextButton,
		supportButton: TextButton,
		floaters: { Tween },
		ready: boolean, -- false until the saved profile has arrived
		onPlay: () -> (),
		keyConnection: RBXScriptConnection?,
		connections: { RBXScriptConnection },
	},
	MenuView
))

local function text(name: string, order: number, value: string, font: Font, size: number, color: Color3): TextLabel
	return create("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		Text = value,
	})
end

-- Blocks drifting up and down behind the menu; returns the tweens so they can be paused while it is closed.
local function addFloaters(parent: GuiObject): { Tween }
	local tweens = {}
	for index, decor in DECOR do
		local piece = Pieces.BY_ID[decor.id]
		local frame = PieceView.build(piece)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(piece.width * DECOR_CELL, piece.height * DECOR_CELL)
		frame.Position = UDim2.fromScale(decor.x, decor.y)
		frame.Rotation = decor.tilt
		frame.Parent = parent
		local info = TweenInfo.new(2.2 + index * 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local drift = TweenService:Create(frame, info, { Position = UDim2.new(decor.x, 0, decor.y, -10) })
		table.insert(tweens, drift)
	end
	return tweens
end

function MenuView.new(
	playerGui: PlayerGui,
	onPlay: () -> (),
	onLeaderboard: () -> (),
	onHowToPlay: () -> (),
	onSupport: () -> (),
	onCoop: () -> (),
	onRanked: (() -> ())?
): MenuView
	local colors, fonts = Theme.Colors, Theme.Fonts
	local lip = Theme.Spacing.ButtonLip

	-- Opaque full-screen sky under the notch and top bar; the content sits in the safe area above it.
	local sky = Clay.sky("Fill", true) -- swallows clicks meant for the game underneath
	local backdrop = create("ScreenGui", {
		Name = "MenuBackdrop",
		DisplayOrder = 10,
		ResetOnSpawn = false,
		Enabled = false,
	}, { sky })
	backdrop.IgnoreGuiInset = true
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it
	local floaters = addFloaters(sky)

	-- Logo: two lines of chunky text, the second pink with an outline, slightly overlapping the first.
	local logoTop = text("Chika", 1, Theme.Text.LogoLines[1], fonts.Title, 72, colors.Text)
	local logoBottom = text("Blocks", 2, Theme.Text.LogoLines[2], fonts.Title, 72, colors.Button)
	create("UIStroke", {
		Color = colors.Outline,
		Thickness = 5,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = logoBottom,
	})
	local logoLayout = create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
	local logo = create("Frame", {
		Name = "Logo",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
	}, { logoLayout, logoTop, logoBottom })
	local mascot = create("ImageLabel", {
		Name = "Mascot",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(160, 160),
		BackgroundTransparency = 1,
		Image = Theme.Images.MascotHappy,
	})
	local heroLayout = create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	})
	local hero = create("Frame", {
		Name = "Hero",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
	}, { heroLayout, logo, mascot })

	-- Buttons side: the Best and level pills, Play, Leaderboard and the tagline.
	local bestPill = Clay.pill({ name = "Best", text = "Best —", icon = Theme.Images.Crown, order = 1 })
	local levelPill = Clay.pill({ name = "Level", text = "Lv 1", order = 2 })
	Clay.pillLabel(levelPill).TextColor3 = colors.Title
	local pills = create("Frame", {
		Name = "Pills",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Wraps = true,
			Padding = UDim.new(0, 8),
		}),
		bestPill,
		levelPill,
	})
	local playRoot = Clay.button({
		name = "Play",
		text = "Loading…",
		style = "primary",
		order = 2,
		size = UDim2.new(1, 0, 0, 72 + lip),
		textSize = 30,
	})
	-- Ranked (gold) and Co-op side by side once they are on (see setModes), and Leaderboard on its own row under them
	-- (mockup 06-menu-ranked-button). The text shrinks to fit a half-width button.
	local function secondaryButton(name: string, label: string, order: number, style: Clay.ButtonStyle?): Frame
		local root = Clay.button({
			name = name,
			text = label,
			style = style or "secondary",
			order = order,
			size = UDim2.fromScale(1, 1),
		})
		local face = Clay.face(root)
		face.TextScaled = true
		create("UITextSizeConstraint", { MaxTextSize = Theme.TextSize.Button, MinTextSize = 12, Parent = face })
		return root
	end
	local leaderboardRoot = secondaryButton("Leaderboard", "Leaderboard", 1)
	local rankedRoot = secondaryButton("Ranked", "Ranked", 1, "reward")
	local coopRoot = secondaryButton("Coop", "Co-op", 2)
	rankedRoot.Visible = false
	coopRoot.Visible = false
	local function row(name: string, order: number, children: { Instance }): Frame
		local frame = create("Frame", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 60 + lip),
			BackgroundTransparency = 1,
		}, {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 10),
			}),
		})
		for _, child in children do
			child.Parent = frame
		end
		return frame
	end
	local modeRow = row("ModeRow", 3, { rankedRoot, coopRoot })
	modeRow.Visible = false
	local secondaryRow = row("SecondaryRow", 4, { leaderboardRoot })
	local tagline = create("TextLabel", {
		Name = "Tagline",
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = fonts.Body,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = colors.TextMuted,
		Text = "Drag blocks. Clear lines. Stay cozy.",
	})
	local actions = create("Frame", {
		Name = "Actions",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
		pills,
		playRoot,
		modeRow,
		secondaryRow,
		tagline,
	})

	local pop = create("UIScale", { Name = "Pop" })
	local main = create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 24),
		}),
		pop,
		hero,
		actions,
	})

	local helpButton = Clay.iconButton({ name = "HowToPlay", text = "?" })
	helpButton.AnchorPoint = Vector2.new(1, 0)
	helpButton.Position = UDim2.new(1, -12, 0, 12)
	-- Out of the main column, so a short phone screen has room for it: a small button in the top-left corner.
	local supportRoot = Clay.button({
		name = "Support",
		text = "Support us",
		style = "secondary",
		size = UDim2.fromOffset(124, 44 + lip),
		textSize = Theme.TextSize.Label,
	})
	supportRoot.Position = UDim2.fromOffset(12, 12)
	local content = create("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, { main, helpButton, supportRoot })
	local gui = create("ScreenGui", {
		Name = "Menu",
		DisplayOrder = 11,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, { content })

	local playButton, leaderboardButton = Clay.face(playRoot), Clay.face(leaderboardRoot)
	local coopButton = Clay.face(coopRoot)
	local rankedButton = Clay.face(rankedRoot)
	local supportButton = Clay.face(supportRoot)
	local self = setmetatable({
		backdrop = backdrop,
		gui = gui,
		content = content,
		main = main,
		pop = pop,
		heroLayout = heroLayout,
		logoLayout = logoLayout,
		logoTop = logoTop,
		logoBottom = logoBottom,
		mascot = mascot,
		actions = actions,
		bestPill = bestPill,
		levelPill = levelPill,
		playButton = playButton,
		leaderboardButton = leaderboardButton,
		coopButton = coopButton,
		rankedButton = rankedButton,
		leaderboardRoot = leaderboardRoot,
		coopRoot = coopRoot,
		rankedRoot = rankedRoot,
		modeRow = modeRow,
		helpButton = helpButton,
		supportButton = supportButton,
		floaters = floaters,
		ready = false,
		onPlay = onPlay,
		keyConnection = nil,
		connections = {},
	}, MenuView)
	table.insert(
		self.connections,
		playButton.Activated:Connect(function()
			if self.ready then
				onPlay()
			end
		end)
	)
	table.insert(
		self.connections,
		leaderboardButton.Activated:Connect(function()
			if self.ready then
				onLeaderboard()
			end
		end)
	)
	table.insert(
		self.connections,
		coopButton.Activated:Connect(function()
			if self.ready then
				onCoop()
			end
		end)
	)
	table.insert(
		self.connections,
		rankedButton.Activated:Connect(function()
			if self.ready and onRanked then
				onRanked()
			end
		end)
	)
	table.insert(
		self.connections,
		helpButton.Activated:Connect(function()
			if self.ready then
				onHowToPlay()
			end
		end)
	)
	table.insert(self.connections, supportButton.Activated:Connect(onSupport))
	table.insert(
		self.connections,
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout()
		end)
	)

	backdrop.Parent = playerGui
	gui.Parent = playerGui
	self:layout()
	return self
end

-- Sizes the logo, mascot and button column for the screen: beside each other in landscape, stacked in portrait.
function MenuView.layout(self: MenuView)
	local size = self.content.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local landscape = size.X / size.Y >= LANDSCAPE_MIN_RATIO
	local logoSize, mascotSize, actionsWidth, gap
	if landscape then
		logoSize = math.clamp(size.Y * 0.17, 34, 96)
		mascotSize = math.clamp(size.Y * 0.28, 72, 200)
		actionsWidth = math.clamp(size.X * 0.34, 240, 380)
		gap = size.X * 0.06
	else
		logoSize = math.clamp(size.X * 0.16, 34, 80)
		mascotSize = math.clamp(math.min(size.X * 0.4, size.Y * 0.2), 72, 170)
		actionsWidth = math.clamp(size.X * 0.9, 240, 380)
		gap = size.Y * 0.04
	end
	self.logoTop.TextSize = logoSize
	self.logoBottom.TextSize = logoSize
	self.logoLayout.Padding = UDim.new(0, -math.floor(logoSize * 0.14)) -- the second line tucks under the first
	self.mascot.Size = UDim2.fromOffset(mascotSize, mascotSize)
	self.actions.Size = UDim2.fromOffset(actionsWidth, 0)
	local layout = self.main:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	layout.FillDirection = if landscape then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, math.floor(gap))
end

-- Called once the saved profile is known; until then Play shows "Loading…" and does nothing.
function MenuView.setReady(self: MenuView, best: number, level: number, title: string?)
	self.ready = true
	self.playButton.Text = "Play"
	Clay.pillLabel(self.bestPill).Text = `Best {Format.withCommas(best)}`
	Clay.pillLabel(self.levelPill).Text = if title then `Lv {level} · {title}` else `Lv {level}`
end

-- Shows the Ranked and Co-op buttons that are on, side by side on their row (one alone fills it; with neither the row
-- goes). Leaderboard keeps its own row.
function MenuView.setModes(self: MenuView, ranked: boolean, coop: boolean)
	self.rankedRoot.Visible = ranked
	self.coopRoot.Visible = coop
	self.modeRow.Visible = ranked or coop
	local both = ranked and coop
	local size = if both then UDim2.new(0.5, -5, 1, 0) else UDim2.fromScale(1, 1)
	self.rankedRoot.Size = size
	self.coopRoot.Size = size
end

-- The Co-op button on its own (Ranked off); see setModes.
function MenuView.setCoopVisible(self: MenuView, visible: boolean)
	self:setModes(self.rankedRoot.Visible, visible)
end

function MenuView.show(self: MenuView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	Clay.popIn(self.pop, OPEN_START_SCALE, Theme.Motion.Panel)
	for _, tween in self.floaters do
		tween:Play()
	end
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.playButton
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and PLAY_KEYS[input.KeyCode] and self.ready then
				self.onPlay()
			end
		end)
	end
end

function MenuView.hide(self: MenuView)
	self.backdrop.Enabled = false
	self.gui.Enabled = false
	for _, tween in self.floaters do
		tween:Pause()
	end
	local selected = GuiService.SelectedObject
	if
		selected == self.playButton
		or selected == self.leaderboardButton
		or selected == self.coopButton
		or selected == self.rankedButton
		or selected == self.helpButton
		or selected == self.supportButton
	then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

function MenuView.isOpen(self: MenuView): boolean
	return self.gui.Enabled
end

function MenuView.destroy(self: MenuView)
	self:hide()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, tween in self.floaters do
		tween:Destroy()
	end
	self.backdrop:Destroy()
	self.gui:Destroy()
end

return MenuView
