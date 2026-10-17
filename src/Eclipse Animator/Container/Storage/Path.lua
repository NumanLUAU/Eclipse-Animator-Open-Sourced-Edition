--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Timing = require("Timing")
local Path = {}

function Path.validate(strokes)
	assert(type(strokes) == "table", "Invalid drawing data")
	local count = 0
	for id, stroke in strokes do
		count += 1
		assert(count <= 1000 and type(id) == "string" and type(stroke) == "table", "Invalid stroke")
		assert(
			type(stroke.points) == "table" and #stroke.points >= 2 and #stroke.points <= 1024,
			"Invalid stroke points"
		)
		assert(
			type(stroke.smoothing) == "number" and stroke.smoothing >= 0 and stroke.smoothing <= 100,
			"Invalid smoothing"
		)
		for _, point in stroke.points do
			assert(
				typeof(point) == "Vector3"
					and point.Magnitude == point.Magnitude
					and point.Magnitude < 1e7,
				"Invalid stroke position"
			)
		end

		Timing.validate(stroke.easing)
		local length = 0
		for i = 2, #stroke.points do
			length += (stroke.points[i] - stroke.points[i - 1]).Magnitude
		end

		assert(length > 1e-5, "Draw a longer stroke")
	end

	return strokes
end

function Path.resample(points, count)
	assert(#points >= 2 and count >= 2, "Draw a longer stroke")
	local lengths = { 0 }
	for i = 2, #points do
		lengths[i] = lengths[i - 1] + (points[i] - points[i - 1]).Magnitude
	end

	local total = lengths[#points]
	assert(total > 1e-5, "Draw a longer stroke")
	local segment = 2
	local result = {}
	for i = 1, count do
		local distance = (i - 1) / (count - 1) * total
		while segment < #points and lengths[segment] < distance do
			segment += 1
		end

		local span = lengths[segment] - lengths[segment - 1]
		result[i] = points[segment - 1]:Lerp(
			points[segment],
			span > 1e-8 and (distance - lengths[segment - 1]) / span or 0
		)
	end

	result[1], result[count] = points[1], points[#points]
	return result
end

function Path.smooth(points, amount)
	assert(
		type(amount) == "number" and amount == amount and amount >= 0 and amount <= 100,
		"Smoothing must be 0–100"
	)
	if #points < 3 or amount == 0 then
		return table.clone(points)
	end

	local result = Path.resample(points, math.clamp(#points, 3, 256))
	local strength = amount / 100
	for _ = 1, math.ceil(strength * 8) do
		local nextPoints = table.clone(result)
		for i = 2, #result - 1 do
			nextPoints[i] = result[i]:Lerp((result[i - 1] + result[i + 1]) * 0.5, strength * 0.65)
		end

		result = nextPoints
	end

	return result
end

function Path.at(points, alpha)
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end

	local remaining = length * math.clamp(alpha, 0, 1)
	for i = 2, #points do
		local span = (points[i] - points[i - 1]).Magnitude
		if remaining <= span and span > 1e-8 then
			return points[i - 1]:Lerp(points[i], remaining / span)
		end

		remaining -= span
	end

	return points[#points]
end

function Path.sampler(points)
	local saved = table.clone(points)
	local lengths, spans = { 0 }, {}
	for i = 2, #saved do
		spans[i] = (saved[i] - saved[i - 1]).Magnitude
		lengths[i] = lengths[i - 1] + spans[i]
	end

	local total = lengths[#saved]
	return function(alpha)
		local distance = total * math.clamp(alpha, 0, 1)
		local low, high = 2, #saved
		while low < high do
			local middle = (low + high) // 2
			if lengths[middle] < distance then
				low = middle + 1
			else
				high = middle
			end
		end

		while low <= #saved and spans[low] <= 1e-8 do
			low += 1
		end

		if low > #saved then
			return saved[#saved]
		end

		return saved[low - 1]:Lerp(saved[low], (distance - lengths[low - 1]) / spans[low])
	end
end

function Path.intersect(ray, origin, normal)
	local dot = ray.Direction:Dot(normal)
	if math.abs(dot) < 1e-6 then
		return nil
	end

	local distance = (origin - ray.Origin):Dot(normal) / dot
	if distance <= 0 or distance > 100000 then
		return nil
	end

	return ray.Origin + ray.Direction * distance
end

function Path.localPose(parent, world, position, c1)
	return parent:Inverse() * (CFrame.new(position) * world.Rotation) * c1
end

return Path
