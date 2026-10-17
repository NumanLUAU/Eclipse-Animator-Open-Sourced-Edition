--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local State = require("State")
local Target = require("Target")
local CameraRig = require("CameraRig")
local History = require("History")
local Tool = require("Tool")
local Theme = require("Theme")
local Edit = require("BlenderEdit")
local Preferences = require("Preferences")
local ParentingUI = require("ParentingUI")
local RigTraversal = require("RigTraversal")
local Targets = {}
local enableButtons = setmetatable({}, { __mode = "k" })
local rowButtons = setmetatable({}, { __mode = "k" })
local manualRig
local refs, window
local panel, panelRig, picking, dismissed
local parenter, pickingChild, parenterStamp, parenterRows, parenterOwner
local pickingOwner = false
local chosenParent
local hierarchyLinks = setmetatable({}, { __mode = "k" })
local hierarchyIndex
local Properties = require("Properties")
local Master = require("MasterControl")
local ignorePickedUntil = 0

local function refresh(rig)
	State.Timeline:ApplyPoseAtTime(rig, State.Timeline:GetState().CurrentTime)
	State.currentProjectSaved = false
	require("CameraDisplay").refresh()
	require("motionPath").markDirty()
end

function Targets.editWeight(keys, value)
	if
		not State.Timeline
		or Edit.blocked()
		or typeof(value) ~= "number"
		or value ~= value
		or math.abs(value) == math.huge
		or #keys == 0
	then
		return false
	end

	local timeline = State.Timeline
	local raw = timeline:GetState()
	for _, key in keys do
		if
			not CameraRig.isTransform(key.Motor)
			or not raw.Keyframes[key.Motor]
			or raw.Keyframes[key.Motor][key.Frame] ~= key
		then
			return false
		end
	end

	local before, after = {}, {}
	for _, key in keys do
		if not before[key.Motor] then
			before[key.Motor] = timeline:_snapshotMotorBucket(key.Motor)
		end
	end

	for _, key in keys do
		key.CamTrackTo = math.clamp(value, 0, 1)
	end

	for motor in before do
		after[motor] = timeline:_snapshotMotorBucket(motor)
	end

	local function apply(buckets)
		for motor, bucket in buckets do
			if motor.Parent then
				timeline:_restoreMotorBucket(motor, bucket)
				refresh(CameraRig.owner(motor))
			end
		end
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Camera Track to")
	return true
end

function Targets.editEnabled(keys, value)
	if not State.Timeline or Edit.blocked() or #keys == 0 then
		return false
	end

	local timeline = State.Timeline
	local raw = timeline:GetState()
	local before, after, optionsBefore, optionsAfter = {}, {}, {}, {}
	for _, key in keys do
		if
			not Target.is(key.Motor)
			or not raw.Keyframes[key.Motor]
			or raw.Keyframes[key.Motor][key.Frame] ~= key
		then
			return false
		end
	end

	for _, key in keys do
		if not before[key.Motor] then
			before[key.Motor] = timeline:_snapshotMotorBucket(key.Motor)
		end

		key.CamTargetEnabled = value == true
	end

	for motor in before do
		after[motor] = timeline:_snapshotMotorBucket(motor)
		local rig = CameraRig.owner(motor)
		local master, default =
			rig:GetAttribute("EclipseTrackTarget"),
			rig:GetAttribute("EclipseCamTargetDefaultEnabled")
		optionsBefore[rig] = { master = master, default = default }
		optionsAfter[rig] = { master = value and true or master, default = default }
		if value and default == nil then
			optionsAfter[rig].default = master == true
		end
	end

	local function apply(buckets, options)
		for rig, option in options do
			rig:SetAttribute("EclipseTrackTarget", option.master)
			rig:SetAttribute("EclipseCamTargetDefaultEnabled", option.default)
		end

		for motor, bucket in buckets do
			if motor.Parent then
				timeline:_restoreMotorBucket(motor, bucket)
				refresh(CameraRig.owner(motor))
			end
		end
	end

	apply(after, optionsAfter)
	History.record(function()
		apply(before, optionsBefore)
	end, function()
		apply(after, optionsAfter)
	end, "CamTarget enabled")
	return true
end

function Targets.setEnabled(rig, value)
	local timeline = State.Timeline
	local raw = timeline:GetState()
	if Edit.blocked() or raw.Playing then
		return false
	end

	if refs then
		refs.Finalize()
	end

	local motor = Target.ensure(rig)
	if not motor then
		return false
	end

	local before = timeline:_snapshotMotorBucket(motor)
	local old = rig:GetAttribute("EclipseTrackTarget")
	local oldDefault = rig:GetAttribute("EclipseCamTargetDefaultEnabled")
	local nextDefault = oldDefault
	if nextDefault == nil then
		nextDefault = old == true
	end

	local frame = timeline:TimeToFrame(raw.CurrentTime)
	timeline:RecordKeyframeForMotorAtCurrentTime(
		motor.Part1,
		motor,
		motor.C0,
		{ Frame = frame },
		State.UIHelpers.SanitizeName
	)
	raw.Keyframes[motor][frame].CamTargetEnabled = value == true
	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(bucket, master, default)
		if motor.Parent then
			rig:SetAttribute("EclipseTrackTarget", master)
			rig:SetAttribute("EclipseCamTargetDefaultEnabled", default)
			timeline:_restoreMotorBucket(motor, bucket)
			refresh(rig)
		end
	end

	apply(after, true, nextDefault)
	History.record(function()
		apply(before, old, oldDefault)
	end, function()
		apply(after, true, nextDefault)
	end, "CamTarget enabled")
	Targets.updateRows()
	return true
end

function Targets.setOption(rig, attribute, value)
	assert(attribute == "EclipseTrackTarget" or attribute == "EclipseHideCamTarget")
	assert(not Edit.blocked(), "Finish the current edit first")
	local before = rig:GetAttribute(attribute)

	local function apply(nextValue)
		if not rig.Parent then
			return
		end

		rig:SetAttribute(attribute, nextValue)
		if attribute == "EclipseHideCamTarget" and nextValue and State.Axis then
			local bone = State.Axis:GetSelectedBone()
			local source = bone and bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
			if
				source
				and source.Value == rig
				and bone:GetAttribute("SourcePartName") == "CamTarget"
			then
				State.Axis:ClearSelection()
			end
		end

		if refs then
			refs.RefreshStructure()
		end

		refresh(rig)
	end

	apply(value)
	History.record(function()
		apply(before)
	end, function()
		apply(value)
	end, "Camera target setting")
end

function Targets.canParent(rig, object)
	return object == nil
		or typeof(object) == "Instance"
			and object.Parent ~= nil
			and (object:IsA("BasePart") or object:IsA("Bone"))
			and not object:IsDescendantOf(rig)
			and not CameraRig.owner(object)
			and not object:GetAttribute("EclipseCameraProxy")
			and not object:GetAttribute("EclipseNavigationOrigin")
			and object:IsDescendantOf(workspace)
end

function Targets.setParent(rig, object)
	assert(not Edit.blocked(), "Finish the current edit first")
	assert(not State.Timeline:GetState().Playing, "Pause playback before changing the parent")
	assert(Targets.canParent(rig, object), "Choose a scene part or bone outside this camera")
	local timeline = State.Timeline
	local raw = timeline:GetState()
	local motor = Target.ensure(rig)
	assert(motor, "Camera target is unavailable")
	if refs then
		refs.Finalize()
	end

	timeline:ApplyPoseAtTime(rig, raw.CurrentTime)
	local pose = motor.C0
	local before = timeline:_snapshotMotorBucket(motor)
	local frame = timeline:TimeToFrame(raw.CurrentTime)
	timeline:RecordKeyframeForMotorAtCurrentTime(
		motor.Part1,
		motor,
		pose,
		{ Frame = frame },
		State.UIHelpers.SanitizeName
	)
	local key = assert(raw.Keyframes[motor][frame])
	key.CamTargetParent = Target.reference(object)
	Target.capture(motor, key)
	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(bucket)
		if not motor.Parent then
			return
		end

		timeline:_restoreMotorBucket(motor, bucket)
		refresh(rig)
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "CamTarget parent")
	return key
end

function Targets.close()
	if window then
		local old = window
		window = nil
		old:close()
	end
end

local function chooser(name, title, heading, chosen, canUse, noneLabel, commit, includeCameras)
	Targets.close()
	window = Tool.new(refs, name, title, Vector2.new(328, 280), false, function()
		window = nil
	end)
	local frame = window.frame
	Tool.label(frame, "Time", heading, UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 20))
	local shell = Tool.make("Frame", frame, "Targets", {
		Position = UDim2.fromOffset(12, 57),
		Size = UDim2.new(1, -24, 1, -105),
		BorderSizePixel = 0,
	})
	shell:SetAttribute("ThemeBg", "TopBtn")
	local outline = Tool.make(
		"UIStroke",
		shell,
		"Outline",
		{ Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	outline:SetAttribute("ThemeStrk", "Strk")
	local list = Tool.make("ScrollingFrame", shell, "List", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	Tool.make(
		"UIListLayout",
		list,
		"Rows",
		{ Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	local rows = {}
	local seen = {}

	local function update()
		for _, row in rows do
			row.button.BackgroundTransparency = row.object == chosen and 0 or 1
			row.button.BackgroundColor3 = Theme.get("TopBtnHover", Color3.fromRGB(73, 46, 90))
		end
	end

	local function add(object, label)
		if object and (seen[object] or not canUse(object)) then
			return
		end

		if object then
			seen[object] = true
		end

		local button = Tool.make("TextButton", list, "Target", {
			Text = "",
			Size = UDim2.new(1, -6, 0, 25),
			BorderSizePixel = 0,
			AutoButtonColor = false,
		})
		local text =
			Tool.label(button, "Label", label, UDim2.fromOffset(7, 0), UDim2.new(1, -14, 1, 0))
		text.TextWrapped = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		button.Activated:Connect(function()
			chosen = object
			update()
		end)
		button.MouseEnter:Connect(function()
			if chosen ~= object then
				button.BackgroundTransparency = 0.55
			end
		end)
		button.LayoutOrder = #rows
		button:SetAttribute("ThemeBg", nil)
		table.insert(rows, { button = button, object = object })
		button.MouseLeave:Connect(update)
	end

	add(nil, noneLabel)
	for _, object in game:GetService("Selection"):Get() do
		if object:IsA("Model") then
			object = (Master.get(object) and Master.get(object).Part1) or object.PrimaryPart
		end

		if object then
			add(object, object.Name .. " \u{b7} selected")
		end
	end

	for _, other in State.getAllRigs() do
		if includeCameras or not CameraRig.isRig(other) then
			local master = Master.get(other)
			if master then
				add(master.Part1, other.Name .. " / Master Control")
			end

			if other:IsA("BasePart") or other:IsA("Bone") then
				add(other, other.Name)
			end

			for _, object in RigTraversal.rigDescendants(other) do
				if object:IsA("BasePart") or object:IsA("Bone") then
					local names, ancestor = {}, object
					while ancestor and ancestor ~= other do
						table.insert(names, 1, ancestor.Name)
						ancestor = ancestor.Parent
					end

					table.insert(names, 1, other.Name)
					add(object, table.concat(names, " / "))
				end
			end
		end
	end

	if chosen then
		add(chosen, chosen.Name)
	end

	Tool.button(
		frame,
		"Cancel",
		"CANCEL",
		UDim2.new(1, -192, 1, -36),
		UDim2.fromOffset(84, 24),
		Targets.close
	)
	local apply, label = Tool.button(
		frame,
		"Apply",
		"APPLY",
		UDim2.new(1, -100, 1, -36),
		UDim2.fromOffset(88, 24),

		function()
			local ok, err = pcall(commit, chosen)
			if ok then
				Targets.close()
			else
				require("Notification").show(title, (tostring(err):gsub("^.-:%d+: ", "")))
			end
		end
	)
	apply:SetAttribute("ThemeBg", "MenuSel")
	apply:SetAttribute("Primary", true)
	label.TextTransparency = 0
	Theme.applyTree(frame)
	update()
end

function Targets.canAttach(rig, object)
	return typeof(object) == "Instance"
		and object:IsDescendantOf(workspace)
		and (object:IsA("BasePart") or object:IsA("Bone"))
		and not object:IsDescendantOf(rig)
		and not object:GetAttribute("EclipseCameraProxy")
		and not object:GetAttribute("EclipseNavigationOrigin")
		and not (object.Parent and object.Parent:FindFirstChild("RootPart") and object.Parent.RootPart:FindFirstChild(
			"AttachToPart"
		) and object.Parent.RootPart.AttachToPart:IsA("Motor6D") and object.Parent.RootPart.AttachToPart.Part1 == object)
		and not Targets.dynamicCycle(CameraRig.motor(rig, "CamPart"), object)
end

function Targets.setCameraAttachment(rig, object, frame)
	assert(not Edit.blocked(), "Finish the current edit first")
	local timeline = State.Timeline
	local raw = timeline:GetState()
	assert(not raw.Playing, "Pause playback before changing AttachToPart")
	assert(
		object == nil or Targets.canAttach(rig, object),
		"Choose a part or bone outside this camera"
	)
	if State.CameraControls and State.CameraControls.isEditing() then
		State.CameraControls.finish(false)
	end

	if State.CameraPreview and State.CameraPreview.isViewRotating() then
		State.CameraPreview.finishViewRotation(false)
	end

	if refs then
		refs.Finalize()
	end

	local motor = assert(Target.ensureAttachment(rig), "Choose an Eclipse camera")
	raw.DefaultPose[motor] = raw.DefaultPose[motor] or CFrame.identity
	raw.MotorByPart[motor.Part1] = motor
	raw.ParentingDefaults[motor] = true
	frame = frame or timeline:TimeToFrame(raw.CurrentTime)
	local before = timeline:_snapshotMotorBucket(motor)
	timeline:RecordKeyframeForMotorAtCurrentTime(
		motor.Part1,
		motor,
		CFrame.identity,
		{ Frame = frame },
		State.UIHelpers.SanitizeName
	)
	local key = raw.Keyframes[motor][frame]
	key.CamAttachTarget = object and Target.reference(object) or false
	key.EasingStyle = "Constant"
	key.Channels = nil
	key.GraphCurves = nil
	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(bucket)
		if motor.Parent then
			timeline:_restoreMotorBucket(motor, bucket)
			refresh(rig)
		end
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Attach camera to part")

	if not Target.attachmentObject(rig, raw.CurrentTime) and State.Rig then
		local item
		for _, candidate in State.Rig._orderedItems or {} do
			if candidate.linkedRigInstance == rig.CamPart then
				item = candidate
				break
			end
		end

		if item then
			item.linkedBone = nil
			if State.Axis then
				State.Axis:ClearSelection()
			end

			State.Rig:SetSingleItemSelection(item)
		end
	end

	return true
end

function Targets.openCameraAttachment(rig, selectedFrame)
	if not refs or not CameraRig.isRig(rig) or not refs.Active() then
		return
	end

	local raw = State.Timeline:GetState()
	local frame = selectedFrame or State.Timeline:TimeToFrame(raw.CurrentTime)
	chooser(
		"EclipseCameraAttachment",
		"ATTACH TO PART",
		"Camera source at frame " .. frame,
		Target.attachmentObject(rig, State.Timeline:FrameToTime(frame)),

		function(object)
			return Targets.canAttach(rig, object)
		end,
		"Eclipse Camera \u{b7} use camera CFrame",

		function(object)
			Targets.setCameraAttachment(rig, object, frame)
		end,
		true
	)
end

function Targets.openParent(rig)
	if not refs or not CameraRig.isRig(rig) or not refs.Active() then
		return
	end

	local raw = State.Timeline:GetState()
	local key = Target.previous(raw.Keyframes[Target.ensure(rig)], raw.CurrentTime)
	chooser(
		"EclipseCamTargetParent",
		"CAMTARGET PARENT",
		"Parent at frame " .. State.Timeline:TimeToFrame(raw.CurrentTime),
		key and Target.resolve(key.CamTargetParent),

		function(object)
			return Targets.canParent(rig, object)
		end,
		"World \u{b7} unparent",

		function(object)
			Targets.setParent(rig, object)
		end
	)
end

local function follows(object, motor)
	if object == motor.Part1 or object:IsDescendantOf(motor.Part1) then
		return true
	end

	local byPart = State.Timeline:GetState().MotorByPart
	local part, steps = object, 0
	while part and steps < 512 do
		if part == motor.Part1 then
			return true
		end

		local joint = byPart[part]
		if not joint then
			break
		end

		part = typeof(joint) == "table" and joint.RealPart0 or joint.Part0
		steps += 1
	end

	return false
end

function Targets.dynamicCycle(motor, object, time)
	return Target.dependsOn(object, motor, time or State.Timeline:GetState().CurrentTime)
end

function Targets.canChild(motor, object, time)
	return typeof(object) == "Instance"
		and object.Parent ~= nil
		and (object:IsA("BasePart") or object:IsA("Bone"))
		and object:IsDescendantOf(workspace)
		and not object:GetAttribute("EclipseCameraProxy")
		and not object:GetAttribute("EclipseNavigationOrigin")
		and not CameraRig.owner(object)
		and not (Properties.is(motor) and (object == motor.Rig or object:IsDescendantOf(motor.Rig)))
		and not follows(object, motor)
		and not Targets.dynamicCycle(motor, object, time)
end

function Targets.setChild(motor, rig, object, atFrame, worldMode)
	assert(not Edit.blocked(), "Finish the current edit first")
	local timeline = State.Timeline
	local raw = timeline:GetState()
	assert(not raw.Playing, "Pause playback before changing Child Of")
	assert(motor and motor.Parent and not Target.is(motor), "Pick a joint first")
	assert(
		object == nil or Targets.canChild(motor, object, atFrame and timeline:FrameToTime(atFrame)),
		"Choose a part or bone that doesn't follow this joint"
	)
	if refs then
		refs.Finalize()
	end

	local Parenting = require("Parenting")
	local frame = atFrame or timeline:TimeToFrame(raw.CurrentTime)
	local resume = raw.CurrentTime
	raw.CurrentTime = timeline:FrameToTime(frame)

	local changingTime = math.abs(raw.CurrentTime - resume) > 1e-9
	if changingTime then
		timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { SkipControls = true })
	end

	local before = timeline:_snapshotMotorBucket(motor, nil, frame)
	local world = Parenting.worldOf(motor, raw.MotorByPart)
	timeline:RecordKeyframeForMotorAtCurrentTime(
		motor.Part1,
		motor,
		motor.C0,
		{ Frame = frame, SkipChildCapture = true },
		State.UIHelpers.SanitizeName
	)
	local key = assert(raw.Keyframes[motor][frame])
	key.CamTargetParent = object and Target.reference(object) or false
	if object and worldMode then
		key.CamTargetParent.world = true
	end

	key.PathTangentIn, key.PathTangentOut = nil, nil
	if object then
		if Properties.is(motor) then
			Target.captureProperty(motor, key)
		else
			Target.capture(motor, key, motor.C0)
		end
	else
		key.CamTargetAnchor = nil
		if not Properties.is(motor) then
			local parented = not worldMode
				and Parenting.keyIsParented(motor, nil, raw.ParentingDefaults[motor])
			key.Parented = parented
			key.WorldCFrame = not parented and world or nil
		end
	end

	key.MasterWorld = key.WorldCFrame and require("MasterControl").worldDelta(motor) or nil
	require("GraphCurves").invalidate(raw.Keyframes[motor])
	local after = timeline:_snapshotMotorBucket(motor, nil, frame)
	raw.CurrentTime = resume

	local function apply(bucket, alreadyApplied)
		if not motor.Parent then
			return
		end

		if not alreadyApplied then
			local saved = bucket[frame]
			local key = saved and table.clone(saved)
			if key then
				for name, value in key do
					if
						name ~= "Motor"
						and name ~= "Part"
						and name ~= "Template"
						and name ~= "SanitizeName"
					then
						key[name] = require("GraphCurves").clone(value)
					end
				end
			end

			timeline:_applyLiveKeyPatch(motor, { [frame] = key or false })
		end

		raw._motorUniform[motor] = nil
		raw.LastPlaybackFrame = nil
		if alreadyApplied and not changingTime and not require("Layers").has(raw) then
			if not Properties.is(motor) then
				motor:SetAttribute("TrackParent", key.Parented == true)
			end

			State.currentProjectSaved = false
			timeline:RefreshParentingControls(resume)
			require("CameraDisplay").refresh()
			require("motionPath").markDirty()
		else
			refresh(rig)
		end

		if not Properties.is(motor) then
			Target.watchChild(motor, resume)
		end

		timeline:CreateOrUpdateTimelineKeyframeButton(
			motor.Part1,
			motor,
			frame,
			nil,
			State.UIHelpers.SanitizeName
		)
		timeline:RefreshAllChannelDiamondsForMotor(motor)
	end

	apply(after, true)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, object and "Child Of " .. object.Name or "Clear Child Of", frame)
	return key
end

function Targets.openChild(motor, rig)
	if not refs or not refs.Active() or not motor or Target.is(motor) then
		return
	end

	local raw = State.Timeline:GetState()
	local link = Target.childAt(motor, raw.CurrentTime)
	chooser(
		"EclipseChildOf",
		"CHILD OF",
		motor.Part1.Name .. " follows from frame " .. State.Timeline:TimeToFrame(raw.CurrentTime),
		link and Target.resolve(link) or nil,

		function(object)
			return Targets.canChild(motor, object)
		end,
		"None \u{b7} normal parent",

		function(object)
			Targets.setChild(motor, rig, object)
		end
	)
end

function Targets.selectedRig()
	local bone = State.Axis and State.Axis:GetSelectedBone()
	local object = bone
	if bone and bone:GetAttribute("SourcePartName") == "CamTarget" then
		local source = bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
		if source then
			return source.Value
		end
	end

	for item in State.Rig and State.Rig._selectedItems or {} do
		if item.itemKind == "camtarget" then
			object = item.linkedRigInstance
			break
		end
	end

	local rig = object and CameraRig.owner(object)
	return rig and object == rig:FindFirstChild("CamTarget") and rig or nil
end

local function panelAllowed()
	return refs and refs.Active() and refs.ScreenGui.Enabled and not State.PresentationHidden
end

local function over(frame, point)
	if
		not frame
		or not frame.Parent
		or not frame.Visible
		or require("Motion").isFloatingHidden(frame)
	then
		return false
	end

	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X < p.X + s.X and point.Y < p.Y + s.Y
end

function Targets.isPointOverUI(point)
	return over(window and window.frame, point)
		or over(panel and panel.frame, point)
		or over(parenter and not parenter.docked and parenter.frame, point)
end

function Targets.cancelPick()
	pickingOwner = false
	picking = nil
end

local function commitPick(object)
	if pickingOwner then
		local ok, accepted = pcall(Targets.pickChild, object)
		if not ok then
			require("Notification").show("CHILD OF", tostring(accepted):gsub("^.-:%d+: ", ""))
			return false
		end

		if not accepted then
			return false
		end

		pickingOwner = false
		ignorePickedUntil = os.clock() + 0.2
		Targets.updateParenter()
		return true
	end

	if pickingChild then
		local target = pickingChild
		if not object or not Targets.canChild(target.motor, object) then
			return false
		end

		local ok, err = pcall(Targets.setChild, target.motor, target.rig, object)
		if not ok then
			require("Notification").show("DYNAMIC PARENTER", (tostring(err):gsub("^.-:%d+: ", "")))
			return false
		end

		pickingChild = nil
		ignorePickedUntil = os.clock() + 0.2
		return true
	end

	local rig = picking
	if not rig or not Targets.canParent(rig, object) then
		return false
	end

	local ok, err = pcall(Targets.setParent, rig, object)
	if not ok then
		require("Notification").show("CAMTARGET", (tostring(err):gsub("^.-:%d+: ", "")))
		return false
	end

	picking = nil
	ignorePickedUntil = os.clock() + 0.2
	return true
end

function Targets.beginPick(rig)
	if not panelAllowed() or State.Timeline:GetState().Playing then
		return false
	end

	picking = rig or Targets.selectedRig()
	return picking ~= nil
end

function Targets.pickTimelineChild(item)
	if not pickingOwner or not panelAllowed() or State.Timeline:GetState().Playing then
		return false
	end

	local motor = Targets.trackMotor(item)
	local object = motor and (Properties.is(motor) and motor.Rig or motor.Part1)
		or item.linkedRigInstance
	return object ~= nil and commitPick(object)
end

function Targets.selectionChanged(selected)
	if not panelAllowed() then
		return false
	end

	if os.clock() < ignorePickedUntil then
		return true
	end

	if not (picking or pickingChild or pickingOwner) or #selected ~= 1 then
		return false
	end

	local object = selected[1]
	return commitPick(object)
end

function Targets.input(input, processed)
	if not panelAllowed() then
		return false
	end

	local Input = require("UserInputService")
	local point = (pickingOwner and not (Input.pointerInWidget and Input.pointerInWidget()))
			and game:GetService("UserInputService"):GetMouseLocation()
		or Input:GetMouseLocation()
	if input.UserInputType == Enum.UserInputType.MouseButton1 and Targets.isPointOverUI(point) then
		return true
	end

	if not (picking or pickingChild or pickingOwner) then
		return false
	end

	if
		input.KeyCode == Enum.KeyCode.Escape
		or input.UserInputType == Enum.UserInputType.MouseButton2
	then
		picking = nil
		pickingChild = nil
		pickingOwner = false
		return true
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return false
	end

	if
		(Input.pointerInWidget and Input.pointerInWidget())
		or (Input.isUIInput and Input.isUIInput(input))
		or (Input.pointerOverUI and Input.pointerOverUI())
	then
		return false
	end

	if pickingOwner then
		local camera = workspace.CurrentCamera
		if not camera then
			return true
		end

		local mouse = game:GetService("UserInputService"):GetMouseLocation()
		local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local excluded = { camera }
		params.FilterDescendantsInstances = excluded
		for _ = 1, 8 do
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
			if not hit then
				break
			end

			if Targets.objectTarget(hit.Instance) then
				commitPick(hit.Instance)
				break
			end

			table.insert(excluded, hit.Instance)
			params.FilterDescendantsInstances = excluded
		end

		return true
	end

	local object
	local bone = State.Axis and State.Axis:GetBoneUnderMouse()
	if bone and State.Rig then
		object = State.Rig:GetPartFromBone(State.currentRig, bone)
	end

	if not object then
		local camera = workspace.CurrentCamera
		if camera then
			local ray = camera:ViewportPointToRay(point.X, point.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = pickingChild
					and { camera, pickingChild.motor.Part1 }
				or { camera, picking }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
			object = hit and hit.Instance
		end
	end

	if object then
		commitPick(object)
	end

	return true
end

function Targets.updateRows()
	local timeline = State.Timeline
	if not timeline then
		return
	end

	local raw = timeline:GetState()
	for button, motor in enableButtons do
		if not button.Parent or not motor.Parent then
			enableButtons[button] = nil
			continue
		end

		local enabled = Target.enabledAt(CameraRig.owner(motor), raw.CurrentTime)
		button.Text = enabled and "E" or "D"
		button.TextColor3 = enabled and Color3.fromRGB(97, 255, 197)
			or Color3.fromRGB(255, 198, 103)
		button.Active = not raw.Playing
		button.AutoButtonColor = not raw.Playing
	end

	for button, motor in rowButtons do
		if not button.Parent or not motor.Parent then
			rowButtons[button] = nil
			continue
		end

		button.Visible = Preferences.get("CamTargetParentButton") == true
		local key = Target.previous(raw.Keyframes[motor], raw.CurrentTime)
		ParentingUI.paint(
			button,
			key ~= nil and key.CamTargetParent ~= nil and key.CamTargetParent ~= false
		)
	end
end

function Targets.openPanel(rig)
	if not panelAllowed() or not CameraRig.isRig(rig) then
		return false
	end

	manualRig = rig
	dismissed = nil
	Targets.updatePanel()
	return panelRig == rig
end

function Targets.bindRow(item)
	if item.camTargetParentButton then
		return
	end

	local motor = CameraRig.motor(CameraRig.owner(item.linkedRigInstance), "CamTarget")
	if not motor then
		return
	end

	local toggle = ParentingUI.modeButton(item.appearDetails.RightDiv, "CamTargetEnabled")
	toggle.AnchorPoint = Vector2.new(0.5, 0.5)
	toggle.LayoutOrder = -2
	enableButtons[toggle] = motor
	item.camTargetEnabledButton = toggle
	local tooltip = item.rigModule.refs.UIHelpers.hoverDialog
	if tooltip then
		tooltip:latchToInstance(toggle, "Enable / disable camera tracking at this frame")
	end

	table.insert(
		item.connections,
		toggle.MouseButton1Click:Connect(function()
			local rig = CameraRig.owner(motor)
			Targets.setEnabled(
				rig,
				not Target.enabledAt(rig, State.Timeline:GetState().CurrentTime)
			)
		end)
	)
	local button = ParentingUI.modeButton(item.appearDetails.RightDiv, "CamTargetParent")
	button.LayoutOrder = -1
	item.camTargetParentButton = button
	ParentingUI.paint(button, false)
	rowButtons[button] = motor
	button.Visible = Preferences.get("CamTargetParentButton") == true
	local hover = item.rigModule.refs.UIHelpers.hoverDialog
	if hover then
		hover:latchToInstance(button, "Dynamic Parenter")
	end

	table.insert(
		item.connections,
		button.MouseButton1Click:Connect(function()
			item.rigModule:SetSingleItemSelection(item)
			Targets.openPanel(CameraRig.owner(item.linkedRigInstance))
		end)
	)
	Targets.updateRows()
end

function Targets.closePanel()
	picking = nil
	panelRig = nil
	if panel then
		local old = panel
		panel = nil
		old:close()
	end
end

function Targets.setFirstPersonHead(rig, value)
	assert(not Edit.blocked(), "Finish the current edit first")
	local timeline = State.Timeline
	local raw = timeline:GetState()
	assert(not raw.Playing, "Pause playback first")
	local source = rig:FindFirstChild("EclipseFPVSource")
	local model = source and source.Value
	if not model then
		local motor = CameraRig.motor(rig, "CamPart")
		local link = motor and Target.childAt(motor, math.huge)
		local object = link and Target.resolve(link)
		for _, other in State.getAllRigs() do
			if object and object:IsDescendantOf(other) then
				model = other
				break
			end
		end
	end

	assert(model and model.Parent, "The viewmodel for this camera is gone")
	local eye = assert(Target.eye(model, value), "Couldn't find that part on the viewmodel")
	local motor = assert(CameraRig.motor(rig, "CamPart"), "Camera is broken")
	if refs then
		refs.Finalize()
	end

	local before = timeline:_snapshotMotorBucket(motor)
	local was = rig:GetAttribute("EclipseFPVHead")
	local link = Target.reference(eye)
	for _, key in raw.Keyframes[motor] or {} do
		if key.CamTargetParent then
			key.CamTargetParent = link
		end
	end

	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(bucket, flag)
		if not motor.Parent then
			return
		end

		rig:SetAttribute("EclipseFPVHead", flag)
		timeline:_restoreMotorBucket(motor, bucket)
		raw._motorUniform[motor] = nil
		raw.LastPlaybackFrame = nil
		refresh(rig)
	end

	apply(after, value == true)
	History.record(function()
		apply(before, was)
	end, function()
		apply(after, value == true)
	end, "First person lock")
end

local function ownerRig(object)
	local owner
	for _, rig in State.getAllRigs() do
		if object == rig then return rig end
		if object:IsDescendantOf(rig) and (not owner or rig:IsDescendantOf(owner)) then owner = rig end
	end
	return owner
end

local function propertyTransform(rig)
	for _, motor in Properties.list(rig, true) do
		if motor.PropertyId == "CFrame" then
			return motor
		end
	end
end

function Targets.objectTarget(object)
	if typeof(object) == "Instance" and (object:IsA("Model") or object:IsA("Tool") or object:IsA("Accessory")) then
		local master = object:IsA("Model") and Master.get(object)
		object = master and master.Part1 or object:IsA("Model") and object.PrimaryPart
			or object:FindFirstChild("Handle") or object:FindFirstChildWhichIsA("BasePart", true)
	end

	if not object or not object.Parent then
		return nil
	end

	if object:IsA("Motor6D") then
		object = object.Part1
	end

	if
		not object
		or object:GetAttribute("EclipseR6Control")
		or object:GetAttribute("EclipseLimbControl")
		or object:GetAttribute("SourcePartName")
	then
		return nil
	end

	local rig = ownerRig(object)
	local raw = State.Timeline:GetState()
	local motor = raw.MotorByPart[object]
	if
		rig
		and motor
		and not Target.is(motor)
		and not Properties.is(motor)
		and not (typeof(motor) == "table" and (motor.IsEclipseR6Control or motor.IsEclipseIKHandle))
	then
		return {
			kind = "motor",
			motor = motor,
			rig = rig,
			label = rig.Name
				.. " / "
				.. (
					typeof(motor) == "table"
						and motor.IsEclipseMasterControl
						and "Master Control"
					or object.Name
				),
		}
	end

	if
		object:IsA("BasePart")
		and (not rig or rig == object or not motor)
		and object:IsDescendantOf(workspace)
	then
		local transform = rig == object and propertyTransform(rig)
		return transform
				and { kind = "object", motor = transform, rig = object, label = object.Name }
			or { kind = "pending", object = object, rig = object, label = object.Name }
	end

	return nil
end

function Targets.selectedParent()
	local current = Targets.parenterTarget()
	local child = current
		and (Properties.is(current.motor) and current.rig or current.motor and current.motor.Part1)

	local function valid(object)
		if typeof(object) ~= "Instance" then
			return nil
		end

		if object:IsA("Model") then
			object = (Master.get(object) and Master.get(object).Part1) or object.PrimaryPart
		end

		if object and object ~= child and Targets.objectTarget(object) then
			return object
		end
	end

	local row = State.Rig and State.Rig._lastClickedItem
	if row and State.Rig._selectedItems[row] then
		local motor = Targets.trackMotor(row)
		local object = valid(
			motor and (Properties.is(motor) and motor.Rig or motor.Part1) or row.linkedRigInstance
		)
		if object then
			return object
		end
	end

	local bone = State.Axis and State.Axis:GetSelectedBone()
	if
		bone
		and not bone:GetAttribute("EclipseLimbControl")
		and not bone:GetAttribute("EclipseR6Control")
	then
		local object = valid(State.Rig and State.Rig:GetPartFromBone(State.currentRig, bone))
		if object then
			return object
		end
	end

	local selected = game:GetService("Selection"):Get()
	if #selected == 1 then
		return valid(selected[1])
	end
end

function Targets.parenterTarget()
	if parenterOwner and parenterOwner.rig and parenterOwner.rig.Parent then
		return parenterOwner
	end

	parenterOwner = nil
	return nil
end

local function ensureChild(target)
	if target.kind ~= "pending" then
		return target
	end

	local object = target.object
	local Project = require("Project")
	Project.addObjectToTimeline(object)
	object = require("rig").localOf(object)
	assert(ownerRig(object) == object, "Could not add the picked child to the timeline")
	local motor = propertyTransform(object)
	if not motor then
		Properties.enable(object, "CFrame", true, State.Timeline:GetState())
		State.Timeline:CaptureDefaultPoseAdditive(object)
		Project.refreshTimelineAfterStructureChange()
		motor = propertyTransform(object)
	end

	assert(motor, "The picked child has no transform track")
	return { kind = "object", motor = motor, rig = object, label = object.Name }
end

function Targets.pickChild(object)
	local target = Targets.objectTarget(object)
	if not target then
		return false
	end

	parenterOwner = ensureChild(target)
	parenterStamp = nil
	return true
end

local function parentLabel(link, target)
	if typeof(link) == "table" then
		return link.label or "Part"
	end

	if target.kind == "camera" or target.kind == "object" then
		return "World"
	end

	return "Rig parent"
end

local function switchesFor(target)
	local raw = State.Timeline:GetState()
	local motor = target.kind == "camera" and Target.ensure(target.rig) or target.motor
	local list = {}
	for _, key in raw.Keyframes[motor] or {} do
		if not key.Disabled and not key.GraphOnly then
			table.insert(list, key)
		end
	end

	table.sort(list, function(a, b)
		return a.Time < b.Time
	end)
	local rows = {}
	local last
	for _, key in list do
		local link = key.CamTargetParent
		local id = typeof(link) == "table" and (link.id .. (link.world and ":world" or ":parent"))
			or (link == false and "none")
			or nil
		if id ~= nil and id ~= last then
			table.insert(rows, {
				frame = key.Frame or State.Timeline:TimeToFrame(key.Time),
				label = parentLabel(link, target),
				world = typeof(link) == "table" and link.world
					or target.kind == "motor" and key.Parented == false and not link,
			})
			last = id
		end
	end

	return rows
end

function Targets.setInverse(target, clear)
	if not target then
		return false
	end

	local timeline = State.Timeline
	local raw = timeline:GetState()
	assert(
		not Edit.blocked() and not raw.Playing,
		"Pause playback and finish the current edit first"
	)
	local motor = target.kind == "camera" and Target.ensure(target.rig) or target.motor
	local previous = motor and Target.previous(raw.Keyframes[motor], raw.CurrentTime)
	local object = previous and Target.resolve(previous.CamTargetParent)
	if not object then
		return false
	end

	if not clear then
		if target.kind == "camera" then
			Targets.setParent(target.rig, object)
		else
			Targets.setChild(motor, target.rig, object)
		end

		return true
	end

	if refs then
		refs.Finalize()
	end

	local frame = timeline:TimeToFrame(raw.CurrentTime)
	timeline:ApplyPoseAtTime(target.rig, raw.CurrentTime)
	local before = timeline:_snapshotMotorBucket(motor)
	if not raw.Keyframes[motor][frame] then
		timeline:RecordKeyframeForMotorAtCurrentTime(
			motor.Part1,
			motor,
			motor.C0,
			{ Frame = frame },
			State.UIHelpers.SanitizeName
		)
	end

	raw.Keyframes[motor][frame].CamTargetAnchor = CFrame.identity
	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(bucket)
		timeline:_restoreMotorBucket(motor, bucket)
		require("Policy").invalidate(raw.Keyframes[motor])
		require("GraphCurves").invalidate(raw.Keyframes[motor])
		raw._motorUniform[motor] = nil
		raw.LastPlaybackFrame = nil
		refresh(target.rig)
		timeline:RefreshAllKeyframeVisuals()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Clear Child Of inverse", frame)
	return true
end

function Targets.parenterAction(kind)
	if not State.Timeline or State.Timeline:GetState().Playing then
		return
	end

	local ok, err = pcall(function()
		if kind == "pick" then
			pickingOwner = not pickingOwner
			pickingChild = nil
			picking = nil
			if pickingOwner then
				local selected = game:GetService("Selection"):Get()
				if #selected == 1 and selected[1] ~= chosenParent then commitPick(selected[1]) end
			end
			return
		elseif kind == "selected" then
			chosenParent = assert(
				Targets.selectedParent(),
				"Select the parent master control, bone or part first"
			)
			return
		elseif kind == "browse" then
			chooser(
				"EclipseChooseDynamicParent",
				"PARENT",
				"Parent",
				chosenParent,

				function(object)
					local child = Targets.parenterTarget()
					return Targets.objectTarget(object) ~= nil
						and (not child or Targets.canChild(child.motor, object))
				end,
				"None",

				function(object)
					chosenParent = object
					Targets.updateParenter()
				end
			)
			return
		end

		local target =
			assert(Targets.parenterTarget(), "Pick the child master control, bone or part first")
		if kind == "parent" then
			assert(chosenParent and chosenParent.Parent, "Choose the parent first")
			Targets.setChild(target.motor, target.rig, chosenParent)
			pickingOwner = false
		elseif kind == "world" then
			Targets.setChild(target.motor, target.rig, nil, nil, true)
		elseif kind == "inverse" or kind == "clearInverse" then
			Targets.setInverse(target, kind == "clearInverse")
		end
	end)
	if not ok then
		require("Notification").show("DYNAMIC PARENTING", (tostring(err):gsub("^.-:%d+: ", "")))
	end

	parenterStamp = nil
	Targets.updateHierarchy()
	Targets.updateParenter()
end

function Targets.trackMotor(item)
	if item.trackIsMaster and typeof(item.linkedRigInstance) == "Instance" then
		if item.linkedRigInstance:IsA("Model") then
			return Master.get(item.linkedRigInstance)
		elseif item.linkedRigInstance:IsA("BasePart") then
			return propertyTransform(item.linkedRigInstance)
		end
	end

	return item.fetchMotor and item:fetchMotor()
end

function Targets.switchSpace(motor, rig)
	local link = Target.childAt(motor, State.Timeline:GetState().CurrentTime)
	if not link then
		return false
	end

	local parent = Target.resolve(link)
	if not parent then
		return false
	end

	Targets.setChild(motor, rig, parent, nil, not link.world)
	return true
end

function Targets.bindObjectRow(item)
	if not item.trackIsMaster or item.dynamicParentButton then
		return
	end

	local motor = Targets.trackMotor(item)
	if not motor then
		return
	end

	local button = ParentingUI.modeButton(item.appearDetails.RightDiv, "DynamicParenting")
	button.LayoutOrder = -1
	item.dynamicParentButton = button
	local timeline = State.Timeline
	timeline:RegisterParentingControl(button, motor, function()
		local link = Target.childAt(motor, timeline:GetState().CurrentTime)
		button.Visible = link ~= nil
		ParentingUI.paint(button, link ~= nil and not link.world)
	end, item.linkedRigInstance)
	table.insert(
		item.connections,
		button.MouseButton1Click:Connect(function()
			Targets.switchSpace(motor, item.linkedRigInstance)
		end)
	)
	local hover = item.rigModule.refs.UIHelpers.hoverDialog
	if hover then
		hover:latchToInstance(button, "Parent / World")
	end
end

function Targets.updateHierarchy()
	local rig = State.Rig
	if not rig or not rig._hierarchyOrganization then
		hierarchyIndex = nil
		table.clear(hierarchyLinks)
		return
	end

	if rig._rebuilding or rig._batchHold then
		return
	end

	local raw = State.Timeline:GetState()

	local items = rig._organizationItems
	local revision = require("cache").revision()
	local index = hierarchyIndex
	if
		not index
		or index.rig ~= rig
		or index.items ~= items
		or index.organization ~= rig._hierarchyOrganization
		or index.keys ~= raw.Keyframes
		or index.revision ~= revision
	then
		index = {
			rig = rig,
			items = items,
			organization = rig._hierarchyOrganization,
			keys = raw.Keyframes,
			revision = revision,
			motors = {},
		}
		for _, item in items or {} do
			local motor = Targets.trackMotor(item)
			if motor and Target.hasChild(raw.Keyframes[motor]) then
				table.insert(index.motors, motor)
			end
		end

		hierarchyIndex = index
	end

	local now = {}
	local changed = false

	for _, motor in index.motors do
		if motor.Parent then
			local link = Target.childAt(motor, raw.CurrentTime)
			local parent = (link and Target.resolve(link)) or nil
			if parent then
				now[motor] = parent
			end

			if hierarchyLinks[motor] ~= parent then
				changed = true
			end
		end
	end

	for motor, parent in hierarchyLinks do
		if now[motor] ~= parent then
			changed = true
		end
	end

	if changed and not require("Hierarchy").refreshDynamic(rig) then
		return
	end

	hierarchyLinks = now
end

function Targets.closeParenter()
	pickingOwner = false
	parenterOwner = nil
	pickingChild = nil
	if parenter then
		local old = parenter
		parenter = nil
		old:close()
	end
end

function Targets.openParenter()
	if not refs or not refs.Active() then
		return
	end

	if parenter then
		return
	end

	parenterOwner = nil
	pickingOwner = false
	chosenParent = Targets.selectedParent()
	parenter = Tool.new(
		refs,
		"EclipseDynamicParenterWindow",
		"DYNAMIC PARENTING",
		Vector2.new(340, 320),
		true,

		function()
			parenter = nil
			pickingChild = nil
			parenterOwner = nil
			pickingOwner = false
		end
	)
	local frame = parenter.frame
	Tool.label(frame, "Owner", "", UDim2.fromOffset(12, 68), UDim2.new(1, -92, 0, 20)).TextTruncate =
		Enum.TextTruncate.AtEnd
	Tool.button(frame, "Pick", "PICK", UDim2.new(1, -72, 0, 68), UDim2.fromOffset(60, 20), function()
		Targets.parenterAction("pick")
	end
)
	Tool.label(frame, "TargetLabel", "Parent", UDim2.fromOffset(12, 34), UDim2.fromOffset(48, 24))
	local browse = Tool.button(
		frame,
		"Browse",
		"None",
		UDim2.fromOffset(66, 32),
		UDim2.fromOffset(154, 28),

		function()
			Targets.parenterAction("browse")
		end
	)
	browse.TextLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Tool.button(
		frame,
		"UseSelected",
		"USE SELECTED",
		UDim2.fromOffset(226, 32),
		UDim2.fromOffset(102, 28),

		function()
			Targets.parenterAction("selected")
		end
	)
	Tool.button(
		frame,
		"SetInverse",
		"SET INVERSE",
		UDim2.fromOffset(12, 132),
		UDim2.fromOffset(154, 26),

		function()
			Targets.parenterAction("inverse")
		end
	)
	Tool.button(
		frame,
		"ClearInverse",
		"CLEAR INVERSE",
		UDim2.fromOffset(174, 132),
		UDim2.fromOffset(154, 26),

		function()
			Targets.parenterAction("clearInverse")
		end
	)
	Tool.button(frame, "Attach", "PARENT", UDim2.fromOffset(12, 98), UDim2.fromOffset(154, 26), function()
		Targets.parenterAction("parent")
	end
)
	Tool.button(frame, "World", "UNPARENT", UDim2.fromOffset(174, 98), UDim2.fromOffset(154, 26), function()
		Targets.parenterAction("world")
	end
)
	Tool.label(
		frame,
		"Heading",
		"KEYED SWITCHES",
		UDim2.fromOffset(12, 168),
		UDim2.new(1, -100, 0, 18)
	).TextTransparency =
		0.35
	local current = Tool.make("Frame", frame, "Current", {
		Position = UDim2.new(1, -90, 0, 166),
		Size = UDim2.fromOffset(78, 20),
		BackgroundTransparency = 1,
	})
	Tool.label(current, "Label", "", UDim2.new(), UDim2.fromScale(1, 1)).TextXAlignment =
		Enum.TextXAlignment.Right
	local shell = Tool.make("Frame", frame, "Switches", {
		Position = UDim2.fromOffset(12, 190),
		Size = UDim2.new(1, -24, 1, -202),
		BorderSizePixel = 0,
	})
	shell:SetAttribute("ThemeBg", "TopBtn")
	local outline = Tool.make(
		"UIStroke",
		shell,
		"Outline",
		{ Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	outline:SetAttribute("ThemeStrk", "Strk")
	local list = Tool.make("ScrollingFrame", shell, "List", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	Tool.make(
		"UIListLayout",
		list,
		"Rows",
		{ Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	Theme.applyTree(frame)
	parenterStamp = nil
	Targets.updateParenter()
end

function Targets.toggleParenter()
	if parenter then
		Targets.closeParenter()
	else
		Targets.openParenter()
	end
end

function Targets.updateParenter()
	if not parenter or not parenter.frame.Parent then
		return
	end

	if not State.Timeline then
		return
	end

	local frame = parenter.frame
	local raw = State.Timeline:GetState()
	local target = Targets.parenterTarget()
	if pickingChild and not pickingChild.motor.Parent then
		pickingChild = nil
	end

	local frameNumber = State.Timeline:TimeToFrame(raw.CurrentTime)
	local link
	if target then
		local motor = target.kind == "camera" and Target.ensure(target.rig) or target.motor
		local key = motor and Target.previous(raw.Keyframes[motor], raw.CurrentTime)
		link = key and key.CamTargetParent
		if target.kind == "motor" and not link and key and key.Parented == false then
			link = "world"
		end
	end

	frame.Owner.Text = target and ("Child: " .. target.label) or "Child: None"
	local selected = chosenParent and chosenParent.Parent and Targets.objectTarget(chosenParent)
	frame.Browse.TextLabel.Text = selected and selected.label
		or chosenParent and chosenParent.Parent and chosenParent.Name
		or "None"
	frame.Current.Label.Text = "Frame " .. frameNumber
	local picking_ = pickingChild ~= nil or (picking ~= nil and target and target.kind == "camera")
	frame.Pick.TextLabel.Text = pickingOwner and "CANCEL" or "PICK"
	for _, name in
		{ "Pick", "UseSelected", "Browse", "Attach", "World", "SetInverse", "ClearInverse" }
	do
		local ready = (name == "Pick" or name == "UseSelected" or name == "Browse" or target ~= nil)
			and (name ~= "Attach" or chosenParent ~= nil)
			and not raw.Playing
			and ((name ~= "SetInverse" and name ~= "ClearInverse") or typeof(link) == "table")
		frame[name].Active = ready
		frame[name]:SetAttribute("Ready", ready)
		frame[name].TextLabel.TextTransparency = ready and 0.1 or 0.6
	end

	local motor = target and (target.kind == "camera" and Target.ensure(target.rig) or target.motor)
	local count = 0
	for _ in motor and raw.Keyframes[motor] or {} do
		count += 1
	end

	local stamp = tostring(motor)
		.. ":"
		.. count
		.. ":"
		.. tostring(link and (typeof(link) == "table" and link.id or link))
	if stamp == parenterStamp then
		return
	end

	parenterStamp = stamp
	local list = frame.Switches.List
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local rows = target and switchesFor(target) or {}
	if #rows == 0 then
		Tool.label(list, "Empty", "\u{2014}", UDim2.new(), UDim2.new(1, -6, 0, 24)).TextTransparency =
			0.45
		Theme.applyTree(list)
		return
	end

	for index, row in rows do
		local button = Tool.make("TextButton", list, "Switch", {
			Text = "",
			Size = UDim2.new(1, -6, 0, 24),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		})
		local text = Tool.label(
			button,
			"Label",
			string.format("Frame %d   \u{2192}   %s", row.frame, row.world and "World" or row.label),
			UDim2.fromOffset(7, 0),
			UDim2.new(1, -14, 1, 0)
		)
		text.TextWrapped = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0.55
			button.BackgroundColor3 = Theme.get("TopBtnHover", Color3.fromRGB(73, 46, 90))
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
		end)
		button.Activated:Connect(function()
			if raw.Playing then
				return
			end

			raw.CurrentTime = State.Timeline:FrameToTime(row.frame)
			if State.currentRig then
				State.Timeline:ApplyPoseAtTime(State.currentRig, raw.CurrentTime)
			end

			State.Timeline:UpdatePlayhead()
		end)
	end

	Theme.applyTree(list)
end

function Targets.updatePanel()
	Targets.updateHierarchy()
	Target.syncChildren()
	Targets.updateParenter()
	Targets.updateRows()
	local selected = Targets.selectedRig()
	if manualRig ~= selected then
		manualRig = nil
	end

	local rig = panelAllowed() and (picking or selected) or nil
	if Preferences.get("CamTargetParentButton") == true and manualRig ~= rig then
		rig = nil
	end

	if rig and (not rig.Parent or rig:GetAttribute("EclipseHideCamTarget") == true) then
		rig = nil
	end

	if dismissed and dismissed ~= rig then
		dismissed = nil
	end

	if dismissed == rig then
		rig = nil
	end

	if rig ~= panelRig then
		local requested, requestedManual = picking, manualRig
		Targets.closePanel()
		picking = rig and requested or nil
		manualRig = rig and requestedManual or nil
		if rig then
			panelRig = rig
			panel = Tool.new(
				refs,
				"EclipseDynamicParenter",
				"DYNAMIC PARENTER",
				Vector2.new(304, 164),
				false,

				function()
					dismissed = panelRig
					panel = nil
					panelRig = nil
					picking = nil
					manualRig = nil
				end
			)
			local frame = panel.frame
			frame.AnchorPoint = Vector2.one
			frame.Position = UDim2.new(1, -16, 1, -16)
			Tool.label(
				frame,
				"Camera",
				rig.Name .. " / CamTarget",
				UDim2.fromOffset(12, 34),
				UDim2.new(1, -24, 0, 20)
			)
			local parent = Tool.make("Frame", frame, "Binding", {
				Position = UDim2.fromOffset(12, 62),
				Size = UDim2.new(1, -24, 0, 28),
				BorderSizePixel = 0,
			})
			parent:SetAttribute("ThemeBg", "TopBtn")
			local text =
				Tool.label(parent, "Label", "", UDim2.fromOffset(8, 0), UDim2.new(1, -16, 1, 0))
			text.TextWrapped = false
			text.TextTruncate = Enum.TextTruncate.AtEnd

			local function action(callback)
				if State.Timeline:GetState().Playing then
					return
				end

				local ok, err = pcall(callback)
				if not ok then
					require("Notification").show("CAMTARGET", (tostring(err):gsub("^.-:%d+: ", "")))
				end
			end

			Tool.button(
				frame,
				"Pick",
				"PICK OBJECT",
				UDim2.fromOffset(12, 100),
				UDim2.fromOffset(112, 26),

				function()
					action(function()
						if picking then
							Targets.cancelPick()
						else
							Targets.beginPick(rig)
						end
					end)
				end
			)
			Tool.button(
				frame,
				"Browse",
				"BROWSE",
				UDim2.fromOffset(132, 100),
				UDim2.fromOffset(77, 26),

				function()
					action(function()
						Targets.cancelPick()
						Targets.openParent(rig)
					end)
				end
			)
			Tool.button(
				frame,
				"World",
				"WORLD",
				UDim2.fromOffset(217, 100),
				UDim2.fromOffset(75, 26),

				function()
					action(function()
						Targets.cancelPick()
						Targets.setParent(rig, nil)
					end)
				end
			)
			Tool.label(frame, "Time", "", UDim2.fromOffset(12, 137), UDim2.new(1, -24, 0, 19))
			Theme.applyTree(frame)
		end
	end

	if not panel or not rig then
		return
	end

	local raw = State.Timeline:GetState()
	local key = Target.previous(raw.Keyframes[Target.ensure(rig)], raw.CurrentTime)
	panel.frame.Binding.Label.Text = "Parent: "
		.. (key and key.CamTargetParent and key.CamTargetParent.label or "World")
	panel.frame.Pick.TextLabel.Text = picking and "CANCEL PICK" or "PICK OBJECT"
	panel.frame.Time.Text = "Change at frame " .. State.Timeline:TimeToFrame(raw.CurrentTime)
	for _, name in { "Pick", "Browse", "World" } do
		local button = panel.frame[name]
		button.Active = not raw.Playing
		button:SetAttribute("Ready", not raw.Playing)
	end
end

function Targets.init(options)
	if refs == options then
		return
	end

	refs = options
	options.State.CameraTargets = Targets
	local connection = game:GetService("RunService").RenderStepped:Connect(Targets.updatePanel)

	local function closeAll()
		connection:Disconnect()
		Targets.close()
		Targets.closePanel()
		Targets.closeParenter()
	end

	options.ScreenGui.Destroying:Once(closeAll)
	options.Plugin.Unloading:Once(closeAll)
	options.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not options.AnimatorFrame.Visible then
			Targets.close()
			Targets.closePanel()
			Targets.closeParenter()
		end
	end)
end

return Targets
