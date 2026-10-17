--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local zoom = {}
zoom.__index = zoom

function zoom:GetZoom()
	return self.zoomScale
end

function zoom:Apply()
	self.element.Position = UDim2.new(0, 0, 0, 0)
	self.element.Size = UDim2.fromScale(self.zoomScale, 1)

	if self.fitFrame then
		self.fitFrame.Position = UDim2.new(0, 0, 0, 0)
		self.fitFrame.Size = UDim2.fromScale(1, 1)
	end

	self.changed:Fire(self.zoomScale)
end

function zoom:Change(direction)
	local minimum = self.minimum and self.minimum() or 1
	local factor = (1 + self.step) ^ require("Preferences").timelineScrollSpeed()
	local nextZoom = math.clamp(self.zoomScale * factor ^ direction, minimum, self.maxZoom)
	if nextZoom == self.zoomScale then
		return
	end

	self.zoomScale = nextZoom
	self:Apply()
end

function zoom:inZoom()
	self:Change(1)
end

function zoom:outZoom()
	self:Change(-1)
end

function zoom.new(element: Frame, fitFrame: Frame?, onWheel)
	local self = setmetatable({}, zoom)

	self.element = element
	self.fitFrame = fitFrame
	self.step = 0.1
	self.maxZoom = 10
	self.zoomScale = 1
	self.changed = Instance.new("BindableEvent")

	element.MouseWheelForward:Connect(function()
		if not onWheel or not onWheel(1) then
			self:inZoom()
		end
	end)

	element.MouseWheelBackward:Connect(function()
		if not onWheel or not onWheel(-1) then
			self:outZoom()
		end
	end)

	element.Destroying:Connect(function()
		self:Destroy()
	end)

	self:Apply()

	return self
end

function zoom:Destroy()
	if self.changed then
		self.changed:Destroy()
	end

	table.clear(self)
end

return zoom
