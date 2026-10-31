--!strict
-- Studio-only test hook. Creates PlayerScripts.ChikaDebug (a BindableFunction) so playtests driven through
-- Studio MCP can read the state and play moves without real input, and prints the layout whenever it
-- changes. Does nothing outside Studio.
--
-- Commands: state | layout | place <slot> <x> <y> | autoplay <moves> | gameover | restart
--           dragstats | dragpoint <slot> <x> <y> [touch] | pointer
--           playdrag <moves> (plays through the drag intents) | stats (leak checks)
-- Screen positions are in GUI space (as AbsolutePosition); `inset` is GuiService:GetGuiInset().
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local DragController = require("./DragController")
local DragMath = require("../Util/DragMath")
local GameController = require("./GameController")

local SIZE = Config.GRID_SIZE
local MAX_GAME_OVER_MOVES = 500
local MOVE_PACE_SECONDS = 0.13 -- bots play at a human pace, under the server's limit of 8 moves a second

local DebugController = {}

local function describeState(): string
	local session = GameController.getSession()
	local rows = table.create(SIZE)
	for y = 0, SIZE - 1 do
		local row = table.create(SIZE)
		for x = 0, SIZE - 1 do
			row[x + 1] = if Board.get(session.board, x, y) == 0 then "." else "#"
		end
		rows[y + 1] = table.concat(row)
	end
	local tray = {}
	for i, piece in session.tray do
		tray[i] = if piece then piece.id else "-"
	end
	local header =
		`run={GameController.getRunId()} score={session.score} over={session.isOver} moves={session.moveCount}`
	return `{header} tray={table.concat(tray, ",")}\n` .. table.concat(rows, "\n")
end

-- After the last piece of a set the tray stays empty until the server's next set arrives.
local function waitForTray(): boolean
	local deadline = os.clock() + 3
	while GameController.getSession().awaitingSet and os.clock() < deadline do
		task.wait()
	end
	return not GameController.getSession().awaitingSet
end

local function rect(object: GuiObject): string
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	return string.format("%dx%d@%d,%d", size.X, size.Y, position.X, position.Y)
end

local function describeLayout(): string
	local views = GameController.getViews()
	if not views then
		return "[Layout] UI not built yet"
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	local boardCell = views.board.grid.AbsoluteSize.X / SIZE
	local slot = views.tray.slots[1]
	local trayCell = slot.AbsoluteSize.X / 5
	return string.format(
		"[Layout] mode=%s viewport=%dx%d board=%s hud=%s slot1=%s boardCell=%.1f trayCell=%.1f (%.0f%%)",
		views.gui.getMode(),
		viewport.X,
		viewport.Y,
		rect(views.board.frame),
		rect(views.gui.hudArea),
		rect(slot),
		boardCell,
		trayCell,
		if boardCell > 0 then trayCell / boardCell * 100 else 0
	)
end

-- Picks a move: the placement clearing the most lines, or any valid placement when `random` is set.
local function chooseMove(rng: Random, random: boolean): { number }?
	local session = GameController.getSession()
	local candidates: { { number } } = {}
	local best: { number }? = nil
	local bestLines = -1
	for slot, piece in session.tray do
		if not piece then
			continue
		end
		for y = 0, SIZE - piece.height do
			for x = 0, SIZE - piece.width do
				if session:canPlace(slot, x, y) then
					table.insert(candidates, { slot, x, y })
					local lines = Board.previewLines(session.board, piece, x, y)
					local count = #lines.rows + #lines.cols
					if count > bestLines then
						best, bestLines = { slot, x, y }, count
					end
				end
			end
		end
	end
	return if random and #candidates > 0 then candidates[rng:NextInteger(1, #candidates)] else best
end

local function playOne(rng: Random, random: boolean): boolean
	local move = chooseMove(rng, random)
	return move ~= nil and GameController.tryPlace(move[1], move[2], move[3]) ~= nil
end

-- Plays a move the way a player does: pick from the tray, move the pointer onto the target, drop.
local function dragOne(rng: Random): boolean
	local move = chooseMove(rng, false)
	local views = GameController.getViews()
	if not move or not views then
		return false
	end
	local piece = GameController.getSession().tray[move[1]]
	if not piece or not DragController.pick(move[1], false) then
		return false
	end
	local grid = views.board.grid
	local pointerX, pointerY = DragMath.pointerFor({
		x = grid.AbsolutePosition.X,
		y = grid.AbsolutePosition.Y,
		size = grid.AbsoluteSize.X,
		cells = SIZE,
	}, move[2], move[3], piece.width, piece.height, false, DragController.TOUCH_LIFT_CELLS)
	DragController.movePointer(Vector2.new(pointerX, pointerY))
	return DragController.drop()
end

local function handle(rng: Random, command: string, ...: any): string
	local session = GameController.getSession()
	if command == "state" then
		return describeState()
	elseif command == "layout" then
		return describeLayout()
	elseif command == "place" then
		local slot, x, y = ...
		local result = GameController.tryPlace(slot, x, y)
		return if result then `placed +{result.points}\n{describeState()}` else "invalid move"
	elseif command == "autoplay" then
		local moves = tonumber((...)) or 10
		local played = 0
		while played < moves and waitForTray() and not GameController.getSession().isOver and playOne(rng, false) do
			played += 1
			task.wait(MOVE_PACE_SECONDS)
		end
		return `played {played}\n{describeState()}`
	elseif command == "gameover" then
		for _ = 1, MAX_GAME_OVER_MOVES do
			if not waitForTray() or GameController.getSession().isOver or not playOne(rng, true) then
				break
			end
			task.wait(MOVE_PACE_SECONDS)
		end
		return describeState()
	elseif command == "restart" then
		-- Waits for the server to start the new run.
		local before = GameController.getRunId()
		GameController.restart()
		local deadline = os.clock() + 5
		while GameController.getRunId() == before and os.clock() < deadline do
			task.wait()
		end
		return describeState()
	elseif command == "dragstats" then
		local stats = DragController.getStats()
		local parts = {}
		for key, value in stats do
			table.insert(parts, `{key}={value}`)
		end
		table.sort(parts)
		return table.concat(parts, " ")
	elseif command == "dragpoint" then
		-- Where to press (slot center) and release (pointer that drops the slot's piece on cell x, y).
		local slot, x, y, mode = ...
		local views = GameController.getViews()
		local piece = session.tray[slot]
		if not views or not piece then
			return "no piece in that slot"
		end
		local grid = views.board.grid
		local toX, toY = DragMath.pointerFor({
			x = grid.AbsolutePosition.X,
			y = grid.AbsolutePosition.Y,
			size = grid.AbsoluteSize.X,
			cells = SIZE,
		}, x, y, piece.width, piece.height, mode == "touch", DragController.TOUCH_LIFT_CELLS)
		local from = views.tray:center(slot)
		local inset = GuiService:GetGuiInset()
		return string.format(
			"piece=%s from=%d,%d to=%d,%d inset=%d,%d",
			piece.id,
			from.X,
			from.Y,
			toX,
			toY,
			inset.X,
			inset.Y
		)
	elseif command == "playdrag" then
		local moves = tonumber((...)) or 1000
		local played, failed = 0, 0
		while played < moves and waitForTray() and not GameController.getSession().isOver do
			if not dragOne(rng) then
				failed += 1
				break
			end
			played += 1
			task.wait(MOVE_PACE_SECONDS)
		end
		return `played {played} failed {failed}\n{describeState()}`
	elseif command == "stats" then
		local views = GameController.getViews()
		if not views then
			return "UI not built yet"
		end
		return string.format(
			"guiDescendants=%d dragLayer=%d effects=%d popups=%d dragConnections=%d restartKeys=%s overlay=%s luaHeapKB=%d",
			#Players.LocalPlayer.PlayerGui:GetDescendants(),
			#views.gui.dragLayer:GetChildren(),
			#views.board.effects:GetChildren(),
			#views.hud.popups:GetChildren(),
			DragController.getStats().connections,
			tostring(views.hud:isListeningForRestartKeys()),
			tostring(views.gui.overlay.Enabled),
			gcinfo()
		)
	elseif command == "pointer" then
		local stats = DragController.getStats()
		local mouse = UserInputService:GetMouseLocation()
		return `lastPointer={stats.lastPointer} lastInputType={stats.lastInputType} mouseLocation={mouse.X},{mouse.Y}`
	end
	return `unknown command "{command}" (score={session.score})`
end

function DebugController.start(_self: any)
	if not RunService:IsStudio() then
		return
	end
	-- GameController builds the UI in its own start(), which may still be running.
	local views = GameController.getViews()
	while not views do
		task.wait()
		views = GameController.getViews()
	end

	local rng = Random.new()
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ChikaDebug"
	bridge.OnInvoke = function(command: string, ...: any): string
		return handle(rng, command, ...)
	end
	bridge.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")

	views.gui.onLayoutChanged(function()
		task.wait(0.1) -- let the layout pass settle before reading sizes
		print(describeLayout())
	end)
	task.wait(0.1)
	print(describeLayout())
end

return DebugController
