--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local BlenderEdit = require("BlenderEdit")
local TimelineState = require("RawState").Timeline
local LimbIK = require("LimbIK")
local History = require("History")
local Parenting = require("Parenting")
local R6Controls = require("R6Controls")
local EMPTY = table.freeze({})

return function(Timeline)
	function Timeline:GetIKEndKeys()
		return EMPTY
	end

	function Timeline:GetIKEndMarkerButtons()
		return EMPTY
	end

	function Timeline:RefreshIKEndMarkerPositions() end

	function Timeline:RefreshIKEndMarkers()
		for _, buttons in self._ikEndMarkers or {} do
			for _, button in buttons do
				button:Destroy()
			end
		end

		for key in self._ikEndCoveredKeys or {} do
			if key.Button then
				key.Button.Visible = true
			end
		end

		self._ikEndMarkers, self._ikEndCoveredKeys = nil, nil
	end

	function Timeline:RegisterIKControl(button, motor, refresh)
		self._ikControls = self._ikControls or setmetatable({}, { __mode = "k" })
		local enabled = LimbIK.isEnabled(motor, TimelineState.CurrentTime)
		self._ikControls[button] = { motor = motor, refresh = refresh, enabled = enabled }
		refresh(enabled)
	end

	function Timeline:RefreshIKControls(time)
		for button, control in self._ikControls or {} do
			if button.Parent then
				local enabled = LimbIK.isEnabled(control.motor, time)
				if control.enabled ~= enabled then
					control.enabled = enabled
					control.refresh(enabled)
				end
			else
				self._ikControls[button] = nil
			end
		end
	end

	function Timeline:SwitchIKAtCurrentTime(motor, rig, parentingChange)
		if BlenderEdit.blocked() then
			return
		end

		local chain = LimbIK.chain(rig, motor)
		if not chain or motor:GetAttribute("EclipseDisabled") then
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
		local before, after, spaces, worlds = {}, {}, {}, {}
		for _, member in chain.motors do
			before[member] = self:_snapshotMotorBucket(member)
		end

		for _, control in R6Controls.forOwner(motor) do
			before[control] = self:_snapshotMotorBucket(control)
		end

		local controls = LimbIK.prepare(chain)
		self:CaptureDefaultPoseAdditive(rig)
		local frame = self:TimeToFrame(TimelineState.CurrentTime)
		TimelineState.CurrentTime = self:FrameToTime(frame)
		self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		local enabled = not LimbIK.isEnabled(motor, TimelineState.CurrentTime)
		local target, pole, baseC0, baseWorld, rootControl = LimbIK.capturePose(chain)
		local dependents = {}
		if chain.kind == "Torso" then
			for _, other in chain.entry.chains do
				local state = other.kind == "R6" and LimbIK.state(other)
				if state then
					before[other.owner] = self:_snapshotMotorBucket(other.owner)
					dependents[other] = table.clone(state)
				end
			end
		end

		for _, control in controls do
			if not before[control] then
				before[control] = {}
			end
		end

		for _, member in chain.motors do
			spaces[member] = if enabled
				then self:IsParentedAtTime(member, TimelineState.CurrentTime)
				else LimbIK.restoreParented(chain, member, TimelineState.CurrentTime)
			worlds[member] = Parenting.worldOf(member, TimelineState.MotorByPart)
		end

		for _, member in chain.motors do
			self:RecordKeyframeForMotorAtCurrentTime(
				member.Part1,
				member,
				member.C0,
				nil,
				self.refs.UIHelpers.SanitizeName
			)
			local memberKey = TimelineState.Keyframes[member][frame]
			memberKey.Parented = if parentingChange and parentingChange.motor == member
				then parentingChange.parented
				else enabled or spaces[member]
			memberKey.WorldCFrame = not memberKey.Parented and worlds[member] or nil
			memberKey.MasterWorld = memberKey.WorldCFrame
					and require("MasterControl").worldDelta(member)
				or nil
			memberKey.IKRestoreParented = if enabled then spaces[member] else nil
			memberKey.PathTangentIn, memberKey.PathTangentOut = nil, nil
		end

		local key = TimelineState.Keyframes[motor][frame]
		key.IK = enabled
		key.IKRoot = enabled and rootControl or nil
		key.IKPoleFollowsTarget = enabled
				and chain.kind == "R15"
				and require("Preferences").get("R15PoleFollowsIK") == true
			or nil
		key.IKAnchor = enabled and LimbIK.anchor(chain) or nil
		key.IKRigWorld = enabled and LimbIK.rigFrame(chain) or nil
		key.IKTarget, key.IKPole = enabled and target or nil, enabled and pole or nil
		key.IKBaseC0, key.IKBaseWorld = enabled and baseC0 or nil, enabled and baseWorld or nil
		if enabled then
			local anchor = LimbIK.anchor(chain)
			for _, control in controls do
				local kind = control.Bone:GetAttribute("EclipseR6Control")
				local world = kind == "upper" and target or rootControl
				if chain.kind == "R15" then
					world = ({ root = rootControl, target = target, pole = pole, roll = target })[kind]
				end

				local controlAnchor = anchor
				if chain.kind == "R6" and kind == "pole" then
					world = LimbIK.defaultLegPole(chain, target)
					controlAnchor = target
				end

				if chain.kind == "R15" then
					local parent = chain.entry.map[control.RealPart0]
					controlAnchor = parent and Parenting.worldOf(parent, chain.entry.map)
						or control.Part0.CFrame
				end

				control.C0 = (chain.kind == "R15" and kind == "roll")
						and (TimelineState.DefaultPose[control] or control.Bone.CFrame)
					or controlAnchor:ToObjectSpace(world)
				self:RecordKeyframeForMotorAtCurrentTime(
					control.Part1,
					control,
					control.C0,
					nil,
					self.refs.UIHelpers.SanitizeName
				)
			end
		end

		if chain.kind == "Torso" then
			chain.entry.torsoBaseWorld = enabled and baseWorld or nil
			for other, state in dependents do
				local owner = other.owner
				self:RecordKeyframeForMotorAtCurrentTime(
					owner.Part1,
					owner,
					owner.C0,
					nil,
					self.refs.UIHelpers.SanitizeName
				)
				local childKey = TimelineState.Keyframes[owner][frame]
				childKey.IK, childKey.Parented, childKey.WorldCFrame = true, true, nil
				childKey.IKTarget, childKey.IKPole, childKey.IKRoot =
					state.target, state.pole, state.root
				childKey.IKBaseC0, childKey.IKBaseWorld = state.baseC0, state.baseWorld
				childKey.IKAnchor = LimbIK.anchor(other)
				childKey.IKRigWorld = LimbIK.rigFrame(other)
				after[owner] = self:_snapshotMotorBucket(owner)
			end
		end

		for _, control in controls do
			after[control] = self:_snapshotMotorBucket(control)
		end

		for _, member in chain.motors do
			after[member] = self:_snapshotMotorBucket(member)
		end

		local function refresh(snapshot)
			if snapshot then
				for member, bucket in snapshot do
					self:_restoreMotorBucket(member, bucket, true)
				end

				for member in snapshot do
					self:RefreshAllChannelDiamondsForMotor(member)
				end
			end

			for member in snapshot or after do
				require("Policy").invalidate(TimelineState.Keyframes[member])
				TimelineState._motorUniform[member] = nil
			end

			TimelineState.LastPlaybackFrame = nil
			LimbIK.clearLive()
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			self:RefreshAllKeyframeVisuals()
			self:RefreshIKControls(TimelineState.CurrentTime)
			if self.refs.RefreshIKHierarchy then
				self.refs.RefreshIKHierarchy()
			end

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
		end, "Switch " .. motor.Part1.Name .. " to " .. (enabled and "IK" or "FK"), frame)
		refresh()
	end

	function Timeline:SwitchPoleFollowAtCurrentTime(motor, rig)
		if self:IsExportLocked() or BlenderEdit.blocked() then
			return
		end

		local chain = LimbIK.chain(rig, motor)
		if not chain or chain.kind ~= "R15" or motor:GetAttribute("EclipseDisabled") then
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
		local frame = self:TimeToFrame(TimelineState.CurrentTime)
		TimelineState.CurrentTime = self:FrameToTime(frame)
		self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
		local state = LimbIK.state(chain)
		if not state then
			return
		end

		local before = self:_snapshotMotorBucket(motor)
		state.poleFollowsTarget = not state.poleFollowsTarget
		self:RecordKeyframeForMotorAtCurrentTime(
			motor.Part1,
			motor,
			motor.C0,
			nil,
			self.refs.UIHelpers.SanitizeName
		)
		LimbIK.captureKey(motor, TimelineState.Keyframes[motor][frame])
		local after = self:_snapshotMotorBucket(motor)

		local function restore(bucket)
			if bucket then
				self:_restoreMotorBucket(motor, bucket)
			end

			require("Policy").invalidate(TimelineState.Keyframes[motor])
			LimbIK.clearLive()
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			self:RefreshAllKeyframeVisuals()
			require("motionPath").markDirty()
			if axis then
				axis:InvalidateAxisCache()
				axis:RefreshAxis()
			end

			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		History.record(function()
			restore(before)
		end, function()
			restore(after)
		end, "Switch pole follows IK", frame)
		restore()
	end
end
