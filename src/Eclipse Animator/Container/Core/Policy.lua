--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local CameraRig = require("CameraRig")
local Quaternion = require("Quaternion")
local Preferences = require("Preferences")
local Physics = require("Cache")
local Policy = {}
local liveChannels
local cache = setmetatable({}, { __mode = "k" })
const POSE_IDS = { "loc_x", "loc_y", "loc_z", "qrot_w", "qrot_x", "qrot_y", "qrot_z" }

function Policy.channelsEnabled()
	if liveChannels ~= nil then
		return liveChannels
	end

	return Preferences.get("TransformChannels") ~= false
end

function Policy.setLiveChannels(value)
	liveChannels = value
	table.clear(cache)
end

function Policy.channelAvailable(motor, id)
	if id:sub(1, 6) ~= "scale_" then
		return true
	end

	if
		typeof(motor) == "table"
		and motor.IsEclipseBoneMotor
		and not motor.IsEclipseArmatureControl
	then
		return false
	end

	return true
end

function Policy.isDisabled(key, id)
	if not key then
		return false
	end

	if key.Disabled then
		return true
	end

	if id then
		local channel = key.Channels and key.Channels[id]
		local point = key.GraphCurves and key.GraphCurves[id]
		return channel and channel.Disabled == true or point and point.Disabled == true or false
	end

	for _, entries in { key.Channels or {}, key.GraphCurves or {} } do
		for _, entry in entries do
			if entry.Disabled then
				return true
			end
		end
	end

	return false
end

function Policy.poseChannels(key, pose)
	const channels = table.clone(key.Channels or {})
	const q = Quaternion.fromCFrame(pose)
	const values = { pose.X, pose.Y, pose.Z, q.w, q.x, q.y, q.z }
	for index, id in POSE_IDS do
		const channel = if channels[id] then table.clone(channels[id]) else {}
		channel.Value = values[index]
		channels[id] = channel
	end

	return channels
end

function Policy.invalidate(bucket)
	require("cache").invalidate()
	Physics.invalidate(bucket)
	if bucket then
		cache[bucket] = nil
	else
		table.clear(cache)
	end
end

function Policy.activeBucket(bucket)
	bucket = Physics.active(bucket)
	if not bucket then
		return nil
	end

	local saved = cache[bucket]
	if saved then
		return saved.bucket or bucket
	end

	local order = require("GraphCurves").rotationOrder(bucket)
	local result, changed = {}, false
	for frame, key in bucket do
		if key.Disabled then
			changed = true
			continue
		end

		local filtered = key
		if key.ChannelPoseC0 ~= nil and typeof(key.C0) == "CFrame" and key.ChannelPoseC0 ~= key.C0 then
			filtered = table.clone(key)
			filtered.ChannelPoseC0, filtered.GraphOnly = nil, nil
			filtered.Channels = Policy.poseChannels(key, key.C0)
		end

		if CameraRig.isTransform(key.Motor) and filtered.C0 and not key.GraphOnly then
			filtered = table.clone(filtered)
			filtered.Channels = table.clone(filtered.Channels or {})
			local pose = filtered.C0
			local q = Quaternion.fromCFrame(pose)
			for id, value in
				{
					loc_x = pose.X,
					loc_y = pose.Y,
					loc_z = pose.Z,
					qrot_w = q.w,
					qrot_x = q.x,
					qrot_y = q.y,
					qrot_z = q.z,
				}
			do
				if not filtered.Channels[id] then
					filtered.Channels[id] = { Value = value }
				end
			end
		end

		if Policy.isDisabled(key) then
			filtered = table.clone(filtered)
			filtered.EulerRotationOrder = order
			filtered.Channels = table.clone(filtered.Channels or {})
			filtered.GraphCurves = table.clone(key.GraphCurves or {})
			for id in filtered.Channels do
				if Policy.isDisabled(key, id) then
					filtered.Channels[id] = nil
				end
			end

			for id in filtered.GraphCurves do
				if Policy.isDisabled(key, id) then
					filtered.GraphCurves[id] = nil
				end
			end

			if not next(filtered.GraphCurves) then
				filtered.GraphCurves = nil
			end
		end

		changed = changed or filtered ~= key
		result[frame] = filtered
	end

	for frame, key in bucket do
		if key.Disabled then
			continue
		end

		local function boundary(at, source)
			if at < 0 or bucket[at] then
				return
			end

			local point = table.clone(source)
			point.Frame, point.Time = at, if frame > 0 then at * (key.Time / frame) else key.Time
			point.Motor, point.Part = key.Motor, key.Part
			point.Button, point.KeyGroups, point.PhysicsLead, point.PhysicsTail = nil, nil, nil, nil
			point.Channels = table.clone(point.Channels or {})
			for id in point.Channels do
				if Policy.isDisabled(key, id) then
					point.Channels[id] = nil
				end
			end

			result[at] = point
			changed = true
		end

		if key.PhysicsLead then
			boundary(frame - 1, key.PhysicsLead)
		end

		if key.PhysicsTail and key.PhysicsTail > 0 then
			local at = frame + key.PhysicsTail
			for other in bucket do
				if other > frame and other <= at then
					at = other - 1
				end
			end

			if at > frame then
				boundary(at, result[frame] or key)
			end
		end
	end

	result = changed and result or bucket
	cache[bucket] = { bucket = changed and result or nil }
	return result
end

function Policy.activeTracks(tracks)
	local out = {}
	for motor, bucket in tracks do
		out[motor] = Policy.activeBucket(bucket)
	end

	return out
end

return Policy
