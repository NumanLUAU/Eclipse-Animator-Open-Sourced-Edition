--!native
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Interp = {}

local Defaults = require("Defaults")
local Easing = require("Easing")
local Bezier = require("Bezier")
local Quat = require("Quaternion")
local ChannelEasing = require("ChannelEasing")
local PoseCache = require("cache")
local GraphCurves

local VECTOR_HANDLES = { Vector = true, Free = true }
local SMOOTH_HANDLES = { Automatic = true, Aligned = true, AutoClamped = true }
local FALLBACK_HANDLE = "AutoClamped"
const handleNames = {}
const channelViews = {}
const fieldViews = {}
const automaticViews = {}

local function normalizeHandleName(name)
	if type(name) ~= "string" then
		return nil
	end

	local cached = handleNames[name]
	if cached == nil then
		local stripped = string.gsub(name, "%s+", "")
		cached = (VECTOR_HANDLES[stripped] or SMOOTH_HANDLES[stripped]) and stripped or false
		handleNames[name] = cached
	end

	return cached or nil
end

local function viewName(field, channelId)
	if channelId then
		local name = channelViews[channelId]
		if not name then
			name = "channel:" .. channelId
			channelViews[channelId] = name
		end

		return name
	end

	if field then
		local name = fieldViews[field]
		if not name then
			name = "field:" .. field
			fieldViews[field] = name
		end

		return name
	end

	return "all"
end

local function automaticViewName(prefix, suffix)
	local names = automaticViews[prefix]
	if not names then
		names = {}
		automaticViews[prefix] = names
	end

	local name = names[suffix]
	if not name then
		name = prefix .. ":" .. suffix
		names[suffix] = name
	end

	return name
end

local function resolveHandleName(keyData)
	local own = keyData and normalizeHandleName(keyData.HandleType)
	if own then
		return own
	end

	return normalizeHandleName(Defaults.HandleType) or FALLBACK_HANDLE
end

local function clampedAxis(c, p, n, autoVal)
	if (c >= p and c >= n) or (c <= p and c <= n) then
		return 0
	end

	return autoVal
end

local function clampedTangent(curPos, leftPos, rightPos, autoTan)
	return Vector3.new(
		clampedAxis(curPos.X, leftPos.X, rightPos.X, autoTan.X),
		clampedAxis(curPos.Y, leftPos.Y, rightPos.Y, autoTan.Y),
		clampedAxis(curPos.Z, leftPos.Z, rightPos.Z, autoTan.Z)
	)
end

local function computeOutTangent(
	prevPrevD,
	prevPrevTime,
	prevD,
	nextD,
	segmentDt,
	handleName,
	field
)
	local curPos = prevD[field].Position
	local nextPos = nextD[field].Position

	if VECTOR_HANDLES[handleName] or not prevPrevD then
		return nextPos - curPos
	end

	local farPos = prevPrevD[field].Position
	local span = nextD.Time - prevPrevTime
	local scale = (span > 0) and (segmentDt / span) or 0
	local autoTan = (nextPos - farPos) * scale

	if handleName == "AutoClamped" then
		return clampedTangent(curPos, farPos, nextPos, autoTan)
	end

	return autoTan
end

local function computeInTangent(prevD, nextD, nextNextD, nextNextTime, segmentDt, handleName, field)
	local prevPos = prevD[field].Position
	local curPos = nextD[field].Position

	if VECTOR_HANDLES[handleName] or not nextNextD then
		return curPos - prevPos
	end

	local farPos = nextNextD[field].Position
	local span = nextNextTime - prevD.Time
	local scale = (span > 0) and (segmentDt / span) or 0
	local autoTan = (farPos - prevPos) * scale

	if handleName == "AutoClamped" then
		return clampedTangent(curPos, prevPos, farPos, autoTan)
	end

	return autoTan
end

function Interp.index(bucket, field, channelId)
	if not bucket then
		return nil
	end

	local cache = PoseCache.poseCache()
	if not cache or not cache.persistent then
		return nil
	end

	cache.keyIndexes = cache.keyIndexes or setmetatable({}, { __mode = "k" })
	local views = cache.keyIndexes[bucket]
	if not views then
		views = {}
		cache.keyIndexes[bucket] = views
	end

	local name = viewName(field, channelId)
	if views[name] ~= nil then
		return views[name] or nil
	end

	local ordered = (field or channelId) and Interp.index(bucket)
	if ordered then
		local filtered = {}
		for _, entry in ordered do
			local key = entry.key
			if channelId then
				local channel = key.Channels and key.Channels[channelId]
				if channel and channel.Value ~= nil then
					table.insert(filtered, entry)
				end
			elseif key[field] then
				table.insert(filtered, entry)
			end
		end

		views[name] = filtered
		return filtered
	end

	local index = {}
	for frame, key in bucket do
		if type(key) == "table" and type(key.Time) == "number" then
			local channel = channelId and key.Channels and key.Channels[channelId]
			if channelId and (not channel or channel.Value == nil) then
				continue
			end

			if not channelId and field and not key[field] then
				continue
			end

			if
				key.Time ~= key.Time
				or math.abs(key.Time) == math.huge
				or not field and not channelId and type(frame) ~= "number"
			then
				views[name] = false
				return nil
			end

			table.insert(index, { key = key, time = key.Time, frame = frame })
		end
	end

	table.sort(index, function(a, b)
		return a.time < b.time
	end)
	for i = 2, #index do
		if
			index[i].time == index[i - 1].time
			or not field and not channelId and index[i].frame <= index[i - 1].frame
		then
			views[name] = false
			return nil
		end
	end

	views[name] = index
	return index
end

function Interp.search(index, time)
	local low, high, previous = 1, #index, 0
	while low <= high do
		local mid = (low + high) // 2
		if index[mid].time <= time then
			previous = mid
			low = mid + 1
		else
			high = mid - 1
		end
	end

	return previous,
		if previous > 0 and index[previous].time == time then previous else previous + 1
end

local function findFlankingData(bucket, prevTime, nextTime, field, loopEndTime, channelId)
	local index = Interp.index(bucket, field, channelId)
	if index then
		local p = Interp.search(index, prevTime)
		if p > 0 and index[p].time == prevTime then
			p -= 1
		end

		local _, n = Interp.search(index, nextTime)
		if index[n] and index[n].time == nextTime then
			n += 1
		end

		local before, after = index[p], index[n]
		local bt, nt = before and before.time, after and after.time
		if loopEndTime and loopEndTime > 0 then
			if not before and #index >= 2 then
				before = index[#index - 1]
				bt = before.time - loopEndTime
			end

			if not after and #index >= 2 then
				after = index[2]
				nt = after.time + loopEndTime
			end
		end

		if bt and bt >= prevTime then
			before = nil
			bt = nil
		end

		if nt and nt <= nextTime then
			after = nil
			nt = nil
		end

		return before and before.key, bt, after and after.key, nt
	end

	local prevPrevD = nil
	local prevPrevTime = nil
	local nextNextD = nil
	local nextNextTime = nil

	local firstD, firstT = nil, nil
	local secondD, secondT = nil, nil
	local lastD, lastT = nil, nil
	local secondLastD, secondLastT = nil, nil
	local wrap = loopEndTime ~= nil and loopEndTime > 0

	for _, data in bucket do
		if not data or data.Time == nil then
			continue
		end

		if channelId then
			local channel = data.Channels and data.Channels[channelId]
			if not channel or channel.Value == nil then
				continue
			end
		elseif not data[field] then
			continue
		end

		local t = data.Time

		if t < prevTime and (not prevPrevTime or t > prevPrevTime) then
			prevPrevTime = t
			prevPrevD = data
		end

		if t > nextTime and (not nextNextTime or t < nextNextTime) then
			nextNextTime = t
			nextNextD = data
		end

		if wrap then
			if not firstT or t < firstT then
				secondD, secondT = firstD, firstT
				firstD, firstT = data, t
			elseif not secondT or t < secondT then
				secondD, secondT = data, t
			end

			if not lastT or t > lastT then
				secondLastD, secondLastT = lastD, lastT
				lastD, lastT = data, t
			elseif not secondLastT or t > secondLastT then
				secondLastD, secondLastT = data, t
			end
		end
	end

	if wrap then
		if not prevPrevD and secondLastD then
			prevPrevD = secondLastD
			prevPrevTime = secondLastT - loopEndTime
		end

		if not nextNextD and secondD then
			nextNextD = secondD
			nextNextTime = secondT + loopEndTime
		end
	end

	if prevPrevTime and prevPrevTime >= prevTime then
		prevPrevD, prevPrevTime = nil, nil
	end

	if nextNextTime and nextNextTime <= nextTime then
		nextNextD, nextNextTime = nil, nil
	end

	return prevPrevD, prevPrevTime, nextNextD, nextNextTime
end

local function hermiteCubic(p0, p1, m0, m1, t)
	local t2 = t * t
	local t3 = t2 * t
	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = -2 * t3 + 3 * t2
	local h11 = t3 - t2
	return p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11
end

local AUTO_HANDLES = { Automatic = true, AutoClamped = true }
local DEFAULT_BEZIER = { 0.42, 0, 0.58, 1 }
local QUATERNION_CHANNELS = { qrot_w = "w", qrot_x = "x", qrot_y = "y", qrot_z = "z" }

function Interp.usesAutomaticBezier(prevD, nextD)
	if not prevD or not nextD or prevD.PathTangentOut or nextD.PathTangentIn then
		return false
	end

	local style = prevD.EasingStyle or Defaults.EasingStyle
	if (typeof(style) == "EnumItem" and style.Name or style) ~= "Bezier" then
		return false
	end

	local prevHandle, nextHandle = resolveHandleName(prevD), resolveHandleName(nextD)
	if
		not (AUTO_HANDLES[prevHandle] or prevHandle == "Vector")
		or not (AUTO_HANDLES[nextHandle] or nextHandle == "Vector")
		or not (AUTO_HANDLES[prevHandle] or AUTO_HANDLES[nextHandle])
	then
		return false
	end

	local points = prevD.BezierPoints or Defaults.BezierPoints
	if points then
		for i, value in DEFAULT_BEZIER do
			if type(points[i]) ~= "number" or math.abs(points[i] - value) > 1e-7 then
				return false
			end
		end
	end

	return true
end

local function automaticSegment(before, beforeTime, prevD, nextD, after, afterTime, alpha)
	local prevTime, nextTime = prevD.Time, nextD.Time
	if not prevTime or not nextTime or nextTime <= prevTime then
		return nil
	end

	local prevHandle, nextHandle = resolveHandleName(prevD), resolveHandleName(nextD)
	local prevLeft, prevRight = Bezier.lengths(beforeTime, prevTime, nextTime, prevHandle)
	local nextLeft, nextRight = Bezier.lengths(prevTime, nextTime, afterTime, nextHandle)
	local duration = nextTime - prevTime
	return {
		beforeTime = beforeTime,
		prevTime = prevTime,
		nextTime = nextTime,
		afterTime = afterTime,
		prevHandle = prevHandle,
		nextHandle = nextHandle,
		prevLeft = prevLeft,
		prevRight = prevRight,
		nextLeft = nextLeft,
		nextRight = nextRight,
		u = Bezier.parameter(alpha, prevRight / duration, 1 - nextLeft / duration),
	}
end

local function automaticControls(segment, before, previous, following, after)
	local _, outgoing = Bezier.handles(
		before,
		previous,
		following,
		segment.beforeTime,
		segment.prevTime,
		segment.nextTime,
		segment.prevLeft,
		segment.prevRight,
		segment.prevHandle
	)
	local incoming = Bezier.handles(
		previous,
		following,
		after,
		segment.prevTime,
		segment.nextTime,
		segment.afterTime,
		segment.nextLeft,
		segment.nextRight,
		segment.nextHandle
	)
	return outgoing, incoming
end

local function automaticValue(segment, before, previous, following, after)
	local outgoing, incoming = automaticControls(segment, before, previous, following, after)
	return Bezier.cubic(previous, outgoing, incoming, following, segment.u)
end

local function automaticPosition(segment, before, previous, following, after)
	return Vector3.new(
		automaticValue(segment, before and before.X, previous.X, following.X, after and after.X),
		automaticValue(segment, before and before.Y, previous.Y, following.Y, after and after.Y),
		automaticValue(segment, before and before.Z, previous.Z, following.Z, after and after.Z)
	)
end

local function legacyAutomaticRotation(segment, beforeCF, prevCF, nextCF, afterCF)
	local previous = Quat.fromCFrame(prevCF)
	local following = Quat.alignSign(previous, Quat.fromCFrame(nextCF))
	local before = beforeCF and Quat.alignSign(previous, Quat.fromCFrame(beforeCF))
	local after = afterCF and Quat.alignSign(following, Quat.fromCFrame(afterCF))
	return Quat.normalize({
		w = automaticValue(
			segment,
			before and before.w,
			previous.w,
			following.w,
			after and after.w
		),
		x = automaticValue(
			segment,
			before and before.x,
			previous.x,
			following.x,
			after and after.x
		),
		y = automaticValue(
			segment,
			before and before.y,
			previous.y,
			following.y,
			after and after.y
		),
		z = automaticValue(
			segment,
			before and before.z,
			previous.z,
			following.z,
			after and after.z
		),
	})
end

local function automaticRotation(segment, beforeCF, prevCF, nextCF, afterCF, version)
	if version == 1 then
		return legacyAutomaticRotation(segment, beforeCF, prevCF, nextCF, afterCF)
	end

	return Quat.automaticBezier(
		segment,
		beforeCF and Quat.fromCFrame(beforeCF),
		Quat.fromCFrame(prevCF),
		Quat.fromCFrame(nextCF),
		afterCF and Quat.fromCFrame(afterCF)
	)
end

local function channelQuaternion(data)
	local channels = data.Channels
	if not channels then
		return nil
	end

	local w, x, y, z = channels.qrot_w, channels.qrot_x, channels.qrot_y, channels.qrot_z
	if
		not w
		or not x
		or not y
		or not z
		or type(w.Value) ~= "number"
		or type(x.Value) ~= "number"
		or type(y.Value) ~= "number"
		or type(z.Value) ~= "number"
	then
		return nil
	end

	return { w = w.Value, x = x.Value, y = y.Value, z = z.Value }
end


local function smoothedAutomaticValue(bucket, time, field, channelId, component, loopEndTime)
	local cache = PoseCache.poseCache()
	local views
	local name = automaticViewName(field or "channel", channelId or component)
	if cache and cache.persistent then
		cache.automaticBezier = cache.automaticBezier or setmetatable({}, { __mode = "k" })
		views = cache.automaticBezier[bucket]
		if not views then
			views = {}
			cache.automaticBezier[bucket] = views
		end
	end
	local channel = views and views[name]
	if channel == nil then
		local keys = {}
		for _, key in bucket do
			if type(key) == "table" and type(key.Time) == "number" then
				if field and typeof(key[field]) == "CFrame"
					or not field and key.Channels and key.Channels[channelId]
				then
					table.insert(keys, key)
				end
			end
		end
		table.sort(keys, function(a, b) return a.Time < b.Time end)
		channel = {}
		local previousQuaternion
		for i, key in keys do
			local easing = not field and ChannelEasing.resolve(key, channelId) or key
			local handle = resolveHandleName(easing)
			if key.QuaternionInterpolationVersion == 1
				or not Interp.usesAutomaticBezier(easing, easing)
				or i > 1 and key.Time <= keys[i - 1].Time
			then
				channel = false
				break
			end
			local value
			if component and (component == "w" or component == "x" or component == "y" or component == "z") then
				local q = field and Quat.fromCFrame(key[field]) or channelQuaternion(key)
				if not q then channel = false break end
				if previousQuaternion then q = Quat.alignSign(previousQuaternion, q) end
				previousQuaternion = q
				value = q[component]
			else
				value = field and key[field].Position[component] or key.Channels[channelId].Value
			end
			if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
				channel = false
				break
			end
			table.insert(channel, { time = key.Time, key = {}, point = {
				Value = value, Interpolation = "Bezier", HandleType = handle,
			} })
		end
		if channel and #channel < 2 then channel = false end
		if views then views[name] = channel end
	end
	if channel then
		GraphCurves = GraphCurves or require("GraphCurves")
		return GraphCurves.value(channel, time, loopEndTime)
	end
	return nil
end

function Interp.channel(bucket, prevD, nextD, alpha, channelId, previous, following, loopEndTime)
	prevD = ChannelEasing.resolve(prevD, channelId)
	nextD = ChannelEasing.resolve(nextD, channelId)
	local component = QUATERNION_CHANNELS[channelId]
	if component then
		local a, b = channelQuaternion(prevD), channelQuaternion(nextD)
		if a and b then
			previous = a[component]
			following = Quat.alignSign(a, b)[component]
		end
	end

	if Interp.usesAutomaticBezier(prevD, nextD) then
		local before, beforeTime, after, afterTime =
			findFlankingData(bucket, prevD.Time, nextD.Time, nil, loopEndTime, channelId)
		local segment = automaticSegment(before, beforeTime, prevD, nextD, after, afterTime, alpha)
		if segment then
			local beforeValue = before and before.Channels[channelId].Value
			local afterValue = after and after.Channels[channelId].Value
			local component = QUATERNION_CHANNELS[channelId]
			if component then
				local prevQuat, nextQuat = channelQuaternion(prevD), channelQuaternion(nextD)
				if prevQuat and nextQuat then
					local coupled = true
					for _, key in { prevD, nextD, before or prevD, after or nextD } do
						if not channelQuaternion(key) then
							coupled = false
							break
						end

						for id in QUATERNION_CHANNELS do
							local ch = key.Channels[id]
							if
								not ChannelEasing.equal(
									ch.Easing or {},
									key.Channels[channelId].Easing or {}
								)
								or ch.Disabled
								or (key.GraphCurves and key.GraphCurves[id])
							then
								coupled = false
								break
							end
						end
					end

					if coupled and prevD.QuaternionInterpolationVersion ~= 1 then
						return Quat.automaticBezier(
							segment,
							before and channelQuaternion(before),
							prevQuat,
							nextQuat,
							after and channelQuaternion(after)
						)[component]
					end

					nextQuat = Quat.alignSign(prevQuat, nextQuat)
					previous, following = prevQuat[component], nextQuat[component]
					local beforeQuat = before and channelQuaternion(before)
					local afterQuat = after and channelQuaternion(after)
					if beforeQuat then
						beforeValue = Quat.alignSign(prevQuat, beforeQuat)[component]
					end

					if afterQuat then
						afterValue = Quat.alignSign(nextQuat, afterQuat)[component]
					end
				end
			end

			if not component then
				local smoothed = smoothedAutomaticValue(bucket, prevD.Time + alpha * (nextD.Time - prevD.Time), nil, channelId, nil, loopEndTime)
				if smoothed ~= nil then return smoothed end
			end
			return automaticValue(segment, beforeValue, previous, following, afterValue)
		end
	end

	return previous + (following - previous) * Easing.apply(alpha, prevD)
end

local function validTangent(value)
	return typeof(value) == "Vector3" and value.Magnitude < 1e6
end

local function sanitizeTangents(key)
	if key.PathTangentOut ~= nil and not validTangent(key.PathTangentOut) then
		key.PathTangentOut = nil
	end

	if key.PathTangentIn ~= nil and not validTangent(key.PathTangentIn) then
		key.PathTangentIn = nil
	end
end

function Interp.tangents(bucket, prevD, nextD, loopEndTime, field)
	field = field or "C0"
	sanitizeTangents(prevD)
	sanitizeTangents(nextD)
	local prevTime = prevD.Time
	local nextTime = nextD.Time
	local segmentDt = (nextTime or 0) - (prevTime or 0)

	local prevPrevD, prevPrevTime, nextNextD, nextNextTime =
		findFlankingData(bucket, prevTime, nextTime, field, loopEndTime)

	local prevHandle = resolveHandleName(prevD)
	local nextHandle = resolveHandleName(nextD)

	if Interp.usesAutomaticBezier(prevD, nextD) then
		local segment =
			automaticSegment(prevPrevD, prevPrevTime, prevD, nextD, nextNextD, nextNextTime, 0)
		if segment then
			local before = prevPrevD and prevPrevD[field].Position
			local after = nextNextD and nextNextD[field].Position
			local previous, following = prevD[field].Position, nextD[field].Position
			local outX, inX = automaticControls(
				segment,
				before and before.X,
				previous.X,
				following.X,
				after and after.X
			)
			local outY, inY = automaticControls(
				segment,
				before and before.Y,
				previous.Y,
				following.Y,
				after and after.Y
			)
			local outZ, inZ = automaticControls(
				segment,
				before and before.Z,
				previous.Z,
				following.Z,
				after and after.Z
			)
			return (Vector3.new(outX, outY, outZ) - previous) * 3,
				(following - Vector3.new(inX, inY, inZ)) * 3
		end
	end

	local m0 = prevD.PathTangentOut
		or computeOutTangent(prevPrevD, prevPrevTime, prevD, nextD, segmentDt, prevHandle, field)
	local m1 = nextD.PathTangentIn
		or computeInTangent(prevD, nextD, nextNextD, nextNextTime, segmentDt, nextHandle, field)

	return m0, m1
end

function Interp.cframe(bucket, prevD, nextD, rawAlpha, field, loopEndTime)
	field = field or "C0"
	if not prevD or not nextD then
		return nil
	end

	local prevCF = prevD[field]
	local nextCF = nextD[field]
	if not prevCF or not nextCF then
		return nil
	end

	sanitizeTangents(prevD)
	sanitizeTangents(nextD)

	if
		prevCF == nextCF
		and prevD.Time
		and nextD.Time
		and not prevD.PathTangentOut
		and not nextD.PathTangentIn
	then
		local before, _, after =
			findFlankingData(bucket, prevD.Time, nextD.Time, field, loopEndTime)
		if (not before or before[field] == prevCF) and (not after or after[field] == prevCF) then
			return prevCF
		end
	end

	local style = prevD.EasingStyle or Defaults.EasingStyle
	local styleName = typeof(style) == "EnumItem" and style.Name or style
	if
		styleName == "Linear"
		or styleName == "Constant"
		or (styleName ~= "Bezier" and not prevD.PathTangentOut and not nextD.PathTangentIn)
	then
		return prevCF:Lerp(nextCF, Easing.apply(rawAlpha, prevD))
	end

	local prevHandle = resolveHandleName(prevD)
	local nextHandle = resolveHandleName(nextD)
	local manualTangents = (prevD.PathTangentOut ~= nil) or (nextD.PathTangentIn ~= nil)
	local smooth = manualTangents or not (VECTOR_HANDLES[prevHandle] and VECTOR_HANDLES[nextHandle])

	if
		Interp.usesAutomaticBezier(prevD, nextD)
		and prevD.Time
		and nextD.Time
		and nextD.Time > prevD.Time
	then
		local time = prevD.Time + rawAlpha * (nextD.Time - prevD.Time)
		local x = smoothedAutomaticValue(bucket, time, field, nil, "X", loopEndTime)
		local y = smoothedAutomaticValue(bucket, time, field, nil, "Y", loopEndTime)
		local z = smoothedAutomaticValue(bucket, time, field, nil, "Z", loopEndTime)
		local position = x ~= nil and y ~= nil and z ~= nil and Vector3.new(x, y, z) or nil
		local rotation
		local segment = true
		if not position or not rotation then
			local prevPrevD, prevPrevTime, nextNextD, nextNextTime =
				findFlankingData(bucket, prevD.Time, nextD.Time, field, loopEndTime)
			segment = automaticSegment(
				prevPrevD,
				prevPrevTime,
				prevD,
				nextD,
				nextNextD,
				nextNextTime,
				rawAlpha
			)
			if segment then
				local beforeCF = prevPrevD and prevPrevD[field]
				local afterCF = nextNextD and nextNextD[field]
				position = position
					or automaticPosition(
						segment,
						beforeCF and beforeCF.Position,
						prevCF.Position,
						nextCF.Position,
						afterCF and afterCF.Position
					)
				rotation = rotation
					or automaticRotation(
						segment,
						beforeCF,
						prevCF,
						nextCF,
						afterCF,
						prevD.QuaternionInterpolationVersion
					)
			end
		end

		if segment then
			return CFrame.new(
				position.X,
				position.Y,
				position.Z,
				rotation.x,
				rotation.y,
				rotation.z,
				rotation.w
			)
		end
	end

	local easedAlpha = Easing.apply(rawAlpha, prevD)

	local style = prevD.EasingStyle or Defaults.EasingStyle
	local styleName = typeof(style) == "EnumItem" and style.Name or style
	if styleName == "Linear" or styleName == "Constant" then
		smooth = false
	end

	if not smooth then
		return prevCF:Lerp(nextCF, easedAlpha)
	end

	local prevTime = prevD.Time
	local nextTime = nextD.Time
	if not prevTime or not nextTime then
		return prevCF:Lerp(nextCF, easedAlpha)
	end

	local segmentDt = nextTime - prevTime
	if segmentDt <= 0 then
		return prevCF:Lerp(nextCF, easedAlpha)
	end

	local prevPrevD, prevPrevTime, nextNextD, nextNextTime =
		findFlankingData(bucket, prevTime, nextTime, field, loopEndTime)

	local m0 = prevD.PathTangentOut
		or computeOutTangent(prevPrevD, prevPrevTime, prevD, nextD, segmentDt, prevHandle, field)
	local m1 = nextD.PathTangentIn
		or computeInTangent(prevD, nextD, nextNextD, nextNextTime, segmentDt, nextHandle, field)

	local prevPos = prevCF.Position
	local nextPos = nextCF.Position
	local splinedPos = hermiteCubic(prevPos, nextPos, m0, m1, easedAlpha)

	local q1 = Quat.fromCFrame(prevCF)
	local q2 = Quat.fromCFrame(nextCF)
	local rotQuat = Quat.slerp(q1, q2, easedAlpha)

	return CFrame.new(
		splinedPos.X,
		splinedPos.Y,
		splinedPos.Z,
		rotQuat.x,
		rotQuat.y,
		rotQuat.z,
		rotQuat.w
	)
end

return Interp
