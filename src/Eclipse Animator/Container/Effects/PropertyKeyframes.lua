--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Motion = require("Motion")
local Properties = require("Properties")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("RawState")
local TimelineState = State.Timeline
local TimelineConfig = State.Config
local PlayheadDrag = State.PlayheadDrag
local KeyframeDrag = State.KeyframeDrag
local SelectionState = State.Selection
local KEYFRAME_DEFAULT_COLOR = State.Colors.KEYFRAME_DEFAULT_COLOR
local KEYFRAME_HOVER_COLOR = State.Colors.KEYFRAME_HOVER_COLOR
local KEYFRAME_SELECTED_COLOR = State.Colors.KEYFRAME_SELECTED_COLOR
local LOOP_ACTIVE_COLOR = State.Colors.LOOP_ACTIVE_COLOR
local LOOP_INACTIVE_COLOR = State.Colors.LOOP_INACTIVE_COLOR

local function refreshSelectionFilter(timeline)
	local app = require("State")
	local frame = timeline.refs and timeline.refs.AnimatorFrame
	local gui = timeline.refs and timeline.refs.PluginGui
	if
		frame
		and frame.Visible
		and (not gui or gui.Enabled)
		and not app.LoadingProject
		and (next(TimelineState.SelectedKeyframes) or next(TimelineState.SelectedChannelKeyframes))
	then
		if app.WorkspaceSelection and app.setWorkspaceSelection then
			app.setWorkspaceSelection(false)
		end

		local selection = game:GetService("Selection")
		if #selection:Get() > 0 then
			local ignore = app.ignoreSelectionChanged
			app.ignoreSelectionChanged = true
			local ok, err = pcall(function()
				selection:Set({})
			end)
			app.ignoreSelectionChanged = ignore
			if not ok then
				error(err, 0)
			end
		end
	end

	if timeline.refs.RefreshSelectionFilter then
		timeline.refs.RefreshSelectionFilter()
	end
end

return function(Timeline)
	function Timeline:IsSelectionModifierDown()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	function Timeline:SelectRigFrame(key)
		if
			not (
				UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
			)
		then
			return false
		end

		if
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		then
			return false
		end

		local app = require("State")
		local owner
		for _, rig in app.getAllRigs() do
			for _, motor in require("Parenting").collectMotors(rig) do
				if motor == key.Motor then
					owner = rig
					break
				end
			end

			if owner then
				break
			end
		end

		if not owner then
			return false
		end

		local toggle = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if not toggle then
			TimelineState.SelectedKeyframes = {}
			TimelineState.SelectedChannelKeyframes = {}
		end

		for _, motor in require("Parenting").collectMotors(owner) do
			local candidate = TimelineState.Keyframes[motor]
				and TimelineState.Keyframes[motor][key.Frame]
			if candidate then
				if toggle and TimelineState.SelectedKeyframes[candidate] then
					TimelineState.SelectedKeyframes[candidate] = nil
					TimelineState.SelectedChannelKeyframes[candidate] = nil
				else
					TimelineState.SelectedKeyframes[candidate] = true
					self:SelectAllChannelsForKeyData(candidate)
				end
			end
		end

		TimelineState.SelectedKeyframe = next(TimelineState.SelectedKeyframes)
			or next(TimelineState.SelectedChannelKeyframes)
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
		return true
	end

	function Timeline:SelectAllKeyframes()
		TimelineState.SelectedKeyframes = {}
		TimelineState.SelectedChannelKeyframes = {}
		TimelineState.SelectedKeyframe = nil
		for motor, bucket in TimelineState.Keyframes do
			if not motor.Parent then
				continue
			end

			for _, keyData in bucket do
				TimelineState.SelectedKeyframes[keyData] = true
				self:SelectAllChannelsForKeyData(keyData)
				if
					not TimelineState.SelectedKeyframe
					or keyData.Frame < TimelineState.SelectedKeyframe.Frame
				then
					TimelineState.SelectedKeyframe = keyData
				end
			end
		end

		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:SetSelectedKeyframe(keyData)
		TimelineState.SelectedKeyframes = {}

		TimelineState.SelectedChannelKeyframes = {}
		if keyData then
			TimelineState.SelectedKeyframes[keyData] = true
		end

		TimelineState.SelectedKeyframe = keyData
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:IsKeyframeSelected(keyData)
		return keyData and TimelineState.SelectedKeyframes[keyData] == true
	end

	function Timeline:ClearSelectedKeyframe()
		self:ClearSelectedKeyframes()
	end

	function Timeline:ClearSelectedKeyframes()
		TimelineState.SelectedKeyframes = {}
		TimelineState.SelectedChannelKeyframes = {}
		TimelineState.SelectedKeyframe = nil
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:IsChannelKeyframeSelected(keyData, channelId)
		if not keyData or not channelId then
			return false
		end

		local entry = TimelineState.SelectedChannelKeyframes[keyData]
		return entry ~= nil and entry[channelId] == true
	end

	function Timeline:HasAnyChannelSelectedForKeyData(keyData)
		if not keyData then
			return false
		end

		local entry = TimelineState.SelectedChannelKeyframes[keyData]
		if not entry then
			return false
		end

		return next(entry) ~= nil
	end

	function Timeline:SetSelectedChannelKeyframe(keyData, channelId)
		TimelineState.SelectedKeyframes = {}
		TimelineState.SelectedChannelKeyframes = {}
		TimelineState.SelectedKeyframe = nil
		if keyData and channelId then
			TimelineState.SelectedChannelKeyframes[keyData] = { [channelId] = true }
			TimelineState.SelectedKeyframe = keyData
		end

		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:AddSelectedChannelKeyframe(keyData, channelId)
		if not keyData or not channelId then
			return
		end

		TimelineState.SelectedChannelKeyframes[keyData] = TimelineState.SelectedChannelKeyframes[keyData]
			or {}
		TimelineState.SelectedChannelKeyframes[keyData][channelId] = true
		TimelineState.SelectedKeyframe = keyData
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:ToggleSelectedChannelKeyframe(keyData, channelId)
		if not keyData or not channelId then
			return
		end

		local entry = TimelineState.SelectedChannelKeyframes[keyData]
		if entry and entry[channelId] then
			TimelineState.SelectedKeyframes[keyData] = nil
			entry[channelId] = nil
			if not next(entry) then
				TimelineState.SelectedChannelKeyframes[keyData] = nil
			end
		else
			TimelineState.SelectedChannelKeyframes[keyData] = entry or {}
			TimelineState.SelectedChannelKeyframes[keyData][channelId] = true
			TimelineState.SelectedKeyframe = keyData
		end

		TimelineState.SelectedKeyframe = next(TimelineState.SelectedKeyframes)
			or next(TimelineState.SelectedChannelKeyframes)
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:SelectAllChannelsForKeyData(keyData)
		if not keyData or Properties.is(keyData.Motor) then
			return
		end

		local entry = {}
		for _, id in ipairs(self:GetChannelIds()) do
			entry[id] = true
		end

		TimelineState.SelectedChannelKeyframes[keyData] = entry
	end

	function Timeline:SetSelectedKeyframes(keyframes)
		TimelineState.SelectedKeyframes = {}

		TimelineState.SelectedChannelKeyframes = {}
		TimelineState.SelectedKeyframe = nil

		if keyframes then
			for _, keyData in ipairs(keyframes) do
				if keyData then
					TimelineState.SelectedKeyframes[keyData] = true
					if not TimelineState.SelectedKeyframe then
						TimelineState.SelectedKeyframe = keyData
					end
				end
			end
		end

		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:AddSelectedKeyframe(keyData)
		if not keyData then
			return
		end

		TimelineState.SelectedKeyframes[keyData] = true
		TimelineState.SelectedKeyframe = keyData
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:ToggleSelectedKeyframe(keyData)
		if not keyData then
			return
		end

		if TimelineState.SelectedKeyframes[keyData] then
			TimelineState.SelectedKeyframes[keyData] = nil
			TimelineState.SelectedChannelKeyframes[keyData] = nil

			if TimelineState.SelectedKeyframe == keyData then
				TimelineState.SelectedKeyframe = nil
				TimelineState.SelectedKeyframe = next(TimelineState.SelectedKeyframes)
					or next(TimelineState.SelectedChannelKeyframes)
			end
		else
			TimelineState.SelectedKeyframes[keyData] = true
			self:SelectAllChannelsForKeyData(keyData)
			TimelineState.SelectedKeyframe = keyData
		end

		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:GetSelectedKeyframesList()
		local list = {}

		for keyData in pairs(TimelineState.SelectedKeyframes) do
			table.insert(list, keyData)
		end

		table.sort(list, function(a, b)
			if a.Frame == b.Frame then
				return tostring(a.Part and a.Part.Name or "")
					< tostring(b.Part and b.Part.Name or "")
			end

			return a.Frame < b.Frame
		end)

		return list
	end

	function Timeline:HasAnySelectedChannelKeyframes()
		for _ in pairs(TimelineState.SelectedChannelKeyframes) do
			return true
		end

		return false
	end

	function Timeline:GetSelectedChannelKeyframesList()
		local list = {}
		for keyData, channels in pairs(TimelineState.SelectedChannelKeyframes) do
			if not TimelineState.SelectedKeyframes[keyData] then
				for channelId in pairs(channels) do
					table.insert(list, { keyData = keyData, channelId = channelId })
				end
			end
		end

		table.sort(list, function(a, b)
			if a.keyData.Frame == b.keyData.Frame then
				return a.channelId < b.channelId
			end

			return a.keyData.Frame < b.keyData.Frame
		end)
		return list
	end

	function Timeline:CopySelectedKeyframes()
		local selected = self:GetSelectedKeyframesList()
		if #selected == 0 and TimelineState.SelectedKeyframe then
			selected = { TimelineState.SelectedKeyframe }
		end

		table.clear(TimelineState.CopiedKeyframes)

		if #selected == 0 then
			return 0
		end

		local baseFrame = selected[1].Frame

		for _, keyData in ipairs(selected) do
			table.insert(TimelineState.CopiedKeyframes, {
				Motor = keyData.Motor,
				Part = keyData.Part,
				FrameOffset = keyData.Frame - baseFrame,
				C0 = keyData.C0,
				PropertyValue = keyData.PropertyValue,
				WorldCFrame = keyData.WorldCFrame,
				MasterWorld = keyData.MasterWorld,
				Parented = keyData.Parented,
				SanitizeName = keyData.SanitizeName,
			})
		end

		return #TimelineState.CopiedKeyframes
	end

	function Timeline:PasteCopiedKeyframesAtCurrentTime()
		if not TimelineState.CopiedKeyframes or #TimelineState.CopiedKeyframes == 0 then
			return 0
		end

		local pastedCount = 0
		local targetBaseFrame = self:TimeToFrame(TimelineState.CurrentTime)
		local maxFrame = self:GetMaxFrame()

		local newlySelected = {}

		for _, copied in ipairs(TimelineState.CopiedKeyframes) do
			if copied.Motor and copied.Part then
				local targetFrame = math.clamp(targetBaseFrame + copied.FrameOffset, 0, maxFrame)
				local bucket = self:GetMotorKeyframeBucket(copied.Motor)

				bucket[targetFrame] = bucket[targetFrame] or {}
				local keyData = bucket[targetFrame]

				keyData.Time = self:FrameToTime(targetFrame)
				keyData.C0 = copied.C0
				keyData.PropertyValue = copied.PropertyValue
				keyData.Position = copied.C0.Position
				keyData.Rotation = copied.C0 - copied.C0.Position
				keyData.Motor = copied.Motor
				keyData.Part = copied.Part
				keyData.Frame = targetFrame
				keyData.SanitizeName = copied.SanitizeName
				keyData.Parented = copied.Parented
				keyData.MasterWorld = copied.MasterWorld

				if copied.Parented == false and copied.WorldCFrame then
					keyData.WorldCFrame = copied.WorldCFrame
				else
					keyData.WorldCFrame = nil
				end

				self:CreateOrUpdateTimelineKeyframeButton(
					copied.Part,
					copied.Motor,
					targetFrame,
					nil,
					copied.SanitizeName
				)

				if bucket[targetFrame] then
					table.insert(newlySelected, bucket[targetFrame])
				end

				pastedCount += 1
			end
		end

		self:SetSelectedKeyframes(newlySelected)
		return pastedCount
	end

	function Timeline:GetTimelinePointFromMouse(mousePos)
		local root = self.refs.Scale or self.refs.KeysRoot
		if not root then
			return Vector2.zero
		end

		return Vector2.new(
			(mousePos.X - root.AbsolutePosition.X) / Motion.scale(root),
			(mousePos.Y - root.AbsolutePosition.Y) / Motion.scale(root)
		)
	end

	function Timeline:EnsureSelectionBox()
		if SelectionState.selectionBox then
			return
		end

		local box = self.refs and self.refs.SelectionBox
		if not box then
			return
		end

		box.AnchorPoint = Vector2.new(0, 0)
		box.Visible = false
		box.Size = UDim2.new(0, 0, 0, 0)
		box.Position = UDim2.new(0, 0, 0, 0)
		box.ZIndex = 50
		SelectionState.selectionBox = box
	end

	function Timeline:HideSelectionBox()
		SelectionState.selectionDragging = false
		if self._selectionScroll then
			self._selectionScroll:Disconnect()
			self._selectionScroll = nil
		end

		self._selectionHitTargets = nil
		self._selectionBoxHits = nil
		self._selectionBoxCounts = nil
		self._selectionBasePoses = nil
		self._selectionBaseChannels = nil
		self._selectionBaseEvents = nil
		self._selectionAdditive = nil
		if SelectionState.selectionBox then
			SelectionState.selectionBox.Visible = false
		end
	end

	function Timeline:UpdateSelectionBox(currentMousePos)
		if SelectionState.selectionDragging and SelectionState.selectionStartMouse then
			local point = Vector2.new(currentMousePos.X, currentMousePos.Y)
			if (point - SelectionState.selectionStartMouse).Magnitude >= 4 then
				self._selectionDragConsumed = true
			end
		end

		if
			not SelectionState.selectionBox
			or not SelectionState.selectionDragging
			or not SelectionState.selectionStartTimelinePoint
		then
			return
		end

		local currentPoint = self:GetTimelinePointFromMouse(currentMousePos)

		local minX = math.min(SelectionState.selectionStartTimelinePoint.X, currentPoint.X)
		local minY = math.min(SelectionState.selectionStartTimelinePoint.Y, currentPoint.Y)
		local maxX = math.max(SelectionState.selectionStartTimelinePoint.X, currentPoint.X)
		local maxY = math.max(SelectionState.selectionStartTimelinePoint.Y, currentPoint.Y)

		SelectionState.selectionBox.Position = UDim2.new(0, minX, 0, minY)
		SelectionState.selectionBox.Size = UDim2.new(0, maxX - minX, 0, maxY - minY)
		SelectionState.selectionBox.Visible = true
	end

	function Timeline:GetSelectionBounds(currentMousePos)
		if not SelectionState.selectionStartTimelinePoint then
			return nil
		end

		local currentPoint = self:GetTimelinePointFromMouse(currentMousePos)

		local minX = math.min(SelectionState.selectionStartTimelinePoint.X, currentPoint.X)
		local minY = math.min(SelectionState.selectionStartTimelinePoint.Y, currentPoint.Y)
		local maxX = math.max(SelectionState.selectionStartTimelinePoint.X, currentPoint.X)
		local maxY = math.max(SelectionState.selectionStartTimelinePoint.Y, currentPoint.Y)

		return minX, minY, maxX, maxY
	end

	function Timeline:GetSelectionHitTargets()
		if self._selectionHitTargets then
			return self._selectionHitTargets
		end

		local targets = {}

		local function add(button, key, lane, group)
			if button and button.Parent then
				table.insert(targets, { button = button, key = key, lane = lane, group = group })
			end
		end

		for _, bucket in TimelineState.Keyframes do
			for _, key in bucket do
				add(key.Button, key)
				for _, button in
					self.GetIKEndMarkerButtons and self:GetIKEndMarkerButtons(key) or {}
				do
					add(button, key)
				end
			end
		end

		for motor, rows in TimelineState.ChannelTracks do
			local bucket = TimelineState.Keyframes[motor]
			if not bucket then
				continue
			end

			for lane, row in rows do
				local container = self:GetTrackKeyframesContainer(row)
				if container then
					for _, child in container:GetChildren() do
						local frame = tonumber(child.Name:match("^ChannelKF_(.+)$"))
						if frame and bucket[frame] and child:IsA("GuiObject") then
							add(child, bucket[frame], lane)
						end
					end
				end
			end
		end

		for _, groups in self._keyGroupBars or {} do
			for _, entry in groups do
				add(entry.bar, nil, nil, entry)
			end
		end

		local Model = require("KeyGroups")
		local Curves = require("GraphCurves")
		for motor, bucket in TimelineState.Keyframes do
			local lanes = { Pose = TimelineState.TrackRows[motor.Part1] }
			for lane, row in TimelineState.ChannelTracks[motor] or {} do
				lanes[lane] = row
			end

			for lane, row in lanes do
				local content = self:GetTrackKeyframesContainer(row)
				if not content then
					continue
				end

				local grouped = {}
				for id, members in Model.collect(bucket, lane) do
					if not (self._expandedKeyGroups and self._expandedKeyGroups[id]) then
						local group = { members = members, lane = lane }
						table.insert(targets, {
							row = content,
							group = group,
							first = members[1].frame,
							last = members[#members].frame,
						})
						for _, member in members do
							grouped[member.key] = true
						end
					end
				end

				for frame, key in bucket do
					if
						not grouped[key]
						and Model.hasLane(key, lane)
						and (lane ~= "Pose" or Curves.hasVisibleKey(bucket, key))
					then
						table.insert(targets, {
							row = content,
							key = key,
							lane = lane ~= "Pose" and lane or nil,
							first = frame,
							last = frame,
						})
					end
				end
			end
		end

		self._selectionHitTargets = targets
		self._selectionBoxHits = nil
		self._selectionBoxCounts = nil
		return targets
	end

	function Timeline:StepSelectionScroll(dt, point)
		if not SelectionState.selectionDragging then
			return
		end

		local viewport = self.refs.KeysRoot or self.refs.TimelineContainer
		local horizontal = self.refs.TimelineContainer
		if not viewport or not horizontal then
			return
		end

		local factor = Motion.scale(horizontal)

		local function speed(value, low, high)
			local band = 18 * factor
			if value < low + band then
				return -math.clamp((low + band - value) / band, 0, 3) * 420
			end

			if value > high - band then
				return math.clamp((value - high + band) / band, 0, 3) * 420
			end

			return 0
		end

		local step = math.clamp(dt or 0, 0, 0.05)
		local dx = speed(
			point.X,
			horizontal.AbsolutePosition.X + 20 * factor,
			horizontal.AbsolutePosition.X + horizontal.AbsoluteSize.X - 20 * factor
		) * step
		if dx ~= 0 then
			self:SetTimelineScroll(TimelineState.ScrollOffset + dx)
		end

		local scroll = self.refs.RigListScroll
		if scroll then
			local dy = speed(
				point.Y,
				viewport.AbsolutePosition.Y,
				viewport.AbsolutePosition.Y + viewport.AbsoluteSize.Y
			) * step
			local previous = scroll.CanvasPosition.Y
			local limit = math.max(
				0,
				(scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y) / Motion.scale(scroll)
			)
			local target = math.clamp(previous + dy, 0, limit)
			if target ~= previous then
				scroll.CanvasPosition = Vector2.new(scroll.CanvasPosition.X, target)
				self:SyncScrollingFramePosition()

				SelectionState.selectionStartTimelinePoint -= Vector2.new(0, target - previous)
			end
		end

		self:UpdateSelectionBox(point)
		self:SelectKeyframesInSelectionBox(point)
	end

	function Timeline:IsSelectionCaptureVisible()
		if require("State").PresentationHidden or UserInputService:GetFocusedTextBox() then
			return false
		end

		local node = self.refs.Scale
		if not node or not node.Parent then
			return false
		end

		while node do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end

			if node:IsA("LayerCollector") and not node.Enabled then
				return false
			end

			node = node.Parent
		end

		return true
	end

	function Timeline:SelectKeyframesBeside(point, extend)
		local selector = self.refs and self.refs.Selector
		local playX = selector and selector.AbsolutePosition.X + selector.AbsoluteSize.X * 0.5
			or point.X
		local left = point.X < playX
		local frame = TimelineState.CurrentTime * TimelineState.FPS
		local list = {}
		if extend then
			for key in self._preBoxSelection or {} do
				table.insert(list, key)
			end
		end

		for motor, bucket in TimelineState.Keyframes do
			if not motor.Parent then
				continue
			end

			for _, keyData in bucket do
				local f = keyData.Frame or 0
				if (left and f <= frame + 0.1) or (not left and f >= frame - 0.1) then
					table.insert(list, keyData)
				end
			end
		end

		self:SetSelectedKeyframes(list)
		for _, keyData in list do
			self:SelectAllChannelsForKeyData(keyData)
		end

		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:StartSelectionCapture(point)
		self._selectionDragConsumed = false
		self._preBoxSelection = table.clone(TimelineState.SelectedKeyframes)
		self:BeginKeyframeBoxSelection(self:IsSelectionModifierDown())
		SelectionState.selectionDragging = true
		SelectionState.selectionStartMouse = point
		SelectionState.selectionStartTimelinePoint = self:GetTimelinePointFromMouse(point)
		self:UpdateSelectionBox(point)
		if self._selectionScroll then
			self._selectionScroll:Disconnect()
		end

		self._selectionScroll = RunService.Heartbeat:Connect(function(dt)
			if not SelectionState.selectionDragging then
				self:HideSelectionBox()
				return
			end

			if not self:IsSelectionCaptureVisible() then
				self:HideSelectionBox()
				return
			end

			self:StepSelectionScroll(dt, UserInputService:GetMouseLocation())
		end)
	end

	function Timeline:BeginKeyframeBoxSelection(additive)
		self._selectionSubtract = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		additive = additive or self._selectionSubtract
		self._selectionAdditive = additive == true
		self._selectionBasePoses = additive and table.clone(TimelineState.SelectedKeyframes) or {}
		self._selectionBaseChannels = {}
		if additive then
			for key, lanes in TimelineState.SelectedChannelKeyframes do
				self._selectionBaseChannels[key] = table.clone(lanes)
			end
		end

		local targets = self:GetSelectionHitTargets()
		if not additive then
			TimelineState.SelectedKeyframes = {}
			TimelineState.SelectedChannelKeyframes = {}
			TimelineState.SelectedKeyframe = nil
		end

		self._selectionBoxHits = nil
		self._selectionBoxCounts = nil
		local groups = {}
		for _, target in targets do
			if not target.button then
				continue
			end

			if target.group then
				if target.group.bar then
					groups[target.group] = true
				end
			elseif target.lane then
				self:_paintChannelDiamond(
					target.button,
					target.key.Motor,
					target.key.Frame,
					target.lane
				)
			else
				local image = self:GetKeyframeImageObject(target.button)
				self:ApplyKeyframeVisualState(target.key, target.button, image and image.Image)
			end
		end

		if self.RefreshKeyframeGroupSelection then
			self:RefreshKeyframeGroupSelection(groups)
		end

		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
	end

	function Timeline:SelectKeyframesInSelectionBox(currentMousePos)
		local minX, minY, maxX, maxY = self:GetSelectionBounds(currentMousePos)
		if not minX then
			self:ClearSelectedKeyframes()
			return
		end

		local scale = self.refs and self.refs.Scale
		if not scale then
			return
		end

		local targets = self:GetSelectionHitTargets()
		local origin = scale.AbsolutePosition
		local hits = {}
		local factor = Motion.scale(scale)
		local geometryCache, frameCache = {}, {}

		local function geometry(button)
			local cached = geometryCache[button]
			if cached ~= nil then
				return cached
			end

			if not button.Parent then
				geometryCache[button] = false
				return false
			end

			local ancestor = button
			while ancestor and ancestor ~= scale do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then
					geometryCache[button] = false
					return false
				end

				ancestor = ancestor.Parent
			end

			cached = { (button.AbsolutePosition - origin) / factor, button.AbsoluteSize / factor }
			geometryCache[button] = cached
			return cached
		end

		local function frameX(frame)
			local x = frameCache[frame]
			if x == nil then
				x = self:FrameToVisibleX(frame)
				frameCache[frame] = x
			end

			return x
		end

		for _, target in targets do
			local button = target.row or target.button
			local bounds = button and geometry(button)
			if not bounds then
				continue
			end

			local pos, size = bounds[1], bounds[2]
			if target.row then
				local y = pos.Y + size.Y * 0.5
				if y < minY or y > maxY then
					continue
				end

				local first, last = frameX(target.first), frameX(target.last)
				first += pos.X
				last += pos.X
				pos = Vector2.new(first, y)
				size = Vector2.new(last - first, 0)
			end

			local inside
			if target.group then
				inside = pos.X <= maxX
					and pos.X + size.X >= minX
					and pos.Y <= maxY
					and pos.Y + size.Y >= minY
			else
				local center = pos + size * 0.5
				inside = center.X >= minX
					and center.X <= maxX
					and center.Y >= minY
					and center.Y <= maxY
			end

			if inside then
				hits[target] = true
			end
		end

		local previous = self._selectionBoxHits
		local changed = previous == nil
		if previous then
			for target in hits do
				if not previous[target] then
					changed = true
					break
				end
			end

			if not changed then
				for target in previous do
					if not hits[target] then
						changed = true
						break
					end
				end
			end
		end

		if not changed then
			return false
		end

		self._selectionBoxHits = hits
		local dirty, groups = {}, {}
		local counts = self._selectionBoxCounts
		if not counts then
			counts = { poses = {}, channels = {} }
			self._selectionBoxCounts = counts
			for key in self._selectionBasePoses or {} do
				counts.poses[key] = 1
			end

			for key, lanes in self._selectionBaseChannels or {} do
				local saved = {}
				counts.channels[key] = saved
				for lane in lanes do
					saved[lane] = 1
				end
			end

			for key in TimelineState.SelectedKeyframes do
				dirty[key] = true
			end

			for key in TimelineState.SelectedChannelKeyframes do
				dirty[key] = true
			end

			TimelineState.SelectedKeyframes = {}
			TimelineState.SelectedChannelKeyframes = {}
		end

		local function adjust(key, lane, delta)
			dirty[key] = true
			if lane and lane ~= "Pose" then
				local lanes = counts.channels[key] or {}
				counts.channels[key] = lanes
				local count = (lanes[lane] or 0) + delta
				lanes[lane] = count > 0 and count or nil
				if not next(lanes) then
					counts.channels[key] = nil
				end
			else
				local count = (counts.poses[key] or 0) + delta
				counts.poses[key] = count > 0 and count or nil
			end
		end

		local function adjustTarget(target, delta)
			if target.group then
				if target.group.bar then
					groups[target.group] = true
				end

				for _, member in target.group.members do
					adjust(member.key, target.group.lane, delta)
				end
			else
				adjust(target.key, target.lane, delta)
			end
		end

		for target in previous or {} do
			if not hits[target] then
				adjustTarget(target, -1)
			end
		end

		for target in hits do
			if not previous or not previous[target] then
				adjustTarget(target, 1)
			end
		end

		for key in dirty do
			if self._selectionSubtract then
				local basePose = self._selectionBasePoses[key]
				local poseHit = (counts.poses[key] or 0) > (basePose and 1 or 0)
				local baseChannels = self._selectionBaseChannels[key] or {}
				local channelHit = false
				local remaining = {}
				for lane, count in counts.channels[key] or {} do
					local hit = count > (baseChannels[lane] and 1 or 0)
					if hit then
						channelHit = true
					end

					if baseChannels[lane] and not hit and not poseHit then
						remaining[lane] = true
					end
				end

				TimelineState.SelectedKeyframes[key] = basePose
						and not poseHit
						and not channelHit
						and true
					or nil
				TimelineState.SelectedChannelKeyframes[key] = next(remaining) and remaining or nil
			else
				TimelineState.SelectedKeyframes[key] = counts.poses[key] and true or nil
				TimelineState.SelectedChannelKeyframes[key] = nil
				if counts.poses[key] then
					self:SelectAllChannelsForKeyData(key)
				end

				for lane in counts.channels[key] or {} do
					local lanes = TimelineState.SelectedChannelKeyframes[key] or {}
					TimelineState.SelectedChannelKeyframes[key] = lanes
					lanes[lane] = true
				end
			end

			for _, entry in self._groupsByKey and self._groupsByKey[key] or {} do
				groups[entry] = true
			end
		end

		TimelineState.SelectedKeyframe = next(TimelineState.SelectedKeyframes)
			or next(TimelineState.SelectedChannelKeyframes)

		for _, target in targets do
			if
				target.group
				or not dirty[target.key]
				or not target.button
				or not target.button.Parent
			then
				continue
			end

			if target.lane then
				self:_paintChannelDiamond(
					target.button,
					target.key.Motor,
					target.key.Frame,
					target.lane
				)
			else
				local image = self:GetKeyframeImageObject(target.button)
				self:ApplyKeyframeVisualState(target.key, target.button, image and image.Image)
			end
		end

		if self.RefreshKeyframeGroupSelection then
			self:RefreshKeyframeGroupSelection(groups)
		end

		self:UpdateDeleteButtonState()
		refreshSelectionFilter(self)
		return true
	end
end
