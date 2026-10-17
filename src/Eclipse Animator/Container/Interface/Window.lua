--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Shortcuts = require("Shortcuts")
local Theme = require("Theme")
local Surface = require("Surface")
local Audio = require("Audio")
local Storage = require("Storage")
local Preview = require("PathPreview")
local Rig = require("Rig")
local Icons = require("LibraryIcons")
local Chrome = require("Chrome")
local Motion = require("Motion")
local Style = require("Style")
local FX = require("WindowFX")
local Notification = require("Notification")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Window = {}
local refs, active = {}, nil
local picker
local lifetime = {}
local WIDTH, HEIGHT, SIDEBAR, GAP, CARD_HEIGHT = 660, 460, 114, 10, 112

local function make(class, parent, name, props)
	local object = Instance.new(class)

	object.Name = name
	for key, value in props or {} do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function round(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius or 5) })
end

local function surface(object, key)
	object.BorderSizePixel = 0
	object:SetAttribute("ThemeBg", key)
	round(object)
	return object
end

local function label(parent, name, value, position, size, fontSize)
	local object = make("TextLabel", parent, name, {
		Text = value,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = fontSize or 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = parent.ZIndex + 2,
	})
	object:SetAttribute("ThemeTxt", "Txt")
	return object
end

local function connect(list, signal, callback)
	local c = signal:Connect(callback)
	table.insert(list, c)
	return c
end

local function button(parent, name, value, position, size)
	local object = surface(
		make("TextButton", parent, name, {
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position + UDim2.new(
				size.X.Scale * 0.5,
				size.X.Offset * 0.5,
				size.Y.Scale * 0.5,
				size.Y.Offset * 0.5
			),
			Size = size,
			BackgroundColor3 = Color3.fromRGB(45, 29, 60),
			AutoButtonColor = false,
			ZIndex = parent.ZIndex + 3,
		}),
		"TopBtn"
	)
	make("UIGradient", object, "SubtleGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196)),
	})
	local text = label(object, "Label", value, UDim2.fromOffset(8, 0), UDim2.new(1, -16, 1, 0), 14)
	text:SetAttribute("ThemeTxt", "TopT")
	text.TextXAlignment = Enum.TextXAlignment.Center
	local style = Style.bind(object, text)
	local scale = make("UIScale", object, "HoverScale", { Scale = 1 })
	local tween
	local selected = false

	function style.setSelected(value)
		selected = value
		if selected then
			style.open()
		else
			style.idle()
		end
	end

	local function sizing(value)
		if tween then
			tween:Cancel()
		end

		tween = TweenService:Create(
			scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad),
			{ Scale = value }
		)
		tween:Play()
	end

	object.MouseEnter:Connect(function()
		if selected then
			style.open()
		else
			style.hover()
		end

		sizing(1.025)
	end)
	object.MouseLeave:Connect(function()
		if selected then
			style.open()
		else
			style.idle()
		end

		sizing(1)
	end)
	object.MouseButton1Down:Connect(style.open)
	object.MouseButton1Up:Connect(function()
		if selected then
			style.open()
		else
			style.hover()
		end
	end)
	object.Destroying:Once(function()
		if tween then
			tween:Cancel()
		end
	end)
	return object, text, style
end

local function box(parent, name, value, position, size)
	local shell = surface(
		make("Frame", parent, name .. "Field", {
			Position = position,
			Size = size,
			ClipsDescendants = true,
			BackgroundColor3 = Color3.fromRGB(22, 16, 28),
			ZIndex = parent.ZIndex + 4,
		}),
		"Pnl"
	)
	local object = make("TextBox", shell, name, {
		Text = value,
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 1, -4),
		FontFace = Chrome.FONT,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		PlaceholderColor3 = Color3.fromRGB(157, 151, 168),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = shell.ZIndex + 1,
	})
	object:SetAttribute("ThemeTxt", "Txt")
	local stroke = make("UIStroke", shell, "Outline", {
		Color = Theme.panelOutlineDefault(),
		Thickness = 1,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	stroke:SetAttribute("ThemeStrk", "Strk")
	return object
end

local function report(action)
	local ok, result = pcall(action)
	if not ok then
		Notification.show("LIBRARY", (tostring(result):gsub("^.-:%d+: ", "")))
	end

	return ok, result
end

local function navigation()
	local timeline = refs.State and refs.State.Timeline
	if timeline then
		timeline:RefreshNavigation()
	end
end

local function stopHover(s)
	Audio.stop()
	local card = s.hover
	s.hover = nil
	if card and card.preview then
		card.preview:pose(0, card.entry.kind == "Animations")
	end
end

local function closePopover(s, immediate)
	if not s.popover then
		return
	end

	local pop = s.popover
	s.popover = nil

	local function remove()
		s.retiring[pop] = nil
		FX.clear(pop)
		pop:Destroy()
	end

	if immediate then
		remove()
		return
	end

	s.retiring[pop] = true
	for _, object in pop:GetDescendants() do
		if object:IsA("GuiButton") then
			object.Interactable = false
		elseif object:IsA("TextBox") then
			object:ReleaseFocus()
			object.TextEditable = false
		end
	end

	FX.shrink(pop, remove)
end

local function beside(s, pop, size)
	local scale = Motion.scale(s.window)
	local bounds = s.window.Parent.AbsoluteSize / scale
	local position = (s.window.AbsolutePosition - s.window.Parent.AbsolutePosition) / scale
	local extent = s.window.AbsoluteSize / scale
	if extent.X < 1 then
		extent = Vector2.new(s.window.Size.X.Offset, s.window.Size.Y.Offset)
		position = bounds * 0.5 - extent * 0.5
	end

	local gap = 14
	local x = position.X + extent.X + gap + size.X * 0.5
	if x + size.X * 0.5 > bounds.X - 8 then
		if position.X - gap - size.X >= 8 then
			x = position.X - gap - size.X * 0.5
		elseif bounds.X >= extent.X + size.X + gap + 16 then
			s.window.Position = UDim2.fromOffset(8 + extent.X * 0.5, position.Y + extent.Y * 0.5)
			x = 8 + extent.X + gap + size.X * 0.5
		else
			local newWidth = math.max(460, bounds.X - size.X - gap - 16)
			if newWidth + size.X + gap + 16 <= bounds.X then
				s.window.Size = UDim2.fromOffset(newWidth, extent.Y)
				s.window.Position =
					UDim2.fromOffset(8 + newWidth * 0.5, position.Y + extent.Y * 0.5)
				x = 8 + newWidth + gap + size.X * 0.5
			else
				x = math.max(size.X * 0.5 + 8, bounds.X - size.X * 0.5 - 8)
			end
		end
	end

	pop.Position = UDim2.fromOffset(
		x,
		math.clamp(
			position.Y + size.Y * 0.5,
			8 + size.Y * 0.5,
			math.max(8 + size.Y * 0.5, bounds.Y - size.Y * 0.5 - 8)
		)
	)
end

local function popover(s, title, size)
	closePopover(s, true)
	stopHover(s)
	local pop = make("CanvasGroup", s.window.Parent, "LibraryOptions", {
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Active = true,
		BackgroundTransparency = 1,
		ZIndex = 260,
	})
	s.popover = pop
	Surface.backdrop(pop, true)
	beside(s, pop, size)
	local header, _, drag = Chrome.header(pop, title, 261)
	Chrome.close(header, function()
		closePopover(s)
	end, 265)
	Chrome.bindDrag(pop, drag, { clamp = true })
	return pop
end

local function showPopover(pop)
	Theme.applyTree(pop)
	FX.pop(pop)
end

local function saveDialog(s, entry, startUpload)
	local kind = entry and entry.kind or s.kind
	local media = not entry and (kind == "Faces" or kind == "Sounds")
	local noun = ({ Poses = "POSE", Animations = "ANIMATION", Faces = "FACE", Sounds = "SOUND" })[kind]
	local pop =
		popover(s, entry and "RENAME" or "SAVE " .. noun, Vector2.new(342, media and 266 or 202))
	label(pop, "NameLabel", "Name", UDim2.fromOffset(16, 42), UDim2.new(1, -32, 0, 22))
	local name = box(
		pop,
		"Name",
		entry and entry.name or "",
		UDim2.fromOffset(16, 70),
		UDim2.new(1, -32, 0, 34)
	)
	name.PlaceholderText = entry and entry.name or refs.Controller.nextName(kind)
	local asset, hint
	local selectedOnly = false
	if media then
		label(
			pop,
			"AssetLabel",
			kind == "Sounds" and "Audio ID" or "Image or decal ID",
			UDim2.fromOffset(16, 118),
			UDim2.new(1, -32, 0, 22)
		)
		asset = box(
			pop,
			"Asset",
			refs.Controller.selectedAsset(kind),
			UDim2.fromOffset(16, 146),
			UDim2.new(1, -32, 0, 34)
		)
		hint = label(pop, "Hint", "", UDim2.fromOffset(16, 183), UDim2.new(1, -32, 0, 28), 12)
		hint.TextWrapped = true
	elseif not entry and kind == "Poses" then
		local toggle = make("TextButton", pop, "SelectedBonesOnly", {
			Text = "",
			Position = UDim2.fromOffset(16, 110),
			Size = UDim2.new(1, -32, 0, 30),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = pop.ZIndex + 3,
		})
		label(
			toggle,
			"Title",
			"SELECTED BONES ONLY",
			UDim2.fromOffset(26, 0),
			UDim2.new(1, -26, 1, 0),
			12
		)
		local check = make("Frame", toggle, "Check", {
			Position = UDim2.fromOffset(0, 7),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = toggle.ZIndex + 1,
		})
		check:SetAttribute("ThemeBg", "TopBtn")
		local fill = make("Frame", check, "Fill", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			ZIndex = check.ZIndex + 1,
			Visible = false,
		})
		fill:SetAttribute("ThemeBg", "Txt")
		round(check, 2)
		round(fill, 2)
		local border = make("UIStroke", check, "Outline", { Thickness = 1 })
		border:SetAttribute("ThemeStrk", "Strk")
		toggle.Activated:Connect(function()
			selectedOnly = not selectedOnly
			fill.Visible = selectedOnly
		end)
	elseif not entry then
		local value = kind == "Poses" and "Save the pose at your current frame"
			or "Save this rig's full animation."
		label(pop, "Hint", value, UDim2.fromOffset(16, 110), UDim2.new(1, -32, 0, 34), 14).TextWrapped =
			true
	end

	local save, saveLabel =
		button(pop, "Save", "SAVE", UDim2.new(1, -116, 1, -50), UDim2.fromOffset(100, 34))
	local busy = false

	local function submit()
		if busy or s.closing or s.popover ~= pop then
			return
		end

		busy = true
		save.Interactable = false
		saveLabel.Text = "SAVING..."
		local nameValue, assetValue, selectedValue = name.Text, asset and asset.Text, selectedOnly
		task.defer(function()
			local ok = report(function()
				if entry then
					refs.Controller.rename(entry, nameValue)
				else
					refs.Controller.capture(kind, nameValue, assetValue, selectedValue)
				end
			end)
			if s.popover ~= pop then
				return
			end

			if ok then
				closePopover(s)
			else
				busy = false
				save.Interactable = true
				saveLabel.Text = "SAVE"
			end
		end)
	end

	local uploading = false
	local uploadButton, uploadLabel, uploadLink

	local function upload()
		if uploading or busy or s.closing or s.popover ~= pop then
			return
		end

		uploading = true
		if uploadButton then
			uploadButton.Interactable = false
			uploadLabel.Text = "OPENING..."
		end

		local ok, id, message, metadata = pcall(refs.Controller.upload, kind)
		uploading = false
		if s.closing or s.popover ~= pop then
			return
		end

		if uploadButton then
			uploadButton.Interactable = true
			uploadLabel.Text = "UPLOAD"
		end

		if not ok then
			hint.Text = "Couldn't open the upload. Try an asset ID."
			return
		end

		if message then
			hint.Text = message
		elseif id then
			asset.Text = id
			hint.Text = ""
		elseif metadata and metadata.url then
			hint.Text = "Upload audio in Creator Hub, then paste its ID above."
			hint.Size = UDim2.new(1, -32, 0, 44)
			hint.TextSize = 14
			if not uploadLink then
				pop.Size = UDim2.fromOffset(342, 362)
				beside(s, pop, Vector2.new(342, 362))
				label(
					pop,
					"LinkLabel",
					"Creator Hub link (copy into your browser)",
					UDim2.fromOffset(16, 237),
					UDim2.new(1, -32, 0, 20),
					12
				)
				uploadLink = box(
					pop,
					"UploadLink",
					metadata.url,
					UDim2.fromOffset(16, 263),
					UDim2.new(1, -32, 0, 32)
				)
				uploadLink.TextSize = 12
				uploadLink.TextEditable = false
				uploadLink.TextXAlignment = Enum.TextXAlignment.Left
				Theme.applyTree(pop)
			end

			uploadLink:CaptureFocus()
			uploadLink.CursorPosition = #uploadLink.Text + 1
			uploadLink.SelectionStart = 1
		end
	end

	if media then
		uploadButton, uploadLabel =
			button(pop, "Upload", "UPLOAD", UDim2.new(0, 16, 1, -50), UDim2.fromOffset(116, 34))
		uploadButton.Activated:Connect(upload)
	end

	save.Activated:Connect(submit)
	name.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
	if asset then
		asset.FocusLost:Connect(function(enter)
			if enter then
				submit()
			end
		end)
	end

	showPopover(pop)
	if startUpload then
		task.defer(upload)
	end
end

local function cameraDialog(s, card)
	local entry = card.entry
	local pop = popover(s, "PREVIEW CAMERA", Vector2.new(278, 222))
	pop:SetAttribute("LibraryEntry", entry.id)
	local values = table.clone(entry.camera or { 0, 0, 0 })
	for i, axis in { "X", "Y", "Z" } do
		local row = surface(
			make("Frame", pop, axis, {
				Position = UDim2.fromOffset(14, 42 + (i - 1) * 55),
				Size = UDim2.new(1, -28, 0, 44),
				BackgroundColor3 = Color3.fromRGB(34, 23, 46),
				BackgroundTransparency = 0.1,
				ZIndex = 262,
			}),
			"Pnl"
		)
		label(row, "Axis", axis, UDim2.fromOffset(14, 0), UDim2.fromOffset(36, 44), 16)
		local field = box(
			row,
			"Value",
			tostring(values[i]),
			UDim2.new(1, -158, 0.5, -16),
			UDim2.fromOffset(146, 32)
		)
		require("NumericInput").connect(field, { step = 0.1 }, function()
			local value = tonumber(field.Text)
			if not value or value ~= value or math.abs(value) == math.huge then
				field.Text = tostring(values[i])
				return
			end

			if value == values[i] then
				return
			end

			local previous = values[i]
			values[i] = value
			local ok = report(function()
				refs.Controller.camera(entry, table.clone(values))
			end)
			if not ok then
				values[i] = previous
				field.Text = tostring(previous)
			end
		end)
	end

	showPopover(pop)
end

local function contextDialog(s, card)
	local entry = card.entry
	local pop = popover(
		s,
		entry.kind == "Faces" and "FACE" or "SAVE OPTIONS",
		Vector2.new(220, entry.rig and 168 or 128),
		Input:GetMouseLocation()
	)
	local rename =
		button(pop, "Rename", "RENAME", UDim2.fromOffset(10, 36), UDim2.new(1, -20, 0, 30))
	rename.Activated:Connect(function()
		saveDialog(s, entry)
	end)
	local y = 76
	if entry.rig then
		local insert = button(
			pop,
			"InsertRig",
			"INSERT SAVED RIG",
			UDim2.fromOffset(10, y),
			UDim2.new(1, -20, 0, 30)
		)
		insert.Activated:Connect(function()
			if report(function()
				refs.Controller.insertRig(entry)
			end) then
				closePopover(s)
			end
		end)
		y += 40
	end

	local remove = button(
		pop,
		"Delete",
		entry.kind == "Poses" and "DELETE POSE" or "DELETE SAVE",
		UDim2.fromOffset(10, y),
		UDim2.new(1, -20, 0, 30)
	)
	remove.Activated:Connect(function()
		if report(function()
			Storage.remove(entry.id)
		end) then
			closePopover(s)
		end
	end)
	showPopover(pop)
end

local function destroyCard(s, card)
	if s.hover == card then
		stopHover(s)
	end

	card.disposed = true
	if card.entry.kind == "Sounds" then
		Audio.stop()
	end

	if card.preview then
		card.preview:destroy()
	end

	if card.tween then
		card.tween:Cancel()
	end

	card.root:Destroy()
	card.data = nil
end

local function soundRow(s, entry)
	local root = surface(
		make("Frame", s.scroll, "Save_" .. entry.id, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(400, 56),
			BackgroundColor3 = Color3.fromRGB(31, 24, 42),
			Active = true,
			ZIndex = 233,
		}),
		"Pnl"
	)
	local title = make("TextButton", root, "Name", {
		Text = entry.name,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.new(1, -204, 0, 22),
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 236,
	})
	title:SetAttribute("ThemeTxt", "Txt")
	local seconds = math.max(0, math.floor((entry.duration or 0) + 0.5))
	local duration = label(
		root,
		"Duration",
		string.format("%d:%02d", math.floor(seconds / 60), seconds % 60),
		UDim2.fromOffset(14, 30),
		UDim2.new(1, -204, 0, 18),
		12
	)
	duration.TextTransparency = 0.25
	local preview, previewLabel = button(
		root,
		"PreviewSound",
		"PREVIEW",
		UDim2.new(1, -184, 0, 13),
		UDim2.fromOffset(100, 30)
	)
	local use = button(
		root,
		"UseSound",
		s.pick and "USE" or "INSERT",
		UDim2.new(1, -74, 0, 13),
		UDim2.fromOffset(60, 30)
	)
	local c = { root = root, entry = entry, title = title }
	local busy = false
	preview.Activated:Connect(function()
		if busy or c.disposed or s.closing then
			return
		end

		busy = true
		local ok = report(function()
			local data = Storage.data(c.entry.id)
			if c.disposed or s.closing then
				return
			end

			Audio.toggle(data.id, function(playing)
				if not c.disposed then
					previewLabel.Text = playing and "STOP" or "PREVIEW"
				end
			end)
		end)
		busy = false
	end)
	use.Activated:Connect(function()
		if busy or c.disposed or s.closing or s.popover then
			return
		end

		busy = true
		local ok = report(function()
			if s.pick then
				local data = Storage.data(c.entry.id)
				if not c.disposed and not s.closing then
					s.pick(data.id, c.entry)
				end
			else
				refs.Controller.apply(c.entry)
			end
		end)
		busy = false
		if ok and s.pick then
			Window.close(s)
		end
	end)
	title.Activated:Connect(function()
		if not s.closing then
			saveDialog(s, c.entry)
		end
	end)
	root.InputBegan:Connect(function(input)
		if not s.closing and input.UserInputType == Enum.UserInputType.MouseButton2 then
			contextDialog(s, c)
		end
	end)
	Theme.applyTree(root)
	return c
end

local function card(s, entry)
	if entry.kind == "Sounds" then
		return soundRow(s, entry)
	end

	local root = surface(
		make("TextButton", s.scroll, "Save_" .. entry.id, {
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(170, CARD_HEIGHT),
			BackgroundColor3 = Color3.fromRGB(31, 24, 42),
			ZIndex = 233,
		}),
		"TopBtn"
	)
	local scaling = make("UIScale", root, "HoverScale", { Scale = 1 })
	local hit = make("TextButton", root, "Apply", {
		Size = UDim2.new(1, 0, 1, -34),
		Text = "",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 234,
	})
	local title = make("TextButton", root, "Name", {
		Text = entry.name,
		Position = UDim2.new(0, 9, 1, -31),
		Size = UDim2.new(1, entry.rig and not entry.readOnly and -68 or -44, 0, 28),
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 236,
	})
	title:SetAttribute("ThemeTxt", "Txt")
	local c = { root = root, entry = entry, title = title }
	local style = Style.bind(root, title)

	local function hover(inside)
		if c.disposed then
			return
		end

		if c.tween then
			c.tween:Cancel()
		end

		c.tween = TweenService:Create(
			scaling,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad),
			{ Scale = inside and 1.025 or 1 }
		)
		c.tween:Play()
		if inside then
			style.hover()
			stopHover(s)
			s.hover = c
			s.hoverStart = os.clock()
		elseif s.hover == c then
			style.idle()
			stopHover(s)
		else
			style.idle()
		end
	end

	root.MouseEnter:Connect(function()
		hover(true)
	end)
	root.MouseLeave:Connect(function()
		hover(false)
	end)
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not c.entry.readOnly then
			contextDialog(s, c)
		end
	end)

	local function apply()
		if s.closing or s.popover then
			return
		end

		local ok = report(function()
			if s.pick then
				local id = c.entry.image or Storage.data(c.entry.id).id
				if c.entry.kind == "Faces" then
					id = require("ImageLibrary").resolve(id)
				end

				s.pick(id, c.entry)
			else
				refs.Controller.apply(c.entry)
			end
		end)
		if ok and s.pick then
			Window.close(s)
		end
	end

	hit.Activated:Connect(apply)
	title.Activated:Connect(function()
		if s.pick or c.entry.readOnly then
			apply()
		else
			saveDialog(s, c.entry)
		end
	end)
	local status =
		label(root, "Loading", "Loading...", UDim2.fromOffset(12, 48), UDim2.new(1, -24, 0, 26), 11)
	status.TextXAlignment = Enum.TextXAlignment.Center
	if entry.kind == "Animations" or entry.kind == "Sounds" then
		local duration = label(
			root,
			"Duration",
			string.format("%.2fs", entry.duration),
			UDim2.new(1, -67, 1, -59),
			UDim2.fromOffset(57, 20),
			11
		)
		duration.TextXAlignment = Enum.TextXAlignment.Right
		duration.ZIndex = 237
	end

	if entry.rig then
		local function action(name, x, draw, callback)
			local control = make("TextButton", root, name, {
				Text = "",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(18, 18),
				Position = UDim2.new(1, x, 1, -16.5),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				ZIndex = 237,
			})
			draw(control)
			local scale = make("UIScale", control, "HoverScale", { Scale = 1 })
			local tween

			local function resize(value)
				if tween then
					tween:Cancel()
				end

				tween = TweenService:Create(
					scale,
					TweenInfo.new(0.12, Enum.EasingStyle.Quad),
					{ Scale = value }
				)
				tween:Play()
			end

			control.MouseEnter:Connect(function()
				resize(1.15)
			end)
			control.MouseLeave:Connect(function()
				resize(1)
			end)
			control.Destroying:Once(function()
				if tween then
					tween:Cancel()
				end
			end)
			control.Activated:Connect(function()
				if not c.disposed and not s.closing then
					callback()
				end
			end)
			return control
		end

		action("CameraSettings", entry.readOnly and -16.5 or -38.5, function(control)
			local icon = make("ImageLabel", control, "Camera", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(17, 17),
				Image = require("CameraRig").ICON,
				ZIndex = 238,
			})
			icon:SetAttribute("ThemeImg", "Txt")
		end, function()
			cameraDialog(s, c)
		end)
		if not entry.readOnly then
			action("PoseOptions", -16.5, Icons.gear, function()
				contextDialog(s, c)
			end)
		end
	end

	Theme.applyTree(root)
	task.defer(function()
		if c.disposed or s.closing then
			return
		end

		local ok, err = pcall(function()
			local data = entry.image and { id = entry.image } or Storage.data(entry.id)
			if c.disposed or s.closing then
				return
			end

			c.data = data
			if entry.kind == "Sounds" then
				local play, playLabel = button(
					hit,
					"PreviewSound",
					"PLAY",
					UDim2.new(0.5, -48, s.pick and 0.32 or 0.5, -18),
					UDim2.fromOffset(96, 36)
				)
				play.ZIndex = 238
				playLabel.ZIndex = 239
				if s.pick then
					local use = button(
						hit,
						"UseSound",
						"USE SOUND",
						UDim2.new(0.5, -58, 1, -38),
						UDim2.fromOffset(116, 30)
					)
					use.Activated:Connect(apply)
				end

				play.Activated:Connect(function()
					Audio.toggle(data.id, function(playing)
						if not c.disposed then
							playLabel.Text = playing and "STOP" or "PLAY"
						end
					end)
				end)
			elseif entry.kind == "Faces" then
				local image = require("ImageLibrary").resolve(data.id)
				if c.disposed or s.closing then
					return
				end

				make("ImageLabel", hit, "Face", {
					Position = UDim2.fromOffset(12, 12),
					Size = UDim2.new(1, -24, 1, -24),
					Image = image,
					ScaleType = Enum.ScaleType.Fit,
					BackgroundTransparency = 1,
					ZIndex = 235,
				})
			else
				local view = make("ViewportFrame", hit, "Viewport", {
					Position = UDim2.fromOffset(5, 5),
					Size = UDim2.new(1, -10, 1, -10),
					BackgroundTransparency = 1,
					Ambient = Color3.fromRGB(180, 180, 180),
					LightColor = Color3.new(1, 1, 1),
					LightDirection = Vector3.new(-1, -1, -1),
					ZIndex = 235,
				})
				local preview = Preview.attach(view, c.entry, data)
				if c.disposed or s.closing then
					preview:destroy()
				else
					c.preview = preview
				end
			end
		end)
		if not c.disposed then
			status.Text = ok and "" or "Preview unavailable"
			c.error = not ok and tostring(err) or nil
		end
	end)
	return c
end

local function paint(s)
	if s.closing then
		return
	end

	local width = s.window.Size.X.Offset - s.sidebar - 30
	local columns = s.kind == "Sounds" and 1 or math.max(1, math.floor((width + GAP) / 136))
	local height = s.kind == "Sounds" and 56 or CARD_HEIGHT
	local cell = (width - (columns - 1) * GAP) / columns
	local rows = math.ceil(#s.entries / columns)
	s.scroll.CanvasSize = UDim2.fromOffset(0, 12 + rows * (height + GAP))
	local first = math.max(0, math.floor((s.scroll.CanvasPosition.Y - 6) / (height + GAP)) - 1)
	local last = first + math.ceil((s.window.Size.Y.Offset - 90) / (height + GAP)) + 2
	local wanted = {}
	for index = first * columns + 1, math.min(#s.entries, (last + 1) * columns) do
		local entry = s.entries[index]
		wanted[entry.id] = true
		local c = s.cards[entry.id]
		if not c then
			c = card(s, entry)
			s.cards[entry.id] = c
		end

		c.entry = entry
		c.title.Text = entry.name
		local row = math.floor((index - 1) / columns)
		local column = (index - 1) % columns
		c.root.Position = UDim2.fromOffset(
			8 + column * (cell + GAP) + (cell - 8) * 0.5,
			8 + row * (height + GAP) + height * 0.5
		)
		c.root.Size = UDim2.fromOffset(cell - 8, height)
		if c.preview then
			c.preview:setCamera(entry.camera or { 0, 0, 0 })
		end
	end

	for id, c in s.cards do
		if not wanted[id] then
			destroyCard(s, c)
			s.cards[id] = nil
		end
	end

	s.empty.Visible = #s.entries == 0
end

local function refresh(s)
	if s.closing then
		return
	end

	local ok, entries =
		pcall(s.includeRecent and refs.Controller.imageEntries or Storage.entries, s.kind)
	if not ok then
		s.empty.Text = "Couldn't open the library."
		s.empty.Visible = true
		return
	end

	local query = s.search.Text:lower()
	s.entries = {}
	for _, entry in entries do
		if query == "" or entry.name:lower():find(query, 1, true) then
			table.insert(s.entries, entry)
		end
	end

	s.empty.Text = query ~= "" and "No matching saves."
		or s.kind == "Poses" and "Save the pose at your current frame"
		or s.kind == "Animations" and "Save an animation to start your library."
		or s.kind == "Sounds" and "Save a sound using its audio ID."
		or s.includeRecent and "Your saved and uploaded images appear here."
		or "Add a face using its image or decal ID."
	if s.upload then
		s.upload.Visible = s.kind == "Faces" or s.kind == "Sounds"
		s.search.Parent.Size = UDim2.new(1, s.upload.Visible and -244 or -120, 0, 36)
	end

	paint(s)
end

local function resize(s)
	for _, edge in
		{
			Vector2.new(-1, 0),
			Vector2.new(1, 0),
			Vector2.new(0, -1),
			Vector2.new(0, 1),
			Vector2.new(-1, -1),
			Vector2.new(1, -1),
			Vector2.new(-1, 1),
			Vector2.new(1, 1),
		}
	do
		local both = edge.X ~= 0 and edge.Y ~= 0
		local grip = make("TextButton", s.window, "Resize", {
			Text = "",
			Position = UDim2.fromScale((edge.X + 1) * 0.5, (edge.Y + 1) * 0.5),
			AnchorPoint = Vector2.new((edge.X + 1) * 0.5, (edge.Y + 1) * 0.5),
			Size = both and UDim2.fromOffset(9, 9)
				or edge.X == 0 and UDim2.new(1, -18, 0, 5)
				or UDim2.new(0, 5, 1, -18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 250,
		})
		grip.InputBegan:Connect(function(input)
			if
				s.closing
				or (
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				)
			then
				return
			end

			closePopover(s)
			stopHover(s)
			local point, size, position, scale =
				input.Position, s.window.Size, s.window.Position, Motion.scale(s.window)
			Motion.begin(s.window, input, function(nextPoint)
				local delta = (nextPoint - point) / scale
				local bounds = s.window.Parent.AbsoluteSize / scale - Vector2.new(16, 16)
				local w = edge.X == 0 and size.X.Offset
					or math.clamp(
						size.X.Offset + delta.X * edge.X,
						math.min(460, bounds.X),
						bounds.X
					)
				local h = edge.Y == 0 and size.Y.Offset
					or math.clamp(
						size.Y.Offset + delta.Y * edge.Y,
						math.min(320, bounds.Y),
						bounds.Y
					)
				s.window.Size = UDim2.fromOffset(w, h)
				s.window.Position = position
					+ UDim2.fromOffset(
						(w - size.X.Offset) * edge.X * 0.5,
						(h - size.Y.Offset) * edge.Y * 0.5
					)
				paint(s)
			end, nil, "resize")
		end)
	end
end

local function dispose(s)
	if s.disposed then
		return
	end

	s.disposed = true
	s.closing = true
	closePopover(s, true)
	stopHover(s)
	for pop in s.retiring do
		FX.clear(pop)
		pop:Destroy()
	end

	table.clear(s.retiring)
	for _, connection in s.connections do
		connection:Disconnect()
	end

	if s.unsubscribe then
		s.unsubscribe()
	end

	if s.unsubscribeImages then
		s.unsubscribeImages()
	end

	for _, c in s.cards do
		destroyCard(s, c)
	end

	table.clear(s.cards)
	FX.clear(s.window)
	s.window:Destroy()
	if not s.pick then
		Rig.clear()
	end

	if active == s then
		active = nil
	end

	if picker == s then
		picker = nil
	end

	navigation()
end

function Window.isOpen()
	return active ~= nil and not active.closing
end

function Window.close(target)
	local s = target or active
	if not s or s.closing then
		return
	end

	s.closing = true
	closePopover(s)
	stopHover(s)
	FX.shrink(s.window, function()
		dispose(s)
	end)
	navigation()
end

function Window.closeSounds(owner)
	if picker and (not owner or picker.owner == owner) then
		Window.close(picker)
	end
end

function Window.open(options)
	local pick = options and options.pick
	local previous = active
	if pick then
		previous = picker
	end

	if previous then
		if pick or previous.closing then
			dispose(previous)
		else
			return previous.window
		end
	end

	local hostGui = options and options.hostGui or refs.ScreenGui
	if not hostGui then
		return
	end

	local window = make(
		"CanvasGroup",
		hostGui,
		pick and ((options.kind == "Faces") and "FaceLibrary" or "SoundLibrary") or "AssetLibrary",
		{
			Size = UDim2.fromOffset(
				math.min(WIDTH, math.max(460, hostGui.AbsoluteSize.X - 16)),
				math.min(HEIGHT, math.max(320, hostGui.AbsoluteSize.Y - 16))
			),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 230,
		}
	)
	Surface.backdrop(window, true)
	Surface.halftone(window)
	local s = {
		window = window,
		connections = {},
		cards = {},
		entries = {},
		retiring = {},
		kind = pick and (options.kind or "Sounds") or "Poses",
		pick = pick,
		owner = options and options.owner,
		includeRecent = options and options.includeRecent,
		sidebar = pick and 0 or SIDEBAR,
	}
	if pick then
		picker = s
	else
		active = s
	end

	local header, _, drag = Chrome.header(
		window,
		pick and (options.title or (s.kind == "Faces" and "FACE LIBRARY" or "SOUND LIBRARY"))
			or "LIBRARY",
		231
	)
	Chrome.close(header, function()
		Window.close(s)
	end, 235)
	Chrome.bindDrag(window, drag, {
		clamp = true,
		margin = 8,
		began = function()
			closePopover(s)
		end,
		disabled = function()
			return s.closing
		end,
	})
	s.tabs = {}
	if not pick then
		local sidebar = make("Frame", window, "Categories", {
			Position = UDim2.fromOffset(6, 34),
			Size = UDim2.new(0, SIDEBAR - 6, 1, -40),
			BackgroundTransparency = 1,
			ZIndex = 231,
		})
		local divider = make("Frame", window, "CategoryDivider", {
			Position = UDim2.fromOffset(SIDEBAR, 42),
			Size = UDim2.new(0, 1, 1, -56),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(69, 41, 93),
			BackgroundTransparency = 0.25,
			ZIndex = 232,
		})
		divider:SetAttribute("ThemeBg", "Div")
		s.tabs = {}
		for i, kind in { "Poses", "Animations", "Faces", "Sounds" } do
			local tab, _, style = button(
				sidebar,
				kind,
				kind:upper(),
				UDim2.fromOffset(2, 8 + (i - 1) * 48),
				UDim2.new(1, -10, 0, 38)
			)
			local tint = surface(
				make("Frame", tab, "SelectedPage", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.fromRGB(100, 0, 151),
					BackgroundTransparency = 0.68,
					Visible = kind == s.kind,
					ZIndex = tab.ZIndex + 1,
				}),
				"MenuSel"
			)
			local marker = surface(
				make("Frame", tint, "Accent", {
					Position = UDim2.fromOffset(0, 8),
					Size = UDim2.new(0, 3, 1, -16),
					BackgroundColor3 = Color3.fromRGB(235, 228, 242),
					ZIndex = tint.ZIndex + 1,
				}),
				"Txt"
			)
			s.tabs[kind] = { button = tab, style = style, tint = tint }
			tab:SetAttribute("Selected", kind == s.kind)
			tab.Activated:Connect(function()
				if s.kind == kind then
					return
				end

				closePopover(s)
				stopHover(s)
				s.kind = kind
				s.scroll.CanvasPosition = Vector2.zero
				for key, v in s.tabs do
					local selected = key == kind
					v.button:SetAttribute("Selected", selected)
					v.tint.Visible = selected
					v.style.setSelected(selected)
				end

				refresh(s)
			end)
		end
	end

	local body = make("Frame", window, "Content", {
		Position = UDim2.fromOffset(s.sidebar + 8, 34),
		Size = UDim2.new(1, -s.sidebar - 14, 1, -40),
		BackgroundTransparency = 1,
		ZIndex = 231,
	})
	s.search = box(body, "Search", "", UDim2.fromOffset(0, 0), UDim2.new(1, -120, 0, 36))
	s.search.PlaceholderText = "Search saves"
	local save =
		button(body, "SaveNew", "+ SAVE", UDim2.new(1, -108, 0, 0), UDim2.fromOffset(108, 36))
	save.Activated:Connect(function()
		saveDialog(s)
	end)
	s.upload =
		button(body, "UploadNew", "UPLOAD", UDim2.new(1, -232, 0, 0), UDim2.fromOffset(112, 36))
	s.upload.Visible = false
	s.upload.Activated:Connect(function()
		saveDialog(s, nil, true)
	end)
	s.scroll = make("ScrollingFrame", body, "Saves", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 232,
	})
	s.scroll:SetAttribute("ThemeScr", "Scr")
	s.empty = label(body, "Empty", "", UDim2.fromOffset(18, 90), UDim2.new(1, -36, 0, 94), 19)
	s.empty.TextWrapped = true
	s.empty.TextXAlignment = Enum.TextXAlignment.Center
	connect(s.connections, window:GetPropertyChangedSignal("Size"), function()
		paint(s)
	end)
	connect(s.connections, s.search:GetPropertyChangedSignal("Text"), function()
		s.scroll.CanvasPosition = Vector2.zero
		refresh(s)
	end)
	connect(s.connections, s.scroll:GetPropertyChangedSignal("CanvasPosition"), function()
		paint(s)
	end)
	connect(s.connections, RunService.Heartbeat, function()
		local c = s.hover
		if s.closing or s.popover or not c or not c.preview or c.entry.kind ~= "Animations" then
			return
		end

		local duration = c.entry.duration
		if duration > 0 then
			c.preview:pose((os.clock() - s.hoverStart) % duration, true)
		end
	end)
	connect(s.connections, Input.InputBegan, function(input)
		if Shortcuts.matches("Cancel", input) and not Input:GetFocusedTextBox() then
			if picker and picker ~= s and not picker.closing then
				return
			end

			if s.popover then
				closePopover(s)
			else
				Window.close(s)
			end
		end
	end)
	s.unsubscribe = Storage.subscribe(function()
		refresh(s)
	end)
	if s.includeRecent then
		s.unsubscribeImages = require("ImageLibrary").subscribe(function()
			refresh(s)
		end)
	end

	resize(s)
	refresh(s)
	Theme.applyTree(window)
	if s.tabs.Poses then
		s.tabs.Poses.style.setSelected(true)
	end

	FX.pop(window)
	navigation()
	return window
end

function Window.init(options)
	Window.destroy()
	refs = options
	connect(lifetime, refs.ScreenGui.Destroying, Window.destroy)
	connect(lifetime, refs.ScreenGui:GetPropertyChangedSignal("Enabled"), function()
		if not refs.ScreenGui.Enabled then
			Window.close()
			Window.closeSounds()
		end
	end)
	connect(lifetime, refs.AnimatorFrame:GetPropertyChangedSignal("Visible"), function()
		if not refs.AnimatorFrame.Visible then
			Window.close()
			Window.closeSounds()
		end
	end)
end

function Window.destroy()
	if active then
		dispose(active)
	end

	if picker then
		dispose(picker)
	end

	for _, c in lifetime do
		c:Disconnect()
	end

	table.clear(lifetime)
	if refs.OnDestroy then
		refs.OnDestroy()
	end

	refs = {}
end

return Window
