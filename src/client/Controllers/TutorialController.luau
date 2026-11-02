--!strict
-- First-time tutorial on top of a tutorial run: shows the card, the hand and the dotted arrow from the hinted
-- tray slot to the suggested move until the player makes a move, then explains line clears once. Skip ends the
-- tutorial: the server counts it as done and a normal run starts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local GameController = require("./GameController")
local Theme = require("../Views/Theme")
local TutorialView = require("../Views/TutorialView")

local SIZE = Config.GRID_SIZE

local TutorialController = {}

local view: TutorialView.TutorialView? = nil
local tipShown = false

local function getViews(): GameController.Views
	return GameController.getViews() :: GameController.Views
end

-- What the card says, for the device in use.
local function copy(): (string, string)
	local last = UserInputService:GetLastInputType()
	if string.find(last.Name, "Gamepad", 1, true) then
		return "Pick up the block", "A · D-pad · A"
	elseif last == Enum.UserInputType.Keyboard then
		return "Pick up the block", "Space · arrows · Space"
	end
	return "Drag the block", "to fill the row!"
end

local function hudArea(): (Vector2, Vector2)
	local area = getViews().gui.hudArea
	return area.AbsolutePosition, area.AbsoluteSize
end

local function hintSource(): Vector2
	return getViews().tray:center(Tutorial.HINT.slot)
end

-- The screen rectangle of each cell the hinted piece would fill.
local function hintTargets(): { TutorialView.Rect }
	local grid = getViews().board.grid
	local cell = grid.AbsoluteSize.X / SIZE
	local hint = Tutorial.HINT
	local piece = Tutorial.tray()[hint.slot]
	local pad = cell * 0.04
	local rects = {}
	for _, offset in piece.cells do
		table.insert(rects, {
			x = grid.AbsolutePosition.X + (hint.x + offset.x) * cell + pad,
			y = grid.AbsolutePosition.Y + (hint.y + offset.y) * cell + pad,
			width = cell - 2 * pad,
			height = cell - 2 * pad,
		})
	end
	return rects
end

-- Center of where the hinted piece lands.
local function hintTarget(): Vector2
	local grid = getViews().board.grid
	local cell = grid.AbsoluteSize.X / SIZE
	local hint = Tutorial.HINT
	local piece = Tutorial.tray()[hint.slot]
	return grid.AbsolutePosition + Vector2.new((hint.x + piece.width / 2) * cell, (hint.y + piece.height / 2) * cell)
end

function TutorialController.isHintVisible(): boolean
	return view ~= nil and view:isHintVisible()
end

-- Puts the screen back to normal play (score bar, tray colors, no Skip).
local function endHint(tutorialView: TutorialView.TutorialView)
	tutorialView:hideHint()
	tutorialView:setSkipVisible(false)
	local views = getViews()
	views.hud:setBarVisible(true)
	views.tray:setHint(nil)
end

function TutorialController.start(_self: any)
	local views = GameController.getViews()
	while not views do
		task.wait()
		views = GameController.getViews()
	end
	local tutorialView = TutorialView.new(views.gui.dragLayer, function()
		Net.SkipTutorial:FireServer()
		GameController.restart()
	end)
	view = tutorialView

	GameController.onSessionReplaced(function()
		if GameController.getRunMode() == "tutorial" and GameController.getSession().moveCount == 0 then
			tipShown = false
			tutorialView:hideTip()
			views.hud:setBarVisible(false) -- the card takes the score bar's place
			views.tray:setHint(Tutorial.HINT.slot)
			tutorialView:setSkipVisible(true)
			tutorialView:showHint({
				copy = copy,
				from = hintSource,
				to = hintTarget,
				targets = hintTargets,
				area = hudArea,
			})
		else
			endHint(tutorialView)
		end
	end)

	GameController.onMovePlayed(function(result)
		endHint(tutorialView)
		local cleared = #result.clearedRows + #result.clearedCols > 0
		if GameController.getRunMode() == "tutorial" and cleared and not tipShown then
			tipShown = true
			tutorialView:showTip(
				"Nice!",
				"Full rows and columns clear. Keep the board open!",
				hudArea,
				Theme.Motion.Tip
			)
		end
	end)

	GameController.onMenuRequested(function()
		endHint(tutorialView)
		tutorialView:hideTip()
	end)
end

return TutorialController
