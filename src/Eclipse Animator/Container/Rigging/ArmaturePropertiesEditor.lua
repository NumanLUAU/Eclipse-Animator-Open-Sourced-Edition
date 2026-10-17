--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local WindowMotion = require("Motion")
local Shortcuts = require("Shortcuts")
local Theme = require("Theme")
local Surface = require("Surface")
local Runtime = require("ArmatureRuntime")
local Animation = require("ArmatureAnimation")
local History = require("History")
local RunService = game:GetService("RunService")
local Notification = require("Notification")
local WindowFX = require("WindowFX")
local Chrome = require("Chrome")
local UserInputService = game:GetService("UserInputService")

local Editor = {}
local WIDTH, HEIGHT = 420, 440

local refs = {}
local active
local sessions = {}

local function make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function tag(object, attribute, key)
	object:SetAttribute(attribute, key)
	return object
end

local function round(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius) })
end

local function outline(object, transparency)
	return tag(
		make("UIStroke", object, "Outline", {
			Color = Color3.fromRGB(87, 59, 106),
			Thickness = 1,
			Transparency = transparency or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		"ThemeStrk",
		"Strk"
	)
end

local function connect(session, signal, callback)
	local connection = signal:Connect(callback)
	table.insert(session.connections, connection)
	return connection
end

local function disconnect(session)
	for _, connection in session.connections do
		connection:Disconnect()
	end

	table.clear(session.connections)
	for _, cleanup in session.tipCleanups do
		cleanup()
	end

	table.clear(session.tipCleanups)
	if session.unsubscribe then
		session.unsubscribe()
		session.unsubscribe = nil
	end
end

local function scaleOf(session)
	local animationScale = session.window:FindFirstChild("EclipseWindowScale")
	local scale = session.window.AbsoluteSize.X
		/ (WIDTH * (animationScale and animationScale.Scale or 1))
	return scale > 0 and scale or 1
end

local function restingPosition(session)
	local window = session.window
	local animationScale = window:FindFirstChild("EclipseWindowScale")
	local scale = animationScale and animationScale.Scale or 1
	return window.AbsolutePosition + window.AbsoluteSize * (0.5 - 0.5 / scale)
end

local function place(session, point)
	local window = session.window
	local parent = window.Parent
	if not parent then
		return
	end

	local scale = scaleOf(session)
	local origin, viewport = parent.AbsolutePosition, parent.AbsoluteSize
	local desired = UDim2.fromOffset(
		(point.X - origin.X) / scale + WIDTH * 0.5,
		(point.Y - origin.Y) / scale + HEIGHT * 0.5
	)
	window.Position = WindowMotion.reachable(
		desired,
		Vector2.new(WIDTH, HEIGHT),
		viewport / scale,
		Vector2.new(0.5, 0.5),
		scale
	)
end

local function hideTip(session)
	if not session.hoverDialog then
		return
	end

	for _, tip in session.tips do
		session.hoverDialog:disappear(tip.button)
	end
end

local function dispose(session, destroyWindow)
	if session.disposed then
		return
	end

	session.disposed = true
	session.closing = true
	hideTip(session)
	disconnect(session)
	WindowFX.clear(session.window)
	sessions[session] = nil
	if active == session then
		active = nil
	end

	if destroyWindow then
		session.window:Destroy()
	end
end

local function bindDrag(session, handle)
	WindowMotion.resetOnOpen(session.window)
	local drag
	connect(session, handle.InputBegan, function(input)
		if session.closing or drag then
			return
		end

		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		hideTip(session)
		drag = {
			input = input,
			start = Vector2.new(input.Position.X, input.Position.Y),
			origin = restingPosition(session),
		}
	end)
	connect(session, UserInputService.InputChanged, function(input)
		if not drag or session.closing then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= drag.input then
			return
		end

		local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.start
		if delta.Magnitude >= 3 then
			place(session, drag.origin + delta)
		end
	end)
	connect(session, UserInputService.InputEnded, function(input)
		if
			drag
			and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1)
		then
			drag = nil
		end
	end)
	connect(session, session.window.Parent:GetPropertyChangedSignal("AbsoluteSize"), function()
		if not session.closing then
			hideTip(session)
			place(session, restingPosition(session))
		end
	end)
end

local function bindTip(session, button, text)
	local tooltip = session.hoverDialog
	if not tooltip then
		return
	end

	local options = { maxWidth = 320 }
	table.insert(session.tipCleanups, tooltip:latchToInstance(button, text, options))

	local function show()
		if session.closing or not button.Parent then
			return
		end

		tooltip:popup(text, button, options)
	end

	if not button:IsA("GuiButton") then
		return
	end

	connect(session, button.SelectionGained, show)
	connect(session, button.SelectionLost, function()
		tooltip:disappear(button)
	end)
	connect(session, button.Activated, function()
		if tooltip.open and tooltip.causedElement == button then
			tooltip:disappear(button)
		else
			show()
		end
	end)
end

function Editor.init(newRefs)
	if refs.ScreenGui ~= newRefs.ScreenGui then
		Editor.destroy()
	end

	refs = newRefs
end

function Editor.open()
	local rig = refs.GetRig and refs.GetRig()
	if not rig or not Runtime.isRig(rig) then
		Notification.show("ARMATURE CONTROLS", "Select a rig with an imported Blender armature.")
		return
	end

	if active and not active.closing and active.rig == rig and active.window.Parent then
		return active
	end

	if active and active.rig ~= rig then
		Editor.close()
	end

	local OPTIONS, values = {}, {}
	local valueRevision = -1
	local keyFrame, keyRevision, keyArm, keyed

	local function keyedAtFrame()
		local frame = refs.GetFrame()
		local revision, arm = Animation.propertyRevision(rig)
		if frame ~= keyFrame or revision ~= keyRevision or arm ~= keyArm then
			keyFrame, keyRevision, keyArm = frame, revision, arm
			keyed = Animation.keyedProperties(rig, frame)
		end

		return keyed
	end

	local function collect()
		local revision = Runtime.propertyRevision(rig)
		if valueRevision == revision then
			return false
		end

		valueRevision = revision
		for _, property in Runtime.properties(rig) do
			local key = game:GetService("HttpService")
				:JSONEncode({ property.object, property.bone or "", property.key })
			values[key] = property
		end

		return true
	end

	collect()
	for key, property in values do
		table.insert(OPTIONS, {
			key = key,
			label = property.key,
			owner = property.bone or property.object,
			numeric = typeof(property.value) == "number",
		})
	end

	table.sort(OPTIONS, function(a, b)
		return a.owner .. a.label < b.owner .. b.label
	end)
	local Preferences = {}

	function Preferences.get(key)
		return values[key].value
	end

	function Preferences.set(key, value)
		local property = values[key]
		local before = property.value
		if before == value then
			return
		end

		local function apply(v)
			if not rig.Parent then
				return
			end

			Runtime.setProperty(rig, property.object, property.key, v, property.bone)
			Runtime.evaluate(rig)
			property.value = v
		end

		apply(value)
		History.record(function()
			apply(before)
		end, function()
			apply(value)
		end, "Change " .. property.key)
	end

	if active and not active.closing then
		if active.window.Parent then
			return active
		end

		dispose(active, false)
	end

	local parent = refs.ScreenGui
	if not parent or not parent.Parent then
		return
	end

	local titleTemplate = refs.RigItemTemplate
		and refs.RigItemTemplate:FindFirstChild("Title", true)
	local fontFace = titleTemplate and titleTemplate.FontFace
		or Font.new("rbxasset://fonts/families/RobotoMono.json")
	local window = tag(
		make("CanvasGroup", nil, "ArmaturePropertiesEditor", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(WIDTH, HEIGHT),
			BackgroundColor3 = Color3.fromRGB(22, 16, 28),
			BorderSizePixel = 0,
			Active = true,
			Visible = false,
			ZIndex = 100,
		}),
		"ThemeBg",
		"Bg"
	)
	round(window, 6)
	Surface.backdrop(window, false)
	outline(window)
	local session = {
		rig = rig,
		window = window,
		connections = {},
		controls = {},
		flushers = {},
		keyRefreshers = {},
		tips = {},
		tipCleanups = {},
		hoverDialog = refs.HoverDialog,
	}

	function session.flush()
		if session.closing then
			return
		end

		for _, flush in session.flushers do
			flush()
		end
	end

	active = session
	sessions[session] = true
	window.Destroying:Once(function()
		dispose(session, false)
	end)

	local function label(parentObject, name, text, position, size)
		return tag(
			make("TextLabel", parentObject, name, {
				Text = text,
				Position = position,
				Size = size,
				BackgroundTransparency = 1,
				FontFace = fontFace,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(230, 223, 238),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 103,
			}),
			"ThemeTxt",
			"Txt"
		)
	end

	local header, title, dragHandle = Chrome.header(window, "ARMATURE CONTROLS", 101)
	local close = Chrome.close(header, nil, 105)
	local body = tag(
		make("Frame", window, "Body", {
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.new(1, -20, 1, -48),
			BackgroundColor3 = Color3.fromRGB(15, 12, 19),
			BorderSizePixel = 0,
			ZIndex = 101,
		}),
		"ThemeBg",
		"Pnl"
	)
	round(body, 5)
	outline(body, 0.35)
	local scroll = tag(
		make("ScrollingFrame", body, "Options", {
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarImageColor3 = Color3.fromRGB(111, 78, 130),
			ZIndex = 102,
		}),
		"ThemeScr",
		"Scr"
	)
	make(
		"UIListLayout",
		scroll,
		"Layout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	make("UIPadding", scroll, "Padding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	})

	local function refresh(key)
		local control = session.controls[key]
		if not control or session.closing then
			return
		end

		if control:IsA("TextBox") then
			local text = tostring(Preferences.get(key))
			if control.Text ~= text then
				control.Text = text
			end
		else
			local visible = Preferences.get(key) == true
			if control.Mark.Visible ~= visible then
				control.Mark.Visible = visible
			end
		end
	end

	for index, option in OPTIONS do
		local row = make("Frame", scroll, option.key, {
			Size = UDim2.new(1, 0, 0, 46),
			LayoutOrder = index,
			BackgroundTransparency = 1,
			ZIndex = 102,
		})
		local ownerLabel =
			label(row, "Owner", option.owner, UDim2.fromOffset(7, 2), UDim2.new(1, -148, 0, 17))
		ownerLabel.TextSize = 11
		ownerLabel.TextTransparency = 0.3
		local propertyLabel =
			label(row, "Label", option.label, UDim2.fromOffset(7, 19), UDim2.new(1, -148, 0, 23))
		propertyLabel.TextTruncate = Enum.TextTruncate.AtEnd
		bindTip(session, row, option.owner .. " · " .. option.label)
		local keyButton = tag(
			make("TextButton", row, "Key", {
				Position = UDim2.new(1, -32, 0.5, -12),
				Size = UDim2.fromOffset(24, 24),
				Text = "◇",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				FontFace = fontFace,
				TextSize = 20,
				TextColor3 = Color3.fromRGB(230, 223, 238),
				ZIndex = 104,
			}),
			"ThemeTxt",
			"Txt"
		)
		bindTip(
			session,
			keyButton,
			"Click to save this value at the playhead. Click again to remove the keyframe."
		)

		local function refreshKey()
			local found = keyedAtFrame()[option.key] == true
			local text = found and "◆" or "◇"
			if keyButton.Text ~= text then
				keyButton.Text = text
			end

			return found
		end

		connect(session, keyButton.Activated, function()
			session.flush()
			local before = Animation.propertySnapshot(rig)
			local frame = refs.GetFrame()
			Animation.keyProperty(
				rig,
				values[option.key],
				frame,
				Preferences.get(option.key),
				refreshKey()
			)
			local after = Animation.propertySnapshot(rig)

			local function restore(snapshot)
				Animation.restoreProperties(rig, snapshot)
				Animation.applyProperties(rig, frame)
				Runtime.evaluate(rig)
				refreshKey()
			end

			History.record(function()
				restore(before)
			end, function()
				restore(after)
			end, "Key " .. option.label, frame)
			refreshKey()
		end)
		table.insert(session.keyRefreshers, refreshKey)
		refreshKey()
		if option.numeric then
			local shell = tag(
				make("Frame", row, "Input", {
					Position = UDim2.new(1, -119, 0.5, -14),
					Size = UDim2.fromOffset(74, 28),
					BackgroundColor3 = Color3.fromRGB(22, 16, 28),
					BorderSizePixel = 0,
					ZIndex = 103,
				}),
				"ThemeBg",
				"Bg"
			)
			round(shell, 4)
			outline(shell)
			local box = tag(
				make("TextBox", shell, "Value", {
					Position = UDim2.fromOffset(5, 2),
					Size = UDim2.new(1, -10, 1, -4),
					Text = "",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					FontFace = fontFace,
					TextSize = 14,
					TextColor3 = Color3.fromRGB(230, 223, 238),
					ClearTextOnFocus = false,
					ZIndex = 104,
				}),
				"ThemeTxt",
				"Txt"
			)
			session.controls[option.key] = box
			local draft
			connect(session, box.Focused, function()
				draft = box.Text
			end)

			local function flush()
				if session.closing or draft == nil then
					return
				end

				local changed = box.Text ~= draft
				draft = nil
				local value = changed and tonumber(box.Text) or nil
				if value and value == value and math.abs(value) < math.huge then
					Preferences.set(option.key, value)
				end

				refresh(option.key)
			end

			table.insert(session.flushers, flush)
			require("NumericInput").bind(
				box,
				{ step = option.unit == "%" and 1 or option.integer and 1 or 0.1 }
			)
			connect(session, box.FocusLost, flush)
		else
			local toggle = tag(
				make("TextButton", row, "Toggle", {
					Position = UDim2.new(1, -69, 0.5, -12),
					Size = UDim2.fromOffset(24, 24),
					Text = "",
					BackgroundColor3 = Color3.fromRGB(45, 27, 56),
					BorderSizePixel = 0,
					AutoButtonColor = true,
					ZIndex = 103,
				}),
				"ThemeBg",
				"TopBtn"
			)
			round(toggle, 4)
			outline(toggle, 0.35)
			local mark = label(toggle, "Mark", "✓", UDim2.new(), UDim2.fromScale(1, 1))
			mark.TextSize = 18
			mark.TextXAlignment = Enum.TextXAlignment.Center
			mark.ZIndex = 104
			session.controls[option.key] = toggle
			connect(session, toggle.Activated, function()
				if session.closing then
					return
				end

				Preferences.set(option.key, Preferences.get(option.key) ~= true)
				refresh(option.key)
			end)
		end

		if option.tip then
			local info = tag(
				make("TextButton", row, "Info", {
					Position = UDim2.new(1, -58, 0.5, -9),
					Size = UDim2.fromOffset(18, 18),
					Text = "i",
					FontFace = fontFace,
					TextSize = 13,
					TextColor3 = Color3.fromRGB(230, 223, 238),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 104,
				}),
				"ThemeTxt",
				"Txt"
			)
			round(info, 9)
			outline(info, 0.35)
			table.insert(session.tips, { button = info, text = option.tip })
		end

		refresh(option.key)
	end

	local nextRefresh = 0
	connect(session, RunService.Heartbeat, function()
		if os.clock() < nextRefresh or session.closing then
			return
		end

		nextRefresh = os.clock() + 0.15
		if not rig.Parent then
			Editor.close()
			return
		end

		if collect() then
			for _, option in OPTIONS do
				local control = session.controls[option.key]
				if not control:IsA("TextBox") or not control:IsFocused() then
					refresh(option.key)
				end
			end
		end

		local previous = keyed
		if keyedAtFrame() ~= previous then
			for _, update in session.keyRefreshers do
				update()
			end
		end
	end)
	connect(session, close.Activated, Editor.close)
	connect(session, scroll:GetPropertyChangedSignal("CanvasPosition"), function()
		hideTip(session)
	end)
	connect(session, UserInputService.InputBegan, function(input)
		if Shortcuts.matches("Cancel", input) then
			Editor.close()
		end
	end)
	window.Parent = parent
	bindDrag(session, dragHandle)
	for _, tip in session.tips do
		bindTip(session, tip.button, tip.text)
	end

	Theme.applyTree(window)
	task.defer(function()
		if session.closing or not window.Parent then
			return
		end

		place(session, restingPosition(session))
		window.Visible = true
		WindowFX.pop(window)
	end)
	return session
end

function Editor.close()
	local session = active
	if not session or session.closing then
		return
	end

	session.flush()
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(session.window) then
		focused:ReleaseFocus()
	end

	session.closing = true
	active = nil
	hideTip(session)
	disconnect(session)
	for _, object in session.window:GetDescendants() do
		if object:IsA("GuiButton") then
			object.Interactable = false
		end

		if object:IsA("TextBox") then
			object.TextEditable = false
		end
	end

	WindowFX.shrink(session.window, function()
		dispose(session, true)
	end)
end

function Editor.destroy()
	local pending = {}
	for session in sessions do
		table.insert(pending, session)
	end

	for _, session in pending do
		if not session.closing and session.flush then
			session.flush()
		end

		dispose(session, true)
	end

	active = nil
end

return Editor
