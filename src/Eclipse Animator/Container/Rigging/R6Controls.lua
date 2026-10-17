--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local R6Controls = {}
const CONTROL_NAMES = {
	root = "IK",
	spine = "Spine",
	upper = "UpperTorso",
	target = "IKTarget",
	pole = "IKPole",
	roll = "FootRoll",
}
const BASE_NAMES = {}
for _, base in CONTROL_NAMES do
	BASE_NAMES[base] = true
end

function R6Controls.resolveOwner(value)
	if typeof(value) == "Instance" and value:IsA("Bone") then
		return require("BoneMotor").get(value)
	end

	return value
end

function R6Controls.ownerInstance(owner)
	return typeof(owner) == "table" and owner.Bone or owner
end

local cache = setmetatable({}, { __mode = "k" })
local revisions = setmetatable({}, { __mode = "k" })

function R6Controls.revision(rig)
	return revisions[rig] or 0
end

function R6Controls.isControl(bone)
	return bone and bone:IsA("Bone") and typeof(bone:GetAttribute("EclipseR6Control")) == "string"
end

function R6Controls.isR15(owner)
	return owner
		and owner.Part1
		and (
			owner:GetAttribute("EclipseAutoIK") == true
			or owner.Part1.Name == "LeftHand"
			or owner.Part1.Name == "RightHand"
			or owner.Part1.Name == "LeftFoot"
			or owner.Part1.Name == "RightFoot"
		)
end

local customAnchors = setmetatable({}, { __mode = "k" })
local controlRigs = setmetatable({}, { __mode = "kv" })

function R6Controls.rememberRig(owner, rig)
	controlRigs[owner] = rig
end

local r15Anchors = setmetatable({}, { __mode = "k" })

local function frozenAnchor(body, root, bone, rig)
	local offset = bone:GetAttribute("EclipseIKAnchorOffset")
	if typeof(offset) ~= "CFrame" then
		local map = require("Parenting").buildMotorMap(require("Parenting").collectMotors(rig))
		local parent = map[typeof(body) == "table" and body.RealInstance or body]
		local world = parent and require("Parenting").worldOf(parent, map) or body.CFrame
		offset = root.CFrame:ToObjectSpace(world)
		bone:SetAttribute("EclipseIKAnchorOffset", offset)
	end

	local proxy = customAnchors[bone]
	if not proxy or proxy.AnchorRoot ~= root then
		proxy = setmetatable({ AnchorRoot = root }, {
			__index = function(_, key)
				if key == "CFrame" then
					return root.CFrame * bone:GetAttribute("EclipseIKAnchorOffset")
				end

				if key == "AnchorOffset" then
					return bone:GetAttribute("EclipseIKAnchorOffset")
				end

				if key == "RealInstance" then
					return nil
				end

				if key == "IsA" then
					return function(_, class)
						return root:IsA(class)
					end
				end

				if key == "IsDescendantOf" then
					return function(_, object)
						return root:IsDescendantOf(object)
					end
				end

				if key == "GetFullName" then
					return function()
						return root:GetFullName()
					end
				end

				return root[key]
			end,
		})
		customAnchors[bone] = proxy
	end

	return proxy
end

function R6Controls.rigRoot(rig, body)
	local root = rig and rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	local source = typeof(body) == "table" and body.RealInstance or body
	local ancestor = source and source.Parent
	while ancestor and ancestor ~= rig do
		if rig and not ancestor:IsDescendantOf(rig) then
			break
		end

		if ancestor:IsA("Model") then
			root = ancestor:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root
			end
		end

		ancestor = ancestor.Parent
	end

	return nil
end

local function customRoot(rig, body, map)
	if not rig then
		return nil
	end

	local source = typeof(body) == "table" and body.RealInstance or body
	if typeof(source) ~= "Instance" then
		return nil
	end

	if source:IsA("Bone") then
		source = source:FindFirstAncestorWhichIsA("BasePart")
	end

	if not source or not source:IsA("BasePart") or not source:IsDescendantOf(rig) then
		return nil
	end

	if not map then
		map = require("customRest").index(require("RigTraversal").rigDescendants(rig))
	end

	local seen = {}
	while map[source] do
		if seen[source] then
			return nil
		end

		seen[source] = true
		local motor = map[source]
		if typeof(motor) == "table" and motor.IsEclipseMasterControl then
			break
		end

		local parent = require("Parenting").realPart0(motor)
		if
			typeof(parent) ~= "Instance"
			or not parent:IsA("BasePart")
			or not parent:IsDescendantOf(rig)
		then
			return nil
		end

		source = parent
	end

	return source ~= body and source or nil
end

function R6Controls.anchor(owner, kind)
	if owner and owner:GetAttribute("EclipseAutoIK") == true then
		local body, rig, map = require("LimbIK").cachedCustomAnchor(owner)
		rig = rig or owner.Part1:FindFirstAncestorWhichIsA("Model")
		while not body and rig do
			local members =
				require("customRest").chain(rig, owner, require("Parenting").collectMotors(rig))
			if members then
				body = body or members[1].Part0
				break
			end

			rig = rig:FindFirstAncestorWhichIsA("Model")
		end

		body = body or owner.Part0
		local context = controlRigs[owner]
		if context and context.Parent and owner.Part1:IsDescendantOf(context) then
			rig = context
		end

		local root = R6Controls.rigRoot(rig, body)
		local generic = not root
		root = root or customRoot(rig, body, map)
		if kind == "root" or not root then
			return body
		end

		local bone = R6Controls.find(owner, kind)
		local space = bone and bone:GetAttribute("EclipseIKControlSpace")
		if generic and bone and space ~= 4 then
			return frozenAnchor(body, root, bone, rig)
		end

		if not bone or space == 3 or space == 4 then
			return root
		end

		if
			bone:GetAttribute("EclipseIKControlSpace") == 2
			and rig:FindFirstChild("HumanoidRootPart") == root
		then
			return root
		end

		return frozenAnchor(body, root, bone, rig)
	end

	if not R6Controls.isR15(owner) then
		return owner and owner.Part0
	end

	local body, rig = require("LimbIK").cachedControlAnchor(owner)
	if not body then
		local saved = r15Anchors[owner]
		if
			saved
			and saved.rig.Parent
			and owner.Part1:IsDescendantOf(saved.rig)
			and saved.upper.Parent
			and saved.lower.Parent
			and saved.lower.Part1 == owner.Part0
			and saved.upper.Part1 == saved.lower.Part0
			and saved.upper.Part0 == saved.body
			and saved.body:IsDescendantOf(saved.rig)
		then
			body, rig = saved.body, saved.rig
		else
			local ancestor = owner.Part1.Parent
			while ancestor and ancestor ~= workspace do
				if ancestor:IsA("Model") then
					local byPart = {}
					for _, motor in require("RigTraversal").rigDescendants(ancestor) do
						if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
							byPart[motor.Part1] = motor
						end
					end

					local lower = byPart[owner.Part0]
					local upper = lower and byPart[lower.Part0]
					if upper and upper.Part0:IsDescendantOf(ancestor) then
						local root = ancestor:FindFirstChild("HumanoidRootPart")
						if not body or root then
							body, rig = upper.Part0, ancestor
							r15Anchors[owner] =
								{ upper = upper, lower = lower, body = body, rig = rig }
						end

						if root then
							break
						end
					end
				end

				ancestor = ancestor.Parent
			end
		end
	end

	if not body then
		return owner.Part0
	end

	local context = controlRigs[owner]
	if
		context
		and context.Parent
		and body:IsDescendantOf(context)
		and owner.Part1:IsDescendantOf(context)
	then
		rig = context
	end

	if kind == "root" then
		return body
	end

	local root = R6Controls.rigRoot(rig, body) or body
	local bone = R6Controls.find(owner, kind)
	if not bone or bone:GetAttribute("EclipseIKControlSpace") == 3 then
		return root
	end

	if bone:GetAttribute("EclipseIKControlSpace") == 2 then
		local previous = rig:FindFirstChild("HumanoidRootPart") or body
		if previous == root then
			return root
		end

		return frozenAnchor(previous, root, bone, rig)
	end

	local legacy = owner.Part1.Parent:FindFirstChild("HumanoidRootPart") or owner.Part0
	if legacy == root then
		return root
	end

	return frozenAnchor(legacy, root, bone, rig)
end

function R6Controls.isLegPole(owner, kind)
	return kind == "pole"
		and owner
		and owner.Part1
		and (owner.Part1.Name == "Left Leg" or owner.Part1.Name == "Right Leg")
		and not (
			owner:GetAttribute("EclipseAutoIK") == true
			and not (owner.Part0 and owner.Part0.Name == "Torso")
		)
end

function R6Controls.visible(control)
	return not R6Controls.isLegPole(control.Owner, control:GetAttribute("EclipseR6Control"))
		or require("Preferences").get("R6IKLegPole") ~= false
end

function R6Controls.label(bone)
	local reference = bone and bone:FindFirstChild("EclipseR6Owner")
	local owner = reference and R6Controls.resolveOwner(reference.Value)
	if not owner or not owner.Part1 then
		return bone and bone.Name or "IK"
	end

	local kind = bone:GetAttribute("EclipseR6Control")
	if owner:GetAttribute("EclipseAutoIK") == true then
		return owner.Part1.Name
			.. (({ target = " IK", pole = " Pole", root = " Root" })[kind] or " Control")
	end

	if R6Controls.isR15(owner) then
		local side = owner.Part1.Name:sub(1, 4) == "Left" and "Left" or "Right"
		local arm = owner.Part1.Name:find("Hand", 1, true) ~= nil
		if kind == "target" then
			return side .. (arm and " Hand IK" or " Foot IK")
		end

		if kind == "pole" then
			return side .. (arm and " Elbow Pole" or " Knee Pole")
		end

		if kind == "roll" then
			return side .. " Foot Roll"
		end

		return side .. (arm and " Shoulder Control" or " Hip Control")
	end

	if R6Controls.isLegPole(owner, kind) then
		return owner.Part1.Name .. " Pole"
	end

	return owner.Part1.Name
		.. (kind == "root" and " IK" or kind == "spine" and " Spine" or " Upper Torso")
end

function R6Controls.find(owner, kind)
	for _, child in owner.Part1:GetChildren() do
		if R6Controls.isControl(child) and child:GetAttribute("EclipseR6Control") == kind then
			return child
		end
	end
end

function R6Controls.controlName(owner, kind)
	return owner.Part1.Name .. "_" .. (CONTROL_NAMES[kind] or kind)
end

function R6Controls.baseName(parentName, name)
	if type(name) ~= "string" then
		return nil
	end

	if BASE_NAMES[name] then
		return name
	end

	const prefix = tostring(parentName) .. "_"
	if #name > #prefix and name:sub(1, #prefix) == prefix and BASE_NAMES[name:sub(#prefix + 1)] then
		return name:sub(#prefix + 1)
	end

	return nil
end

function R6Controls.findNamed(parent, name, index)
	if typeof(parent) ~= "Instance" then
		return nil
	end

	const base = R6Controls.baseName(parent.Name, name)
	if not base then
		return nil
	end

	const wanted = type(index) == "number" and index >= 1 and index or 1
	local count = 0
	for _, child in parent:GetChildren() do
		if not child:IsA("Bone") then
			continue
		end

		const kind = R6Controls.isControl(child) and child:GetAttribute("EclipseR6Control")
		if (kind and (CONTROL_NAMES[kind] or kind) or R6Controls.baseName(parent.Name, child.Name)) == base then
			count += 1
			if count == wanted then
				return child
			end
		end
	end

	return nil
end

local function applyName(owner, bone, kind)
	const name = R6Controls.controlName(owner, kind)
	if bone.Name ~= name then
		const taken = owner.Part1:FindFirstChild(name)
		if not taken or taken == bone then
			bone.Name = name
		end
	end
end

function R6Controls.ensure(owner, kind, relative)
	local bone = R6Controls.find(owner, kind)
	if bone then
		applyName(owner, bone, kind)
		require("rig").shareR6Control(owner, bone)
		return bone
	end

	bone = Instance.new("Bone")
	bone.Name = R6Controls.controlName(owner, kind)
	bone.CFrame = relative
	bone:SetAttribute("EclipseR6Control", kind)
	if R6Controls.isR15(owner) then
		bone:SetAttribute(
			"EclipseIKControlSpace",
			owner:GetAttribute("EclipseAutoIK") == true and 4 or 3
		)
	end

	bone:SetAttribute("TrackParent", true)
	local reference = Instance.new("ObjectValue")
	reference.Name, reference.Value, reference.Parent =
		"EclipseR6Owner", R6Controls.ownerInstance(owner), bone
	bone.Parent = owner.Part1
	local ancestor = owner.Part1.Parent
	while ancestor do
		if ancestor:IsA("Model") then
			revisions[ancestor] = R6Controls.revision(ancestor) + 1
		end

		ancestor = ancestor.Parent
	end

	require("rig").shareR6Control(owner, bone)
	return bone
end

function R6Controls.get(bone)
	if not R6Controls.isControl(bone) then
		return nil
	end

	if cache[bone] then
		return cache[bone]
	end

	local reference = bone:FindFirstChild("EclipseR6Owner")
	if not reference or not reference.Value then
		return nil
	end

	local adapter = setmetatable({}, {
		__index = function(_, key)
			local owner = R6Controls.resolveOwner(reference.Value)
			if key == "C0" then
				return bone.CFrame * bone.Transform
			elseif key == "C1" then
				return CFrame.identity
			elseif key == "Part0" or key == "RealPart0" then
				local anchor = R6Controls.anchor(owner, bone:GetAttribute("EclipseR6Control"))
				return key == "RealPart0" and typeof(anchor) == "table" and anchor.RealInstance
					or anchor
			elseif key == "Part1" or key == "Bone" then
				return bone
			elseif key == "Owner" then
				return owner
			elseif key == "Parent" then
				return bone.Parent
			elseif key == "Name" then
				return bone.Name
			elseif
				key == "IsEclipseR6Control"
				or key == "IsEclipseBoneMotor"
				or key == "Enabled"
			then
				return true
			elseif key == "IsFootRelativePole" then
				return R6Controls.isLegPole(owner, bone:GetAttribute("EclipseR6Control"))
			elseif key == "IsTranslationOnly" then
				return bone:GetAttribute("EclipseR6Control") == "root"
					or bone:GetAttribute("EclipseR6Control") == "pole"
			elseif key == "IsA" then
				return function(_, class)
					return class == "Motor6D" or class == "JointInstance"
				end
			elseif key == "GetAttribute" then
				return function(_, attr)
					if attr == "TrackParent" then
						return true
					end

					return bone:GetAttribute(attr)
				end
			elseif key == "SetAttribute" then
				return function(_, attr, value)
					if attr ~= "TrackParent" then
						bone:SetAttribute(attr, value)
					end
				end
			elseif key == "GetAttributes" then
				return function()
					return bone:GetAttributes()
				end
			elseif key == "GetFullName" then
				return function()
					return bone:GetFullName()
				end
			end
		end,
		__newindex = function(_, key, value)
			if key == "C0" then
				bone.Transform = bone.CFrame:Inverse() * value
			end
		end,
	})
	cache[bone] = adapter
	local owner = R6Controls.resolveOwner(reference.Value)
	if
		owner:GetAttribute("EclipseAutoIK") == true
		and bone:GetAttribute("EclipseIKControlSpace") ~= 4
	then
		R6Controls.anchor(owner, bone:GetAttribute("EclipseR6Control"))
	end

	return adapter
end

function R6Controls.forOwner(owner)
	local list = {}
	for _, child in owner.Part1:GetChildren() do
		local adapter = R6Controls.get(child)
		if adapter then
			table.insert(list, adapter)
		end
	end

	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function R6Controls.value(motor, defaults)
	return motor:GetAttribute("EclipseDisabled") and (defaults[motor] or motor.Bone.CFrame)
		or motor.C0
end

return R6Controls
