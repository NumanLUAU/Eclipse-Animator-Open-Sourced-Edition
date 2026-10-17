--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Input = require("UserInputService")
local Numeric = {}
local bindings = setmetatable({}, { __mode = "k" })

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function read(box, entry)
	if entry.options.read then
		return entry.options.read(), ""
	end

	return Numeric.value(box.Text)
end

function Numeric.value(text)
	local body, suffix = tostring(text):gsub("px%s*$", ""):match("^%s*(.-)%s*(%%?)%s*$")
	local value = tonumber(body)
	return finite(value) and value or nil, suffix
end

function Numeric.next(value, direction, step, minimum, maximum)
	if not finite(value) or not finite(direction) or direction == 0 then
		return nil
	end

	step = finite(step) and step > 0 and step or 0.1
	local n = value + (direction > 0 and step or -step)
	if minimum then
		n = math.max(minimum, n)
	end

	if maximum then
		n = math.min(maximum, n)
	end

	return tonumber(string.format("%.10g", n))
end

local function visible(box, point)
	if not box.Parent or not box.TextEditable or not Input.isGuiPointCompatible(box) then
		return false
	end

	local node = box
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end

			if node == box or node.ClipsDescendants then
				local p, s = node.AbsolutePosition, node.AbsoluteSize
				if point.X < p.X or point.Y < p.Y or point.X > p.X + s.X or point.Y > p.Y + s.Y then
					return false
				end
			end
		elseif node:IsA("LayerCollector") and not node.Enabled then
			return false
		end

		node = node.Parent
	end

	return true
end

function Numeric.contains(point)
	for box, entry in bindings do
		if
			(not entry.options.enabled or entry.options.enabled())
			and read(box, entry)
			and visible(box, point)
		then
			return true
		end
	end

	return false
end

function Numeric.bind(box, options)
	if not box or not box:IsA("TextBox") then
		return
	end

	if bindings[box] then
		if options then
			bindings[box].options = options
		end

		return
	end

	local entry = { options = options or {}, connections = {}, scrolls = {} }
	bindings[box] = entry

	local function restore()
		for scroll, value in entry.scrolls do
			if scroll.Parent then
				scroll.ScrollingEnabled = value
			end
		end

		table.clear(entry.scrolls)
	end

	local function hover()
		restore()
		if not read(box, entry) or entry.options.enabled and not entry.options.enabled() then
			return
		end

		local node = box.Parent
		while node do
			if node:IsA("ScrollingFrame") then
				entry.scrolls[node] = node.ScrollingEnabled
				node.ScrollingEnabled = false
			end

			node = node.Parent
		end
	end

	local seen

	local function wheel(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel or input == seen then
			return
		end

		local opts = entry.options
		if opts.enabled and not opts.enabled() or not visible(box, Input:GetMouseLocation()) then
			return
		end

		local focus = Input:GetFocusedTextBox()
		if focus and focus ~= box then
			return
		end

		local value, suffix = read(box, entry)
		if value == nil then
			return
		end

		local step = type(opts.step) == "function" and opts.step() or opts.step or 0.1
		if
			not opts.integer
			and (
				Input:IsKeyDown(Enum.KeyCode.LeftShift)
				or Input:IsKeyDown(Enum.KeyCode.RightShift)
			)
		then
			step *= 0.1
		end

		local nextValue =
			Numeric.next(entry.pending or value, input.Position.Z, step, opts.min, opts.max)
		if nextValue == nil or nextValue == value then
			return
		end

		seen = input
		task.defer(function()
			if seen == input then
				seen = nil
			end
		end)
		if opts.change then
			opts.change(nextValue)
			return
		end

		if not box:IsFocused() then
			box:CaptureFocus()
		end

		if not box:IsFocused() then
			return
		end

		local pending = entry.pending
		entry.pending = nextValue
		if pending then
			return
		end

		task.defer(function()
			local n = entry.pending
			entry.pending = nil
			if not n or not box.Parent or not box:IsFocused() then
				return
			end

			box.Text = string.format("%.10g", n) .. suffix
			box:ReleaseFocus(true)
		end)
	end

	table.insert(entry.connections, box.InputChanged:Connect(wheel))
	table.insert(entry.connections, box.MouseEnter:Connect(hover))
	table.insert(entry.connections, box.MouseLeave:Connect(restore))
	if options and options.surface then
		table.insert(entry.connections, options.surface.InputChanged:Connect(wheel))
		table.insert(entry.connections, options.surface.MouseEnter:Connect(hover))
		table.insert(entry.connections, options.surface.MouseLeave:Connect(restore))
	end

	box.Destroying:Once(function()
		restore()
		bindings[box] = nil
		for _, connection in entry.connections do
			connection:Disconnect()
		end
	end)
end

function Numeric.connect(box, options, callback)
	Numeric.bind(box, options)
	return box.FocusLost:Connect(callback)
end

return Numeric
