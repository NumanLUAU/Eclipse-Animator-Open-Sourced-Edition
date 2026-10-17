--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("RawState")
local TimelineState = State.Timeline
local TimelineConfig = State.Config
local PlayheadDrag = State.PlayheadDrag
local KeyframeDrag = State.KeyframeDrag
local SelectionState = State.Selection
local KEYFRAME_DEFAULT_COLOR = State.Colors.KEYFRAME_DEFAULT_COLOR
local KEYFRAME_HOVER_COLOR = State.Colors.KEYFRAME_HOVER_COLOR
local KEYFRAME_SELECTED_COLOR = State.Colors.KEYFRAME_SELECTED_COLOR
local LOOP_ACTIVE_COLOR = State.Colors.LOOP_ACTIVE_COLOR
local LOOP_INACTIVE_COLOR = State.Colors.LOOP_INACTIVE_COLOR

return function(Timeline)
	function Timeline:TimeToFrame(t)
		return math.floor(t * TimelineState.FPS + 0.5)
	end

	function Timeline:FrameToTime(frame)
		return frame / TimelineState.FPS
	end

	function Timeline:PixelToTime(pixelX)
		local width = self:GetVisibleTimelineWidth()

		if width <= 0 then
			return 0
		end

		local alpha = math.clamp(pixelX / width, 0, 1)
		return alpha * TimelineConfig.Length
	end

	function Timeline:PixelToFrame(pixelX)
		local t = self:PixelToTime(pixelX)
		return self:TimeToFrame(t)
	end

	function Timeline:GetTimelineWidth()
		return math.max(0, math.floor(TimelineConfig.Length * TimelineConfig.PixelsPerSecond))
	end

	function Timeline:GetMajorTickStep(pixelsPerFrame)
		pixelsPerFrame = pixelsPerFrame
			or self:GetVisibleTimelineWidth() / math.max(1, self:GetMaxFrame())
		local wantedSpacing = 45

		local rawStep = wantedSpacing / math.max(1e-6, pixelsPerFrame)

		local steps = { 1, 2, 5, 10, 15, 30, 60, 120, 300 }

		for _, step in ipairs(steps) do
			if step >= rawStep then
				return step
			end
		end

		return math.ceil(rawStep / 300) * 300
	end

	function Timeline:GetMaxFrame()
		return self:TimeToFrame(TimelineConfig.Length)
	end

	function Timeline:VisibleXToFrame(x)
		return self:TimeToFrame(self:VisibleXToTime(x))
	end

	function Timeline:VisibleXToTime(x)
		local width = self:GetVisibleTimelineWidth()
		if width <= 0 then
			return 0
		end

		local alpha = math.clamp(x / width, 0, 1)
		return alpha * TimelineConfig.Length
	end

	function Timeline:FrameToVisibleX(frame)
		frame = math.max(0, math.floor(frame + 0.5))
		local maxFrame = self:GetMaxFrame()
		local width = self:GetVisibleTimelineWidth()

		if maxFrame <= 0 then
			return 0
		end

		return math.floor((frame / maxFrame) * width + 0.5)
	end
end
