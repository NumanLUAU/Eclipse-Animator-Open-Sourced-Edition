--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tree = require("RigTraversal")
local Paths = require("Paths")
local AccessoryRig = {}

function AccessoryRig.supports(model)
	if not model or not model:IsA("Model") then
		return false
	end

	if model:FindFirstChildOfClass("Humanoid") then
		return true
	end

	for _, object in Tree.descendants(model) do
		if
			object:IsA("Motor6D") and not object:GetAttribute("EclipsePartRigJoint")
			or object:IsA("Bone")
			or object:IsA("AnimationConstraint")
		then
			return true
		end
	end

	return false
end

local function source(motor)
	local ref = motor:FindFirstChild("EclipseAccessoryPart")
	return ref and ref:IsA("ObjectValue") and ref.Value
end

function AccessoryRig.catalog(model)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "Select a rig or model first")
	local objects = Tree.descendants(model)
	local body, existing, links, blocked = {}, {}, {}, {}

	local function link(part, joint)
		if part and part:IsDescendantOf(model) then
			links[part] = links[part] or {}
			table.insert(links[part], joint)
		end
	end

	for _, object in objects do
		if object:IsA("Motor6D") and object:GetAttribute("EclipseAccessoryControl") then
			local part = source(object)
			if part and part:IsDescendantOf(model) then
				existing[part] = object
			end

			if object.Part1 then
				body[object.Part1] = true
			end
		elseif object:IsA("Motor6D") then
			if object.Part0 then
				body[object.Part0] = true
			end

			if object.Part1 then
				body[object.Part1] = true
			end
		elseif object:IsA("AnimationConstraint") then
			for _, attachment in { object.Attachment0, object.Attachment1 } do
				if attachment and attachment.Parent:IsA("BasePart") then
					body[attachment.Parent] = true
				end
			end
		elseif object:IsA("Bone") then
			local part = object:FindFirstAncestorWhichIsA("BasePart")
			if part then
				body[part] = true
			end
		end

		if
			(object:IsA("JointInstance") or object:IsA("WeldConstraint"))
			and not object:GetAttribute("EclipseAccessoryLink")
			and not object:GetAttribute("EclipseAccessoryControl")
		then
			link(object.Part0, object)
			link(object.Part1, object)
		elseif object:IsA("Constraint") and not object:IsA("WeldConstraint") then
			for _, attachment in { object.Attachment0, object.Attachment1 } do
				local part = attachment and attachment:FindFirstAncestorWhichIsA("BasePart")
				if part then
					blocked[part] = true
				end
			end
		end
	end

	local root = model.PrimaryPart
	if not root or not body[root] then
		local incoming = {}
		for _, object in objects do
			if object:IsA("Motor6D") and object.Part1 then
				incoming[object.Part1] = true
			end
		end

		root = nil
		for _, object in objects do
			if body[object] and object:IsA("BasePart") and not incoming[object] then
				root = object
				break
			end
		end
	end

	local parts, plans, reasons = {}, {}, {}
	for _, part in objects do
		if not part:IsA("BasePart") or body[part] or Paths.excluded(part, model) then
			continue
		end

		local accessory = part:FindFirstAncestorOfClass("Accessory")
			or part:FindFirstAncestorOfClass("Hat")
		if accessory and accessory:FindFirstChild("Handle") ~= part and not existing[part] then
			continue
		end

		table.insert(parts, part)
		if existing[part] then
			continue
		end

		if part:FindFirstChildWhichIsA("WrapLayer", true) then
			reasons[part] = "Layered clothing"
		elseif part:FindFirstChildWhichIsA("Bone", true) then
			reasons[part] = "Use its bone tracks"
		elseif blocked[part] then
			reasons[part] = "Constrained part"
		else
			local candidates = {}
			local unsafe = false
			for _, joint in links[part] or {} do
				if not joint.Enabled then
					continue
				end

				local other = joint.Part0 == part and joint.Part1 or joint.Part0

				if
					accessory
					and other
					and other:IsDescendantOf(accessory)
					and (
						joint:IsA("Weld")
						or joint:IsA("WeldConstraint")
						or joint:IsA("ManualWeld")
					)
				then
					continue
				end

				if
					other
					and body[other]
					and other:IsDescendantOf(model)
					and (
						joint:IsA("Weld")
						or joint:IsA("WeldConstraint")
						or joint:IsA("ManualWeld")
					)
				then
					table.insert(candidates, { joint = joint, parent = other })
				else
					unsafe = true
				end
			end

			if unsafe or #candidates > 1 then
				reasons[part] = "Multiple or unsupported joints"
			elseif #candidates == 1 then
				plans[part] = candidates[1]
			elseif accessory then
				reasons[part] = "Attach this accessory to the rig first"
			elseif root then
				plans[part] = { parent = root }
			else
				reasons[part] = "No rig root"
			end
		end
	end

	table.sort(parts, function(a, b)
		return Paths.of(a, model) < Paths.of(b, model)
	end)
	return parts, existing, plans, reasons
end

function AccessoryRig.create(model, selected)
	local parts, existing, plans, reasons = AccessoryRig.catalog(model)
	local chosen = {}
	for part, enabled in selected do
		if enabled then
			assert(table.find(parts, part), "A selected part was removed")
			assert(not reasons[part], part.Name .. ": " .. tostring(reasons[part]))
			if not existing[part] then
				table.insert(chosen, part)
			end
		end
	end

	assert(#chosen > 0, "Choose an accessory or part that is not already on the timeline")
	table.sort(chosen, function(a, b)
		return Paths.of(a, model) < Paths.of(b, model)
	end)
	local names = {}
	for _, object in Tree.descendants(model) do
		if object:IsA("BasePart") then
			names[object.Name] = true
		end
	end

	local entries, joints, owned = {}, {}, {}
	for _, part in chosen do
		local plan = plans[part]
		assert(plan and plan.parent and plan.parent.Parent, "The attachment was removed")
		local accessory = part:FindFirstAncestorOfClass("Accessory")
			or part:FindFirstAncestorOfClass("Hat")
		local name = accessory and accessory.Name or part.Name
		local base = name
		local index = 1
		while names[name] do
			index += 1
			name = base .. " (" .. index .. ")"
		end

		names[name] = true

		local control = Instance.new("Part")
		control.Name = name
		control.Size = part.Size
		control.CFrame = part.CFrame
		control.Transparency = 1
		control.CanCollide = false
		control.CanTouch = false
		control.CanQuery = false
		control.CastShadow = false
		control.Massless = true
		control:SetAttribute("EclipseAccessoryControlPart", true)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = plan.parent
		motor.Part1 = control
		local original = plan.joint
		if original and original:IsA("JointInstance") then
			if original.Part0 == part then
				motor.C0 = original.C1
				motor.C1 = original.C0
			else
				motor.C0 = original.C0
				motor.C1 = original.C1
			end
		else
			motor.C0 = plan.parent.CFrame:ToObjectSpace(part.CFrame)
		end

		motor:SetAttribute("EclipseAccessoryControl", true)
		motor:SetAttribute("EclipseAnimatorDefaultC0", motor.C0)
		local ref = Instance.new("ObjectValue")
		ref.Name = "EclipseAccessoryPart"
		ref.Value = part
		ref.Parent = motor
		local weld = Instance.new("Weld")
		weld.Name = "EclipseAccessoryLink"
		weld.Part0 = control
		weld.Part1 = part
		weld:SetAttribute("EclipseAccessoryLink", true)
		weld.Parent = control
		motor.Parent = control
		table.insert(entries, {
			part = part,
			control = control,
			motor = motor,
			original = original,
			enabled = original and original.Enabled,
			stamp = original and original:GetAttribute("EclipseAccessorySource"),
			frame = part.CFrame,
		})
		table.insert(joints, motor)
		owned[control] = true
		owned[motor] = true
	end

	local transaction = { model = model, joints = joints, owned = owned, parts = chosen }

	function transaction.apply(enabled)
		for _, entry in entries do
			if enabled then
				if entry.original then
					entry.original:SetAttribute("EclipseAccessorySource", true)
					entry.original.Enabled = false
				end

				entry.control.Parent = model
			else
				entry.control.Parent = nil
				if entry.original and entry.original.Parent then
					entry.original.Enabled = entry.enabled
					entry.original:SetAttribute("EclipseAccessorySource", entry.stamp)
				end
			end

			entry.control.CFrame = entry.frame
			if entry.part.Parent then
				entry.part.CFrame = entry.frame
			end
		end
	end

	transaction.apply(true)
	return transaction
end

return AccessoryRig
