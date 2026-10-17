--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local ParentingUI = {}

local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local PARENT_COLOR = Color3.fromRGB(97, 255, 197)
local WORLD_COLOR = Color3.fromRGB(255, 198, 103)

function ParentingUI.paint(button, parented)
	button.Text = parented and "P" or "W"
	button.TextColor3 = parented and PARENT_COLOR or WORLD_COLOR
	button.BackgroundTransparency = parented and 1 or 0.45
end

function ParentingUI.modeButton(parent, name)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, 18, 1, 0)
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color3.fromRGB(51, 0, 77)
	button:SetAttribute("ThemeBg", "TopBtn")
	button.FontFace = FONT
	button.TextSize = 10
	ParentingUI.paint(button, true)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = button
	button.Parent = parent
	return button
end

return ParentingUI
