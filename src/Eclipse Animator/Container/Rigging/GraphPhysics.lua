--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local GraphCurves = require("GraphCurves")
local RigTraversal = require("RigTraversal")
local PhysicsCache = require("Cache")
local Properties = require("Properties")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("RawState")
local MainState = require("State")

local function checkpoint()
	if MainState.ProjectWorkStep then
		MainState.ProjectWorkStep()
	end
end

local Theme = require("Theme")
local BoneMotor = require("BoneMotor")
local Parenting = require("Parenting")
local LimbIK = require("LimbIK")
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

local TOGGLE_DISABLED_ICON = Color3.fromRGB(64, 64, 64)
local TOGGLE_DISABLED_GRADIENT =
	ColorSequence.new(Color3.fromRGB(132, 132, 132), Color3.fromRGB(88, 88, 88))

local defaultImageColors = {}
local defaultGradientColors = {}
local defaultBackgroundColors = {}

local function paintToggleButton(button, isActive)
	if not button then
		return
	end

	local img = button:FindFirstChild("ImageLabel")
	local gradient = button:FindFirstChildOfClass("UIGradient")

	if defaultBackgroundColors[button] == nil then
		defaultBackgroundColors[button] = button.BackgroundColor3
	end

	if img and defaultImageColors[img] == nil then
		defaultImageColors[img] = img.ImageColor3
	end

	if gradient and defaultGradientColors[gradient] == nil then
		defaultGradientColors[gradient] = gradient.Color
	end

	if isActive then
		button.BackgroundColor3 = defaultBackgroundColors[button]
		if img then
			img.ImageColor3 = Theme.resolveInstanceValue(img, "ThemeImg") or defaultImageColors[img]
		end

		if gradient then
			gradient.Color = Theme.resolveInstanceValue(gradient, "ThemeGrad")
				or defaultGradientColors[gradient]
		end
	else
		if img then
			img.ImageColor3 = TOGGLE_DISABLED_ICON
		end

		if gradient then
			gradient.Color = TOGGLE_DISABLED_GRADIENT
		else
			button.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
		end
	end
end

local function contentBuckets()
	local Layers = require("Layers")
	if not Layers.has(TimelineState) then
		return TimelineState.Keyframes
	end

	local result = {}
	for _, layer in Layers.ensure(TimelineState).layers do
		for motor, bucket in layer.keys do
			if TimelineState.DefaultPose[motor] ~= nil then
				table.insert(result, bucket)
			end
		end
	end

	return result
end

local function liveMotor(motor)
	if typeof(motor) == "Instance" then
		return motor.Parent ~= nil
	end

	if typeof(motor) ~= "table" or motor.IsEclipseProperty then
		return true
	end

	const part = motor.Part1
	return typeof(part) ~= "Instance" or part.Parent ~= nil
end

return function(Timeline)
	function Timeline:GetState()
		return TimelineState
	end

	function Timeline:GetConfig()
		return TimelineConfig
	end

	function Timeline:HasAnyKeyframes()
		if #PhysicsCache.list(TimelineState) > 0 then
			return true
		end

		for _, bucket in pairs(contentBuckets()) do
			for _, key in bucket or {} do
				if GraphCurves.hasKeyContent(bucket, key) then
					return true
				end
			end
		end

		return false
	end

	function Timeline:GetLastKeyframeFrame()
		local cache = require("cache").poseCache()
		if
			cache
			and cache.persistent
			and cache.lastFrameReady
			and cache.lastFrameTracks == TimelineState.Keyframes
			and cache.lastFrameLayers == TimelineState.AnimationLayers
		then
			return cache.lastFrame
		end

		local lastFrame = nil

		for motor, bucket in pairs(contentBuckets()) do
			if bucket and liveMotor(motor) then
				for frameNumber, key in pairs(bucket) do
					if
						GraphCurves.hasKeyContent(bucket, key)
						and (not lastFrame or frameNumber > lastFrame)
					then
						lastFrame = frameNumber
					end
				end
			end
		end

		for _, layer in TimelineState.AnimationLayers and TimelineState.AnimationLayers.layers or {} do
			for frame in layer.weightKeys or {} do
				lastFrame = math.max(lastFrame or 0, frame)
			end
		end

		if cache and cache.persistent then
			cache.lastFrameReady = true
			cache.lastFrame = lastFrame
			cache.lastFrameTracks = TimelineState.Keyframes
			cache.lastFrameLayers = TimelineState.AnimationLayers
		end

		return lastFrame
	end

	function Timeline:GetPlaybackEndTime()
		local now = os.clock()
		if self._playbackEndAt and now - self._playbackEndAt < 1 / 240 then
			return self._playbackEnd
		end

		local finish
		if require("Preferences").get("ContinuousTimeline") then
			finish = self:FrameToTime(self:GetMaxFrame())
		else
			local last = self:GetLastKeyframeFrame(true) or 0
			for _, clip in PhysicsCache.list(TimelineState) do
				last = math.max(last, clip.last)
			end

			for _, effect in TimelineState.ScreenEffects or {} do
				if effect.enabled ~= false then
					last = math.max(last, effect.start + effect.duration)
				end
			end

			if last <= 0 then
				last = self:GetMaxFrame()
			end

			finish = self:FrameToTime(last)
		end

		finish = math.min(finish, self:FrameToTime(self:GetMaxFrame()))
		self._playbackEnd, self._playbackEndAt = finish, now
		return finish
	end

	function Timeline:IsLooping()
		local loopButton = self.refs.LoopButton
		if not loopButton then
			return false
		end

		return loopButton:GetAttribute("Active") == true
	end

	function Timeline:SetLooping(isActive)
		local loopButton = self.refs.LoopButton
		if not loopButton then
			return
		end

		isActive = isActive == true
		loopButton:SetAttribute("Active", isActive)
		paintToggleButton(loopButton, isActive)
	end

	function Timeline:IsRecording()
		return TimelineState.Recording == true
	end

	function Timeline:SetRecording(isActive)
		isActive = isActive == true
		TimelineState.Recording = isActive

		local recordButton = self.refs.RecordButton
		if not recordButton then
			return
		end

		recordButton:SetAttribute("Active", isActive)
		paintToggleButton(recordButton, isActive)
	end

	function Timeline:ToggleRecording()
		local newState = not self:IsRecording()
		self:SetRecording(newState)
		return newState
	end

	function Timeline:ToggleLooping()
		local newState = not self:IsLooping()
		self:SetLooping(newState)
		return newState
	end

	function Timeline:CaptureDefaultPose(rig, preserveCurrent)
		local nativeRest, nativeSizes = require("ArmatureRuntime").nativeRestPose(rig)
		for motor, rest in nativeRest do
			if motor:GetAttribute("EclipseAnimatorDefaultC0") ~= nil then
				motor:SetAttribute("EclipseAnimatorDefaultC0", rest)
			end
		end

		if rig then
			require("RigPose").captureHome(rig)
			if preserveCurrent then
				Properties.captureDefaults(rig)
			else
				Properties.restoreDefaults(rig)
			end
		end

		if rig and preserveCurrent then
			require("Recovery").applyRest(rig, nil)
		elseif rig then
			require("RigPose").recoverStamps(rig)
		end

		self:InvalidateMotorListCache()
		TimelineState.DefaultPose = {}
		TimelineState.DefaultWorldPose = {}
		TimelineState.ParentingDefaults = {}
		TimelineState.MotorByPart = {}
		TimelineState.DefaultSize = {}

		if not rig then
			return
		end

		for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
			checkpoint()
			if m:IsA("Motor6D") then
				local c0 = nativeRest[m] or m.C0
				if nativeRest[m] then
					require("RigPose").rememberRest(m, c0)
				end

				TimelineState.DefaultPose[m] = c0
				m:SetAttribute("EclipseAnimatorDefaultC0", c0)
				require("RigPose").claimStamp(rig, m)
			elseif m:IsA("Bone") and not m:GetAttribute("EclipseArmatureSkinningHelper") then
				local adapter = BoneMotor.get(m)
				local c0 = adapter.C0
				TimelineState.DefaultPose[adapter] = c0
				m:SetAttribute("EclipseAnimatorDefaultC0", c0)
				require("RigPose").claimStamp(rig, m)
			end
		end

		local motors = Parenting.collectMotors(rig)
		TimelineState.MotorByPart = Parenting.buildMotorMap(motors)
		for _, motor in ipairs(motors) do
			checkpoint()
			TimelineState.DefaultPose[motor] = nativeRest[motor]
				or (typeof(motor) == "table" and motor.DefaultC0 or motor.C0)
			motor:SetAttribute("EclipseAnimatorDefaultC0", nativeRest[motor] or motor.C0)
			require("RigPose").claimStamp(rig, motor)
			TimelineState.ParentingDefaults[motor] = Parenting.captureDefault(motor)
			TimelineState.DefaultWorldPose[motor] =
				Parenting.worldOf(motor, TimelineState.MotorByPart)
		end

		for _, p in ipairs(RigTraversal.rigDescendants(rig)) do
			checkpoint()
			if p:IsA("BasePart") then
				TimelineState.DefaultSize[p] = (not preserveCurrent and nativeSizes[p]) or p.Size
				p:SetAttribute(
					"EclipseAnimatorDefaultSize",
					(not preserveCurrent and nativeSizes[p]) or p.Size
				)
				require("RigPose").claimStamp(rig, p)
			end
		end

		self:EnsureTransformChannelStarts()
	end

	function Timeline:CaptureDefaultPoseAdditive(root, preserveCurrent)
		local nativeRest, nativeSizes = require("ArmatureRuntime").nativeRestPose(root)
		for motor, rest in nativeRest do
			if TimelineState.DefaultPose[motor] == nil then
				TimelineState.DefaultPose[motor] = rest
				motor:SetAttribute("EclipseAnimatorDefaultC0", rest)
				require("RigPose").rememberRest(motor, rest)
			end
		end

		if root then
			require("RigPose").captureHome(root)
			if preserveCurrent then
				Properties.captureDefaults(root)
			else
				Properties.restoreDefaults(root)
			end
		end

		if not root then
			return
		end

		if preserveCurrent then
			require("Recovery").applyRest(root, TimelineState)
		else
			require("RigPose").recoverStamps(root, TimelineState)
		end

		self:InvalidateMotorListCache()
		const owner = root:IsA("Model") and root or root:FindFirstAncestorOfClass("Model")
		local motors = Parenting.collectMotors(root)
		if root:IsA("Motor6D") and root.Part0 and root.Part1 then
			table.insert(motors, root)
		end

		if root:IsA("Bone") and not root:GetAttribute("EclipseArmatureSkinningHelper") then
			table.insert(motors, BoneMotor.get(root))
		end

		for _, motor in ipairs(motors) do
			TimelineState.MotorByPart[motor.Part1] = motor
		end

		for _, motor in ipairs(motors) do
			checkpoint()
			if TimelineState.DefaultPose[motor] == nil then
				TimelineState.DefaultPose[motor] = nativeRest[motor]
					or (typeof(motor) == "table" and motor.DefaultC0 or motor.C0)
				motor:SetAttribute("EclipseAnimatorDefaultC0", nativeRest[motor] or motor.C0)
				require("RigPose").claimStamp(owner, motor)
				TimelineState.ParentingDefaults[motor] = Parenting.captureDefault(motor)
				TimelineState.DefaultWorldPose[motor] =
					Parenting.worldOf(motor, TimelineState.MotorByPart)
			end
		end

		local function captureSize(part)
			if
				part:IsA("BasePart")
				and not part:IsA("Terrain")
				and TimelineState.DefaultSize[part] == nil
			then
				TimelineState.DefaultSize[part] = (not preserveCurrent and nativeSizes[part])
					or part.Size
				part:SetAttribute(
					"EclipseAnimatorDefaultSize",
					(not preserveCurrent and nativeSizes[part]) or part.Size
				)
				require("RigPose").claimStamp(owner, part)
			end
		end

		captureSize(root)
		for _, item in ipairs(RigTraversal.rigDescendants(root)) do
			captureSize(item)
		end

		for _, motor in ipairs(motors) do
			captureSize(motor.Part1)
		end

		self:EnsureTransformChannelStarts()
	end

	function Timeline:ClearTimelineData()
		TimelineState.OnlyShowSelected = false
		if self.refs and self.refs.SetSelectionFilter then
			self.refs.SetSelectionFilter(false)
		end
		if self.RefreshNavigation then
			self:RefreshNavigation()
		end
		require("Layers").reset(TimelineState)
		if self.IsBlenderKeyframeTransformActive and self:IsBlenderKeyframeTransformActive() then
			self:CancelBlenderKeyframeTransform()
		end

		require("Origin").reset()
		LimbIK.clearLive()
		self:InvalidateMotorListCache()
		TimelineState.Keyframes = {}
		TimelineState.CurveModifiers = {}
		TimelineState.TrackRows = {}
		TimelineState.SelectedKeyframe = nil
		TimelineState.SelectedKeyframes = {}
		TimelineState.SelectedChannelKeyframes = {}
		TimelineState.CopiedKeyframes = {}
		TimelineState.DefaultPose = {}
		TimelineState.DefaultWorldPose = {}
		TimelineState.ParentingDefaults = {}
		TimelineState.MotorByPart = {}
		TimelineState.DefaultSize = {}
		TimelineState._motorUniform = {}
		TimelineState._motorHasScale = {}
		KeyframeDrag.hoveringKeyframe = nil
		KeyframeDrag.draggingKeyframe = nil
		KeyframeDrag.dragBucketSnapshotsBefore = nil
		KeyframeDrag.groupDragOriginals = {}
		KeyframeDrag.groupDragSelected = {}
		KeyframeDrag.groupDragSelectedChannels = {}
		if self.RefreshIKEndMarkers then
			self:RefreshIKEndMarkers()
		end
	end

	function Timeline:GetMotorKeyframeBucket(motor)
		if not motor then
			return nil
		end

		TimelineState.Keyframes[motor] = TimelineState.Keyframes[motor] or {}
		return TimelineState.Keyframes[motor]
	end

	function Timeline:GetAllKeyframeFrames()
		local seen = {}
		local frames = {}
		for _, bucket in pairs(TimelineState.Keyframes) do
			if bucket then
				for frame, key in pairs(bucket) do
					if not seen[frame] and GraphCurves.hasKeyContent(bucket, key) then
						seen[frame] = true
						table.insert(frames, frame)
					end
				end
			end
		end

		table.sort(frames)
		return frames
	end

	function Timeline:GetSortedMotorKeyframes(motor)
		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return {}
		end

		local frames = {}
		for frame in pairs(bucket) do
			table.insert(frames, frame)
		end

		table.sort(frames)
		return frames
	end
end
