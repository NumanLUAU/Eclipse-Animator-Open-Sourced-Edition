--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Properties = require("Properties")
local CameraRig = require("CameraRig")
local HttpService = game:GetService("HttpService")
local Storage = {}
local NAME = "EclipseTrackOrganization"
local ID = "EclipseTrackId"

local function finite(value, fallback)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge and value
		or fallback
end

const SAVE_ROOTS = { "EclipseAnimator_Saves", "EclipseAnimator_Backups" }
local liveCache

local function migrateIdentity(object, old, new)
	object:SetAttribute(ID, new)
	const saves = object:FindFirstChild("AnimSaves")
	for _, sequence in saves and saves:GetChildren() or {} do
		if sequence:IsA("KeyframeSequence") and sequence:GetAttribute("EclipseAuthoredRigId") == old then
			sequence:SetAttribute("EclipseAuthoredRigId", new)
		end
	end

	const Root = require("root")
	for _, name in SAVE_ROOTS do
		const folder = Root.get(name, false)
		for _, value in folder and folder:GetDescendants() or {} do
			if value:IsA("ObjectValue") and value.Value == object and value.Parent then
				for _, attribute in { value.Name .. "Id", value.Name .. "ObjectId" } do
					if value.Parent:GetAttribute(attribute) == old then
						value.Parent:SetAttribute(attribute, new)
					end
				end
			end
		end
	end

	const bakes = Root.get("EclipseCameraBakes", false)
	for _, folder in bakes and bakes:GetChildren() or {} do
		const link = folder:FindFirstChild("Camera")
		if link and link:IsA("ObjectValue") and link.Value == object and folder:GetAttribute(ID) == old then
			folder:SetAttribute(ID, new)
		end
	end

	const exports = Root.get("EclipseCameraExports", false)
	for _, target in exports and exports:GetChildren() or {} do
		const link = target:FindFirstChild("EclipseCameraSource")
		if
			link
			and link:IsA("ObjectValue")
			and link.Value == object
			and target:GetAttribute("EclipseCameraExportOwner") == old
		then
			target:SetAttribute("EclipseCameraExportOwner", new)
		end
	end

	liveCache = nil
end

local function identity(object, used, migrate)
	local id = object:GetAttribute(ID)
	if typeof(id) ~= "string" or id == "" then
		id = HttpService:GenerateGUID(false)
		object:SetAttribute(ID, id)
	elseif used and used[id] and used[id] ~= object then
		const fresh = HttpService:GenerateGUID(false)
		if migrate then
			migrateIdentity(object, id, fresh)
		else
			object:SetAttribute(ID, fresh)
		end

		id = fresh
	end

	if used then
		used[id] = object
	end

	return id
end

local function liveIndex()
	if liveCache and os.clock() - liveCache.time < 0.5 then
		return liveCache.ids
	end

	const ids = {}
	const Root = require("root")
	const Preview = require("rig")
	const step = require("State").ProjectWorkStep
	for _, scope in { workspace, Root.get("EclipseCameras", false), Root.get("EclipseEffectStorage", false) } do
		for index, candidate in scope and scope:GetDescendants() or {} do
			if step and index % 4096 == 0 then
				step()
			end

			const id = candidate:GetAttribute(ID)
			if typeof(id) == "string" and id ~= "" and Preview.original(candidate) == candidate then
				const list = ids[id]
				if list then
					table.insert(list, candidate)
				else
					ids[id] = { candidate }
				end
			end
		end
	end

	liveCache = { time = os.clock(), ids = ids }
	return ids
end

local function linkedRigs()
	const linked = {}
	const folder = require("root").get(SAVE_ROOTS[1], false)
	for _, value in folder and folder:GetDescendants() or {} do
		if value.Name == "Rig" and value:IsA("ObjectValue") and value.Value then
			linked[value.Value] = true
		end
	end

	return linked
end

function Storage.claimIdentity(object)
	object = require("rig").original(object)
	if typeof(object) ~= "Instance" or not object:IsDescendantOf(game) then
		return nil
	end

	const id = object:GetAttribute(ID)
	if typeof(id) ~= "string" or id == "" then
		return identity(object)
	end

	const holders = {}
	for _, candidate in liveIndex()[id] or {} do
		if candidate ~= object and candidate:GetAttribute(ID) == id and candidate:IsDescendantOf(game) then
			table.insert(holders, candidate)
		end
	end

	if #holders == 0 then
		return id
	end

	if linkedRigs()[object] then
		return id
	end

	migrateIdentity(object, id, HttpService:GenerateGUID(false))
	warn(
		"[Eclipse] "
			.. object:GetFullName()
			.. " shared its identity with "
			.. holders[1]:GetFullName()
			.. ", so saved animations could be matched to the wrong copy. It now has its own identity; the other rig is unchanged. Animations copied inside its AnimSaves stay there unchanged."
	)
	require("Notification").show(
		"DUPLICATED RIG SEPARATED",
		object.Name
			.. " shared its identity with a copy. It now has its own, so animations can't be mixed up between them. Details are in Output."
	)
	return object:GetAttribute(ID)
end

local function reference(parent, name, value)
	local result = Instance.new("ObjectValue")
	result.Name, result.Value, result.Parent = name, require("rig").original(value), parent
end

local function referenced(entry, name)
	local value = entry:FindFirstChild(name)
	return value and value:IsA("ObjectValue") and value.Value or nil
end

local function traversable(object)
	return not object:IsA("ValueBase")
		and not object:IsA("KeyframeSequence")
		and object.Name ~= "AnimSaves"
		and object.Name ~= NAME
		and object:GetAttribute("EclipseSave") ~= true
end

local function childSegments(parent)
	local result, counts = {}, {}
	for _, child in parent:GetChildren() do
		local nameClass = child.ClassName .. "\0" .. child.Name
		counts[nameClass] = (counts[nameClass] or 0) + 1
		table.insert(
			result,
			{ child, { name = child.Name, class = child.ClassName, index = counts[nameClass] } }
		)
	end

	return result
end

local function appended(path, segment)
	local result = table.clone(path)
	table.insert(result, segment)
	return result
end

local function buildBindingIndex(rig)
	local index = { members = {}, ids = {}, paths = {} }
	local step = require("State").ProjectWorkStep
	local links = {}

	local function visit(object, path)
		if index.members[object] then
			return
		end

		if step then
			step()
		end

		index.members[object], index.paths[object] = true, path
		local id = object:GetAttribute(ID)
		if typeof(id) == "string" and id ~= "" then
			index.ids[id] = index.ids[id] == nil and object or false
		end

		if object:IsA("Motor6D") and object.Part1 then
			table.insert(links, { object.Part1, appended(path, { link = "Part1" }) })
		end

		for _, info in
			object == rig and Properties.propertyOnly(rig) and {} or childSegments(object)
		do
			if traversable(info[1]) then
				visit(info[1], appended(path, info[2]))
			end
		end
	end

	visit(rig, {})
	Properties.list(rig)
	local properties = Properties.folder(rig, false)
	if properties then
		visit(properties, { { link = "Properties" } })
	end

	local cursor = 1
	while cursor <= #links do
		local link = links[cursor]
		visit(link[1], link[2])
		cursor += 1
	end

	return index
end

local function follow(root, encoded)
	if typeof(encoded) ~= "string" then
		return nil
	end

	local ok, path = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or typeof(path) ~= "table" then
		return nil
	end

	local current = root
	for _, segment in ipairs(path) do
		if typeof(segment) ~= "table" then
			return nil
		end

		if segment.link == "Properties" then
			current = Properties.folder(current, true)
		elseif segment.link == "Part1" then
			if not current:IsA("Motor6D") or not current.Part1 then
				return nil
			end

			current = current.Part1
		else
			local found, ordinal = nil, 0
			for _, child in current:GetChildren() do
				if child.Name == segment.name and child.ClassName == segment.class then
					ordinal += 1
					if ordinal == segment.index then
						found = child
						break
					end
				end
			end

			if not found and segment.name == "Properties" and segment.class == "Folder" then
				found = Properties.folder(current, false)
			end

			if not found and segment.class == "Bone" then
				found = require("R6Controls").findNamed(current, segment.name, segment.index)
			end

			if not found then
				return nil
			end

			current = found
		end
	end

	return current
end

local function pathFrom(root, object)
	local path = {}
	while object and object ~= root do
		local parent = object.Parent
		if not parent then
			return nil
		end

		for _, info in childSegments(parent) do
			if info[1] == object then
				table.insert(path, 1, info[2])
				break
			end
		end

		object = parent
	end

	return object == root and path or nil
end

function Storage.bindingPath(rig, object, cache)
	local state = require("State")
	local rigs = state.getAllRigs and state.getAllRigs() or {}
	local ancestor = object
	while ancestor do
		if table.find(rigs, ancestor) then
			if ancestor ~= rig then
				return nil
			end

			break
		end

		ancestor = ancestor.Parent
	end

	if cache and not cache.index then
		cache.index = buildBindingIndex(rig)
	end

	local index = cache and cache.index or buildBindingIndex(rig)
	return index.paths[object]
end

function Storage.writeRig(entry, rig, order)
	rig = require("rig").original(rig)
	CameraRig.write(entry, rig)
	reference(entry, "Rig", rig)
	entry:SetAttribute("RigId", identity(rig))
	entry:SetAttribute("RigName", rig.Name)
	entry:SetAttribute("RigClass", rig.ClassName)
	entry:SetAttribute("Order", order)
	local path = pathFrom(workspace, rig)
	if path then
		entry:SetAttribute("RigPath", HttpService:JSONEncode(path))
	end

	local gamePath = pathFrom(game, rig)
	if gamePath then
		entry:SetAttribute("RigGamePath", HttpService:JSONEncode(gamePath))
	end
end

function Storage.resolveRigs(folder, scope)
	scope = scope or workspace
	local entries = folder:GetChildren()
	table.sort(entries, function(a, b)
		local first, second =
			finite(a:GetAttribute("Order"), math.huge), finite(b:GetAttribute("Order"), math.huge)
		if first ~= second then
			return first < second
		end

		return a.Name < b.Name
	end)
	local models

	local function candidates()
		if models then
			return models
		end

		models = {}

		local function visit(object)
			if object:IsA("Model") or object:IsA("BasePart") or #Properties.catalog(object) > 0 then
				table.insert(models, object)
			end

			for _, child in object:GetChildren() do
				if traversable(child) then
					visit(child)
				end
			end
		end

		visit(scope)
		return models
	end

	local known
	local function savedElsewhere(id)
		if not known then
			known = {}
			const saves = require("root").get(SAVE_ROOTS[1], false)
			for _, save in saves and saves:GetChildren() or {} do
				const rigs = save:FindFirstChild("Rigs")
				for _, other in rigs and rigs:GetChildren() or {} do
					const value = other:GetAttribute("RigId")
					if typeof(value) == "string" then
						known[value] = true
					end
				end
			end

			for _, other in folder:GetChildren() do
				const value = other:GetAttribute("RigId")
				if typeof(value) == "string" then
					known[value] = true
				end
			end
		end

		return known[id] == true
	end

	local results, used = {}, {}
	for _, entry in entries do
		local rig = referenced(entry, "Rig")
		local camera = entry:GetAttribute("EclipseCamera") == true
		local savedId = entry:GetAttribute("RigId")

		local function matchingCamera(candidate)
			return not camera
				or CameraRig.isRig(candidate)
					and (not savedId or candidate:GetAttribute(ID) == savedId)
		end

		if rig and camera and not CameraRig.isRig(rig) then
			rig = nil
		end

		if (not rig or not rig.Parent) and scope == workspace then
			local found = follow(game, entry:GetAttribute("RigGamePath"))
			if
				found
				and found.ClassName == entry:GetAttribute("RigClass")
				and matchingCamera(found)
				and (not savedId or found:GetAttribute(ID) == savedId)
			then
				rig = found
			end
		end

		if not rig or not rig.Parent then
			rig = nil
			local id, name =
				entry:GetAttribute("RigId"), entry:GetAttribute("RigName") or entry.Name
			local class = entry:GetAttribute("RigClass")
			local byId, byName = {}, {}
			for _, candidate in candidates() do
				if not matchingCamera(candidate) then
					continue
				end

				if id and candidate:GetAttribute(ID) == id then
					table.insert(byId, candidate)
				end

				if candidate.Name == name and (not class or candidate.ClassName == class) then
					table.insert(byName, candidate)
				end
			end

			local function unclaimed(candidate)
				const current = candidate:GetAttribute(ID)
				return not id
					or typeof(current) ~= "string"
					or current == ""
					or current == id
					or not savedElsewhere(current)
			end

			if #byId == 1 then
				rig = byId[1]
			else
				local atPath = follow(scope, entry:GetAttribute("RigPath"))
				if atPath and table.find(#byId > 0 and byId or byName, atPath) and unclaimed(atPath) then
					rig = atPath
				elseif #byId == 0 and #byName == 1 and unclaimed(byName[1]) then
					rig = byName[1]
				end
			end
		end

		if not rig then
			rig = CameraRig.restore(entry, scope)
		end

		if rig and used[rig] then
			rig = nil
		end

		if rig then
			used[rig] = true
			if CameraRig.isRig(rig) and entry:GetAttribute("EclipseCamera") == true then
				rig:SetAttribute(
					"EclipseOrthographic",
					entry:GetAttribute("CameraOrthographic") == true
				)
				local project = folder.Parent
				CameraRig.organize(
					rig,
					project and project:GetAttribute("EclipseSave") and project.Name or nil,
					scope
				)
			end
		end

		table.insert(results, { entry = entry, rig = rig })
	end

	return results
end

local function findRig(object, natural, rigs, indexes)
	local entry = natural[object]
	if entry and entry.rig and table.find(rigs, entry.rig) then
		return entry.rig
	end

	for _, rig in rigs do
		if indexes[rig].members[object] then
			return rig
		end
	end

	return nil
end

local function writeReference(entry, name, key, context)
	if typeof(key) == "Instance" and key:GetAttribute("EclipseNavigationOrigin") == true then
		entry:SetAttribute(name .. "Kind", "Origin")
		return
	end

	if key == nil or key == false then
		entry:SetAttribute(name .. "Kind", "Root")
		return
	end

	if typeof(key) == "string" then
		entry:SetAttribute(name .. "Kind", "Folder")
		entry:SetAttribute(name .. "Id", key)
		return
	end

	local rig = findRig(key, context.natural, context.rigs, context.indexes)
	if not rig then
		entry:SetAttribute(name .. "Kind", "Root")
		return
	end

	entry:SetAttribute(name .. "Kind", "Instance")
	reference(entry, name, key)
	reference(entry, name .. "Rig", rig)
	entry:SetAttribute(name .. "ObjectId", identity(key, context.used))
	entry:SetAttribute(name .. "RigId", identity(rig, context.used))
	entry:SetAttribute(name .. "RigName", rig.Name)
	local path = context.indexes[rig].paths[key]
	if path then
		entry:SetAttribute(name .. "Path", HttpService:JSONEncode(path))
	end
end

function Storage.write(container, snapshot, natural, rigs, singleRig)
	rigs = rigs or {}
	local context = { natural = natural, rigs = rigs, indexes = {}, used = {} }
	for _, rig in rigs do
		identity(rig, context.used, true)
	end

	for key in natural do
		if table.find(rigs, natural[key].rig) then
			identity(key, context.used)
		end
	end

	for _, rig in rigs do
		context.indexes[rig] = buildBindingIndex(rig)
	end

	local root = Instance.new("Folder")
	root.Name = NAME
	root:SetAttribute("Version", 2)
	root:SetAttribute("NextNumber", snapshot.nextNumber)
	if singleRig then
		root:SetAttribute("SingleRigId", identity(singleRig, context.used))
	end

	local ok, message = xpcall(function()
		for id, folder in snapshot.folders do
			local entry = Instance.new("Folder")
			entry.Name = id
			entry:SetAttribute("Kind", "Folder")
			entry:SetAttribute("Title", folder.name)
			entry:SetAttribute("Enabled", folder.enabled ~= false)
			local placement = snapshot.placements[id] or {}
			entry:SetAttribute("Order", finite(placement.order, 2147483647))
			writeReference(entry, "Parent", placement.parent, context)
			entry.Parent = root
		end

		local armatureIndex = 0
		for arm, initialized in snapshot.collectionArmatures or {} do
			if
				initialized
				and typeof(arm) == "Instance"
				and arm.Parent
				and arm:GetAttribute("EclipseArmature")
				and findRig(arm, natural, rigs, context.indexes)
			then
				armatureIndex += 1
				local entry = Instance.new("Folder")
				entry.Name = "ArmatureCollections" .. armatureIndex
				entry:SetAttribute("Kind", "ArmatureCollections")
				entry:SetAttribute("ArmatureKey", arm:GetAttribute("EclipseArmatureKey"))
				writeReference(entry, "Target", arm, context)
				entry.Parent = root
			end
		end

		for id, collection in snapshot.collections or {} do
			local entry = Instance.new("Folder")
			entry.Name = id
			entry:SetAttribute("Kind", "BoneCollection")
			entry:SetAttribute("Title", collection.name)
			entry:SetAttribute("Visible", collection.visible ~= false)
			local count = 0
			for part in collection.members do
				if
					typeof(part) == "Instance"
					and part.Parent
					and findRig(part, natural, rigs, context.indexes)
				then
					count += 1
					local member = Instance.new("Folder")
					member.Name = "Member" .. count
					writeReference(member, "Target", part, context)
					member.Parent = entry
				end
			end

			if not singleRig or count > 0 or not next(collection.members) then
				entry.Parent = root
			else
				entry:Destroy()
			end
		end

		local keys = {}
		for key in snapshot.placements do
			if typeof(key) == "Instance" then
				keys[key] = true
			end
		end

		for key in snapshot.enabled do
			if typeof(key) == "Instance" then
				keys[key] = true
			end
		end

		for key in snapshot.removed or {} do
			if typeof(key) == "Instance" then
				keys[key] = true
			end
		end

		for _, field in { "hiddenBones", "partWidgets" } do
			for key in snapshot[field] or {} do
				keys[key] = true
			end
		end

		local index = 0
		for key in keys do
			if
				not key:GetAttribute("EclipseNavigationOrigin")
				and not findRig(key, natural, rigs, context.indexes)
			then
				continue
			end

			index += 1
			local entry = Instance.new("Folder")
			entry.Name = "Item" .. index
			entry:SetAttribute("Kind", "Item")
			for _, field in { "hiddenBones", "partWidgets" } do
				if snapshot[field] and snapshot[field][key] then
					entry:SetAttribute(field, true)
				end
			end

			entry:SetAttribute("Removed", snapshot.removed and snapshot.removed[key] or nil)
			writeReference(entry, "Target", key, context)
			local placement = snapshot.placements[key]
			if placement then
				entry:SetAttribute("Placed", true)
				entry:SetAttribute("Order", finite(placement.order, 2147483647))
				writeReference(entry, "Parent", placement.parent, context)
			end

			if snapshot.enabled[key] ~= nil then
				entry:SetAttribute("Enabled", snapshot.enabled[key])
			end

			entry.Parent = root
		end
	end, debug.traceback)
	if not ok then
		root:Destroy()
		error(message)
	end

	local previous = container:FindFirstChild(NAME)
	root.Parent = container
	if previous then
		previous:Destroy()
	end

	return root
end

local function readReference(entry, name, context)
	local kind = entry:GetAttribute(name .. "Kind")
	if kind == "Origin" then
		return require("Origin").ensure()
	end

	if kind == "Root" then
		return false
	end

	if kind == "Folder" then
		return entry:GetAttribute(name .. "Id")
	end

	if kind ~= "Instance" then
		return nil
	end

	local object = referenced(entry, name)
	if object and object.Parent then
		for _, rig in context.rigs do
			if context.indexes[rig].members[object] then
				return object
			end
		end
	end

	local rig = referenced(entry, name .. "Rig")
	if not table.find(context.rigs, rig) then
		rig = nil
		local id = entry:GetAttribute(name .. "RigId")
		if id and id == context.singleId and #context.rigs == 1 then
			rig = context.rigs[1]
		else
			local exact, named = {}, {}
			for _, candidate in context.rigs do
				if id and candidate:GetAttribute(ID) == id then
					table.insert(exact, candidate)
				end

				if candidate.Name == entry:GetAttribute(name .. "RigName") then
					table.insert(named, candidate)
				end
			end

			if #exact == 1 then
				rig = exact[1]
			elseif #exact == 0 and #named == 1 then
				rig = named[1]
			end
		end
	end

	if not rig then
		return nil
	end

	local id = entry:GetAttribute(name .. "ObjectId")
	local exact = id and context.indexes[rig].ids[id]
	if exact then
		return exact
	end

	local found = follow(rig, entry:GetAttribute(name .. "Path"))
	if not found or not context.indexes[rig].members[found] then
		return nil
	end

	local currentId = found:GetAttribute(ID)
	local sourceRigId = entry:GetAttribute(name .. "RigId")
	local retargeted = context.singleId ~= nil
		or sourceRigId ~= nil and rig:GetAttribute(ID) ~= sourceRigId
	if id and currentId and currentId ~= id and not retargeted and not Properties.owner(found) then
		return nil
	end

	return found
end

function Storage.read(container, rigs)
	local root = container and container:FindFirstChild(NAME)
	if not root or not root:IsA("Folder") then
		return nil
	end

	local version = root:GetAttribute("Version")
	if version ~= 1 and version ~= 2 then
		return nil
	end

	rigs = rigs or {}
	local context = { rigs = rigs, indexes = {}, singleId = root:GetAttribute("SingleRigId") }
	for _, rig in rigs do
		context.indexes[rig] = buildBindingIndex(rig)
	end

	local snapshot = {
		folders = {},
		placements = {},
		enabled = {},
		removed = {},
		collections = {},
		collectionArmatures = {},
		hiddenBones = {},
		partWidgets = {},
		nextNumber = 1,
	}
	snapshot.nextNumber = math.max(1, math.floor(finite(root:GetAttribute("NextNumber"), 1)))
	local entries = root:GetChildren()
	for _, entry in entries do
		if entry:IsA("Folder") and entry:GetAttribute("Kind") == "ArmatureCollections" then
			local arm = readReference(entry, "Target", context)
			local key = entry:GetAttribute("ArmatureKey")
			if
				typeof(arm) == "Instance"
				and arm:GetAttribute("EclipseArmature")
				and (key == nil or key == arm:GetAttribute("EclipseArmatureKey"))
			then
				snapshot.collectionArmatures[arm] = true
			end
		end
	end

	for _, entry in entries do
		if
			entry:IsA("Folder")
			and entry:GetAttribute("Kind") == "BoneCollection"
			and type(entry:GetAttribute("Title")) == "string"
		then
			local collection = {
				id = entry.Name,
				name = entry:GetAttribute("Title"),
				visible = entry:GetAttribute("Visible") ~= false,
				members = {},
			}
			for _, member in entry:GetChildren() do
				local part = readReference(member, "Target", context)
				if typeof(part) == "Instance" and (part:IsA("BasePart") or part:IsA("Bone")) then
					collection.members[part] = true
				end
			end

			snapshot.collections[entry.Name] = collection
		end
	end

	for _, entry in entries do
		if entry:IsA("Folder") and entry:GetAttribute("Kind") == "Folder" then
			local name = entry:GetAttribute("Title")
			if typeof(name) == "string" and name ~= "" and not snapshot.folders[entry.Name] then
				snapshot.folders[entry.Name] = {
					id = entry.Name,
					name = name,
					enabled = entry:GetAttribute("Enabled") ~= false,
				}
			end
		end
	end

	for _, entry in entries do
		if not entry:IsA("Folder") then
			continue
		end

		local key = entry:GetAttribute("Kind") == "Folder" and entry.Name
			or readReference(entry, "Target", context)
		if not key or typeof(key) == "string" and not snapshot.folders[key] then
			continue
		end

		if entry:GetAttribute("Kind") == "Folder" or entry:GetAttribute("Placed") then
			local parent = readReference(entry, "Parent", context)
			if typeof(parent) == "string" and not snapshot.folders[parent] then
				parent = false
			end

			snapshot.placements[key] = {
				parent = parent or false,
				order = finite(entry:GetAttribute("Order"), 2147483647),
			}
		end

		if typeof(key) == "Instance" and entry:GetAttribute("Removed") == true then
			snapshot.removed[key] = true
		end

		if typeof(key) == "Instance" then
			for _, field in { "hiddenBones", "partWidgets" } do
				if entry:GetAttribute(field) == true then
					snapshot[field][key] = true
				end
			end
		end

		if typeof(key) == "Instance" and typeof(entry:GetAttribute("Enabled")) == "boolean" then
			snapshot.enabled[key] = entry:GetAttribute("Enabled")
		end
	end

	for key, placement in snapshot.placements do
		local parent, seen = placement.parent, { [key] = true }
		while parent and snapshot.placements[parent] do
			if seen[parent] then
				placement.parent = false
				break
			end

			seen[parent] = true
			parent = snapshot.placements[parent].parent
		end
	end

	return snapshot
end

return Storage
