--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

return function(object: Model, requested: string?)
	if not object or not object:IsA("Model") then
		return {}
	end

	require("NativeJoints").prepare(object)
	local map = require("RigTraversal").jointMap(object, requested)
	local motors, bones = false, false
	for _, v in map do
		if v:IsA("Motor6D") then
			motors = true
		else
			bones = true
		end
	end

	return map, motors and "Motor6D" or bones and "Bone" or "Motor6D"
end
