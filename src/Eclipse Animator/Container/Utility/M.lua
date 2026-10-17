--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

type Matrix = { number }
local M = {}

function M.isFinite(a): boolean
	if typeof(a) ~= "table" then
		return false
	end

	for i = 1, 12 do
		local v = a[i]
		if typeof(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
			return false
		end
	end

	return true
end

function M.isFiniteCFrame(cf): boolean
	return typeof(cf) == "CFrame" and M.isFinite(M.fromCFrame(cf))
end

function M.isRigidCFrame(cf): boolean
	if typeof(cf) ~= "CFrame" then
		return false
	end

	local p = cf.Position
	if
		not (math.abs(p.X) < math.huge and math.abs(p.Y) < math.huge and math.abs(p.Z) < math.huge)
	then
		return false
	end

	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return math.abs(x:Dot(x) - 1) < 1e-3
		and math.abs(y:Dot(y) - 1) < 1e-3
		and math.abs(z:Dot(z) - 1) < 1e-3
		and math.abs(x:Dot(y)) < 1e-3
		and math.abs(x:Dot(z)) < 1e-3
		and math.abs(y:Dot(z)) < 1e-3
		and x:Dot(y:Cross(z)) > 0.999
end

function M.isFiniteVector(v): boolean
	return typeof(v) == "Vector3"
		and v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < math.huge
		and math.abs(v.Y) < math.huge
		and math.abs(v.Z) < math.huge
end

function M.identity(): Matrix
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end

function M.read(value)
	if typeof(value) == "CFrame" then
		return M.fromCFrame(value)
	end

	local out = M.identity()
	if typeof(value) ~= "table" then
		return out
	end

	for r = 1, 4 do
		for c = 1, 4 do
			local v = typeof(value[r]) == "table" and value[r][c] or value[(r - 1) * 4 + c]
			if typeof(v) == "number" and v == v and math.abs(v) < 1e30 then
				out[(r - 1) * 4 + c] = v
			end
		end
	end

	return out
end

function M.fromCFrame(cf: CFrame): Matrix
	local x, y, z, a, b, c, d, e, f, g, h, i = cf:GetComponents()
	return { a, b, c, x, d, e, f, y, g, h, i, z, 0, 0, 0, 1 }
end

function M.position(a: Matrix): Vector3
	return Vector3.new(a[4], a[8], a[12])
end

function M.column(a: Matrix, c: number): Vector3
	return Vector3.new(a[c], a[c + 4], a[c + 8])
end

function M.translation(v: Vector3): Matrix
	local a = M.identity()
	a[4], a[8], a[12] = v.X, v.Y, v.Z
	return a
end

function M.withPosition(a: Matrix, v: Vector3): Matrix
	local b = table.clone(a)
	b[4], b[8], b[12] = v.X, v.Y, v.Z
	return b
end

function M.mul(a: Matrix, b: Matrix): Matrix
	local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 =
		a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
	local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12 =
		b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12]
	return {
		a1 * b1 + a2 * b5 + a3 * b9,
		a1 * b2 + a2 * b6 + a3 * b10,
		a1 * b3 + a2 * b7 + a3 * b11,
		a1 * b4 + a2 * b8 + a3 * b12 + a4,
		a5 * b1 + a6 * b5 + a7 * b9,
		a5 * b2 + a6 * b6 + a7 * b10,
		a5 * b3 + a6 * b7 + a7 * b11,
		a5 * b4 + a6 * b8 + a7 * b12 + a8,
		a9 * b1 + a10 * b5 + a11 * b9,
		a9 * b2 + a10 * b6 + a11 * b10,
		a9 * b3 + a10 * b7 + a11 * b11,
		a9 * b4 + a10 * b8 + a11 * b12 + a12,
		0,
		0,
		0,
		1,
	}
end

local function inverseFinite(a: Matrix): Matrix
	local x, y, z = M.column(a, 1), M.column(a, 2), M.column(a, 3)
	local det = x:Dot(y:Cross(z))
	if det ~= det or math.abs(det) == math.huge or math.abs(det) < 1e-12 then
		error("Armature contains a singular transform", 2)
	end

	local r1, r2, r3 = y:Cross(z) / det, z:Cross(x) / det, x:Cross(y) / det
	local p = M.position(a)
	return {
		r1.X,
		r1.Y,
		r1.Z,
		-r1:Dot(p),
		r2.X,
		r2.Y,
		r2.Z,
		-r2:Dot(p),
		r3.X,
		r3.Y,
		r3.Z,
		-r3:Dot(p),
		0,
		0,
		0,
		1,
	}
end

function M.inverse(a: Matrix): Matrix
	if not M.isFinite(a) then
		error("Armature contains a non-finite transform", 2)
	end

	return inverseFinite(a)
end

function M.vector(a: Matrix, v: Vector3): Vector3
	return M.column(a, 1) * v.X + M.column(a, 2) * v.Y + M.column(a, 3) * v.Z
end

function M.point(a: Matrix, v: Vector3): Vector3
	return M.position(a) + M.vector(a, v)
end

function M.scale(a: Matrix): Vector3
	local x, y, z = M.column(a, 1), M.column(a, 2), M.column(a, 3)
	local sign = x:Dot(y:Cross(z)) < 0 and -1 or 1
	return Vector3.new(x.Magnitude, y.Magnitude, z.Magnitude) * sign
end

function M.toCFrame(a: Matrix): CFrame
	if not M.isFinite(a) then
		error("Armature contains a non-finite transform", 2)
	end

	local x, y, z = M.column(a, 1), M.column(a, 2), M.column(a, 3)
	if x.Magnitude < 1e-10 or y.Magnitude < 1e-10 or z.Magnitude < 1e-10 then
		local collapsed = CFrame.new(M.position(a))
		if not M.isFiniteCFrame(collapsed) then
			error("Armature position could not be resolved", 2)
		end

		return collapsed
	end

	if x:Dot(y:Cross(z)) < 0 then
		x, y, z = -x, -y, -z
	end

	local r1, r2, r3, r5, r6, r7, r9, r10, r11 = x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z
	for _ = 1, 8 do
		local rx, ry, rz =
			Vector3.new(r1, r5, r9), Vector3.new(r2, r6, r10), Vector3.new(r3, r7, r11)
		local det = rx:Dot(ry:Cross(rz))
		if det ~= det or math.abs(det) == math.huge or math.abs(det) < 1e-12 then
			error("Armature contains a singular transform", 2)
		end

		local ix, iy, iz = ry:Cross(rz) / det, rz:Cross(rx) / det, rx:Cross(ry) / det
		local a, b, c = (r1 + ix.X) * 0.5, (r2 + iy.X) * 0.5, (r3 + iz.X) * 0.5
		local d, e, f = (r5 + ix.Y) * 0.5, (r6 + iy.Y) * 0.5, (r7 + iz.Y) * 0.5
		local g, h, i = (r9 + ix.Z) * 0.5, (r10 + iy.Z) * 0.5, (r11 + iz.Z) * 0.5
		local change = math.max(
			math.abs(a - r1),
			math.abs(b - r2),
			math.abs(c - r3),
			math.abs(d - r5),
			math.abs(e - r6),
			math.abs(f - r7),
			math.abs(g - r9),
			math.abs(h - r10),
			math.abs(i - r11)
		)
		r1, r2, r3, r5, r6, r7, r9, r10, r11 = a, b, c, d, e, f, g, h, i
		if change < 1e-7 then
			break
		end
	end

	local result = CFrame.fromMatrix(
		M.position(a),
		Vector3.new(r1, r5, r9),
		Vector3.new(r2, r6, r10),
		Vector3.new(r3, r7, r11)
	):Orthonormalize()
	if not M.isRigidCFrame(result) then
		error("Armature rotation could not be resolved", 2)
	end

	return result
end

function M.compose(cf: CFrame, scale: Vector3): Matrix
	local a = M.fromCFrame(cf)
	for r = 0, 2 do
		a[r * 4 + 1] *= scale.X
		a[r * 4 + 2] *= scale.Y
		a[r * 4 + 3] *= scale.Z
	end

	return a
end

function M.normalized(a: Matrix): Matrix
	return M.fromCFrame(M.toCFrame(a))
end

function M.normalizedColumns(a: Matrix): Matrix
	local out = table.clone(a)
	for column = 1, 3 do
		local length = M.column(out, column).Magnitude
		if length > 1e-15 then
			out[column] /= length
			out[column + 4] /= length
			out[column + 8] /= length
		end
	end

	return out
end

function M.readStrict(value): Matrix
	if typeof(value) == "CFrame" then
		assert(M.isFiniteCFrame(value), "Invalid armature CFrame")
		return M.fromCFrame(value)
	end

	assert(typeof(value) == "table", "Expected an armature matrix")
	local result = M.identity()
	for row = 1, 4 do
		for column = 1, 4 do
			local v = typeof(value[row]) == "table" and value[row][column]
				or value[(row - 1) * 4 + column]
			if row <= 3 or v ~= nil then
				assert(
					typeof(v) == "number" and v == v and math.abs(v) < math.huge,
					"Invalid armature matrix component"
				)
				result[(row - 1) * 4 + column] = v
			end
		end
	end

	return result
end

function M.orthogonalizedY(a: Matrix, normalize: boolean?): Matrix
	normalize = normalize ~= false
	local y, x, z = M.column(a, 2), M.column(a, 1), M.column(a, 3)
	local len = y:Dot(y)
	if len > 0 then
		x -= y * (x:Dot(y) / len)
		z -= y * (z:Dot(y) / len)
		if normalize then
			y /= math.sqrt(len)
		end
	end

	local lengthX, lengthZ = x.Magnitude, z.Magnitude
	local nx = lengthX > 0 and x.Unit or Vector3.zero
	local nz = lengthZ > 0 and z.Unit or Vector3.zero
	local cosine = math.clamp(nx:Dot(nz), -1, 1)
	if math.abs(cosine) > 1e-4 and math.abs(cosine) < 1 - 1.1920928955078125e-7 then
		local angle = math.acos(cosine)
		local corrected = angle + (math.pi * 0.5 - angle) * 0.5
		nx -= nz * cosine
		nx = nx * (math.sin(corrected) / nx.Magnitude) + nz * math.cos(corrected)
		nz = nx:Cross(nz):Cross(nx).Unit
		if not normalize then
			local areaScale = math.sqrt(math.sin(angle))
			x, z = nx * (lengthX * areaScale), nz * (lengthZ * areaScale)
		end
	end

	if normalize then
		x, z = nx, nz
	end

	return { x.X, y.X, z.X, a[4], x.Y, y.Y, z.Y, a[8], x.Z, y.Z, z.Z, a[12], 0, 0, 0, 1 }
end

function M.lerp(a: Matrix, b: Matrix, t: number): Matrix
	if t <= 0 then
		return a
	elseif t >= 1 then
		return b
	end

	local position = M.position(a):Lerp(M.position(b), t)
	local same = true
	for row = 0, 2 do
		for column = 1, 3 do
			if a[row * 4 + column] ~= b[row * 4 + column] then
				same = false
				break
			end
		end
	end

	if same then
		return M.withPosition(a, position)
	end

	local rotationA, rotationB = M.toCFrame(a).Rotation, M.toCFrame(b).Rotation
	local stretchA = M.mul(M.fromCFrame(rotationA:Inverse()), M.withPosition(a, Vector3.zero))
	local stretchB = M.mul(M.fromCFrame(rotationB:Inverse()), M.withPosition(b, Vector3.zero))
	local stretch = table.clone(stretchA)
	for row = 0, 2 do
		for column = 1, 3 do
			local index = row * 4 + column
			stretch[index] = stretchA[index] + (stretchB[index] - stretchA[index]) * t
		end
	end

	return M.withPosition(M.mul(M.fromCFrame(rotationA:Lerp(rotationB, t)), stretch), position)
end

function M.translationScaled(a: Matrix, scale: number): Matrix
	local out = table.clone(a)
	out[4] *= scale
	out[8] *= scale
	out[12] *= scale
	return out
end

function M.error(a: Matrix, b: Matrix): number
	local max = 0
	for i = 1, 12 do
		max = math.max(max, math.abs(a[i] - b[i]))
	end

	return max
end

local validOrders = { XYZ = true, XZY = true, YXZ = true, YZX = true, ZXY = true, ZYX = true }
local affineOrders = {
	XYZ = { 1, 2, 3, 1 },
	XZY = { 1, 3, 2, -1 },
	YXZ = { 2, 1, 3, -1 },
	YZX = { 2, 3, 1, 1 },
	ZXY = { 3, 1, 2, 1 },
	ZYX = { 3, 2, 1, -1 },
}

function M.blenderAffineEuler(a: Matrix, order: string?): (Vector3, Vector3)
	local axes = affineOrders[order] or affineOrders.XYZ
	local i, j, k, parity = axes[1], axes[2], axes[3], axes[4]
	local sx, sy, sz = M.column(a, 1).Magnitude, M.column(a, 2).Magnitude, M.column(a, 3).Magnitude

	local function at(row: number, column: number): number
		local length = column == 1 and sx or column == 2 and sy or sz
		return length > 0 and a[(row - 1) * 4 + column] / length or 0
	end

	local ii, ji, ki = at(i, i), at(j, i), at(k, i)
	local cy = math.sqrt(ii * ii + ji * ji)
	local ei, ej, ek
	if cy > 0.0000375 then
		local kj, kk = at(k, j), at(k, k)
		ei, ej, ek = math.atan2(kj, kk), math.atan2(-ki, cy), math.atan2(ji, ii)
		local vi, vj, vk = math.atan2(-kj, -kk), math.atan2(-ki, -cy), math.atan2(-ji, -ii)
		if
			math.abs(vi) + math.abs(vj) + math.abs(vk)
			< math.abs(ei) + math.abs(ej) + math.abs(ek)
		then
			ei, ej, ek = vi, vj, vk
		end
	else
		ei, ej, ek = math.atan2(-at(j, k), at(j, j)), math.atan2(-ki, cy), 0
	end

	return Vector3.new(
		i == 1 and ei or j == 1 and ej or ek,
		i == 2 and ei or j == 2 and ej or ek,
		i == 3 and ei or j == 3 and ej or ek
	) * parity,
		Vector3.new(sx, sy, sz)
end

function M.euler(cf: CFrame, order: string?): Vector3
	order = validOrders[order] and order or "XYZ"
	local enum = Enum.RotationOrder[order:reverse()]
	local x, y, z = cf:ToEulerAngles(enum)
	return Vector3.new(x, y, z)
end

function M.fromEuler(v: Vector3, order: string?): CFrame
	order = validOrders[order] and order or "XYZ"
	return CFrame.fromEulerAngles(v.X, v.Y, v.Z, Enum.RotationOrder[order:reverse()])
end

M.axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
return M
