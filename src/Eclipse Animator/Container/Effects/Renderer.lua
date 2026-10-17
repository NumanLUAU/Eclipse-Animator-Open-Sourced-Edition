--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("SubtitleData")
local Text = game:GetService("TextService")
local Http = game:GetService("HttpService")
local Renderer = {}
Renderer.__index = Renderer

local function make(class, parent, props)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end

	o.Parent = parent
	return o
end

local function font(style)
	local name = style.Font == "RobotoMono" and "RobotoMono" or style.Font
	local enum = Enum.Font[name == "RobotoMono" and "Code" or name]
	if style.Bold and name == "Gotham" then
		enum = Enum.Font.GothamBold
	elseif style.Bold and name == "SourceSans" then
		enum = Enum.Font.SourceSansBold
	end

	local f = name == "RobotoMono" and Font.new("rbxasset://fonts/families/RobotoMono.json")
		or Font.fromEnum(enum)
	return Font.new(
		f.Family,
		style.Bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular,
		style.Italic and Enum.FontStyle.Italic or Enum.FontStyle.Normal
	),
		enum
end

Renderer.font = font

function Renderer.new(parent)
	local root = make("Frame", parent, {
		Name = "EclipseSubtitles",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 240,
	})
	return setmetatable({ root = root, items = {} }, Renderer)
end

function Renderer:clear()
	for _, item in self.items do
		item.frame:Destroy()
	end

	table.clear(self.items)
	self.lastSignature = nil
end

function Renderer:destroy()
	self:clear()
	self.root:Destroy()
end

function Renderer.layout(style, width)
	local image = style.Image ~= "" and style.ImageSize or 0
	local horizontal = image > 0 and style.ImageSide ~= "Above"
	local textWidth = math.max(40, width - 2 * style.Padding - (horizontal and image + 12 or 0))
	local lines = { { width = 0, words = {} } }
	local words = {}
	local index, chars = 0, 0
	local paragraph = 1

	local function add(piece, wordStyle, wordIndex, prefix)
		local face, enum = font(wordStyle)
		local line = lines[#lines]
		if prefix:find("\n", 1, true) then
			line = { width = 0, words = {} }
			table.insert(lines, line)
			paragraph += 1
		end

		local gap = line.width > 0
				and Text:GetTextSize(" ", style.Size, enum, Vector2.new(10000, 10000)).X
			or 0
		local w = Text:GetTextSize(piece, style.Size, enum, Vector2.new(10000, 10000)).X + 2
		if line.width > 0 and line.width + gap + w > textWidth then
			line = { width = 0, words = {} }
			table.insert(lines, line)
			gap = 0
		end

		const class, rtl = Data.script(piece)
		local label = {
			text = piece,
			index = wordIndex,
			style = wordStyle,
			face = face,
			x = line.width + gap,
			width = math.min(w, textWidth),
			line = #lines,
			start = chars,
			space = gap > 0 and gap or nil,
			enum = enum,
			paragraph = paragraph,
			class = class,
			rtl = rtl,
		}
		for _ in utf8.graphemes(piece) do
			chars += 1
		end

		label.finish = chars
		table.insert(line.words, label)
		table.insert(words, label)
		line.width = label.x + label.width
	end

	for prefix, word in style.Text:gmatch("(%s*)(%S+)") do
		index += 1
		if index > 300 then
			break
		end

		local ws = table.clone(style)
		for k, v in style.Words[tostring(index)] or {} do
			ws[k] = v
		end

		local _, enum = font(ws)
		if Text:GetTextSize(word, style.Size, enum, Vector2.new(10000, 10000)).X <= textWidth then
			add(word, ws, index, prefix)
		else
			local piece = ""
			local first = true
			for first, last in utf8.graphemes(word) do
				local c = word:sub(first, last)
				if
					piece ~= ""
					and Text:GetTextSize(
							piece .. c,
							style.Size,
							enum,
							Vector2.new(10000, 10000)
						).X
						> textWidth
				then
					add(piece, ws, index, first and prefix or "")
					piece = ""
					first = false
				end

				piece ..= c
			end

			if piece ~= "" then
				add(piece, ws, index, first and prefix or "")
			end
		end
	end

	local base
	const paragraphs = {}
	for _, word in words do
		local group = paragraphs[word.paragraph]
		if not group then
			group = { words = {}, classes = {} }
			paragraphs[word.paragraph] = group
		end

		table.insert(group.words, word)
		table.insert(group.classes, word.class)
		if word.class == "R" or word.class == "L" then
			base = base or word.class
			group.direction = group.direction or word.class
		end

		group.mixed = group.mixed or word.rtl
	end

	for _, group in paragraphs do
		const rtl = group.direction == "R"
		if rtl or group.mixed then
			const levels = Data.levels(group.classes, rtl)
			const count = #group.words
			local first = 1
			while first <= count do
				const row = group.words[first].line
				local last = first
				while last < count and group.words[last + 1].line == row do
					last += 1
				end

				local cursor = 0
				for k, position in Data.reorder(levels, first, last) do
					const word = group.words[position]
					if k > 1 then
						cursor += word.space
							or Text:GetTextSize(" ", style.Size, word.enum, Vector2.new(10000, 10000)).X
					end

					word.x = cursor
					cursor += word.width
				end

				lines[row].width = cursor
				first = last + 1
			end
		end
	end

	local lineHeight = math.ceil(style.Size * 1.3)
	local nameHeight = style.Speaker ~= "" and math.ceil(style.NameSize * 1.3) + 6 or 0
	local textHeight = #lines * lineHeight + nameHeight
	local contentHeight = horizontal and math.max(textHeight, image)
		or textHeight + (image > 0 and image + 10 or 0)
	local x = style.Padding + (horizontal and style.ImageSide == "Left" and image + 12 or 0)
	local y = style.Padding
		+ (horizontal and (contentHeight - textHeight) * 0.5 or image > 0 and image + 10 or 0)
		+ nameHeight
	for _, word in words do
		local line = lines[word.line]
		local align = style.Align == "Left" and 0
			or style.Align == "Right" and textWidth - line.width
			or (textWidth - line.width) / 2
		word.x += x + align
		word.y = y + (word.line - 1) * lineHeight
	end

	return {
		words = words,
		width = width,
		height = contentHeight + style.Padding * 2,
		textX = x,
		textY = y - nameHeight,
		textWidth = textWidth,
		nameHeight = nameHeight,
		image = image,
		imageX = horizontal
				and (style.ImageSide == "Left" and style.Padding or width - style.Padding - image)
			or (width - image) / 2,
		imageY = horizontal and style.Padding + (contentHeight - image) / 2 or style.Padding,
		lineHeight = lineHeight,
		characters = chars,
		wordCount = index,
		rtl = base == "R",
	}
end

local function build(self, id, style, width, letters)
	local old = self.items[id]
	if old then
		old.frame:Destroy()
	end

	local layout = Renderer.layout(style, width)
	local frame = make("Frame", self.root, {
		Name = "Subtitle",
		Size = UDim2.fromOffset(width, layout.height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 241,
	})
	local scale = make("UIScale", frame, { Scale = 1 })
	local clip = make("Frame", frame, {
		Name = "Reveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 241,
	})
	local content = make("Frame", clip, {
		Name = "Content",
		Size = UDim2.fromOffset(width, layout.height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 241,
	})
	if layout.rtl then
		clip.AnchorPoint = Vector2.new(1, 0)
		clip.Position = UDim2.fromScale(1, 0)
		content.AnchorPoint = Vector2.new(1, 0)
		content.Position = UDim2.fromScale(1, 0)
	end

	local bg = make("Frame", content, {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Data.color(style.Background),
		BackgroundTransparency = 1 - style.BackgroundOpacity,
		BorderSizePixel = 0,
		ZIndex = 241,
	})
	make("UICorner", bg, { CornerRadius = UDim.new(0, style.Radius) })
	local item = {
		frame = frame,
		layout = layout,
		labels = {},
		style = style,
		scale = scale,
		bg = bg,
		clip = clip,
		letters = letters,
		glyphCount = 0,
	}
	for _, word in layout.words do
		local label = make("TextLabel", content, {
			Name = "Word" .. word.index,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(word.width, layout.lineHeight),
			Position = UDim2.fromOffset(word.x, word.y),
			Text = word.text,
			FontFace = word.face,
			TextSize = style.Size,
			TextColor3 = Data.color(word.style.Color),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 243,
		})
		local outline = make("UIStroke", label, {
			Thickness = style.Outline,
			Color = Data.color(style.OutlineColor),
			Enabled = style.Outline > 0,
		})
		local underline
		if word.style.Underline then
			underline = make("Frame", label, {
				Name = "Underline",
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 1, -4),
				Size = UDim2.new(1, -2, 0, math.max(1, style.Size / 20)),
				BackgroundColor3 = Data.color(word.style.Color),
				ZIndex = 243,
			})
		end

		local gradient = make("UIGradient", label, { Enabled = false })
		local row = {
			gradient = gradient,
			label = label,
			outline = outline,
			underline = underline,
			word = word,
			glyphs = {},
			order = #item.labels + 1,
		}
		if letters then
			local prefix = ""
			const _, enum = font(word.style)
			for first, last in utf8.graphemes(word.text) do
				const character = word.rtl and word.text or word.text:sub(first, last)
				local x = Text:GetTextSize(prefix, style.Size, enum, Vector2.new(10000, 10000)).X
				prefix ..= character
				local right =
					Text:GetTextSize(prefix, style.Size, enum, Vector2.new(10000, 10000)).X
				local glyph = make("TextLabel", label, {
					Name = "Letter",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset((x + right) / 2, layout.lineHeight / 2),
					Size = UDim2.fromOffset(math.max(1, right - x) + 4, layout.lineHeight * 2),
					Text = character,
					FontFace = word.face,
					TextSize = style.Size,
					TextColor3 = label.TextColor3,
					ZIndex = 244,
				})
				local stroke = make("UIStroke", glyph, {
					Thickness = style.Outline,
					Color = Data.color(style.OutlineColor),
					Enabled = style.Outline > 0,
				})
				item.glyphCount += word.rtl and word.finish - word.start or 1
				table.insert(row.glyphs, {
					label = glyph,
					outline = stroke,
					x = (x + right) / 2,
					index = word.rtl and word.start + 1 or item.glyphCount,
				})
				if word.rtl then
					break
				end
			end
		end

		table.insert(item.labels, row)
	end

	item.visual = table.clone(item.labels)
	table.sort(item.visual, function(a, b)
		if a.word.line ~= b.word.line then
			return a.word.line < b.word.line
		end

		if a.word.x ~= b.word.x then
			return a.word.x < b.word.x
		end

		return a.order < b.order
	end)

	if layout.nameHeight > 0 then
		local speakerStyle = table.clone(style)
		speakerStyle.Font = style.NameFont
		speakerStyle.Bold = style.NameBold
		speakerStyle.Italic = style.NameItalic
		local face = font(speakerStyle)
		item.speaker = make("TextLabel", content, {
			Name = "Speaker",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(layout.textX, layout.textY + style.NameOffset),
			Size = UDim2.fromOffset(layout.textWidth, layout.nameHeight - 6),
			Text = style.Speaker,
			FontFace = face,
			TextSize = style.NameSize,
			TextColor3 = Data.color(style.NameColor),
			TextXAlignment = Enum.TextXAlignment[style.Align],
			ZIndex = 243,
		})
		item.speakerOutline = make("UIStroke", item.speaker, {
			Thickness = style.NameOutline,
			Color = Data.color(style.NameOutlineColor),
			Enabled = style.NameOutline > 0,
		})
	end

	if layout.image > 0 then
		item.image = make("ImageLabel", content, {
			Name = "Portrait",
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. style.Image,
			Position = UDim2.fromOffset(layout.imageX, layout.imageY),
			Size = UDim2.fromOffset(layout.image, layout.image),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 242,
		})
		make(
			"UICorner",
			item.image,
			{ CornerRadius = style.ImageShape == "Circle" and UDim.new(0.5, 0) or UDim.new(0, 4) }
		)
	end

	self.items[id] = item
	return item
end

function Renderer:step(entries, frame, fps, previewTime)
	local viewport = self.root.AbsoluteSize
	if viewport.X < 1 or viewport.Y < 1 then
		return
	end

	local parts = {
		tostring(frame),
		tostring(fps),
		tostring(viewport),
		tostring(self.referenceHeight),
		tostring(previewTime),
	}
	for _, entry in entries do
		table.insert(
			parts,
			entry.id
				.. tostring(entry.event.Subtitle)
				.. tostring(entry.event.Frame)
				.. tostring(entry.track and entry.track.Revision)
		)
	end

	local signature = table.concat(parts, "|")
	if self.lastSignature == signature then
		return
	end

	self.lastSignature = signature
	local resolution = math.max(0.1, viewport.Y / (self.referenceHeight or 1080))
	local active, groups = {}, { Bottom = {}, Center = {}, Top = {} }
	for _, entry in entries do
		local age = frame - entry.event.Frame
		local cue = entry.event.Subtitle
		if cue and age >= 0 and age < cue.Duration then
			local style = Data.sample(cue, age)
			local width = math.min(
				viewport.X * style.Width / resolution,
				viewport.X * 0.94 / (resolution * style.Scale * (1 + style.Pulse))
			)
			local signature
			local layoutStyle = table.clone(style)
			for _, key in
				{
					"JitterDecay",
					"NameOutline",
					"NameOutlineColor",
					"RainbowSpread",
					"GradientColor",
					"GradientAngle",
					"Color",
					"NameColor",
					"Background",
					"OutlineColor",
					"Opacity",
					"RainbowSpeed",
					"Jitter",
					"JitterSpeed",
					"Wave",
					"Pulse",
					"X",
					"Y",
					"Scale",
					"Rotation",
					"BackgroundOpacity",
					"Outline",
					"Radius",
				}
			do
				layoutStyle[key] = nil
			end

			local letters = Data.letters(cue.Entrance) or Data.letters(cue.Exit) or style.Jitter > 0
			for _, w in style.Words do
				if (w.Jitter or 0) > 0 then
					letters = true
				end
			end

			signature = tostring(letters)
				.. Http:JSONEncode(layoutStyle)
				.. ":"
				.. string.format("%.2f", width)
			local item = self.items[entry.id]
			if not item or item.signature ~= signature then
				item = build(self, entry.id, style, width, letters)
				item.signature = signature
				self.lastSignature = nil
			end

			item.style = style
			item.age = age
			item.cue = cue
			item.motion = Data.motion(cue, age)
			item.height = (item.layout.height + (letters and 10 or 0))
				* resolution
				* style.Scale
				* (1 + style.Pulse)
				* ((cue.Entrance == "Pop" or cue.Exit == "Pop") and 1.16 or 1)
			table.insert(groups[style.Position], item)
			active[entry.id] = true
		end
	end

	for id, item in self.items do
		if not active[id] then
			item.frame:Destroy()
			self.items[id] = nil
		end
	end

	for position, items in groups do
		local height = 0
		for _, item in items do
			height += item.height + 12 * resolution
		end

		local fit = math.min(1, viewport.Y * 0.86 / math.max(height, 1))
		height *= fit
		local cursor = position == "Top" and viewport.Y * 0.065
			or position == "Bottom" and viewport.Y * 0.935 - height
			or (viewport.Y - height) / 2
		for _, item in items do
			local style, motion = item.style, item.motion
			local time = previewTime or item.age / fps
			local alpha = style.Opacity * motion.alpha
			item.frame.Position = UDim2.fromOffset(
				viewport.X * (0.5 + style.X) + motion.x * resolution,
				cursor + item.height * fit / 2 + viewport.Y * style.Y + motion.y * resolution
			)
			item.frame.Rotation = style.Rotation + motion.rotation
			item.clip.ClipsDescendants = motion.wipe < 1
			item.clip.Size = UDim2.new(motion.wipe, 0, 1, 0)
			item.scale.Scale = resolution
				* fit
				* style.Scale
				* motion.scale
				* (1 + style.Pulse * math.sin(time * 6))
			item.bg.BackgroundColor3 = Data.color(style.Background)
			item.bg.BackgroundTransparency = 1 - style.BackgroundOpacity * alpha
			item.bg:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, style.Radius)
			local measured = {}
			local unit = math.max(0.01, item.scale.Scale)
			for _, row in item.visual do
				local w = row.word
				local line = measured[w.line] or { width = 0, rows = {}, positions = {} }
				measured[w.line] = line
				local glyph = row.label.TextBounds.X / unit
				if glyph <= 0 then
					glyph = w.width
					self.lastSignature = nil
				end

				local gap = #line.rows > 0
						and math.max(
							0,
							w.x - line.rows[#line.rows].word.x - line.rows[#line.rows].word.width
						)
					or 0
				line.width += gap
				line.positions[w] = line.width
				line.width += glyph
				table.insert(line.rows, row)
			end

			for _, line in measured do
				local offset = item.layout.textX
					+ (
						style.Align == "Left" and 0
						or style.Align == "Right" and item.layout.textWidth - line.width
						or (item.layout.textWidth - line.width) / 2
					)
				for word, x in line.positions do
					line.positions[word] = offset + x
				end
			end

			item.measuredLines = measured
			local chars = math.floor(item.layout.characters * motion.reveal + 0.00001)
			local words = math.floor(item.layout.wordCount * motion.reveal + 0.00001)
			for _, row in item.labels do
				local word = row.word
				local overrides = style.Words[tostring(word.index)] or {}
				local ws = setmetatable(overrides, { __index = style })
				local rainbow = ws.Rainbow
				local color = rainbow
						and Color3.fromHSV(
							(
								time * style.RainbowSpeed
								+ (word.index - 1)
									/ math.max(1, item.layout.wordCount - 1)
									* style.RainbowSpread
							) % 1,
							0.8,
							1
						)
					or Data.color(ws.Color)
				row.gradient.Enabled = style.Gradient and not ws.Rainbow and not item.letters
				if row.gradient.Enabled then
					row.label.TextColor3 = Color3.new(1, 1, 1)
					local angle = math.rad(style.GradientAngle)
					local cx, cy = math.cos(angle), math.sin(angle)
					local tw, th = item.layout.textWidth, item.layout.height - 2 * style.Padding
					local span = math.max(1, math.abs(cx) * tw + math.abs(cy) * th)
					local minimum = math.min(0, cx * tw) + math.min(0, cy * th)
					local center = (
						(word.x + word.width / 2 - item.layout.textX) * cx
						+ (word.y + item.layout.lineHeight / 2 - item.layout.textY) * cy
						- minimum
					) / span
					local half = (math.abs(cx) * word.width + math.abs(cy) * item.layout.lineHeight)
						/ (2 * span)
					local first, last = Data.color(ws.Color), Data.color(style.GradientColor)
					row.gradient.Color = ColorSequence.new(
						first:Lerp(last, math.clamp(center - half, 0, 1)),
						first:Lerp(last, math.clamp(center + half, 0, 1))
					)
					row.gradient.Rotation = style.GradientAngle
				else
					row.label.TextColor3 = color
				end

				row.label.TextTransparency = item.letters and 1 or 1 - alpha
				row.outline.Color = Data.color(style.OutlineColor)
				row.outline.Thickness = style.Outline
				row.outline.Enabled = style.Outline > 0 and not item.letters
				row.outline.Transparency = 1 - alpha
				if row.underline then
					row.underline.BackgroundColor3 = color
					row.underline.BackgroundTransparency = 1 - alpha
					row.underline.Visible = motion.reveal >= 1
						or (
							motion.words and word.index <= words
							or not motion.words and chars > word.start
						)
				end

				row.label.MaxVisibleGraphemes = motion.words and (word.index <= words and -1 or 0)
					or motion.reveal >= 1 and -1
					or word.rtl and (chars > word.start and -1 or 0)
					or math.clamp(chars - word.start, 0, word.finish - word.start)
				local line = item.measuredLines and item.measuredLines[word.line]
				local textX = line and line.positions[word] or word.x
				local dy = math.sin(time * 5 + word.index * 0.8) * style.Wave
				row.label.Position = UDim2.fromOffset(textX, word.y + dy)
				if item.letters then
					row.label.MaxVisibleGraphemes = -1
					for _, glyph in row.glyphs do
						local g = Data.glyph(
							item.cue,
							item.age,
							glyph.index,
							item.glyphCount,
							word.index,
							item.layout.wordCount,
							fps,
							ws,
							previewTime
						)
						local shown = motion.words and word.index <= words
							or not motion.words and glyph.index <= chars
						local opacity = shown and alpha * g.alpha or 0
						glyph.label.TextTransparency = 1 - opacity
						glyph.label.TextSize = style.Size * g.scale
						glyph.label.Position =
							UDim2.fromOffset(glyph.x + g.x, item.layout.lineHeight / 2 + g.y)
						glyph.label.Rotation = g.rotation
						local tint = color
						if style.Gradient and not ws.Rainbow then
							local angle = math.rad(style.GradientAngle)
							local tw, th =
								item.layout.textWidth, item.layout.height - 2 * style.Padding
							local cx, cy = math.cos(angle), math.sin(angle)
							local span = math.max(1, math.abs(cx) * tw + math.abs(cy) * th)
							local minimum = math.min(0, cx * tw) + math.min(0, cy * th)
							local blend = (
								(textX + glyph.x - item.layout.textX) * cx
								+ (word.y - item.layout.textY) * cy
								- minimum
							) / span
							tint = Data.color(ws.Color)
								:Lerp(Data.color(style.GradientColor), math.clamp(blend, 0, 1))
						elseif ws.Rainbow then
							tint = Color3.fromHSV(
								(
									time * style.RainbowSpeed
									+ (glyph.index - 1)
										/ math.max(1, item.glyphCount - 1)
										* style.RainbowSpread
								) % 1,
								0.8,
								1
							)
						end

						glyph.label.TextColor3 = tint
						glyph.outline.Color = Data.color(style.OutlineColor)
						glyph.outline.Thickness = style.Outline
						glyph.outline.Enabled = style.Outline > 0
						glyph.outline.Transparency = 1 - opacity
					end
				end
			end

			if item.speaker then
				item.speaker.TextColor3 = Data.color(style.NameColor)
				item.speaker.TextTransparency = 1 - alpha
				item.speakerOutline.Color = Data.color(style.NameOutlineColor)
				item.speakerOutline.Thickness = style.NameOutline
				item.speakerOutline.Enabled = style.NameOutline > 0
				item.speakerOutline.Transparency = 1 - alpha
			end

			if item.image then
				item.image.ImageTransparency = 1 - alpha
			end

			cursor += (item.height + 12 * resolution) * fit
		end
	end
end

return Renderer
