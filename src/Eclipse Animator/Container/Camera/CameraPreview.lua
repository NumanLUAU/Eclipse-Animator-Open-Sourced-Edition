--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local DockHost = require("DockHost")

local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Organization = require("Organization")
local CameraRig = require("CameraRig")
local CameraTarget = require("Target")
local Visibility = require("Visibility")
local Selection = game:GetService("Selection")
local Scene = require("Environment")
local Chrome = require("Chrome")
local Surface = require("Surface")
local Sizeable = require("SizeableWindows")
local FX = require("WindowFX")
local Theme = require("Theme")
local Data = require("ProjectData")
local Preferences = require("Preferences")
local Preview = {}
local ViewRotate = require("ViewRotate")
local viewRotate
local refs, window, scene, screenGrid, previewGrid, field, fovLabel, gridButton, empty, viewport, title
local docked, docking, widgetFocused = false, false, false
local widgetConnections = {}
local widget, floatingGui, floating, dockLabel
local linked, grid, static, mainGrid = true, false, 70, false
local fitted, fitLabel, full = false, nil, nil
local opening, dockRequest = false, nil
local currentCamera, observedSelection, navigation
local retiring = {}
local accessoryButton
local accessoryViews = setmetatable({}, { __mode = "k" })

local function accessoryView(rig)
	if not rig then
		return nil
	end

	local attachment = CameraTarget.attachmentObject(rig)
	local state = accessoryViews[rig]
	if not state or state.attachment ~= attachment then
		state =
			{ attachment = attachment, hidden = attachment ~= nil and attachment.Name == "Head" }
		accessoryViews[rig] = state
	end

	return state
end

local sceneIsolated
local updateView

function Preview.toggleAccessories()
	local state = accessoryView(Preview.target(Preview.cameras()))
	if state then
		state.hidden = not state.hidden
		updateView()
	end
end

local previewGate, previewMatte
local authoredPreviewFov = 70
local previewElapsed = math.huge
local previewPlaying = false
local titleState = {}

local function maskTransparency()
	return 1 - (Preferences.get("CameraPreviewMaskOpacity") or 45) / 100
end

local function make(class, parent, name, properties)
	local object = Instance.new(class)

	object.Name = name
	for key, value in properties do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local gridKinds =
	{ "Thirds", "Golden Ratio", "Golden Spiral", "Triangles", "Center", "Custom Image" }
local composition =
	{ kind = "Thirds", opacity = 0.55, thickness = 2, rotation = 0, image = "", fit = true }
local compositionProfiles = {}
local compositionViews = {}
local compositionOwned = {}
local compositionWindow
local compositionGeneration = 0

local function finite(value, fallback, low, high)
	local n = tonumber(value)
	if not n or n ~= n or math.abs(n) == math.huge then
		return fallback
	end

	return math.clamp(n, low, high)
end

local function normalizeComposition(value)
	value = type(value) == "table" and value or {}
	return {
		kind = table.find(gridKinds, value.kind) and value.kind or "Thirds",
		opacity = finite(value.opacity, 0.55, 0, 1),
		thickness = finite(value.thickness, 2, 1, 6),
		rotation = math.floor(finite(value.rotation, 0, 0, 359) / 90 + 0.5) % 4 * 90,
		image = require("Sequence").asset(value.image) or "",
		fit = value.fit ~= false,
		profile = type(value.profile) == "string" and value.profile or nil,
	}
end

local function readCompositionSetting(key, fallback)
	local ok, value = pcall(Data.getSetting, key)
	if ok and type(value) == "string" then
		ok, value = pcall(game.HttpService.JSONDecode, game.HttpService, value)
	end

	return ok and type(value) == "table" and value or fallback
end

local function saveComposition()
	Data.setSetting("EclipseCompositionGridV1", game.HttpService:JSONEncode(composition))
	for _, refresh in compositionViews do
		refresh()
	end
end

function Preview.composition()
	return table.clone(composition)
end

function Preview.compositionPresets()
	local result = {}
	for _, entry in compositionProfiles do
		table.insert(result, { name = entry.name, config = table.clone(entry.config) })
	end

	return result
end

function Preview.setComposition(value)
	local nextValue = normalizeComposition(value)
	if nextValue.kind == "Custom Image" and nextValue.image == "" then
		return false, "Paste an image asset ID or choose a recent image."
	end

	local old = composition
	composition = nextValue
	local ok, err = pcall(saveComposition)
	if not ok then
		composition = old
		return false, tostring(err)
	end

	return true
end

function Preview.saveCompositionPreset(name)
	name = tostring(name or ""):match("^%s*(.-)%s*$"):sub(1, 80)
	if name == "" then
		return false, "Give the preset a name."
	end

	local nextProfiles = table.clone(compositionProfiles)
	local found
	for index, entry in nextProfiles do
		if entry.name == name then
			found = index
			break
		end
	end

	if not found and #nextProfiles >= 20 then
		return false, "You can save up to 20 grid presets."
	end

	local config = table.clone(composition)
	config.profile = name
	nextProfiles[found or #nextProfiles + 1] = { name = name, config = config }
	local ok, err = pcall(
		Data.setSetting,
		"EclipseCompositionPresetsV1",
		game.HttpService:JSONEncode(nextProfiles)
	)
	if not ok then
		return false, tostring(err)
	end

	compositionProfiles = nextProfiles
	return true
end

function Preview.deleteCompositionPreset(name)
	local profiles = {}
	for _, entry in compositionProfiles do
		if entry.name ~= name then
			table.insert(profiles, entry)
		end
	end

	local ok, err =
		pcall(Data.setSetting, "EclipseCompositionPresetsV1", game.HttpService:JSONEncode(profiles))
	if not ok then
		return false, tostring(err)
	end

	compositionProfiles = profiles
	return true
end

function Preview.cycleComposition()
	local choices = {}
	for _, kind in gridKinds do
		if kind ~= "Custom Image" then
			local c = table.clone(composition)
			c.kind = kind
			c.profile = nil
			table.insert(choices, c)
		end
	end

	for _, entry in compositionProfiles do
		local c = table.clone(entry.config)
		c.profile = entry.name
		table.insert(choices, c)
	end

	local current = 0
	for i, value in choices do
		if
			composition.profile and composition.profile == value.profile
			or not composition.profile and not value.profile and composition.kind == value.kind
		then
			current = i
			break
		end
	end

	return Preview.setComposition(choices[current % #choices + 1])
end

function Preview.rotateComposition()
	local value = table.clone(composition)
	value.rotation = (value.rotation + 90) % 360
	value.profile = nil
	return Preview.setComposition(value)
end

function Preview.compositionSegments(kind, size)
	local result = {}

	local function line(x, y, u, v)
		table.insert(result, { Vector2.new(x, y), Vector2.new(u, v) })
	end

	if kind == "Thirds" or kind == "Golden Ratio" then
		local n = kind == "Thirds" and 1 / 3 or (3 - math.sqrt(5)) / 2
		for _, at in { n, 1 - n } do
			line(at, 0, at, 1)
			line(0, at, 1, at)
		end
	elseif kind == "Center" then
		line(0.5, 0, 0.5, 1)
		line(0, 0.5, 1, 0.5)
	elseif kind == "Triangles" then
		line(0, 1, 1, 0)
		line(0, 0, 0.5, 0.5)
		line(0.5, 0.5, 1, 1)
	elseif kind == "Golden Spiral" then
		local previous
		local factor = math.min(size.X, size.Y) * 0.46
		local phi = (1 + math.sqrt(5)) / 2
		for i = 0, 96 do
			local angle = -math.pi * 4 + i / 96 * math.pi * 4
			local radius = factor * math.exp(math.log(phi) / (math.pi / 2) * angle)
			local point = Vector2.new(
				0.5 + radius * math.cos(angle) / math.max(size.X, 1),
				0.5 + radius * math.sin(angle) / math.max(size.Y, 1)
			)
			if previous then
				table.insert(result, { previous, point })
			end

			previous = point
		end
	end

	return result
end

function Preview.closeGridSettings()
	compositionGeneration += 1
	if compositionWindow then
		local view = compositionWindow
		compositionWindow = nil
		view:close(true)
	end

	for gui in compositionOwned do
		gui:Destroy()
	end

	table.clear(compositionOwned)
end

function Preview.toggleGridSettings()
	if compositionWindow then
		Preview.closeGridSettings()
		return
	end

	if not refs then
		return
	end

	local Tool = require("Tool")
	local recent = require("ImageLibrary")
	local draft = Preview.composition()
	local recentIndex = 0
	local view = Tool.new(
		refs,
		"EclipseGridSettings",
		"GRID SETTINGS",
		Vector2.new(430, 324),
		true,

		function()
			compositionGeneration += 1
			compositionWindow = nil
		end
	)
	compositionWindow = view
	compositionOwned[view.gui] = true
	view.gui.Destroying:Once(function()
		compositionOwned[view.gui] = nil
	end)
	local apply

	local function report(message)
		require("Notification").show("GRID SETTINGS", message)
	end

	local kind, kindLabel
	local choices
	kind, kindLabel = Tool.button(
		view.frame,
		"Guide",
		draft.kind .. "  \u{25be}",
		UDim2.fromOffset(12, 42),
		UDim2.new(1, -24, 0, 27),

		function()
			choices.Visible = not choices.Visible
		end
	)
	choices = Tool.make("Frame", view.frame, "GuideChoices", {
		Visible = false,
		Position = UDim2.fromOffset(12, 71),
		Size = UDim2.new(1, -24, 0, #gridKinds * 28 + 4),
		BorderSizePixel = 0,
		ZIndex = 100,
		Active = true,
	})
	choices:SetAttribute("ThemeBg", "TopBtn")
	for index, value in gridKinds do
		Tool.button(
			choices,
			"Guide" .. index,
			value,
			UDim2.fromOffset(2, 2 + (index - 1) * 28),
			UDim2.new(1, -4, 0, 26),

			function()
				draft.kind = value
				kindLabel.Text = value .. "  \u{25be}"
				choices.Visible = false
				apply(false)
			end
		)
	end

	table.insert(
		view.connections,
		game:GetService("UserInputService").InputBegan:Connect(function(input)
			if not choices.Visible then
				return
			end

			if input.KeyCode == Enum.KeyCode.Escape then
				choices.Visible = false
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				local function inside(object)
					local p, s = object.AbsolutePosition, object.AbsoluteSize
					local point = input.Position
					return point.X >= p.X
						and point.Y >= p.Y
						and point.X <= p.X + s.X
						and point.Y <= p.Y + s.Y
				end

				if not inside(kind) and not inside(choices) then
					choices.Visible = false
				end
			end
		end)
	)
	local asset = Tool.field(
		view.frame,
		"ImageAsset",
		draft.image,
		UDim2.fromOffset(12, 78),
		UDim2.new(1, -182, 0, 25)
	)
	asset.PlaceholderText = "Image asset ID"

	local function selectImage(id)
		if id then
			draft.kind = "Custom Image"
			draft.image = id
			asset.Text = id
			kindLabel.Text = draft.kind .. "  \u{25be}"
			apply(false)
		end
	end

	Tool.button(
		view.frame,
		"Recent",
		"RECENT",
		UDim2.new(1, -162, 0, 77),
		UDim2.fromOffset(72, 27),

		function()
			local images = recent.recent()
			if #images == 0 then
				report("No recent images. Paste an ID or upload an image.")
				return
			end

			recentIndex = recentIndex % #images + 1
			selectImage(images[recentIndex].id)
		end
	)
	local busy = false
	Tool.button(view.frame, "Upload", "UPLOAD", UDim2.new(1, -84, 0, 77), UDim2.fromOffset(72, 27), function()
		if busy then
			return
		end

		busy = true
		local token = compositionGeneration
		task.spawn(function()
			local ok, id, message = pcall(require("Upload").prompt)
			busy = false
			if token ~= compositionGeneration or view.closed then
				return
			end

			if ok and id then
				selectImage(id)
			else
				report(tostring(ok and message or id or "Upload cancelled."))
			end
		end)
	end
)
	Tool.label(
		view.frame,
		"OpacityLabel",
		"Opacity %",
		UDim2.fromOffset(12, 115),
		UDim2.fromOffset(86, 25)
	)
	local opacity = Tool.field(
		view.frame,
		"Opacity",
		math.round(draft.opacity * 100),
		UDim2.fromOffset(100, 115),
		UDim2.fromOffset(60, 25)
	)
	Tool.label(
		view.frame,
		"ThicknessLabel",
		"Width",
		UDim2.fromOffset(178, 115),
		UDim2.fromOffset(48, 25)
	)
	local thickness = Tool.field(
		view.frame,
		"Thickness",
		draft.thickness,
		UDim2.fromOffset(230, 115),
		UDim2.fromOffset(44, 25)
	)
	local rotation, rotationLabel
	rotation, rotationLabel = Tool.button(
		view.frame,
		"Rotate",
		draft.rotation .. "\u{b0}",
		UDim2.fromOffset(292, 114),
		UDim2.fromOffset(56, 27),

		function()
			draft.rotation = (draft.rotation + 90) % 360
			rotationLabel.Text = draft.rotation .. "\u{b0}"
			apply(false)
		end
	)
	local fit, fitLabel
	fit, fitLabel = Tool.button(
		view.frame,
		"Fit",
		draft.fit and "FIT" or "FILL",
		UDim2.fromOffset(354, 114),
		UDim2.fromOffset(64, 27),

		function()
			draft.fit = not draft.fit
			fitLabel.Text = draft.fit and "FIT" or "FILL"
			apply(false)
		end
	)
	local name = Tool.field(
		view.frame,
		"PresetName",
		"",
		UDim2.fromOffset(12, 154),
		UDim2.new(1, -178, 0, 25)
	)
	name.PlaceholderText = "Preset name"
	local list = Tool.make("ScrollingFrame", view.frame, "Presets", {
		Position = UDim2.fromOffset(12, 190),
		Size = UDim2.new(1, -24, 0, 96),
		CanvasSize = UDim2.new(),
		BackgroundTransparency = 0,
		BorderSizePixel = 1,
		ScrollBarThickness = 4,
	})
	list:SetAttribute("ThemeBg", "TopBtn")
	list:SetAttribute("ThemeBorder", "Strk")
	list.BorderColor3 = Theme.get("Strk", Color3.fromRGB(74, 116, 124))

	local function showDraft(value)
		draft = table.clone(value)
		kindLabel.Text = draft.kind .. "  \u{25be}"
		asset.Text = draft.image
		opacity.Text = tostring(math.round(draft.opacity * 100))
		thickness.Text = tostring(draft.thickness)
		rotationLabel.Text = draft.rotation .. "\u{b0}"
		fitLabel.Text = draft.fit and "FIT" or "FILL"
	end

	local function refresh()
		for _, child in list:GetChildren() do
			child:Destroy()
		end

		for index, entry in Preview.compositionPresets() do
			Tool.button(
				list,
				entry.name,
				entry.name,
				UDim2.fromOffset(0, (index - 1) * 29),
				UDim2.new(1, -6, 0, 25),

				function()
					name.Text = entry.name
					showDraft(entry.config)
					apply(false)
				end
			)
		end

		list.CanvasSize = UDim2.fromOffset(0, #compositionProfiles * 29)
	end

	apply = function(save)
		compositionGeneration += 1
		local token = compositionGeneration
		draft.image = asset.Text
		draft.opacity = finite(opacity.Text, 55, 0, 100) / 100
		draft.thickness = finite(thickness.Text, 2, 1, 6)
		draft.profile = nil
		local nextValue = normalizeComposition(draft)
		if nextValue.kind == "Custom Image" and nextValue.image == "" then
			report("Paste an image asset ID first.")
			return
		end

		task.spawn(function()
			local image, worker
			local loaded = true
			if nextValue.kind == "Custom Image" then
				loaded = false
				image = Instance.new("ImageLabel")
				image.Image = nextValue.image
				local settled = false
				worker = task.spawn(function()
					pcall(function()
						game:GetService("ContentProvider")
							:PreloadAsync({ image }, function(_, fetch)
								loaded = fetch == Enum.AssetFetchStatus.Success
							end)
					end)
					loaded = loaded or image.IsLoaded
					settled = true
				end)
				local untilTime = os.clock() + 10
				while not settled and token == compositionGeneration and os.clock() < untilTime do
					task.wait(0.03)
				end

				if not settled then
					pcall(task.cancel, worker)
				end

				image:Destroy()
			end

			if token ~= compositionGeneration or view.closed then
				return
			end

			if not loaded then
				report("Image could not load. The previous grid is unchanged.")
				return
			end

			local ok, message = Preview.setComposition(nextValue)
			if ok and nextValue.kind == "Custom Image" then
				recent.add(
					nextValue.image,
					{ name = name.Text ~= "" and name.Text or "Composition grid" }
				)
			end

			if ok and save then
				ok, message = Preview.saveCompositionPreset(name.Text)
				refresh()
			end

			if not ok then
				report(tostring(message))
			end
		end)
	end

	Tool.button(view.frame, "Save", "SAVE", UDim2.new(1, -158, 0, 153), UDim2.fromOffset(68, 27), function()
		apply(true)
	end
)
	Tool.button(
		view.frame,
		"Delete",
		"DELETE",
		UDim2.new(1, -84, 0, 153),
		UDim2.fromOffset(72, 27),

		function()
			local ok, message = Preview.deleteCompositionPreset(name.Text)
			if not ok then
				report(tostring(message))
			end

			refresh()
		end
	)
	local shortcuts = require("Shortcuts")
	Tool.label(
		view.frame,
		"Shortcuts",
		shortcuts.format("ToggleCameraGrid")
			.. ": toggle   "
			.. shortcuts.format("CycleCameraGrid")
			.. ": next guide   "
			.. shortcuts.format("RotateCameraGrid")
			.. ": rotate",
		UDim2.fromOffset(12, 292),
		UDim2.new(1, -24, 0, 30)
	)
	for _, field in { asset, opacity, thickness } do
		table.insert(
			view.connections,
			require("NumericInput").connect(field, {
				step = 1,
				enabled = function()
					return field ~= asset
				end,
			}, function()
				apply(false)
			end)
		)
	end

	refresh()
	Theme.applyTree(view.frame)
	return view.frame
end

function Preview.grid(parent, name, z)
	local frame = make("Frame", parent, name, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		Active = false,
		Interactable = false,
		ClipsDescendants = true,
	})
	local image = make("ImageLabel", frame, "CustomGrid", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = z,
		Active = false,
		Interactable = false,
	})
	local lines = {}

	local function layout()
		local size = frame.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end

		local custom = composition.kind == "Custom Image"
		image.Visible = custom
		image.Image = composition.image
		image.ImageTransparency = 1 - composition.opacity
		image.ScaleType = composition.fit and Enum.ScaleType.Fit or Enum.ScaleType.Stretch
		image.Rotation = composition.rotation
		image.Size = composition.rotation % 180 == 90
				and UDim2.fromScale(size.Y / size.X, size.X / size.Y)
			or UDim2.fromScale(1, 1)
		local segmentSize = composition.rotation % 180 == 90 and Vector2.new(size.Y, size.X) or size
		local segments = Preview.compositionSegments(composition.kind, segmentSize)
		local angle = math.rad(composition.rotation)
		local c, s = math.cos(angle), math.sin(angle)

		local function rotate(point)
			local p = point - Vector2.new(0.5, 0.5)
			return Vector2.new(p.X * c - p.Y * s + 0.5, p.X * s + p.Y * c + 0.5) * size
		end

		local color = Theme.get("Txt", Color3.fromRGB(225, 243, 238))
		for i, segment in segments do
			local line = lines[i]
			if not line then
				line = make("Frame", frame, "Guide" .. i, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BorderSizePixel = 0,
					ZIndex = z,
					Active = false,
					Interactable = false,
				})
				lines[i] = line
			end

			local a, b = rotate(segment[1]), rotate(segment[2])
			local delta = b - a
			local middle = (a + b) * 0.5
			line.Position = UDim2.fromScale(middle.X / size.X, middle.Y / size.Y)
			line.Size = UDim2.fromScale(delta.Magnitude / size.X, composition.thickness / size.Y)
			line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			line.BackgroundTransparency = 1 - composition.opacity
			line.BackgroundColor3 = color
			line.Visible = true
		end

		for i = #segments + 1, #lines do
			lines[i].Visible = false
		end
	end

	compositionViews[frame] = layout
	local resized = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local themed = Theme.onChanged(layout)
	frame.Destroying:Once(function()
		resized:Disconnect()
		themed()
		compositionViews[frame] = nil
	end)
	layout()
	return frame
end

function Preview.cameras(includeDisabled)
	local cameras, seen = {}, {}
	if not refs then
		return cameras
	end

	for _, rig in refs.State.getAllRigs() do
		if
			rig.Parent
			and not seen[rig]
			and CameraRig.isRig(rig)
			and (includeDisabled or Organization.isEnabled(rig))
		then
			seen[rig] = true
			table.insert(cameras, rig)
		end
	end

	return cameras
end

local function selectedCamera()
	local rig = refs and refs.State.Rig
	local item = rig and rig._lastClickedItem
	return item and CameraRig.owner(item.linkedRigInstance)
end

function Preview.target(cameras)
	cameras = cameras or Preview.cameras()
	local candidate = selectedCamera()
	if candidate ~= observedSelection then
		observedSelection = candidate
		if not full and table.find(cameras, candidate) then
			currentCamera = candidate
		end
	end

	if not table.find(cameras, currentCamera) then
		currentCamera = table.find(cameras, candidate) and candidate or cameras[1]
	end

	return currentCamera
end

function Preview.select(rig)
	local cameras = Preview.cameras()
	if not table.find(cameras, rig) then
		return false
	end

	currentCamera, observedSelection = rig, selectedCamera()
	if full then
		if viewRotate then
			viewRotate.finish(not viewRotate.isFlying())
		end

		if refs and refs.State.CameraControls then
			refs.State.CameraControls.finish(true)
		end

		if not full.view.setRig(rig) then
			Preview.exitFull()
			return false
		end

		full.rig = rig
		if
			not full.view.step(
				(linked or refs.State.CameraControls and refs.State.CameraControls.isEditing())
						and CameraRig.fov(rig)
					or static
			)
		then
			Preview.exitFull()
			return false
		end
	end

	if updateView then
		updateView(cameras)
	end

	return true
end

function Preview.navigate(direction)
	local cameras = Preview.cameras()
	if #cameras == 0 then
		return false
	end

	local index = table.find(cameras, Preview.target(cameras)) or 1
	local step = direction < 0 and -1 or 1
	return Preview.select(cameras[(index - 1 + step) % #cameras + 1])
end

function Preview.subtitleSurface()
	return Preview.isOpen() and previewGate or nil
end

function Preview.isOpen()
	if not window or not window.Parent then
		return false
	end

	if refs.State.PresentationHidden or docking or opening then
		return true
	end

	return window.Visible
		and (
			docked and widget ~= nil and widget.Enabled
			or not docked and floatingGui ~= nil and floatingGui.Enabled
		)
end

function Preview.hasFocus()
	if refs and refs.State.PresentationHidden then
		return false
	end

	if not Preview.isOpen() then
		return false
	end

	if docked then
		return widgetFocused
	end

	local point, p, size = Input:GetMouseLocation(), window.AbsolutePosition, window.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + size.X and point.Y <= p.Y + size.Y
end

function Preview.toggleGrid()
	grid = not grid
	Data.setSetting("CameraPreviewGrid", grid)
	if gridButton then
		gridButton:SetAttribute("Selected", grid)
	end

	return grid
end

function Preview.mainGridEnabled()
	return mainGrid
end

function Preview.toggleMainGrid()
	mainGrid = not mainGrid
	Data.setSetting("CameraMainGrid", mainGrid)
	return mainGrid
end

function Preview.setLinked(enabled)
	linked = enabled == true
	Data.setSetting("CameraPreviewLinkedFOV", linked)
end

function Preview.setStatic(value)
	static = CameraRig.clamp(value)
	Data.setSetting("CameraPreviewStaticFOV", static)
end

function Preview.isDocked()
	return docked
end

function Preview.setDocked(enabled)
	if not window or docking or docked == enabled then
		return false
	end

	local frame = window
	local request = {}
	dockRequest, docking = request, true
	if enabled and not widget then
		if not refs.Plugin then
			dockRequest, docking = nil, false
			return false
		end

		local ok, created = pcall(function()
			return DockHost.acquire(
				refs.Plugin,
				"EclipseAnimatorCameraPreview",
				DockWidgetPluginGuiInfo.new(
					Enum.InitialDockState.Right,
					true,
					true,
					560,
					390,
					460,
					230
				)
			)
		end)
		if dockRequest ~= request or window ~= frame then
			if ok then
				DockHost.release(created)
			end

			return false
		end

		if not ok then
			dockRequest, docking = nil, false
			return false
		end

		widget = created
		widget.Title = "Eclipse Camera Preview"
		widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		table.insert(
			widgetConnections,
			widget.WindowFocused:Connect(function()
				if widget == created then
					widgetFocused = true
				end
			end)
		)
		table.insert(
			widgetConnections,
			widget.WindowFocusReleased:Connect(function()
				if widget == created then
					widgetFocused = false
				end
			end)
		)
		table.insert(
			widgetConnections,
			widget:GetPropertyChangedSignal("Enabled"):Connect(function()
				if widget ~= created then
					return
				end

				if not created.Enabled then
					widgetFocused = false
					if scene then
						scene.destroy()
						scene = nil
					end
				end

				if refs.State.Timeline then
					refs.State.Timeline:RefreshNavigation()
				end
			end)
		)
	end

	if
		enabled
		and not DockHost.show(widget, function()
			return dockRequest == request and window == frame
		end)
	then
		if dockRequest == request then
			dockRequest, docking = nil, false
			widget.Enabled = false
		end

		return false
	end

	FX.clear(frame)
	local scale = frame:FindFirstChild("EclipseWindowScale")
	if scale then
		scale.Scale = 1
	end

	docked = enabled
	if enabled then
		floating = { position = frame.Position, size = frame.Size }
		frame.Parent, frame.Position, frame.Size =
			widget, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
		widget.Enabled = true
	else
		frame.Parent, frame.Position, frame.Size = floatingGui, floating.position, floating.size
		widget.Enabled, widgetFocused = false, false
	end

	dockLabel.Text = docked and "UNDOCK" or "DOCK"
	for _, child in frame:GetChildren() do
		if string.find(child.Name, "EclipseResizeHandle_", 1, true) == 1 then
			child.Visible = not docked
		end
	end

	Data.setSetting("CameraPreviewDocked", docked)
	dockRequest, docking = nil, false
	return true
end

function Preview.presentationWidget()
	return widget
end

function Preview.close(immediate)
	opening, docking, dockRequest = false, false, nil
	local previous, previousGui, wasDocked = window, floatingGui, docked
	window, floatingGui, dockLabel, fitLabel = nil, nil, nil, nil
	docked, widgetFocused = false, false
	if scene then
		scene.destroy()
		scene = nil
	end

	field, gridButton, previewGrid, viewport = nil, nil, nil, nil
	accessoryButton = nil
	previewGate, previewMatte = nil, nil
	if navigation then
		for _, tween in navigation.tweens do
			tween:Cancel()
		end

		navigation = nil
	end

	if widget then
		widget.Enabled = false
	end

	if previous then
		retiring[previous] = previousGui or true
	end

	local function destroy()
		if previous then
			retiring[previous] = nil
			previous:Destroy()
		end

		if previousGui then
			previousGui:Destroy()
		end
	end

	if previous and not wasDocked and not immediate then
		FX.shrink(previous, destroy)
	else
		destroy()
	end

	if refs and refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end
end

function Preview.fitSize(width, height)
	if width <= 0 or height <= 0 then
		return UDim2.fromScale(1, 1)
	end

	local ratio = 1920 / 1080
	if width / height > ratio then
		return UDim2.fromScale(height * ratio / width, 1)
	end

	return UDim2.fromScale(1, width / ratio / height)
end

function Preview.frameGeometry(width, height, fov, fit)
	fov = CameraRig.clamp(fov)
	if width <= 0 or height <= 0 or not fit then
		return 1, 1, fov
	end

	local size = Preview.fitSize(width, height)
	local x, y = size.X.Scale * 0.92, size.Y.Scale * 0.92
	local tangent = math.tan(math.rad(fov) * 0.5)
	local minimumHeight = tangent / math.tan(math.rad(120) * 0.5)
	if y < minimumHeight then
		x, y = x * minimumHeight / y, minimumHeight
	end

	return x, y, math.deg(2 * math.atan(tangent / y))
end

local layoutState

local function layoutView()
	if not viewport or not previewGate then
		return authoredPreviewFov
	end

	local size = viewport.Parent.AbsoluteSize
	if
		layoutState
		and layoutState.viewport == viewport
		and layoutState.size == size
		and layoutState.authored == authoredPreviewFov
		and layoutState.fitted == fitted
	then
		return layoutState.fov
	end

	local x, y, fov = Preview.frameGeometry(size.X, size.Y, authoredPreviewFov, fitted)
	layoutState = {
		viewport = viewport,
		size = size,
		authored = authoredPreviewFov,
		fitted = fitted,
		fov = fov,
	}
	previewGate.Size = UDim2.fromScale(x, y)
	local left, top = math.max(0, (1 - x) * 0.5), math.max(0, (1 - y) * 0.5)
	local layouts = {
		{ 0, 0, 1, top },
		{ 0, 1 - top, 1, top },
		{ 0, top, left, 1 - 2 * top },
		{ 1 - left, top, left, 1 - 2 * top },
	}
	for i, rect in layouts do
		previewMatte[i].Position = UDim2.fromScale(rect[1], rect[2])
		previewMatte[i].Size = UDim2.fromScale(rect[3], rect[4])
	end

	if scene then
		scene.camera.FieldOfView = fov
	end

	return fov
end

function Preview.toggleFit()
	fitted = not fitted
	Data.setSetting("CameraPreviewFit", fitted)
	if fitLabel then
		fitLabel.Text = fitted and "UNFIT" or "FIT"
	end

	layoutView()
	return fitted
end

function Preview.isFull()
	return full ~= nil
end

function Preview.isViewRotating()
	return viewRotate ~= nil and viewRotate.isEditing()
		or refs and refs.State.CameraControls and refs.State.CameraControls.isEditing()
end

function Preview.finishViewRotation(cancel)
	if refs and refs.State.CameraControls then
		refs.State.CameraControls.finish(cancel)
	end

	return viewRotate and viewRotate.finish(cancel)
end

function Preview.fullInput(input)
	if not full or not viewRotate then
		return false
	end

	if game:GetService("UserInputService"):GetFocusedTextBox() then
		return false
	end

	local controls = refs.State.CameraControls
	local shortcuts = require("Shortcuts")
	local rotate = shortcuts.matches("ToggleBlenderGrab", input)
	local fov = shortcuts.matches("StartBlenderRotate", input)
	if rotate or fov then
		local axis = refs.State.Axis
		if
			require("BlenderEdit").blocked()
			or refs.State.Timeline:GetState().Playing
			or refs.State.Timeline:IsExportLocked()
			or refs.State.PhysicsSimulating
			or axis
				and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
		then
			return false
		end

		if fov then
			if not controls then
				return false
			end

			if controls.isEditing() then
				return controls.input(input)
			end

			viewRotate.finish(false)
			Preview.setLinked(true)
			return controls.begin(CameraRig.motor(full.rig, "FovPart"), "view")
		end

		if controls and controls.isEditing() then
			controls.finish(false)
		end

		if viewRotate.isFlying() then
			viewRotate.finish(false)
		end
	elseif controls and controls.isEditing() then
		return controls.input(input)
	end

	return viewRotate.input(input, full.rig)
end

function Preview.exitFull(fromVisibility)
	local previous = full
	if not previous then
		return false
	end

	if viewRotate then
		viewRotate.finish(not viewRotate.isFlying())
	end

	if refs and refs.State.CameraControls then
		refs.State.CameraControls.finish(true)
	end

	if Visibility.beforeHide then
		Visibility.beforeHide()
	end

	full = nil
	refs.State.CameraPoseMode = nil
	refs.State.CameraBonesHidden = nil
	previous.view.stop()
	local restoring = refs.State.ignoreSelectionChanged
	refs.State.ignoreSelectionChanged = true
	local selection = {}
	for _, object in previous.selection do
		if object.Parent then
			table.insert(selection, object)
		end
	end

	Selection:Set(selection)
	refs.State.ignoreSelectionChanged = restoring
	if not fromVisibility then
		Visibility.setHidden(previous.hidden, true)
	end

	return true
end

function Preview.toggleFull()
	if refs and refs.State.BlenderNavigation then
		local nav = refs.State.BlenderNavigation
		if nav.prepareCameraView then
			nav.prepareCameraView()
		else
			nav.stop()
		end
	end

	if full then
		return Preview.exitFull()
	end

	if not refs or not refs.Active() then
		return false
	end

	local rig = Preview.target()
	if not rig then
		Preview.open()
		return false
	end

	full = {
		rig = rig,
		view = CameraRig.startView(rig),
		hidden = refs.State.PresentationHidden,
		selection = Selection:Get(),
	}
	refs.State.CameraPoseMode = true
	refs.State.CameraBonesHidden = full.hidden or Preferences.get("ShowBonesInCamera") == false
	Visibility.setHidden(true, true)
	local restoring = refs.State.ignoreSelectionChanged
	refs.State.ignoreSelectionChanged = true
	Selection:Set({})
	refs.State.ignoreSelectionChanged = restoring
	if
		not full.view.step(
			(linked or refs.State.CameraControls and refs.State.CameraControls.isEditing())
					and CameraRig.fov(rig)
				or static
		)
	then
		Preview.exitFull()
		return false
	end

	return true
end

function Preview.cycleFull()
	if not full then
		return Preview.toggleFull()
	end

	local cameras = Preview.cameras()
	local index = table.find(cameras, full.rig)
	if not index or index >= #cameras then
		return Preview.exitFull()
	end

	return Preview.select(cameras[index + 1])
end

function Preview.togglePlayback()
	if refs.State.Timeline and refs.State.Timeline:IsExportLocked() then
		return
	end

	if not full or not refs.State.Timeline then
		return
	end

	if viewRotate and viewRotate.isFlying() then
		viewRotate.finish(false)
	end

	local timeline = refs.State.Timeline
	local state = timeline:GetState()
	if state.Playing then
		state.Playing = false
	else
		timeline:StartPlayback(true)
	end
end

function Preview.open()
	previewElapsed = math.huge
	if opening then
		return window
	end

	if window and window.Parent then
		window.Visible = true
		local active = window
		if docked then
			if
				not DockHost.show(widget, function()
					return window == active
				end) and window == active
			then
				Preview.setDocked(false)
			end

			if window ~= active then
				return nil
			end
		elseif floatingGui then
			floatingGui.Enabled = true
		end

		FX.clear(window)
		local scale = window:FindFirstChild("EclipseWindowScale")
		if scale then
			scale.Scale = 1
		end

		refs.State.Timeline:RefreshNavigation()
		return window
	end

	if window then
		Preview.close()
	end

	local frame = make("Frame", refs.ScreenGui, "CameraPreview", {
		Size = UDim2.fromOffset(560, 390),
		Position = UDim2.fromScale(0.66, 0.44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Active = true,
		Visible = false,
		ZIndex = 220,
		BorderSizePixel = 0,
	})
	window, opening = frame, true
	local factor = Chrome.scale(frame)
	local layer = make("ScreenGui", refs.ScreenGui.Parent, "EclipseCameraPreview", {
		IgnoreGuiInset = refs.ScreenGui.IgnoreGuiInset,
		ScreenInsets = refs.ScreenGui.ScreenInsets,
		ResetOnSpawn = false,
		DisplayOrder = refs.ScreenGui.DisplayOrder + 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	layer:SetAttribute("EclipseWindowIsolated", true)
	local layerScale = make("UIScale", layer, "Scale", { Scale = factor })
	local sourceScale = refs.ScreenGui:FindFirstChildOfClass("UIScale")
	if sourceScale then
		local changed = sourceScale:GetPropertyChangedSignal("Scale"):Connect(function()
			layerScale.Scale = sourceScale.Scale
		end)
		layer.Destroying:Once(function()
			changed:Disconnect()
		end)
	end

	floatingGui, frame.Parent = layer, layer
	Surface.fill(frame)
	local outline = make(
		"UIStroke",
		frame,
		"Outline",
		{ Color = Theme.panelOutlineDefault(), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	outline:SetAttribute("ThemeStrk", "Strk")
	local header, heading, drag = Chrome.header(frame, "CAMERA PREVIEW", 221, 192)
	title = heading
	title.TextTruncate = Enum.TextTruncate.AtEnd
	Chrome.close(header, Preview.close, 225)
	accessoryButton = Chrome.menuButton(
		header,
		"HideAccessories",
		"HIDE ACCESSORIES",
		UDim2.new(1, -178, 0, 3),
		UDim2.fromOffset(140, 24),
		225
	)
	accessoryButton.TextLabel.TextSize = 11
	accessoryButton.Activated:Connect(Preview.toggleAccessories)
	local fov = Chrome.menuButton(
		frame,
		"LinkFOV",
		"FOV",
		UDim2.fromOffset(10, 36),
		UDim2.fromOffset(72, 26),
		224
	)
	fovLabel = fov.TextLabel
	fovLabel.TextSize = 14
	fov.Corner.CornerRadius = UDim.new(0, 3)
	local box = make("Frame", frame, "StaticFOV", {
		Position = UDim2.fromOffset(90, 36),
		Size = UDim2.fromOffset(62, 26),
		BorderSizePixel = 0,
		ZIndex = 224,
		ClipsDescendants = true,
	})
	box:SetAttribute("ThemeBg", "TopBtn")
	local border = make(
		"UIStroke",
		box,
		"Outline",
		{ ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1 }
	)
	border:SetAttribute("ThemeStrk", "Strk")
	make("UICorner", box, "Corner", { CornerRadius = UDim.new(0, 3) })
	field = make("TextBox", box, "Value", {
		Text = tostring(static),
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		BackgroundTransparency = 1,
		TextSize = 14,
		FontFace = Chrome.FONT,
		ClearTextOnFocus = false,
		ZIndex = 225,
	})
	field:SetAttribute("ThemeTxt", "Txt")
	local gridToggle = Chrome.menuButton(
		frame,
		"Grid",
		"GRID",
		UDim2.new(1, -76, 0, 36),
		UDim2.fromOffset(66, 26),
		224
	)
	local dockButton, label = Chrome.menuButton(
		frame,
		"Dock",
		"DOCK",
		UDim2.new(1, -150, 0, 36),
		UDim2.fromOffset(66, 26),
		224
	)
	dockLabel = label
	local fit, fitText = Chrome.menuButton(
		frame,
		"Fit",
		fitted and "UNFIT" or "FIT",
		UDim2.new(1, -224, 0, 36),
		UDim2.fromOffset(66, 26),
		224
	)
	fitLabel = fitText
	fit.Activated:Connect(Preview.toggleFit)
	local fullButton = Chrome.menuButton(
		frame,
		"Full",
		"FULL",
		UDim2.new(1, -298, 0, 36),
		UDim2.fromOffset(66, 26),
		224
	)
	fullButton.Activated:Connect(Preview.toggleFull)
	dockButton.Activated:Connect(function()
		Preview.setDocked(not docked)
	end)
	gridButton = gridToggle
	gridToggle.TextLabel.TextSize = 14
	gridToggle.Corner.CornerRadius = UDim.new(0, 3)
	gridToggle:SetAttribute("Selected", grid)
	gridToggle.Activated:Connect(Preview.toggleGrid)
	fov.Activated:Connect(function()
		Preview.setLinked(not linked)
	end)
	local inputField = field
	require("NumericInput").connect(inputField, { step = 1 }, function()
		if window ~= frame then
			return
		end

		if not linked then
			Preview.setStatic(tonumber(inputField.Text) or static)
		end

		inputField.Text = tostring(static)
	end)
	local well = make("Frame", frame, "View", {
		BackgroundColor3 = Color3.fromRGB(5, 9, 11),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 70),
		Size = UDim2.new(1, -16, 1, -78),
		ZIndex = 223,
		ClipsDescendants = true,
	})
	viewport = make("ViewportFrame", well, "Viewport", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 223,
	})
	previewGate = make("Frame", well, "CameraFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 225,
	})
	make("UIStroke", previewGate, "Outline", {
		Color = Color3.fromRGB(235, 232, 217),
		Thickness = 1,
		Transparency = 0.15,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	previewMatte = {}
	for _, name in { "Top", "Bottom", "Left", "Right" } do
		table.insert(
			previewMatte,
			make("Frame", well, "Outside" .. name, {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = maskTransparency(),
				BorderSizePixel = 0,
				ZIndex = 224,
			})
		)
	end

	well:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutView)
	layoutView()
	previewGrid = Preview.grid(previewGate, "Grid", 226)
	empty = make("TextLabel", well, "Empty", {
		Text = "Add a camera to get started!",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = Chrome.FONT,
		TextSize = 14,
		TextWrapped = true,
		ZIndex = 227,
	})
	empty:SetAttribute("ThemeTxt", "Txt")
	local nav = { arrows = {}, buttons = {}, tweens = {}, hover = nil }
	navigation = nav

	local function arrows()
		for _, arrow in nav.arrows do
			if nav.tweens[arrow] then
				nav.tweens[arrow]:Cancel()
			end

			local tween = TweenService:Create(
				arrow,
				TweenInfo.new(0.15),
				{ TextTransparency = nav.hover and 0.1 or 1 }
			)
			nav.tweens[arrow] = tween
			tween:Play()
		end
	end

	local function side(name, right)
		local hit = make("TextButton", well, name, {
			Text = "",
			Position = UDim2.fromScale(right and 0.8 or 0, 0),
			Size = UDim2.fromScale(0.2, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Visible = false,
			ZIndex = 228,
		})
		local arrow = make("TextLabel", hit, "Arrow", {
			Text = right and "\u{203a}" or "\u{2039}",
			BackgroundTransparency = 1,
			Position = UDim2.new(right and 1 or 0, right and -32 or 8, 0.5, -18),
			Size = UDim2.fromOffset(24, 36),
			FontFace = Chrome.FONT,
			TextSize = 30,
			TextTransparency = 1,
			ZIndex = 229,
		})
		arrow:SetAttribute("ThemeTxt", "Txt")
		table.insert(nav.buttons, hit)
		table.insert(nav.arrows, arrow)
		hit.MouseEnter:Connect(function()
			nav.hover = hit
			arrows()
		end)
		hit.MouseLeave:Connect(function()
			if nav.hover == hit then
				nav.hover = nil
				arrows()
			end
		end)
		hit.MouseButton1Click:Connect(function()
			Preview.navigate(right and 1 or -1)
		end)
	end

	side("Previous", false)
	side("Next", true)
	Chrome.bindDrag(frame, drag, {
		clamp = true,
		margin = 8,
		disabled = function()
			return docked or docking
		end,
	})
	Sizeable.attach({
		frame = frame,
		mouse = refs.State.mouse,
		minSize = Vector2.new(460, 230),
		maxSize = Vector2.new(1500, 1000),
		settingKey = "CameraPreviewSize",
	})
	frame.InputBegan:Connect(function(input)
		if docked then
			Visibility.input(input)
		end
	end)
	Theme.addRoot(frame)
	Theme.applyTree(frame)
	if Data.getSetting("CameraPreviewDocked") == true then
		Preview.setDocked(true)
	end

	if window ~= frame then
		return nil
	end

	opening = false
	frame.Visible = true
	if not docked then
		FX.pop(frame)
	end

	refs.State.Timeline:RefreshNavigation()
	updateView()
	return frame
end

function Preview.toggle()
	if Preview.isOpen() then
		Preview.close()
	else
		Preview.open()
	end
end

function Preview.shouldRefresh(dt, playing)
	previewElapsed += math.max(0, dt or 0)
	local changed = previewPlaying ~= playing
	previewPlaying = playing
	local limit = Preferences.get("CameraPreviewFPS")
	if not limit or limit <= 0 then
		previewElapsed = 0
		return true
	end

	local interval = 1 / limit
	if not changed and previewElapsed + 1e-9 < interval then
		return false
	end

	previewElapsed = previewElapsed == math.huge and 0
		or math.max(0, previewElapsed - math.floor((previewElapsed + 1e-9) / interval) * interval)
	return true
end

local function set(object, property, value)
	if object[property] ~= value then
		object[property] = value
	end
end

updateView = function(cameras)
	if
		not window
		or not viewport
		or not Preview.isOpen()
		or refs.State.PresentationHidden
		or docking
	then
		return
	end

	cameras = cameras or Preview.cameras()
	local rig = Preview.target(cameras)
	local accessoryState = accessoryView(rig)
	if accessoryButton then
		accessoryButton:SetAttribute("Selected", accessoryState and accessoryState.hidden or false)
		accessoryButton.Interactable = rig ~= nil
	end

	set(empty, "Visible", rig == nil)
	set(
		empty,
		"Text",
		#cameras == 0 and #Preview.cameras(true) > 0 and "Enable a camera to get started!"
			or "Add a camera to get started!"
	)
	local index, name = table.find(cameras, rig), rig and rig.Name
	if
		titleState.object ~= title
		or titleState.rig ~= rig
		or titleState.name ~= name
		or titleState.index ~= index
		or titleState.count ~= #cameras
	then
		titleState = { object = title, rig = rig, name = name, index = index, count = #cameras }
		set(
			title,
			"Text",
			rig and string.format("CAMERA PREVIEW \u{b7} %s (%d/%d)", name, index, #cameras)
				or "CAMERA PREVIEW"
		)
	end

	for _, button in navigation.buttons do
		set(button, "Visible", #cameras > 1)
	end

	set(viewport, "Visible", rig ~= nil)
	set(previewGate, "Visible", rig ~= nil)
	for _, matte in previewMatte do
		set(matte, "Visible", rig ~= nil)
	end

	set(previewGrid, "Visible", grid and rig ~= nil)
	set(fovLabel, "Text", linked and "\u{2713} FOV" or "FOV")
	set(field, "TextEditable", not linked)
	set(field, "Interactable", not linked)
	set(field, "TextTransparency", linked and 0.65 or 0)
	if linked then
		set(field, "Text", string.format("%.1f", rig and CameraRig.fov(rig) or 70))
	elseif not field:IsFocused() then
		set(field, "Text", tostring(static))
	end

	if rig then
		local green = require("GreenScreen")
		local isolated = green.isEnabled()
		if scene and sceneIsolated ~= isolated then scene.destroy() scene = nil end
		if not scene then
			scene = isolated and green.attachViewport(viewport) or Scene.attach(viewport)
			sceneIsolated = isolated
		end
		viewport.BackgroundTransparency = isolated and 0 or 1
		if isolated then viewport.BackgroundColor3 = green.color() end

		local fov = linked and CameraRig.fov(rig) or static
		local cf, renderFov = CameraRig.renderFrame(rig, fov)
		authoredPreviewFov = renderFov
		scene.setHideAccessories(accessoryState and accessoryState.hidden)
		scene.update(cf, layoutView(), refs.State.getAllRigs())
	elseif scene then
		scene.destroy()
		scene = nil
	end
end

local lifetime = {}
local gridOverlay

function Preview.refresh()
	updateView()
end

function Preview.destroy()
	table.clear(accessoryViews)
	Preview.closeGridSettings()
	for _, connection in widgetConnections do
		connection:Disconnect()
	end

	table.clear(widgetConnections)
	for _, connection in lifetime do
		connection:Disconnect()
	end

	table.clear(lifetime)
	Preview.exitFull()
	Preview.close(true)
	for frame, gui in retiring do
		FX.clear(frame)
		frame:Destroy()
		if typeof(gui) == "Instance" then
			gui:Destroy()
		end
	end

	table.clear(retiring)
	if gridOverlay then
		gridOverlay:Destroy()
		gridOverlay = nil
	end

	if widget then
		DockHost.release(widget)
		widget = nil
	end

	screenGrid = nil
end

function Preview.syncCamera(dt)
	if
		dt
		and refs
		and refs.PlaybackOwnsRefresh
		and window
		and not docking
		and not refs.State.PresentationHidden
		and refs.ScreenGui.Enabled
		and refs.Active()
		and Preview.isOpen()
		and Preview.shouldRefresh(dt, refs.State.Timeline:GetState().Playing == true)
	then
		updateView()
	end

	if not full then
		return
	end

	if
		not full.view.step(
			(linked or refs.State.CameraControls and refs.State.CameraControls.isEditing())
					and CameraRig.fov(full.rig)
				or static
		)
	then
		Preview.exitFull()
	end
end

function Preview.init(options)
	if refs then
		Preview.destroy()
	end

	refs = options
	composition = normalizeComposition(readCompositionSetting("EclipseCompositionGridV1", {}))
	if composition.kind == "Custom Image" and composition.image == "" then
		composition.kind = "Thirds"
	end

	compositionProfiles = {}
	for _, entry in readCompositionSetting("EclipseCompositionPresetsV1", {}) do
		if
			type(entry) == "table"
			and type(entry.name) == "string"
			and #compositionProfiles < 20
		then
			table.insert(
				compositionProfiles,
				{ name = entry.name, config = normalizeComposition(entry.config) }
			)
		end
	end

	viewRotate = ViewRotate.new(refs)
	const unsubscribeMask = Preferences.subscribe(function(key)
		if key ~= "CameraPreviewMaskOpacity" or not previewMatte then
			return
		end

		const transparency = maskTransparency()
		for _, matte in previewMatte do
			FX.setRestingProperty(matte, "BackgroundTransparency", transparency)
		end
	end)
	table.insert(lifetime, { Disconnect = unsubscribeMask })
	table.insert(
		lifetime,
		Input.WindowFocusReleased:Connect(function()
			if viewRotate then
				viewRotate.focusLost()
			end
		end)
	)
	refs.State.CameraPreview = Preview
	linked = Data.getSetting("CameraPreviewLinkedFOV") ~= false
	grid = Data.getSetting("CameraPreviewGrid") == true
	fitted = Data.getSetting("CameraPreviewFit") ~= false
	mainGrid = Data.getSetting("CameraMainGrid") == true
	static = CameraRig.clamp(Data.getSetting("CameraPreviewStaticFOV"))
	local overlay = make(
		"ScreenGui",
		refs.ScreenGui.Parent,
		"EclipseCameraGrid-" .. game.HttpService:GenerateGUID(false),
		{
			IgnoreGuiInset = refs.ScreenGui.IgnoreGuiInset,
			ResetOnSpawn = false,
			DisplayOrder = refs.ScreenGui.DisplayOrder - 1,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}
	)
	gridOverlay = overlay
	local boneHint = make("TextLabel", overlay, "CameraBoneHint", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -14),
		Size = UDim2.fromOffset(350, 22),
		TextSize = 13,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(180, 180, 180),
		TextTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Active = false,
	})
	screenGrid = Preview.grid(overlay, "CameraCompositionGrid", 1)
	screenGrid.Visible = false
	local connection = RunService.RenderStepped:Connect(function(dt)
		local active = refs.Active()
		boneHint.Visible = full ~= nil
			and refs.ScreenGui.Enabled
			and not refs.State.CameraBonesHidden
		if boneHint.Visible then
			local chord = require("Shortcuts").format("TogglePresentation")
			boneHint.Text = chord
				.. (refs.State.CameraBonesHidden and " to show bones" or " to hide bones")
		end

		local cameras
		if full then
			viewRotate.step(full.rig, dt)
			cameras = Preview.cameras()
			local rig = Preview.target(cameras)
			if not refs.ScreenGui.Enabled or not rig then
				Preview.exitFull()
			elseif rig ~= full.rig then
				Preview.select(rig)
			elseif
				not full.view.step(
					(linked or refs.State.CameraControls and refs.State.CameraControls.isEditing())
							and CameraRig.fov(rig)
						or static
				)
			then
				Preview.exitFull()
			end
		end

		if full and refs.State.ScreenEffects then
			refs.State.ScreenEffects.step()
		end

		local hidden = refs.State.PresentationHidden
		set(screenGrid, "Visible", refs.ScreenGui.Enabled and mainGrid and (full ~= nil or active and not hidden))
		if not window or hidden or docking then
			previewElapsed = math.huge
			return
		end

		if not refs.ScreenGui.Enabled then
			Preview.close()
			return
		end

		if refs.PlaybackOwnsRefresh or not active or not Preview.isOpen() then
			return
		end

		if
			Preview.shouldRefresh(
				dt,
				refs.State.Timeline and refs.State.Timeline:GetState().Playing == true
			)
		then
			updateView(cameras)
		end
	end)
	local changed
	if refs.AnimatorFrame then
		changed = refs.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not refs.AnimatorFrame.Visible and not refs.State.PresentationHidden then
				Preview.closeGridSettings()
				Preview.exitFull()
				Preview.close()
				currentCamera, observedSelection = nil, nil
			end
		end)
	end

	table.insert(lifetime, connection)
	if changed then
		table.insert(lifetime, changed)
	end

	table.insert(
		lifetime,
		refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then
				Preview.closeGridSettings()
			end
		end)
	)
	table.insert(lifetime, refs.ScreenGui.Destroying:Once(Preview.destroy))
	if refs.Plugin then
		table.insert(lifetime, refs.Plugin.Unloading:Once(Preview.destroy))
	end
end

return Preview
