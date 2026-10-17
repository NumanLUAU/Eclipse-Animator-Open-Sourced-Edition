--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Weld = require("transaction")
local CoreGui = game:GetService("CoreGui")
local Selection = game:GetService("Selection")
local TweenService = game:GetService("TweenService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UI = require("UI")
local State = require("State")
local Avatar = require("Avatar")
local Catalog = require("Catalog")
local RigPose = require("RigPose")
const MasterControl = require("MasterControl")
local Layout = require("Layout")
local Appearance = require("Appearance")
local BoneMotor = require("BoneMotor")
local History = require("History")
local Drag = require("Drag")
local WindowFX = require("WindowFX")

local BTN = Color3.fromRGB(51, 0, 77)
local BTN_SEL = Color3.fromRGB(100, 0, 151)

local Theme = require("Theme")
Theme.onChanged(function()
	BTN = Theme.isGradient("TopBtn") and Color3.new(1, 1, 1)
		or Theme.get("TopBtn", Color3.fromRGB(51, 0, 77))
	BTN_SEL = Theme.get("MenuSel", Color3.fromRGB(100, 0, 151))
end)

local HelperMenu = {}

local initialized = false
local selectionConnection

function HelperMenu.destroy()
	if selectionConnection then
		selectionConnection:Disconnect()
		selectionConnection = nil
	end

	initialized = false
end

local miscGui = nil
local frame = nil
local rigStore = nil

local anchorPart = nil
local targetInstances = {}
local pendingSelection = nil
local sweepTarget = nil
local animatable = true
local emptyTweens = {}

local function setEmptyVisible(vp, visible)
	local empty = vp and vp:FindFirstChild("EmptyState")
	if not empty then
		return
	end

	empty.Visible = visible
	local swirl = empty:FindFirstChild("Swirl")
	if not swirl then
		return
	end

	if visible then
		if not emptyTweens[swirl] then
			emptyTweens[swirl] = {
				TweenService:Create(
					swirl,
					TweenInfo.new(7, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
					{ Rotation = 360 }
				),
				TweenService:Create(
					swirl,
					TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ ImageTransparency = 0.88 }
				),
			}
		end

		for _, t in ipairs(emptyTweens[swirl]) do
			t:Play()
		end
	else
		if emptyTweens[swirl] then
			for _, t in ipairs(emptyTweens[swirl]) do
				t:Pause()
			end
		end
	end
end

local function fitCamera(vp, inst, zoom)
	local cf, size
	if inst:IsA("Model") then
		cf, size = inst:GetBoundingBox()
	else
		cf, size = inst.CFrame, inst.Size
	end

	local viewportSize = vp.AbsoluteSize
	local aspect = viewportSize.Y > 0 and viewportSize.X / viewportSize.Y or 1
	local vertical = math.tan(math.rad(35) * 0.5)
	local dist = math.max(size.Y / (2 * vertical), size.X / (2 * vertical * math.max(0.1, aspect)))
			* 1.15
		+ size.Z * 0.6
	local camPos = cf.Position + Vector3.new(0.45, 0.28, -1).Unit * dist
	local cam = vp:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = vp
	end

	cam.FieldOfView = 35
	cam.CFrame = CFrame.lookAt(camPos, cf.Position)
	vp.CurrentCamera = cam
end

local function setPreview(vp, inst)
	local wm = vp and vp:FindFirstChildOfClass("WorldModel")
	if not wm then
		return
	end

	wm:ClearAllChildren()

	if inst then
		local ok, clone = pcall(function()
			return inst:Clone()
		end)
		if ok and clone then
			clone.Parent = wm
			pcall(function()
				fitCamera(vp, clone)
			end)
			setEmptyVisible(vp, false)
			return
		end
	end

	setEmptyVisible(vp, true)
end

local function sanitizeCharacter(model)
	if not model then
		return
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
end

local function countJoints(container)
	local n = 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			n += 1
		end
	end

	return n
end

local function setToggleVisual(row, on)
	local fill = row and row:FindFirstChild("Toggle") and row.Toggle:FindFirstChild("Fill")
	if fill then
		fill.Visible = on
	end
end

local function setButtonSelected(btn, selected)
	if not btn then
		return
	end

	btn.BackgroundColor3 = selected and BTN_SEL or BTN
	btn:SetAttribute("ThemeBg", selected and "MenuSel" or "TopBtn")
	Theme.applyInstance(btn)
	local s = btn:FindFirstChildOfClass("UIStroke")
	if s then
		s.Transparency = selected and 0.3 or 0.75
	end
end

local function placeModel(model, waypointName)
	local cam = workspace.CurrentCamera
	local pos = Vector3.new(0, 8, 0)
	local camPos = Vector3.new(0, 8, -20)
	if cam then
		camPos = cam.CFrame.Position
		pos = camPos + cam.CFrame.LookVector * 14
	end

	const rigRoot = MasterControl.root(model)
	if rigRoot and (not model.PrimaryPart or rigRoot.Name == "HumanoidRootPart") then
		model.PrimaryPart = rigRoot
	end

	RigPose.assemble(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Locked = false
		end
	end

	model.Parent = workspace

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { model }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit =
		workspace:Raycast(Vector3.new(pos.X, pos.Y + 20, pos.Z), Vector3.new(0, -120, 0), params)

	local look = Vector3.new(camPos.X, pos.Y, camPos.Z) - pos
	local yaw = 0
	if look.Magnitude > 0.001 then
		yaw = math.atan2(-look.X, -look.Z)
	end

	local snappedYaw = math.rad(math.round(math.deg(yaw) / 90) * 90)
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, snappedYaw, 0))

	if hit then
		local bboxCF, size = model:GetBoundingBox()
		local deltaY = (hit.Position.Y + size.Y / 2) - bboxCF.Position.Y
		model:PivotTo(model:GetPivot() + Vector3.new(0, deltaY, 0))
	end

	sanitizeCharacter(model)

	if
		rigRoot
		and rigRoot:IsDescendantOf(model)
		and (rigRoot.Name == "HumanoidRootPart" or #rigRoot:GetJoints() > 0)
	then
		rigRoot.Anchored = true
	end

	Selection:Set({ model })
	ChangeHistoryService:SetWaypoint(waypointName)
end

function HelperMenu.captureSelection(selected)
	pendingSelection = table.clone(selected or Selection:Get())
end

function HelperMenu.init()
	if initialized then
		return
	end

	initialized = true
	State.HelperMenu = HelperMenu
	HelperMenu.captureSelection()

	miscGui = UI.MiscGUI
	local storage = UI.EclipseGUI and UI.EclipseGUI:FindFirstChild("Storage")
	frame = WindowFX.solidify(storage and storage:FindFirstChild("HelperFrame"))
	rigStore = storage and storage:FindFirstChild("HelperRigs")
	if not miscGui or not frame then
		return
	end

	Layout.apply(frame)
	frame.Parent = miscGui
	frame.Visible = true
	Theme.addRoot(miscGui)

	if miscGui.Enabled then
		WindowFX.pop(frame)
	end

	require("PoseReset").attach(frame, Selection, State, miscGui)
	frame.ResetPose.Activated:Connect(function()
		local rig, multiple =
			RigPose.resolve(Selection:Get(), State.Rig and State.Rig._selectedItems)
		if not rig or multiple then
			frame.ResetStatus.Text = "Select one rig to reset."
			return
		end

		if State.Timeline then
			State.Timeline:GetState().Playing = false
		end

		local playing = State.currentAnimations[rig]
		if playing then
			playing:Stop()
		end

		local recording
		local editing = UI.isAnimatorActive()
		if not editing then
			pcall(function()
				recording =
					ChangeHistoryService:TryBeginRecording("EclipseResetPose", "Reset rig pose")
			end)
			if not recording then
				ChangeHistoryService:SetWaypoint("Before Eclipse Reset Pose")
			end
		end

		local before = RigPose.capture(rig)
		local defaults = State.Timeline and State.Timeline:GetState().DefaultPose
		local ok, err = pcall(RigPose.reset, rig, defaults, BoneMotor)
		if not ok then
			RigPose.restore(rig, before)
			if recording then
				ChangeHistoryService:FinishRecording(
					recording,
					Enum.FinishRecordingOperation.Cancel
				)
			end

			frame.ResetStatus.Text = "Could not reset this rig."
			warn(err)
			return
		end

		local after = RigPose.capture(rig)
		if editing then
			History.record(function()
				if rig.Parent then
					RigPose.restore(rig, before)
				end
			end, function()
				if rig.Parent then
					RigPose.restore(rig, after)
				end
			end, "Reset rig pose")
		elseif recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint("Eclipse Reset Pose")
		end

		frame.ResetStatus.Text = rig.Name .. " reset."
	end)
	frame.Destroying:Once(HelperMenu.destroy)
	UI.EclipseGUI.Destroying:Once(HelperMenu.destroy)
	local bar = frame.Bar
	local weldTab = frame.WeldTab
	local rigsTab = frame.RigsTab
	local anchorCard = weldTab.AnchorCard
	local targetCard = weldTab.TargetCard
	local binder = weldTab.BinderPanel
	local sweeper = weldTab.SweeperPanel
	local blankPanel = rigsTab.BlankRigsPanel

	Drag.makeDraggable({ bar, bar.Title }, frame, nil, {
		dragThreshold = 5,
		suppressClickAfterDrag = true,
	})

	bar.CloseButton.MouseButton1Click:Connect(function()
		WindowFX.shrink(frame, function()
			miscGui.Enabled = false
		end)
	end)

	local function selectTab(name)
		Layout.selectTab(frame, name)
		if frame:FindFirstChild("AccessoriesTab") then
			frame.AccessoriesTab.Visible = name == "ACCESSORIES"
		end

		frame.ResetPose.Visible = name ~= "ACCESSORIES"
		frame.ResetStatus.Visible = name ~= "ACCESSORIES"
		setButtonSelected(bar.TabButtons.ACCESSORIESTab, name == "ACCESSORIES")
		weldTab.Visible = (name == "WELD")
		rigsTab.Visible = (name == "RIGS")
		setButtonSelected(bar.TabButtons.WELDTab, name == "WELD")
		setButtonSelected(bar.TabButtons.RIGSTab, name == "RIGS")
	end

	bar.TabButtons.WELDTab.MouseButton1Click:Connect(function()
		selectTab("WELD")
	end)
	bar.TabButtons.RIGSTab.MouseButton1Click:Connect(function()
		selectTab("RIGS")
	end)
	bar.TabButtons.ACCESSORIESTab.Activated:Connect(function()
		selectTab("ACCESSORIES")
	end)
	selectTab("WELD")

	local function refreshWeldSelection()
		if
			not frame.Parent
			or not anchorCard:FindFirstChild("TargetName")
			or not targetCard:FindFirstChild("TargetName")
		then
			return
		end

		local sel = pendingSelection or Selection:Get()
		pendingSelection = nil
		anchorPart, targetInstances = Weld.selection(sel)
		anchorCard.TargetName.Text = anchorPart and anchorPart.Name or "Select a part first"
		setPreview(anchorCard.Preview, anchorPart)
		if #targetInstances == 1 then
			local target = targetInstances[1]
			targetCard.TargetName.Text = target.Name .. (target:IsA("Model") and " (Model)" or "")
			setPreview(targetCard.Preview, target)
		elseif #targetInstances > 1 then
			targetCard.TargetName.Text = tostring(#targetInstances) .. " targets"
			local group = Instance.new("Model")
			for _, target in targetInstances do
				local ok, clone = pcall(function()
					return target:Clone()
				end)
				if ok and clone then
					clone.Parent = group
				end
			end

			setPreview(targetCard.Preview, group)
			group:Destroy()
		else
			targetCard.TargetName.Text = "Ctrl+select targets"
			setPreview(targetCard.Preview, nil)
		end

		local ready = pcall(Weld.plan, anchorPart, targetInstances)
		Layout.enabled(binder.BindButton, ready)
		Layout.enabled(binder.BindInPlaceButton, ready)
		binder.Hint.Text = ""

		local newSweep = nil
		for _, inst in ipairs(sel) do
			if
				inst:IsA("Model")
				or inst:IsA("Tool")
				or inst:IsA("Folder")
				or inst:IsA("Accessory")
			then
				newSweep = inst
				break
			end
		end

		sweepTarget = newSweep

		if sweepTarget then
			sweeper.TargetName.Text = sweepTarget.Name
			sweeper.JointCount.Text = countJoints(sweepTarget) .. " joints found"
		else
			sweeper.TargetName.Text = "Select a model or folder"
			sweeper.JointCount.Text = "No selection"
		end

		Layout.enabled(sweeper.SweepButton, sweepTarget ~= nil and countJoints(sweepTarget) > 0)
	end

	selectionConnection = Selection.SelectionChanged:Connect(function()
		if miscGui.Enabled then
			pendingSelection = nil
			refreshWeldSelection()
		end
	end)

	miscGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if miscGui.Enabled then
			WindowFX.pop(frame)
			refreshWeldSelection()
		end
	end)

	local animatableRow = binder.AnimatableRow
	animatableRow.Toggle.MouseButton1Click:Connect(function()
		animatable = not animatable
		setToggleVisual(animatableRow, animatable)
	end)
	setToggleVisual(animatableRow, animatable)

	local function feedback(text)
		binder.Hint.Text = text
	end

	local function bind(inPlace)
		local valid, reason = pcall(Weld.plan, anchorPart, targetInstances)
		if not valid then
			feedback(tostring(reason):gsub("^.-:%d+: ", ""))
			return
		end

		if UI.isAnimatorActive() then
			local ok, count =
				pcall(require("PartRigging").bindTargets, anchorPart, targetInstances, inPlace, animatable)
			if not ok then
				feedback(tostring(count):gsub("^.-:%d+: ", ""))
				return
			end

			feedback(
				string.format(
					animatable and "Bound %d target%s for the whole rig. P/W remains available."
						or "Bound %d target%s with fixed joints.",
					count,
					count == 1 and "" or "s"
				)
			)
			return
		end

		local recording
		pcall(function()
			recording = ChangeHistoryService:TryBeginRecording("EclipseBindTargets", "Bind targets")
		end)
		if not recording then
			ChangeHistoryService:SetWaypoint("Before Eclipse Bind")
		end

		local ok, count =
			pcall(Weld.apply, anchorPart, targetInstances, inPlace, animatable, workspace)
		if recording then
			ChangeHistoryService:FinishRecording(
				recording,
				ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
			)
		elseif ok then
			ChangeHistoryService:SetWaypoint("Eclipse Bind")
		end

		if not ok then
			feedback(tostring(count):gsub("^.-:%d+: ", ""))
			return
		end

		feedback(
			string.format(
				"Bound %d target%s to %s",
				count,
				count == 1 and "" or "s",
				anchorPart.Name
			)
		)
	end

	binder.BindButton.MouseButton1Click:Connect(function()
		bind(false)
	end)
	binder.BindInPlaceButton.MouseButton1Click:Connect(function()
		bind(true)
	end)

	sweeper.SweepButton.MouseButton1Click:Connect(function()
		if not sweepTarget or not sweepTarget.Parent then
			sweeper.JointCount.Text = "select something first!"
			return
		end

		local swept = 0
		for _, d in ipairs(sweepTarget:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
				swept += 1
			end
		end

		ChangeHistoryService:SetWaypoint("Eclipse Sweep")
		sweeper.JointCount.Text = "Removed " .. swept .. " joints"
		Layout.enabled(sweeper.SweepButton, false)
	end)

	Catalog.init({
		Gui = miscGui,
		Frame = frame,
		Owner = UI.EclipseGUI,
		State = State,
		FitCamera = fitCamera,
		PlaceModel = placeModel,
		SetButtonSelected = setButtonSelected,
	})
	Avatar.init({
		Gui = miscGui,
		Tab = rigsTab,
		Owner = UI.EclipseGUI,
		State = State,
		SetButtonSelected = setButtonSelected,
		SetEmptyVisible = setEmptyVisible,
		FitCamera = fitCamera,
		PlaceModel = placeModel,
		OnTheme = Theme.onChanged,
	})

	if rigStore then
		for _, presetButton in ipairs(blankPanel.PresetGrid:GetChildren()) do
			if presetButton:IsA("TextButton") then
				local rigName = presetButton:GetAttribute("RigName")
				local source = rigName and rigStore:FindFirstChild(rigName)
				if source then
					presetButton.MouseButton1Click:Connect(function()
						local clone = source:Clone()
						placeModel(clone, "Eclipse Spawn Rig")
					end)
				end
			end
		end
	end

	blankPanel.PresetGrid.CameraPreset.Activated:Connect(function()
		local Camera = require("CameraRig")
		local source
		if UI.isAnimatorActive() then
			local candidates = {}
			for _, rig in State.getAllRigs() do
				if Camera.isRig(rig) then
					table.insert(candidates, rig)
				end
			end

			if Camera.isRig(State.currentRig) then
				source = State.currentRig
			elseif #candidates == 1 then
				source = candidates[1]
			elseif #candidates > 1 then
				frame.ResetStatus.Text = "Select the camera to copy in the timeline."
				return
			end
		end

		local ok, model = pcall(require("Export").createCameraRig, source)
		if not ok then
			frame.ResetStatus.Text = tostring(model):gsub("^.-:%d+: ", "")
			return
		end

		model.Parent = workspace
		require("CameraRig").organize(model, require("Project").getProjectExportName())
		Selection:Set({ model })
		ChangeHistoryService:SetWaypoint("Eclipse Insert Camera Rig")
		frame.ResetStatus.Text = source and "Camera + FOV copied to AnimSaves."
			or "Camera rig added. Export camera keys to animate it."
	end)

	setEmptyVisible(anchorCard.Preview, true)
	setEmptyVisible(targetCard.Preview, true)
	refreshWeldSelection()
end

return HelperMenu
