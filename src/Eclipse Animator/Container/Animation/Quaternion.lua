--!nocheck
--!native
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Quaternion = {}

local function dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
end

local function negate(q)
	return { x = -q.x, y = -q.y, z = -q.z, w = -q.w }
end

local function alignSign(reference, q)
	if dot(reference, q) < 0 then
		return negate(q)
	end

	return q
end

local function multiply(a, b)
	return {
		x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}
end

local function conjugate(q)
	return { x = -q.x, y = -q.y, z = -q.z, w = q.w }
end

local function normalize(q)
	local mag2 = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	if mag2 < 1e-20 then
		return { x = 0, y = 0, z = 0, w = 1 }
	end

	local inv = 1 / math.sqrt(mag2)
	return { x = q.x * inv, y = q.y * inv, z = q.z * inv, w = q.w * inv }
end

local function logUnit(q)
	local vMag2 = q.x * q.x + q.y * q.y + q.z * q.z
	if vMag2 < 1e-20 then
		return { x = 0, y = 0, z = 0, w = 0 }
	end

	local vMag = math.sqrt(vMag2)
	local w = math.clamp(q.w, -1, 1)
	local theta = math.atan2(vMag, w)
	local k = theta / vMag
	return { x = q.x * k, y = q.y * k, z = q.z * k, w = 0 }
end

local function expPure(q)
	local vMag2 = q.x * q.x + q.y * q.y + q.z * q.z
	if vMag2 < 1e-20 then
		return { x = 0, y = 0, z = 0, w = 1 }
	end

	local vMag = math.sqrt(vMag2)
	local cosV = math.cos(vMag)
	local k = math.sin(vMag) / vMag
	return { x = q.x * k, y = q.y * k, z = q.z * k, w = cosV }
end

local function slerp(a, b, t)
	b = alignSign(a, b)
	local cosTheta = dot(a, b)
	if cosTheta > 0.9995 then
		return normalize({
			x = a.x + t * (b.x - a.x),
			y = a.y + t * (b.y - a.y),
			z = a.z + t * (b.z - a.z),
			w = a.w + t * (b.w - a.w),
		})
	end

	cosTheta = math.clamp(cosTheta, -1, 1)
	local theta = math.acos(cosTheta)
	local sinTheta = math.sin(theta)
	local s0 = math.sin((1 - t) * theta) / sinTheta
	local s1 = math.sin(t * theta) / sinTheta
	return {
		x = s0 * a.x + s1 * b.x,
		y = s0 * a.y + s1 * b.y,
		z = s0 * a.z + s1 * b.z,
		w = s0 * a.w + s1 * b.w,
	}
end

local function squad(q1, q2, a, b, t)
	local r1 = slerp(q1, q2, t)
	local r2 = slerp(a, b, t)
	return slerp(r1, r2, 2 * t * (1 - t))
end

local function tangent(qPrev, qCur, qNext)
	qPrev = alignSign(qCur, qPrev)
	qNext = alignSign(qCur, qNext)
	local invCur = conjugate(qCur)
	local relNext = multiply(invCur, qNext)
	local relPrev = multiply(invCur, qPrev)
	local lNext = logUnit(relNext)
	local lPrev = logUnit(relPrev)
	local sum = {
		x = -(lNext.x + lPrev.x) * 0.25,
		y = -(lNext.y + lPrev.y) * 0.25,
		z = -(lNext.z + lPrev.z) * 0.25,
		w = 0,
	}
	return multiply(qCur, expPure(sum))
end

local function fromCFrame(cf)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cf:GetComponents()
	local trace = m00 + m11 + m22

	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		return {
			w = 0.25 * s,
			x = (m21 - m12) / s,
			y = (m02 - m20) / s,
			z = (m10 - m01) / s,
		}
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		return {
			w = (m21 - m12) / s,
			x = 0.25 * s,
			y = (m01 + m10) / s,
			z = (m02 + m20) / s,
		}
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		return {
			w = (m02 - m20) / s,
			x = (m01 + m10) / s,
			y = 0.25 * s,
			z = (m12 + m21) / s,
		}
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		return {
			w = (m10 - m01) / s,
			x = (m02 + m20) / s,
			y = (m12 + m21) / s,
			z = 0.25 * s,
		}
	end
end

local function rotationVector(a, b)
	local q = logUnit(multiply(conjugate(a), alignSign(a, b)))
	return Vector3.new(q.x, q.y, q.z)
end

local function advance(q, v)
	return normalize(multiply(q, expPure({ x = v.X, y = v.Y, z = v.Z, w = 0 })))
end

local function limited(v, limit)
	const length = v.Magnitude
	if length ~= length or length == math.huge then
		return Vector3.zero
	end

	return if length > limit then v * (limit / length) else v
end

local function velocity(before, current, after, leftTime, rightTime, leftLength, rightLength, mode)
	if not before or not after then
		return Vector3.zero
	end

	local left, right = -rotationVector(current, before), rotationVector(current, after)
	local v = (left / leftTime + right / rightTime) * 0.5
	if mode == "AutoClamped" then
		if left:Dot(right) <= 0 then
			return Vector3.zero
		end

		local limit = math.min(left.Magnitude / leftLength, right.Magnitude / rightLength)
		if v.Magnitude > limit then
			v = v.Unit * limit
		end
	end

	return v
end

function Quaternion.automaticBezier(segment, before, previous, following, after)
	previous, following = normalize(previous), normalize(following)
	following = alignSign(previous, following)
	local dt = segment.nextTime - segment.prevTime
	local out = segment.prevHandle == "Vector" and rotationVector(previous, following) / dt
		or velocity(
			before,
			previous,
			following,
			segment.beforeTime and segment.prevTime - segment.beforeTime,
			dt,
			segment.prevLeft,
			segment.prevRight,
			segment.prevHandle
		)
	local incoming = segment.nextHandle == "Vector" and -rotationVector(following, previous) / dt
		or velocity(
			previous,
			following,
			after,
			dt,
			segment.afterTime and segment.afterTime - segment.nextTime,
			segment.nextLeft,
			segment.nextRight,
			segment.nextHandle
		)
	const reach = math.min(rotationVector(previous, following).Magnitude * 0.5, math.pi * 0.5)
	local a = advance(previous, limited(out * segment.prevRight, reach))
	local b = advance(following, limited(-incoming * segment.nextLeft, reach))
	local u = segment.u
	local p, q, r = slerp(previous, a, u), slerp(a, b, u), slerp(b, following, u)
	return normalize(slerp(slerp(p, q, u), slerp(q, r, u), u))
end

Quaternion.alignSign = alignSign
Quaternion.fromCFrame = fromCFrame
Quaternion.slerp = slerp
Quaternion.squad = squad
Quaternion.tangent = tangent
Quaternion.normalize = normalize

return Quaternion
