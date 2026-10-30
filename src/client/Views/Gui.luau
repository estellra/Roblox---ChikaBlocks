--!strict
-- Builds the ScreenGuis and owns the responsive layout. Views only fill the areas handed out here.
--   Portrait  (narrow screens): HUD, board and tray stacked top to bottom, tray slots in a row
--   Landscape (wide screens):   board on the left; HUD above a column of tray slots on the right
-- The layout is re-applied whenever the safe area changes size (rotation, window resize, device switch).

local Theme = require("./Theme")
local create = require("./Create")

export type LayoutMode = "Portrait" | "Landscape"

export type Gui = {
	hudArea: Frame,
	boardArea: Frame,
	trayArea: Frame,
	dragLayer: Frame, -- full-screen layer above everything in the game UI, for pieces being dragged
	overlay: ScreenGui, -- disabled until a view shows something in it (game over)
	getMode: () -> LayoutMode,
	onLayoutChanged: (callback: (mode: LayoutMode) -> ()) -> (),
	destroy: () -> (),
}

local LANDSCAPE_MIN_RATIO = 1.1 -- width / height of the safe area

-- Sizes are scales of the parent (Root, or the side column in landscape).
local PORTRAIT = {
	hud = UDim2.fromScale(1, 0.12),
	board = UDim2.fromScale(1, 0.6),
	tray = UDim2.fromScale(1, 0.22),
	slot = UDim2.fromScale(0.3, 1),
}
local LANDSCAPE = {
	board = UDim2.fromScale(0.6, 1),
	side = UDim2.fromScale(0.36, 1),
	hud = UDim2.fromScale(1, 0.2),
	tray = UDim2.fromScale(1, 0.76),
	slot = UDim2.fromScale(1, 0.31),
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
	}, {
		create("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Colors.Background,
			BorderSizePixel = 0,
		}),
	})
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
	local trayLayout = listLayout("Layout", spacing.TrayGap)
	trayLayout.Parent = trayArea
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

	local overlay = create("ScreenGui", {
		Name = "Overlay",
		DisplayOrder = 2,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	overlay.IgnoreGuiInset = true
	overlay.ScreenInsets = Enum.ScreenInsets.None -- the dimmer covers the whole screen

	local mode: LayoutMode = "Portrait"
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
			trayLayout.FillDirection = Enum.FillDirection.Horizontal
			slotSize = PORTRAIT.slot
		else
			rootLayout.FillDirection = Enum.FillDirection.Horizontal
			boardArea.LayoutOrder, boardArea.Size = 1, LANDSCAPE.board
			sideColumn.Visible, sideColumn.Size = true, LANDSCAPE.side
			hudArea.Parent, hudArea.LayoutOrder, hudArea.Size = sideColumn, 1, LANDSCAPE.hud
			trayArea.Parent, trayArea.LayoutOrder, trayArea.Size = sideColumn, 2, LANDSCAPE.tray
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
	overlay.Parent = playerGui
	applyLayout()

	return {
		hudArea = hudArea,
		boardArea = boardArea,
		trayArea = trayArea,
		dragLayer = dragLayer,
		overlay = overlay,
		getMode = function(): LayoutMode
			return mode
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
			overlay:Destroy()
		end,
	}
end

return Gui
