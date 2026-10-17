--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local Surface = require("Surface")
local Chrome = require("Chrome")
local WindowFX = require("WindowFX")
local Notification = require("Notification")
local Theme = require("Theme")
local Batch = require("Batch")
local Selection = game:GetService("Selection")
local Input = game:GetService("UserInputService")

local Results = {}
local refs, latest, window = {}, {}, nil
local lifetime = {}
local retiring = {}
local publishing = false
local rowViews = {}
local Z = 230
local HALFTONE = "rbxassetid://71635441690027"
const PUBLISH_FOLDER = "EclipsePublish"
const publishCopies = setmetatable({}, { __mode = "k" })

local function make(class, parent, name, properties)
	local object = Instance.new(class)
	object.Name = name
	for key, value in properties do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function surface(object, key, radius)
	object.BorderSizePixel = 0
	object:SetAttribute("ThemeBg", key)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius or 5) })
end

local function text(parent, name, value, position, size, fontSize)
	local label = make("TextLabel", parent, name, {
		Text = value,
		Position = position,
		Size = size,
		TextSize = fontSize or 12,
		FontFace = Chrome.FONT,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = Z + 3,
	})
	label:SetAttribute("ThemeTxt", "Txt")
	return label
end

function Results.close(immediate)
	if not window then
		return
	end

	for index, view in rowViews do
		if view.name:IsFocused() then
			Results.rename(index, view.name.Text)
		end
	end

	local old = window
	window = nil
	table.clear(rowViews)
	retiring[old] = true

	local function dispose()
		retiring[old] = nil
		WindowFX.clear(old)
		old:Destroy()
	end

	if immediate or not old.Visible then
		dispose()
	else
		WindowFX.shrink(old, dispose)
	end
end

function Results.clear()
	Results.close()
	latest = {}
end

function Results.hasFocus()
	if not window or not refs.ScreenGui.Enabled then
		return false
	end

	local point = Input:GetMouseLocation()
	local p, s = window.AbsolutePosition, window.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y
end

function Results.rename(index, value)
	local result = latest[index]
	if not result then
		return false
	end

	local ok, name = Batch.rename(result, value)
	local view = rowViews[index]
	if view then
		view.name.Text = result.animationName or ""
	end

	if not ok then
		Notification.show("EXPORT", name)
	end

	return ok, name
end

local function clearPublishCopies()
	for source, copy in publishCopies do
		copy:Destroy()
		publishCopies[source] = nil
	end

	const folder = require("root").get(PUBLISH_FOLDER)
	if folder then
		folder:Destroy()
	end
end

local function publishable(result)
	const source = result.sequence
	if not source or not source.Parent then
		return result
	end

	const previous = publishCopies[source]
	if previous then
		previous:Destroy()
		publishCopies[source] = nil
	end

	const ok, copy = pcall(require("Animation").publishCopy, source)
	if not ok then
		warn("[Eclipse export] Publishing the full export because a clean copy failed: " .. tostring(copy))
		return result
	end

	copy.Name = source.Name
	copy.Parent = require("root").get(PUBLISH_FOLDER, true)
	publishCopies[source] = copy
	return { sequence = copy }
end

function Results.publish(index)
	local result = latest[index]
	if publishing or not result then
		return false
	end

	local current, view = window, rowViews[index]

	if view then
		local renamed, err = Results.rename(index, view.name.Text)
		if not renamed then
			return false, err
		end
	end

	publishing = true
	if view then
		view.label.Text = "OPENING..."
	end

	local state = refs.State
	local ignoring = state and state.ignoreSelectionChanged
	if state then
		state.ignoreSelectionChanged = true
	end

	local ok, err = Batch.publish(publishable(result), refs.Plugin, refs.Selection or Selection)
	if state then
		state.ignoreSelectionChanged = ignoring
	end

	publishing = false
	if window == current and view then
		view.label.Text = "SAVE TO ROBLOX"
		if not ok then
			Notification.show("EXPORT", err)
		end

		if ok and #latest == 1 then
			Results.close()
		end
	end

	return ok, err
end

function Results.open()
	if window then
		return window
	end

	if not refs.ScreenGui or not refs.ScreenGui.Enabled then
		return
	end

	local count, exported = #latest, 0
	for _, result in latest do
		if result.sequence then
			exported += 1
		end
	end

	local height = 184 + math.clamp(count, 1, 5) * 72
	window = make("CanvasGroup", refs.ScreenGui, "ExportResults", {
		Visible = false,
		GroupTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(400, height),
		Active = true,
		BackgroundColor3 = Color3.fromRGB(20, 12, 28),
		ZIndex = Z,
	})
	Surface.backdrop(window)
	local current = window
	local header, _, drag = Chrome.header(window, "EXPORTED ANIMATIONS", Z + 1, 42)
	Chrome.close(header, function()
		Results.close()
	end, Z + 5)
	local body = make("Frame", window, "Body", {
		Position = UDim2.fromOffset(4, Chrome.HEIGHT),
		Size = UDim2.new(1, -8, 1, -Chrome.HEIGHT - 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = Z + 1,
	})
	surface(body, "Bg")
	Surface.fill(body)
	body:SetAttribute("ThemeBgImage", 1)
	local summary = count == 0 and "No exports yet"
		or string.format("%d / %d Rigs Exported", exported, count)
	text(body, "Summary", summary, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 42), 28)
	local list = make("ScrollingFrame", body, "Animations", {
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -24, 1, -152),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = Z + 2,
	})
	list:SetAttribute("ThemeScr", "Div")
	make(
		"UIListLayout",
		list,
		"Layout",
		{ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	for index, result in latest do
		local row = make("Frame", list, "Rig" .. index, {
			Size = UDim2.new(1, -8, 0, 64),
			LayoutOrder = index,
			BackgroundColor3 = Color3.fromRGB(28, 19, 38),
			BackgroundTransparency = 0.12,
			ZIndex = Z + 2,
		})
		surface(row, "Pnl")
		local halftone = make("ImageLabel", row, "Halftone", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 1, -12),
			BackgroundTransparency = 1,
			Image = HALFTONE,
			ImageTransparency = 0.94,
			ImageColor3 = Color3.new(1, 1, 1),
			ZIndex = Z + 2,
		})
		local tint = make("UIGradient", halftone, "Tint", {
			Color = ColorSequence.new(Color3.fromRGB(235, 228, 242)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.12, 0),
				NumberSequenceKeypoint.new(0.88, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
		tint:SetAttribute("ThemeGrad", "Txt")
		make("UICorner", halftone, "Corner", { CornerRadius = UDim.new(0, 5) })
		local outline = make("UIStroke", row, "Outline", { Thickness = 1, Transparency = 0.5 })
		outline:SetAttribute("ThemeStrk", "Strk")
		text(row, "RigName", result.rigName, UDim2.fromOffset(12, 8), UDim2.new(1, -164, 0, 21), 13)
		if result.sequence then
			result.animationName = result.sequence.Name
			local name = make("TextBox", row, "AnimationName", {
				Text = result.animationName,
				Position = UDim2.fromOffset(12, 32),
				Size = UDim2.new(1, -164, 0, 23),
				FontFace = Chrome.FONT,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = Color3.fromRGB(235, 228, 242),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClearTextOnFocus = true,
				MultiLine = false,
				ZIndex = Z + 3,
			})
			name:SetAttribute("ThemeTxt", "Txt")
			name.FocusLost:Connect(function(_, input)
				if window ~= current or latest[index] ~= result then
					return
				end

				if input and Shortcuts.matches("Cancel", input) then
					name.Text = result.sequence.Name
				else
					Results.rename(index, name.Text)
				end
			end)
			local save, label = Chrome.menuButton(
				row,
				"SaveToRoblox",
				"SAVE TO ROBLOX",
				UDim2.new(1, -140, 0, 17),
				UDim2.fromOffset(128, 30),
				Z + 4
			)
			rowViews[index] = { label = label, name = name }
			save.Activated:Connect(function()
				Results.publish(index)
			end)

			const notice = result.sequence:GetAttribute("EclipseExportNotice")
			if typeof(notice) == "string" and notice ~= "" then
				row.Size = UDim2.new(1, -8, 0, 100)
				const line = text(
					row,
					"Notice",
					notice,
					UDim2.fromOffset(12, 58),
					UDim2.new(1, -24, 0, 36),
					11
				)
				line.TextWrapped = true
				line.TextTruncate = Enum.TextTruncate.None
				line.TextYAlignment = Enum.TextYAlignment.Top
				line.TextColor3 = Color3.fromRGB(255, 196, 120)
				line:SetAttribute("ThemeTxt", nil)
			end
		else
			text(
				row,
				"AnimationName",
				"Export failed",
				UDim2.fromOffset(12, 32),
				UDim2.new(1, -24, 0, 23),
				12
			)
		end
	end

	local footer = text(
		body,
		"Footer",
		"File > Export Results to see these animation results without re-exporting",
		UDim2.new(0, 12, 1, -51),
		UDim2.new(1, -24, 0, 44),
		14
	)
	footer.TextWrapped = true
	footer.TextTruncate = Enum.TextTruncate.None
	const groupOwned = game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0
	const ownership = text(
		body,
		"Ownership",
		if groupOwned
			then "This experience is owned by a group. In Save to Roblox, set Creator to that group or the animation won't play here."
			else "Animations only play in experiences owned by their creator. For a group game, set Creator to the group in Save to Roblox.",
		UDim2.new(0, 12, 1, -88),
		UDim2.new(1, -24, 0, 34),
		12
	)
	ownership.TextWrapped = true
	ownership.TextTruncate = Enum.TextTruncate.None
	Chrome.bindDrag(window, drag, { clamp = true, margin = 8 })

	Theme.applyInstance(window)
	for _, object in window:GetDescendants() do
		Theme.applyInstance(object)
	end

	task.defer(function()
		if window ~= current or not current.Parent then
			return
		end

		current.Visible = true
		WindowFX.pop(current)
	end)
	return window
end

function Results.show(results)
	Results.close()
	latest = results
	return Results.open()
end

function Results.destroy()
	Results.close(true)
	latest = {}
	pcall(clearPublishCopies)
	for old in retiring do
		WindowFX.clear(old)
		old:Destroy()
	end

	table.clear(retiring)
	for _, connection in lifetime do
		connection:Disconnect()
	end

	table.clear(lifetime)
	if refs.State then
		refs.State.ExportResults = nil
	end

	refs = {}
end

function Results.init(options)
	Results.destroy()
	refs = options
	if refs.State then
		refs.State.ExportResults = Results
	end

	table.insert(
		lifetime,
		refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then
				Results.close(true)
			end
		end)
	)
	table.insert(
		lifetime,
		refs.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not refs.AnimatorFrame.Visible then
				Results.clear()
			end
		end)
	)
	table.insert(lifetime, refs.ScreenGui.Destroying:Connect(Results.destroy))
	if refs.Plugin then
		table.insert(lifetime, refs.Plugin.Unloading:Connect(Results.destroy))
	end
end

return Results
