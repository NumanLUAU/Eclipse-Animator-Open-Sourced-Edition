--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Icons = {}

function Icons.attach(image, kind)
	local root = Instance.new("Frame")
	root.Name = "VectorIcon"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = image.ZIndex
	local pieces = {}

	local function rect(x, y, width, height, opacity)
		local part = Instance.new("Frame")
		part.BorderSizePixel = 0
		part.Position = UDim2.fromScale(x / 64, y / 64)
		part.Size = UDim2.fromScale(width / 64, height / 64)
		part.ZIndex = root.ZIndex
		part.Active = false
		part.Parent = root
		table.insert(pieces, { part = part, opacity = opacity or 1 })
	end

	if kind == "face" then
		root.Size = UDim2.fromScale(6 / 7, 6 / 7)
		root.Position = UDim2.fromScale(1 / 14, 1 / 14)
	end

	if kind == "face" or kind == "facekey" then
		rect(4, 4, 8, 56)
		rect(52, 4, 8, 56)
		rect(12, 4, 10, 8)
		rect(42, 4, 10, 8)
		rect(12, 52, 10, 8)
		rect(42, 52, 10, 8)
		rect(20, 20, 8, 10)
		rect(36, 20, 8, 10)
		rect(24, 40, 16, 8)
	elseif kind == "event" then
		rect(4, 4, 8, 56)
		rect(52, 4, 8, 56)
		rect(12, 4, 12, 8)
		rect(40, 4, 12, 8)
		rect(12, 52, 12, 8)
		rect(40, 52, 12, 8)
		rect(24, 24, 16, 8)
		rect(24, 32, 16, 8, 0.5)
	else
		rect(8, 10, 5, 44)
		rect(13, 10, 6, 5)
		rect(13, 49, 6, 5)
		rect(51, 10, 5, 44)
		rect(45, 10, 6, 5)
		rect(45, 49, 6, 5)
		local points = {
			Vector2.new(34, 8),
			Vector2.new(20, 35),
			Vector2.new(30, 35),
			Vector2.new(27, 56),
			Vector2.new(44, 27),
			Vector2.new(33, 27),
		}
		for y = 8, 55 do
			local xs = {}
			for i, a in points do
				local b = points[i % #points + 1]
				local scan = y + 0.5
				if (a.Y <= scan and b.Y > scan) or (b.Y <= scan and a.Y > scan) then
					table.insert(xs, a.X + (scan - a.Y) / (b.Y - a.Y) * (b.X - a.X))
				end
			end

			table.sort(xs)
			for i = 1, #xs, 2 do
				rect(xs[i], y, xs[i + 1] - xs[i], 1)
			end
		end
	end

	local function paint()
		root.Visible = kind == "face" or kind == "facekey" or not image.IsLoaded
		for _, piece in pieces do
			piece.part.BackgroundColor3 = image.ImageColor3
			piece.part.BackgroundTransparency = 1 - piece.opacity * (1 - image.ImageTransparency)
		end
	end

	image:GetPropertyChangedSignal("ZIndex"):Connect(function()
		root.ZIndex = image.ZIndex
		for _, piece in pieces do
			piece.part.ZIndex = image.ZIndex
		end
	end)
	image:GetPropertyChangedSignal("ImageColor3"):Connect(paint)
	image:GetPropertyChangedSignal("ImageTransparency"):Connect(paint)
	image:GetPropertyChangedSignal("IsLoaded"):Connect(paint)
	root.Parent = image
	paint()
	return root
end

return Icons
