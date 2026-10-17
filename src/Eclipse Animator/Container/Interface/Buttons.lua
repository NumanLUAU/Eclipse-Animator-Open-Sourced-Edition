--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Selection = game:GetService("Selection")

local Organization = require("Organization")
local State = require("State")
local Config = require("Config")
local UI = require("UI")
local Project = require("Project")
local Export = require("Export")
local ArmatureImport = require("ArmatureImport")
local Notification = require("Notification")
local Alert = require("Alert")
local WindowFX = require("WindowFX")
local Data = require("ProjectData")
local History = require("History")
local LegacyEvents = require("LegacyEvents")

local Buttons = {}

local attached = false
local Membership = require("Membership")
local pendingArmature = setmetatable({}, { __mode = "k" })

local function attach()
	if attached then
		return
	end

	attached = true
	local function hideWindow(frame)
		const shrunk = pcall(WindowFX.shrink, frame, function()
			UI.EclipseGUI.Enabled = false
		end)
		if not shrunk then
			UI.EclipseGUI.Enabled = false
		end
	end

	UI.RequestEvent.OnInvoke = function(action)
		if action == "IsInProject" then
			return UI.PluginActiveBool.Value and UI.AnimatorFrame.Visible
		end

		if action == "RequestCloseProject" then
			if UI.PluginActiveBool.Value and UI.AnimatorFrame.Visible then
				Alert.showReturnWarning()
			else
				hideWindow(UI.PrimaryFrame.Visible and UI.PrimaryFrame or UI.AnimatorFrame)
			end

			return true
		end

		return false
	end

	UI.ExitButton.MouseButton1Click:Connect(function()
		const finalized, issue = pcall(function()
			if not State.LoadingProject and not State.Timeline:IsExportLocked() then
				Project.finalizeCurrentManipulation()
			end
		end)
		if not finalized then
			warn("[Eclipse] " .. tostring(issue))
		end

		hideWindow(UI.AnimatorFrame.Visible and UI.AnimatorFrame or UI.PrimaryFrame)
	end)

	local nameBox = UI.ProjectNameTextBox
	nameBox.ClearTextOnFocus = false
	nameBox.Focused:Connect(function()
		if nameBox.Text:match("%S") then
			nameBox.PlaceholderText = nameBox.Text
		end

		nameBox.Text = ""
	end)
	nameBox.FocusLost:Connect(function()
		local oldName = nameBox.PlaceholderText
		local nextName = nameBox.Text:match("%S") and Data.sanitizeExportName(nameBox.Text)
			or oldName
		Project.setProjectName(nextName)
		if nextName ~= oldName then
			State.currentProjectSaved = false
			Export.requestRename(nextName)
		end
	end)

	ArmatureImport.resolveTarget = function()
		local rigs = State.getAllRigs()
		if not UI.PluginActiveBool.Value then
			return nil
		end

		local chosen = {}

		local function collect(part)
			if typeof(part) ~= "Instance" then
				return
			end

			local reference = part.Parent and part.Parent:FindFirstChild("EclipseSourceRig")
			part = reference and reference.Value or part
			for _, rig in rigs do
				if part == rig or part:IsDescendantOf(rig) then
					chosen[rig] = true
					return true
				end
			end
		end

		local selection = Selection:Get()
		for _, part in selection do
			if not collect(part) then
				return nil
			end
		end

		if next(chosen) == nil and State.Rig then
			for item, selected in State.Rig._selectedItems do
				if selected then
					collect((item.grandpa or item).linkedRigInstance)
				end
			end
		end

		local target
		for rig in chosen do
			if target then
				return nil
			end

			target = rig
		end

		return target or (#rigs == 1 and rigs[1] or nil)
	end

	ArmatureImport.onBeforeImport = function(rig)
		if State.currentRig and UI.PluginActiveBool.Value and State.Timeline then
			local tl = State.Timeline:GetState()
			tl.Playing = false
			tl.CurrentTime = 0
			State.Timeline:ApplyPoseAtTime(State.currentRig, 0)
			State.Timeline:UpdatePlayhead()
			pendingArmature[rig] = Membership.capture(tl, rig)
		end
	end

	ArmatureImport.onImported = function(arm, rigRoot)
		if not State.currentRig then
			return
		end

		if not UI.PluginActiveBool.Value then
			return
		end

		local active = false
		for _, rig in State.getAllRigs() do
			if rigRoot == rig or rigRoot:IsDescendantOf(rig) or rig:IsDescendantOf(rigRoot) then
				active = true
				break
			end
		end

		if active then
			local tl = State.Timeline:GetState()
			tl.Playing = false
			tl.CurrentTime = 0
			local previous = pendingArmature[rigRoot]
			if previous then
				local live = {}
				for _, motor in require("Parenting").collectMotors(rigRoot) do
					live[motor] = true
					live[motor.Part1] = true
				end

				local retained = {}
				for field, values in previous do
					if field ~= "owned" then
						retained[field] = {}
						for key, value in values do
							if live[field == "MotorByPart" and value or key] then
								retained[field][key] = value
							end
						end
					end
				end

				for motor in previous.Keyframes do
					if not live[motor] then
						State.Timeline:_restoreMotorBucket(motor, {})
					end
				end

				Membership.remove(tl, rigRoot, previous)
				Membership.restoreNativeDefaults(tl, rigRoot, previous)
				Membership.restore(tl, retained)
				for motor in State.lastCFrames do
					if not live[motor] and Membership.belongs(motor, rigRoot, previous.owned) then
						State.lastCFrames[motor] = nil
					end
				end

				pendingArmature[rigRoot] = nil
			end

			State.currentProjectSaved = false
			State.Timeline:CaptureDefaultPoseAdditive(rigRoot)
			State.Rig:BuildRigHierarchy(State.currentRig)
			State.Rig:CreateBonesForRig(State.currentRig)
			if rigRoot ~= State.currentRig then
				State.Rig:CreateBonesForRig(rigRoot)
			end

			State.Timeline:UpdatePlayhead()
		end
	end

	UI.ProjectCreator_BTN.MouseButton1Click:Connect(function()
		local selectedRigs = Project.getSelectedAnimatableRigs()
		if #selectedRigs > 1 then
			Project.openEmptyProject(nil)
			for _, rig in selectedRigs do
				Project.addRigToTimeline(
					rig,
					{ Loading = true, AllowDuplicateName = true, NewRig = true }
				)
			end

			State.currentProjectSaved = false
			History.clear()
			return
		end

		local selected = Project.getSelectedAnimatableRig()
		if not selected then
			return
		end

		Project.stopAllAnimations()
		Project.setProjectName(Data.getNextDefaultExportName(selected:FindFirstChild("AnimSaves")))
		State.currentRig = selected
		State.currentProjectSave = nil
		State.currentProjectSequence = nil
		pcall(function()
			ArmatureImport.restore(selected)
		end)
		UI.PluginActiveBool.Value = true
		State.currentProjectSaved = false
		table.clear(State.lastCFrames)
		table.clear(State.extraRigs)
		table.clear(State.activeObjectMotors)
		Project.syncObjectMotorStates()

		History.clear()
		State.Timeline:ClearTimelineData()
		Organization.reset()
		State.Timeline:LoadProjectSettings()
		State.Timeline:CaptureDefaultPose(State.currentRig, true)
		State.Timeline:InitializeRotationModeForRig(State.currentRig)
		State.Timeline:SetLooping(true)
		State.Timeline:SetRecording(true)

		State.Rig:LockRigLimbs(State.currentRig, true)
		State.Axis:SetCurrentRig(State.currentRig)

		UI.PrimaryFrame.Visible = false
		UI.AnimatorFrame.Visible = true

		State.ignoreSelectionChanged = true
		Selection:Set({})
		State.ignoreSelectionChanged = false

		State.Timeline:BuildTimelineUI(Project.getCurrentRig)
		State.Timeline:GetState().CurrentTime = 0
		State.Timeline:GetState().Playing = false
		State.Timeline:UpdatePlayhead()

		State.Rig:BuildRigHierarchy(State.currentRig)
		State.Rig:CreateBonesForRig(State.currentRig)

		Project.clearAnimButtons()
		if State.currentRig:FindFirstChild("AnimSaves") then
			Project.populateAnimButtons(State.currentRig)
		end

		History.armGuard()
	end)

	UI.BlankProjectCreator_BTN.MouseButton1Click:Connect(function()
		local selected = Project.getSelectedAnimatableRigs()
		Project.openEmptyProject(nil)
		Project.addSelectionToTimeline(
			selected,
			{ Loading = true, AllowDuplicateName = true, NewRig = true }
		)
		History.clear()
	end)

	UI.ReturnButton.MouseButton1Click:Connect(function()
		if State.LoadingProject or State.Timeline:IsExportLocked() then
			return
		end

		if State.currentProjectSaved then
			Project.clearCurrentRig()
		else
			Alert.showReturnWarning()
		end
	end)

	UI.AgreeButton.MouseButton1Click:Connect(function()
		if State.LoadingProject or State.Timeline:IsExportLocked() then
			return
		end

		Alert.hideReturnWarning(function()
			Project.clearCurrentRig()
			State.currentProjectSaved = false
			UI.PrimaryFrame.Visible = true
			WindowFX.pop(UI.PrimaryFrame)
		end)
	end)

	UI.DisagreeButton.MouseButton1Click:Connect(function()
		Alert.hideReturnWarning(function()
			UI.AnimatorFrame.Visible = true
			WindowFX.pop(UI.AnimatorFrame)
		end)
	end)

	UI.ExportButton.MouseButton1Click:Connect(function()
		Export.exportCurrentAnimation()
	end)

	if UI.SaveButton then
		UI.SaveButton.MouseButton1Click:Connect(function()
			Export.saveProject()
		end)
		UI.SaveButton.MouseButton2Click:Connect(function()
			require("FileTools").openSaveAs()
		end)
	end

	if UI.AddRigButton then
		UI.AddRigButton.MouseButton1Click:Connect(function()
			if not UI.isAnimatorActive() then
				return
			end

			local selected = Selection:Get()[1]
			if not selected then
				Notification.show(
					"NOTHING SELECTED",
					"Select a rig or an object to add it to the timeline."
				)
				return
			end

			if #Selection:Get() == 1 and LegacyEvents.isTrack(selected) then
				local item = State.Rig._lastClickedItem
				local owner = item and (item.grandpa or item)
				local target = owner and owner.linkedRigInstance or State.Rig._lastEventRig
				local matched = false
				for _, rig in State.getAllRigs() do
					if target == rig then
						matched = true
						break
					end
				end

				State.Timeline:ImportLegacyEvents(selected, matched and target or State.currentRig)
				return
			end

			Project.addSelectionToTimeline()
		end)
	end

	UI.ClosingEvent.Event:Connect(function()
		if State.UIHelpers then
			State.UIHelpers:Destroy()
		end

		if
			State.currentRig
			and not State.currentProjectSaved
			and State.Timeline
			and State.Timeline:HasAnyKeyframes()
		then
			Export.exportCurrentAnimation({ showResults = false })
		end
	end)

	local descriptions = Config.UI.Descriptions or {}
	local hoverDialog = State.UIHelpers and State.UIHelpers.hoverDialog
	if hoverDialog then
		for _, frame in { UI.PrimaryFrame, UI.AnimatorFrame } do
			local bar = frame:FindFirstChild("Bar")
			local appearance = bar and bar:FindFirstChild("Appearence")
			local icon = appearance and appearance:FindFirstChild("Icon")
			if icon then
				hoverDialog:latchToInstance(
					icon,
					"Community Server — find the link on our Creator Store page. Cracked by numan"
				)
			end
		end

		if UI.AddRigButton then
			hoverDialog:latchToInstance(UI.AddRigButton, function()
				local selected = Selection:Get()[1]
				if selected and selected:FindFirstChildOfClass("Humanoid") then
					return descriptions.AddRig or "Add Rig"
				end

				return descriptions.AddObject or "Add Object"
			end)
		end

		hoverDialog:latchToInstance(UI.LoopButton, function()
			if State.Timeline and State.Timeline:IsLooping() then
				return descriptions.LoopOn or "Disable Loop"
			end

			return descriptions.LoopOff or "Enable Loop"
		end)

		if UI.RecordButton then
			hoverDialog:latchToInstance(UI.RecordButton, function()
				if State.Timeline and State.Timeline:IsRecording() then
					return descriptions.RecordOn or "Disable Live Recording"
				end

				return descriptions.RecordOff or "Enable Live Recording"
			end)
		end

		if UI.SaveButton then
			hoverDialog:latchToInstance(UI.SaveButton, function()
				return "Save " .. Export.documentKind()
			end)
		end

		hoverDialog:latchToInstance(UI.ExportButton, descriptions.Export or "Export Animation")
		hoverDialog:latchToInstance(UI.ReturnButton, descriptions.Close or "Close Animation")
	end
end

Buttons.attach = attach

return Buttons
