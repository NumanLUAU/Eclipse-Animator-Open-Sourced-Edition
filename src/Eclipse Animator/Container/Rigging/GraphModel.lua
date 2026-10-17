--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local ChannelEasing = require("ChannelEasing")
local KeyGroups = require("KeyGroups")
local BlenderEdit = require("BlenderEdit")
local KeyframePolicy = require("Policy")
local Curves = require("GraphCurves")
local Quaternion = require("Quaternion")
local Bezier = require("Bezier")
local Interp = require("Interp")
local Defaults = require("Defaults")
local KeyframeDefaults = require("KeyframeDefaults")
local Preferences = require("Preferences")
local Activity = require("Activity")
local Mods = require("Mods")
local Model = {}
Model.__index = Model
local GROUPS =
	{ loc = "Position", rot = "Euler Rotation", qrot = "Quaternion Rotation", scale = "Scale" }
local counter = 0

local function nextId()
	counter += 1
	return "graph-" .. tostring(counter) .. "-" .. tostring(os.clock())
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e12
end

local function angleNear(value, reference)
	return reference + ((value - reference + 180) % 360) - 180
end

local function cloneKey(key)
	local copy = {}
	for field, value in pairs(key) do
		if field ~= "Button" then
			copy[field] = (
				field == "Channels"
				or field == "GraphCurves"
				or field == "BezierPoints"
				or field == "KeyGroups"
			)
					and Curves.clone(value)
				or value
		end
	end

	return copy
end

local function copyBucket(bucket)
	local copy = {}
	for frame, key in pairs(bucket or {}) do
		copy[frame] = cloneKey(key)
	end

	return copy
end

local function removeKey(timeline, motor, bucket, frame)
	local key = bucket[frame]
	if key and key.Button then
		key.Button:Destroy()
		key.Button = nil
	end

	bucket[frame] = nil
	if timeline._removeChannelDiamondAtFrame then
		timeline:_removeChannelDiamondAtFrame(motor, frame)
	end
end

local function styleName(style)
	return typeof(style) == "EnumItem" and style.Name or style
end

local function muteId(id)
	if id == "qrot_w" then
		return nil
	end

	if id:sub(1, 5) == "qrot_" then
		return id:sub(2)
	end

	return (id:sub(1, 4) == "loc_" or id:sub(1, 4) == "rot_") and id or nil
end

function Model.setMuted(self: any, track, muted)
	if BlenderEdit.blocked() then
		return false
	end

	local id = muteId(track.channelId)
	if not id then
		return false
	end

	local motor = track.motor
	local before = Mods.snapshot(motor)
	local entry = Mods.ensure(motor, id)
	entry.Muted = muted and true or nil
	if muted then
		local rest = self.Timeline:GetState().DefaultPose[motor] or motor.C0
		entry.MuteValue = Mods.component(id, rest, nil, 0)
		if id:sub(1, 4) == "rot_" then
			entry.MuteRest = { rest:GetComponents() }
		end
	else
		entry.MuteValue = nil
		entry.MuteRest = nil
	end

	Mods.prune(motor)
	Mods.touch(motor)
	local after = Mods.snapshot(motor)
	self:_notify("commit")
	if self.History then
		self.History.record(function()
			Mods.restore(motor, before)
			self:_notify("undo")
		end, function()
			Mods.restore(motor, after)
			self:_notify("redo")
		end, muted and "Mute animation axis" or "Unmute animation axis")
	end

	return true
end

function Model.new(config)
	assert(config and config.Timeline, "GraphModel requires Timeline")
	return setmetatable({
		Timeline = config.Timeline,
		History = config.History,
		onChanged = config.onChanged,
		_cache = {},
		_motorIds = setmetatable({}, { __mode = "k" }),
		_transaction = nil,
	}, Model)
end

function Model.invalidate(self: any)
	table.clear(self._cache)
end

function Model._notify(self: any, phase)
	if phase ~= "preview" then
		self:invalidate()
	end

	if self.onChanged then
		self.onChanged(phase)
	end
end

function Model._motorId(self: any, motor)
	if not self._motorIds[motor] then
		self._motorIds[motor] = nextId()
	end

	return self._motorIds[motor]
end

function Model._sampleEntry(self: any, motor)
	local entry = self._cache[motor]
	if entry then
		return entry
	end

	local state = self.Timeline:GetState()
	local bucket = copyBucket(Curves.legacyBucket(state.Keyframes[motor]))
	for _, key in pairs(bucket) do
		key.GraphCurves = nil
	end

	for _, key in pairs(bucket) do
		self.Timeline:EnsureChannelsPopulated(key)
	end

	entry = { bucket = bucket, frames = {}, count = 0 }
	self._cache[motor] = entry
	return entry
end

function Model.sample(self: any, track, frame)
	local loopEnd = self.Timeline:IsLooping() and self.Timeline:GetPlaybackEndTime() or nil
	if self._sampleLoopEnd ~= loopEnd then
		self:invalidate()
		self._sampleLoopEnd = loopEnd
	end

	local scalar =
		Curves.compile(self.Timeline:GetState().Keyframes[track.motor]).channels[track.channelId]
	if scalar then
		return Curves.value(scalar, frame / self.Timeline:GetState().FPS, loopEnd)
	end

	local entry = self:_sampleEntry(track.motor)
	local at = entry.frames[frame]
	if not at then
		local time = frame / self.Timeline:GetState().FPS
		local loopEnd = self.Timeline:IsLooping() and self.Timeline:GetPlaybackEndTime() or nil
		local cf = (self.Timeline.EvaluateMotorJointC0 or self.Timeline.EvaluateMotorC0)(
			self.Timeline,
			track.motor,
			time,
			entry.bucket,
			loopEnd
		)
		local scale = self.Timeline:EvaluateMotorScale(track.motor, time, entry.bucket, loopEnd)
		local ex, ey, ez =
			Curves.euler(cf, Curves.rotationOrder(self.Timeline:GetState().Keyframes[track.motor]))
		local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
		local graph = Curves.compile(self.Timeline:GetState().Keyframes[track.motor]).channels
		local qcf = cf
		if graph.rot_x or graph.rot_y or graph.rot_z then
			qcf = Curves.rotation(
				graph.rot_x and Curves.value(graph.rot_x, time, loopEnd) or ex,
				graph.rot_y and Curves.value(graph.rot_y, time, loopEnd) or ey,
				graph.rot_z and Curves.value(graph.rot_z, time, loopEnd) or ez,
				Curves.rotationOrder(self.Timeline:GetState().Keyframes[track.motor])
			)
		end

		local q = Quaternion.fromCFrame(qcf)
		local reference = Curves.quaternionReference(entry.bucket, time)
		if reference then
			q = Quaternion.alignSign(reference, q)
		end

		at = {
			loc_x = cf.X,
			loc_y = cf.Y,
			loc_z = cf.Z,
			qrot_w = q.w,
			qrot_x = q.x,
			qrot_y = q.y,
			qrot_z = q.z,
			rot_x = math.deg(x),
			rot_y = math.deg(y),
			rot_z = math.deg(z),
			scale_x = scale and scale.scale_x or 1,
			scale_y = scale and scale.scale_y or 1,
			scale_z = scale and scale.scale_z or 1,
		}
		entry.count += 1
		if entry.count > 2048 then
			table.clear(entry.frames)
			entry.count = 1
		end

		entry.frames[frame] = at
	end

	local value = at[track.channelId]
	if string.sub(track.channelId, 1, 5) == "qrot_" then
		local exact = entry.bucket[frame]
		local graph = Curves.compile(self.Timeline:GetState().Keyframes[track.motor])
		local euler = graph.channels.rot_x or graph.channels.rot_y or graph.channels.rot_z
		if not euler and exact and exact.Channels and exact.Channels[track.channelId] then
			local reference =
				Curves.quaternionReference(entry.bucket, frame / self.Timeline:GetState().FPS)
			return reference and reference[track.channelId:sub(6)]
				or exact.Channels[track.channelId].Value
		end
	end

	if
		track.group == "Euler Rotation"
		and not Curves.compile(entry.bucket).channels[track.channelId]
		and track.keys
		and #track.keys > 0
	then
		local lo, hi = 1, #track.keys
		while hi - lo > 1 do
			local middle = math.floor((lo + hi) / 2)
			if track.keys[middle].frame < frame then
				lo = middle
			else
				hi = middle
			end
		end

		local nearest = math.abs(track.keys[lo].frame - frame)
					< math.abs(track.keys[hi].frame - frame)
				and track.keys[lo]
			or track.keys[hi]
		value = angleNear(value, nearest.value)
	end

	return value
end

function Model.tracks(self: any, motors)
	if not KeyframePolicy.channelsEnabled() then
		return {}
	end

	local tracks, seen = {}, {}
	local state = self.Timeline:GetState()
	local activities = {}
	for _, motor in ipairs(motors or {}) do
		if seen[motor] or typeof(motor) == "table" and motor.IsEclipseProperty then
			continue
		end

		seen[motor] = true
		local ranges = Activity.forMotor(self.Timeline, motor, activities)
		if ranges and #ranges == 0 then
			continue
		end

		local bucket = state.Keyframes[motor] or {}
		local compiled = Curves.compile(bucket)
		local frames = {}
		for frame, key in pairs(bucket) do
			if not key.GraphOnly then
				table.insert(frames, frame)
			end
		end

		table.sort(frames)
		local uniform = not motor:GetAttribute("EclipseChannelDisabledAny")
		for _, frame in ipairs(frames) do
			local key = bucket[frame]
			if not key.C0 then
				uniform = false
				break
			end

			if key.Channels then
				for _, id in ipairs({
					"loc_x",
					"loc_y",
					"loc_z",
					"qrot_w",
					"qrot_x",
					"qrot_y",
					"qrot_z",
				}) do
					if not key.Channels[id] then
						uniform = false
						break
					end
				end
			end

			if not uniform then
				break
			end
		end

		if compiled.channels.rot_x or compiled.channels.rot_y or compiled.channels.rot_z then
			uniform = false
		end

		local exactKeys = {}
		if uniform then
			for _, frame in ipairs(frames) do
				local key = bucket[frame]
				local cf = key.C0
				local x, y, z = cf:ToEulerAnglesXYZ()
				local q = Curves.quaternionReference(bucket, key.Time) or Quaternion.fromCFrame(cf)
				local values = {
					qrot_w = q.w,
					qrot_x = q.x,
					qrot_y = q.y,
					qrot_z = q.z,
					loc_x = cf.X,
					loc_y = cf.Y,
					loc_z = cf.Z,
					rot_x = math.deg(x),
					rot_y = math.deg(y),
					rot_z = math.deg(z),
				}
				for _, id in ipairs({ "scale_x", "scale_y", "scale_z" }) do
					values[id] = key.Channels and key.Channels[id] and key.Channels[id].Value or 1
				end

				for _, id in ipairs({ "qrot_w", "qrot_x", "qrot_y", "qrot_z" }) do
					if key.Channels and key.Channels[id] then
						values[id] = q[id:sub(6)]
					end
				end

				exactKeys[frame] = values
			end
		end

		local name = motor.Part1 and motor.Part1.Name or motor.Name or "Bone"
		for _, id in ipairs(Curves.ids) do
			if
				not KeyframePolicy.channelAvailable(motor, id)
				or (
					not Curves.rotationChannelVisible(bucket, id)
					and not (Mods.get(motor, id) and #Mods.get(motor, id).Stack > 0)
				)
			then
				continue
			end

			if
				string.sub(id, 1, 4) == "rot_"
				and not compiled.channels[id]
				and not (
					Mods.get(motor, id)
					and (#Mods.get(motor, id).Stack > 0 or Mods.get(motor, id).Extrapolation)
				)
			then
				continue
			end

			local prefix, axis = string.match(id, "^(.-)_([wxyz])$")
			local group = GROUPS[prefix]
			local track = {
				id = self:_motorId(motor) .. "/" .. id,
				channelId = id,
				motor = motor,
				bone = name,
				name = group .. " " .. string.upper(axis),
				group = group,
				axis = string.upper(axis),
				unit = group == "Euler Rotation" and "\u{00B0}"
					or group == "Quaternion Rotation" and ""
					or group == "Position" and "studs"
					or "\u{00D7}",
				keys = {},
			}
			local authored = compiled.channels[id]
			if authored then
				for _, item in ipairs(authored) do
					if item.point.Empty then
						continue
					end

					table.insert(track.keys, {
						id = item.point.Id or track.id .. "/" .. item.frame,
						frame = item.frame,
						value = item.point.Value,
						keyData = item.key,
						interpolation = item.point.Interpolation,
						handleType = item.point.HandleType,
					})
				end
			else
				local lastAngle
				for _, frame in ipairs(frames) do
					local key = bucket[frame]
					local hasChannel = key.Channels == nil
					if prefix == "rot" then
						for _, q in ipairs({ "qrot_w", "qrot_x", "qrot_y", "qrot_z" }) do
							hasChannel = hasChannel or (key.Channels and key.Channels[q] ~= nil)
						end
					else
						hasChannel = hasChannel or (key.Channels and key.Channels[id] ~= nil)
					end

					if hasChannel then
						local value = exactKeys[frame] and exactKeys[frame][id]
							or self:sample(track, frame)
						if prefix == "rot" and lastAngle then
							value = angleNear(value, lastAngle)
						end

						lastAngle = value
						local source = ChannelEasing.resolve(key, id)
						table.insert(track.keys, {
							id = track.id .. "/" .. frame,
							frame = frame,
							value = value,
							keyData = key,
							interpolation = (source.EasingStyle == Enum.PoseEasingStyle.Constant)
									and "Legacy"
								or styleName(source.EasingStyle or Defaults.EasingStyle),
							handleType = source.HandleType or Defaults.HandleType,
						})
					end
				end
			end

			track.activeRanges = ranges
			for _, key in track.keys do
				key.inactive = KeyframePolicy.isDisabled(key.keyData, track.channelId)
					or not Activity.contains(ranges, key.frame)
			end

			track.evaluate = function(frame)
				return self:sample(track, frame)
			end

			self:syncModifiers(track)
			table.insert(tracks, track)
		end
	end

	return tracks
end

function Model.prepareDisplay(self: any, track, freezeScale)
	track.displayOffset = 0
	track.displayScale = 100 / (Preferences.get("GraphCompressionPercent") or 10)
	track.displayClamp = Preferences.get("GraphClamp") or 2
	if track.plotDirty then
		track.modCache = nil
	end

	if track.plotPoints and not track.plotDirty then
		return
	end

	local points, keys = {}, track.keys
	local low, high = math.huge, -math.huge
	for _, key in ipairs(keys) do
		low = math.min(low, key.value)
		high = math.max(high, key.value)
	end

	local tolerance = math.max((high - low) * 0.0015, 1e-5)

	local function append(frame, value)
		if not finite(value) then
			return
		end

		table.insert(points, Vector2.new(frame, value))
		low = math.min(low, value)
		high = math.max(high, value)
	end

	local function segment(a, b, depth)
		local mid = (a.X + b.X) * 0.5
		local value = self:sample(track, mid)
		if depth < 5 and #points < 512 and math.abs(value - (a.Y + b.Y) * 0.5) > tolerance then
			segment(a, Vector2.new(mid, value), depth + 1)
			segment(Vector2.new(mid, value), b, depth + 1)
		else
			append(b.X, b.Y)
		end
	end

	if keys[1] then
		append(keys[1].frame, keys[1].value)
	end

	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if a.interpolation == "Constant" then
			append(b.frame, a.value)
			append(b.frame, b.value)
		elseif a.interpolation == "ConstantNext" then
			append(a.frame, b.value)
			append(b.frame, b.value)
		elseif a.interpolation == "Linear" then
			append(b.frame, b.value)
		else
			local previous = Vector2.new(a.frame, a.value)
			for j = 1, 4 do
				local f = a.frame + (b.frame - a.frame) * j / 4
				local point = Vector2.new(f, j == 4 and b.value or self:sample(track, f))
				segment(previous, point, 0)
				previous = point
			end
		end
	end

	track.plotPoints, track.plotDirty = points, false
end

function Model.syncModifiers(self: any, track)
	local mutedId = muteId(track.channelId)
	local mute = mutedId and Mods.get(track.motor, mutedId)
	track.canMute = mutedId ~= nil
	track.muted = mute and mute.Muted == true or false
	local entry = Mods.get(track.motor, track.channelId)
	track.modEntry = entry
	track.hasModifiers = entry ~= nil and #entry.Stack > 0
	track.modifiersOff = entry ~= nil and entry.Off == true
	track.modified = not track.muted and Mods.extends(entry)
	track.linear = entry ~= nil and entry.Extrapolation == "Linear"
	track.keysHidden = track.modified and not Mods.keysUsable(entry)
	track.modCache = nil
	if track.keysHidden then
		for _, key in track.keys do
			key.hidden = true
		end
	else
		for _, key in track.keys do
			key.hidden = nil
		end
	end
end

function Model.sampleModified(self: any, track, frame)
	if not track.modified then
		return self:sample(track, frame)
	end

	local base = function(f)
		return self:sample(track, f)
	end

	local bucket = KeyframePolicy.activeBucket(self.Timeline:GetState().Keyframes[track.motor])
	return (
		Mods.evaluate(track.modEntry, frame, base, function()
			local first, last = Mods.keySpan(bucket, track.channelId)
			return first and { first, base(first), last, base(last) } or nil
		end)
	)
end

function Model.modifiedPoints(self: any, track, frameMin, frameMax, pixelsPerFrame)
	if not (track.modified or track.linear) then
		return nil
	end

	local step = math.max(0.1, 2.5 / math.max(pixelsPerFrame, 1e-6))
	step = 2 ^ math.ceil(math.log(step, 2) - 1e-9)
	local cache = track.modCache
	if not cache or cache.step ~= step then
		cache = { step = step, values = {}, count = 0 }
		track.modCache = cache
	end

	local base = function(f)
		return self:sample(track, f)
	end

	local bucket = KeyframePolicy.activeBucket(self.Timeline:GetState().Keyframes[track.motor])
	local span
	local range = function()
		if span == nil then
			local first, last = Mods.keySpan(bucket, track.channelId)
			span = first and { first, base(first), last, base(last) } or false
		end

		return span or nil
	end

	local first = math.floor(frameMin / step) - 1
	local last = math.min(math.ceil(frameMax / step) + 1, first + 4000)
	local points = table.create(last - first + 1)
	local values = cache.values
	for i = first, last do
		local v = values[i]
		if v == nil then
			v = Mods.evaluate(track.modEntry, i * step, base, range)
			if not finite(v) then
				v = false
			end

			values[i] = v
			cache.count += 1
		end

		if v then
			table.insert(points, Vector2.new(i * step, v))
		end
	end

	if cache.count > 24000 then
		track.modCache = nil
	end

	return points
end

function Model.handles(self: any, track, key)
	local fps = self.Timeline:GetState().FPS
	local channel =
		Curves.compile(self.Timeline:GetState().Keyframes[track.motor]).channels[track.channelId]
	if channel then
		for index, point in ipairs(channel) do
			if point.frame == key.frame then
				local left, right = Curves.pointHandles(
					channel,
					index,
					self.Timeline:IsLooping() and self.Timeline:GetPlaybackEndTime() or nil
				)
				return { frame = left.time * fps, value = left.value }, {
					frame = right.time * fps,
					value = right.value,
				}
			end
		end
	end

	local index = table.find(track.keys, key) or 1
	local previous, following = track.keys[index - 1], track.keys[index + 1]
	local source = ChannelEasing.resolve(key.keyData, track.channelId)
	if
		track.group ~= "Euler Rotation"
		and track.group ~= "Quaternion Rotation"
		and #track.keys >= 2
	then
		local leftAutomatic = not previous
			or Interp.usesAutomaticBezier(
				ChannelEasing.resolve(previous.keyData, track.channelId),
				source
			)
		local rightAutomatic = not following
			or Interp.usesAutomaticBezier(
				source,
				ChannelEasing.resolve(following.keyData, track.channelId)
			)
		if leftAutomatic and rightAutomatic then
			local handle = source.HandleType or Defaults.HandleType
			local ll, rr = Bezier.lengths(
				previous and previous.frame,
				key.frame,
				following and following.frame,
				handle
			)
			local lv, rv = Bezier.handles(
				previous and previous.value,
				key.value,
				following and following.value,
				previous and previous.frame,
				key.frame,
				following and following.frame,
				ll,
				rr,
				handle
			)
			return { frame = key.frame - ll, value = lv }, { frame = key.frame + rr, value = rv }
		end
	end

	local leftSpan = previous and key.frame - previous.frame
		or following and following.frame - key.frame
		or fps
	local rightSpan = following and following.frame - key.frame or leftSpan
	local epsilon = math.min(0.05, leftSpan / 100, rightSpan / 100)
	local leftSlope = (self:sample(track, key.frame) - self:sample(track, key.frame - epsilon))
		/ epsilon
	local rightSlope = (self:sample(track, key.frame + epsilon) - self:sample(track, key.frame))
		/ epsilon
	if
		previous
		and styleName(
				ChannelEasing.resolve(previous.keyData, track.channelId).EasingStyle
					or Defaults.EasingStyle
			)
			== "Constant"
	then
		leftSlope = 0
	end

	if styleName(source.EasingStyle or Defaults.EasingStyle) == "Constant" then
		rightSlope = 0
	end

	return { frame = key.frame - leftSpan / 3, value = key.value - leftSlope * leftSpan / 3 }, {
		frame = key.frame + rightSpan / 3,
		value = key.value + rightSlope * rightSpan / 3,
	}
end

function Model._adopt(self: any, track)
	local state = self.Timeline:GetState()
	local bucket = state.Keyframes[track.motor]
	if not bucket then
		bucket = {}
		state.Keyframes[track.motor] = bucket
	end

	if Curves.compile(bucket).channels[track.channelId] then
		return
	end

	local originalHandles = {}
	for _, key in ipairs(track.keys) do
		if
			styleName(
				ChannelEasing.resolve(key.keyData, track.channelId).EasingStyle
					or Defaults.EasingStyle
			) == "Bezier"
		then
			originalHandles[key] = { self:handles(track, key) }
		end
	end

	for _, key in ipairs(track.keys) do
		local data = bucket[key.frame]
		if data then
			data.GraphCurves = data.GraphCurves or {}
			local source = ChannelEasing.resolve(data, track.channelId)
			local style = styleName(source.EasingStyle or Defaults.EasingStyle)
			local point = {
				Id = key.id,
				Value = key.value,
				HandleType = source.HandleType or Defaults.HandleType or "AutoClamped",
			}
			if
				style == "Linear"
				or style == "Constant"
					and not (typeof(source.EasingStyle) == "EnumItem" and source.EasingStyle.EnumType == Enum.PoseEasingStyle)
			then
				point.Interpolation = style
			elseif style == "Bezier" then
				point.Interpolation = "Bezier"
				local left, right = originalHandles[key][1], originalHandles[key][2]

				point.HandleType = (point.HandleType == "Free" or point.HandleType == "Vector")
						and "Free"
					or "Aligned"
				point.In = { (left.frame - key.frame) / state.FPS, left.value - key.value }
				point.Out = { (right.frame - key.frame) / state.FPS, right.value - key.value }
			else
				point.Interpolation = "Legacy"
				point.Easing = {
					EasingStyle = style,
					NativePose = typeof(source.EasingStyle) == "EnumItem"
						and source.EasingStyle.EnumType == Enum.PoseEasingStyle,
					EasingDirection = styleName(source.EasingDirection or Defaults.EasingDirection),
					BezierPoints = Curves.clone(source.BezierPoints),
					Overshoot = source.Overshoot,
					Amplitude = source.Amplitude,
					Period = source.Period,
					MoonEasing = source.MoonEasing,
				}
			end

			point.ChannelEasing = Curves.clone(
				data.Channels
					and data.Channels[track.channelId]
					and data.Channels[track.channelId].Easing
			)
			data.GraphCurves[track.channelId] = point
		end
	end

	Curves.invalidate(bucket)
end

function Model._restoreRaw(self: any, snapshots)
	local state = self.Timeline:GetState()
	for motor, snapshot in pairs(snapshots) do
		local bucket = state.Keyframes[motor] or {}
		state.Keyframes[motor] = bucket
		local buttons = {}
		for frame, key in pairs(bucket) do
			if key.Button then
				buttons[frame] = key.Button
			end
		end

		table.clear(bucket)
		for frame, key in pairs(snapshot) do
			local copy = cloneKey(key)
			copy.Button = buttons[frame]
			buttons[frame] = nil
			bucket[frame] = copy
			if copy.Button then
				self.Timeline:CreateOrUpdateTimelineKeyframeButton(
					copy.Part or motor.Part1,
					motor,
					frame,
					copy.Template,
					copy.SanitizeName
				)
			end
		end

		for _, button in pairs(buttons) do
			if button.Parent then
				button:Destroy()
			end
		end

		state._motorUniform[motor], state._motorHasScale[motor] = nil, nil
		Curves.invalidate(bucket)
	end

	self:invalidate()
end

function Model._restoreFinal(self: any, snapshots, phase)
	if self.Timeline.ApplyEditedBuckets then
		self.Timeline:ApplyEditedBuckets(snapshots)
	else
		for motor, snapshot in snapshots do
			self.Timeline:_restoreMotorBucket(motor, snapshot)
		end
	end

	self:_notify(phase)
end

function Model.begin(self: any, label, items)
	if BlenderEdit.blocked() then
		return
	end

	if self._transaction then
		self:cancel(self._transaction)
	end

	local tx = {
		label = label or "Edit graph keys",
		items = items or {},
		before = {},
		originals = {},
		changed = false,
	}
	local state = self.Timeline:GetState()
	for _, item in ipairs(tx.items) do
		local motor = item.track.motor
		if not tx.before[motor] then
			tx.before[motor] = copyBucket(state.Keyframes[motor])
		end

		table.insert(
			tx.originals,
			{ item = item, frame = item.key.frame, value = item.key.value, id = item.key.id }
		)
	end

	local adopted = {}
	for _, item in ipairs(tx.items) do
		if not adopted[item.track.id] then
			adopted[item.track.id] = true
			self:_adopt(item.track)
		end
	end

	tx.working = {}
	for motor in pairs(tx.before) do
		tx.working[motor] = copyBucket(state.Keyframes[motor])
	end

	self._transaction = tx
	return tx
end

function Model._ensureKey(self: any, motor, frame, template)
	local state = self.Timeline:GetState()
	local bucket = state.Keyframes[motor]
	local key = bucket[frame]
	if not key then
		local cf = template and template.C0 or state.DefaultPose[motor] or motor.C0
		key = {
			Frame = frame,
			Time = frame / state.FPS,
			Motor = motor,
			Part = motor.Part1,
			C0 = cf,
			Position = cf.Position,
			Rotation = cf.Rotation,
			Channels = {},
			GraphOnly = true,
			SanitizeName = template and template.SanitizeName,
		}
		bucket[frame] = key
	end

	key.GraphCurves = key.GraphCurves or {}
	return key
end

function Model._touch(self: any, tx)
	tx.changed = true
	for _, item in ipairs(tx.items) do
		item.track.plotDirty = true
	end

	for motor in pairs(tx.before) do
		local state = self.Timeline:GetState()
		state._motorUniform[motor], state._motorHasScale[motor] = nil, nil
		Curves.invalidate(state.Keyframes[motor])
	end

	local state = self.Timeline:GetState()
	for _, original in tx.originals do
		local motor = original.item.track.motor
		local bucket = state.Keyframes[motor]
		local key = bucket and bucket[original.frame]
		if
			key
			and (not key.GraphCurves or not next(key.GraphCurves))
			and not Curves.hasVisibleKey(bucket, key)
		then
			removeKey(self.Timeline, motor, bucket, original.frame)
			Curves.invalidate(bucket)
		end
	end

	self:_notify("preview")
end

function Model.updateTransform(self: any, tx, transform)
	if tx ~= self._transaction then
		return false, "No graph edit in progress"
	end

	local targets, occupied = {}, {}
	for _, original in tx.originals do
		local item = original.item
		local frame, value = transform(original.frame, original.value, item.track)
		if not tx.preserveFrameTimes and frame ~= original.frame then
			frame = math.round(frame)
		end

		if not finite(frame) or not finite(value) or frame < 0 then
			return false, "Keys cannot move before frame 0"
		end

		local id = item.track.id .. "/" .. frame
		if occupied[id] then
			if not tx.merge then
				return false, "Keys overlap on the same channel"
			end
		else
			occupied[id] = true
			table.insert(targets, { original = original, frame = frame, value = value })
		end
	end

	local selected = {}
	for _, original in tx.originals do
		selected[original.item.track.id .. "/" .. original.frame] = true
	end
	if not tx.merge then
		for _, target in targets do
			local track = target.original.item.track
			local key = tx.working[track.motor][target.frame]
			if key and key.GraphCurves and key.GraphCurves[track.channelId]
				and not selected[track.id .. "/" .. target.frame] then
				return false, "A key already exists on this channel at that frame"
			end
		end
	end
	local state = self.Timeline:GetState()
	local unchanged = not tx.duplicate and not tx.pointMap
	for _, target in targets do
		local original = target.original
		if target.frame ~= original.frame or target.value ~= original.value then
			unchanged = false
			break
		end

		local point =
			tx.working[original.item.track.motor][original.frame].GraphCurves[original.item.track.channelId]
		for _, side in { "In", "Out" } do
			local handle = point[side]
			if handle then
				local f, v = original.frame + handle[1] * state.FPS, original.value + handle[2]
				local movedFrame, movedValue = transform(f, v, original.item.track)
				if movedFrame ~= f or movedValue ~= v then
					unchanged = false
				end
			end
		end
	end

	if unchanged then
		self:_restoreRaw(tx.before)
		tx.changed = false
		for _, original in tx.originals do
			original.item.key.frame, original.item.key.value = original.frame, original.value
			original.item.key.keyData = state.Keyframes[original.item.track.motor][original.frame]
			original.item.track.plotDirty = true
		end

		self:_notify("preview")
		return true
	end

	self:_restoreRaw(tx.working)
	if not tx.duplicate then
		for _, original in tx.originals do
			local item = original.item
			local key = state.Keyframes[item.track.motor][original.frame]
			key.GraphCurves[item.track.channelId] = nil
			KeyGroups.set(key, item.track.channelId, nil)
		end
	end

	for _, target in targets do
		local original = target.original
		local item = original.item
		local source = tx.working[item.track.motor][original.frame]
		local point = Curves.clone(source.GraphCurves[item.track.channelId])
		if tx.duplicate then
			original.duplicateId = original.duplicateId or nextId()
			point.Id = original.duplicateId
		end

		if tx.pointMap then
			tx.pointMap(point, item.track)
		else
			for _, side in { "In", "Out" } do
				local handle = point[side]
				if handle then
					local x, y = transform(
						original.frame + handle[1] * state.FPS,
						original.value + handle[2],
						item.track
					)
					point[side] = { (x - target.frame) / state.FPS, y - target.value }
				end
			end
		end

		point.Value = target.value
		local key = self:_ensureKey(item.track.motor, target.frame, source)
		key.GraphCurves[item.track.channelId] = point
		KeyGroups.set(key, item.track.channelId, KeyGroups.get(source, item.track.channelId))
		item.key.frame, item.key.value, item.key.keyData = target.frame, target.value, key
		item.key.id = point.Id or item.key.id
	end

	for motor in tx.before do
		for frame, key in state.Keyframes[motor] do
			if key.GraphCurves and not next(key.GraphCurves) then
				key.GraphCurves = nil
			end

			if key.GraphOnly and not key.GraphCurves then
				removeKey(self.Timeline, motor, state.Keyframes[motor], frame)
			end
		end
	end

	self:_touch(tx)
	for _, item in tx.items do
		table.sort(item.track.keys, function(a, b)
			return a.frame < b.frame
		end)
	end

	for _, item in tx.items do
		item.key.left, item.key.right = self:handles(item.track, item.key)
	end

	return true
end

function Model.updateMove(self: any, tx, deltaFrame, deltaValue)
	if tx ~= self._transaction or not finite(deltaFrame) or not finite(deltaValue) then
		return false, "Invalid graph edit"
	end

	deltaFrame = math.round(deltaFrame)

	if tx.duplicate or deltaFrame ~= 0 then
		return self:updateTransform(tx, function(frame, value, track)
			return frame + deltaFrame,
				value + deltaValue * (tx.valueScales and tx.valueScales[track.id] or 1)
		end)
	end

	local state = self.Timeline:GetState()
	local selected = {}
	for _, original in ipairs(tx.originals) do
		local item = original.item
		selected[item.track.id .. "/" .. original.frame] = true
	end

	for _, original in ipairs(tx.originals) do
		local item, frame = original.item, original.frame + deltaFrame
		if frame < 0 then
			return false, "Keys cannot move before frame 0"
		end

		local occupied = tx.working[item.track.motor][frame]
		if
			occupied
			and occupied.GraphCurves
			and occupied.GraphCurves[item.track.channelId]
			and not selected[item.track.id .. "/" .. frame]
		then
			return false, "A key already exists on this channel at that frame"
		end
	end

	if tx.lastMove then
		for _, original in ipairs(tx.originals) do
			local item = original.item
			local bucket = state.Keyframes[item.track.motor]
			local key = bucket[item.key.frame]
			if key and key.GraphCurves then
				key.GraphCurves[item.track.channelId] = nil
				KeyGroups.set(key, item.track.channelId, nil)
				if not next(key.GraphCurves) then
					key.GraphCurves = nil
				end

				if key.GraphOnly and not key.GraphCurves then
					removeKey(self.Timeline, item.track.motor, bucket, item.key.frame)
				end
			end
		end

		for _, original in ipairs(tx.originals) do
			local item = original.item
			local source = tx.working[item.track.motor][original.frame]
			local key = self:_ensureKey(item.track.motor, original.frame, source)
			key.GraphCurves[item.track.channelId] =
				Curves.clone(source.GraphCurves[item.track.channelId])
			KeyGroups.set(key, item.track.channelId, KeyGroups.get(source, item.track.channelId))
		end
	end

	local moving = {}
	for _, original in ipairs(tx.originals) do
		local item = original.item
		local bucket = state.Keyframes[item.track.motor]
		local source = bucket[original.frame]
		local point = source and source.GraphCurves and source.GraphCurves[item.track.channelId]
		if point then
			table.insert(moving, {
				original = original,
				source = source,
				point = point,
				group = KeyGroups.get(source, item.track.channelId),
			})
			KeyGroups.set(source, item.track.channelId, nil)
			source.GraphCurves[item.track.channelId] = nil
		end
	end

	for _, move in ipairs(moving) do
		local original, item = move.original, move.original.item
		local frame, value =
			original.frame + deltaFrame,
			original.value + deltaValue * (tx.valueScales and tx.valueScales[item.track.id] or 1)
		local target = self:_ensureKey(item.track.motor, frame, move.source)
		move.point.Value = value
		target.GraphCurves[item.track.channelId] = move.point
		KeyGroups.set(target, item.track.channelId, move.group)
		item.key.frame, item.key.value, item.key.keyData = frame, value, target
	end

	for motor in pairs(tx.before) do
		local bucket = state.Keyframes[motor]
		for frame, key in pairs(bucket) do
			if key.GraphCurves and not next(key.GraphCurves) then
				key.GraphCurves = nil
			end

			if key.GraphOnly and not key.GraphCurves then
				removeKey(self.Timeline, motor, bucket, frame)
			end
		end
	end

	self:_touch(tx)
	tx.lastMove = true
	local sorted = {}
	for _, item in ipairs(tx.items) do
		if not sorted[item.track] then
			sorted[item.track] = true
			table.sort(item.track.keys, function(a, b)
				return a.frame < b.frame
			end)
		end
	end

	for _, item in ipairs(tx.items) do
		item.key.left, item.key.right = self:handles(item.track, item.key)
	end

	return true
end

function Model.updateHandle(self: any, tx, item, side, frame, value, metric)
	if tx ~= self._transaction or not finite(frame) or not finite(value) then
		return false
	end

	local bucket = self.Timeline:GetState().Keyframes[item.track.motor]
	local key = bucket[item.key.frame]
	local point = key and key.GraphCurves and key.GraphCurves[item.track.channelId]
	if not point then
		return false
	end

	local left, right = self:handles(item.track, item.key)
	local fps, field = self.Timeline:GetState().FPS, side == "left" and "In" or "Out"
	local channel = Curves.compile(bucket).channels[item.track.channelId]
	local index
	for i, entry in ipairs(channel) do
		if entry.frame == item.key.frame then
			index = i
			break
		end
	end

	if not index then
		return false
	end

	local previous, following = channel[index - 1], channel[index + 1]
	if not tx.handle then
		point.In = { (left.frame - item.key.frame) / fps, left.value - item.key.value }
		point.Out = { (right.frame - item.key.frame) / fps, right.value - item.key.value }
		local opposite = field == "In" and point.Out or point.In
		metric = metric or { frame = 1, value = 1 }
		tx.handle = {
			metric = metric,
			oppositeLength = Vector2.new(
				opposite[1] * fps / metric.frame,
				opposite[2] / metric.value
			).Magnitude,
		}
	end

	if field == "In" then
		frame = math.min(frame, item.key.frame)
	else
		frame = math.max(frame, item.key.frame)
	end

	point[field] = { (frame - item.key.frame) / fps, value - item.key.value }
	point.Interpolation = "Bezier"
	if point.HandleType == "Automatic" or point.HandleType == "AutoClamped" then
		point.HandleType = "Aligned"
	end

	if point.HandleType ~= "Aligned" then
		point.HandleType = "Free"
	else
		local m = tx.handle.metric
		local direction =
			Vector2.new((frame - item.key.frame) / m.frame, (value - item.key.value) / m.value)
		if direction.Magnitude > 1e-8 then
			local other = -direction.Unit * tx.handle.oppositeLength
			local dt, dv = other.X * m.frame / fps, other.Y * m.value
			point[field == "In" and "Out" or "In"] = { dt, dv }
		end
	end

	ChannelEasing.graphChanged(key, item.track.channelId)
	item.key.interpolation, item.key.handleType = "Bezier", point.HandleType

	if side == "left" or point.HandleType == "Aligned" then
		local channel = Curves.compile(bucket).channels[item.track.channelId]
		for i, entry in ipairs(channel or {}) do
			if entry.frame == item.key.frame and channel[i - 1] then
				channel[i - 1].point.Interpolation = "Bezier"
				ChannelEasing.graphChanged(channel[i - 1].key, item.track.channelId)
				for _, previousKey in ipairs(item.track.keys) do
					if previousKey.frame == channel[i - 1].frame then
						previousKey.interpolation = "Bezier"
						break
					end
				end

				break
			end
		end
	end

	self:_touch(tx)
	item.key.left, item.key.right = self:handles(item.track, item.key)
	return true
end

function Model.commit(self: any, tx)
	if tx ~= self._transaction then
		return false
	end

	self._transaction = nil
	if not tx.changed then
		self:_restoreFinal(tx.before, "cancel")
		return false
	end

	local after = {}
	for motor in pairs(tx.before) do
		local bucket = self.Timeline:GetState().Keyframes[motor]
		after[motor] = copyBucket(bucket)
		for frame in pairs(after[motor]) do
			self.Timeline:EnsureTimelineEnd(frame)
		end
	end

	self:_restoreFinal(after, "commit")
	for motor, bucket in after do
		require("HumanoidScale").bucketsChanged(motor, tx.before[motor], bucket)
	end

	if self.History then
		self.History.record(function()
			if tx.onUndo then
				tx.onUndo()
			end

			self:_restoreFinal(tx.before, "undo")
		end, function()
			if tx.onRedo then
				tx.onRedo()
			end

			self:_restoreFinal(after, "redo")
		end, tx.label)
	end

	return true
end

function Model.cancel(self: any, tx)
	if tx ~= self._transaction then
		return false
	end

	self._transaction = nil
	for _, original in ipairs(tx.originals) do
		original.item.key.frame, original.item.key.value = original.frame, original.value
	end

	self:_restoreFinal(tx.before, "cancel")
	return true
end

function Model.insert(self: any, track, frame, value)
	if BlenderEdit.blocked() then
		return
	end

	if not finite(frame) or (value ~= nil and not finite(value)) then
		return false
	end

	frame = math.max(0, math.round(frame))
	value = value or self:sample(track, frame)
	local state = self.Timeline:GetState()
	local tx = self:begin("Insert graph key", {})
	tx.before[track.motor] = copyBucket(state.Keyframes[track.motor])
	self:_adopt(track)
	local key = self:_ensureKey(track.motor, frame)
	local existing = key.GraphCurves[track.channelId]
	if not existing then
		local creation = KeyframeDefaults.new(state.Keyframes[track.motor], frame)
		existing = Curves.newPoint(creation)
		existing.Id = nextId()
		if track.channelId:sub(1, 4) == "rot_" then
			existing.RotationOrder = Curves.rotationOrder(state.Keyframes[track.motor])
		end
	end

	key.GraphCurves[track.channelId] = existing
	key.GraphCurves[track.channelId].Value = value
	key.GraphCurves[track.channelId].Empty = nil
	self:_touch(tx)
	return self:commit(tx)
end

function Model.delete(self: any, items)
	if BlenderEdit.blocked() then
		return
	end

	if not items or #items == 0 then
		return false
	end

	local tx = self:begin("Delete graph keys", items)
	local state = self.Timeline:GetState()
	for _, item in ipairs(items) do
		local bucket = state.Keyframes[item.track.motor]
		local key = bucket[item.key.frame]
		local reset = self.Timeline:ResetDeletedFirstTransformKey(
			item.track.motor,
			key,
			{ [item.track.channelId] = true }
		)
		if reset then
			bucket[item.key.frame] = reset
		elseif key and key.GraphCurves then
			key.GraphCurves[item.track.channelId] = nil
			KeyGroups.set(key, item.track.channelId, nil)
			if not next(key.GraphCurves) then
				key.GraphCurves = nil
			end

			if key.GraphOnly and not key.GraphCurves then
				removeKey(self.Timeline, item.track.motor, bucket, item.key.frame)
			end
		end
	end

	local seen = {}
	for _, item in ipairs(items) do
		if seen[item.track.id] then
			continue
		end

		seen[item.track.id] = true
		Curves.invalidate(state.Keyframes[item.track.motor])
		if not Curves.compile(state.Keyframes[item.track.motor]).channels[item.track.channelId] then
			local key = self:_ensureKey(item.track.motor, 0)
			local cf = state.DefaultPose[item.track.motor] or item.track.motor.C0
			local order = Curves.rotationOrder(state.Keyframes[item.track.motor])
			local ex, ey, ez = Curves.euler(cf, order)
			local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
			local q = Quaternion.fromCFrame(cf)
			local rest = {
				qrot_w = q.w,
				qrot_x = q.x,
				qrot_y = q.y,
				qrot_z = q.z,
				loc_x = cf.X,
				loc_y = cf.Y,
				loc_z = cf.Z,
				rot_x = math.deg(x),
				rot_y = math.deg(y),
				rot_z = math.deg(z),
				scale_x = 1,
				scale_y = 1,
				scale_z = 1,
			}
			key.GraphCurves[item.track.channelId] = {
				Id = nextId(),
				Value = rest[item.track.channelId],
				Interpolation = "Constant",
				HandleType = "Vector",
				Empty = true,
				RotationOrder = item.track.channelId:sub(1, 4) == "rot_" and order or nil,
			}
		end
	end

	self:_touch(tx)
	return self:commit(tx)
end

function Model.setInterpolation(self: any, items, name)
	if BlenderEdit.blocked() then
		return
	end

	if name ~= "Bezier" and name ~= "Linear" and name ~= "Constant" then
		return false
	end

	if not items or #items == 0 then
		return false
	end

	local tx = self:begin("Set graph interpolation", items)
	for _, item in ipairs(items) do
		local key = self.Timeline:GetState().Keyframes[item.track.motor][item.key.frame]
		key.GraphCurves[item.track.channelId].Interpolation = name
		ChannelEasing.graphChanged(key, item.track.channelId)
	end

	self:_touch(tx)
	return self:commit(tx)
end

function Model.setEasing(self: any, items, values)
	if BlenderEdit.blocked() or not items or #items == 0 then
		return false
	end

	local normalized = {}
	local Settings = require("SavedDefaults")
	for _, field in ChannelEasing.fields do
		if values[field] ~= nil then
			local value = Settings.normalize(field, values[field])
			if value == nil then
				return false
			end

			normalized[field] = Curves.clone(value)
		end
	end

	if not normalized.EasingStyle then
		return false
	end

	local tx = self:begin("Set graph easing", items)
	if not tx then
		return false
	end

	for _, item in items do
		local key = self.Timeline:GetState().Keyframes[item.track.motor][item.key.frame]
		local point = key.GraphCurves[item.track.channelId]
		point.Interpolation = "Legacy"
		point.Easing = Curves.clone(normalized)
		point.In = nil
		point.Out = nil
		point.BlenderHandles = nil
		local overrides = {}
		for field, value in normalized do
			if not ChannelEasing.equal(value, key[field] or Defaults[field]) then
				overrides[field] = Curves.clone(value)
			end
		end

		point.ChannelEasing = next(overrides) and overrides or nil
	end

	self:_touch(tx)
	return self:commit(tx)
end

function Model.setHandleType(self: any, items, name)
	if BlenderEdit.blocked() then
		return
	end

	if name == "Auto" then
		name = "Automatic"
	end

	if
		not ({ Automatic = true, AutoClamped = true, Vector = true, Aligned = true, Free = true })[name]
	then
		return false
	end

	if not items or #items == 0 then
		return false
	end

	local tx = self:begin("Set graph handles", items)
	for _, item in ipairs(items) do
		local key = self.Timeline:GetState().Keyframes[item.track.motor][item.key.frame]
		local point = key.GraphCurves[item.track.channelId]
		local left, right = self:handles(item.track, item.key)
		point.BlenderHandles = nil
		point.HandleType, point.Interpolation = name, "Bezier"
		ChannelEasing.graphChanged(key, item.track.channelId)
		Curves.activateIncoming(
			self.Timeline:GetState().Keyframes[item.track.motor],
			key,
			item.track.channelId
		)
		if name == "Free" or name == "Aligned" then
			local fps = self.Timeline:GetState().FPS
			point.In = { (left.frame - item.key.frame) / fps, left.value - item.key.value }
			point.Out = { (right.frame - item.key.frame) / fps, right.value - item.key.value }
			if name == "Aligned" and math.abs(point.Out[1]) > 1e-9 then
				point.In[2] = point.In[1] * point.Out[2] / point.Out[1]
			end
		else
			point.In, point.Out = nil, nil
		end
	end

	self:_touch(tx)
	return self:commit(tx)
end

function Model.remapKeys(self: any, label, items, keyMap, pointMap, merge)
	if BlenderEdit.blocked() then
		return false
	end

	if not items or #items == 0 then
		return false
	end

	local tx = self:begin(label, items)
	if not tx then
		return false
	end

	tx.snap, tx.pointMap, tx.merge = false, pointMap, merge
	tx.preserveFrameTimes = true
	local ok, err = self:updateTransform(tx, keyMap)
	if ok == false then
		self:cancel(tx)
		return false, err
	end

	return self:commit(tx)
end

function Model.flattenHandles(self: any, items)
	if BlenderEdit.blocked() then
		return false
	end

	if not items or #items == 0 then
		return false
	end

	local tx = self:begin("Flatten Handles", items)
	if not tx then
		return false
	end

	local state = self.Timeline:GetState()
	local handles = {}
	for index, item in ipairs(items) do
		handles[index] = { self:handles(item.track, item.key) }
	end

	for index, item in ipairs(items) do
		local key = state.Keyframes[item.track.motor][item.key.frame]
		local point = key and key.GraphCurves and key.GraphCurves[item.track.channelId]
		if point then
			local left, right = handles[index][1], handles[index][2]
			point.BlenderHandles = nil
			point.In = { (left.frame - item.key.frame) / state.FPS, 0 }
			point.Out = { (right.frame - item.key.frame) / state.FPS, 0 }
			if point.HandleType ~= "Free" then
				point.HandleType = "Aligned"
			end

			ChannelEasing.graphChanged(key, item.track.channelId)
		end
	end

	self:_touch(tx)
	return self:commit(tx)
end

function Model.setExtrapolation(self: any, tracks, mode)
	if BlenderEdit.blocked() then
		return false
	end

	local motors, items = {}, {}
	for _, track in ipairs(tracks) do
		motors[track.motor] = true
		if track.keys[1] then
			table.insert(items, { track = track, key = track.keys[1] })
		end
	end

	if not next(motors) then
		return false
	end

	local before, after = {}, {}
	for motor in pairs(motors) do
		before[motor] = Mods.snapshot(motor)
	end

	local function apply()
		for _, track in ipairs(tracks) do
			local entry = Mods.ensure(track.motor, track.channelId)
			entry.Extrapolation = mode == "Linear" and "Linear" or nil
		end

		for motor in pairs(motors) do
			Mods.prune(motor)
			Mods.touch(motor)
			after[motor] = Mods.snapshot(motor)
		end
	end

	local function restore(state)
		for motor in pairs(motors) do
			Mods.restore(motor, state[motor])
		end
	end

	local label = mode == "Linear" and "Linear Extrapolation" or "Constant Extrapolation"
	if mode ~= "Linear" or #items == 0 then
		apply()
		self:_notify("commit")
		if self.History then
			self.History.record(function()
				restore(before)
				self:_notify("undo")
			end, function()
				restore(after)
				self:_notify("redo")
			end, label)
		end

		return true
	end

	local tx = self:begin(label, items)
	if not tx then
		return false
	end

	apply()
	tx.onUndo = function()
		restore(before)
	end

	tx.onRedo = function()
		restore(after)
	end

	self:_touch(tx)
	return self:commit(tx)
end

function Model.filterRotation(self: any, tracks)
	if BlenderEdit.blocked() then
		return false
	end

	local before, after = {}, {}
	for _, track in tracks do
		local motor = track.motor
		if not before[motor] then
			before[motor] = copyBucket(self.Timeline:GetState().Keyframes[motor])
			local copy = copyBucket(before[motor])
			if Curves.filterRotation(copy) then
				after[motor] = copy
			end
		end
	end

	if not next(after) then
		return false
	end

	for motor in before do
		if not after[motor] then
			before[motor] = nil
		end
	end

	self:_restoreFinal(after, "commit")
	if self.History then
		self.History.record(function()
			self:_restoreFinal(before, "undo")
		end, function()
			self:_restoreFinal(after, "redo")
		end, "Filter rotation discontinuities")
	end

	return true
end

function Model.copy(self: any, items)
	if not items or #items == 0 then
		return nil
	end

	local minimum, entries = math.huge, {}
	local state = self.Timeline:GetState()
	for _, item in ipairs(items) do
		minimum = math.min(minimum, item.key.frame)
	end

	for _, item in ipairs(items) do
		local track, key = item.track, item.key
		local data = state.Keyframes[track.motor] and state.Keyframes[track.motor][key.frame]
		local point = data and data.GraphCurves and data.GraphCurves[track.channelId]
		if point then
			point = Curves.clone(point)
		else
			local source = ChannelEasing.resolve(data, track.channelId)
			local style = styleName(data and source.EasingStyle or Defaults.EasingStyle)
			point = {
				Value = key.value,
				HandleType = "Free",
				ChannelEasing = Curves.clone(
					data
						and data.Channels
						and data.Channels[track.channelId]
						and data.Channels[track.channelId].Easing
				),
			}
			if
				style == "Linear"
				or style == "Constant"
					and not (data and typeof(source.EasingStyle) == "EnumItem" and source.EasingStyle.EnumType == Enum.PoseEasingStyle)
			then
				point.Interpolation = style
			elseif style == "Bezier" then
				local left, right = self:handles(track, key)
				point.Interpolation = "Bezier"
				point.In = { (left.frame - key.frame) / state.FPS, left.value - key.value }
				point.Out = { (right.frame - key.frame) / state.FPS, right.value - key.value }
			else
				point.Interpolation = "Legacy"
				point.Easing = {
					EasingStyle = style,
					NativePose = data
						and typeof(source.EasingStyle) == "EnumItem"
						and source.EasingStyle.EnumType == Enum.PoseEasingStyle,
					EasingDirection = styleName(
						data and source.EasingDirection or Defaults.EasingDirection
					),
					BezierPoints = Curves.clone(data and source.BezierPoints),
					Overshoot = data and source.Overshoot,
					Amplitude = data and source.Amplitude,
					Period = data and source.Period,
					MoonEasing = data and source.MoonEasing,
				}
			end
		end

		table.insert(entries, {
			motor = track.motor,
			channelId = track.channelId,
			offsetFrame = key.frame - minimum,
			point = point,
			track = track,
			group = data and KeyGroups.get(data, track.channelId),
		})
	end

	return { entries = entries, originFrame = minimum }
end

function Model.paste(self: any, clipboard, atFrame)
	if BlenderEdit.blocked() then
		return
	end

	if not clipboard or not clipboard.entries or #clipboard.entries == 0 or not finite(atFrame) then
		return false, "Copy graph keys first"
	end

	local state = self.Timeline:GetState()
	local tracks, motors, seen = {}, {}, {}
	for _, entry in ipairs(clipboard.entries) do
		local ok, active = pcall(function()
			return entry.motor.Parent ~= nil
				and entry.motor.Part1 ~= nil
				and state.DefaultPose[entry.motor] ~= nil
		end)
		if not ok or not active then
			return false, "The copied control is no longer in this animation"
		end

		local order = Curves.rotationOrder(state.Keyframes[entry.motor])
		if
			entry.point
			and entry.point.RotationOrder ~= order
			and entry.channelId:sub(1, 4) == "rot_"
		then
			return false, "Convert to the copied Euler order before pasting rotation curves"
		end

		if order and entry.channelId:sub(1, 5) == "qrot_" then
			return false, "Convert this track to Quaternion before pasting quaternion curves"
		end

		if not seen[entry.motor] then
			seen[entry.motor] = true
			table.insert(motors, entry.motor)
		end
	end

	for _, track in ipairs(self:tracks(motors)) do
		tracks[track.motor] = tracks[track.motor] or {}
		tracks[track.motor][track.channelId] = track
	end

	local tx = self:begin("Paste graph keys", {})
	for _, motor in ipairs(motors) do
		tx.before[motor] = copyBucket(state.Keyframes[motor])
	end

	local touched = {}
	for _, entry in ipairs(clipboard.entries) do
		local track = tracks[entry.motor][entry.channelId]
		if not touched[track] then
			touched[track] = true
			self:_adopt(track)
		end
	end

	local pasted, groupIds = {}, {}
	for _, entry in ipairs(clipboard.entries) do
		local frame = math.max(0, atFrame + entry.offsetFrame)
		local key = self:_ensureKey(entry.motor, frame)
		local point = Curves.clone(entry.point)
		point.Id, point.Empty = nextId(), nil
		key.GraphCurves[entry.channelId] = point
		if entry.group then
			groupIds[entry.group] = groupIds[entry.group]
				or game:GetService("HttpService"):GenerateGUID(false)
		end

		KeyGroups.set(key, entry.channelId, entry.group and groupIds[entry.group])
		table.insert(pasted, {
			track = tracks[entry.motor][entry.channelId],
			key = {
				id = point.Id,
				frame = frame,
				value = point.Value,
				keyData = key,
				interpolation = point.Interpolation,
				handleType = point.HandleType,
			},
		})
	end

	self:_touch(tx)
	self:commit(tx)
	return true, pasted
end

function Model.duplicate(self: any, items, offsetFrames)
	if BlenderEdit.blocked() then
		return
	end

	local clipboard = self:copy(items)
	if not clipboard then
		return false, "Select graph keys to duplicate"
	end

	return self:paste(clipboard, clipboard.originFrame + (offsetFrames or 1))
end

function Model.setRotationMode(self, motors, mode)
	if BlenderEdit.blocked() then
		return false
	end

	assert(mode == "Quaternion" or Curves.validRotationOrder(mode), "Invalid rotation mode")
	local raw = self.Timeline:GetState()
	local before, after = {}, {}
	for motor in motors do
		if typeof(motor) == "table" and (motor.IsTranslationOnly or motor.IsEclipseProperty) then
			continue
		end

		local bucket = raw.Keyframes[motor] or {}
		local current = Curves.rotationOrder(bucket)
		local compiled = Curves.compile(bucket)
		local legacyEuler = compiled.channels.rot_x
			or compiled.channels.rot_y
			or compiled.channels.rot_z
		if current == mode or mode == "Quaternion" and not current and not legacyEuler then
			continue
		end

		before[motor] = copyBucket(bucket)
		local copy = copyBucket(bucket)
		local frames = {}
		for frame in copy do
			table.insert(frames, frame)
		end

		if #frames == 0 then
			local cf = raw.DefaultPose[motor] or motor.C0
			copy[0] = {
				Frame = 0,
				Time = 0,
				Motor = motor,
				Part = motor.Part1,
				C0 = cf,
				Position = cf.Position,
				Rotation = cf.Rotation,
				Channels = {},
				GraphOnly = true,
			}
			frames = { 0 }
		end

		table.sort(frames)
		local reference
		local previousQ
		for _, frame in frames do
			local key = copy[frame]
			local cf = self.Timeline:EvaluateMotorJointC0(motor, frame / raw.FPS, bucket)
			local x, y, z
			if mode ~= "Quaternion" then
				x, y, z = Curves.euler(cf, mode, reference)
				reference = { x, y, z }
			end

			local q = Quaternion.fromCFrame(cf)
			if previousQ then
				q = Quaternion.alignSign(previousQ, q)
			end

			previousQ = q
			key.GraphCurves = key.GraphCurves or {}
			key.EulerRotationOrder = mode ~= "Quaternion" and mode or nil
			if not key.GraphOnly then
				for id, value in { loc_x = cf.X, loc_y = cf.Y, loc_z = cf.Z } do
					if not key.GraphCurves[id] and (not KeyframePolicy.channelsEnabled() or not (key.Channels and key.Channels[id])) then
						local point = Curves.newPoint(key, id)
						point.Id, point.Value = nextId(), value
						key.GraphCurves[id] = point
					end
				end
			end
			for id in key.GraphCurves do
				if id:sub(1, 4) == "rot_" or id:sub(1, 5) == "qrot_" then
					key.GraphCurves[id] = nil
				end
			end

			local values = mode == "Quaternion"
					and { qrot_w = q.w, qrot_x = q.x, qrot_y = q.y, qrot_z = q.z }
				or { rot_x = x, rot_y = y, rot_z = z }
			for id, value in values do
				local point = Curves.newPoint(key, id)
				point.Id = nextId()
				point.Value = value
				if mode ~= "Quaternion" then
					point.RotationOrder = mode
				end

				key.GraphCurves[id] = point
			end
		end

		after[motor] = copy
	end

	if not next(after) then
		return false
	end

	self:_restoreFinal(after, "commit")
	if self.onRotationChanged then
		self.onRotationChanged()
	end

	if self.History then
		self.History.record(function()
			self:_restoreFinal(before, "undo")
			if self.onRotationChanged then
				self.onRotationChanged()
			end
		end, function()
			self:_restoreFinal(after, "redo")
			if self.onRotationChanged then
				self.onRotationChanged()
			end
		end, "Convert rotation to " .. mode)
	end

	return true
end

return Model
