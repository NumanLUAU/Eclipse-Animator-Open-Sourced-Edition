--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Input = game:GetService("UserInputService")
local Run = game:GetService("RunService")
local Core = game:GetService("CoreGui")
local Preferences = require("Preferences")
local EditorInput = require("UserInputService")
local Math = require("localOffset")
local Focus = require("Focus")
local Cursor = require("Cursor")
local Origin = require("Origin")
local Navigation = {}
local Recovery = require("Recovery")
local refs, drag, parked, layer, cursor, pluginMouse, anchor
local gizmo, gizmoDrag, projection, axisTween
local connections = {}
local unsubscribe
local idle = {}
local inactiveSince
local nativeRight = false
local pointerInput
local yieldNative
local allowed
local betaOK, betaEnabled = pcall(function()
	return settings():GetFFlag("NewCameraControls")
end)
local nativeCamera = betaOK and betaEnabled == true

local function arrowHeld()
	return Input:IsKeyDown(Enum.KeyCode.Left)
		or Input:IsKeyDown(Enum.KeyCode.Right)
		or Input:IsKeyDown(Enum.KeyCode.Up)
		or Input:IsKeyDown(Enum.KeyCode.Down)
end

local function movementHeld()
	for _, key in { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Q, Enum.KeyCode.E } do
		if Input:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function keyboardCoasting()
	local current = drag or parked
	return current and current.keyboardOnly and current.keyboardVelocity
		and current.keyboardVelocity.Magnitude > 0.01
end

local function keyboardFiltering()
	return keyboardCoasting() or arrowHeld() or Preferences.get("DisableCameraWASD") == true
		or Preferences.get("DisableCameraQE") == true
end

local directions = {
	W = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	A = Vector3.new(-1, 0, 0),
	D = Vector3.new(1, 0, 0),
	Q = Vector3.new(0, -1, 0),
	E = Vector3.new(0, 1, 0),
}

local function blocked(key)
	return EditorInput.isCameraKeyBlocked and EditorInput.isCameraKeyBlocked(key)
end

local function keyDown(key)
	return Input:IsKeyDown(key)
end

local function commandModifier()
	for _, key in
		{
			Enum.KeyCode.LeftControl,
			Enum.KeyCode.RightControl,
			Enum.KeyCode.LeftAlt,
			Enum.KeyCode.RightAlt,
			Enum.KeyCode.LeftMeta,
			Enum.KeyCode.RightMeta,
			Enum.KeyCode.LeftSuper,
			Enum.KeyCode.RightSuper,
		}
	do
		if Input:IsKeyDown(key) then
			return true
		end
	end

	return false
end

local RENDER = "EclipseBlenderNavigation-" .. game:GetService("HttpService"):GenerateGUID(false)

local function needsKeyboardGuard()
	if refs and refs.State.GreasePencil and refs.State.GreasePencil.isStrokeActive() then
		return false
	end

	if keyboardCoasting() and allowed() and not commandModifier() and not EditorInput.isCapturingKeys() then
		return true
	end

	if arrowHeld() then
		return true
	end

	local ioHeld = Input:IsKeyDown(Enum.KeyCode.I) or Input:IsKeyDown(Enum.KeyCode.O)
	if ioHeld then
		return false
	end

	for _, key in { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Q, Enum.KeyCode.E } do
		if Input:IsKeyDown(key) and blocked(key) then
			return true
		end
	end
	return false
end

local function nativeHeld()
	return not (drag and drag.fly) and not (parked and Preferences.get("BlenderCameraBeta")) and not needsKeyboardGuard()
		and (nativeRight or not nativeCamera and Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
end

local function walking()
	if Input:GetFocusedTextBox() or EditorInput.pointerInWidget() then
		return false
	end

	for _, key in
		{
			Enum.KeyCode.W,
			Enum.KeyCode.A,
			Enum.KeyCode.S,
			Enum.KeyCode.D,
			Enum.KeyCode.Q,
			Enum.KeyCode.E,
		}
	do
		if Input:IsKeyDown(key) then
			return true
		end
	end

	return false
end

local function uiHeld()
	return (EditorInput.isUIGestureActive and EditorInput.isUIGestureActive())
		or (EditorInput.isTransformCameraActive and EditorInput.isTransformCameraActive())
end

local function yieldWalking()
	if needsKeyboardGuard() or Preferences.get("BlenderCameraBeta") and (drag or parked) then
		return false
	end

	if (not drag or drag.wheelOnly) and walking() then
		yieldNative("native keyboard navigation")
		return true
	end

	return false
end

function Navigation.isDragging()
	return (drag ~= nil and not drag.wheelOnly and not drag.fly)
		or (gizmoDrag ~= nil and not gizmoDrag.moving)
end

function Navigation.isWalkingInput(input)
	return keyboardFiltering()
		and not commandModifier()
		and input.UserInputType == Enum.UserInputType.Keyboard
		and directions[input.KeyCode.Name] ~= nil
		and not blocked(input.KeyCode)
end

function Navigation.isWheelZooming()
	return drag ~= nil and drag.wheelOnly == true
end

local function panHeld()
	return Input:IsKeyDown(Enum.KeyCode.LeftShift) or Input:IsKeyDown(Enum.KeyCode.RightShift)
end

local function zoomHeld()
	return Input:IsKeyDown(Enum.KeyCode.LeftControl) or Input:IsKeyDown(Enum.KeyCode.RightControl)
end

local function canOwn()
	for _, gui in Core:GetChildren() do
		if
			refs
			and gui ~= refs.ScreenGui
			and gui:IsA("ScreenGui")
			and gui.Enabled
			and gui:GetAttribute("EclipseRiggingViewport") == true
		then
			return false
		end
	end

	if
		not refs
		or not (Preferences.get("BlenderCameraBeta") or keyboardFiltering()
			or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
		or not refs.ScreenGui.Enabled
		or refs.AnimatorFrame and not refs.AnimatorFrame.Visible
		or refs.State.PresentationHidden
		or refs.State.WorkspaceSelection
		or refs.State.LoadingProject
		or refs.State.CameraPoseMode
		or EditorInput.isWindowFocused and not EditorInput.isWindowFocused()
		or refs.State.CameraPreview and refs.State.CameraPreview.isFull()
	then
		inactiveSince = nil
		return false
	end

	if refs.Active() or refs.ScreenGui:GetAttribute("EclipseConfirmationOpen") == true then
		inactiveSince = nil
		return true
	end

	inactiveSince = inactiveSince or os.clock()
	return (drag ~= nil or parked ~= nil) and os.clock() - inactiveSince < 0.15
end

allowed = function()
	if not canOwn() or not refs.Active() then
		return false
	end

	local state = refs.State
	if
		Origin.isDragging()
		or state.PresentationHidden
		or Input:GetFocusedTextBox()
		or EditorInput.pointerInWidget()
	then
		return false
	end

	if state.CameraPreview and state.CameraPreview.isFull() then
		return false
	end

	if
		state.Axis
		and (
			state.Axis:IsHoldingAxis()
			or state.Axis:IsBlenderGrabMode()
			or state.Axis:IsBlenderRotateMode()
		)
	then
		return false
	end

	for _, controller in { state.PropertyGizmo, state.CameraControls } do
		if controller and controller.isEditing() then
			return false
		end
	end

	return not (state.GreasePencil and state.GreasePencil.isStrokeActive())
end

local function overUI(point, allowOwned)
	if
		not allowOwned
		and refs
		and not refs.State.HUDHidden
		and refs.AnimatorFrame
		and refs.AnimatorFrame:IsDescendantOf(Core)
	then
		local frame = refs.AnimatorFrame
		local visible, ancestor = true, frame
		while ancestor and ancestor ~= Core do
			if
				ancestor:IsA("GuiObject") and not ancestor.Visible
				or ancestor:IsA("LayerCollector") and not ancestor.Enabled
			then
				visible = false
				break
			end

			ancestor = ancestor.Parent
		end

		local p, size = frame.AbsolutePosition, frame.AbsoluteSize
		if
			visible
			and frame.Parent
			and point.X >= p.X
			and point.Y >= p.Y
			and point.X <= p.X + size.X
			and point.Y <= p.Y + size.Y
		then
			return true
		end
	end

	local ok, objects = pcall(function()
		return Core:GetGuiObjectsAtPosition(point.X, point.Y)
	end)
	if not ok then
		return true
	end

	for _, object in objects do
		local ancestor = object
		local blocks, visible, owned = false, true, false
		while ancestor and ancestor ~= Core do
			owned = owned
				or ancestor == refs.ScreenGui
				or ancestor:GetAttribute("EclipseOwnedUI") == true
			if ancestor:IsA("GuiObject") then
				if not ancestor.Visible then
					visible = false
					break
				end

				blocks = blocks
					or ancestor.Active
					or ancestor:IsA("GuiButton")
					or ancestor:IsA("TextBox")
			elseif ancestor:IsA("LayerCollector") and not ancestor.Enabled then
				visible = false
				break
			end

			ancestor = ancestor.Parent
		end

		if blocks and visible and not (allowOwned and owned) then
			return true
		end
	end

	return false
end

local function ensureCursor()
	if layer then
		return
	end

	layer = Instance.new("ScreenGui")
	layer.Name = "EclipseBlenderNavigationCursor"
	layer.DisplayOrder = 2147483647
	layer.IgnoreGuiInset = true
	layer.ResetOnSpawn = false
	layer:SetAttribute("EclipseOwnedUI", true)
	layer.Enabled = false
	layer.Parent = refs.ScreenGui.Parent
	cursor = Cursor.create(layer)
end

local function applyPose(current)
	if yieldWalking() then
		return
	end

	if
		(drag ~= current and parked ~= current)
		or current.writing
		or workspace.CurrentCamera ~= current.camera
		or not current.camera.Parent
	then
		return
	end

	if Recovery.maintain and not Recovery.maintain(current.camera) then
		Navigation.stop(false, "lease superseded")
		return
	end

	current.writing = true
	local ok, err = pcall(function()
		if current.camera.CameraType ~= Enum.CameraType.Scriptable then
			current.camera.CameraType = Enum.CameraType.Scriptable
		end

		if current.camera.CFrame ~= current.frame then
			current.camera.CFrame = current.frame
		end

		if current.camera.Focus ~= current.focus then
			current.camera.Focus = current.focus
		end
	end)
	current.writing = false
	if not ok then
		Navigation.stop(false, "camera write/render error")
		warn("Eclipse camera navigation: " .. tostring(err))
	end
end

local function queueCorrection(current)
	if nativeHeld() then
		yieldNative()
		return
	end

	if yieldWalking() then
		return
	end

	if parked == current and (current.focusHandoff or (Focus.isActive and Focus.isActive())) then
		current.focusHandoff = true
		return
	end

	if
		(drag ~= current and parked ~= current)
		or current.writing
		or workspace.CurrentCamera ~= current.camera
	then
		return
	end

	if
		current.camera.CFrame == current.frame
		and current.camera.Focus == current.focus
		and current.camera.CameraType == Enum.CameraType.Scriptable
	then
		return
	end

	if current.correctionQueued or current.correctedFrame == current.renderFrame then
		return
	end

	current.correctionQueued = true
	task.defer(function()
		current.correctionQueued = false
		if
			(drag ~= current and parked ~= current)
			or current.correctedFrame == current.renderFrame
		then
			return
		end

		current.correctedFrame = current.renderFrame
		applyPose(current)
	end)
end

local function consumeMotion(current)
	if current.delta.Magnitude == 0 then
		return
	end

	if current.fly then
		current.lookReverse = current.lookReverse
			or (if current.frame.UpVector.Y < 0 then -1 else 1)
		current.frame, current.pitchAxis = Math.lookView(
			current.frame,
			current.delta,
			0.005,
			current.lookReverse,
			current.pitchAxis
		)
		current.focus =
			CFrame.new(current.frame.Position + current.frame.LookVector * current.flyDistance)
		current.pose = nil
	else
		Math.move(
			current.pose,
			current.delta,
			current.pendingPan or not Preferences.get("BlenderCameraBeta"),
			current.camera.ViewportSize.Y,
			current.camera.FieldOfView,
			3.5 * Preferences.get("BlenderPanSensitivity"),
			Preferences.get("BlenderOrbitSensitivity")
		)
	end

	current.delta = Vector2.zero
end

local function releaseCamera(previous, reason)
	if not previous then
		return
	end

	local owned = not Recovery.owns or Recovery.owns(previous.camera)

	local frame, focus = previous.camera.CFrame, previous.camera.Focus
	for _, connection in previous.cameraConnections do
		connection:Disconnect()
	end

	if previous.camera.SetAttribute then
		previous.camera:SetAttribute("EclipseCameraReleaseReason", reason or "explicit release")
	end

	previous.release()

	if owned and previous.camera.Parent and workspace.CurrentCamera == previous.camera then
		pcall(function()
			previous.camera.CFrame = frame
			previous.camera.Focus = focus
		end)
	end
end

function Navigation.stop(keepCamera, reason)
	local retain = keepCamera and (needsKeyboardGuard() or Preferences.get("BlenderCameraBeta"))
	local previous = drag
	drag = nil
	if layer then
		layer.Enabled = false
	end

	if previous then
		if EditorInput.releasePointer then
			EditorInput.releasePointer(previous)
		else
			pcall(function()
				Input.MouseBehavior = Enum.MouseBehavior.Default
			end)
		end

		Cursor.release(previous)

		if anchor then
			anchor.pivot = previous.focus.Position
			anchor.frame = previous.frame
		end

		idle.camera, idle.frame, idle.focus = previous.camera, previous.frame, previous.focus
		if retain and canOwn() and workspace.CurrentCamera == previous.camera then
			parked = previous
			applyPose(previous)
		else
			releaseCamera(previous, reason)
		end
	end

	if not retain and parked then
		local old = parked
		parked = nil
		releaseCamera(old, reason)
	end

	if not keepCamera then
		anchor = nil
		idle = {}
	end
end

yieldNative = function(reason)
	local current = drag or parked

	if current and current.camera.Parent then
		current.frame, current.focus = current.camera.CFrame, current.camera.Focus
	end

	Navigation.stop(false, reason or "native RMB navigation")
end

local function captureWheel(view)
	local targets = Focus.targets(refs.State)
	if #targets == 0 and typeof(refs.State.currentRig) == "Instance" then
		targets = { refs.State.currentRig }
	end
	local bounds = Focus.bounds(targets)
	local center = bounds and bounds.Position
	local depth = center and (center - view.CFrame.Position):Dot(view.CFrame.LookVector)
	local pivot = depth and depth > 0.05 and view.CFrame.Position + view.CFrame.LookVector * depth or nil
	local pose = Math.capture(view, pivot)
	pose.pivot = pose.frame.Position + pose.frame.LookVector * pose.depth
	pose.distance = pose.depth
	return pose
end

local function capture(camera, view)
	view = view or camera
	local targets = Focus.targets(refs.State)
	if #targets == 0 and typeof(refs.State.currentRig) == "Instance" then
		targets = { refs.State.currentRig }
	end

	local bounds, size = Focus.bounds(targets)
	local center = bounds and bounds.Position
	local same = anchor
		and anchor.camera == camera
		and anchor.center == center
		and #anchor.targets == #targets
	if same then
		for _, target in targets do
			if not table.find(anchor.targets, target) then
				same = false
				break
			end
		end
	end

	local pivot
	if same and view.CFrame == anchor.frame then
		pivot = anchor.pivot
	else
		pivot = center or view.Focus.Position
	end

	local zoomScale = size and size.Magnitude * 0.5 or (anchor and anchor.zoomScale) or 4
	local pose = Math.capture(view, pivot, zoomScale)
	anchor = {
		camera = camera,
		targets = targets,
		center = center,
		pivot = pose.pivot,
		frame = view.CFrame,
		zoomScale = zoomScale,
	}
	return pose
end

function Navigation.begin(point, processed, wheelOnly, fly, holdOnly)
	local eligible = holdOnly
			and canOwn()
			and refs.Active()
			and not Input:GetFocusedTextBox()
			and not EditorInput.isCapturingKeys()
		or not holdOnly and allowed()
	if uiHeld() or drag or not fly and nativeHeld() or not eligible then
		return false
	end

	if wheelOnly and yieldWalking() then
		return false
	end

	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize
	if
		not size
		or not holdOnly
			and (point.X < 0 or point.Y < 0 or point.X >= size.X or point.Y >= size.Y or overUI(
				point
			))
	then
		return false
	end

	if camera.CameraType == Enum.CameraType.Scriptable and not Recovery.owns(camera) then
		return false
	end

	Focus.cancel()
	local view = camera
	local release, pose
	local keyboardVelocity = parked and parked.keyboardVelocity
	if parked and parked.camera == camera then
		if
			not parked.keyboardOnly
			and parked.pose
			and parked.pose.frame == view.CFrame
			and parked.focus == view.Focus
		then
			pose = table.clone(parked.pose)
			Math.clearZoom(pose)
		end

		release = parked.release
		for _, connection in parked.cameraConnections do
			connection:Disconnect()
		end

		parked = nil
	else
		if parked then
			Navigation.stop()
		end

		release = require("Recovery").acquire(camera)
	end

	local keyboardOnly = holdOnly or fly

	local cameraPose = wheelOnly and not keyboardOnly and captureWheel(view)
		or pose
		or (keyboardOnly and Math.capture(view, view.Focus.Position, 4) or capture(camera, view))
	drag = {
		keyboardOnly = keyboardOnly,
		keyboardVelocity = keyboardVelocity,
		release = release,
		camera = camera,
		cameraType = camera.CameraType,
		mouseBehavior = Input.MouseBehavior,
		pose = cameraPose,
		point = point,
		delta = Vector2.zero,
		frame = view.CFrame,
		focus = view.Focus,
		cameraConnections = {},
		renderFrame = 0,
		pointerDelta = Vector2.zero,
		wheelOnly = wheelOnly == true,
		wheelRemaining = 0.25,
		zoomY = point.Y,
	}
	drag.fly = fly == true
	drag.flyDistance = math.max(0.1, (view.CFrame.Position - view.Focus.Position).Magnitude)
	camera.CameraType = Enum.CameraType.Scriptable

	local current = drag
	for _, property in { "CFrame", "Focus", "CameraType" } do
		table.insert(
			current.cameraConnections,
			camera:GetPropertyChangedSignal(property):Connect(function()
				if
					property == "CameraType"
					and not current.writing
					and camera.CameraType ~= Enum.CameraType.Scriptable
				then
					applyPose(current)
				else
					queueCorrection(current)
				end
			end)
		)
	end

	if not wheelOnly then
		ensureCursor()
	end

	return true
end

function Navigation.resumeAfterTransform(camera, frame, focus, velocity)
	if
		not canOwn()
		or not refs.Active()
		or workspace.CurrentCamera ~= camera
		or not camera.Parent
		or not Recovery.owns(camera)
	then
		return false
	end

	Navigation.stop(false, "transform handback")
	camera.CFrame, camera.Focus = frame, focus
	if not Navigation.begin(Input:GetMouseLocation(), false, true, false, true) then
		return false
	end

	drag.keyboardVelocity = velocity
	Navigation.stop(true)
	return true
end

function Navigation.isReservedInput(input)
	return input.UserInputType == Enum.UserInputType.Keyboard
		and blocked(input.KeyCode)
		and canOwn()
end

local function moveKeyboard(current, dt)
	if
		commandModifier()
		or Input:GetFocusedTextBox()
		or EditorInput.isCapturingKeys()
		or EditorInput.pointerInWidget()
	then
		return
	end

	local move = Vector3.zero
	for name, vector in directions do
		local key = Enum.KeyCode[name]
		if
			not blocked(key)
			and keyDown(key)
			and not (EditorInput.isCapturedKey and EditorInput.isCapturedKey(key))
		then
			move += vector
		end
	end

	local shifted = Input:IsKeyDown(Enum.KeyCode.LeftShift)
		or Input:IsKeyDown(Enum.KeyCode.RightShift)

	local frame = current.frame
	local offset = Math.keyboardOffset(
		current,
		move,
		Math.keyboardSpeed(shifted),
		dt,
		Preferences.get("DisableCameraWASD") == true,
		Preferences.get("DisableCameraQE") == true
	)
	local delta = frame.RightVector * offset.X
		+ Vector3.yAxis * offset.Y
		- frame.LookVector * offset.Z
	current.frame += delta
	current.focus += delta
	if current.pose then
		current.pose.frame = current.frame
		current.pose.pivot = current.focus.Position
	end
end

function Navigation.step(dt)
	if refs and refs.State.GreasePencil and refs.State.GreasePencil.isStrokeActive() then
		Navigation.stop(false, "drawing stroke owns camera")
		return
	end

	if uiHeld() or axisTween or (gizmoDrag and gizmoDrag.camera) then
		return
	end

	if drag and not drag.wheelOnly and not allowed() then
		Navigation.stop(false, "tool or focus took pointer")
		return
	end

	if drag and not drag.wheelOnly then
		local button = drag.fly and Enum.UserInputType.MouseButton2
			or Enum.UserInputType.MouseButton3
		if
			not Input:IsMouseButtonPressed(button)
			or pointerInput
				and (pointerInput.UserInputState == Enum.UserInputState.End or pointerInput.UserInputState == Enum.UserInputState.Cancel)
		then
			nativeRight = false
			pointerInput = nil
			Navigation.stop(true)
		end
	end

	if refs then
		Origin.sync()
	end

	if
		keyboardFiltering()
		and (not canOwn() or Input:GetFocusedTextBox() or EditorInput.isCapturingKeys())
	then
		Navigation.stop(false, "keyboard camera inactive")
		return
	end

	if not needsKeyboardGuard() and not Preferences.get("BlenderCameraBeta") and parked then
		Navigation.stop(false, "native permitted movement")
	end

	local function rememberNative()
		local camera = workspace.CurrentCamera
		if keyboardFiltering() and camera then
			idle.camera, idle.frame, idle.focus = camera, camera.CFrame, camera.Focus
		end
	end

	if yieldWalking() then
		rememberNative()
		return
	end

	if nativeHeld() then
		if drag or parked then
			yieldNative()
		end

		rememberNative()
		return
	end

	if drag and drag.wheelOnly and Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) then
		Navigation.stop(true)
		Navigation.begin(Input:GetMouseLocation(), false)
	end

	if
		needsKeyboardGuard()
		and not drag
		and not parked
		and canOwn()
		and not (Focus.isActive and Focus.isActive())
	then
		local fly = allowed() and Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		if Navigation.begin(Input:GetMouseLocation(), false, not fly, fly, true) and not fly then
			Navigation.stop(true)
		end
	end

	local current = drag
	if not current then
		if parked then
			local walking = false
			if not Input:GetFocusedTextBox() and not EditorInput.pointerInWidget() then
				for _, key in
					{
						Enum.KeyCode.W,
						Enum.KeyCode.A,
						Enum.KeyCode.S,
						Enum.KeyCode.D,
						Enum.KeyCode.Q,
						Enum.KeyCode.E,
					}
				do
					if Input:IsKeyDown(key) then
						walking = true
						break
					end
				end
			end

			if walking and not keyboardFiltering() and not Preferences.get("BlenderCameraBeta") and allowed() then
				Navigation.stop(false, "native keyboard navigation")
				anchor = nil
				idle = {}
				return
			end

			if
				not canOwn()
				or workspace.CurrentCamera ~= parked.camera
				or not parked.camera.Parent
			then
				Navigation.stop(false, "editor gate or camera replacement")
			elseif parked.focusHandoff or (Focus.isActive and Focus.isActive()) then
				parked.frame, parked.focus = parked.camera.CFrame, parked.camera.Focus
				parked.focusHandoff = Focus.isActive and Focus.isActive() or nil
				anchor = nil
				return
			else
				parked.renderFrame += 1
				if allowed() then
					moveKeyboard(parked, dt)
				end

				applyPose(parked)
				return
			end
		end

		local camera = workspace.CurrentCamera
		if refs and (Preferences.get("BlenderCameraBeta") or keyboardFiltering()) and camera then
			idle.camera, idle.frame, idle.focus = camera, camera.CFrame, camera.Focus
		else
			idle.camera = nil
		end

		return
	end

	if not canOwn() or workspace.CurrentCamera ~= current.camera or not current.camera.Parent then
		Navigation.stop(false, "editor gate or camera replacement")
		return
	end

	local camera = current.camera
	current.renderFrame += 1
	if current.fly and not Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		Navigation.stop(true)
		return
	end

	if not current.wheelOnly then
		local locked = false
		if not locked then
			if EditorInput.claimPointer then
				locked = EditorInput.claimPointer(current)
			else
				locked = pcall(function()
					Input.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				end)
				locked = locked and Input.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition
			end
		end

		local customCursor = locked and not current.fly and Cursor.isReady(cursor, panHeld())
		if customCursor then
			customCursor = Cursor.hide(current, pluginMouse)
		else
			Cursor.release(current)
		end
		layer.Enabled = customCursor == true

		if current.pointerDelta.Magnitude > 0 then
			current.point = Math.wrap(current.point + current.pointerDelta, camera.ViewportSize)
			current.pointerDelta = Vector2.zero
		end

		local position = UDim2.fromOffset(current.point.X, current.point.Y)
		if cursor.root.Position ~= position then
			cursor.root.Position = position
		end

		local pan = panHeld()
		if pan ~= current.cursorPan then
			Cursor.setPan(cursor, pan)
			current.cursorPan = pan
		end
	end

	consumeMotion(current)
	if current.fly then
		moveKeyboard(current, dt)
		applyPose(current)
		return
	end

	if current.zoomTarget and Math.smoothZoom(current.pose, current.zoomTarget, dt or 0) then
		current.zoomTarget = nil
	end

	if current.wheelOnly then
		current.pose.pivot = current.pose.frame.Position + current.pose.frame.LookVector * current.pose.depth
	end

	current.frame, current.focus = current.pose.frame, CFrame.new(current.pose.pivot)
	moveKeyboard(current, dt)
	applyPose(current)
	if current.wheelOnly then
		current.wheelRemaining -= math.max(0, dt or 0)
		if current.wheelRemaining <= 0 and not current.zoomTarget then
			Navigation.stop(true)
		end
	end
end

function Navigation.finishWheel(keepCamera)
	if Navigation.isWheelZooming() then
		Navigation.step(0)
		Navigation.stop(keepCamera)
	end
end

local function aimZoom(current, point)
	local pose = current.pose
	local depth = math.max(0.05, (pose.pivot - pose.frame.Position):Dot(pose.frame.LookVector))
	local direction = pose.frame.LookVector
	if Preferences.get("BlenderZoomToMouse") then
		direction =
			Math.zoomRay(pose, point, current.camera.ViewportSize, current.camera.FieldOfView)
	end

	local center = pose.frame.Position
		+ direction * (depth / math.max(0.00001, direction:Dot(pose.frame.LookVector)))
	Math.aimZoom(pose, direction, center)
	current.zoomPoint = point
	current.zoomToMouse = Preferences.get("BlenderZoomToMouse") == true
end

function Navigation.wheel(steps, point)
	if uiHeld() then
		return false
	end

	if yieldWalking() then
		return false
	end

	if nativeHeld() then
		if drag or parked then
			yieldNative()
		end

		return false
	end

	if steps == 0 or not allowed() then
		return false
	end

	if overUI(point) then
		Navigation.finishWheel(true)
		return false
	end

	if not drag or drag.wheelOnly then
		local camera = workspace.CurrentCamera
		local size = camera and camera.ViewportSize
		if
			not size
			or point.X < 0
			or point.Y < 0
			or point.X >= size.X
			or point.Y >= size.Y
			or overUI(point)
		then
			Navigation.finishWheel(true)
			return false
		end
	end

	if not drag and not Navigation.begin(point, false, true) then
		return false
	end

	consumeMotion(drag)
	if drag.fly then
		local pose =
			Math.capture({ CFrame = drag.frame, Focus = drag.focus }, drag.focus.Position, 4)
		Math.zoom(pose, steps)
		drag.frame = pose.frame
		drag.focus = CFrame.new(pose.pivot)
		drag.flyDistance = pose.distance
		return true
	end

	local zoomToMouse = Preferences.get("BlenderZoomToMouse") == true
	if not drag.pose.zoomPivot or drag.zoomToMouse ~= zoomToMouse
		or zoomToMouse and drag.zoomPoint ~= point
	then
		local remaining = drag.zoomTarget and drag.zoomTarget / drag.pose.distance
		aimZoom(drag, point)
		drag.zoomTarget = remaining and drag.pose.distance * remaining or nil
	end

	local targetPose = table.clone(drag.pose)
	local direction = math.sign(steps)

	if drag.zoomTarget and drag.wheelDirection == direction then
		Math.setDistance(targetPose, drag.zoomTarget)
	end

	Math.zoom(targetPose, steps)
	drag.zoomTarget = targetPose.distance
	drag.wheelDirection = direction
	drag.zoomStart = nil
	drag.wheelRemaining = 0.25
	return true
end

local function gizmoAllowed()
	return refs
		and not uiHeld()
		and refs.ScreenGui.Enabled
		and refs.Active()
		and not refs.State.PresentationHidden
		and not (refs.State.CameraPreview and refs.State.CameraPreview.isFull())
end

local function finishGizmo()
	if axisTween then
		local previous = axisTween
		axisTween = nil
		local cf, focus = previous.camera.CFrame, previous.camera.Focus
		local owned = Recovery.owns(previous.camera)
		previous.release()
		if owned and previous.camera.Parent and workspace.CurrentCamera == previous.camera then
			previous.camera.CFrame = cf
			previous.camera.Focus = focus
		end
	end

	local previous = gizmoDrag
	gizmoDrag = nil
	if previous and previous.release then
		local cf, focus = previous.camera.CFrame, previous.camera.Focus
		local owned = Recovery.owns(previous.camera)
		previous.release()
		if owned and previous.camera.Parent and workspace.CurrentCamera == previous.camera then
			previous.camera.CFrame = cf
			previous.camera.Focus = focus
		end
	end
end

function Navigation.movementForTransform(camera)
	local current = drag or parked
	return current and current.camera == camera and current.keyboardVelocity or nil
end

function Navigation.cancelCameraGestures()
	Navigation.stop(false, "transform tool owns pointer")
	finishGizmo()
	Focus.cancel()
	pointerInput = nil
	nativeRight = false
end

local function cameraAvailable(camera)
	return camera and (camera.CameraType ~= Enum.CameraType.Scriptable or Recovery.owns(camera))
end

local function projectionOff()
	local p = projection
	projection = nil
	if not p or not p.camera.Parent or workspace.CurrentCamera ~= p.camera then
		return
	end

	if cameraAvailable(p.camera) and math.abs(p.camera.FieldOfView - p.projectedFov) < 0.01 then
		p.camera.FieldOfView = p.fov
		p.camera.CFrame = p.frame
		p.camera.Focus = p.focus
	end
end

local function gizmoPivot(camera)
	local rig = refs and refs.State.currentRig
	if rig and rig.Parent then
		local ok, cf = pcall(rig.GetBoundingBox, rig)
		if ok then
			return cf.Position
		end
	end

	return camera.Focus.Position
end

function Navigation.axisView(camera, index, negative, pivot)
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local direction = axes[index] * (negative and -1 or 1)
	if -camera.CFrame.LookVector:Dot(direction) > 0.995 then
		direction = -direction
	end

	pivot = pivot or gizmoPivot(camera)
	local distance = math.max(0.5, (camera.CFrame.Position - pivot).Magnitude)
	local up = index == 2 and Vector3.new(0, 0, direction.Y > 0 and -1 or 1) or Vector3.yAxis
	return CFrame.lookAt(pivot + direction * distance, pivot, up), CFrame.new(pivot)
end

local function axisClick(index, negative)
	if not gizmoAllowed() then
		return
	end

	Navigation.stop()
	finishGizmo()
	Focus.cancel()
	local camera = workspace.CurrentCamera
	if not cameraAvailable(camera) then
		return
	end

	local target, focus = Navigation.axisView(camera, index, negative)
	axisTween = {
		camera = camera,
		from = camera.CFrame,
		target = target,
		focus = focus,
		fromFocus = camera.Focus,
		elapsed = 0,
		release = Recovery.acquire(camera),
	}
	camera.CameraType = Enum.CameraType.Scriptable
end

local function toggleProjection()
	if not gizmoAllowed() then
		return
	end

	Navigation.stop()
	finishGizmo()
	Focus.cancel()
	if projection then
		projectionOff()
		return
	end

	local camera = workspace.CurrentCamera
	if not cameraAvailable(camera) then
		return
	end

	local center = gizmoPivot(camera)
	local depth = math.max(0.5, (center - camera.CFrame.Position):Dot(camera.CFrame.LookVector))
	center = camera.CFrame.Position + camera.CFrame.LookVector * depth
	local frame, fov = require("fov").atDistance(camera.CFrame, camera.FieldOfView, depth)
	projection = {
		camera = camera,
		fov = camera.FieldOfView,
		frame = camera.CFrame,
		focus = camera.Focus,
		projectedFov = fov,
	}
	camera.CFrame = frame
	camera.Focus = CFrame.new(center)
	camera.FieldOfView = fov
end

local function destroyGizmo()
	finishGizmo()
	projectionOff()
	if gizmo then
		gizmo.gui:Destroy()
		gizmo = nil
	end
end

function Navigation.prepareCameraView()
	Navigation.stop()
	destroyGizmo()
end

local function ensureGizmo()
	if gizmo then
		return
	end

	local function make(class, parent, props)
		local o = Instance.new(class)
		for k, v in props do
			o[k] = v
		end

		o.Parent = parent
		return o
	end

	local gui = make("ScreenGui", refs.ScreenGui.Parent, {
		Name = "EclipseViewportNavigation",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = refs.ScreenGui.DisplayOrder + 5,
	})
	gui:SetAttribute("EclipseOwnedUI", true)
	require("Motion").watchFloatingGui(gui)
	local holder = make(
		"Frame",
		gui,
		{ Name = "Navigation", Size = UDim2.fromOffset(88, 128), BackgroundTransparency = 1 }
	)
	local grip = make("TextButton", holder, {
		Name = "Move",
		Text = "···",
		TextSize = 18,
		Size = UDim2.fromOffset(48, 16),
		Position = UDim2.fromOffset(20, 0),
		BackgroundTransparency = 0.7,
		BackgroundColor3 = Color3.fromRGB(40, 55, 60),
		TextColor3 = Color3.fromRGB(185, 195, 200),
		AutoButtonColor = true,
	})
	local disc = make("TextButton", holder, {
		Name = "Orbit",
		Text = "",
		Size = UDim2.fromOffset(88, 88),
		Position = UDim2.fromOffset(0, 16),
		BackgroundColor3 = Color3.fromRGB(120, 120, 120),
		BackgroundTransparency = 0.85,
		AutoButtonColor = false,
	})
	make("UICorner", disc, { CornerRadius = UDim.new(1, 0) })
	local buttons, lines = {}, {}
	local colors = {
		Color3.fromRGB(255, 82, 115),
		Color3.fromRGB(130, 220, 55),
		Color3.fromRGB(50, 155, 255),
	}
	for i, name in { "X", "Y", "Z" } do
		lines[i] = make("Frame", disc, {
			BorderSizePixel = 0,
			BackgroundColor3 = colors[i],
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		buttons[i] = {}
		for _, sign in { 1, -1 } do
			local ball = make("TextButton", disc, {
				Name = name .. sign,
				Text = sign == 1 and name or "",
				TextSize = 11,
				Font = Enum.Font.GothamBold,
				TextColor3 = Color3.fromRGB(25, 25, 25),
				BackgroundColor3 = colors[i],
				BackgroundTransparency = sign == 1 and 0 or 0.45,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(sign == 1 and 18 or 14, sign == 1 and 18 or 14),
				AutoButtonColor = true,
			})
			make("UICorner", ball, { CornerRadius = UDim.new(1, 0) })
			ball.Activated:Connect(function()
				axisClick(i, sign == -1)
			end)
			buttons[i][sign] = ball
		end
	end

	local mode = make("TextButton", holder, {
		Name = "Projection",
		Text = "PERSP",
		TextSize = 10,
		Size = UDim2.fromOffset(56, 20),
		Position = UDim2.fromOffset(16, 108),
		BackgroundColor3 = Color3.fromRGB(30, 50, 55),
		TextColor3 = Color3.fromRGB(200, 215, 220),
		AutoButtonColor = true,
	})
	mode.Activated:Connect(toggleProjection)
	gizmo = { gui = gui, holder = holder, buttons = buttons, lines = lines, mode = mode }
	EditorInput.attachSurface(gui, { holder })
	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and gizmoAllowed() then
			finishGizmo()
			gizmoDrag = {
				moving = true,
				point = Input:GetMouseLocation(),
				position = holder.AbsolutePosition,
			}
		end
	end)
	disc.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not gizmoAllowed() then
			return
		end

		local point = Input:GetMouseLocation()
		for _, pair in buttons do
			for _, ball in pair do
				if (point - (ball.AbsolutePosition + ball.AbsoluteSize / 2)).Magnitude < 11 then
					return
				end
			end
		end

		Navigation.stop()
		finishGizmo()
		Focus.cancel()
		local cam = workspace.CurrentCamera
		if not cameraAvailable(cam) then
			return
		end

		gizmoDrag = {
			camera = cam,
			pose = Math.capture(cam, gizmoPivot(cam)),
			point = point,
			release = Recovery.acquire(cam),
		}
		cam.CameraType = Enum.CameraType.Scriptable
	end)
end

local function stepGizmo(dt)
	if not Preferences.get("NavigationGizmo") then
		if gizmo then
			destroyGizmo()
		end

		return
	end

	ensureGizmo()
	local active = gizmoAllowed()
	gizmo.gui.Enabled = active
	if not active then
		finishGizmo()
		if not uiHeld() then
			projectionOff()
		end

		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if projection and projection.camera ~= camera then
		projectionOff()
	end

	if axisTween then
		local t = axisTween
		if t.camera ~= camera or not Recovery.maintain(camera) then
			finishGizmo()
		else
			t.elapsed += math.max(0, dt or 0)
			local a = math.clamp(t.elapsed / 0.12, 0, 1)
			local smooth = a * a * (3 - 2 * a)
			local pivot = t.focus.Position
			local rotation = t.from.Rotation:Lerp(t.target.Rotation, smooth)
			local radius = (t.from.Position - pivot).Magnitude

			local residual = t.from.Position - (pivot - t.from.LookVector * radius)
			camera.CFrame = CFrame.new(
				pivot - rotation.LookVector * radius + residual * (1 - smooth)
			) * rotation
			camera.Focus = t.fromFocus:Lerp(t.focus, smooth)
			camera.CameraType = Enum.CameraType.Scriptable
			if a >= 1 then
				camera.CFrame = t.target
				camera.Focus = t.focus
				finishGizmo()
			end
		end
	end

	local size = camera.ViewportSize
	local available = Vector2.new(math.max(0, size.X - 104), math.max(0, size.Y - 144))
	if gizmoDrag and gizmoDrag.moving then
		local pos = gizmoDrag.position + Input:GetMouseLocation() - gizmoDrag.point
		pos = Vector2.new(
			math.clamp(pos.X, 8, available.X + 8),
			math.clamp(pos.Y, 8, available.Y + 8)
		)
		gizmo.holder.Position = UDim2.fromOffset(pos.X, pos.Y)
	elseif gizmoDrag then
		if gizmoDrag.camera ~= camera or not Recovery.maintain(camera) then
			finishGizmo()
			return
		end

		local point = Input:GetMouseLocation()
		local delta = point - gizmoDrag.point
		gizmoDrag.point = point
		camera.CFrame, camera.Focus =
			Math.move(gizmoDrag.pose, delta, false, size.Y, camera.FieldOfView, 1, 0.6)
		camera.CameraType = Enum.CameraType.Scriptable
	else
		gizmo.holder.Position = UDim2.fromOffset(
			8 + Preferences.get("NavigationGizmoX") * available.X,
			8 + Preferences.get("NavigationGizmoY") * available.Y
		)
	end

	gizmo.mode.Text = projection and "ORTHO" or "PERSP"
	for i, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		for _, sign in { 1, -1 } do
			local v = axis * sign
			local x, y = camera.CFrame.RightVector:Dot(v), -camera.CFrame.UpVector:Dot(v)
			local front = camera.CFrame.LookVector:Dot(v) <= 0
			local ball = gizmo.buttons[i][sign]
			local native = ({ "X", "Y", "Z" })[i]
			local positive = sign == Preferences.axisSign(native)
			local color = Preferences.axisColor(native, {
				X = Color3.fromRGB(255, 82, 115),
				Y = Color3.fromRGB(130, 220, 55),
				Z = Color3.fromRGB(50, 155, 255),
			})
			ball.Text = positive and Preferences.axisName(native) or ""
			ball.BackgroundColor3 = color
			ball.BackgroundTransparency = positive and 0 or 0.45
			ball.Size = UDim2.fromOffset(positive and 18 or 14, positive and 18 or 14)
			gizmo.lines[i].BackgroundColor3 = color
			ball.Position = UDim2.fromOffset(44 + x * 30, 44 + y * 30)
			ball.ZIndex = front and 6 or 3
			if positive then
				local line = gizmo.lines[i]
				line.Position = UDim2.fromOffset(44 + x * 15, 44 + y * 15)
				line.Size = UDim2.fromOffset(math.max(0, math.sqrt(x * x + y * y) * 30 - 8), 2)
				line.Rotation = math.deg(math.atan2(y, x))
				line.ZIndex = front and 5 or 2
			end
		end
	end
end

local function releaseGizmo(input)
	if input and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if gizmoDrag and gizmoDrag.moving and gizmo then
		local size = workspace.CurrentCamera.ViewportSize
		local pos = gizmo.holder.Position
		Preferences.set("NavigationGizmoX", (pos.X.Offset - 8) / math.max(1, size.X - 104))
		Preferences.set("NavigationGizmoY", (pos.Y.Offset - 8) / math.max(1, size.Y - 144))
	end

	if gizmoDrag then
		finishGizmo()
	end
end

function Navigation.destroy()
	destroyGizmo()
	Navigation.stop(false, "controller destroyed")
	Focus.cancel()
	Origin.destroy()
	anchor = nil
	idle = {}
	Run:UnbindFromRenderStep(RENDER)
	Run:UnbindFromRenderStep(RENDER .. "-Guard")
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end

	if layer then
		layer:Destroy()
		layer, cursor = nil, nil
	end

	refs, pluginMouse = nil, nil
	inactiveSince = nil
	nativeRight = false
	pointerInput = nil
end

function Navigation.init(options)
	Navigation.destroy()
	refs = options
	refs.State.BlenderNavigation = Navigation
	Origin.init(options)
	pluginMouse = options.Plugin:GetMouse()

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	connect(Input.InputBegan, function(input, processed)
		if
			axisTween
			and (
				input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3
				or input.KeyCode == Enum.KeyCode.Escape
				or walking()
			)
		then
			finishGizmo()
		end

		if uiHeld() then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard and (blocked(input.KeyCode) or directions[input.KeyCode.Name]) then
			Navigation.step(0)
		end

		if yieldWalking() then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			nativeRight = true
			pointerInput = input
			if allowed() and (needsKeyboardGuard() or Preferences.get("BlenderCameraBeta")) then
				Navigation.stop(true)
				if Navigation.begin(Input:GetMouseLocation(), processed, false, true) then
					pointerInput = input
					return
				end
			else
				yieldNative()
			end
		end

		if parked and input.KeyCode == Enum.KeyCode.F and not Input:GetFocusedTextBox() then
			parked.focusHandoff = true
		end

		if
			input.KeyCode == Enum.KeyCode.Escape
			or input.UserInputType == Enum.UserInputType.MouseButton2
		then
			Origin.endDrag(true)
		end

		if
			Navigation.isWheelZooming()
			and (
				input.UserInputType == Enum.UserInputType.MouseButton3
				or input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.KeyCode == Enum.KeyCode.Escape
			)
		then
			Navigation.finishWheel(input.UserInputType ~= Enum.UserInputType.MouseButton2)
		end

		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			if Navigation.begin(Input:GetMouseLocation(), processed) then
				pointerInput = input
			end
		elseif drag and input.KeyCode == Enum.KeyCode.Escape then
			Navigation.stop(true)
		end
	end)
	connect(Input.InputChanged, function(input)
		if axisTween and input.UserInputType == Enum.UserInputType.MouseWheel then
			finishGizmo()
		end

		if uiHeld() then
			return
		end

		if nativeHeld() then
			if drag or parked then
				yieldNative()
			end

			return
		end

		if
			input.UserInputType == Enum.UserInputType.MouseWheel
			and not require("NumericInput").contains(Input:GetMouseLocation())
		then
			Navigation.wheel(input.Position.Z, Input:GetMouseLocation())
			return
		end

		if not drag or drag.wheelOnly then
			return
		end

		local current = drag
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = Vector2.new(input.Delta.X, input.Delta.Y)
			if delta.Magnitude == 0 then
				return
			end

			current.zoomTarget = nil
			if current.fly then
				current.delta += delta * math.max(0, Input.MouseDeltaSensitivity)
				return
			end

			current.zoomY += delta.Y
			if zoomHeld() then
				consumeMotion(current)
				if not current.zoomStart then
					aimZoom(current, current.point)
					current.zoomStart =
						{ distance = current.pose.distance, y = current.zoomY - delta.Y }
				end

				Math.zoomDrag(
					current.pose,
					current.zoomStart.distance,
					current.zoomStart.y,
					current.zoomY - current.zoomStart.y
				)
				current.pointerDelta += delta
				return
			end

			current.zoomStart = nil
			local pan = panHeld()
			if current.pendingPan ~= pan then
				consumeMotion(current)
			end

			current.pendingPan = pan
			current.delta += delta
			current.pointerDelta += delta

			if not pan then
				consumeMotion(current)
			end
		end
	end)
	connect(Input.InputEnded, releaseGizmo)
	connect(Input.WindowFocusReleased, function()
		releaseGizmo()
	end)
	connect(Input.InputEnded, function(input)
		if (input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down) and not keyboardFiltering() and not Preferences.get("BlenderCameraBeta") then
			Navigation.stop(false, "timeline arrow released")
		end

		if input == pointerInput then
			pointerInput = nil
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			nativeRight = false
			if drag and drag.fly then
				consumeMotion(drag)
				Navigation.stop(true)
				if Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) then
					Navigation.begin(Input:GetMouseLocation(), false)
				end
			end

			idle = {}
			anchor = nil
		end

		if input.UserInputType == Enum.UserInputType.MouseButton3 and drag and not drag.fly then
			Navigation.step()
			Navigation.stop(true)
		end
	end)
	connect(Input.WindowFocusReleased, function()
		finishGizmo()
		nativeRight = false
		pointerInput = nil
		Origin.endDrag(true)
		Navigation.stop(false, "window focus released")
		Focus.cancel()
	end)
	connect(options.Plugin.Deactivation, function()
		if not canOwn() then
			Origin.endDrag(true)
			Navigation.stop(false, "editor deactivated/hidden")
			Focus.cancel()
		end
	end)
	connect(options.Plugin.Unloading, Navigation.destroy)
	connect(options.ScreenGui.Destroying, Navigation.destroy)
	connect(options.ScreenGui:GetPropertyChangedSignal("Enabled"), function()
		if not options.ScreenGui.Enabled then
			Origin.endDrag(true)
			Navigation.stop()
			Focus.cancel()
		end
	end)
	unsubscribe = Preferences.subscribe(function(key, value)
		if key == "DisableCameraWASD" or key == "DisableCameraQE" then
			if not keyboardFiltering() then
				Navigation.stop(false, "movement disablers off")
			else
				local current = drag or parked
				if current and current.keyboardVelocity then
					current.keyboardVelocity *= Vector3.new(
						Preferences.get("DisableCameraWASD") and 0 or 1,
						Preferences.get("DisableCameraQE") and 0 or 1,
						Preferences.get("DisableCameraWASD") and 0 or 1
					)
				end
			end

			return
		end

		if key == "BlenderCameraBeta" or key == "HideOriginBone" or key == "BlenderZoomToMouse" then
			Navigation.stop(false, "preference: " .. key)
			Origin.endDrag(true)
			Origin.sync()
			if key == "BlenderCameraBeta" and refs.State.Rig and refs.State.currentRig then
				refs.State.Rig:BuildRigHierarchy(refs.State.currentRig)
			end
		end
	end)

	Run:BindToRenderStep(RENDER .. "-Guard", Enum.RenderPriority.Input.Value - 1, function()
		if not keyboardFiltering() or uiHeld() then
			return
		end

		local ok, err = pcall(function()
			if canOwn() and needsKeyboardGuard() then
				Navigation.step(0)
			end
		end)
		if not ok then
			Navigation.stop(false, "early camera guard error")
			warn(tostring(err))
		end
	end)
	if Run.Heartbeat then
		connect(Run.Heartbeat, function()
			if drag and not drag.wheelOnly then
				local button = drag.fly and Enum.UserInputType.MouseButton2
					or Enum.UserInputType.MouseButton3
				if
					not allowed()
					or not Input:IsMouseButtonPressed(button)
					or pointerInput
						and (pointerInput.UserInputState == Enum.UserInputState.End or pointerInput.UserInputState == Enum.UserInputState.Cancel)
				then
					nativeRight = false
					pointerInput = nil
					consumeMotion(drag)
					Navigation.stop(allowed(), "pointer gesture ended")
				end
			end
		end)
	end

	Run:BindToRenderStep(RENDER, Enum.RenderPriority.Last.Value + 2, function(dt)
		local ok, err = pcall(function()
			stepGizmo(dt)
			Navigation.step(dt)
		end)
		if not ok then
			Navigation.stop(false, "camera write/render error")
			warn("Eclipse camera navigation: " .. tostring(err))
		end
	end)
end

return Navigation
