--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")

local Joints = {}
local rigs = setmetatable({}, { __mode = "k" })
local busy = false

local function rescale(frame, scale)
	return CFrame.new(frame.Position * scale) * frame.Rotation
end

local function recover(constraint)
	local enabled = constraint:GetAttribute("EclipseConstraintEnabled")
	if enabled == nil then
		return
	end

	local owner = constraint.Parent
	local scale = 1
	while owner do
		local original = owner:GetAttribute("EclipseNativeJointScale")
		if owner:IsA("Model") and original then
			scale = owner:GetScale() / original
			break
		end

		owner = owner.Parent
	end

	local rest = constraint:GetAttribute("EclipseConstraintRestC0")
	if rest and constraint.Attachment0 then
		constraint.Attachment0.CFrame = rescale(rest, scale)
	end

	constraint.Transform =
		rescale(constraint:GetAttribute("EclipseConstraintTransform") or CFrame.identity, scale)
	constraint.Enabled = enabled
	constraint:SetAttribute("EclipseConstraintEnabled", nil)
	constraint:SetAttribute("EclipseConstraintTransform", nil)
	constraint:SetAttribute("EclipseConstraintRestC0", nil)
end

local function restoreMotor(motor)
	local rest = motor:GetAttribute("EclipseConstraintBorrowedC0")
	if typeof(rest) == "CFrame" then
		local owner, scale = motor.Parent, 1
		local original = motor:GetAttribute("EclipseConstraintBorrowedScale")
		while original and owner do
			if owner:IsA("Model") and owner:GetAttribute("EclipseNativeJointScale") then
				scale = owner:GetScale() / original
				break
			end
			owner = owner.Parent
		end
		motor.C0 = rescale(rest, scale)
		motor.C1 = rescale(motor:GetAttribute("EclipseConstraintBorrowedC1") or motor.C1, scale)
		motor:SetAttribute("EclipseConstraintBorrowedScale", nil)
		motor:SetAttribute("EclipseConstraintBorrowedC0", nil)
		motor:SetAttribute("EclipseConstraintBorrowedC1", nil)
	else
		motor:Destroy()
	end
end

function Joints.recover(scope)
	for _, motor in RigTraversal.descendants(scope) do
		if motor:IsA("Motor6D") and (motor:GetAttribute("EclipseConstraintProxy") or motor:GetAttribute("EclipseConstraintBorrowedC0")) then
			restoreMotor(motor)
		end
	end

	for _, constraint in RigTraversal.descendants(scope) do
		if constraint:IsA("AnimationConstraint") then
			recover(constraint)
		end
	end

	for _, object in RigTraversal.descendants(scope) do
		if object:IsA("Model") then
			object:SetAttribute("EclipseNativeJointScale", nil)
		end
	end

	if scope:IsA("Model") then
		scope:SetAttribute("EclipseNativeJointScale", nil)
	end
end

local function remove(entry)
	for _, connection in entry.connections do
		connection:Disconnect()
	end

	for constraint, row in entry.rows do
		restoreMotor(row.motor)
		if constraint.Parent then
			recover(constraint)
		end
	end
end

function Joints.release(rig)
	local entry = rigs[rig]
	if not entry then
		return
	end

	for constraint, row in entry.rows do
		if constraint.Parent and constraint.Attachment0 and row.motor.Parent then
			row.motor.C0 = rescale(row.restC0 * row.transform, rig:GetScale() / entry.scale)
		end
	end

	Joints.flush(rig)
	rigs[rig] = nil
	remove(entry)
	rig:SetAttribute("EclipseNativeJointScale", nil)
end

function Joints.clear()
	local list = {}
	for rig in rigs do
		table.insert(list, rig)
	end

	for _, rig in list do
		Joints.release(rig)
	end
end

function Joints.prepare(rig)
	if busy or not rig or not rig:IsA("Model") then
		return
	end

	local entry = rigs[rig]
	if entry and not entry.dirty then
		return
	end

	local constraints = {}
	for _, item in RigTraversal.rigDescendants(rig) do
		if item:IsA("AnimationConstraint") then
			table.insert(constraints, item)
		end
	end

	if #constraints == 0 and not entry then
		return
	end

	if not entry then
		Joints.recover(rig)
		rig:SetAttribute("EclipseNativeJointScale", rig:GetScale())
		entry = { rows = {}, connections = {}, dirty = true, rig = rig, scale = rig:GetScale() }
		rigs[rig] = entry

		local function changed(item)
			if not busy and (item:IsA("AnimationConstraint") or item:IsA("Attachment")) then
				entry.dirty = true
			end
		end

		table.insert(entry.connections, rig.DescendantAdded:Connect(changed))
		table.insert(entry.connections, rig.DescendantRemoving:Connect(changed))
		table.insert(
			entry.connections,
			rig.Destroying:Connect(function()
				Joints.release(rig)
			end)
		)
	end

	busy = true
	local ok, err = xpcall(function()
		for constraint, row in entry.rows do
			if not constraint:IsDescendantOf(rig) or not row.motor.Parent then
				restoreMotor(row.motor)
				if constraint.Parent then
					recover(constraint)
				end

				entry.rows[constraint] = nil
			end
		end

		local occupied, claimed = {}, {}
		for _, row in entry.rows do
			if row.motor.Part1 then claimed[row.motor.Part1] = true end
		end
		for _, motor in RigTraversal.rigDescendants(rig) do
			if
				motor:IsA("Motor6D")
				and motor.Part1
				and not motor:GetAttribute("EclipseConstraintProxy")
			then
				if not occupied[motor.Part1] or motor.Enabled then occupied[motor.Part1] = motor end
			end
		end

		for _, constraint in constraints do
			if entry.rows[constraint] then
				continue
			end

			recover(constraint)
			local a, b = constraint.Attachment0, constraint.Attachment1
			if
				not constraint.Enabled
				or not a
				or not b
				or not a.Parent
				or not b.Parent
				or not a.Parent:IsA("BasePart")
				or not b.Parent:IsA("BasePart")
				or claimed[b.Parent]
				or occupied[b.Parent] and (occupied[b.Parent].Enabled or occupied[b.Parent].Part0 ~= a.Parent)
			then
				continue
			end

			local motor = occupied[b.Parent]
			local borrowed = motor ~= nil
			if borrowed then
				motor:SetAttribute("EclipseConstraintBorrowedC0", motor.C0)
				motor:SetAttribute("EclipseConstraintBorrowedC1", motor.C1)
			motor:SetAttribute("EclipseConstraintBorrowedScale", rig:GetScale())
			else
				motor = Instance.new("Motor6D")
				motor.Name = constraint.Name
				motor.Archivable = false
				motor.Enabled = false
				motor:SetAttribute("EclipseConstraintProxy", true)
			end
			motor.C0 = a.CFrame * constraint.Transform
			motor.C1 = b.CFrame
			motor.Part0 = a.Parent
			motor.Part1 = b.Parent
			entry.rows[constraint] =
				{ motor = motor, transform = constraint.Transform, restC0 = a.CFrame }
			constraint:SetAttribute("EclipseConstraintEnabled", constraint.Enabled)
			constraint:SetAttribute("EclipseConstraintTransform", constraint.Transform)
			constraint:SetAttribute("EclipseConstraintRestC0", a.CFrame)
			if not borrowed then motor.Parent = constraint.Parent end
			occupied[b.Parent] = motor
			claimed[b.Parent] = true
		end

		entry.dirty = false
	end, debug.traceback)
	busy = false
	if not ok then
		Joints.release(rig)
		error(err)
	end
end

function Joints.applyWorlds(rig, desired)
	local entry = rigs[rig]
	if entry then
		for constraint, row in entry.rows do
			local motor = row.motor
			local a, b = constraint.Attachment0, constraint.Attachment1
			if not constraint.Parent or not a or not b or not motor.Part0 or not motor.Part1 then
				entry.dirty = true
				continue
			end

			if a.CFrame ~= motor.C0 or constraint.Transform ~= CFrame.identity then
				a.CFrame = motor.C0
				constraint.Transform = CFrame.identity

				constraint.Enabled = false
				constraint.Enabled = true
			end
		end
	end

	if not next(desired) then
		return
	end

	local map, parts, seen = {}, {}, {}
	const welds = {}
	local passive = RigTraversal.passiveMotors(rig)

	local function part(value)
		if value and value:IsA("BasePart") and not seen[value] then
			seen[value] = true
			table.insert(parts, value)
		end
	end

	for _, item in RigTraversal.rigDescendants(rig) do
		if item:IsA("BasePart") then
			part(item)
		elseif
			item:IsA("JointInstance")
			and item.Part0
			and item.Part1
			and (
				item.Enabled
				or item:GetAttribute("EclipseConstraintProxy")
				or item:GetAttribute("EclipseConstraintBorrowedC0")
			)
		then
			local accessory = item.Part0:FindFirstAncestorOfClass("Accessory")
			if passive[item] or accessory and not item.Part1:IsDescendantOf(accessory) then
				map[item.Part0] = {
					Part0 = item.Part1,
					C0 = item.C1,
					C1 = item.C0 * (item:IsA("Motor6D") and item.Transform or CFrame.identity),
				}
			elseif item:IsA("Motor6D") or not map[item.Part1] then
				map[item.Part1] = item
			end

			part(item.Part0)
			part(item.Part1)
		elseif
			item:IsA("WeldConstraint")
			and item.Part0
			and item.Part1
			and not (item:GetAttribute("EclipseAccessorySource") and not item.Enabled)
		then
			table.insert(welds, item)
			part(item.Part0)
			part(item.Part1)
		elseif
			item:IsA("RigidConstraint")
			and item.Enabled
			and item.Attachment0
			and item.Attachment1
		then
			local a, b = item.Attachment0, item.Attachment1
			if
				a.Parent
				and b.Parent
				and a.Parent:IsA("BasePart")
				and b.Parent:IsA("BasePart")
				and a:IsDescendantOf(rig)
				and b:IsDescendantOf(rig)
			then
				local accessory = a.Parent:FindFirstAncestorOfClass("Accessory")
				if accessory and not b:IsDescendantOf(accessory) then
					a, b = b, a
				end

				if not map[b.Parent] then
					map[b.Parent] =
						{ Part0 = a.Parent, Part1 = b.Parent, C0 = a.CFrame, C1 = b.CFrame }
				end

				part(a.Parent)
				part(b.Parent)
			end
		end
	end

	if #welds > 0 then
		const reached = {}
		for value, joint in map do
			reached[value] = true
			reached[joint.Part0] = true
		end

		require("RigPose").spreadWelds(rig, welds, reached, function(value, parent, offset)
			map[value] = { Part0 = parent, Part1 = value, C0 = offset, C1 = CFrame.identity }
		end)
	end

	for value in desired do
		part(value)
	end

	local worlds, visiting = {}, {}

	const Parenting = require("Parenting")

	local function world(value)
		if worlds[value] then
			return worlds[value]
		end

		const joint = map[value]
		if
			desired[value]
			and (
				not joint
				or typeof(joint) == "Instance"
					and joint:IsA("Motor6D")
					and Parenting.getDefault(joint) == false
			)
		then
			return desired[value]
		end

		if visiting[value] then
			return value.CFrame
		end

		visiting[value] = true
		local frame = joint and world(joint.Part0) * joint.C0 * joint.C1:Inverse() or value.CFrame
		visiting[value] = nil
		worlds[value] = frame
		return frame
	end

	local frames = {}
	for _, value in parts do
		table.insert(frames, world(value))
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Joints.flush(rig)
	if not rig then
		return
	end

	Joints.applyWorlds(rig, {})
	require("RigPose").syncAccessories(rig)
end

return Joints
