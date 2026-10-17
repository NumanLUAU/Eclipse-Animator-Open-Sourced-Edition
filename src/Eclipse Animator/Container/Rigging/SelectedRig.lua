--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Properties = require("Properties")
local Selection = game:GetService("Selection")
local Target = {}

function Target.resolve(state, fallback)
	local rigs = state.getAllRigs()

	local function owner(object)
		if typeof(object) ~= "Instance" then
			return nil
		end

		local propertyOwner = Properties.owner(object)
		if propertyOwner and table.find(rigs, propertyOwner) then
			return propertyOwner
		end

		local current = object
		while current do
			local source = current:FindFirstChild("EclipseSourceRig")
			if source and source:IsA("ObjectValue") and table.find(rigs, source.Value) then
				return source.Value
			end

			current = current.Parent
		end

		for _, rig in rigs do
			if rig.Parent and (object == rig or object:IsDescendantOf(rig)) then
				return rig
			end
		end
	end

	for _, object in Selection:Get() do
		local selected = owner(object)
		if selected then
			return selected
		end
	end

	local selected = owner(state.Axis and state.Axis:GetSelectedBone())
	if selected then
		return selected
	end

	local rig = state.Rig
	local item = rig and rig._lastClickedItem
	if item and rig._selectedItems and rig._selectedItems[item] then
		selected = owner(item.linkedRigInstance) or owner((item.grandpa or item).linkedRigInstance)
		if selected then
			return selected
		end
	end

	if fallback ~= false then
		return state.currentRig
	end
end

return Target
