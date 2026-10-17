--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RigPose = require("RigPose")
local RigTraversal = require("RigTraversal")
local Properties = require("Properties")
local CameraRig = require("CameraRig")
local KeyframePolicy = require("Policy")
local KeyframeStorage = require("KeyframeStorage")
local LimbIK = require("LimbIK")
local ArmatureRuntime = require("ArmatureRuntime")
local ArmatureAnimation = require("ArmatureAnimation")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local State = require("State")
local Diagnostics = require("Diagnostics")
local AnimationEvents = require("Events")
local TrackOrganization = require("Organization")
local TrackOrganizationStorage = require("TrackOrganizationStorage")
local Data = require("ProjectData")
local UI = require("UI")
local Project = require("Project")
local Notification = require("Notification")
local ArmatureImport = require("ArmatureImport")
local R6Controls = require("R6Controls")
local MasterControl = require("MasterControl")
local BoneMotor = require("BoneMotor")
local Parenting = require("Parenting")
local PoseSpace = require("PoseSpace")
local PivotSpace = require("PivotSpace")
local Defaults = require("Defaults")

local CFRAME_CHANNEL_IDS = { "loc_x", "loc_y", "loc_z", "qrot_w", "qrot_x", "qrot_y", "qrot_z" }

local SAVES_FOLDER_NAME = "EclipseAnimator_Saves"
local PROJECT_ID_ATTRIBUTE = "EclipseProjectId"

local function realPart0(motor)
	if typeof(motor) == "table" then
		return motor.RealPart0
	end

	return motor.Part0
end

local Batch = require("Batch")
local ExportResults = require("ExportResults")
local Export = {}

local populateProjectsList

local function getSavesFolder(create)
	return require("root").get(SAVES_FOLDER_NAME, create)
end

local MOON_EASE_TYPES = {
	Linear = true,
	Constant = true,
	Sine = true,
	Quad = true,
	Cubic = true,
	Quart = true,
	Quint = true,
	Sextic = true,
	Expo = true,
	Circ = true,
	Back = true,
	Elastic = true,
	Bounce = true,
}
local MOON_EASE_DIRECTIONS = { In = true, Out = true, InOut = true, OutIn = true }

local function writeEasingForPose(pose, keyData, enumsOnly)
	if not keyData then
		return
	end

	local easingStyle = keyData.EasingStyle or Defaults.EasingStyle
	local nativePose = typeof(easingStyle) == "EnumItem"
		and easingStyle.EnumType == Enum.PoseEasingStyle
	if typeof(easingStyle) == "EnumItem" then
		easingStyle = easingStyle.Name
	end

	if not easingStyle then
		return
	end

	local easingDir = keyData.EasingDirection or Defaults.EasingDirection
	if typeof(easingDir) == "EnumItem" then
		easingDir = easingDir.Name
	end

	do
		local okStyle, nativeStyle = pcall(function()
			return Enum.PoseEasingStyle[easingStyle]
		end)
		if okStyle and nativeStyle then
			pose.EasingStyle = nativeStyle
		end

		if easingDir then
			local okDir, nativeDir = pcall(function()
				return Enum.PoseEasingDirection[easingDir]
			end)
			if okDir and nativeDir then
				pose.EasingDirection = nativeDir
			end
		end
	end

	if easingStyle == "Constant" and not nativePose then
		pose.EasingDirection = Enum.PoseEasingDirection.Out
	end

	if enumsOnly or not MOON_EASE_TYPES[easingStyle] then
		return
	end

	if not MOON_EASE_DIRECTIONS[easingDir] then
		easingDir = "In"
	end

	if keyData.IsEclipseSynthetic and easingStyle == "Linear" then
		return
	end

	local easeFolder = Instance.new("Folder")
	if nativePose then
		easeFolder:SetAttribute("NativePose", true)
	end

	easeFolder.Name = "Ease"
	easeFolder.Parent = pose

	local typeVal = Instance.new("StringValue")
	typeVal.Name = "Type"
	typeVal.Value = easingStyle
	typeVal.Parent = easeFolder

	local paramsFolder = Instance.new("Folder")
	paramsFolder.Name = "Params"
	paramsFolder.Parent = easeFolder

	local function addNum(name, val)
		if val == nil then
			return
		end

		local v = Instance.new("NumberValue")
		v.Name = name
		v.Value = val
		v.Parent = paramsFolder
	end

	if easingStyle == "Bezier" then
		local bp = keyData.BezierPoints or { 0.42, 0, 0.58, 1 }
		addNum("X1", bp[1] or 0)
		addNum("Y1", bp[2] or 0)
		addNum("X2", bp[3] or 0)
		addNum("Y2", bp[4] or 0)
	end

	if easingDir then
		local d = Instance.new("StringValue")
		d.Name = "Direction"
		d.Value = easingDir
		d.Parent = paramsFolder
	end

	addNum("Overshoot", keyData.Overshoot)
	addNum("Amplitude", keyData.Amplitude)
	addNum("Period", keyData.Period)

	local handleType = keyData.HandleType
	if typeof(handleType) == "EnumItem" then
		handleType = handleType.Name
	end

	if handleType then
		local h = Instance.new("StringValue")
		h.Name = "HandleType"
		h.Value = handleType
		h.Parent = pose
	end
end

local function checkpoint()
	if State.ProjectWorkStep then
		State.ProjectWorkStep()
	end
end

local function prepareMoonTracks(tracks)
	local function difference(a, b)
		return math.max(
			(a.Position - b.Position).Magnitude,
			(a.XVector - b.XVector).Magnitude,
			(a.YVector - b.YVector).Magnitude,
			(a.ZVector - b.ZVector).Magnitude
		)
	end

	local function hidden(pose, value)
		local marker = pose:FindFirstChild("Null")
		if value then
			if not marker then
				marker = Instance.new("IntValue")
				marker.Name = "Null"
				marker.Parent = pose
			end
		elseif marker then
			marker:Destroy()
		end
	end

	for _, rows in tracks do
		checkpoint()
		table.sort(rows, function(a, b)
			return a.frame < b.frame
		end)
		local samples = {}
		local guarded = false
		for _, row in rows do
			local fraction = math.abs(row.frame - math.round(row.frame))
			if fraction < 1e-6 then
				table.insert(samples, row)
			elseif fraction < 0.0002 then
				guarded = true
			end
		end

		local authored = {}
		local compatible = true
		local supported = {
			Linear = true,
			Constant = true,
			Sine = true,
			Quad = true,
			Cubic = true,
			Quart = true,
			Quint = true,
			Sextic = true,
			Circ = true,
			Back = true,
			Bounce = true,
		}
		for _, row in rows do
			if row.authored then
				local key = row.key
				local style = key.EasingStyle or Defaults.EasingStyle
				if
					type(style) ~= "string"
					or not supported[style]
					or key.Reversed
					or key.NativePose
				then
					compatible = false
				end

				local direction = key.EasingDirection or Defaults.EasingDirection
				if
					direction ~= "In"
					and direction ~= "Out"
					and direction ~= "InOut"
					and direction ~= "OutIn"
				then
					compatible = false
				end

				table.insert(authored, row)
			end
		end

		if #authored < 2 then
			compatible = false
		end

		if compatible then
			local segment = 1
			local Easing = require("Easing")
			for _, row in rows do
				while segment < #authored - 1 and authored[segment + 1].frame < row.frame do
					segment += 1
				end

				local a, b = authored[segment], authored[segment + 1]
				local alpha = Easing.apply(
					math.clamp((row.frame - a.frame) / (b.frame - a.frame), 0, 1),
					a.key
				)
				if difference(a.pose.CFrame:Lerp(b.pose.CFrame, alpha), row.pose.CFrame) > 1e-5 then
					compatible = false
					break
				end
			end
		end

		if compatible then
			for _, row in rows do
				hidden(row.pose, not row.authored)
				if row.authored then
					local pose = row.pose
					local style, direction = pose.EasingStyle, pose.EasingDirection
					local prior = pose:FindFirstChild("Ease")
					if prior then
						prior:Destroy()
					end

					writeEasingForPose(pose, row.key, false)
					pose.EasingStyle, pose.EasingDirection = style, direction
				end
			end

			continue
		end

		if guarded or #samples < 2 then
			continue
		end

		local index = 1
		local ambiguous = false
		for _, row in rows do
			while index < #samples and samples[index + 1].frame < row.frame do
				index += 1
			end

			local a, b = samples[index], samples[index + 1]
			if
				a
				and b
				and b.frame - a.frame > 1.000001
				and row.frame > a.frame
				and row.frame < b.frame
			then
				if
					difference(
						a.pose.CFrame:Lerp(
							b.pose.CFrame,
							(row.frame - a.frame) / (b.frame - a.frame)
						),
						row.pose.CFrame
					) > 1e-5
				then
					ambiguous = true
					break
				end
			end
		end

		if ambiguous then
			continue
		end

		for _, row in rows do
			hidden(row.pose, true)
		end

		local keep = { [1] = true, [#samples] = true }
		for i, row in samples do
			if row.authored then
				keep[i] = true
			end
		end

		local boundaries = {}
		for i in keep do
			table.insert(boundaries, i)
		end

		table.sort(boundaries)
		local pending = {}
		for i = 2, #boundaries do
			table.insert(pending, { boundaries[i - 1], boundaries[i] })
		end

		while #pending > 0 do
			checkpoint()
			local range = table.remove(pending)
			local a, b = range[1], range[2]
			if b <= a + 1 then
				continue
			end

			local first, last = samples[a], samples[b]
			local worst, index = 0, nil
			for i = a + 1, b - 1 do
				if i % 256 == 0 then
					checkpoint()
				end

				local row = samples[i]
				local expected = first.pose.CFrame:Lerp(
					last.pose.CFrame,
					(row.frame - first.frame) / (last.frame - first.frame)
				)
				local error = difference(expected, row.pose.CFrame)
				if error > worst then
					worst, index = error, i
				end
			end

			if worst > 1e-5 then
				keep[index] = true
				table.insert(pending, { a, index })
				table.insert(pending, { index, b })
			end
		end

		for i in keep do
			local pose = samples[i].pose
			hidden(pose, false)

			local previous = pose:FindFirstChild("Ease")
			if previous then
				previous:Destroy()
			end

			local ease = Instance.new("Folder")
			ease.Name = "Ease"
			local kind = Instance.new("StringValue")
			kind.Name = "Type"
			kind.Value = "Linear"
			kind.Parent = ease
			local params = Instance.new("Folder")
			params.Name = "Params"
			params.Parent = ease
			ease.Parent = pose
		end
	end
end

local rawProjectSequence

local function buildKeyframeSequenceUnlayered(
	rig,
	finalName,
	includeRestPose,
	onPose,
	cameraRelative,
	denseBake,
	nativeExport
)
	if not rig then
		return nil
	end

	local timelineState = State.Timeline:GetState()
	if not timelineState or not timelineState.Keyframes then
		return nil
	end
	if nativeExport then
		assert(type(timelineState.FPS) == "number" and timelineState.FPS >= 1 and timelineState.FPS <= 120,
			"Roblox's Animation Editor supports up to 120 FPS. Set the project FPS between 1 and 120 before exporting; the Eclipse project is unchanged.")
	end

	local timelineKeyframes = KeyframePolicy.activeTracks(timelineState.Keyframes)
	local archiveTracks, archivedMotors = KeyframeStorage.plan(rig, timelineState)
	local defaultPose = timelineState.DefaultPose or {}
	local cameraOrigin, cameraViewOrigin
	local cameraMotor = cameraRelative and CameraRig.motor(rig, "CamPart") or nil
	if cameraMotor then
		cameraOrigin = State.Timeline:EvaluateMotorC0(cameraMotor, 0)
	end

	local inversePoseScale = 1 / PoseSpace.getRigScale(rig)

	local motorByPart1 = {}
	local animatedMotors = {}
	local allMotors = {}
	local hasCameraTarget = CameraRig.isRig(rig)
		and (
			rig:GetAttribute("EclipseTrackTarget") == true
			or require("Target").hasAttachment(rig, timelineKeyframes)
		)

	for _, descendant in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			descendant:GetAttribute("EclipseArmatureSkinningHelper")
			or descendant:GetAttribute("EclipseCameraAttachment")
		then
			continue
		end

		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			motorByPart1[descendant.Part1] = descendant
			table.insert(allMotors, descendant)

			local bucket = timelineKeyframes[descendant]
			local hasKeys = bucket and next(bucket) ~= nil
			local isDetached = timelineState.ParentingDefaults[descendant] == false

			if
				hasKeys
				or isDetached
				or hasCameraTarget and CameraRig.isTransform(descendant)
				or cameraMotor and (descendant == cameraMotor or CameraRig.isFov(descendant))
			then
				table.insert(animatedMotors, descendant)
			end
		elseif descendant:IsA("Bone") then
			local adapter = BoneMotor.get(descendant)
			motorByPart1[descendant] = adapter
			table.insert(allMotors, adapter)

			local bucket = timelineKeyframes[adapter]
			if
				(bucket and next(bucket) ~= nil)
				or timelineState.ParentingDefaults[adapter] == false
			then
				table.insert(animatedMotors, adapter)
			end
		end
	end

	local importedArmature = ArmatureRuntime.isRig(rig)
	if importedArmature then
		defaultPose = table.clone(defaultPose)
		for _, motor in allMotors do
			local reference = ArmatureRuntime.nativeRestC0(
				rig,
				typeof(motor) == "Instance" and motor or motor.Part1
			)
			if reference then
				defaultPose[motor] = reference
			end
		end
	end

	local hasArmatureKeys = importedArmature and ArmatureAnimation.hasKeys(rig, timelineState)
	if hasArmatureKeys then
		local present = {}
		for _, motor in animatedMotors do
			present[motor] = true
		end

		for _, motor in allMotors do
			if
				ArmatureRuntime.isDriven(motor.Part1)
				or (typeof(motor) == "Instance" and ArmatureRuntime.isDriven(motor))
			then
				if not present[motor] then
					table.insert(animatedMotors, motor)
					present[motor] = true
				end
			end
		end
	end

	local master = MasterControl.get(rig)
	local masterKeys = master and timelineKeyframes[master]
	local hasMasterKeys = masterKeys and next(masterKeys) ~= nil
	local masterRoots = {}
	if hasMasterKeys then
		local present = {}
		for _, motor in animatedMotors do
			present[motor] = true
		end

		for _, motor in allMotors do
			local parent = realPart0(motor)
			if
				parent
				and parent:IsA("BasePart")
				and parent:IsDescendantOf(rig)
				and not motorByPart1[parent]
			then
				masterRoots[motor] = parent
				if not present[motor] then
					table.insert(animatedMotors, motor)
					present[motor] = true
				end
			end
		end
	end

	const objectMotion = nativeExport
		and require("Animation").objectMotion(rig, State.Timeline, motorByPart1, allMotors)
	if objectMotion then
		const present = {}
		for _, motor in animatedMotors do
			present[motor] = true
		end

		for motor in objectMotion.roots do
			if not present[motor] then
				table.insert(animatedMotors, motor)
			end
		end
	end

	local hasIK = false
	local included = {}
	for _, motor in animatedMotors do
		included[motor] = true
	end

	for _, chain in (not importedArmature and LimbIK.getRig(rig).chains or {}) do
		local animated = false
		for _, key in timelineKeyframes[chain.owner] or {} do
			if key.IK == true then
				animated = true
				break
			end
		end

		if animated then
			hasIK = true
			for _, motor in chain.motors do
				if not included[motor] then
					included[motor] = true
					table.insert(animatedMotors, motor)
				end
			end
		end
	end

	if #allMotors == 0 then
		local sequence = rawProjectSequence(rig)
		sequence.Name = finalName
		return sequence
	end

	local restOnly = rig:IsA("Model")
		and #animatedMotors == 0
		and not next(AnimationEvents.get(rig).Events)
	if restOnly then
		if not includeRestPose then
			return nil
		end

		animatedMotors = table.clone(allMotors)
	end

	local frameSet = {}
	for frame in hasMasterKeys and masterKeys or {} do
		frameSet[frame] = true
	end

	for _, motor in ipairs(animatedMotors) do
		local bucket = timelineKeyframes[motor]
		if bucket then
			for f, data in pairs(bucket) do
				if data then
					frameSet[f] = true
				end
			end
		end
	end

	local hasAnyDetached = false
	for _, motor in ipairs(animatedMotors) do
		if timelineState.ParentingDefaults[motor] == false then
			hasAnyDetached = true
		end

		for _, key in pairs(timelineKeyframes[motor] or {}) do
			if not Parenting.keyIsParented(motor, key, timelineState.ParentingDefaults[motor]) then
				hasAnyDetached = true
			end
		end
	end

	local anyPartialChannels = false
	local hasGraphCurve = false
	for _, motor in animatedMotors do
		for _, key in timelineKeyframes[motor] or {} do
			if key.BlenderCurve or next(key.GraphCurves or {}) then
				hasGraphCurve = true
				break
			end
		end

		if hasGraphCurve then
			break
		end
	end

	for _, motor in ipairs(animatedMotors) do
		local bucket = timelineKeyframes[motor]
		if bucket then
			for _, kd in pairs(bucket) do
				if kd.Channels then
					for _, id in ipairs(CFRAME_CHANNEL_IDS) do
						local ch = kd.Channels[id]
						if not ch or ch.Value == nil then
							anyPartialChannels = true
							break
						end
					end
				end

				if anyPartialChannels then
					break
				end
			end
		end

		if anyPartialChannels then
			break
		end
	end

	local channelOverrides = false
	for _, motor in animatedMotors do
		const bucket = timelineKeyframes[motor]
		if
			motor:GetAttribute("EclipseChannelDisabledAny")
			or bucket and require("GraphCurves").hasChannelEasing(bucket)
		then
			channelOverrides = true
			break
		end
	end

	local hasCustomCurve = false
	for _, motor in ipairs(animatedMotors) do
		local ordered = {}
		for _, key in pairs(timelineKeyframes[motor] or {}) do
			table.insert(ordered, key)
		end

		table.sort(ordered, function(a, b)
			return a.Time < b.Time
		end)
		for index, key in ordered do
			local style = key.EasingStyle or Defaults.EasingStyle
			local name = typeof(style) == "EnumItem" and style.Name or style
			if name ~= "Linear" and name ~= "Constant" then
				hasCustomCurve = true
				break
			end

			if name == "Linear" and key.C0 then
				for later = index + 1, #ordered do
					local other = ordered[later]
					if other.C0 and other.Time > key.Time then
						local _, angle = key.C0:ToObjectSpace(other.C0):ToAxisAngle()
						if math.abs(angle) > 0.1 then
							hasCustomCurve = true
						end

						break
					end
				end
			end

			if hasCustomCurve then
				break
			end
		end

		if hasCustomCurve then
			break
		end
	end

	local hasHeadStabilizer = false
	for _, motor in animatedMotors do
		for _, key in timelineKeyframes[motor] or {} do
			if key.HS then
				hasHeadStabilizer = true
				break
			end
		end

		if hasHeadStabilizer then
			break
		end
	end

	local hasPivot = false
	for _, motor in animatedMotors do
		if PivotSpace.get(motor) then
			hasPivot = true
			break
		end
	end

	local hasModifiers = require("Mods").hasFor(animatedMotors)
	local frameSkip = (timelineState.SkipFrames or 0) > 0
	local needsBake = frameSkip
		or nativeExport
		or denseBake
		or cameraMotor ~= nil
		or hasModifiers
		or hasCameraTarget
		or hasMasterKeys
		or hasArmatureKeys
		or hasHeadStabilizer
		or hasIK
		or hasAnyDetached
		or anyPartialChannels
		or channelOverrides
		or hasCustomCurve
		or hasGraphCurve
		or hasPivot
	if needsBake and not denseBake then
		archiveTracks, archivedMotors = KeyframeStorage.plan(rig, timelineState, true)
	end

	local maxUserFrame = hasArmatureKeys and ArmatureAnimation.maxFrame(rig, timelineState) or 0
	for _, motor in ipairs(animatedMotors) do
		local bucket = timelineKeyframes[motor]
		if bucket then
			for f in pairs(bucket) do
				if f > maxUserFrame then
					maxUserFrame = f
				end
			end
		end
	end

	for frame in hasMasterKeys and masterKeys or {} do
		maxUserFrame = math.max(maxUserFrame, frame)
	end

	if objectMotion then
		maxUserFrame = math.max(maxUserFrame, objectMotion.lastFrame)
	end

	local externalMotion = hasCameraTarget or hasModifiers
	for _, motor in animatedMotors do
		for _, key in timelineKeyframes[motor] or {} do
			if key.CamTargetParent then
				externalMotion = true
				break
			end
		end
	end

	if externalMotion then
		maxUserFrame = math.max(maxUserFrame, State.Timeline:GetLastKeyframeFrame() or 0)
		for _, clip in require("Cache").list(timelineState) do
			maxUserFrame = math.max(maxUserFrame, clip.last)
		end
	end

	if hasModifiers then
		maxUserFrame =
			math.max(maxUserFrame, State.Timeline:TimeToFrame(State.Timeline:GetPlaybackEndTime()))
	end

	frameSet[maxUserFrame] = true
	local moonTracks = {}
	local motorSampleC0 = {}
	local detachedSampleWorld = {}

	if needsBake then
		local subdivisions = nativeExport and math.max(1, math.floor(120 / timelineState.FPS))
			or math.max(2, math.ceil(120 / timelineState.FPS))
		for tick = 0, maxUserFrame * subdivisions do
			frameSet[tick / subdivisions] = true
		end

		local function guard(frame, before)
			if nativeExport then return end
			local guardFrame = frame + (before and -0.0001 or 0.0001)
			if guardFrame >= 0 and guardFrame <= maxUserFrame then
				frameSet[guardFrame] = true
			end
		end

		local function guardConstant(frame, nextFrame, key)
			if not nextFrame then
				return
			end

			local style = key.EasingStyle or Defaults.EasingStyle
			local name = typeof(style) == "EnumItem" and style.Name or style
			if name ~= "Constant" then
				return
			end

			local nativePose = key.NativePose == true
				or typeof(style) == "EnumItem" and style.EnumType == Enum.PoseEasingStyle
			local direction = key.EasingDirection
			if typeof(direction) == "EnumItem" then
				direction = direction.Name
			end

			if nativePose and direction == "In" then
				guard(frame, false)
			elseif nativePose and direction == "InOut" then
				local midpoint = (frame + nextFrame) * 0.5
				frameSet[midpoint] = true
				guard(midpoint, true)
			else
				guard(nextFrame, true)
			end
		end

		local samplingTracks = table.clone(animatedMotors)
		local attachment = CameraRig.isRig(rig) and CameraRig.motor(rig, "AttachToPart")
		if attachment then
			table.insert(samplingTracks, attachment)
		end

		if hasArmatureKeys then
			local seen = {}
			for _, motor in samplingTracks do
				seen[motor] = true
			end

			for _, motor in ArmatureRuntime.collectMotors(rig) do
				if not seen[motor] and timelineKeyframes[motor] then
					table.insert(samplingTracks, motor)
					seen[motor] = true
				end
			end

			for _, track in ArmatureAnimation.propertyView(rig).tracks do
				local previous = track.default
				for _, key in track.keys do
					frameSet[key.frame] = true
					if
						previous ~= key.value
						and (typeof(previous) ~= "number" or typeof(key.value) ~= "number")
					then
						guard(key.frame, true)
					end

					previous = key.value
				end
			end
		end

		for _, motor in ipairs(samplingTracks) do
			local bucket = timelineKeyframes[motor]
			require("Mods").bakeBoundaries(motor, bucket, maxUserFrame, function(f)
				frameSet[f] = true
			end)
			for frame in bucket or {} do
				frameSet[frame] = true
			end

			local frames, nextFrameByKey, nextByChannel, nextByLegacyChannel = {}, {}, {}, {}
			for frame in bucket or {} do
				table.insert(frames, frame)
			end

			table.sort(frames)
			local channels, legacyChannels = {}, {}
			for i = #frames, 1, -1 do
				local frame = frames[i]
				nextFrameByKey[frame] = frames[i + 1]
				nextByChannel[frame] = {}
				nextByLegacyChannel[frame] = {}
				for id in bucket[frame].GraphCurves or {} do
					nextByChannel[frame][id] = channels[id]
					channels[id] = frame
				end

				for id, channel in bucket[frame].Channels or {} do
					if channel.Value ~= nil then
						nextByLegacyChannel[frame][id] = legacyChannels[id]
						legacyChannels[id] = frame
					end
				end
			end

			local hsFrames = {}
			for frame, key in bucket or {} do
				if typeof(key.HS) == "boolean" then
					table.insert(hsFrames, frame)
				end
			end

			table.sort(hsFrames)
			local previousHS = false
			for _, frame in hsFrames do
				local enabled = bucket[frame].HS
				if enabled ~= previousHS then
					guard(frame, true)
					previousHS = enabled
				end
			end

			for frame, key in pairs(bucket or {}) do
				for id, point in pairs(key.GraphCurves or {}) do
					if point.Interpolation == "ConstantNext" then
						guard(frame, false)
					elseif point.Interpolation == "Constant" then
						local following = nextByChannel[frame][id]
						if following then
							guard(following, true)
						end
					end
				end
			end

			for frame, key in pairs(bucket or {}) do
				guardConstant(frame, nextFrameByKey[frame], key)

				for _, nextFrame in nextByLegacyChannel[frame] do
					guardConstant(frame, nextFrame, key)
				end
			end
		end

		if nativeExport then
			table.clear(frameSet)
			const spacing = require("Animation")
			const perFrame, stride = spacing.nativeSampleSpacing(timelineState.FPS)
			local ticks = math.floor(maxUserFrame * perFrame / stride + 1e-6)
			for tick = 0, ticks do frameSet[tick * stride / perFrame] = true end
			local last = ticks * stride / perFrame
			if maxUserFrame - last > 1e-6 then
				if last > 0 and (maxUserFrame - last) / timelineState.FPS < spacing.MIN_KEY_GAP then
					frameSet[last] = nil
				end
				frameSet[maxUserFrame] = true
			end
		end

		local sampleFrames = {}
		for frame in pairs(frameSet) do
			table.insert(sampleFrames, frame)
		end

		table.sort(sampleFrames)
		local savedPose = RigPose.capture(rig)
		local savedObserved = table.clone(State.lastCFrames)
		local armatureSnapshot = importedArmature and ArmatureRuntime.snapshot(rig)
		local masterC0 = master and master.C0
		local savedC0, savedParenting, savedSize = {}, {}, {}
		for _, m in ipairs(allMotors) do
			savedC0[m] = m.C0
			savedParenting[m] = m:GetAttribute("TrackParent")
			if m.Part1 and m.Part1:IsA("BasePart") then
				savedSize[m.Part1] = m.Part1.Size
			end
		end

		local direct = CameraRig.isRig(rig)
			and not cameraMotor
			and not (
				hasModifiers
				or hasCameraTarget
				or hasMasterKeys
				or importedArmature
				or hasHeadStabilizer
				or hasIK
				or hasAnyDetached
			)
		local loopEnd = State.Timeline:IsLooping() and State.Timeline:GetPlaybackEndTime() or nil
		local ok, err = xpcall(function()
			ArmatureRuntime.withSampling(rig, function()
				for _, frame in ipairs(sampleFrames) do
					checkpoint()
					local time = State.Timeline:GetPoseTime(State.Timeline:FrameToTime(frame))
					if not direct then
						State.Timeline:ApplyPoseAtTime(
							rig,
							time,
							{ OnlyRig = true, SkipControls = true }
						)
					end

					local cameraView, cameraFov
					if cameraMotor then
						cameraView, cameraFov = CameraRig.renderFrame(rig, nil, false, time)
					end

					for _, motor in ipairs(animatedMotors) do
						if R6Controls.isControl(motor.Part1) then
							continue
						end

						motorSampleC0[motor] = motorSampleC0[motor] or {}
						local evaluated = direct
								and State.Timeline:EvaluateMotorC0(
									motor,
									time,
									timelineKeyframes[motor],
									loopEnd
								)
							or motor.C0
						motorSampleC0[motor][frame] = direct and evaluated
							or masterRoots[motor] and MasterControl.exportRootDelta(
								rig,
								masterRoots[motor]
							) * motor.C0
							or motor.C0
						if not direct and objectMotion and objectMotion.roots[motor] then
							motorSampleC0[motor][frame] = objectMotion.delta(objectMotion.roots[motor], time)
								* motorSampleC0[motor][frame]
						end

						if cameraMotor and motor == cameraMotor then
							motorSampleC0[motor][frame] = cameraView
							if frame == 0 then
								cameraViewOrigin = cameraView
							end
						elseif cameraMotor and CameraRig.isFov(motor) then
							motorSampleC0[motor][frame] =
								CFrame.new(0, cameraFov - CameraRig.DEFAULT_FOV, 0)
						elseif hasCameraTarget and CameraRig.isTransform(motor) then
							local base = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
							local tracked = require("Target").frame(rig, base, time)
							motorSampleC0[motor][frame] = motor.Part0.CFrame:Inverse()
								* tracked
								* motor.C1
							if frame == 0 and cameraRelative then
								cameraOrigin = motorSampleC0[motor][frame]
							end
						end

						if
							not direct
							and motor:GetAttribute("TrackParent") == false
							and motor.Part0
							and motor.Part1
						then
							detachedSampleWorld[motor] = detachedSampleWorld[motor] or {}
							detachedSampleWorld[motor][frame] =
								Parenting.worldOf(motor, motorByPart1)
						end
					end
				end
			end)
		end, debug.traceback)
		if not direct then
			for m, c0 in pairs(savedC0) do
				m.C0 = c0
				m:SetAttribute("TrackParent", savedParenting[m])
			end

			if masterC0 then
				master.C0 = masterC0
			end

			for part, size in pairs(savedSize) do
				part.Size = size
			end

			LimbIK.clearLive()
			if armatureSnapshot then
				ArmatureRuntime.restore(rig, armatureSnapshot)
				ArmatureRuntime.evaluate(rig, true)
			end
		end

		RigPose.restore(rig, savedPose)

		local function sampled(motor)
			return require("Layers").owner(motor) == rig
		end

		for motor in State.lastCFrames do
			if sampled(motor) then
				State.lastCFrames[motor] = savedObserved[motor]
			end
		end

		for motor, value in savedObserved do
			if sampled(motor) then
				State.lastCFrames[motor] = value
			end
		end

		if not ok then
			error(err)
		end

		for motor, samples in motorSampleC0 do
			local previous
			for index, frame in sampleFrames do
				local current = samples[frame]
				local following = sampleFrames[index + 1]
				local authored = timelineKeyframes[motor] and timelineKeyframes[motor][frame]
				local world = detachedSampleWorld[motor]
				if
					not denseBake
					and current
					and previous == current
					and following
					and samples[following] == current
					and not authored
					and (
						not world
						or world[frame] == world[sampleFrames[index - 1]]
							and world[frame] == world[following]
					)
				then
					samples[frame] = nil
				end

				previous = current
			end

			checkpoint()
		end
	end

	frameSet[0] = true
	if restOnly then
		const restFrame = if nativeExport
			then select(2, require("Animation").nativeSampleSpacing(timelineState.FPS))
			else 1
		frameSet[math.max(restFrame, maxUserFrame)] = true
	end

	local sortedFrames = {}
	for f in pairs(frameSet) do
		table.insert(sortedFrames, f)
	end

	table.sort(sortedFrames)

	if #sortedFrames == 0 then
		return nil
	end

	local keyframeSequence = Instance.new("KeyframeSequence")
	PoseSpace.markCanonical(keyframeSequence, rig)
	keyframeSequence:SetAttribute("EclipseBuild", Diagnostics.build())
	keyframeSequence:SetAttribute("EclipseParentingVersion", 1)
	keyframeSequence:SetAttribute("EclipseBaked", needsBake)
	keyframeSequence.Name = finalName or Project.getProjectExportName()
	if cameraOrigin then
		keyframeSequence:SetAttribute("EclipseCameraRelative", true)
		keyframeSequence:SetAttribute("EclipseCameraOrigin", cameraOrigin)
		keyframeSequence:SetAttribute("EclipseCameraViewpoint", true)
		keyframeSequence:SetAttribute("EclipseCameraRoot", cameraViewOrigin)
		keyframeSequence:SetAttribute("EclipseCameraDefaultFOV", CameraRig.DEFAULT_FOV)
	end

	keyframeSequence.Loop = State.Timeline:IsLooping()
	State.Timeline:WriteProjectSettings(keyframeSequence)

	for _, frameNumber in ipairs(sortedFrames) do
		if denseBake and math.abs(frameNumber - math.round(frameNumber)) > 1e-6 then
			continue
		end

		checkpoint()
		local keyframe = Instance.new("Keyframe")
		keyframe.Name = "Keyframe"
		keyframe.Time = State.Timeline:FrameToTime(frameNumber)
		keyframe:SetAttribute("EclipseExactFrame", frameNumber)

		local motorsAtFrame = {}
		for _, motor in ipairs(animatedMotors) do
			local bucket = timelineKeyframes[motor]
			local userKey = bucket and bucket[frameNumber]
			local isDetached =
				not State.Timeline:IsParentedAtTime(motor, State.Timeline:FrameToTime(frameNumber))
			local sampleC0 = motorSampleC0[motor] and motorSampleC0[motor][frameNumber]
			local sampleWorld = detachedSampleWorld[motor]
				and detachedSampleWorld[motor][frameNumber]
			if userKey then
				if sampleC0 then
					local bakedKey = {}
					for k, v in pairs(userKey) do
						bakedKey[k] = v
					end

					bakedKey.IKAnchor = LimbIK.keyAnchor(userKey)
					bakedKey.IKRigWorld = userKey.IKRigWorld
					bakedKey.EditorC0 = userKey.C0
					bakedKey.C0 = sampleC0
					if isDetached and sampleWorld then
						bakedKey.WorldCFrame = sampleWorld
					end

					motorsAtFrame[motor] = bakedKey
				else
					motorsAtFrame[motor] = userKey
				end
			elseif sampleC0 then
				motorsAtFrame[motor] = {
					C0 = sampleC0,
					WorldCFrame = sampleWorld,
					Parented = not isDetached,
					EasingStyle = "Linear",
					EasingDirection = "In",
					IsEclipseSynthetic = true,
				}
			elseif frameNumber == maxUserFrame and bucket then
				motorsAtFrame[motor] = {
					C0 = State.Timeline:EvaluateMotorC0(
						motor,
						State.Timeline:FrameToTime(frameNumber),
						bucket
					),
					EasingStyle = "Linear",
					EasingDirection = "In",
					IsEclipseSynthetic = true,
				}
			elseif restOnly then
				motorsAtFrame[motor] = {
					C0 = defaultPose[motor] or motor.C0,
					EasingStyle = "Linear",
					EasingDirection = "In",
					IsEclipseSynthetic = true,
				}
			elseif frameNumber == 0 and bucket then
				local firstFrame = nil
				local firstKey = nil
				for f, kd in pairs(bucket) do
					if kd and (not firstFrame or f < firstFrame) then
						firstFrame = f
						firstKey = kd
					end
				end

				if firstKey and firstFrame ~= 0 and firstKey.C0 then
					motorsAtFrame[motor] = {
						C0 = firstKey.C0,
						EasingStyle = "Linear",
						EasingDirection = "In",
						IsEclipseSynthetic = true,
					}
				end
			end
		end

		local poseMap = {}
		local rootAnchorPoses = {}

		local function ensureRootAnchorPose(rigRootPart)
			if not rigRootPart then
				return nil
			end

			if rootAnchorPoses[rigRootPart] then
				return rootAnchorPoses[rigRootPart]
			end

			local rootAnchorPose = Instance.new("Pose")
			rootAnchorPoses[rigRootPart] = rootAnchorPose
			rootAnchorPose.Name = rigRootPart.Name
			rootAnchorPose.Weight = 0
			rootAnchorPose.CFrame = CFrame.new()
			rootAnchorPose.Parent = keyframe
			local nullVal = Instance.new("IntValue")
			nullVal.Name = "Null"
			nullVal.Parent = rootAnchorPose
			return rootAnchorPose
		end

		local ensureParentPlaceholderPose

		local function attachToParent(pose, motor)
			local parentMotor = R6Controls.isControl(motor.Part1) and motor.Owner
				or motorByPart1[realPart0(motor)]
			local parentPose
			if parentMotor then
				parentPose = ensureParentPlaceholderPose(parentMotor)
			else
				parentPose = ensureRootAnchorPose(realPart0(motor))
			end

			pose.Parent = parentPose or keyframe
		end

		ensureParentPlaceholderPose = function(motor)
			if poseMap[motor] then
				return poseMap[motor]
			end

			local pose = Instance.new("Pose")
			pose.Name = motor.Part1.Name
			pose.CFrame = CFrame.new()
			pose.Weight = 0
			local nullVal = Instance.new("IntValue")
			nullVal.Name = "Null"
			nullVal.Parent = pose

			attachToParent(pose, motor)
			poseMap[motor] = pose
			return pose
		end

		local function ensureLeafPose(motor, keyData)
			local pose = poseMap[motor]
			if pose then
				local nullChild = pose:FindFirstChild("Null")
				if nullChild then
					nullChild:Destroy()
				end
			else
				pose = Instance.new("Pose")
				pose.Name = motor.Part1.Name
				attachToParent(pose, motor)
				poseMap[motor] = pose
			end

			local defaultC0 = defaultPose[motor] or motor.C0
			local localC0 = keyData.C0 or defaultC0
			if onPose then
				onPose(motor, keyData, frameNumber, localC0, needsBake)
			end

			if motor == cameraMotor then
				pose.CFrame = cameraViewOrigin:ToObjectSpace(localC0):Orthonormalize()
			elseif cameraMotor and CameraRig.isFov(motor) then
				pose.CFrame = localC0
			else
				pose.CFrame =
					PoseSpace.scaleTranslation(defaultC0:ToObjectSpace(localC0), inversePoseScale)
						:Orthonormalize()
			end

			pose.Weight = 1
			if R6Controls.isControl(motor.Part1) then
				pose.Weight = 0
				pose:SetAttribute("EclipseR6Control", motor:GetAttribute("EclipseR6Control"))
				pose:SetAttribute("EclipseR6Owner", motor.Owner.Part1.Name)
				pose:SetAttribute("EclipseR6Rest", defaultC0)
				for attr, value in motor:GetAttributes() do
					if attr == "EclipseDisabled" or attr:sub(1, 22) == "EclipseChannelDisabled" then
						pose:SetAttribute(attr, value)
					end
				end
			end

			local archivedPose = archivedMotors[motor] == true
			if needsBake and archivedPose and pose.Weight > 0 then
				moonTracks[motor] = moonTracks[motor] or {}
				table.insert(moonTracks[motor], {
					frame = frameNumber,
					pose = pose,
					authored = not keyData.IsEclipseSynthetic,
					key = keyData,
				})
			end

			writeEasingForPose(pose, keyData, archivedPose)
			if needsBake then
				pose.EasingStyle = frameSkip and Enum.PoseEasingStyle.Constant
					or Enum.PoseEasingStyle.Linear
				pose.EasingDirection = Enum.PoseEasingDirection.In
			end

			if not (archivedPose and keyData.IsEclipseSynthetic) then
				pose:SetAttribute(
					"EclipseParented",
					Parenting.keyIsParented(motor, keyData, timelineState.ParentingDefaults[motor])
				)
				pose:SetAttribute("EclipsePivot", PivotSpace.get(motor))
				pose:SetAttribute("EclipseHS", keyData.HS)
				pose:SetAttribute("EclipseHSRestoreParented", keyData.HSRestoreParented)
				pose:SetAttribute("EclipseHSRotation", keyData.HSRotation)
				pose:SetAttribute("EclipseHSLocalRotation", keyData.HSLocalRotation)
				pose:SetAttribute("EclipseIK", keyData.IK)
				pose:SetAttribute("EclipseIKTarget", keyData.IKTarget)
				pose:SetAttribute("EclipseIKPole", keyData.IKPole)
				pose:SetAttribute("EclipseIKBaseC0", keyData.IKBaseC0)
				pose:SetAttribute("EclipseIKBaseWorld", keyData.IKBaseWorld)
				pose:SetAttribute("EclipseIKAnchor", LimbIK.keyAnchor(keyData))
				pose:SetAttribute("EclipseIKRigWorld", keyData.IKRigWorld)
				pose:SetAttribute("EclipseIKRoot", keyData.IKRoot)
				pose:SetAttribute("EclipseIKPoleFollowsTarget", keyData.IKPoleFollowsTarget)
				pose:SetAttribute("EclipseIKRestoreParented", keyData.IKRestoreParented)
				if not keyData.IsEclipseSynthetic then
					pose:SetAttribute(
						"EclipseLocalPose",
						PoseSpace.scaleTranslation(
							defaultC0:ToObjectSpace(keyData.EditorC0 or localC0),
							inversePoseScale
						)
					)
				end
			end

			if keyData.IsEclipseSynthetic and not archivedPose then
				local marker = Instance.new("IntValue")
				marker.Name = "EclipseSynthetic"
				marker.Parent = pose

				local nullVal = Instance.new("IntValue")
				nullVal.Name = "Null"
				nullVal.Parent = pose
			end

			if not keyData.IsEclipseSynthetic and not archivedPose and keyData.GraphCurves then
				local graph = Instance.new("StringValue")
				graph.Name = "EclipseGraphCurves"
				graph.Value = HttpService:JSONEncode(keyData.GraphCurves)
				graph.Parent = pose
				pose:SetAttribute("EclipseGraphOnly", keyData.GraphOnly == true)
			end

			if not keyData.IsEclipseSynthetic and not archivedPose and keyData.Channels then
				local channelCount = 0
				for _ in pairs(keyData.Channels) do
					channelCount += 1
				end

				if channelCount > 0 and channelCount < 10 then
					local idsList = {}
					for chId in pairs(keyData.Channels) do
						table.insert(idsList, chId)
					end

					local idsVal = Instance.new("StringValue")
					idsVal.Name = "EclipseChannels"
					idsVal.Value = table.concat(idsList, ",")
					idsVal.Parent = pose

					local valuesFolder = Instance.new("Folder")
					valuesFolder.Name = "EclipseChannelValues"
					for chId, ch in pairs(keyData.Channels) do
						local v = Instance.new("NumberValue")
						v.Name = chId
						v.Value = ch.Value
						v.Parent = valuesFolder
					end

					valuesFolder.Parent = pose
				end
			end

			if
				not Parenting.keyIsParented(motor, keyData, timelineState.ParentingDefaults[motor])
			then
				local world = keyData.WorldCFrame
				if not world and motor.Part0 then
					world = motor.Part0.CFrame * localC0 * motor.C1:Inverse()
				end

				if world then
					local worldVal = Instance.new("CFrameValue")
					worldVal.Name = "DetachedWorldCFrame"
					worldVal.Value = world
					worldVal.Parent = pose
				end
			end

			if not keyData.IsEclipseSynthetic and not archivedPose then
				if keyData.PathTangentOut then
					local v = Instance.new("Vector3Value")
					v.Name = "EclipsePathTangentOut"
					v.Value = keyData.PathTangentOut
					v.Parent = pose
				end

				if keyData.PathTangentIn then
					local v = Instance.new("Vector3Value")
					v.Name = "EclipsePathTangentIn"
					v.Value = keyData.PathTangentIn
					v.Parent = pose
				end
			end
		end

		for motor, keyData in pairs(motorsAtFrame) do
			ensureLeafPose(motor, keyData)
		end

		if
			next(motorsAtFrame)
			or frameNumber == 0
			or frameNumber == sortedFrames[#sortedFrames]
		then
			keyframe.Parent = keyframeSequence
		else
			keyframe:Destroy()
		end
	end

	if denseBake then
		for _, object in keyframeSequence:GetDescendants() do
			if object:IsA("Pose") and object.Weight > 0 then
				local null = object:FindFirstChild("Null")
				if null then
					null:Destroy()
				end

				local ease = object:FindFirstChild("Ease")
				if ease then
					ease:Destroy()
				end

				writeEasingForPose(
					object,
					{ EasingStyle = frameSkip and "Constant" or "Linear", EasingDirection = "In" }
				)
			end
		end
	else
		if not frameSkip then
			prepareMoonTracks(moonTracks)
		end
	end

	if hasCameraTarget and require("Target").hasAttachment(rig, timelineKeyframes) then
		local target = require("Target")
		local samples = keyframeSequence:GetKeyframes()
		table.sort(samples, function(a, b)
			return a.Time < b.Time
		end)
		for index, keyframe in samples do
			local following = samples[index + 1]
			if
				following
				and target.attachmentObject(
						rig,
						keyframe:GetAttribute("EclipseExactFrame") / timelineState.FPS
					)
					~= target.attachmentObject(
						rig,
						following:GetAttribute("EclipseExactFrame") / timelineState.FPS
					)
			then
				local pose = keyframe:FindFirstChild("CamPart", true)
				if pose and pose:IsA("Pose") then
					pose.EasingStyle = Enum.PoseEasingStyle.Constant
					local ease = pose:FindFirstChild("Ease")
					if ease then
						ease:Destroy()
					end

					writeEasingForPose(pose, { EasingStyle = "Constant", EasingDirection = "In" })
				end
			end
		end
	end

	local defaultsFolder = Instance.new("Folder")
	defaultsFolder.Name = "EclipseParentingDefaults"
	for _, motor in ipairs(allMotors) do
		local ref = Instance.new("ObjectValue")
		ref.Name = motor.Part1.Name
		ref.Value = motor.Part1
		ref:SetAttribute(
			"Parented",
			Parenting.keyIsParented(motor, nil, timelineState.ParentingDefaults[motor])
		)
		ref.Parent = defaultsFolder
	end

	defaultsFolder.Parent = keyframeSequence

	AnimationEvents.export(rig, keyframeSequence, timelineState.FPS)
	AnimationEvents.writeSubtitles(keyframeSequence)
	TrackOrganization.writeForRig(keyframeSequence, rig)
	if importedArmature then
		ArmatureAnimation.write(keyframeSequence, rig, timelineState)
	end

	MasterControl.write(keyframeSequence, rig)
	Properties.write(keyframeSequence, rig, timelineState)
	KeyframeStorage.write(keyframeSequence, rig, timelineState, nil, archiveTracks)
	keyframeSequence:SetAttribute("EclipseMoonEasingVersion", 1)
	PivotSpace.write(keyframeSequence, rig)
	return keyframeSequence
end

local function buildKeyframeSequenceForRig(
	rig,
	finalName,
	includeRestPose,
	onPose,
	cameraRelative,
	denseBake,
	nativeExport
)
	local Layers = require("Layers")
	local Storage = require("layerStorage")
	local archive = Storage.capture(rig, State.Timeline:GetState())
	local sequence = Layers.withBaked(State.Timeline, function()
		return require("cache").withFrozen(function()
			return buildKeyframeSequenceUnlayered(
				rig,
				finalName,
				includeRestPose,
				onPose,
				cameraRelative,
				denseBake,
				nativeExport
			)
		end)
	end, rig)
	if sequence and archive then
		Storage.write(sequence, rig, State.Timeline:GetState(), archive)
		KeyframeStorage.writePhysics(sequence, rig, State.Timeline:GetState())
	end

	return sequence
end

local function writeCameraFov(rig, sequence, includeSampler)
	local ok, err = pcall(function()
		local writer = require("writer")
		writer.write(rig, sequence, CameraRig.default(rig), includeSampler)
		local original = require("rig").original(rig)
		if original and original ~= rig and original:IsDescendantOf(workspace) then
			writer.write(original, sequence, CameraRig.default(rig), includeSampler)
		end
	end)
	if not ok then
		warn("Camera animation saved, but FovPart.FieldOfView export failed: " .. tostring(err))
		Notification.show(
			"FOV EXPORT NEEDS ATTENTION",
			"Camera animation saved. See Output for the FOV export error."
		)
	end
end

local function validateNativePoseNames(rig)
	local siblings = {}
	for _, motor in Parenting.collectMotors(rig) do
		local part, parent = motor.Part1, Parenting.realPart0(motor)
		if typeof(part) ~= "Instance" or not (part:IsA("BasePart") or part:IsA("Bone"))
			or R6Controls.isControl(part) or typeof(parent) ~= "Instance" then
			continue
		end
		local names = siblings[parent]
		if not names then names = {} siblings[parent] = names end
		assert(not names[part.Name] or names[part.Name] == part,
			string.format('Native animation has two "%s" parts under joint parent "%s". Give these parts unique names before exporting; the Eclipse project is unchanged.', part.Name, parent.Name))
		names[part.Name] = part
	end
end

local function animationSaveName(previous, animSaves, requested)
	if not previous then
		return if Data.isDefaultAnimationName(requested)
			then Data.getNextDefaultExportName(animSaves)
			else Data.getUniqueExportName(animSaves, requested)
	end

	const rename = State.animationRename
	if
		rename
		and rename.name == requested
		and not rename.applied[previous]
		and requested ~= Data.sanitizeExportName(previous.Name)
	then
		return Data.getUniqueExportName(animSaves, requested)
	end

	return previous.Name
end

local function markRenameApplied(sequence)
	const rename = State.animationRename
	if rename and sequence then
		rename.applied[sequence] = true
	end
end

function Export.requestRename(name)
	if type(name) ~= "string" or not name:match("%S") then
		return
	end

	State.animationRename = {
		name = Data.sanitizeExportName(name),
		applied = setmetatable({}, { __mode = "k" }),
	}
end

local function exportAnimationForRig(rig)
	assert(rig and rig.Parent, "The rig is no longer in the place.")
	validateNativePoseNames(rig)
	local animSaves = Data.ensureAnimSaves(rig)
	assert(animSaves, "Could not create this rig's AnimSaves folder.")

	local exportProjectId = State.currentProjectSave
		and State.currentProjectSave:GetAttribute(PROJECT_ID_ATTRIBUTE)
	local previous = State.exportSequences[rig]
	if previous and exportProjectId then
		local owner = previous:GetAttribute("EclipseExportProjectId")
			or previous:GetAttribute(PROJECT_ID_ATTRIBUTE)
		if owner and owner ~= exportProjectId then
			previous = nil
		end
	end

	if not previous or previous.Parent ~= animSaves then
		local source = previous or (rig == State.currentRig and State.currentProjectSequence)
		local id = exportProjectId or (source and source:GetAttribute(PROJECT_ID_ATTRIBUTE))
		previous = nil
		if source and source:IsA("KeyframeSequence") and source.Parent == animSaves then
			local owner = source:GetAttribute("EclipseExportProjectId")
				or source:GetAttribute(PROJECT_ID_ATTRIBUTE)
			if not exportProjectId or not owner or owner == exportProjectId then
				previous = source
			end
		end

		if not previous and id then
			for _, saved in animSaves:GetChildren() do
				if
					saved:IsA("KeyframeSequence")
					and (
						saved:GetAttribute("EclipseExportProjectId") == id
						or saved:GetAttribute(PROJECT_ID_ATTRIBUTE) == id
					)
				then
					previous = saved
					break
				end
			end
		end
	end

	local finalName = animationSaveName(previous, animSaves, Project.getProjectExportName())
	local keyframeSequence =
		buildKeyframeSequenceForRig(rig, finalName, true, nil, CameraRig.isRig(rig), nil, not CameraRig.isRig(rig))
	assert(keyframeSequence, "No timeline data is available for this rig.")
	keyframeSequence:SetAttribute("EclipseHadArmature", ArmatureImport.find(rig) ~= nil)

	keyframeSequence:SetAttribute("EclipseExportProjectId", exportProjectId)
	local isCamera = CameraRig.isRig(rig)
	if not isCamera then
		require("Animation").enforceKeySpacing(keyframeSequence)
	end

	local nativeSequence = keyframeSequence
	if isCamera then
		local ok, value = pcall(
			CameraRig.nativeCopy,
			keyframeSequence,
			rig,
			State.Timeline:GetState().DefaultPose,
			checkpoint
		)
		if not ok then
			keyframeSequence:Destroy()
			error(value, 0)
		end

		nativeSequence = value
	end

	local committed = Batch.commit(previous, nativeSequence, animSaves)
	local sequence = if isCamera then keyframeSequence else committed
	committed.Name = finalName
	committed:SetAttribute(
		"EclipseExportNotice",
		not isCamera and require("Animation").exportNotice(rig, State.Timeline) or nil
	)
	State.exportSequences[rig] = committed
	markRenameApplied(committed)
	if isCamera then
		writeCameraFov(rig, committed)
		local original = require("rig").original(rig)
		local id = original:GetAttribute("EclipseTrackId") or rig:GetAttribute("EclipseTrackId")
		if not id then
			id = game:GetService("HttpService"):GenerateGUID(false)
		end

		original:SetAttribute("EclipseTrackId", id)
		CameraRig.organize(rig, Project.getProjectExportName())
		local copiedRig
		local ownerId = id
		local copies = require("root").get("EclipseCameraExports", true)
		local candidates = copies:GetChildren()
		for _, candidate in workspace:GetDescendants() do
			table.insert(candidates, candidate)
		end

		local editing = {}
		for _, activeRig in State.getAllRigs() do
			editing[activeRig] = true
		end

		for _, target in candidates do
			local link = target:FindFirstChild("EclipseCameraSource")
			if
				not editing[target]
				and target:IsA("Model")
				and target:GetAttribute("EclipseCameraTransferRig")
				and (
					target:GetAttribute("EclipseCameraExportOwner") == ownerId
					or link
						and link:IsA("ObjectValue")
						and (link.Value == rig or link.Value == original)
				)
			then
				local saves = target:FindFirstChild("AnimSaves")
				if saves then
					local reference = target:FindFirstChild("EclipseCameraSequence")
					local previous = reference and reference:IsA("ObjectValue") and reference.Value
						or saves:FindFirstChild(sequence.Name)
					local copied = Batch.commit(
						previous and previous:IsA("KeyframeSequence") and previous or nil,
						sequence:Clone(),
						saves
					)
					copied.Name = sequence.Name
					if reference and reference:IsA("ObjectValue") then
						reference.Value = copied
					end

					target:PivotTo(sequence:GetAttribute("EclipseCameraRoot"))
					target:SetAttribute("EclipseCameraExportOwner", ownerId)
					target.Parent = copies
					if link and link:IsA("ObjectValue") then
						link.Value = original
					end

					copiedRig = target
				end
			end
		end

		if
			not copiedRig
			and not (rig:IsDescendantOf(workspace) and rig:GetAttribute("EclipseCameraTransferRig"))
		then
			local target = CameraRig.createTransfer(
				sequence:GetAttribute("EclipseCameraRoot"),
				rig.Name .. " Camera Rig"
			)
			local copied = sequence:Clone()
			copied.Parent = target.AnimSaves
			local link = Instance.new("ObjectValue")
			link.Name = "EclipseCameraSource"
			link.Value = original
			link.Parent = target
			local reference = Instance.new("ObjectValue")
			reference.Name = "EclipseCameraSequence"
			reference.Value = copied
			reference.Parent = target
			target:SetAttribute("EclipseCameraExportOwner", ownerId)
			target.Parent = copies
			copiedRig = target
		end

		if copiedRig then
			copiedRig:SetAttribute("EclipseCameraExportCopy", true)
			copiedRig.Name = rig.Name .. " Export"
			for _, part in copiedRig:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 1
					part.CanQuery = false
				end
			end
		end
	end

	if isCamera then
		keyframeSequence:Destroy()
	end

	return committed
end

local projectWorkBusy = false
local projectWorkOwner

local function projectWorkActive()
	if
		projectWorkBusy
		and projectWorkOwner
		and coroutine.status(projectWorkOwner.thread) == "dead"
	then
		const owner = projectWorkOwner
		projectWorkBusy, projectWorkOwner = false, nil
		if owner.raw.Exporting == owner.token then
			owner.raw.Exporting = nil
		end
	end

	require("WorkBudget").settle()
	return projectWorkBusy
end

local function runProjectWork(callback)
	if projectWorkActive() or State.LoadingProject or State.Timeline:IsExportLocked() then
		return
	end

	if State.PhysicsSimulating then
		Notification.show("PHYSICS", "Finish the simulation before saving or exporting.")
		return
	end

	projectWorkBusy = true
	local raw = State.Timeline:GetState()
	local rig = State.currentRig
	local playing, recording = raw.Playing, raw.Recording
	local live = State.LiveSession
	local token = {}
	projectWorkOwner = { thread = coroutine.running(), raw = raw, token = token }
	local previousStep = State.ProjectWorkStep
	local acquired, liveStarted = false, false
	local result = table.pack(xpcall(function()
		Project.finalizeCurrentManipulation()
		if live and live.prepareSave then
			live.prepareSave()
		end

		assert(State.currentRig == rig, "The project changed before export")
		raw.Exporting = token
		raw.Playing = false
		raw.Recording = false
		State.LoadingProject = true
		State.ProjectLoadThread = coroutine.running()
		acquired = true
		local slice = os.clock()
		State.ProjectWorkStep = function()
			assert(not token.Cancelled, "Export cancelled because Eclipse closed")
			assert(State.currentRig == rig, "The project changed during export")
			if os.clock() - slice >= 0.012 then
				task.wait()
				slice = os.clock()
			end

			assert(not token.Cancelled, "Export cancelled because Eclipse closed")
			assert(State.currentRig == rig, "The project changed during export")
		end

		if live and live.beginExport then
			liveStarted = true
			live.beginExport()
		end

		if State.BlenderBridge and State.BlenderBridge.waitForExport then
			State.BlenderBridge.waitForExport(function()
				return token.Cancelled
			end)
		end

		return callback()
	end, debug.traceback))
	if acquired then
		State.ProjectWorkStep = previousStep
		State.LoadingProject = nil
		State.ProjectLoadThread = nil
		if raw.Exporting == token then
			raw.Exporting = nil
		end

		raw.Recording = recording
		if State.currentRig == rig then
			raw.Playing = playing and not token.Cancelled
			State.Timeline._playbackReadyAt = os.clock()
		end
	end

	local restored, restoreError = pcall(function()
		if liveStarted and live and live.endExport then
			live.endExport(State.currentRig == rig and not token.Cancelled)
		end
	end)
	projectWorkBusy = false
	projectWorkOwner = nil
	if token.Cancelled and State.currentRig == rig then
		Project.suspendPreview()
	end

	if not result[1] then
		error(result[2], 0)
	end

	if not restored then
		error(restoreError, 0)
	end

	require("History").protectSavedAnimations()
	return table.unpack(result, 2, result.n)
end

local function exportCurrentAnimation(options)
	local results = runProjectWork(function()
		return Batch.run(State.getAllRigs(), exportAnimationForRig)
	end)
	if not results then
		return {}
	end

	local complete = #results > 0
	for _, result in results do
		if result.error then
			complete = false
			warn("[Eclipse export] " .. result.rigName .. ": " .. result.error)
		end
	end

	if complete and Export.documentKind() == "Animation" then
		State.currentProjectSaved = true
	end

	if not options or options.showResults ~= false then
		ExportResults.show(results)
	end

	return results
end

local function getProjectId(save)
	local id = save and save:GetAttribute(PROJECT_ID_ATTRIBUTE)
	return if typeof(id) == "string" and id ~= "" then id else nil
end

local function getProjectSaveName(savesFolder, currentSave, requestedName)
	local reserved = {}
	for _, save in ipairs(savesFolder:GetChildren()) do
		if save ~= currentSave then
			reserved[save.Name] = true
		end
	end

	if not currentSave and Data.isDefaultAnimationName(requestedName) then
		return Data.getNextDefaultProjectName(savesFolder)
	end

	if not reserved[requestedName] then
		return requestedName
	end

	local base = requestedName:match("^(.-) %d+$") or requestedName
	local suffix = 1
	for name in pairs(reserved) do
		local prefix, number = name:match("^(.-) (%d+)$")
		if prefix == base then
			suffix = math.max(suffix, tonumber(number) or 1)
		end
	end

	return base .. " " .. tostring(suffix + 1)
end

rawProjectSequence = function(rig, parent)
	local sequence = Instance.new("KeyframeSequence")
	sequence.Parent = parent
	sequence.Name = "Animation"
	PoseSpace.markCanonical(sequence, rig)
	sequence:SetAttribute("EclipseBuild", Diagnostics.build())
	sequence.Loop = State.Timeline:IsLooping()
	local raw = State.Timeline:GetState()
	State.Timeline:WriteProjectSettings(sequence)
	sequence:SetAttribute("EclipseRawRecovery", true)
	require("layerStorage").write(sequence, rig, raw)
	KeyframeStorage.write(sequence, rig, raw, true)
	PivotSpace.write(sequence, rig)
	MasterControl.write(sequence, rig)
	Properties.write(sequence, rig, raw)
	ArmatureAnimation.write(sequence, rig, raw)
	AnimationEvents.export(rig, sequence, raw.FPS)
	AnimationEvents.writeSubtitles(sequence)
	TrackOrganization.writeForRig(sequence, rig)
	return sequence
end

local CAMERA_BAKES_FOLDER = "EclipseCameraBakes"
local CAMERA_BAKE_ID = "EclipseCameraBakeId"
local CAMERA_BAKE_MIGRATED = "Migrated"
local FOV_MARKER = "EclipseFOVExport"

local function childFolder(parent, name, create)
	for _, child in parent:GetChildren() do
		if child.Name == name and child:IsA("Folder") then
			return child
		end
	end

	if not create then
		return nil
	end

	const folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function cameraBakeOwner(folder)
	const link = folder:FindFirstChild("Camera")
	return if link and link:IsA("ObjectValue") then link.Value else nil
end

local function cameraBakeFolder(rig, create)
	const original = require("rig").original(rig) or rig
	const root = original and require("root").get(CAMERA_BAKES_FOLDER, create)
	if not root then
		return nil
	end

	const id = original:GetAttribute(CAMERA_BAKE_ID)
	const trackId = original:GetAttribute("EclipseTrackId")
	local orphan
	for _, folder in root:GetChildren() do
		if not folder:IsA("Folder") then
			continue
		end

		const owner = cameraBakeOwner(folder)
		if owner == original then
			return folder
		end

		const linked = id ~= nil and folder:GetAttribute(CAMERA_BAKE_ID) == id
			or trackId ~= nil and folder:GetAttribute("EclipseTrackId") == trackId
		if linked and not orphan and not (owner and owner:IsDescendantOf(game)) then
			orphan = folder
		end
	end

	if not create then
		return orphan
	end

	local folder = orphan
	if not folder then
		folder = Instance.new("Folder")
		folder:SetAttribute(CAMERA_BAKE_ID, HttpService:GenerateGUID(false))
	end

	local link = folder:FindFirstChild("Camera")
	if not (link and link:IsA("ObjectValue")) then
		link = Instance.new("ObjectValue")
		link.Name = "Camera"
		link.Parent = folder
	end

	link.Value = original
	folder.Name = original.Name
	folder:SetAttribute("EclipseTrackId", trackId)
	folder.Parent = root
	original:SetAttribute(CAMERA_BAKE_ID, folder:GetAttribute(CAMERA_BAKE_ID))
	return folder
end

local function legacyCameraBakes(rig)
	const original = require("rig").original(rig) or rig
	const saves = original and original:FindFirstChild("AnimSaves")
	const found = {}
	for _, sequence in saves and saves:GetChildren() or {} do
		if
			sequence:IsA("KeyframeSequence")
			and sequence:GetAttribute("EclipseProjectComponent") == true
		then
			table.insert(found, sequence)
		end
	end

	return found, original
end

local function migrateLegacyCameraBakes(rig)
	const legacy, original = legacyCameraBakes(rig)
	if #legacy == 0 then
		return 0
	end

	const bakes = assert(cameraBakeFolder(rig, true), "Could not create the camera bake storage.")
	const migrated = childFolder(bakes, CAMERA_BAKE_MIGRATED, true)
	const fovPart = original:FindFirstChild("FovPart")
	const fovRoot = fovPart and fovPart:FindFirstChild("FieldOfView")
	const fovEntries = if fovRoot and fovRoot:IsA("Folder") and fovRoot:GetAttribute(FOV_MARKER) == true
		then fovRoot:GetChildren()
		else {}
	for _, sequence in legacy do
		const id = getProjectId(sequence)
		for _, entry in fovEntries do
			const matches = entry.Parent == fovRoot
				and entry:IsA("Folder")
				and entry:GetAttribute(FOV_MARKER) == true
				and (if id then entry:GetAttribute("ProjectId") == id else entry.Name == sequence.Name)
			if matches then
				const target = childFolder(migrated, "FieldOfView", true)
				target:SetAttribute(FOV_MARKER, true)
				entry.Parent = target
			end
		end

		sequence.Parent = migrated
	end

	require("History").protectSavedAnimations()
	warn(
		"Eclipse moved "
			.. #legacy
			.. " auto-saved camera copy(s) from "
			.. original:GetFullName()
			.. ".AnimSaves to "
			.. migrated:GetFullName()
			.. " so playtests no longer replicate them. Use Export to place a camera animation in AnimSaves for your game."
	)
	Notification.show(
		"CAMERA COPY MOVED",
		"Auto-saved camera copies now live in ServerStorage > Eclipse Animator Saves > "
			.. CAMERA_BAKES_FOLDER
			.. " to keep playtests fast. Use Export to put a camera animation in AnimSaves for your game."
	)
	return #legacy
end

local function writeBakedCameraFov(bakes, rig, sequence)
	const ok, err = pcall(function()
		const output = require("writer").build(sequence, CameraRig.default(rig))
		const root = childFolder(bakes, "FieldOfView", true)
		root:SetAttribute(FOV_MARKER, true)
		const id = output:GetAttribute("ProjectId")
		for _, child in root:GetChildren() do
			const replaced = if id ~= nil
				then child:GetAttribute("ProjectId") == id
				else child.Name == output.Name
			if replaced then
				child:Destroy()
			end
		end

		output.Parent = root
	end)
	if not ok then
		warn("Camera project saved, but its stored FOV copy failed: " .. tostring(err))
	end
end

local function findProjectAnimation(rig, container, projectId)
	if not projectId or not container then
		return nil
	end

	for _, saved in container:GetChildren() do
		if saved:IsA("KeyframeSequence") and getProjectId(saved) == projectId then
			return saved
		end
	end

	for _, candidate in
		{
			State.exportSequences[rig],
			rig == State.currentRig and State.currentProjectSequence or nil,
		}
	do
		if candidate and candidate:IsA("KeyframeSequence") and candidate.Parent == container then
			local id = getProjectId(candidate)
			if not id or id == projectId then
				return candidate
			end
		end
	end
end

local function authoredCounts(raw, rigs)
	local Layers = require("Layers")
	local counts = {}
	if raw.AnimationLayers then
		Layers.ensure(raw)
		Layers.syncProperties(raw)
	end

	for _, rig in rigs do
		local count = 0
		local rows = raw.AnimationLayers and Layers.stack(raw, rig) or { { keys = raw.Keyframes } }
		for _, layer in rows do
			for motor, bucket in layer.keys do
				if Layers.owner(motor) == rig then
					for _, key in bucket do
						if not key.IsEclipseSynthetic then
							count += 1
						end
					end
				end
			end

			local properties = layer.properties and layer.properties[rig]
			if not raw.AnimationLayers then
				properties = ArmatureAnimation.propertySnapshot(rig)
			end

			for _, track in properties and properties.tracks or {} do
				count += #track.keys
			end
		end

		counts[rig] = count
	end

	return counts
end

local function presentRigs()
	const rigs = {}
	for _, rig in State.getAllRigs() do
		if rig.Parent then
			table.insert(rigs, rig)
		end
	end

	return rigs
end

local function missingRigEntry(rig)
	for _, record in State.MissingRigEntries or {} do
		if record.holder == rig then
			return record.entry
		end
	end

	const original = require("rig").original(rig) or rig
	const id = original:GetAttribute("EclipseTrackId")
	const save = State.currentProjectSave
	const folder = save and save:FindFirstChild("Rigs")
	for _, entry in folder and folder:GetChildren() or {} do
		const link = entry:FindFirstChild("Rig")
		const linked = link and link:IsA("ObjectValue") and link.Value == original
		if entry:FindFirstChild("Animation") and (linked or id ~= nil and entry:GetAttribute("RigId") == id) then
			return entry
		end
	end

	return nil
end

local function carryMissingRigs(rigsFolder, order)
	const names = {}
	const carried = {}

	local function carry(entry)
		if carried[entry] then
			return
		end

		carried[entry] = true
		entry:Clone().Parent = rigsFolder
		table.insert(names, entry:GetAttribute("RigName") or entry.Name)
	end

	for _, rig in State.getProjectRigs() do
		if rig.Parent then
			continue
		end

		const entry = missingRigEntry(rig)
		if entry then
			carry(entry)
			continue
		end

		const ok, err = pcall(function()
			const fresh = Instance.new("Folder")
			fresh.Name = rig.Name
			rawProjectSequence(rig, fresh)
			order += 1
			TrackOrganizationStorage.writeRig(fresh, rig, order)
			fresh:SetAttribute(
				"EclipseAuthoredKeyCount",
				authoredCounts(State.Timeline:GetState(), { rig })[rig]
			)
			fresh.Parent = rigsFolder
			table.insert(names, rig.Name)
		end)
		if not ok then
			warn("[Eclipse] Could not store the missing rig " .. rig.Name .. ": " .. tostring(err))
		end
	end

	for _, record in State.MissingRigEntries or {} do
		if not record.holder then
			carry(record.entry)
		end
	end

	return names
end

local function protectPreviousSave(previous, candidate)
	local oldRigs = previous:FindFirstChild("Rigs")
	if not oldRigs then
		return
	end

	local current = {}
	for _, entry in candidate.Rigs:GetChildren() do
		local id = entry:GetAttribute("RigId")
		if id then
			current[id] = entry:GetAttribute("EclipseAuthoredKeyCount")
		end
	end

	for _, entry in oldRigs:GetChildren() do
		local before = entry:GetAttribute("EclipseAuthoredKeyCount")
		local after = current[entry:GetAttribute("RigId")]

		if before == nil or (before > 0 and (after == nil or after < before)) then
			previous:SetAttribute("EclipseBackupProtected", true)
			previous:SetAttribute(
				"EclipseBackupReason",
				before == nil and "Legacy recovery revision" or "Before keys or rig were removed"
			)
			return
		end
	end
end

local function trimBackups(backups, projectId)
	local recent = {}
	for _, old in backups:GetChildren() do
		if
			getProjectId(old) == projectId
			and old:GetAttribute("EclipseBackupProtected") ~= true
		then
			table.insert(recent, old)
		end
	end

	table.sort(recent, function(a, b)
		return (a:GetAttribute("EclipseBackupTime") or 0)
			> (b:GetAttribute("EclipseBackupTime") or 0)
	end)
	for i = 4, #recent do
		recent[i]:Destroy()
	end
end

function Export.documentKind()
	const openSave = State.currentProjectSave
	if
		openSave
			and (
				openSave:GetAttribute("EclipseLiveProject") == true
				or openSave.Parent ~= nil and openSave:GetAttribute("EclipseSave") == true
			)
		or State.LiveSession and State.LiveSession.isJoined and State.LiveSession.isJoined()
	then
		return "Project"
	end

	local rigs = State.getAllRigs()
	if
		#rigs ~= 1
		or CameraRig.isRig(rigs[1])
		or rigs[1]:IsA("Camera")
		or Properties.propertyOnly(rigs[1])
		or rigs[1]:GetAttribute("EclipseEffectObject") == 1
	then
		return "Project"
	end

	if next(State.extraRigs or {}) then
		return "Project"
	end

	local raw = State.Timeline and State.Timeline:GetState() or {}
	if
		next(raw.ScreenEffects or {})
		or next(raw.GreaseStrokes or {})
		or raw.GreaseDrawings and #raw.GreaseDrawings.layers > 0
	then
		return "Project"
	end

	for _, track in AnimationEvents.all() do
		if track.Rig == rigs[1] or track.ProjectSubtitles then
			for _, event in track.Events or {} do
				if
					event.Subtitle
					or next(event.Sounds or {})
					or next(event.Emits or {})
					or (event.CodeBegin or "") ~= ""
					or (event.CodeEnd or "") ~= ""
				then
					return "Project"
				end
			end
		end
	end

	if State.Physics and State.Physics.hasProjectData and State.Physics.hasProjectData() then
		return "Project"
	end

	return "Animation"
end

local function saveAnimationUnlocked(rawOnly, saveAsName)
	Project.finalizeCurrentManipulation()
	local rig = assert(State.currentRig, "No animation is open.")
	assert(rig.Parent, "The rig is missing; previous saves have been retained.")
	local animSaves = assert(Data.ensureAnimSaves(rig), "Could not create AnimSaves.")
	local previous = not saveAsName and (State.exportSequences[rig] or State.currentProjectSequence)
		or nil

	if previous and (previous.Parent ~= animSaves or getProjectId(previous)) then
		previous = nil
	end

	local requested = Data.sanitizeExportName(saveAsName or Project.getProjectExportName())
	local name = animationSaveName(previous, animSaves, requested)
	local sequence, backup
	local ok, result = xpcall(function()
		local nativeRig = false
		for _, item in RigTraversal.rigDescendants(rig) do
			if item:IsA("Bone") or item:IsA("Motor6D") and item.Part0 and item.Part1 then
				nativeRig = true
				break
			end
		end

		sequence = not rawOnly and nativeRig and buildKeyframeSequenceForRig(rig, name, true)
			or rawProjectSequence(rig)
		if not nativeRig and not rawOnly then
			sequence:SetAttribute("EclipseRawRecovery", nil)
			PoseSpace.markCanonical(sequence, rig)
		end

		assert(sequence, "No animation data is available.")
		sequence.Name = name
		sequence:SetAttribute("EclipseStandaloneAnimation", true)
		sequence:SetAttribute("EclipseHadArmature", ArmatureImport.find(rig) ~= nil)
		local id = previous and previous:GetAttribute("EclipseAnimationId")
			or HttpService:GenerateGUID(false)
		sequence:SetAttribute("EclipseAnimationId", id)
		sequence:SetAttribute(
			"EclipseAuthoredKeyCount",
			authoredCounts(State.Timeline:GetState(), { rig })[rig]
		)
		checkpoint()
		assert(
			rig.Parent and State.currentRig == rig and Export.documentKind() == "Animation",
			"The animation changed while saving; previous save retained."
		)
		if previous then
			backup = previous:Clone()
			backup:SetAttribute("EclipseBackupTime", DateTime.now().UnixTimestampMillis)
			backup:SetAttribute("EclipseAnimationId", id)
			local before = previous:GetAttribute("EclipseAuthoredKeyCount")
			if before == nil or before > sequence:GetAttribute("EclipseAuthoredKeyCount") then
				backup:SetAttribute("EclipseBackupProtected", true)
			end

			backup.Parent = require("root").get("EclipseAnimator_Backups", true)
		end

		local committed = Batch.commit(previous, sequence, animSaves)
		sequence = nil
		committed.Name = name
		return committed
	end, debug.traceback)
	if not ok then
		if sequence then
			sequence:Destroy()
		end

		if backup then
			backup:Destroy()
		end

		warn(result)
        if not rawOnly then return saveAnimationUnlocked(true, saveAsName) end

		State.currentProjectSaved = false
		Notification.show(
			"SAVE NEEDS ATTENTION",
			"Your animation is still open; the previous save is untouched. " .. tostring(result):gsub("^.-:%d+: ", ""):match("[^\n]+")
		)
		return nil
	end

	State.currentProjectSave = nil
	State.currentProjectSequence = result
	State.exportSequences[rig] = result
	markRenameApplied(result)
	State.currentProjectSaved = true
	if backup then
		local recent = {}
		for _, item in backup.Parent:GetChildren() do
			if
				item:IsA("KeyframeSequence")
				and item:GetAttribute("EclipseAnimationId") == result:GetAttribute(
					"EclipseAnimationId"
				)
				and item:GetAttribute("EclipseBackupProtected") ~= true
			then
				table.insert(recent, item)
			end
		end

		table.sort(recent, function(a, b)
			return (a:GetAttribute("EclipseBackupTime") or 0)
				> (b:GetAttribute("EclipseBackupTime") or 0)
		end)
		for i = 4, #recent do
			recent[i]:Destroy()
		end
	end

	AnimationEvents.saved({ rig })
	Project.setProjectName(result.Name)
	populateProjectsList()
	Notification.show(
		"ANIMATION SAVED",
		result.Name
			.. " saved to "
			.. rig.Name
			.. " > AnimSaves." .. (rawOnly and " Editable keys were preserved; native export needs attention." or "") .. " Save your Studio place to keep this after closing Studio."
	)
	return result
end

const RIGS_CHANGED = "The timeline rigs changed while saving"
local autoSaving = false

local function saveProjectUnlocked(rawOnly, saveAsName, forceProject)
	local recoveredFrom = State.ProjectLoadFailure == State.currentProjectSave and State.ProjectLoadFailure or nil
	if recoveredFrom then
		saveAsName = saveAsName or Project.getProjectExportName() .. " (recovered)"
		forceProject = true
	end
	if not forceProject and Export.documentKind() == "Animation" then
		return saveAnimationUnlocked(rawOnly, saveAsName)
	end

	Project.finalizeCurrentManipulation()
	local savesFolder = getSavesFolder(true)
	local rigs = presentRigs()
	local carriedNames = {}

	local function checkRigs()
		local current = presentRigs()
		assert(#current == #rigs, RIGS_CHANGED)
		for i, rig in rigs do
			assert(rig.Parent and current[i] == rig, RIGS_CHANGED)
		end
	end

	local currentSave = if saveAsName then nil else State.currentProjectSave
	if currentSave and currentSave.Parent ~= savesFolder then
		local identity = getProjectId(currentSave)
		if identity then
			for _, candidate in savesFolder:GetChildren() do
				if
					candidate:GetAttribute("EclipseSave") == true
					and getProjectId(candidate) == identity
				then
					currentSave = candidate
					break
				end
			end
		end
	end

	if
		currentSave
		and (currentSave.Parent ~= savesFolder or currentSave:GetAttribute("EclipseSave") ~= true)
	then
		currentSave = nil
	end

	local previousId = getProjectId(currentSave)
	local projectId = previousId or HttpService:GenerateGUID(false)
	local projectName = getProjectSaveName(
		savesFolder,
		currentSave,
		Data.sanitizeExportName(saveAsName or Project.getProjectExportName())
	)
	local save = Instance.new("Folder")
	save.Name = projectName
	local copies = {}
	local replacedCopies = {}
	local openedSequence
	local ok, message = xpcall(function()
		checkRigs()
		local counts = authoredCounts(State.Timeline:GetState(), rigs)
		save:SetAttribute("EclipseSave", true)
		if
			forceProject
			or currentSave and currentSave:GetAttribute("EclipseLiveProject") == true
		then
			save:SetAttribute("EclipseLiveProject", true)
		end

		save:SetAttribute("EclipseCompleteSave", rawOnly ~= true)
		save:SetAttribute(PROJECT_ID_ATTRIBUTE, projectId)
		State.Timeline:WriteProjectSettings(save)
		save:SetAttribute("Loop", State.Timeline:IsLooping())
		TrackOrganization.write(save, rigs)
		AnimationEvents.writeSubtitles(save)
		if State.GreasePencil then
			State.GreasePencil.write(save)
		end

		if State.ScreenEffects then
			State.ScreenEffects.write(save)
		end

		if State.Physics then
			State.Physics.write(save)
		end

		local rigsFolder = Instance.new("Folder")
		rigsFolder.Name = "Rigs"
		rigsFolder.Parent = save
		for rigIndex, rig in ipairs(rigs) do
			local sequence = rawProjectSequence(rig)
			if sequence then
				sequence.Parent = rigsFolder
				sequence:SetAttribute(PROJECT_ID_ATTRIBUTE, projectId)
				sequence:SetAttribute("EclipseProjectComponent", true)
				local armSource = ArmatureImport.find(rig)
				sequence:SetAttribute("EclipseHadArmature", armSource ~= nil)
				local entry = Instance.new("Folder")
				entry.Name = rig.Name
				entry.Parent = rigsFolder
				sequence.Parent = entry
				if rig == State.currentRig then
					openedSequence = sequence
				end

				TrackOrganizationStorage.writeRig(entry, rig, rigIndex)
				entry:SetAttribute("EclipseAuthoredKeyCount", counts[rig])
				if armSource then
					local armCopy = armSource:Clone()
					armCopy.Name = "Armature"
					armCopy.Parent = entry
				end

				if rawOnly == true or not CameraRig.isRig(rig) then
					continue
				end

				local evaluated = assert(
					buildKeyframeSequenceForRig(rig, "Animation", true, nil, true),
					"Camera export is empty"
				)
				local copy = CameraRig.nativeCopy(
					evaluated,
					rig,
					State.Timeline:GetState().DefaultPose,
					checkpoint
				)
				evaluated:Destroy()
				copy:SetAttribute(PROJECT_ID_ATTRIBUTE, projectId)
				copy:SetAttribute("EclipseProjectComponent", true)
				const bakes = cameraBakeFolder(rig, false)
				local previousCopy = if saveAsName
					then nil
					else findProjectAnimation(rig, bakes, previousId)
				local legacyName
				if not saveAsName and not previousCopy and previousId then
					for _, legacy in legacyCameraBakes(rig) do
						if getProjectId(legacy) == previousId then
							legacyName = legacy.Name
							break
						end
					end
				end

				copy.Name = previousCopy and previousCopy.Name
					or legacyName
					or (
						if Data.isDefaultProjectName(projectName)
							then Data.getNextDefaultExportName(bakes)
							else Data.getUniqueExportName(bakes, projectName)
					)
				local staged = { rig = rig, sequence = copy, previous = previousCopy }
				table.insert(copies, staged)
			end
		end

		carriedNames = carryMissingRigs(rigsFolder, #rigs)
		checkRigs()
		for _, copy in ipairs(copies) do
			migrateLegacyCameraBakes(copy.rig)
			const bakes = cameraBakeFolder(copy.rig, true)
			assert(bakes, "Cannot create camera bake storage for " .. copy.rig.Name)
			for _, sequence in ipairs(bakes:GetChildren()) do
				if
					sequence:IsA("KeyframeSequence")
					and (
						sequence == copy.previous
						or previousId and getProjectId(sequence) == previousId
					)
				then
					table.insert(replacedCopies, sequence)
				end
			end

			copy.sequence.Parent = bakes
			copy.bakes = bakes
		end

		save.Parent = savesFolder
	end, debug.traceback)

	if not ok then
		for _, copy in ipairs(copies) do
			copy.sequence:Destroy()
		end

		save:Destroy()
		const rigsChanged = string.find(tostring(message), RIGS_CHANGED, 1, true) ~= nil
		if rigsChanged and autoSaving then
			return nil
		end

		warn(message)
		if rawOnly ~= true and not rigsChanged then
			return saveProjectUnlocked(true, saveAsName, forceProject)
		end

		State.currentProjectSaved = false
		Notification.show(
			"SAVE NEEDS ATTENTION",
			"Your animation is still open; the previous save is untouched. " .. tostring(message):gsub("^.-:%d+: ", ""):match("[^\n]+")
		)
		return
	end

	for _, copy in copies do
		State.exportSequences[copy.rig] = copy.sequence
		writeBakedCameraFov(copy.bakes, copy.rig, copy.sequence)
		if copy.previous and State.currentProjectSequence == copy.previous then
			State.currentProjectSequence = copy.sequence
		end
	end

	if saveAsName and openedSequence then
		State.currentProjectSequence = openedSequence
	end

	for _, sequence in ipairs(replacedCopies) do
		sequence:Destroy()
	end

	if currentSave then
		local backups = require("root").get("EclipseAnimator_Backups", true)
		protectPreviousSave(currentSave, save)
		currentSave:SetAttribute("EclipseBackupTime", DateTime.now().UnixTimestampMillis)
		currentSave.Parent = backups
		trimBackups(backups, projectId)
	end

	AnimationEvents.saved(rigs)
	if State.Timeline.RegroupKeyframes then
		local regrouped, err = pcall(State.Timeline.RegroupKeyframes, State.Timeline)
		if not regrouped then
			warn(err)
		end
	end

	State.currentProjectSave = save
	State.ProjectLoadFailure = nil
	State.currentProjectSaved = true
	Project.setProjectName(projectName)
	for _, rig in State.getAllRigs() do
		local source = require("rig").original(rig)
		if source and source:IsDescendantOf(workspace) then
			CameraRig.organize(source, projectName)
		end
	end

	populateProjectsList()
	Notification.show(
		recoveredFrom and "RECOVERED COPY SAVED" or "PROJECT SAVED",
		projectName
			.. " saved to ServerStorage > Eclipse Animator Saves > "
			.. SAVES_FOLDER_NAME
			.. (rawOnly == true and ". Editable keys preserved; animation export needs attention." or ".")
			.. (recoveredFrom and " The original project is untouched. This copy contains the currently loaded animation; check the original for anything that failed to open." or "")
			.. (#carriedNames > 0 and " Missing rigs kept with their saved keys: " .. table.concat(carriedNames, ", ") .. "." or "")
			.. " Save your Studio place to keep this after closing Studio."
	)
	return save
end

local function saveProject(rawOnly, saveAsName, forceProject)
	const deadline = os.clock() + 10
	while
		coroutine.isyieldable()
		and os.clock() < deadline
		and (
			require("WorkBudget").busy()
			or State.LoadingProject and State.ProjectLoadThread ~= coroutine.running()
		)
	do
		task.wait()
	end

	if
		projectWorkActive()
		or State.LoadingProject
		or not State.Timeline
		or State.Timeline:IsExportLocked()
	then
		Notification.show(
			"NOT SAVED",
			"Eclipse is still loading or saving. Wait a moment, then save again."
		)
		return nil
	end

	return runProjectWork(function()
		return saveProjectUnlocked(rawOnly, saveAsName, forceProject)
	end)
end

function Export.saveLiveProject(rawOnly)
	return saveProject(rawOnly, nil, true)
end

local savingAndClosing = false

local function saveAndCloseProject()
	if savingAndClosing or not UI.isAnimatorActive() or not State.Timeline then
		return false
	end

	if State.Timeline:IsExportLocked() then
		return false
	end

	savingAndClosing = true
	local ok, save = pcall(saveProject)
	savingAndClosing = false
	if not ok then
		warn(save)
		Notification.show(
			"SAVE NEEDS ATTENTION",
			"Your project is still open. Save it successfully before closing."
		)
		return false
	end

	if
		not save
		or (State.currentProjectSave ~= save and State.currentProjectSequence ~= save)
		or not State.currentProjectSaved
	then
		return false
	end

	Project.clearCurrentRig()
	return true
end

local function resolveSaveName(name)
	if Export.documentKind() == "Animation" then
		local folder = State.currentRig and State.currentRig:FindFirstChild("AnimSaves")
		local clean = Data.sanitizeExportName(name)
		return folder and Data.getUniqueExportName(folder, clean) or clean
	end

	local folder = getSavesFolder(false)
	local clean = Data.sanitizeExportName(name)
	return if folder then getProjectSaveName(folder, nil, clean) else clean
end

local function saveProjectAs(name)
	if not UI.isAnimatorActive() or not State.Timeline then
		return nil
	end

	if State.Timeline:IsExportLocked() then
		return nil
	end

	if State.LiveSession and State.LiveSession.isJoined() then
		Notification.show(
			"LIVE",
			"Leave Live before saving a copy. Everyone in the room is editing this file."
		)
		return nil
	end

	local restoreDocument = AnimationEvents.forkDocument()
	local ok, save = pcall(saveProject, nil, name)
	if
		ok
		and save
		and (State.currentProjectSave == save or State.currentProjectSequence == save)
	then
		return save
	end

	restoreDocument()
	if not ok then
		warn(save)
		Notification.show(
			"SAVE NEEDS ATTENTION",
			"The copy wasn't saved. Your project is still open. See Output for the error."
		)
	end

	return nil
end

local function missingRigDescription(entry)
	local name = entry:GetAttribute("RigName")
	if type(name) ~= "string" or name == "" then
		name = entry.Name
	end

	local description = name
	local path = entry:GetAttribute("RigGamePath") or entry:GetAttribute("RigPath")
	if type(path) == "string" then
		local ok, segments = pcall(HttpService.JSONDecode, HttpService, path)
		if ok and type(segments) == "table" then
			local names = {}
			if not entry:GetAttribute("RigGamePath") then
				table.insert(names, "Workspace")
			end

			for _, segment in ipairs(segments) do
				if type(segment) ~= "table" or type(segment.name) ~= "string" then
					table.clear(names)
					break
				end

				table.insert(names, segment.name)
			end

			if #names > 0 then
				description ..= " (" .. table.concat(names, " > ") .. ")"
			end
		end
	end

	return name, description
end

local function showMissingRigs(save, entries)
	local labels, details = {}, {}
	for _, entry in ipairs(entries) do
		local name, description = missingRigDescription(entry)
		if #labels < 4 then
			table.insert(labels, (name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")))
		end

		table.insert(details, description)
	end

	local message = "Couldn't match these saved rigs:\n" .. table.concat(labels, "\n")
	if #entries > #labels then
		message ..= "\n+ " .. (#entries - #labels) .. " more (see Output)"
	end

	message ..= "\nEverything else is open. Their saved keys are kept and saved with the project; add the original rigs, then reopen. Saved locations are in Output."
	warn("Eclipse: unmatched rigs in " .. save.Name .. ":\n" .. table.concat(details, "\n"))
	Notification.show("MISSING RIGS", message)
end

local function openProjectSaveUnlocked(save)
	if not save or not save.Parent then
		return
	end

	local rigsFolder = save:FindFirstChild("Rigs")
	if not rigsFolder then
		error("This save is missing its rig data. Try a backup of the project.", 0)
	end
	const inert = {}
	for _, entry in rigsFolder:GetChildren() do
		local sequence = entry:FindFirstChild("Animation")
		if not sequence or not sequence:IsA("KeyframeSequence") then
			warn("[Eclipse] " .. save.Name .. ": the saved entry " .. entry.Name .. " has no readable animation. It is kept unchanged in the project.")
			table.insert(inert, entry)
		end
	end

	local function keepInert()
		const records = State.MissingRigEntries or {}
		State.MissingRigEntries = records
		for _, entry in inert do
			table.insert(records, { entry = entry:Clone(), holder = nil })
		end
	end

	local function notifyInert()
		if #inert > 0 then
			Notification.show(
				"OPENED WITH UNMATCHED RIGS",
				#inert
					.. (#inert == 1 and " saved rig couldn't be opened; its" or " saved rigs couldn't be opened; their")
					.. " data is kept unchanged and saved with the project. Everything else is open. Details are in Output."
			)
		end
	end

	if #rigsFolder:GetChildren() == #inert then
		Project.openEmptyProject(save)
		keepInert()
		if State.GreasePencil then
			State.GreasePencil.load(save)
		end

		if State.ScreenEffects then
			State.ScreenEffects.load(save)
		end

		if State.Physics then
			State.Physics.load(save)
		end

		TrackOrganization.read(save, {})
		State.ProjectLoadFailure = nil
		State.currentProjectSaved = true
		notifyInert()
		return
	end

	local firstRig, firstSequence = nil, nil
	local others = {}
	if State.ScreenEffects then
		State.ScreenEffects.restoreObjects(save)
	end

	local resolvedRigs = TrackOrganizationStorage.resolveRigs(rigsFolder)
	local missing = {}
	for _, resolved in ipairs(resolvedRigs) do
		local sequence = resolved.entry:FindFirstChild("Animation")
		if
			sequence
			and sequence:IsA("KeyframeSequence")
			and (not resolved.rig or not resolved.rig.Parent)
		then
			table.insert(missing, resolved.entry)
		end
	end

	local function keepMissing(holders)
		const records = {}
		for _, entry in missing do
			const holder = holders and Instance.new("Model") or nil
			if holder then
				holder.Name = entry:GetAttribute("RigName") or entry.Name
				holder.Archivable = false
				const id = entry:GetAttribute("RigId")
				if typeof(id) == "string" then
					holder:SetAttribute("EclipseTrackId", id)
				end

				table.insert(State.extraRigs, holder)
			end

			table.insert(records, { entry = entry:Clone(), holder = holder })
		end

		State.MissingRigEntries = records
		if holders then
			Project.refreshTimelineAfterStructureChange()
		end
	end

	for _, resolved in ipairs(resolvedRigs) do
		local entry = resolved.entry
		local sequence = entry:FindFirstChild("Animation")
		local rig = resolved.rig
		if rig and rig.Parent and sequence and sequence:IsA("KeyframeSequence") then
			if not firstRig then
				firstRig, firstSequence = rig, sequence
			else
				table.insert(others, { rig = rig, sequence = sequence })
			end
		end
	end

	if not firstRig and #missing > 0 then
		Project.openEmptyProject(save)
		keepMissing(false)
		keepInert()
		if State.GreasePencil then
			State.GreasePencil.load(save)
		end

		if State.ScreenEffects then
			State.ScreenEffects.load(save)
		end

		if State.Physics then
			State.Physics.load(save)
		end

		TrackOrganization.read(save, {})
		State.ProjectLoadFailure = nil
		State.currentProjectSaved = true
		showMissingRigs(save, missing)
		notifyInert()
		return
	end

	if not firstRig then
		Notification.show(
			"PROJECT NEEDS ATTENTION",
			"This save has no usable rig animations. Try a backup of the project."
		)
		return
	end

	if Project.openProjectFromKeyframeSequence(firstRig, firstSequence, save) == false then
		return false
	end

	Project.setProjectName(save.Name)
	if typeof(save:GetAttribute("Loop")) == "boolean" then
		State.Timeline:SetLooping(save:GetAttribute("Loop"))
	end

	Project.batchStructure(function()
		for _, info in ipairs(others) do
			if State.ProjectWorkStep then
				State.ProjectWorkStep()
			end

			Project.activateObjectMotorsFromSequence(info.rig, info.sequence)
			if info.sequence:GetAttribute("EclipseHadArmature") then
				local backup = info.sequence.Parent
					and info.sequence.Parent:FindFirstChild("Armature")
				pcall(ArmatureImport.restore, info.rig, backup)
			end

			const added, addError = pcall(Project.addRigToTimeline, info.rig, { Loading = true, AllowDuplicateName = true })
			if not added or addError ~= true then
				warn("[Eclipse] Could not add the saved rig " .. info.rig.Name .. " to the timeline; its saved animation is kept unchanged in the project: " .. tostring(addError))
				table.insert(inert, info.sequence.Parent)
				continue
			end

			if table.find(State.extraRigs, info.rig) then
				const imported, importError = pcall(Project.importKeyframesFromSequence, info.rig, info.sequence)
				if not imported then
					warn("[Eclipse] Could not read the saved animation of " .. info.rig.Name .. "; it is kept unchanged in the project: " .. tostring(importError))
					pcall(Project.removeRigFromTimeline, info.rig, { Loading = true })
					table.insert(inert, info.sequence.Parent)
				end
			end
		end

		if #missing > 0 then
			keepMissing(true)
		end

		keepInert()

		TrackOrganization.read(save, State.getAllRigs())
	end)
	if State.GreasePencil then
		State.GreasePencil.load(save)
	end

	if State.ScreenEffects then
		State.ScreenEffects.load(save)
	end

	if State.Physics then
		State.Physics.load(save)
	end

	for _, rig in State.getAllRigs() do
		if CameraRig.isRig(rig) then
			const migrated, err = pcall(migrateLegacyCameraBakes, rig)
			if not migrated then
				warn("Eclipse could not move the auto-saved camera copy for " .. rig.Name .. ": " .. tostring(err))
			end
		end
	end

	State.currentProjectSaved = not AnimationEvents.hasRecovered()
	State.ProjectLoadFailure = nil
	if #missing > 0 then
		showMissingRigs(save, missing)
	end

	notifyInert()
	Project.notifyUnmatched("project")
end

local function openProjectSave(save)
	require("WorkBudget").settle()
	if State.LoadingProject then
		Notification.show(
			"NOT OPENED",
			"Eclipse is still loading or saving. Wait a moment, then open the project again."
		)
		return
	end

	local beforeLoading, beforeThread, beforeStep =
		State.LoadingProject, State.ProjectLoadThread, State.ProjectWorkStep
	State.LoadingProject = true
	State.ProjectLoadThread = coroutine.running()
	local slice = os.clock()
	State.ProjectWorkStep = function()
		if os.clock() - slice >= 0.008 then
			task.wait()
			slice = os.clock()
		end
	end

	local result = table.pack(xpcall(function()
		return openProjectSaveUnlocked(save)
	end, debug.traceback))
	State.LoadingProject, State.ProjectLoadThread, State.ProjectWorkStep =
		beforeLoading, beforeThread, beforeStep
	if not result[1] then
		if State.currentProjectSave == save then
			State.ProjectLoadFailure = save
			State.ProjectLoadError = tostring(result[2])
			State.currentProjectSaved = false
		end

		warn("[Eclipse] Could not reopen " .. tostring(save and save.Name) .. ": " .. tostring(result[2]))
		Notification.show("COULDN'T OPEN PROJECT", (tostring(result[2]):gsub("^.-:%d+: ", ""):gsub("\n.*", "")) .. " The original save is unchanged. Save will create a separate recovered copy of the loaded animation.")
		return false
	end

	return table.unpack(result, 2, result.n)
end

local projectButtons = {}
local projectListConnections = {}
local projectListPermanent = {}
local projectListPending, projectListDestroyed = false, false

local function queueProjectsList()
	if projectListPending or projectListDestroyed then
		return
	end

	projectListPending = true
	task.defer(function()
		projectListPending = false
		if not projectListDestroyed then
			populateProjectsList()
		end
	end)
end

local function disconnectProjectWatchers()
	for _, connection in projectListConnections do
		connection:Disconnect()
	end

	table.clear(projectListConnections)
end

local function watchProjectFolder(folder)
	if not folder then
		return
	end

	for _, signal in { folder.ChildAdded, folder.ChildRemoved } do
		table.insert(projectListConnections, signal:Connect(queueProjectsList))
	end
end

populateProjectsList = function()
	if projectListDestroyed then
		return
	end

	local mainFrame = UI.MainFrame
	if not mainFrame then
		return
	end

	local leftPanel = mainFrame:FindFirstChild("Left")
	local scroll = leftPanel and leftPanel:FindFirstChild("ScrollingFrame")
	local template = scroll and scroll:FindFirstChild("Template")
	if not scroll or not template then
		return
	end

	template.Visible = false

	for _, btn in ipairs(projectButtons) do
		pcall(function()
			btn:Destroy()
		end)
	end

	table.clear(projectButtons)

	local savesFolder = getSavesFolder(false)
	disconnectProjectWatchers()
	local root = ServerStorage:FindFirstChild("Eclipse Animator Saves")
	watchProjectFolder(root)
	watchProjectFolder(savesFolder)
	if not savesFolder then
		return
	end

	for _, save in ipairs(savesFolder:GetChildren()) do
		if save:IsA("Folder") then
			table.insert(
				projectListConnections,
				save:GetPropertyChangedSignal("Name"):Connect(queueProjectsList)
			)
			table.insert(
				projectListConnections,
				save:GetAttributeChangedSignal("EclipseSave"):Connect(queueProjectsList)
			)
		end

		if save:IsA("Folder") and save:GetAttribute("EclipseSave") == true then
			local btn = template:Clone()
			btn.Name = save.Name
			btn.Visible = true
			local title = btn:FindFirstChild("Title")
			if title then
				title.Text = save.Name
                title.Size = UDim2.new(1, -34, title.Size.Y.Scale, title.Size.Y.Offset)
			end

			btn.MouseButton1Click:Connect(function()
				openProjectSave(save)
			end)
			btn.Parent = scroll
            require("AnimationList").attachDelete(btn, function() return save end)
			table.insert(projectButtons, btn)
		end
	end
end

local projectsListInitialized = false

local function initProjectsList()
	if projectsListInitialized then
		return
	end

	projectsListInitialized = true

	local function connect(signal, callback)
		table.insert(projectListPermanent, signal:Connect(callback))
	end

	if UI.PrimaryFrame then
		connect(UI.PrimaryFrame:GetPropertyChangedSignal("Visible"), function()
			if UI.PrimaryFrame.Visible then
				queueProjectsList()
			end
		end)
	end

	if UI.EclipseGUI then
		connect(UI.EclipseGUI:GetPropertyChangedSignal("Enabled"), function()
			if UI.EclipseGUI.Enabled then
				queueProjectsList()
			end
		end)
		connect(UI.EclipseGUI.Destroying, function()
			projectListDestroyed = true
			disconnectProjectWatchers()
			for _, connection in projectListPermanent do
				connection:Disconnect()
			end

			table.clear(projectListPermanent)
		end)
	end

	local function rootChanged(child)
		if child.Name == "Eclipse Animator Saves" or child.Name == SAVES_FOLDER_NAME then
			queueProjectsList()
		end
	end

	connect(ServerStorage.ChildAdded, rootChanged)
	connect(ServerStorage.ChildRemoved, rootChanged)
	populateProjectsList()
end

local function onLinkedProjectOpened(rig, keyframeSequence)
	if keyframeSequence.Parent == rig:FindFirstChild("AnimSaves") then
		return
	end

	if
		State.currentRig ~= rig
		or State.currentProjectSequence ~= keyframeSequence
		or State.currentProjectSave
	then
		return
	end

	local projectId = getProjectId(keyframeSequence)
	local savesFolder = getSavesFolder(false)
	if not projectId or not savesFolder then
		return
	end

	local save
	for _, candidate in ipairs(savesFolder:GetChildren()) do
		if
			candidate:IsA("Folder")
			and candidate:GetAttribute("EclipseSave") == true
			and getProjectId(candidate) == projectId
		then
			if save then
				return
			end

			save = candidate
		end
	end

	if not save then
		return
	end

	local rigsFolder = save:FindFirstChild("Rigs")
	if not rigsFolder then
		return
	end

	local containsRig = false
	if State.ScreenEffects then
		State.ScreenEffects.restoreObjects(save)
	end

	local resolvedRigs = TrackOrganizationStorage.resolveRigs(rigsFolder)
	for _, resolved in ipairs(resolvedRigs) do
		local sequence = resolved.entry:FindFirstChild("Animation")
		if sequence and sequence:IsA("KeyframeSequence") and not resolved.rig then
			return
		end

		if resolved.rig == rig then
			containsRig = true
		end
	end

	if not containsRig then
		return
	end

	State.currentProjectSave = save
	Project.setProjectName(save.Name)
	Project.batchStructure(function()
		for _, resolved in ipairs(resolvedRigs) do
			local entry = resolved.entry
			local sequence = entry:FindFirstChild("Animation")
			local otherRig = resolved.rig
			if
				otherRig
				and otherRig ~= rig
				and otherRig.Parent
				and sequence
				and sequence:IsA("KeyframeSequence")
			then
				Project.activateObjectMotorsFromSequence(otherRig, sequence)
				Project.addRigToTimeline(otherRig, { Loading = true })
				if table.find(State.extraRigs, otherRig) then
					Project.importKeyframesFromSequence(otherRig, sequence)
				end
			end
		end

		TrackOrganization.read(save, State.getAllRigs())
	end)
	if State.GreasePencil then
		State.GreasePencil.load(save)
	end

	if State.ScreenEffects then
		State.ScreenEffects.load(save)
	end

	if State.Physics then
		State.Physics.load(save)
	end

	State.currentProjectSaved = true
end

Project.setProjectOpenedHook(onLinkedProjectOpened)
local autoSaveQueued = false

local function autoSaveBlocked()
	return projectWorkActive()
		or State.LoadingProject
		or require("WorkBudget").busy()
		or not State.Timeline
		or State.Timeline:IsExportLocked()
		or State.Rig ~= nil
			and (State.Rig._hierarchyBuildToken ~= nil or State.Rig._batchHold == true)
end

local function autoSaveReady()
	if
		autoSaveBlocked()
		or State.currentProjectSave
		or not State.currentRig
		or not UI.isAnimatorActive()
		or Export.documentKind() ~= "Project"
	then
		return false
	end

	for _, rig in State.getProjectRigs() do
		if not rig.Parent then
			return false
		end
	end

	return true
end

Project.structureChanged = function()
	if autoSaveQueued then
		return
	end

	autoSaveQueued = true
	task.defer(function()
		const deadline = os.clock() + 10
		while autoSaveBlocked() and os.clock() < deadline do
			task.wait(0.1)
		end

		autoSaveQueued = false
		if not autoSaveReady() then
			return
		end

		autoSaving = true
		const ok, problem = pcall(saveProject)
		autoSaving = false
		if not ok then
			warn(problem)
		end
	end)
end

Export.buildLibraryPreview = function(rig, onPose)
	return buildKeyframeSequenceForRig(rig, "Library preview", true, onPose)
end

Export.exportCurrentAnimation = exportCurrentAnimation

function Export.createCameraRig(source)
	local sequence
	if source then
		assert(CameraRig.isRig(source), "Select an Eclipse camera.")
		assert(
			State.Timeline and not State.Timeline:GetState().Playing,
			"Pause playback before copying the camera."
		)
		assert(
			not State.LoadingProject and not State.Timeline:IsExportLocked(),
			"Wait for the current project operation to finish."
		)
		assert(
			not State.PhysicsSimulating,
			"Finish the physics simulation before copying the camera."
		)
		sequence =
			buildKeyframeSequenceForRig(source, Project.getProjectExportName(), true, nil, true)
	end

	local view = sequence and sequence:GetAttribute("EclipseCameraRoot")
	local current = workspace.CurrentCamera
	local model = CameraRig.createTransfer(
		view
			or CameraRig.spawnFrame(
				CameraRig.spawnTarget(State),
				current and current.CFrame or CFrame.new(0, 5, 0)
			),
		"Camera Rig"
	)
	if sequence then
		sequence.Parent = model.AnimSaves
		local link = Instance.new("ObjectValue")
		link.Name = "EclipseCameraSource"
		link.Value = source
		link.Parent = model
		local reference = Instance.new("ObjectValue")
		reference.Name = "EclipseCameraSequence"
		reference.Value = sequence
		reference.Parent = model
	end

	return model
end

local function recoveryArmatureCopy(armature, budget)
	if not budget or not armature:IsA("Model") or armature:GetScale() ~= 1 then
		return armature:Clone()
	end

	local supported = {
		Part = true,
		Folder = true,
		StringValue = true,
		ObjectValue = true,
		WireframeHandleAdornment = true,
	}
	local all = armature:GetDescendants()
	for _, object in all do
		budget()
		if not supported[object.ClassName] then
			return armature:Clone()
		end
	end

	local copy = Instance.new("Model")
	local map = { [armature] = copy }

	local function metadata(source, target)
		target.Name = source.Name
		target.Archivable = source.Archivable
		for name, value in source:GetAttributes() do
			target:SetAttribute(name, value)
		end

		for _, tag in source:GetTags() do
			target:AddTag(tag)
		end
	end

	local function pair(source, target)
		map[source] = target
		local children = target:GetChildren()
		local index = 0
		for _, child in source:GetChildren() do
			if child.Archivable then
				index += 1
				local match = children[index]
				assert(
					match and match.ClassName == child.ClassName and match.Name == child.Name,
					"Armature changed during recovery"
				)
				pair(child, match)
			end
		end

		assert(index == #children, "Armature changed during recovery")
	end

	local function children(source, target)
		for _, child in source:GetChildren() do
			budget()
			if child.Archivable then
				if child:IsA("Folder") then
					local folder = Instance.new("Folder")
					metadata(child, folder)
					map[child] = folder
					folder.Parent = target
					children(child, folder)
				else
					local item = assert(child:Clone(), "Armature changed during recovery")
					item.Parent = target
					pair(child, item)
				end
			end
		end
	end

	local ok, err = xpcall(function()
		metadata(armature, copy)
		copy.ModelStreamingMode = armature.ModelStreamingMode
		copy.LevelOfDetail = armature.LevelOfDetail
		copy.WorldPivot = armature.WorldPivot
		children(armature, copy)
		for source, target in map do
			budget()
			if source:IsA("ObjectValue") then
				local value = source.Value
				target.Value = map[value] or value
			elseif source:IsA("WireframeHandleAdornment") then
				local value = source.Adornee
				target.Adornee = map[value] or value
			end
		end

		copy.PrimaryPart = map[armature.PrimaryPart]
		budget()
	end, debug.traceback)
	if not ok then
		copy:Destroy()
		error(err, 0)
	end

	return copy
end

function Export.buildProjectArchive()
	assert(
		not State.ProjectLoadFailure or State.ProjectLoadFailure ~= State.currentProjectSave,
		"Project opening failed; retaining the preceding recovery copy. Reopen the original project."
	)
	local archive = Instance.new("Folder")
	archive.Name = "ProjectArchive"
	local ok, message = xpcall(function()
		State.Timeline:WriteProjectSettings(archive)
		archive:SetAttribute("Loop", State.Timeline:IsLooping())
		local rigs = presentRigs()
		TrackOrganization.write(archive, rigs)
		AnimationEvents.writeSubtitles(archive)
		if State.GreasePencil then
			State.GreasePencil.write(archive)
		end

		if State.ScreenEffects then
			State.ScreenEffects.write(archive)
		end

		if State.Physics then
			State.Physics.write(archive)
		end

		local folder = Instance.new("Folder")
		folder.Name = "Rigs"
		folder.Parent = archive
		for index, rig in rigs do
			local entry = Instance.new("Folder")
			entry.Name = rig.Name
			entry.Parent = folder
			rawProjectSequence(rig, entry).Parent = entry
			TrackOrganizationStorage.writeRig(entry, rig, index)
			local armature = ArmatureImport.find(rig)
			if armature then
				local copy = recoveryArmatureCopy(armature, State.ProjectWorkStep)
				copy.Name = "Armature"
				copy.Parent = entry
			end
		end

		carryMissingRigs(folder, #rigs)
	end, debug.traceback)
	if not ok then
		archive:Destroy()
		error(message, 2)
	end

	return archive
end

function Export.buildRecoveryArchive(budget)
	assert(
		not State.LoadingProject
			and not State.PhysicsSimulating
			and not State.Timeline:GetState().Exporting,
		"The project is busy"
	)
	local rigs = presentRigs()
	local step, owner = State.ProjectWorkStep, coroutine.running()
	local finished = false

	local function recoveryStep()
		if finished then
			if State.ProjectWorkStep == recoveryStep then
				State.ProjectWorkStep = step
			end

			if step then
				step()
			end

			return
		end

		if coroutine.running() ~= owner then
			return
		end

		assert(not State.LoadingProject, "A project operation interrupted recovery")
		if budget then
			budget()
		end

		assert(not State.LoadingProject, "A project operation interrupted recovery")
	end

	State.ProjectWorkStep = recoveryStep
	local success, archive = xpcall(Export.buildProjectArchive, debug.traceback)
	finished = true
	if State.ProjectWorkStep == recoveryStep then
		State.ProjectWorkStep = step
	end

	if not success then
		error(archive, 0)
	end

	local ok, message = pcall(function()
		local current = presentRigs()
		assert(#current == #rigs, "Project rigs changed during recovery")
		for i, rig in rigs do
			assert(rig.Parent and current[i] == rig, "Project rigs changed during recovery")
		end

		for _, entry in archive.Rigs:GetChildren() do
			local sequence = entry:FindFirstChild("Animation")
			if sequence then
				sequence:SetAttribute("EclipseHadArmature", entry:FindFirstChild("Armature") ~= nil)
			end
		end
	end)
	if not ok then
		archive:Destroy()
		error(message, 0)
	end

	return archive
end

Export.saveProject = saveProject
Export.saveAndCloseProject = saveAndCloseProject
Export.saveProjectAs = saveProjectAs
Export.resolveSaveName = resolveSaveName
Export.openProjectSave = openProjectSave
Export.initProjectsList = initProjectsList

local bakeWindow

function Export.bakeAnimation(rig, storeResult)
	assert(
		rig and rig.Parent and table.find(State.getAllRigs(), rig),
		"Select an animated rig in this project."
	)
	assert(not Properties.propertyOnly(rig), "Select a character rig to bake a native animation.")
	local timeline = State.Timeline
	local refs = {
		State = State,
		Finalize = Project.finalizeCurrentManipulation,
		Active = UI.isAnimatorActive,
	}
	local result
	require("Bake").withExportLock(refs, {}, function()
		local raw = timeline:GetState()
		local snapshot = require("snapshot").new(State.getAllRigs(), raw, {})
		local ok, message = xpcall(function()
			result = buildKeyframeSequenceForRig(
				rig,
				Project.getProjectExportName() .. " Baked",
				true,
				nil,
				nil,
				true,
				true
			)
			assert(result, "No animation could be baked.")
		end, debug.traceback)
		local restored, restoreError = pcall(function()
			snapshot:restore()
		end)
		if not ok or not restored then
			if result then
				result:Destroy()
				result = nil
			end

			error(not ok and message or restoreError)
		end
	end)
	if storeResult == false then return result end
	local stored, folder = pcall(Data.ensureAnimSaves, rig)
	if not stored then
		result:Destroy()
		error(folder)
	end

	result.Name = Data.getUniqueExportName(folder, result.Name)
	result:SetAttribute("EclipseDenseBake", true)
	result.Parent = folder
	return result
end

function Export.openBake()
	if bakeWindow then
		bakeWindow:close()
		return
	end

	if not UI.isAnimatorActive() or not State.Timeline or require("BlenderEdit").blocked() then
		return
	end

	local rig = require("SelectedRig").resolve(State, false) or State.currentRig
	if not rig then
		return
	end

	local openedTimeline = State.Timeline
	local openedKeys = openedTimeline:GetState().Keyframes
	local Tool = require("Tool")
	local window = Tool.new(
		{ ScreenGui = UI.EclipseGUI, Plugin = Data.getPlugin() },
		"EclipseBakeAnimation",
		"BAKE ANIMATION",
		Vector2.new(370, 212),
		false,

		function()
			bakeWindow = nil
		end
	)
	bakeWindow = window
	Tool.label(window.frame, "Rig", rig.Name, UDim2.fromOffset(16, 40), UDim2.new(1, -32, 0, 24))
	local info = Tool.label(
		window.frame,
		"Info",
		"Creates a pose at every frame in a new animation copy. Import it into Moon at "
			.. State.Timeline:GetState().FPS
			.. " FPS, or use it in Roblox Animator.",
		UDim2.fromOffset(16, 70),
		UDim2.new(1, -32, 0, 90)
	)
	info.TextWrapped = true
	Tool.button(
		window.frame,
		"Bake",
		"BAKE COPY",
		UDim2.fromOffset(16, 174),
		UDim2.new(1, -32, 0, 26),

		function()
			if window.busy then
				return
			end

			if
				State.Timeline ~= openedTimeline
				or openedTimeline:GetState().Keyframes ~= openedKeys
			then
				window:close()
				return
			end

			window.busy = true
			local ok, result = pcall(Export.bakeAnimation, rig)
			window.busy = false
			if ok then
				window:close()
				Notification.show(
					"ANIMATION BAKED",
					result.Name .. " was saved in " .. rig.Name .. " / AnimSaves."
				)
			else
				Notification.show("BAKE FAILED", tostring(result):gsub("^.-:%d+: ", ""))
			end
		end
	)
	require("Theme").applyTree(window.frame)
end

return Export
