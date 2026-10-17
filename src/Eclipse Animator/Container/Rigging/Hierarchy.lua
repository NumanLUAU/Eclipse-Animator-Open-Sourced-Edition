--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Shortcuts = require("Shortcuts")
local CameraRig = require("CameraRig")
local Motion = require("Motion")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")
local Organization = require("Organization")
local Preferences = require("Preferences")
local Hierarchy = {}

function Hierarchy.flatBone(item)
	return Preferences.get("FlatBoneList") == true
		and (
			item.itemKind == "bone"
			or item.itemKind == "displaybone"
			or item.itemKind == "ikcontrol"
			or item.itemKind == "mastercontrol"
			or item.itemKind == "origin"
		)
end

local PEACH = Color3.fromRGB(255, 190, 151)
local RED = Color3.fromRGB(245, 102, 111)

local function keyFor(item)
	if
		item.itemKind == "events"
		or item.itemKind == "subtitles"
		or item.itemKind == "faces"
		or item.itemKind == "channel"
		or (item.itemKind == "ikcontrol" or item.itemKind == "mastercontrol")
	then
		return nil
	end

	return item.organizationKey or item.linkedRigInstance
end

function Hierarchy.dragColor(item)
	return item.trackColor or item.centerDiv.ImgContainer.Img.ImageColor3
end

local function connect(session, signal, callback)
	local connection = signal:Connect(callback)
	table.insert(session.connections, connection)
	return connection
end

local function inside(point, object)
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X < p.X + s.X and point.Y < p.Y + s.Y
end

local function visible(object)
	local cursor = object
	while cursor do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end

		if cursor:IsA("ScreenGui") and not cursor.Enabled then
			return false
		end

		cursor = cursor.Parent
	end

	return true
end

local function scaleFor(object)
	local scale, cursor = 1, object
	while cursor do
		local value = cursor:FindFirstChildOfClass("UIScale")
		if value then
			scale *= value.Scale
		end

		cursor = cursor.Parent
	end

	return math.max(0.001, scale)
end

function Hierarchy.drawTrash(button)
	local function bar(x, y, w, h, rotation)
		local part = Instance.new("Frame")
		part.Name = "TrashStroke"
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		part.Position = UDim2.fromScale(x, y)
		part.Size = UDim2.fromOffset(w, h)
		part.Rotation = rotation or 0
		part.BorderSizePixel = 0
		part.BackgroundColor3 = RED
		part.ZIndex = button.ZIndex + 1
		part.Parent = button
	end

	bar(0.5, 0.26, 10, 1.5)
	bar(0.5, 0.13, 4, 1.5)
	bar(0.25, 0.58, 1.5, 8, -4)
	bar(0.75, 0.58, 1.5, 8, 4)
	bar(0.5, 0.84, 8, 1.5)
	bar(0.43, 0.56, 1, 5)
	bar(0.59, 0.56, 1, 5)
end

local function trash(session, item)
	if item.itemKind ~= "folder" and item.itemKind ~= "origin" and not item.trackIsMaster then
		return
	end

	local button = Instance.new("ImageButton")
	button.Name = "DeleteTrack"
	button.Image = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(15, 15)
	button.LayoutOrder = -100
	button.ZIndex = item.centerDiv.ZIndex + 1
	button.Parent = item.leftDiv
	local layout = item.leftDiv:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end

	local settings = item.trackIsMaster or item.itemKind == "origin"
	item.trashButton = button
	if settings then
		button.Name = "ItemSettings"
		button.Image = "rbxassetid://133038504099093"
		button.ImageColor3 = Color3.fromRGB(190, 212, 229)
	else
		Hierarchy.drawTrash(button)
	end

	local hover = session.rig.refs.UIHelpers.hoverDialog
	if hover then
		hover:latchToInstance(
			button,
			settings and "Item settings"
				or item.trackIsMaster and "Remove camera"
				or "Remove folder"
		)
	end

	connect(session, button.MouseButton1Click, function()
		if item.itemKind == "origin" then
			require("Origin").openSettings()
		elseif settings and session.rig.refs.OpenItemSettings then
			session.rig.refs.OpenItemSettings(item.linkedRigInstance)
		else
			Hierarchy.requestRemove(session.rig, item)
		end
	end)
end

function Hierarchy.requestRemove(rig, item)
	local session = rig._hierarchyOrganization
	if not session or session.drag then
		return false
	end

	local callback = item.trackIsMaster and rig.refs.RequestRemoveRig
		or item.itemKind == "folder" and rig.refs.RequestDeleteFolder
	if not callback then
		return false
	end

	callback(item.linkedRigInstance)
	return true
end

function Hierarchy.rename(rig, item)
	local session = rig._hierarchyOrganization
	if not session or item.itemKind ~= "folder" then
		return
	end

	if session.renameBox then
		session.renameBox:ReleaseFocus()
	end

	local title = item.centerDiv.Title
	local input = Instance.new("TextBox")
	input.Name = "FolderName"
	input.AnchorPoint, input.Position, input.Size = title.AnchorPoint, title.Position, title.Size
	input.LayoutOrder, input.AutomaticSize = title.LayoutOrder, title.AutomaticSize
	input.FontFace, input.TextSize = title.FontFace, title.TextSize
	input.TextXAlignment, input.TextYAlignment = title.TextXAlignment, title.TextYAlignment
	input.TextColor3 = title.TextColor3
	input.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	input.BackgroundTransparency = 0.05
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Text = Organization.get(item.linkedRigInstance).name
	input.ZIndex = title.ZIndex + 3
	input.Parent = item.centerDiv
	for _, child in title:GetChildren() do
		if child:IsA("UIConstraint") or child:IsA("UIFlexItem") then
			child:Clone().Parent = input
		end
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = input
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = PEACH, 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = input
	title.Visible = false
	session.renameBox = input
	local finished = false

	local function finish(cancel)
		if finished then
			return
		end

		finished = true
		local name = input.Text
		if session.renameBox == input then
			session.renameBox = nil
		end

		title.Visible = true
		input:Destroy()
		if not cancel and not session.dead then
			Organization.rename(item.linkedRigInstance, name)
		end
	end

	connect(session, input.FocusLost, function()
		finish(false)
	end)
	connect(session, input.InputBegan, function(event)
		if Shortcuts.matches("Cancel", event) then
			finish(true)
		end
	end)
	input:CaptureFocus()
	input.SelectionStart, input.CursorPosition = 1, #input.Text + 1
end

local function snapLine(entry, scale, hostY)
	local row, header, line = entry.row, entry.header, entry.line
	if not line or not line.Parent then
		return
	end

	local height = entry.height * scale
	local thickness = math.max(1, math.round(2 * scale))
	local rowY = hostY + entry.first * scale
	local center = hostY + entry.headerFirst * scale + height * 0.5
	local top = math.round(center - thickness * 0.5)
	local rowHeight = math.max(1, entry.rowHeight * scale)
	local size = UDim2.new(1, -21, thickness / rowHeight, 0)
	local position = UDim2.new(0.5, -10.5, (top + thickness * 0.5 - rowY) / rowHeight, 0)
	if line.AnchorPoint ~= Vector2.new(0.5, 0.5) then
		line.AnchorPoint = Vector2.new(0.5, 0.5)
	end

	if entry.lineSize ~= size then
		line.Size = size
		entry.lineSize = size
	end

	if entry.linePosition ~= position then
		line.Position = position
		entry.linePosition = position
	end

	if line.BorderSizePixel ~= 0 then
		line.BorderSizePixel = 0
	end
end

local function enableVirtual(session)
	if session.virtual then
		return
	end

	local rig = session.rig
	if #(rig._organizationItems or {}) < 128 and not Preferences.get("FlatBoneList") then
		return
	end

	local scroll = rig.refs.RigListScroll
	local storage = Instance.new("Folder")
	storage.Name = "EclipseParkedRows"
	local host = Instance.new("Frame")
	host.Name = "VirtualRigRows"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.new(1, 0, 0, 0)
	local list = scroll:FindFirstChildOfClass("UIListLayout")
	session.virtual =
		{ storage = storage, host = host, list = list, saved = {}, mounted = {}, byItem = {} }
	if list then
		list.Parent = storage
	end

	host.Parent = scroll
end

local function registerVirtual(session, item)
	local v = session.virtual
	local root = item.uiElement
	if v.saved[item] then
		return
	end

	v.saved[item] = {
		parent = root.Parent,
		position = root.Position,
		size = root.Size,
		automatic = root.AutomaticSize,
		childParent = item.childContainer.Parent,
		trackParent = item.trackElement.Parent,
	}
	item._virtualized = true
	root.Parent = v.storage
	root.AutomaticSize = Enum.AutomaticSize.None
	item.childContainer.Parent = v.storage
	root.AnchorPoint = Vector2.zero

	session.virtualBound = session.virtualBound or {}
	if session.virtualBound[item] then
		return
	end

	session.virtualBound[item] = true
	connect(session, root:GetPropertyChangedSignal("Visible"), function()
		Hierarchy.layout(session.rig)
	end)
	connect(session, root:GetPropertyChangedSignal("LayoutOrder"), function()
		Hierarchy.layout(session.rig)
	end)
	connect(session, item.appearDetails:GetPropertyChangedSignal("Size"), function()
		Hierarchy.layout(session.rig)
	end)
	connect(session, item.appearDetails:GetPropertyChangedSignal("Visible"), function()
		Hierarchy.layout(session.rig)
	end)
	connect(session, item.childContainer:GetPropertyChangedSignal("Visible"), function()
		Hierarchy.layout(session.rig)
	end)
	connect(session, item.trackElement:GetPropertyChangedSignal("Visible"), function()
		Hierarchy.layout(session.rig)
	end)
end

local function virtualLayout(session)
	local v, rig = session.virtual, session.rig
	local scroll, keys = rig.refs.RigListScroll, rig.refs.KeysRoot
	local scale = scaleFor(scroll)
	local rows = {}
	local byItem = {}
	local y = 0

	local function visit(item, x)
		registerVirtual(session, item)
		local root, header = item.uiElement, item.appearDetails
		if not root.Visible then
			return
		end

		if header.Visible then
			local height = header.Size.Y.Offset
			if height <= 0 then
				height = 19
			end

			local entry = {
				item = item,
				row = item.trackElement,
				header = header,
				line = item.trackElement:FindFirstChild("Line"),
				left = x,
				leftY = y,
				height = height,
				rowHeight = height,
			}
			byItem[item] = entry
			table.insert(rows, entry)
			y += height
		end

		if item.childContainer.Visible then
			local contents = item.childContainer.ChildrenContents
			local padding = contents:FindFirstChildOfClass("UIPadding")
			local layout = contents:FindFirstChildOfClass("UIListLayout")
			local children = {}
			for _, child in item.childItems do
				table.insert(children, child)
			end

			for _, child in item.transformChannelItems or {} do
				table.insert(children, child)
			end

			table.sort(children, function(a, b)
				return a.uiElement.LayoutOrder < b.uiElement.LayoutOrder
			end)
			local shown = false
			local gap = layout and layout.Padding.Offset or 0
			for _, child in children do
				if child.uiElement.Visible then
					y += shown and gap or padding and padding.PaddingTop.Offset or 0
					shown = true
					visit(
						child,
						Hierarchy.flatBone(item) and Hierarchy.flatBone(child) and x
							or x + (padding and padding.PaddingLeft.Offset or 0)
					)
				else
					registerVirtual(session, child)
				end
			end

			if shown then
				y += padding and padding.PaddingBottom.Offset or 0
			end
		end
	end

	local roots = table.clone(rig._rootItems)
	table.sort(roots, function(a, b)
		return a.uiElement.LayoutOrder < b.uiElement.LayoutOrder
	end)
	for _, root in roots do
		visit(root, 0)
	end

	for _, item in rig._organizationItems do
		registerVirtual(session, item)
		for _, child in item.transformChannelItems or {} do
			registerVirtual(session, child)
		end
	end

	v.host.Size = UDim2.new(1, 0, 0, y)
	local leftOrigin = scroll.AbsolutePosition.Y
	local pad = scroll:FindFirstChildOfClass("UIPadding")
	local inset = pad and pad.PaddingTop.Offset or 0
	local offset = (leftOrigin - session.host.AbsolutePosition.Y - keys.CanvasPosition.Y) / scale
		+ inset
	local maximum = 0
	for _, entry in rows do
		local row = entry.row
		entry.first = math.round(entry.leftY + offset)
		entry.headerFirst = entry.leftY + offset
		entry.last = entry.headerFirst + entry.height
		entry.maxEnd = entry.last
		row.AutomaticSize = Enum.AutomaticSize.None
		row.AnchorPoint = Vector2.zero
		row.Position = UDim2.fromOffset(0, entry.first)
		row.Size = UDim2.new(1, 0, 0, entry.height)
		maximum = math.max(maximum, entry.last)
		entry.item._virtualBounds =
			{ top = entry.leftY + inset, bottom = entry.leftY + inset + entry.height }
	end

	for item in v.saved do
		if not byItem[item] then
			item._virtualBounds = nil
		end

		local parent = item.trackElement.Visible and session.host or v.storage
		if item.trackElement.Parent ~= parent then
			item.trackElement.Parent = parent
		end
	end

	session.host.Size = UDim2.new(1, 0, 0, maximum)
	session.rows = rows
	v.byItem = byItem
	session.hostOffset = session.host.AbsolutePosition.Y
		- keys.AbsolutePosition.Y
		+ keys.CanvasPosition.Y
	session.viewportTop = keys.AbsolutePosition.Y
	session.viewportHeight = keys.AbsoluteWindowSize.Y
	session.paintStamp = nil
end

local function mountVirtual(session)
	local v = session.virtual
	if not v then
		return
	end

	local scroll = session.rig.refs.RigListScroll
	local scale = scaleFor(scroll)
	local stamp = v.stamp
	local height = scroll.AbsoluteWindowSize.Y
	local canvas = scroll.CanvasPosition.Y
	local width = math.max(scroll.CanvasSize.X.Offset, scroll.AbsoluteSize.X / scale)
	if
		stamp
		and stamp.rows == session.rows
		and stamp.height == height
		and stamp.canvas == canvas
		and stamp.scale == scale
		and stamp.width == width
	then
		return
	end

	v.stamp =
		{ rows = session.rows, height = height, canvas = canvas, scale = scale, width = width }
	local padding = scroll:FindFirstChildOfClass("UIPadding")
	width -= padding and padding.PaddingLeft.Offset + padding.PaddingRight.Offset or 0
	v.host.Size = UDim2.fromOffset(width, v.host.Size.Y.Offset)
	local first = scroll.CanvasPosition.Y / scale - 38
	local last = first + scroll.AbsoluteWindowSize.Y / scale + 76
	local wanted = {}
	local rows = session.rows or {}
	local low, high = 1, #rows
	while low <= high do
		local mid = (low + high) // 2
		if rows[mid].leftY + rows[mid].height < first then
			low = mid + 1
		else
			high = mid - 1
		end
	end

	for i = low, #rows do
		local e = rows[i]
		if e.leftY > last then
			break
		end

		local item = e.item
		wanted[item] = true
		local root = item.uiElement
		local position = UDim2.fromOffset(e.left, e.leftY)
		local size = UDim2.new(1, -e.left, 0, e.height)
		if root.Position ~= position then
			root.Position = position
		end

		if root.Size ~= size then
			root.Size = size
		end

		if root.Parent ~= v.host then
			root.Parent = v.host
		end

		item._virtualMounted = true
	end

	for item in v.mounted do
		if not wanted[item] then
			item.uiElement.Parent = v.storage
			item._virtualMounted = false
		end
	end

	v.mounted = wanted
end

local function restoreVirtual(session)
	local v = session.virtual
	if not v then
		return
	end

	for item, saved in v.saved do
		local root = item.uiElement
		item._virtualBounds = nil
		item._virtualMounted = nil
		item._virtualized = nil
		root.Position = saved.position
		root.Size = saved.size
		root.AutomaticSize = saved.automatic
		item.childContainer.Parent = saved.childParent
		root.Parent = saved.parent
		item.trackElement.Parent = saved.trackParent
	end

	if v.list then
		v.list.Parent = session.rig.refs.RigListScroll
	end

	v.host:Destroy()
	v.storage:Destroy()
	session.virtual = nil
end

local function updateLayout(session)
	if session.dead then
		return
	end

	if session.virtual then
		return virtualLayout(session)
	end

	local rig, host = session.rig, session.host
	local scroll, keys = rig.refs.RigListScroll, rig.refs.KeysRoot
	if
		rig._hierarchyOrganization ~= session
		or not host.Parent
		or not scroll.Parent
		or not keys.Parent
		or not visible(scroll)
	then
		return
	end

	local scale = scaleFor(host)
	local maximum = 0
	local rows = {}

	local function place(item)
		local row, header = item.trackElement, item.appearDetails
		if not row or not header or not row.Parent or not header.Parent then
			return
		end

		if row.Parent ~= host then
			row.Parent = host
		end

		if not session.layoutBound[header] then
			session.layoutBound[header] = true
			connect(session, header:GetPropertyChangedSignal("AbsolutePosition"), function()
				if session.virtual then
					return
				end

				local previous = session.headerDocuments and session.headerDocuments[header]
				local current = header.AbsolutePosition.Y
					+ scroll.CanvasPosition.Y
					- scroll.AbsolutePosition.Y
				if previous == nil or math.abs(current - previous) > 0.01 then
					Hierarchy.layout(rig)
				end
			end)
			connect(session, header:GetPropertyChangedSignal("AbsoluteSize"), function()
				if not session.virtual then
					Hierarchy.layout(rig)
				end
			end)
			connect(session, header:GetPropertyChangedSignal("Visible"), function()
				Hierarchy.layout(rig)
			end)
		end

		local documentY = header.AbsolutePosition.Y
			+ scroll.CanvasPosition.Y
			- scroll.AbsolutePosition.Y
		session.headerDocuments = session.headerDocuments or {}
		session.headerDocuments[header] = documentY
		local y = header.AbsolutePosition.Y
			+ scroll.CanvasPosition.Y
			- host.AbsolutePosition.Y
			- keys.CanvasPosition.Y
		local height = header.AbsoluteSize.Y
		if row.AutomaticSize ~= Enum.AutomaticSize.None then
			row.AutomaticSize = Enum.AutomaticSize.None
		end

		if row.AnchorPoint ~= Vector2.zero then
			row.AnchorPoint = Vector2.zero
		end

		local position = UDim2.fromOffset(0, math.round(y / scale))
		local size = UDim2.new(1, 0, 0, height > 0 and math.round(height / scale) or 19)
		if row.Position ~= position then
			row.Position = position
		end

		if row.Size ~= size then
			row.Size = size
		end

		if row.Visible then
			maximum = math.max(maximum, y + height)
			table.insert(rows, {
				row = row,
				header = header,
				line = row:FindFirstChild("Line"),
				first = position.Y.Offset,
				headerFirst = y / scale,
				last = (y + height) / scale,
				height = height / scale,
				rowHeight = size.Y.Offset,
			})
		end
	end

	for _, item in rig._organizationItems do
		place(item)
		for _, channel in item.transformChannelItems or {} do
			place(channel)
		end
	end

	table.sort(rows, function(a, b)
		return a.first < b.first
	end)
	local last = -math.huge
	for _, row in rows do
		last = math.max(last, row.last)
		row.maxEnd = last
	end

	session.rows = rows
	session.reference = rows[1] and rows[1].header
	local size = UDim2.new(1, 0, 0, math.max(0, maximum) / scale)
	if host.Size ~= size then
		host.Size = size
	end

	session.hostOffset = host.AbsolutePosition.Y - keys.AbsolutePosition.Y + keys.CanvasPosition.Y
	session.viewportTop = keys.AbsolutePosition.Y
	session.viewportHeight = keys.AbsoluteWindowSize.Y
	session.paintStamp = nil
end

local function refreshViewport(session)
	local rig, host = session.rig, session.host
	local scroll, keys = rig.refs.RigListScroll, rig.refs.KeysRoot

	local separation = scroll.AbsolutePosition.Y - keys.AbsolutePosition.Y
	if session.paneSeparation ~= nil and math.abs(separation - session.paneSeparation) > 0.01 then
		session.layoutDirty = true
	end

	session.paneSeparation = separation
	session.viewportTop = keys.AbsolutePosition.Y
	session.viewportHeight = keys.AbsoluteWindowSize.Y
	session.viewportDirty = false
end

local function stepLayout(session)
	if session.dead then
		return
	end

	local rig, host = session.rig, session.host
	local scroll, keys = rig.refs.RigListScroll, rig.refs.KeysRoot
	if
		rig._hierarchyOrganization ~= session
		or not host.Parent
		or not scroll.Parent
		or not keys.Parent
		or not visible(scroll)
	then
		return
	end

	if Motion.isTranslating(scroll) then
		session.viewportDirty = true
		return
	end

	if session.viewportDirty then
		refreshViewport(session)
	end

	local scale = scaleFor(host)
	local origin = (host.AbsolutePosition.Y + keys.CanvasPosition.Y - scroll.AbsolutePosition.Y)
		/ scale
	if session.layoutOrigin == nil or math.abs(session.layoutOrigin - origin) > 0.01 then
		session.layoutOrigin = origin
		session.layoutDirty = true
	end

	if session.layoutScale ~= scale then
		session.layoutDirty = true
	end

	if session.layoutDirty then
		session.layoutDirty = false
		session.layoutScale = scale
		updateLayout(session)
		rig.refs.Timeline:InvalidateKeyframeViewportLayout()
	end

	mountVirtual(session)

	local stamp = session.paintStamp

	local top = session.viewportTop or 0
	local hostY = host.AbsolutePosition.Y
	local height = session.viewportHeight or 0
	if
		stamp
		and stamp.hostY == hostY
		and stamp.top == top
		and stamp.height == height
		and stamp.scale == scale
	then
		return
	end

	session.paintStamp = { hostY = hostY, top = top, height = height, scale = scale }
	local first = (top - hostY) / scale - 24
	local last = first + height / scale + 48
	local rows = session.rows or {}
	local low, high = 1, #rows
	while low <= high do
		local mid = (low + high) // 2
		if rows[mid].maxEnd < first then
			low = mid + 1
		else
			high = mid - 1
		end
	end

	for i = low, #rows do
		local row = rows[i]
		if row.first > last then
			break
		end

		snapLine(row, scale, hostY)
	end
end

function Hierarchy.layout(rig)
	local session = rig._hierarchyOrganization
	if session and not session.dead then
		enableVirtual(session)
		session.layoutDirty = true
	end
end

local function finishDrag(session, commit)
	local drag = session.drag
	session.pending = nil
	if not drag then
		return
	end

	session.drag = nil
	if session.render then
		session.render:Disconnect()
		session.render = nil
	end

	if drag.tooltip then
		drag.tooltip:endDrag(session)
	end

	if drag.indicator then
		drag.indicator:Destroy()
	end

	session.rig._dragHiddenItems = nil
	session.rig._suppressHierarchyClickUntil = os.clock() + 0.15
	session.rig:RefreshSelectionFilter()
	if commit and drag.valid then
		Organization.move(drag.keys, drag.parent, drag.index)
	end
end

local function overlayParent(scroll)
	return scroll:FindFirstAncestorOfClass("ScreenGui") or scroll.Parent
end

local function overlayOrigin(parent)
	return parent:IsA("GuiObject") and parent.AbsolutePosition or Vector2.zero
end

local function paintDrop(session, point)
	local drag, rig = session.drag, session.rig
	if not drag then
		return
	end

	local origin = overlayOrigin(drag.indicator.Parent)
	local scale = scaleFor(drag.indicator.Parent)
	if drag.tooltip then
		drag.tooltip:moveDrag(point)
	end

	drag.valid = false
	drag.indicator.Visible = false
	local scroll = rig.refs.RigListScroll
	if not inside(point, scroll) then
		return
	end

	local target
	for _, item in rig._organizationItems do
		if
			(not session.virtual or item._virtualMounted)
			and item.itemKind ~= "property"
			and item.itemKind ~= "properties"
			and keyFor(item)
			and item.appearDetails.Visible
			and visible(item.uiElement)
			and inside(point, item.appearDetails)
		then
			target = item
			break
		end
	end

	local parent, index
	local y = point.Y
	local indent = 0
	if target then
		local p, size = target.appearDetails.AbsolutePosition, target.appearDetails.AbsoluteSize
		local fraction = (point.Y - p.Y) / math.max(1, size.Y)
		if fraction >= 0.25 and fraction <= 0.75 then
			parent = keyFor(target)
			y, indent = p.Y + size.Y, 14
		else
			parent = Organization.parent(keyFor(target))
			local siblings = Organization.children(parent)
			index = table.find(siblings, keyFor(target)) or #siblings + 1
			if fraction > 0.75 then
				index += 1
			end

			y = fraction > 0.75 and p.Y + size.Y or p.Y
		end
	else
		parent = nil
		y = math.clamp(
			point.Y,
			scroll.AbsolutePosition.Y,
			scroll.AbsolutePosition.Y + scroll.AbsoluteSize.Y
		)
	end

	local ancestor = parent
	while ancestor do
		if drag.keySet[ancestor] then
			return
		end

		ancestor = Organization.parent(ancestor)
	end

	if index then
		local before = 0
		for position, key in Organization.children(parent) do
			if position >= index then
				break
			end

			if drag.keySet[key] then
				before += 1
			end
		end

		index -= before
	end

	drag.parent, drag.index, drag.valid = parent, index, true
	drag.indicator.Position = UDim2.fromOffset(
		(scroll.AbsolutePosition.X - origin.X + indent) / scale,
		(y - origin.Y) / scale
	)
	drag.indicator.Size =
		UDim2.fromOffset(math.max(8, scroll.AbsoluteSize.X - indent) / scale, 2 / scale)
	drag.indicator.Visible = true
end

local function startDrag(session, point)
	local pending, rig = session.pending, session.rig
	if not pending then
		return
	end

	local keys, selected = {}, rig._explicitSelectedKeys or {}
	if not selected[keyFor(pending.item)] then
		selected = { [keyFor(pending.item)] = true }
	end

	local keySet = {}
	for _, item in rig._organizationItems do
		local key = keyFor(item)
		if key and selected[key] then
			local parent, nested = Organization.parent(key), false
			while parent do
				if selected[parent] then
					nested = true
					break
				end

				parent = Organization.parent(parent)
			end

			if not nested then
				table.insert(keys, key)
				keySet[key] = true
			end
		end
	end

	if #keys == 0 then
		return
	end

	local parent = overlayParent(rig.refs.RigListScroll)
	local tooltip = rig.refs.UIHelpers.hoverDialog
	local info = #keys == 1 and pending.item.centerDiv.Title.Text or tostring(#keys) .. " tracks"
	if not tooltip or not tooltip.beginDrag or tooltip:beginDrag(info, session) ~= true then
		tooltip = nil
	end

	local indicator = Instance.new("Frame")
	indicator.Name = "TrackDropIndicator"
	indicator.BackgroundColor3 = Hierarchy.dragColor(pending.item)
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 201
	indicator.Parent = parent
	session.drag = { keys = keys, keySet = keySet, tooltip = tooltip, indicator = indicator }
	rig._dragHiddenItems = {}
	for key in keySet do
		rig._dragHiddenItems[session.byKey[key]] = true
	end

	rig:RefreshSelectionFilter()
	paintDrop(session, point)
	session.render = RunService.RenderStepped:Connect(function(dt)
		if session.dead or not visible(rig.refs.RigListScroll) then
			finishDrag(session, false)
			return
		end

		local mouse = UserInputService:GetMouseLocation()
		local scroll = rig.refs.RigListScroll
		if inside(mouse, scroll) then
			local relative = mouse.Y - scroll.AbsolutePosition.Y
			local edge = 22
			local velocity = relative < edge and -180 * (1 - relative / edge)
				or relative > scroll.AbsoluteSize.Y - edge and 180 * (1 - (scroll.AbsoluteSize.Y - relative) / edge)
				or 0
			if velocity ~= 0 then
				local uiScale = scaleFor(scroll)
				local limit = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
					/ uiScale
				scroll.CanvasPosition = Vector2.new(
					scroll.CanvasPosition.X,
					math.clamp(
						scroll.CanvasPosition.Y + velocity * math.min(dt, 0.05) / uiScale,
						0,
						limit
					)
				)
			end
		end

		paintDrop(session, mouse)
	end)
end

function Hierarchy.pointerDown(rig, item, point)
	local session = rig._hierarchyOrganization
	if not session or session.dead or not keyFor(item) or session.renameBox then
		return false
	end

	session.pending = { item = item, point = point }
	return true
end

function Hierarchy.pointerMove(rig, point)
	local session = rig._hierarchyOrganization
	if not session or not session.pending then
		return false
	end

	if not session.drag and (point - session.pending.point).Magnitude >= 5 then
		startDrag(session, point)
	end

	if session.drag then
		paintDrop(session, point)
	end

	return session.drag ~= nil
end

function Hierarchy.pointerUp(rig, point, cancel)
	local session = rig._hierarchyOrganization
	if not session then
		return
	end

	if session.drag and point then
		paintDrop(session, point)
	end

	finishDrag(session, cancel ~= true)
end

function Hierarchy.click(rig, item)
	if require("Targets").pickTimelineChild(item) then
		return true
	end

	if item.itemKind == "events" or item.itemKind == "subtitles" or item.itemKind == "faces" then
		return
	end

	if (rig._suppressHierarchyClickUntil or 0) > os.clock() then
		return false
	end

	local session = rig._hierarchyOrganization
	if session and (session.renameBox or session.drag) then
		return false
	end

	local key = keyFor(item)
	if key then
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local selected = rig._explicitSelectedKeys or {}
		if ctrl then
			selected[key] = not selected[key] or nil
		elseif shift and session and session.lastKey then
			local first, last
			for index, row in rig._organizationItems do
				if keyFor(row) == session.lastKey then
					first = index
				end

				if row == item then
					last = index
				end
			end

			selected = {}
			if first and last then
				for index = math.min(first, last), math.max(first, last) do
					local row = rig._organizationItems[index]
					if keyFor(row) and visible(row.uiElement) then
						selected[keyFor(row)] = true
					end
				end
			else
				selected[key] = true
			end
		else
			selected = { [key] = true }
		end

		rig._explicitSelectedKeys = selected
		if session then
			local now = os.clock()
			local double = session.lastClickItem == item
				and now - (session.lastClickTime or 0) < 0.32
			session.lastClickItem, session.lastClickTime, session.lastKey = item, now, key
			if double and item.itemKind == "folder" then
				Hierarchy.rename(rig, item)
				return
			end
		end
	end

	item:selectBone()
	rig._lastObservedSelectedBone = rig.refs.Axis and rig.refs.Axis:GetSelectedBone() or nil
	rig:RefreshHierarchySelectionVisuals()
end

function Hierarchy.enabled(rig, incremental)
	for _, item in rig._organizationItems or {} do
		local key = keyFor(item)
			or (
				(item.itemKind == "ikcontrol" or item.itemKind == "mastercontrol")
				and item.linkedRigInstance
			)
		if key then
			local own
			if item.itemKind == "folder" then
				own = Organization.get(key).enabled
			else
				own = Organization.getOwnEnabled(key, true)
			end

			local disabled = own == false
			if not incremental or item.disabled ~= disabled then
				item.disabled = disabled
				item:_repaintDisable()
			end
		end

		local motor = item:fetchMotor()
		if motor then
			local owner = key
			local disabled = owner and not Organization.isEnabled(owner) or false
			local value = disabled and true or nil
			if motor:GetAttribute("EclipseDisabled") ~= value then
				motor:SetAttribute("EclipseDisabled", value)
			end
		end
	end
end

function Hierarchy.setDisabled(rig, item, disabled, propagate)
	local key = keyFor(item)
		or (
			(item.itemKind == "ikcontrol" or item.itemKind == "mastercontrol")
			and item.linkedRigInstance
		)
	if item.itemKind == "folder" then
		Organization.setEnabled(key, not disabled)
		return
	end

	if not key then
		item.disabled = disabled == true
		item:_repaintDisable()
		Hierarchy.enabled(rig)
		item:refreshControlPose()
		return
	end

	local keys = { key }
	if propagate then
		local function visit(node)
			for _, child in node.childItems do
				local childKey = keyFor(child)
					or (
						(child.itemKind == "ikcontrol" or child.itemKind == "mastercontrol")
						and child.linkedRigInstance
					)
				if childKey and child.itemKind ~= "folder" then
					table.insert(keys, childKey)
				end

				visit(child)
			end
		end

		visit(item)
	end

	Organization.setOwnEnabled(keys, not disabled)
end

function Hierarchy.destroy(rig)
	local session = rig._hierarchyOrganization
	if not session then
		return
	end

	session.dead = true
	finishDrag(session, false)
	if session.renameBox then
		session.renameBox:Destroy()
		session.renameBox = nil
	end

	if session.unsubscribe then
		session.unsubscribe()
	end

	for _, connection in session.connections do
		connection:Disconnect()
	end

	restoreVirtual(session)
	if session.host then
		session.host:Destroy()
	end

	rig._hierarchyOrganization = nil
	rig._organizationReady = false
end

function Hierarchy.build(rig, baseItem, saved)
	local session =
		{ rig = rig, connections = {}, byKey = {}, layoutBound = {}, viewportDirty = true }
	rig._hierarchyOrganization = session
	local natural, pinned = {}, {}
	session.authoredChildren = {}
	local masters, duplicates = {}, {}
	for _, master in rig._masterItems do
		masters[master.linkedRigInstance] = master
	end

	local function capture(item, parentKey, order)
		session.authoredChildren[item] = table.clone(item.childItems or {})
		if not item.trackIsMaster and item.itemKind == "bone" and masters[item.linkedRigInstance] then
			item.organizationKey = item:fetchMotor()
		end
		local key = keyFor(item)
		if key and session.byKey[key] then
			duplicates[item] = session.byKey[key]
		elseif key then
			session.byKey[key] = item
			table.insert(natural, {
				key = key,
				parent = parentKey,
				order = order,
				rig = (item.grandpa or item).linkedRigInstance,
				enabled = not item.disabled,
			})
		else
			pinned[item.parentItem] = pinned[item.parentItem] or {}
			table.insert(pinned[item.parentItem], item)
			if item.itemKind == "ikcontrol" or item.itemKind == "mastercontrol" then
				table.insert(natural, {
					key = item.linkedRigInstance,
					parent = parentKey,
					order = order,
					rig = item.grandpa.linkedRigInstance,
					enabled = not item.disabled,
					hidden = true,
				})
			end
		end

		for index, child in item.childItems do
			capture(child, key or parentKey, index)
		end
	end

	if rig._originItem then
		capture(rig._originItem, nil, 0)
	end

	for index, master in rig._masterItems do
		capture(master, nil, index)
	end
	for duplicate, canonical in duplicates do
		for _, child in pinned[duplicate] or {} do
			pinned[canonical] = pinned[canonical] or {}
			table.insert(pinned[canonical], child)
		end
		pinned[duplicate] = nil
	end

	local originalNatural = {}
	for _, entry in natural do
		table.insert(originalNatural, table.clone(entry))
	end

	local entries = {}
	local children

	local function updateDynamicParents()
		natural = {}
		entries = {}
		for _, original in originalNatural do
			local entry = table.clone(original)
			table.insert(natural, entry)
			entries[entry.key] = entry
		end

		local Targets = require("Targets")
		local Target = require("Target")

		for _, entry in natural do
			local item = session.byKey[entry.key]
			local motor = item and Targets.trackMotor(item)
			if motor and (CameraRig.isTransform(motor) or Target.isAttachment(motor)) then
				entry.parent = CameraRig.owner(motor)
				entry.dynamic = true
				continue
			end

			local link = motor
				and not CameraRig.isTransform(motor)
				and Target.childAt(motor, rig.refs.Timeline:GetState().CurrentTime)
			local parent = link and Target.resolve(link)
			if parent and entries[parent] and parent ~= entry.key then
				local cursor = parent
				local seen = { [entry.key] = true }
				local cycle = false
				while cursor do
					if seen[cursor] then
						cycle = true
						break
					end

					seen[cursor] = true
					cursor = entries[cursor] and entries[cursor].parent
				end

				if not cycle then
					entry.parent = parent
					entry.dynamic = true
				end
			end
		end
	end

	updateDynamicParents()
	local Targets = require("Targets")

	local folded = {}
	for _, master in rig._masterItems do
		local mesh = master.linkedRigInstance
		local part = typeof(mesh) == "Instance" and mesh:IsA("DataModelMesh") and mesh.Parent
		local owner = part and part:IsA("BasePart") and session.byKey[part]
		if
			owner
			and owner.trackIsMaster
			and part:FindFirstChildWhichIsA("DataModelMesh") == mesh
		then
			local destination, source
			for _, child in owner.childItems do
				if child.itemKind == "properties" then
					destination = child
				end
			end

			for _, child in master.childItems do
				if child.itemKind == "properties" then
					source = child
				end
			end

			if
				destination
				and source
				and Organization.getOwnEnabled(mesh, true) ~= false
				and Organization.getOwnEnabled(keyFor(source), true) ~= false
				and not Organization.isRemoved(mesh)
				and not Organization.isRemoved(keyFor(source))
			then
				local entry = entries[mesh]
				entry.parent = keyFor(destination)
				entry.dynamic = true
				local group = entries[keyFor(source)]
				group.parent = mesh
				group.dynamic = true
				folded[mesh] = true
				folded[keyFor(source)] = true
				pinned[destination] = pinned[destination] or {}
				for _, child in pinned[master] or {} do
					if child.itemKind == "events" then
						child.centerDiv.Title.Text = "MESH EVENTS"
					end

					table.insert(pinned[destination], child)
				end

				pinned[master] = nil
			end
		end
	end

	Organization.sync(natural)
	children = Organization.childIndex()
	for key, item in session.byKey do
		if Organization.isRemoved(key) then
			item.uiElement.Visible = false
			item.trackElement.Visible = false
			local motor = item:fetchMotor()
			if motor then
				motor:SetAttribute("EclipseDisabled", true)
			end
		end
	end

	local host = Instance.new("Frame")
	host.Name = "OrganizedTracks"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.new(1, 0, 0, 0)
	host.Parent = rig.refs.KeysRoot
	session.host = host
	for _, item in session.byKey do
		item.childItems = {}
	end

	local roots, ordered = {}, {}
	local displayOrders = {}
	local parking = Instance.new("Frame")
	parking.Name = "MeshPropertyOwners"
	parking.Visible = false
	parking.Parent = host
	for duplicate in duplicates do
		duplicate.uiElement.Parent = parking
		duplicate.trackElement.Parent = parking
		duplicate.childItems = {}
	end
	local maximumDepth = 0

	local function attach(key, parent, index, depth)
		local item = session.byKey[key]
		if not item and Organization.isFolder(key) then
			local data = Organization.get(key)
			local row = rig.refs.Timeline:GetTrackTemplate():Clone()
			row.Name = "Folder_Track"
			for _, child in row:GetChildren() do
				if child:IsA("GuiObject") then
					child.Visible = false
				end
			end

			item = baseItem.initialize(
				rig.refs.RigItemTemplate:Clone(),
				data.name,
				nil,
				row,
				false,
				key,
				"folder"
			)
			item.openedState = not saved[key] or saved[key].open ~= false
			session.byKey[key] = item
		end

		if not item then
			return
		end

		if folded[key] then
			if session.virtual and session.virtual.saved[item] then
				session.virtual.saved[item].parent = parking
			else
				item.uiElement.Parent = parking
			end

			item.trackElement.Parent = parking
			for _, childKey in (children[key] or {}) do
				attach(childKey, parent, index, depth)
			end

			return
		end

		local displayOwner = parent or roots
		displayOrders[displayOwner] = (displayOrders[displayOwner] or 0) + 1
		index = displayOrders[displayOwner]
		item.parentItem = parent
		if entries[key] and entries[key].dynamic and parent then
			parent.openedState = true
		end

		Targets.bindObjectRow(item)
		local uiParent = parent and parent.childContainer.ChildrenContents or rig.refs.RigListScroll
		if session.virtual and session.virtual.saved[item] then
			session.virtual.saved[item].parent = uiParent
		else
			item.uiElement.Parent = uiParent
		end

		item.uiElement.LayoutOrder = index
		item.trackElement.Parent = host
		if item.trackIsMaster then
			item.trackElement.TrackContainers.Visible = false
		end

		for _, channel in item.transformChannelItems or {} do
			channel.trackElement.Parent = host
		end

		if parent then
			table.insert(parent.childItems, item)
		else
			table.insert(roots, item)
		end

		table.insert(ordered, item)
		maximumDepth = math.max(maximumDepth, depth)
		local pins = pinned[item] or {}
		table.sort(pins, function(a, b)
			local function rank(row)
				return row.itemKind == "mastercontrol" and -90
					or row.itemKind == "events" and -100
					or row.itemKind == "faces" and -99
					or row.itemKind == "subtitles" and -98 + (row.subtitleIndex or 0) * 0.001
					or 0
			end

			return rank(a) < rank(b)
		end)
		for pinIndex, child in pins do
			child.parentItem = item
			if session.virtual and session.virtual.saved[child] then
				session.virtual.saved[child].parent = item.childContainer.ChildrenContents
			else
				child.uiElement.Parent = item.childContainer.ChildrenContents
			end

			child.uiElement.LayoutOrder = child.itemKind == "mastercontrol" and -90
				or child.itemKind == "events" and -100
				or child.itemKind == "faces" and -99
				or -50 + pinIndex
			child.trackElement.Parent = host
			for _, channel in child.transformChannelItems or {} do
				channel.trackElement.Parent = host
			end

			table.insert(item.childItems, child)
			table.insert(ordered, child)
		end

		for childIndex, childKey in (children[key] or {}) do
			attach(childKey, item, childIndex, depth + 1)
		end

		item:refreshMoreButtonVisibility()
	end

	for _, item in rig._subtitleItems or {} do
		item.trackElement.Parent = host
		table.insert(roots, item)
		table.insert(ordered, item)
	end

	for index, key in (children[false] or {}) do
		attach(key, nil, index, 0)
	end

	rig._rootItems, rig._organizationItems = roots, ordered
	rig._orderedItems = {}
	for _, item in ordered do
		if not item.trackIsMaster then
			table.insert(rig._orderedItems, item)
		end
	end

	rig._organizationReady = true
	enableVirtual(session)
	Hierarchy.enabled(rig)
	session.refreshDynamic = function()
		if session.dead or session.drag or session.renameBox then
			return false
		end

		updateDynamicParents()

		for key in folded do
			local old = Organization.parent(key)
			if entries[key] then
				entries[key].parent = old
				entries[key].dynamic = true
			end
		end

		Organization.sync(natural)
		children = Organization.childIndex()
		for _, item in session.byKey do
			item.childItems = {}
		end

		roots = {}
		ordered = {}
		displayOrders = {}
		maximumDepth = 0
		for _, item in rig._subtitleItems or {} do
			item.trackElement.Parent = host
			table.insert(roots, item)
			table.insert(ordered, item)
		end

		for index, key in (children[false] or {}) do
			attach(key, nil, index, 0)
		end

		rig._rootItems, rig._organizationItems = roots, ordered
		rig._orderedItems = {}
		for _, item in ordered do
			if not item.trackIsMaster then
				table.insert(rig._orderedItems, item)
			end
		end

		rig._organizationReady = true
		enableVirtual(session)
		Hierarchy.enabled(rig)
		rig:RefreshSelectionFilter()
		rig:UpdateRigListCanvasWidth(maximumDepth)
		Hierarchy.layout(rig)
		return true
	end

	for _, item in ordered do
		if keyFor(item) and item.itemKind ~= "property" and item.itemKind ~= "properties" then
			trash(session, item)
			connect(session, item.centerDiv.InputBegan, function(input)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					or UserInputService:GetFocusedTextBox()
				then
					return
				end

				if session.renameBox then
					return
				end

				local point = UserInputService:GetMouseLocation()
				local image = item.centerDiv.ImgContainer.Img
				if image.Active and inside(point, image) then
					return
				end

				Hierarchy.pointerDown(rig, item, point)
			end)
		end
	end

	connect(session, UserInputService.InputChanged, function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			or not session.pending
			or session.drag
		then
			return
		end

		Hierarchy.pointerMove(rig, UserInputService:GetMouseLocation())
	end)
	connect(session, UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Hierarchy.pointerUp(rig, UserInputService:GetMouseLocation(), false)
		end
	end)
	connect(session, UserInputService.InputBegan, function(input)
		if Shortcuts.matches("Cancel", input) then
			finishDrag(session, false)
		end
	end)
	connect(session, UserInputService.WindowFocusReleased, function()
		finishDrag(session, false)
	end)
	local ancestor = rig.refs.RigListScroll
	while ancestor do
		if ancestor:IsA("GuiObject") or ancestor:IsA("ScreenGui") then
			local property = ancestor:IsA("ScreenGui") and "Enabled" or "Visible"
			connect(session, ancestor:GetPropertyChangedSignal(property), function()
				if not visible(rig.refs.RigListScroll) then
					finishDrag(session, false)
				end

				Hierarchy.layout(rig)
			end)
		end

		ancestor = ancestor.Parent
	end

	connect(session, rig.refs.RigListScroll.Destroying, function()
		Hierarchy.destroy(rig)
	end)
	connect(session, rig.refs.RigListScroll:GetPropertyChangedSignal("AbsoluteSize"), function()
		if session.virtual then
			session.viewportDirty = true
		else
			Hierarchy.layout(rig)
		end
	end)
	connect(session, rig.refs.RigListScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"), function()
		Hierarchy.layout(rig)
	end
)
	connect(session, rig.refs.RigListScroll:GetPropertyChangedSignal("AbsolutePosition"), function()
		session.viewportDirty = true
	end)
	connect(session, rig.refs.KeysRoot:GetPropertyChangedSignal("AbsoluteSize"), function()
		if session.virtual then
			session.viewportDirty = true
		else
			Hierarchy.layout(rig)
		end
	end)
	connect(session, rig.refs.KeysRoot:GetPropertyChangedSignal("AbsoluteWindowSize"), function()
		if session.virtual then
			session.viewportDirty = true
		else
			Hierarchy.layout(rig)
		end
	end)
	connect(session, rig.refs.KeysRoot:GetPropertyChangedSignal("AbsolutePosition"), function()
		session.viewportDirty = true
	end)

	session.unsubscribe = Organization.subscribe(function(kind)
		if session.dead or rig._rebuilding or rig._batchHold then
			return
		end

		if kind == "reset" then
			return
		end

		if kind == "widgets" then
			return
		end

		if kind == "enabled" or kind == "ownEnabled" then
			Hierarchy.enabled(rig)
			for _, master in rig._masterItems do
				rig.refs.Timeline:ApplyPoseAtTime(
					master.linkedRigInstance,
					rig.refs.Timeline:GetState().CurrentTime
				)
			end
		else
			rig:BuildRigHierarchy(rig._primaryRigInstance)
		end
	end)
	Hierarchy.layout(rig)
	connect(session, RunService.RenderStepped, function()
		if not session.dead then
			stepLayout(session)
		end
	end)
	return maximumDepth
end

function Hierarchy.refreshDynamic(rig)
	local session = rig._hierarchyOrganization
	return session and session.refreshDynamic and session.refreshDynamic() or false
end

function Hierarchy.authoredChildren(rig, item)
	local session = rig and rig._hierarchyOrganization
	return session and session.authoredChildren and session.authoredChildren[item]
		or item.childItems
		or {}
end

Hierarchy.key = keyFor
Hierarchy.finishDrag = function(rig, commit)
	local session = rig._hierarchyOrganization
	if session then
		finishDrag(session, commit)
	end
end

return Hierarchy
