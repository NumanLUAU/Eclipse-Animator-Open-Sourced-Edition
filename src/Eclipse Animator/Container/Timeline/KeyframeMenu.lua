--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local SavedDefaults = require("SavedDefaults")
local ChannelEasing = require("ChannelEasing")
local Shortcuts = require("Shortcuts")
local BlenderEdit = require("BlenderEdit")
local KeyframeValues = require("KeyframeValues")
local CameraRig = require("CameraRig")
local CameraControls = require("CameraControls")
local UserInputService = require("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local State = require("State")
local Defaults = require("Defaults")
local Easing = require("Easing")
local DropdownConfigs = require("DropdownConfigs")
local DropdownBuilder = require("DropdownBuilder")
local motionPath = require("motionPath")
local CurveGraph = require("CurveGraph")
local Theme = require("Theme")

local KeyframeMenu = {}

local DEFAULT_COLOR = Color3.fromRGB(51, 0, 77)
local HOVER_COLOR = Color3.fromRGB(34, 0, 52)
local SELECTED_COLOR = Color3.fromRGB(100, 0, 151)

Theme.onChanged(function()
	HOVER_COLOR = Theme.get("MenuHov", Color3.fromRGB(34, 0, 52))
	SELECTED_COLOR = Theme.get("MenuSel", Color3.fromRGB(100, 0, 151))
end)
local HALFTONE_WHITE = Color3.fromRGB(255, 255, 255)
local HALFTONE_BLACK = Color3.fromRGB(0, 0, 0)
local HALFTONE_SELECTED_TRANSPARENCY = 0.4
local HALFTONE_HOVER_TRANSPARENCY = 0.8
local HALFTONE_HIDDEN_TRANSPARENCY = 1
local CURSOR_OFFSET_X = 8
local CURSOR_OFFSET_Y = 8
local OPEN_DEBOUNCE = 0.1
local FADE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DESIGN_VP_X = 1920
local DESIGN_VP_Y = 1080
local SUBFRAME_BIASES = {
	HandleType = { x = 25, y = -18 },
	EasingMode = { x = 23, y = -12 },
	InterpolationMode = { x = 300, y = 0 },
}
local SUBFRAME_OFFSET_X_BIAS_DEFAULT = 26
local SUBFRAME_OFFSET_Y_BIAS_DEFAULT = -16
local BRIDGE_PADDING = 6

local PRIMARY_MENU_NAMES = {
	DefaultSelection = true,
	MainSelection = true,
	SecondarySelection = true,
}

local IGNORED_MENU_NAMES = {
	DropdownTemplate = true,
}

local curvePicker

local function curveSettings()
	if curvePicker then
		return require("GraphCurves").clone(curvePicker.values)
	end

	return SavedDefaults.get()
end

local function setCurveSetting(field, value)
	if curvePicker then
		local normalized = SavedDefaults.normalize(field, value)
		if normalized == nil then
			return false
		end

		curvePicker.values[field] = normalized
		return true
	end

	return SavedDefaults.set(field, value)
end

local editingDefaults = false
local defaultMenuFrame
local defaultCurveDraft
local mainMenuFrame = nil
local secondaryMenuFrame = nil
local activeMenuFrame = nil
local uiScale = nil
local frozenSelection = nil
local frozenBones = nil
local frozenToggleTargets = {}
local frozenInsertTarget
local frozenIsChannelOnly = false
local opened = false
local directInterpolation = false
local openedAt = 0
local connections = {}
local selectionWatch = nil
local subFrameOffsets = {}
local dropdownSetups = {}
local mainButtonRefs = {}
local secondaryButtonRefs = {}
local optionRefreshers = {}
local paramSlots = {}
local parametersFrame = nil
local resetBezierButton
local parametersEmptyLabel = nil
local parametersEmptyText, curvePreviewFrame
local bezierHandle1 = nil
local bezierHandle2 = nil
local pendingDragSnapshots = nil
local handleDragging = false
local cameraValueRow, cameraValueField, valuePanel
local refreshParametersUI

local function getDesignTopLeft(frame)
	local pos = frame.Position
	local size = frame.Size
	local anchor = frame.AnchorPoint
	local cx = pos.X.Scale * DESIGN_VP_X + pos.X.Offset
	local cy = pos.Y.Scale * DESIGN_VP_Y + pos.Y.Offset
	local sx = size.X.Scale * DESIGN_VP_X + size.X.Offset
	local sy = size.Y.Scale * DESIGN_VP_Y + size.Y.Offset
	return Vector2.new(cx - anchor.X * sx, cy - anchor.Y * sy)
end

local function precomputeOffsets(dropdownsFolder)
	if not dropdownsFolder or not mainMenuFrame then
		return
	end

	local mainTL = getDesignTopLeft(mainMenuFrame)
	for _, child in ipairs(dropdownsFolder:GetChildren()) do
		if
			child:IsA("Frame")
			and not PRIMARY_MENU_NAMES[child.Name]
			and not IGNORED_MENU_NAMES[child.Name]
			and not subFrameOffsets[child]
		then
			local subTL = getDesignTopLeft(child)
			subFrameOffsets[child] = subTL - mainTL
		end
	end
end

local function pointInFrame(x, y, frame)
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	return x >= pos.X and x <= pos.X + size.X and y >= pos.Y and y <= pos.Y + size.Y
end

local function pointerHeld()
	return handleDragging or UserInputService.isPointerHeld()
end

local function asString(v)
	if typeof(v) == "EnumItem" then
		return v.Name
	end

	return v
end

local OPTION_TO_EASING = {
	Beziar = "Bezier",
}

local CLICK_OVERRIDES = {}

local function canonicalEasingForOption(optionName)
	return Easing.styleName(OPTION_TO_EASING[optionName] or optionName)
end

local function easingToApplyForOption(optionName)
	return canonicalEasingForOption(CLICK_OVERRIDES[optionName] or optionName)
end

local function currentKey(key)
	local timeline = State.Timeline and State.Timeline:GetState()
	local bucket = timeline and key and timeline.Keyframes[key.Motor]
	return bucket and bucket[key.Frame] or nil
end

local function getEffectiveCurveSource()
	if editingDefaults then
		return defaultCurveDraft or curveSettings()
	end

	local sources = {}
	local Policy = require("Policy")
	local Curves = require("GraphCurves")

	local function channelSource(key, id)
		local point = key.GraphCurves and key.GraphCurves[id]
		local source = table.clone(
			point and point.Empty and ChannelEasing.resolve(key, id) or ChannelEasing.view(key, id)
		)

		if point and not point.Empty then
			if point.Interpolation == "Legacy" then
				local easing = point.Easing or key
				for _, field in ChannelEasing.fields do
					source[field] = easing[field]
				end
			else
				source.EasingStyle = point.Interpolation or "Bezier"
			end

			if point.HandleType then
				source.HandleType = point.HandleType
			end
		end

		return source
	end

	local function add(key, id)
		key = currentKey(key)
		if not key then
			return
		end

		if id then
			table.insert(sources, channelSource(key, id))
			return
		end

		local bucket = State.Timeline:GetState().Keyframes[key.Motor]
		local order = Curves.rotationOrder(bucket)
		local found, ids = false, {}
		if Policy.channelsEnabled() or order then
			for name, channel in key.Channels or {} do
				if channel.Value ~= nil and not channel.Disabled then
					ids[name] = true
				end
			end

			for name, point in key.GraphCurves or {} do
				if point.Value ~= nil and not point.Empty and not point.Disabled then
					ids[name] = true
				end
			end

			for name in ids do
				if
					not Policy.isDisabled(key, name)
					and Curves.rotationChannelVisible(bucket, name)
				then
					table.insert(sources, channelSource(key, name))
					found = true
				end
			end
		end

		if not found then
			table.insert(sources, key)
		end
	end

	if #frozenToggleTargets > 0 then
		for _, target in frozenToggleTargets do
			add(target.key, target.id)
		end
	else
		for _, key in frozenSelection or {} do
			add(key)
		end
	end

	if #sources == 0 then
		return nil
	end

	local result = { _MixedFields = {} }
	local fallback = { Amplitude = 1, Period = 0.3, Overshoot = 1.70158 }
	for _, field in ChannelEasing.fields do
		local function value(source)
			local value = source[field] or Defaults[field] or fallback[field]
			return field == "EasingStyle" and Easing.styleName(value) or asString(value)
		end

		local first = value(sources[1])
		for i = 2, #sources do
			if not ChannelEasing.equal(first, value(sources[i])) then
				result._MixedFields[field] = true
				break
			end
		end

		if not result._MixedFields[field] then
			result[field] = ChannelEasing.clone(first)
		end
	end

	return result
end

local function resolveSelectedOptionForSubMenu(subMenuName)
	if subMenuName == "DefaultInterpolation" then
		subMenuName = "InterpolationMode"
	end

	local source = getEffectiveCurveSource()
	if not source then
		return nil
	end

	local cfg = DropdownConfigs[subMenuName]
	if cfg then
		for _, row in ipairs(cfg.rows) do
			if typeof(row) == "table" and row.apply then
				local field = row.apply.field
				if
					not (source._MixedFields and source._MixedFields[field])
					and asString(source[field] or Defaults[field]) == row.apply.value
					and not (field == "EasingDirection" and row.apply.value == "Automatic"
						and Easing.styleName(source.EasingStyle or Defaults.EasingStyle) == "Bezier"
						and not ChannelEasing.isAutomaticBezier(source))
				then
					return row.id
				end
			end
		end
	elseif subMenuName == "InterpolationMode" then
		return not (source._MixedFields and source._MixedFields.EasingStyle)
				and Easing.styleName(source.EasingStyle or Defaults.EasingStyle)
			or nil
	end

	return nil
end

local function refreshCurveGraph(immediate)
	local kd = getEffectiveCurveSource()
	local mixed = kd and kd._MixedFields and next(kd._MixedFields) ~= nil
	if curvePreviewFrame then
		curvePreviewFrame.Visible = kd ~= nil and not mixed
	end

	if not kd or mixed then
		return
	end

	if immediate then
		CurveGraph.setTargetImmediate(kd)
	else
		CurveGraph.setTarget(kd)
	end
end

local function refreshAllOptionStates()
	for _, refresher in ipairs(optionRefreshers) do
		refresher()
	end
end

local function resolveSubMenuContext(btn)
	local optionFrame = btn.Parent
	if not optionFrame then
		return nil, nil
	end

	local cursor = optionFrame
	while cursor and cursor.Parent and cursor.Parent.Name ~= "Content" do
		cursor = cursor.Parent
	end

	if not cursor or not cursor.Parent or cursor.Parent.Name ~= "Content" then
		return nil, nil
	end

	local content = cursor.Parent
	local subMenuFrame = content.Parent
	if not subMenuFrame then
		return nil, nil
	end

	if PRIMARY_MENU_NAMES[subMenuFrame.Name] then
		return nil, nil
	end

	return optionFrame.Name, subMenuFrame.Name
end

local function isOptionSelected(btn)
	local optionName, subMenuName = resolveSubMenuContext(btn)
	if not optionName then
		return false
	end

	if subMenuName == "InterpolationMode" then
		return resolveSelectedOptionForSubMenu(subMenuName) == canonicalEasingForOption(optionName)
	end

	return resolveSelectedOptionForSubMenu(subMenuName) == optionName
end

local function wireButton(btn, onOptionClick)
	local halftone = btn:FindFirstChild("Halftone")
	local checkIcon = btn:FindFirstChild("Check")
	local isDropdown = btn:FindFirstChild("Arrow") ~= nil
	local optionName, subMenuName = resolveSubMenuContext(btn)
	local isOptionButton = optionName ~= nil

	btn.AutoButtonColor = false
	if halftone then
		halftone.Visible = true
	end

	local activeBgTween = nil
	local activeHalftoneTransparencyTween = nil
	local activeHalftoneColorTween = nil

	local function tweenBg(color, transparency)
		if activeBgTween then
			activeBgTween:Cancel()
		end

		if btn.BackgroundTransparency >= 0.99 then
			btn.BackgroundColor3 = color
		end

		activeBgTween = TweenService:Create(
			btn,
			FADE_TWEEN,
			{ BackgroundColor3 = color, BackgroundTransparency = transparency or 0 }
		)
		activeBgTween:Play()
	end

	local function tweenHalftone(transparency, color)
		if not halftone then
			return
		end

		if activeHalftoneTransparencyTween then
			activeHalftoneTransparencyTween:Cancel()
		end

		activeHalftoneTransparencyTween =
			TweenService:Create(halftone, FADE_TWEEN, { ImageTransparency = transparency })
		activeHalftoneTransparencyTween:Play()
		if color then
			if activeHalftoneColorTween then
				activeHalftoneColorTween:Cancel()
			end

			activeHalftoneColorTween =
				TweenService:Create(halftone, FADE_TWEEN, { ImageColor3 = color })
			activeHalftoneColorTween:Play()
		end
	end

	local function setCheck(visible)
		if checkIcon then
			checkIcon.Visible = visible
		end
	end

	local function applySelected()
		tweenBg(SELECTED_COLOR)
		tweenHalftone(HALFTONE_SELECTED_TRANSPARENCY, HALFTONE_BLACK)
		setCheck(true)
	end

	local function applyDefault()
		if isOptionSelected(btn) then
			applySelected()
		else
			tweenBg(DEFAULT_COLOR, 1)
			tweenHalftone(HALFTONE_HIDDEN_TRANSPARENCY, HALFTONE_WHITE)
			setCheck(false)
		end
	end

	local function applyHover()
		if isOptionSelected(btn) then
			applySelected()
		else
			tweenBg(HOVER_COLOR)
			tweenHalftone(HALFTONE_HOVER_TRANSPARENCY, HALFTONE_WHITE)
			setCheck(false)
		end
	end

	applyDefault()

	if isOptionButton then
		table.insert(optionRefreshers, applyDefault)
	end

	btn.MouseEnter:Connect(applyHover)
	btn.MouseLeave:Connect(applyDefault)

	if not isDropdown then
		btn.MouseButton1Down:Connect(function()
			tweenBg(SELECTED_COLOR)
			tweenHalftone(HALFTONE_SELECTED_TRANSPARENCY, HALFTONE_BLACK)
		end)

		if isOptionButton and onOptionClick then
			btn.MouseButton1Click:Connect(function()
				onOptionClick(subMenuName, optionName, btn)
			end)
		else
			btn.MouseButton1Up:Connect(applyHover)
		end
	end
end

local function wireDropdownButtonWithSubFrame(btn, subFrame, offset)
	local halftone = btn:FindFirstChild("Halftone")

	btn.AutoButtonColor = false
	if halftone then
		halftone.Visible = true
	end

	subFrame.AnchorPoint = Vector2.new(0, 0)
	subFrame.Visible = false

	local logicallyHovered = false
	local pinned = false
	local pollConn = nil

	local activeBgTween = nil
	local activeHalftoneTransparencyTween = nil
	local activeHalftoneColorTween = nil

	local function tweenBg(color, transparency)
		if activeBgTween then
			activeBgTween:Cancel()
		end

		if btn.BackgroundTransparency >= 0.99 then
			btn.BackgroundColor3 = color
		end

		activeBgTween = TweenService:Create(
			btn,
			FADE_TWEEN,
			{ BackgroundColor3 = color, BackgroundTransparency = transparency or 0 }
		)
		activeBgTween:Play()
	end

	local function tweenHalftone(transparency, color)
		if not halftone then
			return
		end

		if activeHalftoneTransparencyTween then
			activeHalftoneTransparencyTween:Cancel()
		end

		activeHalftoneTransparencyTween =
			TweenService:Create(halftone, FADE_TWEEN, { ImageTransparency = transparency })
		activeHalftoneTransparencyTween:Play()
		if color then
			if activeHalftoneColorTween then
				activeHalftoneColorTween:Cancel()
			end

			activeHalftoneColorTween =
				TweenService:Create(halftone, FADE_TWEEN, { ImageColor3 = color })
			activeHalftoneColorTween:Play()
		end
	end

	local function applyOpen()
		tweenBg(SELECTED_COLOR)
		tweenHalftone(HALFTONE_SELECTED_TRANSPARENCY, HALFTONE_BLACK)
	end

	local function applyClosed()
		tweenBg(DEFAULT_COLOR, 1)
		tweenHalftone(HALFTONE_HIDDEN_TRANSPARENCY, HALFTONE_WHITE)
	end

	applyClosed()

	local function isMouseInHotZone(mp)
		local focused = UserInputService:GetFocusedTextBox()
		if focused and focused:IsDescendantOf(subFrame) then
			return true
		end

		if pointInFrame(mp.X, mp.Y, btn) then
			return true
		end

		if subFrame.Visible and pointInFrame(mp.X, mp.Y, subFrame) then
			return true
		end

		if subFrame.Visible then
			local bp = btn.AbsolutePosition
			local bs = btn.AbsoluteSize
			local sp = subFrame.AbsolutePosition
			local ss = subFrame.AbsoluteSize
			local from, to = bp.X + bs.X, sp.X
			if sp.X + ss.X <= bp.X then
				from, to = sp.X + ss.X, bp.X
			end

			local leftEdge = math.min(from, to) - BRIDGE_PADDING
			local rightEdge = math.max(from, to) + BRIDGE_PADDING
			local topEdge = math.min(bp.Y, sp.Y) - BRIDGE_PADDING
			local bottomEdge = math.max(bp.Y + bs.Y, sp.Y + ss.Y) + BRIDGE_PADDING
			if
				mp.X >= leftEdge
				and mp.X <= rightEdge
				and mp.Y >= topEdge
				and mp.Y <= bottomEdge
			then
				return true
			end
		end

		return false
	end

	local function positionSubFrame()
		require("Motion").placePopup(subFrame, btn, "right")
		if subFrame.Name == "Values" then
			valuePanel.refresh()
		end
	end

	local stopPolling

	local function startPolling()
		if pollConn then
			return
		end

		pollConn = RunService.Heartbeat:Connect(function()
			local mp = UserInputService:GetMouseLocation()
			if isMouseInHotZone(mp) then
				pinned = pointerHeld()
			elseif not pinned and not handleDragging then
				logicallyHovered = false
				applyClosed()
				subFrame.Visible = false
				stopPolling()
			end
		end)
	end

	stopPolling = function()
		if pollConn then
			pollConn:Disconnect()
			pollConn = nil
		end
	end

	local function setHovered()
		if not activeMenuFrame or not btn:IsDescendantOf(activeMenuFrame) then
			return
		end

		if logicallyHovered then
			return
		end

		for _, setup in dropdownSetups do
			if setup.subFrame ~= subFrame then
				setup.reset()
			end
		end

		logicallyHovered = true
		applyOpen()
		positionSubFrame()
		subFrame.Visible = true
		startPolling()
	end

	btn.MouseEnter:Connect(setHovered)
	subFrame.MouseEnter:Connect(setHovered)

	local function reset()
		stopPolling()
		pinned = false
		if logicallyHovered then
			logicallyHovered = false
			if activeBgTween then
				activeBgTween:Cancel()
				activeBgTween = nil
			end

			if activeHalftoneTransparencyTween then
				activeHalftoneTransparencyTween:Cancel()
				activeHalftoneTransparencyTween = nil
			end

			if activeHalftoneColorTween then
				activeHalftoneColorTween:Cancel()
				activeHalftoneColorTween = nil
			end

			btn.BackgroundColor3 = DEFAULT_COLOR
			btn.BackgroundTransparency = 1
			if halftone then
				halftone.ImageTransparency = HALFTONE_HIDDEN_TRANSPARENCY
				halftone.ImageColor3 = HALFTONE_WHITE
			end
		end

		subFrame.Visible = false
	end

	table.insert(dropdownSetups, { reset = reset, subFrame = subFrame })
end

local function findContainingSubFrame(btn)
	local cur = btn and btn.Parent
	while cur do
		if subFrameOffsets[cur] then
			return cur
		end

		cur = cur.Parent
	end

	return nil
end

local function closeSubFrame(subFrame)
	if not subFrame then
		return
	end

	for _, setup in ipairs(dropdownSetups) do
		if setup.subFrame == subFrame then
			setup.reset()
			refreshAllOptionStates()
			return
		end
	end
end

local function wireAllButtons(root, buttonRefs, onOptionClick)
	local dropdownsFolder = root.Parent
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("GuiButton") and desc ~= resetBezierButton then
			local hasArrow = desc:FindFirstChild("Arrow") ~= nil
			local subFrame = nil
			if hasArrow and dropdownsFolder then
				local parentName = desc.Parent and desc.Parent.Name
				if parentName then
					local candidate = dropdownsFolder:FindFirstChild(parentName)
					if
						candidate
						and not PRIMARY_MENU_NAMES[candidate.Name]
						and candidate:IsA("Frame")
					then
						subFrame = candidate
					end
				end
			end

			if subFrame and subFrameOffsets[subFrame] then
				wireDropdownButtonWithSubFrame(desc, subFrame, subFrameOffsets[subFrame])
			else
				wireButton(desc, onOptionClick)
			end

			if buttonRefs and desc.Parent then
				buttonRefs[desc.Parent.Name] = desc
			end
		end
	end
end

local function isMouseInsideMenuOrSubFrames(mp)
	if activeMenuFrame and pointInFrame(mp.X, mp.Y, activeMenuFrame) then
		return true
	end

	for subFrame in pairs(subFrameOffsets) do
		if subFrame.Visible and pointInFrame(mp.X, mp.Y, subFrame) then
			return true
		end
	end

	return false
end

local function isFrozenSelectionStillValid()
	if not frozenSelection or #frozenSelection == 0 then
		return true
	end

	if not State.Timeline then
		return true
	end

	local tl = State.Timeline:GetState()
	if not tl or not tl.Keyframes then
		return true
	end

	for index, kd in ipairs(frozenSelection) do
		local latest = currentKey(kd)
		if not latest then
			return false
		end

		if latest ~= kd then
			frozenSelection[index] = latest
			for _, target in frozenToggleTargets do
				if target.key == kd then
					target.key = latest
				end
			end
		end
	end

	return true
end

local function close(flushPending)
	if selectionWatch then
		selectionWatch:Disconnect()
		selectionWatch = nil
	end

	if not opened then
		return
	end

	CurveGraph.suspend(flushPending)
	opened = false
	directInterpolation = false
	editingDefaults = false
	if curvePicker then
		local picker = curvePicker
		curvePicker = nil
		for _, connection in picker.connections do
			connection:Disconnect()
		end

		picker.frame.Visible = false
		if picker.frame.Parent and picker.parent.Parent then
			picker.frame.Parent = picker.parent
		end
		picker.frame.Position = picker.position
		picker.frame.AnchorPoint = picker.anchor
		for object, z in picker.zindexes or {} do
			if object.Parent then
				object.ZIndex = z
			end
		end
	end

	if defaultMenuFrame then
		defaultMenuFrame.Visible = false
	end

	frozenToggleTargets = {}
	frozenInsertTarget = nil
	frozenSelection = nil
	frozenBones = nil
	frozenIsChannelOnly = false
	for _, setup in ipairs(dropdownSetups) do
		setup.reset()
	end

	if mainMenuFrame then
		mainMenuFrame.Visible = false
	end

	if secondaryMenuFrame then
		secondaryMenuFrame.Visible = false
	end

	activeMenuFrame = nil
end

local function watchSelection()
	if selectionWatch then
		selectionWatch:Disconnect()
	end

	local previous = ChannelEasing.clone(getEffectiveCurveSource())
	selectionWatch = RunService.Heartbeat:Connect(function()
		if not isFrozenSelectionStillValid() then
			close()
			return
		end

		local source = getEffectiveCurveSource()
		if not ChannelEasing.equal(previous, source) then
			previous = ChannelEasing.clone(source)
			refreshAllOptionStates()
			refreshParametersUI()
			refreshCurveGraph(true)
		end
	end)
end

local function snapshotSelection()
	if not State.Timeline then
		return {}
	end

	local timeline = State.Timeline:GetState()
	for selected in table.clone(timeline.SelectedKeyframes or {}) do
		local latest = currentKey(selected)
		if latest ~= selected then
			timeline.SelectedKeyframes[selected] = nil
			if latest then
				timeline.SelectedKeyframes[latest] = true
			end
		end
	end

	for selected, channels in table.clone(timeline.SelectedChannelKeyframes or {}) do
		local latest = currentKey(selected)
		if latest ~= selected then
			timeline.SelectedChannelKeyframes[selected] = nil
			if latest then
				local merged = timeline.SelectedChannelKeyframes[latest] or {}
				for id, enabled in channels do
					merged[id] = enabled
				end

				timeline.SelectedChannelKeyframes[latest] = merged
			end
		end
	end

	timeline.SelectedKeyframe = currentKey(timeline.SelectedKeyframe)
	local seen = {}
	local copy = {}
	local list = State.Timeline:GetSelectedKeyframesList() or {}
	for _, selected in ipairs(list) do
		local kd = currentKey(selected)
		if kd and not seen[kd] then
			seen[kd] = true
			table.insert(copy, kd)
		end
	end

	if State.Timeline.GetSelectedChannelKeyframesList then
		local channelList = State.Timeline:GetSelectedChannelKeyframesList() or {}
		for _, entry in ipairs(channelList) do
			local kd = currentKey(entry and entry.keyData)
			if kd and not seen[kd] then
				seen[kd] = true
				table.insert(copy, kd)
			end
		end
	end

	return copy
end

local function snapshotSelectedBones()
	if not State.Axis or not State.Axis.GetSelectedBones then
		return {}
	end

	local list = State.Axis:GetSelectedBones() or {}
	local copy = {}
	for _, b in ipairs(list) do
		table.insert(copy, b)
	end

	return copy
end

local function setButtonText(btn, text)
	if not btn then
		return
	end

	local title = btn:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	end
end

local function updateLabelsForMain()
	local stretch, fill = require("fill").availability(State.Timeline)
	for id, enabled in { StretchFrames = stretch, FillFrames = fill } do
		local button = mainButtonRefs[id]
		if button then
			button.Parent.Visible = enabled
		end
	end

	local cameraKeys = frozenSelection and #frozenSelection > 0
	for _, key in frozenSelection or {} do
		if not CameraRig.isFov(key.Motor) then
			cameraKeys = false
			break
		end
	end

	local attachmentKeys = frozenSelection and #frozenSelection > 0
	for _, key in frozenSelection or {} do
		if not require("Target").isAttachment(key.Motor) then
			attachmentKeys = false
			break
		end
	end

	for _, id in { "HandleType", "InterpolationMode", "EasingMode" } do
		local button = mainButtonRefs[id]
		if button then
			button.Parent.Visible = not attachmentKeys
		end
	end

	setButtonText(mainButtonRefs.Values, attachmentKeys and "Attach To Part" or "Values")
	if valuePanel then
		valuePanel.refresh()
	end

	if cameraValueRow then
		cameraValueRow.Visible = false
		mainButtonRefs.Values.Visible = true
		if cameraKeys then
			cameraValueField.Text = string.format(
				"%.2f",
				CameraRig.decode(frozenSelection[1].Motor, frozenSelection[1].C0)
			)
		end
	end

	local kfCount = #(frozenSelection or {})
	setButtonText(mainButtonRefs.DeleteKey, kfCount > 1 and "Delete Keyframes" or "Delete Keyframe")

	local enable = State.Timeline:KeyframeToggleEnables(frozenToggleTargets)
	if mainButtonRefs.ToggleKey and mainButtonRefs.ToggleKey:FindFirstChild("Icon") then
		mainButtonRefs.ToggleKey.Icon.Image = enable and "rbxassetid://77657913275528"
			or "rbxassetid://91467782437984"
	end

	setButtonText(
		mainButtonRefs.ToggleKey,
		(enable and "Enable " or "Disable ")
			.. (#frozenToggleTargets > 1 and "Keyframes" or "Keyframe")
	)
end

local function updateLabelsForSecondary()
	local boneCount = #(frozenBones or {})
	setButtonText(
		secondaryButtonRefs.InsertKey,
		boneCount > 1 and "Insert Keyframes" or "Insert Keyframe"
	)
end

local function positionMenuAtCursor(frame, cursorPos)
	frame.AnchorPoint = Vector2.new(0, 0)

	local scale = UserInputService.inWidget() and 1 or (uiScale and uiScale.Scale) or 1

	local screenX = cursorPos.X + CURSOR_OFFSET_X
	local screenY = cursorPos.Y + CURSOR_OFFSET_Y

	local cam = workspace.CurrentCamera
	if cam then
		local root = frame:FindFirstAncestorWhichIsA("LayerCollector")
		local vp = root and root.AbsoluteSize or cam.ViewportSize
		local absSize = frame.AbsoluteSize
		if screenX + absSize.X > vp.X then
			screenX = vp.X - absSize.X
		end

		if screenY + absSize.Y > vp.Y then
			screenY = vp.Y - absSize.Y
		end

		screenX = math.max(0, screenX)
		screenY = math.max(0, screenY)
	end

	frame.Position = UDim2.fromOffset(screenX / scale, screenY / scale)
end

local function open(cursorPos)
	if BlenderEdit.blocked() then
		return
	end

	if not mainMenuFrame then
		return
	end

	if opened then
		close()
	end

	local snap = snapshotSelection()
	if #snap == 0 then
		return
	end

	frozenToggleTargets = {}
	for _, target in State.Timeline:GetKeyframeToggleTargets() do
		local key = currentKey(target.key)
		if key then
			table.insert(frozenToggleTargets, { key = key, id = target.id })
		end
	end

	frozenSelection = snap
	frozenBones = snapshotSelectedBones()

	local boneList = State.Timeline and State.Timeline:GetSelectedKeyframesList() or {}
	local hasChannelKfs = State.Timeline
		and State.Timeline.HasAnySelectedChannelKeyframes
		and State.Timeline:HasAnySelectedChannelKeyframes()
	frozenIsChannelOnly = (#boneList == 0) and (hasChannelKfs == true)

	refreshAllOptionStates()
	refreshParametersUI()
	refreshCurveGraph(true)
	updateLabelsForMain()
	positionMenuAtCursor(mainMenuFrame, cursorPos)
	mainMenuFrame.Visible = true
	activeMenuFrame = mainMenuFrame
	opened = true
	openedAt = os.clock()
	watchSelection()
end

local function openSecondary(cursorPos)
	if BlenderEdit.blocked() then
		return
	end

	if not secondaryMenuFrame then
		return
	end

	if opened then
		close()
	end

	frozenInsertTarget = State.Timeline and State.Timeline:KeyframeTargetAtPosition(cursorPos)
	frozenSelection = {}
	frozenBones = snapshotSelectedBones()

	refreshAllOptionStates()
	updateLabelsForSecondary()
	positionMenuAtCursor(secondaryMenuFrame, cursorPos)
	secondaryMenuFrame.Visible = true
	activeMenuFrame = secondaryMenuFrame
	opened = true
	openedAt = os.clock()
	watchSelection()
end

local function bindActionButtons(buttonRefs, actions)
	for parentName, action in pairs(actions) do
		local btn = buttonRefs[parentName]
		if btn and btn:IsA("GuiButton") then
			btn.MouseButton1Click:Connect(function()
				action()
				close()
			end)
		end
	end
end

local GraphCurves = require("GraphCurves")

local function editEasingTargets(mutate, handleOnly)
	for _, target in frozenToggleTargets do
		local key = currentKey(target.key)
		if key then
			target.key = key
			local bucket = State.Timeline:GetState().Keyframes[key.Motor]
			if target.id then
				ChannelEasing.edit(key, target.id, mutate, bucket, handleOnly)
			else
				ChannelEasing.editAll(key, mutate, bucket, handleOnly)
			end
		end
	end
end

local function snapshotKeyDataEasing(kd)
	local snap = {
		Channels = GraphCurves.clone(kd.Channels),
		GraphCurves = GraphCurves.clone(kd.GraphCurves),
		HandleType = kd.HandleType,
		EasingStyle = kd.EasingStyle,
		EasingDirection = kd.EasingDirection,
		Overshoot = kd.Overshoot,
		Amplitude = kd.Amplitude,
		Period = kd.Period,
	}
	if kd.BezierPoints then
		snap.BezierPoints = {
			kd.BezierPoints[1],
			kd.BezierPoints[2],
			kd.BezierPoints[3],
			kd.BezierPoints[4],
		}
	end

	return snap
end

local function applyKeyDataEasingSnapshot(kd, snap)
	local bucket = State.Timeline and State.Timeline:GetState().Keyframes[kd.Motor]
	if bucket and bucket[kd.Frame] ~= kd then
		kd = bucket[kd.Frame]
		if not kd then
			return
		end
	end

	kd.GraphCurves = GraphCurves.clone(snap.GraphCurves)
	kd.Channels = GraphCurves.clone(snap.Channels)
	if State.Timeline then
		State.Timeline:GetState()._motorUniform[kd.Motor] = nil
	end

	kd.HandleType = snap.HandleType
	kd.EasingStyle = snap.EasingStyle
	kd.EasingDirection = snap.EasingDirection
	kd.Overshoot = snap.Overshoot
	kd.Amplitude = snap.Amplitude
	kd.Period = snap.Period
	if snap.BezierPoints then
		kd.BezierPoints = {
			snap.BezierPoints[1],
			snap.BezierPoints[2],
			snap.BezierPoints[3],
			snap.BezierPoints[4],
		}
	else
		kd.BezierPoints = nil
	end
end

local function refreshAnimationAfterEasingChange()
	local Timeline = State.Timeline
	if not Timeline then
		return
	end

	local tl = Timeline:GetState()
	for _, key in frozenSelection or {} do
		tl._motorUniform[key.Motor] = nil
	end

	for _, bucket in pairs(tl.Keyframes) do
		GraphCurves.invalidate(bucket)
	end

	if State.GraphEditor then
		State.GraphEditor.invalidate()
	end

	if Timeline.RefreshAllKeyframeVisuals then
		Timeline:RefreshAllKeyframeVisuals()
	end

	if State.currentRig and Timeline.GetState and Timeline.ApplyPoseAtTime then
		local tl = Timeline:GetState()
		if tl and tl.CurrentTime then
			Timeline:ApplyPoseAtTime(State.currentRig, tl.CurrentTime)
		end
	end

	motionPath.markDirty()
end

local PARAM_LAYOUTS = {
	Bezier = {
		{ title = "X2:", key = "BezierX2" },
		{ title = "Y2:", key = "BezierY2" },
		{ title = "Y1:", key = "BezierY1" },
		{ title = "X1:", key = "BezierX1" },
	},
	Back = {
		{ title = "Overshoot:", key = "Overshoot" },
	},
	Elastic = {
		{ title = "Amplitude:", key = "Amplitude" },
		{ title = "Period:", key = "Period" },
	},
}

local DEFAULT_OVERSHOOT = 1.70158
local DEFAULT_AMPLITUDE = 1
local DEFAULT_PERIOD = 0.3

local function getDefaultBezierPoints()
	local bp = Defaults.BezierPoints or { 0.42, 0, 0.58, 1 }
	return { bp[1], bp[2], bp[3], bp[4] }
end

local function getParamValue(kd, key)
	if key == "BezierX1" then
		return (kd.BezierPoints and kd.BezierPoints[1]) or getDefaultBezierPoints()[1]
	elseif key == "BezierY1" then
		return (kd.BezierPoints and kd.BezierPoints[2]) or getDefaultBezierPoints()[2]
	elseif key == "BezierX2" then
		return (kd.BezierPoints and kd.BezierPoints[3]) or getDefaultBezierPoints()[3]
	elseif key == "BezierY2" then
		return (kd.BezierPoints and kd.BezierPoints[4]) or getDefaultBezierPoints()[4]
	elseif key == "Overshoot" then
		return kd.Overshoot or DEFAULT_OVERSHOOT
	elseif key == "Amplitude" then
		return kd.Amplitude or DEFAULT_AMPLITUDE
	elseif key == "Period" then
		return kd.Period or DEFAULT_PERIOD
	end

	return 0
end

local function setParamValue(kd, key, value)
	if key == "BezierX1" or key == "BezierY1" or key == "BezierX2" or key == "BezierY2" then
		kd.BezierPoints = kd.BezierPoints or getDefaultBezierPoints()
		local i = (key == "BezierX1") and 1
			or (key == "BezierY1") and 2
			or (key == "BezierX2") and 3
			or 4
		kd.BezierPoints[i] = value
	elseif key == "Overshoot" then
		kd.Overshoot = value
	elseif key == "Amplitude" then
		kd.Amplitude = value
	elseif key == "Period" then
		kd.Period = value
	end
end

local function formatParamNumber(v)
	if v == nil then
		return ""
	end

	if v == math.floor(v) and math.abs(v) < 1e6 then
		return tostring(math.floor(v))
	end

	local s = string.format("%.3f", v)
	s = string.gsub(s, "(%..-)0+$", "%1")
	s = string.gsub(s, "%.$", "")
	return s
end

refreshParametersUI = function()
	if not parametersFrame then
		return
	end

	local source = getEffectiveCurveSource()
	local style = resolveSelectedOptionForSubMenu("InterpolationMode")
	local layout = PARAM_LAYOUTS[style]
	if resetBezierButton then resetBezierButton.Visible = style == "Bezier" end

	if parametersEmptyLabel then
		parametersEmptyLabel.Visible = (layout == nil)
		parametersEmptyLabel.Text = source
				and source._MixedFields
				and source._MixedFields.EasingStyle
				and "Mixed easing styles"
			or parametersEmptyText
			or ""
	end

	for i, slot in ipairs(paramSlots) do
		local entry = layout and layout[i] or nil
		slot._entry = entry
		slot.frame.Visible = (entry ~= nil)
		if entry then
			local title = slot.frame:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.Text = entry.title
			end

			local input = slot.frame:FindFirstChild("ValueInput")
			if input and input:IsA("TextBox") and not input:IsFocused() then
				local v = source and getParamValue(source, entry.key) or 0
				local field = entry.key:sub(1, 6) == "Bezier" and "BezierPoints" or entry.key
				input.Text = source and source._MixedFields and source._MixedFields[field] and ""
					or formatParamNumber(v)
			end
		end
	end

	if style == "Bezier" and not (source._MixedFields and source._MixedFields.BezierPoints) then
		CurveGraph.setHandlesVisible(true)
		local x1 = source and getParamValue(source, "BezierX1") or getDefaultBezierPoints()[1]
		local y1 = source and getParamValue(source, "BezierY1") or getDefaultBezierPoints()[2]
		local x2 = source and getParamValue(source, "BezierX2") or getDefaultBezierPoints()[3]
		local y2 = source and getParamValue(source, "BezierY2") or getDefaultBezierPoints()[4]
		CurveGraph.setHandlePositions(x1, y1, x2, y2)
	else
		CurveGraph.setHandlesVisible(false)
	end
end

local function snapshotsDiffer(before, after)
	return not ChannelEasing.equal(before, after)
end

local function recordParameterHistory(before, after, description)
	local History = require("History")
	History.record(function()
		for kd, snap in pairs(before) do
			applyKeyDataEasingSnapshot(kd, snap)
		end

		refreshAllOptionStates()
		refreshParametersUI()
		refreshCurveGraph(false)
		refreshAnimationAfterEasingChange()
	end, function()
		for kd, snap in pairs(after) do
			applyKeyDataEasingSnapshot(kd, snap)
		end

		refreshAllOptionStates()
		refreshParametersUI()
		refreshCurveGraph(false)
		refreshAnimationAfterEasingChange()
	end, description, nil)
end

function KeyframeMenu.resetBezier()
    if not opened then return end
    if editingDefaults then
        setCurveSetting("BezierPoints", getDefaultBezierPoints())
        defaultCurveDraft = curveSettings()
    else
        if not frozenSelection or #frozenSelection == 0 then return end
        local before, after = {}, {}
        for _, kd in frozenSelection do before[kd] = snapshotKeyDataEasing(kd) end
        editEasingTargets(function(kd)
            if Easing.styleName(kd.EasingStyle or Defaults.EasingStyle) == "Bezier" then kd.BezierPoints = getDefaultBezierPoints() end
        end)
        for _, kd in frozenSelection do after[kd] = snapshotKeyDataEasing(kd) end
        if snapshotsDiffer(before, after) then
            State.currentProjectSaved = false
            recordParameterHistory(before, after, "Reset Bezier parameters")
        end
    end
    refreshParametersUI()
    refreshCurveGraph(true)
    if not editingDefaults then refreshAnimationAfterEasingChange() end
end

local function onBezierHandleChange(phase, idx, gx, gy)
	if phase == "begin" then
		handleDragging = true
	elseif phase == "end" then
		handleDragging = false
	end

	if not opened then
		return
	end

	if editingDefaults then
		defaultCurveDraft = defaultCurveDraft or curveSettings()
		if defaultCurveDraft.EasingStyle ~= "Bezier" then
			return
		end

		if phase == "drag" then
			setParamValue(defaultCurveDraft, idx == 1 and "BezierX1" or "BezierX2", gx)
			setParamValue(defaultCurveDraft, idx == 1 and "BezierY1" or "BezierY2", gy)
			refreshParametersUI()
			refreshCurveGraph(true)
		elseif phase == "end" then
			setCurveSetting("BezierPoints", defaultCurveDraft.BezierPoints)
			defaultCurveDraft = curveSettings()
			refreshParametersUI()
			refreshCurveGraph(true)
		end

		return
	end

	if not frozenSelection or #frozenSelection == 0 then
		return
	end

	local source = getEffectiveCurveSource()
	local style = asString((source and source.EasingStyle) or Defaults.EasingStyle)
	if style ~= "Bezier" then
		return
	end

	if phase == "begin" then
		pendingDragSnapshots = {}
		for _, kd in ipairs(frozenSelection) do
			pendingDragSnapshots[kd] = snapshotKeyDataEasing(kd)
		end
	elseif phase == "drag" then
		local xKey = (idx == 1) and "BezierX1" or "BezierX2"
		local yKey = (idx == 1) and "BezierY1" or "BezierY2"
		editEasingTargets(function(kd)
			if (asString(kd.EasingStyle) or Defaults.EasingStyle) == "Bezier" then
				setParamValue(kd, xKey, gx)
				setParamValue(kd, yKey, gy)
			end
		end)
		State.currentProjectSaved = false
		refreshParametersUI()
		refreshCurveGraph(true)
		refreshAnimationAfterEasingChange()
	elseif phase == "end" then
		if pendingDragSnapshots then
			local before = pendingDragSnapshots
			pendingDragSnapshots = nil
			local after = {}
			for kd in pairs(before) do
				after[kd] = snapshotKeyDataEasing(kd)
			end

			if snapshotsDiffer(before, after) then
				recordParameterHistory(before, after, "Drag Bezier handle")
			end
		end
	end
end

local function applyTextBoxValue(slotEntry, newValue)
	if not slotEntry then
		return
	end

	if editingDefaults then
		local draft = curveSettings()
		setParamValue(draft, slotEntry.key, newValue)
		local field = slotEntry.key:sub(1, 6) == "Bezier" and "BezierPoints" or slotEntry.key
		setCurveSetting(field, draft[field])
		defaultCurveDraft = curveSettings()
		refreshParametersUI()
		refreshCurveGraph(true)
		return
	end

	if not frozenSelection or #frozenSelection == 0 then
		return
	end

	local before = {}
	for _, kd in ipairs(frozenSelection) do
		before[kd] = snapshotKeyDataEasing(kd)
	end

	editEasingTargets(function(kd)
		setParamValue(kd, slotEntry.key, newValue)
	end)

	local after = {}
	for _, kd in ipairs(frozenSelection) do
		after[kd] = snapshotKeyDataEasing(kd)
	end

	if not snapshotsDiffer(before, after) then
		return
	end

	State.currentProjectSaved = false
	refreshParametersUI()
	refreshCurveGraph(true)
	refreshAnimationAfterEasingChange()

	if snapshotsDiffer(before, after) then
		recordParameterHistory(before, after, "Edit " .. slotEntry.title:gsub(":", ""))
	end
end

local function applyOptionToFrozenSelection(subMenuName, optionName)
	if subMenuName == "InterpolationMode" and optionName == "Confirm" then
		return
	end

	if editingDefaults then
		local cfg = DropdownConfigs[subMenuName]
		local row = cfg and cfg.rowsById and cfg.rowsById[optionName]
		local field, value
		if row and row.apply then
			field, value = row.apply.field, row.apply.value
		elseif subMenuName == "InterpolationMode" then
			field, value = "EasingStyle", easingToApplyForOption(optionName)
		end

		if field and setCurveSetting(field, value) then
			defaultCurveDraft = curveSettings()
			refreshAllOptionStates()
			refreshParametersUI()
			refreshCurveGraph(true)
		end

		return
	end

	local kfs = frozenSelection
	if not kfs or #kfs == 0 then
		return
	end

	local before = {}
	for _, kd in ipairs(kfs) do
		before[kd] = snapshotKeyDataEasing(kd)
	end

	local cfg = DropdownConfigs[subMenuName]
	local rowDef = cfg and cfg.rowsById and cfg.rowsById[optionName]

	editEasingTargets(function(kd)
		if rowDef and rowDef.apply then
			ChannelEasing.setOption(kd, rowDef.apply.field, rowDef.apply.value)
		elseif subMenuName == "InterpolationMode" then
			if optionName == "Confirm" then
			else
				kd.EasingStyle = easingToApplyForOption(optionName)
			end
		end
	end, subMenuName == "HandleType")
	local after = {}
	for _, kd in ipairs(kfs) do
		after[kd] = snapshotKeyDataEasing(kd)
	end

	if not snapshotsDiffer(before, after) then
		refreshAllOptionStates()
		refreshParametersUI()
		refreshCurveGraph(true)
		return
	end

	State.currentProjectSaved = false
	refreshAllOptionStates()
	refreshParametersUI()
	refreshCurveGraph(false)
	refreshAnimationAfterEasingChange()

	local History = require("History")
	History.record(function()
		for kd, snap in pairs(before) do
			applyKeyDataEasingSnapshot(kd, snap)
		end

		refreshAllOptionStates()
		refreshParametersUI()
		refreshCurveGraph(false)
		refreshAnimationAfterEasingChange()
	end, function()
		for kd, snap in pairs(after) do
			applyKeyDataEasingSnapshot(kd, snap)
		end

		refreshAllOptionStates()
		refreshParametersUI()
		refreshCurveGraph(false)
		refreshAnimationAfterEasingChange()
	end, "Change " .. subMenuName, nil)
end

function KeyframeMenu.init(refs)
	if mainMenuFrame then
		return
	end

	local dropdownsFolder = refs
		and (refs.DropdownsFolder or (refs.MenuFrame and refs.MenuFrame.Parent))
	if not dropdownsFolder then
		return
	end

	local template = dropdownsFolder:FindFirstChild("DropdownTemplate")
	if template then
		template.Visible = false
		for name, cfg in pairs(DropdownConfigs) do
			if typeof(cfg) == "table" and cfg.rows and not cfg.menubar then
				local existing = dropdownsFolder:FindFirstChild(name)
				if existing then
					existing:Destroy()
				end

				local built = DropdownBuilder.build(template, name, cfg)
				if built then
					built.Parent = dropdownsFolder
					if cfg.main then
						mainMenuFrame = built
					elseif cfg.primary then
						secondaryMenuFrame = built
					elseif cfg.offset then
						subFrameOffsets[built] = Vector2.new(cfg.offset.x, cfg.offset.y)
					end
				end
			end
		end
	end

	if not mainMenuFrame then
		mainMenuFrame = (refs and refs.MenuFrame) or dropdownsFolder:FindFirstChild("MainSelection")
	end

	if not mainMenuFrame then
		return
	end

	if not secondaryMenuFrame then
		secondaryMenuFrame = refs and refs.SecondaryMenuFrame or nil
	end

	if DropdownConfigs._designOffsets then
		for name, off in pairs(DropdownConfigs._designOffsets) do
			local designFrame = dropdownsFolder:FindFirstChild(name)
			if designFrame then
				subFrameOffsets[designFrame] = Vector2.new(off.x, off.y)
			end
		end
	end

	for _, menu in dropdownsFolder:GetChildren() do
		if menu:IsA("GuiObject") then
			menu.ZIndex = PRIMARY_MENU_NAMES[menu.Name] and 70 or 71
		end
	end

	if template then
		defaultMenuFrame = DropdownBuilder.build(template, "DefaultSelection", {
			width = 145,
			rows = {
				DropdownConfigs.MainSelection.rows[1],
				DropdownConfigs.MainSelection.rows[2],
				DropdownConfigs.MainSelection.rows[3],
			},
		})
		defaultMenuFrame.Parent = dropdownsFolder
		defaultMenuFrame.ZIndex = 70
		defaultMenuFrame.Visible = false
	end

	precomputeOffsets(dropdownsFolder)

	local interpolationModeFrame = dropdownsFolder:FindFirstChild("InterpolationMode")
	if interpolationModeFrame then
		local graphHost = interpolationModeFrame:FindFirstChild("Content")
		local paramGraph = graphHost and graphHost:FindFirstChild("ParameterGraph")
		local graphOuter = paramGraph and paramGraph:FindFirstChild("Graph")
		local graphInner = graphOuter and graphOuter:FindFirstChild("Graph")
		curvePreviewFrame = graphOuter
		if graphInner and graphInner:IsA("Frame") then
			CurveGraph.init(graphInner)
			CurveGraph.setTargetImmediate(nil)

			local circles = {}
			for _, child in ipairs(graphInner:GetChildren()) do
				if child:IsA("Frame") and child.Name == "Circle" then
					table.insert(circles, child)
				end
			end

			if #circles >= 2 then
				bezierHandle1 = circles[1]
				bezierHandle2 = circles[2]
				CurveGraph.attachHandles(bezierHandle1, bezierHandle2, onBezierHandleChange)
			end

			CurveGraph.setHandlesVisible(false)
		end

		local paramsFrame = paramGraph and paramGraph:FindFirstChild("Parameters")
		local cc = paramsFrame and paramsFrame:FindFirstChild("ContentContainer")
		parametersFrame = paramsFrame
		local paramsHeader = paramsFrame and paramsFrame:FindFirstChild("Header")
		if paramsHeader then
			local label
			resetBezierButton, label = require("Tool").button(paramsHeader, "ResetBezier", "RESET", UDim2.new(), UDim2.new(0, 46, 1, -4), KeyframeMenu.resetBezier)
			resetBezierButton.AnchorPoint = Vector2.new(0.5, 0.5)
			resetBezierButton.Position = UDim2.new(1, -27, 0.5, 0)
			label.TextSize = 9
			resetBezierButton.Visible = false
		end
		parametersEmptyLabel = paramsHeader and paramsHeader:FindFirstChild("Empty") or nil
		if parametersEmptyLabel then
			parametersEmptyText = parametersEmptyLabel.Text
			parametersEmptyLabel.Visible = false
		end

		if cc then
			for _, child in ipairs(cc:GetChildren()) do
				if child:IsA("Frame") and child.Name == "ParameterSlot" then
					table.insert(paramSlots, { frame = child, _entry = nil })
				end
			end

			for _, slot in ipairs(paramSlots) do
				local input = slot.frame:FindFirstChild("ValueInput")
				if input and input:IsA("TextBox") then
					require("NumericInput").connect(input, { step = 0.05 }, function()
						local entry = slot._entry
						if not entry then
							refreshParametersUI()
							return
						end

						local val = tonumber(input.Text)
						if not val then
							refreshParametersUI()
							return
						end

						applyTextBoxValue(entry, val)
					end)
				end
			end
		end
	end

	mainMenuFrame.Visible = false
	mainMenuFrame.AnchorPoint = Vector2.new(0, 0)

	if secondaryMenuFrame then
		secondaryMenuFrame.Visible = false
		secondaryMenuFrame.AnchorPoint = Vector2.new(0, 0)
	end

	local screenGui = dropdownsFolder:FindFirstAncestorWhichIsA("LayerCollector")
	if screenGui then
		uiScale = screenGui:FindFirstChildOfClass("UIScale")
	end

	local function onOptionClick(subMenuName, optionName, btn)
		if subMenuName == "DefaultInterpolation" then
			subMenuName = "InterpolationMode"
		end

		if subMenuName == "InterpolationMode" and optionName == "Confirm" then
			if directInterpolation then
				close()
				return
			end

			if curvePicker then
				local callback, values = curvePicker.callback, curveSettings()
				close()
				callback(values)
				return
			end

			local subFrame = findContainingSubFrame(btn)
			closeSubFrame(subFrame)
			return
		end

		applyOptionToFrozenSelection(subMenuName, optionName)
	end

	valuePanel = KeyframeValues.build(template, dropdownsFolder, function()
		return frozenSelection or {}
	end)
	subFrameOffsets[valuePanel.frame] = Vector2.zero
	wireAllButtons(mainMenuFrame, mainButtonRefs, onOptionClick)
	if defaultMenuFrame then
		wireAllButtons(defaultMenuFrame, {}, onOptionClick)
	end

	local values = mainButtonRefs.Values
	if values then
		cameraValueRow = values:Clone()
		cameraValueRow.Name = "CameraFOV"
		cameraValueRow.Visible = false
		cameraValueRow.Title.Text = "FOV"
		cameraValueRow.Title.Size = UDim2.new(0.38, 0, 0.5, 0)
		cameraValueRow.Icon.Image = CameraRig.ICON
		local arrow = cameraValueRow:FindFirstChild("Arrow")
		if arrow then
			arrow:Destroy()
		end

		cameraValueRow.Parent = values.Parent
		local background = Instance.new("Frame")
		background.Name = "Number"
		background.Size, background.Position = UDim2.new(0.43, -4, 1, -4), UDim2.new(0.57, 0, 0, 2)
		background.BorderSizePixel, background.ZIndex = 0, cameraValueRow.ZIndex + 1
		background:SetAttribute("ThemeBg", "TopBtn")
		background.Parent = cameraValueRow
		local outline = Instance.new("UIStroke")
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline:SetAttribute("ThemeStrk", "Strk")
		outline.Parent = background
		cameraValueField = Instance.new("TextBox")
		cameraValueField.Name = "Value"
		cameraValueField.BackgroundTransparency = 1
		cameraValueField.Size, cameraValueField.Position =
			UDim2.new(1, -6, 1, 0), UDim2.fromOffset(3, 0)
		cameraValueField.Text, cameraValueField.ClearTextOnFocus = "70", false
		cameraValueField.FontFace, cameraValueField.TextSize = values.Title.FontFace, 12
		cameraValueField.ZIndex = background.ZIndex + 1
		cameraValueField:SetAttribute("ThemeTxt", "Txt")
		cameraValueField.Parent = background
		local editing
		cameraValueField.Focused:Connect(function()
			editing = frozenSelection and table.clone(frozenSelection)
		end)
		require("NumericInput").connect(cameraValueField, { step = 1 }, function()
			local value = tonumber(cameraValueField.Text)
			if value and editing then
				CameraControls.edit(editing, value)
				close()
			end

			editing = nil
		end)
		wireButton(cameraValueRow)
		Theme.applyTree(cameraValueRow)
	end

	if secondaryMenuFrame then
		wireAllButtons(secondaryMenuFrame, secondaryButtonRefs, onOptionClick)
	end

	for _, child in ipairs(dropdownsFolder:GetChildren()) do
		if
			child:IsA("Frame")
			and not PRIMARY_MENU_NAMES[child.Name]
			and not IGNORED_MENU_NAMES[child.Name]
		then
			wireAllButtons(child, nil, onOptionClick)
		end
	end

	local Timeline = State.Timeline

	local function actionCopy()
		if not Timeline or not Timeline.CopySelectedKeyframes then
			return
		end

		const kfs = frozenSelection
		if
			kfs
			and #kfs > 0
			and not frozenIsChannelOnly
			and #Timeline:GetSelectedKeyframesList() == 0
			and not Timeline:HasAnySelectedChannelKeyframes()
		then
			Timeline:SetSelectedKeyframes(kfs)
		end

		Timeline:CopySelectedKeyframes()
	end

	local function actionPaste()
		if Timeline and Timeline.PasteKeyframes then
			Timeline:PasteKeyframes()
		end
	end

	local function actionPasteFlipped()
		if Timeline and Timeline.PasteKeyframesFlipped then
			Timeline:PasteKeyframesFlipped()
		end
	end

	local function actionDeleteSelected()
		local kfs = frozenSelection
		if not kfs or #kfs == 0 then
			return
		end

		if not frozenIsChannelOnly and Timeline and Timeline.SetSelectedKeyframes then
			Timeline:SetSelectedKeyframes(kfs)
		end

		if Timeline and Timeline.DeleteSelectedKeyframes then
			Timeline:DeleteSelectedKeyframes()
		end
	end

	local function actionInsertKeyframe()
		if Timeline then
			Timeline:InsertKeyframeAtTarget(frozenInsertTarget)
		end
	end

	local function actionToggleKeyframes()
		if Timeline then
			Timeline:ToggleKeyframesEnabled(frozenToggleTargets)
		end
	end

	local ACTION_FUNCTIONS = {
		StretchFrames = function()
			require("fill").open("stretch")
		end,
		FillFrames = function()
			require("fill").open("fill")
		end,
		GroupKeyframes = function()
			if Timeline then
				Timeline:GroupSelectedKeyframes()
			end
		end,
		UngroupKeyframes = function()
			if Timeline then
				Timeline:UngroupSelectedKeyframes()
			end
		end,
		UngroupAllKeyframes = function()
			if Timeline then
				Timeline:UngroupSelectedKeyframes(true)
			end
		end,
		ToggleKey = actionToggleKeyframes,
		Copy = actionCopy,
		Paste = actionPaste,
		PasteFlipped = actionPasteFlipped,
		InsertKey = actionInsertKeyframe,
		DeleteKey = actionDeleteSelected,
	}

	local function bindConfigActions(menuFrame, buttonRefs, fallback)
		local cfg = menuFrame and DropdownConfigs[menuFrame.Name]
		if cfg and cfg.rows then
			local actionMap = {}
			for _, row in ipairs(cfg.rows) do
				if typeof(row) == "table" and row.action and ACTION_FUNCTIONS[row.action] then
					actionMap[row.id] = ACTION_FUNCTIONS[row.action]
				end
			end

			bindActionButtons(buttonRefs, actionMap)
		elseif fallback then
			bindActionButtons(buttonRefs, fallback)
		end
	end

	bindConfigActions(mainMenuFrame, mainButtonRefs, {
		ToggleKey = actionToggleKeyframes,
		Copy = actionCopy,
		Paste = actionPaste,
		PasteFlipped = actionPasteFlipped,
		InsertKey = actionInsertKeyframe,
		DeleteKey = actionDeleteSelected,
	})

	if secondaryMenuFrame then
		bindConfigActions(secondaryMenuFrame, secondaryButtonRefs, {
			InsertKey = actionInsertKeyframe,
			Paste = actionPaste,
			PasteFlipped = actionPasteFlipped,
		})
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input)
			if not opened then
				return
			end

			if (os.clock() - openedAt) < OPEN_DEBOUNCE then
				return
			end

			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local mp = UserInputService:GetMouseLocation()

				if curvePicker and curvePicker.button then
					local b = curvePicker.button
					local p, s = b.AbsolutePosition, b.AbsoluteSize
					if mp.X >= p.X and mp.Y >= p.Y and mp.X <= p.X + s.X and mp.Y <= p.Y + s.Y then
						return
					end
				end

				if not isMouseInsideMenuOrSubFrames(mp) then
					close()
				end
			elseif input.UserInputType == Enum.UserInputType.Keyboard then
				if Shortcuts.matches("Cancel", input) then
					close()
				end
			end
		end)
	)
	table.insert(
		connections,
		mainMenuFrame.Destroying:Connect(function()
			close(false)
		end)
	)
end

local function curvePickerHotZone(mp, p, s, b, bs)
	local insidePanel = mp.X >= p.X and mp.Y >= p.Y and mp.X <= p.X + s.X and mp.Y <= p.Y + s.Y
	local insideRow = mp.X >= math.min(b.X, p.X + s.X) - 6
		and mp.X <= math.max(b.X + bs.X, p.X) + 6
		and mp.Y >= b.Y - 6
		and mp.Y <= b.Y + bs.Y + 6
	return insidePanel or insideRow
end

function KeyframeMenu.openCurvePicker(owner, values, callback, anchor, button, options)
	if not mainMenuFrame or not owner or not owner.Parent or BlenderEdit.blocked() then
		return false
	end

	close()
	local frame = mainMenuFrame.Parent:FindFirstChild("InterpolationMode")
	if not frame then
		return false
	end

	curvePicker = {
		owner = owner,
		button = button,
		values = require("GraphCurves").clone(values),
		callback = callback,
		frame = frame,
		parent = frame.Parent,
		position = frame.Position,
		anchor = frame.AnchorPoint,
		connections = {},
	}
	editingDefaults = true
	defaultCurveDraft = curveSettings()
	frozenSelection = {}
	frozenToggleTargets = {}
	if anchor and button then
		frame.Parent = options and options.host or anchor
		frame.AnchorPoint = Vector2.zero
		if options and options.graph then
			local zindexes = {}
			curvePicker.zindexes = zindexes
			for _, object in { frame, table.unpack(frame:GetDescendants()) } do
				if object:IsA("GuiObject") then
					zindexes[object] = object.ZIndex
					object.ZIndex += 250
				end
			end

			local function position()
				if not curvePicker or curvePicker.owner ~= owner then
					return
				end

				local host = options.host
				local width = host.Size.X.Offset
					+ host.Size.X.Scale * (host.Parent and host.Parent.AbsoluteSize.X or 0)
				local scale = host.AbsoluteSize.X / math.max(width, 1)
				local p = (anchor.AbsolutePosition - host.AbsolutePosition) / scale
				local size, available = frame.AbsoluteSize / scale, host.AbsoluteSize / scale
				local x = p.X + anchor.AbsoluteSize.X / scale
				if x + size.X > available.X then
					x = p.X - size.X
				end

				local y = (button.AbsolutePosition.Y - host.AbsolutePosition.Y) / scale
				frame.Position = UDim2.fromOffset(
					math.clamp(x, 0, math.max(0, available.X - size.X)),
					math.clamp(y, 0, math.max(0, available.Y - size.Y))
				)
			end

			for _, object in { frame, options.host } do
				table.insert(
					curvePicker.connections,
					object:GetPropertyChangedSignal("AbsoluteSize"):Connect(position)
				)
			end

			position()
			task.defer(position)
		else
			frame.Position = UDim2.new(1, 0, 0, button.Position.Y.Offset)
		end
	else
		frame.Parent = owner
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
	end

	activeMenuFrame = frame
	frame.Visible = true
	opened = true
	openedAt = os.clock()
	table.insert(
		curvePicker.connections,
		owner.Destroying:Connect(function()
			close(false)
		end)
	)
	if anchor and button then
		local leftAt, pinned = nil, false
		table.insert(
			curvePicker.connections,
			RunService.Heartbeat:Connect(function()
				if not anchor.Parent or not anchor.Visible then
					close()
					return
				end

				local mp = options and options.mousePosition and options.mousePosition()
					or UserInputService:GetMouseLocation()
				local p, s = frame.AbsolutePosition, frame.AbsoluteSize
				local b, bs = button.AbsolutePosition, button.AbsoluteSize
				local focused = UserInputService:GetFocusedTextBox()
				if
					curvePickerHotZone(mp, p, s, b, bs)
					or focused and focused:IsDescendantOf(frame)
				then
					leftAt = nil
					pinned = pointerHeld()
				elseif pinned or handleDragging then
					leftAt = nil
				else
					leftAt = leftAt or os.clock()
					if os.clock() - leftAt > 0.18 then
						close()
					end
				end
			end)
		)
	end

	refreshParametersUI()
	refreshCurveGraph(true)
	refreshAllOptionStates()
	return true
end

function KeyframeMenu.curvePickerFrame(owner)
	return curvePicker and curvePicker.owner == owner and curvePicker.frame or nil
end

function KeyframeMenu.closeCurvePicker(owner)
	if curvePicker and curvePicker.owner == owner then
		close()
		return true
	end

	return false
end

function KeyframeMenu.isCurvePickerOpen(owner)
	return curvePicker ~= nil and curvePicker.owner == owner
end

function KeyframeMenu.openInterpolation()
	local timeline = State.Timeline
	if
		not timeline
		or not require("UI").isAnimatorActive()
		or timeline:IsExportLocked()
		or State.PhysicsSimulating
		or UserInputService:GetFocusedTextBox()
	then
		return
	end

	local raw = timeline:GetState()
	if State.LoadingProject or raw.Playing or require("RawState").KeyframeTransform.active then
		return
	end

	open(UserInputService:GetMouseLocation())
	if not opened or not frozenSelection or #frozenSelection == 0 then
		return
	end

	local frame = mainMenuFrame.Parent:FindFirstChild("InterpolationMode")
	if not frame then
		close()
		return
	end

	mainMenuFrame.Visible = false
	positionMenuAtCursor(frame, UserInputService:GetMouseLocation())
	frame.Visible = true
	activeMenuFrame = frame
	directInterpolation = true
end

function KeyframeMenu.openDefaults()
	if not defaultMenuFrame or BlenderEdit.blocked() then
		return
	end

	close()
	editingDefaults = true
	defaultCurveDraft = curveSettings()
	frozenSelection = {}
	frozenToggleTargets = {}
	refreshParametersUI()
	refreshCurveGraph(true)
	refreshAllOptionStates()
	positionMenuAtCursor(defaultMenuFrame, UserInputService:GetMouseLocation())
	activeMenuFrame = defaultMenuFrame
	defaultMenuFrame.Visible = true
	opened = true
	openedAt = os.clock()
end

KeyframeMenu.open = open
KeyframeMenu.openSecondary = openSecondary
KeyframeMenu.close = close

function KeyframeMenu.isOpen()
	return opened
end

function KeyframeMenu.getSelection()
	return frozenSelection or {}
end

return KeyframeMenu
