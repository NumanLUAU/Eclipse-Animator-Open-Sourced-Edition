--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local DockHost = require("DockHost")
local Motion = require("Motion")
local Chrome = require("Chrome")
local Theme = require("Theme")
local Preferences = require("Preferences")
local PreferencesEditor = require("PreferencesEditor")
local Library = require("ImageLibrary")
local Upload = require("Upload")
local WindowFX = require("WindowFX")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local AssetService = game:GetService("AssetService")
local Previewer = {}
local refs, session = {}, nil
local lifetime = {}
local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local DEFAULT_SIZE = Vector2.new(560, 360)
local HEADER, INSET = Chrome.HEIGHT, 12
local DOCK_SETTING = "EclipseAnimator_ImagePreviewerDocked"

local function make(class, parent, name, props)
	local object = Instance.new(class)

	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function corner(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius) })
end

local function surface(object, key)
	object.BorderSizePixel = 0
	object:SetAttribute("ThemeBg", key)
	corner(object, 5)
end

local function button(parent, name, label, pos, size)
	local object = make("TextButton", parent, name, {
		Text = label,
		Position = pos,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(40, 28, 50),
		TextColor3 = Color3.fromRGB(235, 228, 242),
		FontFace = FONT,
		TextSize = 12,
		AutoButtonColor = true,
		ZIndex = 212,
	})
	surface(object, "TopBtn")
	object:SetAttribute("ThemeTxt", "TopT")
	return object
end

local function text(parent, name, label, pos, size, fontSize)
	local object = make("TextLabel", parent, name, {
		Text = label,
		Position = pos,
		Size = size,
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		FontFace = FONT,
		TextSize = fontSize or 12,
		ZIndex = 211,
	})
	object:SetAttribute("ThemeTxt", "Txt")
	return object
end

local function connect(list, signal, callback)
	local c = signal:Connect(callback)
	table.insert(list, c)
	return c
end

local function rootScale()
	if session and session.docked then
		return 1
	end

	local scale = refs.ScreenGui and refs.ScreenGui:FindFirstChildOfClass("UIScale")
	return scale and scale.Scale or 1
end

local function viewport()
	return workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
end

local function refreshToggle()
	local timeline = refs.State and refs.State.Timeline
	if timeline and timeline.RefreshNavigation then
		timeline:RefreshNavigation()
	end
end

function Previewer.isOpen()
	return session ~= nil and not session.closing
end

function Previewer.hasFocus()
	if not Previewer.isOpen() or not refs.ScreenGui.Enabled then
		return false
	end

	local preferences = refs.ScreenGui:FindFirstChild("PreferencesEditor")
	if preferences and preferences.Visible then
		return false
	end

	if session.docked then
		return session.widgetFocused == true
	end

	local p, z = session.window.AbsolutePosition, session.window.AbsoluteSize
	local m = Input:GetMouseLocation()
	return m.X >= p.X and m.Y >= p.Y and m.X <= p.X + z.X and m.Y <= p.Y + z.Y
end

function Previewer.geometry(size, available, scale, native)
	local limit =
		Vector2.new(math.max(1, available.X / scale - 24), math.max(1, available.Y / scale - 24))
	local dimensions = DEFAULT_SIZE
	if native and size and size.X > 0 and size.Y > 0 then
		local area = (DEFAULT_SIZE.X - INSET * 2) * (DEFAULT_SIZE.Y - HEADER - INSET * 2)
		local width = math.sqrt(area * size.X / size.Y)
		local height = area / width
		local fit = math.min(1, 616 / width, 448 / height)
		dimensions = Vector2.new(
			math.max(420, width * fit + INSET * 2),
			math.max(220, height * fit + HEADER + INSET * 2)
		)
	end

	dimensions = dimensions:Min(limit)
	return dimensions,
		Vector2.new(
			math.max(1, dimensions.X - INSET * 2),
			math.max(1, dimensions.Y - HEADER - INSET * 2)
		)
end

local function clampPosition(s)
	if s.docked then
		return
	end

	local area = viewport() / rootScale()
	local size = s.window.Size
	local half = Vector2.new(size.X.Offset, size.Y.Offset) * 0.5
	local pos = s.window.Position
	local center =
		Vector2.new(pos.X.Scale * area.X + pos.X.Offset, pos.Y.Scale * area.Y + pos.Y.Offset)
	s.window.Position = UDim2.fromOffset(
		math.clamp(center.X, half.X + 8, math.max(half.X + 8, area.X - half.X - 8)),
		math.clamp(center.Y, half.Y + 8, math.max(half.Y + 8, area.Y - half.Y - 8))
	)
end

local function layout(s, automatic)
	if session ~= s or s.closing then
		return
	end

	if not s.docked and automatic then
		local native = s.index ~= nil and Preferences.get("ImagePreviewerNativeImageScale")
		local dimensions = Previewer.geometry(s.sourceSize, viewport(), rootScale(), native)
		s.window.Size = UDim2.fromOffset(math.round(dimensions.X), math.round(dimensions.Y))
	end

	s.picture.Size = UDim2.new(1, -INSET * 2 + 8, 1, -INSET * 2 + 4)
	if s.fitThumbnails then
		s.fitThumbnails()
	end

	clampPosition(s)
end

local function arrows(s, visible)
	for _, arrow in { s.leftArrow, s.rightArrow } do
		if s.arrowTweens[arrow] then
			s.arrowTweens[arrow]:Cancel()
		end

		local tween = TweenService:Create(
			arrow,
			TweenInfo.new(0.15),
			{ TextTransparency = visible and 0.1 or 1 }
		)
		s.arrowTweens[arrow] = tween
		tween:Play()
	end
end

function Previewer.gallery()
	local s = session
	if not s or s.closing then
		return
	end

	s.generation += 1
	s.index = nil
	s.sourceSize = nil
	s.hoverSide = nil
	s.gallery.Visible = true
	s.preview.Visible = false
	s.back.Visible = false
	s.title.Size = UDim2.new(1, -210, 1, 0)
	s.drag.Size = s.title.Size
	arrows(s, false)
	layout(s, true)
end

function Previewer.select(index)
	local s = session
	if not s or s.closing then
		return
	end

	local entry = s.images[index]
	if not entry then
		Previewer.gallery()
		return
	end

	s.generation += 1
	local generation = s.generation
	s.index = index
	s.gallery.Visible = false
	s.preview.Visible = true
	s.back.Visible = true
	s.title.Size = UDim2.new(1, -238, 1, 0)
	s.drag.Size = s.title.Size
	s.picture.Image = entry.id
	s.sourceSize = entry.width and entry.height and Vector2.new(entry.width, entry.height) or nil
	arrows(s, s.hoverSide ~= nil)
	layout(s, true)
	if not s.sourceSize then
		task.spawn(function()
			local ok, editable = pcall(
				AssetService.CreateEditableImageAsync,
				AssetService,
				Content.fromUri(entry.id)
			)
			if not ok or not editable then
				return
			end

			local size = editable.Size
			editable:Destroy()
			entry.width, entry.height = size.X, size.Y
			if session == s and s.generation == generation then
				s.sourceSize = size
				layout(s, true)
			end
		end)
	end
end

function Previewer.navigate(direction)
	if session and session.index then
		Previewer.select(session.index + direction)
	end
end

local function rebuildGallery(s)
	local selected = s.index and s.images[s.index] and s.images[s.index].id
	s.images = Library.recent()
	for _, child in s.recent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for i, entry in s.images do
		local row = button(s.recent, "Recent" .. i, "", UDim2.new(), UDim2.fromOffset(86, 62))
		row.LayoutOrder = i
		local thumbnail = make("ImageLabel", row, "Thumbnail", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			Image = entry.id,
			ScaleType = Enum.ScaleType.Fit,
			BackgroundTransparency = 1,
			ZIndex = 213,
		})
		row.MouseButton1Click:Connect(function()
			Previewer.select(i)
		end)
		Theme.applyInstance(row)
		Theme.applyInstance(thumbnail)
	end

	s.empty.Visible = #s.images == 0
	if selected then
		for i, entry in s.images do
			if entry.id == selected then
				s.index = i
				return
			end
		end

		Previewer.gallery()
	end
end

function Previewer.upload()
	local s = session
	if not s or s.uploading or s.closing then
		return
	end

	s.uploading = true
	s.upload.Interactable = false
	s.status.Text = "Choose an image to upload."
	local id, err = Upload.prompt()
	if session ~= s or s.closing then
		return
	end

	s.uploading = false
	s.upload.Interactable = true
	s.status.Text = err or ""
	if id then
		rebuildGallery(s)
		for i, entry in s.images do
			if entry.id == id then
				Previewer.select(i)
				break
			end
		end
	end
end

local function dispose(s)
	if s.disposed then
		return
	end

	s.disposed = true
	if s.widget then
		s.widget.Enabled = false
	end

	for _, c in s.connections do
		c:Disconnect()
	end

	if s.unsubscribe then
		s.unsubscribe()
	end

	for _, t in s.arrowTweens do
		t:Cancel()
	end

	WindowFX.clear(s.window)
	if session == s then
		session = nil
	end

	if s.window.Parent then
		s.window:Destroy()
	end

	if s.widget then
		DockHost.release(s.widget)
		s.widget = nil
	end

	refreshToggle()
end

function Previewer.close()
	local s = session
	if not s or s.closing then
		return
	end

	s.closing = true
	s.generation += 1
	refreshToggle()
	if s.docked then
		dispose(s)
		return
	end

	WindowFX.shrink(s.window, function()
		dispose(s)
	end)
end

local function dotted(s)
	local border = make("Frame", s.window, "DottedBorder", {
		Position = UDim2.fromOffset(9, HEADER + 5),
		Size = UDim2.new(1, -18, 1, -HEADER - 14),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 218,
	})
	local lastSize

	local function paint()
		local fx = s.window:FindFirstChild("EclipseWindowScale")
		local size = border.AbsoluteSize / (rootScale() * (fx and fx.Scale or 1))
		local w, h = math.round(size.X), math.round(size.Y)
		if lastSize == Vector2.new(w, h) then
			return
		end

		lastSize = Vector2.new(w, h)
		for _, child in border:GetChildren() do
			child:Destroy()
		end

		local function dot(x, y, width, height)
			local p = make("Frame", border, "Dot", {
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(width, height),
				BackgroundColor3 = Theme.get("Strk", Color3.new(1, 1, 1)),
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				ZIndex = 218,
			})
			p:SetAttribute("ThemeBg", "Strk")
		end

		for x = 0, w - 3, 10 do
			dot(x, 0, 3, 1)
			dot(x, h - 1, 3, 1)
		end

		for y = 6, h - 3, 10 do
			dot(0, y, 1, 3)
			dot(w - 1, y, 1, 3)
		end
	end

	connect(s.connections, border:GetPropertyChangedSignal("AbsoluteSize"), paint)
	task.defer(paint)
end

function Previewer.presentationWidget()
	return session and session.widget
end

function Previewer.isDocked()
	return session and session.docked == true or false
end

function Previewer.setDocked(docked, restoring)
	local s = session
	if not s or s.closing or s.docking or s.docked == docked then
		return false
	end

	if docked and not s.widget then
		if not refs.Plugin then
			s.status.Text = "Docking is available when Eclipse runs as a plugin."
			return false
		end

		s.docking = true
		local ok, widget = pcall(function()
			return DockHost.acquire(
				refs.Plugin,
				"EclipseAnimatorImagePreviewer",
				DockWidgetPluginGuiInfo.new(
					Enum.InitialDockState.Right,
					false,
					true,
					560,
					360,
					420,
					260
				)
			)
		end)
		s.docking = false
		if not ok then
			s.status.Text = "Unable to dock the previewer."
			return false
		end

		if session ~= s or s.closing then
			DockHost.release(widget)
			return false
		end

		s.widget = widget
		widget.Title = "Eclipse Image Previewer"
		widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		widget:BindToClose(Previewer.close)
		connect(s.connections, widget.WindowFocused, function()
			s.widgetFocused = true
		end)
		connect(s.connections, widget.WindowFocusReleased, function()
			s.widgetFocused = false
		end)
	end

	s.docking = true
	if
		docked
		and not DockHost.show(s.widget, function()
			return session == s and not s.closing
		end)
	then
		s.docking = false
		if session == s and not s.closing then
			s.widget.Enabled = false
			s.status.Text = "Dock unavailable. Preview remains floating."
		end

		return false
	end

	WindowFX.clear(s.window)
	local fx = s.window:FindFirstChild("EclipseWindowScale")
	if fx then
		fx.Scale = 1
	end

	s.resizing = nil
	s.docked = docked
	if docked then
		s.floating = { position = s.window.Position, size = s.window.Size }
		s.window.Parent = s.widget
		s.window.Position = UDim2.fromScale(0.5, 0.5)
		s.window.Size = UDim2.fromScale(1, 1)
		s.widget.Enabled = true
	else
		s.window.Parent = refs.ScreenGui
		s.window.Position = s.floating.position
		s.window.Size = s.floating.size
		s.widget.Enabled = false
		s.widgetFocused = false
	end

	s.dockLabel.Text = docked and "UNDOCK" or "DOCK"
	for _, grip in s.grips do
		grip.Visible = not docked
	end

	if refs.Plugin and not restoring then
		pcall(function()
			refs.Plugin:SetSetting(DOCK_SETTING, docked)
		end)
	end

	s.docking = false
	layout(s, false)
	return true
end

local function resizing(s)
	s.grips = {}
	for _, edge in
		{
			Vector2.new(-1, 0),
			Vector2.new(1, 0),
			Vector2.new(0, -1),
			Vector2.new(0, 1),
			Vector2.new(-1, -1),
			Vector2.new(1, -1),
			Vector2.new(-1, 1),
			Vector2.new(1, 1),
		}
	do
		local both = edge.X ~= 0 and edge.Y ~= 0
		local grip = make("TextButton", s.window, "Resize_" .. edge.X .. "_" .. edge.Y, {
			Text = "",
			Position = UDim2.fromScale((edge.X + 1) * 0.5, (edge.Y + 1) * 0.5),
			AnchorPoint = Vector2.new((edge.X + 1) * 0.5, (edge.Y + 1) * 0.5),
			Size = both and UDim2.fromOffset(9, 9)
				or edge.X == 0 and UDim2.new(1, -18, 0, 5)
				or UDim2.new(0, 5, 1, -18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			ZIndex = both and 221 or 220,
		})
		table.insert(s.grips, grip)
		connect(s.connections, grip.InputBegan, function(input)
			if
				s.docked
				or s.closing
				or (
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				)
			then
				return
			end

			s.resizing = {
				input = input,
				edge = edge,
				start = Vector2.new(input.Position.X, input.Position.Y),
				position = s.window.Position,
				size = s.window.Size,
				scale = rootScale(),
			}
			local d = s.resizing
			Motion.begin(s.window, input, function(point)
				local delta = (Vector2.new(point.X, point.Y) - d.start) / d.scale
				local available = viewport() / d.scale - Vector2.new(16, 16)
				local w = d.edge.X == 0 and d.size.X.Offset
					or math.clamp(
						d.size.X.Offset + delta.X * d.edge.X,
						math.min(420, available.X),
						available.X
					)
				local h = d.edge.Y == 0 and d.size.Y.Offset
					or math.clamp(
						d.size.Y.Offset + delta.Y * d.edge.Y,
						math.min(260, available.Y),
						available.Y
					)
				s.window.Size = UDim2.fromOffset(w, h)
				s.window.Position = d.position
					+ UDim2.fromOffset(
						(w - d.size.X.Offset) * d.edge.X * 0.5,
						(h - d.size.Y.Offset) * d.edge.Y * 0.5
					)
				layout(s, false)
			end, function()
				s.resizing = nil
			end, "resize")
		end)
	end
end

function Previewer.open()
	if session and session.closing then
		dispose(session)
	end

	if session then
		local active = session
		if
			active.docked
			and not DockHost.show(active.widget, function()
				return session == active and not active.closing
			end)
			and session == active
		then
			Previewer.setDocked(false, true)
		end

		return session == active and active.window or nil
	end

	if not refs.ScreenGui then
		return
	end

	local window = make("Frame", refs.ScreenGui, "ImagePreviewer", {
		Size = UDim2.fromOffset(DEFAULT_SIZE.X, DEFAULT_SIZE.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 12, 28),
		Active = true,
		ZIndex = 210,
	})
	surface(window, "Bg")
	local s = { window = window, connections = {}, arrowTweens = {}, images = {}, generation = 0 }
	session = s
	local header, title, drag = Chrome.header(window, "IMAGE PREVIEWER", 211, 210)
	s.title = title
	s.drag = drag
	local close = Chrome.close(header, nil, 215)
	local settings = Chrome.menuButton(
		header,
		"Settings",
		"SETTINGS",
		UDim2.new(1, -116, 0, 4),
		UDim2.fromOffset(78, 20),
		215
	)
	s.dock, s.dockLabel = Chrome.menuButton(
		header,
		"Dock",
		"DOCK",
		UDim2.new(1, -186, 0, 4),
		UDim2.fromOffset(62, 20),
		215
	)
	s.back = Chrome.menuButton(
		header,
		"Back",
		"←",
		UDim2.new(1, -214, 0, 4),
		UDim2.fromOffset(22, 20),
		215
	)
	connect(s.connections, s.dock.Activated, function()
		Previewer.setDocked(not s.docked)
	end)

	s.gallery = make("Frame", window, "Gallery", {
		Position = UDim2.fromOffset(4, HEADER),
		Size = UDim2.new(1, -8, 1, -HEADER - 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 211,
	})
	surface(s.gallery, "Bg")
	s.gallery:SetAttribute("ThemeBgImage", 1)
	s.upload = button(
		s.gallery,
		"Upload",
		"     UPLOAD IMAGE",
		UDim2.new(0.5, -83, 0, 26),
		UDim2.fromOffset(166, 34)
	)
	local uploadIcon = make("ImageLabel", s.upload, "Icon", {
		Image = Chrome.UPLOAD_ICON,
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		ZIndex = 213,
	})
	uploadIcon:SetAttribute("ThemeImg", "Txt")
	text(
		s.gallery,
		"RecentTitle",
		"RECENT UPLOADS",
		UDim2.new(0, 12, 0, 78),
		UDim2.new(1, -24, 0, 20),
		11
	).TextTransparency =
		0.35
	s.recent = make("Frame", s.gallery, "RecentImages", {
		Position = UDim2.fromOffset(12, 108),
		Size = UDim2.new(1, -24, 1, -138),
		BackgroundTransparency = 1,
		ZIndex = 212,
	})
	make("UIGridLayout", s.recent, "Grid", {
		CellSize = UDim2.new(0.2, -8, 0, 62),
		CellPadding = UDim2.fromOffset(9, 9),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		FillDirectionMaxCells = 5,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local function fitThumbnails()
		local fx = window:FindFirstChild("EclipseWindowScale")
		local windowHeight = s.docked and window.AbsoluteSize.Y / (fx and fx.Scale or 1)
			or window.Size.Y.Offset
		local height = windowHeight - HEADER - 4 - 138
		s.recent.Grid.CellSize =
			UDim2.new(0.2, -8, 0, math.clamp(math.floor((height - 9) * 0.5), 28, 62))
	end

	s.fitThumbnails = fitThumbnails
	connect(s.connections, window:GetPropertyChangedSignal("Size"), fitThumbnails)
	connect(s.connections, s.recent:GetPropertyChangedSignal("AbsoluteSize"), fitThumbnails)
	s.empty = text(
		s.recent,
		"Empty",
		"Your last 10 uploads will appear here.",
		UDim2.new(0, 0, 0, 12),
		UDim2.new(1, 0, 0, 30),
		12
	)
	s.empty.Parent = s.gallery
	s.empty.Position = UDim2.new(0, 12, 0, 136)
	s.empty.Size = UDim2.new(1, -24, 0, 30)
	s.empty.TextTransparency = 0.35
	s.status = text(s.gallery, "Status", "", UDim2.new(0, 12, 1, -27), UDim2.new(1, -24, 0, 20), 11)
	s.preview = make("Frame", window, "Preview", {
		Position = UDim2.fromOffset(4, HEADER),
		Size = UDim2.new(1, -8, 1, -HEADER - 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 211,
	})
	surface(s.preview, "Bg")
	s.picture = make("ImageLabel", s.preview, "Image", {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Image = "",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 212,
	})

	local function side(name, right)
		local hit = button(
			s.preview,
			name,
			"",
			UDim2.fromScale(right and 0.8 or 0, 0),
			UDim2.fromScale(0.2, 1)
		)
		hit.BackgroundTransparency = 1
		local arrow = text(
			hit,
			"Arrow",
			right and "›" or "‹",
			UDim2.new(right and 1 or 0, right and -32 or 8, 0.5, -18),
			UDim2.fromOffset(24, 36),
			30
		)
		arrow.TextTransparency = 1
		arrow.ZIndex = 214
		connect(s.connections, hit.MouseEnter, function()
			s.hoverSide = hit
			arrows(s, true)
		end)
		connect(s.connections, hit.MouseLeave, function()
			if s.hoverSide == hit then
				s.hoverSide = nil
				arrows(s, false)
			end
		end)
		connect(s.connections, hit.MouseButton1Click, function()
			Previewer.navigate(right and 1 or -1)
		end)
		return arrow
	end

	s.leftArrow = side("Previous", false)
	s.rightArrow = side("Next", true)
	connect(s.connections, close.Activated, Previewer.close)
	connect(s.connections, s.back.MouseButton1Click, Previewer.gallery)
	connect(
		s.connections,
		settings.MouseButton1Click,
		PreferencesEditor.openImagePreviewerPreferences
	)
	connect(s.connections, s.upload.MouseButton1Click, Previewer.upload)
	Chrome.bindDrag(window, drag, {
		disabled = function()
			return s.docked or s.closing
		end,
		clamp = true,
		margin = 8,
	})
	resizing(s)

	local function keyboard(input)
		if not Previewer.hasFocus() or Input:GetFocusedTextBox() then
			return
		end

		if Shortcuts.matches("PreviousImage", input) then
			Previewer.navigate(-1)
		elseif Shortcuts.matches("NextImage", input) then
			Previewer.navigate(1)
		end
	end

	connect(s.connections, Input.InputBegan, function(input)
		if not s.docked then
			keyboard(input)
		end
	end)
	connect(s.connections, window.InputBegan, function(input)
		if s.docked then
			keyboard(input)
		end
	end)

	s.unsubscribe = Library.subscribe(function()
		if session == s and not s.closing then
			rebuildGallery(s)
		end
	end)
	dotted(s)
	rebuildGallery(s)
	Previewer.gallery()
	Theme.applyInstance(window)
	for _, object in window:GetDescendants() do
		Theme.applyInstance(object)
	end

	Theme.addRoot(window)
	WindowFX.pop(window)
	refreshToggle()
	if refs.Plugin then
		local ok, saved = pcall(function()
			return refs.Plugin:GetSetting(DOCK_SETTING)
		end)
		if ok and saved then
			Previewer.setDocked(true, true)
		end
	end

	return window
end

function Previewer.toggle()
	if Previewer.isOpen() then
		Previewer.close()
	else
		return Previewer.open()
	end
end

function Previewer.destroy()
	if session then
		dispose(session)
	end

	for _, c in lifetime do
		c:Disconnect()
	end

	table.clear(lifetime)
	if refs.unsubscribe then
		refs.unsubscribe()
	end

	if refs.State then
		refs.State.ImagePreviewer = nil
	end

	refs = {}
end

function Previewer.init(options)
	Previewer.destroy()
	refs = options
	refs.State.ImagePreviewer = Previewer
	refs.unsubscribe = Preferences.subscribe(function(key)
		if key == "ImagePreviewerNativeImageScale" and session then
			layout(session, true)
		end
	end)
	connect(lifetime, refs.ScreenGui:GetPropertyChangedSignal("Enabled"), function()
		if not refs.ScreenGui.Enabled then
			Previewer.close()
		end
	end)
	connect(lifetime, refs.AnimatorFrame:GetPropertyChangedSignal("Visible"), function()
		if not refs.AnimatorFrame.Visible then
			Previewer.close()
		end
	end)
	connect(lifetime, refs.ScreenGui.Destroying, Previewer.destroy)
end

return Previewer
