--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Surface = {}

local function make(class, parent, name, props)
	local object = Instance.new(class)

	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

function Surface.fill(frame, key)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame:SetAttribute("ThemeBg", key or "Bg")
	local gradient = frame:FindFirstChild("SurfaceGradient")
		or make("UIGradient", frame, "SurfaceGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(29, 17, 40), Color3.fromRGB(13, 8, 21)),
		})
	gradient:SetAttribute("ThemeGrad", key or "Bg")
	if not frame:FindFirstChildOfClass("UICorner") then
		make("UICorner", frame, "Corner", { CornerRadius = UDim.new(0, 5) })
	end

	return frame
end

function Surface.backdrop(group, outline)
	group.BackgroundTransparency = 1
	group:SetAttribute("ThemeBg", nil)
	local frame =
		make("Frame", group, "Backdrop", { Size = UDim2.fromScale(1, 1), ZIndex = group.ZIndex })
	Surface.fill(frame)
	if outline then
		local stroke = make(
			"UIStroke",
			frame,
			"Outline",
			{ Color = Color3.fromRGB(69, 41, 93), Transparency = 0.25, Thickness = 1 }
		)
		stroke:SetAttribute("ThemeStrk", "Strk")
	end

	return frame
end

function Surface.halftone(parent)
	local pattern = make("Frame", parent, "Halftone", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(144, 108),
		BackgroundTransparency = 1,
		ZIndex = parent.ZIndex + 1,
	})
	for row = 0, 9 do
		for column = 0, 12 do
			local strength = math.max(0, 1 - math.sqrt((column / 13) ^ 2 + (row / 10) ^ 2))
			if strength > 0.08 then
				local diameter = 1 + 3.5 * strength
				local dot = make("Frame", pattern, "Dot", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(1, -4 - column * 11 - (row % 2) * 5.5, 1, -4 - row * 10),
					Size = UDim2.fromOffset(diameter, diameter),
					BorderSizePixel = 0,
					BackgroundColor3 = Color3.fromRGB(235, 228, 242),
					BackgroundTransparency = 0.85 + 0.12 * (1 - strength),
					ZIndex = pattern.ZIndex,
				})
				dot:SetAttribute("ThemeBg", "Txt")
				make("UICorner", dot, "Round", { CornerRadius = UDim.new(1, 0) })
			end
		end
	end

	return pattern
end

return Surface
