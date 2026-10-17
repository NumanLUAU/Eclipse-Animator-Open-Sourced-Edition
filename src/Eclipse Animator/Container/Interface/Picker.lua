--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Theme = require("Theme")
local UserInputService = require("UserInputService")
local Chrome = require("Chrome")
local Motion = require("Motion")
local FX = require("WindowFX")
local Picker = {}
local closing = {}
local Customize = {}
local picker, pickerValue, pickerSnapshot, pickerStop, screenGui, callback, owner
local connections = {}
local options = {}
local undoStack, redoStack = {}, {}
local lastValue, lastStop, replaying, gesture, gestureRecorded, stopInteraction
local FIELD_BG = Color3.fromRGB(15, 31, 38)
local TXT = Color3.new(1, 1, 1)
local TXT_DIM = Color3.fromRGB(190, 200, 205)
local FONT = Chrome.FONT

local function copy(v)
	return {
		stops = table.clone(v.stops),
		rot = v.rot,
		positions = v.positions and table.clone(v.positions),
		alphas = v.alphas and table.clone(v.alphas),
		mode = v.mode,
	}
end

local function mk(class, props, parent)
	local v = Instance.new(class)
	if v:IsA("GuiObject") then
		v.BorderSizePixel = 0
	end

	for k, p in props do
		v[k] = p
	end

	v.Parent = parent
	return v
end

local function corner(v, n)
	mk("UICorner", { CornerRadius = UDim.new(0, n) }, v)
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

local function tagText(v, shade)
	v:SetAttribute("ThemeTxt", "Txt")
	v:SetAttribute("ThemeShade", shade)
	return v
end

local function accent()
	return Theme.get("MenuSel", Color3.fromRGB(140, 60, 90))
end

local function setFieldText(box, value)
	if not box:IsFocused() then
		box.Text = value
	end
end

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end

	for k in b do
		if a[k] == nil then
			return false
		end
	end

	return true
end

local function beginGesture()
	gesture, gestureRecorded = true, false
	lastStop = pickerStop
end

local function endGesture()
	gesture, gestureRecorded = false, false
end

local function remember()
	if not lastValue or replaying then
		return
	end

	if not same(pickerValue, lastValue) then
		if not gesture or not gestureRecorded then
			table.insert(undoStack, { value = copy(lastValue), stop = lastStop })
			if #undoStack > 200 then
				table.remove(undoStack, 1)
			end

			table.clear(redoStack)
			gestureRecorded = true
		end

		lastValue = copy(pickerValue)
	end

	lastStop = pickerStop
end

local function commitPicker()
	remember()
	if callback and pickerValue and not options.commitOnDone then
		callback(copy(pickerValue))
	end
end

local function closePicker(immediate)
	table.clear(undoStack)
	table.clear(redoStack)
	lastValue, lastStop, stopInteraction = nil, nil, nil
	endGesture()
	for _, c in connections do
		c:Disconnect()
	end

	connections = {}
	local oldGui, oldFrame = screenGui, picker
	screenGui = nil
	picker = nil
	owner = nil
	callback = nil
	if immediate then
		for g, f in closing do
			closing[g] = nil
			FX.clear(f)
			g:Destroy()
		end
	end

	if not oldGui then
		return
	end

	local function dispose()
		closing[oldGui] = nil
		FX.clear(oldFrame)
		oldGui:Destroy()
	end

	oldGui.Name = "EclipseEffectColorPickerClosing"
	if immediate then
		dispose()
	else
		closing[oldGui] = oldFrame
		for _, v in oldFrame:GetDescendants() do
			if v:IsA("GuiObject") then
				v.Interactable = false
			end
		end

		FX.shrink(oldFrame, dispose)
	end
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
			Size = options.drawing and UDim2.fromOffset(52, 18) or UDim2.fromOffset(24, 14),
			Position = options.drawing and UDim2.fromOffset(10 + col * 57, 314 + rowIdx * 22)
				or UDim2.fromOffset(10 + col * 32, 204 + rowIdx * 18),
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
	doneBtn:SetAttribute("ThemeTxt", "Txt")

	local gradRow = { stopA, stopB, rotLabel, rotBox.Parent }
	if options.solid then
		flatBtn.Visible = false
		gradBtn.Visible = false
		for _, child in picker:GetChildren() do
			if child:IsA("GuiObject") and child.Position.Y.Offset >= 204 then
				child.Position -= UDim2.fromOffset(0, 48)
			end
		end

		picker.Size = UDim2.fromOffset(180, 240)
	end

	local drawingChips, previewGradient, positionBox, alphaBox, drawingRamp, draggingStop

	local function metadata()
		pickerValue.positions = pickerValue.positions or {}
		pickerValue.alphas = pickerValue.alphas or {}
		for i = 1, #pickerValue.stops do
			pickerValue.positions[i] = pickerValue.positions[i]
				or (#pickerValue.stops == 1 and 0 or (i - 1) / (#pickerValue.stops - 1))
			pickerValue.alphas[i] = pickerValue.alphas[i] or 1
		end
	end

	if options.drawing then
		metadata()
		picker.Size = UDim2.fromOffset(300, 400)
		hexBox.Parent.Position = UDim2.fromOffset(10, 130)
		hexBox.Parent.Size = UDim2.fromOffset(94, 22)
		hexBox.TextSize = 12
		for i, box in rgbBoxes do
			box.Parent.Position = UDim2.fromOffset(112 + (i - 1) * 62, 130)
			box.Parent.Size = UDim2.fromOffset(54, 22)
			box.TextSize = 12
		end

		sv.Size = UDim2.fromOffset(280, 96)
		hue.Size = UDim2.fromOffset(280, 12)
		flatBtn.Size = UDim2.fromOffset(136, 18)
		gradBtn.Size = UDim2.fromOffset(136, 18)
		gradBtn.Position = UDim2.fromOffset(154, 156)
		stopA.Visible = false
		stopB.Visible = false
		for _, child in picker:GetChildren() do
			if
				child:IsA("GuiObject")
				and child.Position.Y.Offset >= 204
				and child.Position.Y.Offset < 300
			then
				if child.Position.Y.Offset == 258 then
					child.Position =
						UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, 368)
				else
					child.Position += UDim2.fromOffset(64, 112)
				end
			end
		end

		local function button(name, text, x, y, w, fn)
			local b = mk("TextButton", {
				Name = name,
				Text = text,
				FontFace = FONT,
				TextSize = 10,
				TextColor3 = TXT,
				BackgroundColor3 = FIELD_BG,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(w, 22),
				ZIndex = 31,
			}, picker)
			b:SetAttribute("ThemeBg", "Pnl")
			b:SetAttribute("ThemeTxt", "Txt")
			corner(b, 4)
			b.MouseButton1Click:Connect(function()
				fn()
				commitPicker()
				Customize._refreshPicker()
			end)
			return b
		end

		local ramp = mk("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Name = "GradientPreview",
			Position = UDim2.fromOffset(10, 188),
			Size = UDim2.fromOffset(280, 18),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 31,
		}, picker)
		drawingRamp = ramp
		previewGradient = mk("UIGradient", {}, ramp)
		drawingChips = {}
		for i = 1, 8 do
			local b = button("Stop" .. i, "", 18, 197, 16, function()
				pickerStop = i
			end)
			b.Size = UDim2.fromOffset(10, 10)
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.ZIndex = 35
			b.AutoButtonColor = false
			b:SetAttribute("ThemeBg", nil)
			b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
			mk("UIStroke", {
				Name = "SelectionRing",
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Thickness = 2,
				Color = Color3.new(0.1, 0.1, 0.1),
			}, b)
			b.MouseButton1Down:Connect(function()
				pickerStop = i
				draggingStop = i
				beginGesture()
				Customize._refreshPicker()
			end)
			drawingChips[i] = b
		end

		local function field(name, title, x)
			tagText(mk("TextLabel", {
				Name = name .. "Label",
				Text = title,
				FontFace = FONT,
				TextSize = 10,
				TextColor3 = TXT,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(x, 218),
				Size = UDim2.fromOffset(86, 18),
				ZIndex = 31,
			}, picker))
			return tagField(mk("TextBox", {
				Name = name,
				Text = "",
				FontFace = FONT,
				TextSize = 11,
				TextColor3 = TXT,
				BackgroundColor3 = FIELD_BG,
				ClearTextOnFocus = false,
				Position = UDim2.fromOffset(x, 240),
				Size = UDim2.fromOffset(86, 22),
				ZIndex = 31,
			}, picker))
		end

		positionBox = field("StopPosition", "Position %", 10)
		alphaBox = field("StopOpacity", "Opacity %", 107)
		rotLabel.Text = "Angle °"
		rotLabel.Position = UDim2.fromOffset(204, 218)
		rotLabel.Size = UDim2.fromOffset(86, 18)
		rotBox.Parent.Position = UDim2.fromOffset(204, 240)
		rotBox.Parent.Size = UDim2.fromOffset(86, 22)
		local numeric = require("NumericInput")
		numeric.connect(positionBox, { min = 0, max = 100, step = 1 }, function()
			metadata()
			local i = pickerStop
			local n = tonumber(positionBox.Text)
			if n and #pickerValue.stops > 1 then
				pickerValue.positions[i] = math.clamp(
					n / 100,
					i > 1 and pickerValue.positions[i - 1] + 0.00001 or 0,
					i < #pickerValue.stops and pickerValue.positions[i + 1] - 0.00001 or 1
				)
				commitPicker()
			end

			Customize._refreshPicker()
		end)
		numeric.connect(alphaBox, { min = 0, max = 100, step = 1 }, function()
			metadata()
			local n = tonumber(alphaBox.Text)
			if n then
				pickerValue.alphas[pickerStop] = math.clamp(n / 100, 0, 1)
				commitPicker()
			end

			Customize._refreshPicker()
		end)

		local function addStop(at)
			metadata()
			if #pickerValue.stops < 2 then
				return
			end

			at = math.clamp(at, 0, 1)
			for i, position in pickerValue.positions do
				if math.abs(position - at) < 0.00004 then
					pickerStop = i
					return
				end
			end

			if #pickerValue.stops >= 8 then
				return
			end

			local index = 1
			while index <= #pickerValue.positions and pickerValue.positions[index] < at do
				index += 1
			end

			local left = math.max(1, index - 1)
			local right = math.min(#pickerValue.stops, index)
			local span = pickerValue.positions[right] - pickerValue.positions[left]
			local fraction = span > 0
					and math.clamp((at - pickerValue.positions[left]) / span, 0, 1)
				or 0
			local color = pickerValue.stops[left]:Lerp(pickerValue.stops[right], fraction)
			local alpha = pickerValue.alphas[left]
				+ (pickerValue.alphas[right] - pickerValue.alphas[left]) * fraction
			table.insert(pickerValue.stops, index, color)
			table.insert(pickerValue.positions, index, at)
			table.insert(pickerValue.alphas, index, alpha)
			pickerStop = index
		end

		ramp.MouseButton1Down:Connect(function()
			if ramp.AbsoluteSize.X <= 14 then
				return
			end

			addStop(
				(UserInputService:GetMouseLocation().X - ramp.AbsolutePosition.X - 7)
					/ (ramp.AbsoluteSize.X - 14)
			)
			commitPicker()
			Customize._refreshPicker()
		end)
		button("AddStop", "+ STOP", 10, 276, 88, function()
			metadata()
			if #pickerValue.stops < 2 then
				return
			end

			local i = math.min(pickerStop, #pickerValue.stops - 1)
			addStop((pickerValue.positions[i] + pickerValue.positions[i + 1]) / 2)
		end)

		button("RemoveStop", "REMOVE", 106, 276, 88, function()
			if #pickerValue.stops > 2 then
				for _, list in { pickerValue.stops, pickerValue.positions, pickerValue.alphas } do
					table.remove(list, pickerStop)
				end

				pickerStop = math.min(pickerStop, #pickerValue.stops)
			end
		end)
		button("Reverse", "REVERSE", 202, 276, 88, function()
			metadata()
			local old = copy(pickerValue)
			local n = #old.stops
			for i = 1, n do
				pickerValue.stops[i] = old.stops[n - i + 1]
				pickerValue.positions[i] = n == 1 and 0 or 1 - old.positions[n - i + 1]
				pickerValue.alphas[i] = old.alphas[n - i + 1]
			end

			pickerStop = n - pickerStop + 1
		end)
	end

	local function curColor()
		return pickerValue.stops[math.min(pickerStop, #pickerValue.stops)]
	end

	local function setCurColor(c)
		pickerValue.stops[math.min(pickerStop, #pickerValue.stops)] = c
		commitPicker()
	end

	local function refreshPicker(skipHSV)
		if not pickerValue then
			return
		end

		local isGrad = not options.solid and #pickerValue.stops > 1
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

		if options.drawing then
			metadata()
			stopA.Visible = false
			stopB.Visible = false
			local colors, alphas = {}, {}
			for i, c in pickerValue.stops do
				table.insert(colors, ColorSequenceKeypoint.new(pickerValue.positions[i], c))
				table.insert(
					alphas,
					NumberSequenceKeypoint.new(pickerValue.positions[i], 1 - pickerValue.alphas[i])
				)
			end

			if #colors == 1 then
				table.insert(colors, ColorSequenceKeypoint.new(1, pickerValue.stops[1]))
				table.insert(alphas, NumberSequenceKeypoint.new(1, 1 - pickerValue.alphas[1]))
			end

			if colors[1].Time > 0 then
				table.insert(colors, 1, ColorSequenceKeypoint.new(0, colors[1].Value))
				table.insert(alphas, 1, NumberSequenceKeypoint.new(0, alphas[1].Value))
			end

			if colors[#colors].Time < 1 then
				table.insert(colors, ColorSequenceKeypoint.new(1, colors[#colors].Value))
				table.insert(alphas, NumberSequenceKeypoint.new(1, alphas[#alphas].Value))
			end

			previewGradient.Color = ColorSequence.new(colors)
			previewGradient.Transparency = NumberSequence.new(alphas)
			for i, b in drawingChips do
				b.Visible = isGrad and i <= #pickerValue.stops
				if b.Visible then
					b.BackgroundColor3 = pickerValue.stops[i]
					b.Text = ""
					b.Position = UDim2.fromOffset(17 + 266 * pickerValue.positions[i], 197)
					b.SelectionRing.Thickness = pickerStop == i and 2 or 1
					b.SelectionRing.Color = pickerStop == i and Color3.new(1, 1, 1)
						or Color3.new(0.1, 0.1, 0.1)
					b.ZIndex = pickerStop == i and 36 or 35
					local c = b.BackgroundColor3
					b.TextColor3 = c.R * 0.2126 + c.G * 0.7152 + c.B * 0.0722 > 0.55
							and Color3.new()
						or Color3.new(1, 1, 1)
				end
			end

			setFieldText(
				positionBox,
				tostring(math.round(pickerValue.positions[pickerStop] * 1000) / 10)
			)
			positionBox.TextEditable = #pickerValue.stops > 1
			setFieldText(alphaBox, tostring(math.round(pickerValue.alphas[pickerStop] * 100)))
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

	local draggingSV = false
	local draggingHue = false

	stopInteraction = function()
		draggingStop, draggingSV, draggingHue = nil, false, false
		endGesture()
	end

	local function applyStopFromMouse()
		if not draggingStop or not drawingRamp or not pickerValue or #pickerValue.stops < 2 then
			return
		end

		local width = drawingRamp.AbsoluteSize.X
		if width <= 14 then
			return
		end

		local i = draggingStop
		pickerValue.positions[i] = math.clamp(
			(UserInputService:GetMouseLocation().X - drawingRamp.AbsolutePosition.X - 7)
				/ (width - 14),
			i > 1 and pickerValue.positions[i - 1] + 0.00001 or 0,
			i < #pickerValue.stops and pickerValue.positions[i + 1] - 0.00001 or 1
		)
		commitPicker()
		refreshPicker()
	end

	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			endGesture()
			draggingStop = nil
			draggingSV = false
			draggingHue = false
		end)
	)

	local function applySVFromMouse()
		local mp = UserInputService:GetMouseLocation()
		local p = sv.AbsolutePosition
		local sz = sv.AbsoluteSize
		local s = math.clamp((mp.X - p.X) / sz.X, 0, 1)
		local vv = 1 - math.clamp((mp.Y - p.Y) / sz.Y, 0, 1)
		local h = select(1, curColor():ToHSV())
		local baseH = select(1, sv.BackgroundColor3:ToHSV())
		svCursor.Position = UDim2.fromScale(s, 1 - vv)
		setCurColor(Color3.fromHSV(baseH, s, vv))
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
		setCurColor(Color3.fromHSV(h, math.max(s, 0.001), math.max(v, 0.001)))
		refreshPicker(true)
	end

	sv.MouseButton1Down:Connect(function()
		draggingSV = true
		beginGesture()
		applySVFromMouse()
	end)
	hue.MouseButton1Down:Connect(function()
		draggingHue = true
		beginGesture()
		applyHueFromMouse()
	end)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end

			if draggingStop then
				applyStopFromMouse()
			end

			if draggingSV then
				applySVFromMouse()
			end

			if draggingHue then
				applyHueFromMouse()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				endGesture()
				draggingSV = false
				draggingStop = nil
				draggingHue = false
			end
		end)
	)

	hexBox.FocusLost:Connect(function()
		local v = Theme.parseValue(hexBox.Text:gsub("%s", ""))
		if v then
			setCurColor(v.stops[1])
		end

		refreshPicker()
	end)
	for i, box in ipairs(rgbBoxes) do
		require("NumericInput").connect(box, { step = 1, min = 0, max = 255, integer = true }, function()
			local n = tonumber(box.Text)
			if n then
				local c = curColor()
				local rgb = { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
				rgb[i] = math.clamp(math.round(n), 0, 255)
				setCurColor(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
			end

			refreshPicker()
		end
)
	end

	require("NumericInput").connect(rotBox, { step = 1 }, function()
		local n = tonumber(rotBox.Text)
		if n then
			pickerValue.rot = math.clamp(math.round(n), -360, 360)
			if options.drawing then
				pickerValue.mode = "Linear"
			end

			commitPicker()
		end

		refreshPicker()
	end)

	flatBtn.MouseButton1Click:Connect(function()
		if #pickerValue.stops > 1 then
			pickerValue.stops = { pickerValue.stops[pickerStop] }
			pickerValue.alphas = pickerValue.alphas and { pickerValue.alphas[pickerStop] }
			pickerValue.positions = pickerValue.positions and { 0 }
			pickerValue.rot = nil
			pickerStop = 1
			commitPicker()
		end

		refreshPicker()
	end)
	gradBtn.MouseButton1Click:Connect(function()
		if options.solid then
			return
		end

		if #pickerValue.stops == 1 then
			pickerValue.stops =
				{ pickerValue.stops[1], pickerValue.stops[1]:Lerp(Color3.new(0, 0, 0), 0.5) }
			pickerValue.rot = pickerValue.rot or 90
			if options.drawing then
				pickerValue.positions = { 0, 1 }
				pickerValue.alphas = { pickerValue.alphas[1], pickerValue.alphas[1] }
			end

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
		Picker.accept()
	end)
	cancelBtn.MouseButton1Click:Connect(function()
		Picker.cancel()
	end)

	picker:SetAttribute("RefreshPicker", true)
	Customize._refreshPicker = refreshPicker
end

local function restoreHistory(from, to)
	if not picker then
		return false
	end

	if options.alive and not options.alive() then
		closePicker(true)
		return false
	end

	if stopInteraction then
		stopInteraction()
	end

	local entry = table.remove(from)
	if not entry then
		return false
	end

	table.insert(to, { value = copy(pickerValue), stop = pickerStop })
	pickerValue = copy(entry.value)
	pickerStop = math.clamp(entry.stop or 1, 1, #pickerValue.stops)
	replaying = true
	local ok, message = xpcall(function()
		commitPicker()
		Customize._refreshPicker()
	end, debug.traceback)
	replaying = false
	lastValue, lastStop = copy(pickerValue), pickerStop
	if not ok then
		error(message, 0)
	end

	return true
end

function Picker.undo()
	return restoreHistory(undoStack, redoStack)
end

function Picker.redo()
	return restoreHistory(redoStack, undoStack)
end

function Picker.accept()
	if not picker then
		return false
	end

	if options.alive and not options.alive() then
		closePicker(true)
		return false
	end

	if options.commitOnDone and callback then
		callback(copy(pickerValue))
	end

	closePicker()
	return true
end

function Picker.cancel()
	if pickerSnapshot then
		pickerValue = copy(pickerSnapshot)
		commitPicker()
	end

	closePicker()
end

function Picker.close(immediate)
	closePicker(immediate)
end

function Picker.isOpen(anchor)
	return picker ~= nil and (not anchor or owner == anchor)
end

function Picker.open(refs, anchor, value, onChange, config)
	if Picker.isOpen(anchor) then
		closePicker()
		return
	end

	closePicker(true)
	options = config or {}
	owner = anchor
	callback = onChange
	pickerValue = copy(value)
	pickerSnapshot = copy(value)
	pickerStop = 1
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EclipseEffectColorPicker"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = refs.ScreenGui.DisplayOrder + 50
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui:SetAttribute("EclipseOwnedUI", true)
	screenGui.Parent = refs.ScreenGui.Parent
	buildPicker()
	picker.Visible = true
	Theme.applyTree(picker)
	Customize._refreshPicker()
	lastValue, lastStop = copy(pickerValue), pickerStop

	for _, v in picker:GetDescendants() do
		if v:IsA("GuiObject") then
			local d = Vector2.new(0.5, 0.5) - v.AnchorPoint
			local p, s = v.Position, v.Size
			v.Position = UDim2.new(
				p.X.Scale + s.X.Scale * d.X,
				p.X.Offset + s.X.Offset * d.X,
				p.Y.Scale + s.Y.Scale * d.Y,
				p.Y.Offset + s.Y.Offset * d.Y
			)
			v.AnchorPoint = Vector2.new(0.5, 0.5)
		end
	end

	picker.AnchorPoint = Vector2.new(0.5, 0.5)
	local p, size = anchor.AbsolutePosition, anchor.AbsoluteSize
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1920, 1080)
	picker.Position = UDim2.fromOffset(
		math.clamp(
			p.X + size.X + picker.Size.X.Offset / 2 + 10,
			picker.Size.X.Offset / 2,
			math.max(picker.Size.X.Offset / 2, viewport.X - picker.Size.X.Offset / 2)
		),
		math.clamp(
			p.Y + picker.Size.Y.Offset / 2,
			picker.Size.Y.Offset / 2,
			math.max(picker.Size.Y.Offset / 2, viewport.Y - picker.Size.Y.Offset / 2)
		)
	)
	table.insert(
		connections,
		anchor.Destroying:Connect(function()
			closePicker(true)
		end)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				Picker.cancel()
			end
		end)
	)

	if refs.ScreenGui then
		table.insert(
			connections,
			refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not refs.ScreenGui.Enabled then
					closePicker(true)
				end
			end)
		)
	end

	if options.alive then
		table.insert(
			connections,
			game:GetService("RunService").Heartbeat:Connect(function()
				if not options.alive() then
					closePicker(true)
				end
			end)
		)
	end

	FX.pop(picker)
	return picker
end

return Picker
