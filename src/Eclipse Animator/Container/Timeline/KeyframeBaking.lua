--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")
local CameraRig = require("CameraRig")
local Properties = require("Properties")
local BlenderCurve = require("BlenderCurve")
local KeyframePolicy = require("Policy")
local ArmatureRuntime = require("ArmatureRuntime")
local ArmatureAnimation = require("ArmatureAnimation")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")
local Motion = require("Motion")

local State = require("RawState")
local Interp = require("Interp")
local PivotSpace = require("PivotSpace")
local GraphCurves = require("GraphCurves")
local BoneMotor = require("BoneMotor")
local Parenting = require("Parenting")
local LimbIK = require("LimbIK")
local EventDependencies = require("EventDependencies")
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

local CHANNEL_IDS = {
	"loc_x",
	"loc_y",
	"loc_z",
	"qrot_w",
	"qrot_x",
	"qrot_y",
	"qrot_z",
	"scale_x",
	"scale_y",
	"scale_z",
}
local CFRAME_IDS = { "loc_x", "loc_y", "loc_z", "qrot_w", "qrot_x", "qrot_y", "qrot_z" }
local QROT_IDS = { "qrot_w", "qrot_x", "qrot_y", "qrot_z" }
local SCALE_IDS = { "scale_x", "scale_y", "scale_z" }

local scratchPrevFrame = {}
local scratchPrevValue = {}
local scratchPrevTime = {}
local scratchNextFrame = {}
local scratchNextValue = {}
local scratchNextTime = {}
local scratchValues = {}
local scratchDisabled = {}

local defaultDecomposedCache = setmetatable({}, { __mode = "k" })

local motorListCache = setmetatable({}, { __mode = "k" })

local function releaseMotorCache(entry)
	if entry.released then
		return
	end

	entry.released = true
	for _, connection in ipairs(entry.connections) do
		connection:Disconnect()
	end

	for _, connections in pairs(entry.joints) do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end

	table.clear(entry.connections)
	table.clear(entry.joints)
	entry.list = nil
end

local function getCachedMotorList(rig)
	if Properties.propertyOnly(rig) then
		return {}
	end

	local entry = motorListCache[rig]
	if not entry then
		entry = { connections = {}, joints = {} }
		motorListCache[rig] = entry

		local function watch(item)
			if entry.released then
				return
			end

			if item:IsA("Motor6D") then
				entry.list = nil
				if entry.joints[item] then
					return
				end

				local function changed()
					entry.list = nil
				end

				entry.joints[item] = {
					item:GetPropertyChangedSignal("Part0"):Connect(changed),
					item:GetPropertyChangedSignal("Part1"):Connect(changed),
				}
			elseif item:IsA("Bone") then
				entry.list = nil
			end
		end

		table.insert(entry.connections, rig.DescendantAdded:Connect(watch))
		table.insert(
			entry.connections,
			rig.DescendantRemoving:Connect(function(item)
				if entry.released then
					return
				end

				if item:IsA("Motor6D") or item:IsA("Bone") then
					entry.list = nil
				end

				local connections = entry.joints[item]
				if connections then
					for _, connection in ipairs(connections) do
						connection:Disconnect()
					end

					entry.joints[item] = nil
				end
			end)
		)
		table.insert(
			entry.connections,
			rig.Destroying:Connect(function()
				releaseMotorCache(entry)
				if motorListCache[rig] == entry then
					motorListCache[rig] = nil
				end
			end)
		)
		for _, item in ipairs(RigTraversal.rigDescendants(rig)) do
			watch(item)
		end
	end

	if not entry.list then
		entry.list = Parenting.collectMotors(rig)
	end

	return entry.list
end

local function invalidateMotorListCache()
	for _, entry in pairs(motorListCache) do
		releaseMotorCache(entry)
	end

	table.clear(motorListCache)
end

local function getDefaultDecomposed(motor, decomposeFn, evaluationState)
	local TimelineState = evaluationState or TimelineState
	local defaultC0 = TimelineState.DefaultPose[motor] or motor.C0 or CFrame.new()
	local cached = defaultDecomposedCache[motor]
	if cached and cached._cf == defaultC0 then
		return cached, defaultC0
	end

	cached = decomposeFn(defaultC0)
	cached._cf = defaultC0
	defaultDecomposedCache[motor] = cached
	return cached, defaultC0
end

return function(Timeline)
	function Timeline:IsDraggingPlayhead()
		return PlayheadDrag.draggingPlayhead
	end

	function Timeline:SetDraggingPlayhead(state)
		PlayheadDrag.draggingPlayhead = state and true or false
	end

	local SNAP_PIXEL_THRESHOLD = 8

	function Timeline:SnapXToNearestKeyframe(x)
		local frames = self:GetAllKeyframeFrames()
		if #frames == 0 then
			return x
		end

		local bestX = nil
		local bestDist = math.huge
		for _, frame in ipairs(frames) do
			local frameX = self:FrameToVisibleX(frame)
			local dist = math.abs(frameX - x)
			if dist < bestDist and dist <= SNAP_PIXEL_THRESHOLD then
				bestDist = dist
				bestX = frameX
			end
		end

		return bestX or x
	end

	function Timeline:GetClickReferenceX()
		local sc = self.refs.SelectorContainer
		if not sc then
			local visibleFrame = self:GetVisibleTimelineFrame()
			return visibleFrame and visibleFrame.AbsolutePosition.X or 0
		end

		local padding = 0
		local p = sc:FindFirstChildOfClass("UIPadding")
		if p then
			padding = p.PaddingLeft.Offset
		end

		return (self.refs.Scale or sc).AbsolutePosition.X + padding * Motion.scale(sc)
	end

	function Timeline:JumpPlayheadToVisibleX(x, currentRigGetter)
		if self:IsExportLocked() then
			return
		end

		local width = self:GetVisibleTimelineWidth()
		local clampedX = math.clamp(x, 0, width)
		local frame = self:VisibleXToFrame(clampedX)
		local maxFrame = self:GetMaxFrame()
		frame = math.clamp(frame, 0, maxFrame)
		local time = self:FrameToTime(frame)
		if TimelineState.CurrentTime == time then
			return
		end

		TimelineState.CurrentTime = time
		local rig = currentRigGetter and currentRigGetter() or nil
		if rig then
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		end

		self:UpdatePlayhead()
		if not TimelineState.Playing then
			require("EventPlayback").scrub(self, time)
		end
	end

	function Timeline:StepPlayheadDrag(dt, point, currentRigGetter)
		if not PlayheadDrag.draggingPlayhead then
			return
		end

		if self:IsExportLocked() then
			self:SetDraggingPlayhead(false)
			return
		end

		local viewport = self.refs.TimelineContainer
		if not viewport then
			return
		end

		local factor = Motion.scale(viewport)
		local left = viewport.AbsolutePosition.X + 20 * factor
		local right =
			math.max(left, viewport.AbsolutePosition.X + viewport.AbsoluteSize.X - 20 * factor)
		local band = math.min(18 * factor, (right - left) / 2)
		local speed = 0
		if band > 0 then
			if point.X < left + band then
				speed = -math.clamp((left + band - point.X) / band, 0, 3) * 420
			elseif point.X > right - band then
				speed = math.clamp((point.X - right + band) / band, 0, 3) * 420
			end
		end

		local previous = TimelineState.ScrollOffset
		local x = (math.clamp(point.X, left, right) - self:GetClickReferenceX()) / factor
		if speed ~= 0 then
			self:SetTimelineScroll(previous + speed * math.clamp(dt or 0, 0, 0.05))
		end

		self:JumpPlayheadToVisibleX(x + TimelineState.ScrollOffset - previous, currentRigGetter)
	end

	function Timeline:BindPlayhead(currentRigGetter)
		if self.refs._TimelinePlayheadBound then
			return
		end

		self.refs._TimelinePlayheadBound = true

		local dragButton = self.refs.TopSelectorDragHitbox
		if not dragButton then
			return
		end

		dragButton.MouseButton1Down:Connect(function()
			if self:IsExportLocked() then
				return
			end

			PlayheadDrag.draggingPlayhead = true
			TimelineState.Playing = false

			self:StepPlayheadDrag(0, UserInputService:GetMouseLocation(), currentRigGetter)
			PlayheadDrag.playheadMouseOffsetX = 0
		end)

		local inputConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				PlayheadDrag.draggingPlayhead = false
				PlayheadDrag.playheadMouseOffsetX = 0
			end
		end)

		local function finishDrag()
			PlayheadDrag.draggingPlayhead = false
			PlayheadDrag.playheadMouseOffsetX = 0
		end

		local focusConnection = UserInputService.WindowFocusReleased:Connect(finishDrag)
		local renderConnection = RunService.RenderStepped:Connect(function(dt)
			self:StepPlayheadDrag(dt, UserInputService:GetMouseLocation(), currentRigGetter)
		end)
		dragButton.Destroying:Once(function()
			invalidateMotorListCache()
			inputConnection:Disconnect()
			renderConnection:Disconnect()
			focusConnection:Disconnect()
			finishDrag()
		end)
	end

	function Timeline:UpdatePlayhead()
		local selector = self.refs.Selector
		local topSelector = self.refs.TopSelector
		local label = self.refs.TopSelectorLabel
		local fpsLabel = self.refs.FPSLabel
		local timeLabel = self.refs.TimeLabel

		if not selector or not topSelector then
			return
		end

		local frame = self:TimeToFrame(TimelineState.CurrentTime)
		self:PositionPlayhead()

		if label then
			label.Text = tostring(frame)
		end

		if fpsLabel and not (fpsLabel:IsA("TextBox") and fpsLabel:IsFocused()) then
			fpsLabel.Text = tostring(TimelineState.FPS) .. " FPS"
		end

		if timeLabel then
			local milliseconds = math.floor(math.max(0, TimelineState.CurrentTime) * 1000 + 0.5)
			local minutes = math.floor(milliseconds / 60000)
			local seconds = math.floor(milliseconds / 1000) % 60
			timeLabel.Text = string.format("%02d:%02d.%03d", minutes, seconds, milliseconds % 1000)
		end
	end

	function Timeline:InvalidateMotorListCache()
		invalidateMotorListCache()
	end

	local function indexedChannels(self, bucket, time, ids, populate, hasDisabled)
		local cache = require("cache").poseCache()
		if not cache or not cache.persistent then
			return nil
		end

		local ordered = Interp.index(bucket)
		if not ordered then
			return nil
		end

		cache.legacyChannels = cache.legacyChannels or setmetatable({}, { __mode = "k" })
		local entry = cache.legacyChannels[bucket]
		if not entry or populate and not entry.populated then
			entry = { populated = populate, channels = {} }
			for _, row in ordered do
				if populate then
					self:EnsureChannelsPopulated(row.key)
				end

				for id, channel in row.key.Channels or {} do
					if channel.Value ~= nil then
						local index = entry.channels[id]
						if not index then
							index = {}
							entry.channels[id] = index
						end

						table.insert(index, row)
					end
				end
			end

			cache.legacyChannels[bucket] = entry
		end

		local any = false
		for _, id in ids do
			local index = entry.channels[id]
			if not index or #index == 0 or hasDisabled and scratchDisabled[id] then
				continue
			end

			any = true
			local p, n = Interp.search(index, time)
			local previous, following = index[p], index[n]
			if previous then
				scratchPrevFrame[id] = previous.frame
				scratchPrevTime[id] = previous.time
				scratchPrevValue[id] = previous.key.Channels[id].Value
			end

			if following then
				scratchNextFrame[id] = following.frame
				scratchNextTime[id] = following.time
				scratchNextValue[id] = following.key.Channels[id].Value
			end
		end

		return any
	end

	local function evaluateLegacyMotorC0(self, motor, time, loopEndTime, bucket, evaluationState)
		local TimelineState = evaluationState or TimelineState

		if not bucket or not next(bucket) then
			return TimelineState.DefaultPose[motor] or motor.C0, false
		end

		local defaultDecomposed, defaultC0 = getDefaultDecomposed(motor, function(cf)
			return self:DecomposeC0(cf)
		end, TimelineState)

		local hasDisabled = false
		if motor:GetAttribute("EclipseChannelDisabledAny") then
			hasDisabled = true
			table.clear(scratchDisabled)
			for _, chId in ipairs(CHANNEL_IDS) do
				if motor:GetAttribute("EclipseChannelDisabled_" .. chId) then
					scratchDisabled[chId] = true
				end
			end
		end

		if not hasDisabled then
			local uniformFlag = TimelineState._motorUniform[motor]
			if uniformFlag == nil then
				uniformFlag = true
				for _, keyData in pairs(bucket) do
					self:EnsureChannelsPopulated(keyData)
					local channels = keyData.Channels
					if not channels then
						uniformFlag = false
						break
					end

					for _, chId in ipairs(CFRAME_IDS) do
						local ch = channels[chId]
						if not ch or ch.Value == nil or ch.Easing then
							uniformFlag = false
							break
						end
					end

					if not uniformFlag then
						break
					end
				end

				TimelineState._motorUniform[motor] = uniformFlag
			end

			if uniformFlag then
				local prevFrame, nextFrame = nil, nil
				local index = Interp.index(bucket)
				if index then
					local p, n = Interp.search(index, time)
					prevFrame = index[p] and index[p].frame
					nextFrame = index[n] and index[n].frame
				else
					for kfFrame, keyData in pairs(bucket) do
						if keyData.Time <= time and (not prevFrame or kfFrame > prevFrame) then
							prevFrame = kfFrame
						end

						if keyData.Time >= time and (not nextFrame or kfFrame < nextFrame) then
							nextFrame = kfFrame
						end
					end
				end

				if prevFrame and not nextFrame then
					return bucket[prevFrame].C0 or defaultC0, true
				end

				if nextFrame and not prevFrame then
					return bucket[nextFrame].C0 or defaultC0, true
				end

				if prevFrame == nextFrame and prevFrame then
					return bucket[prevFrame].C0 or defaultC0, true
				end

				if prevFrame and nextFrame then
					local prevKd = bucket[prevFrame]
					local nextKd = bucket[nextFrame]
					if prevKd.C0 and nextKd.C0 then
						local rawAlpha = 0
						if nextKd.Time and prevKd.Time and nextKd.Time > prevKd.Time then
							rawAlpha =
								math.clamp((time - prevKd.Time) / (nextKd.Time - prevKd.Time), 0, 1)
						end

						local smoothed =
							Interp.cframe(bucket, prevKd, nextKd, rawAlpha, "C0", loopEndTime)
						if smoothed then
							return smoothed, true
						end
					end
				end
			end
		end

		table.clear(scratchPrevFrame)
		table.clear(scratchPrevValue)
		table.clear(scratchPrevTime)
		table.clear(scratchNextFrame)
		table.clear(scratchNextValue)
		table.clear(scratchNextTime)
		local anyKeyframed = false

		local indexed = indexedChannels(self, bucket, time, CHANNEL_IDS, true, hasDisabled)
		if indexed ~= nil then
			anyKeyframed = indexed
		else
			for kfFrame, keyData in pairs(bucket) do
				self:EnsureChannelsPopulated(keyData)
				local channels = keyData.Channels
				if channels then
					local kfTime = keyData.Time
					local isPrev = keyData.Time <= time
					local isNext = keyData.Time >= time
					for _, chId in ipairs(CHANNEL_IDS) do
						if not (hasDisabled and scratchDisabled[chId]) then
							local ch = channels[chId]
							if ch and ch.Value ~= nil then
								anyKeyframed = true
								if isPrev then
									local existing = scratchPrevFrame[chId]
									if not existing or kfFrame > existing then
										scratchPrevFrame[chId] = kfFrame
										scratchPrevValue[chId] = ch.Value
										scratchPrevTime[chId] = kfTime
									end
								end

								if isNext then
									local existing = scratchNextFrame[chId]
									if not existing or kfFrame < existing then
										scratchNextFrame[chId] = kfFrame
										scratchNextValue[chId] = ch.Value
										scratchNextTime[chId] = kfTime
									end
								end
							end
						end
					end
				end
			end
		end

		if not anyKeyframed then
			return defaultC0, false
		end

		local cframeShared = true
		local sharedCFramePrev, sharedCFrameNext
		for _, cid in ipairs(CFRAME_IDS) do
			if hasDisabled and scratchDisabled[cid] then
				cframeShared = false
				break
			end

			local pFrame = scratchPrevFrame[cid]
			local nFrame = scratchNextFrame[cid]
			if
				pFrame and bucket[pFrame].Channels[cid].Easing
				or nFrame and bucket[nFrame].Channels[cid].Easing
			then
				cframeShared = false
				break
			end

			if not pFrame or not nFrame then
				cframeShared = false
				break
			end

			if sharedCFramePrev == nil then
				sharedCFramePrev = pFrame
				sharedCFrameNext = nFrame
			elseif pFrame ~= sharedCFramePrev or nFrame ~= sharedCFrameNext then
				cframeShared = false
				break
			end
		end

		if cframeShared and sharedCFramePrev then
			local prevKeyData = bucket[sharedCFramePrev]
			local nextKeyData = bucket[sharedCFrameNext]
			if
				prevKeyData
				and nextKeyData
				and prevKeyData.C0
				and nextKeyData.C0
				and not Interp.usesAutomaticBezier(prevKeyData, nextKeyData)
			then
				local rawAlpha = 0
				if
					sharedCFramePrev ~= sharedCFrameNext
					and nextKeyData.Time
					and prevKeyData.Time
					and nextKeyData.Time > prevKeyData.Time
				then
					rawAlpha = math.clamp(
						(time - prevKeyData.Time) / (nextKeyData.Time - prevKeyData.Time),
						0,
						1
					)
				end

				local smoothed =
					Interp.cframe(bucket, prevKeyData, nextKeyData, rawAlpha, "C0", loopEndTime)
				if smoothed then
					return smoothed, true
				end
			end
		end

		local qrotShared = true
		local sharedPrevFrame, sharedNextFrame
		for _, qid in ipairs(QROT_IDS) do
			if hasDisabled and scratchDisabled[qid] then
				qrotShared = false
				break
			end

			local pFrame = scratchPrevFrame[qid]
			local nFrame = scratchNextFrame[qid]
			if not pFrame or not nFrame then
				qrotShared = false
				break
			end

			if sharedPrevFrame == nil then
				sharedPrevFrame = pFrame
				sharedNextFrame = nFrame
			elseif pFrame ~= sharedPrevFrame or nFrame ~= sharedNextFrame then
				qrotShared = false
				break
			end
		end

		if qrotShared then
			local dot = scratchPrevValue.qrot_w * scratchNextValue.qrot_w
				+ scratchPrevValue.qrot_x * scratchNextValue.qrot_x
				+ scratchPrevValue.qrot_y * scratchNextValue.qrot_y
				+ scratchPrevValue.qrot_z * scratchNextValue.qrot_z
			if dot < 0 then
				scratchNextValue.qrot_w = -scratchNextValue.qrot_w
				scratchNextValue.qrot_x = -scratchNextValue.qrot_x
				scratchNextValue.qrot_y = -scratchNextValue.qrot_y
				scratchNextValue.qrot_z = -scratchNextValue.qrot_z
			end
		end

		table.clear(scratchValues)
		for _, chId in ipairs(CHANNEL_IDS) do
			local pFrame = scratchPrevFrame[chId]
			local nFrame = scratchNextFrame[chId]
			local pTime = scratchPrevTime[chId]
			local nTime = scratchNextTime[chId]
			local pValue = scratchPrevValue[chId]
			local nValue = scratchNextValue[chId]
			if pFrame and nFrame and pFrame ~= nFrame and nTime > pTime then
				local alpha = math.clamp((time - pTime) / (nTime - pTime), 0, 1)
				local prevKeyData = bucket[pFrame]
				scratchValues[chId] = Interp.channel(
					bucket,
					prevKeyData,
					bucket[nFrame],
					alpha,
					chId,
					pValue,
					nValue,
					loopEndTime
				)
			elseif pFrame then
				scratchValues[chId] = pValue
			elseif nFrame then
				scratchValues[chId] = nValue
			else
				scratchValues[chId] = defaultDecomposed[chId]
			end
		end

		do
			local pKd, nKd = nil, nil
			local index = Interp.index(bucket, "C0")
			if index then
				local p, n = Interp.search(index, time)
				pKd, nKd = index[p] and index[p].key, index[n] and index[n].key
			else
				for _, keyData in pairs(bucket) do
					if keyData and keyData.C0 and keyData.Time then
						if keyData.Time <= time and (not pKd or keyData.Time > pKd.Time) then
							pKd = keyData
						end

						if keyData.Time >= time and (not nKd or keyData.Time < nKd.Time) then
							nKd = keyData
						end
					end
				end
			end

			local manual = (pKd and pKd.PathTangentOut ~= nil) or (nKd and nKd.PathTangentIn ~= nil)
			local locDisabled = hasDisabled
				and (scratchDisabled.loc_x or scratchDisabled.loc_y or scratchDisabled.loc_z)

			if not manual then
				local pF, nF = nil, nil
				for _, chId in ipairs(CHANNEL_IDS) do
					pF = pF or scratchPrevFrame[chId]
					nF = nF or scratchNextFrame[chId]
				end

				local locConsistent = true
				for _, chId in ipairs({ "loc_x", "loc_y", "loc_z" }) do
					local pp = scratchPrevFrame[chId]
					local nn = scratchNextFrame[chId]
					if pp ~= pF or nn ~= nF then
						locConsistent = false
						break
					end
				end

				if locConsistent and pF and nF then
					pKd, nKd = bucket[pF], bucket[nF]
				else
					pKd, nKd = nil, nil
				end
			end

			if
				not locDisabled
				and pKd
				and nKd
				and pKd ~= nKd
				and pKd.C0
				and nKd.C0
				and not Interp.usesAutomaticBezier(pKd, nKd)
				and pKd.Time
				and nKd.Time
				and nKd.Time > pKd.Time
			then
				local rawA = math.clamp((time - pKd.Time) / (nKd.Time - pKd.Time), 0, 1)
				local cf = Interp.cframe(bucket, pKd, nKd, rawA, "C0", loopEndTime)
				if cf then
					for _, axis in { "x", "y", "z" } do
						local id = "loc_" .. axis
						local a = pKd.Channels and pKd.Channels[id]
						local b = nKd.Channels and nKd.Channels[id]
						if not (a and a.Easing or b and b.Easing) then
							scratchValues[id] = cf.Position[axis:upper()]
						end
					end
				end
			end
		end

		return self:ReconstructC0(scratchValues), true
	end

	local function evaluateLegacyScale(self, motor, time, loopEndTime, bucket)
		if not bucket or not next(bucket) then
			return nil
		end

		local cache = require("cache").poseCache()
		if cache then
			cache.scalePresence = cache.scalePresence or setmetatable({}, { __mode = "k" })
		end

		local hasScaleFlag
		if cache then
			hasScaleFlag = cache.scalePresence[bucket]
		else
			hasScaleFlag = TimelineState._motorHasScale[motor]
		end

		if hasScaleFlag == nil then
			hasScaleFlag = false
			for _, keyData in pairs(bucket) do
				local channels = keyData.Channels
				if channels then
					for _, chId in ipairs(SCALE_IDS) do
						local ch = channels[chId]
						if
							ch
							and typeof(ch.Value) == "number"
							and math.abs(ch.Value - 1) > 1e-6
						then
							hasScaleFlag = true
							break
						end
					end

					if hasScaleFlag then
						break
					end
				end
			end

			TimelineState._motorHasScale[motor] = hasScaleFlag
			if cache then
				cache.scalePresence[bucket] = hasScaleFlag
			end
		end

		if not hasScaleFlag then
			return nil
		end

		local hasDisabled = false
		if motor:GetAttribute("EclipseChannelDisabledAny") then
			hasDisabled = true
			table.clear(scratchDisabled)
			for _, chId in ipairs(SCALE_IDS) do
				if motor:GetAttribute("EclipseChannelDisabled_" .. chId) then
					scratchDisabled[chId] = true
				end
			end
		end

		table.clear(scratchPrevFrame)
		table.clear(scratchPrevValue)
		table.clear(scratchPrevTime)
		table.clear(scratchNextFrame)
		table.clear(scratchNextValue)
		table.clear(scratchNextTime)
		local anyScale = false

		local indexed = indexedChannels(self, bucket, time, SCALE_IDS, false, hasDisabled)
		if indexed ~= nil then
			anyScale = indexed
		else
			for kfFrame, keyData in pairs(bucket) do
				local channels = keyData.Channels
				if channels then
					local kfTime = keyData.Time
					local isPrev = keyData.Time <= time
					local isNext = keyData.Time >= time
					for _, chId in ipairs(SCALE_IDS) do
						if not (hasDisabled and scratchDisabled[chId]) then
							local ch = channels[chId]
							if ch and ch.Value ~= nil then
								anyScale = true
								if isPrev then
									local existing = scratchPrevFrame[chId]
									if not existing or kfFrame > existing then
										scratchPrevFrame[chId] = kfFrame
										scratchPrevValue[chId] = ch.Value
										scratchPrevTime[chId] = kfTime
									end
								end

								if isNext then
									local existing = scratchNextFrame[chId]
									if not existing or kfFrame < existing then
										scratchNextFrame[chId] = kfFrame
										scratchNextValue[chId] = ch.Value
										scratchNextTime[chId] = kfTime
									end
								end
							end
						end
					end
				end
			end
		end

		if not anyScale then
			return nil
		end

		local out = {}
		for _, chId in ipairs(SCALE_IDS) do
			local pFrame = scratchPrevFrame[chId]
			local nFrame = scratchNextFrame[chId]
			local pTime = scratchPrevTime[chId]
			local nTime = scratchNextTime[chId]
			local pValue = scratchPrevValue[chId]
			local nValue = scratchNextValue[chId]
			if pFrame and nFrame and pFrame ~= nFrame and nTime > pTime then
				local alpha = math.clamp((time - pTime) / (nTime - pTime), 0, 1)
				local prevKeyData = bucket[pFrame]
				out[chId] = Interp.channel(
					bucket,
					prevKeyData,
					bucket[nFrame],
					alpha,
					chId,
					pValue,
					nValue,
					loopEndTime
				)
			elseif pFrame then
				out[chId] = pValue
			elseif nFrame then
				out[chId] = nValue
			else
				out[chId] = 1
			end
		end

		return out
	end

	function Timeline:EvaluateMotorC0(motor, time, bucketOverride, loopEndTime)
		local value, keyed = self:EvaluateMotorJointC0(motor, time, bucketOverride, loopEndTime)
		local offset = value and PivotSpace.jointOffset(motor)
		if not offset then
			return value, keyed
		end

		if PivotSpace.blocked(motor, time) then
			return value, keyed
		end

		if not bucketOverride and require("Layers").has(TimelineState) then
			return value, keyed
		end

		local bucket = KeyframePolicy.activeBucket(bucketOverride or TimelineState.Keyframes[motor])
		if not bucket then
			return value, keyed
		end

		local previous, following = Parenting.bounds(bucket, time)
		if
			not previous
			or not following
			or previous == following
			or following.Time <= previous.Time
		then
			return value, keyed
		end

		return PivotSpace.correct(
			bucket,
			previous,
			following,
			math.clamp((time - previous.Time) / (following.Time - previous.Time), 0, 1),
			"C0",
			loopEndTime,
			offset,
			value
		),
			keyed
	end

	function Timeline:EvaluateMotorJointC0(
		motor,
		time,
		bucketOverride,
		loopEndTime,
		evaluationState
	)
		local TimelineState = evaluationState or TimelineState
		local Layers = require("Layers")
		if not bucketOverride and Layers.has(TimelineState) then
			return Layers.c0(self, motor, time, loopEndTime)
		end

		if Properties.is(motor) then
			return Properties.encode(
				Properties.evaluate(
					motor,
					bucketOverride or TimelineState.Keyframes[motor],
					time,
					loopEndTime
				)
			),
				true
		end

		local bucket = KeyframePolicy.activeBucket(bucketOverride or TimelineState.Keyframes[motor])
		local section = LimbIK.controlBucket(motor, time, bucket, TimelineState.Keyframes)
		if section ~= bucket then
			loopEndTime = nil
		end

		bucket = section
		local imported = BlenderCurve.evaluate(bucket, time)
		if imported then
			return imported, true
		end

		TimelineState._evaluationBuckets = TimelineState._evaluationBuckets
			or setmetatable({}, { __mode = "kv" })
		if TimelineState._evaluationBuckets[motor] ~= bucket then
			TimelineState._motorUniform[motor] = nil
			TimelineState._motorHasScale[motor] = nil
			TimelineState._evaluationBuckets[motor] = bucket
		end

		local legacy = GraphCurves.legacyBucket(bucket)
		local cf, keyed =
			evaluateLegacyMotorC0(self, motor, time, loopEndTime, legacy, TimelineState)
		if not GraphCurves.compile(bucket).hasGraph then
			return cf, keyed
		end

		return GraphCurves.cframe(
			bucket,
			time,
			cf,
			motor,
			loopEndTime,
			TimelineState.DefaultPose[motor]
		),
			true
	end

	function Timeline:CreatePreviewSampler(motor, bucket, rest)
		local context = {
			DefaultPose = { [motor] = rest },
			Keyframes = { [motor] = bucket },
			ParentingDefaults = { [motor] = true },
			_motorUniform = {},
			_motorHasScale = {},
		}
		self:EnsureTransformChannelStarts(motor, context)
		return function(time)
			return self:EvaluateMotorJointC0(motor, time, bucket, nil, context)
		end
	end

	function Timeline:EvaluateMotorScale(motor, time, bucketOverride, loopEndTime)
		local Layers = require("Layers")
		if not bucketOverride and Layers.has(TimelineState) then
			return Layers.scale(self, motor, time, loopEndTime)
		end

		if bucketOverride then
			TimelineState._motorHasScale[motor] = nil
		end

		local bucket = KeyframePolicy.activeBucket(bucketOverride or TimelineState.Keyframes[motor])
		local _, scale = BlenderCurve.evaluate(bucket, time)
		if scale then
			return { scale_x = scale.X, scale_y = scale.Y, scale_z = scale.Z }
		end

		local legacy = GraphCurves.legacyBucket(bucket)
		local scale = evaluateLegacyScale(self, motor, time, loopEndTime, legacy)
		if not GraphCurves.compile(bucket).hasGraph then
			return scale
		end

		return GraphCurves.scale(bucket, time, scale, motor, loopEndTime)
	end

	function Timeline:ApplyPoseAtTime(rig, time, options)
		time = self:GetPoseTime(time)
		return require("cache").withPose(function()
			return self:_ApplyPoseAtTimeCached(rig, time, options)
		end)
	end

	function Timeline:_ApplyPoseAtTimeCached(rig, time, options)
		return EventDependencies.withPose(function()
			return require("Layers").withPose(self, time, function()
				return self:_ApplyPoseAtTimeUnlayered(rig, time, options)
			end)
		end)
	end

	function Timeline:_ApplyPoseAtTimeUnlayered(rig, time, options)
		if not rig then
			return
		end

		TimelineState.LastPoseApplyClock = os.clock()

		local loopEndTime = self:IsLooping() and self:GetPlaybackEndTime() or nil

		local function getEvaluatedMotorC0(motor, sampleTime)
			return self:EvaluateMotorC0(motor, sampleTime or time, nil, loopEndTime)
		end

		local function getEvaluatedPartScale(motor)
			return self:EvaluateMotorScale(motor, time, nil, loopEndTime)
		end

		local propertyRigs = not (options and options.OnlyRig)
				and self.refs.GetAllRigs
				and self.refs.GetAllRigs()
			or { rig }
		local propertySamples = require("Target").propertySampleCache()
		local placed = {}
		for _, target in propertyRigs do
			placed[target] = Properties.beginPose(target, TimelineState, time, loopEndTime, propertySamples)
			require("Faces").apply(target, time, TimelineState.FPS)
		end

		local descendants = getCachedMotorList(rig)
		local allRigs = not (options and options.OnlyRig)
				and self.refs.GetAllRigs
				and self.refs.GetAllRigs()
			or nil
		if allRigs and #allRigs > 1 then
			local combined = {}
			for _, otherRig in ipairs(allRigs) do
				for _, m in ipairs(getCachedMotorList(otherRig)) do
					table.insert(combined, m)
				end
			end

			descendants = combined
		end

		local propertyFiltered = {}
		for _, motor in descendants do
			local name = typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Name
			local owner = (name == "FovPart" or name == "CamPart") and CameraRig and CameraRig.owner(motor)
			local id = owner
				and (
					CameraRig.isFov(motor) and "FieldOfView"
					or CameraRig.isTransform(motor) and "CFrame"
				)
			if not id or Properties.enabled(owner, id) then
				table.insert(propertyFiltered, motor)
			end
		end

		descendants = propertyFiltered
		local isObjectMotorActive = self.refs.IsObjectMotorActive
		if isObjectMotorActive then
			local filtered = table.create(#descendants)
			for _, m in ipairs(descendants) do
				if m:GetAttribute("EclipseAddedObject") ~= true or isObjectMotorActive(m) then
					table.insert(filtered, m)
				end
			end

			descendants = filtered
		end

		local evaluator
		require("MasterControl").withPose(propertyRigs, function()
			evaluator = Parenting.newEvaluator(
				descendants,
				KeyframePolicy.activeTracks(TimelineState.Keyframes),
				TimelineState.DefaultPose,
				TimelineState.DefaultWorldPose,
				TimelineState.ParentingDefaults,

				function(motor, sampleTime)
					return getEvaluatedMotorC0(motor, sampleTime)
				end,
				loopEndTime
			)
			local resolved = {}
			for _, motor in ipairs(descendants) do
				resolved[motor] = evaluator.localAt(motor, time)
			end

			local CurveModifiers = require("Mods")
			local modifiersActive = CurveModifiers.any()
			if modifiersActive then
				for _, motor in ipairs(descendants) do
					if CurveModifiers.entries(motor) then
						local modified = CurveModifiers.applyC0(motor, time, TimelineState.FPS, function(
							sampleTime
						)
							return evaluator.localAt(motor, sampleTime)
						end, KeyframePolicy.activeBucket(TimelineState.Keyframes[motor]))
						if modified then
							resolved[motor] = modified
						end
					end
				end
			end

			for _, motor in ipairs(descendants) do
				local parented = LimbIK.isDriven(motor, time) or evaluator.isParentedAt(motor, time)
				if motor:GetAttribute("TrackParent") ~= parented then
					EventDependencies.poseAttribute(motor, "TrackParent", parented)
				end

				motor.C0 = resolved[motor]
				local part = motor.Part1
				local defaultSize = part and TimelineState.DefaultSize[part]
				if
					part
					and defaultSize
					and not (typeof(motor) == "table" and motor.IsEclipseMasterControl)
				then
					local scale = getEvaluatedPartScale(motor)
					if modifiersActive and CurveModifiers.entries(motor) then
						local modified, any = CurveModifiers.applyScale(motor, time, TimelineState.FPS, function(
							sampleTime
						)
							return self:EvaluateMotorScale(motor, sampleTime, nil, loopEndTime)
						end, KeyframePolicy.activeBucket(TimelineState.Keyframes[motor]))
						if any then
							scale = modified
						end
					end

					if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
						motor.InputScale = scale
								and Vector3.new(
									scale.scale_x or 1,
									scale.scale_y or 1,
									scale.scale_z or 1
								)
							or Vector3.one
					else
						EventDependencies.poseWrite(
							part,
							"Size",
							scale
									and Vector3.new(
										defaultSize.X * (scale.scale_x or 1),
										defaultSize.Y * (scale.scale_y or 1),
										defaultSize.Z * (scale.scale_z or 1)
									)
								or defaultSize
						)
					end
				end
			end

			local function applyRigControls(targetRig)
				if ArmatureRuntime.isRig(targetRig) then
					ArmatureRuntime.setTime(targetRig, time)
					ArmatureAnimation.applyProperties(targetRig, time * TimelineState.FPS)
					ArmatureRuntime.evaluate(targetRig)
				else
					LimbIK.apply(targetRig, time, true, getEvaluatedMotorC0, evaluator.worldAt)
				end
			end

			if allRigs and #allRigs > 1 then
				for _, targetRig in allRigs do
					applyRigControls(targetRig)
				end
			else
				applyRigControls(rig)
			end

			if not (options and options.SkipControls) then
				self:RefreshParentingControls(time, evaluator.isParentedAt, evaluator.childAt)
				if self.refs.RefreshIKHierarchy then
					self.refs.RefreshIKHierarchy()
				end

				self:RefreshIKControls(time)
				self:RefreshHeadStabilizerControls(time)
			end

		end)

		for _, target in propertyRigs do
			require("PartRig").flush(target)
			Properties.apply(target, TimelineState, time, loopEndTime, propertySamples, placed[target])
		end

		for _, target in propertyRigs do
			require("Target").applied(target, time)
		end

		if not (options and options.OnlyRig) then
			require("Origin").apply(self, time)
		end

		for _, target in propertyRigs do
			require("NativeJoints").flush(target)
		end

		require("Target").appliedChildren(descendants, time, evaluator)
		local lastCFrames = require("State").lastCFrames
		for _, motor in descendants do
			lastCFrames[motor] = motor.C0
		end
	end
end
