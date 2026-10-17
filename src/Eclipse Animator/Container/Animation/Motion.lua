--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Input = require("UserInputService")
local RunService = game:GetService("RunService")
local Motion = {}
local active

local floatingRoots = {}
local floatingHidden = false

function Motion.isFloatingHidden(object)
	local root = object and object:FindFirstAncestorWhichIsA("ScreenGui")
	local entry = root and floatingRoots[root]
	return entry ~= nil and not entry.host.Visible
end

function Motion.isFloatingChildOf(child, parent)
	local entry = floatingRoots[parent]
	return child.Parent == parent or entry ~= nil and child.Parent == entry.host
end

function Motion.watchFloatingGui(root)
	if not root then
		return
	end

	if not root:IsA("ScreenGui") then
		root = root:FindFirstAncestorWhichIsA("ScreenGui")
	end

	if not root or floatingRoots[root] then
		return
	end

	local host = Instance.new("Frame")
	host.Name = "EclipseFloatingVisibility"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromScale(1, 1)
	host.Active = false
	host.Visible = not floatingHidden
	host.Parent = root
	local entry = { host = host }
	floatingRoots[root] = entry

	local function child(object)
		if
			object ~= host
			and (object:IsA("GuiObject") or object:IsA("Folder") and object.Name == "Dropdowns")
			and object.Parent == root
		then
			object.Parent = host
		end
	end

	entry.added = root.ChildAdded:Connect(function(object)
		task.defer(function()
			if floatingRoots[root] == entry and host.Parent == root then
				child(object)
			end
		end)
	end)
	for _, object in root:GetChildren() do
		child(object)
	end

	root.Destroying:Once(function()
		entry.added:Disconnect()
		floatingRoots[root] = nil
	end)
end

function Motion.setFloatingHidden(hidden)
	hidden = hidden == true
	if hidden == floatingHidden then
		return
	end

	floatingHidden = hidden
	for root, entry in floatingRoots do
		if root.Parent and entry.host.Parent and entry.host.Visible == hidden then
			entry.host.Visible = not hidden
		end
	end
end

function Motion.coordinateParent(window)
	local parent = window.Parent
	while parent and not parent:IsA("GuiBase2d") do
		parent = parent.Parent
	end

	return parent
end

function Motion.reachable(position, size, viewport, anchor, scale)
	scale = math.max(scale or 1, 0.001)
	local visibleX = math.min(size.X, 96 / scale, viewport.X)
	local visibleY = math.min(size.Y, 20 / scale, viewport.Y)
	local left = position.X.Scale * viewport.X + position.X.Offset - size.X * anchor.X
	local top = position.Y.Scale * viewport.Y + position.Y.Offset - size.Y * anchor.Y
	local minX, maxX =
		math.ceil(visibleX - size.X + size.X * anchor.X),
		math.floor(viewport.X - visibleX + size.X * anchor.X)
	local minY, maxY =
		math.ceil(-4 / scale + size.Y * anchor.Y),
		math.floor(viewport.Y - visibleY + size.Y * anchor.Y)
	return UDim2.fromOffset(
		math.clamp(left + size.X * anchor.X, minX, math.max(minX, maxX)),
		math.clamp(top + size.Y * anchor.Y, minY, math.max(minY, maxY))
	)
end

function Motion.inside(position, size, viewport, anchor)
	local x = position.X.Scale * viewport.X + position.X.Offset - size.X * anchor.X
	local y = position.Y.Scale * viewport.Y + position.Y.Offset - size.Y * anchor.Y
	return UDim2.fromOffset(
		math.clamp(x, 0, math.max(0, viewport.X - size.X)) + size.X * anchor.X,
		math.clamp(y, 0, math.max(0, viewport.Y - size.Y)) + size.Y * anchor.Y
	)
end

local resetBindings = setmetatable({}, { __mode = "k" })

local revealGuards = setmetatable({}, { __mode = "k" })

function Motion.preserveNextReveal(object, property)
	for window in resetBindings do
		if
			(property == "Visible" and window == object)
			or (
				property == "Enabled"
				and window:FindFirstAncestorWhichIsA("LayerCollector") == object
			)
		then
			local guards = revealGuards[window] or {}
			revealGuards[window] = guards
			guards[property] = true
		end
	end
end

function Motion.resetOnOpen(window)
	Motion.watchFloatingGui(window)
	if resetBindings[window] then
		return
	end

	resetBindings[window] = true
	local origin, anchor
	local connections = {}

	local function reset()
		if not window.Parent or not window.Visible or window:GetAttribute("EclipseDocked") then
			return
		end

		local currentRoot = window:FindFirstAncestorWhichIsA("LayerCollector")
		if currentRoot and currentRoot:IsA("DockWidgetPluginGui") then
			return
		end

		origin, anchor = window.Position, window.AnchorPoint

		local scale = Motion.scale(window)
		local parent = Motion.coordinateParent(window)
		if not parent then
			return
		end

		local viewport = parent.AbsoluteSize / scale
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end

		local size = Vector2.new(
			window.Size.X.Scale * viewport.X + window.Size.X.Offset,
			window.Size.Y.Scale * viewport.Y + window.Size.Y.Offset
		)
		window.AnchorPoint = anchor
		window.Position = Motion.inside(origin, size, viewport, anchor)
	end

	local function schedule(property)
		local guards = revealGuards[window]
		if guards and guards[property] then
			guards[property] = nil
			return
		end

		task.defer(reset)
	end

	table.insert(
		connections,
		window:GetPropertyChangedSignal("Visible"):Connect(function()
			if window.Visible then
				schedule("Visible")
			end
		end)
	)
	local root = window:FindFirstAncestorWhichIsA("LayerCollector")
	if root then
		table.insert(
			connections,
			root:GetPropertyChangedSignal("Enabled"):Connect(function()
				if root.Enabled then
					schedule("Enabled")
				end
			end)
		)
	end

	window.Destroying:Once(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	schedule()
end

function Motion.constrain(window, position)
	local scale = Motion.scale(window)
	local parent = Motion.coordinateParent(window)
	if not parent then
		return position
	end

	local viewport = parent.AbsoluteSize / scale
	if viewport.X <= 0 or viewport.Y <= 0 then
		return position
	end

	local size = Vector2.new(
		window.Size.X.Scale * viewport.X + window.Size.X.Offset,
		window.Size.Y.Scale * viewport.Y + window.Size.Y.Offset
	)
	return Motion.reachable(position, size, viewport, window.AnchorPoint, scale)
end

function Motion.scale(window)
	local scale, parent = 1, window.Parent
	while parent do
		local factor = parent:FindFirstChildOfClass("UIScale")
		if factor then
			scale *= factor.Scale
		end

		parent = parent.Parent
	end

	return math.max(scale, 0.001)
end

function Motion.placePopup(window, anchor, side)
	local root = window:FindFirstAncestorWhichIsA("LayerCollector")
	local parent = Motion.coordinateParent(window)
	if not root or not parent then
		return
	end

	local origin, area = root.AbsolutePosition, root.AbsoluteSize
	local p, a = anchor.AbsolutePosition, anchor.AbsoluteSize
	local factor = window:FindFirstChildOfClass("UIScale")
	local size = window.AbsoluteSize / math.max(factor and factor.Scale or 1, 0.001)
	local scale = Motion.scale(window)
	local gap = 3 * scale
	local x, y = p.X + a.X + gap, p.Y
	if side == "below" then
		x, y = p.X, p.Y + a.Y + gap
		if y + size.Y > origin.Y + area.Y then
			y = p.Y - size.Y - gap
		end
	elseif x + size.X > origin.X + area.X then
		x = p.X - size.X - gap
	end

	x = math.clamp(x, origin.X, math.max(origin.X, origin.X + area.X - size.X))
	y = math.clamp(y, origin.Y, math.max(origin.Y, origin.Y + area.Y - size.Y))
	window.AnchorPoint = Vector2.zero
	window.Position = UDim2.fromOffset(
		(x - parent.AbsolutePosition.X) / scale,
		(y - parent.AbsolutePosition.Y) / scale
	)
end

local function isolate(window)
	local owner, originalParent = window, window.Parent
	local root = window:FindFirstAncestorWhichIsA("LayerCollector")
	if not root or not root:IsA("ScreenGui") or root:GetAttribute("EclipseWindowIsolated") then
		return function() end
	end

	local coordinateParent = Motion.coordinateParent(window)
	if not coordinateParent then
		return function() end
	end

	local layer = Instance.new("ScreenGui")
	layer.Name = "EclipseWindowMotion"
	for _, property in
		{
			"IgnoreGuiInset",
			"ScreenInsets",
			"ClipToDeviceSafeArea",
			"SafeAreaCompatibility",
			"ZIndexBehavior",
		}
	do
		layer[property] = root[property]
	end

	layer.ResetOnSpawn = false
	layer.DisplayOrder = root.DisplayOrder + 1
	layer.Enabled = root.Enabled
	local factor = Motion.scale(window)
	local parentPosition, parentSize =
		coordinateParent.AbsolutePosition, coordinateParent.AbsoluteSize
	local scale = Instance.new("UIScale")
	scale.Scale = factor
	scale.Parent = layer
	layer.Parent = root.Parent
	local host = layer
	if coordinateParent ~= root then
		host = Instance.new("Frame")
		host.Name = "Coordinates"
		host.BackgroundTransparency = 1
		host.BorderSizePixel = 0

		local offset, viewport = parentPosition - root.AbsolutePosition, root.AbsoluteSize
		host.Position = UDim2.fromScale(offset.X / viewport.X, offset.Y / viewport.Y)
		host.Size = UDim2.fromScale(parentSize.X / viewport.X, parentSize.Y / viewport.Y)
		host.Parent = layer
	end

	owner.Parent = host
	local released = false
	return function()
		if released then
			return
		end

		released = true
		if owner.Parent == host then
			owner.Parent = originalParent
		end

		layer:Destroy()
	end
end

function Motion.isMoving(window)
	return active ~= nil
		and (window == nil or active.window == window or window:IsDescendantOf(active.window))
end

function Motion.isTranslating(window)
	return active ~= nil
		and (active.kind == nil or active.kind == "move")
		and Motion.isMoving(window)
end

function Motion.begin(window, input, apply, finished, kind)
	if active then
		active.finish()
	end

	local gesture = { window = window, kind = kind }
	local connections, pending, release, stopped = {}, nil, nil, false
	local last = input.Position

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	function gesture.flush()
		local point = pending
		pending = nil
		if stopped or not point or not window.Parent or not window.Visible then
			return
		end

		if not release and kind ~= "divider" then
			release = isolate(window)
		end

		apply(point)
	end

	function gesture.finish(cancel)
		if stopped then
			return
		end

		if not cancel then
			gesture.flush()
		end

		stopped = true
		for _, connection in connections do
			connection:Disconnect()
		end

		if release then
			release()
		end

		if active == gesture then
			active = nil
		end

		if finished then
			finished()
		end
	end

	active = gesture
	connect(Input.InputChanged, function(changed)
		local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
			and changed.UserInputType == Enum.UserInputType.MouseMovement
		if (mouse or changed == input) and changed.Position ~= last then
			last = changed.Position
			pending = changed.Position
		end
	end)
	connect(RunService.PreRender, gesture.flush)
	connect(Input.InputEnded, function(ended)
		if
			ended == input
			or (
				input.UserInputType == Enum.UserInputType.MouseButton1
				and ended.UserInputType == Enum.UserInputType.MouseButton1
			)
		then
			gesture.finish()
		end
	end)
	connect(Input.WindowFocusReleased, function()
		gesture.finish()
	end)
	connect(window.Destroying, function()
		gesture.finish(true)
	end)
	local parent = window
	while parent do
		local watched = parent
		if watched:IsA("GuiObject") or watched:IsA("LayerCollector") then
			local property = watched:IsA("GuiObject") and "Visible" or "Enabled"
			connect(watched:GetPropertyChangedSignal(property), function()
				if not watched[property] then
					gesture.finish(true)
				end
			end)
		end

		if parent:IsA("LayerCollector") then
			connect(parent.Destroying, function()
				gesture.finish(true)
			end)
			connect(parent:GetPropertyChangedSignal("AbsoluteSize"), function()
				gesture.finish()
			end)
			local scale = parent:FindFirstChildOfClass("UIScale")
			if scale then
				connect(scale:GetPropertyChangedSignal("Scale"), function()
					gesture.finish()
				end)
			end

			break
		end

		parent = parent.Parent
	end

	return gesture
end

return Motion
