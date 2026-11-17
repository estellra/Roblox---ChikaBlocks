--!strict
-- The opponent's card in a PVP match (mockup 07-match-playing): a colored circle and their name, their score in the
-- match, their board in small with its colors (garbage grey), and their IN column, the garbage lines waiting for them
-- as plain grey squares (their sides are only shown to the player they are coming for). It only draws what
-- PvpRunController hands it from Net.PvpOpponentBoard (see PvpBoardCodec); it never knows the opponent's tray.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Block = require("./Block")
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require("./Format")
local Theme = require("./Theme")
local create = require("./Create")

local SIZE = Config.GRID_SIZE
local QUEUE = Config.PVP.GARBAGE_QUEUE_MAX
local HEADER_SHARE = 0.17 -- of the card's inner height
local CIRCLE_SIZE = 22
local IN_SIZE = 22 -- the IN column's squares
local COLUMN_GAP = 10 -- between the small board and the IN column

local OpponentBoardView = {}
OpponentBoardView.__index = OpponentBoardView

export type OpponentBoardView = typeof(setmetatable(
	{} :: {
		card: Frame,
		circle: Frame,
		nameLabel: TextLabel,
		scoreLabel: TextLabel,
		blocks: { Frame },
		shown: { number },
		queue: { Frame }, -- bottom first
	},
	OpponentBoardView
))

local function inSlot(order: number): Frame
	return create("Frame", {
		Name = `In{order}`,
		LayoutOrder = order,
		Size = UDim2.fromOffset(IN_SIZE, IN_SIZE),
		BackgroundColor3 = Theme.Colors.Pieces[Config.PVP.GARBAGE_COLOR],
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
		create("UIStroke", { Color = Theme.Colors.TextMuted, Thickness = 1.5 }),
	})
end

function OpponentBoardView.new(parent: GuiObject): OpponentBoardView
	local colors, fonts = Theme.Colors, Theme.Fonts

	local circle = create("Frame", {
		Name = "Circle",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(CIRCLE_SIZE, CIRCLE_SIZE),
		BackgroundColor3 = colors.ButtonSecondary,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke", { Color = colors.Outline, Thickness = 2 }),
	})
	local nameLabel = create("TextLabel", {
		Name = "Name",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 20,
		TextColor3 = colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, { create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) })
	local scoreLabel = create("TextLabel", {
		Name = "Score",
		LayoutOrder = 3,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = fonts.Title,
		TextSize = 20,
		TextColor3 = colors.Text,
		Text = "0",
	})
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.fromScale(1, HEADER_SHARE),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
		circle,
		nameLabel,
		scoreLabel,
	})

	-- The small board: the same blocks as the big one, without the motion.
	local grid = create("Frame", {
		Name = "Board",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Board,
		BorderSizePixel = 0,
	}, {
		create("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize }),
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		create("UIStroke", { Color = colors.Outline, Thickness = 2 }),
	})
	local cells = create("Frame", {
		Name = "Cells",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.94),
		BackgroundTransparency = 1,
		Parent = grid,
	})
	local blocks: { Frame } = table.create(SIZE * SIZE)
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			local block = create("Frame", {
				Name = "Block",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.86, 0.86),
				BackgroundColor3 = colors.CellEmpty,
				BorderSizePixel = 0,
			}, { create("UICorner", { CornerRadius = Theme.Radius.Cell }) })
			Block.decorate(block)
			create("Frame", {
				Name = `Cell_{x}_{y}`,
				Position = UDim2.fromScale(x / SIZE, y / SIZE),
				Size = UDim2.fromScale(1 / SIZE, 1 / SIZE),
				BackgroundTransparency = 1,
				Parent = cells,
			}, { block })
			blocks[y * SIZE + x + 1] = block
		end
	end

	local queue: { Frame } = {}
	local column = create("Frame", {
		Name = "In",
		Size = UDim2.new(0, IN_SIZE + 4, 1, 0),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 4),
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
		-- Listed top to bottom, so the slot nearest to entering (queue[1]) is the last one.
		local slot = inSlot(QUEUE - i + 1)
		slot.Parent = column
		queue[i] = slot
	end

	local body = create("Frame", {
		Name = "Body",
		Position = UDim2.fromScale(0, HEADER_SHARE),
		Size = UDim2.fromScale(1, 1 - HEADER_SHARE),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, COLUMN_GAP),
		}),
		create("Frame", {
			Name = "BoardHolder",
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			create("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize }),
			grid,
		}),
		column,
	})
	column.LayoutOrder = 2

	local card = create("Frame", {
		Name = "Opponent",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.Panel,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Panel }),
		create("UIStroke", { Color = colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}),
		header,
		body,
	})

	return setmetatable({
		card = card,
		circle = circle,
		nameLabel = nameLabel,
		scoreLabel = scoreLabel,
		blocks = blocks,
		shown = table.create(SIZE * SIZE, 0),
		queue = queue,
	}, OpponentBoardView)
end

--- Who the opponent is: the name next to the circle.
function OpponentBoardView.setName(self: OpponentBoardView, name: string)
	self.nameLabel.Text = name
end

--- Draws the opponent's board, score and how many garbage lines wait for them (a PvpBoardCodec.View).
function OpponentBoardView.render(self: OpponentBoardView, view: { cells: { number }, score: number, pending: number })
	for index, value in view.cells do
		if self.shown[index] ~= value and self.blocks[index] then
			Block.paint(self.blocks[index], value)
			self.shown[index] = value
		end
	end
	self.scoreLabel.Text = Format.withCommas(view.score)
	for i, slot in self.queue do
		slot.BackgroundTransparency = if i <= view.pending then 0 else 1
	end
end

--- An empty board and score, for a match that is about to start.
function OpponentBoardView.reset(self: OpponentBoardView)
	self:render({ cells = table.create(SIZE * SIZE, 0), score = 0, pending = 0 })
end

function OpponentBoardView.destroy(self: OpponentBoardView)
	self.card:Destroy()
end

return OpponentBoardView
