--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Preferences = require("Preferences")
local PropertyGizmo = require("PropertyGizmo")
local Tracks = require("Properties")
local Policy = require("Policy")
local Edit = require("BlenderEdit")
local Armature = require("ArmatureRuntime")
local History = require("History")
local Notification = require("Notification")
local Scale = {}
local refs, selected, active = nil, nil, false
local selecting = false

function Scale.isActive()
	return active and Preferences.get("ScaleGizmo") ~= false
end

local function adapter(motor)
	if not motor or not motor.Parent or Tracks.is(motor) then
		return nil
	end

	local part = motor.Part1
	if
		typeof(part) ~= "Instance"
		or not part:IsA("BasePart")
		or not Policy.channelAvailable(motor, "scale_x")
	then
		return nil
	end

	if typeof(motor) == "table" and (motor.IsEclipseMasterControl or motor.IsTranslationOnly) then
		return nil
	end

	local state = refs.State
	local timeline, rig = state.Timeline, state.currentRig
	local raw = timeline:GetState()
	local base = raw.DefaultSize[part]
	if not base then
		return nil
	end

	local armature = typeof(motor) == "table" and motor.IsEclipseArmatureControl
	local target = {
		IsEclipseScaleAdapter = true,
		Parent = part.Parent,
		Rig = part,
		Part1 = part,
		PropertyId = "Size",
		DefaultValue = base * (armature and 1 or Tracks.scaleFactor(motor)),
	}

	function target.read()
		return armature and (motor.InputScale or Vector3.one) * base or part.Size
	end

	function target.capture()
		return {
			c0 = motor.C0,
			cf = part.CFrame,
			edit = armature and Armature.captureEdit(motor) or nil,
			bucket = timeline:_snapshotMotorBucket(motor),
		}
	end

	function target.write(value, saved, offset)
		if not part.Parent or not motor.Parent then
			return
		end

		local placement = saved and saved.placement
		if armature then
			motor.InputScale = Armature.constrainScale(motor, value / base)
			if placement and placement.edit then
				motor.C0 = placement.c0
				Armature.evaluate(rig, true)
				local shift = placement.cf.Position + (offset or Vector3.zero) - part.Position
				motor.C0 = Armature.solveEditC0(motor, placement.edit.world + shift, placement.edit)
			end

			Armature.evaluate(rig, true)
		else
			part.Size = value
			if placement then
				local shift = offset or Vector3.zero
				motor.C0 = placement.c0 + motor.Part0.CFrame:VectorToObjectSpace(shift)
				part.CFrame = placement.cf + shift
			end
		end
	end

	function target.finish(saved, cancel)
		if not part.Parent or not motor.Parent then
			return
		end

		local value = target.read()
		local pose = target.capture()
		local original = saved.placement or pose

		local function restorePose(size, placement)
			target.write(size)
			motor.C0 = placement.c0
			if armature then
				if placement.edit then
					Armature.restoreEdit(motor, placement.edit)
				end

				Armature.evaluate(rig, true)
			else
				part.CFrame = placement.cf
			end

			require("Resize").syncBones(state, part)
		end

		if cancel then
			restorePose(saved.value, original)
			return
		end

		if (value - saved.value).Magnitude < 1e-6 and pose.c0 == original.c0 then
			return
		end

		require("HumanoidScale").changed(motor)
		if timeline:IsRecording() then
			local before = original.bucket or timeline:_snapshotMotorBucket(motor)
			local channels = { "scale_x", "scale_y", "scale_z" }
			if pose.c0 ~= original.c0 then
				for _, id in { "loc_x", "loc_y", "loc_z" } do
					table.insert(channels, id)
				end
			end

			timeline:RecordPartialKeyframeForMotorAtCurrentTime(
				part,
				motor,
				motor.C0,
				channels,
				state.UIHelpers.SanitizeName,
				{ Frame = saved.frame }
			)
			local after = timeline:_snapshotMotorBucket(motor)

			local function restore(bucket)
				if not motor.Parent then
					return
				end

				timeline:_restoreMotorBucket(motor, bucket)
				timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
				state.currentProjectSaved = false
			end

			History.record(function()
				restore(before)
			end, function()
				restore(after)
			end, "Scale " .. part.Name, saved.frame)
		else
			local function restore(size, placement)
				restorePose(size, placement)
				state.currentProjectSaved = false
			end

			History.record(function() end, function() end, "Scale " .. part.Name, {
				afterUndo = function()
					restore(saved.value, original)
				end,
				afterRedo = function()
					restore(value, pose)
				end,
			})
		end

		state.currentProjectSaved = false
		state.lastCFrames[motor] = motor.C0
	end

	return target
end

local function show()
	if not Scale.isActive() then
		PropertyGizmo.select(selected)
		return false
	end

	local target
	local part = selected and (Tracks.is(selected) and selected.Rig or selected.Part1)
	local mesh = typeof(part) == "Instance"
		and part:IsA("BasePart")
		and part:FindFirstChildWhichIsA("DataModelMesh")
	if mesh and Tracks.definition(mesh, "Scale") then
		local project = refs.State.currentRig

		selecting = true
		local ok, err = xpcall(function()
			if not table.find(refs.State.getAllRigs(), mesh) then
				refs.AddRig(mesh, { Loading = true, MeshScaleTarget = true })
			end

			if not table.find(refs.State.getAllRigs(), mesh) then
				return
			end

			target = Tracks.enable(mesh, "Scale", true, refs.State.Timeline:GetState())
			require("Resize").prepare(mesh)
			if not active or refs.State.currentRig ~= project or not mesh.Parent then
				target = nil
				return
			end

			if refs.RefreshStructure then
				refs.RefreshStructure()
			end
		end, debug.traceback)
		selecting = false
		if not ok then
			error(err)
		end
	elseif
		Tracks.is(selected)
		and (
			selected.Rig:IsA("BasePart")
			or selected.Rig:IsA("Model")
			or selected.Rig:IsA("DataModelMesh")
		)
	then
		local id = selected.Rig:IsA("BasePart") and "Size" or "Scale"
		local enabled = Tracks.enabled(selected.Rig, id)
		target = Tracks.enable(selected.Rig, id, true, refs.State.Timeline:GetState())
		if not enabled then
			refs.State.currentProjectSaved = false
			if refs.RefreshStructure then
				refs.RefreshStructure()
			end
		end

		if selected.Rig:IsA("DataModelMesh") then
			require("Resize").prepare(selected.Rig)
		end
	else
		target = adapter(selected)
	end

	if not active then
		target = nil
	end

	PropertyGizmo.select(target)
	refs.State.Axis:RefreshAxis()
	return target ~= nil
end

function Scale.select(motor, group)
	if group and #group > 1 then
		if selecting then return end
		PropertyGizmo.finish(true)
		selected, active = motor, false
		PropertyGizmo.select(motor, group)
		return
	end
	if selecting then
		return
	end

	if selected == motor then
		if not active then
			PropertyGizmo.select(motor)
		end

		return
	end

	selected = motor
	show()
end

function Scale.disable()
	if not active then
		return
	end

	PropertyGizmo.finish(false)
	active = false
	PropertyGizmo.select(selected)
	refs.State.Axis:RefreshAxis()
end

function Scale.clear()
	PropertyGizmo.finish(true)
	selected, active = nil, false
	PropertyGizmo.select(nil)
end

function Scale.start()
	if not refs or Preferences.get("ScaleGizmo") == false then
		return false
	end

	if PropertyGizmo.isEditing() then
		PropertyGizmo.finish(true)
		return false
	end

	if refs.State.Timeline:GetState().Playing or refs.State.PhysicsSimulating or Edit.blocked() then
		return false
	end

	refs.Finalize()
	active = true
	if not show() then
		Scale.disable()
		Notification.show("SCALE", "Select a rig limb, mesh part or imported armature control.")
		return false
	end

	return PropertyGizmo.begin("pointer")
end

function Scale.reset()
	if
		not refs
		or not selected
		or not selected.Parent
		or PropertyGizmo.isEditing()
		or refs.State.Timeline:GetState().Playing
		or refs.State.PhysicsSimulating
		or Edit.blocked()
	then
		return false
	end

	refs.Finalize()
	local wasActive = active
	active = true
	local ok, result = xpcall(function()
		return show() and PropertyGizmo.reset()
	end, debug.traceback)
	active = wasActive
	if not active then
		PropertyGizmo.select(selected)
		refs.State.Axis:RefreshAxis()
	end

	if not ok then
		error(result, 0)
	end

	return result
end

function Scale.toggle()
	if not refs or Preferences.get("ScaleGizmo") == false then
		return
	end

	if active then
		Scale.disable()
		return
	end

	if refs.State.Timeline:GetState().Playing or refs.State.PhysicsSimulating or Edit.blocked() then
		return
	end

	refs.Finalize()
	active = true
	if not show() then
		Scale.disable()
		Notification.show(
			"SIZING GIZMO",
			"Select a rig limb, mesh part or imported armature control."
		)
	end
end

function Scale.init(options)
	refs, selected, active = options, nil, false
	options.State.ScaleGizmo = Scale
	local unsubscribe = Preferences.subscribe(function(key, value)
		if key == "ScaleGizmo" and value == false then
			Scale.disable()
		end
	end)
	options.ScreenGui.Destroying:Once(unsubscribe)
end

return Scale
