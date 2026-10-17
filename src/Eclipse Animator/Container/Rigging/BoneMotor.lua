--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")
local BoneMotor = {}

local BoneIK = require("BoneIK")
local R6Controls = require("R6Controls")
local ArmatureRuntime = require("ArmatureRuntime")

local cache = setmetatable({}, { __mode = "k" })
local ikCache = setmetatable({}, { __mode = "k" })
local part0Cache = setmetatable({}, { __mode = "k" })

local function getPart0Proxy(parent)
	local existing = part0Cache[parent]
	if existing then
		return existing
	end

	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "CFrame" then
				if parent:IsA("Bone") then
					return BoneIK.worldOf(parent)
				end

				return parent.CFrame
			elseif key == "RealInstance" then
				return parent
			elseif key == "IsA" then
				return function(_, className)
					return parent:IsA(className)
				end
			elseif key == "GetAttribute" then
				return function(_, attr)
					return parent:GetAttribute(attr)
				end
			elseif key == "GetFullName" then
				return function()
					return parent:GetFullName()
				end
			elseif key == "Name" then
				return parent.Name
			elseif key == "Parent" then
				return parent.Parent
			end

			return nil
		end,
	})
	part0Cache[parent] = proxy
	return proxy
end

local adapterMeta = {
	__index = function(self, key)
		local bone = rawget(self, "_bone")
		if key == "C0" then
			return bone.CFrame * bone.Transform
		elseif key == "C1" then
			return CFrame.identity
		elseif key == "Part1" then
			return bone
		elseif key == "Part0" then
			local p = bone.Parent
			return p and getPart0Proxy(p) or nil
		elseif key == "RealPart0" then
			return bone.Parent
		elseif key == "Parent" then
			return bone.Parent
		elseif key == "Name" then
			return bone.Name
		elseif key == "Enabled" then
			return true
		elseif key == "Bone" then
			return bone
		elseif key == "IsEclipseBoneMotor" then
			return true
		elseif key == "IsA" then
			return function(_, className)
				return className == "Motor6D" or className == "JointInstance"
			end
		elseif key == "GetAttribute" then
			return function(_, attr)
				return bone:GetAttribute(attr)
			end
		elseif key == "SetAttribute" then
			return function(_, attr, value)
				bone:SetAttribute(attr, value)
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

		return nil
	end,
	__newindex = function(self, key, value)
		local bone = rawget(self, "_bone")
		if key == "C0" then
			bone.Transform = bone.CFrame:Inverse() * value
		end
	end,
}

function BoneMotor.get(bone)
	if R6Controls.isControl(bone) then
		return R6Controls.get(bone)
	end

	if not bone or not bone:IsA("Bone") or bone:GetAttribute("EclipseArmatureSkinningHelper") then
		return nil
	end

	local existing = cache[bone]
	if existing then
		return existing
	end

	local adapter = setmetatable({ _bone = bone }, adapterMeta)
	cache[bone] = adapter
	return adapter
end

function BoneMotor.isAdapter(motor)
	return typeof(motor) == "table"
		and (
			rawget(motor, "_bone") ~= nil
			or motor.IsEclipseR6Control == true
			or motor.IsEclipseArmatureControl == true
		)
end

local ikRootPart0 = setmetatable({}, {
	__index = function(_, key)
		if key == "CFrame" then
			return CFrame.identity
		elseif key == "Name" then
			return "IKRoot"
		elseif key == "IsA" then
			return function(_, className)
				return className == "BasePart"
			end
		end

		return nil
	end,
})

local ikMeta = {
	__index = function(self, key)
		local anchor = rawget(self, "_anchor")
		if key == "C0" then
			return anchor.CFrame
		elseif key == "C1" then
			return CFrame.identity
		elseif key == "Part0" then
			return ikRootPart0
		elseif key == "Part1" then
			return rawget(self, "_joint") or anchor
		elseif key == "RealPart0" then
			return nil
		elseif key == "Parent" then
			return anchor.Parent
		elseif key == "Name" then
			return anchor.Name
		elseif key == "Enabled" then
			return true
		elseif key == "IsEclipseIKHandle" then
			return true
		elseif key == "IsA" then
			return function(_, className)
				return className == "Motor6D" or className == "JointInstance"
			end
		elseif key == "GetAttribute" then
			return function(_, attr)
				return anchor:GetAttribute(attr)
			end
		elseif key == "SetAttribute" then
			return function(_, attr, value)
				anchor:SetAttribute(attr, value)
			end
		elseif key == "GetFullName" then
			return function()
				return anchor:GetFullName()
			end
		end

		return nil
	end,
	__newindex = function(self, key, value)
		if key == "C0" then
			local anchor = rawget(self, "_anchor")
			anchor.CFrame = value
			local rig = rawget(self, "_rig")
			if rig then
				BoneIK.solveForAnchor(anchor, rig)
				local followName = anchor:GetAttribute("EclipseFollowBone")
				if typeof(followName) == "string" then
					local followBone = rawget(self, "_followBone")
					if not (followBone and followBone.Parent and followBone.Name == followName) then
						followBone = nil
						for _, d in ipairs(RigTraversal.rigDescendants(rig)) do
							if
								d:IsA("Bone")
								and not d:GetAttribute("EclipseArmatureSkinningHelper")
								and d.Name == followName
							then
								followBone = d
								break
							end
						end

						rawset(self, "_followBone", followBone)
					end

					if followBone then
						anchor:SetAttribute(
							"EclipseFollowOffset",
							BoneIK.worldOf(followBone):Inverse() * value
						)
					end
				end
			end
		end
	end,
}

function BoneMotor.getIKHandle(anchor, rig, joint)
	if ArmatureRuntime.isAnchor(anchor) then
		return ArmatureRuntime.get(anchor, rig, joint)
	end

	if not anchor then
		return nil
	end

	BoneIK.prepareAnchor(anchor, rig)
	local adapter = ikCache[anchor]
	if not adapter then
		adapter = setmetatable({ _anchor = anchor }, ikMeta)
		ikCache[anchor] = adapter
	end

	rawset(adapter, "_rig", rig)
	rawset(adapter, "_joint", joint)
	return adapter
end

return BoneMotor
