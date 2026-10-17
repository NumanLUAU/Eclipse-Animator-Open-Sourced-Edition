--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Weld = {}

function Weld.primary(object)
	if not object or not object.Parent then
		return nil
	end

	if object:IsA("BasePart") then
		return object
	end

	if object:IsA("Model") then
		return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

function Weld.selection(selected)
	local anchor, source
	local candidates, seen = {}, {}
	for _, object in selected do
		local primary = Weld.primary(object)
		if not primary or seen[object] then
			continue
		end

		seen[object] = true
		if not anchor then
			anchor, source = primary, object
		elseif object ~= source and primary ~= anchor and not anchor:IsDescendantOf(object) then
			table.insert(candidates, object)
		end
	end

	local targets = {}
	for _, object in candidates do
		local nested = false
		for _, other in candidates do
			if other ~= object and object:IsDescendantOf(other) then
				nested = true
				break
			end
		end

		if not nested then
			table.insert(targets, object)
		end
	end

	return anchor, targets
end

function Weld.plan(anchor, targets)
	assert(anchor and anchor.Parent and anchor:IsA("BasePart"), "Select an anchor first.")
	assert(#targets > 0, "Select one or more targets after the anchor.")
	local entries, seen = {}, {}
	for _, object in targets do
		local primary = Weld.primary(object)
		assert(primary, "A target was removed or has no parts. Reselect the targets.")
		assert(
			primary ~= anchor and not anchor:IsDescendantOf(object),
			"A target contains the anchor."
		)
		assert(not seen[primary], "Targets overlap. Select each part or model once.")
		seen[primary] = true
		local parts = object:IsA("Model") and object:GetDescendants() or { object }
		local entry = { object = object, primary = primary, parts = {} }
		for _, part in parts do
			if part:IsA("BasePart") then
				table.insert(entry.parts, part)
			end
		end

		table.insert(entries, entry)
	end

	return entries
end

function Weld.apply(anchor, targets, inPlace, animatable, workspaceRoot)
	local entries = Weld.plan(anchor, targets)
	local primaries = {}
	for _, entry in entries do
		primaries[entry.primary] = entry
	end

	local joints = {}
	for _, joint in workspaceRoot:GetDescendants() do
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			local p0, p1 = joint.Part0, joint.Part1
			local child = primaries[p1]
			local incoming = child
				and joint:GetAttribute("EclipseHelperWeld") == true
				and not table.find(child.parts, p0)
			local rebound = primaries[p0] and p1 == anchor or primaries[p1] and p0 == anchor
			if incoming or rebound then
				joint:Destroy()
			else
				table.insert(joints, joint)
			end
		end
	end

	for _, entry in entries do
		local primary, object = entry.primary, entry.object
		if not inPlace then
			if object:IsA("Model") then
				local offset = object:GetPivot():ToObjectSpace(primary.CFrame)
				object:PivotTo(anchor.CFrame * offset:Inverse())
			else
				primary:PivotTo(anchor.CFrame)
			end
		end

		local groups = {}
		for _, part in entry.parts do groups[part] = part end
		local function find(part)
			while groups[part] ~= part do part = groups[part] end
			return part
		end
		local function connect(a, b)
			if groups[a] and groups[b] then groups[find(b)] = find(a) end
		end
		for _, joint in joints do connect(joint.Part0, joint.Part1) end
		for _, part in entry.parts do
			if find(part) ~= find(primary) then
				local internal = Instance.new("WeldConstraint")
				internal.Name, internal.Part0, internal.Part1 = "EclipseWeld", primary, part
				internal:SetAttribute("EclipseHelperWeld", true)
				internal.Parent = primary
				connect(primary, part)
			end
			part.Anchored = false
		end

		if animatable then
			local motor = Instance.new("Motor6D")
			motor.Name, motor.Part0, motor.Part1 = primary.Name, anchor, primary
			motor.C0 = inPlace and anchor.CFrame:ToObjectSpace(primary.CFrame) or CFrame.identity
			motor:SetAttribute("EclipseHelperWeld", true)
			motor.Parent = anchor
		else
			local joint = Instance.new("WeldConstraint")
			joint.Name, joint.Part0, joint.Part1 = "EclipseWeld", anchor, primary
			joint:SetAttribute("EclipseHelperWeld", true)
			joint.Parent = anchor
		end
	end

	return #entries
end

function Weld.prepareTimeline(anchor, targets, inPlace, raw, rigs, root, animatable)
	animatable = animatable ~= false
	local entries = Weld.plan(anchor, targets)
	local owner
	for _, rig in rigs do
		if anchor == rig or anchor:IsDescendantOf(rig) then
			owner = rig
			break
		end
	end

	assert(owner, "Add the parent rig to the timeline first.")
	local incoming, links, ambiguous, parents = {}, {}, {}, {}
	local passive = {}
	for _, rig in rigs do
		for motor in require("RigTraversal").passiveMotors(rig) do
			passive[motor] = true
		end
	end

	for _, object in require("RigTraversal").descendants(root) do
		if object:IsA("Motor6D") and object.Part1 and object.Part0 and not passive[object] then
			if incoming[object.Part1] then
				ambiguous[object.Part1] = true
			end

			incoming[object.Part1] = object
		elseif object:IsA("JointInstance") or object:IsA("WeldConstraint") then
			table.insert(links, object)
		end

		if (object:IsA("JointInstance") or object:IsA("WeldConstraint")) and object.Part0 and object.Part1 then
			local parent, child = object.Part0, object.Part1
			if passive[object] then
				parent, child = child, parent
			end
			parents[child] = parents[child] or {}
			parents[child][parent] = true
		end
	end

	local proposed = {}
	for _, entry in entries do
		proposed[entry.primary] = anchor
	end

	for _, entry in entries do
		assert(not ambiguous[entry.primary], "The selected child has multiple motors.")
		assert(
			animatable or not incoming[entry.primary] and not raw.MotorByPart[entry.primary],
			"This target already has an animation joint. Keep Animatable joint enabled to preserve its tracks."
		)
		local seen, pending = {}, { anchor }
		while #pending > 0 do
			local part = table.remove(pending)
			assert(part ~= entry.primary, "This binding would create a joint cycle.")
			assert(not ambiguous[part], "The parent chain has multiple motors.")
			if not seen[part] then
				seen[part] = true
				if proposed[part] then
					table.insert(pending, proposed[part])
				else
					for parent in parents[part] or {} do
						table.insert(pending, parent)
					end
				end
			end
		end

		local mapped = raw.MotorByPart[entry.primary]
		assert(
			not mapped or typeof(mapped) == "Instance" and mapped:IsA("Motor6D"),
			"Use the armature's parenting controls for this control."
		)
	end

	local transaction = { entries = entries, owner = owner }
	local records, detached, internal = {}, {}, {}
	for _, entry in entries do
		local part = entry.primary
		local motor = incoming[part]
		local created = not motor
		if created then
			motor = Instance.new(animatable and "Motor6D" or "Weld")
			motor.Name = part.Name
			motor.Part0 = anchor
			motor.Part1 = part
			motor:SetAttribute("EclipseHelperWeld", true)
			if not animatable then
				motor:SetAttribute("EclipseAccessoryLink", true)
			end
		end

		local record = {
			motor = motor,
			created = created,
			register = animatable and raw.DefaultPose[motor] == nil,
			previousMap = raw.MotorByPart[part],
			parent = motor.Parent,
			p0 = motor.Part0,
			c0 = motor.C0,
			c1 = motor.C1,
			transform = animatable and motor.Transform or nil,
			world = part.CFrame,
			anchored = {},
			worlds = {},
		}
		record.nextC1 = inPlace and part.CFrame:Inverse() * anchor.CFrame * motor.C0 or motor.C0
		for _, body in entry.parts do
			record.anchored[body] = body.Anchored
			record.worlds[body] = body.CFrame
		end

		local groups = {}
		for _, body in entry.parts do
			groups[body] = body
		end

		local function find(body)
			while groups[body] ~= body do
				body = groups[body]
			end

			return body
		end

		local function connect(a, b)
			if groups[a] and groups[b] then
				groups[find(b)] = find(a)
			end
		end

		for _, joint in incoming do
			connect(joint.Part0, joint.Part1)
		end

		for _, joint in links do
			connect(joint.Part0, joint.Part1)
		end

		for _, body in entry.parts do
			if find(body) ~= find(part) then
				local joint = Instance.new("Weld")
				joint.Name = "EclipseWeld"
				joint.Part0 = part
				joint.Part1 = body
				joint.C0 = part.CFrame:ToObjectSpace(body.CFrame)
				joint:SetAttribute("EclipseHelperWeld", true)
				joint:SetAttribute("EclipseAccessoryLink", true)
				internal[#internal + 1] = joint
				connect(part, body)
			end
		end

		records[#records + 1] = record
		for _, joint in links do
			local other = joint.Part0 == part and joint.Part1 or joint.Part1 == part and joint.Part0

			if
				other
				and not table.find(entry.parts, other)
				and (joint.Part1 == part or other == anchor)
			then
				detached[joint] = joint.Parent
			end
		end
	end

	local fields = {
		"DefaultPose",
		"DefaultWorldPose",
		"ParentingDefaults",
		"_motorUniform",
		"_motorHasScale",
		"Keyframes",
	}
	local snapshots = {}

	function transaction.apply(enabled)
		for _, joint in internal do
			joint.Parent = enabled and anchor or nil
		end

		for joint, parent in detached do
			joint.Parent = if enabled then nil else parent
		end

		for _, record in records do
			local motor = record.motor
			local part = motor.Part1
			if enabled then
				motor.Part0 = anchor
				motor.C1 = record.nextC1
				if animatable then
					motor.Transform = CFrame.identity
				end
				motor.Parent = record.created and anchor or record.parent
				for body in record.anchored do
					body.Anchored = false
				end

				if animatable then
					raw.MotorByPart[part] = motor
				end
				if record.register then
					if snapshots[motor] then
						for field, values in snapshots[motor] do
							for key, value in values do
								raw[field][key] = value
							end
						end
					else
						raw.DefaultPose[motor] = motor.C0
						raw.DefaultWorldPose[motor] = inPlace and record.world or anchor.CFrame
						raw.ParentingDefaults[motor] = true
						raw.MotorByPart[part] = motor
						motor:SetAttribute("EclipseAnimatorDefaultC0", motor.C0)
						motor:SetAttribute("EclipseParentingDefault", true)
					end
				end
			else
				if record.register then
					local saved = {}
					snapshots[motor] = saved
					for _, field in fields do
						local values = {}
						saved[field] = values
						if raw[field] and raw[field][motor] ~= nil then
							values[motor] = raw[field][motor]
							raw[field][motor] = nil
						end
					end
				end

				if animatable then
					raw.MotorByPart[part] = record.previousMap
				end
				if record.created then
					motor.Parent = nil
				else
					motor.Part0 = record.p0
					motor.C0 = record.c0
					motor.C1 = record.c1
					motor.Transform = record.transform
				end

				for body, anchored in record.anchored do
					body.Anchored = anchored
					body.CFrame = record.worlds[body]
				end
			end
		end
	end

	transaction.records = records
	return transaction
end

return Weld
