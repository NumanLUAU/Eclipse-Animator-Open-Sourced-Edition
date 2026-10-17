--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Solver = require("LimbSolver")
local R6TorsoSolver = {}

function R6TorsoSolver.solve(base, height, spine, upper)
	local direction = upper.Position - spine.Position

	local reference = upper.Rotation
	local rotation = direction.Magnitude > 1e-6
			and Solver.rotationBetween(reference.UpVector, direction)
		or CFrame.identity
	return CFrame.new(spine.Position) * rotation * reference * CFrame.new(0, height * 0.5, 0)
end

function R6TorsoSolver.controlFrame(base, height, spine, upper, kind)
	local torso = R6TorsoSolver.solve(base, height, spine, upper)
	if kind == "spine" then
		return torso
	end

	return CFrame.new(upper.Position - torso.UpVector * 0.15) * torso.Rotation
end

function R6TorsoSolver.controlValue(base, height, spine, upper, kind, value)
	local direction = kind == "spine" and upper.Position - value.Position
		or value.Position - spine.Position
	local up = direction.Magnitude > 1e-6 and direction.Unit or base.UpVector
	local position = kind == "spine" and value.Position - up * height * 0.5
		or value.Position + up * 0.15
	return CFrame.new(position) * (kind == "spine" and spine.Rotation or upper.Rotation)
end

return R6TorsoSolver
