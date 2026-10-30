--!strict
-- Draws the tray slots. Each piece is drawn on a 5x5 grid centered in its slot, so every piece uses the same
-- cell size and the longest (5-cell) piece just fits. Slot sizes come from the Gui layout.
-- Each slot has a transparent Hitbox button on top that drag and drop listens to.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(ReplicatedStorage.Shared.Pieces)
local PieceView = require("./PieceView")
local Theme = require("./Theme")
local create = require("./Create")

type Piece = Pieces.Piece

local PREVIEW_GRID = 5

local TrayView = {}
TrayView.__index = TrayView

export type TrayView = typeof(setmetatable(
	{} :: {
		slots: { Frame },
		contents: { Frame }, -- padded area inside each slot that holds the piece preview
		hitboxes: { TextButton },
		shown: { Piece | false },
	},
	TrayView
))

function TrayView.new(parent: GuiObject): TrayView
	local padding = Theme.Spacing.TraySlotPadding
	local slots, contents, hitboxes = {}, {}, {}
	for i = 1, Config.PIECES_PER_SET do
		local content = create("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			create("UIPadding", {
				PaddingTop = padding,
				PaddingBottom = padding,
				PaddingLeft = padding,
				PaddingRight = padding,
			}),
		})
		local hitbox = create("TextButton", {
			Name = "Hitbox",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
		})
		slots[i] = create("Frame", {
			Name = `Slot{i}`,
			LayoutOrder = i,
			BackgroundColor3 = Theme.Colors.TraySlot,
			BackgroundTransparency = Theme.Transparency.TraySlot,
			BorderSizePixel = 0,
			Parent = parent,
		}, {
			create("UICorner", { CornerRadius = Theme.Radius.TraySlot }),
			create("UIAspectRatioConstraint", {
				AspectRatio = 1,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
			content,
			hitbox,
		})
		contents[i] = content
		hitboxes[i] = hitbox
	end
	return setmetatable({
		slots = slots,
		contents = contents,
		hitboxes = hitboxes,
		shown = table.create(Config.PIECES_PER_SET, false),
	}, TrayView)
end

function TrayView.render(self: TrayView, tray: { Piece | false })
	for index, piece in tray do
		if self.shown[index] == piece then
			continue
		end
		local content = self.contents[index]
		local old = content:FindFirstChild("Piece")
		if old then
			old:Destroy()
		end
		if piece then
			local preview = PieceView.build(piece)
			preview.AnchorPoint = Vector2.new(0.5, 0.5)
			preview.Position = UDim2.fromScale(0.5, 0.5)
			preview.Size = UDim2.fromScale(piece.width / PREVIEW_GRID, piece.height / PREVIEW_GRID)
			preview.Parent = content
		end
		self.shown[index] = piece
	end
end

-- Hides the preview while its piece is being dragged.
function TrayView.setHidden(self: TrayView, slot: number, hidden: boolean)
	local preview = self.contents[slot]:FindFirstChild("Piece")
	if preview and preview:IsA("GuiObject") then
		preview.Visible = not hidden
	end
end

-- Pixel size of one preview cell in this slot (0 when the slot is empty).
function TrayView.cellSize(self: TrayView, slot: number): number
	local piece = self.shown[slot]
	local preview = self.contents[slot]:FindFirstChild("Piece")
	if not piece or not preview or not preview:IsA("GuiObject") then
		return 0
	end
	return preview.AbsoluteSize.X / piece.width
end

-- Center of the slot's preview area, in screen pixels.
function TrayView.center(self: TrayView, slot: number): Vector2
	local content = self.contents[slot]
	return content.AbsolutePosition + content.AbsoluteSize / 2
end

function TrayView.destroy(self: TrayView)
	for _, slot in self.slots do
		slot:Destroy()
	end
end

return TrayView
