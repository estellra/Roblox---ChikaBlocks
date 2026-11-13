--!strict
-- Draws the tray slots. Each piece is drawn on a 5x5 grid centered in its slot, so every piece uses the same
-- cell size and the longest (5-cell) piece just fits. Slot sizes come from the Gui layout.
-- Each slot has a transparent Hitbox button on top that drag and drop listens to. A piece that can be turned
-- also gets a Rotate button: a round disc whose touch area is at least Theme.MinTouchTarget, in the corner of
-- its slot (or beside it in the landscape layout, where the slots are small and the column has room).
-- New pieces pop in one slot after the other, a turned piece spins into place, and slots fade as they empty.
-- While the tray waits for the server's next set, the empty slots breathe so it doesn't look frozen.
-- The tray builds a slot for every piece of the biggest set (Co-op's four) once. A solo run uses the first three. In
-- Co-op the player's own two slots sit in the tray area and the partner's two are small, in a panel with the
-- partner's name where the third slot would be (configure()); both are the same slots, so drag and drop and the
-- gamepad treat them alike and only ask GameController which ones may be picked up.
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
local ROTATE_OUTSIDE_GAP = 6 -- pixels between a slot and its Rotate button in the landscape layout
local SLOT_CAPACITY = Config.COOP.SET_SIZE -- the most pieces a set can have
local PARTNER_LABEL_HEIGHT = 20
local PARTNER_SLOT_SHARE = 0.47 -- of the panel's width, for each of the partner's two slots

export type LayoutMode = "Portrait" | "Landscape"

local TrayView = {}
TrayView.__index = TrayView

export type Coop = { own: { number }, partnerName: string } -- own: the slots that are the player's (the other two are the partner's)

export type TrayView = typeof(setmetatable(
	{} :: {
		parent: GuiObject,
		partnerPanel: Frame, -- the partner's slots and their name; in the tray area only in Co-op
		partnerSlots: Frame,
		partnerLabel: TextLabel,
		partnerStroke: UIStroke, -- purple while the partner is here, gold once they have left
		partnerName: string,
		slots: { Frame },
		contents: { Frame }, -- padded area inside each slot that holds the piece preview
		hitboxes: { TextButton },
		selections: { UIStroke }, -- outline of the slot chosen with keyboard or gamepad
		selected: number?,
		hint: number?, -- the slot the tutorial points at; the others fade
		hintStrokes: { UIStroke },
		held: { boolean }, -- slots whose piece is in hand
		rotateButtons: { TextButton }, -- the touch areas; each holds the visible disc
		rotatable: { boolean }, -- slots whose piece can be turned, as far as the game says
		turning: number?, -- the slot the next render() spins instead of popping
		slotFades: { number }, -- the transparency each slot is at or fading to
		shown: { Piece | false },
		waits: { Frame }, -- the glow that breathes in an empty slot
		waitTweens: { Tween },
		waiting: boolean,
		waitToken: number, -- identifies the latest change of `waiting`, for the delayed start
	},
	TrayView
))

function TrayView.new(parent: GuiObject, onRotate: (slot: number) -> ()): TrayView
	local padding = Theme.Spacing.TraySlotPadding
	local slots, contents, hitboxes, selections, hintStrokes = {}, {}, {}, {}, {}
	local rotateButtons: { TextButton } = {}
	local waits: { Frame } = {}
	for i = 1, SLOT_CAPACITY do
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
		-- The visible disc. The game fonts have no turn arrow; its glyph comes from the emoji fallback.
		local disc = Clay.iconButton({ name = "Disc", text = "🔄" })
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(0.8, 0.8)
		disc.Interactable = false -- presses fall through to the touch area around it
		disc.ZIndex = 3
		local glyph = disc:FindFirstChild("Icon")
		if glyph and glyph:IsA("TextLabel") then
			glyph.TextScaled = true
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.Size = UDim2.fromScale(0.6, 0.6) -- the emoji's square must stay inside the disc
		end
		-- The touch area is a square that is never smaller than the minimum touch target, even when the slot is
		-- tiny (a phone held sideways); the disc inside may be smaller. setLayout() places it.
		local rotate = create("TextButton", {
			Name = "Rotate",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.95, 0.95),
			Size = UDim2.fromScale(0.4, 0.4),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 3, -- above the Hitbox, so a press on it doesn't start a drag
			Visible = false,
		}, {
			create("UIAspectRatioConstraint", { AspectRatio = 1 }),
			create("UISizeConstraint", { MinSize = Theme.MinTouchTarget }),
			disc,
		})
		local pressScale = disc:FindFirstChildOfClass("UIScale")
		local function press(down: boolean)
			if pressScale then
				local seconds = if down then Theme.Motion.ButtonPress else Theme.Motion.ButtonRelease
				local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(pressScale, info, { Scale = if down then 0.92 else 1 }):Play()
			end
		end
		rotate.MouseButton1Down:Connect(function()
			press(true)
		end)
		rotate.MouseButton1Up:Connect(function()
			press(false)
		end)
		rotate.MouseLeave:Connect(function()
			press(false)
		end)
		rotate.Activated:Connect(function()
			onRotate(i)
		end)
		-- Breathes while the tray waits for a new set; the slot's own fade is left alone.
		local wait = create("Frame", {
			Name = "Wait",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Colors.CellEmpty,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
		}, { create("UICorner", { CornerRadius = Theme.Radius.TraySlot }) })
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
		}, {
			create("UICorner", { CornerRadius = Theme.Radius.TraySlot }),
			create("UIAspectRatioConstraint", {
				AspectRatio = 1,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
			wait,
			selection,
			hintStroke,
			content,
			hitbox,
			rotate,
		})
		waits[i] = wait
		contents[i] = content
		hitboxes[i] = hitbox
		selections[i] = selection
		hintStrokes[i] = hintStroke
		rotateButtons[i] = rotate
	end
	local partnerLabel = create("TextLabel", {
		Name = "PartnerName",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, PARTNER_LABEL_HEIGHT),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Title,
		TextSize = 16,
		TextColor3 = Theme.Colors.Title,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	local partnerStroke = create("UIStroke", { Color = Theme.Colors.Title, Thickness = 2 })
	local partnerSlots = create("Frame", {
		Name = "Slots",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 1, -PARTNER_LABEL_HEIGHT - 4),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	-- The partner's side of the tray: a soft card edged in purple, so it reads as theirs.
	local partnerPanel = create("Frame", {
		Name = "Partner",
		LayoutOrder = 3,
		BackgroundColor3 = Theme.Colors.PartnerCard,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = Theme.Radius.Button }),
		create("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize }),
		partnerStroke,
		create("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		}),
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
		partnerLabel,
		partnerSlots,
	})
	local self = setmetatable({
		parent = parent,
		partnerPanel = partnerPanel,
		partnerSlots = partnerSlots,
		partnerLabel = partnerLabel,
		partnerStroke = partnerStroke,
		partnerName = "",
		slots = slots,
		contents = contents,
		hitboxes = hitboxes,
		selections = selections,
		selected = nil,
		hint = nil,
		hintStrokes = hintStrokes,
		held = table.create(SLOT_CAPACITY, false),
		shown = table.create(SLOT_CAPACITY, false),
		rotateButtons = rotateButtons,
		rotatable = table.create(SLOT_CAPACITY, false),
		turning = nil,
		slotFades = table.create(SLOT_CAPACITY, Theme.Transparency.TraySlot),
		waits = waits,
		waitTweens = {},
		waiting = false,
		waitToken = 0,
	}, TrayView)
	self:configure(nil)
	return self
end

-- Arranges the slots: nil for a solo run (the first three, in the tray area), or for Co-op the player's own two
-- there and the partner's two small beside them under the partner's name. Safe to call again.
function TrayView.configure(self: TrayView, coop: Coop?)
	if not coop then
		for index, slot in self.slots do
			slot.LayoutOrder = index
			slot.Parent = if index <= Config.PIECES_PER_SET then self.parent else nil
		end
		self.partnerPanel.Parent = nil
		return
	end
	local isOwn: { [number]: boolean } = {}
	for _, slot in coop.own do
		isOwn[slot] = true
	end
	local ownOrder, partnerOrder = 0, 0
	for index, slot in self.slots do
		if isOwn[index] then
			ownOrder += 1
			slot.LayoutOrder = ownOrder
			slot.Parent = self.parent -- the layout sizes it like any slot
		else
			partnerOrder += 1
			slot.LayoutOrder = partnerOrder
			slot.Parent = self.partnerSlots
			slot.Size = UDim2.fromScale(PARTNER_SLOT_SHARE, 1)
		end
	end
	self.partnerName = coop.partnerName
	self:setPartnerLeft(false)
	self.partnerPanel.LayoutOrder = ownOrder + 1
	self.partnerPanel.Parent = self.parent
end

-- The partner's card says who they are, or (gold) that they have left.
function TrayView.setPartnerLeft(self: TrayView, left: boolean)
	self.partnerLabel.Text = if left then `{self.partnerName} left` else self.partnerName
	self.partnerStroke.Color = if left then Theme.Colors.Reward else Theme.Colors.Title
end

-- Whether the slot's piece can be picked up is GameController's call; this only keeps its touch area from
-- reacting while it is locked (the partner's pieces).
function TrayView.setLocked(self: TrayView, slot: number, locked: boolean)
	self.hitboxes[slot].Active = not locked
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

-- The Rotate button shows for a piece that can be turned. It stays while the piece is in hand: a second finger
-- can tap it to turn the piece mid-drag.
local function refreshRotate(self: TrayView, index: number)
	self.rotateButtons[index].Visible = self.rotatable[index] and self.shown[index] ~= false
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
			preview.Visible = not self.held[index] -- a piece turned in hand stays hidden here until it is let go
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
	for index = 1, SLOT_CAPACITY do
		self.rotatable[index] = rotatable[index] == true
		refreshRotate(self, index)
	end
end

-- Whether any piece is in hand.
function TrayView.isHeld(self: TrayView): boolean
	return table.find(self.held, true) ~= nil
end

-- The slot whose piece is in hand, if any.
function TrayView.heldSlot(self: TrayView): number?
	return table.find(self.held, true)
end

-- Places each Rotate touch area for the layout: in the corner of its slot, or (landscape, where slots are small
-- and the side column is wide) beside it, so it covers no cell of the piece.
function TrayView.setLayout(self: TrayView, mode: LayoutMode)
	for _, button in self.rotateButtons do
		if mode == "Landscape" then
			button.AnchorPoint = Vector2.new(0, 0.5)
			button.Position = UDim2.new(1, ROTATE_OUTSIDE_GAP, 0.5, 0)
			button.Size = UDim2.fromScale(0.5, 0.5)
		else
			button.AnchorPoint = Vector2.new(0.5, 0.5)
			button.Position = UDim2.fromScale(0.95, 0.95)
			button.Size = UDim2.fromScale(0.4, 0.4)
		end
	end
end

local function stopWaiting(self: TrayView)
	for _, tween in self.waitTweens do
		tween:Cancel()
	end
	table.clear(self.waitTweens)
	for _, glow in self.waits do
		glow.Visible = false
		glow.BackgroundTransparency = 1
	end
end

-- While `waiting` (the last piece is down and the server's next set has not come) the empty slots breathe, but
-- only after WaitDelay, so a normal round trip never flashes it. Safe to call on every render.
function TrayView.setWaiting(self: TrayView, waiting: boolean)
	if self.waiting == waiting then
		return
	end
	self.waiting = waiting
	self.waitToken += 1
	if not waiting then
		stopWaiting(self)
		return
	end
	local token = self.waitToken
	task.delay(Theme.Motion.WaitDelay, function()
		if token ~= self.waitToken then
			return
		end
		for index, glow in self.waits do
			glow.BackgroundTransparency = 0.85
			glow.Visible = true
			local info = TweenInfo.new(
				Theme.Motion.WaitPulse,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true,
				(index - 1) * Theme.Motion.WaitStep
			)
			local tween = TweenService:Create(glow, info, { BackgroundTransparency = 0.3 })
			table.insert(self.waitTweens, tween)
			tween:Play()
		end
	end)
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
	self.waitToken += 1
	stopWaiting(self)
	for _, slot in self.slots do
		slot:Destroy()
	end
	self.partnerPanel:Destroy()
end

return TrayView
