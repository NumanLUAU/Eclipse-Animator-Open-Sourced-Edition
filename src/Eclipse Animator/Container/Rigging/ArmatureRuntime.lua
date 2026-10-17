--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")
--!native
local HttpService = game:GetService("HttpService")
local M = require("M")
local Binding = require("Binding")
local Constraints = require("Constraints")
local Drivers = require("Drivers")
local Geometry = require("distance")
local Display = require("MeshDisplay")
local Skinning = require("Skinning")
local RigidGeometry = require("RigidGeometry")
local ObjectGeometry = require("ObjectGeometry")
local ArmatureData = require("ChunkStore")
local Visibility = require("ArmatureVisibility")
local BoneIK = require("BoneIK")
local Preferences = require("Preferences")
local MasterControl = require("MasterControl")
local RotationMode = require("cache")
local TimelineState = require("RawState").Timeline
local Runtime = {}
local interactiveDepth = 0
local samplingRigs = setmetatable({}, { __mode = "k" })

function Runtime.withSampling(rig, callback)
	Runtime.endDeferredEdit(rig)
	samplingRigs[rig] = (samplingRigs[rig] or 0) + 1
	local result = table.pack(xpcall(callback, debug.traceback))
	samplingRigs[rig] -= 1
	if samplingRigs[rig] == 0 then
		samplingRigs[rig] = nil
	end

	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

function Runtime.deferInteractive(callback)
	interactiveDepth += 1
	local result = table.pack(xpcall(callback, debug.traceback))
	interactiveDepth -= 1
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

local nextRevision = 0
local nextPropertyRevision = 0

local function propertiesChanged(entry)
	nextPropertyRevision += 1
	entry.propertyRevision = nextPropertyRevision
end

local entries = setmetatable({}, { __mode = "k" })
local deferredEdits = setmetatable({}, { __mode = "k" })

function Runtime.beginDeferredEdit(snapshots)
	if Preferences.get("DeferredArmatureUpdates") ~= true then
		return
	end

	for _, info in snapshots or {} do
		if info.edit then
			local rig = info.edit.rig
			deferredEdits[rig] = deferredEdits[rig] or {}
		end
	end
end

function Runtime.endDeferredEdit(rig)
	local pending = deferredEdits[rig]
	if not pending then
		return
	end

	deferredEdits[rig] = nil
	for node, old in pending do
		if node.anchor and node.anchor.Parent then
			node.anchor.CFrame = old
			Geometry.update(node.anchor, node.committedGeometry)
		end

		node.deferredWorld = nil
	end

	Runtime.evaluate(rig)
end

function Runtime.endDeferredEdits()
	local rigs = {}
	for rig in deferredEdits do
		table.insert(rigs, rig)
	end

	for _, rig in rigs do
		Runtime.endDeferredEdit(rig)
	end
end

local anchorEntries = setmetatable({}, { __mode = "k" })
local stableAdapters = setmetatable({}, { __mode = "k" })
local nativeEntries = setmetatable({}, { __mode = "k" })
local absent = setmetatable({}, { __mode = "k" })

local function dirty(entry)
	entry.inputRevision = (entry.inputRevision or 0) + 1
	entry.dirty = true
end

local function dispose(entry)
	if not entry or entry.disposed then
		return
	end

	entry.disposed = true
	if entries[entry.rig] == entry then
		entries[entry.rig] = nil
	end

	for _, connection in entry.connections or {} do
		connection:Disconnect()
	end

	Skinning.cleanup(entry.skinning)
	RigidGeometry.cleanup(entry.rigidGeometry)
	ObjectGeometry.cleanup(entry.objectGeometry)
	for _, node in entry.list do
		if node.anchor then
			anchorEntries[node.anchor] = nil
		end
	end

	for _, target in entry.targets do
		nativeEntries[target] = nil
	end
end

local WORLD = { 1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1 }

local function findArm(rig)
	for _, item in RigTraversal.rigDescendants(rig) do
		if item:IsA("Model") and item:FindFirstChild("EclipseArmatureGraph") then
			return item
		end
	end
end

local function objectName(target)
	return target.object or typeof(target.id) == "table" and (target.id.object or target.id.id)
end

local function propertyAt(entry, object, path)
	local bone, key = path:match('^pose%.bones%["(.-)"%]%.?%["(.-)"%]$')
	if bone then
		local node = entry.nodes[object .. "::" .. bone]
		return node and node.properties[key]
	end

	local field, index
	bone, field, index = path:match('^pose%.bones%["(.-)"%]%.([%w_]+)%[(%d+)%]$')
	if not bone then
		local channel
		bone, field, channel = path:match('^pose%.bones%["(.-)"%]%.([%w_]+)%.([xyzw])$')
		if channel then
			index = tostring((field == "rotation_quaternion" and { w = 0, x = 1, y = 2, z = 3 } or {
				x = 0,
				y = 1,
				z = 2,
			})[channel])
		end
	end

	local node = bone and entry.nodes[object .. "::" .. bone]
	if node then
		local basis = node.effectiveBasis or node.basis
		local channels = node.drivenChannels
		local values
		if field == "location" then
			values = (channels and channels.location or M.position(basis))
				/ (tonumber(entry.data.scale) or 1)
		elseif field == "scale" then
			values = channels and channels.scale or M.scale(basis)
		elseif field == "rotation_euler" then
			values = channels and channels.rotation_euler
				or M.euler(M.toCFrame(basis), node.data.rotation_mode)
		elseif field == "rotation_quaternion" then
			local axis, angle = M.toCFrame(basis):ToAxisAngle()
			local xyz = axis * math.sin(angle * 0.5)
			return ({ math.cos(angle * 0.5), xyz.X, xyz.Y, xyz.Z })[tonumber(index) + 1]
		end

		if values then
			return ({ values.X, values.Y, values.Z })[tonumber(index) + 1]
		end
	end

	key = path:match('^%["(.-)"%]$') or path:match("^%['(.-)'%]$")
	return key and entry.objects[object] and entry.objects[object].properties[key]
end

local function quaternionOf(matrix)
	local axis, angle = M.toCFrame(matrix).Rotation:ToAxisAngle()
	local half = angle * 0.5
	local w, x, y, z =
		math.cos(half), axis.X * math.sin(half), axis.Y * math.sin(half), axis.Z * math.sin(half)
	if w < 0 then
		return -w, -x, -y, -z
	end

	return w, x, y, z
end

local function transformChannel(matrix, field, mode, order, sourceScale)
	local kind, axis = field:sub(1, 3), field:sub(-1)
	if kind == "LOC" then
		return M.position(matrix)[axis] / sourceScale
	end

	if field == "SCALE_AVG" then
		local s = M.scale(matrix)
		local volume = s.X * s.Y * s.Z
		return math.sign(volume) * math.abs(volume) ^ (1 / 3)
	end

	if kind ~= "ROT" then
		return M.scale(matrix)[axis]
	end

	if mode == "QUATERNION" then
		local w, x, y, z = quaternionOf(matrix)
		return ({ W = w, X = x, Y = y, Z = z })[axis]
	end

	local twistAxis = mode:match("^SWING_TWIST_([XYZ])$")
	if twistAxis then
		local w, x, y, z = quaternionOf(matrix)
		local q = { X = x, Y = y, Z = z }
		local twist = 2 * math.atan2(q[twistAxis], w)
		if axis == twistAxis then
			return twist
		end

		local c, sn = math.cos(twist * 0.5), math.sin(twist * 0.5)
		local tw = { X = 0, Y = 0, Z = 0 }
		tw[twistAxis] = -sn
		local sw = w * c - (x * tw.X + y * tw.Y + z * tw.Z)
		local sx = w * tw.X + x * c + (y * tw.Z - z * tw.Y)
		local sy = w * tw.Y + y * c + (z * tw.X - x * tw.Z)
		local sz = w * tw.Z + z * c + (x * tw.Y - y * tw.X)
		local sign = sw < 0 and -1 or 1
		if axis == "W" then
			return 2 * math.acos(math.clamp(sw * sign, -1, 1))
		end

		return 2 * math.asin(math.clamp(({ X = sx, Y = sy, Z = sz })[axis] * sign, -1, 1))
	end

	if axis == "W" then
		return 0
	end

	local euler = mode
	if euler == "AUTO" then
		euler = order
	end

	if euler == nil or euler == "QUATERNION" or euler == "AXIS_ANGLE" then
		euler = "XYZ"
	end

	return M.euler(M.toCFrame(matrix), euler)[axis]
end

local function report(entry, issue)
	if not entry.reported[issue] then
		entry.reported[issue] = true
		table.insert(entry.diagnostics, issue)
	end
end

local function fittedMatrix(entry, matrix)
	return M.mul(entry.fitMatrix, M.translationScaled(matrix, entry.scale))
end

local function fitted(entry, matrix)
	return M.toCFrame(fittedMatrix(entry, matrix))
end

local function nativeState(binding)
	local target = binding.target
	return {
		cframe = target:IsA("BasePart") and target.CFrame,
		transform = target:IsA("Bone") and target.Transform,
		c0 = target:IsA("JointInstance") and target.C0,
		partFrame = binding.part and binding.part.CFrame,
		size = binding.part and binding.part.Size,
	}
end

local function restoreNativeState(binding)
	local target, state = binding.target, binding.committedNative
	if not state or not target.Parent then
		return
	end

	if state.cframe then
		target.CFrame = state.cframe
	end

	if state.transform then
		target.Transform = state.transform
	end

	if state.c0 then
		target.C0 = state.c0
	end

	if binding.part and binding.part.Parent then
		if state.partFrame then
			binding.part.CFrame = state.partFrame
		end

		if state.size then
			binding.part.Size = state.size
		end
	end
end

local function worldFrame(node)
	local source = node.committedWorld or node.initialWorld
	if node.frameSource ~= source or node.frameFit ~= node.entry.fitMatrix then
		if
			not node.frameSource
			or node.frameFit ~= node.entry.fitMatrix
			or M.error(node.frameSource, source) > 0
		then
			node.outputFrame = fitted(node.entry, source)
		end

		node.frameSource = source
		node.frameFit = node.entry.fitMatrix
	end

	return node.outputFrame
end

local function restoreStoredInputs(entry)
	for _, node in entry.list do
		if node.anchor then
			local c0 = node.anchor:GetAttribute("EclipseArmatureInputC0")
			local scale = node.anchor:GetAttribute("EclipseArmatureInputScale")
			if typeof(c0) == "CFrame" then
				local ok, basis = pcall(function()
					assert(
						M.isRigidCFrame(c0) and (scale == nil or M.isFiniteVector(scale)),
						"Invalid saved armature input"
					)
					local saved = node.anchor:GetAttribute("EclipseArmatureLastValidBasis")
					if
						typeof(saved) == "string"
						and c0 == node.anchor:GetAttribute("EclipseArmatureLastValidInputC0")
						and scale
							== node.anchor:GetAttribute("EclipseArmatureLastValidInputScale")
					then
						return M.readStrict(HttpService:JSONDecode(saved))
					end

					local localPose = M.compose(
						c0,
						typeof(scale) == "Vector3" and scale
							or M.scale(M.mul(node.restLocal, node.basis))
					)
					return M.mul(M.inverse(node.restLocal), localPose)
				end)
				if ok then
					node.basis = basis
				else
					local saved = node.anchor:GetAttribute("EclipseArmatureLastValidBasis")
					local restored, last = pcall(function()
						local value = HttpService:JSONDecode(saved)
						return M.readStrict(value)
					end)
					if restored then
						node.basis = last
					end

					local pose = M.mul(node.restLocal, node.basis)
					node.anchor:SetAttribute("EclipseArmatureInputC0", M.toCFrame(pose))
					node.anchor:SetAttribute("EclipseArmatureInputScale", M.scale(pose))
					report(entry, "Recovered invalid saved input for " .. node.id)
				end
			end
		end
	end
end

function Runtime.attach(arm, rig, data, fit, scale)
	require("Organization").registerArmatureCollections(arm, data)
	if not arm or not rig or typeof(data) ~= "table" or tonumber(data.version) < 4 then
		return nil
	end

	dispose(entries[rig])

	require("ArmatureConverter").restoreShapes(arm, data)
	local entry = {
		arm = arm,
		rig = rig,
		data = data,
		fit = fit or arm:GetAttribute("EclipseArmatureFit") or CFrame.identity,
		scale = scale or arm:GetAttribute("EclipseArmatureScale") or 1,
		nodes = {},
		list = {},
		objects = {},
		groups = {},
		drivers = {},
		diagnostics = {},
		reported = {},
		dirty = true,
		motors = {},
		targets = {},
		bindings = {},
		overrides = {},
	}
	entry.cycleParents = {}
	entry.cycleTargets = {}
	local schedule = data.evaluation_schedule
	entry.hasCycleSchedule = typeof(schedule) == "table" and schedule.version == 1
	if entry.hasCycleSchedule then
		for _, edge in schedule.cycle_breaks or {} do
			local from, to = edge.from, edge.to
			if
				typeof(from) == "table"
				and typeof(to) == "table"
				and typeof(from.bone) == "string"
				and typeof(to.bone) == "string"
			then
				if from.op == "BONE_DONE" and to.op == "BONE_POSE_PARENT" then
					entry.cycleParents[to.bone] = from.bone
				elseif from.op == "BONE_DONE" and to.op == "BONE_CONSTRAINTS" then
					entry.cycleTargets[to.bone] = entry.cycleTargets[to.bone] or {}
					entry.cycleTargets[to.bone][from.bone] = true
				else
					report(
						entry,
						"Unsupported cyclic evaluation link "
							.. tostring(from.op)
							.. " -> "
							.. tostring(to.op)
					)
				end
			end
		end
	end

	entry.masterMovement = MasterControl.movement(rig)
	local masterOrigin = arm:GetAttribute("EclipseArmatureMasterOrigin")
	if typeof(masterOrigin) ~= "CFrame" then
		masterOrigin = entry.masterMovement
		arm:SetAttribute("EclipseArmatureMasterOrigin", masterOrigin)
	end

	if entry.masterMovement ~= masterOrigin then
		entry.fit = (entry.masterMovement * masterOrigin:Inverse() * entry.fit):Orthonormalize()
	end

	entry.fitMatrix = M.fromCFrame(entry.fit)
	propertiesChanged(entry)
	entry.preparing = true
	entry.inputRevision = 0
	local visibility = Visibility.classify(data)
	local anchors = {}
	for _, anchor in arm:GetChildren() do
		local id = anchor:GetAttribute("EclipseArmatureBoneId")
		if typeof(id) == "string" and anchor:IsA("BasePart") then
			anchors[id] = anchor
		end
	end

	entry.armatureObjects = {}
	const armatureProperties = {}
	for _, armature in data.armatures or {} do
		if typeof(armature) == "table" and typeof(armature.name) == "string" then
			armatureProperties[armature.name] = armature.properties
			entry.armatureObjects[armature.data_name or armature.name] = armature.name
		end
	end

	for _, object in data.objects or {} do
		const defaults = table.clone(object.properties or {})
		for key, value in armatureProperties[object.name] or {} do
			if defaults[key] == nil then
				defaults[key] = value
			end
		end

		entry.objects[object.name] = {
			data = object,
			matrix = M.read(object.matrix),
			original = M.read(object.matrix),
			defaults = defaults,
			properties = table.clone(defaults),
		}
	end

	for _, bone in data.bones do
		local constraints = {}
		for _, constraint in bone.constraints or {} do
			local copy = table.clone(constraint)
			if constraint.targets then
				copy.targets = {}
				for _, target in constraint.targets do
					table.insert(copy.targets, table.clone(target))
				end
			end

			table.insert(constraints, copy)
		end

		local node = {
			id = bone.id,
			data = bone,
			entry = entry,
			anchor = anchors[bone.id],
			rest = M.read(bone.rest_matrix),
			restLocal = M.read(bone.rest_local_matrix),
			basis = M.read(bone.basis_matrix),
			properties = table.clone(bone.properties or {}),
			constraints = constraints,
		}
		node.defaultDisplay = Display.state(bone)
		node.visibility = visibility[bone.id]
		if node.anchor then
			node.anchor:SetAttribute("EclipseArmatureControl", node.visibility.control)
		end

		node.initialWorld = M.read(bone.pose_matrix)
		node.defaultScale = M.scale(node.basis)
		entry.nodes[node.id] = node
		table.insert(entry.list, node)
		if node.anchor then
			anchorEntries[node.anchor] = entry
			node.committedVisual = {
				cframe = node.anchor.CFrame,
				size = node.anchor.Size,
				pivot = node.anchor.PivotOffset,
				hidden = node.anchor:GetAttribute("Hidden"),
				canQuery = node.anchor.CanQuery,
			}
			local seenTargets = {}

			local function bind(target, offset, reference)
				if not target or seenTargets[target] or typeof(offset) ~= "CFrame" then
					return
				end

				seenTargets[target] = true
				nativeEntries[target] = entry
				node.target = node.target or target
				table.insert(entry.targets, target)
				local binding = {
					node = node,
					target = target,
					offset = M.fromCFrame(offset),
					reference = reference,
				}
				local part = target:IsA("JointInstance") and target.Part1
					or target:IsA("BasePart") and target
				if part then
					binding.part = part
					local saved = reference:GetAttribute("EclipseArmatureRestSize")
					binding.restSize = typeof(saved) == "Vector3" and saved or part.Size
					if not saved then
						reference:SetAttribute("EclipseArmatureRestSize", binding.restSize)
					end

					local rest = M.mul(fittedMatrix(entry, node.rest), binding.offset)
					if target:IsA("JointInstance") then
						rest = M.mul(rest, M.fromCFrame(target.C1:Inverse()))
					end

					binding.affineRest = rest
					binding.committedAffine = rest
					binding.restScale = M.scale(rest)
				end

				binding.committedNative = nativeState(binding)
				table.insert(entry.bindings, binding)
			end

			local target = node.anchor:FindFirstChild("EclipseArmatureTarget")
			if target and target:IsA("ObjectValue") and target.Value then
				bind(target.Value, node.anchor:GetAttribute("EclipseArmatureBindOffset"), target)
			end

			local copies = node.anchor:FindFirstChild("EclipseArmatureTargets")
			if copies then
				for _, copy in copies:GetChildren() do
					if copy:IsA("ObjectValue") then
						bind(copy.Value, copy:GetAttribute("BindOffset"), copy)
					end
				end
			end
		end
	end

	for _, node in entry.list do
		node.parent = entry.nodes[node.data.parent]
	end

	for _, node in entry.list do
		node.object = entry.objects[node.data.armature]
		if not node.object then
			error("Missing exported armature object " .. tostring(node.data.armature))
		end

		node.restObject = M.mul(M.inverse(node.object.original), node.rest)
		node.restRelative = node.parent and M.mul(M.inverse(node.parent.rest), node.rest)
		node.visualOwner = entry.nodes[node.data.visual_owner] or node
		if node.anchor then
			local visual = node.anchor:GetAttribute("EclipseArmatureVisualOffset")
			if typeof(visual) == "CFrame" then
				local original = node.anchor:GetAttribute("EclipseArmatureVisualRest")
				node.visualOriginal = M.fromCFrame(
					typeof(original) == "CFrame" and original
						or fitted(entry, M.read(node.data.pose_matrix)) * visual
				)
				node.visualInitialInverse =
					M.inverse(fittedMatrix(entry, M.read(node.visualOwner.data.pose_matrix)))
			end
		end

		for index, c in node.constraints do
			if c.type == "IK" then
				local chain = {}
				local cursor = node
				if c.type == "IK" and c.use_tail == false then
					cursor = node.parent
				end

				local count = tonumber(c.chain_count) or 0
				while cursor and (#chain < count or count == 0) do
					table.insert(chain, 1, cursor)
					cursor = cursor.parent
				end

				if #chain == 0 then
					continue
				end

				local group = { owner = node, constraint = c, index = index, chain = chain }
				table.insert(entry.groups, group)
				for _, member in chain do
					member.groups = member.groups or {}
					table.insert(member.groups, group)
				end
			end
		end
	end

	const followBone = Binding.followers(data)
	for name, object in entry.objects do
		const node = object.data.type == "ARMATURE" and entry.nodes[followBone(name) or ""]
		if node and node.object ~= object then
			object.follow =
				{ node = node, offset = M.mul(M.inverse(node.initialWorld), object.original) }
		end
	end

	entry.shapeKeys = {}
	for _, mesh in data.skin_meshes or {} do
		local keys = entry.shapeKeys[mesh.object] or {}
		entry.shapeKeys[mesh.object] = keys
		for _, key in mesh.shape_keys or {} do
			keys[key.name] =
				{ value = key.value or 0, min = key.min or 0, max = key.max or 1, mute = key.mute }
		end
	end

	for _, driver in data.drivers or {} do
		if driver.valid == false then
			continue
		end

		local prepared = Drivers.prepare(driver)
		local bone, constraint, constraintField =
			driver.data_path:match('^pose%.bones%["(.-)"%]%.constraints%["(.-)"%]%.([%w_]+)$')
		local weightBone, weightConstraint, weightIndex = driver.data_path:match(
			'^pose%.bones%["(.-)"%]%.constraints%["(.-)"%]%.targets%[(%d+)%]%.weight$'
		)
		if driver.scope and driver.scope.type == "SHAPE_KEYS" then
			local keys = entry.shapeKeys[driver.scope.object]
			local key = keys and keys[driver.shape_key]
			if key then
				prepared.kind, prepared.shapeKey = "shapeKey", key
				table.insert(entry.drivers, prepared)
			else
				report(entry, "Missing exported shape key " .. driver.data_path)
			end
		elseif weightBone and driver.scope then
			local node = entry.nodes[driver.scope.object .. "::" .. weightBone]
			local constraint
			if node then
				for _, c in node.constraints do
					if c.name == weightConstraint then
						constraint = c
						break
					end
				end
			end

			local target = constraint
				and constraint.targets
				and constraint.targets[tonumber(weightIndex) + 1]
			if target then
				prepared.node, prepared.kind, prepared.constraintObject, prepared.targetObject =
					node, "constraintTarget", constraint, target
				table.insert(entry.drivers, prepared)
			else
				report(entry, "Unsupported armature target driver " .. driver.data_path)
			end
		elseif bone and driver.scope then
			local node = entry.nodes[driver.scope.object .. "::" .. bone]
			local target
			if node then
				for _, candidate in node.constraints do
					if candidate.name == constraint then
						target = candidate
						break
					end
				end
			end

			if
				target
				and (typeof(target[constraintField]) == "number" or typeof(target[constraintField]) == "boolean")
				and constraintField ~= "chain_count"
			then
				prepared.node, prepared.constraint, prepared.kind = node, constraint, "constraint"
				prepared.constraintObject, prepared.field = target, constraintField
				prepared.boolean = typeof(target[constraintField]) == "boolean"
				table.insert(entry.drivers, prepared)
			else
				report(entry, "Unsupported constraint driver " .. driver.data_path)
			end
		elseif driver.scope and driver.valid ~= false then
			local field
			bone, field = driver.data_path:match('^pose%.bones%["(.-)"%]%.([%w_]+)$')
			if not bone then
				bone, field = driver.data_path:match('^bones%["(.-)"%]%.([%w_]+)$')
			end

			local node = bone and entry.nodes[driver.scope.object .. "::" .. bone]
			if
				node
				and (
					field == "hide"
					or field == "hide_select"
					or field == "use_inherit_rotation"
					or field == "location"
					or field == "scale"
					or field == "rotation_euler"
					or field == "rotation_quaternion"
					or field == "custom_shape_scale_xyz"
					or field == "custom_shape_translation"
					or field == "custom_shape_rotation_euler"
				)
			then
				prepared.node, prepared.field, prepared.kind = node, field, "channel"
				table.insert(entry.drivers, prepared)
				if field:sub(1, 13) == "custom_shape_" then
					node.hasDisplayDrivers = true
				end
			elseif
				not bone
				and (driver.data_path == "hide_viewport" or driver.data_path == "hide_render")
			then
				prepared.object, prepared.field, prepared.kind =
					entry.objects[driver.scope.object], driver.data_path, "objectVisibility"
				table.insert(entry.drivers, prepared)
			else
				report(
					entry,
					"Unsupported driver output " .. driver.scope.object .. " / " .. driver.data_path
				)
			end
		end
	end

	entry.usesFrame = false
	for _, driver in entry.drivers do
		if not driver.mute and Drivers.usesFrame(driver) then
			entry.usesFrame = true
		end
	end

	local incoming = {}
	for _, binding in entry.bindings do
		local target = binding.target
		if target:IsA("JointInstance") and target.Part1 then
			incoming[target.Part1] = target
		end
	end

	local depths, visiting = {}, {}

	local function depth(target)
		if depths[target] then
			return depths[target]
		end

		if visiting[target] then
			return 0
		end

		visiting[target] = true

		local parent
		if target:IsA("JointInstance") then
			parent = target.Part0
		elseif target:IsA("BasePart") then
			parent = incoming[target] or target.Parent
		else
			parent = target.Parent
		end

		local value = parent and parent ~= rig and depth(parent) + 1 or 0
		visiting[target] = nil
		depths[target] = value
		return value
	end

	table.sort(entry.bindings, function(a, b)
		return depth(a.target) < depth(b.target)
	end)
	local storedProperties = arm:FindFirstChild("EclipseArmaturePropertyValues")
	if storedProperties then
		local ok, properties =
			pcall(HttpService.JSONDecode, HttpService, ArmatureData.read(storedProperties))
		if ok and typeof(properties) == "table" then
			for _, property in properties do
				local owner = property.bone
						and entry.nodes[property.object .. "::" .. property.bone]
					or entry.objects[property.object]
				if owner and owner.properties[property.key] ~= nil then
					owner.properties[property.key] = property.value
					entry.overrides[HttpService:JSONEncode({
						property.object,
						property.bone or "",
						property.key,
					})] =
						property
				end
			end
		end
	end

	entries[rig] = entry
	entry.connections = {
		arm.Destroying:Connect(function()
			dispose(entry)
		end),
		rig.Destroying:Connect(function()
			dispose(entry)
		end),
	}
	if absent[rig] then
		absent[rig]:Disconnect()
		absent[rig] = nil
	end

	restoreStoredInputs(entry)
	for _, node in entry.list do
		node.c0 = M.toCFrame(M.translationScaled(M.mul(node.restLocal, node.basis), entry.scale))
	end

	local prepared, issue = pcall(function()
		local skinning = Skinning.attach(entry)
		if entry.disposed then
			Skinning.cleanup(skinning)
			return
		end

		entry.skinning = skinning
		for _, message in skinning.diagnostics do
			report(entry, message)
		end

		entry.rigidGeometry = RigidGeometry.attach(entry)
		entry.objectGeometry = ObjectGeometry.attach(entry)
		for _, message in entry.objectGeometry.diagnostics do
			report(entry, message)
		end
	end)
	entry.preparing = false
	if not prepared then
		dispose(entry)
		entries[rig] = nil
		error(issue)
	end

	if entry.disposed then
		return nil
	end

	for _, node in entry.list do
		local cached = node.anchor and stableAdapters[node.anchor]
		if cached and cached.rig == rig then
			cached.bind(node, entry)
		end
	end

	return entry
end

local function getEntry(rig)
	if not rig then
		return nil
	end

	local entry = entries[rig]
	if entry and not entry.disposed and entry.arm:IsDescendantOf(rig) then
		return entry
	end

	if entry then
		dispose(entry)
		entries[rig] = nil
	end

	if absent[rig] then
		return nil
	end

	local arm = rig and findArm(rig)
	if not arm then
		if rig then
			local connection
			connection = rig.DescendantAdded:Connect(function(item)
				if item.Name == "EclipseArmatureGraph" or item:GetAttribute("EclipseArmature") then
					absent[rig] = nil
					connection:Disconnect()
				end
			end)
			absent[rig] = connection
		end

		return nil
	end

	local value = arm:FindFirstChild("EclipseArmatureGraph")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, ArmatureData.read(value))
	if not ok then
		return nil
	end

	return Runtime.attach(arm, rig, data)
end

function Runtime.isRig(rig)
	return getEntry(rig) ~= nil
end

function Runtime.isAnchor(anchor)
	return typeof(anchor) == "Instance"
		and typeof(anchor:GetAttribute("EclipseArmatureBoneId")) == "string"
end

function Runtime.isDriven(target)
	local entry = nativeEntries[target]
	return entry ~= nil and entry.arm:IsDescendantOf(entry.rig)
end

local function objectInverse(object)
	if object.inverseSource ~= object.matrix then
		object.inverseMatrix = M.inverse(object.matrix)
		object.inverseSource = object.matrix
	end

	return object.inverseMatrix
end

local function parentWorldFor(node)
	local parent = node.parent
	return node.laggedParent and (parent.constraintPrevious or parent.initialWorld) or parent.world
end

local function basisFor(entry, node)
	if node.rotationOverride ~= nil then
		node.inheritRotation = node.rotationOverride
	end

	local parent = node.parent
	if not parent then
		return M.mul(node.object.matrix, node.restObject)
	end

	local parentWorld = parentWorldFor(node)
	local relative = node.restRelative
	local parentBasis = parentWorld
	local inherit = node.data.inherit_scale or "FULL"
	if inherit == "FULL" and node.inheritRotation ~= false then
		local result = M.mul(parentWorld, relative)
		node.locationBase = result
		return result
	end

	local parentPose = (inherit ~= "FULL" or node.inheritRotation == false)
		and M.mul(objectInverse(parent.object), parentWorld)
	if inherit == "NONE_LEGACY" then
		parentBasis = M.mul(parent.object.matrix, M.normalizedColumns(parentPose))
	elseif inherit == "NONE" then
		parentBasis = M.mul(parent.object.matrix, M.orthogonalizedY(parentPose))
	elseif inherit == "AVERAGE" then
		local s = M.scale(parentPose)
		parentBasis = M.mul(
			parent.object.matrix,
			M.compose(M.toCFrame(parentPose), Vector3.one * math.abs(s.X * s.Y * s.Z) ^ (1 / 3))
		)
	elseif inherit == "FIX_SHEAR" or inherit == "ALIGNED" then
		parentBasis =
			M.mul(parent.object.matrix, M.compose(M.toCFrame(parentPose), M.scale(parentPose)))
	end

	local result = M.mul(parentBasis, relative)

	node.locationBase = M.mul(parentWorld, relative)
	result = M.withPosition(result, M.position(node.locationBase))
	if node.inheritRotation == false then
		local restParent = parent.restObject
		local inheritedScale = (inherit == "NONE" or inherit == "NONE_LEGACY") and Vector3.one
			or M.scale(parentPose)
		local rotationParent = M.compose(M.toCFrame(restParent), inheritedScale)
		local rotationBase = M.mul(M.mul(parent.object.matrix, rotationParent), relative)
		node.locationBase = M.mul(parentWorld, relative)
		result = M.withPosition(rotationBase, M.position(node.locationBase))
	end

	return result
end

local function applyBasis(node)
	local basis = node.effectiveBasis or node.basis
	local world = M.mul(node.base, basis)
	if node.locationBase then
		world = M.withPosition(world, M.point(node.locationBase, M.position(basis)))
	end

	if node.data.connected then
		world = M.withPosition(world, M.position(node.base))
	end

	if node.data.local_location == false then
		local parent = node.parent and parentWorldFor(node) or node.object.matrix
		world = M.withPosition(world, M.position(node.base) + M.vector(parent, M.position(basis)))
	end

	return world
end

local function writeInput(node, preparedPose, preparedFrame)
	local localPose = preparedPose or M.mul(node.restLocal, node.basis)
	assert(M.isFinite(localPose), "Invalid authored armature pose")
	node.c0 = preparedFrame or M.toCFrame(M.translationScaled(localPose, node.entry.scale))
	if not node.anchor then
		return
	end

	local inputFrame = if preparedFrame
		then preparedFrame.Rotation + M.position(localPose)
		else M.toCFrame(localPose)
	node.anchor:SetAttribute("EclipseArmatureInputC0", inputFrame)
	node.anchor:SetAttribute("EclipseArmatureInputScale", M.scale(localPose))
end

local function rememberInput(node)
	local entry = node.entry
	entry.pendingInputs = entry.pendingInputs or {}
	if not entry.pendingInputs[node] then
		entry.pendingInputs[node] = {
			basis = node.basis,
			c0 = node.c0,
			lastC0Input = node.lastC0Input,
			lastScaleInput = node.lastScaleInput,
			properties = table.clone(node.properties),
		}
	end
end

local function setNodeBasis(node, basis, c0, scaleInput)
	local ok, result, localPose = pcall(function()
		assert(M.isFinite(basis), "Invalid armature input")
		local localPose = M.mul(node.restLocal, basis)
		local frame = M.toCFrame(M.translationScaled(localPose, node.entry.scale))
		return frame, localPose
	end)
	if not ok then
		report(node.entry, "Rejected input for " .. node.id .. ": " .. tostring(result))
		return false
	end

	rememberInput(node)
	node.basis = basis
	node.lastC0Input = c0
	node.lastScaleInput = scaleInput
	writeInput(node, localPose, result)

	if c0 then
		node.c0 = c0:Orthonormalize()
	end

	dirty(node.entry)
	return true
end

function Runtime.setBasis(rig, id, basis)
	local entry = getEntry(rig)
	local node = entry and entry.nodes[id]
	if not node then
		return false
	end

	local ok, parsed = pcall(M.readStrict, basis)
	if not ok then
		report(entry, "Rejected invalid basis for " .. id)
		return false
	end

	return setNodeBasis(node, parsed)
end

function Runtime.setProperty(rig, object, key, value, boneName, transient)
	local entry = getEntry(rig)
	if not entry then
		return false
	end

	local owner = boneName and entry.nodes[object .. "::" .. boneName] or entry.objects[object]
	if not owner then
		return false
	end

	if owner.properties[key] == value then
		return true
	end

	if typeof(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
		return false
	end

	if owner.entry then
		rememberInput(owner)
	else
		entry.pendingObjects = entry.pendingObjects or {}
		if not entry.pendingObjects[owner] then
			entry.pendingObjects[owner] =
				{ matrix = owner.matrix, properties = table.clone(owner.properties) }
		end
	end

	owner.properties[key] = value
	dirty(entry)
	propertiesChanged(entry)
	if transient then
		return true
	end

	entry.pendingOverrides = entry.pendingOverrides or table.clone(entry.overrides)
	entry.overrides[HttpService:JSONEncode({ object, boneName or "", key })] =
		{ object = object, bone = boneName, key = key, value = value }
	local records = {}
	for _, record in entry.overrides do
		table.insert(records, record)
	end

	local previous = entry.arm:FindFirstChild("EclipseArmaturePropertyValues")
	if previous then
		previous:Destroy()
	end

	ArmatureData.write(entry.arm, "EclipseArmaturePropertyValues", HttpService:JSONEncode(records))
	return true
end

function Runtime.propertyRevision(rig)
	local entry = entries[rig]
	return entry and not entry.disposed and entry.propertyRevision or 0
end

function Runtime.properties(rig)
	local entry = getEntry(rig)
	local out = {}
	if not entry then
		return out
	end

	local function append(owner, object, bone)
		for key, value in owner.properties do
			if typeof(value) == "number" or typeof(value) == "boolean" then
				table.insert(out, {
					object = object,
					bone = bone,
					key = key,
					value = value,
					default = (owner.defaults or owner.data.properties or {})[key],
				})
			end
		end
	end

	for name, object in entry.objects do
		append(object, name)
	end

	for _, node in entry.list do
		append(node, node.data.armature, node.data.name)
	end

	table.sort(out, function(a, b)
		return a.object .. (a.bone or "") .. a.key < b.object .. (b.bone or "") .. b.key
	end)
	return out
end

function Runtime.setObjectMatrix(rig, object, matrix)
	local entry = getEntry(rig)
	local owner = entry and entry.objects[object]
	if not owner then
		return false
	end

	local ok, parsed = pcall(M.readStrict, matrix)
	if not ok then
		return false
	end

	entry.pendingObjects = entry.pendingObjects or {}
	if not entry.pendingObjects[owner] then
		entry.pendingObjects[owner] =
			{ matrix = owner.matrix, properties = table.clone(owner.properties) }
	end

	owner.matrix = parsed
	dirty(entry)
	return true
end

function Runtime.reset(rig)
	local entry = getEntry(rig)
	if not entry then
		return
	end

	for _, node in entry.list do
		rememberInput(node)
		node.basis = M.read(node.data.basis_matrix)
		node.lastC0Input, node.lastScaleInput = nil, nil
		node.properties = table.clone(node.data.properties or {})
		writeInput(node)
	end

	entry.pendingObjects = entry.pendingObjects or {}
	for _, object in entry.objects do
		if not entry.pendingObjects[object] then
			entry.pendingObjects[object] =
				{ matrix = object.matrix, properties = table.clone(object.properties) }
		end

		object.matrix = table.clone(object.original)
		object.properties = table.clone(object.defaults)
	end

	entry.pendingOverrides = entry.pendingOverrides or table.clone(entry.overrides)
	table.clear(entry.overrides)
	local values = entry.arm:FindFirstChild("EclipseArmaturePropertyValues")
	if values then
		values:Destroy()
	end

	propertiesChanged(entry)
	dirty(entry)
	for _, node in entry.list do
		node.constraintPrevious = node.initialWorld
	end

	entry.constraintRevision = entry.inputRevision
end

local function sameMatrix(a, b)
	if not a or not b then
		return false
	end

	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

local function sameDisplay(a, b)
	return a == b
		or a
			and b
			and a.custom_shape_scale_xyz == b.custom_shape_scale_xyz
			and a.custom_shape_translation == b.custom_shape_translation
			and a.custom_shape_rotation_euler == b.custom_shape_rotation_euler
end

local function sameInput(a, b)
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return a == b
	end

	for key, value in a do
		if not sameInput(value, b[key]) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

function Runtime.evaluate(rig, force)
	if deferredEdits[rig] then
		if
			not force
			and not samplingRigs[rig]
			and Preferences.get("DeferredArmatureUpdates") == true
		then
			return false
		end

		Runtime.endDeferredEdit(rig)
	end

	if interactiveDepth > 0 and not force then
		return false
	end

	local entry = getEntry(rig)
	if not entry or entry.disposed or entry.preparing or entry.evaluating then
		return false
	end

	local repaired = not samplingRigs[rig] and Geometry.repair(entry.arm)
	local pendingPresentation = not samplingRigs[rig] and entry.sampledPresentation
	local movement = MasterControl.movement(rig)
	if movement ~= entry.masterMovement then
		entry.fit = (movement * entry.masterMovement:Inverse() * entry.fit):Orthonormalize()
		entry.fitMatrix = M.fromCFrame(entry.fit)
		entry.masterMovement = movement
		dirty(entry)
	end

	if entry.rotationRevision ~= RotationMode.revision() then
		entry.rotationRevision = RotationMode.revision()
		dirty(entry)
	end

	local presentationOnly = not force and not entry.dirty and pendingPresentation
	if pendingPresentation then
		entry.dirty = true
	end

	if not force and not entry.dirty then
		return repaired == true
	end

	entry.evaluating = true
	local inputRevision = entry.inputRevision
	if entry.constraintRevision ~= inputRevision then
		for _, node in entry.list do
			node.constraintPrevious = node.committedWorld or node.initialWorld
		end

		entry.constraintRevision = inputRevision
	end

	local previousShapes = {}
	for _, keys in entry.shapeKeys do
		for _, key in keys do
			previousShapes[key] = key.value
		end
	end

	local function run()
		if not presentationOnly then
			local evaluateNode, solveGroup
			local driverValues = {}
			for _, object in entry.objects do
				object.hide_viewport = object.data.hide_viewport == true
				object.followed = nil
			end

			for _, node in entry.list do
				node.status = nil
				node.world = nil
				node.base = nil
				node.locationBase = nil
				node.laggedParent = entry.hasCycleSchedule
						and node.parent
						and entry.cycleParents[node.id] == node.parent.id
					or false
				if not entry.hasCycleSchedule then
					for _, c in node.parent and node.parent.constraints or {} do
						if
							c.type == "DAMPED_TRACK"
							and c.target_id == node.id
							and c.enabled ~= false
							and not c.mute
							and (tonumber(c.influence) or 1) > 0
						then
							node.laggedParent = true
							break
						end
					end
				end

				node.effectiveBasis = node.basis
				node.drivenChannels = nil
				node.inheritRotation = node.data.inherit_rotation
				node.rotationOverride = nil
				if node.adapter then
					local value, found = RotationMode.authored(
						node.adapter,
						TimelineState.Keyframes[node.adapter],
						entry.time or 0
					)
					if found then
						node.rotationOverride = value
					end
				end

				node.hidden = node.visibility.boneHidden
				node.unselectable = node.visibility.unselectable
				node.display = node.defaultDisplay
					and (
						node.hasDisplayDrivers and table.clone(node.defaultDisplay)
						or node.defaultDisplay
					)
			end

			for _, group in entry.groups do
				group.status = nil
			end

			entry.constraintCache = entry.constraintCache or {}
			entry.constraintRevisions = entry.constraintRevisions or {}
			local ctx = {
				worldSpace = WORLD,
				sourceScale = tonumber(entry.data.scale) or 1,
				constraintCache = entry.constraintCache,
				constraintRevisions = entry.constraintRevisions,
			}
			local inverses = {}
			ctx.inverse = function(matrix)
				local inverse = inverses[matrix]
				if not inverse then
					inverse = M.inverse(matrix)
					inverses[matrix] = inverse
				end

				return inverse
			end

			ctx.unsupported = function(node, c, detail)
				report(entry, node.id .. " / " .. c.name .. ": " .. detail)
			end

			ctx.influence = function(node, c)
				local values = driverValues[node]
				return values and values[c.name] or tonumber(c.influence) or 1
			end

			local function readVariable(variable)
				local t = (variable.targets or {})[1]
				if not t then
					return nil
				end

				local object = objectName(t)
				if t.id_type == "ARMATURE" then
					object = entry.armatureObjects[object] or object
				end

				if variable.type == "SINGLE_PROP" then
					local value = propertyAt(entry, object, t.data_path or "")
					if value ~= nil then
						return value
					end

					report(
						entry,
						"Unsupported driver property "
							.. tostring(object)
							.. " / "
							.. tostring(t.data_path)
					)
				elseif variable.type == "TRANSFORMS" then
					local node = entry.nodes[t.target_id or (tostring(object) .. "::" .. tostring(
						t.bone_target
					))]
					local objectEntry = not node and entry.objects[object]
					if node or objectEntry then
						local matrix, order
						if node then
							matrix = node.effectiveBasis or node.basis
							if t.transform_space == "WORLD_SPACE" then
								matrix = M.mul(M.inverse(WORLD), evaluateNode(node))
							elseif t.transform_space == "LOCAL_SPACE" then
								local world = evaluateNode(node)
								matrix = M.mul(M.inverse(node.base), world)
							end

							order = node.data.rotation_mode
						else
							local basis = objectEntry.data.matrix_basis
							matrix = if t.transform_space ~= "WORLD_SPACE"
									and typeof(basis) == "table"
									and #basis == 16
								then M.read(basis)
								else M.mul(M.inverse(WORLD), objectEntry.matrix)
							order = objectEntry.data.rotation_mode
						end

						return transformChannel(
							matrix,
							t.transform_type or "LOC_X",
							t.rotation_mode or "AUTO",
							order,
							tonumber(entry.data.scale) or 1
						)
					end
				else
					report(entry, "Unsupported driver variable type " .. tostring(variable.type))
				end

				if t.evaluated_value ~= nil then
					return t.evaluated_value
				end

				return t.use_fallback_value and t.fallback_value or nil
			end

			local function targetOf(c, owner)
				local node = entry.nodes[c.target_id]
				if node then
					local delayed = owner
						and entry.cycleTargets[owner.id]
						and entry.cycleTargets[owner.id][node.id]
					local world = delayed and node.constraintPrevious or evaluateNode(node)
					local offset = (tonumber(c.head_tail) or 0) * (tonumber(node.data.length) or 0)
					if offset ~= 0 then
						world = M.withPosition(world, M.point(world, Vector3.new(0, offset, 0)))
					end

					return node, world, node.data.rotation_mode
				end

				local name = c.target and (c.target.object or c.target.id)
				local object = entry.objects[name]
				return nil, object and object.matrix, object and object.data.rotation_mode
			end

			ctx.target = targetOf
			ctx.space = function(node, space, c)
				if space == "CUSTOM" then
					local custom = entry.nodes[c.space_target_id]
					if custom then
						return evaluateNode(custom)
					end

					local name = c.space_object and (c.space_object.object or c.space_object.id)
					return entry.objects[name] and entry.objects[name].matrix or WORLD
				end

				if not node or space == nil or space == "WORLD" then
					return WORLD
				end

				if space == "POSE" then
					return node.object.matrix
				end

				if space == "LOCAL_WITH_PARENT" then
					return M.mul(node.object.matrix, node.restObject)
				end

				if space == "LOCAL" or space == "LOCAL_OWNER_ORIENT" then
					if not node.base then
						if node.parent then
							evaluateNode(node.parent)
						end

						node.base = basisFor(entry, node)
					end

					return node.base
				end

				return WORLD
			end

			local function applyConstraints(node, world, first, last)
				for i = first or 1, last or #node.constraints do
					world = Constraints.apply(ctx, node, world, node.constraints[i])
					node.world = world
				end

				return world
			end

			local function connectedHead(node, world)
				if node.data.connected and node.parent then
					return M.withPosition(
						world,
						M.point(parentWorldFor(node), Vector3.new(0, node.parent.data.length, 0))
					)
				end

				return world
			end

			local function preNode(node, group)
				if node.parent then
					evaluateNode(node.parent, group)
				end

				node.base = basisFor(entry, node)
				local world = applyBasis(node)
				node.world = world
				local last = group.ends and group.ends[node] and group.ends[node].index - 1
					or node == group.owner and group.index - 1
					or #node.constraints
				local input = applyConstraints(node, world, 1, last)
				node.editWorld = input
				return input
			end

			solveGroup = function(group)
				if group.sharedGroup then
					return solveGroup(group.sharedGroup)
				end

				if group.status == "done" then
					return
				end

				if group.status == "running" then
					return
				end

				group.status = "running"
				local chain = {}
				local relative = {}
				local indices = {}
				for i, node in group.chain do
					indices[node] = i
				end

				local objectMatrix = group.owner.object.matrix
				local objectInverse = objectInverse(group.owner.object)
				local solverRoot, solverInverse

				local function normalizedColumns(matrix)
					local result = M.withPosition(matrix, Vector3.zero)
					for column = 1, 3 do
						local length = M.column(result, column).Magnitude
						if length > 1e-15 then
							result[column] /= length
							result[column + 4] /= length
							result[column + 8] /= length
						end
					end

					return result
				end

				local function rawFrame(matrix)
					return CFrame.new(
						0,
						0,
						0,
						matrix[1],
						matrix[2],
						matrix[3],
						matrix[5],
						matrix[6],
						matrix[7],
						matrix[9],
						matrix[10],
						matrix[11]
					)
				end

				for i, node in group.chain do
					node.status = "running"
					local world = preNode(node, group)
					local pose = M.mul(objectInverse, world)
					local parentPose = node.parent and M.mul(objectInverse, node.parent.world)
						or M.identity()
					relative[i] = M.mul(M.inverse(parentPose), pose)
					local parentRotation = normalizedColumns(parentPose)
					local poseRotation = normalizedColumns(pose)
					if i == 1 then
						solverRoot = M.withPosition(parentRotation, M.position(pose))
						solverInverse = M.inverse(solverRoot)
					end

					local restRotation =
						M.withPosition(node.restRelative or node.restObject, Vector3.zero)
					local inverseParent = M.inverse(parentRotation)
					local sourceBasis =
						M.mul(M.inverse(restRotation), M.mul(inverseParent, poseRotation))
					local start = Vector3.zero
					if i > 1 then
						local parentTail = M.position(parentPose)
							+ M.column(parentPose, 2) * (tonumber(node.parent.data.length) or 0)
						start = M.vector(inverseParent, M.position(pose) - parentTail)
					end

					chain[i] = {
						head = M.point(solverInverse, M.position(pose)),
						rot = rawFrame(M.mul(solverInverse, poseRotation)),
						solverRestBasis = rawFrame(restRotation),
						solverBasis = rawFrame(sourceBasis),
						solverStart = start,
						length = (tonumber(node.data.length) or 0) * M.column(pose, 2).Magnitude,
						minStretchLength = 0.001 * (tonumber(entry.data.scale) or 1),
						solverParent = group.members and (indices[node.parent] or 0) or nil,
					}
				end

				local c = group.constraint
				local _, target = targetOf(c)
				local influence = ctx.influence(group.owner, c)
				if target and influence > 0 and c.enabled ~= false and not c.mute then
					local pole = entry.nodes[c.pole_target_id]
					local polePosition = pole
						and M.point(
							solverInverse,
							M.point(objectInverse, M.position(evaluateNode(pole)))
						)
					local weights, stretchWeights = {}, {}
					for i, node in group.chain do
						local ik = node.data.ik_settings or node.data.ik or {}
						local stretch = tonumber(ik.ik_stretch or node.data.ik_stretch) or 0
						stretchWeights[i] = c.use_stretch
								and stretch > 0
								and math.clamp(stretch * stretch, 0.01, 1)
							or 0
						local unlocked, hinge = 0, nil
						for d, axis in { "x", "y", "z" } do
							local lock = ik["lock_ik_" .. axis] or node.data["lock_ik_" .. axis]
							local stiffness = tonumber(
								ik["ik_stiffness_" .. axis] or node.data["ik_stiffness_" .. axis]
							) or 0
							weights[(i - 1) * 3 + d] = lock and 0
								or 1 - math.clamp(stiffness, 0, 0.99)
							if not lock then
								unlocked += 1
								hinge = d
							end
						end

						if unlocked == 1 then
							chain[i].solverHinge = hinge
						end
					end

					local goal = M.point(solverInverse, M.point(objectInverse, M.position(target)))
					local angle, iterations =
						tonumber(c.pole_angle) or 0, tonumber(c.iterations) or 500
					local soft = 100

					local goals
					if group.members then
						goals = {}
						for _, member in group.members do
							local _, matrix = targetOf(member.constraint)
							if matrix then
								goals[#goals + 1] = {
									index = indices[member.owner],
									position = M.point(
										solverInverse,
										M.point(objectInverse, M.position(matrix))
									),
								}
							end
						end
					end

					local inputs = {
						chain,
						goal,
						polePosition or false,
						angle,
						iterations,
						weights,
						influence,
						stretchWeights,
						soft,
						goals or false,
					}
					local solution = group.solution
					if not solution or not sameInput(inputs, group.solutionInputs) then
						solution = goals
								and BoneIK.solveRigidTree(chain, goals, iterations, weights)
							or BoneIK.solveRigidChain(
								chain,
								goal,
								polePosition,
								angle,
								iterations,
								weights,
								influence,
								stretchWeights,
								soft
							)
						group.solutionInputs, group.solution = inputs, solution
					end

					local function columnLength(matrix, index, length)
						local current = M.column(matrix, index).Magnitude
						local factor = current > 1e-15 and length / current or 0
						matrix[index] *= factor
						matrix[index + 4] *= factor
						matrix[index + 8] *= factor
					end

					for i, node in group.chain do
						local parentPose = node.parent and M.mul(objectInverse, node.parent.world)
							or M.identity()
						local posed = M.mul(parentPose, relative[i])
						local originalScale = M.scale(posed)
						local delta = solution[i].delta
						if not delta then
							local before = i == 1 and chain[i].rot
								or chain[i - 1].rot:Inverse() * chain[i].rot
							local after = i == 1 and solution[i].rot
								or solution[i - 1].rot:Inverse() * solution[i].rot
							delta = before:Inverse() * after
						end

						local parentIndex = group.members and (indices[node.parent] or 0) or i - 1
						local parentStretch = parentIndex > 0
								and (solution[parentIndex].stretch or 1)
							or 1
						local stretch = parentStretch ~= 0
								and (solution[i].stretch or 1) / parentStretch
							or 1
						local blend = solution[i].resultInfluence
							or (polePosition and influence or 1)
						stretch = 1 + (stretch - 1) * blend

						columnLength(posed, 1, originalScale.Y)
						columnLength(posed, 3, originalScale.Y)
						local deltaMatrix = solution[i].deltaMatrix
								and table.clone(solution[i].deltaMatrix)
							or M.fromCFrame(delta)
						for column = 1, 3 do
							deltaMatrix[column] *= stretch
							deltaMatrix[column + 4] *= stretch
							deltaMatrix[column + 8] *= stretch
						end

						posed = M.mul(posed, deltaMatrix)
						columnLength(posed, 1, originalScale.X * M.column(deltaMatrix, 1).Magnitude)
						columnLength(posed, 3, originalScale.Z * M.column(deltaMatrix, 3).Magnitude)
						node.world = M.mul(objectMatrix, posed)
					end
				end

				for _, node in group.chain do
					node.status = "done"
				end

				group.status = "done"
				for _, member in group.members or { group } do
					member.status = "done"
					if member.constraint.use_tail == false then
						member.owner.world = preNode(member.owner, member)
					end

					member.owner.world = connectedHead(
						member.owner,
						applyConstraints(member.owner, member.owner.world, member.index + 1)
					)
				end
			end

			local function followObject(object)
				const follow = object.follow
				if follow and not object.followed then
					object.followed = true
					object.matrix = M.mul(evaluateNode(follow.node), follow.offset)
				end
			end

			evaluateNode = function(node, skipGroup)
				if node.status == "done" then
					return node.world
				end

				if node.status == "running" then
					if node.world then
						return node.world
					end

					report(entry, "Cyclic dependency at " .. node.id)
					return M.read(node.data.pose_matrix)
				end

				followObject(node.object)

				for _, group in node.groups or {} do
					if
						group ~= skipGroup
						and (not skipGroup or group.sharedGroup ~= skipGroup)
						and not group.constraint.mute
						and group.constraint.enabled ~= false
						and ctx.influence(group.owner, group.constraint) > 0
					then
						solveGroup(group)
						if node.world then
							return node.world
						end
					end
				end

				node.status = "running"
				if node.parent and not node.laggedParent then
					evaluateNode(node.parent, skipGroup)
				end

				node.base = basisFor(entry, node)
				local world = applyBasis(node)
				node.world = world
				world = applyConstraints(node, world)
				node.editWorld = world
				node.world, node.status = connectedHead(node, world), "done"
				return node.world
			end

			local function component(vector, index, value)
				return Vector3.new(
					index == 0 and value or vector.X,
					index == 1 and value or vector.Y,
					index == 2 and value or vector.Z
				)
			end

			local function booleanDriver(value)
				return math.abs(Vector3.new(value, 0, 0).X) >= 1
			end

			for _, driver in entry.drivers do
				if not driver.mute then
					local value, err = Drivers.evaluate(
						driver,
						readVariable,
						(entry.time or 0) * (tonumber(entry.data.fps) or 24)
					)
					if typeof(value) == "number" and value == value then
						local node, field = driver.node, driver.field
						if driver.kind == "shapeKey" then
							local key = driver.shapeKey
							key.value = math.clamp(value, key.min, key.max)
						elseif driver.kind == "constraintTarget" then
							local target = driver.targetObject
							value = math.clamp(value, 0, 1)
							if target.weight ~= value then
								target.weight = value
								local constraint = driver.constraintObject
								entry.constraintRevisions[constraint] = (
									entry.constraintRevisions[constraint] or 0
								) + 1
							end
						elseif driver.kind == "constraint" then
							if field == "influence" then
								driverValues[node] = driverValues[node] or {}
								driverValues[node][driver.constraint] = value
							else
								local constraint = driver.constraintObject
								local nextValue = value
								if driver.boolean then
									nextValue = booleanDriver(value)
								end

								if constraint[field] ~= nextValue then
									constraint[field] = nextValue
									if field == "mute" then
										constraint.enabled = not nextValue
											and constraint.is_valid ~= false
									end

									entry.constraintRevisions[constraint] = (
										entry.constraintRevisions[constraint] or 0
									) + 1
								end
							end
						elseif driver.kind == "objectVisibility" then
							if driver.object then
								driver.object[field] = booleanDriver(value)
							end
						elseif field == "hide" then
							node.hidden = booleanDriver(value)
						elseif field == "hide_select" then
							node.unselectable = booleanDriver(value)
						elseif field == "use_inherit_rotation" then
							node.inheritRotation = booleanDriver(value)
						elseif field:sub(1, 13) == "custom_shape_" then
							if node.display then
								if field == "custom_shape_translation" then
									value *= tonumber(entry.data.scale) or 1
								end

								node.display[field] =
									component(node.display[field], driver.array_index, value)
							end
						else
							local order = node.data.rotation_mode
							if order == "QUATERNION" or order == "AXIS_ANGLE" then
								order = "XYZ"
							end

							local channels = node.drivenChannels
							if not channels then
								channels = {
									location = M.position(node.basis),
									scale = M.scale(node.basis),
									rotation_euler = M.euler(M.toCFrame(node.basis), order),
								}
								node.drivenChannels = channels
							end

							if field == "location" then
								value *= tonumber(entry.data.scale) or 1
							end

							if field == "rotation_quaternion" then
								if not channels.rotation_quaternion then
									channels.rotation_quaternion = { quaternionOf(node.basis) }
								end

								channels.rotation_quaternion[(driver.array_index or 0) + 1] = value
								channels.quaternionDriven = true
							else
								channels[field] =
									component(channels[field], driver.array_index, value)
							end

							local rotation
							if channels.quaternionDriven then
								local q = channels.rotation_quaternion
								local length =
									math.sqrt(q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
								rotation = if length > 1e-12
									then CFrame.new(
										0,
										0,
										0,
										q[2] / length,
										q[3] / length,
										q[4] / length,
										q[1] / length
									)
									else CFrame.identity
							else
								rotation = M.fromEuler(channels.rotation_euler, order)
							end

							node.effectiveBasis =
								M.compose(CFrame.new(channels.location) * rotation, channels.scale)
						end
					else
						report(entry, "Driver " .. driver.data_path .. ": " .. tostring(err))
					end
				end
			end

			local roots = {}
			for _, group in entry.groups do
				group.sharedGroup = nil
				local c = group.constraint
				if not c.mute and c.enabled ~= false and ctx.influence(group.owner, c) == 1 then
					local root = group.chain[1]
					roots[root] = roots[root] or {}
					table.insert(roots[root], group)
				end
			end

			entry.mergedGroups = entry.mergedGroups or {}
			for root, members in roots do
				if #members < 2 then
					continue
				end

				local seen, ends, chain = {}, {}, {}
				local eligible = true
				local key = {}
				for _, member in members do
					local c = member.constraint
					if
						ends[member.owner]
						or c.pole_target_id
						or c.use_tail == false
						or c.use_rotation
					then
						eligible = false
						break
					end

					ends[member.owner] = member
					key[#key + 1] = member.owner.id .. ":" .. member.index
					for _, node in member.chain do
						if
							c.use_stretch
							and (tonumber((node.data.ik_settings or {}).ik_stretch) or 0) > 0
						then
							eligible = false
						end

						if not seen[node] then
							seen[node] = true
							chain[#chain + 1] = node
						end
					end
				end

				if not eligible then
					continue
				end

				local id = table.concat(key, "|")
				local merged = entry.mergedGroups[id]
				if not merged then
					merged = {
						owner = members[1].owner,
						index = members[1].index,
						constraint = members[1].constraint,
						chain = chain,
						members = members,
						ends = ends,
					}
					entry.mergedGroups[id] = merged
				end

				merged.status = nil
				for _, member in members do
					member.sharedGroup = merged
				end
			end

			for _, node in entry.list do
				evaluateNode(node)
			end
		end

		for _, node in entry.list do
			assert(M.isFinite(node.world), "Invalid solved pose for " .. node.id)
			node.candidateFrame = node.frameFit == entry.fitMatrix
					and sameMatrix(node.world, node.committedWorld)
					and node.outputFrame
				or fitted(entry, node.world)
		end

		for _, binding in entry.bindings do
			local c1 = binding.target:IsA("JointInstance") and binding.target.C1 or nil
			local affine
			if
				binding.affineFit == entry.fitMatrix
				and binding.affineC1 == c1
				and sameMatrix(binding.affineSource, binding.node.world)
			then
				affine = binding.candidateAffine
			else
				affine = M.mul(fittedMatrix(entry, binding.node.world), binding.offset)
				if c1 then
					affine = M.mul(affine, M.fromCFrame(c1:Inverse()))
				end

				local frame = M.toCFrame(affine)
				binding.candidateAffine, binding.candidateFrame = affine, frame
				binding.affineFit, binding.affineC1, binding.affineSource =
					entry.fitMatrix, c1, binding.node.world
			end

			if binding.part then
				local ratio = M.scale(affine) / binding.restScale
				assert(M.isFiniteVector(ratio), "Invalid native part scale")
			end
		end

		for _, node in entry.list do
			local visible = node.visibility
			node.candidateHidden = not visible.control
				or visible.collectionHidden
				or visible.objectHidden
				or node.hidden
				or node.object.hide_viewport == true
				or (node.display and node.display.custom_shape_scale_xyz.Magnitude < 1e-8)
				or false
			if
				not samplingRigs[rig]
				and node.anchor
				and not node.candidateHidden
				and Geometry.prepareVisible
			then
				Geometry.prepareVisible(node.anchor)
			end

			if entry.disposed or inputRevision ~= entry.inputRevision then
				return false
			end
		end

		if RigidGeometry.preparePending then
			RigidGeometry.preparePending(entry.rigidGeometry)
		end

		ObjectGeometry.prepare(entry.objectGeometry)
		if entry.disposed or inputRevision ~= entry.inputRevision then
			return false
		end

		local visibilityChanged = false
		for _, node in entry.list do
			local anchor = node.anchor
			if not samplingRigs[rig] and anchor and anchor.Parent then
				local hidden = node.candidateHidden
				local visual = node.visualCache
				if
					force
					or not visual
					or visual.fit ~= entry.fitMatrix
					or anchor.CFrame ~= visual.cframe
					or not sameMatrix(node.visualOwner.world, visual.owner)
					or not sameMatrix(node.world, visual.bone)
					or not sameDisplay(node.display, visual.display)
				then
					local localShape
					if anchor:GetAttribute("EclipseArmatureRawDisplay") and node.display then
						local shape = Display.matrix(
							node.data,
							node.visualOwner.world,
							entry.fit,
							entry.scale,
							entry.data.scale,
							node.display
						)
						local unscaled = table.clone(node.display)
						unscaled.custom_shape_scale_xyz = Vector3.one
						local rotation = M.toCFrame(
							Display.matrix(
								node.data,
								node.visualOwner.world,
								entry.fit,
								entry.scale,
								entry.data.scale,
								unscaled
							)
						).Rotation
						local rawCenter = anchor:GetAttribute("EclipseArmatureRawCenter")
							or Vector3.zero
						anchor.CFrame = CFrame.new(M.point(shape, rawCenter)) * rotation
						localShape = M.mul(
							M.fromCFrame(rotation:Inverse()),
							M.withPosition(shape, Vector3.zero)
						)
						localShape = M.withPosition(localShape, -M.vector(localShape, rawCenter))
						local rawSize = anchor:GetAttribute("EclipseArmatureRawSize")
						if typeof(rawSize) == "Vector3" then
							local x, y, z =
								M.column(localShape, 1),
								M.column(localShape, 2),
								M.column(localShape, 3)
							anchor.Size = Vector3.new(
								math.max(
									0.05,
									math.abs(x.X) * rawSize.X
										+ math.abs(y.X) * rawSize.Y
										+ math.abs(z.X) * rawSize.Z
								),
								math.max(
									0.05,
									math.abs(x.Y) * rawSize.X
										+ math.abs(y.Y) * rawSize.Y
										+ math.abs(z.Y) * rawSize.Z
								),
								math.max(
									0.05,
									math.abs(x.Z) * rawSize.X
										+ math.abs(y.Z) * rawSize.Y
										+ math.abs(z.Z) * rawSize.Z
								)
							)
						end
					elseif node.visualOriginal then
						local shape = M.mul(
							M.mul(
								fittedMatrix(entry, node.visualOwner.world),
								node.visualInitialInverse
							),
							node.visualOriginal
						)
						anchor.CFrame = M.toCFrame(shape)
						localShape = M.mul(M.inverse(M.fromCFrame(anchor.CFrame)), shape)
					end

					anchor.PivotOffset = anchor.CFrame:ToObjectSpace(node.candidateFrame)
					if not hidden then
						Geometry.update(anchor, localShape)
						node.visualPending = nil
					else
						node.visualPending = localShape
					end

					node.pendingGeometry = localShape
					node.pendingVisualCache = {
						fit = entry.fitMatrix,
						cframe = anchor.CFrame,
						owner = table.clone(node.visualOwner.world),
						bone = table.clone(node.world),
						display = node.display and table.clone(node.display),
					}
				end

				if not hidden and node.visualPending then
					Geometry.update(anchor, node.visualPending)
					node.visualPending = nil
				end

				local unselectable = node.unselectable or node.object.data.hide_select == true
				if
					force
					or node.appliedHidden ~= hidden
					or node.appliedUnselectable ~= unselectable
					or node.appliedAnchor ~= anchor
				then
					node.appliedHidden, node.appliedUnselectable, node.appliedAnchor =
						hidden, unselectable, anchor
					node.visualTouched = true
					if anchor:GetAttribute("Hidden") ~= hidden then
						anchor:SetAttribute("Hidden", hidden)
						visibilityChanged = true
					end

					if anchor:GetAttribute("EclipseArmatureUnselectable") ~= unselectable then
						anchor:SetAttribute("EclipseArmatureUnselectable", unselectable)
						visibilityChanged = true
					end

					if Geometry.setVisible then
						Geometry.setVisible(anchor, not hidden)
					end
				end
			end
		end

		if visibilityChanged then
			entry.arm:SetAttribute(
				"EclipseArmatureVisibilityVersion",
				(entry.arm:GetAttribute("EclipseArmatureVisibilityVersion") or 0) + 1
			)
		end

		if
			not samplingRigs[rig]
			and (
				not entry.previewCaptured
				or rig:GetAttribute("EclipseArmaturePreviewActive") ~= true
			)
		then
			require("Recovery").captureArmature(rig, entry.bindings)
			entry.previewCaptured = true
		end

		local nativeWorlds = {}

		local function nativeWorld(target)
			if not target:IsA("Bone") then
				return target.CFrame
			end

			local frame = nativeWorlds[target]
			if not frame then
				frame = nativeWorld(target.Parent) * target.CFrame * target.Transform
				nativeWorlds[target] = frame
			end

			return frame
		end

		for _, binding in entry.bindings do
			local target = binding.target
			if target.Parent then
				local affine = binding.candidateAffine
				local desired = binding.candidateFrame
				if target:IsA("Bone") then
					target.Transform = (nativeWorld(target.Parent) * target.CFrame):Inverse()
						* desired
					nativeWorlds[target] = nil
				elseif target:IsA("JointInstance") and target.Part0 and target.Part1 then
					local partWorld = desired
					target.C0 = target.Part0.CFrame:Inverse() * partWorld * target.C1
					target.Part1.CFrame = partWorld
					table.clear(nativeWorlds)
				elseif target:IsA("BasePart") then
					target.CFrame = desired
					table.clear(nativeWorlds)
				end

				if binding.part and binding.part.Parent then
					binding.affineWorld = affine
					local current = M.scale(affine)
					local ratio = current / binding.restScale
					local size = binding.restSize
						* Vector3.new(math.abs(ratio.X), math.abs(ratio.Y), math.abs(ratio.Z))
					size = Vector3.new(
						math.max(0.001, size.X),
						math.max(0.001, size.Y),
						math.max(0.001, size.Z)
					)
					if binding.part.Size ~= size then
						binding.part.Size = size
					end
				end
			end
		end

		Skinning.update(entry.skinning, entry.nodes, force, entry.shapeKeys)
		RigidGeometry.update(entry.rigidGeometry, entry.nodes, force)
		ObjectGeometry.update(entry.objectGeometry)
		for _, node in entry.list do
			node.committedWorld = node.world
			node.committedEditWorld = node.editWorld or node.world
			node.outputFrame = node.candidateFrame
			node.frameSource = node.world
			node.frameFit = entry.fitMatrix
			local touched = node.visualTouched
				or node.pendingVisualCache ~= nil
				or node.committedVisual == nil
			node.visualTouched = nil
			if node.pendingVisualCache then
				node.visualCache = node.pendingVisualCache
				node.pendingVisualCache = nil
			end

			if node.pendingGeometry then
				node.committedGeometry = node.pendingGeometry
				node.pendingGeometry = nil
			end

			local anchor = node.anchor
			if touched and anchor and anchor.Parent then
				node.committedVisual = {
					cframe = anchor.CFrame,
					size = anchor.Size,
					pivot = anchor.PivotOffset,
					hidden = anchor:GetAttribute("Hidden"),
					canQuery = anchor.CanQuery,
				}
			end
		end

		for _, binding in entry.bindings do
			if binding.target.Parent then
				binding.committedNative = nativeState(binding)
				binding.committedAffine = binding.affineWorld
			end
		end

		for node in entry.pendingInputs or {} do
			if not samplingRigs[rig] and node.anchor then
				node.anchor:SetAttribute(
					"EclipseArmatureLastValidBasis",
					HttpService:JSONEncode(node.basis)
				)
				node.anchor:SetAttribute(
					"EclipseArmatureLastValidInputC0",
					node.anchor:GetAttribute("EclipseArmatureInputC0")
				)
				node.anchor:SetAttribute(
					"EclipseArmatureLastValidInputScale",
					node.anchor:GetAttribute("EclipseArmatureInputScale")
				)
			end
		end

		entry.sampledPresentation = samplingRigs[rig] ~= nil
		entry.pendingInputs = nil
		entry.pendingObjects = nil
		entry.pendingOverrides = nil
		entry.dirty = false
		entry.lastFailure = nil
		nextRevision += 1
		entry.revision = nextRevision
		return true
	end

	local ok, result = pcall(run)
	entry.evaluating = false
	if entry.disposed then
		return false
	end

	if not ok then
		for key, value in previousShapes do
			key.value = value
		end

		propertiesChanged(entry)
		for node, saved in entry.pendingInputs or {} do
			node.basis = saved.basis
			node.properties = saved.properties
			writeInput(node)
			node.c0 = saved.c0
			node.lastC0Input = saved.lastC0Input
			node.lastScaleInput = saved.lastScaleInput
		end

		for object, saved in entry.pendingObjects or {} do
			object.matrix = saved.matrix
			object.properties = saved.properties
		end

		if entry.pendingOverrides then
			entry.overrides = entry.pendingOverrides
			local values = entry.arm:FindFirstChild("EclipseArmaturePropertyValues")
			if values then
				values:Destroy()
			end

			local records = {}
			for _, record in entry.overrides do
				table.insert(records, record)
			end

			ArmatureData.write(
				entry.arm,
				"EclipseArmaturePropertyValues",
				HttpService:JSONEncode(records)
			)
		end

		entry.pendingInputs = nil
		entry.pendingObjects = nil
		entry.pendingOverrides = nil
		for _, node in entry.list do
			node.world = node.committedWorld or node.initialWorld
			node.pendingVisualCache = nil
			local anchor, visual = node.anchor, node.committedVisual
			if anchor and anchor.Parent and visual then
				anchor.CFrame = visual.cframe
				anchor.Size = visual.size
				anchor.PivotOffset = visual.pivot
				anchor.CanQuery = visual.canQuery
				anchor:SetAttribute("Hidden", visual.hidden)
				if Geometry.setVisible then
					Geometry.setVisible(anchor, visual.hidden ~= true)
				end

				pcall(Geometry.update, anchor, node.committedGeometry)
			end

			node.pendingGeometry = nil
			node.visualPending = nil
			node.appliedHidden = nil
		end

		for _, binding in entry.bindings do
			binding.affineWorld = binding.committedAffine
			restoreNativeState(binding)
		end

		pcall(Skinning.update, entry.skinning, entry.nodes, true, entry.shapeKeys)
		pcall(RigidGeometry.update, entry.rigidGeometry, entry.nodes, true)
		pcall(function()
			ObjectGeometry.prepare(entry.objectGeometry)
			ObjectGeometry.update(entry.objectGeometry)
		end)
		entry.dirty = false
		report(entry, tostring(result))
		if entry.lastFailure ~= tostring(result) then
			warn("[Eclipse Armature] " .. tostring(result))
			entry.lastFailure = tostring(result)
		end

		return false
	end

	return result
end

function Runtime.setTime(rig, seconds)
	local entry = getEntry(rig)
	if not entry or entry.time == seconds then
		return
	end

	entry.time = seconds
	if entry.usesFrame then
		dirty(entry)
	end
end

function Runtime.revision(rig)
	local entry = getEntry(rig)
	return entry and entry.revision or 0
end

function Runtime.controls(rig)
	local entry = getEntry(rig)
	if not entry then
		return {}
	end

	if not entry.controls then
		entry.controls = {}
		for _, node in entry.list do
			if node.anchor and node.visibility.control then
				table.insert(entry.controls, node.anchor)
			end
		end
	end

	return entry.controls
end

function Runtime.worldCFrame(anchor, rig)
	local entry = anchorEntries[anchor] or getEntry(rig)
	local node = entry and entry.nodes[anchor:GetAttribute("EclipseArmatureBoneId")]
	return node and (node.deferredWorld or worldFrame(node))
end

function Runtime.getMatrix(rig, id)
	local entry = getEntry(rig)
	local node = entry and entry.nodes[id]
	if not node then
		return nil
	end

	if entry.dirty then
		Runtime.evaluate(rig)
	end

	return node.world and table.clone(node.world)
end

function Runtime.getBasis(rig, id)
	local entry = getEntry(rig)
	local node = entry and entry.nodes[id]
	return node and table.clone(node.basis)
end

function Runtime.getDisplay(rig, id)
	local entry = getEntry(rig)
	local node = entry and entry.nodes[id]
	if not node then
		return nil
	end

	if entry.dirty then
		Runtime.evaluate(rig)
	end

	return node.display
		and {
			matrix = Display.matrix(
				node.data,
				node.visualOwner.world,
				CFrame.identity,
				1,
				entry.data.scale,
				node.display
			),
			hidden = node.hidden or node.object.hide_viewport == true,
			scale = node.display.custom_shape_scale_xyz,
			translation = node.display.custom_shape_translation,
			rotation = node.display.custom_shape_rotation_euler,
		}
end

function Runtime.snapshot(rig)
	local entry = getEntry(rig)
	if not entry then
		return nil
	end

	local out = { basis = {}, properties = {}, objects = {}, constraintPrevious = {} }
	for _, node in entry.list do
		out.basis[node.id] = table.clone(node.basis)
		out.properties[node.id] = table.clone(node.properties)
		out.constraintPrevious[node.id] = table.clone(node.constraintPrevious or node.initialWorld)
	end

	for name, object in entry.objects do
		out.objects[name] =
			{ matrix = table.clone(object.matrix), properties = table.clone(object.properties) }
	end

	return out
end

function Runtime.exportSurfaces(rig)
	local entry = getEntry(rig)
	if not entry then
		return {}
	end

	local surfaces = RigidGeometry.prepareExport(entry.rigidGeometry)
	for _, surface in ObjectGeometry.prepareExport(entry.objectGeometry) do
		table.insert(surfaces, surface)
	end

	for _, state in entry.skinning and entry.skinning.meshes or {} do
		table.insert(surfaces, state.part)
	end

	return surfaces
end

function Runtime.restore(rig, snapshot)
	local entry = getEntry(rig)
	if not entry or not snapshot then
		return false
	end

	local ok, prepared = pcall(function()
		local out = { nodes = {}, objects = {} }

		local function properties(value)
			local copy = table.clone(value)
			for _, v in copy do
				assert(
					typeof(v) ~= "number" or v == v and math.abs(v) < math.huge,
					"Invalid saved property"
				)
			end

			return copy
		end

		for id, basis in snapshot.basis do
			local node = entry.nodes[id]
			if node then
				local parsed = M.readStrict(basis)
				M.toCFrame(M.mul(node.restLocal, parsed))
				out.nodes[node] = {
					basis = parsed,
					properties = properties(snapshot.properties[id] or node.properties),
					constraintPrevious = snapshot.constraintPrevious
						and snapshot.constraintPrevious[id]
						and M.readStrict(snapshot.constraintPrevious[id]),
				}
			end
		end

		for name, object in snapshot.objects do
			local current = entry.objects[name]
			if current then
				out.objects[current] = {
					matrix = M.readStrict(object.matrix),
					properties = properties(object.properties),
				}
			end
		end

		return out
	end)
	if not ok then
		report(entry, "Rejected invalid undo pose: " .. tostring(prepared))
		return false
	end

	local function same(a, b)
		if a == b then
			return true
		end

		if typeof(a) ~= "table" or typeof(b) ~= "table" then
			return false
		end

		for key, v in a do
			if b[key] ~= v then
				return false
			end
		end

		for key in b do
			if a[key] == nil then
				return false
			end
		end

		return true
	end

	for node, value in prepared.nodes do
		if not same(node.basis, value.basis) then
			setNodeBasis(node, value.basis)
		end

		if not same(node.properties, value.properties) then
			node.properties = value.properties
		end
	end

	for current, value in prepared.objects do
		Runtime.setObjectMatrix(rig, current.data.name, value.matrix)
		current.properties = value.properties
	end

	propertiesChanged(entry)
	dirty(entry)
	for node, value in prepared.nodes do
		node.constraintPrevious = value.constraintPrevious or node.initialWorld
	end

	entry.constraintRevision = entry.inputRevision
	return true
end

function Runtime.diagnostics(rig)
	local entry = getEntry(rig)
	return entry and table.clone(entry.diagnostics) or {}
end

function Runtime.gatherDriven(rig)
	local entry = getEntry(rig)
	return entry and table.clone(entry.targets) or {}
end

function Runtime.nativeRestPose(rig)
	local result, sizes = {}, {}
	local arm = rig and findArm(rig)
	if not arm then
		return result, sizes
	end

	for _, reference in arm:GetDescendants() do
		if reference:IsA("ObjectValue") then
			local target = reference.Value
			local rest = reference:GetAttribute("EclipseArmatureRestC0")
			if
				target
				and target:IsA("Motor6D")
				and target:IsDescendantOf(rig)
				and typeof(rest) == "CFrame"
			then
				result[target] = rest
			end

			if target then
				local part = target:IsA("JointInstance") and target.Part1
					or target:IsA("BasePart") and target
				local size = reference:GetAttribute("EclipseArmatureRestSize")
				if part and part:IsDescendantOf(rig) and typeof(size) == "Vector3" then
					sizes[part] = size
				end
			end
		end
	end

	return result, sizes
end

function Runtime.nativeRestC0(rig, target)
	local entry = getEntry(rig)
	if not entry then
		return nil
	end

	for _, binding in entry.bindings do
		if binding.target == target then
			if target:IsA("Bone") then
				return target.CFrame
			end

			local value = binding.reference
				and binding.reference:GetAttribute("EclipseArmatureRestC0")
			return typeof(value) == "CFrame" and value or nil
		end
	end

	return nil
end

local function editNode(adapter)
	local anchor = adapter and adapter.Part1
	local entry = anchor and anchorEntries[anchor]
	return entry and entry.nodes[anchor:GetAttribute("EclipseArmatureBoneId")]
end

function Runtime.inheritsRotation(adapter)
	local node = editNode(adapter)
	if not node then
		return true
	end

	if node.rotationOverride ~= nil then
		return node.rotationOverride
	end

	return node.inheritRotation ~= false
end

local function keepLocked(value, original, locks)
	locks = locks or {}
	return Vector3.new(
		locks[1] and original.X or value.X,
		locks[2] and original.Y or value.Y,
		locks[3] and original.Z or value.Z
	)
end

function Runtime.constrainC0(adapter, value)
	local node = editNode(adapter)
	if not node then
		return value
	end

	if not M.isRigidCFrame(value) then
		report(node.entry, "Rejected invalid drag for " .. node.id)
		return node.c0
	end

	local locations = node.data.lock_location or {}
	local rotations = node.data.lock_rotation or {}
	if
		not (
			locations[1]
			or locations[2]
			or locations[3]
			or rotations[1]
			or rotations[2]
			or rotations[3]
			or node.data.rotation_mode == "QUATERNION" and node.data.lock_rotation_w
		)
	then
		return value
	end

	local desired = M.mul(
		M.inverse(node.restLocal),
		M.translationScaled(M.fromCFrame(value), 1 / node.entry.scale)
	)
	local old = M.toCFrame(node.basis)
	local position = keepLocked(M.position(desired), old.Position, node.data.lock_location)
	local locks = node.data.lock_rotation or {}
	local rotation = M.toCFrame(desired).Rotation
	if locks[1] and locks[2] and locks[3] then
		rotation = old.Rotation
	elseif
		locks[1]
		or locks[2]
		or locks[3]
		or node.data.rotation_mode == "QUATERNION" and node.data.lock_rotation_w
	then
		local order = node.data.rotation_mode
		if order == "QUATERNION" and node.data.lock_rotations_4d then
			local function quaternion(cf)
				local axis, angle = cf:ToAxisAngle()
				return math.cos(angle * 0.5), axis * math.sin(angle * 0.5)
			end

			local w, v = quaternion(rotation)
			local oldW, oldV = quaternion(old)
			if w * oldW + v:Dot(oldV) < 0 then
				w, v = -w, -v
			end

			v = keepLocked(v, oldV, locks)
			if node.data.lock_rotation_w then
				w = oldW
			end

			rotation = v.Magnitude > 1e-10
					and CFrame.fromAxisAngle(v.Unit, 2 * math.atan2(v.Magnitude, w))
				or CFrame.identity
		else
			rotation =
				M.fromEuler(keepLocked(M.euler(rotation, order), M.euler(old, order), locks), order)
		end
	end

	local localPose =
		M.mul(node.restLocal, M.compose(CFrame.new(position) * rotation, M.scale(node.basis)))
	return M.toCFrame(M.translationScaled(localPose, node.entry.scale))
end

function Runtime.constrainScale(adapter, value)
	local node = editNode(adapter)
	if node and not M.isFiniteVector(value) then
		return adapter.InputScale
	end

	return node and keepLocked(value, adapter.InputScale, node.data.lock_scale) or value
end

function Runtime.captureEdit(adapter)
	local node = editNode(adapter)
	if not node then
		return nil
	end

	local world = worldFrame(node)
	local input =
		fitted(node.entry, node.committedEditWorld or node.committedWorld or node.initialWorld)
	local location = node.data.local_location == false
			and (node.parent and parentWorldFor(node) or node.object.matrix)
		or node.locationBase
		or node.base
	return {
		id = node.id,
		rig = node.entry.rig,
		c0 = node.c0,
		scale = adapter.InputScale,
		basis = table.clone(node.basis),
		world = world,
		inputWorld = input,
		bridge = (input * node.c0:Inverse()):Orthonormalize(),
		locationInverse = location and M.inverse(location),
		fit = node.entry.fit,
	}
end

function Runtime.solveEditC0(adapter, targetWorld, snapshot, skipInputLocks)
	local node = editNode(adapter)
	if not node then
		return nil
	end

	if
		not snapshot
		or snapshot.id ~= node.id
		or snapshot.rig ~= node.entry.rig
		or not M.isRigidCFrame(targetWorld)
	then
		return node.c0
	end

	local target = targetWorld * snapshot.world:Inverse() * (snapshot.inputWorld or snapshot.world)
	local value = snapshot.bridge:ToObjectSpace(target)
	if snapshot.locationInverse then
		local delta = snapshot.fit:VectorToObjectSpace(
			target.Position - (snapshot.inputWorld or snapshot.world).Position
		) / node.entry.scale
		local inputDelta = M.vector(node.restLocal, M.vector(snapshot.locationInverse, delta))
			* node.entry.scale
		value = CFrame.new(snapshot.c0.Position + inputDelta) * value.Rotation
	end

	value = skipInputLocks and value or Runtime.constrainC0(adapter, value)
	local pending = deferredEdits[node.entry.rig]
	if pending then
		local anchor = node.anchor
		pending[node] = pending[node] or anchor.CFrame
		local constrainedWorld = (snapshot.bridge * value)
			* (snapshot.inputWorld or snapshot.world):Inverse()
			* snapshot.world
		node.deferredWorld = constrainedWorld
		anchor.CFrame = constrainedWorld * snapshot.world:Inverse() * pending[node]
		Geometry.update(anchor, node.committedGeometry)
		nextRevision += 1
		node.entry.revision = nextRevision
	end

	return value
end

function Runtime.restoreEdit(adapter, snapshot)
	local node = editNode(adapter)
	if not node or not snapshot or snapshot.id ~= node.id or snapshot.rig ~= node.entry.rig then
		return false
	end

	return setNodeBasis(node, table.clone(snapshot.basis), snapshot.c0, snapshot.scale)
end

function Runtime.restoreNativeGeometry(rig)
	local entry = entries[rig]
	if entry then
		Skinning.cleanup(entry.skinning)
		RigidGeometry.cleanup(entry.rigidGeometry)
		ObjectGeometry.cleanup(entry.objectGeometry)
		for _, binding in entry.bindings do
			if binding.part and binding.part.Parent then
				binding.part.Size = binding.restSize
			end
		end
	end
end

function Runtime.invalidate(rig)
	Runtime.endDeferredEdit(rig)
	local entry = entries[rig]
	entries[rig] = nil
	dispose(entry)
	if absent[rig] then
		absent[rig]:Disconnect()
		absent[rig] = nil
	end
end

function Runtime.suspend(rig)
	local entry = entries[rig]
	local arm = entry and entry.arm or (rig and findArm(rig))
	Runtime.invalidate(rig)
	if entry then
		for _, binding in entry.bindings do
			if binding.part and binding.part.Parent then
				binding.part.Size = binding.restSize
			end
		end
	end

	require("Recovery").restoreArmature(rig)
	if arm and Geometry.releaseArm then
		Geometry.releaseArm(arm)
	end
end

function Runtime.clear()
	require("MeshAccess").clear()
	Runtime.endDeferredEdits()
	local rigs = {}
	for rig in entries do
		table.insert(rigs, rig)
	end

	for _, rig in rigs do
		Runtime.suspend(rig)
	end

	for rig, connection in absent do
		connection:Disconnect()
		absent[rig] = nil
	end
end

function Runtime.get(anchor, rig, joint)
	if not Runtime.isAnchor(anchor) then
		return nil
	end

	local entry = anchorEntries[anchor] or getEntry(rig)
	local node = entry and entry.nodes[anchor:GetAttribute("EclipseArmatureBoneId")]
	if not node then
		return nil
	end

	if node.adapter then
		return node.adapter
	end

	local part0 = setmetatable({}, {
		__index = function(_, key)
			if key == "CFrame" then
				local output = worldFrame(node)
				if node.proxyOutput ~= output or node.proxyInput ~= node.c0 then
					node.proxyOutput, node.proxyInput = output, node.c0
					node.proxyFrame = (output * node.c0:Inverse()):Orthonormalize()
				end

				return node.proxyFrame
			elseif key == "Name" then
				return node.parent and node.parent.data.name or "ArmatureRoot"
			elseif key == "IsA" then
				return function(_, class)
					return class == "BasePart"
				end
			end
		end,
	})

	local members = {
		C1 = CFrame.identity,
		Part0 = part0,
		Part1 = anchor,
		RealPart0 = node.parent and node.parent.anchor,
		Enabled = true,
		IsEclipseArmatureControl = true,
		IsEclipseIKHandle = true,
		IsA = function(_, class)
			return class == "Motor6D" or class == "JointInstance"
		end,
		GetAttribute = function(_, attribute)
			return anchor:GetAttribute(attribute)
		end,
		SetAttribute = function(_, attribute, value)
			anchor:SetAttribute(attribute, value)
		end,
		GetAttributes = function()
			return anchor:GetAttributes()
		end,
		GetFullName = function()
			return anchor:GetFullName()
		end,
	}
	node.adapter = setmetatable({}, {
		__index = function(_, key)
			if members[key] ~= nil then
				return members[key]
			end

			if key == "C0" then
				return node.c0
			elseif key == "RestC0" then
				if not node.restFrame then
					node.restFrame = M.toCFrame(M.translationScaled(node.restLocal, entry.scale))
				end

				return node.restFrame
			elseif key == "InputScale" then
				return node.lastScaleInput or M.scale(node.basis) / node.defaultScale
			elseif key == "C1" then
				return CFrame.identity
			elseif key == "Part0" then
				return part0
			elseif key == "Part1" then
				return anchor
			elseif key == "RealPart0" then
				return node.parent and node.parent.anchor
			elseif key == "Name" then
				return anchor.Name
			elseif key == "Parent" then
				return anchor.Parent
			elseif
				key == "Enabled"
				or key == "IsEclipseArmatureControl"
				or key == "IsEclipseIKHandle"
			then
				return true
			elseif key == "IsA" then
				return function(_, class)
					return class == "Motor6D" or class == "JointInstance"
				end
			elseif key == "GetAttribute" then
				return function(_, attribute)
					return anchor:GetAttribute(attribute)
				end
			elseif key == "SetAttribute" then
				return function(_, attribute, value)
					anchor:SetAttribute(attribute, value)
				end
			elseif key == "GetAttributes" then
				return function()
					return anchor:GetAttributes()
				end
			elseif key == "GetFullName" then
				return function()
					return anchor:GetFullName()
				end
			end
		end,
		__newindex = function(_, key, value)
			if key == "C0" then
				if value == node.c0 or value == node.lastC0Input then
					return
				end

				if not M.isRigidCFrame(value) then
					report(entry, "Rejected invalid input for " .. node.id)
					return
				end

				local pose = M.translationScaled(M.fromCFrame(value), 1 / entry.scale)
				pose = M.compose(M.toCFrame(pose), M.scale(M.mul(node.restLocal, node.basis)))
				if not node.restLocalInverse then
					node.restLocalInverse = M.inverse(node.restLocal)
				end

				setNodeBasis(node, M.mul(node.restLocalInverse, pose), value, node.lastScaleInput)
			elseif key == "InputScale" and typeof(value) == "Vector3" then
				if not M.isFiniteVector(value) then
					report(entry, "Rejected non-finite scale for " .. node.id)
					return
				end

				if value == node.lastScaleInput then
					return
				end

				local desired = node.defaultScale * value
				if (M.scale(node.basis) - desired).Magnitude < 1e-7 then
					node.lastScaleInput = value
					return
				end

				setNodeBasis(node, M.compose(M.toCFrame(node.basis), desired), nil, value)
			end
		end,
	})
	local adapter = node.adapter
	stableAdapters[anchor] = {
		rig = rig,
		bind = function(nextNode, nextEntry)
			node, entry = nextNode, nextEntry
			node.adapter = adapter
			members.RealPart0 = node.parent and node.parent.anchor
		end,
	}
	return adapter
end

function Runtime.collectMotors(rig)
	local entry = getEntry(rig)
	local out = {}
	if entry then
		for _, node in entry.list do
			if node.anchor then
				table.insert(out, Runtime.get(node.anchor, rig))
			end
		end
	end

	return out
end

return Runtime
