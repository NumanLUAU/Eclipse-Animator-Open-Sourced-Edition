--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Window = {}
local Tool = require("Tool")
local Layers = require("Layers")
local Theme = require("Theme")
local Input = require("UserInputService")
local Chrome = require("Chrome")
local Raw = require("RawState").Timeline
local refs, window, unsubscribe, windowTooltip

local function center(object)
	local p, s, a = object.Position, object.Size, object.AnchorPoint
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.new(
		p.X.Scale + s.X.Scale * (0.5 - a.X),
		p.X.Offset + s.X.Offset * (0.5 - a.X),
		p.Y.Scale + s.Y.Scale * (0.5 - a.Y),
		p.Y.Offset + s.Y.Offset * (0.5 - a.Y)
	)
	return object
end

local function tip(object, text)
	object:SetAttribute("Tooltip", text)
	local hover = windowTooltip or refs.State.UIHelpers and refs.State.UIHelpers.hoverDialog
	if hover then
		hover:latchToInstance(object, text, { maxWidth = 300 })
	end
end

local function button(parent, name, text, x, y, w, h, fn, help)
	local object, label =
		Tool.button(parent, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h), fn)
	center(object)
	center(label)
	if help then
		tip(object, help)
	end

	return object, label
end

local function label(parent, name, text, x, y, w, h)
	return center(Tool.label(parent, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)))
end

local function field(parent, name, text, x, y, w, h)
	local box = Tool.field(parent, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h))
	center(box.Parent)
	center(box)
	return box
end

function Window.close(immediate)
	if window then
		local previous = window
		window = nil
		previous:close(immediate == true)
	end
end

function Window.isOpen()
	return window ~= nil
end

function Window.open()
	if window then
		return window.frame
	end

	if not refs.State.currentRig then
		require("Notification").show("ANIMATION LAYERS", "Open a project first.")
		return
	end

	Layers.ensure(Raw)
	local cancelDrag
	local view = Tool.new(refs, "AnimationLayers", "ANIMATION LAYERS", Vector2.new(390, 402), true, function()
		if cancelDrag then
			cancelDrag()
		end

		if windowTooltip then
			windowTooltip:Destroy()
			windowTooltip = nil
		end

		window = nil
		if unsubscribe then
			unsubscribe()
			unsubscribe = nil
		end
	end
)
	window = view
	local frame = view.frame
	local shared = refs.State.UIHelpers and refs.State.UIHelpers.hoverDialog
	if shared and shared.ui then
		local tipUI = shared.ui:Clone()
		tipUI.Name = "LayerTooltip"
		tipUI.Parent = view.gui
		local oldLimit = tipUI.Information:FindFirstChild("TooltipSizeLimit")
		if oldLimit then
			oldLimit:Destroy()
		end

		windowTooltip = require("HoverDialog").initialize(tipUI, shared.mouse)
		table.insert(
			view.connections,
			frame.AncestryChanged:Connect(function()
				if view.closed or not windowTooltip or windowTooltip.destroyed then
					return
				end

				local host = frame:FindFirstAncestorWhichIsA("LayerCollector")

				local destination = host and host:IsA("DockWidgetPluginGui") and host or view.gui
				if destination.Parent and tipUI.Parent ~= destination then
					windowTooltip:disappear()
					tipUI.Parent = destination
				end

				if host and host:IsA("ScreenGui") then
					view.gui.DisplayOrder = host ~= view.gui and host.DisplayOrder + 1
						or refs.ScreenGui.DisplayOrder + 20
				end
			end)
		)
	end

	local container = Tool.make("Frame", frame, "LayerListPanel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 139),
		Size = UDim2.new(1, -24, 0, 154),
		BackgroundColor3 = Color3.fromRGB(18, 14, 27),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	container:SetAttribute("ThemeBg", "Bg")
	container:SetAttribute("ThemeBgTransparency", 0.15)
	Tool.make("UICorner", container, "Corner", { CornerRadius = UDim.new(0, 4) })
	local outline = Tool.make(
		"UIStroke",
		container,
		"Outline",
		{ Color = Color3.fromRGB(69, 41, 93), Thickness = 1, Transparency = 0.25 }
	)
	outline:SetAttribute("ThemeStrk", "Strk")
	local list = Tool.make("ScrollingFrame", container, "Layers", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 1, -16),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 13,
	})
	label(frame, "StackLabel", "LAYERS", 12, 38, 70, 18)
	local legend = label(frame, "ControlsLegend", "M: Mute   S: Solo   L: Lock", 94, 38, 284, 18)
	legend.TextXAlignment = Enum.TextXAlignment.Right
	tip(legend, "Mute / Solo / Lock")
	local activeText = label(frame, "ActiveLabel", "", 12, 263, 364, 20)
	activeText.TextTruncate = Enum.TextTruncate.AtEnd
	local add = button(
		frame,
		"Add",
		"+ LAYER",
		12,
		225,
		101,
		27,
		Layers.add,
		"Create an additive layer. New keys go on the selected layer."
	)
	button(frame, "Duplicate", "COPY", 119, 225, 71, 27, function()
		Layers.duplicate(Layers.active(Raw).id)
	end, "Duplicate the selected layer")
	button(frame, "Raise", "\u{2191}", 196, 225, 39, 27, function()
		Layers.move(Layers.active(Raw).id, 1)
	end, "Move above the next layer")
	button(frame, "Lower", "\u{2193}", 241, 225, 39, 27, function()
		Layers.move(Layers.active(Raw).id, -1)
	end, "Move below the next layer")
	button(frame, "Delete", "DELETE", 286, 225, 92, 27, function()
		Layers.remove(Layers.active(Raw).id)
	end, "Delete selected layer. Undo restores it.")
	local additive, addText = button(frame, "Additive", "ADDITIVE", 12, 291, 180, 27, function()
		Layers.change(Layers.active(Raw).id, "mode", "Additive")
	end, "Adds a correction to the animation below")
	local override, overrideText = button(frame, "Override", "OVERRIDE", 198, 291, 180, 27, function()
		Layers.change(Layers.active(Raw).id, "mode", "Override")
	end, "Blends keyed tracks toward this layer\u{2019}s pose")
	local blendLabel = label(frame, "WeightLabel", "BLEND %", 12, 328, 70, 24)
	tip(blendLabel, "How much this layer affects the animation")
	local weightBox = field(frame, "Weight", "100", 285, 328, 57, 25)
	local keyButton, keyText = button(frame, "KeyWeight", "\u{25c7}", 348, 328, 30, 25, function()
		Layers.keyWeight(Layers.active(Raw).id)
	end, "Key blend")
	local slider = Tool.make("TextButton", frame, "WeightSlider", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(179, 341),
		Size = UDim2.fromOffset(192, 24),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = 14,
	})
	local rail = Tool.make("Frame", slider, "Rail", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 3),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(69, 41, 93),
		ZIndex = 14,
	})
	rail:SetAttribute("ThemeBg", "Strk")
	local fill = Tool.make("Frame", rail, "Fill", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(194, 120, 174),
		ZIndex = 15,
	})
	fill:SetAttribute("ThemeBg", "KeySel")
	local knob = Tool.make("Frame", slider, "Handle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(9, 16),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(235, 228, 242),
		ZIndex = 16,
	})
	knob:SetAttribute("ThemeBg", "Txt")

	local function jump(direction)
		local layer = Layers.active(Raw)
		local frameNumber = Raw.CurrentTime * Raw.FPS
		local target
		for f in layer.weightKeys or {} do
			if
				direction < 0 and f < frameNumber - 0.001 and (not target or f > target)
				or direction > 0 and f > frameNumber + 0.001 and (not target or f < target)
			then
				target = f
			end
		end

		if target then
			Raw.CurrentTime = target / Raw.FPS
			refs.State.Timeline:ApplyPoseAtTime(refs.State.currentRig, Raw.CurrentTime)
			refs.State.Timeline:UpdatePlayhead()
		end
	end

	local previousKey = button(frame, "PreviousWeight", "PREV KEY", 12, 363, 174, 27, function()
		jump(-1)
	end, "Previous blend key")
	local nextKey = button(frame, "NextWeight", "NEXT KEY", 204, 363, 174, 27, function()
		jump(1)
	end, "Next blend key")
	local dragging = false
	local dragValue, dragLayer, dragOriginal, dragKey, dragFrame

	local function paintWeight(value)
		weightBox.Text = string.format("%.0f", value * 100)
		knob.Position = UDim2.fromScale(value, 0.5)
		fill.Size = UDim2.fromScale(value, 1)
		fill.Position = UDim2.fromScale(value * 0.5, 0.5)
	end

	local function canAdjustWeight()
		local layer = Layers.active(Raw)
		return layer.id ~= "base"
			and not layer.locked
			and not Raw.Playing
			and not require("BlenderEdit").blocked()
	end

	local function paintAvailability()
		local enabled = canAdjustWeight()
		slider.Active = enabled
		slider:SetAttribute("WeightEditable", enabled)
		weightBox.TextEditable = enabled
		keyButton.Active = enabled
		for _, object in { rail, fill, knob } do
			local token = object == rail and "Strk" or object == fill and "KeySel" or "Txt"
			object:SetAttribute("ThemeBg", enabled and token or nil)
			object.BackgroundColor3 = enabled
					and (Theme.resolveInstanceValue(object, "ThemeBg") or Color3.fromRGB(
						235,
						228,
						242
					))
				or Color3.fromRGB(
					object == knob and 105 or 65,
					object == knob and 105 or 65,
					object == knob and 105 or 65
				)
		end

		weightBox.TextTransparency = enabled and 0 or 0.55
		keyText.TextTransparency = enabled and 0.1 or 0.65
	end

	local function refreshWeight()
		if view.closed or dragging then
			return
		end

		paintAvailability()
		local layer = Layers.active(Raw)
		paintWeight(Layers.weight(layer, Raw.CurrentTime, Raw.FPS))
		local keyed = layer.weightKeys
			and layer.weightKeys[math.round(Raw.CurrentTime * Raw.FPS)] ~= nil
		keyText.Text = keyed and "\u{25c6}" or "\u{25c7}"
		local count = 0
		for _ in layer.weightKeys or {} do
			count += 1
		end

		local showKeys = count > 0 and layer.id ~= "base"
		previousKey.Visible = showKeys
		nextKey.Visible = showKeys
		local height = showKeys and 436 or 399
		frame.MinimumSize.MinSize = Vector2.new(390, height)
		if not view.docked then
			frame.Size = UDim2.fromOffset(390, height)
		end
	end

	local picker
	local masterButton, masterText = button(frame, "Master", "", 12, 38, 366, 27, function()
		if picker then
			picker:Destroy()
			picker = nil
			return
		end

		local rigs = refs.State.getAllRigs()
		picker = Tool.make("ScrollingFrame", frame, "MasterChoices", {
			Position = UDim2.fromOffset(12, 69),
			Size = UDim2.fromOffset(366, math.min(#rigs * 30 + 8, 188)),
			CanvasSize = UDim2.fromOffset(0, #rigs * 30 + 8),
			ScrollBarThickness = 3,
			BackgroundColor3 = Color3.fromRGB(24, 19, 34),
			BorderSizePixel = 0,
			ZIndex = 40,
		})
		picker:SetAttribute("ThemeBg", "Bg")
		Tool.make("UICorner", picker, "Corner", { CornerRadius = UDim.new(0, 4) })
		for i, rig in rigs do
			local b, t = button(picker, "Master" .. i, rig.Name, 4, 4 + (i - 1) * 30, 354, 26, function()
				picker:Destroy()
				picker = nil
				Layers.setMaster(rig)
			end
)
			b.ZIndex = 41
			t.ZIndex = 42
			t.TextTruncate = Enum.TextTruncate.AtEnd
			tip(b, rig:GetFullName())
		end

		Theme.applyTree(picker)
	end, "choose master")

	for _, object in frame:GetChildren() do
		if
			object:IsA("GuiObject")
			and object ~= masterButton
			and object.Position.Y.Offset >= 38
		then
			object.Position += UDim2.fromOffset(0, 34)
		end
	end

	local lastSelected = require("SelectedRig").resolve(refs.State)
	if lastSelected then
		Layers.setMaster(lastSelected)
	end

	local function refresh()
		if view.closed then
			return
		end

		for _, object in list:GetChildren() do
			object:Destroy()
		end

		local data = Layers.ensure(Raw)
		local active = Layers.active(Raw)
		local stack = Layers.stack(Raw)
		masterText.Text = (Layers.master() and Layers.master().Name or "master") .. "  \u{25be}"
		activeText.Text = "KEYING: " .. active.name
		addText.Text = (active.mode == "Additive" and "\u{25cf} " or "") .. "ADDITIVE"
		overrideText.Text = (active.mode == "Override" and "\u{25cf} " or "") .. "OVERRIDE"
		additive.Active = active.id ~= "base"
		override.Active = active.id ~= "base"
		weightBox.TextEditable = active.id ~= "base"
		keyButton.Active = active.id ~= "base"
		for index = #stack, 1, -1 do
			local layer = stack[index]
			local y = (#stack - index) * 34
			local row = Tool.make("Frame", list, "Layer_" .. layer.id, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, -2, 0, y + 15),
				Size = UDim2.new(1, -4, 0, 30),
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.fromRGB(51, 0, 77),
				BackgroundTransparency = layer.id == data.active and 0.05 or 0.65,
				ZIndex = 13,
			})
			row:SetAttribute("ThemeBg", layer.id == data.active and "TopBtn" or "Bg")
			row:SetAttribute("ThemeBgTransparency", layer.id == data.active and 0.05 or 0.65)
			Tool.make("UICorner", row, "Corner", { CornerRadius = UDim.new(0, 3) })
			local marker = Tool.make("Frame", row, "ActiveMarker", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(5, 5),
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.fromRGB(235, 228, 242),
				Visible = layer.id == data.active,
				ZIndex = 15,
			})
			marker:SetAttribute("ThemeBg", "Txt")
			Tool.make("UICorner", marker, "Corner", { CornerRadius = UDim.new(1, 0) })
			local selectButton = Tool.make("TextButton", row, "Select", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 10, 0.5, 0),
				Size = UDim2.new(1, -28, 1, 0),
				Text = layer.name,
				TextTruncate = Enum.TextTruncate.AtEnd,
				FontFace = Chrome.FONT,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(235, 228, 242),
				ZIndex = 14,
			})
			selectButton:SetAttribute("ThemeTxt", "Txt")
			local lastClick = 0
			selectButton.Activated:Connect(function()
				local now = os.clock()
				local double = now - lastClick < 0.32 and layer.id ~= "base"
				lastClick = now
				if double then
					local rename = field(row, "Rename", layer.name, 28, 2, 218, 26)
					rename.ZIndex = 20
					rename:CaptureFocus()
					rename.FocusLost:Once(function()
						local name = rename.Text
						rename.Parent:Destroy()
						Layers.change(layer.id, "name", name)
					end)
				else
					task.defer(function()
						if not view.closed and not Layers.select(layer.id) then
							require("Notification").show("ANIMATION LAYERS", "Finish the active edit or unlock the layer before switching.")
						end
					end)
				end
			end)
			tip(selectButton, "Select this layer to edit its keys. Double-click to rename.")
			if layer.id ~= "base" then
				for n, control in
					{
						{ "M", "muted", "mute layer" },
						{ "S", "solo", "solo layer" },
						{ "L", "locked", "lock layer" },
					}
				do
					local b, t = button(row, control[2], control[1], 270 + (n - 1) * 29, 3, 25, 24, function()
						Layers.toggle(layer.id, control[2])
					end, control[3])
					b.Position = UDim2.new(1, -(3 - n) * 29 - 17, 0.5, 0)
					t.TextTransparency = 0
					t:SetAttribute("ThemeTxt", "Txt")
					b:SetAttribute("Primary", true)
					b:SetAttribute("Ready", true)
					b:SetAttribute("ThemeBg", "Bg")
					b:SetAttribute("ThemeBgTransparency", 0)
					b.BackgroundTransparency = 0
					local selected = layer[control[2]] == true
					local edge = Tool.make("UIStroke", b, "ToggleOutline", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Thickness = selected and 2 or 1,
						Transparency = selected and 0 or 0.35,
						Color = Color3.fromRGB(180, 160, 210),
					})
					edge:SetAttribute("ThemeStrk", selected and "KeySel" or "Strk")
					b:SetAttribute("Selected", selected)
				end
			else
				local base = label(row, "Base", "BASE", 0, 3, 60, 24)
				base.Position = UDim2.new(1, -40, 0.5, 0)
				base.TextXAlignment = Enum.TextXAlignment.Right
			end
		end

		list.CanvasSize = UDim2.fromOffset(0, #stack * 34)
		refreshWeight()
		Theme.applyTree(frame)
		paintAvailability()
	end

	require("NumericInput").connect(weightBox, { step = 1, min = 0, max = 100, integer = true }, function()
		if not canAdjustWeight() then
			refreshWeight()
			return
		end

		local value = tonumber((weightBox.Text:gsub("%%", "")))
		if
			value
			and math.abs(
					math.clamp(value / 100, 0, 1)
						- Layers.weight(Layers.active(Raw), Raw.CurrentTime, Raw.FPS)
				)
				> 0.00001
		then
			Layers.change(Layers.active(Raw).id, "weight", value / 100)
		else
			refreshWeight()
		end
	end
)

	local function updateDrag(x)
		dragValue =
			math.clamp((x - slider.AbsolutePosition.X) / math.max(slider.AbsoluteSize.X, 1), 0, 1)
		paintWeight(dragValue)
		local layer = Layers.active(Raw)
		if layer.id ~= dragLayer then
			return
		end

		if dragKey then
			layer.weightKeys[dragFrame] = dragValue
		else
			layer.weight = dragValue
		end

		refs.State.Timeline:ApplyPoseAtTime(refs.State.currentRig, Raw.CurrentTime)
	end

	cancelDrag = function()
		if not dragging then
			return
		end

		dragging = false
		for _, layer in Layers.ensure(Raw).layers do
			if layer.id == dragLayer then
				if dragKey then
					layer.weightKeys[dragFrame] = dragOriginal
				else
					layer.weight = dragOriginal
				end
			end
		end

		if refs.State.currentRig then
			refs.State.Timeline:ApplyPoseAtTime(refs.State.currentRig, Raw.CurrentTime)
		end
	end

	slider.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and canAdjustWeight() then
			dragging = true
			local layer = Layers.active(Raw)
			dragLayer = layer.id
			dragFrame = math.round(Raw.CurrentTime * Raw.FPS)
			dragKey = layer.weightKeys and layer.weightKeys[dragFrame] ~= nil
			dragOriginal = dragKey and layer.weightKeys[dragFrame] or layer.weight
			updateDrag(input.Position.X)
		end
	end)
	table.insert(
		view.connections,
		Input.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				updateDrag(input.Position.X)
			end
		end)
	)
	table.insert(
		view.connections,
		Input.InputEnded:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
				cancelDrag()
				Layers.change(dragLayer, "weight", dragValue)
			end
		end)
	)
	local elapsed = 0
	table.insert(
		view.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed > 0.1 then
				elapsed = 0
				local selected = require("SelectedRig").resolve(refs.State)
				if selected ~= lastSelected then
					lastSelected = selected
					if not dragging then
						Layers.setMaster(selected)
					end
				end

				refreshWeight()
			end
		end)
	)
	unsubscribe = Layers.subscribe(refresh)
	refresh()
	for _, object in frame:GetDescendants() do
		if object:IsA("GuiObject") then
			center(object)
		end
	end

	return frame
end

function Window.toggle()
	if window then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(value)
	Window.close(true)
	refs = value
	Layers.init(value)
	local host = value.ScreenGui.Parent

	local function shutdown()
		Window.close(true)

		for _, gui in host and host:GetChildren() or {} do
			if
				gui:IsA("ScreenGui")
				and gui.Name == "AnimationLayers"
				and gui:GetAttribute("EclipseOwnedUI") == true
			then
				gui:Destroy()
			end
		end
	end

	if value.AnimatorFrame then
		value.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not value.AnimatorFrame.Visible then
				Window.close()
			end
		end)
	end

	value.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not value.ScreenGui.Enabled then
			Window.close()
		end
	end)

	value.ScreenGui.Destroying:Connect(shutdown)
	if value.Plugin then
		value.Plugin.Unloading:Connect(shutdown)
	end
end

return Window
