--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Motion = require("Motion")

local Data = require("ProjectData")

local DEFAULT_MIN_SIZE = Vector2.new(584, 137)
local DEFAULT_MAX_SIZE = Vector2.new(2494, 1320)
local EDGE_THICKNESS = 6
local CORNER_THICKNESS = 12

local CURSOR_EW = "rbxasset://SystemCursors/SizeEW"
local CURSOR_NS = "rbxasset://SystemCursors/SizeNS"
local CURSOR_NESW = "rbxasset://SystemCursors/SizeNESW"
local CURSOR_NWSE = "rbxasset://SystemCursors/SizeNWSE"

local HANDLE_DEFS = {
	{
		name = "Top",
		cursor = CURSOR_NS,
		anchor = Vector2.new(0.5, 0),
		pos = UDim2.new(0.5, 0, 0, 0),
		size = UDim2.new(1, -CORNER_THICKNESS * 2, 0, EDGE_THICKNESS),
	},
	{
		name = "Bottom",
		cursor = CURSOR_NS,
		anchor = Vector2.new(0.5, 1),
		pos = UDim2.new(0.5, 0, 1, 0),
		size = UDim2.new(1, -CORNER_THICKNESS * 2, 0, EDGE_THICKNESS),
	},
	{
		name = "Left",
		cursor = CURSOR_EW,
		anchor = Vector2.new(0, 0.5),
		pos = UDim2.new(0, 0, 0.5, 0),
		size = UDim2.new(0, EDGE_THICKNESS, 1, -CORNER_THICKNESS * 2),
	},
	{
		name = "Right",
		cursor = CURSOR_EW,
		anchor = Vector2.new(1, 0.5),
		pos = UDim2.new(1, 0, 0.5, 0),
		size = UDim2.new(0, EDGE_THICKNESS, 1, -CORNER_THICKNESS * 2),
	},
	{
		name = "TopLeft",
		cursor = CURSOR_NWSE,
		anchor = Vector2.new(0, 0),
		pos = UDim2.new(0, 0, 0, 0),
		size = UDim2.fromOffset(CORNER_THICKNESS, CORNER_THICKNESS),
	},
	{
		name = "TopRight",
		cursor = CURSOR_NESW,
		anchor = Vector2.new(1, 0),
		pos = UDim2.new(1, 0, 0, 0),
		size = UDim2.fromOffset(CORNER_THICKNESS, CORNER_THICKNESS),
	},
	{
		name = "BottomLeft",
		cursor = CURSOR_NESW,
		anchor = Vector2.new(0, 1),
		pos = UDim2.new(0, 0, 1, 0),
		size = UDim2.fromOffset(CORNER_THICKNESS, CORNER_THICKNESS),
	},
	{
		name = "BottomRight",
		cursor = CURSOR_NWSE,
		anchor = Vector2.new(1, 1),
		pos = UDim2.new(1, 0, 1, 0),
		size = UDim2.fromOffset(CORNER_THICKNESS, CORNER_THICKNESS),
	},
}

local SizeableWindows = {}

local function makeHandle(parent: GuiObject, def: any): ImageButton
	local handle = Instance.new("ImageButton")
	handle.Name = "EclipseResizeHandle_" .. def.name
	handle.AnchorPoint = def.anchor
	handle.Position = def.pos
	handle.Size = def.size
	handle.BackgroundTransparency = 1
	handle.ImageTransparency = 1
	handle.BorderSizePixel = 0
	handle.AutoButtonColor = false
	handle.ZIndex = 1000
	handle.Active = true
	handle.Selectable = false
	handle.Parent = parent
	return handle
end

local function attach(options: {
	frame: GuiObject,
	mouse: any?,
	minSize: Vector2?,
	maxSize: Vector2?,
	settingKey: string?,
	onResize: ((width: number, height: number) -> ())?,
})
	local frame = options.frame
	local mouse = options.mouse
	local minSize = options.minSize or DEFAULT_MIN_SIZE
	local maxSize = options.maxSize or DEFAULT_MAX_SIZE
	local settingKey = options.settingKey
	local onResize = options.onResize

	local activeDrag: any = nil
	local hoverIcon: string? = nil

	local function setCursor(icon: string?)
		if not mouse then
			return
		end

		mouse.Icon = icon or ""
	end

	local function applyResize(dx: number, dy: number)
		if not activeDrag then
			return
		end

		local oldSize = activeDrag.startSize
		local oldPos = activeDrag.startPos
		local flags = activeDrag.flags

		local desiredX = oldSize.X.Offset
		local desiredY = oldSize.Y.Offset

		if flags.left then
			desiredX = oldSize.X.Offset - dx
		elseif flags.right then
			desiredX = oldSize.X.Offset + dx
		end

		if flags.top then
			desiredY = oldSize.Y.Offset - dy
		elseif flags.bottom then
			desiredY = oldSize.Y.Offset + dy
		end

		local newX = math.clamp(desiredX, minSize.X, maxSize.X)
		local newY = math.clamp(desiredY, minSize.Y, maxSize.Y)

		local actualDeltaX = newX - oldSize.X.Offset
		local actualDeltaY = newY - oldSize.Y.Offset

		local deltaPosX = 0
		local deltaPosY = 0

		if flags.left then
			deltaPosX = -actualDeltaX / 2
		elseif flags.right then
			deltaPosX = actualDeltaX / 2
		end

		if flags.top then
			deltaPosY = -actualDeltaY / 2
		elseif flags.bottom then
			deltaPosY = actualDeltaY / 2
		end

		frame.Size = UDim2.new(oldSize.X.Scale, newX, oldSize.Y.Scale, newY)
		frame.Position = UDim2.new(
			oldPos.X.Scale,
			oldPos.X.Offset + deltaPosX,
			oldPos.Y.Scale,
			oldPos.Y.Offset + deltaPosY
		)

		if onResize then
			onResize(newX, newY)
		end
	end

	local function saveState()
		if not settingKey then
			return
		end

		local sz = frame.Size
		local pos = frame.Position
		Data.setSetting(settingKey, {
			sizeScaleX = sz.X.Scale,
			sizeOffsetX = sz.X.Offset,
			sizeScaleY = sz.Y.Scale,
			sizeOffsetY = sz.Y.Offset,
			positionScaleX = pos.X.Scale,
			positionOffsetX = pos.X.Offset,
			positionScaleY = pos.Y.Scale,
			positionOffsetY = pos.Y.Offset,
		})
	end

	local function loadState()
		if not settingKey then
			return
		end

		local saved = Data.getSetting(settingKey)
		if type(saved) ~= "table" then
			return
		end

		local currentSize = frame.Size
		local currentPos = frame.Position

		local sx = math.clamp(saved.sizeOffsetX or currentSize.X.Offset, minSize.X, maxSize.X)
		local sy = math.clamp(saved.sizeOffsetY or currentSize.Y.Offset, minSize.Y, maxSize.Y)

		frame.Size = UDim2.new(
			saved.sizeScaleX or currentSize.X.Scale,
			sx,
			saved.sizeScaleY or currentSize.Y.Scale,
			sy
		)
		frame.Position = UDim2.new(
			saved.positionScaleX or currentPos.X.Scale,
			saved.positionOffsetX or currentPos.X.Offset,
			saved.positionScaleY or currentPos.Y.Scale,
			saved.positionOffsetY or currentPos.Y.Offset
		)

		if onResize then
			onResize(frame.Size.X.Offset, frame.Size.Y.Offset)
		end
	end

	for _, def in ipairs(HANDLE_DEFS) do
		local handle = makeHandle(frame, def)
		local flags = {
			left = string.find(def.name, "Left") ~= nil,
			right = string.find(def.name, "Right") ~= nil,
			top = string.find(def.name, "Top") ~= nil,
			bottom = string.find(def.name, "Bottom") ~= nil,
		}
		local cursor = def.cursor

		handle.MouseEnter:Connect(function()
			hoverIcon = cursor
			if not activeDrag then
				setCursor(cursor)
			end
		end)

		handle.MouseLeave:Connect(function()
			hoverIcon = nil
			if not activeDrag then
				setCursor(nil)
			end
		end)

		handle.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			if activeDrag or frame:GetAttribute("EclipseDocked") then
				return
			end

			activeDrag = {
				handle = handle,
				flags = flags,
				mouseStart = input.Position,
				startSize = frame.Size,
				startPos = frame.Position,
				cursor = cursor,
			}
			setCursor(cursor)

			local drag = activeDrag
			local scale = Motion.scale(frame)
			Motion.begin(frame, input, function(point)
				local delta = (point - drag.mouseStart) / scale
				applyResize(delta.X, delta.Y)
			end, function()
				activeDrag = nil
				if frame.Parent then
					saveState()
				end

				setCursor(hoverIcon)
			end, "resize")
		end)
	end

	loadState()
	return saveState
end

SizeableWindows.attach = attach

local function attachDivider(options: {
	target: GuiObject,
	dragHandle: GuiObject,
	mouse: any?,
	cursor: string?,
	minWidth: number?,
	maxWidth: (number | (() -> number))?,
	settingKey: string?,
	onChange: ((width: number) -> ())?,
})
	local target = options.target
	local dragHandle = options.dragHandle
	local mouse = options.mouse
	local cursor = options.cursor or CURSOR_EW
	local minWidth = options.minWidth or 80
	local maxWidthRaw = options.maxWidth
	local settingKey = options.settingKey
	local onChange = options.onChange

	local function getMaxWidth(): number
		if type(maxWidthRaw) == "function" then
			return (maxWidthRaw :: any)()
		elseif type(maxWidthRaw) == "number" then
			return maxWidthRaw :: number
		end

		return math.huge
	end

	local activeDrag: any = nil
	local hovered = false

	local function setCursor(icon: string?)
		if not mouse then
			return
		end

		mouse.Icon = icon or ""
	end

	local function applyWidth(width: number)
		local clamped = math.clamp(width, minWidth, getMaxWidth())
		target.Size =
			UDim2.new(target.Size.X.Scale, clamped, target.Size.Y.Scale, target.Size.Y.Offset)
		if onChange then
			onChange(clamped)
		end
	end

	if settingKey then
		local saved = Data.getSetting(settingKey)
		if type(saved) == "number" then
			applyWidth(saved)
		end
	end

	dragHandle.MouseEnter:Connect(function()
		hovered = true
		if not activeDrag then
			setCursor(cursor)
		end
	end)

	dragHandle.MouseLeave:Connect(function()
		hovered = false
		if not activeDrag then
			setCursor(nil)
		end
	end)

	dragHandle.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		if activeDrag then
			return
		end

		activeDrag = {
			mouseStart = input.Position,
			startWidth = target.Size.X.Offset,
		}
		setCursor(cursor)

		local drag = activeDrag
		local scale = Motion.scale(target)
		Motion.begin(target, input, function(point)
			applyWidth(drag.startWidth + (point.X - drag.mouseStart.X) / scale)
		end, function()
			activeDrag = nil
			if settingKey and target.Parent then
				Data.setSetting(settingKey, target.Size.X.Offset)
			end

			if not hovered then
				setCursor(nil)
			end
		end, "divider")
	end)
end

SizeableWindows.attachDivider = attachDivider

return SizeableWindows
