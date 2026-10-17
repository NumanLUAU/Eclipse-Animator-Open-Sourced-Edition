--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Chrome = require("Chrome")
local FX = require("WindowFX")
local Theme = require("Theme")
local Physics = require("Physics")

local function physicalClips()
	local result = {}
	for _, clip in Physics.list() do
		if clip.settings.kind ~= "SmartBone" and clip.settings.kind ~= "BoneDynamics" then
			table.insert(result, clip)
		end
	end

	return result
end

local RunService = game:GetService("RunService")
local Scene = require("Scene")
local Forces = require("Forces")
local Preferences = require("Preferences")
local Notice = require("Notification")
local Window = {}

local function notify(message)
	Notice.show("PHYSICS", message)
end

const STILL_REASONS = {
	removed = "Nothing moved: the physics parts were deleted while simulating. Another plugin or script may be removing new parts, or the start pose is below FallenPartsDestroyHeight.",
	hold = 'Nothing moved: "Stay still until hit" is on and no blast reached the parts. Turn it off or add a blast.',
	gravity = "Nothing moved: Gravity is 0 and nothing pushed the parts. Raise Gravity or add a push.",
	objects = "Nothing moved: Objects mode drops the parts as loose objects and they were already resting. For a ragdoll, switch to Ragdoll, then simulate again.",
	limbs = "Nothing moved: none of the added parts are rig limbs joined by Motor6Ds, so they fell as loose objects and were already resting. Add a push or a blast to move them.",
	anchored = "Nothing moved: another plugin or script kept anchoring the physics parts while simulating. Turn it off, then simulate again.",
	frozen = "Nothing moved: Roblox physics did not start moving the parts within 3 seconds. Close plugins that anchor or move new parts, then simulate again.",
	resting = "Nothing moved: every part started at rest on a surface and nothing pushed it. Add a push (X, Y or Z) or a blast to knock it over.",
}

local refs, window, warning, controls
local revision = 0
local connections = {}

local function numberText(value)
	if typeof(value) ~= "number" then
		return tostring(value)
	end

	return (string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", ""))
end

function Window.matchesNumber(text, value, vector)
	local number = tonumber(text)
	if not number or number ~= number or math.abs(number) == math.huge or type(value) ~= "number" then
		return false
	end
	return number == value
		or number == tonumber(numberText(value))
		or vector == true and Vector3.new(number, 0, 0).X == value
end

local function errorText(err)
	local full = tostring(err)
	if full:find("simulation canceled because playback started", 1, true) then
		return "Playback started. Pause it, then simulate again."
	end

	if full:find("simulation canceled", 1, true) then
		return "Canceled. Your animation hasn't changed."
	end

	local message = full:match("^[^\r\n]+") or "Couldn't simulate. Try again."
	while true do
		local stripped, count = message:gsub("^.-:%d+:%s*", "", 1)
		if count == 0 then
			break
		end

		message = stripped
	end

	if #message > 400 then
		return "Couldn't simulate. Check the selected rig and try again."
	end

	return message
end

function Window.isOpen()
	return window ~= nil or warning ~= nil
end

function Window.getFrame()
	return window and window.frame
end

function Window.isEditorOpen()
	return window ~= nil
end

function Window.close(immediate)
	controls = nil
	if warning then
		local old = warning
		warning = nil
		old:close(immediate)
	end

	if refs then
		refs.State.PhysicsSimulating = false
		Physics.preview(false)
	end

	Forces.close()
	if refs and refs.State.GreasePencil and refs.State.GreasePencil.closePhysics then
		refs.State.GreasePencil.closePhysics()
	end

	revision += 1
	if window then
		local old = window
		window = nil
		old:close(immediate)
	end

	require("SceneSync").hide()
end

function Window.destroy()
	require("SceneSync").destroy()
	Window.close(true)
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

function Window.state()
	return controls and controls.state() or {}
end

function Window.run()
	if not refs or not refs.Active() then
		return false
	end

	if refs and refs.State.Timeline:IsExportLocked() then
		return false
	end

	if not controls then
		Window.open()
	end

	if not controls then
		return false
	end

	require("SceneSync").finish(false)
	controls.run()
	return true
end

function Window.includeFrame(frame)
	if controls then
		controls.includeFrame(frame)
	end
end

function Window.jump(frame)
	if refs and refs.State.Timeline:IsExportLocked() then
		return
	end

	if not refs or refs.State.PhysicsSimulating then
		return
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	raw.Playing = false
	timeline:EnsureTimelineEnd(frame)
	raw.CurrentTime = frame / raw.FPS
	timeline:UpdatePlayhead()
	if refs.State.currentRig then
		timeline:ApplyPoseAtTime(refs.State.currentRig, raw.CurrentTime)
	end
end

function Window.play()
	if not refs or not refs.Active() then
		return false
	end

	if controls then
		controls.play()
	end
end

function Window.open()
	if window then
		return window.frame
	end

	if not refs or not refs.Active() then
		return
	end

	if Preferences.get("PhysicsAcknowledged") ~= true then
		if warning then
			return warning.frame
		end

		local message =
			"<b>!! VERY experimental</b>\n\nPhysics is still pretty rough, and some of the settings get advanced. Save your project before trying it.\n\nAdd the rigs or parts you want, then simulate. You can play the result before baking it into keys. Your simulations live in this window.\n\nThings might act weird. Please report faults in our Community Server. Find the link on our Creator Store page."
		local textHeight = game:GetService("TextService"):GetTextSize(
			message:gsub("<[^>]+>", ""),
			16,
			Enum.Font.RobotoMono,
			Vector2.new(432, 10000)
		).Y
		warning = Tool.new(
			refs,
			"EclipsePhysicsWarning",
			"PHYSICS",
			Vector2.new(460, textHeight + 108),
			true,

			function()
				warning = nil
			end,
			{ Scrollable = true, Resizable = true }
		)
		local host, frame = warning, warning.content
		local body = Tool.label(
			frame,
			"Message",
			message,
			UDim2.fromOffset(14, 42),
			UDim2.new(1, -28, 1, -98)
		)
		body.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
		body.TextSize = 16
		body.RichText = true
		body.TextColor3 = Color3.new(1, 1, 1)
		body.TextTransparency = 0.12
		body.TextYAlignment = Enum.TextYAlignment.Top
		local cancel, cancelText = Tool.button(
			frame,
			"Cancel",
			"CANCEL",
			UDim2.new(0, 14, 1, -48),
			UDim2.fromOffset(210, 34),

			function()
				host:close()
			end
		)
		cancelText.TextSize = 14
		cancelText.TextTransparency = 0.15
		local proceed, proceedText = Tool.button(
			frame,
			"Proceed",
			"PROCEED",
			UDim2.new(0, 236, 1, -48),
			UDim2.fromOffset(210, 34),

			function()
				local ok = Preferences.set("PhysicsAcknowledged", true)
				if not ok then
					body.Text = "Couldn't save that preference. Close this window and try again."
					return
				end

				host:close(true)
				Window.open()
			end
		)
		proceedText.TextSize = 14
		proceedText.TextTransparency = 0.15
		proceed:SetAttribute("ThemeBg", "MenuSel")
		local scroll = host.frame.Body
		local function layoutWarning()
			if host.closed then return end
			local scale = require("Motion").scale(host.frame)
			local width = math.max(210, scroll.AbsoluteSize.X / scale - 6)
			local height = game:GetService("TextService"):GetTextSize(body.Text:gsub("<[^>]+>", ""), body.TextSize, Enum.Font.RobotoMono, Vector2.new(width - 28, 10000)).Y + 8
			local total = height + 70
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromOffset(width / 2, total / 2)
			frame.Size = UDim2.fromOffset(width, total)
			body.AnchorPoint = Vector2.new(0.5, 0.5)
			body.Position = UDim2.fromOffset(width / 2, 10 + height / 2)
			body.Size = UDim2.fromOffset(width - 28, height)
			for i, button in {cancel, proceed} do
				button.AnchorPoint = Vector2.new(0.5, 0.5)
				button.Size = UDim2.fromOffset((width - 36) / 2, 34)
				button.Position = UDim2.fromOffset(14 + (i - 1) * (width - 20) / 2 + (width - 36) / 4, height + 39)
			end
			scroll.CanvasSize = UDim2.fromOffset(0, total)
			scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		end
		table.insert(host.connections, scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutWarning))
		layoutWarning()

		return frame
	end

	local raw = refs.State.Timeline:GetState()
	window = Tool.new(refs, "EclipsePhysics", "PHYSICS", Vector2.new(440, 676), true, function()
		window = nil
		controls = nil
		revision += 1
		refs.State.PhysicsSimulating = false
		Physics.preview(false)
		Forces.close()
		if refs.State.GreasePencil and refs.State.GreasePencil.closePhysics then
			refs.State.GreasePencil.closePhysics()
		end

		require("SceneSync").hide()
	end, { Scrollable = true, Resizable = true })
	local host, frame = window, window.content
	local mode, chosen, busy = "Ragdoll", nil, false
	local progress = "CANCEL"
	local hold, setHold
	local listed, repaint, simulate, bake, remove
	local clipButtons = {}
	local inputs, tabs = {}, {}

	local function label(parent, name, text, x, y, width, height)
		local object = Tool.label(
			parent,
			name,
			text,
			UDim2.fromOffset(x, y),
			UDim2.fromOffset(width, height or 22)
		)
		object.ZIndex = parent.ZIndex + 3
		return object
	end

	local function panel(parent, name, x, y, width, height)
		local object = Tool.make("Frame", parent, name, {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BorderSizePixel = 0,
			ZIndex = 12,
		})
		object:SetAttribute("ThemeBg", "Pnl")
		Tool.make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, 4) })
		local stroke =
			Tool.make("UIStroke", object, "Outline", { Thickness = 1, Transparency = 0.35 })
		stroke:SetAttribute("ThemeStrk", "Strk")
		return object
	end

	local function hint(parent, name, text, x, y, width, height)
		local object = label(parent, name, text, x, y, width, height)
		object.TextSize = 11
		object.TextTransparency = 0.2
		return object
	end

	local bar = panel(frame, "Mode", 12, 36, 416, 30)
	for i, value in { "Ragdoll", "Objects" } do
		local button = Tool.make("TextButton", bar, value, {
			Text = value,
			Position = UDim2.new((i - 1) / 2, 3, 0, 3),
			Size = UDim2.new(0.5, -6, 1, -6),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			FontFace = Chrome.FONT,
			TextSize = 12,
			ZIndex = 14,
		})
		button:SetAttribute("ThemeTxt", "Txt")
		Tool.make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 4) })
		tabs[value] = button
		button.Activated:Connect(function()
			if busy or mode == value then
				return
			end

			for _, clip in physicalClips() do
				for motor in Scene.get().entries do
					if clip.tracks[motor] then
						notify(
							"Remove the object from the Simulations list before switching to "
								.. value
								.. "."
						)
						return
					end
				end
			end

			mode = value
			chosen = nil
			Scene.setMode(value)
			if setHold then
				setHold(value == "Objects")
			end

			repaint()
		end)
	end

	local target = label(frame, "Target", "", 12, 72, 416)
	target.TextWrapped = false
	target.TextTruncate = Enum.TextTruncate.AtEnd

	local function setupAction(callback)
		if busy then
			return
		end

		local ok, err = pcall(callback)
		if not ok then
			notify(errorText(err))
		end

		repaint()
	end

	local function addSelected()
		const before = table.clone(Scene.get().entries)
		Scene.add(mode)
		if mode ~= "Ragdoll" then
			return
		end

		for motor, entry in Scene.get().entries do
			if not before[motor] and not entry.ragdoll then
				notify(
					Scene.part(motor).Name
						.. " isn't a rig limb, so it falls as a loose object. To ragdoll a character, select the rig model itself, then Add selected."
				)
				return
			end
		end
	end

	Tool.button(
		frame,
		"AddSelected",
		"ADD SELECTED",
		UDim2.fromOffset(12, 100),
		UDim2.fromOffset(202, 26),

		function()
			setupAction(addSelected)
		end
	)
	Tool.button(
		frame,
		"ClearParticipants",
		"CLEAR LIST",
		UDim2.fromOffset(222, 100),
		UDim2.fromOffset(206, 26),

		function()
			setupAction(function()
				Scene.clear()
			end)
		end
	)
	local guide = Tool.button(
		frame,
		"GreasePencil",
		"ANNOTATE",
		UDim2.fromOffset(12, 134),
		UDim2.fromOffset(154, 26),

		function()
			setupAction(function()
				assert(#Scene.entries() > 0, "add a rig or parts first")
				local selected = Scene.selectedGuideMotors()
				local motor = selected[1] or Scene.guideMotor()
				assert(motor, "add a rig or object first")
				local choices, names = {}, {}
				for _, entry in Scene.entries() do
					table.insert(choices, entry.motor)
					names[entry.motor] = entry.rig.Name .. " / " .. entry.motor.Part1.Name
				end

				refs.State.GreasePencil.close()
				refs.State.GreasePencil.open(motor, function(target, points, easing, targets)
					assert(not host.closed, "Reopen Physics to apply the path")
					local hadGuide = #Scene.paths() > 0
					Scene.setGuides(targets or { target }, points, easing)
					setHold(false)
					if not hadGuide then
						inputs.pathEnd.Text = inputs.last.Text
					end

					repaint()
				end, {
					targets = choices,
					multiple = true,
					selected = #selected > 0 and selected or { motor },
					label = function(target)
						return names[target]
					end,
					clear = Scene.clearGuide,
				})
			end)
		end
	)
	local clearGuide = Tool.button(
		frame,
		"ClearGuide",
		"CLEAR PATHS",
		UDim2.fromOffset(174, 134),
		UDim2.fromOffset(112, 26),

		function()
			setupAction(Scene.clearGuide)
		end
	)
	local forces = Tool.button(
		frame,
		"Forces",
		"FORCES",
		UDim2.fromOffset(296, 134),
		UDim2.fromOffset(132, 26),

		function()
			setupAction(Forces.open)
		end
	)

	local function field(parent, name, title, value, x, y, width)
		label(parent, name .. "Label", title, x, y, width, 20)
		local box = Tool.field(
			parent,
			name,
			numberText(value),
			UDim2.fromOffset(x, y + 22),
			UDim2.fromOffset(width, 26)
		)
		inputs[name] = box
		require("NumericInput").bind(box, {
			step = (name == "first" or name == "last" or name == "pathEnd") and 1 or 0.1,
			integer = name == "first" or name == "last" or name == "pathEnd",
			enabled = function()
				return not busy
			end,
		})
		return box
	end

	local first = math.floor(raw.CurrentTime * raw.FPS + 0.5)
	field(frame, "first", "Start frame", first, 12, 280, 104)
	field(
		frame,
		"last",
		"End frame",
		math.max(first + 1, refs.State.Timeline:GetMaxFrame()),
		124,
		280,
		104
	)
	field(frame, "speed", "Speed (x)", 1, 236, 280, 82)
	local here = Tool.button(
		frame,
		"StartHere",
		"USE PLAYHEAD",
		UDim2.fromOffset(326, 302),
		UDim2.fromOffset(102, 26),

		function()
			if busy then
				return
			end

			local state = refs.State.Timeline:GetState()
			local at = math.floor(state.CurrentTime * state.FPS + 0.5)
			local length = math.max(
				1,
				(tonumber(inputs.last.Text) or at + 1) - (tonumber(inputs.first.Text) or at)
			)
			local pathLength = math.max(
				1,
				(tonumber(inputs.pathEnd.Text) or at + length) - (tonumber(inputs.first.Text) or at)
			)
			inputs.first.Text = tostring(at)
			inputs.last.Text = tostring(at + length)
			inputs.pathEnd.Text = tostring(at + pathLength)
		end
	)
	local pathTiming = Tool.make("Frame", frame, "PathTiming", {
		Position = UDim2.fromOffset(12, 338),
		Size = UDim2.fromOffset(416, 48),
		BackgroundTransparency = 1,
		ZIndex = 12,
	})
	field(pathTiming, "pathEnd", "Path end", tonumber(inputs.last.Text), 0, 0, 202)
	field(pathTiming, "pathLaunch", "Launch speed", 0, 214, 0, 202)
	local extra = panel(frame, "ExtraSettings", 12, 230, 416, 222)
	extra.Visible = true
	field(extra, "gravity", "Gravity", workspace.Gravity, 10, 8, 122)
	field(extra, "bounce", "Bounce", 0.1, 147, 8, 122)
	field(extra, "friction", "Friction", 0.6, 284, 8, 122)
	for i, axis in { "X", "Y", "Z" } do
		field(extra, axis, "Push " .. axis, 0, 10 + (i - 1) * 137, 62, 122)
	end

	local function checkbox(name, title, text, x, value)
		local button = Tool.make("TextButton", extra, name, {
			Text = "",
			Position = UDim2.fromOffset(x, 120),
			Size = UDim2.fromOffset(196, 24),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = 13,
		})
		label(button, "Label", title, 23, 0, 173)
		local box = Tool.make("Frame", button, "Box", {
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
			ZIndex = 14,
		})
		box:SetAttribute("ThemeBg", "TopBtn")
		local outline = Tool.make("UIStroke", box, "Outline", { Thickness = 1 })
		outline:SetAttribute("ThemeStrk", "Strk")
		local fill = Tool.make("Frame", box, "Fill", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			ZIndex = 15,
			Visible = value,
		})
		fill:SetAttribute("ThemeBg", "Txt")
		for _, item in { box, fill } do
			Tool.make("UICorner", item, "Corner", { CornerRadius = UDim.new(0, 2) })
		end

		hint(extra, name .. "Hint", text, x, 143, 196, 30)
		button.Activated:Connect(function()
			if not busy then
				value = not value
				fill.Visible = value
			end
		end)
		return function()
			return value
		end, function(nextValue)
			value = nextValue
			fill.Visible = value
		end
	end

	local inherit, setInherit =
		checkbox("Inherit", "Keep motion", "keeps the speed and spin from your animation", 10, true)
	local collision, setCollision = checkbox(
		"SelfCollision",
		"Self collision",
		"lets limbs in the same rig bump into each other",
		218,
		false
	)
	hold, setHold = checkbox(
		"Hold",
		"Stay still until hit",
		"holds the starting pose until a force reaches it",
		10,
		false
	)
	extra.Hold.Position = UDim2.fromOffset(10, 176)
	extra.Hold.Size = UDim2.fromOffset(196, 24)
	extra.Hold.Label.Size = UDim2.fromOffset(173, 22)
	extra.HoldHint.Position = UDim2.fromOffset(10, 198)
	extra.HoldHint.Size = UDim2.fromOffset(196, 20)
	local detached, setDetached =
		checkbox("Detached", "Detached limbs", "ragdoll limbs fall separately", 218, false)
	extra.Detached.Position = UDim2.fromOffset(218, 176)
	extra.DetachedHint.Position = UDim2.fromOffset(218, 198)
	extra.DetachedHint.Size = UDim2.fromOffset(196, 20)
	local previews = label(frame, "PreviewsTitle", "SIMULATIONS", 12, 216, 220)
	previews.TextSize = 11
	local fresh = Tool.button(
		frame,
		"NewPreview",
		"NEW SIM",
		UDim2.fromOffset(312, 216),
		UDim2.fromOffset(116, 24),

		function()
			if busy then
				return
			end

			chosen = nil
			Scene.clear()
			repaint()
		end
	)
	local clips = Tool.make("ScrollingFrame", frame, "Clips", {
		Position = UDim2.fromOffset(12, 246),
		Size = UDim2.fromOffset(416, 64),
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 12,
	})
	clips:SetAttribute("ThemeBg", "Pnl")
	Tool.make("UICorner", clips, "Corner", { CornerRadius = UDim.new(0, 4) })
	local stroke = Tool.make("UIStroke", clips, "Outline", { Thickness = 1, Transparency = 0.35 })
	stroke:SetAttribute("ThemeStrk", "Strk")
	Tool.make("UIPadding", clips, "Padding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	})
	Tool.make(
		"UIListLayout",
		clips,
		"Layout",
		{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }
	)

	local function action(callback)
		local ok, err = pcall(callback)
		if not ok then
			notify(errorText(err))
		end

		repaint()
	end

	local function openClip(clip)
		chosen, mode = clip, clip.settings.mode
		Scene.useClip(clip)
		inputs.speed.Text = numberText(clip.settings.speed or 1)
		inputs.pathEnd.Text = numberText(clip.settings.pathEnd or clip.last)
		inputs.pathLaunch.Text = numberText(clip.settings.pathLaunch or 0)
		for name, box in inputs do
			if clip.settings[name] ~= nil then
				box.Text = numberText(clip.settings[name])
			end
		end

		local push = clip.settings.velocity or Vector3.zero
		inputs.X.Text, inputs.Y.Text, inputs.Z.Text =
			numberText(push.X), numberText(push.Y), numberText(push.Z)
		setHold(clip.settings.hold == true)
		setInherit(clip.settings.inherit == true)
		setCollision(clip.settings.selfCollision == true)
		setDetached(clip.settings.detached == true)
		repaint()
	end

	local function dirty()
		if not chosen then
			return false
		end

		if Scene.forcesChanged(chosen) or Scene.guideChanged(chosen) then
			return true
		end

		if (chosen.settings.hold == true) ~= hold() then
			return true
		end

		if
			chosen.settings.mode ~= mode
			or (chosen.settings.inherit == true) ~= inherit()
			or (chosen.settings.selfCollision == true) ~= collision()
			or (chosen.settings.detached == true) ~= detached()
		then
			return true
		end

		for name, box in inputs do
			if name == "X" or name == "Y" or name == "Z" then
				if not Window.matchesNumber(box.Text, (chosen.settings.velocity or Vector3.zero)[name], true) then
					return true
				end
			elseif (name ~= "pathEnd" and name ~= "pathLaunch") or #Scene.paths() > 0 then
				local value = chosen.settings[name]
				if name == "speed" then
					value = value or 1
				elseif name == "pathEnd" then
					value = value or chosen.last
				elseif name == "pathLaunch" then
					value = value or 0
				end

				if not Window.matchesNumber(box.Text, value) then
					return true
				end
			end
		end

		local count = 0
		for motor in Scene.get().entries do
			if not chosen.tracks[motor] then
				return true
			end

			count += 1
		end

		local previous = 0
		for _ in chosen.tracks do
			previous += 1
		end

		return count ~= previous
	end

	local function run()
		if busy then
			revision += 1
			return
		end

		if next(Scene.get().entries) == nil then
			local added, issue = pcall(addSelected)
			if not added then notify(errorText(issue)) repaint() return end
		end
		local settings = {
			mode = mode,
			inherit = inherit(),
			selfCollision = collision(),
			hold = hold(),
			detached = detached(),
		}
		for name, box in inputs do
			settings[name] = tonumber(box.Text)
		end

		for _, name in { "first", "last", "speed", "gravity", "bounce", "friction", "X", "Y", "Z" } do
			if not settings[name] then
				notify("Fill in the empty fields with numbers first.")
				repaint()
				return
			end
		end

		if #Scene.paths() > 0 and (not settings.pathEnd or not settings.pathLaunch) then
			notify("Enter the path end frame and launch speed.")
			repaint()
			return
		end

		settings.velocity = Vector3.new(settings.X, settings.Y, settings.Z)
		local rangeError = Forces.rangeError(settings.first, settings.last)
		if rangeError then
			notify(rangeError)
			repaint()
			return
		end

		revision += 1
		local token = revision
		busy = true
		refs.State.PhysicsSimulating = true
		progress = "CANCEL · 0%"
		repaint()
		task.spawn(function()
			local update = 0
			local ok, result = pcall(Physics.simulate, settings, function(current)
				assert(not host.closed and token == revision, "simulation canceled")
				if
					os.clock() - update >= 0.05
					or current == settings.first
					or current == settings.last
				then
					progress = string.format(
						"CANCEL · %d%%",
						math.clamp(
							math.floor(
								(current - settings.first)
									/ math.max(1, settings.last - settings.first)
									* 100
							),
							0,
							100
						)
					)
					update = os.clock()
				end
			end, chosen)
			refs.State.PhysicsSimulating = false
			if host.closed then
				return
			end

			busy = false
			if ok then
				chosen = result
				Physics.preview(true)
				Window.jump(result.first)
				if result.still then
					notify(
						STILL_REASONS[result.stillReason]
							or "Nothing moved in this simulation. Check the start and end frames, Gravity and the pushes, then simulate again."
					)
				else
					notify("Simulation ready. Click PLAY to preview, then BAKE KEYS to keep it.")
				end
			else
				notify(errorText(result))
			end

			repaint()
		end)
	end

	controls = {
		run = run,
		state = function()
			local ready = next(Scene.get().entries) ~= nil
			return {
				busy = busy,
				ready = ready,
				preview = chosen ~= nil,
				dirty = dirty(),
				playing = raw.Playing,
				first = tonumber(inputs.first.Text),
				last = tonumber(inputs.last.Text),
			}
		end,
		includeFrame = function(at)
			if busy then
				return
			end

			inputs.first.Text = tostring(math.min(tonumber(inputs.first.Text) or at, at))
			inputs.last.Text = tostring(math.max(tonumber(inputs.last.Text) or at + 1, at + 1))
			repaint()
		end,
		play = function()
			if busy then
				return
			end

			if refs.State.Timeline:IsExportLocked() then
				notify("Wait for the export to finish before playing.")
				return
			end

			if raw.Playing then
				raw.Playing = false
				return
			end

			if not chosen then
				notify("Simulate first, then select the simulation to play.")
				return
			end

			if dirty() then
				notify("Playing the last simulation. Click UPDATE SIM to preview changed settings.")
			end

			Window.jump(chosen.first)
			refs.State.Timeline:StartPlayback()
		end,
	}
	simulate = Tool.button(
		frame,
		"Simulate",
		"SIMULATE",
		UDim2.fromOffset(12, 358),
		UDim2.fromOffset(132, 28),
		Window.run
	)
	bake = Tool.button(
		frame,
		"Bake",
		"BAKE KEYS",
		UDim2.fromOffset(154, 358),
		UDim2.fromOffset(132, 28),

		function()
			if busy then
				return
			elseif not chosen then
				notify("Simulate first, then select the simulation to bake.")
				return
			elseif refs.State.Timeline:GetState().Playing then
				notify("Pause playback before baking keys.")
				return
			elseif dirty() then
				notify("The simulation settings changed. Click UPDATE SIM, then BAKE KEYS.")
				return
			end

			revision += 1
			local token = revision
			busy = true
			refs.State.PhysicsSimulating = true
			progress = "CANCEL BAKE"
			repaint()
			task.spawn(function()
				local ok, result = pcall(Physics.bake, chosen, function()
					assert(not host.closed and token == revision, "simulation canceled")
				end)
				refs.State.PhysicsSimulating = false
				busy = false
				if host.closed then
					return
				end

				if ok then
					chosen = nil
					notify("Physics baked into animation keys.")
				else
					notify(errorText(result))
				end

				repaint()
			end)
		end
	)
	remove = Tool.button(
		frame,
		"Play",
		"PLAY",
		UDim2.fromOffset(296, 358),
		UDim2.fromOffset(132, 28),
		Window.play
	)
	local body = host.frame.Body
	local function place(object, x, y, width, height)
		object.AnchorPoint = Vector2.new(0.5, 0.5)
		object.Position = UDim2.fromOffset(x + width / 2, y + height / 2)
		object.Size = UDim2.fromOffset(width, height)
	end
	local function layout()
		if host.closed then return end
		local scale = require("Motion").scale(host.frame)
		local width = math.max(210, body.AbsoluteSize.X / scale - 6)
		local height = body.AbsoluteSize.Y / scale
		local usable = width - 24
		local function buttons(items, x, y, w, minimum, h)
			local columns = math.clamp(math.floor((w + 8) / (minimum + 8)), 1, #items)
			local cell = (w - (columns - 1) * 8) / columns
			for i, object in items do
				place(object, x + ((i - 1) % columns) * (cell + 8), y + math.floor((i - 1) / columns) * (h + 8), cell, h)
			end
			return y + math.ceil(#items / columns) * (h + 8)
		end
		local function fields(names, parent, x, y, w, minimum)
			local columns = math.clamp(math.floor((w + 8) / (minimum + 8)), 1, #names)
			local cell = (w - (columns - 1) * 8) / columns
			for i, name in names do
				local left = x + ((i - 1) % columns) * (cell + 8)
				local top = y + math.floor((i - 1) / columns) * 56
				if name == "here" then
					place(here, left, top + 22, cell, 26)
				else
					place(parent[name .. "Label"], left, top, cell, 20)
					place(inputs[name].Parent, left, top + 22, cell, 26)
				end
			end
			return y + math.ceil(#names / columns) * 56
		end
		place(bar, 12, 8, usable, 30)
		for i, name in { "Ragdoll", "Objects" } do
			place(tabs[name], 3 + (i - 1) * usable / 2, 3, usable / 2 - 6, 24)
		end
		place(target, 12, 44, usable, 22)
		local top = buttons({frame.AddSelected, frame.ClearParticipants}, 12, 72, usable, 100, 26)
		top = buttons({guide, clearGuide, forces}, 12, top, usable, 100, 26) + 8
		local wide = usable >= 720
		local listWidth = wide and math.floor(usable * 0.38) or usable
		local settingsX = wide and 12 + listWidth + 16 or 12
		local settingsWidth = wide and usable - listWidth - 16 or usable
		local inner = settingsWidth - 20
		local extraY = fields({"gravity", "bounce", "friction", "X", "Y", "Z"}, extra, 10, 8, inner, 104)
		local names = {"Inherit", "SelfCollision", "Hold", "Detached"}
		local columns = inner >= 360 and 2 or 1
		local cell = (inner - (columns - 1) * 12) / columns
		for row = 1, math.ceil(#names / columns) do
			local rowHeight = 0
			for column = 1, columns do
				local name = names[(row - 1) * columns + column]
				if name then
					local button, help = extra[name], extra[name .. "Hint"]
					local x = 10 + (column - 1) * (cell + 12)
					local textHeight = game:GetService("TextService"):GetTextSize(help.Text, help.TextSize, Enum.Font.RobotoMono, Vector2.new(cell, 1000)).Y + 4
					place(button, x, extraY, cell, 24)
					place(button.Label, 23, 0, cell - 23, 24)
					place(help, x, extraY + 24, cell, textHeight)
					rowHeight = math.max(rowHeight, 24 + textHeight + 8)
				end
			end
			extraY += rowHeight
		end
		local function settings(y)
			y = fields({"first", "last", "speed", "here"}, frame, settingsX, y, settingsWidth, 90)
			local pathHeight = fields({"pathEnd", "pathLaunch"}, pathTiming, 0, 0, settingsWidth, 110)
			place(pathTiming, settingsX, y, settingsWidth, pathHeight)
			y += pathHeight + 6
			place(extra, settingsX, y, settingsWidth, extraY)
			y += extraY + 12
			return buttons({simulate, bake, remove}, settingsX, y, settingsWidth, 100, 28) + 4
		end
		local settingsHeight = settings(0)
		local listHeight = wide and math.max(100, height - top - 44, settingsHeight - 32)
			or math.max(72, height - top - settingsHeight - 44)
		place(previews, 12, top, math.max(70, listWidth - 116), 24)
		place(fresh, 12 + listWidth - 108, top, 108, 24)
		place(clips, 12, top + 32, listWidth, listHeight)
		local bottom = settings(wide and top or top + 32 + listHeight + 12)
		local total = math.max(bottom, top + 32 + listHeight + 12)
		place(frame, 0, 0, width, total)
		body.CanvasSize = UDim2.fromOffset(0, total)
		body.ScrollingDirection = Enum.ScrollingDirection.Y
	end
	table.insert(host.connections, body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))

	repaint = function()
		if host.closed then
			return
		end

		if refs.State.LoadingProject then
			return
		end

		if not refs.Active() then
			if
				not refs.ScreenGui.Parent
				or not refs.ScreenGui.Enabled
			then
				Window.close()
			else
				host.gui.Enabled = false
			end

			return
		end

		host.gui.Enabled = true
		local list = physicalClips()
		if chosen and not table.find(list, chosen) then
			chosen = nil
		end

		local listChanged = not listed or #listed ~= #list
		if not listChanged then
			for i, clip in list do
				if listed[i] ~= clip then
					listChanged = true
					break
				end
			end
		end

		if listChanged then
			listed = list
			for _, child in clips:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end

			if #list == 0 then
				local empty = hint(clips, "Empty", "No simulations yet", 0, 0, 386, 28)
				empty.Size = UDim2.new(1, -4, 0, 28)
				empty.TextWrapped = false
				empty.TextTruncate = Enum.TextTruncate.AtEnd
			end

			clipButtons = {}
			for i, clip in list do
				local row = Tool.make("Frame", clips, "Clip" .. i, {
					Size = UDim2.new(1, -4, 0, 28),
					BackgroundTransparency = 1,
					LayoutOrder = i,
					ZIndex = 13,
				})
				local button, title = Tool.button(
					row,
					"Select",
					i .. ". " .. clip.name .. "  |  " .. clip.first .. " - " .. clip.last,
					UDim2.new(),
					UDim2.new(1, -80, 1, 0),

					function()
						if not busy then
							openClip(clip)
						end
					end
				)
				button:SetAttribute("PhysicsClipId", clip.id)
				table.insert(clipButtons, button)
				title.TextWrapped = false
				title.TextTruncate = Enum.TextTruncate.AtEnd
				title.TextSize = 11
				Tool.button(
					row,
					"Remove",
					"REMOVE",
					UDim2.new(1, -74, 0, 0),
					UDim2.fromOffset(74, 28),

					function()
						if busy then
							return
						end

						action(function()
							Physics.remove(clip)
							if chosen == clip then
								chosen = nil
							end
						end)
					end
				)
			end

			Theme.applyTree(clips)
		end

		for _, button in clipButtons do
			local active = chosen and button:GetAttribute("PhysicsClipId") == chosen.id
			local color = active and "MenuSel" or "TopBtn"
			if button:GetAttribute("ThemeBg") ~= color then
				button:SetAttribute("ThemeBg", color)
				Theme.applyInstance(button)
			end

			FX.setRestingProperty(button, "BackgroundTransparency", active and 0 or 0.4)
		end

		for value, button in tabs do
			FX.setRestingProperty(button, "BackgroundTransparency", mode == value and 0 or 1)
			button.BackgroundColor3 = Theme.get("TopBtn", Color3.fromRGB(30, 60, 65))
			button.Interactable = not busy
		end

		local valid, rig, motors = pcall(Physics.targets, mode)
		local registered = 0
		for _ in Scene.get().entries do
			registered += 1
		end

		target.Text = registered > 0 and registered .. " parts added"
			or "Select a rig, model or parts, then Add selected"
		guide.TextLabel.Text = #Scene.paths() > 0 and "EDIT DRAWN PATHS" or "ANNOTATE"
		clearGuide.Interactable = not busy and #Scene.paths() > 0
		forces.TextLabel.Text = "FORCES (" .. #Scene.get().forces .. ")"
		for _, button in { guide, forces } do
			button.Interactable = not busy
		end

		local playing = refs.State.Timeline:GetState().Playing
		simulate.Interactable = busy or not playing
		simulate:SetAttribute("Ready", simulate.Interactable)
		simulate.TextLabel.Text = busy and progress or chosen and "UPDATE SIM" or "SIMULATE"
		bake.Interactable = not busy
		remove.Interactable = not busy
		remove.TextLabel.Text = playing and "STOP" or "PLAY"
		for _, button in { bake, remove } do
			button:SetAttribute("Ready", button.Interactable)
		end

		for button, primary in
			{ [simulate] = chosen == nil or dirty(), [bake] = chosen ~= nil and not dirty() }
		do
			local color = primary and "MenuSel" or "TopBtn"
			if button:GetAttribute("ThemeBg") ~= color then
				button:SetAttribute("ThemeBg", color)
				Theme.applyInstance(button)
			end

			button:SetAttribute("Primary", primary)
		end

		fresh.Interactable = not busy
		here.Interactable = not busy
		for _, box in inputs do
			box.TextEditable = not busy
		end

		local hasPath = #Scene.paths() > 0
		for _, name in { "pathEnd", "pathLaunch" } do
			inputs[name].TextEditable = not busy and hasPath
		end

		pathTiming.Visible = true
		layout()
	end

	local elapsed = 0
	table.insert(
		host.connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed > 0.2 then
				elapsed = 0
				repaint()
			end
		end)
	)
	local unsubscribe = Theme.onChanged(repaint)
	frame.Destroying:Once(unsubscribe)
	Physics.preview(true)
	local existing = physicalClips()
	if #existing > 0 then
		openClip(existing[#existing])
	else
		repaint()
	end

	require("SceneSync").refresh()
	return frame
end

function Window.toggle()
	if Window.isOpen() then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(options)
	Window.destroy()
	refs = options
	Physics.init(options)
	Forces.init(options)
	refs.State.Physics = Window
	Physics.preview(false)
	require("SceneSync").init(options)
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Window.close()
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Window.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Window.destroy))
end

function Window.hasProjectData()
	local session = Scene.get()
	return next(session.entries or {}) ~= nil
		or next(session.forces or {}) ~= nil
		or next(session.guides or {}) ~= nil
		or session.guide ~= nil
end

function Window.write(save)
	Scene.write(save)
end

function Window.load(save)
	require("SmartBone").close()
	require("customRest").close()
	Window.close(true)
	Scene.load(save)
end

return Window
