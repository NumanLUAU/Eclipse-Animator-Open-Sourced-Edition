--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local VFX = {}
local cache = setmetatable({}, { __mode = "k" })

local function sample(sequence, t, keypoints)
	local points = keypoints or sequence.Keypoints
	local a = points[1]
	for i = 2, #points do
		local b = points[i]
		if t <= b.Time then
			local f = (t - a.Time) / math.max(1e-6, b.Time - a.Time)
			return typeof(a.Value) == "Color3" and a.Value:Lerp(b.Value, f)
				or a.Value + (b.Value - a.Value) * f
		end

		a = b
	end

	return a.Value
end

local function set(object, property, value)
	if object[property] ~= value then
		object[property] = value
	end
end

local function frame(parent)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	f.Active = false
	f.Interactable = false
	f.Parent = parent
	return f
end

local function image(parent, texture)
	local i = Instance.new("ImageLabel")
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.Image = texture
	i.Active = false
	i.Interactable = false
	i.Parent = parent
	return i
end

local function create(part, rows)
	local result = {}
	cache[part] = result
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "EffectVFX" .. face.Name
		gui.Archivable = false
		gui:SetAttribute("EclipseEffectSurface", true)
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(1024, 1024)
		gui.ClipsDescendants = false
		gui.Active = false
		gui.Parent = part
		local surface = { gui = gui, rows = {}, flip = face == Enum.NormalId.Front and -1 or 1 }
		table.insert(result, surface)
		for index, row in rows do
			local object = row.object
			local entry = { object = object, source = row, slices = {} }
			table.insert(surface.rows, entry)
			if object:IsA("Beam") then
				local count = math.abs(object.Width0 - object.Width1) > 0.001 and 32 or 1
				for i = 1, count do
					local clip = frame(gui)
					clip.Name = "Ribbon" .. index .. "_" .. i
					local images = {}
					for j = 1, 3 do
						images[j] = image(clip, object.Texture)
					end

					table.insert(
						entry.slices,
						{ clip = clip, images = images, t = (i - 0.5) / count, count = count }
					)
				end
			else
				entry.image = image(gui, object.Texture)
				entry.image.Name = "Flare" .. index
			end
		end
	end

	return result
end

function VFX.paint(part, rows, visible, time)
	local surfaces = cache[part]
	if not visible then
		if surfaces then
			for _, s in surfaces do
				set(s.gui, "Enabled", false)
			end
		end

		return
	end

	if not surfaces then
		for _, c in part:GetChildren() do
			if c:IsA("SurfaceGui") and c.Name:sub(1, 9) == "EffectVFX" then
				c:Destroy()
			end
		end

		surfaces = create(part, rows)
	end

	local partSize = part.Size
	for _, s in surfaces do
		set(s.gui, "Enabled", true)
		set(s.gui, "AlwaysOnTop", true)
		for _, entry in s.rows do
			local object = entry.object
			if object:IsA("Beam") then
				local a, b = object.Attachment0.Position, object.Attachment1.Position
				local width0, width1, mode, texture =
					object.Width0, object.Width1, object.TextureMode, object.TextureLength
				local enabled = entry.source.props.Enabled ~= false
				local geometry = entry.geometry
				local changed = not geometry
					or geometry.a ~= a
					or geometry.b ~= b
					or geometry.size ~= partSize
					or geometry.width0 ~= width0
					or geometry.width1 ~= width1
					or geometry.mode ~= mode
					or geometry.texture ~= texture
					or geometry.enabled ~= enabled
				local color, transparency = object.Color, object.Transparency
				local paintChanged = entry.color ~= color or entry.transparency ~= transparency
				local colorPoints = paintChanged and color.Keypoints
				local transparencyPoints = paintChanged and transparency.Keypoints
				local offset = (time * (entry.source.props.TextureSpeed or 0)) % 1
				local moving = changed or entry.offset ~= offset
				if changed then
					local delta = b - a
					local length = math.max(0.001, delta.Magnitude)
					local textureLength = mode == Enum.TextureMode.Stretch
							and length / math.max(0.01, texture)
						or math.max(0.01, texture)
					local horizontal = math.abs(delta.X) >= math.abs(delta.Y)
					geometry = {
						a = a,
						b = b,
						size = partSize,
						width0 = width0,
						width1 = width1,
						mode = mode,
						texture = texture,
						enabled = enabled,
						length = length,
						textureLength = textureLength,
						along = horizontal and partSize.X or partSize.Y,
						across = horizontal and partSize.Y or partSize.X,
						rotation = math.deg(math.atan2(-delta.Y, s.flip * delta.X)),
					}
					entry.geometry = geometry
				end

				if not changed and not paintChanged and not moving then
					continue
				end

				for _, slice in entry.slices do
					local t = slice.t
					if changed then
						local center = a:Lerp(b, t)
						local width = width0 + (width1 - width0) * t
						local clip = slice.clip
						set(clip, "Visible", enabled and width > 0.00001)
						set(
							clip,
							"Position",
							UDim2.fromScale(
								0.5 + s.flip * center.X / partSize.X,
								0.5 - center.Y / partSize.Y
							)
						)
						set(
							clip,
							"Size",
							UDim2.fromScale(
								geometry.length / slice.count / geometry.along,
								width / geometry.across
							)
						)
						set(clip, "Rotation", geometry.rotation)
						slice.tile = geometry.textureLength / (geometry.length / slice.count)
						slice.phase = (t - 0.5 / slice.count)
							* geometry.length
							/ geometry.textureLength
					end

					local tile = slice.tile
					local phase = (offset + slice.phase) % 1
					local tint = paintChanged and sample(color, t, colorPoints)
					local alpha = paintChanged and sample(transparency, t, transparencyPoints)
					for j, i in slice.images do
						if changed then
							set(i, "Size", UDim2.fromScale(tile, 1))
						end

						if moving then
							set(i, "Position", UDim2.fromScale((j - 1 - phase) * tile, 0.5))
						end

						if paintChanged then
							set(i, "ImageColor3", tint)
							set(i, "ImageTransparency", alpha)
						end
					end
				end

				entry.color, entry.transparency, entry.offset = color, transparency, offset
			else
				local life = math.max(0.001, (object.Lifetime.Min + object.Lifetime.Max) * 0.5)
				local age = (time * object.TimeScale % life) / life
				local size = sample(object.Size, age)
				local squash = math.max(0.05, 1 + sample(object.Squash, age))
				local attachment = object.Parent
				local p = attachment:IsA("Attachment") and attachment.Position or Vector3.zero
				local i = entry.image
				i.Visible = entry.source.props.Enabled ~= false
				i.Position =
					UDim2.fromScale(0.5 + s.flip * p.X / partSize.X, 0.5 - p.Y / partSize.Y)
				i.Size = UDim2.fromScale(size * squash / partSize.X, size / squash / partSize.Y)
				i.Rotation = (object.Rotation.Min + object.Rotation.Max) * 0.5
					+ time * (object.RotSpeed.Min + object.RotSpeed.Max) * 0.5
				i.ImageColor3 = sample(object.Color, age)
				i.ImageTransparency = sample(object.Transparency, age)
			end
		end
	end
end

return VFX
