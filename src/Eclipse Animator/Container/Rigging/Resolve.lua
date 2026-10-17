--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Selection = {}

function Selection.resolve(rigs, selected, items)
	if #rigs == 1 then
		return rigs[1]
	end

	local chosen = {}

	local function collect(part)
		if typeof(part) ~= "Instance" then
			return
		end

		local reference = part.Parent and part.Parent:FindFirstChild("EclipseSourceRig")
		if reference and reference:IsA("ObjectValue") then
			part = reference.Value
		end

		for _, rig in rigs do
			if part == rig or part and part:IsDescendantOf(rig) then
				chosen[rig] = true
			end
		end
	end

	for _, part in selected do
		collect(part)
	end

	if next(chosen) == nil then
		for item, enabled in items or {} do
			if enabled then
				collect((item.grandpa or item).linkedRigInstance)
			end
		end
	end

	local rig
	for candidate in chosen do
		if rig then
			return nil
		end

		rig = candidate
	end

	return rig
end

return Selection
