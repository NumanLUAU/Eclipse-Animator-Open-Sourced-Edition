--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Frames = {}
Frames.__index = Frames

local MAX_FRAMES = 600
local MAX_VALUES = 262144

function Frames.new(clock, fps)
	return setmetatable(
		{ clock = clock, fps = fps, epoch = -1, entries = {}, order = {}, weight = 0 },
		Frames
	)
end

function Frames:sync()
	if self.epoch == self.clock.frameEpoch then
		return
	end

	self.epoch = self.clock.frameEpoch
	table.clear(self.entries)
	table.clear(self.order)
	self.weight = 0
end

function Frames:key(time)
	local frame = math.floor(time * self.fps + 0.5)
	if math.abs(frame / self.fps - time) > 1e-7 then
		return nil
	end

	return frame
end

function Frames:capture()
	if not self.clock.frameProperties then
		return
	end

	self:sync()
	local key = self:key(self.clock.now)
	if key == nil or self.entries[key] then
		return
	end

	local frame = self.clock:captureFrame()
	if frame.weight > MAX_VALUES then
		return
	end

	self.entries[key] = frame
	table.insert(self.order, key)
	self.weight += frame.weight
	while #self.order > MAX_FRAMES or self.weight > MAX_VALUES do
		local oldest = table.remove(self.order, 1)
		self.weight -= self.entries[oldest].weight
		self.entries[oldest] = nil
	end
end

function Frames:get(time)
	self:sync()
	local key = self:key(time)
	return key ~= nil and self.entries[key] or nil
end

return Frames
