--// cracked by numan | Eclipse Animator

local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
const folder = Storage:FindFirstChild("EclipseCutscenes") or Storage:WaitForChild("EclipseCutscenes", 30)
if not folder then
	return
end
local entries = {}
local connections = {}
local icons = {
	Play = "rbxassetid://86614211960827",
	Pause = "rbxassetid://130990669009260",
	Loop = "rbxassetid://108297228549419",
}

for _, child in playerGui:GetChildren() do
	if child:GetAttribute("EclipseCutsceneControls") then
		return
	end
end

local gui, stack, hint, layout
local active
local closed = false

local function resize()
	if not gui then
		return
	end

	local height = layout.AbsoluteContentSize.Y
	hint.Visible = height > 0
	stack.Size = UDim2.fromOffset(262, math.min(height, 120, math.max(40, gui.AbsoluteSize.Y - 46)))
	stack.CanvasSize = UDim2.fromOffset(0, height)
	stack.CanvasPosition = Vector2.new(
		0,
		math.clamp(stack.CanvasPosition.Y, 0, math.max(0, height - stack.AbsoluteSize.Y))
	)
end

local coreState

local function setHidden(hidden)
	if not gui then
		return
	end

	if hidden then
		if coreState then
			return
		end

		gui.Enabled = false
		coreState = { kinds = {} }
		for _, kind in Enum.CoreGuiType:GetEnumItems() do
			if kind == Enum.CoreGuiType.All then
				continue
			end
			local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
			if ok and enabled == true then
				coreState.kinds[kind] = true
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
			end
		end
		local ok, topbar = pcall(StarterGui.GetCore, StarterGui, "TopbarEnabled")
		if ok and topbar == true then
			coreState.topbar = true
			pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)
		end
		return
	end

	gui.Enabled = true
	local state = coreState
	coreState = nil
	if not state then
		return
	end
	for kind in state.kinds do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true)
	end
	if state.topbar then
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", true)
	end
end

local function cutscenePlaying()
	local session = active and active.session
	return session ~= nil and (session.Status == "Playing" or session.Status == "Paused")
end

local function visibilityShortcut(input, processed)
	if processed or not gui or Input:GetFocusedTextBox() or input.KeyCode ~= Enum.KeyCode.H then
		return
	end
	if Input:IsKeyDown(Enum.KeyCode.LeftControl) or Input:IsKeyDown(Enum.KeyCode.RightControl) then
		if coreState then
			setHidden(false)
		elseif cutscenePlaying() then
			setHidden(true)
		end
	end
end

local function ensureGui()
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "EclipseCutsceneControls"
	gui:SetAttribute("EclipseCutsceneControls", true)
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60

	stack = Instance.new("ScrollingFrame")
	stack.Name = "Cutscenes"
	stack.AnchorPoint = Vector2.new(1, 1)
	stack.Position = UDim2.new(1, -12, 1, -34)
	stack.Size = UDim2.fromOffset(262, 0)
	stack.BackgroundTransparency = 1
	stack.BorderSizePixel = 0
	stack.ScrollBarThickness = 3
	stack.ScrollBarImageTransparency = 0.4
	stack.ScrollingDirection = Enum.ScrollingDirection.Y
	stack.CanvasSize = UDim2.new()
	stack.Parent = gui

	hint = Instance.new("TextLabel")
	hint.Name = "HideHint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -18, 1, -12)
	hint.Size = UDim2.fromOffset(256, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.Text = "ctrl + H to hide while playing"
	hint.TextSize = 11
	hint.TextColor3 = Color3.fromRGB(214, 224, 226)
	hint.TextTransparency = 0.25
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Visible = false
	hint.Parent = gui

	layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.Name
	layout.Parent = stack

	table.insert(connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize))
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	table.insert(connections, Input.InputBegan:Connect(visibilityShortcut))
	gui.Parent = playerGui
	resize()
end

local function round(object)
	local corner = Instance.new("UICorner")

	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = object
end

local function text(parent, name, size)
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = size
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent

	return label
end

local function refresh(entry, message)
	if not entry.row then
		if message then
			warn(message)
		end
		return
	end

	local status = entry.session and entry.session.Status or "Stopped"
	local playing = status == "Playing"
	local paused = status == "Paused"

	entry.caption.Text = entry.busy and "Loading..."
		or (playing or paused) and "Stop"
		or entry.config.ButtonLabel
		or "Play"
	entry.icon.Image = playing and icons.Pause or icons.Play
	entry.icon.ImageTransparency = entry.busy and 0.6 or 0
	entry.toggle.Active = not entry.busy
	entry.toggle.Selectable = not entry.busy
	entry.loopButton.BackgroundColor3 = entry.looped
			and entry.background:Lerp(entry.foreground, 0.14)
		or entry.background
	entry.loopButton.BackgroundTransparency = entry.looped and 0.08 or 0.25
	entry.loopIcon.ImageColor3 = entry.foreground
	entry.loopIcon.ImageTransparency = entry.looped and 0 or 0.2
	entry.loopStroke.Enabled = entry.looped
	entry.loopButton:SetAttribute("LoopEnabled", entry.looped)

	if message ~= nil then
		entry.message.Text = message
		entry.message.Visible = message ~= ""
		entry.row.Size = UDim2.fromOffset(256, message ~= "" and 94 or 58)
	end
end

local function stop(entry, reason)
	entry.request += 1
	entry.busy = false

	if entry.session then
		entry.session:Stop(reason)
	end

	if active == entry then
		active = nil
		setHidden(false)
	end
	refresh(entry, "")
end

local function start(entry)
	if entry.removed then
		return
	end

	local status = entry.session and entry.session.Status
	if entry.busy or status == "Playing" or status == "Paused" then
		stop(entry, "Stopped")
		return
	end

	if active and active ~= entry then
		stop(active, "Replaced")
	end
	setHidden(false)
	active = entry
	entry.request += 1

	local request = entry.request
	entry.busy = true
	refresh(entry, "")
	task.wait()
	if entry.removed or request ~= entry.request then
		return
	end

	local ok, message = xpcall(function()
		if entry.session then
			entry.session:Destroy()
		end

		local cutscene = require(entry.package)
		if entry.removed or request ~= entry.request then
			return
		end

		local session = cutscene.new({ Loop = entry.looped })
		if entry.removed or request ~= entry.request then
			session:Destroy()
			return
		end
		session.options.Loop = entry.looped
		entry.session = session

		session.Stopped:Connect(function()
			if entry.session ~= session or entry.removed then
				return
			end
			if active == entry then
				active = nil
				setHidden(false)
			end
			refresh(entry)
		end)

		session.Failed:Connect(function(errorMessage)
			if entry.session == session and not entry.removed then
				refresh(entry, tostring(errorMessage):match("^[^\n]+"))
			end
		end)

		session:Play()
	end, debug.traceback)

	if entry.removed or request ~= entry.request then
		return
	end
	entry.busy = false

	if ok then
		refresh(entry)
	else
		if active == entry then
			active = nil
			setHidden(false)
		end
		refresh(entry, "Could not play. See Output for details.")
		warn(message)
	end
end

local function toggle(entry)
	if entry.removed or entry.busy then
		return
	end

	local session = entry.session
	if not session or session.Status == "Stopped" then
		start(entry)
		return
	end

	local ok, message = pcall(function()
		if session.Status == "Playing" then
			session:Pause()
		elseif session.Status == "Paused" then
			session:Play()
		end
	end)

	refresh(entry, ok and "" or "Could not resume. See Output for details.")
	if not ok then
		warn(message)
	end
end

local function toggleLoop(entry)
	if entry.removed then
		return
	end
	entry.looped = not entry.looped
	local session = entry.session
	if session then
		session.options.Loop = entry.looped
	end
	if entry.looped then
		for _, other in entries do
			if other ~= entry and other.looped then
				other.looped = false
				if other.session then
					other.session.options.Loop = false
				end
				refresh(other)
			end
		end
	end
	refresh(entry)
	if not entry.looped or entry.busy then
		return
	end
	if session and session.Status == "Playing" then
		return
	end
	if session and session.Status == "Paused" then
		toggle(entry)
	else
		start(entry)
	end
end

local function luminance(color)
	local function linear(value)
		return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
	end
	return linear(color.R) * 0.2126 + linear(color.G) * 0.7152 + linear(color.B) * 0.0722
end

local function buttonRow(entry)
	local theme = entry.config.Theme or {}
	entry.background = typeof(theme.Background) == "Color3" and theme.Background
		or Color3.fromRGB(28, 30, 35)
	entry.foreground = typeof(theme.Foreground) == "Color3" and theme.Foreground
		or Color3.new(1, 1, 1)
	local bg = luminance(entry.background)
	local fg = luminance(entry.foreground)
	if (math.max(bg, fg) + 0.05) / (math.min(bg, fg) + 0.05) < 4.5 then
		entry.foreground = bg > 0.179 and Color3.new(0.06, 0.06, 0.07) or Color3.new(1, 1, 1)
	end
	ensureGui()
	local row = Instance.new("Frame")

	row.Name = entry.package.Name
	row.Size = UDim2.fromOffset(256, 58)
	row.BackgroundTransparency = 1
	row.Parent = stack
	entry.row = row

	local title = text(row, "Title", 12)
	title.Text = entry.package.Name
	title.TextTransparency = 0.18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, 18)

	local button = Instance.new("TextButton")

	button.Name = "StartStop"
	button.Position = UDim2.fromOffset(0, 18)
	button.Size = UDim2.fromOffset(164, 40)
	button.BackgroundColor3 = entry.background
	button.BackgroundTransparency = 0.25
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = row
	round(button)

	local logo = Instance.new("ImageLabel")

	logo.Name = "Logo"
	logo.BackgroundTransparency = 1
	logo.Image = "rbxassetid://126656292244944"
	logo.Size = UDim2.fromOffset(22, 22)
	logo.Position = UDim2.fromOffset(10, 9)
	logo.Parent = button

	local caption = text(button, "Caption", 16)
	caption.Position = UDim2.fromOffset(38, 0)
	caption.Size = UDim2.new(1, -44, 1, 0)
	caption.TextColor3 = entry.foreground
	entry.caption = caption

	local pause = Instance.new("ImageButton")

	pause.Name = "PlayPause"
	pause.Position = UDim2.fromOffset(170, 18)
	pause.Size = UDim2.fromOffset(40, 40)
	pause.BackgroundColor3 = button.BackgroundColor3
	pause.BackgroundTransparency = button.BackgroundTransparency
	pause.BorderSizePixel = 0
	pause.Image = ""
	pause.Parent = row
	round(pause)
	entry.toggle = pause

	local icon = Instance.new("ImageLabel")

	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(30, 30)
	icon.Position = UDim2.fromOffset(5, 5)
	icon.Parent = pause
	icon.ImageColor3 = entry.foreground
	entry.icon = icon

	local loop = Instance.new("ImageButton")

	loop.Name = "Loop"
	loop.Position = UDim2.fromOffset(216, 18)
	loop.Size = UDim2.fromOffset(40, 40)
	loop.BackgroundColor3 = button.BackgroundColor3
	loop.BackgroundTransparency = button.BackgroundTransparency
	loop.BorderSizePixel = 0
	loop.Image = ""
	loop.Parent = row
	round(loop)
	entry.loopButton = loop
	local loopIcon = Instance.new("ImageLabel")

	loopIcon.Name = "Icon"
	loopIcon.BackgroundTransparency = 1
	loopIcon.Image = icons.Loop
	loopIcon.Size = UDim2.fromOffset(24, 24)
	loopIcon.Position = UDim2.fromOffset(8, 8)
	loopIcon.Parent = loop
	entry.loopIcon = loopIcon
	local loopStroke = Instance.new("UIStroke")

	loopStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	loopStroke.Color = entry.foreground
	loopStroke.Transparency = 0.5
	loopStroke.Enabled = false
	loopStroke.Parent = loop
	entry.loopStroke = loopStroke
	loop.Activated:Connect(function()
		toggleLoop(entry)
	end)

	local message = text(row, "Status", 11)
	message.Position = UDim2.fromOffset(0, 62)
	message.Size = UDim2.new(1, 0, 0, 30)
	message.TextColor3 = Color3.fromRGB(255, 166, 155)
	message.TextWrapped = true
	message.TextTruncate = Enum.TextTruncate.None
	message.Visible = false
	entry.message = message

	button.Activated:Connect(function()
		start(entry)
	end)
	pause.Activated:Connect(function()
		toggle(entry)
	end)
	refresh(entry, "")
end

local function remove(package)
	local entry = entries[package]
	if not entry then
		return
	end

	entry.removed = true
	stop(entry, "Removed")
	if entry.session then
		entry.session:Destroy()
	end
	if entry.waiting then
		entry.waiting:Disconnect()
	end
	if entry.row then
		entry.row:Destroy()
	end
	entries[package] = nil
end

local function attach(package)
	if closed or not package:IsA("ModuleScript") or entries[package] then
		return
	end
	local generation = package:GetAttribute("EclipseCutscene")
	if type(generation) ~= "number" then
		return
	end

	local entry = { package = package, request = 0, busy = false, looped = false }
	entries[package] = entry

	local function configure(launch)
		if entry.config or entry.configuring then
			return
		end
		entry.configuring = true
		if entry.waiting then
			entry.waiting:Disconnect()
			entry.waiting = nil
		end

		local ok, message = xpcall(function()
			local config
			if launch then
				config = require(launch)
				assert(type(config) == "table", "Launch must return a table")
			else
				local cutscene = require(package)
				local button = type(cutscene) == "table" and cutscene.Button
				config = button and { Mode = "Button", ButtonLabel = button.Label, Theme = button.Theme }
					or { Mode = "Scripting" }
			end
			if entry.removed or closed then
				return
			end
			entry.config = config
			entry.toggleLoop = function()
				toggleLoop(entry)
			end
			entry.start = function()
				start(entry)
			end
			entry.togglePlayback = function()
				toggle(entry)
			end

			if config.Mode == "Button" then
				buttonRow(entry)
			end
		end, debug.traceback)

		if not ok then
			warn(`Eclipse cutscene {package.Name}: {message}`)
		end
	end

	if generation >= 2 then
		task.spawn(configure)
		return
	end

	entry.waiting = package.ChildAdded:Connect(function(child)
		if child.Name == "Launch" and child:IsA("ModuleScript") then
			task.spawn(configure, child)
		end
	end)
	local launch = package:FindFirstChild("Launch")
	if launch and launch:IsA("ModuleScript") then
		task.spawn(configure, launch)
	end
end
table.insert(connections, folder.ChildAdded:Connect(attach))
table.insert(connections, folder.ChildRemoved:Connect(remove))

for _, package in folder:GetChildren() do
	attach(package)
end
resize()

script.Destroying:Once(function()
	closed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	while next(entries) do
		remove(next(entries))
	end
	setHidden(false)
	if gui then
		gui:Destroy()
	end
end)
