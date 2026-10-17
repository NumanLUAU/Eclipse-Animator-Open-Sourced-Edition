--!nocheck
--// cracked by numan

return function(require)
	local Service = game:GetService("AssetService")
	local Geometry = {}
	local function remap(map, values)
		local out = {}
		for _, id in values do
			assert(map[id], "Mesh topology changed after export")
			table.insert(out, map[id])
		end
		return out
	end
	function Geometry.create(part, data)
		local mesh = Service:CreateEditableMesh()
		assert(
			mesh,
			"Editable mesh allocation failed. Enable Mesh & Image APIs for the experience and check device memory."
		)
		local state = {
			mesh = mesh,
			vertices = {},
			normals = {},
			uvs = {},
			colors = {},
			bones = {},
			faces = {},
		}
		local ok, message = xpcall(function()
			for id, v in data.Vertices do
				state.vertices[id] = mesh:AddVertex(v)
			end
			for id, v in data.Normals do
				state.normals[id] = mesh:AddNormal(v)
			end
			for id, v in data.UVs do
				state.uvs[id] = mesh:AddUV(v)
			end
			for id, v in data.Colors do
				state.colors[id] = mesh:AddColor(v[1], v[2])
			end
			for id, v in data.Bones do
				state.bones[id] =
					mesh:AddBone({ Name = v.Name, CFrame = v.CFrame, Virtual = v.Virtual })
			end
			for id, v in data.Bones do
				if state.bones[v.Parent] then
					mesh:SetBoneParent(state.bones[id], state.bones[v.Parent])
				end
			end
			for id, v in data.Weights do
				mesh:SetVertexBones(state.vertices[id], remap(state.bones, v[1]))
				mesh:SetVertexBoneWeights(state.vertices[id], v[2])
			end
			for id, v in data.Faces do
				local vertices = remap(state.vertices, v[1])
				assert(#vertices == 3, "The exported mesh must be triangulated")
				local face = mesh:AddTriangle(table.unpack(vertices))
				state.faces[id] = face
				if #v[2] > 0 then
					mesh:SetFaceNormals(face, remap(state.normals, v[2]))
				end
				if #v[3] > 0 then
					mesh:SetFaceUVs(face, remap(state.uvs, v[3]))
				end
				if #v[4] > 0 then
					mesh:SetFaceColors(face, remap(state.colors, v[4]))
				end
			end
			local link = Service:CreateMeshPartAsync(
				Content.fromObject(mesh),
				{
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = part.RenderFidelity,
				}
			)
			local size, texture = part.Size, part.TextureID
			part:ApplyMesh(link)
			part.Size = size
			part.TextureID = texture
			link:Destroy()
		end, debug.traceback)
		if not ok then
			mesh:Destroy()
			error(message, 2)
		end
		return state
	end
	function Geometry.apply(state, key, value)
		local kind, text = key:match("^([^:]+):(.+)$")
		local id = tonumber(text)
		local mesh = state.mesh
		if kind == "Position" then
			mesh:SetPosition(state.vertices[id], value)
		elseif kind == "Normal" then
			mesh:SetNormal(
				state.normals[id],
				value.Magnitude > 1e-10 and value.Unit or Vector3.yAxis
			)
		elseif kind == "UV" then
			mesh:SetUV(state.uvs[id], value)
		elseif kind == "Color" then
			mesh:SetColor(state.colors[id], value[1])
			mesh:SetColorAlpha(state.colors[id], value[2])
		elseif kind == "Bone" then
			mesh:SetBoneCFrame(state.bones[id], value)
		elseif kind == "Weights" then
			mesh:SetVertexBones(state.vertices[id], remap(state.bones, value[1]))
			mesh:SetVertexBoneWeights(state.vertices[id], value[2])
		elseif kind == "Face" then
			local face = state.faces[id]
			mesh:SetFaceVertices(face, remap(state.vertices, value[1]))
			if #value[2] > 0 then
				mesh:SetFaceNormals(face, remap(state.normals, value[2]))
			end
			if #value[3] > 0 then
				mesh:SetFaceUVs(face, remap(state.uvs, value[3]))
			end
			if #value[4] > 0 then
				mesh:SetFaceColors(face, remap(state.colors, value[4]))
			end
		else
			error("Unknown geometry field " .. key)
		end
	end
	return Geometry
end
