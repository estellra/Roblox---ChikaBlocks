--!strict
-- Draws the grid. render() only touches cells whose value changed since the last call.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require("./Theme")
local create = require("./Create")

local SIZE = Config.GRID_SIZE

local BoardView = {}
BoardView.__index = BoardView

export type BoardView = typeof(setmetatable(
	{} :: {
		frame: Frame,
		grid: Frame, -- the area the cells cover; drag and drop maps screen positions through it
		blocks: { Frame }, -- one per cell, indexed like Board cells
		shown: { number }, -- cell values currently drawn
	},
	BoardView
))

local function colorFor(value: number): Color3
	return if value == 0 then Theme.Colors.CellEmpty else Theme.Colors.Pieces[value]
end

function BoardView.new(parent: GuiObject): BoardView
	local inset = Theme.Spacing.CellInset
	local padding = Theme.Spacing.BoardPadding
	local grid = create("Frame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})

	local blocks = table.create(SIZE * SIZE)
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			local block = create("Frame", {
				Name = "Block",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1 - inset, 1 - inset),
				BackgroundColor3 = Theme.Colors.CellEmpty,
				BorderSizePixel = 0,
			}, {
				create("UICorner", { CornerRadius = Theme.Radius.Cell }),
				create("UIScale", {}), -- for clear and pop effects (M4)
			})
			create("Frame", {
				Name = `Cell_{x}_{y}`,
				Position = UDim2.fromScale(x / SIZE, y / SIZE),
				Size = UDim2.fromScale(1 / SIZE, 1 / SIZE),
				BackgroundTransparency = 1,
				Parent = grid,
			}, { block })
			blocks[Board.index(x, y)] = block
		end
	end

	local frame = create("Frame", {
		Name = "Board",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Board,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Board }),
		create("UIPadding", {
			PaddingTop = padding,
			PaddingBottom = padding,
			PaddingLeft = padding,
			PaddingRight = padding,
		}),
		grid,
	})
	frame.Parent = parent

	return setmetatable({
		frame = frame,
		grid = grid,
		blocks = blocks,
		shown = table.create(SIZE * SIZE, 0),
	}, BoardView)
end

function BoardView.render(self: BoardView, board: Board.Board)
	for index, value in board.cells do
		if self.shown[index] ~= value then
			self.blocks[index].BackgroundColor3 = colorFor(value)
			self.shown[index] = value
		end
	end
end

function BoardView.destroy(self: BoardView)
	self.frame:Destroy()
end

return BoardView
