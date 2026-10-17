--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Theme = require("Theme")
local Scene = require("Scene")
local History = require("History")
local Selection = game:GetService("Selection")
local Display = require("SceneSync")
local Notice = require("Notification")
local Forces = {}
local refs, window

function Forces.rangeError(first, last, part)
	part = part or window and window.selectedForce
	if not part or not part.Parent then
		return nil
	end

	local at = part:GetAttribute("Frame")
	local kind = part:GetAttribute("ForceType") or "Blast"
	local finish = at
		and (
			(kind == "BlackHole" or part:GetAttribute("ForcePath"))
				and at + (part:GetAttribute("Duration") or 60) + (at == first and 1 or 0)
			or at
		)
	if at and first and last and (at < first or finish > last) then
		return string.format(
			"%s is at frame %d%s, outside simulation %d-%d. Click Include in Forces, or change the force frame or simulation range.",
			kind,
			at,
			finish ~= at and "-" .. finish or "",
			first,
			last
		)
	end
end

function Forces.close()
	if window then
		local old = window
		window = nil
		old:close()
	end
end

function Forces.place(frame, main, viewport)
	if not main then
		return
	end

	local gap = 12
	local size = Vector2.new(440, 454)
	local mainSize = Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
	local pos = main.AbsolutePosition
	local x, y =
		pos.X + mainSize.X + gap, math.clamp(pos.Y, gap, math.max(gap, viewport.Y - size.Y - gap))
	if x + size.X > viewport.X - gap then
		if pos.X - size.X - gap >= gap then
			x = pos.X - size.X - gap
		elseif viewport.X >= mainSize.X + size.X + gap * 3 then
			local mainX = viewport.X - size.X - mainSize.X - gap * 2
			main.AnchorPoint = Vector2.zero
			main.Position = UDim2.fromOffset(mainX, pos.Y)
			x = mainX + mainSize.X + gap
		elseif pos.Y + mainSize.Y + size.Y + gap * 2 <= viewport.Y then
			x = gap
			y = pos.Y + mainSize.Y + gap
		elseif pos.Y - size.Y - gap >= gap then
			x = gap
			y = pos.Y - size.Y - gap
		end
	end

	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(
		math.clamp(x, 0, math.max(0, viewport.X - size.X)) + size.X * 0.5,
		math.clamp(y, 0, math.max(0, viewport.Y - size.Y)) + size.Y * 0.5
	)
end

function Forces.open()
	if window then
		return window.frame
	end

	window = Tool.new(refs, "EclipsePhysicsForces", "FORCES", Vector2.new(440, 454), false, function()
		window = nil
	end
)
	local host, frame = window, window.frame
	local session, physics = Scene.get(), refs.State.Physics
	local selected, repaint, stamp, drawnForces
	local inputs, buttons, kinds = {}, {}, {}

	local function action(callback)
		if host.closed then
			return
		end

		local ok, err = pcall(function()
			assert(not refs.State.Timeline:GetState().Playing, "Pause playback first")
			assert(not refs.State.PhysicsSimulating, "Wait for the simulation to finish")
			callback()
		end)
		if not ok then
			Notice.show("FORCES", (tostring(err):gsub("^.-:%d+: ", "")))
		end

		repaint()
	end

	local function attribute(name, value)
		assert(selected and selected.Parent, "Create or select a force first")
		local part, before = selected, selected:GetAttribute(name)
		if before == value then
			return
		end

		local function apply(nextValue)
			part:SetAttribute(name, nextValue)
			refs.State.currentProjectSaved = false
		end

		apply(value)
		History.record(function()
			apply(before)
		end, function()
			apply(value)
		end, "Edit force " .. name)
	end

	for i, kind in { "Blast", "Pull", "Lift", "BlackHole" } do
		local button = Tool.button(
			frame,
			kind,
			kind == "BlackHole" and "BLACK HOLE" or kind:upper(),
			UDim2.fromOffset(12 + (i - 1) * 107, 74),
			UDim2.fromOffset(95, 26),

			function()
				action(function()
					attribute("ForceType", kind)
				end)
			end
		)
		button.TextLabel.TextSize = 11
		kinds[kind] = button
	end

	local fields = {
		{ "Frame", "At frame", 0, 100000 },
		{ "Duration", "Frames", 1, 2400 },
		{ "Radius", "Radius", 0.1, 1000 },
		{ "Power", "Power", 0, 500 },
		{ "Spin", "Spin (turns/s)", -10, 10 },
		{ "Launch", "Launch speed", 0, 500 },
	}
	for i, field in fields do
		local name, label, low, high = table.unpack(field)
		local x = 12 + ((i - 1) % 4) * 107
		local y = i <= 4 and 224 or 282
		Tool.label(frame, name .. "Label", label, UDim2.fromOffset(x, y), UDim2.fromOffset(99, 20))
		local box =
			Tool.field(frame, name, "", UDim2.fromOffset(x, y + 22), UDim2.fromOffset(95, 26))
		inputs[name] = box
		require("NumericInput").connect(box, {
			step = (name == "Frame" or name == "Duration") and 1 or name == "Spin" and 0.1 or 1,
			min = low,
			max = high,
			integer = name == "Frame" or name == "Duration",
		}, function()
			if not box.TextEditable then
				return
			end

			action(function()
				local value = tonumber(box.Text)
				assert(
					value
						and value == value
						and value >= low
						and value <= high
						and ((name ~= "Frame" and name ~= "Duration") or value % 1 == 0),
					label .. " needs " .. low .. " to " .. high
				)
				attribute(name, value)
			end)
		end)
	end

	buttons.playhead = Tool.button(
		frame,
		"AtPlayhead",
		"USE PLAYHEAD",
		UDim2.fromOffset(226, 304),
		UDim2.fromOffset(95, 26),

		function()
			action(function()
				local raw = refs.State.Timeline:GetState()
				attribute("Frame", math.floor(raw.CurrentTime * raw.FPS + 0.5))
			end)
		end
	)
	buttons.jump = Tool.button(
		frame,
		"Jump",
		"GO TO FRAME",
		UDim2.fromOffset(333, 304),
		UDim2.fromOffset(95, 26),

		function()
			action(function()
				physics.jump(selected:GetAttribute("Frame"))
			end)
		end
	)
	local include = Tool.button(
		frame,
		"IncludeFrame",
		"INCLUDE FORCE RANGE",
		UDim2.fromOffset(12, 340),
		UDim2.fromOffset(416, 26),

		function()
			action(function()
				local first = selected:GetAttribute("Frame")
				physics.includeFrame(first)
				if
					selected:GetAttribute("ForceType") == "BlackHole"
					or selected:GetAttribute("ForcePath")
				then
					physics.includeFrame(
						first
							+ (selected:GetAttribute("Duration") or 60)
							+ (first == physics.state().first and 1 or 0)
					)
				end
			end)
		end
	)
	buttons.path = Tool.button(
		frame,
		"GreasePencil",
		"ANNOTATE",
		UDim2.fromOffset(12, 376),
		UDim2.fromOffset(202, 26),

		function()
			action(function()
				local part = assert(selected, "Create a force first")
				local pencil = refs.State.GreasePencil
				pencil.close()
				local choices = {}
				local proxy
				for _, force in Scene.get().forces do
					local target = {
						Parent = force.Parent,
						Part0 = force,
						Part1 = force,
						C0 = CFrame.identity,
						C1 = CFrame.identity,
					}
					table.insert(choices, target)
					if force == part then
						proxy = target
					end
				end

				pencil.open(proxy, function(target, points, easing)
					assert(
						not host.closed and target.Part1.Parent,
						"Reopen Forces to apply the path"
					)
					Scene.setForcePath(target.Part1, points, easing)
					selected = target.Part1
					repaint()
				end, {
					targets = choices,
					clear = function(target)
						Scene.clearForcePath(target.Part1)
						repaint()
					end,
				})
			end)
		end
	)
	buttons.clear = Tool.button(
		frame,
		"ClearPath",
		"CLEAR PATH",
		UDim2.fromOffset(226, 376),
		UDim2.fromOffset(202, 26),

		function()
			action(function()
				Scene.clearForcePath(selected)
			end)
		end
	)
	Tool.label(frame, "ListTitle", "FORCES", UDim2.fromOffset(12, 110), UDim2.fromOffset(220, 24))
	buttons.new = Tool.button(
		frame,
		"AddForce",
		"NEW FORCE",
		UDim2.fromOffset(12, 36),
		UDim2.fromOffset(416, 28),

		function()
			action(function()
				selected = Scene.addForce()
				Display.select(selected)
			end)
		end
	)
	local list = Tool.make("ScrollingFrame", frame, "Forces", {
		Position = UDim2.fromOffset(12, 140),
		Size = UDim2.fromOffset(416, 72),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	list:SetAttribute("ThemeBg", "Pnl")
	Tool.make("UIPadding", list, "Padding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	})
	Tool.make(
		"UIListLayout",
		list,
		"Layout",
		{ Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	local run = Tool.button(
		frame,
		"Simulate",
		"SIMULATE",
		UDim2.fromOffset(12, 414),
		UDim2.fromOffset(202, 28),

		function()
			physics.run()
			repaint()
		end
	)
	run:SetAttribute("ThemeBg", "MenuSel")
	local play = Tool.button(
		frame,
		"Play",
		"PLAY",
		UDim2.fromOffset(226, 414),
		UDim2.fromOffset(202, 28),

		function()
			physics.play()
			repaint()
		end
	)
	repaint = function()
		if host.closed then
			return
		end

		if Scene.get() ~= session then
			Forces.close()
			return
		end

		local info = physics.state()
		local editable = not info.busy and not info.playing
		local picked = Selection:Get()[1]
		if picked and table.find(session.forces, picked) then
			selected = picked
		end

		if selected and (not selected.Parent or not table.find(session.forces, selected)) then
			selected = nil
		end

		selected = selected or session.forces[1]
		host.selectedForce = selected
		local nextStamp = tostring(selected) .. tostring(editable)
		for _, part in session.forces do
			nextStamp ..= part.Name .. tostring(part:GetAttribute("Frame")) .. tostring(
				part:GetAttribute("ForceType")
			)
		end

		local changed = not drawnForces or #drawnForces ~= #session.forces
		if not changed then
			for i, part in session.forces do
				if drawnForces[i] ~= part then
					changed = true
					break
				end
			end
		end

		if nextStamp ~= stamp or changed then
			stamp = nextStamp
			drawnForces = table.clone(session.forces)
			for _, child in list:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end

			if #session.forces == 0 then
				Tool.label(list, "Empty", "No forces", UDim2.new(), UDim2.new(1, -8, 0, 24))
			end

			for i, part in session.forces do
				local row = Tool.make(
					"Frame",
					list,
					"Force" .. i,
					{ Size = UDim2.new(1, -4, 0, 27), BackgroundTransparency = 1, LayoutOrder = i }
				)
				local name = part:GetAttribute("ForceType") or "Blast"
				local button, title = Tool.button(
					row,
					"Select",
					part.Name
						.. " / "
						.. (name == "BlackHole" and "Black Hole" or name)
						.. " / "
						.. tostring(part:GetAttribute("Frame")),
					UDim2.new(),
					UDim2.new(1, -76, 1, 0),

					function()
						if editable then
							selected = part
							Display.select(part)
							repaint()
						end
					end
				)
				title.TextWrapped = false
				title.TextTruncate = Enum.TextTruncate.AtEnd
				button:SetAttribute("ThemeBg", part == selected and "MenuSel" or "TopBtn")
				button.Interactable = editable
				local remove = Tool.button(
					row,
					"Remove",
					"REMOVE",
					UDim2.new(1, -70, 0, 0),
					UDim2.fromOffset(70, 27),

					function()
						action(function()
							Scene.removeForce(part)
							Display.refresh()
							if selected == part then
								selected = nil
							end
						end)
					end
				)
				remove.Interactable = editable
			end

			Theme.applyTree(list)
		end

		local black = selected and selected:GetAttribute("ForceType") == "BlackHole"
		local traveling = selected and selected:GetAttribute("ForcePath") ~= nil
		frame.DurationLabel.Text = traveling and "Path frames" or "Frames"
		for name, box in inputs do
			local enabled = selected ~= nil
				and (
					(name ~= "Duration" and name ~= "Spin" and name ~= "Launch")
					or black
					or name == "Duration" and traveling
				)
			if not box:IsFocused() then
				local value = selected and selected:GetAttribute(name)
				box.Text = enabled
						and string
							.format(
								"%.3f",
								value or (name == "Duration" and 60 or name == "Spin" and 1 or 0)
							)
							:gsub("0+$", "")
							:gsub("%.$", "")
					or ""
			end

			box.TextEditable = editable and enabled == true
			box.TextTransparency = enabled and 0 or 0.6
			box.Interactable = box.TextEditable
			box.PlaceholderText = not selected and "Select force"
				or enabled and ""
				or name == "Duration" and "Path / hole"
				or "Black hole"
		end

		for kind, button in kinds do
			button.Interactable = editable and selected ~= nil
			local color = selected
					and (selected:GetAttribute("ForceType") or "Blast") == kind
					and "MenuSel"
				or "TopBtn"
			if button:GetAttribute("ThemeBg") ~= color then
				button:SetAttribute("ThemeBg", color)
				Theme.applyInstance(button)
			end
		end

		for name, button in buttons do
			button.Interactable = editable and (name == "new" or selected ~= nil)
		end

		buttons.clear.Interactable = editable
			and selected ~= nil
			and selected:GetAttribute("ForcePath") ~= nil
		buttons.path.TextLabel.Text = selected
				and selected:GetAttribute("ForcePath")
				and "EDIT FORCE PATH"
			or "DRAW FORCE PATH"
		local first = selected and selected:GetAttribute("Frame")
		local last = first
			and (
				(black or traveling)
					and first + (selected:GetAttribute("Duration") or 60) + (first == info.first and 1 or 0)
				or first
			)
		local outside = first
			and info.first
			and info.last
			and (first < info.first or last > info.last)
		include.Interactable = editable and outside == true
		include.TextLabel.Text = outside
				and "INCLUDE " .. first .. (last ~= first and " - " .. last or "")
			or "INCLUDE FORCE RANGE"
		run.TextLabel.Text = info.busy and "CANCEL"
			or not info.ready and "ADD OBJECTS FIRST"
			or info.preview and "UPDATE SIM"
			or "SIMULATE"
		run.Interactable = info.busy or info.ready == true and not info.playing and not outside
		play.TextLabel.Text = info.playing and "STOP" or "PLAY"
		play.Interactable = not info.busy
			and (info.playing or info.preview == true and not info.dirty)
	end

	local elapsed = 0
	table.insert(
		host.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed > 0.15 then
				elapsed = 0
				repaint()
			end
		end)
	)
	repaint()
	Theme.applyTree(frame)
	task.defer(function()
		if not host.closed then
			local camera = workspace.CurrentCamera
			if camera then
				Forces.place(frame, physics.getFrame(), camera.ViewportSize)
			end
		end
	end)
	return frame
end

function Forces.init(options)
	Forces.close()
	refs = options
end

return Forces
