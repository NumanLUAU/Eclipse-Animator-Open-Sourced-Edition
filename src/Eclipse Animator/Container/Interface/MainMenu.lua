--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local WindowFX = require("WindowFX")
local Theme = require("Theme")

local MainMenu = {}

local function make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function round(object, radius)
	local corner = object:FindFirstChildOfClass("UICorner")
		or make("UICorner", object, "Corner", {})
	corner.CornerRadius = UDim.new(0, radius)
end

local function surface(object, key, color)
	object.BackgroundTransparency = 0
	object.BackgroundColor3 = color
	object.BorderSizePixel = 0
	object:SetAttribute("ThemeBg", key)
	round(object, 4)
	local stroke = object:FindFirstChildOfClass("UIStroke")
		or make("UIStroke", object, "Outline", {})
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	stroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	stroke.Thickness = 1
	stroke.Transparency = 0
	stroke.Color = Theme.panelOutlineDefault()
	stroke:SetAttribute("ThemeStrk", "Strk")
end

local function windowBackground(panel, window)
	surface(panel, "Bg", Color3.new(1, 1, 1))
	panel:SetAttribute("ThemeBgImage", nil)
	local gradient = window:FindFirstChildOfClass("UIGradient"):Clone()
	gradient.Name = "WindowBackground"
	gradient:SetAttribute("ThemeGrad", "Bg")
	gradient.Parent = panel
end

local function halftone(panel)
	local accent = make("Frame", panel, "CornerHalftone", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		Size = UDim2.fromOffset(119, 114),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
	})
	for y = 0, 7 do
		for x = 0, 7 do
			if x + y < 7 then
				continue
			end

			local strength = (x + y - 6) / 8
			local diameter = 1.5 + strength * 2.5
			local dot = make("Frame", accent, "Dot", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(7 + x * 15, 7 + y * 14),
				Size = UDim2.fromOffset(diameter, diameter),
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.fromRGB(190, 142, 224),
				BackgroundTransparency = 0.98 - strength * 0.22,
				Active = false,
				ZIndex = 1,
			})
			dot:SetAttribute("ThemeBg", "Txt")
			round(dot, 8)
		end
	end
end

local function textStyle(label, font, size)
	label.FontFace = font
	label.TextScaled = false
	label.TextSize = size
	label.TextColor3 = Color3.fromRGB(231, 224, 239)
	label.BackgroundTransparency = 1
	label:SetAttribute("ThemeTxt", "Txt")
end

local function divider(parent, y)
	local line = make("Frame", parent, "Divider", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.panelOutlineDefault(),
		BorderSizePixel = 0,
	})
	line:SetAttribute("ThemeBg", "Div")
	return line
end

function MainMenu.bindPreferencesTip(UI)
	local Data = require("ProjectData")
	local Notification = require("Notification")
	local setting = "EclipseAnimator_PreferencesTipSeen_v1"
	local shown = false
	local ok, seen = pcall(Data.getSetting, setting)
	if ok and seen == true then
		return
	end

	local connections = {}

	local function show()
		if shown or not UI.EclipseGUI.Enabled or not UI.PrimaryFrame.Visible then
			return
		end

		local notice = Notification.show(
			"WELCOME TO ECLIPSE",
			"Be sure to check Settings > Preferences before animating. These settings are important for choosing how Eclipse works for you.",
			12
		)
		if not notice then
			return
		end

		shown = true
		pcall(Data.setSetting, setting, true)
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	table.insert(connections, UI.EclipseGUI:GetPropertyChangedSignal("Enabled"):Connect(show))
	table.insert(connections, UI.PrimaryFrame:GetPropertyChangedSignal("Visible"):Connect(show))
	UI.EclipseGUI.Destroying:Once(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	show()
end

function MainMenu.updateSelection(UI, selected, count)
	count = count or (selected and 1 or 0)
	local center = UI.MainFrame.Center
	center.Label1.Text = count > 1 and (tostring(count) .. " RIGS SELECTED")
		or selected and selected.Name
		or "SELECT RIGS IN EXPLORER"
	center.Label2.Text = count > 1 and "PREVIEW TOGETHER"
		or selected and "SELECTED"
		or "TO BEGIN ANIMATING"

	center.Label1.TextColor3 = Color3.fromRGB(231, 224, 239)
	center.Label2.TextColor3 = Color3.fromRGB(231, 224, 239)
	center.Label2.TextTransparency = 0.35
	Theme.applyInstance(center.Label1)
	Theme.applyInstance(center.Label2)
	local button = center.ProjectCreator
	button:SetAttribute("HasSelection", selected ~= nil)
	button.Interactable = selected ~= nil
	button.Active = selected ~= nil
	button.AutoButtonColor = selected ~= nil
	button.Title.Text = count > 1 and "NEW PROJECT" or "NEW ANIMATION"
	WindowFX.setRestingProperty(button.Title, "TextTransparency", selected and 0 or 0.6)
	WindowFX.setRestingProperty(button, "BackgroundTransparency", selected and 0 or 0.5)
	WindowFX.setRestingProperty(
		button:FindFirstChildOfClass("UIStroke"),
		"Transparency",
		selected and 0 or 0.5
	)
end

function MainMenu.attach(UI)
	local fontSource = UI.RigItemTemplate:FindFirstChild("Title", true)
	local font = fontSource and fontSource.FontFace
		or Font.new("rbxasset://fonts/families/RobotoMono.json")

	for _, glow in UI.EclipseGUI:GetDescendants() do
		if glow:IsA("ImageLabel") and glow.Name == "Glow" and glow.Parent:IsA("GuiButton") then
			local button = glow.Parent
			glow:Destroy()
			surface(button, button:GetAttribute("ThemeBg") or "TopBtn", Color3.fromRGB(45, 27, 56))
			button.AutoButtonColor = true
			local title = button:FindFirstChild("Title")
			if title then
				textStyle(title, font, 14)
				title.AnchorPoint = Vector2.zero
				title.Position = UDim2.fromOffset(8, 0)
				title.Size = UDim2.new(1, -16, 1, 0)
			end
		end
	end

	local themes = UI.FramesFolder:FindFirstChild("Themes")
	if themes then
		themes:Destroy()
	end

	local themeButton = UI.MenuButtons:FindFirstChild("ThemeButton")
	if themeButton then
		themeButton.Name = "SettingsButton"
		themeButton.TextLabel.Text = "SETTINGS"
	end

	for _, button in UI.MenuButtons:GetChildren() do
		if button:IsA("GuiButton") and button.Name ~= "SettingsButton" then
			button:Destroy()
		end
	end

	local main = UI.MainFrame
	local mainSurface = UI.PrimaryFrame:FindFirstChild("MainSurface", true)
	if mainSurface then
		mainSurface:SetAttribute("ThemeBgImage", nil)
	end

	local layout = main:FindFirstChildOfClass("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 6)
	local padding = main:FindFirstChildOfClass("UIPadding")
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 4), UDim.new(0, 6)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)

	local function listPanel(panel, order, icon, labelName, emptyText)
		panel.LayoutOrder = order
		panel.AnchorPoint = Vector2.zero
		panel.Size = UDim2.new(0.3, -4, 1, 0)
		windowBackground(panel, UI.PrimaryFrame)
		local title = panel.Label1
		textStyle(title, font, 14)
		title.AnchorPoint = Vector2.zero
		title.Position = UDim2.fromOffset(10, 0)
		title.Size = UDim2.new(1, -50, 0, 34)
		title.TextXAlignment = Enum.TextXAlignment.Left
		divider(panel, 34)
		local count = make("TextLabel", panel, "Count", {
			Position = UDim2.new(1, -40, 0, 0),
			Size = UDim2.fromOffset(30, 34),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTransparency = 0.35,
		})
		textStyle(count, font, 12)
		local empty = make("TextLabel", panel, "Empty", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.new(1, -28, 0, 40),
			Text = emptyText,
			TextWrapped = true,
			TextTransparency = 0.4,
		})
		textStyle(empty, font, 14)
		local scroll = panel.ScrollingFrame
		scroll.AnchorPoint = Vector2.zero
		scroll.Position = UDim2.fromOffset(6, 41)
		scroll.Size = UDim2.new(1, -12, 1, -47)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 0
		scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
		empty.Parent = scroll
		empty.AnchorPoint = Vector2.zero
		empty.Position = UDim2.new()
		empty.Size = UDim2.new(1, -4, 0, 40)
		empty.LayoutOrder = 0
		local rowPadding = scroll:FindFirstChildOfClass("UIPadding")
			or make("UIPadding", scroll, "RowPadding", {})
		rowPadding.PaddingLeft, rowPadding.PaddingRight = UDim.new(0, 2), UDim.new(0, 2)
		rowPadding.PaddingTop, rowPadding.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
		local rows = scroll:FindFirstChildOfClass("UIListLayout")
		rows.Padding = UDim.new(0, 2)
		rows.HorizontalAlignment = Enum.HorizontalAlignment.Left
		rows.HorizontalFlex = Enum.UIFlexAlignment.None
		rows.VerticalFlex = Enum.UIFlexAlignment.None
		rows.Wraps = false
		rows.SortOrder = Enum.SortOrder.LayoutOrder
		local template = scroll.Template
		template.AnchorPoint = Vector2.zero
		template.Size = UDim2.new(1, 0, 0, 24)
		template.AutomaticSize = Enum.AutomaticSize.None
		surface(template, "TopBtn", Color3.fromRGB(35, 22, 44))

		template.ClipsDescendants = false
		local artwork = make("Frame", template, "Artwork", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Active = false,
			ZIndex = template.ZIndex,
		})
		local iconImage = template.Icon
		iconImage.Parent = artwork
		local outline = template:FindFirstChildOfClass("UIStroke")
		outline.BorderStrokePosition = Enum.BorderStrokePosition.Inner
		outline.ZIndex = 2
		iconImage.Image = icon
		iconImage.ImageColor3 = Color3.new(1, 1, 1)
		iconImage:SetAttribute("ThemeImg", nil)
		iconImage.AnchorPoint = Vector2.new(0, 0.5)
		iconImage.Position = UDim2.new(0, 5, 0.5, 0)
		iconImage.Size = UDim2.fromOffset(18, 18)
		iconImage.ImageTransparency = 0.1
		iconImage.ZIndex = template.ZIndex
		iconImage.ScaleType = Enum.ScaleType.Fit
		local name = template:FindFirstChild(labelName)
		textStyle(name, font, 13)
		name.AnchorPoint = Vector2.zero
		name.Position = UDim2.fromOffset(29, 0)
		name.Size = UDim2.new(1, -35, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextWrapped = false
		name.ZIndex = template.ZIndex + 2
		name.TextTruncate = Enum.TextTruncate.AtEnd

		local function refresh(removing)
			local total = 0
			local sections = false
			for _, child in scroll:GetDescendants() do
				if child == removing or removing and child:IsDescendantOf(removing) then
					continue
				end

				if child.Name == "RigAnimations" and child.Parent == scroll then
					sections = true
				end

				if
					child:IsA("GuiButton")
					and child ~= template
					and not child:IsDescendantOf(template)
					and not child:GetAttribute("EclipseAnimationImport")
					and (child.Parent == scroll or child:GetAttribute("EclipseAnimationRow"))
				then
					total += 1
				end
			end

			count.Text = tostring(total)
			empty.Visible = total == 0 and not sections
		end

		scroll.DescendantAdded:Connect(function()
			refresh()
		end)
		scroll.DescendantRemoving:Connect(refresh)
		refresh()
	end

	listPanel(main.Left, 0, "rbxassetid://78090070815334", "Title", "No saved projects yet")
	listPanel(main.Right, 1, "rbxassetid://89556935799891", "Name", "No animations to show")

	local center = main.Center
	center.LayoutOrder = 2
	center.AnchorPoint = Vector2.zero
	center.Size = UDim2.new(0.4, -4, 1, 0)
	local centerLayout = center:FindFirstChildOfClass("UIListLayout")
	if centerLayout then
		centerLayout:Destroy()
	end

	if center:FindFirstChild("Label3") then
		center.Label3:Destroy()
	end

	windowBackground(center, UI.PrimaryFrame)
	halftone(center)
	for _, item in { { center.Label1, 16, -94, 28 }, { center.Label2, 12, -62, 20 } } do
		local label = item[1]
		textStyle(label, font, item[2])
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0.5, item[3])
		label.Size = UDim2.new(1, -28, 0, item[4])
		label.ZIndex = 3
		label.TextWrapped = true
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end

	center.Label2.TextTransparency = 0.35
	local create = center.ProjectCreator
	create.AnchorPoint = Vector2.new(0.5, 0)
	create.Position = UDim2.new(0.5, 0, 0.5, -34)
	create.ZIndex = 3
	create.Title.ZIndex = 4
	create.Size = UDim2.new(1, -32, 0, 34)
	surface(create, "TopBtn", Color3.fromRGB(45, 27, 56))
	create.Title.Text = "NEW ANIMATION"
	local orLabel = make("TextLabel", center, "Or", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(1, -32, 0, 20),
		Text = "OR",
		TextTransparency = 0.4,
		ZIndex = 3,
	})
	textStyle(orLabel, font, 12)
	local blank = create:Clone()
	blank.Name = "BlankProjectCreator"
	blank.Position = UDim2.new(0.5, 0, 0.5, 32)
	blank.Title.Text = "NEW BLANK PROJECT"
	blank.Parent = center
	UI.BlankProjectCreator_BTN = blank

	create:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if not create.Interactable and create.BackgroundTransparency ~= 0.5 then
			create.BackgroundTransparency = 0.5
		end
	end)
	create:SetAttribute("EOrig_BackgroundTransparency", 0)
	create.Title:SetAttribute("EOrig_TextTransparency", 0)
	MainMenu.updateSelection(UI, nil)
	local unsubscribe = Theme.onChanged(function()
		local enabled = create:GetAttribute("HasSelection") == true
		WindowFX.setRestingProperty(create.Title, "TextTransparency", enabled and 0 or 0.6)
		WindowFX.setRestingProperty(create, "BackgroundTransparency", enabled and 0 or 0.5)
		WindowFX.setRestingProperty(
			create:FindFirstChildOfClass("UIStroke"),
			"Transparency",
			enabled and 0 or 0.5
		)
	end)
	UI.EclipseGUI.Destroying:Once(unsubscribe)

	local alert = UI.AlertFrame
	alert.Size = UDim2.fromOffset(328, 0)
	alert.AutomaticSize = Enum.AutomaticSize.Y
	round(alert, 5)
	local alertPadding = alert:FindFirstChildOfClass("UIPadding")
	alertPadding.PaddingTop, alertPadding.PaddingBottom = UDim.new(0, 14), UDim.new(0, 14)
	alertPadding.PaddingLeft, alertPadding.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	local alertLayout = alert:FindFirstChildOfClass("UIListLayout")
	alertLayout.Padding = UDim.new(0, 12)
	alertLayout.SortOrder = Enum.SortOrder.LayoutOrder
	alert.Information.LayoutOrder = 0
	alert.Buttons.LayoutOrder = 2
	alert.Buttons.Size = UDim2.new(1, 0, 0, 32)
	local alertLine = divider(alert, 0)
	alertLine.LayoutOrder = 1
	local buttons = alert.Buttons:FindFirstChildOfClass("UIListLayout")
	buttons.FillDirection = Enum.FillDirection.Horizontal
	buttons.SortOrder = Enum.SortOrder.LayoutOrder
	buttons.Padding = UDim.new(0, 8)
	UI.DisagreeButton.LayoutOrder, UI.AgreeButton.LayoutOrder = 0, 1
	UI.AgreeButton.Size = UDim2.new(0.5, -4, 0, 32)
	UI.DisagreeButton.Size = UDim2.new(0.5, -4, 0, 32)
	textStyle(UI.HeaderLabel, font, 15)
	textStyle(UI.DescriptionLabel, font, 14)
	UI.AgreeButton.Title.Text = "Discard"
	UI.DisagreeButton.Title.Text = "Cancel"
	UI.AgreeButton:SetAttribute("ThemeBg", "MenuSel")
	UI.DisagreeButton:SetAttribute("ThemeBg", "Menu")
	for _, button in { UI.AgreeButton, UI.DisagreeButton } do
		button.Title:SetAttribute("ThemeTxt", "Txt")
		for _, g in button:GetDescendants() do
			if g:IsA("UIGradient") and g:GetAttribute("ThemeGrad") == "TopBtn" then
				g:SetAttribute("ThemeGrad", button:GetAttribute("ThemeBg"))
			end
		end
	end
end

return MainMenu
