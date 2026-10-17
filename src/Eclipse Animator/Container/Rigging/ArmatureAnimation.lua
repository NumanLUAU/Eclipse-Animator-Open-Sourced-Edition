--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Runtime = require("ArmatureRuntime")
local Storage = require("ChunkStore")
local Http = game:GetService("HttpService")
local Animation = {}
local MainState = require("State")

local function checkpoint()
	if MainState.ProjectWorkStep then
		MainState.ProjectWorkStep()
	end
end

local cache = setmetatable({}, { __mode = "k" })
local arms = setmetatable({}, { __mode = "k" })
local revisions = setmetatable({}, { __mode = "k" })
local nextRevision = 0

local function changed(arm)
	nextRevision += 1
	revisions[arm] = nextRevision
end

local NAME = "EclipseArmatureAnimation"
local PROPERTIES = "EclipseArmaturePropertyKeys"
local omitted = { Motor = true, Part = true, Button = true, SanitizeName = true }

local function encode(value, seen)
	local kind = typeof(value)
	if kind == "CFrame" then
		return { type = "CFrame", value = { value:GetComponents() } }
	elseif kind == "Vector3" then
		return { type = "Vector3", value = { value.X, value.Y, value.Z } }
	elseif kind == "EnumItem" then
		return {
			type = "Enum",
			enum = tostring(value.EnumType):gsub("Enum%.", ""),
			value = value.Name,
		}
	elseif kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "Non-finite armature key")
		return value
	elseif kind == "string" or kind == "boolean" then
		return value
	elseif kind == "table" then
		seen = seen or {}
		if seen[value] then
			return nil
		end

		seen[value] = true
		local entries = {}
		for key, item in value do
			if not omitted[key] and (typeof(key) == "string" or typeof(key) == "number") then
				local encoded = encode(item, seen)
				if encoded ~= nil then
					table.insert(entries, { key = key, value = encoded })
				end
			end
		end

		seen[value] = nil
		return { type = "Table", entries = entries }
	end

	return nil
end

local function decode(value)
	if typeof(value) ~= "table" then
		return value
	end

	if value.type == "CFrame" then
		return CFrame.new(table.unpack(value.value))
	elseif value.type == "Vector3" then
		return Vector3.new(table.unpack(value.value))
	elseif value.type == "Enum" then
		return Enum[value.enum][value.value]
	elseif value.type == "Table" then
		local out = {}
		for _, entry in value.entries do
			out[entry.key] = decode(entry.value)
		end

		return out
	end

	error("Invalid armature key encoding")
end

local armMisses = setmetatable({}, { __mode = "k" })

local function armature(rig)
	local cached = arms[rig]
	if cached and cached:IsDescendantOf(rig) then
		return cached
	end

	local miss = armMisses[rig]
	if miss and miss.valid and os.clock() - miss.at < 1 then
		return nil
	end

	for _, item in require("RigTraversal").descendants(rig) do
		if item:GetAttribute("EclipseArmatureVersion") == 4 then
			arms[rig] = item
			armMisses[rig] = nil
			return item
		end
	end

	arms[rig] = nil
	if miss then
		miss.valid, miss.at = true, os.clock()
	else
		local entry = { valid = true, at = os.clock() }
		entry.connection = rig.DescendantAdded:Connect(function()
			entry.valid = false
		end)
		armMisses[rig] = entry
	end
end

local function replace(parent, name, value)
	local text = Http:JSONEncode(value)
	local old = parent:FindFirstChild(name)
	Storage.write(parent, name, text)
	if old then
		old:Destroy()
	end
end

local function properties(rig)
	local arm = armature(rig)
	if not arm then
		return nil
	end

	local entry = cache[arm]
	if not entry then
		local source = arm:FindFirstChild(PROPERTIES)
		entry = source and Http:JSONDecode(Storage.read(source)) or { version = 1, tracks = {} }
		cache[arm] = entry
	end

	return entry, arm
end

local function identity(property)
	return Http:JSONEncode({ property.object, property.bone or "", property.key })
end

local function findTrack(entry, property)
	local id = identity(property)
	for _, track in entry.tracks do
		if track.id == id then
			return track
		end
	end
end

function Animation.propertyView(rig)
	return properties(rig) or { version = 1, tracks = {} }
end

local orderedProperties = setmetatable({}, { __mode = "k" })

function Animation.propertyBounds(track, frame)
	local keys = track.keys
	local ordered = orderedProperties[keys]
	if ordered == nil then
		ordered = true
		local last = -math.huge
		for _, key in keys do
			if type(key.frame) ~= "number" or key.frame ~= key.frame or key.frame < last then
				ordered = false
				break
			end

			last = key.frame
		end

		orderedProperties[keys] = ordered
	end

	if ordered then
		local low, high = 1, #keys
		while low <= high do
			local mid = (low + high) // 2
			if keys[mid].frame <= frame then
				low = mid + 1
			else
				high = mid - 1
			end
		end

		return keys[high], keys[low]
	end

	local previous, following
	for _, key in keys do
		if key.frame <= frame then
			previous = key
		else
			following = key
			break
		end
	end

	return previous, following
end

function Animation.propertySnapshot(rig)
	local entry = properties(rig)
	return entry and Http:JSONDecode(Http:JSONEncode(entry)) or { version = 1, tracks = {} }
end

function Animation.restoreProperties(rig, snapshot)
	local arm = armature(rig)
	if not arm then
		return
	end

	local value = Http:JSONDecode(Http:JSONEncode(snapshot))
	cache[arm] = value
	replace(arm, PROPERTIES, value)
	changed(arm)
end

function Animation.propertyRevision(rig)
	local arm = armature(rig)
	return arm and revisions[arm] or 0, arm
end

function Animation.keyedProperties(rig, frame)
	local entry = properties(rig)
	local result = {}
	if entry then
		for _, track in entry.tracks do
			for _, key in track.keys do
				if key.frame == frame then
					result[track.id] = true
					break
				end

				if key.frame > frame then
					break
				end
			end
		end
	end

	return result
end

function Animation.propertyFrames(rig, property)
	local entry = properties(rig)
	local track = entry and findTrack(entry, property)
	local frames = {}
	if track then
		for _, key in track.keys do
			table.insert(frames, key.frame)
		end
	end

	return frames
end

function Animation.keyProperty(rig, property, frame, value, remove)
	local entry, arm = properties(rig)
	if not entry then
		return
	end

	local Layers = require("Layers")
	local raw = require("RawState").Timeline
	if Layers.has(raw) and not raw._LayerLoading and not remove then
		value = Layers.propertyValue(rig, identity(property), frame, value)
		if value == nil then
			return
		end
	end

	local track = findTrack(entry, property)
	if not track then
		if remove then
			return
		end

		track = {
			id = identity(property),
			object = property.object,
			bone = property.bone,
			key = property.key,
			default = property.default,
			keys = {},
		}
		table.insert(entry.tracks, track)
	end

	for i = #track.keys, 1, -1 do
		if track.keys[i].frame == frame then
			table.remove(track.keys, i)
		end
	end

	if not remove then
		table.insert(track.keys, { frame = frame, value = value })
	end

	table.sort(track.keys, function(a, b)
		return a.frame < b.frame
	end)
	replace(arm, PROPERTIES, entry)
	changed(arm)
end

function Animation.applyProperties(rig, frame)
	local Layers = require("Layers")
	local raw = require("RawState").Timeline
	if Layers.has(raw) then
		return Layers.applyProperties(rig, frame)
	end

	local entry = properties(rig)
	if not entry then
		return
	end

	for _, track in entry.tracks do
		local previous, following = Animation.propertyBounds(track, frame)
		local value = track.default
		if previous then
			value = previous.value
		end

		if
			previous
			and following
			and typeof(previous.value) == "number"
			and typeof(following.value) == "number"
		then
			value = previous.value
				+ (following.value - previous.value)
					* math.clamp(
						(frame - previous.frame) / (following.frame - previous.frame),
						0,
						1
					)
		end

		if value ~= nil then
			Runtime.setProperty(rig, track.object, track.key, value, track.bone, true)
		end
	end
end

function Animation.maxFrame(rig, state)
	local last = 0
	for _, motor in Runtime.collectMotors(rig) do
		for frame in state.Keyframes[motor] or {} do
			last = math.max(last, frame)
		end
	end

	local entry = properties(rig)
	if entry then
		for _, track in entry.tracks do
			for _, key in track.keys do
				last = math.max(last, key.frame)
			end
		end
	end

	return last
end

function Animation.hasKeys(rig, state)
	for _, motor in Runtime.collectMotors(rig) do
		if next(state.Keyframes[motor] or {}) then
			return true
		end
	end

	local entry = properties(rig)
	if entry then
		for _, track in entry.tracks do
			if #track.keys > 0 then
				return true
			end
		end
	end

	return false
end

const retainedControls = setmetatable({}, { __mode = "k" })

function Animation.write(sequence, rig, state)
	local arm = armature(rig)
	if not arm then
		return
	end

	local controls = {}
	const written = {}
	for _, motor in Runtime.collectMotors(rig) do
		checkpoint()
		written[motor.Part1:GetAttribute("EclipseArmatureBoneId")] = true
		local keys = {}
		for frame, key in state.Keyframes[motor] or {} do
			table.insert(keys, { frame = frame, data = encode(key) })
			checkpoint()
		end

		table.sort(keys, function(a, b)
			return a.frame < b.frame
		end)
		table.insert(controls, {
			id = motor.Part1:GetAttribute("EclipseArmatureBoneId"),
			default = encode(state.DefaultPose[motor] or motor.C0),
			defaultWorld = encode(state.DefaultWorldPose[motor]),
			parented = state.ParentingDefaults[motor],
			keys = keys,
		})
	end

	for _, control in retainedControls[rig] or {} do
		if not written[control.id] then
			table.insert(controls, control)
		end
	end

	replace(sequence, NAME, {
		version = 1,
		scale = arm:GetAttribute("EclipseArmatureScale"),
		fit = encode(arm:GetAttribute("EclipseArmatureFit") or CFrame.identity),
		controls = controls,
		properties = Animation.propertySnapshot(rig),
	})
end

function Animation.hasSaved(sequence)
	return sequence:FindFirstChild(NAME) ~= nil
end

function Animation.read(sequence, rig, timeline, sanitizeName, budget)
	local source = sequence:FindFirstChild(NAME)
	if not source or not Runtime.isRig(rig) then
		return false
	end

	local data = Http:JSONDecode(Storage.read(source))
	assert(data.version == 1, "Unsupported armature animation version")
	local arm = armature(rig)
	local ratio = (arm:GetAttribute("EclipseArmatureScale") or 1) / (data.scale or 1)

	local function scaleFrame(value)
		return CFrame.new(value.Position * ratio) * value.Rotation
	end

	local oldFit = data.fit and decode(data.fit)
	local newFit = arm:GetAttribute("EclipseArmatureFit") or CFrame.identity

	local function worldFrame(value)
		if not oldFit then
			return value
		end

		return CFrame.new(
			newFit:PointToWorldSpace(oldFit:PointToObjectSpace(value.Position) * ratio)
		) * newFit.Rotation * oldFit.Rotation:Inverse() * value.Rotation
	end

	local function worldVector(value)
		if not oldFit then
			return value * ratio
		end

		return newFit:VectorToWorldSpace(oldFit:VectorToObjectSpace(value) * ratio)
	end

	local state = timeline:GetState()
	local motors = {}
	for _, motor in Runtime.collectMotors(rig) do
		motors[motor.Part1:GetAttribute("EclipseArmatureBoneId")] = motor
	end

	const retained = {}
	retainedControls[rig] = retained

	local previous = state.CurrentTime
	for _, control in data.controls do
		if budget then
			budget()
		end

		local motor = motors[control.id]
		if not motor then
			warn("[Eclipse] Saved armature control " .. tostring(control.id) .. " couldn't be matched on " .. rig.Name .. "; it is kept unchanged in the save.")
			table.insert(retained, control)
			continue
		end

		state.DefaultPose[motor] = scaleFrame(decode(control.default))
		if control.defaultWorld then
			state.DefaultWorldPose[motor] = worldFrame(decode(control.defaultWorld))
		end

		if typeof(control.parented) == "boolean" then
			state.ParentingDefaults[motor] = control.parented
			motor:SetAttribute("EclipseParentingDefault", control.parented)
		end

		for _, record in control.keys do
			if budget then
				budget()
			end

			local saved = decode(record.data)
			saved.C0 = scaleFrame(saved.C0)
			saved.Position = saved.C0.Position
			if saved.WorldCFrame then
				saved.WorldCFrame = worldFrame(saved.WorldCFrame)
			end

			local world = saved.Parented == false
				or (saved.Parented == nil and control.parented == false)
			for _, field in { "PathTangentIn", "PathTangentOut" } do
				if saved[field] then
					saved[field] = world and worldVector(saved[field]) or saved[field] * ratio
				end
			end

			for _, id in { "loc_x", "loc_y", "loc_z" } do
				local channel = saved.Channels and saved.Channels[id]
				if channel and channel.Value then
					channel.Value *= ratio
				end

				local graph = saved.GraphCurves and saved.GraphCurves[id]
				if graph then
					graph.Value *= ratio
					if graph.In then
						graph.In[2] *= ratio
					end

					if graph.Out then
						graph.Out[2] *= ratio
					end
				end
			end

			state.CurrentTime = timeline:FrameToTime(record.frame)
			timeline:RecordKeyframeForMotorAtCurrentTime(
				motor.Part1,
				motor,
				saved.C0,
				{ InheritEasing = false, PreserveGraph = true, Frame = record.frame },
				sanitizeName
			)
			local key = state.Keyframes[motor][record.frame]
			for field, value in saved do
				key[field] = value
			end

			key.Motor, key.Part, key.Frame, key.Time =
				motor, motor.Part1, record.frame, state.CurrentTime
			state._motorUniform[motor], state._motorHasScale[motor] = nil, nil
			timeline:EnsureTimelineEnd(record.frame)
		end
	end

	Animation.restoreProperties(rig, data.properties or { version = 1, tracks = {} })
	for _, track in data.properties and data.properties.tracks or {} do
		for _, key in track.keys do
			timeline:EnsureTimelineEnd(key.frame)
		end
	end

	state.CurrentTime = previous
	return true
end

Animation.encode, Animation.decode = encode, decode
return Animation
