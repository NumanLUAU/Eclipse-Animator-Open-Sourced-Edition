--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Picker = require("Picker")
local Interpolation = require("Interpolation")
local Tool = require("Tool")
local Sizeable = require("SizeableWindows")
local Motion = require("Motion")
local Theme = require("Theme")
local Effects = require("Effects")
local Model = require("Model")
local Objects = require("Objects")
local Assets = require("EffectCatalog")
local Raw = require("RawState")
local Input = require("UserInputService")
local Window = {}
local refs
local windows = {}

local function centered(root)
	local function fix(v)
		if not v:IsA("GuiObject") then
			return
		end

		local delta = Vector2.new(0.5, 0.5) - v.AnchorPoint
		local s, p = v.Size, v.Position
		v.Position = UDim2.new(
			p.X.Scale + s.X.Scale * delta.X,
			p.X.Offset + s.X.Offset * delta.X,
			p.Y.Scale + s.Y.Scale * delta.Y,
			p.Y.Offset + s.Y.Offset * delta.Y
		)
		v.AnchorPoint = Vector2.new(0.5, 0.5)
	end

	fix(root)
	for _, v in root:GetDescendants() do
		fix(v)
	end
end

local function text(parent, name, value, x, y, w, h, size)
	local t = Tool.label(parent, name, value, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h or 20))
	t.TextSize = size or 12
	return t
end

local function button(parent, name, value, x, y, w, h, callback, selected)
	local b, t =
		Tool.button(parent, name, value, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h), callback)
	b:SetAttribute("ThemeBg", selected and "MenuSel" or "TopBtn")
	t.TextSize = 12
	return b, t
end

local function field(parent, name, value, x, y, w, changed)
	local box = Tool.field(parent, name, value, UDim2.fromOffset(x, y), UDim2.fromOffset(w, 24))
	require("NumericInput").connect(box, {
		step = (name:lower():find("frame") or name == "Start" or name == "Duration") and 1 or 0.1,
		enabled = function()
			return type(value) == "number"
		end,
	}, function()
		changed(box.Text, box)
	end)
	return box
end

function Window.close(immediate, kind)
	if kind then
		local item = windows[kind]
		if item then
			windows[kind] = nil
			item.tool:close(immediate)
		end

		return
	end

	local copy = table.clone(windows)
	for k in copy do
		Window.close(immediate, k)
	end
end

function Window.isOpen()
	return next(windows) ~= nil
end

function Window.open(kind)
	if kind == "Camera Shake" then
		return Window.openShake()
	end

	if kind == "Impact Frames" then
		return Window.openImpact()
	end

	kind = kind or "Vignette"
	if not refs or not refs.AnimatorFrame.Visible then
		return
	end

	if windows[kind] then
		return windows[kind].tool.frame
	end

	local id = kind:gsub(" ", "")
	local letter = kind == "Letterbox"
	local width = letter and 480 or 360
	local height = letter and 504 or 380
	local item = {
		draft = Model.defaults(
			kind,
			math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS),
			Raw.Timeline.FPS
		),
		colorOpen = false,
	}
	local v = item.draft
	v.width = 1
	v.heightScale = 1
	v.depth = 1.2
	v.images = table.clone(Objects.images)
	if letter then
		v.fadeIn = 0
		v.fadeOut = 0
	end

	local cams = Effects.cameras()
	if #cams == 1 then
		v.cameraId = cams[1].id
	end

	local tool = Tool.new(
		refs,
		"Eclipse" .. id .. "Creator",
		string.upper(kind),
		Vector2.new(width, height),
		false,

		function()
			windows[kind] = nil
			Picker.close()
			Interpolation.close()
		end
	)
	item.tool = tool
	windows[kind] = item
	local frame = tool.frame
	frame.MinimumSize.MinSize = Vector2.new(width, letter and 420 or 380)
	local scroll = Tool.make("ScrollingFrame", frame, "Settings", {
		Position = UDim2.new(0, 12, 0, 36),
		Size = UDim2.new(1, -24, 1, -96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
	})
	local status =
		Tool.label(frame, "Status", "", UDim2.new(0, 12, 1, -58), UDim2.new(1, -24, 0, 20))
	status.TextSize = 11
	local valid = true

	local function message(value, bad)
		status.Text = value
		status.TextColor3 = bad and Color3.fromRGB(239, 133, 151)
			or Theme.get("Txt", Color3.new(1, 1, 1))
	end

	local function validate()
		local ok, result = pcall(Effects.validateForProject, v)
		valid = ok
		if ok then
			message("")
		else
			message(tostring(result):gsub("^.-:%d+: ", ""), true)
		end

		return ok
	end

	local render
	render = function()
		if not windows[kind] then
			return
		end

		local old = scroll:FindFirstChild("Content")
		if old then
			old:Destroy()
		end

		local w =
			math.max(width - 28, scroll.AbsoluteSize.X / math.max(0.01, Motion.scale(scroll)) - 4)
		local body = Tool.make(
			"Frame",
			scroll,
			"Content",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(w, 1), Position = UDim2.new() }
		)
		local y = 0

		local function section(title)
			text(body, title .. "Label", title, 0, y, w, 18, 11)
			local line = Tool.make("Frame", body, title .. "Divider", {
				Position = UDim2.fromOffset(0, y + 20),
				Size = UDim2.fromOffset(w, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.get("Div", Color3.fromRGB(64, 66, 80)),
				BackgroundTransparency = 0.45,
			})
			line:SetAttribute("ThemeBg", "Div")
			y += 28
		end

		local function number(label, key, x, rowY, fieldWidth, factor)
			text(body, key .. "Label", label, x, rowY, fieldWidth, 16)
			field(body, key, string.format("%g", v[key] * (factor or 1)), x, rowY + 18, fieldWidth, function(
				value,
				box
			)
				local n = tonumber(value)
				if not Model.finite(n) then
					message("Enter a number for " .. label .. ".", true)
					box.Text = tostring(v[key] * (factor or 1))
					return
				end

				v[key] = n / (factor or 1)
				validate()
			end
)
		end

		if letter then
			section("CAMERA")
			local cameras = Effects.cameras()
			local columns = #cameras > 1 and 2 or 1
			local cw = (w - 8 * (columns - 1)) / columns
			if #cameras == 0 then
				text(
					body,
					"NoCamera",
					"Add a camera to your project to create letterbox.",
					0,
					y,
					w,
					36
				)
				y += 48
			else
				for i, c in cameras do
					local n = i - 1
					button(
						body,
						"Camera" .. i,
						c.name,
						n % columns * (cw + 8),
						y + math.floor(n / columns) * 38,
						cw,
						30,

						function()
							v.cameraId = c.id
							render()
						end,
						v.cameraId == c.id
					)
				end

				y += math.ceil(#cameras / columns) * 38 + 8
			end

			section("STYLE")
			local choices = { { id = "Solid", label = "Solid" } }
			for i, asset in Assets do
				table.insert(choices, { id = asset.id, label = tostring(i), asset = asset })
			end

			local tileW = (w - 5 * 8) / 6
			for i, choice in choices do
				local x = (i - 1) % 6 * (tileW + 8)
				local row = y + math.floor((i - 1) / 6) * 53
				local b, t = button(body, "Style" .. i, choice.label, x, row, tileW, 45, function()
					v.style = choice.id
					v.color = choice.id == "Solid" and { 0, 0, 0 } or { 1, 1, 1 }
					render()
				end, v.style == choice.id)
				t.Position = UDim2.new(0, 0, 1, -20)
				t.Size = UDim2.new(1, 0, 0, 19)
				if choice.asset then
					local texture
					for _, node in choice.asset.nodes do
						if node.properties.Texture then
							texture = node.properties.Texture
							break
						end
					end

					Tool.make("ImageLabel", b, "Thumbnail", {
						Position = UDim2.fromOffset(6, 5),
						Size = UDim2.new(1, -12, 0, 20),
						BackgroundTransparency = 1,
						Image = texture or "",
						ScaleType = Enum.ScaleType.Fit,
					})
				else
					for _, offset in { 6, 17 } do
						Tool.make("Frame", b, "Bar", {
							Position = UDim2.fromOffset(8, offset),
							Size = UDim2.new(1, -16, 0, 5),
							BackgroundColor3 = Theme.get("Txt", Color3.new(1, 1, 1)),
							BorderSizePixel = 0,
						})
					end
				end
			end

			y += 159 + 8
			local third = (w - 16) / 3
			number("Width %", "width", 0, y, third, 100)
			number(
				v.style == "Solid" and "Bar height %" or "Height %",
				v.style == "Solid" and "height" or "heightScale",
				third + 8,
				y,
				third,
				100
			)
			number("Depth · studs", "depth", 2 * (third + 8), y, third)
			y += 57
		end

		section("APPEARANCE")
		local half = (w - 12) / 2
		local color = Color3.new(table.unpack(v.color))
		text(body, "ColorLabel", "Color", 0, y, half, 16)
		text(body, "OpacityLabel", "Opacity %", half + 12, y, half, 16)
		local colorButton, colorLabel
		colorButton, colorLabel = button(
			body,
			"ColorToggle",
			"#" .. color:ToHex():upper(),
			0,
			y + 18,
			half,
			24,

			function()
				local stops = { Color3.new(table.unpack(v.color)) }
				if v.gradient then
					table.insert(stops, Color3.new(table.unpack(v.color2 or v.color)))
				end

				Picker.open(refs, colorButton, { stops = stops, rot = v.gradientRotation or 90 }, function(
					value
				)
					local c = value.stops[1]
					v.color = { c.R, c.G, c.B }
					v.gradient = #value.stops > 1
					local c2 = value.stops[2] or c
					v.color2 = { c2.R, c2.G, c2.B }
					v.gradientRotation = value.rot or 90
					colorLabel.Text = v.gradient and "GRADIENT" or "#" .. c:ToHex():upper()
					local swatch = colorButton:FindFirstChild("Swatch")
					if swatch then
						local g = swatch:FindFirstChildOfClass("UIGradient")
						g.Enabled = v.gradient
						g.Color = ColorSequence.new(c, c2)
						g.Rotation = v.gradientRotation
						swatch.BackgroundColor3 = v.gradient and Color3.new(1, 1, 1) or c
					end
				end
)
			end
		)
		colorLabel.Position = UDim2.fromOffset(34, 0)
		colorLabel.Size = UDim2.new(1, -40, 1, 0)
		colorLabel.TextXAlignment = Enum.TextXAlignment.Left
		if v.gradient then
			colorLabel.Text = "GRADIENT"
		end

		local swatch = Tool.make("Frame", colorButton, "Swatch", {
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = v.gradient and Color3.new(1, 1, 1) or color,
			BorderSizePixel = 0,
		})
		Tool.make("UIGradient", swatch, "Gradient", {
			Enabled = v.gradient == true,
			Color = ColorSequence.new(color, Color3.new(table.unpack(v.color2 or v.color))),
			Rotation = v.gradientRotation or 90,
		})
		field(body, "Opacity", v.opacity * 100, half + 12, y + 18, half, function(s, box)
			local n = tonumber(s)
			if not Model.finite(n) then
				box.Text = tostring(v.opacity * 100)
				return
			end

			v.opacity = n / 100
			validate()
		end)
		y += 60
		if not (letter and v.style == "Solid") then
			section("TIMING")
			number("Start frame", "start", 0, y, half)

			local function seconds(label, key, x, row)
				text(body, key .. "Label", label .. " · seconds", x, row, half, 16)
				local hint = text(
					body,
					key .. "Frames",
					tostring(v[key]) .. " frames",
					x,
					row + 45,
					half,
					17,
					10
				)
				field(body, key, string.format("%g", v[key] / Raw.Timeline.FPS), x, row + 18, half, function(
					value,
					box
				)
					local n = tonumber(value)
					if Model.finite(n) and n >= 0 then
						v[key] = math.round(n * Raw.Timeline.FPS)
					end

					box.Text = string.format("%g", v[key] / Raw.Timeline.FPS)
					hint.Text = tostring(v[key]) .. " frames"
					validate()
				end
)
			end

			seconds("Duration", "duration", half + 12, y)
			y += 70
			seconds("Fade in", "fadeIn", 0, y)
			seconds("Fade out", "fadeOut", half + 12, y)
			y += 70
			button(body, "EasingSelection", "EASING SELECTION", 0, y, w, 26, function()
				Picker.close()
				Interpolation.open(refs, v, function(result)
					v.easeIn = result.easeIn
					v.easeOut = result.easeOut
					validate()
				end)
			end)
			y += 28
		end

		if letter then
			frame.Size = UDim2.fromOffset(width, y + 100)
		end

		body.Size = UDim2.fromOffset(w, y)
		scroll.CanvasSize = UDim2.fromOffset(0, y)
		Theme.applyTree(body)
		centered(body)
		validate()
	end

	local cancel = Tool.button(
		frame,
		"Cancel",
		"CANCEL",
		UDim2.new(0, 12, 1, -34),
		UDim2.fromOffset(84, 24),

		function()
			Window.close(false, kind)
		end
	)
	local add = Tool.button(
		frame,
		"CreateEffect",
		"ADD TO TIMELINE",
		UDim2.new(1, -172, 1, -34),
		UDim2.fromOffset(160, 24),

		function()
			if not validate() then
				return
			end

			local ok, result = pcall(Effects.create, v)
			if ok then
				Window.close(false, kind)
			else
				message(tostring(result):gsub("^.-:%d+: ", ""), true)
			end
		end
	)
	Sizeable.attach({
		frame = frame,
		mouse = refs.Mouse or refs.Plugin:GetMouse(),
		minSize = Vector2.new(width, letter and 420 or 380),
		maxSize = Vector2.new(720, 900),
		settingKey = "Eclipse" .. id .. "CreatorPersistent",
		onResize = render,
	})
	render()
	centered(frame)
	return frame
end

local function fit(button, label)
	button.ClipsDescendants = true
	label.TextWrapped = false
	label.TextScaled = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextSize = 11
	return button, label
end

function Window.openImpact()
	local kind = "Impact Frames"
	if not refs or not refs.Active() then
		return
	end

	if windows[kind] then
		return windows[kind].tool.frame
	end

	local tool = Tool.new(
		refs,
		"EclipseImpactFrames",
		"IMPACT FRAMES",
		Vector2.new(560, 356),
		false,

		function()
			windows[kind] = nil
		end
	)
	local s = {
		tool = tool,
		rows = { { image = "", delay = 0, hold = 1 } },
		selected = 1,
		start = math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS),
	}
	windows[kind] = s
	local frame = tool.frame
	local preview = Tool.make("Frame", frame, "Preview", {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.fromOffset(180, 102),
		BackgroundColor3 = Color3.new(),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	})
	local status = text(frame, "Status", "", 12, 295, 536, 18, 10)

	local function message(value)
		status.Text = value or ""
	end

	local render

	local function paint(image)
		Objects.paintImpact(preview, image or "", Color3.new(1, 1, 1), 0)
	end

	local function stop()
		s.playing = false
		paint(s.rows[s.selected].image)
	end

	local function whole(box, value, minimum, maximum)
		local n = tonumber(box.Text)
		if not Model.finite(n) or n % 1 ~= 0 or n < minimum or n > maximum then
			box.Text = tostring(value)
			message("Enter a whole number from " .. minimum .. " to " .. maximum .. ".")
			return
		end

		message()
		return n
	end

	local play, label = button(frame, "PlayPreview", "PLAY", 12, 150, 180, 24, function()
		if s.playing then
			stop()
		else
			local ok, err = pcall(Effects.validateImpactFrames, s.rows)
			if not ok then
				message("Choose an image for every row.")
				return
			end

			s.elapsed = 0
			s.playing = true
		end
	end)
	text(frame, "StartLabel", "START FRAME", 12, 215, 100, 16, 10)
	local start = Tool.field(
		frame,
		"StartFrame",
		s.start,
		UDim2.fromOffset(116, 210),
		UDim2.fromOffset(76, 24)
	)
	require("NumericInput").connect(start, { step = 1, min = 0, integer = true }, function()
		local n = whole(start, s.start, 0, Model.MAX_FRAME)
		if n then
			s.start = n
			render()
		end
	end)
	text(frame, "CountLabel", "IMAGES", 12, 249, 100, 16, 10)
	local count =
		Tool.field(frame, "ImageCount", 1, UDim2.fromOffset(116, 244), UDim2.fromOffset(76, 24))
	require("NumericInput").connect(count, { step = 1, min = 1, integer = true }, function()
		local n = whole(count, #s.rows, 1, 256)
		if not n then
			return
		end

		while #s.rows < n do
			table.insert(s.rows, { image = "", delay = 0, hold = 1 })
		end

		while #s.rows > n do
			table.remove(s.rows)
		end

		s.selected = math.min(s.selected, n)
		stop()
		render()
	end)
	local list = Tool.make("ScrollingFrame", frame, "Frames", {
		Position = UDim2.fromOffset(204, 40),
		Size = UDim2.fromOffset(344, 106),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	})
	text(frame, "ImageLabel", "IMAGE", 204, 156, 100, 16, 10)
	local asset =
		Tool.field(frame, "ImageAsset", "", UDim2.fromOffset(204, 175), UDim2.fromOffset(344, 24))
	asset.PlaceholderText = "Image asset ID"
	asset.FocusLost:Connect(function()
		local ok, value = pcall(Objects.impactImage, asset.Text)
		if not ok or value == "" or value:sub(1, 8) == "builtin:" then
			message("Enter an image asset ID.")
			asset.Text = s.rows[s.selected].image
			return
		end

		s.rows[s.selected].image = value
		s.rows[s.selected].name = nil
		stop()
		render()
		message()
	end)
	text(frame, "DelayLabel", "GAP BEFORE · FRAMES", 204, 208, 166, 16, 10)
	text(frame, "HoldLabel", "HOLD · FRAMES", 382, 208, 166, 16, 10)
	local delay =
		Tool.field(frame, "Delay", 0, UDim2.fromOffset(204, 228), UDim2.fromOffset(166, 24))
	local hold = Tool.field(frame, "Hold", 1, UDim2.fromOffset(382, 228), UDim2.fromOffset(166, 24))
	require("NumericInput").connect(delay, { step = 1, min = 0, integer = true }, function()
		local row = s.rows[s.selected]
		local n = whole(delay, row.delay, 0, Model.MAX_FRAME)
		if n then
			row.delay = n
			stop()
			render()
		end
	end)
	require("NumericInput").connect(hold, { step = 1, min = 1, integer = true }, function()
		local row = s.rows[s.selected]
		local n = whole(hold, row.hold, 1, Model.MAX_FRAME)
		if n then
			row.hold = n
			stop()
			render()
		end
	end)
	local recent
	button(frame, "Recent", "RECENT IMAGES", 12, 182, 180, 24, function()
		if recent then
			recent:Destroy()
			recent = nil
			return
		end

		local entries = require("ImageLibrary").recent()
		if #entries == 0 then
			message("No recent images. Paste an image asset ID.")
			return
		end

		recent = Tool.make("ScrollingFrame", frame, "RecentImages", {
			Position = UDim2.fromOffset(12, 40),
			Size = UDim2.fromOffset(180, 134),
			CanvasSize = UDim2.fromOffset(0, #entries * 28),
			ScrollBarThickness = 4,
			BorderSizePixel = 0,
			ZIndex = 30,
			ClipsDescendants = true,
		})
		recent:SetAttribute("ThemeBg", "Top")
		for i, entry in entries do
			local b, t = button(recent, "Recent" .. i, entry.name, 4, (i - 1) * 28, 168, 24, function()
				s.rows[s.selected].image = Objects.impactImage(entry.id)
				s.rows[s.selected].name = entry.name
				recent:Destroy()
				recent = nil
				stop()
				render()
			end
)
			fit(b, t)
		end

		Theme.applyTree(recent)
	end)
	render = function()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local at = s.start
		for i, row in s.rows do
			at += row.delay
			local name = row.name
				or (row.image == "" and "Choose image" or row.image:gsub("rbxassetid://", ""))
			local b, t = button(
				list,
				"Frame" .. i,
				string.format("%02d   %s", i, name),
				0,
				(i - 1) * 28,
				338,
				24,

				function()
					s.selected = i
					stop()
					render()
				end,
				i == s.selected
			)
			fit(b, t)
			t.Size = UDim2.new(1, -96, 1, 0)
			t.Position = UDim2.fromOffset(6, 0)
			t.AnchorPoint = Vector2.zero
			t.TextXAlignment = Enum.TextXAlignment.Left
			local timing = text(
				b,
				"Timing",
				row.hold == 1 and tostring(at) or string.format("%d–%d", at, at + row.hold - 1),
				250,
				0,
				82,
				24,
				10
			)
			timing.TextXAlignment = Enum.TextXAlignment.Right
			timing.TextWrapped = false
			timing.TextTruncate = Enum.TextTruncate.AtEnd
			at += row.hold
		end

		list.CanvasSize = UDim2.fromOffset(0, #s.rows * 28)
		count.Text = tostring(#s.rows)
		local row = s.rows[s.selected]
		asset.Text = row.image
		delay.Text = tostring(row.delay)
		hold.Text = tostring(row.hold)
		Theme.applyTree(frame)
	end

	button(frame, "AddImage", "+", 204, 264, 46, 24, function()
		if #s.rows < 256 then
			table.insert(s.rows, s.selected + 1, { image = "", delay = 0, hold = 1 })
			s.selected += 1
			stop()
			render()
		end
	end)
	button(frame, "RemoveImage", "REMOVE", 258, 264, 98, 24, function()
		if #s.rows > 1 then
			table.remove(s.rows, s.selected)
			s.selected = math.min(s.selected, #s.rows)
			stop()
			render()
		end
	end)
	for i, entry in { { "Earlier", "UP", -1 }, { "Later", "DOWN", 1 } } do
		button(frame, entry[1], entry[2], 364 + (i - 1) * 96, 264, 88, 24, function()
			local n = s.selected + entry[3]
			if n >= 1 and n <= #s.rows then
				s.rows[s.selected], s.rows[n] = s.rows[n], s.rows[s.selected]
				s.selected = n
				stop()
				render()
			end
		end)
	end

	button(frame, "Cancel", "CANCEL", 12, 320, 90, 24, function()
		Window.close(false, kind)
	end)
	button(frame, "CreateImpact", "ADD TO TIMELINE", 380, 320, 168, 24, function()
		local ok, result = pcall(Effects.createImpact, s.rows, s.start)
		if not ok then
			message(tostring(result):gsub("^.-:%d+: ", ""))
			return
		end

		for _, row in s.rows do
			require("ImageLibrary").add(row.image, { name = row.name })
		end

		local item = refs.State.Rig:PropertyItem(result, "Image")
		if item then
			refs.State.Rig:SetSingleItemSelection(item)
		end

		Window.close(false, kind)
	end)
	table.insert(
		tool.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			label.Text = s.playing and "PAUSE" or "PLAY"
			if not s.playing then
				return
			end

			s.elapsed += dt
			local tick = math.floor(s.elapsed * Raw.Timeline.FPS)
			local at = 0
			local value = ""
			for _, row in s.rows do
				at += row.delay
				if tick >= at and tick < at + row.hold then
					value = row.image
				end

				at += row.hold
			end

			paint(value)
			if tick >= at then
				s.playing = false
			end
		end)
	)
	render()
	paint("")
	return frame
end

function Window.openShake()
	local kind = "Camera Shake"
	if not refs or not refs.Active() then
		return
	end

	if windows[kind] then
		return windows[kind].tool.frame
	end

	local tool = Tool.new(refs, "EclipseCameraShake", "CAMERA SHAKE", Vector2.new(340, 428), false, function()
		windows[kind] = nil
		Interpolation.close()
	end
)
	windows[kind] = { tool = tool }
	local frame = tool.frame
	local cameras = Effects.cameras()
	local selected = require("SelectedRig").resolve(refs.State)
	local cameraId
	for _, camera in cameras do
		if camera.rig == selected or #cameras == 1 then
			cameraId = camera.id
		end
	end

	text(frame, "CameraLabel", "CAMERA", 12, 42, 76, 24, 10)

	local function cameraName()
		for _, camera in Effects.cameras() do
			if camera.id == cameraId then
				return camera.name
			end
		end

		return "Choose camera"
	end

	local cameraButton, cameraText
	cameraButton, cameraText = button(frame, "Camera", cameraName(), 94, 40, 234, 28, function()
		local choices = Effects.cameras()
		if #choices == 0 then
			return
		end

		local index = 0
		for i, camera in choices do
			if camera.id == cameraId then
				index = i
			end
		end

		cameraId = choices[index % #choices + 1].id
		cameraText.Text = cameraName()
	end)
	cameraButton.ClipsDescendants = true
	cameraText.TextWrapped = false
	cameraText.TextTruncate = Enum.TextTruncate.AtEnd
	local fields = {}
	local duration = math.max(1, math.round(Raw.Timeline.FPS * 0.5))
	local fade = math.min(math.floor(duration / 2), math.round(Raw.Timeline.FPS * 0.1))
	local envelope = Model.defaults(kind, 0, Raw.Timeline.FPS)
	for i, row in
		{
			{ "Strength", "STRENGTH", 1 },
			{ "Speed", "SPEED", 12 },
			{ "Start", "START FRAME", math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS) },
			{ "Duration", "DURATION · FRAMES", duration },
			{ "FadeIn", "FADE IN · FRAMES", fade },
			{ "FadeOut", "FADE OUT · FRAMES", fade },
		}
	do
		local x = 12 + ((i - 1) % 2) * 164
		local y = 86 + math.floor((i - 1) / 2) * 64
		text(frame, row[1] .. "Label", row[2], x, y, 152, 16, 10)
		fields[row[1]] = Tool.field(
			frame,
			row[1],
			row[3],
			UDim2.fromOffset(x, y + 20),
			UDim2.fromOffset(152, 26)
		)
	end

	button(frame, "ShakeEasing", "FADE EASING", 12, 278, 316, 26, function()
		Interpolation.open(refs, envelope, function(value)
			envelope.easeIn = value.easeIn
			envelope.easeOut = value.easeOut
		end)
	end)
	local hint = text(
		frame,
		"Hint",
		"Strength keys control the fades. Select them in the timeline to adjust their easing later.",
		12,
		312,
		316,
		38,
		10
	)
	hint.TextWrapped = true
	local status = text(
		frame,
		"Status",
		#cameras == 0 and "Add a camera to the timeline first." or "",
		12,
		352,
		316,
		36,
		10
	)
	status.TextWrapped = true
	button(frame, "Cancel", "CANCEL", 12, 392, 80, 24, function()
		Window.close(false, kind)
	end)
	button(frame, "CreateShake", "ADD TO TIMELINE", 160, 392, 168, 24, function()
		local values = {}
		for key, box in fields do
			values[key] = tonumber(box.Text)
			if not Model.finite(values[key]) then
				status.Text = "Enter a valid " .. key:lower() .. "."
				return
			end
		end

		envelope.fadeIn = values.FadeIn
		envelope.fadeOut = values.FadeOut
		local ok, result = pcall(
			Effects.createShake,
			values.Strength,
			values.Speed,
			values.Start,
			values.Duration,
			cameraId,
			envelope
		)
		if not ok then
			status.Text = tostring(result):gsub("^.-:%d+: ", "")
			return
		end

		local item = refs.State.Rig:PropertyItem(result, "Strength")
		if item then
			refs.State.Rig:SetSingleItemSelection(item)
		end

		Window.close(false, kind)
	end)
	Theme.applyTree(frame)
	return frame
end

function Window.init(options)
	refs = options
	refs.State.EffectsWindow = Window
	refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not refs.ScreenGui.Enabled then
			Window.close(true)
		end
	end)
	refs.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not refs.AnimatorFrame.Visible then
			Window.close(true)
		end
	end)
	refs.ScreenGui.Destroying:Once(function()
		Window.close(true)
	end)
end

return Window
