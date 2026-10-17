--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Storage = {}
local ROOT = "Eclipse Animator Saves"
local names = {
	"EclipseAnimator_Saves",
	"EclipseAnimator_Backups",
	"EclipseEffectStorage",
	"EclipseEventRecovery",
	"EclipsePhysicsForces",
	"EclipseArmatures",
	"_EclipseEventRuntime",
	"EclipseAnimator_Live",
}

local function folder(parent, name)
	for _, child in parent:GetChildren() do
		if child.Name == name and child:IsA("Folder") then
			return child
		end
	end
end

function Storage.migrate(parent)
	parent = parent or game:GetService("ServerStorage")
	local root = folder(parent, ROOT)
	for _, name in names do
		for _, legacy in parent:GetChildren() do
			if legacy.Name == name and legacy:IsA("Folder") then
				if not root then
					root = Instance.new("Folder")
					root.Name = ROOT
					root.Parent = parent
				end

				local current = folder(root, name)
				if current then
					for _, child in legacy:GetChildren() do
						child.Parent = current
					end

					legacy:Destroy()
				else
					legacy.Parent = root
				end
			end
		end
	end

	return root
end

local cache = setmetatable({}, { __mode = "k" })

function Storage.get(name, create, parent)
	parent = parent or game:GetService("ServerStorage")
	local known = cache[parent]
	local hit = known and known[name]
	if
		hit
		and hit.Parent
		and hit.Parent.Parent == parent
		and hit.Parent.Name == ROOT
		and hit.Name == name
		and not folder(parent, name)
	then
		return hit
	end

	local root = Storage.migrate(parent)
	if not root and create then
		root = Instance.new("Folder")
		root.Name = ROOT
		root.Parent = parent
	end

	if not root then
		return nil
	end

	local result = folder(root, name)
	if not result and create then
		result = Instance.new("Folder")
		result.Name = name
		result.Parent = root
	end

	if result then
		known = known or {}
		cache[parent] = known
		known[name] = result
	end

	return result
end

return Storage
