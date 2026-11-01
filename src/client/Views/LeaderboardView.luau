--!strict
-- Leaderboard screen over the menu: All time / This week and Highscore / Level tabs, the top entries with
-- each player's title, and the player's own value. A gray-box placeholder until the mockups arrive; it only
-- draws what LeaderboardController hands it.
-- Back works by click/tap, Escape or Backspace, and the gamepad B button.
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require("./Theme")
local create = require("./Create")

local MAX_ROWS = 50
local ROW_HEIGHT = 44
local COMPACT_HEIGHT = 480 -- below this (phones held sideways) the heading goes and the tabs share one row
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.ButtonB] = true,
}

export type Period = "all" | "week"
export type Board = "Highscore" | "Level"
export type Entry = { rank: number, name: string, title: string?, value: number }
export type Snapshot = {
	boards: { [string]: { Entry } },
	updatedAt: number,
	you: { best: number, level: number, weekBest: number, weekExp: number },
}

type Row = { frame: Frame, rank: TextLabel, name: TextLabel, title: TextLabel, value: TextLabel }

local LeaderboardView = {}
LeaderboardView.__index = LeaderboardView

export type LeaderboardView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		heading: TextLabel,
		tabs: { [string]: TextButton }, -- "all", "week", "Highscore", "Level"
		rows: { Row },
		list: ScrollingFrame,
		status: TextLabel,
		you: TextLabel,
		closeButton: TextButton,
		period: Period,
		board: Board,
		snapshot: Snapshot?,
		onClose: () -> (),
		keyConnection: RBXScriptConnection?,
		connections: { RBXScriptConnection },
	},
	LeaderboardView
))

local function text(
	name: string,
	value: string,
	font: Font,
	size: number,
	color: Color3,
	props: { [string]: any }?
): TextLabel
	local label = create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = value,
	})
	for key, prop in props or {} do
		(label :: any)[key] = prop
	end
	return label
end

local function tabButton(name: string, label: string, order: number): TextButton
	return create("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(0.5, -4, 0, 40),
		BackgroundColor3 = Theme.Colors.ButtonSecondary,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Colors.ButtonSecondaryText,
		Text = label,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UISizeConstraint", { MinSize = Theme.MinTouchTarget }),
	})
end

local function newRow(index: number): Row
	local colors, fonts, sizes = Theme.Colors, Theme.Fonts, Theme.TextSize
	local rank = text("Rank", "", fonts.Title, sizes.Label, colors.TextMuted, {
		Size = UDim2.new(0, 36, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local name = text("Name", "", fonts.Title, sizes.Label, colors.Text, {
		Position = UDim2.fromOffset(40, 2),
		Size = UDim2.new(1, -140, 0.55, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local title = text("Title", "", fonts.Body, sizes.Label - 3, colors.Title, {
		Position = UDim2.new(0, 40, 0.55, 0),
		Size = UDim2.new(1, -140, 0.4, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local value = text("Value", "", fonts.Title, sizes.Label, colors.Text, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 96, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local frame = create("Frame", {
		Name = `Row{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = colors.Board,
		BackgroundTransparency = if index % 2 == 0 then 1 else 0,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		rank,
		name,
		title,
		value,
	})
	return { frame = frame, rank = rank, name = name, title = title, value = value }
end

function LeaderboardView.new(playerGui: PlayerGui, onClose: () -> ()): LeaderboardView
	local colors, fonts, sizes = Theme.Colors, Theme.Fonts, Theme.TextSize

	-- Opaque full-screen background over the menu; the content sits in the safe area above it.
	local backdrop = create("ScreenGui", {
		Name = "LeaderboardBackdrop",
		DisplayOrder = 12,
		ResetOnSpawn = false,
		Enabled = false,
	}, {
		create("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.Background,
			BorderSizePixel = 0,
			Active = true,
		}),
	})
	backdrop.IgnoreGuiInset = true
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	local tabs = {
		all = tabButton("AllTime", "All time", 1),
		week = tabButton("ThisWeek", "This week", 2),
		Highscore = tabButton("Highscore", "Highscore", 3),
		Level = tabButton("Level", "Level", 4),
	}
	-- Two rows of two tabs, or one row of four on short screens (see layout()).
	local tabArea = create("Frame", {
		Name = "Tabs",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
			Wraps = true,
		}),
		tabs.all,
		tabs.week,
		tabs.Highscore,
		tabs.Level,
	})
	local heading = text("Heading", "Leaderboard", fonts.Title, sizes.Title, colors.Text, {
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local rows = table.create(MAX_ROWS)
	for i = 1, MAX_ROWS do
		rows[i] = newRow(i)
	end
	local list = create("ScrollingFrame", {
		Name = "List",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = colors.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = true, -- the gamepad's stick scrolls it once selected
	}, {
		create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	for _, row in rows do
		row.frame.Parent = list
	end
	local status = text("Status", "", fonts.Body, sizes.Label, colors.TextMuted, {
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
	})
	local you = text("You", "", fonts.Title, sizes.Label, colors.Text, {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 24),
	})
	local closeButton = create("TextButton", {
		Name = "Back",
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = colors.ButtonSecondary,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		FontFace = fonts.Title,
		TextSize = sizes.Button,
		TextColor3 = colors.ButtonSecondaryText,
		Text = "Back",
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UISizeConstraint", { MinSize = Theme.MinTouchTarget }),
	})
	local gui = create("ScreenGui", {
		Name = "Leaderboard",
		DisplayOrder = 13,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, {
		create("Frame", {
			Name = "Column",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.92, 0, 1, -16),
			BackgroundTransparency = 1,
		}, {
			create("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			heading,
			tabArea,
			list,
			status,
			you,
			closeButton,
		}),
	})

	local self = setmetatable({
		backdrop = backdrop,
		gui = gui,
		heading = heading,
		tabs = tabs,
		rows = rows,
		list = list,
		status = status,
		you = you,
		closeButton = closeButton,
		period = "all" :: Period,
		board = "Highscore" :: Board,
		snapshot = nil,
		onClose = onClose,
		keyConnection = nil,
		connections = {},
	}, LeaderboardView)

	local function choose(period: Period?, board: Board?)
		self.period = period or self.period
		self.board = board or self.board
		self.list.CanvasPosition = Vector2.zero
		self:render()
	end
	table.insert(
		self.connections,
		tabs.all.Activated:Connect(function()
			choose("all", nil)
		end)
	)
	table.insert(
		self.connections,
		tabs.week.Activated:Connect(function()
			choose("week", nil)
		end)
	)
	table.insert(
		self.connections,
		tabs.Highscore.Activated:Connect(function()
			choose(nil, "Highscore")
		end)
	)
	table.insert(
		self.connections,
		tabs.Level.Activated:Connect(function()
			choose(nil, "Level")
		end)
	)
	table.insert(self.connections, closeButton.Activated:Connect(onClose))
	table.insert(
		self.connections,
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout()
		end)
	)

	backdrop.Parent = playerGui
	gui.Parent = playerGui
	self:layout()
	self:render()
	return self
end

-- Fits the screen: on short screens the heading goes and the four tabs share one row, so more of the
-- list shows.
function LeaderboardView.layout(self: LeaderboardView)
	local compact = self.gui.AbsoluteSize.Y > 0 and self.gui.AbsoluteSize.Y < COMPACT_HEIGHT
	self.heading.Visible = not compact
	local size = if compact then UDim2.new(0.25, -6, 0, 40) else UDim2.new(0.5, -4, 0, 40)
	for _, button in self.tabs do
		button.Size = size
	end
end

local function formatValue(board: Board, period: Period, value: number): string
	if board == "Level" then
		return if period == "week" then `{value} EXP` else `Lv {value}`
	end
	return tostring(value)
end

-- Draws the chosen board from the last snapshot (or "Loading…" before one arrives).
function LeaderboardView.render(self: LeaderboardView)
	for key, button in self.tabs do
		local selected = key == self.period or key == self.board
		button.BackgroundColor3 = if selected then Theme.Colors.Button else Theme.Colors.ButtonSecondary
		button.TextColor3 = if selected then Theme.Colors.ButtonText else Theme.Colors.ButtonSecondaryText
	end

	local snapshot = self.snapshot
	local entries = if snapshot then snapshot.boards[`{self.board}_{self.period}`] else nil
	for i, row in self.rows do
		local entry = entries and entries[i]
		row.frame.Visible = entry ~= nil
		if entry then
			row.rank.Text = `#{entry.rank}`
			row.name.Text = entry.name
			row.title.Text = entry.title or ""
			row.value.Text = formatValue(self.board, self.period, entry.value)
		end
	end

	if not snapshot then
		self.status.Text = "Loading…"
		self.status.Visible = true
		self.you.Text = ""
		return
	end
	-- The status line only takes room when the list has nothing to show.
	local empty = not entries or #entries == 0
	self.status.Text = if empty then "No scores yet. Play a run to get on the board!" else ""
	self.status.Visible = empty
	local you = snapshot.you
	if self.board == "Highscore" then
		self.you.Text = if self.period == "week" then `Your best this week: {you.weekBest}` else `Your best: {you.best}`
	else
		self.you.Text = if self.period == "week" then `Your EXP this week: {you.weekExp}` else `Your level: {you.level}`
	end
end

function LeaderboardView.setSnapshot(self: LeaderboardView, snapshot: Snapshot)
	self.snapshot = snapshot
	self:render()
end

function LeaderboardView.open(self: LeaderboardView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	self:render()
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.tabs.all
	end
	if not self.keyConnection then
		self.keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and CLOSE_KEYS[input.KeyCode] then
				self.onClose()
			end
		end)
	end
end

function LeaderboardView.close(self: LeaderboardView)
	self.backdrop.Enabled = false
	self.gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
end

function LeaderboardView.isOpen(self: LeaderboardView): boolean
	return self.gui.Enabled
end

-- For the Studio debug bridge: the visible rows as "rank name [title] value" lines.
function LeaderboardView.describe(self: LeaderboardView): string
	local lines = { `{self.board}_{self.period} status="{self.status.Text}" you="{self.you.Text}"` }
	for _, row in self.rows do
		if row.frame.Visible then
			table.insert(lines, `{row.rank.Text} {row.name.Text} [{row.title.Text}] {row.value.Text}`)
		end
	end
	return table.concat(lines, "\n")
end

return LeaderboardView
