--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Drawing = require(script:FindFirstAncestor("Container").Shared.EclipseDrawing)
local DrawingEditor = require(script:FindFirstAncestor("Container").Shared.EclipseDrawingEditor)
local ColorPicker = require("Picker")
local drawingEditor
local drawingTab = "Annotate"
local introductionShown = false

local function introduce()
	if introductionShown then
		return
	end

	local data = require("ProjectData")
	if data.getSetting("GreasePencilIntroductionV1") == true then
		introductionShown = true
		return
	end

	local notice = require("Notification").show(
		"GREASE PENCIL",
		"Grease pencil is INCREDIBLY new. It was a last minute addition. You may encounter issues!! -riftkuro",
		7,
		"GreasePencilFirstOpen"
	)
	if notice then
		introductionShown = true
		data.setSetting("GreasePencilIntroductionV1", true)
	end
end

local Timing = require("Timing")
local TimingEditor = require("TimingEditor")
local Shortcuts = require("Shortcuts")
local Input = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local Tool = require("Tool")
local Path = require("Path")
local Document = require("Document")
local Chunks = require("ChunkStore")
local Preferences = require("Preferences")
local History = require("History")
local Parenting = require("Parenting")
local Policy = require("Policy")
local CameraRig = require("CameraRig")
local LimbIK = require("LimbIK")
local Head = require("HeadStabilizer")
local Graph = require("GraphCurves")
local GraphModel = require("GraphModel")
local Defaults = require("Defaults")
local KeyDefaults = require("KeyframeDefaults")
local Recovery = require("Recovery")
local Run = game:GetService("RunService")
local Pencil = {}
local refs, window, host, wire, highlight, selected, stroke
local strokeCamera
local strokeRender = "EclipseStrokeCamera-" .. Http:GenerateGUID(false)

local function releaseStrokeCamera()
	if strokeCamera then
		strokeCamera.release()
	end
end

local function lockStrokeCamera(camera)
	releaseStrokeCamera()
	if refs.State.BlenderNavigation then
		refs.State.BlenderNavigation.cancelCameraGestures()
	end
	require("Focus").cancel()
	local current = {
		camera = camera,
		frame = camera.CFrame,
		focus = camera.Focus,
		fov = camera.FieldOfView,
		connections = {},
	}
	local release = Recovery.acquire(camera)
	strokeCamera = current
	function current.release()
		if strokeCamera ~= current then
			return
		end
		strokeCamera = nil
		Run:UnbindFromRenderStep(strokeRender)
		for _, connection in current.connections do
			connection:Disconnect()
		end
		release()
	end
	local function maintain()
		if strokeCamera ~= current or current.writing then
			return
		end
		local raw = refs.State.Timeline:GetState()
		if not camera.Parent or workspace.CurrentCamera ~= camera
			or not refs.Active() or not refs.ScreenGui.Enabled or not refs.AnimatorFrame.Visible
			or raw.Playing or raw.Exporting or refs.State.PhysicsSimulating
			or not Pencil.isStrokeActive() or not Recovery.maintain(camera) then
			current.release()
			Pencil.cancelStroke()
			return
		end
		current.writing = true
		local ok, err = pcall(function()
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = current.frame
			camera.Focus = current.focus
			camera.FieldOfView = current.fov
		end)
		current.writing = false
		if not ok then
			current.release()
			Pencil.cancelStroke()
			warn(tostring(err))
		end
	end
	local ok, err = pcall(function()
		for _, property in { "CFrame", "Focus", "CameraType", "FieldOfView" } do
			table.insert(current.connections, camera:GetPropertyChangedSignal(property):Connect(maintain))
		end
		Run:BindToRenderStep(strokeRender, Enum.RenderPriority.Camera.Value + 1, maintain)
		maintain()
	end)
	if not ok then
		current.release()
		error(err)
	end
	return current.release, maintain
end

local drawing = false
local drawingTarget
local physicsTarget, physicsApply, physicsOptions
local physicsTargets = {}
local targetButtons = {}

local function refreshTargets()
	for motor, button in targetButtons do
		local active = table.find(physicsTargets, motor) ~= nil
		button.TextLabel.Text = (active and "☑  " or "☐  ")
			.. (physicsOptions.label and physicsOptions.label(motor) or motor.Part1.Name)
	end
end

local targetStrokes = setmetatable({}, { __mode = "k" })
local smoothing = 50
local hidden = false
local connections = {}
local Notification = require("Notification")

local function data()
	local raw = refs.State.Timeline:GetState()
	raw.GreaseStrokes = raw.GreaseStrokes or {}
	return raw.GreaseStrokes
end

local function target()
	if physicsApply then
		if
			physicsTarget
			and physicsTarget.Parent
			and physicsTarget.Part1
			and physicsTarget.Part1.Parent
		then
			return physicsTarget
		end

		return nil
	end

	local state = refs.State
	local raw = state.Timeline:GetState()
	local items = state.Rig and state.Rig._selectedItems or {}
	local chosen

	local function add(motor)
		if
			not (typeof(motor) == "table" and motor.IsEclipseProperty)
			and motor
			and motor.Parent
			and motor.Part0
			and motor.Part1
			and raw.DefaultPose[motor] ~= nil
			and not CameraRig.isFov(motor)
		then
			if chosen and chosen ~= motor then
				return false
			end

			chosen = motor
		end

		return true
	end

	for item in items do
		if item.fetchMotor and not add(item:fetchMotor()) then
			return nil
		end
	end

	if not chosen then
		for key in raw.SelectedKeyframes or {} do
			if not add(key.Motor) then
				return nil
			end
		end

		for key in raw.SelectedChannelKeyframes or {} do
			if not add(key.Motor) then
				return nil
			end
		end
	end

	return chosen
end

local function selectionChanged()
	local motor = target()
	if drawing and motor ~= drawingTarget then
		drawing = false
		drawingTarget = nil
		stroke = nil
		releaseStrokeCamera()
		Pencil.refresh()
	end

	if window then
		window.target.Text = motor and motor.Part1.Name or "Select a bone or camera"
		if window.targetChoice then
			window.targetChoice.TextLabel.Text = (
				physicsOptions.multiple and (#physicsTargets .. " parts selected")
				or (
					motor
						and (physicsOptions.label and physicsOptions.label(motor) or motor.Part1.Name)
					or "Choose object"
				)
			) .. "  ▾"
		end

		window.draw.Interactable = motor ~= nil
		window.drawText.Text = drawing and "STOP" or "DRAW PATH"
		window.drawText.TextTransparency = motor and 0.1 or 0.65
		window.apply.Interactable = motor ~= nil and selected ~= nil
		window.applyText.TextTransparency = window.apply.Interactable and 0.1 or 0.65
	end

	return motor
end

local function teardown()
	if host then
		host:Destroy()
	end

	host, wire, highlight = nil, nil, nil
end

local function showStatus(message)
	Notification.show("ANNOTATE", message)
end

function Pencil.refresh()
	if drawingEditor then
		drawingEditor:step()
	end

	if not refs then
		return
	end

	if not window then
		teardown()
		return
	end

	if not host or host.Parent ~= workspace.CurrentCamera then
		teardown()
		if not workspace.CurrentCamera then
			return
		end

		host = Instance.new("Folder")
		host.Name = "EclipseGreasePencil"
		host.Archivable = false
		host.Parent = workspace.CurrentCamera
		wire = Instance.new("WireframeHandleAdornment")
		wire.Name = "Strokes"
		wire.Adornee = workspace.Terrain
		wire.AlwaysOnTop = true
		wire.Thickness = 3
		wire.Color3 = Color3.fromRGB(245, 186, 222)
		wire.Parent = host
		highlight = wire:Clone()
		highlight.Name = "SelectedStroke"
		highlight.Color3 = Color3.fromRGB(255, 216, 108)
		highlight.Parent = host
	end

	wire:Clear()
	highlight:Clear()
	wire.Visible = not hidden and refs.Active() and not refs.State.PresentationHidden
	highlight.Visible = wire.Visible
	local ids = {}
	for id in data() do
		table.insert(ids, id)
	end

	table.sort(ids)
	if not selected or not data()[selected] then
		selected = ids[#ids]
	end

	for id, entry in data() do
		local points = Path.smooth(entry.points, entry.smoothing)
		local targetWire = id == selected and highlight or wire
		for i = 2, #points do
			targetWire:AddLine(points[i - 1], points[i])
		end
	end

	if stroke then
		for i = 2, #stroke.points do
			wire:AddLine(stroke.points[i - 1], stroke.points[i])
		end
	end

	if window then
		window.drawText.Text = drawing and "STOP" or "DRAW"
		window.showText.Text = hidden and "SHOW" or "HIDE"
		selectionChanged()
		window.strokeLabel.Text = #ids == 0 and "No strokes"
			or "Stroke " .. tostring(table.find(ids, selected)) .. " / " .. #ids
	end
end

function Pencil.isDrawing()
	return drawing or drawingEditor and drawingEditor:isDrawing() or false
end

function Pencil.isStrokeActive()
	return stroke ~= nil or drawingEditor and drawingEditor.pending ~= nil or false
end

function Pencil.isOpen()
	return window ~= nil
end

function Pencil.presentationChanged()
	Pencil.refresh()
end

function Pencil.cancelStroke()
	if drawingEditor then
		drawingEditor:cancel()
		drawingEditor.mode = "Select"
		drawingEditor:refresh()
	end

	stroke = nil

	releaseStrokeCamera()
	drawing = false
	drawingTarget = nil
	Pencil.refresh()
end

local function recordStrokes(before, after, label)
	local raw = refs.State.Timeline:GetState()

	local function restore(value)
		raw.GreaseStrokes = Document.unpack(value)
		refs.State.currentProjectSaved = false
		Pencil.refresh()
	end

	restore(after)
	History.record(function()
		restore(before)
	end, function()
		restore(after)
	end, label)
end

local function overUI(point)
	for _, object in game:GetService("CoreGui"):GetGuiObjectsAtPosition(point.X, point.Y) do
		if object.Active and object.Visible then
			return true
		end
	end

	return false
end

local function beginStroke()
	if drawingEditor and drawingEditor.visible then
		drawingEditor:begin()
		return
	end

	if not drawing then
		return
	end

	local motor = selectionChanged()
	if not motor or motor ~= drawingTarget then
		return
	end

	if not drawing or not refs.Active() or Input:GetFocusedTextBox() then
		return
	end

	local point = Input:GetMouseLocation()
	if overUI(point) then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local origin = (motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()).Position
	local normal = camera.CFrame.LookVector
	local hit = Path.intersect(camera:ScreenPointToRay(point.X, point.Y), origin, normal)
	if not hit then
		return
	end

	stroke = {
		motor = motor,
		origin = origin,
		normal = normal,
		points = { hit },
		camera = camera,
		last = point,
	}
	stroke.releaseCamera, stroke.holdCamera = lockStrokeCamera(camera)
end

local function moveStroke()
	if drawingEditor and drawingEditor.visible then
		drawingEditor:move()
		return
	end

	if not drawing then
		return
	end

	selectionChanged()
	if not stroke or workspace.CurrentCamera ~= stroke.camera then
		return
	end

	stroke.holdCamera()
	if not stroke then
		return
	end
	local point = Input:GetMouseLocation()
	if (point - stroke.last).Magnitude < 3 then
		return
	end

	local hit = Path.intersect(
		stroke.camera:ScreenPointToRay(point.X, point.Y),
		stroke.origin,
		stroke.normal
	)
	if hit then
		if #stroke.points >= 1024 then
			stroke.points = Path.resample(stroke.points, 512)
		end

		table.insert(stroke.points, hit)
		stroke.last = point
		Pencil.refresh()
	end
end

local function finishStroke()
	if drawingEditor and drawingEditor.visible then
		drawingEditor:finish()
		return
	end

	if not stroke then
		return
	end

	selectionChanged()
	if not stroke then
		return
	end

	local points = stroke.points
	stroke = nil
	releaseStrokeCamera()
	if #points < 2 then
		Pencil.refresh()
		return
	end

	local before = Document.pack(data())
	local nextData = Document.unpack(before)
	selected = Http:GenerateGUID(false)
	nextData[selected] = { points = points, smoothing = smoothing }
	recordStrokes(before, Document.pack(nextData), "Draw annotation stroke")
	showStatus("Path captured.")
end

function Pencil.apply(motor, points, first, last, step, offset, easing)
	Timing.validate(easing)
	local state = refs.State
	local timeline = state.Timeline
	local raw = timeline:GetState()
	assert(refs.Active() and not raw.Playing, "Stop playback before applying a path")
	assert(
		Policy.channelsEnabled(),
		"Enable Transform Channels in Preferences before applying a path"
	)
	assert(
		not state.BlenderBridge or not state.BlenderBridge.isLocked(),
		"Turn Blender Live off first"
	)
	assert(
		motor and motor.Parent and motor.Part0 and motor.Part1 and not CameraRig.isFov(motor),
		"Select a bone or camera transform track"
	)
	assert(
		not (typeof(motor) == "table" and motor.IsEclipseArmatureControl),
		"Use an output bone or camera track for Apply Path"
	)
	assert(
		first
			and last
			and step
			and first % 1 == 0
			and last % 1 == 0
			and step % 1 == 0
			and first >= 0
			and last > first
			and last <= 1000000
			and step >= 1,
		"Enter whole frames: End after Start, Step at least 1"
	)
	assert(math.ceil((last - first) / step) <= 5000, "Increase Step to use at most 5000 path keys")
	local motors = {}
	for candidate in raw.DefaultPose do
		table.insert(motors, candidate)
	end

	local evaluator = Parenting.newEvaluator(
		motors,
		Policy.activeTracks(raw.Keyframes),
		raw.DefaultPose,
		raw.DefaultWorldPose,
		raw.ParentingDefaults,

		function(candidate, time)
			return timeline:EvaluateMotorC0(candidate, time)
		end
	)
	local frames = {}
	for frame = first, last, step do
		table.insert(frames, frame)
	end

	if frames[#frames] ~= last then
		table.insert(frames, last)
	end

	local included = {}
	for _, frame in frames do
		included[frame] = true
	end

	for frame in raw.Keyframes[motor] or {} do
		if frame > first and frame < last and not included[frame] then
			table.insert(frames, frame)
		end
	end

	table.sort(frames)
	local positions = {}
	for i, frame in frames do
		positions[i] = Path.at(points, Timing.sample(easing, (frame - first) / (last - first)))
	end

	local shift = offset == true
			and evaluator.worldAt(motor, first / raw.FPS).Position - positions[1]
		or Vector3.zero
	local before = timeline:_snapshotMotorBucket(motor)
	local after = Document.unpack(Document.pack(before))
	for frame, key in after do
		key.Motor = motor
		key.Part = motor.Part1
		key.SanitizeName = state.UIHelpers.SanitizeName
		if not key.Channels and not key.GraphOnly then
			timeline:EnsureChannelsPopulated(key)
		end
	end

	local scratch = table.clone(raw)
	scratch.Keyframes = table.clone(raw.Keyframes)
	scratch.Keyframes[motor] = after
	local privateTimeline = setmetatable({
		GetState = function()
			return scratch
		end,
	}, {
		__index = function(_, key)
			local value = timeline[key]
			return type(value) == "function"
					and function(_, ...)
						return value(timeline, ...)
					end
				or value
		end,
	})
	local model = GraphModel.new({ Timeline = privateTimeline })
	for _, track in model:tracks({ motor }) do
		if track.group == "Position" then
			model:_adopt(track)
		end
	end

	for i, frame in frames do
		local time = frame / raw.FPS
		assert(
			not LimbIK.isDriven(motor, time) and not Head.isEnabled(motor, time),
			"Turn off IK or head stabilization on this track before applying a path"
		)
		assert(evaluator.isParentedAt(motor, time), "Use a parented track for Apply Path")
		local world = evaluator.worldAt(motor, time)
		local c0 = Path.localPose(
			evaluator.parentWorldAt(motor, time),
			world,
			positions[i] + shift,
			motor.C1
		)
		local key = after[frame]
		if not key then
			key = KeyDefaults.new(after, frame)
			key.Frame, key.Time, key.C0 = frame, time, timeline:EvaluateMotorC0(motor, time)
			key.Motor, key.Part, key.SanitizeName = motor, motor.Part1, state.UIHelpers.SanitizeName
			key.Parented, key.GraphOnly = true, true
			key.EasingStyle = key.EasingStyle or Defaults.EasingStyle
			key.EasingDirection = key.EasingDirection or Defaults.EasingDirection
			key.HandleType = key.HandleType or Defaults.HandleType
			if key.EasingStyle == "Bezier" and not key.BezierPoints then
				key.BezierPoints = Graph.clone(Defaults.BezierPoints)
			end
		end

		key.C0 = CFrame.new(c0.Position) * key.C0.Rotation
		key.Position = key.C0.Position
		key.Rotation = key.C0.Rotation
		key.BlenderCurve, key.BlenderSource, key.PathTangentIn, key.PathTangentOut =
			nil, nil, nil, nil
		key.GraphCurves = key.GraphCurves or {}
		key.Channels = key.Channels or {}
		for id, value in { loc_x = c0.X, loc_y = c0.Y, loc_z = c0.Z } do
			key.Channels[id] = { Value = value }
			local oldPoint = key.GraphCurves[id]
			local style = typeof(key.EasingStyle) == "EnumItem" and key.EasingStyle.Name
				or key.EasingStyle
			local native = typeof(key.EasingStyle) == "EnumItem"
				and key.EasingStyle.EnumType == Enum.PoseEasingStyle
			local interpolation = style == "Bezier" and "Bezier"
				or (style == "Linear" or style == "Constant" and not native) and style
				or "Legacy"
			key.GraphCurves[id] = {
				Value = value,
				Interpolation = oldPoint and oldPoint.Interpolation or interpolation,
				HandleType = oldPoint and oldPoint.HandleType or key.HandleType,
				Easing = oldPoint and Graph.clone(oldPoint.Easing) or {
					EasingStyle = style,
					NativePose = native,
					EasingDirection = key.EasingDirection,
					BezierPoints = Graph.clone(key.BezierPoints),
					Overshoot = key.Overshoot,
					Amplitude = key.Amplitude,
					Period = key.Period,
				},
			}
		end

		after[frame] = key
	end

	local functionRestore = function(bucket)
		timeline:_restoreMotorBucket(motor, bucket)
		if state.currentRig then
			timeline:ApplyPoseAtTime(state.currentRig, raw.CurrentTime)
		end

		if state.GraphEditor then
			state.GraphEditor.invalidate()
		end

		state.currentProjectSaved = false
		Pencil.refresh()
	end

	local ok, err = pcall(functionRestore, after)
	if not ok then
		functionRestore(before)
		error(err)
	end

	timeline:EnsureTimelineEnd(last)
	History.record(function()
		functionRestore(before)
	end, function()
		functionRestore(after)
	end, "Apply drawn path")
	return #frames
end

function Pencil.closePhysics()
	if physicsApply then
		Pencil.close()
	end
end

function Pencil.close()
	if drawingEditor then
		drawingEditor:cancel()
	end
	TimingEditor.close()
	physicsTarget, physicsApply, physicsOptions = nil, nil, nil
	physicsTargets = {}
	targetButtons = {}
	drawing = false
	drawingTarget = nil
	stroke = nil
	releaseStrokeCamera()
	if window then
		local old = window
		window = nil
		old:close()
	end

	Pencil.refresh()
end

function Pencil.chooseTarget(motor)
	assert(
		physicsOptions and table.find(physicsOptions.targets, motor),
		"choose an object from the list"
	)
	assert(motor.Parent and motor.Part1 and motor.Part1.Parent, "that object was removed")
	if physicsTarget and physicsTarget.Part1 then
		targetStrokes[physicsTarget.Part1] = selected
	end

	physicsTarget = motor
	physicsTargets = { motor }
	selected = targetStrokes[motor.Part1]
	drawing = false
	drawingTarget = nil
	stroke = nil
	releaseStrokeCamera()
	if window and window.targetList then
		window.targetList.Visible = false
	end

	Pencil.refresh()
end

function Pencil.open(guideMotor, onGuide, options)
	if window then
		if onGuide then
			Pencil.close()
		else
			return
		end
	end

	physicsTarget, physicsApply, physicsOptions = guideMotor, onGuide, options
	physicsTargets = options and options.selected and table.clone(options.selected)
		or (guideMotor and { guideMotor } or {})
	targetButtons = {}
	if guideMotor and guideMotor.Part1 and targetStrokes[guideMotor.Part1] then
		selected = targetStrokes[guideMotor.Part1]
	end

	assert(refs.Active(), "Open an Eclipse file first")
	smoothing = Preferences.get("GreasePencilSmoothing") or 50
	window = Tool.new(
		refs,
		"EclipseGreasePencilWindow",
		physicsApply and "ANNOTATE - PHYSICS" or "DRAWING",
		physicsApply and Vector2.new(320, 240) or Vector2.new(320, 344),
		false,

		function()
			TimingEditor.close()
			if drawingEditor then
				drawingEditor:setVisible(false)
				drawingEditor:unmount()
			end

			window = nil
			drawing = false
			drawingTarget = nil
			stroke = nil
			releaseStrokeCamera()
			physicsTarget = nil
			physicsApply = nil
			physicsOptions = nil
			Pencil.refresh()
		end
	)
	local rootFrame = window.frame
	local frame = rootFrame
	local header = rootFrame:FindFirstChild("Header")
	if header then
		header.Title.Position = UDim2.fromOffset(12, 0)
		header.Title.TextYAlignment = Enum.TextYAlignment.Center
		header.Title.TextSize = 13
	end

	if not physicsApply then
		frame = Tool.make("Frame", rootFrame, "AnnotationPanel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.fromOffset(320, 310),
		})
		drawingEditor:mount(rootFrame)

		local function resizeDrawing()
			local grease = drawingTab == "Grease Pencil"
			local size = grease and Vector2.new(412, drawingEditor.advanced and 564 or 484)
				or Vector2.new(320, 344)
			rootFrame.MinimumSize.MinSize = size
			rootFrame.Size = UDim2.fromOffset(size.X, size.Y)
			local tabWidth = (size.X - 30) / 2
			rootFrame.TabBar.AnnotateTab.Size = UDim2.fromOffset(tabWidth, 26)
			rootFrame.TabBar.GreaseTab.Size = UDim2.fromOffset(tabWidth, 26)
			rootFrame.TabBar.GreaseTab.Position = UDim2.fromOffset(3 + tabWidth, 3)
			for _, name in { "AnnotateTab", "GreaseTab" } do
				local button = rootFrame.TabBar[name]
				local active = (name == "GreaseTab") == grease
				button:SetAttribute("ThemeBgTransparency", active and 0 or 1)
				button:SetAttribute("Primary", active)
				button.TextLabel:SetAttribute("ThemeTxtTransparency", active and 0 or 0.35)
				button.BackgroundTransparency = active and 0 or 1
				button.TextLabel.TextTransparency = active and 0 or 0.35
			end

			header.Title.Text = grease and "GREASE PENCIL" or "ANNOTATE"
		end

		drawingEditor.onLayout = resizeDrawing

		local function selectTab(tab)
			Pencil.cancelStroke()
			drawingTab = tab
			frame.Visible = tab == "Annotate"
			drawingEditor:setVisible(tab == "Grease Pencil")
			resizeDrawing()
			if tab == "Grease Pencil" then
				introduce()
			end
		end

		local tabBar = Tool.make("Frame", rootFrame, "TabBar", {
			Position = UDim2.fromOffset(12, 32),
			Size = UDim2.new(1, -24, 0, 32),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		})
		tabBar:SetAttribute("ThemeBg", "Top")
		tabBar:SetAttribute("EclipseTabBar", true)
		Tool.make("UICorner", tabBar, "Corner", { CornerRadius = UDim.new(0, 5) })
		local outline = Tool.make("UIStroke", tabBar, "Outline", { Thickness = 1 })
		outline:SetAttribute("ThemeStrk", "Strk")
		Tool.button(
			tabBar,
			"AnnotateTab",
			"ANNOTATE",
			UDim2.fromOffset(3, 3),
			UDim2.fromOffset(190, 26),

			function()
				selectTab("Annotate")
			end
		)
		Tool.button(
			tabBar,
			"GreaseTab",
			"GREASE PENCIL",
			UDim2.fromOffset(193, 3),
			UDim2.fromOffset(190, 26),

			function()
				selectTab("Grease Pencil")
			end
		)
		frame.Visible = drawingTab == "Annotate"
		drawingEditor:setVisible(drawingTab == "Grease Pencil")
		resizeDrawing()
		if drawingTab == "Grease Pencil" then
			introduce()
		end
	end

	window.target =
		Tool.label(frame, "Target", "", UDim2.fromOffset(12, 36), UDim2.new(1, -24, 0, 22))
	if physicsOptions and #physicsOptions.targets > 1 then
		window.target.Visible = false
		window.targetList = Tool.make("ScrollingFrame", frame, "Targets", {
			Position = UDim2.fromOffset(12, 62),
			Size = UDim2.new(1, -24, 0, 138),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = 80,
			Visible = false,
		})
		window.targetList:SetAttribute("ThemeBg", "Pnl")
		Tool.make(
			"UIListLayout",
			window.targetList,
			"Layout",
			{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }
		)
		window.targetChoice = Tool.button(
			frame,
			"TargetChoice",
			"CHOOSE OBJECT",
			UDim2.fromOffset(12, 36),
			UDim2.new(1, -24, 0, 24),

			function()
				window.targetList.Visible = not window.targetList.Visible
			end
		)
		window.targetChoice.TextLabel.TextWrapped = false
		window.targetChoice.TextLabel.TextTruncate = Enum.TextTruncate.AtEnd
		if physicsOptions.multiple then
			local all = Tool.button(
				window.targetList,
				"SelectAll",
				"SELECT ALL",
				UDim2.new(),
				UDim2.new(1, -4, 0, 26),

				function()
					physicsTargets = table.clone(physicsOptions.targets)
					physicsTarget = physicsTargets[1]
					refreshTargets()
					selectionChanged()
				end
			)
			all.LayoutOrder = -2
			local done = Tool.button(
				window.targetList,
				"DoneTargets",
				"DONE",
				UDim2.new(),
				UDim2.new(1, -4, 0, 26),

				function()
					window.targetList.Visible = false
				end
			)
			done.LayoutOrder = 10000
		end

		for i, motor in physicsOptions.targets do
			local text = physicsOptions.label and physicsOptions.label(motor) or motor.Part1.Name
			local button, label = Tool.button(
				window.targetList,
				"Target" .. i,
				text,
				UDim2.new(),
				UDim2.new(1, -4, 0, 26),

				function()
					if not physicsOptions.multiple then
						Pencil.chooseTarget(motor)
						return
					end

					local at = table.find(physicsTargets, motor)
					if at then
						table.remove(physicsTargets, at)
					else
						table.insert(physicsTargets, motor)
					end

					physicsTarget = physicsTargets[1]
					drawing = false
					drawingTarget = nil
					stroke = nil
					releaseStrokeCamera()
					refreshTargets()
					selectionChanged()
				end
			)
			targetButtons[motor] = button
			button.LayoutOrder = i
			label.TextWrapped = false
			label.TextTruncate = Enum.TextTruncate.AtEnd
		end

		if physicsOptions.multiple then
			refreshTargets()
		end
	end

	window.draw, window.drawText = Tool.button(
		frame,
		"Draw",
		"DRAW PATH",
		UDim2.fromOffset(12, 66),
		UDim2.fromOffset(128, 26),

		function()
			refs.Finalize()
			local motor = target()
			if not motor then
				showStatus("Select one bone or camera track first.")
				return
			end

			drawing = not drawing
			drawingTarget = drawing and motor or nil
			stroke = nil
			releaseStrokeCamera()
			if drawing then
				refs.State.Timeline:GetState().Playing = false
			end

			showStatus(drawing and "Drag in the viewport. Esc stops drawing." or "Drawing stopped.")
			Pencil.refresh()
		end
	)
	window.show, window.showText = Tool.button(
		frame,
		"Show",
		"HIDE",
		UDim2.fromOffset(148, 66),
		UDim2.fromOffset(76, 26),

		function()
			hidden = not hidden
			Pencil.refresh()
		end
	)
	Tool.button(frame, "Erase", "ERASE", UDim2.fromOffset(232, 66), UDim2.fromOffset(76, 26), function()
		if not selected then
			showStatus("Draw a stroke first.")
			return
		end

		local before = Document.pack(data())
		local after = Document.unpack(before)
		after[selected] = nil
		recordStrokes(before, Document.pack(after), "Erase annotation stroke")
		selected = nil
	end
)
	Tool.label(
		frame,
		"SmoothLabel",
		"Smoothing (%)",
		UDim2.new(1, -220, 0, 130),
		UDim2.fromOffset(118, 24)
	).TextXAlignment =
		Enum.TextXAlignment.Right
	local smooth = Tool.field(
		frame,
		"Smoothing",
		smoothing,
		UDim2.new(1, -94, 0, 130),
		UDim2.fromOffset(82, 24)
	)
	require("NumericInput").connect(smooth, { step = 0.1, min = 0 }, function()
		local value = tonumber(smooth.Text)
		if value and value == value and value >= 0 and value <= 100 then
			smoothing = value
			if selected and data()[selected] then
				local before = Document.pack(data())
				local after = Document.unpack(before)
				after[selected].smoothing = value
				recordStrokes(before, Document.pack(after), "Smooth annotation stroke")
			end
		end

		smooth.Text = tostring(smoothing)
		Pencil.refresh()
	end)
	Tool.button(
		frame,
		"PathTiming",
		"PATH TIMING",
		UDim2.fromOffset(12, 162),
		UDim2.new(1, -24, 0, 26),

		function()
			local id = selected
			local entry = id and data()[id]
			if not entry then
				showStatus("draw a path first")
				return
			end

			local raw = refs.State.Timeline:GetState()
			local strokes = raw.GreaseStrokes
			TimingEditor.open(refs, entry.easing, function(easing)
				assert(
					window and raw.GreaseStrokes == strokes and data()[id],
					"reopen the drawing to edit its timing"
				)
				local before = Document.pack(data())
				local after = Document.unpack(before)
				after[id].easing = easing
				recordStrokes(before, Document.pack(after), "Edit path timing")
			end)
		end
	)
	local divider = Tool.make("Frame", frame, "Divider", {
		Position = UDim2.fromOffset(12, 198),
		Size = UDim2.new(1, -24, 0, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(69, 41, 93),
	})
	divider:SetAttribute("ThemeBg", "Div")
	window.strokeLabel =
		Tool.label(frame, "Stroke", "", UDim2.fromOffset(42, 100), UDim2.new(1, -84, 0, 24))
	window.strokeLabel.TextXAlignment = Enum.TextXAlignment.Center

	local function selectStroke(delta)
		local ids = {}
		for id in data() do
			table.insert(ids, id)
		end

		table.sort(ids)
		if #ids == 0 then
			return
		end

		selected = ids[((table.find(ids, selected) or 1) - 1 + delta) % #ids + 1]
		smoothing = data()[selected].smoothing
		smooth.Text = tostring(smoothing)
		Pencil.refresh()
	end

	Tool.button(frame, "PreviousStroke", "<", UDim2.fromOffset(12, 100), UDim2.fromOffset(24, 24), function()
		selectStroke(-1)
	end
)
	Tool.button(frame, "NextStroke", ">", UDim2.new(1, -36, 0, 100), UDim2.fromOffset(24, 24), function()
		selectStroke(1)
	end
)
	local current = refs.State.Timeline:TimeToFrame(refs.State.Timeline:GetState().CurrentTime)
	local fields = {}
	for i, entry in { { "Start", current }, { "End", current + 60 } } do
		local x = 12 + (i - 1) * 154
		Tool.label(
			frame,
			entry[1] .. "Label",
			entry[1],
			UDim2.fromOffset(x, 208),
			UDim2.fromOffset(44, 24)
		)
		fields[i] = Tool.field(
			frame,
			entry[1],
			entry[2],
			i == 2 and UDim2.new(1, -94, 0, 208) or UDim2.fromOffset(x + 48, 208),
			UDim2.fromOffset(i == 2 and 82 or 94, 24)
		)
		if i == 2 then
			local label = frame:FindFirstChild("EndLabel")
			label.Position = UDim2.new(1, -146, 0, 208)
			label.TextXAlignment = Enum.TextXAlignment.Right
		end
	end

	Tool.label(
		frame,
		"SpacingLabel",
		"Key spacing (frames)",
		UDim2.fromOffset(12, 242),
		UDim2.fromOffset(180, 24)
	)
	fields[3] = Tool.field(frame, "Spacing", 4, UDim2.new(1, -94, 0, 242), UDim2.fromOffset(82, 24))

	window.apply, window.applyText = Tool.button(
		frame,
		"Apply",
		"APPLY PATH",
		UDim2.new(0, 12, 1, -38),
		UDim2.new(1, -24, 0, 26),

		function()
			drawing = false
			finishStroke()
			local ok, result = pcall(function()
				local entry = selected and data()[selected]
				assert(entry, "Draw a path first")
				if physicsApply then
					local motor = target()
					assert(motor, "select parts for the path first")
					physicsApply(
						motor,
						Path.smooth(entry.points, entry.smoothing),
						entry.easing,
						table.clone(physicsTargets)
					)
					for _, picked in physicsTargets do
						targetStrokes[picked.Part1] = selected
					end

					return "guide"
				end

				return Pencil.apply(
					target(),
					Path.smooth(entry.points, entry.smoothing),
					tonumber(fields[1].Text),
					tonumber(fields[2].Text),
					tonumber(fields[3].Text),
					false,
					entry.easing
				)
			end)
			showStatus(
				ok
						and (result == "guide" and "Path ready. Go back to Physics and simulate." or tostring(
							result
						) .. " path keys added.")
					or tostring(result):gsub("^.-:%d+: ", "")
			)
			Pencil.refresh()
		end
	)
	if physicsApply then
		frame.Size = UDim2.fromOffset(320, 240)
		for _, name in
			{ "Divider", "StartLabel", "EndLabel", "Start", "End", "SpacingLabel", "Spacing" }
		do
			local child = frame:FindFirstChild(name)
			if child then
				child.Visible = false
			end
		end

		window.applyText.Text = "USE FOR PHYSICS"
		window.apply:SetAttribute("ThemeBg", "MenuSel")
		require("Theme").applyInstance(window.apply)
		if physicsOptions and physicsOptions.clear then
			Tool.button(
				frame,
				"ClearTargetPath",
				"CLEAR PATH",
				UDim2.fromOffset(12, 130),
				UDim2.fromOffset(94, 24),

				function()
					local ok, err = pcall(function()
						assert(target(), "choose an object first")
						for _, motor in physicsTargets do
							physicsOptions.clear(motor)
						end
					end)
					if not ok then
						showStatus(tostring(err):gsub("^.-:%d+: ", ""))
					end
				end
			)
		end
	end

	Pencil.refresh()
	local opened = window
	task.spawn(function()
		while window == opened and not opened.closed do
			task.wait(0.3)
			if window == opened then
				selectionChanged()
			end
		end
	end)
end

function Pencil.toggle()
	if window then
		Pencil.close()
	else
		Pencil.open()
	end
end

function Pencil.write(save)
	local value = Drawing.validate(refs.State.Timeline:GetState().GreaseDrawings or Drawing.empty())
	if #value.layers == 0 then
		local old = save:FindFirstChild("EclipseDrawingsV1")
		if old then
			old:Destroy()
		end
	end

	if #value.layers > 0 then
		Chunks.write(save, "EclipseDrawingsV1", Document.pack(value))
	end

	if next(data()) then
		Chunks.write(save, "EclipseGreasePencil", Document.pack(data()))
	end
end

function Pencil.load(save)
	local visual = save and save:FindFirstChild("EclipseDrawingsV1")
	local value = visual and Drawing.validate(Document.unpack(Chunks.read(visual)))
		or Drawing.empty()
	refs.State.Timeline:GetState().GreaseDrawings = value
	if drawingEditor then
		drawingEditor:cancel()
		drawingEditor.selected = nil
		drawingEditor:refresh()
	end

	TimingEditor.close()
	local restored = {}
	local source = save and save:FindFirstChild("EclipseGreasePencil")
	if source then
		local ok, result = pcall(function()
			return Path.validate(Document.unpack(Chunks.read(source)))
		end)
		if ok then
			restored = result
		end
	end

	refs.State.Timeline:GetState().GreaseStrokes = restored
	selected = next(restored)
	drawing = false
	stroke = nil
	releaseStrokeCamera()
	Pencil.refresh()
end

function Pencil.destroy()
	if drawingEditor then
		drawingEditor:destroy()
		drawingEditor = nil
	end

	TimingEditor.close()
	physicsTarget, physicsApply, physicsOptions = nil, nil, nil
	if window then
		local old = window
		window = nil
		old:close(true)
	end

	drawing = false
	stroke = nil
	releaseStrokeCamera()
	teardown()
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

function Pencil.init(options)
	refs = options
	drawingEditor = DrawingEditor.new({
		refs = refs,
		Tool = Tool,
		History = History,
		Picker = ColorPicker,
		Path = Path,
		overUI = overUI,
		lockCamera = lockStrokeCamera,
		notify = function(message)
			Notification.showOnce("DRAWING", message, 5)
		end,
	})
	table.insert(
		connections,
		game:GetService("RunService").RenderStepped:Connect(function()
			if drawingEditor then
				drawingEditor:step()
			end
		end)
	)
	refs.State.GreasePencil = Pencil
	for _, camera in workspace:GetChildren() do
		if camera:IsA("Camera") then
			for _, child in camera:GetChildren() do
				if child.Name == "EclipseGreasePencil" then
					child:Destroy()
				end
			end
		end
	end

	local mouse = refs.Plugin:GetMouse()
	table.insert(connections, mouse.Button1Down:Connect(beginStroke))
	table.insert(connections, mouse.Button1Up:Connect(finishStroke))
	table.insert(
		connections,
		Input.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				finishStroke()
			end
		end)
	)
	table.insert(connections, mouse.Move:Connect(moveStroke))
	table.insert(
		connections,
		Input.InputBegan:Connect(function(input)
			if Shortcuts.matches("Cancel", input) and Pencil.isDrawing() then
				Pencil.cancelStroke()
			end
		end)
	)
	table.insert(connections, Input.WindowFocusReleased:Connect(Pencil.cancelStroke))
	table.insert(
		connections,
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			Pencil.cancelStroke()
		end)
	)
	table.insert(
		connections,
		refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then
				Pencil.close()
			end
		end)
	)
	table.insert(
		connections,
		refs.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not refs.AnimatorFrame.Visible then
				Pencil.close()
			end
		end)
	)
	refs.ScreenGui.Destroying:Once(Pencil.destroy)
	refs.Plugin.Unloading:Once(Pencil.destroy)
end

return Pencil
