--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preferences = require("Preferences")
local DockHost = require("DockHost")
local AppState = require("State")
local Motion = require("Motion")
local Chrome = require("Chrome")

local Theme = require("Theme")
local HoverDialog = require("HoverDialog")
local WindowFX = require("WindowFX")
local Input = require("UserInputService")
local GraphView = {}
local View = {}
View.__index = View
local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular)
local BOLD = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local COLORS = {
	X = Color3.fromRGB(238, 112, 121),
	Y = Color3.fromRGB(125, 204, 151),
	Z = Color3.fromRGB(113, 167, 242),
}
local ACCENT = Color3.fromRGB(181, 144, 237)
local TEXT = Color3.fromRGB(225, 225, 235)
local MUTED = Color3.fromRGB(144, 146, 165)
local MAX_LINES = 1000
local Activity = require("Activity")
local DOCK_SETTING = "EclipseAnimator_GraphDocked"
local GEOMETRY_SETTING = "EclipseAnimator_GraphWindow"
local ICONS = {
	eye = "rbxassetid://139145796514555",
	hidden = "rbxassetid://110103359407250",
	dock = "rbxassetid://110982451175098",
	lock = "rbxassetid://77905869505487",
	unlock = "rbxassetid://131252285085986",
}
local ROW = 24

local function make(class, parent, name, props)
	local item = Instance.new(class)

	item.Name = name
	for k, v in props or {} do
		item[k] = v
	end

	item.Parent = parent
	return item
end

local function round(item, radius)
	make("UICorner", item, "Corners", { CornerRadius = UDim.new(0, radius or 5) })
end

local function connect(self, signal, callback)
	local c = signal:Connect(callback)
	table.insert(self.connections, c)
	return c
end

local function frame(parent, name, position, size, color, z)
	return make("Frame", parent, name, {
		Position = position,
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z or 201,
	})
end

local function label(parent, name, text, position, size, textSize, color)
	return make("TextLabel", parent, name, {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = FONT,
		TextSize = textSize or 14,
		TextColor3 = color or TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 205,
	})
end

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < 1e14
end

local function fmt(value)
	if math.abs(value) < 1e-8 then
		value = 0
	end

	if math.abs(value) >= 100000 then
		return string.format("%.3g", value)
	end

	return string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function niceStep(span, pixels)
	local raw = math.max(span, 1e-9) / math.max(2, math.floor(pixels / 85))
	local power = 10 ^ math.floor(math.log10(raw))
	local ratio = raw / power
	return (ratio <= 1 and 1 or ratio <= 2 and 2 or ratio <= 5 and 5 or 10) * power
end

local function clipped(a, b, w, h)
	local d = b - a
	local low, high = 0, 1

	local function edge(p, q)
		if math.abs(p) < 1e-10 then
			return q >= 0
		end

		local t = q / p
		if p < 0 then
			if t > high then
				return false
			end

			low = math.max(low, t)
		else
			if t < low then
				return false
			end

			high = math.min(high, t)
		end

		return true
	end

	if not (edge(-d.X, a.X) and edge(d.X, w - a.X) and edge(-d.Y, a.Y) and edge(d.Y, h - a.Y)) then
		return
	end

	return a + d * low, a + d * high
end

function View:_action(action, payload)
	if not self.destroyed then
		self.callback(action, payload)
	end
end

function View:_scale()
	local parent = self.frame.Parent
	local width = self.frame.Size.X.Offset
		+ self.frame.Size.X.Scale * (parent and parent.AbsoluteSize.X or 0)
	return math.max(0.01, self.frame.AbsoluteSize.X / math.max(1, width))
end

function View:mousePosition()
	return self.docked and self.widget:GetRelativeMousePosition() or Input:GetMouseLocation()
end

function View:isKeyDown(key)
	if self.docked then
		return self.heldKeys[key] == true
	end

	return Input:IsKeyDown(key)
end

function View:_latchTip(button, text)
	self.tipBindings = self.tipBindings or {}
	if self.tipBindings[button] then
		self.tipBindings[button]()
		self.tipBindings[button] = nil
	end

	local tooltip = self.docked and self.widgetHover or self.options.hoverDialog
	if tooltip then
		self.tipBindings[button] = tooltip:latchToInstance(button, text)
	end
end

function View:_tip(button, text)
	self.tipButtons[button] = text
	self:_latchTip(button, text)
end

function View:_hideTips()
	for _, tip in { self.options.hoverDialog, self.widgetHover } do
		if tip then
			for button in self.tipButtons do
				tip:disappear(button)
			end
		end
	end
end

function View:_button(parent, name, text, pos, size, action, tip)
	local button = make("TextButton", parent, name, {
		Text = text,
		Position = pos,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		TextColor3 = self.colors.text,
		FontFace = FONT,
		TextSize = 13,
		ZIndex = 207,
	})
	if action then
		connect(self, button.Activated, function()
			self:_action(action)
		end)
	end

	if tip then
		self:_tip(button, tip)
	end

	return button
end

local function luminance(c)
	local function linear(v)
		return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end

	return 0.2126 * linear(c.R) + 0.7152 * linear(c.G) + 0.0722 * linear(c.B)
end

local function contrast(a, b)
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

local function readable(color, bg, minimum)
	if contrast(color, bg) >= minimum then
		return color
	end

	local black, white = Color3.new(), Color3.new(1, 1, 1)
	local target = contrast(black, bg) > contrast(white, bg) and black or white
	for i = 1, 20 do
		local adjusted = color:Lerp(target, i / 20)
		if contrast(adjusted, bg) >= minimum then
			return adjusted
		end
	end

	return target
end

local function original(instance, property, fallback)
	if not instance then
		return fallback
	end

	local stored = instance:GetAttribute("EOrig_" .. property)
	if stored ~= nil then
		return stored
	end

	local ok, value = pcall(function()
		return instance[property]
	end)
	return ok and value or fallback
end

local function cloneDecoration(source, parent, class)
	local item = source and source:FindFirstChildOfClass(class)
	if item then
		local copy = item:Clone()
		copy.Parent = parent
		return copy
	end
end

function View:_background()
	local override = Theme.getOverride and Theme.getOverride("Bg")
	local stops = {}
	if override and override.stops then
		for i, color in override.stops do
			table.insert(
				stops,
				ColorSequenceKeypoint.new((i - 1) / math.max(1, #override.stops - 1), color)
			)
		end

		if #stops == 1 then
			return ColorSequence.new(stops[1].Value), override.rot or self.backgroundRotation
		end

		return ColorSequence.new(stops), override.rot or self.backgroundRotation
	end

	return self.backgroundSequence, self.backgroundRotation
end

function View:_palette()
	local function get(key)
		return Theme.get(key, self.defaults[key])
	end

	local sequence = self:_background()
	local top, bottom = sequence.Keypoints[1].Value, sequence.Keypoints[#sequence.Keypoints].Value
	local c = {
		bg = top,
		panel = top,
		top = get("Top"),
		border = get("Strk"),
		divider = get("Div"),
		menu = get("Menu"),
		selection = get("Sel"),
		scroll = get("Scr"),
	}

	local function overBackground(color, minimum)
		for _, stop in sequence.Keypoints do
			color = readable(color, stop.Value, minimum)
		end

		return color
	end

	c.text = overBackground(get("Txt"), 4.5)
	c.topText = readable(get("TopT"), c.top, 4.5)
	c.tick = overBackground(get("Tick"), 3)
	c.menuText = readable(get("Txt"), c.menu, 4.5)
	c.muted = overBackground(get("Tick"), 3)
	c.grid = top:Lerp(c.text, 0.16)
	c.zero = top:Lerp(c.text, 0.3)
	c.playhead = get("Ph")
	c.playheadText = readable(self.playheadTextDefault, c.playhead, 4.5)
	c.selectedKey = readable(get("KfS"), c.panel, 3)
	c.W = c.text
	c.X = overBackground(COLORS.X, 3)
	c.Y = overBackground(Preferences.axisColor("Y", COLORS), 3)
	c.Z = overBackground(Preferences.axisColor("Z", COLORS), 3)
	c.slider = get("Slider")
	c.sliderHandle = Theme.getOverride("Slider") and c.slider:Lerp(Color3.new(1, 1, 1), 0.35)
		or self.sliderHandleDefault
	c.selectionLine = readable(c.selection, c.panel, 3)
	return c
end

function View:_bind(item, property, key)
	table.insert(self.bindings, { item = item, property = property, key = key })
	item[property] = self.colors[key]
	return item
end

function View:_applyTheme()
	if self.destroyed then
		return
	end

	self.colors = self:_palette()
	self.backgroundGradient.Color, self.backgroundGradient.Rotation = self:_background()
	for _, binding in self.bindings do
		if binding.item.Parent then
			binding.item[binding.property] = self.colors[binding.key]
		end
	end

	Theme.applyInstance(self.outline)
	Theme.applyInstance(self.channelDivider)
	if self.onTheme then
		self.onTheme()
	end

	self:_refreshRows()
	if self.menu then
		self:closeMenu()
	end

	if self.frame.Visible then
		self:render()
	end
end

function View:_pool(kind, parent, class)
	local pool = self.pools[kind]
	if not pool then
		pool = { items = {}, used = 0, parent = parent, class = class }
		self.pools[kind] = pool
	end

	pool.used += 1
	local item = pool.items[pool.used]
	if not item then
		item = make(class or "Frame", parent, kind .. pool.used, {
			BorderSizePixel = 0,
			BackgroundTransparency = class == "TextLabel" and 1 or 0,
			ZIndex = 204,
		})
		if class == "TextLabel" then
			item.FontFace = FONT
			item.TextSize = self.tickTextSize
			item.TextColor3 = self.colors.tick
			item.TextXAlignment = Enum.TextXAlignment.Center
		end

		pool.items[pool.used] = item
	end

	if class == "TextLabel" then
		item.TextColor3 = self.colors.tick
	end

	if not item.Visible then
		item.Visible = true
	end

	return item
end

function View:_line(kind, a, b, color, thickness, transparency)
	local w, h = self.plot.AbsoluteSize.X, self.plot.AbsoluteSize.Y
	a, b = clipped(a, b, w, h)
	if not a then
		return
	end

	local delta = b - a
	if delta.Magnitude < 0.05 then
		return
	end

	local line = self:_pool(kind, kind == "grid" and self.plot or self.scene)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale((a.X + b.X) * 0.5 / w, (a.Y + b.Y) * 0.5 / h)

	local size =
		UDim2.fromScale(delta.Magnitude / w, math.max(1, (thickness or 1) * self:_scale()) / h)
	local rotation = math.deg(math.atan2(delta.Y, delta.X))
	if line.Size ~= size then
		line.Size = size
	end

	if line.Rotation ~= rotation then
		line.Rotation = rotation
	end

	if line.BackgroundColor3 ~= color then
		line.BackgroundColor3 = color
	end

	if line.BackgroundTransparency ~= (transparency or 0) then
		line.BackgroundTransparency = transparency or 0
	end

	line.ZIndex = kind == "grid" and 202 or kind == "handles" and 204 or 205
	return true
end

function View:_diamond(point, color, selected, size, kind, opacity)
	if
		point.X < -5
		or point.Y < -5
		or point.X > self.plot.AbsoluteSize.X + 5
		or point.Y > self.plot.AbsoluteSize.Y + 5
	then
		return
	end

	if self.markerCount >= 1200 then
		return
	end

	self.markerCount += 1
	local item = self:_pool(kind or "keys", self.scene)
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position =
		UDim2.fromScale(point.X / self.plot.AbsoluteSize.X, point.Y / self.plot.AbsoluteSize.Y)
	item.Size = UDim2.fromOffset(size or 7, size or 7)
	item.Rotation = 45
	item.BackgroundColor3 = selected and self.colors.selectedKey or color
	item.BackgroundTransparency = selected and 0 or (opacity or 0)
	item.ZIndex = kind == "handlePoints" and 212 or 209
end

function View:_dashed(kind, a, b, color, dash, gap, transparency)
	local delta = b - a
	local length = delta.Magnitude
	if length < 1 then
		return
	end

	local unit = delta / length
	local d, count = 0, 0
	while d < length and count < 160 do
		local e = math.min(length, d + dash)
		self:_line(kind, a + unit * d, a + unit * e, color, 1, transparency)
		d = e + gap
		count += 1
	end
end

function View:_drawEnvelope(channel)
	local m = channel.envelope
	local w = self.plot.AbsoluteSize.X
	local s = self:_scale()
	local color = self.colors.text
	for _, value in { m.Reference + m.Min, m.Reference + m.Max } do
		local y = self:toScreen(0, value, channel).Y
		self:_dashed("envelope", Vector2.new(0, y), Vector2.new(w, y), color, 10 * s, 8 * s, 0.4)
	end

	for _, p in m.Points do
		for _, value in { p.Min, p.Max } do
			self:_diamond(self:toScreen(p.Frame, value, channel), color, false, 5, "envelopePoints")
		end
	end
end

function View:toast(text)
	if self.destroyed or not text or text == "" then
		return
	end

	self.toastLabel.Text = text
	self.toastLabel.Visible = true
	self.toastLabel.TextTransparency = 0
	self.toastLabel.BackgroundTransparency = 0.25
	self.toastVersion = (self.toastVersion or 0) + 1
	local version = self.toastVersion
	task.delay(3.5, function()
		if self.destroyed or self.toastVersion ~= version then
			return
		end

		self.toastLabel.Visible = false
	end)
end

function View:setSidebarFrame(frame)
	self.sidebarFrame = frame
	self:_layoutSidebar()
end

function View:setSidebar(open)
	self.sidebarOpen = open == true
	self.modifiersLabel.Text = self.sidebarOpen and "MODIFIERS ✓" or "MODIFIERS"
	self:_layoutSidebar()
end

function View:_layoutSidebar()
	if self.destroyed then
		return
	end

	local width = 0
	if self.sidebarOpen then
		local available = self.body.AbsoluteSize.X / self:_scale()
		width = math.floor(math.clamp(available - 175 - 189 - 180, 190, 250))
	end

	self.sidebarWidth = width
	self.chart.Size = UDim2.new(1, -189 - width, 1, -20)
	self.valueScrollbar.Position = UDim2.new(1, -14 - width, 0, 18)
	self.scrollbar.Size = UDim2.new(1, -243 - width, 0, 14)
	if self.sidebarFrame then
		self.sidebarFrame.Position = UDim2.new(1, -width, 0, 0)
		self.sidebarFrame.Size = UDim2.new(0, width, 1, -2)
	end
end

function View:toScreen(frameValue, value, channel)
	if channel then
		value = (value - (channel.displayOffset or 0)) / (channel.displayScale or 1)
		if channel.displayClamp then
			value = math.clamp(value, -channel.displayClamp, channel.displayClamp)
		end
	end

	local v = self.viewport
	local size = self.plot.AbsoluteSize
	return Vector2.new(
		(frameValue - v.frameMin) / (v.frameMax - v.frameMin) * size.X,
		(v.valueMax - value) / (v.valueMax - v.valueMin) * size.Y
	)
end

function View:fromScreen(point, channel)
	local v = self.viewport
	local size = self.plot.AbsoluteSize
	local value = v.valueMax - point.Y / math.max(size.Y, 1) * (v.valueMax - v.valueMin)
	if channel then
		value = value * (channel.displayScale or 1) + (channel.displayOffset or 0)
	end

	return v.frameMin + point.X / math.max(size.X, 1) * (v.frameMax - v.frameMin), value
end

function View:_hitPosition(hit)
	return hit.normalized * self.plot.AbsoluteSize + (self.sceneOffset or Vector2.zero)
end

function View:hitTest(point)
	local best, distance = nil, math.huge
	for _, hit in self.hits do
		local d = (self:_hitPosition(hit) - point).Magnitude
		if d <= (hit.kind == "handle" and 10 or 9) * self:_scale() then
			local priority = (hit.kind == "handle" and -2 or 0) - (hit.channel.selected and 2 or 0)
			priority *= self:_scale()
			if d + priority < distance then
				best, distance = hit, d + priority
			end
		end
	end

	return best
end

function View:coincidentKeys(hit)
	local found = {}
	local point = self:_hitPosition(hit)
	for _, entry in self.hits do
		if
			entry.kind == "key"
			and entry.key.value == hit.key.value
			and entry.channel.displayOffset == hit.channel.displayOffset
			and entry.channel.displayScale == hit.channel.displayScale
			and (self:_hitPosition(entry) - point).Magnitude < 0.75 * self:_scale()
		then
			table.insert(found, entry)
		end
	end

	return found
end

function View:keysInRect(a, b)
	local low, high = a:Min(b), a:Max(b)
	local found = {}
	for _, hit in self.hits do
		local p = self:_hitPosition(hit)
		if
			hit.kind == "key"
			and p.X >= low.X
			and p.Y >= low.Y
			and p.X <= high.X
			and p.Y <= high.Y
		then
			table.insert(found, hit)
		end
	end

	return found
end

function View:setPlayhead(value)
	if not self.viewport or not finite(value) then
		return
	end

	self.viewport.playhead = value
	local alpha = (value - self.viewport.frameMin)
		/ (self.viewport.frameMax - self.viewport.frameMin)
	local visible = alpha >= 0 and alpha <= 1
	if self.playheadCursor.Visible ~= visible then
		self.playheadCursor.Visible = visible
	end

	local position = UDim2.new(alpha, 48 - 49 * alpha, 0, 0)
	if self.playheadCursor.Position ~= position then
		self.playheadCursor.Position = position
	end

	local text = tostring(math.floor(value + 1e-6))
	if self.playheadLabel.Text ~= text then
		self.playheadLabel.Text = text
	end
end

function View:setStatus(text)
	self.statusText = text or ""
end

function View:setPlaying(value)
	self.playing = value
end

function View:setSnap(value)
	self.snapping = value
end

function View:setInspector(channel, key)
	self.inspectorChannel, self.inspectorKey = channel, key
end

function View:closeMenu()
	if self.selectionBox then
		self.selectionBox.Visible = false
	end

	local menu = self.menu
	self:closeSubmenu()
	self.menu = nil
	if menu then
		menu:Destroy()
	end
end

function View:closeSubmenu()
	if self.menu then
		require("KeyframeMenu").closeCurvePicker(self.menu)
	end

	local submenu, button = self.submenu, self.submenuButton
	self.submenu = nil
	self.submenuButton = nil
	if button then
		button.BackgroundTransparency = 1
	end

	if submenu then
		submenu:Destroy()
	end
end

function View:menuHover(point)
	if not self.submenu or not self.submenuButton then
		return
	end

	local a, b = self.submenuButton, self.submenu
	local low = Vector2.new(
		math.min(a.AbsolutePosition.X, b.AbsolutePosition.X),
		math.min(a.AbsolutePosition.Y, b.AbsolutePosition.Y)
	) - Vector2.new(6, 6)
	local high = Vector2.new(
		math.max(a.AbsolutePosition.X + a.AbsoluteSize.X, b.AbsolutePosition.X + b.AbsoluteSize.X),
		math.max(a.AbsolutePosition.Y + a.AbsoluteSize.Y, b.AbsolutePosition.Y + b.AbsoluteSize.Y)
	) + Vector2.new(6, 6)
	if point.X < low.X or point.Y < low.Y or point.X > high.X or point.Y > high.Y then
		self:closeSubmenu()
	end
end

function View:menuContains(point)
	for _, menu in
		{
			self.menu,
			self.submenu,
			self.menu and require("KeyframeMenu").curvePickerFrame(self.menu),
		}
	do
		if menu and menu.Visible then
			local a, z = menu.AbsolutePosition, menu.AbsoluteSize
			if
				point.X >= a.X
				and point.Y >= a.Y
				and point.X <= a.X + z.X
				and point.Y <= a.Y + z.Y
			then
				return true
			end
		end
	end

	return false
end

function View:menuInput(input)
	if not self.menu or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if not self:menuContains(self:mousePosition()) then
		self.menuDismissInput = input
		task.defer(function()
			if self.menuDismissInput == input then self.menuDismissInput = nil end
		end)
		self:closeMenu()
	end
end

function View:openMenu(screen, section)
	if self.destroyed or not self.frame.Visible then
		return
	end

	self:closeMenu()
	local key, channel = self.inspectorKey, self.inspectorChannel
	local rotationMotor = section == "rotation" and self.rotationMotor or nil
	self.rotationMotor = nil
	if section and section ~= "rotation" and not key then
		return
	end

	local template = self.options.templates and self.options.templates.Dropdown
	if not template then
		return
	end

	local Dropdown = require("DropdownBuilder")
	local configs = require("DropdownConfigs")
	local width = configs.MainSelection.width
	local icons = {
		filterRotation = "rbxassetid://85012573369942",
		editFrame = "rbxassetid://113995793536843",
		editValue = "rbxassetid://96817013607764",
		snap = "rbxassetid://137816284187553",
	}

	local function entriesFor(kind)
		local entries = {}
		if kind == "rotation" then
			table.insert(
				entries,
				{ text = "Quaternion", action = "rotationMode", value = "Quaternion" }
			)
			for _, order in require("GraphCurves").orders do
				table.insert(
					entries,
					{ text = "Euler " .. order, action = "rotationMode", value = order }
				)
			end
		elseif kind == "interpolation" then
			for _, value in { "Bezier", "Linear", "Constant" } do
				table.insert(entries, { text = value, action = "interpolation", value = value })
			end
		elseif kind == "handles" then
			for _, value in { "AutoClamped", "Automatic", "Aligned", "Free", "Vector" } do
				table.insert(entries, {
					text = value == "AutoClamped" and "Auto Clamped" or value,
					action = "handleType",
					value = value,
				})
			end
		else
			table.insert(entries, { text = "Rotation Mode", section = "rotation" })
			table.insert(entries, { text = "Filter Rotation", action = "filterRotation" })
			if key then
				table.insert(entries, "divider")
				table.insert(entries, { text = "Frame", numeric = "editFrame", value = key.frame })
				table.insert(entries, { text = "Value", numeric = "editValue", value = key.value })
				table.insert(entries, "divider")
				table.insert(entries, { text = "Interpolation", section = "interpolation" })
				table.insert(entries, { text = "Handle Type", section = "handles" })
			else
				table.insert(entries, "divider")
			end

			table.insert(entries, { text = "Snap to Frames", action = "snap" })
		end

		return entries
	end

	local root, buildMenu

	local function hideSubmenu()
		self:closeSubmenu()
	end

	buildMenu = function(kind, parent, anchor)
		local entries, rows = entriesFor(kind), {}
		for i, entry in entries do
			if entry == "divider" then
				rows[i] = "divider"
				continue
			end

			local row = {
				id = "Graph" .. i,
				text = entry.text,
				submenu = entry.section ~= nil,
				checkable = entry.action == "snap",
				leftCheck = false,
				icon = icons[entry.action or entry.numeric],
				iconSize = { 0.12, 0.75 },
			}
			rows[i] = row
			local config
			if entry.section == "rotation" then
				row.icon = "rbxassetid://108133144074779"
			elseif entry.section then
				config =
					configs.MainSelection.rowsById[entry.section == "handles" and "HandleType" or "InterpolationMode"]
			elseif entry.action == "handleType" then
				config = configs.HandleType.rowsById[entry.value]
			end

			if config then
				row.icon = config.icon
			end

			if entry.action == "interpolation" then
				row.icon = ({
					Bezier = "rbxassetid://99914985674433",
					Linear = "rbxassetid://138611869110105",
					Constant = "rbxassetid://85738635874166",
				})[entry.value]
			end
		end

		local menu = Dropdown.build(
			template,
			anchor and "GraphSubmenu" or "GraphContextMenu",
			{ width = width, compact = true, rows = rows }
		)
		menu.AnchorPoint = Vector2.zero
		menu.ClipsDescendants = false
		menu.Parent = parent
		local depth = anchor and 240 or 230
		menu.ZIndex = depth
		if not anchor then
			root = menu
			self.menu = menu
		end

		for i, entry in entries do
			if entry == "divider" then
				continue
			end

			local row = menu.Content["Graph" .. i]
			local button = row:FindFirstChildWhichIsA("GuiButton")
			local title, arrow = button:FindFirstChild("Title"), button:FindFirstChild("Arrow")
			if arrow then
				arrow.AnchorPoint = Vector2.new(1, 0.5)
				arrow.Position = UDim2.new(1, -6, 0.5, 0)
				arrow.Size = UDim2.fromOffset(10, 10)
				arrow.ScaleType = Enum.ScaleType.Fit
			end

			local check = button:FindFirstChild("Check")
			if check then
				check.Visible = entry.action == "snap" and self.snapping
			end

			local function hover()
				if self.menu ~= root then
					return
				end

				button.BackgroundColor3 = Theme.get("MenuHov", self.colors.selection)
				button.BackgroundTransparency = 0
				if not anchor then
					if
						entry.section == "interpolation"
						and require("KeyframeMenu").isCurvePickerOpen(root)
					then
						return
					end

					if self.submenu and self.submenu:GetAttribute("Section") == entry.section then
						return
					end

					hideSubmenu()
					if entry.section == "interpolation" then
						self:_action(
							"curvePicker",
							{ owner = root, anchor = root, button = button }
						)
					elseif entry.section then
						self.submenu = buildMenu(entry.section, self.frame, button)
						self.submenuButton = button
						self.submenu:SetAttribute("Section", entry.section)
					end
				end
			end

			button.MouseEnter:Connect(hover)
			button.MouseLeave:Connect(function()
				if self.submenuButton ~= button then
					button.BackgroundTransparency = 1
				end
			end)
			if entry.numeric then
				button.Active = false
				if title then
					title.Size = UDim2.new(0, 42, 1, -4)
				end

				local box = make("TextBox", button, entry.text, {
					Text = fmt(entry.value),
					Position = UDim2.new(0, 57, 0, 2),
					Size = UDim2.new(1, -65, 1, -4),
					BackgroundTransparency = 0,
					BorderSizePixel = 0,
					FontFace = FONT,
					TextSize = 11,
					ClearTextOnFocus = false,
					ZIndex = depth + 3,
				})
				box.BackgroundColor3 = Theme.get("Bg", self.colors.bg)
				box.TextColor3 = Theme.get("Txt", Color3.new(1, 1, 1))
				box:SetAttribute("ThemeBg", "Bg")
				box:SetAttribute("ThemeTxt", "Txt")
				round(box, 3)
				local outline = make("UIStroke", box, "Outline", {
					Thickness = 1,
					Transparency = 0.45,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.get("Strk", self.colors.border),
				})
				outline:SetAttribute("ThemeStrk", "Strk")
				local committed = box.Text
				box.Focused:Connect(function()
					outline.Transparency = 0
					box.SelectionStart = 1
					box.CursorPosition = #box.Text + 1
				end)
				require("NumericInput").connect(box, { step = entry.text == "Frame" and 1 or 0.1 }, function()
					outline.Transparency = 0.45
					if self.menu ~= root or box.Text == committed then
						return
					end

					local value = tonumber(box.Text)
					if finite(value) then
						self:_action(entry.numeric, { value = value, key = key, channel = channel })
						committed = box.Text
					else
						box.Text = committed
					end
				end
)
			elseif entry.section then
				button.Activated:Connect(hover)
			else
				button.Activated:Connect(function()
					self:closeMenu()
					self:_action(
						entry.action,
						{ value = entry.value, key = key, channel = channel, motor = rotationMotor }
					)
				end)
			end
		end

		for _, child in menu:GetDescendants() do
			if child:IsA("GuiObject") then
				child.ZIndex = depth + 1 + (child:IsA("GuiButton") and 0 or 1)
			end
		end

		Theme.applyTree(menu)
		Dropdown.refreshIcons(menu)
		local zoom = menu:FindFirstChildOfClass("UIScale")
		if zoom then
			zoom.Scale = 1
		end

		menu.Visible = true

		local function position()
			if self.menu ~= root or not menu.Parent then
				return
			end

			local scale = self:_scale()
			local viewport = self.frame.AbsoluteSize / scale
			local size = menu.AbsoluteSize / scale
			if anchor then
				local origin = (root.AbsolutePosition - self.frame.AbsolutePosition) / scale
				local x = root.AbsoluteSize.X / scale
				if origin.X + x + size.X > viewport.X - 2 then
					x = -size.X
				end

				local y = (anchor.AbsolutePosition.Y - root.AbsolutePosition.Y) / scale
				menu.Position = UDim2.fromOffset(
					origin.X + x,
					math.clamp(origin.Y + y, 2, math.max(2, viewport.Y - size.Y - 2))
				)
			else
				local point = (screen - self.frame.AbsolutePosition) / scale
				menu.Position = UDim2.fromOffset(
					math.clamp(point.X, 2, math.max(2, viewport.X - size.X - 2)),
					math.clamp(point.Y, 30, math.max(30, viewport.Y - size.Y - 2))
				)
			end
		end

		menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(position)
		position()
		task.defer(position)
		return menu
	end

	local initialSection = section
	if section == "interpolation" then
		initialSection = nil
	end

	local menu = buildMenu(initialSection, self.frame)
	if section == "interpolation" then
		local row = menu.Content:FindFirstChild("Graph7")
		local button = row and row:FindFirstChildWhichIsA("GuiButton")
		if button then
			self:_action("curvePicker", { owner = menu, anchor = menu, button = button })
		end
	end
end

function View:_refreshRows()
	if self.destroyed then
		return
	end

	local scale = self:_scale()
	local height = ROW * scale
	local offset = math.clamp(
		math.floor(self.channels.CanvasPosition.Y / height + 1e-5),
		0,
		math.max(0, #self.rows - 1)
	)
	local visible = math.ceil(self.channels.AbsoluteSize.Y / height) + 2
	for index = 1, visible do
		local item = self.rows[offset + index]
		local row = self.rowPool[index]
		if item and not row then
			row = {}
			self.rowPool[index] = row
			row.frame = frame(
				self.channels,
				"ChannelRow",
				UDim2.new(),
				UDim2.new(1, -5, 0, ROW),
				Color3.fromRGB(40, 39, 52),
				204
			)
			row.frame.BackgroundTransparency = 1
			row.select = make("TextButton", row.frame, "Channel", {
				Text = "",
				Size = UDim2.new(1, -48, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				FontFace = FONT,
				TextSize = 14,
				TextColor3 = TEXT,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 205,
			})
			row.dot = frame(
				row.frame,
				"AxisColor",
				UDim2.fromOffset(13, 9),
				UDim2.fromOffset(7, 7),
				ACCENT,
				206
			)
			round(row.dot, 4)
			row.eye = self:_button(
				row.frame,
				"Visibility",
				"●",
				UDim2.new(1, -45, 0, 2),
				UDim2.fromOffset(20, 19),
				nil,
				"Show or hide these curves"
			)
			row.lock = self:_button(
				row.frame,
				"Lock",
				"○",
				UDim2.new(1, -23, 0, 2),
				UDim2.fromOffset(20, 19),
				nil,
				"Lock this curve to prevent edits"
			)
			row.eye.Text = ""
			row.lock.Text = ""
			row.eyeImage = make("ImageLabel", row.eye, "Eye", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(1, 1),
				Size = UDim2.fromOffset(18, 18),
				Image = ICONS.eye,
				ScaleType = Enum.ScaleType.Stretch,
				ZIndex = 208,
			})
			row.mod = self:_button(
				row.frame,
				"Modifiers",
				"",
				UDim2.new(1, -89, 0, 2),
				UDim2.fromOffset(20, 19),
				nil,
				"Turn this curve's modifiers on or off"
			)
			row.modIcon = make("TextLabel", row.mod, "Wrench", {
				Text = "🔧",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				FontFace = FONT,
				TextSize = 12,
				TextColor3 = TEXT,
				ZIndex = 208,
			})
			connect(self, row.mod.Activated, function()
				if row.channel then
					self:_action("toggleModifiers", { channel = row.channel, id = row.channel.id })
				end
			end)
			row.mute = self:_button(
				row.frame,
				"MuteAxis",
				"M",
				UDim2.new(1, -67, 0, 2),
				UDim2.fromOffset(20, 19),
				nil,
				"Mute this axis during playback and export; rotation uses the joint's rest frame. Keys are preserved."
			)
			connect(self, row.mute.Activated, function()
				if row.channel then
					self:_action("toggleMute", { channel = row.channel, id = row.channel.id })
				end
			end)
			row.lockImage = make("ImageLabel", row.lock, "LockIcon", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(1, 0),
				Size = UDim2.fromOffset(18, 18),
				Image = ICONS.unlock,
				ScaleType = Enum.ScaleType.Stretch,
				ZIndex = 208,
			})
			connect(self, row.select.Activated, function()
				local shift = self:isKeyDown(Enum.KeyCode.LeftShift)
					or self:isKeyDown(Enum.KeyCode.RightShift)
				if row.channel then
					self:_action(
						"selectChannel",
						{ channel = row.channel, id = row.channel.id, shift = shift }
					)
				elseif row.item then
					self:_action("selectGroup", {
						bone = row.item.bone,
						motor = row.item.motor,
						group = row.item.family,
						shift = shift,
					})
				end
			end)
			connect(self, row.select.MouseButton2Click, function()
				if row.item and row.item.motor then
					self.rotationMotor = row.item.motor
					self:openMenu(self:mousePosition(), "rotation")
				end
			end)
			connect(self, row.eye.Activated, function()
				if row.channel then
					self:_action("toggleVisible", { channel = row.channel, id = row.channel.id })
				elseif row.item then
					self:_action(
						"toggleGroupVisible",
						{ motor = row.item.motor, group = row.item.family }
					)
				end
			end)
			connect(self, row.lock.Activated, function()
				if row.channel then
					self:_action("toggleLock", { channel = row.channel, id = row.channel.id })
				end
			end)
		end

		if row then
			row.frame.Visible = item ~= nil
			if item then
				row.channel = item.channel
				row.item = item
				row.frame.Position = UDim2.fromOffset(0, (offset + index - 1) * ROW)
				local channel = item.channel
				row.select.Position = UDim2.fromOffset(channel and 28 or item.group and 12 or 7, 0)
				local hasModifiers = channel ~= nil and channel.hasModifiers == true
				row.select.Size =
					UDim2.new(1, channel and (hasModifiers and -120 or -98) or -52, 1, 0)
				row.mod.Visible = hasModifiers
				row.mute.Visible = channel ~= nil and channel.canMute == true
				row.mute.TextTransparency = channel and channel.muted and 0 or 0.65
				row.mute.TextColor3 = channel and channel.muted and self.colors.selection
					or self.colors.text
				if hasModifiers then
					row.modIcon.TextTransparency = channel.modifiersOff and 0.7 or 0
				end

				row.select.Text = item.text
				row.select.FontFace = channel and FONT or BOLD
				local rowBackground = channel
						and channel.selected
						and self.colors.panel:Lerp(self.colors.selection, 0.2)
					or self.colors.panel
				row.select.TextSize = item.group and 10 or 12
				row.select.TextColor3 = readable(
					item.group and self.colors.muted or self.colors.text,
					rowBackground,
					4.5
				)
				row.select.TextTransparency = 0
				row.dot.Visible = channel ~= nil
				row.eye.Visible = true
				if not channel then
					local visible = false
					for _, track in self.data.channels or {} do
						if
							track.motor == item.motor
							and (not item.family or track.group == item.family)
							and track.visible ~= false
						then
							visible = true
						end
					end

					row.eyeImage.Image = visible and ICONS.eye or ICONS.hidden
					row.eyeImage.ImageColor3 = self.colors.text
				end

				row.lock.Visible = channel ~= nil
				row.frame.BackgroundColor3 = channel and self.colors.selection or self.colors.border
				row.frame.BackgroundTransparency = channel and (channel.selected and 0.72 or 1)
					or (item.group and 0.88 or 0.65)
				if channel then
					row.dot.BackgroundColor3 =
						readable(self.colors[channel.axis] or self.colors.text, rowBackground, 3)
					local iconColor =
						readable(self.colors.text:Lerp(self.colors.muted, 0.25), rowBackground, 4.5)
					row.eyeImage.Image = channel.visible == false and ICONS.hidden or ICONS.eye
					row.eyeImage.ImageColor3 = iconColor
					row.lockImage.Image = channel.locked and ICONS.lock or ICONS.unlock
					row.lockImage.ImageColor3 = iconColor
					row.lockImage.Visible = true
					row.lock.BackgroundColor3 = self.colors.selection
					row.lock.BackgroundTransparency = channel.locked and 0.35 or 1
				end
			end
		end
	end

	for i = visible + 1, #self.rowPool do
		self.rowPool[i].frame.Visible = false
	end
end

function View:_filterRows()
	local query = self.search.Text:lower()
	local rows = {}
	local bone, group, motor
	for _, channel in self.data.channels or {} do
		local name = tostring(channel.bone or channel.name or "Curve")
		local family = channel.group or "Value"
		if
			query == ""
			or (name .. " " .. family .. " " .. (channel.axis and Preferences.axisLabel(
				channel.axis,
				channel.group == "Scale"
			) or "") .. " " .. (channel.name or "")):lower():find(query, 1, true)
		then
			if name ~= bone or channel.motor ~= motor then
				table.insert(rows, { text = name, bone = name, motor = channel.motor })
				bone, group, motor = name, nil, channel.motor
			end

			if family ~= group then
				table.insert(rows, {
					text = family,
					group = true,
					bone = name,
					motor = channel.motor,
					family = family,
				})
				group = family
			end

			table.insert(rows, {
				text = channel.axis and Preferences.axisLabel(
					channel.axis,
					channel.group == "Scale"
				) or channel.name or "Value",
				channel = channel,
			})
		end
	end

	self.rows = rows
	self.channels.CanvasSize = UDim2.fromOffset(0, #rows * ROW)
	self:_refreshRows()
end

function View:setData(data)
	self.data = data or { channels = {} }
	if self.data.emptyText then
		self.empty.Text = self.data.emptyText
	end

	if self.data.playing ~= nil then
		self:setPlaying(self.data.playing)
	end

	if self.data.snap ~= nil then
		self:setSnap(self.data.snap)
	end

	self:_filterRows()
	local selected = self.data.selectedKey
	self:setInspector(selected and selected.channel, selected and selected.key)
end

local function evaluate(channel, f)
	if channel.evaluate then
		return channel.evaluate(f)
	end

	local keys = channel.keys or {}
	if #keys == 0 then
		return nil
	end

	if f <= keys[1].frame then
		return keys[1].value
	end

	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if f <= b.frame then
			local t = (f - a.frame) / math.max(1e-12, b.frame - a.frame)
			return a.value + (b.value - a.value) * t
		end
	end

	return keys[#keys].value
end

function View:_drawGrid()
	local v = self.viewport
	local w, h = self.plot.AbsoluteSize.X, self.plot.AbsoluteSize.Y
	local gridColor = self.colors.grid
	local xStep = self.options.tickStep and self.options.tickStep(w / (v.frameMax - v.frameMin))
		or niceStep(v.frameMax - v.frameMin, w)
	local yStep = niceStep(v.valueMax - v.valueMin, h * 2)
	for value = math.ceil(v.frameMin / xStep) * xStep, v.frameMax, xStep do
		local p = self:toScreen(value, 0)
		self:_line("grid", Vector2.new(p.X, 0), Vector2.new(p.X, h), gridColor, 1, 0)
		local tick = self:_pool("frameTicks", self.ruler, "TextLabel")
		tick.Text = fmt(value)
		tick.Position = UDim2.new(p.X / w, -28, 0, 2)
		tick.Size = UDim2.fromOffset(56, 20)
	end

	for value = math.ceil(v.valueMin / yStep) * yStep, v.valueMax, yStep do
		local p = self:toScreen(0, value)
		self:_line(
			"grid",
			Vector2.new(0, p.Y),
			Vector2.new(w, p.Y),
			math.abs(value) < 1e-8 and self.colors.zero or gridColor,
			1,
			0
		)
		local tick = self:_pool("valueTicks", self.valueRuler, "TextLabel")
		tick.Text = fmt(value)
		tick.Position = UDim2.new(0, 0, p.Y / h, -10)
		tick.Size = UDim2.new(1, -7, 0, 20)
		tick.TextXAlignment = Enum.TextXAlignment.Right
	end
end

function View:pan(viewport)
	self:render(viewport)
	return true
end

function View:_updateScroll()
	local v = self.viewport
	if v and v.bounds then
		local span = v.bounds.frameMax - v.bounds.frameMin
		self.scrollThumb.Position = UDim2.fromScale((v.frameMin - v.bounds.frameMin) / span, 0.5)
		self.scrollThumb.Size = UDim2.new((v.frameMax - v.frameMin) / span, 0, 0, 8)
		local height = v.valueMax - v.valueMin
		local valueSpan = math.max(height, v.bounds.valueMax - v.bounds.valueMin)
		local fraction = math.clamp(
			math.max(
				height / valueSpan,
				18 * self:_scale() / math.max(1, self.valueScrollbar.AbsoluteSize.Y)
			),
			0,
			1
		)
		local travel = valueSpan - height
		local alpha = travel > 1e-8 and math.clamp((v.bounds.valueMax - v.valueMax) / travel, 0, 1)
			or 0
		self.valueThumb.Position = UDim2.fromScale(0.5, alpha * (1 - fraction))
		self.valueThumb.Size = UDim2.new(0, 8, fraction, 0)
	end
end

function View:_curvePoints(channel, w, h)
	local points = channel.drawPoints or channel.plotPoints or {}
	if #points < 3 then
		return points
	end

	local v = self.viewport
	local sx = w / (v.frameMax - v.frameMin)
	local sy = h / (v.valueMax - v.valueMin) / (channel.displayScale or 1)
	local cached = self.simplified[channel]
	if
		cached
		and cached.source == points
		and math.abs(cached.sx - sx) < 1e-7
		and math.abs(cached.sy - sy) < 1e-7
	then
		return cached.points
	end

	local keep = {}
	local stack = {}

	for first = 1, #points - 1, 128 do
		local last = math.min(first + 128, #points)
		keep[first] = true
		keep[last] = true
		table.insert(stack, first)
		table.insert(stack, last)
	end

	while #stack > 0 do
		local last = table.remove(stack)
		local first = table.remove(stack)
		local a, b = points[first], points[last]
		local dx, dy = (b.X - a.X) * sx, (b.Y - a.Y) * sy
		local length = dx * dx + dy * dy
		local farthest, maximum = nil, 0.33 * 0.33
		for i = first + 1, last - 1 do
			local px, py = (points[i].X - a.X) * sx, (points[i].Y - a.Y) * sy
			local t = length > 1e-16 and math.clamp((px * dx + py * dy) / length, 0, 1) or 0
			local ex, ey = px - t * dx, py - t * dy
			local error = ex * ex + ey * ey
			if error > maximum then
				maximum = error
				farthest = i
			end
		end

		if farthest then
			keep[farthest] = true
			table.insert(stack, first)
			table.insert(stack, farthest)
			table.insert(stack, farthest)
			table.insert(stack, last)
		end
	end

	local reduced = {}
	for i, p in points do
		if keep[i] then
			table.insert(reduced, p)
		end
	end

	self.simplified[channel] = { source = points, sx = sx, sy = sy, points = reduced }
	return reduced
end

function View:render(viewport)
	if self.destroyed then
		return
	end

	viewport = viewport or self.viewport
	if not viewport then
		return
	end

	self.viewport = table.clone(viewport)
	self.sceneViewport = table.clone(viewport)
	self.sceneSize = self.plot.AbsoluteSize
	self.sceneOffset = Vector2.zero
	self.scene.Position = UDim2.new()
	local v = self.viewport
	v.frameMin = finite(v.frameMin) and v.frameMin or 0
	v.frameMax = finite(v.frameMax) and v.frameMax or 60
	v.valueMin = finite(v.valueMin) and v.valueMin or -1
	v.valueMax = finite(v.valueMax) and v.valueMax or 1
	if v.frameMax <= v.frameMin then
		v.frameMax = v.frameMin + 1
	end

	if v.valueMax <= v.valueMin then
		v.valueMax = v.valueMin + 1
	end

	for _, pool in self.pools do
		pool.used = 0
	end

	table.clear(self.hits)
	self.markerCount = 0
	self.handleLineCount = 0
	local w, h = self.plot.AbsoluteSize.X, self.plot.AbsoluteSize.Y
	if w < 2 or h < 2 then
		return
	end

	self:_drawGrid()
	if v.cursorValue then
		local y = self:toScreen(0, v.cursorValue).Y
		if y >= 0 and y <= h then
			self:_line(
				"cursor",
				Vector2.new(0, y),
				Vector2.new(w, y),
				self.colors.playhead,
				1,
				0.55
			)
		end
	end

	local visible = {}
	for _, c in self.data.channels or {} do
		if c.visible ~= false and #(c.keys or {}) > 0 then
			table.insert(visible, c)
		end
	end

	self.empty.Visible = #(self.data.channels or {}) == 0
	local focused = false
	for _, channel in visible do
		if channel.selected then
			focused = true
			break
		end
	end

	local remaining = MAX_LINES
	for ci, channel in visible do
		local color = channel.color or self.colors[channel.axis] or self.colors.text
		local opacity = focused and not channel.selected and 0.7 or 0
		local quota = math.min(320, math.floor(remaining / (#visible - ci + 1)))
		local used = 0
		local points = self:_curvePoints(channel, w, h)

		local function drawLine(a, b)
			if used >= quota or b.X < v.frameMin or a.X > v.frameMax then
				return
			end

			if
				self:_line(
					"curves",
					self:toScreen(a.X, a.Y, channel),
					self:toScreen(b.X, b.Y, channel),
					color,
					channel.selected and 2 or 1.4,
					opacity
				)
			then
				used += 1
			end
		end

		local function drawSegment(a, b)
			if not channel.displayClamp or math.abs(b.Y - a.Y) < 1e-12 then
				drawLine(a, b)
				return
			end

			local cuts = { 0, 1 }
			local limit = channel.displayClamp * (channel.displayScale or 1)
			for _, value in { -limit, limit } do
				local t = (value + (channel.displayOffset or 0) - a.Y) / (b.Y - a.Y)
				if t > 0 and t < 1 then
					table.insert(cuts, t)
				end
			end

			table.sort(cuts)
			for i = 2, #cuts do
				drawLine(a:Lerp(b, cuts[i - 1]), a:Lerp(b, cuts[i]))
			end
		end

		local function draw(a, b)
			if not channel.activeRanges then
				drawSegment(a, b)
				return
			end

			for _, interval in channel.activeRanges do
				local low, high = math.max(a.X, interval[1]), math.min(b.X, interval[2])
				if high >= low then
					local width = b.X - a.X
					if width > 1e-9 then
						drawSegment(
							Vector2.new(low, a.Y + (b.Y - a.Y) * (low - a.X) / width),
							Vector2.new(high, a.Y + (b.Y - a.Y) * (high - a.X) / width)
						)
					else
						drawSegment(a, b)
					end
				end
			end
		end

		if points[1] then
			draw(Vector2.new(math.min(v.frameMin, points[1].X), points[1].Y), points[1])
			local first, last = 1, #points
			while first < last and points[first + 1].X < v.frameMin do
				first += 1
			end

			while last > first and points[last - 1].X > v.frameMax do
				last -= 1
			end

			local stride = math.max(
				1,
				math.ceil(
					(last - first) / math.max(1, (quota - 2) / (channel.displayClamp and 3 or 1))
				)
			)
			local index = first
			while index < last do
				local following = math.min(last, index + stride)
				draw(points[index], points[following])
				index = following
			end

			draw(
				points[#points],
				Vector2.new(math.max(v.frameMax, points[#points].X), points[#points].Y)
			)
		end

		remaining -= used
		if channel.envelope then
			self:_drawEnvelope(channel)
		end

		for index, key in channel.keys do
			if channel.keysHidden then
				break
			end

			if
				Activity.contains(channel.activeRanges, key.frame)
				and finite(key.frame)
				and finite(key.value)
			then
				local point = self:toScreen(key.frame, key.value, channel)
				if point.X >= -5 and point.X <= w + 5 and point.Y >= -5 and point.Y <= h + 5 then
					local selected = key.selected or v.selection and v.selection[key] == true
					self:_diamond(point, require("KeyColors").get(key.keyData, channel.channelId) or color, selected, selected and 8 or 6, nil, opacity)
					if not channel.locked then
						table.insert(self.hits, {
							kind = "key",
							channel = channel,
							channelId = channel.id,
							key = key,
							keyIndex = index,
							position = point,
							normalized = point / Vector2.new(w, h),
						})
					end

					if selected and not channel.locked then
						for _, side in { "left", "right" } do
							local handle = key[side]
							if
								handle
								and (key.interpolation == "Bezier" or side == "right")
								and finite(handle.frame)
								and finite(handle.value)
							then
								local raw = self:toScreen(handle.frame, handle.value, channel)
								local delta = raw - point
								local displayScale = math.min(
									1,
									84 * self:_scale() / math.max(0.001, delta.Magnitude)
								)

								local margin = 5 * self:_scale()
								if delta.X > 0 then
									displayScale = math.min(
										displayScale,
										math.max(0, w - margin - point.X) / delta.X
									)
								elseif delta.X < 0 then
									displayScale = math.min(
										displayScale,
										math.max(0, point.X - margin) / -delta.X
									)
								end

								if delta.Y > 0 then
									displayScale = math.min(
										displayScale,
										math.max(0, h - margin - point.Y) / delta.Y
									)
								elseif delta.Y < 0 then
									displayScale = math.min(
										displayScale,
										math.max(0, point.Y - margin) / -delta.Y
									)
								end

								local hp = point + delta * displayScale
								if self.handleLineCount < 100 then
									self:_line("handles", point, hp, color, 1, 0.2)
									self.handleLineCount += 1
								end

								self:_diamond(hp, color, false, 5, "handlePoints")
								if hp.X >= 0 and hp.X <= w and hp.Y >= 0 and hp.Y <= h then
									table.insert(self.hits, {
										kind = "handle",
										channel = channel,
										channelId = channel.id,
										key = key,
										keyIndex = index,
										side = side,
										position = hp,
										normalized = hp / Vector2.new(w, h),
										displayScale = math.max(0.001, displayScale),
									})
								end
							end
						end
					end
				end
			end
		end
	end

	for _, pool in self.pools do
		for i = pool.used + 1, #pool.items do
			pool.items[i].Visible = false
		end
	end

	self:_updateScroll()
	self:setPlayhead(v.playhead or 0)
	if v.lasso and #v.lasso > 1 then
		local origin = self.plot.AbsolutePosition
		for i = 2, #v.lasso + 1 do
			local a, b = v.lasso[i - 1], v.lasso[i] or v.lasso[1]
			self:_line(
				"lasso",
				a - origin,
				b - origin,
				self.colors.selectionLine,
				1,
				i > #v.lasso and 0.6 or 0.1
			)
		end
	end

	if v.circle then
		local origin = self.plot.AbsolutePosition
		local center, radius = v.circle.at - origin, v.circle.radius
		for i = 1, 32 do
			local a0, a1 = (i - 1) / 32 * math.pi * 2, i / 32 * math.pi * 2
			self:_line(
				"lasso",
				center + Vector2.new(math.cos(a0), math.sin(a0)) * radius,
				center + Vector2.new(math.cos(a1), math.sin(a1)) * radius,
				self.colors.selectionLine,
				1,
				0.15
			)
		end
	end

	for _, pool in { self.pools.lasso } do
		for i = pool.used + 1, #pool.items do
			pool.items[i].Visible = false
		end
	end

	self.selectionBox.Visible = v.box ~= nil and self.menu == nil
	if v.box then
		local a, b = v.box[1], v.box[2]
		local low, high = a:Min(b), a:Max(b)
		self.selectionBox.Position = UDim2.fromScale(low.X / w, low.Y / h)
		self.selectionBox.Size = UDim2.fromScale((high.X - low.X) / w, (high.Y - low.Y) / h)
	end
end

function View:isVisible()
	if self.destroyed or self.closing or not self.frame.Parent then
		return false
	end

	if AppState.PresentationHidden or self.docking then
		return true
	end

	if self.docked and (not self.widget or not self.widget.Enabled) then
		return false
	end

	local parent = self.frame
	while parent do
		if parent:IsA("GuiObject") and not parent.Visible then
			return false
		end

		if parent:IsA("LayerCollector") and not parent.Enabled then
			return false
		end

		parent = parent.Parent
	end

	return true
end

function View:setVisible(visible)
	if self.destroyed then
		return
	end

	self.visibilityVersion = (self.visibilityVersion or 0) + 1
	local version = self.visibilityVersion
	self.closing = not visible
	if visible then
		self:_applyTheme()
		if not self.dockRestored then
			self.dockRestored = true
			self:restoreDocked()
		end

		if self.destroyed or self.visibilityVersion ~= version then
			return
		end

		self.frame.Visible = true
		if self.docked then
			WindowFX.clear(self.frame)
			self.docking = true
			local opened = DockHost.show(self.widget, function()
				return not self.destroyed and self.visibilityVersion == version
			end)
			self.docking = false
			if not opened and not self.destroyed and self.visibilityVersion == version then
				self:setDocked(false, true)
			end
		else
			self:_constrainWindow()
			WindowFX.pop(self.frame)
		end
	else
		self:_hideTips()
		self:_finishWindowDrag()
		if self.menu then
			self:closeMenu()
		end

		if self.docked then
			WindowFX.clear(self.frame)
			self.frame.Visible = false
			self.widget.Enabled = false
		else
			WindowFX.shrink(self.frame, function()
				if not self.destroyed and self.visibilityVersion == version then
					self.frame.Visible = false
				end
			end)
		end
	end
end

function View:_cancelGeometrySave()
	if self.geometrySaveTask then
		task.cancel(self.geometrySaveTask)
		self.geometrySaveTask = nil
	end
end

function View:_queueGeometrySave()
	if self.docked then
		return
	end

	self:_cancelGeometrySave()
	local parent = self.frame.Parent
	if not parent then
		return
	end

	local available = parent.AbsoluteSize / self:_scale()
	if available.X < 1 or available.Y < 1 then
		return
	end

	local pos, size = self.frame.Position, self.frame.Size
	local saved = {
		x = pos.X.Scale + pos.X.Offset / available.X,
		y = pos.Y.Scale + pos.Y.Offset / available.Y,
		width = size.X.Offset,
		height = size.Y.Offset,
	}
	self.floatingGeometry = { position = pos, size = size }
	local plugin = self.options.plugin
	if not plugin then
		return
	end

	self.geometryDirty = true

	self.geometrySaveTask = task.delay(1, function()
		self.geometrySaveTask = nil
		local ok, err = pcall(function()
			plugin:SetSetting(GEOMETRY_SETTING, saved)
		end)
		if ok then
			self.geometryDirty = false
		end

		if not ok then
			warn("Eclipse graph position: " .. tostring(err))
		end
	end)
end

function View:_restoreGeometry()
	local plugin = self.options.plugin
	if not plugin then
		return
	end

	local ok, saved = pcall(function()
		return plugin:GetSetting(GEOMETRY_SETTING)
	end)
	if not ok or type(saved) ~= "table" then
		return
	end

	for _, key in { "x", "y", "width", "height" } do
		if not finite(saved[key]) then
			return
		end
	end

	self.frame.Position = UDim2.fromScale(math.clamp(saved.x, 0, 1), math.clamp(saved.y, 0, 1))
	self.frame.Size =
		UDim2.fromOffset(math.clamp(saved.width, 460, 1800), math.clamp(saved.height, 260, 1100))
	self.floatingGeometry = { position = self.frame.Position, size = self.frame.Size }
end

function View:_finishWindowDrag()
	if self.windowMotion then
		self.windowMotion.finish()
		return
	end

	if not self.drag then
		return
	end

	self:flushWindowDrag()
	local moved = self.drag.moved
	self.drag = nil
	if moved or self.geometryDirty then
		self:_queueGeometrySave()
	end
end

function View:flushWindowDrag()
	local point, d = self.pendingWindowPoint, self.drag
	self.pendingWindowPoint = nil
	if not point or not d then
		return
	end

	local delta = (point - d.start) / d.scale
	local pos, size = d.position, d.size
	if d.edge then
		local x, y = d.edge.X, d.edge.Y
		local width = x == 0 and d.size.X.Offset
			or math.clamp(d.size.X.Offset + delta.X * x, 460, 1800)
		local height = y == 0 and d.size.Y.Offset
			or math.clamp(d.size.Y.Offset + delta.Y * y, 260, 1100)
		size = UDim2.fromOffset(width, height)
		pos = d.position
			+ UDim2.fromOffset(
				(width - d.size.X.Offset) * x * 0.5,
				(height - d.size.Y.Offset) * y * 0.5
			)
	else
		pos = d.position + UDim2.fromOffset(delta.X, delta.Y)
	end

	if self:_constrainWindow(pos, size, d.scale) then
		d.moved = true
	end
end

function View:_createWidget()
	if self.widget then
		return true
	end

	local plugin = self.options.plugin
	if not plugin then
		return false
	end

	local ok, widget = pcall(function()
		return DockHost.acquire(
			plugin,
			"EclipseAnimatorGraphEditor",
			DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, true, 800, 420, 460, 260)
		)
	end)
	if not ok then
		warn("Eclipse graph docking: " .. tostring(widget))
		return false
	end

	if self.destroyed then
		DockHost.release(widget)
		return false
	end

	self.widget = widget
	widget.Title = "Eclipse Graph Editor"
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	connect(self, widget.WindowFocused, function()
		self.widgetFocused = true
	end)
	connect(self, widget.WindowFocusReleased, function()
		self.widgetFocused = false
		table.clear(self.heldKeys)
		self:_hideTips()
		self:_action("focusLost")
	end)
	connect(self, widget:GetPropertyChangedSignal("Enabled"), function()
		if self.destroyed then
			return
		end

		if not widget.Enabled then
			self.widgetFocused = false
			table.clear(self.heldKeys)
			self:_hideTips()
			self:_action("focusLost")
		end

		self:_action("visibility")
	end)
	local base = self.options.hoverDialog
	if base and base.ui then
		local tooltip = base.ui:Clone()
		tooltip.Name = "GraphTooltip"
		tooltip.ZIndex = 1000
		tooltip.Parent = widget
		for property, value in base.labelDefaults do
			tooltip.Information[property] = value
		end

		local move = Instance.new("BindableEvent")
		self.widgetMouseMove = move
		local mouse = setmetatable({ Move = move.Event }, {
			__index = function(_, key)
				local p = widget:GetRelativeMousePosition()
				return (key == "x" or key == "X") and p.X or p.Y
			end,
		})
		self.widgetHover = HoverDialog.initialize(tooltip, mouse)
		connect(self, self.frame.MouseMoved, function()
			if self.docked then
				move:Fire()
			end
		end)
	end

	return true
end

function View:restoreDocked()
	local plugin = self.options.plugin
	if not plugin then
		return
	end

	local ok, saved = pcall(function()
		return plugin:GetSetting(DOCK_SETTING)
	end)
	if ok and saved == true then
		self:setDocked(true, true)
	end
end

function View:setDocked(docked, restoring)
	docked = docked == true
	if self.destroyed or self.docking or self.docked == docked then
		return
	end

	self.docking = true
	if docked and not self:_createWidget() then
		self.docking = false
		return
	end

	if self.destroyed then
		self.docking = false
		return
	end

	if
		docked
		and not DockHost.show(self.widget, function()
			return not self.destroyed and not self.closing
		end)
	then
		self.docking = false
		self.widget.Enabled = false
		return
	end

	self.docked = docked
	self:_hideTips()
	self:_finishWindowDrag()
	self.pendingWindowPoint = nil
	WindowFX.clear(self.frame)
	local scaler = self.frame:FindFirstChildOfClass("UIScale")
	if scaler then
		scaler.Scale = 1
	end

	if docked then
		self.floatingGeometry = { position = self.frame.Position, size = self.frame.Size }
		self.frame.Parent = self.widget
		self.frame.Position = UDim2.fromScale(0.5, 0.5)
		self.frame.Size = UDim2.fromScale(1, 1)
		self.widget.Enabled = not self.closing
	else
		self.frame.Parent = self.floatingParent
		local saved = self.floatingGeometry
		if saved then
			self.frame.Position = saved.position
			self.frame.Size = saved.size
		end

		if self.widget then
			self.widget.Enabled = false
		end
	end

	self.docking = false
	self.dockLabel.Text = docked and "UNDOCK" or "DOCK"
	if self.options.plugin and not restoring then
		local ok, err = pcall(function()
			self.options.plugin:SetSetting(DOCK_SETTING, docked)
		end)
		if not ok then
			warn("Eclipse graph docking preference: " .. tostring(err))
		end
	end

	for _, grip in self.resizeGrips do
		grip.Visible = not docked
	end

	for button, text in self.tipButtons do
		self:_latchTip(button, text)
	end

	if not docked then
		self:_constrainWindow()
	end

	self:_action("resize", self.plot.AbsoluteSize)
end

function View:_constrainWindow(position, dimensions, dragScale)
	if self.docked then
		return
	end

	local parent = self.frame.Parent
	if not parent or not parent:IsA("GuiObject") then
		return
	end

	local scale = dragScale or self:_scale()
	local available = parent.AbsoluteSize / scale
	if available.X < 100 or available.Y < 100 then
		return
	end

	local size = dimensions or self.frame.Size
	local width, height =
		math.min(size.X.Offset, math.max(100, available.X - 16)),
		math.min(size.Y.Offset, math.max(100, available.Y - 16))
	local pos = position or self.frame.Position
	local x = math.clamp(
		pos.X.Scale * available.X + pos.X.Offset,
		width * 0.5 + 8,
		available.X - width * 0.5 - 8
	)
	local y = math.clamp(
		pos.Y.Scale * available.Y + pos.Y.Offset,
		height * 0.5 + 8,
		available.Y - height * 0.5 - 8
	)
	local sizeValue, posValue = UDim2.fromOffset(width, height), UDim2.fromOffset(x, y)
	local changed = self.frame.Size ~= sizeValue or self.frame.Position ~= posValue
	if self.frame.Size ~= sizeValue then
		self.frame.Size = sizeValue
	end

	if self.frame.Position ~= posValue then
		self.frame.Position = posValue
	end

	return changed
end

function View:destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true
	for _, c in self.connections do
		c:Disconnect()
	end

	for _, cleanup in self.cleanups do
		cleanup()
	end

	for _, cleanup in self.tipBindings or {} do
		cleanup()
	end

	if self.widgetHover then
		self.widgetHover:Destroy()
	end

	if self.widgetMouseMove then
		self.widgetMouseMove:Destroy()
	end

	if self.widget then
		DockHost.release(self.widget)
	end

	WindowFX.clear(self.frame)
	if not self.frameDestroying then
		self.frame:Destroy()
	end

	table.clear(self.pools)
	table.clear(self.hits)
	table.clear(self.rowPool)
	self.data = { channels = {} }
	self.rows = {}
	self.viewport = nil
	self.inspectorKey = nil
	self.inspectorChannel = nil
end

function GraphView.create(parent, callback, options)
	local self = setmetatable({
		callback = callback,
		options = options or {},
		connections = {},
		cleanups = {},
		tipButtons = {},
		bindings = {},
		defaults = {},
		pools = {},
		hits = {},
		simplified = setmetatable({}, { __mode = "k" }),
		rowPool = {},
		rows = {},
		data = { channels = {} },
	}, View)
	if self.options.fontFace then
		BOLD = self.options.fontFace
		FONT = Font.new(BOLD.Family, Enum.FontWeight.Regular, BOLD.Style)
	end

	local fallback = {
		Bg = Color3.fromRGB(22, 16, 28),
		Pnl = Color3.fromRGB(16, 10, 21),
		Top = Color3.fromRGB(49, 16, 65),
		Strk = Theme.panelOutlineDefault(),
		Div = Theme.panelOutlineDefault(),
		Txt = Color3.fromRGB(230, 223, 238),
		TopT = Color3.fromRGB(230, 223, 238),
		Tick = Color3.fromRGB(170, 158, 179),
		Ph = Color3.fromRGB(255, 232, 0),
		Sel = Color3.fromRGB(104, 10, 255),
		Scr = Color3.fromRGB(178, 113, 229),
		Menu = Color3.fromRGB(34, 0, 52),
		KfS = Color3.fromRGB(255, 232, 0),
	}
	for key, value in fallback do
		self.defaults[key] = value
	end

	local templates = self.options.templates or {}
	self.templates = templates
	local bar = templates.Header
	local titleSource = bar and bar:FindFirstChildWhichIsA("TextLabel")
	if titleSource then
		BOLD = titleSource.FontFace
		FONT = Font.new(BOLD.Family, Enum.FontWeight.Regular, BOLD.Style)
	end

	local animator = templates.Background
	local gradient = animator and animator:FindFirstChildOfClass("UIGradient")
	local savedGradient = gradient and gradient:GetAttribute("EOrig_Color")
	local parsed = type(savedGradient) == "string"
		and Theme.parseValue
		and Theme.parseValue(savedGradient:gsub("^CS:", ""))
	if parsed then
		local keys = {}
		for i, color in parsed.stops do
			table.insert(
				keys,
				ColorSequenceKeypoint.new((i - 1) / math.max(1, #parsed.stops - 1), color)
			)
		end

		self.backgroundSequence = #keys > 1 and ColorSequence.new(keys)
			or ColorSequence.new(keys[1].Value)
	else
		self.backgroundSequence = gradient and gradient.Color
			or ColorSequence.new(Color3.fromRGB(33, 0, 49), Color3.fromRGB(10, 10, 10))
	end

	self.backgroundRotation = original(gradient, "Rotation", 90)
	local outlineSource = templates.Outline and templates.Outline:FindFirstChildOfClass("UIStroke")
	self.defaults.Strk = Theme.panelOutlineDefault()
	self.defaults.Top = original(bar, "BackgroundColor3", Color3.fromRGB(20, 8, 32))
	self.defaults.TopT = original(titleSource, "TextColor3", Color3.fromRGB(235, 225, 245))
	self.defaults.Txt = self.defaults.TopT
	self.defaults.Tick = original(templates.Tick, "TextColor3", Color3.fromRGB(98, 98, 98))
	self.tickTextSize = templates.Tick and templates.Tick.TextSize or 14
	self.defaults.Ph = original(templates.Chip, "BackgroundColor3", Color3.fromRGB(255, 217, 0))
	local chipText = templates.Chip and templates.Chip:FindFirstChildWhichIsA("TextLabel")
	self.playheadTextDefault = original(chipText, "TextColor3", Color3.new())
	self.defaults.Slider =
		original(templates.Scroll, "BackgroundColor3", Color3.fromRGB(85, 0, 127))
	self.sliderHandleDefault = original(
		templates.Scroll and templates.Scroll:FindFirstChild("LeftDrag"),
		"BackgroundColor3",
		Color3.fromRGB(170, 85, 255)
	)
	self.colors = self:_palette()
	local c = self.colors
	self.frame = make("Frame", parent, "GraphEditorWindow", {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(800, 400),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 200,
	})
	self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	self.frame.Active = true
	self.frame.Visible = false
	if not cloneDecoration(templates.Outline or animator, self.frame, "UICorner") then
		round(self.frame, 5)
	end

	local shell = frame(self.frame, "WindowSurface", UDim2.new(), UDim2.fromScale(1, 1), c.bg, 199)
	round(shell, 5)
	shell:SetAttribute("ThemeBg", "Bg")
	Theme.applyInstance(shell)
	self.backdrop = frame(
		self.frame,
		"Backdrop",
		UDim2.fromOffset(4, Chrome.HEIGHT),
		UDim2.new(1, -8, 1, -Chrome.HEIGHT - 4),
		Color3.new(1, 1, 1),
		200
	)
	if not cloneDecoration(templates.Outline or animator, self.backdrop, "UICorner") then
		round(self.backdrop, 5)
	end

	self.backgroundGradient = make(
		"UIGradient",
		self.backdrop,
		"UIGradient",
		{ Color = self.backgroundSequence, Rotation = self.backgroundRotation }
	)
	local outline = cloneDecoration(templates.Outline, shell, "UIStroke")
		or make("UIStroke", shell, "UIStroke", { Thickness = 1, Transparency = 0.35 })
	for key in outline:GetAttributes() do
		outline:SetAttribute(key, nil)
	end

	outline.Color = self.colors.border
	outline:SetAttribute("ThemeStrk", "Strk")
	self.outline = outline
	Theme.addRoot(self.frame)
	Theme.applyInstance(outline)
	local header, title, drag = Chrome.header(self.frame, "GRAPH EDITOR", 201, 210)
	self.title = title
	local close = Chrome.close(header, function()
		self:_action("close")
	end, 209)
	self:_tip(close, "Close graph editor")
	local body = frame(
		self.frame,
		"Body",
		UDim2.fromOffset(5, Chrome.HEIGHT + 4),
		UDim2.new(1, -10, 1, -Chrome.HEIGHT - 9),
		c.panel,
		201
	)
	body.BackgroundTransparency = 1
	self.body = body

	local side = frame(body, "Sidebar", UDim2.new(), UDim2.new(0, 174, 1, 0), c.panel, 202)
	side.BackgroundTransparency = 1
	self.search = make("TextBox", side, "Search", {
		PlaceholderText = "Filter channels",
		Text = "",
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.new(1, -12, 0, 24),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = c.border,
		BorderSizePixel = 0,
		FontFace = FONT,
		TextSize = 12,
		TextColor3 = c.text,
		PlaceholderColor3 = c.muted,
		ClearTextOnFocus = false,
		ZIndex = 205,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self:_bind(self.search, "TextColor3", "text")
	self:_bind(self.search, "PlaceholderColor3", "muted")
	round(self.search, 3)
	make(
		"UIPadding",
		self.search,
		"Padding",
		{ PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }
	)
	self:_bind(self.search, "BackgroundColor3", "border")
	self.channels = make("ScrollingFrame", side, "Channels", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, -1, 1, -32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ScrollBarImageColor3 = c.scroll,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 203,
	})
	self:_bind(self.channels, "ScrollBarImageColor3", "scroll")
	local divider = frame(
		body,
		"ChannelDivider",
		UDim2.fromOffset(174, 0),
		UDim2.new(0, 1, 1, 0),
		c.divider,
		204
	)
	divider.BackgroundTransparency = 0.35
	divider:SetAttribute("ThemeBg", "Div")
	self.channelDivider = divider
	Theme.applyInstance(divider)
	local chart =
		frame(body, "Chart", UDim2.fromOffset(175, 0), UDim2.new(1, -189, 1, -20), c.panel, 201)
	self.chart = chart
	chart.BackgroundTransparency = 1
	self.ruler =
		frame(chart, "FrameRuler", UDim2.fromOffset(48, 0), UDim2.new(1, -49, 0, 18), c.panel, 202)
	self.ruler.ClipsDescendants = true
	self.ruler.Active = true
	self.ruler.BackgroundTransparency = 1
	self.valueRuler =
		frame(chart, "ValueRuler", UDim2.fromOffset(0, 18), UDim2.new(0, 47, 1, -19), c.panel, 202)
	self.valueRuler.ClipsDescendants = true
	self.valueRuler.BackgroundTransparency = 1
	self.plot =
		frame(chart, "Plot", UDim2.fromOffset(48, 18), UDim2.new(1, -49, 1, -19), c.panel, 201)
	self.plot.ClipsDescendants = true
	self.plot.Active = true
	self.plot.BackgroundTransparency = 1
	self.scrollbar = frame(
		body,
		"TimeScroll",
		UDim2.new(0, 223, 1, -16),
		UDim2.new(1, -243, 0, 14),
		c.panel,
		203
	)
	self.scrollbar.BackgroundTransparency = 1
	local rail =
		frame(self.scrollbar, "Rail", UDim2.fromScale(0, 0.5), UDim2.new(1, 0, 0, 8), c.slider, 204)
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.BackgroundTransparency = 0.65
	round(rail, 3)
	self:_bind(rail, "BackgroundColor3", "slider")
	self.scrollThumb = frame(
		self.scrollbar,
		"Range",
		UDim2.fromScale(0, 0.5),
		UDim2.new(1, 0, 0, 8),
		c.slider,
		205
	)
	self.scrollThumb.AnchorPoint = Vector2.new(0, 0.5)
	self.scrollThumb.Active = true
	round(self.scrollThumb, 3)
	self:_bind(self.scrollThumb, "BackgroundColor3", "slider")
	for _, side in { "Left", "Right" } do
		local handle = frame(
			self.scrollThumb,
			side .. "Drag",
			UDim2.fromScale(side == "Left" and 0 or 1, 0.5),
			UDim2.fromOffset(10, 10),
			c.sliderHandle,
			207
		)
		handle.AnchorPoint = Vector2.new(0.5, 0.5)
		handle.Active = true
		round(handle, 8)
		self:_bind(handle, "BackgroundColor3", "sliderHandle")
		self["scroll" .. side] = handle
	end

	self.valueScrollbar =
		frame(body, "ValueScroll", UDim2.new(1, -14, 0, 18), UDim2.new(0, 14, 1, -39), c.panel, 203)
	self.valueScrollbar.BackgroundTransparency = 1
	self.valueScrollbar.Active = true
	local valueRail = frame(
		self.valueScrollbar,
		"Rail",
		UDim2.fromScale(0.5, 0),
		UDim2.new(0, 8, 1, 0),
		c.slider,
		204
	)
	valueRail.AnchorPoint = Vector2.new(0.5, 0)
	valueRail.BackgroundTransparency = 0.65
	round(valueRail, 3)
	self:_bind(valueRail, "BackgroundColor3", "slider")
	self.valueThumb = frame(
		self.valueScrollbar,
		"Range",
		UDim2.fromScale(0.5, 0),
		UDim2.new(0, 8, 1, 0),
		c.slider,
		205
	)
	self.valueThumb.AnchorPoint = Vector2.new(0.5, 0)
	self.valueThumb.Active = true
	round(self.valueThumb, 3)
	self:_bind(self.valueThumb, "BackgroundColor3", "slider")
	for _, side in { "Top", "Bottom" } do
		local handle = frame(
			self.valueThumb,
			side .. "Drag",
			UDim2.fromScale(0.5, side == "Top" and 0 or 1),
			UDim2.fromOffset(10, 10),
			c.sliderHandle,
			207
		)
		handle.AnchorPoint = Vector2.new(0.5, 0.5)
		handle.Active = true
		round(handle, 8)
		self:_bind(handle, "BackgroundColor3", "sliderHandle")
		self["value" .. side] = handle
	end

	self.scene = frame(self.plot, "CurveScene", UDim2.new(), UDim2.fromScale(1, 1), c.panel, 205)
	self.scene.BackgroundTransparency = 1

	local function widget(source, name, parent)
		if not source then
			return
		end

		local copy = source:Clone()
		copy.Name = name
		for _, node in { copy, table.unpack(copy:GetDescendants()) } do
			for key in node:GetAttributes() do
				node:SetAttribute(key, nil)
			end

			if node:IsA("GuiObject") then
				node.ZIndex = 210
			end
		end

		copy.Parent = parent
		return copy
	end

	self.playheadCursor =
		frame(chart, "PlayheadCursor", UDim2.new(), UDim2.new(0, 0, 1, 0), c.playhead, 210)
	self.playheadCursor.BackgroundTransparency = 1
	self.playhead = widget(templates.Line, "Playhead", self.playheadCursor)
		or frame(
			self.playheadCursor,
			"Playhead",
			UDim2.new(),
			UDim2.new(0, 2, 1, -15),
			c.playhead,
			208
		)
	self.playhead.Size = UDim2.new(0, templates.Line and templates.Line.Size.X.Offset or 2, 1, -15)
	self.playhead.AnchorPoint = Vector2.new(0.5, 0)
	self:_bind(self.playhead, "BackgroundColor3", "playhead")
	self.playheadChip = widget(templates.Chip, "PlayheadFrame", self.playheadCursor)
	if not self.playheadChip then
		self.playheadChip = frame(
			self.playheadCursor,
			"PlayheadFrame",
			UDim2.new(),
			UDim2.fromOffset(0, 15),
			c.playhead,
			210
		)
		self.playheadChip.AutomaticSize = Enum.AutomaticSize.X
		round(self.playheadChip, 5)
		make(
			"UIPadding",
			self.playheadChip,
			"Padding",
			{ PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }
		)
		self.playheadLabel = label(
			self.playheadChip,
			"TextLabel",
			"0",
			UDim2.new(),
			UDim2.fromScale(0, 1),
			14,
			c.playheadText
		)
		self.playheadLabel.AutomaticSize = Enum.AutomaticSize.X
	else
		self.playheadLabel = self.playheadChip:FindFirstChildWhichIsA("TextLabel")
	end

	self.playheadChip.AnchorPoint = Vector2.new(0.5, 0)
	self.playheadChip.Position = UDim2.new()
	local chipHeight = self.playheadChip.Size.Y.Offset
	self.playhead.Position = UDim2.fromOffset(0, chipHeight)
	self.playhead.Size = UDim2.new(0, self.playhead.Size.X.Offset, 1, -chipHeight)
	self:_bind(self.playheadLabel, "TextColor3", "playheadText")
	self:_bind(self.playheadChip, "BackgroundColor3", "playhead")
	self.empty = label(
		side,
		"Empty",
		"Select a bone",
		UDim2.fromOffset(7, 32),
		UDim2.new(1, -14, 0, 0),
		12,
		c.text
	)
	self.empty.TextTruncate = Enum.TextTruncate.None
	self.empty.TextWrapped = true
	self.empty.TextYAlignment = Enum.TextYAlignment.Top
	self.empty.AutomaticSize = Enum.AutomaticSize.Y
	self:_bind(self.empty, "TextColor3", "text")
	self.selectionBox =
		frame(self.plot, "BoxSelection", UDim2.new(), UDim2.new(), c.selectionLine, 210)
	self.selectionBox.BackgroundTransparency = 0.87
	self.selectionBox.Visible = false
	self:_bind(self.selectionBox, "BackgroundColor3", "selectionLine")
	self:_bind(
		make("UIStroke", self.selectionBox, "Outline", { Thickness = 1 }),
		"Color",
		"selectionLine"
	)
	self.dockButton, self.dockLabel = Chrome.menuButton(
		header,
		"Dock",
		"DOCK",
		UDim2.new(1, -186, 0, 4),
		UDim2.fromOffset(62, 20),
		209
	)
	self.preferencesButton = Chrome.menuButton(
		header,
		"Settings",
		"SETTINGS",
		UDim2.new(1, -116, 0, 4),
		UDim2.fromOffset(78, 20),
		209
	)
	connect(self, self.dockButton.Activated, function()
		self:_action("dock")
	end)
	connect(self, self.preferencesButton.Activated, function()
		self:_action("preferences")
	end)
	self:_tip(self.dockButton, "Dock or undock graph editor")
	self.modifiersButton, self.modifiersLabel = Chrome.menuButton(
		header,
		"Modifiers",
		"MODIFIERS",
		UDim2.new(1, -282, 0, 4),
		UDim2.fromOffset(90, 20),
		209
	)
	connect(self, self.modifiersButton.Activated, function()
		self:_action("modifiers")
	end)
	self:_tip(self.modifiersButton, "F-Curve modifiers (N)")
	self.toastLabel =
		label(chart, "Toast", "", UDim2.new(0, 56, 1, -30), UDim2.new(1, -70, 0, 22), 12, c.text)
	self.toastLabel.AutomaticSize = Enum.AutomaticSize.X
	self.toastLabel.Size = UDim2.fromOffset(0, 22)
	self.toastLabel.BackgroundColor3 = c.menu
	self.toastLabel.ZIndex = 225
	self.toastLabel.Visible = false
	round(self.toastLabel, 4)
	make(
		"UIPadding",
		self.toastLabel,
		"Padding",
		{ PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }
	)
	self:_bind(self.toastLabel, "BackgroundColor3", "menu")
	self:_bind(self.toastLabel, "TextColor3", "text")
	connect(self, body:GetPropertyChangedSignal("AbsoluteSize"), function()
		if self.sidebarOpen then
			self:_layoutSidebar()
		end
	end)
	self:_tip(self.preferencesButton, "Graph preferences")

	self.resizeGrips = {}

	local function startDrag(input, edge)
		if
			self.docked
			or self.closing
			or (
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			)
		then
			return
		end

		self:_finishWindowDrag()
		self:_hideTips()
		self:_cancelGeometrySave()
		self.drag = {
			input = input,
			start = Vector2.new(input.Position.X, input.Position.Y),
			position = self.frame.Position,
			size = self.frame.Size,
			edge = edge,
			scale = self:_scale(),
		}
		self.windowMotion = Motion.begin(self.frame, input, function(point)
			self.pendingWindowPoint = Vector2.new(point.X, point.Y)
			self:flushWindowDrag()
		end, function()
			self.windowMotion = nil
			self:_finishWindowDrag()
		end, edge and "resize" or "move")
	end

	connect(self, drag.InputBegan, function(input)
		startDrag(input)
	end)
	for _, edge in
		{
			Vector2.new(-1, 0),
			Vector2.new(1, 0),
			Vector2.new(0, -1),
			Vector2.new(0, 1),
			Vector2.new(-1, -1),
			Vector2.new(1, -1),
			Vector2.new(-1, 1),
			Vector2.new(1, 1),
		}
	do
		local corner = edge.X ~= 0 and edge.Y ~= 0
		local grip = self:_button(
			self.frame,
			"Resize_" .. edge.X .. "_" .. edge.Y,
			"",
			UDim2.fromScale((edge.X + 1) * 0.5, (edge.Y + 1) * 0.5),
			edge.X == 0 and UDim2.new(1, -24, 0, 8)
				or edge.Y == 0 and UDim2.new(0, 8, 1, -24)
				or UDim2.fromOffset(12, 12)
		)
		grip.AnchorPoint = Vector2.new((edge.X + 1) * 0.5, (edge.Y + 1) * 0.5)
		grip.ZIndex = corner and 221 or 220
		connect(self, grip.InputBegan, function(input)
			startDrag(input, edge)
		end)
		table.insert(self.resizeGrips, grip)
		if edge.X == 1 and edge.Y == 1 then
			self.resizeGrip = grip
			for i = 1, 2 do
				local mark = frame(
					grip,
					"Grip",
					UDim2.fromOffset(11 - i * 3, 11 - i * 3),
					UDim2.fromOffset(i * 3, 1),
					c.divider,
					222
				)
				mark.Rotation = -45
				self:_bind(mark, "BackgroundColor3", "divider")
			end
		end
	end

	connect(self, Input.InputBegan, function(input)
		if not self.docked then
			self:menuInput(input)
		end
	end)
	connect(self, Input.InputChanged, function(input)
		if not self.docked and input.UserInputType == Enum.UserInputType.MouseMovement then
			self:menuHover(self:mousePosition())
		end
	end)
	connect(self, self.plot:GetPropertyChangedSignal("AbsoluteSize"), function()
		local logical = self.plot.AbsoluteSize / self:_scale()
		if self.logicalPlotSize and (logical - self.logicalPlotSize).Magnitude < 0.1 then
			return
		end

		self.logicalPlotSize = logical
		if self.destroyed or self.resizeQueued then
			return
		end

		self.resizeQueued = true
		task.defer(function()
			self.resizeQueued = false
			if not self.destroyed then
				self:_refreshRows()
				self:_action("resize", self.plot.AbsoluteSize)
			end
		end)
	end)
	connect(self, self.channels:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:_refreshRows()
	end)
	connect(self, self.channels:GetPropertyChangedSignal("CanvasPosition"), function()
		self:_refreshRows()
	end)
	if parent:IsA("GuiObject") then
		connect(self, parent:GetPropertyChangedSignal("AbsoluteSize"), function()
			self:_constrainWindow()
		end)
	end

	connect(self, self.search:GetPropertyChangedSignal("Text"), function()
		self.channels.CanvasPosition = Vector2.zero
		self:_filterRows()
		self:_action("search", self.search.Text)
	end)
	connect(self, self.frame.Destroying, function()
		self.frameDestroying = true
		self:destroy()
	end)
	if Theme.onChanged then
		local remove = Theme.onChanged(function()
			self:_applyTheme()
		end)
		if remove then
			table.insert(self.cleanups, remove)
		end
	end

	self.heldKeys = {}
	self.frame.Active = true
	connect(self, self.frame.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			self.heldKeys[input.KeyCode] = true
		end
	end)
	connect(self, self.frame.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			self.heldKeys[input.KeyCode] = nil
		end
	end)
	connect(self, self.frame.InputBegan, function(input)
		if self.docked then
			self:menuInput(input)
		end
	end)
	connect(self, self.frame.InputChanged, function(input)
		if self.docked and input.UserInputType == Enum.UserInputType.MouseMovement then
			self:menuHover(self:mousePosition())
		end
	end)
	self.floatingParent = parent
	self.docked = false
	table.insert(
		self.cleanups,
		Preferences.subscribe(function(key)
			if key == "BlenderAxes" then
				self:_filterRows()
				self:_applyTheme()
			end
		end)
	)
	self:setData({ channels = {} })
	self:_restoreGeometry()
	return self
end

return GraphView
