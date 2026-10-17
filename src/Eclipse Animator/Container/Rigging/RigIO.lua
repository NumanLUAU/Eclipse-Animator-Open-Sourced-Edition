--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Storage = {}
local Layers = require("Layers")
local Document = require("Document")
local Data = require("ChunkStore")
local Http = game:GetService("HttpService")
local NAME = "EclipseAnimationLayers"
const retained = setmetatable({}, { __mode = "k" })
const unreadable = setmetatable({}, { __mode = "k" })
const unreadableNodes = setmetatable({}, { __mode = "k" })
const UNREADABLE = NAME .. "Unreadable"

local function metadata(data, rows, owners)
	local out = { version = 2, active = data.active, layers = {} }
	for _, layer in rows or data.layers do
		table.insert(out.layers, {
			owner = owners and owners[layer.owner],
			id = layer.id,
			name = layer.name,
			mode = layer.mode,
			weight = layer.weight,
			weightKeys = Layers.clone(layer.weightKeys),
			muted = layer.muted,
			solo = layer.solo,
			locked = layer.locked,
		})
	end

	return out
end

local function validate(value)
	assert(
		type(value) == "table"
			and (value.version == 1 or value.version == 2)
			and type(value.layers) == "table"
			and #value.layers >= 1
			and #value.layers <= 12800,
		"Invalid animation layer stack"
	)
	local ids = {}
	for i, layer in value.layers do
		assert(
			type(layer.id) == "string"
				and #layer.id <= 64
				and not layer.id:find("|", 1, true)
				and not ids[layer.id],
			"Invalid animation layer identity"
		)
		ids[layer.id] = true
		assert(type(layer.name) == "string" and #layer.name <= 192, "Invalid animation layer name")
		assert(
			layer.mode == "Additive" or layer.mode == "Override",
			"Invalid animation layer blend"
		)
		assert(
			type(layer.weight) == "number" and layer.weight >= 0 and layer.weight <= 1,
			"Invalid animation layer weight"
		)
		for frame, w in layer.weightKeys or {} do
			assert(
				type(frame) == "number"
					and frame >= 0
					and frame <= 1000000
					and type(w) == "number"
					and w >= 0
					and w <= 1,
				"Invalid layer weight key"
			)
		end

		for _, flag in { "muted", "solo", "locked" } do
			assert(layer[flag] == nil or type(layer[flag]) == "boolean", "Invalid layer switch")
		end

		if i == 1 then
			assert(layer.id == "base" and layer.mode == "Override", "Missing Base Animation")
		end
	end

	return ids
end

local function decodedKey(text, motor, frame, fps, budget)
	assert(
		type(frame) == "number" and frame == frame and frame >= 0 and frame <= 1000000,
		"Invalid animation layer frame"
	)
	local key = Document.unpackKey(text, budget and Data.decodeJson(text, budget) or nil)
	assert(type(key) == "table" and typeof(key.C0) == "CFrame", "Invalid animation layer key")
	key.Frame, key.Time, key.Motor, key.Part = frame, frame / fps, motor, motor.Part1
	local Properties = require("Properties")
	if Properties.is(motor) then
		assert(
			Properties.validate(motor, Properties.decode(motor, key.C0, key.PropertyValue)),
			"Invalid layered property"
		)
	end

	return key
end

local function availableTracks(rig, raw)
	const Paths = require("Paths")
	const motors, collided = {}, {}
	for motor in require("motors").collect(rig, raw, true) do
		const id = Paths.motor(motor, rig)
		if not id then
			const own = typeof(motor) == "Instance" and Paths.of(motor, rig)
			if own then
				motors["motor:" .. own] = motor
			end
		elseif collided[id] then
			table.insert(collided[id], motor)
		elseif motors[id] then
			collided[id] = { motors[id], motor }
			motors[id] = nil
		else
			motors[id] = motor
		end
	end

	for id, list in collided do
		for _, motor in list do
			const own = typeof(motor) == "Instance" and Paths.of(motor, rig)
			if own and not motors["motor:" .. own] then
				motors["motor:" .. own] = motor
			elseif not motors[id] then
				motors[id] = motor
			end
		end
	end

	if rig == require("State").currentRig then
		for motor in raw.DefaultPose do
			if motor.Part1 and motor.Part1:GetAttribute("EclipseNavigationOrigin") then
				motors["$origin"] = motor
			end
		end
	end

	return motors
end

local function aliasResolver(rig, available)
	const Preview = require("rig")
	local byPart, byMotor
	local function original(object)
		return Preview.original(object) or object
	end

	return function(id)
		if type(id) ~= "string" then
			return nil
		end

		const joint = id:sub(1, 6) == "motor:"
		const path = joint and id:sub(7) or id
		if path:sub(1, 1) ~= "[" then
			return nil
		end

		const ok, object = pcall(require("Paths").resolve, rig, path)
		if not ok or typeof(object) ~= "Instance" then
			return nil
		end

		if not byPart then
			byPart, byMotor = {}, {}
			for _, motor in available do
				if typeof(motor) == "table" and (motor.IsEclipseProperty or motor.IsEclipseMasterControl) then
					continue
				end

				if typeof(motor) == "Instance" then
					byMotor[original(motor)] = motor
				end

				const part = motor.Part1
				if typeof(part) == "Instance" then
					const key = original(part)
					byPart[key] = (byPart[key] == nil or byPart[key] == motor) and motor or false
				end
			end
		end

		if joint then
			return byMotor[original(object)]
		end

		return byPart[original(object)] or nil
	end
end

local function loadTrack(row, track, motor, fps, budget)
	const ok, bucket = pcall(function()
		const bucket = {}
		for _, entry in track.keys do
			bucket[entry.frame] = decodedKey(entry.key, motor, entry.frame, fps, budget)
			if budget then
				budget()
			end
		end

		return bucket
	end)
	if not ok then
		warn("[Eclipse] A saved layer track could not be read and is kept unchanged: " .. tostring(bucket))
		return false
	end

	row.keys[motor] = bucket
	return true
end

function Storage.capture(rig, raw)
	if not raw.AnimationLayers then
		return nil
	end

	Layers.ensure(raw)
	Layers.syncProperties(raw)
	local stack = Layers.stack(raw, rig)
	local result = metadata(raw.AnimationLayers, stack)
	result.active = raw.AnimationLayers.activeByRig[rig] or "base"
	local motors = availableTracks(rig, raw)
	for i, layer in stack do
		local row = result.layers[i]
		row.tracks = {}
		row.properties = Layers.clone(layer.properties[rig] or { version = 1, tracks = {} })
		for id, motor in motors do
			local keys = {}
			for frame, key in layer.keys[motor] or {} do
				table.insert(keys, { frame = frame, key = Document.packKey(key) })
				local step = require("State").ProjectWorkStep
				if step then
					step()
				end
			end

			if #keys > 0 then
				table.sort(keys, function(a, b)
					return a.frame < b.frame
				end)
				table.insert(row.tracks, { id = id, keys = keys })
			end
		end

		const kept = retained[rig] and retained[rig][layer.id]
		if kept then
			const present = {}
			for _, track in row.tracks do
				present[track.id] = true
			end

			for _, track in kept do
				if not present[track.id] then
					present[track.id] = true
					table.insert(row.tracks, track)
				end
			end
		end

		table.sort(row.tracks, function(a, b)
			return a.id < b.id
		end)
	end

	return result
end

function Storage.retainedCount(rig)
	local count = 0
	for owner, layers in retained do
		if not rig or owner == rig then
			for _, tracks in layers do
				count += #tracks
			end
		end
	end

	for owner in unreadableNodes do
		if not rig or owner == rig then
			count += 1
		end
	end

	return count
end

function Storage.clearRetained(rig)
	if rig then
		retained[rig] = nil
		unreadableNodes[rig] = nil
	else
		table.clear(retained)
		table.clear(unreadableNodes)
	end
end

function Storage.write(sequence, rig, raw, archive)
	local value = archive or Storage.capture(rig, raw)
	const kept = unreadableNodes[rig]
	if not value and not kept then
		return
	end

	for _, name in { NAME, UNREADABLE } do
		const old = sequence:FindFirstChild(name)
		if old and (name == NAME or kept) then
			old:Destroy()
		end
	end

	if kept and (not value or #value.layers <= 1) then
		const copy = kept:Clone()
		copy.Name = NAME
		copy.Parent = sequence
		return
	end

	if kept then
		const copy = kept:Clone()
		copy.Name = UNREADABLE
		copy.Parent = sequence
	end

	Data.write(sequence, NAME, Document.pack(value))
end

local function legacyDuplicates(rig, sequence, value, available, budget)
	local ignored, wanted = {}, {}
	local project = sequence:GetAttribute("EclipseProjectId")
	if type(project) ~= "string" or project == "" then
		return ignored
	end

	for _, track in value.layers[1].tracks or {} do
		if
			type(track.id) == "string"
			and track.id:sub(1, 9) == "property:"
			and not available[track.id]
		then
			wanted[track.id] = track
		end
	end

	if not next(wanted) then
		return ignored
	end

	local declared = {}
	for _, layer in value.layers do
		for _, row in layer.properties and layer.properties.tracks or {} do
			declared["property:" .. row.id] = true
		end
	end

	local properties = sequence:FindFirstChild("EclipseProperties")
	if properties then
		for _, row in Document.unpackArchive(Data.read(properties), budget).tracks or {} do
			declared["property:" .. row.id] = true
		end
	end

	for id in declared do
		wanted[id] = nil
	end

	if not next(wanted) then
		return ignored
	end

	local function sameTrack(a, b)
		if type(b.keys) ~= "table" or #a.keys == 0 or #a.keys ~= #b.keys then
			return false
		end

		local keys = {}
		for _, entry in a.keys do
			if keys[entry.frame] then
				return false
			end

			keys[entry.frame] = entry.key
		end

		for _, entry in b.keys do
			if keys[entry.frame] ~= entry.key then
				return false
			end

			keys[entry.frame] = nil
		end

		return next(keys) == nil
	end

	local function inspect(owner, saved)
		if
			not saved:IsA("KeyframeSequence")
			or saved:GetAttribute("EclipseProjectId") ~= project
			or saved:GetAttribute("FPS") ~= sequence:GetAttribute("FPS")
		then
			return
		end

		local node = saved:FindFirstChild(NAME)
		local props = saved:FindFirstChild("EclipseProperties")
		if not node or not props then
			return
		end

		local archive = Document.unpackArchive(Data.read(node), budget)
		validate(archive)
		local base = archive.layers[1]
		local source = value.layers[1]
		if
			base.mode ~= source.mode
			or base.weight ~= source.weight
			or (base.muted == true) ~= (source.muted == true)
			or (base.solo == true) ~= (source.solo == true)
		then
			return
		end

		if not Document.equal(base.weightKeys or {}, source.weightKeys or {}) then
			return
		end

		local own = {}
		for _, row in Document.unpackArchive(Data.read(props), budget).tracks or {} do
			own["property:" .. row.id] = row.id
		end

		for _, track in base.tracks or {} do
			local original = wanted[track.id]
			if
				original
				and own[track.id]
				and require("Properties").definition(owner, own[track.id])
				and sameTrack(original, track)
			then
				ignored[original] = true
			end
		end
	end

	local pending = { rig }
	while #pending > 0 do
		local owner = table.remove(pending)
		for _, child in owner:GetChildren() do
			if child.Name == "AnimSaves" then
				if owner ~= rig then
					for _, saved in child:GetChildren() do
						pcall(inspect, owner, saved)
						if budget then
							budget()
						end
					end
				end
			else
				table.insert(pending, child)
			end
		end

		if budget then
			budget()
		end
	end

	return ignored
end

function Storage.restoreRig(rig, raw, value, keepActive, budget, sequence)
	local ids = validate(value)
	for _, layer in value.layers do
		for _, track in layer.tracks or {} do
			if track.id == "$origin" then
				require("Origin").ensure(require("State").Timeline)
			end
		end
	end

	local available = availableTracks(rig, raw)
	const alias = aliasResolver(rig, available)
	local rows = {}
	const missing = {}
	local ignored = sequence and legacyDuplicates(rig, sequence, value, available, budget) or {}
	for _, source in value.layers do
		local row = {}
		for k, v in source do
			if k ~= "tracks" and k ~= "properties" then
				row[k] = Layers.clone(v)
			end
		end

		row.keys = {}
		row.properties = {}
		const pending = {}
		local function keep(track)
			if type(track.keys) == "table" and #track.keys > 0 then
				missing[row] = missing[row] or {}
				table.insert(missing[row], track)
			end
		end

		for _, track in source.tracks or {} do
			if ignored[track] then
				continue
			end

			if track.id == "$origin" and rig ~= require("State").currentRig then
				continue
			end

			const motor = available[track.id]
			if not motor then
				table.insert(pending, track)
			elseif not loadTrack(row, track, motor, raw.FPS, budget) then
				keep(track)
			end
		end

		for _, track in pending do
			const motor = alias(track.id)
			if not motor or row.keys[motor] or not loadTrack(row, track, motor, raw.FPS, budget) then
				keep(track)
			end
		end

		row.properties[rig] = Layers.clone(source.properties or { version = 1, tracks = {} })
		table.insert(rows, row)
	end

	local data = Layers.ensure(raw)
	local ordered = { data.layers[1] }
	local used = { base = true }

	for _, motor in available do
		data.layers[1].keys[motor] = nil
	end

	for i = 2, #data.layers do
		local layer = data.layers[i]
		if layer.owner ~= rig then
			table.insert(ordered, layer)
			used[layer.id] = true
		end
	end

	local target = "base"
	for _, row in rows do
		local original = row.id
		if row.id == "base" then
			for motor, bucket in row.keys do
				ordered[1].keys[motor] = bucket
			end

			ordered[1].properties[rig] = row.properties[rig]
		else
			row.owner = rig
			if used[row.id] then
				row.id = Http:GenerateGUID(false)
			end

			used[row.id] = true
			table.insert(ordered, row)
			if original == value.active and not row.locked then
				target = row.id
			end
		end
	end

	if next(missing) then
		const layers = retained[rig] or {}
		retained[rig] = layers
		const names = {}
		for row, tracks in missing do
			const kept = layers[row.id] or {}
			layers[row.id] = kept
			const known = {}
			for _, track in kept do
				known[track.id] = true
			end

			for _, track in tracks do
				if known[track.id] then
					continue
				end

				known[track.id] = true
				table.insert(kept, track)
				table.insert(names, tostring(track.id))
			end
		end

		warn(
			"[Eclipse] " .. rig.Name .. ": kept saved layer keys for missing controls (" .. table.concat(names, ", ") .. "). They stay in the project and reload when the controls are restored."
		)
	end

	data.layers = ordered
	if not keepActive then
		data.activeByRig[rig] = target
	end

	Layers.rebuild(raw)
	Layers.restoreActiveProperties()
	return data.activeByRig[rig] or "base"
end

function Storage.prepareRead(sequence, budget)
	local node = sequence:FindFirstChild(NAME)
	if not node then
		return nil
	end

	const ok, value = pcall(function()
		const value = Document.unpackArchive(Data.read(node), budget)
		validate(value)
		return value
	end)
	if ok then
		unreadable[sequence] = nil
		return value
	end

	unreadable[sequence] = node
	warn("[Eclipse] The animation layers of " .. sequence.Name .. " could not be read. They are kept unchanged in the save: " .. tostring(value))
	return nil
end

function Storage.read(sequence, rig, timeline, budget, prepared, targetPivot)
	local node = sequence:FindFirstChild(NAME)
	if not node then
		return false
	end

	local value = prepared or not unreadable[sequence] and Storage.prepareRead(sequence, budget) or nil
	if not value then
		const raw = unreadable[sequence]
		if raw then
			unreadableNodes[rig] = raw:Clone()
		end

		return false
	end

	unreadableNodes[rig] = nil
	local active = Storage.restoreRig(rig, timeline:GetState(), value, nil, budget, sequence)
	local raw = timeline:GetState()
	raw._LayerLoadActive = raw._LayerLoadActive or {}
	raw._LayerLoadActive[rig] = active
	const Properties = require("Properties")
	const placement = Properties.shift(sequence)
	if placement then
		for _, layer in raw.AnimationLayers.layers do
			if layer.mode ~= "Override" then
				continue
			end

			for motor, bucket in layer.keys do
				if Properties.is(motor) and motor.Rig == rig and motor.PropertyId == "CFrame" then
					for _, key in bucket do
						Properties.shiftKey(key, placement, timeline)
					end
				end
			end
		end
	end

	local ratio = require("PoseSpace").savedRatio(rig, sequence)
	if ratio ~= 1 or typeof(sequence:GetAttribute("EclipseAuthoredPivot")) == "CFrame" then
		local available = require("motors").collect(rig, timeline:GetState(), true)
		for _, layer in timeline:GetState().AnimationLayers.layers do
			for motor in available do
				if
					typeof(motor) == "table"
					and (motor.IsEclipseProperty or motor.IsEclipseArmatureControl)
				then
					continue
				end

				for _, key in layer.keys[motor] or {} do
					require("PoseSpace").retargetKey(
						key,
						ratio,
						sequence:GetAttribute("EclipseAuthoredPivot"),
						targetPivot or require("PoseSpace").getImportPivot(rig, sequence)
					)
				end
			end
		end
	end

	return true
end

function Storage.withImport(timeline, fn)
	local raw = timeline:GetState()
	local data = raw.AnimationLayers
	local active
	if data then
		Layers.ensure(raw)
		Layers.syncProperties(raw)
		active = table.clone(data.activeByRig)
		data.activeByRig = {}
		Layers.rebuild(raw)
		Layers.restoreActiveProperties()
	end

	local loading = raw._LayerLoading
	raw._LayerLoading = true
	local result = table.pack(xpcall(fn, debug.traceback))
	raw._LayerLoading = loading
	if raw.AnimationLayers then
		Layers.ensure(raw)
		data = raw.AnimationLayers
		for rig, id in active or {} do
			data.activeByRig[rig] = id
		end

		for rig, id in raw._LayerLoadActive or {} do
			data.activeByRig[rig] = id
		end

		raw._LayerLoadActive = nil
		Layers.rebuild(raw)
		Layers.restoreActiveProperties()
	end

	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

return Storage
