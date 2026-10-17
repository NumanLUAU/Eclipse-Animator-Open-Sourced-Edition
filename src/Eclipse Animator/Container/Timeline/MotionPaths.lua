--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Preferences = require("Preferences")
local Editor = require("PreferencesEditor")
local Window = {}
local refs, host
local connections = {}

function Window.close(immediate)
	if host then
		local old = host
		host = nil
		old:close(immediate)
	end
end

function Window.destroy()
	Window.close(true)
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
end

local function selected()
	local result = {}
	local rig = refs and refs.State.Rig
	for item, chosen in rig and rig._selectedItems or {} do
		if
			chosen
			and item.motionPathButton
			and item.uiElement
			and item.uiElement.Parent
			and item.itemKind ~= "origin"
			and item.itemKind ~= "camerafov"
		then
			table.insert(result, item)
		end
	end

	return result
end

function Window.open()
	if host or not refs or not refs.Active() then
		return
	end

	local session
	session = Tool.new(refs, "EclipseMotionPaths", "MOTION PATHS", Vector2.new(340, 184), false, function()
		if host == session then
			host = nil
		end
	end, { AnimateClose = true })
	host = session
	local frame = session.frame
	if frame:FindFirstChild("Header") then
		frame.Header.Title.Size = UDim2.new(1, -118, 1, 0)
		frame.Header.WindowDrag.Size = frame.Header.Title.Size
	end

	local function alive()
		return host == session and not session.closed and refs.Active()
	end

	local controls = {}
	Tool.button(frame, "Settings", "SETTINGS", UDim2.fromOffset(234, 4), UDim2.fromOffset(72, 22), function()
		if not alive() then
			return
		end

		Window.close()
		Editor.openMotionPathPreferences()
	end
)

	local function pathAction(enabled)
		if not alive() then
			return
		end

		local items = selected()
		if enabled and #items > 0 then
			Preferences.set("ShowMotionPaths", true)
		end

		for _, item in items do
			item:setMotionPath(enabled, item.trackIsMaster)
		end
	end

	local show = Tool.button(
		frame,
		"ShowSelected",
		"SHOW SELECTED",
		UDim2.fromOffset(12, 38),
		UDim2.fromOffset(154, 26),

		function()
			pathAction(true)
		end
	)
	local hide = Tool.button(
		frame,
		"HideSelected",
		"HIDE SELECTED",
		UDim2.fromOffset(174, 38),
		UDim2.fromOffset(154, 26),

		function()
			pathAction(false)
		end
	)

	local function choices(key, title, names, y)
		local row = Tool.make("Frame", frame, key, {
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.fromOffset(316, 26),
			BackgroundTransparency = 1,
		})
		Tool.label(row, "Label", title, UDim2.new(), UDim2.fromOffset(78, 26))
		local buttons = {}
		local step = 240 / #names
		for i, name in names do
			local button, label = Tool.button(
				row,
				tostring(i),
				name,
				UDim2.fromOffset(80 + (i - 1) * step, 0),
				UDim2.fromOffset(step - 4, 26),

				function()
					if alive() then
						Preferences.set(key, i)
					end
				end
			)
			buttons[i] = { button = button, label = label }
		end

		controls[key] = { row = row, buttons = buttons }
		return row
	end

	choices("MotionPathRange", "Range", { "Full", "Keys", "Frames", "Custom" }, 72)
	local countRow = Tool.make("Frame", frame, "EachSide", {
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.fromOffset(316, 26),
		BackgroundTransparency = 1,
	})
	local countLabel =
		Tool.label(countRow, "Label", "Keys each side", UDim2.new(), UDim2.fromOffset(226, 26))
	local count = Tool.field(
		countRow,
		"RangeCount",
		Preferences.get("MotionPathEachSide"),
		UDim2.fromOffset(236, 0),
		UDim2.fromOffset(80, 26)
	)
	count.ClearTextOnFocus = false
	local customRow = Tool.make("Frame", frame, "CustomRange", {
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.fromOffset(316, 26),
		BackgroundTransparency = 1,
	})
	local bounds = {}
	for i, info in { { "MotionPathStart", "Start" }, { "MotionPathEnd", "End" } } do
		local x = (i - 1) * 160
		Tool.label(
			customRow,
			info[1] .. "Label",
			info[2],
			UDim2.fromOffset(x, 0),
			UDim2.fromOffset(54, 26)
		)
		local input = Tool.field(
			customRow,
			info[1],
			Preferences.get(info[1]),
			UDim2.fromOffset(x + 56, 0),
			UDim2.fromOffset(100, 26)
		)
		input.ClearTextOnFocus = false
		bounds[info[1]] = input
	end

	local numbers = choices("MotionPathNumbers", "Numbers", { "Auto", "On", "Off" }, 106)
	local edit = Tool.make("TextButton", frame, "EditPoints", {
		Position = UDim2.fromOffset(12, 140),
		Size = UDim2.fromOffset(316, 26),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})
	Tool.label(
		edit,
		"Label",
		"Click path points",
		UDim2.fromOffset(26, 0),
		UDim2.fromOffset(286, 26)
	)
	local box = Tool.make(
		"Frame",
		edit,
		"Box",
		{ Position = UDim2.fromOffset(0, 5), Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0 }
	)
	box:SetAttribute("ThemeBg", "TopBtn")
	Tool.make("UIStroke", box, "Outline", { Thickness = 1 }):SetAttribute("ThemeStrk", "Strk")
	local mark = Tool.make(
		"Frame",
		box,
		"Mark",
		{ Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(8, 8), BorderSizePixel = 0 }
	)
	mark:SetAttribute("ThemeBg", "Txt")

	local function refresh()
		if not alive() then
			return
		end

		local mode = Preferences.get("MotionPathRange")
		local nearby = mode ~= 1
		countRow.Visible = mode == 2 or mode == 3
		customRow.Visible = mode == 4
		countLabel.Text = mode == 3 and "Frames each side" or "Keys each side"
		if not count:IsFocused() then
			count.Text = tostring(Preferences.get("MotionPathEachSide"))
		end

		for key, input in bounds do
			if not input:IsFocused() then
				input.Text = tostring(Preferences.get(key))
			end
		end

		local offset = nearby and 34 or 0
		numbers.Position = UDim2.fromOffset(12, 106 + offset)
		edit.Position = UDim2.fromOffset(12, 140 + offset)
		frame.Size = UDim2.fromOffset(340, 184 + offset)
		mark.Visible = Preferences.get("MotionPathEditing") == true
		for key, group in controls do
			for value, entry in group.buttons do
				local active = Preferences.get(key) == value
				entry.button:SetAttribute("ThemeBg", active and "Sel" or "TopBtn")
				entry.label.TextTransparency = active and 0 or 0.25
				require("Theme").applyInstance(entry.button)
			end
		end
	end

	table.insert(
		session.connections,
		count.FocusLost:Connect(function()
			if not alive() then
				return
			end

			local value = tonumber(count.Text)
			if value and value == value and math.abs(value) < math.huge then
				Preferences.set("MotionPathEachSide", math.clamp(math.floor(value + 0.5), 1, 1000))
			end

			count.Text = tostring(Preferences.get("MotionPathEachSide"))
			refresh()
		end)
	)
	for key, input in bounds do
		table.insert(
			session.connections,
			input.FocusLost:Connect(function()
				if not alive() then
					return
				end

				Preferences.set(key, input.Text)
				input.Text = tostring(Preferences.get(key))
				refresh()
			end)
		)
	end

	table.insert(
		session.connections,
		edit.Activated:Connect(function()
			if alive() then
				Preferences.set("MotionPathEditing", not Preferences.get("MotionPathEditing"))
			end
		end)
	)
	local unsubscribe = Preferences.subscribe(function(key)
		if
			key == "MotionPathRange"
			or key == "MotionPathEachSide"
			or key == "MotionPathStart"
			or key == "MotionPathEnd"
			or key == "MotionPathNumbers"
			or key == "MotionPathEditing"
		then
			refresh()
		end
	end)
	table.insert(session.connections, { Disconnect = unsubscribe })
	local elapsed = 0.2
	table.insert(
		session.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.15 then
				return
			end

			elapsed = 0
			if not alive() then
				Window.close()
				return
			end

			local canSelect = #selected() > 0
			show.Interactable = canSelect
			hide.Interactable = canSelect
			show.TextLabel.TextTransparency = canSelect and 0.1 or 0.6
			hide.TextLabel.TextTransparency = canSelect and 0.1 or 0.6
		end)
	)
	show.Interactable = #selected() > 0
	hide.Interactable = show.Interactable
	refresh()
end

function Window.toggle()
	if host then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(options)
	Window.destroy()
	refs = options
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Window.close(true)
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Window.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Window.destroy))
end

return Window
