--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Engine = require("KeyframeCleanup")
local Edit = require("BlenderEdit")
local Chrome = require("Chrome")
local Surface = require("Surface")
local Theme = require("Theme")
local History = require("History")
local HoverDialog = require("HoverDialog")
local FX = require("WindowFX")
local Window = {}
local closing = {}
local refs, window, layer, tooltip
local result, running, revision = nil, false, 0
local mode, method, scope = "Smooth", "Gaussian", "Selected"
local connections = {}
local status, review, applyButton, analyzeButton, inputs, render

local function make(class, parent, name, properties)
	local item = Instance.new(class)
	item.Name = name
	for key, value in properties do
		item[key] = value
	end

	item.Parent = parent
	return item
end

local function label(parent, name, text, position, size)
	local item = make("TextLabel", parent, name, {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		TextSize = 12,
		FontFace = Chrome.FONT,
		TextColor3 = Theme.get("Txt", Color3.new(1, 1, 1)),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		ZIndex = parent.ZIndex + 2,
	})
	item:SetAttribute("ThemeTxt", "Txt")
	return item
end

local function navigation()
	if refs and refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end
end

local function invalidate(message)
	revision += 1
	running, result = false, nil
	if status then
		status.Text = message or ""
	end

	if applyButton then
		applyButton.Active = false
		applyButton.TextLabel.TextTransparency = 0.65
	end

	if analyzeButton then
		analyzeButton.TextLabel.Text = "PREVIEW"
	end

	if review then
		review.Text = ""
	end
end

function Window.isOpen()
	return window ~= nil
end

function Window.close(immediate)
	invalidate()
	if tooltip then
		tooltip:Destroy()
		tooltip = nil
	end

	local oldLayer, oldWindow = layer, window
	window, layer = nil, nil
	status, review, applyButton, analyzeButton, inputs, render = nil, nil, nil, nil, nil, nil
	if oldLayer then
		local functionDispose = function()
			FX.clear(oldWindow)
			closing[oldLayer] = nil
			oldLayer:Destroy()
		end

		if immediate then
			functionDispose()
		else
			closing[oldLayer] = oldWindow
			for _, object in oldWindow:GetDescendants() do
				if object:IsA("GuiButton") then
					object.Interactable = false
				end

				if object:IsA("TextBox") then
					object.TextEditable = false
				end
			end

			FX.shrink(oldWindow, functionDispose)
		end
	end

	navigation()
end

function Window.destroy()
	Window.close(true)
	for gui, frame in closing do
		FX.clear(frame)
		gui:Destroy()
	end

	table.clear(closing)
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	refs = nil
end

local function available()
	assert(refs and refs.Active() and refs.State.currentRig, "Open an Eclipse project first.")
	assert(not Edit.blocked(), "Turn Blender Live off before editing this animation.")
	assert(
		not refs.State.Timeline:GetState().Playing,
		"Stop playback before reviewing or applying cleanup."
	)
end

function Window.targets(choice)
	available()
	local state = refs.State.Timeline:GetState()
	local chosen = {}
	if choice == "Selected" then
		for key in state.SelectedKeyframes or {} do
			if key.Motor then
				chosen[key.Motor] = true
			end
		end

		for key in state.SelectedChannelKeyframes or {} do
			if key.Motor then
				chosen[key.Motor] = true
			end
		end

		if state.SelectedKeyframe and state.SelectedKeyframe.Motor then
			chosen[state.SelectedKeyframe.Motor] = true
		end
	else
		local rig = refs.State.currentRig
		for motor in state.Keyframes do
			if
				motor.Parent
				and (
					motor.Part1 and motor.Part1:IsDescendantOf(rig)
					or typeof(motor) == "Instance" and motor:IsDescendantOf(rig)
				)
			then
				chosen[motor] = true
			end
		end
	end

	local motors = {}
	for motor in chosen do
		if motor.Parent and state.Keyframes[motor] then
			table.insert(motors, motor)
		end
	end

	table.sort(motors, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	assert(
		#motors > 0,
		"Select at least one animation key, or choose Current rig with keyed tracks."
	)
	return motors
end

function Window.analyze(settings, checkpoint)
	available()
	if refs.Finalize then
		refs.Finalize()
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	settings.fps = raw.FPS
	local motors = Window.targets(settings.scope)
	local snapshots = {}
	for _, motor in motors do
		snapshots[motor] = Engine.copy(raw.Keyframes[motor])
	end

	local analyzed = Engine.run(timeline, motors, settings, checkpoint)
	analyzed.keyframes, analyzed.sources, analyzed.project =
		raw.Keyframes, snapshots, refs.State.currentAnimations
	return analyzed
end

function Window.apply(analyzed)
	available()
	assert(analyzed and analyzed.changed > 0, "There are no changes to apply.")
	local state, timeline = refs.State, refs.State.Timeline
	local raw = timeline:GetState()
	assert(
		raw.Keyframes == analyzed.keyframes
			and raw.FPS == analyzed.fps
			and state.currentAnimations == analyzed.project,
		"The project changed. Review the result again."
	)
	for motor, snapshot in analyzed.sources do
		assert(
			motor.Parent and Engine.equal(snapshot, raw.Keyframes[motor]),
			"Animation changed since review. Review the result again."
		)
	end

	local function restore(buckets)
		for motor, bucket in buckets do
			if motor.Parent then
				timeline:_restoreMotorBucket(motor, bucket)
			end
		end

		if state.GraphEditor then
			state.GraphEditor.invalidate()
		end

		if state.currentRig then
			timeline:ApplyPoseAtTime(state.currentRig, raw.CurrentTime)
		end

		timeline:RefreshAllKeyframeVisuals()
		if state.Axis and state.Axis.RefreshAxis then
			state.Axis:RefreshAxis()
		end

		state.currentProjectSaved = false
	end

	local ok, err = xpcall(function()
		restore(analyzed.after)
	end, debug.traceback)
	if not ok then
		restore(analyzed.before)
		error(err)
	end

	History.record(function()
		restore(analyzed.before)
	end, function()
		restore(analyzed.after)
	end, analyzed.mode == "Smooth" and "Smooth animation" or "Optimize animation")
	return true
end

function Window.clearTransform()
	if not refs or not refs.Active() or not refs.State.currentRig or Edit.blocked() then
		return 0
	end

	if refs.State.Timeline:GetState().Playing then
		return 0
	end

	if refs.Finalize then
		refs.Finalize()
	end

	local state = refs.State
	local timeline = state.Timeline
	local raw = timeline:GetState()
	local chosen = {}
	local frame = timeline:TimeToFrame(raw.CurrentTime)
	if state.Axis and state.Rig then
		for _, bone in state.Axis:GetSelectedBones() do
			local part = state.Rig:GetPartFromBone(state.currentRig, bone)
			local motor = part and state.Rig:GetMotorForPart(state.currentRig, part)
			local owner = bone:FindFirstChild("EclipseLimbOwner")
			if not motor and owner and owner:IsA("ObjectValue") then
				motor = require("R6Controls").resolveOwner(owner.Value)
			end

			if motor then
				chosen[motor] = true
			end
		end
	end

	if not next(chosen) then
		for key in raw.SelectedKeyframes or {} do
			if key.Motor then
				chosen[key.Motor] = true
			end
		end

		for key in raw.SelectedChannelKeyframes or {} do
			if key.Motor then
				chosen[key.Motor] = true
			end
		end

		if raw.SelectedKeyframe and raw.SelectedKeyframe.Motor then
			chosen[raw.SelectedKeyframe.Motor] = true
		end
	end

	local before, after = {}, {}
	local count = 0
	for motor in chosen do
		local rest = typeof(motor) == "table"
				and motor.IsEclipseArmatureControl
				and require("Properties").basePose(motor, motor.RestC0)
			or raw.DefaultPose[motor]
		local bucket = raw.Keyframes[motor]
		if rest and not require("Properties").is(motor) then
			local values = timeline:DecomposeC0(rest)
			local G = require("GraphCurves")
			local ex, ey, ez = G.euler(rest, G.rotationOrder(bucket))
			local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
			values.rot_x, values.rot_y, values.rot_z = math.deg(x), math.deg(y), math.deg(z)
			local world = raw.DefaultWorldPose[motor]
				or motor.Part0.CFrame * rest * motor.C1:Inverse()
			before[motor] = Engine.copy(bucket or {})
			local target = Engine.copy(bucket or {})
			if not target[frame] then
				local key = require("KeyframeDefaults").new(target, frame)
				key.Frame, key.Time, key.Motor, key.Part =
					frame, frame / raw.FPS, motor, motor.Part1
				key.Parented = motor:GetAttribute("TrackParent") ~= false
				key.IK, key.HS, key.HeadFollow = false, false, false
				key.Channels = {}
				for id, value in values do
					if require("Policy").channelAvailable(motor, id) then
						key.Channels[id] = { Value = value }
					end
				end

				target[frame] = key
			end

			after[motor] = Engine.clearTransforms(target, rest, world, values, frame)
			count += 1
		end
	end

	if count == 0 then
		return 0
	end

	local function restore(buckets)
		require("LimbIK").clearLive()
		for motor, bucket in buckets do
			timeline:_restoreMotorBucket(motor, Engine.copy(bucket), true)

			for at, key in bucket do
				local restored = raw.Keyframes[motor][at]
				if restored then
					restored.Channels = require("GraphCurves").clone(key.Channels)
				end
			end
		end

		raw.LastPlaybackFrame = nil
		timeline:RefreshAllKeyframeVisuals()
		if state.GraphEditor then
			state.GraphEditor.invalidate()
		end

		if state.currentRig then
			timeline:ApplyPoseAtTime(state.currentRig, raw.CurrentTime)
		end

		if state.Axis then
			state.Axis:RefreshAxis()
		end

		state.currentProjectSaved = false
	end

	local ok, err = xpcall(function()
		restore(after)
	end, debug.traceback)
	if not ok then
		restore(before)
		error(err, 0)
	end

	History.record(function()
		restore(before)
	end, function()
		restore(after)
	end, "Clear transform")
	return count
end

local function showResult(analyzed)
	local lines, details = {}, {}
	for _, row in analyzed.rows do
		table.insert(
			lines,
			row.name
				.. (
					row.reason and (" - " .. row.reason)
					or (
						analyzed.mode == "Smooth" and " - smoothed"
						or string.format(" - %d to %d keys", row.before, row.after)
					)
				)
		)
		if not row.reason then
			table.insert(
				details,
				string.format(
					"%s: %.4g %s, %.3g deg rotation, %.3g scale",
					row.name,
					row.position,
					row.fov and "FOV degrees" or "studs",
					row.rotation,
					row.scale
				)
			)
		end
	end

	review.Text = table.concat(lines, "\n")
	review:SetAttribute("Details", table.concat(details, "\n"))
	status.Text = analyzed.changed == 0 and "No changes needed."
		or analyzed.mode == "Smooth" and string.format("%d tracks smoothed", analyzed.changed)
		or string.format(
			"%d keys removed (%d to %d)",
			analyzed.beforeCount - analyzed.afterCount,
			analyzed.beforeCount,
			analyzed.afterCount
		)
	if analyzed.skipped > 0 then
		status.Text ..= string.format(" | %d skipped", analyzed.skipped)
	end

	applyButton.Active = analyzed.changed > 0
	applyButton.TextLabel.TextTransparency = analyzed.changed > 0 and 0 or 0.65
	if render then
		render()
	end
end

function Window.open()
	if window then
		return window
	end

	if not refs or not refs.Active() or not refs.ScreenGui.Enabled then
		return nil
	end

	layer = make("ScreenGui", refs.ScreenGui.Parent, "EclipseAnimationCleanup", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = refs.ScreenGui.DisplayOrder + 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	window = make("CanvasGroup", layer, "AnimationCleanup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 224),
		Active = true,
		ZIndex = 10,
	})
	local frame = window
	Surface.backdrop(frame, true)
	local header, _, drag = Chrome.header(frame, "ANIMATION CLEANUP")
	Chrome.close(header, function()
		Window.close()
	end)
	if refs.HoverDialog then
		local ui = refs.HoverDialog.ui:Clone()
		ui.Name = "CleanupTooltip"
		ui.Visible = false
		ui.ZIndex = 200
		local previousLimit = ui.Information:FindFirstChild("TooltipSizeLimit")
		if previousLimit then
			previousLimit:Destroy()
		end

		ui.Parent = layer
		tooltip = HoverDialog.initialize(ui, refs.HoverDialog.mouse)
	end

	local function hint(item, text)
		if tooltip then
			tooltip:latchToInstance(item, text, { maxWidth = 300 })
		end
	end

	local tabs = make("Frame", frame, "Tabs", {
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(1, -24, 0, 30),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	tabs:SetAttribute("ThemeBg", "Pnl")
	local tabsStroke = make("UIStroke", tabs, "Outline", { Thickness = 1, Transparency = 0.3 })
	tabsStroke:SetAttribute("ThemeStrk", "Strk")
	make("UICorner", tabs, "Corner", { CornerRadius = UDim.new(0, 3) })

	local function tab(name, text, x)
		local button = make("TextButton", tabs, name, {
			Text = text,
			Position = UDim2.new(x, 2, 0, 2),
			Size = UDim2.new(0.5, -4, 0, 26),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			FontFace = Chrome.FONT,
			TextSize = 11,
			ZIndex = 13,
		})
		button:SetAttribute("ThemeTxt", "Txt")
		make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 4) })
		return button
	end

	local smoothTab, optimizeTab =
		tab("SmoothTab", "Smooth", 0), tab("OptimizeTab", "Optimize", 0.5)
	hint(smoothTab, "Smooth jitter while retaining key times and end poses.")
	hint(optimizeTab, "Remove redundant keys within the chosen tolerances.")
	local popup, popupOwner

	local function closePopup()
		if popup then
			popup:Destroy()
			popup = nil
		end

		popupOwner = nil
	end

	local function dropdown(name, text, position, size, choices, select)
		local button, title = Chrome.menuButton(frame, name, text, position, size)
		title.Position, title.Size = UDim2.fromOffset(8, 0), UDim2.new(1, -34, 1, 0)
		title.TextXAlignment, title.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
		local arrow = label(
			button,
			"DropdownArrow",
			utf8.char(0x25BE),
			UDim2.new(1, -26, 0, 0),
			UDim2.fromOffset(20, 24)
		)
		arrow.TextXAlignment = Enum.TextXAlignment.Center
		button.Activated:Connect(function()
			if popupOwner == button then
				closePopup()
				return
			end

			closePopup()
			popupOwner = button
			popup = make("Frame", frame, "Choices", {
				Position = button.Position + UDim2.fromOffset(0, button.Size.Y.Offset + 3),
				Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, #choices * 24 + 4),
				BorderSizePixel = 0,
				ZIndex = 120,
			})
			Surface.fill(popup)
			local border = make("UIStroke", popup, "Outline", { Thickness = 1 })
			border:SetAttribute("ThemeStrk", "Strk")
			for i, choice in choices do
				local entry = Chrome.menuButton(
					popup,
					"Choice" .. i,
					choice[1],
					UDim2.fromOffset(2, 2 + (i - 1) * 24),
					UDim2.new(1, -4, 0, 24),
					121
				)
				entry.Activated:Connect(function()
					closePopup()
					select(choice[2])
					invalidate()
					render()
				end)
			end

			Theme.applyTree(popup)
		end)
		return button, title
	end

	label(frame, "ScopeLabel", "Tracks", UDim2.fromOffset(12, 74), UDim2.fromOffset(58, 24))
	local scopeButton, scopeText = dropdown(
		"Scope",
		"Selected tracks",
		UDim2.fromOffset(76, 74),
		UDim2.new(1, -88, 0, 24),
		{ { "Selected tracks", "Selected" }, { "Current rig", "Rig" } },

		function(value)
			scope = value
		end
	)
	hint(
		scopeButton,
		"Selected tracks uses the tracks containing your selected keys. Both options process each track's full keyed length, including all transform channels."
	)
	label(frame, "FilterLabel", "Filter", UDim2.fromOffset(12, 108), UDim2.fromOffset(58, 24))
	local filterButton, filterText = dropdown(
		"Filter",
		"Gaussian",
		UDim2.fromOffset(76, 108),
		UDim2.new(1, -88, 0, 24),
		{ { "Gaussian", "Gaussian" }, { "Butterworth", "Butterworth" } },

		function(value)
			method = value
		end
	)
	hint(
		filterButton,
		"Gaussian averages nearby poses. Butterworth removes rapid changes using a forward/backward filter to avoid time lag."
	)
	inputs = {}

	local function field(name, title, default, x, y, tooltip)
		local row = make("Frame", frame, name .. "Field", {
			Position = UDim2.new(x, x == 0 and 12 or 6, 0, y),
			Size = UDim2.new(0.5, -18, 0, 24),
			BackgroundTransparency = 1,
			ZIndex = 12,
		})
		label(row, "Label", title, UDim2.new(), UDim2.new(1, -70, 1, 0))
		local fill = make("Frame", row, "ValueField", {
			Position = UDim2.new(1, -64, 0, 0),
			Size = UDim2.fromOffset(64, 24),
			BorderSizePixel = 0,
			ZIndex = 14,
		})
		fill:SetAttribute("ThemeBg", "TopBtn")
		local stroke =
			make("UIStroke", fill, "Outline", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		stroke:SetAttribute("ThemeStrk", "Strk")
		local input = make("TextBox", fill, name, {
			Text = default,
			ClearTextOnFocus = false,
			Position = UDim2.fromOffset(5, 0),
			Size = UDim2.new(1, -10, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 15,
			FontFace = Chrome.FONT,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		input:SetAttribute("ThemeTxt", "Txt")
		input:GetPropertyChangedSignal("Text"):Connect(function()
			invalidate()
			if render then
				render()
			end
		end)
		inputs[name] = input
		require("NumericInput").bind(input, {
			step = name == "Position" and 0.01
				or name == "Rotation" and 0.1
				or name == "Strength" and 1
				or 0.1,
			min = 0,
		})
		hint(row, tooltip)
		return row
	end

	local width = field(
		"Width",
		"Width (frames)",
		"2",
		0,
		142,
		"Gaussian standard deviation in frames (0.5 to 30). Larger values smooth over more time. Authored key times are preserved."
	)
	local cutoff = field(
		"Cutoff",
		"Cutoff (Hz)",
		"6",
		0,
		142,
		"Lower frequencies remove more jitter. Must be positive and below half the project FPS."
	)
	local strength = field(
		"Strength",
		"Strength (%)",
		"75",
		0.5,
		142,
		"How much filtering to apply, from greater than 0 to 100%. End poses stay fixed. Intermediate keys use Auto Clamped transitions."
	)
	local position = field(
		"Position",
		"Position",
		"0.01",
		0,
		108,
		"Maximum sampled local-position error in studs. This does not guarantee world-space hand or foot contacts."
	)
	local rotation = field(
		"Rotation",
		"Rotation",
		"0.1",
		0.5,
		108,
		"Maximum sampled local-rotation error in degrees."
	)
	local scale = field(
		"Scale",
		"Scale",
		"0.001",
		0,
		142,
		"Maximum sampled scale-component error. 0.001 is 0.1% of a scale value of 1."
	)
	local fov = field(
		"FOV",
		"Camera FOV",
		"0.05",
		0.5,
		142,
		"Maximum sampled camera field-of-view error in degrees."
	)
	local divider = make("Frame", frame, "Divider", {
		Position = UDim2.fromOffset(12, 176),
		Size = UDim2.new(1, -24, 0, 1),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.4,
		ZIndex = 12,
	})
	divider:SetAttribute("ThemeBg", "Strk")
	local log = make("ScrollingFrame", frame, "Log", {
		Position = UDim2.fromOffset(12, 184),
		Size = UDim2.new(1, -24, 0, 28),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	status = label(log, "Status", "", UDim2.new(), UDim2.new(1, -8, 0, 0))
	status.AutomaticSize, status.TextYAlignment = Enum.AutomaticSize.Y, Enum.TextYAlignment.Top
	local results = make("ScrollingFrame", frame, "Results", {
		Position = UDim2.fromOffset(12, 216),
		Size = UDim2.new(1, -24, 1, -260),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 12,
		Visible = false,
	})
	review = label(results, "Report", "", UDim2.new(), UDim2.new(1, -8, 0, 0))
	review.AutomaticSize, review.TextYAlignment = Enum.AutomaticSize.Y, Enum.TextYAlignment.Top
	make("UIPadding", results, "BottomPadding", { PaddingBottom = UDim.new(0, 8) })
	hint(review, function()
		return review and review:GetAttribute("Details") or ""
	end)
	analyzeButton = Chrome.menuButton(
		frame,
		"Analyze",
		"PREVIEW",
		UDim2.new(0, 12, 1, -36),
		UDim2.new(0.5, -18, 0, 24)
	)
	applyButton = Chrome.menuButton(
		frame,
		"Apply",
		"APPLY",
		UDim2.new(0.5, 6, 1, -36),
		UDim2.new(0.5, -18, 0, 24)
	)
	hint(
		analyzeButton,
		"Calculate changes without editing the animation. Apply commits the result as one undoable operation."
	)
	render = function()
		if window ~= frame or not status then
			return
		end

		local hasStatus = status.Text ~= ""
		local logHeight = hasStatus and math.clamp(status.TextBounds.Y, 16, 48) or 0
		log.Visible = hasStatus
		log.Size = UDim2.new(1, -24, 0, logHeight)
		local bottom = hasStatus and 184 + logHeight or 176
		local hasResults = result ~= nil and result.changed > 0
		results.Visible = hasResults
		if hasResults then
			local height = math.clamp(review.TextBounds.Y + 8, 22, 112)
			results.Position = UDim2.fromOffset(12, bottom + 8)
			results.Size = UDim2.new(1, -24, 0, height)
			bottom += 8 + height
		end

		local size = UDim2.fromOffset(420, bottom + 48)
		if frame.Size ~= size then
			frame.Size = size
		end

		local smoothing = mode == "Smooth"
		for button, active in { [smoothTab] = smoothing, [optimizeTab] = not smoothing } do
			button.BackgroundColor3 = Theme.get("TopBtn", Color3.fromRGB(30, 60, 65))
			button.BackgroundTransparency = active and 0 or 1
			button.TextTransparency = 0
		end

		scopeText.Text = scope == "Selected" and "Selected tracks" or "Current rig"
		filterText.Text = method
		filterButton.Visible, frame.FilterLabel.Visible, strength.Visible =
			smoothing, smoothing, smoothing
		width.Visible, cutoff.Visible =
			smoothing and method == "Gaussian", smoothing and method == "Butterworth"
		for _, row in { position, rotation, scale, fov } do
			row.Visible = not smoothing
		end
	end

	smoothTab.Activated:Connect(function()
		closePopup()
		mode = "Smooth"
		invalidate()
		render()
	end)
	optimizeTab.Activated:Connect(function()
		closePopup()
		mode = "Optimize"
		invalidate()
		render()
	end)
	local outside = game:GetService("UserInputService").InputBegan:Connect(function(input)
		if not popup or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local function inside(item)
			local p, s = item.AbsolutePosition, item.AbsoluteSize
			return input.Position.X >= p.X
				and input.Position.X <= p.X + s.X
				and input.Position.Y >= p.Y
				and input.Position.Y <= p.Y + s.Y
		end

		if not inside(popup) and not inside(popupOwner) then
			closePopup()
		end
	end)
	frame.Destroying:Once(function()
		outside:Disconnect()
	end)
	analyzeButton.Activated:Connect(function()
		closePopup()
		if running then
			invalidate("Preview canceled.")
			render()
			return
		end

		invalidate()
		render()
		local token = revision
		running = true
		analyzeButton.TextLabel.Text = "CANCEL"
		status.Text = "Processing..."
		local lastYield = os.clock()
		local checkpoint = function(name)
			assert(window == frame and revision == token, "Preview canceled.")
			if name then
				status.Text = name
			end

			if os.clock() - lastYield > 0.012 then
				task.wait()
				lastYield = os.clock()
			end
		end

		local settings = { scope = scope, mode = mode, method = method }
		for name, input in inputs do
			settings[name:lower()] = tonumber(input.Text)
		end

		settings.strength = (settings.strength or 0) / 100
		task.spawn(function()
			local ok, analyzed = xpcall(function()
				return Window.analyze(settings, checkpoint)
			end, function(err)
				return tostring(err)
			end)
			if window ~= frame or revision ~= token then
				return
			end

			running = false
			analyzeButton.TextLabel.Text = "PREVIEW"
			if not ok then
				status.Text = tostring(analyzed):gsub("^.-:%d+: ", "")
				return
			end

			result = analyzed
			showResult(analyzed)
		end)
	end)
	applyButton.Activated:Connect(function()
		if not result or not applyButton.Active then
			return
		end

		local ok, err = pcall(Window.apply, result)
		if ok then
			Window.close()
		else
			invalidate(tostring(err):gsub("^.-:%d+: ", ""))
			render()
		end
	end)
	Chrome.bindDrag(frame, drag, { clamp = true, margin = 8 })
	status:GetPropertyChangedSignal("Text"):Connect(render)
	status:GetPropertyChangedSignal("TextBounds"):Connect(render)
	review:GetPropertyChangedSignal("TextBounds"):Connect(render)
	hint(status, function()
		return result and result.changed == 0 and review and review.Text
			or status and status.Text
			or ""
	end)
	Theme.addRoot(frame)
	Theme.applyTree(frame)
	invalidate()
	render()
	navigation()
	FX.pop(frame)
	local unsubscribe = Theme.onChanged(function()
		if render then
			render()
		end
	end)
	frame.Destroying:Once(unsubscribe)
	return frame
end

function Window.toggle()
	if window then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(options)
	Window.destroy()
	refs = options
	refs.State.AnimationCleanup = Window
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Window.close()
			end
		end)
	)
	table.insert(
		connections,
		options.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not options.AnimatorFrame.Visible then
				Window.close()
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Window.destroy))
	table.insert(connections, options.AnimatorFrame.Destroying:Connect(Window.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Window.destroy))
end

return Window
