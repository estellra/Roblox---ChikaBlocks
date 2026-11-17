--!strict
-- What a PVP match adds to the game screen (docs/PHASE6.md, M26; mockups in docs/mockups/phase6):
--   * the VS screen before the countdown (13-vs-practice-bot, 14-vs-ranked)
--   * "3, 2, 1  Get ready!" over the dimmed board (02-match-countdown)
--   * the player's IN column beside the board's bottom left corner: the garbage lines waiting, nearest at the bottom,
--     each with a small arrow for the side it will come in from; and an arrow on that side of the board for the next
--     one (04-match-garbage-arrives)
--   * the board sliding one cell as a garbage line is pushed in
--   * "Stuck! Board cleared" over the board and the tray locked with a countdown ring (12-match-stuck-locked)
--   * the result panel (10-result-friendly-loss, 11-result-ranked-win)
-- The opponent's card is OpponentBoardView; the clock is in the HUD bar. This only draws what PvpRunController tells it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Clay = require("./Clay")
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require("./Format")
local Theme = require("./Theme")
local create = require("./Create")

local QUEUE = Config.PVP.GARBAGE_QUEUE_MAX
local GARBAGE = Config.PVP.GARBAGE_COLOR
local SIZE = Config.GRID_SIZE
local IN_WIDTH = 30 -- the IN column's squares
local IN_GAP = 12 -- between the IN column and the board
local EDGE_ARROW_SIZE = 30
local PUSH_SECONDS = 0.25
local FLASH_SECONDS = 0.15
local LOCK_RING_SIZE = 64
local COUNT_POP_SCALE = 1.4 -- each countdown number shrinks in from this
local PANEL_WIDTH = 420
local SCORE_BOX_HEIGHT = 84

-- Garbage sides as PvpSession codes them: 1 bottom, 2 left, 3 right. An arrow points the way the line moves in.
local ARROW_ROTATION = { [1] = 0, [2] = 90, [3] = -90 }
-- Where a line from that side sits on the board's edge (as a position within the board) and how the board slides.
local EDGE_POSITION = { [1] = UDim2.fromScale(0.5, 1), [2] = UDim2.fromScale(0, 0.5), [3] = UDim2.fromScale(1, 0.5) }
local PUSH_FROM =
	{ [1] = UDim2.fromScale(0, 1 / SIZE), [2] = UDim2.fromScale(-1 / SIZE, 0), [3] = UDim2.fromScale(1 / SIZE, 0) }

export type Card = { name: string, initial: string, subtitle: string, color: Color3, subtitleColor: Color3? }

export type VsInfo = { label: string, you: Card, opponent: Card }

export type Result = {
	title: string, -- "You win!", "Mia wins", "Draw!"
	mood: "win" | "loss" | "draw",
	subtitle: string, -- "Time's up · friendly duel, no rank change"
	youName: string,
	opponentName: string,
	scores: { number }, -- you, opponent
	garbage: string, -- "Garbage sent 2 · blocked 4"
	canPlayAgain: boolean,
}

export type Callbacks = { onPlayAgain: () -> (), onMenu: () -> () }

local PvpView = {}
PvpView.__index = PvpView

export type PvpView = typeof(setmetatable(
	{} :: {
		boardFrame: Frame,
		grid: Frame,
		inColumn: Frame,
		inSlots: { Frame }, -- bottom first
		inArrows: { Frame },
		edgeArrow: Frame,
		countdown: Frame,
		countLabel: TextLabel,
		countPop: UIScale,
		countShown: number?,
		stuckCard: Frame,
		trayArea: GuiObject,
		lockLayer: GuiObject,
		lock: Frame,
		lockLabel: TextLabel,
		vsGui: ScreenGui,
		vsLabel: TextLabel,
		vsCards: { { root: Frame, circle: Frame, initial: TextLabel, name: TextLabel, subtitle: TextLabel } },
		resultGui: ScreenGui,
		resultPanel: Frame,
		mascot: ImageLabel,
		resultTitle: TextLabel,
		resultSubtitle: TextLabel,
		scoreBoxes: { { root: Frame, caption: TextLabel, value: TextLabel } },
		garbageLabel: TextLabel,
		rematchNote: TextLabel,
		playAgainRoot: Frame,
		menuRoot: Frame,
		connections: { RBXScriptConnection },
	},
	PvpView
))

local function label(name: string, text: string, font: Font, size: number, color: Color3, order: number?): TextLabel
	return create("TextLabel", {
		Name = name,
		LayoutOrder = order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = true,
		Text = text,
	})
end

-- A "^" made of two bars, pointing up; rotate the returned frame to point elsewhere.
local function chevron(name: string, color: Color3, thickness: number): Frame
	local function bar(x: number, rotation: number): Frame
		return create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.new(0.62, 0, 0, thickness),
			Rotation = rotation,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	return create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundTransparency = 1,
	}, { bar(0.3, -45), bar(0.7, 45) })
end

local function circleWith(initial: TextLabel, size: number): Frame
	return create("Frame", {
		Name = "Circle",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.Button,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = Theme.Colors.Outline, Thickness = Theme.Stroke.Panel }),
		initial,
	})
end

local function vsCard(order: number): (Frame, Frame, TextLabel, TextLabel, TextLabel)
	local colors, fonts = Theme.Colors, Theme.Fonts
	local initial = create("TextLabel", {
		Name = "Initial",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 44,
		TextColor3 = colors.Text,
		Text = "",
	})
	local circle = circleWith(initial, 104)
	local name = label("Name", "", fonts.Title, 30, colors.Text, 2)
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local subtitle = label("Subtitle", "", fonts.Label, 17, colors.TextMuted, 3)
	local root = create("Frame", {
		Name = `Card{order}`,
		LayoutOrder = order,
		Size = UDim2.fromOffset(300, 220),
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UIPadding", { PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18) }),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
		circle,
		name,
		subtitle,
	})
	return root, circle, initial, name, subtitle
end

local function scoreBox(order: number, color: Color3): (Frame, TextLabel, TextLabel)
	local caption = label("Caption", "", Theme.Fonts.Label, 15, Theme.Colors.Text, 1)
	caption.TextWrapped = false
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	local value = label("Value", "0", Theme.Fonts.Title, 34, Theme.Colors.Text, 2)
	local root = create("Frame", {
		Name = `Score{order}`,
		LayoutOrder = order,
		Size = UDim2.new(0.5, -5, 0, SCORE_BOX_HEIGHT),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 2),
		}),
		caption,
		value,
	})
	return root, caption, value
end

--- `boardArea` and `board` are the game screen's (Gui.boardArea, BoardView.frame and .grid); `trayArea` the tray's;
--- `lockLayer` a full-screen frame of the game screen above the tray (Gui.dragLayer).
function PvpView.new(
	playerGui: PlayerGui,
	boardArea: GuiObject,
	boardFrame: Frame,
	grid: Frame,
	trayArea: GuiObject,
	lockLayer: GuiObject,
	callbacks: Callbacks
): PvpView
	local colors, fonts = Theme.Colors, Theme.Fonts

	-- IN column: beside the board's bottom left corner, outside it.
	local inSlots: { Frame } = {}
	local inArrows: { Frame } = {}
	local inColumn = create("Frame", {
		Name = "PvpIn",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0, -IN_GAP, 1, 0),
		Size = UDim2.new(0, IN_WIDTH, 0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = boardArea,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 6),
		}),
		create("TextLabel", {
			Name = "Caption",
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			FontFace = fonts.Label,
			TextSize = 11,
			TextColor3 = colors.TextMuted,
			Text = "IN",
		}),
	})
	for i = 1, QUEUE do
		local arrow = chevron("Arrow", colors.Outline, 3)
		arrow.Visible = false
		local slot = create("Frame", {
			Name = `In{i}`,
			LayoutOrder = QUEUE - i + 1, -- the nearest line is at the bottom
			Size = UDim2.fromOffset(IN_WIDTH, IN_WIDTH),
			BackgroundColor3 = colors.Pieces[GARBAGE],
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = inColumn,
		}, {
			create("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			create("UIStroke", { Color = colors.TextMuted, Thickness = 1.5 }),
			arrow,
		})
		inSlots[i], inArrows[i] = slot, arrow
	end

	-- The arrow on the board's edge for the next garbage line: a cream disc on the board's outline.
	local edgeChevron = chevron("Chevron", colors.Outline, 4)
	local edgeArrow = create("Frame", {
		Name = "PvpEdgeArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(EDGE_ARROW_SIZE, EDGE_ARROW_SIZE),
		BackgroundColor3 = colors.Reward,
		BorderSizePixel = 0,
		ZIndex = 7,
		Visible = false,
		Parent = boardFrame,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = colors.Outline, Thickness = 2 }),
		edgeChevron,
	})

	-- Countdown over the dimmed board.
	local countPop = create("UIScale", {})
	local countStroke = create("UIStroke", { Color = colors.Outline, Thickness = 6 })
	local countLabel = create("TextLabel", {
		Name = "Number",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.5, 0.36),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextScaled = true,
		TextColor3 = colors.Reward,
		Text = "3",
	}, { countStroke, countPop })
	local readyStroke = create("UIStroke", { Color = colors.Outline, Thickness = 3 })
	local countdown = create("Frame", {
		Name = "PvpCountdown",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Overlay,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 8,
		Visible = false,
		Parent = boardFrame,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Board }),
		countLabel,
		create("TextLabel", {
			Name = "Ready",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.64),
			Size = UDim2.fromScale(0.8, 0.07),
			BackgroundTransparency = 1,
			FontFace = fonts.Title,
			TextScaled = true,
			TextColor3 = colors.Panel,
			Text = "Get ready!",
		}, { readyStroke }),
	})

	-- "Stuck! Board cleared" in the middle of the board.
	local stuckCard = create("Frame", {
		Name = "PvpStuck",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
		ZIndex = 8,
		Visible = false,
		Parent = boardFrame,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
		}),
		create("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			FontFace = fonts.Title,
			TextSize = 24,
			TextColor3 = colors.Text,
			Text = "Stuck! Board cleared",
		}),
	})

	-- The tray while it is locked: pale over the slots, and a ring counting down in the middle.
	local lockLabel = create("TextLabel", {
		Name = "Seconds",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 30,
		TextColor3 = colors.Text,
		Text = "5",
	})
	local lock = create("Frame", {
		Name = "PvpTrayLock",
		BackgroundColor3 = colors.Background,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Active = true, -- presses on the locked tray go nowhere
		ZIndex = 50,
		Visible = false,
		Parent = lockLayer,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.TraySlot }),
		create("Frame", {
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(LOCK_RING_SIZE, LOCK_RING_SIZE),
			BackgroundColor3 = colors.Panel,
			BorderSizePixel = 0,
			ZIndex = 51,
		}, {
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke", { Color = colors.Reward, Thickness = 5 }),
			lockLabel,
		}),
	})

	-- VS screen.
	local vsLabelText = create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = fonts.Label,
		TextSize = 16,
		TextColor3 = colors.Text,
		Text = "",
	})
	local vsPill = create("Frame", {
		Name = "Kind",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Pill }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		vsLabelText,
	})
	local youCard, youCircle, youInitial, youName, youSubtitle = vsCard(1)
	local oppCard, oppCircle, oppInitial, oppName, oppSubtitle = vsCard(3)
	local vsText = create("TextLabel", {
		Name = "Vs",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(160, 120),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 96,
		TextColor3 = colors.Reward,
		Text = "VS",
	}, { create("UIStroke", { Color = colors.Outline, Thickness = 6 }) })
	local vsGui = create("ScreenGui", {
		Name = "PvpVs",
		DisplayOrder = 6,
		ResetOnSpawn = false,
		Enabled = false,
	}, {
		Clay.sky("Sky", true),
		vsPill,
		create("Frame", {
			Name = "Row",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.47),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 48),
			}),
			youCard,
			vsText,
			oppCard,
		}),
		create("TextLabel", {
			Name = "Starting",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -60),
			Size = UDim2.fromOffset(300, 24),
			BackgroundTransparency = 1,
			FontFace = fonts.Label,
			TextSize = 18,
			TextColor3 = colors.TextMuted,
			Text = "Starting…",
		}),
	})
	vsGui.IgnoreGuiInset = true

	-- Result panel.
	local mascot = create("ImageLabel", {
		Name = "Mascot",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(84, 84),
		BackgroundTransparency = 1,
		Image = Theme.Images.MascotHappy,
	})
	local resultTitle = label("Title", "", fonts.Title, Theme.TextSize.Title, colors.Text, 2)
	local resultSubtitle = label("Subtitle", "", fonts.Label, 15, colors.TextMuted, 3)
	local youBox, youCaption, youValue = scoreBox(1, colors.Reward)
	local oppBox, oppCaption, oppValue = scoreBox(2, colors.ButtonDisabled)
	local scores = create("Frame", {
		Name = "Scores",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, SCORE_BOX_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		youBox,
		oppBox,
	})
	local garbageLabel = label("Garbage", "", fonts.Label, 15, colors.TextMuted, 5)
	local rematchNote = label("Rematch", "", fonts.Label, 15, colors.Title, 6)
	rematchNote.Visible = false
	local lip = Theme.Spacing.ButtonLip
	local playAgainRoot = Clay.button({
		name = "PlayAgain",
		text = "Play again",
		style = "primary",
		order = 7,
		size = UDim2.new(1, 0, 0, 56 + lip),
	})
	local menuRoot = Clay.button({
		name = "Menu",
		text = "Menu",
		style = "secondary",
		order = 8,
		size = UDim2.new(1, 0, 0, 56 + lip),
	})
	local resultPanel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 20),
			PaddingBottom = UDim.new(0, 20),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
		}),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
		mascot,
		resultTitle,
		resultSubtitle,
		scores,
		garbageLabel,
		rematchNote,
		playAgainRoot,
		menuRoot,
	})
	local resultGui = create("ScreenGui", {
		Name = "PvpResult",
		DisplayOrder = 7,
		ResetOnSpawn = false,
		Enabled = false,
	}, {
		create("Frame", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.Overlay,
			BackgroundTransparency = Theme.Transparency.Overlay,
			BorderSizePixel = 0,
			Active = true,
		}),
		resultPanel,
	})
	resultGui.IgnoreGuiInset = true

	vsGui.Parent = playerGui
	resultGui.Parent = playerGui

	local self = setmetatable({
		boardFrame = boardFrame,
		grid = grid,
		inColumn = inColumn,
		inSlots = inSlots,
		inArrows = inArrows,
		edgeArrow = edgeArrow,
		countdown = countdown,
		countLabel = countLabel,
		countPop = countPop,
		countShown = nil,
		stuckCard = stuckCard,
		trayArea = trayArea,
		lockLayer = lockLayer,
		lock = lock,
		lockLabel = lockLabel,
		vsGui = vsGui,
		vsLabel = vsLabelText,
		vsCards = {
			{ root = youCard, circle = youCircle, initial = youInitial, name = youName, subtitle = youSubtitle },
			{ root = oppCard, circle = oppCircle, initial = oppInitial, name = oppName, subtitle = oppSubtitle },
		},
		resultGui = resultGui,
		resultPanel = resultPanel,
		mascot = mascot,
		resultTitle = resultTitle,
		resultSubtitle = resultSubtitle,
		scoreBoxes = {
			{ root = youBox, caption = youCaption, value = youValue },
			{ root = oppBox, caption = oppCaption, value = oppValue },
		},
		garbageLabel = garbageLabel,
		rematchNote = rematchNote,
		playAgainRoot = playAgainRoot,
		menuRoot = menuRoot,
		connections = {},
	}, PvpView)
	table.insert(self.connections, Clay.face(playAgainRoot).Activated:Connect(callbacks.onPlayAgain))
	table.insert(self.connections, Clay.face(menuRoot).Activated:Connect(callbacks.onMenu))
	return self
end

--- Shows or hides what belongs on the game screen during a match (the IN column; the rest shows when it has
--- something to say).
function PvpView.setActive(self: PvpView, active: boolean)
	self.inColumn.Visible = active
	if not active then
		self:setPending({})
		self:setCountdown(nil)
		self:setStuck(false)
		self:setTrayLock(nil)
		self:hideVs()
		self:hideResult()
		self.grid.Position = UDim2.new()
	end
end

--- The VS screen.
function PvpView.showVs(self: PvpView, info: VsInfo)
	self.vsLabel.Text = info.label
	for index, card in { info.you, info.opponent } do
		local view = self.vsCards[index]
		view.initial.Text = card.initial
		view.circle.BackgroundColor3 = card.color
		view.name.Text = card.name
		view.subtitle.Text = card.subtitle
		view.subtitle.TextColor3 = card.subtitleColor or Theme.Colors.TextMuted
	end
	self.vsGui.Enabled = true
end

function PvpView.hideVs(self: PvpView)
	self.vsGui.Enabled = false
end

function PvpView.isVsOpen(self: PvpView): boolean
	return self.vsGui.Enabled
end

--- "3", "2", "1" over the dimmed board, each popping in; nil hides it.
function PvpView.setCountdown(self: PvpView, number: number?)
	self.countdown.Visible = number ~= nil
	if number and number ~= self.countShown then
		self.countLabel.Text = tostring(number)
		Clay.popIn(self.countPop, COUNT_POP_SCALE, Theme.Motion.ScorePop)
	end
	self.countShown = number
end

--- The player's garbage queue (sides, nearest first): the IN column and the arrow on the board's edge.
function PvpView.setPending(self: PvpView, pending: { number })
	for i, slot in self.inSlots do
		local side = pending[i]
		slot.BackgroundTransparency = if side then 0 else 1
		local arrow = self.inArrows[i]
		arrow.Visible = side ~= nil
		if side then
			arrow.Rotation = ARROW_ROTATION[side] or 0
		end
	end
	local next = pending[1]
	self.edgeArrow.Visible = next ~= nil
	if next then
		self.edgeArrow.Position = EDGE_POSITION[next] or EDGE_POSITION[1]
		local chevronFrame = self.edgeArrow:FindFirstChild("Chevron") :: Frame
		chevronFrame.Rotation = ARROW_ROTATION[next] or 0
	end
end

--- A garbage line came in from `side`: the board slides one cell away from that edge into place, and the arrow there
--- flashes.
function PvpView.pushBoard(self: PvpView, side: number)
	local from = PUSH_FROM[side]
	if not from then
		return
	end
	self.grid.Position = from
	local info = TweenInfo.new(PUSH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.grid, info, { Position = UDim2.new() }):Play()

	self.edgeArrow.Position = EDGE_POSITION[side]
	local chevronFrame = self.edgeArrow:FindFirstChild("Chevron") :: Frame
	chevronFrame.Rotation = ARROW_ROTATION[side] or 0
	local wasVisible = self.edgeArrow.Visible
	self.edgeArrow.Visible = true
	local flash = TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true)
	local tween = TweenService:Create(self.edgeArrow, flash, { BackgroundColor3 = Theme.Colors.Panel })
	tween.Completed:Once(function()
		self.edgeArrow.BackgroundColor3 = Theme.Colors.Reward
		if not wasVisible then
			self.edgeArrow.Visible = false
		end
	end)
	tween:Play()
end

--- "Stuck! Board cleared" over the board, while the tray is locked.
function PvpView.setStuck(self: PvpView, visible: boolean)
	self.stuckCard.Visible = visible
end

--- Locks the tray with `seconds` left on the ring, or (nil) unlocks it. Follows the tray area on screen.
function PvpView.setTrayLock(self: PvpView, seconds: number?)
	self.lock.Visible = seconds ~= nil
	if not seconds then
		return
	end
	local origin = self.lockLayer.AbsolutePosition
	local position, size = self.trayArea.AbsolutePosition, self.trayArea.AbsoluteSize
	self.lock.Position = UDim2.fromOffset(position.X - origin.X, position.Y - origin.Y)
	self.lock.Size = UDim2.fromOffset(size.X, size.Y)
	self.lockLabel.Text = tostring(seconds)
end

--- The result panel.
function PvpView.showResult(self: PvpView, result: Result)
	self.mascot.Image = if result.mood == "win"
		then Theme.Images.MascotCheer
		elseif result.mood == "loss" then Theme.Images.MascotSad
		else Theme.Images.MascotHappy
	self.resultTitle.Text = result.title
	self.resultSubtitle.Text = result.subtitle
	local boxes = self.scoreBoxes
	boxes[1].caption.Text = result.youName
	boxes[1].value.Text = Format.withCommas(result.scores[1])
	boxes[2].caption.Text = result.opponentName
	boxes[2].value.Text = Format.withCommas(result.scores[2])
	self.garbageLabel.Text = result.garbage
	self.playAgainRoot.Visible = result.canPlayAgain
	Clay.setEnabled(self.playAgainRoot, true)
	self.rematchNote.Visible = false
	self.resultGui.Enabled = true
	self.resultPanel.Position = UDim2.fromScale(0.5, 0.56)
	local slide = TweenInfo.new(Theme.Motion.Panel, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(self.resultPanel, slide, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
end

--- What Play again does now: enabled or waiting, the line under it ("Mia wants a rematch"), or gone (the opponent left).
function PvpView.setRematch(self: PvpView, available: boolean, enabled: boolean, note: string?)
	self.playAgainRoot.Visible = available
	Clay.setEnabled(self.playAgainRoot, enabled)
	self.rematchNote.Text = note or ""
	self.rematchNote.Visible = note ~= nil
end

function PvpView.hideResult(self: PvpView)
	self.resultGui.Enabled = false
end

function PvpView.isResultOpen(self: PvpView): boolean
	return self.resultGui.Enabled
end

--- For the Studio debug bridge.
function PvpView.describe(self: PvpView): string
	local pending = 0
	for _, slot in self.inSlots do
		if slot.BackgroundTransparency == 0 then
			pending += 1
		end
	end
	return `vs={self.vsGui.Enabled} countdown={if self.countdown.Visible then self.countLabel.Text else "off"} in={pending} edge={self.edgeArrow.Visible} stuck={self.stuckCard.Visible} lock={if self.lock.Visible
		then self.lockLabel.Text
		else "off"} result={if self.resultGui.Enabled then `"{self.resultTitle.Text}"` else "off"}`
end

return PvpView
