--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Shortcuts = require("Shortcuts")

local Tracks = require("Properties")
local Input = require("UserInputService")
local Edit = require("BlenderEdit")
local History = require("History")
local Cursor = require("RotateCursor")
local Run = game:GetService("RunService")
local Preferences = require("Preferences")
local Resize = require("Resize")
local Gizmo = {}

local function read(motor)
	if motor.IsEclipseScaleAdapter then
		return motor.read()
	end

	return Tracks.readValue(motor.Rig, motor.PropertyId)
end

local function write(motor, value, saved, offset)
	if motor.IsEclipseScaleAdapter then
		motor.write(value, saved, offset)
	else
		Tracks.setValue(motor, value)
		if saved and saved.placement then
			Resize.placeProperty(motor, saved, offset or Vector3.zero)
		end
	end
end

local refs, target, visual, drag, connection
local targets
local connections = {}
local handles = {}
local visualConnections = {}
local hovered, hoverMouse, previousIcon, hoverIcon

local function clearHover()
	if hoverMouse and hoverIcon and hoverMouse.Icon == hoverIcon then
		hoverMouse.Icon = previousIcon
	end

	hovered, hoverMouse, previousIcon, hoverIcon = nil, nil, nil, nil
end

local function setHover(handle, camera, center)
	if not handle then
		clearHover()
		return
	end

	local position = camera:WorldToViewportPoint(handle.part.Position)
	local pivot = camera:WorldToViewportPoint(center)
	local delta = Vector2.new(position.X - pivot.X, position.Y - pivot.Y)
	local icon
	if math.abs(delta.Y) < math.abs(delta.X) * 0.5 then
		icon = "SizeEW"
	elseif math.abs(delta.X) < math.abs(delta.Y) * 0.5 then
		icon = "SizeNS"
	elseif delta.X * delta.Y > 0 then
		icon = "SizeNWSE"
	else
		icon = "SizeNESW"
	end

	icon = "rbxasset://SystemCursors/" .. icon
	if hovered ~= handle or hoverIcon ~= icon then
		clearHover()
		hovered = handle
		hoverMouse = refs.Plugin:GetMouse()
		local _, iconBefore = require("Cursor").snapshot(hoverMouse)
		previousIcon = iconBefore
		hoverIcon = icon
		hoverMouse.Icon = icon
	end
end

local function hit(camera, mouse)
	local nearest, distance = nil, math.huge
	for _, handle in handles do
		local point, onScreen = camera:WorldToViewportPoint(handle.part.Position)
		local gap = (Vector2.new(point.X, point.Y) - mouse).Magnitude
		if onScreen and gap <= (handle.hitRadius or 14) and gap < distance then
			nearest, distance = handle, gap
		end
	end

	return nearest
end

local function destroyVisual()
	clearHover()
	for _, item in visualConnections do
		item:Disconnect()
	end

	table.clear(visualConnections)
	if visual then
		visual:Destroy()
		visual = nil
	end

	table.clear(handles)
end

local function facial(motor)
	return motor and motor.Definition and motor.Definition.facial == true
end

local function bounds(rig, motor)
	if facial(motor) then
		local face = Tracks.faceControls(rig)
		local head = face and face:FindFirstAncestorWhichIsA("BasePart")
		if head then return head.CFrame, head.Size end
	end
	return Resize.bounds(rig)
end

function Gizmo.faceValue(initial, delta, numeric)
	return math.clamp(tonumber(numeric) or initial + delta / 160, 0, 1)
end

local function available()
	return refs
		and target
		and target.Parent
		and target.Rig.Parent
		and (target.IsEclipseScaleAdapter or Tracks.enabled(target.Rig, target.PropertyId))
		and (facial(target) or target.PropertyId == "CFrame" or Preferences.get("ScaleGizmo") ~= false)
		and not Edit.blocked()
		and (not refs.State.PresentationHidden or refs.State.CameraPoseMode and not refs.State.CameraBonesHidden)
		and refs.Active()
		and not refs.State.Timeline:GetState().Playing
		and refs.ScreenGui.Enabled
		and (refs.AnimatorFrame.Visible or refs.State.CameraPoseMode)
end

function Gizmo.isEditing()
	return drag ~= nil
end

function Gizmo.finish(cancel)
	if not drag then
		return false
	end

	if not cancel and (drag.mode == "pointer" or drag.mode == "handles") then
		Gizmo.change(Input:GetMouseLocation())
	end

	local saved = drag
	drag = nil
	if saved.motor.PropertyId == "CFrame" then
		local axis = refs.State.Axis
		axis:StopBlenderRotate(cancel)
		axis:StopBlenderGrab()
		axis:StopDrag()
	end

	if saved.mode == "pointer" or saved.mode == "handles" then
		Cursor.stop()
	end

	clearHover()
	local motor = saved.motor
	if not motor.Parent and not saved.group then
		return true
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	if motor.IsEclipseScaleAdapter then
		motor.finish(saved, cancel)
		return true
	end

	if saved.placement then
		Resize.finishProperty(refs, saved, cancel)
		return true
	end

	if saved.group then
		local before, after = {}, {}
		local recording = timeline:IsRecording()
		local changed = false
		for _, entry in saved.group do
			if entry.motor.Parent and entry.motor.Rig.Parent and read(entry.motor) ~= entry.value then changed = true break end
		end
		if not cancel and not changed then
			refs.State.Axis:RefreshAxis()
			return true
		end
		for _, entry in saved.group do
			local member = entry.motor
			if not member.Parent or not member.Rig.Parent then continue end
			local value = read(member)
			changed = changed or value ~= entry.value
			if cancel then
				Tracks.setValue(member, entry.value)
			elseif recording then
				before[member] = timeline:_snapshotMotorBucket(member)
				timeline:RecordKeyframeForMotorAtCurrentTime(member.Part1, member, Tracks.encode(value), { Frame = saved.frame, PropertyValue = value }, refs.State.UIHelpers.SanitizeName)
				after[member] = timeline:_snapshotMotorBucket(member)
			else
				before[member] = { value = entry.value, default = entry.default }
				after[member] = { value = value, default = value }
			end
		end
		local function apply(values)
			for member, data in values do
				if not member.Parent or not member.Rig.Parent then continue end
				if recording then
					timeline:_restoreMotorBucket(member, data)
				else
					member.Part1:SetAttribute("Default", require("Document").pack(data.default))
					raw.DefaultPose[member] = Tracks.encode(data.default)
					Tracks.setValue(member, data.value)
				end
			end
			if recording then
				for member in values do
					if member.Parent and member.Rig.Parent then timeline:ApplyPoseAtTime(member.Rig, raw.CurrentTime, { OnlyRig = true }) end
				end
			end
			refs.State.currentProjectSaved = false
		end
		if not cancel and changed then
			apply(after)
			History.record(function() apply(before) end, function() apply(after) end, "Transform selected parts")
		end
		refs.State.Axis:RefreshAxis()
		return true
	end
	if cancel then
		Tracks.setValue(motor, saved.value)
		if motor.PropertyId == "CFrame" then
			refs.State.Axis:RefreshAxis()
		end

		return true
	end

	local value = Tracks.readValue(motor.Rig, motor.PropertyId)
	if value == saved.value then
		return true
	end

	require("HumanoidScale").propertyChanged(motor, saved.value, value)
	if timeline:IsRecording() then
		local before = timeline:_snapshotMotorBucket(motor)
		timeline:RecordKeyframeForMotorAtCurrentTime(
			motor.Part1,
			motor,
			Tracks.encode(value),
			{ Frame = saved.frame, PropertyValue = value },
			refs.State.UIHelpers.SanitizeName
		)
		local after = timeline:_snapshotMotorBucket(motor)

		local function apply(bucket)
			if not motor.Parent then
				return
			end

			timeline:_restoreMotorBucket(motor, bucket)
			timeline:ApplyPoseAtTime(motor.Rig, raw.CurrentTime, { OnlyRig = true })
			refs.State.currentProjectSaved = false
		end

		apply(after)
		History.record(function()
			apply(before)
		end, function()
			apply(after)
		end, motor.PropertyId .. " " .. motor.Rig.Name)
	else
		local Document = require("Document")
		local beforeDefault = motor.DefaultValue

		local function apply(v, default)
			if not motor.Parent then
				return
			end

			motor.Part1:SetAttribute("Default", Document.pack(default))
			raw.DefaultPose[motor] = Tracks.encode(default)
			Tracks.setValue(motor, v)
			refs.State.currentProjectSaved = false
		end

		apply(value, value)
		History.record(function()
			apply(saved.value, beforeDefault)
		end, function()
			apply(value, value)
		end, motor.PropertyId .. " " .. motor.Rig.Name)
	end

	refs.State.currentProjectSaved = false
	return true
end

function Gizmo.reset()
	if drag or not available() or Input:GetFocusedTextBox() or target.PropertyId == "CFrame" then
		return false
	end

	local motor = target
	local value = motor.DefaultValue
	if value == nil or read(motor) == value then
		return false
	end

	local saved = {
		motor = motor,
		mode = "reset",
		value = read(motor),
		frame = refs.State.Timeline:TimeToFrame(refs.State.Timeline:GetState().CurrentTime),
		placement = motor.IsEclipseScaleAdapter and motor.capture()
			or not facial(motor) and Resize.captureProperty(motor, refs.State.Timeline:GetState()),
	}
	write(motor, value)
	drag = saved
	Gizmo.finish(false)
	return true
end

function Gizmo.select(motor, group)
	Gizmo.finish(true)
	targets = nil
	if group and #group > 1 then
		targets = {}
		for _, member in group do
			local nested = false
			for _, parent in group do
				if parent ~= member and (parent.Rig:IsA("Model") or parent.Rig:IsA("BasePart")) and member.Rig:IsDescendantOf(parent.Rig) then nested = true break end
			end
			if not nested then table.insert(targets, member) end
		end
		if not table.find(targets, motor) then motor = targets[1] end
	end
	if target == motor then
		if target and target.PropertyId == "CFrame" then
			refs.State.Axis:SetPropertyTarget(target, targets)
		end

		return
	end

	Gizmo.finish(true)
	destroyVisual()
	target = nil
	if typeof(motor) == "table" and motor.IsEclipseScaleAdapter then
		target = motor
	elseif
		Tracks.is(motor)
		and (
			(
				motor.PropertyId == "CFrame"
				and (
					motor.Rig:IsA("Model")
					or motor.Rig:IsA("BasePart")
					or motor.Rig:IsA("Attachment")
				)
			)
			or (motor.PropertyId == "Scale" and (motor.Rig:IsA("Model") or motor.Rig:IsA(
				"DataModelMesh"
			) and motor.Rig:FindFirstAncestorWhichIsA("BasePart")))
			or (motor.PropertyId == "Size" and motor.Rig:IsA("BasePart"))
			or facial(motor)
		)
	then
		target = motor
	end

	if refs and refs.State.Axis then
		refs.State.Axis:SetPropertyTarget(
			target and target.PropertyId == "CFrame" and target or nil, targets
		)
	end
end

function Gizmo.begin(mode, name)
	if drag or not available() or Input:GetFocusedTextBox() or Input.inWidget() then
		return false
	end

	refs.Finalize()
	local motor = target
	local cf, size = bounds(motor.Rig, motor)
	if motor.PropertyId == "CFrame" then
		cf = motor.Rig:IsA("Attachment") and motor.Rig.WorldCFrame
			or Tracks.readValue(motor.Rig, "CFrame")
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local projection = camera:WorldToViewportPoint(cf.Position)
	if projection.Z <= 0 then
		return false
	end

	local mouse = Input:GetMouseLocation()
	local center = Vector2.new(projection.X, projection.Y)
	local axis, unit, pixels, sign
	if mode == "handles" then
		axis = name:sub(-1)
		sign = name:sub(1, 1) == "-" and -1 or 1
		local direction = cf:VectorToWorldSpace(
			axis == "X" and Vector3.xAxis or axis == "Y" and Vector3.yAxis or Vector3.zAxis
		) * sign
		local along = camera:WorldToViewportPoint(cf.Position + direction)
		local delta = Vector2.new(along.X - projection.X, along.Y - projection.Y)
		if delta.Magnitude < 0.01 then
			return false
		end

		unit, pixels = delta.Unit, delta.Magnitude
	end

	drag = {
		motor = motor,
		mode = mode,
		value = read(motor),
		mouse = mouse,
		center = center,
		radius = (mouse - center).Magnitude,
		unit = unit,
		pixels = pixels,
		size = size,
		cf = cf,
		sign = sign,
		axis = axis,
		handle = name,
		frame = refs.State.Timeline:TimeToFrame(refs.State.Timeline:GetState().CurrentTime),
	}
	if motor.PropertyId == "CFrame" and targets and #targets > 1 then
		drag.group = {}
		for _, member in targets do
			table.insert(drag.group, { motor = member, value = read(member), default = member.DefaultValue })
		end
	end
	if motor.IsEclipseScaleAdapter then
		drag.placement = motor.capture()
	elseif motor.PropertyId ~= "CFrame" and not facial(motor) then
		drag.placement = Resize.captureProperty(motor, refs.State.Timeline:GetState())
	end

	if motor.PropertyId == "CFrame" then
		local axis = refs.State.Axis
		local started
		if mode == "move" then
			started = axis:StartBlenderGrab(mouse)
		elseif mode == "rotate" then
			started = axis:StartBlenderRotate(mouse, false)
		elseif mode == "axisHandle" then
			started = axis:StartDrag(name, mouse)
		end

		if not started then
			drag = nil
			return false
		end
	elseif mode == "pointer" or mode == "handles" then
		clearHover()
		Cursor.start(cf.Position, true)
		if facial(motor) then Cursor.setValue(drag.value) end
	end

	return true
end

function Gizmo.start(mode)
	if not available() then
		return false
	end

	if drag then
		if drag.motor.PropertyId == "CFrame" and drag.mode == "rotate" and mode ~= "move" then
			refs.State.Axis:EnterTrackballRotate()
		end

		return true
	end

	if target.PropertyId == "CFrame" then
		return Gizmo.begin(mode == "move" and "move" or "rotate")
	end

	if mode == "move" and not facial(target) then
		return false
	end

	return Gizmo.begin("pointer")
end

function Gizmo.change(point)
	if not drag then
		return
	end

	local value, offset
	if drag.motor.PropertyId == "CFrame" then
		local axis = refs.State.Axis
		if drag.mode == "move" then
			axis:ProcessBlenderGrab(point)
		elseif drag.mode == "rotate" then
			axis:ProcessBlenderRotate(point)
		elseif drag.mode == "axisHandle" then
			axis:ProcessDrag(point)
		end

		return
	elseif facial(drag.motor) then
		local delta = point - drag.mouse
		value = Gizmo.faceValue(drag.value, drag.mode == "handles" and delta:Dot(drag.unit) or delta.X - delta.Y, drag.numeric)
	elseif drag.mode == "pointer" then
		local factor = tonumber(drag.numeric)
			or math.max(
				0.001,
				1 + ((point - drag.center).Magnitude - drag.radius) / math.max(60, drag.radius)
			)
		factor = math.clamp(factor, 0.001, 10000)
		if drag.axis and typeof(drag.value) == "Vector3" then
			local mask = drag.axis == "X" and Vector3.xAxis
				or drag.axis == "Y" and Vector3.yAxis
				or Vector3.zAxis
			value = drag.value * (Vector3.one + mask * (factor - 1))
		else
			value = drag.value * factor
		end

		if typeof(value) == "number" then
			value = math.clamp(value, 0.001, 10000)
		else
			value = Vector3.new(
				math.max(0.001, value.X),
				math.max(0.001, value.Y),
				math.max(0.001, value.Z)
			)
		end
	else
		local distance = (point - drag.mouse):Dot(drag.unit) / math.max(1, drag.pixels)
		local symmetric = Input:IsKeyDown(Enum.KeyCode.LeftControl)
			or Input:IsKeyDown(Enum.KeyCode.RightControl)
		local uniform = Input:IsKeyDown(Enum.KeyCode.LeftAlt)
			or Input:IsKeyDown(Enum.KeyCode.RightAlt)
		value, offset = Resize.resolve(drag, distance, symmetric, uniform)
	end

	write(drag.motor, value, drag, offset or Vector3.zero)
	if facial(drag.motor) then Cursor.setValue(value) end
	Resize.syncBones(refs.State, drag.motor.Rig)
end

function Gizmo.input(input, processed)
	if drag then
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			Gizmo.finish(false)
			return false
		elseif Shortcuts.matches("Cancel", input) then
			Gizmo.finish(true)
		elseif
			(drag.mode == "pointer" or drag.mode == "move" or drag.mode == "rotate")
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or Shortcuts.matches("ConfirmTransform", input)
				or Shortcuts.matches("ConfirmTransformAlternate", input)
			)
		then
			Gizmo.finish(false)
		end

		if
			drag
			and drag.mode == "pointer"
			and input.UserInputType == Enum.UserInputType.Keyboard
		then
			local key = input.KeyCode.Name
			if key == "X" or key == "Y" or key == "Z" then
				key = Preferences.axisName(key)
			end

			if (key == "X" or key == "Y" or key == "Z") and typeof(drag.value) == "Vector3" then
				drag.axis = drag.axis ~= key and key or nil
			elseif key == "Backspace" then
				drag.numeric = (drag.numeric or ""):sub(1, -2)
			elseif key == "Period" or key == "KeypadPeriod" then
				if not (drag.numeric or ""):find(".", 1, true) then
					drag.numeric = (drag.numeric or "") .. "."
				end
			else
				local digits = {
					Zero = "0",
					One = "1",
					Two = "2",
					Three = "3",
					Four = "4",
					Five = "5",
					Six = "6",
					Seven = "7",
					Eight = "8",
					Nine = "9",
					KeypadZero = "0",
					KeypadOne = "1",
					KeypadTwo = "2",
					KeypadThree = "3",
					KeypadFour = "4",
					KeypadFive = "5",
					KeypadSix = "6",
					KeypadSeven = "7",
					KeypadEight = "8",
					KeypadNine = "9",
				}
				if digits[key] and #(drag.numeric or "") < 12 then
					drag.numeric = (drag.numeric or "") .. digits[key]
				end
			end

			Gizmo.change(Input:GetMouseLocation())
		end

		return true
	end

	if
		processed
		or not available()
		or Input.inWidget()
		or Input:GetFocusedTextBox()
		or input.UserInputType ~= Enum.UserInputType.MouseButton1
	then
		return false
	end

	local mouse = Input:GetMouseLocation()
	local camera = workspace.CurrentCamera
	if target.PropertyId == "CFrame" then
		local axis = refs.State.Axis:GetAxisUnderMouse()
		return axis ~= nil and Gizmo.begin("axisHandle", axis)
	end

	local nearest = hit(camera, mouse)
	return nearest ~= nil and Gizmo.begin("handles", nearest.part.Name)
end

local function step()
	if not available() then
		if drag then
			Gizmo.finish(true)
		end

		destroyVisual()
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if target.PropertyId == "CFrame" then
		if drag then
			Gizmo.change(Input:GetMouseLocation())
		end

		if not visual then
			visual = Instance.new("Part")
			visual.Name = "EclipsePropertyCFrame"
			visual.Archivable = false
			visual.Anchored = true
			visual.CanCollide = false
			visual.CanTouch = false
			visual.CanQuery = false
			visual.Transparency = 1
			visual:SetAttribute("EclipsePropertyGizmo", true)
			require("Recovery").mark(visual)
			local marker = Instance.new("BoxHandleAdornment")
			marker.Name = "CFrameHandle"
			marker.Adornee = visual
			marker.AlwaysOnTop = true
			marker.ZIndex = 1
			marker.Color3 = Color3.fromRGB(124, 186, 209)
			marker.Parent = visual
		end

		local _, size = bounds(target.Rig, target)
		visual.CFrame = target.Rig:IsA("Attachment") and target.Rig.WorldCFrame
			or Tracks.readValue(target.Rig, "CFrame")
		visual.Parent = camera
		visual.CFrameHandle.Size = Vector3.new(
			math.max(0.2, size.X * 0.28),
			math.max(0.2, size.Y * 0.28),
			math.max(0.2, size.Z * 0.28)
		)
		visual.CFrameHandle.Transparency = (Preferences.get("HandleBoneTransparency") or 55) / 100
		return
	end

	if not visual then
		local template = refs.Template
		if not template then
			return
		end

		visual = template:Clone()
		visual.Name = "EclipsePropertyScale"
		visual.Archivable = false
		visual.Parent = camera
		visual:SetAttribute("EclipsePropertyGizmo", true)
		require("Recovery").mark(visual)
		for _, part in visual:GetChildren() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Transparency = 1
				if not part.Name:match("^[+-][XYZ]$") then
					continue
				end

				local color = part.Color
				for _, adornment in part:GetChildren() do
					if adornment:IsA("HandleAdornment") then
						color = adornment.Color3
						adornment:Destroy()
					end
				end

				local position = template.Parent:FindFirstChild("Position")
				local axisPart = position and position:FindFirstChild(part.Name)
				local axisAdornment = axisPart
					and axisPart:FindFirstChildWhichIsA("HandleAdornment", true)
				if axisAdornment then
					color = axisAdornment.Color3
				end

				local adornment = Instance.new("SphereHandleAdornment")
				adornment.Name = "ScaleHandle"
				adornment.Adornee = part
				adornment.Color3 = color
				adornment.AlwaysOnTop = true
				adornment.ZIndex = 3
				adornment.Transparency = 0.85
				adornment.Parent = part
				table.insert(handles, { part = part, adornment = adornment, color = color })
			end
		end
	end

	if visual.Parent ~= camera then
		visual.Parent = camera
	end

	if drag then
		Gizmo.change(Input:GetMouseLocation())
	end

	local cf, size = bounds(target.Rig, target)
	if not drag and not Input.inWidget() and not Input:GetFocusedTextBox() then
		setHover(hit(camera, Input:GetMouseLocation()), camera, cf.Position)
	else
		clearHover()
	end

	local unit = 2
		* math.tan(math.rad(camera.FieldOfView) * 0.5)
		/ math.max(1, camera.ViewportSize.Y)
	for _, handle in handles do
		local part = handle.part
		local axis = part.Name:sub(-1)
		local sign = part.Name:sub(1, 1) == "-" and -1 or 1
		handle.adornment.Color3 = Preferences.get("BlenderAxes")
				and Preferences.axisColor(axis, {
					X = Color3.fromRGB(255, 88, 88),
					Y = Color3.fromRGB(92, 220, 92),
					Z = Color3.fromRGB(92, 140, 255),
				})
			or handle.color
		local direction = (
			axis == "X" and Vector3.xAxis
			or axis == "Y" and Vector3.yAxis
			or Vector3.zAxis
		) * sign
		local depth = math.max(0.1, -camera.CFrame:PointToObjectSpace(cf.Position).Z)
		local scale = (Preferences.get("GizmoSize") or 0.5) / 0.5
		local pixels = depth * unit * scale
		local length = size[axis] * 0.5
			+ pixels * (11 + 8 * (Preferences.get("GizmoDistance") or 2.5) / 2.5)
		local offset = direction * length
		part.CFrame = cf * CFrame.new(offset)
		depth = -camera.CFrame:PointToObjectSpace(part.Position).Z
		local active = drag and drag.mode == "handles" and part.Name == drag.handle
		local hot = hovered == handle
		local radius = (active and 13 or hot and 12 or 11) * scale
		handle.adornment.Radius = math.max(0.001, depth * unit * radius)
		handle.hitRadius = radius + 4
		handle.adornment.Transparency = active and 0.35 or hot and 0.65 or drag and 1 or 0.85
		handle.adornment.Visible = depth > 0 and not (drag and drag.mode == "pointer")
	end
end

function Gizmo.destroy()
	Gizmo.select(nil)
	if connection then
		connection:Disconnect()
		connection = nil
	end

	for _, item in connections do
		item:Disconnect()
	end

	connections = {}
end

function Gizmo.init(options)
	Gizmo.destroy()
	refs = options
	options.State.PropertyGizmo = Gizmo
	connection = Run.RenderStepped:Connect(step)
	table.insert(
		connections,
		Input.InputEnded:Connect(function(input)
			if
				drag
				and (drag.mode == "handles" or drag.mode == "axisHandle")
				and input.UserInputType == Enum.UserInputType.MouseButton1
			then
				Gizmo.finish(false)
			end
		end)
	)
	table.insert(
		connections,
		Input.WindowFocusReleased:Connect(function()
			Gizmo.finish(true)
			clearHover()
		end)
	)
	options.Plugin.Unloading:Once(Gizmo.destroy)
	options.ScreenGui.Destroying:Once(Gizmo.destroy)
end

return Gizmo
