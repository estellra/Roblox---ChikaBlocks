--!strict
-- Keyboard and gamepad play through the Input Action System: choose a tray slot, lift the piece, move it
-- cell by cell, place it or put it back. Drives the same DragController intents as mouse and touch.
-- The "Gameplay" context is enabled only while a run is being played (not on the menu or the game over
-- panel), so there Enter, Space and the gamepad buttons work the menu buttons instead.
--
--   Select previous / next slot   Q / E         LB / RB
--   Move (cell by cell)           WASD, arrows  D-pad, left stick
--   Pick up / place               Space, Enter  A
--   Turn the piece (a rotation)   R             Y
--   Put back                      Backspace     B
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local DragController = require("./DragController")
local GameController = require("./GameController")
local MenuController = require("./MenuController")

type InputMode = "pointer" | "keyboard" | "gamepad"

local SIZE = Config.GRID_SIZE
local SLOTS = Config.PIECES_PER_SET
local REPEAT_DELAY = 0.25 -- holding a direction repeats after this long...
local REPEAT_INTERVAL = 0.08 -- ...then this often
local STICK_THRESHOLD = 0.5
local HINTS: { [InputMode]: string } = {
	pointer = "",
	keyboard = "Q/E select · Space place · R rotate · Bksp back",
	gamepad = "LB/RB select · A place · Y rotate · B back",
}

local GamepadController = {}

local context: InputContext
local moveAction: InputAction
local inputMode: InputMode = "pointer"
local selectedSlot = 1
local target = { x = 2, y = 2 } -- top-left cell of the held piece; kept between pieces
local keyDrag = false -- the current drag was started from the keyboard or gamepad
local heldDirection: { x: number, y: number }? = nil
local nextRepeatAt = 0

local function addAction(name: string, actionType: Enum.InputActionType, bindings: { { [string]: any } }): InputAction
	local action = Instance.new("InputAction")
	action.Name = name
	action.Type = actionType
	for _, properties in bindings do
		local binding = Instance.new("InputBinding")
		for key, value in properties do
			(binding :: any)[key] = value
		end
		binding.Parent = action
	end
	action.Parent = context
	return action
end

local function isPlaying(): boolean
	return GameController.getRunId() > 0
		and not GameController.getSession().isOver
		and not MenuController.isOpen()
		and not GameController.isPaused()
end

local function canAct(): boolean
	return isPlaying() and UserInputService:GetFocusedTextBox() == nil
end

local function isKeyDragging(): boolean
	keyDrag = keyDrag and DragController.isDragging()
	return keyDrag
end

-- Moves the selection to the next slot holding a piece, in direction `step` (1 or -1).
local function cycle(step: number)
	local tray = GameController.getSession().tray
	for offset = 1, SLOTS do
		local slot = ((selectedSlot - 1 + step * offset) % SLOTS) + 1
		if tray[slot] then
			selectedSlot = slot
			return
		end
	end
end

local function hoverTarget(width: number, height: number)
	target.x = math.clamp(target.x, 0, SIZE - width)
	target.y = math.clamp(target.y, 0, SIZE - height)
	DragController.hover(target.x, target.y)
end

local function confirm()
	if not canAct() then
		return
	end
	if DragController.isDragging() then
		if DragController.hasTarget() then
			DragController.drop() -- an invalid spot keeps the piece in hand
		end
		return
	end
	if not GameController.getSession().tray[selectedSlot] then
		cycle(1)
	end
	local piece = GameController.getSession().tray[selectedSlot]
	if piece and DragController.pick(selectedSlot, false) then
		keyDrag = true
		hoverTarget(piece.width, piece.height)
	end
end

local function putBack()
	if canAct() and isKeyDragging() then
		DragController.cancel()
	end
end

local function step(dx: number, dy: number)
	local piece = if isKeyDragging() then DragController.getPiece() else nil
	if piece then
		-- A turn may have moved the piece to keep it on the board; carry on from where it is now.
		local hoverX, hoverY = DragController.getHoverCell()
		if hoverX and hoverY then
			target.x, target.y = hoverX, hoverY
		end
		target.x += dx
		target.y += dy
		hoverTarget(piece.width, piece.height)
	elseif dx ~= 0 and not DragController.isDragging() then
		cycle(dx) -- left / right choose the piece while nothing is held
	end
end

-- The held direction as one board step: the stronger axis wins; Up (+Y for the action) is row - 1.
local function readDirection(): (number, number)
	local value = moveAction:GetState()
	if typeof(value) ~= "Vector2" then
		return 0, 0
	end
	if math.abs(value.X) < STICK_THRESHOLD and math.abs(value.Y) < STICK_THRESHOLD then
		return 0, 0
	end
	if math.abs(value.X) >= math.abs(value.Y) then
		return math.sign(value.X), 0
	end
	return 0, -math.sign(value.Y)
end

local function modeFor(inputType: Enum.UserInputType): InputMode?
	if inputType == Enum.UserInputType.Keyboard then
		return "keyboard"
	elseif string.find(inputType.Name, "Gamepad", 1, true) then
		return "gamepad"
	elseif
		inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.Touch
	then
		return "pointer"
	end
	return nil
end

local function update()
	local playing = isPlaying()
	if context.Enabled ~= playing then
		context.Enabled = playing
	end
	local views = GameController.getViews()
	if not views then
		return
	end
	local showKeys = playing and inputMode ~= "pointer"
	views.tray:setSelected(if showKeys then selectedSlot else nil)
	local hint = if playing then GameController.getRotationText() else ""
	local keys = if playing then HINTS[inputMode] else ""
	if keys ~= "" then
		hint = if hint ~= "" then `{hint}  |  {keys}` else keys
	end
	if views.gui.hint.Text ~= hint then
		views.gui.hint.Text = hint
	end
	if not playing then
		heldDirection = nil
		return
	end

	if showKeys and not isKeyDragging() and not GameController.getSession().tray[selectedSlot] then
		cycle(1)
	end
	local dx, dy = readDirection()
	local now = os.clock()
	if (dx == 0 and dy == 0) or UserInputService:GetFocusedTextBox() then
		heldDirection = nil
	elseif not heldDirection or heldDirection.x ~= dx or heldDirection.y ~= dy then
		heldDirection = { x = dx, y = dy }
		nextRepeatAt = now + REPEAT_DELAY
		step(dx, dy)
	elseif now >= nextRepeatAt then
		nextRepeatAt = now + REPEAT_INTERVAL
		step(dx, dy)
	end
end

-- For the Studio debug bridge.
function GamepadController.getStats(): { [string]: any }
	return {
		inputMode = inputMode,
		contextEnabled = context and context.Enabled,
		selectedSlot = selectedSlot,
		keyDrag = isKeyDragging(),
		target = `{target.x},{target.y}`,
	}
end

function GamepadController.start(_self: any)
	context = Instance.new("InputContext")
	context.Name = "Gameplay"
	context.Priority = 1000
	context.Enabled = false

	local K = Enum.KeyCode
	local Bool, Direction2D = Enum.InputActionType.Bool, Enum.InputActionType.Direction2D
	local selectPrevious = addAction("SelectPrevious", Bool, { { KeyCode = K.Q }, { KeyCode = K.ButtonL1 } })
	local selectNext = addAction("SelectNext", Bool, { { KeyCode = K.E }, { KeyCode = K.ButtonR1 } })
	moveAction = addAction("Move", Direction2D, {
		{ Up = K.W, Down = K.S, Left = K.A, Right = K.D },
		{ Up = K.Up, Down = K.Down, Left = K.Left, Right = K.Right },
		{ Up = K.DPadUp, Down = K.DPadDown, Left = K.DPadLeft, Right = K.DPadRight },
		{ KeyCode = K.Thumbstick1 },
	})
	local confirmAction = addAction("Confirm", Bool, {
		{ KeyCode = K.Space },
		{ KeyCode = K.Return },
		{ KeyCode = K.KeypadEnter },
		{ KeyCode = K.ButtonA },
	})
	local putBackAction = addAction("PutBack", Bool, { { KeyCode = K.Backspace }, { KeyCode = K.ButtonB } })
	local rotateAction = addAction("Rotate", Bool, { { KeyCode = K.R }, { KeyCode = K.ButtonY } })
	local pauseAction = addAction("Pause", Bool, { { KeyCode = K.P } })
	context.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")

	selectPrevious.Pressed:Connect(function()
		if canAct() and not DragController.isDragging() then
			cycle(-1)
		end
	end)
	selectNext.Pressed:Connect(function()
		if canAct() and not DragController.isDragging() then
			cycle(1)
		end
	end)
	confirmAction.Pressed:Connect(confirm)
	putBackAction.Pressed:Connect(putBack)
	rotateAction.Pressed:Connect(function()
		if not canAct() then
			return
		end
		if DragController.isDragging() then
			DragController.rotate() -- the piece in hand, for a mouse or touch drag as much as a key drag
		else
			GameController.tryRotate(selectedSlot)
		end
	end)
	pauseAction.Pressed:Connect(function()
		if canAct() then
			GameController.pause()
		end
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		inputMode = modeFor(inputType) or inputMode
	end)
	inputMode = modeFor(UserInputService:GetLastInputType()) or inputMode
	RunService.Heartbeat:Connect(update)
end

return GamepadController
