--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preferences = require("Preferences")
local AssetService = game:GetService("AssetService")
local Matrix = require("M")
local Geometry = {}
local meshes = setmetatable({}, { __mode = "k" })
local wires = setmetatable({}, { __mode = "k" })
local invalid = setmetatable({}, { __mode = "k" })
local writer = game:GetService("HttpService"):GenerateGUID(false)
local serial = 0

local function watchWires(anchor, state)
	state.connections = {}
	table.insert(
		state.connections,
		anchor.Destroying:Once(function()
			for _, connection in state.connections do
				connection:Disconnect()
			end

			if wires[anchor] == state then
				wires[anchor], invalid[anchor] = nil, nil
			end
		end)
	)
	for _, name in { "XRayEdges", "XRayEdgesSelect" } do
		local wire = anchor:FindFirstChild(name)
		if wire then
			local function changed()
				if wires[anchor] ~= state or state.writing then
					return
				end

				local expected = state.expected
				if
					expected
					and (
						wire.Scale ~= expected.scale
						or wire.CFrame ~= expected.frame
						or wire:GetAttribute("EclipseGeometryWriter") ~= expected.stamp
					)
				then
					invalid[anchor] = true
				end
			end

			for _, property in { "Scale", "CFrame" } do
				table.insert(
					state.connections,
					wire:GetPropertyChangedSignal(property):Connect(changed)
				)
			end

			table.insert(
				state.connections,
				wire:GetAttributeChangedSignal("EclipseGeometryWriter"):Connect(changed)
			)
		end
	end
end

local function releaseWires(anchor)
	local state = wires[anchor]
	for _, connection in state and state.connections or {} do
		connection:Disconnect()
	end

	wires[anchor], invalid[anchor] = nil, nil
end

function Geometry.repair(arm)
	local repaired = false
	for anchor in invalid do
		if not anchor.Parent then
			releaseWires(anchor)
		elseif anchor.Parent == arm then
			local state = wires[anchor]
			if state and state.shape then
				Geometry.update(anchor, state.shape)
				repaired = true
			else
				invalid[anchor] = nil
			end
		end
	end

	return repaired
end

local solidKinds = setmetatable({}, { __mode = "k" })

function Geometry.isSolid(bone)
	if bone.solid ~= true then
		return false
	end

	local vertices = bone.display and bone.display.vertices
	if not vertices then
		return true
	end

	if solidKinds[vertices] ~= nil then
		return solidKinds[vertices]
	end

	local points = {}
	local origin = vertices[1] and Vector3.new(unpack(vertices[1])) or Vector3.zero
	local axis = Vector3.zero
	local magnitude = 0
	for _, v in vertices do
		magnitude = math.max(magnitude, math.abs(v[1]), math.abs(v[2]), math.abs(v[3]))
		local p = Vector3.new(unpack(v)) - origin
		table.insert(points, p)
		if p.Magnitude > axis.Magnitude then
			axis = p
		end
	end

	local extent = axis.Magnitude
	local normal = Vector3.zero
	for _, p in points do
		local n = axis:Cross(p)
		if n.Magnitude > normal.Magnitude then
			normal = n
		end
	end

	local solid = false
	if normal.Magnitude > extent * extent * 1e-7 then
		normal = normal.Unit
		local tolerance = math.max(extent * 1e-6, magnitude * 2 ^ -22)
		for _, p in points do
			if math.abs(normal:Dot(p)) > tolerance then
				solid = true
				break
			end
		end
	end

	solidKinds[vertices] = solid
	return solid
end

function Geometry.setLines(anchor, points)
	releaseWires(anchor)
	local minimum, maximum
	for _, point in points do
		minimum = minimum and minimum:Min(point) or point
		maximum = maximum and maximum:Max(point) or point
	end

	wires[anchor] = {
		points = points,
		originalPoints = true,
		boundsCenter = minimum and (minimum + maximum) * 0.5,
		boundsHalfSize = minimum and (maximum - minimum) * 0.5,
	}
	serial += 1
	local state = wires[anchor]
	state.expected =
		{ scale = Vector3.one, frame = CFrame.identity, stamp = writer .. ":" .. serial }
	watchWires(anchor, state)
	state.writing = true
	for _, name in { "XRayEdges", "XRayEdgesSelect" } do
		local wire = anchor:FindFirstChild(name)
		if wire then
			wire:SetAttribute("EclipseGeometryWriter", state.expected.stamp)
			wire.Scale = Vector3.one
			wire.CFrame = CFrame.identity
			wire:Clear()
			wire:AddLines(points)
		end
	end

	state.writing = false
end

function Geometry.has(anchor)
	return meshes[anchor] ~= nil or (anchor:GetAttribute("Solid") ~= true and wires[anchor] ~= nil)
end

function Geometry.clear(anchor)
	local mesh = meshes[anchor]
	if mesh then
		if mesh.connection then
			mesh.connection:Disconnect()
		end

		if mesh.mesh then
			mesh.mesh:Destroy()
		end

		meshes[anchor] = nil
	end

	local solid = anchor:FindFirstChild("EclipseSolidShape")
	if solid then
		solid:Destroy()
	end
end

function Geometry.releaseArm(arm)
	for _, anchor in arm:GetChildren() do
		if anchor:IsA("BasePart") then
			Geometry.clear(anchor)
			releaseWires(anchor)
			for _, name in { "XRayEdges", "XRayEdgesSelect" } do
				local wire = anchor:FindFirstChild(name)
				if wire then
					wire:Clear()
				end
			end
		end
	end
end

local function materialize(anchor, state, visible)
	if state.mesh or state.loading then
		return anchor:FindFirstChild("EclipseSolidShape")
	end

	state.loading = true
	local mesh, part
	local ok, result = pcall(function()
		mesh = AssetService:CreateEditableMesh()
		assert(mesh, "Not enough editable mesh memory for armature shapes")
		local ids = {}
		for i, point in state.points do
			ids[i] = mesh:AddVertex(point - state.center)
		end

		for _, tri in state.indices do
			mesh:AddTriangle(ids[tri[1]], ids[tri[2]], ids[tri[3]])
		end

		part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))

		if meshes[anchor] ~= state then
			part:Destroy()
			mesh:Destroy()
			return nil
		end

		part.Name = "EclipseSolidShape"
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow =
			true, false, false, false, false
		part.DoubleSided = true
		part.Color = anchor:GetAttribute(
			anchor:GetAttribute("EclipseArmatureSelected") and "SelectColor" or "BoneColor"
		) or Color3.new(0.5, 0.5, 0.5)
		if state.wantVisible ~= nil then
			visible = state.wantVisible
			state.wantVisible = nil
		end

		visible = visible
			and require("Organization").isBoneVisible(anchor)
			and not require("Organization").usesPartWidget(anchor)
		part.Material, part.Transparency =
			Enum.Material.SmoothPlastic,
			visible and (Preferences.get("ArmatureBoneTransparency") or 65) / 100 or 1
		part.CFrame = anchor.CFrame * CFrame.new(state.center)
		part:SetAttribute("EclipseVisualOffset", CFrame.new(state.center))
		part:SetAttribute("EclipseGeneratedVisual", true)
		state.mesh, state.ids, state.baseSize = mesh, ids, part.Size
		state.indices = nil
		state.originalVertices = true
		part.Parent = anchor
		if state.pendingShape then
			local shape = state.pendingShape
			state.pendingShape = nil
			task.defer(function()
				if meshes[anchor] == state and anchor.Parent then
					pcall(Geometry.update, anchor, shape)
				end
			end)
		end

		return part
	end)
	state.loading = nil
	if not ok then
		if part then
			part:Destroy()
		end

		if mesh then
			mesh:Destroy()
		end

		error(result)
	end

	return result
end

local queue, draining = {}, false

local function materializeLater(anchor, state, visible)
	if
		not state.mesh
		and not state.loading
		and not state.queued
		and not (state.retryAt and os.clock() < state.retryAt)
	then
		state.queued = true
		table.insert(queue, { anchor = anchor, state = state, visible = visible })
		if not draining then
			draining = true
			task.spawn(function()
				while #queue > 0 do
					local job = table.remove(queue, 1)
					job.state.queued = nil
					if
						meshes[job.anchor] == job.state
						and not job.state.mesh
						and job.anchor.Parent
					then
						local ok, err = pcall(materialize, job.anchor, job.state, job.visible)
						if not ok then
							job.state.retryAt = os.clock() + 5
							warn("Eclipse armature shape: " .. tostring(err))
						end
					end
				end

				draining = false
			end)
		end
	end

	return anchor:FindFirstChild("EclipseSolidShape")
end

function Geometry.prepareVisible(anchor)
	local state = meshes[anchor]
	if state and not state.mesh then
		return materializeLater(anchor, state)
	end

	return anchor:FindFirstChild("EclipseSolidShape")
end

function Geometry.solid(anchor, triangles, transform, rawLocal)
	Geometry.clear(anchor)
	if #triangles == 0 then
		return
	end

	local points, indices, keys, edges = {}, {}, {}, {}
	local minimum, maximum

	local function vertex(raw)
		local point = Vector3.new(raw[1], raw[2], raw[3])
		if not rawLocal then
			point = anchor.CFrame:PointToObjectSpace(transform(point))
		end

		local key = string.format("%.8g,%.8g,%.8g", point.X, point.Y, point.Z)
		if keys[key] then
			return keys[key]
		end

		local id = #points + 1
		points[id], keys[key] = point, id
		minimum = minimum and minimum:Min(point) or point
		maximum = maximum and maximum:Max(point) or point
		return id
	end

	for _, triangle in triangles do
		local a, b, c = vertex(triangle[1]), vertex(triangle[2]), vertex(triangle[3])
		if (points[b] - points[a]):Cross(points[c] - points[a]).Magnitude > 1e-10 then
			table.insert(indices, { a, b, c })
			for _, edge in { { a, b }, { b, c }, { c, a } } do
				local lo, hi = math.min(edge[1], edge[2]), math.max(edge[1], edge[2])
				edges[tostring(lo) .. ":" .. tostring(hi)] = { lo, hi }
			end
		end
	end

	local lines = wires[anchor] and table.clone(wires[anchor].points) or {}
	if #lines == 0 then
		for _, edge in edges do
			table.insert(lines, points[edge[1]])
			table.insert(lines, points[edge[2]])
		end
	end

	Geometry.setLines(anchor, lines)
	if #indices == 0 then
		return
	end

	local center = (minimum + maximum) * 0.5
	local state = { points = points, indices = indices, center = center }
	meshes[anchor] = state
	state.connection = anchor.Destroying:Once(function()
		if meshes[anchor] == state then
			meshes[anchor] = nil
			if state.mesh then
				state.mesh:Destroy()
			end
		end

		releaseWires(anchor)
	end)

	if not anchor:GetAttribute("Hidden") then
		return materializeLater(anchor, state, true)
	end
end

local function changed(previous, current)
	if not previous then
		return true
	end

	for i = 1, 12 do
		if math.abs(previous[i] - current[i]) > 1e-6 then
			return true
		end
	end

	return false
end

local function diagonalScale(shape)
	for _, index in { 2, 3, 5, 7, 9, 10 } do
		if math.abs(shape[index]) > 1e-7 then
			return nil
		end
	end

	return Vector3.new(shape[1], shape[6], shape[11])
end

local function nativeScale(shape, baseSize)
	local scale = diagonalScale(shape)
	if not scale then
		return nil
	end

	local size = baseSize * scale
	if math.min(size.X, size.Y, size.Z) < 0.001 then
		return nil
	end

	return size
end

function Geometry.update(anchor, shape)
	local solid = anchor:FindFirstChild("EclipseSolidShape")
	local state = meshes[anchor]
	if state and shape then
		state.pendingShape = not state.mesh and table.clone(shape) or nil
	end

	if solid then
		local center = state and state.center or solid:GetAttribute("EclipseVisualOffset").Position
		solid.CFrame = anchor.CFrame * CFrame.new(shape and Matrix.point(shape, center) or center)
		if state and shape and changed(state.shape, shape) then
			local size = nativeScale(shape, state.baseSize)
			if size then
				if not state.originalVertices then
					for i, point in state.points do
						state.mesh:SetPosition(state.ids[i], point - state.center)
					end
				end

				solid.Size = size
				state.originalVertices = true
			else
				solid.Size = state.baseSize
				for i, point in state.points do
					state.mesh:SetPosition(state.ids[i], Matrix.vector(shape, point - state.center))
				end

				state.originalVertices = false
			end

			state.shape = table.clone(shape)
		end
	end

	local wireState = wires[anchor]
	if shape and wireState and (invalid[anchor] or changed(wireState.shape, shape)) then
		if invalid[anchor] then
			wireState.originalPoints = false
		end

		invalid[anchor] = nil
		wireState.writing = true
		if not anchor:GetAttribute("EclipseArmatureRawDisplay") and wireState.boundsCenter then
			local center = Matrix.point(shape, wireState.boundsCenter)
			local half = wireState.boundsHalfSize
			local x, y, z =
				Matrix.column(shape, 1), Matrix.column(shape, 2), Matrix.column(shape, 3)
			local extent = Vector3.new(
				math.abs(x.X) * half.X + math.abs(y.X) * half.Y + math.abs(z.X) * half.Z,
				math.abs(x.Y) * half.X + math.abs(y.Y) * half.Y + math.abs(z.Y) * half.Z,
				math.abs(x.Z) * half.X + math.abs(y.Z) * half.Y + math.abs(z.Z) * half.Z
			)
			local size = (
				Vector3.new(math.abs(center.X), math.abs(center.Y), math.abs(center.Z)) + extent
			) * 2
			anchor.Size =
				Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
		end

		serial += 1
		local scale = diagonalScale(shape)
		local native = scale and math.min(scale.X, scale.Y, scale.Z) > 0
		wireState.expected = {
			scale = native and scale or Vector3.one,
			frame = native and CFrame.new(Matrix.position(shape)) or CFrame.identity,
			stamp = writer .. ":" .. serial,
		}
		for _, name in { "XRayEdges", "XRayEdgesSelect" } do
			local wire = anchor:FindFirstChild(name)
			if wire then
				wire:SetAttribute("EclipseGeometryWriter", wireState.expected.stamp)
			end
		end

		if scale and math.min(scale.X, scale.Y, scale.Z) > 0 then
			local frame = CFrame.new(Matrix.position(shape))
			for _, name in { "XRayEdges", "XRayEdgesSelect" } do
				local wire = anchor:FindFirstChild(name)
				if wire then
					if not wireState.originalPoints then
						wire:Clear()
						wire:AddLines(wireState.points)
					end

					wire.Scale = scale
					wire.CFrame = frame
				end
			end

			wireState.originalPoints = true
		else
			local points = table.create(#wireState.points)
			for i, point in wireState.points do
				points[i] = Matrix.point(shape, point)
			end

			for _, name in { "XRayEdges", "XRayEdgesSelect" } do
				local wire = anchor:FindFirstChild(name)
				if wire then
					wire.Scale = Vector3.one
					wire.CFrame = CFrame.identity
					wire:Clear()
					wire:AddLines(points)
				end
			end

			wireState.originalPoints = false
		end

		wireState.shape = table.clone(shape)
		wireState.writing = false
	end
end

function Geometry.screenDistance(anchor, camera, point)
	local wire = wires[anchor]
	if not wire then
		return nil
	end

	local shape = wire.shape
	local best = math.huge
	for i = 1, #wire.points - 1, 2 do
		local a, b = wire.points[i], wire.points[i + 1]
		if shape then
			a = Matrix.point(shape, a)
			b = Matrix.point(shape, b)
		end

		local p = camera:WorldToViewportPoint(anchor.CFrame:PointToWorldSpace(a))
		local q = camera:WorldToViewportPoint(anchor.CFrame:PointToWorldSpace(b))
		if p.Z > 0 and q.Z > 0 then
			local start = Vector2.new(p.X, p.Y)
			local delta = Vector2.new(q.X, q.Y) - start
			local t = delta:Dot(delta) > 0
					and math.clamp((point - start):Dot(delta) / delta:Dot(delta), 0, 1)
				or 0
			best = math.min(best, (point - start - delta * t).Magnitude)
		end
	end

	return best
end

function Geometry.select(anchor, selected)
	anchor:SetAttribute("EclipseArmatureSelected", selected == true)
	local solid = anchor:FindFirstChild("EclipseSolidShape")
	if solid then
		solid.Color = anchor:GetAttribute(selected and "SelectColor" or "BoneColor") or solid.Color
	end
end

function Geometry.setVisible(anchor, visible)
	visible = visible
		and require("Organization").isBoneVisible(anchor)
		and not require("Organization").usesPartWidget(anchor)
	local state = meshes[anchor]
	if state and not state.mesh then
		state.wantVisible = visible == true
		if visible then
			materializeLater(anchor, state, true)
		end
	end

	if visible and state and state.pendingShape then
		Geometry.update(anchor, state.pendingShape)
	end

	local fill = anchor:FindFirstChild("XRayFill")
	if fill then
		fill.Visible = visible == true
		fill.Transparency = (Preferences.get("ArmatureBoneTransparency") or 65) / 100
	end

	local selected = anchor:GetAttribute("EclipseArmatureSelected") == true
	local glow = anchor:FindFirstChild("EclipseSelectGlow")
	if glow then
		glow.Transparency = visible
				and selected
				and (Preferences.get("ArmatureBoneTransparency") or 65) / 100
			or 1
	end

	local normal, selection =
		anchor:FindFirstChild("XRayEdges"), anchor:FindFirstChild("XRayEdgesSelect")
	if normal then
		normal.Transparency = (Preferences.get("ArmatureBoneTransparency") or 65) / 100
		normal.Visible = visible and not selected
	end

	if selection then
		selection.Transparency = (Preferences.get("ArmatureBoneTransparency") or 65) / 100
		selection.Visible = visible and selected
	end

	local solid = anchor:FindFirstChild("EclipseSolidShape")
	if solid then
		solid.Transparency = visible and (Preferences.get("ArmatureBoneTransparency") or 65) / 100
			or 1
	end

	anchor.CanQuery = visible
		and anchor:GetAttribute("EclipseArmatureEmptyDisplay") ~= true
		and anchor:GetAttribute("EclipseArmatureUnselectable") ~= true
end

return Geometry
