--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Theme = require("Theme")
local Style = require("Style")
local Motion = require("Motion")
local Chrome = {
	HEIGHT = 28,
	CLOSE_ICON = "rbxassetid://117305983275957",
	UPLOAD_ICON = "rbxassetid://136557548941861",
	IMAGE_ICON = "rbxassetid://119386712211813",
}
Chrome.FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local function make(class, parent, name, props)
	local o = Instance.new(class)

	o.Name = name
	for k, v in props do
		o[k] = v
	end

	o.Parent = parent
	return o
end

local function round(o, r)
	make("UICorner", o, "Corner", { CornerRadius = UDim.new(0, r) })
end

function Chrome.close(parent, callback, z)
	local b = make("ImageButton", parent, "Close", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -30, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Image = "",
		ZIndex = z or parent.ZIndex + 3,
	})
	round(b, 2)
	local g = make("UIGradient", b, "ControlGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(172, 155, 195), Color3.fromRGB(103, 86, 128)),
	})
	g:SetAttribute("ThemeGrad", "Ctrl")
	local icon = make("ImageLabel", b, "Icon", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(3, 3),
		BackgroundTransparency = 1,
		Image = Chrome.CLOSE_ICON,
		ImageColor3 = Color3.fromRGB(38, 26, 52),
		ZIndex = b.ZIndex + 1,
	})
	icon:SetAttribute("ThemeImg", "CtrlIc")
	if callback then
		b.Activated:Connect(callback)
	end

	Theme.applyInstance(g)
	Theme.applyInstance(icon)
	return b
end

function Chrome.header(window, title, z, reserved)
	z = z or window.ZIndex + 1
	local header = make("Frame", window, "Header", {
		Size = UDim2.new(1, 0, 0, Chrome.HEIGHT),
		BackgroundColor3 = Color3.fromRGB(20, 8, 32),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = z,
	})
	round(header, 5)
	header:SetAttribute("ThemeBg", "Top")
	local text = make("TextLabel", header, "Title", {
		Text = title,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -(reserved or 42), 1, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		FontFace = Chrome.FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z + 1,
	})
	text:SetAttribute("ThemeTxt", "TopT")
	local drag = make("TextButton", header, "WindowDrag", {
		Text = "",
		Position = text.Position,
		Size = text.Size,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = z + 2,
	})
	Theme.applyInstance(header)
	Theme.applyInstance(text)
	return header, text, drag
end

function Chrome.menuButton(parent, name, value, position, size, z)
	local b = make("TextButton", parent, name, {
		Text = "",
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(51, 0, 77),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = z or parent.ZIndex + 3,
	})
	round(b, 3)
	b:SetAttribute("ThemeBg", "TopBtn")
	local g = make("UIGradient", b, "SubtleGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196)),
	})
	local label = make("TextLabel", b, "TextLabel", {
		Text = value,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		TextTransparency = 0.4,
		ZIndex = b.ZIndex + 1,
	})
	label:SetAttribute("ThemeTxt", "TopT")
	Theme.applyInstance(b)
	Theme.applyInstance(label)
	local style = Style.bind(b, label)
	b.MouseEnter:Connect(style.hover)
	b.MouseLeave:Connect(style.idle)
	b.MouseButton1Down:Connect(style.open)
	b.MouseButton1Up:Connect(style.hover)
	return b, label
end

Chrome.scale = Motion.scale

function Chrome.bindDrag(window, handle, options)
	Motion.resetOnOpen(window)
	options = options or {}
	local gesture
	local connection = handle.InputBegan:Connect(function(input)
		if options.disabled and options.disabled() then
			return
		end

		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		if options.began then
			options.began()
		end

		local start, position, scale = input.Position, window.Position, Motion.scale(window)
		local parent = Motion.coordinateParent(window)
		if not parent then
			return
		end

		local viewport = parent.AbsoluteSize / scale
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end

		local size = Vector2.new(
			window.Size.X.Scale * viewport.X + window.Size.X.Offset,
			window.Size.Y.Scale * viewport.Y + window.Size.Y.Offset
		)
		local anchor = window.AnchorPoint
		local moved = false
		gesture = Motion.begin(window, input, function(point)
			local delta = (point - start) / scale
			if not moved and delta.Magnitude < (options.threshold or 0) then
				return
			end

			moved = true
			local nextPosition = position + UDim2.fromOffset(delta.X, delta.Y)
			nextPosition = options.inside and Motion.inside(nextPosition, size, viewport, anchor)
				or Motion.reachable(nextPosition, size, viewport, anchor, scale)
			if window.Position ~= nextPosition then
				window.Position = nextPosition
				if options.changed then
					options.changed()
				end
			end
		end, function()
			gesture = nil
		end)
	end)

	local function cleanup()
		connection:Disconnect()
		if gesture then
			gesture.finish(true)
		end
	end

	window.Destroying:Once(cleanup)
	return cleanup
end

return Chrome
