--!nocheck
--// cracked by numan

local Container = script.Parent
local index

local function build()
	local map = {}
	for _, descendant in Container:GetDescendants() do
		if descendant:IsA("ModuleScript") and descendant ~= script then
			if map[descendant.Name] then
				error("Duplicate Eclipse module name: " .. descendant.Name, 0)
			end

			map[descendant.Name] = descendant
		end
	end

	return map
end

local function resolve(target)
	if type(target) ~= "string" then
		assert(typeof(target) == "Instance" and target:IsA("ModuleScript") and target:IsDescendantOf(Container), "Eclipse requires a bundled ModuleScript")
		return require(target)
	end

	if not index then
		index = build()
	end

	local module = index[target]
	if not module then
		index = build()
		module = index[target]
	end

	if not module then
		error("Unknown Eclipse module: " .. tostring(target), 0)
	end

	return require(module)
end

return resolve
