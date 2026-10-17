--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Binding = require("Binding")
local Plan = {}

function Plan.build(data, rig)
	local byName, sourceByName, entries = {}, {}, {}
	local motorByPart, restCache, visiting = {}, {}, {}
	local descendants = require("RigTraversal").rigDescendants(rig)
	for _, item in descendants do
		if item:IsA("JointInstance") and item.Part0 and item.Part1 then
			local existing = motorByPart[item.Part1]
			if not existing or item:IsA("Motor6D") and not existing:IsA("Motor6D") then
				motorByPart[item.Part1] = item
			end
		end
	end

	local function restC0(motor)
		local value = motor:GetAttribute("EclipseAnimatorDefaultC0")
		return typeof(value) == "CFrame" and value or motor.C0
	end

	local function restWorld(target)
		if restCache[target] then
			return restCache[target]
		end

		assert(not visiting[target], "Cyclic native rig joints")
		visiting[target] = true
		local frame
		if target:IsA("Bone") then
			frame = restWorld(target.Parent) * target.CFrame
		elseif target:IsA("JointInstance") then
			frame = restWorld(target.Part0) * restC0(target)
		elseif motorByPart[target] then
			local motor = motorByPart[target]
			frame = restWorld(motor.Part0) * restC0(motor) * motor.C1:Inverse()
		else
			frame = target.CFrame
		end

		visiting[target] = nil
		restCache[target] = frame
		return frame
	end

	local function candidate(name, target, priority)
		local group = byName[name]
		if not group or group.priority < priority then
			group = { priority = priority, targets = {} }
			byName[name] = group
		end

		if group.priority == priority then
			table.insert(group.targets, target)
		end
	end

	for _, target in descendants do
		if target:GetAttribute("EclipseArmatureSkinningHelper") then
			continue
		end

		local cursor, generated = target.Parent, false
		while cursor and cursor ~= rig do
			if cursor:GetAttribute("EclipseArmature") == true then
				generated = true
				break
			end

			cursor = cursor.Parent
		end

		if generated then
			continue
		end

		if target:IsA("Bone") and target:GetAttribute("EclipseR6Control") == nil then
			candidate(target.Name, target, 3)
		elseif target:IsA("JointInstance") and target.Part0 and target.Part1
			and motorByPart[target.Part1] == target then
			candidate(target.Part1.Name, target, 2)
		elseif target:IsA("BasePart") and not motorByPart[target] then
			candidate(target.Name, target, 2)
		end
	end

	for _, bone in data.bones do
		assert(
			typeof(bone.id) == "string" and not entries[bone.id],
			"Missing or duplicate armature bone identity"
		)
		entries[bone.id] = { data = bone }
		sourceByName[bone.name] = sourceByName[bone.name] or {}
		table.insert(sourceByName[bone.name], bone)
		Binding.matrix(bone.rest_matrix)
		Binding.matrix(bone.pose_matrix)
	end

	local geometryAncestors = {}
	for _, bone in data.bones do
		if bone.skinning == true or bone.geometry_binding == true then
			local cursor, seen = bone, {}
			while cursor and not seen[cursor.id] do
				seen[cursor.id] = true
				geometryAncestors[cursor.id] = true
				cursor = cursor.parent and entries[cursor.parent] and entries[cursor.parent].data
			end
		end
	end

	local function selectSource(name, sources)
		local candidates = {}
		for _, source in sources do
			if source.skinning == true or source.geometry_binding == true then
				table.insert(candidates, source)
			end
		end

		if #candidates == 0 then
			for _, source in sources do
				if geometryAncestors[source.id] then
					table.insert(candidates, source)
				end
			end
		end

		if #candidates == 0 then
			candidates = sources
		end

		local selected = #candidates == 1 and candidates[1] or nil
		if not selected and type(data.primary_armature) == "string" then
			for _, source in candidates do
				if source.armature == data.primary_armature then
					assert(not selected, "Ambiguous mesh bone in selected armature: " .. name)
					selected = source
				end
			end
		end

		assert(
			selected,
			"Ambiguous mesh bone: "
				.. name
				.. ". Select the armature that drives this rig and export its JSON again."
		)
		return selected
	end

	local pairs, deferred, claimed = {}, {}, {}
	local geometryFrames = false
	local function fitWorld(source, target)
		if geometryFrames and source.geometry_binding == true and target:IsA("JointInstance") then
			return restWorld(target.Part1)
		end
		return restWorld(target)
	end
	local function fitPairs()
		for _, pair in pairs do
			pair.target = fitWorld(pair.data, pair.object)
		end
		return Binding.fit(pairs)
	end

	local function attach(source, target)
		local entry = entries[source.id]
		entry.targets = entry.targets or {}
		table.insert(entry.targets, target)
		claimed[source.id] = true
	end

	local function bind(source, target)
		attach(source, target)
		table.insert(
			pairs,
			{ source = Binding.matrix(source.rest_matrix), target = restWorld(target), data = source, object = target }
		)
	end

	for name, group in byName do
		local sources = sourceByName[name]
		if not sources then
			continue
		end

		local selected = selectSource(name, sources)
		local repeated = false
		if group.priority ~= 3 then
			for candidateName, candidates in sourceByName do
				local suffix = string.sub(candidateName, #name + 1)
				if string.sub(candidateName, 1, #name) == name
					and string.match(suffix, "^%.%d+$") then
					for _, candidate in candidates do
						if candidate.armature == selected.armature then repeated = true end
					end
				end
			end
		end
		if (#group.targets == 1 and not repeated) or group.priority == 3 then
			for _, target in group.targets do
				bind(selected, target)
			end
		else
			table.insert(deferred, { name = name, group = group, selected = selected })
		end
	end

	local ok, fit, scale, errorDistance = pcall(fitPairs)
	if not ok then
		geometryFrames = true
		fit, scale, errorDistance = fitPairs()
	end
	local tolerance = math.max(0.01, scale * 0.001, errorDistance * 4)
	table.sort(deferred, function(a, b)
		return a.name < b.name
	end)
	for _, item in deferred do
		local candidates = { item.selected }
		for name, sources in sourceByName do
			local suffix = string.sub(name, #item.name + 1)
			if
				string.sub(name, 1, #item.name) == item.name
				and (string.match(suffix, "^%d+%.?%d*$") or string.match(suffix, "^%.%d+$"))
			then
				local eligible = {}
				for _, source in sources do
					if source.armature == item.selected.armature and not claimed[source.id] then
						table.insert(eligible, source)
					end
				end

				if #eligible == 1 then
					table.insert(candidates, eligible[1])
				end
			end
		end

		for _, target in item.group.targets do
			local nearest, distance, second = nil, math.huge, math.huge
			if #item.group.targets == 1 then
				local position = fit * (Binding.matrix(item.selected.rest_matrix).Position * scale)
				local delta = (position - fitWorld(item.selected, target).Position).Magnitude
				if delta <= tolerance then
					nearest, distance = item.selected, delta
				end
			end
			for _, source in candidates do
				if nearest == item.selected and #item.group.targets == 1 and distance <= tolerance then break end
				if not claimed[source.id] or #candidates == 1 then
					local position = fit * (Binding.matrix(source.rest_matrix).Position * scale)
					local delta = (position - fitWorld(source, target).Position).Magnitude
					if delta < distance then
						nearest, second, distance = source, distance, delta
					else
						second = math.min(second, delta)
					end
				end
			end

			assert(
				nearest and distance <= tolerance and second - distance > 0.0001,
				"Cannot uniquely match repeated rig part: "
					.. item.name
					.. ". The exported rest positions must match this rig."
			)
			bind(nearest, target)
		end
	end

	const follow, objects = Binding.followers(data)
	local unmatched = {}
	for name, group in byName do
		if sourceByName[name] then
			continue
		end

		if not objects[name] then
			for _, target in group.targets do
				table.insert(unmatched, target)
			end

			continue
		end

		const boneId = follow(name)
		const source = boneId and entries[boneId] and entries[boneId].data
		if not source then
			continue
		end

		for _, target in group.targets do
			const carrier = target:IsA("JointInstance") and target.Part0
			if not (carrier and follow(carrier.Name) == boneId) then
				restWorld(target)
				attach(source, target)
			end
		end
	end

	local matches, uses = {}, {}
	for _, target in unmatched do
		local nearest, distance, second = nil, math.huge, math.huge
		for _, source in data.bones do
			if source.geometry_binding == true and not claimed[source.id] then
				local position = fit * (Binding.matrix(source.rest_matrix).Position * scale)
				local delta = (position - fitWorld(source, target).Position).Magnitude
				if delta < distance then
					nearest, second, distance = source, distance, delta
				else
					second = math.min(second, delta)
				end
			end
		end

		if nearest and distance <= tolerance and second - distance > 0.0001 then
			matches[target] = nearest
			uses[nearest.id] = (uses[nearest.id] or 0) + 1
		end
	end

	for target, source in matches do
		if uses[source.id] == 1 then
			bind(source, target)
		end
	end

	fit, scale, errorDistance = fitPairs()
	for _, entry in entries do
		local parent, seen = entry.data.parent, { [entry.data.id] = true }
		while parent do
			assert(entries[parent] and not seen[parent], "Invalid exported bone hierarchy")
			seen[parent] = true
			parent = entries[parent].data.parent
		end
	end

	return {
		entries = entries,
		frame = fit,
		scale = scale,
		errorDistance = errorDistance,
		matched = #pairs,
		restWorlds = restCache,
	}
end

return Plan
