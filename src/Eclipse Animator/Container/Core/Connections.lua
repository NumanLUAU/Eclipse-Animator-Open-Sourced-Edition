--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local ViewportSelection = require("ViewportSelection")
local ArmatureRuntime = require("ArmatureRuntime")
local Selection = game:GetService("Selection")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("State")
local Config = require("Config")
local UI = require("UI")
local Project = require("Project")
local MotorMath = require("MotorMath")
local BoneMotor = require("BoneMotor")
local ArmatureImport = require("ArmatureImport")
local BoneIK = require("BoneIK")
local LimbIK = require("LimbIK")
local HeadStabilizer = require("HeadStabilizer")
local Notification = require("Notification")
local Alert = require("Alert")
local WindowFX = require("WindowFX")
local EditShortcuts = require("EditShortcuts")
local EventPlayback = require("EventPlayback")

local Origin = require("Origin")
local WorkBudget = require("WorkBudget")
local CameraRig = require("CameraRig")
local Connections = {}
local TransformPreferences = require("Preferences")
local transformControllers =
	{ "PropertyGizmo", "CameraControls", "EffectHandles", "AttachmentHandles", "PivotEditor" }
local transformHost
local TransformWindows = require("Motion")
function Connections.isPlaytestActive()
	return false
end

function Connections.prepareTransformVisibility()
	TransformWindows.watchFloatingGui(UI.EclipseGUI)
	TransformWindows.watchFloatingGui(UI.MiscGUI)
	if transformHost and transformHost.Parent then
		return
	end

	local frame = UI.AnimatorFrame
	if not frame or not frame.Parent then
		return
	end

	local host = Instance.new("Frame")
	host.Name = "EclipseTransformVisibility"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromScale(1, 1)
	host.ZIndex = frame.ZIndex
	host.Active = false
	host.Parent = frame.Parent
	frame.Parent = host
	transformHost = host
end

function Connections.updateTransformVisibility(forceShow)
	local host, frame = transformHost, UI.AnimatorFrame
	if not host or not host.Parent or not frame then
		TransformWindows.setFloatingHidden(false)
		return
	end

	local hidden = false
	if
		not forceShow
		and TransformPreferences.get("HideAnimatorDuringTransform")
		and frame.Visible
		and UI.EclipseGUI.Enabled
		and not State.LoadingProject
		and not State.PresentationHidden
		and UI.isAnimatorActive()
		and (not UserInputService.isWindowFocused or UserInputService.isWindowFocused())
	then
		local axis = State.Axis
		local keyboard = axis and (axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
		local gizmo = axis and axis:IsHoldingAxis() and not keyboard
		if not keyboard then
			for _, name in transformControllers do
				local controller = State[name]
				if controller and controller.isEditing and controller.isEditing() then
					gizmo = true
					break
				end
			end
		end

		hidden = (
			keyboard and TransformPreferences.get("HideAnimatorForKeyboard")
			or gizmo and TransformPreferences.get("HideAnimatorForGizmos")
		) == true
	end

	TransformWindows.setFloatingHidden(hidden)
	local animatorHidden = hidden
		and frame.Parent == host
		and frame:GetAttribute("EclipseDocked") ~= true
	if host.Visible == animatorHidden then
		host.Visible = not animatorHidden
	end
end

function Connections.blankSelectionTarget(hit)
	if not hit or not hit:IsA("BasePart") or hit.Locked or not hit:IsDescendantOf(workspace) then
		return nil
	end

	if workspace.CurrentCamera and hit:IsDescendantOf(workspace.CurrentCamera) then
		return nil
	end

	local nearest, current = nil, hit.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			nearest = nearest or current
			if
				current:FindFirstChildOfClass("Humanoid")
				or current:FindFirstChildOfClass("AnimationController")
			then
				return current
			end
		end

		current = current.Parent
	end

	return nearest or hit
end

function Connections.selectInBlankFile(hit, additive)
	if UserInputService.pointerOverUI() or UserInputService.isUIGestureActive() then
		return false
	end

	if #State.getAllRigs() > 0 then
		return false
	end

	local target = Connections.blankSelectionTarget(hit)
	local selected = additive and Selection:Get() or {}
	if target then
		local at = table.find(selected, target)
		if at then
			table.remove(selected, at)
		else
			table.insert(selected, target)
		end
	end

	Selection:Set(selected)
	return true
end

local recordingInventories = {}

local function clearInventory(rig)
	local entry = recordingInventories[rig]
	if not entry then
		return
	end

	for _, connection in entry.connections do
		connection:Disconnect()
	end

	for _, row in entry.watched do
		for _, connection in row do
			connection:Disconnect()
		end
	end

	recordingInventories[rig] = nil
end

local function recordingItems(rig)
	local entry = recordingInventories[rig]
	if not entry then
		entry = {
			dirty = true,
			connections = {},
			watched = {},
			pending = {},
			bones = {},
			transforms = {},
		}
		recordingInventories[rig] = entry

		local function invalidate(object)
			if object:IsA("Motor6D") or object:IsA("Bone") then
				entry.dirty = true
			end
		end

		table.insert(entry.connections, rig.DescendantAdded:Connect(invalidate))
		table.insert(entry.connections, rig.DescendantRemoving:Connect(invalidate))
		table.insert(
			entry.connections,
			rig.Destroying:Connect(function()
				clearInventory(rig)
			end)
		)
	end

	if entry.dirty then
		local retained = {}
		table.clear(entry.bones)
		for _, object in rig:GetDescendants() do
			if object:IsA("Bone") then
				table.insert(entry.bones, object)
			end

			if not (object:IsA("Motor6D") or object:IsA("Bone")) then
				continue
			end

			retained[object] = true
			if entry.watched[object] then
				continue
			end

			local function changed()
				entry.pending[object] = true
			end

			local row = {
				object
					:GetPropertyChangedSignal(object:IsA("Motor6D") and "C0" or "CFrame")
					:Connect(changed),
			}
			if object:IsA("Bone") then
				table.insert(row, object.AttributeChanged:Connect(changed))
			end

			entry.watched[object] = row
			changed()
		end

		for object, row in entry.watched do
			if retained[object] then
				continue
			end

			for _, connection in row do
				connection:Disconnect()
			end

			entry.watched[object], entry.pending[object], entry.transforms[object] = nil, nil, nil
		end

		entry.dirty = false
	end

	for _, bone in entry.bones do
		local transform = bone.Transform
		if entry.transforms[bone] ~= transform then
			entry.transforms[bone] = transform
			entry.pending[bone] = true
		end
	end

	local pending = entry.pending
	if not next(pending) then
		return pending
	end

	entry.pending = {}
	return pending
end

local wasPlaying = false
local markersHiddenForPlayback = false

local nativeEditUntil, nativeEditObjects, nativeEditReleased = 0, {}, false

function Connections.noteNativeEdit(objects)
	nativeEditUntil = os.clock() + 0.5
	nativeEditObjects = table.clone(objects)
	nativeEditReleased = false
end

local function expireNativeEdit()
	if not next(nativeEditObjects) then
		return
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		nativeEditReleased = true
	end
	if nativeEditReleased and os.clock() > nativeEditUntil then
		nativeEditUntil, nativeEditObjects = 0, {}
	end
end

function Connections.canRecordExternal(motor)
	if UserInputService.isWindowFocused and not UserInputService.isWindowFocused() then return false end
	if os.clock() > nativeEditUntil and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return false end
	local object = typeof(motor) == "Instance" and motor or motor.Part1
	for _, selected in nativeEditObjects do
		if selected.Parent and (object == selected or object:IsDescendantOf(selected) or motor.Part1 and (motor.Part1 == selected or motor.Part1:IsDescendantOf(selected))) then return true end
	end
	return false
end

function Connections.stepRecording()
	expireNativeEdit()
	if State.WorkspaceSelection then
		return
	end

	if State.LoadingProject or State.PhysicsSimulating then
		return
	end

	if require("Visibility").bonesHidden() then
		return
	end

	local timeline = State.Timeline:GetState()
	if timeline.Exporting or State.LiveSession and State.LiveSession.isApplying() then
		return
	end

	local stoppedPlayback = wasPlaying and not timeline.Playing
	wasPlaying = timeline.Playing
	if not State.currentRig or not UI.isAnimatorActive() then
		for rig in recordingInventories do
			clearInventory(rig)
		end

		return
	end

	if timeline.Playing then
		return
	end

	if State.CameraPreview and State.CameraPreview.isViewRotating() then
		return
	end

	if require("History").isApplying() then
		return
	end

	local manipulating = State.Axis:IsHoldingAxis()
		or State.Axis:IsBlenderGrabMode()
		or State.Axis:IsBlenderRotateMode()
		or (State.PropertyGizmo and State.PropertyGizmo.isEditing())
		or (State.PivotEditor and State.PivotEditor.isActive())
	if manipulating then
		return
	end

	local graphEditing = State.GraphEditor and State.GraphEditor.isInteracting()
	local suppress = graphEditing
		or stoppedPlayback
		or not timeline.Recording
		or timeline.Playing
		or State.Timeline:IsDraggingPlayhead()
		or (os.clock() - (timeline.LastPoseApplyClock or 0)) < 0.05

	local sanitize = State.UIHelpers and State.UIHelpers.SanitizeName
		or function(str)
			return tostring(str or ""):gsub("%s+", "")
		end

	local rigs = State.getAllRigs()
	for rig in recordingInventories do
		if not table.find(rigs, rig) then
			clearInventory(rig)
		end
	end

	for _, rig in ipairs(rigs) do
		if ArmatureRuntime.isRig(rig) then
			continue
		end

		for motor in recordingItems(rig) do
			if motor:IsA("Motor6D") then
				local last = State.lastCFrames[motor]
				local compensated = MotorMath.consumeParentCompensation(motor, motor.C0, last)
				if
					not suppress
					and not compensated
					and last
					and motor.C0 ~= last
					and Connections.canRecordExternal(motor)
					and motor.Part1
					and not HeadStabilizer.isCompensated(motor, motor.C0)
					and (not LimbIK.isDriven(motor, timeline.CurrentTime) or LimbIK.isDirty(motor))
				then
					State.Timeline:RecordChangedKeyframeForMotorAtCurrentTime(
						motor.Part1,
						motor,
						motor.C0,
						last,
						sanitize
					)
					State.currentProjectSaved = false
				end

				State.lastCFrames[motor] = motor.C0
			elseif
				motor:IsA("Bone") and not motor:GetAttribute("EclipseArmatureSkinningHelper")
			then
				local adapter = BoneMotor.get(motor)
				local c0 = adapter.C0
				local last = State.lastCFrames[adapter]
				local compensated = MotorMath.consumeParentCompensation(adapter, c0, last)
				if not suppress and not compensated and last and c0 ~= last and Connections.canRecordExternal(adapter) then
					State.Timeline:RecordChangedKeyframeForMotorAtCurrentTime(
						motor,
						adapter,
						c0,
						last,
						sanitize
					)
					State.currentProjectSaved = false
				end

				State.lastCFrames[adapter] = c0
			end
		end
	end
end

local attached = false
local connections = {}

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

function Connections.destroy()
	Project.finishLiveRecording(false)
	ViewportSelection.cancel()
	Connections.updateTransformVisibility(true)
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	if State.pendingScoreHoldConnection then
		State.pendingScoreHoldConnection:Disconnect()
		State.pendingScoreHoldConnection = nil
	end

	for rig in recordingInventories do
		clearInventory(rig)
	end

	for _, name in
		{
			"LiveSession",
			"GreasePencil",
			"ScreenEffects",
			"AnimationCleanup",
			"GraphEditor",
			"ImagePreviewer",
		}
	do
		if State[name] then
			pcall(State[name].destroy)
		end
	end

	if State.EffectsWindow then
		pcall(State.EffectsWindow.close, true)
	end

	EditShortcuts.destroy()
	EventPlayback.clear()
	if State.Axis then
		State.Axis:ClearBlenderRotateInput()
	end

	if State.Rig then
		State.Rig:StopSelectionSync()
	end

	ArmatureRuntime.clear()
	attached = false
end

function Connections.stepPlayback(dt)
	if State.LoadingProject or State.PhysicsSimulating then
		return
	end

	if State.Timeline:GetState().Exporting then
		return
	end

	local fullCamera = State.CameraPreview and State.CameraPreview.isFull()
	if not require("Visibility").isPlaybackActive() then
		EventPlayback.suspend()
		return
	end

	if Project.hasLiveRecording() and (not State.Timeline:GetState().Playing or not State.Timeline:GetState().Recording) then
		Project.finalizeCurrentManipulation()
		Project.finishLiveRecording(false)
	end
	local recording = Project.captureLiveRecording()
	State.Timeline:AdvancePlayback(dt)
	Project.restoreLiveRecording(recording)
	if recording and not State.Timeline:GetState().Playing then
		Project.finalizeCurrentManipulation()
	elseif not State.Timeline:GetState().Playing or not State.Timeline:GetState().Recording then
		Project.finishLiveRecording(false)
	end
	if State.CameraPreview then
		State.CameraPreview.syncCamera(dt)
	end

	if State.ScreenEffects then
		State.ScreenEffects.step()
	end

	local hideMarkers = require("Visibility").bonesHidden()
		or (State.PivotEditor ~= nil and State.PivotEditor.isActive())
	local playbackHidden = State.Timeline:GetState().Playing and not State.Timeline:GetState().Recording
	State.Axis:SetPlaybackHidden(hideMarkers or playbackHidden, hideMarkers)
	if markersHiddenForPlayback and not playbackHidden and not hideMarkers then
		for _, rig in State.getAllRigs() do
			State.Rig:UpdateBonesFollowRig(rig)
		end
	end

	markersHiddenForPlayback = playbackHidden
end

local function attach()
	if attached then
		return
	end

	attached = true
	Connections.prepareTransformVisibility()
	connect(UI.ClosingEvent.Event, function()
		Connections.updateTransformVisibility(true)
	end)
	connect(UserInputService.WindowFocusReleased, function()
		Connections.updateTransformVisibility(true)
	end)
	connect(
		UI.AnimatorFrame:GetAttributeChangedSignal("EclipseDocked"),
		Connections.updateTransformVisibility
	)
	wasPlaying = false
	UI.EclipseGUI.Destroying:Once(Connections.destroy)
	require("UserInputService").attachSurface(UI.EclipseGUI, { UI.AnimatorFrame, UI.PrimaryFrame })
	require("UserInputService").attachSurface(UI.MiscGUI)
	EditShortcuts.init(require("ProjectData").getPlugin())
	connect(UI.EclipseGUI.Destroying, EditShortcuts.destroy)

	local function clearRotationInput()
		if State.Axis then
			State.Axis:ClearBlenderRotateInput()
		end
	end

	connect(UI.EclipseGUI.Destroying, clearRotationInput)
	connect(UI.ClosingEvent.Event, clearRotationInput)

	local function finalizeCurrentManipulation()
		if State.EffectHandles and State.EffectHandles.isEditing() then
			State.EffectHandles.finish(false)
		end

		if State.Axis:IsBlenderRotateMode() then
			State.Axis:QueueBlenderRotateInput(UserInputService:GetViewportMouseLocation())
		end

		return Project.finalizeCurrentManipulation()
	end

	require("Visibility").beforeHide = finalizeCurrentManipulation
	require("History").setBeforeUndoRedo(function()
		State.Timeline:CancelTimelineKeyframeDrag()
		if State.CameraPreview and State.CameraPreview.isViewRotating() then
			State.CameraPreview.finishViewRotation(false)
		elseif State.EffectHandles and State.EffectHandles.isEditing() then
			State.EffectHandles.finish(false)
		elseif State.CameraControls and State.CameraControls.isEditing() then
			State.CameraControls.finish(false)
		elseif State.Timeline:IsBlenderKeyframeTransformActive() then
			State.Timeline:ConfirmBlenderKeyframeTransform()
		else
			finalizeCurrentManipulation()
		end
	end)

	local function refreshVisibleSelection()
		if UI.EclipseGUI.Enabled and not UI.isAnimatorActive() then
			Project.updateUI()
		end
	end

	connect(UI.EclipseGUI:GetPropertyChangedSignal("Enabled"), refreshVisibleSelection)
	connect(UI.PrimaryFrame:GetPropertyChangedSignal("Visible"), refreshVisibleSelection)

	connect(Selection.SelectionChanged, function()
		if ViewportSelection.active() then
			return
		end

		if require("History").nativeEcho() then
			return
		end

		if State.WorkspaceSelection then
			return
		end

		WorkBudget.settle()
		if State.LoadingProject or State.PhysicsSimulating then
			return
		end

		if require("Visibility").bonesHidden() then
			return
		end

		if State.ignoreSelectionChanged then
			return
		end

		if not UI.EclipseGUI.Enabled then
			return
		end

		if
			UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
			or State.BlenderNavigation and State.BlenderNavigation.isDragging()
		then
			return
		end

		if State.Axis:IsHoldingAxis() then
			State.ignoreSelectionChanged = true
			Selection:Set({})
			State.ignoreSelectionChanged = false
			return
		end

		local selected = Selection:Get()
		if State.CameraTargets and State.CameraTargets.selectionChanged(selected) then
			State.ignoreSelectionChanged = true
			Selection:Set({})
			State.ignoreSelectionChanged = false
			return
		end

		if #selected == 1 and UI.isAnimatorActive() then
			local display = require("CameraDisplay")
			local target = display.targetProxy(selected[1])
			if target and display.selectTarget(target) then
				State.ignoreSelectionChanged = true
				Selection:Set({})
				State.ignoreSelectionChanged = false
				return
			end
		end

		if UI.isAnimatorActive() and State.currentRig then
			if
				#selected > 0
				and workspace.CurrentCamera
				and selected[1]:IsDescendantOf(workspace.CurrentCamera)
			then
				State.ignoreSelectionChanged = true
				Selection:Set({})
				State.ignoreSelectionChanged = false
				return
			end

			if #selected == 1 and not (State.PropertyGizmo and State.PropertyGizmo.isEditing()) then
				State.Rig:SelectPropertyPart(selected[1])
			end

			State.Axis:RefreshBoneFade()
			return
		end

		State.Rig:FadeSelectionBones(State.currentRig, selected)

		Project.updateUI()
	end)

	local pendingActiveTool
	local viewportPress

	local function selectViewportClick()
		if not State.Axis:IsHoldingAxis() then
			if
				require("MarkerHandles").select(
					workspace.CurrentCamera,
					UserInputService:GetViewportMouseLocation(),
					UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
						or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				)
			then
				return
			end

			local bone = State.Axis:GetBoneUnderMouse()
			local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

			if bone then
				local item = State.Rig._FindItemForBone and State.Rig:_FindItemForBone(bone) or nil
				if
					item
					and (
						not bone:GetAttribute("EclipseLimbControl")
						or item.itemKind == "ikcontrol"
					)
				then
					if ctrlHeld then
						State.Rig:ToggleItemSelection(item)
					else
						State.Rig:SetSingleItemSelection(item)
					end
				else
					if ctrlHeld then
						State.Axis:ToggleSelection(bone)
					else
						State.Axis:SelectBone(bone)
					end
				end

				if State.Axis:GetSelectedBone() == bone then
					State.Rig:RevealBone(bone)
				end
			else
				if State.Rig:SelectPropertyUnderMouse() then
					return
				end

				if not ctrlHeld then
					if State.Rig.ClearItemSelection then
						State.Rig:ClearItemSelection()
					else
						State.Axis:SelectBone(nil)
					end
				end
			end
		end
	end

	local function beginActiveTool(pending)
		if
			State.Axis:GetSelectedBone() ~= pending.bone
			or not State.Axis:IsBoneSelectable(pending.bone)
		then
			return false
		end

		State.manipulationMotors = {}
		for _, bone in State.Axis:GetSelectedBones() do
			local part = State.Rig:GetPartFromBone(State.currentRig, bone)
			local motor = part and State.Rig:GetMotorForPart(State.currentRig, part)
			if motor then
				table.insert(
					State.manipulationMotors,
					{ part = part, motor = motor, startC0 = motor.C0 }
				)
			end
		end

		Project.appendIKManipulationEntries(State.manipulationMotors)
		local first = State.manipulationMotors[1]
		State.manipulationMotor = first and first.motor
		State.manipulationStartC0 = first and first.startC0
		if pending.mode == "Rotation" then
			State.Axis:StartBlenderRotate(pending.start, false, true)
		else
			State.Axis:StartBlenderGrab(pending.start)
		end

		return State.Axis:IsBlenderRotateMode() or State.Axis:IsBlenderGrabMode()
	end

	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if ViewportSelection.active() then
			if
				input.KeyCode == Enum.KeyCode.Escape
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3
			then
				ViewportSelection.cancel()
				if input.KeyCode == Enum.KeyCode.Escape then
					return
				end
			elseif input.UserInputType == Enum.UserInputType.Keyboard then
				return
			end
		end

		if State.WorkspaceSelection then
			return
		end

		if State.LoadingProject or State.PhysicsSimulating then
			return
		end

		if
			UI.isAnimatorActive()
			and State.Axis
			and (
				State.Axis:IsHoldingAxis()
				or State.Axis:IsBlenderGrabMode()
				or State.Axis:IsBlenderRotateMode()
			)
		then
			if Shortcuts.matches("Cancel", input) then
				pendingActiveTool = nil
				Project.cancelCurrentManipulation()
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or Shortcuts.matches("ConfirmTransform", input)
				or Shortcuts.matches("ConfirmTransformAlternate", input)
			then
				pendingActiveTool = nil
				finalizeCurrentManipulation()
				return
			end
		end

		if State.PivotEditor and State.PivotEditor.input(input, gameProcessed) then
			return
		end

		if require("SceneSync").keyboard(input) then
			return
		end

		if State.CameraTargets and State.CameraTargets.input(input, gameProcessed) then
			return
		end

		if State.GreasePencil and State.GreasePencil.isDrawing() then
			return
		end

		if State.PoseSliders and State.PoseSliders.isEditing() then return end
		if State.FaceHandles and State.FaceHandles.input(input, gameProcessed) then return end
		if State.PropertyGizmo and State.PropertyGizmo.input(input, gameProcessed) then
			return
		end

		if State.EffectHandles and State.EffectHandles.input(input, gameProcessed) then
			return
		end

		if State.CameraControls and State.CameraControls.input(input) then
			return
		end

		if State.CameraPreview and State.CameraPreview.hasFocus() then
			return
		end

		if require("Visibility").bonesHidden() then
			return
		end

		if State.GraphEditor and State.GraphEditor.hasFocus() then
			return
		end

		if State.ImagePreviewer and State.ImagePreviewer.hasFocus() then
			return
		end

		if State.ExportResults and State.ExportResults.hasFocus() then
			return
		end

		if not UI.isAnimatorActive() then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if
				not UserInputService:GetViewportMouseLocation()
				or UserInputService.isUIInput(input)
				or UserInputService.pointerOverUI()
			then
				return
			end

			if State.Timeline:IsPointOverEventUI(UserInputService:GetViewportMouseLocation()) then
				return
			end

			if State.Timeline:IsDraggingPlayhead() then
				return
			end

			if
				State.Axis:IsHoldingAxis()
				or State.Axis:IsBlenderGrabMode()
				or State.Axis:IsBlenderRotateMode()
			then
				finalizeCurrentManipulation()
				return
			end
		end

		local focusedTextBox = UserInputService:GetFocusedTextBox()
		if focusedTextBox then
			return
		end

		if State.Axis:ConstrainTransform(input) then
			return
		end

		if
			Shortcuts.matches("Cancel", input)
			and (
				State.Axis:IsHoldingAxis()
				or State.Axis:IsBlenderGrabMode()
				or State.Axis:IsBlenderRotateMode()
			)
		then
			Project.cancelCurrentManipulation()
			return
		end

		if
			(
				Shortcuts.matches("ConfirmTransform", input)
				or Shortcuts.matches("ConfirmTransformAlternate", input)
			) and (State.Axis:IsBlenderGrabMode() or State.Axis:IsBlenderRotateMode())
		then
			finalizeCurrentManipulation()
			return
		end

		if gameProcessed then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if UserInputService.pointerInWidget() then
			return
		end

		viewportPress = input
		if require("SceneSync").input(UserInputService:GetViewportMouseLocation()) then
			return
		end

		if #State.getAllRigs() == 0 then
			local additive = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			Connections.selectInBlankFile(State.mouse and State.mouse.Target, additive)
			return
		end

		if
			Origin.hit(workspace.CurrentCamera, UserInputService:GetViewportMouseLocation())
			and not State.Axis:GetAxisUnderMouse()
		then
			local item = State.Rig._originItem
			if item then
				State.Rig:SetSingleItemSelection(item)
			end

			if Origin.beginDrag(UserInputService:GetViewportMouseLocation()) then
				return
			end
		end

		local selectedBone = State.Axis:GetSelectedBone()

		if selectedBone then
			local axis = State.Axis:GetAxisUnderMouse()
			if axis then
				State.ignoreSelectionChanged = true
				Selection:Set({})
				State.ignoreSelectionChanged = false

				State.mouseDownTime = tick()
				State.mouseDownAxisPart = axis
				State.mouseDownSelectedBone = selectedBone
				State.mouseDownMousePos = UserInputService:GetViewportMouseLocation()
				State.scoreDragStarted = false

				if State.pendingScoreHoldConnection then
					State.pendingScoreHoldConnection:Disconnect()
					State.pendingScoreHoldConnection = nil
				end

				if axis.Name ~= "SCore" then
					local selectedPart = State.Rig:GetPartFromBone(State.currentRig, selectedBone)
					local motor = selectedPart
							and State.Rig:GetMotorForPart(State.currentRig, selectedPart)
						or nil
					local success = State.Axis:StartDrag(axis, State.mouseDownMousePos)

					if success then
						State.manipulationMotor = motor
						State.manipulationStartC0 = motor and motor.C0 or nil

						State.manipulationMotors = {}
						for _, b in ipairs(State.Axis:GetSelectedBones()) do
							local p = State.Rig:GetPartFromBone(State.currentRig, b)
							local m = p and State.Rig:GetMotorForPart(State.currentRig, p) or nil
							if p and m then
								table.insert(State.manipulationMotors, {
									part = p,
									motor = m,
									startC0 = m.C0,
								})
							end
						end

						Project.appendIKManipulationEntries(State.manipulationMotors)

						return
					end

					return
				else
					State.pendingScoreHoldConnection = RunService.Heartbeat:Connect(function()
						if require("Visibility").bonesHidden() then
							return
						end

						if
							not State.mouseDownAxisPart
							or State.mouseDownAxisPart ~= axis
							or State.scoreDragStarted
						then
							if State.pendingScoreHoldConnection then
								State.pendingScoreHoldConnection:Disconnect()
								State.pendingScoreHoldConnection = nil
							end

							return
						end

						if tick() - State.mouseDownTime >= Config.Behavior.ScoreHoldThreshold then
							Project.beginScoreDrag(axis)
						end
					end)

					return
				end
			end
		end

		if
			selectedBone
			and require("Preferences").get("ActiveToolDrag")
			and not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			and not UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		then
			local hit = State.Axis:GetBoneUnderMouse()
			if hit and hit ~= selectedBone then
				selectViewportClick()
				return
			end

			pendingActiveTool = {
				start = UserInputService:GetViewportMouseLocation(),
				bone = selectedBone,
				mode = State.GizmoMode,
				moved = false,
			}
			pendingActiveTool.started = beginActiveTool(pendingActiveTool)
			if not pendingActiveTool.started then
				pendingActiveTool = nil
				selectViewportClick()
			end

			return
		end

		if
			not State.Axis:GetBoneUnderMouse()
			and ViewportSelection.begin(UserInputService:GetViewportMouseLocation())
		then
			return
		end

		selectViewportClick()
	end)

	connect(UserInputService.InputChanged, function(input)
		if ViewportSelection.active() then
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				ViewportSelection.move(UserInputService:GetViewportMouseLocation())
			end

			return
		end

		if State.LoadingProject or State.Timeline:GetState().Exporting then
			return
		end

		if State.PivotEditor and State.PivotEditor.isActive() then
			return
		end

		if State.PropertyGizmo and State.PropertyGizmo.isEditing() then
			return
		end

		if require("Visibility").bonesHidden() then
			return
		end

		if State.GraphEditor and State.GraphEditor.isInteracting() then
			return
		end

		if not UI.isAnimatorActive() then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if not UserInputService:GetViewportMouseLocation() then
				return
			end

			if Origin.moveDrag(UserInputService:GetViewportMouseLocation()) then
				return
			end

			if
				pendingActiveTool
				and (UserInputService:GetViewportMouseLocation() - pendingActiveTool.start).Magnitude
					>= Config.Behavior.ScoreDragStartDistance
			then
				pendingActiveTool.moved = true
			end

			if
				State.mouseDownAxisPart
				and State.mouseDownAxisPart.Name == "SCore"
				and not State.scoreDragStarted
				and State.mouseDownMousePos
			then
				local currentMousePos = UserInputService:GetViewportMouseLocation()
				local delta = currentMousePos - State.mouseDownMousePos

				if delta.Magnitude >= Config.Behavior.ScoreDragStartDistance then
					Project.beginScoreDrag(State.mouseDownAxisPart)
				end
			end

			ArmatureRuntime.deferInteractive(function()
				if State.Axis:IsHoldingAxis() then
					State.Axis:ProcessDrag(UserInputService:GetViewportMouseLocation())
				elseif State.Axis:IsBlenderGrabMode() then
					State.Axis:ProcessBlenderGrab(UserInputService:GetViewportMouseLocation())
				elseif State.Axis:IsBlenderRotateMode() then
					State.Axis:QueueBlenderRotateInput(UserInputService:GetViewportMouseLocation())
				end
			end)
		end
	end)

	local function releaseViewportPointer(cancelClick)
		if ViewportSelection.active() then
			local click = ViewportSelection.finish(cancelClick)
			if click then
				selectViewportClick()
			end
		end

		local pending = pendingActiveTool
		pendingActiveTool = nil
		if pending then
			if pending.started then
				if pending.moved or cancelClick then
					finalizeCurrentManipulation()
				end
			elseif
				not cancelClick
				and UI.isAnimatorActive()
				and not UserInputService.pointerOverUI()
			then
				selectViewportClick()
			end
		end

		Origin.endDrag(false)
		State.Timeline:SetDraggingPlayhead(false)

		local releasedAxis = State.mouseDownAxisPart
		local heldTime = tick() - State.mouseDownTime
		local didScoreDrag = State.scoreDragStarted

		if State.pendingScoreHoldConnection then
			State.pendingScoreHoldConnection:Disconnect()
			State.pendingScoreHoldConnection = nil
		end

		if releasedAxis and releasedAxis.Name == "SCore" then
			if didScoreDrag then
				finalizeCurrentManipulation()
			end

			State.mouseDownAxisPart = nil
			State.mouseDownSelectedBone = nil
			State.mouseDownMousePos = nil
			State.scoreDragStarted = false
			return
		end

		if releasedAxis and releasedAxis.Name ~= "SCore" then
			finalizeCurrentManipulation()
			State.Axis:UpdateHover()
		end

		State.mouseDownAxisPart = nil
		State.mouseDownSelectedBone = nil
		State.mouseDownMousePos = nil
		State.scoreDragStarted = false
	end

	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and input == viewportPress then
			viewportPress = nil
			releaseViewportPointer()
		end
	end)
	connect(UserInputService.WindowFocusReleased, function()
		viewportPress = nil
		releaseViewportPointer(true)
		if
			State.Axis:IsHoldingAxis()
			or State.Axis:IsBlenderGrabMode()
			or State.Axis:IsBlenderRotateMode()
		then
			finalizeCurrentManipulation()
		end
	end)

	connect(RunService.Heartbeat, ViewportSelection.validate)
	connect(UserInputService.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Keyboard then
			Connections.noteNativeEdit(Selection:Get())
		end
	end)
	connect(UserInputService.WindowFocusReleased, function()
		nativeEditUntil, nativeEditObjects = 0, {}
	end)
	connect(RunService.Heartbeat, Connections.stepRecording)

	local eventConnection

	local function stopEventPlayback()
		if eventConnection then
			eventConnection:Disconnect()
			eventConnection = nil
		end

		EventPlayback.clear()
	end

	connect(UI.EclipseGUI.Destroying, stopEventPlayback)
	connect(UI.ClosingEvent.Event, stopEventPlayback)
	eventConnection = connect(RunService.PreRender, Connections.stepPlayback)

	connect(RunService.RenderStepped, function()
		Connections.updateTransformVisibility()
		if State.LoadingProject or State.Timeline:GetState().Exporting then
			return
		end

		State.Timeline:UpdateKeyframeHover()
		if require("Visibility").bonesHidden() then
			return
		end

		if not UI.isAnimatorActive() then
			return
		end

		if
			not State.Timeline:GetState().Playing
			and State.GraphEditor
			and State.GraphEditor.isNavigating()
		then
			return
		end

		if State.Axis:IsBlenderRotateMode() then
			State.Axis:FlushBlenderRotateInput()
		else
			State.Axis:RefreshRotationModifiers()
		end

		local manipulating = State.Axis:IsHoldingAxis()
			or State.Axis:IsBlenderGrabMode()
			or State.Axis:IsBlenderRotateMode()
		if manipulating then
			require("Target").syncChildren()
			for _, rig in ipairs(State.getAllRigs()) do
				if ArmatureRuntime.isRig(rig) then
					ArmatureRuntime.evaluate(rig)
				else
					BoneIK.syncDeform(rig)
					BoneIK.solveAllForRig(rig)
					LimbIK.apply(rig, State.Timeline:GetState().CurrentTime, false)
				end
			end
		end

		local raw = State.Timeline:GetState()
		local playbackHidden = raw.Playing and not raw.Recording
		for _, rig in ipairs(State.getAllRigs()) do
			State.Rig:UpdateBonesFollowRig(rig, playbackHidden and not CameraRig.isRig(rig))
		end

		if
			not State.WorkspaceSelection
			and not (State.GraphEditor and State.GraphEditor.hasFocus())
		then
			State.Axis:UpdateHover()
		end
	end)

	connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		if State.currentRig and UI.isAnimatorActive() then
			task.defer(function()
				State.Axis:InvalidateAxisCache()
				State.Axis:SetCurrentRig(State.currentRig)
				for _, rig in ipairs(State.getAllRigs()) do
					State.Rig:CreateBonesForRig(rig)
				end

				if State.Axis:GetSelectedBone() then
					State.Axis:RefreshAxis()
				end
			end)
		end
	end)

	connect(UI.EclipseGUI:GetPropertyChangedSignal("Enabled"), function()
		local enabled = UI.EclipseGUI.Enabled
		local timeline = State.Timeline:GetState()
		if timeline.Exporting then
			timeline.Exporting.Cancelled = true
			const deadline = os.clock() + 10
			repeat
				task.wait()
			until not timeline.Exporting or not UI.EclipseGUI.Parent or os.clock() > deadline
			if not UI.EclipseGUI.Parent or UI.EclipseGUI.Enabled ~= enabled then
				return
			end
		end

		if not UI.EclipseGUI.Enabled then
			local function reopened()
				return not UI.EclipseGUI.Parent or UI.EclipseGUI.Enabled
			end

			local function teardown()
				if reopened() then
					return
				end

				const ok, problem = pcall(function()
					clearRotationInput()
					Project.stopAllAnimations()
					Project.suspendPreview()

					UI.PluginActiveBool.Value = false

					State.Axis:SelectBone(nil)
					State.Axis:ClearAxis()

					for _, rig in ipairs(State.getAllRigs()) do
						local bonesFolder = State.Rig:GetBonesFolder(rig)
						if bonesFolder then
							bonesFolder.Parent = nil
						end

						State.Rig:LockRigLimbs(rig, false)
					end

					State.Rig:CleanUpOldLockedRigs()
					pcall(function()
						ArmatureImport.stashAll()
					end)
				end)
				if not ok then
					warn("[Eclipse] Close cleanup: " .. tostring(problem))
				end
			end

			WorkBudget.wait(2, reopened)
			if reopened() then
				return
			end

			teardown()
			if WorkBudget.busy() then
				task.spawn(function()
					WorkBudget.wait(60, reopened)
					teardown()
				end)
			end
		else
			WindowFX.pop(UI.AnimatorFrame.Visible and UI.AnimatorFrame or UI.PrimaryFrame)

			if State.currentRig then
				WorkBudget.run(function()
					for _, rig in ipairs(State.getAllRigs()) do
						ArmatureImport.restore(rig)
						State.Rig:LockRigLimbs(rig, true)
						State.Timeline:ApplyPoseAtTime(
							rig,
							State.Timeline:GetState().CurrentTime,
							{ OnlyRig = true }
						)
						for _, motor in require("Parenting").collectMotors(rig) do
							State.lastCFrames[motor] = motor.C0
						end

						State.Rig:CreateBonesForRig(rig)
					end

					State.Axis:SetCurrentRig(State.currentRig)
					State.Timeline:BuildTimelineUI(Project.getCurrentRig)
					State.Timeline:UpdatePlayhead()
					State.Rig:BuildRigHierarchy(State.currentRig)
					State.Timeline:RebuildAllTimelineKeyframeButtons(
						UI.TrackContainer,
						State.UIHelpers and State.UIHelpers.SanitizeName
							or function(str)
								return tostring(str or ""):gsub("%s+", "")
							end
					)

					if UI.AnimatorFrame.Visible then
						UI.PluginActiveBool.Value = true
					end
				end)
			end
		end
	end)
end

Connections.attach = attach

return Connections
