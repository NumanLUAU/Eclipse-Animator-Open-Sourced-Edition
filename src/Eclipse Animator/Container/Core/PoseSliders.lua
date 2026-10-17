--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Tool = require("Tool")
local Theme = require("Theme")
local Tracks = require("Properties")
local History = require("History")
local Input = require("UserInputService")
local Edit = require("BlenderEdit")
local Sliders = {}
local refs, window, faceWindow, drag
local connections = {}
local chosen = setmetatable({}, { __mode = "k" })
local RESET = "rbxassetid://110138249483014"

local function owner(motor)
	return Tracks.is(motor) and motor.Rig or require("Layers").owner(motor)
end

local componentNames = {
 number = { "Value" }, boolean = { "Value" }, string = { "Value" }, EnumItem = { "Value" },
 Vector2 = { "X", "Y" }, Vector3 = { "X", "Y", "Z" }, Color3 = { "R", "G", "B" },
 CFrame = { "X", "Y", "Z", "RX", "RY", "RZ" }, NumberRange = { "Min", "Max" },
 UDim = { "Scale", "Offset" }, UDim2 = { "X Scale", "X Offset", "Y Scale", "Y Offset" },
 Rect = { "Min X", "Min Y", "Max X", "Max Y" }, BrickColor = { "Color number" },
 NumberSequence = { "Keypoints" }, ColorSequence = { "Keypoints" },
}

local function definition(motor)
 return Tracks.is(motor) and motor.Definition or { kind = "CFrame" }
end

function Sliders.channels(motor)
 return componentNames[definition(motor).kind] or {}
end

function Sliders.value(motor, channel, original)
 local value = original
 if value == nil then value = (if Tracks.is(motor) then Tracks.readValue(motor.Rig, motor.PropertyId) else motor.C0) end
 local components = require("PropertyValues").components(definition(motor).kind, value)
 return components[table.find(Sliders.channels(motor), channel)]
end

function Sliders.pose(motor, channel, value, original)
 local def = definition(motor)
 if original == nil then original = (if Tracks.is(motor) then Tracks.readValue(motor.Rig, motor.PropertyId) else motor.C0) end
 local components = require("PropertyValues").components(def.kind, original)
 components[assert(table.find(Sliders.channels(motor), channel), "Unknown slider component")] = value
 local result = require("PropertyValues").compose(def, components)
 return Tracks.encode(result), (if Tracks.is(motor) then result else nil)
end

local function apply(motor, bucket, time)
	if not motor.Parent then return end
	local timeline = refs.State.Timeline
	timeline:_restoreMotorBucket(motor, bucket)
	for _, rig in refs.State.getAllRigs() do timeline:ApplyPoseAtTime(rig, time, { OnlyRig = true }) end
	refs.State.currentProjectSaved = false
end

function Sliders.begin(motor, channel)
	if not refs or not refs.Active() or Edit.blocked() or drag then return false end
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	if raw.Playing or not motor.Parent or motor:GetAttribute("EclipseDisabled") then return false end
	if not table.find(Sliders.channels(motor), channel) then return false end
	if require("Layers").active(raw, motor).locked then return false end
	refs.Finalize()
	drag = { motor = motor, channel = channel, before = timeline:_snapshotMotorBucket(motor), time = raw.CurrentTime, frame = timeline:TimeToFrame(raw.CurrentTime), original = (if Tracks.is(motor) then Tracks.readValue(motor.Rig, motor.PropertyId) else motor.C0), changed = false }
	return true
end

function Sliders.change(value)
	if not drag or value == nil then return false end
	if typeof(value) == "number" and (value ~= value or math.abs(value) == math.huge) then return false end
	local d = drag
	if not d.motor.Parent then Sliders.finish(true) return false end
	local ok, cf, property = pcall(Sliders.pose, d.motor, d.channel, value, d.original)
	if not ok then return false end
	if Tracks.is(d.motor) and not Tracks.validate(d.motor, property) then return false end
	local timeline = refs.State.Timeline
	timeline:RecordKeyframeForMotorAtCurrentTime(d.motor.Part1, d.motor, cf, { Frame = d.frame, PropertyValue = property }, refs.State.UIHelpers.SanitizeName)
	for _, rig in refs.State.getAllRigs() do timeline:ApplyPoseAtTime(rig, d.time, { OnlyRig = true }) end
	d.changed = true
	return true
end

function Sliders.finish(cancel)
	local d = drag
	if not d then return end
	drag = nil
	if cancel or not d.changed then apply(d.motor, d.before, d.time) return end
	local after = refs.State.Timeline:_snapshotMotorBucket(d.motor)
	History.record(function() apply(d.motor, d.before, d.time) end, function() apply(d.motor, after, d.time) end, "Pose slider " .. d.channel, d.frame)
	refs.State.currentProjectSaved = false
end

function Sliders.isEditing() return drag ~= nil end

function Sliders.set(motor, channel, value)
	if not Sliders.begin(motor, channel) then return false end
	local ok, result = pcall(Sliders.change, value)
	Sliders.finish(not ok or not result)
	if not ok then error(result, 0) end
	return result
end

local function available(rig)
	local out, seen = {}, {}
	for _, item in refs.State.Rig._orderedItems or {} do
		local motor = item:fetchMotor()
		if motor and motor.Parent and not seen[motor] and (not rig or owner(motor) == rig) and #Sliders.channels(motor) > 0 then
			seen[motor] = true
			table.insert(out, { motor = motor, label = item.centerDiv.Title.Text })
		end
	end
    for _, object in refs.State.getAllRigs() do
        if not rig or rig == object then
            local existing = {}
            for _, motor in Tracks.list(object, true) do
                existing[motor.PropertyId] = motor
                if not seen[motor] and #Sliders.channels(motor) > 0 and not motor:GetAttribute("EclipseDisabled") then
                    seen[motor] = true
                    table.insert(out, { motor = motor, label = object.Name .. " · " .. motor.Definition.label })
                end
            end
            for _, def in Tracks.catalog(object) do
                if componentNames[def.kind] and (not existing[def.id] or existing[def.id]:GetAttribute("EclipseDisabled")) then
                    table.insert(out, { object = object, property = def.id, label = object.Name .. " · " .. def.label })
                end
            end
        end
    end
	table.sort(out, function(a, b) return a.label < b.label end)
	return out
end

Sliders.available = available

function Sliders.add(motor)
	local project = refs and refs.State.currentRig
	if not project then return false end
	for _, entry in available() do
		if entry.motor == motor or typeof(motor) == "table" and motor.object == entry.object and motor.property == entry.property and entry.object then
            if entry.object then
                motor = Tracks.enable(entry.object, entry.property, true, refs.State.Timeline:GetState())
                refs.State.currentProjectSaved = false
                if refs.RefreshStructure then refs.RefreshStructure() end
            end
			chosen[project] = chosen[project] or {}
			chosen[project][motor] = true
			return true
		end
	end
	return false
end

function Sliders.members()
	return refs and table.clone(chosen[refs.State.currentRig] or {}) or {}
end

function Sliders.removeAll()
	local project = refs and refs.State.currentRig
	if not project then return end
	Sliders.finish(true)
	table.clear(chosen[project] or {})
	if window and window.rebuild then window.rebuild() end
end

function Sliders.focus(motor)
	for _, view in { pose = window, face = faceWindow } do
		if view and view.focus then view.focus(motor) end
	end
end

function Sliders.open(rig)
	if not refs or not refs.Active() then return end
	local facial = rig ~= nil
	if not facial then require("ViewportSelection").apply({}, "replace") game:GetService("Selection"):Set({}) end
	if facial and not Tracks.faceControls(rig) then return end
	local previous = facial and faceWindow or window
	if facial and previous and previous.rig == rig then return previous end
	if previous then previous:close(true) end
	local view
	view = Tool.new(refs, facial and "EclipseFaceControls" or "EclipsePoseSliders", facial and "DYNAMIC HEAD" or "POSE SLIDERS", Vector2.new(480, 440), true, function()
		Sliders.finish(true)
		if facial then faceWindow = nil else window = nil end
	end, { Resizable = true, MinSize = Vector2.new(390, 240) })
	view.rig = rig
	if facial then faceWindow = view else window = view end
	local frame = view.frame
	frame.MinimumSize.MinSize = Vector2.new(390, 240)
	local project = refs.State.currentRig
	if not project then view:close(true) return end
	chosen[project] = chosen[project] or {}
	local members = chosen[project]
	local filter = Tool.field(frame, "Filter", "", UDim2.fromOffset(12, 36), UDim2.new(1, -24, 0, 25))
	filter.PlaceholderText = facial and "Filter expressions" or "Filter pose sliders"
	local top = facial and 70 or 104
	local list = Tool.make("ScrollingFrame", frame, "Controls", { Position = UDim2.fromOffset(12, top), Size = UDim2.new(1, -24, 1, -top - 12), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, BackgroundTransparency = 1, BorderSizePixel = 0 })
	local rows, picker = {}, nil
	local function selectMotor(motor)
		for _, item in refs.State.Rig._orderedItems or {} do
			if item:fetchMotor() == motor then require("ViewportSelection").apply({ item }, "replace") return end
		end
	end
	local function updateFilter()
		local query = filter.Text:lower():gsub("%s", "")
		for _, row in rows do row.frame.Visible = query == "" or row.search:find(query, 1, true) ~= nil end
	end
	local function refresh()
		for _, row in rows do
			if row.motor.Parent and not row.field:IsFocused() then
				local value = Sliders.value(row.motor, row.channel)
				row.field.Text = typeof(value) == "number" and string.format("%.3f", value) or tostring(value)
				if typeof(value) ~= "number" then continue end
				local t = math.clamp((value - row.low) / (row.high - row.low), 0, 1)
				row.knob.Position = UDim2.fromScale(t, 0.5)
				row.fill.Size = UDim2.fromScale(t, 1)
			end
		end
	end
	local rebuild
	rebuild = function()
		if picker then picker:Destroy() picker = nil end
		Sliders.finish(true)
		list:ClearAllChildren()
		table.clear(rows)
		Tool.make("UIListLayout", list, "Rows", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
		local entries = {}
		if facial then
			for _, motor in Tracks.list(rig) do if motor.Definition.facial then table.insert(entries, { motor = motor, label = motor.Definition.label }) end end
		else
			for _, entry in available() do if members[entry.motor] then table.insert(entries, entry) end end
		end
		if #entries == 0 then Tool.label(list, "Empty", "Add a bone or property to begin.", UDim2.new(), UDim2.new(1, 0, 0, 30)) end
		for _, entry in entries do
			local motor = entry.motor
			for _, channel in Sliders.channels(motor) do
				local row = Tool.make("Frame", list, "Slider", { Size = UDim2.new(1, -7, 0, 26), BackgroundTransparency = 1, LayoutOrder = #rows * 2 + 1 })
				local text = facial and entry.label:gsub("(%l)(%u)", "%1 %2") or channel == "Value" and entry.label or (entry.label .. " · " .. channel)
				local name = Tool.make("TextButton", row, "Name", { Text = text, Size = UDim2.new(0.4, -5, 1, 0), BackgroundTransparency = 1, TextSize = 11, FontFace = require("Chrome").FONT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
				name:SetAttribute("ThemeTxt", "Txt")
				name.Activated:Connect(function() selectMotor(motor) end)
				local right = facial and 0 or 24
				local field = Tool.field(row, "Number", "0", UDim2.new(1, -65 - right, 0, 1), UDim2.fromOffset(65, 24))
				local reset = Tool.make("ImageButton", row, "Reset", { Position = UDim2.new(1, -89 - right, 0, 4), Size = UDim2.fromOffset(18, 18), Image = RESET, BackgroundTransparency = 1 })
				reset:SetAttribute("ThemeImg", "Txt")
				if not facial then
					local remove = Tool.make("ImageButton", row, "Remove", { Position = UDim2.new(1, -20, 0, 4), Size = UDim2.fromOffset(18, 18), Image = "", BackgroundTransparency = 1 })
					require("LibraryIcons").dynamic(remove, "trash")
					remove.Activated:Connect(function() members[motor] = nil rebuild() end)
				end
				local slider = Tool.make("TextButton", row, "Slider", { Text = "", Position = UDim2.new(0.4, 0, 0, 0), Size = UDim2.new(0.6, -103 - right, 1, 0), BackgroundTransparency = 1, AutoButtonColor = false })
				local rail = Tool.make("Frame", slider, "Rail", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 0, 3), BorderSizePixel = 0 })
				rail:SetAttribute("ThemeBg", "Strk")
				local fill = Tool.make("Frame", rail, "Fill", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 })
				fill:SetAttribute("ThemeBg", "KeySel")
				local knob = Tool.make("Frame", rail, "Handle", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 12), Position = UDim2.fromScale(0, 0.5), BorderSizePixel = 0 })
				knob:SetAttribute("ThemeBg", "Txt")
				Tool.make("UICorner", knob, "Round", { CornerRadius = UDim.new(0, 2) })
				local value = Sliders.value(motor, channel)
				local face = Tracks.is(motor) and motor.Definition.facial
				local width = channel:sub(1, 1) == "R" and 180 or 10
				local numeric = typeof(value) == "number"
				local color = definition(motor).kind == "Color3"
				local low, high = face and 0 or color and 0 or numeric and value - width or 0, face and 1 or color and 255 or numeric and value + width or 1
				if not numeric then
					slider.Visible = false
					field.Position = UDim2.new(0.4, 0, 0, 1)
					field.Size = UDim2.new(0.6, -30 - right, 0, 24)
					reset.Position = UDim2.new(1, -24 - right, 0, 4)
				end
				local data = { frame = row, field = field, motor = motor, channel = channel, search = (entry.label .. channel):lower():gsub("%s", ""), low = low, high = high, knob = knob, fill = fill }
				table.insert(rows, data)
				local function commit(v)
					local ok, err = pcall(Sliders.set, motor, channel, v)
					if not ok then require("Notification").show("POSE SLIDERS", tostring(err)) end
					refresh()
				end
				if numeric then
                    require("NumericInput").connect(field, { step = face and 0.01 or color and 1 or 0.1, min = (face or color) and 0 or nil, max = face and 1 or color and 255 or nil }, function() commit(tonumber(field.Text)) end)
                else
                    field.FocusLost:Connect(function()
                        local text = field.Text
                        if definition(motor).kind == "boolean" then
                            if text:lower() == "true" or text == "1" then commit(true)
                            elseif text:lower() == "false" or text == "0" then commit(false)
                            else refresh() end
                        else commit(text) end
                    end)
                end
				reset.Activated:Connect(function()
					local rest = refs.State.Timeline:GetState().DefaultPose[motor] or motor.C0
                    if face then commit(0) else
                        commit(Sliders.value(motor, channel, (if Tracks.is(motor) then motor.DefaultValue else rest)))
                    end
				end)
				local function move(x)
					Sliders.change(low + math.clamp((x - rail.AbsolutePosition.X) / math.max(1, rail.AbsoluteSize.X), 0, 1) * (high - low))
					refresh()
				end
				slider.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 and Sliders.begin(motor, channel) then drag.move = move move(input.Position.X) end
				end)
			end
		end
		Theme.applyTree(frame)
		updateFilter()
		refresh()
	end
	if not facial then
		Tool.button(frame, "Add", "+ ADD", UDim2.fromOffset(12, 69), UDim2.new(1 / 3, -12, 0, 26), function()
			if picker then picker:Destroy() picker = nil return end
			picker = Tool.make("Frame", frame, "ChooseTrack", { Position = UDim2.fromOffset(12, 101), Size = UDim2.new(1, -24, 1, -113), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 30 })
			picker:SetAttribute("ThemeBg", "Bg")
			local search = Tool.field(picker, "Search", "", UDim2.fromOffset(6, 6), UDim2.new(1, -12, 0, 26))
			search.PlaceholderText = "Search bones and properties"
			local choices = Tool.make("ScrollingFrame", picker, "Tracks", { Position = UDim2.fromOffset(6, 38), Size = UDim2.new(1, -12, 1, -44), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 31 })
			Tool.make("UIListLayout", choices, "Rows", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
			local buttons = {}
			for index, entry in available() do
				if members[entry.motor] then continue end
				local b = Tool.button(choices, "Track", entry.label, UDim2.new(), UDim2.new(1, -6, 0, 26), function() Sliders.add(entry.motor or entry) picker:Destroy() picker = nil rebuild() end)
				b.LayoutOrder = index
				buttons[b] = entry.label:lower():gsub("%s", "")
			end
			search:GetPropertyChangedSignal("Text"):Connect(function()
				local query = search.Text:lower():gsub("%s", "")
				for button, label in buttons do button.Visible = label:find(query, 1, true) ~= nil end
				choices.CanvasPosition = Vector2.zero
			end)
			Theme.applyTree(picker)
			search:CaptureFocus()
		end)
		Tool.button(frame, "AddAll", "ADD ALL", UDim2.new(1 / 3, 6, 0, 69), UDim2.new(1 / 3, -12, 0, 26), function()
			for _, entry in available() do Sliders.add(entry.motor or entry) end
			rebuild()
		end)
	end
	if not facial then
		Tool.button(frame, "RemoveAll", "REMOVE ALL", UDim2.new(2 / 3, 0, 0, 69), UDim2.new(1 / 3, -12, 0, 26), Sliders.removeAll)
	end
	view.rebuild = rebuild
	view.focus = function(motor)
		for _, row in rows do
			if row.motor == motor then
				if not row.frame.Visible then filter.Text = "" updateFilter() end
				task.defer(function()
					if not row.frame.Parent or not list.Parent then return end
					local scale = math.max(0.01, row.frame.AbsoluteSize.Y / row.frame.Size.Y.Offset)
					local y = (row.frame.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
					list.CanvasPosition = Vector2.new(0, math.clamp(y, 0, math.max(0, (list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y) / scale)))
				end)
				return true
			end
		end
		return false
	end
	local lastSelected
	filter:GetPropertyChangedSignal("Text"):Connect(updateFilter)
	local elapsed = 0
	table.insert(view.connections, game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not refs.Active() or refs.State.currentRig ~= project or facial and not rig.Parent then view:close(true) return end
		elapsed += dt
		if elapsed > 0.1 then
			elapsed = 0 refresh()
			local item = refs.State.Rig._lastClickedItem
			if item ~= lastSelected then
				lastSelected = item
				if item then view.focus(item:fetchMotor()) end
			end
		end
	end))
	rebuild()
	return view
end

function Sliders.toggleFace(rig)
	if faceWindow and faceWindow.rig == rig then faceWindow:close() else return Sliders.open(rig) end
end

function Sliders.toggle()
	if window then window:close() else Sliders.open() end
end

function Sliders.close()
	Sliders.finish(true)
	if window then window:close(true) end
	if faceWindow then faceWindow:close(true) end
end

function Sliders.init(options)
	Sliders.close()
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	refs = options
	options.State.PoseSliders = Sliders
	local function connect(signal, callback) table.insert(connections, signal:Connect(callback)) end
	local function destroy()
		Sliders.close()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
	end
	connect(Input.InputChanged, function(input) if drag and drag.move and input.UserInputType == Enum.UserInputType.MouseMovement then drag.move(input.Position.X) end end)
	connect(Input.InputEnded, function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then Sliders.finish(false) end end)
	connect(Input.InputBegan, function(input) if input.KeyCode == Enum.KeyCode.Escape then Sliders.finish(true) end end)
	connect(game:GetService("UserInputService").WindowFocusReleased, function() Sliders.finish(true) end)
	connect(options.Plugin.Unloading, destroy)
	connect(options.ScreenGui.Destroying, destroy)
end

return Sliders

