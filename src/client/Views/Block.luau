--!strict
-- The look of one block, as in the mockups: a pastel fill, an edge in a darker tone of the same color and a
-- small white shine in the top left corner. Empty board cells are plain (no edge, no shine).
-- Callers create the Frame (with its size and corners); decorate() adds the parts, paint() colors them.
local Theme = require("./Theme")
local create = require("./Create")

local SHINE_TRANSPARENCY = 0.4
local EDGE_THICKNESS = 2

local Block = {}

function Block.decorate(block: Frame)
	create("UIStroke", {
		Name = "Edge",
		Thickness = EDGE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Theme.Colors.Outline,
		Enabled = false,
		Parent = block,
	})
	create("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.16, 0.14),
		Size = UDim2.fromScale(0.3, 0.13),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = SHINE_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = block,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

-- Colors the block as piece color `color` (1..Config.COLOR_COUNT), or as an empty cell for 0.
function Block.paint(block: Frame, color: number)
	local edge = block:FindFirstChild("Edge") :: UIStroke
	local shine = block:FindFirstChild("Shine") :: Frame
	if color == 0 then
		block.BackgroundColor3 = Theme.Colors.CellEmpty
		edge.Enabled = false
		shine.Visible = false
		return
	end
	block.BackgroundColor3 = Theme.Colors.Pieces[color]
	edge.Color = Theme.Colors.PieceOutlines[color]
	edge.Enabled = true
	shine.Visible = true
end

-- Fades the whole block (fill, edge and shine); 0 is solid, 1 invisible.
function Block.setTransparency(block: Frame, transparency: number)
	block.BackgroundTransparency = transparency
	local edge = block:FindFirstChild("Edge") :: UIStroke
	local shine = block:FindFirstChild("Shine") :: Frame
	edge.Transparency = transparency
	shine.BackgroundTransparency = math.max(SHINE_TRANSPARENCY, transparency)
end

return Block
