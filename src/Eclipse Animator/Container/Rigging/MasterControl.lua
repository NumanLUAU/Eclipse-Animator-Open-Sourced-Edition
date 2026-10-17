--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Master = {}
local cache = setmetatable({}, { __mode = "k" })
local roots = setmetatable({}, { __mode = "k" })
local Tree = require("RigTraversal")
local FLAG, REST, INPUT = "EclipseMasterControl", "EclipseMasterRest", "EclipseMasterInput"
const STAMP = "EclipseAnimatorDefaultC0"

function Master.root(rig)
	if not rig or not rig:IsA("Model") then
		return nil
	end

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	root = nil
	local existing = roots[rig]
	if existing and existing.primary == rig.PrimaryPart and existing.root:IsDescendantOf(rig) then
		return existing.root
	end

	local parts, incoming, outgoing = {}, {}, {}
	for _, object in Tree.rigDescendants(rig) do
		if object:IsA("Motor6D") then
			if object.Part1 then
				incoming[object.Part1] = true
			end

			if object.Part0 then
				outgoing[object.Part0] = true
			end
		elseif
			object:IsA("BasePart")
			and not object:GetAttribute("EclipseArmatureBone")
			and not object:GetAttribute("EclipseLimbControl")
			and not object:GetAttribute("EclipseMasterMarker")
		then
			table.insert(parts, object)
		end
	end

	table.sort(parts, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	for _, part in parts do
		if
			not incoming[part]
			and (not root or part == rig.PrimaryPart or outgoing[part] and not outgoing[root])
		then
			root = part
		end

		if root == rig.PrimaryPart then
			break
		end
	end

	if root and root:IsA("BasePart") then
		roots[rig] = { root = root, primary = rig.PrimaryPart }
		return root
	end

	return nil
end

function Master.enabled(rig)
	return rig ~= nil and rig:GetAttribute(FLAG) == true and Master.root(rig) ~= nil
end

function Master.get(rig, includeDisabled)
	if
		not rig
		or not rig:IsA("Model")
		or not includeDisabled and rig:GetAttribute(FLAG) ~= true
	then
		return nil
	end

	if typeof(rig:GetAttribute(REST)) ~= "CFrame" then
		return nil
	end

	local root = Master.root(rig)
	if not root or not includeDisabled and not Master.enabled(rig) then
		return nil
	end

	local rest = rig:GetAttribute(REST)
	if typeof(rest) ~= "CFrame" then
		return nil
	end

	local entry = cache[rig]
	if entry and entry.root == root then
		return entry.motor
	end

	local input = rig:GetAttribute(INPUT)
	input = typeof(input) == "CFrame" and input or rest
	local applied = Master.enabled(rig) and input * rest:Inverse() or CFrame.identity
	local movement = rig:GetAttribute("EclipseMasterMovement")
	if typeof(movement) ~= "CFrame" then
		movement = CFrame.identity
	end

	entry = {
		rig = rig,
		root = root,
		rest = rest,
		input = input,
		lastInput = input,
		base = root.CFrame * applied:Inverse(),
		last = root.CFrame,
		movement = movement,
		enabled = Master.enabled(rig),
	}

	if root:GetAttribute(STAMP) ~= nil then
		root:SetAttribute(STAMP, nil)
	end

	local function base()
		if entry.poseBase then
			return entry.poseBase
		end
		if root.CFrame ~= entry.last then
			entry.base = (root.CFrame * entry.last:Inverse() * entry.base):Orthonormalize()
			entry.last = root.CFrame
		end

		return entry.base
	end

	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "CFrame" then
				return base()
			elseif key == "Name" then
				return "MasterOrigin"
			elseif key == "IsA" then
				return function(_, class)
					return class == "BasePart"
				end
			end
		end,
	})
	entry.motor = setmetatable({}, {
		__index = function(_, key)
			if key == "C0" then
				return entry.input
			elseif key == "C1" or key == "DefaultC0" then
				return entry.rest
			elseif key == "Part0" then
				return proxy
			elseif key == "Part1" then
				return root
			elseif key == "Parent" then
				return rig
			elseif key == "Name" then
				return "Master Control"
			elseif key == "IsEclipseMasterControl" or key == "Enabled" then
				return true
			elseif key == "IsA" then
				return function(_, class)
					return class == "Motor6D" or class == "JointInstance"
				end
			elseif key == "GetAttribute" then
				return function(_, attr)
					if attr == "TrackParent" then
						return true
					elseif attr == STAMP then
						return entry.stamp
					end

					return root:GetAttribute(attr)
				end
			elseif key == "SetAttribute" then
				return function(_, attr, value)
					if attr == STAMP then
						entry.stamp = value
					elseif attr ~= "TrackParent" then
						root:SetAttribute(attr, value)
					end
				end
			elseif key == "GetAttributes" then
				return function()
					return root:GetAttributes()
				end
			elseif key == "GetFullName" then
				return function()
					return rig:GetFullName() .. ".Master Control"
				end
			end
		end,
		__newindex = function(_, key, value)
			if key ~= "C0" or typeof(value) ~= "CFrame" then
				return
			end

			for _, number in { value:GetComponents() } do
				if number ~= number or math.abs(number) == math.huge then
					return
				end
			end

			local enabled = Master.enabled(rig)
			if (value == entry.input or value == entry.lastInput) and enabled == entry.enabled then
				return
			end

			local origin = base()
			entry.input = value:Orthonormalize()
			entry.lastInput = value
			rig:SetAttribute(INPUT, entry.input)
			local desired = (
				origin * (enabled and entry.input * entry.rest:Inverse() or CFrame.identity)
			):Orthonormalize()
			if desired ~= root.CFrame then
				local delta = (desired * root.CFrame:Inverse()):Orthonormalize()
				rig:PivotTo((delta * rig:GetPivot()):Orthonormalize())
				entry.movement = (delta * entry.movement):Orthonormalize()
				rig:SetAttribute("EclipseMasterMovement", entry.movement)
			end

			entry.enabled = enabled
			entry.last = root.CFrame
		end,
	})
	cache[rig] = entry
	rig.Destroying:Once(function()
		cache[rig] = nil
	end)
	return entry.motor
end

function Master.withPose(rigs, callback)
	local captured = {}
	for _, rig in rigs do
		local motor = Master.get(rig)
		local entry = motor and cache[rig]
		if entry and not entry.poseBase then
			local origin = motor.Part0.CFrame
			entry.poseBase = origin
			table.insert(captured, entry)
		end
	end
	local result = table.pack(pcall(callback))
	local failure
	for _, entry in captured do
		local origin = entry.poseBase
		entry.poseBase = nil
		local ok, err = pcall(function()
			if not entry.rig.Parent or not entry.root:IsDescendantOf(entry.rig) then return end
			local desired = (origin * (Master.enabled(entry.rig)
				and entry.input * entry.rest:Inverse() or CFrame.identity)):Orthonormalize()
			if not entry.root.CFrame:FuzzyEq(desired, 1e-6) then
				local delta = desired * entry.root.CFrame:Inverse()
				entry.rig:PivotTo((delta * entry.rig:GetPivot()):Orthonormalize())
			end
			entry.base, entry.last = origin, entry.root.CFrame
		end)
		if not ok then failure = failure or err end
	end
	if not result[1] then error(result[2], 0) end
	if failure then error(failure, 0) end
	return table.unpack(result, 2, result.n)
end

function Master.capture(rig)
	local motor = Master.get(rig, true)
	if not motor then
		return nil
	end

	local origin = motor.Part0.CFrame
	local entry = cache[rig]
	return {
		root = entry.root,
		rest = entry.rest,
		input = entry.input,
		lastInput = entry.lastInput,
		base = origin,
		last = entry.last,
		movement = entry.movement,
		enabled = entry.enabled,
		storedInput = rig:GetAttribute(INPUT),
		storedMovement = rig:GetAttribute("EclipseMasterMovement"),
	}
end

function Master.restore(rig, snapshot)
	if not snapshot or not rig.Parent or Master.root(rig) ~= snapshot.root then
		return
	end

	local entry = cache[rig]
	if not entry or entry.root ~= snapshot.root then
		return
	end

	for _, field in { "rest", "input", "lastInput", "base", "last", "movement", "enabled" } do
		entry[field] = snapshot[field]
	end

	rig:SetAttribute(INPUT, snapshot.storedInput)
	rig:SetAttribute("EclipseMasterMovement", snapshot.storedMovement)
end

function Master.setEnabled(rig, enabled)
	local root = Master.root(rig)
	if not root then
		return nil
	end

	if typeof(rig:GetAttribute(REST)) ~= "CFrame" then
		local minimum, maximum
		local geometry = {}
		for _, part in Tree.rigDescendants(rig) do
			if
				part:IsA("BasePart")
				and not part:GetAttribute("EclipseArmatureBone")
				and not part:GetAttribute("EclipseLimbControl")
				and not part:GetAttribute("EclipseMasterMarker")
			then
				table.insert(geometry, part)
			end
		end

		for _, part in geometry do
			if part ~= root or #geometry == 1 then
				local half = part.Size * 0.5
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							local point = root.CFrame:PointToObjectSpace(
								part.CFrame:PointToWorldSpace(half * Vector3.new(x, y, z))
							)
							minimum = minimum and minimum:Min(point) or point
							maximum = maximum and maximum:Max(point) or point
						end
					end
				end
			end
		end

		local scale = rig:GetScale()
		local rest = CFrame.new(0, minimum and minimum.Y + 0.025 * scale or -3 * scale, 0)
		rig:SetAttribute(REST, rest)
		rig:SetAttribute(INPUT, rest)
		rig:SetAttribute(
			"EclipseMasterRadius",
			math.max(
				scale,
				maximum
						and math.max(
							math.abs(minimum.X),
							math.abs(maximum.X),
							math.abs(minimum.Z),
							math.abs(maximum.Z)
						) * 1.2
					or 2.4 * scale
			)
		)
	end

	local motor = Master.get(rig, true)
	local current = motor.C0
	rig:SetAttribute(FLAG, enabled == true)
	motor.C0 = current
	return motor
end

function Master.movement(rig)
	Master.get(rig, true)
	local entry = cache[rig]
	return entry and entry.movement or CFrame.identity
end

function Master.delta(rig)
	local motor = Master.get(rig)
	return motor and motor.C0 * motor.C1:Inverse() or CFrame.identity
end

function Master.exportRootDelta(rig, parent)
	local motor = Master.get(rig)
	if not motor then
		return CFrame.identity
	end

	local delta = Master.delta(rig)
	if parent == motor.Part1 then
		return delta
	end

	local origin = motor.Part0.CFrame
	local world = origin * delta * origin:Inverse()
	return parent.CFrame:Inverse() * world * parent.CFrame
end

function Master.worldDelta(motor, evaluate, time)
	if typeof(motor) == "table" and motor.IsEclipseMasterControl then
		return CFrame.identity
	end

	local rig = motor and motor.Part1
	while typeof(rig) == "Instance" and rig ~= workspace do
		if rig:IsA("Model") then
			local master = Master.get(rig)
			if master then
				local base = master.Part0.CFrame
				local value = evaluate and evaluate(master, time) or master.C0
				if value == master.C1 then
					return CFrame.identity
				end

				return base * value * master.C1:Inverse() * base:Inverse()
			end
		end

		rig = rig.Parent
	end

	return nil
end

local function markerRadius(rig, root)
	local body = {}
	local r6 = true
	for _, name in { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local part = rig:FindFirstChild(name)
		if not part or not part:IsA("BasePart") then
			r6 = false
			break
		end

		body[name] = part.Size
	end

	if r6 then
		local width = body.Torso.X + body["Left Arm"].X + body["Right Arm"].X
		local depth = 0
		for _, size in body do
			depth = math.max(depth, size.Z)
		end

		local height = body.Head.Y
			+ body.Torso.Y
			+ math.max(body["Left Leg"].Y, body["Right Leg"].Y)
		return math.max(0.025, math.max(width, depth) * 0.6, height * 0.1) * 0.8
	end

	local minimum, maximum
	for _, part in Tree.rigDescendants(rig) do
		if
			part:IsA("BasePart")
			and part ~= root
			and part.Transparency < 1
			and not part:GetAttribute("EclipseArmatureBone")
			and not part:GetAttribute("EclipseArmatureSkinningHelper")
			and not part:GetAttribute("EclipseAccessoryControlPart")
			and not part:GetAttribute("EclipseLimbControl")
			and not part:GetAttribute("EclipseMasterMarker")
		then
			local half = part.Size * 0.5
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = root.CFrame:PointToObjectSpace(
							part.CFrame:PointToWorldSpace(half * Vector3.new(x, y, z))
						)
						minimum = minimum and minimum:Min(point) or point
						maximum = maximum and maximum:Max(point) or point
					end
				end
			end
		end
	end

	minimum = minimum or -root.Size * 0.5
	maximum = maximum or root.Size * 0.5
	local extent =
		math.max(math.abs(minimum.X), math.abs(maximum.X), math.abs(minimum.Z), math.abs(maximum.Z))
	return math.max(0.025, extent * 1.2, (maximum.Y - minimum.Y) * 0.1) * 0.8
end

function Master.makeMarker(rig, folder)
	local motor = Master.get(rig)
	if not motor then
		return
	end

	local radius = markerRadius(rig, motor.Part1)
	local marker = Instance.new("Part")
	marker.Name = "MasterControl_Bone"
	marker.Size = Vector3.new(radius * 2, 0.08, radius * 2)
	marker.CFrame = motor.Part0.CFrame * motor.C0
	marker.Transparency, marker.Anchored, marker.Locked = 1, true, true
	marker.CanCollide, marker.CanTouch, marker.CanQuery, marker.CastShadow =
		false, false, true, false
	marker:SetAttribute("SourcePartName", motor.Part1.Name)
	marker:SetAttribute("EclipseMasterMarker", true)
	local reference = Instance.new("ObjectValue")
	reference.Name, reference.Value, reference.Parent = "EclipseSourcePart", motor.Part1, marker
	local wire = Instance.new("CylinderHandleAdornment")
	wire.Name = "MasterCircle"
	wire.Adornee, wire.AlwaysOnTop, wire.ZIndex = marker, true, 4
	wire.AdornCullingMode = Enum.AdornCullingMode.Never
	wire.CFrame = CFrame.Angles(math.pi / 2, 0, 0)
	wire.Radius, wire.InnerRadius, wire.Height = radius, math.max(0, radius - 0.025), 0.012
	wire.Color3, wire.Transparency = Color3.fromRGB(215, 225, 230), 0.08
	wire.Parent = marker
	marker.Parent = folder
	return marker
end

function Master.write(sequence, rig)
	local motor = Master.get(rig, true)
	if not motor then
		return
	end

	sequence:SetAttribute(FLAG, Master.enabled(rig))
	sequence:SetAttribute(REST, motor.DefaultC0)
	sequence:SetAttribute("EclipseMasterRadius", rig:GetAttribute("EclipseMasterRadius"))
end

function Master.read(sequence, rig)
	if not Master.root(rig) then
		return
	end

	local old = Master.get(rig, true)
	if old then
		old.C0 = old.DefaultC0
	end

	local rest = sequence:GetAttribute(REST)
	if typeof(rest) == "CFrame" then
		rig:SetAttribute(REST, rest)
		rig:SetAttribute(INPUT, rest)
		rig:SetAttribute("EclipseMasterRadius", sequence:GetAttribute("EclipseMasterRadius"))
	end

	rig:SetAttribute(FLAG, sequence:GetAttribute(FLAG) == true)
	local entry = cache[rig]
	if entry then
		entry.rest = rig:GetAttribute(REST) or entry.rest
		entry.input, entry.base, entry.last = entry.rest, entry.root.CFrame, entry.root.CFrame
		entry.enabled = Master.enabled(rig)
		entry.lastInput = entry.input
	end

	return Master.get(rig, true)
end

return Master
