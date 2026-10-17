--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local AssetService = game:GetService("AssetService")
local MeshAccess = require("MeshAccess")
local M = require("M")
local Rigid = {}
local HELPER = "EclipseArmatureSkinningHelper"
local SAVED = "EclipseArmatureRigidLocalTransparency"
local BODY_NAMES = {
	Head = true,
	Torso = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}
local R15_BODY_NAMES = {
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

local function nativeAvatarBody(part)
	local parent = part.Parent
	local humanoid = parent and parent:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return humanoid.RigType == Enum.HumanoidRigType.R6 and BODY_NAMES[part.Name] == true
		or humanoid.RigType == Enum.HumanoidRigType.R15 and R15_BODY_NAMES[part.Name] == true
end

local function near(a, b)
	for i = 1, 12 do
		if math.abs(a[i] - b[i]) > 1e-9 then
			return false
		end
	end

	return true
end

local function mark(instance)
	instance:SetAttribute("EclipseGeneratedVisual", true)
	instance:SetAttribute(HELPER, true)
end

local function normal(matrix, value)
	local v = Vector3.new(
		matrix[1] * value.X + matrix[5] * value.Y + matrix[9] * value.Z,
		matrix[2] * value.X + matrix[6] * value.Y + matrix[10] * value.Z,
		matrix[3] * value.X + matrix[7] * value.Y + matrix[11] * value.Z
	)
	return v.Magnitude > 1e-15 and v.Unit or Vector3.yAxis
end

local function requiresProxy(matrix)
	local x, y, z = M.column(matrix, 1), M.column(matrix, 2), M.column(matrix, 3)
	local a, b, c = x.Magnitude, y.Magnitude, z.Magnitude
	if math.min(a, b, c) < 1e-10 then
		return true
	end

	return x:Dot(y:Cross(z)) < 0
		or math.abs(x:Dot(y)) > 1e-6 * a * b
		or math.abs(x:Dot(z)) > 1e-6 * a * c
		or math.abs(y:Dot(z)) > 1e-6 * b * c
end

local function restorePart(part)
	local saved = part:GetAttribute(SAVED)
	if typeof(saved) == "number" then
		part.LocalTransparencyModifier = saved
		part:SetAttribute(SAVED, nil)
	end

	for _, child in part:GetChildren() do
		if child:IsA("Decal") or child:IsA("Texture") then
			local value = child:GetAttribute(SAVED)
			if typeof(value) == "number" then
				child.LocalTransparencyModifier = value
				child:SetAttribute(SAVED, nil)
			end
		end
	end
end

local function showSource(state)
	if state.active then
		state.active = false
		if state.part.Parent then
			restorePart(state.part)
		end

		state.proxy.Parent = nil
	end
end

local function dispose(state)
	state.destroyed = true
	showSource(state)
	if state.connection then
		state.connection:Disconnect()
		state.connection = nil
	end

	if state.proxy then
		state.proxy:Destroy()
		state.proxy = nil
	end

	if state.mesh then
		state.mesh:Destroy()
		state.mesh = nil
	end
end

local function blockMesh(size)
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "Roblox could not allocate the rigid surface preview")
	local positions = {}
	for z = -1, 1, 2 do
		for y = -1, 1, 2 do
			for x = -1, 1, 2 do
				table.insert(positions, mesh:AddVertex(Vector3.new(x, y, z) * size * 0.5))
			end
		end
	end

	local quads = {
		{ 1, 5, 7, 3 },
		{ 2, 4, 8, 6 },
		{ 1, 2, 6, 5 },
		{ 3, 7, 8, 4 },
		{ 1, 3, 4, 2 },
		{
			5,
			6,
			8,
			7,
		},
	}
	local directions = {
		-Vector3.xAxis,
		Vector3.xAxis,
		-Vector3.yAxis,
		Vector3.yAxis,
		-Vector3.zAxis,
		Vector3.zAxis,
	}
	local uv = {
		mesh:AddUV(Vector2.new(0, 1)),
		mesh:AddUV(Vector2.new(1, 1)),
		mesh:AddUV(Vector2.new(1, 0)),
		mesh:AddUV(Vector2.new(0, 0)),
	}
	for index, q in quads do
		local n = mesh:AddNormal(directions[index])
		for _, t in { { 1, 2, 3 }, { 1, 3, 4 } } do
			local face =
				mesh:AddTriangle(positions[q[t[1]]], positions[q[t[2]]], positions[q[t[3]]])
			mesh:SetFaceNormals(face, { n, n, n })
			mesh:SetFaceUVs(face, { uv[t[1]], uv[t[2]], uv[t[3]] })
		end
	end

	return mesh
end

local function loadMesh(part, restSize)
	local special = part:FindFirstChildWhichIsA("DataModelMesh")
	if part:IsA("MeshPart") then
		local mesh = MeshAccess.open(part.MeshContent)
		assert(mesh, "Roblox could not read the native mesh asset")
		if #mesh:GetBones() > 0 then
			mesh:Destroy()
			error("A skinned MeshPart requires the armature skinning preview")
		end

		return mesh, restSize / part.MeshSize, nil
	elseif special and special:IsA("SpecialMesh") and special.MeshType == Enum.MeshType.Head then
		local mesh = MeshAccess.open(Content.fromUri("rbxasset://fonts/head.mesh"))
		assert(mesh, "Roblox could not read its built-in head mesh")
		local width = math.min(restSize.X, restSize.Z)
		return mesh, Vector3.new(width, restSize.Y, width) * special.Scale * 0.8, special
	elseif
		special
		and special:IsA("FileMesh")
		and (not special:IsA("SpecialMesh") or special.MeshType == Enum.MeshType.FileMesh)
	then
		local mesh = MeshAccess.open(Content.fromUri(special.MeshId))
		assert(mesh, "Roblox could not read the native file mesh")
		return mesh, special.Scale, special
	elseif
		part:IsA("Part")
		and part.Shape == Enum.PartType.Block
		and (
			not special
			or special:IsA("BlockMesh")
			or special:IsA("SpecialMesh") and special.MeshType == Enum.MeshType.Brick
		)
	then
		return blockMesh(restSize), special and special.Scale or Vector3.one, special
	end

	error("This native geometry type cannot yet preview an affine shear: " .. part.ClassName)
end

local function register(binding, parent)
	local part = binding.part
	local rest = binding.affineRest or M.compose(part.CFrame, binding.restScale or Vector3.one)
	local state = {
		part = part,
		binding = binding,
		parent = parent,
		vertices = {},
		normals = {},
		faces = {},
		decals = {},
		special = not part:IsA("MeshPart") and part:FindFirstChildWhichIsA("DataModelMesh") or nil,
		sourceToAffine = M.mul(M.inverse(rest), M.fromCFrame(M.toCFrame(rest))),
	}
	restorePart(part)
	state.connection = part.Destroying:Connect(function()
		dispose(state)
	end)
	return state
end

local function allocate(state)
	if state.proxy or state.destroyed or state.loading then
		return state.proxy ~= nil
	end

	state.loading = true
	local part, binding = state.part, state.binding
	local ok, result = pcall(function()
		local mesh, scale, special = loadMesh(part, binding.restSize)
		state.mesh = mesh
		state.special = special
		assert(not state.destroyed, "The rigid preview was closed during asset loading")
		local offset = special and special.Offset or Vector3.zero
		local invScale = M.compose(CFrame.identity, Vector3.one / scale)
		for _, id in mesh:GetVertices() do
			local p = mesh:GetPosition(id) * scale + offset
			mesh:SetPosition(id, p)
			table.insert(state.vertices, { id = id, position = p })
		end

		for _, id in mesh:GetNormals() do
			local n = normal(invScale, mesh:GetNormal(id))
			mesh:SetNormal(id, n)
			table.insert(state.normals, { id = id, normal = n })
		end

		for _, id in mesh:GetFaces() do
			table.insert(state.faces, {
				id = id,
				vertices = mesh:GetFaceVertices(id),
				normals = mesh:GetFaceNormals(id),
				uvs = mesh:GetFaceUVs(id),
				colors = mesh:GetFaceColors(id),
			})
		end

		local neutralName = "__EclipseRigidPreview"
		local neutral =
			mesh:AddBone({ Name = neutralName, CFrame = CFrame.identity, Virtual = false })
		for _, v in state.vertices do
			mesh:SetVertexBones(v.id, { neutral })
			mesh:SetVertexBoneWeights(v.id, { 1 })
		end

		local proxy = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
		state.proxy = proxy
		state.meshSize = proxy.Size
		assert(not state.destroyed, "The rigid preview was closed during asset loading")
		proxy.Name = "_EclipseRigidSurface"
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.CanTouch = false
		proxy.CanQuery = false
		proxy.Locked = true
		mark(proxy)
		proxy:SetAttribute("EclipseArmatureRigidSurface", true)
		local bone = Instance.new("Bone")
		bone.Name = neutralName
		mark(bone)
		bone.Parent = proxy
		if part:IsA("MeshPart") then
			proxy.TextureID = part.TextureID
			proxy.DoubleSided = part.DoubleSided
		end

		if special and special:IsA("FileMesh") then
			proxy.TextureID = special.TextureId
		end

		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") then
				local copy = child:Clone()
				copy.Parent = proxy
				if child:IsA("Decal") or child:IsA("Texture") then
					table.insert(state.decals, { source = child, copy = copy })
				end
			end
		end

		return state
	end)
	state.loading = nil
	if not ok then
		dispose(state)
		return nil, tostring(result)
	end

	return result
end

local function prepare(binding, parent)
	return allocate(register(binding, parent))
end

local function reverse(values)
	return { values[1], values[3], values[2] }
end

local function proxyTransform(state, affine, nativeSize, nativeFrame)
	local world = M.mul(affine, state.sourceToAffine)
	local absoluteMesh = state.special
		and state.special:IsA("FileMesh")
		and (
			not state.special:IsA("SpecialMesh")
			or state.special.MeshType == Enum.MeshType.FileMesh
		)
	local scaling = absoluteMesh and (M.scale(world) - Vector3.one).Magnitude > 1e-6
	if
		state.special
		and state.special:IsA("SpecialMesh")
		and state.special.MeshType == Enum.MeshType.Head
	then
		local size = state.binding.restSize
		local displayed = nativeSize or state.part.Size
		local nativeWidth = math.min(displayed.X, displayed.Z) / math.min(size.X, size.Z)
		local desiredScale = M.scale(world)
		scaling = scaling
			or math.abs(desiredScale.X - nativeWidth) > 1e-6
			or math.abs(desiredScale.Z - nativeWidth) > 1e-6
	end

	if state.special and state.special.Offset.Magnitude > 1e-9 then
		local offset = state.special.Offset
		scaling = scaling
			or (M.vector(world, offset) - (nativeFrame or state.part.CFrame):VectorToWorldSpace(
					offset
				)).Magnitude
				> 1e-6
	end

	return world, scaling or requiresProxy(world)
end

function Rigid.updateBinding(state, affine, force)
	if state.destroyed or not state.part.Parent or not affine then
		return false
	end

	if nativeAvatarBody(state.part) then
		showSource(state)
		return false
	end

	local world, required = proxyTransform(state, affine)
	if not required then
		showSource(state)
		return false
	end

	assert(state.proxy, "The rigid surface must be prepared before committing an affine pose")
	local part, proxy = state.part, state.proxy
	if not state.active then
		part:SetAttribute(SAVED, part.LocalTransparencyModifier)
		for _, pair in state.decals do
			if pair.source.Parent then
				pair.source:SetAttribute(SAVED, pair.source.LocalTransparencyModifier)
			end
		end

		state.active = true
		force = true
		proxy.Parent = state.parent
	end

	proxy.Transparency = part.Transparency
	proxy.LocalTransparencyModifier = part:GetAttribute(SAVED) or 0
	proxy.Color = part.Color
	proxy.Material = state.special and Enum.Material.SmoothPlastic or part.Material
	proxy.MaterialVariant = state.special and "" or part.MaterialVariant
	proxy.Reflectance = part.Reflectance
	proxy.CastShadow = part.CastShadow
	if state.special then
		local v = state.special.VertexColor
		proxy.Color = Color3.new(part.Color.R * v.X, part.Color.G * v.Y, part.Color.B * v.Z)
	end

	part.LocalTransparencyModifier = 1
	for _, pair in state.decals do
		if pair.source.Parent then
			pair.copy.Transparency = pair.source.Transparency
			pair.copy.LocalTransparencyModifier = pair.source:GetAttribute(SAVED) or 0
			pair.source.LocalTransparencyModifier = 1
			pair.copy.Texture = pair.source.Texture
			pair.copy.Color3 = pair.source.Color3
		end
	end

	if not force and state.last and near(state.last, world) then
		return true
	end

	local frame = M.toCFrame(world)
	local localMatrix = M.mul(M.fromCFrame(frame:Inverse()), world)

	if not state.localMatrix or not near(state.localMatrix, localMatrix) then
		local inv = M.inverse(localMatrix)
		for _, v in state.vertices do
			state.mesh:SetPosition(v.id, M.point(localMatrix, v.position))
		end

		for _, v in state.normals do
			state.mesh:SetNormal(v.id, normal(inv, v.normal))
		end

		state.localMatrix = table.clone(localMatrix)
	end

	local mirrored = M.column(world, 1):Dot(M.column(world, 2):Cross(M.column(world, 3))) < 0
	if mirrored ~= state.mirrored then
		for _, face in state.faces do
			state.mesh:SetFaceVertices(
				face.id,
				mirrored and reverse(face.vertices) or face.vertices
			)
			state.mesh:SetFaceNormals(face.id, mirrored and reverse(face.normals) or face.normals)
			state.mesh:SetFaceUVs(face.id, mirrored and reverse(face.uvs) or face.uvs)
			if #face.colors == 3 then
				state.mesh:SetFaceColors(face.id, mirrored and reverse(face.colors) or face.colors)
			end
		end

		state.mirrored = mirrored
	end

	proxy.CFrame = frame
	proxy.Size = state.meshSize
	state.last = table.clone(world)
	return true
end

function Rigid.attach(entry)
	local group = { states = {}, unsupported = {}, entry = entry }
	for _, child in entry.arm:GetChildren() do
		if child:GetAttribute("EclipseArmatureRigidSurface") == true then
			child:Destroy()
		end
	end

	local seen = {}
	for _, binding in entry.bindings do
		local part = binding.part
		if part and not seen[part] then
			seen[part] = true
			table.insert(group.states, register(binding, entry.arm))
		end
	end

	return group
end

function Rigid.prepareExport(group)
	local surfaces = {}
	if not group then
		return surfaces
	end

	for _, state in group.states do
		if state.failure and MeshAccess.isDenied(state.failure) and state.binding.affineWorld then
			local _, required = proxyTransform(state, state.binding.affineWorld)
			if required then
				error(state.failure, 0)
			end
		end

		if state.proxy then
			table.insert(surfaces, state.proxy)
		end
	end

	return surfaces
end

function Rigid.preparePending(group)
	if not group or group.destroyed then
		return
	end

	for _, state in group.states do
		if nativeAvatarBody(state.part) then
			continue
		end

		local binding = state.binding
		local affine = binding.candidateAffine or binding.affineWorld
		if
			(not state.destroyed or state.failure)
			and not state.proxy
			and state.part.Parent
			and affine
		then
			local size, frame
			if binding.candidateAffine then
				local ratio = M.scale(affine) / (binding.restScale or Vector3.one)
				size = binding.restSize
					* Vector3.new(math.abs(ratio.X), math.abs(ratio.Y), math.abs(ratio.Z))
				size = Vector3.new(
					math.max(0.001, size.X),
					math.max(0.001, size.Y),
					math.max(0.001, size.Z)
				)
				frame = binding.candidateFrame or M.toCFrame(affine)
			end

			local _, required = proxyTransform(state, affine, size, frame)
			if required then
				if state.failure then
					if MeshAccess.isDenied(state.failure) then
						continue
					end

					error(state.failure, 0)
				end

				local ready, err = allocate(state)
				if group.destroyed then
					return
				end

				if not ready and err then
					state.failure = err
					table.insert(
						group.unsupported,
						{ binding = binding, error = err, reported = true }
					)
					table.insert(group.entry.diagnostics, err)
					if MeshAccess.isDenied(err) then
						continue
					end

					error(err, 0)
				end
			end
		end
	end
end

function Rigid.update(group, _nodes, force)
	if not group then
		return
	end

	for _, state in group.states do
		Rigid.updateBinding(state, state.binding.affineWorld, force)
	end

	for _, item in group.unsupported do
		if
			not item.reported
			and item.binding.affineWorld
			and requiresProxy(item.binding.affineWorld)
		then
			item.reported = true
			table.insert(group.entry.diagnostics, item.error)
			warn("[Eclipse Armature] " .. item.error)
		end
	end
end

function Rigid.cleanup(group)
	if not group then
		return
	end

	group.destroyed = true
	for _, state in group.states do
		dispose(state)
	end

	table.clear(group.states)
end

Rigid.prepare = prepare
Rigid.requiresProxy = requiresProxy
Rigid.restorePart = restorePart
return Rigid
