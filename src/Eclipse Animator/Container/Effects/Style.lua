--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Theme = require("Theme")
local TweenService = game:GetService("TweenService")
local Style = {}

function Style.bind(button, label)
	button.AutoButtonColor = false
	local stroke = button:FindFirstChild("HoverStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")

		stroke.Name = "HoverStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 1
		stroke.Transparency = 1
		stroke.Parent = button
	end

	local tweens = {}
	local mode = "idle"

	local function rest()
		local role = button:GetAttribute("ThemeBg") or "TopBtn"
		if Theme.isGradient(role) then
			return Color3.new(1, 1, 1)
		end

		return Theme.get(
			role,
			button:GetAttribute("EOrig_BackgroundColor3") or Color3.fromRGB(51, 0, 77)
		)
	end

	local function apply(nextMode)
		mode = nextMode
		for _, t in tweens do
			t:Cancel()
		end

		table.clear(tweens)
		local primary = button:GetAttribute("Primary") == true
		local color, strokeT, textT = rest(), 1, primary and 0 or 0.4
		if primary and mode ~= "idle" then
			color = color:Lerp(Color3.new(1, 1, 1), mode == "open" and 0.06 or 0.14)
			strokeT, textT = 0.45, 0
		elseif mode == "hover" then
			color = Theme.isGradient("TopBtn") and color:Lerp(Color3.new(), 0.12)
				or color:Lerp(Color3.new(1, 1, 1), 0.14)
			strokeT = 0.45
			textT = 0.15
		elseif mode == "open" then
			color = Theme.isGradient("TopBtn") and Color3.new(1, 1, 1)
				or Theme.get("MenuSel", Color3.fromRGB(100, 0, 151))
			strokeT = 0
			textT = 0
		end

		local ready = button:GetAttribute("Ready")
		if typeof(ready) == "boolean" then
			textT = ready and 0 or 0.65
		end

		stroke.Color = Theme.get("MenuSel", Color3.fromRGB(196, 132, 255))
			:Lerp(Color3.new(1, 1, 1), 0.35)

		local function tween(target, properties)
			local t = TweenService:Create(
				target,
				TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				properties
			)
			table.insert(tweens, t)
			t:Play()
		end

		tween(button, { BackgroundColor3 = color })
		tween(stroke, { Transparency = strokeT })
		if label then
			tween(label, { TextTransparency = textT })
		end
	end

	local readyChanged = button:GetAttributeChangedSignal("Ready"):Connect(function()
		apply(mode)
	end)
	local primaryChanged = button:GetAttributeChangedSignal("Primary"):Connect(function()
		apply(mode)
	end)
	local unsubscribe = Theme.onChanged(function()
		if button.Parent then
			apply(mode)
		end
	end)
	button.Destroying:Once(function()
		unsubscribe()
		readyChanged:Disconnect()
		primaryChanged:Disconnect()
		for _, t in tweens do
			t:Cancel()
		end
	end)
	return {
		idle = function()
			apply("idle")
		end,
		hover = function()
			apply("hover")
		end,
		open = function()
			apply("open")
		end,
	}
end

return Style
