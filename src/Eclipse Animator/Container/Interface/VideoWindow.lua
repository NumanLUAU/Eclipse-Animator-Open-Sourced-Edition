--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Chrome = require("Chrome")
local Surface = require("Surface")
local FX = require("WindowFX")
local Theme = require("Theme")
local Bridge = require("Bridge")
local Video = {}
local refs, window, unsubscribe

function Video.isOpen()
	return window ~= nil
end

function Video.close()
	local previous = window
	window = nil
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end

	if previous then
		FX.shrink(previous, function()
			previous:Destroy()
		end)
	end

	if refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end
end

function Video.open()
	if window then
		return window
	end

	local frame = Instance.new("Frame")

	frame.Name = "EclipseVideo"
	frame.Size = UDim2.fromOffset(346, 182)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 210
	frame.Active = true
	frame.Parent = refs.ScreenGui
	window = frame
	Surface.fill(frame)
	local outline = Instance.new("UIStroke")

	outline.Color = Theme.panelOutlineDefault()
	outline:SetAttribute("ThemeStrk", "Strk")
	outline.Parent = frame
	local header, _, drag = Chrome.header(frame, "ECLIPSE VIDEO", 211, 44)
	Chrome.close(header, nil, 215).Activated:Connect(Video.close)

	local function label(name, y)
		local text = Instance.new("TextLabel")

		text.Name = name
		text.Position = UDim2.fromOffset(14, y)
		text.Size = UDim2.new(1, -28, 0, 22)
		text.BackgroundTransparency = 1
		text.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
		text.TextSize = 12
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.ZIndex = 213
		text:SetAttribute("ThemeTxt", "Txt")
		text.Parent = frame
		return text
	end

	local status, file = label("Status", 43), label("File", 69)
	local sync, title = Chrome.menuButton(
		frame,
		"Sync",
		"SYNC ON",
		UDim2.fromOffset(14, 112),
		UDim2.new(1, -28, 0, 30),
		213
	)
	local download = label("Download", 150)
	download.Text = "Companion download: Community Server\nFind its link on our Creator Store page."
	download.TextSize = 11
	download.TextWrapped = true
	download.TextTruncate = Enum.TextTruncate.None
	download.Size = UDim2.new(1, -28, 0, 28)
	local wasConnected = Bridge.status().connected

	local function refresh()
		if window ~= frame then
			return
		end

		local current = Bridge.status()
		status.Text = current.connected and "Eclipse Connected" or "Eclipse Not Connected"
		file.Text = current.error or (current.file ~= "" and current.file or "No video selected")
		file.TextWrapped = current.error ~= nil
		file.TextTruncate = current.error and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
		file.Size = UDim2.new(1, -28, 0, current.error and 38 or 24)
		title.Text = current.enabled and "SYNC ON" or "SYNC OFF"
		local synced = current.connected and not wasConnected and current.enabled
		wasConnected = current.connected
		if synced then
			Video.close()
		end
	end

	sync.Activated:Connect(function()
		local enabled = not Bridge.status().enabled
		Bridge.setEnabled(enabled)
		if enabled and Bridge.status().connected then
			Video.close()
		else
			refresh()
		end
	end)
	unsubscribe = Bridge.subscribe(refresh)
	local pattern = Surface.halftone(frame)
	pattern.AnchorPoint = Vector2.new(1, 0)
	pattern.Position = UDim2.new(1, -16, 0, 38)
	pattern.Size = UDim2.fromOffset(128, 64)
	for _, dot in pattern:GetChildren() do
		if dot:IsA("Frame") then
			dot.Position =
				UDim2.new(1, dot.Position.X.Offset * 0.82, 0, -dot.Position.Y.Offset * 0.58)
		end
	end

	Chrome.bindDrag(frame, drag, { clamp = true, margin = 8 })
	Theme.addRoot(frame)
	Theme.applyTree(frame)
	refresh()
	FX.pop(frame)
	if refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end

	return frame
end

function Video.toggle()
	if window then
		Video.close()
	else
		Video.open()
	end
end

function Video.init(options)
	refs = options
	refs.State.VideoWindow = Video
	Bridge.init(refs)
	refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not refs.ScreenGui.Enabled then
			Video.close()
		end
	end)
	refs.ScreenGui.Destroying:Once(function()
		Video.close()
		Bridge.destroy()
	end)
end

return Video
