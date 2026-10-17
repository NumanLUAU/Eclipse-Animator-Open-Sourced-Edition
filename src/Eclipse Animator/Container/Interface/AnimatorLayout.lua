--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preferences = require("Preferences")
local Theme = require("Theme")

local AnimatorLayout = {}
local HEADER_HEIGHT = 34
local CONTROL_PADDING_TOP = 5
local CONTROL_PADDING_BOTTOM = 1

local function separateTitle(bar)
	local appearance = bar:FindFirstChild("Appearence")
	local title = appearance and appearance:FindFirstChild("Title")
	if not title or not title:IsA("TextLabel") or title:FindFirstChild("EclipseTitleText") then
		return
	end

	local text = Instance.new("TextLabel")

	text.Name = "EclipseTitleText"
	for _, property in
		{
			"Text",
			"FontFace",
			"TextSize",
			"TextColor3",
			"TextTransparency",
			"TextStrokeColor3",
			"TextStrokeTransparency",
			"TextXAlignment",
			"TextYAlignment",
			"TextScaled",
			"TextWrapped",
			"TextTruncate",
			"RichText",
			"LineHeight",
		}
	do
		text[property] = title[property]
	end

	text.BackgroundTransparency = 1
	text.BorderSizePixel = 0
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = title.ZIndex + 1
	text:SetAttribute("ThemeTxt", title:GetAttribute("ThemeTxt"))
	for _, property in { "TextColor3", "TextTransparency" } do
		text:SetAttribute("EOrig_" .. property, title:GetAttribute("EOrig_" .. property))
	end

	text.Parent = title
	title.Text = ""
	title:SetAttribute("ThemeTxt", nil)
end

local function attachWindow(window, bar, main)
	separateTitle(bar)
	window.BorderSizePixel = 0
	bar.BorderSizePixel = 0
	main.BorderSizePixel = 0
	local windowCorner = window:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 6)
	windowCorner.Parent = window
	local barCorner = bar:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = bar
	local windowStroke = window:FindFirstChildOfClass("UIStroke")
	local barPadding = bar:FindFirstChildOfClass("UIPadding")
	local barStroke = bar:FindFirstChildOfClass("UIStroke")
	local original = {
		barPosition = bar.Position,
		barSize = bar.Size,
		barAnchor = bar.AnchorPoint,
		mainPosition = main.Position,
		mainSize = main.Size,
		mainAnchor = main.AnchorPoint,
		paddingTop = barPadding and barPadding.PaddingTop,
		paddingBottom = barPadding and barPadding.PaddingBottom,
		barStrokeEnabled = barStroke and barStroke.Enabled,
		windowStrokeEnabled = windowStroke and windowStroke.Enabled,
	}

	local outline = Instance.new("UIStroke")
	outline.Name = "AnimatorWindowOutline"
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	outline.Thickness = 1
	outline.Color = Theme.panelOutlineDefault()
	outline:SetAttribute("ThemeStrk", "Strk")
	outline.Parent = window
	Theme.applyInstance(outline)

	local appliedShape

	local function barTop()
		local scale = 1
		local ancestor = window
		while ancestor do
			for _, child in ancestor:GetChildren() do
				if child:IsA("UIScale") then
					scale *= child.Scale
				end
			end

			ancestor = ancestor.Parent
		end

		local height = window.AbsoluteSize.Y / math.max(0.001, scale)
		return bar.Position.Y.Scale * height
			+ bar.Position.Y.Offset
			- bar.AnchorPoint.Y * (bar.Size.Y.Scale * height + bar.Size.Y.Offset)
	end

	local function apply(preservePosition)
		local previousTop = barTop()
		local shape = Preferences.get("TopbarShape") or 1
		local legacy = shape ~= 1 and not window:GetAttribute("EclipseDocked")
		outline.Enabled = not legacy
		if windowStroke then
			windowStroke.Enabled = legacy and original.windowStrokeEnabled or false
		end

		if barStroke then
			barStroke.Enabled = legacy and original.barStrokeEnabled or false
		end

		if barPadding then
			barPadding.PaddingTop = legacy and original.paddingTop
				or UDim.new(0, CONTROL_PADDING_TOP)
			barPadding.PaddingBottom = legacy and original.paddingBottom
				or UDim.new(0, CONTROL_PADDING_BOTTOM)
		end

		if legacy then
			bar.AnchorPoint, bar.Position, bar.Size =
				original.barAnchor, original.barPosition, original.barSize
			main.AnchorPoint, main.Position, main.Size =
				original.mainAnchor, original.mainPosition, original.mainSize
			if shape == 2 then
				bar.AnchorPoint = Vector2.new(0.5, original.barAnchor.Y)
				bar.Position =
					UDim2.new(0.5, 0, original.barPosition.Y.Scale, original.barPosition.Y.Offset)
				bar.Size = UDim2.new(1, -2, original.barSize.Y.Scale, original.barSize.Y.Offset)
			end
		else
			bar.AnchorPoint = Vector2.zero
			bar.Position = UDim2.fromOffset(1, 0)
			bar.Size = UDim2.new(1, -2, 0, HEADER_HEIGHT)
			main.AnchorPoint = Vector2.zero
			main.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
			main.Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT)
		end

		if
			preservePosition
			and not window:GetAttribute("EclipseDocked")
			and appliedShape
			and appliedShape ~= shape
		then
			window.Position += UDim2.fromOffset(0, math.round(previousTop - barTop()))
		end

		appliedShape = shape
	end

	local dockChanged = window:GetAttributeChangedSignal("EclipseDocked"):Connect(function()
		apply(false)
	end)
	window.Destroying:Once(function()
		dockChanged:Disconnect()
	end)
	return apply
end

function AnimatorLayout.attach(UI)
	local animator = attachWindow(UI.AnimatorFrame, UI.AnimatorBarFrame, UI.AnimatorMain)
	local primary = attachWindow(UI.PrimaryFrame, UI.BarFrame, UI.MainFrame)

	local function apply()
		primary(false)
		animator(true)
		UI.PrimaryFrame.Position = UI.AnimatorFrame.Position
	end

	local unsubscribe = Preferences.subscribe(function(key)
		if key == "TopbarShape" then
			apply()
		end
	end)
	UI.AnimatorFrame.Destroying:Once(unsubscribe)
	apply()
end

function AnimatorLayout.keepVisible(UI)
	const State = require("State")
	const WindowFX = require("WindowFX")
	local elapsed, strikes = 0, 0

	local function blank()
		const gui = UI.EclipseGUI
		return gui.Parent ~= nil
			and gui.Enabled
			and not State.LoadingProject
			and not State.PresentationHidden
			and not (UI.AlertFrame and UI.AlertFrame.Visible)
			and not UI.PrimaryFrame.Visible
			and not UI.AnimatorFrame.Visible
	end

	local function restore()
		const frame = UI.PluginActiveBool.Value == true and UI.AnimatorFrame or UI.PrimaryFrame
		WindowFX.clear(UI.PrimaryFrame)
		WindowFX.clear(UI.AnimatorFrame)
		frame.Visible = true
		pcall(
			require("Notification").show,
			"EDITOR RESTORED",
			"An interrupted update hid the Eclipse window. It has been restored and your animation is still open.",
			6
		)
	end

	local function check()
		const gui = UI.EclipseGUI
		if
			gui:GetAttribute("EclipseConfirmationOpen") == true
			and not gui:FindFirstChild("EclipseConfirmation", true)
		then
			gui:SetAttribute("EclipseConfirmationOpen", nil)
		end

		if State.AnimatorDock and State.AnimatorDock.recover then
			State.AnimatorDock.recover()
		end

		if not blank() then
			strikes = 0
			return
		end

		strikes += 1
		if strikes >= 2 then
			strikes = 0
			restore()
		end
	end

	const connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end

		elapsed = 0
		const ok, issue = pcall(check)
		if not ok then
			warn("[Eclipse] Window recovery: " .. tostring(issue))
		end
	end)
	UI.EclipseGUI.Destroying:Once(function()
		connection:Disconnect()
	end)
end

return AnimatorLayout
