--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RunService = game:GetService("RunService")
local UserInputService = require("UserInputService")

local Easing = require("Easing")

local CurveGraph = {}

local NUM_POINTS = 160
local Theme = require("Theme")
local LINE_THICKNESS = 2
local TRANSITION_DURATION = 0.25
local Y_MIN = -0.25
local Y_MAX = 1.25
local Y_RANGE = Y_MAX - Y_MIN

local graphFrame = nil
local segments = {}
local currentYs = {}
local sourceYs = {}
local targetYs = {}
local transitionStart = 0
local transitionActive = false
local heartbeatConn = nil
local sizeChangedConn = nil

local handle1 = nil
local handle2 = nil
local onHandleChange = nil
local dragHandleIndex = nil
local dragConn = nil
local inputEndedConn = nil
local inputChangedConn = nil
local handleConnections = {}
local frameDestroyConn = nil
local lastGX, lastGY = nil, nil
local flushDrag

local function clamp01(v)
	if v < 0 then
		return 0
	end

	if v > 1 then
		return 1
	end

	return v
end

local function easeOutCubic(t)
	local x = 1 - t
	return 1 - x * x * x
end

local function sampleAt(t, keyData)
	return Easing.apply(t, keyData)
end

local function mapYToScreen(y, h)
	return h * (Y_MAX - y) / Y_RANGE
end

local function updateSegments()
	if not graphFrame then
		return
	end

	local size = graphFrame.AbsoluteSize
	local scale = 1
	local ancestor = graphFrame
	while ancestor do
		if ancestor:IsA("GuiObject") or ancestor:IsA("LayerCollector") then
			local uiScale = ancestor:FindFirstChildOfClass("UIScale")
			if uiScale then
				scale *= uiScale.Scale
			end
		end

		ancestor = ancestor.Parent
	end

	local w, h = size.X / math.max(scale, 0.001), size.Y / math.max(scale, 0.001)
	if w <= 0 or h <= 0 then
		return
	end

	local denom = NUM_POINTS - 1
	for i = 1, NUM_POINTS - 1 do
		local seg = segments[i]
		if seg then
			local x1 = (i - 1) / denom * w
			local x2 = i / denom * w
			local y1 = mapYToScreen(currentYs[i], h)
			local y2 = mapYToScreen(currentYs[i + 1], h)

			local dx = x2 - x1
			local dy = y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			local cx = (x1 + x2) * 0.5
			local cy = (y1 + y2) * 0.5
			local rotation = math.deg(math.atan2(dy, dx))

			seg.Position = UDim2.fromOffset(cx, cy)
			seg.Size = UDim2.fromOffset(len + 2, LINE_THICKNESS)
			seg.Rotation = rotation
		end
	end
end

local function ensureHeartbeat()
	if heartbeatConn then
		return
	end

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if transitionActive then
			local elapsed = os.clock() - transitionStart
			local alpha = math.min(elapsed / TRANSITION_DURATION, 1)
			local eased = easeOutCubic(alpha)
			for i = 1, NUM_POINTS do
				currentYs[i] = sourceYs[i] + (targetYs[i] - sourceYs[i]) * eased
			end

			updateSegments()
			if alpha >= 1 then
				transitionActive = false
				heartbeatConn:Disconnect()
				heartbeatConn = nil
			end
		end
	end)
end

function CurveGraph.init(frame)
	if not frame then
		return
	end

	if graphFrame == frame then
		return
	end

	CurveGraph.destroy()
	graphFrame = frame
	frameDestroyConn = frame.Destroying:Once(CurveGraph.destroy)
	frame.ClipsDescendants = true

	local denom = NUM_POINTS - 1
	for i = 1, NUM_POINTS do
		local t = (i - 1) / denom
		currentYs[i] = t
		sourceYs[i] = t
		targetYs[i] = t
	end

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Frame") and string.sub(child.Name, 1, 8) == "Segment_" then
			child:Destroy()
		end
	end

	for i = 1, NUM_POINTS - 1 do
		local seg = Instance.new("Frame")
		seg.Name = "Segment_" .. i
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = Theme.get("Ph", Color3.fromRGB(226, 171, 192))
		seg:SetAttribute("ThemeBg", "Ph")
		Theme.applyInstance(seg)
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.ZIndex = 10
		seg.Parent = frame
		segments[i] = seg
	end

	updateSegments()

	if sizeChangedConn then
		sizeChangedConn:Disconnect()
	end

	sizeChangedConn = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSegments)
end

function CurveGraph.setTarget(keyData)
	if not graphFrame then
		return
	end

	local denom = NUM_POINTS - 1
	for i = 1, NUM_POINTS do
		sourceYs[i] = currentYs[i]
		local t = (i - 1) / denom
		targetYs[i] = sampleAt(t, keyData)
	end

	transitionStart = os.clock()
	transitionActive = true
	ensureHeartbeat()
end

function CurveGraph.setTargetImmediate(keyData)
	if not graphFrame then
		return
	end

	local denom = NUM_POINTS - 1
	for i = 1, NUM_POINTS do
		local t = (i - 1) / denom
		currentYs[i] = sampleAt(t, keyData)
		sourceYs[i] = currentYs[i]
		targetYs[i] = currentYs[i]
	end

	transitionActive = false
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	updateSegments()
end

local function graphCoordsFromMouse(mousePos)
	if not graphFrame then
		return 0, 0
	end

	local absPos = graphFrame.AbsolutePosition
	local absSize = graphFrame.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then
		return 0, 0
	end

	local relX = (mousePos.X - absPos.X) / absSize.X
	local relY = (mousePos.Y - absPos.Y) / absSize.Y
	local graphY = Y_MAX - relY * Y_RANGE
	return relX, graphY
end

local function positionHandleAt(handle, x, y)
	if not handle then
		return
	end

	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	local screenYScale = (Y_MAX - y) / Y_RANGE
	handle.Position = UDim2.new(x, 0, screenYScale, 0)
end

function CurveGraph.attachHandles(h1, h2, callback)
	CurveGraph.suspend()
	for _, connection in handleConnections do
		connection:Disconnect()
	end

	table.clear(handleConnections)
	handle1 = h1
	handle2 = h2
	onHandleChange = callback

	local function wireHandle(handle, index)
		if not handle then
			return
		end

		handle.Active = true
		handle.ZIndex = 20
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("GuiObject") then
				child.ZIndex = 21
			end
		end

		table.insert(
			handleConnections,
			handle.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end

				if not handle.Visible then
					return
				end

				dragHandleIndex = index
				lastGX, lastGY = nil, nil
				if onHandleChange then
					onHandleChange("begin", index)
				end
			end)
		)
	end

	wireHandle(handle1, 1)
	wireHandle(handle2, 2)

	if inputEndedConn then
		inputEndedConn:Disconnect()
	end

	inputEndedConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if dragHandleIndex then
			flushDrag()
			local idx = dragHandleIndex
			dragHandleIndex = nil
			if onHandleChange then
				onHandleChange("end", idx)
			end
		end
	end)

	if inputChangedConn then
		inputChangedConn:Disconnect()
	end

	inputChangedConn = UserInputService.InputChanged:Connect(function(input)
		if
			not dragHandleIndex
			or input.UserInputType ~= Enum.UserInputType.MouseMovement
			or dragConn
		then
			return
		end

		dragConn = RunService.RenderStepped:Once(function()
			dragConn = nil
			flushDrag()
		end)
	end)
end

function CurveGraph.setHandlesVisible(visible)
	if handle1 then
		handle1.Visible = visible
	end

	if handle2 then
		handle2.Visible = visible
	end
end

function CurveGraph.setHandlePositions(x1, y1, x2, y2)
	positionHandleAt(handle1, x1, y1)
	positionHandleAt(handle2, x2, y2)
end

flushDrag = function()
	if dragConn then
		dragConn:Disconnect()
		dragConn = nil
	end

	if not dragHandleIndex then
		return
	end

	local gx, gy = graphCoordsFromMouse(UserInputService:GetMouseLocation())
	gx, gy = math.clamp(gx, 0, 1), math.clamp(gy, Y_MIN, Y_MAX)
	if gx == lastGX and gy == lastGY then
		return
	end

	lastGX, lastGY = gx, gy
	if onHandleChange then
		onHandleChange("drag", dragHandleIndex, gx, gy)
	end
end

function CurveGraph.suspend(flushPending)
	if dragHandleIndex then
		if flushPending ~= false then
			flushDrag()
		end

		local index = dragHandleIndex
		dragHandleIndex = nil
		if onHandleChange then
			onHandleChange("end", index)
		end
	end

	transitionActive = false
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	if dragConn then
		dragConn:Disconnect()
		dragConn = nil
	end
end

function CurveGraph.destroy()
	CurveGraph.suspend(false)
	for _, connection in handleConnections do
		connection:Disconnect()
	end

	table.clear(handleConnections)
	for _, connection in { inputChangedConn, inputEndedConn, sizeChangedConn, frameDestroyConn } do
		if connection then
			connection:Disconnect()
		end
	end

	inputChangedConn, inputEndedConn, sizeChangedConn, frameDestroyConn = nil, nil, nil, nil
	graphFrame, handle1, handle2, onHandleChange = nil, nil, nil, nil
	table.clear(segments)
	table.clear(currentYs)
	table.clear(sourceYs)
	table.clear(targetYs)
end

return CurveGraph
