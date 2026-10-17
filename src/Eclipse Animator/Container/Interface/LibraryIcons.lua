--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Icons = {}

function Icons.book(parent)
	local icon = Instance.new("ImageLabel")

	icon.Name = "Book"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(20, 20)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Image = "rbxassetid://103690539141361"
	icon.ImageColor3 = Color3.fromRGB(235, 228, 242)
	icon:SetAttribute("ThemeImg", "Txt")
	icon.ZIndex = parent.ZIndex + 1
	icon.Parent = parent
	return icon
end

function Icons.gear(parent)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Gear"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(14, 14)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Image = "rbxassetid://93233728223498"
	icon:SetAttribute("ThemeImg", "Txt")
	icon.ZIndex = parent.ZIndex + 1
	icon.Parent = parent
	return icon
end

function Icons.dynamic(parent, kind, size)
	local ids = { trash = "rbxassetid://101065966087803", controls = "rbxassetid://72473799769133", sliders = "rbxassetid://73239604571560", eye = "rbxassetid://90671086059426" }
	local icon = Instance.new("ImageLabel")
	icon.Name = "Dynamic" .. kind
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(size or 14, size or 14)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Image = ids[kind] or ids.controls
	icon:SetAttribute("ThemeImg", "Txt")
	icon.ZIndex = parent.ZIndex + 1
	icon.Parent = parent
	return icon
end

return Icons
