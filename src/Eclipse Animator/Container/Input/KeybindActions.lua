--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local UserInputService = require("UserInputService")

local State = require("State")
local UI = require("UI")
local Project = require("Project")
local Notification = require("Notification")
local Keybinds = require("Keybinds")
local KeyframeMenu = require("KeyframeMenu")

local GraphEditor = require("GraphEditor")
local KeybindActions = {}

local registered = false

local function register()
	if registered then
		return
	end

	registered = true
	for action, pref in
		{ ToggleCameraWASD = "DisableCameraWASD", ToggleCameraQE = "DisableCameraQE" }
	do
		Keybinds.bind(action, function()
			if not UI.isAnimatorActive() then
				return
			end

			local prefs = require("Preferences")
			local value = not prefs.get(pref)
			if prefs.set(pref, value) then
				Notification.show(
					"CAMERA MOVEMENT",
					(pref == "DisableCameraWASD" and "WASD" or "Q/E")
						.. (value and " movement disabled" or " movement enabled")
				)
			end
		end)
	end

	local function actionJumpKeyframeLeft()
		Project.jumpToNearestSelectedLimbKeyframe("Left")
	end

	local function actionJumpKeyframeRight()
		Project.jumpToNearestSelectedLimbKeyframe("Right")
	end

	local function actionCutKeyframes()
		if not UI.isAnimatorActive() then
			return
		end

		if State.Timeline:CutSelectedKeyframes() then
			State.currentProjectSaved = false
			Notification.show("NOTIFICATION", "Cut keyframes", 1.5, "KeyframeAction")
		end
	end

	local function actionCopyKeyframes()
		if not UI.isAnimatorActive() then
			return
		end

		local copied = State.Timeline:CopySelectedKeyframes()
		if copied then
			Notification.show("NOTIFICATION", "Copied keyframes", 1.5, "KeyframeAction")
		end
	end

	local function actionPasteKeyframes()
		if not UI.isAnimatorActive() then
			return
		end

		local ok = State.Timeline:PasteKeyframes()
		if ok then
			State.currentProjectSaved = false
			Notification.show("NOTIFICATION", "Pasted keyframes", 1.5, "KeyframeAction")
		end
	end

	local function actionResetMotorPosition()
		Project.resetSelectedMotorPositions()
	end

	local function actionResetMotorOrientation()
		Project.resetSelectedMotorOrientations()
	end

	local function actionTogglePlayback()
		require("Visibility").togglePlayback()
	end

	local function actionRecordKeyframe()
		Project.recordKeyframesForAllSelected()
	end

	local function actionToggleBlenderGrab()
		if State.Timeline:IsBlenderKeyframeTransformActive() then
			if State.Timeline:GetBlenderKeyframeTransformMode() == "move" then
				State.Timeline:CancelBlenderKeyframeTransform()
			end

			return
		end

		if
			State.Timeline:IsMouseOverPluginAnimator()
			and (
				#State.Timeline:GetSelectedKeyframesList() > 0
				or State.Timeline:HasAnySelectedChannelKeyframes()
			)
		then
			State.Timeline:StartBlenderKeyframeMove()
			return
		end

		if require("SceneSync").start("Move") then
			return
		end

		if State.PropertyGizmo and State.PropertyGizmo.start("move") then
			return
		end

		if UI.isAnimatorActive() and State.Axis:GetSelectedBone() then
			local selectedBone = State.Axis:GetSelectedBone()
			local selectedPart = selectedBone
					and State.Rig:GetPartFromBone(State.currentRig, selectedBone)
				or nil
			local motor = selectedPart and State.Rig:GetMotorForPart(State.currentRig, selectedPart)
				or nil

			if not State.Axis:IsBlenderGrabMode() then
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
			end

			State.Axis:ToggleBlenderGrab(UserInputService:GetViewportMouseLocation())
		end
	end

	local function actionStartBlenderRotate()
		if State.EffectHandles and State.EffectHandles.start() then
			return
		end

		if require("SceneSync").start("Scale") then
			return
		end

		if State.PropertyGizmo and State.PropertyGizmo.start() then
			return
		end

		if State.CameraControls and State.CameraControls.start() then
			return
		end

		if
			not UI.isAnimatorActive()
			or not State.currentRig
			or not State.Axis
			or not State.Timeline
		then
			return
		end

		if State.Axis:IsBlenderGrabMode() then
			return
		end

		if State.Timeline:IsBlenderKeyframeTransformActive() then
			return
		end

		if UI.isAnimatorActive() and State.Axis:GetSelectedBone() then
			local selectedBone = State.Axis:GetSelectedBone()
			local selectedPart = selectedBone
					and State.Rig:GetPartFromBone(State.currentRig, selectedBone)
				or nil
			local motor = selectedPart and State.Rig:GetMotorForPart(State.currentRig, selectedPart)
				or nil

			if State.Axis:IsBlenderRotateMode() then
				State.Axis:EnterTrackballRotate()
			else
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

				State.Axis:StartBlenderRotate(UserInputService:GetViewportMouseLocation(), false)
			end
		end
	end

	local function actionToggleGizmoMode()
		if State.ScaleGizmo then
			State.ScaleGizmo.disable()
		end

		if not UI.isAnimatorActive() then
			return
		end

		if require("SceneSync").toggleMode() then
			return
		end

		if State.GizmoMode == "Position" then
			Project.updateGizmoMode("Rotation")
		else
			Project.updateGizmoMode("Position")
		end
	end

	local function actionSetGizmoMode(mode)
		if not UI.isAnimatorActive() or require("BlenderEdit").blocked() then
			return
		end

		local axis = State.Axis
		if
			not axis
			or State.PhysicsSimulating
			or (State.Timeline:GetState().Playing and not State.Timeline:GetState().Recording)
			or axis:IsHoldingAxis()
			or axis:IsBlenderGrabMode()
			or axis:IsBlenderRotateMode()
			or State.PropertyGizmo and State.PropertyGizmo.isEditing()
			or State.Timeline:IsBlenderKeyframeTransformActive()
		then
			return
		end

		if State.ScaleGizmo then
			State.ScaleGizmo.disable()
		end

		if State.claimViewport then
			State.claimViewport()
		end
		Project.updateGizmoMode(mode)
	end

	local function actionToggleAxisSpace()
		if not UI.isAnimatorActive() then
			return
		end

		if not State.Axis or not State.Axis.ToggleAxisSpace then
			return
		end

		if
			State.Axis:IsBlenderGrabMode()
			or State.Axis:IsBlenderRotateMode()
			or State.Axis:IsHoldingAxis()
		then
			return
		end

		local newSpace = State.Axis:ToggleAxisSpace()
		Notification.show("AXIS SPACE", "Axis space: " .. newSpace)
	end

	local function actionToggleOnionSkin()
		if not UI.AnimatorFrame.Visible or not State.currentRig then
			return
		end

		if not State.OnionSkin then
			return
		end

		State.OnionSkin:Toggle()
	end

	local function actionApplyOnionSkin()
		if not UI.AnimatorFrame.Visible or not State.currentRig then
			return
		end

		if not State.OnionSkin then
			return
		end

		if not State.OnionSkin:IsActive() then
			return
		end

		State.OnionSkin:ApplyToRig()
	end

	local function actionOpenKeyframeMenu()
		if not UI.isAnimatorActive() or not State.Timeline then
			return
		end

		local list = State.Timeline:GetSelectedKeyframesList()
		local hasChannelKfs = State.Timeline:HasAnySelectedChannelKeyframes()
		if (list and #list > 0) or hasChannelKfs then
			KeyframeMenu.open(UserInputService:GetMouseLocation())
		else
			if KeyframeMenu.openSecondary then
				KeyframeMenu.openSecondary(UserInputService:GetMouseLocation())
			end
		end
	end

	local function actionToggleBlenderScale()
		if State.Timeline:IsBlenderKeyframeTransformActive() then
			if State.Timeline:GetBlenderKeyframeTransformMode() == "scale" then
				State.Timeline:CancelBlenderKeyframeTransform()
			end

			return
		end

		if State.Timeline:IsMouseOverPluginAnimator() then
			if
				#State.Timeline:GetSelectedKeyframesList() > 0
				or State.Timeline:HasAnySelectedChannelKeyframes()
			then
				State.Timeline:StartBlenderKeyframeScale()
			end
		elseif UI.isAnimatorActive() and State.ScaleGizmo then
			State.ScaleGizmo.start()
		end
	end

	Keybinds.bind("FocusSelection", function()
		if not UI.isAnimatorActive() or not State.Rig or not State.Axis then
			return
		end

		if
			State.Axis:IsHoldingAxis()
			or State.Axis:IsBlenderGrabMode()
			or State.Axis:IsBlenderRotateMode()
		then
			return
		end

		local Focus = require("Focus")
		if State.CameraPreview and State.CameraPreview.isFull() then
			return
		end

		Focus.focus(Focus.targets(State), workspace.CurrentCamera, function()
			return UI.isAnimatorActive()
				and not (State.CameraPreview and State.CameraPreview.isFull())
				and not State.Axis:IsHoldingAxis()
				and not State.Axis:IsBlenderGrabMode()
				and not State.Axis:IsBlenderRotateMode()
		end)
	end)

	local splitWindow

	local function canSplit()
		return UI.isAnimatorActive()
			and State.currentRig
			and not State.Timeline:IsExportLocked()
			and not State.Timeline:IsBlenderKeyframeTransformActive()
			and not State.Axis:IsHoldingAxis()
			and not State.Axis:IsBlenderGrabMode()
			and not State.Axis:IsBlenderRotateMode()
	end

	Keybinds.bind("SplitKeyframes", function()
		if canSplit() and not splitWindow then
			State.Timeline:SplitSelectedKeyframes()
		end
	end)
	Keybinds.bind("SplitStride", function()
		if not canSplit() then
			return
		end

		if splitWindow then
			splitWindow:close(true)
		end

		local Tool = require("Tool")
		local window = Tool.new(
			{ ScreenGui = UI.EclipseGUI },
			"EclipseSplitStride",
			"SPLIT STRIDE",
			Vector2.new(260, 126),
			false,

			function()
				splitWindow = nil
			end
		)
		splitWindow = window
		Tool.label(
			window.frame,
			"Label",
			"FRAMES",
			UDim2.fromOffset(12, 41),
			UDim2.fromOffset(76, 24)
		)
		local field = Tool.field(
			window.frame,
			"Stride",
			State.Timeline:GetState().SplitStride or 3,
			UDim2.fromOffset(94, 41),
			UDim2.fromOffset(154, 26)
		)

		local function confirm()
			local value = tonumber(field.Text)
			if not value or value ~= value or value == math.huge or value < 1 or value % 1 ~= 0 then
				Notification.show("SPLIT STRIDE", "Enter a whole number of frames, at least 1.")
				return
			end

			State.Timeline:GetState().SplitStride = value
			window:close()
		end

		Tool.button(
			window.frame,
			"Confirm",
			"CONFIRM",
			UDim2.fromOffset(134, 86),
			UDim2.fromOffset(114, 26),
			confirm
		)
		table.insert(
			window.connections,
			field.FocusLost:Connect(function(enter)
				if enter then
					confirm()
				end
			end)
		)

		local function closeIfInactive()
			if not UI.isAnimatorActive() then
				window:close(true)
			end
		end

		table.insert(
			window.connections,
			UI.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(closeIfInactive)
		)
		table.insert(
			window.connections,
			UI.EclipseGUI:GetPropertyChangedSignal("Enabled"):Connect(closeIfInactive)
		)
		table.insert(
			window.connections,
			UI.EclipseGUI.Destroying:Connect(function()
				window:close(true)
			end)
		)
		table.insert(
			window.connections,
			UserInputService.InputBegan:Connect(function(input)
				if input.KeyCode == Enum.KeyCode.Escape then
					window:close()
				end
			end)
		)
		task.defer(function()
			if not window.closed then
				field:CaptureFocus()
			end
		end)
	end)
	Keybinds.bind("StepSingleFrameLeft", function()
		Project.stepFrame("Left", 1)
	end)
	Keybinds.bind("StepSingleFrameRight", function()
		Project.stepFrame("Right", 1)
	end)
	Keybinds.bind("JumpSingleKeyframeLeft", function()
		Project.jumpToNearestSelectedLimbKeyframe("Left", false, 1)
	end)
	Keybinds.bind("JumpSingleKeyframeRight", function()
		Project.jumpToNearestSelectedLimbKeyframe("Right", false, 1)
	end)
	Keybinds.bind("StepFrameLeft", function()
		Project.stepFrame("Left")
	end)
	Keybinds.bind("StepFrameRight", function()
		Project.stepFrame("Right")
	end)
	Keybinds.bind("JumpToStart", Project.jumpToStart)
	Keybinds.bind("JumpKeyframeLeft", actionJumpKeyframeLeft)
	Keybinds.bind("JumpKeyframeRight", actionJumpKeyframeRight)
	Keybinds.bind("CutKeyframes", actionCutKeyframes)
	Keybinds.bind("CopyKeyframes", actionCopyKeyframes)
	Keybinds.bind("PasteKeyframes", actionPasteKeyframes)
	for action, mode in { StretchFrames = "stretch", FillFrames = "fill" } do
		Keybinds.bind(action, function()
			if UI.isAnimatorActive() then
				require("fill").open(mode)
			end
		end)
	end

	Keybinds.bind("StudioSelection", function()
		if UI.isAnimatorActive() and State.setWorkspaceSelection then
			State.setWorkspaceSelection(true, true)
		end
	end)
	Keybinds.bind("ResetScale", function()
		if UI.isAnimatorActive() then
			require("PropertyEditing").reset()
		end
	end)
	Keybinds.bind("ResetMotorPosition", actionResetMotorPosition)
	Keybinds.bind("ResetMotorOrientation", actionResetMotorOrientation)
	Keybinds.bind("RecordKeyframe", actionRecordKeyframe)
	Keybinds.bind("RecordAllTracks", Project.recordAllTrackKeyframes)
	Keybinds.bind("TogglePlayback", actionTogglePlayback)
	Keybinds.bind("HideSelectedBones", function()
		if UI.isAnimatorActive() then
			require("Organization").hideSelectedBones()
		end
	end)
	Keybinds.bind("UnhideAllBones", function()
		if UI.isAnimatorActive() then
			require("Organization").unhideBones()
		end
	end)
	Keybinds.bind("ToggleBlenderGrab", actionToggleBlenderGrab)
	Keybinds.bind("ToggleBlenderScale", actionToggleBlenderScale)
	Keybinds.bind("StartBlenderRotate", actionStartBlenderRotate)
	Keybinds.bind("ToggleGizmoMode", actionToggleGizmoMode)
	Keybinds.bind("SetPositionGizmo", function()
		actionSetGizmoMode("Position")
	end)
	Keybinds.bind("SetRotationGizmo", function()
		actionSetGizmoMode("Rotation")
	end)
	Keybinds.bind("ToggleScaleGizmo", function()
		if UI.isAnimatorActive() and State.ScaleGizmo then
			State.ScaleGizmo.toggle()
		end
	end)
	Keybinds.bind("ToggleAxisSpace", actionToggleAxisSpace)
	Keybinds.bind("ToggleOnionSkin", actionToggleOnionSkin)
	Keybinds.bind("ApplyOnionSkin", actionApplyOnionSkin)
	Keybinds.bind("OpenKeyframeMenu", actionOpenKeyframeMenu)
	Keybinds.bind("ToggleGraphEditor", GraphEditor.toggle)
	Keybinds.bind("CycleCameraGrid", function()
		if UI.isAnimatorActive() and State.CameraPreview then
			State.CameraPreview.cycleComposition()
		end
	end)
	Keybinds.bind("RotateCameraGrid", function()
		if UI.isAnimatorActive() and State.CameraPreview then
			State.CameraPreview.rotateComposition()
		end
	end)
	Keybinds.bind("ToggleCameraGrid", function()
		if UI.isAnimatorActive() and State.CameraPreview then
			State.CameraPreview.toggleMainGrid()
		end
	end)
end

KeybindActions.register = register

return KeybindActions
