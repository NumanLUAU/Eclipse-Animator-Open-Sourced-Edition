--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local SelectedRig = require("SelectedRig")
local Confirm = require("Confirm")
local Notice = require("Notification")
local Import = require("ArmatureImport")
local Runtime = require("ArmatureRuntime")
local LimbIK = require("LimbIK")
local Membership = require("Membership")
local Pose = require("RigPose")
local BoneMotor = require("BoneMotor")
local History = require("History")
local Removal = {}
local refs

function Removal.remove(rig, arm)
	local state = refs.State
	if not rig.Parent or Import.find(rig) ~= arm or not table.find(state.getAllRigs(), rig) then
		return false
	end

	refs.Finalize()
	local timeline = state.Timeline
	local raw = timeline:GetState()
	raw.Playing = false
	local animation = state.currentAnimations and state.currentAnimations[rig]
	if animation then
		animation:Stop()
	end

	local parent = arm.Parent
	local key = rig:GetAttribute("EclipseArmatureKey")
	local beforePose = Pose.capture(rig)
	local beforeRuntime = Runtime.snapshot(rig)
	local data = Membership.capture(raw, arm)
	for motor in data.Keyframes do
		data.Keyframes[motor] = timeline:_snapshotMotorBucket(motor)
	end

	local defaults = table.clone(raw.DefaultPose)
	for _, object in arm:GetDescendants() do
		if object:IsA("ObjectValue") and object.Value then
			local rest = object:GetAttribute("EclipseArmatureRestC0")
			if typeof(rest) == "CFrame" then
				defaults[object.Value:IsA("Bone") and BoneMotor.get(object.Value) or object.Value] =
					rest
			end
		end
	end

	local stashed = {}
	local store = require("root").get("EclipseArmatures", false)
	if key and store then
		for _, object in store:GetChildren() do
			if object:GetAttribute("EclipseArmatureKey") == key then
				stashed[object] = store
			end
		end
	end

	local current = data

	local function refresh()
		LimbIK.invalidate(rig)
		timeline:ClearSelectedKeyframes()
		if state.Axis then
			state.Axis:ClearSelection()
		end

		refs.RefreshStructure()
		state.currentProjectSaved = false
	end

	local function undo()
		if not rig.Parent then
			return
		end

		rig:SetAttribute("EclipseArmatureKey", key)
		arm.Parent = parent
		for object, home in stashed do
			object.Parent = home
		end

		Import.bind(arm, rig)
		local motors = {}
		for _, motor in Runtime.collectMotors(rig) do
			motors[motor.Part1] = motor
		end

		local function remap(value)
			if typeof(value) == "table" and value.IsEclipseArmatureControl then
				return assert(motors[value.Part1], "Missing restored armature control")
			end

			return value
		end

		for field, values in data do
			if field == "owned" then
				continue
			end

			for object, value in values do
				local mapped = remap(object)
				if field == "Keyframes" then
					local bucket = {}
					for frame, record in value do
						local copy = table.clone(record)
						copy.Motor = mapped
						copy.Part = mapped.Part1
						bucket[frame] = copy
					end

					timeline:_restoreMotorBucket(mapped, bucket)
				else
					raw[field][mapped] = remap(value)
				end
			end
		end

		current = Membership.capture(raw, arm)
		refresh()
		if beforeRuntime then
			assert(Runtime.restore(rig, beforeRuntime), "Could not restore armature pose")
			Runtime.evaluate(rig, true)
		end

		Pose.restore(rig, beforePose)
	end

	local function redo()
		if not rig.Parent then
			return
		end

		Runtime.restoreNativeGeometry(rig)
		Membership.remove(raw, arm, current)
		arm.Parent = nil
		for object in stashed do
			object.Parent = nil
		end

		rig:SetAttribute("EclipseArmatureKey", nil)
		Runtime.suspend(rig)
		refresh()
		Pose.reset(rig, defaults, BoneMotor)
	end

	local ok, err = xpcall(redo, debug.traceback)
	if not ok then
		undo()
		error(err)
	end

	History.record(undo, redo, "Remove armature")
	return true
end

function Removal.open()
	if not refs or not refs.Active() then
		return
	end

	local rig = SelectedRig.resolve(refs.State)
	local arm = rig and Import.find(rig)
	if not arm then
		Notice.show("REMOVE ARMATURE", "Select a rig with an imported armature first.")
		return
	end

	Confirm.open(
		refs.ScreenGui,
		refs.RigItemTemplate,
		"REMOVE ARMATURE",
		'Remove the armature from "'
			.. rig.Name
			.. '"? Its control keyframes will be removed and the character pose will reset. You can undo this action.',
		"Remove",

		function()
			if not refs.Active() then
				return
			end

			local ok, err = pcall(Removal.remove, rig, arm)
			if not ok then
				Notice.show("REMOVE ARMATURE", (tostring(err):gsub("^.-:%d+: ", "")))
			end
		end
	)
end

function Removal.init(options)
	refs = options
end

return Removal
