--!strict
-- Builds a piece as a frame of blocks laid out by Scale. The caller sets the frame's Size (and position);
-- blocks keep the same inset and corners as the board's cells at any size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pieces = require(ReplicatedStorage.Shared.Pieces)
local Theme = require("./Theme")
local create = require("./Create")

local PieceView = {}

function PieceView.build(piece: Pieces.Piece): Frame
	local inset = Theme.Spacing.CellInset
	local frame = create("Frame", {
		Name = "Piece",
		BackgroundTransparency = 1,
	})
	for _, cell in piece.cells do
		create("Frame", {
			Name = "Cell",
			Position = UDim2.fromScale(cell.x / piece.width, cell.y / piece.height),
			Size = UDim2.fromScale(1 / piece.width, 1 / piece.height),
			BackgroundTransparency = 1,
			Parent = frame,
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
	return frame
end

return PieceView
