--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preview = {}
local originals, locals, hidden = {}, {}, {}
local root, context, hooks
local watchers = {}
local hiddenRefs = {}

local function watch(connection)
	watchers[connection] = true
	return connection
end

local function canHide(object)
	return object:IsA("BasePart")
		or object:IsA("Decal")
		or object:IsA("ParticleEmitter")
		or object:IsA("Beam")
		or object:IsA("Trail")
end

local function hide(object)
	if not root or not canHide(object) or hidden[object] ~= nil then
		return
	end

	hidden[object] = object.LocalTransparencyModifier
	local saved = root:FindFirstChild("HiddenParts")
	if not saved then
		saved = Instance.new("Folder")
		saved.Name = "HiddenParts"
		saved.Parent = root
	end

	local ref = Instance.new("ObjectValue")
	ref.Value = object
	ref:SetAttribute("Before", hidden[object])
	ref.Parent = saved
	hiddenRefs[object] = ref
	object.LocalTransparencyModifier = 1
end

function Preview.original(object)
	return originals[object] or object
end

function Preview.localOf(object)
	return locals[object] or object
end

function Preview.active()
	return root ~= nil
end

function Preview.recover(container)
	local saved = container:FindFirstChild("HiddenParts")
	for _, ref in saved and saved:GetChildren() or {} do
		local part = ref:IsA("ObjectValue") and ref.Value
		if part and canHide(part) then
			part.LocalTransparencyModifier = ref:GetAttribute("Before") or 0
		end
	end
end

local function mapTree(source, copy)
	locals[source], originals[copy] = copy, source
	local children = {}
	for _, child in copy:GetChildren() do
		local class = children[child.ClassName]
		if not class then
			class = {}
			children[child.ClassName] = class
		end

		local queue = class[child.Name]
		if not queue then
			queue = { next = 1 }
			class[child.Name] = queue
		end

		table.insert(queue, child)
	end

	for _, child in source:GetChildren() do
		local class = children[child.ClassName]
		local queue = class and class[child.Name]
		local candidate = queue and queue[queue.next]
		if candidate then
			queue.next += 1
			mapTree(child, candidate)
		end
	end
end

function Preview.shareR6Control(owner, bone)
	local Controls = require("R6Controls")
	local originalOwner = Controls.resolveOwner(originals[Controls.ownerInstance(owner)])
	if not root or not originalOwner then
		return
	end

	local original =
		Controls.ensure(originalOwner, bone:GetAttribute("EclipseR6Control"), bone.CFrame)
	mapTree(original, bone)
	local a, b = Controls.get(original), Controls.get(bone)
	locals[a], originals[b] = b, a
end

local function references(source)
	if
		source:IsA("JointInstance")
		or source:IsA("WeldConstraint")
		or source:IsA("NoCollisionConstraint")
	then
		return { "Part0", "Part1" }
	end

	if source:IsA("Beam") or source:IsA("Trail") or source:IsA("Constraint") then
		return { "Attachment0", "Attachment1" }
	end

	if source:IsA("Model") then
		return { "PrimaryPart" }
	end

	if source:IsA("ObjectValue") then
		return { "Value" }
	end

	if
		source:IsA("PVAdornment")
		or source:IsA("Highlight")
		or source:IsA("BillboardGui")
		or source:IsA("SurfaceGui")
	then
		return { "Adornee" }
	end

	return nil
end

local function remapReferences()
	for source, target in locals do
		if typeof(source) ~= "Instance" or typeof(target) ~= "Instance" then
			continue
		end

		for _, property in references(source) or {} do
			local value = source[property]
			target[property] = locals[value] or value
		end
	end

	require("Target").remapLive(locals)
end

local batching = false

function Preview.localize(rig)
	if not root or originals[rig] or locals[rig] then
		return Preview.localOf(rig)
	end

	if not (rig:IsA("Model") or rig:IsA("BasePart")) then
		if rig:IsA("ParticleEmitter") or rig:IsA("Beam") or rig:IsA("Trail") then
			local owner = rig:FindFirstAncestorWhichIsA("Model")
				or rig:FindFirstAncestorWhichIsA("BasePart")
			if owner then
				Preview.localize(owner)
				return Preview.localOf(rig)
			end
		end

		return rig
	end

	if not rig:GetAttribute("EclipseTrackId") then
		rig:SetAttribute("EclipseTrackId", game:GetService("HttpService"):GenerateGUID(false))
	end

	local flags = {}
	local objects = { rig }
	for _, v in rig:GetDescendants() do
		table.insert(objects, v)
	end

	for _, v in objects do
		local excluded = v ~= rig
			and (v.Name == "AnimSaves" or v:IsA("KeyframeSequence") or v:IsA("LuaSourceContainer"))
		local wanted = not excluded
		if v.Archivable ~= wanted then
			flags[v] = v.Archivable
			v.Archivable = wanted
		end
	end

	local ok, copy = pcall(rig.Clone, rig)
	for v, value in flags do
		v.Archivable = value
	end

	assert(ok and copy, "Could not create a local Live preview for " .. rig.Name)
	mapTree(rig, copy)
	copy.Archivable = false
	copy.Parent = root
	for _, v in objects do
		local c = locals[v]
		if c and canHide(c) then
			c.LocalTransparencyModifier = hidden[v] or v.LocalTransparencyModifier
			hide(v)
		elseif c and c:IsA("BaseScript") then
			c.Enabled = false
		end
	end

	local queued = false
	local watched, watchStructure = {}, nil

	local function syncDescendants()
		if queued then
			return
		end

		queued = true
		task.defer(function()
			queued = false
			if not root or not copy.Parent or locals[rig] ~= copy then
				return
			end

			local removed = {}
			for source, localObject in locals do
				if
					typeof(source) == "Instance"
					and typeof(localObject) == "Instance"
					and localObject ~= copy
					and localObject:IsDescendantOf(copy)
					and not source:IsDescendantOf(rig)
				then
					table.insert(removed, { source, localObject })
				end
			end

			for _, pair in removed do
				local source, localObject = pair[1], pair[2]
				if hidden[source] ~= nil then
					if source.Parent then
						source.LocalTransparencyModifier = hidden[source]
					end

					hidden[source] = nil
					if hiddenRefs[source] then
						hiddenRefs[source]:Destroy()
						hiddenRefs[source] = nil
					end
				end

				if watched[source] then
					for _, connection in watched[source] do
						connection:Disconnect()
						watchers[connection] = nil
					end

					watched[source] = nil
				end

				locals[source], originals[localObject] = nil, nil
				localObject:Destroy()
			end

			local function visit(source)
				for _, child in source:GetChildren() do
					if
						child.Name == "AnimSaves"
						or child:IsA("KeyframeSequence")
						or child:IsA("LuaSourceContainer")
					then
						continue
					end

					watchStructure(child)
					local target = locals[child]
					if not target then
						target = Instance.fromExisting(child)
						locals[child], originals[target] = target, child
						if canHide(child) then
							target.LocalTransparencyModifier = hidden[child]
								or child.LocalTransparencyModifier
							hide(child)
						end
					end

					if target.Parent ~= locals[source] then
						target.Parent = locals[source]
					end

					visit(child)
				end
			end

			visit(rig)

			remapReferences()
		end)
	end

	watchStructure = function(source)
		if watched[source] then
			return
		end

		watched[source] = { watch(source.AncestryChanged:Connect(syncDescendants)) }
		for _, property in references(source) or {} do
			table.insert(
				watched[source],
				watch(source:GetPropertyChangedSignal(property):Connect(syncDescendants))
			)
		end
	end

	for _, source in objects do
		if locals[source] then
			watchStructure(source)
		end
	end

	watch(rig.DescendantAdded:Connect(syncDescendants))
	watch(rig.DescendantRemoving:Connect(syncDescendants))
	watch(rig.Destroying:Connect(function()
		if copy.Parent then
			copy:Destroy()
		end
	end))
	if not batching then
		remapReferences()
	end

	return copy
end

local function remap(value, mapping, seen)
	if mapping[value] then
		return mapping[value]
	end

	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local result = {}
	seen[value] = result
	for key, item in value do
		result[remap(key, mapping, seen)] = remap(item, mapping, seen)
	end

	return result
end

Preview.remap = remap

function Preview.syncControls(source, target, raw)
	local Master = require("MasterControl")
	local different = false
	for _, attribute in { "EclipseMasterControl", "EclipseMasterRest", "EclipseMasterRadius" } do
		if source:GetAttribute(attribute) ~= target:GetAttribute(attribute) then different = true end
	end
	if different then Master.read(source, target) end
	local Scene = require("motors")
	local destination = Scene.motors(target, raw)
	local changed = false
	for id, motor in Scene.motors(source, raw) do
		local other = destination[id]
		if other and require("customRest").isJoint(motor) and require("customRest").isJoint(other) then
			for _, attribute in require("customRest").attributeNames() do
				local value = motor:GetAttribute(attribute)
				if other:GetAttribute(attribute) ~= value then other:SetAttribute(attribute, value) changed = true end
			end
		end
	end
	if changed then require("LimbIK").invalidate(target) end
end

local function bindMotors(source, target)
	local Scene = require("motors")
	local Properties = require("Properties")
	local raw = context.Timeline:GetState()
	Preview.syncControls(source, target, raw)
	local propertyData = Properties.snapshot(source, raw, false)
	Properties.restore(target, propertyData, context.Timeline, context.UIHelpers.SanitizeName)
	local a, b = Properties.folder(source, false), Properties.folder(target, false)
	if a and b then
		if originals[source] then
			originals[a], locals[b] = b, a
		else
			locals[a], originals[b] = b, a
		end
	end

	local Controls = require("R6Controls")
	for _, bone in source:GetDescendants() do
		if Controls.isControl(bone) then
			local control = Controls.get(bone)
			local owner = control
				and (originals[source] and originals[control.Owner] or locals[control.Owner])
			if owner and owner.Parent and owner.Part1 then
				local rest = raw.DefaultPose[control] or bone.CFrame
				local destination = Controls.ensure(owner, bone:GetAttribute("EclipseR6Control"), rest)
				destination.CFrame = rest
				destination.Transform = CFrame.identity
				for _, attribute in { "EclipseIKControlSpace", "EclipseIKAnchorOffset" } do
					destination:SetAttribute(attribute, bone:GetAttribute(attribute))
				end
			end
		end
	end

	local from = Scene.motors(source, raw)
	local to = Scene.motors(target, raw)
	for id, motor in from do
		local other = to[id]
		if other then
			if raw.DefaultPose[motor] == nil then
				raw.DefaultPose[other] = nil
			end

			if originals[source] then
				originals[motor], locals[other] = other, motor
				if motor.Part1 and other.Part1 then
					originals[motor.Part1], locals[other.Part1] = other.Part1, motor.Part1
				end
			else
				locals[motor], originals[other] = other, motor
				if motor.Part1 and other.Part1 then
					locals[motor.Part1], originals[other.Part1] = other.Part1, motor.Part1
				end
			end
		end
	end
end

local function remapInPlace(value, mapping, seen)
	if mapping[value] then
		return mapping[value]
	end

	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return value
	end

	if seen[value] then
		return value
	end

	seen[value] = true
	local entries = {}
	for key, item in value do
		entries[#entries + 1] =
			{ remapInPlace(key, mapping, seen), remapInPlace(item, mapping, seen) }
	end

	table.clear(value)
	for _, entry in entries do
		value[entry[1]] = entry[2]
	end

	return value
end

local function transferData(mapping)
	local raw = context.Timeline:GetState()
	local seen = {}
	for _, name in
		{
			"DefaultPose",
			"DefaultWorldPose",
			"DefaultSize",
			"ParentingDefaults",
			"MotorByPart",
			"Keyframes",
			"GreaseStrokes",
			"CopiedKeyframes",
			"AnimationLayers",
		}
	do
		if raw[name] then
			raw[name] = remapInPlace(raw[name], mapping, seen)
		end
	end

	for _, name in { "_motorUniform", "_motorHasScale", "_evaluationBuckets" } do
		if raw[name] then
			table.clear(raw[name])
		end
	end

	context.currentRig = mapping[context.currentRig] or context.currentRig
	for _, name in { "extraRigs", "activeObjectMotors", "lastCFrames", "exportSequences" } do
		context[name] = remapInPlace(context[name] or {}, mapping, seen)
	end
end

local function transfer(mapping)
	require("Target").remapLive(mapping)
	require("EventPlayback").clear()
	if context.OnionSkin and context.OnionSkin.Clear then
		context.OnionSkin:Clear()
	end

	local raw = context.Timeline:GetState()
	local Organization = require("Organization")
	local Events = require("Events")
	local Cache = require("Cache")

	if context.Axis then
		context.Axis:SelectBone(nil)
		context.Axis:ClearAxis()
	end

	if context.Rig and context.Rig.GetBonesFolder then
		for _, rig in context.getAllRigs() do
			if mapping[rig] then
				local folder = context.Rig:GetBonesFolder(rig)
				if folder then
					folder:Destroy()
				end
			end
		end
	end

	local organization = remap(Organization.snapshot(), mapping)
	local clips = remap(Cache.list(raw), mapping)
	for _, rig in context.getAllRigs() do
		local target = mapping[rig]
		if target then
			local track = Events.get(rig)
			Events.detach(rig)
			Events.attach(target, track)
		end
	end

	transferData(mapping)
	Cache.set(raw, clips)
	require("Scene").remapLive(context, mapping)
	if context.Axis then
		context.Axis:SelectBone(nil)
		context.Axis:ClearAxis()
		context.Axis:SetCurrentRig(context.currentRig)
	end

	if context.Timeline.ClearSelectedKeyframes then
		context.Timeline:ClearSelectedKeyframes()
	end

	if context.Rig then
		context.Rig:DestroyHierarchyItems()
	end

	Organization.restore(organization, "live")
	if hooks.RefreshStructure then
		hooks.RefreshStructure()
	end

	require("LimbIK").clearLive()
	for _, rig in context.getAllRigs() do
		require("LimbIK").invalidate(rig)
		context.Timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
	end
end

function Preview.begin(state, refs)
	assert(not root, "Live preview already exists")
	context, hooks = state, refs
	root = Instance.new("Folder")
	root.Name = "EclipseLivePreview"
	root.Archivable = false
	root:SetAttribute("EclipseLocalLivePreview", true)
	root.Parent = assert(workspace.CurrentCamera, "No local camera")
	local ok, err = xpcall(function()
		local rigs = state.getAllRigs()
		batching = true
		for _, rig in rigs do
			Preview.localize(rig)
		end

		batching = false
		remapReferences()
		for _, rig in rigs do
			if locals[rig] then
				bindMotors(rig, locals[rig])
			end
		end

		transfer(locals)
	end, debug.traceback)
	batching = false
	if not ok then
		Preview.finish()
		error(err, 0)
	end
end

function Preview.finish()
	if not root then
		return
	end

	local ok, err = xpcall(function()
		for _, rig in context.getAllRigs() do
			if originals[rig] then
				bindMotors(rig, originals[rig])
			end
		end

		transfer(originals)
	end, debug.traceback)
	if not ok then
		local restored, restoreError = pcall(transferData, originals)
		if restored and hooks.RefreshStructure then
			local rebuilt, rebuildError = pcall(hooks.RefreshStructure)
			if not rebuilt then
				err = tostring(err) .. "\n" .. tostring(rebuildError)
			end
		elseif not restored then
			err = tostring(err) .. "\n" .. tostring(restoreError)
		end
	end

	for connection in watchers do
		connection:Disconnect()
	end

	watchers = {}
	for part, value in hidden do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end

	local old = root
	root = nil
	originals, locals, hidden, hiddenRefs = {}, {}, {}, {}
	context, hooks = nil, nil
	old:Destroy()
	if not ok then
		error(err, 0)
	end
end

local function finitePose(value)
	if typeof(value) ~= "CFrame" then
		return false
	end

	for _, number in { value:GetComponents() } do
		if number ~= number or math.abs(number) == math.huge then
			return false
		end
	end

	return true
end

local function validSize(value)
	return typeof(value) == "Vector3"
		and value.X > 0
		and value.X < math.huge
		and value.Y > 0
		and value.Y < math.huge
		and value.Z > 0
		and value.Z < math.huge
end

local function manifestCovers(consumed, commit)
	if not consumed then
		return false
	end

	if consumed.text == commit then
		return true
	end

	local ok, expected = pcall(function()
		return game:GetService("HttpService"):JSONDecode(commit)
	end)
	if not ok or type(expected) ~= "table" or type(consumed.index) ~= "table" then
		return false
	end

	for id, names in expected do
		local current = consumed.index[id]
		if type(names) ~= "table" or type(current) ~= "table" or #current == 0 then
			return false
		end

		local required = 0
		for _, name in names do
			local shard, revision = tostring(name):match("^Page(%d+)_(%d+)_%d+$")
			if shard ~= id then
				return false
			end

			required = math.max(required, tonumber(revision))
		end

		for _, name in current do
			local shard, revision = tostring(name):match("^Page(%d+)_(%d+)_%d+$")
			if shard ~= id or tonumber(revision) < required then
				return false
			end
		end
	end

	return true
end

function Preview.stream(adapter)
	local self =
		{ nodes = {}, last = 0, active = false, receivers = setmetatable({}, { __mode = "k" }) }
	local commits = setmetatable({}, { __mode = "k" })

	local function editedRigs()
		local state = adapter.state
		local result = {}
		local axis = state.Axis

		local function include(part)
			if typeof(part) ~= "Instance" then
				return
			end

			for _, rig in adapter.rigs do
				if part == rig or part:IsDescendantOf(rig) then
					result[rig] = true
				end
			end
		end

		local snapshots = axis and axis.GetManipulationSnapshots and axis:GetManipulationSnapshots()
		for _, info in snapshots or {} do
			include(info.part or info.motor and info.motor.Part1)
		end

		for _, info in state.manipulationMotors or {} do
			include(info.part or info.motor and info.motor.Part1)
		end

		for _, bone in axis and axis.GetSelectedBones and axis:GetSelectedBones() or {} do
			local part = state.Rig
				and state.Rig.GetPartFromBone
				and state.Rig:GetPartFromBone(state.currentRig, bone)
			include(part or bone)
		end

		if not next(result) and state.currentRig then
			result[state.currentRig] = true
		end

		return result
	end

	local function belongs(motor, rigs)
		local part = motor.Part1
		if typeof(part) ~= "Instance" then
			return false
		end

		for rig in rigs do
			if part == rig or part:IsDescendantOf(rig) then
				return true
			end
		end

		return false
	end

	function self:publish(peer, editing, force)
		if not editing then
			return false
		end

		if not self.active then
			adapter:refresh()
			self.editRigs = editedRigs()
			self.active = true
			peer:SetAttribute("PoseActive", true)
		end

		if not force and os.clock() - self.last < 1 / 30 then
			return true
		end

		self.last = os.clock()
		local folder = peer:FindFirstChild("Pose")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Pose"
			folder.Parent = peer
		end

		local nextNode = #folder:GetChildren()
		local Parenting = require("Parenting")
		local raw = adapter.state.Timeline:GetState()
		local present = {}
		for id, motor in adapter.motors do
			local part = motor.Part1
			if
				belongs(motor, self.editRigs)
				and id ~= "$origin"
				and typeof(part) == "Instance"
				and part.Parent
				and (part:IsA("BasePart") or part:IsA("Bone"))
				and not (typeof(motor) == "table" and motor.IsEclipseProperty)
			then
				present[id] = true
				local node = self.nodes[id]
				if not node then
					nextNode += 1
					node = Instance.new("CFrameValue")
					node.Name = tostring(nextNode)
					node:SetAttribute("Track", id)
					self.nodes[id] = node
				end

				local world = Parenting.worldOf(motor, raw.MotorByPart)
				if node.Value ~= world then
					node.Value = world
				end

				if node:GetAttribute("C0") ~= motor.C0 then
					node:SetAttribute("C0", motor.C0)
				end

				if part:IsA("BasePart") and node:GetAttribute("Size") ~= part.Size then
					node:SetAttribute("Size", part.Size)
				end

				node.Parent = folder
			end
		end

		for id, node in self.nodes do
			if not present[id] then
				node:Destroy()
				self.nodes[id] = nil
			end
		end

		return true
	end

	function self:commit(peer)
		if not self.active then
			return
		end

		peer:SetAttribute("PoseCommit", peer:GetAttribute("Manifest"))
		peer:SetAttribute("PoseActive", false)
		self.active = false
	end

	function self:apply(peer, consumed, dt)
		local commit = peer:GetAttribute("PoseCommit")
		if not peer:GetAttribute("PoseActive") then
			local cached = commits[peer]
			local text = consumed and consumed.text
			if not cached or cached.commit ~= commit or cached.text ~= text then
				cached = {
					commit = commit,
					text = text,
					covered = not commit or manifestCovers(consumed, commit),
				}
				commits[peer] = cached
			end

			if cached.covered then
				self.receivers[peer] = nil
				return false
			end
		end

		local folder = peer:FindFirstChild("Pose")
		if not folder then
			return false
		end

		local previous = self.receivers[peer] or {}
		self.receivers[peer] = previous
		local step = type(dt) == "number" and dt == dt and math.clamp(dt, 0, 1) or 1 / 60
		local alpha = 1 - math.exp(-step * 90)
		local applied = false
		local updates = {}
		for _, node in folder:GetChildren() do
			if node:IsA("CFrameValue") then
				local id = node:GetAttribute("Track")
				local motor = adapter.motors[id]
				local cf = node:GetAttribute("C0")
				if
					motor
					and motor.Parent
					and finitePose(cf)
					and finitePose(node.Value)
					and not (typeof(motor) == "table" and motor.IsEclipseProperty)
					and not (self.active and belongs(motor, self.editRigs))
				then
					local old = previous[id]
					local world = old and old.world:Lerp(node.Value, alpha) or node.Value
					local localPose = old and old.cf:Lerp(cf, alpha) or cf
					table.insert(updates, {
						motor = motor,
						pose = localPose,
						world = world,
						size = node:GetAttribute("Size"),
					})

					previous[id] = { world = world, cf = localPose }
					applied = true
				end
			end
		end

		adapter.state.lastCFrames = adapter.state.lastCFrames or {}
		for _, masterPass in { true, false } do
			for _, update in updates do
				local m = update.motor
				local master = typeof(m) == "table" and m.IsEclipseMasterControl == true
				if master == masterPass then
					m.C0 = update.pose
					adapter.state.lastCFrames[m] = m.C0
				end
			end
		end

		for _, update in updates do
			local m = update.motor
			local part = m.Part1
			if
				typeof(part) == "Instance"
				and part:IsA("BasePart")
				and not (typeof(m) == "table" and m.IsEclipseMasterControl)
			then
				part.CFrame = update.world
				if validSize(update.size) then
					part.Size = update.size
				end
			end
		end

		return applied
	end

	return self
end

return Preview
