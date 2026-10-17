--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local TweenService = game:GetService("TweenService")
const RunService = game:GetService("RunService")
const Input = require("UserInputService")
local hover = {}
local hoverWait = 0.1
const CHECK_INTERVAL = 0.1

local function shownOn(object)
	local current = object
	while current do
		if current:IsA("LayerCollector") then
			return current.Enabled, current
		end

		if current:IsA("GuiObject") and not current.Visible then
			return false
		end

		current = current.Parent
	end

	return false
end

function hover.initialize(ui: Frame, mouse: Mouse)
	local label = ui.Information
	local background = ui:FindFirstChild("TooltipBackground")
	if not background then
		background = Instance.new("Frame")
		background.Name = "TooltipBackground"
		background.Size = UDim2.fromScale(1, 1)
		background.BorderSizePixel = 0
		background.BackgroundColor3 = ui.BackgroundColor3
		background.BackgroundTransparency = ui.BackgroundTransparency
		background.ZIndex = ui.ZIndex
		background.Active = false
		background.Interactable = false
		for _, name in
			{ "ThemeBg", "ThemeShade", "EOrig_BackgroundColor3", "EOrig_BackgroundTransparency" }
		do
			background:SetAttribute(name, ui:GetAttribute(name))
		end

		for _, child in ui:GetChildren() do
			if child:IsA("UIGradient") then
				child.Parent = background
			elseif child:IsA("UICorner") and not background:FindFirstChildOfClass("UICorner") then
				child:Clone().Parent = background
			end
		end

		ui:SetAttribute("ThemeBg", nil)
		ui.BackgroundTransparency = 1
		background.Parent = ui
	end

	label.ZIndex = math.max(label.ZIndex, background.ZIndex + 1)
	require("Theme").applyInstance(background)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.Name = "TooltipSizeLimit"
	sizeLimit.Parent = label
	local self = setmetatable({
		ui = ui,
		label = label,
		mouse = mouse,
		connections = {},
		bindings = {},
		generation = 0,
		hoverEpoch = 0,
		open = false,
		destroyed = false,
		sizeLimit = sizeLimit,
		labelDefaults = {
			Size = label.Size,
			AutomaticSize = label.AutomaticSize,
			TextWrapped = label.TextWrapped,
			RichText = label.RichText,
		},
		tweens = {
			popIn = TweenService:Create(
				ui,
				TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
				{ GroupTransparency = 0.1 }
			),
			popOut = TweenService:Create(
				ui,
				TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ GroupTransparency = 1 }
			),
		},
	}, { __index = hover })
	self:_track(ui.Destroying:Connect(function()
		self:Destroy(true)
	end))
	self:_track(label.Destroying:Connect(function()
		self:Destroy()
	end))
	self.baseZIndex = ui.ZIndex
	self.layers = {}
	for _, object in { ui, table.unpack(ui:GetDescendants()) } do
		if object:IsA("GuiObject") then
			table.insert(
				self.layers,
				{ object = object, offset = math.max(0, object.ZIndex - ui.ZIndex) }
			)
		end
	end

	ui.Visible = false
	self:_track(ui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.open and not self.destroyed then
			self:_cancelPosition()
			ui.Position = self:_position(Vector2.new(mouse.x, mouse.y))
		end
	end))
	self:_track(mouse.Move:Connect(function()
		if
			not self.dragOwner
			and self.open
			and (not self.bindings[self.causedElement] or not self:_hovering(self.causedElement))
		then
			self:disappear()
		end
	end))
	self:_track(Input.InputBegan:Connect(function(input)
		if
			self.open
			and not self.dragOwner
			and input
			and input.UserInputType == Enum.UserInputType.Keyboard
		then
			self:disappear()
		end
	end))
	return self
end

function hover:_hovering(owner)
	if typeof(owner) ~= "Instance" or not owner:IsA("GuiObject") then
		return true
	end

	const visible, surface = shownOn(owner)
	if not visible then
		return false
	end

	if not surface:IsA("PluginGui") then
		return not Input.pointerInWidget()
	end

	const point, size = surface:GetRelativeMousePosition(), surface.AbsoluteSize
	if point.X < 0 or point.Y < 0 or point.X >= size.X or point.Y >= size.Y then
		return false
	end

	const start, extent = owner.AbsolutePosition, owner.AbsoluteSize
	return point.X >= start.X - 1
		and point.Y >= start.Y - 1
		and point.X <= start.X + extent.X + 1
		and point.Y <= start.Y + extent.Y + 1
end

function hover:_unwatch()
	if self.watcher then
		self.watcher:Disconnect()
		self.watcher = nil
	end
end

function hover:_watch()
	if self.watcher then
		return
	end

	local elapsed = 0
	self.watcher = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_INTERVAL then
			return
		end

		elapsed = 0
		if self.destroyed or not self.open then
			self:_unwatch()
		elseif not self.dragOwner and not self:_hovering(self.causedElement) then
			self:disappear()
		end
	end)
end

function hover:_track(connection)
	table.insert(self.connections, connection)
	if #self.connections > (self.pruneAt or 256) then
		local kept = {}
		for _, existing in self.connections do
			if existing.Connected then
				table.insert(kept, existing)
			end
		end

		self.connections = kept
		self.pruneAt = math.max(256, #kept * 2)
	end

	return connection
end

function hover:latchToInstance(otherFrame: Frame, info: any, options)
	local previous = self.bindings[otherFrame]
	if previous then
		previous.cleanup()
	end

	local binding = { serial = 0, active = true, connections = {} }
	self.bindings[otherFrame] = binding

	function binding.cancel()
		binding.serial += 1
		binding.pending = false
	end

	local function startHoverTimer()
		if self.destroyed or not binding.active or self.dragOwner then
			return
		end

		if self.open then
			if self.causedElement == otherFrame then
				return
			end

			self:disappear()
		end

		if binding.pending then
			return
		end

		binding.pending = true
		binding.serial += 1
		local serial, epoch = binding.serial, self.hoverEpoch
		task.delay(hoverWait, function()
			if serial ~= binding.serial then
				return
			end

			binding.pending = false
			if self.destroyed or not binding.active or epoch ~= self.hoverEpoch then
				return
			end

			if self.open or self.dragOwner or not otherFrame.Parent or not self:_hovering(otherFrame) then
				return
			end

			local output = if typeof(info) == "function" then info() else info
			if output then
				self:popup(output, otherFrame, options)
			end
		end)
	end

	function binding.cleanup()
		if not binding.active then
			return
		end

		binding.active = false
		binding.cancel()
		if not self.destroyed then
			self:disappear(otherFrame)
		end

		for _, connection in binding.connections do
			connection:Disconnect()
		end

		if self.bindings[otherFrame] == binding then
			self.bindings[otherFrame] = nil
		end
	end

	local function connect(signal, callback)
		table.insert(binding.connections, self:_track(signal:Connect(callback)))
	end

	connect(otherFrame.MouseEnter, startHoverTimer)
	connect(otherFrame.MouseMoved, startHoverTimer)
	connect(otherFrame.MouseLeave, function()
		self:disappear(otherFrame)
	end)
	connect(otherFrame.Destroying, binding.cleanup)
	return binding.cleanup
end

function hover:updateText(info: string)
	if self.destroyed then
		return
	end

	self.label.Text = tostring(info)
end

function hover:_format(options, literal)
	local label, defaults = self.label, self.labelDefaults
	label.RichText = if literal then false else defaults.RichText
	label.TextWrapped = if options and options.maxWidth then true else defaults.TextWrapped

	self.sizeLimit.MaxSize = Vector2.new(
		if options and options.maxWidth then math.max(1, options.maxWidth) else math.huge,
		math.huge
	)
	label.AutomaticSize = if options and options.maxWidth
		then Enum.AutomaticSize.Y
		else defaults.AutomaticSize
	label.Size = if options and options.maxWidth then UDim2.fromOffset(math.max(1, options.maxWidth), 0) else defaults.Size
end

function hover:_position(point)
	local parent, scale = self.ui.Parent, 1
	local current = parent
	while current do
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end

		current = current.Parent
	end

	local origin = if parent and parent:IsA("GuiBase2d")
		then parent.AbsolutePosition
		else Vector2.zero
	local surface = self.ui:FindFirstAncestorWhichIsA("LayerCollector")
	if surface then
		local start, size = surface.AbsolutePosition, surface.AbsoluteSize
		point = Vector2.new(
			math.clamp(point.X, start.X, math.max(start.X, start.X + size.X - self.ui.AbsoluteSize.X - 10 * scale)),
			math.clamp(point.Y, start.Y, math.max(start.Y, start.Y + size.Y - self.ui.AbsoluteSize.Y - 10 * scale))
		)
	end
	return UDim2.fromOffset(
		(point.X - origin.X) / math.max(scale, 0.001) + 10,
		(point.Y - origin.Y) / math.max(scale, 0.001) + 10
	)
end

function hover:_cancelPosition()
	if self.positionTween then
		self.positionTween:Cancel()
		self.positionTween:Destroy()
		self.positionTween = nil
	end
end

function hover:_raiseAbove(owner)
	local level = self.baseZIndex
	local cursor = owner
	while typeof(cursor) == "Instance" and cursor ~= self.ui.Parent do
		if cursor:IsA("GuiObject") then
			level = math.max(level, cursor.ZIndex + 32)
		end

		cursor = cursor.Parent
	end

	for _, layer in self.layers do
		if layer.object.Parent then
			layer.object.ZIndex = level + layer.offset
		end
	end
end

function hover:_show(info, owner, options, literal)
	if self.destroyed or not self.ui.Parent or self.label.Parent ~= self.ui then
		self:Destroy()
		return false
	end

	self.generation += 1
	self.hoverEpoch += 1
	self:_cancelPosition()
	self:_raiseAbove(owner)
	self:_format(options, literal)
	self:updateText(info)
	self.causedElement = owner
	local target = self:_position(Vector2.new(self.mouse.x, self.mouse.y))
	self.ui.Position = if literal then target else target + UDim2.fromOffset(0, 5)
	self.ui.Visible, self.open = true, true
	self:_watch()
	if not literal then
		self.positionTween = TweenService:Create(
			self.ui,
			TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Position = target }
		)
		self.positionTween:Play()
	end

	self.tweens.popOut:Cancel()
	self.tweens.popIn:Play()
	return true
end

function hover:popup(info, causedElement, options)
	if self.destroyed or self.dragOwner then
		return false
	end

	return self:_show(info, causedElement, options, false)
end

function hover:disappear(owner)
	if self.destroyed then
		return
	end

	if owner then
		local binding = self.bindings[owner]
		if binding then
			binding.cancel()
		end
	else
		self.hoverEpoch += 1
	end

	if self.dragOwner or (owner and self.causedElement ~= owner) or not self.open then
		return
	end

	self.generation += 1
	local generation = self.generation
	self.open, self.causedElement = false, nil
	self:_unwatch()
	self:_cancelPosition()
	self.positionTween = TweenService:Create(
		self.ui,
		TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Position = self.ui.Position + UDim2.fromOffset(0, 5) }
	)
	self.positionTween:Play()
	self.tweens.popIn:Cancel()
	self.tweens.popOut:Play()
	task.delay(0.1, function()
		if not self.destroyed and generation == self.generation and not self.open then
			self.ui.Visible = false
		end
	end)
end

function hover:beginDrag(info, owner)
	if self.destroyed or not owner or (self.dragOwner and self.dragOwner ~= owner) then
		return false
	end

	self.dragOwner = owner
	return self:_show(info, owner, nil, true)
end

function hover:moveDrag(point)
	if self.destroyed or not self.dragOwner then
		return
	end

	self.ui.Position = self:_position(point)
end

function hover:endDrag(owner)
	if self.destroyed or not self.dragOwner or (owner and owner ~= self.dragOwner) then
		return
	end

	self.dragOwner = nil
	self:disappear()
end

function hover:Destroy(external)
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.generation += 1
	self.hoverEpoch += 1
	for _, binding in table.clone(self.bindings) do
		binding.cleanup()
	end

	for _, connection in self.connections do
		connection:Disconnect()
	end

	table.clear(self.connections)
	self:_unwatch()
	self:_cancelPosition()
	for _, tween in self.tweens do
		tween:Destroy()
	end

	if not external then
		self.ui:Destroy()
	end
end

return hover
