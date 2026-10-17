--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local L = {}
local Raw = require("RawState").Timeline
local Main = require("State")
local Properties = require("Properties")
local Policy = require("Policy")
local Interp = require("Interp")
local Physics = require("Cache")
local Http = game:GetService("HttpService")
local listeners = {}
local refs

local evaluation
local physicsSource

local function withEvaluation(fn)
	if evaluation then
		return fn()
	end

	evaluation = { owners = {}, rigs = {}, weights = {}, solo = {} }
	for _, rig in Main.getAllRigs() do
		evaluation.rigs[rig] = true
	end

	local result = table.pack(xpcall(fn, debug.traceback))
	evaluation = nil
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

local function notify()
	for callback in listeners do
		callback()
	end
end

function L.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

function L.init(value)
	refs = value
end

local function clone(value, key)
	if key == "Button" then
		return nil
	end

	if key == "Motor" or key == "Part" or typeof(value) ~= "table" then
		return value
	end

	local out = {}
	for k, v in value do
		out[k] = clone(v, k)
	end

	return out
end

L.clone = clone

function L.owner(motor)
	if not motor then
		return nil
	end

	if typeof(motor) == "table" and motor.Rig then
		return motor.Rig
	end

	local object = motor.Part1 or motor.Parent
	if typeof(object) == "Instance" and object:GetAttribute("EclipseNavigationOrigin") then
		return Main.currentRig
	end

	if evaluation and evaluation.owners[motor] ~= nil then
		return evaluation.owners[motor] or nil
	end

	local rigs = not evaluation and Main.getAllRigs()
	while typeof(object) == "Instance" do
		if
			evaluation and evaluation.rigs[object]
			or not evaluation and table.find(rigs, object)
		then
			if evaluation then
				evaluation.owners[motor] = object
			end

			return object
		end

		object = object.Parent
	end

	local membership = require("Membership")
	for _, rig in Main.getAllRigs() do
		local owned = membership.ownedKeys(Raw, rig)
		if membership.belongs(motor, rig, owned) then
			if evaluation then
				evaluation.owners[motor] = rig
			end

			return rig
		end
	end

	return nil
end

local function find(data, id)
	for _, layer in data.layers do
		if layer.id == id then
			return layer
		end
	end

	return data.layers[1]
end

local function forRig(data, rig)
	local layer = find(data, rig and data.activeByRig and data.activeByRig[rig])
	if layer.id == "base" or layer.owner == rig and not layer.locked then
		return layer
	end

	return data.layers[1]
end

local function flush(raw, data)
	if not data.view or raw._LayerContext or raw._LayerBaked or raw._LayerReading then
		return
	end

	for motor, layer in data.viewOwners do
		layer.keys[motor] = raw.Keyframes[motor]
	end

	for motor, bucket in raw.Keyframes do
		if not data.viewOwners[motor] then
			local layer = forRig(data, L.owner(motor))
			layer.keys[motor] = bucket
			data.viewOwners[motor] = layer
		end
	end

	data.view = raw.Keyframes
end

function L.rebuild(raw)
	raw = raw or Raw
	local data = raw.AnimationLayers
	if not data then
		return
	end

	local view, owners = {}, {}
	for _, layer in data.layers do
		for motor, bucket in layer.keys do
			if forRig(data, L.owner(motor)) == layer then
				view[motor] = bucket
				owners[motor] = layer
			end
		end
	end

	local destination = raw.Keyframes
	for _, layer in data.layers do
		if layer.keys == destination then
			layer.keys = table.clone(destination)
		end
	end

	table.clear(destination)
	for motor, bucket in view do
		destination[motor] = bucket
	end

	data.view = destination
	data.viewOwners = owners
	local clips = Physics.list(raw)
	if #clips > 0 then
		Physics.set(raw, clips)
	end

	data.active = forRig(data, data.master).id
end

function L.ensure(raw)
	raw = raw or Raw
	if not raw.AnimationLayers then
		raw.AnimationLayers = {
			scoped = true,
			master = Main.currentRig,
			active = "base",
			activeByRig = {},
			layers = {
				{
					id = "base",
					name = "Base Animation",
					mode = "Override",
					weight = 1,
					keys = raw.Keyframes,
					properties = {},
				},
			},
		}
		L.rebuild(raw)
	end

	local data = raw.AnimationLayers
	if
		evaluation
		and evaluation.raw == raw
		and evaluation.data == data
		and evaluation.keys == raw.Keyframes
	then
		return data
	end

	if data.scoped and not table.find(Main.getAllRigs(), data.master) then
		data.master = Main.currentRig
		data.active = forRig(data, data.master).id
	end

	if not data.scoped then
		local oldActive = data.active
		local rows = { data.layers[1] }
		local activeByRig = {}
		for _, rig in Main.getAllRigs() do
			for i = 2, #data.layers do
				local old = data.layers[i]
				local row = { keys = {}, properties = {} }
				for k, v in old do
					if k ~= "keys" and k ~= "properties" then
						row[k] = clone(v)
					end
				end

				row.id = Http:GenerateGUID(false)
				row.owner = rig
				for motor, bucket in old.keys do
					if L.owner(motor) == rig then
						row.keys[motor] = bucket
					end
				end

				row.properties[rig] = old.properties[rig]
				table.insert(rows, row)
				if old.id == oldActive then
					activeByRig[rig] = row.id
				end
			end
		end

		data.layers = rows
		data.activeByRig = activeByRig
		data.master = Main.currentRig
		data.scoped = true
		L.rebuild(raw)
	else
		flush(raw, data)
	end

	if evaluation then
		evaluation.raw = raw
		evaluation.data = data
		evaluation.keys = raw.Keyframes
	end

	return data
end

function L.has(raw)
	return raw.AnimationLayers ~= nil and #raw.AnimationLayers.layers > 1 and not raw._LayerBaked
end

function L.active(raw, motor)
	local data = L.ensure(raw)
	if motor then
		return forRig(data, L.owner(motor))
	end

	return forRig(data, data.master)
end

function L.stack(raw, rig)
	local data = L.ensure(raw)
	rig = rig or data.master
	local rows = { data.layers[1] }
	for i = 2, #data.layers do
		if data.layers[i].owner == rig then
			table.insert(rows, data.layers[i])
		end
	end

	return rows
end

function L.master()
	return L.ensure(Raw).master
end

function L.setMaster(rig)
	if require("BlenderEdit").blocked() then
		return false
	end

	if not rig or not table.find(Main.getAllRigs(), rig) then
		return false
	end

	local data = L.ensure(Raw)
	if data.master == rig then
		return true
	end

	if refs then
		refs.Finalize()
	end

	data.master = rig
	data.active = forRig(data, rig).id
	notify()
	return true
end

function L.weight(layer, time, fps)
	local memo = evaluation and evaluation.weights[layer]
	fps = fps or Raw.FPS
	if memo and memo.time == time and memo.fps == fps then
		return memo.value
	end

	local value = layer.weight or 1
	local previous, following
	for frame, w in layer.weightKeys or {} do
		local t = frame / (fps or Raw.FPS)
		if t <= time and (not previous or t > previous.t) then
			previous = { t = t, w = w }
		end

		if t > time and (not following or t < following.t) then
			following = { t = t, w = w }
		end
	end

	if not previous and following then
		value = following.w
	end

	if previous then
		value = previous.w
		if following then
			value += (following.w - value) * math.clamp(
				(time - previous.t) / (following.t - previous.t),
				0,
				1
			)
		end
	end

	value = math.clamp(value, 0, 1)
	if evaluation then
		evaluation.weights[layer] = { time = time, fps = fps, value = value }
	end

	return value
end

local function contributing(data, layer, rig)
	if layer.id ~= "base" and layer.owner ~= rig then
		return false
	end

	local key = rig or false
	local solo = evaluation and evaluation.solo[key]
	if solo == nil then
		solo = false
		for _, other in data.layers do
			if other.owner == rig and other.solo then
				solo = true
				break
			end
		end

		if evaluation then
			evaluation.solo[key] = solo
		end
	end

	if solo and not layer.solo then
		return false
	end

	return not layer.muted
end

local function pow(cf, n)
	local axis, angle = cf.Rotation:ToAxisAngle()
	return CFrame.new(cf.Position * n) * CFrame.fromAxisAngle(axis, angle * n)
end

local function lerp(a, b, w)
	local kind = typeof(a)
	if kind == "CFrame" then
		local axis, angle = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
		return CFrame.new(a.Position:Lerp(b.Position, w))
			* a.Rotation
			* CFrame.fromAxisAngle(axis, angle * w)
	elseif kind == "number" then
		return a + (b - a) * w
	elseif kind == "Vector3" or kind == "Color3" or kind == "Vector2" then
		return a:Lerp(b, w)
	else
		if w >= 0.5 then
			return b
		else
			return a
		end
	end
end

local function add(a, b, rest, w)
	local kind = typeof(a)
	if kind == "CFrame" then
		return a * pow(rest:Inverse() * b, w)
	elseif kind == "number" or kind == "Vector3" or kind == "Vector2" then
		return a + (b - rest) * w
	elseif kind == "Color3" then
		return Color3.new(
			a.R + (b.R - rest.R) * w,
			a.G + (b.G - rest.G) * w,
			a.B + (b.B - rest.B) * w
		)
	else
		if w >= 0.5 then
			return b
		else
			return a
		end
	end
end

local function invert(after, value, rest, w, mode)
	if not table.find({ "CFrame", "number", "Vector3", "Vector2", "Color3" }, typeof(after)) then
		if w >= 0.5 then
			return nil
		else
			return after
		end
	end

	if mode == "Override" then
		if w >= 0.999999 then
			return nil
		end

		return lerp(value, after, 1 / (1 - w))
	end

	if typeof(after) == "CFrame" then
		return after * pow(rest:Inverse() * value, w):Inverse()
	end

	return add(after, value, rest, -w)
end

local function solve(before, desired, rest, w, mode)
	if mode == "Override" then
		return lerp(before, desired, 1 / w)
	end

	if typeof(desired) == "CFrame" then
		return rest * pow(before:Inverse() * desired, 1 / w)
	end

	return add(rest, desired, before, 1 / w)
end

local function bounds(bucket, time)
	return require("Parenting").bounds(Policy.activeBucket(bucket), time)
end

local function exists(bucket)
	for _, key in bucket or {} do
		if not key.Disabled then
			return true
		end
	end

	return false
end

local function sample(timeline, layer, motor, time, loopEnd, scale)
	return Physics.without(function()
		local bucket = layer.keys[motor] or {}
		if scale then
			local s = timeline:EvaluateMotorScale(motor, time, bucket, loopEnd) or {}
			return Vector3.new(s.scale_x or 1, s.scale_y or 1, s.scale_z or 1)
		end

		if Properties.is(motor) then
			return Properties.evaluate(motor, bucket, time, loopEnd)
		end

		return timeline:EvaluateMotorC0(motor, time, bucket, loopEnd)
	end)
end

local function restFor(raw, motor, scale)
	if scale then
		return Vector3.one
	end

	if Properties.is(motor) then
		return motor.DefaultValue
	end

	return raw.DefaultPose[motor] or motor.C0
end

local function scaleBlend(a, b, w, mode)
	if mode == "Override" then
		return a:Lerp(b, w)
	end

	return a
		* Vector3.new(math.max(b.X, 1e-5) ^ w, math.max(b.Y, 1e-5) ^ w, math.max(b.Z, 1e-5) ^ w)
end

local function physicsValue(timeline, motor, time, loopEnd, scale)
	local bucket = (physicsSource or timeline:GetState().Keyframes)[motor]
	if not Physics.contains(bucket, time) then
		return nil
	end

	if scale then
		local values = timeline:EvaluateMotorScale(motor, time, bucket, loopEnd) or {}
		return Vector3.new(values.scale_x or 1, values.scale_y or 1, values.scale_z or 1)
	end

	return timeline:EvaluateMotorC0(motor, time, bucket, loopEnd)
end

function L.evaluate(timeline, motor, time, loopEnd, scale)
	local raw = timeline:GetState()
	local data = L.ensure(raw)
	local simulated = physicsValue(timeline, motor, time, loopEnd, scale)
	local result = simulated or restFor(raw, motor, scale)
	local keyed = simulated ~= nil
	local rig = L.owner(motor)
	for _, layer in data.layers do
		if
			(not simulated or layer.id ~= "base")
			and exists(layer.keys[motor])
			and contributing(data, layer, rig)
		then
			local w = layer.id == "base" and 1 or L.weight(layer, time, raw.FPS)
			if w > 0 then
				local value = sample(timeline, layer, motor, time, loopEnd, scale)
				result = scale and scaleBlend(result, value, w, layer.mode)
					or layer.mode == "Additive" and add(
						result,
						value,
						restFor(raw, motor, false),
						w
					)
					or lerp(result, value, w)
				keyed = true
			end
		end
	end

	return result, keyed
end

function L.c0(timeline, motor, time, loopEnd)
	local value, keyed = L.evaluate(timeline, motor, time, loopEnd, false)
	return Properties.is(motor) and Properties.encode(value) or value, keyed
end

function L.scale(timeline, motor, time, loopEnd)
	local value = L.evaluate(timeline, motor, time, loopEnd, true)
	return { scale_x = value.X, scale_y = value.Y, scale_z = value.Z }
end

function L.solveValue(timeline, motor, time, desired, scale)
	local raw = timeline:GetState()
	local data = L.ensure(raw)
	local active = L.active(raw, motor)
	if active.id == "base" and not L.has(raw) then
		return desired
	end

	if active.locked or not contributing(data, active, L.owner(motor)) then
		return nil
	end

	local w = active.id == "base" and 1 or L.weight(active, time, raw.FPS)
	if w < 1e-5 then
		return nil
	end

	local index = table.find(data.layers, active)
	local target = desired
	local rest = restFor(raw, motor, scale)
	for i = #data.layers, index + 1, -1 do
		local layer = data.layers[i]
		local weight = L.weight(layer, time, raw.FPS)
		if
			contributing(data, layer, L.owner(motor))
			and weight > 0
			and exists(layer.keys[motor])
		then
			local value = sample(timeline, layer, motor, time, nil, scale)
			if scale and layer.mode == "Additive" then
				target = target
					/ Vector3.new(
						math.max(value.X, 1e-5) ^ weight,
						math.max(value.Y, 1e-5) ^ weight,
						math.max(value.Z, 1e-5) ^ weight
					)
			else
				target = invert(target, value, rest, weight, layer.mode)
			end

			if target == nil then
				return nil
			end
		end
	end

	local simulated = physicsValue(timeline, motor, time, nil, scale)
	local before = simulated or rest
	for i = 1, index - 1 do
		local layer = data.layers[i]
		local weight = layer.id == "base" and 1 or L.weight(layer, time, raw.FPS)
		if
			(not simulated or layer.id ~= "base")
			and contributing(data, layer, L.owner(motor))
			and weight > 0
			and exists(layer.keys[motor])
		then
			local value = sample(timeline, layer, motor, time, nil, scale)
			before = scale and scaleBlend(before, value, weight, layer.mode)
				or layer.mode == "Additive" and add(before, value, rest, weight)
				or lerp(before, value, weight)
		end
	end

	if scale and active.mode == "Additive" then
		local ratio = target / before
		return Vector3.new(
			math.max(ratio.X, 1e-5) ^ (1 / w),
			math.max(ratio.Y, 1e-5) ^ (1 / w),
			math.max(ratio.Z, 1e-5) ^ (1 / w)
		)
	end

	return solve(before, target, rest, w, active.mode)
end

function L.prepareRecord(timeline, motor, c0, options)
	local raw = timeline:GetState()
	if
		not motor
		or not c0
		or not L.has(raw)
		or raw._LayerLoading
		or options and options.LayerRaw
	then
		return c0, options
	end

	local time = options and options.Frame and options.Frame / raw.FPS or raw.CurrentTime
	local desired = c0
	if Properties.is(motor) then
		local value = options and options.PropertyValue
		if value == nil and motor.Definition.kind ~= "CFrame" then
			value = Properties.readValue(motor.Rig, motor.PropertyId)
		end

		desired = Properties.decode(motor, c0, value)
	end

	local referenceLocal, referenceWorld, referenceMaster, parented
	if not Properties.is(motor) then
		local composed = L.dominant(raw, motor, time)
		parented = composed and composed.Parented
		if parented == false then
			referenceLocal, referenceWorld, referenceMaster =
				L.worldReference(timeline, motor, time)
			local Parenting = require("Parenting")
			local parentMotor = raw.MotorByPart[Parenting.realPart0(motor)]
			local parent = parentMotor and Parenting.worldOf(parentMotor, raw.MotorByPart)
				or motor.Part0.CFrame
			local world = parent * desired * motor.C1:Inverse()
			desired = referenceLocal
				* motor.C1:Inverse()
				* referenceWorld:Inverse()
				* world
				* motor.C1
		end
	end

	local value = L.solveValue(timeline, motor, time, desired, false)
	if value == nil then
		require("Notification").show(
			"LAYER NOT EDITABLE",
			"Unmute the layer, raise its weight, or select a layer above the override."
		)
		return nil
	end

	options = table.clone(options or {})
	options.LayerParented = parented
	if referenceWorld then
		options.LayerWorldCFrame = referenceWorld
			* motor.C1
			* referenceLocal:Inverse()
			* value
			* motor.C1:Inverse()
		options.LayerMasterWorld = referenceMaster
	end

	if Properties.is(motor) then
		options.PropertyValue = value
		return Properties.encode(value), options
	end

	return value, options
end

function L.recordScale(timeline, motor, values, frame, options)
	local raw = timeline:GetState()
	if not L.has(raw) or raw._LayerLoading or options and options.LayerRaw then
		return
	end

	local value = L.solveValue(
		timeline,
		motor,
		frame / raw.FPS,
		Vector3.new(values.scale_x or 1, values.scale_y or 1, values.scale_z or 1),
		true
	)
	if value then
		values.scale_x, values.scale_y, values.scale_z = value.X, value.Y, value.Z
	end
end

function L.buckets(raw)
	local result = {}
	if L.has(raw) then
		for _, layer in L.ensure(raw).layers do
			for _, bucket in layer.keys do
				table.insert(result, bucket)
			end
		end
	else
		for _, bucket in raw.Keyframes do
			table.insert(result, bucket)
		end
	end

	return result
end

function L.allTracks(raw)
	if not L.has(raw) then
		return raw.Keyframes
	end

	local data = L.ensure(raw)
	local out = {}
	for _, layer in data.layers do
		for motor, bucket in layer.keys do
			if raw.DefaultPose[motor] == nil then
				continue
			end

			out[motor] = out[motor] or {}
			for frame, key in bucket do
				out[motor][frame] = key
			end
		end
	end

	return out
end

function L.worldReference(timeline, motor, time)
	local bucket = (physicsSource or timeline:GetState().Keyframes)[motor]
	if Physics.contains(bucket, time) then
		local active = Policy.activeBucket(bucket)
		local previous, following = bounds(active, time)
		local source = previous or following
		local localPose = timeline:EvaluateMotorC0(motor, time, bucket)
		local world = source and source.WorldCFrame
		if
			previous
			and following
			and previous ~= following
			and previous.WorldCFrame
			and following.WorldCFrame
		then
			world = Interp.cframe(
				active,
				previous,
				following,
				math.clamp((time - previous.Time) / (following.Time - previous.Time), 0, 1),
				"WorldCFrame"
			)
		end

		return localPose,
			world or motor.Part0.CFrame * localPose * motor.C1:Inverse(),
			source and source.MasterWorld
	end

	local data = L.ensure(timeline:GetState())
	local base = data.layers[1]
	local p, n = bounds(base.keys[motor], time)
	local baseLocal = sample(timeline, base, motor, time)
	local master = require("MasterControl").worldDelta(motor, function(m, t)
		return sample(timeline, base, m, t)
	end, time)
	if master then
		local raw = timeline:GetState()
		local evaluator = evaluation and evaluation.worldReference
		if not evaluator then
			evaluator = require("Parenting").newEvaluator(
				{},
				base.keys,
				raw.DefaultPose,
				raw.DefaultWorldPose,
				raw.ParentingDefaults,

				function(m, t)
					return sample(timeline, base, m, t)
				end
			)
			if evaluation then
				evaluation.worldReference = evaluator
			end
		end

		return baseLocal, evaluator.worldAt(motor, time), master
	end

	local world = p and p.WorldCFrame
		or n and n.WorldCFrame
		or motor.Part0.CFrame * baseLocal * motor.C1:Inverse()
	if p and n and p ~= n and p.WorldCFrame and n.WorldCFrame then
		world = Interp.cframe(
			base.keys[motor],
			p,
			n,
			math.clamp((time - p.Time) / (n.Time - p.Time), 0, 1),
			"WorldCFrame"
		) or world
	end

	return baseLocal, world
end

function L.dominant(raw, motor, time)
	local physicsBucket = (physicsSource or raw.Keyframes)[motor]
	if Physics.contains(physicsBucket, time) then
		local previous, following = bounds(physicsBucket, time)
		return previous or following
	end

	local data = L.ensure(raw)
	local dominant
	for _, layer in data.layers do
		if contributing(data, layer, L.owner(motor)) and L.weight(layer, time, raw.FPS) >= 0.5 then
			local previous, following = bounds(layer.keys[motor], time)
			dominant = previous or following or dominant
		end
	end

	return dominant
end

local cameraMetadata = setmetatable({}, { __mode = "k" })

function L.cameraMetadataBucket(raw, motor, time, field)
	if not motor or not L.has(raw) then
		return motor and raw.Keyframes[motor]
	end

	local data = L.ensure(raw)
	local rig = L.owner(motor)
	local source
	local revision = require("cache").revision()
	for _, layer in data.layers do
		if contributing(data, layer, rig) and L.weight(layer, time, raw.FPS) >= 0.5 then
			local bucket = layer.keys[motor]
			if bucket then
				local cached = cameraMetadata[bucket]
				if not cached or cached.revision ~= revision then
					cached = { revision = revision }
					cameraMetadata[bucket] = cached
					for _, key in bucket do
						if not key.Disabled and not key.GraphOnly then
							for _, name in
								{
									"CamTargetEnabled",
									"CamTrackTo",
									"CamTargetParent",
									"CamAttachTarget",
								}
							do
								if key[name] ~= nil then
									cached[name] = true
								end
							end
						end
					end
				end

				if cached[field] then
					source = bucket
				end
			end
		end
	end

	return source
end

local function sampleTracks(timeline, time, scope)
	local raw = timeline:GetState()
	local data = L.ensure(raw)
	local tracks = {}
	local motors = raw.Keyframes
	if L.has(raw) then
		motors = {}
		for _, layer in data.layers do
			for motor in layer.keys do
				if raw.DefaultPose[motor] ~= nil then
					motors[motor] = true
				end
			end
		end
	end

	for motor in motors do
		if scope and L.owner(motor) ~= scope then
			continue
		end

		local physicsBucket = raw.Keyframes[motor]
		if Physics.contains(physicsBucket, time) then
			local bucket = Policy.activeBucket(physicsBucket)
			local previous, following = require("Parenting").bounds(bucket, time)
			local source = previous or following
			if source then
				local key = clone(source)
				key.Frame = time * raw.FPS
				key.Time = time
				key.Motor = motor
				key.Part = motor.Part1
				local simulated = timeline:EvaluateMotorC0(motor, time, physicsBucket)
				key.C0 = L.c0(timeline, motor, time)
				if previous and following and following.Time > previous.Time then
					local alpha =
						math.clamp((time - previous.Time) / (following.Time - previous.Time), 0, 1)
					for _, field in { "WorldCFrame", "MasterWorld" } do
						if previous[field] and following[field] then
							key[field] = Interp.cframe(bucket, previous, following, alpha, field)
						end
					end
				end

				if key.WorldCFrame then
					key.WorldCFrame = key.WorldCFrame
						* motor.C1
						* simulated:Inverse()
						* key.C0
						* motor.C1:Inverse()
				end

				key.Position = key.C0.Position
				key.Rotation = key.C0.Rotation
				key.GraphCurves = nil
				key.ChannelPoseC0 = nil
				key.Channels = {}
				for id, value in timeline:DecomposeC0(key.C0) do
					key.Channels[id] = { Value = value }
				end

				for id, value in L.scale(timeline, motor, time) do
					key.Channels[id] = { Value = value }
				end

				key.EasingStyle = "Linear"
				key.EasingDirection = "In"
				key.HandleType = "Vector"
				tracks[motor] = { [key.Frame] = key }
			end

			continue
		end

		local cf, keyed = L.c0(timeline, motor, time)
		if not keyed then
			continue
		end

		local dominant = L.dominant(raw, motor, time)
		local key = dominant and clone(dominant) or {}
		key.Frame = time * raw.FPS
		key.Time = time
		key.Motor = motor
		key.Part = motor.Part1
		key.C0 = cf
		key.Position = cf.Position
		key.Rotation = cf.Rotation
		key.GraphCurves = nil
		key.BlenderCurve = nil
		key.BlenderSource = nil
		key.ChannelPoseC0 = nil
		key.Disabled = nil
		key.Channels = nil
		key.EasingStyle = "Linear"
		key.EasingDirection = "In"
		key.HandleType = "Vector"
		local camera = require("CameraRig")
		if camera.isTransform(motor) then
			key.CamTrackTo = require("Target").weight(camera.owner(motor), time)
		elseif require("Target").is(motor) then
			key.CamTargetEnabled = require("Target").enabledAt(camera.owner(motor), time)
		end

		if require("Target").isAttachment(motor) then
			local selected = require("Target").attachmentKey(camera.owner(motor), time)
			key.CamAttachTarget = clone(selected and selected.CamAttachTarget or false)
			key.EasingStyle = "Constant"
			key.Channels = nil
			tracks[motor] = { [key.Frame] = key }
			continue
		end

		if Properties.is(motor) then
			key.PropertyValue = L.evaluate(timeline, motor, time)
		else
			local scale = L.scale(timeline, motor, time)
			key.WholePoseScale = scale
			key.Channels = timeline:DecomposeC0(cf)
			local values = key.Channels
			key.Channels = {}
			for id, value in values do
				key.Channels[id] = { Value = value }
			end

			for id, value in scale do
				key.Channels[id] = { Value = value }
			end

			if key.Parented == false then
				local baseLocal, baseWorld, master = L.worldReference(timeline, motor, time)
				key.WorldCFrame = baseWorld
					* motor.C1
					* baseLocal:Inverse()
					* cf
					* motor.C1:Inverse()
				key.MasterWorld = master
			end
		end

		tracks[motor] = { [key.Frame] = key }
	end

	return tracks
end

function L.sampleTracks(timeline, time, scope)
	local raw = timeline:GetState()
	L.ensure(raw)
	local reading = raw._LayerReading
	raw._LayerReading = true
	local ok, result = xpcall(function()
		return withEvaluation(function()
			return sampleTracks(timeline, time, scope)
		end)
	end, debug.traceback)
	raw._LayerReading = reading
	if not ok then
		error(result, 0)
	end

	return result
end

function L.withPose(timeline, time, fn)
	local raw = timeline:GetState()
	if Main.LoadingProject and Main.ProjectLoadThread ~= coroutine.running() then
		return
	end

	if not L.has(raw) or raw._LayerContext then
		return fn()
	end

	L.ensure(raw)
	local tracks = L.sampleTracks(timeline, time)
	local before = raw.Keyframes
	local previousPhysics = physicsSource
	physicsSource = before

	local loading, thread, importing =
		Main.LoadingProject, Main.ProjectLoadThread, raw._ImportingKeyframes
	Main.LoadingProject = true
	Main.ProjectLoadThread = coroutine.running()
	raw._ImportingKeyframes = true
	raw._LayerContext = true
	raw.Keyframes = tracks
	local results = table.pack(xpcall(fn, debug.traceback))

	if raw.Keyframes == tracks then
		raw.Keyframes = before
	end

	raw._LayerContext = nil
	physicsSource = previousPhysics
	Main.LoadingProject, Main.ProjectLoadThread, raw._ImportingKeyframes =
		loading, thread, importing
	if not results[1] then
		error(results[2], 0)
	end

	return table.unpack(results, 2, results.n)
end

function L.refresh(structure)
	require("cache").invalidate()
	table.clear(Raw._motorUniform)
	table.clear(Raw._motorHasScale)
	if Raw._evaluationBuckets then
		table.clear(Raw._evaluationBuckets)
	end

	if Main.GraphEditor then
		Main.GraphEditor.invalidate()
	end

	if structure == "keys" and Main.Timeline then
		local timeline = Main.Timeline
		timeline:EnsureTransformChannelStarts()
		timeline:InvalidateMotorListCache()
		timeline:RebuildAllTimelineKeyframeButtons(
			nil,
			Main.UIHelpers and Main.UIHelpers.SanitizeName
		)
		for motor in Raw.ChannelTracks do
			timeline:RefreshAllChannelDiamondsForMotor(motor)
		end

		timeline:UpdatePlayhead()
	elseif refs and structure then
		refs.RefreshStructure()
	end

	if Main.Timeline and Main.currentRig then
		Main.Timeline:ApplyPoseAtTime(Main.currentRig, Raw.CurrentTime)
	end

	Main.currentProjectSaved = false
	notify()
end

local function syncProperties(raw)
	local data = L.ensure(raw)
	for _, rig in Main.getAllRigs() do
		local active = forRig(data, rig)
		active.properties = active.properties or {}
		active.properties[rig] = require("ArmatureAnimation").propertySnapshot(rig)
	end
end

local function hideKeys(raw)
	for _, bucket in raw.Keyframes do
		for _, key in bucket do
			if key.Button then
				key.Button:Destroy()
				key.Button = nil
			end
		end
	end

	if Main.Timeline and Main.Timeline.ClearSelectedKeyframes then
		Main.Timeline:ClearSelectedKeyframes()
	end
end

function L.select(id, internal)
	if require("BlenderEdit").blocked() then
		return false
	end

	local data = L.ensure(Raw)
	local layer
	for _, value in data.layers do
		if value.id == id then
			layer = value
			break
		end
	end

	if not layer or layer.locked and not internal then
		return false
	end

	if layer.owner then
		data.master = layer.owner
	end

	if layer.id == data.active and forRig(data, data.master) == layer then
		return true
	end

	if not internal and refs then
		refs.Finalize()
	end

	syncProperties(Raw)
	hideKeys(Raw)
	data.activeByRig[data.master] = id
	L.rebuild(Raw)
	L.restoreActiveProperties()
	L.refresh("keys")
	return true
end

function L.snapshot(raw)
	raw = raw or Raw
	local data = L.ensure(raw)
	local out = {
		scoped = true,
		master = data.master,
		active = data.active,
		activeByRig = table.clone(data.activeByRig or {}),
		layers = {},
	}
	for _, layer in data.layers do
		local nextLayer = {}
		for k, v in layer do
			if k ~= "keys" and k ~= "properties" then
				nextLayer[k] = clone(v)
			end
		end

		nextLayer.keys = {}
		for motor, bucket in layer.keys do
			nextLayer.keys[motor] = clone(bucket)
		end

		nextLayer.properties = {}
		for rig, value in layer.properties do
			nextLayer.properties[rig] = clone(value)
		end

		table.insert(out.layers, nextLayer)
	end

	return out
end

function L.restore(snapshot)
	hideKeys(Raw)
	Raw.AnimationLayers = nil
	local copy = L.copySnapshot(snapshot)
	Raw.AnimationLayers = copy
	L.rebuild(Raw)
	L.restoreActiveProperties()
	L.refresh(true)
end

local function transaction(name, callback, options)
	if
		(Raw.Playing and not (options and options.duringPlayback))
		or require("BlenderEdit").blocked()
	then
		return false
	end

	if refs then
		refs.Finalize()
	end

	syncProperties(Raw)
	local before = L.snapshot()
	callback(L.ensure(Raw))
	L.rebuild(Raw)
	L.restoreActiveProperties()
	local after = L.snapshot()
	L.refresh(not options or options.structure ~= false)
	require("History").record(function()
		L.restore(before)
	end, function()
		L.restore(after)
	end, name)
	return true
end

function L.add()
	return transaction("Add animation layer", function(data)
		if #L.stack(Raw) >= 128 then
			require("Notification").show("LAYER LIMIT", "This master already has 128 layers.")
			return
		end

		local layer = {
			id = Http:GenerateGUID(false),
			name = "Layer " .. #L.stack(Raw),
			owner = data.master,
			mode = "Additive",
			weight = 1,
			keys = {},
			properties = {},
		}
		table.insert(data.layers, layer)
		hideKeys(Raw)
		data.activeByRig[data.master] = layer.id
	end)
end

function L.change(id, field, value, toggle)
	return transaction("Change animation layer", function(data)
		for _, layer in data.layers do
			if layer.id == id then
				if layer.id == "base" then
					return
				end

				if field == "name" then
					value = tostring(value):match("^%s*(.-)%s*$"):sub(1, 48)
					if value == "" then
						return
					end
				elseif field == "mode" then
					assert(value == "Additive" or value == "Override")
				elseif field == "weight" then
					assert(type(value) == "number" and value == value)
					value = math.clamp(value, 0, 1)
				else
					assert(field == "muted" or field == "solo" or field == "locked")
					if toggle then
						value = not layer[field]
					else
						value = value == true
					end
				end

				if
					field == "weight"
					and layer.weightKeys
					and layer.weightKeys[math.round(Raw.CurrentTime * Raw.FPS)] ~= nil
				then
					layer.weightKeys[math.round(Raw.CurrentTime * Raw.FPS)] = value
				else
					layer[field] = value
				end

				if field == "solo" and value then
					layer.muted = false
				end

				if field == "locked" and value and data.activeByRig[layer.owner] == id then
					hideKeys(Raw)
					data.activeByRig[layer.owner] = "base"
				end

				break
			end
		end
	end, {
		duringPlayback = field == "muted" or field == "solo" or field == "locked",
		structure = field ~= "muted" and field ~= "solo",
	})
end

function L.toggle(id, field)
	assert(field == "muted" or field == "solo" or field == "locked")

	return L.change(id, field, nil, true)
end

function L.move(id, direction)
	return transaction("Reorder animation layer", function(data)
		for i, layer in data.layers do
			if layer.id == id and i > 1 then
				local target = i + direction
				while
					target >= 2
					and target <= #data.layers
					and data.layers[target].owner ~= layer.owner
				do
					target += direction
				end

				if target >= 2 and target <= #data.layers then
					table.remove(data.layers, i)
					table.insert(data.layers, target, layer)
				end

				break
			end
		end
	end)
end

function L.remove(id)
	return transaction("Delete animation layer", function(data)
		for i, layer in data.layers do
			if layer.id == id and i > 1 then
				if data.activeByRig[layer.owner] == id then
					hideKeys(Raw)
					data.activeByRig[layer.owner] = "base"
				end

				table.remove(data.layers, i)
				break
			end
		end
	end)
end

function L.duplicate(id)
	return transaction("Duplicate animation layer", function(data)
		for _, layer in table.clone(data.layers) do
			if layer.id == id then
				local copy = clone(layer)
				copy.keys = {}
				for motor, bucket in layer.keys do
					if L.owner(motor) == data.master then
						copy.keys[motor] = clone(bucket)
					end
				end

				copy.owner = data.master
				copy.properties = {}
				if layer.properties[data.master] then
					copy.properties[data.master] = clone(layer.properties[data.master])
				end

				copy.id = Http:GenerateGUID(false)
				copy.name = layer.name .. " Copy"
				copy.locked = false
				table.insert(data.layers, copy)
				hideKeys(Raw)
				data.activeByRig[data.master] = copy.id
				break
			end
		end
	end)
end

function L.keyWeight(id)
	return transaction("Key layer weight", function(data)
		for _, layer in data.layers do
			if layer.id == id and id ~= "base" then
				local frame = math.round(Raw.CurrentTime * Raw.FPS)
				local weight = L.weight(layer, Raw.CurrentTime, Raw.FPS)
				layer.weightKeys = layer.weightKeys or {}
				if layer.weightKeys[frame] ~= nil then
					layer.weightKeys[frame] = nil
				else
					layer.weightKeys[frame] = weight
				end

				break
			end
		end
	end)
end

function L.reset(raw)
	raw.AnimationLayers = nil
	raw._LayerContext = nil
	notify()
end

function L.history(id, fn, master, activeByRig)
	if Raw.AnimationLayers and activeByRig then
		local data = L.ensure(Raw)
		data.activeByRig = table.clone(activeByRig)
		data.master = master or data.master
		L.rebuild(Raw)
		L.restoreActiveProperties()
	end

	if id and Raw.AnimationLayers then
		L.select(id, true)
	end

	local result = table.pack(fn())
	if Raw.AnimationLayers then
		L.refresh(false)
	end

	return table.unpack(result, 1, result.n)
end

function L.copySnapshot(data)
	local out = {
		scoped = true,
		master = data.master,
		active = data.active,
		activeByRig = table.clone(data.activeByRig or {}),
		layers = {},
	}
	for _, layer in data.layers do
		local row = { keys = {}, properties = {} }
		for k, v in layer do
			if k ~= "keys" and k ~= "properties" then
				row[k] = clone(v)
			end
		end

		for motor, bucket in layer.keys do
			row.keys[motor] = clone(bucket)
		end

		for rig, value in layer.properties or {} do
			row.properties[rig] = clone(value)
		end

		table.insert(out.layers, row)
	end

	return out
end

function L.restoreActiveProperties()
	local data = L.ensure(Raw)
	for _, rig in Main.getAllRigs() do
		local layer = forRig(data, rig)
		require("ArmatureAnimation").restoreProperties(
			rig,
			layer.properties[rig] or { version = 1, tracks = {} }
		)
	end
end

L.syncProperties = syncProperties

local function propertySample(track, frame)
	local previous, following = require("ArmatureAnimation").propertyBounds(track, frame)
	local value = track.default
	if previous then
		value = previous.value
	end

	if previous and following and type(value) == "number" then
		value += (following.value - value) * math.clamp(
			(frame - previous.frame) / (following.frame - previous.frame),
			0,
			1
		)
	end

	return value
end

local function propertyTracks(data, layer, rig)
	local snapshot = layer == forRig(data, rig) and require("ArmatureAnimation").propertyView(rig)
		or layer.properties[rig]
	if not evaluation then
		return snapshot and snapshot.tracks or {}
	end

	evaluation.properties = evaluation.properties or {}
	local byLayer = evaluation.properties[layer]
	if not byLayer then
		byLayer = {}
		evaluation.properties[layer] = byLayer
	end

	local entry = byLayer[rig]
	if not entry or entry.snapshot ~= snapshot then
		entry = { snapshot = snapshot, tracks = snapshot and snapshot.tracks or {}, byId = {} }
		for _, track in entry.tracks do
			if not entry.byId[track.id] then
				entry.byId[track.id] = track
			end
		end

		byLayer[rig] = entry
	end

	return entry.tracks, entry.byId
end

function L.propertyValue(rig, id, frame, desired)
	local data = L.ensure(Raw)
	local active = forRig(data, rig)
	local result, rest, descriptor
	local values = {}
	for i, layer in data.layers do
		local tracks, byId = propertyTracks(data, layer, rig)
		if byId then
			tracks = byId[id] and { byId[id] } or {}
		end

		for _, track in tracks do
			if track.id == id then
				descriptor = track
				rest = rest == nil and track.default or rest
				values[i] = propertySample(track, frame)
				break
			end
		end
	end

	if not descriptor then
		return desired
	end

	result = rest
	local index = table.find(data.layers, active)
	local before = rest
	local target = desired
	if desired ~= nil then
		if
			active.locked
			or not contributing(data, active, rig)
			or L.weight(active, frame / Raw.FPS, Raw.FPS) < 1e-5
		then
			return nil
		end

		for i = #data.layers, index + 1, -1 do
			local layer = data.layers[i]
			if values[i] ~= nil and contributing(data, layer, rig) then
				target = invert(
					target,
					values[i],
					rest,
					L.weight(layer, frame / Raw.FPS, Raw.FPS),
					layer.mode
				)
				if target == nil then
					return nil
				end
			end
		end
	end

	for i, layer in data.layers do
		if desired ~= nil and i == index then
			before = result
			break
		end

		if values[i] ~= nil and contributing(data, layer, rig) then
			local w = layer.id == "base" and 1 or L.weight(layer, frame / Raw.FPS, Raw.FPS)
			result = layer.mode == "Additive" and add(result, values[i], rest, w)
				or lerp(result, values[i], w)
		end
	end

	if desired ~= nil then
		return solve(
			before,
			target,
			rest,
			active.id == "base" and 1 or L.weight(active, frame / Raw.FPS, Raw.FPS),
			active.mode
		)
	end

	return result, descriptor
end

function L.applyProperties(rig, frame)
	return withEvaluation(function()
		local ids = {}
		local data = L.ensure(Raw)
		for _, layer in data.layers do
			for _, track in propertyTracks(data, layer, rig) do
				ids[track.id] = true
			end
		end

		for id in ids do
			local value, track = L.propertyValue(rig, id, frame)
			if value ~= nil and track then
				require("ArmatureRuntime").setProperty(
					rig,
					track.object,
					track.key,
					value,
					track.bone,
					true
				)
			end
		end
	end)
end

function L.withBaked(timeline, fn, scope)
	local raw = timeline:GetState()
	if not L.has(raw) then
		return fn()
	end

	L.ensure(raw)
	syncProperties(raw)
	local original = raw.Keyframes
	local baked = {}
	local frames = { [0] = true }
	local allTracks = L.allTracks(raw)
	if scope then
		local own = {}
		local external = scope:GetAttribute("EclipseTrackTarget") == true
		for motor, bucket in allTracks do
			if L.owner(motor) == scope then
				table.insert(own, motor)
				for _, key in bucket do
					if key.CamTargetParent or key.CamAttachTarget then
						external = true
					end
				end

				local parent = motor.Part0 and raw.MotorByPart[motor.Part0]
				if parent and L.owner(parent) ~= scope then
					external = true
				end
			end
		end

		if external or require("Mods").hasFor(own) then
			scope = nil
		end
	end

	local last = scope and 0 or timeline:GetLastKeyframeFrame() or 0
	for motor, bucket in allTracks do
		if scope and L.owner(motor) ~= scope then
			continue
		end

		for frame in bucket do
			frames[frame] = true
			last = math.max(last, frame)
		end
	end

	for _, layer in raw.AnimationLayers.layers do
		if scope and layer.id ~= "base" and layer.owner ~= scope then
			continue
		end

		for frame in layer.weightKeys or {} do
			frames[frame] = true
			last = math.max(last, frame)
		end

		for owner, props in layer.properties do
			if scope and owner ~= scope then
				continue
			end

			for _, track in props.tracks do
				for _, key in track.keys do
					last = math.max(last, key.frame)
				end
			end
		end
	end

	for _, clip in Physics.list(raw) do
		local relevant = not scope
		for motor in clip.tracks do
			if (clip.owners and clip.owners[motor] or clip.rig) == scope then
				relevant = true
				break
			end
		end

		if relevant then
			last = math.max(last, clip.last)
		end
	end

	for frame = 0, math.ceil(last) do
		frames[frame] = true
	end

	local propertyBake = {}
	for _, rig in scope and { scope } or Main.getAllRigs() do
		propertyBake[rig] = { version = 1, tracks = {} }
	end

	local sorted = {}
	for frame in frames do
		table.insert(sorted, frame)
	end

	table.sort(sorted)
	for _, frame in sorted do
		if Main.ProjectWorkStep then
			Main.ProjectWorkStep()
		end

		for motor, bucket in L.sampleTracks(timeline, frame / raw.FPS, scope) do
			baked[motor] = baked[motor] or {}
			local _, key = next(bucket)
			if key then
				key.Frame = frame
				baked[motor][frame] = key
			end
		end

		for rig, props in propertyBake do
			local ids = {}
			for _, layer in raw.AnimationLayers.layers do
				for _, track in layer.properties[rig] and layer.properties[rig].tracks or {} do
					ids[track.id] = true
				end
			end

			for id in ids do
				local value, descriptor = L.propertyValue(rig, id, frame)
				local track = props.tracks[id]
				if not track then
					track = clone(descriptor)
					track.keys = {}
					props.tracks[id] = track
				end

				table.insert(track.keys, { frame = frame, value = value })
			end
		end
	end

	raw._LayerBaked = true
	raw.Keyframes = baked
	local Animation = require("ArmatureAnimation")
	local ok, result = xpcall(function()
		for rig, props in propertyBake do
			local list = {}
			for _, track in props.tracks do
				table.insert(list, track)
			end

			props.tracks = list
			Animation.restoreProperties(rig, props)
		end

		return fn()
	end, debug.traceback)
	raw.Keyframes = original
	raw._LayerBaked = nil
	L.restoreActiveProperties()
	if not ok then
		error(result, 0)
	end

	return result
end

return L
