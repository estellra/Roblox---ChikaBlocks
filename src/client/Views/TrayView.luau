--!strict
-- Draws the tray slots. Each piece is drawn on a 5x5 grid centered in its slot, so every piece uses the same
-- cell size and the longest (5-cell) piece just fits. Slot sizes come from the Gui layout.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(ReplicatedStorage.Shared.Pieces)
local Theme = require("./Theme")
local create = require("./Create")

type Piece = Pieces.Piece

local PREVIEW_GRID = 5

local TrayView = {}
TrayView.__index = TrayView

export type TrayView = typeof(setmetatable(
	{} :: {
		slots: { Frame }, -- drag and drop listens for input on these
		shown: { Piece | false },
	},
	TrayView
))

local function buildPreview(piece: Piece): Frame
	local inset = Theme.Spacing.CellInset
	local preview = create("Frame", {
		Name = "Piece",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(piece.width / PREVIEW_GRID, piece.height / PREVIEW_GRID),
		BackgroundTransparency = 1,
	})
	for _, cell in piece.cells do
		create("Frame", {
			Name = "Cell",
			Position = UDim2.fromScale(cell.x / piece.width, cell.y / piece.height),
			Size = UDim2.fromScale(1 / piece.width, 1 / piece.height),
			BackgroundTransparency = 1,
			Parent = preview,
		}, {
			create("Frame", {
				Name = "Block",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1 - inset, 1 - inset),
				BackgroundColor3 = Theme.Colors.Pieces[piece.color],
				BorderSizePixel = 0,
			}, { create("UICorner", { CornerRadius = Theme.Radius.Cell }) }),
		})
	end
	return preview
end

function TrayView.new(parent: GuiObject): TrayView
	local padding = Theme.Spacing.TraySlotPadding
	local slots = table.create(Config.PIECES_PER_SET)
	for i = 1, Config.PIECES_PER_SET do
		slots[i] = create("Frame", {
			Name = `Slot{i}`,
			LayoutOrder = i,
			BackgroundColor3 = Theme.Colors.TraySlot,
			BackgroundTransparency = Theme.Transparency.TraySlot,
			BorderSizePixel = 0,
			Parent = parent,
		}, {
			create("UICorner", { CornerRadius = Theme.Radius.TraySlot }),
			create("UIPadding", {
				PaddingTop = padding,
				PaddingBottom = padding,
				PaddingLeft = padding,
				PaddingRight = padding,
			}),
			create("UIAspectRatioConstraint", {
				AspectRatio = 1,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
		})
	end
	return setmetatable({
		slots = slots,
		shown = table.create(Config.PIECES_PER_SET, false),
	}, TrayView)
end

function TrayView.render(self: TrayView, tray: { Piece | false })
	for index, piece in tray do
		if self.shown[index] == piece then
			continue
		end
		local slot = self.slots[index]
		local old = slot:FindFirstChild("Piece")
		if old then
			old:Destroy()
		end
		if piece then
			buildPreview(piece).Parent = slot
		end
		self.shown[index] = piece
	end
end

function TrayView.destroy(self: TrayView)
	for _, slot in self.slots do
		slot:Destroy()
	end
end

return TrayView
