--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local BlenderEdit = require("BlenderEdit")
local TimelineState = require("RawState").Timeline
local Parenting = require("Parenting")
local GraphCurves = require("GraphCurves")
local LimbIK = require("LimbIK")
local HeadStabilizer = require("HeadStabilizer")
local History = require("History")

return function(Timeline)
	function Timeline:IsParentedAtTime(motor, time)
		local link = require("Target").childAt(motor, time)
		if link then
			return not link.world
		end

		return LimbIK.isDriven(motor, time)
			or Parenting.isParentedAt(
				motor,
				TimelineState.Keyframes[motor],
				time,
				TimelineState.ParentingDefaults[motor]
			)
	end

	function Timeline:CaptureKeyframeParenting(motor, keyData, c0, skipChildCapture)
		if typeof(keyData.Parented) ~= "boolean" then
			local previous = nil
			for _, candidate in pairs(TimelineState.Keyframes[motor] or {}) do
				if
					candidate ~= keyData
					and not candidate.GraphOnly
					and not candidate.Disabled
					and candidate.Time <= keyData.Time
					and (not previous or candidate.Time > previous.Time)
				then
					previous = candidate
				end
			end

			keyData.Parented =
				Parenting.keyIsParented(motor, previous, TimelineState.ParentingDefaults[motor])
		end

		if keyData.Parented then
			keyData.WorldCFrame = nil
		else
			local parentMotor = TimelineState.MotorByPart[Parenting.realPart0(motor)]
			local parentWorld = parentMotor
					and Parenting.worldOf(parentMotor, TimelineState.MotorByPart)
				or motor.Part0.CFrame
			keyData.WorldCFrame = parentWorld * c0 * motor.C1:Inverse()
		end

		LimbIK.captureKey(motor, keyData)
		HeadStabilizer.captureKey(motor, keyData, c0)
		if not skipChildCapture then
			require("Target").capture(motor, keyData, c0)
		end

		keyData.MasterWorld = keyData.WorldCFrame and require("MasterControl").worldDelta(motor)
			or nil
		GraphCurves.invalidate(TimelineState.Keyframes[motor])
	end

	function Timeline:RefreshParentingControls(time, isParentedAt, childAt)
		time = time or TimelineState.CurrentTime
		for button, entry in pairs(self._parentingControls or {}) do
			if not button.Parent then
				self._parentingControls[button] = nil
			else
				local parented
				if isParentedAt then
					parented = isParentedAt(entry.motor, time)
				end

				if parented == nil then
					parented = self:IsParentedAtTime(entry.motor, time)
				end

				local link = require("Target").childAt(entry.motor, time)
				if link then
					parented = not link.world
				end

				local driven = LimbIK.isDriven(entry.motor, time)
					or HeadStabilizer.isEnabled(entry.motor, time)
				local child = (not childAt or childAt(entry.motor, time))
					and require("Target").childAt(entry.motor, time) ~= nil
				if entry.parented ~= parented or entry.driven ~= driven or entry.child ~= child then
					entry.parented, entry.driven, entry.child = parented, driven, child
					entry.refresh(parented, driven, child)
				end
			end
		end
	end

	function Timeline:RegisterParentingControl(button, motor, refresh, rig)
		self._parentingControls = self._parentingControls or setmetatable({}, { __mode = "k" })
		local parented = self:IsParentedAtTime(motor, TimelineState.CurrentTime)
		LimbIK.getRig(rig)
		local driven = LimbIK.isDriven(motor, TimelineState.CurrentTime)
			or HeadStabilizer.isEnabled(motor, TimelineState.CurrentTime)
		local child = require("Target").childAt(motor, TimelineState.CurrentTime) ~= nil
		self._parentingControls[button] = {
			motor = motor,
			refresh = refresh,
			parented = parented,
			driven = driven,
			child = child,
			rig = rig,
		}
		refresh(parented, driven, child)
	end

	local function selectedParentingKeys(self, motor)
		const controls = {}
		for _, entry in self._parentingControls or {} do
			if entry.rig then
				controls[entry.motor] = entry.rig
			end
		end

		if not controls[motor] then
			return nil
		end

		const Target = require("Target")
		const keys = {}
		local includesMotor = false
		for key in TimelineState.SelectedKeyframes or {} do
			const keyMotor = key.Motor
			const bucket = keyMotor and TimelineState.Keyframes[keyMotor]
			if
				controls[keyMotor]
				and bucket
				and bucket[key.Frame] == key
				and not key.GraphOnly
				and keyMotor.Part1
				and (typeof(keyMotor) ~= "Instance" or keyMotor.Parent and not keyMotor:GetAttribute("EclipseDisabled"))
				and not LimbIK.isDriven(keyMotor, key.Time)
				and not HeadStabilizer.isEnabled(keyMotor, key.Time)
				and not Target.childAt(keyMotor, key.Time)
			then
				table.insert(keys, key)
				includesMotor = includesMotor or keyMotor == motor
			end
		end

		if
			not includesMotor
			or #keys == 1 and keys[1].Frame == self:TimeToFrame(TimelineState.CurrentTime)
		then
			return nil
		end

		return keys, controls
	end

	function Timeline:SwitchParentingForKeys(keys, controls)
		local allParented = true
		for _, key in keys do
			if not Parenting.keyIsParented(key.Motor, key, TimelineState.ParentingDefaults[key.Motor]) then
				allParented = false
				break
			end
		end

		const parented = not allParented
		const startTime = TimelineState.CurrentTime
		const rigs, frames, motors, before = {}, {}, {}, {}
		TimelineState.Playing = false
		for _, key in keys do
			rigs[controls[key.Motor]] = true
			frames[key.Frame] = frames[key.Frame] or {}
			table.insert(frames[key.Frame], key)
			if not motors[key.Motor] then
				motors[key.Motor] = true
				before[key.Motor] = self:_snapshotMotorBucket(key.Motor)
			end
		end

		for rig in rigs do
			self:CaptureDefaultPoseAdditive(rig)
		end

		const MasterControl = require("MasterControl")
		const captured = {}
		for frame, list in frames do
			const time = self:FrameToTime(frame)
			TimelineState.CurrentTime = time
			for rig in rigs do
				self:ApplyPoseAtTime(rig, time)
			end

			for _, key in list do
				const keyMotor = key.Motor
				captured[key] = {
					c0 = keyMotor.C0,
					world = Parenting.worldOf(keyMotor, TimelineState.MotorByPart),
					master = MasterControl.worldDelta(keyMotor),
				}
			end
		end

		const sanitize = self.refs.UIHelpers.SanitizeName
		const ok, err = pcall(function()
			for frame, list in frames do
				const time = self:FrameToTime(frame)
				TimelineState.CurrentTime = time
				for rig in rigs do
					self:ApplyPoseAtTime(rig, time)
				end

				for _, key in list do
					const keyMotor, capture = key.Motor, captured[key]
					self:RecordKeyframeForMotorAtCurrentTime(keyMotor.Part1, keyMotor, capture.c0, nil, sanitize)
					const bucket = TimelineState.Keyframes[keyMotor]
					const current = bucket and bucket[frame]
					if current then
						current.Parented = parented
						current.WorldCFrame = not parented and capture.world or nil
						current.MasterWorld = not parented and capture.master or nil
						current.PathTangentIn = nil
						current.PathTangentOut = nil
					end
				end
			end
		end)

		TimelineState.CurrentTime = startTime

		local function refresh()
			for rig in rigs do
				self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			end

			self:RefreshAllKeyframeVisuals()
			self:RefreshAllChannelDiamondColors()
			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		local function restore(snapshots)
			for keyMotor, snap in snapshots do
				self:_restoreMotorBucket(keyMotor, snap)
			end

			refresh()
		end

		if not ok then
			restore(before)
			error(err, 0)
		end

		const after = {}
		for keyMotor in motors do
			GraphCurves.invalidate(TimelineState.Keyframes[keyMotor])
			after[keyMotor] = self:_snapshotMotorBucket(keyMotor)
		end

		History.record(function()
			restore(before)
		end, function()
			restore(after)
		end, "Switch " .. #keys .. " keyframes to " .. (parented and "Parent" or "World"), self:TimeToFrame(startTime))
		refresh()
	end

	function Timeline:SwitchParentingAtCurrentTime(motor, rig)
		if BlenderEdit.blocked() then
			return
		end

		if not motor or not motor.Parent or not rig or motor:GetAttribute("EclipseDisabled") then
			return
		end

		if require("Targets").switchSpace(motor, rig) then
			return
		end

		local driven = LimbIK.drivingChain(motor, TimelineState.CurrentTime)
		if driven then
			return self:SwitchIKAtCurrentTime(
				driven.owner,
				rig,
				{ motor = motor, parented = false }
			)
		end

		if HeadStabilizer.isEnabled(motor, TimelineState.CurrentTime) then
			return
		end

		const selectedKeys, controls = selectedParentingKeys(self, motor)
		if selectedKeys then
			return self:SwitchParentingForKeys(selectedKeys, controls)
		end

		TimelineState.Playing = false
		self:CaptureDefaultPoseAdditive(rig)
		local frame = self:TimeToFrame(TimelineState.CurrentTime)
		local time = self:FrameToTime(frame)
		TimelineState.CurrentTime = time
		self:ApplyPoseAtTime(rig, time)
		local parented = not self:IsParentedAtTime(motor, time)
		local before = self:_snapshotMotorBucket(motor)
		local c0 = motor.C0
		local world = Parenting.worldOf(motor, TimelineState.MotorByPart)
		local sanitize = self.refs.UIHelpers.SanitizeName
		self:RecordKeyframeForMotorAtCurrentTime(motor.Part1, motor, c0, nil, sanitize)
		local key = TimelineState.Keyframes[motor][frame]
		key.Parented = parented
		key.WorldCFrame = not parented and world or nil
		key.MasterWorld = not parented and require("MasterControl").worldDelta(motor) or nil
		key.PathTangentIn = nil
		key.PathTangentOut = nil
		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		local after = self:_snapshotMotorBucket(motor)

		local function refresh()
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			self:RefreshAllKeyframeVisuals()
			self:RefreshAllChannelDiamondColors()
			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		History.record(function()
			self:_restoreMotorBucket(motor, before)
			refresh()
		end, function()
			self:_restoreMotorBucket(motor, after)
			refresh()
		end, "Switch " .. motor.Part1.Name .. " to " .. (parented and "Parent" or "World"), frame)
		refresh()
	end
end
