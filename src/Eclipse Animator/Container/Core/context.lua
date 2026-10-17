--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Codec = require("Codec")
local Paths = require("ClipboardRows")
local Cleanup = require("DumpStorage")
local Plan = {}

local function folder(parent, name)
	local object = Instance.new("Folder")
	object.Name = name
	object.Parent = parent
	return object
end

local function supportedSource(source, name)
	local list = require("list").tokens(source)
	local server = {
		ServerStorage = true,
		ServerScriptService = true,
		DataStoreService = true,
		MessagingService = true,
	}
	for i, token in list do
		local nextToken, argument = list[i + 1], list[i + 2]
		if token.kind == "name" and nextToken and nextToken.value == "(" then
			assert(
				token.value ~= "require" or not argument or argument.kind ~= "number",
				"Numeric require is unavailable to game clients: "
					.. name
					.. ". Add the local module as a dependency."
			)
		end

		local previous = list[i - 1]
		local serviceLookup = token.kind == "name"
			or token.kind == "string"
				and previous
				and (previous.value == "[" or previous.value == "(" and list[i - 2] and (list[i - 2].value == "GetService" or list[i - 2].value == "FindService"))
		assert(
			not serviceLookup or not server[token.value],
			"Client event references "
				.. token.value
				.. ": "
				.. name
				.. ". Move visual assets/modules to ReplicatedStorage or use a scripting callback."
		)
	end
end

function Plan.create(options, fps, last)
	local root = Instance.new("ModuleScript")
	root.Name = options.Name
	local scene = folder(root, "Scene")
	folder(scene, "Assets")
	local meshFolder = folder(root, "Meshes")
	local originals = folder(root, "Originals")
	local data = {
		Version = 1,
		FPS = fps,
		LastFrame = last,
		CameraMode = options.CameraMode,
		Tracks = {},
		Bindings = {},
		Roots = {},
		Globals = {},
		Events = {},
		Subtitles = {},
		Effects = {},
		EffectCameras = {},
		Geometry = {},
	}
	local surfaces = {}
	local sourceCode = {}
	local ids, copies = {}, {}
	local context = { nextId = 0 }
	local scanQueue = {}
	local rootKinds = {}
	local objectQueue = {}

	local function code(source, label)
		if not source or source == "" then
			return
		end

		supportedSource(source, label)
		local id = "Code" .. tostring(#sourceCode + 1)
		table.insert(sourceCode, { Id = id, Source = source, Name = label })
		return id
	end

	local function identify(source, copy)
		context.nextId += 1
		local id = tostring(context.nextId)
		ids[source] = id
		copies[source] = copy
		copy:SetAttribute("EclipseExportId", id)
		table.insert(objectQueue, source)
		if source:IsA("ModuleScript") then
			local ok, text = pcall(function()
				return game:GetService("ScriptEditorService"):GetEditorSource(source)
			end)
			text = ok and text or source.Source
			copy:SetAttribute("EclipseExportCode", code(text, source:GetFullName()))
			table.insert(scanQueue, { Source = text, Script = source })
		end

		return id
	end

	local excluded = { AnimSaves = true, BonesFolder = true, dragGuides = true, EclipseSave = true }
	local previewOnly =
		{ EclipseEventPlayback = true, EclipseEventParticle = true, EclipseEventHold = true }

	local function templateJoint(object)
		if not object:IsA("JointInstance") or object:IsA("Motor6D") then
			return false
		end

		for _, part in { object.Part0, object.Part1 } do
			if part and part:IsDescendantOf(game:GetService("CoreGui")) then
				return true
			end
		end

		return false
	end

	local function cloneTree(source)
		local all = source:GetDescendants()
		table.insert(all, 1, source)
		local previous = {}
		for _, object in all do
			previous[object] = object.Archivable
			object.Archivable = true
		end

		local ok, clone = pcall(function()
			return source:Clone()
		end)
		for object, value in previous do
			object.Archivable = value
		end

		assert(ok and clone, "Cannot clone " .. source:GetFullName())

		local function pair(a, b)
			identify(a, b)
			if b:IsA("BaseScript") then
				b.Enabled = false
			end

			local bChildren = b:GetChildren()
			local byName = {}
			for _, copy in bChildren do
				local key = copy.ClassName .. "\0" .. copy.Name
				local matches = byName[key]
				if not matches then
					matches = {}
					byName[key] = matches
				end

				table.insert(matches, copy)
			end

			local occurrences = {}
			for _, child in a:GetChildren() do
				if child.ClassName == "Status" then
					continue
				end
				local key = child.ClassName .. "\0" .. child.Name
				local index = (occurrences[key] or 0) + 1
				occurrences[key] = index
				local matches = byName[key]
				local copy = matches and matches[index]
				assert(copy, "Cannot clone export object " .. child:GetFullName())
				if copies[child] then
					copies[child].Parent = b
					copy:Destroy()
				elseif
					excluded[child.Name]
					or templateJoint(child)
					or child:IsA("KeyframeSequence")
					or child:GetAttribute("EclipseOwnedUI")
					or child:GetAttribute("EclipseEffectSurface")
					or previewOnly[child.Name]
					or Cleanup.isVisual(child)
				then
					copy:Destroy()
				else
					pair(child, copy)
				end
			end
		end

		local paired, message = pcall(pair, source, clone)
		if not paired then
			clone:Destroy()
			error(message)
		end

		return clone
	end

	local rootSources = {}

	local function reference(source)
		local id = ids[source]
		if not originals:FindFirstChild(id) then
			local value = Instance.new("ObjectValue")
			value.Name = id
			value.Value = source
			value.Parent = originals
		end

		return id
	end

	local function addRoot(source, kind)
		if ids[source] then
			return
		end

		assert(source and (source.Parent or kind == "Surface"), "An export object was deleted")
		assert(
			source ~= workspace and not source:IsA("Terrain"),
			"Export individual objects; the entire Workspace/Terrain is not an actor."
		)
		local copy = cloneTree(source)
		copy.Parent = kind == "Dependency" and scene.Assets or scene
		rootKinds[source] = kind
		local service = source:IsDescendantOf(game:GetService("Lighting")) and "Lighting"
			or source:IsDescendantOf(game:GetService("SoundService")) and "SoundService"
			or source:IsDescendantOf(game:GetService("MaterialService")) and "MaterialService"
			or nil
		local record = {
			Id = ids[source],
			Kind = kind,
			InWorld = source:IsDescendantOf(workspace),
			Service = service,
			Path = service and Codec.path(source) or nil,
		}
		table.insert(data.Roots, record)
		table.insert(rootSources, source)
		if service then
			record.Reference = reference(source)
			record.Selector = Codec.selector(source)
		end

		if
			kind ~= "Surface"
			and (
				service
				or source:IsDescendantOf(workspace)
				or source:IsDescendantOf(game:GetService("ReplicatedStorage"))
			)
		then
			local binding = {
				Path = Codec.path(source),
				Selector = Codec.selector(source),
				Reference = reference(source),
				Visible = source:IsDescendantOf(workspace),
				Nodes = {},
			}
			for original in ids do
				if original == source or original:IsDescendantOf(source) then
					table.insert(binding.Nodes, {
						Id = ids[original],
						Reference = reference(original),
						Path = Paths.path(source, original),
					})
				end
			end

			table.insert(data.Bindings, binding)
		end
	end

	context.root = root
	context.scene = scene
	context.meshFolder = meshFolder
	context.originals = originals
	context.data = data
	context.surfaces = surfaces
	context.sourceCode = sourceCode
	context.ids = ids
	context.copies = copies
	context.scanQueue = scanQueue
	context.rootKinds = rootKinds
	context.objectQueue = objectQueue
	context.code = code
	context.reference = reference
	context.addRoot = addRoot
	return context
end

function Plan.dependencies(context)
	local ids, copies, scanQueue, objectQueue, addRoot =
		context.ids, context.copies, context.scanQueue, context.objectQueue, context.addRoot
	local lighting = game:GetService("Lighting")

	local function referenceFields(source)
		if source:IsA("JointInstance") or source:IsA("WeldConstraint") then
			return { "Part0", "Part1" }
		end

		if source:IsA("Constraint") or source:IsA("Beam") or source:IsA("Trail") then
			return { "Attachment0", "Attachment1" }
		end

		if source:IsA("ObjectValue") then
			return { "Value" }
		end

		if source:IsA("Model") then
			return { "PrimaryPart" }
		end

		if source:IsA("Sound") then
			return { "SoundGroup" }
		end

		return {}
	end

	context.referenceFields = referenceFields
	local scanned = {}
	local scanIndex = 1
	local referenceIndex = 1
	repeat
		while scanIndex <= #scanQueue do
			assert(
				scanIndex <= 4096,
				"Too many event module dependencies. Select a smaller dependency folder."
			)
			local entry = scanQueue[scanIndex]
			scanIndex += 1
			if entry.Script and scanned[entry.Script] then
				continue
			end

			if entry.Script then
				scanned[entry.Script] = true
			end

			for _, dependency in require("list").scan(entry.Source, entry) do
				if not ids[dependency] then
					addRoot(dependency, "Dependency")
				end
			end
		end

		while referenceIndex <= #objectQueue do
			local source = objectQueue[referenceIndex]
			referenceIndex += 1
			if source:IsA("BasePart") and source.MaterialVariant ~= "" then
				local variant
				for _, entry in game:GetService("MaterialService"):GetDescendants() do
					if
						entry:IsA("MaterialVariant")
						and entry.Name == source.MaterialVariant
						and entry.BaseMaterial == source.Material
					then
						assert(not variant, "Ambiguous material variant: " .. entry.Name)
						variant = entry
					end
				end

				assert(variant, "Missing material variant: " .. source.MaterialVariant)
				if not ids[variant] then
					addRoot(variant, "Material")
				end
			end

			for _, key in referenceFields(source) do
				local value = source[key]
				if value and not copies[value] and not value:IsDescendantOf(game) then
					warn(
						"Eclipse export: "
							.. source:GetFullName()
							.. "."
							.. key
							.. " points at a destroyed instance, left empty"
					)
				elseif
					value
					and not copies[value]
					and not (source:IsA("ObjectValue") and source.Name:sub(1, 7) == "Eclipse")
				then
					assert(
						value:IsDescendantOf(workspace)
							or value:IsDescendantOf(game:GetService("ReplicatedStorage"))
							or value:IsDescendantOf(lighting)
							or value:IsDescendantOf(game:GetService("SoundService")),
						"External reference "
							.. source:GetFullName()
							.. "."
							.. key
							.. " must be in a client-visible service: "
							.. value:GetFullName()
					)
					local target = value
					if target:IsA("Attachment") then
						local parent = target.Parent
						while parent do
							if parent:IsA("BasePart") then
								target = parent
								break
							end

							parent = parent.Parent
						end
					end

					addRoot(target, "Dependency")
				end
			end
		end
	until scanIndex > #scanQueue and referenceIndex > #objectQueue
	local function owningRoot(part)
		while part do
			if context.rootKinds[part] then return part end
			part = part.Parent
		end
	end
	local changed
	repeat
		changed = false
		for source in copies do
			if not (source:IsA("JointInstance") or source:IsA("WeldConstraint")) or not source.Enabled then continue end
			local a, b = owningRoot(source.Part0), owningRoot(source.Part1)
			for _, pair in { { a, b }, { b, a } } do
				local from, target = pair[1], pair[2]
				local kind = from and context.rootKinds[from]
				if target and context.rootKinds[target] == "Dependency" and (kind == "Actor" or kind == "Bound") then
					context.rootKinds[target] = "Bound"
					copies[target].Parent = context.scene
					for _, record in context.data.Roots do if record.Id == ids[target] then record.Kind = "Bound" break end end
					changed = true
				end
			end
		end
	until not changed
end

return Plan
