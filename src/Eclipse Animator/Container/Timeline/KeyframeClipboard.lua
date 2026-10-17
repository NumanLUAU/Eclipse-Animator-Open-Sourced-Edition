--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local ClipboardModes = require("ClipboardModes")
local KeyGroups = require("KeyGroups")
local Shortcuts = require("Shortcuts")
local Properties = require("Properties")
local BlenderEdit = require("BlenderEdit")
local MasterControl = require("MasterControl")
local KeyframePolicy = require("Policy")
local GraphCurves = require("GraphCurves")
local GraphRootState = require("State")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local State = require("RawState")
local MainState = require("State")
local History = require("History")
local R6Controls = require("R6Controls")
local LimbIK = require("LimbIK")
local BoneMotor = require("BoneMotor")
local ArmatureRuntime = require("ArmatureRuntime")
local Parenting = require("Parenting")
local motionPath = require("motionPath")
local TimelineState = State.Timeline
local TimelineConfig = State.Config
local PlayheadDrag = State.PlayheadDrag
local KeyframeDrag = State.KeyframeDrag
local SelectionState = State.Selection
local KEYFRAME_DEFAULT_COLOR = State.Colors.KEYFRAME_DEFAULT_COLOR
local KEYFRAME_HOVER_COLOR = State.Colors.KEYFRAME_HOVER_COLOR
local KEYFRAME_SELECTED_COLOR = State.Colors.KEYFRAME_SELECTED_COLOR
local LOOP_ACTIVE_COLOR = State.Colors.LOOP_ACTIVE_COLOR
local LOOP_INACTIVE_COLOR = State.Colors.LOOP_INACTIVE_COLOR

local CameraRig = require("CameraRig")

local function ownerRig(motor, fallback)
	if
		Properties.is(motor)
		and motor.Rig.Parent
		and table.find(MainState.getAllRigs and MainState.getAllRigs() or {}, motor.Rig)
	then
		return motor.Rig
	end

	local camera = CameraRig.owner(motor)
	if camera then
		return camera
	end

	return ClipboardModes.sourceRig(motor) or fallback
end

local function mirrorOrigin(rig)
	if rig:IsA("BasePart") then
		return rig.CFrame
	end

	local root = rig:FindFirstChild("HumanoidRootPart")
		or rig:FindFirstChild("RootPart")
		or rig.PrimaryPart
	return root and root.CFrame or rig:GetPivot()
end

local function flippedName(name)
	if #name < 3 then
		return name
	end

	local base, suffix = name:match("^(.*)(%.%d+)$")
	base, suffix = base or name, suffix or ""
	local sides = { l = "r", r = "l", L = "R", R = "L" }
	if base:sub(-2, -2):match("[._ %-]") and sides[base:sub(-1)] then
		return base:sub(1, -2) .. sides[base:sub(-1)] .. suffix
	end

	if base:sub(2, 2):match("[._ %-]") and sides[base:sub(1, 1)] then
		return sides[base:sub(1, 1)] .. base:sub(2) .. suffix
	end

	if #base >= 4 then
		for _, pair in { { "right", "left" }, { "left", "right" } } do
			local first, last = base:lower():find(pair[1], 1, true)
			if
				first
				and (
					first == 1
					or base:sub(first - 1, first - 1):match("[:._ %-/]")
					or base:sub(first, first):match("%u")
						and base:sub(first - 1, first - 1):match("[%l%d]")
				)
			then
				local replacement = pair[2]
				if base:sub(first, first) == base:sub(first, first):upper() then
					replacement = base:sub(first + 1, first + 1)
								== base:sub(first + 1, first + 1):upper()
							and replacement:upper()
						or replacement:sub(1, 1):upper() .. replacement:sub(2)
				end

				return base:sub(1, first - 1) .. replacement .. base:sub(last + 1) .. suffix
			end
		end
	end

	return name
end

local function findMirroredPart(rig, partName, sourcePart)
	if not rig or not partName then
		return nil
	end

	local name = flippedName(partName)
	local sourceId = sourcePart and sourcePart:GetAttribute("EclipseArmatureBoneId")
	if typeof(sourceId) == "string" then
		local object, bone = sourceId:match("^(.*::)(.-)$")
		local targetId = object and object .. flippedName(bone)
		for _, part in require("RigTraversal").descendants(rig) do
			if part:GetAttribute("EclipseArmatureBoneId") == targetId and part:IsA("BasePart") then
				return part
			end
		end

		return nil
	end

	local root = rig
	if sourcePart and sourcePart:IsA("Bone") then
		root = sourcePart.Parent
		while root and root:IsA("Bone") do
			root = root.Parent
		end

		root = root or rig
	end

	if sourcePart and sourcePart:IsDescendantOf(root) then
		local path, cursor, changed = {}, sourcePart, false
		while cursor and cursor ~= root do
			local mirrored = flippedName(cursor.Name)
			changed = changed or mirrored ~= cursor.Name
			table.insert(path, 1, { name = mirrored, class = cursor.ClassName })
			cursor = cursor.Parent
		end

		local target = root
		for _, step in path do
			local match
			for _, child in target:GetChildren() do
				if child.Name == step.name and child.ClassName == step.class then
					if match then
						match = nil
						break
					end

					match = child
				end
			end

			if not match then
				target = nil
				break
			end

			target = match
		end

		if changed and target and not ArmatureRuntime.isAnchor(target) then
			return target
		end
	end

	if name == partName and sourcePart then
		return sourcePart
	end

	local found
	for _, part in require("RigTraversal").descendants(root) do
		if
			part.Name == name
			and (part:IsA("BasePart") or part:IsA("Bone"))
			and not ArmatureRuntime.isAnchor(part)
		then
			if sourcePart and sourcePart:IsA("Bone") ~= part:IsA("Bone") then
				continue
			end

			if found then
				return nil
			end

			found = part
		end
	end

	return found
end

local function findMotorForPart(rig, part)
	if not rig or not part then
		return nil
	end

	if ArmatureRuntime.isAnchor(part) then
		return ArmatureRuntime.get(part, rig)
	end

	local known = TimelineState.MotorByPart[part]
	if known then
		return known
	end

	local master = MasterControl.get(rig)
	if master and master.Part1 == part then
		return master
	end

	if part:IsA("Bone") then
		return BoneMotor.get(part)
	end

	for _, m in ipairs(require("RigTraversal").descendants(rig)) do
		if m:IsA("Motor6D") and m.Part1 == part then
			return m
		end
	end

	return nil
end

local function mirrorC0(c0)
	local pos = c0.Position
	local right = c0.RightVector
	local up = c0.UpVector

	return CFrame.fromMatrix(
		Vector3.new(-pos.X, pos.Y, pos.Z),
		Vector3.new(right.X, -right.Y, -right.Z),
		Vector3.new(-up.X, up.Y, up.Z)
	)
end

local function mirrorPose(c0, source, target, rig)
	if CameraRig.isFov(source) then
		return c0
	end

	if
		typeof(source) == "table"
		and source.IsEclipseR6Control
		and typeof(target) == "table"
		and target.IsEclipseR6Control
		and source.Bone:GetAttribute("EclipseR6Control") == "root"
		and target.Bone:GetAttribute("EclipseR6Control") == "root"
	then
		local chain = LimbIK.chain(rig, source.Owner)
		if chain and chain.kind == "R6" then
			return mirrorC0(c0)
		end
	end

	local origin = mirrorOrigin(rig)
	if CameraRig.isTransform(source) or typeof(source) == "table" and source.IsEclipseR6Control and typeof(target) == "table" and target.IsEclipseR6Control then
		local world = source.Part0.CFrame * c0 * source.C1:Inverse()
		local mirrored = origin * mirrorC0(origin:ToObjectSpace(world))
		return target.Part0.CFrame:ToObjectSpace(mirrored) * target.C1
	end

	local function rest(motor)
		if typeof(motor) == "table" then
			if motor.RestC0 then
				return motor.RestC0
			end

			if motor.Bone then
				return motor.Bone.CFrame
			end
		end

		if typeof(motor) == "Instance" and motor:IsA("Motor6D") then
			local physicalRest = motor:GetAttribute("EclipseRigRestC0")
				or motor:GetAttribute("EclipseAnimatorDefaultC0")
			if typeof(physicalRest) == "CFrame" then
				return physicalRest
			end
		end

		return TimelineState.DefaultPose[motor]
			or motor:GetAttribute("EclipseAnimatorDefaultC0")
			or motor.C0
	end

	if
		typeof(source) == "Instance"
		and source:IsA("Motor6D")
		and typeof(target) == "Instance"
		and target:IsA("Motor6D")
		and source.Part0
		and source.Part1
		and target.Part0
		and target.Part1
	then
		local worlds, visiting = {}, {}

		local function parentRest(part)
			if worlds[part] then
				return worlds[part]
			end

			if visiting[part] then
				return origin:ToObjectSpace(part.CFrame)
			end

			visiting[part] = true
			local motor = TimelineState.MotorByPart and TimelineState.MotorByPart[part]
			if not motor then
				motor = findMotorForPart(rig, part)
			end

			local world = origin:ToObjectSpace(part.CFrame)
			if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part0 then
				world = parentRest(motor.Part0) * rest(motor) * motor.C1:Inverse()
			end

			visiting[part] = nil
			worlds[part] = world
			return world
		end

		local sourceParent, targetParent = parentRest(source.Part0), parentRest(target.Part0)
		local sourceRest = sourceParent * rest(source) * source.C1:Inverse()
		local sourcePose = sourceParent * c0 * source.C1:Inverse()
		local reflectedRest = mirrorC0(sourceRest)
		local reflectedPose = mirrorC0(sourcePose)
		local targetRest = targetParent * rest(target) * target.C1:Inverse()
		return targetParent:ToObjectSpace(reflectedPose * reflectedRest:Inverse() * targetRest)
			* target.C1
	end

	return rest(target) * mirrorC0(rest(source):ToObjectSpace(c0))
end

local function mirrorGraph(timeline, metadata, fallback, source, target, rig)
	local points = metadata.GraphCurves or {}
	if not next(points) and not next(metadata.Channels or {}) then
		return
	end

	local offset = mirrorPose(CFrame.identity, source, target, rig)

	local function close(a, b)
		local delta = a:ToObjectSpace(b)
		local _, angle = delta:ToAxisAngle()
		return delta.Position.Magnitude < 1e-5 and math.abs(angle) < 1e-5
	end

	local independent = close(offset.Rotation, CFrame.identity)
	for _, probe in
		{ CFrame.new(1, 2, 3), CFrame.Angles(0.3, 0.5, 0.7), CFrame.Angles(-0.7, 0.2, -0.4) }
	do
		independent = independent
			and close(
				mirrorPose(probe, source, target, rig),
				CFrame.new(offset.Position) * mirrorC0(probe)
			)
	end

	local signs = {
		loc_x = -1,
		loc_y = 1,
		loc_z = 1,
		rot_x = 1,
		rot_y = -1,
		rot_z = -1,
		qrot_w = 1,
		qrot_x = 1,
		qrot_y = -1,
		qrot_z = -1,
	}
	local shifts = { loc_x = offset.X, loc_y = offset.Y, loc_z = offset.Z }

	local original = GraphCurves.clone(points)

	local function transformed(id, value)
		local samplePoints = GraphCurves.clone(original)
		samplePoints[id].Value = value
		local sample = GraphCurves.cframe(
			{ [0] = { Time = 0, Frame = 0, GraphCurves = samplePoints } },
			0,
			fallback
		)
		local cf = mirrorPose(sample, source, target, rig)
		local values = timeline:DecomposeC0(cf)
		local order =
			GraphCurves.rotationOrder({ [0] = { Time = 0, Frame = 0, GraphCurves = original } })
		local ex, ey, ez = GraphCurves.euler(cf, order)
		local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
		values.rot_x, values.rot_y, values.rot_z = math.deg(x), math.deg(y), math.deg(z)
		return values[id]
	end

	local function mapPoint(id, point)
		local sign = signs[id]
		if sign then
			local value = point.Value
			local mapped = independent and (sign * value + (shifts[id] or 0))
				or transformed(id, value)
			for _, field in { "In", "Out" } do
				local handle = point[field]
				if handle then
					if independent then
						handle[2] *= sign
					else
						local changed = transformed(id, value + handle[2])
						local delta = changed - mapped
						if id:sub(1, 4) == "rot_" then
							delta = (delta + 180) % 360 - 180
						end

						handle[2] = delta
					end
				end
			end

			point.Value = mapped
			if point.BlenderHandles then
				point.BlenderHandles.incoming = GraphCurves.clone(point.In)
				point.BlenderHandles.outgoing = GraphCurves.clone(point.Out)
			end
		end
	end
	local fallbackValues = not independent and timeline:DecomposeC0(mirrorPose(fallback, source, target, rig))
	for id, channel in metadata.Channels or {} do
		if independent then
			mapPoint(id, channel)
		elseif signs[id] then
			channel.Value = fallbackValues[id]
		end
	end
	for id, point in points do mapPoint(id, point) end
end

local function mirrorWorldCFrameAcrossRig(worldCF, rig, origin)
	if not worldCF or not rig then
		return worldCF
	end

	origin = origin or mirrorOrigin(rig)
	return origin * mirrorC0(origin:ToObjectSpace(worldCF))
end

local function overrideWorldCFrameIfDetached(motor, frame, worldCF)
	if not worldCF or not motor then
		return
	end

	local bucket = TimelineState.Keyframes[motor]
	local kd = bucket and bucket[frame]
	if kd then
		kd.WorldCFrame = worldCF
	end
end

local function extractKeyframeMetadata(kd)
	if not kd then
		return nil
	end

	local meta = {
		Disabled = kd.Disabled,
		PropertyValue = kd.PropertyValue,
		PathTangentIn = kd.PathTangentIn,
		PathTangentOut = kd.PathTangentOut,
		KeyGroups = KeyGroups.clone(kd.KeyGroups),
		WholePoseScale = GraphCurves.clone(kd.WholePoseScale),
		PhysicsLead = GraphCurves.clone(kd.PhysicsLead),
		PhysicsTail = kd.PhysicsTail,
		ChannelPoseC0 = kd.ChannelPoseC0,
		BlenderCurve = GraphCurves.clone(kd.BlenderCurve),
		BlenderSource = kd.BlenderSource,
		GraphOnly = kd.GraphOnly,
		GraphCurves = GraphCurves.clone(kd.GraphCurves),
		Parented = kd.Parented,
		HeadFollow = kd.HeadFollow,
		HS = kd.HS,
		HSRestoreParented = kd.HSRestoreParented,
		HSRotation = kd.HSRotation,
		HSLocalRotation = kd.HSLocalRotation,
		IK = kd.IK,
		IKTarget = kd.IKTarget,
		IKPole = kd.IKPole,
		IKBaseC0 = kd.IKBaseC0,
		IKBaseWorld = kd.IKBaseWorld,
		IKAnchor = kd.IKAnchor,
		IKRigWorld = kd.IKRigWorld,
		CamTrackTo = kd.CamTrackTo,
		CamTargetEnabled = kd.CamTargetEnabled,
		CamAttachTarget = require("GraphCurves").clone(kd.CamAttachTarget),
		FovFollowAnchor = kd.FovFollowAnchor,
		CamTargetParent = kd.CamTargetParent,
		CamTargetAnchor = kd.CamTargetAnchor,
		IKRoot = kd.IKRoot,
		IKPoleFollowsTarget = kd.IKPoleFollowsTarget,
		IKRestoreParented = kd.IKRestoreParented,
		WorldCFrame = kd.WorldCFrame,
		MasterWorld = kd.MasterWorld,
		HandleType = kd.HandleType,
		EasingStyle = kd.EasingStyle,
		QuaternionInterpolationVersion = kd.QuaternionInterpolationVersion,
		EasingDirection = kd.EasingDirection,
		Overshoot = kd.Overshoot,
		Amplitude = kd.Amplitude,
		Period = kd.Period,
		MoonEasing = kd.MoonEasing,
	}
	if kd.BezierPoints then
		meta.BezierPoints = {
			kd.BezierPoints[1],
			kd.BezierPoints[2],
			kd.BezierPoints[3],
			kd.BezierPoints[4],
		}
	end

	if kd.Channels then
		meta.Channels = {}
		for chId, ch in pairs(kd.Channels) do
			if type(ch) == "table" then
				meta.Channels[chId] = GraphCurves.clone(ch)
			end
		end
	end

	return meta
end

local function applyEasingMetadata(kd, meta)
	if not kd or not meta then
		return
	end

	kd.PathTangentIn, kd.PathTangentOut = meta.PathTangentIn, meta.PathTangentOut
	kd.Disabled = meta.Disabled
	kd.PropertyValue = meta.PropertyValue
	kd.KeyGroups = KeyGroups.clone(meta.KeyGroups)
	kd.WholePoseScale = GraphCurves.clone(meta.WholePoseScale)
	kd.PhysicsLead, kd.PhysicsTail = GraphCurves.clone(meta.PhysicsLead), meta.PhysicsTail
	kd.ChannelPoseC0 = meta.ChannelPoseC0
	kd.BlenderCurve = GraphCurves.clone(meta.BlenderCurve)
	kd.BlenderSource = meta.BlenderSource
	kd.GraphOnly, kd.GraphCurves = meta.GraphOnly, GraphCurves.clone(meta.GraphCurves)
	GraphCurves.invalidate(TimelineState.Keyframes[kd.Motor])
	if typeof(meta.Parented) == "boolean" then
		kd.Parented = meta.Parented
	end

	kd.WorldCFrame = kd.Parented == false and meta.WorldCFrame or nil
	kd.MasterWorld = meta.MasterWorld
	kd.HeadFollow = meta.HeadFollow
	kd.HS, kd.HSRotation, kd.HSLocalRotation = meta.HS, meta.HSRotation, meta.HSLocalRotation
	kd.HSRestoreParented = meta.HSRestoreParented
	kd.IK = meta.IK
	kd.IKTarget = meta.IKTarget
	kd.IKPole = meta.IKPole
	kd.IKBaseC0 = meta.IKBaseC0
	kd.IKBaseWorld = meta.IKBaseWorld
	kd.IKAnchor = meta.IKAnchor
	kd.IKRigWorld = meta.IKRigWorld
	kd.CamTrackTo = meta.CamTrackTo
	kd.CamTargetEnabled = meta.CamTargetEnabled
	kd.CamAttachTarget = require("GraphCurves").clone(meta.CamAttachTarget)
	kd.FovFollowAnchor = meta.FovFollowAnchor
	kd.CamTargetParent = meta.CamTargetParent
	kd.CamTargetAnchor = meta.CamTargetAnchor
	kd.IKRoot = meta.IKRoot
	kd.IKPoleFollowsTarget = meta.IKPoleFollowsTarget
	kd.IKRestoreParented = meta.IKRestoreParented
	kd.HandleType = meta.HandleType
	kd.QuaternionInterpolationVersion = meta.QuaternionInterpolationVersion
	kd.EasingStyle = meta.EasingStyle
	kd.EasingDirection = meta.EasingDirection
	kd.Overshoot = meta.Overshoot
	kd.Amplitude = meta.Amplitude
	kd.Period = meta.Period
	kd.MoonEasing = meta.MoonEasing
	if meta.BezierPoints then
		kd.BezierPoints = {
			meta.BezierPoints[1],
			meta.BezierPoints[2],
			meta.BezierPoints[3],
			meta.BezierPoints[4],
		}
	else
		kd.BezierPoints = nil
	end
end

local function clipboardMetadata(key)
	local metadata = ClipboardModes.capture(key, extractKeyframeMetadata(key))
	local rig = ownerRig(key.Motor, MainState.currentRig)
	if rig and not Properties.is(key.Motor) and (rig:IsA("Model") or rig:IsA("BasePart")) then
		local origin = mirrorOrigin(rig)
		local root = rig:FindFirstChild("HumanoidRootPart")
			or rig:FindFirstChild("RootPart")
			or (rig:IsA("Model") and rig.PrimaryPart)
		local motor = root and TimelineState.MotorByPart[root]
		if motor and MainState.Timeline then
			local evaluator = Parenting.newEvaluator(
				Parenting.collectMotors(rig),
				TimelineState.Keyframes,
				TimelineState.DefaultPose,
				TimelineState.DefaultWorldPose,
				TimelineState.ParentingDefaults,

				function(m, t)
					return MainState.Timeline:EvaluateMotorC0(m, t)
				end
			)
			origin = evaluator.worldAt(motor, key.Time)
		end

		metadata.MirrorOrigin = origin
	end

	if Properties.is(key.Motor) then
		return metadata
	end

	metadata.ChannelPoseC0, metadata.WholePoseScale, metadata.BlenderCurve = nil, nil, nil
	local owned = GraphCurves.compile(TimelineState.Keyframes[key.Motor]).channels
	metadata.Channels = metadata.Channels or {}
	for id in metadata.Channels do
		if key.GraphOnly or owned[id] then
			metadata.Channels[id] = nil
		end
	end

	for id, point in metadata.GraphCurves or {} do
		if point.Empty then
			metadata.GraphCurves[id] = nil
		end
	end

	return metadata
end

local function mergeChannelPaste(existing, metadata, channelOnly)
	if not existing or not channelOnly then
		return metadata
	end

	local merged = extractKeyframeMetadata(existing)
	ClipboardModes.merge(merged, metadata)
	merged.Channels = merged.Channels or {}
	merged.GraphCurves = merged.GraphCurves or {}
	for id, channel in metadata.Channels or {} do
		merged.Channels[id] = GraphCurves.clone(channel)
		KeyGroups.set(merged, id, KeyGroups.get(metadata, id))
		merged.GraphCurves[id] = nil
	end

	for id, point in metadata.GraphCurves or {} do
		merged.GraphCurves[id] = GraphCurves.clone(point)
		KeyGroups.set(merged, id, KeyGroups.get(metadata, id))
		merged.Channels[id] = nil
	end

	return merged
end

local function metadataForPaste(metadata, frame, groups)
	local copy = GraphCurves.clone(metadata)
	if copy then
		copy.KeyGroups = KeyGroups.remap(copy.KeyGroups, groups, function()
			return game:GetService("HttpService"):GenerateGUID(false)
		end)
	end

	for id, point in pairs(copy and copy.GraphCurves or {}) do
		point.Id = tostring(point.Id or id)
			.. "/paste/"
			.. tostring(frame)
			.. "/"
			.. tostring(os.clock())
	end

	return copy
end

local function restoreChannelsAndRebuild(timeline, motor, frame, channelsSnap, recorded)
	if not channelsSnap then
		return
	end

	local bucket = TimelineState.Keyframes[motor]
	local kd = bucket and bucket[frame]
	if not kd then
		return
	end

	local restored = {}
	for chId, ch in recorded or {} do
		restored[chId] = ch
	end

	for chId, ch in pairs(channelsSnap) do
		restored[chId] = GraphCurves.clone(ch)
	end

	kd.Channels = restored
	GraphCurves.invalidate(bucket)
	local rebuilt = timeline:_reconstructC0FromKeyData(kd)
	if rebuilt then
		kd.C0 = rebuilt
		kd.Position = rebuilt.Position
		kd.Rotation = rebuilt - rebuilt.Position
	end

	TimelineState._motorUniform[motor] = nil
	TimelineState._motorHasScale[motor] = nil
	timeline:CreateOrUpdateTimelineKeyframeButton(motor.Part1, motor, frame, nil, kd.SanitizeName)
	timeline:_addChannelDiamondAtFrame(motor, frame)
end

return function(Timeline)
	local function refreshKeyEdit(timeline, motors)
		for motor in motors do
			GraphCurves.invalidate(TimelineState.Keyframes[motor])
			TimelineState._motorUniform[motor], TimelineState._motorHasScale[motor] = nil, nil
			timeline:RefreshAllChannelDiamondsForMotor(motor)
		end

		MainState.currentProjectSaved = false
		if MainState.GraphEditor then
			MainState.GraphEditor.invalidate()
		end

		if MainState.currentRig then
			timeline:ApplyPoseAtTime(MainState.currentRig, TimelineState.CurrentTime)
		end

		timeline:RefreshAllKeyframeVisuals()
		motionPath.markDirty()
	end

	function Timeline:GetKeyframeToggleTargets()
		local targets, whole = {}, {}
		for _, key in self:GetSelectedKeyframesList() do
			whole[key] = true
			table.insert(targets, { key = key })
		end

		for _, selected in self:GetSelectedChannelKeyframesList() do
			if not whole[selected.keyData] then
				table.insert(targets, { key = selected.keyData, id = selected.channelId })
			end
		end

		return targets
	end

	function Timeline:KeyframeToggleEnables(targets)
		for _, target in targets do
			if KeyframePolicy.isDisabled(target.key, target.id) then
				return true
			end
		end

		return false
	end

	function Timeline:ToggleKeyframesEnabled(targets)
		if BlenderEdit.blocked() then
			return
		end

		if #targets == 0 then
			return
		end

		local disabled = not self:KeyframeToggleEnables(targets)
		local motors, before, after = {}, {}, {}
		for _, target in targets do
			local motor = target.key.Motor
			if motor and not motors[motor] then
				motors[motor] = true
				before[motor] = self:_snapshotMotorBucket(motor)
			end
		end

		for _, target in targets do
			local key, id = target.key, target.id
			if id then
				self:EnsureChannelsPopulated(key)
				if not disabled and key.Disabled then
					key.Disabled = nil
					for _, entries in { key.Channels or {}, key.GraphCurves or {} } do
						for _, entry in entries do
							entry.Disabled = true
						end
					end
				end

				if key.Channels and key.Channels[id] then
					key.Channels[id].Disabled = disabled or nil
				end

				if key.GraphCurves and key.GraphCurves[id] then
					key.GraphCurves[id].Disabled = disabled or nil
				end
			else
				key.Disabled = disabled or nil
				if not disabled then
					for _, entries in { key.Channels or {}, key.GraphCurves or {} } do
						for _, entry in entries do
							entry.Disabled = nil
						end
					end
				end
			end
		end

		for motor in motors do
			after[motor] = self:_snapshotMotorBucket(motor)
		end

		refreshKeyEdit(self, motors)

		local function restore(snapshot)
			for motor, bucket in snapshot do
				self:_restoreMotorBucket(motor, bucket)
			end

			refreshKeyEdit(self, motors)
		end

		History.record(function()
			restore(before)
		end, function()
			restore(after)
		end, disabled and "Disable keyframes" or "Enable keyframes")
	end

	function Timeline:KeyframeTargetAtPosition(position)
		local best, distance

		local function consider(row, motor, part, id)
			if not row or not motor or not part or row.AbsoluteSize.Y <= 0 then
				return
			end

			local ancestor = row
			while ancestor do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then
					return
				end

				ancestor = ancestor.Parent
			end

			local middle = row.AbsolutePosition.Y + row.AbsoluteSize.Y * 0.5
			local delta = math.abs(position.Y - middle)
			if not distance or delta < distance then
				distance = delta
				best = { motor = motor, part = part, id = id, row = row }
			end
		end

		for part, row in TimelineState.TrackRows do
			local motor = TimelineState.MotorByPart[part]
			if not motor then
				for candidate in TimelineState.DefaultPose do
					if candidate.Part1 == part then
						motor = candidate
						break
					end
				end
			end

			consider(row, motor, part)
		end

		if KeyframePolicy.channelsEnabled() then
			for motor, rows in TimelineState.ChannelTracks do
				for id, row in rows do
					consider(row, motor, motor.Part1, id)
				end
			end
		end

		if best then
			local container = self:GetTrackKeyframesContainer(best.row)
			local width = self:GetVisibleTimelineWidth()
			local scale = container
					and container.AbsoluteSize.X > 0
					and container.AbsoluteSize.X / math.max(1, width)
				or 1
			local origin = container and container.AbsolutePosition.X or self:GetClickReferenceX()
			best.frame = math.clamp(
				self:VisibleXToFrame((position.X - origin) / scale),
				0,
				self:GetMaxFrame()
			)
		end

		return best
	end

	function Timeline:InsertKeyframeAtTarget(target)
		if BlenderEdit.blocked() then
			return
		end

		if not target or not target.motor or not target.part then
			return
		end

		local motor, part, frame = target.motor, target.part, target.frame
		local before = self:_snapshotMotorBucket(motor)
		local time = self:FrameToTime(frame)
		local c0 = self:EvaluateMotorC0(motor, time)
		if target.id then
			self:RecordPartialKeyframeForMotorAtCurrentTime(part, motor, c0, { target.id }, nil, {
				Frame = frame,
				PropertyValue = Properties.is(motor)
						and Properties.evaluate(motor, TimelineState.Keyframes[motor], time)
					or nil,
			})
		else
			self:RecordKeyframeForMotorAtCurrentTime(part, motor, c0, {
				Frame = frame,
				PropertyValue = Properties.is(motor)
						and Properties.evaluate(motor, TimelineState.Keyframes[motor], time)
					or nil,
			})
		end

		local after = self:_snapshotMotorBucket(motor)
		local motors = { [motor] = true }
		refreshKeyEdit(self, motors)

		local function restore(snapshot)
			self:_restoreMotorBucket(motor, snapshot)
			refreshKeyEdit(self, motors)
		end

		History.record(function()
			restore(before)
		end, function()
			restore(after)
		end, "Insert keyframe", frame)
	end

	function Timeline:GetDeleteButton()
		if self.refs and self.refs.DeleteButton then
			return self.refs.DeleteButton
		end

		if self.refs and self.refs.MainFrame then
			local direct = self.refs.MainFrame:FindFirstChild("DeleteButton", true)
			if direct then
				return direct
			end
		end

		if State.timelineUI then
			local direct = State.timelineUI:FindFirstChild("DeleteButton", true)
			if direct then
				return direct
			end
		end

		return nil
	end

	function Timeline:UpdateDeleteButtonState()
		local deleteButton = self:GetDeleteButton()
		if not deleteButton then
			return
		end

		deleteButton.Visible = TimelineState.SelectedKeyframe ~= nil

		if deleteButton:IsA("GuiButton") then
			deleteButton.AutoButtonColor = false
			deleteButton.Active = true
			deleteButton.Selectable = true
		end
	end

	function Timeline:BindUnselectorButton()
		local unselector = self.refs.Unselector
		if not unselector or unselector:GetAttribute("TimelineUnselectorBound") then
			return
		end

		unselector:SetAttribute("TimelineUnselectorBound", true)

		if unselector:IsA("GuiButton") then
			unselector.AutoButtonColor = false
			unselector.Active = true
			unselector.Selectable = true

			unselector.MouseButton1Click:Connect(function()
				if not self._selectionDragConsumed and not self:IsSelectionModifierDown() then
					self:ClearSelectedKeyframe()
				end
			end)

			if unselector.Activated then
				unselector.Activated:Connect(function()
					if not self._selectionDragConsumed and not self:IsSelectionModifierDown() then
						self:ClearSelectedKeyframe()
					end
				end)
			end
		end
	end

	function Timeline:BindDeleteButton()
		local deleteButton = self:GetDeleteButton()
		if not deleteButton or deleteButton:GetAttribute("TimelineDeleteBound") then
			return
		end

		deleteButton:SetAttribute("TimelineDeleteBound", true)

		if deleteButton:IsA("GuiButton") then
			deleteButton.AutoButtonColor = false
			deleteButton.Active = true
			deleteButton.Selectable = true
		end

		if deleteButton:IsA("GuiButton") then
			deleteButton.Activated:Connect(function()
				self:DeleteSelectedKeyframes()
			end)
		end

		self:UpdateDeleteButtonState()
	end

	function Timeline:ApplyEditedBuckets(buckets)
		self:CancelTimelineKeyframeDrag()
		table.clear(TimelineState.SelectedKeyframes)
		table.clear(TimelineState.SelectedChannelKeyframes)
		TimelineState.SelectedKeyframe = nil
		KeyframeDrag.hoveringKeyframe = nil
		KeyframeDrag.hoveringChannelId = nil
		KeyframeDrag.draggingKeyframe = nil
		local rigs = {}
		for motor, bucket in buckets do
			self:_restoreMotorBucket(motor, bucket, true)
			local rig = ownerRig(motor, MainState.currentRig)
			if rig then
				rigs[rig] = true
			end
		end

		for motor in buckets do
			for frame, key in TimelineState.Keyframes[motor] do
				if
					key.Part
					and not (
						self.IsKeyGroupCollapsed
						and self:IsKeyGroupCollapsed(key, KeyGroups.POSE)
					)
				then
					self:CreateOrUpdateTimelineKeyframeButton(
						key.Part,
						motor,
						frame,
						key.Template,
						key.SanitizeName
					)
				end
			end

			self:RefreshAllChannelDiamondsForMotor(motor)
		end

		for rig in rigs do
			if rig.Parent then
				self:ApplyPoseAtTime(rig, TimelineState.CurrentTime, { OnlyRig = true })
				for _, motor in Parenting.collectMotors(rig) do
					MainState.lastCFrames[motor] = motor.C0
				end
			end
		end

		self:RefreshAllKeyframeVisuals()
		self:UpdateDeleteButtonState()
		if MainState.GraphEditor then
			MainState.GraphEditor.invalidate()
		end

		MainState.currentProjectSaved = false
		motionPath.markDirty()
	end

	function Timeline:SplitSelectedKeyframes(stride)
		if
			BlenderEdit.blocked()
			or self:IsExportLocked()
			or self:IsBlenderKeyframeTransformActive()
		then
			return false
		end

		stride = stride or TimelineState.SplitStride or 3
		if
			typeof(stride) ~= "number"
			or stride ~= stride
			or stride == math.huge
			or stride < 1
			or stride % 1 ~= 0
		then
			return false
		end

		local chosen, ordered = {}, {}
		for _, key in self:GetSelectedKeyframesList() do
			chosen[key] = true
		end

		for _, entry in self:GetSelectedChannelKeyframesList() do
			local key = entry.keyData
			if chosen[key] ~= true then
				chosen[key] = chosen[key] or {}
				chosen[key][entry.channelId] = true
			end
		end

		local groupPlans = {}

		local function plan(key, lane)
			local bucket = TimelineState.Keyframes[key.Motor]
			if not bucket or bucket[key.Frame] ~= key then
				return
			end

			local members = { { key = key, frame = key.Frame } }
			local id = KeyGroups.get(key, lane)
			if id and self:IsKeyGroupCollapsed(key, lane) then
				local token = tostring(key.Motor) .. ":" .. lane .. ":" .. id
				if groupPlans[token] then
					return
				end

				groupPlans[token] = true
				members = KeyGroups.collect(bucket, lane)[id] or members
			end

			table.insert(ordered, {
				key = members[1].key,
				mask = lane == KeyGroups.POSE and true or { [lane] = true },
				members = members,
			})
		end

		for key, mask in chosen do
			if mask == true then
				plan(key, KeyGroups.POSE)
			else
				for id in mask do
					plan(key, id)
				end
			end
		end

		if #ordered == 0 then
			return false
		end

		table.sort(ordered, function(a, b)
			return a.key.Frame < b.key.Frame
		end)
		local before, working, after, originalSelection, newSelection = {}, {}, {}, {}, {}

		local function copy(key)
			local result = table.clone(key)
			for _, field in
				{
					"Channels",
					"GraphCurves",
					"BezierPoints",
					"WholePoseScale",
					"KeyGroups",
					"BlenderCurve",
				}
			do
				result[field] = GraphCurves.clone(key[field])
			end

			return result
		end

		for _, entry in ordered do
			local motor = entry.key.Motor
			if not before[motor] then
				before[motor] = self:_snapshotMotorBucket(motor)
				working[motor] = {}
				after[motor] = {}
				originalSelection[motor] = {}
				newSelection[motor] = {}
				for frame, key in before[motor] do
					working[motor][frame] = copy(key)
				end
			end

			for _, member in entry.members do
				local mask = originalSelection[motor][member.frame]
				if entry.mask == true then
					originalSelection[motor][member.frame] = true
				elseif mask ~= true then
					mask = mask or {}
					originalSelection[motor][member.frame] = mask
					for id in entry.mask do
						mask[id] = true
					end
				end
			end
		end

		for motor, bucket in working do
			local channels = {}
			for _, mask in originalSelection[motor] do
				if mask ~= true then
					for id in mask do
						channels[id] = true
					end
				end
			end

			if next(channels) then
				local state = table.clone(TimelineState)
				state.Keyframes = { [motor] = bucket }
				local proxy = setmetatable({
					GetState = function()
						return state
					end,
				}, { __index = self })
				local model = require("GraphModel").new({ Timeline = proxy })
				for _, track in model:tracks({ motor }) do
					if channels[track.channelId] then
						model:_adopt(track)
					end
				end
			end

			for frame, key in bucket do
				after[motor][frame] = copy(key)
			end
		end

		local function occupied(bucket, lo, hi, mask)
			for frame, key in bucket do
				if frame >= lo and frame <= hi then
					if mask == true or not key.GraphOnly and not key.Channels then
						return true
					end

					for id in mask do
						if
							key.Channels and key.Channels[id]
							or key.GraphCurves and key.GraphCurves[id]
						then
							return true
						end
					end
				end
			end

			local lanes = {}
			if mask == true then
				lanes[KeyGroups.POSE] = true
			else
				lanes = mask
			end

			for lane in lanes do
				for _, members in KeyGroups.collect(bucket, lane) do
					if members[1].frame <= hi and members[#members].frame >= lo then
						return true
					end
				end
			end

			return false
		end

		local function sample(motor, source, key, frame, mask)
			local value = copy(key)
			local time = frame / TimelineState.FPS
			value.Frame, value.Time = frame, time
			value.Button, value.KeyGroups, value.PhysicsLead, value.PhysicsTail = nil, nil, nil, nil
			value.BlenderCurve, value.BlenderSource = nil, nil
			value.C0 = self:EvaluateMotorC0(motor, time, source)
			value.Position, value.Rotation = value.C0.Position, value.C0.Rotation

			if mask == true and key.IK ~= nil then
				local chain = LimbIK.chain(ownerRig(motor, MainState.currentRig), motor)
				if chain then
					local sampled = LimbIK.keyStateAt(chain, time, source)
					for _, field in
						{
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
						}
					do
						value[field] = sampled[field]
					end
				end
			end

			if
				mask == true and not (typeof(motor) == "table" and motor.IsEclipseArmatureControl)
			then
				local stabilizer = require("HeadStabilizer")
				local rotation = stabilizer.rotationAt(motor, time, value.C0, source)
				if rotation then
					value.HS, value.HSRotation, value.HSLocalRotation =
						true, rotation, value.C0.Rotation
				elseif key.HS ~= nil then
					value.HS = require("cache").isEnabled(motor, source, time)
					value.HSRotation, value.HSLocalRotation = nil, nil
				end
			end

			value.ChannelPoseC0 = nil
			if Properties.is(motor) then
				value.PropertyValue = Properties.evaluate(motor, source, time)
			end

			local values = self:DecomposeC0(value.C0)
			values.rot_x, values.rot_y, values.rot_z =
				GraphCurves.euler(value.C0, GraphCurves.rotationOrder(source))
			local scale = self:EvaluateMotorScale(motor, time, source)
			for id, v in scale or {} do
				values[id] = v
			end

			value.WholePoseScale = scale and table.clone(scale) or nil
			if key.WorldCFrame then
				local a, b = require("Parenting").bounds(source, time)
				if a and b and a ~= b and a.WorldCFrame and b.WorldCFrame then
					value.WorldCFrame = require("Interp").cframe(
						source,
						a,
						b,
						(time - a.Time) / (b.Time - a.Time),
						"WorldCFrame"
					)
				else
					local k = a or b
					value.WorldCFrame = k and k.WorldCFrame or key.WorldCFrame
				end
			end

			local compiled = GraphCurves.compile(source)
			for id, point in value.GraphCurves or {} do
				point.Value = GraphCurves.value(compiled.channels[id], time)
					or values[id]
					or point.Value
			end

			for id, channel in value.Channels or {} do
				channel.Value = values[id] or channel.Value
			end

			if mask ~= true then
				value.Channels, value.GraphCurves, value.GraphOnly = {}, {}, true
				for id in mask do
					local point = key.GraphCurves and GraphCurves.clone(key.GraphCurves[id])
						or GraphCurves.newPoint(key, id)
					point.Value = GraphCurves.value(compiled.channels[id], time) or values[id]
					value.GraphCurves[id] = point
				end
			end

			return value
		end

		local count = 0
		for _, entry in ordered do
			local old, mask = entry.key, entry.mask
			local motor, frame = old.Motor, old.Frame
			local source, output = working[motor], after[motor]
			local key = source[frame]
			local destinations = {}
			if frame - stride >= 0 and not occupied(output, frame - stride, frame - 1, mask) then
				table.insert(destinations, frame - stride)
			end

			if
				frame + stride <= self:GetMaxFrame()
				and not occupied(output, frame + 1, frame + stride, mask)
			then
				table.insert(destinations, frame + stride)
			end

			if #destinations == 0 then
				newSelection[motor][frame] = mask
				continue
			end

			count += 1
			for _, member in entry.members do
				local removing = output[member.frame]
				local retained = self:ResetDeletedFirstTransformKey(
					motor,
					removing,
					mask ~= true and mask or nil
				)

				if retained then
					retained = copy(removing)
				end

				if mask == true then
					output[member.frame] = retained
				else
					if not retained then
						for id in mask do
							if removing.Channels then
								removing.Channels[id] = nil
							end

							if removing.GraphCurves then
								removing.GraphCurves[id] = nil
							end

							KeyGroups.set(removing, id, nil)
						end

						if
							removing.GraphOnly
							and not next(removing.Channels or {})
							and not next(removing.GraphCurves or {})
						then
							output[member.frame] = nil
						end
					end
				end
			end

			for _, dest in destinations do
				local value = sample(motor, source, key, dest, mask)
				if mask == true then
					output[dest] = value
				else
					local target = output[dest] or value
					output[dest] = target
					target.Channels, target.GraphCurves =
						target.Channels or {}, target.GraphCurves or {}
					for id in mask do
						target.Channels[id] = nil
						target.GraphCurves[id] = value.GraphCurves[id]
					end
				end

				if mask == true then
					newSelection[motor][dest] = true
				elseif newSelection[motor][dest] ~= true then
					newSelection[motor][dest] = newSelection[motor][dest] or {}
					for id in mask do
						newSelection[motor][dest][id] = true
					end
				end
			end
		end

		if count == 0 then
			return false
		end

		local function restore(buckets, selection)
			TimelineState.Playing = false
			self:ApplyEditedBuckets(buckets)
			for motor, frames in selection do
				for frame, mask in frames do
					local key = TimelineState.Keyframes[motor][frame]
					if key then
						if mask == true then
							TimelineState.SelectedKeyframes[key] = true
						else
							TimelineState.SelectedChannelKeyframes[key] = GraphCurves.clone(mask)
						end

						TimelineState.SelectedKeyframe = key
					end
				end
			end

			self:RefreshAllKeyframeVisuals()
			self:UpdateDeleteButtonState()
		end

		local remaining = {}
		for motor, frames in originalSelection do
			remaining[motor] = {}
			for frame, mask in frames do
				if newSelection[motor][frame] then
					remaining[motor][frame] = mask
				end
			end
		end

		restore(after, remaining)
		History.record(function()
			restore(before, originalSelection)
		end, function()
			restore(after, newSelection)
		end, "Split keyframes", ordered[1].key.Frame)
		return true
	end

	function Timeline:CutSelectedKeyframes()
		if
			BlenderEdit.blocked()
			or self:IsExportLocked()
			or self:IsBlenderKeyframeTransformActive()
		then
			return false
		end

		if self.ExpandGroupedSelection then
			self:ExpandGroupedSelection()
		end

		if not self:CopySelectedKeyframes() then
			return false
		end

		local channels = {}
		local mixed = #self:GetSelectedKeyframesList() > 0
		if mixed then
			for _, item in self:GetSelectedChannelKeyframesList() do
				if not TimelineState.SelectedKeyframes[item.keyData] then
					channels[#channels + 1] = {
						motor = item.keyData.Motor,
						frame = item.keyData.Frame,
						id = item.channelId,
					}
				end
			end
		end

		History.batch("Cut keyframes", function()
			self:DeleteSelectedKeyframes()
			if #channels > 0 then
				for _, item in channels do
					local bucket = TimelineState.Keyframes[item.motor]
					local key = bucket and bucket[item.frame]
					if key then
						local selected = TimelineState.SelectedChannelKeyframes[key] or {}
						selected[item.id] = true
						TimelineState.SelectedChannelKeyframes[key] = selected
					end
				end

				self:DeleteSelectedChannelKeyframes()
			end
		end)

		return true
	end

	function Timeline:DeleteSelectedKeyframes()
		if BlenderEdit.blocked() then
			return
		end

		if self.ExpandGroupedSelection then
			self:ExpandGroupedSelection()
		end

		local selectedList = self:GetSelectedKeyframesList()

		if #selectedList == 0 and self:HasAnySelectedChannelKeyframes() then
			self:DeleteSelectedChannelKeyframes()
			return
		end

		if #selectedList == 0 and TimelineState.SelectedKeyframe then
			selectedList = { TimelineState.SelectedKeyframe }
		end

		if #selectedList == 0 then
			return
		end


		local before, after = {}, {}
		local count, first = 0, math.huge
		for _, key in selectedList do
			local motor = key.Motor
			if
				motor
				and key.Frame ~= nil
				and TimelineState.Keyframes[motor]
				and TimelineState.Keyframes[motor][key.Frame] == key
			then
				if not before[motor] then
					before[motor] = self:_snapshotMotorBucket(motor)
					after[motor] = table.clone(before[motor])
				end

				after[motor][key.Frame] =
					self:ResetDeletedFirstTransformKey(motor, after[motor][key.Frame])
				count += 1
				first = math.min(first, key.Frame)
			end
		end

		if count == 0 then
			return
		end

		self:ApplyEditedBuckets(after)
		History.record(function()
			self:ApplyEditedBuckets(before)
		end, function()
			self:ApplyEditedBuckets(after)
		end, count > 1 and "Delete " .. count .. " keyframes" or "Delete keyframe", first)
	end

	function Timeline:DeleteSelectedChannelKeyframes()
		if BlenderEdit.blocked() then
			return
		end

		local toDelete = {}
		local order = {}
		for keyData, channels in pairs(TimelineState.SelectedChannelKeyframes) do
			if
				not TimelineState.SelectedKeyframes[keyData]
				and keyData.Motor
				and keyData.Frame ~= nil
			then
				local channelSet = {}
				local anyChannel = false
				for channelId in pairs(channels) do
					channelSet[channelId] = true
					anyChannel = true
				end

				if anyChannel then
					toDelete[keyData] = channelSet
					table.insert(order, keyData)
				end
			end
		end

		if #order == 0 then
			return
		end

		local hasGraph = false
		local motors, seen = {}, {}
		for _, key in ipairs(order) do
			if not seen[key.Motor] then
				seen[key.Motor] = true
				table.insert(motors, key.Motor)
			end

			hasGraph = hasGraph or GraphCurves.compile(TimelineState.Keyframes[key.Motor]).hasGraph
		end

		if hasGraph then
			local Model = require("GraphModel")
			local model = Model.new({
				Timeline = self,
				History = History,
				onChanged = function(phase)
					if MainState.GraphEditor then
						MainState.GraphEditor.invalidate()
					end

					if phase ~= "preview" then
						MainState.currentProjectSaved = false
						if MainState.currentRig then
							self:ApplyPoseAtTime(MainState.currentRig, TimelineState.CurrentTime)
						end
					end
				end,
			})
			local selected = {}
			for _, track in ipairs(model:tracks(motors)) do
				for _, key in ipairs(track.keys) do
					local channels = toDelete[key.keyData]
					if channels and channels[track.channelId] then
						table.insert(selected, { track = track, key = key })
					end
				end
			end

			model:delete(selected)
			TimelineState.SelectedChannelKeyframes = {}
			TimelineState.SelectedKeyframe = nil
			return
		end

		local before, after = {}, {}
		local count, first = 0, math.huge
		for _, key in order do
			local motor, frame = key.Motor, key.Frame
			if not before[motor] then
				before[motor] = self:_snapshotMotorBucket(motor)
				after[motor] = table.clone(before[motor])
			end

			local reset =
				self:ResetDeletedFirstTransformKey(motor, after[motor][frame], toDelete[key])
			local copy = reset or table.clone(after[motor][frame])
			copy.Channels = GraphCurves.clone(copy.Channels or {})
			copy.KeyGroups = GraphCurves.clone(copy.KeyGroups)
			for id in toDelete[key] do
				if not reset then
					copy.Channels[id] = nil
					KeyGroups.set(copy, id, nil)
				end

				count += 1
			end

			if not next(copy.Channels) then
				after[motor][frame] = nil
			else
				local cf = self:_reconstructC0FromKeyData(copy)
				if cf then
					copy.C0 = cf
					copy.ChannelPoseC0 = nil
					copy.Position = cf.Position
					copy.Rotation = cf.Rotation
				end

				after[motor][frame] = copy
			end

			first = math.min(first, frame)
		end

		self:ApplyEditedBuckets(after)
		History.record(

			function()
				self:ApplyEditedBuckets(before)
			end,

			function()
				self:ApplyEditedBuckets(after)
			end,
			count > 1 and "Delete " .. count .. " channel keyframes" or "Delete channel keyframe",
			first
		)
	end

	function Timeline:BindDeleteHotkey()
		if TimelineState._DeleteHotkeyBound then
			return
		end

		TimelineState._DeleteHotkeyBound = true

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if UserInputService:GetFocusedTextBox() then
				return
			end

			if GraphRootState.GraphEditor and GraphRootState.GraphEditor.hasFocus() then
				return
			end

			if MainState.PathEasingEditor and MainState.PathEasingEditor.hasFocus() then
				return
			end

			if gameProcessed then
				return
			end

			if Shortcuts.matches("DeleteKeys", input) then
				local animator = self.refs and self.refs.AnimatorFrame
				if not animator or not animator.Visible then
					return
				end

				local pluginGui = self.refs and self.refs.PluginGui
				if pluginGui and pluginGui:IsA("LayerCollector") and not pluginGui.Enabled then
					return
				end

				self:DeleteSelectedKeyframes()
			end
		end)
	end

	function Timeline:CaptureSelectedKeyframes()
		local selected, whole, masks = {}, {}, {}

		local function current(key)
			local bucket = key and TimelineState.Keyframes[key.Motor]
			local latest = bucket and bucket[key.Frame]
			return latest and latest.C0 and latest or nil
		end

		for _, reference in self:GetSelectedKeyframesList() do
			local key = current(reference)
			if not key or whole[key] then
				continue
			end

			whole[key] = true
			table.insert(selected, key)
		end

		for _, item in self:GetSelectedChannelKeyframesList() do
			local key = current(item.keyData)
			if not key then
				continue
			end

			if not whole[key] then
				if not masks[key] then
					masks[key] = {}
					table.insert(selected, key)
				end

				masks[key][item.channelId] = true
			end
		end

		if #selected == 0 then
			local key = current(TimelineState.SelectedKeyframe)
			if key then
				table.insert(selected, key)
			end
		end

		if #selected == 0 then
			return nil
		end

		local minimum = math.huge
		for _, key in selected do
			minimum = math.min(minimum, key.Frame)
		end

		local clip = {}
		for _, key in selected do
			if key.Motor and key.Frame ~= nil and key.C0 then
				local metadata = clipboardMetadata(key)
				local mask = masks[key]
				if mask then
					self:EnsureChannelsPopulated(key)
					metadata.Channels, metadata.GraphCurves = {}, {}
					metadata.KeyGroups = {}
					for id in mask do
						metadata.KeyGroups[id] = KeyGroups.get(key, id)
					end

					for id in mask do
						local channel = key.Channels and key.Channels[id]
						if channel then
							metadata.Channels[id] = GraphCurves.clone(channel)
						end

						local point = key.GraphCurves and key.GraphCurves[id]
						if point then
							metadata.GraphCurves[id] = GraphCurves.clone(point)
						end
					end
				end

				table.insert(clip, {
					motor = key.Motor,
					part = key.Part or key.Motor.Part1,
					c0 = key.C0,
					worldCFrame = key.WorldCFrame,
					sanitizeName = key.SanitizeName,
					offsetFrame = key.Frame - minimum,
					metadata = metadata,
					channelOnly = mask ~= nil,
				})
			end
		end

		if #clip == 0 then
			return nil
		end

		ClipboardModes.appendDependencies(clip, minimum, clipboardMetadata)
		ClipboardModes.captureTransfer(clip)
		return clip, minimum
	end

	function Timeline:CopySelectedKeyframes()
		const clip, minimum = self:CaptureSelectedKeyframes()
		if not clip then
			return false
		end

		TimelineState._KeyframeClipboard = clip
		return true, minimum
	end

	function Timeline:CopyAllKeyframes()
		local entries = {}
		local minFrame = math.huge

		for motor, bucket in pairs(TimelineState.Keyframes) do
			if motor and motor.Parent then
				for frameNumber, keyData in pairs(bucket) do
					if keyData and keyData.C0 then
						if frameNumber < minFrame then
							minFrame = frameNumber
						end

						table.insert(entries, {
							motor = motor,
							part = keyData.Part or motor.Part1,
							c0 = keyData.C0,
							worldCFrame = keyData.WorldCFrame,
							sanitizeName = keyData.SanitizeName,
							absoluteFrame = frameNumber,
							metadata = clipboardMetadata(keyData),
						})
					end
				end
			end
		end

		if #entries == 0 then
			return 0
		end

		local clip = {}
		for _, e in ipairs(entries) do
			table.insert(clip, {
				motor = e.motor,
				part = e.part,
				c0 = e.c0,
				worldCFrame = e.worldCFrame,
				sanitizeName = e.sanitizeName,
				offsetFrame = e.absoluteFrame - minFrame,
				metadata = e.metadata,
			})
		end

		ClipboardModes.appendDependencies(clip, minFrame, clipboardMetadata)
		ClipboardModes.captureTransfer(clip)
		TimelineState._KeyframeClipboard = clip
		return #clip, minFrame
	end

	local function compatibleRotationPaste(metadata, bucket)
		if not bucket or not next(bucket) then
			return true
		end

		local target = GraphCurves.rotationOrder(bucket)
		local incoming
		for id, point in metadata and metadata.GraphCurves or {} do
			if id:sub(1, 4) == "rot_" or id:sub(1, 5) == "qrot_" then
				incoming = point.RotationOrder or false
				if (incoming or nil) ~= target then
					return false
				end
			end
		end

		if incoming == nil and target then
			for id in metadata and metadata.Channels or {} do
				if id:sub(1, 5) == "qrot_" then
					return false
				end
			end
		end

		return true
	end

	local function rotationPasteError()
		require("Notification").show(
			"PASTE ROTATION",
			"Source and destination use different rotation modes. Choose the same Rotation Mode in the Graph Editor before pasting rotation keys."
		)
		return false
	end

	local function pasteRefused(title, message)
		require("Notification").show(title, message, 3, "KeyframeAction")
		return false
	end

	local function pasteBlocked(title)
		return BlenderEdit.blocked()
			and not pasteRefused(
				title,
				"Eclipse is busy loading a project, drawing, or syncing with Blender. Paste again when it finishes."
			)
	end

	local function nothingCopied(title)
		return pasteRefused(
			title,
			"Nothing is copied yet. Select keys and press " .. Shortcuts.format("Copy") .. " first."
		)
	end

	local function selectionDescriptors()
		local result = {}
		for key in TimelineState.SelectedKeyframes do
			if key.Motor and key.Frame ~= nil then
				table.insert(result, { motor = key.Motor, frame = key.Frame, mask = true })
			end
		end

		for key, channels in TimelineState.SelectedChannelKeyframes do
			if key.Motor and key.Frame ~= nil and not TimelineState.SelectedKeyframes[key] then
				table.insert(
					result,
					{ motor = key.Motor, frame = key.Frame, mask = table.clone(channels) }
				)
			end
		end

		return result
	end

	local function restoreSelection(timeline, descriptors)
		local whole = {}
		for _, item in descriptors do
			local bucket = TimelineState.Keyframes[item.motor]
			local key = bucket and bucket[item.frame]
			if key and item.mask == true then
				table.insert(whole, key)
			end
		end

		timeline:SetSelectedKeyframes(whole)
		for _, item in descriptors do
			local bucket = TimelineState.Keyframes[item.motor]
			local key = bucket and bucket[item.frame]
			if key and item.mask ~= true and not TimelineState.SelectedKeyframes[key] then
				local mask = TimelineState.SelectedChannelKeyframes[key] or {}
				for id in item.mask do
					mask[id] = true
				end

				TimelineState.SelectedChannelKeyframes[key] = mask
				TimelineState.SelectedKeyframe = TimelineState.SelectedKeyframe or key
			end
		end

		timeline:RefreshKeyframeSelectionVisuals()
		timeline:UpdateDeleteButtonState()
	end

	local function pasteMask(entry)
		if not entry.channelOnly then
			return true
		end

		local mask = {}
		for _, field in { "Channels", "GraphCurves" } do
			for id in entry.metadata and entry.metadata[field] or {} do
				mask[id] = true
			end
		end

		return mask
	end

	local function commitPaste(timeline, pasteList, beforeEnd, pasteEnd, anchorFrame, description)
		const motors = {}
		const before = {}
		const after = {}
		for _, snap in pasteList do
			if not motors[snap.motor] then
				motors[snap.motor] = true
				before[snap.motor] = timeline:_snapshotMotorBucket(snap.motor)
			end
		end

		const previous = selectionDescriptors()
		const savedTime = TimelineState.CurrentTime
		const importing = TimelineState._ImportingKeyframes
		timeline:CancelTimelineKeyframeDrag()
		timeline:EnsureTimelineEnd(pasteEnd)
		TimelineState._ImportingKeyframes = true
		local ok, err = xpcall(function()
			for _, snap in pasteList do
				if snap.motor.Parent then
					snap.motor.C0 = snap.c0
				end
			end

			for _, snap in pasteList do
				TimelineState.CurrentTime = snap.frame / TimelineState.FPS
				timeline:RecordKeyframeForMotorAtCurrentTime(
					snap.part,
					snap.motor,
					snap.c0,
					{ PreserveGraph = true, LayerRaw = true, ImportRaw = snap.metadata ~= nil, Frame = snap.frame },
					snap.sanitizeName
				)
				overrideWorldCFrameIfDetached(snap.motor, snap.frame, snap.worldCFrame)
				const bucket = TimelineState.Keyframes[snap.motor]
				const kd = bucket and bucket[snap.frame]
				if kd and snap.metadata then
					const whole = snap.mask == true
					const recordedChannels = whole and kd.Channels or nil
					const recordedGraph = whole and kd.GraphCurves or nil
					applyEasingMetadata(kd, snap.metadata)
					const stale = {}
					if recordedGraph and next(recordedGraph) then
						kd.GraphCurves = kd.GraphCurves or {}
						for id, point in recordedGraph do
							if kd.GraphCurves[id] == nil then
								kd.GraphCurves[id] = point
								table.insert(stale, id)
							end
						end

						GraphCurves.invalidate(bucket)
					end

					restoreChannelsAndRebuild(
						timeline,
						snap.motor,
						snap.frame,
						snap.metadata.Channels,
						recordedChannels
					)
					if #stale > 0 and not kd.GraphOnly and typeof(kd.C0) == "CFrame" then
						GraphCurves.recordPose(bucket, kd, kd.C0, stale)
					end
				end
			end
		end, debug.traceback)
		TimelineState._ImportingKeyframes = importing
		TimelineState.CurrentTime = savedTime

		local function apply(buckets, selection, extended)
			TimelineState.Playing = false
			if extended then
				timeline:EnsureTimelineEnd(pasteEnd)
			end

			LimbIK.clearLive()
			timeline:ApplyEditedBuckets(buckets)
			if not extended and pasteEnd > beforeEnd.frame then
				timeline:ApplyTimelineEnd(beforeEnd)
			end

			restoreSelection(timeline, selection)
		end

		if not ok then
			pcall(apply, before, previous, false)
			warn("Eclipse could not paste keyframes: " .. tostring(err))
			require("Notification").show("PASTE KEYS", "Paste failed, so no keys were changed.")
			return false
		end

		for motor in motors do
			after[motor] = timeline:_snapshotMotorBucket(motor)
		end

		const pasted = {}
		for _, snap in pasteList do
			if not snap.dependency then
				table.insert(pasted, { motor = snap.motor, frame = snap.frame, mask = snap.mask })
			end
		end

		apply(after, pasted, true)
		History.record(function()
			apply(before, previous, false)
		end, function()
			apply(after, pasted, true)
		end, description, anchorFrame)
		return true
	end

	function Timeline:PasteKeyframes(reverse, selectedTarget, reverseSpan)
		if pasteBlocked("PASTE KEYS") then
			return false
		end

		local clip = TimelineState._KeyframeClipboard
		if not clip or #clip == 0 then
			return nothingCopied("PASTE KEYS")
		end

		local message
		clip, message = ClipboardModes.forPaste(clip, selectedTarget)
		if message then
			require("Notification").show("PASTE KEYS", message)
		end

		if #clip == 0 then
			return false
		end

		if reverse then
			local reason
			clip, reason = self:ReverseSelectedKeyframes(clip, reverseSpan)
			if not clip then
				if reason then
					require("Notification").show("REVERSE PASTE", reason)
				end

				return false
			end
		end

		local tl = TimelineState
		local beforeEnd = self:CaptureTimelineEnd()
		local pasteEnd = beforeEnd.frame
		local pasteAnchorFrame = self:TimeToFrame(tl.CurrentTime)

		local pasteList = {}
		local pastedGroups = {}

		for _, entry in ipairs(clip) do
			if entry.part and entry.motor then
				local targetFrame = pasteAnchorFrame + entry.offsetFrame
				if targetFrame >= 0 and targetFrame < math.huge then
					local bucket = tl.Keyframes[entry.motor]
					if not compatibleRotationPaste(entry.metadata, bucket) then
						return rotationPasteError()
					end

					local existing = bucket and bucket[targetFrame]
					table.insert(pasteList, {
						dependency = entry.modeDependency,
						mask = pasteMask(entry),
						motor = entry.motor,
						part = entry.part,
						frame = targetFrame,
						c0 = entry.channelOnly
								and (existing and existing.C0 or self:EvaluateMotorC0(
									entry.motor,
									targetFrame / tl.FPS
								))
							or entry.c0,
						worldCFrame = entry.worldCFrame,
						sanitizeName = entry.sanitizeName,
						metadata = mergeChannelPaste(
							existing,
							metadataForPaste(entry.metadata, targetFrame, pastedGroups),
							entry.channelOnly
						),
					})
				end
			end
		end

		if #pasteList == 0 then
			return pasteRefused("PASTE KEYS", "None of the copied keys can be pasted on the current rig.")
		end

		for _, snap in pasteList do
			pasteEnd = math.max(pasteEnd, snap.frame)
		end

		return commitPaste(
			self,
			pasteList,
			beforeEnd,
			pasteEnd,
			pasteAnchorFrame,
			reverse and "Reverse paste keyframes"
				or (
					(#pasteList > 1) and ("Paste " .. #pasteList .. " keyframes")
					or "Paste keyframe"
				)
		)
	end

	function Timeline:PasteKeyframesFlipped(selectedTarget)
		if pasteBlocked("PASTE FLIPPED") then
			return false
		end

		local function failed(message)
			require("Notification").show("PASTE FLIPPED", message)
			return false
		end

		local clip = TimelineState._KeyframeClipboard
		if not clip or #clip == 0 then
			return failed(
				"Copy keyframes first ("
					.. Shortcuts.format("Copy")
					.. "). Paste Flipped mirrors the copied keys at the playhead."
			)
		end

		local message
		clip, message = ClipboardModes.forPaste(clip, selectedTarget)
		if message then
			require("Notification").show("PASTE KEYS", message)
		end

		if #clip == 0 then
			return false
		end

		local rig = ownerRig(clip[1].motor, nil)
		if not rig then
			return failed("Select the rig whose copied keys you want to paste.")
		end

		local tl = TimelineState
		local beforeEnd = self:CaptureTimelineEnd()
		local pasteEnd = beforeEnd.frame
		local pasteAnchorFrame = self:TimeToFrame(tl.CurrentTime)

		local pasteList = {}
		local pastedGroups = {}
		local outsideRange, missingMirror = 0, 0

		for _, entry in ipairs(clip) do
			if entry.part and entry.motor then
				local targetFrame = pasteAnchorFrame + entry.offsetFrame
				if not (targetFrame >= 0 and targetFrame < math.huge) then
					outsideRange += 1
				end

				if targetFrame >= 0 and targetFrame < math.huge then
					local sourceRig = ownerRig(entry.motor, rig)
					local flipPose = not CameraRig.isRig(sourceRig)
						and not Properties.is(entry.motor)
						and not (typeof(entry.motor) == "Instance" and entry.motor:GetAttribute(
							"EclipseAddedObject"
						) == true)
						and not (
							type(entry.motor) == "table" and entry.motor.IsEclipseMasterControl
						)
					local mirrorPart = flipPose
							and findMirroredPart(sourceRig, entry.part.Name, entry.part)
						or nil
					local mirrorMotor = mirrorPart and findMotorForPart(sourceRig, mirrorPart)
						or nil
					if R6Controls.isControl(entry.part) then
						local ownerPart = findMirroredPart(
							sourceRig,
							entry.motor.Owner.Part1.Name,
							entry.motor.Owner.Part1
						)
						local owner = ownerPart and findMotorForPart(sourceRig, ownerPart)
						local chain = owner and LimbIK.chain(sourceRig, owner)
						if chain then
							LimbIK.prepare(chain)
							mirrorPart =
								R6Controls.find(owner, entry.part:GetAttribute("EclipseR6Control"))
							mirrorMotor = mirrorPart and R6Controls.get(mirrorPart)
							self:CaptureDefaultPoseAdditive(sourceRig)
						elseif ownerPart ~= entry.motor.Owner.Part1 then
							mirrorPart, mirrorMotor = nil, nil
						end
					end

					if not mirrorMotor and flipPose then
						missingMirror += 1
						continue
					end

					if not mirrorMotor then
						mirrorPart = entry.part
						mirrorMotor = entry.motor
					end

					local newC0 = entry.c0
					if flipPose then
						newC0 = mirrorPose(entry.c0, entry.motor, mirrorMotor, sourceRig)
					end

					local newWorldCFrame = entry.worldCFrame
					if flipPose then
						newWorldCFrame = mirrorWorldCFrameAcrossRig(
							entry.worldCFrame,
							sourceRig,
							entry.metadata and entry.metadata.MirrorOrigin
						)
					end

					local metadata = metadataForPaste(entry.metadata, targetFrame, pastedGroups)
					if metadata and flipPose then
						metadata.WorldCFrame = newWorldCFrame
						for _, field in { "PathTangentIn", "PathTangentOut" } do
							if metadata[field] then
								local moved = mirrorPose(
									entry.c0 + metadata[field],
									entry.motor,
									mirrorMotor,
									sourceRig
								)
								metadata[field] = moved.Position - newC0.Position
							end
						end

						if metadata.ChannelPoseC0 then
							metadata.ChannelPoseC0 = mirrorPose(
								metadata.ChannelPoseC0,
								entry.motor,
								mirrorMotor,
								sourceRig
							)
						end


						if not CameraRig.isFov(entry.motor) then
							mirrorGraph(
								self,
								metadata,
								entry.c0,
								entry.motor,
								mirrorMotor,
								sourceRig
							)
						end

						for _, field in
							{
								"IKTarget",
								"IKPole",
								"IKBaseWorld",
								"IKAnchor",
								"IKRigWorld",
								"IKRoot",
							}
						do
							metadata[field] = mirrorWorldCFrameAcrossRig(
								metadata[field],
								sourceRig,
								metadata.MirrorOrigin
							)
						end

						local curve = metadata.BlenderCurve
						if curve then
							local from, to = curve.from or entry.c0, curve.to or entry.c0
							if curve.from then
								curve.from =
									mirrorPose(curve.from, entry.motor, mirrorMotor, sourceRig)
							end

							if curve.to then
								curve.to = mirrorPose(curve.to, entry.motor, mirrorMotor, sourceRig)
							end

							for _, sample in curve.samples or {} do
								sample.value =
									mirrorPose(sample.value, entry.motor, mirrorMotor, sourceRig)
							end

							for _, pair in
								{ { curve.signature, from }, { curve.nextSignature, to } }
							do
								if pair[1] and pair[1].graph then
									mirrorGraph(
										self,
										{ GraphCurves = pair[1].graph },
										pair[2],
										entry.motor,
										mirrorMotor,
										sourceRig
									)
								end
							end
						end

						if metadata.HSLocalRotation then
							metadata.HSLocalRotation = mirrorC0(metadata.HSLocalRotation)
						end

						if metadata.HSRotation then
							metadata.HSRotation = mirrorWorldCFrameAcrossRig(
								metadata.HSRotation,
								sourceRig,
								metadata.MirrorOrigin
							).Rotation
						end

						if metadata.IKBaseC0 then
							metadata.IKBaseC0 =
								mirrorPose(metadata.IKBaseC0, entry.motor, mirrorMotor, sourceRig)
						end
					end

					local bucket = tl.Keyframes[mirrorMotor]
					if not compatibleRotationPaste(metadata, bucket) then
						return rotationPasteError()
					end

					local existing = bucket and bucket[targetFrame]
					table.insert(pasteList, {
						dependency = entry.modeDependency,
						mask = pasteMask(entry),
						motor = mirrorMotor,
						part = mirrorPart,
						frame = targetFrame,
						c0 = entry.channelOnly
								and (existing and existing.C0 or self:EvaluateMotorC0(
									mirrorMotor,
									targetFrame / tl.FPS
								))
							or newC0,
						worldCFrame = newWorldCFrame,
						sanitizeName = entry.sanitizeName,
						metadata = mergeChannelPaste(existing, metadata, entry.channelOnly),
					})
				end
			end
		end

		if #pasteList == 0 then
			if outsideRange > 0 and missingMirror == 0 then
				return failed(
					"The copied keys fall outside the timeline. Move the playhead or extend the animation."
				)
			end

			return failed(
				"No matching mirrored bones were found. Check the rig and its left/right bone names."
			)
		end

		for _, snap in pasteList do
			pasteEnd = math.max(pasteEnd, snap.frame)
		end

		return commitPaste(
			self,
			pasteList,
			beforeEnd,
			pasteEnd,
			pasteAnchorFrame,
			(#pasteList > 1) and ("Paste " .. #pasteList .. " keyframes flipped")
				or "Paste keyframe flipped"
		)
	end

	local function reverseKeys(self, clipboard, reverseSpan)
		if BlenderEdit.blocked() then
			return false
		end

		local tl = TimelineState
		local selection, masks = {}, {}
		local clipBuckets = {}
		if clipboard then
			for _, entry in clipboard do
				local key = GraphCurves.clone(entry.metadata or {})
				key.Motor, key.Part, key.C0 = entry.motor, entry.part, entry.c0
				key.WorldCFrame = entry.worldCFrame
				key.Frame, key.Time = entry.offsetFrame, entry.offsetFrame / tl.FPS
				clipBuckets[entry.motor] = clipBuckets[entry.motor] or {}
				clipBuckets[entry.motor][key.Frame] = key
				if entry.channelOnly then
					local mask = {}
					for id in key.Channels or {} do
						mask[id] = true
					end

					for id in key.GraphCurves or {} do
						mask[id] = true
					end

					masks[key] = mask
				else
					selection[key] = true
				end
			end
		else
			for _, key in self:GetSelectedKeyframesList() do
				selection[key] = true
			end

			for _, item in self:GetSelectedChannelKeyframesList() do
				if not selection[item.keyData] then
					masks[item.keyData] = masks[item.keyData] or {}
					masks[item.keyData][item.channelId] = true
				end
			end
		end

		local minimum, maximum = math.huge, -math.huge
		local byMotor = {}
		for _, set in { selection, masks } do
			for key in set do
				minimum, maximum = math.min(minimum, key.Frame), math.max(maximum, key.Frame)
				byMotor[key.Motor] = byMotor[key.Motor] or {}
				byMotor[key.Motor][key.Frame] = masks[key] or true
			end
		end

		if clipboard and reverseSpan and next(byMotor) then
			minimum, maximum = 0, reverseSpan
		end

		if minimum >= maximum then
			if clipboard then
				return clipboard
			end

			return false,
				next(byMotor) == nil and "Select the keys you want to reverse."
					or "Select keys on at least two different frames to reverse them."
		end

		local pivot = minimum + maximum
		local before, after = {}, {}

		local function copyKey(key)
			local copy = table.clone(key)
			for _, field in
				{
					"PhysicsLead",
					"Channels",
					"GraphCurves",
					"BezierPoints",
					"WholePoseScale",
					"BlenderCurve",
					"KeyGroups",
				}
			do
				copy[field] = GraphCurves.clone(key[field])
			end

			return copy
		end

		local function reverseEase(target, original)
			for _, field in
				{
					"QuaternionInterpolationVersion",
					"EasingStyle",
					"EasingDirection",
					"Overshoot",
					"Amplitude",
					"Period",
					"MoonEasing",
					"BezierPoints",
				}
			do
				target[field] = GraphCurves.clone(original[field])
			end

			local style = typeof(target.EasingStyle) == "EnumItem" and target.EasingStyle.Name
				or target.EasingStyle
			local direction = typeof(target.EasingDirection) == "EnumItem"
					and target.EasingDirection.Name
				or target.EasingDirection
			if direction == nil or direction == "Automatic" then
				direction = (style == "Back" or style == "Elastic" or style == "Bounce") and "Out"
					or "In"
			end

			target.EasingDirection = direction == "In" and "Out"
				or direction == "Out" and "In"
				or direction
			if style == "Constant" and typeof(target.EasingStyle) ~= "EnumItem" then
				target.EasingStyle, target.EasingDirection = Enum.PoseEasingStyle.Constant, "In"
			end

			if target.BezierPoints then
				local p = target.BezierPoints
				target.BezierPoints = { 1 - p[3], 1 - p[4], 1 - p[1], 1 - p[2] }
			end
		end

		for motor, chosen in byMotor do
			local source = clipboard and clipBuckets[motor] or self:_snapshotMotorBucket(motor)
			before[motor] = source
			local channelIds = {}
			for _, mask in chosen do
				if mask ~= true then
					for id in mask do
						channelIds[id] = true
					end
				end
			end

			if next(channelIds) then
				local working = {}
				for frame, key in source do
					working[frame] = copyKey(key)
				end

				local state = table.clone(tl)
				state.Keyframes = { [motor] = working }
				local proxy = setmetatable({
					GetState = function()
						return state
					end,
				}, { __index = self })
				local model = require("GraphModel").new({ Timeline = proxy })
				for _, track in model:tracks({ motor }) do
					if channelIds[track.channelId] then
						model:_adopt(track)
					end
				end

				source = working
			end

			local output = {}
			for frame, key in source do
				output[frame] = copyKey(key)
			end

			after[motor] = output

			for frame, mask in chosen do
				local dest, occupied = pivot - frame, source[pivot - frame]
				local moving = chosen[dest]
				if occupied then
					if mask == true then
						if moving ~= true then
							return false,
								"Reverse would overwrite unselected keys. Select those keys too."
						end
					elseif moving ~= true then
						for id in mask do
							if
								not (moving and moving[id])
								and (
									(occupied.GraphCurves and occupied.GraphCurves[id])
									or (occupied.Channels and occupied.Channels[id])
								)
							then
								return false,
									"Reverse would overwrite an unselected channel key. Select it too."
							end
						end
					end
				end
			end

			for frame, mask in chosen do
				if mask == true then
					output[frame] = nil
				else
					local key = output[frame]
					for id in mask do
						if key.Channels then
							key.Channels[id] = nil
						end

						if key.GraphCurves then
							key.GraphCurves[id] = nil
						end

						KeyGroups.set(key, id, nil)
					end
				end
			end

			local frames = {}
			for frame in chosen do
				table.insert(frames, frame)
			end

			table.sort(frames)
			local compiled = GraphCurves.compile(source)
			for index, frame in frames do
				local mask, old, dest = chosen[frame], source[frame], pivot - frame
				local moved = copyKey(old)
				moved.Frame, moved.Time = dest, dest / tl.FPS
				moved.PathTangentIn = old.PathTangentOut and -old.PathTangentOut
				moved.PathTangentOut = old.PathTangentIn and -old.PathTangentIn
				if index > 1 then
					reverseEase(moved, source[frames[index - 1]])
				end

				for id, point in moved.GraphCurves or {} do
					if mask == true or mask[id] then
						local channel = compiled.channels[id]
						for i, entry in channel or {} do
							if entry.frame == frame then
								local left, right = GraphCurves.pointHandles(channel, i)
								point.In = { -(right.time - entry.time), right.value - point.Value }
								point.Out = { -(left.time - entry.time), left.value - point.Value }
								point.BlenderHandles = {
									mode = point.HandleType or "AutoClamped",
									incoming = GraphCurves.clone(point.In),
									outgoing = GraphCurves.clone(point.Out),
								}
								local previous = channel[i - 1]
								if
									previous
									and chosen[previous.frame]
									and (
										chosen[previous.frame] == true
										or chosen[previous.frame][id]
									)
								then
									local p = previous.point
									point.Interpolation = p.Interpolation
									point.Easing = GraphCurves.clone(p.Easing)
									if not point.Easing then
										point.Easing = {}
										for _, field in
											{
												"QuaternionInterpolationVersion",
												"EasingStyle",
												"EasingDirection",
												"BezierPoints",
												"Overshoot",
												"Amplitude",
												"Period",
												"MoonEasing",
											}
										do
											point.Easing[field] =
												GraphCurves.clone(previous.key[field])
										end
									end

									point.Easing.Reversed = not point.Easing.Reversed or nil
									if p.Interpolation == "Constant" then
										point.Interpolation = "ConstantNext"
									elseif p.Interpolation == "ConstantNext" then
										point.Interpolation = "Constant"
									end
								end

								break
							end
						end
					end
				end

				if mask == true then
					output[dest] = moved
				else
					local target = output[dest]
					if not target then
						target = copyKey(moved)
						target.Channels, target.GraphCurves, target.GraphOnly = {}, {}, true
						target.KeyGroups = nil
						output[dest] = target
					end

					target.Channels, target.GraphCurves =
						target.Channels or {}, target.GraphCurves or {}
					for id in mask do
						KeyGroups.set(target, id, KeyGroups.get(moved, id))
						target.Channels[id] = moved.Channels and moved.Channels[id]
						target.GraphCurves[id] = moved.GraphCurves and moved.GraphCurves[id]
						if target.GraphCurves[id] then
							target.Channels[id] = nil
						end
					end

					if next(target.Channels) then
						target.GraphOnly = nil
					end
				end
			end

			for frame, key in output do
				if
					key.GraphOnly
					and not next(key.GraphCurves or {})
					and not next(key.Channels or {})
				then
					output[frame] = nil
				end
			end
		end

		if clipboard then
			local reversed = {}
			for _, entry in clipboard do
				local copy = table.clone(entry)
				copy.offsetFrame = pivot - entry.offsetFrame
				local key = after[entry.motor][copy.offsetFrame]
				copy.metadata = extractKeyframeMetadata(key)
				table.insert(reversed, copy)
			end

			return reversed
		end

		local function restore(snapshots, reversed)
			tl.Playing = false
			self:ClearSelectedKeyframes()
			self:ApplyEditedBuckets(snapshots)

			for motor, chosen in byMotor do
				for frame, mask in chosen do
					local key = tl.Keyframes[motor][reversed and pivot - frame or frame]
					if key then
						if mask == true then
							tl.SelectedKeyframes[key] = true
						else
							tl.SelectedChannelKeyframes[key] = GraphCurves.clone(mask)
						end

						tl.SelectedKeyframe = tl.SelectedKeyframe or key
					end
				end
			end

			self:RefreshKeyframeSelectionVisuals()
			self:UpdateDeleteButtonState()
		end

		restore(after, true)
		History.record(function()
			restore(before, false)
		end, function()
			restore(after, true)
		end, "Reverse selected keys", minimum)
		return true
	end

	function Timeline:ReverseSelectedKeyframes(clipboard, reverseSpan)
		const result, reason = reverseKeys(self, clipboard, reverseSpan)
		if not clipboard and reason then
			require("Notification").show("REVERSE KEYS", reason, 3, "KeyframeAction")
		end

		return result, reason
	end

	function Timeline:BindCopyPasteHotkeys()
		if TimelineState._CopyPasteHotkeyBound then
			return
		end

		TimelineState._CopyPasteHotkeyBound = true

		local function neutralizeStudioSelection()
			if #Selection:Get() == 0 then
				return
			end

			const ignore = MainState.ignoreSelectionChanged
			MainState.ignoreSelectionChanged = true
			Selection:Set({})
			MainState.ignoreSelectionChanged = ignore
		end

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if GraphRootState.GraphEditor and GraphRootState.GraphEditor.hasFocus() then
				return
			end

			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			local copy = Shortcuts.matches("Copy", input)
			local paste = Shortcuts.matches("Paste", input)
			local flipped = Shortcuts.matches("PasteFlipped", input)
			if not copy and not paste and not flipped then
				return
			end

			if not UserInputService.ownsClipboard() then
				const reachable = not UserInputService:GetFocusedTextBox() and require("UI").isAnimatorActive()
				if reachable and not copy then
					require("Notification").show(
						"PASTE KEYS",
						"Studio kept keyboard focus, so nothing was pasted. Click the timeline and press "
							.. Shortcuts.format(flipped and "PasteFlipped" or "Paste")
							.. " again.",
						3,
						"KeyframeAction"
					)
				elseif
					reachable
					and (next(TimelineState.SelectedKeyframes) or next(TimelineState.SelectedChannelKeyframes))
				then
					require("Notification").show(
						"COPY KEYS",
						"Studio kept keyboard focus, so the keys were not copied. Click the timeline and press "
							.. Shortcuts.format("Copy")
							.. " again.",
						3,
						"KeyframeAction"
					)
				end

				return
			end

			local pluginGui = self.refs and self.refs.PluginGui
			if not pluginGui or not pluginGui.Enabled then
				return
			end

			local focusedBox = UserInputService:GetFocusedTextBox()
			if focusedBox then
				return
			end

			const title = copy and "COPY KEYS" or "PASTE KEYS"
			const ok, result = xpcall(function()
				if copy then
					const copied = self:CopySelectedKeyframes()
					neutralizeStudioSelection()
					return copied
				end

				const pasteTarget = require("SelectedRig").resolve(MainState, false)
				neutralizeStudioSelection()
				TimelineState.Playing = false
				if flipped then
					return self:PasteKeyframesFlipped(pasteTarget or false)
				end

				return self:PasteKeyframes(nil, pasteTarget or false)
			end, debug.traceback)
			if not ok then
				warn("Eclipse " .. title:lower() .. " failed: " .. tostring(result))
				require("Notification").show(title, "This action failed and nothing was changed. Details are in the Output window.")
			elseif result then
				if not copy then
					MainState.currentProjectSaved = false
				end

				require("Notification").show("NOTIFICATION", copy and "Copied keyframes" or "Pasted keyframes", 1.5, "KeyframeAction")
			end
		end)
	end
end
