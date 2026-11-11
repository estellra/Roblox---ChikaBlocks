--!strict
-- Drag and drop from the tray to the board, for mouse and touch.
-- The input adapter at the bottom turns pointer events into intents: pick(), movePointer(), drop(), cancel().
-- Keyboard and gamepad (GamepadController) drive the same intents, using hover() to target cells instead of a pointer.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(ReplicatedStorage.Shared.Pieces)
local DragMath = require("../Util/DragMath")
local GameController = require("./GameController")
local Block = require("../Views/Block")
local PieceView = require("../Views/PieceView")
local Theme = require("../Views/Theme")

type Piece = Pieces.Piece
type Views = GameController.Views

type Drag = {
	slot: number,
	piece: Piece,
	isTouch: boolean,
	frame: Frame, -- the floating piece, centered on its Position, in the drag layer
	scale: UIScale,
	cell: number, -- board cell size in pixels
	target: { x: number, y: number }?, -- board cell the piece would drop on
	blocked: boolean, -- faded: held with keys over cells it can't land on
	pointer: Vector2?, -- where the pointer last was (mouse and touch drags)
	hovered: { x: number, y: number }?, -- the cell the piece was last put over (keyboard and gamepad drags)
	connections: { RBXScriptConnection },
}

local DragController = {}

DragController.TOUCH_LIFT_CELLS = 1.5 -- how far above the finger a touch-dragged piece sits (less near the screen's bottom)
DragController.SNAP_ASSIST_CELLS = 0.75 -- how far from the nearest cell a drop may still snap to a free neighbour

local drag: Drag? = nil
local aimListeners: { (slot: number?, x: number?, y: number?) -> () } = {}
local returning: { [number]: Frame } = {} -- slot -> piece flying back to it after a cancelled drag
local lastPointer: Vector2? = nil
local lastInputType: Enum.UserInputType? = nil

local function getViews(): Views
	return GameController.getViews() :: Views
end

local function gridOf(views: Views): DragMath.Grid
	local grid = views.board.grid
	return {
		x = grid.AbsolutePosition.X,
		y = grid.AbsolutePosition.Y,
		size = grid.AbsoluteSize.X,
		cells = Config.GRID_SIZE,
	}
end

-- Bottom edge of the screen, in the coordinates of pointer positions and AbsolutePosition (below the top bar).
function DragController.getScreenBottom(): number
	local camera = workspace.CurrentCamera :: Camera
	return camera.ViewportSize.Y - GuiService:GetGuiInset().Y
end

-- Moves the floating piece so its center is at (x, y) in screen pixels.
local function placeFrame(current: Drag, x: number, y: number)
	local layer = (current.frame.Parent :: GuiObject).AbsolutePosition
	current.frame.Position = UDim2.fromOffset(x - layer.X, y - layer.Y)
end

-- Tells whoever listens (the Co-op partner's shadow) where the piece in hand is aimed: a slot and the board cell
-- it would land on, or nothing.
local function notifyAim(slot: number?, x: number?, y: number?)
	for _, listener in aimListeners do
		task.spawn(listener, slot, x, y)
	end
end

local function setTarget(current: Drag, x: number?, y: number?)
	local target = current.target
	if target and target.x == x and target.y == y then
		return
	end
	if x and y then
		current.target = { x = x, y = y }
		getViews().board:showPreview(GameController.getSession().board, current.piece, x, y)
		notifyAim(current.slot, x, y)
	elseif target then
		current.target = nil
		getViews().board:clearPreview()
		notifyAim(nil, nil, nil)
	end
end

local function setBlocked(current: Drag, blocked: boolean)
	if current.blocked == blocked then
		return
	end
	current.blocked = blocked
	for _, block in current.frame:GetDescendants() do
		if block.Name == "Block" and block:IsA("Frame") then
			Block.setTransparency(block, if blocked then Theme.Transparency.Blocked else 0)
		end
	end
end

local function endDrag(current: Drag)
	setTarget(current, nil, nil)
	for _, connection in current.connections do
		connection:Disconnect()
	end
	table.clear(current.connections)
	drag = nil
end

local function returnToTray(current: Drag)
	local views = getViews()
	local slot = current.slot
	local center = views.tray:center(slot)
	local layer = (current.frame.Parent :: GuiObject).AbsolutePosition
	local trayCell = views.tray:cellSize(slot)
	local info = TweenInfo.new(Theme.Motion.Return, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	setBlocked(current, false)
	returning[slot] = current.frame
	if trayCell > 0 then
		TweenService:Create(current.scale, info, { Scale = trayCell / current.cell }):Play()
	end
	local fly = TweenService:Create(current.frame, info, {
		Position = UDim2.fromOffset(center.X - layer.X, center.Y - layer.Y),
	})
	fly.Completed:Once(function()
		current.frame:Destroy()
		-- A new drag of this slot may have started meanwhile; it owns the preview's visibility then.
		if returning[slot] == current.frame then
			returning[slot] = nil
			views.tray:setHidden(slot, false)
		end
	end)
	fly:Play()
end

-- The dropped piece glides the last bit into the cells it now fills, then goes: the board draws it from here on.
local function landOnBoard(current: Drag, x: number, y: number)
	local grid = gridOf(getViews())
	local layer = (current.frame.Parent :: GuiObject).AbsolutePosition
	local piece, cell = current.piece, current.cell
	local info = TweenInfo.new(Theme.Motion.Land, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local land = TweenService:Create(current.frame, info, {
		Position = UDim2.fromOffset(
			grid.x + (x + piece.width / 2) * cell - layer.X,
			grid.y + (y + piece.height / 2) * cell - layer.Y
		),
	})
	land.Completed:Once(function()
		current.frame:Destroy()
	end)
	land:Play()
end

-- Called whenever the cell the piece in hand is aimed at changes (slot, x, y), and with nothing when it stops being
-- aimed at one (it left the board, was dropped or put back).
function DragController.onAim(callback: (slot: number?, x: number?, y: number?) -> ())
	table.insert(aimListeners, callback)
end

-- Intent: lift the piece in `slot` off the tray. Returns false when there is nothing to pick up (or, in Co-op, it is
-- the partner's).
function DragController.pick(slot: number, isTouch: boolean): boolean
	local views = GameController.getViews()
	local session = GameController.getSession()
	local piece = session.tray[slot]
	if drag or not views or session.isOver or not piece or not GameController.canDrag(slot) then
		return false
	end
	local flying = returning[slot]
	if flying then
		returning[slot] = nil
		flying:Destroy()
	end

	local cell = views.board.grid.AbsoluteSize.X / Config.GRID_SIZE
	local trayCell = views.tray:cellSize(slot)
	local frame = PieceView.build(piece)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(piece.width * cell, piece.height * cell)
	local scale = Instance.new("UIScale")
	scale.Scale = if trayCell > 0 then trayCell / cell else 1
	scale.Parent = frame
	frame.Parent = views.gui.dragLayer

	local current: Drag = {
		slot = slot,
		piece = piece,
		isTouch = isTouch,
		frame = frame,
		scale = scale,
		cell = cell,
		target = nil,
		blocked = false,
		pointer = nil,
		hovered = nil,
		connections = {},
	}
	drag = current
	local start = views.tray:center(slot)
	placeFrame(current, start.X, start.Y)
	views.tray:setHidden(slot, true)
	TweenService
		:Create(
			scale,
			TweenInfo.new(Theme.Motion.Pickup, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		:Play()
	return true
end

-- Intent: the pointer moved. The piece follows it and snaps to the board when it can land.
function DragController.movePointer(position: Vector2)
	local current = drag
	if not current then
		return
	end
	local piece, cell = current.piece, current.cell
	current.pointer, current.hovered = position, nil
	local grid = gridOf(getViews())
	local lift = if current.isTouch
		then DragMath.touchLift(position.Y, grid, DragController.TOUCH_LIFT_CELLS, DragController.getScreenBottom())
		else 0
	local left, top =
		DragMath.pieceTopLeft(position.X, position.Y, piece.width, piece.height, cell, current.isTouch, lift)
	placeFrame(current, left + piece.width * cell / 2, top + piece.height * cell / 2)

	local session = GameController.getSession()
	local x, y = DragMath.snap(left, top, grid, function(cellX: number, cellY: number): boolean
		return session:canPlace(current.slot, cellX, cellY)
	end, DragController.SNAP_ASSIST_CELLS)
	setTarget(current, x, y)
end

-- Intent (keyboard / gamepad): put the piece over board cell (x, y); it can land there only if it fits.
function DragController.hover(x: number, y: number)
	local current = drag
	if not current then
		return
	end
	local grid = gridOf(getViews())
	local piece, cell = current.piece, current.cell
	current.pointer, current.hovered = nil, { x = x, y = y }
	placeFrame(current, grid.x + (x + piece.width / 2) * cell, grid.y + (y + piece.height / 2) * cell)
	local fits = GameController.getSession():canPlace(current.slot, x, y)
	setTarget(current, if fits then x else nil, if fits then y else nil)
	setBlocked(current, not fits)
end

-- Intent: let go. Places the piece when it has a target, otherwise sends it back. Returns whether it placed.
function DragController.drop(): boolean
	local current = drag
	if not current then
		return false
	end
	local target = current.target
	endDrag(current)
	if target and GameController.tryPlace(current.slot, target.x, target.y) then
		landOnBoard(current, target.x, target.y)
		-- The slot may hold a freshly dealt piece now; make sure its preview shows.
		getViews().tray:setHidden(current.slot, false)
		return true
	end
	returnToTray(current)
	return false
end

-- Intent: abandon the drag; the piece goes back to its slot.
function DragController.cancel()
	local current = drag
	if not current then
		return
	end
	endDrag(current)
	returnToTray(current)
end

-- Intent: turn the piece in hand a quarter clockwise (it costs a rotation like any first turn of a piece).
-- GameController tells us when it turned; see onPieceTurned.
function DragController.rotate(): boolean
	local current = drag
	return current ~= nil and GameController.tryRotate(current.slot)
end

-- The piece in hand just turned in the tray's session: swap the floating piece for the turned one, spinning into
-- place, and aim it again at where the pointer or the keys had it.
local function onPieceTurned(slot: number)
	local current = drag
	local piece = GameController.getSession().tray[slot]
	if not current or current.slot ~= slot or not piece then
		return
	end
	setTarget(current, nil, nil) -- the old shape's ghost must go
	local old = current.frame
	local frame = PieceView.build(piece)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(piece.width * current.cell, piece.height * current.cell)
	frame.Position = old.Position
	-- A quarter turn back, the new piece looks just like the one it replaces.
	frame.Rotation = -90
	local scale = Instance.new("UIScale")
	scale.Scale = current.scale.Scale
	scale.Parent = frame
	frame.Parent = old.Parent
	old:Destroy()
	current.frame, current.scale, current.piece, current.blocked = frame, scale, piece, false
	local info = TweenInfo.new(Theme.Motion.Turn, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(frame, info, { Rotation = 0 }):Play()

	local pointer, hovered = current.pointer, current.hovered
	if pointer then
		DragController.movePointer(pointer)
	elseif hovered then
		-- The turned piece has other sides: keep it on the board.
		DragController.hover(
			math.clamp(hovered.x, 0, Config.GRID_SIZE - piece.width),
			math.clamp(hovered.y, 0, Config.GRID_SIZE - piece.height)
		)
	end
end

-- The board cell the piece in hand was last put over with keys or a gamepad (nil for pointer drags).
function DragController.getHoverCell(): (number?, number?)
	local current = drag
	local hovered = current and current.hovered
	if hovered then
		return hovered.x, hovered.y
	end
	return nil, nil
end

function DragController.isDragging(): boolean
	return drag ~= nil
end

-- The piece being dragged, if any.
function DragController.getPiece(): Piece?
	local current = drag
	return if current then current.piece else nil
end

-- Whether the dragged piece would land if dropped now.
function DragController.hasTarget(): boolean
	local current = drag
	return current ~= nil and current.target ~= nil
end

-- For the Studio debug bridge.
function DragController.getStats(): { [string]: any }
	local current = drag
	return {
		dragging = current ~= nil,
		slot = current and current.slot,
		target = current and current.target and `{current.target.x},{current.target.y}` or "none",
		connections = current and #current.connections or 0,
		returning = (function()
			local count = 0
			for _ in returning do
				count += 1
			end
			return count
		end)(),
		lastPointer = lastPointer,
		lastInputType = lastInputType,
	}
end

-- Input adapter: mouse and touch.
local function beginPointerDrag(slot: number, input: InputObject)
	local inputType = input.UserInputType
	local isTouch = inputType == Enum.UserInputType.Touch
	if not isTouch and inputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	lastInputType = inputType
	if not DragController.pick(slot, isTouch) then
		return
	end
	local current = drag :: Drag

	local function move(position: Vector3)
		local pointer = Vector2.new(position.X, position.Y)
		lastPointer = pointer
		DragController.movePointer(pointer)
	end

	-- Moving over GUI marks events as game-processed, so these deliberately ignore that flag.
	table.insert(
		current.connections,
		UserInputService.InputChanged:Connect(function(changed: InputObject)
			if isTouch then
				if changed == input then
					move(changed.Position)
				end
			elseif changed.UserInputType == Enum.UserInputType.MouseMovement then
				-- The button can be released outside the window, where no InputEnded arrives.
				if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					move(changed.Position)
				else
					DragController.drop()
				end
			end
		end)
	)
	table.insert(
		current.connections,
		UserInputService.InputEnded:Connect(function(ended: InputObject)
			local isOurs = if isTouch then ended == input else ended.UserInputType == Enum.UserInputType.MouseButton1
			if isOurs then
				move(ended.Position)
				DragController.drop()
			end
		end)
	)
	move(input.Position)
end

function DragController.start(_self: any)
	-- GameController builds the UI in its own start(), which may still be running.
	local views = GameController.getViews()
	while not views do
		task.wait()
		views = GameController.getViews()
	end
	for slot, hitbox in views.tray.hitboxes do
		hitbox.InputBegan:Connect(function(input: InputObject)
			beginPointerDrag(slot, input)
		end)
	end
	-- Cell sizes change with the layout and a new session has a new tray: drop any drag in progress.
	views.gui.onLayoutChanged(function()
		DragController.cancel()
	end)
	GameController.onSessionReplaced(DragController.cancel)
	GameController.onPieceTurned(onPieceTurned)
	-- A right click turns the piece in hand. Over the UI the click counts as processed, so that flag is ignored.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			DragController.rotate()
		end
	end)
end

return DragController
