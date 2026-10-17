--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local TimelineState = require("RawState").Timeline
local HeadStabilizer = require("HeadStabilizer")
local Parenting = require("Parenting")
local History = require("History")
local MotionPath = require("motionPath")

return function(Timeline)
	function Timeline:RegisterHeadStabilizerControl(button, motor, refresh)
		self._headStabilizerControls = self._headStabilizerControls
			or setmetatable({}, { __mode = "k" })
		local enabled = not require("cache").inherits(motor, TimelineState.CurrentTime)
		self._headStabilizerControls[button] =
			{ motor = motor, refresh = refresh, enabled = enabled }
		refresh(enabled)
	end

	function Timeline:RefreshHeadStabilizerControls(time)
		for button, control in self._headStabilizerControls or {} do
			if button.Parent then
				local enabled = not require("cache").inherits(control.motor, time)
				if control.enabled ~= enabled then
					control.enabled = enabled
					control.refresh(enabled)
				end
			else
				self._headStabilizerControls[button] = nil
			end
		end
	end

	function Timeline:SwitchHeadStabilizerAtCurrentTime(motor, rig)
		if self:IsExportLocked() or require("BlenderEdit").blocked() then
			return
		end

		if
			not rig
			or not HeadStabilizer.isEligible(motor)
			or motor:GetAttribute("EclipseDisabled")
		then
			return
		end

		local axis = self.refs.Axis
		if
			axis
			and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
		then
			return
		end

		TimelineState.Playing = false
		self:CaptureDefaultPoseAdditive(rig)
		local frame = self:TimeToFrame(TimelineState.CurrentTime)
		TimelineState.CurrentTime = self:FrameToTime(frame)
		self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		local enabled = require("cache").inherits(motor, TimelineState.CurrentTime)
		local restoreParented = if enabled
			then self:IsParentedAtTime(motor, TimelineState.CurrentTime)
			else HeadStabilizer.restoreParented(motor, TimelineState.CurrentTime)
		local before = self:_snapshotMotorBucket(motor)
		local world = Parenting.worldOf(motor, TimelineState.MotorByPart)
		self:RecordKeyframeForMotorAtCurrentTime(
			motor.Part1,
			motor,
			motor.C0,
			nil,
			self.refs.UIHelpers.SanitizeName
		)
		local key = TimelineState.Keyframes[motor][frame]
		key.HS, key.HSRotation, key.HSLocalRotation = enabled, world.Rotation, motor.C0.Rotation
		key.HSRestoreParented = if enabled then restoreParented else nil
		key.Parented = enabled or restoreParented
		key.WorldCFrame = not key.Parented and world or nil
		key.MasterWorld = key.WorldCFrame and require("MasterControl").worldDelta(motor) or nil
		key.PathTangentIn, key.PathTangentOut = nil, nil
		require("cache").invalidate()
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			local runtime = require("ArmatureRuntime")
			runtime.evaluate(rig, true)
			motor.C0 = runtime.solveEditC0(motor, world, runtime.captureEdit(motor), true)
			self:RecordKeyframeForMotorAtCurrentTime(
				motor.Part1,
				motor,
				motor.C0,
				nil,
				self.refs.UIHelpers.SanitizeName
			)
			key = TimelineState.Keyframes[motor][frame]
			key.HS = enabled
			key.HSRotation = nil
			key.HSLocalRotation = nil
		end

		local after = self:_snapshotMotorBucket(motor)

		local function refresh(snapshot)
			if snapshot then
				self:_restoreMotorBucket(motor, snapshot)
			end

			require("cache").invalidate()
			HeadStabilizer.clearLive()
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			self:RefreshAllKeyframeVisuals()
			MotionPath.markDirty()
			if axis then
				axis:InvalidateAxisCache()
				axis:RefreshAxis()
			end

			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		History.record(function()
			refresh(before)
		end, function()
			refresh(after)
		end, "Turn Inherit Rotation " .. (enabled and "off" or "on"), frame)
		refresh()
	end
end
