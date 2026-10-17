--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local Parenting = require("Parenting")
local LimbIK = require("LimbIK")
local Controls = require("R6Controls")
local Properties = require("Properties")
local Modes = {}
local copyTargets = setmetatable({}, { __mode = "k" })
Modes.Fields = {
	"Parented",
	"WorldCFrame",
	"IK",
	"IKTarget",
	"IKPole",
	"IKBaseC0",
	"IKBaseWorld",
	"IKAnchor",
	"IKRigWorld",
	"IKRoot",
	"IKPoleFollowsTarget",
	"IKRestoreParented",
	"HS",
	"HSRestoreParented",
	"HSRotation",
	"HSLocalRotation",
	"HeadFollow",
}

local function sourceRig(motor)
	if not motor then
		return nil
	end

	local rigs = State.getAllRigs and State.getAllRigs() or {}
	if Properties.is(motor) and table.find(rigs, motor.Rig) then
		return motor.Rig
	end

	local function owner(part)
		if typeof(part) ~= "Instance" then
			return nil
		end

		for _, rig in rigs do
			if rig.Parent and (part == rig or part:IsDescendantOf(rig)) then
				return rig
			end
		end
	end

	local rig = owner(motor.Part1)
	if rig then
		return rig
	end

	local raw = State.Timeline and State.Timeline:GetState()
	local seen = {}
	while motor and not seen[motor] do
		seen[motor] = true
		rig = owner(motor) or owner(motor.Part0)
		if rig then
			return rig
		end

		motor = raw and raw.MotorByPart and raw.MotorByPart[motor.Part0]
	end
end

Modes.sourceRig = sourceRig

function Modes.capture(key, metadata)
	if Properties.is(key.Motor) then
		return metadata
	end

	local raw = State.Timeline:GetState()

	if typeof(metadata.IK) ~= "boolean" then
		metadata.IK = LimbIK.isEnabled(key.Motor, key.Time)
	end

	metadata.Parented = Parenting.keyIsParented(key.Motor, key, raw.ParentingDefaults[key.Motor])
	if metadata.IK and (not metadata.IKTarget or not metadata.IKPole) then
		local rig = sourceRig(key.Motor)
		local entry = rig and LimbIK.getRig(rig)
		local chain = entry and entry.owners[key.Motor]
		if chain then
			for field, value in LimbIK.keyStateAt(chain, key.Time) do
				if metadata[field] == nil then
					metadata[field] = value
				end
			end
		end
	end

	if metadata.Parented then
		metadata.WorldCFrame = nil
	end

	return metadata
end

function Modes.merge(target, source)
	for _, field in Modes.Fields do
		target[field] = source[field]
	end
end

function Modes.appendDependencies(clip, baseFrame, metadataForKey)
	local timeline, seen, initial = State.Timeline, {}, #clip
	local raw = timeline:GetState()
	for _, item in clip do
		seen[item.motor] = seen[item.motor] or {}
		seen[item.motor][item.offsetFrame] = true
	end

	local function add(motor, frame, chain)
		local offset = frame - baseFrame
		seen[motor] = seen[motor] or {}
		if seen[motor][offset] then
			return
		end

		seen[motor][offset] = true
		local bucket, time = raw.Keyframes[motor] or {}, frame / raw.FPS
		local source = bucket[frame]
		if not source then
			local previous = Parenting.bounds(bucket, time)
			source = {
				Motor = motor,
				Part = motor.Part1,
				Frame = frame,
				Time = time,
				C0 = timeline:EvaluateMotorC0(motor, time),
				Parented = Parenting.keyIsParented(motor, previous, raw.ParentingDefaults[motor]),
			}
			if motor == chain.owner then
				for field, value in LimbIK.keyStateAt(chain, time) do
					source[field] = value
				end
			end
		end

		local metadata = metadataForKey(source)
		metadata.KeyGroups = nil
		table.insert(clip, {
			motor = motor,
			part = motor.Part1,
			c0 = source.C0,
			worldCFrame = metadata.WorldCFrame,
			offsetFrame = offset,
			sanitizeName = source.SanitizeName,
			metadata = metadata,
			modeDependency = true,
		})
	end

	for i = 1, initial do
		local item = clip[i]
		if Properties.is(item.motor) or item.channelOnly then
			continue
		end

		local rig = sourceRig(item.motor)
		local entry = rig and LimbIK.getRig(rig)
		if not entry then
			continue
		end

		local owner = typeof(item.motor) == "table"
			and item.motor.IsEclipseR6Control
			and item.motor.Owner
		local chain = entry.members[item.motor] or (owner and entry.owners[owner])
		if not chain then
			continue
		end

		local frame = baseFrame + item.offsetFrame
		if LimbIK.isEnabled(chain.owner, frame / raw.FPS) then
			add(chain.owner, frame, chain)
			for _, control in Controls.forOwner(chain.owner) do
				add(control, frame, chain)
			end
		end
	end
end

local Paths = require("Paths")
local Curves = require("GraphCurves")
local PoseSpace = require("PoseSpace")
const MasterControl = require("MasterControl")

local function homePivot(rig)
	const pivot = rig:GetPivot()
	const master = MasterControl.get(rig)
	if not master then
		return pivot
	end

	const base = master.Part0.CFrame
	return base * master.C1 * master.C0:Inverse() * base:Inverse() * pivot
end

local function kind(motor)
	if Properties.is(motor) then
		return "property"
	end

	if typeof(motor) == "Instance" then
		return motor:IsA("Motor6D") and "joint" or "other"
	end

	if motor.IsEclipseMasterControl then
		return "master"
	end

	if motor.IsEclipseR6Control then
		return "control"
	end

	if motor.IsEclipseArmatureControl then
		return "armature"
	end

	if motor.Bone then
		return "bone"
	end

	return "other"
end

local function describe(motor, rig, raw)
	local part = motor.Part1
	local k = kind(motor)
	local supported = (
		k == "joint"
		or k == "bone"
		or k == "armature"
		or k == "control"
		or k == "master"
	) and not require("CameraRig").isRig(rig)

	if not supported then
		return { rig = rig, kind = k, supported = false }
	end

	return {
		rig = rig,
		kind = k,
		supported = supported,
		path = part and Paths.motor(motor, rig),
		name = part and part.Name,
		parentName = motor.Part0 and motor.Part0.Name,
		control = k == "control" and part:GetAttribute("EclipseR6Control") or nil,
		ownerName = k == "control" and motor.Owner.Part1.Name or nil,
		space = k == "control" and part:GetAttribute("EclipseIKControlSpace") or nil,
		rest = raw.DefaultPose[motor] or (typeof(motor) == "table" and motor.DefaultC0) or motor.C0,
		origin = homePivot(rig),
		scale = PoseSpace.getRigScale(rig),
	}
end

function Modes.captureTransfer(clip)
	local raw = State.Timeline:GetState()
	copyTargets[clip] = require("SelectedRig").resolve(State, false) or false
	for _, entry in clip do
		local rig = sourceRig(entry.motor) or (typeof(entry.motor) == "table" and entry.motor.Rig)
		if rig then
			entry.transfer = describe(entry.motor, rig, raw)
		end
	end
end

local function closeRotation(a, b)
	return (a.RightVector - b.RightVector).Magnitude < 0.0001
		and (a.UpVector - b.UpVector).Magnitude < 0.0001
end

local function matches(a, b, exact)
	if not a.supported or a.kind ~= b.kind then
		return false
	end

	if a.kind == "master" then
		return true
	end

	if a.kind == "control" then
		return a.control == b.control and a.ownerName == b.ownerName and a.space == b.space
	end

	if exact then
		return a.path ~= nil and a.path == b.path
	end

	return a.kind == "joint" and a.name == b.name and a.parentName == b.parentName
end

local function movedEntry(entry, motor, target, raw)
	local from, to = entry.transfer, describe(motor, target, raw)
	const control = from.kind == "control"
	if not control and not closeRotation(from.rest, to.rest) then
		return nil
	end

	local ratio = to.scale / from.scale
	local offset = if control then Vector3.zero else to.rest.Position - from.rest.Position * ratio

	local function localPose(value)
		return typeof(value) == "CFrame"
				and CFrame.new(value.Position * ratio + offset) * value.Rotation
			or value
	end

	local function world(value)
		if typeof(value) == "CFrame" then
			return to.origin * PoseSpace.scaleTranslation(from.origin:ToObjectSpace(value), ratio)
		end

		if typeof(value) == "Vector3" then
			return to.origin:PointToWorldSpace(from.origin:PointToObjectSpace(value) * ratio)
		end

		return value
	end

	local function channels(collection)
		for id, point in collection or {} do
			local axis = ({ loc_x = "X", loc_y = "Y", loc_z = "Z" })[id]
			if axis then
				if typeof(point.Value) == "number" then
					point.Value = point.Value * ratio + offset[axis]
				end

				for _, side in { "In", "Out" } do
					if point[side] then
						point[side][2] *= ratio
					end
				end

				if point.BlenderHandles then
					for _, side in { "incoming", "outgoing" } do
						local h = point.BlenderHandles[side]
						if h then
							h[2] *= ratio
						end
					end
				end
			end
		end
	end

	local function metadata(meta)
		if not meta then
			return
		end

		for _, field in { "C0", "ChannelPoseC0", "IKBaseC0" } do
			meta[field] = localPose(meta[field])
		end

		for _, field in
			{
				"WorldCFrame",
				"IKTarget",
				"IKPole",
				"IKBaseWorld",
				"IKAnchor",
				"IKRigWorld",
				"IKRoot",
				"MirrorOrigin",
			}
		do
			meta[field] = world(meta[field])
		end

		if meta.HSRotation then
			meta.HSRotation = (to.origin * from.origin:Inverse()).Rotation * meta.HSRotation
		end

		if meta.MasterWorld then
			meta.MasterWorld = to.origin
				* PoseSpace.scaleTranslation(
					from.origin:Inverse() * meta.MasterWorld * from.origin,
					ratio
				)
				* to.origin:Inverse()
		end

		for _, field in { "PathTangentIn", "PathTangentOut" } do
			if meta[field] then
				meta[field] *= ratio
			end
		end

		channels(meta.Channels)
		channels(meta.GraphCurves)
		local curve = meta.BlenderCurve
		if curve then
			curve.from = localPose(curve.from)
			curve.to = localPose(curve.to)
			for _, sample in curve.samples or {} do
				sample.value = localPose(sample.value)
			end

			for _, signature in { curve.signature or {}, curve.nextSignature or {} } do
				channels(signature.graph)
			end
		end

		metadata(meta.PhysicsLead)
	end

	local copy = table.clone(entry)
	copy.motor, copy.part = motor, motor.Part1
	copy.c0, copy.worldCFrame = localPose(entry.c0), world(entry.worldCFrame)
	copy.metadata = Curves.clone(entry.metadata)
	metadata(copy.metadata)
	copy.sanitizeName = nil
	return copy
end

function Modes.forPaste(clip, selectedTarget)
	local raw = State.Timeline:GetState()
	local rigs = State.getAllRigs()

	local target = selectedTarget
	if selectedTarget == nil then
		target = require("SelectedRig").resolve(State, false)
	end

	if not table.find(rigs, target) then
		target = nil
	end

	local source, mixed
	for _, entry in clip do
		local rig = entry.transfer and entry.transfer.rig or sourceRig(entry.motor)
		if not rig then
			mixed = true
		elseif source and source ~= rig then
			mixed = true
		else
			source = rig
		end
	end

	if target and copyTargets[clip] == target then
		target = nil
	end

	const CameraRig = require("CameraRig")
	if target and source and CameraRig.isRig(target) ~= CameraRig.isRig(source) then
		target = nil
	end

	if mixed or not target or source == target then
		local result = {}
		for _, entry in clip do
			local rig = entry.transfer and entry.transfer.rig or sourceRig(entry.motor)
			if table.find(rigs, rig) and rig.Parent and entry.motor.Parent then
				table.insert(result, entry)
			end
		end

		const dropped = #clip - #result
		return result,
			dropped > 0
					and (#result > 0 and tostring(dropped) .. " copied keys belong to rigs or parts that are no longer in this project. Pasting the rest." or "The copied keys belong to a rig that is no longer in this project, so nothing was pasted.")
				or nil
	end

	local candidates, seen = {}, {}
	for _, motor in Parenting.collectMotors(target) do
		if not seen[motor] then
			seen[motor] = true
			table.insert(candidates, { motor = motor, info = describe(motor, target, raw) })
		end
	end

	for _, motor in raw.MotorByPart or {} do
		if not seen[motor] and sourceRig(motor) == target then
			seen[motor] = true
			table.insert(candidates, { motor = motor, info = describe(motor, target, raw) })
		end
	end

	local mapping, claimed, skipped, result = {}, {}, {}, {}
	for _, entry in clip do
		if entry.transfer and not entry.transfer.supported then
			local owner = entry.transfer.rig
			if table.find(rigs, owner) and owner.Parent and entry.motor.Parent then
				table.insert(result, entry)
			end

			continue
		end

		local descriptor = entry.transfer
		local motor = mapping[entry.motor]
		if motor == nil and descriptor then
			for _, exact in { true, false } do
				local found, ambiguous
				for _, candidate in candidates do
					if matches(descriptor, candidate.info, exact) then
						if found then
							ambiguous = true
						else
							found = candidate.motor
						end
					end
				end

				if ambiguous then
					break
				end

				if found then
					motor = found
					break
				end
			end

			if motor and claimed[motor] and claimed[motor] ~= entry.motor then
				motor = nil
			end

			mapping[entry.motor] = motor or false
			if motor then
				claimed[motor] = entry.motor
			end
		end

		local copy = motor and movedEntry(entry, motor, target, raw)
		if copy then
			table.insert(result, copy)
		elseif not entry.modeDependency then
			skipped[entry.motor] = true
		end
	end

	local count = 0
	for _ in skipped do
		count += 1
	end

	return result,
		count > 0
				and (tostring(count) .. " copied tracks could not be matched to this rig. " .. (#result > 0 and "Pasting the compatible tracks." or "No keys were pasted."))
			or nil
end

return Modes
