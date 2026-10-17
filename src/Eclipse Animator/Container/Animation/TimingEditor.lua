--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Curve = require("Timing")
local Motion = require("Motion")
local Input = require("UserInputService")
local Theme = require("Theme")
local Notice = require("Notification")
local Editor = {}
local window

function Editor.hasFocus()
	if not window or window.closed then
		return false
	end

	local point = Input:GetMouseLocation()
	local frame = window.frame
	local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
	return point.X >= pos.X
		and point.X <= pos.X + size.X
		and point.Y >= pos.Y
		and point.Y <= pos.Y + size.Y
end

function Editor.close()
	if window then
		local old = window
		window = nil
		old:close()
	end
end

function Editor.open(refs, value, onApply)
	Editor.close()
	refs.State.PathEasingEditor = Editor
	local draft = Curve.copy(value)
	local selected = 1
	window = Tool.new(refs, "EclipsePathEasing", "PATH TIMING", Vector2.new(440, 394), false, function()
		window = nil
	end
)
	local host, frame = window, window.frame
	local repaint
	local modes = {}
	for i, entry in
		{
			{ "Linear", "LINEAR" },
			{ "QuadIn", "QUAD IN" },
			{ "QuadOut", "QUAD OUT" },
			{
				"Custom",
				"CUSTOM",
			},
		}
	do
		modes[entry[1]] = Tool.button(
			frame,
			entry[1],
			entry[2],
			UDim2.fromOffset(12 + (i - 1) * 107, 36),
			UDim2.fromOffset(95, 26),

			function()
				if entry[1] ~= "Custom" or draft.mode ~= "Custom" then
					draft = Curve.new(entry[1])
					selected = 1
				end

				repaint()
			end
		)
	end

	local graph = Tool.make("TextButton", frame, "Graph", {
		Text = "",
		AutoButtonColor = false,
		Active = true,
		Position = UDim2.fromOffset(36, 94),
		Size = UDim2.fromOffset(388, 180),
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 12,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.7,
	})

	local gradient = Tool.make(
		"UIGradient",
		graph,
		"UIGradient",
		{ Rotation = 90, Transparency = NumberSequence.new(1, 0) }
	)
	gradient:SetAttribute("ThemeGrad", "MenuSel")
	local stroke = Tool.make("UIStroke", graph, "UIStroke", { Thickness = 1 })
	stroke:SetAttribute("ThemeStrk", "Strk")
	Tool.make("ImageLabel", graph, "Grid", {
		BackgroundTransparency = 1,
		Image = "rbxassetid://131801242728904",
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(142, 62),
		ZIndex = 13,
		Active = false,
	})
	for i = 0, 4 do
		local y = Tool.label(
			frame,
			"Distance" .. i,
			tostring(100 - i * 25),
			UDim2.fromOffset(4, 86 + i * 45),
			UDim2.fromOffset(27, 16)
		)
		y.TextSize = 10
		y.TextXAlignment = Enum.TextXAlignment.Right
		local x = Tool.label(
			frame,
			"Time" .. i,
			tostring(i * 25),
			UDim2.fromOffset(24 + i * 97, 276),
			UDim2.fromOffset(26, 16)
		)
		x.TextSize = 10
		x.TextXAlignment = Enum.TextXAlignment.Center
	end

	local segments, nodes = {}, {}
	Tool.label(frame, "TimeLabel", "Time (%)", UDim2.fromOffset(12, 300), UDim2.fromOffset(120, 18))
	Tool.label(
		frame,
		"DistanceLabel",
		"Speed (%)",
		UDim2.fromOffset(152, 300),
		UDim2.fromOffset(128, 18)
	)
	local time =
		Tool.field(frame, "TimeValue", "0", UDim2.fromOffset(12, 320), UDim2.fromOffset(128, 26))
	local distance = Tool.field(
		frame,
		"DistanceValue",
		"0",
		UDim2.fromOffset(152, 320),
		UDim2.fromOffset(128, 26)
	)
	Tool.button(
		frame,
		"AddPoint",
		"ADD POINT",
		UDim2.fromOffset(292, 294),
		UDim2.fromOffset(136, 22),

		function()
			local at, width = 0.5, -1
			for i = 2, #draft.points do
				local a, b = draft.points[i - 1][1], draft.points[i][1]
				if b - a > width then
					width = b - a
					at = (a + b) / 2
				end
			end

			selected = Curve.add(draft, at, Curve.speed(draft, at))
			repaint()
		end
	)
	local remove = Tool.button(
		frame,
		"RemovePoint",
		"REMOVE POINT",
		UDim2.fromOffset(292, 320),
		UDim2.fromOffset(136, 26),

		function()
			if Curve.remove(draft, selected) then
				selected = math.max(1, selected - 1)
				repaint()
			end
		end
	)

	local function coordinates(point)
		local size = graph.AbsoluteSize
		return math.clamp((point.X - graph.AbsolutePosition.X) / math.max(1, size.X), 0, 1),
			1 - math.clamp((point.Y - graph.AbsolutePosition.Y) / math.max(1, size.Y), 0, 1)
	end

	graph.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.MouseButton2
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local x, y = coordinates(input.Position)
		local nearest, best = nil, 100
		for i, point in draft.points do
			local delta = Vector2.new(
				(point[1] - x) * graph.AbsoluteSize.X,
				(point[2] - y) * graph.AbsoluteSize.Y
			).Magnitude
			if delta < best then
				nearest, best = i, delta
			end
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if nearest and best <= 10 then
				Curve.remove(draft, nearest)
				selected = 1
				repaint()
			end

			return
		end

		selected = nearest and best <= 10 and nearest or Curve.add(draft, x, y)
		repaint()
		Motion.begin(frame, input, function(point)
			local t, d = coordinates(point)
			Curve.move(draft, selected, t, d)
			repaint()
		end, nil, "graph")
	end)

	local function setValue()
		local t, d = tonumber(time.Text), tonumber(distance.Text)
		if t and d and t == t and d == d then
			Curve.move(draft, selected, t / 100, d / 100)
		end

		repaint()
	end

	require("NumericInput").connect(time, { step = 1, min = 0, max = 100 }, setValue)
	require("NumericInput").connect(distance, { step = 1, min = 0, max = 100 }, setValue)
	Tool.button(
		frame,
		"Cancel",
		"CANCEL",
		UDim2.fromOffset(12, 356),
		UDim2.fromOffset(202, 26),
		Editor.close
	)
	Tool.button(
		frame,
		"Apply",
		"APPLY TIMING",
		UDim2.fromOffset(226, 356),
		UDim2.fromOffset(202, 26),

		function()
			local ok, err = pcall(function()
				Curve.validate(draft)
				onApply(Curve.copy(draft))
			end)
			if ok then
				Editor.close()
			else
				Notice.show("PATH TIMING", (tostring(err):gsub("^.-:%d+: ", "")))
			end
		end
	)
	repaint = function()
		if host.closed then
			return
		end

		local points = Curve.polyline(draft)
		for i = #segments, #points, -1 do
			segments[i]:Destroy()
			segments[i] = nil
		end

		for i = 1, #points - 1 do
			local line = segments[i]
			if not line then
				line = Tool.make(
					"Frame",
					graph,
					"Curve" .. i,
					{ AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 14 }
				)
				line:SetAttribute("ThemeBg", "Ph")
				Theme.applyInstance(line)
				segments[i] = line
			end

			local a, b = points[i], points[i + 1]
			local delta = Vector2.new((b.X - a.X) * 388, (b.Y - a.Y) * 180)
			line.Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			line.Size = UDim2.new(delta.Magnitude / 388, 1, 0, 2)
			line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		end

		for i = #nodes, #draft.points + 1, -1 do
			nodes[i]:Destroy()
			nodes[i] = nil
		end

		for i, point in draft.points do
			if not nodes[i] then
				nodes[i] = Tool.make(
					"Frame",
					graph,
					"Point" .. i,
					{ AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 15 }
				)
				Tool.make("UICorner", nodes[i], "Round", { CornerRadius = UDim.new(1, 0) })
			end

			local node = nodes[i]
			node.Position = UDim2.fromScale(point[1], 1 - point[2])
			node.Size = UDim2.fromOffset(i == selected and 11 or 8, i == selected and 11 or 8)
			node:SetAttribute("ThemeBg", i == selected and "MenuSel" or "Ph")
			Theme.applyInstance(node)
		end

		for mode, button in modes do
			button:SetAttribute("ThemeBg", mode == draft.mode and "MenuSel" or "TopBtn")
			Theme.applyInstance(button)
		end

		selected = math.clamp(selected, 1, #draft.points)
		time.Text = string.format("%.2f", draft.points[selected][1] * 100)
		distance.Text = string.format("%.2f", draft.points[selected][2] * 100)
		time.TextEditable = true
		distance.TextEditable = true
		remove.Interactable = #draft.points > 2
	end

	local key = Input.InputBegan:Connect(function(input)
		if
			not host.closed
			and not Input:GetFocusedTextBox()
			and input.KeyCode == Enum.KeyCode.Delete
		then
			local point = Input:GetMouseLocation()
			local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
			if
				point.X >= pos.X
				and point.X <= pos.X + size.X
				and point.Y >= pos.Y
				and point.Y <= pos.Y + size.Y
			then
				if Curve.remove(draft, selected) then
					selected = 1
					repaint()
				end
			end
		end
	end)
	table.insert(host.connections, key)
	repaint()
	Theme.applyTree(frame)
	return frame
end

return Editor
