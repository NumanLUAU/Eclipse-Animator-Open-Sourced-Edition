--!nocheck
--!native
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")
local HttpService = game:GetService("HttpService")
local Matrix = require("M")
local SoftIK = require("SoftIK")
local Preferences = require("Preferences")

local BoneIK = {}

local function worldOf(inst)
	if inst:IsA("Bone") then
		return worldOf(inst.Parent) * inst.CFrame * inst.Transform
	end

	return inst.CFrame
end

local function rotationBetween(a, b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.9999 then
		return CFrame.identity
	end

	if dot < -0.9999 then
		local ortho = math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis
		local axis = a:Cross(ortho).Unit
		return CFrame.fromAxisAngle(axis, math.pi)
	end

	return CFrame.fromAxisAngle(a:Cross(b).Unit, math.acos(dot))
end

local descCountCache = setmetatable({}, { __mode = "k" })

local function boneDescendantCount(bone)
	local cached = descCountCache[bone]
	if cached then
		return cached
	end

	local count = 0
	for _, d in ipairs(bone:GetDescendants()) do
		if d:IsA("Bone") and not d:GetAttribute("EclipseArmatureSkinningHelper") then
			count += 1
		end
	end

	descCountCache[bone] = count
	return count
end

local function selectChain(effector)
	local eps = 0.02
	local endPos = worldOf(effector).Position
	local knee = effector.Parent
	while knee and knee:IsA("Bone") and (worldOf(knee).Position - endPos).Magnitude <= eps do
		knee = knee.Parent
	end

	if not (knee and knee:IsA("Bone")) then
		return nil, nil
	end

	if boneDescendantCount(knee) > 60 then
		return nil, nil
	end

	local hip = knee.Parent
	while
		hip
		and hip:IsA("Bone")
		and (worldOf(hip).Position - worldOf(knee).Position).Magnitude <= eps
	do
		hip = hip.Parent
	end

	if hip and hip:IsA("Bone") then
		if boneDescendantCount(hip) > 4 * boneDescendantCount(knee) + 4 then
			hip = nil
		end
	else
		hip = nil
	end

	return knee, hip
end

local function setWorldCFrame(bone, desired)
	local parent = bone.Parent
	if not parent then
		return
	end

	bone.Transform = (worldOf(parent) * bone.CFrame):Inverse() * desired
end

local function worldUnder(rootWorld, root, targetBone)
	local chainBones = {}
	local b = targetBone
	while b and b ~= root do
		table.insert(chainBones, 1, b)
		b = b.Parent
	end

	local w = rootWorld
	for _, bn in ipairs(chainBones) do
		w = w * bn.CFrame * bn.Transform
	end

	return w
end

local DV, DR = {}, {}
local vectorMeta, rotationMeta = {}, {}

function DV.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vectorMeta)
end

DV.zero = DV.new(0, 0, 0)

function vectorMeta.__index(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end

	if k == "Unit" then
		return v / v.Magnitude
	end

	return DV[k]
end

function vectorMeta.__add(a, b)
	return DV.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function vectorMeta.__sub(a, b)
	return DV.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function vectorMeta.__unm(a)
	return DV.new(-a.X, -a.Y, -a.Z)
end

function vectorMeta.__mul(a, b)
	if type(a) == "number" then
		return DV.new(a * b.X, a * b.Y, a * b.Z)
	end

	return DV.new(a.X * b, a.Y * b, a.Z * b)
end

function vectorMeta.__div(a, b)
	return DV.new(a.X / b, a.Y / b, a.Z / b)
end

function DV:Dot(b)
	return self.X * b.X + self.Y * b.Y + self.Z * b.Z
end

function DV:Cross(b)
	return DV.new(
		self.Y * b.Z - self.Z * b.Y,
		self.Z * b.X - self.X * b.Z,
		self.X * b.Y - self.Y * b.X
	)
end

function DV:Lerp(b, t)
	return self + (b - self) * t
end

function DR.new(_, __, ___, ...)
	local values = { ... }
	if #values == 0 then
		values = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end

	return setmetatable(values, rotationMeta)
end

DR.identity = DR.new()

function rotationMeta.__index(r, k)
	if k == "RightVector" then
		return DV.new(r[1], r[4], r[7])
	end

	if k == "UpVector" then
		return DV.new(r[2], r[5], r[8])
	end

	if k == "LookVector" then
		return DV.new(-r[3], -r[6], -r[9])
	end

	return DR[k]
end

function rotationMeta.__mul(a, b)
	if b.X ~= nil then
		return DV.new(
			a[1] * b.X + a[2] * b.Y + a[3] * b.Z,
			a[4] * b.X + a[5] * b.Y + a[6] * b.Z,
			a[7] * b.X + a[8] * b.Y + a[9] * b.Z
		)
	end

	local r = {}
	for i = 0, 2 do
		for j = 1, 3 do
			r[i * 3 + j] = a[i * 3 + 1] * b[j] + a[i * 3 + 2] * b[j + 3] + a[i * 3 + 3] * b[j + 6]
		end
	end

	return setmetatable(r, rotationMeta)
end

function DR:Inverse()
	return DR.new(
		0,
		0,
		0,
		self[1],
		self[4],
		self[7],
		self[2],
		self[5],
		self[8],
		self[3],
		self[6],
		self[9]
	)
end

function DR.fromAxisAngle(v, angle)
	local x, y, z = v.X, v.Y, v.Z
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	return DR.new(
		0,
		0,
		0,
		t * x * x + c,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		t * y * y + c,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		t * z * z + c
	)
end

function DR.fromMatrix(_, x, y, z)
	return DR.new(0, 0, 0, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end

function DR:Lerp(b, t)
	return DR.read(DR.native(self):Lerp(DR.native(b), t))
end

function DR.read(cf)
	if getmetatable(cf) == rotationMeta then
		return cf
	end

	local _, __, ___, a, b, c, d, e, f, g, h, i = cf:GetComponents()
	return DR.new(0, 0, 0, a, b, c, d, e, f, g, h, i)
end

function DR.native(r)
	return CFrame.new(0, 0, 0, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

function DR.matrix(r)
	return { r[1], r[2], r[3], 0, r[4], r[5], r[6], 0, r[7], r[8], r[9], 0, 0, 0, 0, 1 }
end

local MAX_ANGLE_CHANGE = math.pi / 4

local function jacobiEigen3(a11, a12, a13, a22, a23, a33, makeVector)
	makeVector = makeVector or Vector3.new
	local a = { { a11, a12, a13 }, { a12, a22, a23 }, { a13, a23, a33 } }
	local V = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	for _ = 1, 48 do
		local off = math.abs(a[1][2]) + math.abs(a[1][3]) + math.abs(a[2][3])
		if off < 1e-16 then
			break
		end

		for p = 1, 2 do
			for q = p + 1, 3 do
				local apq = a[p][q]
				if apq ~= 0 then
					local theta = (a[q][q] - a[p][p]) / (2 * apq)
					local t
					if math.abs(theta) > 1e9 then
						t = 1 / (2 * theta)
					else
						t = (theta >= 0 and 1 or -1)
							/ (math.abs(theta) + math.sqrt(theta * theta + 1))
					end

					local c = 1 / math.sqrt(t * t + 1)
					local s = t * c
					local tau = s / (1 + c)
					local app = a[p][p]
					local aqq = a[q][q]
					a[p][p] = app - t * apq
					a[q][q] = aqq + t * apq
					a[p][q] = 0
					a[q][p] = 0
					for k = 1, 3 do
						if k ~= p and k ~= q then
							local akp = a[k][p]
							local akq = a[k][q]
							a[k][p] = akp - s * (akq + tau * akp)
							a[p][k] = a[k][p]
							a[k][q] = akq + s * (akp - tau * akq)
							a[q][k] = a[k][q]
						end
					end

					for k = 1, 3 do
						local vkp = V[k][p]
						local vkq = V[k][q]
						V[k][p] = vkp - s * (vkq + tau * vkp)
						V[k][q] = vkq + s * (vkp - tau * vkq)
					end
				end
			end
		end
	end

	return { a[1][1], a[2][2], a[3][3] }, {
		makeVector(V[1][1], V[2][1], V[3][1]),
		makeVector(V[1][2], V[2][2], V[3][2]),
		makeVector(V[1][3], V[2][3], V[3][3]),
	}
end

local function sdlsInvert(cols, beta, weight, wsqrt, dtheta, normWeights)
	local dof = #cols
	local a11, a12, a13, a22, a23, a33 = 0, 0, 0, 0, 0, 0
	for j = 1, dof do
		local cj = cols[j]
		a11 += cj.X * cj.X
		a12 += cj.X * cj.Y
		a13 += cj.X * cj.Z
		a22 += cj.Y * cj.Y
		a23 += cj.Y * cj.Z
		a33 += cj.Z * cj.Z
	end

	local vals, vecs =
		jacobiEigen3(a11, a12, a13, a22, a23, a33, type(cols[1]) == "table" and DV.new or nil)
	for j = 1, dof do
		dtheta[j] = 0
	end

	local vk = table.create(dof)
	for k = 1, 3 do
		local lam = vals[k]
		if lam < 0 then
			lam = 0
		end

		local w = math.sqrt(lam)
		if w > 1e-6 then
			local u = vecs[k]
			local wInv = 1 / w
			local alpha = u:Dot(beta) * wInv
			local M = 0
			for j = 1, dof do
				local vj = cols[j]:Dot(u) * wInv
				vk[j] = vj
				M += math.abs(vj) * cols[j].Magnitude
			end

			M *= wInv
			local gamma = MAX_ANGLE_CHANGE
			if M > 1 then
				gamma /= M
			end

			local maxD = 0
			for j = 1, dof do
				local ad = math.abs(vk[j] * alpha) * wsqrt[j]
				if ad > maxD then
					maxD = ad
				end
			end

			local damp = 1
			if gamma < maxD then
				damp = gamma / maxD
			end

			for j = 1, dof do
				local dofdamp = damp / weight[j]
				if dofdamp > 1 then
					dofdamp = 1
				end

				dtheta[j] += 0.8 * dofdamp * vk[j] * alpha
			end
		end
	end

	local mx = 0
	for j = 1, dof do
		dtheta[j] *= weight[j]
		local ab = math.abs(dtheta[j])
		if ab > mx then
			mx = ab
		end
	end

	if mx > MAX_ANGLE_CHANGE then
		local damp = MAX_ANGLE_CHANGE / (MAX_ANGLE_CHANGE + mx)
		for j = 1, dof do
			dtheta[j] *= damp
		end

		mx *= damp
	end

	if normWeights then
		mx = 0
		for j = 1, dof do
			mx = math.max(mx, math.abs(dtheta[j]) * (normWeights[j] or 1))
		end
	end

	return mx
end

local function solveTree(chain, goals, iterations, weights)
	local n, dof, m = #chain, #chain * 3, #goals * 3
	local total = 0
	for _, b in chain do
		total += b.length + (b.solverStart or Vector3.zero).Magnitude
	end

	local scale = total > 0 and 1 / total or 1
	local basis, starts, lengths, heads, rots, tails = {}, {}, {}, {}, {}, {}
	local weight, sqrtWeight = {}, {}
	for i, b in chain do
		basis[i] = b.solverBasis or CFrame.identity
		starts[i] = (b.solverStart or Vector3.zero) * scale
		lengths[i] = b.length * scale
		for axis = 1, 3 do
			local j = (i - 1) * 3 + axis
			weight[j] = weights[j] or 1
			sqrtWeight[j] = math.sqrt(weight[j])
		end
	end

	local ancestors = {}
	for g, goal in goals do
		local set = {}
		local i = goal.index
		while i > 0 do
			set[i] = true
			i = chain[i].solverParent or 0
		end

		ancestors[g] = set
	end

	local clampLength = 0.5 / n
	for iteration = 1, iterations do
		for i, b in chain do
			local p = b.solverParent or 0
			local rotation = p > 0 and rots[p] or CFrame.identity
			heads[i] = (p > 0 and tails[p] or Vector3.zero) + rotation * starts[i]
			rots[i] = rotation * b.solverRestBasis * basis[i]
			tails[i] = heads[i] + rots[i] * Vector3.new(0, lengths[i], 0)
		end

		local columns, beta, norms = {}, {}, {}
		for j = 1, dof do
			columns[j] = table.create(m, 0)
			norms[j] = 0
		end

		for g, goal in goals do
			local tip = tails[goal.index]
			local target = (goal.position - chain[1].head) * scale
			local error = target - tip
			if error.Magnitude > clampLength then
				error *= clampLength / error.Magnitude
			end

			local k = (g - 1) * 3
			beta[k + 1], beta[k + 2], beta[k + 3] = error.X, error.Y, error.Z
			for i in ancestors[g] do
				local offset = heads[i] - tip
				for axis, v in { rots[i].RightVector, rots[i].UpVector, -rots[i].LookVector } do
					local j = (i - 1) * 3 + axis
					local derivative = offset:Cross(v) * sqrtWeight[j]
					columns[j][k + 1], columns[j][k + 2], columns[j][k + 3] =
						derivative.X, derivative.Y, derivative.Z
					norms[j] += derivative.Magnitude
				end
			end
		end

		local a, v = {}, {}
		for i = 1, m do
			a[i] = table.create(m, 0)
			v[i] = table.create(m, 0)
			v[i][i] = 1
			for k = 1, i do
				local sum = 0
				for j = 1, dof do
					sum += columns[j][i] * columns[j][k]
				end

				a[i][k] = sum
				if k < i then
					a[k][i] = sum
				end
			end
		end

		for sweep = 1, 32 do
			local off = 0
			for p = 1, m - 1 do
				for q = p + 1, m do
					local apq = a[p][q]
					off += math.abs(apq)
					if math.abs(apq) < 1e-18 then
						continue
					end

					local theta = (a[q][q] - a[p][p]) / (2 * apq)
					local t = (theta >= 0 and 1 or -1)
						/ (math.abs(theta) + math.sqrt(theta * theta + 1))
					local c = 1 / math.sqrt(1 + t * t)
					local s = t * c
					local tau = s / (1 + c)
					a[p][p] -= t * apq
					a[q][q] += t * apq
					a[p][q] = 0
					a[q][p] = 0
					for k = 1, m do
						if k ~= p and k ~= q then
							local x, y = a[k][p], a[k][q]
							a[k][p] = x - s * (y + tau * x)
							a[p][k] = a[k][p]
							a[k][q] = y + s * (x - tau * y)
							a[q][k] = a[k][q]
						end

						local x, y = v[k][p], v[k][q]
						v[k][p] = x - s * (y + tau * x)
						v[k][q] = y + s * (x - tau * y)
					end
				end
			end

			if off < 1e-15 then
				break
			end
		end

		local delta = table.create(dof, 0)
		for k = 1, m do
			local singular = math.sqrt(math.max(0, a[k][k]))
			if singular <= 1e-6 then
				continue
			end

			local alpha, N = 0, 0
			for row = 1, m, 3 do
				local x, y, z = v[row][k], v[row + 1][k], v[row + 2][k]
				alpha += x * beta[row] + y * beta[row + 1] + z * beta[row + 2]
				N += math.sqrt(x * x + y * y + z * z)
			end

			alpha /= singular
			local right, M, maxDelta = {}, 0, 0
			for j = 1, dof do
				local x = 0
				for row = 1, m do
					x += columns[j][row] * v[row][k]
				end

				x /= singular
				right[j] = x
				M += math.abs(x) * norms[j]
				maxDelta = math.max(maxDelta, math.abs(x * alpha) * sqrtWeight[j])
			end

			M /= singular
			local gamma = MAX_ANGLE_CHANGE * (M > N and N / M or 1)
			local damp = maxDelta > gamma and gamma / maxDelta or 1
			for j = 1, dof do
				if weight[j] > 0 then
					delta[j] += 0.8 * math.min(1, damp / weight[j]) * right[j] * alpha
				end
			end
		end

		local maximum = 0
		for j = 1, dof do
			delta[j] *= weight[j]
			maximum = math.max(maximum, math.abs(delta[j]))
		end

		if maximum > MAX_ANGLE_CHANGE then
			local damp = MAX_ANGLE_CHANGE / (MAX_ANGLE_CHANGE + maximum)
			for j = 1, dof do
				delta[j] *= damp
			end

			maximum *= damp
		end

		for i = 1, n do
			local rotation = Vector3.new(delta[3 * i - 2], delta[3 * i - 1], delta[3 * i])
			if rotation.Magnitude > 1e-30 then
				basis[i] *= CFrame.fromAxisAngle(rotation.Unit, rotation.Magnitude)
			end
		end

		if maximum < 1e-3 and iteration > 11 then
			break
		end
	end

	local result = {}
	for i, b in chain do
		local raw = Matrix.fromCFrame(b.solverBasis)
		local transpose = CFrame.new(
			0,
			0,
			0,
			raw[1],
			raw[5],
			raw[9],
			raw[2],
			raw[6],
			raw[10],
			raw[3],
			raw[7],
			raw[11]
		)
		local delta = transpose * basis[i]
		result[i] = {
			delta = delta,
			deltaMatrix = Matrix.fromCFrame(delta),
			stretch = 1,
			resultInfluence = 1,
		}
	end

	return result
end

local function solveChain(
	chain,
	goalPos,
	polePos,
	poleAngle,
	iterations,
	weights,
	influence,
	stretchWeights,
	softPercent
)
	local n = #chain
	if n == 0 then
		return {}
	end

	local blenderInput = chain[1].solverBasis ~= nil or stretchWeights ~= nil
	local nativeChain = chain
	local NativeVector, NativeFrame = Vector3, CFrame
	local Vector3 = blenderInput and DV or Vector3
	local CFrame = blenderInput and DR or CFrame
	local fromFrame = blenderInput and DR.matrix or Matrix.fromCFrame
	if blenderInput then
		chain = {}
		for i, b in nativeChain do
			local copy = table.clone(b)
			copy.head = DV.new(b.head.X, b.head.Y, b.head.Z)
			copy.rot = DR.read(b.rot)
			if b.solverBasis then
				copy.solverBasis = DR.read(b.solverBasis)
			end

			if b.solverRestBasis then
				copy.solverRestBasis = DR.read(b.solverRestBasis)
			end

			if b.solverStart then
				copy.solverStart = DV.new(b.solverStart.X, b.solverStart.Y, b.solverStart.Z)
			end

			chain[i] = copy
		end

		goalPos = DV.new(goalPos.X, goalPos.Y, goalPos.Z)
		if polePos then
			polePos = DV.new(polePos.X, polePos.Y, polePos.Z)
		end
	end

	local rootHead = chain[1].head
	local restBasis = table.create(n)
	local originalBasis = table.create(n)
	local starts = table.create(n)
	local lengths = table.create(n)
	local total = 0
	for i = 1, n do
		local R = chain[i].rot
		if i == 1 then
			restBasis[1] = R
			starts[1] = Vector3.zero
		else
			local prevR = chain[i - 1].rot
			local prevTail = chain[i - 1].head + prevR * Vector3.new(0, chain[i - 1].length, 0)
			restBasis[i] = prevR:Inverse() * R
			starts[i] = prevR:Inverse() * (chain[i].head - prevTail)
		end

		lengths[i] = chain[i].length
		if chain[i].solverRestBasis then
			restBasis[i] = chain[i].solverRestBasis
			starts[i] = chain[i].solverStart or Vector3.zero
		end

		total += starts[i].Magnitude + lengths[i]
	end

	local s = total > 0 and 1 / total or 1
	softPercent =
		SoftIK.percent(softPercent == nil and Preferences.get("SoftIKPercent") or softPercent)

	if softPercent < 100 then
		goalPos = SoftIK.goal(rootHead, goalPos, total, softPercent)
	end

	local goal = (goalPos - rootHead) * s
	local pole = nil
	if polePos then
		pole = (polePos - rootHead) * s
	end

	if blenderInput and not pole and influence and influence < 1 then
		local tip = chain[n].head + chain[n].rot * Vector3.new(0, chain[n].length, 0)
		goal = ((tip - rootHead) * s):Lerp(goal, math.clamp(influence, 0, 1))
	end

	local originalLengths = table.create(n)
	local translationDof = {}
	local dof = 3 * n
	local segmentCount = n
	for i = 1, n do
		if stretchWeights and (stretchWeights[i] or 0) > 0 then
			dof += 1
			translationDof[i] = dof
			if
				not weights
				or (weights[3 * i - 2] or 1) > 0
				or (weights[3 * i - 1] or 1) > 0
				or (weights[3 * i] or 1) > 0
			then
				segmentCount += 1
			end
		end
	end

	local clampLen = 0
	for i = 1, n do
		starts[i] *= s
		lengths[i] *= s
		originalLengths[i] = lengths[i]
		clampLen += starts[i].Magnitude + lengths[i]
	end

	clampLen /= 2 * segmentCount
	local basis = table.create(n)
	for i = 1, n do
		local initial = chain[i].solverBasis or CFrame.identity
		originalBasis[i] = initial
		local hinge = chain[i].solverHinge
		if hinge then
			local raw = fromFrame(initial)
			local angle
			if hinge == 1 then
				angle = -math.atan2(raw[7], raw[11])
			elseif hinge == 2 then
				angle = 2 * math.atan2(raw[3] - raw[9], raw[1] + raw[6] + raw[11] + 1)
			else
				angle = -math.atan2(raw[2], raw[1])
			end

			initial = CFrame.fromAxisAngle(Matrix.axes[hinge], angle)
		end

		basis[i] = initial
	end

	local rootLin = CFrame.identity
	local gs = table.create(n)
	local glin = table.create(n)
	local gend = table.create(n)

	local function updateTransform()
		local curLin = rootLin
		local curPos = Vector3.zero
		for i = 1, n do
			local st = curPos + curLin * starts[i]
			local lin = curLin * restBasis[i] * basis[i]
			local en = st + lin * Vector3.new(0, lengths[i], 0)
			gs[i] = st
			glin[i] = lin
			gend[i] = en
			curLin = lin
			curPos = en
		end
	end

	if pole then
		updateTransform()
		local dir = gend[n] - gs[1]
		local poledir = goal - gs[1]
		local poleup = pole - gs[1]
		if dir.Magnitude > 1e-10 and poledir.Magnitude > 1e-10 and poleup.Magnitude > 1e-10 then
			dir = dir.Unit
			poledir = poledir.Unit
			poleup = poleup.Unit
			local rb = glin[1]
			local up = rb.RightVector * math.cos(poleAngle) - rb.LookVector * math.sin(poleAngle)
			local m0 = dir:Cross(up)
			local p0 = poledir:Cross(poleup)
			if m0.Magnitude > 1e-10 and p0.Magnitude > 1e-10 then
				m0 = m0.Unit
				p0 = p0.Unit
				local matT = CFrame.fromMatrix(Vector3.zero, m0, m0:Cross(dir), -dir)
				local polematT = CFrame.fromMatrix(Vector3.zero, p0, p0:Cross(poledir), -poledir)
				rootLin = polematT * matT:Inverse() * rootLin
			end
		end
	end

	local weight = table.create(dof, 1)
	local wsqrt = table.create(dof, 1)
	if weights then
		for j = 1, 3 * n do
			local wj = weights[j] or 1
			weight[j] = wj
			wsqrt[j] = math.sqrt(wj)
		end
	end

	local normWeights = stretchWeights and table.create(dof, 1) or nil
	for i, index in pairs(translationDof) do
		local w = math.clamp(stretchWeights[i], 0.01, 1)
		weight[index], wsqrt[index] = w, math.sqrt(w)
		normWeights[index] = 100
	end

	local cols = table.create(dof)
	local dtheta = table.create(dof, 0)
	local maxIter = iterations or 500
	for it = 1, maxIter do
		updateTransform()
		local pos = gend[n]
		local dpos = goal - pos
		local ln = dpos.Magnitude
		if ln > clampLen then
			dpos *= clampLen / ln
		end

		local idx = 0
		for i = 1, n do
			local p = gs[i] - pos
			local lin = glin[i]
			idx += 1
			cols[idx] = p:Cross(lin.RightVector) * wsqrt[idx]
			idx += 1
			cols[idx] = p:Cross(lin.UpVector) * wsqrt[idx]
			idx += 1
			cols[idx] = p:Cross(-lin.LookVector) * wsqrt[idx]
			if translationDof[i] then
				cols[translationDof[i]] = lin.UpVector * wsqrt[translationDof[i]]
			end
		end

		local mx = sdlsInvert(cols, dpos, weight, wsqrt, dtheta, normWeights)
		local limitedLengths = nil
		if next(translationDof) then
			limitedLengths = {}
			for _ = 1, n do
				local nearestBone, nearestDelta, nearestAbs = nil, 0, math.huge
				for i, index in pairs(translationDof) do
					local floorLength = (chain[i].minStretchLength or 0.001) * s
					if not limitedLengths[i] and lengths[i] + dtheta[index] < floorLength then
						local delta = floorLength - lengths[i]
						if math.abs(delta) < nearestAbs then
							nearestBone, nearestDelta, nearestAbs = i, delta, math.abs(delta)
						end
					end
				end

				if not nearestBone then
					break
				end

				local index = translationDof[nearestBone]
				limitedLengths[nearestBone] = lengths[nearestBone] + nearestDelta
				dpos -= cols[index] * nearestDelta
				cols[index] = Vector3.zero
				mx =
					math.max(nearestAbs, sdlsInvert(cols, dpos, weight, wsqrt, dtheta, normWeights))
			end
		end

		for i = 1, n do
			local dx = dtheta[3 * i - 2]
			local dy = dtheta[3 * i - 1]
			local dz = dtheta[3 * i]
			local th = math.sqrt(dx * dx + dy * dy + dz * dz)
			if th > 1e-30 then
				basis[i] *= CFrame.fromAxisAngle(Vector3.new(dx / th, dy / th, dz / th), th)
			end

			if translationDof[i] then
				lengths[i] = limitedLengths[i] or lengths[i] + dtheta[translationDof[i]]
			end
		end

		if mx < 1e-3 and it > 11 then
			break
		end
	end

	if pole then
		basis[1] = restBasis[1]:Inverse() * rootLin * restBasis[1] * basis[1]
	end

	for i = 1, n do
		if chain[i].solverBasis then
			local raw = fromFrame(originalBasis[i])
			local transpose = CFrame.new(
				0,
				0,
				0,
				raw[1],
				raw[5],
				raw[9],
				raw[2],
				raw[6],
				raw[10],
				raw[3],
				raw[7],
				raw[11]
			)
			basis[i] = transpose * basis[i]
		end
	end

	local resultInfluence = (pole or not blenderInput) and math.clamp(influence or 1, 0, 1) or 1
	if resultInfluence < 1 then
		for i = 1, n do
			basis[i] = CFrame.identity:Lerp(basis[i], resultInfluence)
		end
	end

	local out = table.create(n)
	local curRot = nil
	local curTail = nil
	local previousStretch, accumulatedStretch = 1, 1
	for i = 1, n do
		local rawStretch = originalLengths[i] > 0 and lengths[i] / originalLengths[i] or 1
		local relativeStretch = previousStretch > 0 and rawStretch / previousStretch or 1
		local parentStretch = accumulatedStretch
		accumulatedStretch *= 1 + (relativeStretch - 1) * resultInfluence
		local newHead
		local newRot
		if i == 1 then
			newRot = restBasis[1] * basis[1]
			newHead = rootHead
		else
			local prevRPre = chain[i - 1].rot
			local prevTailPre = chain[i - 1].head
				+ prevRPre * Vector3.new(0, chain[i - 1].length, 0)
			local startU = prevRPre:Inverse() * (chain[i].head - prevTailPre)
			newHead = curTail + curRot * startU * parentStretch
			newRot = curRot * restBasis[i] * basis[i]
		end

		curRot = newRot
		curTail = newHead + newRot * Vector3.new(0, chain[i].length * accumulatedStretch, 0)
		out[i] = {
			head = newHead,
			rot = newRot,
			tail = curTail,
			delta = basis[i],
			deltaMatrix = chain[i].solverBasis and fromFrame(basis[i]),
			stretch = rawStretch,
			resultInfluence = resultInfluence,
			length = chain[i].length * accumulatedStretch,
		}
		previousStretch = rawStretch
	end

	if blenderInput then
		for _, r in out do
			for _, key in { "head", "tail" } do
				local v = r[key]
				r[key] = NativeVector.new(v.X, v.Y, v.Z)
			end

			r.rot = DR.native(r.rot)
			r.delta = DR.native(r.delta)
		end
	end

	return out
end

local function worldOfClean(inst, dirty)
	if inst:IsA("Bone") then
		local w = worldOfClean(inst.Parent, dirty) * inst.CFrame
		if dirty[inst] then
			return w
		end

		return w * inst.Transform
	end

	return inst.CFrame
end

local function boneDepth(inst)
	local d = 0
	local cur = inst.Parent
	while cur and cur:IsA("Bone") do
		d += 1
		cur = cur.Parent
	end

	return d
end

function BoneIK.solveChainBones(effector, chainBones, followerSets, opts)
	local n = #chainBones
	if n == 0 then
		return false
	end

	local dirty = { [effector] = true }
	for _, b in ipairs(chainBones) do
		dirty[b] = true
	end

	local followerList = {}
	local followerSeg = {}
	if followerSets then
		for i, set in ipairs(followerSets) do
			for _, fb in ipairs(set) do
				if not dirty[fb] then
					dirty[fb] = true
					followerSeg[fb] = i
					table.insert(followerList, fb)
				end
			end
		end
	end

	local pre = table.create(n)
	for i, b in ipairs(chainBones) do
		pre[i] = worldOfClean(b, dirty)
	end

	local tipPre = worldOfClean(effector, dirty).Position
	local chain = table.create(n)
	for i = 1, n do
		local headPos = pre[i].Position
		local nextPos = i < n and pre[i + 1].Position or tipPre
		local len = (nextPos - headPos).Magnitude
		if len < 1e-5 then
			return false
		end

		chain[i] = { head = headPos, rot = pre[i].Rotation, length = len }
	end

	local fPre = {}
	for _, fb in ipairs(followerList) do
		fPre[fb] = worldOfClean(fb, dirty)
	end

	local res = solveChain(
		chain,
		opts.goal,
		opts.pole,
		opts.poleAngle or 0,
		opts.iterations,
		opts.weights,
		opts.influence,
		nil,
		opts.softPercent
	)
	for i, b in ipairs(chainBones) do
		local desired = CFrame.new(res[i].head) * res[i].rot
		b.Transform = (worldOf(b.Parent) * b.CFrame):Inverse() * desired
	end

	table.sort(followerList, function(x, y)
		return boneDepth(x) < boneDepth(y)
	end)
	for _, fb in ipairs(followerList) do
		local i = followerSeg[fb]
		local desired = (CFrame.new(res[i].head) * res[i].rot) * pre[i]:Inverse() * fPre[fb]
		fb.Transform = (worldOf(fb.Parent) * fb.CFrame):Inverse() * desired
	end

	local tipPos = res[n].tail
	local effAttach = worldOf(effector.Parent) * effector.CFrame
	local endRot = typeof(opts.endCF) == "CFrame" and opts.endCF.Rotation or effAttach.Rotation
	effector.Transform = effAttach:Inverse() * (CFrame.new(tipPos) * endRot)
	return true
end

function BoneIK.aimEffector(effector, targetPos, rotationDelta)
	local parentWorld = worldOf(effector.Parent)
	local rest = parentWorld * effector.CFrame
	local want = targetPos - rest.Position
	if want.Magnitude < 1e-4 and not rotationDelta then
		return false
	end

	local R = want.Magnitude >= 1e-4 and rotationBetween(rest.UpVector, want.Unit)
		or CFrame.identity
	if rotationDelta then
		R = rotationDelta * R
	end

	effector.Transform = rest:Inverse() * (CFrame.new(rest.Position) * (R * rest.Rotation))
	return true
end

function BoneIK.solve(effector, targetPos, polePos, endCF, fullPin)
	local knee, hip = selectChain(effector)
	if not knee then
		return false
	end

	local chainBones = hip and { hip, knee } or { knee }
	local goal = (fullPin and typeof(endCF) == "CFrame") and endCF.Position or targetPos
	return BoneIK.solveChainBones(effector, chainBones, nil, {
		goal = goal,
		pole = polePos,
		endCF = endCF,
	})
end

function BoneIK.chain(effector)
	local out = { effector }
	local knee, hip = selectChain(effector)
	if knee then
		table.insert(out, knee)
	end

	if hip then
		table.insert(out, hip)
	end

	return out
end

local boneLookupCache = setmetatable({}, { __mode = "k" })

local function findBone(rig, name)
	local map = boneLookupCache[rig]
	if not map then
		map = {}
		boneLookupCache[rig] = map
	end

	local cached = map[name]
	if cached and cached.Parent and cached.Name == name then
		return cached
	end

	for _, d in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			d:IsA("Bone")
			and not d:GetAttribute("EclipseArmatureSkinningHelper")
			and d.Name == name
		then
			map[name] = d
			return d
		end
	end

	map[name] = nil
	return nil
end

local function restAttach(bone)
	return worldOf(bone.Parent) * bone.CFrame
end

function BoneIK.solveAbsolute(effector, knee, hip, targetPos, polePos, endCF, fullPin)
	local chainBones = hip and { hip, knee } or { knee }
	local goal = (fullPin and typeof(endCF) == "CFrame") and endCF.Position or targetPos
	return BoneIK.solveChainBones(effector, chainBones, nil, {
		goal = goal,
		pole = polePos,
		endCF = endCF,
	})
end

local effCache = setmetatable({}, { __mode = "k" })

local function ikPoint(part)
	const size = part.Size
	local stored = part:GetAttribute("EclipseIKPoint")
	if typeof(stored) ~= "Vector3" then
		stored = part.PivotOffset.Position / size
		part:SetAttribute("EclipseIKPoint", stored)
	end

	return part.CFrame:PointToWorldSpace(stored * size)
end

function BoneIK.prepareAnchor(anchor, rig)
	if not anchor or not rig then
		return nil
	end

	local name = anchor:GetAttribute("EclipseIKEffector")
	if typeof(name) ~= "string" then
		return nil
	end

	local effector = effCache[anchor]
	if not (effector and effector.Parent and effector.Name == name) then
		effector = findBone(rig, name)
		effCache[anchor] = effector
	end

	if not effector then
		return nil
	end

	if
		typeof(anchor:GetAttribute("EclipseIKEndOffset")) ~= "CFrame"
		and typeof(anchor:GetAttribute("EclipseIKEndRot")) ~= "CFrame"
	then
		anchor:SetAttribute(
			"EclipseIKEndRot",
			anchor.CFrame.Rotation:Inverse() * worldOf(effector).Rotation
		)
	end

	if
		anchor:GetAttribute("EclipseIKChainCount") == 1
		and typeof(anchor:GetAttribute("EclipseIKChainBones")) ~= "string"
		and typeof(anchor:GetAttribute("EclipseIKAimParentRotation")) ~= "CFrame"
	then
		anchor:SetAttribute(
			"EclipseIKAimParentRotation",
			worldOf(effector.Parent).Rotation:Inverse() * anchor.CFrame.Rotation
		)
	end

	return effector
end

function BoneIK.solveForAnchor(anchor, rig)
	local effName = anchor:GetAttribute("EclipseIKEffector")
	if typeof(effName) ~= "string" or not rig then
		return false
	end

	local effector = effCache[anchor]
	if not (effector and effector.Parent and effector.Name == effName) then
		effector = nil
		for _, d in ipairs(RigTraversal.rigDescendants(rig)) do
			if
				d:IsA("Bone")
				and not d:GetAttribute("EclipseArmatureSkinningHelper")
				and d.Name == effName
			then
				effector = d
				break
			end
		end

		effCache[anchor] = effector
	end

	if not effector then
		return false
	end

	BoneIK.prepareAnchor(anchor, rig)
	local target = ikPoint(anchor)
	local chainCount = anchor:GetAttribute("EclipseIKChainCount")
	local chainNamesAttr = anchor:GetAttribute("EclipseIKChainBones")
	if chainCount == 1 and typeof(chainNamesAttr) ~= "string" then
		local reference = anchor:GetAttribute("EclipseIKAimParentRotation")
		local delta = anchor.CFrame.Rotation
			* (worldOf(effector.Parent).Rotation * reference):Inverse()
		delta = delta:Orthonormalize()
		local _, angle = delta:ToAxisAngle()
		return BoneIK.aimEffector(effector, target, math.abs(angle) > 1e-6 and delta or nil)
	end

	local polePos = nil
	local poleName = anchor:GetAttribute("EclipseIKPole")
	if typeof(poleName) == "string" and anchor.Parent then
		local poleAnchor = anchor.Parent:FindFirstChild(poleName)
		if poleAnchor and poleAnchor:IsA("BasePart") then
			polePos = ikPoint(poleAnchor)
		end
	end

	local endCF = nil
	local fullPin = false
	local endOff = anchor:GetAttribute("EclipseIKEndOffset")
	if typeof(endOff) == "CFrame" then
		endCF = anchor.CFrame * endOff
		fullPin = true
	else
		local endRotOff = anchor:GetAttribute("EclipseIKEndRot")
		if typeof(endRotOff) == "CFrame" then
			endCF = anchor.CFrame.Rotation * endRotOff.Rotation
		end
	end

	local goal
	local goalOff = anchor:GetAttribute("EclipseIKGoalOffset")
	if typeof(goalOff) == "Vector3" then
		goal = anchor.CFrame:PointToWorldSpace(goalOff)
	elseif fullPin then
		goal = endCF.Position
	else
		goal = target
	end

	local chainBones = nil
	if typeof(chainNamesAttr) == "string" then
		chainBones = {}
		for _, nm in ipairs(string.split(chainNamesAttr, ",")) do
			local cb = findBone(rig, nm)
			if not cb then
				chainBones = nil
				break
			end

			table.insert(chainBones, cb)
		end
	end

	if not chainBones then
		local kneeName = anchor:GetAttribute("EclipseIKChainKnee")
		local knee = typeof(kneeName) == "string" and findBone(rig, kneeName) or nil
		if knee then
			local hipName = anchor:GetAttribute("EclipseIKChainHip")
			local hip = typeof(hipName) == "string" and findBone(rig, hipName) or nil
			chainBones = hip and { hip, knee } or { knee }
		else
			local sKnee, sHip = selectChain(effector)
			if not sKnee then
				return false
			end

			chainBones = sHip and { sHip, sKnee } or { sKnee }
		end
	end

	local followerSets = nil
	local folAttr = anchor:GetAttribute("EclipseIKFollowers")
	if typeof(folAttr) == "string" then
		local okF, decoded = pcall(HttpService.JSONDecode, HttpService, folAttr)
		if okF and typeof(decoded) == "table" then
			followerSets = {}
			for i = 1, #chainBones do
				local set = {}
				local src = decoded[i]
				if typeof(src) == "table" then
					for _, nm in ipairs(src) do
						local fb = findBone(rig, nm)
						if fb then
							table.insert(set, fb)
						end
					end
				end

				followerSets[i] = set
			end
		end
	end

	local weights = nil
	local stAttr = anchor:GetAttribute("EclipseIKStiffness")
	if typeof(stAttr) == "string" then
		local okS, st = pcall(HttpService.JSONDecode, HttpService, stAttr)
		if okS and typeof(st) == "table" then
			weights = {}
			for i = 1, #chainBones do
				local bs = st[i]
				for d = 1, 3 do
					local sv = typeof(bs) == "table" and tonumber(bs[d]) or 0
					if not sv or sv ~= sv or sv < 0 then
						sv = 0
					end

					if sv > 0.99 then
						sv = 0.99
					end

					weights[3 * (i - 1) + d] = 1 - sv
				end
			end
		end
	end

	local lockAttr = anchor:GetAttribute("EclipseIKLocks")
	if typeof(lockAttr) == "string" then
		local okL, locks = pcall(HttpService.JSONDecode, HttpService, lockAttr)
		if okL and typeof(locks) == "table" then
			if not weights then
				weights = table.create(3 * #chainBones, 1)
			end

			for i = 1, #chainBones do
				local bl = locks[i]
				if typeof(bl) == "table" then
					for d = 1, 3 do
						if bl[d] == true then
							weights[3 * (i - 1) + d] = 0
						end
					end
				end
			end
		end
	end

	return BoneIK.solveChainBones(effector, chainBones, followerSets, {
		goal = goal,
		pole = polePos,
		poleAngle = tonumber(anchor:GetAttribute("EclipseIKPoleAngle")) or 0,
		iterations = tonumber(anchor:GetAttribute("EclipseIKIterations")) or 500,
		influence = tonumber(anchor:GetAttribute("EclipseIKInfluence")) or 1,
		weights = weights,
		endCF = endCF,
	})
end

local armCache = setmetatable({}, { __mode = "k" })

local function getRigEntry(rig)
	local entry = armCache[rig]
	if entry and entry.arm == false and os.clock() - entry.at < 2 then
		return nil
	end

	if not (entry and entry.arm and entry.arm.Parent) then
		entry = nil
		for _, d in ipairs(RigTraversal.rigDescendants(rig)) do
			if d:IsA("Model") and d:GetAttribute("EclipseArmature") then
				local list = {}
				for _, anchor in ipairs(d:GetChildren()) do
					if anchor:IsA("BasePart") and anchor:GetAttribute("EclipseIKEffector") then
						table.insert(list, anchor)
					end
				end

				entry = { arm = d, anchors = list }
				break
			end
		end

		armCache[rig] = entry or { arm = false, at = os.clock() }
	end

	return entry
end

function BoneIK.solveAllForRig(rig)
	local entry = getRigEntry(rig)
	if not entry then
		return
	end

	for _, anchor in ipairs(entry.anchors) do
		if anchor.Parent then
			BoneIK.solveForAnchor(anchor, rig)
		end
	end
end

function BoneIK.gatherChainBones(rig)
	local out = {}
	local entry = getRigEntry(rig)
	if not entry then
		return out
	end

	local seen = {}
	for _, anchor in ipairs(entry.anchors) do
		if anchor.Parent then
			local effName = anchor:GetAttribute("EclipseIKEffector")
			if typeof(effName) == "string" then
				local effector = effCache[anchor]
				if not (effector and effector.Parent and effector.Name == effName) then
					effector = nil
					for _, d in ipairs(RigTraversal.rigDescendants(rig)) do
						if
							d:IsA("Bone")
							and not d:GetAttribute("EclipseArmatureSkinningHelper")
							and d.Name == effName
						then
							effector = d
							break
						end
					end

					effCache[anchor] = effector
				end

				if effector then
					if not seen[effector] then
						seen[effector] = true
						table.insert(out, effector)
					end

					local names = {}
					local chainNamesAttr = anchor:GetAttribute("EclipseIKChainBones")
					if typeof(chainNamesAttr) == "string" then
						for _, nm in ipairs(string.split(chainNamesAttr, ",")) do
							table.insert(names, nm)
						end
					end

					local folAttr = anchor:GetAttribute("EclipseIKFollowers")
					if typeof(folAttr) == "string" then
						local okF, decoded = pcall(HttpService.JSONDecode, HttpService, folAttr)
						if okF and typeof(decoded) == "table" then
							for _, set in ipairs(decoded) do
								if typeof(set) == "table" then
									for _, nm in ipairs(set) do
										table.insert(names, nm)
									end
								end
							end
						end
					end

					local kneeName = anchor:GetAttribute("EclipseIKChainKnee")
					if typeof(kneeName) == "string" then
						table.insert(names, kneeName)
					end

					local hipName = anchor:GetAttribute("EclipseIKChainHip")
					if typeof(hipName) == "string" then
						table.insert(names, hipName)
					end

					for _, cname in ipairs(names) do
						local cb = findBone(rig, cname)
						if cb and not seen[cb] then
							seen[cb] = true
							table.insert(out, cb)
						end
					end

					for _, b in ipairs(BoneIK.chain(effector)) do
						if not seen[b] then
							seen[b] = true
							table.insert(out, b)
						end
					end
				end
			end
		end
	end

	for _, b in ipairs(BoneIK.gatherSyncBones(rig)) do
		if not seen[b] then
			seen[b] = true
			table.insert(out, b)
		end
	end

	return out
end

function BoneIK.syncDeform(rig)
	local entry = getRigEntry(rig)
	if not entry then
		return
	end

	if entry.arm:GetAttribute("EclipseHasDeformData") ~= true then
		return
	end

	local pairsList = entry.syncPairs
	if not pairsList then
		pairsList = {}
		for _, anchor in ipairs(entry.arm:GetChildren()) do
			if anchor:IsA("BasePart") then
				local fromName = anchor:GetAttribute("EclipseSyncFrom")
				local offset = anchor:GetAttribute("EclipseSyncOffset")
				if typeof(fromName) == "string" and typeof(offset) == "CFrame" then
					table.insert(
						pairsList,
						{ deform = anchor.Name, ctrl = fromName, offset = offset }
					)
				end
			end
		end

		entry.syncPairs = pairsList
	end

	for _, pair in ipairs(pairsList) do
		local deformBone = findBone(rig, pair.deform)
		local ctrlBone = findBone(rig, pair.ctrl)
		if deformBone and ctrlBone then
			local desired = worldOf(ctrlBone) * pair.offset
			local deformRest = worldOf(deformBone.Parent) * deformBone.CFrame
			deformBone.Transform = deformRest:Inverse() * desired
		end
	end
end

function BoneIK.gatherSyncBones(rig)
	local out = {}
	local entry = getRigEntry(rig)
	if not entry then
		return out
	end

	if entry.arm:GetAttribute("EclipseHasDeformData") ~= true then
		return out
	end

	for _, anchor in ipairs(entry.arm:GetChildren()) do
		if
			anchor:IsA("BasePart")
			and typeof(anchor:GetAttribute("EclipseSyncFrom")) == "string"
		then
			local b = findBone(rig, anchor.Name)
			if b then
				table.insert(out, b)
			end
		end
	end

	return out
end

function BoneIK.invalidateCache(rig)
	armCache[rig] = nil
end

BoneIK.worldOf = worldOf
BoneIK.solveRigidChain = solveChain
BoneIK.solveRigidTree = solveTree
return BoneIK
