--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local CameraRig = require("CameraRig")
local State = require("State")
local Display = {}
local shapes = {}
local IDLE = Color3.fromRGB(151, 77, 235)
local SELECTED = Color3.fromRGB(255, 100, 184)
local FIRST_PERSON = Color3.fromRGB(86, 214, 255)

local function idle(rig)
	return rig:GetAttribute("EclipseFPV") == true and FIRST_PERSON or IDLE
end

local TARGET_SIZE = 0.7 * 0.75
local FOV_HIT_RADIUS = 16

function Display.segments(fov, aspect)
	local y = math.tan(math.rad(CameraRig.DEFAULT_FOV) * 0.5) * CameraRig.DEPTH
	local depth = CameraRig.displayDepth(fov)
	local x = y * (aspect or CameraRig.ASPECT)
	local a, b = Vector3.new(-x, y, -depth), Vector3.new(x, y, -depth)
	local c, d = Vector3.new(x, -y, -depth), Vector3.new(-x, -y, -depth)
	local tip = Vector3.new(0, y + math.max(0.24, y * 0.22), -depth)
	return {
		{ a, b },
		{ b, c },
		{ c, d },
		{ d, a },
		{ Vector3.zero, a },
		{ Vector3.zero, b },
		{ Vector3.zero, c },
		{ Vector3.zero, d },
		{ Vector3.new(-x * 0.16, y, -depth), tip },
		{ tip, Vector3.new(x * 0.16, y, -depth) },
		{ Vector3.new(-x * 0.16, y, -depth), Vector3.new(x * 0.16, y, -depth) },
	}
end

function Display.create(rig, parent, name)
	for folder, shape in shapes do
		if shape.rig == rig then
			folder:Destroy()
		end
	end

	local parents = { [parent] = true }
	for _, camera in workspace:GetChildren() do
		if camera:IsA("Camera") then
			parents[camera] = true
		end
	end

	for host in parents do
		for _, folder in host:GetChildren() do
			local source = folder:FindFirstChild("EclipseSourceRig")
			if
				folder:GetAttribute("EclipseCameraDisplay") == true
				and source
				and source:IsA("ObjectValue")
				and source.Value == rig
			then
				folder:Destroy()
			end
		end
	end

	local previous = parent:FindFirstChild(name)
	if previous then
		local source = previous:FindFirstChild("EclipseSourceRig")
		if not source or source:IsA("ObjectValue") and source.Value == rig then
			previous:Destroy()
		end
	end

	local folder = Instance.new("Folder")

	folder.Name = name
	require("Recovery").mark(folder)
	folder:SetAttribute("EclipseAnimator_BonesFolder", true)
	folder:SetAttribute("EclipseCameraDisplay", true)
	folder.Parent = parent
	local source = Instance.new("ObjectValue")

	source.Name, source.Value, source.Parent = "EclipseSourceRig", rig, folder
	require("Target").ensure(rig)
	for _, name in { "CamPart", "FovPart", "CamTarget" } do
		local proxy = Instance.new("Part")

		proxy.Name = name .. "_Bone"
		proxy:SetAttribute("SourcePartName", name)
		proxy:SetAttribute("EclipseCameraProxy", true)
		proxy.Size = Vector3.new(0.55, 0.55, 0.55)
		proxy.Transparency, proxy.Anchored = 1, true
		proxy.CanCollide, proxy.CanTouch, proxy.CanQuery = false, false, false
		proxy.Parent = folder
	end

	local lines = {}
	for i = 1, 11 do
		local line = Instance.new("LineHandleAdornment")

		line.Name = "Wire" .. i
		line.Visible = not State.PresentationHidden
		line.Adornee = folder.CamPart_Bone
		line.AlwaysOnTop, line.ZIndex = true, 3
		line.Thickness, line.Color3 = 2, idle(rig)
		line.Parent = folder
		table.insert(lines, line)
	end

	local circle = Instance.new("SphereHandleAdornment")

	circle.Name = "FOVHandle"
	circle.Visible = not State.PresentationHidden
	circle.Adornee = folder.FovPart_Bone
	circle.Radius = 0.14
	circle.AlwaysOnTop, circle.ZIndex = true, 4
	circle.Color3 = Color3.fromRGB(242, 171, 196)
	circle.Parent = folder
	local targetLines = {}
	local corners = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(corners, Vector3.new(x, y, z) * (TARGET_SIZE * 0.5))
			end
		end
	end

	for i, a in corners do
		for j = i + 1, #corners do
			local b = corners[j]
			if math.abs((a - b).Magnitude - TARGET_SIZE) > 0.001 then
				continue
			end

			local line = Instance.new("LineHandleAdornment")
			line.Name = "TargetEdge"
			line.Adornee = folder.CamTarget_Bone
			line.AlwaysOnTop = true
			line.ZIndex = 4
			line.Color3 = require("Target").COLOR
			line.Thickness = 2
			line.CFrame = CFrame.lookAt(a, b)
			line.Length = TARGET_SIZE
			line.Parent = folder
			table.insert(targetLines, { line = line, frame = line.CFrame })
		end
	end

	local fill = Instance.new("BoxHandleAdornment")
	fill.Name = "TargetCube"
	fill.Adornee = folder.CamTarget_Bone
	fill.Size = Vector3.one * TARGET_SIZE
	fill.AlwaysOnTop = true
	fill.ZIndex = 3
	fill.Transparency = 0.7
	fill.Color3 = require("Target").COLOR
	fill.Parent = folder
	folder.CamTarget_Bone.Size = fill.Size
	shapes[folder] =
		{ rig = rig, lines = lines, circle = circle, targetLines = targetLines, fill = fill }
	local ancestry = rig.AncestryChanged:Connect(function()
		if not rig.Parent then
			folder:Destroy()
		end
	end)
	folder.Destroying:Once(function()
		ancestry:Disconnect()
		shapes[folder] = nil
	end)
	Display.update(folder)
	return folder
end

function Display.update(folder, selected, visible)
	local shape = shapes[folder]
	if not shape then
		return
	end

	if not shape.rig.Parent or not folder.Parent then
		folder:Destroy()
		return
	end

	local nextSelected = selected == nil and shape.selected or selected == true
	local nextVisible = visible == nil and shape.visible ~= false or visible == true
	local shown = nextVisible
		and not require("Target").attachmentObject(shape.rig)
		and not State.PresentationHidden
		and not folder:GetAttribute("EclipsePlaybackHidden")
	local cf, fov = CameraRig.displayFrame(shape.rig), CameraRig.fov(shape.rig)
	local target = CameraRig.motor(shape.rig, "CamTarget")
	if target then
		folder.CamTarget_Bone.CFrame =
			CFrame.new((target.Part0.CFrame * target.C0 * target.C1:Inverse()).Position)
	end

	local selectedBone = State.Axis and State.Axis:GetSelectedBone()
	local targetShown = shown
		and target ~= nil
		and shape.rig:GetAttribute("EclipseHideCamTarget") ~= true
	local targetColor = selectedBone == folder.CamTarget_Bone and SELECTED
		or require("Target").COLOR
	if shape.targetShown ~= targetShown or shape.targetColor ~= targetColor then
		shape.targetShown, shape.targetColor = targetShown, targetColor
		folder.CamTarget_Bone.CanQuery = targetShown
		shape.fill.Visible = targetShown
		shape.fill.Color3 = targetColor
		for _, edge in shape.targetLines do
			local line = edge.line
			line.CFrame = edge.frame
			line.Visible = targetShown
			line.Color3 = targetColor
		end
	end

	if shape.cf ~= cf then
		folder.CamPart_Bone.CFrame = cf
		folder.FovPart_Bone.CFrame = cf
		shape.cf = cf
	end

	if shape.fov ~= fov then
		shape.segments = Display.segments(fov)
		for i, pair in shape.segments do
			local line = shape.lines[i]
			line.CFrame = CFrame.lookAt(pair[1], pair[2])
			line.Length = (pair[2] - pair[1]).Magnitude
		end

		shape.fov = fov
	end

	if shape.selected ~= nextSelected then
		for _, line in shape.lines do
			line.Color3 = nextSelected and SELECTED or idle(shape.rig)
		end

		shape.selected = nextSelected
	end

	shape.visible = nextVisible
	if shape.shown ~= shown then
		for _, line in shape.lines do
			line.Visible = shown
		end

		shape.circle.Visible = shown
		shape.shown = shown
	end
end

function Display.refresh()
	for folder in shapes do
		Display.update(folder)
	end
end

local function distance(point, a, b)
	local span = b - a
	local t = math.clamp((point - a):Dot(span) / math.max(span:Dot(span), 0.001), 0, 1)
	return (point - a - span * t).Magnitude
end

function Display.rayBox(origin, direction, frame, size)
	local point = frame:PointToObjectSpace(origin)
	local ray = frame:VectorToObjectSpace(direction)
	local near, far = 0, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local half = size[axis] * 0.5
		if math.abs(ray[axis]) < 1e-8 then
			if math.abs(point[axis]) > half then
				return
			end
		else
			local a, b = (-half - point[axis]) / ray[axis], (half - point[axis]) / ray[axis]
			if a > b then
				a, b = b, a
			end

			near, far = math.max(near, a), math.min(far, b)
			if near > far then
				return
			end
		end
	end

	return near
end

function Display.targetUnderMouse(camera, point, folders)
	if State.PresentationHidden then
		return
	end

	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local best, distance
	for _, folder in folders do
		local shape = shapes[folder]
		if not shape or not shape.fill.Visible then
			continue
		end

		local proxy = folder.CamTarget_Bone
		local hit = Display.rayBox(ray.Origin, ray.Direction, proxy.CFrame, proxy.Size)
		if hit and (not distance or hit < distance) then
			best, distance = proxy, hit
		end
	end

	return best
end

function Display.targetProxy(object)
	if State.PresentationHidden then
		return
	end

	for folder, shape in shapes do
		if not shape.fill.Visible then
			continue
		end

		local motor = CameraRig.motor(shape.rig, "CamTarget")
		if object == folder.CamTarget_Bone or motor and object == motor.Part1 then
			return folder.CamTarget_Bone
		end
	end
end

function Display.selectTarget(proxy)
	if not Display.targetProxy(proxy) then
		return false
	end

	local item = State.Rig and State.Rig._FindItemForBone and State.Rig:_FindItemForBone(proxy)
	if item then
		State.Rig:SetSingleItemSelection(item)
	elseif State.Axis then
		State.Axis:SelectBone(proxy)
	else
		return false
	end

	return true
end

function Display.hitTest(camera, point, folders)
	if State.PresentationHidden then
		return nil
	end

	local target = Display.targetUnderMouse(camera, point, folders)
	if target then
		return target
	end

	local best, closest = nil, 9
	for _, folder in folders do
		local shape = shapes[folder]
		if not shape or not shape.circle.Visible then
			continue
		end

		local cf = folder.CamPart_Bone.CFrame
		local center = camera:WorldToViewportPoint(folder.FovPart_Bone.Position)
		if
			center.Z > 0
			and (point - Vector2.new(center.X, center.Y)).Magnitude < FOV_HIT_RADIUS
		then
			return folder.FovPart_Bone
		end

		for _, pair in shape.segments or {} do
			local a = camera:WorldToViewportPoint(cf * pair[1])
			local b = camera:WorldToViewportPoint(cf * pair[2])
			if a.Z <= 0 or b.Z <= 0 then
				continue
			end

			local gap = distance(point, Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y))
			if gap < closest then
				closest, best = gap, folder.CamPart_Bone
			end
		end
	end

	return best
end

return Display
