--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Storage = {}
local Layers = require("Layers")
local Document = require("Document")
local Data = require("ChunkStore")
local Http = game:GetService("HttpService")
local NAME = "EclipseAnimationLayers"

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
	local motors = require("motors").motors(rig, raw)
	if rig == require("State").currentRig then
		for motor in raw.DefaultPose do
			if motor.Part1 and motor.Part1:GetAttribute("EclipseNavigationOrigin") then
				motors["$origin"] = motor
			end
		end
	end

	return motors
end

function Storage.capture(...)
	return require("RigIO").capture(...)
end

function Storage.write(...)
	return require("RigIO").write(...)
end

function Storage.restoreRig(...)
	return require("RigIO").restoreRig(...)
end

function Storage.prepareRead(...)
	return require("RigIO").prepareRead(...)
end

function Storage.read(...)
	return require("RigIO").read(...)
end

function Storage.withImport(...)
	return require("RigIO").withImport(...)
end

function Storage.captureLive(values, raw, motors, rigs, budget)
	if not Layers.has(raw) then
		return false
	end

	Layers.ensure(raw)
	Layers.syncProperties(raw)
	local owners = {}
	for id, rig in rigs do
		owners[rig] = id
	end

	local rows = {}
	for _, layer in raw.AnimationLayers.layers do
		if layer.id == "base" or owners[layer.owner] then
			table.insert(rows, layer)
		end
	end

	local meta = metadata(raw.AnimationLayers, rows, owners)
	meta.active = nil
	values.animationLayers = Document.pack(meta)
	for _, layer in rows do
		for id, motor in motors do
			for frame, key in layer.keys[motor] or {} do
				values["ak|" .. layer.id .. "|" .. id .. "|" .. frame] = Document.packKey(key)
				if budget then
					budget()
				end
			end
		end

		for id, rig in rigs do
			if layer.id == "base" or layer.owner == rig then
				values["ap|" .. layer.id .. "|" .. id] =
					Document.pack(layer.properties[rig] or { version = 1, tracks = {} })
			end
		end
	end

	return true
end

local function prepareKeyPatch(values, previous, raw, motors, fps, budget, timeline)
	if
		not previous
		or not raw.AnimationLayers
		or not timeline
		or not timeline._applyLiveKeyPatch
		or values.animationLayers ~= previous.animationLayers
	then
		return nil
	end

	for key, value in values do
		if key:sub(1, 3) == "ap|" and previous[key] ~= value then
			return nil
		end
	end

	for key, value in previous do
		if key:sub(1, 3) == "ap|" and values[key] ~= value then
			return nil
		end
	end

	local layers = {}
	for _, layer in Layers.ensure(raw).layers do
		layers[layer.id] = layer
	end

	local patches = {}

	local function add(key, value)
		local layerId, id, frame = key:match("^ak|([^|]+)|(.*)|([%d%.]+)$")
		if not layerId then
			return
		end

		local layer = assert(layers[layerId], "Missing Live animation layer")
		local motor = assert(motors[id], "Waiting for layered control")
		frame = tonumber(frame)
		assert(
			layer.id == "base" or Layers.owner(motor) == layer.owner,
			"Layer control belongs to another master"
		)
		local data = value and decodedKey(value, motor, frame, fps, budget) or false
		local byMotor = patches[layer]
		if not byMotor then
			byMotor = {}
			patches[layer] = byMotor
		end

		byMotor[motor] = byMotor[motor] or {}
		byMotor[motor][frame] = data
		if budget then
			budget()
		end
	end

	for key, value in values do
		if key:sub(1, 3) == "ak|" and previous[key] ~= value then
			add(key, value)
		end
	end

	for key in previous do
		if key:sub(1, 3) == "ak|" and values[key] == nil then
			add(key, nil)
		end
	end

	return function()
		for layer, byMotor in patches do
			for motor, patch in byMotor do
				local bucket = layer.keys[motor] or {}
				layer.keys[motor] = bucket
				timeline:_applyLiveKeyPatch(motor, patch, bucket)
			end
		end

		Layers.rebuild(raw)
		for _, byMotor in patches do
			for motor in byMotor do
				if timeline.RefreshAllChannelDiamondsForMotor then
					timeline:RefreshAllChannelDiamondsForMotor(motor)
				end
			end
		end

		Layers.refresh(false)
		timeline:RefreshAllKeyframeVisuals()
	end
end

function Storage.prepareLive(values, raw, motors, rigs, fps, budget, previous, timeline)
	if not values.animationLayers then
		return nil
	end

	local meta = Document.unpack(values.animationLayers)
	validate(meta)
	local patch = prepareKeyPatch(values, previous, raw, motors, fps, budget, timeline)
	if patch then
		return patch
	end

	local before = raw.AnimationLayers and Layers.snapshot(raw)
	local active = before and before.active or "base"
	local byId = {}
	assert(meta.version == 2, "Update Eclipse Live for per-master layers")
	for _, layer in meta.layers do
		if layer.id ~= "base" then
			layer.owner = assert(rigs[layer.owner], "Waiting for layer master")
		end

		layer.keys = {}
		layer.properties = {}
		byId[layer.id] = layer
	end

	local encoded = {}
	for key, value in values do
		if key:sub(1, 3) == "ak|" then
			encoded[key] = value
		end
	end

	local decoded = Document.unpackKeys(encoded, budget)
	for key, data in decoded do
		local layerId, id, frame = key:match("^ak|([^|]+)|(.*)|([%d%.]+)$")
		frame = tonumber(frame)
		local layer = assert(byId[layerId], "Missing Live animation layer")
		local motor = assert(motors[id], "Waiting for layered control")
		assert(
			layer.id == "base" or Layers.owner(motor) == layer.owner,
			"Layer control belongs to another master"
		)
		assert(
			frame and frame >= 0 and frame <= 1000000 and typeof(data.C0) == "CFrame",
			"Invalid Live layer key"
		)
		data.Frame, data.Time, data.Motor, data.Part = frame, frame / fps, motor, motor.Part1
		local Properties = require("Properties")
		if Properties.is(motor) then
			assert(
				Properties.validate(motor, Properties.decode(motor, data.C0, data.PropertyValue)),
				"Invalid shared layer property"
			)
		end

		layer.keys[motor] = layer.keys[motor] or {}
		layer.keys[motor][frame] = data
	end

	for key, value in values do
		local layerId, id = key:match("^ap|([^|]+)|(.*)$")
		if layerId then
			local layer = assert(byId[layerId])
			local rig = assert(rigs[id])
			assert(
				layer.id == "base" or layer.owner == rig,
				"Layer properties belong to another master"
			)
			layer.properties[rig] = Document.unpack(value)
		end
	end

	meta.scoped = true
	meta.master = before and before.master or require("State").currentRig
	meta.activeByRig = {}
	for _, rig in rigs do
		local id = before and before.activeByRig[rig]
		local layer = id and byId[id]
		meta.activeByRig[rig] = layer and layer.owner == rig and not layer.locked and id or "base"
	end

	meta.active = meta.activeByRig[meta.master] or "base"
	return function()
		Layers.restore(meta)
	end
end

return Storage
