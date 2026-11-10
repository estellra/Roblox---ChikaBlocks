--!strict
-- Draws the grid. render() only touches cells whose value changed since the last call.
-- While a piece is dragged, showPreview() draws a ghost where it would land and paints the lines it would
-- complete in its color; the ghost glides from cell to cell and the lines light up as they come in.
-- playMoveEffects() animates a placement; call it before rendering the new board.
-- setNoMoves() darkens the board with "No moves left" when the run ends.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local GameSession = require(ReplicatedStorage.Shared.GameSession)
local Pieces = require(ReplicatedStorage.Shared.Pieces)
local Block = require("./Block")
local Theme = require("./Theme")
local create = require("./Create")

type Piece = Pieces.Piece

local SIZE = Config.GRID_SIZE
local MAX_PIECE_CELLS = 9
local PLACE_START_SCALE = 0.72 -- a placed cell grows from this
local LINE_START_SCALE = 0.86 -- a line lighting up grows from this
local PUNCH_SCALE = 1.02 -- how far the board swells on a big clear

local BoardView = {}
BoardView.__index = BoardView

export type BoardView = typeof(setmetatable(
	{} :: {
		frame: Frame,
		grid: Frame, -- the area the cells cover; drag and drop maps screen positions through it
		blocks: { Frame }, -- one per cell, indexed like Board cells
		scales: { UIScale },
		shown: { number }, -- cell values currently drawn
		ghosts: { Frame },
		ghostBlocks: { Frame },
		ghostGroup: Frame, -- holds the ghosts; moving it moves the whole ghost in one tween
		ghostTween: Tween?,
		ghostShown: boolean,
		effects: Frame,
		highlighted: { number }, -- cells the preview painted, to restore later
		punch: UIScale,
		noMoves: Frame,
		noMovesLabel: TextLabel,
	},
	BoardView
))

-- A transparent frame covering one grid cell, holding a block with the board's inset and corners.
local function cellWithBlock(name: string, x: number, y: number, blockProps: { [string]: any }): (Frame, Frame)
	local inset = Theme.Spacing.CellInset
	local props: { [string]: any } = {
		Name = "Block",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1 - inset, 1 - inset),
		BorderSizePixel = 0,
	}
	for key, value in blockProps do
		props[key] = value
	end
	local block = create("Frame", props, { create("UICorner", { CornerRadius = Theme.Radius.Cell }) })
	Block.decorate(block)
	local cell = create("Frame", {
		Name = name,
		Position = UDim2.fromScale(x / SIZE, y / SIZE),
		Size = UDim2.fromScale(1 / SIZE, 1 / SIZE),
		BackgroundTransparency = 1,
	}, { block })
	return cell, block
end

local function layer(name: string, zIndex: number): Frame
	return create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
	})
end

function BoardView.new(parent: GuiObject): BoardView
	local padding = Theme.Spacing.BoardPadding
	local grid = layer("Grid", 1)
	local ghostLayer = layer("Ghosts", 2)
	local effects = layer("Effects", 3)

	local blocks, scales = table.create(SIZE * SIZE), table.create(SIZE * SIZE)
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			local cell, block = cellWithBlock(`Cell_{x}_{y}`, x, y, { BackgroundColor3 = Theme.Colors.CellEmpty })
			local scale = create("UIScale", { Parent = block }) -- place pops
			cell.Parent = grid
			blocks[Board.index(x, y)] = block
			scales[Board.index(x, y)] = scale
		end
	end

	local ghostGroup = create("Frame", {
		Name = "GhostGroup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ghostLayer,
	})
	local ghosts, ghostBlocks = table.create(MAX_PIECE_CELLS), table.create(MAX_PIECE_CELLS)
	for i = 1, MAX_PIECE_CELLS do
		local ghost, block = cellWithBlock(`Ghost{i}`, 0, 0, {})
		Block.setTransparency(block, Theme.Transparency.Ghost)
		ghost.Visible = false
		ghost.Parent = ghostGroup
		ghosts[i], ghostBlocks[i] = ghost, block
	end

	local noMovesLabel = create("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Title,
		TextScaled = true,
		TextColor3 = Theme.Colors.Text,
		Text = "No moves left",
	}, {
		create("UITextSizeConstraint", { MinTextSize = Theme.TextSize.GainMin, MaxTextSize = Theme.TextSize.GainMax }),
	})
	local noMoves = create("Frame", {
		Name = "NoMoves",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
		Visible = false,
	}, { create("UICorner", { CornerRadius = Theme.Radius.Board }), noMovesLabel })

	local punch = create("UIScale", { Name = "Punch" })
	local frame = create("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0.5), -- the punch swells it from the middle
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Board,
		BorderSizePixel = 0,
	}, {
		punch,
		create("UICorner", { CornerRadius = Theme.Radius.Board }),
		create("UIStroke", { Color = Theme.Colors.Outline, Thickness = Theme.Stroke.Panel }),
		create("UIPadding", {
			PaddingTop = padding,
			PaddingBottom = padding,
			PaddingLeft = padding,
			PaddingRight = padding,
		}),
		grid,
		ghostLayer,
		effects,
		noMoves,
	})
	frame.Parent = parent

	return setmetatable({
		frame = frame,
		grid = grid,
		blocks = blocks,
		scales = scales,
		shown = table.create(SIZE * SIZE, 0),
		ghosts = ghosts,
		ghostBlocks = ghostBlocks,
		ghostGroup = ghostGroup,
		ghostTween = nil,
		ghostShown = false,
		effects = effects,
		highlighted = {},
		punch = punch,
		noMoves = noMoves,
		noMovesLabel = noMovesLabel,
	}, BoardView)
end

function BoardView.render(self: BoardView, board: Board.Board)
	for index, value in board.cells do
		if self.shown[index] ~= value then
			Block.paint(self.blocks[index], value)
			self.shown[index] = value
		end
	end
end

-- Ghost of `piece` at cell (x, y) plus the rows and columns it would complete, painted in its color.
function BoardView.showPreview(self: BoardView, board: Board.Board, piece: Piece, x: number, y: number)
	local wasShown = self.ghostShown
	local lit: { [number]: boolean } = {}
	for _, index in self.highlighted do
		lit[index] = true
	end
	self:clearPreview()
	for i, cell in piece.cells do
		local ghost = self.ghosts[i]
		ghost.Position = UDim2.fromScale(cell.x / SIZE, cell.y / SIZE)
		Block.paint(self.ghostBlocks[i], piece.color)
		ghost.Visible = true
	end
	-- A ghost already on the board glides to the new cell; a new one starts where it belongs.
	local target = UDim2.fromScale(x / SIZE, y / SIZE)
	if wasShown then
		local glide = TweenInfo.new(Theme.Motion.GhostGlide, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(self.ghostGroup, glide, { Position = target })
		self.ghostTween = tween
		tween:Play()
	else
		self.ghostGroup.Position = target
	end
	self.ghostShown = true

	local lines = Board.previewLines(board, piece, x, y)
	local popInfo = TweenInfo.new(Theme.Motion.LinePop, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function paint(index: number)
		Block.paint(self.blocks[index], piece.color)
		table.insert(self.highlighted, index)
		if not lit[index] then -- only the cells that have just joined a line
			lit[index] = true
			local scale = self.scales[index]
			scale.Scale = LINE_START_SCALE
			TweenService:Create(scale, popInfo, { Scale = 1 }):Play()
		end
	end
	for _, row in lines.rows do
		for col = 0, SIZE - 1 do
			paint(Board.index(col, row))
		end
	end
	for _, col in lines.cols do
		for row = 0, SIZE - 1 do
			paint(Board.index(col, row))
		end
	end
end

function BoardView.clearPreview(self: BoardView)
	for _, ghost in self.ghosts do
		ghost.Visible = false
	end
	if self.ghostTween then
		self.ghostTween:Cancel()
		self.ghostTween = nil
	end
	self.ghostShown = false
	for _, index in self.highlighted do
		Block.paint(self.blocks[index], self.shown[index])
	end
	table.clear(self.highlighted)
end

-- Cleared cells go in a wave spreading out from where the piece landed: each one brightens, swells a little and
-- shrinks away. The placed piece's surviving cells pop in one after the other, and a clear of two lines or more
-- swells the whole board for a moment. Call before render(), while the board still shows the cells that are about
-- to clear.
function BoardView.playMoveEffects(self: BoardView, result: GameSession.PlaceResult)
	local cleared: { [number]: boolean } = {}
	for _, row in result.clearedRows do
		for col = 0, SIZE - 1 do
			cleared[Board.index(col, row)] = true
		end
	end
	for _, col in result.clearedCols do
		for row = 0, SIZE - 1 do
			cleared[Board.index(col, row)] = true
		end
	end

	local centerX = result.x + (result.piece.width - 1) / 2
	local centerY = result.y + (result.piece.height - 1) / 2
	for index in cleared do
		-- Cells of the piece just placed aren't drawn yet, so they take the piece's color.
		local value = self.shown[index]
		local x, y = (index - 1) % SIZE, (index - 1) // SIZE
		local cell, block = cellWithBlock("Clearing", x, y, {})
		Block.paint(block, if value ~= 0 then value else result.piece.color)
		local scale = create("UIScale", { Parent = block })
		cell.Parent = self.effects

		local delay = math.max(math.abs(x - centerX), math.abs(y - centerY)) * Theme.Motion.ClearStep
		local shrinkInfo =
			TweenInfo.new(Theme.Motion.Clear, Enum.EasingStyle.Back, Enum.EasingDirection.In, 0, false, delay)
		local fadeInfo =
			TweenInfo.new(Theme.Motion.Clear, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delay)
		TweenService:Create(block, fadeInfo, { BackgroundColor3 = Color3.new(1, 1, 1) }):Play()
		TweenService:Create(block:FindFirstChild("Edge") :: UIStroke, fadeInfo, { Transparency = 1 }):Play()
		local shrink = TweenService:Create(scale, shrinkInfo, { Scale = 0 })
		shrink.Completed:Once(function()
			cell:Destroy()
		end)
		shrink:Play()
	end

	for order, cell in result.piece.cells do
		local index = Board.index(result.x + cell.x, result.y + cell.y)
		if not cleared[index] then
			local scale = self.scales[index]
			scale.Scale = PLACE_START_SCALE
			local delay = (order - 1) * Theme.Motion.PlaceStep
			local popInfo =
				TweenInfo.new(Theme.Motion.PlacePop, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
			TweenService:Create(scale, popInfo, { Scale = 1 }):Play()
		end
	end

	if #result.clearedRows + #result.clearedCols >= 2 then
		self.punch.Scale = PUNCH_SCALE
		local settle = TweenInfo.new(Theme.Motion.Punch, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self.punch, settle, { Scale = 1 }):Play()
	end
end

-- Darkens the board with "No moves left" (fading in), or removes that.
function BoardView.setNoMoves(self: BoardView, visible: boolean)
	local frame, label = self.noMoves, self.noMovesLabel
	if not visible then
		frame.Visible = false
		return
	end
	if frame.Visible then
		return
	end
	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	frame.Visible = true
	local info = TweenInfo.new(Theme.Motion.NoMovesFade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, info, { BackgroundTransparency = Theme.Transparency.NoMoves }):Play()
	TweenService:Create(label, info, { TextTransparency = 0 }):Play()
end

function BoardView.destroy(self: BoardView)
	self.frame:Destroy()
end

return BoardView
