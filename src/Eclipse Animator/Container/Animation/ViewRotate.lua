--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")

local Input = game:GetService("UserInputService")
local CameraRig = require("CameraRig")
local History = require("History")
local Cursor = require("RotateCursor")
local Edit = require("BlenderEdit")
local Rotate = {}
local Preferences = require("Preferences")

local function verticalEnabled()
	return Preferences.get("DisableCameraQE") ~= true
end

local directions = {
	W = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	A = Vector3.new(-1, 0, 0),
	D = Vector3.new(1, 0, 0),
	Q = Vector3.new(0, -1, 0),
	E = Vector3.new(0, 1, 0),
}

local function commandHeld()
	return Input:IsKeyDown(Enum.KeyCode.LeftControl)
		or Input:IsKeyDown(Enum.KeyCode.RightControl)
		or Input:IsKeyDown(Enum.KeyCode.LeftAlt)
		or Input:IsKeyDown(Enum.KeyCode.RightAlt)
end

local function movement()
	local value = Vector3.zero
	local held = false
	for name, direction in directions do
		if
			(name ~= "Q" and name ~= "E" or verticalEnabled())
			and Input:IsKeyDown(Enum.KeyCode[name])
		then
			value += direction
			held = true
		end
	end

	return value.Magnitude > 1 and value.Unit or value, held
end

local function restoreLook(d)
	if d.mouseBehavior then
		if Input.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition then
			Input.MouseBehavior = d.mouseBehavior
		end

		d.mouseBehavior = nil
	end
end

function Rotate.new(refs)
	local drag
	local self = {}

	function self.isFlying()
		return drag ~= nil and drag.fly == true
	end

	function self.isFlyInput(input)
		return not commandHeld()
			and not Input:GetFocusedTextBox()
			and (
				input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.Keyboard
					and directions[input.KeyCode.Name] ~= nil
					and (input.KeyCode ~= Enum.KeyCode.Q and input.KeyCode ~= Enum.KeyCode.E or verticalEnabled())
			)
	end

	function self.focusLost()
		self.finish(false)
	end

	function self.isEditing()
		return drag ~= nil
	end

	local function stamp(d)
		if refs.State.lastCFrames then
			refs.State.lastCFrames[d.motor] = d.motor.C0
			if d.target and d.target.Parent then
				refs.State.lastCFrames[d.target] = d.target.C0
			end
		end
	end

	function self.finish(cancel)
		if not drag then
			return false
		end

		local d = drag
		drag = nil
		restoreLook(d)
		Cursor.stop()
		local label = d.fly and "Fly camera in view" or "Rotate camera in view"
		if not d.motor.Parent then
			return true
		end

		if cancel then
			d.motor.C0 = d.c0
			if d.target and d.target.Parent then
				d.target.C0 = d.targetC0
			end

			stamp(d)
			return true
		end

		stamp(d)
		if refs.State.lastCFrames then
			refs.State.lastCFrames[d.motor] = d.motor.C0
		end

		local value = d.motor.C0
		if value == d.c0 then
			return true
		end

		local targetValue = d.target and d.target.C0
		local timeline = refs.State.Timeline
		if timeline:IsRecording() then
			timeline:RecordKeyframeForMotorAtCurrentTime(
				d.motor.Part1,
				d.motor,
				value,
				{ Frame = d.frame },
				refs.State.UIHelpers.SanitizeName
			)
			if d.target and d.target.Parent then
				timeline:RecordKeyframeForMotorAtCurrentTime(
					d.target.Part1,
					d.target,
					d.target.C0,
					{ Frame = d.frame },
					refs.State.UIHelpers.SanitizeName
				)
			end

			local after = timeline:_snapshotMotorBucket(d.motor)
			local targetAfter = d.target and timeline:_snapshotMotorBucket(d.target)

			local function restore(bucket, c0, targetBucket, targetPose)
				if not d.motor.Parent then
					return
				end

				timeline:_restoreMotorBucket(d.motor, bucket)
				d.motor.C0 = c0
				if d.target and d.target.Parent then
					timeline:_restoreMotorBucket(d.target, targetBucket)
					d.target.C0 = targetPose
				end

				if refs.State.lastCFrames then
					refs.State.lastCFrames[d.motor] = c0
				end

				stamp(d)
				refs.State.currentProjectSaved = false
			end

			History.record(function()
				restore(d.bucket, d.c0, d.targetBucket, d.targetC0)
			end, function()
				restore(after, value, targetAfter, targetValue)
			end, label)
		else
			History.record(function()
				if d.motor.Parent then
					d.motor.C0 = d.c0
					if d.target and d.target.Parent then
						d.target.C0 = d.targetC0
					end

					stamp(d)
					refs.State.currentProjectSaved = false
				end
			end, function()
				if d.motor.Parent then
					d.motor.C0 = value
					if d.target and d.target.Parent then
						d.target.C0 = targetValue
					end

					stamp(d)
					refs.State.currentProjectSaved = false
				end
			end, label)
		end

		refs.State.currentProjectSaved = false
		return true
	end

	function self.input(input, rig)
		if Input:GetFocusedTextBox() then
			return false
		end

		if
			not verticalEnabled()
			and (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E)
		then
			self.finish(false)
			return false
		end

		if drag and not drag.fly and self.isFlyInput(input) then
			drag.fly = true
			drag.world = CameraRig.viewFrame(rig)
			drag.yaw, drag.pitch = 0, 0
			drag.point = Input:GetMouseLocation()
			Cursor.stop()
			return true
		end

		if drag and drag.fly then
			if
				Shortcuts.matches("Undo", input)
				or Shortcuts.matches("Redo", input)
				or Shortcuts.matches("RedoAlternate", input)
			then
				return false
			end

			if Shortcuts.matches("Cancel", input) then
				self.finish(true)
				return true
			end

			if self.isFlyInput(input) then
				return true
			end

			if
				input.KeyCode == Enum.KeyCode.LeftShift
				or input.KeyCode == Enum.KeyCode.RightShift
			then
				return true
			end

			self.finish(false)
		end

		if drag then
			local ctrl = Input:IsKeyDown(Enum.KeyCode.LeftControl)
				or Input:IsKeyDown(Enum.KeyCode.RightControl)
			if
				Shortcuts.matches("Undo", input)
				or Shortcuts.matches("Redo", input)
				or Shortcuts.matches("RedoAlternate", input)
			then
				return false
			end

			if Shortcuts.matches("CycleCamera", input) then
				self.finish(false)
				return false
			end

			if
				Shortcuts.matches("Cancel", input)
				or input.UserInputType == Enum.UserInputType.MouseButton2
			then
				self.finish(true)
			elseif
				Shortcuts.matches("ConfirmTransform", input)
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				self.finish(false)
			end

			return true
		end

		local fly = self.isFlyInput(input)
		if not fly and not Shortcuts.matches("ToggleBlenderGrab", input) then
			return false
		end

		local timeline = refs.State.Timeline
		if
			Edit.blocked()
			or not rig
			or not rig.Parent
			or not timeline
			or timeline:GetState().Playing
			or timeline:IsExportLocked()
			or refs.State.PhysicsSimulating
			or refs.State.Axis
				and (refs.State.Axis:IsHoldingAxis() or refs.State.Axis:IsBlenderGrabMode() or refs.State.Axis:IsBlenderRotateMode())
		then
			return false
		end

		local motor = CameraRig.motor(rig, "CamPart")
		if not motor then
			return false
		end

		drag = {
			motor = motor,
			fly = fly,
			rig = rig,
			c0 = motor.C0,
			world = CameraRig.viewFrame(rig),
			point = Input:GetMouseLocation(),
			yaw = 0,
			pitch = 0,
			frame = timeline:TimeToFrame(timeline:GetState().CurrentTime),
			bucket = timeline:_snapshotMotorBucket(motor),
		}
		if require("Target").enabledAt(rig, timeline:GetState().CurrentTime) then
			drag.target = CameraRig.motor(rig, "CamTarget")
			if drag.target then
				drag.targetC0 = drag.target.C0
				drag.targetBucket = timeline:_snapshotMotorBucket(drag.target)
				drag.targetDistance = math.max(
					0.1,
					((drag.target.Part0.CFrame * drag.target.C0).Position - drag.world.Position).Magnitude
				)
			end
		end

		if not fly then
			Cursor.start((drag.world * CFrame.new(0, 0, -12)).Position, true)
		end

		return true
	end

	function self.step(rig, dt)
		if not drag then
			return
		end

		if
			drag.rig ~= rig
			or not drag.motor.Parent
			or not drag.motor.Part0
			or not drag.motor.Part1
			or drag.target and (not drag.target.Parent or not drag.target.Part0 or not drag.target.Part1)
			or not rig.Parent
			or refs.State.Timeline:GetState().Playing
		then
			self.finish(true)
			return
		end

		if
			drag.fly
			and (
				Input:GetFocusedTextBox()
				or commandHeld()
				or Edit.blocked()
				or refs.State.Timeline:IsExportLocked()
				or refs.State.Timeline:TimeToFrame(refs.State.Timeline:GetState().CurrentTime)
					~= drag.frame
			)
		then
			self.finish(false)
			return
		end

		local point = Input:GetMouseLocation()
		local delta = point - drag.point
		local move = Vector3.zero
		if drag.fly then
			local held
			move, held = movement()
			local looking = Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			if looking then
				if not drag.mouseBehavior then
					drag.mouseBehavior = Input.MouseBehavior
					Input.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
					delta = Vector2.zero
				else
					delta = Input:GetMouseDelta()
				end
			else
				restoreLook(drag)
				delta = Vector2.zero
			end

			if not looking and not held then
				self.finish(false)
				return
			end
		end

		drag.point = point
		local fine = Input:IsKeyDown(Enum.KeyCode.LeftShift)
			or Input:IsKeyDown(Enum.KeyCode.RightShift)
		local sensitivity = fine and 0.0004 or 0.002
		drag.yaw -= delta.X * sensitivity
		drag.pitch = math.clamp(drag.pitch - delta.Y * sensitivity, -math.pi * 0.49, math.pi * 0.49)
		local world = drag.world * CFrame.Angles(0, drag.yaw, 0) * CFrame.Angles(drag.pitch, 0, 0)
		if drag.fly then
			local speed = require("localOffset").keyboardSpeed(fine)

			local offset = (
				world.RightVector * move.X
				+ Vector3.yAxis * move.Y
				- world.LookVector * move.Z
			) * (speed * math.clamp(dt or 0, 0, 0.1))
			world += offset
			drag.world += offset
		end

		drag.motor.C0 = drag.motor.Part0.CFrame:Inverse()
			* (drag.rig:GetAttribute("EclipseCameraTransferRig") and world or CameraRig.authoredFromView(
				world,
				CameraRig.fov(drag.rig)
			))
			* drag.motor.C1
		if drag.target then
			local targetWorld = drag.target.Part0.CFrame * drag.targetC0 * drag.target.C1:Inverse()
			drag.target.C0 = drag.target.Part0.CFrame:Inverse()
				* (CFrame.new(world.Position + world.LookVector * drag.targetDistance) * targetWorld.Rotation)
				* drag.target.C1
		end
	end

	return self
end

return Rotate
