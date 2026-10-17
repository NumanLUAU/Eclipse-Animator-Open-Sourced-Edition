--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Cursor = require("Cursor")
local RotationCursor = {}
local GUI_NAME = "EclipseRotateCursor"
local RENDER_NAME = "EclipseAnimator_RotationCursor"
local RESTORE_ATTRIBUTE = "EclipseRestoreMouseIconEnabled"
local RESTORE_PLUGIN_ATTRIBUTE = "EclipseRestorePluginMouseIcon"
local BLANK_CURSOR = "rbxasset://textures/Blank.png"
local WHITE = Color3.fromRGB(250, 250, 250)
local OUTLINE = Color3.fromRGB(25, 25, 29)
local DASH_PITCH = 9
local DASH_LENGTH = 5

local gui, cursor, guide, normalIcon, trackballIcon, circle, readout
local circleRadius
local pivot, previousMouseVisible
local pluginMouse, previousPluginIcon
local active = false
local isCurrent
local focused = true
local trackball = false
local dashes = {}
local visibleDashCount = 0
local lastMouse, lastProjection, lastLength
local connections = {}

local function frame(name, parent)
	local value = Instance.new("Frame")
	value.Name = name
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Size = UDim2.fromOffset(0, 0)
	value.Active = false
	value.Parent = parent
	return value
end

local function segment(parent, from, to, thickness, color, layer)
	local delta = to - from
	local value = frame("Stroke", parent)
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromOffset((from.X + to.X) * 0.5, (from.Y + to.Y) * 0.5)
	value.Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.5, thickness)
	value.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	value.BackgroundColor3 = color
	value.BackgroundTransparency = 0
	value.ZIndex = layer
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, thickness * 0.5)
	corner.Parent = value
	return value
end

local function arrows(parent, vertical)
	local paths = {
		{ Vector2.new(-10, 0), Vector2.new(10, 0) },
		{ Vector2.new(-10, 0), Vector2.new(-5, -5) },
		{ Vector2.new(-10, 0), Vector2.new(-5, 5) },
		{ Vector2.new(10, 0), Vector2.new(5, -5) },
		{ Vector2.new(10, 0), Vector2.new(5, 5) },
	}
	if vertical then
		for index = 1, 5 do
			local path = paths[index]
			table.insert(
				paths,
				{ Vector2.new(path[1].Y, path[1].X), Vector2.new(path[2].Y, path[2].X) }
			)
		end
	end

	for _, path in ipairs(paths) do
		segment(parent, path[1], path[2], 5, OUTLINE, 3)
	end

	for _, path in ipairs(paths) do
		segment(parent, path[1], path[2], 2, WHITE, 4)
	end
end

local function restoreMouse()
	Cursor.release(RotationCursor)
end

local function recoverStale()
	RunService:UnbindFromRenderStep(RENDER_NAME)
	local stale = CoreGui:FindFirstChild(GUI_NAME)
	if stale then
		local saved = stale:GetAttribute(RESTORE_ATTRIBUTE)
		if typeof(saved) == "boolean" then
			UserInputService.MouseIconEnabled = saved
		end

		local savedIcon = stale:GetAttribute(RESTORE_PLUGIN_ATTRIBUTE)
		if pluginMouse and typeof(savedIcon) == "string" and pluginMouse.Icon == BLANK_CURSOR then
			pluginMouse.Icon = savedIcon
		end

		stale:Destroy()
	end
end

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	recoverStale()
	gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2147483647
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.Enabled = false
	gui.Parent = CoreGui
	guide = frame("DottedGuide", gui)
	circle = frame("RotationCircle", gui)
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle
	local outline = Instance.new("UIStroke")
	outline.Color = WHITE
	outline.Thickness = 1.5
	outline.Transparency = 0.2
	outline.Parent = circle
	cursor = frame("RotateCursor", gui)
	readout = Instance.new("TextLabel")
	readout.Name = "Value"
	readout.AnchorPoint = Vector2.new(0.5, 0.5)
	readout.Position = UDim2.fromOffset(64, 18)
	readout.Size = UDim2.fromOffset(88, 22)
	readout.BackgroundTransparency = 1
	readout.Font = Enum.Font.RobotoMono
	readout.TextSize = 15
	readout.TextColor3 = WHITE
	readout.TextStrokeColor3 = OUTLINE
	readout.TextStrokeTransparency = 0.15
	readout.TextXAlignment = Enum.TextXAlignment.Left
	readout.ZIndex = 6
	readout.Visible = false
	readout.Parent = cursor
	normalIcon = frame("Rotate", cursor)
	trackballIcon = frame("Trackball", cursor)
	arrows(normalIcon, false)
	arrows(trackballIcon, true)
	gui.Destroying:Connect(function()
		RotationCursor.stop()
	end)
	dashes = {}
	visibleDashCount = 0
end

local function setGuideLength(length)
	local count = math.max(0, math.ceil(length / DASH_PITCH))
	for index = #dashes + 1, count do
		local dash = frame("Dash", guide)
		dash.Position = UDim2.fromOffset((index - 1) * DASH_PITCH + DASH_LENGTH * 0.5, 0)
		dash.Size = UDim2.fromOffset(DASH_LENGTH, 2)
		dash.BackgroundColor3 = WHITE
		dash.BackgroundTransparency = 0.08
		dash.ZIndex = 2
		local outline = Instance.new("UIStroke")
		outline.Name = "Outline"
		outline.Color = OUTLINE
		outline.Thickness = 1
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline.Parent = dash
		dashes[index] = dash
	end

	for index = count + 1, visibleDashCount do
		dashes[index].Visible = false
	end

	for index = visibleDashCount + 1, count do
		dashes[index].Visible = true
	end

	if visibleDashCount > 0 then
		dashes[visibleDashCount].Size = UDim2.fromOffset(DASH_LENGTH, 2)
		dashes[visibleDashCount].Position = UDim2.fromOffset((visibleDashCount - 1) * DASH_PITCH + DASH_LENGTH * 0.5, 0)
	end

	if count > 0 then
		local width = math.min(DASH_LENGTH, length - (count - 1) * DASH_PITCH)
		dashes[count].Size = UDim2.fromOffset(width, 2)
		dashes[count].Position = UDim2.fromOffset((count - 1) * DASH_PITCH + width * 0.5, 0)
	end

	visibleDashCount = count
end

local function render()
	if not active or not gui or not gui.Parent then
		return
	end
	if isCurrent and not isCurrent() then
		RotationCursor.stop()
		return
	end

	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local size = camera and camera.ViewportSize
	local inside = focused
		and size
		and mouse.X >= 0
		and mouse.Y >= 0
		and mouse.X < size.X
		and mouse.Y < size.Y
	if not inside then
		gui.Enabled = false
		restoreMouse()
		return
	end

	gui.Enabled = true
	if not Cursor.hide(RotationCursor, pluginMouse) then
		gui.Enabled = false
		return
	end

	local projected = camera:WorldToViewportPoint(pivot)
	if mouse == lastMouse and projected == lastProjection then
		return
	end

	lastMouse, lastProjection = mouse, projected
	cursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	local center = Vector2.new(projected.X, projected.Y)
	circle.Visible = circleRadius ~= nil and projected.Z > 0 and not trackball
	if circle.Visible then
		local diameter = math.min(circleRadius, size.Magnitude) * 2
		circle.Position = UDim2.fromOffset(center.X, center.Y)
		circle.Size = UDim2.fromOffset(diameter, diameter)
	end

	local delta = mouse - center
	local distance = delta.Magnitude
	guide.Visible = projected.Z > 0 and distance > 14
	if guide.Visible then
		local direction = delta / distance
		local length = math.min(math.max(0, distance - 16), size.Magnitude + 8)
		local start = mouse - direction * (length + 12)
		guide.Position = UDim2.fromOffset(start.X, start.Y)
		guide.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		if length ~= lastLength then
			setGuideLength(length)
			lastLength = length
		end
	end

	if not trackball and distance > 6 then
		cursor.Rotation = math.deg(math.atan2(delta.Y, delta.X)) + 90
	end
end

local function guardedRender()
	local ok, err = pcall(render)
	if not ok then
		RotationCursor.stop()
		warn(tostring(err))
	end
end

function RotationCursor.setTrackball(enabled)
	trackball = enabled == true
	if not cursor then
		return
	end

	normalIcon.Visible = not trackball
	trackballIcon.Visible = trackball
	if trackball then
		cursor.Rotation = 0
	end

	lastMouse = nil
end

function RotationCursor.setValue(value)
	if readout then
		readout.Visible = typeof(value) == "number"
		readout.Text = typeof(value) == "number" and string.format("%.3f", value) or ""
	end
end

function RotationCursor.start(worldPivot, useTrackball, radius, current)
	RotationCursor.stop()
	ensureGui()
	pivot = worldPivot
	circleRadius = radius
	previousMouseVisible, previousPluginIcon = Cursor.snapshot(pluginMouse)
	gui:SetAttribute(RESTORE_ATTRIBUTE, previousMouseVisible)
	gui:SetAttribute(RESTORE_PLUGIN_ATTRIBUTE, previousPluginIcon)
	active = true
	isCurrent = current
	focused = true
	lastMouse, lastProjection, lastLength = nil, nil, nil
	RotationCursor.setTrackball(useTrackball)
	guardedRender()
	if active then
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 1, guardedRender)
	end
end

function RotationCursor.stop()
	RunService:UnbindFromRenderStep(RENDER_NAME)
	active = false
	isCurrent = nil
	RotationCursor.setValue(nil)
	restoreMouse()
	previousMouseVisible = nil
	previousPluginIcon = nil
	pivot = nil
	circleRadius = nil
	if circle then
		circle.Visible = false
	end

	if gui then
		gui.Enabled = false
		gui:SetAttribute(RESTORE_ATTRIBUTE, nil)
		gui:SetAttribute(RESTORE_PLUGIN_ATTRIBUTE, nil)
	end
end

function RotationCursor.destroy()
	RotationCursor.stop()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
	if gui then
		gui:Destroy()
	end

	gui, cursor, guide, normalIcon, trackballIcon, circle, readout = nil, nil, nil, nil, nil, nil, nil
	table.clear(dashes)
	visibleDashCount = 0
	pluginMouse = nil
end

function RotationCursor.attach(plugin, ownerGui, animatorFrame)
	RotationCursor.destroy()
	pluginMouse = plugin:GetMouse()
	recoverStale()
	table.insert(connections, plugin.Unloading:Connect(RotationCursor.destroy))
	table.insert(connections, plugin.Deactivation:Connect(RotationCursor.stop))
	table.insert(connections, ownerGui.Destroying:Connect(RotationCursor.destroy))
	table.insert(
		connections,
		ownerGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not ownerGui.Enabled then
				RotationCursor.stop()
			end
		end)
	)
	table.insert(
		connections,
		animatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not animatorFrame.Visible then
				RotationCursor.stop()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			focused = false
			if active then
				gui.Enabled = false
				restoreMouse()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocused:Connect(function()
			focused = true
		end)
	)
end

return RotationCursor
