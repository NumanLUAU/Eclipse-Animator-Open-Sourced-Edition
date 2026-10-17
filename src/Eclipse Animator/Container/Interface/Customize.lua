--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Chrome = require("Chrome")
local Tool = require("Tool")
local GifEditor = require("GifEditor")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Theme = require("Theme")
local ThemeConfig = require("ThemeConfig")
local WindowFX = require("WindowFX")
local MainState = require("State")

local Customize = {}

local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local ICON_RESET = "rbxassetid://78735604616196"
local ICON_SAVE = "rbxassetid://133945325216888"
local ICON_LOAD = "rbxassetid://117142004423616"
local ICON_CLOSE = "rbxassetid://104480403429046"
local CARD_BG = Color3.fromRGB(26, 14, 40)
local FIELD_BG = Color3.fromRGB(16, 7, 26)
local CHIP_BG = Color3.fromRGB(100, 0, 151)
local TXT = Color3.fromRGB(235, 228, 242)
local TXT_DIM = Color3.fromRGB(157, 157, 157)

local screenGui = nil
local window = nil
local scroll = nil
local grid = nil
local modeChip = nil
local presetsChip = nil
local presetsFrame = nil
local showingPresets = false
local userPresets = {}
local getSetting = nil
local setSetting = nil
local tooltip = nil
local resetHint = nil
local picker = nil
local modal = nil
local layoutTool = nil
local windowRefs = nil
local cards = {}
local pickerKey = nil
local pickerValue = nil
local pickerSnapshot = nil
local pickerStop = 1
local lastResetPress = 0
local initialized = false
local closing = false
local suppressPickerClose = false

local editingFields = setmetatable({}, { __mode = "k" })

local function fieldText(box)
	return editingFields[box] or box.Text
end

local function setFieldText(box, value)
	if editingFields[box] == nil then
		box.Text = value
	end
end

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end

	if inst:IsA("TextBox") then
		inst.ClearTextOnFocus = false
		inst.Focused:Connect(function()
			if not inst.TextEditable or inst:GetAttribute("PreserveTextOnFocus") then
				return
			end

			editingFields[inst] = inst.Text
			inst.Text = ""
		end)

		inst.FocusLost:Connect(function()
			local previous = editingFields[inst]
			editingFields[inst] = nil
			if previous ~= nil and not inst.Text:match("%S") then
				inst.Text = previous
			end
		end)
	end

	inst.Parent = parent
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst:SetAttribute("ThemeTxt", "Txt")
	end

	return inst
end

local function corner(inst, r)
	mk("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

local function copyValue(v)
	if not v then
		return nil
	end

	local stops = {}
	for _, c in ipairs(v.stops or {}) do
		table.insert(stops, c)
	end

	return {
		stops = stops,
		rot = v.rot,
		t = v.t,
		image = v.image,
		frames = v.frames,
		layout = v.layout and table.clone(v.layout),
		mode = v.mode,
	}
end

local function baseKeyFor(key)
	local exp = ThemeConfig.simpleExpand[key]
	if exp then
		return exp[1].target
	end

	return key
end

local function currentValueFor(key)
	local base = baseKeyFor(key)
	local ov = Theme.getOverride(base)
	if ov then
		return copyValue(ov)
	end

	return copyValue(Theme.sampleDefaultValue(base))
end

local function accent()
	return Theme.get("MenuSel", CHIP_BG)
end

local function guiScale()
	local sc = screenGui and screenGui:FindFirstChildOfClass("UIScale")
	return (sc and sc.Scale) or 1
end

local function ensureTooltip()
	if tooltip then
		return
	end

	tooltip = mk("TextLabel", {
		Name = "EclipseCustomizeTip",
		BackgroundColor3 = Color3.fromRGB(12, 5, 20),
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 9,
		Visible = false,
		ZIndex = 120,
		AutomaticSize = Enum.AutomaticSize.XY,
		Text = "",
	}, screenGui)
	corner(tooltip, 4)
	mk("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, tooltip)
	local tipStroke =
		mk("UIStroke", { Color = Color3.fromRGB(140, 80, 210), Transparency = 0.4 }, tooltip)
	tooltip:SetAttribute("ThemeBg", "Tip")
	tooltip:SetAttribute("ThemeTxt", "TipT")
	tipStroke:SetAttribute("ThemeStrk", "Strk")
end

local function moveTooltip()
	local mp = UserInputService:GetMouseLocation()
	local scale = guiScale()
	tooltip.Position = UDim2.fromOffset(
		(mp.X - screenGui.AbsolutePosition.X) / scale + 14,
		(mp.Y - screenGui.AbsolutePosition.Y) / scale + 12
	)
end

local function attachTip(gui, textOrFn)
	local hd = MainState.UIHelpers and MainState.UIHelpers.hoverDialog
	if hd then
		hd:latchToInstance(gui, textOrFn)
		return
	end

	ensureTooltip()
	gui.MouseEnter:Connect(function()
		tooltip.Text = typeof(textOrFn) == "function" and textOrFn() or textOrFn
		moveTooltip()
		tooltip.Visible = true
	end)
	gui.MouseMoved:Connect(function()
		if tooltip.Visible then
			moveTooltip()
		end
	end)
	gui.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)
end

local function tagText(lbl, shade)
	lbl:SetAttribute("ThemeTxt", "Txt")
	if shade then
		lbl:SetAttribute("ThemeShade", shade)
	end

	return lbl
end

local function tagField(box)
	local shell = Instance.new("Frame")
	shell.Name = box.Name .. "Surface"
	shell.Size = box.Size
	shell.Position = box.Position
	shell.AnchorPoint = box.AnchorPoint
	shell.ZIndex = box.ZIndex
	shell.BorderSizePixel = 0
	shell.BackgroundColor3 = box.BackgroundColor3
	shell.Parent = box.Parent
	shell:SetAttribute("ThemeBg", "Pnl")
	shell:SetAttribute("ThemeShade", -0.45)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = shell
	box.Parent = shell
	box.Size = UDim2.fromScale(1, 1)
	box.Position = UDim2.new()
	box.AnchorPoint = Vector2.zero
	box.BackgroundTransparency = 1
	box.ZIndex = shell.ZIndex + 1
	box:SetAttribute("ThemeTxt", "Txt")
	box:SetAttribute("ThemeShade", nil)
	return box
end

local function paintSwatch(swatch, v)
	local g = swatch:FindFirstChild("SwatchGradient")
	if v.stops and #v.stops > 1 then
		swatch.BackgroundColor3 = Color3.new(1, 1, 1)
		local kps = {}
		for i, c in ipairs(v.stops) do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#v.stops - 1), c))
		end

		g.Color = ColorSequence.new(kps)
		g.Rotation = v.rot or 90
		g.Enabled = true
	else
		g.Enabled = false
		swatch.BackgroundColor3 = (v.stops and v.stops[1]) or Color3.new(1, 1, 1)
	end
end

local function refreshCards()
	for _, card in pairs(cards) do
		if card.refresh then
			card.refresh()
		end
	end
end

local closePicker

local commitQueued = false
local commitTransient = false

local function commitPicker(transient)
	commitTransient = transient == true and (commitQueued == false or commitTransient)
	if commitQueued then
		return
	end

	commitQueued = true
	task.defer(function()
		commitQueued = false
		if pickerKey and pickerValue then
			Theme.set(pickerKey, copyValue(pickerValue), commitTransient)
			refreshCards()
		end
	end)
end

local function positionPicker()
	if not picker or not window then
		return
	end

	local scale = guiScale()
	local guiPos = screenGui.AbsolutePosition
	local x = (window.AbsolutePosition.X - guiPos.X + window.AbsoluteSize.X) / scale + 10
	local y = (window.AbsolutePosition.Y - guiPos.Y) / scale + 30
	local cam = workspace.CurrentCamera
	if cam and (x + 190) * scale > cam.ViewportSize.X then
		x = (window.AbsolutePosition.X - guiPos.X) / scale - 190
	end

	picker.Position = UDim2.fromOffset(x, y)
end

local function buildPicker()
	picker = mk("Frame", {
		Name = "EclipseColorPicker",
		Size = UDim2.fromOffset(180, 288),
		Position = UDim2.new(0.5, 250, 0.5, -160),
		BackgroundColor3 = Color3.fromRGB(20, 9, 32),
		Visible = false,
		ZIndex = 90,
	}, screenGui)
	corner(picker, 8)
	local pickerStroke = mk(
		"UIStroke",
		{ Color = Color3.fromRGB(120, 70, 180), Transparency = 0.4, Thickness = 1 },
		picker
	)
	picker:SetAttribute("ThemeBg", "Bg")
	pickerStroke:SetAttribute("ThemeStrk", "Strk")

	local sv = mk("ImageButton", {
		Name = "SV",
		Size = UDim2.fromOffset(160, 96),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.new(1, 0, 0),
		AutoButtonColor = false,
		ZIndex = 31,
	}, picker)
	corner(sv, 4)
	local whiteOv = mk(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 31 },
		sv
	)
	corner(whiteOv, 4)
	mk("UIGradient", { Transparency = NumberSequence.new(0, 1) }, whiteOv)
	local blackOv = mk(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 32 },
		sv
	)
	corner(blackOv, 4)
	mk("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90 }, blackOv)
	local svCursor = mk("Frame", {
		Name = "Cursor",
		Size = UDim2.fromOffset(8, 8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 33,
	}, sv)
	mk("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5 }, svCursor)
	corner(svCursor, 4)

	local hue = mk("ImageButton", {
		Name = "Hue",
		Size = UDim2.fromOffset(160, 12),
		Position = UDim2.fromOffset(10, 112),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		ZIndex = 31,
	}, picker)
	corner(hue, 6)
	local hueKps = {}
	for i = 0, 6 do
		table.insert(
			hueKps,
			ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 == 1 and 0.999 or i / 6, 1, 1))
		)
	end

	mk("UIGradient", { Color = ColorSequence.new(hueKps) }, hue)
	local hueCursor = mk("Frame", {
		Name = "Cursor",
		Size = UDim2.new(0, 3, 1, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 33,
	}, hue)
	corner(hueCursor, 2)

	local hexBox = tagField(mk("TextBox", {
		Name = "Hex",
		Size = UDim2.fromOffset(70, 18),
		Position = UDim2.fromOffset(10, 132),
		BackgroundColor3 = FIELD_BG,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 10,
		Text = "#ffffff",
		ClearTextOnFocus = false,
		ZIndex = 31,
	}, picker))
	corner(hexBox, 4)
	local rgbBoxes = {}
	for i = 1, 3 do
		local b = tagField(mk("TextBox", {
			Size = UDim2.fromOffset(26, 18),
			Position = UDim2.fromOffset(84 + (i - 1) * 29, 132),
			BackgroundColor3 = FIELD_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 10,
			Text = "255",
			ClearTextOnFocus = false,
			ZIndex = 31,
		}, picker))
		corner(b, 4)
		rgbBoxes[i] = b
	end

	local flatBtn = mk("TextButton", {
		Name = "Flat",
		Size = UDim2.fromOffset(76, 18),
		Position = UDim2.fromOffset(10, 156),
		BackgroundColor3 = Color3.fromRGB(100, 0, 151),
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 10,
		Text = "FLAT",
		AutoButtonColor = true,
		ZIndex = 31,
	}, picker)
	corner(flatBtn, 4)
	local gradBtn = mk("TextButton", {
		Name = "Grad",
		Size = UDim2.fromOffset(76, 18),
		Position = UDim2.fromOffset(94, 156),
		BackgroundColor3 = FIELD_BG,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 10,
		Text = "GRADIENT",
		AutoButtonColor = true,
		ZIndex = 31,
	}, picker)
	corner(gradBtn, 4)

	local stopA = mk("TextButton", {
		Name = "StopA",
		Size = UDim2.fromOffset(24, 18),
		Position = UDim2.fromOffset(10, 180),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 31,
	}, picker)
	corner(stopA, 4)
	mk("UIStroke", { Name = "Sel", Color = Color3.new(1, 1, 1), Thickness = 1.5 }, stopA)
	local stopB = mk("TextButton", {
		Name = "StopB",
		Size = UDim2.fromOffset(24, 18),
		Position = UDim2.fromOffset(40, 180),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 31,
	}, picker)
	corner(stopB, 4)
	mk(
		"UIStroke",
		{ Name = "Sel", Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 1 },
		stopB
	)
	local rotLabel = tagText(
		mk("TextLabel", {
			Size = UDim2.fromOffset(28, 18),
			Position = UDim2.fromOffset(72, 180),
			BackgroundTransparency = 1,
			TextColor3 = TXT_DIM,
			FontFace = FONT,
			TextSize = 9,
			Text = "ROT",
			ZIndex = 31,
		}, picker),
		-0.35
	)
	local rotBox = tagField(mk("TextBox", {
		Name = "Rot",
		Size = UDim2.fromOffset(36, 18),
		Position = UDim2.fromOffset(100, 180),
		BackgroundColor3 = FIELD_BG,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 10,
		Text = "90",
		ClearTextOnFocus = false,
		ZIndex = 31,
	}, picker))
	corner(rotBox, 4)

	local PALETTE = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(20, 20, 24),
		Color3.fromRGB(255, 84, 84),
		Color3.fromRGB(255, 157, 77),
		Color3.fromRGB(255, 222, 114),
		Color3.fromRGB(85, 200, 120),
		Color3.fromRGB(96, 200, 255),
		Color3.fromRGB(90, 120, 255),
		Color3.fromRGB(160, 90, 255),
		Color3.fromRGB(255, 105, 180),
	}
	for i, pc in ipairs(PALETTE) do
		local col = (i - 1) % 5
		local rowIdx = math.floor((i - 1) / 5)
		local pb = mk("TextButton", {
			Size = UDim2.fromOffset(24, 14),
			Position = UDim2.fromOffset(10 + col * 32, 204 + rowIdx * 18),
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = pc,
			ZIndex = 31,
		}, picker)
		corner(pb, 4)
		pb.MouseButton1Click:Connect(function()
			if pickerValue then
				pickerValue.stops[math.min(pickerStop, #pickerValue.stops)] = pc
				commitPicker()
				Customize._refreshPicker()
			end
		end)
	end

	local cancelBtn = mk("TextButton", {
		Size = UDim2.new(0.5, -13, 0, 20),
		Position = UDim2.fromOffset(10, 258),
		BackgroundColor3 = FIELD_BG,
		TextColor3 = TXT_DIM,
		FontFace = FONT,
		TextSize = 10,
		Text = "CANCEL",
		ZIndex = 31,
	}, picker)
	corner(cancelBtn, 5)
	cancelBtn:SetAttribute("ThemeBg", "Pnl")
	cancelBtn:SetAttribute("ThemeShade", -0.45)
	cancelBtn:SetAttribute("ThemeTxt", "Txt")
	local doneBtn = mk("TextButton", {
		Size = UDim2.new(0.5, -13, 0, 20),
		Position = UDim2.new(0.5, 3, 0, 258),
		BackgroundColor3 = Color3.fromRGB(100, 0, 151),
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 10,
		Text = "DONE",
		ZIndex = 31,
	}, picker)
	corner(doneBtn, 5)
	doneBtn:SetAttribute("ThemeBg", "MenuSel")

	local gradRow = { stopA, stopB, rotLabel, rotBox.Parent }

	local function curColor()
		return pickerValue.stops[math.min(pickerStop, #pickerValue.stops)]
	end

	local function setCurColor(c, transient)
		pickerValue.stops[math.min(pickerStop, #pickerValue.stops)] = c
		commitPicker(transient)
	end

	local function refreshPicker(skipHSV)
		if not pickerValue then
			return
		end

		local isGrad = #pickerValue.stops > 1
		local inactive = Theme.get("Pnl", FIELD_BG):Lerp(Color3.new(0, 0, 0), 0.3)
		flatBtn.BackgroundColor3 = isGrad and inactive or accent()
		gradBtn.BackgroundColor3 = isGrad and accent() or inactive
		for _, chip in { flatBtn, gradBtn } do
			local c = chip.BackgroundColor3
			chip.TextColor3 = c.R * 0.2126 + c.G * 0.7152 + c.B * 0.0722 > 0.55
					and Color3.fromRGB(15, 25, 28)
				or Theme.get("Txt", TXT)
		end

		for _, el in ipairs(gradRow) do
			el.Visible = isGrad
		end

		stopA.BackgroundColor3 = pickerValue.stops[1]
		if isGrad then
			stopB.BackgroundColor3 = pickerValue.stops[2]
		end

		stopA.Sel.Transparency = pickerStop == 1 and 0 or 1
		stopB.Sel.Transparency = pickerStop == 2 and 0 or 1
		local c = curColor()
		local h, s, v = c:ToHSV()
		if not skipHSV then
			sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.fromScale(s, 1 - v)
			hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
		end

		setFieldText(
			hexBox,
			string.format(
				"#%02x%02x%02x",
				math.round(c.R * 255),
				math.round(c.G * 255),
				math.round(c.B * 255)
			)
		)
		setFieldText(rgbBoxes[1], tostring(math.round(c.R * 255)))
		setFieldText(rgbBoxes[2], tostring(math.round(c.G * 255)))
		setFieldText(rgbBoxes[3], tostring(math.round(c.B * 255)))
		setFieldText(rotBox, tostring(pickerValue.rot or 90))
	end

	Theme.onChanged(function()
		if picker and picker.Visible then
			refreshPicker()
		end
	end)

	local draggingSV = false
	local draggingHue = false

	local function applySVFromMouse()
		local mp = UserInputService:GetMouseLocation()
		local p = sv.AbsolutePosition
		local sz = sv.AbsoluteSize
		local s = math.clamp((mp.X - p.X) / sz.X, 0, 1)
		local vv = 1 - math.clamp((mp.Y - p.Y) / sz.Y, 0, 1)
		local h = select(1, curColor():ToHSV())
		local baseH = select(1, sv.BackgroundColor3:ToHSV())
		svCursor.Position = UDim2.fromScale(s, 1 - vv)
		setCurColor(Color3.fromHSV(baseH, s, vv), true)
		refreshPicker(true)
	end

	local function applyHueFromMouse()
		local mp = UserInputService:GetMouseLocation()
		local p = hue.AbsolutePosition
		local sz = hue.AbsoluteSize
		local h = math.clamp((mp.X - p.X) / sz.X, 0, 0.999)
		local c = curColor()
		local _, s, v = c:ToHSV()
		hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		setCurColor(Color3.fromHSV(h, math.max(s, 0.001), math.max(v, 0.001)), true)
		refreshPicker(true)
	end

	sv.MouseButton1Down:Connect(function()
		draggingSV = true
		applySVFromMouse()
	end)
	hue.MouseButton1Down:Connect(function()
		draggingHue = true
		applyHueFromMouse()
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		if draggingSV then
			applySVFromMouse()
		end

		if draggingHue then
			applyHueFromMouse()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local wasDragging = draggingSV or draggingHue
			draggingSV = false
			draggingHue = false
			if wasDragging then
				commitPicker()
			end
		end
	end)

	hexBox.FocusLost:Connect(function()
		local v = Theme.parseValue(hexBox.Text:gsub("%s", ""))
		if v then
			setCurColor(v.stops[1])
		end

		refreshPicker()
	end)
	for i, box in ipairs(rgbBoxes) do
		require("NumericInput").connect(box, { step = 1 }, function()
			local n = tonumber(box.Text)
			if n then
				local c = curColor()
				local rgb = { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
				rgb[i] = math.clamp(math.round(n), 0, 255)
				setCurColor(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
			end

			refreshPicker()
		end)
	end

	require("NumericInput").connect(rotBox, { step = 1 }, function()
		local n = tonumber(rotBox.Text)
		if n then
			pickerValue.rot = math.round(n)
			commitPicker()
		end

		refreshPicker()
	end)

	flatBtn.MouseButton1Click:Connect(function()
		if #pickerValue.stops > 1 then
			pickerValue.stops = { pickerValue.stops[1] }
			pickerValue.rot = nil
			pickerStop = 1
			commitPicker()
		end

		refreshPicker()
	end)
	gradBtn.MouseButton1Click:Connect(function()
		if #pickerValue.stops == 1 then
			pickerValue.stops =
				{ pickerValue.stops[1], pickerValue.stops[1]:Lerp(Color3.new(0, 0, 0), 0.5) }
			pickerValue.rot = pickerValue.rot or 90
			commitPicker()
		end

		refreshPicker()
	end)
	stopA.MouseButton1Click:Connect(function()
		pickerStop = 1
		refreshPicker()
	end)
	stopB.MouseButton1Click:Connect(function()
		pickerStop = 2
		refreshPicker()
	end)
	doneBtn.MouseButton1Click:Connect(function()
		closePicker()
	end)
	cancelBtn.MouseButton1Click:Connect(function()
		if pickerSnapshot then
			Theme.load(pickerSnapshot)
			refreshCards()
		end

		closePicker()
	end)

	picker:SetAttribute("RefreshPicker", true)
	Customize._refreshPicker = refreshPicker
end

closePicker = function()
	if picker and picker.Visible then
		WindowFX.shrink(picker, function()
			picker.Visible = false
			pickerKey = nil
			pickerValue = nil
		end)
	else
		pickerKey = nil
		pickerValue = nil
	end
end

local function openPicker(key)
	pickerKey = key
	pickerValue = currentValueFor(key)
	pickerSnapshot = Theme.encode()
	pickerStop = 1
	positionPicker()
	Customize._refreshPicker()
	Theme.applyTree(picker)
	picker.Visible = true
	WindowFX.pop(picker)
end

local function openBackgroundLayout()
	if layoutTool and not layoutTool.closed then
		return
	end

	if not window or not window.Visible or closing then
		return
	end

	closePicker()
	if modal then
		modal:Destroy()
		modal = nil
	end

	local tool
	tool = Tool.new(
		windowRefs,
		"EclipseBackgroundLayout",
		"BACKGROUND LAYOUT",
		Vector2.new(300, 214),
		false,

		function()
			if layoutTool == tool then
				layoutTool = nil
			end
		end,
		{ AllowMainMenu = true }
	)
	layoutTool = tool
	local panel, boxes = tool.frame, {}
	local fitLabel
	local fitNames = { Crop = "FILL", Fit = "FIT", Stretch = "STRETCH" }

	local function refresh()
		local layout = Theme.getBackgroundLayout()
		if fitLabel then fitLabel.Text = "MODE: " .. fitNames[layout.fit] end
		for key, box in boxes do
			box.Text = tostring(math.round(layout[key] * 100))
		end
	end

	for i, row in
		{
			{ "scale", "Scale (%)", 25, 200 },
			{ "x", "Horizontal (%)", -100, 100 },
			{ "y", "Vertical (%)", -100, 100 },
		}
	do
		local key, y = row[1], 38 + (i - 1) * 32
		Tool.label(
			panel,
			key .. "Label",
			row[2],
			UDim2.fromOffset(12, y),
			UDim2.fromOffset(166, 24)
		)
		local box = Tool.field(panel, key, "", UDim2.fromOffset(184, y), UDim2.fromOffset(104, 24))
		boxes[key] = box
		require("NumericInput").connect(box, { step = 1, min = row[3], max = row[4] }, function()
			if tool.closed then
				return
			end

			local n = tonumber(box.Text)
			if n then
				local layout = Theme.getBackgroundLayout()
				layout[key] = n / 100
				Theme.setBackgroundLayout(layout)
			end

			refresh()
		end)
	end

	local _, label = Tool.button(panel, "FitMode", "MODE: FILL", UDim2.fromOffset(12, 138), UDim2.fromOffset(276, 28), function()
		local layout = Theme.getBackgroundLayout()
		layout.fit = ({ Crop = "Fit", Fit = "Stretch", Stretch = "Crop" })[layout.fit]
		Theme.setBackgroundLayout(layout)
		refresh()
	end)
	fitLabel = label
	Tool.button(panel, "Reset", "RESET", UDim2.fromOffset(12, 174), UDim2.fromOffset(132, 28), function()
		if tool.closed then
			return
		end

		Theme.setBackgroundLayout({})
		refresh()
	end
)
	Tool.button(panel, "Done", "DONE", UDim2.fromOffset(156, 174), UDim2.fromOffset(132, 28), function()
		tool:close()
	end
)
	table.insert(
		tool.connections,
		window:GetPropertyChangedSignal("Visible"):Connect(function()
			if not window.Visible then
				tool:close()
			end
		end)
	)
	table.insert(
		tool.connections,
		window.Destroying:Connect(function()
			tool:close(true)
		end)
	)
	table.insert(
		tool.connections,
		screenGui.Destroying:Connect(function()
			tool:close(true)
		end)
	)
	table.insert(
		tool.connections,
		require("UserInputService").InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				tool:close()
			end
		end)
	)
	refresh()
end

local function buildCard(setting, order)
	local card = mk("Frame", {
		Name = setting.key,
		LayoutOrder = order,
		BackgroundColor3 = CARD_BG,
		BackgroundTransparency = 0.25,
	}, scroll)
	corner(card, 6)
	local cardStroke = mk(
		"UIStroke",
		{ Color = Color3.fromRGB(90, 50, 140), Transparency = 0.7, Thickness = 1 },
		card
	)
	card:SetAttribute("ThemeBg", "Pnl")
	cardStroke:SetAttribute("ThemeStrk", "Strk")

	local entry = { setting = setting }

	if setting.kind == "image" then
		tagText(mk("TextLabel", {
			Size = UDim2.new(1, -66, 0, 12),
			Position = UDim2.fromOffset(8, 6),
			BackgroundTransparency = 1,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 8,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = setting.label,
		}, card))
		local idBox = tagField(mk("TextBox", {
			Name = "BackgroundAssetId",
			Size = UDim2.new(1, -58, 0, 16),
			Position = UDim2.fromOffset(8, 17),
			BackgroundColor3 = FIELD_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 9,
			Text = "",
			PlaceholderText = "rbxassetid://...",
			ClearTextOnFocus = false,
		}, card))
		corner(idBox, 4)
		local gif = mk("TextButton", {
			Name = "GIF",
			Text = "GIF",
			Position = UDim2.new(1, -42, 0, 36),
			Size = UDim2.fromOffset(34, 10),
			BackgroundColor3 = CHIP_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 9,
			BorderSizePixel = 0,
		}, card)
		corner(gif, 3)
		gif:SetAttribute("ThemeBg", "MenuSel")
		gif:SetAttribute("ThemeTxt", "Txt")
		local image = mk("TextButton", {
			Name = "IMAGE",
			Text = "IMAGE",
			Position = UDim2.new(1, -94, 0, 36),
			Size = UDim2.fromOffset(44, 10),
			BackgroundColor3 = CHIP_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 9,
			BorderSizePixel = 0,
		}, card)
		corner(image, 3)
		image:SetAttribute("ThemeBg", "TopBtn")
		image:SetAttribute("ThemeTxt", "Txt")
		local layout = mk("TextButton", {
			Name = "LAYOUT",
			Text = "LAYOUT",
			Position = UDim2.new(1, -154, 0, 36),
			Size = UDim2.fromOffset(52, 10),
			BackgroundColor3 = CHIP_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 9,
			BorderSizePixel = 0,
		}, card)
		corner(layout, 3)
		layout:SetAttribute("ThemeBg", "TopBtn")
		layout:SetAttribute("ThemeTxt", "Txt")
		layout.Activated:Connect(openBackgroundLayout)
		image.Activated:Connect(function()
			Theme.setBackgroundMode("image")
			entry.refresh()
		end)
		gif.Activated:Connect(function()
			Theme.setBackgroundMode("gif")
			entry.refresh()
			GifEditor.open(screenGui, Theme.getOverride("Img"), function(frames)
				local previous = Theme.getOverride("Img")
				local applied = Theme.set("Img", {
					frames = frames,
					layout = previous and previous.layout,
					mode = frames and "gif" or "image",
					image = previous and previous.image or (frames and frames[1].image) or "",
					t = previous and previous.t or 0.85,
					stops = { Color3.new(1, 1, 1) },
				})
				entry.refresh()
				return applied
			end)
		end)
		local localImage = mk("TextButton", {
			Name = "LocalImage",
			Text = "LOCAL",
			Position = UDim2.fromOffset(8, 36),
			Size = UDim2.fromOffset(44, 10),
			BackgroundColor3 = CHIP_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 9,
			BorderSizePixel = 0,
		}, card)
		corner(localImage, 3)
		localImage:SetAttribute("ThemeBg", "TopBtn")
		localImage:SetAttribute("ThemeTxt", "Txt")
		local importing = false
		localImage.Activated:Connect(function()
			if importing then return end
			importing = true
			localImage.Interactable = false
			local id, message = require("Upload").promptLocal()
			importing = false
			if not localImage.Parent then return end
			localImage.Interactable = true
			if id then
				local value = copyValue(Theme.getOverride("Img")) or { stops = { Color3.new(1, 1, 1) }, t = 0.85 }
				value.image, value.mode = id, "image"
				Theme.set("Img", value)
				entry.refresh()
			end
			if message then require("Notification").show("LOCAL IMAGE", message, 7) end
		end)
		local tBox = tagField(mk("TextBox", {
			Name = "Transparency",
			Size = UDim2.fromOffset(34, 16),
			Position = UDim2.new(1, -42, 0, 17),
			BackgroundColor3 = FIELD_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 10,
			Text = "0",
			ClearTextOnFocus = false,
		}, card))
		corner(tBox, 4)

		local function commitImage()
			local id = fieldText(idBox):gsub("%s", "")
			if tonumber(id) then
				id = "rbxassetid://" .. id
			end

			local t = math.clamp(tonumber(fieldText(tBox)) or 0.85, 0, 1)
			local previous = Theme.getOverride("Img")
			local value = copyValue(previous) or { stops = { Color3.new(1, 1, 1) } }
			value.t = t
			if not (value.frames and value.mode ~= "image") then
				value.image = id
				value.mode = "image"
			end

			Theme.set("Img", value)
		end

		idBox.FocusLost:Connect(commitImage)
		require("NumericInput").connect(tBox, { step = 0.05, min = 0, max = 1 }, function()
			local value = tonumber(tBox.Text)
			if value then
				Theme.setBackgroundTransparency(value)
			end

			entry.refresh()
		end)

		entry.refresh = function()
			local ov = Theme.getOverride("Img")
			local playing = ov and ov.frames and ov.mode ~= "image"
			setFieldText(idBox, playing and "GIF OCCUPIED" or (ov and ov.image) or "")
			idBox.TextEditable = not playing
			gif:SetAttribute("ThemeBg", playing and "MenuSel" or "TopBtn")
			image:SetAttribute("ThemeBg", playing and "TopBtn" or "MenuSel")
			Theme.applyInstance(gif)
			Theme.applyInstance(image)
			setFieldText(tBox, tostring((ov and ov.t) or 0.85))
		end
	else
		local swatch = mk("ImageButton", {
			Name = "Swatch",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(8, 10),
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, card)
		corner(swatch, 5)
		mk(
			"UIStroke",
			{ Color = Color3.fromRGB(255, 255, 255), Transparency = 0.75, Thickness = 1 },
			swatch
		)
		mk("UIGradient", { Name = "SwatchGradient", Enabled = false }, swatch)

		tagText(mk("TextLabel", {
			Size = UDim2.new(1, -100, 0, 12),
			Position = UDim2.fromOffset(44, 8),
			BackgroundTransparency = 1,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = setting.label,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, card))
		tagText(
			mk("TextLabel", {
				Size = UDim2.new(1, -54, 0, 18),
				Position = UDim2.fromOffset(44, 22),
				BackgroundTransparency = 1,
				TextColor3 = TXT_DIM,
				FontFace = FONT,
				TextSize = 8,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Text = setting.desc,
				TextWrapped = true,
			}, card),
			-0.35
		)

		local tBox = tagField(mk("TextBox", {
			Size = UDim2.fromOffset(34, 16),
			Position = UDim2.new(1, -42, 0, 8),
			BackgroundColor3 = FIELD_BG,
			TextColor3 = TXT,
			FontFace = FONT,
			TextSize = 10,
			Text = "0",
			ClearTextOnFocus = false,
		}, card))
		corner(tBox, 4)

		swatch.MouseButton1Click:Connect(function()
			suppressPickerClose = true
			openPicker(setting.key)
			task.delay(0.05, function()
				suppressPickerClose = false
			end)
		end)
		swatch.MouseButton2Click:Connect(function()
			Theme.clear(setting.key)
			refreshCards()
		end)
		require("NumericInput").connect(tBox, { step = 0.05, min = 0, max = 1 }, function()
			local t = tonumber(fieldText(tBox))
			if t then
				local v = currentValueFor(setting.key)
				v.t = math.clamp(t, 0, 1)
				Theme.set(setting.key, v)
			else
				entry.refresh()
			end
		end)

		entry.refresh = function()
			local v = currentValueFor(setting.key)
			paintSwatch(swatch, v)
			setFieldText(
				tBox,
				tostring(v.t or Theme.restingTransparency(baseKeyFor(setting.key)) or 0)
			)
		end
	end

	entry.refresh()
	cards[setting.key] = entry
end

local function rebuildCards()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	table.clear(cards)
	local list = Theme.getMode() == "S" and ThemeConfig.simpleSettings or ThemeConfig.settings
	for order, setting in ipairs(list) do
		buildCard(setting, order)
	end

	modeChip.Text = Theme.getMode() == "S" and "SIMPLE" or "ADVANCED"
end

Customize._rebuildCards = rebuildCards

local function loadUserPresets()
	userPresets = {}
	local raw = getSetting and getSetting(ThemeConfig.presetsKey)
	local decoded = nil
	if typeof(raw) == "string" and raw ~= "" then
		pcall(function()
			decoded = HttpService:JSONDecode(raw)
		end)
	end

	for i = 1, ThemeConfig.maxUserPresets do
		local e = typeof(decoded) == "table" and decoded[i] or nil
		userPresets[i] = {
			name = (e and typeof(e.name) == "string" and e.name) or ("Preset " .. i),
			data = (e and typeof(e.data) == "string" and e.data) or nil,
		}
	end
end

local function saveUserPresets()
	if setSetting then
		setSetting(ThemeConfig.presetsKey, HttpService:JSONEncode(userPresets))
	end
end

local rebuildPresets

local function presetRow(order, name, hasData, tip, onApply, onSaveSlot, onRename)
	local row = mk("TextButton", {
		Size = UDim2.new(1, -6, 0, 24),
		BackgroundColor3 = CARD_BG,
		BackgroundTransparency = 0.25,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = order,
	}, presetsFrame)
	corner(row, 6)
	local rowStroke = mk(
		"UIStroke",
		{ Color = Color3.fromRGB(90, 50, 140), Transparency = 0.7, Thickness = 1 },
		row
	)
	row:SetAttribute("ThemeBg", "Pnl")
	rowStroke:SetAttribute("ThemeStrk", "Strk")
	local nameLbl = tagText(
		mk("TextLabel", {
			Size = UDim2.new(1, -70, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			BackgroundTransparency = 1,
			TextColor3 = hasData and TXT or TXT_DIM,
			FontFace = FONT,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = name,
		}, row),
		hasData and 0 or -0.35
	)

	local status = tagText(mk("TextLabel", {
		Name = "LoadProgress",
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 10,
		FontFace = FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, onSaveSlot and -30 or -8, 0, 0),
		Size = UDim2.new(0, 140, 1, 0),
		Visible = false,
	}, row))
	local request = 0

	local function progressCallback(ticket)
		return function(done, total, state)
			if ticket ~= request or not row.Parent then
				return
			end

			if state == "cancelled" then
				status.Visible = false
				nameLbl.Size = UDim2.new(1, -70, 1, 0)
				return
			end

			status.Visible = true
			nameLbl.Size = UDim2.new(1, onSaveSlot and -180 or -158, 1, 0)
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			local fraction = math.clamp(total == 0 and 1 or done / total, 0, 1)
			local blocks = math.floor(fraction * 10)
			status.Text = state == "partial" and (done .. "/" .. total .. " loaded - retry")
				or state == "failed" and "load failed - see notice"
				or "["
					.. string.rep("=", blocks)
					.. string.rep("-", 10 - blocks)
					.. "] "
					.. math.floor(fraction * 100)
					.. "%"
			if state == "complete" or state == "failed" or state == "partial" then
				task.delay(state ~= "complete" and 8 or 0.5, function()
					if ticket == request and row.Parent then
						status.Visible = false
						nameLbl.Size = UDim2.new(1, -70, 1, 0)
					end
				end)
			end
		end
	end

	local lastClick = 0
	row.MouseButton1Click:Connect(function()
		if onRename and os.clock() - lastClick < 0.4 then
			lastClick = 0
			nameLbl.Visible = false
			local box = mk("TextBox", {
				Size = UDim2.new(1, -70, 1, -6),
				Position = UDim2.fromOffset(10, 3),
				BackgroundColor3 = FIELD_BG,
				TextColor3 = TXT,
				FontFace = FONT,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = nameLbl.Text,
				ClearTextOnFocus = false,
			}, row)
			corner(box, 4)
			task.defer(function()
				box:CaptureFocus()
			end)
			box.FocusLost:Connect(function()
				local newName = box.Text
				box:Destroy()
				nameLbl.Visible = true
				onRename(newName)
			end)
			return
		end

		lastClick = os.clock()
		if onApply then
			request += 1
			onApply(progressCallback(request))
		end
	end)

	if onSaveSlot then
		local sBtn = mk("ImageButton", {
			Size = UDim2.fromOffset(15, 15),
			Position = UDim2.new(1, -24, 0, 4),
			BackgroundTransparency = 1,
			Image = ICON_SAVE,
			ImageColor3 = TXT_DIM,
		}, row)
		sBtn:SetAttribute("ThemeImg", "Txt")
		sBtn:SetAttribute("ThemeShade", -0.35)
		attachTip(sBtn, "Save the current theme into this slot")
		sBtn.MouseButton1Click:Connect(onSaveSlot)
	end
end

rebuildPresets = function()
	if not presetsFrame then
		return
	end

	for _, c in ipairs(presetsFrame:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") or c.Name == "CommunityDivider" then
			c:Destroy()
		end
	end

	local order = 0

	local function header(text)
		order += 1
		tagText(
			mk("TextLabel", {
				Size = UDim2.new(1, -6, 0, 16),
				BackgroundTransparency = 1,
				TextColor3 = TXT_DIM,
				FontFace = FONT,
				TextSize = 9,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = text,
				LayoutOrder = order,
			}, presetsFrame),
			-0.3
		)
	end

	header("Eclipse Presets")
	for _, p in ipairs(ThemeConfig.builtinPresets) do
		order += 1
		presetRow(order, p.name, true, p.desc .. " • Click to apply", function(progress)
			Theme.load(p.data, p.name, progress)
			Customize._rebuildCards()
		end, nil, nil)
	end

	header("Community Presets")
	for _, p in ThemeConfig.communityPresets do
		order += 1
		presetRow(order, p.name, true, p.desc, function(progress)
			Theme.load(p.data, p.name, progress)
			Customize._rebuildCards()
		end, nil, nil)
	end

	header("Your Presets")
	for i, slot in ipairs(userPresets) do
		order += 1
		local tip = slot.data and "Click to apply • Double-click to rename"
			or "Empty • Press the save icon to store the current theme"
		presetRow(order, slot.name, slot.data ~= nil, tip, function(progress)
			if slot.data then
				Theme.load(slot.data, slot.name, progress)
				Customize._rebuildCards()
			end
		end, function()
			slot.data = Theme.encode()
			saveUserPresets()
			rebuildPresets()
		end, function(newName)
			newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
			if newName ~= "" then
				slot.name = newName:sub(1, 24)
			end

			saveUserPresets()
			rebuildPresets()
		end)
	end
end

local function setPresetsView(visible)
	showingPresets = visible
	if presetsFrame then
		presetsFrame.Visible = visible
	end

	if scroll then
		scroll.Visible = not visible
	end

	if visible then
		closePicker()
		rebuildPresets()
	end
end

local function tryClipboard(text)
	local ok = pcall(function()
		game:GetService("StudioService"):CopyToClipboard(text)
	end)
	if not ok then
		ok = pcall(function()
			setclipboard(text)
		end)
	end

	return ok
end

local function showModal(titleText, prefill, buttonText, onConfirm)
	if modal then
		modal:Destroy()
	end

	modal = mk("Frame", {
		Size = UDim2.new(1, -20, 0, 96),
		Position = UDim2.new(0, 10, 0.5, -48),
		BackgroundColor3 = Color3.fromRGB(14, 6, 24),
		ZIndex = 40,
	}, window)
	corner(modal, 8)
	local modalStroke =
		mk("UIStroke", { Color = Color3.fromRGB(140, 80, 210), Transparency = 0.3 }, modal)
	modal:SetAttribute("ThemeBg", "Bg")
	modalStroke:SetAttribute("ThemeStrk", "Strk")
	tagText(mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 6),
		BackgroundTransparency = 1,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 12,
		Text = titleText,
		ZIndex = 41,
	}, modal))
	local box = tagField(mk("TextBox", {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 28),
		BackgroundColor3 = FIELD_BG,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 9,
		Text = prefill or "",
		PlaceholderText = "Paste preset JSON here",
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 41,
	}, modal))
	corner(box, 5)
	local confirm = mk("TextButton", {
		Size = UDim2.new(0.5, -15, 0, 22),
		Position = UDim2.fromOffset(10, 62),
		BackgroundColor3 = Color3.fromRGB(100, 0, 151),
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 10,
		Text = buttonText,
		ZIndex = 41,
	}, modal)
	corner(confirm, 5)
	confirm:SetAttribute("ThemeBg", "MenuSel")
	local cancel = mk("TextButton", {
		Size = UDim2.new(0.5, -15, 0, 22),
		Position = UDim2.new(0.5, 5, 0, 62),
		BackgroundColor3 = FIELD_BG,
		TextColor3 = TXT_DIM,
		FontFace = FONT,
		TextSize = 10,
		Text = "CLOSE",
		ZIndex = 41,
	}, modal)
	corner(cancel, 5)
	cancel:SetAttribute("ThemeBg", "Pnl")
	cancel:SetAttribute("ThemeShade", -0.45)
	cancel:SetAttribute("ThemeTxt", "Txt")

	if prefill and prefill ~= "" then
		box:SetAttribute("PreserveTextOnFocus", true)
		task.defer(function()
			box:CaptureFocus()
			box.CursorPosition = #box.Text + 1
			box.SelectionStart = 1
		end)
	end

	confirm.MouseButton1Click:Connect(function()
		if onConfirm then
			onConfirm(box)
		end
	end)
	cancel.MouseButton1Click:Connect(function()
		modal:Destroy()
		modal = nil
	end)
end

local function buildWindow()
	window = mk("Frame", {
		Name = "EclipseCustomize",
		Size = UDim2.fromOffset(480, 330),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 25,
	}, screenGui)
	corner(window, 5)

	local surface = mk("Frame", {
		Name = "WindowSurface",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(18, 10, 26),
		BorderSizePixel = 0,
		ZIndex = -1,
	}, window)
	corner(surface, 5)
	surface:SetAttribute("ThemeBg", "Bg")

	local backdrop = mk("Frame", {
		Name = "Backdrop",
		Position = UDim2.fromOffset(4, Chrome.HEIGHT),
		Size = UDim2.new(1, -8, 1, -Chrome.HEIGHT - 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 0,
	}, window)
	corner(backdrop, 5)
	backdrop:SetAttribute("ThemeBgImage", 1)
	local wg = mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 28, 76)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(24, 9, 38)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 4, 19)),
		}),
	}, backdrop)
	wg:SetAttribute("ThemeGrad", "Bg")
	local bdStroke = mk(
		"UIStroke",
		{ Color = Color3.fromRGB(120, 70, 180), Transparency = 0.35, Thickness = 1 },
		surface
	)
	bdStroke:SetAttribute("ThemeStrk", "Strk")

	local bar, title, drag = Chrome.header(window, "CUSTOMIZATION", 1, 282)
	bar.Name = "Bar"

	local chipGradient = function(chip)
		Theme.separateButtonText(chip)
	end

	presetsChip = mk("TextButton", {
		Size = UDim2.fromOffset(66, 18),
		Position = UDim2.new(1, -268, 0, 5),
		BackgroundColor3 = CHIP_BG,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 9,
		Text = "PRESETS",
	}, bar)
	presetsChip:SetAttribute("ThemeBg", "MenuSel")
	presetsChip:SetAttribute("ThemeTxt", "TopT")
	corner(presetsChip, 2)
	chipGradient(presetsChip)
	attachTip(presetsChip, "Built-in themes + your own saved presets")

	modeChip = mk("TextButton", {
		Size = UDim2.fromOffset(78, 18),
		Position = UDim2.new(1, -196, 0, 5),
		BackgroundColor3 = CHIP_BG,
		TextColor3 = TXT,
		FontFace = FONT,
		TextSize = 9,
		Text = "ADVANCED",
	}, bar)
	modeChip:SetAttribute("ThemeBg", "MenuSel")
	modeChip:SetAttribute("ThemeTxt", "TopT")
	corner(modeChip, 2)
	chipGradient(modeChip)
	attachTip(modeChip, function()
		return Theme.getMode() == "A" and "Switch to simple for easier customization"
			or "Switch to advanced for more options"
	end)

	local function iconBtn(image, xOff)
		local b = mk("ImageButton", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, xOff, 0, 5),
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = Color3.new(1, 1, 1),
		}, bar)
		b:SetAttribute("ThemeImg", "TopT")
		return b
	end

	local resetBtn = iconBtn(ICON_RESET, -110)
	local saveBtn = iconBtn(ICON_SAVE, -85)
	local loadBtn = iconBtn(ICON_LOAD, -60)

	local closeBtn = Chrome.close(bar, nil, 4)

	attachTip(resetBtn, "Reset every color to default")
	attachTip(saveBtn, "Copy this theme to your clipboard")
	attachTip(loadBtn, "Load a theme from JSON")
	attachTip(closeBtn, "Close")

	resetHint = mk("TextLabel", {
		Size = UDim2.fromOffset(150, 14),
		Position = UDim2.new(1, -196, 0, 28),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(255, 170, 170),
		FontFace = FONT,
		TextSize = 9,
		Text = "Press again to reset",
		Visible = false,
		ZIndex = 26,
	}, window)

	scroll = mk("ScrollingFrame", {
		Name = "Cards",
		Size = UDim2.new(1, -16, 1, -40),
		Position = UDim2.fromOffset(8, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(150, 100, 220),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, window)
	scroll:SetAttribute("ThemeScr", "Scr")
	grid = mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 48),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	mk("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingTop = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
	}, scroll)

	presetsFrame = mk("ScrollingFrame", {
		Name = "Presets",
		Size = UDim2.new(1, -16, 1, -40),
		Position = UDim2.fromOffset(8, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(150, 100, 220),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Visible = false,
	}, window)
	presetsFrame:SetAttribute("ThemeScr", "Scr")
	mk(
		"UIListLayout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder },
		presetsFrame
	)
	mk("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingTop = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
	}, presetsFrame)

	presetsChip.MouseButton1Click:Connect(function()
		setPresetsView(not showingPresets)
	end)

	Chrome.bindDrag(window, drag, {
		changed = function()
			if picker.Visible then
				positionPicker()
			end
		end,
	})

	modeChip.MouseButton1Click:Connect(function()
		Theme.setMode(Theme.getMode() == "S" and "A" or "S")
		closePicker()
		rebuildCards()
	end)

	resetBtn.MouseButton1Click:Connect(function()
		if os.clock() - lastResetPress < 2.5 then
			lastResetPress = 0
			resetHint.Visible = false
			Theme.resetAll()
			closePicker()
			refreshCards()
		else
			lastResetPress = os.clock()
			resetHint.Visible = true
			task.delay(2.5, function()
				if os.clock() - lastResetPress >= 2.4 then
					resetHint.Visible = false
				end
			end)
		end
	end)

	saveBtn.MouseButton1Click:Connect(function()
		local encoded = Theme.encode()
		if tryClipboard(encoded) then
			showModal("Preset copied to clipboard!", encoded, "COPY AGAIN", function(box)
				tryClipboard(box.Text)
			end)
		else
			showModal("Save Preset - press CTRL+C", encoded, "SELECT ALL", function(box)
				box:CaptureFocus()
				box.CursorPosition = #box.Text + 1
				box.SelectionStart = 1
			end)
		end
	end)

	loadBtn.MouseButton1Click:Connect(function()
		showModal("Load Preset", "", "LOAD", function(box)
			if Theme.load(box.Text) then
				modal:Destroy()
				modal = nil
				closePicker()
				rebuildCards()
			else
				box.Text = ""
				box.PlaceholderText = "Invalid preset JSON, try again"
			end
		end)
	end)

	closeBtn.MouseButton1Click:Connect(function()
		Customize.close()
	end)

	buildPicker()
end

function Customize.open()
	if not window or window.Visible and not closing then
		return
	end

	closing = false
	setPresetsView(false)
	rebuildCards()
	Theme.applyTree(window)
	WindowFX.pop(window)
	window.Visible = true
end

function Customize.close()
	if layoutTool then
		layoutTool:close()
	end

	if not window or not window.Visible or closing then
		return
	end

	closing = true
	closePicker()
	if modal then
		modal:Destroy()
		modal = nil
	end

	WindowFX.shrink(window, function()
		window.Visible = false
		closing = false
	end)
end

function Customize.init(refs)
	if initialized then
		return
	end

	screenGui = refs and refs.ScreenGui
	if not screenGui then
		return
	end

	windowRefs = refs
	getSetting = refs.GetSetting
	setSetting = refs.SetSetting
	initialized = true
	loadUserPresets()
	buildWindow()
end

return Customize
