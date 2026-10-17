--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Camera = require("CameraRig")
local Paths = require("Paths")
local Parenting = require("Parenting")
local Armature = require("ArmatureRuntime")
local History = require("History")
local R6Controls = require("R6Controls")
local BlenderCurve = require("BlenderCurve")
local Diagnostics = require("Diagnostics")
local Codec = {}

function Codec.pack(frame)
	local values = { frame:GetComponents() }
	for index, number in values do
		values[index] = math.round(number * 1e6) / 1e6
	end

	return values
end

function Codec.number(value, minimum, maximum)
	return typeof(value) == "number" and value == value and value >= minimum and value <= maximum
end

function Codec.unpack(value)
	assert(typeof(value) == "table" and #value == 12, "invalid bone transform")
	for _, n in value do
		assert(Codec.number(n, -1e9, 1e9), "invalid bone transform")
	end

	local frame = CFrame.new(table.unpack(value))
	assert(
		math.abs(frame.RightVector.Magnitude - 1) < 0.002
			and math.abs(frame.UpVector.Magnitude - 1) < 0.002
			and math.abs(frame.LookVector.Magnitude - 1) < 0.002
			and math.abs(frame.RightVector:Dot(frame.UpVector)) < 0.002,
		"bone transform contains unsupported scale"
	)
	return frame
end

function Codec.capture(refs)
	local state = refs.State
	local raw = state.Timeline:GetState()
	local manifest = {
		name = state.currentProjectSave and state.currentProjectSave.Name or "Eclipse file",
		fps = raw.FPS,
		build = Diagnostics.build(),
		rigs = {},
	}
	local bindings = {}
	for _, rig in state.getAllRigs() do
		local id = rig:GetAttribute("EclipseTrackId") or Http:GenerateGUID(false)
		rig:SetAttribute("EclipseTrackId", id)
		local motors = Parenting.collectMotors(rig)
		local byPart = Parenting.buildMotorMap(motors)
		local entry = {
			rig = rig,
			motors = motors,
			byPart = byPart,
			tracks = {},
			byId = {},
			id = id,
			camera = Camera.isRig(rig),
		}
		local worlds = {}

		local function rest(motor)
			if worlds[motor] then
				return worlds[motor]
			end

			local parent = byPart[Parenting.realPart0(motor)]
			local parentWorld = parent and rest(parent) or motor.Part0.CFrame
			local value = parentWorld * (raw.DefaultPose[motor] or motor.C0) * motor.C1:Inverse()
			worlds[motor] = value
			return value
		end

		local row = {
			id = id,
			name = rig.Name,
			kind = entry.camera and "camera" or "rig",
			origin = Codec.pack(rig:GetPivot()),
			camera = entry.camera and Codec.pack(Camera.viewFrame(rig)) or nil,
			tracks = {},
		}
		for _, motor in motors do
			if Camera.isFov(motor) then
				entry.fov = motor
				continue
			end

			if
				R6Controls.isControl(motor.Part1)
				or (typeof(motor) == "table" and motor.IsEclipseMasterControl)
			then
				continue
			end

			local key = Paths.motor(motor, rig)
			if not key then
				continue
			end

			assert(not entry.byId[key], "this rig has duplicate output track identifiers")
			local parent = byPart[Parenting.realPart0(motor)]
			local track = {
				id = key,
				name = motor.Part1.Name,
				rest = Codec.pack(rest(motor)),
				joint = Codec.pack(rest(motor) * motor.C1),
				parent = parent and Paths.motor(parent, rig),
			}
			if typeof(motor.Part1) == "Instance" and motor.Part1:IsA("BasePart") then
				raw.DefaultSize[motor.Part1] = raw.DefaultSize[motor.Part1] or motor.Part1.Size
			end

			table.insert(row.tracks, track)
			table.insert(entry.tracks, { id = key, motor = motor, name = motor.Part1.Name })
			entry.byId[key] = motor
			if Camera.isTransform(motor) then
				entry.transform = motor
			end
		end

		if entry.camera or #entry.tracks > 0 then
			table.insert(manifest.rigs, row)
			bindings[id] = entry
		end
	end

	return manifest, bindings
end

function Codec.pose(refs, bindings, allowed)
	local timeline = refs.State.Timeline
	local result = {
		time = timeline:GetState().CurrentTime,
		playing = timeline:GetState().Playing,
		rigs = {},
		finish = timeline.GetPlaybackEndTime and timeline:GetPlaybackEndTime(),
		loop = timeline.IsLooping and timeline:IsLooping(),
	}
	for id, entry in bindings do
		if allowed and not allowed[id] then
			continue
		end

		local row = { id = id, tracks = {} }
		if entry.camera then
			row.camera, row.fov = Codec.pack(Camera.viewFrame(entry.rig)), Camera.fov(entry.rig)
		else
			for _, track in entry.tracks do
				local part = track.motor.Part1
				local default = refs.State.Timeline:GetState().DefaultSize[part]
				local scale = typeof(track.motor) == "table"
						and track.motor.IsEclipseArmatureControl
						and track.motor.InputScale
					or default and part.Size / default
					or Vector3.one
				table.insert(row.tracks, {
					id = track.id,
					world = Codec.pack(Parenting.worldOf(track.motor, entry.byPart)),
					scale = { scale.X, scale.Y, scale.Z },
				})
			end
		end

		table.insert(result.rigs, row)
	end

	return result
end

function Codec.decode(bindings, packet)
	assert(typeof(packet) == "table" and typeof(packet.rigs) == "table", "invalid pose packet")
	local values, worlds, scales = {}, {}, {}
	for _, row in packet.rigs do
		local entry = assert(bindings[row.id], "animation targets a rig outside this file")
		assert(entry.rig.Parent, "a paired rig was removed")
		if entry.camera then
			local frame = Codec.unpack(row.camera)
			assert(Codec.number(row.fov, 1, 120), "camera FOV must be between 1 and 120")
			worlds[entry.transform] = Camera.authoredFromView(frame, row.fov)
			values[entry.fov] = Camera.encode(entry.fov, row.fov)
		else
			for _, track in row.tracks or {} do
				local motor = assert(entry.byId[track.id], "animation targets an unknown bone")
				assert(not worlds[motor], "animation contains a duplicate bone")
				worlds[motor] = Codec.unpack(track.world)
				if track.scale then
					assert(#track.scale == 3, "invalid bone scale")
					for _, number in track.scale do
						assert(Codec.number(number, 0.0001, 10000), "invalid bone scale")
					end

					local scale = Vector3.new(table.unpack(track.scale))
					assert(
						not motor.Part1:IsA("Bone") or (scale - Vector3.one).Magnitude < 0.0001,
						"native Studio bones cannot reproduce animated scale; use an Eclipse armature"
					)
					scales[motor] = scale
				end
			end
		end

		for _, track in entry.tracks do
			local motor = track.motor
			local world = worlds[motor]
			if not world then
				continue
			end

			local parent = entry.byPart[Parenting.realPart0(motor)]
			local parentWorld = parent
					and (worlds[parent] or Parenting.worldOf(parent, entry.byPart))
				or motor.Part0.CFrame
			values[motor] = parentWorld:Inverse() * world * motor.C1
		end
	end

	return values, worlds, scales
end

function Codec.preview(refs, bindings, packet)
	local values, worlds, scales = Codec.decode(bindings, packet)
	local raw = refs.State.Timeline:GetState()
	assert(Codec.number(packet.time, 0, 1000000), "invalid animation time")
	raw.Playing, raw.CurrentTime = packet.playing == true, packet.time
	for motor, value in values do
		motor.C0 = value
	end

	for motor, scale in scales do
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			motor.InputScale = scale
		elseif raw.DefaultSize[motor.Part1] then
			motor.Part1.Size = raw.DefaultSize[motor.Part1] * scale
		end
	end

	for _, entry in bindings do
		local desired = {}
		for _, track in entry.tracks do
			local motor = track.motor
			local world = worlds[motor]
			if world and typeof(motor.Part1) == "Instance" and motor.Part1:IsA("BasePart") then
				desired[motor.Part1] = world
			end
		end

		if next(desired) then
			require("NativeJoints").applyWorlds(entry.rig, desired)
		end
	end

	for _, entry in bindings do
		if refs.State.Rig and refs.State.Rig.UpdateBonesFollowRig then
			refs.State.Rig:UpdateBonesFollowRig(entry.rig)
		end
	end

	refs.State.Timeline:UpdatePlayhead()
end

local function withImportWork(refs, callback, valid)
	local state = refs.State
	assert(
		not state.LoadingProject or state.ProjectLoadThread == coroutine.running(),
		"another file operation is running"
	)
	local loading, thread, work =
		state.LoadingProject, state.ProjectLoadThread, state.ProjectWorkStep
	state.LoadingProject, state.ProjectLoadThread = true, coroutine.running()
	local slice = os.clock()

	local function budget()
		if os.clock() - slice >= 0.008 then
			if valid then
				assert(valid(), "Blender import cancelled: file or connection changed")
			end

			task.wait()
			slice = os.clock()
			if valid then
				assert(valid(), "Blender import cancelled: file or connection changed")
			end
		end
	end

	state.ProjectWorkStep = budget
	state.Timeline:GetState().Playing = false
	local result = table.pack(xpcall(function()
		if valid then
			assert(valid(), "Blender import cancelled: file or connection changed")
		end

		return callback(budget)
	end, debug.traceback))
	state.LoadingProject, state.ProjectLoadThread, state.ProjectWorkStep = loading, thread, work
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

local function import(refs, bindings, take, options, budget)
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	assert(take.fps == raw.FPS, "file FPS changed; reconnect before importing")
	assert(
		typeof(take.frames) == "table" and #take.frames > 0 and #take.frames <= 200001,
		"invalid animation range"
	)
	local before, after, protected = {}, {}, {}
	local defaultBefore, defaultAfter = {}, {}
	for _, entry in bindings do
		for _, track in entry.tracks do
			for _, key in raw.Keyframes[track.motor] or {} do
				budget()
				if key.IK ~= nil or key.Parented == false or key.WorldCFrame then
					protected[track.motor] = track.name
					break
				end
			end
		end
	end

	local last = -1
	for _, sample in take.frames do
		budget()
		local frame = sample.frame
		assert(Codec.number(frame, 0, 20000) and frame > last, "invalid keyframe order")
		last = frame
		local values, _, scales = Codec.decode(bindings, sample)
		for motor, value in values do
			if protected[motor] then
				continue
			end

			if not before[motor] then
				before[motor] = timeline:_snapshotMotorBucket(motor, budget)
				after[motor] = {}
			end

			after[motor][frame] = {
				Frame = frame,
				Time = frame / raw.FPS,
				Motor = motor,
				Part = motor.Part1,
				C0 = value,
				Position = value.Position,
				Rotation = value.Rotation,
				Parented = true,
				EasingStyle = "Linear",
				EasingDirection = "In",
				HandleType = "Vector",
				Template = refs.TrackContainer,
				SanitizeName = refs.State.UIHelpers.SanitizeName,
				BlenderSource = true,
			}
			local scale = scales[motor]
			if scale then
				local key = after[motor][frame]
				key.WholePoseScale = { scale_x = scale.X, scale_y = scale.Y, scale_z = scale.Z }
				key.Channels = {}
				for id, number in timeline:DecomposeC0(value) do
					key.Channels[id] = { Value = number }
				end

				for id, number in key.WholePoseScale do
					key.Channels[id] = { Value = number }
				end
			end
		end
	end

	if not take.baked and (take.keys or take.trackKeys) then
		for id, entry in bindings do
			for _, motor in entry.motors do
				local trackId = entry.camera and (motor == entry.fov and "fov" or "camera")
					or Paths.motor(motor, entry.rig)
				local authored = take.trackKeys
						and take.trackKeys[id]
						and take.trackKeys[id][trackId]
					or take.keys and take.keys[id]
				if not authored then
					after[motor], before[motor] = nil, nil
					continue
				end

				local dense = after[motor]
				if not dense then
					continue
				end

				local sparse = {}
				if #authored == 0 then
					for frame, key in before[motor] do
						if not key.BlenderSource then
							sparse[frame] = key
						end
					end

					if not next(sparse) then
						defaultBefore[motor] = raw.DefaultPose[motor] or motor.C0
						defaultAfter[motor] = dense[take.frames[1].frame].C0
					end
				end

				local previousFrame = -1
				for index, frame in authored do
					assert(
						Codec.number(frame, 0, 20000) and frame > previousFrame and dense[frame],
						"invalid authored keyframe"
					)
					previousFrame = frame
					local key = dense[frame]
					sparse[frame] = key
				end

				BlenderCurve.attach(
					sparse,
					dense,
					authored,
					take.frames,
					take.curves and take.curves[id],
					raw.FPS,
					budget
				)
				after[motor] = sparse
			end
		end
	end

	for motor, bucket in after do
		if options and options.groupKeys then
			local members = {}
			for frame, key in bucket do
				budget()
				if key.BlenderSource and key ~= before[motor][frame] then
					table.insert(members, key)
				end
			end

			if #members > 1 then
				local id = Http:GenerateGUID(false)
				for _, key in members do
					key.KeyGroups = { Pose = id }
				end
			end
		end

		for frame, key in before[motor] do
			if key.Parented == false or key.WorldCFrame or key.Disabled or key.GraphOnly then
				bucket[frame] = key
			end
		end
	end

	local function apply(buckets, defaults)
		return withImportWork(refs, function(step)
			local importing, refreshing = raw._ImportingKeyframes, timeline._refreshingKeyGroups
			raw._ImportingKeyframes, timeline._refreshingKeyGroups = true, true
			local ok, err = xpcall(function()
				for motor, value in defaults or {} do
					raw.DefaultPose[motor] = value
				end

				for motor, bucket in buckets do
					timeline:_restoreMotorBucket(motor, bucket, true, step)
				end

				raw._ImportingKeyframes = importing
				if not importing then
					for motor in buckets do
						for frame, key in raw.Keyframes[motor] or {} do
							step()
							timeline:CreateOrUpdateTimelineKeyframeButton(
								key.Part,
								motor,
								frame,
								key.Template,
								key.SanitizeName
							)
						end

						timeline:RefreshAllChannelDiamondsForMotor(motor, step)
					end

					timeline._refreshingKeyGroups = refreshing
					timeline:RefreshAllKeyframeVisuals(step)
				end

				timeline:InvalidateMotorListCache()
				if refs.State.currentRig then
					timeline:ApplyPoseAtTime(refs.State.currentRig, raw.CurrentTime)
				end

				timeline:RefreshTimelineScale()
				refs.State.currentProjectSaved = false
			end, debug.traceback)
			raw._ImportingKeyframes, timeline._refreshingKeyGroups = importing, refreshing
			if not ok then
				error(err, 0)
			end
		end)
	end

	budget()
	if options and options.valid then
		assert(options.valid(), "Blender import cancelled: file or connection changed")
	end

	refs.Finalize()
	local ok, err = xpcall(function()
		apply(after, defaultAfter)
	end, debug.traceback)
	if not ok then
		apply(before, defaultBefore)
		error(err, 0)
	end

	if timeline.EnsureTimelineEnd then
		timeline:EnsureTimelineEnd(last)
	end

	History.record(function()
		apply(before, defaultBefore)
	end, function()
		apply(after, defaultAfter)
	end, "Import Blender animation")
	local kept = {}
	for _, name in protected do
		table.insert(kept, name)
	end

	table.sort(kept)
	return last + 1,
		#kept > 0
				and ("Kept Eclipse IK / parenting: " .. table.concat(kept, ", ") .. ". Switch direction to send it.")
			or nil
end

function Codec.import(refs, bindings, take, options)
	return withImportWork(refs, function(budget)
		return import(refs, bindings, take, options, budget)
	end, options and options.valid)
end

function Codec.keyState(refs, bindings, allowed)
	local raw = refs.State.Timeline:GetState()
	local result = {}
	for id, entry in bindings do
		if allowed and not allowed[id] then
			continue
		end

		local tracks = {}
		for _, motor in Parenting.collectMotors(entry.rig) do
			local keys = {}
			for frame, key in raw.Keyframes[motor] or {} do
				table.insert(keys, {
					frame,
					key.C0 and Codec.pack(key.C0),
					key.WorldCFrame and Codec.pack(key.WorldCFrame),
					key.EasingStyle,
					key.EasingDirection,
					key.HandleType,
					key.Parented,
					key.Disabled,
					key.IK,
					key.IKPoleFollowsTarget,
					key.HS,
					key.HSRotation and Codec.pack(key.HSRotation),
					key.IKTarget and Codec.pack(key.IKTarget),
					key.IKRoot and Codec.pack(key.IKRoot),
					key.WholePoseScale,
					key.GraphCurves,
					key.Channels,
					key.IKPole and { key.IKPole.X, key.IKPole.Y, key.IKPole.Z },
				})
			end

			table.sort(keys, function(a, b)
				return a[1] < b[1]
			end)
			table.insert(tracks, { Paths.motor(motor, entry.rig), keys })
		end

		result[id] = tracks
	end

	return Http:JSONEncode(result)
end

function Codec.take(refs, bindings, allowed, valid)
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local finish = math.max(0, timeline:GetLastKeyframeFrame() or 0)
	assert(finish <= 20000, "animation exceeds the 20000-frame transfer limit")
	local snapshots, armatures = {}, {}
	for id, entry in bindings do
		if not allowed[id] then
			continue
		end

		assert(valid(), "file changed while sampling")
		if Armature.isRig(entry.rig) then
			armatures[entry.rig] = Armature.snapshot(entry.rig)
		end

		for _, motor in Parenting.collectMotors(entry.rig) do
			local part = motor.Part1
			local physical = typeof(part) == "Instance" and part:IsA("BasePart")
			snapshots[motor] = {
				c0 = motor.C0,
				parented = motor:GetAttribute("TrackParent"),
				frame = physical and part.CFrame,
				size = physical and part.Size,
				scale = typeof(motor) == "table"
						and motor.IsEclipseArmatureControl
						and motor.InputScale
					or nil,
			}
		end
	end

	local take =
		{ fps = raw.FPS, frames = {}, trackKeys = {}, baked = true, build = Diagnostics.build() }
	for id, entry in bindings do
		if not allowed[id] then
			continue
		end

		local tracks = {}
		for _, track in entry.tracks do
			local values = {}
			local current = track.motor
			while current do
				for frame, key in raw.Keyframes[current] or {} do
					if not key.Disabled then
						values[frame] = true
					end
				end

				for _, control in R6Controls.forOwner(current) do
					for frame, key in raw.Keyframes[control] or {} do
						if not key.Disabled then
							values[frame] = true
						end
					end
				end

				current = entry.byPart[Parenting.realPart0(current)]
				if current and entry.byId[Paths.motor(current, entry.rig)] then
					break
				end
			end

			local keys = {}
			for frame in values do
				table.insert(keys, frame)
			end

			table.sort(keys)
			tracks[entry.camera and "camera" or track.id] = keys
		end

		if entry.fov then
			local keys = {}
			for frame, key in raw.Keyframes[entry.fov] or {} do
				if not key.Disabled then
					table.insert(keys, frame)
				end
			end

			table.sort(keys)
			tracks.fov = keys
		end

		take.trackKeys[id] = tracks
	end

	refs.State.BlenderSampling = true
	local ok, err = xpcall(function()
		local positions = {}
		for frame = 0, finish do
			positions[frame] = true
		end

		for _, tracks in take.trackKeys do
			for _, keys in tracks do
				for _, frame in keys do
					positions[frame] = true
				end
			end
		end

		local frames = {}
		for frame in positions do
			table.insert(frames, frame)
		end

		table.sort(frames)
		for index, frame in frames do
			assert(valid(), "file changed while sampling")
			for id, entry in bindings do
				if allowed[id] then
					timeline:ApplyPoseAtTime(
						entry.rig,
						frame / raw.FPS,
						{ OnlyRig = true, SkipControls = true }
					)
				end
			end

			local pose = Codec.pose(refs, bindings, allowed)
			table.insert(take.frames, { frame = frame, rigs = pose.rigs })
			if index % 60 == 0 then
				task.wait()
			end
		end
	end, debug.traceback)
	for motor, saved in snapshots do
		if motor.Part1 and motor.Part1.Parent then
			motor.C0 = saved.c0
			motor:SetAttribute("TrackParent", saved.parented)
			if saved.size then
				motor.Part1.Size, motor.Part1.CFrame = saved.size, saved.frame
			end

			if saved.scale then
				motor.InputScale = saved.scale
			end
		end
	end

	for rig, saved in armatures do
		if rig.Parent then
			Armature.restore(rig, saved)
			Armature.evaluate(rig, true)
		end
	end

	refs.State.BlenderSampling = false
	if not ok then
		error(err, 0)
	end

	return take
end

return Codec
