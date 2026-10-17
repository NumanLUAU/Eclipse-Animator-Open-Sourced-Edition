--!nocheck
--// cracked by numan

return function(require)
	local VFX = {}
	local cache = setmetatable({}, { __mode = "k" })
	local function sample(sequence, t)
		local a = sequence.Keypoints[1]
		for i = 2, #sequence.Keypoints do
			local b = sequence.Keypoints[i]
			if t <= b.Time then
				local f = (t - a.Time) / math.max(1e-6, b.Time - a.Time)
				return typeof(a.Value) == "Color3" and a.Value:Lerp(b.Value, f)
					or a.Value + (b.Value - a.Value) * f
			end
			a = b
		end
		return a.Value
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
					s.gui.Enabled = false
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
		for _, s in surfaces do
			s.gui.Enabled = true
			s.gui.AlwaysOnTop = true
			for _, entry in s.rows do
				local object = entry.object
				if object:IsA("Beam") then
					local a, b = object.Attachment0.Position, object.Attachment1.Position
					local delta = b - a
					local length = math.max(0.001, delta.Magnitude)
					local textureLength = object.TextureMode == Enum.TextureMode.Stretch
							and length / math.max(0.01, object.TextureLength)
						or math.max(0.01, object.TextureLength)
					local offset = (time * (entry.source.props.TextureSpeed or 0)) % 1
					for _, slice in entry.slices do
						local t = slice.t
						local center = a:Lerp(b, t)
						local width = object.Width0 + (object.Width1 - object.Width0) * t
						local clip = slice.clip
						clip.Visible = entry.source.props.Enabled ~= false and width > 0.00001
						clip.Position = UDim2.fromScale(
							0.5 + s.flip * center.X / part.Size.X,
							0.5 - center.Y / part.Size.Y
						)
						local horizontal = math.abs(delta.X) >= math.abs(delta.Y)
						local along = horizontal and part.Size.X or part.Size.Y
						local across = horizontal and part.Size.Y or part.Size.X
						clip.Size = UDim2.fromScale(length / slice.count / along, width / across)
						clip.Rotation = math.deg(math.atan2(-delta.Y, s.flip * delta.X))

						local tile = textureLength / (length / slice.count)
						local phase = (offset + (t - 0.5 / slice.count) * length / textureLength)
							% 1
						for j, i in slice.images do
							i.Size = UDim2.fromScale(tile, 1)
							i.Position = UDim2.fromScale((j - 1 - phase) * tile, 0.5)
							i.ImageColor3 = sample(object.Color, t)
							i.ImageTransparency = sample(object.Transparency, t)
						end
					end
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
						UDim2.fromScale(0.5 + s.flip * p.X / part.Size.X, 0.5 - p.Y / part.Size.Y)
					i.Size =
						UDim2.fromScale(size * squash / part.Size.X, size / squash / part.Size.Y)
					i.Rotation = (object.Rotation.Min + object.Rotation.Max) * 0.5
						+ time * (object.RotSpeed.Min + object.RotSpeed.Max) * 0.5
					i.ImageColor3 = sample(object.Color, age)
					i.ImageTransparency = sample(object.Transparency, age)
				end
			end
		end
	end
	return VFX
end
