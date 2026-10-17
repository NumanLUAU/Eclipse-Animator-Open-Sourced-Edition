--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Recovery = {}
local roots = setmetatable({}, { __mode = "k" })
local cameras = setmetatable({}, { __mode = "k" })
local TYPE = "EclipseCameraTypeBeforeControl"
local OWNED = "EclipseCameraOwned"
local LEASE = "EclipseCameraLease"
local FOV = "EclipseCameraFOVBeforeControl"
local FOV_MODE = "EclipseCameraFOVModeBeforeControl"

local function leaseFor(camera, create)
	local core = game:GetService("CoreGui")
	local folder = core:FindFirstChild("EclipseCameraLeases")
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = "EclipseCameraLeases"
		folder.Archivable = false
		folder.Parent = core
	end

	for _, lease in folder and folder:GetChildren() or {} do
		if lease:IsA("ObjectValue") and lease.Value == camera then
			return lease
		end
	end

	if create then
		local lease = Instance.new("ObjectValue")
		lease.Name = "CameraLease"
		lease.Value = camera
		lease.Parent = folder
		return lease
	end
end

local unload
local poses = setmetatable({}, { __mode = "k" })
local joints = setmetatable({}, { __mode = "k" })
local REST = "EclipsePoseBeforePreview"
local JOINT = "EclipseJointBeforePreview"

local function cameraType(name)
	for _, value in Enum.CameraType:GetEnumItems() do
		if value.Name == name then
			return value
		end
	end

	return Enum.CameraType.Custom
end

function Recovery.captureJoint(joint)
	local part = joint.Part1
	if not part then
		return
	end

	if not poses[part] then
		if part:GetAttribute(REST) == nil then
			part:SetAttribute(REST, part.CFrame)
		end

		poses[part] = true
	end

	if not joints[joint] then
		if joint:GetAttribute(JOINT) == nil then
			joint:SetAttribute(JOINT, joint:GetAttribute("EclipseAnimatorDefaultC0") or joint.C0)
		end

		joints[joint] = true
	end
end

local armatureRigs = setmetatable({}, { __mode = "k" })
local ARM_ACTIVE = "EclipseArmaturePreviewActive"
local ARM_C0 = "EclipseArmaturePreviewC0"
local ARM_TRANSFORM = "EclipseArmaturePreviewTransform"
local ARM_WORLD = "EclipseArmaturePreviewWorld"
local ARM_SIZE = "EclipseArmaturePreviewSize"

local function stamp(object, name, value)
	if value ~= nil and object:GetAttribute(name) == nil then
		object:SetAttribute(name, value)
	end
end

function Recovery.captureArmature(rig, bindings)
	local master = require("MasterControl").get(rig, true)
	for _, binding in bindings do
		local target = binding.target
		if not target:IsDescendantOf(rig) then
			continue
		end

		if target:IsA("JointInstance") then
			local rest = binding.reference:GetAttribute("EclipseArmatureRestC0")
				or target:GetAttribute("EclipseAnimatorDefaultC0")
				or target.C0
			stamp(target, ARM_C0, rest)
			if target:IsA("Motor6D") then
				stamp(target, ARM_TRANSFORM, CFrame.identity)
			end
		elseif target:IsA("Bone") then
			stamp(target, ARM_TRANSFORM, target.Transform)
		elseif target:IsA("BasePart") then
			stamp(
				target,
				ARM_WORLD,
				master and master.Part1 == target and master.Part0.CFrame or target.CFrame
			)
		end

		if binding.part and binding.part:IsDescendantOf(rig) then
			stamp(binding.part, ARM_SIZE, binding.restSize)
		end
	end

	rig:SetAttribute(ARM_ACTIVE, true)
	armatureRigs[rig] = true
end

function Recovery.restoreArmature(rig)
	if not rig then
		return false
	end

	require("Skinning").restoreOrphans(rig)
	if rig:GetAttribute(ARM_ACTIVE) ~= true then
		armatureRigs[rig] = nil
		return false
	end

	local master = require("MasterControl").get(rig, true)
	if master then
		master.C0 = master.DefaultC0
	end

	local objects = require("RigTraversal").rigDescendants(rig)
	table.insert(objects, rig)
	for _, object in objects do
		local c0, transform, world, size =
			object:GetAttribute(ARM_C0),
			object:GetAttribute(ARM_TRANSFORM),
			object:GetAttribute(ARM_WORLD),
			object:GetAttribute(ARM_SIZE)
		if object:IsA("JointInstance") and typeof(c0) == "CFrame" then
			object.C0 = c0
			require("RigPose").rememberRest(object, c0)
		end

		if (object:IsA("Motor6D") or object:IsA("Bone")) and typeof(transform) == "CFrame" then
			object.Transform = transform
		end

		if object:IsA("BasePart") then
			if typeof(size) == "Vector3" then
				object.Size = size
			end

			if typeof(world) == "CFrame" then
				object.CFrame = world
			end
		end
	end

	require("RigPose").assemble(rig)

	for _, object in objects do
		for _, name in { ARM_C0, ARM_TRANSFORM, ARM_WORLD, ARM_SIZE } do
			if object:GetAttribute(name) ~= nil then
				object:SetAttribute(name, nil)
			end
		end
	end

	rig:SetAttribute(ARM_ACTIVE, nil)
	armatureRigs[rig] = nil
	return true
end

function Recovery.parkForce(part)
	if not part.Parent or part:GetAttribute("EclipsePhysicsForce") ~= true then
		return
	end

	local folder = require("root").get("EclipsePhysicsForces", true)
	part.Parent = folder
end

function Recovery.forgetRig(rig)
	for _, object in require("RigTraversal").descendants(rig) do
		if poses[object] or object:GetAttribute(REST) ~= nil then
			object:SetAttribute(REST, nil)
			poses[object] = nil
		end

		if joints[object] or object:GetAttribute(JOINT) ~= nil then
			object:SetAttribute(JOINT, nil)
			joints[object] = nil
		end
	end
end

local function restorePose(object)
	local cf = object:GetAttribute(REST)
	if object:IsA("BasePart") and typeof(cf) == "CFrame" then
		object.CFrame = cf
		object:SetAttribute(REST, nil)
	end

	local c0 = object:GetAttribute(JOINT)
	if object:IsA("Motor6D") and typeof(c0) == "CFrame" then
		object.C0 = c0
		object.Transform = CFrame.identity
		object:SetAttribute(JOINT, nil)
	end
end

function Recovery.mark(object)
	object.Archivable = false
	object:SetAttribute("EclipseTransient", true)
	roots[object] = true
	return object
end

local function restore(camera, expected)
	local lease = leaseFor(camera, false)
	if expected and (not lease or lease:GetAttribute("Token") ~= expected) then
		return false
	end

	if not expected and lease then
		return false
	end

	if not expected and camera:GetAttribute(OWNED) ~= true then
		return false
	end

	if camera.Parent and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType =
			cameraType(lease and lease:GetAttribute("Before") or camera:GetAttribute(TYPE))
	end

	local fov = camera:GetAttribute(FOV)
	if camera.Parent and typeof(fov) == "number" and fov == fov and fov >= 1 and fov <= 120 then
		local mode = camera:GetAttribute(FOV_MODE)
		for _, value in Enum.FieldOfViewMode:GetEnumItems() do
			if value.Name == mode then camera.FieldOfViewMode = value break end
		end
		camera.FieldOfView = fov
	end
	camera:SetAttribute(FOV, nil)
	camera:SetAttribute(FOV_MODE, nil)
	camera:SetAttribute(OWNED, nil)
	camera:SetAttribute(TYPE, nil)
	camera:SetAttribute(LEASE, nil)
	if lease then
		local folder = lease.Parent
		lease:Destroy()
		if #folder:GetChildren() == 0 then
			folder:Destroy()
		end
	end

	return true
end

function Recovery.acquire(camera)
	local entry = cameras[camera]
	if not entry then
		local lease = leaseFor(camera, true)
		local previous = lease:GetAttribute("Before")
			or camera:GetAttribute(OWNED) == true and camera:GetAttribute(TYPE)
		entry = {
			count = 0,
			kind = previous and cameraType(previous) or camera.CameraType,
			token = game:GetService("HttpService"):GenerateGUID(false),
			lease = lease,
		}
		lease:SetAttribute("Token", entry.token)
		lease:SetAttribute("Before", entry.kind.Name)
		cameras[camera] = entry
		if camera:GetAttribute(FOV) == nil then camera:SetAttribute(FOV, camera.FieldOfView) end
		if camera:GetAttribute(FOV_MODE) == nil then camera:SetAttribute(FOV_MODE, camera.FieldOfViewMode.Name) end
		camera:SetAttribute(TYPE, entry.kind.Name)
		camera:SetAttribute(OWNED, true)
		camera:SetAttribute(LEASE, entry.token)
	end

	entry.count += 1
	local released = false
	return function()
		if released then
			return
		end

		released = true
		entry.count -= 1
		if entry.count ~= 0 or cameras[camera] ~= entry then
			return
		end

		cameras[camera] = nil
		restore(camera, entry.token)
	end
end

function Recovery.owns(camera)
	local entry = cameras[camera]
	return entry ~= nil
		and entry.lease.Parent ~= nil
		and entry.lease:GetAttribute("Token") == entry.token
end

function Recovery.maintain(camera)
	local entry = cameras[camera]
	if not entry then
		return false
	end

	if not Recovery.owns(camera) then
		return false
	end

	if camera:GetAttribute(LEASE) ~= entry.token then
		camera:SetAttribute(LEASE, entry.token)
	end

	if camera:GetAttribute(OWNED) ~= true then
		camera:SetAttribute(OWNED, true)
	end

	if camera:GetAttribute(TYPE) ~= entry.kind.Name then
		camera:SetAttribute(TYPE, entry.kind.Name)
	end

	return true
end

function Recovery.recover(scope, localOnly)
	local removed, restored = 0, 0
	local functionScan = function(parent)
		local legacy = false
		for _, object in parent:GetChildren() do
			if roots[object] then
				continue
			end

			local boneDisplay = object:IsA("Folder")
				and object:GetAttribute("EclipseAnimator_BonesFolder") == true
			if
				boneDisplay
				or object:GetAttribute("EclipseTransient") == true
				or object:GetAttribute("EclipseLocalLivePreview") == true
			then
				legacy = legacy or boneDisplay
				if object:GetAttribute("EclipseLocalLivePreview") == true then
					require("rig").recover(object)
				end

				object:Destroy()
				removed += 1
			end
		end

		return legacy
	end

	if not localOnly then functionScan(scope) end
	for _, object in scope:GetChildren() do
		if not object:IsA("Camera") then
			continue
		end

		local legacy = functionScan(object)
		if cameras[object] or leaseFor(object, false) then
			continue
		end

		if restore(object) then
			restored += 1
		elseif legacy and object.CameraType == Enum.CameraType.Scriptable then
			object.CameraType = Enum.CameraType.Custom
			restored += 1
		end
	end

	if localOnly then return { removed = removed, restored = restored } end

	for _, object in require("RigTraversal").descendants(scope) do
		if not poses[object] and not joints[object] then
			restorePose(object)
		end

		if object:IsA("BasePart") and object:GetAttribute("EclipsePhysicsForce") == true then
			Recovery.parkForce(object)
		end
	end

	for _, object in require("RigTraversal").descendants(scope) do
		if
			object:IsA("MeshPart")
			and object:GetAttribute("EclipseArmatureSkinOriginalMesh")
			and not armatureRigs[object:FindFirstAncestorOfClass("Model")]
		then
			require("Skinning").restoreOrphans(object)
		end

		if object:GetAttribute(ARM_ACTIVE) == true and not armatureRigs[object] then
			Recovery.restoreArmature(object)
		end
	end

	if scope:GetAttribute(ARM_ACTIVE) == true and not armatureRigs[scope] then
		Recovery.restoreArmature(scope)
	end

	return { removed = removed, restored = restored }
end

function Recovery.cleanup()
	pcall(function()
		require("ArmatureRuntime").clear()
	end)
	for joint in joints do
		if joint.Parent then
			restorePose(joint)
		end

		joints[joint] = nil
	end

	for part in poses do
		if part.Parent then
			restorePose(part)
		end

		poses[part] = nil
	end

	for _, part in workspace:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("EclipsePhysicsForce") == true then
			Recovery.parkForce(part)
		end
	end

	for rig in armatureRigs do
		if rig.Parent then
			Recovery.restoreArmature(rig)
		else
			armatureRigs[rig] = nil
		end
	end

	for camera, entry in cameras do
		restore(camera, entry.token)
		cameras[camera] = nil
	end

	for object in roots do
		object:Destroy()
		roots[object] = nil
	end
end

const STAMP_TOKEN = "EclipseAnimatorStampToken"
const REST_C0 = "EclipseAnimatorDefaultC0"
const REST_SIZE = "EclipseAnimatorDefaultSize"
const HOME_C1 = "EclipseAnimatorDefaultC1"
const LOADED_C1 = "EclipseAnimatorLoadedC1"

local function inUse(model)
	const State = require("State")
	for _, rig in State.getAllRigs and State.getAllRigs() or {} do
		if rig == model or rig:IsDescendantOf(model) or model:IsDescendantOf(rig) then
			return true
		end
	end

	return false
end

function Recovery.applyRest(scope, state)
	if typeof(scope) ~= "Instance" or not scope.Parent then
		return nil
	end

	const owner = scope:IsA("Model") and scope or scope:FindFirstAncestorOfClass("Model") or scope
	const token = owner:GetAttribute(STAMP_TOKEN)
	const objects = require("RigTraversal").descendants(scope)
	table.insert(objects, 1, scope)
	const changes = {}
	for _, object in objects do
		if
			object:GetAttribute("EclipseArmatureSkinningHelper")
			or object:GetAttribute(STAMP_TOKEN) ~= token
		then
			continue
		end

		if object:IsA("Motor6D") and not (state and state.DefaultPose[object]) then
			const rest = object:GetAttribute(REST_C0)
			if typeof(rest) == "CFrame" and not object.C0:FuzzyEq(rest, 1e-6) then
				table.insert(changes, { object, "C0", rest })
			end

			const home, loaded = object:GetAttribute(HOME_C1), object:GetAttribute(LOADED_C1)
			if
				typeof(home) == "CFrame"
				and (typeof(loaded) ~= "CFrame" or object.C1:FuzzyEq(loaded, 1e-5))
				and not object.C1:FuzzyEq(home, 1e-6)
			then
				table.insert(changes, { object, "C1", home })
			end
		elseif object:IsA("BasePart") and not (state and state.DefaultSize[object]) then
			const size = object:GetAttribute(REST_SIZE)
			if typeof(size) == "Vector3" and (object.Size - size).Magnitude > 1e-6 then
				table.insert(changes, { object, "Size", size })
			end
		end
	end

	if #changes == 0 then
		return nil
	end

	const snapshot = { values = {}, parts = {}, frames = {} }
	for _, object in require("RigTraversal").descendants(owner) do
		if object:IsA("BasePart") then
			table.insert(snapshot.parts, object)
			table.insert(snapshot.frames, object.CFrame)
		end
	end

	for _, change in changes do
		table.insert(snapshot.values, { change[1], change[2], change[1][change[2]] })
		change[1][change[2]] = change[3]
	end

	if owner:IsA("Model") then
		require("RigPose").assemble(owner)
	end

	return snapshot
end

function Recovery.restoreSnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	for index = #snapshot.values, 1, -1 do
		const entry = snapshot.values[index]
		if entry[1].Parent then
			entry[1][entry[2]] = entry[3]
		end
	end

	const parts, frames = {}, {}
	for index, part in snapshot.parts do
		if part.Parent then
			table.insert(parts, part)
			table.insert(frames, snapshot.frames[index])
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Recovery.settleRig(rig)
	if
		typeof(rig) ~= "Instance"
		or not rig:IsA("Model")
		or not rig:IsDescendantOf(workspace)
		or inUse(rig)
	then
		return nil
	end

	return Recovery.applyRest(rig, nil)
end

function Recovery.init(plugin)
	if unload then
		unload:Disconnect()
	end

	Recovery.recover(workspace, true)
	unload = plugin.Unloading:Connect(Recovery.cleanup)
end

local Http = game:GetService("HttpService")
local Encoding = game:GetService("EncodingService")
local Serialization = game:GetService("SerializationService")
local LIMIT = 24000000
local SLOTS = 8

local function encode(text)
	return buffer.tostring(Encoding:Base64Encode(buffer.fromstring(text)))
end

local function decode(text)
	return buffer.tostring(Encoding:Base64Decode(buffer.fromstring(text)))
end

local function externalPath(object)
	local path = {}
	while object and object ~= game do
		local parent = object.Parent
		if not parent then
			return
		end

		local matches = 0
		for _, sibling in parent:GetChildren() do
			if sibling.Name == object.Name and sibling.ClassName == object.ClassName then
				matches += 1
			end
		end

		if matches ~= 1 then
			return
		end

		table.insert(path, 1, { name = object.Name, class = object.ClassName })
		object = parent
	end

	return object == game and path or nil
end

local function externalObject(path, id)
	local object = game
	for _, segment in path do
		local match
		for _, child in object:GetChildren() do
			if child.Name == segment.name and child.ClassName == segment.class then
				if match then
					return
				end

				match = child
			end
		end

		if not match then
			return
		end

		object = match
	end

	if
		id
		and object:GetAttribute("EclipseTrackId")
		and object:GetAttribute("EclipseTrackId") ~= id
	then
		return
	end

	return object
end

function Recovery.newJournal(store, scope)
	assert(type(scope) == "string" and scope:match("^[%w_]+$"), "Invalid recovery scope")
	local journal = { store = store, scope = scope, seen = {}, slots = {} }
	local cached = {}

	local function copyRow(value)
		if type(value) ~= "table" then
			return value
		end

		local copy = {}
		for k, v in value do
			copy[k] = copyRow(v)
		end

		return copy
	end

	local function key(slot, bank)
		return "EclipseRecoveryV1_" .. scope .. "_" .. slot .. "_" .. bank
	end

	function journal:read(slot, bank, budget)
		if budget then
			budget()
		end

		local setting = key(slot, bank)
		local value = self.store.get(setting)
		if value == nil then
			task.wait(0.05)
			value = self.store.get(setting)
			assert(
				value ~= nil or not self.seen[setting],
				"A known recovery copy is temporarily unavailable"
			)
		end

		if value == nil or value == "EclipseRecoveryDeletedV1" then
			return nil
		end

		self.seen[setting] = true
		assert(type(value) == "string" and #value <= LIMIT, "Unreadable recovery entry")
		for index, item in cached do
			if item.key == setting then
				table.remove(cached, index)
				if item.value == value then
					table.insert(cached, 1, item)
					if budget then
						budget()
					end

					return copyRow(item.row)
				end

				break
			end
		end

		local row = Http:JSONDecode(decode(value))
		assert(
			type(row) == "table"
				and row.schema == 1
				and row.scope == scope
				and type(row.id) == "string"
				and type(row.name) == "string"
				and type(row.time) == "number"
				and type(row.data) == "string"
				and row.time >= 0
				and row.time < 4102444800000
				and #row.name <= 512
				and #row.id <= 128
				and #row.data <= LIMIT
				and type(row.links) == "table"
				and type(row.token) == "string"
				and (row.compression == nil or row.compression == "zstd"),
			"Invalid recovery entry"
		)
		row.slot = slot
		row.bank = bank
		table.insert(cached, 1, { key = setting, value = value, row = copyRow(row) })
		if #cached > 2 then
			table.remove(cached)
		end

		if budget then
			budget()
		end

		return row
	end

	function journal:list(budget)
		local rows, errors, unreadable = {}, 0, {}
		for slot = 1, SLOTS do
			for bank = 1, 2 do
				if budget then
					budget()
				end

				local ok, row = pcall(self.read, self, slot, bank)
				if budget then
					budget()
				end

				if not ok then
					errors += 1
					unreadable[slot] = true
				elseif row then
					table.insert(rows, row)
				end
			end
		end

		table.sort(rows, function(a, b)
			return a.time > b.time
		end)
		return rows, errors, unreadable
	end

	function journal:write(id, name, archive, budget)
		local rows, errors, unreadable
		local owned = self.slots[id]
		if owned then
			rows = {}
			errors = 0
			unreadable = {}
			for bank = 1, 2 do
				if budget then
					budget()
				end

				local good, row = pcall(self.read, self, owned, bank)
				if budget then
					budget()
				end

				if not good then
					rows = nil
					break
				end

				if row then
					table.insert(rows, row)
				end
			end

			if rows then
				table.sort(rows, function(a, b)
					return a.time > b.time
				end)
			end

			if not rows or not rows[1] or rows[1].id ~= id then
				rows = nil
			end
		end

		if not rows then
			rows, errors, unreadable = self:list(budget)
		end

		if budget then
			budget()
		end

		local latest = {}
		local slot
		for _, row in rows do
			latest[row.slot] = latest[row.slot] or row
			if row.id == id and not slot then
				slot = row.slot
			end
		end

		if not slot then
			for i = 1, SLOTS do
				if not latest[i] and not unreadable[i] then
					slot = i
					break
				end
			end
		end

		if not slot then
			local oldest = math.huge
			for i, row in latest do
				if row.time < oldest then
					oldest = row.time
					slot = i
				end
			end
		end

		assert(slot, "Local recovery is unreadable. Previous copies were retained; retry shortly.")
		local previous = latest[slot]
		local bank = previous and (3 - previous.bank) or 1
		local links, linkIds = {}, {}
		for _, value in archive:GetDescendants() do
			if budget then
				budget()
			end

			if
				value:IsA("ObjectValue")
				and value.Value
				and not value.Value:IsDescendantOf(archive)
				and value.Value ~= archive
			then
				local index = linkIds[value.Value]
				if index == nil then
					local path = externalPath(value.Value)
					index = path and #links + 1 or false
					linkIds[value.Value] = index
					if index then
						links[index] =
							{ path = path, id = value.Value:GetAttribute("EclipseTrackId") }
					end
				end

				if index then
					value:SetAttribute("EclipseRecoveryLink", index)
				end
			end
		end

		local bytes = Serialization:SerializeInstancesAsync({ archive })
		if budget then
			budget()
		end

		assert(
			buffer.len(bytes) <= 12000000,
			"Recovery copy exceeds the local size limit. Save the project and Studio place manually."
		)
		bytes = Encoding:CompressBuffer(bytes, Enum.CompressionAlgorithm.Zstd, 3)
		local row = {
			schema = 1,
			compression = "zstd",
			scope = scope,
			id = id,
			name = name,
			placeName = game.Name,
			time = math.max(
				DateTime.now().UnixTimestampMillis,
				previous and previous.time + 1 or 0
			),
			token = Http:GenerateGUID(false),
			data = buffer.tostring(Encoding:Base64Encode(bytes)),
			links = links,
		}
		local text = encode(Http:JSONEncode(row))
		assert(#text <= LIMIT, "Recovery copy exceeds the local size limit")

		local function commit()
			if budget then
				budget()
			end

			local now = self:read(slot, previous and previous.bank or bank)
			assert(
				(not previous and not now) or previous and now and previous.token == now.token,
				"Another Studio window updated recovery; retrying later."
			)
			self.store.set(key(slot, bank), text)
			assert(
				self.store.get(key(slot, bank)) == text,
				"Recovery write could not be verified. The preceding copy was retained."
			)
			self.seen[key(slot, bank)] = true
			if not previous or previous.id ~= id then
				local other = 3 - bank
				local old = self:read(slot, other)
				assert(
					not previous and not old or previous and old and old.token == previous.token,
					"Another window claimed this recovery slot"
				)
				self.store.set(key(slot, other), text)
				assert(
					self.store.get(key(slot, other)) == text,
					"The second recovery copy could not be verified"
				)
				self.seen[key(slot, other)] = true
			end
		end

		if self.store.transaction then
			self.store.transaction(commit)
		else
			commit()
		end

		self.slots[id] = slot
		row.slot, row.bank = slot, bank
		return row
	end

	function journal:remove(row)
		local function commit()
			local current = self:read(row.slot, row.bank)
			assert(
				current and current.token == row.token,
				"This recovery copy changed; reopen Recovery"
			)
			self.store.set(key(row.slot, row.bank), "EclipseRecoveryDeletedV1")
			assert(
				self.store.get(key(row.slot, row.bank)) == "EclipseRecoveryDeletedV1",
				"Recovery deletion could not be verified"
			)
		end

		if self.store.transaction then
			self.store.transaction(commit)
		else
			commit()
		end

		self.slots[row.id] = nil
	end

	function journal:restore(row)
		local bytes = Encoding:Base64Decode(buffer.fromstring(row.data))
		if row.compression == "zstd" then
			bytes = Encoding:DecompressBuffer(bytes, Enum.CompressionAlgorithm.Zstd)
		end

		assert(buffer.len(bytes) <= 12000000, "Recovery archive exceeds the local size limit")
		local roots = Serialization:DeserializeInstancesAsync(bytes)
		local archive = roots[1]
		local ok, message = pcall(function()
			assert(
				#roots == 1 and archive:IsA("Folder") and archive:FindFirstChild("Rigs"),
				"Invalid recovery archive"
			)
			for _, value in archive:GetDescendants() do
				local index = value:GetAttribute("EclipseRecoveryLink")
				if value:IsA("ObjectValue") and index then
					local link = row.links[index]
					if link then
						value.Value = externalObject(link.path, link.id)
					end

					value:SetAttribute("EclipseRecoveryLink", nil)
				end
			end

			archive:SetAttribute("EclipseSave", true)
			archive:SetAttribute("EclipseProjectId", Http:GenerateGUID(false))
			archive:SetAttribute("EclipseLiveProject", true)
			archive:SetAttribute("EclipseCompleteSave", false)
			archive:SetAttribute("EclipseRecoveredAt", row.time)
			archive.Name = row.name .. " (Recovered)"
		end)
		if not ok then
			for _, root in roots do
				root:Destroy()
			end

			error(message, 0)
		end

		return archive
	end

	return journal
end

function Recovery.newPlaceJournal(parent)
	local journal = {}

	local function read(entry)
		if not entry:IsA("Folder") or entry:GetAttribute("Complete") ~= true then
			return nil
		end

		local archive = entry:FindFirstChild("Archive")
		local id, token, time =
			entry:GetAttribute("ProjectId"), entry:GetAttribute("Token"), entry:GetAttribute("Time")
		local slot, bank = entry:GetAttribute("Slot"), entry:GetAttribute("Bank")
		if
			not archive
			or not archive:IsA("Folder")
			or not archive:FindFirstChild("Rigs")
			or type(id) ~= "string"
			or type(token) ~= "string"
			or type(time) ~= "number"
			or time ~= time
			or type(slot) ~= "number"
			or slot % 1 ~= 0
			or slot < 1
			or slot > SLOTS
			or (bank ~= 1 and bank ~= 2)
		then
			return nil
		end

		return {
			id = id,
			token = token,
			time = time,
			name = entry:GetAttribute("Title") or "Animation",
			placeName = entry:GetAttribute("PlaceName") or game.Name,
			archive = archive,
			entry = entry,
			slot = entry:GetAttribute("Slot"),
			bank = entry:GetAttribute("Bank"),
		}
	end

	function journal:list()
		local rows, errors = {}, 0
		local entries = parent:GetChildren()
		local legacy = parent:FindFirstChild("ImportedRecovery")
		if legacy then
			for _, entry in legacy:GetChildren() do
				table.insert(entries, entry)
			end
		end

		for _, entry in entries do
			local row = read(entry)
			if row then
				table.insert(rows, row)
			elseif entry:GetAttribute("Complete") == true then
				errors += 1
			end
		end

		table.sort(rows, function(a, b)
			return a.time > b.time
		end)
		return rows, errors
	end

	function journal:write(id, name, archive, budget)
		assert(archive:IsA("Folder") and archive:FindFirstChild("Rigs"), "Invalid recovery archive")
		if budget then
			budget()
		end

		local rows, errors = self:list()
		local latest, slot = {}, nil
		for _, row in rows do
			if row.entry.Parent ~= parent then
				continue
			end

			latest[row.slot] = latest[row.slot] or row
			if row.id == id then
				slot = slot or row.slot
			end
		end

		if not slot then
			for n = 1, SLOTS do
				if
					not latest[n]
					and not parent:FindFirstChild("Copy" .. n .. "_1")
					and not parent:FindFirstChild("Copy" .. n .. "_2")
				then
					slot = n
					break
				end
			end
		end

		if not slot then
			local oldest = math.huge
			for n, row in latest do
				if row.time < oldest then
					oldest = row.time
					slot = n
				end
			end
		end

		assert(slot, "Recovery contains unreadable copies; save the place and retry")
		local previous = latest[slot]
		local bank = previous and 3 - previous.bank or 1
		assert(
			not parent:FindFirstChild("Pending" .. slot),
			"Recovery is already writing this slot; retrying later"
		)
		local lock = Instance.new("Folder")
		lock.Name = "Pending" .. slot
		lock.Archivable = false
		lock.Parent = parent
		local entry = Instance.new("Folder")
		entry.Name = "Copy" .. slot .. "_" .. bank
		entry.Archivable = false
		entry:SetAttribute("Slot", slot)
		entry:SetAttribute("Bank", bank)
		entry:SetAttribute("ProjectId", id)
		entry:SetAttribute("Title", name)
		entry:SetAttribute("Token", Http:GenerateGUID(false))
		entry:SetAttribute(
			"Time",
			math.max(DateTime.now().UnixTimestampMillis, previous and previous.time + 1 or 0)
		)
		entry:SetAttribute("EclipseRecoveryArchive", true)
		local replaced = parent:FindFirstChild(entry.Name)
		local oldName = archive.Name
		local detached = {}
		local ok, err = pcall(function()
			if budget then
				local queue = { archive }
				local index = 1
				while index <= #queue do
					local object = queue[index]
					index += 1
					for _, child in object:GetChildren() do
						table.insert(detached, { child, object })
						table.insert(queue, child)
					end

					budget()
				end

				if #detached > 256 then
					for _, pair in detached do
						pair[1].Parent = nil
						budget()
					end
				else
					table.clear(detached)
				end
			end

			archive.Name = "Archive"
			archive.Parent = entry
			entry.Parent = parent
			for _, pair in detached do
				pair[1].Parent = pair[2]
				budget()
			end

			if budget then
				budget()
			end

			entry:SetAttribute("Complete", true)
			assert(read(entry), "Could not verify recovery copy")
			assert(entry.Parent == parent and archive.Parent == entry, "Recovery commit failed")
			entry.Archivable = true
		end)
		if not ok then
			archive.Parent = nil
			archive.Name = oldName
			for _, pair in detached do
				pair[1].Parent = pair[2]
			end

			entry:Destroy()
			lock:Destroy()
			error(err, 0)
		end

		if replaced then
			replaced:Destroy()
		end

		lock:Destroy()
		return assert(read(entry))
	end

	function journal:ownsArchive(archive)
		return archive.Parent
			and archive.Parent.Parent == parent
			and archive.Parent:GetAttribute("Complete") == true
	end

	function journal:remove(row)
		local current = row.entry and row.entry:IsDescendantOf(parent) and read(row.entry)
		assert(current and current.token == row.token, "Recovery changed; reopen Recovery")
		row.entry:Destroy()
	end

	function journal:restore(row)
		local current = row.entry and row.entry:IsDescendantOf(parent) and read(row.entry)
		assert(current and current.token == row.token, "Recovery changed; reopen Recovery")
		local archive = current.archive:Clone()
		archive.Name = row.name .. " (Recovered)"
		archive:SetAttribute("EclipseSave", true)
		archive:SetAttribute("EclipseProjectId", Http:GenerateGUID(false))
		archive:SetAttribute("EclipseLiveProject", true)
		archive:SetAttribute("EclipseCompleteSave", false)
		archive:SetAttribute("EclipseRecoveredAt", row.time)
		return archive
	end

	function journal:importLegacy(row, archive)
		local folder = parent:FindFirstChild("ImportedRecovery")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "ImportedRecovery"
			folder.Parent = parent
		end

		for _, entry in folder:GetChildren() do
			if entry:GetAttribute("Token") == row.token then
				archive:Destroy()
				return assert(read(entry))
			end
		end

		local entry = Instance.new("Folder")
		entry.Name = "Legacy" .. row.slot .. "_" .. row.bank
		entry:SetAttribute("Slot", row.slot)
		entry:SetAttribute("Bank", row.bank)
		entry:SetAttribute("ProjectId", row.id)
		entry:SetAttribute("Title", row.name)
		entry:SetAttribute("Time", row.time)
		entry:SetAttribute("Token", row.token)
		entry:SetAttribute("PlaceName", row.placeName)
		archive.Name = "Archive"
		archive.Parent = entry
		entry:SetAttribute("Complete", true)
		local valid = read(entry)
		if not valid then
			archive.Parent = nil
			entry:Destroy()
			error("Invalid legacy recovery copy")
		end

		entry.Parent = folder
		return valid
	end

	return journal
end

function Recovery.newRecentJournal(store, scope)
	local current = Recovery.newJournal(store, "Recent")
	local journals = { current, Recovery.newJournal(store, scope) }
	if scope ~= "Place_0" then
		table.insert(journals, Recovery.newJournal(store, "Place_0"))
	end

	local journal = {}

	function journal:list()
		local rows, errors, seen = {}, 0, {}
		for _, source in journals do
			local entries, issues = source:list()
			errors += issues
			for _, row in entries do
				if not seen[row.token] then
					seen[row.token] = true
					row.journal = source
					table.insert(rows, row)
				end
			end
		end

		table.sort(rows, function(a, b)
			return a.time > b.time
		end)
		return rows, errors
	end

	function journal:write(id, name, archive, budget)
		local row = current:write(id, name, archive, budget)
		row.journal = current
		return row
	end

	function journal:restore(row)
		return assert(row.journal):restore(row)
	end

	function journal:remove(row)
		return assert(row.journal):remove(row)
	end

	return journal
end

function Recovery.newPlaceRecoveryJournal(parent, store, scope)
	local place = Recovery.newPlaceJournal(parent)
	local legacy = parent:FindFirstChild("LegacySettings")
	if not legacy then
		legacy = Instance.new("Folder")
		legacy.Name = "LegacySettings"
		legacy.Parent = parent
	end

	local runtime = parent:FindFirstChild("RecoveryRuntime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "RecoveryRuntime"
		runtime.Archivable = false
		runtime:SetAttribute("Session", Http:GenerateGUID(false))
		runtime.Parent = parent
	end

	assert(
		runtime.Archivable == false and type(runtime:GetAttribute("Session")) == "string",
		"Invalid recovery session"
	)
	local session = runtime:GetAttribute("Session")
	local journal = {}

	local function parseKey(key)
		if type(key) ~= "string" then
			return
		end

		local name, slot, bank = key:match("^EclipseRecoveryV1_(.+)_(%d+)_(%d+)$")
		slot, bank = tonumber(slot), tonumber(bank)
		if
			name
			and (name == "Recent" or name:match("^Place_%d+$"))
			and slot
			and slot >= 1
			and slot <= SLOTS
			and (bank == 1 or bank == 2)
		then
			return name, slot, bank
		end
	end

	local function payload(entry)
		assert(
			entry:IsA("Folder")
				and entry.Parent == legacy
				and entry:GetAttribute("Complete") == true,
			"Incomplete legacy copy"
		)
		local length, count = entry:GetAttribute("Length"), entry:GetAttribute("Chunks")
		assert(type(length) == "number" and length > 0 and length <= LIMIT, "Invalid legacy size")
		assert(
			type(count) == "number"
				and count >= 1
				and count <= math.ceil(LIMIT / 100000)
				and count % 1 == 0,
			"Invalid legacy chunks"
		)
		local chunks = {}
		for index = 1, count do
			local chunk = entry:FindFirstChild(tostring(index))
			assert(chunk and chunk:IsA("StringValue") and chunk.Archivable, "Missing legacy chunk")
			chunks[index] = chunk.Value
		end

		local text = table.concat(chunks)
		assert(#text == length, "Incomplete legacy data")
		return text
	end

	local function decoded(entry)
		local name, slot, bank = parseKey(entry:GetAttribute("Setting"))
		assert(name, "Invalid legacy setting")
		local text = payload(entry)
		local reader = Recovery.newJournal({
			get = function()
				return text
			end,
		}, name)
		local row = assert(reader:read(slot, bank), "Invalid legacy copy")
		row.storage, row.entry, row.reader, row.encoded = journal, entry, reader, text
		return row
	end

	local function migrate(budget)
		local imported, errors, cleared = 0, 0, 0
		local keys, known = {}, {}

		local function add(key)
			if parseKey(key) and not known[key] then
				known[key] = true
				table.insert(keys, key)
			end
		end

		for _, name in { "Recent", scope, "Place_0" } do
			for slot = 1, SLOTS do
				for bank = 1, 2 do
					add("EclipseRecoveryV1_" .. name .. "_" .. slot .. "_" .. bank)
				end
			end
		end

		for _, entry in legacy:GetChildren() do
			add(entry:GetAttribute("Setting"))
		end

		for _, key in keys do
			if budget then
				budget()
			end

			local ok = pcall(function()
				local text = store.get(key)
				if text == nil or text == "EclipseRecoveryDeletedV1" then
					return
				end

				assert(type(text) == "string" and #text <= LIMIT, "Invalid legacy settings value")
				local existing
				for _, entry in legacy:GetChildren() do
					if entry:GetAttribute("Setting") == key then
						local valid, value = pcall(payload, entry)
						if valid and value == text then
							existing = entry
							break
						end
					end
				end

				local function clear(entry)
					local function commit()
						assert(
							entry.Archivable and payload(entry) == text,
							"Legacy place copy changed"
						)
						assert(store.get(key) == text, "Legacy setting changed")
						store.set(key, "EclipseRecoveryDeletedV1")
						assert(
							store.get(key) == "EclipseRecoveryDeletedV1",
							"Legacy cleanup could not be verified"
						)
					end

					if store.transaction then
						store.transaction(commit)
					else
						commit()
					end

					cleared += 1
				end

				if existing then
					clear(existing)
					return
				end

				local entry = Instance.new("Folder")
				entry.Name = Http:GenerateGUID(false)
				entry.Archivable = false
				entry:SetAttribute("Setting", key)
				entry:SetAttribute("CapturedSession", session)
				entry:SetAttribute("Length", #text)
				local count = 0
				local success, issue = pcall(function()
					entry.Parent = legacy
					for first = 1, #text, 100000 do
						count += 1
						local chunk = Instance.new("StringValue")
						chunk.Name = tostring(count)
						chunk.Value = text:sub(first, first + 99999)
						chunk.Parent = entry
						if budget then
							budget()
						end
					end

					entry:SetAttribute("Chunks", count)
					entry:SetAttribute("Complete", true)
					assert(payload(entry) == text, "Legacy copy verification failed")
					entry.Archivable = true
				end)
				if not success then
					entry:Destroy()
					error(issue, 0)
				end

				imported += 1
				clear(entry)
			end)
			if not ok then
				errors += 1
			end

			if budget then
				budget()
			end
		end

		return imported, errors, cleared
	end

	function journal:migrate(budget)
		if runtime:FindFirstChild("Migration") then
			return 0, 1, 0
		end

		local lock = Instance.new("Folder")
		lock.Name = "Migration"
		lock.Parent = runtime
		local ok, count, errors, cleared = pcall(migrate, budget)
		lock:Destroy()
		assert(ok, count)
		return count, errors, cleared
	end

	function journal:list()
		local rows, errors = place:list()
		for _, row in rows do
			row.storage = place
		end

		for _, entry in legacy:GetChildren() do
			local ok, row = pcall(decoded, entry)
			if ok then
				table.insert(rows, row)
			else
				errors += 1
			end
		end

		table.sort(rows, function(a, b)
			return a.time > b.time
		end)
		return rows, errors
	end

	function journal:write(id, name, archive, budget)
		return place:write(id, name, archive, budget)
	end

	function journal:ownsArchive(archive)
		return place:ownsArchive(archive)
	end

	function journal:restore(row)
		if row.storage == place then
			return place:restore(row)
		end

		assert(payload(row.entry) == row.encoded, "Legacy copy changed")
		return row.reader:restore(row)
	end

	function journal:remove(row)
		if row.storage == place then
			return place:remove(row)
		end

		assert(payload(row.entry) == row.encoded, "Legacy copy changed")
		local key = row.entry:GetAttribute("Setting")

		local function clear()
			if store.get(key) == row.encoded then
				store.set(key, "EclipseRecoveryDeletedV1")
				assert(
					store.get(key) == "EclipseRecoveryDeletedV1",
					"Legacy deletion could not be verified"
				)
			end
		end

		if store.transaction then
			store.transaction(clear)
		else
			clear()
		end

		row.entry:Destroy()
	end

	return journal
end

local autosave, recoveryWindow

function Recovery.migrateSession(session)
	if session.stopped or not session.journal or session.legacyImported or session.migratingLegacy then
		return
	end

	session.migratingLegacy = true

	local function budget()
		game:GetService("RunService").Heartbeat:Wait()
		assert(not session.stopped, "Recovery migration was interrupted; old copies are retained")
	end

	local ok, count, errors = pcall(session.journal.migrate, session.journal, budget)
	session.migratingLegacy = false
	session.legacyCount = ok and count or 0
	session.legacyErrors = ok and errors or 1
	session.legacyImported = ok and errors == 0
	return ok and count or 0, session.legacyErrors
end

function Recovery.checkpoint()
	local session = autosave
	if not session or session.busy or session.stopped or not session.journal then
		return false
	end

	local refs = session.refs
	local state = refs.State
	local timeline = state.Timeline
	require("WorkBudget").settle()
	if
		not timeline
		or not refs.Active()
		or state.LoadingProject
		or state.PhysicsSimulating
		or state.LiveSession and state.LiveSession.recoveryToken and state.LiveSession.recoveryToken() == nil
	then
		return false
	end

	local raw = timeline:GetState()

	if
		raw.Exporting
		or raw.Playing
		or timeline:IsExportLocked()
		or timeline.IsBlenderKeyframeTransformActive and timeline:IsBlenderKeyframeTransformActive()
		or require("History").isApplying()
	then
		return false
	end

	local interaction = require("RawState")
	if
		state.scoreDragStarted
		or interaction.KeyframeDrag.draggingKeyframe
		or interaction.KeyframeTransform.active
		or game:GetService("UserInputService"):IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	then
		return false
	end

	local axis = state.Axis
	if
		axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
	then
		return false
	end

	if state.PropertyGizmo and state.PropertyGizmo.isEditing() then
		return false
	end

	session.busy = coroutine.running()
	local archive
	local revision = session.revision
	local keyframes = raw.Keyframes
	local live = state.LiveSession
	local liveToken = live and live.recoveryToken and live.recoveryToken()
	local cancelled = false
	local ok, result = xpcall(function()
		local identity = state.currentProjectSave
				and state.currentProjectSave:GetAttribute("EclipseProjectId")
			or state.currentProjectSequence and state.currentProjectSequence:GetAttribute(
				"EclipseAnimationId"
			)
			or raw.Keyframes
		if session.identity ~= identity then
			session.identity = identity
			session.document = type(identity) == "string"
					and #identity > 0
					and #identity <= 128
					and identity
				or Http:GenerateGUID(false)
		end

		local function current()
			local valid = not session.stopped
				and (not live or not live.recoveryToken or live.recoveryToken() == liveToken)
				and session.revision == revision
				and state.Timeline == timeline
				and timeline:GetState().Keyframes == keyframes
				and not state.LoadingProject
				and not state.PhysicsSimulating
				and not raw.Playing
				and not raw.Exporting
				and not timeline:IsExportLocked()
				and not state.scoreDragStarted
				and not interaction.KeyframeDrag.draggingKeyframe
				and not interaction.KeyframeTransform.active
				and not (state.PropertyGizmo and state.PropertyGizmo.isEditing())
				and not game:GetService("UserInputService")
					:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
				and not (
					axis
					and (
						axis:IsHoldingAxis()
						or axis:IsBlenderGrabMode()
						or axis:IsBlenderRotateMode()
					)
				)
			if not valid then
				cancelled = true
			end

			assert(valid, "Recovery changed; retrying")
		end

		local deadline = os.clock() + 0.002

		local function budget()
			if os.clock() < deadline then
				return
			end

			game:GetService("RunService").Heartbeat:Wait()
			current()
			deadline = os.clock() + 0.002
		end

		archive = refs.Archive(budget)
		current()
		return session.journal:write(session.document, refs.Name(), archive, budget)
	end, debug.traceback)
	if archive and not (session.journal.ownsArchive and session.journal:ownsArchive(archive)) then
		archive:Destroy()
	end

	session.busy = false
	session.lastWrite = os.clock()
	if not ok and cancelled then
		session.due = os.clock() + 5
		return false, result
	end

	session.due = if ok and session.revision == revision then math.huge else os.clock() + 30
	if ok then
		session.status = "Last place copy: "
			.. DateTime.fromUnixTimestampMillis(result.time):FormatLocalTime("HH:mm:ss", "en-us")
		session.warned = false
	else
		session.status = "Recovery needs attention. Save Eclipse and the Studio place."
		if not session.stopped and not session.warned then
			session.warned = true
			warn("[Eclipse recovery] " .. tostring(result))
			require("Notification").show("AUTOSAVE NEEDS ATTENTION", session.status)
		end
	end

	return ok, result
end

function Recovery.openAutosaves()
	if recoveryWindow then
		recoveryWindow:close()
		return
	end

	local session = autosave
	if not session then
		return
	end

	local Tool = require("Tool")
	local refs = session.refs
	local w = Tool.new(refs, "EclipseRecovery", "RECOVERY", Vector2.new(500, 360), false, function()
		recoveryWindow = nil
	end, { AllowMainMenu = true })
	recoveryWindow = w
	local status = Tool.label(
		w.frame,
		"Status",
		"Copies are stored in this place. Crash recovery uses Studio Auto-Recovery.",
		UDim2.fromOffset(12, 38),
		UDim2.new(1, -24, 0, 44)
	)
	status.TextWrapped = true
	status.TextSize = 18
	local list = Tool.make("ScrollingFrame", w.frame, "Copies", {
		Position = UDim2.fromOffset(12, 90),
		Size = UDim2.new(1, -24, 1, -136),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ZIndex = 12,
	})
	while session.migratingLegacy and not session.stopped do
		task.wait()
	end

	if session.stopped then
		return
	end

	Recovery.migrateSession(session)
	if (session.legacyCount or 0) > 0 then
		status.Text = "Older backups moved into this place and removed from plugin data."
	end

	local legacyErrors = session.legacyErrors or 0
	local rows, errors = {}, 0
	if session.journal then
		local listed, found, issues = pcall(session.journal.list, session.journal)
		if listed then
			rows, errors = found, issues
		else
			errors = 1
			warn("[Eclipse recovery] " .. tostring(found))
		end
	else
		status.Text = session.status
	end

	errors += legacyErrors
	local seen = {}
	local count = 0
	for _, row in rows do
		if seen[row.token] then
			continue
		end

		seen[row.token] = true
		count += 1
		local title = "RESTORE  "
			.. DateTime.fromUnixTimestampMillis(row.time):FormatLocalTime("MMM D HH:mm:ss", "en-us")
			.. "  "
			.. row.name
		if type(row.placeName) == "string" then
			title ..= " [" .. row.placeName .. "]"
		end

		local b, label = Tool.button(
			list,
			"Copy" .. count,
			title,
			UDim2.fromOffset(0, (count - 1) * 32),
			UDim2.new(1, -80, 0, 28),

			function()
				if w.busy then
					return
				end

				w.busy = true
				local restored
				local ok, message = pcall(function()
					restored = session.journal:restore(row)
					local parent = require("root").get("EclipseAnimator_Saves", true)
					local base = restored.Name
					local index = 2
					while parent:FindFirstChild(restored.Name) do
						restored.Name = base .. " " .. index
						index += 1
					end

					restored.Parent = parent
				end)
				w.busy = false
				if ok then
					require("Notification").show(
						"PROJECT RECOVERED",
						"Open " .. restored.Name .. " from Home > Projects."
					)
				else
					if restored then
						restored:Destroy()
					end

					require("Notification").show(
						"RECOVERY FAILED",
						"Could not restore this copy. Try the earlier copy."
					)
					warn(message)
				end
			end
		)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		Tool.button(
			list,
			"Delete" .. count,
			"DELETE",
			UDim2.new(1, -74, 0, (count - 1) * 32),
			UDim2.fromOffset(68, 28),

			function()
				if w.busy then
					return
				end

				w.busy = true
				local ok, message = pcall(function()
					for _, copy in rows do
						if copy.token == row.token then
							session.journal:remove(copy)
						end
					end
				end)
				w.busy = false
				if ok then
					w:close()
					Recovery.openAutosaves()
				else
					require("Notification").show("RECOVERY", tostring(message))
				end
			end
		)
	end

	list.CanvasSize = UDim2.fromOffset(0, count * 32)
	if errors > 0 then
		require("Notification").show(
			"RECOVERY NEEDS ATTENTION",
			count == 0 and "Local recovery could not be read. Retry shortly."
				or "Some copies could not be read. Earlier readable copies are shown."
		)
	end

	Tool.button(w.frame, "Close", "CLOSE", UDim2.new(1, -112, 1, -36), UDim2.fromOffset(100, 26), function()
		w:close()
	end
)
	require("Theme").applyTree(w.frame)
	return w
end

function Recovery.initAutosave(refs)
	if autosave then
		autosave.stop()
	end

	local session = {
		refs = refs,
		due = os.clock() + 30,
		revision = 0,
		lastWrite = -math.huge,
		status = "Automatic recovery saves in this place after editing settles.",
	}
	autosave = session
	const opened, journal = xpcall(function()
		return Recovery.newPlaceRecoveryJournal(require("root").get("EclipseRecovery", true), {
			get = function(key)
				return refs.Plugin:GetSetting(key)
			end,
			set = function(key, value)
				assert(
					value == "EclipseRecoveryDeletedV1",
					"Recovery snapshots cannot be written to plugin settings"
				)
				refs.Plugin:SetSetting(key, value)
			end,
			transaction = require("ProjectData").withSettingsWriter,
		}, "Place_" .. tostring(game.PlaceId))
	end, debug.traceback)
	if opened then
		session.journal = journal
	else
		session.due = math.huge
		session.status = "Recovery copies could not be opened in this place. Save the project and the Studio place manually."
		warn("[Eclipse recovery] " .. tostring(journal))
	end

	local unsubscribe = require("History").subscribe(function()
		session.revision += 1
		session.due = math.min(session.due, math.max(os.clock() + 5, session.lastWrite + 30))
	end)
	local connection = game:GetService("RunService").Heartbeat:Connect(function()
		if type(session.busy) == "thread" and coroutine.status(session.busy) == "dead" then
			session.busy = false
		end

		if session.stopped or session.busy or os.clock() < session.due then
			return
		end

		session.due = os.clock() + 1
		task.spawn(Recovery.checkpoint)
	end)
	local unloading, destroying
	local settings = refs.HomeMenu:FindFirstChild("SettingsButton")
	local button = assert(settings, "Home Settings button is missing"):Clone()
	button.Name = "RecoveryButton"
	button.LayoutOrder = settings.LayoutOrder - 1
	local label = assert(button:FindFirstChildWhichIsA("TextLabel"))
	label.Text = "RECOVERY"
	button.Parent = refs.HomeMenu
	button.Activated:Connect(Recovery.openAutosaves)
	const styled, issue = pcall(function()
		const style = require("Style").bind(button, label)
		button.MouseEnter:Connect(style.hover)
		button.MouseLeave:Connect(style.idle)
		button.MouseButton1Down:Connect(style.open)
		button.Activated:Connect(style.hover)
		require("Theme").applyTree(button)
		style.idle()
	end)
	if not styled then
		warn("[Eclipse recovery] " .. tostring(issue))
	end

	function session.stop()
		if session.stopped then
			return
		end

		session.stopped = true
		connection:Disconnect()
		unsubscribe()
		button:Destroy()
		if unloading then
			unloading:Disconnect()
		end

		if destroying then
			destroying:Disconnect()
		end

		if recoveryWindow then
			recoveryWindow:close(true)
			recoveryWindow = nil
		end
	end

	unloading = refs.Plugin.Unloading:Connect(session.stop)
	destroying = refs.ScreenGui.Destroying:Once(session.stop)

	task.defer(function()
		Recovery.migrateSession(session)
	end)
end

return Recovery
