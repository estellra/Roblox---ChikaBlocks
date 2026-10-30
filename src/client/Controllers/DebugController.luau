--!strict
-- Studio-only test hook. Creates PlayerScripts.ChikaDebug (a BindableFunction) so playtests driven through
-- Studio MCP can read the state and play moves without real input, and prints the layout whenever it
-- changes. Does nothing outside Studio.
--
-- Commands: state | layout | place <slot> <x> <y> | autoplay <moves> | gameover | restart
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local GameController = require("./GameController")

local SIZE = Config.GRID_SIZE
local MAX_GAME_OVER_MOVES = 500

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
	return `score={session.score} over={session.isOver} moves={session.moveCount} tray={table.concat(tray, ",")}\n`
		.. table.concat(rows, "\n")
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

-- Plays one move: the placement clearing the most lines, or any valid placement when `random` is set.
local function playOne(rng: Random, random: boolean): boolean
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
	local move = if random and #candidates > 0 then candidates[rng:NextInteger(1, #candidates)] else best
	return move ~= nil and GameController.tryPlace(move[1], move[2], move[3]) ~= nil
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
		while played < moves and not GameController.getSession().isOver and playOne(rng, false) do
			played += 1
		end
		return `played {played}\n{describeState()}`
	elseif command == "gameover" then
		for _ = 1, MAX_GAME_OVER_MOVES do
			if GameController.getSession().isOver or not playOne(rng, true) then
				break
			end
		end
		return describeState()
	elseif command == "restart" then
		GameController.restart()
		return describeState()
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
