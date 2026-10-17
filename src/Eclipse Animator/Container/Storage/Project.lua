--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")
local Properties = require("Properties")
local CameraRig = require("CameraRig")
local KeyframeStorage = require("KeyframeStorage")
local MasterControl = require("MasterControl")
local MainMenu = require("MainMenu")
local Selection = game:GetService("Selection")
local GraphCurves = require("GraphCurves")
local GraphHttp = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local EditorInput = require("UserInputService")

local State = require("State")
local AnimationEvents = require("Events")
local EventPlayback = require("EventPlayback")
local Data = require("ProjectData")
local Config = require("Config")
local UI = require("UI")
local Notification = require("Notification")
local WindowFX = require("WindowFX")
local Main = require("Main")
local History = require("History")
local WorkBudget = require("WorkBudget")
local MotorMath = require("MotorMath")
local Easing = require("Easing")
local PoseSpace = require("PoseSpace")
local PivotSpace = require("PivotSpace")
local ArmatureImport = require("ArmatureImport")
local ArmatureAnimation = require("ArmatureAnimation")
local ArmatureRuntime = require("ArmatureRuntime")
local R6Controls = require("R6Controls")
local BoneMotor = require("BoneMotor")
local BoneIK = require("BoneIK")
local LimbIK = require("LimbIK")
local HeadStabilizer = require("HeadStabilizer")
local Parenting = require("Parenting")
local Organization = require("Organization")
local Membership = require("Membership")
local Confirm = require("Confirm")
local AnimationList = require("AnimationList")

local previewGroup = Main.previewGroup()
local animationList

local function clearRetainedData()
	KeyframeStorage.clearRetained()
	require("RigIO").clearRetained()
	State.MissingRigEntries = {}
end

local function notifyUnmatched(kind)
	const count = KeyframeStorage.retainedCount() + require("RigIO").retainedCount()
	if count > 0 then
		Notification.show(
			"OPENED WITH UNMATCHED TRACKS",
			"Opened with "
				.. count
				.. (count == 1 and " track that couldn't be matched; its" or " tracks that couldn't be matched; their")
				.. " data is kept and saved with the "
				.. kind
				.. ". Restore the missing objects and reopen to use them. Details are in Output."
		)
	end

	return count
end
local previewButtons = {}
local previewSelections = {}
local previewConnections = {}
local previewSettled = {}

local function releaseSettled(rig)
	const snapshot = previewSettled[rig]
	previewSettled[rig] = nil
	if snapshot then
		const restored, problem = pcall(require("Recovery").restoreSnapshot, snapshot)
		if not restored then
			warn("[Eclipse] Could not put the rig back after preview: " .. tostring(problem))
		end
	end
end

local function disconnectPreview(rig)
	for _, connection in previewConnections[rig] or {} do
		connection:Disconnect()
	end

	previewConnections[rig] = nil
end

local selectedPreviewRigs = {}

local function stopRigPreview(rig)
	disconnectPreview(rig)
	local anim = State.currentAnimations[rig]
	State.currentAnimations[rig] = nil
	if anim then
		previewGroup:remove(anim)
	end

	local button = previewButtons[rig]
	previewButtons[rig] = nil
	previewSelections[rig] = nil
	AnimationList.setPreview(button, false)
	if anim then
		pcall(function()
			anim:Stop()
			anim:Destroy()
		end)
	end

	releaseSettled(rig)
	if State.currentPlayingTrack == anim then
		State.currentPlayingTrack = nil
		State.currentPlayingRig = nil
		State.currentPlayButton = nil
	end
end

local Project = {}

local function getCurrentRig()
	return State.currentRig
end

local function stopAllAnimations()
	previewGroup:clear()
	for rig in previewConnections do
		disconnectPreview(rig)
	end

	for _, button in previewButtons do
		AnimationList.setPreview(button, false)
	end

	table.clear(previewButtons)
	table.clear(previewSelections)
	AnimationList.setPreview(State.currentPlayButton, false)
	for rig, anim in pairs(State.currentAnimations) do
		if anim then
			pcall(function()
				anim:Stop()
			end)
			pcall(function()
				anim:Destroy()
			end)
		end

		State.currentAnimations[rig] = nil
	end

	for rig in previewSettled do
		releaseSettled(rig)
	end

	State.currentPlayingTrack = nil
	State.currentPlayingRig = nil
	if not State.currentRig then
		require("NativeJoints").clear()
	end

	local timeline = State.Timeline and State.Timeline:GetState()
	if timeline then
		timeline.Playing = false
	end

	State.currentPlayButton = nil
end

local function getSelectedAnimatableRigs()
	local rigs, seen = {}, {}

	local function add(object)
		if not seen[object] and State.Rig and State.Rig:IsAnimatable(object) then
			for _, rig in rigs do
				if object:IsDescendantOf(rig) then
					return
				end
			end

			seen[object] = true
			table.insert(rigs, object)
		end
	end

	for _, object in Selection:Get() do
		if State.Rig and State.Rig:IsAnimatable(object) then
			add(object)
		elseif object:IsA("Folder") then
			for _, child in object:GetDescendants() do
				if child:IsA("Model") then
					add(child)
				end
			end
		end
	end

	for i = #rigs, 1, -1 do
		for j, other in rigs do
			if i ~= j and rigs[i]:IsDescendantOf(other) then
				table.remove(rigs, i)
				break
			end
		end
	end

	return rigs
end

local function getSelectedAnimatableRig()
	local selectedObjects = Selection:Get()
	for _, obj in ipairs(selectedObjects) do
		if State.Rig and State.Rig:IsAnimatable(obj) then
			return obj
		end
	end

	return nil
end

local function clearAnimButtons()
	if animationList then
		animationList:setRigs({})
	end
end

local function playAnimationOnRig(rig, keyframeSequence, clickedButton)
	if State.LoadingProject or State.currentRig then
		return
	end

	if not rig or not keyframeSequence then
		return
	end

	if #selectedPreviewRigs > 1 then
		stopRigPreview(rig)
	else
		stopAllAnimations()
	end

	releaseSettled(rig)
	const settled, snapshot = pcall(require("Recovery").settleRig, rig)
	if settled then
		previewSettled[rig] = snapshot
	else
		warn("[Eclipse] Rest pose check before preview: " .. tostring(snapshot))
	end

	local animInstance = Main.new(rig, keyframeSequence)
	animInstance.Speed = 1
	animInstance.Weight = 1
	animInstance.EndHoldDuration = 1
	animInstance.Looped = keyframeSequence.Loop
	animInstance.AutoReplayNonLooped = true

	State.currentAnimations[rig] = animInstance
	previewConnections[rig] = {
		rig.Destroying:Connect(function()
			stopRigPreview(rig)
		end),
		keyframeSequence.Destroying:Connect(function()
			stopRigPreview(rig)
		end),
	}
	previewButtons[rig] = clickedButton
	previewSelections[rig] = keyframeSequence
	State.currentPlayingTrack = animInstance
	State.currentPlayingRig = rig
	State.currentPlayButton = clickedButton
	AnimationList.setPreview(clickedButton, true, keyframeSequence)

	animInstance.Stopped:Connect(function()
		if State.currentAnimations[rig] == animInstance then
			disconnectPreview(rig)
			State.currentAnimations[rig] = nil
			releaseSettled(rig)
			previewGroup:remove(animInstance)
			AnimationList.setPreview(previewButtons[rig], false)
			previewButtons[rig] = nil
			previewSelections[rig] = nil
		end

		if State.currentPlayingTrack == animInstance then
			State.currentPlayingTrack = nil
			State.currentPlayingRig = nil
			if State.currentPlayButton == clickedButton then
				AnimationList.setPreview(clickedButton, false)
				State.currentPlayButton = nil
			end
		end
	end)

	animInstance.Ended:Connect(function() end)
	previewGroup:restart(State.currentAnimations)
end

local populateAnimButtons
local syncObjectMotorStates
local projectOpenedHook = nil

local function setProjectOpenedHook(fn)
	projectOpenedHook = fn
end

local function readEaseFolder(easeFolder)
	local typeValue = easeFolder:FindFirstChild("Type")
	if not typeValue then
		return nil
	end

	local info = { style = typeValue.Value, params = {} }
	local paramsFolder = easeFolder:FindFirstChild("Params")
	if paramsFolder then
		for _, val in ipairs(paramsFolder:GetChildren()) do
			if val:IsA("ValueBase") then
				info.params[val.Name] = val.Value
			end
		end
	end

	return info
end

local function isRealKeyframePose(pose, keyframe)
	if pose.ClassName ~= "Pose" then
		return false
	end

	if pose.Weight <= 0 and not pose:GetAttribute("EclipseR6Control") then
		return false
	end

	if pose:FindFirstChild("EclipseSynthetic") then
		return false
	end

	return true
end

local function moonBakedSegments(sequence, budget)
	local linear, previous = {}, {}
	local moon = false
	local frames = sequence:GetKeyframes()
	table.sort(frames, function(a, b)
		return a.Time < b.Time
	end)
	for _, frame in frames do
		for _, pose in frame:GetDescendants() do
			budget()
			if pose:IsA("Pose") then
				local ease = pose:FindFirstChild("Ease")
				if
					pose:FindFirstChild("Null")
					or pose:FindFirstChild("xSIXxNull")
					or pose:FindFirstChild("xSIXxCustomStyle")
					or ease and not ease:GetAttribute("NativePose")
				then
					moon = true
				end
			end

			if not isRealKeyframePose(pose, frame) then
				continue
			end

			local path, ancestor = {}, pose
			while ancestor and ancestor ~= frame do
				table.insert(path, 1, #ancestor.Name .. ":" .. ancestor.Name)
				ancestor = ancestor.Parent
			end

			local key = table.concat(path, "/")
			if pose:FindFirstChild("Null") or pose:FindFirstChild("xSIXxNull") then
				linear[pose] = true
				if previous[key] then
					linear[previous[key]] = true
				end
			end

			previous[key] = pose
		end
	end

	if
		sequence:GetAttribute("EclipsePoseSpace")
		or sequence:GetAttribute("EclipseBaked") ~= nil
		or sequence:GetAttribute("EclipseHadArmature") ~= nil
		or sequence:FindFirstChild("EclipseKeyframeData")
	then
		moon = false
	end

	return linear, moon
end

local function applyMoonEasingToKeyData(keyData, pose, bakedSegment, moon)
	keyData.HandleType = "Vector"
	if bakedSegment then
		keyData.EasingStyle = Enum.PoseEasingStyle.Linear
		keyData.EasingDirection = "In"
		keyData.HandleType = "Vector"
		return
	end

	local easeFolder = pose:FindFirstChild("Ease")
	if easeFolder then
		local info = readEaseFolder(easeFolder)
		if info then
			keyData.EasingStyle = info.style
			if easeFolder:GetAttribute("NativePose") then
				local ok, style = pcall(function()
					return Enum.PoseEasingStyle[info.style]
				end)
				if ok then
					keyData.EasingStyle = style
				end
			end

			if info.style == "Bezier" then
				keyData.BezierPoints = {
					info.params.X1 or 0,
					info.params.Y1 or 0.5,
					info.params.X2 or 0.5,
					info.params.Y2 or 1,
				}
			end

			keyData.EasingDirection = info.params.Direction
			keyData.Overshoot = info.params.Overshoot
			keyData.Amplitude = info.params.Amplitude
			keyData.Period = info.params.Period
			if moon and not easeFolder:GetAttribute("NativePose") then
				keyData.MoonEasing = true
				if info.style == "Elastic" then
					keyData.Amplitude = info.params.Amplitude or 1
					keyData.Period = info.params.Period or 0.3
				elseif info.style == "Back" then
					keyData.Overshoot = info.params.Overshoot or 1.70158
				end
			end

			return
		end
	end

	local customStyle = pose:FindFirstChild("xSIXxCustomStyle")
	local customDir = pose:FindFirstChild("xSIXxCustomDir")
	if customStyle then
		keyData.EasingStyle = customStyle.Value
		keyData.EasingDirection = customDir and customDir.Value or "In"
		return
	end

	keyData.EasingStyle = pose.EasingStyle
	keyData.EasingDirection = pose.EasingDirection.Name

	if
		moon
		and pose.EasingStyle == Enum.PoseEasingStyle.Constant
		and pose.EasingDirection == Enum.PoseEasingDirection.In
	then
		keyData.EasingStyle = "Constant"
	end

	keyData.HandleType = "Vector"
end

local structureBatch

local function restoreUnparentedStateFromSequence(rig, keyframeSequence)
	if not rig or not keyframeSequence then
		return
	end

	local defaults = State.Timeline:GetState().ParentingDefaults
	local folder = keyframeSequence:FindFirstChild("EclipseParentingDefaults")
	local legacy = keyframeSequence:FindFirstChild("EclipseUnparentedMotors")
	for _, motor in ipairs(Parenting.collectMotors(rig)) do
		if folder then
			for _, ref in ipairs(folder:GetChildren()) do
				if ref:IsA("ObjectValue") and (ref.Value == motor or ref.Value == motor.Part1) then
					defaults[motor] = ref:GetAttribute("Parented") ~= false
					break
				end
			end
		elseif legacy then
			for _, ref in ipairs(legacy:GetChildren()) do
				if
					ref:IsA("ObjectValue")
					and (ref.Value == motor or ref.Name == motor.Part1.Name)
				then
					defaults[motor] = false
					break
				end
			end
		end
	end
end

local function keepUnkeyedPlacement(rig, pivot)
	if typeof(pivot) ~= "CFrame" or Properties.inheritedTransform(rig) then
		return
	end

	const raw = State.Timeline:GetState()
	for _, motor in Properties.list(rig, true) do
		if motor.PropertyId == "CFrame" and not next(raw.Keyframes[motor] or {}) then
			motor.Part1:SetAttribute("Default", require("Document").pack(pivot))
			raw.DefaultPose[motor] = Properties.encode(pivot)
		end
	end
end

local function importKeyframesUnlayered(rig, keyframeSequence, options)
	local budget = options and options.ImportBudget or function() end
	if rig and keyframeSequence then
		require("NativeJoints").prepare(rig)
	end

	if rig and keyframeSequence and not (options and options.KeepMasterControl) then
		local master = MasterControl.read(keyframeSequence, rig)
		if master then
			local state = State.Timeline:GetState()
			state.DefaultPose[master], state.MotorByPart[master.Part1] = master.DefaultC0, master
			state.DefaultWorldPose[master], state.ParentingDefaults[master] =
				master.Part0.CFrame, true
		end
	end

	if rig and keyframeSequence then
		State.exportSequences[rig] = keyframeSequence
	end

	if not rig or not keyframeSequence then
		return
	end

	local timelineState = State.Timeline:GetState()
	if not timelineState then
		return
	end

	local importPivot = PoseSpace.getImportPivot(rig, keyframeSequence)
	local lastFrame = 0
	for _, key in ipairs(keyframeSequence:GetKeyframes()) do
		lastFrame = math.max(lastFrame, State.Timeline:TimeToFrame(key.Time))
	end

	State.Timeline:EnsureTimelineEnd(lastFrame)
	restoreUnparentedStateFromSequence(rig, keyframeSequence)

	local sanitizeName = (State.UIHelpers and State.UIHelpers.SanitizeName)
		or function(str)
			return tostring(str or ""):gsub("%s+", "")
		end

	local motorByPartName = RigTraversal.jointMap(rig, "Motor6D")
	for _, pose in keyframeSequence:GetDescendants() do
		budget()
		local kind = pose:IsA("Pose") and pose:GetAttribute("EclipseR6Control")
		local owner = kind and motorByPartName[pose:GetAttribute("EclipseR6Owner")]
		local rest = kind and pose:GetAttribute("EclipseR6Rest")
		if owner and typeof(rest) == "CFrame" then
			local bone = R6Controls.ensure(owner, kind, rest)
			bone.CFrame, bone.Transform = rest, CFrame.identity
			for attr, value in pose:GetAttributes() do
				if attr == "EclipseDisabled" or attr:sub(1, 22) == "EclipseChannelDisabled" then
					bone:SetAttribute(attr, value)
				end
			end

			timelineState.DefaultPose[R6Controls.get(bone)] = rest
		end
	end

	LimbIK.invalidate(rig)
	State.Timeline:CaptureDefaultPoseAdditive(rig)
	local nativeMap = RigTraversal.jointMap(rig)
	for key, m in nativeMap do
		motorByPartName[key] = m:IsA("Bone") and BoneMotor.get(m) or m
	end

	local poseScale = PoseSpace.getImportScale(rig, keyframeSequence)
	local authoredArmature = ArmatureAnimation.hasSaved(keyframeSequence)
		and ArmatureRuntime.isRig(rig)

	local bakedArmature = ArmatureAnimation.hasSaved(keyframeSequence) and not authoredArmature
	local bakedArmatureKeys = 0
	local previousTime = timelineState.CurrentTime
	local missingWorld = {}
	local layerStorage = require("layerStorage")
	local preparedPhysics, preparedLayers, preparedKeys
	local physicsParts, archivedMotors = {}, {}
	if not bakedArmature then
		preparedPhysics, physicsParts =
			KeyframeStorage.preparePhysics(keyframeSequence, rig, budget)
		preparedLayers = layerStorage.prepareRead(keyframeSequence, budget)
		preparedKeys, archivedMotors = KeyframeStorage.prepareRead(
			keyframeSequence,
			rig,
			timelineState,
			budget,
			preparedLayers ~= nil
		)
	end

	local rotationEvidence = {}
	local bakedSegments, moon = moonBakedSegments(keyframeSequence, budget)

	for _, kf in ipairs(keyframeSequence:GetKeyframes()) do
		budget()
		timelineState.CurrentTime = kf.Time
		local exactFrame = kf:GetAttribute("EclipseExactFrame")
		local frameNumber = typeof(exactFrame) == "number" and exactFrame
			or kf.Time * timelineState.FPS
		if
			typeof(exactFrame) ~= "number"
			and math.abs(frameNumber - math.round(frameNumber)) < 1e-3
		then
			frameNumber = math.round(frameNumber)
		end

		for _, pose in ipairs(kf:GetDescendants()) do
			budget()
			if isRealKeyframePose(pose, kf) then
				local motor = RigTraversal.resolvePose(motorByPartName, pose)
				local kind = pose:GetAttribute("EclipseR6Control")
				if kind then
					local owner = motorByPartName[pose:GetAttribute("EclipseR6Owner")]
					motor = owner and R6Controls.get(R6Controls.find(owner, kind))
				end

				if motor and (physicsParts[motor.Part1] or archivedMotors[motor]) then
					if
						archivedMotors[motor]
						and preparedKeys
						and not preparedKeys.quaternionInterpolation
						and not keyframeSequence:GetAttribute("EclipseCameraExportVersion")
					then
						local evidence = rotationEvidence[motor]
						if not evidence then
							evidence = { samples = {}, count = 0, stride = 1 }
							rotationEvidence[motor] = evidence
						end

						evidence.count += 1
						if (evidence.count - 1) % evidence.stride == 0 then
							local localPose = pose:GetAttribute("EclipseLocalPose")
							table.insert(evidence.samples, {
								time = frameNumber / timelineState.FPS,
								c0 = (timelineState.DefaultPose[motor] or motor.C0)
									* PoseSpace.scaleTranslation(
										typeof(localPose) == "CFrame" and localPose or pose.CFrame,
										poseScale
									),
							})
							if #evidence.samples > 64 then
								local reduced = {}
								for i = 1, #evidence.samples, 2 do
									table.insert(reduced, evidence.samples[i])
								end

								evidence.samples = reduced
								evidence.stride *= 2
							end
						end
					end

					continue
				end

				if
					authoredArmature
					and motor
					and ArmatureRuntime.isDriven(
						typeof(motor) == "Instance" and motor or motor.Part1
					)
				then
					continue
				end

				if motor then
					local defaultC0 = timelineState.DefaultPose[motor] or motor.C0
					local localPose = not bakedArmature and pose:GetAttribute("EclipseLocalPose")
					local c0 = defaultC0
						* PoseSpace.scaleTranslation(
							typeof(localPose) == "CFrame" and localPose or pose.CFrame,
							poseScale
						)
					if
						CameraRig.isFov(motor)
						and typeof(keyframeSequence:GetAttribute("EclipseCameraDefaultFOV"))
							== "number"
					then
						c0 = CameraRig.encode(
							motor,
							keyframeSequence:GetAttribute("EclipseCameraDefaultFOV") + pose.CFrame.Y
						)
					end

					if bakedArmature and pose.Weight < 1 then
						c0 = defaultC0
							* PoseSpace.scaleTranslation(
								CFrame.identity:Lerp(pose.CFrame, math.clamp(pose.Weight, 0, 1)),
								poseScale
							)
					end

					State.Timeline:RecordKeyframeForMotorAtCurrentTime(motor.Part1, motor, c0, {
						InheritEasing = false,
						PreserveGraph = true,
						Frame = frameNumber,
						ImportRaw = true,
					}, sanitizeName)

					local bucket = timelineState.Keyframes[motor]
					if bucket and bucket[frameNumber] then
						local keyData = bucket[frameNumber]
						if bakedArmature then
							bakedArmatureKeys += 1
							keyData.Parented, keyData.WorldCFrame = true, nil
							keyData.EasingStyle, keyData.EasingDirection =
								pose.EasingStyle, pose.EasingDirection.Name
							keyData.HandleType = "Vector"
							continue
						end

						local parented = pose:GetAttribute("EclipseParented")
						if typeof(parented) ~= "boolean" then
							parented = timelineState.ParentingDefaults[motor] ~= false
						end

						keyData.Parented = parented
						if typeof(pose:GetAttribute("EclipsePivot")) == "Vector3" then
							PivotSpace.set(motor, pose:GetAttribute("EclipsePivot"))
						end

						keyData.WorldCFrame = nil
						keyData.HS = pose:GetAttribute("EclipseHS")
						keyData.HSRestoreParented = pose:GetAttribute("EclipseHSRestoreParented")
						keyData.HSRotation = pose:GetAttribute("EclipseHSRotation")
						keyData.HSLocalRotation = pose:GetAttribute("EclipseHSLocalRotation")
						keyData.IK = pose:GetAttribute("EclipseIK")
						keyData.IKTarget = pose:GetAttribute("EclipseIKTarget")
						keyData.IKPole = pose:GetAttribute("EclipseIKPole")
						keyData.IKBaseC0 = pose:GetAttribute("EclipseIKBaseC0")
						keyData.IKBaseWorld = pose:GetAttribute("EclipseIKBaseWorld")
						keyData.IKAnchor = pose:GetAttribute("EclipseIKAnchor")
						keyData.IKRigWorld = pose:GetAttribute("EclipseIKRigWorld")
						keyData.IKRoot = pose:GetAttribute("EclipseIKRoot")
						keyData.IKPoleFollowsTarget =
							pose:GetAttribute("EclipseIKPoleFollowsTarget")
						keyData.IKRestoreParented = pose:GetAttribute("EclipseIKRestoreParented")
						applyMoonEasingToKeyData(keyData, pose, bakedSegments[pose], moon)
						local graph = pose:FindFirstChild("EclipseGraphCurves")
						if graph and graph:IsA("StringValue") then
							keyData.GraphCurves = GraphHttp:JSONDecode(graph.Value)
							keyData.GraphOnly = pose:GetAttribute("EclipseGraphOnly") == true
							GraphCurves.invalidate(bucket)
						end

						local handleTypeVal = pose:FindFirstChild("HandleType")
						if handleTypeVal and handleTypeVal:IsA("StringValue") then
							bucket[frameNumber].HandleType = handleTypeVal.Value
						end

						local detachedWorldVal = pose:FindFirstChild("DetachedWorldCFrame")
						if detachedWorldVal and detachedWorldVal:IsA("CFrameValue") then
							bucket[frameNumber].WorldCFrame = not parented
									and detachedWorldVal.Value
								or nil
						elseif not parented then
							table.insert(missingWorld, keyData)
						end

						local tangentOutVal = pose:FindFirstChild("EclipsePathTangentOut")
						if tangentOutVal and tangentOutVal:IsA("Vector3Value") then
							bucket[frameNumber].PathTangentOut = tangentOutVal.Value
						end

						local tangentInVal = pose:FindFirstChild("EclipsePathTangentIn")
						if tangentInVal and tangentInVal:IsA("Vector3Value") then
							bucket[frameNumber].PathTangentIn = tangentInVal.Value
						end

						local channelsMarker = pose:FindFirstChild("EclipseChannels")
						local valuesFolder = pose:FindFirstChild("EclipseChannelValues")
						if
							channelsMarker
							and channelsMarker:IsA("StringValue")
							and valuesFolder
						then
							local newChannels = {}
							for _, v in ipairs(valuesFolder:GetChildren()) do
								if v:IsA("NumberValue") or v:IsA("IntValue") then
									newChannels[v.Name] = { Value = v.Value }
								end
							end

							if next(newChannels) then
								bucket[frameNumber].Channels = newChannels
								bucket[frameNumber]._EclipseRawChannels = true
								bucket[frameNumber].C0 = State.Timeline:_reconstructC0FromKeyData(
									bucket[frameNumber]
								) or bucket[frameNumber].C0
								if bucket[frameNumber].C0 then
									bucket[frameNumber].Position = bucket[frameNumber].C0.Position
									bucket[frameNumber].Rotation = bucket[frameNumber].C0
										- bucket[frameNumber].C0.Position
								end

								timelineState._motorUniform[motor] = nil
								timelineState._motorHasScale[motor] = nil
								State.Timeline:_addChannelDiamondAtFrame(motor, frameNumber)
							end
						end
					end
				end
			end
		end
	end

	assert(
		not bakedArmature or bakedArmatureKeys > 0,
		"This animation needs its Blender control rig; no matching baked joint animation is available"
	)
	for _, chain in LimbIK.getRig(rig).chains do
		if chain.kind ~= "R6" then
			continue
		end

		local roots = {}
		for frame, key in timelineState.Keyframes[chain.owner] or {} do
			budget()
			if key.IK and key.IKRoot then
				roots[frame] = key
			end
		end

		if not next(roots) then
			continue
		end

		local existing = LimbIK.controlMotor(chain, "root")
		if existing and next(timelineState.Keyframes[existing] or {}) then
			continue
		end

		local control = LimbIK.prepare(chain)[1]
		State.Timeline:CaptureDefaultPoseAdditive(rig)
		for frame, key in roots do
			budget()
			local reference = LimbIK.keyAnchor(key) or LimbIK.anchor(chain)
			local value = reference:ToObjectSpace(key.IKRoot)
			timelineState.CurrentTime = key.Time
			State.Timeline:RecordKeyframeForMotorAtCurrentTime(
				control.Part1,
				control,
				value,
				{ InheritEasing = false, PreserveGraph = true },
				sanitizeName
			)
			local child = timelineState.Keyframes[control][frame]
			for _, field in
				{
					"EasingStyle",
					"EasingDirection",
					"HandleType",
					"BezierPoints",
					"Overshoot",
					"Amplitude",
					"Period",
				}
			do
				child[field] = key[field]
			end
		end
	end

	if #missingWorld > 0 then
		local savedModes = {}
		for _, bucket in pairs(timelineState.Keyframes) do
			for _, key in pairs(bucket) do
				savedModes[key] = key.Parented
				key.Parented = true
				budget()
			end

			GraphCurves.invalidate(bucket)
		end

		local defaults = timelineState.ParentingDefaults
		timelineState.ParentingDefaults = {}
		for motor in pairs(timelineState.DefaultPose) do
			timelineState.ParentingDefaults[motor] = true
		end

		local byTime = {}
		for _, key in missingWorld do
			local list = byTime[key.Time] or {}
			byTime[key.Time] = list
			table.insert(list, key)
			budget()
		end

		for time, list in byTime do
			budget()
			State.Timeline:ApplyPoseAtTime(rig, time, { OnlyRig = true })
			for _, key in list do
				key.WorldCFrame = Parenting.worldOf(key.Motor, timelineState.MotorByPart)
				budget()
			end
		end

		timelineState.ParentingDefaults = defaults
		for key, parented in pairs(savedModes) do
			key.Parented = parented
			budget()
		end

		for _, bucket in timelineState.Keyframes do
			GraphCurves.invalidate(bucket)
		end
	end

	ArmatureAnimation.read(keyframeSequence, rig, State.Timeline, sanitizeName, budget)
	if not (options and options.KeepPropertyTracks) then
		const placement = rig:IsA("Model") and rig:GetPivot()
		Properties.read(keyframeSequence, rig, State.Timeline, sanitizeName)
		keepUnkeyedPlacement(rig, placement)
	end

	if not bakedArmature then
		PivotSpace.read(keyframeSequence, rig)
	end

	if not bakedArmature then
		KeyframeStorage.read(
			keyframeSequence,
			rig,
			State.Timeline,
			sanitizeName,
			preparedKeys,
			budget,
			importPivot,
			rotationEvidence
		)
	end

	local ratio = PoseSpace.savedRatio(rig, keyframeSequence)
	if ratio ~= 1 or typeof(keyframeSequence:GetAttribute("EclipseAuthoredPivot")) == "CFrame" then
		local generatedWorld = {}
		for _, key in missingWorld do
			generatedWorld[key] = key.WorldCFrame
		end

		for motor, bucket in timelineState.Keyframes do
			if options and options.KeepImportMotors and options.KeepImportMotors[motor] then
				continue
			end

			if not motor.Part1 or not motor.Part1:IsDescendantOf(rig) then
				continue
			end

			if
				typeof(motor) == "table"
				and (motor.IsEclipseProperty or motor.IsEclipseArmatureControl)
			then
				continue
			end

			for _, key in bucket do
				budget()
				local canonicalC0 = key.C0
				local stored = key._EclipseRawStored or key._EclipseRawChannels
				PoseSpace.retargetKey(
					key,
					ratio,
					keyframeSequence:GetAttribute("EclipseAuthoredPivot"),
					importPivot
				)

				if generatedWorld[key] then
					key.WorldCFrame = generatedWorld[key]
				end

				if not stored then
					key.C0 = canonicalC0
					key.Position = canonicalC0.Position
					key.Rotation = canonicalC0.Rotation
				end

				key._EclipseRawStored, key._EclipseRawChannels = nil, nil
			end
		end
	end

	if not bakedArmature then
		KeyframeStorage.readPhysics(
			keyframeSequence,
			rig,
			State.Timeline,
			sanitizeName,
			preparedPhysics,
			budget,
			importPivot
		)
	end

	for motor, bucket in pairs(timelineState.Keyframes) do
		GraphCurves.invalidate(bucket)
		for frame, key in pairs(bucket) do
			budget()
			State.Timeline:CreateOrUpdateTimelineKeyframeButton(
				key.Part,
				motor,
				frame,
				key.Template,
				key.SanitizeName
			)
		end

		State.Timeline:RefreshAllChannelDiamondsForMotor(motor)
	end

	for _, chain in LimbIK.getRig(rig).chains do
		if LimbIK.hasAnimation(chain.owner) then
			LimbIK.prepare(chain)
		end
	end

	State.Timeline:CaptureDefaultPoseAdditive(rig)
	State.Timeline:EnsureTransformChannelStarts()

	if State.Rig and State.Rig.RefreshIKChildren and not (options and options.DeferVisuals) then
		State.Rig:RefreshIKChildren(State.currentRig or rig)
	end

	if State.GraphEditor then
		State.GraphEditor.invalidate()
	end

	AnimationEvents.load(rig, keyframeSequence, timelineState.FPS, options and options.EventOptions)
	State.Timeline:RefreshEventRows()
	if
		not bakedArmature
		and layerStorage.read(
			keyframeSequence,
			rig,
			State.Timeline,
			budget,
			preparedLayers,
			importPivot
		)
	then
		for motor, bucket in timelineState.Keyframes do
			for frame, key in bucket do
				State.Timeline:CreateOrUpdateTimelineKeyframeButton(
					key.Part,
					motor,
					frame,
					key.Template,
					sanitizeName
				)
				budget()
			end
		end
	end

	timelineState.CurrentTime = previousTime
	if structureBatch then
		structureBatch.dirty, structureBatch.pose = true, true
		return
	end

	State.Timeline:ApplyPoseAtTime(rig, previousTime)
	State.Timeline:RefreshAllKeyframeVisuals()
	State.Timeline:UpdatePlayhead()
end

local function importKeyframesFromSequence(rig, keyframeSequence, options)
	if State.LoadingProject and State.ProjectLoadThread ~= coroutine.running() then
		return
	end

    local nativeCopy
    local authoredRig = keyframeSequence and keyframeSequence:GetAttribute("EclipseAuthoredRigId")
    if authoredRig and authoredRig ~= rig:GetAttribute("EclipseTrackId") and not keyframeSequence:GetAttribute("EclipseRawRecovery") and require("Import").isR15(rig) then
        nativeCopy = require("Import").nativeR15(keyframeSequence)
        keyframeSequence = nativeCopy or keyframeSequence
    end
	local previousLoading, previousThread = State.LoadingProject, State.ProjectLoadThread
	State.LoadingProject = true
	State.ProjectLoadThread = coroutine.running()
	local slice = os.clock()
	local maxSlice, yields = 0, 0

	local function budget()
		local now = os.clock()
		if now - slice >= 0.012 then
			maxSlice = math.max(maxSlice, now - slice)
			yields += 1
			task.wait()
			slice = os.clock()
		end
	end

	local previousWorkStep = State.ProjectWorkStep
	State.ProjectWorkStep = budget
	options = table.clone(options or {})
	options.ImportBudget = budget
	local raw = State.Timeline:GetState()
	local importing = raw._ImportingKeyframes
	raw._ImportingKeyframes = true
	raw.Playing = false
	local result = table.pack(xpcall(function()
		return require("layerStorage").withImport(State.Timeline, function()
			return importKeyframesUnlayered(rig, keyframeSequence, options)
		end)
	end, debug.traceback))
	raw._ImportingKeyframes = importing
	local visualOK, visualError = xpcall(function()
		if not importing and structureBatch then
			structureBatch.dirty, structureBatch.visuals = true, true
		elseif not importing and not (options and options.DeferVisuals) then
			for motor, bucket in raw.Keyframes do
				for frame, key in bucket do
					State.Timeline:CreateOrUpdateTimelineKeyframeButton(
						key.Part,
						motor,
						frame,
						key.Template,
						key.SanitizeName
					)
					budget()
				end

				State.Timeline:RefreshAllChannelDiamondsForMotor(motor, budget)
			end

			State.Timeline:RefreshAllKeyframeVisuals(budget)
		end
	end, debug.traceback)
	maxSlice = math.max(maxSlice, os.clock() - slice)
	State.LastProjectLoad = { maxSliceMs = maxSlice * 1000, yields = yields }
	for motor in raw.DefaultPose do
		if motor.Parent or typeof(motor) == "table" then
			local ok, value = pcall(function()
				return motor.C0
			end)
			if ok then
				State.lastCFrames[motor] = value
			end
		end
	end

	State.LoadingProject, State.ProjectLoadThread = previousLoading, previousThread
	State.ProjectWorkStep = previousWorkStep
	if nativeCopy then
		if State.exportSequences[rig] == nativeCopy then State.exportSequences[rig] = nil end
		nativeCopy:Destroy()
	end
	if not result[1] then
		error(result[2], 0)
	end

	if not visualOK then
		error(visualError, 0)
	end

	return table.unpack(result, 2, result.n)
end

local function activateObjectMotorsFromSequence(rig, keyframeSequence)
	if not rig or not keyframeSequence then
		return
	end

	local poseNames = {}
	for _, pose in ipairs(keyframeSequence:GetDescendants()) do
		if pose:IsA("Pose") then
			poseNames[pose.Name] = true
		end
	end

	for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			m:IsA("Motor6D")
			and m:GetAttribute("EclipseAddedObject") == true
			and m.Part1
			and poseNames[m.Part1.Name]
		then
			State.activeObjectMotors[m] = true
		end
	end
end

local function openProjectFromKeyframeSequenceUnlocked(rig, keyframeSequence, settings)
	if not rig or not keyframeSequence then
		return
	end

	CameraRig.resume(rig)
	if State.LiveSession then
		State.LiveSession.leave()
	end

	const claimed, claimError = pcall(require("TrackOrganizationStorage").claimIdentity, rig)
	if not claimed then
		warn("[Eclipse] Rig identity check skipped: " .. tostring(claimError))
	end

	if State.GreasePencil then
		State.GreasePencil.load(nil)
	end

	if State.ScreenEffects then
		State.ScreenEffects.load(nil)
	end

	if State.Physics then
		State.Physics.load(nil)
	end

	Confirm.close(true)
	History.clear()

	stopAllAnimations()

	if State.OnionSkin and State.OnionSkin.Clear then
		pcall(function()
			State.OnionSkin:Clear()
		end)
	end

	State.currentRig = rig
	State.currentProjectSave = if settings
			and settings:IsA("Folder")
			and settings:GetAttribute("EclipseSave") == true
		then settings
		else nil
	table.clear(State.exportSequences)
	State.currentProjectSequence = keyframeSequence
	pcall(function()
		if keyframeSequence:GetAttribute("EclipseHadArmature") then
			local backup = keyframeSequence.Parent
				and keyframeSequence.Parent:FindFirstChild("Armature")
			ArmatureImport.restore(rig, backup)
		else
			ArmatureImport.stash(rig)
		end
	end)
	UI.PluginActiveBool.Value = true
	State.currentProjectSaved = true
	table.clear(State.lastCFrames)
	table.clear(State.extraRigs)
	Membership.clear()
	table.clear(State.activeObjectMotors)
	activateObjectMotorsFromSequence(rig, keyframeSequence)
	syncObjectMotorStates()

	State.Timeline:ClearTimelineData()
	Organization.reset()
	clearRetainedData()
	State.Timeline:LoadProjectSettings(keyframeSequence, settings)
	AnimationEvents.loadSubtitles(settings or keyframeSequence)
	State.Timeline:CaptureDefaultPose(State.currentRig)

	restoreUnparentedStateFromSequence(rig, keyframeSequence)

	State.Rig:LockRigLimbs(State.currentRig, true)
	State.Axis:SetCurrentRig(State.currentRig)

	UI.AnimatorFrame.Visible = false

	State.ignoreSelectionChanged = true
	Selection:Set({})
	State.ignoreSelectionChanged = false

	State.Timeline:BuildTimelineUI(getCurrentRig)
	State.Timeline:GetState().CurrentTime = 0
	State.Timeline:GetState().Playing = false
	State.Timeline:UpdatePlayhead()

	clearAnimButtons()
	if State.currentRig:FindFirstChild("AnimSaves") then
		populateAnimButtons(State.currentRig)
	end

	State.Timeline:SetLooping(keyframeSequence.Loop == true)

	if UI.ProjectNameTextBox then
		UI.ProjectNameTextBox.Text = keyframeSequence.Name
		UI.ProjectNameTextBox.PlaceholderText = keyframeSequence.Name
	end

	importKeyframesFromSequence(rig, keyframeSequence, { DeferVisuals = true })
	if
		not State.currentProjectSave
		and keyframeSequence:FindFirstChild("EclipseTrackOrganization")
	then
		Organization.read(keyframeSequence, State.getAllRigs())
	end

	State.Rig:BuildRigHierarchy(State.currentRig)
	State.Rig:CreateBonesForRig(State.currentRig)
	State.Rig:UpdateBonesFollowRig(State.currentRig)
	State.Timeline:UpdatePlayhead()
	UI.PrimaryFrame.Visible = false
	UI.AnimatorFrame.Visible = true
	History.armGuard()

	if projectOpenedHook then
		task.defer(function()
			pcall(projectOpenedHook, rig, keyframeSequence)
		end)
	end
end

local function openProjectFromKeyframeSequence(rig, keyframeSequence, settings)
	if
		State.LoadingProject and State.ProjectLoadThread ~= coroutine.running()
		or State.Timeline:IsExportLocked()
	then
		return
	end

	if not rig or not rig.Parent or not keyframeSequence or not keyframeSequence.Parent then
		return
	end

	local priorLoading, priorThread, priorWorkStep =
		State.LoadingProject, State.ProjectLoadThread, State.ProjectWorkStep
	State.LoadingProject = true
	State.ProjectLoadThread = coroutine.running()

	local before

	local function captureHomePose()
		if State.currentRig then
			return
		end

		stopAllAnimations()
		require("RigPose").captureHome(rig)
		local pose = require("RigPose").capture(rig)
		local attributes = {}
		for object, properties in pose do
			if object:IsA("BasePart") then
				properties.Size = object.Size
			end

			if object:IsA("Motor6D") then
				properties.C1 = object.C1
				properties.Enabled = object.Enabled
			end

			attributes[object] = {}
			for _, name in
				{
					"EclipseAnimatorDefaultC0",
					"EclipseAnimatorDefaultSize",
					"EclipseRigRestC0",
					"TrackParent",
				}
			do
				attributes[object][name] = object:GetAttribute(name)
			end
		end

		before = { pose = pose, attributes = attributes, armature = ArmatureImport.find(rig) }
	end

	local slice = os.clock()
	State.ProjectWorkStep = function()
		if os.clock() - slice >= 0.012 then
			task.wait()
			slice = os.clock()
		end
	end

	local result = table.pack(xpcall(function()
		captureHomePose()
		return openProjectFromKeyframeSequenceUnlocked(rig, keyframeSequence, settings)
	end, debug.traceback))
	if not result[1] then
		local cleaned, cleanupError = pcall(Project.clearCurrentRig)
		if not cleaned then
			warn("[Eclipse] Open cleanup: " .. tostring(cleanupError))
		end

		if before and rig.Parent then
			local restored, restoreError = pcall(function()
				if before.armature then
					ArmatureImport.restore(rig, before.armature)
				end

				for object, properties in before.pose do
					if object.Parent then
						if properties.Size then
							object.Size = properties.Size
						end

						if properties.C1 then
							object.C1 = properties.C1
							object.Enabled = properties.Enabled
						end

						for _, name in
							{
								"EclipseAnimatorDefaultC0",
								"EclipseAnimatorDefaultSize",
								"EclipseRigRestC0",
								"TrackParent",
							}
						do
							object:SetAttribute(name, before.attributes[object][name])
						end
					end
				end

				require("RigPose").restore(rig, before.pose)
			end)
			if not restored then
				warn("[Eclipse] Open pose recovery: " .. tostring(restoreError))
			end
		end
	end

	State.ProjectWorkStep = priorWorkStep
	State.LoadingProject = priorLoading
	State.ProjectLoadThread = priorThread
	if not result[1] then
		warn("[Eclipse] Could not open " .. keyframeSequence.Name .. ": " .. tostring(result[2]))
		Notification.show(
			"Couldn't open animation",
			(tostring(result[2]):gsub("^.-:%d+: ", ""):gsub("\n.*", ""))
		)
		return false
	end

	if not settings then
		notifyUnmatched("animation")
	end

	return table.unpack(result, 2, result.n)
end

populateAnimButtons = function(rig)
	if not animationList then
		animationList = AnimationList.new(UI.TemplateButton, UI.FrameButton, function(
			targetRig,
			animation,
			button,
			intent
		)
			if State.LoadingProject or State.currentRig then
				return
			end

			if intent == "open" then
				openProjectFromKeyframeSequence(targetRig, animation)
			elseif intent == "preview" then
				playAnimationOnRig(targetRig, animation, button)
			elseif
				#selectedPreviewRigs > 1
				and State.currentAnimations[targetRig]
				and previewSelections[targetRig] == animation
			then
				stopRigPreview(targetRig)
			elseif
				#selectedPreviewRigs <= 1
				and State.currentPlayingTrack
				and State.currentPlayButton == button
				and AnimationList.isPreview(button, animation)
			then
				openProjectFromKeyframeSequence(targetRig, animation)
			else
				playAnimationOnRig(targetRig, animation, button)
			end
		end, State.animButtons, UI.MainFrame)
	end

	if #selectedPreviewRigs > 1 then
		animationList:setRigs(selectedPreviewRigs)
	else
		animationList:setRigs(rig and { rig } or {})
	end
end

local function jumpToNearestSelectedLimbKeyframe(direction, byFrame, frameStep)
	if not UI.isTransportActive() or (not byFrame and not State.currentRig) then
		return
	end

	if not State.Axis or not State.Rig or not State.Timeline then
		return
	end

	if State.Timeline:IsExportLocked() or State.Timeline:IsBlenderKeyframeTransformActive() then
		return
	end

	local timeline = State.Timeline:GetState()
	local currentFrame = State.Timeline:TimeToFrame(timeline.CurrentTime)
	local prefs = require("Preferences")
	local targetFrame
	if direction == "Start" then
		targetFrame = 0
	elseif byFrame then
		targetFrame = math.clamp(
			currentFrame
				+ (direction == "Left" and -1 or 1) * (frameStep or prefs.get("FrameStep") or 1),
			0,
			State.Timeline:GetMaxFrame()
		)
	else
		targetFrame =
			State.Timeline:GetJumpKeyframe(currentFrame, direction, frameStep or prefs.get("KeyframeJumpStep"))
	end

	if not targetFrame then
		return
	end

	Project.finalizeCurrentManipulation()
	if State.pendingScoreHoldConnection then
		State.pendingScoreHoldConnection:Disconnect()
		State.pendingScoreHoldConnection = nil
	end

	State.mouseDownAxisPart = nil
	State.mouseDownSelectedBone = nil
	State.mouseDownMousePos = nil
	State.scoreDragStarted = false
	timeline.Playing = false
	timeline.CurrentTime = State.Timeline:FrameToTime(targetFrame)
	if State.currentRig then
		State.Timeline:ApplyPoseAtTime(State.currentRig, timeline.CurrentTime)
	end

	for _, rig in State.getAllRigs() do
		for _, motor in Parenting.collectMotors(rig) do
			State.lastCFrames[motor] = motor.C0
		end

		State.Rig:UpdateBonesFollowRig(rig)
	end

	State.Axis:RefreshAxis()
	if direction == "Start" then
		State.Timeline:SetTimelineScroll(0)
	end

	State.Timeline:UpdatePlayhead()
	require("EventPlayback").scrub(State.Timeline, timeline.CurrentTime)
end

local function restoreRigToDefaultPose(rig)
	if rig then
		require("Target").releaseRig(rig)
	end

	local nativeRest, nativeSizes = ArmatureRuntime.nativeRestPose(rig)
	require("Faces").restore(rig)
	local master = rig and MasterControl.get(rig, true)
	if master then
		master.C0 = master.DefaultC0
	end

	Properties.restoreDefaults(rig)
	require("RigPose").restoreHome(rig)

	if rig then
		Parenting.restoreDefaults(rig)
	end

	if not rig then
		return
	end

	local defaultPose = nil
	local defaultSize = nil
	local defaultWorldPose = nil
	if State.Timeline then
		local timelineState = State.Timeline:GetState()
		defaultPose = timelineState and timelineState.DefaultPose or nil
		defaultSize = timelineState and timelineState.DefaultSize or nil
		defaultWorldPose = timelineState and timelineState.DefaultWorldPose or nil
	end

	for motor, rest in nativeRest do
		if defaultPose then
			defaultPose[motor] = rest
		end

		if defaultWorldPose then
			defaultWorldPose[motor] = nil
		end
	end

	if defaultSize then
		for part, size in nativeSizes do
			defaultSize[part] = size
		end
	end

	local restoredSizes, restoredJoints = {}, {}

	local function restoreSize(part)
		if not part:IsA("BasePart") or part:IsA("Terrain") then
			return
		end

		local size = nativeSizes[part]
			or part:GetAttribute("EclipseAnimatorDefaultSize")
			or (defaultSize and defaultSize[part])
		if typeof(size) == "Vector3" then
			part.Size = size
		end

		table.insert(restoredSizes, part)
	end

	restoreSize(rig)
	local restWorlds = {}

	for _, motor in ipairs(RigTraversal.rigDescendants(rig)) do
		restoreSize(motor)
		if motor:GetAttribute("EclipseArmatureSkinningHelper") then
			continue
		end

		if motor:IsA("Motor6D") then
			require("RigPose").restoreLoadedC1(motor)
			local stamped = motor:GetAttribute("EclipseAnimatorDefaultC0")
			local defaultC0 = nativeRest[motor]
				or motor:GetAttribute("EclipseArmaturePreviewC0")
				or stamped
				or (defaultPose and defaultPose[motor])
				or motor:GetAttribute("EclipseRigRestC0")
			if defaultC0 then
				motor.C0 = defaultC0
				require("RigPose").rememberRest(motor, defaultC0)
			end

			motor.Transform = CFrame.identity
			local world = not nativeRest[motor]
				and (
					motor.Part1 and motor.Part1:GetAttribute("EclipsePoseBeforePreview")
					or defaultWorldPose and defaultWorldPose[motor]
				)
			if typeof(world) == "CFrame" and motor.Part1 and motor.Part1:IsDescendantOf(rig) then
				restWorlds[motor.Part1] = world
			end

			table.insert(restoredJoints, motor)
		elseif motor:IsA("Bone") then
			local stamped = motor:GetAttribute("EclipseAnimatorDefaultC0")
			local defaultC0 = stamped
				or (defaultPose and defaultPose[BoneMotor.get(motor)])
				or motor:GetAttribute("EclipseRigRestC0")
			if defaultC0 then
				motor.Transform = motor.CFrame:Inverse() * defaultC0
				require("RigPose").rememberRest(motor, defaultC0)
			end

			table.insert(restoredJoints, motor)
		end
	end

	if next(restWorlds) then
		require("NativeJoints").applyWorlds(rig, restWorlds)
	end

	require("Recovery").restoreArmature(rig)
	require("RigPose").assemble(rig)
	require("PartRig").flush(rig, true)
	for _, motor in restoredJoints do
		motor:SetAttribute("EclipseAnimatorDefaultC0", nil)
	end

	for _, part in restoredSizes do
		part:SetAttribute("EclipseAnimatorDefaultSize", nil)
	end

	require("Recovery").forgetRig(rig)
end

local function suspendPreview()
	local timeline = State.Timeline and State.Timeline:GetState()
	if timeline then
		timeline.Playing = false
		if timeline.Exporting then
			timeline.Exporting.Cancelled = true
			return false
		end
	end

	for _, rig in State.getAllRigs() do
		local ok, issue = pcall(restoreRigToDefaultPose, rig)
		if not ok then
			warn("[Eclipse restore] " .. tostring(issue))
		end

		for _, motor in Parenting.collectMotors(rig) do
			State.lastCFrames[motor] = motor.C0
		end
	end

	return true
end

local function gracefulShutdown()
	Project.finalizeCurrentManipulation()
	Project.finishLiveRecording(false)
	stopAllAnimations()
	suspendPreview()
	if State.ScaleGizmo then
		State.ScaleGizmo.clear()
	end

	if State.PropertyGizmo then
		State.PropertyGizmo.select(nil)
	end

	stopAllAnimations()
	require("Faces").clear()
	Confirm.close(true)
	EventPlayback.clear()
	if State.Timeline then
		State.Timeline:CloseEventEditor()
	end

	if State.OnionSkin and State.OnionSkin.Clear then
		pcall(function()
			State.OnionSkin:Clear()
		end)
	end

	if State.Axis and State.Axis.CleanupOrphans then
		pcall(function()
			State.Axis:CleanupOrphans()
		end)
	end

	do
		local cam = workspace.CurrentCamera
		if cam then
			for _, child in ipairs(cam:GetChildren()) do
				if
					child.Name == "_EclipseAnimator_Axis"
					or child:GetAttribute("EclipseAnimator_BonesFolder")
				then
					pcall(function()
						child:Destroy()
					end)
				end
			end
		end
	end

	if State.currentRig then
		for _, rig in ipairs(State.getAllRigs()) do
			pcall(function()
				restoreRigToDefaultPose(rig)
			end)
			pcall(function()
				for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
					if m:IsA("Motor6D") and m:GetAttribute("EclipseAddedObject") == true then
						require("RigPose").restoreObjectJoint(m)
					end
				end
			end)
			if State.Rig then
				pcall(function()
					State.Rig:LockRigLimbs(rig, false)
				end)
				local bonesFolder = nil
				pcall(function()
					bonesFolder = State.Rig:GetBonesFolder(rig)
				end)
				if bonesFolder then
					pcall(function()
						bonesFolder:Destroy()
					end)
				end
			end
		end
	end

	require("NativeJoints").clear()
end

local function getProjectExportName()
	if not UI.ProjectNameTextBox then
		return Config.Defaults.AnimationName
	end

	local typedText = UI.ProjectNameTextBox.Text
	if typedText:match("%S") then
		return Data.sanitizeExportName(typedText)
	end

	local placeholderText = UI.ProjectNameTextBox.PlaceholderText
	if placeholderText:match("%S") then
		return Data.sanitizeExportName(placeholderText)
	end

	return Config.Defaults.AnimationName
end

local function updateSelectionUI(selectedRig)
	MainMenu.updateSelection(UI, selectedRig, selectedRig and #selectedPreviewRigs or 0)
end

local function updateUI()
	selectedPreviewRigs = getSelectedAnimatableRigs()
	local selectedRig = selectedPreviewRigs[1]
	local keep = {}
	for _, rig in selectedPreviewRigs do
		keep[rig] = true
	end

	local remove = {}
	for rig in State.currentAnimations do
		if not keep[rig] then
			table.insert(remove, rig)
		end
	end

	for _, rig in remove do
		stopRigPreview(rig)
	end

	if selectedRig then
		updateSelectionUI(selectedRig)
		populateAnimButtons(selectedRig)
	else
		stopAllAnimations()
		clearAnimButtons()
		updateSelectionUI(nil)
	end
end

local function clearCurrentRig()
	if State.LoadingProject and State.ProjectLoadThread ~= coroutine.running() then
		return
	end

	Project.finishLiveRecording(false)

	if State.Timeline then
		State.Timeline:GetState().Playing = false
	end

	if State.ScaleGizmo then
		State.ScaleGizmo.clear()
	end

	if State.PropertyGizmo then
		State.PropertyGizmo.select(nil)
	end

	require("Faces").clear()
	if State.LiveSession then
		State.LiveSession.leave()
	end

	if State.GreasePencil then
		State.GreasePencil.load(nil)
	end

	if State.ScreenEffects then
		State.ScreenEffects.load(nil)
	end

	if State.Physics then
		State.Physics.load(nil)
	end

	Confirm.close(true)
	EventPlayback.clear()
	Organization.reset()
	clearRetainedData()
	stopAllAnimations()

	if State.OnionSkin and State.OnionSkin.Clear then
		pcall(function()
			State.OnionSkin:Clear()
		end)
	end

	if State.Axis then
		State.Axis:SelectBone(nil)
		State.Axis:ClearAxis()
	end

	if State.currentRig then
		for _, rig in ipairs(State.getAllRigs()) do
			restoreRigToDefaultPose(rig)
			pcall(function()
				ArmatureImport.stash(rig)
			end)
			for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
				if m:IsA("Motor6D") and m:GetAttribute("EclipseAddedObject") == true then
					require("RigPose").restoreObjectJoint(m)
				end
			end

			if State.Rig then
				State.Rig:LockRigLimbs(rig, false)
				local bonesFolder = State.Rig:GetBonesFolder(rig)
				if bonesFolder then
					bonesFolder:Destroy()
				end
			end

			CameraRig.park(rig)
		end

		if State.Rig then
			State.Rig:DestroyHierarchyItems()
			State.Rig:CleanUpOldLockedRigs()
		end
	end

	State.ignoreSelectionChanged = true
	Selection:Set({})
	State.ignoreSelectionChanged = false

	if State.Rig then
		State.Rig:DestroyHierarchyItems()
	end

	require("NativeJoints").clear()
	require("RigPose").forgetHome()
	Properties.forget()
	require("RigCleanup").run()
	State.currentRig = nil
	State.currentProjectSave = nil
	State.currentProjectSequence = nil
	table.clear(State.exportSequences)
	table.clear(State.extraRigs)
	table.clear(State.activeObjectMotors)
	table.clear(State.lastCFrames)

	State.manipulationStartC0 = nil
	State.manipulationMotor = nil
	State.manipulationMotors = nil

	if State.Timeline then
		State.Timeline:ClearTimelineData()
		State.Timeline:GetState().CurrentTime = 0
		State.Timeline:GetState().Playing = false
		State.Timeline:UpdatePlayhead()
	end

	clearAnimButtons()
	updateSelectionUI(nil)

	UI.AlertFrame.Visible = false
	UI.PrimaryFrame.Visible = true
	UI.AnimatorFrame.Visible = false

	UI.PluginActiveBool.Value = false
	History.clear()
end

local function setProjectName(name)
	if UI.ProjectNameTextBox and typeof(name) == "string" then
		UI.ProjectNameTextBox.Text = name
		UI.ProjectNameTextBox.PlaceholderText = name
	end
end

local function updateGizmoMode(mode)
	State.GizmoMode = mode
	if State.Axis then
		State.Axis:SetGizmoMode(mode)
		if State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
		end
	end
end

local function c0Changed(a, b)
	if not a or not b then
		return false
	end

	return a ~= b
end

local function getSelectedMotorData()
	if not UI.isAnimatorActive() or not State.currentRig then
		return nil, nil, nil, nil
	end

	if not State.Axis or not State.Rig or not State.Timeline then
		return nil, nil, nil, nil
	end

	local selectedBone = State.Axis:GetSelectedBone()
	if not selectedBone then
		return nil, nil, nil, nil
	end

	local selectedPart = State.Rig:GetPartFromBone(State.currentRig, selectedBone)
	local motor = selectedPart and State.Rig:GetMotorForPart(State.currentRig, selectedPart) or nil
	local timelineState = State.Timeline:GetState()
	local defaultC0 = timelineState
			and timelineState.DefaultPose
			and timelineState.DefaultPose[motor]
		or nil

	return selectedBone, selectedPart, motor, defaultC0
end

local function snapshotKeyData(kd)
	if not kd then
		return nil
	end

	local s = {}
	for k, v in pairs(kd) do
		if k == "Button" then
		elseif k == "Channels" and type(v) == "table" then
			local ch = {}
			for chId, c in pairs(v) do
				if type(c) == "table" then
					ch[chId] = GraphCurves.clone(c)
				end
			end

			s.Channels = ch
		elseif (k == "GraphCurves" or k == "KeyGroups") and type(v) == "table" then
			s[k] = GraphCurves.clone(v)
		elseif k == "BezierPoints" and type(v) == "table" then
			s.BezierPoints = { v[1], v[2], v[3], v[4] }
		else
			s[k] = v
		end
	end

	return s
end

local function applyKeyDataSnapshot(motor, frame, part, sanitizeName, snapshot)
	local bucket = State.Timeline:GetMotorKeyframeBucket(motor)
	if not bucket then
		return
	end

	GraphCurves.invalidate(bucket)

	local existingKd = bucket[frame]
	local timelineState = State.Timeline:GetState()
	if timelineState then
		if timelineState._motorUniform then
			timelineState._motorUniform[motor] = nil
		end

		if timelineState._motorHasScale then
			timelineState._motorHasScale[motor] = nil
		end
	end

	if snapshot then
		local existingButton = existingKd and existingKd.Button or nil
		local newKd = {}
		for k, v in pairs(snapshot) do
			if k == "Channels" and type(v) == "table" then
				local ch = {}
				for chId, c in pairs(v) do
					ch[chId] = GraphCurves.clone(c)
				end

				newKd.Channels = ch
			elseif (k == "GraphCurves" or k == "KeyGroups") and type(v) == "table" then
				newKd[k] = GraphCurves.clone(v)
			elseif k == "BezierPoints" and type(v) == "table" then
				newKd.BezierPoints = { v[1], v[2], v[3], v[4] }
			else
				newKd[k] = v
			end
		end

		if existingButton then
			newKd.Button = existingButton
		end

		bucket[frame] = newKd
		State.Timeline:CreateOrUpdateTimelineKeyframeButton(part, motor, frame, nil, sanitizeName)
		State.Timeline:_addChannelDiamondAtFrame(motor, frame)
	else
		if existingKd then
			State.Timeline:DeleteKeyframe(existingKd)
		end
	end
end

local function detectChangedChannels(motor, frameNumber, newC0, currentTime, baselineC0)
	return State.Timeline:GetChangedPoseChannels(motor, newC0, currentTime, baselineC0)
end

local function recordCurrentMotorKeyframe(selectedPart, motor)
	if not selectedPart or not motor then
		return
	end

	if not State.Timeline then
		return
	end

	local sanitizeName = State.UIHelpers and State.UIHelpers.SanitizeName
		or function(str)
			return tostring(str or ""):gsub("%s+", "")
		end

	local timeline = State.Timeline:GetState()
	local frameNumber = State.Timeline:TimeToFrame(timeline.CurrentTime)
	local bucket = State.Timeline:GetMotorKeyframeBucket(motor)
	local hadKeyframeBefore = bucket and bucket[frameNumber] ~= nil
	local prevKeyframeC0 = hadKeyframeBefore and bucket[frameNumber].C0 or nil
	local newC0 = Properties.basePose(motor, motor.C0)

	State.Timeline:RecordKeyframeForMotorAtCurrentTime(
		selectedPart,
		motor,
		newC0,
		UI.TrackContainer,
		sanitizeName
	)

	State.currentProjectSaved = false

	local capturedMotor = motor
	local capturedPart = selectedPart
	local capturedFrame = frameNumber
	local capturedHadKeyframe = hadKeyframeBefore
	local capturedPrevC0 = prevKeyframeC0
	local capturedNewC0 = newC0

	History.record(function()
		if capturedHadKeyframe then
			local tl = State.Timeline:GetState()
			local savedTime = tl.CurrentTime
			tl.CurrentTime = capturedFrame / tl.FPS
			State.Timeline:RecordKeyframeForMotorAtCurrentTime(
				capturedPart,
				capturedMotor,
				capturedPrevC0,
				UI.TrackContainer,
				sanitizeName
			)
			tl.CurrentTime = savedTime
		else
			local b = State.Timeline:GetMotorKeyframeBucket(capturedMotor)
			local kd = b and b[capturedFrame]
			if kd then
				State.Timeline:DeleteKeyframe(kd)
			end
		end

		if State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, function()
		local tl = State.Timeline:GetState()
		local savedTime = tl.CurrentTime
		tl.CurrentTime = capturedFrame / tl.FPS
		State.Timeline:RecordKeyframeForMotorAtCurrentTime(
			capturedPart,
			capturedMotor,
			capturedNewC0,
			UI.TrackContainer,
			sanitizeName
		)
		tl.CurrentTime = savedTime
		if State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, tl.CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, "Record " .. capturedPart.Name .. " keyframe", capturedFrame)
end

local function adoptExternalPartMovement(motor)
	if CameraRig.isFov(motor) or CameraRig.isTransform(motor) then
		return
	end

	if not motor or not motor.Part0 or not motor.Part1 then
		return
	end

	if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
		return
	end

	if
		BoneMotor.isAdapter(motor)
		or HeadStabilizer.isEnabled(motor, State.Timeline:GetState().CurrentTime)
	then
		return
	end

	local expected = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
	local actual = motor.Part1.CFrame
	local delta = expected:ToObjectSpace(actual)
	local axisDir, angle = delta:ToAxisAngle()

	if delta.Position.Magnitude > 1e-3 or math.abs(angle) > 1e-3 then
		motor.C0 = motor.Part0.CFrame:Inverse() * actual * motor.C1
	end
end

local function restoreManipulation(transaction, direction)
	local rig = transaction.rig
	if not rig or not rig.Parent then
		return
	end

	local timeline = State.Timeline:GetState()
	timeline.Playing = false
	timeline.CurrentTime = transaction.time
	State.Timeline:ApplyPoseAtTime(rig, transaction.time)
	for targetRig in transaction.graphs do
		if targetRig ~= rig and targetRig.Parent then
			State.Timeline:ApplyPoseAtTime(targetRig, transaction.time)
		end
	end

	for targetRig in transaction.nativeIK or {} do
		if targetRig ~= rig and targetRig.Parent and not transaction.graphs[targetRig] then
			State.Timeline:ApplyPoseAtTime(targetRig, transaction.time)
		end
	end

	for _, item in transaction.motors do
		local motor = item.motor
		if
			motor
			and motor.Parent
			and not (typeof(motor) == "table" and motor.IsEclipseArmatureControl)
		then
			motor.C0 = item[direction]
			State.lastCFrames[motor] = motor.C0
		end
	end

	for targetRig, states in transaction.graphs do
		if targetRig.Parent then
			assert(
				ArmatureRuntime.restore(targetRig, states[direction]),
				"Could not restore the armature edit"
			)
			ArmatureRuntime.evaluate(targetRig)
			if State.Rig then
				State.Rig:UpdateBonesFollowRig(targetRig)
			end
		end
	end

	for targetRig, states in transaction.nativeIK or {} do
		if targetRig.Parent then
			assert(LimbIK.restore(targetRig, states[direction]), "Could not restore the IK edit")
			if State.Rig then
				State.Rig:UpdateBonesFollowRig(targetRig)
			end
		end
	end

	if State.Rig then
		State.Rig:UpdateBonesFollowRig(rig)
	end

	State.Timeline:UpdatePlayhead()
	if State.Axis and State.Axis:GetSelectedBone() then
		State.Axis:RefreshAxis()
		State.Axis:RefreshBoneFade()
	end
end

local function sameAuthoredValue(a, b)
	if typeof(a) ~= typeof(b) then
		return false
	end

	if typeof(a) ~= "table" then
		return a == b
	end

	for key, value in a do
		if not sameAuthoredValue(value, b[key]) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function recordKeyframesForMotors(motorList, descriptionPrefix, manipulation, collectRecords)
	if not motorList or #motorList == 0 then
		return 0
	end

	if not State.Timeline or not UI.isAnimatorActive() then
		return 0
	end

	local sanitizeName = State.UIHelpers and State.UIHelpers.SanitizeName
		or function(str)
			return tostring(str or ""):gsub("%s+", "")
		end

	local timeline = State.Timeline:GetState()
	local frameNumber = State.Timeline:TimeToFrame(timeline.CurrentTime)
	local currentTime = timeline.CurrentTime
	local records = {}

	for _, info in ipairs(motorList) do
		if info.ikFollower and not LimbIK.isDirty(info.motor) then
			continue
		end

		if info.part and info.motor and info.motor.Parent and not info.skipIKRecord then
			if not manipulation and not info.authoredReset and not Properties.is(info.motor) then
				adoptExternalPartMovement(info.motor)
			end

			local propertyValue = Properties.is(info.motor)
				and Properties.readValue(info.motor.Rig, info.motor.PropertyId)
			local newC0 = Properties.is(info.motor) and Properties.encode(propertyValue)
				or Properties.basePose(info.motor, info.motor.C0)
			local bucket = State.Timeline:GetMotorKeyframeBucket(info.motor)
			local beforeSnapshot = bucket and snapshotKeyData(bucket[frameNumber]) or nil

			local changed = detectChangedChannels(
				info.motor,
				frameNumber,
				newC0,
				currentTime,
				Properties.basePose(info.motor, info.startC0)
			)
			local recordedAnything = false

			if
				Properties.is(info.motor)
				or info.forceFull
				or not info.channelIds
					and (LimbIK.isDirty(info.motor) or (#changed == 0 and descriptionPrefix == "Record"))
			then
				State.Timeline:RecordKeyframeForMotorAtCurrentTime(
					info.part,
					info.motor,
					newC0,
					Properties.is(info.motor) and { PropertyValue = propertyValue }
						or UI.TrackContainer,
					sanitizeName
				)
				recordedAnything = true
			elseif info.channelIds or #changed > 0 then
				State.Timeline:RecordPartialKeyframeForMotorAtCurrentTime(
					info.part,
					info.motor,
					newC0,
					info.channelIds or changed,
					sanitizeName
				)
				local kdAfter = bucket[frameNumber]
				if kdAfter and not info.channelIds and not require("Layers").has(timeline) then
					kdAfter.C0 = newC0
					kdAfter.Position = newC0.Position
					kdAfter.Rotation = newC0 - newC0.Position
					State.Timeline:CaptureKeyframeParenting(info.motor, kdAfter, newC0)
				end

				recordedAnything = true
			end

			if recordedAnything then
				local afterSnapshot = snapshotKeyData(bucket[frameNumber])
				LimbIK.markRecorded(info.motor)
				table.insert(records, {
					part = info.part,
					motor = info.motor,
					frame = frameNumber,
					sanitizeName = sanitizeName,
					beforeSnapshot = beforeSnapshot,
					afterSnapshot = afterSnapshot,
					startC0 = info.startC0,
					newC0 = newC0,
				})
			end
		end
	end

	if #records == 0 then
		return 0
	end

	State.currentProjectSaved = false
	if collectRecords then
		collectRecords(records)
		return #records
	end

	local description
	if #records == 1 then
		description = descriptionPrefix .. " " .. records[1].part.Name
	else
		description = descriptionPrefix .. " " .. #records .. " bones"
	end

	local captured = records
	local capturedFrame = frameNumber

	History.record(function()
		for _, r in ipairs(captured) do
			if not manipulation and r.startC0 and r.motor and r.motor.Parent then
				local locked =
					MotorMath.collectTrackParentLockedDescendants(State.currentRig, r.motor)
				r.motor.C0 = r.startC0
				MotorMath.restoreTrackParentLockedDescendants(locked)
			end
		end

		for _, r in ipairs(captured) do
			applyKeyDataSnapshot(r.motor, r.frame, r.part, r.sanitizeName, r.beforeSnapshot)
		end

		if manipulation then
			restoreManipulation(manipulation, "before")
		elseif State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, function()
		for _, r in ipairs(captured) do
			if not manipulation and r.startC0 and r.motor and r.motor.Parent and r.newC0 then
				local locked =
					MotorMath.collectTrackParentLockedDescendants(State.currentRig, r.motor)
				r.motor.C0 = r.newC0
				MotorMath.restoreTrackParentLockedDescendants(locked)
			end
		end

		for _, r in ipairs(captured) do
			applyKeyDataSnapshot(r.motor, r.frame, r.part, r.sanitizeName, r.afterSnapshot)
		end

		if manipulation then
			restoreManipulation(manipulation, "after")
		elseif State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, description, if manipulation then nil else capturedFrame)

	return #records
end

local liveTake

function Project.hasLiveRecording()
	return liveTake ~= nil
end

function Project.finishLiveRecording(cancel)
	local take = liveTake
	if not take then return false end
	liveTake = nil
	if not next(take.records) then return false end
	local function apply(which)
		for _, frames in take.records do
			for _, record in frames do
				if record.motor.Parent then
					applyKeyDataSnapshot(record.motor, record.frame, record.part, record.sanitizeName, record[which])
				end
			end
		end
		require("motionPath").markDirty()
		if State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
		end
	end
	if cancel then
		apply("beforeSnapshot")
	else
		History.record(function() apply("beforeSnapshot") end, function() apply("afterSnapshot") end, "Live recording")
	end
	return true
end

function Project.captureLiveRecording(finishing)
	local timeline = State.Timeline and State.Timeline:GetState()
	local axis = State.Axis
	local manipulating = axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
	if not timeline or not manipulating or not UI.isAnimatorActive() or not State.currentRig
		or timeline.Exporting or State.LoadingProject or State.PhysicsSimulating or History.isApplying()
		or not timeline.Recording or not (timeline.Playing or finishing and liveTake)
	then return nil end
	local infos = State.manipulationMotors
	if not infos or #infos == 0 then return nil end
	if liveTake and (liveTake.infos ~= infos or liveTake.rig ~= State.currentRig) then
		Project.finishLiveRecording(false)
	end
	if not liveTake then
		liveTake = { infos = infos, rig = State.currentRig, baseline = {}, authored = {}, records = {} }
		for _, info in infos do liveTake.baseline[info.motor] = info.startC0 end
	end
	local take = liveTake
	if axis:IsBlenderRotateMode() then axis:FlushBlenderRotateInput() end
	local records, values, handles = {}, {}, {}
	for _, info in infos do
		local motor = info.motor
		if motor and motor.Parent and info.part and not info.skipIKRecord then
			local value = motor.C0
			if take.baseline[motor] and c0Changed(value, take.baseline[motor]) then
				take.authored[motor] = true
			end
			if take.authored[motor] then
				local frames = take.records[motor]
				local previous = frames and frames[State.Timeline:TimeToFrame(timeline.CurrentTime)]
				if not previous or previous.newC0 ~= value then
					local record = table.clone(info)
					record.forceFull, record.ikFollower = true, nil
					table.insert(records, record)
				end
				values[motor] = value
			end
		end
	end
	for _, info in axis:GetManipulationSnapshots() or {} do
		if info.motor and info.motor.Parent then handles[info.motor] = info.motor.C0 end
	end
	if #records > 0 then
		recordKeyframesForMotors(records, "Live recording", {}, function(captured)
			for _, record in captured do
				local frames = take.records[record.motor]
				if not frames then frames = {}; take.records[record.motor] = frames end
				local previous = frames[record.frame]
				if previous then
					previous.afterSnapshot = record.afterSnapshot
					previous.newC0 = record.newC0
				else
					frames[record.frame] = record
				end
			end
		end)
	end
	return { take = take, values = values, handles = handles }
end

function Project.restoreLiveRecording(capture)
	if not capture or capture.take ~= liveTake then return end
	for motor, value in capture.values do
		if motor.Parent then motor.C0 = value end
	end
	for motor, value in capture.handles do
		if motor.Parent then motor.C0 = value end
	end
	for _, info in capture.take.infos do
		if info.motor and info.motor.Parent then
			capture.take.baseline[info.motor] = info.motor.C0
			State.lastCFrames[info.motor] = info.motor.C0
		end
	end
end

local function getSelectedMotorListWithDefaults()
	if not UI.isAnimatorActive() or not State.currentRig then
		return nil
	end

	if not State.Axis or not State.Rig or not State.Timeline then
		return nil
	end

	local property = State.Axis.GetPropertyTarget and State.Axis:GetPropertyTarget()
	if Properties.is(property) and property.PropertyId == "CFrame" and property.Parent then
		return {
			{
				part = property.Part1,
				motor = property,
				startC0 = property.C0,
				defaultC0 = Properties.encode(property.DefaultValue),
				authoredReset = true,
			},
		}
	end

	local bones = State.Axis:GetSelectedBones()
	if not bones or #bones == 0 then
		return nil
	end

	local timelineState = State.Timeline:GetState()
	local defaultPose = timelineState and timelineState.DefaultPose or nil
	if not defaultPose then
		return nil
	end

	local motorList, seen = {}, {}
	for _, bone in ipairs(bones) do
		local part = State.Rig:GetPartFromBone(State.currentRig, bone)
		local motor = part and State.Rig:GetMotorForPart(State.currentRig, part) or nil
		local owner = bone:FindFirstChild("EclipseLimbOwner")
		if not motor and owner and owner:IsA("ObjectValue") and owner.Value then
			motor = require("R6Controls").resolveOwner(owner.Value)
			part = motor.Part1
		end

		local defaultC0 = motor
				and (typeof(motor) == "table" and motor.IsEclipseArmatureControl and Properties.basePose(
					motor,
					motor.RestC0
				) or defaultPose[motor])
			or nil
		if part and motor and defaultC0 and not seen[motor] then
			seen[motor] = true
			table.insert(motorList, {
				part = part,
				motor = motor,
				startC0 = motor.C0,
				defaultC0 = defaultC0,
				authoredReset = true,
				ikControl = bone:GetAttribute("EclipseLimbControl"),
			})
		end
	end

	if #motorList == 0 then
		return nil
	end

	return motorList
end

local function resetSelectedMotors(component)
	local motorList = getSelectedMotorListWithDefaults()
	if not motorList then
		return 0
	end

	local groups, nativeIK = {}, {}
	for _, info in motorList do
		local motor = info.motor
		local owner = Properties.is(motor) and motor.Rig or nil
		if not owner then
			local part = motor.Part1
			for _, rig in State.getAllRigs() do
				if typeof(part) == "Instance" and (part == rig or part:IsDescendantOf(rig))
					and (not owner or rig:IsDescendantOf(owner)) then
					owner = rig
				end
			end
		end
		owner = owner or State.currentRig
		groups[owner] = groups[owner] or {}
		table.insert(groups[owner], info)
	end

	local recordedMotors = {}
	for rig, infos in groups do
		local property = Properties.is(infos[1].motor)
		local before = not property and LimbIK.snapshot(rig) or nil
		if not property then
			LimbIK.resetSelected(rig, infos, component, Properties.scaleFactor)
		end
		for _, info in infos do
			table.insert(recordedMotors, info)
			if info.ikReset then continue end
			local locked = MotorMath.collectTrackParentLockedDescendants(rig, info.motor)
			if component == "Position" then
				info.motor.C0 = info.motor.C0.Rotation + info.defaultC0.Position * Properties.scaleFactor(info.motor)
			else
				info.motor.C0 = info.defaultC0.Rotation + info.motor.C0.Position
			end
			MotorMath.restoreTrackParentLockedDescendants(locked)
		end
		local entry = not property and LimbIK.getRig(rig) or nil
		if entry then
			LimbIK.apply(rig, State.Timeline:GetState().CurrentTime, false)
			HeadStabilizer.apply(rig, State.Timeline:GetState().CurrentTime, false, entry.motors, entry.map)
		end
		if before then nativeIK[rig] = { before = before, after = LimbIK.snapshot(rig) } end
		if State.Rig then State.Rig:UpdateBonesFollowRig(rig) end
	end
	motorList = recordedMotors
	local transaction = next(nativeIK) and {
		rig = State.currentRig,
		time = State.Timeline:GetState().CurrentTime,
		motors = {}, graphs = {}, nativeIK = nativeIK,
	} or nil

	if State.Axis and State.Axis:GetSelectedBone() then
		State.Axis:RefreshAxis()
		State.Axis:RefreshBoneFade()
	end

	local recorded = recordKeyframesForMotors(
		motorList,
		"Reset " .. string.lower(component) .. " for",
		transaction
	)
	if transaction then
		for rig, snapshot in transaction.nativeIK do snapshot.after = LimbIK.snapshot(rig) end
	end

	return recorded
end

local function resetSelectedMotorPositions()
	return resetSelectedMotors("Position")
end

local function resetSelectedMotorOrientations()
	return resetSelectedMotors("Orientation")
end

local function recordPartialKeyframesForChannels(targets, descriptionPrefix)
	if not targets or #targets == 0 then
		return 0
	end

	if not State.Timeline or not UI.isAnimatorActive() then
		return 0
	end

	local sanitizeName = State.UIHelpers and State.UIHelpers.SanitizeName
		or function(str)
			return tostring(str or ""):gsub("%s+", "")
		end

	local timeline = State.Timeline:GetState()
	local frameNumber = State.Timeline:TimeToFrame(timeline.CurrentTime)
	local records = {}

	for _, t in ipairs(targets) do
		if t.part and t.motor and t.motor.Parent and t.channelIds and #t.channelIds > 0 then
			local bucket = State.Timeline:GetMotorKeyframeBucket(t.motor)
			local beforeSnapshot = bucket and snapshotKeyData(bucket[frameNumber]) or nil

			State.Timeline:RecordPartialKeyframeForMotorAtCurrentTime(
				t.part,
				t.motor,
				Properties.basePose(t.motor, t.motor.C0),
				t.channelIds,
				sanitizeName
			)

			local afterSnapshot = bucket and snapshotKeyData(bucket[frameNumber]) or nil

			table.insert(records, {
				part = t.part,
				motor = t.motor,
				frame = frameNumber,
				sanitizeName = sanitizeName,
				beforeSnapshot = beforeSnapshot,
				afterSnapshot = afterSnapshot,
			})
		end
	end

	if #records == 0 then
		return 0
	end

	State.currentProjectSaved = false

	local description
	if #records == 1 then
		description = descriptionPrefix .. " " .. records[1].part.Name .. " channels"
	else
		description = descriptionPrefix .. " " .. #records .. " partial keyframes"
	end

	local captured = records
	local capturedFrame = frameNumber

	History.record(function()
		for _, r in ipairs(captured) do
			applyKeyDataSnapshot(r.motor, r.frame, r.part, r.sanitizeName, r.beforeSnapshot)
		end

		if State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, function()
		for _, r in ipairs(captured) do
			applyKeyDataSnapshot(r.motor, r.frame, r.part, r.sanitizeName, r.afterSnapshot)
		end

		if State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, description, capturedFrame)

	return #records
end

local function recordTimelineSelection(allTracks, masterItem)
	local timeline, rig, axis = State.Timeline, State.Rig, State.Axis
	if
		not timeline
		or not rig
		or not UI.isAnimatorActive()
		or State.LoadingProject
		or timeline:IsExportLocked()
		or require("BlenderEdit").blocked()
		or timeline:IsBlenderKeyframeTransformActive()
		or axis
			and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
	then
		return 0
	end

	local selectedOwners, rowOwners = {}, {}
	if allTracks then
		local projectOwners, indexed = {}, {}
		for _, owner in State.getAllRigs() do
			projectOwners[owner] = true
		end

		local function index(item, inheritedOwner)
			if not item or indexed[item] or item._destroyed then
				return
			end

			indexed[item] = true
			local owner = item.trackIsMaster and item.linkedRigInstance
				or item.grandpa and item.grandpa.linkedRigInstance
				or inheritedOwner
			if projectOwners[owner] then
				rowOwners[item] = owner
			end

			for _, child in item.childItems or {} do
				index(child, owner)
			end
		end

		for _, item in rig._rootItems or rig._masterItems or {} do
			index(item, nil)
		end

		local function selectOwner(item)
			if item and item.itemKind == "channel" then
				item = item.parentBoneItem
			end

			local owner = item and rowOwners[item]
			if not owner or item.disabled then
				return
			end

			local kind = item.itemKind
			if item.trackIsMaster then
				selectedOwners[owner] = true
				return
			end

			if
				kind == "folder"
				or kind == "properties"
				or kind == "events"
				or kind == "faces"
				or kind == "subtitles"
				or kind == "cameraattach"
			then
				return
			end

			local motor = item.fetchMotor and item:fetchMotor()
			if
				motor
				and motor.Parent
				and motor.Part1
				and (kind ~= "property" or motor.PropertyId == "CFrame")
			then
				selectedOwners[owner] = true
			end
		end

		for item in rig._selectedItems or {} do
			selectOwner(item)
		end

		local channels = rig.GetSelectedChannels and rig:GetSelectedChannels() or {}
		for _, item in channels do
			selectOwner(item)
		end

		if not next(rig._selectedItems or {}) and #channels == 0 and axis then
			for _, bone in axis:GetSelectedBones() or {} do
				for owner in projectOwners do
					local part = rig:GetPartFromBone(owner, bone)
					if part and rig:GetMotorForPart(owner, part) then
						selectedOwners[owner] = true
						break
					end
				end
			end
		end

		if masterItem then
			table.clear(selectedOwners)
			selectOwner(masterItem)
		end

		if not next(selectedOwners) then
			return 0
		end
	end

	local targets, byMotor, visited = {}, {}, {}

	local function add(motor, id)
		if not motor or not motor.Parent or not motor.Part1 then
			return
		end

		local entry = byMotor[motor]
		if not entry then
			entry = { motor = motor, part = motor.Part1, channelIds = {} }
			byMotor[motor] = entry
			table.insert(targets, entry)
		end

		if id and not entry.forceFull then
			if not table.find(entry.channelIds, id) then
				table.insert(entry.channelIds, id)
			end
		elseif not id then
			entry.forceFull = true
			entry.channelIds = nil
		end
	end

	local function visit(item, descendants)
		if not item or visited[item] or item.disabled then
			return
		end

		visited[item] = true
		local kind = item.itemKind
		local inScope = not allTracks or selectedOwners[rowOwners[item]]
		if inScope and kind == "channel" then
			local row = item.parentBoneItem
			if row and not row.disabled then
				add(row:fetchMotor(), if allTracks then nil else item.channelId)
			end
		elseif
			inScope
			and kind ~= "cameraattach"
			and kind ~= "events"
			and kind ~= "faces"
			and kind ~= "subtitles"
		then
			if item.fetchMotor then
				add(item:fetchMotor())
			end
		end

		if
			descendants
			or item.trackIsMaster
			or kind == "folder"
			or kind == "properties"
			or kind == "armature"
		then
			for _, child in item.childItems or {} do
				visit(child, true)
			end
		end
	end

	if allTracks then
		for _, item in rig._rootItems or rig._masterItems or {} do
			visit(item, true)
		end
	else
		for item in rig._selectedItems or {} do
			visit(item, false)
		end

		for _, item in rig.GetSelectedChannels and rig:GetSelectedChannels() or {} do
			visit(item, false)
		end

		if not next(visited) and axis then
			for _, bone in axis:GetSelectedBones() or {} do
				for _, owner in State.getAllRigs() do
					local part = rig:GetPartFromBone(owner, bone)
					local motor = part and rig:GetMotorForPart(owner, part)
					if motor then
						add(motor)
						break
					end
				end
			end
		end
	end

	if #targets == 0 then
		return 0
	end

	timeline:GetState().Playing = false
	return recordKeyframesForMotors(targets, "Record")
end

local function recordKeyframesForAllSelected()
	return recordTimelineSelection(false)
end

function Project.recordAllTrackKeyframes()
	return recordTimelineSelection(true)
end

function Project.recordRigTrackKeys(item)
	if not item or item._destroyed or item.disabled or not item.trackIsMaster or item.itemKind == "origin" then return 0 end
	return recordTimelineSelection(true, item)
end

function Project.recordTrackKey(item)
	local timeline, axis = State.Timeline, State.Axis
	if
		State.LoadingProject
		or not UI.isAnimatorActive()
		or not timeline
		or timeline:IsExportLocked()
		or timeline:IsBlenderKeyframeTransformActive()
		or require("BlenderEdit").blocked()
		or (
			axis
			and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
		)
	then
		return 0
	end

	if not item or item.disabled or item.trackIsMaster then
		return 0
	end

	local kind = item.itemKind
	if
		kind == "folder"
		or kind == "properties"
		or kind == "armature"
		or kind == "events"
		or kind == "faces"
		or kind == "subtitles"
		or kind == "cameraattach"
	then
		return 0
	end

	local row = kind == "channel" and item.parentBoneItem or item
	local motor = row and row:fetchMotor()
	if not motor or not motor.Parent or not motor.Part1 or (row and row.disabled) then
		return 0
	end

	timeline:GetState().Playing = false
	if Properties.is(motor) then
		return State.PropertySettings
				and State.PropertySettings.addAtCurrentTime(motor) ~= nil
				and 1
			or 0
	end

	if kind == "channel" then
		if not item.channelId then
			return 0
		end

		return recordPartialKeyframesForChannels(
			{ { part = motor.Part1, motor = motor, channelIds = { item.channelId } } },
			"Record"
		)
	end

	return recordKeyframesForMotors({ { part = motor.Part1, motor = motor } }, "Record")
end

local function appendIKManipulationEntries(list)
	if not State.currentRig or not list then
		return
	end

	local properties = State.Axis and State.Axis.GetMixedPropertyMotors and State.Axis:GetMixedPropertyMotors()
	for _, member in properties or {} do
		if member.Parent and member.Rig.Parent then
			local exists = false
			for _, entry in list do
				if entry.motor == member then
					exists = true
					break
				end
			end

			if not exists then
				table.insert(list, { part = member.Part1, motor = member, startC0 = member.C0 })
			end
		end
	end

	LimbIK.appendManipulation(State.currentRig, list)
	for _, chainBone in ipairs(BoneIK.gatherChainBones(State.currentRig)) do
		local adapter = BoneMotor.get(chainBone)
		local exists = false
		for _, e in ipairs(list) do
			if e.motor == adapter then
				exists = true
				break
			end
		end

		if not exists then
			table.insert(list, {
				part = chainBone,
				motor = adapter,
				startC0 = adapter.C0,
			})
		end
	end
end

local function finalizeCurrentManipulation()
	if State.CameraPreview and State.CameraPreview.isViewRotating() then
		return State.CameraPreview.finishViewRotation(false)
	end

	ArmatureRuntime.endDeferredEdits()

	for _, rig in State.getAllRigs() do
		if ArmatureRuntime.isRig(rig) then
			ArmatureRuntime.evaluate(rig)
		end
	end

	if State.PropertyGizmo and State.PropertyGizmo.isEditing() then
		return State.PropertyGizmo.finish(false)
	end

	if not State.Axis then
		return false
	end

	local wasManipulating = State.Axis:IsHoldingAxis()
		or State.Axis:IsBlenderGrabMode()
		or State.Axis:IsBlenderRotateMode()
	if not wasManipulating then
		return false
	end

	Project.captureLiveRecording(true)
	if liveTake then
		State.Axis:StopDrag()
		Project.finishLiveRecording(false)
		State.manipulationStartC0 = nil
		State.manipulationMotor = nil
		State.manipulationMotors = nil
		return true
	end

	local snapshots, rigBefore, editRig, rigSnapshots, nativeIKSnapshots =
		State.Axis:GetManipulationSnapshots()
	State.Axis:StopDrag()

	local manipMotors = State.manipulationMotors
	if (not manipMotors or #manipMotors == 0) and State.manipulationMotor then
		local selectedBone = State.Axis:GetSelectedBone()
		local selectedPart = selectedBone
				and State.Rig
				and State.Rig:GetPartFromBone(State.currentRig, selectedBone)
			or nil
		if selectedPart and State.manipulationStartC0 then
			manipMotors = {
				{
					part = selectedPart,
					motor = State.manipulationMotor,
					startC0 = State.manipulationStartC0,
				},
			}
		end
	end

	local validMotors = {}
	local anyChanged = false
	if manipMotors then
		for _, info in ipairs(manipMotors) do
			if info.motor and info.motor.Parent and info.startC0 and info.part then
				table.insert(validMotors, info)
				if c0Changed(info.startC0, info.motor.C0) or LimbIK.isDirty(info.motor) then
					anyChanged = true
				end
			end
		end
	end

	local timeline = State.Timeline and State.Timeline:GetState() or nil
	local transaction = {
		rig = editRig or State.currentRig,
		time = timeline and timeline.CurrentTime or 0,
		motors = {},
		graphs = {},
		nativeIK = {},
	}
	rigSnapshots = rigSnapshots or (rigBefore and { [transaction.rig] = rigBefore }) or {}
	for rig, before in rigSnapshots do
		local after = ArmatureRuntime.snapshot(rig)
		transaction.graphs[rig] = { before = before, after = after }
		if not sameAuthoredValue(before, after) then
			anyChanged = true
		end
	end

	for rig, before in nativeIKSnapshots or {} do
		local after = LimbIK.snapshot(rig)
		transaction.nativeIK[rig] = { before = before, after = after }
		if not sameAuthoredValue(before, after) then
			anyChanged = true
		end
	end

	local starts = {}
	for _, snapshot in snapshots or {} do
		starts[snapshot.motor] = snapshot.startC0
	end

	for _, info in validMotors do
		table.insert(transaction.motors, {
			motor = info.motor,
			before = starts[info.motor] or info.startC0,
			after = info.motor.C0,
		})
	end

	local canRecord = UI.isAnimatorActive()
		and State.currentRig
		and State.Timeline
		and timeline
		and timeline.Recording
		and not timeline.Playing

	local recorded = 0
	if canRecord and anyChanged and #validMotors > 0 then
		recorded = recordKeyframesForMotors(validMotors, "Manipulate", transaction)
	end

	if anyChanged and recorded == 0 and transaction.rig then
		History.record(function()
			restoreManipulation(transaction, "before")
		end, function()
			restoreManipulation(transaction, "after")
		end, "Manipulate bones")
	end

	for _, info in validMotors do
		State.lastCFrames[info.motor] = info.motor.C0
	end

	State.manipulationStartC0 = nil
	State.manipulationMotor = nil
	State.manipulationMotors = nil

	return true
end

local function cancelCurrentManipulation()
	if not State.Axis then
		return
	end

	Project.finishLiveRecording(true)
	State.Axis:CancelDrag()
	State.manipulationStartC0 = nil
	State.manipulationMotor = nil
	State.manipulationMotors = nil
end

local function isPointInsideGui(guiObject, x, y)
	if not guiObject or not guiObject.Parent then
		return false
	end

	if guiObject.Visible == false then
		return false
	end

	local absPos = guiObject.AbsolutePosition
	local absSize = guiObject.AbsoluteSize

	return x >= absPos.X
		and x <= absPos.X + absSize.X
		and y >= absPos.Y
		and y <= absPos.Y + absSize.Y
end

local function isMouseOverAnimButton()
	local mousePos = UserInputService:GetMouseLocation()
	local x = mousePos.X
	local y = mousePos.Y

	for _, btn in ipairs(State.animButtons) do
		if btn and btn.Parent and btn.Visible and isPointInsideGui(btn, x, y) then
			return true
		end
	end

	return false
end

function syncObjectMotorStates()
	if not State.currentRig then
		return
	end

	for _, rig in ipairs(State.getAllRigs()) do
		for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
			if m:IsA("Motor6D") and m:GetAttribute("EclipseAddedObject") == true then
				if State.activeObjectMotors[m] == true and not Organization.isRemoved(m.Part1) then
					require("RigPose").setObjectJoint(m, true)
				else
					require("RigPose").restoreObjectJoint(m)
				end
			end
		end
	end
end

local function refreshStructure(targets)
	WorkBudget.run(function()
		State.Timeline:EnsureTransformChannelStarts()
		syncObjectMotorStates()
		State.Timeline:InvalidateMotorListCache()
		if structureBatch then
			structureBatch.dirty = true
			if targets and structureBatch.rigs ~= false then
				structureBatch.rigs = structureBatch.rigs or {}
				for rig in targets do
					structureBatch.rigs[rig] = true
				end
			else
				structureBatch.rigs = false
			end

			return
		end

		State.Rig:BuildRigHierarchy(State.currentRig)
		for _, rig in ipairs(State.getAllRigs()) do
			if not targets or targets[rig] then
				State.Rig:CreateBonesForRig(rig)
			end
		end

		State.Timeline:UpdatePlayhead()
	end)
end

local function refreshTimelineAfterStructureChange()
	refreshStructure(nil)
end

local function batchStructure(callback)
	if structureBatch then
		return callback()
	end

	local batch = { dirty = false }
	structureBatch = batch
	if State.Rig then
		State.Rig._batchHold = true
	end

	local result = table.pack(xpcall(callback, debug.traceback))
	structureBatch = nil
	if State.Rig then
		State.Rig._batchHold = nil
	end

	if batch.dirty and State.Timeline then
		local flushed, flushError = xpcall(function()
			refreshStructure(batch.rigs or nil)
			if batch.visuals then
				for motor in State.Timeline:GetState().Keyframes do
					State.Timeline:RefreshAllChannelDiamondsForMotor(motor)
				end

				State.Timeline:RefreshAllKeyframeVisuals()
			end

			if batch.pose and State.currentRig then
				State.Timeline:ApplyPoseAtTime(
					State.currentRig,
					State.Timeline:GetState().CurrentTime
				)
			end
		end, debug.traceback)
		if not flushed and result[1] then
			result = table.pack(false, flushError)
		end
	end

	if batch.changed and Project.structureChanged then
		local saved, saveError = xpcall(Project.structureChanged, debug.traceback)
		if not saved and result[1] then
			result = table.pack(false, saveError)
		end
	end

	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

local function openEmptyProject(save)
	clearCurrentRig()
	State.currentProjectSave = save
	State.currentProjectSequence = nil
	State.currentProjectSaved = save ~= nil
	State.Timeline:LoadProjectSettings(nil, save)
	AnimationEvents.loadSubtitles(save)
	State.Timeline:SetLooping(not save or save:GetAttribute("Loop") ~= false)
	State.Timeline:SetRecording(true)
	setProjectName(
		save and save.Name
			or Data.getNextDefaultProjectName(require("root").get("EclipseAnimator_Saves", false))
	)
	UI.PrimaryFrame.Visible = false
	UI.AnimatorFrame.Visible = true
	UI.PluginActiveBool.Value = true
	State.Timeline:BuildTimelineUI(getCurrentRig)
	State.Timeline:UpdatePlayhead()
	State.Rig:BuildRigHierarchy(nil)
	History.armGuard()
end

local function captureRigMembership(rig)
	local data = Membership.capture(State.Timeline:GetState(), rig)
	local active = {}
	for motor, enabled in State.activeObjectMotors do
		if Membership.belongs(motor, rig, data.owned) then
			active[motor] = enabled
		end
	end

	return {
		rig = rig,
		rigs = State.getProjectRigs(),
		data = data,
		organization = Organization.snapshot(),
		events = AnimationEvents.get(rig),
		active = active,
		armature = ArmatureImport.find(rig),
	}
end

local function setRigList(rigs)
	const ordered = {}
	for _, rig in rigs do
		if rig.Parent then
			table.insert(ordered, rig)
		end
	end

	for _, rig in rigs do
		if not rig.Parent then
			table.insert(ordered, rig)
		end
	end

	State.currentRig = ordered[1]
	table.clear(State.extraRigs)
	for i = 2, #ordered do
		table.insert(State.extraRigs, ordered[i])
	end

	State.Axis:SetCurrentRig(State.currentRig)
end

local function prepareMembershipChange()
	stopAllAnimations()
	EventPlayback.clear()
	State.Timeline:CloseEventEditor()
	State.Timeline:ClearSelectedKeyframes()
	if State.OnionSkin then
		State.OnionSkin:Clear()
	end

	State.Axis:StopDrag()
	State.Axis:SelectBone(nil)
	State.Axis:ClearAxis()
	State.Rig:DestroyHierarchyItems()
end

local function detachRig(snapshot, organization)
	local rig = snapshot.rig
	prepareMembershipChange()
	if rig.Parent then
		restoreRigToDefaultPose(rig)
	end

	for motor, c0 in snapshot.data.DefaultPose do
		if motor.Parent then
			motor.C0 = c0
			motor:SetAttribute("EclipseAnimatorDefaultC0", nil)
		end
	end

	if rig.Parent then
		ArmatureImport.stash(rig)
	end

	for part, size in snapshot.data.DefaultSize do
		if part.Parent then
			part.Size = size
		end
	end

	if rig.Parent then
		State.Rig:LockRigLimbs(rig, false)
	end

	local bones = State.Rig:GetBonesFolder(rig)
	if bones then
		bones.Parent = nil
	end

	for motor in snapshot.active do
		State.activeObjectMotors[motor] = nil
		if motor.Parent then
			require("RigPose").restoreObjectJoint(motor)
		end
	end

	for motor in State.lastCFrames do
		if Membership.belongs(motor, rig, snapshot.data.owned) then
			State.lastCFrames[motor] = nil
		end
	end

	Membership.remove(State.Timeline:GetState(), rig, snapshot.data)
	AnimationEvents.detach(rig)
	local remaining = {}
	for _, candidate in State.getProjectRigs() do
		if candidate ~= rig then
			table.insert(remaining, candidate)
		end
	end

	setRigList(remaining)
	Organization.removeRig(rig)
	if organization then
		Organization.restore(organization, "membership")
	end

	refreshTimelineAfterStructureChange()
	clearAnimButtons()
	State.currentProjectSaved = false
	CameraRig.park(rig)
end

local function attachRig(snapshot)
	CameraRig.resume(snapshot.rig)
	prepareMembershipChange()
	setRigList(snapshot.rigs)
	if snapshot.rig.Parent and snapshot.armature then
		ArmatureImport.restore(snapshot.rig, snapshot.armature)
	end

	Membership.restore(State.Timeline:GetState(), snapshot.data)
	for motor, enabled in snapshot.active do
		State.activeObjectMotors[motor] = enabled
	end

	AnimationEvents.attach(snapshot.rig, snapshot.events)
	Organization.restore(snapshot.organization, "membership")
	if snapshot.rig.Parent then
		State.Rig:LockRigLimbs(snapshot.rig, true)
	end

	refreshStructure({ [snapshot.rig] = true })
	State.Timeline:ApplyPoseAtTime(State.currentRig, State.Timeline:GetState().CurrentTime)
	State.currentProjectSaved = false
end

local function removeRigFromTimeline(rig, options)
	if rig.Parent and not (options and options.Loading) and Organization.cameraHasShake(rig) then
		require("Notification").show(
			"CAMERA SHAKE",
			"Move or remove this camera's shake tracks before removing the camera.",
			4
		)
		return false
	end

	if not table.find(State.getProjectRigs(), rig) then
		return false
	end

	Project.finalizeCurrentManipulation()
	local snapshot = captureRigMembership(rig)
	detachRig(snapshot)
	local after = Organization.snapshot()
	if not (options and options.Loading) then
		History.record(function()
			attachRig(snapshot)
		end, function()
			detachRig(snapshot, after)
		end, "Remove rig")
	end

	return true, snapshot
end

local function addRigToTimeline(rig, options)
	if rig then
		rig = require("rig").localize(rig)
	end

	if not rig or not UI.isAnimatorActive(options and options.Loading == true) then
		return false
	end

	if not State.Rig:IsAnimatable(rig) then
		Notification.show("INVALID OBJECT", rig.Name .. " has no supported animatable properties.")
		return
	end

	if rig == State.currentRig or table.find(State.extraRigs, rig) then
		if not (options and options.Loading) then
			Notification.show("ALREADY ADDED", rig.Name .. " is already on the timeline.")
		end

		return
	end

	for _, existing in ipairs(State.getAllRigs()) do
		if
			existing ~= rig
			and existing.Name == rig.Name
			and not (options and options.AllowDuplicateName)
			and not (
				options
				and options.MeshScaleTarget
				and rig:IsA("DataModelMesh")
				and rig.Parent:IsA("BasePart")
			)
		then
			Notification.show(
				"DUPLICATE NAME",
				"Two rigs on the timeline can't share the name \""
					.. rig.Name
					.. '". Rename one first.'
			)
			return
		end
	end

	Project.finalizeCurrentManipulation()
	local before = Organization.snapshot()
	CameraRig.resume(rig)
	const claimed, claimError = pcall(require("TrackOrganizationStorage").claimIdentity, rig)
	if not claimed then
		warn("[Eclipse] Rig identity check skipped: " .. tostring(claimError))
	end
	if
		Properties.propertyOnly(rig)
		and #Properties.list(rig, true) == 0
		and not (options and options.Loading)
	then
		local first = Properties.catalog(rig)[1]
		if first then
			Properties.enable(rig, first.id, true)
		end
	end

	if State.currentRig then
		table.insert(State.extraRigs, rig)
	else
		setRigList({ rig })
	end

	State.Timeline:CaptureDefaultPoseAdditive(
		rig,
		not (options and options.Loading) or options.NewRig == true
	)
	if not (options and options.Loading) or options.NewRig then
		State.Timeline:InitializeRotationModeForRig(rig)
	end

	State.Rig:LockRigLimbs(rig, true)

	refreshStructure({ [rig] = true })
	if State.setWorkspaceSelection then
		State.setWorkspaceSelection(false)
	end

	local ignore = State.ignoreSelectionChanged
	State.ignoreSelectionChanged = true
	local cleared, clearError = pcall(function()
		Selection:Set({})
	end)
	State.ignoreSelectionChanged = ignore
	if not cleared then
		error(clearError, 0)
	end

	State.currentProjectSaved = false
	if not (options and options.Loading) then
		local snapshot = captureRigMembership(rig)
		History.record(function()
			detachRig(snapshot, before)
		end, function()
			attachRig(snapshot)
		end, "Add rig")
		Notification.show(
			Properties.propertyOnly(rig) and "OBJECT ADDED" or "RIG ADDED",
			rig.Name .. " was added to the timeline."
		)
		if structureBatch then
			structureBatch.changed = true
		elseif Project.structureChanged then
			Project.structureChanged()
		end
	end

	return true
end

local function findNearestRigPart(position)
	local best, bestDist = nil, math.huge
	for _, rig in ipairs(State.getAllRigs()) do
		for _, desc in ipairs(RigTraversal.rigDescendants(rig)) do
			if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
				local dist = (desc.Position - position).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = desc
				end
			end
		end
	end

	return best
end

local function addObjectToTimeline(object, options)
	return addRigToTimeline(object, options)
end

local function beginScoreDrag(axis)
	if State.scoreDragStarted then
		return
	end

	if not State.Axis or not State.Rig then
		return
	end

	local mousePos = EditorInput:GetViewportMouseLocation()
	if not mousePos then
		return
	end

	if State.pendingScoreHoldConnection then
		State.pendingScoreHoldConnection:Disconnect()
		State.pendingScoreHoldConnection = nil
	end

	if State.Axis:GetSelectedBone() ~= State.mouseDownSelectedBone then
		return
	end

	local selectedPart = State.Rig:GetPartFromBone(State.currentRig, State.mouseDownSelectedBone)
	local motor = selectedPart and State.Rig:GetMotorForPart(State.currentRig, selectedPart) or nil
	local success = State.Axis:StartDrag(axis, mousePos)

	if success then
		State.scoreDragStarted = true
		State.manipulationMotor = motor
		State.manipulationStartC0 = motor and motor.C0 or nil
		State.manipulationMotors = {}
		for _, bone in State.Axis:GetSelectedBones() do
			local part = State.Rig:GetPartFromBone(State.currentRig, bone)
			local selectedMotor = part and State.Rig:GetMotorForPart(State.currentRig, part)
			if selectedMotor then
				table.insert(
					State.manipulationMotors,
					{ part = part, motor = selectedMotor, startC0 = selectedMotor.C0 }
				)
			end
		end

		appendIKManipulationEntries(State.manipulationMotors)
	end
end

Project.openEmptyProject = openEmptyProject
Project.notifyUnmatched = notifyUnmatched
Project.removeRigFromTimeline = removeRigFromTimeline
Project.getCurrentRig = getCurrentRig
Project.stopAllAnimations = stopAllAnimations
Project.getSelectedAnimatableRig = getSelectedAnimatableRig
Project.getSelectedAnimatableRigs = getSelectedAnimatableRigs
Project.clearAnimButtons = clearAnimButtons
Project.playAnimationOnRig = playAnimationOnRig
Project.populateAnimButtons = populateAnimButtons
Project.jumpToNearestSelectedLimbKeyframe = jumpToNearestSelectedLimbKeyframe
Project.jumpToStart = function()
	if
		State.LoadingProject
		or not State.currentRig
		or not State.Timeline
		or State.Timeline:IsExportLocked()
	then
		return
	end

	jumpToNearestSelectedLimbKeyframe("Start", true)
end

Project.stepFrame = function(direction, frameStep)
	jumpToNearestSelectedLimbKeyframe(direction, true, frameStep)
end

Project.restoreRigToDefaultPose = restoreRigToDefaultPose
Project.suspendPreview = suspendPreview
Project.getProjectExportName = getProjectExportName
Project.updateSelectionUI = updateSelectionUI
Project.updateUI = updateUI
Project.clearCurrentRig = clearCurrentRig
Project.appendIKManipulationEntries = appendIKManipulationEntries
Project.updateGizmoMode = updateGizmoMode
Project.c0Changed = c0Changed
Project.getSelectedMotorData = getSelectedMotorData
Project.recordCurrentMotorKeyframe = recordCurrentMotorKeyframe
Project.recordKeyframesForAllSelected = recordKeyframesForAllSelected
Project.resetSelectedMotorPositions = resetSelectedMotorPositions
Project.resetSelectedMotorOrientations = resetSelectedMotorOrientations
Project.finalizeCurrentManipulation = finalizeCurrentManipulation
Project.cancelCurrentManipulation = cancelCurrentManipulation
Project.isPointInsideGui = isPointInsideGui
Project.isMouseOverAnimButton = isMouseOverAnimButton
Project.beginScoreDrag = beginScoreDrag
Project.gracefulShutdown = gracefulShutdown

function Project.addSelectionToTimeline(selected, options)
	selected = selected or getSelectedAnimatableRigs()
	local added = 0
	local function addAll()
		for _, object in selected do
			if object.Parent and addRigToTimeline(object, options) then
				added += 1
			end
		end
	end

	if #selected > 1 then
		batchStructure(addAll)
	else
		addAll()
	end

	return added
end

Project.addRigToTimeline = addRigToTimeline
Project.restoreRigMembership = attachRig
Project.addObjectToTimeline = addObjectToTimeline
Project.refreshTimelineAfterStructureChange = refreshTimelineAfterStructureChange
Project.batchStructure = batchStructure
Project.importKeyframesFromSequence = importKeyframesFromSequence
Project.activateObjectMotorsFromSequence = activateObjectMotorsFromSequence
Project.syncObjectMotorStates = syncObjectMotorStates
Project.setProjectOpenedHook = setProjectOpenedHook
Project.openProjectFromKeyframeSequence = openProjectFromKeyframeSequence
Project.setProjectName = setProjectName

return Project
