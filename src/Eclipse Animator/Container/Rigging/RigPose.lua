--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")

local Pose = {}

const HOME_C1 = "EclipseAnimatorDefaultC1"
const LOADED_C1 = "EclipseAnimatorLoadedC1"
const OBJECT_ENABLED = "EclipseObjectJointEnabled"
const STAMP_TOKEN = "EclipseAnimatorStampToken"
const JOINT_STAMPS = {
	"EclipseAnimatorDefaultC0",
	"EclipseRigRestC0",
	HOME_C1,
	LOADED_C1,
	"EclipseJointBeforePreview",
}
const PART_STAMPS = { "EclipseAnimatorDefaultSize", "EclipsePoseBeforePreview" }
const homes = setmetatable({}, { __mode = "k" })
const bonds = setmetatable({}, { __mode = "k" })

function Pose.rememberRest(joint, rest)
	if typeof(rest) == "CFrame" then
		joint:SetAttribute("EclipseRigRestC0", rest)
	end
end

function Pose.applyLoadedC1(motor, c1)
	if motor.C1:FuzzyEq(c1, 1e-6) then
		return
	end

	if typeof(motor:GetAttribute(HOME_C1)) ~= "CFrame" then
		motor:SetAttribute(HOME_C1, motor.C1)
	end

	motor.C1 = c1
	motor:SetAttribute(LOADED_C1, c1)
end

function Pose.restoreLoadedC1(motor)
	const home = motor:GetAttribute(HOME_C1)
	if home == nil then
		return
	end

	const loaded = motor:GetAttribute(LOADED_C1)
	if
		typeof(home) == "CFrame"
		and (typeof(loaded) ~= "CFrame" or motor.C1:FuzzyEq(loaded, 1e-5))
	then
		motor.C1 = home
	end

	motor:SetAttribute(HOME_C1, nil)
	motor:SetAttribute(LOADED_C1, nil)
end

local function attachedInPlace(motor)
	return motor.Part0 ~= nil
		and motor.Part1 ~= nil
		and (motor.Part0.CFrame * motor.C0 * motor.Transform * motor.C1:Inverse()):FuzzyEq(
			motor.Part1.CFrame,
			1e-3
		)
end

function Pose.setObjectJoint(motor, enabled)
	if motor:GetAttribute(OBJECT_ENABLED) == nil then
		motor:SetAttribute(OBJECT_ENABLED, motor.Enabled or attachedInPlace(motor))
	end

	if motor.Enabled ~= enabled then
		motor.Enabled = enabled
	end
end

function Pose.restoreObjectJoint(motor)
	local original = motor:GetAttribute(OBJECT_ENABLED)
	if typeof(original) ~= "boolean" then
		original = motor.Enabled or attachedInPlace(motor)
	end

	if motor.Enabled ~= original then
		motor.Enabled = original
	end

	if motor:GetAttribute(OBJECT_ENABLED) ~= nil then
		motor:SetAttribute(OBJECT_ENABLED, nil)
	end
end

local function settled(rig)
	for _, object in RigTraversal.rigDescendants(rig) do
		if
			not object:GetAttribute("EclipseArmatureSkinningHelper")
			and (
				object:GetAttribute("EclipseAnimatorDefaultC0") ~= nil
				or object:GetAttribute("EclipseAnimatorDefaultSize") ~= nil
			)
		then
			return false
		end
	end

	return true
end

function Pose.captureHome(rig)
	if typeof(rig) ~= "Instance" or not rig:IsA("Model") or homes[rig] then
		return
	end

	homes[rig] = { pivot = rig:GetPivot(), scale = rig:GetScale(), settled = settled(rig) }
	require("Properties").captureDefaults(rig)
	Pose.captureBonds(rig)
end

function Pose.settledHome(rig)
	const home = rig and homes[rig]
	return home and home.settled and home.pivot or nil
end

function Pose.unsettleHome(rig)
	const home = rig and homes[rig]
	if home then
		home.settled = false
	end
end

function Pose.restoreHome(rig)
	const home = rig and homes[rig]
	if not home or not rig.Parent then
		return
	end

	const Properties = require("Properties")
	local scaled, placed = false, false
	for _, motor in Properties.list(rig, true, true) do
		if motor.PropertyId == "Scale" then
			scaled = true
		elseif motor.PropertyId == "CFrame" then
			placed = not Properties.inheritedTransform(rig)
		end
	end

	if scaled and math.abs(rig:GetScale() - home.scale) > 1e-7 then
		rig:ScaleTo(home.scale)
	end

	if placed and not rig:GetPivot():FuzzyEq(home.pivot, 1e-6) then
		rig:PivotTo(home.pivot)
	end
end

function Pose.forgetHome(rig)
	if rig then
		homes[rig] = nil
		bonds[rig] = nil
	else
		table.clear(homes)
		table.clear(bonds)
	end
end

local function classicRest(rig, motor)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end

	local a, b = motor.Part0, motor.Part1
	if not a or not b then
		return nil
	end

	local flip = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	local right = CFrame.Angles(0, math.pi / 2, 0)
	local left = CFrame.Angles(0, -math.pi / 2, 0)
	local rest, expected
	if motor.Name == "RootJoint" and a.Name == "HumanoidRootPart" and b.Name == "Torso" then
		rest = flip
		expected = flip
	elseif motor.Name == "Neck" and a.Name == "Torso" and b.Name == "Head" then
		rest = CFrame.new(0, a.Size.Y / 2, 0) * flip
		expected = CFrame.new(0, -b.Size.Y / 2, 0) * flip
	else
		local side, kind = motor.Name:match("^(Left) (.+)$")
		if not side then
			side, kind = motor.Name:match("^(Right) (.+)$")
		end

		if a.Name ~= "Torso" or not side then
			return nil
		end

		local sign = side == "Right" and 1 or -1
		local rotation = sign == 1 and right or left
		if kind == "Shoulder" and b.Name == side .. " Arm" then
			rest = CFrame.new(sign * a.Size.X / 2, a.Size.Y / 4, 0) * rotation
			expected = CFrame.new(-sign * b.Size.X / 2, b.Size.Y / 4, 0) * rotation
		elseif kind == "Hip" and b.Name == side .. " Leg" then
			rest = CFrame.new(sign * a.Size.X / 2, -a.Size.Y / 2, 0) * rotation
			expected = CFrame.new(sign * b.Size.X / 2, b.Size.Y / 2, 0) * rotation
		end
	end

	return expected and motor.C1:FuzzyEq(expected, 1e-5) and rest or nil
end

local layouts = setmetatable({}, { __mode = "k" })

local function layout(rig)
	local entry = layouts[rig]
	if entry and entry.valid then
		return entry
	end

	if entry then
		for _, connection in entry.connections do
			connection:Disconnect()
		end

		for _, connection in entry.watchers do
			connection:Disconnect()
		end
	end

	entry = {
		valid = true,
		rooted = false,
		posed = true,
		parts = {},
		objects = {},
		motors = {},
		joints = {},
		roots = {},
		transforms = {},
		c0s = {},
		c1s = {},
		connections = {},
		watchers = {},
	}

	local function dirty(object)
		if
			object:IsA("BasePart")
			or object:IsA("JointInstance")
			or object:IsA("WeldConstraint")
			or object:IsA("RigidConstraint")
			or object:IsA("AnimationConstraint")
		then
			entry.valid = false
		end
	end

	local function rebuild()
		entry.valid = false
	end

	local function regroup()
		entry.rooted = false
		entry.posed = true
	end

	local function posed()
		entry.posed = true
	end

	entry.markPosed = posed
	local function watch(object, properties, callback)
		for _, property in properties do
			table.insert(
				entry.connections,
				object:GetPropertyChangedSignal(property):Connect(callback)
			)
		end
	end

	for _, object in RigTraversal.rigDescendants(rig) do
		if object:IsA("BasePart") then
			table.insert(entry.parts, object)
			watch(object, { "Anchored", "RootPriority", "Massless", "Size" }, regroup)
		elseif object:IsA("JointInstance") or object:IsA("WeldConstraint") then
			table.insert(entry.objects, object)
			watch(object, { "Enabled", "Part0", "Part1" }, regroup)
			if object:IsA("JointInstance") then
				table.insert(entry.joints, object)
			end

			if object:IsA("Motor6D") then
				table.insert(entry.motors, object)
			end
		elseif object:IsA("RigidConstraint") or object:IsA("AnimationConstraint") then
			table.insert(entry.objects, object)
			watch(object, { "Enabled" }, regroup)
			watch(object, { "Attachment0", "Attachment1" }, rebuild)
			if object:IsA("AnimationConstraint") then
				watch(object, { "IsKinematic" }, regroup)
				table.insert(entry.motors, object)
			end

			for _, attachment in { object.Attachment0, object.Attachment1 } do
				if attachment then
					watch(attachment, { "CFrame" }, posed)
				end
			end
		end
	end

	table.insert(entry.connections, rig.DescendantAdded:Connect(dirty))
	table.insert(entry.connections, rig.DescendantRemoving:Connect(dirty))
	layouts[rig] = entry
	return entry
end

local function refreshRoots(entry)
	for _, connection in entry.watchers do
		connection:Disconnect()
	end

	table.clear(entry.watchers)
	table.clear(entry.roots)
	for _, part in entry.parts do
		if part.Parent and part.AssemblyRootPart == part then
			table.insert(entry.roots, part)
		end
	end

	if #entry.roots > 1 then
		for _, part in entry.roots do
			table.insert(
				entry.watchers,
				part:GetPropertyChangedSignal("CFrame"):Connect(entry.markPosed)
			)
		end
	end

	entry.rooted = true
	entry.posed = true
end

local function bridged(joint)
	return joint:GetAttribute("EclipseConstraintProxy")
		or joint:GetAttribute("EclipseConstraintBorrowedC0")
end

local function link(links, part, target, offset, motor)
	const current = links[part]
	if not current or motor and not current.motor then
		links[part] = { part = target, offset = offset, motor = motor }
	end
end

local function weldable(rig, joint)
	const a, b = joint.Part0, joint.Part1
	return joint.Enabled
		and a ~= nil
		and b ~= nil
		and a ~= b
		and a:IsDescendantOf(rig)
		and b:IsDescendantOf(rig)
end

function Pose.bondOffset(rig, weld)
	if not weld:IsA("WeldConstraint") then
		return weld.C0 * weld.C1:Inverse()
	end

	local list = bonds[rig]
	if not list then
		list = setmetatable({}, { __mode = "k" })
		bonds[rig] = list
	end

	const a, b = weld.Part0, weld.Part1
	local record = list[weld]
	if not record or record.part0 ~= a or record.part1 ~= b then
		record = { part0 = a, part1 = b, offset = a.CFrame:ToObjectSpace(b.CFrame) }
		list[weld] = record
	else
		const root = a.AssemblyRootPart
		if root and root == b.AssemblyRootPart then
			record.offset = a.CFrame:ToObjectSpace(b.CFrame)
		end
	end

	return record.offset
end

function Pose.captureBonds(rig)
	if typeof(rig) ~= "Instance" then
		return
	end

	for _, object in RigTraversal.rigDescendants(rig) do
		if object:IsA("WeldConstraint") and weldable(rig, object) then
			Pose.bondOffset(rig, object)
		end
	end
end

function Pose.releaseBonds(rig)
	if rig and not homes[rig] then
		bonds[rig] = nil
	end
end

function Pose.spreadWelds(rig, welds, reached, attach)
	const edges = {}
	for _, weld in welds do
		if not weldable(rig, weld) then
			continue
		end

		const a, b = weld.Part0, weld.Part1
		const offset = Pose.bondOffset(rig, weld)
		if not edges[a] then
			edges[a] = {}
		end

		if not edges[b] then
			edges[b] = {}
		end

		table.insert(edges[a], { b, offset })
		table.insert(edges[b], { a, offset:Inverse() })
	end

	if not next(edges) then
		return
	end

	const queue = {}
	const queued = {}
	for _, weld in welds do
		for _, part in { weld.Part0, weld.Part1 } do
			if edges[part] and reached[part] and not queued[part] then
				queued[part] = true
				table.insert(queue, part)
			end
		end
	end

	local index = 1
	local function spread()
		while index <= #queue do
			const part = queue[index]
			index += 1
			for _, edge in edges[part] do
				const other = edge[1]
				if not reached[other] then
					reached[other] = true
					attach(other, part, edge[2])
					table.insert(queue, other)
				end
			end
		end
	end

	spread()
	for _, weld in welds do
		local seed = weld.Part0
		const other = weld.Part1
		if not seed or not other or not edges[seed] or reached[seed] or reached[other] then
			continue
		end

		const accessory = seed:FindFirstAncestorOfClass("Accessory")
		if accessory and not other:IsDescendantOf(accessory) then
			seed = other
		end

		reached[seed] = true
		table.insert(queue, seed)
		spread()
	end
end

local function collectLinks(rig, objects, native)
	const passive = RigTraversal.passiveMotors(rig)
	const links = {}
	const welds = {}
	const constraints = {}
	for _, joint in objects do
		if joint:IsA("JointInstance") then
			const a = joint.Part0
			const b = joint.Part1
			const proxy = native and bridged(joint)
			if
				not a
				or not b
				or not (joint.Enabled or proxy)
				or not a:IsDescendantOf(rig)
				or not b:IsDescendantOf(rig)
			then
				continue
			end

			const motor = joint:IsA("Motor6D")
			if not motor then
				table.insert(welds, joint)
				continue
			end

			const transform = not proxy and joint.Transform or CFrame.identity
			const accessory = a:FindFirstAncestorOfClass("Accessory")
			if passive[joint] or accessory and not b:IsDescendantOf(accessory) then
				link(links, a, b, joint.C1 * transform:Inverse() * joint.C0:Inverse(), motor)
			else
				link(links, b, a, joint.C0 * transform * joint.C1:Inverse(), motor)
			end
		elseif joint:IsA("WeldConstraint") then
			table.insert(welds, joint)
		elseif joint:IsA("RigidConstraint") or joint:IsA("AnimationConstraint") then
			table.insert(constraints, joint)
		end
	end

	const reached = {}
	for part, entry in links do
		reached[part] = true
		reached[entry.part] = true
	end

	Pose.spreadWelds(rig, welds, reached, function(part, target, offset)
		links[part] = { part = target, offset = offset }
	end)

	for _, constraint in constraints do
		local a, b = constraint.Attachment0, constraint.Attachment1
		if
			not constraint.Enabled
			or not a
			or not b
			or not a.Parent
			or not b.Parent
			or not a.Parent:IsA("BasePart")
			or not b.Parent:IsA("BasePart")
			or not a:IsDescendantOf(rig)
			or not b:IsDescendantOf(rig)
		then
			continue
		end

		if constraint:IsA("AnimationConstraint") then
			if not links[b.Parent] then
				links[b.Parent] = {
					part = a.Parent,
					offset = a.CFrame * constraint.Transform * b.CFrame:Inverse(),
				}
			end
		else
			const accessory = a.Parent:FindFirstAncestorOfClass("Accessory")
			if accessory and not b:IsDescendantOf(accessory) then
				a, b = b, a
			end

			if not links[b.Parent] then
				links[b.Parent] = { part = a.Parent, offset = a.CFrame * b.CFrame:Inverse() }
			end
		end
	end

	return links
end

local function resolver(links)
	const worlds = {}
	const visiting = {}
	local function world(part)
		local frame = worlds[part]
		if frame then
			return frame
		end

		if visiting[part] then
			return part.CFrame
		end

		visiting[part] = true
		const entry = links[part]
		frame = entry and world(entry.part) * entry.offset or part.CFrame
		visiting[part] = nil
		worlds[part] = frame
		return frame
	end

	return world
end

function Pose.syncAccessories(rig)
	const cached = layout(rig)
	if not cached.rooted then
		refreshRoots(cached)
	end

	const roots = cached.roots
	if #roots < 2 then
		return
	end

	const transforms = cached.transforms
	for _, motor in cached.motors do
		const transform = motor.Transform
		if transforms[motor] ~= transform then
			transforms[motor] = transform
			cached.posed = true
		end
	end

	const c0s = cached.c0s
	const c1s = cached.c1s
	for _, joint in cached.joints do
		const c0 = joint.C0
		if c0s[joint] ~= c0 then
			c0s[joint] = c0
			cached.posed = true
		end

		const c1 = joint.C1
		if c1s[joint] ~= c1 then
			c1s[joint] = c1
			cached.posed = true
		end
	end

	if not cached.posed then
		return
	end

	cached.posed = false
	const world = resolver(collectLinks(rig, cached.objects, true))
	const parts = {}
	const frames = {}
	for _, part in roots do
		if not part.Parent then
			continue
		end

		const frame = world(part)
		if not part.CFrame:FuzzyEq(frame, 1e-6) then
			table.insert(parts, part)
			table.insert(frames, frame)
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Pose.resolve(selected, items)
	local rigs = {}

	local function add(object)
		while typeof(object) == "Instance" and object ~= workspace do
			local reference = object:FindFirstChild("EclipseSourceRig")
			if reference and reference:IsA("ObjectValue") and reference.Value then
				object = reference.Value
			end

			if
				object:IsA("Model")
				and (
					object:FindFirstChildOfClass("Humanoid")
					or object:FindFirstChildWhichIsA("Motor6D", true)
					or object:FindFirstChildWhichIsA("Bone", true)
					or object:FindFirstChildWhichIsA("AnimationConstraint", true)
				)
			then
				rigs[object] = true
				return
			end

			object = object.Parent
		end
	end

	for _, object in selected do
		add(object)
	end

	if not next(rigs) then
		for item, enabled in items or {} do
			if enabled then
				add((item.grandpa or item).linkedRigInstance or item.linkedRigInstance)
			end
		end
	end

	local result
	for rig in rigs do
		if result then
			return nil, true
		end

		result = rig
	end

	return result, false
end

function Pose.assemble(rig)
	const cached = layout(rig)
	const world = resolver(collectLinks(rig, cached.objects, false))
	const parts = {}
	const frames = {}
	const moved = {}
	for _, part in cached.parts do
		if not part.Parent then
			continue
		end

		const frame = world(part)
		if not part.CFrame:FuzzyEq(frame, 1e-5) then
			table.insert(parts, part)
			table.insert(frames, frame)
			moved[part] = true
		end
	end

	local loose = false
	for _, part in parts do
		if not part.Anchored then
			const root = part.AssemblyRootPart
			if not root or root == part or not root.Anchored or not moved[root] then
				loose = true
				break
			end
		end
	end

	if loose then
		table.clear(parts)
		table.clear(frames)
		for _, part in cached.parts do
			if part.Parent then
				table.insert(parts, part)
				table.insert(frames, world(part))
			end
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	return #parts
end

function Pose.capture(rig)
	local snapshot = {}
	for _, item in RigTraversal.rigDescendants(rig) do
		if item:IsA("Motor6D") then
			snapshot[item] = { C0 = item.C0, Transform = item.Transform }
		elseif item:IsA("JointInstance") then
			snapshot[item] = { C0 = item.C0 }
		elseif item:IsA("Bone") or item:IsA("AnimationConstraint") then
			snapshot[item] = { Transform = item.Transform }
		elseif item:IsA("Attachment") then
			snapshot[item] = { CFrame = item.CFrame }
		elseif item:IsA("BasePart") then
			snapshot[item] = { CFrame = item.CFrame }
		end
	end

	return snapshot
end

function Pose.restore(rig, snapshot)
	local parts, frames = {}, {}
	for item, properties in snapshot do
		if not item.Parent then
			continue
		end

		if item:IsA("BasePart") then
			table.insert(parts, item)
			table.insert(frames, properties.CFrame)
		else
			for property, value in properties do
				item[property] = value
			end
		end
	end

	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

function Pose.stampToken(rig)
	local token = rig:GetAttribute(STAMP_TOKEN)
	if typeof(token) ~= "string" then
		token = game:GetService("HttpService"):GenerateGUID(false)
		rig:SetAttribute(STAMP_TOKEN, token)
	end

	return token
end

function Pose.claimStamp(rig, object)
	if typeof(rig) ~= "Instance" or typeof(object) ~= "Instance" then
		return
	end

	const token = Pose.stampToken(rig)
	if object:GetAttribute(STAMP_TOKEN) ~= token then
		object:SetAttribute(STAMP_TOKEN, token)
	end
end

function Pose.releaseStamp(object)
	if object:GetAttribute(STAMP_TOKEN) ~= nil then
		object:SetAttribute(STAMP_TOKEN, nil)
	end
end

local function stampKind(object)
	if object:GetAttribute("EclipseArmatureSkinningHelper") then
		return nil
	end

	if object:IsA("BasePart") then
		return PART_STAMPS, "EclipseAnimatorDefaultSize"
	elseif object:IsA("Motor6D") then
		return JOINT_STAMPS, not object:GetAttribute("EclipseConstraintProxy") and "EclipseAnimatorDefaultC0"
	elseif object:IsA("Bone") then
		return JOINT_STAMPS, "EclipseAnimatorDefaultC0"
	elseif object:IsA("JointInstance") then
		return JOINT_STAMPS, nil
	end

	return nil
end

local function dropStamps(object, names)
	for _, name in names do
		if object:GetAttribute(name) ~= nil then
			object:SetAttribute(name, nil)
		end
	end

	Pose.releaseStamp(object)
end

function Pose.dropForeignStamps(rig)
	if typeof(rig) ~= "Instance" or not rig:IsA("Model") then
		return
	end

	const token = rig:GetAttribute(STAMP_TOKEN)
	const legacy = {}
	const complete = { joint = true, part = true }
	for _, object in RigTraversal.rigDescendants(rig) do
		const names, primary = stampKind(object)
		if not names then
			continue
		end

		const group = object:IsA("BasePart") and "part" or "joint"
		const owner = object:GetAttribute(STAMP_TOKEN)
		local stamped = false
		for _, name in names do
			if
				object:GetAttribute(name) ~= nil
				and not (primary and owner == nil and token == nil and name == "EclipseRigRestC0")
			then
				stamped = true
				break
			end
		end

		if primary and object:GetAttribute(primary) == nil then
			complete[group] = false
		end

		if not stamped then
			continue
		end

		if owner ~= nil or token ~= nil then
			if owner ~= token or typeof(token) ~= "string" then
				dropStamps(object, names)
			end
		elseif not primary then
			dropStamps(object, names)
		else
			table.insert(legacy, { object, names, group })
		end
	end

	for _, entry in legacy do
		if not complete[entry[3]] then
			dropStamps(entry[1], entry[2])
		end
	end
end

function Pose.recoverStamps(scope, state, budget)
	if typeof(scope) == "Instance" and scope:IsA("Model") then
		Pose.dropForeignStamps(scope)
	end

	local models = {}

	local function owner(item)
		local model = item:FindFirstAncestorOfClass("Model")
		if model then
			models[model] = true
		end
	end

	local objects = RigTraversal.descendants(scope, budget)
	if scope then
		table.insert(objects, 1, scope)
	end

	for _, item in objects do
		if budget then budget() end
		if item:GetAttribute("EclipseArmatureSkinningHelper") then
			continue
		end

		if
			item:IsA("Motor6D")
			and item:GetAttribute(HOME_C1) ~= nil
			and not (state and state.DefaultPose[item])
		then
			Pose.restoreLoadedC1(item)
			owner(item)
		end

		local saved = item:GetAttribute("EclipseAnimatorDefaultC0")
		if
			item:IsA("Motor6D")
			and typeof(saved) == "CFrame"
			and not (state and state.DefaultPose[item])
		then
			item.C0, item.Transform = saved, CFrame.identity
			Pose.rememberRest(item, saved)
			owner(item)
		elseif item:IsA("Bone") and typeof(saved) == "CFrame" then
			local adapter = require("BoneMotor").get(item)
			if not (state and state.DefaultPose[adapter]) then
				item.Transform = item.CFrame:Inverse() * saved
				Pose.rememberRest(item, saved)
			end
		elseif item:IsA("BasePart") and not (state and state.DefaultSize[item]) then
			local size = item:GetAttribute("EclipseAnimatorDefaultSize")
			if typeof(size) == "Vector3" then
				item.Size = size
				owner(item)
			end
		end
	end

	for model in models do
		if budget then budget() end
		Pose.assemble(model)
	end
end

function Pose.reset(rig, defaults, boneMotor)
	for _, item in RigTraversal.rigDescendants(rig) do
		if item:GetAttribute("EclipseArmatureSkinningHelper") then
			continue
		end

		if item:IsA("Motor6D") then
			local rest = defaults and defaults[item]
				or item:GetAttribute("EclipseAnimatorDefaultC0")
				or item:GetAttribute("EclipseRigRestC0")

			if not rest and item.Part0 and item.Part1 then
				local a = item.Part0:FindFirstChild(item.Name .. "RigAttachment")
				local b = item.Part1:FindFirstChild(item.Name .. "RigAttachment")
				if a and b and a:IsA("Attachment") and b:IsA("Attachment") then
					rest = a.CFrame
				end
			end

			rest = rest or classicRest(rig, item)
			if rest then
				item.C0 = rest
				Pose.rememberRest(item, rest)
			end

			item.Transform = CFrame.identity
		elseif item:IsA("JointInstance") then
			local rest = defaults and defaults[item] or item:GetAttribute("EclipseRigRestC0")
			if typeof(rest) == "CFrame" then
				item.C0 = rest
				Pose.rememberRest(item, rest)
			end
		elseif item:IsA("Bone") then
			local rest = defaults and boneMotor and defaults[boneMotor.get(item)]
				or item:GetAttribute("EclipseAnimatorDefaultC0")
				or item:GetAttribute("EclipseRigRestC0")
			item.Transform = rest and item.CFrame:Inverse() * rest or CFrame.identity
		elseif item:IsA("AnimationConstraint") then
			local rest = item:GetAttribute("EclipseConstraintRestC0")
			if typeof(rest) == "CFrame" and item.Attachment0 then
				local savedScale = rig:GetAttribute("EclipseNativeJointScale") or rig:GetScale()
				item.Attachment0.CFrame = CFrame.new(rest.Position * (rig:GetScale() / savedScale))
					* rest.Rotation
			end

			item.Transform = CFrame.identity
		end
	end

	Pose.assemble(rig)
end

return Pose
