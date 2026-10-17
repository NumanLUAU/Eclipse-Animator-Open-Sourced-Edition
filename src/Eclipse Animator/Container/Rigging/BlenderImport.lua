--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local DockHost = require("DockHost")

local Chrome = require("Chrome")
local Surface = require("Surface")
local SizeableWindows = require("SizeableWindows")
local MIN_SIZE = Vector2.new(440, 510)
local FX = require("WindowFX")
local Theme = require("Theme")
local Bridge = require("BlenderBridge")
local Window = {}
local layers, connections, hosts = {}, {}, {}
local refs, window, unsubscribe, popup, popupButton
local rigId, objectName

local function release(frame)
	if window ~= frame then
		return
	end

	window, popup, popupButton = nil, nil, nil
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
end

local function clear()
	release(window)
	for _, dispose in layers do
		dispose()
	end
end

function Window.isOpen()
	return window ~= nil
end

function Window.close(immediate)
	local previous = window
	release(previous)
	if immediate == true or (previous and hosts[previous] and hosts[previous].docked) then
		clear()
	elseif previous then
		FX.shrink(previous, layers[previous])
	end

	if refs and refs.ScreenGui.Parent and refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end
end

function Window.isDocked()
	return window ~= nil and hosts[window] ~= nil and hosts[window].docked
end

function Window.presentationWidget()
	return window and hosts[window] and hosts[window].widget
end

function Window.setDocked(enabled)
	local frame = window
	local host = frame and hosts[frame]
	if not host or host.busy or host.docked == enabled then
		return false
	end

	host.busy = true
	if enabled and not host.widget then
		local ok, widget = pcall(function()
			return DockHost.acquire(
				refs.Plugin,
				"EclipseAnimatorBlenderImport",
				DockWidgetPluginGuiInfo.new(
					Enum.InitialDockState.Right,
					true,
					true,
					500,
					550,
					MIN_SIZE.X,
					MIN_SIZE.Y
				)
			)
		end)
		if hosts[frame] ~= host then
			if ok then
				DockHost.release(widget)
			end

			return false
		end

		if not ok then
			host.busy = false
			return false
		end

		host.widget = widget
		widget.Title, widget.ZIndexBehavior = "Eclipse Blender Import", Enum.ZIndexBehavior.Sibling
		host.widgetConnection = widget:GetPropertyChangedSignal("Enabled"):Connect(function()
			if hosts[frame] == host and host.docked and not host.busy and not widget.Enabled then
				Window.close(true)
			end
		end)
	end

	if
		enabled
		and not DockHost.show(host.widget, function()
			return hosts[frame] == host and window == frame
		end)
	then
		host.busy = false
		if hosts[frame] == host then
			host.widget.Enabled = false
		end

		return false
	end

	FX.clear(frame)
	local scale = frame:FindFirstChild("EclipseWindowScale")
	if scale then
		scale.Scale = 1
	end

	host.docked = enabled
	frame:SetAttribute("EclipseDocked", enabled)
	if enabled then
		host.position = frame.Position
		host.size = frame.Size
		frame.Parent, frame.Position = host.widget, UDim2.fromOffset(0, 0)
		frame.AnchorPoint, frame.Size = Vector2.zero, UDim2.fromScale(1, 1)
		host.widget.Enabled = true
	else
		if host.scale then
			host.scale:Destroy()
			host.scale = nil
		end

		frame.Parent, frame.Position = host.layer, host.position
		frame.AnchorPoint, frame.Size = Vector2.new(0.5, 0.5), host.size
		host.widget.Enabled = false
	end

	host.label.Text = enabled and "UNDOCK" or "DOCK"
	if host.layout then
		host.layout()
	end

	host.busy = false
	return true
end

function Window.resize(size)
	local frame = window
	local host = frame and hosts[frame]
	if not host or host.docked or host.busy then
		return false
	end

	local nextSize = Vector2.new(math.max(MIN_SIZE.X, size.X), math.max(MIN_SIZE.Y, size.Y))
	frame.Size = UDim2.fromOffset(nextSize.X, nextSize.Y)
	if host.layout then
		host.layout()
	end

	return true
end

function Window.destroy()
	clear()
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	refs = nil
end

function Window.open()
	if not refs or not refs.ScreenGui.Parent or not refs.ScreenGui.Enabled then
		return nil
	end

	if window then
		return window
	end

	clear()
	local frame = Instance.new("Frame")

	frame.Name, frame.Size = "BlenderImport", UDim2.fromOffset(500, 550)
	frame.Position, frame.AnchorPoint = UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	frame.ZIndex, frame.Active, frame.BorderSizePixel = 210, true, 0
	local minimum = Instance.new("UISizeConstraint")
	minimum.Name, minimum.MinSize, minimum.Parent = "MinimumSize", MIN_SIZE, frame
	local layer = Instance.new("ScreenGui")

	layer.Name, layer.ResetOnSpawn = "EclipseBlenderImport", false
	layer.IgnoreGuiInset, layer.ScreenInsets =
		refs.ScreenGui.IgnoreGuiInset, refs.ScreenGui.ScreenInsets
	layer.DisplayOrder, layer.ZIndexBehavior =
		refs.ScreenGui.DisplayOrder + 1, Enum.ZIndexBehavior.Sibling
	layer.Enabled = refs.ScreenGui.Enabled
	layer:SetAttribute("EclipseWindowIsolated", true)
	layer.Parent = refs.ScreenGui.Parent
	local sourceScale = refs.ScreenGui:FindFirstChildOfClass("UIScale")
	local scaleConnection
	if sourceScale then
		local factor = sourceScale:Clone()
		factor.Parent = layer
		scaleConnection = sourceScale:GetPropertyChangedSignal("Scale"):Connect(function()
			factor.Scale = sourceScale.Scale
		end)
	end

	frame.Parent = layer
	local host = { layer = layer, docked = false, busy = false }
	hosts[frame] = host
	local disposed = false

	local function detach()
		if disposed then
			return false
		end

		disposed = true
		layers[frame], hosts[frame] = nil, nil
		FX.clear(frame)
		if scaleConnection then
			scaleConnection:Disconnect()
		end

		if host.widgetConnection then
			host.widgetConnection:Disconnect()
		end

		if host.widget then
			DockHost.release(host.widget)
			host.widget = nil
		end

		release(frame)
		return true
	end

	local function dispose()
		if not detach() then
			return
		end

		layer.Enabled = false
		layer:Destroy()
	end

	layers[frame] = dispose
	layer.Destroying:Once(function()
		if detach() then
			frame:Destroy()
		end
	end)
	frame.Destroying:Once(dispose)
	window = frame
	Surface.fill(frame)
	local stroke = Instance.new("UIStroke")

	stroke:SetAttribute("ThemeStrk", "Strk")
	stroke.Parent = frame
	local header, _, drag = Chrome.header(frame, "BLENDER IMPORT", 211, 120)
	Chrome.close(header, nil, 217).Activated:Connect(Window.close)
	local dock, dockText = Chrome.menuButton(
		header,
		"Dock",
		"DOCK",
		UDim2.new(1, -110, 0, 2),
		UDim2.fromOffset(68, 23),
		217
	)
	host.label = dockText
	dock.Activated:Connect(function()
		Window.setDocked(not host.docked)
	end)

	local function label(parent, name, text, position, size)
		local item = Instance.new("TextLabel")

		item.Name, item.Text, item.Position, item.Size = name, text, position, size
		item.BackgroundTransparency, item.ZIndex = 1, parent.ZIndex + 2
		item.FontFace, item.TextSize, item.TextXAlignment =
			Chrome.FONT, 13, Enum.TextXAlignment.Left
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item:SetAttribute("ThemeTxt", "Txt")
		item.Parent = parent
		return item
	end

	local function field(parent, name, value, position, size)
		local fill = Instance.new("Frame")

		fill.Name, fill.Position, fill.Size = name .. "Field", position, size
		fill.BorderSizePixel, fill.ZIndex = 0, parent.ZIndex + 2
		fill:SetAttribute("ThemeBg", "TopBtn")
		fill.Parent = parent
		local line = Instance.new("UIStroke")

		line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		line:SetAttribute("ThemeStrk", "Strk")
		line.Parent = fill
		local input = Instance.new("TextBox")

		input.Name, input.Text, input.ClearTextOnFocus = name, value, false
		input.Position, input.Size = UDim2.fromOffset(5, 0), UDim2.new(1, -10, 1, 0)
		input.BackgroundTransparency, input.ZIndex = 1, fill.ZIndex + 1
		input.FontFace, input.TextSize, input.TextXAlignment =
			Chrome.FONT, 13, Enum.TextXAlignment.Left
		input.TextTruncate = Enum.TextTruncate.AtEnd
		input:SetAttribute("ThemeTxt", "Txt")
		input.Parent = fill
		return input
	end

	local statusPanel = Instance.new("Frame")
	statusPanel.Name, statusPanel.BorderSizePixel, statusPanel.ZIndex = "ConnectionStatus", 0, 212
	statusPanel:SetAttribute("ThemeBg", "Top")
	statusPanel.Parent = frame
	Surface.fill(statusPanel, "Top")
	local statusStroke = Instance.new("UIStroke")
	statusStroke:SetAttribute("ThemeStrk", "Strk")
	statusStroke.Parent = statusPanel
	local statusTitle = label(
		statusPanel,
		"Title",
		"CONNECTION",
		UDim2.fromOffset(10, 5),
		UDim2.new(1, -120, 0, 24)
	)
	local log = Instance.new("ScrollingFrame")
	log.Name, log.BackgroundTransparency, log.BorderSizePixel, log.ScrollBarThickness =
		"Log", 1, 0, 3
	log.Position, log.Size = UDim2.fromOffset(10, 28), UDim2.new(1, -20, 1, -34)
	log.AutomaticCanvasSize, log.CanvasSize, log.ScrollingDirection =
		Enum.AutomaticSize.Y, UDim2.new(), Enum.ScrollingDirection.Y
	log.ZIndex, log.Parent = 213, statusPanel
	local status = Instance.new("TextBox")
	status.Name, status.Text, status.BackgroundTransparency = "Status", "", 1
	status.Size, status.ZIndex, status.FontFace =
		UDim2.new(1, -6, 0, 0), log.ZIndex + 1, Chrome.FONT
	status.TextXAlignment, status.ClearTextOnFocus, status.TextEditable =
		Enum.TextXAlignment.Left, false, false
	status:SetAttribute("ThemeTxt", "Txt")
	status.Parent = log
	status.TextWrapped, status.TextTruncate, status.TextSize = true, Enum.TextTruncate.None, 12
	status.AutomaticSize, status.TextYAlignment = Enum.AutomaticSize.Y, Enum.TextYAlignment.Top
	local connect, connectText = Chrome.menuButton(
		statusPanel,
		"Connect",
		"CONNECT",
		UDim2.new(1, -108, 0, 6),
		UDim2.fromOffset(98, 24),
		215
	)
	local export =
		Chrome.menuButton(frame, "ExportRig", "EXPORT RIG", UDim2.new(), UDim2.new(), 213)
	local sync = Chrome.menuButton(frame, "SyncBones", "SYNC BONES", UDim2.new(), UDim2.new(), 213)

	local centered, includeWelds, page = true, true, "pairing"
	local manual = false
	local tabBar = Instance.new("Frame")
	tabBar.Name, tabBar.BorderSizePixel, tabBar.ZIndex = "TabBar", 0, 213
	tabBar:SetAttribute("ThemeBg", "Top")
	tabBar.Parent = frame
	tabBar.BackgroundTransparency = 0.3
	local tabOutline = Instance.new("UIStroke")
	tabOutline.Transparency = 0.35
	tabOutline:SetAttribute("ThemeStrk", "Strk")
	tabOutline.Parent = tabBar
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 5), tabBar

	local function flatButton(parent, name, title)
		local button = Instance.new("TextButton")
		button.Name, button.Text, button.AutoButtonColor = name, "", false
		button.BackgroundTransparency, button.BorderSizePixel, button.ZIndex =
			1, 0, parent.ZIndex + 1
		button:SetAttribute("ThemeBg", "TopBtn")
		button:SetAttribute("ThemeBgTransparency", 1)
		button.Parent = parent
		local text = label(button, "TextLabel", title, UDim2.new(), UDim2.fromScale(1, 1))
		text.TextXAlignment, text.TextSize = Enum.TextXAlignment.Center, 12
		local round = Instance.new("UICorner")
		round.CornerRadius, round.Parent = UDim.new(0, 3), button
		return button, text
	end

	local function chevron(button)
		local icon = Instance.new("Frame")
		icon.Name, icon.BackgroundTransparency = "DropdownArrow", 1
		icon.Position, icon.Size = UDim2.new(1, -24, 0.5, -6), UDim2.fromOffset(12, 12)
		icon.ZIndex, icon.Parent = button.ZIndex + 3, button
		for index, rotation in { 45, -45 } do
			local line = Instance.new("Frame")
			line.Name, line.BorderSizePixel = "Stroke" .. index, 0
			line.AnchorPoint, line.Position =
				Vector2.new(0.5, 0.5), UDim2.fromOffset(index == 1 and 4 or 8, 6)
			line.Size, line.Rotation, line.ZIndex = UDim2.fromOffset(7, 2), rotation, icon.ZIndex
			line:SetAttribute("ThemeBg", "Txt")
			line.Parent = icon
		end

		return icon
	end

	local function checkbox(name, title)
		local button, text = flatButton(frame, name, title)
		text.Position, text.Size, text.TextXAlignment =
			UDim2.fromOffset(26, 0), UDim2.new(1, -26, 1, 0), Enum.TextXAlignment.Left
		local box = Instance.new("Frame")
		box.Name, box.BorderSizePixel, box.BackgroundTransparency = "Box", 0, 0.25
		box.Position, box.Size, box.ZIndex =
			UDim2.new(0, 2, 0.5, -8), UDim2.fromOffset(16, 16), button.ZIndex + 1
		box:SetAttribute("ThemeBg", "TopBtn")
		box.Parent = button
		local outline = Instance.new("UIStroke")
		outline:SetAttribute("ThemeStrk", "Strk")
		outline.Parent = box
		local fill = Instance.new("Frame")
		fill.Name, fill.BorderSizePixel, fill.ZIndex = "Fill", 0, box.ZIndex + 1
		fill.AnchorPoint, fill.Position, fill.Size =
			Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(8, 8)
		fill:SetAttribute("ThemeBg", "Txt")
		fill.Parent = box
		for _, item in { box, fill } do
			local round = Instance.new("UICorner")
			round.CornerRadius, round.Parent = UDim.new(0, 2), item
		end

		return button, text, fill
	end

	local center, centerText, centerMark = checkbox("CenterOrigin", "Center origin")
	local welds, weldsText, weldsMark = checkbox("ExportWelds", "Include welds")
	local rigToolsHeading = label(frame, "RigToolsHeading", "RIG", UDim2.new(), UDim2.new())
	local accessoryHeading =
		label(frame, "AccessoryHeading", "WEAPON / ACCESSORY", UDim2.new(), UDim2.new())
	rigToolsHeading.TextSize, accessoryHeading.TextSize = 11, 11
	local toolsDivider = Instance.new("Frame")
	toolsDivider.Name, toolsDivider.BorderSizePixel, toolsDivider.ZIndex = "ToolsDivider", 0, 213
	toolsDivider.BackgroundTransparency = 0.35
	toolsDivider:SetAttribute("ThemeBg", "Strk")
	toolsDivider.Parent = frame
	local pairingTab = flatButton(tabBar, "PairingTab", "Pairing")
	local toolsTab = flatButton(tabBar, "ToolsTab", "Rig Tools")
	local manualButton, manualText = flatButton(frame, "ManualPairing", "Manual pairing & scale")
	manualText.TextXAlignment, manualText.Position, manualText.Size =
		Enum.TextXAlignment.Left, UDim2.fromOffset(6, 0), UDim2.new(1, -34, 1, 0)
	chevron(manualButton)
	local pairingSummary = label(frame, "PairingSummary", "", UDim2.new(), UDim2.new())
	pairingSummary.TextWrapped, pairingSummary.TextTruncate = true, Enum.TextTruncate.AtEnd
	local pairingHint = label(
		frame,
		"PairingHint",
		"Auto pair finds the matching Blender object.\nFor a different object or custom bone names, open Manual pairing.",
		UDim2.new(),
		UDim2.new()
	)
	pairingHint.TextSize, pairingHint.TextWrapped, pairingHint.TextTruncate, pairingHint.TextTransparency =
		12, true, Enum.TextTruncate.None, 0.25
	local rigCaption = label(frame, "RigCaption", "ECLIPSE RIG", UDim2.new(), UDim2.new())
	local objectCaption = label(frame, "ObjectCaption", "BLENDER OBJECT", UDim2.new(), UDim2.new())
	rigCaption.TextSize, objectCaption.TextSize = 11, 11

	local pick, pickText =
		Chrome.menuButton(frame, "PickAccessory", "USE SELECTION", UDim2.new(), UDim2.new(), 213)
	local accessoryLabel = label(
		frame,
		"Accessory",
		"Select a weapon or accessory in Explorer.",
		UDim2.new(),
		UDim2.new()
	)
	accessoryLabel.TextWrapped, accessoryLabel.TextTruncate = true, Enum.TextTruncate.None
	local exportAccessory = Chrome.menuButton(
		frame,
		"ExportAccessory",
		"EXPORT ACCESSORY",
		UDim2.new(),
		UDim2.new(),
		213
	)
	local toolsHint = label(
		frame,
		"ToolsHint",
		"Export a selected weapon or accessory with the rig options above.",
		UDim2.new(),
		UDim2.new()
	)
	toolsHint.TextWrapped, toolsHint.TextTruncate, toolsHint.TextSize =
		true, Enum.TextTruncate.None, 12

	local direction, directionText = Chrome.menuButton(
		frame,
		"Direction",
		"BLENDER " .. utf8.char(0x2192) .. " ECLIPSE",
		UDim2.fromOffset(12, 105),
		UDim2.fromOffset(300, 25),
		213
	)
	local live, liveText, liveMark = checkbox("Live", "Live sync")
	local rigButton, rigText = Chrome.menuButton(
		frame,
		"Rig",
		"ECLIPSE RIG",
		UDim2.fromOffset(12, 143),
		UDim2.fromOffset(214, 25),
		213
	)
	local objectButton, objectText = Chrome.menuButton(
		frame,
		"Object",
		"BLENDER OBJECT",
		UDim2.fromOffset(234, 143),
		UDim2.fromOffset(222, 25),
		213
	)
	for _, button in { rigButton, objectButton } do
		button.TextLabel.Position, button.TextLabel.Size =
			UDim2.fromOffset(8, 0), UDim2.new(1, -36, 1, 0)
		button.TextLabel.TextXAlignment = Enum.TextXAlignment.Left
		chevron(button)
	end

	rigText.TextTruncate, objectText.TextTruncate, directionText.TextTruncate =
		Enum.TextTruncate.AtEnd, Enum.TextTruncate.AtEnd, Enum.TextTruncate.AtEnd
	local sectionDivider = Instance.new("Frame")
	sectionDivider.Name, sectionDivider.BorderSizePixel, sectionDivider.ZIndex =
		"SectionDivider", 0, 213
	sectionDivider.BackgroundTransparency = 0.35
	sectionDivider:SetAttribute("ThemeBg", "Strk")
	sectionDivider.Parent = frame
	local mapping = Instance.new("ScrollingFrame")

	mapping.Name, mapping.Position, mapping.Size =
		"BoneMapping", UDim2.fromOffset(12, 205), UDim2.fromOffset(444, 122)
	mapping.BackgroundTransparency, mapping.BorderSizePixel, mapping.ScrollBarThickness, mapping.ZIndex =
		1, 0, 3, 213
	mapping.AutomaticCanvasSize = Enum.AutomaticSize.None
	mapping.ScrollingDirection = Enum.ScrollingDirection.Y
	mapping.ClipsDescendants = true
	mapping.CanvasSize = UDim2.new()
	mapping.Parent = frame
	local fields, mappingKey, lastPaired = {}, nil, nil
	local emptyMapping = label(
		mapping,
		"EmptyMapping",
		"Choose an Eclipse rig and Blender object to map bones.",
		UDim2.fromOffset(8, 10),
		UDim2.new(1, -16, 0, 40)
	)
	emptyMapping.TextWrapped = true
	emptyMapping.TextTruncate = Enum.TextTruncate.None
	emptyMapping.TextSize = 12
	emptyMapping.TextTransparency = 0.25
	local boneHeading = label(frame, "BoneHeading", "ECLIPSE BONE", UDim2.new(), UDim2.new())
	local sourceHeading = label(frame, "SourceHeading", "BLENDER BONE", UDim2.new(), UDim2.new())
	boneHeading.TextSize = 11
	sourceHeading.TextSize = 11
	local download = label(
		frame,
		"Download",
		"Community Server — link on our Creator Store page",
		UDim2.new(),
		UDim2.new()
	)
	download.TextSize = 11
	download.TextXAlignment = Enum.TextXAlignment.Left
	download.TextTransparency = 0.15
	local search =
		field(frame, "SearchBones", "", UDim2.fromOffset(12, 177), UDim2.fromOffset(444, 24))
	search.PlaceholderText = "Search bones"
	local tracks, filtered, slots, editable = {}, {}, {}, true
	local cameraHint = label(
		mapping,
		"CameraHint",
		"CFrame and rendered vertical FOV sync together.",
		UDim2.fromOffset(4, 4),
		UDim2.fromOffset(428, 52)
	)
	cameraHint.TextWrapped, cameraHint.Visible = true, false

	local function save(slot)
		if slot.id then
			fields[slot.id] = slot.input.Text
		end
	end

	local function ensureSlots(count)
		for index = #slots + 1, count do
			local slot = {}
			slot.title = label(mapping, "Bone", "", UDim2.new(), UDim2.fromOffset(170, 23))
			slot.input = field(mapping, "Source", "", UDim2.new(), UDim2.fromOffset(250, 23))
			slot.input.FocusLost:Connect(function()
				save(slot)
			end)
			slots[index] = slot
		end
	end

	ensureSlots(7)

	local function render()
		emptyMapping.Visible = #filtered == 0 and not cameraHint.Visible
		emptyMapping.Text = #tracks == 0
				and "Choose an Eclipse rig and Blender object to map bones."
			or "No bones match your search."
		local factor = host.docked and 1 or Chrome.scale(frame)
		local visible = math.ceil(mapping.AbsoluteWindowSize.Y / (27 * factor)) + 2
		ensureSlots(visible)
		local first = math.max(1, math.floor(mapping.CanvasPosition.Y / (27 * factor)))
		for offset, slot in slots do
			local track = (offset <= visible and filtered[first + offset - 1]) or nil
			if slot.id ~= (track and track.id) then
				save(slot)
				if slot.input:IsFocused() then
					slot.input:ReleaseFocus()
				end

				slot.id = track and track.id
				slot.input.Text = track and fields[track.id] or ""
			end

			slot.title.Visible, slot.input.Parent.Visible = track ~= nil, track ~= nil
			slot.input.TextEditable = editable
			if track then
				local y = 2 + (first + offset - 2) * 27
				slot.title.Text, slot.title.Position = track.name, UDim2.fromOffset(4, y)
				slot.title.Size = UDim2.new(0.4, -12, 0, 23)
				slot.input.Parent.Size = UDim2.new(0.6, -12, 0, 23)
				slot.input.Parent.Position = UDim2.new(0.4, 0, 0, y)
			end
		end
	end

	local queued = false
	mapping:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if queued then
			return
		end

		queued = true
		task.defer(function()
			queued = false
			if window == frame then
				render()
			end
		end)
	end)

	local function filter()
		filtered = {}
		local query = search.Text:lower()
		for _, track in tracks do
			if query == "" or track.name:lower():find(query, 1, true) then
				table.insert(filtered, track)
			end
		end

		mapping.CanvasSize = UDim2.fromOffset(0, #filtered * 27 + 8)
		mapping.CanvasPosition = Vector2.zero
		render()
	end

	search:GetPropertyChangedSignal("Text"):Connect(filter)
	local units = field(frame, "Units", "1", UDim2.fromOffset(88, 291), UDim2.fromOffset(54, 24))
	label(frame, "UnitsLabel", "Studs / unit", UDim2.fromOffset(12, 291), UDim2.fromOffset(76, 24))
	local automatic = Chrome.menuButton(
		frame,
		"Auto",
		"AUTO PAIR",
		UDim2.fromOffset(150, 291),
		UDim2.fromOffset(58, 24),
		213
	)
	local pair = Chrome.menuButton(
		frame,
		"Pair",
		"SAVE PAIRING",
		UDim2.fromOffset(216, 291),
		UDim2.fromOffset(116, 24),
		213
	)
	local unpair = flatButton(frame, "Unpair", "Unpair")
	local pull = Chrome.menuButton(
		frame,
		"PullKeys",
		"IMPORT FROM BLENDER",
		UDim2.fromOffset(12, 325),
		UDim2.fromOffset(214, 25),
		213
	)
	local groupKeys, groupKeysText, groupMark =
		checkbox("GroupImportedKeys", "Group imported keyframes")
	groupKeys.Activated:Connect(function()
		Bridge.setGroupImportedKeys(not Bridge.status().groupImportedKeys)
	end)
	local push = Chrome.menuButton(
		frame,
		"PushKeys",
		"SEND TO BLENDER",
		UDim2.fromOffset(234, 325),
		UDim2.fromOffset(222, 25),
		213
	)
	for _, item in { units.Parent, frame.UnitsLabel, automatic, pair, unpair, pull, push } do
		item.Position += UDim2.fromOffset(0, 44)
	end

	pull:SetAttribute("Primary", true)
	for _, button in { pull, push, automatic, pair, direction } do
		button.TextLabel.TextSize = 12
	end

	local refresh

	local function closeChoices()
		if popup then
			popup:Destroy()
		end

		if popupButton then
			popupButton.DropdownArrow.Rotation = 0
		end

		popup, popupButton = nil, nil
	end

	local function choose(button, options, selected)
		local same = popupButton == button
		closeChoices()
		if same then
			return
		end

		local list = Instance.new("ScrollingFrame")

		list.Name, list.Position =
			"Choices", button.Position + UDim2.fromOffset(0, button.Size.Y.Offset + 3)
		list.Size = UDim2.fromOffset(
			button.AbsoluteSize.X / (host.docked and 1 or Chrome.scale(frame)),
			math.min(154, #options * 26)
		)
		list.BorderSizePixel, list.ScrollBarThickness, list.ZIndex = 0, 3, 240
		list.CanvasSize = UDim2.fromOffset(0, #options * 26)
		list:SetAttribute("ThemeBg", "TopBtn")
		list.Parent, popup, popupButton = frame, list, button
		button.DropdownArrow.Rotation = 180
		for index, option in options do
			local button, text = Chrome.menuButton(
				list,
				"Choice",
				option.name,
				UDim2.fromOffset(0, (index - 1) * 26),
				UDim2.new(1, -4, 0, 25),
				242
			)
			text.TextSize, text.TextTruncate = 12, Enum.TextTruncate.AtEnd
			button.Activated:Connect(function()
				selected(option)
				closeChoices()
				refresh()
			end)
		end

		Theme.applyTree(list)
	end

	refresh = function()
		if window ~= frame then
			return
		end

		local current = Bridge.status()
		groupMark.Visible = current.groupImportedKeys == true
		statusTitle.Text = current.error
				and (current.connected and "OPERATION / ERROR" or "CONNECTION / ERROR")
			or current.connected and "CONNECTED"
			or "CONNECTION"
		status.Text = current.available and current.message
			or "Open an Eclipse file to use Blender sync."
		connectText.Text = current.connected and "DISCONNECT"
			or current.busy and "CONNECTING"
			or current.error and "RETRY"
			or "CONNECT"
		directionText.Text = current.direction == "blender"
				and "BLENDER " .. utf8.char(0x2192) .. " ECLIPSE"
			or "ECLIPSE " .. utf8.char(0x2192) .. " BLENDER"
		liveMark.Visible = current.live == true
		local rig, object, paired
		for _, item in current.rigs do
			if item.id == rigId then
				rig = item
			end
		end

		if not rig and current.rigs[1] then
			rig = current.rigs[1]
			rigId = rig.id
		end

		for _, item in current.objects do
			if item.name == objectName then
				object = item
			end
		end

		if not object then
			objectName = nil
		end

		for _, item in current.pairs do
			if item.rig == rigId then
				paired = item
			end
		end

		if paired and (not object or (paired ~= lastPaired and not current.busy)) then
			objectName = paired.object
			for _, item in current.objects do
				if item.name == objectName then
					object = item
				end
			end
		end

		lastPaired = paired
		automatic.TextLabel.Text = object and "PAIR SELECTED" or "AUTO PAIR"
		pairingSummary.Text = paired and ("Paired with " .. paired.object)
			or "Choose your rig, then Auto pair to get started."
		pairingHint.Text = paired
				and "Ready to transfer animation below.\nManual pairing lets you adjust bone names and scale."
			or "Auto pair finds the matching Blender object.\nFor a different object or custom bone names, open Manual pairing."
		unpair.Visible = page == "pairing" and paired ~= nil
		if not current.connected then
			rigText.Text, objectText.Text = "Connect to Blender", "Connect to Blender"
			pairingSummary.Text = "Connect to Blender to choose rigs and transfer animation."
			pairingHint.Text = "Start the Eclipse server in Blender, then click Connect above."
		else
			rigText.Text = rig and rig.name or "Choose a rig"
			objectText.Text = object and object.name or "Choose an object"
		end

		local key = tostring(rigId)
			.. ":"
			.. tostring(objectName)
			.. ":"
			.. tostring(current.connected)
			.. ":"
			.. tostring(paired)
		if key ~= mappingKey then
			mappingKey = key
			for _, slot in slots do
				slot.id = nil
			end

			table.clear(fields)
			tracks = {}
			cameraHint.Visible = rig ~= nil and rig.kind == "camera"
			if rig and rig.kind == "camera" then
			elseif rig then
				local names = {}
				for _, name in object and object.bones or {} do
					local normalized = name:lower():gsub("[^%w]", "")
					names[normalized] = if names[normalized] ~= nil then false else name
				end

				for index, track in rig.tracks do
					local value = names[track.name:lower():gsub("[^%w]", "")] or ""
					for _, saved in paired and paired.tracks or {} do
						if saved.id == track.id and paired.object == objectName then
							value = saved.source
						end
					end

					fields[track.id] = value
					table.insert(tracks, track)
				end
			end

			filter()
		end

		for _, button in
			{
				direction,
				live,
				rigButton,
				objectButton,
				automatic,
				pair,
				unpair,
				pull,
				push,
				sync,
			}
		do
			button.Active = current.available and current.connected and not current.busy
			button.Interactable = button.Active
			button:SetAttribute("Ready", button.Active)
			button.TextLabel.TextTransparency = button.Active and 0.1 or 0.6
		end

		connect.Active, export.Active =
			current.available and not current.busy, current.available and not current.busy
		connect.Interactable, export.Interactable = connect.Active, export.Active
		connectText.TextTransparency, export.TextLabel.TextTransparency =
			connect.Active and 0.1 or 0.6, export.Active and 0.1 or 0.6
		pick.Active, exportAccessory.Active = export.Active, export.Active
		pick.Interactable, exportAccessory.Interactable = pick.Active, exportAccessory.Active
		units.TextEditable = pair.Active
		editable = pair.Active
		render()
	end

	connect.Activated:Connect(function()
		if connect.Active then
			Bridge.connect()
		end
	end)
	export.Activated:Connect(function()
		if export.Active then
			Bridge.exportRigs({ center = centered, welds = includeWelds })
		end
	end)
	direction.Activated:Connect(function()
		if not direction.Active then
			return
		end

		local state = Bridge.status()
		Bridge.mode(state.direction == "blender" and "eclipse" or "blender", state.live)
	end)
	live.Activated:Connect(function()
		if live.Active then
			local state = Bridge.status()
			Bridge.mode(state.direction, not state.live)
		end
	end)
	rigButton.Activated:Connect(function()
		if rigButton.Active then
			choose(rigButton, Bridge.status().rigs, function(value)
				rigId = value.id
				objectName = nil
				lastPaired = nil
			end)
		end
	end)
	objectButton.Activated:Connect(function()
		if objectButton.Active then
			choose(objectButton, Bridge.status().objects, function(value)
				objectName = value.name
			end)
		end
	end)
	pair.Activated:Connect(function()
		if not pair.Active then
			return
		end

		local values = {}
		for _, slot in slots do
			save(slot)
		end

		for id, value in fields do
			if value ~= "" then
				values[id] = value
			end
		end

		Bridge.pair(rigId, objectName, values, tonumber(units.Text))
	end)
	unpair.Activated:Connect(function()
		if unpair.Active then
			Bridge.unpair(rigId)
		end
	end)
	automatic.Activated:Connect(function()
		if automatic.Active then
			Bridge.pair(rigId, objectName, nil, tonumber(units.Text), true)
		end
	end)
	pull.Activated:Connect(function()
		if pull.Active then
			Bridge.pull()
		end
	end)
	push.Activated:Connect(function()
		if push.Active then
			Bridge.push()
		end
	end)
	local tooltip = label(
		frame,
		"UnitsTooltip",
		"Roblox studs per Blender unit. 1 = unchanged scale; 2 = one Blender unit moves two studs. Re-pair after changing it.",
		UDim2.new(),
		UDim2.fromOffset(280, 70)
	)
	tooltip.BackgroundTransparency, tooltip.TextWrapped, tooltip.TextTruncate, tooltip.TextSize =
		0, true, Enum.TextTruncate.None, 12
	tooltip.ZIndex, tooltip.Visible = 260, false
	tooltip:SetAttribute("ThemeBg", "Tip")
	tooltip:SetAttribute("ThemeTxt", "TipT")
	for _, item in { frame.UnitsLabel, units.Parent } do
		item.MouseEnter:Connect(function()
			tooltip.Visible = true
		end)
		item.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
	end

	units.Focused:Connect(function()
		tooltip.Visible = true
	end)
	require("NumericInput").connect(units, { step = 0.1, min = 0.001 }, function()
		tooltip.Visible = false
	end)
	local lastLayout

	local function layout()
		if window ~= frame then
			return
		end

		local size = host.docked and frame.AbsoluteSize / Chrome.scale(frame)
			or Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset)
		local width, height = size.X, size.Y
		local signature = table.concat({
			width,
			height,
			page,
			tostring(centered),
			tostring(includeWelds),
			tostring(host.docked),
			tostring(manual),
		}, ":")
		if lastLayout == signature then
			return
		end

		lastLayout = signature
		for _, handle in frame:GetChildren() do
			if handle.Name:match("^EclipseResizeHandle_") then
				handle.Visible = not host.docked
			end
		end

		local half = (width - 32) / 2

		local function place(item, x, y, w, h)
			item.Position, item.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
		end

		place(statusPanel, 12, 50, width - 24, 58)
		place(tabBar, 12, 118, width - 24, 30)
		place(pairingTab, 2, 2, (width - 28) / 2, 26)
		place(toolsTab, 2 + (width - 28) / 2, 2, (width - 28) / 2, 26)
		place(rigCaption, 12, 154, half, 16)
		place(objectCaption, 20 + half, 154, half, 16)
		place(rigButton, 12, 174, half, 28)
		place(objectButton, 20 + half, 174, half, 28)
		place(automatic, 12, 214, 140, 28)
		place(pair, 160, 214, width - 268, 28)
		place(unpair, width - 100, 214, 88, 28)
		place(manualButton, 12, 250, width - 24, 24)
		place(search.Parent, 12, 284, width - 208, 26)
		place(frame.UnitsLabel, width - 184, 284, 108, 26)
		place(units.Parent, width - 64, 284, 52, 26)
		place(boneHeading, 16, 316, (width - 24) * 0.4 - 12, 16)
		place(sourceHeading, 12 + (width - 24) * 0.4, 316, (width - 24) * 0.6 - 12, 16)
		place(mapping, 12, 336, width - 24, math.max(28, height - 478))
		place(pairingSummary, 18, 286, width - 36, 40)
		place(pairingHint, 18, 326, width - 36, math.max(34, height - 470))
		place(sectionDivider, 12, height - 138, width - 24, 1)
		place(groupKeys, 12, height - 130, width - 24, 26)
		place(pull, 12, height - 98, half, 32)
		place(push, 20 + half, height - 98, half, 32)
		place(direction, 148, height - 46, width - 160, 28)
		place(live, 12, height - 46, 128, 28)
		place(download, 12, 30, width - 24, 16)
		place(rigToolsHeading, 12, 214, width - 24, 18)
		place(export, 12, 238, half, 28)
		place(sync, 20 + half, 238, half, 28)
		place(center, 12, 274, half, 26)
		place(welds, 20 + half, 274, half, 26)
		place(toolsDivider, 12, 310, width - 24, 1)
		place(accessoryHeading, 12, 322, width - 24, 18)
		place(accessoryLabel, 12, 344, width - 24, 30)
		place(pick, 12, 382, 130, 28)
		place(exportAccessory, 150, 382, width - 162, 28)
		place(toolsHint, 12, 418, width - 24, math.max(28, height - 480))
		place(tooltip, math.max(12, width - 322), 208, math.min(310, width - 24), 70)
		for _, item in
			{
				search.Parent,
				mapping,
				boneHeading,
				sourceHeading,
				units.Parent,
				frame.UnitsLabel,
				pair,
			}
		do
			item.Visible = page == "pairing" and manual
		end

		for _, item in { automatic, pull, push, groupKeys, manualButton, sectionDivider } do
			item.Visible = page == "pairing"
		end

		for _, item in { pairingSummary, pairingHint } do
			item.Visible = page == "pairing" and not manual
		end

		unpair.Visible = page == "pairing" and lastPaired ~= nil
		for _, item in
			{
				export,
				sync,
				center,
				welds,
				pick,
				accessoryLabel,
				exportAccessory,
				toolsHint,
				rigToolsHeading,
				accessoryHeading,
				toolsDivider,
			}
		do
			item.Visible = page == "tools"
		end

		manualButton.DropdownArrow.Rotation = manual and 180 or 0
		for _, entry in { { pairingTab, "pairing" }, { toolsTab, "tools" } } do
			local selected = page == entry[2]
			entry[1]:SetAttribute("ThemeBgTransparency", selected and 0 or 1)
			FX.setRestingProperty(entry[1], "BackgroundTransparency", selected and 0 or 1)
			entry[1].TextLabel.TextTransparency = selected and 0 or 0.25
			Theme.applyTree(entry[1])
		end

		centerMark.Visible, weldsMark.Visible = centered, includeWelds
		closeChoices()
		render()
	end

	host.layout = layout
	SizeableWindows.attach({
		frame = frame,
		mouse = refs.State.mouse,
		minSize = MIN_SIZE,
		maxSize = Vector2.new(1400, 1200),
	})
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	manualButton.Activated:Connect(function()
		manual = not manual
		tooltip.Visible = false
		layout()
	end)
	pairingTab.Activated:Connect(function()
		page = "pairing"
		layout()
	end)
	toolsTab.Activated:Connect(function()
		page = "tools"
		tooltip.Visible = false
		layout()
	end)
	center.Activated:Connect(function()
		centered = not centered
		layout()
	end)
	welds.Activated:Connect(function()
		includeWelds = not includeWelds
		layout()
	end)
	sync.Activated:Connect(function()
		if sync.Active then
			Bridge.syncBones(rigId)
		end
	end)
	pick.Activated:Connect(function()
		if pick.Active then
			local message, selected = Bridge.pickAccessory(rigId)
			accessoryLabel.Text = message
			pickText.Text = selected and "CANCEL" or "USE SELECTION"
		end
	end)
	exportAccessory.Activated:Connect(function()
		if exportAccessory.Active then
			Bridge.exportAccessory(rigId, { center = centered, welds = includeWelds })
		end
	end)
	layout()
	local refreshQueued = false
	unsubscribe = Bridge.subscribe(function()
		if refreshQueued then
			return
		end

		refreshQueued = true
		task.defer(function()
			refreshQueued = false
			if window == frame then
				refresh()
			end
		end)
	end)
	Chrome.bindDrag(frame, drag, {
		clamp = true,
		margin = 8,
		disabled = function()
			return host.docked or host.busy
		end,
	})
	Theme.addRoot(frame)
	Theme.applyTree(frame)
	refresh()
	FX.pop(frame)
	task.defer(function()
		if window == frame and Bridge.ensureConnected then
			Bridge.ensureConnected()
		end
	end)
	if refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end

	return frame
end

function Window.toggle()
	if window then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(options)
	Window.destroy()
	refs = options
	refs.State.BlenderImport = Window
	Bridge.init(refs)
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Window.close(true)
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Window.destroy))
	table.insert(
		connections,
		options.ScreenGui.AncestryChanged:Connect(function()
			if not options.ScreenGui.Parent then
				Window.destroy()
			end
		end)
	)
	table.insert(
		connections,
		options.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not options.AnimatorFrame.Visible then
				Window.close(true)
			end
		end)
	)
	table.insert(connections, options.AnimatorFrame.Destroying:Connect(Window.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Window.destroy))
end

return Window
