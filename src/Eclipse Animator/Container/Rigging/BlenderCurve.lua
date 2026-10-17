--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Parenting = require("Parenting")
local Graph = require("GraphCurves")
local Curve = {}
local handles = {
	AUTO = "Automatic",
	AUTO_CLAMPED = "AutoClamped",
	VECTOR = "Vector",
	ALIGNED = "Aligned",
	FREE = "Free",
}
local styles = {
	CONSTANT = "Constant",
	LINEAR = "Linear",
	BEZIER = "Bezier",
	SINE = "Sine",
	QUAD = "Quad",
	CUBIC = "Cubic",
	QUART = "Quart",
	QUINT = "Quint",
	EXPO = "Expo",
	CIRC = "Circ",
	BACK = "Back",
	BOUNCE = "Bounce",
	ELASTIC = "Elastic",
}
local directions = { AUTO = "Automatic", EASE_IN = "In", EASE_OUT = "Out", EASE_IN_OUT = "InOut" }

local function equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for key, value in a do
		if not equal(value, b[key]) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function signature(key)
	return {
		style = key.EasingStyle,
		direction = key.EasingDirection,
		handle = key.HandleType,
		points = key.BezierPoints,
		graph = key.GraphCurves,
		overshoot = key.Overshoot,
		amplitude = key.Amplitude,
		period = key.Period,
	}
end

local function sameScale(key, expected)
	if not expected then
		return true
	end

	local scale = key.WholePoseScale
	return scale
		and scale.scale_x == expected.X
		and scale.scale_y == expected.Y
		and scale.scale_z == expected.Z
end

local function channels(key)
	local frame = key.C0
	local x, y, z = frame:ToEulerAnglesXYZ()
	local result = {
		loc_x = frame.X,
		loc_y = frame.Y,
		loc_z = frame.Z,
		rot_x = math.deg(x),
		rot_y = math.deg(y),
		rot_z = math.deg(z),
	}
	for id, value in key.WholePoseScale or {} do
		result[id] = value
	end

	return result
end

local function fit(values, source, indices, budget)
	local low, high = indices[1], indices[1]
	for _, index in indices do
		if budget then
			budget()
		end

		if source[index] < source[low] then
			low = index
		end

		if source[index] > source[high] then
			high = index
		end
	end

	local range = source[high] - source[low]
	if math.abs(range) < 1e-7 then
		return
	end

	local slope = (values[high] - values[low]) / range
	if math.abs(slope) < 1e-7 then
		return
	end

	local offset = values[low] - slope * source[low]
	local tolerance = 0.00003 * math.max(1, math.abs(values[high] - values[low]))
	for _, index in indices do
		if budget then
			budget()
		end

		if math.abs(values[index] - (offset + slope * source[index])) > tolerance then
			return
		end
	end

	return slope, offset
end

function Curve.attach(sparse, dense, authored, frames, sources, fps, budget)
	local cursors = {}
	for _, source in sources or {} do
		local last = -math.huge
		local firstAtFrame = {}
		for i, point in source.keys do
			if budget then
				budget()
			end

			assert(
				type(point.frame) == "number" and point.frame >= last,
				"unordered Blender curve keys"
			)
			firstAtFrame[i] = point.frame == last and firstAtFrame[i - 1] or i
			last = point.frame
		end

		cursors[source] = { at = 0, firstAtFrame = firstAtFrame }
	end

	local data, indices, components = {}, {}, {}
	for index, frame in frames do
		if budget then
			budget()
		end

		local key = dense[frame.frame]
		if not key then
			continue
		end

		indices[frame.frame] = index
		data[index] = channels(key)
		for id, value in data[index] do
			components[id] = components[id] or {}
			components[id][index] = value
		end
	end

	local possible = {}
	for index, frame in authored do
		if budget then
			budget()
		end

		local key, following = sparse[frame], authored[index + 1]
		local sourceMetadata = {}
		local representative
		local preferred = -1

		local function consider(point)
			if not point then
				return
			end

			local score = math.abs(point.frame - frame) < 0.00001 and 2
				or point.frame <= frame and 1
				or 0
			if
				score > preferred
				or score == preferred
					and representative
					and point.frame > representative.frame
					and point.frame <= frame
			then
				representative, preferred = point, score
			end
		end

		for _, source in sources or {} do
			if budget then
				budget()
			end

			local cursor = cursors[source]
			local points = source.keys
			while points[cursor.at + 1] and points[cursor.at + 1].frame <= frame do
				if budget then
					budget()
				end

				cursor.at += 1
			end

			local previous, nextKey = points[cursor.at], points[cursor.at + 1]
			table.insert(sourceMetadata, {
				owner = source.owner,
				path = source.path,
				index = source.index,
				previous = previous,
				following = nextKey,
				timing = source.timing,
			})
			consider(previous and points[cursor.firstAtFrame[cursor.at]] or points[1])
			if nextKey and math.abs(nextKey.frame - frame) < 0.00001 then
				consider(nextKey)
			end
		end

		if representative then
			key.EasingStyle = styles[representative.interpolation] or "Linear"
			key.EasingDirection = directions[representative.easing] or "Automatic"
			key.HandleType = handles[representative.rightType] or "AutoClamped"
			key.Overshoot, key.Amplitude, key.Period =
				representative.back, representative.amplitude, representative.period
		end

		key.BlenderCurve = { sources = sourceMetadata }
		if not following then
			continue
		end

		local samples, selected = {}, {}
		for at = indices[frame], indices[following] do
			if budget then
				budget()
			end

			local sample = dense[frames[at].frame]
			local scale = sample.WholePoseScale
			table.insert(selected, at)
			table.insert(samples, {
				alpha = (frames[at].frame - frame) / (following - frame),
				value = sample.C0,
				boundary = frames[at].boundary,
				scale = scale and Vector3.new(scale.scale_x, scale.scale_y, scale.scale_z),
			})
		end

		local curve = key.BlenderCurve
		curve.from, curve.to, curve.samples = key.C0, sparse[following].C0, samples
		local commonStyle, commonDirection, commonHandle, mixed = nil, nil, nil, false
		for _, source in sources or {} do
			local segment = source.segments and source.segments[index]
			if not segment or not source.values then
				continue
			end

			local moving = false
			for _, at in selected do
				if math.abs(source.values[at] - source.values[selected[1]]) > 1e-7 then
					moving = true
					break
				end
			end

			if not moving then
				continue
			end

			local style, direction, handle =
				styles[segment.style],
				directions[segment.easing] or "In",
				handles[segment.leftType] or "Vector"
			if
				commonStyle
				and (style ~= commonStyle or direction ~= commonDirection or handle ~= commonHandle)
			then
				mixed = true
			end

			commonStyle, commonDirection, commonHandle = style, direction, handle
		end

		if commonStyle and not mixed then
			key.EasingStyle, key.EasingDirection, key.HandleType =
				commonStyle, commonDirection, commonHandle
		end

		if key.EasingStyle == "Constant" then
			local origin = data[selected[1]]
			for _, at in selected do
				if frames[at].frame >= following - math.min(0.001, (following - frame) * 0.001) then
					continue
				end

				for id, value in data[at] do
					if math.abs(value - origin[id]) > 0.0001 then
						key.EasingStyle = "Linear"
						break
					end
				end

				if key.EasingStyle ~= "Constant" then
					break
				end
			end
		end

		for id, values in components do
			if possible[id] == false then
				continue
			end

			local matched
			local constant = true
			for _, at in selected do
				if math.abs(values[at] - values[selected[1]]) > 1e-6 then
					constant = false
					break
				end
			end

			if constant then
				matched = {
					style = "CONSTANT",
					start = values[selected[1]],
					finish = values[selected[#selected]],
					leftType = representative and representative.leftType or "VECTOR",
					rightType = representative and representative.rightType or "VECTOR",
				}
			else
				for _, source in sources or {} do
					local segment = source.segments and source.segments[index]
					if
						not segment
						or not source.values
						or not ({ BEZIER = true, LINEAR = true, CONSTANT = true })[segment.style]
					then
						continue
					end

					local slope, offset = fit(values, source.values, selected, budget)
					if not slope then
						continue
					end

					matched = Graph.clone(segment)
					matched.start, matched.finish = values[selected[1]], values[selected[#selected]]
					if segment.left then
						matched.left = { segment.left[1], offset + slope * segment.left[2] }
					end

					if segment.right then
						matched.right = { segment.right[1], offset + slope * segment.right[2] }
					end

					break
				end
			end

			if not matched then
				possible[id] = false
				continue
			end

			possible[id] = possible[id] or {}
			possible[id][index] = matched
		end
	end

	for id, segments in possible do
		if not segments then
			continue
		end

		for index, frame in authored do
			if budget then
				budget()
			end

			local key, previous, following = sparse[frame], segments[index - 1], segments[index]
			if not previous and not following then
				continue
			end

			local value = components[id][indices[frame]]
			local leftType = handles[previous and previous.rightType or following.leftType]
				or "Free"
			local rightType = handles[following and following.leftType or previous.rightType]
				or "Free"
			local mode = leftType == rightType and leftType or "Free"
			local point = {
				Value = value,
				Interpolation = styles[following and following.style or previous.style],
				HandleType = mode,
			}
			point.In = previous
				and previous.right
				and { (previous.right[1] - frame) / fps, previous.right[2] - value }
			point.Out = following
				and following.left
				and { (following.left[1] - frame) / fps, following.left[2] - value }
			point.BlenderHandles = {
				mode = mode,
				leftType = leftType,
				rightType = rightType,
				incoming = Graph.clone(point.In),
				outgoing = Graph.clone(point.Out),
			}
			key.GraphCurves = key.GraphCurves or {}
			key.GraphCurves[id] = point
		end
	end

	for index, frame in authored do
		if budget then
			budget()
		end

		local key, following = sparse[frame], sparse[authored[index + 1]]
		if following then
			key.BlenderCurve.signature = Graph.clone(signature(key))
			key.BlenderCurve.nextSignature = Graph.clone(signature(following))
		end
	end
end

function Curve.evaluate(bucket, time)
	local previous, following = Parenting.bounds(bucket, time)
	local curve = previous and previous.BlenderCurve
	if not curve or not curve.samples or not following or following.Time <= previous.Time then
		return
	end

	if previous.C0 ~= curve.from or following.C0 ~= curve.to then
		return
	end

	if curve.signature then
		if
			not equal(signature(previous), curve.signature)
			or not equal(signature(following), curve.nextSignature)
		then
			return
		end
	elseif
		previous.EasingStyle ~= "Linear"
		or previous.HandleType ~= "Vector"
		or next(previous.GraphCurves or {})
	then
		return
	end

	local alpha = math.clamp((time - previous.Time) / (following.Time - previous.Time), 0, 1)
	local samples = curve.samples
	if
		not sameScale(previous, samples[1].scale)
		or not sameScale(following, samples[#samples].scale)
	then
		return
	end

	if curve.signature and previous.EasingStyle == "Constant" and alpha < 1 then
		return previous.C0, samples[1].scale
	end

	local lo, hi = 1, #samples
	while lo < hi do
		local middle = math.floor((lo + hi + 1) / 2)
		if samples[middle].alpha <= alpha then
			lo = middle
		else
			hi = middle - 1
		end
	end

	local left, right = samples[lo], samples[math.min(lo + 1, #samples)]
	local blend = right.alpha > left.alpha
			and not right.boundary
			and (alpha - left.alpha) / (right.alpha - left.alpha)
		or 0
	local value, scale =
		left.value:Lerp(right.value, blend), left.scale and left.scale:Lerp(right.scale, blend)
	if curve.signature and next(previous.GraphCurves or {}) then
		value = Graph.cframe(bucket, time, value)
		local result = Graph.scale(
			bucket,
			time,
			scale and { scale_x = scale.X, scale_y = scale.Y, scale_z = scale.Z }
		)
		if result then
			scale = Vector3.new(result.scale_x, result.scale_y, result.scale_z)
		end
	end

	return value, scale
end

return Curve
