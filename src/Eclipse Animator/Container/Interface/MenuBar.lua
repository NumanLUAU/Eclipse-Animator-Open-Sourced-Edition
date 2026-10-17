--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Keybinds = require("Keybinds")
local Shortcuts = require("Shortcuts")
local MenuButtonStyle = require("Style")
local TweenService = game:GetService("TweenService")
local UserInputService = require("UserInputService")

local DropdownConfigs = require("DropdownConfigs")
local DropdownBuilder = require("DropdownBuilder")
local Theme = require("Theme")

local MenuBar = {}

local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SWITCH_TWEEN = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_COLOR = Color3.fromRGB(34, 0, 52)
local PRESS_COLOR = Color3.fromRGB(100, 0, 151)

Theme.onChanged(function()
	HOVER_COLOR = Theme.get("MenuHov", Color3.fromRGB(34, 0, 52))
	PRESS_COLOR = Theme.get("MenuSel", Color3.fromRGB(100, 0, 151))
end)
local BTN_DEFAULT = Color3.fromRGB(51, 0, 77)
local BTN_OPEN_FALLBACK = Color3.fromRGB(100, 0, 151)
local MENU_GAP = 5
local CLICK_SWITCH_GRACE = 0.25

local screenGui = nil
local uiScale = nil
local menusFolder = nil
local menuButtonGroups = {}
local menus = {}
local rowActions = {}
local rowChecks = {}
local buttonStyles = {}
local subMenu = nil
local openMenu = nil
local openButton = nil
local lastShowAt = 0
local initialized = false
local documentKind

local function getScaleFactor()
	return UserInputService.inWidget() and 1 or (uiScale and uiScale.Scale) or 1
end

local function pointInGui(x, y, gui)
	local p = gui.AbsolutePosition
	local s = gui.AbsoluteSize
	return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

local function ensureScale(menu)
	local sc = menu:FindFirstChildOfClass("UIScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Parent = menu
	end

	return sc
end

local function positionMenu(menu, btn)
	require("Motion").placePopup(menu, btn, "below")
end

local function close()
	if subMenu then
		subMenu.Visible = false
		subMenu = nil
	end

	if not openMenu then
		return
	end

	openMenu.Visible = false
	if openButton and buttonStyles[openButton] then
		buttonStyles[openButton].idle()
	end

	openMenu = nil
	openButton = nil
end

local function show(menu, btn, switching)
	local converter = menu:FindFirstChild("R15ToR6", true)
	if converter then converter.Visible = #require("Import").r15Rigs(require("State")) > 0 end
	if documentKind then
		local kind = documentKind()
		for id, text in
			{
				SaveProject = "Save " .. kind,
				SaveProjectAs = "Save " .. kind .. " As...",
				SaveAndCloseProject = "Save " .. kind .. " and Close",
			}
		do
			local row = menu:FindFirstChild(id, true)
			local title = row and row:FindFirstChild("Title", true)
			if title then
				title.Text = text
			end
		end
	end

	if subMenu then
		subMenu.Visible = false
		subMenu = nil
	end

	for id, checked in rowChecks do
		local row = menu:FindFirstChild(id, true)
		local check = row and row:FindFirstChild("Check", true)
		if check then
			check.Visible = checked() == true
		end
	end

	menu.AnchorPoint = Vector2.new(0, 0)
	positionMenu(menu, btn)
	local sc = ensureScale(menu)
	sc.Scale = switching and 0.96 or 0.88
	require("DropdownBuilder").refreshIcons(menu)
	menu.Visible = true
	TweenService:Create(sc, switching and SWITCH_TWEEN or OPEN_TWEEN, { Scale = 1 }):Play()
	if openButton and openButton ~= btn and buttonStyles[openButton] then
		buttonStyles[openButton].idle()
	end

	openMenu = menu
	openButton = btn
	lastShowAt = os.clock()
	if buttonStyles[btn] then
		buttonStyles[btn].open()
	end
end

local function effectsSubmenu(button)
	local menu = menus.EFFECTS
	if not menu or not openMenu then
		return
	end

	subMenu = menu
	ensureScale(menu).Scale = 1
	require("Motion").placePopup(menu, button, "right")
	require("DropdownBuilder").refreshIcons(menu)
	menu.Visible = true
end

local function wireRow(button, rowId)
	local activeTween = nil
	local activeHalftoneTween = nil
	local activeHalftoneColorTween = nil

	local function tweenBg(color, transparency)
		if activeTween then
			activeTween:Cancel()
		end

		if button.BackgroundTransparency >= 0.99 then
			button.BackgroundColor3 = color
		end

		activeTween = TweenService:Create(
			button,
			FADE_TWEEN,
			{ BackgroundColor3 = color, BackgroundTransparency = transparency }
		)
		activeTween:Play()
	end

	local halftone = button:FindFirstChild("Halftone")

	local function tweenHalftone(transparency, color)
		if not halftone then
			return
		end

		if activeHalftoneTween then
			activeHalftoneTween:Cancel()
		end

		activeHalftoneTween =
			TweenService:Create(halftone, FADE_TWEEN, { ImageTransparency = transparency })
		activeHalftoneTween:Play()
		if color then
			if activeHalftoneColorTween then
				activeHalftoneColorTween:Cancel()
			end

			activeHalftoneColorTween =
				TweenService:Create(halftone, FADE_TWEEN, { ImageColor3 = color })
			activeHalftoneColorTween:Play()
		end
	end

	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	if halftone then
		halftone.Visible = true
		halftone.ImageTransparency = 1
	end

	local check = button:FindFirstChild("Check")
	if check then
		check.Visible = false
	end

	button.MouseEnter:Connect(function()
		if rowId == "AddEffects" then
			effectsSubmenu(button)
		elseif subMenu and menus.ITEM and button:IsDescendantOf(menus.ITEM) then
			subMenu.Visible = false
			subMenu = nil
		end

		tweenBg(HOVER_COLOR, 0)
		tweenHalftone(0.8, Color3.fromRGB(255, 255, 255))
	end)
	button.MouseLeave:Connect(function()
		tweenBg(HOVER_COLOR, 1)
		tweenHalftone(1, Color3.fromRGB(255, 255, 255))
	end)
	button.MouseButton1Down:Connect(function()
		tweenBg(PRESS_COLOR, 0)
		tweenHalftone(0.4, Color3.fromRGB(0, 0, 0))
	end)
	button.MouseButton1Click:Connect(function()
		if rowId == "AddEffects" then
			effectsSubmenu(button)
			return
		end

		tweenBg(HOVER_COLOR, 1)
		tweenHalftone(1, Color3.fromRGB(255, 255, 255))
		close()
		local action = rowId and rowActions[rowId]
		if action then
			task.spawn(action)
		end
	end)
end

function MenuBar.init(refs)
	documentKind = refs.DocumentKind
	if initialized then
		return
	end

	local menuButtons = refs and refs.MenuButtons
	local dropdownsFolder = refs and refs.DropdownsFolder
	rowChecks = refs and refs.Checks or {}
	if refs and refs.Actions then
		rowActions = refs.Actions
		for _, binding in Shortcuts.list() do
			local action = rowActions[binding.Action]
			if action and binding.Dispatch then
				Keybinds.bind(binding.Action, function()
					if refs.AnimatorFrame and refs.AnimatorFrame.Visible then
						action()
					end
				end)
			end
		end
	end

	if not menuButtons or not dropdownsFolder then
		return
	end

	local template = dropdownsFolder:FindFirstChild("DropdownTemplate")
	if not template then
		return
	end

	screenGui = dropdownsFolder:FindFirstAncestorWhichIsA("ScreenGui")
	if not screenGui then
		return
	end

	uiScale = screenGui:FindFirstChildOfClass("UIScale")
	menuButtonGroups = { menuButtons }
	for _, group in refs.ExtraMenuButtons or {} do
		table.insert(menuButtonGroups, group)
	end

	initialized = true

	local old = screenGui:FindFirstChild("MenuBarDropdowns")
	if old then
		old:Destroy()
	end

	menusFolder = Instance.new("Folder")
	menusFolder.Name = "MenuBarDropdowns"
	menusFolder.Parent = screenGui

	for name, cfg in pairs(DropdownConfigs) do
		if typeof(cfg) == "table" and cfg.rows and cfg.menubar then
			local built = DropdownBuilder.build(template, name, cfg)
			if built then
				built.ZIndex = 60
				built.Visible = false
				built.Parent = menusFolder
				menus[cfg.menubar] = built
				local content = built:FindFirstChild("Content")
				if content then
					for _, row in ipairs(content:GetChildren()) do
						local rowButton = row:FindFirstChildWhichIsA("GuiButton")
						if rowButton then
							wireRow(rowButton, row.Name)
						end
					end
				end
			end
		end
	end

	local menuOrder = { FILE = 1, ITEM = 2, EDIT = 3, RIG = 4, VIEW = 5, SETTINGS = 6 }
	for _, group in menuButtonGroups do
		local file, exists
		for _, button in group:GetChildren() do
			local label = button:FindFirstChildWhichIsA("TextLabel")
			if label then
				if label.Text == "TOOLS" then
					button:Destroy()
					continue
				end

				if label.Text == "FILE" then
					file = button
				end

				if label.Text == "ITEM" then
					exists = true
				end

				if menuOrder[label.Text] then
					button.LayoutOrder = menuOrder[label.Text]
				end
			end
		end

		if file and not exists then
			local item = file:Clone()
			item.Name, item.LayoutOrder = "ItemButton", 2
			item:FindFirstChildWhichIsA("TextLabel").Text = "ITEM"
			item.Parent = group
		end
	end

	local prototype = menuButtons:FindFirstChildWhichIsA("GuiButton")
	for _, group in menuButtonGroups do
		for _, btn in ipairs(group:GetChildren()) do
			if btn:IsA("GuiButton") then
				local label = btn:FindFirstChildWhichIsA("TextLabel")
				local menu = label and menus[string.upper(label.Text)] or nil
				if label then
					if prototype and group ~= menuButtons then
						for _, child in prototype:GetChildren() do
							if
								child:IsA("UICorner")
								or child.Name == "SubtleGradient"
								or child.Name == "HoverStroke"
							then
								local old = btn:FindFirstChild(child.Name)
								if old then
									old:Destroy()
								end

								child:Clone().Parent = btn
							end
						end

						local sourceLabel = prototype:FindFirstChildWhichIsA("TextLabel")
						label.FontFace = sourceLabel.FontFace
						label.TextSize = sourceLabel.TextSize
						label.TextScaled = sourceLabel.TextScaled
						label:SetAttribute("ThemeTxt", "TopT")
						btn:SetAttribute("ThemeBg", "TopBtn")
					end

					buttonStyles[btn] = MenuButtonStyle.bind(btn, label)

					btn.MouseButton1Down:Connect(function()
						buttonStyles[btn].open()
					end)
					btn.MouseButton1Click:Connect(function()
						if not menu then
							close()
							buttonStyles[btn].hover()
							return
						end

						if openMenu == menu then
							if os.clock() - lastShowAt > CLICK_SWITCH_GRACE then
								close()
								buttonStyles[btn].hover()
							end

							return
						end

						local switching = openMenu ~= nil
						if openMenu then
							openMenu.Visible = false
						end

						show(menu, btn, switching)
					end)
					btn.MouseEnter:Connect(function()
						if menu and openMenu and openMenu ~= menu then
							openMenu.Visible = false
							show(menu, btn, true)
						elseif openButton ~= btn then
							buttonStyles[btn].hover()
						end
					end)
					btn.MouseLeave:Connect(function()
						if openButton ~= btn then
							buttonStyles[btn].idle()
						end
					end)
				end
			end
		end

		group:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			if openMenu and openButton and openButton:IsDescendantOf(group) then
				positionMenu(openMenu, openButton)
			end
		end)
	end

	for _, frame in { refs.AnimatorFrame, refs.PrimaryFrame } do
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not frame.Visible and openButton and openButton:IsDescendantOf(frame) then
				close()
			end
		end)
	end

	screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not screenGui.Enabled then
			close()
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if not openMenu then
			return
		end

		if Shortcuts.matches("Cancel", input) then
			close()
			return
		end

		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.MouseButton2
		then
			return
		end

		local mp = UserInputService:GetMouseLocation()
		if
			pointInGui(mp.X, mp.Y, openMenu)
			or subMenu and subMenu.Visible and pointInGui(mp.X, mp.Y, subMenu)
		then
			return
		end

		for _, group in menuButtonGroups do
			if
				openButton
				and openButton:IsDescendantOf(group)
				and pointInGui(mp.X, mp.Y, group)
			then
				return
			end
		end

		close()
	end)
end

function MenuBar.close()
	close()
end

return MenuBar
