--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Curves = require("GraphCurves")
local Groups = require("KeyGroups")
local Scale = {}

function Scale.begin(mouse, pivotX, pivotFrame)
	return {
		start = mouse,
		mouse = mouse,
		virtual = mouse,
		center = Vector2.new(pivotX, mouse.Y),
		distance = math.abs(mouse.X - pivotX),
		pivot = pivotFrame,
		factor = 1,
		text = "",
		negative = false,
		inverse = false,
		snap = true,
	}
end

function Scale.mouse(session, mouse, precision)
	session.virtual += (mouse - session.mouse) * (precision and 0.1 or 1)
	session.mouse = mouse
	local offset = session.virtual - session.center
	local initial = session.start - session.center
	local factor = offset.Magnitude / (session.distance == 0 and 1 or session.distance)
	if offset:Dot(initial) < 0 then
		factor = -factor
	end

	return factor
end

local digits = {
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}
for i = 0, 9 do
	digits["Keypad" .. i] = tostring(i)
end

function Scale.input(session, name)
	if digits[name] then
		session.text ..= digits[name]
	elseif name == "Period" or name == "KeypadPeriod" then
		if not session.text:find(".", 1, true) then
			session.text ..= "."
		end
	elseif name == "Minus" or name == "KeypadMinus" then
		session.negative = not session.negative
	elseif name == "Slash" or name == "KeypadDivide" then
		session.inverse = not session.inverse
	elseif name == "Backspace" then
		if #session.text > 0 then
			session.text = session.text:sub(1, -2)
		else
			session.negative = false
			session.inverse = false
		end
	elseif name == "Delete" then
		session.text = ""
		session.negative = false
		session.inverse = false
	else
		return false
	end

	return true
end

function Scale.value(session, mouseFactor)
	local typed = session.text ~= "" or session.negative or session.inverse
	local value = typed and (tonumber(session.text) or 1) or mouseFactor
	if session.inverse then
		if value == 0 then
			return nil
		end

		value = 1 / value
	end

	if session.negative then
		value = -value
	end

	if value ~= value or math.abs(value) == math.huge then
		return nil
	end

	return value
end

function Scale.frame(original, pivot, factor, step, absolute)
	if factor == 1 then
		return original
	end
	local target = pivot + (original - pivot) * factor
	if step then
		if absolute then
			target = math.floor(target / step + 0.5) * step
		else
			target = original + math.floor((target - original) / step + 0.5) * step
		end
	end

	return math.floor(target + 0.5)
end

function Scale.copyKey(key)
	local out = table.clone(key)
	out.Button = nil
	for _, field in
		{
			"PhysicsLead",
			"Channels",
			"GraphCurves",
			"KeyGroups",
			"BezierPoints",
			"WholePoseScale",
			"BlenderCurve",
		}
	do
		out[field] = Curves.clone(key[field])
	end

	return out
end

function Scale.copyBucket(bucket)
	local out = {}
	for frame, key in bucket do
		out[frame] = Scale.copyKey(key)
	end

	return out
end

local function averageMaps(keys, field)
	local result, counts = {}, {}
	for _, key in keys do
		for id, value in key[field] or {} do
			local scalar = type(value) == "table" and value.Value or value
			if type(scalar) == "number" then
				local count = (counts[id] or 0) + 1
				counts[id] = count
				if count == 1 then
					result[id] = Curves.clone(value)
				elseif type(value) == "table" then
					result[id].Value += (scalar - result[id].Value) / count
				else
					result[id] += (scalar - result[id]) / count
				end
			elseif result[id] == nil then
				result[id] = Curves.clone(value)
			end
		end
	end

	return next(result) and result or nil
end

local function averagePose(keys, field)
	local position, rotation, n = Vector3.zero, Vector3.zero, 0
	for _, key in keys do
		local value = key[field]
		if typeof(value) == "CFrame" then
			n += 1
			position += value.Position
			local x, y, z = value:ToEulerAnglesXYZ()
			rotation += Vector3.new(x, y, z)
		end
	end

	if n == 0 then
		return nil
	end

	position /= n
	rotation /= n
	return CFrame.new(position) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
end

local function merge(keys, frame, fps)
	local out = Scale.copyKey(keys[1])
	out.Frame, out.Time = frame, frame / fps
	if #keys > 1 then
		out.Channels = averageMaps(keys, "Channels")
		out.GraphCurves = averageMaps(keys, "GraphCurves")
		out.WholePoseScale = averageMaps(keys, "WholePoseScale")
		for _, field in { "C0", "WorldCFrame", "IKTarget", "IKPole", "IKRoot" } do
			out[field] = averagePose(keys, field)
		end

		local sum, n = 0, 0
		for _, key in keys do
			if type(key.PropertyValue) == "number" then
				sum += key.PropertyValue
				n += 1
			end
		end

		if n > 0 then
			out.PropertyValue = sum / n
		end

		out.BlenderCurve, out.BlenderSource = nil, nil
	end

	if out.C0 then
		out.Position, out.Rotation = out.C0.Position, out.C0.Rotation
	end

	return out
end

function Scale.build(before, originals, targets, fps, reconstruct)
	local after, whole, channels, fullGroups, channelGroups = {}, {}, {}, {}, {}
	for motor, bucket in before do
		after[motor] = Scale.copyBucket(bucket)
	end

	for _, snap in originals do
		if snap.kind == "bone" then
			whole[snap.motor] = whole[snap.motor] or {}
			whole[snap.motor][snap.originalFrame] = true
		end
	end

	local ordered = table.clone(originals)
	table.sort(ordered, function(a, b)
		return a.originalFrame < b.originalFrame
	end)
	for _, snap in ordered do
		local motor, sourceFrame = snap.motor, snap.originalFrame
		local source = before[motor][sourceFrame]
		local target = targets[snap.keyData] or sourceFrame
		if snap.kind == "bone" then
			after[motor][sourceFrame] = nil
			fullGroups[motor] = fullGroups[motor] or {}
			fullGroups[motor][target] = fullGroups[motor][target] or {}
			table.insert(fullGroups[motor][target], source)
		elseif not (whole[motor] and whole[motor][sourceFrame]) then
			local id = snap.channelId
			channels[motor] = channels[motor] or {}
			channels[motor][sourceFrame] = channels[motor][sourceFrame] or {}
			if channels[motor][sourceFrame][id] then
				continue
			end

			channels[motor][sourceFrame][id] = true
			local key = after[motor][sourceFrame]
			if key.GraphCurves then
				key.GraphCurves[id] = nil
				if not next(key.GraphCurves) then
					key.GraphCurves = nil
				end
			end

			if key.Channels then
				key.Channels[id] = nil
			end

			Groups.set(key, id, nil)
			if
				not key.GraphCurves
				and not next(key.Channels or {})
				and (key.GraphOnly or key.Channels)
			then
				after[motor][sourceFrame] = nil
			end

			channelGroups[motor] = channelGroups[motor] or {}
			channelGroups[motor][target] = channelGroups[motor][target] or {}
			local group = channelGroups[motor][target]
			group[id] = group[id] or {}
			table.insert(group[id], source)
		end
	end

	for motor, frames in fullGroups do
		for frame, keys in frames do
			local key = merge(keys, frame, fps)
			after[motor][frame] = key
			if #keys > 1 and reconstruct then
				local c0 = reconstruct(key)
				if c0 then
					key.C0 = c0
					key.Position, key.Rotation = c0.Position, c0.Rotation
				end
			end
		end
	end

	for motor, frames in channelGroups do
		for frame, ids in frames do
			for id, keys in ids do
				local source = keys[1]
				local key = after[motor][frame]
				if not key then
					key = Scale.copyKey(source)
					key.Frame, key.Time = frame, frame / fps
					key.Channels, key.GraphCurves, key.KeyGroups = {}, nil, nil
					key.GraphOnly = true
					after[motor][frame] = key
				end

				local full = fullGroups[motor] and fullGroups[motor][frame]
				if full then
					local combined = table.clone(keys)
					for _, wholeKey in full do
						table.insert(combined, wholeKey)
					end

					keys = combined
				end

				local points = averageMaps(keys, "GraphCurves")
				local values = averageMaps(keys, "Channels")
				if points and points[id] then
					key.GraphCurves = key.GraphCurves or {}
					key.GraphCurves[id] = points[id]
				end

				if values and values[id] then
					key.Channels = key.Channels or {}
					key.Channels[id] = values[id]
				end

				Groups.set(key, id, Groups.get(source, id))
				local c0 = reconstruct and reconstruct(key)
				if c0 then
					key.C0 = c0
					key.Position, key.Rotation = c0.Position, c0.Rotation
				end
			end
		end
	end

	return after
end

return Scale
