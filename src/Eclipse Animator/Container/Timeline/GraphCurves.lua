--!native
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Bezier = require("Bezier")
local Quaternion = require("Quaternion")
local Easing = require("Easing")
local Policy = require("Policy")
local ChannelEasing = require("ChannelEasing")
local Curves = {}
local cache = setmetatable({}, { __mode = "k" })
local pointHandles
local EMPTY = { channels = {}, legacy = {}, hasGraph = false }
local IDS = {
	"loc_x",
	"loc_y",
	"loc_z",
	"qrot_w",
	"qrot_x",
	"qrot_y",
	"qrot_z",
	"rot_x",
	"rot_y",
	"rot_z",
	"scale_x",
	"scale_y",
	"scale_z",
}
Curves.ids = IDS
Curves.orders = { "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX" }
local validOrder = { XYZ = true, XZY = true, YXZ = true, YZX = true, ZXY = true, ZYX = true }

function Curves.validRotationOrder(order)
	return validOrder[order] == true
end

local function nativeOrder(order)
	return order and Enum.RotationOrder[order:reverse()] or Enum.RotationOrder.XYZ
end

function Curves.rotation(x, y, z, order)
	return CFrame.fromEulerAngles(math.rad(x), math.rad(y), math.rad(z), nativeOrder(order))
end

function Curves.euler(cf, order, reference)
	if not order then
		local x, y, z = cf:ToEulerAnglesXYZ()
		return math.deg(x), math.deg(y), math.deg(z)
	end

	local _, _, _, m11, m12, m13, m21, m22, m23, m31, m32, m33 = cf:GetComponents()
	local m = { { m11, m12, m13 }, { m21, m22, m23 }, { m31, m32, m33 } }
	local tuple = ({
		XYZ = { 1, 0 },
		XZY = { 1, 1 },
		YXZ = { 2, 1 },
		YZX = { 2, 0 },
		ZXY = {
			3,
			0,
		},
		ZYX = {
			3,
			1,
		},
	})[order or "ZYX"]
	local i, parity = tuple[1], tuple[2]
	local nextAxis = { 2, 3, 1, 2 }
	local j = nextAxis[i + parity]
	local k = nextAxis[i - parity + 1]
	local cosine = math.sqrt(m[i][i] ^ 2 + m[j][i] ^ 2)
	local first = cosine > 1e-7 and math.atan2(m[k][j], m[k][k]) or math.atan2(-m[j][k], m[j][j])
	local second = math.atan2(-m[k][i], cosine)
	local third = cosine > 1e-7 and math.atan2(m[j][i], m[i][i]) or 0
	local sign = parity == 1 and -1 or 1
	local a = {}
	a[i] = math.deg(first) * sign
	a[j] = math.deg(second) * sign
	a[k] = math.deg(third) * sign
	if not reference then
		return a[1], a[2], a[3]
	end

	local axes = { X = 1, Y = 2, Z = 3 }
	local middle = axes[(order or "XYZ"):sub(2, 2)]
	local b = table.clone(a)
	for i = 1, 3 do
		b[i] = i == middle and 180 - b[i] or b[i] + 180
	end

	local function near(v)
		local distance = 0
		for i = 1, 3 do
			v[i] = reference[i] + ((v[i] - reference[i] + 180) % 360) - 180
			distance += (v[i] - reference[i]) ^ 2
		end

		return distance
	end

	local da, db = near(a), near(b)
	local v = db < da and b or a
	return v[1], v[2], v[3]
end

function Curves.rotationOrder(bucket)
	return Curves.compile(bucket).rotationOrder
end

function Curves.rotationChannelVisible(bucket, id)
	local order = Curves.rotationOrder(bucket)
	if order then
		return id:sub(1, 5) ~= "qrot_"
	end

	if id:sub(1, 4) == "rot_" then
		return Curves.compile(bucket).channels[id] ~= nil
	end

	return true
end

function Curves.clone(value, budget)
	if type(value) ~= "table" then
		return value
	end

	if budget then
		budget()
	end

	local out = {}
	for key, item in pairs(value) do
		out[key] = Curves.clone(item, budget)
	end

	return out
end

function Curves.newPoint(key, id)
	local inherited = id and key.Channels and key.Channels[id] and key.Channels[id].Easing
	key = ChannelEasing.merge(key, inherited)
	local style = key.EasingStyle or "Bezier"
	local name = typeof(style) == "EnumItem" and style.Name or style
	local points = key.BezierPoints
	local bezier = name == "Bezier"
		and (
			not points
			or math.abs((points[1] or 0.42) - 0.42) < 1e-7
				and math.abs(points[2] or 0) < 1e-7
				and math.abs((points[3] or 0.58) - 0.58) < 1e-7
				and math.abs((points[4] or 1) - 1) < 1e-7
		)
	local point = {
		Interpolation = (
			bezier
			or name == "Linear"
			or name == "Constant" and typeof(style) ~= "EnumItem"
		)
				and name
			or "Legacy",
		HandleType = key.HandleType or require("Defaults").HandleType,
	}
	if point.Interpolation == "Legacy" then
		point.Easing = {
			EasingStyle = style,
			EasingDirection = key.EasingDirection,
			BezierPoints = Curves.clone(points),
			Amplitude = key.Amplitude,
			Period = key.Period,
			MoonEasing = key.MoonEasing,
			Overshoot = key.Overshoot,
		}
	end

	if inherited then
		point.ChannelEasing = Curves.clone(inherited)
	end

	return point
end

function Curves.resetAll()
	table.clear(cache)
end

function Curves.invalidate(bucket)
	Policy.invalidate(bucket)
	if bucket then
		cache[bucket] = nil
	end
end

const HANDLE_TIME_LIMIT = 1e5
const HANDLE_VALUE_LIMIT = 1e7

local function finite(value, limit)
	return type(value) == "number" and value == value and math.abs(value) <= (limit or 1e15)
end

local function validHandle(handle)
	return type(handle) == "table"
		and finite(handle[1], HANDLE_TIME_LIMIT)
		and finite(handle[2], HANDLE_VALUE_LIMIT)
end

local function sanitizePoint(point)
	for _, side in { "In", "Out" } do
		if point[side] ~= nil and not validHandle(point[side]) then
			point[side] = nil
		end
	end

	const imported = point.BlenderHandles
	if imported ~= nil then
		local valid = type(imported) == "table"
		for _, side in { "incoming", "outgoing" } do
			if valid and imported[side] ~= nil and not validHandle(imported[side]) then
				valid = false
			end
		end

		if not valid then
			point.BlenderHandles = nil
		end
	end
end

local function negatedPoint(point)
	const copy = table.clone(point)
	copy.Value = -point.Value
	for _, side in { "In", "Out" } do
		if type(point[side]) == "table" then
			copy[side] = { point[side][1], -point[side][2] }
		end
	end

	if type(point.BlenderHandles) == "table" then
		copy.BlenderHandles = table.clone(point.BlenderHandles)
		for _, side in { "incoming", "outgoing" } do
			const handle = point.BlenderHandles[side]
			if type(handle) == "table" then
				copy.BlenderHandles[side] = { handle[1], -handle[2] }
			end
		end
	end

	return copy
end

local function alignedQuaternions(channels)
	const rows = {}
	const order = {}
	for axis, id in { w = "qrot_w", x = "qrot_x", y = "qrot_y", z = "qrot_z" } do
		for index, row in ipairs(channels[id]) do
			local item = rows[row.key]
			if not item then
				item = { time = row.time, indexes = {}, values = {}, count = 0 }
				rows[row.key] = item
				table.insert(order, item)
			end

			item.indexes[id], item.values[axis] = index, row.point.Value
			item.count += 1
		end
	end

	table.sort(order, function(a, b)
		return a.time < b.time
	end)

	local flipped, previous = nil, nil
	for _, item in order do
		if item.count == 4 then
			local q = item.values
			if previous and previous.w * q.w + previous.x * q.x + previous.y * q.y + previous.z * q.z < 0 then
				q = { w = -q.w, x = -q.x, y = -q.y, z = -q.z }
				flipped = flipped or {}
				for id, index in item.indexes do
					flipped[id] = flipped[id] or {}
					flipped[id][index] = true
				end
			end

			previous = q
		end
	end

	if not flipped then
		return nil
	end

	const view = {}
	for id, indexes in flipped do
		const source = channels[id]
		const copy = { id = source.id, loopEntry = source.loopEntry }
		for index, row in source do
			if type(index) == "number" then
				copy[index] = indexes[index]
						and { key = row.key, point = negatedPoint(row.point), time = row.time, frame = row.frame }
					or row
			end
		end

		view[id] = copy
	end

	return view
end

function Curves.compile(bucket)
	if not bucket then
		return EMPTY
	end

	local saved = cache[bucket]
	if saved then
		return saved
	end

	local entry = { channels = {}, legacy = bucket, hasGraph = false }
	local hasOnly = false
	for _, key in pairs(bucket) do
		if type(key) == "table" then
			if key.EulerRotationOrder then
				entry.rotationOrder = key.EulerRotationOrder
				entry.hasGraph = true
			end

			hasOnly = hasOnly or key.GraphOnly == true
			const curves = type(key.GraphCurves) == "table" and finite(key.Time) and key.GraphCurves
			for id, point in curves or EMPTY.channels do
				if type(point) == "table" and finite(point.Value) then
					sanitizePoint(point)
					if id:sub(1, 4) == "rot_" and point.RotationOrder then
						assert(validOrder[point.RotationOrder], "Invalid Euler rotation order")
						assert(
							not entry.rotationOrder or entry.rotationOrder == point.RotationOrder,
							"Mixed Euler orders in one track; convert the track before pasting"
						)
						entry.rotationOrder = point.RotationOrder
					end

					entry.hasGraph = true
					entry.channels[id] = entry.channels[id] or {}
					table.insert(
						entry.channels[id],
						{ key = key, point = point, time = key.Time, frame = key.Frame }
					)
				end
			end
		end
	end

	if hasOnly then
		entry.legacy = {}
		for frame, key in pairs(bucket) do
			if not key.GraphOnly then
				entry.legacy[frame] = key
			end
		end
	end

	for id, channel in pairs(entry.channels) do
		table.sort(channel, function(a, b)
			return a.time < b.time
		end)
		channel.id = id
		local motor = channel[1].key.Motor
		local modifiers = motor and require("Mods").get(motor, id)
		if modifiers and modifiers.Stack[1] and modifiers.Stack[1].SmoothSeam then
			channel.loopEntry = modifiers
		end
	end

	const channels = entry.channels
	if channels.qrot_w and channels.qrot_x and channels.qrot_y and channels.qrot_z then
		entry.alignedQuaternion = alignedQuaternions(channels)
	end

	cache[bucket] = entry
	return entry
end

function Curves.hasChannelEasing(bucket)
	local entry = Curves.compile(bucket)
	if entry.hasChannelEasing ~= nil then
		return entry.hasChannelEasing
	end

	entry.hasChannelEasing = false
	for _, key in bucket or {} do
		for _, channel in key.Channels or {} do
			if channel.Easing and next(channel.Easing) then
				entry.hasChannelEasing = true
				return true
			end
		end
	end

	return false
end

function Curves.hasVisibleKey(bucket, key)
	if key.PropertyValue ~= nil then
		return true
	end

	for _, point in pairs(key.GraphCurves or {}) do
		if not point.Empty then
			return true
		end
	end

	if key.GraphOnly then
		return false
	end

	local owned = Curves.compile(bucket).channels
	if key.Channels then
		for id in pairs(key.Channels) do
			if not owned[id] then
				return true
			end
		end
	elseif key.C0 then
		for _, id in ipairs(IDS) do
			if id:sub(1, 4) ~= "rot_" and not owned[id] then
				return true
			end
		end
	end

	return false
end

function Curves.hasKeyContent(bucket, key)
	return Curves.hasVisibleKey(bucket, key)
end

function Curves.activateIncoming(bucket, key, id)
	local previous
	for _, entry in ipairs(Curves.compile(bucket).channels[id] or {}) do
		if entry.time < key.Time and (not previous or entry.time > previous.time) then
			previous = entry
		end
	end

	if previous then
		previous.point.Interpolation = "Bezier"
		ChannelEasing.graphChanged(previous.key, id)
	end
end

function Curves.syncEasing(key, handleOnly, bucket, channelId)
	for id, point in pairs(key.GraphCurves or {}) do
		if channelId and id ~= channelId then
			continue
		end

		if point.Empty then
			continue
		end

		local source = ChannelEasing.merge(key, point.ChannelEasing)
		local style = source.EasingStyle
		local name = typeof(style) == "EnumItem" and style.Name or style
		local native = typeof(style) == "EnumItem" and style.EnumType == Enum.PoseEasingStyle
		local incoming, outgoing
		if
			handleOnly
			and (source.HandleType == "Free" or source.HandleType == "Aligned")
			and bucket
		then
			for index, entry in Curves.compile(bucket).channels[id] or {} do
				if entry.key == key then
					local left, right = pointHandles(Curves.compile(bucket).channels[id], index)
					incoming = { left.time - key.Time, left.value - point.Value }
					outgoing = { right.time - key.Time, right.value - point.Value }
					if source.HandleType == "Aligned" and math.abs(outgoing[1]) > 1e-9 then
						incoming[2] = incoming[1] * outgoing[2] / outgoing[1]
					end

					break
				end
			end
		end

		if handleOnly then
			point.BlenderHandles = nil
		end

		if handleOnly then
			point.HandleType = source.HandleType
			point.Interpolation = "Bezier"
			point.In, point.Out = incoming, outgoing
			if bucket then
				Curves.activateIncoming(bucket, key, id)
			end
		else
			local points = source.BezierPoints
			local automaticBezier = name == "Bezier"
				and (
					not points
					or math.abs(points[1] - 0.42) < 1e-7
						and math.abs(points[2]) < 1e-7
						and math.abs(points[3] - 0.58) < 1e-7
						and math.abs(points[4] - 1) < 1e-7
				)
			point.Interpolation = (
				name == "Linear"
				or name == "Constant" and not native
				or automaticBezier
			)
					and name
				or "Legacy"
			point.Easing = {
				EasingStyle = name,
				EasingDirection = typeof(source.EasingDirection) == "EnumItem"
						and source.EasingDirection.Name
					or source.EasingDirection,
				NativePose = native,
				BezierPoints = Curves.clone(source.BezierPoints),
				Overshoot = source.Overshoot,
				Amplitude = source.Amplitude,
				Period = source.Period,
				MoonEasing = source.MoonEasing,
			}
		end
	end
end

function Curves.legacyBucket(bucket)
	return bucket and Curves.compile(bucket).legacy or nil
end

local function automatic(point)
	local mode = point.HandleType or "AutoClamped"
	return mode == "Automatic" or mode == "AutoClamped"
end

local function cycleOf(channel)
	if channel.cycle == nil then
		local kind = false
		local first = channel[1]
		local motor = first and first.key and first.key.Motor
		if
			motor
			and channel.id
			and #channel >= 2
			and automatic(first.point)
			and automatic(channel[#channel].point)
		then
			local Mods = require("Mods")
			kind = Mods.cycleType(Mods.get(motor, channel.id)) or false
		end

		channel.cycle = kind
	end

	return channel.cycle
end

local function loopChannel(channel, finish)
	if not channel or not finish or finish <= 0 or #channel < 3 or cycleOf(channel) then
		return channel
	end

	local first, last = channel[1], channel[#channel]
	if
		math.abs(first.time) > 1e-7
		or math.abs(last.time - finish) > 1e-7
		or not automatic(first.point)
		or not automatic(last.point)
		or first.point.BlenderHandles
		or last.point.BlenderHandles
		or math.abs(first.point.Value - last.point.Value)
			> 1e-6 * math.max(1, math.abs(first.point.Value), math.abs(last.point.Value))
	then
		return channel
	end

	if channel.loopEnd ~= finish then
		local view = table.clone(channel)
		view.cycle = "Repeat"
		view.smoothed = nil
		view.loopView = nil
		view.loopEnd = nil
		channel.loopEnd = finish
		channel.loopView = view
	end

	return channel.loopView
end

local function extendOf(channel)
	if channel.extend == nil then
		local kind = false
		local first = channel[1]
		local motor = first and first.key and first.key.Motor
		if motor and channel.id then
			local entry = require("Mods").get(motor, channel.id)
			kind = entry ~= nil and entry.Extrapolation == "Linear" and "Linear" or false
		end

		channel.extend = kind
	end

	return channel.extend
end

local function extremum(previous, value, following)
	local a, b = previous - value, following - value
	return (a <= 0 and b <= 0) or (a >= 0 and b >= 0)
end

local function keyHandles(channel, index, smooth)
	local key = channel[index]
	local previous, following = channel[index - 1], channel[index + 1]
	local point, value, time = key.point, key.point.Value, key.time
	local mode = point.HandleType or "AutoClamped"
	local cycle = (index == 1 or index == #channel) and cycleOf(channel)
	local first, last = channel[1], channel[#channel]
	local period, shift = 0, 0
	local locked = false
	if cycle then
		period = last.time - first.time
		shift = cycle == "Offset" and last.point.Value - first.point.Value or 0
		if index == 1 then
			local source = channel[#channel - 1]
			previous =
				{ time = source.time - period, point = { Value = source.point.Value - shift } }
		end

		if index == #channel then
			local source = channel[2]
			following =
				{ time = source.time + period, point = { Value = source.point.Value + shift } }
		end
	end

	local realNeighbors = previous ~= nil and following ~= nil
	local linear = not cycle and #channel >= 2 and extendOf(channel) == "Linear"
	if linear then
		if not previous and following then
			previous = {
				time = 2 * time - following.time,
				point = { Value = 2 * value - following.point.Value },
			}
		elseif not following and previous then
			following = {
				time = 2 * time - previous.time,
				point = { Value = 2 * value - previous.point.Value },
			}
		end
	end

	local left, right
	if not previous and not following then
		left, right = { time = time - 1 / 3, value = value }, { time = time + 1 / 3, value = value }
	else
		local lt, rt =
			Bezier.lengths(previous and previous.time, time, following and following.time, mode)
		if smooth and (mode == "Automatic" or mode == "AutoClamped") then
			lt = ((previous and time - previous.time) or (following.time - time)) / 3
			rt = ((following and following.time - time) or (time - previous.time)) / 3
		end

		local lv, rv = Bezier.handles(
			previous and previous.point.Value,
			value,
			following and following.point.Value,
			previous and previous.time,
			time,
			following and following.time,
			lt,
			rt,
			mode
		)
		left, right = { time = time - lt, value = lv }, { time = time + rt, value = rv }
		if
			mode == "AutoClamped"
			and realNeighbors
			and extremum(previous.point.Value, value, following.point.Value)
		then
			locked = true
		end

		if
			(mode == "Automatic" or mode == "AutoClamped")
			and not cycle
			and not linear
			and (index == 1 or index == #channel)
		then
			left.value, right.value = value, value
			locked = true
		end
	end

	if cycle and #channel >= 2 then
		local secondLast, second = channel[#channel - 1], channel[2]
		local firstLocked = (first.point.HandleType or "AutoClamped") == "AutoClamped"
			and extremum(secondLast.point.Value - shift, first.point.Value, second.point.Value)
		local lastLocked = (last.point.HandleType or "AutoClamped") == "AutoClamped"
			and extremum(secondLast.point.Value, last.point.Value, second.point.Value + shift)
		if firstLocked or lastLocked then
			left.value, right.value = value, value
			locked = true
		end
	end

	local imported = point.BlenderHandles

	local function same(a, b)
		return a == b or a and b and a[1] == b[1] and a[2] == b[2]
	end

	local keepImported = imported
		and imported.mode == mode
		and same(point.In, imported.incoming)
		and same(point.Out, imported.outgoing)
	local kind = mode == "Automatic" and "AUTO"
		or mode == "AutoClamped" and "AUTO_ANIM"
		or mode == "Vector" and "VECT"
		or "FIXED"
	if mode == "Free" or mode == "Aligned" or keepImported then
		if point.In then
			left = { time = time + point.In[1], value = value + point.In[2] }
		end

		if point.Out then
			right = { time = time + point.Out[1], value = value + point.Out[2] }
		end

		kind = "FIXED"
	end

	return left, right, locked, kind
end

local HUGE = math.huge

local function isAuto(kind)
	return kind == "AUTO" or kind == "AUTO_ANIM"
end

local function freeAuto(b)
	return isAuto(b.kind) and not b.locked
end

local function solveEnd(b, isEnd)
	return b.kind == "VECT" or (isEnd and isAuto(b.kind) and not b.locked)
end

local function triSolve(a, b, c, d, x, count)
	if count < 1 then
		return false
	end

	local c1, d1 = {}, {}
	local cp, dp = c[0] / b[0], d[0] / b[0]
	c1[0], d1[0] = cp, dp
	for i = 1, count - 1 do
		local den = b[i] - a[i] * cp
		cp = c[i] / den
		dp = (d[i] - a[i] * dp) / den
		c1[i], d1[i] = cp, dp
	end

	local xp = dp
	x[count - 1] = xp
	for i = count - 2, 0, -1 do
		xp = d1[i] - c1[i] * xp
		x[i] = xp
	end

	return xp == xp and math.abs(xp) ~= HUGE
end

local function triSolveCyclic(a, b, c, d, x, count)
	if count < 1 then
		return false
	end

	if count == 1 then
		x[0] = d[0] / (a[0] + b[0] + c[0])
		return x[0] == x[0] and math.abs(x[0]) ~= HUGE
	end

	if count == 2 then
		return triSolve({ [0] = 0, [1] = a[1] + c[1] }, b, { [0] = a[0] + c[0], [1] = 0 }, d, x, 2)
	end

	local a0, cN = a[0], c[count - 1]
	if a0 == 0 and cN == 0 then
		return triSolve(a, b, c, d, x, count)
	end

	local b2, tmp = {}, {}
	for i = 0, count - 1 do
		b2[i] = b[i]
		tmp[i] = 0
	end

	b2[0] -= a0
	b2[count - 1] -= cN
	tmp[0], tmp[count - 1] = a0, cN
	local adjust = {}
	local ok = triSolve(a, b2, c, tmp, adjust, count) and triSolve(a, b2, c, d, x, count)
	if ok then
		local coeff = (x[0] + x[count - 1]) / (1 + adjust[0] + adjust[count - 1])
		for i = 0, count - 1 do
			x[i] -= coeff * adjust[i]
		end
	end

	return ok
end

local function solveLimits(a, b, c, d, h, hmin, hmax, n)
	local a0, b0, c0, d0, lockedAt, unlocks = {}, {}, {}, {}, {}, {}
	for i = 0, n - 1 do
		a0[i], b0[i], c0[i], d0[i], lockedAt[i], unlocks[i] = a[i], b[i], c[i], d[i], false, 0
	end

	local overshoot, unlocked
	local guard = 0
	repeat
		guard += 1
		if guard > 200 or not triSolveCyclic(a, b, c, d, h, n) then
			return false
		end

		local all, lockedAny = false, false
		overshoot, unlocked = false, false
		repeat
			for i = 0, n - 1 do
				if not (h[i] >= hmin[i] and h[i] <= hmax[i]) then
					overshoot = true
					local target = h[i] > hmax[i] and hmax[i] or hmin[i]
					if target ~= 0 or all then
						lockedAt[i] = true
						a[i], b[i], c[i], d[i] = 0, 1, 0, target
						lockedAny = true
					end
				end
			end

			all = true
		until not (overshoot and not lockedAny)
		if not lockedAny then
			for i = 0, n - 1 do
				if lockedAt[i] and unlocks[i] < 2 then
					local state = a0[i] * h[(i + n - 1) % n]
						+ b0[i] * h[i]
						+ c0[i] * h[(i + 1) % n]
						- d0[i]
					local relax = -state * b0[i]
					if (relax > 0 and h[i] < hmax[i]) or (relax < 0 and h[i] > hmin[i]) then
						a[i], b[i], c[i], d[i] = a0[i], b0[i], c0[i], d0[i]
						lockedAt[i] = false
						unlocks[i] += 1
						unlocked = true
					end
				end
			end
		end
	until not (overshoot or unlocked)
	return true
end

local function clampRange(hmax, hmin, i, dy, noReverse, noOvershoot)
	if dy > 0 then
		if noOvershoot then
			hmax[i] = math.min(hmax[i], dy)
		end

		if noReverse then
			hmin[i] = 0
		end
	elseif dy < 0 then
		if noReverse then
			hmax[i] = 0
		end

		if noOvershoot then
			hmin[i] = math.max(hmin[i], dy)
		end
	elseif noReverse or noOvershoot then
		hmax[i], hmin[i] = 0, 0
	end
end

local function outputHandle(b, right, dy, endpoint)
	if not (isAuto(b.kind) or b.kind == "VECT") then
		return
	end

	if right then
		b.ry = b.y + dy
		if endpoint then
			b.lx, b.ly = 2 * b.x - b.rx, 2 * b.y - b.ry
		end
	else
		b.ly = b.y + dy
		if endpoint then
			b.rx, b.ry = 2 * b.x - b.lx, 2 * b.y - b.ly
		end
	end
end

local function handleAdjust(hx, hy, dx)
	local fac = dx / (hx + dx / 3)
	if fac < 1 then
		hx, hy = hx * fac, hy * fac
	end

	return hy, 1 - 3 * hx / dx
end

local function calcSmooth(B, total, start, count, cycle)
	if count < 2 then
		return
	end

	local fullCycle = start == 0 and count == total and cycle
	local first = B[start]
	local last = B[(start + count > total) and start + count - total or start + count - 1]
	local solveFirst = solveEnd(first, start == 0)
	local solveLast = solveEnd(last, start + count == total)
	if count == 2 and not fullCycle and solveFirst == solveLast then
		return
	end

	local dx, dy, l, a, b, c, d, h, hmax, hmin = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
	dx[0], dy[0] = 0 / 0, 0 / 0
	local j = start + 1
	for i = 1, count - 1 do
		dx[i] = B[j].x - B[j - 1].x
		dy[i] = B[j].y - B[j - 1].y
		if cycle and j == total - 1 then
			j = 0
		end

		j += 1
	end

	if fullCycle then
		dx[0], dy[0] = dx[count - 1], dy[count - 1]
		l[0] = dx[1] / dx[0]
		l[count - 1] = l[0]
	else
		l[0], l[count - 1] = 1, 1
	end

	for i = 1, count - 2 do
		l[i] = dx[i + 1] / dx[i]
	end

	for i = 0, count - 1 do
		hmax[i], hmin[i] = HUGE, -HUGE
	end

	local clampedPrev, clampedCur = false, first.kind == "AUTO_ANIM"
	j = start + 1
	for i = 1, count - 1 do
		clampedPrev = clampedCur
		clampedCur = B[j].kind == "AUTO_ANIM"
		if cycle and j == total - 1 then
			j = 0
			clampedCur = clampedCur or B[j].kind == "AUTO_ANIM"
		end

		clampRange(hmax, hmin, i - 1, dy[i], clampedPrev, clampedPrev)
		clampRange(hmax, hmin, i, dy[i] * l[i], clampedCur, clampedCur)
		j += 1
	end

	local firstAdjust, lastAdjust = 0, 0
	local solveCount = count

	local function continuous(i)
		a[i] = l[i] * l[i]
		b[i] = 2 * (l[i] + 1)
		c[i] = 1 / l[i + 1]
		d[i] = dy[i] * l[i] * l[i] + dy[i + 1]
	end

	if fullCycle then
		local i = count - 1
		solveCount = count - 1
		hmin[0] = math.max(hmin[0], hmin[i])
		hmax[0] = math.min(hmax[0], hmax[i])
		solveFirst, solveLast = true, true
		continuous(0)
	else
		if not solveFirst then
			local hy, adjust = handleAdjust(first.rx - first.x, first.ry - first.y, dx[1])
			firstAdjust = adjust
			a[0], b[0], c[0], d[0] = 0, 1, 0, hy
		else
			a[0], b[0], c[0], d[0] = 0, 2, 1 / l[1], dy[1]
		end

		if not solveLast then
			local hy, adjust = handleAdjust(last.x - last.lx, last.y - last.ly, dx[count - 1])
			lastAdjust = adjust
			a[count - 1], b[count - 1], c[count - 1], d[count - 1] = 0, 1, 0, hy
		else
			local n = count - 1
			a[n], b[n], c[n], d[n] = l[n] * l[n], 2 * l[n], 0, dy[n] * l[n] * l[n]
		end
	end

	for i = 1, count - 2 do
		continuous(i)
	end

	if not fullCycle then
		if count > 2 or solveLast then
			b[1] += l[1] * firstAdjust
		end

		if count > 2 or solveFirst then
			b[count - 2] += lastAdjust
		end
	end

	if solveLimits(a, b, c, d, h, hmin, hmax, solveCount) then
		if fullCycle then
			h[count - 1] = h[0]
		end

		j = start + 1
		for i = 1, count - 2 do
			local isEnd = j == total - 1
			outputHandle(B[j], false, -h[i] / l[i], isEnd)
			if isEnd then
				j = 0
			end

			outputHandle(B[j], true, h[i], isEnd)
			j += 1
		end

		if solveFirst then
			outputHandle(first, true, h[0], start == 0)
		end

		if solveLast then
			outputHandle(last, false, -h[count - 1] / l[count - 1], start + count == total)
		end
	end
end

local function smoothFcurve(B, total, cyclic)
	cyclic = cyclic and freeAuto(B[0]) and freeAuto(B[total - 1])
	local searchBase = 0
	if cyclic then
		for i = 1, total - 2 do
			if not freeAuto(B[i]) then
				searchBase = i
				break
			end
		end

		if searchBase == 0 then
			calcSmooth(B, total, 0, total, cyclic)
			return
		end
	end

	local start, count = searchBase, 1
	local j = start + 1
	for _ = 1, total - 1 do
		if j == total - 1 and cyclic then
			j = 0
		end

		if not freeAuto(B[j]) then
			calcSmooth(B, total, start, count + 1, cyclic)
			start, count = j, 1
		else
			count += 1
		end

		j += 1
	end

	if count > 1 then
		calcSmooth(B, total, start, count, cyclic)
	end
end

local function smoothingEnabled(channel)
	if channel.smoothing == nil then
		local ok, value = pcall(function()
			return require("Preferences").get("GraphAutoSmoothing")
		end)
		channel.smoothing = not ok or value ~= false
	end

	return channel.smoothing
end

local function smoothChannel(channel)
	local total = #channel
	local B = {}
	for j = 0, total - 1 do
		local entry = channel[j + 1]
		local left, right, locked, kind = keyHandles(channel, j + 1, true)
		if j > 0 and channel[j].time >= entry.time then
			locked = true
			B[j - 1].locked = true
		end

		B[j] = {
			x = entry.time,
			y = entry.point.Value,
			kind = kind,
			locked = locked,
			lx = left.time,
			ly = left.value,
			rx = right.time,
			ry = right.value,
		}
	end

	smoothFcurve(B, total, cycleOf(channel) and true or false)
	local out = {}
	for j = 0, total - 1 do
		local b = B[j]
		out[j + 1] = { b.lx, b.ly, b.rx, b.ry }
	end

	return out
end

pointHandles = function(channel, index)
	if #channel >= 2 and smoothingEnabled(channel) then
		local cache = channel.smoothed
		if not cache then
			cache = smoothChannel(channel)
			channel.smoothed = cache
		end

		local h = cache[index]
		return { time = h[1], value = h[2] }, { time = h[3], value = h[4] }
	end

	local left, right = keyHandles(channel, index, false)
	return left, right
end

local function segmentHandles(channel, index)
	local a, b = channel[index], channel[index + 1]
	local _, outgoing = pointHandles(channel, index)
	local incoming = pointHandles(channel, index + 1)
	local duration = b.time - a.time
	local rightLength = math.abs(outgoing.time - a.time)
	local leftLength = math.abs(b.time - incoming.time)
	if rightLength + leftLength > duration then
		local factor = duration / (rightLength + leftLength)
		outgoing.value = a.point.Value + (outgoing.value - a.point.Value) * factor
		incoming.value = b.point.Value + (incoming.value - b.point.Value) * factor
		rightLength *= factor
		leftLength *= factor
	end

	local x1, x2 = rightLength / duration, 1 - leftLength / duration
	outgoing.time, incoming.time = a.time + x1 * duration, a.time + x2 * duration
	return outgoing, incoming
end

Curves.segmentHandles = segmentHandles

local function handleValues(channel, index)
	if #channel >= 2 and smoothingEnabled(channel) then
		local cache = channel.smoothed
		if not cache then
			cache = smoothChannel(channel)
			channel.smoothed = cache
		end

		local h = cache[index]
		return h[1], h[2], h[3], h[4]
	end

	local left, right = keyHandles(channel, index, false)
	return left.time, left.value, right.time, right.value
end

local function segmentValues(channel, index)
	local a, b = channel[index], channel[index + 1]
	local _, _, outgoingTime, outgoingValue = handleValues(channel, index)
	local incomingTime, incomingValue = handleValues(channel, index + 1)
	local duration = b.time - a.time
	local rightLength = math.abs(outgoingTime - a.time)
	local leftLength = math.abs(b.time - incomingTime)
	if rightLength + leftLength > duration then
		local factor = duration / (rightLength + leftLength)
		outgoingValue = a.point.Value + (outgoingValue - a.point.Value) * factor
		incomingValue = b.point.Value + (incomingValue - b.point.Value) * factor
		rightLength *= factor
		leftLength *= factor
	end

	local x1, x2 = rightLength / duration, 1 - leftLength / duration
	return a.time + x1 * duration, outgoingValue, a.time + x2 * duration, incomingValue
end

function Curves.pointHandles(channel, index, loopEndTime)
	return pointHandles(loopChannel(channel, loopEndTime), index)
end

local function extrapolate(channel, index, time)
	local key = channel[index]
	local value = key.point.Value
	local style = key.point.Interpolation or "Bezier"
	if style == "Constant" or style == "ConstantNext" then
		return value
	end

	if style == "Linear" then
		local neighbor = channel[index == 1 and 2 or #channel - 1]
		local span = neighbor.time - key.time
		if span == 0 then
			return value
		end

		return value - (neighbor.point.Value - value) / span * (key.time - time)
	end

	local left, right = pointHandles(channel, index)
	local handle = index == 1 and left or right
	local span = key.time - handle.time
	if span == 0 then
		return value
	end

	return value - (value - handle.value) / span * (key.time - time)
end

function Curves.loopModifier(channel, entry)
	if not channel or #channel < 3 or channel.loopModifierView then
		return channel
	end

	local Mods = require("Mods")
	local cycle = Mods.cycleType(entry)
	local modifier = entry and entry.Stack and entry.Stack[1]
	if not cycle or not modifier.SmoothSeam then
		return channel
	end

	local a, b = channel[1], channel[#channel]

	if
		cycle == "Perfect"
		and math.abs(a.point.Value - b.point.Value)
			> 1e-6 * math.max(1, math.abs(a.point.Value), math.abs(b.point.Value))
	then
		return channel
	end

	if
		not channel.smoothLoop
		or channel.smoothLoopEntry ~= entry
		or channel.smoothLoop.cycle ~= cycle
	then
		local view = table.clone(channel)
		view.cycle = cycle
		view.smoothed = nil
		view.loopModifierView = true
		view.loopEntry = nil
		for i, key in channel do
			if type(i) == "number" then
				local row = table.clone(key)
				row.point = table.clone(key.point)
				row.point.HandleType = "Automatic"
				row.point.Interpolation = "Bezier"
				row.point.In = nil
				row.point.Out = nil
				row.point.BlenderHandles = nil
				view[i] = row
			end
		end

		channel.smoothLoop = view
		channel.smoothLoopEntry = entry
	end

	return channel.smoothLoop
end

function Curves.value(channel, time, loopEndTime)
	if channel and channel.loopEntry then
		channel = Curves.loopModifier(channel, channel.loopEntry)
	end

	channel = loopChannel(channel, loopEndTime)
	if not channel or #channel == 0 then
		return nil
	end

	if time <= channel[1].time then
		if time < channel[1].time and #channel >= 2 and extendOf(channel) == "Linear" then
			return extrapolate(channel, 1, time)
		end

		return channel[1].point.Value
	end

	if time >= channel[#channel].time then
		if time > channel[#channel].time and #channel >= 2 and extendOf(channel) == "Linear" then
			return extrapolate(channel, #channel, time)
		end

		return channel[#channel].point.Value
	end

	local lo, hi = 1, #channel
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if channel[mid].time <= time then
			lo = mid
		else
			hi = mid
		end
	end

	local a, b = channel[lo], channel[hi]
	local duration = b.time - a.time
	if duration <= 0 then
		return b.point.Value
	end

	local alpha = math.clamp((time - a.time) / duration, 0, 1)
	local style = a.point.Interpolation or "Bezier"
	if style == "Constant" then
		return a.point.Value
	end

	if style == "ConstantNext" then
		return alpha == 0 and a.point.Value or b.point.Value
	end

	if style == "Linear" then
		return a.point.Value + (b.point.Value - a.point.Value) * alpha
	end

	if style == "Legacy" then
		return a.point.Value
			+ (b.point.Value - a.point.Value) * Easing.apply(alpha, a.point.Easing or a.key)
	end

	if
		a.point.HandleType == "Vector"
		and b.point.HandleType == "Vector"
		and not a.point.BlenderHandles
		and not b.point.BlenderHandles
	then
		return a.point.Value + (b.point.Value - a.point.Value) * alpha
	end

	local outgoingTime, outgoingValue, incomingTime, incomingValue = segmentValues(channel, lo)
	local x1 = (outgoingTime - a.time) / duration
	local x2 = (incomingTime - a.time) / duration
	return Bezier.cubic(
		a.point.Value,
		outgoingValue,
		incomingValue,
		b.point.Value,
		Bezier.parameter(alpha, x1, x2)
	)
end

function Curves.quaternionReference(bucket, time)
	local entry = Curves.compile(bucket)
	if not entry.quaternionReferences then
		local points = {}
		for _, key in bucket or {} do
			if
				not key.Disabled
				and not key.GraphOnly
				and typeof(key.C0) == "CFrame"
				and type(key.Time) == "number"
			then
				local q, complete = {}, true
				for _, axis in { "w", "x", "y", "z" } do
					local channel = key.Channels and key.Channels["qrot_" .. axis]
					if not channel or channel.Disabled or type(channel.Value) ~= "number" then
						complete = false
						break
					end

					q[axis] = channel.Value
				end

				table.insert(points, {
					time = key.Time,
					q = complete and Quaternion.normalize(q) or Quaternion.fromCFrame(key.C0),
				})
			end
		end

		table.sort(points, function(a, b)
			return a.time < b.time
		end)
		for i = 2, #points do
			points[i].q = Quaternion.alignSign(points[i - 1].q, points[i].q)
		end

		entry.quaternionReferences = points
	end

	local points = entry.quaternionReferences
	if #points == 0 then
		return nil
	end

	local low, high = 1, #points
	while low <= high do
		local mid = (low + high) // 2
		if points[mid].time <= time then
			low = mid + 1
		else
			high = mid - 1
		end
	end

	local a, b = points[math.max(1, high)], points[math.min(#points, high + 1)]
	if a == b or b.time <= a.time then
		return a.q
	end

	return Quaternion.slerp(a.q, b.q, math.clamp((time - a.time) / (b.time - a.time), 0, 1))
end

local TRANSFORM_IDS = { "loc_x", "loc_y", "loc_z", "rot_x", "rot_y", "rot_z" }
local QUATERNION_IDS = { "qrot_w", "qrot_x", "qrot_y", "qrot_z" }
local QUATERNION_AXES = { "w", "x", "y", "z" }
local SCALE_IDS = { "scale_x", "scale_y", "scale_z" }

function Curves.cframe(bucket, time, base, motor, loopEndTime, rest)
	local entry = Curves.compile(bucket)
	if not entry.hasGraph then
		return base
	end

	local p = base.Position
	local values = { loc_x = p.X, loc_y = p.Y, loc_z = p.Z }
	local ex, ey, ez = Curves.euler(base, entry.rotationOrder)
	local rx, ry, rz = math.rad(ex), math.rad(ey), math.rad(ez)
	values.rot_x, values.rot_y, values.rot_z = math.deg(rx), math.deg(ry), math.deg(rz)
	local hasPosition, hasRotation = false, false
	local anyDisabled = motor ~= nil and motor:GetAttribute("EclipseChannelDisabledAny") == true
	for _, id in TRANSFORM_IDS do
		local channel = entry.channels[id]
		local disabled = anyDisabled
			and (motor:GetAttribute("EclipseChannelDisabled_" .. id) == true)
		if (disabled or not channel) and entry.rotationOrder and id:sub(1, 4) == "rot_" then
			local r = rest
				or motor and motor:GetAttribute("EclipseAnimatorDefaultC0")
				or CFrame.identity
			local x, y, z = Curves.euler(r, entry.rotationOrder)
			values[id] = ({ rot_x = x, rot_y = y, rot_z = z })[id]
			hasRotation = true
		elseif channel and not disabled then
			values[id] = Curves.value(channel, time, loopEndTime)
			if string.sub(id, 1, 3) == "rot" then
				hasRotation = true
			else
				hasPosition = true
			end
		end
	end

	local hasQuaternion = false
	for _, id in QUATERNION_IDS do
		if
			entry.channels[id]
			and not (anyDisabled and motor:GetAttribute("EclipseChannelDisabled_" .. id))
		then
			hasQuaternion = true
			break
		end
	end

	if not hasPosition and not hasRotation and not hasQuaternion then
		return base
	end

	local rotation = hasRotation
			and Curves.rotation(values.rot_x, values.rot_y, values.rot_z, entry.rotationOrder)
		or base.Rotation
	if hasQuaternion then
		local q = Quaternion.fromCFrame(rotation)
		local reference = Curves.quaternionReference(bucket, time)
		if reference then
			q = Quaternion.alignSign(reference, q)
		end

		const aligned = entry.alignedQuaternion
		for _, axis in QUATERNION_AXES do
			local id = "qrot_" .. axis
			if
				entry.channels[id]
				and not (anyDisabled and motor:GetAttribute("EclipseChannelDisabled_" .. id))
			then
				q[axis] = Curves.value(aligned and aligned[id] or entry.channels[id], time, loopEndTime)
			end
		end

		q = Quaternion.normalize(q)
		rotation = CFrame.new(0, 0, 0, q.x, q.y, q.z, q.w)
	end

	return CFrame.new(values.loc_x, values.loc_y, values.loc_z) * rotation
end

function Curves.scale(bucket, time, base, motor, loopEndTime)
	local entry = Curves.compile(bucket)
	local output = base
	local anyDisabled = motor ~= nil and motor:GetAttribute("EclipseChannelDisabledAny") == true
	for _, id in SCALE_IDS do
		if
			entry.channels[id]
			and not (anyDisabled and motor:GetAttribute("EclipseChannelDisabled_" .. id))
		then
			if output == base then
				output = base and table.clone(base) or { scale_x = 1, scale_y = 1, scale_z = 1 }
			end

			output[id] = Curves.value(entry.channels[id], time, loopEndTime)
		end
	end

	return output
end

function Curves.recordPose(bucket, key, cframe, channelIds)
	local compiled = Curves.compile(bucket)
	key.GraphOnly = nil
	if not compiled.hasGraph then
		return
	end

	local chosen
	if channelIds then
		chosen = {}
		for _, id in ipairs(channelIds) do
			chosen[id] = true
		end
	end

	local order = compiled.rotationOrder
	local referenceEuler
	if order then
		referenceEuler = {}
		local rx, ry, rz = Curves.euler(cframe, order)
		local fallback = { rx, ry, rz }
		for i, id in { "rot_x", "rot_y", "rot_z" } do
			referenceEuler[i] = compiled.channels[id]
					and Curves.value(compiled.channels[id], key.Time)
				or fallback[i]
		end
	end

	local ex, ey, ez = Curves.euler(cframe, order, referenceEuler)
	local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
	local q = Quaternion.fromCFrame(cframe)
	local reference, at
	for _, candidate in bucket do
		if candidate.Time and candidate.Time < key.Time and (not at or candidate.Time > at) then
			local value = {}
			local complete = true
			for _, axis in { "w", "x", "y", "z" } do
				local id = "qrot_" .. axis
				local p = candidate.GraphCurves and candidate.GraphCurves[id]
				local c = candidate.Channels and candidate.Channels[id]
				value[axis] = p and not p.Empty and p.Value or c and not c.Disabled and c.Value
				if value[axis] == nil then
					complete = false
				end
			end

			if complete then
				reference, at = value, candidate.Time
			end
		end
	end

	if reference then
		q = Quaternion.alignSign(reference, q)
	end

	local values = {
		qrot_w = q.w,
		qrot_x = q.x,
		qrot_y = q.y,
		qrot_z = q.z,
		loc_x = cframe.X,
		loc_y = cframe.Y,
		loc_z = cframe.Z,
		rot_x = math.deg(x),
		rot_y = math.deg(y),
		rot_z = math.deg(z),
	}
	for id in pairs(compiled.channels) do
		local rotation = string.sub(id, 1, 4) == "rot_"
		local include = not chosen or chosen[id]
		if rotation and chosen then
			include = chosen[id] or chosen.qrot_w or chosen.qrot_x or chosen.qrot_y or chosen.qrot_z
		end

		local scalar = key.Channels and key.Channels[id]
		local value = values[id] or (scalar and scalar.Value)
		if include and value ~= nil then
			key.GraphCurves = key.GraphCurves or {}
			local point = key.GraphCurves[id]
			if not point then
				point = Curves.newPoint(key, id)
				key.GraphCurves[id] = point
			end

			if rotation and point.Value then
				value = point.Value + ((value - point.Value + 180) % 360) - 180
			end

			point.Value, point.Empty = value, nil
			if rotation and order then
				point.RotationOrder = order
			end
		end
	end

	Curves.invalidate(bucket)
end

function Curves.filterRotation(bucket)
	local frames = {}
	for frame in bucket do
		table.insert(frames, frame)
	end

	table.sort(frames)
	local previousQ, previousEuler
	local previousAxis = {}
	local changed = false

	local function pointValue(key, id)
		local p = key.GraphCurves and key.GraphCurves[id]
		if p and not p.Empty then
			return p.Value
		end

		local c = key.Channels and key.Channels[id]
		return c and not c.Disabled and c.Value
	end

	local function remap(key, id, value, multiplier)
		local point = key.GraphCurves and key.GraphCurves[id]
		local channel = key.Channels and key.Channels[id]
		local old = pointValue(key, id)
		if old == nil or math.abs(value - old) < 1e-7 and multiplier ~= -1 then
			return
		end

		changed = true
		if channel then
			channel.Value = value
		end

		if point then
			point.Value = value
			for _, side in { "In", "Out" } do
				if point[side] then
					point[side][2] *= multiplier or 1
				end
			end

			if point.BlenderHandles then
				for _, handle in point.BlenderHandles do
					if type(handle) == "table" and type(handle[2]) == "number" then
						handle[2] = handle[2] * (multiplier or 1)
					end
				end
			end
		end
	end

	local function near(x, r)
		return r + (x - r + 180) % 360 - 180
	end

	for _, frame in frames do
		local key = bucket[frame]
		local q = {
			w = pointValue(key, "qrot_w"),
			x = pointValue(key, "qrot_x"),
			y = pointValue(key, "qrot_y"),
			z = pointValue(key, "qrot_z"),
		}
		if q.w and q.x and q.y and q.z then
			local aligned = previousQ and Quaternion.alignSign(previousQ, q) or q
			if aligned ~= q then
				for _, axis in { "w", "x", "y", "z" } do
					remap(key, "qrot_" .. axis, aligned[axis], -1)
				end
			end

			previousQ = aligned
		end

		local x, y, z = pointValue(key, "rot_x"), pointValue(key, "rot_y"), pointValue(key, "rot_z")
		if x and y and z then
			local v = { x, y, z }
			if previousEuler then
				local a = {
					near(x, previousEuler[1]),
					near(y, previousEuler[2]),
					near(z, previousEuler[3]),
				}
				local order = Curves.rotationOrder(bucket) or "XYZ"
				local middle = ({ X = 1, Y = 2, Z = 3 })[order:sub(2, 2)]
				local b = { x, y, z }
				for i = 1, 3 do
					b[i] = near(i == middle and 180 - b[i] or b[i] + 180, previousEuler[i])
				end

				local function distance(p)
					local n = 0
					for i = 1, 3 do
						n += (p[i] - previousEuler[i]) ^ 2
					end

					return n
				end

				local alternate = distance(b) < distance(a)
				v = alternate and b or a
				for i, axis in { "x", "y", "z" } do
					remap(key, "rot_" .. axis, v[i], alternate and i == middle and -1 or 1)
				end
			end

			previousEuler = v
		end

		for _, axis in { "x", "y", "z" } do
			local id = "rot_" .. axis
			local value = pointValue(key, id)
			if value ~= nil then
				if previousAxis[id] then
					value = near(value, previousAxis[id])
					remap(key, id, value, 1)
				end

				previousAxis[id] = value
			end
		end
	end

	if changed then
		Curves.invalidate(bucket)
	end

	return changed
end

return Curves
