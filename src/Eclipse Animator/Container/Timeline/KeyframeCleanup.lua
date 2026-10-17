--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Curves = require("GraphCurves")
local Quaternion = require("Quaternion")
local Policy = require("Policy")
local Camera = require("CameraRig")
local Cleanup = {}

local function copyValue(value)
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return value
	end

	local result = {}
	for key, item in value do
		result[key] = copyValue(item)
	end

	return result
end

function Cleanup.copy(bucket)
	local copy = {}
	for frame, key in bucket do
		local item = {}
		for name, value in key do
			if name ~= "Button" then
				item[name] = copyValue(value)
			end
		end

		copy[frame] = item
	end

	return copy
end

function Cleanup.clearTransforms(bucket, rest, world, values, currentFrame)
	local result = Cleanup.copy(bucket)
	for frame, key in result do
		if frame ~= currentFrame then
			continue
		end

		key.C0 = rest
		key.Position = rest.Position
		key.Rotation = rest.Rotation
		key.ChannelPoseC0 = rest
		if key.WorldCFrame or key.Parented == false then
			key.WorldCFrame = world
		end

		key.WholePoseScale = { scale_x = 1, scale_y = 1, scale_z = 1 }
		key.BlenderCurve = nil
		key.BlenderSource = nil
		key.PhysicsLead = nil
		key.PhysicsTail = nil
		key.PathTangentIn = nil
		key.PathTangentOut = nil
		for _, name in
			{
				"IKPoleFollowsTarget",
				"IKTarget",
				"IKPole",
				"IKRoot",
				"IKAnchor",
				"IKRigWorld",
				"IKBaseC0",
				"IKBaseWorld",
				"HSRotation",
				"HSLocalRotation",
			}
		do
			key[name] = nil
		end

		if key.IK then
			key.IK = false
		end

		if key.HS then
			key.HS = false
		end

		if key.HeadFollow then
			key.HeadFollow = false
		end

		for _, points in { key.Channels or {}, key.GraphCurves or {} } do
			for id, point in points do
				if values[id] ~= nil then
					point.Value = values[id]
					if point.In then
						point.In[2] = 0
					end

					if point.Out then
						point.Out[2] = 0
					end
				end
			end
		end
	end

	return result
end

function Cleanup.equal(a, b)
	if a == b then
		return true
	end

	if type(a) ~= type(b) then
		return false
	end

	if type(a) ~= "table" then
		return a == b
	end

	for k, v in a do
		if k ~= "Button" and not Cleanup.equal(v, b[k]) then
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

function Cleanup.frames(bucket)
	local out = {}
	for frame in bucket do
		table.insert(out, frame)
	end

	table.sort(out)
	return out
end

local function style(value)
	return typeof(value) == "EnumItem" and value.Name or value
end

local function movingChannels(bucket)
	local first, moving = {}, {}
	for _, key in bucket do
		for id, point in key.GraphCurves or {} do
			if type(point.Value) == "number" then
				if first[id] == nil then
					first[id] = point.Value
				elseif math.abs(point.Value - first[id]) > 1e-8 then
					moving[id] = true
				end
			end
		end
	end

	return moving
end

local function protected(bucket, smooth)
	local moving = movingChannels(bucket)
	for _, key in bucket do
		if not key.C0 then
			return "Non-transform track"
		end

		if Policy.isDisabled(key) then
			return "Contains disabled keys or channels"
		end

		if
			key.IK
			or key.IKTarget
			or key.IKRoot
			or key.HS
			or key.HeadFollow
			or key.Parented == false
			or key.WorldCFrame
		then
			return "IK, head stabilization or world parenting: bake to local poses first"
		end

		if key.PathTangentIn or key.PathTangentOut then
			return "Contains motion-path handles"
		end

		if smooth then
			if style(key.EasingStyle) == "Constant" then
				return "Stepped / held motion protected"
			end

			for id, point in key.GraphCurves or {} do
				if
					(point.Interpolation == "Constant" or point.Interpolation == "ConstantNext")
					and moving[id]
				then
					return "Stepped / held motion protected"
				end
			end

			for _, sample in key.BlenderCurve and key.BlenderCurve.samples or {} do
				if sample.boundary then
					return "Stepped / held motion protected"
				end
			end
		end
	end

	return nil
end

function Cleanup.gaussian(values, sigma, checkpoint)
	local radius = math.max(1, math.ceil(sigma * 3))
	local out, weights = {}, {}
	local total = 0
	for d = -radius, radius do
		local w = math.exp(-0.5 * (d / sigma) ^ 2)
		weights[d] = w
		total += w
	end

	for i = 1, #values do
		if checkpoint and i % 64 == 0 then
			checkpoint()
		end

		local value = 0
		for d = -radius, radius do
			value += values[math.clamp(i + d, 1, #values)] * weights[d]
		end

		out[i] = value / total
	end

	return out
end

function Cleanup.butterworth(values, cutoff, rate)
	local k = math.tan(math.pi * cutoff / rate)
	local norm = 1 / (1 + math.sqrt(2) * k + k * k)
	local b0, b1, b2 = k * k * norm, 2 * k * k * norm, k * k * norm
	local a1, a2 = 2 * (k * k - 1) * norm, (1 - math.sqrt(2) * k + k * k) * norm
	local pad = math.min(#values - 1, math.max(12, math.ceil(rate / cutoff * 3)))
	local padded = {}
	for i = pad, 1, -1 do
		table.insert(padded, 2 * values[1] - values[i + 1])
	end

	for _, value in values do
		table.insert(padded, value)
	end

	for i = 1, pad do
		table.insert(padded, 2 * values[#values] - values[#values - i])
	end

	local function pass(input)
		local x1, x2, y1, y2 = input[1], input[1], input[1], input[1]
		local out = {}
		for i, x in input do
			local y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
			out[i] = y
			x2, x1, y2, y1 = x1, x, y1, y
		end

		return out
	end

	local forward = pass(padded)
	padded = {}
	for i = #forward, 1, -1 do
		table.insert(padded, forward[i])
	end

	forward = pass(padded)
	local result = {}
	for i = 1, #values do
		result[i] = forward[#forward - pad - i + 1]
	end

	return result
end

local function sample(timeline, motor, bucket, frame, fps)
	local cf = timeline:EvaluateMotorC0(motor, frame / fps, bucket)
	local scale = timeline:EvaluateMotorScale(motor, frame / fps, bucket) or {}
	return {
		cf = cf,
		scale = Vector3.new(scale.scale_x or 1, scale.scale_y or 1, scale.scale_z or 1),
	}
end

local function errors(a, b)
	local _, angle = a.cf.Rotation:ToObjectSpace(b.cf.Rotation):ToAxisAngle()
	local ds = a.scale - b.scale
	return (a.cf.Position - b.cf.Position).Magnitude,
		math.deg(math.abs(angle)),
		math.max(math.abs(ds.X), math.abs(ds.Y), math.abs(ds.Z))
end

local function channels(pose, reference)
	local q = Quaternion.fromCFrame(pose.cf)
	if reference then
		q = Quaternion.alignSign(reference, q)
	end

	return {
		loc_x = pose.cf.X,
		loc_y = pose.cf.Y,
		loc_z = pose.cf.Z,
		qrot_w = q.w,
		qrot_x = q.x,
		qrot_y = q.y,
		qrot_z = q.z,
		scale_x = pose.scale.X,
		scale_y = pose.scale.Y,
		scale_z = pose.scale.Z,
	},
		q
end

local function smooth(timeline, motor, bucket, frames, settings, tick)
	local first, last, fps = frames[1], frames[#frames], settings.fps
	local values, original = {}, {}
	local reference
	for frame = first, last do
		tick()
		local pose = sample(timeline, motor, bucket, frame, fps)
		original[frame - first + 1] = pose
		local entries
		entries, reference = channels(pose, reference)
		for id, value in entries do
			values[id] = values[id] or {}
			table.insert(values[id], value)
		end
	end

	for id, entries in values do
		tick()
		values[id] = settings.method == "Gaussian"
				and Cleanup.gaussian(entries, settings.width, tick)
			or Cleanup.butterworth(entries, settings.cutoff, fps)
	end

	local result = Cleanup.copy(bucket)
	local previous
	for _, frame in frames do
		tick()
		local index = frame - first + 1
		local q = Quaternion.normalize({
			w = values.qrot_w[index],
			x = values.qrot_x[index],
			y = values.qrot_y[index],
			z = values.qrot_z[index],
		})
		local position = Vector3.new(values.loc_x[index], values.loc_y[index], values.loc_z[index])
		local filtered = CFrame.new(position.X, position.Y, position.Z, q.x, q.y, q.z, q.w)
		local edge = math.min(index - 1, #original - index)
		local fade = math.clamp(
			edge
				/ math.max(
					1,
					settings.method == "Gaussian" and settings.width or fps / settings.cutoff
				),
			0,
			1
		)
		local amount = settings.strength * fade
		local cf = original[index].cf:Lerp(filtered, amount)
		local scale = original[index].scale:Lerp(
			Vector3.new(values.scale_x[index], values.scale_y[index], values.scale_z[index]),
			amount
		)
		if amount > 0 then
			scale = Vector3.new(
				math.max(0.001, scale.X),
				math.max(0.001, scale.Y),
				math.max(0.001, scale.Z)
			)
		end

		if Camera.isFov(motor) then
			cf = Camera.encode(motor, Camera.decode(motor, cf))
		end

		local key = result[frame]
		key.C0, key.Position, key.Rotation = cf, cf.Position, cf.Rotation
		key.ChannelPoseC0, key.BlenderCurve, key.BlenderSource, key.GraphOnly = nil, nil, nil, nil
		key.HandleType, key.EasingStyle, key.EasingDirection = "AutoClamped", "Bezier", "InOut"
		key.BezierPoints, key.WholePoseScale =
			nil, { scale_x = scale.X, scale_y = scale.Y, scale_z = scale.Z }
		key.Channels, key.GraphCurves = {}, {}
		local entries
		entries, previous = channels({ cf = cf, scale = scale }, previous)
		for id, value in entries do
			key.Channels[id] = { Value = value }
			key.GraphCurves[id] =
				{ Value = value, HandleType = "AutoClamped", Interpolation = "Bezier" }
		end
	end

	Curves.invalidate(result)
	return result
end

function Cleanup.run(timeline, motors, settings, checkpoint)
	assert(settings.fps > 0, "Invalid project FPS")
	if settings.mode == "Smooth" then
		assert(type(settings.strength) == "number", "Enter a number for strength.")
		assert(
			settings.strength > 0 and settings.strength <= 1,
			"Strength must be greater than 0 and at most 100%."
		)
		if settings.method == "Gaussian" then
			assert(
				type(settings.width) == "number" and settings.width >= 0.5 and settings.width <= 30,
				"Gaussian width must be 0.5 to 30 frames."
			)
		else
			assert(
				type(settings.cutoff) == "number"
					and settings.cutoff > 0
					and settings.cutoff < settings.fps / 2,
				"Cutoff must be a positive number below half the project FPS."
			)
		end
	else
		for _, name in { "position", "rotation", "scale", "fov" } do
			local value = settings[name]
			assert(
				type(value) == "number" and value > 0 and value < 1e6,
				"Tolerances must be positive numbers."
			)
		end
	end

	local result = {
		before = {},
		after = {},
		rows = {},
		beforeCount = 0,
		afterCount = 0,
		changed = 0,
		skipped = 0,
		fps = settings.fps,
		mode = settings.mode,
	}
	local work = 0

	local function tick()
		work += 1
		assert(work <= 2000000, "This selection is too large. Process fewer tracks at a time.")
		if checkpoint and work % 64 == 0 then
			checkpoint()
		end
	end

	for _, motor in motors do
		if checkpoint then
			checkpoint(motor.Name)
		end

		local bucket = Cleanup.copy(timeline:GetState().Keyframes[motor] or {})
		local original = Cleanup.copy(bucket)
		local frames = Cleanup.frames(bucket)
		if typeof(motor) == "table" and motor.IsEclipseProperty then
			continue
		end

		local row = {
			motor = motor,
			name = motor.Part1 and motor.Part1.Name or motor.Name,
			before = #frames,
			after = #frames,
			position = 0,
			rotation = 0,
			scale = 0,
			fov = Camera.isFov(motor),
		}
		table.insert(result.rows, row)
		result.beforeCount += #frames
		local reason = protected(bucket, settings.mode == "Smooth")
		for _, id in Curves.ids do
			if motor:GetAttribute("EclipseChannelDisabled_" .. id) then
				reason = "Contains disabled channels"
			end
		end

		if #frames < 3 then
			reason = "Needs at least 3 keys"
		end

		if
			#frames >= 2
			and (
				frames[#frames] - frames[1] > 18000
				or frames[1] % 1 ~= 0
				or frames[#frames] % 1 ~= 0
			)
		then
			reason = "Track exceeds 18,000 frames or uses fractional key times"
		end

		for _, frame in frames do
			if frame % 1 ~= 0 then
				reason = "Fractional key times are protected"
			end
		end

		if reason then
			row.reason = reason
			result.skipped += 1
			result.afterCount += #frames
			continue
		end

		local after = Cleanup.copy(bucket)

		local function invalidate()
			Curves.invalidate(after)
			local state = timeline:GetState()
			state._motorUniform[motor], state._motorHasScale[motor] = nil, nil
		end

		if settings.mode == "Smooth" then
			after = smooth(timeline, motor, bucket, frames, settings, tick)
		else
			local moving = movingChannels(bucket)
			local probes = {}
			for frame = frames[1], frames[#frames], 0.25 do
				tick()
				table.insert(
					probes,
					{ frame = frame, pose = sample(timeline, motor, bucket, frame, settings.fps) }
				)
			end

			for i = 2, #frames - 1 do
				local key = after[frames[i]]
				if
					style(key.EasingStyle) == "Constant"
					or style(bucket[frames[i - 1]].EasingStyle) == "Constant"
				then
					continue
				end

				local hold = false
				for _, owner in { key, bucket[frames[i - 1]] } do
					for id, point in owner.GraphCurves or {} do
						if
							(
								point.Interpolation == "Constant"
								or point.Interpolation == "ConstantNext"
							) and moving[id]
						then
							hold = true
						end
					end
				end

				if hold then
					continue
				end

				after[frames[i]] = nil
				invalidate()
				local accepted = true
				for _, probe in probes do
					tick()
					local p, r, s = errors(
						probe.pose,
						sample(timeline, motor, after, probe.frame, settings.fps)
					)
					if
						p > (row.fov and settings.fov or settings.position)
						or r > settings.rotation
						or s > settings.scale
					then
						accepted = false
						break
					end
				end

				if not accepted then
					after[frames[i]] = key
					invalidate()
				end
			end
		end

		row.after = #Cleanup.frames(after)
		row.plot = {}
		for frame = frames[1], frames[#frames], 0.25 do
			tick()
			local a, b =
				sample(timeline, motor, bucket, frame, settings.fps),
				sample(timeline, motor, after, frame, settings.fps)
			local p, r, s = errors(a, b)
			row.position, row.rotation, row.scale =
				math.max(row.position, p), math.max(row.rotation, r), math.max(row.scale, s)
			if
				#row.plot < 201
				and (frame - frames[1])
						% math.max(0.25, math.ceil((frames[#frames] - frames[1]) / 50) * 0.25)
					== 0
			then
				table.insert(row.plot, {
					frame = frame,
					before = a.cf.Position.Magnitude,
					after = b.cf.Position.Magnitude,
				})
			end
		end

		if settings.mode ~= "Smooth" then
			local retained = Cleanup.copy(original)
			for frame in retained do
				if not after[frame] then
					retained[frame] = nil
				end
			end

			after = retained
		end

		if not Cleanup.equal(original, after) then
			result.before[motor], result.after[motor] = original, after
			result.changed += 1
		end

		result.afterCount += row.after
	end

	return result
end

return Cleanup
