--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Chrome = require("Chrome")
local Surface = require("Surface")
local Tool = require("Tool")
local Theme = require("Theme")
local Layout = {}

local function box(object, x, y, w, h)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

local function label(parent, name, text, x, y, w, h)
	local object = parent:FindFirstChild(name)
		or Tool.label(parent, name, text, UDim2.new(), UDim2.new())
	box(object, x, y, w, h)
	object.Text = text
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Center
	object.ZIndex = parent.ZIndex + 2
	return object
end

local function quiet(object)
	object.TextTransparency = 0.3
	object.TextSize = 11
end

local function checkbox(row, text, width)
	local toggle = row.Toggle
	local checked = toggle.Fill.Visible
	for _, child in toggle:GetChildren() do
		child:Destroy()
	end

	box(toggle, 0, 0, width, 24)
	toggle.Text = ""
	toggle.BackgroundTransparency = 1
	toggle:SetAttribute("ThemeBg", nil)
	toggle.AutoButtonColor = false
	for _, name in { "Unchecked", "Fill" } do
		Tool.make("ImageLabel", toggle, name, {
			Image = "rbxassetid://129527857019669",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromOffset(16, 16),
			ImageColor3 = name == "Fill" and Color3.fromRGB(113, 255, 61)
				or Color3.fromRGB(58, 58, 58),
			Visible = name ~= "Fill" or checked,
			ZIndex = toggle.ZIndex + (name == "Fill" and 2 or 1),
		})
	end

	label(row, "Title", text, 24, 0, width - 24, 24)
end

function Layout.enabled(button, enabled)
	button.Active = enabled
	button.Interactable = enabled
	local text = button:FindFirstChild("Label") or button:FindFirstChildOfClass("TextLabel")
	if text then
		text.TextTransparency = enabled and 0 or 0.55
	end
end

function Layout.apply(frame)
	local bar = frame:FindFirstChild("Bar")
	local title = bar and bar:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = "RIG TOOLS"
	end

	if frame:GetAttribute("HelpersLayoutVersion") == 9 then
		return frame
	end

	frame:SetAttribute("HelpersLayoutVersion", nil)
	frame.Size = UDim2.fromOffset(500, 410)
	for _, item in frame:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
			item.FontFace = Chrome.FONT
			item.TextSize = 12
			item.TextScaled = false
			item:SetAttribute("ThemeTxt", "Txt")
			item.TextTransparency = 0
		end

		if item:IsA("TextButton") then
			item:SetAttribute("ThemeBg", "TopBtn")
		end

		if item:IsA("UICorner") then
			item.CornerRadius = UDim.new(0, 3)
		end

		if item.Name == "Swirl" or item.Name == "Backdrop" then
			item:Destroy()
		end
	end

	for _, child in frame:GetChildren() do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end

	frame:SetAttribute("ThemeBgImage", nil)
	frame:SetAttribute("EOrig_BackgroundTransparency", nil)
	local backdrop = Surface.backdrop(frame, true)
	backdrop.ZIndex = 0
	if frame:IsA("CanvasGroup") then
		frame.GroupColor3 = Color3.new(1, 1, 1)
	end

	local bar = frame.Bar
	box(bar, 0, 0, 500, 28)
	bar.ClipsDescendants = false
	bar.BackgroundTransparency = 0.25
	bar:SetAttribute("ThemeBg", "Top")
	bar.Icon.Visible = false
	box(bar.Title, 12, 0, 240, 28)
	box(bar.TabButtons, 18, 38, 464, 28)
	local tabs = bar.TabButtons:FindFirstChildOfClass("UIListLayout")
	if tabs then
		tabs.Padding = UDim.new(0, 8)
	end

	if not bar.TabButtons:FindFirstChild("ACCESSORIESTab") then
		local b = bar.TabButtons.RIGSTab:Clone()
		b.Name = "ACCESSORIESTab"
		b.LayoutOrder = 3
		for _, t in b:GetDescendants() do
			if t:IsA("TextLabel") then
				t.Text = "ACCESSORIES"
			end
		end

		b.Parent = bar.TabButtons
	end

	bar.TabButtons.WELDTab.LayoutOrder = 1
	bar.TabButtons.RIGSTab.LayoutOrder = 2
	for _, b in bar.TabButtons:GetChildren() do
		if b:IsA("TextButton") then
			b.Size = UDim2.fromOffset(149, 28)
		end
	end

	if not bar.CloseButton:FindFirstChild("ControlGradient") then
		bar.CloseButton:Destroy()
		Chrome.close(bar).Name = "CloseButton"
	end

	local weld, rigs = frame.WeldTab, frame.RigsTab
	box(weld, 18, 78, 464, 304)
	box(rigs, 18, 78, 464, 304)
	if weld:FindFirstChild("SelectionHelp") then
		weld.SelectionHelp:Destroy()
	end

	for index, card in { weld.AnchorCard, weld.TargetCard } do
		box(card, (index - 1) * 238, 0, 226, 82)
		card.BackgroundTransparency = 1
		for _, child in card:GetChildren() do
			if child:IsA("UIStroke") then
				child.Enabled = false
			end
		end

		box(card.Preview, 0, 0, 80, 80)
		card.Preview:SetAttribute("ThemeBg", "Pnl")
		box(card.Header, 92, 6, 134, 18)
		card.Header.Text = index == 1 and "ANCHOR" or "TARGETS"
		card.Header.TextXAlignment = Enum.TextXAlignment.Left
		quiet(card.Header)
		label(card, "TargetName", "", 92, 28, 134, 48)
		card.TargetName.TextWrapped = true
		card.TargetName.TextXAlignment = Enum.TextXAlignment.Left
		card.TargetName.TextTruncate = Enum.TextTruncate.AtEnd
		box(card.Preview.EmptyState.Message, 0, 0, 80, 80)
		card.Preview.EmptyState.Message.Text = index == 1 and "1" or "2"
		card.Preview.EmptyState.Message.TextSize = 20
		card.Preview.EmptyState.Message.TextTransparency = 0.55
	end

	weld.FlowArrow.Visible = false
	local binder = weld.BinderPanel
	box(binder, 0, 86, 464, 90)
	binder.Title.Visible = false
	binder.Description.Visible = false
	box(binder.AnimatableRow, 0, 0, 464, 24)
	checkbox(binder.AnimatableRow, "Animatable joint", 464)
	box(binder.BindButton, 0, 34, 226, 32)
	box(binder.BindInPlaceButton, 238, 34, 226, 32)
	binder.BindButton.Label.Text = "BIND TO ANCHOR"
	binder.BindInPlaceButton.Label.Text = "BIND IN PLACE"
	if binder:FindFirstChild("SnapHelp") then
		binder.SnapHelp:Destroy()
	end

	if binder:FindFirstChild("KeepHelp") then
		binder.KeepHelp:Destroy()
	end

	box(binder.Hint, 0, 70, 464, 18)
	binder.Hint.Text = ""
	binder.Hint.TextWrapped = true
	binder.Hint.TextXAlignment = Enum.TextXAlignment.Left
	quiet(binder.Hint)
	box(weld.SectionDivider, 0, 182, 464, 1)
	local sweep = weld.SweeperPanel
	box(sweep, 0, 194, 464, 44)
	box(sweep.Title, 0, 0, 100, 18)
	sweep.Title.Text = "JOINTS"
	sweep.Description.Visible = false
	box(sweep.TargetName, 108, 0, 202, 20)
	box(sweep.JointCount, 108, 22, 202, 20)
	for _, text in { sweep.TargetName, sweep.JointCount } do
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
	end

	quiet(sweep.JointCount)
	box(sweep.SweepButton, 324, 6, 140, 32)
	sweep.SweepButton.Label.Text = "REMOVE JOINTS"
	local card, panel = rigs.AvatarCard, rigs.AvatarPanel
	box(card, 0, 0, 128, 170)
	card.BackgroundTransparency = 1
	for _, child in card:GetChildren() do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end

	card.Header.Visible = false
	box(card.Preview, 0, 0, 128, 140)
	card.Preview:SetAttribute("ThemeBg", "Pnl")
	box(card.TargetName, 0, 144, 128, 26)
	card.TargetName.TextTruncate = Enum.TextTruncate.AtEnd
	box(card.Preview.EmptyState.Message, 10, 48, 108, 42)
	card.Preview.EmptyState.Message.Text = "Avatar preview"
	quiet(card.Preview.EmptyState.Message)
	box(panel, 144, 0, 320, 170)
	box(panel.Title, 0, 0, 320, 18)
	box(panel.UserInput, 0, 26, 218, 28)
	panel.UserInput.BackgroundTransparency = 0
	panel.UserInput:SetAttribute("ThemeBg", "TopBtn")
	panel.UserInput:SetAttribute("ThemeShade", nil)
	panel.UserInput.TextXAlignment = Enum.TextXAlignment.Left
	panel.UserInput.ClearTextOnFocus = false
	local stroke = panel.UserInput:FindFirstChildOfClass("UIStroke")
		or Instance.new("UIStroke", panel.UserInput)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke:SetAttribute("ThemeStrk", "Strk")
	local padding = panel.UserInput:FindFirstChildOfClass("UIPadding")
		or Instance.new("UIPadding", panel.UserInput)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	box(panel.SpawnAvatarButton, 226, 26, 94, 28)
	panel.BodyHeader.Visible = true
	box(panel.BodyHeader, 0, 66, 320, 18)
	quiet(panel.BodyHeader)
	box(panel.BodyPills, 0, 90, 320, 28)
	local pills = panel.BodyPills:FindFirstChildOfClass("UIListLayout")
	if pills then
		pills.Padding = UDim.new(0, 7)
	end

	for _, b in panel.BodyPills:GetChildren() do
		if b:IsA("TextButton") then
			b.Size = UDim2.fromOffset(102, 28)
		end
	end

	box(panel.DefaultBodyRow, 0, 132, 320, 24)
	checkbox(panel.DefaultBodyRow, "Default body", 194)
	if panel:FindFirstChild("Outfits") then
		panel.Outfits:Destroy()
	end

	Tool.button(panel, "Outfits", "OUTFITS", UDim2.fromOffset(218, 132), UDim2.fromOffset(102, 28))
	if rigs:FindFirstChild("AvatarHelp") then
		rigs.AvatarHelp:Destroy()
	end

	box(rigs.SectionDivider, 0, 182, 464, 1)
	local blank = rigs.BlankRigsPanel
	box(blank, 0, 192, 464, 88)
	blank.Subtitle.Visible = false
	box(blank.Title, 0, 0, 464, 18)
	blank.Title.Text = "INSERT A RIG"
	box(blank.PresetGrid, 0, 26, 464, 62)
	for _, layout in blank.PresetGrid:GetChildren() do
		if layout:IsA("UIGridLayout") or layout:IsA("UIListLayout") then
			layout:Destroy()
		end
	end

	Tool.make("UIListLayout", blank.PresetGrid, "Layout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for index, name in { "R6Preset", "R15Preset", "TemplateR6Preset", "TemplateR15Preset" } do
		local b = blank.PresetGrid[name]
		b.LayoutOrder = index
		b.Size = UDim2.fromOffset(86, 62)
		b.Label.TextSize = 10
		box(b.Preview, 21, 4, 44, 36)
		box(b.Label, 0, 42, 86, 18)
	end

	if not blank.PresetGrid:FindFirstChild("CameraPreset") then
		local camera, text = Tool.button(
			blank.PresetGrid,
			"CameraPreset",
			"CAMERA",
			UDim2.new(),
			UDim2.fromOffset(88, 62)
		)
		camera.LayoutOrder = 5
		text.TextSize = 10
	end

	quiet(label(frame, "ResetStatus", "", 18, 312, 298, 26))
	frame.ResetStatus.Position = UDim2.new(0, 18, 1, -38)
	if not frame:FindFirstChild("ResetPose") then
		Tool.button(frame, "ResetPose", "RESET POSE", UDim2.new(), UDim2.new())
	end

	box(frame.ResetPose, 332, 312, 150, 26)
	frame.ResetPose.Position = UDim2.new(0, 332, 1, -38)
	Theme.applyTree(frame)
	frame:SetAttribute("HelpersLayoutVersion", 9)
	return frame
end

function Layout.selectTab(frame, name)
	local height = if name == "ACCESSORIES" then 300 elseif name == "WELD" then 370 else 410
	local old = frame.Size
	local scaleObject = frame:FindFirstChildOfClass("UIScale")
	local scale = scaleObject and scaleObject.Scale or 1

	frame.Position += UDim2.fromOffset(
		(500 - old.X.Offset) * frame.AnchorPoint.X * scale,
		(height - old.Y.Offset) * frame.AnchorPoint.Y * scale
	)
	frame.Size = UDim2.fromOffset(500, height)
	frame.WeldTab.Size = UDim2.fromOffset(464, 238)
	frame:SetAttribute("HelpersActiveTab", name)
end

return Layout
