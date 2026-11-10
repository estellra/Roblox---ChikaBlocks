--!strict
-- Draws the tray slots. Each piece is drawn on a 5x5 grid centered in its slot, so every piece uses the same
-- cell size and the longest (5-cell) piece just fits. Slot sizes come from the Gui layout.
-- Each slot has a transparent Hitbox button on top that drag and drop listens to. A piece that can be turned
-- also gets a small Rotate button in the corner of its slot.
-- New pieces pop in one slot after the other, a turned piece spins into place, and slots fade as they empty.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Clay = require("./Clay")
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
		selections: { UIStroke }, -- outline of the slot chosen with keyboard or gamepad
		selected: number?,
		hint: number?, -- the slot the tutorial points at; the others fade
		hintStrokes: { UIStroke },
		held: { boolean }, -- slots whose piece is in hand
		rotateButtons: { TextButton },
		rotatable: { boolean }, -- slots whose piece can be turned, as far as the game says
		turning: number?, -- the slot the next render() spins instead of popping
		slotFades: { number }, -- the transparency each slot is at or fading to
		shown: { Piece | false },
	},
	TrayView
))

function TrayView.new(parent: GuiObject, onRotate: (slot: number) -> ()): TrayView
	local padding = Theme.Spacing.TraySlotPadding
	local slots, contents, hitboxes, selections, hintStrokes = {}, {}, {}, {}, {}
	local rotateButtons: { TextButton } = {}
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
		-- The game fonts have no turn arrow; this glyph comes from the emoji fallback.
		local rotate = Clay.iconButton({ name = "Rotate", text = "🔄" })
		-- Centered near the corner, so it sits mostly outside the 5x5 grid the piece is drawn on and covers no cell.
		rotate.AnchorPoint = Vector2.new(0.5, 0.5)
		rotate.Position = UDim2.fromScale(0.95, 0.95)
		rotate.Size = UDim2.fromScale(0.34, 0.34)
		rotate.ZIndex = 3 -- above the Hitbox, so a press on it doesn't start a drag
		rotate.Visible = false
		local glyph = rotate:FindFirstChild("Icon")
		if glyph and glyph:IsA("TextLabel") then
			glyph.TextScaled = true
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.Size = UDim2.fromScale(0.6, 0.6) -- the emoji's square must stay inside the disc
		end
		rotate.Activated:Connect(function()
			onRotate(i)
		end)
		local hintStroke = create("UIStroke", {
			Name = "Hint",
			Color = Theme.Colors.Selection,
			Thickness = 4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
		})
		local selection = create("UIStroke", {
			Name = "Selection",
			Color = Theme.Colors.Selection,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false,
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
			selection,
			hintStroke,
			content,
			hitbox,
			rotate,
		})
		contents[i] = content
		hitboxes[i] = hitbox
		selections[i] = selection
		hintStrokes[i] = hintStroke
		rotateButtons[i] = rotate
	end
	return setmetatable({
		slots = slots,
		contents = contents,
		hitboxes = hitboxes,
		selections = selections,
		selected = nil,
		hint = nil,
		hintStrokes = hintStrokes,
		held = table.create(Config.PIECES_PER_SET, false),
		shown = table.create(Config.PIECES_PER_SET, false),
		rotateButtons = rotateButtons,
		rotatable = table.create(Config.PIECES_PER_SET, false),
		turning = nil,
		slotFades = table.create(Config.PIECES_PER_SET, Theme.Transparency.TraySlot),
	}, TrayView)
end

-- A slot is faded when it is empty, its piece is in hand, or the tutorial points at another slot.
local function refreshSlot(self: TrayView, index: number)
	local faded = not self.shown[index] or self.held[index] or (self.hint ~= nil and self.hint ~= index)
	local target = if faded then Theme.Transparency.TraySlotEmpty else Theme.Transparency.TraySlot
	if self.slotFades[index] ~= target then
		self.slotFades[index] = target
		local info = TweenInfo.new(Theme.Motion.SlotFade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self.slots[index], info, { BackgroundTransparency = target }):Play()
	end
end

-- The Rotate button shows for a piece that can be turned, unless the piece is in hand.
local function refreshRotate(self: TrayView, index: number)
	self.rotateButtons[index].Visible = self.rotatable[index] and not self.held[index] and self.shown[index] ~= false
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
			if self.turning == index then
				-- A quarter turn back, this piece looks just like the one it replaces.
				preview.Rotation = -90
				local info = TweenInfo.new(Theme.Motion.Turn, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				TweenService:Create(preview, info, { Rotation = 0 }):Play()
			else
				local pop = create("UIScale", { Scale = 0, Parent = preview })
				local delay = (index - 1) * Theme.Motion.DealStep
				local info =
					TweenInfo.new(Theme.Motion.Deal, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
				TweenService:Create(pop, info, { Scale = 1 }):Play()
			end
		end
		self.shown[index] = piece
		refreshSlot(self, index)
		refreshRotate(self, index)
	end
	self.turning = nil
end

-- The next render() shows the piece in `slot` turning into place, rather than arriving.
function TrayView.markTurned(self: TrayView, slot: number)
	self.turning = slot
end

-- Outlines `slot` (keyboard and gamepad play); nil removes the outline.
function TrayView.setSelected(self: TrayView, slot: number?)
	if self.selected == slot then
		return
	end
	for index, selection in self.selections do
		selection.Enabled = index == slot
	end
	self.selected = slot
end

-- Points the tutorial at `slot` (a gold outline, the other slots fade); nil goes back to normal.
function TrayView.setHint(self: TrayView, slot: number?)
	self.hint = slot
	for index, stroke in self.hintStrokes do
		stroke.Enabled = index == slot
		refreshSlot(self, index)
	end
end

-- Hides the preview while its piece is being dragged.
function TrayView.setHidden(self: TrayView, slot: number, hidden: boolean)
	local preview = self.contents[slot]:FindFirstChild("Piece")
	if preview and preview:IsA("GuiObject") then
		preview.Visible = not hidden
	end
	self.held[slot] = hidden
	refreshSlot(self, slot)
	refreshRotate(self, slot)
end

-- Says which slots hold a piece that can be turned (and the run allows turning).
function TrayView.setRotatable(self: TrayView, rotatable: { boolean })
	for index = 1, Config.PIECES_PER_SET do
		self.rotatable[index] = rotatable[index] == true
		refreshRotate(self, index)
	end
end

-- Whether any piece is in hand.
function TrayView.isHeld(self: TrayView): boolean
	return table.find(self.held, true) ~= nil
end

-- Pixel size of one preview cell in this slot (0 when the slot is empty).
function TrayView.cellSize(self: TrayView, slot: number): number
	if not self.shown[slot] then
		return 0
	end
	-- From the slot, not the preview: a piece still popping in is smaller than it will be.
	local width = self.contents[slot].AbsoluteSize.X
	local padding = Theme.Spacing.TraySlotPadding
	return (width - 2 * (width * padding.Scale + padding.Offset)) / PREVIEW_GRID
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
