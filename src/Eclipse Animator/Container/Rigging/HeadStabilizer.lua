--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local TimelineState = require("RawState").Timeline
local Parenting = require("Parenting")
local Mode = require("cache")
local MotorMath = require("MotorMath")
local Interp = require("Interp")

local HeadStabilizer = {}
local live = setmetatable({}, { __mode = "k" })

HeadStabilizer.isEligible = Mode.isEligible

function HeadStabilizer.isEnabled(motor, time)
	return Mode.isEnabled(motor, TimelineState.Keyframes[motor], time)
end

function HeadStabilizer.restoreParented(motor, time)
	local bucket = TimelineState.Keyframes[motor] or {}
	local lastOff = -math.huge
	for _, key in bucket do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.HS == false and key.Time <= time then
			lastOff = math.max(lastOff, key.Time)
		end
	end

	local first, saved
	for _, key in bucket do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.Time > lastOff and key.Time <= time and key.HS == true then
			if not first or key.Time < first.Time then
				first = key
			end

			if
				typeof(key.HSRestoreParented) == "boolean"
				and (not saved or key.Time > saved.Time)
			then
				saved = key
			end
		end
	end

	if saved then
		return saved.HSRestoreParented
	end

	return Parenting.keyIsParented(motor, first, TimelineState.ParentingDefaults[motor])
end

function HeadStabilizer.rotationAt(motor, time, evaluatedC0, source)
	local bucket = source or TimelineState.Keyframes[motor]
	if not Mode.isEnabled(motor, bucket, time) then
		return nil
	end

	local left, right = -math.huge, math.huge
	for _, key in bucket do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.HS == false then
			if key.Time <= time then
				left = math.max(left, key.Time)
			else
				right = math.min(right, key.Time)
			end
		end
	end

	local start
	for _, key in bucket do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if
			key.HS == true
			and key.HSRotation
			and key.Time > left
			and key.Time <= time
			and (not start or key.Time < start.Time)
		then
			start = key
		end
	end

	if not start then
		return nil
	end

	local anchor = start.HSRotation * motor.C1.Rotation * start.C0.Rotation:Inverse()
	local converted, previous, following = {}, nil, nil
	for frame, key in bucket do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.Time < start.Time or key.Time > right then
			continue
		end

		local sample = table.clone(key)
		if key.HSRotation then
			local localRotation = key.HSLocalRotation or key.C0.Rotation
			sample.HSRotation = key.HSRotation
				* motor.C1.Rotation
				* localRotation:Inverse()
				* key.C0.Rotation
				* motor.C1.Rotation:Inverse()
		else
			sample.HSRotation = anchor * key.C0.Rotation * motor.C1.Rotation:Inverse()
		end

		sample.PathTangentIn, sample.PathTangentOut = nil, nil
		converted[frame] = sample
		if key.Time <= time and (not previous or key.Time > previous.Time) then
			previous = sample
		end

		if key.Time >= time and (not following or key.Time < following.Time) then
			following = sample
		end
	end

	if not previous then
		return following and following.HSRotation
	end

	local rotation = previous.HSRotation
	local complete = previous.C0
	if following and previous.Time ~= following.Time then
		local alpha = (time - previous.Time) / (following.Time - previous.Time)
		rotation = Interp.cframe(converted, previous, following, alpha, "HSRotation").Rotation
		if evaluatedC0 and motor:GetAttribute("EclipseChannelDisabledAny") then
			complete = Interp.cframe(converted, previous, following, alpha, "C0")
		end
	end

	if evaluatedC0 and motor:GetAttribute("EclipseChannelDisabledAny") then
		for _, channel in { "qrot_w", "qrot_x", "qrot_y", "qrot_z" } do
			if motor:GetAttribute("EclipseChannelDisabled_" .. channel) then
				return rotation
					* motor.C1.Rotation
					* complete.Rotation:Inverse()
					* evaluatedC0.Rotation
					* motor.C1.Rotation:Inverse()
			end
		end
	end

	return rotation
end

function HeadStabilizer.captureKey(motor, key, c0)
	if
		not HeadStabilizer.isEligible(motor)
		or typeof(motor) == "table" and motor.IsEclipseArmatureControl
	then
		return
	end

	if HeadStabilizer.isEnabled(motor, key.Time) then
		key.HSRestoreParented = HeadStabilizer.restoreParented(motor, key.Time)
		key.HS, key.Parented, key.WorldCFrame = true, true, nil
	end

	if typeof(key.HS) ~= "boolean" then
		return
	end

	local parent = TimelineState.MotorByPart[Parenting.realPart0(motor)]
	local world = parent and Parenting.worldOf(parent, TimelineState.MotorByPart)
		or motor.Part0.CFrame
	key.HSRotation = (world * c0 * motor.C1:Inverse()).Rotation
	key.HSLocalRotation = c0.Rotation
end

function HeadStabilizer.solve(motor, rotation, motors, map)
	if
		not rotation
		or motor:GetAttribute("EclipseDisabled")
		or motor:GetAttribute("TrackParent") == false
	then
		return
	end

	local locked = { MotorByPart = map }
	for _, other in motors do
		if other ~= motor and other:GetAttribute("TrackParent") == false then
			table.insert(locked, { Motor = other, WorldCF = Parenting.worldOf(other, map) })
		end
	end

	local parent = map[Parenting.realPart0(motor)]
	local world = parent and Parenting.worldOf(parent, map) or motor.Part0.CFrame
	motor.C0 = CFrame.new(motor.C0.Position)
		* world.Rotation:Inverse()
		* rotation
		* motor.C1.Rotation
	MotorMath.restoreTrackParentLockedDescendants(locked)
end

const orderCache = setmetatable({}, { __mode = "k" })

local function cachedOrder(motors, map)
	local cached = orderCache[motors]
	if not cached or cached.map ~= map then
		return nil
	end

	local count = 0
	for key, motor in motors do
		count += 1
		if cached.motors[key] ~= motor then
			return nil
		end
	end

	if count ~= cached.count then
		return nil
	end

	for index, motor in cached.ordered do
		if cached.parents[index] ~= (map[Parenting.realPart0(motor)] or false) then
			return nil
		end
	end

	return cached.ordered
end

function HeadStabilizer.ordered(motors, map)
	local reused = cachedOrder(motors, map)
	if reused then
		return reused
	end

	local ordered, visited = {}, {}

	local function visit(motor)
		if visited[motor] then
			return
		end

		visited[motor] = true
		local parent = map[Parenting.realPart0(motor)]
		if parent then
			visit(parent)
		end

		table.insert(ordered, motor)
	end

	for _, motor in motors do
		visit(motor)
	end

	local snapshot, parents, count = {}, {}, 0
	for key, motor in motors do
		count += 1
		snapshot[key] = motor
	end

	for index, motor in ordered do
		parents[index] = map[Parenting.realPart0(motor)] or false
	end

	orderCache[motors] = { map = map, motors = snapshot, parents = parents, count = count, ordered = ordered }
	return ordered
end

function HeadStabilizer.apply(rig, time, resample, motors, map)
	for _, motor in HeadStabilizer.ordered(motors, map) do
		if
			not HeadStabilizer.isEligible(motor)
			or typeof(motor) == "table" and motor.IsEclipseArmatureControl
		then
			continue
		end

		if
			not HeadStabilizer.isEnabled(motor, time)
			or require("LimbIK").isDriven(motor, time)
			or motor:GetAttribute("EclipseDisabled")
			or motor:GetAttribute("TrackParent") == false
		then
			live[motor] = nil
			continue
		end

		local state = live[motor]
		if resample or not state or state.time ~= time then
			state = { time = time, rotation = HeadStabilizer.rotationAt(motor, time, motor.C0) }
			live[motor] = state
		elseif state.lastC0 and state.lastC0 ~= motor.C0 then
			state.rotation = Parenting.worldOf(motor, map).Rotation
			state.dirty = true
		end

		HeadStabilizer.solve(motor, state.rotation, motors, map)
		state.lastC0 = motor.C0
	end
end

function HeadStabilizer.isDirty(motor)
	return live[motor] ~= nil and live[motor].dirty == true
end

function HeadStabilizer.isCompensated(motor, c0)
	local state = live[motor]
	return state ~= nil and state.lastC0 == c0 and not state.dirty
end

function HeadStabilizer.markRecorded(motor)
	if live[motor] then
		live[motor].dirty = false
	end
end

function HeadStabilizer.clearLive()
	table.clear(live)
end

return HeadStabilizer
