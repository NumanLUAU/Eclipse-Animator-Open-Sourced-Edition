--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")

local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CameraRig = require("CameraRig")
local Display = require("CameraDisplay")
local History = require("History")
local RotationCursor = require("RotateCursor")
local Controls = {}
local refs, drag, handles, hovered

function Controls.isEditing()
	return drag ~= nil
end

local function selected()
	if not refs or refs.State.PresentationHidden or not refs.Active() then
		return nil
	end

	local state = refs.State
	local bone = state.Axis and state.Axis:GetSelectedBone()
	local source = bone and bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
	local rig = source and source.Value
	if not CameraRig.isRig(rig) then
		return nil
	end

	local motor = CameraRig.motor(rig, bone:GetAttribute("SourcePartName"))
	return CameraRig.isFov(motor) and motor or nil, bone
end

local function refresh()
	local state = refs.State
	if state.currentRig then
		state.Timeline:ApplyPoseAtTime(state.currentRig, state.Timeline:GetState().CurrentTime)
	end

	state.currentProjectSaved = false
end

function Controls.edit(keys, value)
	if not refs or not tonumber(value) or #keys == 0 then
		return false
	end

	local timeline = refs.State.Timeline
	local before, after = {}, {}
	for _, key in keys do
		if not CameraRig.isFov(key.Motor) then
			return false
		end

		if not before[key.Motor] then
			before[key.Motor] = timeline:_snapshotMotorBucket(key.Motor)
			after[key.Motor] = timeline:_snapshotMotorBucket(key.Motor)
		end

		local copy = after[key.Motor][key.Frame]
		if not copy then
			return false
		end

		copy.C0 = CameraRig.encode(key.Motor, tonumber(value))
		copy.Position, copy.Rotation = copy.C0.Position, CFrame.identity
		copy.WorldCFrame, copy.Parented = nil, true
		copy.Channels, copy.ChannelPoseC0, copy.GraphCurves, copy.GraphOnly = nil, nil, nil, nil
	end

	local function apply(snapshot)
		for motor, bucket in snapshot do
			if motor.Parent then
				timeline:_restoreMotorBucket(motor, bucket)
			end
		end

		refresh()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Edit camera FOV")
	return true
end

function Controls.begin(motor, mode, point)
	require("UserInputService").cancelCameraGestures()
	if
		drag
		or (refs.State.PresentationHidden and mode ~= "view")
		or not CameraRig.isFov(motor)
		or refs.State.Timeline:GetState().Playing
	then
		return false
	end

	local rig = CameraRig.owner(motor)
	drag = {
		motor = motor,
		rig = rig,
		c0 = motor.C0,
		fov = CameraRig.fov(rig),
		mode = mode,
		point = point or Input:GetMouseLocation(),
		frame = refs.State.Timeline:GetState().CurrentTime,
		bucket = refs.State.Timeline:_snapshotMotorBucket(motor),
	}
	if mode == "pointer" or mode == "view" then
		local pivot = mode == "view" and (CameraRig.viewFrame(rig) * CFrame.new(0, 0, -12)).Position
			or CameraRig.viewFrame(rig).Position
		RotationCursor.start(pivot, false)
	end

	return true
end

function Controls.change(factor)
	if not drag or not drag.motor.Parent then
		return
	end

	local tangent = math.tan(math.rad(drag.fov) * 0.5)
	local value = math.deg(math.atan(tangent * math.max(0.01, factor))) * 2
	drag.motor.C0 = CameraRig.encode(drag.motor, value)
	local folder = refs.State.Rig:GetBonesFolder(drag.rig)
	if folder then
		Display.update(folder, false)
	end
end

function Controls.finish(cancel)
	if not drag then
		return false
	end

	local current = drag
	drag = nil
	if current.mode == "pointer" or current.mode == "view" then
		RotationCursor.stop()
	end

	if not current.motor.Parent then
		return true
	end

	if cancel then
		current.motor.C0 = current.c0
		return true
	end

	local final = current.motor.C0
	if final == current.c0 then
		return true
	end

	local timeline = refs.State.Timeline
	if timeline:IsRecording() then
		local raw = timeline:GetState()
		local time = raw.CurrentTime
		raw.CurrentTime = current.frame
		timeline:RecordKeyframeForMotorAtCurrentTime(
			current.motor.Part1,
			current.motor,
			final,
			refs.TrackContainer,
			refs.State.UIHelpers.SanitizeName
		)
		raw.CurrentTime = time
		local after = timeline:_snapshotMotorBucket(current.motor)

		local function apply(bucket)
			if not current.motor.Parent then
				return
			end

			timeline:_restoreMotorBucket(current.motor, bucket)
			refresh()
		end

		History.record(function()
			apply(current.bucket)
		end, function()
			apply(after)
		end, "Camera FOV")
	else
		History.record(function()
			if current.motor.Parent then
				current.motor.C0 = current.c0
			end
		end, function()
			if current.motor.Parent then
				current.motor.C0 = final
			end
		end, "Camera FOV")
	end

	refs.State.currentProjectSaved = false
	return true
end

function Controls.start()
	local motor = selected()
	if not motor then
		return false
	end

	Controls.begin(motor, "pointer")
	return true
end

function Controls.input(input)
	if drag then
		if
			Shortcuts.matches("Cancel", input)
			or input.UserInputType == Enum.UserInputType.MouseButton2
		then
			Controls.finish(true)
		elseif
			(drag.mode == "pointer" or drag.mode == "view")
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or Shortcuts.matches("ConfirmTransform", input)
			)
		then
			Controls.finish(false)
		end

		return true
	end

	return hovered ~= nil
		and selected() ~= nil
		and input.UserInputType == Enum.UserInputType.MouseButton1
end

function Controls.init(options)
	refs = options
	refs.State.CameraControls = Controls
	handles = Instance.new("Handles")

	handles.Name = "CameraFOVScale"
	handles.Style = Enum.HandlesStyle.Resize
	handles.Faces =
		Faces.new(Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom)
	handles.Color3 = Color3.fromRGB(242, 171, 196)
	handles.Visible = false
	handles.Parent = refs.ScreenGui
	local connections = {}

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	connect(handles.MouseEnter, function(face)
		hovered = face
	end)
	connect(handles.MouseLeave, function()
		hovered = nil
	end)
	connect(handles.MouseButton1Down, function()
		local motor = selected()
		if motor then
			Controls.begin(motor, "handles")
		end
	end)
	connect(handles.MouseDrag, function(_, distance)
		Controls.change(math.exp(distance / CameraRig.DEPTH))
	end)
	connect(handles.MouseButton1Up, function()
		if drag and drag.mode == "handles" then
			Controls.finish(false)
		end
	end)
	connect(Input.InputEnded, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			and drag
			and drag.mode == "handles"
		then
			Controls.finish(false)
		end
	end)
	connect(RunService.RenderStepped, function()
		if refs.State.PresentationHidden then
			if drag and drag.mode == "view" then
				if refs.State.Timeline:GetState().Playing then
					Controls.finish(true)
				else
					Controls.change(math.exp((drag.point.Y - Input:GetMouseLocation().Y) / 220))
				end
			elseif drag then
				Controls.finish(true)
			end

			hovered, handles.Adornee, handles.Visible = nil, nil, false
			return
		end

		local motor, bone = selected()
		if drag then
			if motor ~= drag.motor or refs.State.Timeline:GetState().Playing then
				Controls.finish(true)
			elseif drag.mode == "pointer" then
				Controls.change(math.exp((Input:GetMouseLocation().X - drag.point.X) / 220))
			end
		end

		handles.Adornee = motor and bone or nil
		handles.Visible = motor ~= nil
			and not refs.State.Timeline:GetState().Playing
			and not (drag and drag.mode == "pointer")
		local selectedRig = bone and bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
		for _, rig in refs.State.getAllRigs() do
			if CameraRig.isRig(rig) then
				local folder = refs.State.Rig:GetBonesFolder(rig)
				if folder then
					Display.update(
						folder,
						motor == nil and selectedRig ~= nil and selectedRig.Value == rig,
						refs.Active()
					)
				end
			end
		end
	end)
	refs.ScreenGui.Destroying:Once(function()
		Controls.finish(true)
		for _, connection in connections do
			connection:Disconnect()
		end

		handles:Destroy()
	end)
end

return Controls
