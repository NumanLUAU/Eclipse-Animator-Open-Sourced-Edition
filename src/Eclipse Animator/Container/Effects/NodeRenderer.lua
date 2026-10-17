--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Model = require("Model")
local Recovery = require("Recovery")
local Renderer = {}
Renderer.__index = Renderer

local function decode(v, nodes)
	if type(v) ~= "table" then
		return v
	end

	local t, a = v.t, v.v
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
		return Enum[v.e][a]
	elseif t == "Ref" then
		return nodes[a]
	elseif t == "NumberSequence" then
		local k = {}
		for _, p in a do
			table.insert(k, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
		end

		return NumberSequence.new(k)
	elseif t == "ColorSequence" then
		local k = {}
		for _, p in a do
			table.insert(k, ColorSequenceKeypoint.new(p[1], decode(p[2])))
		end

		return ColorSequence.new(k)
	end

	error("Unsupported effect asset value: " .. tostring(t))
end

local function sequence(sequence, fn)
	local result = {}
	for _, k in sequence.Keypoints do
		table.insert(result, NumberSequenceKeypoint.new(k.Time, fn(k.Value), 0))
	end

	return NumberSequence.new(result)
end

local function sample(seq, t)
	local keys = seq.Keypoints
	local left = keys[1]
	for i = 2, #keys do
		local right = keys[i]
		if t <= right.Time then
			local f = (t - left.Time) / math.max(0.000001, right.Time - left.Time)
			if typeof(left.Value) == "Color3" then
				return left.Value:Lerp(right.Value, f)
			end

			return left.Value + (right.Value - left.Value) * f
		end

		left = right
	end

	return left.Value
end

local function tint(c, t)
	return Color3.new(c.R * t.R, c.G * t.G, c.B * t.B)
end

local function part(parent, name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Locked = true
	p.Material = Enum.Material.Neon
	p.Size = Vector3.one
	p.Transparency = 1
	p.Parent = parent
	return p
end

function Renderer.new(guiParent, displayOrder, worldParent)
	return setmetatable({
		guiParent = guiParent,
		displayOrder = displayOrder or -5,
		worldParent = worldParent,
		visuals = {},
	}, Renderer)
end

function Renderer:clear()
	for _, v in self.visuals do
		v.root:Destroy()
	end

	table.clear(self.visuals)
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end

	if self.world then
		self.world:Destroy()
		self.world = nil
	end
end

function Renderer:roots()
	if not self.gui then
		local gui = Instance.new("ScreenGui")
		gui.Name = "EclipseScreenEffects"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = self.displayOrder
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui:SetAttribute("EclipseOwnedUI", true)
		Recovery.mark(gui)
		gui.Parent = self.guiParent
		self.gui = gui
	end

	local parent = self.worldParent or workspace.CurrentCamera
	if not self.world then
		local folder = Instance.new("Folder")
		folder.Name = "EclipseLetterboxEffects"
		Recovery.mark(folder)
		self.world = folder
	end

	self.world.Parent = parent
end

function Renderer:create(effect)
	self:roots()
	if effect.kind ~= "Letterbox" then
		local frame = Instance.new("Frame")
		frame.Name = effect.kind
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Interactable = false
		frame.Parent = self.gui
		local visual = { root = frame, kind = effect.kind, style = effect.style, images = {} }
		if effect.kind == "Vignette" then
			for i = 1, 96 do
				local strip = Instance.new("Frame")
				strip.Name = "Mask" .. i
				strip.BorderSizePixel = 0
				strip.Position = UDim2.fromScale((i - 1) / 96, 0)
				strip.Size = UDim2.fromScale(1 / 96, 1)
				strip.Active = false
				strip.Interactable = false
				local x = (i - 0.5) / 96 * 2 - 1
				local keys = {}
				for j = 0, 19 do
					local y = j / 19 * 2 - 1
					local opacity = math.clamp((math.sqrt(x * x + y * y) - 0.35) / 0.9, 0, 1) ^ 1.7
					table.insert(keys, NumberSequenceKeypoint.new(j / 19, 1 - opacity))
				end

				local gradient = Instance.new("UIGradient")
				gradient.Rotation = 90
				gradient.Transparency = NumberSequence.new(keys)
				gradient.Parent = strip
				strip.Parent = frame
				table.insert(visual.images, strip)
			end
		end

		return visual
	end

	local folder = Instance.new("Folder")
	folder.Name = "Letterbox"
	folder.Parent = self.world
	local visual = {
		root = folder,
		kind = effect.kind,
		style = effect.style,
		beams = {},
		attachments = {},
		flares = {},
	}
	if effect.style == "Solid" then
		visual.top = part(folder, "Top")
		visual.bottom = part(folder, "Bottom")
		return visual
	end

	local asset = assert(Model.catalog[effect.style])
	local nodes = {}
	for i, row in asset.nodes do
		nodes[i] = Instance.new(row.class)
		nodes[i].Name = row.name
	end

	for i, row in asset.nodes do
		local object = nodes[i]
		for key, value in row.properties do
			object[key] = decode(value, nodes)
		end

		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.CastShadow = false
			object.Locked = true
			object.Transparency = 1
			visual.part = object
			visual.originalSize = object.Size
		end

		if object:IsA("Attachment") then
			table.insert(visual.attachments, { object = object, cf = object.CFrame })
		end

		if object:IsA("Beam") then
			table.insert(visual.beams, {
				object = object,
				alpha = object.Transparency,
				color = object.Color,
				width0 = object.Width0,
				width1 = object.Width1,
				curve0 = object.CurveSize0,
				curve1 = object.CurveSize1,
				speed = object.TextureSpeed,
				enabled = object.Enabled,
			})
			object.TextureSpeed = 0
		end

		object.Parent = row.parent and nodes[row.parent] or folder
	end

	for _, object in nodes do
		if object:IsA("ParticleEmitter") then
			object.Enabled = false
			local attachment = object.Parent
			if not attachment:IsA("Attachment") then
				local a = Instance.new("Attachment")
				a.Parent = attachment
				attachment = a
			end

			local gui = Instance.new("BillboardGui")
			gui.Name = "ScrubbableFlare"
			gui.Adornee = attachment
			gui.AlwaysOnTop = false
			gui.LightInfluence = 0
			gui.Parent = attachment
			local image = Instance.new("ImageLabel")
			image.Size = UDim2.fromScale(1, 1)
			image.BackgroundTransparency = 1
			image.Image = object.Texture
			image.Parent = gui
			table.insert(visual.flares, { source = object, gui = gui, image = image })
		end
	end

	return visual
end

function Renderer:update(entries, frame, fps, cameraFor)
	if self.world and not self.world.Parent or self.gui and not self.gui.Parent then
		self:clear()
	end

	local used = {}
	for order, entry in entries do
		local effect, id = entry.value, entry.id
		local alpha = Model.alpha(effect, frame)
		local camera = effect.kind == "Letterbox" and cameraFor(effect.cameraId) or nil
		if alpha <= 0 or effect.kind == "Letterbox" and not camera then
			continue
		end

		used[id] = true
		local v = self.visuals[id]
		if v and (v.kind ~= effect.kind or v.style ~= effect.style) then
			v.root:Destroy()
			v = nil
		end

		if not v then
			v = self:create(effect)
			self.visuals[id] = v
		end

		local color = Color3.new(table.unpack(effect.color))
		if effect.kind ~= "Letterbox" then
			v.root.ZIndex = order
			if effect.kind == "Screen Cover" then
				v.root.BackgroundColor3 = color
				v.root.BackgroundTransparency = 1 - alpha
			else
				if v.lastColor ~= color then
					for _, strip in v.images do
						strip.BackgroundColor3 = color
					end

					v.lastColor = color
				end

				if v.lastAlpha ~= alpha then
					for _, strip in v.images do
						strip.BackgroundTransparency = 1 - alpha
					end

					v.lastAlpha = alpha
				end
			end
		else
			local depth = 1.2 + order * 0.002
			local h = 2 * depth * math.tan(math.rad(camera.fov) * 0.5)
			local w = h * camera.aspect
			local cf = camera.cf * CFrame.new(0, 0, -depth)
			if v.top then
				local height = h * effect.height
				for sign, p in { [1] = v.top, [-1] = v.bottom } do
					p.Size = Vector3.new(w * 1.01, height, 0.005)
					p.CFrame = cf * CFrame.new(0, sign * (h - height) * 0.5, 0)
					p.Color = color
					p.Transparency = 1 - alpha
				end
			else
				v.part.CFrame = cf
				local sx, sy = w / v.originalSize.X, h / v.originalSize.Y
				v.part.Size = Vector3.new(w, h, 0.01)
				for _, a in v.attachments do
					local p = a.cf.Position
					a.object.CFrame = CFrame.new(p.X * sx, p.Y * sy, p.Z * sy) * a.cf.Rotation
				end

				for _, b in v.beams do
					local o = b.object
					o.Width0 = b.width0 * sy * effect.scale
					o.Width1 = b.width1 * sy * effect.scale
					o.CurveSize0 = b.curve0 * sy
					o.CurveSize1 = b.curve1 * sy
					o.Enabled = b.enabled
					if b.lastAlpha ~= alpha then
						o.Transparency = sequence(b.alpha, function(x)
							return 1 - (1 - x) * alpha
						end)
						b.lastAlpha = alpha
					end

					if b.lastColor ~= color then
						local keys = {}
						for _, k in b.color.Keypoints do
							table.insert(
								keys,
								ColorSequenceKeypoint.new(k.Time, tint(k.Value, color))
							)
						end

						o.Color = ColorSequence.new(keys)
						b.lastColor = color
					end

					o:SetTextureOffset(((frame - effect.start) / fps * b.speed) % 1)
				end

				local time = (frame - effect.start) / fps
				for _, f in v.flares do
					local e = f.source
					local life = (e.Lifetime.Min + e.Lifetime.Max) * 0.5
					local age = (time * e.TimeScale % math.max(0.001, life)) / math.max(0.001, life)
					local size = math.max(0.001, sample(e.Size, age) * sy * effect.scale)
					local squash = sample(e.Squash, age)
					f.gui.Size = UDim2.fromScale(
						size * math.max(0.05, 1 + squash),
						size / math.max(0.05, 1 + squash)
					)
					f.image.Rotation = (e.Rotation.Min + e.Rotation.Max) * 0.5
						+ (e.RotSpeed.Min + e.RotSpeed.Max) * 0.5 * time
					f.image.ImageColor3 = tint(sample(e.Color, age), color)
					f.image.ImageTransparency = 1 - (1 - sample(e.Transparency, age)) * alpha
				end
			end
		end
	end

	for id, v in self.visuals do
		if not used[id] then
			v.root:Destroy()
			self.visuals[id] = nil
		end
	end

	if not next(used) then
		self:clear()
	elseif self.world then
		self.world.Parent = self.worldParent or workspace.CurrentCamera
	end
end

return Renderer
