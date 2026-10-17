--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Export = {}
local MARKER = "EclipseFOVExport"
local SAMPLE = script.EclipseExportFOVSample.Source

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function Export.build(sequence, fallback)
	local fps = sequence:GetAttribute("FPS")
	fps = finite(fps) and fps > 0 and fps or 60
	local base = sequence:GetAttribute("EclipseCameraDefaultFOV")
	base = finite(base) and base or 70
	local values, times, duration, endFrame = {}, {}, 0, 0
	for _, key in sequence:GetKeyframes() do
		assert(finite(key.Time) and key.Time >= 0, "Invalid camera export time")
		duration = math.max(duration, key.Time)
		local exact = key:GetAttribute("EclipseExactFrame")
		local frame = finite(exact)
				and exact >= 0
				and math.abs(exact / fps - key.Time) <= math.max(0.00001, key.Time * 0.000001)
				and exact
			or key.Time * fps
		endFrame = math.max(endFrame, frame)
		local root = key:FindFirstChild("RootPart")
		local pose = root and root:FindFirstChild("FovPart")
		if pose and pose:IsA("Pose") and pose.Weight > 0 then
			local degrees = base + pose.CFrame.Y
			assert(finite(degrees), "Invalid camera FOV")
			if values[key.Time] == nil then
				table.insert(times, key.Time)
			end

			values[key.Time] = math.clamp(degrees, 1, 120)
		end
	end

	if #times == 0 then
		times[1], values[0] = 0, math.clamp(finite(fallback) and fallback or base, 1, 120)
	end

	table.sort(times)
	local folder = Instance.new("Folder")
	folder.Name = sequence.Name
	folder:SetAttribute(MARKER, true)
	folder:SetAttribute("FPS", fps)
	folder:SetAttribute("Duration", duration)
	folder:SetAttribute("Units", "Degrees")
	folder:SetAttribute("Loop", sequence.Loop)
	folder:SetAttribute(
		"ProjectId",
		sequence:GetAttribute("EclipseExportProjectId") or sequence:GetAttribute("EclipseProjectId")
	)
	local finalFrame = math.floor(endFrame + 0.0001)
	local cursor = 1
	for frame = 0, finalFrame do
		local time = frame / fps
		while cursor < #times and times[cursor + 1] <= time do
			cursor += 1
		end

		local first, last = times[cursor], times[math.min(cursor + 1, #times)]
		local alpha = last > first and math.clamp((time - first) / (last - first), 0, 1) or 0
		local value = Instance.new("NumberValue")
		value.Name = tostring(frame)
		value.Value = values[first] + (values[last] - values[first]) * alpha
		value:SetAttribute("Time", time)
		value:SetAttribute("Frame", frame)
		value.Parent = folder
	end

	return folder
end

function Export.write(rig, sequence, fallback, includeSampler)
	local part = rig:FindFirstChild("FovPart")
	assert(part and part:IsA("BasePart"), "Camera FovPart is missing")
	local output = Export.build(sequence, fallback)
	local root = part:FindFirstChild("FieldOfView")
	if root and (not root:IsA("Folder") or root:GetAttribute(MARKER) ~= true) then
		output:Destroy()
		error("FovPart.FieldOfView already contains user data; rename it before exporting", 0)
	end

	if not root then
		root = Instance.new("Folder")
		root.Name = "FieldOfView"
		root:SetAttribute(MARKER, true)
	end

	local previous
	for _, child in root:GetChildren() do
		if
			child:IsA("Folder")
			and child:GetAttribute(MARKER) == true
			and (
				child.Name == output.Name
				or output:GetAttribute("ProjectId") ~= nil
					and child:GetAttribute("ProjectId") == output:GetAttribute("ProjectId")
			)
		then
			previous = child
			break
		end
	end

	local name, suffix = output.Name, 2
	while root:FindFirstChild(output.Name) and root:FindFirstChild(output.Name) ~= previous do
		output.Name = name .. " (" .. suffix .. ")"
		suffix += 1
	end

	if includeSampler ~= false then
		local sampler = root:FindFirstChild("Sample")
		if not sampler then
			sampler = Instance.new("ModuleScript")
			sampler.Name = "Sample"
			sampler:SetAttribute(MARKER, true)
			sampler.Source = SAMPLE
			sampler.Parent = root
		elseif sampler:IsA("ModuleScript") and sampler:GetAttribute(MARKER) == true then
			sampler.Source = SAMPLE
		end
	end

	output.Parent = root
	root.Parent = part
	if previous then
		previous:Destroy()
	end

	return output
end

return Export
