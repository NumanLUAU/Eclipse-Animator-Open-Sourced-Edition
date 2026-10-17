--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local SoftIK = {}

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function SoftIK.percent(value)
	value = tonumber(value)
	return finite(value) and math.clamp(value, 0, 100) or 90
end

function SoftIK.distance(distance, reach, percent)
	if not finite(reach) or reach <= 0 or not finite(distance) or distance <= 0 then
		return 0
	end

	local onset = reach * (SoftIK.percent(percent) / 100)
	if distance <= onset then
		return distance
	end

	local zone = reach - onset
	if zone <= 0 then
		return math.min(distance, reach)
	end

	local x = (distance - onset) / zone

	local eased = x < 1e-4 and x * (1 - x * 0.5 + x * x / 6 - x * x * x / 24) or 1 - math.exp(-x)
	return math.min(distance, reach, onset + zone * eased)
end

function SoftIK.goal(root, goal, reach, percent)
	local delta = goal - root
	local distance = delta.Magnitude
	if not finite(distance) or distance <= 0 then
		return root
	end

	return root + delta * (SoftIK.distance(distance, reach, percent) / distance)
end

return SoftIK
