--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local DockHost = require("DockHost")
local Chrome = require("Chrome")
local Surface = require("Surface")
local FX = require("WindowFX")
local Theme = require("Theme")
local Tool = {}

function Tool.make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

function Tool.label(parent, name, text, position, size)
	local label = Tool.make("TextLabel", parent, name, {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	label:SetAttribute("ThemeTxt", "Txt")
	return label
end

local function neutralHover(button)
	button.AutoButtonColor = false
	local overlay = Instance.new("Frame")
	overlay.Name = "HoverFill"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 0.93
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Visible = false
	overlay.ZIndex = button.ZIndex + 1
	overlay.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = overlay
	button.MouseEnter:Connect(function()
		overlay.Visible = true
	end)
	button.MouseLeave:Connect(function()
		overlay.Visible = false
		overlay.BackgroundTransparency = 0.93
	end)
	button.MouseButton1Down:Connect(function()
		overlay.BackgroundTransparency = 0.87
	end)
	button.MouseButton1Up:Connect(function()
		overlay.BackgroundTransparency = 0.93
	end)
end

function Tool.button(parent, name, text, position, size, callback)
	local button, label
	if parent:GetAttribute("EclipseTabBar") then
		button = Tool.make("TextButton", parent, name, {
			Text = "",
			Position = position,
			Size = size,
			BackgroundColor3 = Color3.fromRGB(45, 27, 56),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			ZIndex = parent.ZIndex + 3,
		})
		button:SetAttribute("ThemeBg", "TopBtn")
		Tool.make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 4) })
		label = Tool.label(button, "TextLabel", text, UDim2.new(), UDim2.fromScale(1, 1))
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = button.ZIndex + 1
		neutralHover(button)
		Theme.applyTree(button)
	else
		button, label = Chrome.menuButton(parent, name, text, position, size)
	end

	label.TextSize = 12
	label.TextTransparency = 0.1
	if callback then
		button.Activated:Connect(callback)
	end

	return button, label
end

function Tool.headerButton(header, name, text, width, right, callback)
	local height = math.max(20, header.Size.Y.Offset - 8)
	local button, label = Tool.button(header, name, text, UDim2.new(), UDim2.fromOffset(width, height), callback)
	label.TextSize = height > 20 and 14 or 12
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(1, -right - width / 2, 0.5, 0)
	button.ZIndex = header.ZIndex + 5
	label.ZIndex = button.ZIndex + 1
	return button, label
end

function Tool.field(parent, name, text, position, size, numericOptions)
	local shell = Tool.make("Frame", parent, name, {
		Position = position,
		Size = size,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex + 2,
		BackgroundColor3 = Color3.fromRGB(51, 0, 77),
	})
	shell:SetAttribute("ThemeBg", "TopBtn")
	local stroke = Tool.make("UIStroke", shell, "Outline", {
		Color = Color3.fromRGB(69, 41, 93),
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = Enum.BorderStrokePosition.Inner,
		StrokeSizingMode = Enum.StrokeSizingMode.FixedSize,
		ZIndex = 2,
	})
	stroke:SetAttribute("ThemeStrk", "Strk")
	local box = Tool.make("TextBox", shell, "Value", {
		Text = tostring(text),
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(5, 0),
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		ClearTextOnFocus = false,
		ZIndex = shell.ZIndex + 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	box:SetAttribute("ThemeTxt", "Txt")
	if type(text) == "number" then
		require("NumericInput").bind(box, numericOptions or {
			step = (
				name:lower():find("frame")
				or name:lower():find("fps")
				or name:lower():find("duration")
				or name:lower():find("spacing")
				or name:lower():find("stride")
				or name:lower():find("interval")
			)
					and 1
				or 0.1,
		})
	end

	return box
end

function Tool.new(refs, name, title, size, dockable, onClose, options)
    local transient = name == "EclipseLiveSave" or name == "EclipseLiveInvite" or name == "EclipseAbout"
    dockable = dockable == true and (refs.Plugin or require("ProjectData").getPlugin()) ~= nil
    if dockable and not refs.Plugin then refs = table.clone(refs) refs.Plugin = require("ProjectData").getPlugin() end
	local self = { connections = {}, closed = false, busy = false }
	local desiredSize = size
	local saveSize, fitWindow
	local floatingPosition
	local gui = Tool.make("ScreenGui", refs.ScreenGui.Parent, name, {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = refs.ScreenGui.DisplayOrder + 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	gui:SetAttribute("EclipseOwnedUI", true)
	gui:SetAttribute("EclipseToolWindow", true)
	gui:SetAttribute("EclipseToolOwner", refs.ScreenGui:GetAttribute("EclipseInstance"))
	local frame = Tool.make("Frame", gui, "Window", {
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Active = true,
		ZIndex = 10,
	})
	Tool.make("UISizeConstraint", frame, "MinimumSize", { MinSize = options and options.Scrollable and Vector2.new(100, 100) or size })
	Surface.fill(frame)
	local header, _, drag = Chrome.header(frame, title, nil, dockable and 115 or 42)
	local dockText
	self.gui, self.frame = gui, frame
	if options and options.Scrollable then
		local scroll = Tool.make("ScrollingFrame", frame, "Body", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, -3, 0.5, 11),
			Size = UDim2.new(1, -6, 1, -34),
			CanvasSize = UDim2.fromOffset(size.X, size.Y - 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollingDirection = Enum.ScrollingDirection.XY,
			ClipsDescendants = true,
			Active = true,
			ZIndex = frame.ZIndex,
		})
		self.content = Tool.make("Frame", scroll, "Content", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(size.X / 2, size.Y / 2 - 28),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			ZIndex = frame.ZIndex,
		})

		local function fit()
			if self.closed or self.docked then
				return
			end
			local viewport = gui.AbsoluteSize / require("Motion").scale(frame)
			if viewport.X > 0 and viewport.Y > 0 then
				frame.Size = UDim2.fromOffset(math.min(desiredSize.X, math.max(100, viewport.X - 24)), math.min(desiredSize.Y, math.max(100, viewport.Y - 24)))
				frame.Position = require("Motion").constrain(frame, frame.Position)
			end
		end
		table.insert(self.connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
		fitWindow = fit
		if options.Resizable then
			saveSize = require("SizeableWindows").attach({
				frame = frame,
				mouse = refs.State and refs.State.mouse,
				minSize = Vector2.new(240, 180),
				settingKey = name .. "WindowSize",
				onResize = function(width, height)
					desiredSize = Vector2.new(width, height)
					fit()
				end,
			})
		end
		task.defer(fit)
	end
    if not saveSize and not transient then
        saveSize = require("SizeableWindows").attach({
            frame = frame,
            mouse = refs.State and refs.State.mouse,
            minSize = size,
            maxSize = Vector2.new(2494, 1320),
            settingKey = name .. "WindowSize",
            onResize = function(width, height) desiredSize = Vector2.new(width, height) end,
        })
        desiredSize = Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset)
    end
	local root = refs.ScreenGui
	local rootFrame = root:FindFirstChild("Frame", true)
	local components = rootFrame and rootFrame:FindFirstChild("Components")
	local ui = require("UI")
	local animator = ui.EclipseGUI == root and ui.AnimatorFrame or nil
	local mainMenu = options and options.AllowMainMenu and ui.EclipseGUI == root and ui.PrimaryFrame
		or nil
	local alert = components and components:FindFirstChild("Alert")

	local function syncModal()
		if not gui.Parent then
			return
		end

		local enabled = not self.closed
			and root.Enabled
			and root.Parent ~= nil
			and root:GetAttribute("EclipseConfirmationOpen") ~= true
			and not (alert and alert.Visible)
			and (
				not animator
				or (animator.Visible and not animator:GetAttribute("EclipseHUDHidden"))
				or (mainMenu and mainMenu.Visible)
			)
		if gui.Enabled ~= enabled then
			gui.Enabled = enabled
		end
        if self.widget and self.docked then self.widget.Enabled = enabled end
	end

	table.insert(
		self.connections,
		root:GetAttributeChangedSignal("EclipseConfirmationOpen"):Connect(syncModal)
	)
	if alert then
		table.insert(self.connections, alert:GetPropertyChangedSignal("Visible"):Connect(syncModal))
	end

	table.insert(self.connections, root:GetPropertyChangedSignal("Enabled"):Connect(syncModal))
	if animator then
		table.insert(
			self.connections,
			animator:GetPropertyChangedSignal("Visible"):Connect(syncModal)
		)
		table.insert(
			self.connections,
			animator:GetAttributeChangedSignal("EclipseHUDHidden"):Connect(syncModal)
		)
	end

	if mainMenu then
		table.insert(
			self.connections,
			mainMenu:GetPropertyChangedSignal("Visible"):Connect(syncModal)
		)
	end

	syncModal()

	function self:undock()
		self.docked = false
		frame:SetAttribute("EclipseDocked", false)
		frame.Parent = gui
		frame.Size = UDim2.fromOffset(desiredSize.X, desiredSize.Y)
		frame.Position = floatingPosition or UDim2.fromScale(0.5, 0.5)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		if fitWindow then fitWindow() end
		if self.widget then
			self.widget.Enabled = false
		end

		if dockText then
			dockText.Text = "DOCK"
		end
	end

	function self:dock()
		if not dockable or self.busy or self.closed then
			return false
		end

		if self.docked then
			self:undock()
			return
		end

		self.busy = true
		floatingPosition = frame.Position
		if saveSize then saveSize() end
		local ok, err = pcall(function()
			if not self.widget then
				local widget = DockHost.acquire(
					refs.Plugin,
					name,
					DockWidgetPluginGuiInfo.new(
						Enum.InitialDockState.Right,
						true,
						true,
						size.X,
						size.Y,
						options and options.Resizable and 240 or size.X,
						options and options.Resizable and 180 or size.Y
					)
				)
				if self.closed then
					DockHost.release(widget)
					return
				end

				self.widget = widget
				widget.Title = title
				widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				self.canvas = Tool.make("ScrollingFrame", widget, "Content", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollBarThickness = 4,
				})
				widget:BindToClose(function()
					self:close()
				end)
				Theme.addRoot(widget)
				table.insert(
					self.connections,
					widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
						if
							self.docked
							and not self.busy
							and not self.closed
							and widget.Enabled
							and (widget.AbsoluteSize.X <= 0 or widget.AbsoluteSize.Y <= 0)
						then
							self:undock()
						end
					end)
				)
			end

			assert(
				DockHost.show(self.widget, function()
					return not self.closed
				end),
				"Studio could not open the dock"
			)
			FX.clear(frame)
			local scale = frame:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 1
			end

			frame.Parent = self.canvas
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.Size = UDim2.fromScale(1, 1)
			self.docked = true
			frame:SetAttribute("EclipseDocked", true)
			dockText.Text = "UNDOCK"
		end)
		self.busy = false
		if not ok and not self.closed then
			self:undock()
			warn(tostring(err))
		end
	end

	local disposed = false
	local closingFrame
	local lifetime = {}

	local function dispose()
		if disposed then
			return
		end

		disposed = true
		for _, connection in lifetime do
			connection:Disconnect()
		end

		table.clear(lifetime)
		FX.clear(frame)
		if closingFrame then
			FX.clear(closingFrame)
		end

		if self.widget then
			DockHost.release(self.widget)
			self.widget = nil
		end

		gui:Destroy()
	end

	function self:close(immediate)
		if self.closed then
			if immediate then
				dispose()
			end

			return
		end

		if saveSize and not self.docked then saveSize() end
		self.closed = true
		local animate = not immediate
			and not (options and options.AnimateClose == false)
			and not self.docked
			and gui.Enabled
			and gui.Parent ~= nil
		frame.Interactable = false
		for _, object in frame:GetDescendants() do
			if object:IsA("TextBox") and object:IsFocused() then
				object:ReleaseFocus()
			end
		end

		for _, connection in self.connections do
			connection:Disconnect()
		end

		table.clear(self.connections)
		if animate then
			closingFrame = frame:Clone()
			closingFrame.Name = "ClosingWindow"
			local visuals = closingFrame:GetDescendants()
			table.insert(visuals, closingFrame)
			for _, visual in visuals do
				for attribute in visual:GetAttributes() do
					if attribute:sub(1, 5) == "Theme" then
						visual:SetAttribute(attribute, nil)
					end
				end
			end

			closingFrame.Parent = frame.Parent
			FX.clear(frame)
			frame.Visible = false
		end

		local notified, closeError = true, nil
		if onClose then
			notified, closeError = pcall(onClose)
		end

		if not disposed then
			if animate then
				FX.shrink(closingFrame, dispose)
			else
				dispose()
			end
		end

		if not notified then
			warn("[Eclipse] Tool close: " .. tostring(closeError))
		end
	end

	table.insert(
		lifetime,
		root.Destroying:Connect(function()
			self:close(true)
		end)
	)
	table.insert(
		lifetime,
		gui.Destroying:Connect(function()
			self:close(true)
		end)
	)
	table.insert(
		lifetime,
		root:GetPropertyChangedSignal("Enabled"):Connect(function()
			if self.closed and not root.Enabled then
				dispose()
			end
		end)
	)
	const host = refs.Plugin or require("ProjectData").getPlugin()
	if host and host.Unloading then
		table.insert(
			lifetime,
			host.Unloading:Connect(function()
				self:close(true)
			end)
		)
	end

	Chrome.close(header, function()
		self:close()
	end)
	if dockable then
		local button
		button, dockText = Tool.headerButton(
			header,
			"Dock",
			"DOCK",
			64,
			36,

			function()
				self:dock()
			end
		)
	end

	Chrome.bindDrag(frame, drag, {
		clamp = true,
		disabled = function()
			return self.closed or self.docked or self.busy
		end,
	})
	require("Motion").watchFloatingGui(gui)
	Theme.addRoot(gui)
	task.defer(function()
		if not self.closed then
			if options and options.BeforeOpen then options.BeforeOpen(frame, gui) end
			Theme.applyTree(frame)
			FX.pop(frame)
		end
	end)
	return self
end

function Tool.attachPopup(frame, header, refs, name, title, size, close, right)
    local plugin = refs.Plugin or require("ProjectData").getPlugin()
    local parent = frame.Parent or refs.ScreenGui
    local root = refs.ScreenGui
    local widget, docked, busy, dead = nil, false, false, false
    local position, floatingSize = frame.Position, frame.Size
    local minimum = Instance.new("UISizeConstraint")
    minimum.MinSize = size
    minimum.Parent = frame
    local save = require("SizeableWindows").attach({
        frame = frame, minSize = size, settingKey = name .. "WindowSize",
        onResize = function() floatingSize = frame.Size end,
    })
    floatingSize = frame.Size
    local button, label = Tool.headerButton(header, "Dock", "DOCK", 64, (right or 100) - 64)
    button.Visible = plugin ~= nil
    local connections = {}
    local function undock()
        docked = false
        frame:SetAttribute("EclipseDocked", false)
        frame.Parent = parent
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Position, frame.Size = position, floatingSize
        if widget then widget.Enabled = false end
        label.Text = "DOCK"
    end
    button.Activated:Connect(function()
        if dead or busy then return end
        if docked then undock() return end
        busy = true
        local ok, issue = pcall(function()
            position, floatingSize = frame.Position, frame.Size
            save()
            if not widget then
                widget = DockHost.acquire(plugin, name, DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, true, size.X, size.Y, size.X, size.Y))
                if dead then DockHost.release(widget) widget = nil return end
                widget.Title = title
                widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                widget:BindToClose(close)
                Theme.addRoot(widget)
            end
            assert(DockHost.show(widget, function() return not dead end), "Studio could not open the dock")
            FX.clear(frame)
            local scale = frame:FindFirstChildOfClass("UIScale")
            if scale then scale.Scale = 1 end
            frame.Parent = widget
            frame.AnchorPoint = Vector2.new(0.5, 0.5)
            frame.Position, frame.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
            frame:SetAttribute("EclipseDocked", true)
            docked = true
            label.Text = "UNDOCK"
        end)
        busy = false
        if not ok and not dead then undock() warn(issue) end
    end)
    local function sync()
        if widget and docked then widget.Enabled = root.Enabled and not root:GetAttribute("EclipseConfirmationOpen") end
    end
    table.insert(connections, root:GetPropertyChangedSignal("Enabled"):Connect(sync))
    table.insert(connections, root:GetAttributeChangedSignal("EclipseConfirmationOpen"):Connect(sync))
    table.insert(connections, root.Destroying:Connect(function() frame:Destroy() end))
    frame.Destroying:Once(function()
        dead = true
        for _, connection in connections do connection:Disconnect() end
        if widget then local old = widget widget = nil task.defer(DockHost.release, old) end
    end)
    return { isDocked = function() return docked end, undock = undock }
end

return Tool
