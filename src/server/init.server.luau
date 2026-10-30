--!strict
-- Server entry point: requires every ModuleScript in Services/, runs init() on all of them, then start().
-- init() must not yield; start() may.

type Service = {
	init: ((self: Service) -> ())?,
	start: ((self: Service) -> ())?,
}

local services: { [string]: Service } = {}
local servicesFolder = script:FindFirstChild("Services")
if servicesFolder then
	for _, module in servicesFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			services[module.Name] = (require :: any)(module)
		end
	end
end

for name, service in services do
	if service.init then
		debug.setmemorycategory(name)
		service:init()
		debug.resetmemorycategory()
	end
end

for name, service in services do
	if service.start then
		task.spawn(function()
			debug.setmemorycategory(name)
			service:start()
		end)
	end
end

print("[ChikaBlock] Server ready")
