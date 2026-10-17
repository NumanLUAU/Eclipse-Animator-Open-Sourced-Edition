--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Codec = require("SceneCodec")
local Paths = require("Paths")
local History = require("History")
local Bones = {}

function Bones.apply(refs, entry, packet, changed)
	assert(entry and not entry.camera, "Choose a paired rig to sync bones.")
	assert(typeof(packet.bones) == "table" and #packet.bones <= 10000, "Invalid Blender bone list.")
	local raw, rig = refs.State.Timeline:GetState(), entry.rig
	local known, rest, names, created, defaults, existing = {}, {}, {}, {}, {}, {}
	local additions = {}
	local addedCount = 0
	local data = Codec.capture(refs)
	for _, row in data.rigs do
		if row.id == entry.id then
			for _, track in row.tracks do
				rest[track.id] = Codec.unpack(track.rest)
			end
		end
	end

	for name, id in packet.mapped or {} do
		local motor = assert(entry.byId[id], "Blender mapping changed; pair the rig again.")
		known[name] = { part = motor.Part1, world = rest[id] }
	end

	for _, object in rig:GetDescendants() do
		if object:IsA("BasePart") or object:IsA("Bone") then
			names[object.Name] = true
			local source = object:GetAttribute("EclipseBlenderSource")
			if source then
				existing[source] = object
			end
		end
	end

	local validated = {}
	for _, spec in packet.bones do
		assert(
			typeof(spec.name) == "string"
				and #spec.name > 0
				and #spec.name <= 100
				and (
					not names[spec.name]
					or existing[spec.source] and existing[spec.source].Name == spec.name
				),
			"A bone or part already uses this name: " .. tostring(spec.name)
		)
		assert(typeof(spec.source) == "string" and #spec.source > 0, "Missing Blender bone name.")
		assert(not validated[spec.source], "Duplicate Blender bone: " .. spec.source)
		assert(
			not spec.parent or known[spec.parent] or validated[spec.parent],
			"Missing parent for " .. spec.name
		)
		validated[spec.source], names[spec.name] = Codec.unpack(spec.world), true
	end

	local function rebuild()
		refs.State.Timeline:InvalidateMotorListCache()
		if refs.State.Rig and refs.State.Rig.BuildRigHierarchy then
			refs.State.Rig:BuildRigHierarchy(refs.State.currentRig)
		end

		refs.State.currentProjectSaved = false
	end

	local ok, err = xpcall(function()
		for _, spec in packet.bones do
			if existing[spec.source] then
				local part = existing[spec.source]
				known[spec.source] = { part = part, world = validated[spec.source] }
				additions[Paths.of(part, rig)] = spec.source
				continue
			end

			local parent = spec.parent and known[spec.parent]
			local part0 = parent and parent.part or rig.PrimaryPart
			assert(part0, "Set a PrimaryPart before syncing a root bone.")
			local world = validated[spec.source]
			local parentWorld = parent and parent.world or part0.CFrame
			local part, motor
			if part0:IsA("Bone") then
				part = Instance.new("Bone")
				part.Name, part.CFrame = spec.name, parentWorld:ToObjectSpace(world)
				part.Parent = part0
				table.insert(created, { object = part, parent = part0 })
			else
				part = Instance.new("Part")
				part.Name, part.Size, part.Transparency = spec.name, Vector3.new(0.2, 0.2, 0.2), 1
				part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.Massless =
					true, false, false, false, true
				part.CFrame, part.Parent = part0.CFrame * parentWorld:ToObjectSpace(world), rig
				table.insert(created, { object = part, parent = rig })
				motor = Instance.new("Motor6D")
				motor.Name, motor.Part0, motor.Part1, motor.C0 =
					spec.name, part0, part, parentWorld:ToObjectSpace(world)
				motor.Parent = part0
				table.insert(created, { object = motor, parent = part0 })
				raw.DefaultPose[motor], raw.ParentingDefaults[motor] = motor.C0, true
				defaults[motor] = motor.C0
			end

			part:SetAttribute("EclipseBlenderSource", spec.source)
			addedCount += 1
			known[spec.source] = { part = part, world = world }
			additions[Paths.of(part, rig)] = spec.source
		end

		rebuild()
	end, debug.traceback)
	if not ok then
		for index = #created, 1, -1 do
			created[index].object:Destroy()
		end

		for motor in defaults do
			raw.DefaultPose[motor], raw.ParentingDefaults[motor] = nil, nil
		end

		error(err, 0)
	end

	if #created > 0 then
		History.record(function()
			if changed then
				changed()
			end

			for index = #created, 1, -1 do
				created[index].object.Parent = nil
			end

			rebuild()
		end, function()
			if changed then
				changed()
			end

			for _, item in created do
				item.object.Parent = item.parent
			end

			rebuild()
		end, "Sync Blender bones")
	end

	return addedCount, additions
end

return Bones
