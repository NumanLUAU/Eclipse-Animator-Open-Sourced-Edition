--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Binding = {}

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function Binding.matrix(value, scale)
	assert(typeof(value) == "table" and #value == 16, "Armature matrix must contain 16 numbers")
	for _, component in value do
		assert(finite(component), "Invalid armature matrix")
	end

	local x = Vector3.new(value[1], value[5], value[9])
	local y = Vector3.new(value[2], value[6], value[10])
	assert(x.Magnitude > 1e-9 and y.Magnitude > 1e-9, "Singular armature frame")
	x = x.Unit
	y = y - x * x:Dot(y)
	assert(y.Magnitude > 1e-9, "Singular armature frame")
	y = y.Unit
	return CFrame.fromMatrix(
		Vector3.new(value[4], value[8], value[12]) * (scale or 1),
		x,
		y,
		x:Cross(y)
	)
end

function Binding.world(target)
	if target:IsA("Bone") then
		return Binding.world(target.Parent) * target.CFrame
	elseif target:IsA("JointInstance") then
		return target.Part0.CFrame * target.C0
	end

	return target.CFrame
end

local function bestRotation(covariance)
	local s = covariance
	local n = {
		{ s[1][1] + s[2][2] + s[3][3], s[2][3] - s[3][2], s[3][1] - s[1][3], s[1][2] - s[2][1] },
		{ s[2][3] - s[3][2], s[1][1] - s[2][2] - s[3][3], s[1][2] + s[2][1], s[3][1] + s[1][3] },
		{ s[3][1] - s[1][3], s[1][2] + s[2][1], -s[1][1] + s[2][2] - s[3][3], s[2][3] + s[3][2] },
		{ s[1][2] - s[2][1], s[3][1] + s[1][3], s[2][3] + s[3][2], -s[1][1] - s[2][2] + s[3][3] },
	}
	local vectors = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } }
	for _ = 1, 40 do
		local a, b, maximum = 1, 2, 0
		for i = 1, 3 do
			for j = i + 1, 4 do
				if math.abs(n[i][j]) > maximum then
					a, b, maximum = i, j, math.abs(n[i][j])
				end
			end
		end

		if maximum < 1e-13 then
			break
		end

		local angle = 0.5 * math.atan2(2 * n[a][b], n[b][b] - n[a][a])
		local c, sn = math.cos(angle), math.sin(angle)
		local aa, bb, ab = n[a][a], n[b][b], n[a][b]
		for k = 1, 4 do
			if k ~= a and k ~= b then
				local ka, kb = n[k][a], n[k][b]
				n[k][a], n[a][k] = c * ka - sn * kb, c * ka - sn * kb
				n[k][b], n[b][k] = sn * ka + c * kb, sn * ka + c * kb
			end

			local va, vb = vectors[k][a], vectors[k][b]
			vectors[k][a], vectors[k][b] = c * va - sn * vb, sn * va + c * vb
		end

		n[a][a], n[b][b], n[a][b], n[b][a] =
			c * c * aa - 2 * c * sn * ab + sn * sn * bb,
			sn * sn * aa + 2 * c * sn * ab + c * c * bb,
			0,
			0
	end

	local largest = 1
	for i = 2, 4 do
		if n[i][i] > n[largest][largest] then
			largest = i
		end
	end

	return CFrame.new(
		0,
		0,
		0,
		vectors[2][largest],
		vectors[3][largest],
		vectors[4][largest],
		vectors[1][largest]
	)
end

function Binding.fit(pairs)
	assert(#pairs > 0, "No exported bones match this rig")
	local sourceCenter, targetCenter = Vector3.zero, Vector3.zero
	for _, pair in pairs do
		sourceCenter += pair.source.Position
		targetCenter += pair.target.Position
	end

	sourceCenter /= #pairs
	targetCenter /= #pairs
	local covariance = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
	local variance = 0
	for _, pair in pairs do
		local x, y = pair.source.Position - sourceCenter, pair.target.Position - targetCenter
		variance += x:Dot(x)
		local a, b = { x.X, x.Y, x.Z }, { y.X, y.Y, y.Z }
		for i = 1, 3 do
			for j = 1, 3 do
				covariance[i][j] += a[i] * b[j]
			end
		end
	end

	local rotation = if #pairs >= 3 and variance > 1e-10
		then bestRotation(covariance)
		else pairs[1].target.Rotation * pairs[1].source.Rotation:Inverse()
    local direction, spread
    for _, pair in pairs do
        local delta = pair.source.Position - sourceCenter
        if not spread or delta.Magnitude > spread then direction, spread = delta, delta.Magnitude end
    end
    local collinear = true
    if spread and spread > 1e-5 then
        for _, pair in pairs do
            if (pair.source.Position - sourceCenter):Cross(direction.Unit).Magnitude > spread * 1e-5 then
                collinear = false
                break
            end
        end
    end
    if collinear then
        local oriented = pairs[1].target.Rotation * pairs[1].source.Rotation:Inverse()
        local error, bestError = 0, 0
        for _, pair in pairs do
            local a, b = pair.source.Position - sourceCenter, pair.target.Position - targetCenter
            if a.Magnitude > 1e-7 and b.Magnitude > 1e-7 then
                error += (oriented * a.Unit - b.Unit).Magnitude
                bestError += (rotation * a.Unit - b.Unit).Magnitude
            end
        end
        if error <= bestError + 1e-5 then rotation = oriented end
    end
	local scale = 1
	if variance > 1e-10 then
		local numerator = 0
		for _, pair in pairs do
			numerator += (rotation * (pair.source.Position - sourceCenter)):Dot(
				pair.target.Position - targetCenter
			)
		end

		scale = numerator / variance
	end

	assert(scale > 1e-6 and finite(scale), "Selected rig has an incompatible rest skeleton")
	local frame = CFrame.new(targetCenter - rotation * (sourceCenter * scale)) * rotation
	local maximum, size = 0, 0
	for _, pair in pairs do
		maximum = math.max(
			maximum,
			(frame * (pair.source.Position * scale) - pair.target.Position).Magnitude
		)
		size = math.max(size, (pair.target.Position - targetCenter).Magnitude)
	end

	assert(
		maximum <= math.max(0.01, size * 0.025),
		"The exported rest skeleton does not match the selected rig"
	)
	return frame, scale, maximum
end

function Binding.followers(data)
	const objects, skinned, direct, cache = {}, {}, {}, {}
	for _, object in data.objects or {} do
		if typeof(object) == "table" and typeof(object.name) == "string" then
			objects[object.name] = object
		end
	end

	for _, item in data.mesh_bindings or {} do
		local active = nil
		for _, binding in item.bindings or {} do
			if binding.kind == "SKIN" then
				skinned[item.object] = true
			elseif
				typeof(binding.bone) == "string"
				and binding.mute ~= true
				and (tonumber(binding.influence) or 1) >= 1 - 1e-6
			then
				active = if active == nil then binding.bone else false
			end
		end

		if active then
			direct[item.object] = active
		end
	end

	local function resolve(name)
		if typeof(name) ~= "string" then
			return nil
		end

		const cached = cache[name]
		if cached ~= nil then
			return cached or nil
		end

		cache[name] = false
		const object = objects[name]
		local bone = false
		if object and not skinned[name] then
			if direct[name] then
				bone = direct[name]
			elseif object.parent_type == "BONE" and typeof(object.parent_bone) == "string" then
				bone = object.parent_bone
			elseif typeof(object.parent) == "string" then
				bone = resolve(object.parent) or false
			end
		end

		cache[name] = bone
		return bone or nil
	end

	return resolve, objects
end

function Binding.plan(data, rig)
	return require("ArmatureBindingPlan").build(data, rig)
end

return Binding
