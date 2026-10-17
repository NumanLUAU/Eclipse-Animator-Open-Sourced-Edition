--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Native = game:GetService("UserInputService")
local Input = {}
local destroyed = false
local owner = typeof(script) == "Instance" and script:IsA("ModuleScript") and script or nil
local ownerParent = owner and owner.Parent

local function alive()
	if destroyed then
		return false
	end

	if owner and owner.Parent ~= ownerParent then
		Input.destroy()
		return false
	end

	return true
end

local widget, focused, over, textBox
local viewportFocused = true
local focusSink
local clipboardFocus, clipboardOwner = false, false
local armClipboard
local held, connections, nativeConnections = {}, {}, {}
local pressed, mouseEvents = {}, {}
local events, seen = {}, {}
local capture
local capturedInputs = setmetatable({}, { __mode = "k" })

function Input.isCapturedInput(input)
	return capturedInputs[input] == true
end

local captured = {}

function Input.isCapturedKey(key)
	return captured[key] == true
end

function Input.isCameraKeyBlocked(key)
	if not alive() then
		return false
	end

	if key == Enum.KeyCode.Left or key == Enum.KeyCode.Right or key == Enum.KeyCode.Up or key == Enum.KeyCode.Down then
		return true
	end

	local prefs = require("Preferences")
	if key == Enum.KeyCode.Q or key == Enum.KeyCode.E then
		return prefs.get("DisableCameraQE") == true
	end

	if
		key == Enum.KeyCode.W
		or key == Enum.KeyCode.A
		or key == Enum.KeyCode.S
		or key == Enum.KeyCode.D
	then
		return prefs.get("DisableCameraWASD") == true
	end

	return false
end

local keyRevision = {}
local keyObjects = {}
local keyReleases = {}

local function clearKey(key)
	held[key] = nil
	keyObjects[key] = nil
	if keyReleases[key] then
		for _, connection in keyReleases[key] do
			connection:Disconnect()
		end

		keyReleases[key] = nil
	end
end

const modifierGroups = {
	{ modifier = Enum.ModifierKey.Ctrl, left = Enum.KeyCode.LeftControl, right = Enum.KeyCode.RightControl },
	{ modifier = Enum.ModifierKey.Shift, left = Enum.KeyCode.LeftShift, right = Enum.KeyCode.RightShift },
	{ modifier = Enum.ModifierKey.Alt, left = Enum.KeyCode.LeftAlt, right = Enum.KeyCode.RightAlt },
	{ modifier = Enum.ModifierKey.Meta, left = Enum.KeyCode.LeftMeta, right = Enum.KeyCode.RightMeta },
	{ modifier = Enum.ModifierKey.Meta, left = Enum.KeyCode.LeftSuper, right = Enum.KeyCode.RightSuper },
}
const commandKeys = {
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.RightControl] = true,
	[Enum.KeyCode.LeftMeta] = true,
	[Enum.KeyCode.RightMeta] = true,
	[Enum.KeyCode.LeftSuper] = true,
	[Enum.KeyCode.RightSuper] = true,
}
const macCommandKeys = { Enum.KeyCode.LeftMeta, Enum.KeyCode.RightMeta, Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper }

local function nativeCommandDown()
	for _, key in macCommandKeys do
		if Native:IsKeyDown(key) then
			return true
		end
	end

	return false
end
const modifierGroupOf = {}
for _, group in modifierGroups do
	modifierGroupOf[group.left] = group
	modifierGroupOf[group.right] = group
end
local pointerModifiersReported = false

local function clearModifiers()
	for _, group in modifierGroups do
		if held[group.left] or keyObjects[group.left] then
			clearKey(group.left)
		end
		if held[group.right] or keyObjects[group.right] then
			clearKey(group.right)
		end
	end
end

local function reconcileModifiers(input)
	if typeof(input) ~= "InputObject" then
		return
	end

	const kind = input.UserInputType
	const keyboard = kind == Enum.UserInputType.Keyboard
	if
		not keyboard
		and kind ~= Enum.UserInputType.MouseButton1
		and kind ~= Enum.UserInputType.MouseButton2
		and kind ~= Enum.UserInputType.MouseButton3
	then
		return
	end

	const own = keyboard and modifierGroupOf[input.KeyCode] or nil
	for _, group in modifierGroups do
		if group ~= own and (held[group.left] or held[group.right]) then
			const ok, down = pcall(input.IsModifierKeyDown, input, group.modifier)
			local stale = false
			if ok and down then
				pointerModifiersReported = pointerModifiersReported or not keyboard
			elseif ok and (keyboard or pointerModifiersReported) then
				stale = true
			elseif not Input.inWidget() then
				stale = not Native:IsKeyDown(group.left) and not Native:IsKeyDown(group.right)
			end

			if stale then
				clearKey(group.left)
				clearKey(group.right)
			end
		end
	end
end

function Input.setKeyCapture(callback)
	if not alive() then
		return false
	end

	capture = callback
end

function Input.isCapturingKeys()
	return capture ~= nil
end

local surfaces = setmetatable({}, { __mode = "k" })
local uiInputs = setmetatable({}, { __mode = "k" })
local uiCamera, lastCamera
local unlockFrames = 0
local pointerOwner

local function unlockPointer()
	pcall(function()
		Native.MouseBehavior = Enum.MouseBehavior.Default
	end)
end

function Input.claimPointer(owner)
	if not alive() then
		return false
	end

	pointerOwner = owner
	unlockFrames = 0
	local ok = pcall(function()
		Native.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end)
	return ok and Native.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition
end

function Input.releasePointer(owner)
	if pointerOwner ~= owner then
		return
	end

	pointerOwner = nil
	unlockFrames = 2
	unlockPointer()
end

local function pointerEnded(input)
	return input
		and (
			input.UserInputState == Enum.UserInputState.End
			or input.UserInputState == Enum.UserInputState.Cancel
		)
end

local uiRender = "EclipseUIPointer-" .. game:GetService("HttpService"):GenerateGUID(false)

local function visible(object, root)
	local node = object
	while node do
		if node:GetAttribute("EclipseHUDHidden") then
			return false
		end

		if
			node:IsA("GuiObject") and not node.Visible
			or node:IsA("LayerCollector") and not node.Enabled
		then
			return false
		end

		if node == root then
			return root.Parent ~= nil
		end

		node = node.Parent
	end

	return false
end

function Input.pointerOverUI(point)
	if Input.pointerInWidget and Input.pointerInWidget() then
		return widget
	end

	point = point or Native:GetMouseLocation()
	for root, regions in surfaces do
		for _, region in regions do
			if region.Parent and visible(region, root) then
				local p, s = region.AbsolutePosition, region.AbsoluteSize
				if
					point.X >= p.X
					and point.Y >= p.Y
					and point.X <= p.X + s.X
					and point.Y <= p.Y + s.Y
				then
					return root
				end
			end
		end
	end

	local ok, objects = pcall(function()
		return game:GetService("CoreGui"):GetGuiObjectsAtPosition(point.X, point.Y)
	end)
	if ok then
		for _, object in objects do
			local node = object
			local solid = false
			while node do
				if node:IsA("GuiObject") then
					solid = solid
						or node.Active
						or node:IsA("GuiButton")
						or node:IsA("TextBox")
						or node.BackgroundTransparency < 1
				end

				if surfaces[node] and solid and visible(object, node) then
					return node
				end

				node = node.Parent
			end
		end
	end

	return nil
end

function Input.isUIInput(input)
	return uiInputs[input] == true
end

function Input.isUIGestureActive()
	return uiCamera ~= nil
end

local function releaseUICamera()
	local current = uiCamera
	if not current then
		return
	end

	uiCamera = nil

	if current.navigation then
		Input.releasePointer(current)
	end

	for _, c in current.connections do
		c:Disconnect()
	end

	local recovery = require("Recovery")
	local owned = not recovery.owns or recovery.owns(current.camera)
	pcall(current.release)
	if current.navigation and not pointerOwner then
		unlockPointer()
	end

	if owned and current.camera.Parent and workspace.CurrentCamera == current.camera then
		current.camera.CFrame = current.frame
		current.camera.Focus = current.focus
	end

	lastCamera = nil
end

function Input.cancelCameraGestures()
	releaseUICamera()
	local navigation = require("State").BlenderNavigation
	if navigation then
		navigation.cancelCameraGestures()
	end

	pointerOwner = nil
	unlockFrames = 2
	unlockPointer()
end

local transformCamera
local continueTransformMovement

function Input.isTransformCameraActive()
	return transformCamera ~= nil
end

function Input.endTransformCamera(resumeNavigation)
	local current = transformCamera
	if not current then
		return
	end

	if
		resumeNavigation
		and current.looking
		and viewportFocused
		and workspace.CurrentCamera == current.camera
		and require("Recovery").owns(current.camera)
	then
		current.finishing = true
		return
	end

	local velocity = current.keyboardVelocity
	Input.endTransformLook(false)
	transformCamera = nil
	local state = require("State")
	local owned = require("Recovery").owns(current.camera)
	if
		resumeNavigation
		and owned
		and state.BlenderNavigation
		and viewportFocused
		and not state.LoadingProject
		and not state.PresentationHidden
		and not state.CameraPoseMode
		and not (state.CameraPreview and state.CameraPreview.isFull())
	then
		state.BlenderNavigation.resumeAfterTransform(current.camera, current.frame, current.focus, velocity)
	end

	current.release()
	if owned and current.camera.Parent and workspace.CurrentCamera == current.camera then
		current.camera.CFrame = current.frame
		current.camera.Focus = current.focus
	end

	lastCamera = nil
end

local function transformCameraAllowed()
	local state = require("State")
	return viewportFocused
		and not state.LoadingProject
		and not state.PresentationHidden
		and not state.CameraPoseMode
		and not (state.CameraPreview and state.CameraPreview.isFull())
end

function Input.beginTransformCamera()
	if not alive() then
		return false
	end

	if transformCamera then
		transformCamera.finishing = nil
		return
	end

	if not transformCameraAllowed() then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera or not camera.Parent then
		return
	end

	local recovery = require("Recovery")

	if camera.CameraType == Enum.CameraType.Scriptable and not recovery.owns(camera) then
		return
	end

	local navigation = require("State").BlenderNavigation
	local velocity = uiCamera and uiCamera.navigation and uiCamera.keyboardVelocity
		or navigation
			and navigation.movementForTransform
			and navigation.movementForTransform(camera)
	local current = {
		camera = camera,
		frame = camera.CFrame,
		focus = camera.Focus,
		keyboardVelocity = velocity,
		release = recovery.acquire(camera),
	}
	transformCamera = current

	Input.cancelCameraGestures()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = current.frame
	camera.Focus = current.focus
	continueTransformMovement(current)
end

local function maintainTransformCamera()
	local current = transformCamera
	if not current then
		return
	end

	local axis = require("State").Axis
	if current.finishing and not current.looking then
		Input.endTransformCamera(true)
		return
	end

	if
		not transformCameraAllowed()
		or not axis
		or not (current.finishing or axis:IsBlenderRotateMode() or axis:IsBlenderGrabMode() or axis:IsHoldingAxis())
		or workspace.CurrentCamera ~= current.camera
		or not current.camera.Parent
		or not require("Recovery").maintain(current.camera)
	then
		Input.endTransformCamera()
		return
	end

	current.camera.CameraType = Enum.CameraType.Scriptable
	current.camera.CFrame = current.frame
	current.camera.Focus = current.focus
end

local function applyUICamera()
	local current = uiCamera
	if not current or current.writing then
		return
	end

	if
		workspace.CurrentCamera ~= current.camera
		or not current.camera.Parent
		or not current.owner.Parent
		or not current.owner.Enabled
	then
		releaseUICamera()
		return
	end

	local preview = require("State").CameraPreview
	if preview and preview.isFull() then
		current.frame, current.focus = current.camera.CFrame, current.camera.Focus
		releaseUICamera()
		return
	end

	local recovery = require("Recovery")
	if recovery.maintain and not recovery.maintain(current.camera) then
		releaseUICamera()
		return
	end

	current.writing = true
	current.camera.CameraType = Enum.CameraType.Scriptable
	current.camera.CFrame = current.frame
	current.camera.Focus = current.focus
	current.writing = false
end

local walkKeys = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Q] = Vector3.new(0, -1, 0),
	[Enum.KeyCode.E] = Vector3.new(0, 1, 0),
}

local function navigationAllowed(owner)
	if not viewportFocused or capture or Input:GetFocusedTextBox() or Input.pointerInWidget() then
		return false
	end

	if not owner:IsA("ScreenGui") or owner:GetAttribute("EclipseConfirmationOpen") then
		return false
	end

	local region
	for _, candidate in surfaces[owner] or {} do
		if visible(candidate, owner) then
			region = candidate
			break
		end
	end

	if not region or owner:GetAttribute("EclipseRiggingViewport") then
		return false
	end

	local state = require("State")
	if state.PresentationHidden or state.LoadingProject or state.WorkspaceSelection then
		return false
	end

	if state.CameraPreview and (state.CameraPreview.isFull() or state.CameraPreview.hasFocus()) then
		return false
	end

	if state.GraphEditor and state.GraphEditor.hasFocus() then
		return false
	end

	local axis = state.Axis
	if
		axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
	then
		return false
	end

	for _, controller in { state.PropertyGizmo, state.CameraControls } do
		if controller and controller.isEditing() then
			return false
		end
	end

	if state.GreasePencil and state.GreasePencil.isDrawing() then
		return false
	end

	if require("Motion").isMoving() then
		return false
	end

	return region
end

local function moveView(current, dt)
	local point = Native:GetMouseLocation()
	local delta = current.lookDelta or Vector2.zero
	current.lookDelta = nil

	current.point = point
	if current.keyboardOnly then
		delta = Vector2.zero
	else
		Input.claimPointer(current)
	end

	local rotation = current.frame.Rotation
	if delta.Magnitude > 0 then
		current.lookReverse = current.lookReverse
			or (if current.frame.UpVector.Y < 0 then -1 else 1)
		local frame, axis = require("localOffset").lookView(
			current.frame,
			delta,
			0.005,
			current.lookReverse,
			current.pitchAxis
		)
		rotation, current.pitchAxis = frame.Rotation, axis
	end

	local move = Vector3.zero
	for key, direction in walkKeys do
		if not Input.isCameraKeyBlocked(key) and Native:IsKeyDown(key) then
			move += direction
		end
	end

	if move.Magnitude == 0 and delta.Magnitude == 0 and not current.keyboardVelocity then
		return
	end

	if move.Magnitude > 1 then
		move = move.Unit
	end

	local shifted = Native:IsKeyDown(Enum.KeyCode.LeftShift)
		or Native:IsKeyDown(Enum.KeyCode.RightShift)

	local speed = require("localOffset").keyboardSpeed(shifted)
	local localOffset = require("localOffset").keyboardOffset(
		current,
		move,
		speed,
		dt,
		Input.isCameraKeyBlocked(Enum.KeyCode.W),
		Input.isCameraKeyBlocked(Enum.KeyCode.Q)
	)
	local offset = rotation.RightVector * localOffset.X
		+ Vector3.yAxis * localOffset.Y
		- rotation.LookVector * localOffset.Z
	current.frame = CFrame.new(current.frame.Position + offset) * rotation
	current.focus = CFrame.new(current.frame.Position + current.frame.LookVector * current.distance)
end

local function stepNavigation(current, dt)
	if not navigationAllowed(current.owner) or not visible(current.region, current.owner) then
		releaseUICamera()
		return
	end

	if
		pointerEnded(current.input)
		or not Native:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	then
		releaseUICamera()
		return
	end

	moveView(current, dt)
end

local function walkingHeld()
	for key in walkKeys do
		if not Input.isCameraKeyBlocked(key) and Native:IsKeyDown(key) then
			return true
		end
	end

	return false
end

continueTransformMovement = function(current)
	if Input:GetFocusedTextBox() or capture or Input.pointerInWidget() then
		return
	end

	local right = Native:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if not right and not walkingHeld() then
		return
	end

	current.point = Native:GetMouseLocation()
	current.distance = math.max(0.1, (current.frame.Position - current.focus.Position).Magnitude)

	current.looking, current.keyboardOnly = true, not right
	if right then
		Input.claimPointer(current)
	end
end

local function releaseTransformRight()
	local current = transformCamera
	if current and current.looking and walkingHeld() then
		current.keyboardOnly, current.lookInput = true, nil
		current.point = Native:GetMouseLocation()
		Input.releasePointer(current)

		local axis = require("State").Axis
		if axis and axis.RebaseAfterCameraLook then
			axis:RebaseAfterCameraLook(current.point)
		end
	else
		Input.endTransformLook(true)
	end
end

function Input.isTransformLookActive()
	return transformCamera ~= nil and transformCamera.looking == true
end

function Input.isTransformPointerLookActive()
	return Input.isTransformLookActive() and transformCamera.keyboardOnly ~= true
end

function Input.endTransformLook(rebase)
	local current = transformCamera
	if not current or not current.looking then
		return
	end

	current.looking = nil
	current.lookDelta = nil
	current.keyboardOnly = nil
	current.lookInput = nil
	current.keyboardVelocity = nil
	Input.releasePointer(current)
	if
		rebase
		and workspace.CurrentCamera == current.camera
		and current.camera.Parent
		and require("Recovery").owns(current.camera)
	then
		current.camera.CFrame, current.camera.Focus = current.frame, current.focus
		local axis = require("State").Axis
		if axis and axis.FlushBlenderRotateInput then
			axis:FlushBlenderRotateInput()
		end

		if axis and axis.RebaseAfterCameraLook then
			axis:RebaseAfterCameraLook(Native:GetMouseLocation())
		end
	end
end

function Input.beginTransformLook(input)
	if not alive() then
		return false
	end

	local current = transformCamera
	if
		not current
		or current.looking and not current.keyboardOnly
		or not transformCameraAllowed()
		or workspace.CurrentCamera ~= current.camera
		or not current.camera.Parent
		or not require("Recovery").owns(current.camera)
		or Input:GetFocusedTextBox()
		or capture
		or Input.pointerInWidget()
		or Input.pointerOverUI()
		or pointerEnded(input)
	then
		return false
	end

	local axis = require("State").Axis
	if
		not axis
		or not (
			current.finishing
			or axis:IsHoldingAxis()
			or axis:IsBlenderGrabMode()
			or axis:IsBlenderRotateMode()
		)
	then
		return false
	end

	if axis.FlushBlenderRotateInput then
		axis:FlushBlenderRotateInput()
	end

	current.point = Native:GetMouseLocation()
	current.distance = math.max(0.1, (current.frame.Position - current.focus.Position).Magnitude)
	current.lookInput, current.looking, current.keyboardOnly = input, true, false
	Input.claimPointer(current)
	return true
end

local function stepTransformLook(dt)
	local current = transformCamera
	if not current or not current.looking then
		return
	end

	if current.keyboardOnly then
		if not walkingHeld() then
			Input.endTransformLook(true)
			return
		end
	elseif
		pointerEnded(current.lookInput)
		or not Native:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	then
		releaseTransformRight()
		if not current.looking then
			return
		end
	end

	if
		not transformCameraAllowed()
		or Input:GetFocusedTextBox()
		or capture
		or workspace.CurrentCamera ~= current.camera
		or not current.camera.Parent
		or not require("Recovery").maintain(current.camera)
	then
		Input.endTransformCamera()
		return
	end

	moveView(current, dt)
end

local function beginUIPointer(input, owner)
	local button = input.UserInputType
	if
		button ~= Enum.UserInputType.MouseButton1
		and button ~= Enum.UserInputType.MouseButton2
		and button ~= Enum.UserInputType.MouseButton3
	then
		return false
	end

	if pointerEnded(input) then
		return false
	end

	unlockFrames = 0
	owner = owner or Input.pointerOverUI()
	if not owner then
		if uiCamera and uiCamera.ending then
			releaseUICamera()
		end

		return false
	end

	uiInputs[input] = true

	if button == Enum.UserInputType.MouseButton1 then
		return true
	end

	local region
	if button == Enum.UserInputType.MouseButton2 then
		region = navigationAllowed(owner)
		if not region then
			return true
		end

		if uiCamera then
			releaseUICamera()
		end
	end

	if uiCamera then
		uiCamera.buttons[button] = true
		uiCamera.ending = nil
		return true
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return true
	end

	local frame, focus = camera.CFrame, camera.Focus
	if not region and lastCamera and lastCamera.camera == camera then
		frame, focus = lastCamera.frame, lastCamera.focus
	end

	local state = require("State")
	local navigation = state.BlenderNavigation
	if navigation then
		navigation.stop(false, "UI pointer gesture")
	end

	if region then
		if camera.CameraType == Enum.CameraType.Scriptable then
			return true
		end

		frame, focus = camera.CFrame, camera.Focus
	end

	local current = {
		camera = camera,
		owner = owner,
		frame = frame,
		focus = focus,
		buttons = { [button] = true },
		connections = {},
		release = require("Recovery").acquire(camera),
	}
	if region then
		current.navigation = true
		current.region = region
		current.point = Native:GetMouseLocation()
		current.input = input

		if input.GetPropertyChangedSignal then
			table.insert(
				current.connections,
				input:GetPropertyChangedSignal("UserInputState"):Connect(function()
					if uiCamera == current and pointerEnded(input) then
						releaseUICamera()
					end
				end)
			)
		end

		current.distance = math.max(0.1, (frame.Position - focus.Position).Magnitude)
		Input.claimPointer(current)
	end

	uiCamera = current
	for _, property in { "CFrame", "Focus", "CameraType" } do
		table.insert(
			current.connections,
			camera:GetPropertyChangedSignal(property):Connect(function()
				if uiCamera ~= current or current.writing or current.queued then
					return
				end

				if
					camera.CFrame == current.frame
					and camera.Focus == current.focus
					and camera.CameraType == Enum.CameraType.Scriptable
				then
					return
				end

				current.queued = true
				task.defer(function()
					current.queued = false
					if uiCamera == current then
						applyUICamera()
					end
				end)
			end)
		)
	end

	applyUICamera()
	return true
end

local function endUIPointer(input)
	if
		uiCamera
		and uiCamera.navigation
		and input.UserInputType == Enum.UserInputType.MouseButton2
	then
		uiInputs[input] = true
		releaseUICamera()
		return
	end

	if uiCamera and uiCamera.buttons[input.UserInputType] then
		uiInputs[input] = true
		uiCamera.buttons[input.UserInputType] = nil
		if not next(uiCamera.buttons) then
			uiCamera.ending = 2
		end
	end
end

local function renderUIPointer(dt)
	stepTransformLook(dt)
	maintainTransformCamera()
	if uiCamera then
		if uiCamera.navigation then
			stepNavigation(uiCamera, dt)
		end

		applyUICamera()
		if uiCamera then
			if uiCamera.ending then
				uiCamera.ending -= 1
				if uiCamera.ending <= 0 then
					releaseUICamera()
				end
			else
				local pressed = false
				for button in uiCamera.buttons do
					pressed = pressed or Native:IsMouseButtonPressed(button)
				end

				if pressed then
					uiCamera.missingSince = nil
				else
					uiCamera.missingSince = uiCamera.missingSince or os.clock()
					if os.clock() - uiCamera.missingSince > 0.3 then
						releaseUICamera()
					end
				end
			end
		end
	else
		local camera = workspace.CurrentCamera
		if unlockFrames > 0 and not pointerOwner then
			unlockFrames -= 1
			unlockPointer()
		end

		lastCamera = camera
				and {
					camera = camera,
					frame = camera.CFrame,
					focus = camera.Focus,
				}
			or nil
	end
end

game:GetService("RunService")
	:BindToRenderStep(uiRender, Enum.RenderPriority.Last.Value + 20, function(dt)
		if not alive() then
			return
		end

		local ok, err = pcall(renderUIPointer, dt)
		if not ok then
			Input.endTransformCamera()
			releaseUICamera()
			warn("[Eclipse] Camera navigation stopped: " .. tostring(err))
		end
	end)

local function duplicate(name, input)
	if not seen[name][input] then
		return false
	end

	if
		name ~= "InputBegan"
		or typeof(input) ~= "InputObject"
		or input.UserInputType ~= Enum.UserInputType.Keyboard
	then
		return true
	end

	const objects = keyObjects[input.KeyCode]
	return objects ~= nil and objects[input] == true
end

local function emit(name, input, processed, owner)
	if name == "InputChanged" and input and input.UserInputType == Enum.UserInputType.MouseMovement then
		local current = transformCamera and transformCamera.looking and transformCamera
			or uiCamera and uiCamera.navigation and uiCamera
		if current and pointerOwner == current and not current.keyboardOnly and not seen.InputChanged[input] then
			current.lookDelta = (current.lookDelta or Vector2.zero) + Vector2.new(input.Delta.X, input.Delta.Y) * math.max(0, Native.MouseDeltaSensitivity)
		end
	end
	if not alive() then
		return false
	end

	if name == "InputBegan" and input then
		if pointerEnded(input) then
			return
		end

		viewportFocused = true
	end

	if input then
		if duplicate(name, input) then
			return
		end

		seen[name][input] = true
	end

	if input and clipboardOwner and not (owner or Input.pointerOverUI()) then
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.MouseButton2
			or kind == Enum.UserInputType.MouseButton3
			or kind == Enum.UserInputType.MouseWheel
			or kind == Enum.UserInputType.MouseMovement
		then
			Input.releaseClipboard(true)
		end
	end

	if name == "InputBegan" then
		seen.InputEnded[input] = nil
		uiInputs[input] = nil
		capturedInputs[input] = nil
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			and Input.beginTransformLook(input)
		then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard
			and commandKeys[input.KeyCode]
			and (clipboardOwner or owner or Input.pointerOverUI() or require("UI").isAnimatorActive())
		then
			Input.focusClipboard()
		end

		beginUIPointer(input, owner)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local surface = owner or Input.pointerOverUI()
			if surface or require("UI").isAnimatorActive() then
				clipboardOwner = true
			else
				Input.releaseClipboard()
			end
		end
	elseif name == "InputEnded" then
		seen.InputBegan[input] = nil
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			and Input.isTransformLookActive()
		then
			releaseTransformRight()
			return
		end

		endUIPointer(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			task.delay(0, armClipboard)
		end
	elseif name == "WindowFocusReleased" then
		Input.releaseClipboard()
		Input.endTransformCamera()
		releaseUICamera()
		table.clear(uiInputs)
		table.clear(capturedInputs)
		for _, inputs in seen do
			table.clear(inputs)
		end
	end

	if name == "InputBegan" or name == "InputEnded" then
		reconcileModifiers(input)
	end

	if name == "WindowFocusReleased" then
		for key in keyReleases do
			clearKey(key)
		end

		table.clear(held)
		table.clear(captured)
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		keyRevision[input.KeyCode] = (keyRevision[input.KeyCode] or 0) + 1
		if name == "InputBegan" then
			held[input.KeyCode] = true
			if typeof(input) == "InputObject" then
				local key = input.KeyCode
				keyObjects[key] = keyObjects[key] or {}
				keyObjects[key][input] = true
				keyReleases[key] = keyReleases[key] or {}
				if not keyReleases[key][input] then
					keyReleases[key][input] = input
						:GetPropertyChangedSignal("UserInputState")
						:Connect(function()
							if
								input.UserInputState == Enum.UserInputState.End
								or input.UserInputState == Enum.UserInputState.Cancel
							then
								emit("InputEnded", input, false)
							end
						end)
				end
			end
		elseif name == "InputEnded" then
			clearKey(input.KeyCode)
		end
	end

	if
		name == "InputBegan"
		and input
		and input.UserInputType == Enum.UserInputType.Keyboard
		and walkKeys[input.KeyCode]
		and not Input.isCameraKeyBlocked(input.KeyCode)
		and transformCamera
		and not transformCamera.looking
		and transformCameraAllowed()
	then
		continueTransformMovement(transformCamera)
	end

	if Input.isTransformLookActive() and input then
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			and Input.isTransformPointerLookActive()
		then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape and name == "InputBegan" then
				Input.endTransformLook(true)
			elseif
				walkKeys[input.KeyCode]
				or input.KeyCode == Enum.KeyCode.LeftShift
				or input.KeyCode == Enum.KeyCode.RightShift
			then
				return
			end
		end
	end

	if name ~= "WindowFocusReleased" and input.UserInputType == Enum.UserInputType.Keyboard then
		if name == "InputBegan" and capture then
			captured[input.KeyCode] = true
			capturedInputs[input] = true
			capture(input)
			return
		elseif captured[input.KeyCode] then
			if name == "InputEnded" then
				captured[input.KeyCode] = nil
			end

			return
		end
	end

	if
		uiCamera
		and uiCamera.navigation
		and input
		and input.UserInputType == Enum.UserInputType.Keyboard
	then
		if input.KeyCode == Enum.KeyCode.Escape then
			releaseUICamera()
			return
		end

		if
			walkKeys[input.KeyCode] and not Input.isCameraKeyBlocked(input.KeyCode)
			or input.KeyCode == Enum.KeyCode.LeftShift
			or input.KeyCode == Enum.KeyCode.RightShift
		then
			return
		end
	end

	if clipboardFocus and focusSink and focusSink:IsFocused() and input and input.UserInputType == Enum.UserInputType.Keyboard then
		processed = false
	end

	if input and uiInputs[input] then
		events[name]:Fire(input, true)
	else
		events[name]:Fire(input, processed)
	end
end

for _, name in { "InputBegan", "InputChanged", "InputEnded", "WindowFocusReleased" } do
	local event = Instance.new("BindableEvent")
	events[name] = event
	Input[name] = event.Event
	seen[name] = setmetatable({}, { __mode = "k" })
	table.insert(
		nativeConnections,
		Native[name]:Connect(function(...)
			if not alive() then
				return
			end

			if name == "WindowFocusReleased" then
				viewportFocused = false
			end

			emit(name, ...)
		end)
	)
end

table.insert(
	nativeConnections,
	Native.WindowFocused:Connect(function()
		if not alive() then
			return
		end

		viewportFocused = true
	end)
)

table.insert(
	nativeConnections,
	game:GetService("RunService").Heartbeat:Connect(function()
		if not alive() then
			return
		end

		if clipboardOwner and not require("UI").isAnimatorActive() then
			Input.releaseClipboard()
		elseif clipboardFocus and not Input.pointerOverUI() then
			Input.releaseClipboard(true)
		else
			armClipboard(true)
		end
		table.clear(seen.InputChanged)

		if uiCamera and uiCamera.navigation then
			local current = uiCamera
			local ok, active = pcall(function()
				return viewportFocused
					and not pointerEnded(current.input)
					and Native:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
					and workspace.CurrentCamera == current.camera
					and current.camera.Parent
					and visible(current.region, current.owner)
			end)
			if not ok or not active then
				releaseUICamera()
			end
		end
	end)
)

function Input.inWidget()
	return widget ~= nil and widget.Enabled and (focused or over)
end

function Input.isWindowFocused()
	return viewportFocused
end

function Input.pointerInWidget()
	if not widget or not widget.Enabled or not over then
		return false
	end

	local point, size = widget:GetRelativeMousePosition(), widget.AbsoluteSize
	return point.X >= 0 and point.Y >= 0 and point.X < size.X and point.Y < size.Y
end

function Input:GetViewportMouseLocation()
	if not viewportFocused or Input.pointerInWidget() then
		return nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local point, size = Native:GetMouseLocation(), camera.ViewportSize
	if point.X < 0 or point.Y < 0 or point.X >= size.X or point.Y >= size.Y then
		return nil
	end

	return point
end

function Input.isGuiPointCompatible(gui)
	local dock = gui and gui:FindFirstAncestorWhichIsA("DockWidgetPluginGui")
	if dock then
		return dock == widget and Input.pointerInWidget()
	end

	return not Input.pointerInWidget()
end

local function widgetPointerHeld()
	for _, input in pressed do
		if
			(
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3
			) and not pointerEnded(input)
		then
			return true
		end
	end

	return false
end

function Input:GetMouseLocation()
	if widget and widget.Enabled and (over or widgetPointerHeld()) then
		return widget:GetRelativeMousePosition()
	end

	return Native:GetMouseLocation()
end

function Input.isPointerHeld()
	return widgetPointerHeld() or Native:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
end

function Input.isTimelinePress(input, container)
	if not container or not container.Parent then
		return false
	end

	if require("Motion").isMoving() then
		return false
	end

	local dock = container:FindFirstAncestorWhichIsA("DockWidgetPluginGui")
	if dock then
		return dock == widget and Input.pointerInWidget()
	end

	local point = input.Position
	local root = container:FindFirstAncestorWhichIsA("ScreenGui")
	local ok, objects = pcall(function()
		return game:GetService("CoreGui"):GetGuiObjectsAtPosition(point.X, point.Y)
	end)
	if ok then
		for _, object in objects do
			if object:IsDescendantOf(container) or object == container then
				return true
			end

			if object.Active or object:IsA("GuiButton") or object:IsA("TextBox") then
				local gui = object:FindFirstAncestorWhichIsA("ScreenGui")
				if
					gui
					and (
						gui == root
						or gui:GetAttribute("EclipseOwnedUI")
						or gui:GetAttribute("EclipseInstance")
					)
				then
					return false
				end
			end
		end
	end

	return true
end

function Input:GetFocusedTextBox()
	local box = Native:GetFocusedTextBox()
	if box and box ~= focusSink then return box end
	if Input.inWidget() and textBox and textBox ~= focusSink and textBox:IsFocused() then return textBox end
	return nil
end

function Input:IsKeyDown(key)
	const objects = keyObjects[key]
	if objects then
		for object in objects do
			if
				object.UserInputState == Enum.UserInputState.End
				or object.UserInputState == Enum.UserInputState.Cancel
			then
				clearKey(key)
				break
			end
		end
	end

	return held[key] == true or Native:IsKeyDown(key)
end

local function returnFocus(keep)
	const host = if widget and widget.Enabled and focused and Input.pointerInWidget()
		then widget
		else game:GetService("CoreGui")
	if not focusSink or not focusSink.Parent or focusSink.Parent.Parent ~= host then
		if focusSink and focusSink.Parent then
			focusSink.Parent:Destroy()
		end

		local gui = Instance.new(host == widget and "Frame" or "ScreenGui")
		gui.Name = "EclipseFocusSink"
		if gui:IsA("ScreenGui") then
			gui.ResetOnSpawn = false
			gui.DisplayOrder = -1000
		else
			gui.Size = UDim2.fromOffset(1, 1)
			gui.BackgroundTransparency = 1
		end
		gui.Archivable = false
		local box = Instance.new("TextBox")
		box.Name = "Sink"
		box.Size = UDim2.fromOffset(1, 1)
		box.BackgroundTransparency = 1
		box.TextTransparency = 1
		box.Text = ""
		box.ClearTextOnFocus = false
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if box.Text ~= "" then
				box.Text = ""
			end
		end)
		box.InputEnded:Connect(function(input)
			if alive() and input.UserInputType == Enum.UserInputType.Keyboard and held[input.KeyCode] then
				emit("InputEnded", input, false, widget)
			end
		end)
		box.Parent = gui
		gui.Parent = host
		focusSink = box
	end

	local box = focusSink
	clipboardFocus = keep == true
	if pcall(function()
		box:CaptureFocus()
	end) then
		if not keep then
			task.defer(function()
				if not clipboardFocus and box.Parent and box:IsFocused() then
					box:ReleaseFocus()
				end
			end)
		end
	end
end

local function clipboardModifierDown()
	for key in commandKeys do
		if Input:IsKeyDown(key) then
			return true
		end
	end
	return false
end

function Input.focusClipboard()
	if not alive() or not viewportFocused or capture or Input:GetFocusedTextBox() or not require("UI").isAnimatorActive() then
		return false
	end
	returnFocus(true)
	local focused = focusSink ~= nil and focusSink:IsFocused()
	clipboardOwner = clipboardOwner or focused
	return focused
end

function Input.ownsClipboard()
	return alive() and viewportFocused and not capture
		and not Input:GetFocusedTextBox() and require("UI").isAnimatorActive()
end

function Input.releaseClipboard(keepOwner)
	if keepOwner and clipboardOwner and clipboardModifierDown() then
		return
	end
	clipboardFocus = false
	if not keepOwner then
		clipboardOwner = false
	end
	if focusSink and focusSink.Parent and focusSink:IsFocused() then
		focusSink:ReleaseFocus()
	end
end

armClipboard = function(held)
	if
		not alive()
		or held and not clipboardModifierDown()
		or not viewportFocused
		or capture
		or clipboardFocus and focusSink and focusSink.Parent and focusSink:IsFocused()
		or Input.isPointerHeld()
		or Input:GetFocusedTextBox()
		or not require("UI").isAnimatorActive()
	then
		return
	end

	const state = require("State")
	if state.PresentationHidden or state.CameraPreview and state.CameraPreview.isFull() then
		return
	end

	const surface = Input.pointerOverUI()
	if surface == widget then
		if not surface or not focused then
			return
		end
	elseif surface ~= require("UI").EclipseGUI then
		return
	end

	clipboardOwner = true
	returnFocus(true)
end

function Input.focusEditor()
	if not alive() then
		return false
	end

	if Input:GetFocusedTextBox() or capture then
		return false
	end

	returnFocus()
	return true
end

function Input.detach()
	Input.endTransformCamera()
	for key in keyReleases do
		clearKey(key)
	end

	if focusSink and focusSink.Parent then
		focusSink.Parent:Destroy()
	end

	focusSink = nil
	clipboardFocus, clipboardOwner = false, false
	if uiCamera and uiCamera.owner == widget then
		releaseUICamera()
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	table.clear(held)
	table.clear(pressed)
	widget, focused, over, textBox = nil, false, false, nil
end

function Input.attach(target)
	if not alive() then
		return false
	end

	Input.detach()
	widget = target
	local prunedAt = 2048

	local function connect(signal, callback)
		if #connections > prunedAt then
			local live = {}
			for _, connection in connections do
				if connection.Connected then
					table.insert(live, connection)
				end
			end

			connections = live
			prunedAt = math.max(2048, #live * 2)
		end

		table.insert(
			connections,
			signal:Connect(function(...)
				if alive() then
					callback(...)
				end
			end)
		)
	end

	local function release()
		focused, over, textBox = false, false, nil
		clearModifiers()

		local pending = table.clone(pressed)
		table.clear(pressed)
		for _, input in pending do
			if input.UserInputType == Enum.UserInputType.Keyboard then
				clearKey(input.KeyCode)
			end

			emit("InputEnded", input, true, widget)
		end
	end

	connect(widget.WindowFocused, function()
		focused = true
		viewportFocused = true
	end)
	connect(widget.WindowFocusReleased, release)
	connect(widget:GetPropertyChangedSignal("Enabled"), function()
		if not widget.Enabled then
			release()
		end
	end)

	local function forward(name, input)
		if not widget or not widget.Enabled or duplicate(name, input) then
			return
		end

		const kind = input.UserInputType
		if
			name ~= "InputEnded"
			and (
				kind == Enum.UserInputType.MouseMovement
				or kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.MouseButton3
				or kind == Enum.UserInputType.MouseWheel
			)
		then
			const point, size = widget:GetRelativeMousePosition(), widget.AbsoluteSize
			over = point.X >= 0 and point.Y >= 0 and point.X < size.X and point.Y < size.Y
		end

		if name == "InputBegan" then
			focused = true
			pressed[tostring(input.UserInputType) .. tostring(input.KeyCode)] = input
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				held[input.KeyCode] = true
			end
		elseif name == "InputEnded" then
			held[input.KeyCode] = nil
			pressed[tostring(input.UserInputType) .. tostring(input.KeyCode)] = nil
		end

		emit(name, input, textBox ~= nil, widget)
	end

	local watched = {}
	local pruneAt = 256

	local function watch(object)
		if not object:IsA("GuiObject") or watched[object] then
			return
		end

		local ancestor = object.Parent
		local surface = true
		while ancestor and ancestor ~= widget do
			if ancestor:IsA("GuiObject") then
				surface = false
				break
			end

			ancestor = ancestor.Parent
		end

		local sink = surface or object:IsA("GuiButton") or object.Active
		if not sink and not object:IsA("TextBox") then
			return
		end

		if #connections > pruneAt then
			local live = {}
			for _, connection in connections do
				if connection.Connected then
					table.insert(live, connection)
				end
			end

			connections = live
			pruneAt = math.max(256, #live * 2)
		end

		local owned = {}

		local function own(signal, callback)
			local connection = signal:Connect(function(...)
				if alive() then
					callback(...)
				end
			end)
			table.insert(owned, connection)
			table.insert(connections, connection)
		end

		watched[object] = owned
		if sink then
			for _, name in { "InputBegan", "InputChanged", "InputEnded" } do
				own(object[name], function(input)
					forward(name, input)
				end)
			end
		end

		if object:IsA("TextBox") then
			own(object.Focused, function()
				textBox = object
			end)
			own(object.FocusLost, function()
				if textBox == object then
					textBox = nil
				end
			end)
		end

		local function removed()
			if object:IsDescendantOf(target) then
				return
			end

			if textBox == object then
				textBox = nil
			end

			for _, connection in owned do
				connection:Disconnect()
			end

			watched[object] = nil
		end

		own(object.AncestryChanged, removed)
	end

	for _, object in widget:GetDescendants() do
		watch(object)
	end

	connect(widget.DescendantAdded, watch)
	local surface = widget:FindFirstChild("Frame")
	if surface then
		local pendingReturn = false
		connect(surface.MouseEnter, function()
			over = true
			pendingReturn = false
		end)
		connect(surface.MouseLeave, function()
			over = false
			pendingReturn = true
		end)
		connect(game:GetService("RunService").Heartbeat, function()
			if not pendingReturn then
				return
			end

			if
				not widget
				or not widget.Enabled
				or not focused
				or over
				or textBox and textBox ~= focusSink
				or capture
			then
				pendingReturn = false
				return
			end

			for _, button in
				{
					Enum.UserInputType.MouseButton1,
					Enum.UserInputType.MouseButton2,
					Enum.UserInputType.MouseButton3,
				}
			do
				if Native:IsMouseButtonPressed(button) then
					return
				end
			end

			if widgetPointerHeld() then
				return
			end

			pendingReturn = false
			returnFocus(clipboardFocus and clipboardModifierDown())
		end)
	end
end

function Input.attachSurface(root, regions)
	if not alive() then
		return false
	end

	surfaces[root] = regions or {}
	local owned, watched = {}, {}
	local pruneAt = 2048

	local function connect(signal, callback)
		if #owned > pruneAt then
			local live = {}
			for _, c in owned do
				if c.Connected then
					table.insert(live, c)
				end
			end

			owned = live
			local nativeLive = {}
			for _, c in nativeConnections do
				if c.Connected then
					table.insert(nativeLive, c)
				end
			end

			nativeConnections = nativeLive
			pruneAt = math.max(2048, #owned * 2)
		end

		local c = signal:Connect(function(...)
			if alive() then
				callback(...)
			end
		end)
		table.insert(owned, c)
		table.insert(nativeConnections, c)
		return c
	end

	local function watch(object)
		if not object:IsA("GuiObject") or watched[object] then
			return
		end

		if object.Parent ~= root and not object.Active and not object:IsA("GuiButton") then
			return
		end

		local links = {}
		watched[object] = links
		for _, name in { "InputBegan", "InputChanged", "InputEnded" } do
			table.insert(
				links,
				connect(object[name], function(input)
					if
						root.Enabled
						and root.Parent
						and object:IsDescendantOf(root)
						and not Input.pointerInWidget()
					then
						local owner
						if name == "InputBegan" then
							owner = (
								object.Active
								or object:IsA("GuiButton")
								or object.BackgroundTransparency < 1
							)
									and visible(object, root)
									and root
								or Input.pointerOverUI()
						end

						emit(name, input, Input:GetFocusedTextBox() ~= nil, owner)
					end
				end)
			)
		end

		table.insert(
			links,
			connect(object.Destroying, function()
				for _, c in links do
					c:Disconnect()
				end

				watched[object] = nil
			end)
		)
	end

	for _, object in root:GetDescendants() do
		watch(object)
	end

	connect(root.DescendantAdded, watch)
	connect(root.Destroying, function()
		surfaces[root] = nil
		if uiCamera and uiCamera.owner == root then
			releaseUICamera()
		end

		for _, c in owned do
			c:Disconnect()
		end

		table.clear(owned)
	end)
end

function Input.mouse(original)
	if not alive() then
		return false
	end

	table.insert(
		nativeConnections,
		original.Button2Up:Connect(function()
			if not alive() then
				return
			end

			if uiCamera and uiCamera.navigation then
				releaseUICamera()
			end
		end)
	)
	local numeric = {
		["0"] = "Zero",
		["1"] = "One",
		["2"] = "Two",
		["3"] = "Three",
		["4"] = "Four",
		["5"] = "Five",
		["6"] = "Six",
		["7"] = "Seven",
		["8"] = "Eight",
		["9"] = "Nine",
	}
	local punctuation = {
		[","] = "Comma",
		["."] = "Period",
		["/"] = "Slash",
		[";"] = "Semicolon",
		["'"] = "Quote",
		["["] = "LeftBracket",
		["]"] = "RightBracket",
		["\\"] = "BackSlash",
		["-"] = "Minus",
		["="] = "Equals",
		["`"] = "Backquote",
		["<"] = "Comma",
		[">"] = "Period",
		["?"] = "Slash",
		[":"] = "Semicolon",
		['"'] = "Quote",
		["{"] = "LeftBracket",
		["}"] = "RightBracket",
		["|"] = "BackSlash",
		["_"] = "Minus",
		["+"] = "Equals",
		["~"] = "Backquote",
	}

	local function keyFor(value)
		if type(value) ~= "string" or #value ~= 1 then
			return
		end

		local name = numeric[value] or punctuation[value] or value:upper()
		local ok, code = pcall(function()
			return Enum.KeyCode[name]
		end)
		return ok and code or nil
	end

	table.insert(
		nativeConnections,
		original.KeyDown:Connect(function(value)
			if not alive() then
				return
			end

			local code = keyFor(value)
			if not code or not Native:IsKeyDown(code)
				or nativeCommandDown()
				or Input:IsKeyDown(code) and held[code] then
				return
			end

			local revision = keyRevision[code]
			task.defer(function()
				if
					alive()
					and keyRevision[code] == revision
					and Native:IsKeyDown(code)
					and not nativeCommandDown()
					and not held[code]
					and (capture or not Input:GetFocusedTextBox())
				then
					local input = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = code }
					emit("InputBegan", input, false)
					if numeric[value] and not Native:IsKeyDown(code) then
						emit("InputEnded", input, false)
					end
				end
			end)
		end)
	)
	table.insert(
		nativeConnections,
		original.KeyUp:Connect(function(value)
			if not alive() then
				return
			end

			local code = keyFor(value)
			if code and held[code] then
				emit(
					"InputEnded",
					{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = code },
					false
				)
			end
		end)
	)
	local move = Instance.new("BindableEvent")
	table.insert(mouseEvents, move)
	table.insert(
		nativeConnections,
		original.Move:Connect(function()
			if not alive() then
				return
			end

			move:Fire()
		end)
	)
	table.insert(
		nativeConnections,
		Input.InputChanged:Connect(function(input)
			if not alive() then
				return
			end

			if Input.inWidget() and input.UserInputType == Enum.UserInputType.MouseMovement then
				move:Fire()
			end
		end)
	)
	return setmetatable({ Move = move.Event }, {
		__index = function(_, key)
			if key == "x" or key == "X" then
				return Input:GetMouseLocation().X
			end

			if key == "y" or key == "Y" then
				return Input:GetMouseLocation().Y
			end

			return original[key]
		end,
	})
end

function Input.destroy()
	if destroyed then
		return
	end

	destroyed = true
	for _, connection in nativeConnections do
		connection:Disconnect()
	end

	table.clear(nativeConnections)
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	for key in keyReleases do
		clearKey(key)
	end

	game:GetService("RunService"):UnbindFromRenderStep(uiRender)
	pcall(Input.detach)
	pcall(releaseUICamera)
	if focusSink and focusSink.Parent then
		focusSink.Parent:Destroy()
	end

	focusSink = nil
	clipboardFocus, clipboardOwner = false, false
	widget, focused, over, textBox = nil, false, false, nil
	capture = nil
	viewportFocused = false
	table.clear(held)
	table.clear(pressed)
	table.clear(captured)
	table.clear(uiInputs)
	table.clear(capturedInputs)
	table.clear(surfaces)
	for _, event in events do
		event:Destroy()
	end

	for _, event in mouseEvents do
		event:Destroy()
	end

	table.clear(mouseEvents)
end

if owner then
	table.insert(nativeConnections, owner.Destroying:Connect(Input.destroy))
end

return setmetatable(Input, {
	__index = function(_, key)
		local value = Native[key]
		if typeof(value) == "function" then
			return function(_, ...)
				return value(Native, ...)
			end
		end

		return value
	end,
})
