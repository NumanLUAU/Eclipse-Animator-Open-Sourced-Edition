--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Projection = {}
local State = require("State")
local Camera = require("CameraRig")
local History = require("History")
local views = setmetatable({}, { __mode = "k" })
local hidden, lastView, lastCull = {}, nil, 0
Projection.FOV = 6
Projection.FOCUS_DISTANCE = 12

Projection.MAX_DISTANCE = 160

function Projection.cullBehind(view, depth)
	if not view then
		for part, previous in hidden do
			pcall(function()
				part.LocalTransparencyModifier = previous
			end)
		end

		table.clear(hidden)
		lastView = nil
		return
	end

	if lastView == view and os.clock() - lastCull < 0.5 then
		return
	end

	lastView, lastCull = view, os.clock()
	local look = view.LookVector
	local params = OverlapParams.new()
	params.MaxParts = 10000
	local keep = {}
	for _, part in
		workspace:GetPartBoundsInBox(
			view * CFrame.new(0, 0, depth * 0.5),
			Vector3.new(depth * 0.25, depth * 0.25, depth),
			params
		)
	do
		local size, cf = part.Size, part.CFrame
		local extent = math.abs(cf.RightVector:Dot(look)) * size.X
			+ math.abs(cf.UpVector:Dot(look)) * size.Y
			+ math.abs(cf.LookVector:Dot(look)) * size.Z
		if (part.Position - view.Position):Dot(look) + extent * 0.5 < 0 then
			keep[part] = true
			if hidden[part] == nil then
				hidden[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
	end

	for part, previous in hidden do
		if not keep[part] then
			hidden[part] = nil
			pcall(function()
				part.LocalTransparencyModifier = previous
			end)
		end
	end
end

function Projection.subjectDistance(view, fov)
	local halfY = math.tan(math.rad(fov) * 0.5)
	local camera = workspace.CurrentCamera
	local aspect = camera
			and camera.ViewportSize.Y > 0
			and camera.ViewportSize.X / camera.ViewportSize.Y
		or 16 / 9
	local total, weight = Projection.FOCUS_DISTANCE * 0.001, 0.001
	for _, rig in State.getAllRigs() do
		if rig.Parent and rig:IsA("Model") and not Camera.isRig(rig) then
			local point = view:PointToObjectSpace(rig:GetPivot().Position)
			local depth = -point.Z
			if depth > 0.1 then
				local edge = math.max(
					math.abs(point.X) / (depth * halfY * aspect),
					math.abs(point.Y) / (depth * halfY)
				)
				local w = math.clamp((1.15 - edge) / 0.35, 0, 1)
				total += depth * w
				weight += w
			end
		end
	end

	return math.clamp(total / weight, 1, 500)
end

function Projection.render(view, fov, orthographic)
	fov = Camera.clamp(fov)
	local focus = view * CFrame.new(0, 0, -Projection.FOCUS_DISTANCE)
	if not orthographic then
		return view, fov, focus
	end

	local frame, projectedFov =
		Projection.atDistance(view, fov, Projection.subjectDistance(view, fov))
	return frame, projectedFov, focus
end

function Projection.atDistance(view, fov, reference)
	fov = Camera.clamp(fov)
	reference = math.max(0.5, reference)
	local half = reference * math.tan(math.rad(fov) * 0.5)
	local distance = math.max(
		reference,
		math.min(half / math.tan(math.rad(Projection.FOV) * 0.5), Projection.MAX_DISTANCE)
	)
	return view * CFrame.new(0, 0, distance - reference), math.deg(math.atan(half / distance)) * 2
end

function Projection.setViewing(camera, rig, fov)
	views[camera] = rig and { rig = rig, fov = Camera.clamp(fov or Camera.fov(rig)) } or nil
end

function Projection.viewing(camera)
	local view = views[camera]
	if view and view.rig.Parent and view.rig:GetAttribute("EclipseOrthographic") == true then
		return Camera.viewFrame(view.rig)
			* (Camera.viewOffset and Camera.viewOffset() or CFrame.identity),
			view.fov
	end
end

function Projection.set(rig, enabled)
	if not Camera.isRig(rig) or not rig.Parent or require("BlenderEdit").blocked() then
		return false
	end

	if State.Timeline and State.Timeline:GetState().Playing then
		return false
	end

	local before = rig:GetAttribute("EclipseOrthographic")
	enabled = enabled == true
	if (before == true) == enabled then
		return false
	end

	local function apply(value)
		if not rig.Parent then
			return
		end

		rig:SetAttribute("EclipseOrthographic", value)
		State.currentProjectSaved = false
	end

	apply(enabled)
	History.record(function()
		apply(before)
	end, function()
		apply(enabled)
	end, "Camera projection")
	return true
end

function Projection.bindRow(item)
	local rig = item.linkedRigInstance
	if not Camera.isRig(rig) or item.projectionButton then
		return
	end

	local button =
		require("ParentingUI").modeButton(item.appearDetails.RightDiv, "CameraProjection")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.LayoutOrder = -2
	item.projectionButton = button

	local function paint()
		local enabled = rig:GetAttribute("EclipseOrthographic") == true
		button.Text = enabled and "O" or "P"
		button.TextColor3 = enabled and Color3.fromRGB(255, 198, 103)
			or Color3.fromRGB(97, 255, 197)
		local transparency = enabled and 0.45 or 1
		button:SetAttribute("ThemeBgTransparency", transparency)
		require("WindowFX").setRestingProperty(button, "BackgroundTransparency", transparency)
	end

	local hover = item.rigModule.refs.UIHelpers.hoverDialog
	if hover then
		hover:latchToInstance(
			button,
			"P: Perspective / O: Orthographic (experimental approximation). Ctrl+B and camera viewer only. FOV controls zoom."
		)
	end

	table.insert(
		item.connections,
		button.MouseButton1Click:Connect(function()
			Projection.set(rig, rig:GetAttribute("EclipseOrthographic") ~= true)
		end)
	)
	table.insert(
		item.connections,
		rig:GetAttributeChangedSignal("EclipseOrthographic"):Connect(paint)
	)
	paint()
end

return Projection
