--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Preferences = require("Preferences")

local Run = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Input = require("UserInputService")
local Shortcuts = require("Shortcuts")
local Edit = require("BlenderEdit")
local PivotSpace = require("PivotSpace")
local CameraRig = require("CameraRig")
local Tool = require("Tool")
local Notification = require("Notification")
local History = require("History")
local Theme = require("Theme")

local Editor = {}
local PIVOT_COLOR = Color3.fromRGB(97, 255, 197)
local JOINT_COLOR = Color3.fromRGB(255, 198, 103)
local MARKER_COLOR = Color3.fromRGB(235, 235, 240)
local AXIS_COLORS = {
	X = Color3.fromRGB(255, 87, 90),
	Y = Color3.fromRGB(34, 255, 0),
	Z = Color3.fromRGB(73, 56, 255),
}
local AXES = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }
local PLANES = { XY = { "X", "Y", "Z" }, XZ = { "X", "Z", "Y" }, YZ = { "Y", "Z", "X" } }
local SNAP_PIXELS = 14
local GRAB_PIXELS = 16
local AXIS_GRAB = 7
local ARROW_START = 12
local ARROW_PIXELS = 62
local CONE_PIXELS = 14
local PLANE_PIXELS = 13
local PLANE_OFFSET = 22
local PANEL_WIDTH = 360
local PANEL_HEIGHT = 74
local SETS_HEIGHT = 236
local SETTING = "EclipsePivotSets"

local refs, session, connection
local openedAt, closedAt = 0, 0
local connections = {}

local function snapName(point)
	local count = 0
	for _, value in { point.X, point.Y, point.Z } do
		if value ~= 0 then
			count += 1
		end
	end

	if count == 0 then
		return "Center"
	end

	if count == 1 then
		if point.Y < 0 then
			return "Bottom"
		end

		if point.Y > 0 then
			return "Top"
		end

		return "Side"
	end

	if count == 2 then
		return "Edge"
	end

	return "Corner"
end

local function markerPoints(part)
	local half = part.Size * 0.5
	local points = {}
	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				table.insert(points, {
					grid = Vector3.new(x, y, z),
					point = Vector3.new(x * half.X, y * half.Y, z * half.Z),
				})
			end
		end
	end

	return points
end

local function adorn(class, parent, adornee, color, layer)
	local value = Instance.new(class)
	value.Adornee = adornee
	value.AlwaysOnTop = true
	value.ZIndex = layer
	value.Color3 = color
	value.Transparency = 0.2
	value.Parent = parent
	return value
end

local function facing(center, direction)
	local up = if math.abs(direction.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(center, center + direction, up)
end

local function label(anchor)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PivotLabel"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(240, 26)
	billboard.Adornee = anchor
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.new(0, 0, 1, 0)
	frame:SetAttribute("ThemeBg", "Bg")
	frame.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Code
	text.TextSize = 15
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.new(0, 0, 1, 0)
	text:SetAttribute("ThemeTxt", "Txt")
	text.Parent = frame
	Theme.applyTree(frame)
	local disconnect = Theme.onChanged(function()
		if frame.Parent then
			Theme.applyTree(frame)
		end
	end)
	frame.Destroying:Once(disconnect)
	return billboard, text
end

local function setIcon(icon)
	if not session then
		return
	end

	local mouse = refs.Plugin:GetMouse()
	if session.icon == nil then
		local _, iconBefore = require("Cursor").snapshot(mouse)
		session.icon = iconBefore
	end

	mouse.Icon = icon
end

local function restoreIcon()
	if session and session.icon ~= nil then
		local mouse = refs.Plugin:GetMouse()
		mouse.Icon = session.icon
		session.icon = nil
	end
end

local function rigOf(motor)
	motor = require("R6Controls").ownerInstance(motor)
	local state = refs.State
	for _, rig in state.getAllRigs and state.getAllRigs() or { state.currentRig } do
		if rig and motor:IsDescendantOf(rig) then
			return rig
		end
	end

	return motor:FindFirstAncestorOfClass("Model") or state.currentRig
end

local function panelHeight()
	return PANEL_HEIGHT + (session and not session.poleOnly and session.poleChain and 42 or 0)
end

local function available()
	if not refs or not session then
		return false
	end

	local motor = session.motor
	return motor.Parent ~= nil
		and motor.Part1 ~= nil
		and motor.Part1.Parent ~= nil
		and motor.Part0 ~= nil
		and (not session.attachmentPart or session.attachmentPart.Parent ~= nil
			and require("Target").attachmentObject(session.rig) == session.attachmentPart)
		and refs.Active()
		and refs.ScreenGui.Enabled
		and refs.AnimatorFrame.Visible
		and not refs.State.PresentationHidden
		and not refs.State.Timeline:GetState().Playing
		and not Edit.blocked()
end

local function refresh(rig)
	local state = refs.State
	state.currentProjectSaved = false
	local raw = state.Timeline:GetState()
	pcall(function()
		state.Timeline:ApplyPoseAtTime(rig or state.currentRig, raw.CurrentTime, { OnlyRig = true })
	end)
	if state.Axis then
		state.Axis:RefreshAxis()
	end
end

local function destroyVisual()
	if session and session.folder then
		session.folder:Destroy()
		session.folder = nil
		session.poleAnchor = nil
	end
end

local function editPart()
	return session.poleAnchor or session.attachmentPart or session.motor.Part1
end

local function buildVisual()
	local part = editPart()
	local folder = Instance.new("Folder")
	folder.Name = "EclipsePivotEditor"
	folder.Archivable = false
	require("Recovery").mark(folder)
	if session.poleEditing then
		part = Instance.new("Part")
		part.Name = "PoleEditSpace"
		part.Anchored = true
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.Transparency = 1
		part.Size = session.motor.Part1:IsA("BasePart") and session.motor.Part1.Size or Vector3.one
		part.CFrame = session.poleFrame
		part.Parent = folder
		session.poleAnchor = part
	end

	local box = Instance.new("SelectionBox")
	box.Adornee = part
	box.Color3 = PIVOT_COLOR
	box.SurfaceTransparency = 1
	box.Transparency = 0.55
	box.LineThickness = 0.02
	box.Parent = folder
	session.markers = {}
	for _, entry in session.poleEditing and {} or markerPoints(part) do
		entry.adornment = adorn("SphereHandleAdornment", folder, part, MARKER_COLOR, 6)
		entry.name = snapName(entry.grid)
		table.insert(session.markers, entry)
	end

	session.joint = {
		point = session.poleEditing and session.original or session.motor.C1.Position,
		name = session.attachmentPart and "Center" or "Joint",
		adornment = adorn("SphereHandleAdornment", folder, part, JOINT_COLOR, 7),
	}
	session.link = adorn("LineHandleAdornment", folder, part, PIVOT_COLOR, 7)
	session.link.Thickness = 2
	session.lock = adorn("LineHandleAdornment", folder, part, PIVOT_COLOR, 8)
	session.lock.Thickness = 2
	session.arrows = {}
	for axis in AXES do
		local shaft =
			adorn("BoxHandleAdornment", folder, part, Preferences.axisColor(axis, AXIS_COLORS), 9)
		local cone =
			adorn("ConeHandleAdornment", folder, part, Preferences.axisColor(axis, AXIS_COLORS), 9)
		session.arrows[axis] = { shaft = shaft, cone = cone }
	end

	session.planes = {}
	for name, plane in PLANES do
		session.planes[name] = adorn(
			"BoxHandleAdornment",
			folder,
			part,
			Preferences.axisColor(plane[3], AXIS_COLORS),
			8
		)
	end

	session.handle = adorn("SphereHandleAdornment", folder, part, PIVOT_COLOR, 10)
	session.handle.Transparency = 0
	session.ring = adorn("CylinderHandleAdornment", folder, part, PIVOT_COLOR, 10)
	session.ring.Transparency = 0.15
	local anchor = Instance.new("Part")
	anchor.Name = "PivotLabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Locked = true
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.05
	anchor.Parent = folder
	session.anchor = anchor
	session.billboard, session.text = label(anchor)
	session.billboard.Parent = anchor
	folder.Parent = workspace
	session.folder = folder
end

local function pixelSize(camera, world)
	local depth = math.max(0.05, -camera.CFrame:PointToObjectSpace(world).Z)
	return depth * 2 * math.tan(math.rad(camera.FieldOfView) * 0.5) / math.max(
		1,
		camera.ViewportSize.Y
	),
		depth
end

local function screen(camera, world)
	local point, visible = camera:WorldToViewportPoint(world)
	return Vector2.new(point.X, point.Y), visible and point.Z > 0
end

local function segmentDistance(point, a, b)
	local line = b - a
	local length = line:Dot(line)
	if length < 1e-6 then
		return (point - a).Magnitude
	end

	local t = math.clamp((point - a):Dot(line) / length, 0, 1)
	return (point - (a + line * t)).Magnitude
end

local function axisDirection(axis)
	local space = refs.State.Axis and refs.State.Axis:GetAxisSpace()
	if space == "Global" then
		return editPart().CFrame:VectorToObjectSpace(AXES[axis] * Preferences.axisSign(axis)).Unit
	end

	return AXES[axis] * Preferences.axisSign(axis)
end

local function targets()
	local list = table.clone(session.markers)
	table.insert(list, session.joint)
	return list
end

local function nearestTarget(camera, mouse, limit, accept)
	local part = editPart()
	local best, distance = nil, limit
	for _, entry in targets() do
		if accept and not accept(entry.point) then
			continue
		end

		local point, visible = screen(camera, part.CFrame:PointToWorldSpace(entry.point))
		local gap = (point - mouse).Magnitude
		if visible and gap < distance then
			best, distance = entry, gap
		end
	end

	return best, distance
end

local function overHandle(camera, mouse)
	local point, visible = screen(camera, editPart().CFrame:PointToWorldSpace(session.current))
	return visible and (point - mouse).Magnitude <= GRAB_PIXELS
end

local function gizmoUnderMouse(camera, mouse)
	local frame = editPart().CFrame
	local unit = pixelSize(camera, frame:PointToWorldSpace(session.current))
	local best, score = nil, math.huge
	for axis in AXES do
		local direction = axisDirection(axis)
		local a, va = screen(
			camera,
			frame:PointToWorldSpace(session.current + direction * unit * ARROW_START)
		)
		local b, vb = screen(
			camera,
			frame:PointToWorldSpace(
				session.current + direction * unit * (ARROW_PIXELS + CONE_PIXELS)
			)
		)
		if not va or not vb then
			continue
		end

		local distance = segmentDistance(mouse, a, b)
		if distance < AXIS_GRAB and distance < score then
			best, score = { kind = "axis", axis = axis }, distance
		end
	end

	for name, plane in PLANES do
		local center = session.current
			+ (axisDirection(plane[1]) + axisDirection(plane[2]))
				* unit
				* (PLANE_OFFSET + PLANE_PIXELS * 0.5)
		local point, visible = screen(camera, frame:PointToWorldSpace(center))
		local distance = (point - mouse).Magnitude
		if visible and distance < PLANE_PIXELS * 0.75 and distance < score then
			best, score = { kind = "plane", plane = name }, distance
		end
	end

	return best, score
end

local function describe()
	if session.poleEditing then
		return string.format(
			session.controlKind == "pole" and "Pole offset · %.2f" or "Grab offset · %.2f",
			(session.current - session.original).Magnitude
		)
	end

	local offset = session.current - session.joint.point
	local name = session.snapped and session.snapped.name or "Free"
	local drag = session.drag
	if drag and drag.lockAxis then
		name ..= " · " .. Preferences.axisName(drag.lockAxis) .. " locked"
	end

	if drag and drag.kind == "axis" then
		name ..= " · along " .. Preferences.axisName(drag.axis)
	end

	if drag and drag.kind == "plane" then
		name ..= " · " .. drag.plane .. " plane"
	end

	if offset.Magnitude < 1e-4 then
		return name == "Joint" and "Joint" or name .. " · on the joint"
	end

	return string.format("%s · %.2f from joint", name, offset.Magnitude)
end

local function held(a, b)
	return Input:IsKeyDown(a) or Input:IsKeyDown(b)
end

local function paramOnAxis(ray, origin, direction)
	local r = ray.Direction.Unit
	local w = ray.Origin - origin
	local b = direction:Dot(r)
	local denominator = 1 - b * b
	if denominator < 1e-4 then
		return nil
	end

	return (direction:Dot(w) - b * r:Dot(w)) / denominator
end

local function planeHit(ray, origin, normal)
	local denominator = ray.Direction:Dot(normal)
	if math.abs(denominator) < 1e-6 then
		return nil
	end

	local distance = (origin - ray.Origin):Dot(normal) / denominator
	if distance <= 0 then
		return nil
	end

	return ray.Origin + ray.Direction * distance
end

local function snapConstrained(camera, mouse, point, accept)
	if held(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl) then
		return point, nil
	end

	local frame = editPart().CFrame
	local projected = screen(camera, frame:PointToWorldSpace(point))
	local target = nearestTarget(camera, projected, SNAP_PIXELS, accept)
	if target then
		return target.point, target
	end

	return point, nil
end

local function anchorGrab(drag, mouse)
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local frame = editPart().CFrame
	local origin = frame:PointToWorldSpace(session.current)
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	drag.start = session.current
	drag.frame = frame
	drag.origin = origin
	drag.normal = camera.CFrame.LookVector
	drag.hit = planeHit(ray, origin, drag.normal)
	if drag.lockAxis then
		drag.direction = frame:VectorToWorldSpace(axisDirection(drag.lockAxis))
		drag.along = paramOnAxis(ray, origin, drag.direction)
	end

	return true
end

local function dragTo(mouse)
	local drag = session.drag
	local camera = workspace.CurrentCamera
	local part = editPart()
	if not camera or not part then
		return
	end

	local frame = part.CFrame
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if drag.modal then
		if session.poleEditing and refs.State.Timeline:GetState().CurrentTime ~= session.time then
			return
		end

		if drag.lockAxis then
			local along = paramOnAxis(ray, drag.origin, drag.direction)
			if along and drag.along then
				session.current = drag.start
					+ drag.frame:VectorToObjectSpace(drag.direction) * (along - drag.along)
			end
		else
			local hit = planeHit(ray, drag.origin, drag.normal)
			if hit and drag.hit then
				session.current = drag.start + drag.frame:VectorToObjectSpace(hit - drag.hit)
			end
		end

		session.snapped = nil
		return
	end

	session.snapped = nil
	if drag.kind == "axis" then
		local direction = frame:VectorToWorldSpace(drag.direction)
		local along = paramOnAxis(ray, drag.origin, direction)
		if not along or not drag.along then
			return
		end

		local point = drag.start + drag.direction * (along - drag.along)
		session.current, session.snapped = snapConstrained(camera, mouse, point, function(candidate)
			local offset = candidate - drag.start
			return (offset - drag.direction * offset:Dot(drag.direction)).Magnitude < 1e-3
		end)
		return
	end

	if drag.kind == "plane" then
		local normal = frame:VectorToWorldSpace(drag.normal)
		local hit = planeHit(ray, drag.origin, normal)
		if not hit or not drag.hit then
			return
		end

		local point = drag.start + frame:VectorToObjectSpace(hit - drag.hit)
		session.current, session.snapped = snapConstrained(camera, mouse, point, function(candidate)
			return math.abs((candidate - drag.start):Dot(drag.normal)) < 1e-3
		end)
		return
	end

	if not held(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl) and not drag.lockAxis then
		local target = nearestTarget(camera, mouse, SNAP_PIXELS)
		if target then
			session.current = target.point
			session.snapped = target
			return
		end
	end

	local world
	if held(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift) and not drag.lockAxis then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { part }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		if hit then
			world = hit.Position
		end
	end

	if not world then
		world = planeHit(ray, frame:PointToWorldSpace(drag.start), camera.CFrame.LookVector)
		if not world then
			return
		end
	end

	local point = frame:PointToObjectSpace(world)
	if drag.lockAxis then
		local direction = axisDirection(drag.lockAxis)
		local along = paramOnAxis(
			ray,
			frame:PointToWorldSpace(drag.start),
			frame:VectorToWorldSpace(direction)
		)
		point = if along then drag.start + direction * along else drag.start
	end

	session.current = point
end

local function overPanel(mouse)
	local panel = session and session.panel
	local frame = panel and panel.frame
	if not frame or not frame.Parent or not panel.gui.Enabled then
		return false
	end

	local position, size = frame.AbsolutePosition, frame.AbsoluteSize
	return mouse.X >= position.X
		and mouse.Y >= position.Y
		and mouse.X <= position.X + size.X
		and mouse.Y <= position.Y + size.Y
end

local function step()
	if not session then
		return
	end

	if not available() then
		Editor.finish(true)
		return
	end

	if session.poleOnly and not session.poleEditing then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if not session.folder or not session.folder.Parent then
		buildVisual()
	end

	local mouse = Input:GetMouseLocation()
	local part = editPart()
	local frame = part.CFrame
	if session.drag then
		dragTo(mouse)
	end

	local pivotWorld = frame:PointToWorldSpace(session.current)
	if session.poleEditing then
		Editor.setPolePosition(pivotWorld)
	end

	local unit = pixelSize(camera, pivotWorld)
	local panelHover = not session.drag and overPanel(mouse)
	local onHandle = not session.drag and not panelHover and overHandle(camera, mouse)
	local gizmo = not session.drag
		and not panelHover
		and not onHandle
		and gizmoUnderMouse(camera, mouse)
	local hovered = not session.drag
		and not panelHover
		and not onHandle
		and not gizmo
		and nearestTarget(camera, mouse, SNAP_PIXELS)
	session.hover = gizmo or nil
	if panelHover then
		restoreIcon()
	elseif session.drag then
		setIcon("rbxasset://SystemCursors/ClosedHand")
	elseif onHandle or gizmo or hovered then
		setIcon("rbxasset://SystemCursors/PointingHand")
	else
		setIcon("rbxasset://SystemCursors/Cross")
	end

	for _, entry in targets() do
		local size = pixelSize(camera, frame:PointToWorldSpace(entry.point))
		local active = session.snapped == entry
		local hot = hovered == entry
		local radius = entry == session.joint and 6 or (active and 6 or hot and 6 or 3.5)
		entry.adornment.CFrame = CFrame.new(entry.point)
		entry.adornment.Radius = size * radius
		entry.adornment.Transparency = active and 0
			or hot and 0.05
			or entry == session.joint and 0.1
			or 0.35
		entry.adornment.Color3 = (active or hot) and PIVOT_COLOR
			or entry == session.joint and JOINT_COLOR
			or MARKER_COLOR
	end

	local drag = session.drag
	local centerDrag = drag and drag.kind == "center"
	session.handle.CFrame = CFrame.new(session.current)
	session.handle.Radius = unit * ((centerDrag or onHandle) and 7 or 6)
	session.ring.CFrame = frame:ToObjectSpace(CFrame.lookAt(pivotWorld, camera.CFrame.Position))
	session.ring.Radius = unit * 12
	session.ring.InnerRadius = unit * 10
	session.ring.Height = unit * 0.5
	for axis, arrow in session.arrows do
		arrow.shaft.Color3 = Preferences.axisColor(axis, AXIS_COLORS)
		arrow.cone.Color3 = arrow.shaft.Color3
		local direction = axisDirection(axis)
		local active = drag and drag.kind == "axis" and drag.axis == axis
		local hot = active or gizmo and gizmo.kind == "axis" and gizmo.axis == axis
		local visible = not drag or active
		local length = unit * (ARROW_PIXELS - ARROW_START)
		arrow.shaft.Visible = visible
		arrow.cone.Visible = visible
		arrow.shaft.CFrame = facing(
			session.current + direction * unit * (ARROW_START + (ARROW_PIXELS - ARROW_START) * 0.5),
			direction
		)
		arrow.shaft.Size =
			Vector3.new(unit * (hot and 3.5 or 2.5), unit * (hot and 3.5 or 2.5), length)
		arrow.cone.CFrame = facing(session.current + direction * unit * ARROW_PIXELS, direction)
		arrow.cone.Radius = unit * (hot and 6.5 or 5.5)
		arrow.cone.Height = unit * CONE_PIXELS
		arrow.shaft.Transparency = hot and 0 or 0.15
		arrow.cone.Transparency = hot and 0 or 0.15
	end

	for name, box in session.planes do
		local plane = PLANES[name]
		box.Color3 = Preferences.axisColor(plane[3], AXIS_COLORS)
		local a, b = axisDirection(plane[1]), axisDirection(plane[2])
		local active = drag and drag.kind == "plane" and drag.plane == name
		local hot = active or gizmo and gizmo.kind == "plane" and gizmo.plane == name
		box.Visible = not drag or active
		box.CFrame = CFrame.fromMatrix(
			session.current + (a + b) * unit * (PLANE_OFFSET + PLANE_PIXELS * 0.5),
			a,
			b
		)
		box.Size = Vector3.new(unit * PLANE_PIXELS, unit * PLANE_PIXELS, unit * 0.5)
		box.Transparency = hot and 0.1 or 0.55
	end

	local lockAxis = drag and (drag.kind == "axis" and drag.axis or drag.lockAxis)
	session.lock.Visible = lockAxis ~= nil
	if lockAxis then
		local direction = if drag.kind == "axis" then drag.direction else axisDirection(lockAxis)
		local length = unit * 800
		session.lock.Color3 = Preferences.axisColor(lockAxis, AXIS_COLORS)
		session.lock.CFrame = facing(drag.start - direction * length * 0.5, direction)
		session.lock.Length = length
	end

	local offset = session.current - session.joint.point
	session.link.Visible = offset.Magnitude > 1e-3
	if session.link.Visible then
		session.link.CFrame = facing(session.joint.point, offset)
		session.link.Length = offset.Magnitude
	end

	session.anchor.CFrame = CFrame.new(pivotWorld)
	session.billboard.StudsOffset = Vector3.new(0, unit * 30, 0)
	session.text.Text = describe()
end

local function motorList(rig)
	local list = {}
	for _, item in rig:GetDescendants() do
		if item:IsA("Motor6D") and item.Part0 and item.Part1 then
			table.insert(list, item)
		end
	end

	return list
end

local function snapshot()
	local pivots = {}
	for _, motor in session.motors do
		if motor ~= session.motor then
			pivots[motor] = PivotSpace.get(motor) or false
		end
	end

	return { current = session.current, pivots = pivots }
end

local function restoreSnapshot(state)
	local changed = false
	for motor, value in state.pivots do
		local target = value or nil
		if motor.Parent and PivotSpace.get(motor) ~= target then
			PivotSpace.set(motor, target)
			changed = true
		end
	end

	session.current = state.current
	session.snapped = nil
	if changed then
		refresh(session.rig)
	end
end

local function same(a, b)
	if a.current ~= b.current and (a.current - b.current).Magnitude > 1e-5 then
		return false
	end

	for motor, value in a.pivots do
		if b.pivots[motor] ~= value then
			return false
		end
	end

	return true
end

local function remember(state)
	state = state or snapshot()
	table.insert(session.undo, state)
	if #session.undo > 200 then
		table.remove(session.undo, 1)
	end

	table.clear(session.redo)
end

local function undoStep()
	local state = table.remove(session.undo)
	if not state then
		return
	end

	table.insert(session.redo, snapshot())
	restoreSnapshot(state)
end

local function redoStep()
	local state = table.remove(session.redo)
	if not state then
		return
	end

	table.insert(session.undo, snapshot())
	restoreSnapshot(state)
end

local function resetToJoint()
	if not session or not session.joint then
		return
	end

	session.drag = nil
	session.pending = nil
	if (session.current - session.joint.point).Magnitude < 1e-5 then
		return
	end

	remember()
	session.current = session.joint.point
	session.snapped = session.joint
	if session.poleEditing then
		session.delta = Vector3.zero
		session.previewed = nil
		Editor.setPolePosition(session.poleFrame:PointToWorldSpace(session.current))
	end
end

local function readSets()
	local value = require("ProjectData").getSetting(SETTING)
	assert(
		value == nil or type(value) == "table",
		"Saved pivots could not be read; saved data was retained."
	)
	local list = if type(value) == "table" then value else {}
	local valid = {}
	local fixed = false
	for _, set in list do
		if type(set) ~= "table" or type(set.Pivots) ~= "table" or type(set.Joints) ~= "table" then
			fixed = true
			continue
		end

		if type(set.Id) ~= "string" then
			set.Id = HttpService:GenerateGUID(false)
			fixed = true
		end

		if type(set.Name) ~= "string" or set.Name == "" then
			set.Name = "Pivots"
			fixed = true
		end

		table.insert(valid, set)
	end

	if fixed then
		pcall(function()
			require("ProjectData").setSetting(SETTING, valid)
		end)
	end

	return valid
end

local function writeSets(list)
	local ok, err = pcall(function()
		require("ProjectData").setSetting(SETTING, list)
	end)
	if not ok then
		warn(err)
	end

	return ok
end

local function motorKey(motor)
	return motor.Part0.Name .. "/" .. motor.Part1.Name
end

local function rigMotors(rig)
	local map, list = {}, {}
	for _, item in motorList(rig) do
		local key = motorKey(item)
		if map[key] == nil then
			map[key] = item
			table.insert(list, item)
		else
			map[key] = false
		end
	end

	return map, list
end

local function fits(set, map)
	for _, key in set.Joints do
		if not map[key] then
			return false
		end
	end

	return true
end

local function count(set)
	local total = 0
	for _ in set.Pivots do
		total += 1
	end

	return total
end

local function sessionValue()
	return if (session.current - session.motor.C1.Position).Magnitude < 1e-4
		then nil
		else session.current
end

local function uniqueName(sets, base, ignore)
	local name, suffix = base, 1
	local taken = true
	while taken do
		taken = false
		for _, set in sets do
			if set ~= ignore and set.Name == name then
				taken = true
				break
			end
		end

		if taken then
			suffix += 1
			name = base .. " " .. suffix
		end
	end

	return name
end

local function captureRig()
	local map, list = rigMotors(session.rig)
	local joints, pivots = {}, {}
	local total = 0
	for _, motor in list do
		local key = motorKey(motor)
		if map[key] ~= motor then
			continue
		end

		table.insert(joints, key)
		local value = if motor == session.motor then sessionValue() else PivotSpace.get(motor)
		if value then
			pivots[key] = { value.X, value.Y, value.Z }
			total += 1
		end
	end

	return joints, pivots, total
end

local buildList

function Editor.sets()
	if not session then
		return {}
	end

	local map = rigMotors(session.rig)
	local matches = {}
	for _, set in readSets() do
		if fits(set, map) then
			table.insert(matches, set)
		end
	end

	return matches
end

function Editor.saveSet(name, target)
	if not session then
		return nil
	end

	local joints, pivots, total = captureRig()
	if total == 0 then
		Notification.show("NOTHING TO SAVE", "Move at least one pivot off its joint first.")
		return nil
	end

	local sets = readSets()
	local saved
	if target then
		for _, set in sets do
			if set.Id == target.Id then
				saved = set
				break
			end
		end
	end

	if saved then
		saved.Joints, saved.Pivots = joints, pivots
	else
		local base = if type(name) == "string" and name:match("%S")
			then name:match("^%s*(.-)%s*$")
			else session.rig.Name .. " pivots"
		saved = {
			Id = HttpService:GenerateGUID(false),
			Name = uniqueName(sets, base),
			Joints = joints,
			Pivots = pivots,
		}
		table.insert(sets, saved)
	end

	if not writeSets(sets) then
		return nil
	end

	Notification.show(
		if target then "SET UPDATED" else "PIVOTS SAVED",
		string.format("%s · %d %s.", saved.Name, total, total == 1 and "pivot" or "pivots")
	)
	if session.listOpen then
		buildList()
	end

	return saved
end

function Editor.loadSet(set)
	if not session or type(set) ~= "table" then
		return
	end

	local map, list = rigMotors(session.rig)
	remember()
	local changed = false
	for _, motor in list do
		local key = motorKey(motor)
		if map[key] ~= motor then
			continue
		end

		local value = set.Pivots[key]
		local target = if type(value) == "table"
			then Vector3.new(value[1], value[2], value[3])
			else nil
		if motor == session.motor then
			session.current = target or motor.C1.Position
			session.snapped = nil
		elseif motor.Parent then
			PivotSpace.set(motor, target)
			changed = true
		end
	end

	if changed then
		refresh(session.rig)
	end

	Notification.show(
		"PIVOTS LOADED",
		set.Name .. " is on " .. session.rig.Name .. ". Ctrl+Z steps back."
	)
end

function Editor.renameSet(set, name)
	name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
	if name == "" then
		return false
	end

	local sets = readSets()
	for _, item in sets do
		if item.Id == set.Id then
			item.Name = uniqueName(sets, name, item)
			writeSets(sets)
			return item.Name
		end
	end

	return false
end

function Editor.deleteSet(set)
	local sets = readSets()
	for index, item in sets do
		if item.Id == set.Id then
			table.remove(sets, index)
			break
		end
	end

	writeSets(sets)
	if session and session.listOpen then
		buildList()
	end
end

local function styleButtons(frame)
	local cancel = frame:FindFirstChild("Cancel", true)
	if cancel then
		cancel.BackgroundTransparency = 1
		cancel:SetAttribute("ThemeBg", nil)
	end

	local primary = frame:FindFirstChild("Finish", true)
	if primary then
		primary:SetAttribute("ThemeBg", "MenuSel")
		primary:SetAttribute("Primary", true)
		Theme.applyTree(primary)
	end
end

local function small(text)
	text.TextSize = 11
	text.TextTransparency = 0.3
	return text
end

buildList = function()
	if not session or not session.panel then
		return
	end

	local frame = session.panel.frame
	local old = frame:FindFirstChild("Sets")
	if old then
		old:Destroy()
	end

	local toggle = frame:FindFirstChild("ToggleSets", true)
	local toggleText = toggle and toggle:FindFirstChildWhichIsA("TextLabel", true)
	if toggleText then
		toggleText.Text = if session.listOpen then "HIDE SETS" else "SETS"
	end

	if not session.listOpen then
		frame.Size = UDim2.fromOffset(PANEL_WIDTH, panelHeight())
		return
	end

	local inner = PANEL_WIDTH - 24
	local section = Tool.make("Frame", frame, "Sets", {
		Position = UDim2.fromOffset(12, panelHeight() - 2),
		Size = UDim2.fromOffset(inner, SETS_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex + 1,
	})
	local line = Tool.make("Frame", section, "Divider", {
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.6,
		ZIndex = section.ZIndex + 1,
	})
	line:SetAttribute("ThemeBg", "Strk")
	local nameBox = Tool.field(
		section,
		"NewName",
		uniqueName(readSets(), session.rig.Name .. " pivots"),
		UDim2.fromOffset(0, 10),
		UDim2.fromOffset(inner - 112, 28)
	)
	nameBox.PlaceholderText = "Name this set"
	Tool.button(
		section,
		"SaveNew",
		"SAVE NEW SET",
		UDim2.fromOffset(inner - 106, 10),
		UDim2.fromOffset(106, 28),

		function()
			Editor.saveSet(nameBox.Text)
		end
	)
	nameBox.FocusLost:Connect(function(enter)
		if enter then
			Editor.saveSet(nameBox.Text)
		end
	end)
	local matches = Editor.sets()
	local others = #readSets() - #matches
	local heading = small(
		Tool.label(
			section,
			"Heading",
			if #matches == 0
				then "No saved sets fit this rig yet."
				else string.format("SETS FOR %s  ·  %d", session.rig.Name, #matches),
			UDim2.fromOffset(0, 44),
			UDim2.fromOffset(inner, 18)
		)
	)
	heading.ZIndex = section.ZIndex + 2
	if others > 0 then
		local hidden = small(
			Tool.label(
				section,
				"Hidden",
				string.format("%d for other rigs hidden", others),
				UDim2.fromOffset(0, 44),
				UDim2.fromOffset(inner, 18)
			)
		)
		hidden.TextXAlignment = Enum.TextXAlignment.Right
		hidden.ZIndex = section.ZIndex + 2
	end

	local list = Tool.make("ScrollingFrame", section, "List", {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.fromOffset(inner, SETS_HEIGHT - 74),
		CanvasSize = UDim2.fromOffset(0, #matches * 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ZIndex = section.ZIndex + 1,
	})
	local width = inner - 8
	for index, set in matches do
		local y = (index - 1) * 32
		local total = count(set)
		local box = Tool.field(
			list,
			"Name" .. index,
			set.Name,
			UDim2.fromOffset(0, y),
			UDim2.fromOffset(width - 190, 28)
		)
		box.FocusLost:Connect(function()
			local renamed = Editor.renameSet(set, box.Text)
			if renamed then
				set.Name = renamed
				box.Text = renamed
			else
				box.Text = set.Name
			end
		end)
		local info = small(
			Tool.label(
				list,
				"Count" .. index,
				string.format("%d %s", total, total == 1 and "pivot" or "pivots"),
				UDim2.fromOffset(width - 184, y + 2),
				UDim2.fromOffset(52, 24)
			)
		)
		info.ZIndex = list.ZIndex + 2
		Tool.button(
			list,
			"Load" .. index,
			"LOAD",
			UDim2.fromOffset(width - 130, y),
			UDim2.fromOffset(46, 28),

			function()
				Editor.loadSet(set)
			end
		)
		Tool.button(
			list,
			"Update" .. index,
			"SAVE",
			UDim2.fromOffset(width - 80, y),
			UDim2.fromOffset(46, 28),

			function()
				Editor.saveSet(nil, set)
			end
		)
		Tool.button(
			list,
			"Delete" .. index,
			"×",
			UDim2.fromOffset(width - 28, y),
			UDim2.fromOffset(28, 28),

			function()
				Editor.deleteSet(set)
			end
		)
	end

	frame.Size = UDim2.fromOffset(PANEL_WIDTH, panelHeight() + SETS_HEIGHT + 4)
	Theme.applyTree(section)
end

local function buildPanel()
	local window = Tool.new(
		{ ScreenGui = refs.ScreenGui, Plugin = refs.Plugin },
		"EclipsePivotPanel",
		"EDIT PIVOT · " .. string.upper(session.motor.Part1.Name),
		Vector2.new(PANEL_WIDTH, panelHeight()),
		false,

		function()
			if session and session.panel then
				session.panel = nil
				Editor.finish(true)
			end
		end
	)
	local frame = window.frame
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0, 64 + panelHeight() * 0.5)
	local y = 36
	if not session.poleOnly then
		Tool.button(
			frame,
			"Reset",
			"RESET",
			UDim2.fromOffset(12, y),
			UDim2.fromOffset(64, 28),
			resetToJoint
		)
		if not session.attachmentPart then
			Tool.button(frame, "ToggleSets", "SETS", UDim2.fromOffset(82, y), UDim2.fromOffset(78, 28), function()
				Editor.toggleSets()
			end)
		end
	end

	if session.poleChain then
		Tool.button(
			frame,
			"EditPole",
			"EDIT IK POLE",
			UDim2.fromOffset(12, session.poleOnly and y or y + 40),
			UDim2.fromOffset(148, 28),

			function()
				Editor.editPole()
			end
		)
		if not session.poleOnly then
			local help = small(
				Tool.label(
					frame,
					"PoleHelp",
					"Move the limb's bend control.",
					UDim2.fromOffset(172, y + 42),
					UDim2.fromOffset(176, 24)
				)
			)
			help.TextWrapped = true
		end
	end

	Tool.button(
		frame,
		session.poleOnly and "Reset" or "Cancel",
		session.poleOnly and "RESET" or "CANCEL",
		UDim2.fromOffset(PANEL_WIDTH - 170, y),
		UDim2.fromOffset(76, 28),

		function()
			if session and session.poleOnly then
				resetToJoint()
			else
				Editor.finish(true)
			end
		end
	)
	Tool.button(
		frame,
		"Finish",
		"FINISH",
		UDim2.fromOffset(PANEL_WIDTH - 88, y),
		UDim2.fromOffset(76, 28),

		function()
			Editor.finish(false)
		end
	)
	styleButtons(frame)
	return window
end

local function closePanel(saved)
	local panel = saved and saved.panel
	if panel then
		saved.panel = nil
		pcall(function()
			panel:close()
		end)
	end
end

function Editor.isActive()
	return session ~= nil
end

function Editor.toggleSets(open)
	if not session or session.poleOnly then
		return
	end

	session.listOpen = if open == nil then not session.listOpen else open
	buildList()
end

local function finishPole(saved, cancel)
	local control = saved.poleControl
	local before = saved.poleDisplayOffset
	const attribute = saved.poleAttribute
	local after = control:GetAttribute(attribute)

	local function apply(value)
		control:SetAttribute(attribute, value)
		require("cache").invalidate()
		refs.State.Timeline:ApplyPoseAtTime(saved.rig, refs.State.Timeline:GetState().CurrentTime)
		if refs.State.Axis then
			refs.State.Axis:RefreshAxis()
		end
	end

	if cancel then
		apply(before)
		return true
	end

	if (after or Vector3.zero) == (before or Vector3.zero) then
		return true
	end

	refs.State.currentProjectSaved = false
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, (saved.controlKind == "pole" and "IK Pole Pivot " or "IK Grab Point ") .. saved.motor.Part1.Name, saved.frame)
	return true
end

function Editor.finish(cancel)
	if not session then
		return false
	end

	local saved = session
	if saved.poleEditing and not cancel then
		Editor.setPolePosition(saved.poleFrame:PointToWorldSpace(saved.current))
	end

	if saved.poleEditing and not finishPole(saved, cancel) then
		return false
	end

	closedAt = os.clock()
	restoreIcon()
	destroyVisual()
	session = nil
	closePanel(saved)
	if refs.State.Axis then
		refs.State.Axis:SetPlaybackHidden(false)
		refs.State.Axis:RefreshAxis()
	end

	if saved.poleOnly then
		return true
	end

	local rig = saved.rig
	local before, after = {}, {}
	local changed, selfChanged = false, false
	for _, motor in saved.motors do
		local start = saved.start[motor]
		before[motor] = start or false
		local final = if motor == saved.motor then saved.current else PivotSpace.get(motor)
		if motor == saved.motor and (final - motor.C1.Position).Magnitude < 1e-4 then
			final = nil
		end

		after[motor] = final or false
		local differs = if start and final then (start - final).Magnitude > 1e-5 else start ~= final
		if differs then
			changed = true
			if motor == saved.motor then
				selfChanged = true
			end
		end
	end

	local function apply(values)
		for motor, value in values do
			if motor.Parent then
				PivotSpace.set(motor, value or nil)
			end
		end

		refresh(rig)
	end

	if cancel or not changed then
		apply(before)
		return true
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Pivot " .. saved.motor.Part1.Name)
	local motor = saved.motor
	if not selfChanged then
		Notification.show("PIVOTS UPDATED", "The loaded set is on " .. rig.Name .. " now.")
	elseif saved.attachmentPart then
		Notification.show("CAMERA ATTACHMENT", after[motor] and "The camera uses the new point on the attached part."
			or "The camera uses the center of the attached part again.")
	elseif after[motor] then
		Notification.show(
			"PIVOT SET",
			motor.Part1.Name .. " turns around the new point now. In-betweens follow it too."
		)
	else
		Notification.show("PIVOT RESET", motor.Part1.Name .. " turns around its joint again.")
	end

	return true
end

local function refuseIK()
	Notification.show(
		"CANNOT PIVOT IK",
		"This limb is on IK here. Pivots only apply to FK keys and come back once the IK part ends."
	)
	return false
end

function Editor.editPole(kind)
	if not session or not session.poleChain then
		return false
	end

	local LimbIK = require("LimbIK")
	local saved = session

	local function message(text)
		if saved.panel and saved.panel.frame:FindFirstChild("PoleHelp") then
			saved.panel.frame.PoleHelp.Text = text
		end

		Notification.show("EDIT IK POLE", text)
	end

	local time = refs.State.Timeline:GetState().CurrentTime
	local chain = LimbIK.chain(saved.rig, saved.poleChain.owner)
	if not chain or not LimbIK.isEnabled(chain.owner, time) then
		message("Enable IK for this limb at the current frame first.")
		return false
	end

	if kind ~= "pole" and not (kind and LimbIK.canGrab(chain, kind)) then
		kind = "pole"
	end

	if saved.poleEditing and saved.controlKind == kind then
		return false
	end

	local control = LimbIK.controlMotor(chain, kind)
	if
		chain.owner:GetAttribute("EclipseDisabled")
		or control and control:GetAttribute("EclipseDisabled")
	then
		message(kind == "pole" and "Enable this limb and its pole track first." or "Enable this limb and its IK control track first.")
		return false
	end

	if kind == "pole" and chain.kind == "R6" and Preferences.get("R6IKLegPole") == false then
		message("Enable R6 IK Leg Pole in Preferences to show the pole control.")
		return false
	end

	if not control then
		message("This limb has no editable pole track.")
		return false
	end

	local Mods = require("Mods")
	for _, id in kind == "pole" and { "loc_x", "loc_y", "loc_z" } or {} do
		local entry = Mods.get(control, id)
		if entry and (entry.Off or entry.Muted) then
			message("Enable the pole position channels before editing its offset.")
			return false
		end
	end

	if saved.poleEditing then
		Editor.setPolePosition(saved.poleFrame:PointToWorldSpace(saved.current))
		finishPole(saved, false)
		saved.drag, saved.pending, saved.previewed, saved.snapped = nil, nil, nil, nil
	end

	local pole = kind == "pole" and LimbIK.state(chain).pole or nil
	local previousOffset = control:GetAttribute("EclipsePoleDisplayOffset")
	if pole and typeof(previousOffset) == "Vector3" then
		pole *= CFrame.new(previousOffset)
	end
	saved.poleEditing = true
	saved.controlKind = kind
	saved.ikChain = chain
	saved.poleAttribute = kind == "pole" and "EclipsePolePivotOffset" or "EclipseGrabOffset"
	saved.poleControl = control
	saved.poleDisplayOffset = control:GetAttribute(saved.poleAttribute)
	saved.poleOrigin = pole
	saved.poleBaseC0 = control.C0
	saved.poleRotation = pole and pole.Rotation
	saved.poleFrame = require("Parenting").worldOf(saved.motor, chain.entry.map)
	saved.time = time
	saved.frame = refs.State.Timeline:TimeToFrame(time)
	saved.original = saved.poleFrame:PointToObjectSpace(LimbIK.controlFrame(chain, kind).Position)
	saved.current = saved.original
	saved.motors, saved.undo, saved.redo = {}, {}, {}
	saved.delta = Vector3.zero
	refs.State.Axis:SetPlaybackHidden(true)
	destroyVisual()
	buildVisual()
	if kind ~= "pole" then
		Notification.show("EDIT IK HANDLE", "Move where you grab this IK control. The pose stays the same.")
	end

	return true
end

function Editor.setPolePosition(world)
	if not session or not session.poleEditing or typeof(world) ~= "Vector3" then
		return false
	end

	if
		world.X ~= world.X
		or world.Y ~= world.Y
		or world.Z ~= world.Z
		or world.Magnitude == math.huge
	then
		return false
	end

	local raw = refs.State.Timeline:GetState()
	if raw.CurrentTime ~= session.time then
		if not session.awayFromFrame then
			session.awayFromFrame = true
			Notification.show(
				"EDIT IK POLE",
				string.format("Return to frame %d to adjust the control pivot.", session.frame)
			)
		end

		return false
	end

	session.awayFromFrame = nil
	session.current = session.poleFrame:PointToObjectSpace(world)
	if session.previewed == session.current then
		return true
	end

	local offset = if session.poleOrigin
		then session.poleOrigin:PointToObjectSpace(world)
		else require("LimbIK").grabOffsetFor(session.ikChain, session.controlKind, world)
	if not offset then
		return false
	end

	session.poleControl:SetAttribute(
		session.poleAttribute,
		if offset.Magnitude < 1e-5 then nil else offset
	)
	require("cache").invalidate()
	require("LimbIK").apply(session.rig, raw.CurrentTime, false)
	if refs.State.Rig then
		refs.State.Rig:UpdateBonesFollowRig(session.rig)
	end
	session.delta = session.current - session.original
	session.previewed = session.current
	return true
end

function Editor.start()
	if session or not refs or os.clock() - closedAt < 0.2 then
		return false
	end

	local state = refs.State
	if not refs.Active() or state.Timeline:GetState().Playing or Edit.blocked() then
		return false
	end

	local motor = state.Axis and state.Axis:GetPrimaryMotor()
	local selectedItem = state.Rig and state.Rig._lastClickedItem
	if selectedItem and state.Rig._selectedItems[selectedItem] and selectedItem.itemKind == "cameraattach" then
		motor = selectedItem:fetchMotor()
	end
	local attachment = require("Target").isAttachment(motor)
	local selected = not attachment and state.Axis and state.Axis:GetSelectedBone()
	local reference = selected and selected:FindFirstChild("EclipseLimbOwner")
	local controlKind = reference and selected:GetAttribute("EclipseLimbControl")
	if reference then
		motor = require("R6Controls").resolveOwner(reference.Value)
	elseif type(motor) == "table" and motor.IsEclipseR6Control then
		controlKind = motor:GetAttribute("EclipseR6Control")
		motor = motor.Owner
	elseif type(motor) == "table" and motor.IsEclipseIKHandle and selected and state.Rig then
		controlKind = motor.ControlKind
		local source = selected.Parent and selected.Parent:FindFirstChild("EclipseSourceRig")
		local selectedRig = source and source.Value or state.currentRig
		local part = state.Rig:GetPartFromBone(selectedRig, selected)
		motor = part and state.Rig:GetMotorForPart(selectedRig, part)
	end

	local joint = typeof(motor) == "Instance" and motor:IsA("Motor6D")
		or type(motor) == "table" and motor.IsEclipseBoneMotor
	local rig = joint and motor.Part1 and rigOf(motor)
	local LimbIK = require("LimbIK")
	local entry = rig and LimbIK.getRig(rig)
	local chain = entry and entry.members[motor]
	local poleChain = chain
			and (chain.kind == "R15" or chain.kind == "R6" and chain.limb == "Leg")
			and chain
		or nil
	if poleChain and LimbIK.isEnabled(chain.owner, state.Timeline:GetState().CurrentTime) then
		refs.Finalize()
		openedAt = os.clock()
		session = { motor = chain.owner, rig = rig, poleChain = poleChain, poleOnly = true }
		session.panel = buildPanel()
		Editor.editPole(controlKind)
		return true
	end

	if
		typeof(motor) ~= "Instance"
		or not motor:IsA("Motor6D")
		or not motor.Part1
		or not motor.Part1:IsA("BasePart")
		or not motor.Part0
	then
		Notification.show("EDIT PIVOT", "Select a limb first. Pivots work on normal rig parts.")
		return false
	end

	local attachmentPart = attachment and require("Target").attachmentObject(rig) or nil
	if attachment and (not attachmentPart or not attachmentPart:IsA("BasePart")) then
		Notification.show("EDIT PIVOT", "Choose a part in AttachToPart at this frame first.")
		return false
	end

	if CameraRig.owner(motor) and not attachment then
		Notification.show("EDIT PIVOT", "Cameras keep their own pivot.")
		return false
	end

	if PivotSpace.blocked(motor, state.Timeline:GetState().CurrentTime) then
		return refuseIK()
	end

	refs.Finalize()
	openedAt = os.clock()
	local original = PivotSpace.get(motor)
	local motors = attachment and { motor } or motorList(rig)
	if not table.find(motors, motor) then
		table.insert(motors, motor)
	end

	local start = {}
	for _, item in motors do
		start[item] = PivotSpace.get(item)
	end

	session = {
		motor = motor,
		attachmentPart = attachmentPart,
		poleChain = poleChain,
		rig = rig,
		motors = motors,
		start = start,
		original = original,
		current = original or motor.C1.Position,
		undo = {},
		redo = {},
	}
	if state.Axis then
		state.Axis:SetPlaybackHidden(true)
	end

	buildVisual()
	session.panel = buildPanel()
	return true
end

function Editor.toggle()
	if session then
		return Editor.finish(false)
	end

	return Editor.start()
end

local function beginDrag(mouse)
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local frame = editPart().CFrame
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	session.pending = snapshot()
	if overHandle(camera, mouse) then
		session.drag = { kind = "center", start = session.current }
		return true
	end

	local gizmo, gizmoScore = gizmoUnderMouse(camera, mouse)
	local target, targetScore = nearestTarget(camera, mouse, SNAP_PIXELS)
	if gizmo and (not target or gizmoScore <= targetScore) then
		local origin = frame:PointToWorldSpace(session.current)
		if gizmo.kind == "axis" then
			local direction = axisDirection(gizmo.axis)
			session.drag = {
				kind = "axis",
				axis = gizmo.axis,
				direction = direction,
				start = session.current,
				origin = origin,
				along = paramOnAxis(ray, origin, frame:VectorToWorldSpace(direction)),
			}
		else
			local plane = PLANES[gizmo.plane]
			local normal = axisDirection(plane[3])
			session.drag = {
				kind = "plane",
				plane = gizmo.plane,
				normal = normal,
				start = session.current,
				origin = origin,
				hit = planeHit(ray, origin, frame:VectorToWorldSpace(normal)),
			}
		end

		return true
	end

	if target then
		session.current = target.point
		session.snapped = target
		session.drag = { kind = "center", start = session.current }
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { editPart() }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if hit then
		local world = hit.Position
		if not held(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift) then
			world = planeHit(ray, frame.Position, camera.CFrame.LookVector) or world
		end

		session.current = frame:PointToObjectSpace(world)
		session.snapped = nil
		session.drag = { kind = "center", start = session.current }
		return true
	end

	session.pending = nil
	return false
end

local function endDrag()
	dragTo(Input:GetMouseLocation())
	session.drag = nil
	local pending = session.pending
	session.pending = nil
	if pending and not same(pending, snapshot()) then
		remember(pending)
	end
end

local function cancelDrag()
	local pending = session.pending
	session.drag = nil
	session.pending = nil
	if pending then
		restoreSnapshot(pending)
	end

	step()
end

function Editor.undo()
	if session and (not session.poleOnly or session.poleEditing) and not session.drag then
		undoStep()
	end
end

function Editor.redo()
	if session and (not session.poleOnly or session.poleEditing) and not session.drag then
		redoStep()
	end
end

function Editor.input(input, processed)
	if not session then
		return false
	end

	local kind = input.UserInputType
	if session.drag and session.drag.modal and kind == Enum.UserInputType.MouseButton2 then
		cancelDrag()
		return true
	end

	if kind == Enum.UserInputType.MouseButton1 then
		if processed or Input.inWidget() or Input.pointerOverUI() then
			return false
		end

		local mouse = Input:GetMouseLocation()
		if overPanel(mouse) then
			return true
		end

		if session.poleOnly and not session.poleEditing then
			return true
		end

		if session.drag and session.drag.modal then
			endDrag()
			step()
			return true
		end

		beginDrag(mouse)
		return true
	end

	if kind ~= Enum.UserInputType.Keyboard or Input:GetFocusedTextBox() then
		return false
	end

	local key = input.KeyCode
	if Shortcuts.matches("Cancel", input) then
		if session.drag and session.drag.modal then
			cancelDrag()
			return true
		end

		Editor.finish(true)
		return true
	end

	if
		key == Enum.KeyCode.Return
		or key == Enum.KeyCode.KeypadEnter
		or Shortcuts.matches("EditPivot", input)
	then
		if session.drag and session.drag.modal then
			endDrag()
			step()
			return true
		end

		if os.clock() - openedAt > 0.2 then
			Editor.finish(false)
		end

		return true
	end

	if session.poleOnly and not session.poleEditing then
		return true
	end

	if Shortcuts.matches("ToggleBlenderGrab", input) then
		if processed or session.drag then
			return true
		end

		if session.poleEditing and refs.State.Timeline:GetState().CurrentTime ~= session.time then
			return true
		end

		local drag = { kind = "center", modal = true }
		if anchorGrab(drag, Input:GetMouseLocation()) then
			session.pending = snapshot()
			session.drag = drag
		end

		return true
	end

	if key == Enum.KeyCode.R or key == Enum.KeyCode.Backspace then
		if session.drag and session.drag.modal then
			cancelDrag()
			resetToJoint()
			return true
		end

		if session.drag then
			session.current = session.joint.point
			session.snapped = session.joint
			session.drag = { kind = "center", start = session.current }
		else
			resetToJoint()
		end

		return true
	end

	if
		session.drag
		and session.drag.kind == "center"
		and (key == Enum.KeyCode.X or key == Enum.KeyCode.Y or key == Enum.KeyCode.Z)
	then
		local axis = Preferences.axisName(key.Name)
		session.drag.lockAxis = if session.drag.lockAxis == axis then nil else axis
		if session.drag.modal then
			anchorGrab(session.drag, Input:GetMouseLocation())
		else
			session.drag.start = session.current
		end

		return true
	end

	return true
end

function Editor.inputEnded(input)
	if
		session
		and session.drag
		and not session.drag.modal
		and input.UserInputType == Enum.UserInputType.MouseButton1
	then
		endDrag()
		return true
	end

	return false
end

function Editor.destroy()
	if session then
		Editor.finish(true)
	end

	if connection then
		connection:Disconnect()
		connection = nil
	end

	for _, item in connections do
		item:Disconnect()
	end

	table.clear(connections)
end

function Editor.init(options)
	Editor.destroy()
	refs = options
	options.State.PivotEditor = Editor
	connection = Run.RenderStepped:Connect(step)
	table.insert(connections, Input.InputEnded:Connect(Editor.inputEnded))
	table.insert(
		connections,
		Input.WindowFocusReleased:Connect(function()
			if session then
				if session.drag and session.drag.modal then
					cancelDrag()
					return
				end

				session.drag = nil
			end
		end)
	)
	options.Plugin.Unloading:Once(Editor.destroy)
	options.ScreenGui.Destroying:Once(Editor.destroy)
end

return Editor
