--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Notification = require("Notification")
local Session = game:GetService("StudioService")
local Scale = {}
local SESSION_KEY = "EclipseHumanoidScaleWarned"
local MESSAGE = "Humanoid bone scaling WILL NOT export properly."
local CHANNELS = { "scale_x", "scale_y", "scale_z" }

function Scale.owner(subject)
	if typeof(subject) == "table" then
		if subject.IsEclipseArmatureControl then
			return nil
		end

		subject = subject.Rig or subject.Part1
	elseif typeof(subject) == "Instance" and subject:IsA("JointInstance") then
		subject = subject.Part1
	end

	while typeof(subject) == "Instance" and subject ~= game do
		if subject:IsA("Model") and subject:FindFirstChildOfClass("Humanoid") then
			return subject
		end

		subject = subject.Parent
	end

	return nil
end

function Scale.changed(subject)
	if not Scale.owner(subject) or Session:GetAttribute(SESSION_KEY) then
		return false
	end

	Session:SetAttribute(SESSION_KEY, true)
	Notification.show("HUMANOID SCALING", MESSAGE, 4)
	return true
end

local function sizeProperty(motor)
	return typeof(motor) == "table" and (motor.PropertyId == "Size" or motor.PropertyId == "Scale")
end

function Scale.propertyChanged(motor, before, after)
	if sizeProperty(motor) and before ~= after then
		Scale.changed(motor)
	end
end

local function channelValue(key, id)
	if not key then
		return 1
	end

	local point = key.GraphCurves and key.GraphCurves[id] or key.Channels and key.Channels[id]
	return point and point.Value or key.WholePoseScale and key.WholePoseScale[id] or 1
end

local function offsetHandles(point)
	if not point then
		return false
	end

	for _, side in { "In", "Out" } do
		local handle = point[side]
		if handle and math.abs(handle[2] or 0) > 1e-6 then
			return true
		end
	end

	return false
end

function Scale.bucketsChanged(motor, before, after)
	if not Scale.owner(motor) then
		return
	end

	if sizeProperty(motor) then
		for frame, key in after or {} do
			local old = before and before[frame]
			Scale.propertyChanged(
				motor,
				old and old.PropertyValue or motor.DefaultValue,
				key.PropertyValue
			)
		end

		return
	end

	for frame, key in after or {} do
		for _, id in CHANNELS do
			local old = before and before[frame]
			local point = key.GraphCurves and key.GraphCurves[id]
			local previous = old and old.GraphCurves and old.GraphCurves[id]
			if
				math.abs(channelValue(key, id) - channelValue(old, id)) > 1e-6
				or offsetHandles(point) and not offsetHandles(previous)
			then
				Scale.changed(motor)
				return
			end
		end
	end
end

local function scaledTrack(motor, bucket)
	if not Scale.owner(motor) then
		return false
	end

	for _, key in bucket do
		if key.Disabled then
			continue
		end

		if sizeProperty(motor) then
			if key.PropertyValue ~= nil and key.PropertyValue ~= motor.DefaultValue then
				return true
			end
		else
			for _, id in CHANNELS do
				local channel = key.Channels and key.Channels[id]
				local point = key.GraphCurves and key.GraphCurves[id]
				if
					not (channel and channel.Disabled or point and point.Disabled)
					and (math.abs(channelValue(key, id) - 1) > 1e-6 or offsetHandles(point))
				then
					return true
				end
			end
		end
	end

	return false
end

function Scale.hasChanges(raw)
	for motor, bucket in raw.Keyframes or {} do
		if scaledTrack(motor, bucket) then
			return true
		end
	end

	for _, layer in raw.AnimationLayers and raw.AnimationLayers.layers or {} do
		for motor, bucket in layer.keys do
			if scaledTrack(motor, bucket) then
				return true
			end
		end

		for rig, properties in layer.properties or {} do
			if not Scale.owner(rig) then
				continue
			end

			for _, track in properties.tracks or {} do
				if track.id ~= "Size" and track.id ~= "Scale" then
					continue
				end

				if track.enabled == false or track.disabled then
					continue
				end

				for _, key in track.keys or {} do
					if
						not key.Disabled
						and key.PropertyValue ~= nil
						and key.PropertyValue ~= track.default
					then
						return true
					end
				end
			end
		end
	end

	for part, size in raw.DefaultSize or {} do
		if part.Parent and Scale.owner(part) and (part.Size - size).Magnitude > 1e-5 then
			return true
		end
	end

	return false
end

function Scale.warnExport(raw)
	if not Scale.hasChanges(raw) then
		return false
	end

	Notification.show("EXPORT WARNING", MESSAGE, 4)
	return true
end

return Scale
