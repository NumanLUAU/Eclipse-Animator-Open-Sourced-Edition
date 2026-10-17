local require = require(script:FindFirstAncestor("Container").Require)
local Preferences = require("Preferences")
local ChannelEasing = require("ChannelEasing")
local Defaults = require("Defaults")
local Colors = {}
local palette = {
	Linear = Color3.fromRGB(120, 220, 150),
	Constant = Color3.fromRGB(240, 125, 125),
	Bezier = Color3.fromRGB(115, 175, 250),
	Sine = Color3.fromRGB(110, 215, 225),
	Quad = Color3.fromRGB(230, 210, 115),
	Cubic = Color3.fromRGB(240, 175, 110),
	Quart = Color3.fromRGB(225, 145, 205),
	Quint = Color3.fromRGB(180, 145, 240),
	Expo = Color3.fromRGB(240, 140, 170),
	Circ = Color3.fromRGB(165, 215, 115),
	Back = Color3.fromRGB(185, 160, 120),
	Bounce = Color3.fromRGB(230, 230, 150),
	Elastic = Color3.fromRGB(145, 220, 200),
}
local aliases = { Sinusoidal = "Sine", Quadratic = "Quad", Quartic = "Quart", Quintic = "Quint", Exponential = "Expo", Circular = "Circ", ConstantNext = "Constant" }
function Colors.get(key, channel, hovered)
	if not key or not Preferences.get("ColorKeysByInterpolation") then return nil end
	local source = channel and ChannelEasing.view(key, channel) or key
	local style = source.EasingStyle or Defaults.EasingStyle
	style = typeof(style) == "EnumItem" and style.Name or style
	local color = palette[aliases[style] or style]
	return color and (hovered and color:Lerp(Color3.new(1, 1, 1), 0.25) or color)
end
return Colors
