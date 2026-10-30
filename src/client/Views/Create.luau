--!strict
-- Builds an instance: sets properties, adds children, and sets Parent last so the tree is laid out once.
-- Properties are applied in no particular order; set order-dependent ones (IgnoreGuiInset before
-- ScreenInsets) separately.

local function create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className :: any)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

return create
