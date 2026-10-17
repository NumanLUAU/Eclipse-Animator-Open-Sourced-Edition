--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tree = {}

function Tree.descendants(root, budget)
	local result, stack = {}, {}
	if root then
		table.insert(stack, root)
	end

	while #stack > 0 do
		local parent = table.remove(stack)
		if budget then
			budget()
		end
		for index, child in parent:GetChildren() do
			if budget and index % 64 == 0 then
				budget()
			end
			if
				child.Name == "AnimSaves"
				or child:IsA("KeyframeSequence")
				or child:IsA("Keyframe")
				or child:IsA("Pose")
				or child:IsA("LuaSourceContainer")
			then
				continue
			end

			table.insert(result, child)
			table.insert(stack, child)
		end
	end

	return result
end

function Tree.rigDescendants(root)
	if
		not root
		or root.Parent == game
		or root:IsA("Terrain")
		or not (root:IsA("Model") or root:IsA("BasePart") or root:IsA("Attachment"))
	then
		return {}
	end

	return Tree.descendants(root)
end

local boneFolders = setmetatable({}, { __mode = "kv" })

function Tree.bonesFolder(rig, camera)
	if not rig or not camera then
		return nil
	end

	local name = rig.Name .. "Bones"

	local function owns(folder)
		if
			not folder
			or folder.Parent ~= camera
			or not folder:IsA("Folder")
			or not folder:GetAttribute("EclipseAnimator_BonesFolder")
		then
			return false
		end

		local source = folder:FindFirstChild("EclipseSourceRig")
		return source and source:IsA("ObjectValue") and source.Value == rig
	end

	local folder = boneFolders[rig]
	if not owns(folder) then
		folder = camera:FindFirstChild(name)
		if not owns(folder) then
			folder = nil
			for _, candidate in camera:GetChildren() do
				if owns(candidate) then
					folder = candidate
					break
				end
			end
		end

		if not folder then
			local legacy = camera:FindFirstChild(name)
			if
				legacy
				and legacy:IsA("Folder")
				and legacy:GetAttribute("EclipseAnimator_BonesFolder")
				and not legacy:FindFirstChild("EclipseSourceRig")
			then
				folder = legacy
			end
		end

		boneFolders[rig] = folder
	end

	if folder and folder.Name ~= name then
		folder.Name = name
	end

	return folder
end

local function pathKey(names)
	local out = {}
	for _, name in names do
		out[#out + 1] = #name .. ":" .. name
	end

	return "@pose/" .. table.concat(out, "/")
end

function Tree.poseKey(pose)
	local names = {}
	while pose and pose:IsA("Pose") do
		table.insert(names, 1, pose.Name)
		pose = pose.Parent
	end

	return pathKey(names)
end

local function passiveMotors(rig, objects)
	objects = objects or Tree.rigDescendants(rig)
	local outgoing, incoming, named = {}, {}, {}
	for _, motor in objects do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a, b = motor.Part0, motor.Part1
			outgoing[a] = outgoing[a] or {}
			incoming[b] = incoming[b] or {}
			table.insert(outgoing[a], motor)
			table.insert(incoming[b], motor)
		end

		if motor:IsA("BasePart") then
			local name = motor.Name:lower()
			if named[name] == nil then
				named[name] = motor
			else
				named[name] = false
			end
		end
	end

	local root = rig:IsA("Model") and rig.PrimaryPart or nil
	if
		not root
		or (incoming[root] and root ~= named.humanoidrootpart and root ~= named.rootcontroller)
		or not outgoing[root]
	then
		root = named.humanoidrootpart or named.rootcontroller
		if root and not outgoing[root] then
			root = nil
		end

		local seen = {}
		while
			root
			and root ~= named.humanoidrootpart
			and incoming[root]
			and #incoming[root] == 1
			and not seen[root]
		do
			seen[root] = true
			root = incoming[root][1].Part0
		end
	end

	if not root then
		for part in outgoing do
			if not incoming[part] then
				if root then
					return {}
				end

				root = part
			end
		end
	end

	if not root then
		return {}
	end

	local reached, queue = { [root] = true }, { root }
	local index = 1
	while index <= #queue do
		local part = queue[index]
		index += 1
		for _, motor in outgoing[part] or {} do
			if not reached[motor.Part1] then
				reached[motor.Part1] = true
				table.insert(queue, motor.Part1)
			end
		end
	end

	local passive = {}
	index = 1
	while index <= #queue do
		local part = queue[index]
		index += 1
		for _, motor in outgoing[part] or {} do
			if not reached[motor.Part1] then
				reached[motor.Part1] = true
				table.insert(queue, motor.Part1)
			end
		end

		for _, motor in incoming[part] or {} do
			local source = motor.Part0

			if not reached[source] then
				passive[motor] = true
				reached[source] = true
				table.insert(queue, source)
			end
		end
	end

	return passive
end

local passiveCache = setmetatable({}, { __mode = "k" })

function Tree.passiveMotors(rig, objects)
	if objects or not rig then return passiveMotors(rig, objects) end
	local cached = passiveCache[rig]
	if cached and not cached.dirty then return cached.value end
	if cached then
		for _, connection in cached.connections do connection:Disconnect() end
	end
	local descendants = Tree.rigDescendants(rig)
	cached = { value = passiveMotors(rig, descendants), connections = {} }
	local function dirty() cached.dirty = true end
	local function watch(object, property)
		table.insert(cached.connections, object:GetPropertyChangedSignal(property):Connect(dirty))
	end
	for _, object in descendants do
		watch(object, "Name")
		if object:IsA("Motor6D") then
			watch(object, "Part0")
			watch(object, "Part1")
		end
	end
	if rig:IsA("Model") then watch(rig, "PrimaryPart") end
	table.insert(cached.connections, rig.DescendantAdded:Connect(dirty))
	table.insert(cached.connections, rig.DescendantRemoving:Connect(dirty))
	table.insert(cached.connections, rig.Destroying:Connect(function()
		for _, connection in cached.connections do connection:Disconnect() end
		passiveCache[rig] = nil
	end))
	passiveCache[rig] = cached
	return cached.value
end

function Tree.jointMap(rig, requested)
	local incoming, tracks = {}, {}
	local passive = Tree.passiveMotors(rig)
	for _, v in Tree.rigDescendants(rig) do
		if passive[v] then
			continue
		end

		if v:IsA("Motor6D") and v.Part0 and v.Part1 then
			incoming[v.Part1] = v
			if requested ~= "Bone" then
				tracks[#tracks + 1] = v
			end
		elseif
			v:IsA("Bone")
			and not v:GetAttribute("EclipseArmatureSkinningHelper")
			and requested ~= "Motor6D"
		then
			tracks[#tracks + 1] = v
		end
	end

	local map, ambiguous, keys = {}, {}, {}

	local function add(key, value)
		if ambiguous[key] then
			return
		end

		if map[key] and map[key] ~= value then
			map[key] = nil
			ambiguous[key] = true
		else
			map[key] = value
		end
	end

	for _, v in tracks do
		local part = v:IsA("Motor6D") and v.Part1 or v
		local names, seen = {}, {}
		local node = part
		while node and not seen[node] do
			seen[node] = true
			table.insert(names, 1, node.Name)
			if node:IsA("Bone") then
				node = node.Parent
				if node and not (node:IsA("Bone") or node:IsA("BasePart")) then
					node = nil
				end
			else
				local parent = incoming[node]
				node = parent and parent.Part0
			end
		end

		if not node then
			local key = pathKey(names)
			keys[v] = key
			add(key, v)
		end

		add(part.Name, v)
	end

	return map, keys
end

function Tree.resolvePose(map, pose)
	return map[Tree.poseKey(pose)] or map[pose.Name]
end

return Tree
