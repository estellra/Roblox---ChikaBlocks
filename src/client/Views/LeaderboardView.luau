--!strict
-- Leaderboard screen over the menu, in the same style as the other screens: a cream card on the sky with the
-- trophy, the All time / This week and Highscore / Level / Co-op tabs, the top entries (medals for the first
-- three, each player's title, the player's own row picked out in gold) and the player's own value. The Co-op board
-- ranks pairs ("A & B") and only has an all time version. It only draws
-- what LeaderboardController hands it.
-- Closing works by the X button, Escape or Backspace, and the gamepad B button.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Clay = require("./Clay")
local Format = require("./Format")
local Theme = require("./Theme")
local create = require("./Create")

local MAX_ROWS = 50
local ROW_HEIGHT = 48
local TAB_HEIGHT = 44 + Theme.Spacing.ButtonLip -- the face meets the minimum touch size; the lip comes on top
local CLOSE_SIZE = 44
local OPEN_START_SCALE = 0.94 -- the card grows from this as the screen opens
local COMPACT_HEIGHT = 480 -- below this (phones held sideways) the heading goes and the tabs share one row
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.ButtonB] = true,
}

export type Period = "all" | "week"
export type Board = "Highscore" | "Level" | "Coop"
export type Entry = { rank: number, userId: number, userIds: { number }?, name: string, title: string?, value: number }
export type Snapshot = {
	boards: { [string]: { Entry } },
	updatedAt: number,
	you: { best: number, level: number, weekBest: number, weekExp: number, coopBest: number },
}

type Row = { frame: Frame, medal: Frame, rank: TextLabel, name: TextLabel, title: TextLabel, value: TextLabel }

local LeaderboardView = {}
LeaderboardView.__index = LeaderboardView

export type LeaderboardView = typeof(setmetatable(
	{} :: {
		backdrop: ScreenGui,
		gui: ScreenGui,
		header: Frame,
		tabArea: Frame,
		tabs: { [string]: Frame }, -- "all", "week", "Highscore", "Level" (Clay buttons)
		rows: { Row },
		list: ScrollingFrame,
		status: TextLabel,
		youPill: Frame,
		closeButton: TextButton,
		pop: UIScale,
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

local function tabButton(name: string, label: string, order: number): Frame
	return Clay.button({
		name = name,
		text = label,
		style = "secondary",
		order = order,
		size = UDim2.new(0.5, -4, 0, TAB_HEIGHT),
		textSize = Theme.TextSize.Label,
	})
end

-- The color of the medal behind a rank: gold, silver, bronze, or nothing.
local function medalColor(rank: number): Color3?
	if rank == 1 then
		return Theme.Colors.Reward
	elseif rank == 2 then
		return Theme.Colors.MedalSilver
	elseif rank == 3 then
		return Theme.Colors.MedalBronze
	end
	return nil
end

local function newRow(index: number): Row
	local colors, fonts = Theme.Colors, Theme.Fonts
	local rank = text("Rank", "", fonts.Title, 16, colors.Text, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	local medal = create("Frame", {
		Name = "Medal",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = colors.Reward,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", {
			Color = colors.Outline,
			Thickness = Theme.Stroke.Pill,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
		}),
		rank,
	})
	local name = text("Name", "", fonts.Label, 16, colors.Text, {
		Position = UDim2.fromOffset(48, 4),
		Size = UDim2.new(1, -150, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local title = text("Title", "", fonts.Body, 12, colors.Title, {
		Position = UDim2.new(0, 48, 0.5, 0),
		Size = UDim2.new(1, -150, 0.4, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local value = text("Value", "", fonts.Title, 20, colors.Text, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 96, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local frame = create("Frame", {
		Name = `Row{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = colors.CellEmpty,
		BackgroundTransparency = if index % 2 == 0 then 1 else 0,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		medal,
		name,
		title,
		value,
	})
	return { frame = frame, medal = medal, rank = rank, name = name, title = title, value = value }
end

function LeaderboardView.new(playerGui: PlayerGui, onClose: () -> ()): LeaderboardView
	local colors, fonts = Theme.Colors, Theme.Fonts

	-- Opaque full-screen sky over the menu; the card sits in the safe area above it.
	local backdrop = create("ScreenGui", {
		Name = "LeaderboardBackdrop",
		DisplayOrder = 12,
		ResetOnSpawn = false,
		Enabled = false,
	}, { Clay.sky("Fill", true) })
	backdrop.IgnoreGuiInset = true
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	local tabs = {
		all = tabButton("AllTime", "All time", 1),
		week = tabButton("ThisWeek", "This week", 2),
		Highscore = tabButton("Highscore", "Highscore", 3),
		Level = tabButton("Level", "Level", 4),
		Coop = tabButton("Coop", "Co-op", 5),
	}
	-- Two rows of two tabs, or one row of four on short screens (see layout()).
	local tabArea = create("Frame", {
		Name = "Tabs",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		create("UIPadding", { PaddingRight = UDim.new(0, 0) }),
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
		tabs.Coop,
	})

	local header = create("Frame", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
	}, {
		create("ImageLabel", {
			Name = "Trophy",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(36, 36),
			BackgroundTransparency = 1,
			Image = Theme.Images.Trophy,
		}),
		text("Heading", "Leaderboard", fonts.Title, Theme.TextSize.Title, colors.Text, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 46, 0.5, 0),
			Size = UDim2.new(1, -110, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})

	local rows = table.create(MAX_ROWS)
	for i = 1, MAX_ROWS do
		rows[i] = newRow(i)
	end
	local list = create("ScrollingFrame", {
		Name = "List",
		LayoutOrder = 3,
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
	local status = text("Status", "", fonts.Body, Theme.TextSize.Label, colors.TextMuted, {
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
	})
	local youPill = Clay.pill({ name = "You", text = "", icon = Theme.Images.Crown, order = 1 })
	local youRow = create("Frame", {
		Name = "You",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		youPill,
	})

	local closeButton = Clay.iconButton({ name = "Close", image = Theme.Images.Close })
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	closeButton.ZIndex = 5

	local pop = create("UIScale", { Name = "Pop" })
	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 1, -16),
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		pop,
		create("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
		create("Frame", {
			Name = "Body",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			create("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			header,
			tabArea,
			list,
			status,
			youRow,
		}),
		closeButton, -- on top of the body, outside its layout
	})
	local gui = create("ScreenGui", {
		Name = "Leaderboard",
		DisplayOrder = 13,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	}, { card })

	local self = setmetatable({
		backdrop = backdrop,
		gui = gui,
		header = header,
		tabArea = tabArea,
		tabs = tabs,
		rows = rows,
		list = list,
		status = status,
		youPill = youPill,
		closeButton = closeButton,
		pop = pop,
		period = "all" :: Period,
		board = "Highscore" :: Board,
		snapshot = nil,
		onClose = onClose,
		keyConnection = nil,
		connections = {},
	}, LeaderboardView)

	local function choose(period: Period?, board: Board?)
		if period == "week" and self.board == "Coop" then
			return -- the Co-op board has no weekly version
		end
		self.period = period or self.period
		self.board = board or self.board
		if self.board == "Coop" then
			self.period = "all"
		end
		self.list.CanvasPosition = Vector2.zero
		self:render()
	end
	table.insert(
		self.connections,
		Clay.face(tabs.all).Activated:Connect(function()
			choose("all", nil)
		end)
	)
	table.insert(
		self.connections,
		Clay.face(tabs.week).Activated:Connect(function()
			choose("week", nil)
		end)
	)
	table.insert(
		self.connections,
		Clay.face(tabs.Highscore).Activated:Connect(function()
			choose(nil, "Highscore")
		end)
	)
	table.insert(
		self.connections,
		Clay.face(tabs.Level).Activated:Connect(function()
			choose(nil, "Level")
		end)
	)
	table.insert(
		self.connections,
		Clay.face(tabs.Coop).Activated:Connect(function()
			choose(nil, "Coop")
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

-- Fits the screen: the two periods share a row and the three boards the next; on short screens the heading goes
-- and the five tabs share one row beside the close button, so more of the list shows.
function LeaderboardView.layout(self: LeaderboardView)
	local compact = self.gui.AbsoluteSize.Y > 0 and self.gui.AbsoluteSize.Y < COMPACT_HEIGHT
	self.header.Visible = not compact
	local padding = self.tabArea:FindFirstChildOfClass("UIPadding") :: UIPadding
	padding.PaddingRight = UDim.new(0, if compact then CLOSE_SIZE + 10 else 0)
	local period = if compact then UDim2.new(0.2, -7, 0, TAB_HEIGHT) else UDim2.new(0.5, -4, 0, TAB_HEIGHT)
	local board = if compact then period else UDim2.new(1 / 3, -6, 0, TAB_HEIGHT)
	for key, button in self.tabs do
		button.Size = if key == "all" or key == "week" then period else board
	end
end

local function formatValue(board: Board, period: Period, value: number): string
	if board == "Level" then
		return if period == "week" then `{Format.withCommas(value)} EXP` else `Lv {value}`
	end
	return Format.withCommas(value)
end

-- Draws the chosen board from the last snapshot (or "Loading…" before one arrives).
function LeaderboardView.render(self: LeaderboardView)
	local coop = self.board == "Coop" -- ranked by pair, all time only
	for key, button in self.tabs do
		local selected = key == self.board or key == (if coop then "all" else self.period)
		Clay.setStyle(button, if selected then "primary" else "secondary")
	end
	local weekFace = Clay.face(self.tabs.week)
	weekFace.Active = not coop
	weekFace.BackgroundTransparency = if coop then 0.55 else 0
	weekFace.TextTransparency = if coop then 0.45 else 0

	local snapshot = self.snapshot
	local entries = if snapshot then snapshot.boards[if coop then "Coop_all" else `{self.board}_{self.period}`] else nil
	local me = Players.LocalPlayer.UserId
	for i, row in self.rows do
		local entry = entries and entries[i]
		row.frame.Visible = entry ~= nil
		if entry then
			local medal = medalColor(entry.rank)
			row.medal.BackgroundTransparency = if medal then 0 else 1
			(row.medal:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = medal ~= nil
			if medal then
				row.medal.BackgroundColor3 = medal
			end
			row.rank.Text = tostring(entry.rank)
			row.name.Text = entry.name
			row.title.Text = entry.title or ""
			row.value.Text = formatValue(self.board, self.period, entry.value)
			-- The player's own row stands out in gold; the others alternate pale stripes.
			local isMe = entry.userId == me or (entry.userIds ~= nil and table.find(entry.userIds, me) ~= nil)
			row.frame.BackgroundColor3 = if isMe then Theme.Colors.Reward else Theme.Colors.CellEmpty
			row.frame.BackgroundTransparency = if isMe then 0.35 elseif i % 2 == 0 then 1 else 0
		end
	end

	local youLabel = Clay.pillLabel(self.youPill)
	if not snapshot then
		self.status.Text = "Loading…"
		self.status.Visible = true
		youLabel.Text = "—"
		return
	end
	-- The status line only takes room when the list has nothing to show.
	local empty = not entries or #entries == 0
	self.status.Text = if not empty
		then ""
		elseif coop then "No co-op scores yet. Play a run with a friend to get on the board!"
		else "No scores yet. Play a run to get on the board!"
	self.status.Visible = empty
	local you = snapshot.you
	if coop then
		youLabel.Text = `Your co-op best: {Format.withCommas(you.coopBest)}`
	elseif self.board == "Highscore" then
		youLabel.Text = if self.period == "week"
			then `Your best this week: {Format.withCommas(you.weekBest)}`
			else `Your best: {Format.withCommas(you.best)}`
	else
		youLabel.Text = if self.period == "week"
			then `Your EXP this week: {Format.withCommas(you.weekExp)}`
			else `Your level: {you.level}`
	end
end

function LeaderboardView.setSnapshot(self: LeaderboardView, snapshot: Snapshot)
	self.snapshot = snapshot
	self:render()
end

function LeaderboardView.open(self: LeaderboardView)
	self.backdrop.Enabled = true
	self.gui.Enabled = true
	Clay.popIn(self.pop, OPEN_START_SCALE, Theme.Motion.Panel)
	self:render()
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = Clay.face(self.tabs.all)
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
	local label = Clay.pillLabel(self.youPill).Text
	local lines = { `{self.board}_{self.period} status="{self.status.Text}" you="{label}"` }
	for _, row in self.rows do
		if row.frame.Visible then
			table.insert(lines, `#{row.rank.Text} {row.name.Text} [{row.title.Text}] {row.value.Text}`)
		end
	end
	return table.concat(lines, "\n")
end

return LeaderboardView
