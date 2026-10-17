--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local AssetService = game:GetService("AssetService")
local Codec = require("SceneCodec")
local Camera = require("CameraRig")
local R6Controls = require("R6Controls")
local Export = {}

local function round(value)
	return math.round(value * 1e4) / 1e4
end

local function vector(value)
	return { round(value.X), round(value.Y), round(value.Z) }
end

local function compact(frame)
	local values = Codec.pack(frame)
	for index, number in values do
		values[index] = math.round(number * 1e5) / 1e5
	end

	return values
end

local function appearance(part, size)
	local c = part.Color
	local value = {
		rendered = true,
		class = part.ClassName,
		color = { c.R, c.G, c.B },
		opacity = 1 - part.Transparency,
		size = vector(size),
		decals = {},
	}
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		value.special = {
			type = mesh.MeshType.Name,
			scale = vector(mesh.Scale),
			offset = vector(mesh.Offset),
			mesh = mesh.MeshId,
			texture = mesh.TextureId,
		}
	end

	for _, child in part:GetChildren() do
		if child:IsA("Decal") and not child:IsA("Texture") and child.Transparency < 1 then
			local color = child.Color3
			table.insert(value.decals, {
				face = child.Face.Name,
				texture = child.Texture,
				opacity = 1 - child.Transparency,
				color = { color.R, color.G, color.B },
			})
		end
	end

	return value
end

function Export.build(refs, selected, options)
	options = options or {}
	local manifest, bindings = Codec.capture(refs)
	local package = Instance.new("Model")
	package.Name, package.Archivable = "Eclipse Rig Export", false
	local metadata = {
		format = "EclipseRig",
		version = 1,
		accessory = options.accessory ~= nil,
		centered = options.center == true,
		rigs = {},
	}
	local ok, err = xpcall(function()
		for rigIndex, row in manifest.rigs do
			local entry = bindings[row.id]
			if selected and not selected[entry.rig] then
				continue
			end

			local rig = entry.rig
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			local nativeCharacter = humanoid and not options.accessory
			local bodyNames = {
				Head = true,
				Torso = true,
				["Left Arm"] = true,
				["Right Arm"] = true,
				["Left Leg"] = true,
				["Right Leg"] = true,
			}
			for _, body in Enum.BodyPartR15:GetEnumItems() do
				bodyNames[body.Name] = true
			end

			if nativeCharacter then
				row.meshGroup = "eclipserig" .. rigIndex .. "q"
			end

			if entry.camera then
				row.camera, row.fov = Codec.pack(Camera.viewFrame(rig)), Camera.fov(rig)
			end

			local originals, copies = {}, {}

			local function paths(object, path, output)
				output[path] = object
				for index, child in object:GetChildren() do
					paths(child, path .. "/" .. index, output)
				end
			end

			paths(rig, "", originals)
			local archivable = {}
			for _, original in originals do
				archivable[original] = original.Archivable
				original.Archivable = true
			end

			local cloned, clone = pcall(rig.Clone, rig)
			for original, value in archivable do
				original.Archivable = value
			end

			assert(cloned and clone, "Could not copy " .. rig.Name)
			clone.Parent = package
			if nativeCharacter then
				clone.Name = row.meshGroup
			end

			paths(clone, "", copies)
			if options.accessory and not options.accessory:IsDescendantOf(rig) then
				local original = options.accessory
				local enabled = original.Archivable
				original.Archivable = true
				local success, copy = pcall(original.Clone, original)
				original.Archivable = enabled
				assert(success and copy, "Could not copy the accessory.")
				copy.Parent = clone
				paths(original, "accessory", originals)
				paths(copy, "accessory", copies)
			end

			local byOriginal, byPart, byName = {}, {}, {}
			for path, original in originals do
				byOriginal[original] = copies[path]
			end

			for index, track in entry.tracks do
				byPart[track.motor.Part1] = row.tracks[index]
				byName[track.name] = if byName[track.name] ~= nil then false else index
			end

			local joints = {}
			for _, original in originals do
				if original:IsA("JointInstance") or original:IsA("WeldConstraint") then
					if original.Part0 and original.Part1 then
						joints[original.Part1] = joints[original.Part1] or {}
						table.insert(joints[original.Part1], original.Part0)
						joints[original.Part0] = joints[original.Part0] or {}
						table.insert(joints[original.Part0], original.Part1)
					end
				end
			end

			local function owner(part)
				local seen, pending = {}, { part }
				local at = 1
				while at <= #pending do
					local current = pending[at]
					at += 1
					if seen[current] then
						continue
					end

					seen[current] = true
					if byPart[current] then
						return byPart[current], current
					end

					for _, adjacent in joints[current] or {} do
						table.insert(pending, adjacent)
					end
				end
			end

			row.parts = {}
			for path, original in originals do
				local copy = copies[path]
				if
					original:IsA("LuaSourceContainer")
					or original:IsA("JointInstance")
					or original:IsA("Constraint")
				then
					copy:Destroy()
				elseif original:IsA("Bone") then
					if R6Controls.isControl(original) then
						copy:Destroy()
					else
						copy.Transform = CFrame.identity
					end
				elseif original:IsA("BasePart") then
					if row.kind == "camera" or original.Transparency >= 1 then
						copy:Destroy()
						continue
					end

					if
						options.accessory
						and original ~= options.accessory
						and not original:IsDescendantOf(options.accessory)
					then
						copy:Destroy()
						continue
					end

					local track, part = owner(original)
					if
						options.welds == false
						and track
						and not byPart[original]
						and not options.accessory
					then
						copy:Destroy()
						continue
					end

					copy.Anchored, copy.CanCollide = true, false
					if track then
						copy.CFrame = Codec.unpack(track.rest)
							* part.CFrame:Inverse()
							* original.CFrame
					end

					copy.Size = refs.State.Timeline:GetState().DefaultSize[original]
						or original.Size
					local token = "eclipser" .. rigIndex .. "p" .. (#row.parts + 1) .. "q"
					local item = {
						token = token,
						name = original.Name,
						track = track and track.id,
						matrix = compact(copy.CFrame),
					}
					item.appearance = appearance(original, copy.Size)

					if nativeCharacter and original.Parent == rig and bodyNames[original.Name] then
						item.meshGroup = row.meshGroup
						item.appearance.nativeCharacter = true
					else
						copy.Name = token
					end

					if
						original:IsA("MeshPart")
						and original:FindFirstChildWhichIsA("Bone", true)
					then
						local editable
						local read, failure = pcall(function()
							editable = AssetService:CreateEditableMeshAsync(original.MeshContent)
							assert(editable, "mesh data unavailable")
							item.skin = {}
							local scale = copy.Size / original.MeshSize
							for _, vertex in editable:GetVertices() do
								local bones, weights =
									editable:GetVertexBones(vertex),
									editable:GetVertexBoneWeights(vertex)
								local values = {}
								for index, bone in bones do
									local id = byName[editable:GetBoneName(bone)]
									assert(id, "unmapped or duplicate skin bone")
									table.insert(values, { id, round(weights[index]) })
								end

								table.insert(item.skin, {
									position = vector(
										copy.CFrame * (editable:GetPosition(vertex) * scale)
									),
									weights = values,
								})
							end
						end)
						if editable then
							editable:Destroy()
						end

						assert(
							read,
							"Cannot export skin weights for "
								.. original.Name
								.. ": "
								.. tostring(failure)
						)
					end

					table.insert(row.parts, item)
				end
			end

			if options.accessory then
				assert(#row.parts > 0, "The selected accessory has no exportable geometry.")
				local linked = false
				for _, part in row.parts do
					if part.track then
						linked = true
						break
					end
				end

				assert(
					linked,
					"The accessory needs a weld or Motor6D connection to the chosen rig."
				)
			end

			if options.center then
				local origin = Codec.unpack(row.origin).Position
				local translation = -origin
				if not options.accessory and row.kind ~= "camera" then
					local bottom = math.huge
					for _, part in row.parts do
						local frame = Codec.unpack(part.matrix)
						local size = Vector3.new(table.unpack(part.appearance.size))
						local extent = (
							math.abs(frame.RightVector.Y) * size.X
							+ math.abs(frame.UpVector.Y) * size.Y
							+ math.abs(frame.LookVector.Y) * size.Z
						) * 0.5
						bottom = math.min(bottom, frame.Position.Y - extent)
					end

					if bottom < math.huge then
						translation = Vector3.new(-origin.X, -bottom, -origin.Z)
						row.grounded = true
					end
				end

				local shift = CFrame.new(translation)
				row.origin = compact(shift * Codec.unpack(row.origin))
				if row.camera then
					row.camera = compact(shift * Codec.unpack(row.camera))
				end

				for _, track in row.tracks do
					track.rest = compact(shift * Codec.unpack(track.rest))
					if track.joint then
						track.joint = compact(shift * Codec.unpack(track.joint))
					end
				end

				for _, part in row.parts do
					part.matrix = compact(shift * Codec.unpack(part.matrix))
					for _, vertex in part.skin or {} do
						vertex.position = vector(shift * Vector3.new(table.unpack(vertex.position)))
					end
				end

				for _, part in clone:GetDescendants() do
					if part:IsA("BasePart") then
						part.CFrame = shift * part.CFrame
					end
				end
			end

			table.insert(metadata.rigs, row)
		end

		assert(#metadata.rigs > 0, "Select a rig in this Eclipse file")
		local data = Http:JSONEncode(metadata)
		local encoded = data:gsub(".", function(char)
			return string.format("%02X", string.byte(char))
		end)

		for offset = 1, #encoded, 44 do
			local marker = Instance.new("Part")
			marker.Name = "eclipse"
				.. math.floor((offset - 1) / 44 + 1)
				.. "q1"
				.. encoded:sub(offset, offset + 43)
				.. "q1"
			marker.Size, marker.Anchored, marker.CanCollide =
				Vector3.new(0.01, 0.01, 0.01), true, false
			marker.Parent = package
		end
	end, debug.traceback)
	if not ok then
		package:Destroy()
		error(err, 0)
	end

	return package, metadata
end

function Export.connection(rig, accessory)
	local function inside(part, root)
		return part and (part == root or part:IsDescendantOf(root))
	end

	for _, root in { rig, accessory } do
		for _, joint in root:GetDescendants() do
			if not joint:IsA("JointInstance") and not joint:IsA("WeldConstraint") then
				continue
			end

			if
				inside(joint.Part1, accessory)
				and inside(joint.Part0, rig)
				and not inside(joint.Part0, accessory)
			then
				return "Connected to " .. joint.Part0.Name
			end

			if
				inside(joint.Part0, accessory)
				and inside(joint.Part1, rig)
				and not inside(joint.Part1, accessory)
			then
				return "Connected to " .. joint.Part1.Name
			end
		end
	end

	return "No weld or Motor6D connection to this rig"
end

function Export.prepare(package)
	package.Parent = workspace
	local done, failure = false, nil
	local pending = task.spawn(function()
		local ok, err = pcall(function()
			local missing = {}
			game:GetService("ContentProvider"):PreloadAsync({ package }, function(id, status)
				if status ~= Enum.AssetFetchStatus.Success then
					table.insert(missing, tostring(id))
				end
			end)
			assert(
				#missing == 0,
				"Appearance assets could not load: " .. table.concat(missing, ", ")
			)
		end)
		if not ok then
			failure = tostring(err)
		end

		done = true
	end)
	local deadline = os.clock() + 30
	repeat
		task.wait()
	until done or not package.Parent or os.clock() >= deadline
	if not done then
		pcall(task.cancel, pending)
	end

	assert(package.Parent == workspace, "Export cancelled before appearance finished loading")
	assert(
		done,
		"Appearance loading timed out. Try exporting again once the avatar is fully loaded."
	)
	assert(not failure, failure)

	task.wait(1)
	assert(package.Parent == workspace, "Export cancelled")
end

local pendingCleanup

function Export.save(refs, selected, options)
	if pendingCleanup then
		pendingCleanup()
	end

	local package = Export.build(refs, selected, options)
	local previous = Selection:Get()
	local connections = {}

	local function cleanup()
		if pendingCleanup ~= cleanup then
			return
		end

		pendingCleanup = nil
		for _, connection in connections do
			connection:Disconnect()
		end

		local current = Selection:Get()
		if #current == 1 and current[1] == package then
			Selection:Set(previous)
		end

		package:Destroy()
	end

	pendingCleanup = cleanup
	table.insert(connections, refs.Plugin.Unloading:Connect(cleanup))
	local ok, err = xpcall(function()
		Export.prepare(package)
		Selection:Set({ package })
		PluginManager():ExportSelection(
			options and options.accessory and "Eclipse Accessory.obj" or "Eclipse Rig.obj"
		)
	end, debug.traceback)
	if not ok then
		cleanup()
		error(err, 0)
	end

	task.defer(function()
		if pendingCleanup ~= cleanup then
			return
		end

		table.insert(
			connections,
			Selection.SelectionChanged:Connect(function()
				local current = Selection:Get()
				if #current ~= 1 or current[1] ~= package then
					cleanup()
				end
			end)
		)
		task.delay(600, cleanup)
	end)
end

return Export
