--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local NativeJoints = require("NativeJoints")
local RunService = game:GetService("RunService")

local AutoGetMotor6D = require("AutoGetMotor6D")
local ConvertToTable = require("ConvertToTable")
local Easing = require("Easing")
local PoseSpace = require("PoseSpace")
local RigPose = require("RigPose")

local module = {}
module.__index = module

module.AutoGetMotor6D = AutoGetMotor6D
module.KeyFrameSequanceToTable = ConvertToTable

local IDENTITY = CFrame.new()
const PREVIEW_INTERVAL = 1 / 60
const easingScratch = {}

local function lerpAlpha(timePos, t0, t1, easingStyle, easingDir)
	if t1 <= t0 then
		return 1
	end

	easingScratch.EasingStyle = easingStyle
	easingScratch.EasingDirection = easingDir
	return Easing.apply(math.clamp((timePos - t0) / (t1 - t0), 0, 1), easingScratch)
end

local function getPoseWeight(poseData)
	if not poseData then
		return 1
	end

	local weight = poseData.Weight
	if typeof(weight) ~= "number" then
		return 1
	end

	return math.clamp(weight, 0, 1)
end

local function applyPoseWeight(cf, weight)
	if weight >= 1 then
		return cf
	end

	return IDENTITY:Lerp(cf, weight)
end

local function safeDisconnect(conn)
	if conn and typeof(conn) == "RBXScriptConnection" then
		conn:Disconnect()
	end
end

local function getAnimatedJointSet(animationTable)
	local joints = {}

	for _, keyframe in ipairs(animationTable) do
		for jointName, _ in pairs(keyframe.Data) do
			joints[jointName] = true
		end
	end

	return joints
end

local function buildExistingMotorMap(modelOrMap, motorType)
	if typeof(modelOrMap) == "Instance" and modelOrMap:IsA("Model") then
		return AutoGetMotor6D(modelOrMap, motorType)
	end

	return modelOrMap
end

local function getJointTransformAtTime(animation, jointName, timePos)
	local previousIndex = nil
	local nextIndex = nil

	for i, keyframe in ipairs(animation) do
		local jointData = keyframe.Data[jointName]
		if jointData then
			if keyframe.Time <= timePos then
				previousIndex = i
			elseif not nextIndex then
				nextIndex = i
				break
			end
		end
	end

	if not previousIndex and not nextIndex then
		return nil
	end

	if not previousIndex and nextIndex then
		local nextPose = animation[nextIndex].Data[jointName]
		if nextPose then
			local nextWeight = getPoseWeight(nextPose)
			return applyPoseWeight(nextPose.CFrame or IDENTITY, nextWeight)
		end

		return nil
	end

	local prevFrame = animation[previousIndex]
	local prevPose = prevFrame.Data[jointName]

	if not nextIndex then
		local prevWeight = getPoseWeight(prevPose)
		return applyPoseWeight(prevPose.CFrame or IDENTITY, prevWeight)
	end

	local nextFrame = animation[nextIndex]
	local nextPose = nextFrame.Data[jointName]

	if not prevPose then
		local nextWeight = getPoseWeight(nextPose)
		return applyPoseWeight(nextPose.CFrame or IDENTITY, nextWeight)
	end

	if not nextPose then
		local prevWeight = getPoseWeight(prevPose)
		return applyPoseWeight(prevPose.CFrame or IDENTITY, prevWeight)
	end

	local rawAlpha = 0
	if nextFrame.Time > prevFrame.Time then
		rawAlpha = math.clamp((timePos - prevFrame.Time) / (nextFrame.Time - prevFrame.Time), 0, 1)
	end

	local easedAlpha = nil
	if prevPose.EclipseEasingKeyData then
		easedAlpha = Easing.apply(rawAlpha, prevPose.EclipseEasingKeyData)
	end

	if easedAlpha == nil then
		easedAlpha = lerpAlpha(
			timePos,
			prevFrame.Time,
			nextFrame.Time,
			prevPose.PoseEasingStyle,
			prevPose.PoseEasingDirection
		)
	end

	local prevWeight = getPoseWeight(prevPose)
	local nextWeight = getPoseWeight(nextPose)

	local cfA = applyPoseWeight(prevPose.CFrame or IDENTITY, prevWeight)
	local cfB = applyPoseWeight(nextPose.CFrame or IDENTITY, nextWeight)

	return cfA:Lerp(cfB, easedAlpha)
end

local function getJointWorldCFrameAtTime(animation, jointName, timePos)
	local previousIndex = nil
	local nextIndex = nil

	for i, keyframe in ipairs(animation) do
		local jointData = keyframe.Data[jointName]
		if jointData and jointData.WorldCFrame then
			if keyframe.Time <= timePos then
				previousIndex = i
			elseif not nextIndex then
				nextIndex = i
				break
			end
		end
	end

	if not previousIndex and not nextIndex then
		return nil
	end

	if not previousIndex and nextIndex then
		return animation[nextIndex].Data[jointName].WorldCFrame
	end

	local prevFrame = animation[previousIndex]
	local prevPose = prevFrame.Data[jointName]

	if not nextIndex then
		return prevPose.WorldCFrame
	end

	local nextFrame = animation[nextIndex]
	local nextPose = nextFrame.Data[jointName]

	local rawAlpha = 0
	if nextFrame.Time > prevFrame.Time then
		rawAlpha = math.clamp((timePos - prevFrame.Time) / (nextFrame.Time - prevFrame.Time), 0, 1)
	end

	local easedAlpha = nil
	if prevPose.EclipseEasingKeyData then
		easedAlpha = Easing.apply(rawAlpha, prevPose.EclipseEasingKeyData)
	end

	if easedAlpha == nil then
		easedAlpha = rawAlpha
	end

	return prevPose.WorldCFrame:Lerp(nextPose.WorldCFrame, easedAlpha)
end

local function buildPreviewSamplers(rig, sequence, motors, eligible)
	local result = {}
	if not rig or not eligible or not next(eligible) then
		return result
	end

	local timeline = require("State").Timeline
	local source = sequence:FindFirstChild("EclipseKeyframeData")
	if not source or not timeline or not timeline.CreatePreviewSampler then
		return result
	end

	local ok, archive = pcall(function()
		return game:GetService("HttpService"):JSONDecode(require("ChunkStore").read(source))
	end)
	if
		not ok
		or typeof(archive) ~= "table"
		or (archive.version ~= 1 and archive.version ~= 2)
		or typeof(archive.tracks) ~= "table"
	then
		return result
	end

	local decode = require("KeyframeStorage").decode
	local fps = sequence:GetAttribute("FPS")
	if typeof(fps) ~= "number" or fps < 1 or fps > 1000 then
		return result
	end

	local ratio = PoseSpace.savedRatio(rig, sequence)
	local matched = {}
	for _, saved in archive.tracks do
		local valid, part = pcall(function()
			local part = rig
			for _, step in saved.path do
				local count, found = 0, nil
				for _, child in part:GetChildren() do
					if child.Name == step.name and child.ClassName == step.class then
						count += 1
						if count == step.index then
							found = child
							break
						end
					end
				end

				if not found then
					return nil
				end

				part = found
			end

			return part
		end)
		if not valid or not part or not eligible[part.Name] then
			continue
		end

		local native = motors[part.Name]
		if
			not native
			or (native:IsA("Motor6D") and native.Part1 ~= part)
			or (native:IsA("Bone") and native ~= part)
		then
			continue
		end

		if matched[native] then
			result[part.Name] = nil
			continue
		end

		matched[native] = true
		local motor = native:IsA("Bone") and require("BoneMotor").get(native) or native
		if require("PivotSpace").jointOffset(motor) then
			continue
		end

		local success, sampler = pcall(function()
			if saved.parented == false then
				return nil
			end

			const Storage = require("KeyframeStorage")
			const stamped = typeof(motor) == "Instance" and motor:GetAttribute("EclipseAnimatorDefaultC0")
			const live = typeof(stamped) == "CFrame" and stamped or motor.C0
			const rebase = Storage.restRebase(rig, sequence, saved, motor, live)
			local bucket = {}
			for _, record in saved.keys do
				local frame = record.frame
				if
					typeof(frame) ~= "number"
					or frame < 0
					or frame ~= frame
					or frame >= math.huge
					or bucket[frame]
				then
					return nil
				end

				local key = decode(record.data)
				if
					typeof(key) ~= "table"
					or typeof(key.C0) ~= "CFrame"
					or key.Parented == false
					or key.IK
					or key.HS
					or key.HeadFollow
					or key.WorldCFrame
					or key.MasterWorld
					or key.PhysicsLead
					or key.PhysicsTail
					or key.BlenderCurve
				then
					return nil
				end

				for id, value in key.WholePoseScale or {} do
					if value ~= 1 then
						return nil
					end
				end

				for id in key.GraphCurves or {} do
					if id:sub(1, 6) == "scale_" then
						return nil
					end
				end

				for _, channels in { key.Channels or {}, key.GraphCurves or {} } do
					for id, point in channels do
						if id:sub(1, 6) == "scale_" and point.Value ~= 1 then
							return nil
						end
					end
				end

				Storage.rebaseKey(key, rebase, timeline)
				PoseSpace.retargetKey(key, ratio, nil, nil)
				key.Frame, key.Time, key.Motor, key.Part = frame, frame / fps, motor, part
				bucket[frame] = key
			end

			if not next(bucket) then
				return nil
			end

			local rest = rebase and live
				or saved.rest and PoseSpace.scaleTranslation(decode(saved.rest), ratio)
				or motor.C0
			return timeline:CreatePreviewSampler(motor, bucket, rest)
		end)
		if success then
			result[part.Name] = sampler
		end
	end

	return result
end

local function applyPoseToRig(track, timePos)
	if not track.Motor6D then
		return
	end

	local fps = track._previewFPS
	if fps then
		local step = track._previewFrameStep or 1
		timePos = math.floor(math.max(0, timePos) * fps / step + 1e-7) * step / fps
	end

	if track._poseApplied and track._poseTime == timePos then
		return
	end

	track._poseTime = timePos
	track._poseApplied = true

	for jointName, _ in pairs(track._animatedJoints) do
		local motor = track.Motor6D[jointName]
		if motor then
			if not track._restStamps[motor] then
				local rest = motor:IsA("Motor6D") and motor.C0 or motor.CFrame * motor.Transform
				if motor:GetAttribute("EclipseAnimatorDefaultC0") == nil then
					motor:SetAttribute("EclipseAnimatorDefaultC0", rest)
					track._restStamps[motor] = rest
				end

				if motor:GetAttribute("EclipseRigRestC0") == nil then
					RigPose.rememberRest(motor, rest)
				end
			end

			local sampler = track._previewSamplers and track._previewSamplers[jointName]
			local sampledC0 = sampler and sampler(timePos)
			local jointTransform = not sampledC0
					and getJointTransformAtTime(track.Animation, jointName, timePos)
				or nil
			if jointTransform then
				jointTransform = PoseSpace.scaleTranslation(jointTransform, track._poseScale)
			end

			if motor:IsA("Motor6D") then
				local baseC0 = track._originalC0[motor]
				if not baseC0 then
					baseC0 = motor.C0
					track._originalC0[motor] = baseC0
				end

				if sampledC0 then
					motor.C0 = sampledC0
				elseif jointTransform then
					motor.C0 = baseC0 * jointTransform
				else
					motor.C0 = baseC0
				end
			elseif motor:IsA("Bone") then
				motor.Transform = sampledC0 and motor.CFrame:ToObjectSpace(sampledC0)
					or jointTransform
					or IDENTITY
			end
		end
	end

	if track._detachedJointNames and next(track._detachedJointNames) then
		local targets, byPart, worlds, visiting = {}, {}, {}, {}
		for _, motor in track.Motor6D do
			if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
				byPart[motor.Part1] = motor
			end
		end

		for jointName in pairs(track._detachedJointNames) do
			if track._animatedJoints[jointName] then
				local motor = track.Motor6D[jointName]
				if motor and motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
					local worldCF = getJointWorldCFrameAtTime(track.Animation, jointName, timePos)
					if worldCF then
						targets[motor.Part1] = PoseSpace.retargetWorld(
							worldCF,
							track._worldRatio or 1,
							track._authoredPivot,
							track._importPivot
						)
					end
				end
			end
		end

		local function world(part)
			if targets[part] then
				return targets[part]
			end

			if worlds[part] then
				return worlds[part]
			end

			if visiting[part] then
				return part.CFrame
			end

			visiting[part] = true
			local motor = byPart[part]
			local value = motor
					and world(motor.Part0) * motor.C0 * motor.Transform * motor.C1:Inverse()
				or part.CFrame
			visiting[part] = nil
			worlds[part] = value
			return value
		end

		for part, target in targets do
			local motor = byPart[part]
			motor.C0 = world(motor.Part0):Inverse() * target * motor.C1 * motor.Transform:Inverse()
		end
	end

	if track._rig then
		NativeJoints.flush(track._rig)
		RigPose.assemble(track._rig)
	end
end

local function resetTrackPose(track)
	if not track.Motor6D or not track._poseApplied then
		return
	end

	for jointName, _ in pairs(track._animatedJoints) do
		local motor = track.Motor6D[jointName]
		if motor then
			if motor:IsA("Motor6D") then
				local baseC0 = track._originalC0[motor]
				if baseC0 then
					motor.C0 = baseC0
				end

				motor.Transform = IDENTITY
			elseif motor:IsA("Bone") then
				motor.Transform = IDENTITY
			end
		end
	end

	if track._rig then
		NativeJoints.flush(track._rig)
		if track._originalPose then
			RigPose.restore(track._rig, track._originalPose)
		else
			RigPose.assemble(track._rig)
		end

		RigPose.releaseBonds(track._rig)
	end

	for joint, rest in track._restStamps do
		if joint.Parent and joint:GetAttribute("EclipseAnimatorDefaultC0") == rest then
			joint:SetAttribute("EclipseAnimatorDefaultC0", nil)
		end
	end

	table.clear(track._restStamps)
	track._poseApplied = false
	track._poseTime = nil
end

local function getSafeStartsAt(self)
	local startAt = 0

	if self.Settings and typeof(self.Settings.StartsAt) == "number" then
		startAt = self.Settings.StartsAt
	end

	if self.Length <= 0 then
		return 0
	end

	return math.clamp(startAt, 0, self.Length)
end

local function restartFromBeginning(self, overflow)
	local startAt = getSafeStartsAt(self)
	local newTime = startAt + math.max(overflow or 0, 0)

	if self.Length > 0 and newTime > self.Length then
		newTime = startAt + ((newTime - startAt) % self.Length)
	end

	self.TimePosition = math.clamp(newTime, 0, math.max(self.Length, 0))
	self._fireDidLoop:Fire(true)
	applyPoseToRig(self, self.TimePosition)
end

function module.CreateModuleGroup()
	return {
		i = {},
	}
end

function module.new(Motor6DTable, KeyFrameSequance, AnimationGroup, Settings, Motor6DorBone)
	local self = setmetatable({}, module)

	self.Looped = false
	self.TimePosition = 0
	self.IsPlaying = false
	self.Speed = 1
	self.Weight = 1
	self.Priority = Enum.AnimationPriority.Core
	self.Name = ""
	self.EndHoldDuration = 1
	self.AutoReplayNonLooped = true

	self._connection = nil
	self._playingFrozen = false
	self._holdingAtEnd = false
	self._holdTimer = 0
	self._originalC0 = setmetatable({}, { __mode = "k" })
	self._restStamps = {}
	self._poseApplied = false
	self._poseScale = 1

	self._rig = typeof(Motor6DTable) == "Instance" and Motor6DTable or nil
	self._originalPose = self._rig and RigPose.capture(self._rig) or nil
	if self._rig then
		RigPose.captureBonds(self._rig)
	end
	self.Motor6D = buildExistingMotorMap(Motor6DTable, Motor6DorBone)

	if not KeyFrameSequance then
		error('Parameter "KeyFrameSequance" cannot be nil')
	end

	if typeof(KeyFrameSequance) == "Instance" and KeyFrameSequance:IsA("KeyframeSequence") then
		local animation, looped, priority, detachedJointNames, recovery =
			ConvertToTable(KeyFrameSequance, self.Motor6D)
		local rig = typeof(Motor6DTable) == "Instance" and Motor6DTable or nil
		self._poseScale = PoseSpace.getImportScale(rig, KeyFrameSequance, true)
		self._authoredPivot = KeyFrameSequance:GetAttribute("EclipseAuthoredPivot")
		self._importPivot = PoseSpace.getImportPivot(rig, KeyFrameSequance)
		self._worldRatio = PoseSpace.savedRatio(rig, KeyFrameSequance)
		self._previewSamplers = buildPreviewSamplers(rig, KeyFrameSequance, self.Motor6D, recovery)
		local fps = KeyFrameSequance:GetAttribute("FPS")
		if typeof(fps) == "number" and fps == fps and fps >= 1 and fps <= 1000 then
			self._previewFPS = fps
			local skip = KeyFrameSequance:GetAttribute("SkipFrames")
			self._previewFrameStep = typeof(skip) == "number" and math.clamp(math.floor(skip), 0, 1000) + 1 or 1
		end
		self.Animation = animation
		self.Looped = looped
		self.Priority = priority
		self._detachedJointNames = detachedJointNames
		self.Name = KeyFrameSequance.Name
	elseif typeof(KeyFrameSequance) == "table" then
		self.Animation = KeyFrameSequance
	else
		error(('Invalid format for "KeyFrameSequance": %s'):format(typeof(KeyFrameSequance)))
	end

	self.Settings = Settings
		or {
			StartsAt = 0,
			CanTransformMotor6D = true,
			Animate = "Animate",
			UpsyncThePlaying = "Default",
		}

	self.Length = 0
	if #self.Animation > 0 then
		self.Length = self.Animation[#self.Animation].Time or 0
	end

	self._animatedJoints = getAnimatedJointSet(self.Animation)

	local endedEvent = Instance.new("BindableEvent")
	local stoppedEvent = Instance.new("BindableEvent")
	local didLoopEvent = Instance.new("BindableEvent")
	local markerEvent = Instance.new("BindableEvent")

	self._fireEnded = endedEvent
	self._fireStopped = stoppedEvent
	self._fireDidLoop = didLoopEvent
	self._fireEvent = markerEvent

	self.Ended = endedEvent.Event
	self.Stopped = stoppedEvent.Event
	self.DidLoop = didLoopEvent.Event
	self.Event = markerEvent.Event

	if
		AnimationGroup ~= nil
		and typeof(AnimationGroup) == "Instance"
		and AnimationGroup:IsA("ModuleScript")
	then
		local group = require(AnimationGroup)
		self.Group = group
		local id = tostring(os.clock()) .. "_" .. tostring(math.random(1, 1e9))
		self.DataID = id

		group.i = group.i or {}
		group.i[id] = self

		return group.i[id], id
	end

	return self
end

function module:StopFading() end

function module:AdjustWeight(weight, _fadeTime)
	self.Weight = typeof(weight) == "number" and math.clamp(weight, 0, 1) or 1
end

function module:Freeze()
	self._playingFrozen = true
	self.IsPlaying = false
	self._fireEvent:Fire("MarkerSignal", "Frozen")
	return self.TimePosition
end

function module:UnFreeze()
	self._playingFrozen = false
	self.IsPlaying = true
	self._fireEvent:Fire("MarkerSignal", "UnFrozen")
end

function module:Cancel(DontResetMotor6D)
	safeDisconnect(self._connection)
	self._connection = nil

	local saved = self.TimePosition
	self.IsPlaying = false
	self._playingFrozen = false
	self._holdingAtEnd = false
	self._holdTimer = 0

	if DontResetMotor6D ~= true then
		resetTrackPose(self)
	end

	self.TimePosition = 0
	self._fireEvent:Fire("MarkerSignal", "Canceled")
	self._fireStopped:Fire()

	return saved
end

function module:Stop(_FadeTime)
	if not self.IsPlaying and not self._holdingAtEnd and not self._poseApplied then
		return
	end

	safeDisconnect(self._connection)
	self._connection = nil

	self.IsPlaying = false
	self._playingFrozen = false
	self._holdingAtEnd = false
	self._holdTimer = 0

	resetTrackPose(self)

	self.TimePosition = 0
	self._fireStopped:Fire()
end

function module:SamplePreview(time, restart)
	safeDisconnect(self._connection)
	self._connection = nil
	self.IsPlaying = true
	self._playingFrozen = false
	self._holdingAtEnd = false
	self._holdTimer = 0
	self.TimePosition = math.clamp(time, 0, math.max(self.Length, 0))
	applyPoseToRig(self, self.TimePosition)
	if restart then
		self._fireDidLoop:Fire(true)
	end
end

function module.previewGroup()
	local group = { tracks = {}, time = 0, length = 0, pending = 0, connection = nil }

	function group:stopClock()
		safeDisconnect(self.connection)
		self.connection = nil
	end

	function group:step(dt)
		if self.length <= 0 then
			return
		end

		self.pending += math.max(dt or 0, 0)
		if self.pending < PREVIEW_INTERVAL then
			return
		end

		const nextTime = self.time + self.pending
		self.pending = 0
		local wrapped = nextTime >= self.length
		self.time = wrapped and nextTime % self.length or nextTime
		for track in self.tracks do
			track:SamplePreview(self.time, wrapped)
		end
	end

	function group:restart(tracks)
		self:stopClock()
		self.tracks = {}
		self.time = 0
		self.pending = 0
		self.length = 0
		for _, track in tracks do
			self.tracks[track] = true
			self.length = math.max(self.length, track.Length)
			track:SamplePreview(0, false)
		end

		if next(self.tracks) and self.length > 0 then
			self.connection = RunService.Heartbeat:Connect(function(dt)
				self:step(dt)
			end)
		end
	end

	function group:remove(track)
		self.tracks[track] = nil
		local remaining = {}
		for other in self.tracks do
			table.insert(remaining, other)
		end

		self:restart(remaining)
	end

	function group:clear()
		self:stopClock()
		table.clear(self.tracks)
		self.time = 0
		self.length = 0
	end

	return group
end

function module:Play(_FadeTime, Weight, TimeStamp, Speed)
	safeDisconnect(self._connection)
	self._connection = nil

	self.Weight = typeof(Weight) == "number" and math.clamp(Weight, 0, 1) or self.Weight or 1
	self.Speed = typeof(Speed) == "number" and Speed or self.Speed or 1

	if typeof(TimeStamp) == "number" then
		self.TimePosition = math.clamp(TimeStamp, 0, math.max(self.Length, 0))
	else
		self.TimePosition = math.clamp(self.TimePosition or 0, 0, math.max(self.Length, 0))
	end

	self.IsPlaying = true
	self._playingFrozen = false
	self._holdingAtEnd = false
	self._holdTimer = 0

	applyPoseToRig(self, self.TimePosition)
	self._fireEvent:Fire("MarkerSignal", "Play")

	self._connection = RunService.Heartbeat:Connect(function(dt)
		if not self.IsPlaying then
			return
		end

		if self._playingFrozen then
			return
		end

		dt = math.max(dt or 0, 0)

		if self.Length <= 0 then
			applyPoseToRig(self, 0)

			if self.Looped or self.AutoReplayNonLooped then
				self._fireDidLoop:Fire(true)
			else
				self:Stop()
				self._fireEnded:Fire()
			end

			return
		end

		if self._holdingAtEnd then
			applyPoseToRig(self, self.Length)

			self._holdTimer += dt
			if self._holdTimer >= (self.EndHoldDuration or 1) then
				local overflow = self._holdTimer - (self.EndHoldDuration or 1)
				self._holdTimer = 0
				self._holdingAtEnd = false

				if self.AutoReplayNonLooped then
					restartFromBeginning(self, overflow * math.max(self.Speed, 0))
				else
					self:Stop()
					self._fireEnded:Fire()
				end
			end

			return
		end

		self.TimePosition += dt * self.Speed

		if self.TimePosition >= self.Length then
			local overflow = self.TimePosition - self.Length
			self.TimePosition = self.Length
			applyPoseToRig(self, self.TimePosition)

			if self.Looped then
				restartFromBeginning(self, overflow)
				return
			else
				self._fireEnded:Fire()
				self._holdingAtEnd = true
				self._holdTimer = 0
				return
			end
		end

		applyPoseToRig(self, self.TimePosition)
	end)
end

function module:Destroy()
	self:Cancel(false)

	if self.Group and self.DataID and self.Group.i then
		self.Group.i[self.DataID] = nil
	end

	if self._fireEnded then
		self._fireEnded:Destroy()
	end

	if self._fireStopped then
		self._fireStopped:Destroy()
	end

	if self._fireDidLoop then
		self._fireDidLoop:Destroy()
	end

	if self._fireEvent then
		self._fireEvent:Destroy()
	end
end

return module
