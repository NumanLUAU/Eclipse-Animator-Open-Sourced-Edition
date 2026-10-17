--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local View = {}

function View.tag(frame)
	frame:SetAttribute("ThemeBg", "Bg")
	for _, object in frame:GetDescendants() do
		if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
			object:SetAttribute("ThemeTxt", "Txt")
		end

		if object:IsA("UIStroke") then
			object:SetAttribute("ThemeStrk", "Strk")
		end

		if object.Name == "KeyField" or object.Name == "Activate" then
			object:SetAttribute("ThemeBg", "TopBtn")
		end

		if object.Name == "Header" then
			object:SetAttribute("ThemeBg", "Top")
		end

		if object.Name == "Title" then
			object:SetAttribute("ThemeTxt", "TopT")
		end

		if object.Name == "SurfaceGradient" then
			object:SetAttribute("ThemeGrad", "Bg")
		end

		if object.Name == "ControlGradient" then
			object:SetAttribute("ThemeGrad", "Ctrl")
		end

		if object.Name == "Icon" then
			object:SetAttribute("ThemeImg", "CtrlIc")
		end
	end
end

local function make(class, parent, name, props)
	local object = Instance.new(class)

	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

function View.build(parent)
	local text = Color3.fromRGB(190, 216, 217)
	local line = Color3.fromRGB(59, 96, 105)
	local font = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
	local frame = make("Frame", parent, "KeyEntry", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 224),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 80,
		Active = true,
	})
	frame:SetAttribute("ThemeBg", "Bg")
	make("UIGradient", frame, "SurfaceGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(16, 46, 54), Color3.fromRGB(6, 24, 31)),
	})
	make("UICorner", frame, "Corner", { CornerRadius = UDim.new(0, 4) })
	local stroke = make(
		"UIStroke",
		frame,
		"Outline",
		{ Color = line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	stroke:SetAttribute("ThemeStrk", "Strk")
	local header = make("Frame", frame, "Header", {
		Size = UDim2.new(1, -2, 0, 28),
		Position = UDim2.fromOffset(1, 1),
		BackgroundColor3 = Color3.fromRGB(17, 46, 54),
		BorderSizePixel = 0,
	})
	header:SetAttribute("ThemeBg", "TopBtn")
	make("ImageLabel", header, "Logo", {
		Image = "rbxassetid://126656292244944",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
	})

	local function label(parent, name, words, x, y, w, h, size)
		local item = make("TextLabel", parent, name, {
			Text = words,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			FontFace = font,
			TextSize = size,
			TextColor3 = text,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		item:SetAttribute("ThemeTxt", "Txt")
		return item
	end

	label(header, "Title", "ECLIPSE / EARLY ACCESS", 38, 0, 272, 28, 11)
	local close = make("ImageButton", header, "Close", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -30, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Image = "",
	})
	make("UICorner", close, "Corner", { CornerRadius = UDim.new(0, 2) })
	make("UIGradient", close, "ControlGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(194, 221, 209), Color3.fromRGB(99, 148, 143)),
	})
	make("ImageLabel", close, "Icon", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(3, 3),
		BackgroundTransparency = 1,
		Image = "rbxassetid://117305983275957",
		ImageColor3 = Color3.fromRGB(16, 44, 50),
	})
	label(frame, "Heading", "Activate Eclipse", 16, 49, 328, 24, 17)
	label(frame, "Prompt", "Enter your access key to continue.", 16, 77, 328, 20, 11)
	local field = make("Frame", frame, "KeyField", {
		Position = UDim2.fromOffset(16, 114),
		Size = UDim2.new(1, -32, 0, 24),
		BackgroundColor3 = Color3.fromRGB(25, 61, 70),
		BorderSizePixel = 0,
	})
	field:SetAttribute("ThemeBg", "Input")
	local border = make(
		"UIStroke",
		field,
		"Outline",
		{ Color = line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	border:SetAttribute("ThemeStrk", "Strk")
	local input = make("TextBox", field, "Key", {
		Position = UDim2.fromOffset(5, 0),
		Size = UDim2.new(1, -10, 1, 0),
		Text = "",
		PlaceholderText = "Paste your key",
		ClearTextOnFocus = false,
		MultiLine = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = font,
		TextSize = 13,
		TextColor3 = text,
		PlaceholderColor3 = Color3.fromRGB(114, 146, 154),
		BackgroundTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	input:SetAttribute("ThemeTxt", "Txt")
	local status = label(frame, "Status", "", 16, 147, 328, 23, 10)
	status.TextWrapped = true
	local activate = make("TextButton", frame, "Activate", {
		Position = UDim2.fromOffset(16, 179),
		Size = UDim2.new(1, -32, 0, 29),
		Text = "ACTIVATE",
		FontFace = font,
		TextSize = 12,
		TextColor3 = text,
		BackgroundColor3 = Color3.fromRGB(30, 67, 75),
		BorderSizePixel = 0,
		AutoButtonColor = true,
	})
	activate:SetAttribute("ThemeBg", "TopBtn")
	activate:SetAttribute("ThemeTxt", "Txt")
	make("UICorner", activate, "Corner", { CornerRadius = UDim.new(0, 3) })
	make("UIGradient", activate, "SubtleGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196)),
	})
	View.tag(frame)
	return frame
end

function View.bind(frame, submit, close)
	local input, status, button = frame.KeyField.Key, frame.Status, frame.Activate
	local connections = {}
	local view = { frame = frame, busy = false }

	function view:setStatus(message)
		status.Text = message or ""
	end

	function view:setBusy(value)
		self.busy = value
		button.Text = value and "CHECKING…" or "ACTIVATE"
		button.Active = not value
		button.AutoButtonColor = not value
		input.TextEditable = not value
	end

	function view:submit()
		if self.busy then
			return
		end

		local key = input.Text:match("^%s*(.-)%s*$") or ""
		if key == "" then
			self:setStatus("Enter a key.")
			return
		end

		if #key > 512 or key:find("[%c]") then
			self:setStatus("That key format isn't valid.")
			return
		end

		submit(key, self)
	end

	connections[1] = button.Activated:Connect(function()
		view:submit()
	end)
	connections[2] = input.FocusLost:Connect(function(enter)
		if enter then
			view:submit()
		end
	end)
	connections[3] = frame.Header.Close.Activated:Connect(close)

	function view:clear()
		input.Text = ""
		self:setStatus("")
		self:setBusy(false)
	end

	function view:destroy()
		for _, connection in connections do
			connection:Disconnect()
		end

		table.clear(connections)
	end

	return view
end

return View
