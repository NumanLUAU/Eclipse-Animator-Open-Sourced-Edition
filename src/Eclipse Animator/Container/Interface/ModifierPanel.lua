--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Mods = require("Mods")
local Theme = require("Theme")
local History = require("History")
local Input = require("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MENU_OPEN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local MENU_HOVER = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local Panel = {}
Panel.__index = Panel
Panel.WIDTH = 250
local ROW = 22
local PAD = 6
local SHAKE_CHANNELS = {
	{ "rot_x", "AngleX" },
	{ "rot_y", "AngleY" },
	{ "rot_z", "AngleZ" },
	{ "loc_x", "PosX" },
	{ "loc_y", "PosY" },
	{ "loc_z", "PosZ" },
}

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
	make("UICorner", item, "Corners", { CornerRadius = UDim.new(0, radius or 3) })
end

local function finite(v)
	return typeof(v) == "number" and v == v and math.abs(v) < 1e14
end

local function fmt(v, integer)
	if not finite(v) then
		return "0"
	end

	if integer then
		return tostring(math.floor(v + 0.5))
	end

	if math.abs(v) < 1e-9 then
		v = 0
	end

	if math.abs(v) >= 100000 then
		return string.format("%.4g", v)
	end

	return string.format("%.3f", v)
end

local EXPRESSION = { pi = math.pi, e = math.exp(1), tau = math.pi * 2, huge = math.huge }
local FUNCTIONS = {}
for _, name in
	{
		"abs",
		"acos",
		"asin",
		"atan",
		"atan2",
		"ceil",
		"clamp",
		"cos",
		"cosh",
		"deg",
		"exp",
		"floor",
		"fmod",
		"frexp",
		"ldexp",
		"lerp",
		"log",
		"log10",
		"max",
		"min",
		"modf",
		"noise",
		"pow",
		"rad",
		"round",
		"sign",
		"sin",
		"sinh",
		"sqrt",
		"tan",
		"tanh",
	}
do
	FUNCTIONS[name] = math[name]
end

local function evaluate(text)
	if type(text) ~= "string" or #text > 1024 then
		return nil
	end

	local direct = tonumber(text)
	if direct then
		return finite(direct) and direct or nil
	end

	local ok, value = pcall(function()
		local list, position = {}, 1
		while position <= #text do
			local tail = text:sub(position)
			local space = tail:match("^%s+")
			local number = tail:match("^%d+%.?%d*[eE][+-]?%d+")
				or tail:match("^%.%d+[eE][+-]?%d+")
				or tail:match("^%d+%.?%d*")
				or tail:match("^%.%d+")
			local name = tail:match("^[%a_][%w_]*")
			if space then
				position += #space
			elseif number then
				table.insert(list, tonumber(number))
				position += #number
			elseif name then
				table.insert(list, name)
				position += #name
			else
				local symbol = tail:sub(1, 2) == "//" and "//" or tail:sub(1, 1)
				assert(({
					["+"] = true,
					["-"] = true,
					["*"] = true,
					["/"] = true,
					["//"] = true,
					["%"] = true,
					["^"] = true,
					["("] = true,
					[")"] = true,
					[","] = true,
					["."] = true,
				})[symbol])
				table.insert(list, symbol)
				position += #symbol
			end

			assert(#list <= 256)
		end

		local index, depth = 1, 0
		local precedence =
			{ ["+"] = 1, ["-"] = 1, ["*"] = 2, ["/"] = 2, ["//"] = 2, ["%"] = 2, ["^"] = 4 }
		local expression
		expression = function(minimum)
			depth += 1
			assert(depth <= 32)
			local token = list[index]
			index += 1
			local left
			if type(token) == "number" then
				left = token
			elseif token == "+" or token == "-" then
				left = expression(3)
				if token == "-" then
					left = -left
				end
			elseif token == "(" then
				left = expression(0)
				assert(list[index] == ")")
				index += 1
			elseif type(token) == "string" then
				if token == "math" then
					assert(list[index] == ".")
					token = list[index + 1]
					index += 2
				end

				if list[index] == "(" then
					local fn = FUNCTIONS[token]
					assert(type(fn) == "function")
					index += 1
					local args = {}
					if list[index] ~= ")" then
						repeat
							table.insert(args, expression(0))
							assert(#args <= 8)
							if list[index] ~= "," then
								break
							end

							index += 1
						until false
					end

					assert(list[index] == ")")
					index += 1
					left = fn(table.unpack(args))
				else
					left = EXPRESSION[token]
					assert(type(left) == "number")
				end
			else
				error("Expected a number")
			end

			while true do
				local op = list[index]
				local level = precedence[op]
				if not level or level < minimum then
					break
				end

				index += 1
				local right = expression(op == "^" and level or level + 1)
				if op == "+" then
					left += right
				elseif op == "-" then
					left -= right
				elseif op == "*" then
					left *= right
				elseif op == "/" then
					left /= right
				elseif op == "//" then
					left = math.floor(left / right)
				elseif op == "%" then
					left %= right
				else
					left ^= right
				end
			end

			depth -= 1
			return left
		end

		local result = expression(0)
		assert(index > #list)
		return result
	end)
	return ok and finite(value) and value or nil
end

function Panel.new(view, host, parent)
	local self = setmetatable({
		view = view,
		host = host,
		connections = {},
		cardConnections = {},
		cardTips = {},
		repaint = {},
		cards = {},
		open = false,
		onlyActive = false,
		replacePaste = false,
		mode = "stack",
		expandedRange = setmetatable({}, { __mode = "k" }),
	}, Panel)
	local c = view.colors
	self.bold = view.title and view.title.FontFace
		or Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
	self.font = Font.new(self.bold.Family, Enum.FontWeight.Regular, self.bold.Style)
	self.shake = {
		Start = 0,
		End = 30,
		RepeatRange = false,
		EaseIn = 6,
		EaseOut = 6,
		Interval = 4,
		Detail = 1,
		Seed = math.random(1, 999),
		AngleX = 2,
		AngleY = 2,
		AngleZ = 2,
		PosX = 0,
		PosY = 0,
		PosZ = 0,
	}
	self.frame = make("Frame", parent, "ModifierPanel", {
		Position = UDim2.new(1, -Panel.WIDTH, 0, 0),
		Size = UDim2.new(0, Panel.WIDTH, 1, -2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 212,
		Visible = false,
		ClipsDescendants = true,
	})
	self.divider = make("Frame", self.frame, "Divider", {
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = c.divider,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 213,
	})
	self.divider:SetAttribute("ThemeBg", "Div")
	self.title = self:_label(
		self.frame,
		"Title",
		"MODIFIERS",
		UDim2.fromOffset(PAD + 4, 2),
		UDim2.new(1, -40, 0, 18),
		11,
		true
	)
	self.curve = self:_label(
		self.frame,
		"Curve",
		"",
		UDim2.fromOffset(PAD + 4, 19),
		UDim2.new(1, -16, 0, 16),
		11
	)
	self.close = self:_button(
		self.frame,
		"Close",
		"×",
		UDim2.new(1, -24, 0, 3),
		UDim2.fromOffset(20, 18),

		function()
			host.toggle(false)
		end,
		"Hide modifiers (N)"
	)
	self.close.TextSize = 16
	self.addButton = self:_button(
		self.frame,
		"Add",
		"ADD MODIFIER  ▼",
		UDim2.fromOffset(PAD + 4, 40),
		UDim2.new(1, -PAD * 2 - 4, 0, 22),

		function()
			self:_openAddMenu()
		end,
		"Add a modifier to the active curve (Ctrl+Shift+M adds to every selected curve)"
	)
	self:_chip(self.addButton)
	self.copyButton = self:_button(
		self.frame,
		"Copy",
		"COPY",
		UDim2.fromOffset(PAD + 4, 65),
		UDim2.new(0.5, -PAD - 4, 0, 20),

		function()
			self:copy()
		end,
		"Copy the active curve's modifiers"
	)
	self.pasteButton = self:_button(
		self.frame,
		"Paste",
		"PASTE",
		UDim2.new(0.5, 2, 0, 65),
		UDim2.new(0.5, -PAD - 4, 0, 20),

		function()
			self:paste()
		end,
		"Paste modifiers onto the selected curves"
	)
	self:_chip(self.copyButton)
	self:_chip(self.pasteButton)
	self.onlyToggle = self:_toggle(
		self.frame,
		"OnlyActive",
		"Paste to Active",
		UDim2.fromOffset(PAD + 4, 88),
		UDim2.new(0.5, -PAD, 0, 18),

		function()
			return self.onlyActive
		end,

		function(v)
			self.onlyActive = v
		end,
		"Paste only onto the active curve instead of every selected curve"
	)
	self.replaceToggle = self:_toggle(
		self.frame,
		"Replace",
		"Replace Existing",
		UDim2.new(0.5, 0, 0, 88),
		UDim2.new(0.5, -PAD, 0, 18),

		function()
			return self.replacePaste
		end,

		function(v)
			self.replacePaste = v
		end,
		"Paste replaces the existing modifiers instead of appending"
	)
	self.shakeButton = self:_button(
		self.frame,
		"Shake",
		"SHAKE BONES…",
		UDim2.fromOffset(PAD + 4, 110),
		UDim2.new(1, -PAD * 2 - 4, 0, 20),

		function()
			self:setMode(self.mode == "shake" and "stack" or "shake")
		end,
		"Wiggle the selected bones over a frame range with ease in and out"
	)
	self:_chip(self.shakeButton)
	self.list = make("ScrollingFrame", self.frame, "Stack", {
		Position = UDim2.fromOffset(4, 136),
		Size = UDim2.new(1, -6, 1, -138),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = c.scroll,
		ZIndex = 213,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	})
	make(
		"UIListLayout",
		self.list,
		"Layout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	make("UIPadding", self.list, "Padding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 8),
	})
	self.empty = self:_label(
		self.frame,
		"Empty",
		"",
		UDim2.fromOffset(PAD + 4, 142),
		UDim2.new(1, -PAD * 2 - 4, 0, 60),
		11
	)
	self.empty.TextWrapped = true
	self.empty.TextYAlignment = Enum.TextYAlignment.Top
	self.empty.TextTruncate = Enum.TextTruncate.None
	self.indicator = make("Frame", self.frame, "DropLine", {
		Size = UDim2.new(1, -16, 0, 2),
		BackgroundColor3 = c.selection,
		BorderSizePixel = 0,
		ZIndex = 230,
		Visible = false,
	})
	self:_paint()
	Theme.applyInstance(self.divider)
	return self
end

function Panel:_hold(connection)
	table.insert(self.building and self.cardConnections or self.connections, connection)
	return connection
end

function Panel:_tip(item, text)
	self.view:_tip(item, text)
	if self.building then
		table.insert(self.cardTips, item)
	end
end

function Panel:_label(parent, name, text, position, size, textSize, bold)
	return make("TextLabel", parent, name, {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = bold and self.bold or self.font,
		TextSize = textSize or 11,
		TextColor3 = self.view.colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 215,
	})
end

function Panel:_button(parent, name, text, position, size, callback, tip)
	local b = make("TextButton", parent, name, {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BackgroundColor3 = self.view.colors.selection,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		TextColor3 = self.view.colors.text,
		FontFace = self.bold,
		TextSize = 11,
		ZIndex = 216,
	})
	self:_hold(b.MouseEnter:Connect(function()
		b.BackgroundTransparency = b:GetAttribute("Chip") and 0.35 or 0.6
	end))
	self:_hold(b.MouseLeave:Connect(function()
		b.BackgroundTransparency = b:GetAttribute("Chip") and 0.65 or 1
	end))
	if callback then
		self:_hold(b.Activated:Connect(function()
			callback()
		end))
	end

	if tip then
		self:_tip(b, tip)
	end

	return b
end

function Panel:_chip(button)
	button:SetAttribute("Chip", true)
	button.BackgroundTransparency = 0.65
	button.BackgroundColor3 = self.view.colors.border
	round(button, 3)
end

function Panel:_toggle(parent, name, text, position, size, get, set, tip)
	local row = make("TextButton", parent, name, {
		Text = "",
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 215,
	})
	local box = make("Frame", row, "Box", {
		Position = UDim2.new(0, 0, 0.5, -6),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = self.view.colors.border,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 216,
	})
	round(box, 2)
	local mark = make("TextLabel", box, "Mark", {
		Text = "✓",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextColor3 = self.view.colors.text,
		FontFace = self.bold,
		TextSize = 11,
		ZIndex = 217,
	})
	local l = self:_label(row, "Label", text, UDim2.fromOffset(17, 0), UDim2.new(1, -17, 1, 0), 10)

	local function paint()
		local c = self.view.colors
		local on = get() == true
		mark.Visible = on
		mark.TextColor3 = c.text
		box.BackgroundColor3 = on and c.selection or c.border
		l.TextColor3 = c.text
		l.TextTransparency = on and 0 or 0.25
	end

	self:_hold(row.Activated:Connect(function()
		set(not get())
		paint()
	end))
	paint()
	if tip then
		self:_tip(row, tip)
	end

	if not self.building then
		table.insert(self.repaint, paint)
	end

	return row, paint
end

function Panel:_paint()
	local c = self.view.colors
	self.title.TextColor3 = c.text
	self.curve.TextColor3 = c.muted
	self.empty.TextColor3 = c.muted
	self.list.ScrollBarImageColor3 = c.scroll
	self.indicator.BackgroundColor3 = c.selection
	for _, button in
		{ self.close, self.addButton, self.copyButton, self.pasteButton, self.shakeButton }
	do
		button.TextColor3 = c.text
		if button:GetAttribute("Chip") then
			button.BackgroundColor3 = c.border
		end
	end

	for _, paint in self.repaint do
		paint()
	end
end

function Panel:applyTheme()
	self:_closePopup()
	self:_paint()
	self:refresh(true)
end

function Panel:target()
	return self.host.activeTrack()
end

function Panel:entry(create)
	local track = self:target()
	if not track then
		return nil
	end

	if create then
		return Mods.ensure(track.motor, track.channelId)
	end

	return Mods.get(track.motor, track.channelId)
end

function Panel:_valueStep()
	local track = self:target()
	if not track then
		return 0.01
	end

	if track.group == "Euler Rotation" then
		return 0.1
	end

	if track.group == "Quaternion Rotation" then
		return 0.002
	end

	return 0.01
end

function Panel:_record(label, motors, mutate)
	local before = {}
	for motor in motors do
		before[motor] = Mods.snapshot(motor)
	end

	local ok, err = pcall(mutate)
	for motor in motors do
		Mods.prune(motor)
	end

	local after = {}
	for motor in motors do
		after[motor] = Mods.snapshot(motor)
	end

	local function apply(state)
		for motor in motors do
			Mods.restore(motor, state[motor])
		end

		self.host.changed(motors)
		self:refresh(true)
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, label)
	if not ok then
		self.host.status((tostring(err):gsub("^.-:%d+: ", "")))
	end

	return ok
end

function Panel:_begin(motor)
	self.pending = { motor = motor, before = Mods.snapshot(motor) }
end

function Panel:_live()
	if self.pending then
		self.host.changed({ [self.pending.motor] = true }, true)
	end
end

function Panel:_finish(label)
	local pending = self.pending
	self.pending = nil
	if not pending then
		return
	end

	local motor = pending.motor
	Mods.prune(motor)
	local before, after = pending.before, Mods.snapshot(motor)

	local function apply(state)
		Mods.restore(motor, state)
		self.host.changed({ [motor] = true })
		self:refresh(true)
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, label)
end

function Panel:_edit(label, mutate)
	local track = self:target()
	if not track then
		return
	end

	if track.locked then
		self.host.status("Unlock this curve before editing its modifiers.")
		return
	end

	self:_begin(track.motor)
	mutate()
	self:_finish(label)
end

function Panel:addModifier(kind, allSelected)
	local tracks = allSelected and self.host.selectedTracks() or { self:target() }
	if #tracks == 0 or not tracks[1] then
		self.host.status(
			allSelected and "Select curves before adding a modifier."
				or "Select a curve before adding a modifier."
		)
		return
	end

	local motors = {}
	for _, track in tracks do
		if not track.locked then
			motors[track.motor] = true
		end
	end

	if not next(motors) then
		self.host.status("Unlock the curve before adding a modifier.")
		return
	end

	local failed
	self:_record("Add F-Curve Modifier", motors, function()
		for _, track in tracks do
			if track.locked then
				continue
			end

			local entry = Mods.ensure(track.motor, track.channelId)
			local m, err = Mods.add(entry, kind)
			if not m then
				failed = err
			end
		end
	end)
	if failed then
		self.host.status(failed)
	end
end

function Panel:copy()
	local entry = self:entry(false)
	if not entry or #entry.Stack == 0 then
		self.host.status("No F-Modifiers available to be copied")
		return
	end

	Panel.clipboard = Mods.clone(entry.Stack)
	self.host.status(
		"Copied " .. #Panel.clipboard .. " modifier" .. (#Panel.clipboard == 1 and "" or "s")
	)
end

function Panel:paste()
	if not Panel.clipboard or #Panel.clipboard == 0 then
		self.host.status("No F-Modifiers to paste")
		return
	end

	local tracks = self.onlyActive and { self:target() } or self.host.selectedTracks()
	local usable = {}
	for _, track in tracks do
		if track and not track.locked then
			table.insert(usable, track)
		end
	end

	if #usable == 0 then
		self.host.status("No F-Modifiers to paste")
		return
	end

	local motors = {}
	for _, track in usable do
		motors[track.motor] = true
	end

	self:_record("Paste F-Modifiers", motors, function()
		for _, track in usable do
			local entry = Mods.ensure(track.motor, track.channelId)
			if self.replacePaste then
				table.clear(entry.Stack)
			end

			for _, m in Panel.clipboard do
				local copy = Mods.clone(m)
				copy.Active = false
				table.insert(entry.Stack, copy)
			end
		end
	end)
end

function Panel:setOff(track, off)
	if not track then
		return
	end

	self:_record(
		off and "Disable F-Curve Modifiers" or "Enable F-Curve Modifiers",
		{ [track.motor] = true },

		function()
			Mods.ensure(track.motor, track.channelId).Off = off
		end
	)
end

function Panel:_popup(anchor, options, current, callback, title)
	if self.popup and self.popupAnchor == anchor then
		self:_closePopup()
		return
	end

	self:_closePopup()
	local c = self.view.colors
	local root = self.view.frame
	local scale = self.view:_scale()
	local header = title and 20 or 0
	local height = #options * 22 + 6 + header
	local popup = make("Frame", nil, "ModifierMenu", {
		BackgroundColor3 = c.menu,
		BorderSizePixel = 0,
		ZIndex = 240,
		Size = UDim2.fromOffset(
			math.max(150, anchor and anchor.AbsoluteSize.X / scale or 0),
			height
		),
	})
	round(popup, 4)
	local outline = make("UIStroke", popup, "Outline", { Color = c.border, Thickness = 1 })
	popup:SetAttribute("ThemeBg", "Menu")
	outline:SetAttribute("ThemeStrk", "Strk")
	make("UIListLayout", popup, "Layout", { SortOrder = Enum.SortOrder.LayoutOrder })
	make(
		"UIPadding",
		popup,
		"Padding",
		{ PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }
	)
	if title then
		local t = make("TextLabel", popup, "Title", {
			Text = "  " .. title,
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			TextColor3 = c.muted,
			FontFace = self.bold,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 241,
		})
		t.TextTransparency = 0.1
	end

	for i, option in options do
		local text = type(option) == "table" and option.text or option
		local value = type(option) == "table" and option.value or option
		local b = make("TextButton", popup, "Option", {
			Text = "  " .. text,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = c.selection,
			BackgroundTransparency = value == current and 0.45 or 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			TextColor3 = c.menuText or c.text,
			FontFace = self.font,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 241,
		})
		b:SetAttribute("ThemeTxt", "Txt")
		local hoverTween

		local function paint(hover)
			if hoverTween then
				hoverTween:Cancel()
			end

			local selected = value == current
			local color = Theme.get(hover and "MenuHov" or "MenuSel", c.selection)
			if b.BackgroundTransparency >= 0.99 then
				b.BackgroundColor3 = color
			end

			hoverTween = TweenService:Create(b, MENU_HOVER, {
				BackgroundColor3 = color,
				BackgroundTransparency = (hover or selected) and 0 or 1,
			})
			hoverTween:Play()
		end

		b.BackgroundColor3 = Theme.get("MenuSel", c.selection)
		b.BackgroundTransparency = value == current and 0 or 1
		b.MouseEnter:Connect(function()
			paint(true)
		end)
		b.MouseLeave:Connect(function()
			paint(false)
		end)
		b.Destroying:Once(function()
			if hoverTween then
				hoverTween:Cancel()
			end
		end)
		b.Activated:Connect(function()
			self:_closePopup()
			callback(value)
		end)
	end

	local at
	if anchor then
		at = (anchor.AbsolutePosition - root.AbsolutePosition) / scale
			+ Vector2.new(0, anchor.AbsoluteSize.Y / scale + 2)
	else
		at = (self.view:mousePosition() - root.AbsolutePosition) / scale
	end

	local limit = root.AbsoluteSize / scale
	local y = at.Y
	if y + height > limit.Y - 4 then
		y = math.max(4, (anchor and at.Y - anchor.AbsoluteSize.Y / scale - 4 or at.Y) - height)
	end

	popup.Position =
		UDim2.fromOffset(math.clamp(at.X, 4, math.max(4, limit.X - popup.Size.X.Offset - 4)), y)
	self.popup = popup
	self.popupAnchor = anchor
	self.choose = function(value)
		self:_closePopup()
		callback(value)
	end

	Theme.applyTree(popup)
	local menuScale = make("UIScale", popup, "MenuScale", { Scale = 0.88 })
	popup.Parent = root
	self.popupTween = TweenService:Create(menuScale, MENU_OPEN, { Scale = 1 })
	self.popupTween:Play()

	local function outside()
		task.defer(function()
			if self.popup ~= popup then
				return
			end

			local p = self.view:mousePosition()
			if anchor and anchor.Parent then
				local a, s = anchor.AbsolutePosition, anchor.AbsoluteSize
				if p.X >= a.X and p.Y >= a.Y and p.X <= a.X + s.X and p.Y <= a.Y + s.Y then
					return
				end
			end

			local a, s = popup.AbsolutePosition, popup.AbsoluteSize
			if p.X < a.X or p.Y < a.Y or p.X > a.X + s.X or p.Y > a.Y + s.Y then
				self:_closePopup()
			end
		end)
	end

	local function watch(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
		then
			outside()
		elseif
			input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == Enum.KeyCode.Escape
		then
			self:_closePopup()
		end
	end

	self.popupWatch = {
		Input.InputBegan:Connect(watch),
		root.InputBegan:Connect(function(input)
			if self.view.docked then
				watch(input)
			end
		end),
	}
	return popup
end

function Panel:_closePopup()
	if self.popupTween then
		self.popupTween:Cancel()
		self.popupTween = nil
	end

	self.popupAnchor = nil
	if self.popupWatch then
		for _, connection in self.popupWatch do
			connection:Disconnect()
		end

		self.popupWatch = nil
	end

	if self.popup then
		self.popup:Destroy()
		self.popup = nil
	end

	self.choose = nil
end

function Panel:isPopupOpen()
	return self.popup ~= nil
end

function Panel:_openAddMenu()
	self:_popup(self.addButton, Mods.KINDS, nil, function(kind)
		self:addModifier(kind, false)
	end)
end

function Panel:openAddMenuAt()
	self:_popup(nil, Mods.KINDS, nil, function(kind)
		self:addModifier(kind, true)
	end, "ADD F-CURVE MODIFIER")
end

function Panel:_number(parent, order, text, get, set, opts)
	opts = opts or {}
	local c = self.view.colors
	local row = make("Frame", parent, "Field", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		ZIndex = 215,
	})
	if text then
		local l = self:_label(row, "Label", text, UDim2.new(), UDim2.new(0.42, -4, 1, 0), 10)
		l.TextXAlignment = Enum.TextXAlignment.Right
		l.TextColor3 = c.text:Lerp(c.muted, 0.3)
		if opts.disabled then
			l.TextTransparency = 0.45
		end
	end

	local left = text and 0.42 or 0
	local box = make("TextBox", row, "Value", {
		Position = UDim2.new(left, 2, 0, 2),
		Size = UDim2.new(1 - left, -2, 1, -4),
		BackgroundColor3 = c.border,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Text = fmt(get(), opts.integer),
		TextColor3 = c.text,
		FontFace = self.font,
		TextSize = 11,
		ClearTextOnFocus = false,
		ZIndex = 216,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextEditable = not opts.disabled,
	})
	round(box, 3)
	local overlay = make("TextButton", box, "Scrub", {
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ZIndex = 218,
	})
	if opts.disabled then
		box.TextTransparency = 0.55
		box.BackgroundTransparency = 0.7
	end

	if opts.tip then
		self:_tip(overlay, opts.tip)
	end

	local function show()
		box.Text = fmt(get(), opts.integer)
	end

	local function clean(value)
		if opts.integer then
			value = math.floor(value + 0.5)
		end

		if opts.min then
			value = math.max(opts.min, value)
		end

		if opts.max then
			value = math.min(opts.max, value)
		end

		return value
	end

	local function begin()
		if opts.plain then
			return true
		end

		local track = self:target()
		if not track or track.locked then
			return false
		end

		self:_begin(track.motor)
		return true
	end

	local function finish(label)
		if opts.plain then
			if opts.changed then
				opts.changed()
			end

			return
		end

		self:_finish(label or "Edit F-Modifier")
	end

	local drag
	local lastPress, lastPoint = -math.huge, Vector2.zero

	local function editText()
		if not box.Parent or opts.disabled then
			return
		end

		overlay.Visible = false
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end

	local function stop(typing)
		if not drag then
			return
		end

		local was = drag
		drag = nil
		self.numberStop = nil
		for _, connection in was.connections do
			connection:Disconnect()
		end

		if was.moved then
			finish()
		else
			if not opts.plain then
				self.pending = nil
			end

			if typing ~= false then
				editText()
			end
		end
	end

	self:_hold(overlay.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or opts.disabled then
			return
		end

		local now, point = os.clock(), self.view:mousePosition()
		local doubleClick = now - lastPress <= 0.35
			and (point - lastPoint).Magnitude <= 5 * self.view:_scale()
		lastPress, lastPoint = now, point
		if self.numberStop then
			self.numberStop(false)
		end

		if not box.Parent then
			return
		end

		if doubleClick then
			editText()
			return
		end

		if not begin() then
			return
		end

		self.numberStop = stop
		drag = { start = self.view:mousePosition(), value = get(), moved = false, connections = {} }
		table.insert(
			drag.connections,
			RunService.RenderStepped:Connect(function()
				if not drag then
					return
				end

				if
					not self.view.docked
					and not Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
				then
					stop()
					return
				end

				local dx = (self.view:mousePosition() - drag.start).X / self.view:_scale()
				if not drag.moved and math.abs(dx) < 3 then
					return
				end

				drag.moved = true
				local base = opts.step or 0.01
				local step = base
				if
					self.view:isKeyDown(Enum.KeyCode.LeftShift)
					or self.view:isKeyDown(Enum.KeyCode.RightShift)
				then
					step *= 0.1
				end

				local value = drag.value + dx * step
				if
					self.view:isKeyDown(Enum.KeyCode.LeftControl)
					or self.view:isKeyDown(Enum.KeyCode.RightControl)
				then
					local snap = base * 10
					value = math.floor(value / snap + 0.5) * snap
				end

				value = clean(value)
				if value ~= get() then
					set(value)
					show()
					if opts.plain then
						if opts.changed then
							opts.changed()
						end
					else
						self:_live()
					end
				end
			end)
		)

		local function ended(e)
			if e.UserInputType == Enum.UserInputType.MouseButton1 then
				stop()
			end
		end

		local function inputState()
			if input.UserInputState == Enum.UserInputState.End then
				stop()
			elseif input.UserInputState == Enum.UserInputState.Cancel then
				stop(false)
			end
		end

		table.insert(
			drag.connections,
			input:GetPropertyChangedSignal("UserInputState"):Connect(inputState)
		)
		table.insert(drag.connections, overlay.InputEnded:Connect(ended))
		table.insert(
			drag.connections,
			Input.WindowFocusReleased:Connect(function()
				stop(false)
			end)
		)
		local widget = self.view.frame:FindFirstAncestorWhichIsA("DockWidgetPluginGui")
		if widget then
			table.insert(
				drag.connections,
				widget.WindowFocusReleased:Connect(function()
					stop(false)
				end)
			)
		end

		table.insert(
			drag.connections,
			row.Destroying:Connect(function()
				stop(false)
			end)
		)
		table.insert(drag.connections, Input.InputEnded:Connect(ended))
		table.insert(drag.connections, self.view.frame.InputEnded:Connect(ended))
	end))
	require("NumericInput").bind(box, {
		surface = overlay,
		step = opts.integer and 1 or math.max(0.01, (opts.step or 0.01) * 5),
		integer = opts.integer,
		min = opts.min,
		max = opts.max,
		enabled = function()
			return not opts.disabled and not drag
		end,
		change = function(value)
			if begin() then
				set(clean(value))
				show()
				finish()
			end
		end,
	})
	self:_hold(box.FocusLost:Connect(function()
		overlay.Visible = true
		local value = evaluate(box.Text)
		if finite(value) and clean(value) ~= get() and begin() then
			set(clean(value))
			finish()
		end

		if box.Parent then
			show()
		end
	end))
	return row
end

function Panel:_check(parent, order, text, get, set, plain)
	local row = make("Frame", parent, "Check", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		ZIndex = 215,
	})
	self:_toggle(row, "Toggle", text, UDim2.new(0.42, 2, 0, 2), UDim2.new(0.58, -2, 1, -4), get, function(
		v
	)
		if plain then
			set(v)
		else
			self:_edit("Edit F-Modifier", function()
				set(v)
			end)
		end
	end
)
	return row
end

function Panel:_checkNumber(parent, order, text, getOn, setOn, get, set, opts)
	local row = self:_number(parent, order, nil, get, set, opts)
	row.Value.Position = UDim2.new(0.42, 2, 0, 2)
	row.Value.Size = UDim2.new(0.58, -2, 1, -4)
	self:_toggle(row, "Toggle", text, UDim2.new(0, 0, 0, 2), UDim2.new(0.42, -4, 1, -4), getOn, function(
		v
	)
		self:_edit("Edit F-Modifier", function()
			setOn(v)
		end)
	end
)
	return row
end

function Panel:_enum(parent, order, text, options, get, set)
	local c = self.view.colors
	local row = make("Frame", parent, "Enum", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		ZIndex = 215,
	})
	if text then
		local l = self:_label(row, "Label", text, UDim2.new(), UDim2.new(0.42, -4, 1, 0), 10)
		l.TextXAlignment = Enum.TextXAlignment.Right
		l.TextColor3 = c.text:Lerp(c.muted, 0.3)
	end

	local left = text and 0.42 or 0
	local b
	b = self:_button(
		row,
		"Value",
		get() .. "  ▼",
		UDim2.new(left, 2, 0, 2),
		UDim2.new(1 - left, -2, 1, -4),

		function()
			self:_popup(b, options, get(), function(value)
				if value ~= get() then
					self:_edit("Edit F-Modifier", function()
						set(value)
					end)
				end
			end)
		end
	)
	b.FontFace = self.font
	self:_chip(b)
	return row
end

function Panel:_header(parent, order, text)
	local l = self:_label(parent, "Section", text, UDim2.new(), UDim2.new(1, 0, 0, 16), 10, true)
	l.LayoutOrder = order
	l.TextColor3 = self.view.colors.muted
	return l
end

function Panel:_body(card, m, entry)
	local body = make("Frame", card, "Body", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 214,
	})
	make(
		"UIListLayout",
		body,
		"Layout",
		{ Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	make("UIPadding", body, "Padding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	})
	local order = 0

	local function n()
		order += 1
		return order
	end

	local function field(key)
		return function()
			return m[key]
		end, function(v)
			m[key] = v
		end
	end

	local vstep = self:_valueStep()
	if m.Type == "Generator" then
		self:_enum(body, n(), nil, Mods.GENERATOR_MODES, function()
			return m.Mode
		end, function(v)
			m.Mode = v
			Mods.verify(m)
		end)
		self:_check(body, n(), "Additive", field("Additive"))
		self:_number(body, n(), "Order", function()
			return m.Order
		end, function(v)
			m.Order = v
			Mods.verify(m)
		end, { integer = true, min = 1, max = 100, step = 0.05 })
		if m.Mode == "Factorized Polynomial" then
			local head = make("Frame", body, "PairHeader", {
				LayoutOrder = n(),
				Size = UDim2.new(1, 0, 0, 14),
				BackgroundTransparency = 1,
				ZIndex = 215,
			})
			for i, name in { "A", "B" } do
				local l = self:_label(
					head,
					name,
					name,
					UDim2.new(0.42 + (i - 1) * 0.29, 2, 0, 0),
					UDim2.new(0.29, -2, 1, 0),
					9
				)
				l.TextXAlignment = Enum.TextXAlignment.Center
				l.TextColor3 = self.view.colors.muted
			end

			for i = 1, m.Order do
				local row = self:_number(body, n(), i == 1 and "y = (Ax + B)" or "× (Ax + B)", function()
					return m.Coefficients[2 * i - 1]
				end, function(v)
					m.Coefficients[2 * i - 1] = v
				end
)
				row.Value.Size = UDim2.new(0.29, -2, 1, -4)
				local second = self:_number(row, 1, nil, function()
					return m.Coefficients[2 * i]
				end, function(v)
					m.Coefficients[2 * i] = v
				end, { step = vstep })
				second.Position = UDim2.new(0.71, 0, 0, 0)
				second.Size = UDim2.new(0.29, 0, 1, 0)
			end
		else
			for i = 1, m.Order + 1 do
				self:_number(body, n(), i == 1 and "Coefficient" or ("x^" .. (i - 1)), function()
					return m.Coefficients[i]
				end, function(v)
					m.Coefficients[i] = v
				end, { step = i == 1 and vstep or 0.01 })
			end
		end
	elseif m.Type == "Built-In Function" then
		self:_enum(body, n(), nil, Mods.FUNCTIONS, field("Function"))
		self:_check(body, n(), "Additive", field("Additive"))
		self:_number(body, n(), "Amplitude", function()
			return m.Amplitude
		end, function(v)
			m.Amplitude = v
		end, { step = vstep })
		self:_number(body, n(), "Phase Multiplier", field("PhaseMultiplier"))
		self:_number(body, n(), "Phase Offset", field("PhaseOffset"))
		self:_number(body, n(), "Value Offset", function()
			return m.ValueOffset
		end, function(v)
			m.ValueOffset = v
		end, { step = vstep })
	elseif m.Type == "Envelope" then
		self:_number(body, n(), "Reference", function()
			return m.Reference
		end, function(v)
			m.Reference = v
		end, { step = vstep })
		self:_number(body, n(), "Min", function()
			return m.Min
		end, function(v)
			m.Min = v
		end, { step = vstep })
		self:_number(body, n(), "Max", function()
			return m.Max
		end, function(v)
			m.Max = v
		end, { step = vstep })
		local add = self:_button(
			body,
			"AddPoint",
			"ADD CONTROL POINT",
			UDim2.new(),
			UDim2.new(1, 0, 0, 20),

			function()
				local frame = self.host.currentFrame()
				for _, p in m.Points do
					if math.abs(p.Frame - frame) < 1e-4 then
						return
					end
				end

				self:_edit("Add Envelope Control Point", function()
					table.insert(m.Points, { Frame = frame, Min = -1, Max = 1 })
					Mods.verify(m)
				end)
			end,
			"Add a control point at the current frame"
		)
		add.LayoutOrder = n()
		self:_chip(add)
		if #m.Points > 0 then
			local head = make("Frame", body, "PointHeader", {
				LayoutOrder = n(),
				Size = UDim2.new(1, 0, 0, 14),
				BackgroundTransparency = 1,
				ZIndex = 215,
			})
			for i, name in { "Frame", "Min", "Max" } do
				local l = self:_label(
					head,
					name,
					name,
					UDim2.new((i - 1) * 0.3, 0, 0, 0),
					UDim2.new(0.3, -2, 1, 0),
					9
				)
				l.TextXAlignment = Enum.TextXAlignment.Center
				l.TextColor3 = self.view.colors.muted
			end
		end

		for i, p in m.Points do
			local row = make("Frame", body, "Point", {
				LayoutOrder = n(),
				Size = UDim2.new(1, 0, 0, ROW),
				BackgroundTransparency = 1,
				ZIndex = 215,
			})

			local function part(key, x)
				local f = self:_number(row, 1, nil, function()
					return p[key]
				end, function(v)
					p[key] = v
					if key == "Frame" then
						Mods.verify(m)
					end
				end, { step = key == "Frame" and 0.1 or vstep })
				f.Position = UDim2.new(x, 0, 0, 0)
				f.Size = UDim2.new(0.3, -2, 1, 0)
			end

			part("Frame", 0)
			part("Min", 0.3)
			part("Max", 0.6)
			self:_button(row, "Delete", "×", UDim2.new(0.9, 2, 0, 2), UDim2.new(0.1, -2, 1, -4), function()
				self:_edit("Delete Envelope Control Point", function()
					local index = table.find(m.Points, p)
					if index then
						table.remove(m.Points, index)
					end
				end)
			end, "Delete control point")
		end
	elseif m.Type == "Cycles" then
		self:_check(body, n(), "Smooth Loop", function()
			return m.SmoothSeam == true
		end, function(v)
			m.SmoothSeam = v
		end)
		self:_enum(body, n(), "Before Mode", Mods.CYCLE_MODES, field("BeforeMode"))
		self:_number(body, n(), "Count", function()
			return m.BeforeCount
		end, function(v)
			m.BeforeCount = v
		end, { integer = true, min = 0, step = 0.05, tip = "0 repeats forever" })
		self:_enum(body, n(), "After Mode", Mods.CYCLE_MODES, field("AfterMode"))
		self:_number(body, n(), "Count", function()
			return m.AfterCount
		end, function(v)
			m.AfterCount = v
		end, { integer = true, min = 0, step = 0.05, tip = "0 repeats forever" })
	elseif m.Type == "Noise" then
		self:_check(body, n(), "Repeat Range", field("RepeatRange"))
		self:_enum(body, n(), "Blend Type", Mods.BLENDS, field("Blend"))
		self:_number(body, n(), "Scale", field("Scale"))
		self:_number(body, n(), "Strength", function()
			return m.Strength
		end, function(v)
			m.Strength = v
		end, { step = vstep })
		self:_number(body, n(), "Offset", field("Offset"), { step = 0.1 })
		self:_number(body, n(), "Phase", field("Phase"))
		self:_number(body, n(), "Depth", function()
			return m.Depth
		end, function(v)
			m.Depth = v
		end, { integer = true, min = 0, max = 32767, step = 0.05 })
		self:_check(body, n(), "Legacy Noise", field("Legacy"))
		if not m.Legacy then
			self:_number(body, n(), "Lacunarity", field("Lacunarity"))
			self:_number(body, n(), "Roughness", field("Roughness"))
		end
	elseif m.Type == "Limits" then
		self:_checkNumber(body, n(), "Minimum X", function()
			return m.UseMinX
		end, function(v)
			m.UseMinX = v
		end, function()
			return m.MinX
		end, function(v)
			m.MinX = v
			m.MaxX = math.max(m.MinX, m.MaxX)
		end, { disabled = not m.UseMinX, step = 0.1 })
		self:_checkNumber(body, n(), "Y", function()
			return m.UseMinY
		end, function(v)
			m.UseMinY = v
		end, function()
			return m.MinY
		end, function(v)
			m.MinY = v
			m.MaxY = math.max(m.MinY, m.MaxY)
		end, { disabled = not m.UseMinY, step = vstep })
		self:_checkNumber(body, n(), "Maximum X", function()
			return m.UseMaxX
		end, function(v)
			m.UseMaxX = v
		end, function()
			return m.MaxX
		end, function(v)
			m.MaxX = v
			m.MinX = math.min(m.MinX, m.MaxX)
		end, { disabled = not m.UseMaxX, step = 0.1 })
		self:_checkNumber(body, n(), "Y", function()
			return m.UseMaxY
		end, function(v)
			m.UseMaxY = v
		end, function()
			return m.MaxY
		end, function(v)
			m.MaxY = v
			m.MinY = math.min(m.MinY, m.MaxY)
		end, { disabled = not m.UseMaxY, step = vstep })
	elseif m.Type == "Stepped Interpolation" then
		self:_number(body, n(), "Step Size", field("Step"), { step = 0.02 })
		self:_number(body, n(), "Offset", field("StepOffset"), { step = 0.02 })
		self:_checkNumber(body, n(), "Start Frame", function()
			return m.UseStepStart
		end, function(v)
			m.UseStepStart = v
		end, function()
			return m.StepStart
		end, function(v)
			if m.UseStepEnd then
				v = math.min(v, m.StepEnd)
			end

			m.StepStart = v
			m.Start = v
		end, { disabled = not m.UseStepStart, step = 0.1 })
		self:_checkNumber(body, n(), "End Frame", function()
			return m.UseStepEnd
		end, function(v)
			m.UseStepEnd = v
		end, function()
			return m.StepEnd
		end, function(v)
			if m.UseStepStart then
				v = math.max(v, m.StepStart)
			end

			m.StepEnd = v
			m.End = v
		end, { disabled = not m.UseStepEnd, step = 0.1 })
	end

	self:_checkNumber(body, n(), "Influence", function()
		return m.UseInfluence
	end, function(v)
		m.UseInfluence = v
	end, function()
		return m.Influence
	end, function(v)
		m.Influence = v
	end, { disabled = not m.UseInfluence, min = 0, max = 1, step = 0.005 })
	local rangeRow = make("Frame", body, "Range", {
		LayoutOrder = n(),
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		ZIndex = 215,
	})
	local expanded = self.expandedRange[m]
	if expanded == nil then
		expanded = m.UseRange
	end

	self:_button(
		rangeRow,
		"Expand",
		expanded and "▼" or "▶",
		UDim2.new(0, 0, 0, 2),
		UDim2.fromOffset(16, 18),

		function()
			self.expandedRange[m] = not expanded
			self:refresh(true)
		end
	)
	self:_toggle(
		rangeRow,
		"Toggle",
		"Restrict Frame Range",
		UDim2.new(0, 18, 0, 2),
		UDim2.new(1, -18, 1, -4),

		function()
			return m.UseRange
		end,

		function(v)
			self.expandedRange[m] = v or expanded
			self:_edit("Restrict Frame Range", function()
				m.UseRange = v
				if v and m.Start == 0 and m.End == 0 then
					local first, last = self.host.keySpan()
					if first then
						m.Start, m.End = first, last
					end
				end
			end)
		end
	)
	if expanded then
		self:_number(body, n(), "Start", function()
			return m.Start
		end, function(v)
			m.Start = v
			m.End = math.max(m.Start, m.End)
		end, { disabled = not m.UseRange, step = 0.1 })
		self:_number(body, n(), "End", function()
			return m.End
		end, function(v)
			m.End = v
			m.Start = math.min(m.End, m.Start)
		end, { disabled = not m.UseRange, step = 0.1 })
		self:_number(body, n(), "Blend In", function()
			return m.BlendIn
		end, function(v)
			m.BlendIn = math.clamp(v, 0, math.max(0, m.End - m.Start))
		end, { disabled = not m.UseRange, min = 0, step = 0.1 })
		self:_number(body, n(), "Out", function()
			return m.BlendOut
		end, function(v)
			m.BlendOut = math.clamp(v, 0, math.max(0, m.End - m.Start))
		end, { disabled = not m.UseRange, min = 0, step = 0.1 })
	end

	return body
end

function Panel:_clearCards()
	if self.numberStop then
		self.numberStop(false)
	end

	for _, connection in self.cardConnections do
		connection:Disconnect()
	end

	table.clear(self.cardConnections)
	local view = self.view
	for _, item in self.cardTips do
		view.tipButtons[item] = nil
		local binding = view.tipBindings and view.tipBindings[item]
		if binding then
			binding()
			view.tipBindings[item] = nil
		end
	end

	table.clear(self.cardTips)
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	table.clear(self.cards)
end

function Panel:_note(order, text, button, callback)
	local c = self.view.colors
	local note = make("Frame", self.list, "Note", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = c.selection,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 214,
	})
	round(note, 4)
	make("UIPadding", note, "Padding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	})
	make(
		"UIListLayout",
		note,
		"Layout",
		{ Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	local l = self:_label(note, "Text", text, UDim2.new(), UDim2.new(1, 0, 0, 0), 10)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextTruncate = Enum.TextTruncate.None
	l.LayoutOrder = 1
	if button then
		local b =
			self:_button(note, "Action", button, UDim2.new(), UDim2.new(1, 0, 0, 18), callback)
		b.LayoutOrder = 2
		self:_chip(b)
	end

	return note
end

function Panel:_card(order, m, entry, index)
	local c = self.view.colors
	local card = make("Frame", self.list, "Modifier", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = c.border,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = 214,
	})
	round(card, 4)
	local stroke = make(
		"UIStroke",
		card,
		"Active",
		{ Color = c.selection, Thickness = 1, Transparency = m.Active and 0.15 or 0.85 }
	)
	make("UIListLayout", card, "Layout", { SortOrder = Enum.SortOrder.LayoutOrder })
	local header = make(
		"Frame",
		card,
		"Header",
		{ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 215 }
	)
	self:_button(
		header,
		"Expand",
		m.Expanded and "▼" or "▶",
		UDim2.fromOffset(2, 3),
		UDim2.fromOffset(16, 18),

		function()
			m.Expanded = not m.Expanded
			self:refresh(true)
		end,
		m.Expanded and "Collapse" or "Expand"
	)
	local active = make("TextButton", header, "ActiveToggle", {
		Text = "",
		Position = UDim2.fromOffset(20, 6),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = m.Active and c.selection or c.border,
		BackgroundTransparency = m.Active and 0 or 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 217,
	})
	round(active, 6)
	make(
		"UIStroke",
		active,
		"Ring",
		{ Color = c.text, Thickness = 1, Transparency = m.Active and 0.2 or 0.7 }
	)
	self:_tip(active, "Active modifier (Envelope controls draw for the active one)")
	self:_hold(active.Activated:Connect(function()
		if m.Active then
			return
		end

		self:_edit("Set Active F-Modifier", function()
			Mods.setActive(entry, m)
		end)
	end))
	local name = make("TextBox", header, "Name", {
		Text = m.Name,
		Position = UDim2.fromOffset(36, 3),
		Size = UDim2.new(1, -100, 0, 18),
		BackgroundColor3 = c.border,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		FontFace = self.bold,
		TextSize = 11,
		TextColor3 = c.text,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 216,
	})
	round(name, 3)
	make(
		"UIPadding",
		name,
		"Padding",
		{ PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 4) }
	)
	if m.Mute then
		name.TextTransparency = 0.45
	end

	self:_hold(name.FocusLost:Connect(function()
		local wanted = (name.Text:gsub("^%s+", ""):gsub("%s+$", ""))
		local final = Mods.uniqueName(entry.Stack, m, wanted)
		if final ~= m.Name then
			self:_edit("Rename F-Modifier", function()
				m.Name = final
			end)
		elseif name.Parent then
			name.Text = m.Name
		end
	end))
	local enabled = make("TextButton", header, "Enabled", {
		Text = m.Mute and "" or "✓",
		Position = UDim2.new(1, -60, 0, 5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = m.Mute and c.border or c.selection,
		BackgroundTransparency = m.Mute and 0.3 or 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		TextColor3 = c.text,
		FontFace = self.bold,
		TextSize = 11,
		ZIndex = 217,
	})
	round(enabled, 2)
	self:_tip(enabled, m.Mute and "Modifier is muted, click to enable" or "Mute this modifier")
	self:_hold(enabled.Activated:Connect(function()
		self:_edit(m.Mute and "Unmute F-Modifier" or "Mute F-Modifier", function()
			m.Mute = not m.Mute
		end)
	end))
	self:_button(header, "Delete", "×", UDim2.new(1, -42, 0, 3), UDim2.fromOffset(18, 18), function()
		self:_edit("Delete F-Modifier", function()
			Mods.remove(entry, m)
		end)
	end, "Delete Modifier").TextSize =
		15
	local grip = self:_button(
		header,
		"Grip",
		"≡",
		UDim2.new(1, -22, 0, 3),
		UDim2.fromOffset(18, 18),
		nil,
		"Drag to reorder"
	)
	grip.TextColor3 = c.muted
	self:_hold(grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_startReorder(card, m, entry)
		end
	end))
	if m.Expanded then
		self:_body(card, m, entry)
	end

	self.cards[index] = card
	return card
end

function Panel:_dropIndex(y)
	local index = #self.cards
	for i, card in self.cards do
		if y < card.AbsolutePosition.Y + card.AbsoluteSize.Y * 0.5 then
			index = i
			break
		end
	end

	return index
end

function Panel:_startReorder(card, m, entry)
	if self.reorder then
		return
	end

	local start = self.view:mousePosition()
	local from = table.find(entry.Stack, m)
	if not from then
		return
	end

	local state = { connections = {}, moved = false }
	self.reorder = state
	local scale = self.view:_scale()

	local function place(index)
		local target = self.cards[index]
		if not target then
			self.indicator.Visible = false
			return
		end

		local below = index > from
		local y = below and target.AbsolutePosition.Y + target.AbsoluteSize.Y + 2
			or target.AbsolutePosition.Y - 3
		self.indicator.Position = UDim2.fromOffset(8, (y - self.frame.AbsolutePosition.Y) / scale)
		self.indicator.Visible = index ~= from
	end

	local function stop()
		if self.reorder ~= state then
			return
		end

		self.reorder = nil
		for _, connection in state.connections do
			connection:Disconnect()
		end

		self.indicator.Visible = false
		card.BackgroundTransparency = 0.8
		if not state.moved then
			return
		end

		local index = self:_dropIndex(self.view:mousePosition().Y)
		if index == from then
			return
		end

		if
			m.Type == "Cycles"
			or (entry.Stack[1] and entry.Stack[1].Type == "Cycles" and index == 1)
		then
			self.host.status("Modifier requires original data")
			return
		end

		self:_edit("Move F-Modifier", function()
			Mods.move(entry, m, index)
		end)
	end

	table.insert(
		state.connections,
		RunService.RenderStepped:Connect(function()
			if
				not self.view.docked
				and not Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			then
				stop()
				return
			end

			local p = self.view:mousePosition()
			if not state.moved and math.abs(p.Y - start.Y) < 4 then
				return
			end

			state.moved = true
			card.BackgroundTransparency = 0.55
			place(self:_dropIndex(p.Y))
		end)
	)

	local function ended(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			stop()
		end
	end

	table.insert(state.connections, Input.InputEnded:Connect(ended))
	table.insert(state.connections, self.view.frame.InputEnded:Connect(ended))
end

function Panel:refresh(force)
	if not self.open or self.destroyed then
		return
	end

	local track = self:target()
	local entry = track and Mods.get(track.motor, track.channelId)
	local signature = table.concat({
		tostring(track and track.id),
		tostring(entry),
		tostring(entry and #entry.Stack or -1),
		tostring(entry and entry.Off),
		self.mode,
		tostring(track and track.locked),
	}, "|")
	if not force and signature == self.signature then
		return
	end

	if self.pending or self.reorder then
		return
	end

	local focused = Input:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(self.list) and not force then
		return
	end

	self.signature = signature
	local scroll = self.list.CanvasPosition
	self:_clearCards()
	self.building = true
	local ok, err = pcall(function()
		local shaking = self.mode == "shake"
		self.shakeButton.Text = shaking and "◀  BACK TO MODIFIERS" or "SHAKE BONES…"
		for _, item in
			{
				self.addButton,
				self.copyButton,
				self.pasteButton,
				self.onlyToggle,
				self.replaceToggle,
			}
		do
			item.Visible = not shaking
		end

		self.shakeButton.Position = UDim2.fromOffset(PAD + 4, shaking and 40 or 110)
		self.list.Position = UDim2.fromOffset(4, shaking and 66 or 136)
		self.list.Size = UDim2.new(1, -6, 1, shaking and -68 or -138)
		if self.mode == "shake" then
			self.curve.Text = "Bone shake"
			self.empty.Visible = false
			self:_shakeForm()
			return
		end

		self.curve.Text = track and (tostring(track.bone) .. " · " .. tostring(track.name))
			or "No active curve"
		local has = entry and #entry.Stack > 0
		self.empty.Visible = track ~= nil and not has
		if not track then
			self.empty.Text = ""
		elseif not has then
			self.empty.Text =
				"No modifiers on this curve yet. Use ADD MODIFIER, or press Ctrl+Shift+M in the graph to add one to every selected curve."
		end

		if not has then
			local hiddenShake = false
			for _, id in { "rot_x", "rot_y", "rot_z" } do
				local other = track and Mods.get(track.motor, id)
				for _, m in other and other.Stack or {} do
					if id ~= track.channelId and m.Type == "Noise" and m.Name:match("^Shake") then
						hiddenShake = true
					end
				end
			end

			if hiddenShake then
				self.empty.Visible = false
				self:_note(
					1,
					"This bone has Shake modifiers on its Euler rotation channels.",
					"MANAGE SHAKE",

					function()
						self:setMode("shake")
					end
				)
			end

			return
		end

		local order = 0
		if entry.Off then
			order += 1
			self:_note(order, "Modifiers are turned off for this curve.", "TURN ON", function()
				self:setOff(track, false)
			end)
		elseif track.keysHidden then
			order += 1
			self:_note(
				order,
				"Keys are hidden because a modifier overrides this curve's shape. Mute it or turn modifiers off to edit keys."
			)
		end

		if track.locked then
			order += 1
			self:_note(order, "This curve is locked. Unlock it in the channel list to edit.")
		end

		for index, m in entry.Stack do
			order += 1
			self:_card(order, m, entry, index)
		end
	end)
	self.building = false
	if not ok then
		warn("Eclipse modifier panel: " .. tostring(err))
	end

	self.list.CanvasPosition = scroll
end

function Panel:setMode(mode)
	if self.mode == mode then
		return
	end

	self.mode = mode
	if mode == "shake" then
		self:_primeShake()
	end

	self:refresh(true)
end

function Panel:setOpen(open)
	open = open == true
	if self.open == open then
		return
	end

	self.open = open
	self.frame.Visible = open
	if not open then
		self:_closePopup()
		self:_clearCards()
		self.signature = nil
	else
		self:refresh(true)
	end
end

function Panel:destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true
	self:_closePopup()
	self:_clearCards()
	if self.reorder then
		for _, connection in self.reorder.connections do
			connection:Disconnect()
		end

		self.reorder = nil
	end

	for _, connection in self.connections do
		connection:Disconnect()
	end

	table.clear(self.connections)
	self.frame:Destroy()
end

function Panel:_primeShake()
	local cfg = self.shake
	local length = math.max(1, cfg.End - cfg.Start)
	cfg.Start = math.floor(self.host.currentFrame() + 0.5)
	cfg.End = cfg.Start + length
end

function Panel:_shakeForm()
	local cfg = self.shake
	local c = self.view.colors
	local order = 0

	local function n()
		order += 1
		return order
	end

	local motors = self.host.shakeMotors()
	local names = {}
	for i, motor in motors do
		if i > 4 then
			table.insert(names, "+" .. (#motors - 4) .. " more")
			break
		end

		table.insert(names, motor.Part1 and motor.Part1.Name or motor.Name)
	end

	self:_note(
		n(),
		#motors == 0 and "Select one or more bones to shake."
			or (
				#motors
				.. " bone"
				.. (#motors == 1 and "" or "s")
				.. ": "
				.. table.concat(names, ", ")
			)
	)
	local form = make("Frame", self.list, "ShakeForm", {
		LayoutOrder = n(),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = c.border,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = 214,
	})
	round(form, 4)
	make(
		"UIListLayout",
		form,
		"Layout",
		{ Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	make("UIPadding", form, "Padding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 6),
	})
	local row = 0

	local function r()
		row += 1
		return row
	end

	local function number(text, key, opts)
		opts = opts or {}
		opts.plain = true
		return self:_number(form, r(), text, function()
			return cfg[key]
		end, function(v)
			cfg[key] = v
		end, opts)
	end

	self:_header(form, r(), "FRAMES")
	number("Start", "Start", { integer = true, step = 0.1 })
	number("End", "End", { integer = true, step = 0.1 })
	self:_check(form, r(), "Repeat Shake", function()
		return cfg.RepeatRange == true
	end, function(v)
		cfg.RepeatRange = v
	end, true)
	number("Ease In", "EaseIn", { min = 0, step = 0.1, tip = "Frames the shake takes to ramp up" })
	number("Ease Out", "EaseOut", { min = 0, step = 0.1, tip = "Frames the shake takes to settle" })
	self:_header(form, r(), "MOTION")
	number(
		"Interval",
		"Interval",
		{ min = 0.1, step = 0.02, tip = "Frames between wiggles, lower is faster" }
	)
	number("Detail", "Detail", {
		integer = true,
		min = 0,
		max = 6,
		step = 0.05,
		tip = "Adds finer jitter on top of the main wiggle",
	})
	local seedRow = number("Seed", "Seed", { integer = true, min = 0, step = 0.1 })
	seedRow.Value.Size = UDim2.new(0.58, -36, 1, -4)
	self:_button(seedRow, "Shuffle", "RND", UDim2.new(1, -32, 0, 2), UDim2.fromOffset(32, 18), function()
		cfg.Seed = math.random(1, 999)
		self:refresh(true)
	end, "New random seed")
	self:_header(form, r(), "ANGLE (DEGREES)")
	for _, axis in { "X", "Y", "Z" } do
		local f = number(axis, "Angle" .. axis, { step = 0.05 })
		f.Label.TextColor3 = c[axis] or c.text
	end

	self:_header(form, r(), "POSITION (STUDS)")
	for _, axis in { "X", "Y", "Z" } do
		local f = number(axis, "Pos" .. axis, { step = 0.002 })
		f.Label.TextColor3 = c[axis] or c.text
	end

	local actions = make("Frame", self.list, "ShakeActions", {
		LayoutOrder = n(),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		ZIndex = 214,
	})
	local apply = self:_button(
		actions,
		"Apply",
		"ADD SHAKE",
		UDim2.new(),
		UDim2.new(0.6, -2, 1, 0),

		function()
			self:applyShake()
		end,
		"Adds a Noise modifier with a restricted, eased range to each chosen channel"
	)
	self:_chip(apply)
	apply.BackgroundColor3 = c.selection
	apply.BackgroundTransparency = 0.35
	local remove = self:_button(
		actions,
		"Remove",
		"REMOVE",
		UDim2.new(0.6, 2, 0, 0),
		UDim2.new(0.4, -2, 1, 0),

		function()
			self:removeShake()
		end,
		"Removes shake modifiers from the selected bones"
	)
	self:_chip(remove)
	self:_note(
		n(),
		"Drag a value or double-click to type. Repeat Shake repeats the Start–End range after Start. Angle shake is on the Euler rotation curves; a Cycles modifier on Position does not repeat it."
	)
end

function Panel:applyShake()
	local cfg = self.shake
	local motors = self.host.shakeMotors()
	if #motors == 0 then
		self.host.status("Select bones to shake.")
		return
	end

	if cfg.End <= cfg.Start then
		self.host.status("The shake needs an End frame after its Start frame.")
		return
	end

	local any = false
	for _, pair in SHAKE_CHANNELS do
		if cfg[pair[2]] ~= 0 then
			any = true
		end
	end

	if not any then
		self.host.status("Set an angle or position amount first.")
		return
	end

	local set = {}
	for _, motor in motors do
		set[motor] = true
	end

	local span = cfg.End - cfg.Start
	local count = 0
	self:_record("Add Shake", set, function()
		for mi, motor in motors do
			for ci, pair in SHAKE_CHANNELS do
				local amount = cfg[pair[2]]
				if amount == 0 then
					continue
				end

				local entry = Mods.ensure(motor, pair[1])
				local m = Mods.new("Noise")
				m.Name = Mods.uniqueName(entry.Stack, m, "Shake")
				m.Blend = "Replace"
				m.Strength = math.abs(amount) * 2.5
				m.Scale = math.max(0.1, cfg.Interval)
				m.Phase = ((cfg.Seed * 7.31 + ci * 13.7 + mi * 3.07) % 97) + 1
				m.Depth = cfg.Detail
				m.UseRange = true
				m.RepeatRange = cfg.RepeatRange == true
				m.Start, m.End = cfg.Start, cfg.End
				m.BlendIn = math.clamp(cfg.EaseIn, 0, span)
				m.BlendOut = math.clamp(cfg.EaseOut, 0, span - m.BlendIn)
				m.Expanded = false
				table.insert(entry.Stack, m)
				Mods.setActive(entry, m)
				count += 1
			end
		end
	end)
	self.host.status(
		"Shake added to "
			.. count
			.. " curve"
			.. (count == 1 and "" or "s")
			.. ". Ctrl+Z removes it."
	)
	self.host.shakeAdded(motors)
end

function Panel:removeShake()
	local motors = self.host.shakeMotors()
	if #motors == 0 then
		self.host.status("Select bones to remove shake from.")
		return
	end

	local found = false
	for _, motor in motors do
		for _, pair in SHAKE_CHANNELS do
			local entry = Mods.get(motor, pair[1])
			for _, m in entry and entry.Stack or {} do
				if m.Type == "Noise" and string.match(m.Name, "^Shake") then
					found = true
				end
			end
		end
	end

	if not found then
		self.host.status("No shake on the selected bones.")
		return
	end

	local set = {}
	for _, motor in motors do
		set[motor] = true
	end

	self:_record("Remove Shake", set, function()
		for _, motor in motors do
			for _, pair in SHAKE_CHANNELS do
				local entry = Mods.get(motor, pair[1])
				if not entry then
					continue
				end

				for i = #entry.Stack, 1, -1 do
					local m = entry.Stack[i]
					if m.Type == "Noise" and string.match(m.Name, "^Shake") then
						table.remove(entry.Stack, i)
					end
				end
			end
		end
	end)
	self.host.status("Shake removed.")
end

return Panel
