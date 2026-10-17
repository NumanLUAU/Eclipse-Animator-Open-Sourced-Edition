--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local UserInputService = require("UserInputService")
local Theme = require("Theme")
local WindowFX = require("WindowFX")

local Confirm = {}
local session

local function make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function tag(object, attribute, key)
	object:SetAttribute(attribute, key)
	return object
end

local function round(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius) })
end

function Confirm.close(immediate, accepted)
	local current = session
	if not current then
		return
	end

	if current.closing then
		if immediate and current.finish then
			current.finish(false)
		end

		return
	end

	current.closing = true

	local function finish(allowAccept)
		if current.finished then
			return
		end

		current.finished = true
		if session == current then
			session = nil
			current.root:SetAttribute("EclipseConfirmationOpen", nil)
		end

		for _, connection in current.connections do
			connection:Disconnect()
		end

		WindowFX.clear(current.window)
		current.overlay:Destroy()
		if allowAccept and current.accept then
			current.accept()
		end
	end

	current.finish = finish
	if immediate then
		finish(accepted == true)
	else
		WindowFX.shrink(current.window, function()
			finish(accepted == true)
		end)
	end
end

local function build(root, template, title, message, acceptLabel, accepted)
	local fontSource = template and template:FindFirstChild("Title", true)
	local font = fontSource and fontSource.FontFace
		or Font.new("rbxasset://fonts/families/RobotoMono.json")
	local overlay = make("TextButton", root, "EclipseConfirmation", {
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 300,
	})
	const fit = make("Frame", overlay, "Fit", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(354, 204),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 301,
	})
	const fitScale = make("UIScale", fit, "FitScale", {})
	local function refit()
		const area, current = overlay.AbsoluteSize, math.max(fitScale.Scale, 0.001)
		const natural = fit.AbsoluteSize / current
		if area.X <= 0 or area.Y <= 0 or natural.X <= 0 or natural.Y <= 0 then
			return
		end

		fitScale.Scale = math.clamp(
			math.min((area.X - 16) / natural.X, (area.Y - 16) / natural.Y),
			0.35,
			1
		)
	end

	local window = tag(
		make("Frame", fit, "Window", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(354, 204),
			BackgroundColor3 = Color3.fromRGB(23, 17, 29),
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 301,
		}),
		"ThemeBg",
		"Bg"
	)
	round(window, 7)
	tag(
		make("UIStroke", window, "Outline", {
			Color = Color3.fromRGB(87, 59, 106),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		"ThemeStrk",
		"Strk"
	)
	local header = tag(
		make("Frame", window, "Header", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(49, 16, 65),
			BorderSizePixel = 0,
			ZIndex = 302,
		}),
		"ThemeBg",
		"Top"
	)
	round(header, 7)
	tag(
		make("Frame", header, "LowerEdge", {
			Size = UDim2.new(1, 0, 0, 7),
			Position = UDim2.new(0, 0, 1, -7),
			BackgroundColor3 = header.BackgroundColor3,
			BorderSizePixel = 0,
			ZIndex = 302,
		}),
		"ThemeBg",
		"Top"
	)

	local function label(parent, name, text, position, size, textSize)
		return tag(
			make("TextLabel", parent, name, {
				Text = text,
				Position = position,
				Size = size,
				FontFace = font,
				TextSize = textSize,
				TextColor3 = Color3.fromRGB(235, 229, 240),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				RichText = false,
				ZIndex = 303,
			}),
			"ThemeTxt",
			"Txt"
		)
	end

	label(header, "Title", title, UDim2.fromOffset(14, 0), UDim2.new(1, -50, 1, 0), 13)
	local body =
		label(window, "Message", message, UDim2.fromOffset(16, 50), UDim2.new(1, -32, 0, 90), 14)
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top

	local function button(name, text, position, size, danger)
		local object = make("TextButton", window, name, {
			Text = text,
			Position = position,
			Size = size,
			FontFace = font,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(240, 235, 244),
			BackgroundColor3 = danger and Color3.fromRGB(139, 50, 62) or Color3.fromRGB(48, 32, 60),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			ZIndex = 304,
		})
		if not danger then
			tag(object, "ThemeBg", "TopBtn")
			tag(object, "ThemeTxt", "Txt")
		end

		round(object, 5)
		return object
	end

	local cancel = button("Cancel", "Cancel", UDim2.new(1, -230, 1, -46), UDim2.fromOffset(94, 30))
	local accept =
		button("Confirm", acceptLabel, UDim2.new(1, -124, 1, -46), UDim2.fromOffset(108, 30), true)
	local close = require("Chrome").close(window, nil, 304)
	session =
		{ root = root, overlay = overlay, window = window, accept = accepted, connections = {} }
	root:SetAttribute("EclipseConfirmationOpen", true)
	table.insert(session.connections, overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit))
	refit()
	cancel.Activated:Connect(function()
		Confirm.close()
	end)
	close.Activated:Connect(function()
		Confirm.close()
	end)
	accept.Activated:Connect(function()
		Confirm.close(false, true)
	end)
	table.insert(
		session.connections,
		UserInputService.InputBegan:Connect(function(input)
			if Shortcuts.matches("Cancel", input) then
				Confirm.close()
			end
		end)
	)
	Theme.addRoot(window)
	WindowFX.pop(window)
	return window
end

function Confirm.open(root, template, title, message, acceptLabel, accepted)
	Confirm.close(true)
	if not root or not root.Parent then
		return
	end

	const ok, result = pcall(build, root, template, title, message, acceptLabel, accepted)
	if ok then
		return result
	end

	const current = session
	session = nil
	if current then
		for _, connection in current.connections do
			connection:Disconnect()
		end
	end

	root:SetAttribute("EclipseConfirmationOpen", nil)
	const leftover = root:FindFirstChild("EclipseConfirmation")
	if leftover then
		leftover:Destroy()
	end

	warn("Eclipse confirmation could not open: " .. tostring(result))
end

return Confirm
