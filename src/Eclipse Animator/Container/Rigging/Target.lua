--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local State = require("State")
local Raw = require("RawState").Timeline
local Interp = require("Interp")
local GraphCurves = require("GraphCurves")
local Http = game:GetService("HttpService")
local Target = {}
Target.COLOR = Color3.fromRGB(184, 142, 239)
local objects = setmetatable({}, { __mode = "v" })
local lastWorld = {}
local live = setmetatable({}, { __mode = "k" })

function Target.is(motor)
	return typeof(motor) == "Instance"
		and motor:IsA("Motor6D")
		and motor:GetAttribute("EclipseCamTarget") == true
end

function Target.isAttachment(motor)
	return typeof(motor) == "Instance"
		and motor:GetAttribute("EclipseCameraAttachmentTrack") == true
end

function Target.ensureAttachment(rig)
	local root = rig:FindFirstChild("RootPart")
	if not root or not root:FindFirstChild("CamPart") or not root:FindFirstChild("FovPart") then
		return
	end

	local motor = root:FindFirstChild("AttachToPart")
	if not motor then
		local part = Instance.new("Part")
		part.Name = "AttachToPart"
		part.Size = Vector3.one * 0.1
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = rig
		motor = Instance.new("Motor6D")
		motor.Name = "AttachToPart"
		motor.Part0 = root
		motor.Part1 = part
		motor.Parent = root
	end

	motor:SetAttribute("EclipseCameraAttachment", true)
	motor:SetAttribute("EclipseCameraAttachmentTrack", true)
	motor:SetAttribute("EclipseAnimatorDefaultC0", CFrame.identity)
	return motor
end

function Target.attachmentKey(rig, time)
	local root = rig and rig:FindFirstChild("RootPart")
	local motor = root and root:FindFirstChild("AttachToPart")
	if not motor or not Target.isAttachment(motor) or motor:GetAttribute("EclipseDisabled") then
		return
	end

	local bucket = require("Layers").cameraMetadataBucket(Raw, motor, time, "CamAttachTarget")
	local key = Target.previous(bucket, time)

	if key and key.Time <= time and key.CamAttachTarget ~= nil then
		return key, motor
	end
end

function Target.attachmentObject(rig, time)
	local key = Target.attachmentKey(rig, time or Raw.CurrentTime)
	local object = key and Target.resolve(key.CamAttachTarget)
	if
		object
		and object.Parent
		and (object:IsA("BasePart") or object:IsA("Bone"))
		and not object:IsDescendantOf(rig)
	then
		return object, key.CamAttachTarget
	end
end

function Target.attachmentFrame(rig, time)
	local object, link = Target.attachmentObject(rig, time)
	if not object then
		return
	end

	local motor = rig.RootPart:FindFirstChild("AttachToPart")
	local offset = require("PivotSpace").get(motor) or Vector3.zero
	if time == nil then
		local world = object:IsA("Bone") and object.TransformedWorldCFrame or object.CFrame
		return world * CFrame.new(offset)
	end

	local Parenting = require("Parenting")
	local worldAt = Parenting.newEvaluator(
		{},
		Raw.Keyframes,
		Raw.DefaultPose,
		Raw.DefaultWorldPose,
		Raw.ParentingDefaults,

		function(motor, at)
			return State.Timeline:EvaluateMotorC0(motor, at)
		end
	).worldAt
	return Target.linkWorld(link, time, Target.parentSampler(worldAt)) * CFrame.new(offset)
end

function Target.hasAttachment(rig, keys)
	local root = rig:FindFirstChild("RootPart")
	local motor = root and root:FindFirstChild("AttachToPart")
	for _, key in motor and (keys or Raw.Keyframes)[motor] or {} do
		if key.CamAttachTarget ~= nil then
			return true
		end
	end

	return false
end

function Target.ensure(rig)
	Target.ensureAttachment(rig)
	local root = rig:FindFirstChild("RootPart")
	if not root or not root:FindFirstChild("CamPart") or not root:FindFirstChild("FovPart") then
		return
	end

	local motor = root:FindFirstChild("CamTarget")
	if motor then
		return motor
	end

	local part = Instance.new("Part")
	part.Name = "CamTarget"
	part.Size = Vector3.one * 0.45
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = rig
	motor = Instance.new("Motor6D")
	motor.Name = "CamTarget"
	motor.Part0 = root
	motor.Part1 = part
	motor.C0 = root.CamPart.C0 * CFrame.new(0, 0, -2)
	motor.Parent = root
	motor:SetAttribute("EclipseCamTarget", true)
	motor:SetAttribute("EclipseAnimatorDefaultC0", motor.C0)
	part.CFrame = root.CFrame * motor.C0
	return motor
end

local function path(object, root)
	local out = {}
	while object and object ~= root do
		local parent = object.Parent
		if not parent then
			return
		end

		local index = 0
		for _, child in parent:GetChildren() do
			if child.Name == object.Name and child.ClassName == object.ClassName then
				index += 1
			end

			if child == object then
				break
			end
		end

		table.insert(out, 1, { name = object.Name, class = object.ClassName, index = index })
		object = parent
	end

	return object == root and out or nil
end

local function walk(root, steps)
	for _, step in steps or {} do
		local count, found = 0, nil
		for _, child in root:GetChildren() do
			if child.Name == step.name and child.ClassName == step.class then
				count += 1
				if count == step.index then
					found = child
					break
				end
			end
		end

		if not found then
			return
		end

		root = found
	end

	return root
end

function Target.reference(object)
	if not object then
		return false
	end

	assert(object:IsA("BasePart") or object:IsA("Bone"), "Choose a part or bone")
	local id = object:GetAttribute("EclipseCameraTargetId")
	if not id then
		id = Http:GenerateGUID(false)
		object:SetAttribute("EclipseCameraTargetId", id)
	end

	objects[id] = object
	local rigId, steps
	for _, rig in State.getAllRigs() do
		if object == rig or object:IsDescendantOf(rig) then
			rigId = rig:GetAttribute("EclipseTrackId")
			if not rigId then
				rigId = Http:GenerateGUID(false)
				rig:SetAttribute("EclipseTrackId", rigId)
			end

			steps = path(object, rig)
			break
		end
	end

	return {
		id = id,
		rigId = rigId,
		path = steps,
		scene = path(object, workspace),
		rest = object:IsA("Bone") and object.TransformedWorldCFrame or object.CFrame,
		label = object.Name,
	}
end

local misses = {}

local function within(object, id)
	local node = object
	while node and node ~= game do
		if node:GetAttribute("EclipseTrackId") == id then
			return true
		end

		node = node.Parent
	end

	return false
end

local function tagged(object, link)
	return object ~= nil
		and object:GetAttribute("EclipseCameraTargetId") == link.id
		and (not link.rigId or within(object, link.rigId))
end

function Target.resolve(link)
	if typeof(link) ~= "table" then
		return
	end

	local object = link.id and objects[link.id]
	if object and object:IsDescendantOf(workspace) then
		return object
	end

	const scene = link.scene and walk(workspace, link.scene) or nil
	object = if tagged(scene, link) then scene else nil
	local fallback
	if not object then
		for _, rig in State.getAllRigs() do
			if link.rigId and rig:GetAttribute("EclipseTrackId") == link.rigId then
				const found = walk(rig, link.path)
				if tagged(found, link) then
					object = found
					break
				end

				fallback = fallback or found
			end
		end
	end

	if not object and link.id and (misses[link.id] or 0) < os.clock() then
		const matches = {}
		for _, candidate in workspace:GetDescendants() do
			if (candidate:IsA("BasePart") or candidate:IsA("Bone")) and tagged(candidate, link) then
				table.insert(matches, candidate)
			end
		end

		if #matches == 1 then
			object = matches[1]
		else
			misses[link.id] = os.clock() + 2
		end
	end

	object = object or fallback or scene
	if object and link.id then
		objects[link.id] = object
	end

	return object
end

local rigidLayouts = setmetatable({}, { __mode = "k" })

local function rigidLayout(root)
	local entry = rigidLayouts[root]
	if entry and not entry.dirty then
		return entry.links
	end

	if entry then
		for _, connection in entry.connections do
			connection:Disconnect()
		end
	end

	entry = { links = {}, connections = {}, dirty = false }
	rigidLayouts[root] = entry

	local function dirty()
		entry.dirty = true
	end

	local function watch(signal)
		table.insert(entry.connections, signal:Connect(dirty))
	end

	local function edge(a, b, joint, kind)
		if not a or not b or a == b or not a:IsA("BasePart") or not b:IsA("BasePart") then
			return
		end

		local link = { a = a, b = b, joint = joint, kind = kind }
		if kind == "constraint" then
			link.offset = a.CFrame:ToObjectSpace(b.CFrame)
		end

		entry.links[a] = entry.links[a] or {}
		table.insert(entry.links[a], link)
		entry.links[b] = entry.links[b] or {}
		table.insert(entry.links[b], link)
	end

	for _, object in require("RigTraversal").rigDescendants(root) do
		if object:IsA("Weld") or object:IsA("ManualWeld") or object:IsA("WeldConstraint") then
			for _, property in { "Part0", "Part1", "Enabled" } do
				watch(object:GetPropertyChangedSignal(property))
			end

			if object.Enabled then
				edge(
					object.Part0,
					object.Part1,
					object,
					object:IsA("WeldConstraint") and "constraint" or "joint"
				)
			end
		elseif object:IsA("RigidConstraint") then
			for _, property in { "Attachment0", "Attachment1", "Enabled" } do
				watch(object:GetPropertyChangedSignal(property))
			end

			local a, b = object.Attachment0, object.Attachment1
			if a then
				watch(a.AncestryChanged)
			end

			if b then
				watch(b.AncestryChanged)
			end

			if object.Enabled and a and b then
				edge(a.Parent, b.Parent, object, "attachment")
			end
		end
	end

	watch(root.DescendantAdded)
	watch(root.DescendantRemoving)
	table.insert(
		entry.connections,
		root.Destroying:Connect(function()
			for _, connection in entry.connections do
				connection:Disconnect()
			end

			rigidLayouts[root] = nil
		end)
	)
	return entry.links
end

local function rigidLayoutsFor(object)
	local layouts, roots = {}, {}
	for _, rig in State.getAllRigs() do
		if not roots[rig] then
			roots[rig] = true
			table.insert(layouts, rigidLayout(rig))
		end
	end

	local owner = object:FindFirstAncestorOfClass("Model") or object
	if not roots[owner] then
		table.insert(layouts, rigidLayout(owner))
	end

	return layouts
end

local function rigidWorld(object, time, worldAt)
	if not worldAt or not object:IsA("BasePart") then
		return nil
	end

	local layouts = rigidLayoutsFor(object)
	local visited = {}

	local function resolve(part)
		if not part.Parent or visited[part] then
			return nil
		end

		visited[part] = true
		local motor = Raw.MotorByPart[part]
		if motor then
			return worldAt(motor, time)
		end

		for _, links in layouts do
			for _, link in links[part] or {} do
				local joint = link.joint
				if not joint.Parent or not joint.Enabled then
					continue
				end

				local parent = part == link.b and link.a or link.b
				local frame = resolve(parent)
				if frame then
					local offset = link.offset
					if link.kind == "joint" then
						offset = joint.C0 * joint.C1:Inverse()
					elseif link.kind == "attachment" then
						offset = joint.Attachment0.CFrame * joint.Attachment1.CFrame:Inverse()
					end

					return frame * (part == link.b and offset or offset:Inverse())
				end
			end
		end

		return nil
	end

	return resolve(object)
end

function Target.dependsOn(object, motor, time)
	if not object then
		return false
	end

	local Properties = require("Properties")
	local Parenting = require("Parenting")
	local child = Properties.is(motor) and motor.Rig or motor.Part1
	local layouts, seen = rigidLayoutsFor(object), {}

	local function visit(part)
		if not part or not part.Parent then
			return false
		end

		if part == child or part:IsDescendantOf(child) then
			return true
		end

		if seen[part] then
			return false
		end

		seen[part] = true
		local joint = Raw.MotorByPart[part]
		if not joint then
			for _, property in Properties.list(part, true) do
				if property.PropertyId == "CFrame" then
					joint = property
					break
				end
			end
		end

		if joint then
			local link = Target.childAt(joint, time)
			if link then
				return not link.world and visit(Target.resolve(link))
			end

			return not Properties.is(joint) and visit(Parenting.realPart0(joint))
		end

		for _, links in layouts do
			for _, link in links[part] or {} do
				if
					link.joint.Parent
					and link.joint.Enabled
					and visit(part == link.b and link.a or link.b)
				then
					return true
				end
			end
		end

		if part:IsA("Bone") then
			return visit(part.Parent)
		end

		return false
	end

	return visit(object)
end

function Target.linkWorld(link, time, worldAt)
	if typeof(link) ~= "table" or link.world == true then
		return CFrame.identity
	end

	local object = Target.resolve(link)
	if not object then
		return lastWorld[link.id] or link.rest or CFrame.identity
	end

	local motor = Raw.MotorByPart[object]
	local world = motor and worldAt and worldAt(motor, time)
		or rigidWorld(object, time, worldAt)
		or object:IsA("Bone") and object.TransformedWorldCFrame
		or object.CFrame
	lastWorld[link.id] = world
	return world
end

local PoseMode = require("cache")
local indexes = setmetatable({}, { __mode = "k" })

local function keyIndex(bucket)
	if not bucket then
		return nil
	end

	local revision = PoseMode.revision()
	local entry = indexes[bucket]
	if entry and entry.revision == revision then
		return entry
	end

	entry = { revision = revision, keys = {}, enabled = {}, hasChild = false }
	for _, key in bucket do
		if key.Disabled then
			continue
		end

		if
			type(key.Time) ~= "number"
			or key.Time ~= key.Time
			or math.abs(key.Time) == math.huge
		then
			entry.invalid = true
			continue
		end

		local row = { key = key, time = key.Time }
		if not key.GraphOnly then
			table.insert(entry.keys, row)
			entry.hasChild = entry.hasChild or not not key.CamTargetParent
		end

		if typeof(key.CamTargetEnabled) == "boolean" then
			table.insert(entry.enabled, row)
		end
	end

	for _, rows in { entry.keys, entry.enabled } do
		table.sort(rows, function(a, b)
			return a.time < b.time
		end)
		for n = 2, #rows do
			if rows[n].time == rows[n - 1].time then
				entry.invalid = true
				break
			end
		end
	end

	indexes[bucket] = entry
	return entry
end

function Target.previous(bucket, time)
	local entry = keyIndex(bucket)
	if entry and not entry.invalid then
		local p, n = Interp.search(entry.keys, time)
		return entry.keys[p] and entry.keys[p].key, entry.keys[n] and entry.keys[n].key
	end

	local previous, following
	for _, key in bucket or {} do
		if key.Disabled or key.GraphOnly then
			continue
		end

		if key.Time <= time and (not previous or key.Time > previous.Time) then
			previous = key
		end

		if key.Time >= time and (not following or key.Time < following.Time) then
			following = key
		end
	end

	return previous, following
end

local sampling = {}

local function canSharePropertySamples(rig, context)
	if context.eligible[rig] ~= nil then
		return context.eligible[rig]
	end

	local source = require("LimbIK").getRig(rig)
	local eligible = source ~= nil
	for _, motor in source and source.motors or {} do
		local seen = {}
		local current = motor
		while current and not seen[current] do
			seen[current] = true
			local part = require("Parenting").realPart0(current)
			if part and (typeof(part) ~= "Instance" or not part:IsDescendantOf(rig)) then
				eligible = false
				break
			end

			if Target.hasChild(Raw.Keyframes[current]) then
				eligible = false
			end

			if not eligible then
				break
			end

			current = part and Raw.MotorByPart[part]
		end

		if not eligible then
			break
		end
	end

	context.eligible[rig] = eligible
	return eligible
end

function Target.propertySampleCache()
	return { poses = {}, eligible = {} }
end

function Target.invalidatePropertySamples(context, target)
	if not context then
		return
	end

	for rig in context.poses do
		if rig == target or rig:IsDescendantOf(target) or target:IsDescendantOf(rig) then
			context.poses[rig] = nil
		end
	end
end

function Target.parentSampler(worldAt, propertySamples)
	local sampled, owners = {}, {}

	local function parentAt(parent, sampleTime)
		local rig = owners[parent]
		if rig == nil then
			rig = false
			for _, candidate in State.getAllRigs() do
				if parent.Part1:IsDescendantOf(candidate) then
					rig = candidate
					break
				end
			end

			owners[parent] = rig
		end

		if rig and State.Timeline and State.Timeline.EvaluateMotorC0 then
			if sampling[rig] and sampling[rig][sampleTime] then
				return worldAt(parent, sampleTime)
			end

			local cache = propertySamples
					and canSharePropertySamples(rig, propertySamples)
					and propertySamples.poses
				or sampled
			cache[rig] = cache[rig] or {}
			local atTime = cache[rig][sampleTime]
			if not atTime then
				atTime = {}
				cache[rig][sampleTime] = atTime
			end

			local poses = atTime[parent]
			if poses == nil then
				local active = sampling[rig] or {}
				sampling[rig] = active
				active[sampleTime] = true
				local ok, result = xpcall(function()
					return require("LimbIK").evaluate(rig, sampleTime, function(motor, at)
						return State.Timeline:EvaluateMotorC0(motor, at)
					end, parent)
				end, debug.traceback)
				active[sampleTime] = nil
				if next(active) == nil then
					sampling[rig] = nil
				end

				if not ok then
					error(result, 0)
				end

				poses = result or false
				atTime[parent] = poses
			end

			if poses and poses[parent] then
				return poses[parent]
			end
		end

		return worldAt(parent, sampleTime)
	end

	return parentAt
end

local function blend(time, bucket, keyWorld, parentAt, worldFrameAt, owner)
	local function frameAt(link, at, anchor)
		if link and link.world and worldFrameAt then
			return worldFrameAt(at)
		end

		if
			owner
			and link
			and not link.world
			and Target.dependsOn(Target.resolve(link), owner, at)
		then
			return anchor or link.rest or CFrame.identity
		end

		return Target.linkWorld(link, at, parentAt)
	end

	local a, b = Target.previous(bucket, time)
	local active = a and a.CamTargetParent or false
	local activeAnchor = a and a.CamTargetAnchor
	local frame = frameAt(active, time, activeAnchor)
	local converted = {}

	local function convert(key)
		if not key then
			return
		end

		local copy = table.clone(key)
		local world = keyWorld(key)
		if key.CamTargetParent then
			local anchor = key.CamTargetParent.world and worldFrameAt and key.MasterWorld
				or key.CamTargetAnchor
			world = frameAt(key.CamTargetParent, key.Time, key.CamTargetAnchor)
				* (anchor or CFrame.identity):Inverse()
				* world
		end

		copy.C0 = frameAt(active, key.Time, activeAnchor):ToObjectSpace(world)
		copy.Channels = nil
		copy.GraphCurves = nil
		copy.PathTangentIn = nil
		copy.PathTangentOut = nil
		converted[key.Frame or key.Time] = copy
		return copy
	end

	convert(a)
	convert(b)
	local before, after
	local entry = keyIndex(bucket)
	if entry and not entry.invalid then
		local p, n = Interp.search(entry.keys, time)
		before = entry.keys[p - 1] and entry.keys[p - 1].key
		after = entry.keys[n + 1] and entry.keys[n + 1].key
	else
		for _, key in bucket do
			if key.Disabled or key.GraphOnly then
				continue
			end

			if a and key.Time < a.Time and (not before or key.Time > before.Time) then
				before = key
			end

			if b and key.Time > b.Time and (not after or key.Time < after.Time) then
				after = key
			end
		end
	end

	convert(before)
	convert(after)
	local pose
	if a and b and a ~= b then
		pose = Interp.cframe(
			converted,
			converted[a.Frame or a.Time],
			converted[b.Frame or b.Time],
			(time - a.Time) / (b.Time - a.Time),
			"C0"
		)
	else
		local key = a or b
		pose = key and converted[key.Frame or key.Time].C0
	end

	return frame, pose
end

function Target.evaluate(motor, time, keys, defaults, worldAt, parentAt)
	local frame, pose = blend(time, keys[motor] or {}, function(key)
		return motor.Part0.CFrame * (key.C0 or defaults[motor] or motor.C0) * motor.C1:Inverse()
	end, parentAt or Target.parentSampler(worldAt), nil, motor)
	return frame
		* (
			pose
			or frame:ToObjectSpace(
				motor.Part0.CFrame * (defaults[motor] or motor.C0) * motor.C1:Inverse()
			)
		)
end

function Target.hasChild(bucket)
	local entry = keyIndex(bucket)
	if entry and not entry.invalid then
		return entry.hasChild
	end

	for _, key in bucket or {} do
		if key.CamTargetParent and not key.Disabled and not key.GraphOnly then
			return true
		end
	end

	return false
end

function Target.childAt(motor, time)
	if Target.is(motor) or not Target.hasChild(Raw.Keyframes[motor]) then
		return nil
	end

	local key = Target.previous(Raw.Keyframes[motor], time)
	return key and key.CamTargetParent or nil
end

function Target.evaluateChild(time, bucket, keyWorld, worldAt, parentAt, worldFrameAt, owner)
	local frame, pose = blend(
		time,
		bucket,
		keyWorld,
		parentAt or Target.parentSampler(worldAt),
		worldFrameAt,
		owner
	)
	return pose and frame * pose
end

function Target.cameraPart(model)
	for _, item in model:GetDescendants() do
		if item.Name ~= "Render_Target" then
			continue
		end

		if
			item:IsA("ObjectValue")
			and item.Value
			and (item.Value:IsA("BasePart") or item.Value:IsA("Bone"))
		then
			return item.Value
		end

		if item:IsA("StringValue") and item.Parent:IsA("BasePart") then
			return item.Parent
		end
	end

	local named = model:FindFirstChild("CameraPart", true)
	if named and named:IsA("BasePart") then
		return named
	end

	return nil
end

function Target.eye(model, head)
	if head then
		local part = model:FindFirstChild("Head", true)
		if part and (part:IsA("BasePart") or part:IsA("Bone")) then
			return part
		end
	end

	local explicit = Target.cameraPart(model)
	if explicit then
		return explicit
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local followed = setmetatable({}, { __mode = "k" })

local function objectWorld(object)
	local motor = Raw.MotorByPart[object]
	if motor then
		return require("Parenting").worldOf(motor, Raw.MotorByPart)
	end

	return object:IsA("Bone") and object.TransformedWorldCFrame or object.CFrame
end

function Target.captureChildLock(motor, world)
	local link = Target.childAt(motor, Raw.CurrentTime)
	local object = link and not link.world and Target.resolve(link)
	if not object or Target.dependsOn(object, motor, Raw.CurrentTime) then
		return nil
	end

	return { object = object, relative = objectWorld(object):ToObjectSpace(world) }
end

function Target.restoreChildLock(motor, lock)
	if not lock or not lock.object.Parent then
		return nil
	end

	local world = objectWorld(lock.object)
	followed[motor] = {
		object = lock.object,
		world = world,
		master = require("MasterControl").worldDelta(motor) or CFrame.identity,
	}
	return world * lock.relative
end

local function follow(motor, from, to, carried)
	local Parenting = require("Parenting")
	local parent = Raw.MotorByPart[Parenting.realPart0(motor)]
	local base = parent and Parenting.worldOf(parent, Raw.MotorByPart) or motor.Part0.CFrame
	motor.C0 = base:Inverse()
		* to
		* from:Inverse()
		* (carried or CFrame.identity):Inverse()
		* base
		* motor.C0
	State.lastCFrames[motor] = motor.C0
end

function Target.appliedChildren(motors, time, evaluator)
	for motor, entry in followed do
		if not entry.property then
			followed[motor] = nil
		elseif entry.time == time and entry.object.Parent then
			entry.world = objectWorld(entry.object)
		end
	end

	if Raw.Playing and not evaluator then
		return
	end

	local parentAt = evaluator.parentAt or Target.parentSampler(evaluator.worldAt)
	for _, motor in motors do
		if
			(
				typeof(motor) ~= "Instance"
				and not (
					typeof(motor) == "table"
					and (motor.IsEclipseR6Control or motor.IsEclipseMasterControl)
				)
			) or not evaluator.childAt(motor, time)
		then
			continue
		end

		local link = Target.childAt(motor, time)
		local object = link and not link.world and Target.resolve(link)
		if
			not object
			or not object:IsDescendantOf(workspace)
			or Target.dependsOn(object, motor, time)
		then
			continue
		end

		local evaluated = Target.linkWorld(link, time, parentAt)
		local actual = objectWorld(object)
		if
			(evaluated.Position - actual.Position).Magnitude > 1e-4
			or evaluated.LookVector:Dot(actual.LookVector) < 0.99999
			or evaluated.UpVector:Dot(actual.UpVector) < 0.99999
		then
			follow(motor, evaluated, actual)
		end

		followed[motor] = {
			object = object,
			world = actual,
			master = require("MasterControl").worldDelta(motor) or CFrame.identity,
		}
	end
end

function Target.watchChild(motor, time)
	local link = Target.childAt(motor, time)
	local object = link and not link.world and Target.resolve(link)
	followed[motor] = object
			and not Target.dependsOn(object, motor, time)
			and {
				object = object,
				world = objectWorld(object),
				master = require("MasterControl").worldDelta(motor) or CFrame.identity,
			}
		or nil
end

function Target.watchProperty(motor, time)
	if math.abs(time - Raw.CurrentTime) > 1e-6 then
		return
	end

	local link = Target.childAt(motor, time)
	local object = link and not link.world and Target.resolve(link)
	if not object then
		followed[motor] = nil
		return
	end

	followed[motor] = { object = object, world = objectWorld(object), property = true, time = time }
end

function Target.remapLive(mapping)
	for id, object in objects do
		if mapping[object] then
			objects[id] = mapping[object]
		end
	end

	for motor, entry in followed do
		if mapping[motor] or mapping[entry.object] then
			followed[motor] = nil
		end
	end

	table.clear(live)
	table.clear(lastWorld)
end

function Target.releaseRig(rig)
	for motor in followed do
		local part = motor.Part1
		if
			motor.Parent == rig
			or typeof(part) == "Instance" and (part == rig or part:IsDescendantOf(rig))
		then
			followed[motor] = nil
		end
	end

	live[rig] = nil
end

function Target.syncChildren()
	if Raw.Playing then
		return
	end

	for motor, entry in followed do
		if
			not motor.Parent
			or not entry.object.Parent
			or Target.dependsOn(entry.object, motor, Raw.CurrentTime)
		then
			followed[motor] = nil
			continue
		end

		local world = objectWorld(entry.object)
		local master = not entry.property
			and (require("MasterControl").worldDelta(motor) or CFrame.identity)
		if world ~= entry.world or master and master ~= entry.master then
			if entry.property then
				require("Properties").setValue(motor, world * entry.world:Inverse() * motor.C0)
				State.lastCFrames[motor] = motor.C0
			else
				follow(motor, entry.world, world, master * (entry.master or master):Inverse())
			end

			entry.world = world
			entry.master = master
		end
	end
end

function Target.enabledAt(rig, time)
	if rig:GetAttribute("EclipseTrackTarget") == false then
		return false
	end

	local motor = rig.RootPart:FindFirstChild("CamTarget")
	local latest
	local source = require("Layers").cameraMetadataBucket(Raw, motor, time, "CamTargetEnabled")
	local entry = keyIndex(source)
	if entry and not entry.invalid then
		local p = Interp.search(entry.enabled, time)
		latest = entry.enabled[p] and entry.enabled[p].key
	else
		for _, key in source or {} do
			if
				not key.Disabled
				and typeof(key.CamTargetEnabled) == "boolean"
				and key.Time <= time
				and (not latest or key.Time > latest.Time)
			then
				latest = key
			end
		end
	end

	if latest then
		return latest.CamTargetEnabled
	end

	local value = rig:GetAttribute("EclipseCamTargetDefaultEnabled")
	if value ~= nil then
		return value
	end

	return rig:GetAttribute("EclipseTrackTarget") == true
end

local function evaluatorWorld()
	local Parenting = require("Parenting")
	if State.Timeline and State.Timeline.EvaluateMotorC0 then
		return Parenting.newEvaluator(
			{},
			Raw.Keyframes,
			Raw.DefaultPose,
			Raw.DefaultWorldPose,
			Raw.ParentingDefaults,

			function(parent, time)
				return State.Timeline:EvaluateMotorC0(parent, time)
			end
		).worldAt
	end

	return function(parent)
		return Parenting.worldOf(parent, Raw.MotorByPart)
	end
end

local function captureParentAt(time)
	if
		not Raw.Exporting
		and not State.LoadingProject
		and type(time) == "number"
		and math.abs(time - Raw.CurrentTime) < 1e-7
	then
		local Parenting = require("Parenting")
		return function(parent)
			return Parenting.worldOf(parent, Raw.MotorByPart)
		end
	end

	return Target.parentSampler(evaluatorWorld())
end

function Target.captureProperty(motor, key)
	if key.CamTargetParent == nil then
		local previous = Target.previous(Raw.Keyframes[motor], key.Time - 1e-7)
		if not (previous and previous.CamTargetParent) then
			return
		end

		key.CamTargetParent = previous.CamTargetParent
	end

	if not key.CamTargetParent then
		key.CamTargetAnchor = nil
		return
	end

	key.CamTargetAnchor = Target.linkWorld(key.CamTargetParent, key.Time, captureParentAt(key.Time))
end

function Target.childWorld(time, bucket, keyWorld, propertySamples)
	local worldAt = evaluatorWorld()
	return Target.evaluateChild(
		time,
		bucket,
		keyWorld,
		worldAt,
		Target.parentSampler(worldAt, propertySamples)
	)
end

function Target.captureChild(motor, key, c0)
	if key.CamTargetParent == nil then
		local previous = Target.previous(Raw.Keyframes[motor], key.Time - 1e-7)
		if not (previous and previous.CamTargetParent) then
			return
		end

		key.CamTargetParent = previous.CamTargetParent
	end

	if not key.CamTargetParent then
		key.CamTargetAnchor = nil
		return
	end

	local Parenting = require("Parenting")
	local parentMotor = Raw.MotorByPart[Parenting.realPart0(motor)]
	local parentWorld = parentMotor and Parenting.worldOf(parentMotor, Raw.MotorByPart)
		or motor.Part0.CFrame
	key.Parented = false
	key.WorldCFrame = parentWorld * (c0 or key.C0 or motor.C0) * motor.C1:Inverse()
	key.CamTargetAnchor = Target.linkWorld(key.CamTargetParent, key.Time, captureParentAt(key.Time))
end

function Target.capture(motor, key, c0)
	local camera = require("CameraRig")
	if camera.isTransform(motor) and key.CamTrackTo == nil then
		local previous = Target.previous(Raw.Keyframes[motor], key.Time - 1e-7)
		key.CamTrackTo = previous and previous.CamTrackTo or 1
	end

	if not Target.is(motor) then
		return Target.captureChild(motor, key, c0)
	end

	if key.CamTargetEnabled == nil then
		key.CamTargetEnabled = Target.enabledAt(camera.owner(motor), key.Time - 1e-7)
	end

	if key.CamTargetParent == nil then
		local previous = Target.previous(Raw.Keyframes[motor], key.Time - 1e-7)
		key.CamTargetParent = previous and previous.CamTargetParent or false
	end

	key.CamTargetAnchor = Target.linkWorld(key.CamTargetParent, key.Time, captureParentAt(key.Time))
	key.Parented = true
	key.WorldCFrame = nil
end

function Target.keyEnabled(key)
	if typeof(key.CamTargetEnabled) == "boolean" then
		return key.CamTargetEnabled
	end

	return Target.enabledAt(require("CameraRig").owner(key.Motor), key.Time)
end

local weightMemo = {}

function Target.weight(rig, time)
	local motor = rig.RootPart:FindFirstChild("CamPart")
	local tick = os.clock()
	local source = require("Layers").cameraMetadataBucket(Raw, motor, time, "CamTrackTo")
	local compiled = source and GraphCurves.compile(source) or nil
	local revision = PoseMode.revision()
	if
		weightMemo.rig == rig
		and weightMemo.time == time
		and weightMemo.source == source
		and weightMemo.compiled == compiled
		and weightMemo.revision == revision
		and tick - weightMemo.at < 1 / 240
	then
		return weightMemo.value
	end

	local entry = keyIndex(source)
	local bucket = entry and entry.weights
	if not bucket then
		bucket = {}
		for frame, key in source or {} do
			if not key.Disabled and not key.GraphOnly then
				local copy = table.clone(key)
				copy.C0 = CFrame.new(math.clamp(key.CamTrackTo or 1, 0, 1), 0, 0)
				copy.Channels = nil
				copy.GraphCurves = nil
				bucket[frame] = copy
			end
		end

		if entry then
			entry.weights = bucket
		end
	end

	local a, b = Target.previous(bucket, time)
	local value = 1
	if a and b and a ~= b then
		value = math.clamp(
			Interp.cframe(bucket, a, b, (time - a.Time) / (b.Time - a.Time), "C0").X,
			0,
			1
		)
	elseif a or b then
		value = (a or b).C0.X
	end

	weightMemo.rig, weightMemo.time, weightMemo.source, weightMemo.compiled, weightMemo.at, weightMemo.value =
		rig, time, source, compiled, tick, value
	weightMemo.revision = revision
	return value
end

local function liveParent(rig, time)
	local root = rig:FindFirstChild("RootPart")
	local motor = root and root:FindFirstChild("CamTarget")
	if not motor then
		return
	end

	local source = require("Layers").cameraMetadataBucket(Raw, motor, time, "CamTargetParent")
	local key = Target.previous(source, time)
	local link = key and key.CamTargetParent
	if not link then
		return motor
	end

	local Parenting = require("Parenting")
	return motor,
		link,
		Target.linkWorld(link, time, function(parent)
			return Parenting.worldOf(parent, Raw.MotorByPart)
		end)
end

function Target.applied(rig, time)
	local motor, link, world = liveParent(rig, time)
	live[rig] = link and { motor = motor, id = link.id, time = time, world = world } or nil
end

function Target.syncLive(rig)
	local time = Raw.CurrentTime
	local motor, link, world = liveParent(rig, time)
	local previous = live[rig]
	if
		previous
		and link
		and previous.id == link.id
		and previous.time == time
		and previous.world ~= world
	then
		motor.C0 = motor.Part0.CFrame:Inverse()
			* world
			* previous.world:Inverse()
			* motor.Part0.CFrame
			* motor.C0
	end

	live[rig] = link and { motor = motor, id = link.id, time = time, world = world } or nil
end

function Target.frame(rig, base, time)
	base = Target.attachmentFrame(rig, time) or base
	if time == nil then
		Target.syncLive(rig)
	end

	if not Target.enabledAt(rig, time or Raw.CurrentTime) then
		return base
	end

	local motor = rig.RootPart:FindFirstChild("CamTarget")
	if not motor or motor:GetAttribute("EclipseDisabled") == true then
		return base
	end

	local world = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
	local delta = world.Position - base.Position
	if delta.Magnitude < 1e-5 then
		return base
	end

	local up = base.UpVector
	if math.abs(up:Dot(delta.Unit)) > 0.999 then
		up = base.RightVector
	end

	return base:Lerp(
		CFrame.lookAt(base.Position, world.Position, up),
		Target.weight(rig, time or Raw.CurrentTime)
	)
end

function Target.previewSnapshot()
	local a, b, c = table.clone(lastWorld), table.clone(live), table.clone(followed)
	return function()
		for dest, source in { [lastWorld] = a, [live] = b, [followed] = c } do
			table.clear(dest)
			for key, value in source do
				dest[key] = value
			end
		end
	end
end

return Target
