--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Theme = require("Theme")
local About = {}
local refs, current, cached
local connections = {}
local rankColors = {
	["diamond members"] = { "8df1ff", "199bd8" },
	["gold members"] = { "e9bc4b", "c07a08" },
	["owners"] = { "e4c9ff", "ad87eb" },
	["developers"] = { "a6eddc", "55bfae" },
	["testers"] = { "ffd3b3", "e49b83" },
}

local function colorRank(label, colors)
	label:SetAttribute("ThemeTxt", nil)
	label.TextColor3 = Color3.new(1, 1, 1)
	Tool.make("UIGradient", label, "RankGradient", {
		Color = ColorSequence.new(Color3.fromHex(colors[1]), Color3.fromHex(colors[2])),
		Rotation = 90,
	})
end

local function cancel(window)
	window.requestId = (window.requestId or 0) + 1
	for _, key in { "request", "deadline" } do
		local thread = window[key]
		window[key] = nil
		if thread and thread ~= coroutine.running() then
			pcall(task.cancel, thread)
		end
	end
end

function About.close()
	if current then
		local old = current
		current = nil
		cancel(old)
		old:close()
	end
end

function About.open()
	if current then
		return current
	end

	if not refs or not refs.ScreenGui.Parent then
		return
	end

	local window
	window = Tool.new(refs, "EclipseAbout", "ABOUT ECLIPSE", Vector2.new(470, 422), false, function()
		cancel(window)
		if current == window then
			current = nil
		end
	end, { AllowMainMenu = true })
	current = window
	local frame = window.frame
	Tool.make("ImageLabel", frame, "EclipseLogo", {
		Image = "rbxassetid://126656292244944",
		Position = UDim2.fromOffset(18, 47),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 12,
	})
	local invite = Tool.make("TextBox", frame, "Discord", {
		Text = "Community Server - link on our Creator Store page",
		TextWrapped = true,
		Position = UDim2.fromOffset(56, 46),
		Size = UDim2.new(1, -74, 0, 36),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		TextEditable = false,
		TextSize = 13,
		FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 12,
	})
	invite:SetAttribute("ThemeTxt", "Txt")
	local divider = Tool.make("Frame", frame, "Divider", {
		Position = UDim2.fromOffset(18, 88),
		Size = UDim2.new(1, -36, 0, 1),
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	divider:SetAttribute("ThemeBg", "Div")
	local heading = Tool.label(
		frame,
		"CreditsHeading",
		"CREDITS  |  " .. tostring(refs.ScreenGui:GetAttribute("EclipseBuild") or "Build unknown"),
		UDim2.fromOffset(18, 102),
		UDim2.new(1, -36, 0, 20)
	)
	heading.ZIndex = 12
	heading.TextTransparency = 0.3
	local scroll = Tool.make("ScrollingFrame", frame, "Credits", {
		Position = UDim2.fromOffset(18, 132),
		Size = UDim2.new(1, -36, 1, -188),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 12,
	})
	scroll:SetAttribute("ThemeScr", "Scr")
	Tool.make(
		"UIListLayout",
		scroll,
		"Layout",
		{ Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	local status =
		Tool.label(frame, "Status", "", UDim2.new(0, 18, 1, -40), UDim2.new(1, -138, 0, 26))
	status.ZIndex = 12
	status.TextSize = 11
	status.TextTransparency = 0.25
	local retry, retryLabel = Tool.button(
		frame,
		"Refresh",
		"REFRESH",
		UDim2.new(1, -104, 1, -42),
		UDim2.fromOffset(86, 28)
	)
	retry.ZIndex = 12
	retryLabel.ZIndex = 13

	local function render(groups)
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for index, group in groups do
			local row = Tool.make("Frame", scroll, "Group" .. index, {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -12, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = index,
				ZIndex = 13,
			})
			Tool.make(
				"UIListLayout",
				row,
				"Layout",
				{ Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }
			)
			local title = Tool.label(row, "Rank", group.rank, UDim2.new(), UDim2.new(1, 0, 0, 0))
			title.AutomaticSize = Enum.AutomaticSize.Y
			title.LayoutOrder = 1
			title.ZIndex = 14
			title.TextSize = 16
			title.FontFace =
				Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
			local names = Tool.label(
				row,
				"Members",
				table.concat(group.members, ", "),
				UDim2.new(),
				UDim2.new(1, 0, 0, 0)
			)
			names.AutomaticSize = Enum.AutomaticSize.Y
			names.LayoutOrder = 2
			names.ZIndex = 14
			names.TextSize = 13
			local colors = rankColors[group.rank:lower()]
			if colors then
				colorRank(title, colors)
				colorRank(names, colors)
			end
		end

		Theme.applyTree(frame)
	end

	local function refresh()
		if window.closed or window.loading then
			return
		end

		cancel(window)
		local requestId = window.requestId
		window.loading = true
		retry.Active = false
		retry.Selectable = false
		retryLabel.Text = "LOADING"
		status.Text = "Loading credits\u{2026}"

		local function finish(groups)
			if window.closed or current ~= window or requestId ~= window.requestId then
				return
			end

			cancel(window)
			window.loading = false
			retry.Active = true
			retry.Selectable = true
			if groups then
				cached = groups
				render(groups)
				scroll.CanvasPosition = Vector2.zero
				status.Text = ""
				retryLabel.Text = "REFRESH"
			else
				status.Text = cached and "Couldn't refresh credits." or "Credits couldn't load."
				retryLabel.Text = "RETRY"
			end
		end

		finish({ { rank = "Cracked by:", members = { "numan" } }, { rank = "Developers", members = { "riftkuro" } } })
	end

	retry.Activated:Connect(refresh)
	window.refresh = refresh
	if cached then
		render(cached)
	else
		refresh()
	end

	return window
end

local welcome, welcomeSeen = false, false
local WELCOME_KEY = "EclipseWelcomeSeen_v1"
local welcomeClosers = setmetatable({}, { __mode = "k" })

function About.createWelcome(parent, onClose)
	local Chrome = require("Chrome")
	local Surface = require("Surface")
	local FX = require("WindowFX")
	local gui = Tool.make("ScreenGui", nil, "Eclipse Welcome", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 2147483600,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	gui:SetAttribute("EclipseOwnedUI", true)
	local viewport = Tool.make("Frame", gui, "Viewport", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 272),
		BackgroundTransparency = 1,
	})
	local card = Tool.make("Frame", viewport, "Welcome", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 272),
		Active = true,
		ZIndex = 10,
	})
	Surface.fill(card)
	local outline = Tool.make("UIStroke", card, "Outline", { Thickness = 1, Transparency = 0.25 })
	outline:SetAttribute("ThemeStrk", "Strk")
	local header, _, drag = Chrome.header(card, "WELCOME TO ECLIPSE")
	local closed = false

	local function close(immediate)
		if closed then
			return
		end

		closed = true
		welcomeClosers[gui] = nil
		if onClose then
			onClose()
		end

		local function dispose()
			FX.clear(card)
			gui:Destroy()
		end

		if immediate then
			dispose()
		else
			FX.shrink(card, dispose)
		end
	end

	welcomeClosers[gui] = close
	gui.Destroying:Connect(function()
		FX.clear(card)
		welcomeClosers[gui] = nil
		if not closed then
			closed = true
			if onClose then
				onClose()
			end
		end
	end)
	Chrome.close(header, function()
		close()
	end)
	local scale = Tool.make("UIScale", viewport, "ViewportScale", { Scale = 1 })

	local function resize()
		local size = gui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			scale.Scale = math.max(0.2, math.min(1, (size.X - 24) / 460, (size.Y - 24) / 272))
		end
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	local function label(name, text, x, y, width, height, bold)
		local l =
			Tool.label(card, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(width, height))
		l.FontFace = Font.new(
			"rbxasset://fonts/families/RobotoMono.json",
			bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular
		)
		l.TextSize = 13
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.ZIndex = 12
		return l
	end

	Tool.make("ImageLabel", card, "EclipseIcon", {
		Image = "rbxassetid://126656292244944",
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 12,
	})
	label("Title", "Welcome to Eclipse!", 52, 46, 390, 22, true)
	local divider = Tool.make("Frame", card, "WelcomeDivider", {
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.fromOffset(432, 1),
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	divider:SetAttribute("ThemeBg", "Div")
	label(
		"Introduction",
		"There's a lot of features to unpack and get used to. If you are seeing this, you're on a very early release. There will, unfortunately, be bugs. Please report them to us in our community server below.",
		14,
		86,
		432,
		64,
		false
	)
	local from = label("IfFrom", "If you are from", 14, 158, 110, 18, false)
	from.TextSize = 12

	local width = game:GetService("TextService")
		:GetTextSize(from.Text, 12, Enum.Font.RobotoMono, Vector2.new(432, 18)).X
	local iconX = 14 + width + 5
	Tool.make("ImageLabel", card, "BlenderIcon", {
		Image = "rbxassetid://93204150139908",
		Position = UDim2.fromOffset(iconX, 156),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 12,
	})
	local blender = label("Blender", "Blender", iconX + 22, 158, 65, 18, true)
	blender.TextSize = 12
	blender:SetAttribute("ThemeTxt", nil)
	blender.TextColor3 = Color3.fromRGB(234, 118, 0)
	local wordWidth = game:GetService("TextService")
		:GetTextSize("Blender", 12, Enum.Font.RobotoMono, Vector2.new(100, 18)).X
	local pathX = iconX + 22 + wordWidth + 5
	local preferences = label(
		"PreferencesPath",
		"then go to Settings > Preferences",
		pathX,
		158,
		446 - pathX,
		18,
		false
	)
	preferences.TextSize = 12
	label(
		"BlenderInstructions",
		"and ENABLE the top 3 orange blender features for familiarity.",
		14,
		178,
		432,
		32,
		false
	)
	local community = Tool.make("TextBox", card, "Community", {
		Text = "Community Server - link on our Creator Store page",
		ClearTextOnFocus = false,
		TextEditable = false,
		Position = UDim2.fromOffset(14, 212),
		Size = UDim2.fromOffset(432, 18),
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	})
	community:SetAttribute("ThemeTxt", "Txt")
	local button, text = Tool.button(
		card,
		"Continue",
		"GET STARTED",
		UDim2.fromOffset(14, 236),
		UDim2.fromOffset(432, 24),

		function()
			close()
		end
	)
	button.ZIndex = 12
	text.ZIndex = 13
	Chrome.bindDrag(viewport, drag, {
		clamp = true,
		disabled = function()
			return closed
		end,
	})
	gui.Parent = parent
	Theme.addRoot(gui)
	Theme.applyTree(card)
	resize()
	FX.pop(card)
	return gui
end

function About.closeWelcome(immediate)
	if welcome then
		local old = welcome
		welcome = nil
		local close = welcomeClosers[old]
		if close then
			close(immediate)
		else
			old:Destroy()
		end
	end
end

function About.showWelcomeOnce()
	if welcomeSeen or not refs or not refs.ScreenGui.Enabled or not refs.ScreenGui.Parent then
		return
	end

	local read = refs.GetSetting or function(key)
		return refs.Plugin:GetSetting(key)
	end

	local ok, seen = pcall(read, WELCOME_KEY)
	if ok and seen == true then
		welcomeSeen = true
		return
	end

	welcomeSeen = true
	welcome = About.createWelcome(refs.ScreenGui.Parent, function()
		welcome = nil
	end)
	local write = refs.SetSetting or function(key, value)
		refs.Plugin:SetSetting(key, value)
	end

	pcall(write, WELCOME_KEY, true)
end

function About.init(options)
	About.close()
	About.closeWelcome()
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	refs = options
	table.insert(
		connections,
		refs.ScreenGui.Destroying:Connect(function()
			About.close()
			About.closeWelcome(true)
		end)
	)
	table.insert(
		connections,
		refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then
				About.close()
				About.closeWelcome()
			else
				About.showWelcomeOnce()
			end
		end)
	)
	if refs.Plugin then
		table.insert(
			connections,
			refs.Plugin.Unloading:Connect(function()
				About.close()
				About.closeWelcome(true)
			end)
		)
	end

	task.defer(About.showWelcomeOnce)
end

return About
