--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Chrome = require("Chrome")
local ImageUpload = require("Upload")
local Theme = require("Theme")
local Sequence = require("Sequence")
local WindowFX = require("WindowFX")
local Confirm = require("Confirm")

local Editor = {}
local session
local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local function make(class, parent, name, props)
	local object = Instance.new(class)

	object.Name = name
	for key, value in pairs(props) do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function round(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius) })
end

local function surface(object, key)
	object.BorderSizePixel = 0
	object:SetAttribute("ThemeBg", key)
	round(object, 5)
	local stroke = make("UIStroke", object, "Outline", {
		Color = Color3.fromRGB(78, 57, 95),
		Thickness = 1,
		StrokeSizingMode = Enum.StrokeSizingMode.FixedSize,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	stroke:SetAttribute("ThemeStrk", "Strk")
end

local function text(parent, name, value, pos, size, fontSize)
	local object = make("TextLabel", parent, name, {
		Text = value,
		Position = pos,
		Size = size,
		TextSize = fontSize or 12,
		FontFace = FONT,
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(233, 228, 239),
		ZIndex = 82,
	})
	object:SetAttribute("ThemeTxt", "Txt")
	return object
end

local function button(parent, name, value, pos, size)
	local object = make("TextButton", parent, name, {
		Text = value,
		Position = pos,
		Size = size,
		TextSize = 12,
		FontFace = FONT,
		BackgroundColor3 = Color3.fromRGB(42, 28, 53),
		TextColor3 = Color3.fromRGB(233, 228, 239),
		AutoButtonColor = true,
		ZIndex = 83,
	})
	surface(object, "TopBtn")
	object:SetAttribute("ThemeTxt", "Txt")
	return object
end

local function field(parent, name, value, pos, size)
	local object = make("TextBox", parent, name, {
		Text = value,
		Position = pos,
		Size = size,
		TextSize = 12,
		FontFace = FONT,
		BackgroundColor3 = Color3.fromRGB(17, 10, 24),
		TextColor3 = Color3.fromRGB(233, 228, 239),
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 83,
	})
	surface(object, "Pnl")
	object:SetAttribute("ThemeShade", -0.3)
	object:SetAttribute("ThemeTxt", "Txt")
	return object
end

local function number(value)
	return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function collect()
	local frames = {}
	for _, row in ipairs(session.rows) do
		table.insert(frames, {
			image = row.id.Text,
			delay = row.delay.Text == row.initialDelayText and row.exactDelay or tonumber(
				row.delay.Text
			) or 0,
		})
	end

	return frames
end

local function snapshot(frames)
	local out = {}
	for _, frame in ipairs(frames) do
		table.insert(out, tostring(frame.image) .. ":" .. tostring(frame.delay))
	end

	return table.concat(out, "|")
end

local function info()
	if not session or session.uploading then
		return
	end

	local frames = collect()
	local total = Sequence.duration(frames)
	session.duration.Text = number(total)
	session.fps.Text = total > 0 and number(#frames * 1000 / total) or "0"
	session.lastFPS, session.lastDuration = session.fps.Text, session.duration.Text
	session.summary.Text = #frames
		.. " images  ·  "
		.. math.floor(total / 1000)
		.. "s "
		.. number(total % 1000)
		.. "ms"
end

local rebuild

local function dashed(tile)
	local function paint()
		if not tile.Parent or not session then
			return
		end

		for _, child in ipairs(tile:GetChildren()) do
			if child.Name == "Dash" then
				child:Destroy()
			end
		end

		local scale = session.root:FindFirstChildOfClass("UIScale")
		local width, height = tile.AbsoluteSize.X / (scale and scale.Scale or 1), 80
		for x = 6, width - 6, 12 do
			for _, y in ipairs({ 0, height - 1 }) do
				local dot = make("Frame", tile, "Dash", {
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(math.min(6, width - x - 4), 1),
					BackgroundColor3 = Color3.fromRGB(113, 87, 130),
					BorderSizePixel = 0,
					ZIndex = 82,
				})
				dot:SetAttribute("ThemeBg", "Strk")
			end
		end

		for y = 6, height - 6, 12 do
			for _, x in ipairs({ 0, width - 1 }) do
				local dot = make("Frame", tile, "Dash", {
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(1, 6),
					BackgroundColor3 = Color3.fromRGB(113, 87, 130),
					BorderSizePixel = 0,
					ZIndex = 82,
				})
				dot:SetAttribute("ThemeBg", "Strk")
			end
		end
	end

	tile:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)
	task.defer(paint)
end

function Editor.addFrame()
	if not session or session.uploading then
		return
	end

	local frames = collect()
	if #frames >= Sequence.MAX_FRAMES then
		session.status.Text = "Maximum 300 images."
		return
	end

	table.insert(frames, { image = "", delay = frames[#frames].delay })
	rebuild(frames)
end

rebuild = function(frames)
	local current = session
	for _, child in ipairs(current.scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	current.rows = {}
	for index, frame in ipairs(frames) do
		local card = make(
			"Frame",
			current.scroll,
			"Image" .. index,
			{ LayoutOrder = index, BackgroundColor3 = Color3.fromRGB(26, 18, 34), ZIndex = 81 }
		)
		surface(card, "Pnl")
		local thumbnail = make("ImageLabel", card, "Preview", {
			Position = UDim2.fromOffset(36, 6),
			Size = UDim2.fromOffset(26, 22),
			Image = Sequence.asset(frame.image) or "",
			ScaleType = Enum.ScaleType.Crop,
			BackgroundTransparency = 1,
			ZIndex = 82,
		})
		round(thumbnail, 3)
		local label = text(
			card,
			"Label",
			"Image " .. index,
			UDim2.fromOffset(68, 5),
			UDim2.new(1, -100, 0, 24),
			12
		)
		label.TextXAlignment = Enum.TextXAlignment.Left
		local remove =
			button(card, "Remove", "×", UDim2.new(1, -28, 0, 5), UDim2.fromOffset(22, 22))
		remove.TextSize = 17
		local id =
			field(card, "AssetId", frame.image, UDim2.fromOffset(8, 40), UDim2.new(1, -86, 0, 26))
		id.PlaceholderText = "rbxassetid://..."
		local delay = field(
			card,
			"Delay",
			number(frame.delay),
			UDim2.new(1, -70, 0, 40),
			UDim2.fromOffset(62, 26)
		)
		text(card, "DelayLabel", "ms", UDim2.new(1, -70, 0, 24), UDim2.fromOffset(62, 14), 10).TextTransparency =
			0.35
		table.insert(
			current.rows,
			{ id = id, delay = delay, initialDelayText = delay.Text, exactDelay = frame.delay }
		)
		local upload = button(card, "Upload", "", UDim2.fromOffset(8, 5), UDim2.fromOffset(22, 22))
		local uploadIcon = make("ImageLabel", upload, "Icon", {
			Image = Chrome.UPLOAD_ICON,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(16, 16),
			ZIndex = 84,
		})
		uploadIcon:SetAttribute("ThemeImg", "Txt")
		upload.Activated:Connect(function()
			if current.uploading then
				return
			end

			current.uploading = true
			upload.Interactable = false
			uploadIcon.Visible = false
			upload.Text = "…"
			current.status.Text = "Choose a local image frame."
			local asset, err = ImageUpload.promptLocal()
			current.uploading = false
			if session ~= current or not card.Parent then
				return
			end

			upload.Interactable = true
			uploadIcon.Visible = true
			upload.Text = ""
			if asset then
				id.Text = asset
				thumbnail.Image = asset
			end

			info()
			current.status.Text = err or (asset and "Local image loaded." or "")
		end)
		id.FocusLost:Connect(function()
			local asset = Sequence.asset(id.Text)
			if asset then
				id.Text = asset
				thumbnail.Image = asset
			end

			current.status.Text = asset and "" or "Enter an image ID or rbxasset:// path."
		end)
		require("NumericInput").connect(delay, { step = 1, min = 1, integer = true }, function()
			info()
		end)
		remove.Activated:Connect(function()
			if current.uploading then
				return
			end

			local nextFrames = collect()
			table.remove(nextFrames, index)
			if #nextFrames == 0 then
				nextFrames = { { image = "", delay = 1000 / 30 } }
			end

			rebuild(nextFrames)
		end)
	end

	local add = make("TextButton", current.scroll, "AddImage", {
		LayoutOrder = #frames + 1,
		Text = "+",
		TextSize = 32,
		FontFace = FONT,
		TextColor3 = Color3.fromRGB(205, 191, 217),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 81,
	})
	add:SetAttribute("ThemeTxt", "Txt")
	dashed(add)
	add.Activated:Connect(Editor.addFrame)
	info()
	for _, object in ipairs(current.scroll:GetDescendants()) do
		Theme.applyInstance(object)
	end
end

function Editor.setDuration(duration)
	if not session or session.uploading then
		return false
	end

	local frames, err = Sequence.retime(collect(), tonumber(duration))
	if not frames then
		session.status.Text = err
		info()
		return false
	end

	rebuild(frames)
	session.status.Text = ""
	return true
end

function Editor.close(force)
	local current = session
	if not current or current.closing then
		return
	end

	if current.uploading and not force then
		current.status.Text = "Please wait for the images to finish loading."
		return
	end

	local frames = collect()
	local dirty = snapshot(frames) ~= current.original
	local hasContent = frames[1].image:match("%S") or current.hadContent
	if not force and dirty and hasContent then
		Confirm.open(
			current.root,
			nil,
			"DISCARD GIF CHANGES?",
			"Your frame and timing changes have not been applied.",
			"Discard",

			function()
				Editor.close(true)
			end
		)
		return
	end

	current.closing = true
	WindowFX.shrink(current.window, function()
		if session == current then
			session = nil
		end

		current.window:Destroy()
	end)
end

function Editor.apply()
	if not session or session.uploading then
		return false
	end

	if session.presetRevision ~= Theme.getPresetRevision() then
		session.status.Text = "The preset changed. Reopen GIF to edit the current preset."
		return false
	end

	if session.clearRequested and not collect()[1].image:match("%S") then
		local ok, applied = pcall(session.apply, nil)
		if not ok or applied == false then
			session.status.Text = "The background could not be applied. Your frames have been kept."
			return false
		end

		Editor.close(true)
		return true
	end

	local frames, err = Sequence.normalize(collect())
	if not frames then
		session.status.Text = err
		return false
	end

	local current = session
	local requested = snapshot(collect())
	current.uploading = true
	local Gif = require("GifBackground")
	local completed, ok, reason, id = pcall(Gif.preload, frames, function(done, total)
		if session == current and not current.closing then
			current.status.Text = "Checking images " .. done .. " / " .. total .. "..."
		end
	end, function()
		return session ~= current or current.closing
	end)
	current.uploading = false
	if session ~= current or current.closing then
		return false
	end

	if not completed or not ok then
		local message = "Image loading failed. Your frames have been kept. Press Apply to retry."
		if completed then
			local described, text = pcall(Gif.loadMessage, reason, id)
			if described then
				message = text
			end
		end

		if session ~= current or current.closing then
			return false
		end

		current.status.Text = message
		require("Notification").show("GIF IMAGES", message, 6)
		return false
	end

	if current.presetRevision ~= Theme.getPresetRevision() then
		current.status.Text = "The preset changed. Reopen GIF to edit the current preset."
		return false
	end

	if snapshot(collect()) ~= requested then
		current.status.Text =
			"Your frames changed while loading. Press Apply to check the updated images."
		return false
	end

	local appliedOk, applied = pcall(current.apply, frames)
	if not appliedOk or applied == false then
		current.status.Text = "The background could not be applied. Your frames have been kept."
		return false
	end

	if session == current then
		Editor.close(true)
	end

	return true
end

function Editor.open(root, value, onApply)
	if session and (session.closing or session.presetRevision ~= Theme.getPresetRevision()) then
		WindowFX.clear(session.window)
		session.window:Destroy()
		session = nil
	end

	if session and session.window.Parent then
		return session.window
	end

	local scaleObject = root:FindFirstChildOfClass("UIScale")
	local scale = scaleObject and scaleObject.Scale or 1
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local window = make("Frame", root, "EclipseGifEditor", {
		Size = UDim2.fromOffset(
			math.min(620, view.X / scale - 36),
			math.min(490, view.Y / scale - 36)
		),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(18, 10, 26),
		Active = true,
		ZIndex = 80,
	})
	surface(window, "Bg")
	local header, title, drag = Chrome.header(window, "GIF BACKGROUND", 81, 126)
	local apply = Chrome.menuButton(
		header,
		"Apply",
		"APPLY",
		UDim2.new(1, -110, 0, 4),
		UDim2.fromOffset(72, 20),
		84
	)
	local exit = Chrome.close(header, nil, 84)
	Chrome.bindDrag(window, drag)
	local backdrop = make("Frame", window, "Backdrop", {
		Position = UDim2.fromOffset(4, Chrome.HEIGHT),
		Size = UDim2.new(1, -8, 1, -Chrome.HEIGHT - 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 80,
	})
	surface(backdrop, "Bg")
	backdrop.Outline:Destroy()
	backdrop:SetAttribute("ThemeBgImage", 1)

	text(window, "FPSLabel", "FPS", UDim2.fromOffset(14, 38), UDim2.fromOffset(90, 20), 12)
	local fps = field(window, "FPS", "30", UDim2.fromOffset(14, 65), UDim2.fromOffset(90, 26))
	text(
		window,
		"DurationLabel",
		"Duration (ms)",
		UDim2.fromOffset(118, 38),
		UDim2.fromOffset(122, 20),
		12
	)
	local duration =
		field(window, "Duration", "", UDim2.fromOffset(118, 65), UDim2.fromOffset(122, 26))
	local summary =
		text(window, "Summary", "", UDim2.fromOffset(254, 65), UDim2.new(1, -268, 0, 26), 14)
	summary.TextXAlignment = Enum.TextXAlignment.Right
	summary.TextTransparency = 0.3
	local divider = make("Frame", window, "Divider", {
		Position = UDim2.fromOffset(14, 97),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = Color3.fromRGB(78, 57, 95),
		BorderSizePixel = 0,
		ZIndex = 81,
	})
	divider:SetAttribute("ThemeBg", "Div")
	local scroll = make("ScrollingFrame", window, "Frames", {
		Position = UDim2.fromOffset(12, 107),
		Size = UDim2.new(1, -24, 1, -137),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 81,
	})
	scroll:SetAttribute("ThemeScr", "Scr")
	make("UIGridLayout", scroll, "Grid", {
		CellSize = UDim2.new(0.5, -10, 0, 80),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	make("UIPadding", scroll, "Padding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 4),
	})
	local clear =
		button(window, "ClearGif", "CLEAR GIF", UDim2.new(0, 14, 1, -25), UDim2.fromOffset(90, 19))
	clear.TextSize = 10
	local status =
		text(window, "Status", "", UDim2.new(0, 114, 1, -26), UDim2.new(1, -128, 0, 20), 11)
	status.TextXAlignment = Enum.TextXAlignment.Left
	local frames = value and value.frames and Sequence.normalize(value.frames)
		or { { image = value and value.image or "", delay = 1000 / 30 } }
	session = {
		root = root,
		window = window,
		scroll = scroll,
		fps = fps,
		duration = duration,
		summary = summary,
		status = status,
		rows = {},
		apply = onApply,
		hadContent = frames[1].image ~= "",
		presetRevision = Theme.getPresetRevision(),
	}
	rebuild(frames)
	session.original = snapshot(collect())
	clear.Activated:Connect(function()
		if session.uploading then
			return
		end

		session.clearRequested = true
		rebuild({ { image = "", delay = 1000 / 30 } })
		session.status.Text = "Apply to remove this GIF."
	end)
	require("NumericInput").connect(fps, { step = 1, min = 1, integer = true }, function()
		if not session or fps.Text == session.lastFPS then
			return
		end

		local value = tonumber(fps.Text)
		if value and value > 0 then
			Editor.setDuration(#session.rows * 1000 / value)
		else
			info()
		end
	end)
	require("NumericInput").connect(duration, { step = 0.1, min = 0.01 }, function()
		if session and duration.Text ~= session.lastDuration then
			Editor.setDuration(tonumber(duration.Text))
		end
	end)
	apply.Activated:Connect(Editor.apply)
	exit.Activated:Connect(function()
		Editor.close()
	end)
	Theme.applyInstance(window)
	for _, object in ipairs(window:GetDescendants()) do
		Theme.applyInstance(object)
	end

	WindowFX.pop(window)
	return window
end

return Editor
