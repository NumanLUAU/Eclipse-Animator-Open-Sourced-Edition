--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Assets = require("AssetIds")
local Outline = { Height = 16, Thickness = 1 }

function Outline.points(image, width)
	local w, h = math.max(width, Outline.Height), Outline.Height
	local shapes = Assets.KeyframeShapes
	if image == shapes.IK then
		return { { 6, 0 }, { w, 0 }, { w - 6, h }, { 0, h } }
	elseif image == shapes.IKEnd then
		return { { 0, 0 }, { w - 6, 0 }, { w, h }, { 6, h } }
	elseif image == shapes.Unparented then
		return { { 0, 0 }, { w, 0 }, { w, h }, { 0, h } }
	elseif image == shapes.HeadFollow then
		return {
			{ 3, 0 },
			{ w - 3, 0 },
			{ w, 3 },
			{ w, h - 3 },
			{ w - 3, h },
			{ 3, h },
			{
				0,
				h - 3,
			},
			{
				0,
				3,
			},
		}
	end

	return {
		{ h / 2, 0 },
		{ w - h / 2, 0 },
		{ w, h / 2 },
		{ w - h / 2, h },
		{ h / 2, h },
		{
			0,
			h / 2,
		},
	}
end

local textures = {
	[Assets.KeyframeShapes.Default] = "rbxassetid://102580746718079",
	[Assets.KeyframeShapes.Unparented] = "rbxassetid://71981605144514",
	[Assets.KeyframeShapes.IK] = "rbxassetid://104335396266698",
	[Assets.KeyframeShapes.IKEnd] = "rbxassetid://116515637166512",
	[Assets.KeyframeShapes.HeadFollow] = "rbxassetid://124449395225882",
}

function Outline.update(entry, image, width, color)
	if
		entry._outlineShape == image
		and entry._outlineWidth == width
		and entry._outlineColor == color
	then
		return
	end

	if not entry.texture then
		local texture = Instance.new("ImageLabel")
		texture.Name = "GroupSilhouette"
		texture.BackgroundTransparency = 1
		texture.BorderSizePixel = 0
		texture.Active = false
		texture.Size = UDim2.fromScale(1, 1)
		texture.ScaleType = Enum.ScaleType.Slice
		texture.SliceCenter = Rect.new(32, 14, 96, 18)
		texture.Parent = entry.bar
		entry.texture = texture
	end

	entry.texture.Image = textures[image] or textures[Assets.KeyframeShapes.Default]
	entry.texture.ImageColor3 = color
	entry.texture.SliceScale = 0.5
	entry.shape, entry.color = image, color
	entry._outlineShape, entry._outlineWidth, entry._outlineColor = image, width, color
end

return Outline
