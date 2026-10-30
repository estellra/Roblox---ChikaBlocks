--!strict
-- Client entry point: waits for the game to load, sets up Roblox's core UI, then requires every ModuleScript
-- in Controllers/, runs init() on all of them, then start(). init() must not yield; start() may.
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- The game is UI only: no player list (we'll have our own leaderboards), no movement controls.
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
GuiService.TouchControlsEnabled = false

type Controller = {
	init: ((self: Controller) -> ())?,
	start: ((self: Controller) -> ())?,
}

local controllers: { [string]: Controller } = {}
for _, module in script:WaitForChild("Controllers"):GetChildren() do
	if module:IsA("ModuleScript") then
		controllers[module.Name] = (require :: any)(module)
	end
end

for name, controller in controllers do
	if controller.init then
		debug.setmemorycategory(name)
		controller:init()
		debug.resetmemorycategory()
	end
end

for name, controller in controllers do
	if controller.start then
		task.spawn(function()
			debug.setmemorycategory(name)
			controller:start()
		end)
	end
end
