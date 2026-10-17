--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Motion = require("Motion")
local GraphCurves = require("GraphCurves")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("RawState")
local History = require("History")
local PresentationState = require("State")
local TimelineState = State.Timeline
local TimelineConfig = State.Config
local PlayheadDrag = State.PlayheadDrag
local KeyframeDrag = State.KeyframeDrag
local SelectionState = State.Selection
local KeyframeTransform = State.KeyframeTransform
local KEYFRAME_DEFAULT_COLOR = State.Colors.KEYFRAME_DEFAULT_COLOR
local KEYFRAME_HOVER_COLOR = State.Colors.KEYFRAME_HOVER_COLOR
local KEYFRAME_SELECTED_COLOR = State.Colors.KEYFRAME_SELECTED_COLOR
local LOOP_ACTIVE_COLOR = State.Colors.LOOP_ACTIVE_COLOR
local LOOP_INACTIVE_COLOR = State.Colors.LOOP_INACTIVE_COLOR

local function isPointInsideGui(gui, point)
	if not gui or typeof(gui) ~= "Instance" then
		return false
	end

	local ok, pos = pcall(function()
		return gui.AbsolutePosition
	end)
	if not ok or not pos then
		return false
	end

	local size = gui.AbsoluteSize
	return point.X >= pos.X
		and point.X <= pos.X + size.X
		and point.Y >= pos.Y
		and point.Y <= pos.Y + size.Y
end

return function(Timeline)
	function Timeline:HandleControlWheel(direction)
		if
			not (
				UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			)
		then
			return false
		end

		for _, key in
			{
				Enum.KeyCode.LeftAlt,
				Enum.KeyCode.RightAlt,
				Enum.KeyCode.LeftShift,
				Enum.KeyCode.RightShift,
				Enum.KeyCode.LeftMeta,
				Enum.KeyCode.RightMeta,
				Enum.KeyCode.LeftSuper,
				Enum.KeyCode.RightSuper,
			}
		do
			if UserInputService:IsKeyDown(key) then
				return true
			end
		end

		if
			direction == 0
			or UserInputService:GetFocusedTextBox()
			or require("NumericInput").contains(UserInputService:GetMouseLocation())
			or PresentationState.PresentationHidden
			or PresentationState.LoadingProject
			or PresentationState.PhysicsSimulating
			or TimelineState.Playing
			or self:IsExportLocked()
			or KeyframeDrag.draggingKeyframe
			or PlayheadDrag.draggingPlayhead
			or SelectionState.selectionDragging
			or KeyframeTransform.active
			or History.isApplying()
		then
			return true
		end

		if not require("UI").isAnimatorActive() then
			return true
		end

		self:NudgeSelectedKeyframes(direction > 0 and -1 or 1)
		return true
	end

	function Timeline:HandleAltWheel(direction)
		if
			not (
				UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
			)
		then
			return false
		end

		for _, key in
			{
				Enum.KeyCode.LeftControl,
				Enum.KeyCode.RightControl,
				Enum.KeyCode.LeftShift,
				Enum.KeyCode.RightShift,
				Enum.KeyCode.LeftMeta,
				Enum.KeyCode.RightMeta,
				Enum.KeyCode.LeftSuper,
				Enum.KeyCode.RightSuper,
			}
		do
			if UserInputService:IsKeyDown(key) then
				return true
			end
		end

		if
			direction == 0
			or UserInputService:GetFocusedTextBox()
			or require("NumericInput").contains(UserInputService:GetMouseLocation())
			or PresentationState.PresentationHidden
			or PresentationState.LoadingProject
			or self:IsExportLocked()
			or KeyframeDrag.draggingKeyframe
			or PlayheadDrag.draggingPlayhead
			or SelectionState.selectionDragging
			or KeyframeTransform.active
		then
			return true
		end

		if not require("UI").isAnimatorActive() then
			return true
		end

		require("Project").stepFrame(
			direction > 0 and "Left" or "Right",
			require("Preferences").get("AltScrollFrameStep")
		)
		return true
	end

	function Timeline:UpdateKeyframeDragAtPosition(point, referenceX)
		if not KeyframeDrag.draggingKeyframe then
			return
		end

		local info = KeyframeDrag.draggingKeyframe
		local mouseDelta = point.X - PlayheadDrag.dragStartMouseX

		if not info.IsRealDrag and math.abs(mouseDelta) >= KeyframeDrag.keyframeDragThreshold then
			info.IsRealDrag = true
			self:RefreshAllKeyframeVisuals()
		end

		if not info.IsRealDrag then
			return
		end

		local scaleGui = self.refs.Scale
		if not scaleGui then
			return
		end

		local factor = Motion.scale(scaleGui)
		local x = point.X
		local viewport = self.refs.TimelineContainer
		if viewport then
			local left = viewport.AbsolutePosition.X + 20 * factor
			local right =
				math.max(left, viewport.AbsolutePosition.X + viewport.AbsoluteSize.X - 20 * factor)
			x = math.clamp(x, left, right)
		end

		local mouseTimelineX = (x - (referenceX or self:GetClickReferenceX())) / factor
		local rawFrame = self:PixelToFrame(mouseTimelineX) - KeyframeDrag.dragMouseFrameOffset
		local newFrame = math.clamp(rawFrame, 0, self:GetMaxFrame())

		if info.ChannelId then
			local frameDelta = newFrame - info.OriginalFrame
			local groupChannels = KeyframeDrag.groupDragSelectedChannels
			if not groupChannels or #groupChannels == 0 then
				groupChannels = {
					{
						keyData = info.KeyData,
						channelId = info.ChannelId,
						originalFrame = info.OriginalFrame,
						motor = info.Motor,
						part = info.Part,
						sanitizeName = info.SanitizeName,
					},
				}
			end

			local maxFrame = self:GetMaxFrame()
			if self.ConstrainGroupedDrag then
				frameDelta = self:ConstrainGroupedDrag(frameDelta, groupChannels)
				if frameDelta == nil then
					return
				end
			end

			KeyframeDrag.dragCurrentFrame = info.OriginalFrame + frameDelta
			if self.PreviewCompactKeyframeDrag and self:PreviewCompactKeyframeDrag(frameDelta) then
				return
			end

			local movedBoneButtons = {}
			for _, entry in ipairs(groupChannels) do
				local targetFrame = math.clamp(entry.originalFrame + frameDelta, 0, maxFrame)
				local channelRows = TimelineState.ChannelTracks[entry.motor]
				local row = channelRows and channelRows[entry.channelId]
				if row then
					local container = self:GetTrackKeyframesContainer(row)
					if container then
						local kfBtn = container:FindFirstChild("ChannelKF_" .. entry.originalFrame)
						if kfBtn then
							kfBtn.Position = UDim2.new(0, self:FrameToVisibleX(targetFrame), 0.5, 0)
						end
					end
				end

				if
					entry.keyData
					and entry.keyData.Button
					and not movedBoneButtons[entry.keyData]
				then
					movedBoneButtons[entry.keyData] = true
					entry.keyData.Button.Position =
						UDim2.new(0, self:FrameToVisibleX(targetFrame), 0.5, 0)
				end
			end

			if self.RefreshKeyframeGroupPositions then
				self:RefreshKeyframeGroupPositions()
			end

			return
		end

		local frameDelta = newFrame - info.OriginalFrame
		if self.ConstrainGroupedDrag then
			local entries = {}
			for _, key in KeyframeDrag.groupDragSelected do
				table.insert(entries, {
					keyData = key,
					originalFrame = KeyframeDrag.groupDragOriginals[key] or key.Frame,
				})
			end

			frameDelta = self:ConstrainGroupedDrag(frameDelta, entries)
			if frameDelta == nil then
				return
			end
		end

		KeyframeDrag.dragCurrentFrame = info.OriginalFrame + frameDelta
		if self.PreviewCompactKeyframeDrag and self:PreviewCompactKeyframeDrag(frameDelta) then
			return
		end

		for _, key in KeyframeDrag.groupDragSelected do
			local original = KeyframeDrag.groupDragOriginals[key] or key.Frame
			local position = UDim2.new(0, self:FrameToVisibleX(original + frameDelta), 0.5, 0)
			if key.Button then
				key.Button.Position = position
			end

			for _, row in TimelineState.ChannelTracks[key.Motor] or {} do
				local container = self:GetTrackKeyframesContainer(row)
				local button = container and container:FindFirstChild("ChannelKF_" .. original)
				if button then
					button.Position = position
				end
			end

			if self.GetIKEndMarkerButtons then
				for _, button in self:GetIKEndMarkerButtons(key) do
					button.Position = position
				end
			end
		end

		if self.RefreshKeyframeGroupPositions then
			self:RefreshKeyframeGroupPositions()
		end
	end

	function Timeline:StepKeyframeDragScroll(dt, point)
		local info = KeyframeDrag.draggingKeyframe
		if
			not info
			or not info.IsRealDrag
			or PresentationState.PresentationHidden
			or PresentationState.LoadingProject
			or TimelineState.Playing
			or self:IsExportLocked()
			or not point
		then
			return
		end

		local viewport = self.refs.TimelineContainer
		local animator = self.refs.AnimatorFrame
		if not viewport or not viewport.Parent or animator and not animator.Visible then
			return
		end

		local factor = Motion.scale(viewport)
		local left = viewport.AbsolutePosition.X + 20 * factor
		local right = viewport.AbsolutePosition.X + viewport.AbsoluteSize.X - 20 * factor
		local band = math.min(28 * factor, (right - left) * 0.5)
		if band <= 0 then
			return
		end

		local speed = 0
		if point.X < left + band then
			speed = -math.clamp((left + band - point.X) / band, 0, 2) * 420
		elseif point.X > right - band then
			speed = math.clamp((point.X - right + band) / band, 0, 2) * 420
		end

		local previous = TimelineState.ScrollOffset
		local offset = math.clamp(
			previous + speed * math.clamp(dt or 0, 0, 0.05),
			0,
			self:GetTimelineScrollLimit()
		)
		if offset == previous then
			return
		end

		local referenceX = self:GetClickReferenceX() - (offset - previous) * factor
		self:SetTimelineScroll(offset)
		self:UpdateKeyframeDragAtPosition(
			Vector2.new(math.clamp(point.X, left, right), point.Y),
			referenceX
		)
	end

	function Timeline.Initialize(data)
		local self = setmetatable({}, { __index = Timeline })
		self.refs = data
		if self.refs.DragButton and not self.refs.TopSelectorDragHitbox then
			self.refs.TopSelectorDragHitbox = self.refs.DragButton
		end

		State.timelineUI = self.refs.Scale
			or self.refs.TimelineContainer
			or self.refs.KeysRoot
			or self.refs.MainFrame

		if self.refs.LoopButton and not self.refs.LoopButton:GetAttribute("LoopBound") then
			self.refs.LoopButton:SetAttribute("LoopBound", true)
			self:SetLooping(true)

			if self.refs.LoopButton:IsA("GuiButton") then
				self.refs.LoopButton.MouseButton1Click:Connect(function()
					self:ToggleLooping()
				end)
			end
		end

		if self.refs.RecordButton and not self.refs.RecordButton:GetAttribute("RecordBound") then
			self.refs.RecordButton:SetAttribute("RecordBound", true)
			self:SetRecording(true)

			if self.refs.RecordButton:IsA("GuiButton") then
				self.refs.RecordButton.MouseButton1Click:Connect(function()
					self:ToggleRecording()
				end)
			end
		end

		local scroll = self.refs.RigListScroll
		local wheelGeneration = 0
		scroll.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end

			if require("NumericInput").contains(require("UserInputService"):GetMouseLocation()) then
				return
			end

			if
				self:HandleAltWheel(input.Position.Z) or self:HandleControlWheel(input.Position.Z)
			then
				wheelGeneration += 1
				local generation = wheelGeneration
				local position = scroll.CanvasPosition
				scroll.ScrollingEnabled = false
				task.defer(function()
					if generation == wheelGeneration and scroll.Parent then
						scroll.CanvasPosition = position
						scroll.ScrollingEnabled = true
					end
				end)
				return
			end

			local speed = require("Preferences").timelineScrollSpeed()
			wheelGeneration += 1
			local generation = wheelGeneration
			local position = scroll.CanvasPosition
			scroll.ScrollingEnabled = false
			local limit = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
			scroll.CanvasPosition = Vector2.new(
				position.X,
				math.clamp(position.Y - input.Position.Z * 48 * speed, 0, limit)
			)
			task.defer(function()
				if generation == wheelGeneration and scroll.Parent then
					scroll.ScrollingEnabled = true
				end
			end)
		end)
		self.refs.RigListScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:SyncScrollingFramePosition()
		end)

		self.refs.RigListScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
			self:SyncScrollingFrameHeight()
		end)

		self.refs.KeysRoot:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
			self:SyncScrollingFramePosition()
		end)
		for _, pane in { self.refs.KeysRoot, self.refs.RigListScroll } do
			pane:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
				self:SyncScrollingFrameHeight()
			end)
		end

		self:SyncScrollingFrameHeight()

		self.timelineZoom = self.refs.UIHelpers.zoom.new(self.refs.Scale, self.refs.Fit, function(
			direction
		)
			return self:HandleAltWheel(direction) or self:HandleControlWheel(direction)
		end
)
		self.timelineZoom.minimum = function()
			return 1 / math.max(1, self:GetMaxFrame() / State.Config.DefaultFrames)
		end

		self:InitializeNavigation()
		self:LoadProjectSettings()

		self.refs.TimelineContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:RefreshTimelineScale()
		end)

		self.timelineZoom.changed.Event:Connect(function()
			local x = self.timelineZoom.anchorX
				or math.clamp(
					UserInputService:GetMouseLocation().X
						- self.refs.TimelineContainer.AbsolutePosition.X
						- 20,
					0,
					self:GetTimelineViewportWidth()
				)
			local anchor = (TimelineState.ScrollOffset + x)
				/ math.max(1, TimelineState.ContentWidth)
			self:RefreshTimelineScale()
			self:SetTimelineScroll(anchor * self:GetVisibleTimelineWidth() - x)
		end)

		return self
	end

	function Timeline:BuildTimelineUI(currentRigGetter)
		State.timelineUI = self.refs.Scale
			or self.refs.TimelineContainer
			or self.refs.KeysRoot
			or self.refs.MainFrame
		TimelineState.ContentWidth = self:GetTimelineWidth()
		self:RefreshTimelineScale()

		self:ClearGuides()
		self:ClearTicks()
		self:ClearTracks()
		self:BuildGuidesAndTicks()
		self:BindDeleteHotkey()
		self:BindCopyPasteHotkeys()
		self:BindDeleteButton()
		self:BindUnselectorButton()
		self:BindPlayhead(currentRigGetter)
		self:BindBlenderKeyframeTransform()
		self:EnsureSelectionBox()
		self:HideSelectionBox()
		self:UpdatePlayhead()

		if not TimelineState._TimelineInputBound then
			TimelineState._TimelineInputBound = true

			local scrollConnection
			scrollConnection = RunService.Heartbeat:Connect(function(dt)
				local root = self.refs.PluginGui
				if root and not root.Parent then
					scrollConnection:Disconnect()
					return
				end

				if KeyframeDrag.draggingKeyframe then
					self:StepKeyframeDragScroll(dt, UserInputService:GetMouseLocation())
				end
			end)

			UserInputService.WindowFocusReleased:Connect(function()
				self:CancelTimelineKeyframeDrag()
			end)
			UserInputService.InputBegan:Connect(function(input)
				if
					input.KeyCode == Enum.KeyCode.Escape
					and not UserInputService:GetFocusedTextBox()
				then
					self:CancelTimelineKeyframeDrag()
				end
			end)
			local animator = self.refs.AnimatorFrame
			if animator then
				animator:GetPropertyChangedSignal("Visible"):Connect(function()
					if not animator.Visible then
						self:CancelTimelineKeyframeDrag()
					end
				end)
			end

			local pluginGui = self.refs.PluginGui
			if pluginGui then
				pluginGui:GetPropertyChangedSignal("Enabled"):Connect(function()
					if not pluginGui.Enabled then
						self:CancelTimelineKeyframeDrag()
					end
				end)
			end

			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					if SelectionState.selectionDragging then
						local start = SelectionState.selectionStartMouse
						local point = Vector2.new(input.Position.X, input.Position.Y)
						local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
							or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
						if ctrl and start and (point - start).Magnitude < 4 then
							SelectionState.selectionDragging = false
							self:HideSelectionBox()
							self:SelectKeyframesBeside(
								point,
								UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
									or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
							)
						else
							self:UpdateSelectionBox(input.Position)
							self:SelectKeyframesInSelectionBox(input.Position)
							SelectionState.selectionDragging = false
							self:HideSelectionBox()
						end
					end

					if KeyframeDrag.draggingKeyframe then
						local info = KeyframeDrag.draggingKeyframe
						local finalKeyData = info.KeyData

						if info.ChannelId then
							do
								local groupForReset = KeyframeDrag.groupDragSelectedChannels
								if not groupForReset or #groupForReset == 0 then
									groupForReset = {
										{
											keyData = info.KeyData,
											originalFrame = info.OriginalFrame,
										},
									}
								end

								local resetBoneButtons = {}
								for _, entry in ipairs(groupForReset) do
									if
										entry.keyData
										and entry.keyData.Button
										and not resetBoneButtons[entry.keyData]
									then
										resetBoneButtons[entry.keyData] = true
										entry.keyData.Button.Position = UDim2.new(
											0,
											self:FrameToVisibleX(entry.originalFrame),
											0.5,
											0
										)
									end
								end
							end

							if info.IsRealDrag then
								local finalFrame = KeyframeDrag.dragCurrentFrame
									or info.OriginalFrame
								local frameDelta = finalFrame - info.OriginalFrame
								if frameDelta ~= 0 then
									local groupChannels = KeyframeDrag.groupDragSelectedChannels
									if not groupChannels or #groupChannels == 0 then
										groupChannels = {
											{
												keyData = info.KeyData,
												channelId = info.ChannelId,
												originalFrame = info.OriginalFrame,
												motor = info.Motor,
												part = info.Part,
												sanitizeName = info.SanitizeName,
											},
										}
									end

									local maxFrame = self:GetMaxFrame()

									local function snapshotKeyData(motor, frame)
										local b = TimelineState.Keyframes[motor]
										local kd = b and b[frame]
										if not kd then
											return { existed = false }
										end

										local channelsCopy = {}
										if kd.Channels then
											for chId, ch in pairs(kd.Channels) do
												channelsCopy[chId] = GraphCurves.clone(ch)
											end
										end

										return {
											existed = true,
											channels = channelsCopy,
											Disabled = kd.Disabled,
											ChannelPoseC0 = kd.ChannelPoseC0,
											BlenderCurve = GraphCurves.clone(kd.BlenderCurve),
											BlenderSource = kd.BlenderSource,
											KeyGroups = GraphCurves.clone(kd.KeyGroups),
											WholePoseScale = GraphCurves.clone(kd.WholePoseScale),
											PhysicsLead = GraphCurves.clone(kd.PhysicsLead),
											PhysicsTail = kd.PhysicsTail,
											GraphOnly = kd.GraphOnly,
											GraphCurves = GraphCurves.clone(kd.GraphCurves),
											part = kd.Part,
											sanitizeName = kd.SanitizeName,
											c0 = kd.C0,
											worldCFrame = kd.WorldCFrame,
											MasterWorld = kd.MasterWorld,
										}
									end

									local function restoreFromSnapshot(motor, frame, snap)
										local b = TimelineState.Keyframes[motor]
										if not b then
											return
										end

										if not snap.existed then
											GraphCurves.invalidate(b)
											if PresentationState.GraphEditor then
												PresentationState.GraphEditor.invalidate()
											end

											local kd = b[frame]
											if kd then
												if kd.Button then
													kd.Button:Destroy()
												end

												b[frame] = nil
											end

											self:_removeChannelDiamondAtFrame(motor, frame)
											return
										end

										local kd = b[frame]
										if not kd then
											b[frame] = {
												Frame = frame,
												Time = frame / TimelineState.FPS,
												Motor = motor,
												Part = snap.part,
												SanitizeName = snap.sanitizeName,
												Channels = {},
											}
											kd = b[frame]
										end

										kd.KeyGroups = GraphCurves.clone(snap.KeyGroups)
										kd.GraphOnly, kd.GraphCurves =
											snap.GraphOnly, GraphCurves.clone(snap.GraphCurves)
										GraphCurves.invalidate(b)
										if PresentationState.GraphEditor then
											PresentationState.GraphEditor.invalidate()
										end

										kd.Channels = {}
										for chId, ch in pairs(snap.channels) do
											kd.Channels[chId] = GraphCurves.clone(ch)
										end

										kd.C0 = snap.c0
											or self:_reconstructC0FromKeyData(kd)
											or kd.C0
										if kd.C0 then
											kd.Position = kd.C0.Position
											kd.Rotation = kd.C0 - kd.C0.Position
										end

										kd.Disabled, kd.ChannelPoseC0, kd.WholePoseScale =
											snap.Disabled,
											snap.ChannelPoseC0,
											GraphCurves.clone(snap.WholePoseScale)
										kd.PhysicsLead, kd.PhysicsTail =
											GraphCurves.clone(snap.PhysicsLead), snap.PhysicsTail
										kd.BlenderCurve = GraphCurves.clone(snap.BlenderCurve)
										kd.BlenderSource = snap.BlenderSource
										kd.WorldCFrame = snap.worldCFrame
										kd.MasterWorld = snap.MasterWorld
										self:CreateOrUpdateTimelineKeyframeButton(
											snap.part,
											motor,
											frame,
											nil,
											snap.sanitizeName
										)
										self:_addChannelDiamondAtFrame(motor, frame)
									end

									local touchedFrames = {}
									for _, entry in ipairs(groupChannels) do
										local destFrame = math.clamp(
											entry.originalFrame + frameDelta,
											0,
											maxFrame
										)
										if destFrame ~= entry.originalFrame then
											touchedFrames[entry.motor] = touchedFrames[entry.motor]
												or {}
											touchedFrames[entry.motor][entry.originalFrame] = true
											touchedFrames[entry.motor][destFrame] = true
										end
									end

									local snapshotsBefore = {}
									for motor, frameSet in pairs(touchedFrames) do
										snapshotsBefore[motor] = {}
										for frame in pairs(frameSet) do
											snapshotsBefore[motor][frame] =
												snapshotKeyData(motor, frame)
										end
									end

									local sortedEntries = {}
									for _, e in ipairs(groupChannels) do
										table.insert(sortedEntries, e)
									end

									if frameDelta > 0 then
										table.sort(sortedEntries, function(a, b)
											return a.originalFrame > b.originalFrame
										end)
									elseif frameDelta < 0 then
										table.sort(sortedEntries, function(a, b)
											return a.originalFrame < b.originalFrame
										end)
									end

									local lastPeeled = nil
									local lastDestFrame = nil
									for _, entry in ipairs(sortedEntries) do
										local destFrame = math.clamp(
											entry.originalFrame + frameDelta,
											0,
											maxFrame
										)
										if destFrame ~= entry.originalFrame then
											local peeled = self:PeelOffChannelKeyframe(
												entry.motor,
												entry.originalFrame,
												destFrame,
												entry.channelId
											)
											if peeled then
												lastPeeled = peeled
												lastDestFrame = destFrame
											end
										end
									end

									if lastPeeled then
										finalKeyData = lastPeeled
									end

									local snapshotsAfter = {}
									for motor, frameSet in pairs(touchedFrames) do
										snapshotsAfter[motor] = {}
										for frame in pairs(frameSet) do
											snapshotsAfter[motor][frame] =
												snapshotKeyData(motor, frame)
										end
									end

									local newSelectedChannels = {}
									for _, entry in ipairs(groupChannels) do
										local destFrame = math.clamp(
											entry.originalFrame + frameDelta,
											0,
											maxFrame
										)
										local newKd = TimelineState.Keyframes[entry.motor]
											and TimelineState.Keyframes[entry.motor][destFrame]
										if newKd then
											newSelectedChannels[newKd] = newSelectedChannels[newKd]
												or {}
											newSelectedChannels[newKd][entry.channelId] = true
										end
									end

									local description = (#groupChannels > 1)
											and ("Move " .. #groupChannels .. " channel keyframes")
										or ("Move " .. info.ChannelId .. " keyframe")

									History.record(function()
										for motor, frames in pairs(snapshotsBefore) do
											for frame, snap in pairs(frames) do
												restoreFromSnapshot(motor, frame, snap)
											end
										end

										local rig = currentRigGetter and currentRigGetter()
										if rig then
											self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
										end

										self:RefreshAllKeyframeVisuals()
									end, function()
										for motor, frames in pairs(snapshotsAfter) do
											for frame, snap in pairs(frames) do
												restoreFromSnapshot(motor, frame, snap)
											end
										end

										local rig = currentRigGetter and currentRigGetter()
										if rig then
											self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
										end

										self:RefreshAllKeyframeVisuals()
									end, description, lastDestFrame or finalFrame)

									for motor in pairs(touchedFrames) do
										self:RefreshAllChannelDiamondsForMotor(motor)
									end

									TimelineState.SelectedChannelKeyframes = newSelectedChannels
									TimelineState.SelectedKeyframes = {}
									TimelineState.SelectedKeyframe = finalKeyData
								end
							end

							KeyframeDrag.dragHoverReplaceTarget = nil
							KeyframeDrag.dragCurrentFrame = nil
							KeyframeDrag.draggingKeyframe = nil
							KeyframeDrag.groupDragSelectedChannels = {}
							KeyframeDrag.dragBucketSnapshotsBefore = nil

							local rig = currentRigGetter and currentRigGetter() or nil
							if rig then
								self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
							end

							self:RefreshAllKeyframeVisuals()
						elseif info.IsRealDrag then
							local finalFrame = KeyframeDrag.dragCurrentFrame or info.KeyData.Frame

							local delta = finalFrame - info.OriginalFrame
							local selected = table.clone(KeyframeDrag.groupDragSelected or {})
							if #selected == 0 then
								selected = { info.KeyData }
							end

							table.sort(selected, function(a, b)
								if delta >= 0 then
									return a.Frame > b.Frame
								end

								return a.Frame < b.Frame
							end)
							for _, key in selected do
								local original = KeyframeDrag.groupDragOriginals[key] or key.Frame
								local target = original + delta
								local moved = self:MoveKeyframe(
									key.Part,
									key.Motor,
									original,
									target,
									key.Template,
									key.SanitizeName,
									true
								)
								if key == info.KeyData and moved then
									finalKeyData = moved
								end
							end

							local snapshotsBefore = KeyframeDrag.dragBucketSnapshotsBefore or {}
							KeyframeDrag.dragBucketSnapshotsBefore = nil

							local snapshotsAfter = {}
							for motor in pairs(snapshotsBefore) do
								snapshotsAfter[motor] = self:_snapshotMotorBucket(motor)
							end

							local anyChange = false
							for motor, beforeSnap in pairs(snapshotsBefore) do
								local afterSnap = snapshotsAfter[motor]
								for f, b in pairs(beforeSnap) do
									local a = afterSnap and afterSnap[f]
									if not a or a.C0 ~= b.C0 or a.WorldCFrame ~= b.WorldCFrame then
										anyChange = true
										break
									end
								end

								if not anyChange and afterSnap then
									for f in pairs(afterSnap) do
										if not beforeSnap[f] then
											anyChange = true
											break
										end
									end
								end

								if anyChange then
									break
								end
							end

							local jumpFrameForRedo = nil
							local jumpFrameForUndo = nil
							for kd, origFrame in pairs(KeyframeDrag.groupDragOriginals) do
								if kd == info.KeyData or jumpFrameForUndo == nil then
									jumpFrameForUndo = origFrame
								end
							end

							jumpFrameForRedo = (finalKeyData and finalKeyData.Frame)
								or finalFrame
								or jumpFrameForUndo

							local movedCount = (function()
								local n = 0
								for kd, origFrame in pairs(KeyframeDrag.groupDragOriginals) do
									if kd.Frame ~= origFrame then
										n += 1
									end
								end

								return n
							end)()

							KeyframeDrag.dragHoverReplaceTarget = nil
							KeyframeDrag.dragCurrentFrame = nil
							KeyframeDrag.draggingKeyframe = nil

							local rig = currentRigGetter and currentRigGetter() or nil
							if rig then
								self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
							end

							local selected = {}
							for _, key in KeyframeDrag.groupDragSelected or {} do
								local bucket = TimelineState.Keyframes[key.Motor]
								if bucket and bucket[key.Frame] then
									table.insert(selected, bucket[key.Frame])
								end
							end

							if #selected == 0 and finalKeyData then
								selected = { finalKeyData }
							end

							self:SetSelectedKeyframes(selected)
							self:RefreshAllKeyframeVisuals()

							if anyChange and next(snapshotsBefore) then
								local timeline = self
								local description = (movedCount > 1)
										and ("Move " .. movedCount .. " keyframes")
									or "Move keyframe"
								History.record(function()
									for motor, beforeSnap in pairs(snapshotsBefore) do
										timeline:_restoreMotorBucket(motor, beforeSnap)
									end

									local rigU = currentRigGetter and currentRigGetter() or nil
									if rigU then
										timeline:ApplyPoseAtTime(rigU, TimelineState.CurrentTime)
									end

									timeline:RefreshAllKeyframeVisuals()
								end, function()
									for motor, afterSnap in pairs(snapshotsAfter) do
										timeline:_restoreMotorBucket(motor, afterSnap)
									end

									local rigR = currentRigGetter and currentRigGetter() or nil
									if rigR then
										timeline:ApplyPoseAtTime(rigR, TimelineState.CurrentTime)
									end

									timeline:RefreshAllKeyframeVisuals()
								end, description, jumpFrameForUndo, jumpFrameForRedo)
							end
						else
							KeyframeDrag.dragHoverReplaceTarget = nil
							KeyframeDrag.dragCurrentFrame = nil
							KeyframeDrag.draggingKeyframe = nil
							KeyframeDrag.dragBucketSnapshotsBefore = nil
							self:RefreshAllKeyframeVisuals()
						end

						self:RefreshAllTimelineKeyframePositions()
					end
				end
			end)

			UserInputService.InputChanged:Connect(function(input)
				if PresentationState.PresentationHidden then
					return
				end

				if
					SelectionState.selectionDragging
					and input.UserInputType == Enum.UserInputType.MouseMovement
				then
					if not UserInputService.inWidget() and not UserInputService.isPointerHeld() then
						SelectionState.selectionDragging = false
						self:HideSelectionBox()
						return
					end

					self:UpdateSelectionBox(input.Position)
					self:SelectKeyframesInSelectionBox(input.Position)
					return
				end

				if
					KeyframeDrag.draggingKeyframe
					and input.UserInputType == Enum.UserInputType.MouseMovement
				then
					self:UpdateKeyframeDragAtPosition(input.Position)
				end
			end)

			if not TimelineState._GlobalUnselectBound then
				TimelineState._GlobalUnselectBound = true

				local scaleFrame = self.refs and self.refs.Scale
				if scaleFrame then
					local function beginSelection(input)
						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							and not UserInputService.isTimelinePress(input, scaleFrame)
						then
							return
						end

						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							and not SelectionState.selectionDragging
						then
							self._selectionDragConsumed = false
						end

						if not self:IsSelectionCaptureVisible() then
							return
						end

						if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
							return
						end

						if KeyframeDrag.draggingKeyframe or PlayheadDrag.draggingPlayhead then
							return
						end

						if KeyframeTransform.active then
							return
						end

						local mousePos = Vector2.new(input.Position.X, input.Position.Y)
						if SelectionState.selectionDragging then
							return
						end

						local viewport = self.refs.KeysRoot or self.refs.TimelineContainer
						if
							not isPointInsideGui(self.refs.TimelineContainer, mousePos)
							or not isPointInsideGui(viewport, mousePos)
						then
							return
						end

						if self:IsPointOverSummaryKey(mousePos) then
							return
						end

						if self:IsPointOverEventUI(mousePos, true) then
							return
						end

						local dragBar = self.refs and self.refs.DragBarHitbox
						if dragBar and isPointInsideGui(dragBar, mousePos) then
							return
						end

						for _, bucket in pairs(TimelineState.Keyframes) do
							for _, kd in pairs(bucket) do
								if self:IsMouseDirectlyOverKeyframeButton(kd, mousePos) then
									return
								end
							end
						end

						for _, channelRows in pairs(TimelineState.ChannelTracks) do
							for _, row in pairs(channelRows) do
								local container = self:GetTrackKeyframesContainer(row)
								if container then
									for _, child in ipairs(container:GetChildren()) do
										if
											child:IsA("GuiObject")
											and child.Visible
											and string.sub(child.Name, 1, 10) == "ChannelKF_"
											and isPointInsideGui(child, mousePos)
										then
											return
										end
									end
								end
							end
						end

						self._selectionHitTargets = nil
						for _, target in self:GetSelectionHitTargets() do
							if
								target.button
								and target.button.Parent
								and target.button.Visible
								and isPointInsideGui(target.button, mousePos)
							then
								return
							end
						end

						self:StartSelectionCapture(mousePos)
					end

					scaleFrame.InputBegan:Connect(beginSelection)

					UserInputService.InputBegan:Connect(beginSelection)
					UserInputService.WindowFocusReleased:Connect(function()
						self:HideSelectionBox()
					end)
				end

				UserInputService.InputBegan:Connect(function(input, gameProcessed)
					if PresentationState.PresentationHidden then
						return
					end

					if SelectionState.selectionDragging then
						return
					end

					if gameProcessed then
						return
					end

					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
						return
					end

					local mousePos = UserInputService:GetMouseLocation()
					if self:IsPointOverSummaryKey(mousePos) then
						return
					end

					if self:IsPointOverEventUI(mousePos) then
						return
					end

					if KeyframeDrag.draggingKeyframe or PlayheadDrag.draggingPlayhead then
						return
					end

					if KeyframeTransform.active then
						return
					end

					if
						isPointInsideGui(self.refs.BottomContainer, mousePos)
						or isPointInsideGui(self.refs.FPSLabel, mousePos)
						or (self.navigation and isPointInsideGui(self.navigation.extend, mousePos))
					then
						return
					end

					const keyArea = self.refs.KeysRoot or self.refs.TimelineContainer
					if
						not isPointInsideGui(self.refs.TimelineContainer, mousePos)
						or not isPointInsideGui(keyArea, mousePos)
						or not UserInputService.isTimelinePress(input, keyArea)
						or self:IsSelectionModifierDown()
					then
						return
					end

					self._selectionHitTargets = nil
					for _, target in self:GetSelectionHitTargets() do
						if
							target.button
							and target.button.Parent
							and target.button.Visible
							and isPointInsideGui(target.button, mousePos)
						then
							return
						end
					end

					local selected = TimelineState.SelectedKeyframe
					if not selected and not self:HasSelectedSubtitle() then
						return
					end

					local deleteButton = self:GetDeleteButton()

					if selected and self:IsMouseDirectlyOverKeyframeButton(selected, mousePos) then
						return
					end

					if deleteButton and isPointInsideGui(deleteButton, mousePos) then
						return
					end

					if unselector and isPointInsideGui(unselector, mousePos) then
						return
					end

					self:ClearSelectedKeyframe()
				end)
			end
		end
	end
end
