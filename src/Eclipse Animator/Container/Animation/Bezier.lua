--!nocheck
--!native
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Bezier = {}

local AUTO_HANDLE_LENGTH = 1 / 2.5614

function Bezier.parameter(alpha, x1, x2)
	if alpha <= 0 then
		return 0
	end

	if alpha >= 1 then
		return 1
	end

	x1, x2 = math.clamp(x1, 0, 1), math.clamp(x2, 0, 1)
	local lo, hi, u = 0, 1, alpha
	for _ = 1, 32 do
		local v = 1 - u
		local x = 3 * v * v * u * x1 + 3 * v * u * u * x2 + u * u * u
		local delta = x - alpha
		if math.abs(delta) <= 1e-9 then
			break
		end

		if delta < 0 then
			lo = u
		else
			hi = u
		end

		local derivative = 3 * v * v * x1 + 6 * v * u * (x2 - x1) + 3 * u * u * (1 - x2)
		local candidate = derivative > 1e-9 and u - delta / derivative or -1
		u = candidate > lo and candidate < hi and candidate or (lo + hi) * 0.5
	end

	return u
end

function Bezier.cubic(a, b, c, d, u)
	local v = 1 - u
	return a * (v * v * v) + b * (3 * v * v * u) + c * (3 * v * u * u) + d * (u * u * u)
end

function Bezier.lengths(previousTime, time, nextTime, handle)
	local left = previousTime and time - previousTime or nextTime - time
	local right = nextTime and nextTime - time or time - previousTime
	if handle == "Vector" then
		return left / 3, right / 3
	end

	return math.min(left, right * 5) * AUTO_HANDLE_LENGTH,
		math.min(right, left * 5) * AUTO_HANDLE_LENGTH
end

function Bezier.handles(
	previous,
	value,
	following,
	previousTime,
	time,
	nextTime,
	leftLength,
	rightLength,
	handle
)
	if handle == "Vector" then
		local leftSlope = previous ~= nil and (value - previous) / (time - previousTime)
			or (following - value) / (nextTime - time)
		local rightSlope = following ~= nil and (following - value) / (nextTime - time) or leftSlope
		return value - leftSlope * leftLength, value + rightSlope * rightLength
	end

	local slope = 0
	if previous ~= nil and following ~= nil then
		local leftDelta, rightDelta = value - previous, following - value
		slope = 0.5 * (leftDelta / (time - previousTime) + rightDelta / (nextTime - time))
		if handle == "AutoClamped" then
			if leftDelta * rightDelta <= 0 then
				slope = 0
			else
				local limit =
					math.min(math.abs(leftDelta) / leftLength, math.abs(rightDelta) / rightLength)
				slope = math.sign(slope) * math.min(math.abs(slope), limit)
			end
		end
	end

	return value - slope * leftLength, value + slope * rightLength
end

return Bezier
