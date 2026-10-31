--!strict
-- First-time tutorial on top of a tutorial run: points from the tray to the suggested move until the player
-- makes a move, then explains line clears once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local GameController = require("./GameController")
local Theme = require("../Views/Theme")
local TutorialView = require("../Views/TutorialView")

local SIZE = Config.GRID_SIZE
local TIP = "Full rows and columns clear. Keep the board open!"
local BANNER_MARGIN = 8

local TutorialController = {}

local view: TutorialView.TutorialView? = nil
local tipShown = false

local function getViews(): GameController.Views
	return GameController.getViews() :: GameController.Views
end

local function instructionText(): string
	local last = UserInputService:GetLastInputType()
	if string.find(last.Name, "Gamepad", 1, true) then
		return "Pick up the piece with A, move it with the D-pad, place it with A"
	elseif last == Enum.UserInputType.Keyboard then
		return "Pick up the piece with Space, move it with the arrow keys, place it with Space"
	end
	return "Drag the piece into the gap"
end

-- Top middle of the board, inside it, and the width left by the margins: the tutorial's gap is in the bottom
-- row, so this never covers it.
local function bannerArea(): (Vector2, number)
	local frame = getViews().board.frame
	local position, size = frame.AbsolutePosition, frame.AbsoluteSize
	return Vector2.new(position.X + size.X / 2, position.Y + BANNER_MARGIN), size.X - 2 * BANNER_MARGIN
end

local function hintSource(): Vector2
	return getViews().tray:center(Tutorial.HINT.slot)
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

function TutorialController.start(_self: any)
	local views = GameController.getViews()
	while not views do
		task.wait()
		views = GameController.getViews()
	end
	local tutorialView = TutorialView.new(views.gui.dragLayer)
	view = tutorialView

	GameController.onSessionReplaced(function()
		if GameController.getRunMode() == "tutorial" and GameController.getSession().moveCount == 0 then
			tipShown = false
			tutorialView:showHint(instructionText, hintSource, hintTarget, bannerArea)
		else
			tutorialView:hideHint()
		end
	end)

	GameController.onMovePlayed(function(result)
		tutorialView:hideHint()
		local cleared = #result.clearedRows + #result.clearedCols > 0
		if GameController.getRunMode() == "tutorial" and cleared and not tipShown then
			tipShown = true
			local at, width = bannerArea()
			tutorialView:showTip(TIP, at, width, Theme.Motion.Tip)
		end
	end)

	GameController.onMenuRequested(function()
		tutorialView:hideHint()
		tutorialView:hideTip()
	end)
end

return TutorialController
