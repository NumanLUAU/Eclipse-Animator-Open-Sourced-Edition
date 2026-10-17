--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local Dropdown = {}

function Dropdown.refreshIcons(root)
	for _, drawing in root:GetDescendants() do
		if drawing:GetAttribute("EclipseRasterFallback") then
			local icon = drawing.Parent
			drawing.Visible = not icon.IsLoaded
		end
	end
end

local LONG_KEYBIND_LENGTH = 7

local HINTS = {
	FitTimeline = "FitTimeline",
	ToggleOnionSkin = "ToggleOnionSkin",
	CaptureOnionSkin = "CaptureOnionSkin",
	ApplyOnionSkin = "ApplyOnionSkin",
	ClearOnionSkin = "ClearOnionSkin",
	ReverseKeys = "ReverseKeys",
	ReversePaste = "ReversePaste",
	UngroupAllKeyframes = "UngroupAllKeyframes",
	Hide = "TogglePresentation",
	Copy = "Copy",
	CopyKeys = "Copy",
	Paste = "Paste",
	PasteKeys = "Paste",
	PasteFlipped = "PasteFlipped",
	DeleteKey = "DeleteKeys",
	InsertKey = "RecordKeyframe",
	Undo = "Undo",
	Redo = "RedoAlternate",
	SelectAll = "SelectAll",
	GraphEditor = "ToggleGraphEditor",
	FullCamera = "CycleCamera",
	Grid = "ToggleCameraGrid",
	SaveProject = "SaveProject",
	SaveProjectAs = "SaveProjectAs",
	EditPivot = "EditPivot",
	SaveAndCloseProject = "SaveAndCloseProject",
}

local function applyRowLayout(button, def)
	local title = button:FindFirstChild("Title")
	local keybind = button:FindFirstChild("Keybind")
	local check = button:FindFirstChild("Check")
	local icon = button:FindFirstChild("Icon")

	if icon then
		icon.Rotation = def.iconRotation or 0
		if def.iconColor then
			icon:SetAttribute("ThemeImg", nil)
			icon.ImageColor3 = def.iconColor
		end

		if def.vectorIcon == "ClearTransform" then
			icon.Image = ""
			icon.Visible = true
			icon.Size = UDim2.new(def.iconSize[1], 0, def.iconSize[2], 0)
			local drawing = Instance.new("Frame")
			drawing.Name = "GeneratedResetIcon"
			drawing.BackgroundTransparency = 1
			drawing.Size = UDim2.fromScale(1, 1)
			drawing.ZIndex = icon.ZIndex
			drawing.Parent = icon

			local function line(a, b)
				local d = b - a
				local p = Instance.new("Frame")
				p.AnchorPoint = Vector2.new(0.5, 0.5)
				p.Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2)
				p.Size = UDim2.new(d.Magnitude, 0, 0, 1)
				p.Rotation = math.deg(math.atan2(d.Y, d.X))
				p.BorderSizePixel = 0
				p.BackgroundColor3 = icon.ImageColor3
				p.BackgroundTransparency = icon.ImageTransparency
				p.ZIndex = icon.ZIndex + 1
				p.Parent = drawing
			end

			for i = 0, 11 do
				local a, b = math.rad(-135 + i * 25), math.rad(-135 + (i + 1) * 25)
				line(
					Vector2.new(0.5 + math.cos(a) * 0.34, 0.5 + math.sin(a) * 0.34),
					Vector2.new(0.5 + math.cos(b) * 0.34, 0.5 + math.sin(b) * 0.34)
				)
			end

			line(Vector2.new(0.16, 0.16), Vector2.new(0.26, 0.26))
			line(Vector2.new(0.16, 0.16), Vector2.new(0.35, 0.16))
			line(Vector2.new(0.16, 0.16), Vector2.new(0.16, 0.35))
			line(Vector2.new(0.38, 0.5), Vector2.new(0.62, 0.5))
			line(Vector2.new(0.5, 0.38), Vector2.new(0.5, 0.62))
			icon:GetPropertyChangedSignal("ImageColor3"):Connect(function()
				for _, p in drawing:GetChildren() do
					p.BackgroundColor3 = icon.ImageColor3
				end
			end)
			icon:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
				for _, p in drawing:GetChildren() do
					p.BackgroundTransparency = icon.ImageTransparency
				end
			end)
		elseif def.vectorIcon or def.fallbackVectorIcon then
			local kind = def.vectorIcon or def.fallbackVectorIcon
			icon.Image = def.icon or ""
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Visible = true
			if def.iconSize then
				icon.Size = UDim2.new(def.iconSize[1], 0, def.iconSize[2], 0)
			end

			local drawing = Instance.new("Frame")
			drawing.Name = "Generated" .. kind
			drawing.BackgroundTransparency = 1
			drawing.Size = UDim2.fromScale(1, 1)
			drawing.ZIndex = icon.ZIndex
			drawing.Parent = icon
			if def.icon and def.icon ~= "" then
				drawing:SetAttribute("EclipseRasterFallback", true)

				local function ready()
					drawing.Visible = not icon.IsLoaded
				end

				ready()
				icon:GetPropertyChangedSignal("IsLoaded"):Connect(ready)
				task.defer(ready)
			end

			local function line(x, y, a, b)
				local from, to = Vector2.new(x, y), Vector2.new(a, b)
				local d = to - from
				local p = Instance.new("Frame")
				p.AnchorPoint = Vector2.new(0.5, 0.5)
				p.Position = UDim2.fromScale((x + a) / 2, (y + b) / 2)
				p.Size = UDim2.new(d.Magnitude, 0, 0, def.iconStroke or 1)
				p.Rotation = math.deg(math.atan2(d.Y, d.X))
				p.BorderSizePixel = 0
				p.BackgroundColor3 = icon.ImageColor3
				p.BackgroundTransparency = icon.ImageTransparency
				p.ZIndex = icon.ZIndex + 1
				p.Parent = drawing
			end

			if kind == "PoseSliders" then
				for i, x in { 0.3, 0.7, 0.45 } do
					local y = 0.2 + (i - 1) * 0.3
					line(0.12, y, 0.88, y)
					line(x, y - 0.09, x, y + 0.09)
				end
			elseif kind == "AutoIK" then
				line(0.15, 0.83, 0.46, 0.52)
				line(0.46, 0.52, 0.72, 0.18)
				for _, point in { { 0.15, 0.83 }, { 0.46, 0.52 }, { 0.72, 0.18 } } do
					for i = 0, 7 do
						local a, b = i * math.pi / 4, (i + 1) * math.pi / 4
						line(
							point[1] + math.cos(a) * 0.08,
							point[2] + math.sin(a) * 0.08,
							point[1] + math.cos(b) * 0.08,
							point[2] + math.sin(b) * 0.08
						)
					end
				end

				line(0.58, 0.18, 0.86, 0.18)
				line(0.72, 0.04, 0.72, 0.32)
			elseif kind == "MotionPaths" then
				local previous
				for i = 0, 16 do
					local t = i / 16
					local x = 0.15 + 0.7 * t
					local y = 0.85 - 0.7 * (3 * t * t - 2 * t * t * t)
					if previous then
						line(previous.X, previous.Y, x, y)
					end

					previous = Vector2.new(x, y)
				end

				for _, p in { { 0.15, 0.85 }, { 0.5, 0.5 }, { 0.85, 0.15 } } do
					for i = 0, 7 do
						local a, b = i * math.pi / 4, (i + 1) * math.pi / 4
						line(
							p[1] + math.cos(a) * 0.07,
							p[2] + math.sin(a) * 0.07,
							p[1] + math.cos(b) * 0.07,
							p[2] + math.sin(b) * 0.07
						)
					end
				end

				line(0.72, 0.08, 0.92, 0.12)
				line(0.92, 0.12, 0.85, 0.3)
			elseif kind == "BoneDynamics" then
				line(0.2, 0.12, 0.2, 0.4)
				line(0.2, 0.4, 0.43, 0.66)
				line(0.43, 0.66, 0.35, 0.91)
				line(0.12, 0.12, 0.28, 0.12)
				line(0.12, 0.4, 0.28, 0.4)
				for _, y in { 0.28, 0.53, 0.78 } do
					line(0.58, y, 0.8, y - 0.05)
					line(0.8, y - 0.05, 0.94, y)
					line(0.94, y, 0.82, y + 0.06)
				end
			elseif kind == "GridSettings" then
				for _, v in { 0.12, 0.38, 0.64 } do
					line(v, 0.12, v, 0.76)
					line(0.12, v, 0.76, v)
				end

				line(0.76, 0.12, 0.76, 0.58)
				line(0.12, 0.76, 0.56, 0.76)
				line(0.68, 0.84, 0.96, 0.84)
				line(0.82, 0.69, 0.82, 0.97)
			elseif kind == "BoneControls" then
				for _, row in { { 0.27, 0.38 }, { 0.72, 0.67 } } do
					local y, x = row[1], row[2]
					line(0.1, y, x - 0.1, y)
					line(x + 0.1, y, 0.9, y)
					line(x - 0.1, y - 0.12, x + 0.1, y - 0.12)
					line(x + 0.1, y - 0.12, x + 0.1, y + 0.12)
					line(x + 0.1, y + 0.12, x - 0.1, y + 0.12)
					line(x - 0.1, y + 0.12, x - 0.1, y - 0.12)
				end
			elseif kind == "BoneCollection" then
				line(0.08, 0.13, 0.08, 0.88)
				line(0.08, 0.13, 0.3, 0.13)
				line(0.08, 0.88, 0.3, 0.88)
				for _, y in { 0.32, 0.7 } do
					line(0.35, y, 0.55, y - 0.14)
					line(0.55, y - 0.14, 0.86, y)
					line(0.86, y, 0.55, y + 0.14)
					line(0.55, y + 0.14, 0.35, y)
				end
			elseif kind == "CameraShake" then
				line(0.24, 0.32, 0.76, 0.32)
				line(0.76, 0.32, 0.76, 0.76)
				line(0.76, 0.76, 0.24, 0.76)
				line(0.24, 0.76, 0.24, 0.32)
				line(0.33, 0.32, 0.4, 0.2)
				line(0.4, 0.2, 0.6, 0.2)
				line(0.6, 0.2, 0.67, 0.32)
				for i = 0, 11 do
					local a, b = i * math.pi / 6, (i + 1) * math.pi / 6
					line(
						0.5 + math.cos(a) * 0.14,
						0.54 + math.sin(a) * 0.14,
						0.5 + math.cos(b) * 0.14,
						0.54 + math.sin(b) * 0.14
					)
				end

				line(0.1, 0.29, 0.05, 0.47)
				line(0.05, 0.47, 0.1, 0.68)
				line(0.9, 0.29, 0.95, 0.47)
				line(0.95, 0.47, 0.9, 0.68)
			elseif kind == "Pivot" then
				for i = 0, 11 do
					local a, b = i * math.pi / 6, (i + 1) * math.pi / 6
					line(
						0.5 + math.cos(a) * 0.28,
						0.5 + math.sin(a) * 0.28,
						0.5 + math.cos(b) * 0.28,
						0.5 + math.sin(b) * 0.28
					)
				end

				line(0.5, 0.06, 0.5, 0.3)
				line(0.5, 0.7, 0.5, 0.94)
				line(0.06, 0.5, 0.3, 0.5)
				line(0.7, 0.5, 0.94, 0.5)
				line(0.43, 0.5, 0.57, 0.5)
				line(0.5, 0.43, 0.5, 0.57)
			elseif kind == "Save" or kind == "SaveAs" or kind == "SaveClose" then
				local s = kind == "Save" and 1 or 0.7

				local function draw(x, y, a, b)
					line(x * s, y * s, a * s, b * s)
				end

				draw(0.16, 0.14, 0.7, 0.14)
				draw(0.7, 0.14, 0.86, 0.3)
				draw(0.86, 0.3, 0.86, 0.86)
				draw(0.86, 0.86, 0.16, 0.86)
				draw(0.16, 0.86, 0.16, 0.14)
				draw(0.32, 0.14, 0.32, 0.38)
				draw(0.32, 0.38, 0.64, 0.38)
				draw(0.64, 0.38, 0.64, 0.14)
				draw(0.3, 0.86, 0.3, 0.58)
				draw(0.3, 0.58, 0.72, 0.58)
				draw(0.72, 0.58, 0.72, 0.86)
				if kind == "SaveAs" then
					line(0.8, 0.6, 0.8, 0.98)
					line(0.61, 0.79, 0.99, 0.79)
				elseif kind == "SaveClose" then
					line(0.64, 0.64, 0.96, 0.96)
					line(0.96, 0.64, 0.64, 0.96)
				end
			elseif kind == "ImpactFrames" then
				local points = {
					{ 0.5, 0.08 },
					{ 0.59, 0.34 },
					{ 0.85, 0.18 },
					{ 0.69, 0.46 },
					{ 0.94, 0.55 },
					{ 0.67, 0.62 },
					{ 0.79, 0.88 },
					{ 0.54, 0.71 },
					{ 0.4, 0.95 },
					{ 0.36, 0.67 },
					{ 0.08, 0.77 },
					{ 0.25, 0.52 },
					{ 0.06, 0.33 },
					{ 0.35, 0.36 },
				}
				for i, p in points do
					local q = points[i % #points + 1]
					line(p[1], p[2], q[1], q[2])
				end
			else
				for i = 0, 7 do
					local a, b = math.pi + i * math.pi / 8, math.pi + (i + 1) * math.pi / 8
					line(
						0.45 + math.cos(a) * 0.27,
						0.42 + math.sin(a) * 0.27,
						0.45 + math.cos(b) * 0.27,
						0.42 + math.sin(b) * 0.27
					)
				end

				line(0.18, 0.42, 0.18, 0.82)
				line(0.18, 0.82, 0.32, 0.7)
				line(0.32, 0.7, 0.45, 0.82)
				line(0.45, 0.82, 0.59, 0.7)
				line(0.59, 0.7, 0.72, 0.82)
				line(0.72, 0.82, 0.72, 0.42)
				line(0.34, 0.39, 0.34, 0.48)
				line(0.55, 0.39, 0.55, 0.48)
				if kind == "CaptureOnionSkin" then
					line(0.73, 0.12, 0.73, 0.42)
					line(0.58, 0.27, 0.88, 0.27)
				elseif kind == "ApplyOnionSkin" then
					line(0.48, 0.74, 0.65, 0.9)
					line(0.65, 0.9, 0.96, 0.51)
				elseif kind == "ClearOnionSkin" then
					line(0.6, 0.64, 0.92, 0.96)
					line(0.92, 0.64, 0.6, 0.96)
				else
					line(0.06, 0.48, 0.06, 0.93)
					line(0.06, 0.93, 0.43, 0.93)
				end
			end

			icon:GetPropertyChangedSignal("ImageColor3"):Connect(function()
				for _, p in drawing:GetChildren() do
					p.BackgroundColor3 = icon.ImageColor3
				end
			end)
			icon:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
				for _, p in drawing:GetChildren() do
					p.BackgroundTransparency = icon.ImageTransparency
				end
			end)
		elseif def.icon then
			icon.Image = def.icon
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Visible = true
			if def.iconSize then
				icon.Size = UDim2.new(def.iconSize[1], 0, def.iconSize[2], 0)
			end

			if def.iconColor then
				icon:SetAttribute("ThemeImg", nil)
				icon.ImageColor3 = def.iconColor
			else
				icon.ImageColor3 = Color3.new(1, 1, 1)
			end
		else
			icon.Visible = false
		end
	end

	if icon and def.fallbackIcon == "DeleteItem" then
		local drawing = Instance.new("Frame")
		drawing.Name = "DeleteItemFallback"
		drawing.BackgroundTransparency = 1
		drawing.Size = UDim2.fromScale(1, 1)
		drawing.ZIndex = icon.ZIndex + 1
		drawing.Parent = icon

		local function line(x, y, a, b)
			local d = Vector2.new(a - x, b - y)
			local stroke = Instance.new("Frame")
			stroke.AnchorPoint = Vector2.new(0.5, 0.5)
			stroke.Position = UDim2.fromScale((x + a) / 2, (y + b) / 2)
			stroke.Size = UDim2.new(d.Magnitude, 0, 0, 1)
			stroke.Rotation = math.deg(math.atan2(d.Y, d.X))
			stroke.BorderSizePixel = 0
			stroke.ZIndex = drawing.ZIndex
			stroke.Parent = drawing
		end

		line(0.12, 0.24, 0.42, 0.08)
		line(0.42, 0.08, 0.72, 0.24)
		line(0.72, 0.24, 0.42, 0.40)
		line(0.42, 0.40, 0.12, 0.24)
		line(0.12, 0.24, 0.12, 0.62)
		line(0.12, 0.62, 0.42, 0.79)
		line(0.42, 0.79, 0.42, 0.40)
		line(0.72, 0.24, 0.72, 0.49)
		for i = 0, 11 do
			local a, b = i * math.pi / 6, (i + 1) * math.pi / 6
			line(
				0.76 + math.cos(a) * 0.19,
				0.76 + math.sin(a) * 0.19,
				0.76 + math.cos(b) * 0.19,
				0.76 + math.sin(b) * 0.19
			)
		end

		line(0.65, 0.76, 0.87, 0.76)

		local function update()
			drawing.Visible = not icon.IsLoaded
			for _, stroke in drawing:GetChildren() do
				stroke.BackgroundColor3 = icon.ImageColor3
				stroke.BackgroundTransparency = icon.ImageTransparency
			end
		end

		icon:GetPropertyChangedSignal("IsLoaded"):Connect(update)
		icon:GetPropertyChangedSignal("ImageColor3"):Connect(update)
		icon:GetPropertyChangedSignal("ImageTransparency"):Connect(update)
		update()
	end

	local hintAction = HINTS[def.id] or (Shortcuts.get(def.id) and def.id)

	local function updateHint()
		if keybind and hintAction then
			local value = Shortcuts.get(hintAction)
			keybind.Text = value and value.Key and Shortcuts.format(hintAction):gsub(" ", "") or ""
			keybind.Visible = keybind.Text ~= ""
			if def.compact then
				local width = keybind.Visible and math.clamp(#keybind.Text * 4.5 + 6, 28, 78) or 0
				keybind.Size = UDim2.new(0, width, 1, -4)
				if title then
					title.Size = UDim2.new(1, -30 - width, 1, -4)
				end
			end
		end
	end

	if hintAction then
		local unsubscribe = Shortcuts.subscribe(updateHint, hintAction)
		button.Destroying:Once(unsubscribe)
		task.defer(updateHint)
	end

	local keybindText = def.keybind
	local hasKeybind = keybindText ~= nil and keybindText ~= ""
	local longKeybind = hasKeybind and #keybindText > LONG_KEYBIND_LENGTH

	if keybind then
		if hasKeybind then
			keybind.Visible = true
			keybind.Text = keybindText
			keybind.AnchorPoint = Vector2.new(1, 0.5)
			keybind.Position =
				UDim2.new(def.checkable and not def.leftCheck and 0.82 or 0.97, 0, 0.49, 0)
			if longKeybind then
				keybind.Size = UDim2.new(0.43, 0, 0.375, 0)
			else
				keybind.Size = UDim2.new(0.26, 0, 0.4166, 0)
			end
		else
			keybind.Visible = false
		end
	end

	if check then
		check.Visible = false
		if def.leftCheck then
			check.AnchorPoint = Vector2.new(0.5, 0.5)
			check.Position = icon and icon.Position or UDim2.fromScale(0.084, 0.5)
			if icon and def.icon then
				check:GetPropertyChangedSignal("Visible"):Connect(function()
					icon.Visible = not check.Visible
				end)
			end
		end
	end

	local arrow = button:FindFirstChild("Arrow")
	if arrow then
		if def.submenu or def.rightIcon then
			arrow.Visible = true
			if def.rightIcon then
				arrow.Image = def.rightIcon
			end

			if def.rightIconSize then
				arrow.Size = UDim2.new(def.rightIconSize[1], 0, def.rightIconSize[2], 0)
			end
		else
			arrow:Destroy()
		end
	end

	if title then
		title.Text = def.text or def.id
		title.AnchorPoint = Vector2.new(0, 0.5)
		title.Position = UDim2.new(0.163, 0, 0.49, 0)
		if longKeybind then
			title.Size = UDim2.new(0.46, 0, 0.458, 0)
		elseif hasKeybind then
			title.Size = UDim2.new(def.checkable and not def.leftCheck and 0.39 or 0.62, 0, 0.5, 0)
		elseif def.submenu or def.rightIcon then
			title.Size = UDim2.new(0.62, 0, 0.5, 0)
		elseif def.checkable then
			title.Size = UDim2.new(0.557, 0, 0.5, 0)
		else
			title.Size = UDim2.new(0.68, 0, 0.5, 0)
		end
	end

	if def.compact then
		if check and def.leftCheck then
			check.AnchorPoint = Vector2.new(0.5, 0.5)
			check.Position = UDim2.new(0, 12, 0.5, 0)
			check.Size = UDim2.fromOffset(12, 12)
			check.ScaleType = Enum.ScaleType.Fit
		end

		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0, 12, 0.5, 0)
			local iconSize = def.compactIconSize or 16
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
		end

		local hintWidth = hasKeybind and (longKeybind and 58 or 38) or 0
		if title then
			title.Position = UDim2.new(0, 24, 0.5, 0)
			title.Size = UDim2.new(1, -30 - hintWidth, 1, -4)
			title.TextScaled = false
			title.TextSize = 10
			title.TextXAlignment = Enum.TextXAlignment.Left
		end

		if keybind then
			keybind.Position = UDim2.new(1, -6, 0.5, 0)
			keybind.Size = UDim2.new(0, hintWidth, 1, -4)
			keybind.TextScaled = false
			keybind.TextSize = 7
			keybind.TextWrapped = false
			keybind.TextTruncate = Enum.TextTruncate.None
			keybind.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
end

function Dropdown.build(template, name, config)
	if not template then
		return nil
	end

	local frame = template:Clone()
	frame.Name = name
	frame.Visible = false
	if config.width then
		frame.Size = UDim2.new(0, config.width, 0, 0)
	end

	local content = frame:FindFirstChild("Content")
	if content and config.width then
		content.Size = UDim2.new(1, -8, content.Size.Y.Scale, content.Size.Y.Offset)
	end

	local rowTemplate = content and content:FindFirstChild("RowTemplate")
	local dividerTemplate = content and content:FindFirstChild("DividerTemplate")
	if not content or not rowTemplate then
		return frame
	end

	for order, def in ipairs(config.rows) do
		if def == "divider" or (typeof(def) == "table" and def.divider) then
			if dividerTemplate then
				local divider = dividerTemplate:Clone()
				divider.Name = "Divider"
				divider.Visible = true
				divider.LayoutOrder = order
				divider.Parent = content
			end
		else
			local row = rowTemplate:Clone()
			row.Name = def.id
			row.Visible = true
			row.LayoutOrder = order
			local button = row:FindFirstChildWhichIsA("GuiButton")
			if button then
				button.Name = def.id .. "Button"
				local layoutDef = table.clone(def)
				layoutDef.compact = config.compact or config.menubar ~= nil
				applyRowLayout(button, layoutDef)
			end

			row.Parent = content
		end
	end

	rowTemplate:Destroy()
	if dividerTemplate then
		dividerTemplate:Destroy()
	end

	return frame
end

return Dropdown
