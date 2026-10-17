--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Shortcuts = require("Shortcuts")
local BlenderEdit = require("BlenderEdit")
local GraphCurves = require("GraphCurves")
local UserInputService = require("UserInputService")

local State = require("RawState")
local MainState = require("State")
local History = require("History")
local motionPath = require("motionPath")
local TimelineState = State.Timeline
local KeyframeTransform = State.KeyframeTransform

local TimeScale = require("TimeScale")
local PARK_BASE = 9999999

local function isPointInsideGui(gui, pos)
	if not gui or typeof(gui) ~= "Instance" then
		return false
	end

	local okPos, absPos = pcall(function()
		return gui.AbsolutePosition
	end)
	local okSize, absSize = pcall(function()
		return gui.AbsoluteSize
	end)

	if not okPos or not okSize or not absPos or not absSize then
		return false
	end

	return pos.X >= absPos.X
		and pos.X <= absPos.X + absSize.X
		and pos.Y >= absPos.Y
		and pos.Y <= absPos.Y + absSize.Y
end

return function(Timeline)
	function Timeline:IsMouseOverPluginAnimator()
		local animator = self.refs and self.refs.AnimatorFrame
		if not animator or not animator.Visible then
			return false
		end

		local pluginGui = self.refs and self.refs.PluginGui
		if pluginGui and pluginGui:IsA("LayerCollector") and not pluginGui.Enabled then
			return false
		end

		return UserInputService.isGuiPointCompatible(animator)
			and isPointInsideGui(animator, UserInputService:GetMouseLocation())
	end

	function Timeline:IsBlenderKeyframeTransformActive()
		return KeyframeTransform.active == true
	end

	function Timeline:GetBlenderKeyframeTransformMode()
		return KeyframeTransform.mode
	end

	local function captureOriginals(self)
		local snap = {}

		for _, keyData in ipairs(self:GetSelectedKeyframesList()) do
			if keyData and keyData.Motor and keyData.Frame ~= nil then
				table.insert(snap, {
					kind = "bone",
					keyData = keyData,
					originalFrame = keyData.Frame,
					originalC0 = keyData.C0,
					originalWorldCFrame = keyData.WorldCFrame,
					originalMasterWorld = keyData.MasterWorld,
					originalParented = keyData.Parented,
					motor = keyData.Motor,
					part = keyData.Part,
					template = keyData.Template,
					sanitizeName = keyData.SanitizeName,
				})
			end
		end

		for _, entry in ipairs(self:GetSelectedChannelKeyframesList()) do
			local keyData = entry.keyData
			local point = keyData
				and (
					keyData.GraphCurves and keyData.GraphCurves[entry.channelId]
					or keyData.Channels and keyData.Channels[entry.channelId]
				)
			if keyData and keyData.Motor and keyData.Frame ~= nil and point and not point.Empty then
				table.insert(snap, {
					kind = "channel",
					keyData = keyData,
					channelId = entry.channelId,
					originalFrame = keyData.Frame,
					originalValue = point.Value,
					motor = keyData.Motor,
					part = keyData.Part,
					sanitizeName = keyData.SanitizeName,
				})
			end
		end

		return snap
	end

	local function clearTransformState()
		local session = KeyframeTransform.scaleSession
		if session then
			UserInputService.setKeyCapture(nil)
			if session.modifiers then
				session.modifiers:Disconnect()
			end

			KeyframeTransform.scaleSession = nil
		end

		KeyframeTransform.active = false
		KeyframeTransform.mode = nil
		KeyframeTransform.frozen = false
		KeyframeTransform.startMouseX = 0
		KeyframeTransform.pivotFrame = 0
		KeyframeTransform.pivotPixelX = 0
		KeyframeTransform.originals = {}
		KeyframeTransform.liveFrames = {}
	end

	local function modifier(left, right)
		return UserInputService:IsKeyDown(Enum.KeyCode[left])
			or UserInputService:IsKeyDown(Enum.KeyCode[right])
	end

	function Timeline:BeginTimeScaleInput(mouse, pivotPixel, pivotFrame)
		local session = TimeScale.begin(mouse, pivotPixel, pivotFrame)
		session.endFrame = self:GetMaxFrame()
		session.snap = TimelineState.KeyframeScaleSnap ~= false
		session.precision = modifier("LeftShift", "RightShift")
		session.seconds = modifier("LeftControl", "RightControl")
		session.before = {}
		for _, snap in KeyframeTransform.originals do
			if not session.before[snap.motor] then
				session.before[snap.motor] = self:_snapshotMotorBucket(snap.motor)
			end
		end

		KeyframeTransform.scaleSession = session

		local function finish(cancel)
			if KeyframeTransform.frozen then
				return
			end

			KeyframeTransform.frozen = true
			task.defer(function()
				if KeyframeTransform.scaleSession ~= session then
					return
				end

				if cancel then
					self:CancelBlenderKeyframeTransform()
				else
					self:ConfirmBlenderKeyframeTransform()
				end
			end)
		end

		UserInputService.setKeyCapture(function(input)
			if KeyframeTransform.scaleSession ~= session or KeyframeTransform.frozen then
				return
			end

			local name = input.KeyCode.Name
			if name == "Escape" or Shortcuts.isKey("Cancel", input.KeyCode) then
				finish(true)
			elseif
				name == "Return"
				or name == "KeypadEnter"
				or Shortcuts.isKey("ConfirmTransform", input.KeyCode)
				or Shortcuts.isKey("ConfirmTransformAlternate", input.KeyCode)
			then
				finish(false)
			elseif name == "Tab" and modifier("LeftShift", "RightShift") then
				session.snap = not session.snap
				TimelineState.KeyframeScaleSnap = session.snap
				self:ProcessBlenderKeyframeTransform(UserInputService:GetMouseLocation())
			elseif
				TimeScale.input(session, name)
				or name == "LeftControl"
				or name == "RightControl"
				or name == "LeftShift"
				or name == "RightShift"
			then
				self:ProcessBlenderKeyframeTransform(UserInputService:GetMouseLocation())
			end
		end)
		session.modifiers = game:GetService("RunService").Heartbeat:Connect(function()
			if KeyframeTransform.scaleSession ~= session then
				return
			end

			local precision = modifier("LeftShift", "RightShift")
			local seconds = modifier("LeftControl", "RightControl")
			if session.precision ~= precision or session.seconds ~= seconds then
				session.precision, session.seconds = precision, seconds
				self:ProcessBlenderKeyframeTransform(UserInputService:GetMouseLocation())
			end
		end)
	end

	function Timeline:UpdateTimeScale(mouse)
		local session = KeyframeTransform.scaleSession
		session.precision = modifier("LeftShift", "RightShift")
		session.seconds = modifier("LeftControl", "RightControl")
		local factor = TimeScale.value(session, TimeScale.mouse(session, mouse, session.precision))
		local targets = {}
		local step = session.snap and (session.seconds and TimelineState.FPS or 1) or nil
		session.valid = false
		if not factor then
			return false
		end

		local upper = math.huge
		local lower = -math.huge
		for _, snap in KeyframeTransform.originals do
			local distance = snap.originalFrame - session.pivot
			if distance > 0 then
				upper = math.min(upper, (session.endFrame - session.pivot) / distance)
			elseif distance < 0 then
				lower = math.max(lower, (session.endFrame - session.pivot) / distance)
			end
		end

		if lower > upper then
			return false
		end

		factor = math.clamp(factor, lower, upper)
		for _, snap in KeyframeTransform.originals do
			local target = math.min(
				session.endFrame,
				TimeScale.frame(snap.originalFrame, session.pivot, factor, step, false)
			)
			if target ~= target or target < 0 then
				return false
			end

			targets[snap.keyData] = target
		end

		session.factor, session.valid = factor, true
		KeyframeTransform.liveFrames = targets
		session.after = TimeScale.build(
			session.before,
			KeyframeTransform.originals,
			targets,
			TimelineState.FPS,

			function(key)
				return self:_reconstructC0FromKeyData(key)
			end
		)
		return true
	end

	function Timeline:PreviewTimeScale(rig)
		local session = KeyframeTransform.scaleSession
		if not session or not session.after then
			return
		end

		local saved = {}
		for motor, bucket in session.after do
			saved[motor] = TimelineState.Keyframes[motor]
			TimelineState.Keyframes[motor] = bucket
			GraphCurves.invalidate(bucket)
			TimelineState._motorUniform[motor], TimelineState._motorHasScale[motor] = nil, nil
		end

		local ok, err = pcall(self.ApplyPoseAtTime, self, rig, TimelineState.CurrentTime)
		for motor, bucket in saved do
			TimelineState.Keyframes[motor] = bucket
			GraphCurves.invalidate(bucket)
			TimelineState._motorUniform[motor], TimelineState._motorHasScale[motor] = nil, nil
		end

		if not ok then
			error(err)
		end
	end

	function Timeline:CommitTimeScale()
		local session = KeyframeTransform.scaleSession
		if session.valid == false then
			KeyframeTransform.frozen = false
			return
		end

		local originals = KeyframeTransform.originals
		local targets = KeyframeTransform.liveFrames
		local changed = false
		local first, last = math.huge, 0
		for _, snap in originals do
			local target = targets[snap.keyData] or snap.originalFrame
			changed = changed or target ~= snap.originalFrame
			first = math.min(first, snap.originalFrame)
			last = math.max(last, target)
		end

		if not changed then
			self:CancelBlenderKeyframeTransform()
			return
		end

		local before, after = session.before, session.after

		local function restore(buckets, moved)
			for motor, bucket in buckets do
				self:_restoreMotorBucket(motor, bucket)
			end

			TimelineState.SelectedKeyframes = {}
			TimelineState.SelectedChannelKeyframes = {}
			TimelineState.SelectedKeyframe = nil
			for _, snap in originals do
				local frame = moved and (targets[snap.keyData] or snap.originalFrame)
					or snap.originalFrame
				local key = TimelineState.Keyframes[snap.motor][frame]
				if key then
					if snap.kind == "bone" then
						TimelineState.SelectedKeyframes[key] = true
					elseif not TimelineState.SelectedKeyframes[key] then
						TimelineState.SelectedChannelKeyframes[key] = TimelineState.SelectedChannelKeyframes[key]
							or {}
						TimelineState.SelectedChannelKeyframes[key][snap.channelId] = true
					end

					TimelineState.SelectedKeyframe = key
				end
			end

			self:RefreshAllKeyframeVisuals()
			self:RefreshAllTimelineKeyframePositions()
			if MainState.currentRig then
				self:ApplyPoseAtTime(MainState.currentRig, TimelineState.CurrentTime)
			end

			if MainState.GraphEditor then
				MainState.GraphEditor.invalidate()
			end

			MainState.currentProjectSaved = false
			motionPath.markDirty()
		end

		clearTransformState()
		local ok, err = pcall(restore, after, true)
		if not ok then
			restore(before, false)
			error(err)
		end

		History.record(function()
			restore(before, false)
		end, function()
			restore(after, true)
		end, "Scale keyframes", first, last)
	end

	function Timeline:NudgeSelectedKeyframes(delta)
		if
			BlenderEdit.blocked()
			or KeyframeTransform.active
			or self:IsExportLocked()
			or MainState.LoadingProject
			or TimelineState.Playing
			or History.isApplying()
		then
			return false
		end

		local originals = captureOriginals(self)
		if #originals == 0 then
			return false
		end

		local first, last = math.huge, -math.huge
		for _, snap in originals do
			first = math.min(first, snap.originalFrame)
			last = math.max(last, snap.originalFrame)
		end

		delta = math.clamp(math.round(delta), -first, math.max(0, self:GetMaxFrame() - last))
		if self.ConstrainGroupedDrag then
			delta = self:ConstrainGroupedDrag(delta, originals)
		end

		if not delta or delta == 0 then
			return false
		end

		KeyframeTransform.active = true
		KeyframeTransform.mode = "move"
		KeyframeTransform.originals = originals
		KeyframeTransform.liveFrames = {}
		for _, snap in originals do
			KeyframeTransform.liveFrames[snap.keyData] = snap.originalFrame + delta
		end

		self:ConfirmBlenderKeyframeTransform()
		return true
	end

	function Timeline:StartBlenderKeyframeMove()
		require("UserInputService").cancelCameraGestures()
		if BlenderEdit.blocked() then
			return
		end

		if KeyframeTransform.active then
			return false
		end

		local originals = captureOriginals(self)
		if #originals == 0 then
			return false
		end

		local mousePos = UserInputService:GetMouseLocation()

		KeyframeTransform.active = true
		KeyframeTransform.mode = "move"
		KeyframeTransform.startMouseX = mousePos.X
		KeyframeTransform.originals = originals
		KeyframeTransform.liveFrames = {}

		for _, snap in ipairs(originals) do
			KeyframeTransform.liveFrames[snap.keyData] = snap.originalFrame
		end

		return true
	end

	function Timeline:StartBlenderKeyframeScale()
		require("UserInputService").cancelCameraGestures()
		if BlenderEdit.blocked() then
			return
		end

		if KeyframeTransform.active then
			return false
		end

		local originals = captureOriginals(self)
		if #originals == 0 then
			return false
		end

		local scaleGui = self.refs and self.refs.Scale
		if not scaleGui then
			return false
		end

		local mousePos = UserInputService:GetMouseLocation()

		local pivotFrame = self:TimeToFrame(TimelineState.CurrentTime)
		local pivotPixelX = scaleGui.AbsolutePosition.X + self:FrameToVisibleX(pivotFrame)

		local startMouseX = mousePos.X

		KeyframeTransform.active = true
		KeyframeTransform.mode = "scale"
		KeyframeTransform.startMouseX = startMouseX
		KeyframeTransform.pivotFrame = pivotFrame
		KeyframeTransform.pivotPixelX = pivotPixelX
		KeyframeTransform.originals = originals
		KeyframeTransform.liveFrames = {}

		for _, snap in ipairs(originals) do
			KeyframeTransform.liveFrames[snap.keyData] = snap.originalFrame
		end

		self:BeginTimeScaleInput(mousePos, pivotPixelX, pivotFrame)
		return true
	end

	function Timeline:ProcessBlenderKeyframeTransform(mousePos)
		if not KeyframeTransform.active then
			return
		end

		if KeyframeTransform.frozen then
			return
		end

		local scaleGui = self.refs and self.refs.Scale
		if not scaleGui then
			return
		end

		local maxFrame = self:GetMaxFrame()

		local groupedDelta
		if KeyframeTransform.mode == "move" and self.ConstrainGroupedDrag then
			local start =
				self:PixelToFrame(KeyframeTransform.startMouseX - scaleGui.AbsolutePosition.X)
			local current = self:PixelToFrame(mousePos.X - scaleGui.AbsolutePosition.X)
			groupedDelta = self:ConstrainGroupedDrag(current - start, KeyframeTransform.originals)
			if groupedDelta == nil then
				return
			end
		end

		local function computeTarget(originalFrame)
			if KeyframeTransform.mode == "move" then
				local startTimelineX = KeyframeTransform.startMouseX - scaleGui.AbsolutePosition.X
				local currentTimelineX = mousePos.X - scaleGui.AbsolutePosition.X
				local startFrame = self:PixelToFrame(startTimelineX)
				local currentFrame = self:PixelToFrame(currentTimelineX)
				return math.clamp(
					originalFrame + (groupedDelta or (currentFrame - startFrame)),
					0,
					maxFrame
				)
			end

			return originalFrame
		end

		if KeyframeTransform.mode == "scale" then
			if not self:UpdateTimeScale(mousePos) then
				return
			end
		else
			local bonesByMotor = {}
			for _, snap in ipairs(KeyframeTransform.originals) do
				if snap.kind == "bone" then
					bonesByMotor[snap.motor] = bonesByMotor[snap.motor] or {}
					table.insert(bonesByMotor[snap.motor], snap)
				end
			end

			for _, snaps in pairs(bonesByMotor) do
				table.sort(snaps, function(a, b)
					return a.originalFrame < b.originalFrame
				end)
				local lastTarget = nil
				for _, snap in ipairs(snaps) do
					local target = computeTarget(snap.originalFrame)
					if lastTarget ~= nil and target <= lastTarget then
						target = lastTarget + 1
					end

					KeyframeTransform.liveFrames[snap.keyData] = math.clamp(target, 0, maxFrame)
					lastTarget = KeyframeTransform.liveFrames[snap.keyData]
				end
			end

			for _, snap in ipairs(KeyframeTransform.originals) do
				if snap.kind == "channel" then
					KeyframeTransform.liveFrames[snap.keyData] = computeTarget(snap.originalFrame)
				end
			end
		end

		local movedBoneButtons = {}
		for _, snap in ipairs(KeyframeTransform.originals) do
			local target = KeyframeTransform.liveFrames[snap.keyData] or snap.originalFrame

			if snap.keyData.Button and not movedBoneButtons[snap.keyData] then
				movedBoneButtons[snap.keyData] = true
				snap.keyData.Button.Position = UDim2.new(0, self:FrameToVisibleX(target), 0.5, 0)

				if snap.kind == "bone" then
					local channelRows = TimelineState.ChannelTracks[snap.motor]
					if channelRows then
						local channelName = "ChannelKF_" .. snap.originalFrame
						for _, row in pairs(channelRows) do
							local container = self:GetTrackKeyframesContainer(row)
							if container then
								local chBtn = container:FindFirstChild(channelName)
								if chBtn then
									chBtn.Position =
										UDim2.new(0, self:FrameToVisibleX(target), 0.5, 0)
								end
							end
						end
					end
				end
			end

			if snap.kind == "channel" then
				local channelRows = TimelineState.ChannelTracks[snap.motor]
				local row = channelRows and channelRows[snap.channelId]
				if row then
					local container = self:GetTrackKeyframesContainer(row)
					if container then
						local kfBtn = container:FindFirstChild("ChannelKF_" .. snap.originalFrame)
						if kfBtn then
							kfBtn.Position = UDim2.new(0, self:FrameToVisibleX(target), 0.5, 0)
						end
					end
				end
			end
		end

		if self.RefreshIKEndMarkerPositions then
			self:RefreshIKEndMarkerPositions()
		end

		local rig = MainState.currentRig
		if rig then
			self:ApplyLivePosePreview(rig)
		end
	end

	function Timeline:ApplyLivePosePreview(rig)
		if KeyframeTransform.scaleSession then
			return self:PreviewTimeScale(rig)
		end

		if not rig then
			return
		end

		if not KeyframeTransform.active then
			return
		end

		local boneSnapKeyDatas = {}
		local affectedMotors = {}
		for _, snap in ipairs(KeyframeTransform.originals) do
			if snap.kind ~= "channel" then
				boneSnapKeyDatas[snap.keyData] = true
				affectedMotors[snap.motor] = true
			end
		end

		local savedBuckets = {}
		for motor in pairs(affectedMotors) do
			local original = TimelineState.Keyframes[motor]
			if original then
				savedBuckets[motor] = original
				local rebuilt = {}
				for frame, keyData in pairs(original) do
					local effFrame = (
						boneSnapKeyDatas[keyData] and KeyframeTransform.liveFrames[keyData]
					) or frame
					rebuilt[effFrame] = keyData
				end

				TimelineState.Keyframes[motor] = rebuilt
			end
		end

		local savedTimes = {}
		local savedFrames = {}
		for _, snap in ipairs(KeyframeTransform.originals) do
			if snap.kind ~= "channel" then
				local keyData = snap.keyData
				local effFrame = KeyframeTransform.liveFrames[keyData] or snap.originalFrame
				savedTimes[keyData] = keyData.Time
				savedFrames[keyData] = keyData.Frame
				keyData.Time = self:FrameToTime(effFrame)
				keyData.Frame = effFrame
			end
		end

		local ok, err = pcall(function()
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		end)

		for motor, original in pairs(savedBuckets) do
			TimelineState.Keyframes[motor] = original
		end

		for keyData, t in pairs(savedTimes) do
			keyData.Time = t
		end

		for keyData, f in pairs(savedFrames) do
			keyData.Frame = f
		end

		if not ok then
			warn("ApplyLivePosePreview failed:", err)
		end
	end

	local function buildKeyframeAtFrame(
		self,
		motor,
		frame,
		c0,
		worldCFrame,
		part,
		sanitizeName,
		channels,
		parented,
		metadata
	)
		local bucket = self:GetMotorKeyframeBucket(motor)
		if not bucket then
			return nil
		end

		bucket[frame] = bucket[frame] or {}
		local keyData = bucket[frame]
		keyData.Time = self:FrameToTime(frame)
		keyData.C0 = c0
		keyData.Position = c0 and c0.Position or nil
		keyData.Rotation = c0 and (c0 - c0.Position) or nil
		keyData.Motor = motor
		keyData.Part = part
		keyData.Frame = frame
		keyData.SanitizeName = sanitizeName
		keyData.WorldCFrame = worldCFrame
		keyData.MasterWorld = metadata and metadata.MasterWorld
		keyData.Parented = parented
		keyData.Disabled = metadata and metadata.Disabled
		keyData.ChannelPoseC0 = metadata and metadata.ChannelPoseC0
		keyData.KeyGroups = metadata and GraphCurves.clone(metadata.KeyGroups)
		keyData.WholePoseScale = metadata and GraphCurves.clone(metadata.WholePoseScale)
		keyData.PhysicsLead = metadata and GraphCurves.clone(metadata.PhysicsLead)
		keyData.PhysicsTail = metadata and metadata.PhysicsTail
		keyData.GraphOnly = metadata and metadata.GraphOnly
		keyData.GraphCurves = metadata and GraphCurves.clone(metadata.GraphCurves)
		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		if metadata then
			keyData.IK = metadata.IK
			keyData.IKTarget = metadata.IKTarget
			keyData.IKPole = metadata.IKPole
			keyData.IKBaseC0 = metadata.IKBaseC0
			keyData.IKBaseWorld = metadata.IKBaseWorld
			keyData.IKAnchor = metadata.IKAnchor
			keyData.IKRigWorld = metadata.IKRigWorld
			keyData.CamTrackTo = metadata.CamTrackTo
			keyData.CamTargetEnabled = metadata.CamTargetEnabled
			keyData.CamAttachTarget = require("GraphCurves").clone(metadata.CamAttachTarget)
			keyData.FovFollowAnchor = metadata.FovFollowAnchor
			keyData.CamTargetParent = metadata.CamTargetParent
			keyData.CamTargetAnchor = metadata.CamTargetAnchor
			keyData.IKRoot = metadata.IKRoot
			keyData.IKPoleFollowsTarget = metadata.IKPoleFollowsTarget
			keyData.IKRestoreParented = metadata.IKRestoreParented
		end

		if channels then
			local newChannels = {}
			for chId, ch in pairs(channels) do
				if type(ch) == "table" then
					newChannels[chId] = GraphCurves.clone(ch)
				end
			end

			keyData.Channels = newChannels
		end

		self:CreateOrUpdateTimelineKeyframeButton(part, motor, frame, nil, sanitizeName)
		self:_addChannelDiamondAtFrame(motor, frame)

		return keyData
	end

	local function applyTransformCommit(self, originals, liveFrames)
		local entries = {}
		for _, snap in ipairs(originals) do
			if snap.kind ~= "channel" then
				local target = liveFrames[snap.keyData] or snap.originalFrame
				if target ~= snap.originalFrame then
					table.insert(entries, {
						snap = snap,
						target = target,
					})
				end
			end
		end

		if #entries == 0 then
			return false, {}
		end

		local replaced = {}
		local originalSet = {}
		for _, snap in ipairs(originals) do
			if snap.kind ~= "channel" then
				originalSet[snap.motor] = originalSet[snap.motor] or {}
				originalSet[snap.motor][snap.originalFrame] = true
			end
		end

		for _, e in ipairs(entries) do
			local bucket = TimelineState.Keyframes[e.snap.motor]
			local existing = bucket and bucket[e.target]
			local isSelfOrSelected = originalSet[e.snap.motor]
				and originalSet[e.snap.motor][e.target]
			if existing and not isSelfOrSelected then
				local channelsCopy = nil
				if existing.Channels then
					channelsCopy = {}
					for chId, ch in pairs(existing.Channels) do
						if type(ch) == "table" then
							channelsCopy[chId] = GraphCurves.clone(ch)
						end
					end
				end

				table.insert(replaced, {
					motor = e.snap.motor,
					part = existing.Part or e.snap.part,
					frame = e.target,
					c0 = existing.C0,
					worldCFrame = existing.WorldCFrame,
					MasterWorld = existing.MasterWorld,
					parented = existing.Parented,
					IK = existing.IK,
					IKTarget = existing.IKTarget,
					IKPole = existing.IKPole,
					IKBaseC0 = existing.IKBaseC0,
					IKBaseWorld = existing.IKBaseWorld,
					IKAnchor = existing.IKAnchor,
					IKRigWorld = existing.IKRigWorld,
					CamTrackTo = existing.CamTrackTo,
					CamTargetEnabled = existing.CamTargetEnabled,
					CamAttachTarget = require("GraphCurves").clone(existing.CamAttachTarget),
					FovFollowAnchor = existing.FovFollowAnchor,
					CamTargetParent = existing.CamTargetParent,
					CamTargetAnchor = existing.CamTargetAnchor,
					IKRoot = existing.IKRoot,
					IKPoleFollowsTarget = existing.IKPoleFollowsTarget,
					IKRestoreParented = existing.IKRestoreParented,
					Disabled = existing.Disabled,
					ChannelPoseC0 = existing.ChannelPoseC0,
					KeyGroups = GraphCurves.clone(existing.KeyGroups),
					WholePoseScale = GraphCurves.clone(existing.WholePoseScale),
					PhysicsLead = GraphCurves.clone(existing.PhysicsLead),
					PhysicsTail = existing.PhysicsTail,
					GraphOnly = existing.GraphOnly,
					GraphCurves = GraphCurves.clone(existing.GraphCurves),
					sanitizeName = existing.SanitizeName or e.snap.sanitizeName,
					channels = channelsCopy,
				})
			end
		end

		for i, e in ipairs(entries) do
			local parkFrame = PARK_BASE + i
			self:MoveKeyframe(
				e.snap.part,
				e.snap.motor,
				e.snap.originalFrame,
				parkFrame,
				e.snap.template,
				e.snap.sanitizeName,
				true
			)
			e.parkFrame = parkFrame
		end

		for _, e in ipairs(entries) do
			self:MoveKeyframe(
				e.snap.part,
				e.snap.motor,
				e.parkFrame,
				e.target,
				e.snap.template,
				e.snap.sanitizeName,
				true
			)
		end

		return true, replaced
	end

	function Timeline:ConfirmBlenderKeyframeTransform()
		if KeyframeTransform.scaleSession then
			return self:CommitTimeScale()
		end

		if not KeyframeTransform.active then
			return
		end

		local timeline = self
		local originalsSnapshot = KeyframeTransform.originals
		local liveFramesSnapshot = {}
		for k, v in pairs(KeyframeTransform.liveFrames) do
			liveFramesSnapshot[k] = v
		end

		local modeLabel = KeyframeTransform.mode == "scale" and "Scale" or "Move"

		local function snapshotKD(motor, frame)
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
				part = kd.Part,
				sanitizeName = kd.SanitizeName,
				c0 = kd.C0,
				worldCFrame = kd.WorldCFrame,
				MasterWorld = kd.MasterWorld,
				parented = kd.Parented,
				IK = kd.IK,
				IKTarget = kd.IKTarget,
				IKPole = kd.IKPole,
				IKBaseC0 = kd.IKBaseC0,
				IKBaseWorld = kd.IKBaseWorld,
				IKAnchor = kd.IKAnchor,
				IKRigWorld = kd.IKRigWorld,
				CamTrackTo = kd.CamTrackTo,
				CamTargetEnabled = kd.CamTargetEnabled,
				CamAttachTarget = require("GraphCurves").clone(kd.CamAttachTarget),
				FovFollowAnchor = kd.FovFollowAnchor,
				CamTargetParent = kd.CamTargetParent,
				CamTargetAnchor = kd.CamTargetAnchor,
				IKRoot = kd.IKRoot,
				IKPoleFollowsTarget = kd.IKPoleFollowsTarget,
				IKRestoreParented = kd.IKRestoreParented,
				Disabled = kd.Disabled,
				ChannelPoseC0 = kd.ChannelPoseC0,
				KeyGroups = GraphCurves.clone(kd.KeyGroups),
				WholePoseScale = GraphCurves.clone(kd.WholePoseScale),
				PhysicsLead = GraphCurves.clone(kd.PhysicsLead),
				PhysicsTail = kd.PhysicsTail,
				GraphOnly = kd.GraphOnly,
				GraphCurves = GraphCurves.clone(kd.GraphCurves),
			}
		end

		local function restoreFromSnapshot(motor, frame, snap)
			local b = TimelineState.Keyframes[motor]
			if not b then
				return
			end

			if not snap.existed then
				local kd = b[frame]
				if kd then
					if kd.Button then
						kd.Button:Destroy()
					end

					b[frame] = nil
				end

				timeline:_removeChannelDiamondAtFrame(motor, frame)
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

			kd.Channels = {}
			for chId, ch in pairs(snap.channels) do
				kd.Channels[chId] = GraphCurves.clone(ch)
			end

			kd.C0 = snap.c0 or timeline:_reconstructC0FromKeyData(kd) or kd.C0
			if kd.C0 then
				kd.Position = kd.C0.Position
				kd.Rotation = kd.C0 - kd.C0.Position
			end

			kd.Disabled, kd.ChannelPoseC0, kd.WholePoseScale =
				snap.Disabled, snap.ChannelPoseC0, GraphCurves.clone(snap.WholePoseScale)
			kd.PhysicsLead, kd.PhysicsTail = GraphCurves.clone(snap.PhysicsLead), snap.PhysicsTail
			kd.WorldCFrame = snap.worldCFrame
			kd.MasterWorld = snap.MasterWorld
			kd.Parented = snap.parented
			kd.IK = snap.IK
			kd.IKTarget = snap.IKTarget
			kd.IKPole = snap.IKPole
			kd.IKBaseC0 = snap.IKBaseC0
			kd.IKBaseWorld = snap.IKBaseWorld
			kd.IKAnchor = snap.IKAnchor
			kd.IKRigWorld = snap.IKRigWorld
			kd.CamTrackTo = snap.CamTrackTo
			kd.CamTargetEnabled = snap.CamTargetEnabled
			kd.CamAttachTarget = require("GraphCurves").clone(snap.CamAttachTarget)
			kd.FovFollowAnchor = snap.FovFollowAnchor
			kd.CamTargetParent = snap.CamTargetParent
			kd.CamTargetAnchor = snap.CamTargetAnchor
			kd.IKRoot = snap.IKRoot
			kd.IKPoleFollowsTarget = snap.IKPoleFollowsTarget
			kd.IKRestoreParented = snap.IKRestoreParented
			kd.KeyGroups = GraphCurves.clone(snap.KeyGroups)
			kd.GraphOnly, kd.GraphCurves = snap.GraphOnly, GraphCurves.clone(snap.GraphCurves)
			GraphCurves.invalidate(TimelineState.Keyframes[motor])
			timeline:CreateOrUpdateTimelineKeyframeButton(
				snap.part,
				motor,
				frame,
				nil,
				snap.sanitizeName
			)
			timeline:_addChannelDiamondAtFrame(motor, frame)
		end

		local channelTouchedFrames = {}
		local channelEntries = {}
		for _, snap in ipairs(originalsSnapshot) do
			if snap.kind == "channel" then
				local target = liveFramesSnapshot[snap.keyData] or snap.originalFrame
				if target ~= snap.originalFrame then
					channelTouchedFrames[snap.motor] = channelTouchedFrames[snap.motor] or {}
					channelTouchedFrames[snap.motor][snap.originalFrame] = true
					channelTouchedFrames[snap.motor][target] = true
					table.insert(channelEntries, {
						motor = snap.motor,
						originalFrame = snap.originalFrame,
						target = target,
						channelId = snap.channelId,
					})
				end
			end
		end

		local channelSnapshotsBefore = {}
		for motor, frameSet in pairs(channelTouchedFrames) do
			channelSnapshotsBefore[motor] = {}
			for frame in pairs(frameSet) do
				channelSnapshotsBefore[motor][frame] = snapshotKD(motor, frame)
			end
		end

		local boneChanged, replaced =
			applyTransformCommit(self, originalsSnapshot, liveFramesSnapshot)

		table.sort(channelEntries, function(a, b)
			local aDelta = a.target - a.originalFrame
			local bDelta = b.target - b.originalFrame
			if aDelta * bDelta < 0 then
				return aDelta > 0
			end

			if aDelta > 0 then
				return a.originalFrame > b.originalFrame
			end

			return a.originalFrame < b.originalFrame
		end)

		local channelChanged = false
		for _, entry in ipairs(channelEntries) do
			local peeled = self:PeelOffChannelKeyframe(
				entry.motor,
				entry.originalFrame,
				entry.target,
				entry.channelId
			)
			if peeled then
				channelChanged = true
			end
		end

		local channelSnapshotsAfter = {}
		for motor, frameSet in pairs(channelTouchedFrames) do
			channelSnapshotsAfter[motor] = {}
			for frame in pairs(frameSet) do
				channelSnapshotsAfter[motor][frame] = snapshotKD(motor, frame)
			end
		end

		for motor in pairs(channelTouchedFrames) do
			self:RefreshAllChannelDiamondsForMotor(motor)
		end

		clearTransformState()
		self:RefreshAllKeyframeVisuals()

		local rig = MainState.currentRig
		if rig then
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		end

		if not boneChanged and not channelChanged then
			return
		end

		local entries = {}
		for _, snap in ipairs(originalsSnapshot) do
			if snap.kind ~= "channel" then
				local target = liveFramesSnapshot[snap.keyData] or snap.originalFrame
				if target ~= snap.originalFrame then
					table.insert(entries, {
						motor = snap.motor,
						part = snap.part,
						originalFrame = snap.originalFrame,
						targetFrame = target,
						c0 = snap.originalC0,
						worldCFrame = snap.originalWorldCFrame,
						MasterWorld = snap.originalMasterWorld,
						parented = snap.originalParented,
						template = snap.template,
						sanitizeName = snap.sanitizeName,
					})
				end
			end
		end

		local jumpFrameForUndo = math.huge
		local jumpFrameForRedo = math.huge
		for _, e in ipairs(entries) do
			if e.originalFrame < jumpFrameForUndo then
				jumpFrameForUndo = e.originalFrame
			end

			if e.targetFrame < jumpFrameForRedo then
				jumpFrameForRedo = e.targetFrame
			end
		end

		for _, e in ipairs(channelEntries) do
			if e.originalFrame < jumpFrameForUndo then
				jumpFrameForUndo = e.originalFrame
			end

			if e.target < jumpFrameForRedo then
				jumpFrameForRedo = e.target
			end
		end

		if jumpFrameForUndo == math.huge then
			jumpFrameForUndo = nil
		end

		if jumpFrameForRedo == math.huge then
			jumpFrameForRedo = nil
		end

		local undoFn = function()
			for i, e in ipairs(entries) do
				local parkFrame = PARK_BASE + i
				timeline:MoveKeyframe(
					e.part,
					e.motor,
					e.targetFrame,
					parkFrame,
					e.template,
					e.sanitizeName,
					true
				)
				e._undoParkFrame = parkFrame
			end

			for _, e in ipairs(entries) do
				timeline:MoveKeyframe(
					e.part,
					e.motor,
					e._undoParkFrame,
					e.originalFrame,
					e.template,
					e.sanitizeName,
					true
				)
			end

			for _, r in ipairs(replaced) do
				buildKeyframeAtFrame(
					timeline,
					r.motor,
					r.frame,
					r.c0,
					r.worldCFrame,
					r.part,
					r.sanitizeName,
					r.channels,
					r.parented,
					r
				)
			end

			for motor, frames in pairs(channelSnapshotsBefore) do
				for frame, snap in pairs(frames) do
					restoreFromSnapshot(motor, frame, snap)
				end
			end

			timeline:RefreshAllKeyframeVisuals()
			motionPath.markDirty()
			local rigUndo = MainState.currentRig
			if rigUndo then
				timeline:ApplyPoseAtTime(rigUndo, TimelineState.CurrentTime)
			end
		end

		local redoFn = function()
			for i, e in ipairs(entries) do
				local parkFrame = PARK_BASE + i
				timeline:MoveKeyframe(
					e.part,
					e.motor,
					e.originalFrame,
					parkFrame,
					e.template,
					e.sanitizeName,
					true
				)
				e._redoParkFrame = parkFrame
			end

			for _, e in ipairs(entries) do
				timeline:MoveKeyframe(
					e.part,
					e.motor,
					e._redoParkFrame,
					e.targetFrame,
					e.template,
					e.sanitizeName,
					true
				)
			end

			for motor, frames in pairs(channelSnapshotsAfter) do
				for frame, snap in pairs(frames) do
					restoreFromSnapshot(motor, frame, snap)
				end
			end

			timeline:RefreshAllKeyframeVisuals()
			motionPath.markDirty()
			local rigRedo = MainState.currentRig
			if rigRedo then
				timeline:ApplyPoseAtTime(rigRedo, TimelineState.CurrentTime)
			end
		end

		local totalCount = #entries + #channelEntries
		local desc = (totalCount > 1) and (modeLabel .. " " .. tostring(totalCount) .. " keyframes")
			or (modeLabel .. " keyframe")

		History.record(undoFn, redoFn, desc, jumpFrameForUndo, jumpFrameForRedo)
	end

	function Timeline:CancelBlenderKeyframeTransform()
		if not KeyframeTransform.active then
			return
		end

		local resetButtons = {}
		for _, snap in ipairs(KeyframeTransform.originals) do
			if snap.keyData and snap.keyData.Button and not resetButtons[snap.keyData] then
				resetButtons[snap.keyData] = true
				snap.keyData.Button.Position =
					UDim2.new(0, self:FrameToVisibleX(snap.originalFrame), 0.5, 0)
			end

			if snap.kind == "channel" then
				local channelRows = TimelineState.ChannelTracks[snap.motor]
				local row = channelRows and channelRows[snap.channelId]
				if row then
					local container = self:GetTrackKeyframesContainer(row)
					if container then
						local kfBtn = container:FindFirstChild("ChannelKF_" .. snap.originalFrame)
						if kfBtn then
							kfBtn.Position =
								UDim2.new(0, self:FrameToVisibleX(snap.originalFrame), 0.5, 0)
						end
					end
				end
			end
		end

		clearTransformState()
		self:RefreshAllKeyframeVisuals()

		local rig = MainState.currentRig
		if rig then
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		end
	end

	function Timeline:BindBlenderKeyframeTransform()
		if TimelineState._BlenderKFTransformBound then
			return
		end

		TimelineState._BlenderKFTransformBound = true
		UserInputService.WindowFocusReleased:Connect(function()
			if KeyframeTransform.active then
				self:CancelBlenderKeyframeTransform()
			end
		end)

		local timeline = self

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not KeyframeTransform.active then
				return
			end

			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				KeyframeTransform.frozen = true
				task.defer(function()
					if KeyframeTransform.active then
						timeline:ConfirmBlenderKeyframeTransform()
					end
				end)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				KeyframeTransform.frozen = true
				task.defer(function()
					if KeyframeTransform.active then
						timeline:CancelBlenderKeyframeTransform()
					end
				end)
			elseif input.UserInputType == Enum.UserInputType.Keyboard then
				if Shortcuts.matches("Cancel", input) then
					KeyframeTransform.frozen = true
					task.defer(function()
						if KeyframeTransform.active then
							timeline:CancelBlenderKeyframeTransform()
						end
					end)
				end
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if not KeyframeTransform.active then
				return
			end

			if input.UserInputType == Enum.UserInputType.MouseMovement then
				timeline:ProcessBlenderKeyframeTransform(UserInputService:GetMouseLocation())
			end
		end)
	end
end
