--!strict
-- Studio-only test hook. Creates PlayerScripts.ChikaDebug (a BindableFunction) so playtests driven through
-- Studio MCP can read the state and play moves without real input, and prints the layout whenever it
-- changes. Does nothing outside Studio.
--
-- Commands: state | layout | place <slot> <x> <y> | autoplay <moves> | gameover | restart
--           dragstats | dragpoint <slot> <x> <y> [touch] | pointer
--           play [normal|tutorial] (leaves the menu like the Play button) | flow (menu, run mode, hints, keys)
--           leaderboard [open|close] (opens it from the menu and lists what it shows)
--           playdrag <moves> (plays through the drag intents) | stats (leak checks)
--           touchdrop <slot> <x> <y> (drops through the touch path, reports where the finger had to be)
--           dragturn <slot> [times] (holds a piece over the board and turns it) | waitfx (the tray's waiting effect)
--           rotatebuttons (size and place of each Rotate touch area)
--           coop [open|close|people <n>|invite [id] [seconds]|result <result> [userId]|room [left]|noroom|busy <reason|none>|press <userId> [result...]|cancel]
--           (opens the Co-op screen and lists it; the rest feed it what the server would send, with the player
--           themselves as the other party, or press Invite for a made-up person)
--           queue [open|keep|practice|close] (the ranked queue screen)
--           pvp [again|menu] (the PVP match on this screen; again / menu press the result panel's buttons. Start one
--           against the bot with ServerStorage.ChikaServerDebug "pvpbot")
--           coop run | coop play [moves] | coop again | coop leave | coop takeover | coop rotate [slot] | coop revive
--           (the Co-op run on this screen: its state, play random moves of the player's own, Play again, Menu / Leave
--           run, Take over. Pair with the practice partner first: ServerStorage.ChikaServerDebug "coopbot")
-- Screen positions are in GUI space (as AbsolutePosition); `inset` is GuiService:GetGuiInset().
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Board = require(ReplicatedStorage.Shared.Board)
local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(ReplicatedStorage.Shared.Pieces)
local CoopController = require("./CoopController")
local CoopRunController = require("./CoopRunController")
local DragController = require("./DragController")
local DragMath = require("../Util/DragMath")
local GameController = require("./GameController")
local GamepadController = require("./GamepadController")
local LeaderboardController = require("./LeaderboardController")
local SupportController = require("./SupportController")
local MenuController = require("./MenuController")
local PvpRunController = require("./PvpRunController")
local QueueController = require("./QueueController")
local TutorialController = require("./TutorialController")
local Theme = require("../Views/Theme")

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
		if not piece or not GameController.canDrag(slot) then
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

-- Pointer that drops `piece` on cell (x, y), held by a mouse or a finger.
local function pointerFor(
	views: GameController.Views,
	piece: Pieces.Piece,
	x: number,
	y: number,
	isTouch: boolean
): (number, number)
	local grid = views.board.grid
	return DragMath.pointerFor({
		x = grid.AbsolutePosition.X,
		y = grid.AbsolutePosition.Y,
		size = grid.AbsoluteSize.X,
		cells = SIZE,
	}, x, y, piece.width, piece.height, isTouch, DragController.TOUCH_LIFT_CELLS, DragController.getScreenBottom())
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
	local pointerX, pointerY = pointerFor(views, piece, move[2], move[3], false)
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
	elseif command == "rotate" then
		local slot = ...
		local turned = GameController.tryRotate(slot)
		return `{if turned then "rotated" else "not rotated"} | {GameController.getRotationText()}\n{describeState()}`
	elseif command == "dragturn" then
		-- Picks the piece in a slot, holds it over the board and turns it `times` times (the drag-rotate path).
		local slot, times = ...
		local views = GameController.getViews()
		if not views or not DragController.pick(slot, false) then
			return "nothing to pick"
		end
		local grid = views.board.grid
		local reach = grid.AbsoluteSize.X * 0.4
		DragController.movePointer(Vector2.new(grid.AbsolutePosition.X + reach, grid.AbsolutePosition.Y + reach))
		local lines = {}
		for turn = 1, tonumber(times) or 1 do
			local turned = DragController.rotate()
			local piece = DragController.getPiece()
			table.insert(
				lines,
				`turn {turn}: turned={turned} piece={piece and piece.id} target={DragController.hasTarget()}`
			)
		end
		local other = if slot == 1 then 2 else 1
		local preview = views.tray.contents[slot]:FindFirstChild("Piece")
		local otherTurns = GameController.tryRotate(other)
		table.insert(
			lines,
			`held={views.tray:heldSlot()} trayPreviewVisible={preview and (preview :: GuiObject).Visible} rotateButtonVisible={views.tray.rotateButtons[slot].Visible} dragFrames={#views.gui.dragLayer:GetChildren()} otherSlotTurns={otherTurns}`
		)
		table.insert(lines, GameController.getRotationText())
		DragController.cancel()
		task.wait(0.4)
		local after = GameController.getSession().tray[slot]
		table.insert(lines, `after cancel: dragging={DragController.isDragging()} slot piece={after and after.id}`)
		return table.concat(lines, "\n")
	elseif command == "waitfx" then
		-- Shows the tray's waiting effect for a moment and reports what it did.
		local views = GameController.getViews()
		if not views then
			return "UI not built yet"
		end
		local tray = views.tray
		tray:setWaiting(true)
		local lines = { `right away: glow1={tray.waits[1].Visible}` }
		task.wait(Theme.Motion.WaitDelay + 0.3)
		table.insert(
			lines,
			`after delay: glow1={tray.waits[1].Visible} glow3={tray.waits[3].Visible} tweens={#tray.waitTweens}`
		)
		tray:setWaiting(false)
		table.insert(lines, `stopped: glow1={tray.waits[1].Visible} tweens={#tray.waitTweens}`)
		tray:setWaiting(true)
		task.wait(0.1)
		tray:setWaiting(false) -- a quick set never starts the effect
		task.wait(Theme.Motion.WaitDelay + 0.2)
		table.insert(lines, `quick set: glow1={tray.waits[1].Visible} tweens={#tray.waitTweens}`)
		return table.concat(lines, "\n")
	elseif command == "rotatebuttons" then
		-- Size and place of each Rotate touch area against its slot, in the current layout.
		local views = GameController.getViews()
		if not views then
			return "UI not built yet"
		end
		local lines = { `mode={views.gui.getMode()}` }
		for index, button in views.tray.rotateButtons do
			local slot = views.tray.slots[index]
			lines[#lines + 1] = string.format(
				"slot%d %dx%d@%d,%d  button %dx%d@%d,%d visible=%s",
				index,
				slot.AbsoluteSize.X,
				slot.AbsoluteSize.Y,
				slot.AbsolutePosition.X,
				slot.AbsolutePosition.Y,
				button.AbsoluteSize.X,
				button.AbsoluteSize.Y,
				button.AbsolutePosition.X,
				button.AbsolutePosition.Y,
				tostring(button.Visible)
			)
		end
		return table.concat(lines, "\n")
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
		MenuController.play("normal")
		local deadline = os.clock() + 5
		while GameController.getRunId() == before and os.clock() < deadline do
			task.wait()
		end
		return describeState()
	elseif command == "play" then
		local mode = ...
		local before = GameController.getRunId()
		MenuController.play(mode)
		local deadline = os.clock() + 5
		while GameController.getRunId() == before and os.clock() < deadline do
			task.wait()
		end
		task.wait(0.1) -- let listeners (tutorial hint) react to the new run
		return describeState()
	elseif command == "leaderboard" then
		local action = ...
		if action == "open" then
			MenuController.openLeaderboard()
			task.wait(1) -- the server's answer
		elseif action == "close" then
			LeaderboardController.close()
		end
		return `open={LeaderboardController.isOpen()} menuOpen={MenuController.isOpen()}\n{LeaderboardController.describe()}`
	elseif command == "support" then
		local action = ...
		if action == "open" then
			MenuController.openSupport()
			task.wait(1) -- the server's answer
		elseif action == "close" then
			SupportController.close()
		end
		return `open={SupportController.isOpen()} menuOpen={MenuController.isOpen()}\n{SupportController.describe()}`
	elseif command == "queue" then
		-- The ranked queue screen: "open" opens it from the menu (joining the queue); "keep", "practice" and "close"
		-- press its buttons.
		local action = ...
		if action == "open" then
			MenuController.openRanked()
			task.wait(0.5)
		elseif action == "keep" or action == "practice" or action == "close" then
			QueueController.press(action)
			task.wait(0.5)
		end
		return QueueController.describe()
	elseif command == "pvp" then
		-- The PVP match on this screen; "again" or "menu" press the result panel's buttons.
		local action = ...
		if action == "again" or action == "menu" then
			PvpRunController.press(action)
			task.wait(0.5)
		end
		return PvpRunController.describe()
	elseif command == "coop" then
		local action, first, second = ...
		local me = Players.LocalPlayer
		if action == "open" then
			MenuController.openCoop()
			task.wait(0.5)
		elseif action == "close" then
			CoopController.close()
		elseif action == "people" then
			CoopController.pretendPeople(tonumber(first) or 0)
		elseif action == "invite" then
			local seconds = tonumber(second) or Config.COOP.INVITE_SECONDS
			CoopController.onInvited(tonumber(first) or 1, me.UserId, workspace:GetServerTimeNow() + seconds)
		elseif action == "result" then
			CoopController.onInviteResult(tonumber(second) or me.UserId, first)
		elseif action == "room" then
			CoopController.onRoom({
				id = 1,
				mode = "coop",
				you = 1,
				present = { true, first ~= "left" },
				userIds = { me.UserId, me.UserId },
			})
		elseif action == "noroom" then
			CoopController.onRoom(nil)
		elseif action == "busy" then
			me:SetAttribute("CoopBusy", if first == "none" then nil else first)
		elseif action == "press" then
			-- Results named after the id are fed in at once, before the server has time to answer.
			local userId = tonumber(first) or 0
			CoopController.invite(userId)
			for _, result in { select(3, ...) } do
				CoopController.onInviteResult(userId, result)
			end
		elseif action == "cancel" then
			CoopController.cancel()
		elseif action == "play" then
			-- Plays random moves of the player's own pieces at a human pace, as far as the tray allows.
			local played = 0
			for _ = 1, tonumber(first) or 1 do
				if not waitForTray() or GameController.getSession().isOver or not playOne(rng, true) then
					break
				end
				played += 1
				task.wait(MOVE_PACE_SECONDS)
			end
			return `played {played}\n{CoopRunController.describe()}\n{describeState()}`
		elseif action == "again" then
			GameController.restart()
		elseif action == "leave" then
			GameController.requestMenu()
		elseif action == "takeover" then
			CoopRunController.takeOver()
		elseif action == "rotate" then
			local turned = GameController.tryRotate(tonumber(first) or 1)
			task.wait(0.1)
			return `{if turned then "rotated" else "not rotated"} | {GameController.getRotationText()}\n{CoopRunController.describe()}`
		elseif action == "revive" then
			GameController.requestRevive()
			task.wait(0.3)
			return `{CoopRunController.describe()}\n{describeState()}`
		elseif action == "run" then
			return `{CoopRunController.describe()}\n{describeState()}`
		end
		if action ~= "press" then
			task.wait(0.1) -- let the view settle; a press is read at once, before the server's answer arrives
		end
		return `open={CoopController.isOpen()} menuOpen={MenuController.isOpen()} available={CoopController.isAvailable()}\n{CoopController.describe()}`
	elseif command == "flow" then
		local profile = GameController.getProfile()
		local keys = GamepadController.getStats()
		return string.format(
			"menuOpen=%s runMode=%s runId=%d hint=%s profile=%s keys: mode=%s context=%s slot=%d keyDrag=%s target=%s",
			tostring(MenuController.isOpen()),
			GameController.getRunMode(),
			GameController.getRunId(),
			tostring(TutorialController.isHintVisible()),
			if profile
				then `best={profile.best},games={profile.gamesPlayed},tutorialDone={profile.tutorialDone}`
				else "none",
			keys.inputMode,
			tostring(keys.contextEnabled),
			keys.selectedSlot,
			tostring(keys.keyDrag),
			keys.target
		)
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
		local toX, toY = pointerFor(views, piece, x, y, mode == "touch")
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
	elseif command == "touchdrop" then
		local slot, x, y = ...
		local views = GameController.getViews()
		local piece = session.tray[slot]
		if not views or not piece or not DragController.pick(slot, true) then
			return "no piece in that slot"
		end
		local pointerX, pointerY = pointerFor(views, piece, x, y, true)
		DragController.movePointer(Vector2.new(pointerX, pointerY))
		local placed = DragController.drop()
		return string.format(
			"placed=%s finger=%.1f screenBottom=%.1f\n%s",
			tostring(placed),
			pointerY,
			DragController.getScreenBottom(),
			describeState()
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
