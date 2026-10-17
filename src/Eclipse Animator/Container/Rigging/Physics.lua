--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")

local Cache = require("Cache")
local Simulation = require("Simulation")
local SelectedRig = require("SelectedRig")
local Pose = require("RigPose")
local Parenting = require("Parenting")
local History = require("History")
local Edit = require("BlenderEdit")
local CameraRig = require("CameraRig")
local Armature = require("ArmatureRuntime")
local Quaternion = require("Quaternion")
local Master = require("MasterControl")
local Cleanup = require("KeyframeCleanup")
local Scene = require("Scene")
const Curves = require("GraphCurves")
local RunService = game:GetService("RunService")
local Physics = {}
const MOTION_LEAD = 0.05
const MAX_INHERITED_SPEED = 500
const MAX_INHERITED_SPIN = 60

local function limit(vector, maximum)
	const length = vector.Magnitude
	if length ~= length or length == math.huge then
		return Vector3.zero
	end

	return if length > maximum then vector * (maximum / length) else vector
end

local function workBudget(checkpoint)
	local deadline = os.clock() + 0.006
	return function(frame)
		if os.clock() >= deadline then
			RunService.Heartbeat:Wait()
			if checkpoint then
				checkpoint(frame)
			end

			deadline = os.clock() + 0.006
		end
	end
end

local refs

local function available()
	assert(refs and refs.Active() and refs.State.Timeline, "open an Eclipse project first")
	assert(not Edit.blocked(), "turn Blender Live off before simulating")
	assert(not refs.State.Timeline:GetState().Playing, "pause the animation first")
	return refs.State, refs.State.Timeline
end

local function finishInput(state)
	if state.BlenderNavigation then
		state.BlenderNavigation.stop(true)
	end

	if state.PhysicsDisplay then
		state.PhysicsDisplay.finish(false)
	end

	if state.CameraPreview and state.CameraPreview.isViewRotating() then
		state.CameraPreview.finishViewRotation(false)
	end

	if state.CameraControls and state.CameraControls.isEditing() then
		state.CameraControls.finish(false)
	end

	if
		state.Timeline.IsBlenderKeyframeTransformActive
		and state.Timeline:IsBlenderKeyframeTransformActive()
	then
		state.Timeline:ConfirmBlenderKeyframeTransform()
	end

	if refs.Finalize then
		refs.Finalize()
	end
end

local function refresh()
	local state, timeline = refs.State, refs.State.Timeline
	Cache.invalidate()
	if state.currentRig then
		timeline:ApplyPoseAtTime(state.currentRig, timeline:GetState().CurrentTime)
	end

	if state.GraphEditor then
		state.GraphEditor.invalidate()
	end

	timeline:RefreshAllKeyframeVisuals()
	if state.Axis then
		state.Axis:RefreshAxis()
	end

	state.currentProjectSaved = false
end

function Physics.targets(mode)
	local state, timeline = available()
	local registered = Scene.entries()
	assert(#registered > 0, "select a rig, model or parts, then click Add selected")
	local motors = {}
	for _, entry in registered do
		table.insert(motors, entry.motor)
	end

	return registered[1].rig, motors, registered
end

local function key(motor, frame, fps, cf, world, channels)
	local q = Quaternion.fromCFrame(cf)
	local values = {
		loc_x = cf.X,
		loc_y = cf.Y,
		loc_z = cf.Z,
		qrot_w = q.w,
		qrot_x = q.x,
		qrot_y = q.y,
		qrot_z = q.z,
	}
	local points = {}
	for id, value in values do
		points[id] = { Value = value }
	end

	for id, value in channels or {} do
		if id:sub(1, 6) == "scale_" then
			points[id] = { Value = value }
		end
	end

	return {
		Motor = motor,
		Part = motor.Part1,
		Frame = frame,
		Time = frame / fps,
		C0 = cf,
		ChannelPoseC0 = cf,
		Position = cf.Position,
		Rotation = cf.Rotation,
		WorldCFrame = world,
		MasterWorld = Master.worldDelta(motor),
		Parented = false,
		IK = false,
		HS = false,
		HandleType = "Vector",
		EasingStyle = "Linear",
		EasingDirection = "In",
		Channels = points,
	}
end

local function matchCurves(raw, clip, budget)
	for motor, keys in clip.tracks do
		const bucket = raw.Keyframes[motor]
		const compiled = bucket and Curves.compile(bucket)
		const graph = compiled and compiled.hasGraph
		const order = graph and compiled.rotationOrder
		local rotation, euler
		for index, frame in Cleanup.frames(keys) do
			const key = keys[frame]
			const cf = key.C0
			const points = key.Channels
			if typeof(cf) ~= "CFrame" or not points then
				continue
			end

			if points.qrot_w and points.qrot_x and points.qrot_y and points.qrot_z then
				local q = {
					w = points.qrot_w.Value,
					x = points.qrot_x.Value,
					y = points.qrot_y.Value,
					z = points.qrot_z.Value,
				}
				if rotation then
					q = Quaternion.alignSign(rotation, q)
				end

				rotation = q
				points.qrot_w.Value, points.qrot_x.Value = q.w, q.x
				points.qrot_y.Value, points.qrot_z.Value = q.y, q.z
			end

			if graph then
				const values = { loc_x = cf.X, loc_y = cf.Y, loc_z = cf.Z }
				if order then
					if not euler then
						const x, y, z = Curves.euler(cf, order)
						euler = { x, y, z }
						for i, id in { "rot_x", "rot_y", "rot_z" } do
							const channel = compiled.channels[id]
							if channel then
								euler[i] = Curves.value(channel, key.Time)
							end
						end
					end

					values.rot_x, values.rot_y, values.rot_z = Curves.euler(cf, order, euler)
					euler = { values.rot_x, values.rot_y, values.rot_z }
				end

				key.GraphCurves = key.GraphCurves or {}
				for _, id in Curves.ids do
					const rotated = id:sub(1, 4) == "rot_"
					if not compiled.channels[id] and not (order and rotated) then
						continue
					end

					const value = values[id] or points[id] and points[id].Value
					if type(value) == "number" then
						const point = Curves.newPoint(key, id)
						point.Value = value
						if order and rotated then
							point.RotationOrder = order
						end

						key.GraphCurves[id] = point
					end
				end
			end

			if budget and index % 128 == 0 then
				budget(frame)
			end
		end
	end
end

local function boxesOverlap(a, sizeA, b, sizeB)
	local ha, hb = sizeA * 0.5, sizeB * 0.5
	local offset = b.Position - a.Position
	if offset.Magnitude > ha.Magnitude + hb.Magnitude then
		return false
	end

	local axesA = { a.RightVector, a.UpVector, a.LookVector }
	local axesB = { b.RightVector, b.UpVector, b.LookVector }

	local function separated(axis)
		if axis.Magnitude < 1e-6 then
			return false
		end

		axis = axis.Unit
		local ra = math.abs(axesA[1]:Dot(axis)) * ha.X
			+ math.abs(axesA[2]:Dot(axis)) * ha.Y
			+ math.abs(axesA[3]:Dot(axis)) * ha.Z
		local rb = math.abs(axesB[1]:Dot(axis)) * hb.X
			+ math.abs(axesB[2]:Dot(axis)) * hb.Y
			+ math.abs(axesB[3]:Dot(axis)) * hb.Z
		return math.abs(offset:Dot(axis)) > ra + rb - 0.01
	end

	for i = 1, 3 do
		if separated(axesA[i]) or separated(axesB[i]) then
			return false
		end
	end

	for i = 1, 3 do
		for j = 1, 3 do
			if separated(axesA[i]:Cross(axesB[j])) then
				return false
			end
		end
	end

	return true
end

local function rigidNeighbors(part)
	const result = {}
	for _, joint in part:GetJoints() do
		local a, b
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			a, b = joint.Part0, joint.Part1
		elseif
			(joint:IsA("RigidConstraint") or joint:IsA("AnimationConstraint"))
			and joint.Attachment0
			and joint.Attachment1
		then
			a, b = joint.Attachment0.Parent, joint.Attachment1.Parent
		end

		const other = if a == part then b else a
		if joint.Enabled ~= false and typeof(other) == "Instance" and other:IsA("BasePart") then
			table.insert(result, other)
		end
	end

	return result
end

local function attach(bodies, owners)
	const claimed, blocked, attached = {}, {}, {}
	for _, body in bodies do
		claimed[body.part] = true
		const parent = body.motor and Parenting.realPart0(body.motor)
		if typeof(parent) == "Instance" then
			blocked[parent] = true
		end
	end

	for _, body in bodies do
		const owner = owners[body.motor]
		if not body.part:IsA("BasePart") or not owner then
			continue
		end

		const origin = body.part.CFrame
		const queue = { body.part }
		local index = 1
		body.attached = {}
		while index <= #queue do
			const current = queue[index]
			index += 1
			for _, other in rigidNeighbors(current) do
				if
					claimed[other]
					or blocked[other]
					or attached[other]
					or other.Anchored
					or other.Name == "HumanoidRootPart"
					or not other:IsDescendantOf(owner)
				then
					continue
				end

				attached[other] = body
				table.insert(queue, other)
				if other.CanCollide then
					table.insert(body.attached, {
						part = other,
						offset = origin:ToObjectSpace(other.CFrame),
					})
				end
			end
		end
	end

	return attached
end

local function worn(part, owner)
	const item = part:FindFirstAncestorWhichIsA("Accoutrement")
	return item ~= nil and owner ~= nil and item:IsDescendantOf(owner)
end

function Physics.simulate(settings, checkpoint, previous)
	local state, timeline = available()
	finishInput(state)
	local rig, motors, entries = Physics.targets(settings.mode)
	local raw = timeline:GetState()
	settings = table.clone(settings)
	settings.fps = raw.FPS
	Scene.snapshot(settings, entries)
	local rigs, owners, ragdolls = {}, {}, {}
	for _, entry in entries do
		rigs[entry.rig] = true
		owners[entry.motor] = entry.rig
		ragdolls[entry.motor] = entry.ragdoll
	end

	settings.excludeParts = {}
	if previous then
		assert(table.find(Cache.list(raw), previous), "This simulation was removed")
	end

	local validation = {}
	for _, motor in motors do
		table.insert(
			validation,
			{ part = Scene.part(motor), frame = Scene.world(Scene.part(motor)) }
		)
	end

	Simulation.validate(validation, settings)
	local project, keyframes = state.currentAnimations, raw.Keyframes
	for _, clip in Cache.list(raw) do
		if clip == previous then
			continue
		end

		for _, motor in motors do
			assert(
				not clip.tracks[motor]
					or settings.last + 1 < clip.first - 1
					or settings.first - 1 > clip.last + 1,
				string.format(
					"Overlaps %s (%d-%d). Remove the object from the Simulations list, or select that simulation to update it.",
					clip.name,
					clip.first,
					clip.last
				)
			)
		end
	end

	local capture, masters = {}, {}
	for owner in rigs do
		for object, pose in Pose.capture(owner) do
			capture[object] = pose
		end

		masters[owner] = Master.capture(owner)
	end

	local sizes, parenting = {}, {}
	for part in capture do
		if part:IsA("BasePart") then
			sizes[part] = part.Size
		end
	end

	for owner in rigs do
		for _, motor in Parenting.collectMotors(owner) do
			parenting[motor] = { motor:GetAttribute("TrackParent") }
		end
	end

	for _, motor in motors do
		local part = Scene.part(motor)
		if not capture[part] then
			capture[part] = part:IsA("Bone") and { Transform = part.Transform }
				or { CFrame = part.CFrame }
		end

		if part:IsA("BasePart") then
			sizes[part] = part.Size
		end
	end

	local bodies, links, original, guards, scales = {}, {}, {}, {}, {}
	local startingGeometry = {}

	local function sampledWorld(part)
		local motor = raw.MotorByPart[part]
		return motor and Parenting.worldOf(motor, raw.MotorByPart) or part.CFrame
	end

	local byPart = {}
	for _, motor in motors do
		byPart[Scene.part(motor)] = motor
		original[motor] = timeline:_snapshotMotorBucket(motor)
	end

	local guard

	local function pose(frame)
		for owner in rigs do
			timeline:ApplyPoseAtTime(
				owner,
				frame / raw.FPS,
				{ OnlyRig = true, SkipControls = true }
			)
		end
	end

	local function approach(frame)
		pose(frame)
		const worlds = {}
		for _, motor in motors do
			worlds[Scene.part(motor)] = Parenting.worldOf(motor, raw.MotorByPart)
		end

		return worlds
	end

	local function sample(frame)
		pose(frame)
		local worlds, locals, boundaries = {}, {}, {}
		for _, motor in motors do
			worlds[Scene.part(motor)] = Parenting.worldOf(motor, raw.MotorByPart)
			locals[motor] = motor.C0
			boundaries[motor] = guard(motor, frame, motor.C0, worlds[Scene.part(motor)])
		end

		return worlds, locals, boundaries
	end

	guard = function(motor, frame, cf, world)
		local result = key(
			motor,
			frame,
			raw.FPS,
			cf,
			world,
			timeline:EvaluateMotorScale(motor, frame / raw.FPS)
		)
		result.Parented = timeline:IsParentedAtTime(motor, frame / raw.FPS)
		if result.Parented then
			result.WorldCFrame = nil
		end

		for _, field in { "IK", "HS" } do
			local previous
			for _, source in original[motor] do
				if
					not source.Disabled
					and typeof(source[field]) == "boolean"
					and source.Frame <= frame
					and (not previous or source.Frame > previous.Frame)
				then
					previous = source
				end
			end

			result[field] = previous and previous[field] or false
		end

		require("LimbIK").captureKey(motor, result)
		require("HeadStabilizer").captureKey(motor, result, cf)
		return result
	end

	local ok, err = xpcall(function()
		Cache.without(function()
			local sampling = table.clone(keyframes)
			for motor, bucket in keyframes do
				local owned = byPart[Scene.part(motor)] ~= nil
					or typeof(motor) == "table" and rigs[motor.Rig] == true
				if not owned and typeof(Scene.part(motor)) == "Instance" then
					for owner in rigs do
						if Scene.part(motor):IsDescendantOf(owner) then
							owned = true
							break
						end
					end
				end

				if owned then
					sampling[motor] = Cleanup.copy(bucket)
				end
			end

			raw.Keyframes = sampling
			local before, beforeC0, beforeKeys = sample(math.max(0, settings.first - 1))
			local after, afterC0, afterKeys = sample(settings.last + 1)
			const arriving = settings.first > 0 and approach(settings.first - MOTION_LEAD) or before
			const elapsed = (if settings.first > 0 then 1 - MOTION_LEAD else 1) / raw.FPS
			local start, startC0 = sample(settings.first)
			for owner in rigs do
				for _, part in RigTraversal.rigDescendants(owner) do
					if part:IsA("BasePart") then
						startingGeometry[part] = sampledWorld(part)
					end
				end
			end

			for _, motor in motors do
				local part = Scene.part(motor)
				const from, to = before[part], arriving[part]
				local axis, angle = from:ToObjectSpace(to):ToAxisAngle()
				scales[motor] = timeline:EvaluateMotorScale(motor, settings.first / raw.FPS)
				table.insert(bodies, {
					part = part,
					frame = start[part],
					size = Scene.size(part),
					velocity = limit((to.Position - from.Position) / elapsed, MAX_INHERITED_SPEED),
					angular = limit(from:VectorToWorldSpace(axis) * (angle / elapsed), MAX_INHERITED_SPIN),
					motor = motor,
					group = ragdolls[motor] and owners[motor] or part,
				})
				guards[motor] = {}
				if settings.first > 0 then
					guards[motor][settings.first - 1] = beforeKeys[motor]
				end

				if settings.last < timeline:GetMaxFrame() then
					guards[motor][settings.last + 1] = afterKeys[motor]
				end

				local parent = Parenting.realPart0(motor)
				if byPart[parent] and worn(part, owners[motor]) then
					const holder = byPart[parent]
					bodies[#bodies].group = ragdolls[holder] and owners[holder] or parent
					table.insert(links, { a = parent, b = part, rigid = true })
				elseif
					not settings.detached
					and ragdolls[motor]
					and byPart[parent]
					and ragdolls[byPart[parent]]
				then
					table.insert(links, {
						a = parent,
						b = part,
						frame = start[part] * motor.C1,
						angle = part.Name == "Head" and 35 or 75,
					})
				elseif
					byPart[parent]
					and boxesOverlap(start[parent], Scene.size(parent), start[part], Scene.size(part))
				then
					table.insert(links, { a = parent, b = part, loose = true })
				end
			end
		end)
	end, debug.traceback)
	raw.Keyframes = keyframes
	Pose.restore(rig, capture)
	for owner, snapshot in masters do
		Master.restore(owner, snapshot)
	end

	for part, size in sizes do
		if part.Parent then
			part.Size = size
		end
	end

	for motor, saved in parenting do
		if motor.Parent then
			motor:SetAttribute("TrackParent", saved[1])
		end
	end

	require("LimbIK").clearLive()
	assert(ok, err)

	local function check(frame)
		assert(
			state.currentAnimations == project
				and raw.Keyframes == keyframes
				and raw.FPS == settings.fps
				and rig.Parent,
			"the project changed; simulate again"
		)
		assert(not raw.Playing, "simulation canceled because playback started")
		for owner in rigs do
			assert(owner.Parent, "a registered rig was removed")
		end

		checkpoint(frame)
	end

	local bodyParts, tracked, movingRigs = {}, {}, {}
	for _, body in bodies do
		bodyParts[body.part] = true
	end

	for _, body in bodies do
		if body.part:IsA("Bone") then
			local skin = body.part:FindFirstAncestorWhichIsA("BasePart")
			if skin then
				bodyParts[skin] = true
				table.insert(settings.excludeParts, skin)
			end
		end
	end

	const attached = attach(bodies, owners)
	for owner in rigs do
		const humanoid = owner:FindFirstChildOfClass("Humanoid")
		const root = humanoid and humanoid.RootPart
		for _, part in RigTraversal.rigDescendants(owner) do
			if not part:IsA("BasePart") or not part.CanCollide or bodyParts[part] then
				continue
			end

			if attached[part] or part == root or part.Name == "HumanoidRootPart" then
				table.insert(settings.excludeParts, part)
				continue
			end

			for _, body in bodies do
				if
					boxesOverlap(
						body.frame,
						body.size,
						startingGeometry[part] or part.CFrame,
						part.Size
					)
				then
					table.insert(settings.excludeParts, part)
					break
				end
			end
		end
	end

	local excluded = {}
	for _, part in settings.excludeParts do
		excluded[part] = true
	end

	for _, owner in state.getAllRigs() do
		for _, part in RigTraversal.rigDescendants(owner) do
			if
				part:IsA("BasePart")
				and not bodyParts[part]
				and not tracked[part]
				and part.Name ~= "HumanoidRootPart"
				and part.CanCollide
				and not excluded[part]
			then
				tracked[part] = {}
				movingRigs[owner] = true
			end
		end
	end

	local colliders = {}
	if next(tracked) then
		local saved = {}
		for owner in movingRigs do
			saved[owner] = { pose = Pose.capture(owner), master = Master.capture(owner) }
		end

		local sampleBudget = workBudget(nil)
		local sampled, sampleError = xpcall(function()
			for frame = settings.first, settings.last do
				for owner in movingRigs do
					timeline:ApplyPoseAtTime(
						owner,
						frame / raw.FPS,
						{ OnlyRig = true, SkipControls = true }
					)
				end

				for part, frames in tracked do
					frames[frame] = sampledWorld(part)
				end

				sampleBudget(frame)
			end
		end, debug.traceback)
		for owner, snapshot in saved do
			Pose.restore(owner, snapshot.pose)
			Master.restore(owner, snapshot.master)
		end

		assert(sampled, sampleError)
		for part, frames in tracked do
			local first = frames[settings.first]
			for frame = settings.first + 1, settings.last do
				local cf = frames[frame]
				if
					(cf.Position - first.Position).Magnitude > 1e-3
					or first.Rotation ~= cf.Rotation
						and (first:ToObjectSpace(cf).LookVector - Vector3.new(0, 0, -1)).Magnitude > 1e-4
				then
					table.insert(colliders, { part = part, frames = frames })
					break
				end
			end
		end
	end

	local poses, report = Simulation.run(bodies, links, settings, check, nil, colliders)
	local budget = workBudget(check)
	check(settings.last)
	for motor, snapshot in original do
		assert(
			Cleanup.equal(snapshot, timeline:_snapshotMotorBucket(motor)),
			"the animation changed; simulate again"
		)
	end

	local clip = {
		id = previous and previous.id or game:GetService("HttpService"):GenerateGUID(false),
		rig = rig,
		name = rig.Name .. (#motors > 0 and " / " .. #motors .. " parts" or ""),
		first = settings.first,
		last = settings.last,
		settings = settings,
		tracks = {},
		owners = owners,
		ragdolls = ragdolls,
		guideMotors = {},
	}
	for _, guide in settings.guides or (settings.guide and { settings.guide } or {}) do
		clip.guideMotors[guide.index] = entries[guide.index].motor
	end

	const masterPoses = {}
	local function masterPose(master, time)
		local cached = masterPoses[master]
		if not cached then
			cached = {}
			masterPoses[master] = cached
		end

		local value = cached[time]
		if not value then
			value = timeline:EvaluateMotorC0(master, time)
			cached[time] = value
		end

		return value
	end

	local moved = false
	for _, body in bodies do
		local motor = body.motor
		local keys = guards[motor]
		local samples = poses[body.part]
		local inverse = motor.Part0.CFrame:Inverse()
		const origin = samples[settings.first]
		for frame = settings.first, settings.last do
			local world = samples[frame]
			if not moved and world ~= origin then
				moved = true
			end

			if
				frame == settings.first
				or frame == settings.last
				or world ~= samples[frame - 1]
				or world ~= samples[frame + 1]
			then
				const value =
					key(motor, frame, raw.FPS, inverse * world * motor.C1, world, scales[motor])
				value.MasterWorld = Master.worldDelta(motor, masterPose, frame / raw.FPS)
				keys[frame] = value
			end

			if frame % 128 == 0 then
				budget(frame)
			end
		end

		poses[body.part] = nil
		clip.tracks[motor] = keys
	end

	matchCurves(raw, clip, budget)
	clip.still = not moved
	if clip.still then
		local ragdolled = false
		for _, entry in entries do
			ragdolled = ragdolled or entry.ragdoll == true
		end

		const pushed = settings.velocity.Magnitude > 0 or #(settings.forces or {}) > 0
		clip.stillReason = if report.removed > 0
			then "removed"
			elseif report.held > 0 then "hold"
			elseif report.reanchored > 0 then "anchored"
			elseif report.frozen then "frozen"
			elseif settings.gravity == 0 and not pushed then "gravity"
			elseif not ragdolled then (if settings.mode == "Ragdoll" then "limbs" else "objects")
			else "resting"
	end

	local before = table.clone(Cache.list(raw))
	local after = {}
	for _, existing in before do
		if existing ~= previous then
			table.insert(after, existing)
		end
	end

	table.insert(after, clip)

	local function apply(clips)
		Cache.set(raw, clips)
		timeline:EnsureTimelineEnd(settings.last)
		refresh()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Simulate physics", settings.first)
	return clip
end

local function motionRange(keys, clip, budget)
	local frames = {}
	for frame in keys do
		if frame >= clip.first and frame <= clip.last then
			table.insert(frames, frame)
		end
	end

	table.sort(frames)
	local first, last, lead, anchor
	for i, frame in frames do
		local current = keys[frame].WorldCFrame or keys[frame].C0
		if anchor then
			local delta = anchor:ToObjectSpace(current)
			local _, angle = delta:ToAxisAngle()
			if delta.Position.Magnitude > 1e-4 or math.abs(angle) > 1e-4 then
				if not first then
					first = frame
					lead = keys[frames[i - 1]]
				end

				last = frame
				anchor = current
			end
		else
			anchor = current
		end

		if i % 128 == 0 then
			budget()
		end
	end

	if not first and #frames > 0 then
		first, last = frames[1], frames[#frames]
		lead = keys[first]
	end

	return first, last, lead
end

function Physics.simulateSmartBones(rig, settings, checkpoint, previous, onCommit)
	local state, timeline = available()
	finishInput(state)
	local raw = timeline:GetState()
	local clip = require("dynamics").run(refs, rig, settings, checkpoint, key, previous)
	matchCurves(raw, clip, workBudget(nil))
	local before = table.clone(Cache.list(raw))
	local after = {}
	for _, old in before do
		if old ~= previous then
			table.insert(after, old)
		end
	end

	table.insert(after, clip)

	local function apply(clips)
		Cache.set(raw, clips)
		Cache.preview(raw, true)
		timeline:EnsureTimelineEnd(settings.last)
		refresh()
	end

	if onCommit then
		onCommit()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Simulate Bone Dynamics", clip.first)
	return clip
end

function Physics.bake(clip, checkpoint, onCommit)
	assert(
		(clip.settings.kind == "SmartBone" or clip.settings.kind == "BoneDynamics")
			or (not Scene.forcesChanged(clip) and not Scene.guideChanged(clip)),
		"Update the simulation before baking the changed force or path"
	)
	local state, timeline = available()
	finishInput(state)
	local raw = timeline:GetState()
	local project, keyframes = state.currentAnimations, raw.Keyframes
	local completed, total = 0, 0
	for _, keys in clip.tracks do
		for _ in keys do
			total += 1
		end
	end

	local function check()
		assert(
			state.currentAnimations == project and raw.Keyframes == keyframes and not raw.Playing,
			"simulation canceled; the project changed"
		)
		if checkpoint then
			checkpoint(completed, total)
		end
	end

	local budget = workBudget(check)
	local beforeClips, afterClips = table.clone(Cache.list(raw)), {}
	assert(table.find(beforeClips, clip), "simulate this clip first")
	local before, after = {}, {}
	local partTracks, trackChoices = {}, {}
	for motor, keys in clip.tracks do
		local first, last, lead = motionRange(keys, clip, budget)
		if clip.settings.kind == "BoneDynamics" and clip.settings.loop == true then
			first, last, lead = clip.first, clip.last, keys[clip.first]
		end

		if not first then
			continue
		end

		if motor:GetAttribute("EclipsePartRigJoint") and motor.Part0 then
			trackChoices[motor] = { value = motor:GetAttribute("EclipsePartTrackEnabled") }
			local owner = motor.Part0.Parent
			if owner and not partTracks[owner] then
				partTracks[owner] = {
					value = owner:GetAttribute("EclipseIndividualParts"),
					choices = require("PartRig").choice(owner),
				}
			end
		end

		assert(
			motor.Parent
				and motor.Part0
				and (typeof(motor) == "table" and motor.IsEclipseProperty or motor.Part0.Parent)
				and motor.Part1
				and motor.Part1.Parent,
			"a physics track was removed"
		)
		before[motor] = timeline:_snapshotMotorBucket(motor)
		after[motor] = table.clone(before[motor])
		for frame in after[motor] do
			if frame >= clip.first and frame <= clip.last then
				after[motor][frame] = nil
			end
		end

		local group = game:GetService("HttpService"):GenerateGUID(false)
		local count = 0
		for frame, value in keys do
			completed += 1
			if frame < first or frame > last then
				continue
			end

			local copy = Cleanup.copy({ [frame] = value })[frame]
			copy.KeyGroups = { Pose = group }
			for _, points in { copy.Channels or {}, copy.GraphCurves or {} } do
				for channel in points do
					copy.KeyGroups[channel] = group .. ":" .. channel
				end
			end

			if frame == first and frame > 0 then
				copy.PhysicsLead = Cleanup.copy({ lead })[1]
				copy.PhysicsLead.Motor, copy.PhysicsLead.Part = nil, nil
			end

			if frame == last and last < clip.last then
				copy.PhysicsTail = clip.last - last
			end

			after[motor][frame] = copy
			count += 1
			if count % 128 == 0 then
				budget()
			end
		end

		budget()
	end

	assert(next(after), "The simulation has no samples to bake. Update the simulation first.")
	check()
	for motor, snapshot in before do
		assert(
			Cleanup.equal(snapshot, timeline:_snapshotMotorBucket(motor)),
			"The animation changed; bake again"
		)
		budget()
	end

	check()
	for _, existing in beforeClips do
		if existing ~= clip then
			table.insert(afterClips, existing)
		end
	end

	local function apply(buckets, clips)
		for owner, previous in partTracks do
			owner:SetAttribute(
				"EclipseIndividualParts",
				if buckets == after then true else previous.value
			)
			require("PartRig").restoreChoice(owner, previous.choices)
		end

		for motor, previous in trackChoices do
			motor:SetAttribute(
				"EclipsePartTrackEnabled",
				if buckets == after then true else previous.value
			)
		end

		Cache.set(raw, {})
		for motor, bucket in buckets do
			timeline:_restoreMotorBucket(motor, bucket, true)
		end

		Cache.set(raw, clips)
		if next(partTracks) and refs.RefreshStructure then
			refs.RefreshStructure()
		elseif timeline.RebuildAllTimelineKeyframeButtons then
			timeline:RebuildAllTimelineKeyframeButtons()
		end

		refresh()
	end

	if onCommit then
		onCommit()
	end

	local ok, err = xpcall(function()
		apply(after, afterClips)
	end, debug.traceback)
	if not ok then
		apply(before, beforeClips)
		error(err)
	end

	History.record(function()
		apply(before, beforeClips)
	end, function()
		apply(after, afterClips)
	end, "Bake physics", clip.first)
end

local function removeClips(selected)
	local _, timeline = available()
	local raw = timeline:GetState()
	local before, after = table.clone(Cache.list(raw)), {}
	local affected, removed = {}, false
	for _, clip in before do
		if selected[clip] then
			removed = true
			affected[clip.rig] = true
			for motor in clip.tracks do
				affected[clip.owners and clip.owners[motor] or clip.rig] = true
			end
		else
			table.insert(after, clip)
		end
	end

	if not removed then
		return false
	end

	local function apply(clips)
		Cache.set(raw, clips)

		for rig in affected do
			if rig and rig.Parent then
				timeline:ApplyPoseAtTime(
					rig,
					raw.CurrentTime,
					{ OnlyRig = true, SkipControls = true }
				)
			end
		end

		refresh()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Remove physics cache")
	return true
end

function Physics.remove(clip)
	return removeClips({ [clip] = true })
end

function Physics.removeBoneDynamics(rig)
	local selected = {}
	for _, clip in Physics.list() do
		if
			clip.rig == rig
			and (clip.settings.kind == "SmartBone" or clip.settings.kind == "BoneDynamics")
		then
			selected[clip] = true
		end
	end

	return removeClips(selected)
end

function Physics.list()
	return refs and refs.State.Timeline and Cache.list(refs.State.Timeline:GetState()) or {}
end

function Physics.preview(enabled)
	if not refs or not refs.State.Timeline then
		return
	end

	local state, timeline = refs.State, refs.State.Timeline
	local raw = timeline:GetState()
	Cache.preview(raw, enabled)
	if not enabled then
		raw.Playing = false
	end

	Cache.invalidate()
	local rigs = {}
	for _, clip in Cache.list(raw) do
		for motor in clip.tracks do
			rigs[clip.owners and clip.owners[motor] or clip.rig] = true
		end
	end

	for rig in rigs do
		if rig.Parent then
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true, SkipControls = true })
		end
	end
end

function Physics.init(options)
	refs = options
	Scene.init(options)
end

return Physics
