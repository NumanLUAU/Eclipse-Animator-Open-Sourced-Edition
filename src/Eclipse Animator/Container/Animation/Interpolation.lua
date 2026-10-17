--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Theme = require("Theme")
local Easing = require("Easing")
local Model = require("Model")
local Motion = require("Motion")
local Editor = {}
local host

local function centered(root)
	local all = root:GetDescendants()
	table.insert(all, root)
	for _, v in all do
		if v:IsA("GuiObject") then
			local d = Vector2.new(0.5, 0.5) - v.AnchorPoint
			local p, s = v.Position, v.Size
			v.Position = UDim2.new(
				p.X.Scale + s.X.Scale * d.X,
				p.X.Offset + s.X.Offset * d.X,
				p.Y.Scale + s.Y.Scale * d.Y,
				p.Y.Offset + s.Y.Offset * d.Y
			)
			v.AnchorPoint = Vector2.new(0.5, 0.5)
		end
	end
end

function Editor.close()
	if host then
		local old = host
		host = nil
		old:close(true)
	end
end

function Editor.open(refs, value, onApply)
	Editor.close()
	local template = refs.ScreenGui:FindFirstChild("InterpolationMode", true)
	assert(template, "Interpolation menu is unavailable")
	local draft = { easeIn = Model.copy(value.easeIn), easeOut = Model.copy(value.easeOut) }
	local current = "easeIn"
	host = Tool.new(
		refs,
		"EclipseEffectInterpolation",
		"EASING SELECTION",
		Vector2.new(501, 324),
		false,

		function()
			host = nil
		end
	)
	local window = host
	local frame = host.frame
	local menu = template:Clone()
	menu.Name = "Interpolation"
	menu.Parent = frame
	menu.Visible = true
	menu.Position = UDim2.fromOffset(18, 79)
	menu.AnchorPoint = Vector2.zero
	menu.Size = UDim2.fromOffset(465, 202)
	local content = menu.Content
	local pg = content.ParameterGraph
	local graph = pg.Graph.Graph
	for _, v in graph:GetChildren() do
		if v:IsA("GuiObject") and v.Name ~= "Grid" then
			v:Destroy()
		end
	end

	local lines = {}
	for i = 1, 48 do
		lines[i] = Tool.make(
			"Frame",
			graph,
			"Curve" .. i,
			{ AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = graph.ZIndex + 3 }
		)
		lines[i]:SetAttribute("ThemeBg", "Ph")
	end

	local aliases = {
		Beziar = "Custom",
		Sinusoidal = "Sine",
		Quadratic = "Quad",
		Quartic = "Quart",
		Quintic = "Quint",
	}
	local buttons, params, tabs, directions = {}, {}, {}, {}
	for _, v in pg.Parameters.ContentContainer:GetChildren() do
		if v.Name == "ParameterSlot" then
			table.insert(params, v)
		end
	end

	table.sort(params, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local refresh
	local handles, tangents = {}, {}

	local function point(x, y)
		return Vector2.new(x, (1 - y) / 1.5 + 1 / 6)
	end

	for i = 1, 2 do
		local line = Tool.make("Frame", graph, "Tangent" .. i, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			ZIndex = graph.ZIndex + 4,
			BackgroundTransparency = 0.35,
		})
		line:SetAttribute("ThemeBg", "Txt")
		tangents[i] = line
		local h = Tool.make("TextButton", graph, "BezierHandle" .. i, {
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BorderSizePixel = 0,
			ZIndex = graph.ZIndex + 6,
		})
		h:SetAttribute("ThemeBg", "MenuSel")
		handles[i] = h
		Tool.make("UICorner", h, "Round", { CornerRadius = UDim.new(1, 0) })
		Tool.make("UIStroke", h, "Outline", { Color = Color3.new(1, 1, 1), Thickness = 1.5 })
		h.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local key = current
			Motion.begin(frame, input, function(mouse)
				if host ~= window or current ~= key or draft[key].style ~= "Custom" then
					return
				end

				local p, s = graph.AbsolutePosition, graph.AbsoluteSize
				draft[key].curve[i * 2 - 1] = math.clamp((mouse.X - p.X) / math.max(s.X, 1), 0, 1)
				draft[key].curve[i * 2] =
					math.clamp(1.25 - (mouse.Y - p.Y) / math.max(s.Y, 1) * 1.5, -0.25, 1.25)
				refresh()
			end, nil, "graph")
		end)
	end

	local function confirm()
		local result = Model.copy(draft)
		Editor.close()
		onApply(result)
	end

	local selectedParams = {}
	for _, b in menu:GetDescendants() do
		if b:IsA("GuiButton") then
			local name = b.Parent.Name
			if name == "Confirm" then
				b.Activated:Connect(confirm)
			elseif table.find(Model.styles, aliases[name] or name) then
				local style = aliases[name] or name
				buttons[style] = b
				b.Activated:Connect(function()
					draft[current].style = style
					refresh()
				end)
			end
		end
	end

	for i, key in { "easeIn", "easeOut" } do
		tabs[key] = Tool.button(
			frame,
			key,
			i == 1 and "FADE IN" or "FADE OUT",
			UDim2.fromOffset(18 + (i - 1) * 238, 38),
			UDim2.fromOffset(227, 29),

			function()
				current = key
				refresh()
			end
		)
	end

	for i, name in { "In", "Out", "InOut" } do
		directions[name] = Tool.button(
			frame,
			"Direction" .. name,
			name == "InOut" and "IN / OUT" or name:upper(),
			UDim2.fromOffset(18 + (i - 1) * 158, 285),
			UDim2.fromOffset(149, 25),

			function()
				draft[current].direction = name
				refresh()
			end
		)
	end

	for i, slot in params do
		require("NumericInput").connect(slot.ValueInput, { step = 0.05 }, function()
			local n = tonumber(slot.ValueInput.Text)
			local key = selectedParams[i]
			local e = draft[current]
			if key and Model.finite(n) then
				if type(key) == "number" then
					e.curve[key] =
						math.clamp(n, key % 2 == 1 and 0 or -10, key % 2 == 1 and 1 or 10)
				else
					e[key] = math.clamp(n, 0, 100)
				end
			end

			refresh()
		end)
	end

	refresh = function()
		local e = draft[current]
		local kd = {
			EasingStyle = e.style == "Custom" and "Bezier" or e.style,
			EasingDirection = e.direction,
			BezierPoints = e.curve,
			Overshoot = e.Overshoot,
			Amplitude = e.Amplitude,
			Period = e.Period,
		}
		for style, b in buttons do
			local check = b:FindFirstChild("Check")
			if check then
				check.Visible = style == e.style
			end

			b.BackgroundTransparency = style == e.style and 0.4 or 1
			b.BackgroundColor3 = Theme.get("MenuSel", Color3.new(0.4, 0, 0.6))
		end

		for key, b in tabs do
			b:SetAttribute("ThemeBg", key == current and "MenuSel" or "TopBtn")
			Theme.applyInstance(b)
		end

		for name, b in directions do
			b:SetAttribute("ThemeBg", name == e.direction and "MenuSel" or "TopBtn")
			Theme.applyInstance(b)
		end

		selectedParams = e.style == "Custom" and { 1, 2, 3, 4 }
			or e.style == "Back" and { "Overshoot" }
			or e.style == "Elastic" and { "Amplitude", "Period" }
			or {}
		local labels = { "X1", "Y1", "X2", "Y2" }
		for i, slot in params do
			local key = selectedParams[i]
			slot.Visible = key ~= nil
			if key then
				slot.Title.Text = (type(key) == "number" and labels[key] or key) .. ":"
				slot.ValueInput.Text = tostring(
					type(key) == "number" and e.curve[key]
						or e[key]
						or ({ Overshoot = 1.70158, Amplitude = 1, Period = 0.3 })[key]
				)
			end
		end

		local empty = pg.Parameters.Header:FindFirstChild("Empty")
		if empty then
			empty.Visible = #selectedParams == 0
		end

		for i, h in handles do
			local visible = e.style == "Custom"
			h.Visible = visible
			tangents[i].Visible = visible
			if visible then
				local a = point(i == 1 and 0 or 1, i == 1 and 0 or 1)
				local b = point(e.curve[i * 2 - 1], e.curve[i * 2])
				h.Position = UDim2.fromScale(b.X, b.Y)
				local delta = Vector2.new((b.X - a.X) * 142, (b.Y - a.Y) * 62)
				local line = tangents[i]
				line.Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2)
				line.Size = UDim2.fromOffset(delta.Magnitude, 1)
				line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			end
		end

		local last = Vector2.new(0, 1)
		for i, line in lines do
			local t = i / #lines
			local point = Vector2.new(t, 1 - math.clamp(Easing.apply(t, kd), -0.25, 1.25))
			local a, b =
				Vector2.new(last.X, last.Y / 1.5 + 1 / 6),
				Vector2.new(point.X, point.Y / 1.5 + 1 / 6)
			local delta = Vector2.new((b.X - a.X) * 142, (b.Y - a.Y) * 62)
			line.Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			line.Size = UDim2.fromOffset(delta.Magnitude, 1.5)
			line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			last = point
		end
	end

	Theme.applyTree(frame)
	centered(frame)
	refresh()
	return frame
end

return Editor
