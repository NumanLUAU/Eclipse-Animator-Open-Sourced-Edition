--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Curve = {}
local integrated = setmetatable({}, { __mode = "k" })

function Curve.new(mode)
	mode = mode or "Linear"
	return { mode = mode, points = { { 0, 0 }, { 1, 1 } } }
end

function Curve.copy(curve)
	if not curve then
		return Curve.new()
	end

	if curve.mode ~= "Custom" and curve.mode ~= "Bezier" then
		return Curve.new(curve.mode)
	end

	local copy = { mode = curve.mode == "Bezier" and "Custom" or curve.mode, points = {} }
	for i, point in curve.points do
		copy.points[i] = { point[1], point[2] }
	end

	return copy
end

function Curve.validate(curve)
	if not curve then
		return
	end

	assert(
		type(curve) == "table"
			and ({ Linear = true, QuadIn = true, QuadOut = true, Bezier = true, Custom = true })[curve.mode],
		"choose a path easing preset"
	)
	assert(
		type(curve.points) == "table" and #curve.points >= 2,
		"path timing needs a start and end point"
	)
	local previous = -1
	local moving = false
	for _, point in curve.points do
		assert(
			type(point) == "table" and type(point[1]) == "number" and type(point[2]) == "number",
			"invalid timing point"
		)
		assert(
			point[1] == point[1]
				and point[2] == point[2]
				and point[1] >= 0
				and point[1] <= 1
				and point[2] >= 0
				and point[2] <= 1
				and point[1] > previous,
			"keep timing points in order, from 0 to 100"
		)
		previous = point[1]
		moving = moving or point[2] > 0
	end

	if curve.mode == "Custom" or curve.mode == "Bezier" then
		assert(moving, "give at least one timing point some speed")
	end
end

function Curve.equal(a, b)
	if a == b then
		return true
	end

	a = a or Curve.new()
	b = b or Curve.new()
	local am = a.mode == "Bezier" and "Custom" or a.mode
	local bm = b.mode == "Bezier" and "Custom" or b.mode
	if am ~= bm or #a.points ~= #b.points then
		return false
	end

	for i, point in a.points do
		if point[1] ~= b.points[i][1] or point[2] ~= b.points[i][2] then
			return false
		end
	end

	return true
end

function Curve.speed(curve, time)
	local t = math.clamp(time, 0, 1)
	if not curve then
		return 1
	end

	if curve.mode == "Linear" then
		return t
	end

	if curve.mode == "QuadIn" then
		return t * t
	elseif curve.mode == "QuadOut" then
		return 1 - (1 - t) ^ 2
	end

	local points = curve.points
	if t <= points[1][1] then
		return points[1][2]
	end

	if t >= points[#points][1] then
		return points[#points][2]
	end

	local lo, hi = 1, #points
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if points[mid][1] <= t then
			lo = mid
		else
			hi = mid
		end
	end

	local a, b = points[lo], points[hi]
	local span = b[1] - a[1]
	local u = (t - a[1]) / span
	if curve.mode == "QuadIn" then
		u = u * u
	elseif curve.mode == "QuadOut" then
		u = 1 - (1 - u) ^ 2
	elseif curve.mode == "Bezier" or curve.mode == "Custom" then
		local slope = (b[2] - a[2]) / span

		local function tangent(index)
			if index == 1 or index == #points then
				return 0
			end

			local left, right = points[index - 1], points[index + 1]
			local value = points[index]
			local d0 = (value[2] - left[2]) / (value[1] - left[1])
			local d1 = (right[2] - value[2]) / (right[1] - value[1])
			if d0 * d1 <= 0 then
				return 0
			end

			return math.sign(d0)
				* math.min(math.abs((d0 + d1) / 2), 3 * math.abs(d0), 3 * math.abs(d1))
		end

		local m0, m1 = tangent(lo), tangent(hi)
		if slope == 0 then
			m0, m1 = 0, 0
		end

		return math.clamp(
			(2 * u ^ 3 - 3 * u ^ 2 + 1) * a[2]
				+ (u ^ 3 - 2 * u ^ 2 + u) * span * m0
				+ (-2 * u ^ 3 + 3 * u ^ 2) * b[2]
				+ (u ^ 3 - u ^ 2) * span * m1,
			0,
			1
		)
	end

	return a[2] + (b[2] - a[2]) * u
end

local function area(curve, a, b)
	return (b - a)
		* (Curve.speed(curve, a) + 4 * Curve.speed(curve, (a + b) / 2) + Curve.speed(curve, b))
		/ 6
end

function Curve.sample(curve, time)
	local t = math.clamp(time, 0, 1)
	if not curve then
		return t
	end

	local cache = integrated[curve]
	if not cache or cache.points ~= curve.points or cache.mode ~= curve.mode then
		cache = { points = curve.points, mode = curve.mode, times = { 0 }, sums = { 0 }, total = 0 }
		for _, point in curve.points do
			if point[1] > 0 and point[1] < 1 then
				table.insert(cache.times, point[1])
			end
		end

		table.insert(cache.times, 1)
		for i = 2, #cache.times do
			cache.total += area(curve, cache.times[i - 1], cache.times[i])
			cache.sums[i] = cache.total
		end

		integrated[curve] = cache
	end

	if cache.total <= 1e-12 then
		return t
	end

	if t == 0 or t == 1 then
		return t
	end

	local lo, hi = 1, #cache.times
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if cache.times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end

	return math.clamp((cache.sums[lo] + area(curve, cache.times[lo], t)) / cache.total, 0, 1)
end

function Curve.add(curve, time, distance)
	integrated[curve] = nil
	curve.mode = "Custom"
	local t = math.clamp(time, 0, 1)
	local index = 1
	while index <= #curve.points and curve.points[index][1] < t do
		index += 1
	end

	if index <= #curve.points and math.abs(curve.points[index][1] - t) < 1e-5 then
		return index
	end

	if index > 1 and math.abs(curve.points[index - 1][1] - t) < 1e-5 then
		return index - 1
	end

	table.insert(curve.points, index, { t, math.clamp(distance, 0, 1) })
	return index
end

function Curve.move(curve, index, time, distance)
	integrated[curve] = nil
	curve.mode = "Custom"
	local before = index > 1 and curve.points[index - 1][1] or 0
	local after = index < #curve.points and curve.points[index + 1][1] or 1
	local gap = math.min(1e-5, (after - before) / 3)
	curve.points[index] = {
		math.clamp(
			time,
			index > 1 and before + gap or 0,
			index < #curve.points and after - gap or 1
		),
		math.clamp(distance, 0, 1),
	}
end

function Curve.remove(curve, index)
	integrated[curve] = nil
	if #curve.points > 2 and index >= 1 and index <= #curve.points then
		table.remove(curve.points, index)
		return true
	end

	return false
end

function Curve.polyline(curve)
	local times = { 0, 1 }
	for _, point in curve.points do
		table.insert(times, point[1])
	end

	if curve.mode ~= "Linear" then
		for i = 1, 95 do
			table.insert(times, i / 96)
		end
	end

	table.sort(times)
	local result = {}
	local previous = -1
	local moving = false
	for _, time in times do
		if time > previous then
			table.insert(result, Vector2.new(time, 1 - Curve.speed(curve, time)))
			previous = time
		end
	end

	return result
end

return Curve
