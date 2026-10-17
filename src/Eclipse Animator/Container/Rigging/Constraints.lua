--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local M = require("M")
local Constraints = {}
local AXIS = { X = 1, Y = 2, Z = 3 }

local function component(v, i)
	return i == 1 and v.X or i == 2 and v.Y or v.Z
end

local function vector(v)
	return Vector3.new(v[1], v[2], v[3])
end

local function rotationBetween(a, b)
	if a.Magnitude < 1e-9 or b.Magnitude < 1e-9 then
		return CFrame.identity
	end

	a, b = a.Unit, b.Unit
	local dot = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	local sine = axis.Magnitude
	if sine < 1e-10 then
		if dot > 0 then
			return CFrame.identity
		end

		axis = a:Cross(math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis)
	end

	return CFrame.fromAxisAngle(axis.Unit, math.atan2(sine, dot))
end

local function dampedTrackRotation(owner, dir, index, sign)
	local current = M.column(owner, index) * sign

	if current.Magnitude < 1e-9 then
		current = M.axes[index] * sign
	end

	local a, b = current.Unit, dir.Unit
	local dot = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	local sine = axis.Magnitude
	if sine < 1.1920928955078125e-7 then
		if dot >= 0 then
			return CFrame.identity
		end

		local nextIndex = index % 3 + 1
		local nextSign = index == 3 and -sign or sign
		axis = a:Cross(M.column(owner, nextIndex) * nextSign)
		if axis.Magnitude < 1e-9 then
			return CFrame.identity
		end

		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end

	return CFrame.fromAxisAngle(axis.Unit, math.atan2(sine, dot))
end

local function enumAxis(value, default)
	value = value or default or "TRACK_Y"
	return AXIS[value:sub(-1)] or 2, value:find("NEGATIVE", 1, true) and -1 or 1
end

local function trackRotation(cf, dir, up, track, upIndex)
	local ti, sign = enumAxis(track)
	local ui = enumAxis(upIndex, "UP_Z")
	if ti == ui or dir.Magnitude < 1e-9 then
		return cf.Rotation
	end

	local t = dir.Unit * sign
	local u = up - t * up:Dot(t)
	if u.Magnitude < 1e-9 then
		u = cf:VectorToWorldSpace(M.axes[ui])
		u -= t * u:Dot(t)
	end

	if u.Magnitude < 1e-9 then
		u = t:Cross(math.abs(t.X) < 0.9 and Vector3.xAxis or Vector3.yAxis)
	end

	u = u.Unit
	local axes = {}
	axes[ti], axes[ui] = t, u
	local missing = 6 - ti - ui
	if missing == 1 then
		axes[1] = axes[2]:Cross(axes[3])
	elseif missing == 2 then
		axes[2] = axes[3]:Cross(axes[1])
	else
		axes[3] = axes[1]:Cross(axes[2])
	end

	return CFrame.fromMatrix(Vector3.zero, axes[1], axes[2], axes[3])
end

local function selected(v, old, c, prefix, invert)
	local out = {}
	for i, axis in { "x", "y", "z" } do
		local value = component(v, i)
		if invert and c["invert_" .. axis] then
			value = -value
		end

		out[i] = c[(prefix or "use_") .. axis] ~= false and value or component(old, i)
	end

	return vector(out)
end

local function orderFor(node, c)
	local order = c.euler_order
	if not order or order == "AUTO" then
		order = node.data.rotation_mode or "XYZ"
	end

	return #order == 3 and order or "XYZ"
end

local function stableTargetRotation(matrix)
	return M.orthogonalizedY(matrix)
end

local function rotationMix(original, new, c, node)
	local order = orderFor(node, c)
	local originalEuler = M.blenderAffineEuler(original, order)
	local targetEuler = M.blenderAffineEuler(stableTargetRotation(new), order)
	local originalRotation = M.fromEuler(originalEuler, order)
	local result = M.fromEuler(selected(targetEuler, originalEuler, c, nil, true), order)
	local mode = c.mix_mode or (c.use_offset and "OFFSET" or "REPLACE")
	if mode == "ADD" or mode == "OFFSET" then
		return M.fromEuler(originalEuler + selected(targetEuler, Vector3.zero, c, nil, true), order)
	elseif mode == "BEFORE" then
		return result * originalRotation
	elseif mode == "AFTER" then
		return originalRotation * result
	end

	return result
end

local function channelsOf(a)
	local x, y, z = M.column(a, 1), M.column(a, 2), M.column(a, 3)
	local size = Vector3.new(x.Magnitude, y.Magnitude, z.Magnitude)
	if x:Dot(y:Cross(z)) < 0 then
		size = -size
	end

	local function unit(v, length)
		return if math.abs(length) > 1e-12 then v / length else Vector3.zero
	end

	return M.position(a), { unit(x, size.X), unit(y, size.Y), unit(z, size.Z) }, size
end

local function mixChannels(a, b, split)
	local la, ra, sa = channelsOf(a)
	local lb, rb, sb = channelsOf(b)
	local size = sa * sb
	local location = if split then la + lb else M.point(a, lb)
	local out = table.create(16, 0)
	for column = 1, 3 do
		local r = rb[column]
		local v = (ra[1] * r.X + ra[2] * r.Y + ra[3] * r.Z)
			* size[column == 1 and "X" or column == 2 and "Y" or "Z"]
		out[column], out[4 + column], out[8 + column] = v.X, v.Y, v.Z
	end

	out[4], out[8], out[12], out[16] = location.X, location.Y, location.Z, 1
	return out
end

local function sameMatrix(a, b)
	if a == b then
		return true
	end

	if not a or not b then
		return false
	end

	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

function Constraints.apply(ctx, node, world, c)
	local influence = math.clamp(ctx.influence(node, c), 0, 1)
	if influence == 0 or c.mute or c.enabled == false or c.type == "IK" then
		return world
	end

	local kind = c.type
	if kind == "ARMATURE" then
		if not c.targets then
			ctx.unsupported(node, c, "missing targets; re-export with Blender addon 1.5.8 or later")
			return world
		end

		local sum = table.create(16, 0)
		local weight = 0
		for _, target in c.targets or {} do
			local amount = tonumber(target.weight) or 0
			if amount <= 0 then
				continue
			end

			local targetNode, posed = ctx.target(target, node)
			if not targetNode or not posed then
				return world
			end

			if c.use_bone_envelopes or c.use_deform_preserve_volume then
				ctx.unsupported(node, c, "envelopes/preserve volume")
				return world
			end

			local rest = M.mul(targetNode.object.matrix, targetNode.restObject)
			local delta = M.mul(posed, (ctx.inverse or M.inverse)(rest))
			for i = 1, 16 do
				sum[i] += delta[i] * amount
			end

			weight += amount
		end

		if weight <= 0 then
			return world
		end

		for i = 1, 16 do
			sum[i] /= weight
		end

		return M.lerp(world, M.mul(sum, world), influence)
	end

	local inverse = ctx.inverse or M.inverse
	local ownerBasis = ctx.space(node, c.owner_space, c)
	local targetNode, targetWorld, targetOrder = ctx.target(c, node)
	local targetBasis = targetWorld and ctx.space(targetNode, c.target_space, c)
	local cache = ctx.constraintCache
	local revision = ctx.constraintRevisions and ctx.constraintRevisions[c] or 0
	local previous = cache and cache[c]
	if
		previous
		and previous.revision == revision
		and previous.influence == influence
		and previous.sourceScale == ctx.sourceScale
		and previous.targetOrder == targetOrder
		and sameMatrix(previous.world, world)
		and sameMatrix(previous.ownerBasis, ownerBasis)
		and sameMatrix(previous.targetWorld, targetWorld)
		and sameMatrix(previous.targetBasis, targetBasis)
	then
		return previous.result
	end

	local function finish(result)
		if cache then
			cache[c] = {
				revision = revision,
				influence = influence,
				sourceScale = ctx.sourceScale,
				targetOrder = targetOrder,
				world = world,
				ownerBasis = ownerBasis,
				targetWorld = targetWorld,
				targetBasis = targetBasis,
				result = result,
			}
		end

		return result
	end

	local owner = M.mul(inverse(ownerBasis), world)
	local target = targetWorld and M.mul(inverse(targetBasis), targetWorld)
	assert(M.isFinite(owner), "Armature contains a non-finite transform")
	local needsFrame = kind == "TRACK_TO"
		or kind == "LOCKED_TRACK"
		or kind == "STRETCH_TO"
		or kind == "LIMIT_ROTATION"
		or kind == "LIMIT_SCALE"
		or kind == "TRANSFORM"
	local cf = needsFrame and M.toCFrame(owner)
	local position, scale = M.position(owner), M.scale(owner)
	local result = owner
	if kind == "CHILD_OF" then
		if not target then
			return world
		end

		local inv = M.read(c.inverse_matrix)
		local allEnabled = true
		for _, axis in { "x", "y", "z" } do
			if
				c["use_location_" .. axis] == false
				or c["use_rotation_" .. axis] == false
				or c["use_scale_" .. axis] == false
			then
				allEnabled = false
				break
			end
		end

		if allEnabled then
			result = M.mul(M.mul(target, inv), owner)
		else
			local parentOrder = targetOrder
				or (targetNode and targetNode.data.rotation_mode)
				or "XYZ"
			local ownerOrder = node.data.rotation_mode or "XYZ"
			local te, ts = M.blenderAffineEuler(target, parentOrder)
			local ie, iss = M.blenderAffineEuler(inv, ownerOrder)
			local tp = selected(M.position(target), Vector3.zero, c, "use_location_")
			local ip = selected(M.position(inv), Vector3.zero, c, "use_location_")
			te = selected(te, Vector3.zero, c, "use_rotation_")
			ie = selected(ie, Vector3.zero, c, "use_rotation_")
			ts = selected(ts, Vector3.one, c, "use_scale_")
			iss = selected(iss, Vector3.one, c, "use_scale_")
			local filteredTarget = M.compose(CFrame.new(tp) * M.fromEuler(te, parentOrder), ts)
			local filteredInverse = M.compose(CFrame.new(ip) * M.fromEuler(ie, ownerOrder), iss)
			result = M.mul(M.mul(filteredTarget, filteredInverse), owner)
		end

		result = M.withPosition(result, selected(M.position(result), position, c, "use_location_"))

		return finish(M.lerp(world, M.mul(ctx.worldSpace, result), influence))
	elseif kind == "COPY_TRANSFORMS" then
		if not target then
			return world
		end

		local mode = c.mix_mode or "REPLACE"
		if mode == "REPLACE" then
			result = target
		elseif mode == "BEFORE_FULL" then
			result = M.mul(target, owner)
		elseif mode == "AFTER_FULL" then
			result = M.mul(owner, target)
		elseif mode == "BEFORE" then
			result = mixChannels(target, owner, false)
		elseif mode == "AFTER" then
			result = mixChannels(owner, target, false)
		elseif mode == "BEFORE_SPLIT" then
			result = mixChannels(target, owner, true)
		elseif mode == "AFTER_SPLIT" then
			result = mixChannels(owner, target, true)
		else
			ctx.unsupported(node, c, "mix mode " .. mode)
		end
	elseif kind == "COPY_LOCATION" then
		if not target then
			return world
		end

		local tp = M.position(target)
		local new = selected(tp, position, c, nil, true)
		if c.use_offset then
			local delta = selected(tp, Vector3.zero, c, nil, true)
			new = position + delta
		end

		result = M.withPosition(owner, new)
	elseif kind == "COPY_ROTATION" then
		if not target then
			return world
		end

		result = M.compose(CFrame.new(position) * rotationMix(owner, target, c, node), scale)
	elseif kind == "COPY_SCALE" then
		if not target then
			return world
		end

		local ts = M.scale(target)
		local power = tonumber(c.power) or 1
		if c.use_make_uniform then
			local selectedScale = 1
			if c.use_x ~= false and c.use_y ~= false and c.use_z ~= false then
				selectedScale = math.abs(
					M.column(target, 1):Dot(M.column(target, 2):Cross(M.column(target, 3)))
				)
			else
				for i, axis in { "x", "y", "z" } do
					if c["use_" .. axis] ~= false then
						selectedScale *= component(ts, i)
					end
				end
			end

			ts = Vector3.one * (math.abs(selectedScale) ^ (power / 3))
		else
			ts = Vector3.new(math.abs(ts.X) ^ power, math.abs(ts.Y) ^ power, math.abs(ts.Z) ^ power)
		end

		local new = c.use_make_uniform and ts or selected(ts, scale, c)
		if c.use_offset then
			if c.use_add == true then
				local added = scale + ts - Vector3.one
				new = c.use_make_uniform and added or selected(added, scale, c)
			else
				new = scale * (c.use_make_uniform and ts or selected(ts, Vector3.one, c))
			end
		end

		result = table.clone(owner)
		for column = 1, 3 do
			local original = component(scale, column)
			local factor = math.abs(original) > 1e-12 and component(new, column) / original or 0
			for row = 0, 2 do
				result[row * 4 + column] *= factor
			end
		end
	elseif kind == "DAMPED_TRACK" then
		if not target then
			return world
		end

		local dir = M.position(target) - position
		if dir.Magnitude < 1e-9 then
			return world
		end

		local ti, sign = enumAxis(c.track_axis)
		local rotation = dampedTrackRotation(owner, dir, ti, sign)
		result = M.withPosition(M.mul(M.fromCFrame(rotation), owner), position)
	elseif kind == "TRACK_TO" or kind == "LOCKED_TRACK" or kind == "STRETCH_TO" then
		if not target then
			return world
		end

		if kind == "STRETCH_TO" and (not c.keep_axis or c.keep_axis == "SWING_Y") then
			owner = M.orthogonalizedY(owner, false)
			scale = Vector3.new(
				M.column(owner, 1).Magnitude,
				M.column(owner, 2).Magnitude,
				M.column(owner, 3).Magnitude
			)
			local normalized = M.normalizedColumns(owner)
			cf = CFrame.fromMatrix(
				position,
				M.column(normalized, 1),
				M.column(normalized, 2),
				M.column(normalized, 3)
			)
		end

		local dir = M.position(target) - position
		if dir.Magnitude < 1e-9 then
			return world
		end

		local rot
		if kind == "TRACK_TO" then
			local up = c.use_target_z and M.column(target, 3) or Vector3.zAxis
			rot = trackRotation(cf, dir, up, c.track_axis, c.up_axis)
		elseif kind == "LOCKED_TRACK" then
			local ti, sign = enumAxis(c.track_axis)
			local li = enumAxis(c.lock_axis, "LOCK_Z")
			local lock = M.column(owner, li)
			if li == ti or lock.Magnitude < 1e-9 then
				return world
			end

			lock = lock.Unit
			local dst = dir - lock * dir:Dot(lock)
			if dst.Magnitude < 1e-9 then
				return world
			end

			local axes = {}
			axes[li], axes[ti] = lock, dst.Unit * sign
			local missing = 6 - li - ti
			if missing == 1 then
				axes[1] = axes[2]:Cross(axes[3])
			elseif missing == 2 then
				axes[2] = axes[3]:Cross(axes[1])
			else
				axes[3] = axes[1]:Cross(axes[2])
			end

			rot = CFrame.fromMatrix(Vector3.zero, axes[1], axes[2], axes[3])
		else
			local ti, sign = enumAxis(c.track_axis)
			if kind == "STRETCH_TO" then
				ti, sign = 2, 1
			end

			rot = rotationBetween(cf:VectorToWorldSpace(M.axes[ti]) * sign, dir) * cf.Rotation
			if kind == "STRETCH_TO" then
				local y = dir.Unit
				if c.keep_axis == "PLANE_X" then
					local z = M.column(owner, 1):Cross(y)
					if z.Magnitude > 1e-9 then
						z = z.Unit
						rot = CFrame.fromMatrix(Vector3.zero, y:Cross(z).Unit, y, z)
					end
				elseif c.keep_axis == "PLANE_Z" then
					local x = y:Cross(M.column(owner, 3))
					if x.Magnitude > 1e-9 then
						x = x.Unit
						rot = CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y).Unit)
					end
				end
			end
		end

		if kind == "STRETCH_TO" then
			local length = tonumber(c.rest_length) and c.rest_length * (ctx.sourceScale or 1)
				or node.data.length
				or 1
			if length > 1e-9 then
				local ratio = dir.Magnitude / length
				local volume = c.volume or "VOLUME_XZX"
				local factor = (math.abs(scale.Y) / math.max(ratio, 1e-9))
					^ ((tonumber(c.bulge) or 1) * 0.5)
				scale = Vector3.new(
					volume ~= "NO_VOLUME" and scale.X * factor or scale.X,
					ratio,
					volume ~= "NO_VOLUME" and scale.Z * factor or scale.Z
				)
			end
		end

		result = M.compose(CFrame.new(position) * rot, scale)
	elseif kind == "LIMIT_LOCATION" or kind == "LIMIT_ROTATION" or kind == "LIMIT_SCALE" then
		local order = orderFor(node, c)
		local value = kind == "LIMIT_LOCATION" and position
			or kind == "LIMIT_ROTATION" and M.euler(cf, order)
			or scale
		local out = {}
		local units = kind == "LIMIT_LOCATION" and (ctx.sourceScale or 1) or 1
		for i, axis in { "x", "y", "z" } do
			local v = component(value, i)
			local minEnabled = kind == "LIMIT_ROTATION" and c["use_limit_" .. axis]
				or c["use_min_" .. axis]
			local maxEnabled = kind == "LIMIT_ROTATION" and c["use_limit_" .. axis]
				or c["use_max_" .. axis]
			if minEnabled then
				v = math.max(v, (tonumber(c["min_" .. axis]) or 0) * units)
			end

			if maxEnabled then
				v = math.min(v, (tonumber(c["max_" .. axis]) or 0) * units)
			end

			out[i] = v
		end

		if kind == "LIMIT_LOCATION" then
			result = M.withPosition(owner, vector(out))
		elseif kind == "LIMIT_ROTATION" then
			result = M.compose(CFrame.new(position) * M.fromEuler(vector(out), order), scale)
		else
			result = M.compose(cf, vector(out))
		end
	elseif kind == "TRANSFORM" then
		if not target then
			return world
		end

		local from, to = c.map_from or "LOCATION", c.map_to or "LOCATION"
		local order = orderFor(node, c)
		local input = from == "LOCATION" and M.position(target)
			or from == "ROTATION" and M.euler(M.toCFrame(target), c.from_rotation_mode or order)
			or M.scale(target)
		local suffix = from == "ROTATION" and "_rot" or from == "SCALE" and "_scale" or ""
		local toSuffix = to == "ROTATION" and "_rot" or to == "SCALE" and "_scale" or ""
		local fromUnits = from == "LOCATION" and (ctx.sourceScale or 1) or 1
		local toUnits = to == "LOCATION" and (ctx.sourceScale or 1) or 1
		local mapped = {}
		for i, axis in { "x", "y", "z" } do
			local sourceAxis = (c["map_to_" .. axis .. "_from"] or axis):lower()
			local index = AXIS[sourceAxis:upper()] or i
			local lower = (tonumber(c["from_min_" .. sourceAxis .. suffix]) or 0) * fromUnits
			local upper = (tonumber(c["from_max_" .. sourceAxis .. suffix]) or 1) * fromUnits
			local t = math.abs(upper - lower) > 1e-10
					and (component(input, index) - lower) / (upper - lower)
				or 0
			if not c.use_motion_extrapolate then
				t = math.clamp(t, 0, 1)
			end

			local lo = (tonumber(c["to_min_" .. axis .. toSuffix]) or 0) * toUnits
			local hi = (tonumber(c["to_max_" .. axis .. toSuffix]) or 1) * toUnits
			mapped[i] = lo + (hi - lo) * t
		end

		local output = vector(mapped)
		local mode = (
			to == "ROTATION" and c.mix_mode_rot
			or to == "SCALE" and c.mix_mode_scale
			or c.mix_mode
		) or "ADD"
		if to == "LOCATION" then
			result = M.withPosition(owner, mode == "REPLACE" and output or position + output)
		elseif to == "ROTATION" then
			local rot = M.fromEuler(output, c.to_euler_order or order)
			if mode == "ADD" then
				rot = M.fromEuler(M.euler(cf, order) + output, order)
			elseif mode == "BEFORE" then
				rot = rot * cf.Rotation
			elseif mode == "AFTER" then
				rot = cf.Rotation * rot
			end

			result = M.compose(CFrame.new(position) * rot, scale)
		else
			result = M.compose(
				cf,
				mode == "REPLACE" and output
					or mode == "MULTIPLY" and scale * output
					or scale + output
			)
		end
	elseif kind == "LIMIT_DISTANCE" then
		if not target then
			return world
		end

		const center = M.position(target)
		const offset = position - center
		const current = offset.Magnitude
		const limit = (tonumber(c.distance) or 0) * (ctx.sourceScale or 1)
		const mode = c.limit_mode or "LIMITDIST_INSIDE"
		if
			limit > 0
			and current > 1e-9
			and (
				mode == "LIMITDIST_INSIDE" and current > limit
				or mode == "LIMITDIST_OUTSIDE" and current < limit
				or mode == "LIMITDIST_ONSURFACE" and current ~= limit
			)
		then
			result = M.withPosition(owner, center + offset * (limit / current))
		end
	elseif kind == "MAINTAIN_VOLUME" then
		const free = AXIS[(c.free_axis or "SAMEVOL_Y"):sub(-1)] or 2
		const mode = c.mode or "STRICT"
		const total = if mode == "STRICT"
			then scale.X * scale.Y * scale.Z
			elseif mode == "UNIFORM" then component(scale, free) ^ 3
			else component(scale, free)
		if math.abs(total) > 1e-12 then
			const factor = math.sqrt(math.abs((tonumber(c.volume) or 1) / total))
			result = table.clone(owner)
			for column = 1, 3 do
				if column ~= free then
					for row = 0, 2 do
						result[row * 4 + column] *= factor
					end
				end
			end
		end
	else
		ctx.unsupported(node, c, kind)
	end

	return finish(M.lerp(world, M.mul(ownerBasis, result), influence))
end

return Constraints
