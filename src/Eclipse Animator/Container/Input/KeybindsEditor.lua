--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local Input = require("UserInputService")
local Notification = require("Notification")
local Chrome = require("Chrome")
local FX = require("WindowFX")
local Theme = require("Theme")
local Editor = {}
local studioNumberKeys = { One = true, Two = true, Three = true, Four = true, Five = true }
local priority = {
	StartBlenderRotate = 1,
	ToggleGizmoMode = 2,
	SetPositionGizmo = 2.1,
	SetRotationGizmo = 2.2,
	ToggleAxisSpace = 3,
	ToggleBlenderGrab = 4,
	ToggleBlenderScale = 5,
	RecordKeyframe = 6,
	RecordAllTracks = 6.1,
	TogglePlayback = 7,
	FocusSelection = 8,
	ToggleGraphEditor = 9,
}
local conventional = {
	Undo = true,
	UndoAlternate = true,
	Redo = true,
	RedoAlternate = true,
	RedoShift = true,
	Copy = true,
	Paste = true,
	SelectAll = true,
	SaveProject = true,
	ConfirmTransform = true,
	ConfirmTransformAlternate = true,
	ConstrainX = true,
	ConstrainY = true,
	Cancel = true,
	PreviousImage = true,
	NextImage = true,
	GraphPreviousFrame = true,
	GraphNextFrame = true,
	GraphFocusAlternate = true,
	GraphDeleteAlternate = true,
}

function Editor.ordered()
	local rows = table.clone(Shortcuts.list())
	local ranks = {}
	for _, row in rows do
		local binding = Shortcuts.get(row.Action)
		ranks[row.Action] = (not binding or not binding.Key) and 300
			or conventional[row.Action] and 200
			or priority[row.Action]
			or 100
	end

	table.sort(rows, function(a, b)
		local x, y = ranks[a.Action], ranks[b.Action]
		if x ~= y then
			return x < y
		end

		return a.Label < b.Label
	end)
	return rows
end

local refs, active = {}, nil

local function make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function outline(object)
	local stroke = make(
		"UIStroke",
		object,
		"Outline",
		{ Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	stroke:SetAttribute("ThemeStrk", "Strk")
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, 3) })
end

local function text(class, parent, name, value, position, size)
	local object = make(class, parent, name, {
		Text = value,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Chrome.FONT,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = parent.ZIndex + 1,
	})
	object:SetAttribute("ThemeTxt", "Txt")
	return object
end

local function button(parent, name, value, position, size)
	local object = text("TextButton", parent, name, value, position, size)
	object.BackgroundTransparency = 0
	object:SetAttribute("ThemeBg", "TopBtn")
	outline(object)
	return object
end

function Editor.init(newRefs)
	refs = newRefs
end

function Editor.close()
	local s = active
	if not s then
		return
	end

	active = nil
	Input.setKeyCapture(nil)
	if s.unsubscribe then
		s.unsubscribe()
	end

	for _, connection in s.connections do
		connection:Disconnect()
	end

	s.window.Active = false
	for _, child in s.window:GetDescendants() do
		if child:IsA("GuiButton") then
			child.Interactable = false
		end
	end

	FX.shrink(s.window, function()
		FX.clear(s.window)
		s.window:Destroy()
	end)
end

function Editor.open()
	if active then
		return active
	end

	local parent = refs.ScreenGui
	if not parent or not parent.Parent then
		return
	end

	local window = make("CanvasGroup", parent, "KeybindsEditor", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 440),
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 110,
	})
	require("Surface").backdrop(window, true)
	local s = { window = window, connections = {}, controls = {}, rows = {} }
	active = s
	local header, _, drag = Chrome.header(window, "KEYBINDS", 111, 288)
	Chrome.close(header, Editor.close, 114)
	Chrome.bindDrag(window, drag, { clamp = true, threshold = 3, disabled = function() return window:GetAttribute("EclipseDocked") == true end })
    require("Tool").attachPopup(window, header, refs, "KeybindsEditor", "KEYBINDS", Vector2.new(520, 300), Editor.close, 274)
	local reset = require("Tool").headerButton(header, "ResetAll", "RESET ALL", 92, 36)
	local legacy = require("Tool").headerButton(header, "Legacy", "LEGACY", 70, 134)
    legacy.Activated:Connect(function()
        Input.setKeyCapture(nil)
        require("Confirm").open(parent, refs.Template or require("UI").RigItemTemplate,
            "LEGACY KEYBINDS", "Apply the legacy keybind preset? Conflicting shortcuts will be replaced.", "Apply", function()
                local ok, issue = Shortcuts.applyLegacy()
                Notification.show(ok and "KEYBINDS UPDATED" or "KEYBINDS NEED ATTENTION", ok and "Legacy keybinds applied." or tostring(issue))
            end)
    end)
	local search =
		text("TextBox", window, "Search", "", UDim2.fromOffset(12, 38), UDim2.new(1, -24, 0, 28))
	search.PlaceholderText = "Search keybinds"
	search.ClearTextOnFocus = false
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.BackgroundTransparency = 0
	search:SetAttribute("ThemeBg", "Pnl")
	outline(search)
	make(
		"UIPadding",
		search,
		"Padding",
		{ PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }
	)
	local scroll = make("ScrollingFrame", window, "Bindings", {
		Position = UDim2.fromOffset(10, 76),
		Size = UDim2.new(1, -20, 1, -84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 112,
	})
	scroll:SetAttribute("ThemeScr", "Scr")
	local status =
		text("TextLabel", window, "Status", "", UDim2.new(0, 12, 1, -37), UDim2.new(1, -124, 0, 34))
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	local resolve =
		button(window, "Replace", "REPLACE", UDim2.new(1, -102, 1, -32), UDim2.fromOffset(90, 25))
	resolve.Visible = false

	local function refreshFooter()
		local visible = status.Text ~= "" or resolve.Visible
		status.Visible = visible
		scroll.Size = UDim2.new(1, -20, 1, visible and -116 or -84)
	end

	table.insert(s.connections, status:GetPropertyChangedSignal("Text"):Connect(refreshFooter))
	table.insert(s.connections, resolve:GetPropertyChangedSignal("Visible"):Connect(refreshFooter))
	refreshFooter()
	local pool, filtered = {}, {}
	local renderRows

	local function refresh()
		local query = string.lower(search.Text)
		table.clear(filtered)
		for _, entry in Editor.ordered() do
			if string.lower(entry.Label .. " " .. entry.Context):find(query, 1, true) then
				table.insert(filtered, entry)
			end
		end

		scroll.CanvasSize = UDim2.fromOffset(0, #filtered * 35 + 4)
		if renderRows then
			renderRows()
		end
	end

	local function finish(id, value, replace)
		if s.saving then
			return
		end

		s.saving = true
		s.capturing = nil
		s.captureId = nil
		if s.captureBox then
			s.captureBox:ReleaseFocus()
		end

		status.Text = "Saving…"
		renderRows()
		local ok, message, conflicts = Shortcuts.set(id, value, replace)
		s.saving = nil
		if active ~= s then
			return
		end

		if
			ok
			and (
				studioNumberKeys[value.Key]
				or type(value.Key) == "string"
					and studioNumberKeys[value.Key:match("^Keypad(.+)$")]
			)
		then
			Notification.show(
				"STUDIO NUMBER KEYBIND",
				"This number shortcut will not work in Eclipse unless you rebind Studio's corresponding number key shortcut first.",
				7
			)
			task.delay(2, function()
				Notification.show(
					"STUDIO NUMBER KEYBIND",
					"please do not report it as a bug, IF YOU DO NOT REBIND STUDIO'S NUMBER KEYBIND IT WILL NOT WORK IN ECLIPSE",
					7
				)
			end)
		end

		if
			ok
			and (id == "SetPositionGizmo" or id == "SetRotationGizmo")
			and (value.Key == "Q" or value.Key == "E")
			and #(value.Modifiers or {}) == 0
			and require("Preferences").get("DisableCameraQE") ~= true
		then
			Notification.show(
				"CAMERA KEY",
				"Q/E also moves the Studio camera. Enable Disable Q/E Movement in Preferences to use it only for the gizmo.",
				7
			)
		end

		if s.captureBox then
			s.captureBox:ReleaseFocus()
		end

		if not ok and conflicts and conflicts[1] then
			const key = Shortcuts.describe(value)
			const owner = Shortcuts.label(conflicts[1])
			message = key .. " is already used by the Eclipse shortcut \"" .. owner .. "\". Press REPLACE to move it here."
			Notification.show(
				"KEYBIND IN USE",
				key
					.. " is assigned to the Eclipse shortcut \""
					.. owner
					.. "\" (Keybinds window, not Studio). Press REPLACE to use it for \""
					.. Shortcuts.label(id)
					.. "\" and unbind \""
					.. owner
					.. "\".",
				8
			)
		elseif not ok then
			Notification.show("KEYBIND", message, 4)
		end

		status.Text = ok and "" or message
		s.pending = conflicts and { id = id, value = value } or nil
		s.capturing = nil
		s.captureId = nil
		resolve.Text = "REPLACE"
		resolve.Visible = s.pending ~= nil
		refresh()
	end

	s.captureBox = make("TextBox", window, "ShortcutCapture", {
		Text = "",
		TextTransparency = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1, 1),
		ClearTextOnFocus = true,
		Position = UDim2.fromOffset(0, 0),
		ZIndex = 120,
	})

	local function capture(id)
		if s.saving then
			return
		end

		search:ReleaseFocus()
		Input.setKeyCapture(nil)
		refresh()
		s.pending = nil
		resolve.Visible = false
		s.captureId = id
		s.capturing = true
		renderRows()
		status.Text = Shortcuts.label(id)
		resolve.Visible = true
		resolve.Text = "CANCEL"
		Input.setKeyCapture(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				task.defer(function()
					if active == s then
						Input.setKeyCapture(nil)
						s.captureBox:ReleaseFocus()
						s.capturing = nil
						s.captureId = nil
						resolve.Visible = false
						status.Text = ""
						refresh()
					end
				end)
				return
			end

			local value = Shortcuts.chord(input)
			if not value then
				return
			end

			Input.setKeyCapture(nil)
			if not s.capturing then
				return
			end

			s.capturing = nil
			task.defer(function()
				if active == s then
					Input.setKeyCapture(nil)
					finish(id, value, false)
				end
			end)
		end)
		s.captureBox:CaptureFocus()
	end

	local function newRow()
		local slot = {}
		local row = make(
			"Frame",
			scroll,
			"BindingRow",
			{ Size = UDim2.new(1, -8, 0, 32), BackgroundTransparency = 0.65, ZIndex = 113 }
		)
		row:SetAttribute("ThemeBg", "Pnl")
		slot.row = row
		slot.title =
			text("TextLabel", row, "Title", "", UDim2.fromOffset(8, 0), UDim2.new(1, -200, 1, 0))
		slot.title.TextXAlignment = Enum.TextXAlignment.Left
		slot.title.TextTruncate = Enum.TextTruncate.AtEnd
		local control =
			button(row, "Binding", "", UDim2.new(1, -178, 0, 3), UDim2.fromOffset(114, 26))
		slot.control = control
		control.TextScaled = true
		make("UITextSizeConstraint", control, "TextSize", { MinTextSize = 5, MaxTextSize = 12 })
		control.Activated:Connect(function()
			if slot.entry then
				capture(slot.entry.Action)
			end
		end)
		local clear = button(row, "Clear", "×", UDim2.new(1, -58, 0, 3), UDim2.fromOffset(24, 26))
		clear.Activated:Connect(function()
			if slot.entry then
				Input.setKeyCapture(nil)
				finish(slot.entry.Action, { Key = false }, false)
			end
		end)
		local restore = make("ImageButton", row, "Reset", {
			Image = "rbxassetid://110138249483014",
			ImageColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -28, 0, 7),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = row.ZIndex + 1,
		})
		restore:SetAttribute("ThemeImg", "Txt")
		restore.Activated:Connect(function()
			if slot.entry then
				Input.setKeyCapture(nil)
				finish(slot.entry.Action, slot.entry, false)
			end
		end)
		Theme.applyTree(row)
		return slot
	end

	renderRows = function()
		if active ~= s then
			return
		end

		table.clear(s.rows)
		table.clear(s.controls)
		local height = scroll.AbsoluteWindowSize.Y
		if height <= 0 then
			height = 356
		end

		local count = math.min(#filtered, math.ceil(height / 35) + 2)
		local first = math.clamp(
			math.floor(scroll.CanvasPosition.Y / 35) + 1,
			1,
			math.max(1, #filtered - count + 1)
		)
		for index = 1, count do
			local slot = pool[index]
			if not slot then
				slot = newRow()
				pool[index] = slot
			end

			local entry = filtered[first + index - 1]
			slot.entry = entry
			slot.row.Name = entry.Action
			slot.row.Position = UDim2.fromOffset(2, 2 + (first + index - 2) * 35)
			slot.row.Visible = true
			slot.title.Text = entry.Label
			slot.control.Text = s.captureId == entry.Action and "Press a key…"
				or Shortcuts.format(entry.Action)
			s.rows[entry.Action] = slot.row
			s.controls[entry.Action] = slot.control
		end

		for index = count + 1, #pool do
			pool[index].entry = nil
			pool[index].row.Visible = false
		end
	end

	table.insert(
		s.connections,
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(renderRows)
	)
	table.insert(
		s.connections,
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(renderRows)
	)
	table.insert(
		s.connections,
		search:GetPropertyChangedSignal("Text"):Connect(function()
			scroll.CanvasPosition = Vector2.zero
			refresh()
		end)
	)
	resolve.Activated:Connect(function()
		if s.capturing then
			Input.setKeyCapture(nil)
			s.captureBox:ReleaseFocus()
			s.capturing = nil
			s.captureId = nil
			resolve.Visible = false
			status.Text = ""
			refresh()
			return
		end

		local pending = s.pending
		if pending then
			finish(pending.id, pending.value, true)
		end
	end)
	reset.Activated:Connect(function()
		Input.setKeyCapture(nil)
		s.capturing = nil
		s.captureId = nil
		if Shortcuts.resetAll() then
			status.Text = ""
		else
			status.Text = "Could not save keybinds."
		end

		resolve.Visible = false
		s.pending = nil
		refresh()
	end)
	s.unsubscribe = Shortcuts.subscribe(refresh)
	table.insert(
		s.connections,
		Input.InputBegan:Connect(function(input)
			if Shortcuts.matches("Cancel", input) and not search:IsFocused() then
				Editor.close()
			end
		end)
	)
	window.Destroying:Once(function()
		if active == s then
			active = nil
			Input.setKeyCapture(nil)
			if s.unsubscribe then
				s.unsubscribe()
			end

			for _, c in s.connections do
				c:Disconnect()
			end
		end
	end)
	refresh()
	Theme.applyTree(window)
	task.defer(function()
		if active == s then
			FX.pop(window)
		end
	end)
	return s
end

return Editor
