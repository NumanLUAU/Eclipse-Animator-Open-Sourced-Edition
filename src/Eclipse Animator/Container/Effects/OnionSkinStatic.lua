--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preferences = require("Preferences")
local Target = require("SelectedRig")
local CameraRig = require("CameraRig")
local CameraDisplay = require("CameraDisplay")
local OnionSkin = {}
local Snapshot = require("KeyframeCleanup")

local function ghostColor()
	return Preferences.color("OnionSkinColor")
end

local function ghostTransparency()
	return Preferences.get("OnionSkinTransparency") / 100
end

local GHOST_MATERIAL = Enum.Material.Neon
local GHOST_SIZE_SCALE = 1.005
local LAYER_NAME = "_EclipseAnimator_OnionLayer"
local GHOST_NAME_PREFIX = "_EclipseOnion_"

local State = nil
local UI = nil
local History = nil
local MotorMath = nil

local captures = {}
local capturedRig
local lifetime = {}
local watcher
local partLockState = {}

local function selectedTarget()
	local selected = State.Axis and State.Axis:GetSelectedBone()
	if selected then
		local rig = Target.resolve({ Axis = State.Axis, getAllRigs = State.getAllRigs }, false)
		if rig then
			return rig
		end
	end

	return Target.resolve(State, false) or capturedRig or State.currentRig
end

local function getCamera()
	return workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")
end

local function getSanitizeName()
	return (State and State.UIHelpers and State.UIHelpers.SanitizeName)
		or function(s)
			return tostring(s or ""):gsub("%s+", "")
		end
end

local function stripPartChildren(clone)
	for _, child in ipairs(clone:GetChildren()) do
		if child:IsA("DataModelMesh") then
			if child:IsA("FileMesh") then
				pcall(function()
					child.TextureId = ""
				end)
			end
		elseif child:IsA("HandleAdornment") then
			pcall(function()
				child:SetAttribute("EclipseOnionOriginalTransparency", child.Transparency)
				child.Color3 = ghostColor()
				if child.Transparency > 0 then
					child.Transparency = 1 - ((1 - child.Transparency) * (1 - ghostTransparency()))
				end

				child.ZIndex = math.max(child.ZIndex - 1, 0)
			end)
		else
			child:Destroy()
		end
	end
end

local function buildGhost(part, parent)
	local clone = part:Clone()
	if clone:IsA("MeshPart") then
		pcall(function()
			clone.TextureID = ""
		end)
	end

	stripPartChildren(clone)
	pcall(function()
		clone.Size = clone.Size * GHOST_SIZE_SCALE
	end)
	for _, child in ipairs(clone:GetChildren()) do
		if child:IsA("DataModelMesh") then
			pcall(function()
				child.Scale = child.Scale * GHOST_SIZE_SCALE
			end)
		end
	end

	clone.Locked = false
	clone.Anchored = true
	clone.Massless = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.Archivable = false
	clone.Material = GHOST_MATERIAL
	clone.Transparency = ghostTransparency()
	clone.Color = ghostColor()
	clone.Parent = parent
	return clone
end

function OnionSkin:Initialize(deps)
	self:Clear()
	for _, connection in lifetime do
		connection:Disconnect()
	end

	table.clear(lifetime)
	State = deps.State
	UI = deps.UI
	History = deps.History
	MotorMath = deps.MotorMath
	self:InitializeAutomatic()
	local unsubscribeAppearance = Preferences.subscribe(function(key)
		if
			key == "OnionSkinColor"
			or key == "OnionSkinTransparency"
			or key == "PoseGhostPreviousColor"
			or key == "PoseGhostNextColor"
			or key == "PoseGhostTransparency"
		then
			self:RefreshAppearance()
		end
	end)
	table.insert(lifetime, { Disconnect = unsubscribeAppearance })
	table.insert(
		lifetime,
		UI.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not UI.AnimatorFrame.Visible then
				self:Clear()
			end
		end)
	)
	table.insert(
		lifetime,
		UI.EclipseGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not UI.EclipseGUI.Enabled then
				self:Clear()
			end
		end)
	)
	table.insert(
		lifetime,
		UI.EclipseGUI.Destroying:Connect(function()
			self:Clear()
			for _, c in lifetime do
				c:Disconnect()
			end

			table.clear(lifetime)
		end)
	)
end

function OnionSkin:IsActive()
	return next(captures) ~= nil
end

local function clearRig(rig)
	local capture = captures[rig]
	if not capture then
		return
	end

	captures[rig] = nil
	for part in capture.locks do
		local lock = partLockState[part]
		if lock then
			lock.count -= 1
			if lock.count == 0 then
				if part.Parent then
					pcall(function()
						part.Locked = lock.wasLocked
					end)
				end

				partLockState[part] = nil
			end
		end
	end

	capture.layer:Destroy()
	if capturedRig == rig then
		capturedRig = next(captures)
	end

	if next(captures) == nil and watcher then
		watcher:Disconnect()
		watcher = nil
	end
end

function OnionSkin:Clear()
	self:ClearAutomatic()
	while next(captures) do
		clearRig(next(captures))
	end

	capturedRig = nil
end

function OnionSkin:Toggle(recapture)
	if not State or not UI then
		return
	end

	if not State.currentRig or not UI.AnimatorFrame.Visible then
		return
	end

	local target = selectedTarget()
	if not target or not target.Parent then
		return
	end

	if captures[target] then
		clearRig(target)
		if not recapture then
			return
		end
	end

	capturedRig = target
	local capturedFov = CameraRig.isRig(target) and CameraRig.fov(target) or nil

	local parent = getCamera() or workspace

	local onionLayer = Instance.new("Folder")
	local motorGhosts = {}
	local capture = { layer = onionLayer, ghosts = motorGhosts, fov = capturedFov, locks = {} }
	captures[target] = capture
	onionLayer.Name = LAYER_NAME
	require("Recovery").mark(onionLayer)
	onionLayer.Parent = parent
	local source = Instance.new("ObjectValue")
	source.Name = "EclipseSourceRig"
	source.Value = target
	source.Parent = onionLayer

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local lock = partLockState[descendant]
			if not lock then
				lock = { count = 0, wasLocked = descendant.Locked }
				partLockState[descendant] = lock
			end

			lock.count += 1
			capture.locks[descendant] = true
			descendant.Locked = true
		end
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if
			descendant:IsA("Motor6D")
			and descendant.Part1
			and descendant.Part0
			and not CameraRig.isFov(descendant)
		then
			local ghost = buildGhost(descendant.Part1, onionLayer)
			ghost.Name = GHOST_NAME_PREFIX .. descendant.Part1.Name
			ghost.CFrame = descendant.Part1.CFrame
			motorGhosts[descendant] = ghost
			if CameraRig.isTransform(descendant) then
				ghost.Transparency = 1
				ghost.CFrame = CameraRig.displayFrame(target)
				for i, pair in CameraDisplay.segments(capturedFov) do
					local line = Instance.new("LineHandleAdornment")
					line.Name = "OnionCamera" .. i
					line.Adornee = ghost
					line.CFrame = CFrame.lookAt(pair[1], pair[2])
					line.Length = (pair[2] - pair[1]).Magnitude
					line.Color3 = ghostColor()
					line.Thickness = 3
					line.Transparency = ghostTransparency()
					line.AlwaysOnTop = true
					line.Parent = ghost
				end
			end
		end
	end

	if not watcher then
		local elapsed = 0
		watcher = game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.1 then
				return
			end

			elapsed = 0
			local stale = {}
			for rig, capture in captures do
				if not rig.Parent or not capture.layer.Parent then
					table.insert(stale, rig)
				end
			end

			for _, rig in stale do
				clearRig(rig)
			end
		end)
	end
end

function OnionSkin:Capture()
	if not State or not UI or not State.currentRig or not UI.AnimatorFrame.Visible then
		return
	end

	local target = selectedTarget()
	if not target or not target.Parent then
		return
	end

	self:Toggle(true)
end

function OnionSkin:ApplyToRig()
	if not self:IsActive() then
		return
	end

	if not State or not UI or not History then
		return
	end

	if not State.currentRig or not UI.AnimatorFrame.Visible then
		return
	end

	if not State.Timeline then
		return
	end

	local target = selectedTarget()
	local capture = target and captures[target]
	if not capture then
		return
	end

	local motorGhosts, capturedFov = capture.ghosts, capture.fov
	if not target or not target.Parent then
		return
	end

	local Timeline = State.Timeline
	local sanitizeName = getSanitizeName()
	local timeline = Timeline:GetState()
	local frameNumber = Timeline:TimeToFrame(timeline.CurrentTime)
	local records = {}

	local poses = {}
	local ghostParts = {}
	for motor, ghost in motorGhosts do
		if ghost and ghost.Parent and motor.Part1 then
			ghostParts[motor.Part1] = ghost.CFrame
		end
	end

	for motor, ghost in motorGhosts do
		if ghost and ghost.Parent and motor.Part0 then
			local parentPose = ghostParts[motor.Part0] or motor.Part0.CFrame
			poses[motor] = parentPose:Inverse() * ghost.CFrame * motor.C1
		end
	end

	local fovMotor = capturedFov and CameraRig.motor(target, "FovPart")
	if fovMotor then
		poses[fovMotor] = CameraRig.encode(fovMotor, capturedFov)
	end

	for motor, pose in pairs(poses) do
		if motor.Parent and motor.Part0 and motor.Part1 then
			local prevC0 = motor.C0
			local newC0 = pose

			local bucket = Timeline:GetMotorKeyframeBucket(motor)
			local hadKeyframe = bucket and bucket[frameNumber] ~= nil
			local prevKeyframeC0 = hadKeyframe and bucket[frameNumber].C0 or nil
			local before = Snapshot.copy(bucket or {})

			local locked = MotorMath.collectTrackParentLockedDescendants(target, motor)
			motor.C0 = newC0
			MotorMath.restoreTrackParentLockedDescendants(locked)

			Timeline:RecordKeyframeForMotorAtCurrentTime(
				motor.Part1,
				motor,
				newC0,
				UI.TrackContainer,
				sanitizeName
			)

			table.insert(records, {
				part = motor.Part1,
				motor = motor,
				frame = frameNumber,
				newC0 = newC0,
				prevC0 = prevC0,
				hadKeyframe = hadKeyframe,
				prevKeyframeC0 = prevKeyframeC0,
				before = before,
				after = Snapshot.copy(Timeline:GetMotorKeyframeBucket(motor)),
			})
		end
	end

	if #records == 0 then
		return
	end

	State.currentProjectSaved = false

	local captured = records
	local capturedFrame = frameNumber

	local description
	if #records == 1 then
		description = "Onion skin apply (" .. records[1].part.Name .. ")"
	else
		description = "Onion skin apply (" .. #records .. " bones)"
	end

	History.record(function()
		for _, r in ipairs(captured) do
			if r.motor and r.motor.Parent then
				local locked = MotorMath.collectTrackParentLockedDescendants(target, r.motor)
				r.motor.C0 = r.prevC0
				MotorMath.restoreTrackParentLockedDescendants(locked)
			end
		end

		for _, r in captured do
			if r.motor and r.motor.Parent then
				Timeline:_restoreMotorBucket(r.motor, r.before)
			end
		end

		if State.currentRig then
			Timeline:ApplyPoseAtTime(target, Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, function()
		for _, r in ipairs(captured) do
			if r.motor and r.motor.Parent then
				local locked = MotorMath.collectTrackParentLockedDescendants(target, r.motor)
				r.motor.C0 = r.newC0
				MotorMath.restoreTrackParentLockedDescendants(locked)
			end
		end

		for _, r in captured do
			if r.motor and r.motor.Parent then
				Timeline:_restoreMotorBucket(r.motor, r.after)
			end
		end

		if State.currentRig then
			Timeline:ApplyPoseAtTime(target, Timeline:GetState().CurrentTime)
		end

		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
			State.Axis:RefreshBoneFade()
		end
	end, description, capturedFrame)

	if State.Axis and State.Axis:GetSelectedBone() then
		State.Axis:RefreshAxis()
		State.Axis:RefreshBoneFade()
	end
end

local automaticGhosts, automaticStamp, automaticRevision
local automaticUnsubscribe
local automaticFrames, automaticRetry = nil, 0
local automaticContext, automaticPending
local automaticCache, automaticUse = {}, 0

local function sameStamp(a, b)
	if not a or not b then
		return false
	end

	for i = 1, 8 do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

function OnionSkin:ClearAutomatic()
	for _, entry in automaticCache do
		entry.model:Destroy()
	end

	table.clear(automaticCache)
	if automaticGhosts then
		automaticGhosts:Destroy()
		automaticGhosts = nil
	end

	automaticStamp, automaticContext, automaticPending = nil, nil, nil
end

function OnionSkin:UpdateAutomatic(deferBuild)
	local timeline = State and State.Timeline
	local raw = timeline and timeline:GetState()
	if
		not raw
		or not require("Preferences").get("AutomaticOnionSkin")
		or not UI.AnimatorFrame.Visible
		or not UI.EclipseGUI.Enabled
		or State.PresentationHidden
		or raw.Playing
	then
		self:ClearAutomatic()
		return
	end

	if
		State.LoadingProject
		or State.PhysicsSimulating
		or raw.Exporting
		or History.isApplying()
		or State.scoreDragStarted
		or State.PropertyGizmo and State.PropertyGizmo.isEditing()
	then
		return
	end

	local axis = State.Axis
	if
		axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
	then
		return
	end

	local interaction = require("RawState")
	if interaction.KeyframeDrag.draggingKeyframe or interaction.KeyframeTransform.active then
		return
	end

	local rig = selectedTarget()
	if not rig or not rig.Parent then
		self:ClearAutomatic()
		return
	end

	if os.clock() < automaticRetry then
		return
	end

	local geometry = require("geometry")
	local scope = geometry.scope(rig)
	if not scope then
		self:ClearAutomatic()
		return
	end

	local transparency = require("Preferences").get("PoseGhostTransparency") / 100
	local frame = raw.CurrentTime * raw.FPS
	local before, after
	if
		not automaticFrames
		or automaticFrames.rig ~= rig
		or automaticFrames.keys ~= raw.Keyframes
		or automaticFrames.revision ~= automaticRevision
	then
		local set = {}
		local owners = { rig }

		for _, other in State.getAllRigs() do
			if other ~= rig and (other == scope or other:IsDescendantOf(scope)) then
				table.insert(owners, other)
			end
		end

		for _, owner in owners do
			local motors = require("Parenting").collectMotors(owner)
			for _, motor in require("Properties").list(owner, true) do
				table.insert(motors, motor)
			end

			for _, motor in motors do
				for at, key in raw.Keyframes[motor] or {} do
					if not require("Policy").isDisabled(key) then
						set[at] = true
					end
				end
			end
		end

		local frames = {}
		for at in set do
			table.insert(frames, at)
		end

		table.sort(frames)
		automaticFrames =
			{ rig = rig, keys = raw.Keyframes, revision = automaticRevision, frames = frames }
	end

	local frames = automaticFrames.frames
	local low, high = 1, #frames + 1
	while low < high do
		local mid = math.floor((low + high) / 2)
		if frames[mid] < frame - 1e-5 then
			low = mid + 1
		else
			high = mid
		end
	end

	before = frames[low - 1]
	while frames[low] and frames[low] <= frame + 1e-5 do
		low += 1
	end

	after = frames[low]
	if not before and not after then
		self:ClearAutomatic()
		return
	end

	local stamp = { rig, raw.Keyframes, before, after, raw.FPS, automaticRevision, 0, scope }
	if sameStamp(automaticStamp, stamp) and automaticGhosts and automaticGhosts.Parent then
		return
	end

	local context = { rig, raw.Keyframes, raw.FPS, automaticRevision, 0, scope }
	if not sameStamp(automaticContext, context) then
		self:ClearAutomatic()
		automaticContext = context
	end

	local missing = {}
	for _, at in { before or false, after or false } do
		if at ~= false and not automaticCache[at] then
			table.insert(missing, at)
		end
	end

	if #missing > 0 and deferBuild then
		if automaticGhosts then
			automaticGhosts.Parent = nil
		end

		if not automaticPending or not sameStamp(automaticPending.stamp, stamp) then
			automaticPending = { stamp = stamp, at = os.clock() }
			return
		end

		if os.clock() - automaticPending.at < 0.08 then
			return
		end
	end

	automaticPending = nil
	local root = automaticGhosts
	if not root then
		root = Instance.new("Folder")
		root.Name = "_EclipseAdjacentPoses"
		require("Recovery").mark(root)
		automaticGhosts = root
	end

	local created = {}
	if #missing > 0 then
		local snapshot
		local resume = raw.CurrentTime
		local lastCFrames = State.lastCFrames and table.clone(State.lastCFrames)
		local lastApply = raw.LastPoseApplyClock
		local restoreTargets = require("Target").previewSnapshot()
		local ok, message = xpcall(function()
			snapshot = require("snapshot").new(
				State.getAllRigs(),
				raw,
				getCamera() and { getCamera() } or {}
			)
			snapshot:capture(scope)
			for _, object in scope:GetDescendants() do
				snapshot:capture(object)
			end

			local rigs = State.getAllRigs()

			local function sample(index)
				if index <= #rigs then
					return require("ArmatureRuntime").withSampling(rigs[index], function()
						sample(index + 1)
					end)
				end

				for _, at in missing do
					raw.CurrentTime = at / raw.FPS

					timeline:ApplyPoseAtTime(rig, at / raw.FPS, { SkipControls = true })
					local clone = geometry.capture(rig, scope, Color3.new(1, 1, 1), transparency)
					created[at] = { model = clone }
				end
			end

			sample(1)
		end, debug.traceback)
		raw.CurrentTime = resume
		local restored, restoreError = pcall(function()
			if snapshot then
				snapshot:restore()
			end
		end)
		if lastCFrames then
			table.clear(State.lastCFrames)
			for motor, value in lastCFrames do
				State.lastCFrames[motor] = value
			end
		end

		raw.LastPoseApplyClock = lastApply
		restoreTargets()
		if not ok or not restored then
			for _, entry in created do
				entry.model:Destroy()
			end

			self:ClearAutomatic()
			automaticRetry = os.clock() + 5
			warn("[Eclipse pose ghosts] " .. tostring(not ok and message or restoreError))
			return
		end

		for at, entry in created do
			automaticCache[at] = entry
		end
	end

	for at, entry in automaticCache do
		if at ~= before and at ~= after then
			entry.model.Parent = nil
		end
	end

	for _, pose in
		{
			{ before, Preferences.color("PoseGhostPreviousColor"), "Previous" },
			{ after, Preferences.color("PoseGhostNextColor"), "Next" },
		}
	do
		if pose[1] == nil then
			continue
		end

		local entry = automaticCache[pose[1]]
		if entry.color ~= pose[2] then
			entry.tintTargets = geometry.tint(entry.model, pose[2], entry.tintTargets)
			entry.color = pose[2]
		end

		automaticUse += 1
		entry.used = automaticUse
		entry.model.Name = pose[3]
		entry.model.Parent = root
	end

	local count = 0
	for _ in automaticCache do
		count += 1
	end

	while count > 4 do
		local oldest, age
		for at, entry in automaticCache do
			if at ~= before and at ~= after and (not age or (entry.used or 0) < age) then
				oldest, age = at, entry.used or 0
			end
		end

		automaticCache[oldest].model:Destroy()
		automaticCache[oldest] = nil
		count -= 1
	end

	root.Parent = getCamera() or workspace
	automaticStamp = stamp
end

function OnionSkin:RefreshAppearance()
	for _, capture in captures do
		for motor, ghost in capture.ghosts do
			ghost.Color = ghostColor()
			ghost.Transparency = CameraRig.isTransform(motor) and 1 or ghostTransparency()
			for _, child in ghost:GetChildren() do
				if child:IsA("HandleAdornment") then
					child.Color3 = ghostColor()
					local original = child:GetAttribute("EclipseOnionOriginalTransparency")
					child.Transparency = original and 1 - (1 - original) * (1 - ghostTransparency())
						or ghostTransparency()
				end
			end
		end
	end

	local geometry = require("geometry")
	for _, entry in automaticCache do
		local key = entry.model.Name == "Previous" and "PoseGhostPreviousColor"
			or "PoseGhostNextColor"
		entry.color = Preferences.color(key)
		entry.tintTargets = geometry.tint(entry.model, entry.color, entry.tintTargets)
		geometry.opacity(entry.model, Preferences.get("PoseGhostTransparency") / 100)
	end
end

function OnionSkin:InitializeAutomatic()
	self:ClearAutomatic()
	if automaticUnsubscribe then
		automaticUnsubscribe()
	end

	automaticRevision = 0
	automaticFrames = nil
	automaticRetry = 0
	automaticUnsubscribe = History.subscribe(function()
		automaticRevision += 1
	end)
	local elapsed = 0
	table.insert(
		lifetime,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.03 then
				return
			end

			elapsed = 0
			self:UpdateAutomatic(true)
		end)
	)
	table.insert(
		lifetime,
		UI.EclipseGUI.Destroying:Connect(function()
			self:ClearAutomatic()
			if automaticUnsubscribe then
				automaticUnsubscribe()
				automaticUnsubscribe = nil
			end
		end)
	)
end

return OnionSkin
