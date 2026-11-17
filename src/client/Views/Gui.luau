--!strict
-- Builds the ScreenGuis and owns the responsive layout. Views only fill the areas handed out here.
--   Portrait  (narrow screens): HUD, board and tray stacked top to bottom, tray slots in a row
--   Landscape (wide screens):   board on the left; HUD above a column of tray slots on the right
-- A one-line hint (controls for keyboard and gamepad) sits under the tray in both layouts.
-- A PVP match uses the "match" variant of the landscape layout: under the HUD, the opponent's card (opponentArea), then
-- the tray as a row of three, then the hint. Portrait has no room for the opponent's card yet (mobile comes later).
-- The layout is re-applied whenever the safe area changes size (rotation, window resize, device switch).

local Clay = require("./Clay")
local Theme = require("./Theme")
local create = require("./Create")

export type LayoutMode = "Portrait" | "Landscape"
export type Variant = "normal" | "match"

export type Gui = {
	hudArea: Frame,
	boardArea: Frame,
	trayArea: Frame,
	opponentArea: Frame, -- the opponent's card in a PVP match (landscape only)
	dragLayer: Frame, -- full-screen layer above everything in the game UI, for pieces being dragged
	hint: TextLabel, -- keeps its space when empty, so the board doesn't resize as hints come and go
	overlay: ScreenGui, -- interactive panels over the game (game over); safe area, disabled until used
	overlayBackdrop: ScreenGui, -- full-screen dimmer under the overlay; disabled until used
	getMode: () -> LayoutMode,
	getVariant: () -> Variant,
	setVariant: (variant: Variant) -> (),
	onLayoutChanged: (callback: (mode: LayoutMode) -> ()) -> (),
	destroy: () -> (),
}

local LANDSCAPE_MIN_RATIO = 1.1 -- width / height of the safe area

-- Sizes are scales of the parent (Root, or the side column in landscape).
local PORTRAIT = {
	hud = UDim2.fromScale(1, 0.12),
	board = UDim2.fromScale(1, 0.57),
	tray = UDim2.fromScale(1, 0.2),
	hint = UDim2.fromScale(1, 0.04),
	slot = UDim2.fromScale(0.3, 1),
}
local LANDSCAPE = {
	board = UDim2.fromScale(0.6, 1),
	side = UDim2.fromScale(0.36, 1),
	hud = UDim2.fromScale(1, 0.2),
	tray = UDim2.fromScale(1, 0.7),
	hint = UDim2.fromScale(1, 0.06),
	slot = UDim2.fromScale(1, 0.31),
}
-- The side column of a PVP match (shares of the side column, like LANDSCAPE's).
local LANDSCAPE_MATCH = {
	hud = UDim2.fromScale(1, 0.19),
	opponent = UDim2.fromScale(1, 0.42),
	tray = UDim2.fromScale(1, 0.25),
	hint = UDim2.fromScale(1, 0.08),
	slot = UDim2.fromScale(0.3, 1),
}

local function area(name: string, layoutOrder: number): Frame
	return create("Frame", {
		Name = name,
		LayoutOrder = layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
end

local function listLayout(name: string, padding: UDim): UIListLayout
	return create("UIListLayout", {
		Name = name,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = padding,
	})
end

local Gui = {}

function Gui.create(playerGui: PlayerGui): Gui
	local spacing = Theme.Spacing

	-- Full-bleed background, drawn under the notch and the top bar.
	local background = create("ScreenGui", {
		Name = "Background",
		DisplayOrder = 0,
		ResetOnSpawn = false,
	}, { Clay.sky("Fill") })
	background.IgnoreGuiInset = true
	background.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	-- Interactive UI stays inside the area clear of device cutouts and Roblox's top bar.
	local hudArea = area("HudArea", 1)
	local boardArea = area("BoardArea", 2)
	create("UIAspectRatioConstraint", {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		Parent = boardArea,
	})
	local trayArea = area("TrayArea", 3)
	local opponentArea = area("OpponentArea", 2)
	opponentArea.Visible = false
	local trayLayout = listLayout("Layout", spacing.TrayGap)
	trayLayout.Parent = trayArea
	local hint = create("TextLabel", {
		Name = "Hint",
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextScaled = true,
		TextColor3 = Theme.Colors.TextMuted,
		Text = "",
	}, {
		create("UITextSizeConstraint", { MinTextSize = Theme.TextSize.HintMin, MaxTextSize = Theme.TextSize.HintMax }),
	})
	local sideColumn = area("SideColumn", 2)
	listLayout("Layout", spacing.Gap).Parent = sideColumn
	local rootLayout = listLayout("Layout", spacing.Gap)
	local root = create("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		create("UIPadding", {
			PaddingTop = spacing.ScreenPadding,
			PaddingBottom = spacing.ScreenPadding,
			PaddingLeft = spacing.ScreenPadding,
			PaddingRight = spacing.ScreenPadding,
		}),
		rootLayout,
		hudArea,
		boardArea,
		trayArea,
		hint,
		sideColumn,
	})
	local dragLayer = create("Frame", {
		Name = "DragLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 100,
	})
	local gameGui = create("ScreenGui", {
		Name = "Game",
		DisplayOrder = 1,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	}, { root, dragLayer })

	-- Non-interactive dimmer drawn under the notch and top bar; panels go in the safe-area overlay above it.
	local overlayBackdrop = create("ScreenGui", {
		Name = "OverlayBackdrop",
		DisplayOrder = 2,
		ResetOnSpawn = false,
		Enabled = false,
	})
	overlayBackdrop.IgnoreGuiInset = true
	overlayBackdrop.ScreenInsets = Enum.ScreenInsets.None -- after IgnoreGuiInset, which would reset it

	local overlay = create("ScreenGui", {
		Name = "Overlay",
		DisplayOrder = 3,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})

	local mode: LayoutMode = "Portrait"
	local variant: Variant = "normal"
	local slotSize = PORTRAIT.slot
	local listeners: { (mode: LayoutMode) -> () } = {}

	local function applyLayout()
		local size = root.AbsoluteSize
		mode = if size.Y > 0 and size.X / size.Y >= LANDSCAPE_MIN_RATIO then "Landscape" else "Portrait"
		if mode == "Portrait" then
			rootLayout.FillDirection = Enum.FillDirection.Vertical
			sideColumn.Visible = false
			hudArea.Parent, hudArea.LayoutOrder, hudArea.Size = root, 1, PORTRAIT.hud
			boardArea.LayoutOrder, boardArea.Size = 2, PORTRAIT.board
			trayArea.Parent, trayArea.LayoutOrder, trayArea.Size = root, 3, PORTRAIT.tray
			hint.Parent, hint.LayoutOrder, hint.Size = root, 4, PORTRAIT.hint
			trayLayout.FillDirection = Enum.FillDirection.Horizontal
			slotSize = PORTRAIT.slot
			opponentArea.Visible = false
		elseif variant == "match" then
			rootLayout.FillDirection = Enum.FillDirection.Horizontal
			boardArea.LayoutOrder, boardArea.Size = 1, LANDSCAPE.board
			sideColumn.Visible, sideColumn.Size = true, LANDSCAPE.side
			hudArea.Parent, hudArea.LayoutOrder, hudArea.Size = sideColumn, 1, LANDSCAPE_MATCH.hud
			opponentArea.Parent, opponentArea.LayoutOrder, opponentArea.Size = sideColumn, 2, LANDSCAPE_MATCH.opponent
			opponentArea.Visible = true
			trayArea.Parent, trayArea.LayoutOrder, trayArea.Size = sideColumn, 3, LANDSCAPE_MATCH.tray
			hint.Parent, hint.LayoutOrder, hint.Size = sideColumn, 4, LANDSCAPE_MATCH.hint
			trayLayout.FillDirection = Enum.FillDirection.Horizontal
			slotSize = LANDSCAPE_MATCH.slot
		else
			rootLayout.FillDirection = Enum.FillDirection.Horizontal
			boardArea.LayoutOrder, boardArea.Size = 1, LANDSCAPE.board
			sideColumn.Visible, sideColumn.Size = true, LANDSCAPE.side
			hudArea.Parent, hudArea.LayoutOrder, hudArea.Size = sideColumn, 1, LANDSCAPE.hud
			opponentArea.Visible = false
			trayArea.Parent, trayArea.LayoutOrder, trayArea.Size = sideColumn, 2, LANDSCAPE.tray
			hint.Parent, hint.LayoutOrder, hint.Size = sideColumn, 3, LANDSCAPE.hint
			trayLayout.FillDirection = Enum.FillDirection.Vertical
			slotSize = LANDSCAPE.slot
		end
		for _, child in trayArea:GetChildren() do
			if child:IsA("GuiObject") then
				child.Size = slotSize
			end
		end
		for _, listener in listeners do
			task.spawn(listener, mode)
		end
	end

	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		-- Tray slots are created by TrayView; size them for the current layout as they arrive.
		trayArea.ChildAdded:Connect(function(child)
			if child:IsA("GuiObject") then
				child.Size = slotSize
			end
		end),
	}

	background.Parent = playerGui
	gameGui.Parent = playerGui
	overlayBackdrop.Parent = playerGui
	overlay.Parent = playerGui
	applyLayout()

	return {
		hudArea = hudArea,
		boardArea = boardArea,
		trayArea = trayArea,
		opponentArea = opponentArea,
		dragLayer = dragLayer,
		hint = hint,
		overlay = overlay,
		overlayBackdrop = overlayBackdrop,
		getMode = function(): LayoutMode
			return mode
		end,
		getVariant = function(): Variant
			return variant
		end,
		setVariant = function(newVariant: Variant)
			if variant ~= newVariant then
				variant = newVariant
				applyLayout()
			end
		end,
		onLayoutChanged = function(callback: (mode: LayoutMode) -> ())
			table.insert(listeners, callback)
		end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(listeners)
			background:Destroy()
			gameGui:Destroy()
			overlayBackdrop:Destroy()
			overlay:Destroy()
		end,
	}
end

return Gui
