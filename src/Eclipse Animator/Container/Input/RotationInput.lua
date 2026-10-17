--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RotationInput = {}
local CENTER_RADIUS = 6

function RotationInput.begin(center, mouse)
	local vector = mouse - center
	return {
		center = center,
		mouse = mouse,
		vector = vector.Magnitude > CENTER_RADIUS and vector or nil,
		angle = 0,
	}
end

function RotationInput.advance(state, mouse)
	if mouse == state.mouse then
		return state.angle, false
	end

	state.mouse = mouse
	local vector = mouse - state.center
	if vector.Magnitude <= CENTER_RADIUS then
		state.vector = nil
		return state.angle, false
	end

	local previous = state.vector
	state.vector = vector
	if not previous then
		return state.angle, false
	end

	local segment = vector - previous
	local distanceSquared = segment:Dot(segment)
	if distanceSquared > 0 then
		local alpha = math.clamp(-previous:Dot(segment) / distanceSquared, 0, 1)
		if (previous + segment * alpha).Magnitude <= CENTER_RADIUS then
			return state.angle, false
		end
	end

	local angle = math.atan2(previous.X * vector.Y - previous.Y * vector.X, previous:Dot(vector))
	state.angle += angle
	return state.angle, angle ~= 0
end

return RotationInput
