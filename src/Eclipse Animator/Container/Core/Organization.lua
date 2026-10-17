--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local HttpService = game:GetService("HttpService")
local History = require("History")
local Storage = require("TrackOrganizationStorage")
local Organization = {}

local folders, placements, ownEnabled, natural = {}, {}, {}, {}
local removed = {}
local collections, boneVisibility = {}, {}
local hiddenBones, partWidgets = {}, {}
local collectionRevision = 0
local importedArmatures = setmetatable({}, { __mode = "k" })
local armatureCollections = setmetatable({}, { __mode = "k" })
local armatureVisibility = setmetatable({}, { __mode = "k" })

local function copyCollections(source)
	local result = {}
	for id, value in source or {} do
		result[id] = {
			id = id,
			name = value.name,
			visible = value.visible ~= false,
			members = table.clone(value.members or {}),
		}
	end

	return result
end

local nextNumber = 1
local generation = 0
local listeners = {}
local normalizeCycles
local Camera = require("CameraRig")

local function isShake(key)
	return typeof(key) == "Instance"
		and key:GetAttribute("EclipseEffectObject") == 1
		and key:GetAttribute("EffectKind") == "Camera Shake"
end

local enabledCache = {}

local function copyMap(source)
	local result = {}
	for key, value in source do
		result[key] = typeof(value) == "table" and table.clone(value) or value
	end

	return result
end

local function notify(reason)
	collectionRevision += 1
	table.clear(boneVisibility)
	if Organization.cameraFor then
		for key in natural do
			if isShake(key) then
				local camera = Organization.cameraFor(key)
				if camera then
					key:SetAttribute("EffectCameraId", camera:GetAttribute("EclipseTrackId"))
				end
			end
		end
	end

	table.clear(enabledCache)
	for callback in table.clone(listeners) do
		if not listeners[callback] then
			continue
		end

		local ok, message = pcall(callback, reason)
		if not ok then
			warn("Eclipse track organization: " .. tostring(message))
		end
	end
end

function Organization.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

function Organization.snapshot()
	return {
		folders = copyMap(folders),
		placements = copyMap(placements),
		collections = copyCollections(collections),
		collectionArmatures = table.clone(importedArmatures),
		hiddenBones = table.clone(hiddenBones),
		partWidgets = table.clone(partWidgets),
		enabled = table.clone(ownEnabled),
		removed = table.clone(removed),
		nextNumber = nextNumber,
	}
end

function Organization.restore(snapshot, reason)
	collections = copyCollections(snapshot.collections)

	importedArmatures = setmetatable({}, { __mode = "k" })
	for arm, initialized in snapshot.collectionArmatures or {} do
		if initialized and typeof(arm) == "Instance" and arm:GetAttribute("EclipseArmature") then
			importedArmatures[arm] = true
		end
	end

	for _, collection in collections do
		for part in collection.members do
			local arm = typeof(part) == "Instance" and part.Parent
			if arm and arm:GetAttribute("EclipseArmature") then
				importedArmatures[arm] = true
			end
		end
	end

	hiddenBones = table.clone(snapshot.hiddenBones or {})
	partWidgets = table.clone(snapshot.partWidgets or {})
	folders = copyMap(snapshot.folders or {})
	for _, folder in folders do
		table.freeze(folder)
	end

	placements = copyMap(snapshot.placements or {})
	ownEnabled = table.clone(snapshot.enabled or {})
	removed = table.clone(snapshot.removed or {})
	nextNumber = math.max(1, math.floor(snapshot.nextNumber or 1))
	if normalizeCycles then
		normalizeCycles()
	end

	notify(reason or "change")
end

local function commit(before, description, reason)
	local after = Organization.snapshot()
	local epoch = generation
	History.record(function()
		if generation == epoch then
			Organization.restore(before, reason == "enabled" and "enabled" or "undo")
		end
	end, function()
		if generation == epoch then
			Organization.restore(after, reason == "enabled" and "enabled" or "redo")
		end
	end, description)
	notify(reason or "change")
end

local function importCollections(arm)
	if not arm or not arm:GetAttribute("EclipseArmature") or importedArmatures[arm] then
		return
	end

	local definitions = armatureCollections[arm]
	if not definitions then
		return
	end

	importedArmatures[arm] = true
	local anchors = {}
	for _, part in arm:GetChildren() do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("EclipseArmatureBoneId")
			if id then
				anchors[id] = part
			end
		end
	end

	for _, value in definitions do
		if type(value.name) == "string" and type(value.members) == "table" then
			local id = "bones_" .. HttpService:GenerateGUID(false)
			local members = {}
			for _, boneId in value.members do
				if anchors[boneId] then
					members[anchors[boneId]] = true
				end
			end

			collections[id] = {
				id = id,
				name = value.name,
				visible = value.visible ~= false,
				members = members,
			}
		end
	end

	collectionRevision += 1
	table.clear(boneVisibility)
	return true
end

function Organization.registerArmatureCollections(arm, data)
	if armatureCollections[arm] then
		return
	end

	local definitions, byArmature, visibility = {}, {}, {}
	for _, source in data.armatures or {} do
		if type(source.bone_collections) == "table" then
			local lookup = {}
			byArmature[source.name] = lookup
			for _, value in source.bone_collections do
				if
					type(value.name) == "string"
					and type(value.id) == "string"
					and not lookup[value.id]
				then
					local collection =
						{ name = value.name, visible = value.visible ~= false, members = {} }
					lookup[value.id] = collection
					table.insert(definitions, collection)
				end
			end
		end
	end

	for _, bone in data.bones or {} do
		local lookup = byArmature[bone.armature]
		local assigned, visible = false, false
		if lookup then
			for _, id in bone.collections or {} do
				local collection = lookup[id]
				if collection then
					table.insert(collection.members, bone.id)
					assigned = true
					visible = visible or collection.visible
				end
			end
		end

		visibility[bone.id] = not assigned or visible
	end

	if next(byArmature) then
		armatureCollections[arm] = definitions
		armatureVisibility[arm] = visibility
	end
end

local function rigArmatures(rigs, callback)
	local changed = false
	for _, rig in rigs or {} do
		if typeof(rig) == "Instance" then
			if rig:GetAttribute("EclipseArmature") then
				changed = callback(rig) or changed
			end

			for _, child in rig:GetChildren() do
				if child:GetAttribute("EclipseArmature") then
					changed = callback(child) or changed
				end
			end
		end
	end

	return changed
end

function Organization.reset()
	generation += 1
	natural = {}
	importedArmatures = setmetatable({}, { __mode = "k" })
	Organization.restore({ nextNumber = 1 }, "reset")
end

function Organization.sync(entries)
	local updated = {}
	for index, entry in ipairs(entries) do
		if typeof(entry.key) == "Instance" then
			updated[entry.key] = {
				parent = entry.parent,
				order = entry.order or index,
				rig = entry.rig,
				hidden = entry.hidden == true,
				dynamic = entry.dynamic,
			}
			if ownEnabled[entry.key] == nil then
				ownEnabled[entry.key] = entry.enabled ~= false
			end
		end
	end

	natural = updated
	local rigs = {}
	local seen = {}
	for _, entry in entries do
		if entry.rig and not seen[entry.rig] then
			seen[entry.rig] = true
			table.insert(rigs, entry.rig)
		end
	end

	local imported = rigArmatures(rigs, importCollections)

	local cameras = {}
	for key in natural do
		if Camera.isRig(key) then
			table.insert(cameras, key)
		end
	end

	for key in natural do
		if isShake(key) and not Organization.cameraFor(key) then
			local camera
			for _, candidate in cameras do
				if
					candidate:GetAttribute("EclipseTrackId")
					== key:GetAttribute("EffectCameraId")
				then
					camera = candidate
					break
				end
			end

			if not camera and #cameras == 1 then
				camera = cameras[1]
			end

			if camera then
				placements[key] = { parent = camera, order = math.huge }
				key:SetAttribute("EffectCameraId", camera:GetAttribute("EclipseTrackId"))
			end
		end
	end

	normalizeCycles()
	table.clear(enabledCache)
	if imported then
		notify("membership")
	end
end

function Organization.get(key)
	return folders[key]
end

function Organization.isFolder(key)
	return typeof(key) == "string" and folders[key] ~= nil
end

local function exists(key)
	return key == nil or folders[key] ~= nil or natural[key] ~= nil
end

function Organization.parent(key)
	local entry = natural[key]
	if entry and entry.dynamic then
		return entry.parent
	end

	local placement = placements[key]
	local parent = placement and placement.parent
	if parent == false then
		return nil
	end

	if not placement then
		parent = natural[key] and natural[key].parent
	end

	if parent ~= nil and not exists(parent) then
		return nil
	end

	return parent
end

normalizeCycles = function()
	local keys = {}
	for key in natural do
		keys[key] = true
	end

	for key in folders do
		keys[key] = true
	end

	for key in keys do
		local current, visited = key, {}
		while current and not visited[current] do
			visited[current] = true
			current = Organization.parent(current)
		end

		if current then
			local broken = current
			if not placements[broken] then
				for candidate in visited do
					if placements[candidate] then
						broken = candidate
						break
					end
				end
			end

			if natural[broken] then
				natural[broken].dynamic = nil
			end

			placements[broken] =
				{ parent = false, order = placements[broken] and placements[broken].order or 1 }
		end
	end
end

local function orderedChildren(result)
	local function order(key)
		return placements[key] and placements[key].order
			or natural[key] and natural[key].order
			or math.huge
	end

	table.sort(result, function(a, b)
		local first, second = order(a), order(b)
		if first ~= second then
			return first < second
		end

		local firstName = folders[a] and folders[a].name or a.Name
		local secondName = folders[b] and folders[b].name or b.Name
		if firstName ~= secondName then
			return firstName < secondName
		end

		return tostring(a) < tostring(b)
	end)
	return result
end

function Organization.children(parent)
	local result = {}
	for key, entry in natural do
		if not entry.hidden and not removed[key] and Organization.parent(key) == parent then
			table.insert(result, key)
		end
	end

	for key in folders do
		if Organization.parent(key) == parent then
			table.insert(result, key)
		end
	end

	return orderedChildren(result)
end

function Organization.childIndex()
	local result = {}

	local function add(key)
		local parent = Organization.parent(key) or false
		local list = result[parent]
		if not list then
			list = {}
			result[parent] = list
		end

		table.insert(list, key)
	end

	for key, entry in natural do
		if not entry.hidden and not removed[key] then
			add(key)
		end
	end

	for key in folders do
		add(key)
	end

	for _, list in result do
		orderedChildren(list)
	end

	return result
end

function Organization.getOwnEnabled(key, fallback)
	if ownEnabled[key] ~= nil then
		return ownEnabled[key]
	end

	return fallback ~= false
end

function Organization.isRemoved(key)
	return removed[key] == true
end

function Organization.isEnabled(key)
	if key == nil then
		return true
	end

	if enabledCache[key] ~= nil then
		return enabledCache[key]
	end

	local original = key
	if removed[key] or ownEnabled[key] == false then
		enabledCache[key] = false
		return false
	end

	local visited = {}
	while key ~= nil and not visited[key] do
		visited[key] = true
		if folders[key] and folders[key].enabled == false then
			enabledCache[original] = false
			return false
		end

		key = Organization.parent(key)
	end

	enabledCache[original] = true
	return true
end

local function placeList(parent, children)
	for index, key in ipairs(children) do
		placements[key] = { parent = parent or false, order = index }
	end
end

function Organization.create(parent)
	if not exists(parent) or natural[parent] and natural[parent].hidden then
		return nil
	end

	local before = Organization.snapshot()
	local used = {}
	for _, folder in folders do
		used[folder.name] = true
	end

	local name = "Folder " .. nextNumber
	while used[name] do
		nextNumber += 1
		name = "Folder " .. nextNumber
	end

	nextNumber += 1
	local id = "folder_" .. HttpService:GenerateGUID(false)
	local siblings = Organization.children(parent)
	folders[id] = table.freeze({ id = id, name = name, enabled = true })
	table.insert(siblings, id)
	placeList(parent, siblings)
	commit(before, "Create " .. name)
	return id
end

function Organization.rename(id, name)
	local folder = folders[id]
	if not folder or typeof(name) ~= "string" then
		return false
	end

	name = name:match("^%s*(.-)%s*$")
	if name == "" or name == folder.name then
		return false
	end

	local before = Organization.snapshot()
	folders[id] = table.freeze({ id = id, name = name, enabled = folder.enabled })
	commit(before, "Rename folder")
	return true
end

local function isAncestor(ancestor, key)
	local visited = {}
	while key ~= nil and not visited[key] do
		if key == ancestor then
			return true
		end

		visited[key] = true
		key = Organization.parent(key)
	end

	return false
end

function Organization.cameraFor(key, moving, destination)
	local visited = {}
	while key and not visited[key] do
		visited[key] = true
		if Camera.isRig(key) and natural[key] then
			return key
		end

		if moving and moving[key] then
			key = destination
		else
			key = Organization.parent(key)
		end
	end

	return nil
end

function Organization.cameraHasShake(camera)
	for key in natural do
		if isShake(key) and Organization.cameraFor(key) == camera then
			return true
		end
	end

	return false
end

function Organization.move(keys, parent, index)
	if not exists(parent) or natural[parent] and natural[parent].hidden then
		return false
	end

	local selected, ordered = {}, {}
	for _, key in ipairs(keys) do
		if
			key ~= nil
			and exists(key)
			and not selected[key]
			and not (natural[key] and natural[key].hidden)
		then
			selected[key] = true
			table.insert(ordered, key)
		end
	end

	local moved = {}
	for _, key in ipairs(ordered) do
		local carried = false
		for ancestor in selected do
			if ancestor ~= key and isAncestor(ancestor, key) then
				carried = true
				break
			end
		end

		if not carried then
			if isAncestor(key, parent) then
				return false
			end

			table.insert(moved, key)
		end
	end

	if #moved == 0 then
		return false
	end

	local movingSet = {}
	for _, key in moved do
		movingSet[key] = true
	end

	for key in natural do
		if isShake(key) then
			local carried = false
			local cursor = key
			local visited = {}
			while cursor and not visited[cursor] do
				visited[cursor] = true
				if movingSet[cursor] then
					carried = true
					break
				end

				cursor = Organization.parent(cursor)
			end

			if carried and not Organization.cameraFor(key, movingSet, parent) then
				require("Notification").show(
					"CAMERA SHAKE",
					"Camera shake needs to stay under a camera.",
					4
				)
				return false
			end
		end
	end

	local positions, visited, position = {}, {}, 0

	local function visit(ancestor)
		for _, key in Organization.children(ancestor) do
			if visited[key] then
				continue
			end

			visited[key] = true
			position += 1
			positions[key] = position
			visit(key)
		end
	end

	visit(nil)
	table.sort(moved, function(a, b)
		return (positions[a] or math.huge) < (positions[b] or math.huge)
	end)
	local before = Organization.snapshot()
	local moving = {}
	for _, key in moved do
		moving[key] = true
	end

	local target = {}
	for _, key in Organization.children(parent) do
		if not moving[key] then
			table.insert(target, key)
		end
	end

	index = math.clamp(math.floor(tonumber(index) or (#target + 1)), 1, #target + 1)
	for offset, key in ipairs(moved) do
		table.insert(target, index + offset - 1, key)
	end

	local original = Organization.children(parent)
	local same = #original == #target
	if same then
		for position, key in target do
			if original[position] ~= key then
				same = false
				break
			end
		end
	end

	if same then
		return false
	end

	placeList(parent, target)
	commit(before, "Move tracks")
	return true
end

function Organization.remove(id)
	local folder = folders[id]
	if not folder then
		return false
	end

	local before = Organization.snapshot()
	local parent = Organization.parent(id)
	local siblings = {}
	local children = Organization.children(id)
	for _, key in Organization.children(parent) do
		if key == id then
			for _, child in children do
				table.insert(siblings, child)
			end
		else
			table.insert(siblings, key)
		end
	end

	folders[id], placements[id] = nil, nil
	placeList(parent, siblings)
	commit(before, "Delete " .. folder.name)
	return true
end

function Organization.setEnabled(id, value)
	local folder = folders[id]
	value = value ~= false
	if not folder or folder.enabled == value then
		return false
	end

	local before = Organization.snapshot()
	folders[id] = table.freeze({ id = id, name = folder.name, enabled = value })
	commit(before, value and "Enable folder" or "Disable folder", "enabled")
	return true
end

function Organization.setOwnEnabled(keys, value)
	if typeof(keys) ~= "table" then
		keys = { keys }
	end

	value = value ~= false
	local changed = false
	local before = Organization.snapshot()
	for _, key in ipairs(keys) do
		if natural[key] and Organization.getOwnEnabled(key) ~= value then
			ownEnabled[key] = value
			changed = true
		end
	end

	if changed then
		commit(before, value and "Enable tracks" or "Disable tracks", "enabled")
	end

	return changed
end

function Organization.removeRig(rig)
	local removedKeys = {}

	local function belongs(key)
		return typeof(key) == "Instance"
			and (key == rig or key:IsDescendantOf(rig) or natural[key] and natural[key].rig == rig)
	end

	for key in natural do
		if belongs(key) then
			removedKeys[key] = true
		end
	end

	for key in placements do
		if belongs(key) then
			removedKeys[key] = true
		end
	end

	for key in ownEnabled do
		if belongs(key) then
			removedKeys[key] = true
		end
	end

	local lifted = {}
	for key in folders do
		local parent = Organization.parent(key)
		local seen = {}
		while parent and removedKeys[parent] and not seen[parent] do
			seen[parent] = true
			parent = Organization.parent(parent)
		end

		if parent ~= Organization.parent(key) then
			lifted[key] = parent or false
		end
	end

	for key in natural do
		if removedKeys[key] then
			continue
		end

		local parent = Organization.parent(key)
		local seen = {}
		while parent and removedKeys[parent] and not seen[parent] do
			seen[parent] = true
			parent = Organization.parent(parent)
		end

		if parent ~= Organization.parent(key) then
			lifted[key] = parent or false
		end
	end

	for key in removedKeys do
		natural[key], placements[key], ownEnabled[key], removed[key] = nil, nil, nil, nil
	end

	for key, parent in lifted do
		placements[key] = { parent = parent, order = math.huge }
	end

	notify("change")
end

local function savedSnapshot()
	local snapshot = Organization.snapshot()
	local visited = {}

	local function visit(parent)
		for order, key in Organization.children(parent) do
			if visited[key] then
				continue
			end

			visited[key] = true
			snapshot.placements[key] = { parent = parent or false, order = order }
			visit(key)
		end
	end

	visit(nil)
	return snapshot
end

function Organization.write(container, rigs)
	return Storage.write(container, savedSnapshot(), natural, rigs)
end

function Organization.writeForRig(container, rig)
	return Storage.write(container, savedSnapshot(), natural, { rig }, rig)
end

function Organization.read(container, rigs)
	local snapshot = Storage.read(container, rigs)
	generation += 1
	Organization.restore(snapshot or { nextNumber = 1 }, "load")
	if rigArmatures(rigs, importCollections) then
		notify("collections")
	end

	return snapshot ~= nil
end

local collectionRefs, collectionWindow, collectionUnsubscribe, collectionDestroying
local collectionViews = setmetatable({}, { __mode = "k" })
local collectionLifetime, collectionGuis = {}, {}

function Organization.isBoneVisible(part)
	if not part then
		return true
	end

	if hiddenBones[part] then
		return false
	end

	local arm = part.Parent
	local visibility = arm and not importedArmatures[arm] and armatureVisibility[arm]
	if visibility then
		return visibility[part:GetAttribute("EclipseArmatureBoneId")] ~= false
	end

	if boneVisibility[part] ~= nil then
		return boneVisibility[part]
	end

	local assigned = false
	for _, collection in collections do
		if collection.members[part] then
			assigned = true
			if collection.visible ~= false then
				boneVisibility[part] = true
				return true
			end
		end
	end

	boneVisibility[part] = not assigned
	return not assigned
end

function Organization.isBoneHidden(part)
	return hiddenBones[part] == true
end

function Organization.usesPartWidget(part)
	return partWidgets[part] == true
end

function Organization.presentationRevision()
	return collectionRevision
end

function Organization.setPartWidget(part, enabled)
	if not part or partWidgets[part] == (enabled and true or nil) then
		return false
	end

	local before = Organization.snapshot()
	partWidgets[part] = enabled and true or nil
	commit(before, "Bone widget", "widgets")
	return true
end

function Organization.hideBones(parts)
	local before = Organization.snapshot()
	local changed = false
	for _, part in parts do
		if typeof(part) == "Instance" and part.Parent and not hiddenBones[part] then
			hiddenBones[part] = true
			changed = true
		end
	end

	if changed then
		commit(before, "Hide bones", "collections")
	end

	return changed
end

function Organization.unhideBones()
	if not next(hiddenBones) then
		return false
	end

	local before = Organization.snapshot()
	table.clear(hiddenBones)
	commit(before, "Unhide bones", "collections")
	return true
end

function Organization.toggleBones(parts)
	local hide = false
	for _, part in parts do
		if typeof(part) == "Instance" and part.Parent and not hiddenBones[part] then
			hide = true
			break
		end
	end

	local before = Organization.snapshot()
	local changed = false
	for _, part in parts do
		if typeof(part) == "Instance" and part.Parent and (hiddenBones[part] == true) ~= hide then
			hiddenBones[part] = hide and true or nil
			changed = true
		end
	end

	if changed then
		commit(before, hide and "Hide bones" or "Unhide bones", "collections")
	end

	return changed
end

function Organization.hideSelectedBones()
	if not collectionRefs then
		return false
	end

	local parts = {}
	for motor in collectionRefs.State.Timeline:GetJumpPinSelection() do
		local part = motor.Part1
		if typeof(part) == "Instance" and (part:IsA("BasePart") or part:IsA("Bone")) then
			table.insert(parts, part)
		end
	end

	return Organization.toggleBones(parts)
end

function Organization.collections()
	local result = {}
	for _, collection in collections do
		table.insert(result, {
			id = collection.id,
			name = collection.name,
			visible = collection.visible,
			members = table.clone(collection.members),
		})
	end

	table.sort(result, function(a, b)
		return a.name == b.name and a.id < b.id or a.name < b.name
	end)
	return result
end

function Organization.createCollection(name)
	local before = Organization.snapshot()
	local id = "bones_" .. HttpService:GenerateGUID(false)
	name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
	if name == "" then
		name = "Collection " .. tostring(#Organization.collections() + 1)
	end

	collections[id] = { id = id, name = name:sub(1, 80), visible = true, members = {} }
	commit(before, "Create bone collection", "collections")
	return id
end

function Organization.changeCollection(id, property, value)
	local collection = collections[id]
	if not collection or (property ~= "name" and property ~= "visible") then
		return false
	end

	if property == "name" then
		value = tostring(value or ""):match("^%s*(.-)%s*$"):sub(1, 80)
		if value == "" then
			return false
		end
	else
		value = value == true
	end

	if collection[property] == value then
		return false
	end

	local before = Organization.snapshot()
	collection[property] = value
	commit(before, "Change bone collection", "collections")
	return true
end

function Organization.assignCollection(id, parts, remove)
	local collection = collections[id]
	if not collection then
		return 0
	end

	local before = Organization.snapshot()
	local count = 0
	for _, part in parts do
		if
			typeof(part) == "Instance"
			and part.Parent
			and (part:IsA("BasePart") or part:IsA("Bone"))
		then
			local value = not remove and true or nil
			if collection.members[part] ~= value then
				collection.members[part] = value
				count += 1
			end
		end
	end

	if count > 0 then
		commit(
			before,
			remove and "Remove bones from collection" or "Assign bones to collection",
			"collections"
		)
	end

	return count
end

function Organization.removeCollection(id)
	if not collections[id] then
		return false
	end

	local before = Organization.snapshot()
	collections[id] = nil
	commit(before, "Delete bone collection", "collections")
	return true
end

function Organization.applyCollectionVisibility(rig, api)
	local folder = api:GetBonesFolder(rig)
	if not folder then
		return
	end

	if folder:GetAttribute("EclipsePlaybackHidden") then
		return
	end

	local cache = collectionViews[folder]
	if not next(collections) and not next(hiddenBones) and not cache then
		return
	end

	if not cache then
		cache = { hidden = {}, revision = -1 }
		collectionViews[folder] = cache
		cache.added = folder.DescendantAdded:Connect(function()
			cache.revision = -1
		end)
		cache.destroying = folder.Destroying:Connect(function()
			cache.added:Disconnect()
			cache.destroying:Disconnect()
			collectionViews[folder] = nil
		end)
	end

	if cache.revision ~= collectionRevision then
		for object, saved in cache.hidden do
			if object.Parent then
				if object:IsA("BasePart") then
					object.LocalTransparencyModifier = saved.transparency
					object.CanQuery = saved.query
				else
					object.Visible = saved.visible
				end
			end
		end

		cache.hidden = {}
		cache.revision = collectionRevision
		local hiddenParts = {}
		for _, marker in folder:GetChildren() do
			if marker:IsA("BasePart") then
				local owner = marker:FindFirstChild("EclipseLimbOwner")
				local part = api:GetPartFromBone(rig, marker)
				local visible = not part or Organization.isBoneVisible(part)
				if part and part:GetAttribute("EclipseArmatureBone") then
					require("distance").setVisible(
						part,
						visible and part:GetAttribute("Hidden") ~= true
					)
				end

				if
					owner
					and owner.Value
					and not Organization.isBoneVisible(
						require("R6Controls").resolveOwner(owner.Value).Part1
					)
				then
					visible = false
				end

				if not visible then
					hiddenParts[marker] = true
					cache.hidden[marker] = {
						transparency = marker.LocalTransparencyModifier,
						query = marker.CanQuery,
					}
				end
			end
		end

		for _, object in folder:GetDescendants() do
			if
				object:IsA("HandleAdornment")
				and (hiddenParts[object.Adornee] or hiddenParts[object.Parent])
			then
				cache.hidden[object] = { visible = object.Visible }
			end
		end
	end

	for object, saved in cache.hidden do
		if not object.Parent then
			cache.hidden[object] = nil
		elseif object:IsA("BasePart") then
			if object.CanQuery then
				saved.query = true
			end

			object.LocalTransparencyModifier = 1
			object.CanQuery = false
		else
			if object.Visible then
				saved.visible = true
			end

			object.Visible = false
		end
	end
end

function Organization.refreshCollectionControls()
	if not collectionRefs then
		return
	end

	local state = collectionRefs.State
	local api = state.Rig
	if not api then
		return
	end

	for _, rig in state.getAllRigs() do
		local folder = api:GetBonesFolder(rig)
		if folder then
			Organization.applyCollectionVisibility(rig, api)
		end

		if api._boneFollowCaches and api._boneFollowCaches[rig] then
			api._boneFollowCaches[rig].markerRevision = nil
		end
	end

	if state.Axis then
		local visible = {}
		for _, marker in state.Axis:GetSelectedBones() do
			local part = api:GetPartFromBone(state.currentRig, marker)
			local owner = marker:FindFirstChild("EclipseLimbOwner")
			if
				(not part or Organization.isBoneVisible(part))
				and (
					not owner
					or not owner.Value
					or Organization.isBoneVisible(
						require("R6Controls").resolveOwner(owner.Value).Part1
					)
				)
			then
				table.insert(visible, marker)
			end
		end

		state.Axis:SelectBones(visible)
		state.Axis:RefreshBoneFade()
		state.Axis:RefreshAxis()
	end

	for _, item in api._orderedItems or {} do
		local motor = item:fetchMotor()
		local label = item.centerDiv and item.centerDiv:FindFirstChild("Title")
		if label then
			local dim = motor and hiddenBones[motor.Part1] == true
			label:SetAttribute("ThemeTxtTransparency", dim and 0.55 or 0)
			require("WindowFX").setRestingProperty(label, "TextTransparency", dim and 0.55 or 0)
		end
	end

	for _, rig in state.getAllRigs() do
		local folder = api:GetBonesFolder(rig)
		if folder then
			for _, marker in folder:GetChildren() do
				local reference = marker:FindFirstChild("EclipseArmatureSource")
				local anchor = reference and reference.Value
				if anchor and anchor:GetAttribute("EclipseArmatureBone") then
					require("distance").setVisible(anchor, not anchor:GetAttribute("Hidden"))
				end
			end

			api:UpdateBonesFollowRig(rig)

			for _, marker in folder:GetChildren() do
				local reference = marker:FindFirstChild("EclipseArmatureSource")
				local anchor = reference and reference.Value
				if anchor and anchor.Parent then
					require("handles").updateArmature(marker, anchor)
				end
			end
		end
	end
end

function Organization.filterCollectionSelection(markers, rig, api)
	if not api or not next(collections) and not next(hiddenBones) then
		return markers
	end

	local result = {}
	for _, marker in markers do
		local part = api:GetPartFromBone(rig, marker)
		local owner = marker:FindFirstChild("EclipseLimbOwner")
		if
			Organization.isBoneVisible(part)
			and (
				not owner
				or not owner.Value
				or Organization.isBoneVisible(require("R6Controls").resolveOwner(owner.Value).Part1)
			)
		then
			table.insert(result, marker)
		end
	end

	return result
end

function Organization.closeCollections(immediate)
	if collectionWindow then
		local old = collectionWindow
		collectionWindow = nil
		old:close(immediate == true)
	end
end

function Organization.destroyCollections()
	Organization.closeCollections(true)
	if collectionUnsubscribe then
		collectionUnsubscribe()
		collectionUnsubscribe = nil
	end

	if collectionDestroying then
		collectionDestroying:Disconnect()
		collectionDestroying = nil
	end

	for _, connection in collectionLifetime do
		connection:Disconnect()
	end

	table.clear(collectionLifetime)
	for gui in collectionGuis do
		gui:Destroy()
	end

	table.clear(collectionGuis)
	collectionRefs = nil
end

function Organization.initCollections(refs)
	Organization.destroyCollections()
	collectionRefs = refs
	collectionDestroying = refs.ScreenGui.Destroying:Connect(Organization.destroyCollections)
	table.insert(
		collectionLifetime,
		refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then
				Organization.closeCollections(true)
			end
		end)
	)
	if refs.AnimatorFrame then
		table.insert(
			collectionLifetime,
			refs.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
				if not refs.AnimatorFrame.Visible then
					Organization.closeCollections(true)
				end
			end)
		)
	end

	if refs.Plugin then
		table.insert(
			collectionLifetime,
			refs.Plugin.Unloading:Connect(Organization.destroyCollections)
		)
	end

	collectionUnsubscribe = Organization.subscribe(function(reason)
		if reason == "collections" or reason == "widgets" then
			refs.State.currentProjectSaved = false
		end

		if reason == "reset" then
			Organization.closeCollections(true)
		end

		if
			reason == "collections"
			or reason == "widgets"
			or reason == "undo"
			or reason == "redo"
			or reason == "load"
			or reason == "reset"
			or reason == "membership"
		then
			Organization.refreshCollectionControls()
		end
	end)
end

function Organization.toggleCollections()
	if collectionWindow then
		Organization.closeCollections()
		return
	end

	local refs = collectionRefs
	if not refs or not refs.State.currentRig then
		require("Notification").show("BONE COLLECTION", "Open a project first.")
		return
	end

	local Tool = require("Tool")
	local unsubscribe
	local view = Tool.new(
		refs,
		"EclipseBoneCollection",
		"BONE COLLECTION",
		Vector2.new(360, 325),
		true,

		function()
			collectionWindow = nil
			if unsubscribe then
				unsubscribe()
			end
		end
	)
	collectionWindow = view
	collectionGuis[view.gui] = true
	view.gui.Destroying:Once(function()
		collectionGuis[view.gui] = nil
	end)
	local list = Tool.make("ScrollingFrame", view.frame, "Collections", {
		Position = UDim2.fromOffset(12, 42),
		Size = UDim2.new(1, -24, 0, 166),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		BackgroundTransparency = 0,
		BorderSizePixel = 1,
		ZIndex = 12,
	})
	list:SetAttribute("ThemeBg", "TopBtn")
	list.BorderColor3 = require("Theme").get("Strk", Color3.fromRGB(74, 116, 124))
	local name =
		Tool.field(view.frame, "Name", "", UDim2.fromOffset(12, 219), UDim2.new(1, -24, 0, 25))
	local selected

	local function parts()
		local result = {}
		local state = refs.State
		for _, marker in state.Axis:GetSelectedBones() do
			local part = state.Rig:GetPartFromBone(state.currentRig, marker)
			if part then
				table.insert(result, part)
			end
		end

		return result
	end

	local function refresh()
		for _, child in list:GetChildren() do
			child:Destroy()
		end

		local entries = Organization.collections()
		if not collections[selected] then
			selected = entries[1] and entries[1].id
		end

		name.Text = collections[selected] and collections[selected].name or ""
		for index, collection in entries do
			local count = 0
			for part in collection.members do
				if part.Parent then
					count += 1
				end
			end

			Tool.button(
				list,
				collection.id,
				(selected == collection.id and "> " or "")
					.. collection.name
					.. " ("
					.. count
					.. ")",
				UDim2.fromOffset(0, (index - 1) * 31),
				UDim2.new(1, -75, 0, 27),

				function()
					selected = collection.id
					refresh()
				end
			)
			Tool.button(
				list,
				"Visibility",
				collection.visible and "HIDE" or "SHOW",
				UDim2.new(1, -69, 0, (index - 1) * 31),
				UDim2.fromOffset(64, 27),

				function()
					Organization.changeCollection(collection.id, "visible", not collection.visible)
				end
			)
		end

		list.CanvasSize = UDim2.fromOffset(0, #entries * 31)
	end

	local function button(id, text, x, y, w, fn)
		Tool.button(view.frame, id, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, 27), fn)
	end

	button("Add", "NEW", 12, 253, 102, function()
		selected = Organization.createCollection(name.Text)
		refresh()
	end)
	button("Rename", "RENAME", 123, 253, 103, function()
		Organization.changeCollection(selected, "name", name.Text)
	end)
	button("Delete", "DELETE", 235, 253, 113, function()
		Organization.removeCollection(selected)
	end)
	button("Assign", "ASSIGN", 12, 290, 102, function()
		Organization.assignCollection(selected, parts())
	end)
	button("Remove", "REMOVE", 123, 290, 103, function()
		Organization.assignCollection(selected, parts(), true)
	end)
	button("Select", "SELECT", 235, 290, 113, function()
		local collection = collections[selected]
		if not collection then
			return
		end

		Organization.changeCollection(selected, "visible", true)
		local state = refs.State
		local markers = {}
		for _, rig in state.getAllRigs() do
			local folder = state.Rig:GetBonesFolder(rig)
			if folder then
				for _, marker in folder:GetChildren() do
					if
						marker:IsA("BasePart")
						and collection.members[state.Rig:GetPartFromBone(rig, marker)]
					then
						table.insert(markers, marker)
					end
				end
			end
		end

		state.Axis:SelectBones(markers)
		state.Axis:RefreshAxis()
	end)
	unsubscribe = Organization.subscribe(refresh)
	refresh()
	require("Theme").applyTree(view.frame)
	return view.frame
end

return Organization
