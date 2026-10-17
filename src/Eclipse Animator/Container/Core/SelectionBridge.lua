--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Main = require("State")
local Project = require("Project")
local Organization = require("Organization")
local Hierarchy = require("Hierarchy")
local Properties = require("Properties")
local History = require("History")
local Notice = require("Notification")
local Delete = {}

function Delete.item(item)
	if not item then
		return false
	end

	local key = Hierarchy.key(item)
	if item.itemKind == "folder" then
		return Main.Rig:DeleteFolder(key)
	end

	for _, rig in Main.getProjectRigs() do
		if key == rig then
			return Project.removeRigFromTimeline(rig)
		end
	end

	if not key then
		return false
	end

	Project.finalizeCurrentManipulation()
	local timeline = Main.Timeline
	local raw = timeline:GetState()
	local before = Organization.snapshot()
	local after = Organization.snapshot()
	after.removed = after.removed or {}
	local motors = {}
	local parts = {}
	local seen = {}

	local function collect(row)
		if seen[row] then
			return
		end

		seen[row] = true
		local k = Hierarchy.key(row)
		if k then
			after.removed[k] = true
			after.enabled[k] = false
			parts[k] = true
		end

		local motor = row:fetchMotor()
		if motor then
			motors[motor] = true
		end

		for _, child in Hierarchy.authoredChildren(Main.Rig, row) do
			collect(child)
		end
	end

	collect(item)

	local changed = true
	while changed do
		changed = false
		for motor in raw.DefaultPose do
			if
				typeof(motor) == "Instance"
				and motor:IsA("Motor6D")
				and motor:GetAttribute("EclipseAddedObject")
				and (parts[motor.Part1] or parts[motor.Part0])
				and not motors[motor]
			then
				motors[motor] = true
				parts[motor.Part1] = true
				after.removed[motor.Part1] = true
				after.enabled[motor.Part1] = false
				changed = true
			end
		end
	end

	local saved = {}
	for motor in motors do
		local row = {
			disabled = motor:GetAttribute("EclipseDisabled"),
			active = Main.activeObjectMotors[motor],
			keys = {},
		}
		if raw.AnimationLayers then
			for _, layer in raw.AnimationLayers.layers do
				row.keys[layer.id] = layer.keys[motor]
			end
		else
			row.keys.base = raw.Keyframes[motor]
		end

		saved[motor] = row
	end

	local function apply(deleted)
		if Main.Rig then
			Main.Rig._lastClickedItem = nil
		end

		if Main.PropertyGizmo then
			Main.PropertyGizmo.select(nil)
		end

		if Main.Axis then
			Main.Axis:ClearSelection()
		end

		for motor, row in saved do
			if raw.AnimationLayers then
				for _, layer in raw.AnimationLayers.layers do
					layer.keys[motor] = not deleted and row.keys[layer.id] or nil
				end
			else
				raw.Keyframes[motor] = not deleted and row.keys.base or nil
			end

			motor:SetAttribute("EclipseDisabled", deleted and true or row.disabled)
			if typeof(motor) == "Instance" and motor:GetAttribute("EclipseAddedObject") then
				Main.activeObjectMotors[motor] = not deleted and row.active or nil
				motor.Enabled = not deleted and row.active == true
			end

			if deleted and Properties.is(motor) then
				Properties.restoreValue(motor)
			end
		end

		timeline:ClearSelectedKeyframes()
		Organization.restore(deleted and after or before, "items")
		Project.refreshTimelineAfterStructureChange()
		for _, rig in Main.getAllRigs() do
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
		end

		Main.currentProjectSaved = false
	end

	apply(true)
	History.record(function()
		apply(false)
	end, function()
		apply(true)
	end, "Delete Item")
	return true
end

function Delete.selected()
	local item = Main.Rig and Main.Rig._lastClickedItem
	local motor = item and item.fetchMotor and item:fetchMotor()
	if
		typeof(motor) == "Instance"
		and motor:IsA("Motor6D")
		and motor.Part1
		and not motor:GetAttribute("EclipseAddedObject")
	then
		local UI = require("UI")
		require("Confirm").open(
			UI.EclipseGUI,
			UI.RigItemTemplate,
			"DELETE ITEM",
			'Remove "'
				.. motor.Part1.Name
				.. '" and its keyframes from this animation? The part stays on the rig, and Ctrl+Z brings it back.',
			"Remove",

			function()
				Delete.item(item)
			end
		)
		return
	end

	if not Delete.item(item) then
		Notice.show("SELECT AN ITEM", "select an item in the timeline")
	end
end

return Delete
