--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Preferences = require("Preferences")
local Handles = {}
local surfacePadding = 1.02
local HANDLE_SCALE = 0.28
local updates = setmetatable({}, { __mode = "k" })
local preferenceRevision = 0
Preferences.subscribe(function(key)
	if key == "BoneStyle" or key == "FullBoneTransparency" or key == "HandleBoneTransparency" or key == "ArmatureBoneTransparency" or key == "BoneFrontIndicators" then preferenceRevision += 1 end
end)

local depthRoots = setmetatable({}, { __mode = "k" })
local depthDefaults = setmetatable({}, { __mode = "k" })

local function applyDepth(object)
	if not object:IsA("HandleAdornment") then
		return
	end

	if object.Name == "PartHandle" then
		object.AlwaysOnTop = true
		return
	end

	local saved = depthDefaults[object]
	if not saved then
		local ok, shading = pcall(function()
			return object.Shading
		end)
		saved = { top = object.AlwaysOnTop, shading = ok and shading or nil }
		depthDefaults[object] = saved
	end

	local control = object.Parent
	local xray = (control and control:GetAttribute("EclipseLimbControl") ~= nil)
		or Preferences.get("BoneXRay") ~= false
	object.AlwaysOnTop = xray and saved.top
	if saved.shading then
		object.Shading = xray and saved.shading or Enum.AdornShading.Default
	end
end

function Handles.bindDepth(root)
	if not root or depthRoots[root] then
		return
	end

	local entry = {}
	depthRoots[root] = entry
	for _, object in root:GetDescendants() do
		applyDepth(object)
	end

	entry.added = root.DescendantAdded:Connect(applyDepth)
	entry.changed = Preferences.subscribe(function(key)
		if key == "BoneXRay" then
			for _, object in root:GetDescendants() do
				applyDepth(object)
			end
		end
	end)
	entry.destroying = root.Destroying:Once(function()
		entry.added:Disconnect()
		entry.changed()
		depthRoots[root] = nil
	end)
end

local surfaces = setmetatable({}, { __mode = "k" })

local function visiblePart(part)
	if part:GetAttribute("EclipseAccessoryControlPart") then
		for _, joint in part:GetChildren() do
			if joint:IsA("Motor6D") and joint:GetAttribute("EclipseAccessoryControl") then
				local ref = joint:FindFirstChild("EclipseAccessoryPart")
				local source = ref and ref:IsA("ObjectValue") and ref.Value
				if source and source:IsA("BasePart") and source.Parent then
					return source
				end
			end
		end
	end

	return part
end

local hiddenFolders = setmetatable({}, { __mode = "k" })

function Handles.setPlaybackHidden(folder, hidden)
	if not folder then
		return
	end

	local entry = hiddenFolders[folder]
	if hidden then
		if entry then
			return
		end

		entry = { values = setmetatable({}, { __mode = "k" }) }
		hiddenFolders[folder] = entry
		folder:SetAttribute("EclipsePlaybackHidden", true)

		local function conceal(object)
			if object:IsA("BasePart") then
				entry.values[object] = { Transparency = object.Transparency }
				object.Transparency = 1
			elseif object:IsA("HandleAdornment") then
				entry.values[object] = { Visible = object.Visible }
				object.Visible = false
			end
		end

		for _, object in folder:GetDescendants() do
			conceal(object)
		end

		entry.added = folder.DescendantAdded:Connect(conceal)
		entry.destroying = folder.Destroying:Connect(function()
			entry.added:Disconnect()
			entry.destroying:Disconnect()
			hiddenFolders[folder] = nil
		end)
	elseif entry then
		hiddenFolders[folder] = nil
		entry.added:Disconnect()
		entry.destroying:Disconnect()
		folder:SetAttribute("EclipsePlaybackHidden", nil)
		for object, properties in entry.values do
			if object:IsDescendantOf(folder) then
				for name, value in properties do
					object[name] = value
				end
			end
		end
	end
end

function Handles.create(part)
	part = visiblePart(part)

	local marker
	if part:IsA("MeshPart") or part:IsA("PartOperation") then
		marker = Instance.fromExisting(part)
	end

	marker = marker or Instance.new("Part")
	marker.CastShadow = false
	for _, child in marker:GetChildren() do
		child:Destroy()
	end

	if marker:IsA("Part") and part:IsA("Part") then
		marker.Shape = part.Shape
		for _, child in part:GetChildren() do
			if child:IsA("DataModelMesh") then
				local mesh = child:Clone()
				if mesh:IsA("SpecialMesh") then
					mesh.TextureId = ""
				end

				mesh.Parent = marker
			end
		end
	end

	if marker:IsA("MeshPart") then
		marker.TextureID = ""
	end

	surfaces[marker] = {
		part = part,
		sourceMesh = part:FindFirstChildWhichIsA("DataModelMesh"),
		mesh = marker:FindFirstChildWhichIsA("DataModelMesh"),
	}
	return marker
end

local function boxDistance(ray, frame, size)
	local origin = frame:PointToObjectSpace(ray.Origin)
	local direction = frame:VectorToObjectSpace(ray.Direction.Unit)
	local lo, hi = 0, 1000
	for _, axis in { "X", "Y", "Z" } do
		local o, d, h = origin[axis], direction[axis], size[axis] * 0.5
		if math.abs(d) < 1e-8 then
			if math.abs(o) > h then
				return nil
			end
		else
			local a, b = (-h - o) / d, (h - o) / d
			lo = math.max(lo, math.min(a, b))
			hi = math.min(hi, math.max(a, b))
			if lo > hi then
				return nil
			end
		end
	end

	return lo, hi
end

local function nativeMarker(part)
	return part:GetAttribute("SourceIsBone") == true or part:GetAttribute("EclipseBoneLink") ~= nil
end

local function sphereDistance(origin, direction, radius)
	local c = origin:Dot(origin) - radius * radius
	if c <= 0 then
		return 0
	end

	local b = origin:Dot(direction)
	local disc = b * b - c
	if disc < 0 then
		return nil
	end

	local t = -b - math.sqrt(disc)
	return t >= 0 and t or nil
end

local function coneDistance(origin, direction, radius, height)
	if radius <= 0 or height <= 0 then
		return nil
	end

	local k = radius / height
	local k2 = k * k

	local function inside(t)
		if t < 0 then
			return false
		end

		local z = origin.Z + direction.Z * t
		return z >= -height - 1e-6 and z <= 1e-6
	end

	local best
	local radial = origin.X * origin.X + origin.Y * origin.Y
	if inside(0) and radial <= k2 * (origin.Z + height) ^ 2 then
		return 0
	end

	if math.abs(direction.Z) > 1e-9 then
		local t = -origin.Z / direction.Z
		if t >= 0 then
			local p = origin + direction * t
			if p.X * p.X + p.Y * p.Y <= radius * radius then
				best = t
			end
		end
	end

	local a = direction.X ^ 2 + direction.Y ^ 2 - k2 * direction.Z ^ 2
	local b = 2
		* (origin.X * direction.X + origin.Y * direction.Y - k2 * (origin.Z + height) * direction.Z)
	local c = radial - k2 * (origin.Z + height) ^ 2

	local function consider(t)
		if inside(t) and (not best or t < best) then
			best = t
		end
	end

	if math.abs(a) < 1e-10 then
		if math.abs(b) > 1e-10 then
			consider(-c / b)
		end
	else
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			local root = math.sqrt(disc)
			consider((-b - root) / (2 * a))
			consider((-b + root) / (2 * a))
		end
	end

	return best
end

local function pickNativeMarkers(ray, parts)
	local nearest, distance, zIndex = nil, math.huge, -math.huge
	local direction = ray.Direction.Unit
	for _, part in parts do
		if
			not nativeMarker(part)
			or not part.CanQuery
			or part:GetAttribute("Hidden") == true
			or part.Parent and part.Parent:GetAttribute("EclipsePlaybackHidden") == true
		then
			continue
		end

		for _, adorn in part:GetChildren() do
			if
				not (adorn:IsA("SphereHandleAdornment") or adorn:IsA("ConeHandleAdornment"))
				or not adorn.Visible
				or adorn.Transparency >= 1
				or Preferences.get("BoneXRay") ~= false and adorn.ZIndex < 0
			then
				continue
			end

			local target = adorn.Adornee
			if not target or not target:IsA("BasePart") then
				continue
			end

			local frame = target.CFrame
				* CFrame.new(target.Size * adorn.SizeRelativeOffset * 0.5)
				* adorn.CFrame
			local origin = frame:PointToObjectSpace(ray.Origin)
			local localDirection = frame:VectorToObjectSpace(direction)
			local hit
			if adorn:IsA("SphereHandleAdornment") then
				hit = sphereDistance(origin, localDirection, adorn.Radius)
			else
				hit = coneDistance(origin, localDirection, adorn.Radius, adorn.Height)
			end

			if
				hit
				and hit <= 1000
				and (adorn.ZIndex > zIndex or adorn.ZIndex == zIndex and hit < distance)
			then
				nearest, distance, zIndex = part, hit, adorn.ZIndex
			end
		end
	end

	return nearest
end

function Handles.bodyPart(anchor)
	local link = anchor and anchor:FindFirstChild("EclipseArmatureTarget")
	local target = link and link.Value
	if target and target:IsA("Motor6D") then
		return target.Part1
	end

	if target and target:IsA("Bone") then
		return target:FindFirstAncestorWhichIsA("BasePart")
	end

	if target and target:IsA("BasePart") then
		return target
	end
end

function Handles.partWidgetBounds(anchor)
	local body = Handles.bodyPart(anchor)
	if body and body.Parent then
		return body.CFrame, body.Size * HANDLE_SCALE
	end

	local head, tail = anchor:GetAttribute("Head"), anchor:GetAttribute("Tail")
	if
		typeof(head) == "Vector3"
		and typeof(tail) == "Vector3"
		and (tail - head).Magnitude > 0.001
	then
		local length = (tail - head).Magnitude
		local width = math.clamp(length * 0.2, 0.12, 0.6)
		return CFrame.lookAt((head + tail) * 0.5, tail),
			Vector3.new(width, width, length) * HANDLE_SCALE
	end

	return anchor.CFrame, Vector3.new(0.2, 0.2, 0.2) * HANDLE_SCALE
end

function Handles.updateFront(marker, world, size, visible)
	local arrow = marker:FindFirstChild("FrontIndicator")
	local show = Preferences.get("BoneFrontIndicators") == true and visible == true
		and not (marker.Parent and marker.Parent:GetAttribute("EclipsePlaybackHidden"))
	if show and not arrow then
		arrow = Instance.new("ConeHandleAdornment")
		arrow.Name, arrow.Adornee = "FrontIndicator", marker
		arrow.AlwaysOnTop, arrow.ZIndex = true, 2
		arrow.Transparency = 0.2
		arrow.Parent = marker
	end
	if not arrow then return end
	if arrow.Visible ~= show then arrow.Visible = show end
	if not show then return end
	local length = math.clamp(math.min(size.X, size.Y, size.Z) * 0.25, 0.08, 0.3)
	local frame = marker.CFrame:ToObjectSpace(world * CFrame.new(0, 0, -size.Z * 0.5))
	if arrow.CFrame ~= frame then arrow.CFrame = frame end
	if arrow.Height ~= length then arrow.Height = length end
	if arrow.Radius ~= length * 0.45 then arrow.Radius = length * 0.45 end
	local color = marker:GetAttribute("EclipseHandleSelected") == true and Color3.fromRGB(245, 170, 200) or Color3.fromRGB(124, 186, 209)
	if arrow.Color3 ~= color then arrow.Color3 = color end
end

function Handles.updateArmature(marker, anchor)
	local org = require("Organization")
	require("distance").setVisible(anchor, not anchor:GetAttribute("Hidden"))
	local show = org.usesPartWidget(anchor)
		and anchor.Parent
		and org.isBoneVisible(anchor)
		and not anchor:GetAttribute("Hidden")
		and not marker.Parent:GetAttribute("EclipsePlaybackHidden")
	local handle = marker:FindFirstChild("PartHandle")
	if show and not handle then
		handle = Instance.new("BoxHandleAdornment")
		handle.Name = "PartHandle"
		handle.Adornee = marker
		handle.AlwaysOnTop = true
		handle.ZIndex = 1
		handle.Transparency = 0.75
		handle.Parent = marker
	end

	marker:SetAttribute("EclipseFullPartWidget", show == true)
	marker.CanQuery = show == true
	marker.Transparency = 1
	local frontWorld, frontSize = Handles.partWidgetBounds(anchor)
	Handles.updateFront(marker, frontWorld, frontSize, org.isBoneVisible(anchor) and not anchor:GetAttribute("Hidden"))
	if handle then
		handle.Visible = show == true
		if show then
			local frame, size = Handles.partWidgetBounds(anchor)
			handle.CFrame = marker.CFrame:ToObjectSpace(frame)
			handle.Size = size
			Handles.select(marker, anchor:GetAttribute("EclipseArmatureSelected") == true)
		end
	end
end

function Handles.pick(ray, parts, camera, point)
	local native = pickNativeMarkers(ray, parts)
	if not native and camera and point then
		local markers = {}
		for _, part in parts do
			if nativeMarker(part) then table.insert(markers, part) end
		end
		native = Handles.assist(camera, point, markers)
	end
	if native then
		return native
	end

	local remaining = {}
	local handleHit, handleDistance = nil, math.huge
	for _, part in parts do
		if nativeMarker(part) then
			continue
		end

		local handle = part:FindFirstChild("PartHandle")
		if
			(Preferences.get("BoneStyle") == 2 or part:GetAttribute("EclipseFullPartWidget"))
			and handle
		then
			if part.CanQuery and handle.Visible then
				local distance = boxDistance(ray, part.CFrame * handle.CFrame, handle.Size)
				if distance and distance < handleDistance then
					handleHit, handleDistance = part, distance
				end
			end
		elseif part:GetAttribute("EclipseArmatureBone") and part:GetAttribute("Solid") ~= true then
			if camera and point and part.CanQuery and not part:GetAttribute("Hidden") then
				local distance = require("distance").screenDistance(part, camera, point)
				local depth = (part.Position - ray.Origin):Dot(ray.Direction.Unit)
				if distance and distance <= 4 and depth > 0 and depth < handleDistance then
					handleHit, handleDistance = part, depth
				end
			end
		else
			local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
			if mesh and mesh.MeshType == Enum.MeshType.Head then
				if
					part.CanQuery
					and not part:GetAttribute("Hidden")
					and not (part.Parent and part.Parent:GetAttribute("EclipsePlaybackHidden"))
				then
					local size = Vector3.new(part.Size.X * 0.5, part.Size.Y, part.Size.Z)
						* mesh.Scale:Abs()
					local distance = boxDistance(ray, part.CFrame * CFrame.new(mesh.Offset), size)
					if distance and distance < handleDistance then
						handleHit, handleDistance = part, distance
					end
				end
			else
				table.insert(remaining, part)
			end
		end
	end

	local nearest, bestScore, firstDistance = nil, math.huge, nil
	local visibleHit = false
	local maxDistance = nil
	for _ = 1, 6 do
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = remaining
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = true
		local hit = workspace:Raycast(ray.Origin, ray.Direction.Unit * 1000, params)
		if not hit then
			break
		end

		local distance = (hit.Position - ray.Origin).Magnitude
		if maxDistance and distance > maxDistance then
			break
		end

		local part = hit.Instance
		local source = part:FindFirstChild("EclipseSourcePart")
		local hidden = source
			and source.Value
			and source.Value:IsA("BasePart")
			and source.Value.Transparency >= 1
		if not firstDistance then
			firstDistance = distance
			maxDistance = distance + 0.05
			if hidden then
				local _, exitDistance = boxDistance(ray, part.CFrame, part.Size)
				maxDistance = math.max(maxDistance, exitDistance or distance)
			end
		end

		local localHit = part.CFrame:PointToObjectSpace(hit.Position) / part.Size
		local score = localHit:Dot(localHit)
		if not hidden and not visibleHit then
			nearest, bestScore, visibleHit = part, score, true
			maxDistance = distance + 0.05
		elseif (not hidden or not visibleHit) and score < bestScore then
			nearest, bestScore = part, score
		end

		local index = table.find(remaining, part)
		if not index then
			break
		end

		table.remove(remaining, index)
	end

	if handleHit and (not firstDistance or handleDistance < firstDistance) then
		return handleHit
	end

	return nearest
end

function Handles.assist(camera, point, parts)
	if Preferences.get("BoneSelectionAssist") == false then
		return nil
	end

	local radius = Preferences.get("BoneSelectionRadius") or 10
	local best, bestDistance, bestDepth = nil, radius, math.huge
	for _, part in parts do
		if
			not part.CanQuery
			or part:GetAttribute("Hidden") == true
			or part.Parent and part.Parent:GetAttribute("EclipsePlaybackHidden")
		then
			continue
		end

		local projected = camera:WorldToViewportPoint(part.Position)
		if projected.Z <= 0 then
			continue
		end

		local distance
		if part:GetAttribute("EclipseArmatureBone") then
			distance = require("distance").screenDistance(part, camera, point)
		else
			local center = Vector2.new(projected.X, projected.Y)
			distance = (point - center).Magnitude
			for _, adorn in part:GetChildren() do
				if adorn:IsA("ConeHandleAdornment") and adorn.Visible then
					local frame = part.CFrame
						* CFrame.new(part.Size * adorn.SizeRelativeOffset * 0.5)
						* adorn.CFrame
					local p = camera:WorldToViewportPoint(frame.Position)
					local q = camera:WorldToViewportPoint(
						frame:PointToWorldSpace(Vector3.new(0, 0, -adorn.Height))
					)
					if p.Z > 0 and q.Z > 0 then
						local start = Vector2.new(p.X, p.Y)
						local delta = Vector2.new(q.X, q.Y) - start
						local t = delta:Dot(delta) > 0
								and math.clamp((point - start):Dot(delta) / delta:Dot(delta), 0, 1)
							or 0
						distance = math.min(distance, (point - start - delta * t).Magnitude)
					end
				end
			end
		end

		if
			distance
			and (distance < bestDistance or distance == bestDistance and projected.Z < bestDepth)
		then
			best, bestDistance, bestDepth = part, distance, projected.Z
		end
	end

	return best
end

function Handles.update(marker, part)
	local surface = surfaces[marker]
	if surface and surface.part.Parent then
		part = surface.part
	end

	if marker.CFrame ~= part.CFrame then
		marker.CFrame = part.CFrame
	end

	local size = part.Size * surfacePadding
	if marker.Size ~= size then
		marker.Size = size
	end

	local query = marker.CanQuery
	local hidden = marker.Parent and marker.Parent:GetAttribute("EclipsePlaybackHidden")
	local sourceMesh = surface and surface.sourceMesh
	local meshScale = sourceMesh and sourceMesh.Scale
	local meshOffset = sourceMesh and sourceMesh.Offset
	local meshId = sourceMesh and sourceMesh:IsA("SpecialMesh") and sourceMesh.MeshId
	local meshType = sourceMesh and sourceMesh:IsA("SpecialMesh") and sourceMesh.MeshType
	local previous = updates[marker]
	if previous and previous.size == size and previous.query == query and previous.hidden == hidden
		and previous.revision == preferenceRevision and previous.meshScale == meshScale and previous.meshOffset == meshOffset
		and previous.meshId == meshId and previous.meshType == meshType and previous.handle.Parent == marker then return end

	if surface then
		local sourceMesh, mesh = surface.sourceMesh, surface.mesh
		if sourceMesh and mesh and sourceMesh.Parent == part and mesh.Parent == marker then
			local fileMesh = sourceMesh:IsA("SpecialMesh")
				and sourceMesh.MeshType == Enum.MeshType.FileMesh
			local scale = sourceMesh.Scale * (fileMesh and surfacePadding or 1)
			if mesh.Scale ~= scale then
				mesh.Scale = scale
			end

			if mesh.Offset ~= sourceMesh.Offset then
				mesh.Offset = sourceMesh.Offset
			end

			if mesh:IsA("SpecialMesh") and sourceMesh:IsA("SpecialMesh") then
				if mesh.MeshType ~= sourceMesh.MeshType then
					mesh.MeshType = sourceMesh.MeshType
				end

				if mesh.MeshId ~= sourceMesh.MeshId then
					mesh.MeshId = sourceMesh.MeshId
				end
			end
		end
	end

	local handle = marker:FindFirstChild("PartHandle")
	if not handle then
		handle = Instance.new("BoxHandleAdornment")
		handle.Name = "PartHandle"
		handle.Adornee = marker
		handle.AlwaysOnTop = true
		handle.ZIndex = 1
		handle.Color3 = Color3.fromRGB(124, 186, 209)
		handle.Transparency = 0.55
		handle.Parent = marker
	end

	local style = Preferences.get("BoneStyle") or 1
	local visible = style == 2
		and marker.CanQuery
		and not (marker.Parent and marker.Parent:GetAttribute("EclipsePlaybackHidden"))
	if handle.Visible ~= visible then handle.Visible = visible end
	local handleSize = part.Size * HANDLE_SCALE
	if handle.Size ~= handleSize then handle.Size = handleSize end
	if marker:GetAttribute("EclipseHandleStyle") ~= style then
		marker:SetAttribute("EclipseHandleStyle", style)
		marker.Transparency = style == 1
				and marker:GetAttribute("EclipseHandleSelected") == true
				and (Preferences.get("FullBoneTransparency") or 80) / 100
			or 1
	end

	if handle.Visible then
		marker.Transparency = 1
	end

	Handles.select(marker, marker:GetAttribute("EclipseHandleSelected") == true)
	Handles.updateFront(marker, part.CFrame, part.Size, marker.CanQuery)
	updates[marker] = { size = size, query = query, hidden = hidden, revision = preferenceRevision, meshScale = meshScale, meshOffset = meshOffset, meshId = meshId, meshType = meshType, handle = handle }
end

function Handles.select(marker, selected)
	if marker:GetAttribute("EclipseHandleSelected") ~= selected then marker:SetAttribute("EclipseHandleSelected", selected) end
	local handle = marker:FindFirstChild("PartHandle")
	local arrow = marker:FindFirstChild("FrontIndicator")
	if arrow then
		local color = selected and Color3.fromRGB(245, 170, 200) or Color3.fromRGB(124, 186, 209)
		if arrow.Color3 ~= color then arrow.Color3 = color end
	end
	if handle then
		local transparency = (
			Preferences.get(
				marker:GetAttribute("EclipseFullPartWidget") and "ArmatureBoneTransparency"
					or "HandleBoneTransparency"
			) or 55
		) / 100
		local color = selected and Color3.fromRGB(245, 170, 200) or Color3.fromRGB(124, 186, 209)
		if handle.Transparency ~= transparency then handle.Transparency = transparency end
		if handle.Color3 ~= color then handle.Color3 = color end
	end
end

return Handles
