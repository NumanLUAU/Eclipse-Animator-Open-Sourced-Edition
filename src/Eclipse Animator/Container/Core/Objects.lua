--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Assets = require("EffectCatalog")
local Objects = {}
Objects.images = { "82598366942133", "106569976373084", "92678033024080", "100796043365951" }
local replacedImages = {
	["4764912210"] = Objects.images[1],
	["4764912960"] = Objects.images[2],
	["4764912557"] = Objects.images[3],
	["4764912732"] = Objects.images[4],
}
local defaults = {
	Strength = 0,
	Speed = 12,
	Image = "",
	Color = Color3.new(),
	Transparency = 1,
	Size = Vector2.one,
	Position = Vector2.zero,
	Rotation = 0,
	Enabled = true,
	FollowFOV = true,
	AlwaysOnTop = true,
	Gradient = false,
	Color2 = Color3.new(1, 1, 1),
	GradientRotation = 90,
}
local cache = setmetatable({}, { __mode = "k" })

function Objects.is(model)
	return model and model:IsA("Model") and model:GetAttribute("EclipseEffectObject") == 1
end

function Objects.kind(model)
	return Objects.is(model) and model:GetAttribute("EffectKind")
end

function Objects.catalog(model)
	if Objects.kind(model) == "Camera Shake" then
		return {
			{ id = "Strength", label = "Strength", kind = "number" },
			{ id = "Speed", label = "Speed", kind = "number" },
			{ id = "Enabled", label = "Enabled", kind = "boolean", optional = true },
		}
	end

	local result = {
		{ id = "Color", label = "Color", kind = "Color3" },
		{ id = "Transparency", label = "Transparency", kind = "number" },
		{ id = "Enabled", label = "Enabled", kind = "boolean" },
	}
	if Objects.kind(model) == "Impact Frames" then
		table.insert(result, 1, { id = "Image", label = "Image", kind = "string" })
	end

	if Objects.kind(model) == "Screen Cover" or Objects.kind(model) == "Impact Frames" then
		for _, id in { "Size", "Position", "Rotation" } do
			table.insert(result, { id = id, label = id, kind = typeof(defaults[id]) })
		end
	end

	for _, id in { "Gradient", "Color2", "GradientRotation" } do
		table.insert(result, {
			id = id,
			label = id == "Color2" and "Second Color"
				or id == "GradientRotation" and "Gradient Angle"
				or id,
			kind = typeof(defaults[id]),
			optional = true,
		})
	end

	if Objects.kind(model) == "Impact Frames" then
		for _, def in result do
			if def.id ~= "Image" and def.id ~= "Transparency" then
				def.optional = true
			end
		end
	end

	if Objects.kind(model) == "Letterbox" then
		table.insert(result, { id = "FollowFOV", label = "Follow FOV", kind = "boolean" })
		table.insert(result, { id = "AlwaysOnTop", label = "Always on top", kind = "boolean" })
		table.insert(result, { id = "Depth", label = "Depth", kind = "number", optional = true })
		table.insert(result, { id = "ZIndex", label = "ZIndex", kind = "number", optional = true })
		for _, id in
			model:GetAttribute("EffectStyle") == "Solid" and { "TopSize", "BottomSize" } or {
				"VFXSize",
			}
		do
			table.insert(result, {
				id = id,
				label = id:gsub("Size", " Size"),
				kind = "Vector3",
				hidden = model:GetAttribute("EffectStyle") == "Solid",
				optional = model:GetAttribute("EffectStyle") == "Solid",
				legacy = model:GetAttribute("EffectStyle") == "Solid",
			})
		end
	end

	return result
end

function Objects.read(model, id)
	if id == "Depth" then return model:GetAttribute("EffectDepth") or model:GetAttribute("EffectReferenceDepth") or 1.2 end
	if id == "ZIndex" then
		return model:GetAttribute("EffectZIndex")
			or (model:GetAttribute("EffectStyle") == "Solid" and 0 or 1)
	end

	if id:sub(-4) == "Size" and id ~= "Size" then
		local part = model:FindFirstChild(id:sub(1, -5))
		return part and part.Size or Vector3.one
	end

	local value = model:GetAttribute("Effect" .. id)
	if value ~= nil then
		return value
	end

	return defaults[id]
end

function Objects.write(model, id, value)
	if id:sub(-4) == "Size" and id ~= "Size" then
		local part = model:FindFirstChild(id:sub(1, -5))
		if part then
			part.Size = Vector3.new(
				math.max(0.001, value.X),
				math.max(0.001, value.Y),
				math.max(0.001, value.Z)
			)
		end

		return
	end

	model:SetAttribute("Effect" .. id, value)
end

local function decode(value, nodes)
	if type(value) ~= "table" then
		return value
	end

	local t, a = value.t, value.v
	if t == "Vector3" then
		return Vector3.new(table.unpack(a))
	elseif t == "Vector2" then
		return Vector2.new(table.unpack(a))
	elseif t == "CFrame" then
		return CFrame.new(table.unpack(a))
	elseif t == "Color3" then
		return Color3.new(table.unpack(a))
	elseif t == "NumberRange" then
		return NumberRange.new(table.unpack(a))
	elseif t == "EnumItem" then
		return Enum[value.e][a]
	elseif t == "Ref" then
		return nodes[a]
	elseif t == "NumberSequence" then
		local keys = {}
		for _, p in a do
			table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
		end

		return NumberSequence.new(keys)
	elseif t == "ColorSequence" then
		local keys = {}
		for _, p in a do
			table.insert(keys, ColorSequenceKeypoint.new(p[1], decode(p[2])))
		end

		return ColorSequence.new(keys)
	end

	error("Unknown effect asset value")
end

local function safePart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Locked = false
end

function Objects.build(value, camera, aspect)
	local model = Instance.new("Model")
	model.Name = value.name
	model:SetAttribute("EclipseEffectObject", 1)
	model:SetAttribute("EffectKind", value.kind)
	model:SetAttribute("EclipseTrackId", Http:GenerateGUID(false))
	for id, default in defaults do
		Objects.write(model, id, default)
	end

	Objects.write(model, "Color", Color3.new(table.unpack(value.color)))
	Objects.write(model, "Enabled", value.enabled ~= false)
	Objects.write(model, "Gradient", value.gradient == true)
	Objects.write(model, "Color2", Color3.new(table.unpack(value.color2 or value.color)))
	Objects.write(model, "GradientRotation", value.gradientRotation or 90)
	if value.kind == "Camera Shake" then
		model:SetAttribute("EffectCameraId", value.cameraId)
	end

	if value.kind ~= "Letterbox" then
		Objects.write(model, "Size", Vector2.new(value.width or 1, value.heightScale or 1))
		if value.kind == "Vignette" then
			for i, id in value.images or Objects.images do
				model:SetAttribute("VignetteImage" .. i, id)
			end
		end

		return model
	end

	assert(camera, "Choose a project camera")
	model:SetAttribute("EffectCameraId", value.cameraId)
	model:SetAttribute("EffectStyle", value.style)

	local depth = (value.depth or 1.2)
		* require("CameraRig").displayDepth(camera.fov)
		/ require("CameraRig").DEPTH
	model:SetAttribute("EffectReferenceFOV", camera.fov)
	model:SetAttribute("EffectReferenceDepth", depth)
	model:SetAttribute("EffectReferenceAspect", aspect or 16 / 9)
	local height = 2 * depth * math.tan(math.rad(camera.fov) * 0.5)
	local width = height * (aspect or 16 / 9)
	local cf = camera.cf
	model.WorldPivot = cf
	if value.style == "Solid" then
		for _, entry in { { "Top", 1 }, { "Bottom", -1 } } do
			local part = Instance.new("Part")
			part.Name = entry[1]
			safePart(part)
			part.Material = Enum.Material.Neon

			local overscan = height * 0.25
			part.Size = Vector3.new(
				width * (value.width or 1) * 1.2,
				height * value.height + overscan,
				0.02
			)
			local mesh = Instance.new("BlockMesh")
			mesh.Parent = part
			part.CFrame = cf
				* CFrame.new(
					0,
					entry[2] * (height - height * value.height + overscan) * 0.5,
					-depth
				)
			part.Color = Color3.new(table.unpack(value.color))
			part.Transparency = 1
			part.Parent = model
		end
	else
		local asset
		for _, a in Assets do
			if a.id == value.style then
				asset = a
				break
			end
		end

		assert(asset, "Choose a letterbox style")
		local nodes = {}
		for i, row in asset.nodes do
			nodes[i] = Instance.new(row.class)
			nodes[i].Name = row.name
		end

		for i, row in asset.nodes do
			for id, v in row.properties do
				nodes[i][id] = decode(v, nodes)
			end

			nodes[i].Parent = row.parent and nodes[row.parent] or model
		end

		local plane = nodes[1]
		plane.Name = "VFX"
		safePart(plane)
		plane.Transparency = 1
		plane:SetAttribute("EffectOriginalSize", plane.Size)
		plane.Size = Vector3.new(
			width * (value.width or value.scale or 1),
			height * (value.heightScale or value.scale or 1),
			0.02
		)
		plane.CFrame = cf * CFrame.new(0, 0, -depth)
		for i, row in asset.nodes do
			local node = nodes[i]
			if node:IsA("Attachment") then
				node:SetAttribute("EffectOriginalCFrame", node.CFrame)
			elseif node:IsA("Beam") or node:IsA("ParticleEmitter") then
				node:SetAttribute("EffectOriginalProperties", Http:JSONEncode(row.properties))
			end
		end
	end

	local rig = require("PartRig").create(model)
	rig.root.CFrame = cf
	model:SetAttribute("EclipseIndividualParts", true)
	for _, joint in rig.joints do
		joint:SetAttribute("EclipsePartTrackEnabled", true)
	end

	return model
end

local function multiply(a, b)
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end

local function info(model)
	if cache[model] then
		return cache[model]
	end

	local result = { parts = {}, attachments = {}, visuals = {}, joints = {}, jointFrames = {} }
	cache[model] = result
	for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then
			if v:GetAttribute("EclipsePartRigRoot") then
				result.root = v
			else
				table.insert(result.parts, v)
			end
		elseif v:IsA("Motor6D") and v:GetAttribute("EclipsePartRigJoint") then
			table.insert(result.joints, v)
		elseif v:IsA("Attachment") and v:GetAttribute("EffectOriginalCFrame") then
			table.insert(result.attachments, v)
		elseif v:GetAttribute("EffectOriginalProperties") then
			local row = Http:JSONDecode(v:GetAttribute("EffectOriginalProperties"))
			local props = {}
			for _, id in
				{
					"Color",
					"Transparency",
					"Size",
					"Width0",
					"Width1",
					"CurveSize0",
					"CurveSize1",
					"Enabled",
					"TextureSpeed",
				}
			do
				if row[id] ~= nil then
					props[id] = decode(row[id])
				end
			end

			if model:GetAttribute("EffectStyle") == "DoubleColors/4" and v:IsA("Beam") then
				props.Width0 = math.min(props.Width0, 0.4)
				props.Width1 = math.min(props.Width1, 0.4)
			end

			table.insert(result.visuals, { object = v, props = props })
		end
	end

	return result
end

function Objects.follow(model, camera, raw)
	local data = info(model)
	if not data.root or not camera then
		return
	end

	for _, joint in data.joints do
		local expected = data.root.CFrame * joint.C0 * joint.Transform * joint.C1:Inverse()
		local changed = (joint.Part1.CFrame.Position - expected.Position).Magnitude > 1e-4
			or (joint.Part1.CFrame.LookVector - expected.LookVector).Magnitude > 1e-4
			or (joint.Part1.CFrame.UpVector - expected.UpVector).Magnitude > 1e-4
		if not raw.Playing and data.jointFrames[joint] == joint.C0 and changed then
			joint.C0 = data.root.CFrame:ToObjectSpace(joint.Part1.CFrame)
				* joint.C1
				* joint.Transform:Inverse()
			if not next(raw.Keyframes[joint] or {}) then
				raw.DefaultPose[joint] = joint.C0
				joint:SetAttribute("EclipseAnimatorDefaultC0", joint.C0)
			end
		end

		data.jointFrames[joint] = joint.C0
	end

	local fov = camera.fov or model:GetAttribute("EffectReferenceFOV") or 70
	local reference = model:GetAttribute("EffectReferenceFOV")
	local depth = model:GetAttribute("EffectReferenceDepth")
	if not reference then
		reference = fov
		model:SetAttribute("EffectReferenceFOV", reference)
	end

	if not depth then
		local sum = 0
		for _, joint in data.joints do
			sum += math.abs((raw.DefaultPose[joint] or joint.C0).Z)
		end

		depth = #data.joints > 0 and sum / #data.joints or 1.2
		model:SetAttribute("EffectReferenceDepth", depth)
	end

	local ratio = math.tan(math.rad(math.clamp(reference, 1, 120)) * 0.5)
		/ math.tan(math.rad(math.clamp(fov, 1, 120)) * 0.5)
	local modeKey
	local properties = require("Properties")
	for _, motor in properties.list(model, true) do
		if
			motor.PropertyId == "FollowFOV"
			and motor.Part1:GetAttribute("Enabled") ~= false
			and motor:GetAttribute("EclipseDisabled") ~= true
		then
			for _, key in raw.Keyframes[motor] or {} do
				if
					not key.Disabled
					and key.Time <= raw.CurrentTime
					and (not modeKey or key.Time > modeKey.Time)
				then
					modeKey = key
				end
			end
		end
	end

	local anchor = modeKey and modeKey.FovFollowAnchor
	if anchor then
		local anchorRatio = anchor.X
		local anchorFov = anchor.Y
		ratio = Objects.read(model, "FollowFOV") ~= false
				and anchorRatio * math.tan(math.rad(anchorFov) * 0.5) / math.tan(
					math.rad(math.clamp(fov, 1, 120)) * 0.5
				)
			or anchorRatio
	elseif Objects.read(model, "FollowFOV") == false then
		ratio = 1
	end

	data.followRatio = ratio

	data.root.CFrame = camera.cf * CFrame.new(0, 0, depth * (1 - ratio))
	require("PartRig").flush(model)
end

function Objects.followRatio(model)
	return info(model).followRatio or 1
end

function Objects.paint(model, visible, time)
	local data = info(model)
	local color = Objects.read(model, "Color")
	local alpha = visible and 1 - math.clamp(Objects.read(model, "Transparency"), 0, 1) or 0
	local gradient = Objects.read(model, "Gradient")
	local color2 = Objects.read(model, "Color2")
	local rotation = Objects.read(model, "GradientRotation")
	local solid = model:GetAttribute("EffectStyle") == "Solid"
	if solid and not model:GetAttribute("EffectReferenceAspect") then
		local topPart = model:FindFirstChild("Top")
		local depth = model:GetAttribute("EffectReferenceDepth") or 1.2
		local fov = model:GetAttribute("EffectReferenceFOV") or 70
		local height = 2 * depth * math.tan(math.rad(math.clamp(fov, 1, 120)) * 0.5)
		if topPart and topPart:IsA("BasePart") and height > 0 then
			model:SetAttribute("EffectReferenceAspect", math.max(0.01, topPart.Size.X / height / 1.2))
		end
	end
	local top = Objects.read(model, "AlwaysOnTop") ~= false
	local layer = require("layer")
	local z = Objects.read(model, "ZIndex")
	for _, part in data.parts do
		if solid then
			part.Color = color
			part.Transparency = 1
			part:SetAttribute("EclipseEffectVisible", alpha > 0)
			if not part:FindFirstChild("EffectGradientBack") then
				for _, face in Enum.NormalId:GetEnumItems() do
					local surface = Instance.new("SurfaceGui")
					surface.Name = "EffectGradient" .. face.Name
					surface.Face = face
					surface.LightInfluence = 0
					surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
					surface.CanvasSize = Vector2.new(512, 128)
					surface.Parent = part
					local fill = Instance.new("Frame")
					fill.Name = "Fill"
					fill.AnchorPoint = Vector2.new(0.5, 0.5)
					fill.Position = UDim2.fromScale(0.5, 0.5)
					fill.Size = UDim2.fromScale(1, 1)
					fill.BorderSizePixel = 0
					fill.BackgroundColor3 = Color3.new(1, 1, 1)
					fill.Parent = surface
					local g = Instance.new("UIGradient")
					g.Parent = fill
				end
			end

			for _, surface in part:GetChildren() do
				if surface:IsA("SurfaceGui") and surface.Name:sub(1, 14) == "EffectGradient" then
					surface:SetAttribute("EclipseEffectSurface", true)
					surface.Archivable = false
					surface.AlwaysOnTop = top
					surface.ZOffset = z
					surface.Active = false
					surface.Enabled = alpha > 0
					surface.Fill.BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color
					surface.Fill.UIGradient.Enabled = gradient
					surface.Fill.BackgroundTransparency = 1 - alpha
					surface.Fill.UIGradient.Color = ColorSequence.new(color, color2)
					surface.Fill.UIGradient.Rotation = rotation
				end
			end

			layer.update(part, alpha > 0, z, true, not top and Objects.read(model, "Depth") or nil, model:GetAttribute("EffectReferenceAspect"))
		else
			part.Transparency = 1
			local original = part:GetAttribute("EffectOriginalSize")
			if not original then
				continue
			end

			local sx, sy = part.Size.X / original.X, part.Size.Y / original.Y
			for _, a in data.attachments do
				local cf = a:GetAttribute("EffectOriginalCFrame")
				local p = cf.Position
				a.CFrame = CFrame.new(p.X * sx, p.Y * sy, p.Z * sy) * cf.Rotation
			end

			for _, row in data.visuals do
				local object, props = row.object, row.props
				object.Enabled = alpha > 0 and not top and props.Enabled ~= false
				if row.color ~= color or row.color2 ~= color2 or row.gradient ~= gradient then
					local keys = {}
					for _, p in props.Color.Keypoints do
						table.insert(
							keys,
							ColorSequenceKeypoint.new(
								p.Time,
								multiply(p.Value, gradient and color:Lerp(color2, p.Time) or color)
							)
						)
					end

					object.Color = ColorSequence.new(keys)
					row.color = color
					row.color2 = color2
					row.gradient = gradient
				end

				if row.alpha ~= alpha then
					local keys = {}
					for _, p in props.Transparency.Keypoints do
						table.insert(
							keys,
							NumberSequenceKeypoint.new(
								p.Time,
								1 - (1 - p.Value) * alpha,
								p.Envelope * alpha
							)
						)
					end

					object.Transparency = NumberSequence.new(keys)
					row.alpha = alpha
				end

				if object:IsA("Beam") then
					object.Width0 = props.Width0 * sy
					object.Width1 = props.Width1 * sy
					object.CurveSize0 = props.CurveSize0 * sy
					object.CurveSize1 = props.CurveSize1 * sy
					object.TextureSpeed = 0
					object:SetTextureOffset(((time or 0) * (props.TextureSpeed or 0)) % 1)
				elseif row.scale ~= sy then
					local keys = {}
					for _, p in props.Size.Keypoints do
						table.insert(
							keys,
							NumberSequenceKeypoint.new(p.Time, p.Value * sy, p.Envelope * sy)
						)
					end

					object.Size = NumberSequence.new(keys)
					row.scale = sy
				end
			end

			require("EffectSampler").paint(part, data.visuals, top and alpha > 0, time or 0)
			layer.update(part, alpha > 0 and top, z)
		end
	end
end

function Objects.impactImage(value)
	local builtins = {
		["builtin:White"] = true,
		["builtin:Black"] = true,
		["builtin:Burst"] = true,
		["builtin:Inverse"] = true,
	}
	if value == "" or builtins[value] then
		return value
	end

	local id = tostring(value):match("^%s*(%d+)%s*$")
		or tostring(value):match("^rbxassetid://(%d+)$")
	assert(
		id and #id <= 20 and tonumber(id) > 0,
		"Enter an image asset ID or choose a built-in frame."
	)
	return "rbxassetid://" .. id
end

function Objects.paintImpact(frame, image, color, transparency)
	local current = frame:FindFirstChild("ImpactImage")
	if frame:GetAttribute("ImpactImage") ~= image then
		if current then
			current:Destroy()
		end

		frame:SetAttribute("ImpactImage", image)
		current = Instance.new("CanvasGroup")
		current.Name = "ImpactImage"
		current.Size = UDim2.fromScale(1, 1)
		current.BackgroundTransparency = 1
		current.BorderSizePixel = 0
		current.ClipsDescendants = true
		current.Parent = frame
		if image:sub(1, 8) == "builtin:" then
			local inverse = image == "builtin:Inverse"
			local white = image == "builtin:White"
			current.BackgroundTransparency = 0
			current.BackgroundColor3 = (white or inverse) and Color3.new(1, 1, 1) or Color3.new()
			if image == "builtin:Burst" or inverse then
				for n = 0, 23 do
					local ray = Instance.new("Frame")
					ray.Name = "Ray"
					ray.AnchorPoint = Vector2.new(0.5, 0.5)
					ray.Position = UDim2.fromScale(0.5, 0.5)
					ray.Size = UDim2.fromScale(2, n % 3 == 0 and 0.045 or 0.012)
					ray.Rotation = n * 15 + 7
					ray.BorderSizePixel = 0
					ray.BackgroundColor3 = inverse and Color3.new() or Color3.new(1, 1, 1)
					ray.Parent = current
				end

				local core = Instance.new("Frame")
				core.Name = "Core"
				core.AnchorPoint = Vector2.new(0.5, 0.5)
				core.Position = UDim2.fromScale(0.5, 0.5)
				core.Size = UDim2.fromScale(0.18, 0.3)
				core.BorderSizePixel = 0
				core.BackgroundColor3 = current.BackgroundColor3
				core.Parent = current
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = core
			end
		elseif image ~= "" then
			local picture = Instance.new("ImageLabel")
			picture.Name = "Picture"
			picture.Size = UDim2.fromScale(1, 1)
			picture.BackgroundTransparency = 1
			picture.Image = image
			picture.ScaleType = Enum.ScaleType.Stretch
			picture.Parent = current
		end
	end

	if current then
		current.GroupTransparency = image == "" and 1 or transparency
		current.GroupColor3 = color
	end
end

function Objects.overlay(model, parent)
	local frame = Instance.new("CanvasGroup")
	frame.Name = model.Name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Interactable = false
	frame.Parent = parent
	if Objects.kind(model) == "Vignette" then
		for i, t in
			{
				{ 0, 0, 1024 / 1920, 1024 / 1080 },
				{ 1024 / 1920, 0, 896 / 1920, 1024 / 1080 },
				{ 0, 1024 / 1080, 1024 / 1920, 56 / 1080 },
				{ 1024 / 1920, 1024 / 1080, 896 / 1920, 56 / 1080 },
			}
		do
			local tile = Instance.new("ImageLabel")
			tile.Name = "Tile" .. i
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.Position = UDim2.fromScale(t[1] + t[3] * 0.5, t[2] + t[4] * 0.5)
			tile.Size = UDim2.fromScale(t[3], t[4])
			tile.BackgroundTransparency = 1
			tile.Active = false
			tile.Interactable = false
			tile.Parent = frame
		end
	end

	local gradient = Instance.new("UIGradient")
	gradient.Name = "EffectGradient"
	gradient.Parent = frame
	return frame
end

function Objects.paintOverlay(model, frame, visible)
	local color = Objects.read(model, "Color")
	local gradient = frame:FindFirstChild("EffectGradient")
	local isGradient = Objects.read(model, "Gradient")
	gradient.Enabled = isGradient
	gradient.Color = ColorSequence.new(color, Objects.read(model, "Color2"))
	gradient.Rotation = Objects.read(model, "GradientRotation")
	if isGradient then
		color = Color3.new(1, 1, 1)
	end

	local transparency = visible and math.clamp(Objects.read(model, "Transparency"), 0, 1) or 1
	local size, position =
		Objects.kind(model) == "Vignette" and Vector2.one or Objects.read(model, "Size"),
		Objects.kind(model) == "Vignette" and Vector2.zero or Objects.read(model, "Position")
	frame.Size = UDim2.fromScale(math.max(0.01, size.X), math.max(0.01, size.Y))
	frame.Position = UDim2.fromScale(0.5 + position.X, 0.5 + position.Y)
	frame.Rotation = Objects.kind(model) == "Vignette" and 0 or Objects.read(model, "Rotation")
	if Objects.kind(model) == "Impact Frames" then
		Objects.paintImpact(frame, Objects.read(model, "Image") or "", color, transparency)
	elseif Objects.kind(model) == "Screen Cover" then
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency
	else
		for i = 1, 4 do
			local tile = frame["Tile" .. i]
			local id = tostring(model:GetAttribute("VignetteImage" .. i) or Objects.images[i])
			tile.Image = "rbxassetid://" .. (replacedImages[id] or id)
			tile.ImageColor3 = color
			tile.ImageTransparency = transparency
		end
	end
end

return Objects
