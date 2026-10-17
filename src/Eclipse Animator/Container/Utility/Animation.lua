--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Paths = require("Paths")
local Codec = require("ArmatureAnimation")
local ValueCodec = require("ValueCodec")
local Armature = require("ArmatureRuntime")
local Parenting = require("Parenting")
local Master = require("MasterControl")
local Events = require("Events")
local History = require("History")
local LimbIK = require("LimbIK")
local Animation = {}

local r15Parents = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
}

local function r15Motors(rig)
	local result = {}
	for _, motor in Parenting.collectMotors(rig) do
		if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local name = motor.Part1.Name
			if r15Parents[name] then
				if result[name] or motor.Part0.Name ~= r15Parents[name] then
					return nil
				end

				result[name] = motor
			end
		end
	end

	for name in r15Parents do
		if not result[name] then
			return nil
		end
	end

	return result
end

local function r15Name(path)
	if type(path) ~= "string" or path:sub(1, 1) ~= "[" then
		return nil
	end

	local ok, steps =
		pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), path)
	local last = ok and type(steps) == "table" and steps[#steps]
	return type(last) == "table" and last[2] ~= "Bone" and r15Parents[last[1]] and last[1] or nil
end

local function r15Source(data)
	local names = {}
	for path in data.native or {} do
		local name = r15Name(path)
		if name then
			if names[name] then
				return false
			end

			names[name] = true
		end
	end

	for name in r15Parents do
		if not names[name] then
			return false
		end
	end

	return true
end

local function r15ScaleRatio(data, rig, motors)
	if type(data.scale) == "number" and data.scale > 0 and data.scale < math.huge then
		return require("PoseSpace").getRigScale(rig) / data.scale
	end

	local ratio
	for path, values in data.native or {} do
		local name = r15Name(path)
		local motor = name and motors and motors[name]
		if motor and typeof(values.size) == "Vector3" then
			for _, axis in { "X", "Y", "Z" } do
				if values.size[axis] <= 0 then
					return 1
				end

				local value = motor.Part1.Size[axis] / values.size[axis]
				if ratio and math.abs(value - ratio) > 1e-4 then
					return 1
				end

				ratio = value
			end
		end
	end

	return ratio or 1
end

local function rebaseKey(key, source, target, timeline, ratio)
	return require("PoseSpace").rebaseKey(key, source, target, timeline, ratio)
end

local function copy(value)
	return ValueCodec.decode(ValueCodec.encode(value))
end

local function native(rig)
	local values = {}
	local origin = rig:GetPivot()
	for _, object in rig:GetDescendants() do
		if Paths.excluded(object, rig) then
			continue
		end

		if object:IsA("BasePart") and not object:GetAttribute("EclipseArmatureBone") then
			values[Paths.of(object, rig)] =
				{ frame = origin:ToObjectSpace(object.CFrame), size = object.Size }
		elseif object:IsA("Bone") then
			values[Paths.of(object, rig)] = { transform = object.Transform }
		end
	end

	return values
end

local function appearance(rig)
	local values = {}
	for _, object in rig:GetDescendants() do
		if Paths.excluded(object, rig) then
			continue
		end

		if object:IsA("Decal") or object:IsA("Texture") then
			values[Paths.of(object, rig)] = {
				Texture = object.Texture,
				Color3 = object.Color3,
				Transparency = object.Transparency,
				Face = object.Face,
			}
		elseif object:IsA("Shirt") then
			values[Paths.of(object, rig)] = { ShirtTemplate = object.ShirtTemplate }
		elseif object:IsA("Pants") then
			values[Paths.of(object, rig)] = { PantsTemplate = object.PantsTemplate }
		end
	end

	return values
end

function Animation.capture(rig, timeline, kind, buildPreview, selectedMotors)
	local state = timeline:GetState()
	local data = {
		version = 1,
		kind = kind,
		fps = state.FPS,
		sourceFrame = timeline:TimeToFrame(state.CurrentTime),
		scale = require("PoseSpace").getRigScale(rig),
		origin = rig:GetPivot(),
		tracks = {},
		native = native(rig),
		appearance = appearance(rig),
		preview = {},
	}
	local master = Master.get(rig, true)
	data.master = (not selectedMotors or selectedMotors[master])
			and master
			and Master.enabled(rig)
			and {
				enabled = true,
				rest = master.DefaultC0,
				radius = rig:GetAttribute("EclipseMasterRadius"),
			}
		or nil
	local last = 0
	for _, motor in Parenting.collectMotors(rig) do
		if selectedMotors and not selectedMotors[motor] then
			continue
		end

		local id = Paths.motor(motor, rig)
		if not id then
			continue
		end

		local track = { id = id, default = state.DefaultPose[motor] or motor.C0, keys = {} }
		if typeof(motor) == "table" and motor.IsEclipseR6Control then
			track.control = {
				customRest = require("customRest").rest(motor.Owner),
				customIK = motor.Owner:GetAttribute("EclipseAutoIK") == true or nil,
				owner = Paths.motor(motor.Owner, rig),
				kind = motor:GetAttribute("EclipseR6Control"),
				rest = motor.Bone.CFrame,
			}
		end

		if kind == "Poses" then
			local key = {
				C0 = motor.C0,
				Time = 0,
				Frame = 0,
				Parented = Parenting.isParentedAt(
					motor,
					state.Keyframes[motor],
					state.CurrentTime,
					state.ParentingDefaults[motor]
				),
				EasingStyle = "Linear",
			}
			if not key.Parented then
				key.WorldCFrame = Parenting.worldOf(motor, state.MotorByPart)
				key.MasterWorld = Master.worldDelta(motor)
			end

			local previous = Parenting.bounds(state.Keyframes[motor], state.CurrentTime)
			if previous then
				for _, field in
					{
						"CamTargetAnchor",
						"HS",
						"HSRotation",
						"HSLocalRotation",
						"HSRestoreParented",
					}
				do
					key[field] = previous[field]
				end
			end

			local chain = LimbIK.chain(rig, motor)
			if chain then
				key.IK = LimbIK.isEnabled(motor, state.CurrentTime)
				if key.IK then
					LimbIK.state(chain, state.CurrentTime)
				end
			end

			key.Time = state.CurrentTime
			LimbIK.captureKey(motor, key)
			key.Time = 0
			local part = motor.Part1
			local size = state.DefaultSize and state.DefaultSize[part]
			local scale
			if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
				scale = motor.InputScale
			elseif size and part:IsA("BasePart") then
				scale = part.Size / size
			end

			if scale then
				key.Channels = {}
				for id, value in timeline:DecomposeC0(key.C0) do
					key.Channels[id] = { Value = value }
				end

				key.WholePoseScale = { scale_x = scale.X, scale_y = scale.Y, scale_z = scale.Z }
				for id, value in key.WholePoseScale do
					key.Channels[id] = { Value = value }
				end
			end

			track.keys[1] = copy(key)
		else
			for frame, key in state.Keyframes[motor] or {} do
				local value = copy(key)
				value.Frame = frame
				value.Time = frame / state.FPS
				table.insert(track.keys, value)
				last = math.max(last, frame)
			end

			table.sort(track.keys, function(a, b)
				return a.Frame < b.Frame
			end)
		end

		if #track.keys > 0 then
			table.insert(data.tracks, track)
		end
	end

	data.properties = kind == "Poses" and Armature.properties(rig) or Codec.propertySnapshot(rig)
	if selectedMotors then
		assert(#data.tracks > 0, "Select at least one bone to save a partial pose.")
		data.partial = true

		data.appearance = {}
		data.properties = {}
	end

	if kind == "Animations" then
		data.events = Events.snapshot(Events.get(rig))
		data.subtitles = Events.snapshot(Events.subtitleTrack())
		for _, event in data.subtitles.Events do
			last = math.max(last, event.Frame + event.Subtitle.Duration)
		end

		for _, event in data.events.Events do
			last = math.max(last, event.Frame + (event.Duration or 0))
		end

		for _, track in data.properties.tracks do
			for _, key in track.keys do
				last = math.max(last, key.frame)
			end
		end

		data.duration = last / state.FPS
		assert(buildPreview, "Animation preview isn't ready.")
		local sequence = buildPreview(rig, function(motor, key, frame, c0, baked)
			local path = Paths.of(motor.Part1, rig)
			if not path then
				return
			end

			local track = data.preview[path]
			if not track then
				track = {}
				data.preview[path] = track
			end

			local sample = copy(key)
			sample.C0 = c0
			sample.Time = frame / state.FPS
			sample.Frame = frame
			if baked then
				sample.EasingStyle = "Linear"
				sample.HandleType = "Vector"
			end

			table.insert(track, sample)
		end)
		if sequence then
			sequence:Destroy()
		end

		for _, track in data.preview do
			table.sort(track, function(a, b)
				return a.Time < b.Time
			end)
		end
	end

	return data
end

local worldFrames = {
	WorldCFrame = true,
	CamTargetAnchor = true,
	IKAnchor = true,
	IKRigWorld = true,
	IKRoot = true,
	IKBaseWorld = true,
}
local worldPoints = { IKTarget = true, IKPole = true }

local function resolveTracks(data, rig, motors)
	local plans = {}
	local kinds = {
		root = "IK",
		spine = "Spine",
		upper = "UpperTorso",
		target = "IKTarget",
		pole = "IKPole",
		roll = "FootRoll",
	}
	local Http = game:GetService("HttpService")
	for _, track in data.tracks do
		if (motors[track.id] and not track.control) or track.id == "master" and data.master then
			continue
		end

		local control = track.control
		if not control then
			local ok, path = pcall(Http.JSONDecode, Http, track.id)
			if ok and type(path) == "table" and #path > 1 then
				local last = path[#path]
				if type(last) == "table" and last[2] == "Bone" and last[3] == 1 then
					for kind, name in kinds do
						if last[1] == name then
							local parent = table.clone(path)
							table.remove(parent)
							control = {
								owner = Http:JSONEncode(parent),
								kind = kind,
								rest = track.default,
							}
							break
						end
					end
				end
			end
		end

		local owner = control and motors[control.owner]
		assert(
			control
				and kinds[control.kind]
				and typeof(control.rest) == "CFrame"
				and require("customRest").isJoint(owner),
			"This save uses different bones. Insert its rig from the card menu, or select a matching rig."
		)

		local existing =
			owner.Part1:FindFirstChild(require("R6Controls").controlName(owner, control.kind))
		assert(
			not existing
				or existing:IsA("Bone")
					and existing:GetAttribute("EclipseR6Control") == control.kind,
			"This save's IK control conflicts with an existing bone."
		)
		if control.customIK then
			assert(
				require("customRest").chain(rig, owner, Parenting.collectMotors(rig)),
				"Saved custom IK chain is no longer connected"
			)
		end

		table.insert(plans, {
			track = track,
			owner = owner,
			kind = control.kind,
			rest = control.rest,
			customIK = control.customIK,
			customRest = control.customRest,
		})
	end

	return plans
end

function Animation.apply(data, rig, timeline, sanitize, refreshStructure)
	local state = timeline:GetState()
	local at = timeline:TimeToFrame(state.CurrentTime)
	local targetOrigin = rig:GetPivot()
	local worldDelta = targetOrigin * data.origin:Inverse()
	local motors = {}
	for _, motor in Parenting.collectMotors(rig) do
		local id = Paths.motor(motor, rig)
		if id then
			motors[id] = motor
		end
	end

	local r15 = r15Source(data) and r15Motors(rig)
	local poseRatio = r15 and r15ScaleRatio(data, rig, r15) or 1
	if r15 then
		for _, track in data.tracks do
			local name = r15Name(track.id)
			if name and not track.control and not motors[track.id] then
				motors[track.id] = r15[name]
			end

			if track.control then
				local ownerName = r15Name(track.control.owner)
				if ownerName and not motors[track.control.owner] then
					motors[track.control.owner] = r15[ownerName]
				end
			end
		end
	end

	local controlPlans = resolveTracks(data, rig, motors)
	local customOwners = {}
	for _, plan in controlPlans do
		if plan.customIK and not customOwners[plan.owner] then
			customOwners[plan.owner] = {
				before = plan.owner:GetAttribute("EclipseAutoIK"),
				beforeRest = require("customRest").rest(plan.owner),
				afterRest = plan.customRest,
			}
		end
	end

	local oldMaster = Master.get(rig, true)
	local beforeMaster = oldMaster and { enabled = Master.enabled(rig), c0 = oldMaster.C0 }
	if data.master and data.master.enabled and not motors.master then
		motors.master = Master.setEnabled(rig, true)
		if motors.master then
			timeline:CaptureDefaultPoseAdditive(rig)
			timeline:InvalidateMotorListCache()
			if refreshStructure then
				refreshStructure(rig)
			end
		end
	end

	local before, after = {}, {}
	local beforeProperties = Codec.propertySnapshot(rig)
	local propertyValues = Armature.isRig(rig) and Armature.snapshot(rig)
	local eventTrack = Events.get(rig)
	local beforeEvents = Events.snapshot(eventTrack)
	local beforeSubtitles = Events.snapshot(Events.subtitleTrack())
	local afterSubtitles
	local changes = {}
	for path, values in data.appearance or {} do
		local object = Paths.resolve(rig, path)
		if object then
			local old = {}
			for key in values do
				old[key] = object[key]
			end

			table.insert(changes, { object = object, before = old, after = values })
		end
	end

	local function restore(buckets, properties, events, which)
		for owner, values in customOwners do
			if which == "before" then
				owner:SetAttribute("EclipseAutoIK", values.before)
				require("customRest").restoreRest(owner, values.beforeRest)
			else
				owner:SetAttribute("EclipseAutoIK", true)
				require("customRest").restoreRest(owner, values.afterRest)
			end
		end

		if next(customOwners) then
			LimbIK.invalidate(rig)
		end

		for motor, bucket in buckets do
			timeline:_restoreMotorBucket(motor, bucket)
		end

		Codec.restoreProperties(rig, properties)
		Events.restore(eventTrack, events)
		Events.restore(
			Events.subtitleTrack(),
			which == "before" and beforeSubtitles or afterSubtitles
		)
		for _, change in changes do
			if change.object.Parent then
				for key, value in change[which] do
					change.object[key] = value
				end
			end
		end

		if which == "before" then
			if beforeMaster then
				Master.setEnabled(rig, beforeMaster.enabled)
				Master.get(rig, true).C0 = beforeMaster.c0
			elseif motors.master then
				Master.setEnabled(rig, false)
			end

			if propertyValues then
				Armature.restore(rig, propertyValues)
			end
		elseif data.master then
			Master.setEnabled(rig, data.master.enabled)
		end

		timeline:InvalidateMotorListCache()
		if refreshStructure and (data.master or next(customOwners)) then
			refreshStructure(rig)
		end

		timeline:ApplyPoseAtTime(rig, state.CurrentTime, { OnlyRig = true })
	end

	local createdControls = {}
	local ok, err = xpcall(function()
		local Controls = require("R6Controls")
		for owner, values in customOwners do
			owner:SetAttribute("EclipseAutoIK", true)
			require("customRest").restoreRest(owner, values.afterRest)
		end

		if next(customOwners) then
			LimbIK.invalidate(rig)
		end

		for _, plan in controlPlans do
			local existing = Controls.find(plan.owner, plan.kind)
			local bone = Controls.ensure(plan.owner, plan.kind, plan.rest)
			if not existing then
				table.insert(createdControls, bone)
			end

			motors[plan.track.id] = assert(Controls.get(bone), "Could not create saved IK control")
		end

		if #controlPlans > 0 then
			timeline:CaptureDefaultPoseAdditive(rig)
			timeline:InvalidateMotorListCache()
			if refreshStructure then
				refreshStructure(rig)
			end
		end

		for _, track in data.tracks do
			local motor = assert(motors[track.id], "This rig doesn't have a master control.")
			before[motor] = timeline:_snapshotMotorBucket(motor)
			local combined = table.clone(before[motor])
			for _, saved in track.keys do
				local key = copy(saved)
				if r15 and r15[motor.Part1.Name] == motor and typeof(track.default) == "CFrame" then
					rebaseKey(
						key,
						track.default,
						state.DefaultPose[motor] or motor.C0,
						timeline,
						poseRatio
					)
				end

				if key.MasterWorld then
					key.MasterWorld = worldDelta * key.MasterWorld * worldDelta:Inverse()
				end

				local frame = at
					+ (data.kind == "Poses" and 0 or math.round(saved.Time * state.FPS))
				for field in worldFrames do
					if typeof(key[field]) == "CFrame" then
						key[field] = worldDelta * key[field]
					end
				end

				for field in worldPoints do
					local value = key[field]
					if typeof(value) == "CFrame" then
						key[field] = worldDelta * value
					elseif typeof(value) == "Vector3" then
						key[field] = worldDelta:PointToWorldSpace(value)
					end
				end

				if typeof(key.HSRotation) == "CFrame" then
					key.HSRotation = worldDelta.Rotation * key.HSRotation
				end

				if key.Parented == false then
					for _, field in { "PathTangentIn", "PathTangentOut" } do
						if key[field] then
							key[field] = worldDelta:VectorToWorldSpace(key[field])
						end
					end
				end

				key.Frame, key.Time, key.Motor, key.Part, key.SanitizeName =
					frame, frame / state.FPS, motor, motor.Part1, sanitize
				if key.C0 then
					key.Position, key.Rotation = key.C0.Position, key.C0.Rotation
				end

				for _, curve in key.GraphCurves or {} do
					if curve.In then
						curve.In[1] *= state.FPS / data.fps
					end

					if curve.Out then
						curve.Out[1] *= state.FPS / data.fps
					end
				end

				combined[frame] = key
				timeline:EnsureTimelineEnd(frame)
			end

			timeline:_restoreMotorBucket(motor, combined)
			after[motor] = timeline:_snapshotMotorBucket(motor)
		end

		local properties = copy(beforeProperties)
		local byId = {}
		for _, track in properties.tracks do
			byId[track.id] = track
		end

		local incoming = {}
		if data.kind == "Poses" then
			for _, property in data.properties do
				local id = game:GetService("HttpService")
					:JSONEncode({ property.object, property.bone or "", property.key })
				table.insert(incoming, {
					id = id,
					object = property.object,
					bone = property.bone,
					key = property.key,
					default = property.default,
					keys = { { frame = 0, value = property.value } },
				})
			end
		else
			incoming = data.properties.tracks
		end

		for _, saved in incoming do
			local track = byId[saved.id]
			if not track then
				track = copy(saved)
				track.keys = {}
				table.insert(properties.tracks, track)
				byId[track.id] = track
			end

			for _, key in saved.keys do
				local frame = at + math.round(key.frame / data.fps * state.FPS)
				for i = #track.keys, 1, -1 do
					if track.keys[i].frame == frame then
						table.remove(track.keys, i)
					end
				end

				table.insert(track.keys, { frame = frame, value = key.value })
				timeline:EnsureTimelineEnd(frame)
			end

			table.sort(track.keys, function(a, b)
				return a.frame < b.frame
			end)
		end

		Codec.restoreProperties(rig, properties)
		if data.events then
			for _, event in data.events.Events do
				local item = copy(event)
				item.Id = game:GetService("HttpService"):GenerateGUID(false)
				item.Frame =
					Events.nextFrame(eventTrack, at + math.round(item.Frame / data.fps * state.FPS))
				item.Duration = math.round((item.Duration or 0) / data.fps * state.FPS)
				item.Subtitle = require("SubtitleData").rescale(item.Subtitle, state.FPS / data.fps)
				eventTrack.Events[item.Id] = item
				timeline:EnsureTimelineEnd(item.Frame + item.Duration)
			end

			Events.migrateSubtitles(eventTrack)
			Events.changed(eventTrack)
		end

		local subtitleTrack = Events.subtitleTrack()
		for _, event in data.subtitles and data.subtitles.Events or {} do
			local item = copy(event)
			item.Id = game:GetService("HttpService"):GenerateGUID(false)
			item.Frame = at + math.round(item.Frame / data.fps * state.FPS)
			item.Subtitle = require("SubtitleData").rescale(item.Subtitle, state.FPS / data.fps)
			subtitleTrack.Events[item.Id] = item
			timeline:EnsureTimelineEnd(item.Frame + item.Subtitle.Duration)
		end

		if data.events or data.subtitles then
			Events.changed(subtitleTrack)
		end

		afterSubtitles = Events.snapshot(subtitleTrack)
		for _, change in changes do
			for key, value in change.after do
				change.object[key] = value
			end
		end

		timeline:ApplyPoseAtTime(rig, state.CurrentTime, { OnlyRig = true })
		local afterProperties, afterEvents =
			Codec.propertySnapshot(rig), Events.snapshot(eventTrack)
		History.record(function()
			restore(before, beforeProperties, beforeEvents, "before")
		end, function()
			restore(after, afterProperties, afterEvents, "after")
		end, "Insert " .. (data.kind == "Poses" and "pose" or "animation"), at)
	end, debug.traceback)
	if not ok then
		restore(before, beforeProperties, beforeEvents, "before")
		for _, bone in createdControls do
			bone:Destroy()
		end

		timeline:InvalidateMotorListCache()
		if #createdControls > 0 and refreshStructure then
			refreshStructure(rig)
		end

		error(err, 0)
	end

	return true
end

const PUBLISH_CLASSES = {
	KeyframeSequence = true,
	Keyframe = true,
	Pose = true,
	NumberPose = true,
	KeyframeMarker = true,
}

local function weightedPose(pose)
	if pose.Weight > 0 then
		return true
	end

	for _, child in pose:GetChildren() do
		if child:IsA("PoseBase") and weightedPose(child) then
			return true
		end
	end

	return false
end

local function stripForPublish(object)
	for key in object:GetAttributes() do
		object:SetAttribute(key, nil)
	end

	for _, child in object:GetChildren() do
		if not PUBLISH_CLASSES[child.ClassName] or child:IsA("PoseBase") and not weightedPose(child) then
			child:Destroy()
		else
			stripForPublish(child)
		end
	end
end

const PUBLISH_MIN_KEY_GAP = 1 / 70 + 1e-4

Animation.MIN_KEY_GAP = PUBLISH_MIN_KEY_GAP

function Animation.nativeSampleSpacing(fps)
	const framesPerGap = fps * PUBLISH_MIN_KEY_GAP
	if framesPerGap <= 1 then
		return math.max(1, math.floor(1 / framesPerGap)), 1
	end

	return 1, math.ceil(framesPerGap)
end

local function findPose(parent, name, className)
	for _, child in parent:GetChildren() do
		if child.Name == name and child.ClassName == className then
			return child
		end
	end

	return nil
end

local function mergePose(targetParent, pose)
	const existing = findPose(targetParent, pose.Name, pose.ClassName)
	if not existing then
		pose:Clone().Parent = targetParent
		return
	end

	if pose.Weight > 0 and existing.Weight <= 0 then
		existing.Weight = pose.Weight
		existing.EasingStyle = pose.EasingStyle
		existing.EasingDirection = pose.EasingDirection
		if pose:IsA("Pose") then
			existing.CFrame = pose.CFrame
		else
			existing.Value = pose.Value
		end
	end

	for _, child in pose:GetChildren() do
		if child:IsA("PoseBase") then
			mergePose(existing, child)
		end
	end
end

local function mergeKeyframe(target, source)
	for _, child in source:GetChildren() do
		if child:IsA("PoseBase") then
			mergePose(target, child)
		elseif child:IsA("KeyframeMarker") then
			child.Parent = target
		end
	end

	source:Destroy()
end

function Animation.enforceKeySpacing(sequence, minimumGap)
	const gap = minimumGap or PUBLISH_MIN_KEY_GAP
	const keyframes = {}
	for _, child in sequence:GetChildren() do
		if child:IsA("Keyframe") then
			table.insert(keyframes, child)
		end
	end

	if #keyframes < 2 then
		return 0
	end

	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)
	const final = keyframes[#keyframes]
	const kept = {}
	local merged = 0
	for _, keyframe in keyframes do
		const previous = kept[#kept]
		if not previous or keyframe.Time - previous.Time >= gap then
			table.insert(kept, keyframe)
		elseif keyframe == final then
			if #kept > 1 then
				mergeKeyframe(keyframe, previous)
				kept[#kept] = keyframe
				merged += 1
			else
				table.insert(kept, keyframe)
			end
		else
			mergeKeyframe(previous, keyframe)
			merged += 1
		end
	end

	return merged
end

function Animation.publishCopy(sequence)
	const copy = sequence:Clone()
	stripForPublish(copy)
	Animation.enforceKeySpacing(copy)
	return copy
end

local function pivotTrack(rig, timeline)
	if
		typeof(rig) ~= "Instance"
		or not rig:IsA("Model")
		or rig:FindFirstChildOfClass("Humanoid")
		or not timeline
	then
		return nil
	end

	const Properties = require("Properties")
	if Properties.inheritedTransform(rig) then
		return nil
	end

	const raw = timeline:GetState()
	local track
	for _, motor in Properties.list(rig, false, true) do
		if
			motor.PropertyId == "CFrame"
			and not motor:GetAttribute("EclipseDisabled")
			and next(raw.Keyframes[motor] or {})
		then
			track = motor
		end
	end

	return track, track and raw.Keyframes[track]
end

local function rootJoints(rig)
	const driven, joints = {}, {}
	for _, object in require("RigTraversal").rigDescendants(rig) do
		if
			object:IsA("Motor6D")
			and object.Part0
			and object.Part1
			and object.Part0:IsDescendantOf(rig)
			and object.Part1:IsDescendantOf(rig)
		then
			driven[object.Part1] = true
			table.insert(joints, object)
		end
	end

	const roots = {}
	for _, joint in joints do
		if not driven[joint.Part0] then
			roots[joint.Part0] = true
		end
	end

	return roots, driven
end

function Animation.objectMotion(rig, timeline, motorByPart1, motors)
	const track, bucket = pivotTrack(rig, timeline)
	if not track then
		return nil
	end

	const Properties = require("Properties")
	const Target = require("Target")
	local function pivotAt(time)
		const value = Target.hasChild(bucket)
				and Target.childWorld(time, bucket, function(key)
					return Properties.decode(track, key.C0, key.PropertyValue)
				end)
			or Properties.evaluate(track, bucket, time)
		return typeof(value) == "CFrame" and value or nil
	end

	const start = pivotAt(timeline:GetPoseTime(0))
	if not start then
		return nil
	end

	const pivot = rig:GetPivot()
	const roots, offsets = {}, {}
	for _, motor in motors do
		const parent = typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part0
		if parent and motor.Part1 and not motorByPart1[parent] and parent:IsDescendantOf(rig) then
			roots[motor] = parent
			offsets[parent] = pivot:ToObjectSpace(parent.CFrame)
		end
	end

	if not next(roots) then
		return nil
	end

	local last = 0
	for frame, key in bucket do
		if key and frame > last then
			last = frame
		end
	end

	return {
		roots = roots,
		lastFrame = last,
		delta = function(part, time)
			const value = pivotAt(time)
			const offset = offsets[part]
			if not value or not offset then
				return CFrame.identity
			end

			return offset:Inverse() * start:ToObjectSpace(value) * offset
		end,
	}
end

function Animation.exportNotice(rig, timeline)
	if not pivotTrack(rig, timeline) then
		return nil
	end

	const roots, driven = rootJoints(rig)
	if not next(roots) then
		return "Roblox animations can only move Motor6D joints, so this object's CFrame track will not move it in Roblox. Give it a root part joined to its parts with Motor6Ds to export the motion."
	end

	for _, object in require("RigTraversal").rigDescendants(rig) do
		if not (object:IsA("WeldConstraint") or object:IsA("JointInstance") and not object:IsA("Motor6D")) then
			continue
		end

		const a, b = object.Part0, object.Part1
		if a and b and (roots[a] and not driven[b] and not roots[b] or roots[b] and not driven[a] and not roots[a]) then
			return "CFrame track motion was baked into the root Motor6D joints. Parts welded straight to the root part stay still in Roblox; weld them to a jointed part instead."
		end
	end

	return "CFrame track motion was baked into the root Motor6D joints, relative to the starting position."
end

return Animation
