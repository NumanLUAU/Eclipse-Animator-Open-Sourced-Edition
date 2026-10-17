--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")
local Motion = require("Motion")

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
	function Timeline:SyncScrollingFrameHeight()
		local keys, scroll = self.refs.KeysRoot, self.refs.RigListScroll
		local scale = Motion.scale(keys)

		local limit = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
		local height = math.ceil(limit + keys.AbsoluteWindowSize.Y + 2) / scale
		local size = UDim2.new(keys.CanvasSize.X.Scale, keys.CanvasSize.X.Offset, 0, height)
		if keys.CanvasSize ~= size then
			keys.CanvasSize = size
		end

		self:SyncScrollingFramePosition()
	end

	function Timeline:SyncScrollingFramePosition()
		local KeyRoots: ScrollingFrame = self.refs.KeysRoot
		local RigListScroll: ScrollingFrame = self.refs.RigListScroll

		KeyRoots.CanvasPosition = Vector2.new(0, RigListScroll.CanvasPosition.Y)
		if self.QueueKeyframeViewportRefresh then
			self:QueueKeyframeViewportRefresh()
		end
	end

	function Timeline:GetZoomScale()
		if self.timelineZoom and self.timelineZoom.GetZoom then
			return self.timelineZoom:GetZoom()
		end

		return 1
	end

	function Timeline:GetTimelineViewportWidth()
		local container = self.refs.TimelineContainer

		if container then
			return math.max(
				1,
				math.floor(container.AbsoluteSize.X / Motion.scale(container) - 40 + 0.5)
			)
		end

		return self:GetTimelineWidth()
	end

	function Timeline:GetBaseTimelineWidth()
		local viewportWidth = self:GetTimelineViewportWidth()
		return viewportWidth * math.max(1, self:GetMaxFrame() / TimelineConfig.DefaultFrames)
	end

	function Timeline:GetVisibleTimelineWidth()
		return math.max(
			self:GetTimelineViewportWidth(),
			math.floor(self:GetBaseTimelineWidth() * self:GetZoomScale() + 0.5)
		)
	end

	function Timeline:RefreshTimelineScale()
		local width = self:GetVisibleTimelineWidth()
		self._renderedTimelineWidth = width
		self._renderedTimelineMaxFrame = self:GetMaxFrame()

		if self.refs.Scale then
			TimelineState.ScrollOffset =
				math.clamp(TimelineState.ScrollOffset, 0, self:GetTimelineScrollLimit())
			self.refs.Scale.Position = UDim2.fromOffset(-TimelineState.ScrollOffset, 0)
			self.refs.Scale.Size = UDim2.new(0, width + 40, 1, 0)
		end

		if self.refs.Fit then
			self.refs.Fit.Position = UDim2.new(0, 0, 0, 0)
			self.refs.Fit.Size = UDim2.new(1, 0, 1, 0)
		end

		TimelineState.ContentWidth = width

		self:BuildGuidesAndTicks()
		self:RefreshAllTimelineKeyframePositions()
		self:UpdatePlayhead()
		self:RefreshNavigation()
	end

	function Timeline:EnsureTimelineScaleCurrent()
		if
			self._renderedTimelineWidth ~= self:GetVisibleTimelineWidth()
			or self._renderedTimelineMaxFrame ~= self:GetMaxFrame()
		then
			self:RefreshTimelineScale()
		end
	end

	function Timeline:ClearRuntimeChildren(container, keepNames)
		if not container then
			return
		end

		keepNames = keepNames or {}

		for _, child in ipairs(container:GetChildren()) do
			if not keepNames[child] and not child:GetAttribute("Template") then
				if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
					child:Destroy()
				end
			end
		end
	end

	function Timeline:ClearGuides()
		self._guideRange = nil
		local guidesFolder = self.refs.GuidesFolder
		local guideTemplate = self.refs.GuideTemplate
		if not guidesFolder or not guideTemplate then
			return
		end

		for _, child in ipairs(guidesFolder:GetChildren()) do
			if child ~= guideTemplate then
				child:Destroy()
			end
		end

		guideTemplate.Visible = false
	end

	function Timeline:ClearTicks()
		self._guideRange = nil
		local numberContainer = self.refs.TickNumberContainer
		local tickTemplate = self.refs.TickTemplate
		local topSelector = self.refs.TopSelector
		if not numberContainer or not tickTemplate then
			return
		end

		for _, child in ipairs(numberContainer:GetChildren()) do
			if child ~= tickTemplate and child ~= topSelector then
				child:Destroy()
			end
		end

		tickTemplate.Visible = false
	end

	function Timeline:GetVisibleTimelineFrame()
		return self.refs.Fit or self.refs.Scale or self.refs.TimelineContainer
	end

	function Timeline:GetRulerX(frame)
		return math.clamp(self:FrameToVisibleX(frame), 0, self:GetVisibleTimelineWidth())
			- TimelineState.ScrollOffset
	end

	function Timeline:PositionPlayhead()
		local container, scale = self.refs.SelectorContainer, self.refs.Scale
		local selector, top = self.refs.Selector, self.refs.TopSelector
		if not container or not scale or not selector or not top then
			return
		end

		container.Parent = self.refs.TimelineContainer
		container.Position, container.Size = scale.Position, scale.Size
		container.ZIndex = 45
		selector.ZIndex = 45
		top.Parent = container
		top.AnchorPoint = Vector2.new(0.5, 0)
		local x = math.clamp(
			self:FrameToVisibleX(self:TimeToFrame(TimelineState.CurrentTime)),
			0,
			self:GetVisibleTimelineWidth()
		)
		selector.Position = UDim2.new(0, x, selector.Position.Y.Scale, selector.Position.Y.Offset)
		top.Position = UDim2.new(0, x, 0, -14)
		top.ZIndex = 46
	end

	function Timeline:PositionRulerLabels()
		self:PositionPlayhead()
		local numbers = self.refs.TickNumberContainer
		for _, tick in numbers:GetChildren() do
			if tick:IsA("TextLabel") and tick.Name:match("^Tick_") then
				local frame = tonumber(tick.Text)
				if frame then
					tick.Position = UDim2.new(
						0,
						self:GetRulerX(frame),
						tick.Position.Y.Scale,
						tick.Position.Y.Offset
					)
				end
			end
		end
	end

	function Timeline:BuildGuidesAndTicks()
		local guidesFolder = self.refs.GuidesFolder
		local guideTemplate = self.refs.GuideTemplate
		local numberContainer = self.refs.TickNumberContainer
		local tickTemplate = self.refs.TickTemplate

		if not guidesFolder or not guideTemplate or not numberContainer or not tickTemplate then
			return
		end

		local ruler = numberContainer.Parent
		if self.refs.TimelineContainer and ruler then
			ruler.Parent = self.refs.TimelineContainer
			ruler.AutomaticSize = Enum.AutomaticSize.None
			ruler.Size = UDim2.new(1, -40, 0, 34)
			ruler.Position = UDim2.fromOffset(20, 0)
			ruler.ZIndex = 41
			local hitbox = self.refs.TopSelectorDragHitbox
			if hitbox then
				hitbox.ZIndex = 48
			end

			ruler.Visible = true

			numberContainer.AutomaticSize = Enum.AutomaticSize.None
			numberContainer.Size = UDim2.new(1, 0, 0, 16)
			numberContainer.Visible = true
			numberContainer.ZIndex = 41
			local top = self.refs.TopSelector
			if top then
				top.ZIndex = 46
				for _, child in top:GetDescendants() do
					if child:IsA("GuiObject") then
						child.ZIndex = 47
					end
				end
			end
		end

		local maxFrame = self:GetMaxFrame()
		local tickStep = self:GetMajorTickStep()
		local width = self:GetVisibleTimelineWidth()

		local first = math.max(
			0,
			math.floor(TimelineState.ScrollOffset / math.max(1, width) * maxFrame / tickStep)
				* tickStep
		)
		local last = math.min(
			maxFrame,
			math.ceil(
				(TimelineState.ScrollOffset + self:GetTimelineViewportWidth())
					/ math.max(1, width)
					* maxFrame
					/ tickStep
			) * tickStep
		)
		local range = table.concat({ first, last, tickStep, width, maxFrame }, ":")
		if
			self._guideRange == range
			and self._tickContainer == numberContainer
			and self._guideContainer == guidesFolder
			and numberContainer:FindFirstChild("Tick_" .. first)
		then
			self:PositionRulerLabels()
			return
		end

		self._tickContainer, self._guideContainer = numberContainer, guidesFolder

		guideTemplate.Visible = false
		tickTemplate.Visible = false
		self._guideRange = range
		local frames = {}
		for frame = first, last, tickStep do
			if frame == maxFrame or maxFrame - frame >= tickStep * 0.6 then
				table.insert(frames, frame)
			end
		end

		if last == maxFrame and frames[#frames] ~= maxFrame then
			table.insert(frames, maxFrame)
		end

		local activeGuides, activeTicks = {}, {}
		for _, frame in ipairs(frames) do
			local x = self:FrameToVisibleX(frame)
			x = math.clamp(x, 0, width)

			local guide = guidesFolder:FindFirstChild("Guide_" .. frame) or guideTemplate:Clone()
			activeGuides[guide] = true
			guide.Visible = true
			guide.Name = "Guide_" .. frame
			guide.Parent = guidesFolder
			guide.AnchorPoint = Vector2.new(0.5, guide.AnchorPoint.Y)
			guide.Position = UDim2.new(0, x, guide.Position.Y.Scale, guide.Position.Y.Offset)

			local tick = numberContainer:FindFirstChild("Tick_" .. frame) or tickTemplate:Clone()
			activeTicks[tick] = true
			tick.Visible = true
			tick.TextTransparency = 0
			tick.Name = "Tick_" .. frame
			tick.Parent = numberContainer
			tick.Text = tostring(frame)
			tick.Size = UDim2.fromOffset(48, 16)
			tick.TextXAlignment = Enum.TextXAlignment.Center
			tick.AutomaticSize = Enum.AutomaticSize.None
			tick.AnchorPoint = Vector2.new(0.5, tick.AnchorPoint.Y)
			tick.Position = UDim2.new(0, x, tick.Position.Y.Scale, tick.Position.Y.Offset)
		end

		for _, child in guidesFolder:GetChildren() do
			if
				child ~= guideTemplate
				and not activeGuides[child]
				and child.Name:match("^Guide_")
			then
				child:Destroy()
			end
		end

		for _, child in numberContainer:GetChildren() do
			if child ~= tickTemplate and not activeTicks[child] and child.Name:match("^Tick_") then
				child:Destroy()
			end
		end

		self:PositionRulerLabels()
	end
end
