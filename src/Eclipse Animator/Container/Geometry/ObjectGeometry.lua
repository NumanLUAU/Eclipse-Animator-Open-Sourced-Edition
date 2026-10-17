--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
--!native
local AssetService = game:GetService("AssetService")
local M = require("M")
local Objects = {}
local SAVED = "EclipseArmatureObjectTransparency"
local HELPER = "EclipseArmatureSkinningHelper"

local function hide(part, hidden)
	if not part.Parent then
		return
	end

	local saved = part:GetAttribute(SAVED)
	if hidden then
		if saved == nil then
			part:SetAttribute(SAVED, part.LocalTransparencyModifier)
		end

		part.LocalTransparencyModifier = 1
	elseif typeof(saved) == "number" then
		part.LocalTransparencyModifier = saved
		part:SetAttribute(SAVED, nil)
	end

	for _, child in part:GetChildren() do
		if child:IsA("Decal") or child:IsA("Texture") then
			hide(child, hidden)
		end
	end
end

function Objects.visible(entry, name)
	local object = entry.objects[name]
	if not object then
		return false
	end

	return not object.hide_viewport
		and not object.data.view_layer_hidden
		and not object.data.collection_hidden
end

local function syncAppearance(state)
	local source, proxy = state.appearanceSource, state.proxy
	if not source or not source.Parent or not proxy then
		return
	end

	for _, property in { "Color", "Material", "MaterialVariant", "Reflectance", "Transparency" } do
		if proxy[property] ~= source[property] then
			proxy[property] = source[property]
		end
	end

	proxy.LocalTransparencyModifier = source:GetAttribute(SAVED) or source.LocalTransparencyModifier
	if source:IsA("MeshPart") then
		proxy.TextureID, proxy.DoubleSided = source.TextureID, source.DoubleSided
	else
		local mesh = source:FindFirstChildWhichIsA("FileMesh")
		proxy.TextureID = mesh and mesh.TextureId or ""
	end

	local copies, keep = state.appearanceCopies, {}
	for _, child in source:GetChildren() do
		if not (child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture")) then
			continue
		end

		keep[child] = true
		local clone = copies[child]
		if not clone then
			local archivable = child.Archivable
			child.Archivable = true
			local ok, result = pcall(child.Clone, child)
			child.Archivable = archivable
			assert(ok and result, "Could not copy the imported object's appearance")
			clone = result
			clone:SetAttribute(SAVED, nil)
			clone.Parent = proxy
			copies[child] = clone
		end

		local properties = child:IsA("SurfaceAppearance")
				and { "Color", "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap", "AlphaMode" }
			or { "Color3", "Texture", "Transparency", "Face", "ZIndex" }
		for _, property in properties do
			if clone[property] ~= child[property] then
				clone[property] = child[property]
			end
		end

		if child:IsA("Decal") then
			clone.LocalTransparencyModifier = child:GetAttribute(SAVED)
				or child.LocalTransparencyModifier
		end

		if child:IsA("Texture") then
			for _, property in { "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV" } do
				if clone[property] ~= child[property] then
					clone[property] = child[property]
				end
			end
		end
	end

	for child, clone in copies do
		if not keep[child] then
			clone:Destroy()
			copies[child] = nil
		end
	end
end

local function nativeParts(entry, node)
	local parts = {}
	for _, binding in entry.bindings do
		if binding.node == node and binding.part then
			parts[binding.part] = true
		end
	end

	return parts
end

function Objects.attach(entry)
	local group = { entry = entry, states = {}, groups = {}, direct = {}, diagnostics = {} }

	for _, child in entry.arm:GetChildren() do
		if
			child:IsA("BasePart")
			and child:GetAttribute(HELPER) == true
			and child:GetAttribute("EclipseArmatureObjectSurface") == true
		then
			child:Destroy()
		end
	end

	local byName = {}
	for _, part in entry.rig:GetDescendants() do
		if
			part:IsA("BasePart")
			and not part:GetAttribute(HELPER)
			and not part:GetAttribute("EclipseArmatureBone")
		then
			byName[part.Name] = byName[part.Name] or {}
			table.insert(byName[part.Name], part)
			hide(part, false)
		end
	end

	local definitions = {}
	for _, definition in entry.data.rigid_meshes or {} do
		local node = entry.nodes[definition.bone]
		if not node then
			continue
		end

		definitions[definition.object] = true
		local family = group.groups[node]
		if not family then
			family = { node = node, states = {}, parts = nativeParts(entry, node) }
			group.groups[node] = family
		end

		local object = entry.objects[definition.object]
		local direct = {}
		for part in family.parts do
			if
				part.Name == definition.object
				or (node.data.geometry_binding == true and node.data.name == definition.object)
			then
				table.insert(direct, part)
			end
		end

		if #direct == 0 then
			local named = byName[definition.object]
			direct = named and #named == 1 and named or nil
		end

		local state = {
			definition = definition,
			node = node,
			family = family,
			vertices = {},
			normals = {},
			offset = M.mul(M.inverse(node.initialWorld), M.read(definition.matrix)),
			initialVisible = object and object.data.viewport_visible == true,
			direct = direct,
		}
		table.insert(family.states, state)
		table.insert(group.states, state)
	end

	for _, driver in entry.drivers do
		if
			driver.kind == "objectVisibility"
			and driver.field == "hide_viewport"
			and driver.object
		then
			local name = driver.object.data.name
			if not definitions[name] and byName[name] then
				group.direct[name] = byName[name]
			end

			if
				not definitions[name]
				and not byName[name]
				and driver.object.data.type == "MESH"
				and not group.missingGeometry
			then
				group.missingGeometry = true
				table.insert(
					group.diagnostics,
					"Mesh controls need a fresh armature export from the updated Eclipse Blender add-on."
				)
			end
		end
	end

	return group
end

local function build(group, state)
	if state.proxy then
		return
	end

	local definition = state.definition
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "Roblox could not allocate the imported object preview")
	state.mesh = mesh
	for _, position in definition.vertices do
		local point = Vector3.new(unpack(position))
		assert(M.isFiniteVector(point), "Invalid imported object vertex")
		table.insert(state.vertices, { id = mesh:AddVertex(point), point = point })
	end

	for _, face in definition.faces do
		local ids = {}
		for _, index in face.vertices do
			table.insert(ids, state.vertices[index + 1].id)
		end

		local id = mesh:AddTriangle(unpack(ids))
		if face.normals then
			local normals = {}
			for _, normal in face.normals do
				local direction = Vector3.new(unpack(normal))
				local normalId = mesh:AddNormal(direction)
				table.insert(normals, normalId)
				table.insert(state.normals, { id = normalId, direction = direction })
			end

			mesh:SetFaceNormals(id, normals)
		end

		if face.uvs then
			local uvs = {}
			for _, uv in face.uvs do
				table.insert(uvs, mesh:AddUV(Vector2.new(unpack(uv))))
			end

			mesh:SetFaceUVs(id, uvs)
		end
	end

	local neutral =
		mesh:AddBone({ Name = "__EclipseObject", CFrame = CFrame.identity, Virtual = false })
	for _, vertex in state.vertices do
		mesh:SetVertexBones(vertex.id, { neutral })
		mesh:SetVertexBoneWeights(vertex.id, { 1 })
	end

	local proxy = AssetService:CreateMeshPartAsync(
		Content.fromObject(mesh),
		{ CollisionFidelity = Enum.CollisionFidelity.Box }
	)
	state.proxy, state.meshSize = proxy, proxy.Size
	proxy.Name = definition.object
	proxy:SetAttribute(HELPER, true)
	proxy:SetAttribute("EclipseGeneratedVisual", true)
	proxy:SetAttribute("EclipseArmatureObjectSurface", true)
	proxy.Anchored, proxy.CanCollide, proxy.CanTouch, proxy.CanQuery, proxy.Locked =
		true, false, false, false, true
	proxy.DoubleSided = true
	local bone = Instance.new("Bone")
	bone.Name = "__EclipseObject"
	bone:SetAttribute(HELPER, true)
	bone.Parent = proxy
	local source = next(state.family.parts)
	if source then
		state.appearanceSource, state.appearanceCopies = source, {}
		syncAppearance(state)
	end

	if group.destroyed then
		proxy:Destroy()
		mesh:Destroy()
		error("The armature was closed while preparing an object preview")
	end
end

local function allocate(group, state)
	if state.proxy then
		return
	end

	local ok, issue = pcall(build, group, state)
	if not ok then
		if state.proxy then
			state.proxy:Destroy()
			state.proxy = nil
		end

		if state.mesh then
			state.mesh:Destroy()
			state.mesh = nil
		end

		table.clear(state.vertices)
		table.clear(state.normals)
		error(issue, 0)
	end
end

function Objects.prepare(group)
	if not group or group.destroyed then
		return
	end

	for _, family in group.groups do
		local changed = next(family.parts) == nil
		for _, state in family.states do
			state.visible = Objects.visible(group.entry, state.definition.object)
			if state.visible ~= state.initialVisible then
				changed = true
			end
		end

		family.changed = changed
		for _, state in family.states do
			state.showProxy = changed and state.visible and not state.direct
			if state.showProxy then
				allocate(group, state)
			end
		end
	end
end

function Objects.prepareExport(group)
	local surfaces = {}
	if not group then
		return surfaces
	end

	for _, state in group.states do
		if state.proxy then
			table.insert(surfaces, state.proxy)
		end
	end

	return surfaces
end

local function same(a, b)
	if not a then
		return false
	end

	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

function Objects.update(group)
	if not group or group.destroyed then
		return
	end

	local entry = group.entry
	for name, parts in group.direct do
		for _, part in parts do
			hide(part, not Objects.visible(entry, name))
		end
	end

	for _, family in group.groups do
		for part in family.parts do
			hide(part, family.changed)
		end

		for _, rigid in entry.rigidGeometry and entry.rigidGeometry.states or {} do
			if family.parts[rigid.part] and rigid.proxy then
				hide(rigid.proxy, family.changed)
			end
		end

		for _, state in family.states do
			if state.direct then
				for _, part in state.direct do
					hide(part, not state.visible)
				end
			end

			local proxy = state.proxy
			if not proxy then
				continue
			end

			if not state.showProxy then
				proxy.Parent = nil
				continue
			end

			syncAppearance(state)
			local affine = M.mul(
				entry.fitMatrix,
				M.translationScaled(M.mul(state.node.world, state.offset), entry.scale)
			)
			if not same(state.last, affine) then
				local frame = M.toCFrame(affine)
				local localMatrix = M.mul(M.fromCFrame(frame:Inverse()), affine)
				local inverse = M.inverse(localMatrix)
				for _, vertex in state.vertices do
					state.mesh:SetPosition(
						vertex.id,
						M.point(localMatrix, vertex.point * entry.scale)
					)
				end

				for _, normal in state.normals do
					local n = normal.direction
					local value = Vector3.new(
						inverse[1] * n.X + inverse[5] * n.Y + inverse[9] * n.Z,
						inverse[2] * n.X + inverse[6] * n.Y + inverse[10] * n.Z,
						inverse[3] * n.X + inverse[7] * n.Y + inverse[11] * n.Z
					)
					state.mesh:SetNormal(
						normal.id,
						value.Magnitude > 1e-12 and value.Unit or Vector3.yAxis
					)
				end

				proxy.CFrame, proxy.Size = frame, state.meshSize
				state.last = table.clone(affine)
			end

			proxy.Parent = entry.arm
		end
	end
end

function Objects.cleanup(group)
	if not group or group.destroyed then
		return
	end

	group.destroyed = true
	for _, state in group.states do
		if state.proxy then
			state.proxy:Destroy()
		end

		if state.mesh then
			state.mesh:Destroy()
		end

		if state.direct then
			for _, part in state.direct do
				hide(part, false)
			end
		end
	end

	for _, family in group.groups do
		for part in family.parts do
			hide(part, false)
		end
	end

	for _, parts in group.direct do
		for _, part in parts do
			hide(part, false)
		end
	end
end

return Objects
