--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local TimelineState = require("RawState")
local TimeScale = require("TimeScale")
local Curves = require("GraphCurves")
local Interp = require("Interp")
local Properties = require("Properties")
local Quaternion = require("Quaternion")
local History = require("History")
local Tool = require("Tool")
local Notice = require("Notification")
local Frames = {}
local window

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function Frames.availability(timeline)
	if not timeline then
		return false, false
	end

	local first, last = math.huge, -math.huge
	local ranges = {}
	local fill = false

	local function add(key, id)
		if not key or not key.Motor or not finite(key.Frame) then
			return
		end

		first = math.min(first, key.Frame)
		last = math.max(last, key.Frame)
		local motor = key.Motor
		ranges[motor] = ranges[motor] or {}
		local range = ranges[motor][id] or { key.Frame, key.Frame }
		range[1] = math.min(range[1], key.Frame)
		range[2] = math.max(range[2], key.Frame)
		ranges[motor][id] = range
		if range[2] - range[1] > 1 then
			fill = true
		end
	end

	for _, key in timeline:GetSelectedKeyframesList() do
		add(key, "pose")
	end

	for _, entry in timeline:GetSelectedChannelKeyframesList() do
		add(entry.keyData, entry.channelId)
	end

	return last > first, fill
end

function Frames.capture(timeline)
	local originals, before = {}, {}
	local first, last = math.huge, -math.huge

	local function add(key, channel)
		if not key or not key.Motor or not finite(key.Frame) then
			return
		end

		local motor = key.Motor
		if not before[motor] then
			before[motor] = TimeScale.copyBucket(timeline:GetMotorKeyframeBucket(motor))
		end

		table.insert(originals, {
			kind = channel and "channel" or "bone",
			keyData = key,
			motor = motor,
			channelId = channel,
			originalFrame = key.Frame,
		})
		first = math.min(first, key.Frame)
		last = math.max(last, key.Frame)
	end

	for _, key in timeline:GetSelectedKeyframesList() do
		add(key)
	end

	for _, entry in timeline:GetSelectedChannelKeyframesList() do
		add(entry.keyData, entry.channelId)
	end

	assert(#originals > 0 and last > first, "Select keys spanning at least two frames.")
	return {
		originals = originals,
		before = before,
		first = first,
		last = last,
		fps = timeline:GetState().FPS,
	}
end

function Frames.selectionCurve(selection)
	local counts, examples = {}, {}
	local aliases = { Exponential = "Expo", Circular = "Circ", CubicV2 = "Cubic" }

	local function name(value, fallback)
		local result = typeof(value) == "EnumItem" and value.Name or value or fallback
		return aliases[result] or result
	end

	for _, snap in selection.originals do
		local key = snap.keyData
		local point = snap.channelId and key.GraphCurves and key.GraphCurves[snap.channelId]
		local source = point and point.Interpolation == "Legacy" and point.Easing or key
		local style = point and point.Interpolation ~= "Legacy" and point.Interpolation
			or source.EasingStyle
		style = name(style, "Linear")
		counts[style] = (counts[style] or 0) + 1
		local prior = examples[style]
		if not prior or snap.originalFrame < prior.frame then
			local curve = {
				EasingStyle = style,
				EasingDirection = name(source.EasingDirection, "In"),
				BezierPoints = Curves.clone(source.BezierPoints or { 0.42, 0, 0.58, 1 }),
				Overshoot = source.Overshoot or 1.70158,
				Amplitude = source.Amplitude or 1,
				Period = source.Period or 0.3,
				MoonEasing = source.MoonEasing,
			}
			examples[style] = { frame = snap.originalFrame, curve = curve }
		end
	end

	local best
	for style, count in counts do
		if
			not best
			or count > counts[best]
			or count == counts[best]
				and (examples[style].frame < examples[best].frame or examples[style].frame == examples[best].frame and style < best)
		then
			best = style
		end
	end

	return examples[best].curve
end

function Frames.stretch(selection, percent, reconstruct)
	assert(
		finite(percent) and percent > 0 and percent <= 100000,
		"Enter a stretch percentage greater than 0 and at most 100000."
	)
	local targets, whole, channels, last = {}, {}, {}, {}

	local function stretched(frame)
		return math.floor(selection.first + (frame - selection.first) * percent / 100 + 0.5)
	end

	for _, snap in selection.originals do
		local frame = stretched(snap.originalFrame)
		targets[snap.keyData] = frame
		last[snap.motor] = last[snap.motor] or {}
		local lane = snap.kind == "bone" and "pose" or snap.channelId
		last[snap.motor][lane] = math.max(last[snap.motor][lane] or -math.huge, snap.originalFrame)
	end

	local moves = {}
	local moveTargets = {}

	local function add(motor, frame, channel, target)
		local map = channel and channels or whole
		map[motor] = map[motor] or {}
		if channel then
			map[motor][frame] = map[motor][frame] or {}
			if map[motor][frame][channel] then
				return
			end

			map[motor][frame][channel] = target
		else
			if map[motor][frame] then
				return
			end

			map[motor][frame] = target
		end

		assert(
			target >= 0 and target <= 1000000,
			"The stretched animation exceeds the frame range (0-1000000)."
		)

		local identity = {}
		moveTargets[identity] = target
		table.insert(moves, {
			kind = channel and "channel" or "bone",
			keyData = identity,
			motor = motor,
			channelId = channel,
			originalFrame = frame,
		})
	end

	for _, snap in selection.originals do
		if snap.kind == "bone" then
			add(snap.motor, snap.originalFrame, nil, targets[snap.keyData])
		end
	end

	for motor, lanes in last do
		if lanes.pose then
			local delta = stretched(lanes.pose) - lanes.pose
			for frame in selection.before[motor] do
				if frame > lanes.pose then
					add(motor, frame, nil, frame + delta)
				end
			end
		end
	end

	for _, snap in selection.originals do
		if snap.kind ~= "bone" then
			local full = whole[snap.motor] and whole[snap.motor][snap.originalFrame]
			assert(
				not full or full == targets[snap.keyData],
				"The selected pose and channel ranges conflict. Stretch them separately."
			)
			if not full then
				add(snap.motor, snap.originalFrame, snap.channelId, targets[snap.keyData])
			end
		end
	end

	for motor, lanes in last do
		for id, ending in lanes do
			if id ~= "pose" then
				local delta = stretched(ending) - ending
				for frame, key in selection.before[motor] do
					if
						frame > ending
						and not (whole[motor] and whole[motor][frame])
						and (
							key.GraphCurves and key.GraphCurves[id]
							or key.Channels and key.Channels[id]
						)
					then
						add(motor, frame, id, frame + delta)
					end
				end
			end
		end
	end

	local occupied = {}
	local collision =
		"Stretch would overlap keyframes. Use a longer duration or include the intervening keys."
	for motor, bucket in selection.before do
		local sorted = {}
		for frame in bucket do
			table.insert(sorted, frame)
		end

		table.sort(sorted)
		local previous = {}
		for _, frame in sorted do
			local key = bucket[frame]
			local full = whole[motor] and whole[motor][frame]
			local ids = {}
			for id in key.GraphCurves or {} do
				ids[id] = true
			end

			for id in key.Channels or {} do
				ids[id] = true
			end

			if not key.GraphOnly then
				ids.pose = true
			end

			for id in ids do
				local target = full
					or channels[motor] and channels[motor][frame] and channels[motor][frame][id]
					or frame
				assert(not previous[id] or target > previous[id], collision)
				previous[id] = target
			end
		end

		occupied[motor] = {}
		for frame, key in bucket do
			if not (whole[motor] and whole[motor][frame]) then
				local ids = {}
				for id in key.GraphCurves or {} do
					ids[id] = true
				end

				for id in key.Channels or {} do
					ids[id] = true
				end

				for id in channels[motor] and channels[motor][frame] or {} do
					ids[id] = nil
				end

				if not key.GraphOnly or next(ids) then
					occupied[motor][frame] = { pose = not key.GraphOnly, ids = ids }
				end
			end
		end
	end

	for _, snap in moves do
		if snap.kind == "bone" then
			local frame = moveTargets[snap.keyData]
			local slots = occupied[snap.motor]
			assert(not slots[frame], collision)
			local key = selection.before[snap.motor][snap.originalFrame]
			local ids = {}
			for id in key.GraphCurves or {} do
				ids[id] = true
			end

			for id in key.Channels or {} do
				ids[id] = true
			end

			slots[frame] = { pose = not key.GraphOnly, ids = ids }
		end
	end

	for _, snap in moves do
		if snap.kind == "channel" then
			local frame = moveTargets[snap.keyData]
			local slots = occupied[snap.motor]
			local slot = slots[frame] or { ids = {} }
			assert(not slot.ids[snap.channelId], collision)
			slot.ids[snap.channelId] = true
			slots[frame] = slot
		end
	end

	local after = TimeScale.build(selection.before, moves, moveTargets, selection.fps, reconstruct)
	local adjusted = {}
	for _, snap in selection.originals do
		local key = after[snap.motor][targets[snap.keyData]]
		if key then
			adjusted[key] = adjusted[key] or {}
			for id, point in key.GraphCurves or {} do
				if (snap.kind == "bone" or snap.channelId == id) and not adjusted[key][id] then
					adjusted[key][id] = true
					for _, field in { "In", "Out" } do
						if point[field] then
							point[field][1] *= percent / 100
						end
					end

					if point.BlenderHandles then
						for _, field in { "incoming", "outgoing" } do
							if point.BlenderHandles[field] then
								point.BlenderHandles[field][1] *= percent / 100
							end
						end
					end
				end
			end
		end
	end

	return after, targets
end

local function curveOptions(options)
	local curve = Curves.clone(options.curve or {})
	curve.HandleType = "Vector"
	curve.EasingStyle = options.style
	curve.EasingDirection = options.direction
	return curve
end

local function curvePoint(options)
	local curve = curveOptions(options)
	local point = Curves.newPoint(curve)

	if curve.EasingStyle == "Bezier" then
		point.Interpolation = "Legacy"
		point.Easing = curve
	end

	return point
end

local function easing(key, options, id)
	local function point(value, order)
		local p = curvePoint(options)
		p.Value = value
		p.RotationOrder = order
		return p
	end

	if id then
		local p = key.GraphCurves and key.GraphCurves[id]
		if p and not p.Empty then
			key.GraphCurves[id] = point(p.Value, p.RotationOrder)
		end
	else
		key.NativePose = nil
        key.HandleType = "Vector"
		key.EasingStyle = options.style
		key.EasingDirection = options.direction
		for _, field in { "BezierPoints", "Overshoot", "Amplitude", "Period" } do
			key[field] = Curves.clone(options.curve and options.curve[field])
		end

		key.BlenderCurve = nil
		key.BlenderSource = nil
		key.PathTangentIn = nil
		key.PathTangentOut = nil
		for channel, p in key.GraphCurves or {} do
			if not p.Empty then
				key.GraphCurves[channel] = point(p.Value, p.RotationOrder)
			end
		end
	end
end

local function bounds(bucket, frame)
	local a, b
	for f, key in bucket do
		if not key.Disabled then
			if f <= frame and (not a or f > a.Frame) then
				a = key
			end

			if f >= frame and (not b or f < b.Frame) then
				b = key
			end
		end
	end

	return a or b, b or a
end

local function components(c0, scale, bucket)
	local G = require("GraphCurves")
	local ex, ey, ez = G.euler(c0, G.rotationOrder(bucket))
	local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
	local q = Quaternion.fromCFrame(c0)
	return {
		loc_x = c0.X,
		loc_y = c0.Y,
		loc_z = c0.Z,
		rot_x = math.deg(x),
		rot_y = math.deg(y),
		rot_z = math.deg(z),
		qrot_w = q.w,
		qrot_x = q.x,
		qrot_y = q.y,
		qrot_z = q.z,
		scale_x = scale and scale.scale_x or 1,
		scale_y = scale and scale.scale_y or 1,
		scale_z = scale and scale.scale_z or 1,
	}
end

function Frames.fill(selection, options, timeline)
	assert(
		finite(options.interval) and options.interval >= 1 and options.interval % 1 == 0,
		"Interval must be a whole number of frames, at least 1."
	)
	local style = typeof(options.style) == "EnumItem" and options.style.Name or options.style
	assert(
		({
			Constant = true,
			Linear = true,
			Bezier = true,
			Sine = true,
			Quad = true,
			Cubic = true,
			Quart = true,
			Quint = true,
			Sextic = true,
			Expo = true,
			Exponential = true,
			Circ = true,
			Circular = true,
			Back = true,
			Bounce = true,
			Elastic = true,
		})[style],
		"Choose an easing style."
	)
	local direction = typeof(options.direction) == "EnumItem" and options.direction.Name
		or options.direction
	assert(
		({ Automatic = true, In = true, Out = true, InOut = true, OutIn = true })[direction],
		"Choose an easing direction."
	)
	local position, angle = options.position or Vector3.zero, options.angle or Vector3.zero
	for _, v in { position.X, position.Y, position.Z, angle.X, angle.Y, angle.Z } do
		assert(
			finite(v) and math.abs(v) <= 10000,
			"Wiggle amounts must be finite and no greater than 10000."
		)
	end

	local ranges, after = {}, {}
	for motor, bucket in selection.before do
		after[motor] = TimeScale.copyBucket(bucket)
	end

	for _, snap in selection.originals do
		ranges[snap.motor] = ranges[snap.motor] or {}
		local id = snap.kind == "bone" and "pose" or snap.channelId
		local range = ranges[snap.motor][id]
			or { first = snap.originalFrame, last = snap.originalFrame }
		range.first = math.min(range.first, snap.originalFrame)
		range.last = math.max(range.last, snap.originalFrame)
		ranges[snap.motor][id] = range
	end

	local count = 0
	for _, ids in ranges do
		for _, range in ids do
			count += math.max(0, math.ceil((range.last - range.first) / options.interval) - 1)
		end
	end

	assert(
		count <= 20000,
		"Use a larger interval; Fill Frames is limited to 20000 inserted keys per operation."
	)
	local random = Random.new(options.seed or 1)
	local inserted = 0
	for motor, ids in ranges do
		local source = selection.before[motor]
		local output = after[motor]
		local compiled = Curves.compile(source)
		local samples = {}

		local function sample(frame)
			if samples[frame] then
				return samples[frame]
			end

			local a, b = bounds(source, frame)
			assert(a and b, "This track has no enabled keys to fill.")
			local key = TimeScale.copyKey(a)
			local time = frame / selection.fps
			key.Frame = frame
			key.Time = time
			key.Disabled = nil
			key.PhysicsLead = nil
			key.PhysicsTail = nil
			key.BlenderCurve = nil
			key.BlenderSource = nil
			key.ChannelPoseC0 = nil
            key.IsEclipseSynthetic = nil
			local c0 = timeline:EvaluateMotorC0(motor, time, source)
			if
				options.wiggle
				and not Properties.is(motor)
				and not require("CameraRig").isFov(motor)
			then
				local function noise(v)
					return Vector3.new(
						random:NextNumber(-1, 1) * v.X,
						random:NextNumber(-1, 1) * v.Y,
						random:NextNumber(-1, 1) * v.Z
					)
				end

				local p, r = noise(position), noise(angle) * math.pi / 180
				c0 = CFrame.new(c0.Position + p) * c0.Rotation * CFrame.Angles(r.X, r.Y, r.Z)
			end

			key.C0 = c0
			key.Position = c0.Position
			key.Rotation = c0.Rotation
			if Properties.is(motor) then
				key.PropertyValue = Properties.evaluate(motor, source, time)
				key.C0 = Properties.encode(key.PropertyValue)
				key.Position = key.C0.Position
				key.Rotation = key.C0.Rotation
			end

			if a ~= b then
				for _, field in
					{
						"WorldCFrame",
						"MasterWorld",
						"IKTarget",
						"IKPole",
						"IKBaseC0",
						"IKBaseWorld",
						"IKAnchor",
						"IKRigWorld",
						"IKRoot",
						"HSRotation",
						"HSLocalRotation",
						"CamTargetAnchor",
					}
				do
					if typeof(a[field]) == "CFrame" and typeof(b[field]) == "CFrame" then
						key[field] =
							Interp.cframe(source, a, b, (time - a.Time) / (b.Time - a.Time), field)
					end
				end
			end

			if
				key.IKPoleFollowsTarget
				and typeof(key.IKTarget) == "CFrame"
				and typeof(a.IKTarget) == "CFrame"
				and typeof(a.IKPole) == "CFrame"
			then
				local relative = a.IKTarget:ToObjectSpace(a.IKPole)
				if a ~= b and typeof(b.IKTarget) == "CFrame" and typeof(b.IKPole) == "CFrame" then
					local converted = {}
					for f, k in source do
						local v = table.clone(k)
						if k.IKTarget and k.IKPole then
							v.IKPole = k.IKTarget:ToObjectSpace(k.IKPole)
						end

						converted[f] = v
					end

					relative = Interp.cframe(
						converted,
						converted[a.Frame],
						converted[b.Frame],
						(time - a.Time) / (b.Time - a.Time),
						"IKPole"
					)
				end

				key.IKPole = key.IKTarget * relative
			end

			local scale = timeline:EvaluateMotorScale(motor, time, source)
			local values = components(c0, scale, source)
			if options.wiggle and compiled.rotationOrder then
				local reference = {}
				for i, id in { "rot_x", "rot_y", "rot_z" } do
					reference[i] = compiled.channels[id]
							and Curves.value(compiled.channels[id], time)
						or values[id]
				end

				values.rot_x, values.rot_y, values.rot_z =
					Curves.euler(c0, compiled.rotationOrder, reference)
			end

			key.Channels = {}
			key.GraphCurves = {}
			for _, id in Curves.ids do
				local graph = compiled.channels[id]
				local exists = graph or a.Channels and a.Channels[id]
				if exists then
					local value = graph and Curves.value(graph, time) or values[id]
					if
						options.wiggle
						and (
							id:sub(1, 4) == "loc_"
							or id:sub(1, 4) == "rot_"
							or id:sub(1, 5) == "qrot_"
						)
					then
						value = values[id]
					end

					key.Channels[id] = { Value = value }
					if graph then
						local point = curvePoint(options)
						point.Value = value
						point.RotationOrder = id:sub(1, 4) == "rot_" and compiled.rotationOrder
							or nil
						key.GraphCurves[id] = point
					end
				end
			end

			if not next(key.Channels) then
				key.Channels = nil
			end

			if not next(key.GraphCurves) then
				key.GraphCurves = nil
			end

			if scale then
				key.WholePoseScale = scale
			end

			easing(key, options)
			samples[frame] = key
			return key
		end

		for id, range in ids do
			if range.last <= range.first then
				continue
			end

			if
				id ~= "pose"
				and ids.pose
				and range.first >= ids.pose.first
				and range.last <= ids.pose.last
			then
				continue
			end

            for frame, key in output do
                if frame > range.first and frame < range.last then
                    if id == "pose" then
                        output[frame] = nil
                    else
                        if key.Channels then key.Channels[id] = nil end
                        if key.GraphCurves then key.GraphCurves[id] = nil end
                        if key.GraphOnly and not next(key.Channels or {}) and not next(key.GraphCurves or {}) then
                            output[frame] = nil
                        end
                    end
                end
            end
            for frame = range.first + options.interval, range.last - 1e-7, options.interval do
                local sampled = sample(frame)
                if id == "pose" then
                    output[frame] = sampled
                else
                    local existing = output[frame]
                    if not existing then
                        existing = TimeScale.copyKey(sampled)
                        existing.Channels, existing.GraphCurves = {}, {}
                        existing.GraphOnly = true
                        output[frame] = existing
                    end
                    local value = compiled.channels[id] and Curves.value(compiled.channels[id], frame / selection.fps)
                        or components(sampled.C0, sampled.WholePoseScale, source)[id]
                    if options.wiggle then
                        value = sampled.GraphCurves and sampled.GraphCurves[id] and sampled.GraphCurves[id].Value
                            or components(sampled.C0, sampled.WholePoseScale, source)[id]
                    end
                    existing.Channels = existing.Channels or {}
                    existing.Channels[id] = { Value = value }
                    existing.GraphCurves = existing.GraphCurves or {}
                    existing.GraphCurves[id] = { Value = value, RotationOrder = id:sub(1, 4) == "rot_" and compiled.rotationOrder or nil }
                    easing(existing, options, id)
                end
            end
            inserted += 1

			for frame, key in output do
				if frame >= range.first and frame < range.last then
					easing(key, options, id ~= "pose" and id or nil)
				end
			end
		end
	end

	assert(inserted > 0, "Select at least two different frames on the same track.")
	return after
end

function Frames.commit(timeline, selection, after, targets, label)
	local raw = timeline:GetState()
	assert(raw.FPS == selection.fps, "The project FPS changed. Reopen this tool.")
	local oldEnd = timeline:GetMaxFrame()
	local newEnd = oldEnd
	for _, bucket in after do
		for frame in bucket do
			newEnd = math.max(newEnd, frame)
		end
	end

	local function restore(buckets, moved)
		raw.Playing = false
		for motor, bucket in buckets do
			timeline:_restoreMotorBucket(motor, bucket)
		end

		raw.SelectedKeyframes = {}
		raw.SelectedChannelKeyframes = {}
		raw.SelectedKeyframe = nil
		for _, snap in selection.originals do
			local frame = moved and targets and targets[snap.keyData] or snap.originalFrame
			local key = raw.Keyframes[snap.motor] and raw.Keyframes[snap.motor][frame]
			if key then
				if snap.kind == "bone" then
					raw.SelectedKeyframes[key] = true
				else
					raw.SelectedChannelKeyframes[key] = raw.SelectedChannelKeyframes[key] or {}
					raw.SelectedChannelKeyframes[key][snap.channelId] = true
				end

				raw.SelectedKeyframe = key
			end
		end

		TimelineState.Config.Length = (moved and newEnd or oldEnd) / raw.FPS
		timeline:RefreshTimelineScale()
		timeline:RefreshAllKeyframeVisuals()
		timeline:RefreshAllTimelineKeyframePositions()
		if State.currentRig then
			timeline:ApplyPoseAtTime(State.currentRig, raw.CurrentTime)
		end

		if State.GraphEditor then
			State.GraphEditor.invalidate()
		end

		require("motionPath").markDirty()
		State.currentProjectSaved = false
	end

	local ok, err = pcall(restore, after, true)
	if not ok then
		restore(selection.before, false)
		error(err)
	end

	History.record(function()
		restore(selection.before, false)
	end, function()
		restore(after, true)
	end, label, selection.first, newEnd)
	return true
end

local function sameData(a, b)
	if a == b then
		return true
	end

	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for k, v in a do
		if k ~= "Button" and not sameData(v, b[k]) then
			return false
		end
	end

	for k in b do
		if k ~= "Button" and a[k] == nil then
			return false
		end
	end

	return true
end

function Frames.open(mode)
	if mode ~= "stretch" and mode ~= "fill" then
		return
	end

	if require("BlenderEdit").blocked() then
		return
	end

	local timeline = State.Timeline
	if not timeline or timeline:IsExportLocked() or timeline:IsBlenderKeyframeTransformActive() then
		return
	end

	local ok, selection = pcall(Frames.capture, timeline)
	if not ok then
		Notice.show(
			mode == "fill" and "FILL FRAMES" or "STRETCH FRAMES",
			tostring(selection):gsub("^.-:%d+: ", "")
		)
		return
	end

	if window then
		window:close(true)
	end

	local raw = timeline:GetState()
	raw.Playing = false
	local originalBuckets = {}
	for motor in selection.before do
		originalBuckets[motor] = raw.Keyframes[motor]
	end

	local refs =
		{ ScreenGui = require("UI").EclipseGUI, Plugin = require("ProjectData").getPlugin() }
	local session
	session = Tool.new(
		refs,
		"EclipseFrameTools",
		mode == "fill" and "FILL FRAMES" or "STRETCH FRAMES",
		Vector2.new(380, mode == "fill" and 310 or 214),
		false,

		function()
			if session then
				require("KeyframeMenu").closeCurvePicker((session.frame:FindFirstAncestorWhichIsA("LayerCollector") or session.gui))
			end

			window = nil
		end
	)
	window = session

	local function field(label, text, y)
		Tool.label(
			session.frame,
			label .. "Label",
			label,
			UDim2.fromOffset(16, y),
			UDim2.fromOffset(175, 26)
		)
		return Tool.field(
			session.frame,
			label,
			text,
			UDim2.fromOffset(198, y),
			UDim2.fromOffset(166, 26)
		)
	end

	local apply
	if mode == "stretch" then
		local duration = selection.last - selection.first
		local current = field("Current Duration (frames)", duration, 44)
		current.TextEditable = false
		local factor = field("Stretch Factor (%)", 100, 78)
		local length = field("New Duration (frames)", duration, 112)
		local ending = field("End Frame", selection.last, 146)
		local updating = false

		local function update(source)
			if updating then
				return
			end

			updating = true
			local value = tonumber(source.Text)
			if finite(value) then
				local percent = source == factor and value
					or (source == ending and value - selection.first or value) / duration * 100
				if percent > 0 then
					if source ~= factor then
						factor.Text = string.format("%.6g", percent)
					end

					local last = math.floor(selection.first + duration * percent / 100 + 0.5)
					if source ~= length then
						length.Text = tostring(last - selection.first)
					end

					if source ~= ending then
						ending.Text = tostring(last)
					end
				end
			end

			updating = false
		end

		for _, box in { factor, length, ending } do
			table.insert(
				session.connections,
				box:GetPropertyChangedSignal("Text"):Connect(function()
					update(box)
				end)
			)
		end

		apply = function()
			local after, targets = Frames.stretch(selection, tonumber(factor.Text), function(key)
				return timeline:_reconstructC0FromKeyData(key)
			end)
			Frames.commit(timeline, selection, after, targets, "Stretch frames")
		end
	else
		local interval = field("Interval (frames)", 2, 44)
		local curve = Frames.selectionCurve(selection)
		local directions = { "In", "Out", "InOut", "OutIn", "Automatic" }
		local directionIndex = table.find(directions, curve.EasingDirection) or 1

		local function choice(label, y, values, changed, initial)
			Tool.label(
				session.frame,
				label .. "Label",
				label,
				UDim2.fromOffset(16, y),
				UDim2.fromOffset(170, 26)
			)
			local index = initial or 1
			local caption
			local _, text = Tool.button(
				session.frame,
				label,
				values[index],
				UDim2.fromOffset(198, y),
				UDim2.fromOffset(166, 26),

				function()
					index = index % #values + 1
					caption.Text = values[index]
					changed(index)
				end
			)
			caption = text
		end

		Tool.label(
			session.frame,
			"Easing StyleLabel",
			"Easing Style",
			UDim2.fromOffset(16, 78),
			UDim2.fromOffset(170, 26)
		)
		local styleCaption, styleButton
		local menu = require("KeyframeMenu")

		local function openPicker()
			if session.closed or menu.isCurvePickerOpen((session.frame:FindFirstAncestorWhichIsA("LayerCollector") or session.gui)) then
				return
			end

			local opened = menu.openCurvePicker((session.frame:FindFirstAncestorWhichIsA("LayerCollector") or session.gui), curve, function(value)
				if session.closed then
					return
				end

				curve = value
				styleCaption.Text = curve.EasingStyle
			end, session.frame, styleButton)
			if not opened then
				Notice.show("FILL FRAMES", "Reopen the timeline to use the interpolation editor.")
			end
		end

		local button, caption = Tool.button(
			session.frame,
			"Easing Style",
			curve.EasingStyle,
			UDim2.fromOffset(198, 78),
			UDim2.fromOffset(166, 26),

			function()
				if not menu.closeCurvePicker((session.frame:FindFirstAncestorWhichIsA("LayerCollector") or session.gui)) then
					openPicker()
				end
			end
		)
		styleCaption = caption
		styleButton = button
		caption.Size = UDim2.new(1, -26, 1, 0)
		local arrow = Tool.label(
			button,
			"Arrow",
			"\u{25b6}",
			UDim2.new(1, -20, 0, 0),
			UDim2.fromOffset(16, 26)
		)
		arrow.TextSize = 10
		arrow.TextXAlignment = Enum.TextXAlignment.Center
		arrow.ZIndex = caption.ZIndex
		table.insert(session.connections, button.MouseEnter:Connect(openPicker))
		choice("Direction", 112, directions, function(i)
			directionIndex = i
			curve.EasingDirection = directions[i]
		end, directionIndex)
		local wiggle = false
		choice("Wiggle", 146, { "Off", "On" }, function(i)
			wiggle = i == 2
		end)
		Tool.label(
			session.frame,
			"AxisLabels",
			"X                  Y                  Z",
			UDim2.fromOffset(122, 180),
			UDim2.fromOffset(250, 20)
		)

		local function vector(label, y, default)
			Tool.label(
				session.frame,
				label,
				label,
				UDim2.fromOffset(16, y),
				UDim2.fromOffset(100, 26)
			)
			local boxes = {}
			for i = 1, 3 do
				boxes[i] = Tool.field(
					session.frame,
					label .. i,
					default,
					UDim2.fromOffset(122 + (i - 1) * 82, y),
					UDim2.fromOffset(76, 26)
				)
			end

			return function()
				local v = {}
				for i, box in boxes do
					v[i] = tonumber(box.Text)
					assert(finite(v[i]), "Enter numeric wiggle amounts.")
				end

				return Vector3.new(table.unpack(v))
			end
		end

		local angle = vector("Angle (degrees)", 204, 2)
		local position = vector("Position (studs)", 238, 0)
		local seed = math.random(1, 1000000000)
		apply = function()
			local after = Frames.fill(selection, {
				interval = tonumber(interval.Text),
				style = curve.EasingStyle,
				direction = curve.EasingDirection or directions[directionIndex],
				curve = curve,
				wiggle = wiggle,
				angle = angle(),
				position = position(),
				seed = seed,
			}, timeline)
			Frames.commit(timeline, selection, after, nil, "Fill frames")
		end
	end

	Tool.button(
		session.frame,
		"Apply",
		"APPLY",
		UDim2.new(0, 16, 1, -36),
		UDim2.new(1, -32, 0, 26),

		function()
			local success, message = pcall(function()
				assert(
					State.Timeline == timeline
						and State.currentRig
						and not timeline:IsExportLocked()
						and not require("BlenderEdit").blocked(),
					"Reopen this tool in the current project."
				)
				for motor, bucket in originalBuckets do
					assert(
						raw.Keyframes[motor] == bucket,
						"The active layer or project changed. Reopen this tool."
					)
					assert(
						sameData(TimeScale.copyBucket(bucket), selection.before[motor]),
						"The animation changed. Reopen this tool."
					)
				end

				for _, snap in selection.originals do
					assert(
						raw.Keyframes[snap.motor][snap.originalFrame] == snap.keyData,
						"The selection changed. Reopen this tool."
					)
				end

				apply()
			end)
			if success then
				session:close()
			else
				Notice.show(
					mode == "fill" and "FILL FRAMES" or "STRETCH FRAMES",
					tostring(message):gsub("^.-:%d+: ", "")
				)
			end
		end
	)
	table.insert(
		session.connections,
		refs.ScreenGui.Destroying:Connect(function()
			session:close(true)
		end)
	)
end

return Frames
