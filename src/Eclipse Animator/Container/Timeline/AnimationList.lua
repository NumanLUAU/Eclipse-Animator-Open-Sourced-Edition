--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Import = require("Import")
local Theme = require("Theme")
local AnimationList = {}

function AnimationList.deleteSaved(saved)
    if not saved or not saved.Parent then return false end
    local State = require("State")
    if State.currentRig and (State.currentProjectSave == saved or State.currentProjectSequence == saved or State.exportSequences[State.currentRig] == saved) then
        require("Notification").show("CLOSE THE FILE FIRST", "Close this animation before deleting its saved copy.")
        return false
    end
    local parent = saved.Parent
    local UI = require("UI")
    require("Confirm").open(UI.EclipseGUI, UI.RigItemTemplate, "DELETE SAVED FILE?",
        'Delete "' .. saved.Name .. '"? This removes this saved copy, not the rig.', "Delete", function()
            if saved.Parent ~= parent then return end
            if State.currentRig and (State.currentProjectSave == saved or State.currentProjectSequence == saved or State.exportSequences[State.currentRig] == saved) then
                require("Notification").show("CLOSE THE FILE FIRST", "The file was opened while this prompt was shown. Close it before deleting.")
                return
            end
            for rig, sequence in State.exportSequences do
                if sequence == saved then State.exportSequences[rig] = nil end
            end
            if State.currentProjectSave == saved then State.currentProjectSave = nil end
            if State.currentProjectSequence == saved then State.currentProjectSequence = nil end
            saved:Destroy()
        end)
    return true
end

function AnimationList.attachDelete(row, selected, offset)
    local button = Instance.new("ImageButton")
    button.Name = "DeleteSaved"
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.Position = UDim2.new(1, -(offset or 14), 0.5, 0)
    button.Size = UDim2.fromOffset(22, 22)
    button.BackgroundTransparency = 1
    button.ZIndex = row.ZIndex + 8
    button.Visible = false
    button.Parent = row
    require("LibraryIcons").dynamic(button, "trash")
    row.MouseEnter:Connect(function() button.Visible = true end)
    row.MouseLeave:Connect(function() button.Visible = false end)
    button.Activated:Connect(function()
        AnimationList.deleteSaved(selected())
    end)
    return button
end

local function importButton(template, kind, image)
	local button = Instance.new("TextButton")
	button.Name = "Import" .. kind
	button.Text = ""
	button.Size = UDim2.new(1, 0, 0, 24)
	button.BackgroundColor3 = template.BackgroundColor3
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.ZIndex = template.ZIndex
	button:SetAttribute("ThemeBg", "MenuSel")
	button:SetAttribute("ThemeShade", -0.15)
	button:SetAttribute("EclipseAnimationImport", true)
	local corner = template:FindFirstChildOfClass("UICorner"):Clone()
	corner.Parent = button
	local outline = template:FindFirstChildOfClass("UIStroke"):Clone()
	outline.Parent = button
	local icon = Instance.new("ImageLabel")
	icon.Name = "ImportIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 5, 0.5, 0)
	icon.Size = UDim2.fromOffset(18, 18)
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = button.ZIndex + 1
	icon:SetAttribute("ThemeImg", "MenuSel")
	icon:SetAttribute("ThemeShade", 0.35)
	icon.Parent = button
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Text = kind .. "…"
	label.Position = UDim2.fromOffset(29, 0)
	label.Size = UDim2.new(1, -35, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = template:FindFirstChild("Name").FontFace
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = button.ZIndex + 2
	label:SetAttribute("ThemeTxt", "Txt")
	label.Parent = button
	Theme.applyTree(button)
	return button
end

local previewed = setmetatable({}, { __mode = "k" })
local variantButtons = setmetatable({}, { __mode = "k" })

AnimationList.__index = AnimationList

function AnimationList.isProjectComponent(animation)
	return animation:GetAttribute("EclipseProjectComponent") == true
end

function AnimationList.isPreview(button, animation)
	return previewed[button] == animation
end

function AnimationList.setPreview(button, active, animation)
	if not button or not button.Parent then
		return
	end

	previewed[button] = active and animation or nil
	button:SetAttribute("EclipsePreviewing", active and true or nil)
	button:SetAttribute("ThemeBg", active and "MenuSel" or "TopBtn")
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:SetAttribute("ThemeStrk", active and "MenuSel" or "Strk")
		stroke:SetAttribute("ThemeShade", active and 0.35 or nil)
	end

	Theme.applyTree(button)
	for child, value in variantButtons[button] or {} do
		AnimationList.setPreview(child, active and value == animation, value)
	end
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

function AnimationList.new(template, container, onActivate, buttons, bounds)
	for _, child in container:GetChildren() do
		if
			child ~= template
			and (
				child:GetAttribute("EclipseAnimationRow") == true
				or child:GetAttribute("EclipseAnimationImport") == true
			)
		then
			child:Destroy()
		end
	end

	local self = setmetatable({
		template = template,
		templateLabel = template:FindFirstChild("Name"),
		lifetimeConnections = {},
		bounds = bounds or container,
		container = container,
		onActivate = onActivate,
		buttons = buttons,
		byAnimation = {},
		groupRows = {},
		rigConnections = {},
		saveConnections = {},
		generation = 0,
		pending = false,
	}, AnimationList)
	self.importButtons = {}
	for index, entry in
		{
			{ "Roblox", "rbxassetid://137836958686320" },
			{ "Avatar Shop", "rbxassetid://104660482215747" },
			{ "FBX", "rbxassetid://104487897747120" },
		}
	do
		local kind = entry[1]
		local button = importButton(template, kind, entry[2])
		button.Visible = false
		button.LayoutOrder = -10 + index
		button.Parent = container
		button.MouseButton1Click:Connect(function()
			Import.open(self.rig, kind, function()
				self:queueRefresh()
			end)
		end)
		table.insert(self.importButtons, button)
	end

	for _, object in { container, template, self.templateLabel } do
		table.insert(
			self.lifetimeConnections,
			object.Destroying:Connect(function()
				self:Destroy()
			end)
		)
	end

	return self
end

function AnimationList:isLive()
	if self.destroyed then
		return false
	end

	if
		not self.container.Parent
		or self.templateLabel.Parent ~= self.template
		or self.template:FindFirstChild("Name") ~= self.templateLabel
	then
		self:Destroy()
		return false
	end

	return true
end

function AnimationList:queueRefresh()
	if not self:isLive() or self.pending then
		return
	end

	self.pending = true
	local generation = self.generation
	task.defer(function()
		if self.destroyed or generation ~= self.generation then
			return
		end

		self.pending = false
		self:refresh()
	end)
end

function AnimationList:refresh()
	if not self:isLive() then
		return
	end

	local opened = self.pickerRow and self.pickerRow.base
	self:closeVariants()
	disconnectAll(self.saveConnections)
	local animations, seenNames = {}, {}
	local rig = self.rig
	for _, button in self.importButtons do
		button.Visible = rig ~= nil and not self.multi
	end

	local saves = rig and rig:FindFirstChild("AnimSaves")
	local sources = {}
	if saves then
		table.insert(sources, saves)
		if saves:IsA("ObjectValue") then
			table.insert(
				self.saveConnections,
				saves:GetPropertyChangedSignal("Value"):Connect(function()
					self:queueRefresh()
				end)
			)
			if saves.Value and saves.Value ~= saves then
				table.insert(sources, saves.Value)
			end
		end
	end

	for _, source in ipairs(sources) do
		table.insert(
			self.saveConnections,
			source.ChildAdded:Connect(function(child)
				if
					child:IsA("KeyframeSequence")
					and child:GetAttribute("EclipseAnimationModified") == nil
				then
					child:SetAttribute(
						"EclipseAnimationModified",
						DateTime.now().UnixTimestampMillis
					)
				end

				self:queueRefresh()
			end)
		)
		table.insert(
			self.saveConnections,
			source.ChildRemoved:Connect(function()
				self:queueRefresh()
			end)
		)
		for _, animation in ipairs(source:GetChildren()) do
			if animation:IsA("KeyframeSequence") then
				table.insert(
					self.saveConnections,
					animation
						:GetAttributeChangedSignal("EclipseProjectComponent")
						:Connect(function()
							self:queueRefresh()
						end)
				)
				if AnimationList.isProjectComponent(animation) then
					continue
				end

				table.insert(
					self.saveConnections,
					animation
						:GetAttributeChangedSignal("EclipseAnimationModified")
						:Connect(function()
							self:queueRefresh()
						end)
				)
				table.insert(
					self.saveConnections,
					animation:GetPropertyChangedSignal("Name"):Connect(function()
						self:queueRefresh()
					end)
				)
				if not seenNames[animation] then
					seenNames[animation] = true
					table.insert(animations, animation)
				end
			end
		end
	end

	Import.sortSequences(animations)
	local groups, groupOrder, bases, suffixes = {}, {}, {}, {}
	for position, animation in ipairs(animations) do
		local base, number = string.match(animation.Name, "^(.-)%s+(%d+)$")
		if not base or base == "" then
			base, number = animation.Name, nil
		end

		bases[animation], suffixes[animation] = base, { tonumber(number) or 0, position }
		local group = groups[base]
		if not group then
			group = {}
			groups[base] = group
			table.insert(groupOrder, group)
		end

		table.insert(group, animation)
	end

	local present = {}
	table.clear(self.buttons)
	table.clear(self.byAnimation)
	for order, group in ipairs(groupOrder) do
		table.sort(group, function(a, b)
			local x, y = suffixes[a], suffixes[b]
			return x[1] == y[1] and x[2] < y[2] or x[1] < y[1]
		end)
		local base = bases[group[1]]
		present[base] = true
		local row = self.groupRows[base]
		if not row then
			local button = self.template:Clone()
			button:SetAttribute("EclipseAnimationRow", true)
			button.Visible = true
			button.Parent = self.container
			row = { button = button }
			self.groupRows[base] = row
            row.delete = AnimationList.attachDelete(button, function() return row.selected end)
			button.MouseButton1Click:Connect(function()
				if self.rig ~= rig then
					return
				end

				self:activateRow(row)
			end)
		end

		row.animations = group
		row.base = base
		row.rig = rig
		row.selected = table.find(group, row.selected) and row.selected or group[1]
		row.button.Name = base
		row.button.LayoutOrder = order
		if not row.toggle then
			local toggle = Instance.new("TextButton")
			toggle.Name = "VariantsToggle"
			toggle.Text = "▾"
			toggle.BackgroundTransparency = 1
			toggle.AutoButtonColor = true
			toggle.AnchorPoint = Vector2.new(1, 0)
			toggle.Position = UDim2.new(1, -26, 0, 0)
			toggle.Size = UDim2.new(0, 24, 1, 0)
			toggle.ZIndex = row.button.ZIndex + 5
			toggle.FontFace = self.template:FindFirstChild("Name").FontFace
			toggle.TextSize = 13
			toggle:SetAttribute("ThemeTxt", "Txt")
			toggle.Parent = row.button
			row.toggle = toggle
			toggle.MouseButton1Click:Connect(function()
				if self.rig == row.rig then
					self:openVariants(row)
				end
			end)
		end

		row.toggle.Visible = #group > 1
		local label = row.button:FindFirstChild("Name")
		if label then
			label.Size = UDim2.new(1, #group > 1 and -56 or -30, 1, 0)
		end

		self:labelVariant(row)
		for _, animation in group do
			self.byAnimation[animation] = row.button
		end

		table.insert(self.buttons, row.button)
	end

	for base, row in self.groupRows do
		if not present[base] then
			row.button:Destroy()
			self.groupRows[base] = nil
		end
	end

	if opened and self.groupRows[opened] then
		self:openVariants(self.groupRows[opened])
	end
end

function AnimationList:labelVariant(row)
	local index = table.find(row.animations, row.selected) or 1
	local label = row.button:FindFirstChild("Name")
	if label and label:IsA("TextLabel") then
		label.Text = #row.animations > 1 and (row.base .. " | " .. index .. "/" .. #row.animations)
			or row.selected.Name
	end
end

function AnimationList:activateRow(row)
	if not self:isLive() then
		return false
	end

	if self.rig ~= row.rig or not row.selected or not row.selected.Parent then
		return false
	end

	if #row.animations > 1 and not AnimationList.isPreview(row.button, row.selected) then
		if self.pickerRow ~= row then
			self:openVariants(row)
		end
	end

	return self:activateVariant(row, table.find(row.animations, row.selected) or 1)
end

function AnimationList:activateVariant(row, index)
	if not self:isLive() then
		return false
	end

	local animation = row.animations[index]
	if self.rig ~= row.rig or not animation or not animation.Parent then
		return false
	end

	local selected = AnimationList.isPreview(row.button, animation)
	row.selected = animation
	self:labelVariant(row)
	self.onActivate(row.rig, animation, row.button, selected and "open" or "preview")
	return true
end

function AnimationList.variantBounds(
	position,
	size,
	homePosition,
	homeSize,
	screenPosition,
	screenSize,
	count
)
	local left = math.max(homePosition.X, screenPosition.X)
	local top = math.max(homePosition.Y, screenPosition.Y)
	local right =
		math.max(left + 1, math.min(homePosition.X + homeSize.X, screenPosition.X + screenSize.X))
	local bottom =
		math.max(top + 1, math.min(homePosition.Y + homeSize.Y, screenPosition.Y + screenSize.Y))
	local width = math.min(math.max(1, size.X), right - left)
	local below = math.max(0, bottom - (position.Y + size.Y))
	local above = math.max(0, position.Y - top)
	local desired = math.min(196, count * 26)
	local down = below >= desired or below >= above
	local height = math.max(1, math.min(desired, down and below or above, bottom - top))
	local y = down and position.Y + size.Y or position.Y - height
	return Vector2.new(
		math.clamp(position.X, left, right - width),
		math.clamp(y, top, bottom - height)
	) - screenPosition,
		Vector2.new(width, height)
end

function AnimationList:closeVariants()
	if self.pickerRow then
		variantButtons[self.pickerRow.button] = nil
	end

	for _, connection in self.pickerConnections or {} do
		connection:Disconnect()
	end

	self.pickerConnections = nil
	self.pickerRow = nil
	if self.picker then
		self.picker:Destroy()
		self.picker = nil
	end
end

function AnimationList:openVariants(row)
	if not self:isLive() then
		return false
	end

	if self.picker and self.pickerRow == row then
		self:closeVariants()
		return
	end

	self:closeVariants()
	local screen = self.container:FindFirstAncestorOfClass("ScreenGui")
	if not screen then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "EclipseAnimationVariants"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = screen.IgnoreGuiInset
	gui.DisplayOrder = screen.DisplayOrder + 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = screen.Parent
	self.picker = gui
	self.pickerRow = row
	gui:SetAttribute("EclipseOwnedUI", true)
	variantButtons[row.button] = {}
	self.pickerConnections = {}

	local function watch(signal, callback)
		table.insert(self.pickerConnections, signal:Connect(callback))
	end

	watch(screen:GetPropertyChangedSignal("Enabled"), function()
		if not screen.Enabled then
			self:closeVariants()
		end
	end)
	watch(self.container.Destroying, function()
		self:closeVariants()
	end)
	local ancestor = self.container
	while ancestor and ancestor ~= screen do
		if ancestor:IsA("GuiObject") then
			local object = ancestor
			watch(object:GetPropertyChangedSignal("Visible"), function()
				if not object.Visible then
					self:closeVariants()
				end
			end)
		end

		ancestor = ancestor.Parent
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "Choices"
	list.BackgroundColor3 = self.template.BackgroundColor3
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, #row.animations * 26)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ClipsDescendants = true
	list.Parent = gui
	local bounds = self.bounds

	local function layoutPicker()
		if self.picker ~= gui then
			return
		end

		local position, size = AnimationList.variantBounds(
			row.button.AbsolutePosition,
			row.button.AbsoluteSize,
			bounds.AbsolutePosition,
			bounds.AbsoluteSize,
			gui.AbsolutePosition,
			gui.AbsoluteSize,
			#row.animations
		)
		list.Size = UDim2.fromOffset(size.X, size.Y)
		list.Position = UDim2.fromOffset(position.X, position.Y)
	end

	layoutPicker()
	for _, object in { row.button, bounds, gui } do
		watch(object:GetPropertyChangedSignal("AbsolutePosition"), layoutPicker)
		watch(object:GetPropertyChangedSignal("AbsoluteSize"), layoutPicker)
	end

	list:SetAttribute("ThemeBg", "TopBtn")
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list
	for index, animation in row.animations do
		local button = self.template:Clone()
		button.Name = "Variant" .. index
		button.Visible = true
		button.Size = UDim2.new(1, -4, 0, 24)
		button.LayoutOrder = index
		button.Parent = list
		local label = button:FindFirstChild("Name")
		if label then
			label.Text = animation.Name
            label.Size = UDim2.new(1, -30, label.Size.Y.Scale, label.Size.Y.Offset)
		end

		AnimationList.setPreview(button, previewed[row.button] == animation, animation)
		variantButtons[row.button][button] = animation
        AnimationList.attachDelete(button, function() return animation end)
		button.MouseButton1Click:Connect(function()
			self:activateVariant(row, index)
		end)
	end

	Theme.applyTree(list)
	watch(game:GetService("UserInputService").InputBegan, function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			self:closeVariants()
		end
	end)
	return list
end

function AnimationList:clearSections()
	for _, section in self.sections or {} do
		section.list:Destroy()
		section.frame:Destroy()
	end

	self.sections = nil
end

function AnimationList:setRigs(rigs)
	if not self:isLive() then
		return
	end

	if #rigs <= 1 then
		self:clearSections()
		self:setRig(rigs[1])
		return
	end

	local same = self.sections and #self.sections == #rigs
	if same then
		for i, rig in rigs do
			if self.sections[i].rig ~= rig then
				same = false
				break
			end
		end
	end

	if same then
		return
	end

	self:clearSections()
	self:setRig(nil)
	self.sections = {}
	for order, rig in rigs do
		local frame = Instance.new("Frame")
		frame.Name = "RigAnimations"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.LayoutOrder = order
		frame.Parent = self.container
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 3)
		layout.Parent = frame
		local header = Instance.new("TextButton")
		header.Name = "RigHeader"
		header.Text = "▾ " .. rig.Name
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.FontFace = self.template:FindFirstChild("Name").FontFace
		header.TextSize = 13
		header.Size = UDim2.new(1, 0, 0, 28)
		header.LayoutOrder = -20
		header.Parent = frame
		header:SetAttribute("ThemeBg", "MenuSel")
		header:SetAttribute("ThemeTxt", "Txt")
		local content = Instance.new("Frame")
		content.Name = "Animations"
		content.BackgroundTransparency = 1
		content.Size = UDim2.new(1, 0, 0, 0)
		content.AutomaticSize = Enum.AutomaticSize.Y
		content.Parent = frame
		local rows = layout:Clone()
		rows.Parent = content
		local list = AnimationList.new(self.template, content, self.onActivate, {}, self.bounds)
		list.multi = true
		list:setRig(rig)
		local section = { rig = rig, list = list, frame = frame }
		table.insert(self.sections, section)
		header.MouseButton1Click:Connect(function()
			content.Visible = not content.Visible
			header.Text = (content.Visible and "▾ " or "▸ ") .. rig.Name
		end)
		local hint = Instance.new("TextLabel")
		hint.Name = "PreviewHint"
		hint.Text = "Click to preview / click selected to open"
		hint.FontFace = header.FontFace
		hint.TextSize = 10
		hint.BackgroundTransparency = 1
		hint.Size = UDim2.new(1, 0, 0, 18)
		hint.LayoutOrder = -19
		hint.Parent = content
		hint:SetAttribute("ThemeTxt", "Txt")
		Theme.applyTree(frame)
	end
end

function AnimationList:setRig(rig)
	if not self:isLive() then
		return false
	end

	if self.rig == rig then
		return
	end

	self.generation += 1
	self.pending = false
	disconnectAll(self.rigConnections)
	disconnectAll(self.saveConnections)
	for _, row in self.groupRows do
		row.button:Destroy()
	end

	table.clear(self.groupRows)
	self.rig = rig
	if rig then
		table.insert(
			self.rigConnections,
			rig.ChildAdded:Connect(function(child)
				if child.Name == "AnimSaves" then
					self:queueRefresh()
				end
			end)
		)
		table.insert(
			self.rigConnections,
			rig.ChildRemoved:Connect(function(child)
				if child.Name == "AnimSaves" then
					self:queueRefresh()
				end
			end)
		)
		table.insert(
			self.rigConnections,
			rig.Destroying:Connect(function()
				self:setRig(nil)
			end)
		)
	end

	self:refresh()
end

function AnimationList:Destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.generation += 1
	self.pending = false
	disconnectAll(self.lifetimeConnections)
	disconnectAll(self.rigConnections)
	disconnectAll(self.saveConnections)
	self:closeVariants()
	self:clearSections()
	for _, button in self.importButtons do
		button:Destroy()
	end

	table.clear(self.importButtons)
	for _, row in self.groupRows do
		row.button:Destroy()
	end

	table.clear(self.groupRows)
	table.clear(self.byAnimation)
	table.clear(self.buttons)
	self.rig = nil
end

return AnimationList
