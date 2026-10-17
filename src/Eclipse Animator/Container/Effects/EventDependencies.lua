--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Collection = game:GetService("CollectionService")
local Cleanup = require("DumpStorage")
local Dependencies = {}
Dependencies.__index = Dependencies
local active = setmetatable({}, { __mode = "k" })
local poseDepth = 0
local poseWriting = 0
local spatial = {
	CFrame = true,
	Position = true,
	Orientation = true,
	Rotation = true,
	WorldPivot = true,
	Transform = true,
	C0 = true,
	C1 = true,
}
local derived = {
	WorldCFrame = true,
	WorldPosition = true,
	WorldOrientation = true,
	WorldAxis = true,
	WorldSecondaryAxis = true,
	TransformedCFrame = true,
	TransformedWorldCFrame = true,
	Mass = true,
	AssemblyCenterOfMass = true,
	AssemblyMass = true,
	AssemblyRootPart = true,
	AssemblyLinearVelocity = true,
	AssemblyAngularVelocity = true,
}
local partTransform = { "CFrame", "Position", "Orientation", "Rotation" }
local attachmentTransform = { "CFrame", "Position", "Orientation", "Axis", "SecondaryAxis" }
local texture = { "Texture", "TextureContent" }
local color = { "Color", "BrickColor" }
local single = {}
local classProperties = {}
local inputProperties = {}
local ALL_ATTRIBUTES = {}
local NIL_READ_BUDGET = 0.0005
local worldTransform = {
	WorldCFrame = true,
	WorldPosition = true,
	WorldOrientation = true,
	WorldAxis = true,
	WorldSecondaryAxis = true,
	TransformedCFrame = true,
	TransformedWorldCFrame = true,
}
local boundsProperties = {
	CFrame = true,
	Position = true,
	Orientation = true,
	Rotation = true,
	Size = true,
	PivotOffset = true,
	Parent = true,
}
local particleProperties = {
	"Enabled",
	"TimeScale",
	"Rate",
	"Texture",
	"TextureContent",
	"Color",
	"Size",
	"Transparency",
	"Squash",
	"Rotation",
	"RotSpeed",
	"Lifetime",
	"Speed",
	"SpreadAngle",
	"Acceleration",
	"Drag",
	"EmissionDirection",
	"Shape",
	"ShapeStyle",
	"ShapeInOut",
	"ShapePartial",
	"LockedToPart",
	"VelocityInheritance",
	"WindAffectsDrag",
	"Orientation",
	"FlipbookLayout",
	"FlipbookSizeX",
	"FlipbookSizeY",
	"FlipbookMode",
	"FlipbookFramerate",
	"FlipbookStartRandom",
	"FlipbookBlendFrames",
	"LightEmission",
	"LightInfluence",
	"Brightness",
	"ZOffset",
	"LocalTransparencyModifier",
}
local scaledProperties = {
	ParticleEmitter = { "Size", "Speed", "Acceleration" },
	Beam = { "Width0", "Width1", "CurveSize0", "CurveSize1" },
	Trail = { "MinLength", "MaxLength" },
	Fire = { "Size", "Heat" },
	Smoke = { "Size", "RiseVelocity" },
	Sound = { "RollOffMinDistance", "RollOffMaxDistance", "EmitterSize" },
	BillboardGui = { "Size", "StudsOffset", "StudsOffsetWorldSpace", "MaxDistance" },
	SurfaceGui = { "PixelsPerStud" },
	RopeConstraint = { "Length", "Thickness" },
	RodConstraint = { "Length", "Thickness" },
	SpringConstraint = { "FreeLength", "MinLength", "MaxLength", "Radius", "Thickness" },
}

local function get(object, key, kind)
	if kind == "Attribute" then
		return object:GetAttribute(key)
	end

	if kind == "Tag" then
		return object:HasTag(key)
	end

	if kind == "Scale" then
		return object:GetScale()
	end

	return object[key]
end

local function equal(a, b)
	if a == b then
		return true
	end

	local kind = typeof(a)
	if kind ~= typeof(b) then
		return false
	end

	if kind == "NumberSequence" or kind == "ColorSequence" then
		local left, right = a.Keypoints, b.Keypoints
		if #left ~= #right then
			return false
		end

		for i, v in left do
			local other = right[i]
			if
				v.Time ~= other.Time
				or v.Value ~= other.Value
				or kind == "NumberSequence" and v.Envelope ~= other.Envelope
			then
				return false
			end
		end

		return true
	end

	return false
end

function Dependencies.new(clock, nilValue)
	local self = setmetatable({
		clock = clock,
		NIL = nilValue,
		entries = {},
		connections = {},
		tagNames = {},
		tagQueries = {},
		tagReads = {},
		pendingNil = {},
		pendingOrder = {},
		pendingCursor = 1,
		modelEntries = 0,
		spatialParents = {},
		rigs = {},
		posed = {},
		runtime = setmetatable({}, { __mode = "k" }),
		revision = 0,
		changedAt = 0,
		closed = false,
		polls = 0,
	}, Dependencies)
	for _, tag in Collection:GetAllTags() do
		self:tag(tag)
	end

	table.insert(
		self.connections,
		Collection.TagAdded:Connect(function(tag)
			if self.closed then
				return
			end

			self:tag(tag)
			for object, entry in self.entries do
				if
					(entry.full or entry.allTags or entry.tags[tag] ~= nil)
					and object:HasTag(tag)
				then
					self:check(entry, tag, "Tag", true)
				end
			end
		end)
	)
	active[self] = true
	return self
end

function Dependencies:tag(tag)
	if type(tag) ~= "string" or tag == "" then
		return
	end

	if self.tagNames[tag] then
		return
	end

	self.tagNames[tag] = true

	local function changed(object)
		if self.closed or self:ignore(object) then
			return
		end

		local revision = self.revision
		local entry = self.entries[object]
		if entry and (entry.full or entry.allTags or entry.tags[tag] ~= nil) then
			self:check(entry, tag, "Tag", true)
		end

		local reads = self.tagReads[tag]
		local present = object:HasTag(tag)
		local edited = reads and reads[object] ~= nil and reads[object] ~= present
		if reads and reads[object] ~= nil then
			reads[object] = present
		end

		local query = self.tagQueries[tag]
		if query then
			local included = present and object:IsDescendantOf(game)
			if (query[object] == true) ~= included then
				query[object] = included or nil
				edited = true
			end
		end

		if edited and self.revision == revision then
			self:changed()
		end
	end

	table.insert(self.connections, Collection:GetInstanceAddedSignal(tag):Connect(changed))
	table.insert(self.connections, Collection:GetInstanceRemovedSignal(tag):Connect(changed))
end

function Dependencies.withPose(callback)
	poseDepth += 1
	local result = table.pack(xpcall(callback, debug.traceback))
	poseDepth -= 1
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

function Dependencies.isPosing()
	return poseDepth > 0
end

function Dependencies.poseModel(object, mode, value)
	local writes = {}
	for self in active do
		local watched = {}
		for child in self.entries do
			if child == object or child:IsDescendantOf(object) then
				table.insert(watched, child)
			end
		end

		self:treeKeys(object, mode, function(_, child, key, kind)
			local entry = self.entries[child]
			if not entry then
				return
			end

			self:check(entry, key, kind)
			table.insert(writes, { self, child, key, kind })
		end, watched)
	end

	poseWriting += 1
	local ok, err = pcall(function()
		if mode == "scale" then
			object:ScaleTo(value)
		else
			object:PivotTo(value)
		end
	end)
	poseWriting -= 1
	for _, row in writes do
		row[1]:after(row[2], row[3], row[4])
	end

	if not ok then
		error(err, 0)
	end
end

local function writePose(object, key, value)
	object[key] = value
	for self in active do
		if self.entries[object] then
			if object:IsA("ParticleEmitter") and (key == "Enabled" or key == "TimeScale") then
				self:rebase(object, key, value)
			end

			self:after(object, key)
		end
	end
end

function Dependencies.poseWrite(object, key, value)
	for self in active do
		local entry = self.entries[object]
		if entry then
			self:check(entry, key)
		end
	end

	poseWriting += 1
	local ok, err = pcall(writePose, object, key, value)
	poseWriting -= 1
	if not ok then
		error(err, 0)
	end
end

function Dependencies.poseAttribute(object, key, value)
	local source = typeof(object) == "table"
			and (rawget(object, "_bone") or rawget(object, "_anchor") or object)
		or object
	for self in active do
		local entry = self.entries[source]
		if entry then
			self:check(entry, key, "Attribute")
		end
	end

	object:SetAttribute(key, value)
	for self in active do
		if self.entries[source] then
			self:after(source, key, "Attribute")
		end
	end
end

function Dependencies:ignore(object)
	if self.closed or not object then
		return true
	end

	if self.runtime[object] then
		return true
	end

	local current = object
	while current and current ~= game do
		if
			self.clock.owned[current]
			or self.clock.internal[current]
			or self.runtime[current]
			or Cleanup.isVisual(current)
		then
			self.runtime[object] = true
			return true
		end

		current = current.Parent
	end

	return false
end

function Dependencies:addRig(rig)
	self.rigs[rig] = true
	local pending = { rig }
	local links = {}
	while #pending > 0 do
		local object = table.remove(pending)
		if
			object:IsA("ValueBase")
			or object:IsA("LuaSourceContainer")
			or object:IsA("KeyframeSequence")
			or object:IsA("Keyframe")
			or object:IsA("Pose")
		then
			continue
		end

		if object:IsA("Motor6D") then
			self.posed[object] = true
			if object.Part0 then
				self.posed[object.Part0] = true
			end

			if object.Part1 then
				self.posed[object.Part1] = true
			end
		elseif object:IsA("Bone") then
			self.posed[object] = true
		elseif object:IsA("JointInstance") or object:IsA("WeldConstraint") then
			table.insert(links, object)
		end

		for _, child in object:GetChildren() do
			table.insert(pending, child)
		end
	end

	local changed = true
	while changed do
		changed = false
		for _, joint in links do
			local a, b = joint.Part0, joint.Part1
			if
				a
				and b
				and (self.posed[a] or self.posed[b])
				and not (self.posed[a] and self.posed[b])
			then
				self.posed[a], self.posed[b] = true, true
				changed = true
			end
		end
	end

	for object, entry in self.entries do
		entry.rig = self:inRig(object)
	end
end

function Dependencies:inRig(object)
	for rig in self.rigs do
		if object == rig or object:IsDescendantOf(rig) then
			return true
		end
	end

	return false
end

function Dependencies:group(object, key)
	if
		(key == "Texture" or key == "TextureContent")
		and (object:IsA("ParticleEmitter") or object:IsA("Decal"))
	then
		return texture
	end

	if (key == "Color" or key == "BrickColor") and object:IsA("BasePart") then
		return color
	end

	if
		object:IsA("BasePart")
		and spatial[key]
		and key ~= "Transform"
		and key ~= "C0"
		and key ~= "C1"
		and key ~= "WorldPivot"
	then
		return partTransform
	end

	if
		object:IsA("Attachment")
		and (
			key == "CFrame"
			or key == "Position"
			or key == "Orientation"
			or key == "Axis"
			or key == "SecondaryAxis"
		)
	then
		return attachmentTransform
	end

	if not single[key] then
		single[key] = { key }
	end

	return single[key]
end

function Dependencies:skip(entry, key)
	if derived[key] then
		return true
	end

	local object = entry.object
	if self.rigs[object] and key == "WorldPivot" then
		return true
	end

	if not self.posed[object] then
		return false
	end

	if object:IsA("BasePart") then
		return key == "CFrame" or key == "Position" or key == "Orientation" or key == "Rotation"
	end

	if object:IsA("Motor6D") then
		return key == "C0" or key == "Transform"
	end

	return object:IsA("Bone") and key == "Transform"
end

function Dependencies:changed()
	self.revision += 1
	self.changedAt = os.clock()
end

function Dependencies:rebase(object, key, value, kind)
	local clock = self.clock
	local original
	if kind == "Attribute" then
		original = clock.attributes[object]
	elseif kind == "Tag" then
		original = clock.tags[object]
	elseif kind == "Scale" then
		original = clock.scales
	else
		original = clock.originals[object]
	end

	local index = kind == "Scale" and object or key
	if original and original[index] ~= nil then
		original[index] = value == nil and self.NIL or value
		clock.cleanup:update(object, key, value, kind)
	end

	if not kind and object:IsA("ParticleEmitter") and (key == "Enabled" or key == "TimeScale") then
		local state = clock.particles.emitters[object]
		if state then
			state[key] = value
			clock.originals[object] = clock.originals[object] or {}
			clock.originals[object][key] = value
			clock.cleanup:update(object, key, value)
			if key == "Enabled" then
				object.Enabled = false
			else
				object.TimeScale = 0
			end
		end
	end
end

function Dependencies:check(entry, key, kind, force)
	if
		poseWriting > 0
		or self.closed
		or self:ignore(entry.object)
		or not kind and self:skip(entry, key)
	then
		return
	end

	local object = entry.object
	local values = kind == "Attribute" and entry.attributes
		or kind == "Tag" and entry.tags
		or kind == "Scale" and entry.scales
		or entry.values
	local keys = kind and (single[key] or { key }) or self:group(object, key)
	local edits = {}
	for _, field in keys do
		local ok, value = pcall(get, object, field, kind)
		if ok then
			local encoded = value == nil and self.NIL or value
			if
				values[field] ~= nil and not equal(values[field], encoded)
				or force and values[field] == nil
			then
				edits[field] = encoded
			end
		end
	end

	if next(edits) == nil then
		return
	end

	for field, encoded in edits do
		local value = encoded
		if value == self.NIL then
			value = nil
		end

		self:rebase(object, field, value, kind)
		local ok, value = pcall(get, object, field, kind)
		if ok then
			values[field] = value == nil and self.NIL or value
		end
	end

	if not kind and edits.Parent then
		entry.rig = self:inRig(object)
		self:ancestors(object)
	end

	self:changed()
end

function Dependencies:children(entry, child)
	if self.closed or self:ignore(child) then
		return
	end

	local present = child.Parent == entry.object
	if (entry.children[child] == true) == present then
		return
	end

	entry.children[child] = present or nil
	if present then
		self:watch(child, entry.tree)
	end

	self:changed()
end

function Dependencies:input(object)
	local entry = self.entries[object]
	if entry then
		return entry
	end

	if self:ignore(object) then
		return nil
	end

	entry = {
		object = object,
		full = false,
		values = { Name = object.Name, Parent = object.Parent or self.NIL },
		attributes = {},
		tags = {},
		scales = {},
		written = {},
		children = {},
		inputKeys = { Name = true, Parent = true },
		attributeKeys = {},
		rig = self:inRig(object),
	}
	self.entries[object] = entry
	if object:IsA("Model") then
		self.modelEntries += 1
	end

	self:listenProperties(entry)
	return entry
end

function Dependencies:listenProperties(entry)
	if entry.propertyConnection then
		return
	end

	local object = entry.object
	local valueBase = object:IsA("ValueBase")

	local function changed(key)
		if self.closed or not (entry.full or entry.inputKeys[key]) then
			return
		end

		self:check(entry, key, nil, true)
	end

	entry.propertyConnection = object.Changed:Connect(function(key)
		changed(valueBase and "Value" or key)
	end)
	table.insert(self.connections, entry.propertyConnection)
	if valueBase then
		for _, key in { "Name", "Parent" } do
			table.insert(
				self.connections,
				object:GetPropertyChangedSignal(key):Connect(function()
					changed(key)
				end)
			)
		end
	end
end

function Dependencies:listenAttributes(entry)
	if entry.attributeConnection then
		return
	end

	entry.attributeConnection = entry.object.AttributeChanged:Connect(function(key)
		if entry.full or entry.allAttributes or entry.attributeKeys[key] then
			self:check(entry, key, "Attribute", true)
		end
	end)
	table.insert(self.connections, entry.attributeConnection)
end

function Dependencies:pending(object, key)
	local bucket = self.pendingNil[key]
	if not bucket then
		bucket = { key = key, items = {}, members = {}, cursor = 1, count = 0 }
		self.pendingNil[key] = bucket
		table.insert(self.pendingOrder, bucket)
	end

	if bucket.members[object] ~= nil then
		return
	end

	bucket.members[object] = object.Parent ~= nil or object == game
	table.insert(bucket.items, object)
	bucket.count += 1
end

function Dependencies:takePending(object, key)
	local bucket = self.pendingNil[key]
	if not bucket or bucket.members[object] == nil then
		return false
	end

	bucket.members[object] = nil
	bucket.count -= 1
	return true
end

function Dependencies:promotePending(entry)
	local object = entry.object
	for key, bucket in self.pendingNil do
		if bucket.members[object] == nil then
			continue
		end

		self:takePending(object, key)
		self:listenAttributes(entry)
		if key == ALL_ATTRIBUTES then
			entry.allAttributes = true
			if next(object:GetAttributes()) ~= nil then
				self:changed()
			end
		else
			entry.attributeKeys[key] = true
			entry.attributes[key] = self.NIL
			self:check(entry, key, "Attribute")
		end
	end
end

function Dependencies:readTransform(object)
	if self:ignore(object) then
		return
	end

	if object:IsA("BasePart") then
		self:read(object, "CFrame", object.CFrame)
	elseif object:IsA("Attachment") then
		self:read(object, "CFrame", object.CFrame)
		if object:IsA("Bone") then
			self:read(object, "Transform", object.Transform)
		end

		local parent = object.Parent
		if parent and (parent:IsA("Attachment") or parent:IsA("BasePart")) then
			self:readTransform(parent)
		end
	end
end

function Dependencies:readPivot(object)
	if self:ignore(object) then
		return
	end

	if object:IsA("BasePart") then
		self:readTransform(object)
		self:read(object, "PivotOffset", object.PivotOffset)
		return
	end

	if not object:IsA("Model") then
		return
	end

	self:read(object, "WorldPivot", object.WorldPivot)
	self:read(object, "PrimaryPart", object.PrimaryPart)
	if object.PrimaryPart then
		self:readPivot(object.PrimaryPart)
		return
	end

	local entry = self.entries[object]
	if not entry or entry.pivotChildren then
		return
	end

	entry.pivotChildren = true
	entry.pivotParts = {}

	local function observe(part)
		if not part:IsA("BasePart") or self:ignore(part) then
			return
		end

		entry.pivotParts[part] = true
		self:readTransform(part)
		self:read(part, "Size", part.Size)
		self:read(part, "PivotOffset", part.PivotOffset)
	end

	for _, part in object:GetDescendants() do
		observe(part)
	end

	local function changed(part)
		if self.closed or not part:IsA("BasePart") or self:ignore(part) then
			return
		end

		local present = part:IsDescendantOf(object)
		if (entry.pivotParts[part] == true) == present then
			return
		end

		entry.pivotParts[part] = present or nil
		if present then
			observe(part)
		end

		self:changed()
	end

	table.insert(self.connections, object.DescendantAdded:Connect(changed))
	table.insert(self.connections, object.DescendantRemoving:Connect(changed))
end

function Dependencies:pivotTree(object, check)
	local objects
	for model, entry in self.entries do
		if not entry.pivotParts then
			continue
		end

		if not objects then
			objects = object:GetDescendants()
			table.insert(objects, object)
		end

		for _, part in objects do
			if not part:IsA("BasePart") or self:ignore(part) then
				continue
			end

			local present = part:IsDescendantOf(model)
			if (entry.pivotParts[part] == true) ~= present then
				entry.pivotParts[part] = present or nil
				if present then
					self:readTransform(part)
					self:read(part, "Size", part.Size)
					self:read(part, "PivotOffset", part.PivotOffset)
				end

				if check then
					self:changed()
				end
			end
		end
	end
end

function Dependencies:read(object, key, value, kind)
	if
		self.closed
		or self.clock.owned[object]
		or self.clock.internal[object]
		or self.runtime[object]
		or Cleanup.isVisual(object)
	then
		return
	end

	if kind == "Tag" then
		if self:ignore(object) then
			return
		end

		self:tag(key)
		local reads = self.tagReads[key]
		if not reads then
			reads = {}
			self.tagReads[key] = reads
		end

		if reads[object] ~= nil and reads[object] ~= value then
			self:changed()
		end

		reads[object] = value
		return
	end

	local entry = self.entries[object]
	if kind == "Attribute" and value == nil and not entry then
		self:pending(object, key)
		return
	end

	if not kind then
		if worldTransform[key] and object:IsA("Attachment") then
			self:readTransform(object)
			return
		end

		if
			key == "ClassName"
			or derived[key]
			or (key == "Name" or key == "Parent") and not entry
		then
			return
		end

		local className = object.ClassName
		local properties = inputProperties[className]
		if not properties then
			properties = {}
			inputProperties[className] = properties
		end

		if properties[key] == nil then
			properties[key] = pcall(object.GetPropertyChangedSignal, object, key)
		end

		if not properties[key] then
			return
		end
	end

	entry = entry or self:input(object)
	if not entry then
		return
	end

	if kind == "Attribute" then
		self:listenAttributes(entry)
		entry.attributeKeys[key] = true
		if self:takePending(object, key) then
			entry.attributes[key] = self.NIL
		end

		if entry.attributes[key] ~= nil then
			local encoded = value == nil and self.NIL or value
			if not equal(entry.attributes[key], encoded) then
				self:check(entry, key, "Attribute")
			end
		else
			entry.attributes[key] = value == nil and self.NIL or value
		end
	else
		if
			entry.values[key] ~= nil
			and equal(entry.values[key], value == nil and self.NIL or value)
		then
			return
		end

		for _, field in self:group(object, key) do
			entry.inputKeys[field] = true
			if entry.values[field] == nil then
				local ok, current = pcall(get, object, field)
				if ok then
					entry.values[field] = current == nil and self.NIL or current
				end
			end
		end

		self:check(entry, key)
	end
end

function Dependencies:readAttributes(object, values)
	if
		self.closed
		or self.clock.owned[object]
		or self.clock.internal[object]
		or self.runtime[object]
		or Cleanup.isVisual(object)
	then
		return
	end

	local entry = self.entries[object]
	if not entry and next(values) == nil then
		self:pending(object, ALL_ATTRIBUTES)
		return
	end

	entry = entry or self:input(object)
	if not entry then
		return
	end

	local wasEmpty = self:takePending(object, ALL_ATTRIBUTES)
	self:listenAttributes(entry)
	local all = entry.allAttributes or entry.full
	entry.allAttributes = true
	for key, value in values do
		self:read(object, key, value, "Attribute")
	end

	if all then
		for key in entry.attributes do
			self:check(entry, key, "Attribute")
		end
	end

	if wasEmpty and next(values) ~= nil then
		self:changed()
	end
end

function Dependencies:readObjectTags(object, tags)
	local entry = self.entries[object] or self:input(object)
	if not entry then
		return
	end

	local all = entry.allTags or entry.full
	entry.allTags = true
	for _, tag in tags do
		self:tag(tag)
		if entry.tags[tag] == nil then
			entry.tags[tag] = true
			if all then
				self:changed()
			end
		else
			self:check(entry, tag, "Tag")
		end
	end

	if all then
		for tag in entry.tags do
			self:check(entry, tag, "Tag")
		end
	end
end

function Dependencies:readTags(tag, objects)
	if self.closed then
		return
	end

	self:tag(tag)
	local current = {}
	for _, object in objects do
		if not self:ignore(object) then
			current[object] = true
		end
	end

	local previous = self.tagQueries[tag]
	if previous then
		local different = false
		for object in current do
			if not previous[object] then
				different = true
				break
			end
		end

		if not different then
			for object in previous do
				if not current[object] then
					different = true
					break
				end
			end
		end

		if different then
			self:changed()
		end
	end

	self.tagQueries[tag] = current
end

function Dependencies:tagInput(object, tag, check)
	if self:ignore(object) then
		return
	end

	local reads, query = self.tagReads[tag], self.tagQueries[tag]
	if not query and not (reads and reads[object] ~= nil) then
		return
	end

	local present = object:HasTag(tag)
	local edited = false
	if reads and reads[object] ~= nil then
		edited = reads[object] ~= present
		reads[object] = present
	end

	if query then
		local included = present and object:IsDescendantOf(game)
		edited = edited or (query[object] == true) ~= included
		query[object] = included or nil
	end

	if check and edited then
		self:changed()
	end
end

function Dependencies:tagTree(object, check)
	if next(self.tagQueries) == nil and next(self.tagReads) == nil then
		return
	end

	local tags = {}
	for tag in self.tagQueries do
		tags[tag] = true
	end

	for tag in self.tagReads do
		tags[tag] = true
	end

	local objects = object:GetDescendants()
	table.insert(objects, object)
	for _, child in objects do
		for tag in tags do
			self:tagInput(child, tag, check)
		end
	end
end

function Dependencies:pollPending()
	if #self.pendingOrder == 0 then
		return
	end

	local deadline = os.clock() + NIL_READ_BUDGET
	local scanned = 0

	local visited, remaining = {}, #self.pendingOrder
	while #self.pendingOrder > 0 and remaining > 0 do
		if self.pendingCursor > #self.pendingOrder then
			self.pendingCursor = 1
		end

		local bucket = self.pendingOrder[self.pendingCursor]
		if bucket.count == 0 then
			self.pendingNil[bucket.key] = nil
			table.remove(self.pendingOrder, self.pendingCursor)
			remaining -= 1
		elseif (visited[bucket] or 0) >= #bucket.items then
			self.pendingCursor += 1
		else
			visited[bucket] = (visited[bucket] or 0) + 1
			if visited[bucket] >= #bucket.items then
				remaining -= 1
			end

			if bucket.cursor > #bucket.items then
				bucket.cursor = 1
			end

			local index = bucket.cursor
			local object = bucket.items[index]
			bucket.cursor += 1
			self.pendingCursor += 1
			local parented = bucket.members[object]
			if parented ~= nil then
				if
					parented and object ~= game and not object.Parent
					or self.clock.owned[object]
					or self.clock.internal[object]
					or self.runtime[object]
				then
					self:takePending(object, bucket.key)
				elseif self.entries[object] then
					self:promotePending(self.entries[object])
				elseif bucket.key == ALL_ATTRIBUTES then
					local ok, values = pcall(object.GetAttributes, object)
					if not ok then
						self:takePending(object, bucket.key)
					elseif next(values) ~= nil then
						self:readAttributes(object, values)
					end
				else
					local ok, value = pcall(object.GetAttribute, object, bucket.key)
					if not ok then
						self:takePending(object, bucket.key)
					elseif value ~= nil then
						self:read(object, bucket.key, value, "Attribute")
					end
				end
			end

			if bucket.members[object] == nil then
				bucket.items[index] = false
			end
		end

		scanned += 1
		if scanned % 16 == 0 and os.clock() >= deadline then
			break
		end
	end
end

function Dependencies:one(object)
	if self.entries[object] and self.entries[object].full then
		return self.entries[object]
	end

	if self:ignore(object) or object == game or object.Parent == game then
		return nil
	end

	local entry = self.entries[object] or self:input(object)
	entry.full = true
	for key, value in object:GetAttributes() do
		if entry.attributes[key] == nil then
			entry.attributes[key] = value
		end
	end

	local className = object.ClassName
	local cached = classProperties[className]
	if cached then
		for _, key in cached do
			local value = object[key]
			if entry.values[key] == nil then
				entry.values[key] = value == nil and self.NIL or value
			end
		end
	else
		local properties = { "Name", "Parent", "Archivable" }
		if object:IsA("ParticleEmitter") then
			for _, key in particleProperties do
				table.insert(properties, key)
			end
		elseif object:IsA("BasePart") then
			for _, key in
				{
					"CFrame",
					"Position",
					"Orientation",
					"Rotation",
					"Size",
					"Color",
					"BrickColor",
					"Transparency",
					"LocalTransparencyModifier",
					"Material",
					"MaterialVariant",
					"Reflectance",
					"Anchored",
					"CanCollide",
					"CanTouch",
					"CanQuery",
					"PivotOffset",
				}
			do
				table.insert(properties, key)
			end
		elseif object:IsA("Attachment") then
			for _, key in attachmentTransform do
				table.insert(properties, key)
			end
		elseif object:IsA("ValueBase") then
			table.insert(properties, "Value")
		elseif object:IsA("DataModelMesh") then
			for _, key in { "Scale", "Offset", "VertexColor" } do
				table.insert(properties, key)
			end
		elseif object:IsA("JointInstance") then
			for _, key in { "C0", "C1", "Part0", "Part1" } do
				table.insert(properties, key)
			end
		end

		local valid = {}
		for _, key in properties do
			local ok, value = pcall(get, object, key)
			if ok then
				table.insert(valid, key)
				if entry.values[key] == nil then
					entry.values[key] = value == nil and self.NIL or value
				end
			end
		end

		classProperties[className] = valid
	end

	for _, tag in object:GetTags() do
		if entry.tags[tag] == nil then
			entry.tags[tag] = true
		end
	end

	if object:IsA("Model") then
		entry.scales.Scale = object:GetScale()
	end

	for _, child in object:GetChildren() do
		if not self:ignore(child) then
			entry.children[child] = true
		end
	end

	self:listenProperties(entry)
	self:listenAttributes(entry)
	table.insert(
		self.connections,
		object.ChildAdded:Connect(function(child)
			self:children(entry, child)
		end)
	)
	table.insert(
		self.connections,
		object.ChildRemoved:Connect(function(child)
			self:children(entry, child)
		end)
	)
	self:promotePending(entry)
	return entry
end

function Dependencies:ancestors(object)
	local parent = object.Parent
	while parent and parent ~= game and parent.Parent ~= game do
		self:one(parent)
		if self.rigs[parent] then
			break
		end

		parent = parent.Parent
	end
end

function Dependencies:watch(object, subtree)
	local existing = self.entries[object]
	if
		existing
		and existing.watched
		and existing.watchedParent == object.Parent
		and (not subtree or existing.tree)
	then
		return existing
	end

	local entry = self:one(object)
	if not entry then
		return
	end

	self:ancestors(object)
	entry.watched = true
	entry.watchedParent = object.Parent
	if subtree and not entry.tree then
		entry.tree = true
		for child in entry.children do
			self:watch(child, true)
		end
	end

	if object:IsA("ParticleEmitter") and object.Parent then
		local parent = object.Parent
		if parent:IsA("Attachment") then
			self:watch(parent, true)
		end
	end

	return entry
end

function Dependencies:boundsBefore(object, key)
	if
		self.modelEntries == 0
		or not boundsProperties[key]
		or key ~= "Parent" and not object:IsA("BasePart")
	then
		return
	end

	local parent = object.Parent
	local prior = key == "Parent" and {} or nil
	while parent and parent ~= game do
		local entry = self.entries[parent]
		if entry and parent:IsA("Model") and (entry.full or entry.inputKeys.WorldPivot) then
			self:check(entry, "WorldPivot")
			if prior then
				table.insert(prior, parent)
			end
		end

		parent = parent.Parent
	end

	if prior then
		self.spatialParents[object] = prior
	end
end

function Dependencies:boundsAfter(object, key)
	if
		self.modelEntries == 0
		or not boundsProperties[key]
		or key ~= "Parent" and not object:IsA("BasePart")
	then
		return
	end

	local prior = self.spatialParents[object]
	if prior then
		self.spatialParents[object] = nil
		for _, model in prior do
			self:after(model, "WorldPivot")
		end
	end

	local parent = object.Parent
	while parent and parent ~= game do
		local entry = self.entries[parent]
		if entry and parent:IsA("Model") and (entry.full or entry.inputKeys.WorldPivot) then
			self:after(parent, "WorldPivot")
		end

		parent = parent.Parent
	end
end

function Dependencies:before(object, key, kind)
	if not kind then
		self:boundsBefore(object, key)
	end

	if self:ignore(object) then
		return
	end

	if kind == "Tag" then
		self:tagInput(object, key, true)
	elseif not kind and key == "Parent" then
		self:tagTree(object, true)
		self:pivotTree(object, true)
	end

	local entry = self.entries[object]
	if not entry or not entry.full then
		entry = self:watch(object) or entry
	end

	if not entry or self:ignore(object) then
		return
	end

	if not entry.full then
		if kind == "Attribute" then
			entry.attributeKeys[key] = true
			self:listenAttributes(entry)
		elseif not kind then
			for _, field in self:group(object, key) do
				entry.inputKeys[field] = true
			end
		end
	end

	self:check(entry, key, kind)
	local group = kind or "Property"
	entry.written[group] = entry.written[group] or {}
	entry.written[group][key] = true
end

function Dependencies:after(object, key, kind)
	if self.closed then
		return
	end

	if not kind then
		self:boundsAfter(object, key)
	end

	if kind == "Tag" then
		self:tagInput(object, key, false)
	elseif not kind and key == "Parent" then
		self:tagTree(object, false)
		self:pivotTree(object, false)
	end

	local entry = self.entries[object]
	if not entry or self.closed then
		return
	end

	local values = kind == "Attribute" and entry.attributes
		or kind == "Tag" and entry.tags
		or kind == "Scale" and entry.scales
		or entry.values
	local oldParent = not kind and key == "Parent" and values.Parent
	for _, field in kind and (single[key] or { key }) or self:group(object, key) do
		local ok, value = pcall(get, object, field, kind)
		if ok then
			values[field] = value == nil and self.NIL or value
		end
	end

	if oldParent then
		if self.entries[oldParent] then
			self.entries[oldParent].children[object] = nil
		end

		if self.entries[object.Parent] then
			self.entries[object.Parent].children[object] = true
		end

		entry.rig = self:inRig(object)
		self:ancestors(object)
	end
end

function Dependencies:treeKeys(object, mode, method, watched)
	local list = watched or object:GetDescendants()
	if not watched then
		table.insert(list, object)
	end

	for _, child in list do
		if self:ignore(child) then
			continue
		end

		local function apply(key)
			method(self, child, key)
			if method == self.before and (mode == "scale" or child:IsA("Model")) then
				self.clock:remember(child, key)
			end
		end

		if child:IsA("BasePart") then
			apply("CFrame")
			if mode == "scale" then
				apply("Size")
			end
		elseif child:IsA("Model") then
			if mode == "scale" then
				method(self, child, "Scale", "Scale")
				if method == self.before and self.clock.scales[child] == nil then
					self.clock.scales[child] = child:GetScale()
					self.clock.cleanup:remember(child, "Scale", self.clock.scales[child], "Scale")
				end
			end

			apply("WorldPivot")
		elseif mode == "scale" then
			if child:IsA("Attachment") then
				apply("CFrame")
			elseif child:IsA("DataModelMesh") then
				apply("Scale")
				apply("Offset")
			elseif child:IsA("JointInstance") then
				apply("C0")
				apply("C1")
			else
				for _, key in scaledProperties[child.ClassName] or {} do
					apply(key)
				end
			end
		end
	end
end

function Dependencies:beforeTree(object, mode)
	if self:ignore(object) then
		return
	end

	self:treeKeys(object, mode, self.before)
end

function Dependencies:afterTree(object, mode)
	if self:ignore(object) then
		return
	end

	self:treeKeys(object, mode, self.after)
end

function Dependencies:poll()
	if self.closed then
		return
	end

	self.polls += 1
	for _, entry in self.entries do
		for kind, keys in entry.written do
			for key in keys do
				self:check(entry, key, kind ~= "Property" and kind or nil)
			end
		end
	end

	self:pollPending()
end

function Dependencies:disconnect()
	if self.closed then
		return
	end

	self.closed = true
	active[self] = nil
	for _, connection in self.connections do
		connection:Disconnect()
	end

	table.clear(self.connections)
	table.clear(self.pendingNil)
	table.clear(self.pendingOrder)
	table.clear(self.tagQueries)
	table.clear(self.tagReads)
	table.clear(self.spatialParents)
end

return Dependencies
