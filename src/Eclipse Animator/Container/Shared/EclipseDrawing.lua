--// cracked by numan

local Drawing = { Version = 1 }

local function number(v, low, high, label)
	assert(type(v) == "number" and v == v and v >= low and v <= high, "Invalid drawing " .. label)
	return v
end

local function text(v, label)
	assert(type(v) == "string" and #v > 0 and #v <= 96, "Invalid drawing " .. label)
end

function Drawing.empty()
	return { version = 1, layers = {} }
end

function Drawing.copy(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for k, v in value do
		result[k] = Drawing.copy(v)
	end

	return result
end

function Drawing.style()
	return {
		width = 0.12,
		opacity = 1,
		taperStart = 0,
		taperEnd = 0,
		gradient = "Path",
		angle = 0,
		stops = {
			{ at = 0, color = Color3.fromRGB(220, 155, 255), alpha = 1 },
			{ at = 1, color = Color3.fromRGB(110, 220, 255), alpha = 1 },
		},
		space = "World",
		reveal = 0,
		fadeIn = 0,
		fadeOut = 0,
	}
end

function Drawing.validate(value)
	assert(
		type(value) == "table" and value.version == 1 and type(value.layers) == "table",
		"Unsupported Grease Pencil data"
	)
	assert(#value.layers <= 24, "Grease Pencil supports up to 24 layers")
	local ids, strokes, points, keys = {}, 0, 0, 0
	local exposure = {}

	local function id(v)
		text(v, "id")
		assert(not ids[v], "Duplicate drawing id")
		ids[v] = true
	end

	for _, layer in value.layers do
		id(layer.id)
		text(layer.name, "layer name")
		assert(
			type(layer.visible) == "boolean" and type(layer.locked) == "boolean",
			"Invalid drawing layer flags"
		)
		number(layer.opacity, 0, 1, "layer opacity")
		assert(type(layer.keys) == "table", "Invalid drawing keys")
		local last = -1
		for keyIndex, key in layer.keys do
			local keyPoints = 0
			keys += 1
			assert(keys <= 512, "Grease Pencil supports up to 512 drawings")
			number(key.frame, 0, 1000000, "frame")
			number(key.duration, 1, 1000000, "duration")
			assert(
				key.frame % 1 == 0 and key.duration % 1 == 0 and key.frame > last,
				"Drawing frames must be unique and sorted"
			)
			last = key.frame
			assert(type(key.strokes) == "table", "Invalid drawing strokes")
			for _, stroke in key.strokes do
				strokes += 1
				assert(strokes <= 2048, "Grease Pencil supports up to 2048 saved strokes")
				id(stroke.id)
				assert(
					type(stroke.points) == "table" and #stroke.points >= 2 and #stroke.points <= 512,
					"A stroke needs 2–512 points"
				)
				points += #stroke.points
				assert(points <= 65536, "Grease Pencil project point limit reached")
				keyPoints += #stroke.points
				if stroke.plane then
					assert(typeof(stroke.plane) == "CFrame", "Invalid drawing plane")
					for _, component in { stroke.plane:GetComponents() } do
						number(component, -1000000, 1000000, "plane")
					end
				end

				for _, p in stroke.points do
					assert(
						typeof(p) == "Vector3"
							and p.Magnitude == p.Magnitude
							and p.Magnitude < 1000000,
						"Invalid drawing point"
					)
				end

				local s = stroke.style
				assert(type(s) == "table", "Invalid drawing brush")
				number(s.width, 0.001, 100, "width")
				number(s.opacity, 0, 1, "opacity")
				number(s.taperStart, 0, 1, "start taper")
				number(s.taperEnd, 0, 1, "end taper")
				number(s.angle, -360, 360, "gradient angle")
				number(s.reveal, 0, 1000000, "reveal")
				number(s.fadeIn, 0, 1000000, "fade in")
				number(s.fadeOut, 0, 1000000, "fade out")
				assert(s.space == "World" or s.space == "Camera", "Invalid drawing space")
				assert(
					s.gradient == "Path" or s.gradient == "Linear" or s.gradient == "Radial",
					"Invalid gradient mode"
				)
				assert(
					type(s.stops) == "table" and #s.stops >= 2 and #s.stops <= 8,
					"A gradient needs 2–8 stops"
				)
				local previous = -1
				for i, stop in s.stops do
					number(stop.at, 0, 1, "gradient stop")
					number(stop.alpha, 0, 1, "stop opacity")
					assert(
						stop.at > previous and typeof(stop.color) == "Color3",
						"Gradient stops must be ordered"
					)
					for _, c in { stop.color.R, stop.color.G, stop.color.B } do
						number(c, 0, 1, "color")
					end

					previous = stop.at
				end
			end
		end
	end

	for _, layer in value.layers do
		if not layer.visible then
			continue
		end

		for i, key in layer.keys do
			local count = 0
			for _, stroke in key.strokes do
				count += #stroke.points
			end

			local finish = math.min(
				key.frame + key.duration,
				layer.keys[i + 1] and layer.keys[i + 1].frame or math.huge
			)
			exposure[key.frame] = (exposure[key.frame] or 0) + count
			exposure[finish] = (exposure[finish] or 0) - count
		end
	end

	local times = {}
	for at in exposure do
		table.insert(times, at)
	end

	table.sort(times)
	local active = 0
	for _, at in times do
		active += exposure[at]
		assert(active <= 8192, "Too many simultaneous drawing points (8192 maximum)")
	end

	return value
end

function Drawing.keyAt(layer, frame)
	local result
	for _, key in layer.keys do
		if key.frame > frame then
			break
		end

		result = key
	end

	return result and frame < result.frame + result.duration and result or nil
end

function Drawing.lastFrame(value)
	local last = 0
	for _, layer in value.layers do
		if layer.visible then
			for _, key in layer.keys do
				if #key.strokes > 0 then
					last = math.max(last, key.frame + key.duration - 1)
				end
			end
		end
	end

	return last
end

function Drawing.color(style, t)
	t = math.clamp(t, 0, 1)
	for i = 2, #style.stops do
		local a, b = style.stops[i - 1], style.stops[i]
		if t <= b.at then
			local f = math.clamp((t - a.at) / (b.at - a.at), 0, 1)
			return a.color:Lerp(b.color, f), a.alpha + (b.alpha - a.alpha) * f
		end
	end

	local s = style.stops[#style.stops]
	return s.color, s.alpha
end

function Drawing.width(style, t)
	local scale = 1
	if style.taperStart > 0 then
		scale = math.min(scale, t / style.taperStart)
	end

	if style.taperEnd > 0 then
		scale = math.min(scale, (1 - t) / style.taperEnd)
	end

	return style.width * math.clamp(scale, 0, 1)
end

local function gradientCoordinates(stroke)
	local points, style = stroke.points, stroke.style
	local lengths, total = { 0 }, 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		lengths[i] = total
	end

	local direction =
		Vector3.new(math.cos(math.rad(style.angle)), math.sin(math.rad(style.angle)), 0)
	if stroke.plane then
		direction = stroke.plane:VectorToWorldSpace(direction)
	end

	local low, high = math.huge, -math.huge
	local center = Vector3.zero
	for _, p in points do
		center += p
	end

	center /= #points
	local radius = 0
	for _, p in points do
		local d = p:Dot(direction)
		low = math.min(low, d)
		high = math.max(high, d)
		radius = math.max(radius, (p - center).Magnitude)
	end

	local result, path = {}, {}
	for i, p in points do
		path[i] = total > 1e-7 and lengths[i] / total or (i - 1) / (#points - 1)
		result[i] = style.gradient == "Linear"
				and (p:Dot(direction) - low) / math.max(high - low, 1e-7)
			or style.gradient == "Radial" and (p - center).Magnitude / math.max(radius, 1e-7)
			or path[i]
	end

	return result, path, center, radius
end

function Drawing.new(parent)
	local root = Instance.new("Folder")
	root.Name = "EclipseDrawings"
	root.Archivable = false
	root.Parent = parent
	local self = { root = root, cache = {}, destroyed = false }

	function self:clear()
		for _, entry in self.cache do
			entry.root:Destroy()
		end

		table.clear(self.cache)
		self.previous = nil
	end

	function self:destroy()
		if self.destroyed then
			return
		end

		self.destroyed = true
		self:clear()
		self.root:Destroy()
	end

	local function update(entry, stroke)
		local holder = entry.root
		entry.stroke = stroke
		entry.gradient, entry.path, entry.center, entry.radius = gradientCoordinates(stroke)
		entry.painted = {}
		entry.renderOpacity, entry.renderReveal = nil, nil
		entry.viewNormal = nil
		for i, point in stroke.points do
			local attachment = entry.attachments[i]
			if not attachment then
				attachment = Instance.new("Attachment")
				attachment.Parent = holder
				entry.attachments[i] = attachment
			end

			local before = stroke.points[math.max(1, i - 1)]
			local after = stroke.points[math.min(#stroke.points, i + 1)]
			local tangent = after - before
			if tangent.Magnitude < 1e-7 then
				tangent = Vector3.xAxis
			end

			tangent = tangent.Unit
			local up = math.abs(tangent:Dot(Vector3.yAxis)) > 0.99 and Vector3.zAxis
				or Vector3.yAxis
			local z = tangent:Cross(up).Unit
			attachment.CFrame = CFrame.fromMatrix(point, tangent, z:Cross(tangent), z)
			if i > 1 then
				local beam = entry.beams[i]
				if not beam then
					beam = Instance.new("Beam")
					beam.FaceCamera = false
					beam.LightEmission = 0
					beam.LightInfluence = 0
					beam.Attachment0 = entry.attachments[i - 1]
					beam.Attachment1 = attachment
					beam.Parent = holder
					entry.beams[i] = beam
				end

				local length = (point - stroke.points[i - 1]).Magnitude
				local direction = length > 1e-7 and (point - stroke.points[i - 1]) / length
					or tangent
				local bend = math.max(
					math.acos(
						math.clamp(
							entry.attachments[i - 1].CFrame.RightVector:Dot(direction),
							-1,
							1
						)
					),
					math.acos(math.clamp(tangent:Dot(direction), -1, 1))
				)
				beam.Segments = math.clamp(math.ceil(bend * 48), 1, 32)
				beam.CurveSize0 = length / 3
				beam.CurveSize1 = length / 3
				beam.Width0 = Drawing.width(stroke.style, entry.path[i - 1])
				beam.Width1 = Drawing.width(stroke.style, entry.path[i])
			end
		end

		for i = #entry.attachments, #stroke.points + 1, -1 do
			entry.attachments[i]:Destroy()
			entry.attachments[i] = nil
			if entry.beams[i] then
				entry.beams[i]:Destroy()
				entry.beams[i] = nil
			end
		end
	end

	local function orient(entry, cameraFrame)
		local normal = Vector3.zAxis
		if entry.stroke.style.space == "World" then
			local offset = cameraFrame.Position - entry.stroke.points[1]
			normal = offset.Magnitude > 1e-7 and offset.Unit or -cameraFrame.LookVector
		end

		if entry.viewNormal and entry.viewNormal:Dot(normal) > 0.9999 then
			return
		end

		entry.viewNormal = normal
		for _, attachment in entry.attachments do
			local tangent = attachment.CFrame.RightVector
			local up = normal:Cross(tangent)
			if up.Magnitude < 1e-7 then
				up = attachment.CFrame.UpVector
			else
				up = up.Unit
			end

			attachment.CFrame =
				CFrame.fromMatrix(attachment.Position, tangent, up, tangent:Cross(up))
		end
	end

	local function create(stroke)
		local holder = Instance.new("Part")
		holder.Name = stroke.id
		holder.Size = Vector3.one * 0.01
		holder.Transparency = 1
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanTouch = false
		holder.CanQuery = false
		holder.CastShadow = false
		holder.Locked = true
		holder.Archivable = false
		holder.CFrame = CFrame.identity
		local entry = { root = holder, attachments = {}, beams = {} }
		update(entry, stroke)
		holder.Parent = root
		return entry
	end

	local function paint(entry, index, fraction, opacity)
		local old = entry.painted[index]
		if old and old.fraction == fraction and old.opacity == opacity then
			return
		end

		entry.painted[index] = { fraction = fraction, opacity = opacity }
		local style = entry.stroke.style
		local g0, g1 = entry.gradient[index - 1], entry.gradient[index]
		local a, b = entry.stroke.points[index - 1], entry.stroke.points[index]
		local delta = (b - a) * fraction
		local radial = style.gradient == "Radial"
		local times = { 0, 1 }

		local function add(t)
			if t > 0.00001 and t < 0.99999 then
				table.insert(times, t)
			end
		end

		if radial then
			local offset = a - entry.center
			local qa = delta:Dot(delta)
			local qb = 2 * offset:Dot(delta)
			if qa > 1e-12 then
				add(-qb / (2 * qa))
				for _, stop in style.stops do
					local qc = offset:Dot(offset) - (stop.at * entry.radius) ^ 2
					local discriminant = qb * qb - 4 * qa * qc
					if discriminant >= 0 then
						local d = math.sqrt(discriminant)
						add((-qb - d) / (2 * qa))
						add((-qb + d) / (2 * qa))
					end
				end
			end
		elseif math.abs((g1 - g0) * fraction) > 1e-8 then
			for _, stop in style.stops do
				add((stop.at - g0) / ((g1 - g0) * fraction))
			end
		end

		table.sort(times)
		local colors, alphas = {}, {}
		local previous = -1
		for _, t in times do
			if t - previous < 0.00001 then
				continue
			end

			previous = t
			local coordinate = radial
					and (a + delta * t - entry.center).Magnitude / math.max(entry.radius, 1e-8)
				or g0 + (g1 - g0) * fraction * t
			local color, alpha = Drawing.color(style, coordinate)
			table.insert(colors, ColorSequenceKeypoint.new(t, color))
			table.insert(alphas, NumberSequenceKeypoint.new(t, 1 - opacity * alpha))
		end

		local beam = entry.beams[index]
		local length = (b - a).Magnitude * fraction
		beam.CurveSize0 = length / 3
		beam.CurveSize1 = length / 3
		beam.Color = ColorSequence.new(colors)
		beam.Transparency = NumberSequence.new(alphas)
		beam.Width1 = Drawing.width(
			style,
			entry.path[index - 1] + (entry.path[index] - entry.path[index - 1]) * fraction
		)
	end

	function self:step(value, frame, cameraFrame, enabled, onionLayer)
		if self.destroyed then
			return
		end

		local previous = self.previous
		if
			previous
			and previous.value == value
			and previous.frame == frame
			and previous.enabled == enabled
			and previous.onion == onionLayer
		then
			if previous.camera ~= cameraFrame then
				for _, entry in self.cache do
					if entry.stroke.style.space == "Camera" then
						entry.root.CFrame = cameraFrame
					end

					orient(entry, cameraFrame)
				end

				previous.camera = cameraFrame
			end

			return
		end

		self.previous = {
			value = value,
			frame = frame,
			camera = cameraFrame,
			enabled = enabled,
			onion = onionLayer,
		}
		local wanted, count = {}, 0
		if enabled ~= false then
			for _, layer in value.layers do
				if not layer.visible then
					continue
				end

				local key = Drawing.keyAt(layer, frame)
				local shown = {}
				if key then
					shown[1] = { key = key, alpha = 1 }
				end

				if layer.id == onionLayer then
					local previous, following
					for _, k in layer.keys do
						if k.frame < (key and key.frame or frame) then
							previous = k
						elseif k.frame > frame then
							following = k
							break
						end
					end

					if previous then
						table.insert(shown, { key = previous, alpha = 0.18 })
					end

					if following then
						table.insert(shown, { key = following, alpha = 0.12 })
					end
				end

				for _, display in shown do
					for _, stroke in display.key.strokes do
						if count + #stroke.points > 24576 then
							continue
						end

						count += #stroke.points
						wanted[stroke.id] = true
						local entry = self.cache[stroke.id]
						if entry and entry.stroke ~= stroke then
							update(entry, stroke)
						end

						if not entry then
							entry = create(stroke)
							self.cache[stroke.id] = entry
						end

						local s = stroke.style
						local transform = s.space == "Camera" and cameraFrame or CFrame.identity
						if entry.root.CFrame ~= transform then
							entry.root.CFrame = transform
						end

						orient(entry, cameraFrame)
						local age = display.alpha < 1 and display.key.duration
							or frame - display.key.frame
						local opacity = layer.opacity * s.opacity * display.alpha
						if display.alpha == 1 then
							if s.fadeIn > 0 then
								opacity *= math.clamp(age / s.fadeIn, 0, 1)
							end

							if s.fadeOut > 0 then
								opacity *= math.clamp(
									(display.key.frame + display.key.duration - frame) / s.fadeOut,
									0,
									1
								)
							end
						end

						local reveal = s.reveal > 0 and math.clamp(age / s.reveal, 0, 1) or 1
						if entry.renderOpacity == opacity and entry.renderReveal == reveal then
							continue
						end

						entry.renderOpacity, entry.renderReveal = opacity, reveal
						for i, beam in entry.beams do
							beam.Enabled = opacity > 0 and entry.path[i - 1] < reveal
							if beam.Enabled then
								local fraction = math.clamp(
									(reveal - entry.path[i - 1])
										/ math.max(1e-8, entry.path[i] - entry.path[i - 1]),
									0,
									1
								)
								entry.attachments[i].Position =
									stroke.points[i - 1]:Lerp(stroke.points[i], fraction)
								paint(entry, i, fraction, opacity)
							end
						end
					end
				end
			end
		end

		for id, entry in self.cache do
			if not wanted[id] then
				entry.root:Destroy()
				self.cache[id] = nil
			end
		end
	end

	return self
end

return Drawing
