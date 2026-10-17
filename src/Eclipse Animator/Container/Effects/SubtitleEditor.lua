--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Chrome = require("Chrome")
local Hover = require("HoverDialog")
local Picker = require("Picker")
local Theme = require("Theme")
local Data = require("SubtitleData")
local Subtitles = require("Subtitles")
local Events = require("Events")
local Raw = require("RawState")
local Renderer = require("Renderer")
local Window = {}
local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular)
local view, selectedTrack, selectedId
local advanced, autoKey = false, false

local function event()
	return selectedTrack
		and Events.all()[selectedTrack.Rig] == selectedTrack
		and selectedTrack.Events[selectedId]
end

function Window.close(immediate)
	local old = view
	view = nil
	if old then
		old:close(immediate)
	end
end

function Window.open(track, id)
	if view and view.commit then
		view.commit()
	end

	if track and id then
		selectedTrack, selectedId = track, id
	end

	if view then
		view.refresh()
		return view.frame
	end

	local refs = Subtitles.getRefs()
	if not refs then
		return
	end

	local current
	current = Tool.new(refs, "EclipseSubtitlesWindow", "SUBTITLES", Vector2.new(720, 560), true, function()
		if current.commit then
			current.commit()
		end

		if current.closePopup then
			current.closePopup()
		end

		if current.pickerAnchor and Picker.isOpen(current.pickerAnchor) then
			Picker.close(true)
		end

		if current.tooltip then
			current.tooltip:Destroy()
		end

		if current.tooltipGui then
			current.tooltipGui:Destroy()
		end

		if current.unsubscribe then
			current.unsubscribe()
		end

		if refs.State.Library then
			refs.State.Library.closeSounds(current)
		end

		if view == current then
			view = nil
		end
	end
)
	view = current
	local frame = current.frame
	local pageName, target = "Content", 0
	local popup, inputEdit, pickerEdit, replay
	local syncing, pageSignature, previewClock = false, "", 0
	local bindings, cueRows, tabs = {}, {}, {}
	local paintPage, sync, chooseCue

	local function make(class, parent, name, props)
		return Tool.make(class, parent, name, props)
	end

	local function text(parent, name, value, x, y, w, h)
		local label =
			Tool.label(parent, name, value, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h or 24))
		label.FontFace = FONT
		label.ZIndex = parent.ZIndex + 2
		label.TextWrapped = false
		return label
	end

	local function button(parent, name, value, x, y, w, h, callback)
		local b, label = Chrome.menuButton(
			parent,
			name,
			value,
			UDim2.fromOffset(x, y),
			UDim2.fromOffset(w, h or 28)
		)
		label.FontFace = FONT
		label.TextSize = 12
		if callback then
			b.Activated:Connect(callback)
		end

		return b, label
	end

	local function outline(parent, name)
		local stroke = make(
			"UIStroke",
			parent,
			name,
			{ Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
		)
		stroke:SetAttribute("ThemeStrk", "Strk")
		return stroke
	end

	local oldHover = refs.State.UIHelpers and refs.State.UIHelpers.hoverDialog
	if oldHover and oldHover.ui and oldHover.ui.Parent then
		current.tooltipGui = make("ScreenGui", current.gui.Parent, "EclipseSubtitleTooltip", {
			DisplayOrder = current.gui.DisplayOrder + 100,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		current.tooltipGui:SetAttribute("EclipseOwnedUI", true)
		local tip = oldHover.ui:Clone()
		tip.Parent = current.tooltipGui
		current.tooltip = Hover.initialize(tip, oldHover.mouse)
		Theme.addRoot(current.tooltipGui)
	end

	local function tooltip(o, value)
		if current.tooltip then
			current.tooltip:latchToInstance(o, value)
		end
	end

	local tips = {
		Replay = "Replay this subtitle from its first frame",
		Mode = "Switch between essential controls and all subtitle settings",
		Text = "Edit the caption live",
		Speaker = "Optional name shown above the caption",
		Image = "Optional Roblox image asset ID",
		StartFrame = "Move the whole subtitle, keeping its style keys together",
		Duration = "Length of this subtitle in timeline frames",
		InFrames = "Total entrance duration, including the letter stagger",
		OutFrames = "Total exit duration, including the letter stagger",
		Jitter = "Independent shake for each letter",
		JitterSpeed = "Shake changes per second",
		JitterDecay = "Seconds until each letter settles; zero keeps shaking",
		Word = "Style one word or the whole caption",
		Font = "Each option previews its actual font",
		AutoKey = "Create a style key at the playhead when changing a setting",
	}
	current.closePopup = function()
		if popup then
			popup:Destroy()
			popup = nil
		end
	end

	local function bind(callback)
		table.insert(bindings, callback)
	end

	local function offset()
		local e = event()
		return e
				and math.clamp(
					math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS) - e.Frame,
					0,
					e.Subtitle.Duration - 1
				)
			or 0
	end

	local function style()
		local e = event()
		return e and e.Subtitle and Data.sample(e.Subtitle, offset())
	end

	local function keyOffset()
		if inputEdit then
			return inputEdit.offset
		end

		if pickerEdit then
			return pickerEdit.offset
		end

		local e = event()
		return e and ((advanced and autoKey) or #e.Subtitle.Keys > 0) and offset() or 0
	end

	current.commit = function()
		local pending = { inputEdit, pickerEdit }
		inputEdit = nil
		pickerEdit = nil
		for _, edit in pending do
			if edit and edit.changed then
				Subtitles.commitInput(edit.track, edit.before)
			end
		end
	end

	local function edit(callback, title)
		if syncing or not event() then
			return
		end

		local pending = inputEdit or pickerEdit
		if pending then
			pending.changed = true
		end

		Subtitles.edit(selectedTrack, selectedId, callback, title, pending ~= nil)
	end

	local function property(key)
		if target ~= -1 then
			return key
		end

		return ({
			Font = "NameFont",
			Size = "NameSize",
			Color = "NameColor",
			Bold = "NameBold",
			Italic = "NameItalic",
			Outline = "NameOutline",
			OutlineColor = "NameOutlineColor",
		})[key] or key
	end

	local function value(key)
		local s = style()
		if not s then
			return Data.defaults[property(key)]
		end

		local w = target > 0 and s.Words[tostring(target)]
		if w and w[key] ~= nil then
			return w[key]
		end

		return s[property(key)]
	end

	local function setValue(key, nextValue)
		local at = keyOffset()
		edit(function(cue)
			local k = Data.key(cue, at)
			if not k then
				return
			end

			if
				target > 0
				and table.find({ "Color", "Bold", "Italic", "Underline", "Rainbow", "Jitter" }, key)
			then
				local index = tostring(target)
				k.Value.Words[index] = k.Value.Words[index] or {}
				k.Value.Words[index][key] = nextValue
			else
				k.Value[property(key)] = nextValue
			end
		end, "Subtitle " .. key)
	end

	local list = make("ScrollingFrame", frame, "Cues", {
		Position = UDim2.fromOffset(12, 80),
		Size = UDim2.fromOffset(188, 394),
		CanvasSize = UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ZIndex = 12,
	})
	local divider = make("Frame", frame, "Divider", {
		Position = UDim2.fromOffset(208, 38),
		Size = UDim2.new(0, 1, 1, -52),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.45,
		ZIndex = 12,
	})
	divider:SetAttribute("ThemeBg", "Div")
	local previewHost = make("Frame", frame, "Preview", {
		Position = UDim2.fromOffset(220, 38),
		Size = UDim2.fromOffset(488, 132),
		BorderSizePixel = 0,
		ZIndex = 12,
		ClipsDescendants = true,
	})
	previewHost:SetAttribute("ThemeBg", "Pnl")
	outline(previewHost, "Outline")
	make("UICorner", previewHost, "Corner", { CornerRadius = UDim.new(0, 4) })
	local preview = Renderer.new(previewHost)
	preview.referenceHeight = 180
	local page = make("ScrollingFrame", frame, "Editor", {
		Position = UDim2.fromOffset(220, 214),
		Size = UDim2.fromOffset(488, 296),
		CanvasSize = UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ZIndex = 13,
	})

	local function dropdown(parent, name, get, options, x, y, w, callback, fonts)
		local b, label
		b, label = button(parent, name, "", x, y, w, 28, function()
			current.commit()
			if popup then
				current.closePopup()
				return
			end

			local choices = type(options) == "function" and options() or options
			local height = math.min(232, #choices * 30 + 8)
			local scale = math.max(0.01, frame.AbsoluteSize.X / 720)
			local pos = (b.AbsolutePosition - frame.AbsolutePosition) / scale
			popup = make("ScrollingFrame", frame, "Choices", {
				Position = UDim2.fromOffset(
					math.clamp(pos.X, 8, 720 - w - 8),
					math.clamp(pos.Y + 30, 32, 550 - height)
				),
				Size = UDim2.fromOffset(w, height),
				CanvasSize = UDim2.fromOffset(0, #choices * 30 + 8),
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ZIndex = 400,
			})
			popup:SetAttribute("ThemeBg", "Pnl")
			outline(popup, "Outline")
			for i, option in choices do
				local v = type(option) == "table" and option.value or option
				local title = type(option) == "table" and option.label or tostring(option)
				local _, t = button(popup, "Option" .. i, title, 4, 4 + (i - 1) * 30, w - 12, 28, function()
					current.closePopup()
					callback(v)
					sync()
				end
)
				if fonts then
					t.FontFace = Renderer.font({ Font = v, Bold = false, Italic = false })
					t.TextSize = 16
				end
			end

			Theme.applyTree(popup)
		end)
		if tips[name] then
			tooltip(b, tips[name])
		end

		return b,
			label,
			function()
				local v = get()
				label.Text = tostring(v or "")
				if fonts then
					label.FontFace = Renderer.font({ Font = v, Bold = false, Italic = false })
					label.TextSize = 15
				end
			end
	end

	text(frame, "CueListTitle", "Project subtitles", 12, 40, 188, 28)
	button(frame, "Replay", "Replay", 620, 178, 88, 28, function()
		replay = 0
	end)
	for i, name in { "Content", "Style", "Motion", "Presets" } do
		local b, l = button(frame, "Tab" .. name, name, 220 + (i - 1) * 99, 178, 93, 28, function()
			current.commit()
			pageName = name
			if name ~= "Style" then
				target = 0
			end

			pageSignature = ""
			page.CanvasPosition = Vector2.zero
			sync()
		end)
		local accent = make("Frame", b, "Selected", {
			Position = UDim2.new(0, 8, 1, -2),
			Size = UDim2.new(1, -16, 0, 2),
			BorderSizePixel = 0,
			ZIndex = b.ZIndex + 3,
		})
		accent:SetAttribute("ThemeBg", "MenuSel")
		tabs[name] = { label = l, accent = accent }
	end

	local _, modeLabel = button(frame, "Mode", "Simple", 220, 524, 92, 26, function()
		current.commit()
		advanced = not advanced
		if not advanced and target > 0 then
			target = 0
		end

		pageSignature = ""
		sync()
	end)
	local keyButton, keyLabel = button(frame, "Key", "Add key", 320, 524, 106, 26, function()
		current.commit()
		local at = offset()
		if at == 0 then
			return
		end

		edit(function(cue)
			for i, k in cue.Keys do
				if k.Frame == at then
					table.remove(cue.Keys, i)
					return
				end
			end

			Data.key(cue, at)
		end, "Subtitle key")
		sync()
	end)
	tooltip(keyButton, "add or remove a style key at the playhead")
	local frameLabel = text(frame, "FrameNumber", "", 572, 524, 136, 26)
	frameLabel.TextXAlignment = Enum.TextXAlignment.Right

	local function check(parent, name, title, x, y, w, get, set)
		local b = make("TextButton", parent, name, {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, 26),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = parent.ZIndex + 3,
		})
		if tips[name] then
			tooltip(b, tips[name])
		end

		local box = make("ImageLabel", b, "Check", {
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Image = "rbxassetid://129527857019669",
			ZIndex = b.ZIndex + 1,
		})
		text(b, "Title", title, 24, 0, w - 24, 26)
		b.Activated:Connect(function()
			current.commit()
			set(not get())
			sync()
		end)
		return b,
			function()
				box.ImageColor3 = get() == true and Color3.fromRGB(113, 255, 61)
					or Color3.fromRGB(58, 58, 58)
			end
	end

	local auto, autoFill = check(frame, "AutoKey", "Auto key", 440, 524, 122, function()
		return autoKey
	end, function(v)
		autoKey = v
	end)
	button(frame, "Add", "Add subtitle", 12, 484, 188, 30, function()
		current.commit()
		local t, e = Subtitles.add(nil, math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS))
		if e then
			chooseCue(t, e.Id, true)
		end
	end)
	button(frame, "Duplicate", "Duplicate", 12, 524, 90, 26, function()
		current.commit()
		if not event() then
			return
		end

		local e = Subtitles.duplicate(selectedTrack, selectedId)
		if e then
			chooseCue(selectedTrack, e.Id, true)
		end
	end)
	button(frame, "Delete", "Delete", 110, 524, 90, 26, function()
		current.commit()
		if event() then
			Subtitles.remove(selectedTrack, selectedId)
			sync()
		end
	end)

	local function field(name, title, y, get, set, multiline, lo, hi)
		text(page, name .. "Label", title, 0, y, 132, 26)
		local box = Tool.field(
			page,
			name,
			get() or "",
			UDim2.fromOffset(multiline and 0 or 138, y + (multiline and 28 or 0)),
			UDim2.fromOffset(multiline and 476 or 338, multiline and 70 or 28)
		)
		box.FontFace = FONT
		box.TextSize = 13
		if tips[name] then
			tooltip(box, tips[name])
		end

		if multiline then
			box.MultiLine = true
			box.TextWrapped = true
			box.TextYAlignment = Enum.TextYAlignment.Top
			box.TextTruncate = Enum.TextTruncate.None
		end

		box.Focused:Connect(function()
			Raw.Timeline.Playing = false
			current.commit()
			local at = keyOffset()
			if event() then
				inputEdit = {
					track = selectedTrack,
					before = Events.snapshot(selectedTrack),
					offset = at,
					changed = false,
				}
			end
		end)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if syncing or not inputEdit then
				return
			end

			local v = box.Text
			if lo then
				v = tonumber(v)
				if not v or v ~= v or math.abs(v) == math.huge then
					return
				end

				v = math.clamp(v, lo, hi)
			end

			set(v)
		end)
		if lo then
			require("NumericInput").bind(box, {
				step = (name == "Start" or name == "Duration" or name == "Size") and 1 or 0.1,
				min = lo,
				max = hi,
			})
		end

		box.FocusLost:Connect(function()
			current.commit()
			sync()
		end)
		bind(function()
			if box:IsFocused() then
				return
			end

			local v = get()
			if type(v) == "number" then
				v = math.round(v * 1000) / 1000
			end

			v = tostring(v or "")
			if box.Text ~= v then
				box.Text = v
			end
		end)
		return y + (multiline and 110 or 38)
	end

	local function numeric(name, title, y, lo, hi)
		return field(name, title, y, function()
			return value(name)
		end, function(v)
			setValue(name, v)
		end, false, lo, hi)
	end

	local function choice(name, title, y, get, options, set, fonts)
		text(page, name .. "Label", title, 0, y, 132, 28)
		local _, _, update = dropdown(page, name, get, options, 138, y, 338, set, fonts)
		bind(update)
		return y + 38
	end

	local function toggle(name, title, x, y, w)
		local _, update = check(page, name, title, x, y, w, function()
			return value(name)
		end, function(v)
			setValue(name, v)
		end)
		bind(update)
	end

	local function color(name, title, y, gradient)
		text(page, name .. "Label", title, 0, y, 132, 28)
		local b, l
		b, l = button(page, name, "", 138, y, 338, 28, function()
			current.commit()
			local s = style()
			if not s then
				return
			end

			local at = keyOffset()
			pickerEdit = {
				track = selectedTrack,
				before = Events.snapshot(selectedTrack),
				offset = at,
				changed = false,
			}
			current.pickerAnchor = b
			local stops = { Data.color(value(name)) }
			if gradient and target == 0 and s.Gradient then
				table.insert(stops, Data.color(s.GradientColor))
			end

			Picker.open({ ScreenGui = current.gui }, b, { stops = stops, rot = s.GradientAngle }, function(
				v
			)
				edit(function(cue)
					local k = Data.key(cue, at)
					if not k then
						return
					end

					if target > 0 and name == "Color" then
						local index = tostring(target)
						k.Value.Words[index] = k.Value.Words[index] or {}
						k.Value.Words[index].Color = v.stops[1]:ToHex()
					else
						k.Value[property(name)] = v.stops[1]:ToHex()
					end

					if gradient and target == 0 then
						k.Value.Gradient = #v.stops > 1
						k.Value.GradientColor = (v.stops[2] or v.stops[1]):ToHex()
						k.Value.GradientAngle = v.rot
					end
				end, "Subtitle color")
			end
)
		end)
		local swatch = make("Frame", b, "Swatch", {
			Position = UDim2.fromOffset(9, 7),
			Size = UDim2.fromOffset(28, 14),
			BorderSizePixel = 0,
			ZIndex = b.ZIndex + 4,
		})
		local g = make("UIGradient", swatch, "Gradient", {})
		bind(function()
			local s = style()
			if not s then
				return
			end

			local first = Data.color(value(name))
			local last = gradient and target == 0 and s.Gradient and Data.color(s.GradientColor)
				or first
			swatch.BackgroundColor3 = Color3.new(1, 1, 1)
			g.Color = ColorSequence.new(first, last)
			g.Rotation = s.GradientAngle
			l.Text = gradient and target == 0 and s.Gradient and "Gradient" or "#" .. value(name)
		end)
		return y + 38
	end

	paintPage = function()
		current.closePopup()
		bindings = {}
		for _, o in page:GetChildren() do
			o:Destroy()
		end

		local y = 0
		local e = event()
		if not e or not e.Subtitle then
			page.CanvasSize = UDim2.new()
			return
		end

		local cue = e.Subtitle
		if pageName == "Content" then
			y = field("Text", "Caption", y, function()
				return style().Text
			end, function(v)
				setValue("Text", v)
			end, true)
			y = field("Speaker", "Speaker", y, function()
				return style().Speaker
			end, function(v)
				setValue("Speaker", v)
			end)
			y = field("Image", "Image ID", y, function()
				return style().Image
			end, function(v)
				setValue("Image", v)
			end)
			page.Image.Size = UDim2.fromOffset(238, 28)
			button(page, "ImageLibrary", "Library", 384, y - 38, 92, 28, function()
				current.commit()
				local library = refs.State.Library
				if not library then
					return
				end

				local ownerTrack, ownerId, at = selectedTrack, selectedId, keyOffset()
				library.openImages(current, function(image)
					if
						current.closed
						or Events.all()[ownerTrack.Rig] ~= ownerTrack
						or not ownerTrack.Events[ownerId]
					then
						return
					end

					Subtitles.edit(ownerTrack, ownerId, function(c)
						local k = Data.key(c, at)
						if k then
							k.Value.Image = tostring(image)
						end
					end, "Subtitle image")
					sync()
				end, current.docked and current.widget or current.gui)
			end)
			y = field("StartFrame", "Start frame", y, function()
				return event().Frame
			end, function(v)
				edit(function(_, item)
					item.Frame = Events.nextFrame(selectedTrack, math.round(v), selectedId)
				end, "Move subtitle")
			end, false, 0, 1000000)
			y = field("Duration", "Duration (frames)", y, function()
				return event().Subtitle.Duration
			end, function(v)
				edit(function(c)
					c.Duration = math.round(v)
				end, "Subtitle duration")
			end, false, 1, 1000000)
			if advanced then
				y = choice("ImageSide", "Image position", y, function()
					return style().ImageSide
				end, { "Left", "Right", "Above" }, function(v)
					setValue("ImageSide", v)
				end)
				y = choice("ImageShape", "Image shape", y, function()
					return style().ImageShape
				end, { "Circle", "Square" }, function(v)
					setValue("ImageShape", v)
				end)
				y = numeric("ImageSize", "Image size", y, 24, 160)
				y = field("Order", "Stack order", y, function()
					return event().Subtitle.Order
				end, function(v)
					edit(function(c)
						c.Order = math.round(v)
					end, "Subtitle order")
				end, false, -1000, 1000)
			end

			local _, update = check(page, "Enabled", "Enabled", 0, y, 160, function()
				return event().Enabled ~= false
			end, function(v)
				edit(function(_, item)
					item.Enabled = v
				end, "Toggle subtitle")
			end)
			bind(update)
			y += 34
		elseif pageName == "Style" then
			for i, option in { { "Caption", 0 }, { "Speaker", -1 } } do
				local b = button(page, "Target" .. option[1], option[1], (i - 1) * 160, y, 152, 28, function()
					current.commit()
					target = option[2]
					pageSignature = ""
					sync()
				end
)
				local line = make("Frame", b, "Selected", {
					Position = UDim2.new(0, 8, 1, -2),
					Size = UDim2.new(1, -16, 0, 2),
					BorderSizePixel = 0,
					Visible = option[2] == 0 and target >= 0 or target == option[2],
					ZIndex = b.ZIndex + 3,
				})
				line:SetAttribute("ThemeBg", "MenuSel")
			end

			y += 40
			if advanced and target ~= -1 then
				y = choice("Word", "Apply to", y, function()
					return target == 0 and "Whole caption" or "Word " .. target
				end, function()
					local out = { { label = "Whole caption", value = 0 } }
					local i = 0
					for word in style().Text:gmatch("%S+") do
						i += 1
						table.insert(out, { label = i .. "  " .. word, value = i })
						if i >= 300 then
							break
						end
					end

					return out
				end, function(v)
					target = v
					pageSignature = ""
				end)
			end

			if target <= 0 then
				y = choice(
					"Font",
					"Font",
					y,

					function()
						return value("Font")
					end,
					Data.fonts,

					function(v)
						setValue("Font", v)
					end,
					true
				)
				y = numeric("Size", "Size", y, 12, target == -1 and 72 or 96)
			end

			toggle("Bold", "Bold", 0, y, 120)
			toggle("Italic", "Italic", 138, y, 120)
			if target ~= -1 then
				toggle("Underline", "Underline", 276, y, 180)
			end

			y += 36
			y = color("Color", "Color", y, true)
			if target ~= -1 then
				toggle("Rainbow", "Rainbow", 0, y, 160)
				y += 34
				if value("Rainbow") and target == 0 then
					y = numeric("RainbowSpeed", "Speed", y, 0, 3)
					y = numeric("RainbowSpread", "Spread", y, 0, 2)
				end
			end

			if advanced and target > 0 then
				y = numeric("Jitter", "Letter shake", y, 0, 20)
			end

			if advanced and target <= 0 then
				y = numeric("Outline", "Outline", y, 0, 5)
				y = color("OutlineColor", "Outline color", y)
				if target == -1 then
					y = numeric("NameOffset", "Vertical offset", y, -20, 30)
				else
					for _, f in
						{
							{ "BackgroundOpacity", "Background", 0, 1 },
							{ "Width", "Caption width", 0.2, 0.95 },
							{ "Padding", "Padding", 0, 40 },
							{ "Scale", "Scale", 0.4, 2 },
							{ "Rotation", "Rotation", -45, 45 },
							{ "Opacity", "Opacity", 0, 1 },
							{ "X", "Horizontal offset", -0.4, 0.4 },
							{ "Y", "Vertical offset", -0.4, 0.4 },
						}
					do
						y = numeric(f[1], f[2], y, f[3], f[4])
					end

					y = color("Background", "Panel color", y)
					y = choice("Position", "Position", y, function()
						return style().Position
					end, { "Bottom", "Center", "Top" }, function(v)
						setValue("Position", v)
					end)
					y = choice("Align", "Alignment", y, function()
						return style().Align
					end, { "Center", "Left", "Right" }, function(v)
						setValue("Align", v)
					end)
				end
			end
		elseif pageName == "Motion" then
			y = choice(
				"Entrance",
				"Entrance",
				y,

				function()
					return event().Subtitle.Entrance
				end,
				Data.motions,

				function(v)
					edit(function(c)
						c.Entrance = v
					end, "Subtitle entrance")
					replay = 0
				end
			)
			y = field("InFrames", "Frames in", y, function()
				return event().Subtitle.InFrames
			end, function(v)
				edit(function(c)
					c.InFrames = math.round(v)
				end, "Subtitle entrance")
			end, false, 0, cue.Duration)
			y = choice(
				"Exit",
				"Exit",
				y,

				function()
					return event().Subtitle.Exit
				end,
				Data.motions,

				function(v)
					edit(function(c)
						c.Exit = v
					end, "Subtitle exit")
					replay = 0
				end
			)
			y = field("OutFrames", "Frames out", y, function()
				return event().Subtitle.OutFrames
			end, function(v)
				edit(function(c)
					c.OutFrames = math.round(v)
				end, "Subtitle exit")
			end, false, 0, cue.Duration)
			y = numeric("Jitter", "Letter shake", y, 0, 20)
			y = numeric("JitterSpeed", "Shake speed", y, 1, 60)
			y = numeric("JitterDecay", "Settle (seconds)", y, 0, 10)
			if advanced then
				y = numeric("Wave", "Wave", y, 0, 20)
				y = numeric("Pulse", "Pulse", y, 0, 0.4)
			end
		elseif pageName == "Presets" then
			for i, preset in Data.presets do
				local x = ((i - 1) % 2) * 244
				local py = math.floor((i - 1) / 2) * 68
				local b, l = button(page, "Preset" .. i, preset.Name, x, py, 232, 60, function()
					current.commit()
					target = 0
					local at = keyOffset()
					edit(function(c)
						local p = Data.preset(preset.Name, c)
						local k = Data.key(c, at)
						if at == 0 then
							c.Base = p.Base
						elseif k then
							k.Value = p.Base
						end

						c.Entrance = p.Entrance
						c.Exit = p.Exit
						c.InFrames = p.InFrames
						c.OutFrames = p.OutFrames
						c.Preset = p.Preset
					end, "Subtitle preset")
					replay = 0
					sync()
				end)
				local ps = Data.preset(preset.Name).Base
				l.FontFace = Renderer.font(ps)
				l.TextSize = math.clamp(ps.Size * 0.5, 14, 20)
				local selected = outline(b, "Selection")
				selected:SetAttribute("ThemeStrk", "MenuSel")
				bind(function()
					selected.Enabled = event().Subtitle.Preset == preset.Name
				end)
			end

			y = math.ceil(#Data.presets / 2) * 68
		end

		page.CanvasSize = UDim2.fromOffset(0, y + 8)
		Theme.applyTree(page)
	end

	chooseCue = function(t, id, jump)
		current.commit()
		current.closePopup()
		if current.pickerAnchor and Picker.isOpen(current.pickerAnchor) then
			Picker.close(true)
		end

		selectedTrack, selectedId = t, id
		target = 0
		pageSignature = ""
		if jump and event() then
			Subtitles.jump(
				event().Frame + math.min(event().Subtitle.InFrames, event().Subtitle.Duration - 1)
			)
		end

		require("EventTrackList").select(refs.State.Timeline, t.Rig, id)
		sync()
	end

	sync = function()
		if current.closed then
			return
		end

		syncing = true
		local entries = Subtitles.entries(false)
		if not event() or not event().Subtitle then
			local first = entries[1]
			selectedTrack = first and first.track
			selectedId = first and first.event.Id
			pageSignature = ""
		end

		local keep = {}
		for i, entry in entries do
			keep[entry.id] = true
			local row = cueRows[entry.id]
			if not row then
				local b = make("TextButton", list, "Cue" .. entry.event.Id, {
					Text = "",
					Size = UDim2.fromOffset(180, 40),
					BorderSizePixel = 0,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					ZIndex = 15,
				})
				make("UICorner", b, "Corner", { CornerRadius = UDim.new(0, 3) })
				local l = text(b, "Caption", "", 10, 1, 160, 22)
				l.TextXAlignment = Enum.TextXAlignment.Left
				l.TextTruncate = Enum.TextTruncate.AtEnd
				local timing = text(b, "Time", "", 10, 22, 160, 16)
				timing.TextSize = 10
				local accent = make("Frame", b, "Accent", {
					Position = UDim2.fromOffset(0, 6),
					Size = UDim2.new(0, 2, 1, -12),
					BorderSizePixel = 0,
					ZIndex = b.ZIndex + 3,
				})
				row = { button = b, label = l, time = timing, accent = accent }
				cueRows[entry.id] = row
				b.Activated:Connect(function()
					chooseCue(entry.track, entry.event.Id, true)
				end)
				b.MouseEnter:Connect(function()
					row.hover = true
					sync()
				end)
				b.MouseLeave:Connect(function()
					row.hover = false
					sync()
				end)
			end

			local e = entry.event
			row.button.Position = UDim2.fromOffset(0, (i - 1) * 42)
			row.label.Text = e.Subtitle.Base.Text:gsub("\n", " ")
			row.time.Text = e.Frame .. " - " .. (e.Frame + e.Subtitle.Duration)
			local selected = selectedTrack == entry.track and selectedId == e.Id
			row.accent.Visible = selected
			row.accent.BackgroundColor3 = Theme.get("KfS", Color3.new(1, 1, 1))
			row.button.BackgroundColor3 = Theme.get("MenuSel", Color3.fromRGB(70, 50, 90))
			row.button.BackgroundTransparency = selected and 0.72 or row.hover and 0.88 or 1
			row.label.TextTransparency = e.Enabled == false and 0.6 or selected and 0 or 0.2
			row.time.TextTransparency = selected and 0.3 or 0.5
		end

		for id, row in cueRows do
			if not keep[id] then
				row.button:Destroy()
				cueRows[id] = nil
			end
		end

		list.CanvasSize = UDim2.fromOffset(0, #entries * 42)
		local s = style()
		local schema = table.concat({
			tostring(selectedTrack),
			tostring(selectedId),
			pageName,
			tostring(advanced),
			tostring(target),
			tostring(s and value("Rainbow")),
		}, "|")
		if schema ~= pageSignature and not inputEdit and not pickerEdit then
			pageSignature = schema
			paintPage()
		end

		if s then
			for _, update in bindings do
				update()
			end
		end

		for name, tab in tabs do
			tab.accent.Visible = name == pageName
			tab.label.TextTransparency = name == pageName and 0 or 0.3
		end

		modeLabel.Text = advanced and "Advanced" or "Simple"
		auto.Visible = advanced
		autoFill()
		local e = event()
		local at = offset()
		local keyed = false
		if e then
			for _, k in e.Subtitle.Keys do
				if k.Frame == at then
					keyed = true
				end
			end
		end

		keyLabel.Text = keyed and "Remove key" or "Add key"
		keyButton.Interactable = e ~= nil and at > 0
		keyButton:SetAttribute("Ready", e ~= nil and at > 0)
		frameLabel.Text = "Frame " .. math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS)
		syncing = false
	end

	current.refresh = sync
	tooltip(frame.Replay, tips.Replay)
	tooltip(frame.Mode, tips.Mode)
	current.setPage = function(name)
		current.commit()
		pageName = name
		if name ~= "Style" then
			target = 0
		end

		pageSignature = ""
		sync()
	end

	current.unsubscribe = Theme.onChanged(function()
		if not current.closed then
			sync()
		end
	end)
	local elapsed = 0
	table.insert(
		current.connections,
		game:GetService("RunService").RenderStepped:Connect(function(dt)
			if current.closed then
				return
			end

			previewClock += dt
			if pickerEdit and not Picker.isOpen(current.pickerAnchor) then
				current.commit()
			end

			local e = event()
			if e and e.Subtitle then
				local age = Raw.Timeline.CurrentTime * Raw.Timeline.FPS - e.Frame
				if replay then
					replay += dt * Raw.Timeline.FPS
					age = replay
					if replay >= e.Subtitle.Duration then
						replay = nil
					end
				elseif not Raw.Timeline.Playing then
					local first = math.min(e.Subtitle.InFrames, e.Subtitle.Duration - 1)
					age = math.clamp(
						age,
						first,
						math.max(first, e.Subtitle.Duration - e.Subtitle.OutFrames - 1)
					)
				end

				preview:step(
					{ { id = selectedId, event = e, track = selectedTrack } },
					e.Frame + age,
					Raw.Timeline.FPS,
					if Raw.Timeline.Playing then nil else previewClock
				)
			else
				preview:clear()
			end

			elapsed += dt
			if elapsed >= 0.1 then
				elapsed = 0
				sync()
			end
		end)
	)
	current.gui.Destroying:Once(function()
		preview:destroy()
		if view == current then
			view = nil
		end
	end)
	sync()
	Theme.applyTree(frame)
	return frame
end

function Window.isOpen()
	return view ~= nil
end

function Window.toggle()
	if view then
		Window.close()
	else
		Window.open()
	end
end

return Window
