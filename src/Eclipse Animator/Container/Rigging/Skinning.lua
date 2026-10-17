--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local AssetService = game:GetService("AssetService")
local MeshAccess = require("MeshAccess")
local Binding = require("Binding")
local M = require("M")
local Skinning = {}
local IDENTITY = M.identity()
local SOURCE_ATTRIBUTE = "EclipseArmatureSkinOriginalMesh"
local HELPER_ATTRIBUTE = "EclipseArmatureSkinningHelper"

local function key(x, y, z)
	return x .. ":" .. y .. ":" .. z
end

local function point(a: { number }, x: number, y: number, z: number): Vector3
	return Vector3.new(
		a[1] * x + a[2] * y + a[3] * z + a[4],
		a[5] * x + a[6] * y + a[7] * z + a[8],
		a[9] * x + a[10] * y + a[11] * z + a[12]
	)
end

local function rigid(a)
	local x, y, z = M.column(a, 1), M.column(a, 2), M.column(a, 3)
	return math.abs(x:Dot(x) - 1) < 1e-5
		and math.abs(y:Dot(y) - 1) < 1e-5
		and math.abs(z:Dot(z) - 1) < 1e-5
		and math.abs(x:Dot(y)) < 1e-5
		and math.abs(x:Dot(z)) < 1e-5
		and math.abs(y:Dot(z)) < 1e-5
		and x:Dot(y:Cross(z)) > 0
end

local function uniform(a)
	local x, y, z = M.column(a, 1), M.column(a, 2), M.column(a, 3)
	local length = x:Dot(x)
	return length > 1e-12
		and math.abs(y:Dot(y) - length) < 1e-5 * length
		and math.abs(z:Dot(z) - length) < 1e-5 * length
		and math.abs(x:Dot(y)) < 1e-5 * length
		and math.abs(x:Dot(z)) < 1e-5 * length
		and math.abs(y:Dot(z)) < 1e-5 * length
		and x:Dot(y:Cross(z)) > 0
end

local function sameWeights(a, b)
	if #a ~= #b then
		return false
	end

	for i, w in a do
		if w.bone ~= b[i].bone or math.abs(w.weight - b[i].weight) > 1e-7 then
			return false
		end
	end

	return true
end

local function linearBendy(bone)
	if (bone.bbone_segments or 1) <= 1 then
		return true
	end

	local bend = bone.bbone
	if not bend then
		return false
	end

	for _, properties in { bend.bone_properties or {}, bend.pose_properties or {} } do
		for _, name in
			{
				"bbone_easein",
				"bbone_easeout",
				"bbone_curveinx",
				"bbone_curveinz",
				"bbone_curveoutx",
				"bbone_curveoutz",
				"bbone_rollin",
				"bbone_rollout",
			}
		do
			if math.abs(tonumber(properties[name]) or 0) > 1e-8 then
				return false
			end
		end

		for _, name in { "bbone_scalein", "bbone_scaleout" } do
			for _, v in properties[name] or { 1, 1, 1 } do
				if math.abs(v - 1) > 1e-8 then
					return false
				end
			end
		end
	end

	return true
end

local function unit(v: Vector3): Vector3
	return v.Magnitude > 1e-15 and v.Unit or Vector3.zero
end

local function angle(v: number): number
	return math.acos(math.clamp(v, -1, 1))
end

local function normalPoint(matrix: { number }, normal: Vector3): Vector3
	return unit(
		Vector3.new(
			matrix[1] * normal.X + matrix[5] * normal.Y + matrix[9] * normal.Z,
			matrix[2] * normal.X + matrix[6] * normal.Y + matrix[10] * normal.Z,
			matrix[3] * normal.X + matrix[7] * normal.Y + matrix[11] * normal.Z
		)
	)
end

local function prepareNormals(state, definition)
	local topology = definition.normal_topology
	if not topology then
		return
	end

	state.sourceInverse = M.inverse(M.read(definition.matrix))
	state.localToAsset = M.mul(state.assetMap, M.read(definition.matrix))
	state.normalInverse = M.inverse(M.mul(state.assetMap, M.read(definition.matrix)))
	state.polygons = {}
	state.normalGroups = {}
	local loopNormals = {}
	for _, face in definition.faces or {} do
		for offset, index in face.loops or {} do
			loopNormals[index] = face.normals[offset]
		end
	end

	for _, vertex in state.vertices do
		vertex.polygons = {}
		vertex.normalGroups = {}
		vertex.localPosition = Vector3.new(unpack(definition.vertices[vertex.index].position))
	end

	for index, indices in topology.polygons do
		local polygon =
			{ index = index, vertices = {}, vertexSet = {}, groups = {}, generation = 0 }
		for _, sourceIndex in indices do
			local v = state.vertices[sourceIndex + 1]
			table.insert(polygon.vertices, v)
			polygon.vertexSet[v] = true
			table.insert(v.polygons, polygon)
		end

		state.polygons[index] = polygon
	end

	for index, data in topology.groups do
		local v = state.vertices[data.vertex + 1]
		local group = {
			data = data,
			vertex = v,
			polygons = {},
			previous = {},
			next = {},
			normalIds = {},
			bones = {},
			generation = 0,
		}
		local restNormal = loopNormals[data.corners[1]]
		assert(restNormal, "The source export is missing an authored corner normal")
		group.bindNormal = normalPoint(state.normalInverse, Vector3.new(unpack(restNormal)))
		local included = {}
		for _, i in data.faces do
			local polygon = state.polygons[i + 1]
			table.insert(group.polygons, polygon)
			table.insert(polygon.groups, group)
			for _, neighbor in polygon.vertices do
				for _, weight in neighbor.weights do
					if not included[weight.bone] then
						included[weight.bone] = true
						table.insert(group.bones, weight.bone)
					end
				end
			end
		end

		for _, i in data.previous do
			table.insert(group.previous, state.vertices[i + 1])
		end

		for _, i in data.next do
			table.insert(group.next, state.vertices[i + 1])
		end

		table.insert(v.normalGroups, group)
		state.normalGroups[index] = group
	end

	local nativeVertices = {}
	for _, v in state.vertices do
		for _, id in v.native do
			nativeVertices[id] = v
		end
	end

	local cornerGroups, triangles = {}, {}
	for _, group in state.normalGroups do
		for _, corner in group.data.corners do
			cornerGroups[corner] = group
		end
	end

	local function triangleKey(a, b, c)
		local indices = { a, b, c }
		table.sort(indices)
		return key(indices[1], indices[2], indices[3])
	end

	for _, face in definition.faces or {} do
		local indices = face.vertices
		local signature = triangleKey(indices[1] + 1, indices[2] + 1, indices[3] + 1)
		if triangles[signature] ~= nil then
			triangles[signature] = false
		else
			local groups = {}
			for corner, index in indices do
				groups[index + 1] = cornerGroups[face.loops[corner]]
			end
			triangles[signature] = groups
		end
	end

	local claimed = {}
	for _, faceId in state.mesh:GetFaces() do
		local vertexIds = state.mesh:GetFaceVertices(faceId)
		local normalIds = state.mesh:GetFaceNormals(faceId)
		local a, b, c =
			nativeVertices[vertexIds[1]], nativeVertices[vertexIds[2]], nativeVertices[vertexIds[3]]
		local sourceFace = state.sourceFaces and state.sourceFaces[faceId]
        local triangle = triangles[triangleKey(a.index, b.index, c.index)]
        if sourceFace then
            triangle = {}
            for corner, index in sourceFace.vertices do
                triangle[index + 1] = cornerGroups[sourceFace.loops[corner]]
            end
        end
		local polygon
		if not triangle then
			for _, candidate in a.polygons do
				if candidate.vertexSet[b] and candidate.vertexSet[c] then
					assert(not polygon, "Ambiguous source polygons for a mesh normal")
					polygon = candidate
				end
			end
			assert(polygon, "The imported triangles do not match the source polygon topology")
		end
		local changed = false
		for offset, id in vertexIds do
			local vertex = nativeVertices[id]
			local group = triangle and triangle[vertex.index]
			if not group and polygon then
				for _, candidate in polygon.groups do
					if candidate.vertex == vertex then
						group = candidate
						break
					end
				end
			end

			assert(group, "A source polygon is missing its corner normal")
			local normalId = normalIds[offset]
			if claimed[normalId] and claimed[normalId] ~= group then
				normalId = group.normalIds[1] or state.mesh:AddNormal(group.bindNormal)
				normalIds[offset] = normalId
				changed = true
			end
			if not claimed[normalId] then
				table.insert(group.normalIds, normalId)
				claimed[normalId] = group
			end
		end
		if changed then
			state.mesh:SetFaceNormals(faceId, normalIds)
		end
	end

	for _, group in state.normalGroups do
		for _, id in group.normalIds do
			state.mesh:SetNormal(id, group.bindNormal)
		end
	end

	for _, v in state.vertices do
		v.affectedNormals = {}
		local affected = {}
		for _, polygon in v.polygons do
			for _, group in polygon.groups do
				if not affected[group] then
					affected[group] = true
					table.insert(v.affectedNormals, group)
				end
			end
		end

		if not v.baseCPU and #v.weights == 1 then
			local bone = v.weights[1].bone
			for _, group in v.normalGroups do
				for _, polygon in group.polygons do
					for _, neighbor in polygon.vertices do
						if #neighbor.weights ~= 1 or neighbor.weights[1].bone ~= bone then
							v.baseCPU = true
							break
						end
					end

					if v.baseCPU then
						break
					end
				end

				if v.baseCPU then
					break
				end
			end
		else
			v.baseCPU = true
		end

		if v.baseCPU and not v.cpu then
			v.cpu = true
			for _, id in v.native do
				state.mesh:SetVertexBones(id, state.cpuBones)
				state.mesh:SetVertexBoneWeights(id, state.cpuWeights)
			end
		end
	end
end

local function updateNormals(state, dirty, generation)
	if not state.polygons then
		return 0
	end

	local polygons = state.dirtyPolygons or {}
	state.dirtyPolygons = polygons
	table.clear(polygons)
	local groups = state.dirtyNormals or {}
	state.dirtyNormals = groups
	table.clear(groups)
	for _, v in dirty do
		for _, group in v.affectedNormals do
			if group.generation ~= generation then
				group.generation = generation
				table.insert(groups, group)
			end
		end
	end

	for _, group in groups do
		group.fastDelta = nil
		group.normalStable = false
		if group.vertex.cpu then
			if
				not state.morphChanged
				and group.normal
				and #group.bones > 0
				and (group.fastSteps or 0) < 16
			then
				local first = group.bones[1]
				local fast = first.deltaClass ~= nil
				if fast then
					for index = 2, #group.bones do
						local other = group.bones[index]
						if first.deltaClass ~= other.deltaClass then
							fast = false
							break
						end
					end
				end

				if fast then
					group.fastDelta = first.normalDelta
					group.normalStable = first.normalStable
				end
			end

			if not group.fastDelta then
				for _, polygon in group.polygons do
					if polygon.generation ~= generation then
						polygon.generation = generation
						table.insert(polygons, polygon)
					end
				end
			end
		end
	end

	for _, polygon in polygons do
		local x, y, z = 0, 0, 0
		local previous = polygon.vertices[#polygon.vertices].localPosition
		for _, vertex in polygon.vertices do
			local p = vertex.localPosition
			x += (previous.Y - p.Y) * (previous.Z + p.Z)
			y += (previous.Z - p.Z) * (previous.X + p.X)
			z += (previous.X - p.X) * (previous.Y + p.Y)
			previous = p
		end

		polygon.normal = unit(Vector3.new(x, y, z))
	end

	local writes, fastCount = 0, 0
	for _, group in groups do
		local vertex = group.vertex
		if vertex.cpu then
			if group.fastDelta then
				fastCount += 1
				group.fastSteps = (group.fastSteps or 0) + 1
				if group.normalStable then
					continue
				end

				group.normal = normalPoint(group.fastDelta, group.normal)
				for _, id in group.normalIds do
					state.mesh:SetNormal(id, group.normal)
					writes += 1
				end

				continue
			end

			group.fastSteps = 0
			local p: Vector3 = vertex.localPosition
			local normal = Vector3.zero
			local before: { Vector3 } = group.before or {}
			local after: { Vector3 } = group.after or {}
			group.before, group.after = before, after
			for i, polygon in group.polygons do
				before[i] = unit(group.previous[i].localPosition - p)
				after[i] = unit(group.next[i].localPosition - p)
				local faceNormal: Vector3 = polygon.normal
				normal += faceNormal * angle(before[i]:Dot(after[i]))
			end

			normal = unit(normal)
			local custom = group.data.custom
			if custom and custom[1] ~= 0 then
				local ref, other = after[1], before[#before]
				local dr, ds = ref:Dot(normal), other:Dot(normal)
				if math.abs(dr) < 0.9999 and math.abs(ds) < 0.9999 then
					local alpha
					if #before == 1 then
						alpha = (angle(dr) + angle(ds)) * 0.5
					else
						alpha = 0
						for _, v in after do
							alpha += angle(v:Dot(normal))
						end

						local count = #after
						if group.previous[#before] ~= group.next[1] then
							alpha += angle(ds)
							count += 1
						end

						alpha /= count
					end

					ref = unit(ref - normal * dr)
					local ortho = unit(normal:Cross(ref))
					other = unit(other - normal * ds)
					local dot = ref:Dot(other)
					local beta = math.pi * 2
					if dot < 0.9999 then
						beta = angle(dot)
						if ortho:Dot(other) < 0 then
							beta = math.pi * 2 - beta
						end
					end

					local af, bf = custom[1] / 32767, custom[2] / 32767
					alpha = (af > 0 and alpha or math.pi * 2 - alpha) * af
					beta = (bf > 0 and beta or math.pi * 2 - beta) * bf
					normal = normal * math.cos(alpha)
						+ ref * (math.sin(alpha) * math.cos(beta))
						+ ortho * (math.sin(alpha) * math.sin(beta))
				end
			elseif group.data.custom_vector then
				normal = Vector3.new(unpack(group.data.custom_vector))
			end

			group.normal = normalPoint(state.normalInverse, normal)
			for _, id in group.normalIds do
				state.mesh:SetNormal(id, group.normal)
				writes += 1
			end
		end
	end

	state.normalStatistics = { groups = #groups, fast = fastCount, polygons = #polygons }
	return writes
end

function Skinning.restoreOrphans(root)
	local objects = root:IsA("MeshPart") and { root }
		or require("RigTraversal").rigDescendants(root)
	local restored, failures = 0, {}
	for _, part in objects do
		local source = part:IsA("MeshPart") and part:GetAttribute(SOURCE_ATTRIBUTE)
		if type(source) == "string" and source ~= "" then
			local replacement
			local ok, err = pcall(function()
				replacement = AssetService:CreateMeshPartAsync(Content.fromUri(source))
				local size, frame, texture = part.Size, part.CFrame, part.TextureID
				part:ApplyMesh(replacement)
				part.Size, part.CFrame, part.TextureID = size, frame, texture
				part:SetAttribute(SOURCE_ATTRIBUTE, nil)
				for _, child in part:GetChildren() do
					if child:IsA("Bone") and child:GetAttribute(HELPER_ATTRIBUTE) then
						child:Destroy()
					end
				end
			end)
			if replacement then
				replacement:Destroy()
			end

			if not ok then
				local message = "Could not restore armature mesh "
					.. part.Name
					.. ": "
					.. tostring(err)
				table.insert(failures, message)
				warn("[Eclipse mesh recovery] " .. message)
			else
				restored += 1
			end
		end
	end

	return restored, failures
end

local function restorePart(state)
	if state.applied and state.part.Parent and state.original then
		local size = state.part.Size
		state.part:ApplyMesh(state.original)
		state.part.Size = size
		state.part:SetAttribute(SOURCE_ATTRIBUTE, nil)
	end

	state.applied = false
end

local function dispose(state)
	if state.destroying then
		return
	end

	state.destroying = true
	if state.connection then
		state.connection:Disconnect()
	end

	pcall(restorePart, state)
	if state.neutralBone then
		state.neutralBone:Destroy()
	end

	if state.original then
		state.original:Destroy()
	end

	if state.link then
		state.link:Destroy()
	end

	if state.mesh then
		state.mesh:Destroy()
	end
end

function Skinning.prepare(document, definition, part, options)
	options = options or {}
	local source = part:GetAttribute(SOURCE_ATTRIBUTE) or part.MeshId
	local state = {
		part = part,
		definition = definition,
		vertices = {},
		boneList = {},
		bones = {},
		generation = 0,
		diagnostics = {},
		asset = source,
		statistics = { updates = 0, vertices = 0, seconds = 0 },
	}
	local ok, result = pcall(function()
		assert(
			typeof(source) == "string" and source ~= "",
			"The skinned mesh needs a saved source mesh asset"
		)
		local modifier = definition.modifier or {}
		assert(
			not modifier.use_deform_preserve_volume,
			"Dual-quaternion skinning requires a matching deformation evaluator"
		)
		assert(
			not modifier.use_bone_envelopes,
			"Bone-envelope skinning requires exported evaluated influence weights"
		)
		state.mesh = MeshAccess.open(
			Content.fromUri(source),
			{ FixedSize = definition.normal_topology == nil and #(definition.shape_keys or {}) == 0 }
		)
		assert(state.mesh, "Studio could not allocate the armature preview mesh")
		local mesh = state.mesh
		local byName = {}
		for _, bone in document.bones do
			if bone.armature == definition.armature then
				byName[bone.name] = bone
			end
		end

		local pairs, boneIds = {}, {}
		local nativeNames = {}
		for _, id in mesh:GetBones() do
			local name = mesh:GetBoneName(id)
			local bone = byName[name]
			nativeNames[name] = true
			if bone then
				boneIds[bone.id] = id
				table.insert(
					pairs,
					{ source = Binding.matrix(bone.rest_matrix), target = mesh:GetBoneCFrame(id) }
				)
			end
		end

		local fit, scale = Binding.fit(pairs)
		local spread = 0
		for _, pair in pairs do
			spread = math.max(spread, (pair.source.Position - pairs[1].source.Position).Magnitude)
		end
		if spread < 1e-6 then
			local low, high
			local matrix = M.read(definition.matrix)
			for _, face in definition.faces do
				for _, index in face.vertices do
					local v = definition.vertices[index + 1].position
					local p = fit.Rotation * point(matrix, v[1], v[2], v[3])
					low = low and low:Min(p) or p
					high = high and high:Max(p) or p
				end
			end
			local sourceSize = low and high - low
			local targetSize = mesh:GetSize()
			if sourceSize and sourceSize.Magnitude > 1e-6 and targetSize.Magnitude > 1e-6 then
				scale = targetSize.Magnitude / sourceSize.Magnitude
				assert((sourceSize * scale - targetSize).Magnitude <= math.max(.001, targetSize.Magnitude * .025), "The imported mesh proportions do not match this Blender export")
				fit = CFrame.new(pairs[1].target.Position - fit.Rotation * (pairs[1].source.Position * scale)) * fit.Rotation
			end
		end
		state.assetMap = M.compose(fit, Vector3.one * scale)
		state.assetInverse = M.inverse(state.assetMap)

		local neutralName = "__EclipseCPUPreview"
		local suffix = 1
		while nativeNames[neutralName] or part:FindFirstChild(neutralName) do
			neutralName = "__EclipseCPUPreview" .. suffix
			suffix += 1
		end

		state.neutralName = neutralName
		state.cpuBones =
			{ mesh:AddBone({ Name = neutralName, CFrame = CFrame.identity, Virtual = false }) }
		state.cpuWeights = { 1 }
		local tolerance = math.max(0.0001, mesh:GetSize().Magnitude * 1e-5)
		local squared = tolerance * tolerance
		local spatial = {}
		local mw = M.read(definition.matrix)
		state.shapeKeys = {}
		for _, key in definition.shape_keys or {} do
			local shape = { data = key, previous = nil, deltas = {} }
			for _, delta in key.deltas or {} do
				assert(definition.vertices[delta[1] + 1], "Invalid shape key vertex")
				shape.deltas[delta[1] + 1] = M.vector(mw, Vector3.new(delta[2], delta[3], delta[4]))
			end

			table.insert(state.shapeKeys, shape)
		end

		if #state.shapeKeys > 0 then
			for _, vertex in definition.vertices do
				for _, weight in vertex.weights or {} do
					local bone = byName[weight.bone:sub(#definition.armature + 3)]
					if bone and not linearBendy(bone) then
						state.nativeMorph = true
					end
				end
			end
		end

		for index, vertex in definition.vertices do
			local p = point(mw, vertex.position[1], vertex.position[2], vertex.position[3])
			local assetPoint = M.point(state.assetMap, p)
			local v = {
				index = index,
				x = p.X,
				y = p.Y,
				z = p.Z,
				rest = assetPoint,
				weights = {},
				native = {},
				generation = 0,
			}
			local total = 0
			for _, weight in vertex.weights or {} do
				total += weight.weight
			end

			for _, weight in vertex.weights or {} do
				local bone = state.bones[weight.bone]
				if not bone then
					local name = weight.bone:sub(#definition.armature + 3)
					local data = byName[name]
					assert(
						data,
						"The imported mesh is missing weighted bone " .. name
					)
					assert(
						state.nativeMorph or linearBendy(data),
						"Curved B-Bone skinning requires evaluated segment transforms: " .. name
					)
					assert(not state.nativeMorph or boneIds[weight.bone], "Curved B-Bone morphing requires the imported weighted bone " .. name)
					bone = {
						id = weight.bone,
						native = boneIds[weight.bone] or state.cpuBones[1],
                        missingNative = boneIds[weight.bone] == nil,
						inverse = M.inverse(M.read(data.rest_matrix)),
						vertices = {},
						nonRigid = false,
					}
					state.bones[bone.id] = bone
					table.insert(state.boneList, bone)
				end

				table.insert(v.weights, { bone = bone, weight = weight.weight / total })
				table.insert(bone.vertices, v)
			end

			v.baseCPU = #v.weights > 4 or #state.shapeKeys > 0
            for _, weight in v.weights do
                if weight.bone.missingNative then v.baseCPU = true end
            end
			state.vertices[index] = v
			local hash = key(
				math.floor(assetPoint.X / tolerance),
				math.floor(assetPoint.Y / tolerance),
				math.floor(assetPoint.Z / tolerance)
			)
			spatial[hash] = spatial[hash] or {}
			table.insert(spatial[hash], v)
		end

		if definition.normal_topology or #state.shapeKeys > 0 then
            state.sourceFaces = {}
			local uvTransforms = {}
			local encodedUVs = part:GetAttribute("EclipseArmatureUVTransforms")
			if typeof(encodedUVs) == "string" then
				local ok, decoded = pcall(
					game:GetService("HttpService").JSONDecode,
					game:GetService("HttpService"),
					encodedUVs
				)
				if ok and typeof(decoded) == "table" then
					uvTransforms = decoded
				end
			end

			for _, id in mesh:GetFaces() do
				mesh:RemoveFace(id)
			end

			mesh:RemoveUnused()

			local renderedVertices = {}
			for _, face in definition.faces do
				for _, index in face.vertices do
					renderedVertices[index + 1] = true
				end
			end

			for _, v in state.vertices do
				if not renderedVertices[v.index] then
					continue
				end

				v.native[1] = mesh:AddVertex(v.rest)
				if state.nativeMorph then
					local weights = table.clone(v.weights)
					table.sort(weights, function(a, b)
						return a.weight > b.weight
					end)
					local ids, values, total = {}, {}, 0
					for i = 1, math.min(4, #weights) do
						ids[i], values[i] = weights[i].bone.native, weights[i].weight
						total += values[i]
					end

					for i in values do
						values[i] /= total
					end

					mesh:SetVertexBones(v.native[1], ids)
					mesh:SetVertexBoneWeights(v.native[1], values)
				end
			end

			for _, face in definition.faces do
				local ids, normals, uvs = {}, {}, {}
				for corner, index in face.vertices do
					ids[corner] = state.vertices[index + 1].native[1]
					local n = face.normals[corner]
					normals[corner] = mesh:AddNormal(Vector3.new(n[1], n[2], n[3]))
					local uv = face.uvs and face.uvs[corner] or { 0, 0 }
					local value = Vector2.new(uv[1], 1 - uv[2])
					local material = definition.materials
						and definition.materials[(face.material_index or 0) + 1]
					local transform = material and uvTransforms[material]
					if typeof(transform) == "table" and #transform == 4 then
						value = value * Vector2.new(transform[1], transform[2])
							+ Vector2.new(transform[3], transform[4])
					end

					uvs[corner] = mesh:AddUV(value)
				end

				local id = mesh:AddTriangle(ids[1], ids[2], ids[3])
                state.sourceFaces[id] = face
				mesh:SetFaceNormals(id, normals)
				mesh:SetFaceUVs(id, uvs)
			end
		else
			for _, id in mesh:GetVertices() do
				local p = mesh:GetPosition(id)
				local x, y, z =
					math.floor(p.X / tolerance),
					math.floor(p.Y / tolerance),
					math.floor(p.Z / tolerance)
				local best, distance
				for dx = -1, 1 do
					for dy = -1, 1 do
						for dz = -1, 1 do
							for _, candidate in spatial[key(x + dx, y + dy, z + dz)] or {} do
								local delta = (candidate.rest - p):Dot(candidate.rest - p)
								if delta <= squared and (not distance or delta < distance) then
									if
										best
										and math.abs(delta - distance) < 1e-12
										and not sameWeights(
											definition.vertices[best.index].weights,
											definition.vertices[candidate.index].weights
										)
									then
										error(
											"Coincident source vertices have different weights; an unambiguous mesh mapping is required"
										)
									end

									best, distance = candidate, delta
								end
							end
						end
					end
				end

				assert(best, "The mesh vertices do not match this Blender export")
				table.insert(best.native, id)
			end
		end

		for _, v in state.vertices do
			v.gpuBones, v.gpuWeights = {}, {}
			for i, w in v.weights do
				v.gpuBones[i], v.gpuWeights[i] = w.bone.native, w.weight
			end

			v.cpu = v.baseCPU
			for _, id in v.native do
				mesh:SetPosition(id, v.rest)
				if not state.nativeMorph then
					mesh:SetVertexBones(id, v.cpu and state.cpuBones or v.gpuBones)
				end

				if not state.nativeMorph then
					mesh:SetVertexBoneWeights(id, v.cpu and state.cpuWeights or v.gpuWeights)
				end
			end

			if not v.cpu and #v.native > 0 then
				local stored = mesh:GetVertexBoneWeights(v.native[1])
				local total = 0
				for _, w in stored do
					total += w
				end

				for index, weight in v.gpuWeights do
					if math.abs((stored[index] or 0) / math.max(total, 1e-12) - weight) > 1e-7 then
						v.baseCPU = true
						break
					end
				end

				if v.baseCPU then
					v.cpu = true
					for _, id in v.native do
						mesh:SetVertexBones(id, state.cpuBones)
						mesh:SetVertexBoneWeights(id, state.cpuWeights)
					end
				end
			end
		end

		prepareNormals(state, definition)
		if not options.detached then
			if part:GetAttribute(SOURCE_ATTRIBUTE) then
				state.original = AssetService:CreateMeshPartAsync(Content.fromUri(source))
				state.original.TextureID = part.TextureID
			else
				state.original = Instance.new("MeshPart")
				state.original:ApplyMesh(part)
			end

			state.link = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = part.RenderFidelity,
			})
			state.link.TextureID = part.TextureID
			local size = part.Size
			part:SetAttribute(SOURCE_ATTRIBUTE, source)
			part:ApplyMesh(state.link)
			part.Size = size
			state.applied = true
			for _, child in part:GetChildren() do
				if child:IsA("Bone") and child:GetAttribute(HELPER_ATTRIBUTE) == true then
					child:Destroy()
				end
			end

			local neutral = Instance.new("Bone")
			neutral.Name = neutralName
			neutral.CFrame = CFrame.identity
			neutral.Transform = CFrame.identity
			neutral:SetAttribute(HELPER_ATTRIBUTE, true)
			neutral.Parent = part
			state.neutralBone = neutral
			state.connection = part.Destroying:Connect(function()
				dispose(state)
			end)
		end

		return state
	end)
	if not ok then
		dispose(state)
		return nil, tostring(definition.object or part.Name) .. ": " .. tostring(result)
	end

	return result
end

function Skinning.updateMesh(state, nodes, force, shapeValues)
	if state.destroying then
		return 0
	end

	local started = os.clock()
	state.generation += 1
	local generation = state.generation
	local dirty = state.dirty or {}
	state.dirty = dirty
	table.clear(dirty)
	state.morphChanged = false
	for _, shape in state.shapeKeys or {} do
		local key = shapeValues and shapeValues[shape.data.name] or shape.data
		local value = key.mute and 0
			or math.clamp(tonumber(key.value) or 0, key.min or 0, key.max or 1)
		if force or shape.previous ~= value then
			shape.previous = value
			state.morphChanged = true
			for index in shape.deltas do
				local v = state.vertices[index]
				if v.generation ~= generation then
					v.generation = generation
					table.insert(dirty, v)
				end
			end
		end
	end

	if state.nativeMorph then
		local updates = 0
		for _, v in dirty do
			local source = Vector3.new(v.x, v.y, v.z)
			for _, shape in state.shapeKeys do
				local delta = shape.deltas[v.index]
				if delta then
					source += delta * (shape.previous or 0)
				end
			end

			v.localPosition = M.point(state.sourceInverse, source)
			local position = M.point(state.assetMap, source)
			for _, id in v.native do
				state.mesh:SetPosition(id, position)
				updates += 1
			end
		end

		local normals = updateNormals(state, dirty, generation)
		local elapsed = os.clock() - started
		state.statistics = {
			updates = state.statistics.updates + 1,
			vertices = updates,
			normals = normals,
			seconds = elapsed,
		}
		return updates, elapsed
	end

	for _, bone in state.boneList do
		local node = nodes[bone.id]
		local world = node and (node.world or node)
		if world and (force or not bone.previous or M.error(world, bone.previous) > 1e-8) then
			local previous = bone.previous
			bone.delta = previous and M.mul(world, M.inverse(previous)) or nil
			bone.deltaUniform = bone.delta and uniform(bone.delta)
			bone.normalDelta = bone.deltaUniform
					and M.inverse(M.mul(state.assetMap, M.mul(bone.delta, state.assetInverse)))
				or nil
			local a = bone.normalDelta
			bone.normalStable = a
				and a[1] > 0
				and math.abs(a[1] - a[6]) < 1e-7
				and math.abs(a[1] - a[11]) < 1e-7
				and math.abs(a[2])
						+ math.abs(a[3])
						+ math.abs(a[5])
						+ math.abs(a[7])
						+ math.abs(a[9])
						+ math.abs(a[10])
					< 1e-7
			bone.previous = table.clone(world)
			local transform = M.mul(world, bone.inverse)
			bone.nonRigid = not rigid(transform)
			bone.matrix = M.mul(state.sourceInverse or state.assetMap, transform)
			for _, v in bone.vertices do
				if v.generation ~= generation then
					v.generation = generation
					table.insert(dirty, v)
				end
			end
		else
			bone.delta = IDENTITY
			bone.deltaUniform = true
			bone.normalDelta = IDENTITY
			bone.normalStable = true
		end
	end

	local classes = state.deltaClasses or {}
	state.deltaClasses = classes
	table.clear(classes)
	for _, bone in state.boneList do
		bone.deltaClass = nil
		if bone.deltaUniform then
			for index, other in classes do
				if M.error(bone.delta, other.delta) <= 1e-6 then
					bone.deltaClass = index
					break
				end
			end

			if not bone.deltaClass then
				table.insert(classes, bone)
				bone.deltaClass = #classes
			end
		end
	end

	local updates = 0
	for _, v in dirty do
		local cpu = v.baseCPU
		if not cpu then
			for _, w in v.weights do
				if w.bone.nonRigid then
					cpu = true
					break
				end
			end
		end

		if cpu ~= v.cpu then
			v.cpu = cpu
			for _, group in v.normalGroups or {} do
				group.normal = nil
				group.fastSteps = 0
				if not cpu then
					for _, id in group.normalIds do
						state.mesh:SetNormal(id, group.bindNormal)
					end
				end
			end

			for _, id in v.native do
				state.mesh:SetVertexBones(id, cpu and state.cpuBones or v.gpuBones)
				state.mesh:SetVertexBoneWeights(id, cpu and state.cpuWeights or v.gpuWeights)
				if not cpu then
					state.mesh:SetPosition(id, v.rest)
				end
			end
		end

		if cpu or state.polygons then
			local source = Vector3.new(v.x, v.y, v.z)
			for _, shape in state.shapeKeys or {} do
				local delta = shape.deltas[v.index]
				if delta then
					source += delta * (shape.previous or 0)
				end
			end

			local sx, sy, sz = source.X, source.Y, source.Z
			local x, y, z = 0, 0, 0
			if #v.weights == 0 then
				local p = M.point(state.sourceInverse or state.assetMap, source)
				x, y, z = p.X, p.Y, p.Z
			end

			for _, w in v.weights do
				local a = w.bone.matrix
				local weight = w.weight
				x += (a[1] * sx + a[2] * sy + a[3] * sz + a[4]) * weight
				y += (a[5] * sx + a[6] * sy + a[7] * sz + a[8]) * weight
				z += (a[9] * sx + a[10] * sy + a[11] * sz + a[12]) * weight
			end

			local position = Vector3.new(x, y, z)
			if state.polygons then
				v.localPosition = position
				position = point(state.localToAsset, x, y, z)
			end

			if cpu then
				for _, id in v.native do
					state.mesh:SetPosition(id, position)
					updates += 1
				end
			end
		end
	end

	local normalUpdates = updateNormals(state, dirty, generation)
	local elapsed = os.clock() - started
	state.statistics = {
		updates = state.statistics.updates + 1,
		vertices = updates,
		normals = normalUpdates,
		seconds = elapsed,
	}
	return updates, elapsed
end

function Skinning.attach(entry, options)
	local group = { meshes = {}, diagnostics = {} }
	if #(entry.data.skin_meshes or {}) == 0 then
		return group
	end

	local counts = {}
	local partsByName = {}
	for _, part in entry.rig:GetDescendants() do
		if part:IsA("MeshPart") then
			local matches = partsByName[part.Name] or {}
			partsByName[part.Name] = matches
			table.insert(matches, part)
		end
	end

	for _, definition in entry.data.skin_meshes or {} do
		counts[definition.object] = (counts[definition.object] or 0) + 1
	end

	for _, definition in entry.data.skin_meshes or {} do
		if counts[definition.object] > 1 then
			table.insert(
				group.diagnostics,
				"Multiple armature modifiers on "
					.. definition.object
					.. " require ordered deformation composition"
			)
			continue
		end

		local matches = partsByName[definition.object] or {}
		if #matches == 1 then
			local mesh, issue = Skinning.prepare(entry.data, definition, matches[1], options)
			if mesh then
				table.insert(group.meshes, mesh)
			else
				table.insert(group.diagnostics, issue)
			end
		elseif #matches > 1 then
			table.insert(group.diagnostics, "More than one mesh matches " .. definition.object)
		end
	end

	return group
end

function Skinning.update(group, nodes, force, shapeValues)
	if not group then
		return
	end

	for _, mesh in group.meshes do
		Skinning.updateMesh(mesh, nodes, force, shapeValues and shapeValues[mesh.definition.object])
	end
end

function Skinning.cleanup(group)
	if not group then
		return
	end

	for _, mesh in group.meshes do
		dispose(mesh)
	end

	table.clear(group.meshes)
end

Skinning.dispose = dispose
Skinning.linearBendy = linearBendy
return Skinning
