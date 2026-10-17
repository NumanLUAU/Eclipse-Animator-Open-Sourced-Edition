--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Scene = require("Scene")
local Recovery = require("Recovery")
local History = require("History")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Cursor = require("RotateCursor")
local Shortcuts = require("Shortcuts")
local Edit = require("BlenderEdit")
local EditorInput = require("UserInputService")
local Document = require("Document")
local Path = require("Path")
local Timing = require("Timing")
local Display = {}

function Display.positionAt(part, frame, cache)
	cache = cache or {}
	local source = part:GetAttribute("ForcePath")
	if source ~= cache.pathSource then
		cache.pathSource, cache.pathSample, cache.pathEasing = source, nil, nil
		if source then
			local ok, data, sample = pcall(function()
				local value = Document.unpack(source)
				Path.validate({
					force = { points = value.points, smoothing = 0, easing = value.easing },
				})
				return value, Path.sampler(value.points)
			end)
			if ok then
				cache.pathSample, cache.pathEasing = sample, data.easing
			end
		end
	end

	if not cache.pathSample then
		return part.Position
	end

	local alpha = (frame - (part:GetAttribute("Frame") or 0))
		/ math.max(1, (part:GetAttribute("Duration") or 60) - 1)
	return part.Position + cache.pathSample(Timing.sample(cache.pathEasing, alpha))
end

local COLOR = Color3.fromRGB(242, 171, 196)
local refs, host, handles, selected, hovered, drag
local mode = "Move"
local shapes = {}
local connections = {}

local function editing()
	return (
		refs
		and refs.Active()
		and refs.State.Physics
		and refs.State.Physics.isEditorOpen
		and refs.State.Physics.isEditorOpen()
	) == true
end

local function radius(part)
	local value = part:GetAttribute("Radius")
	return typeof(value) == "number" and value == value and math.clamp(value, 0.1, 1000) or 5
end

function Display.segments(position, value)
	local lines = {}
	for axis = 1, 3 do
		for i = 1, 64 do
			local function point(angle)
				local a, b = math.cos(angle) * value, math.sin(angle) * value
				return position
					+ (
						axis == 1 and Vector3.new(0, a, b)
						or axis == 2 and Vector3.new(a, 0, b)
						or Vector3.new(a, b, 0)
					)
			end

			table.insert(lines, { point((i - 1) * math.pi / 32), point(i * math.pi / 32) })
		end
	end

	local center = math.clamp(value * 0.07, 0.4, 1.5)
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		table.insert(lines, { position - axis * center, position + axis * center })
	end

	return lines
end

function Display.sync(part, shape)
	local value = radius(part)
	local nextRadius = value
	if shape.size and part.Size ~= shape.size and value == shape.radius then
		local delta = part.Size - shape.size
		local largest = math.max(math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z))
		local length = math.abs(delta.X) == largest and part.Size.X
			or math.abs(delta.Y) == largest and part.Size.Y
			or part.Size.Z
		nextRadius = math.clamp(length / 2, 0.1, 1000)
		part:SetAttribute("Radius", nextRadius)
	end

	local size = Vector3.one * (nextRadius * 2)
	if part.Size ~= size then
		part.Size = size
	end

	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	shape.size, shape.radius = size, nextRadius
	return nextRadius
end

function Display.select(part)
	if not editing() then
		return false
	end

	assert(
		part and part.Parent and part:GetAttribute("EclipsePhysicsForce"),
		"choose a blast first"
	)
	if refs and refs.State.Rig and refs.State.Rig.ClearItemSelection then
		refs.State.Rig:ClearItemSelection()
	end

	selected = part
	hovered = nil
	Selection:Set({ part })
	Display.refresh()
end

function Display.deselect()
	if not selected and not drag then
		return
	end

	Display.finish(false)
	selected, hovered = nil, nil
	local keep = {}
	local changed = false
	for _, object in Selection:Get() do
		if object:GetAttribute("EclipsePhysicsForce") then
			changed = true
		else
			table.insert(keep, object)
		end
	end

	if changed then
		local previous = refs and refs.State.ignoreSelectionChanged
		if refs then
			refs.State.ignoreSelectionChanged = true
		end

		Selection:Set(keep)
		if refs then
			refs.State.ignoreSelectionChanged = previous
		end
	end

	Display.refresh()
end

function Display.hide()
	Display.finish(true)
	Display.deselect()
	Display.refresh()
end

function Display.setMode(value)
	mode = value == "Scale" and "Scale" or "Move"
	if handles then
		handles.Style = mode == "Scale" and Enum.HandlesStyle.Resize or Enum.HandlesStyle.Movement
	end
end

function Display.getMode()
	return mode
end

function Display.toggleMode()
	if
		not refs
		or not refs.Active()
		or not selected
		or not selected.Parent
		or not handles
		or not handles.Visible
	then
		return false
	end

	if
		refs.State.PhysicsSimulating
		or refs.State.Timeline:GetState().Playing
		or Input:GetFocusedTextBox()
	then
		return false
	end

	if drag then
		return true
	end

	Display.setMode(mode == "Move" and "Scale" or "Move")
	return true
end

function Display.isEditing()
	return drag ~= nil
end

local function planePoint(camera, point, pivot, normal)
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local denominator = ray.Direction:Dot(normal)
	if math.abs(denominator) < 1e-6 then
		return
	end

	return ray.Origin + ray.Direction * ((pivot - ray.Origin):Dot(normal) / denominator)
end

function Display.start(value)
	if drag then
		return true
	end

	if
		not refs
		or not refs.Active()
		or not selected
		or not selected.Parent
		or not handles
		or not handles.Visible
	then
		return false
	end

	if
		refs.State.PhysicsSimulating
		or refs.State.Timeline:GetState().Playing
		or Input:GetFocusedTextBox()
		or EditorInput.inWidget()
		or Edit.blocked()
	then
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	if refs.Finalize then
		refs.Finalize()
	end

	Display.setMode(value)
	Display.begin()
	if not drag then
		return false
	end

	drag.pointer = true
	drag.mouse = Input:GetMouseLocation()
	drag.normal = camera.CFrame.LookVector
	drag.origin = shapes[selected] and shapes[selected].position or drag.cf.Position
	drag.plane = planePoint(camera, drag.mouse, drag.origin, drag.normal)
	if not drag.plane then
		drag = nil
		return false
	end

	Cursor.start(drag.origin, mode == "Move")
	hovered = nil
	handles.Visible = false
	return true
end

function Display.pointer(point)
	if not drag or not drag.pointer or not drag.part.Parent then
		return
	end

	local fine = (
		Input:IsKeyDown(Enum.KeyCode.LeftShift) or Input:IsKeyDown(Enum.KeyCode.RightShift)
	)
			and 0.1
		or 1
	if drag.mode == "Scale" then
		drag.part:SetAttribute(
			"Radius",
			math.clamp(
				drag.radius * math.exp(math.clamp((drag.mouse.Y - point.Y) * fine / 160, -12, 12)),
				0.1,
				1000
			)
		)
	else
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local world = planePoint(camera, point, drag.origin, drag.normal)
		if world then
			local delta = (world - drag.plane) * fine
			if drag.axis then
				delta = drag.axis * delta:Dot(drag.axis)
			end

			drag.part.CFrame = drag.cf + delta
		end
	end
end

function Display.keyboard(input)
	if not drag or not drag.pointer then
		return false
	end

	if
		Shortcuts.matches("Cancel", input)
		or input.UserInputType == Enum.UserInputType.MouseButton2
	then
		Display.finish(true)
	elseif
		Shortcuts.matches("ConfirmTransform", input)
		or Shortcuts.matches("ConfirmTransformAlternate", input)
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		Display.finish(false)
	elseif drag.mode == "Move" then
		local axis = input.KeyCode == Enum.KeyCode.X and Vector3.xAxis
			or input.KeyCode == Enum.KeyCode.Y and Vector3.yAxis
			or input.KeyCode == Enum.KeyCode.Z and Vector3.zAxis
		if axis then
			drag.axis = if drag.axis == axis then nil else axis
		end
	end

	return true
end

function Display.begin()
	if
		not selected
		or not selected.Parent
		or refs.State.Timeline:GetState().Playing
		or refs.State.PhysicsSimulating
	then
		return
	end

	drag = { part = selected, cf = selected.CFrame, radius = radius(selected), mode = mode }
end

function Display.change(face, distance)
	if not drag or not drag.part.Parent then
		return
	end

	if drag.mode == "Scale" then
		drag.part:SetAttribute("Radius", math.clamp(drag.radius + distance, 0.1, 1000))
	else
		drag.part.CFrame = drag.cf
			+ drag.cf:VectorToWorldSpace(Vector3.FromNormalId(face)) * distance
	end

	Display.refresh()
end

function Display.finish(cancel)
	if not drag then
		return
	end

	local before = drag
	drag = nil
	if before.pointer then
		Cursor.stop()
	end

	local part = before.part
	if not part.Parent then
		return
	end

	local after = { cf = part.CFrame, radius = radius(part) }

	local function apply(value)
		if part.Parent then
			part.CFrame = value.cf
			part:SetAttribute("Radius", value.radius)
			Display.refresh()
		end

		if refs then
			refs.State.currentProjectSaved = false
		end
	end

	if cancel then
		apply(before)
		return
	end

	if before.cf == after.cf and before.radius == after.radius then
		return
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, before.mode == "Scale" and "Scale blast radius" or "Move blast")
end

local function distance(point, a, b)
	local delta = b - a
	local alpha = delta:Dot(delta) > 1e-8
			and math.clamp((point - a):Dot(delta) / delta:Dot(delta), 0, 1)
		or 0
	return (point - a - delta * alpha).Magnitude
end

function Display.hit(camera, point, entries)
	if not camera then
		return
	end

	local best, gap = nil, 10
	for part, shape in entries or shapes do
		if not part.Parent or not shape.visible then
			continue
		end

		local center = camera:WorldToScreenPoint(shape.position or part.Position)
		if center.Z > 0 and (Vector2.new(center.X, center.Y) - point).Magnitude < 12 then
			return part
		end

		for _, line in shape.lines or {} do
			local a, b = camera:WorldToScreenPoint(line[1]), camera:WorldToScreenPoint(line[2])
			if a.Z <= 0 or b.Z <= 0 then
				continue
			end

			local value = distance(point, Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y))
			if value < gap then
				best, gap = part, value
			end
		end
	end

	return best
end

function Display.input(point)
	if
		not editing()
		or refs.State.PresentationHidden
		or refs.State.PhysicsSimulating
		or refs.State.Timeline:GetState().Playing
	then
		return false
	end

	if hovered or drag then
		return true
	end

	local part = Display.hit(workspace.CurrentCamera, point)
	if not part then
		Display.deselect()
		return false
	end

	Display.select(part)
	return true
end

function Display.refresh()
	if not refs or not refs.State.Timeline then
		return
	end

	if not host or host.Parent ~= workspace.CurrentCamera then
		if host then
			host:Destroy()
		end

		shapes = {}
		if not workspace.CurrentCamera then
			return
		end

		host = Recovery.mark(Instance.new("Folder"))

		host.Name = "EclipseBlastDisplay"
		host.Parent = workspace.CurrentCamera
	end

	if drag and drag.pointer then
		Display.pointer(Input:GetMouseLocation())
	end

	local editor = editing()
	local visible = editor
		and not refs.State.PresentationHidden
		and not refs.State.PhysicsSimulating
	local editable = visible and not refs.State.Timeline:GetState().Playing
	local raw = refs.State.Timeline:GetState()
	local frame = raw.CurrentTime * raw.FPS
	local active = {}
	for _, part in Scene.get().forces do
		if not part.Parent then
			continue
		end

		if editor then
			if part.Parent ~= workspace then
				part.Parent = workspace
			end
		elseif part.Parent == workspace then
			Recovery.parkForce(part)
		end

		active[part] = true
		local shape = shapes[part]
		if not shape then
			local wire = Instance.new("WireframeHandleAdornment")

			wire.Name = "BlastRadius"
			wire.Adornee = workspace.Terrain
			wire.AlwaysOnTop = true
			wire.Color3 = COLOR
			wire.Thickness = 2
			wire.Parent = host
			local proxy = Instance.new("Part")
			proxy.Name = "ForcePreviewAnchor"
			proxy.Anchored = true
			proxy.Transparency = 1
			proxy.CanCollide, proxy.CanTouch, proxy.CanQuery = false, false, false
			proxy.Parent = host
			shape = { wire = wire, proxy = proxy }
			shapes[part] = shape
		end

		local value = Display.sync(part, shape)
		local position = Display.positionAt(part, frame, shape)
		shape.proxy.CFrame = part.CFrame.Rotation + position
		shape.proxy.Size = part.Size
		shape.visible = visible
		shape.wire.Visible = visible
		shape.wire.Thickness = part == selected and 3 or 2
		if shape.position ~= position or shape.drawnRadius ~= value then
			shape.position, shape.drawnRadius = position, value
			shape.lines = Display.segments(position, value)
			shape.wire:Clear()
			for _, line in shape.lines do
				shape.wire:AddLine(line[1], line[2])
			end
		end
	end

	for part, shape in shapes do
		if not active[part] then
			Recovery.parkForce(part)
			shape.wire:Destroy()
			shape.proxy:Destroy()
			shapes[part] = nil
		end
	end

	if selected and not active[selected] then
		selected = nil
	end

	if handles then
		handles.Adornee = selected and shapes[selected] and shapes[selected].proxy
		handles.Visible = editable and selected ~= nil and not (drag and drag.pointer)
	end

	if not editable then
		Display.finish(true)
		hovered = nil
	end
end

function Display.destroy()
	Display.finish(true)
	for part in shapes do
		Recovery.parkForce(part)
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	if host then
		host:Destroy()
	end

	if handles then
		handles:Destroy()
	end

	host, handles, selected, hovered, refs = nil, nil, nil, nil, nil
	shapes = {}
end

function Display.init(options)
	Display.destroy()
	refs = options
	options.State.PhysicsDisplay = Display
	handles = Recovery.mark(Instance.new("Handles"))

	handles.Name = "BlastHandles"
	handles.Color3 = COLOR
	handles.Visible = false
	handles.Parent = options.ScreenGui
	Display.setMode("Move")

	local function connect(signal, fn)
		table.insert(connections, signal:Connect(fn))
	end

	connect(handles.MouseEnter, function(face)
		hovered = face
	end)
	connect(handles.MouseLeave, function()
		hovered = nil
	end)
	connect(handles.MouseButton1Down, Display.begin)
	connect(handles.MouseDrag, Display.change)
	connect(handles.MouseButton1Up, function()
		if not drag or not drag.pointer then
			Display.finish(false)
		end
	end)
	connect(Input.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and drag and not drag.pointer then
			Display.finish(false)
		end
	end)
	connect(Input.InputBegan, function(input)
		if drag and not drag.pointer and input.KeyCode == Enum.KeyCode.Escape then
			Display.finish(true)
		end
	end)
	connect(Input.WindowFocusReleased, function()
		Display.finish(true)
	end)
	connect(Selection.SelectionChanged, function()
		local part = Selection:Get()[1]
		if
			part
			and part:GetAttribute("EclipsePhysicsForce")
			and table.find(Scene.get().forces, part)
		then
			selected = part
		else
			Display.finish(false)
			selected = nil
			hovered = nil
		end

		Display.refresh()
	end)
	connect(RunService.RenderStepped, Display.refresh)
	connect(options.Plugin.Unloading, Display.destroy)
	connect(options.ScreenGui.Destroying, Display.destroy)
end

return Display
