--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local PropertyValues = require("PropertyValues")

local State = require("State")
local CameraRig = require("CameraRig")
local GraphCurves = require("GraphCurves")
local Policy = require("Policy")
local History = require("History")
local Theme = require("Theme")
local Target = require("Target")
local Values = {}
local clipboard = {}
local copying = false
local AXES = { "X", "Y", "Z" }
local ROTATION = { "qrot_w", "qrot_x", "qrot_y", "qrot_z" }

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function Values.pose(key)
	return key.C0 or CFrame.identity
end

function Values.sizeBase(key)
	local motor = key.Motor
	if
		not motor
		or not motor.Parent
		or PropertyValues.definition(key)
		or CameraRig.isTransform(motor)
		or Target.is(motor)
		or not Policy.channelAvailable(motor, "scale_x")
		or typeof(motor) == "table"
			and (motor.IsEclipseMasterControl or motor.IsTranslationOnly)
	then
		return nil
	end

	local part = motor.Part1
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end

	local raw = State.Timeline and State.Timeline:GetState()
	return raw and raw.DefaultSize[part]
end

function Values.size(key)
	local base = Values.sizeBase(key)
	if not base then
		return nil
	end

	local result = {}
	local sampled
	for i, axis in AXES do
		local id = "scale_" .. axis:lower()
		local point = key.GraphCurves and key.GraphCurves[id]
		local channel = key.Channels and key.Channels[id]
		local value = channel and channel.Value
		if value == nil then
			local timeline = State.Timeline
			local bucket = timeline:GetState().Keyframes[key.Motor]
			if sampled == nil then
				sampled = bucket and timeline:EvaluateMotorScale(key.Motor, key.Time or 0, bucket)
					or false
			end

			value = sampled and sampled[id] or 1
		end

		if point and not point.Empty and point.Value ~= nil then
			value = point.Value
		end

		result[i] = base[axis] * value
	end

	return result
end

function Values.components(key)
	local pose = Values.pose(key)
	local x, y, z = pose:ToEulerAnglesXYZ()
	return {
		Position = { pose.X, pose.Y, pose.Z },
		Size = Values.size(key),
		Rotation = { math.deg(x), math.deg(y), math.deg(z) },
	}
end

function Values.edit(keys, group, axis, value)
	local all = axis == "All"
	if all then
		if type(value) ~= "table" or #value ~= 3 then
			return false
		end
		for _, number in value do
			if not finite(number) or group == "Size" and (number < 0.001 or number > 2048) then
				return false
			end
		end
	end
	if
		not all and not finite(value)
		or not all and not table.find(AXES, axis)
		or (group ~= "Position" and group ~= "Rotation" and group ~= "Size")
		or not all and group == "Size" and (value < 0.001 or value > 2048)
		or require("BlenderEdit").blocked()
		or #keys == 0
	then
		return false
	end

	local timeline = State.Timeline
	if not timeline then
		return false
	end

	local raw = timeline:GetState()
	for _, key in keys do
		if
			not key.Motor
			or not key.Motor.Parent
			or CameraRig.isFov(key.Motor)
			or Target.isAttachment(key.Motor)
			or group == "Size" and not Values.sizeBase(key)
			or not raw.Keyframes[key.Motor]
			or raw.Keyframes[key.Motor][key.Frame] ~= key
		then
			return false
		end
	end

	local before, after = {}, {}
	local index = table.find(AXES, axis)
	local ids = group == "Size" and (all and { "scale_x", "scale_y", "scale_z" } or { "scale_" .. axis:lower() })
		or group == "Position" and (all and { "loc_x", "loc_y", "loc_z" } or { "loc_" .. axis:lower() })
		or ROTATION
	for _, key in keys do
		if not before[key.Motor] then
			before[key.Motor] = timeline:_snapshotMotorBucket(key.Motor)
		end
	end

	for _, key in keys do
		if group == "Size" then
			for i, id in ids do
				local component = all and AXES[i] or axis
				local ratio = (all and value[i] or value) / Values.sizeBase(key)[component]
				key.Channels = key.Channels or {}
				key.Channels[id] = key.Channels[id] or {}
				key.Channels[id].Value = ratio
				if key.WholePoseScale then
					key.WholePoseScale[id] = ratio
				end
			end
			GraphCurves.recordPose(raw.Keyframes[key.Motor], key, Values.pose(key), ids)

			raw._motorHasScale[key.Motor] = nil
		else
			local old = Values.pose(key)
			local numbers = Values.components(key)
			if all then
				numbers[group] = table.clone(value)
			else
				numbers[group][index] = value
			end
			local p, r = numbers.Position, numbers.Rotation
			local updated = CFrame.new(p[1], p[2], p[3])
				* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
			if key.Parented == false and key.WorldCFrame then
				local c1 = key.Motor.C1
				key.WorldCFrame = key.WorldCFrame * c1 * old:Inverse() * updated * c1:Inverse()
			end

			key.ChannelPoseC0 = nil
			if key.Channels then
				local components = timeline:DecomposeC0(updated)
				for _, id in ids do
					key.Channels[id] = key.Channels[id] or {}
					key.Channels[id].Value = components[id]
				end
			end

			GraphCurves.recordPose(raw.Keyframes[key.Motor], key, updated, ids)

			key.C0, key.Position, key.Rotation = updated, updated.Position, updated.Rotation
		end

		GraphCurves.invalidate(raw.Keyframes[key.Motor])
		raw._motorUniform[key.Motor] = nil
		timeline:CreateOrUpdateTimelineKeyframeButton(
			key.Part,
			key.Motor,
			key.Frame,
			nil,
			key.SanitizeName
		)
		timeline:RefreshAllChannelDiamondsForMotor(key.Motor)
	end

	for motor in before do
		after[motor] = timeline:_snapshotMotorBucket(motor)
		require("HumanoidScale").bucketsChanged(motor, before[motor], after[motor])
	end

	local function refresh()
		State.currentProjectSaved = false
		for _, rig in State.getAllRigs() do
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime)
		end

		require("motionPath").markDirty()
	end

	local function apply(snapshot)
		for motor, bucket in snapshot do
			if motor.Parent then
				timeline:_restoreMotorBucket(motor, bucket)
			end
		end

		refresh()
	end

	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Edit " .. group .. " " .. axis)
	refresh()
	return true
end

function Values.copy(keys, group)
	if #keys == 0 or (group ~= "Position" and group ~= "Rotation" and group ~= "Size") then
		return false
	end
	local value = Values.components(keys[1])[group]
	if not value then
		return false
	end
	for _, key in keys do
		local other = Values.components(key)[group]
		for i = 1, 3 do
			if not other or not finite(other[i]) or math.abs(other[i] - value[i]) > 0.0001 then
				return false
			end
		end
	end
	clipboard[group] = table.clone(value)
	return true
end

function Values.paste(keys, group)
	local value = clipboard[group]
	return value ~= nil and Values.edit(keys, group, "All", value)
end

function Values.format(value)
	return string.format("%.17g, %.17g, %.17g", value[1], value[2], value[3])
end

function Values.parse(text)
	if type(text) ~= "string" or #text > 512 then return nil end
	text = text:match("^%s*(.-)%s*$")
	local wrapped = text:match("^Vector3%.new%s*%((.-)%)$") or text:match("^%((.-)%)$")
	if wrapped then text = wrapped end
	local parts = {}
	if text:find(",", 1, true) then
		parts = string.split(text, ",")
	else
		for part in text:gmatch("%S+") do table.insert(parts, part) end
	end
	if #parts ~= 3 then return nil end
	for i, part in parts do
		part = part:match("^%s*(.-)%s*$")
		if not part:match("^[%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*$")
			and not part:match("^[%+%-]?%d+%.%d*[eE]?[%+%-]?%d*$") then
			return nil
		end
		local value = tonumber(part)
		if not finite(value) then return nil end
		parts[i] = value
	end
	return parts
end

function Values.pasteText(keys, group, text)
	local value = Values.parse(text)
	if not value or not Values.edit(keys, group, "All", value) then return false end
	clipboard[group] = table.clone(value)
	return true
end

function Values.copyText(text)
	if copying or type(text) ~= "string" or #text == 0 or #text > 512 then
		return false
	end
	local Input = require("UserInputService")
	local native = game:GetService("UserInputService")
	if not Input.isWindowFocused() or native:IsKeyDown(Enum.KeyCode.C) then
		return false
	end
	copying = true
	local gui, field, virtual
	local controlDown, copyDown = false, false
	local ok = pcall(function()
		virtual = native:CreateVirtualInput()
		assert(virtual)
		Input.releaseClipboard()
		gui = Instance.new("ScreenGui")
		gui.Name = "EclipseValueCopy"
		gui.Archivable = false
		gui.Parent = game:GetService("Debris")
		game:GetService("Debris"):AddItem(gui, 2)
		field = Instance.new("TextBox")
		field.Text = text
		field.TextEditable = false
		field.ClearTextOnFocus = false
		field.Parent = gui
		field:CaptureFocus()
		task.wait()
		assert(field.Parent and field:IsFocused() and Input.isWindowFocused())
		field.SelectionStart = 1
		field.CursorPosition = #field.Text + 1
		if not native:IsKeyDown(Enum.KeyCode.LeftControl) then
			controlDown = true
			virtual:SendKey(true, Enum.KeyCode.LeftControl)
		end
		copyDown = true
		virtual:SendKey(true, Enum.KeyCode.C)
		virtual:SendKey(false, Enum.KeyCode.C)
		copyDown = false
		if controlDown then
			virtual:SendKey(false, Enum.KeyCode.LeftControl)
			controlDown = false
		end
		task.wait()
	end)
	if virtual then
		if copyDown then pcall(function() virtual:SendKey(false, Enum.KeyCode.C) end) end
		if controlDown then pcall(function() virtual:SendKey(false, Enum.KeyCode.LeftControl) end) end
	end
	if field then
		pcall(function() if field:IsFocused() then field:ReleaseFocus() end end)
	end
	if gui then gui:Destroy() end
	copying = false
	return ok
end

function Values.openClipboard(keys, group, action, refresh)
	if action == "Copy" then
		if not Values.copy(keys, group) then
			require("Notification").show("COPY", "Select compatible keys with matching values to copy.", 3)
			return false
		end
		local copied = Values.copyText(Values.format(clipboard[group]))
		if not copied then
			require("Notification").show("COPY", "Couldn't copy these values. Try again with Studio focused.", 3)
		end
		return copied
	end
	if action ~= "Paste" then return false end
	if not Values.paste(keys, group) then
		require("Notification").show("PASTE", "Copy " .. group:lower() .. " values first, then select compatible keys to paste onto.", 3)
		return false
	end
	if refresh then refresh() end
	return true
end

local function make(class, parent, name, properties)
	local object = Instance.new(class)
	object.Name = name
	for key, value in properties do
		object[key] = value
	end

	object.Parent = parent
	return object
end

function Values.build(template, parent, selection)
	local previous = parent:FindFirstChild("Values")
	if previous then
		previous:Destroy()
	end

	local frame = template:Clone()
	frame.Name, frame.Visible, frame.AutomaticSize = "Values", false, Enum.AutomaticSize.None
	frame.Size = UDim2.fromOffset(158, 124)
	local content = frame.Content
	local row = content.RowTemplate:FindFirstChildWhichIsA("GuiButton")
	local font = row.Title.FontFace
	for _, child in content:GetChildren() do
		child:Destroy()
	end

	content.AnchorPoint = Vector2.zero
	content.AutomaticSize = Enum.AutomaticSize.None
	content.Size, content.Position = UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0)
	frame.Parent = parent
	local fields = {}
	local session = { frame = frame, fields = fields }
	local properties
	local trackRow, trackField, enableRow, enableButton
	local attachmentPanel, attachmentLabel, attachmentButton

	function session.refresh()
		local keys = selection()
		local attachment = #keys > 0
		for _, key in keys do
			if not Target.isAttachment(key.Motor) then
				attachment = false
				break
			end
		end

		attachmentPanel.Visible = attachment
		if attachment then
			for _, child in content:GetChildren() do
				if child:IsA("GuiObject") then
					child.Visible = child == attachmentPanel
				end
			end

			frame.Size = UDim2.fromOffset(178, 104)
			local key = keys[1]
			local link = key.CamAttachTarget
			local object = Target.resolve(link)
			attachmentLabel.Text = #keys > 1 and "Select one attachment key"
				or object and object.Name
				or type(link) == "table" and ("Missing: " .. (link.label or "part"))
				or "Eclipse Camera"
			attachmentButton.Active = #keys == 1
			attachmentButton.AutoButtonColor = #keys == 1
			return
		end

		local typed = properties and properties.refresh()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "PropertyValues" then
				child.Visible = not typed and child ~= attachmentPanel
			end
		end

		if typed then
			return
		end

		frame.Size = UDim2.fromOffset(158, 124)
		local keys = selection()
		local tracking = #keys > 0
		for _, key in keys do
			if
				not CameraRig.isTransform(key.Motor)
				or CameraRig.owner(key.Motor):GetAttribute("EclipseTrackTarget") ~= true
			then
				tracking = false
				break
			end
		end

		if trackRow then
			trackRow.Visible = tracking
			if tracking then
				frame.Size = UDim2.fromOffset(158, 154)
				local weight = keys[1].CamTrackTo or 1
				for _, key in keys do
					if math.abs((key.CamTrackTo or 1) - weight) > 0.00001 then
						weight = nil
						break
					end
				end

				if not trackField:IsFocused() then
					trackField.Text = weight and string.format("%.2f", weight) or ""
					trackField.PlaceholderText = "Mixed"
				end
			end
		end

		local targets = #keys > 0
		for _, key in keys do
			if not require("Target").is(key.Motor) then
				targets = false
				break
			end
		end

		if enableRow then
			enableRow.Visible = targets
			if targets then
				frame.Size = UDim2.fromOffset(158, 154)
				local target = require("Target")
				local value = target.keyEnabled(keys[1])
				local mixed = false
				for _, key in keys do
					if target.keyEnabled(key) ~= value then
						mixed = true
					end
				end

				enableButton.Text = mixed and "MIXED" or value and "ENABLED" or "DISABLED"
			end
		end

		local sized = #keys > 0
		for _, key in keys do
			if not Values.sizeBase(key) then
				sized = false
				break
			end
		end

		content:FindFirstChild("Size").Visible = sized
		content.SizeClipboard.Visible = sized
		for _, axis in AXES do
			content["Size" .. axis].Visible = sized
		end

		if sized then
			frame.Size = UDim2.fromOffset(224, 124)
		end

		local source = keys[1] and Values.components(keys[1])
		for name, field in fields do
			if field:IsFocused() then
				continue
			end

			local group, axis = string.match(name, "(%w+)_(%w+)")
			local i = table.find(AXES, axis)
			if group == "Size" and not sized then
				field.Text = ""
				continue
			end

			local value = source and source[group] and source[group][i]
			for _, key in keys do
				if value and math.abs(Values.components(key)[group][i] - value) > 0.0001 then
					value = nil
					break
				end
			end

			field.Text = value and string.format("%.3f", value):gsub("%.?0+$", "") or ""
			field.PlaceholderText = source and "Mixed" or ""
		end
	end

	for column, group in { "Position", "Rotation", "Size" } do
		local x = 24 + (column - 1) * 66
		local heading = make("TextLabel", content, group, {
			Text = group == "Rotation" and "Rotation °" or group,
			Position = UDim2.fromOffset(x, 4),
			Size = UDim2.fromOffset(58, 18),
			BackgroundTransparency = 1,
			FontFace = font,
			TextSize = 12,
			ZIndex = frame.ZIndex + 2,
		})
		heading:SetAttribute("ThemeTxt", "Txt")
		local buttons = make("Frame", content, group .. "Clipboard", {
			Position = UDim2.fromOffset(x, 98), Size = UDim2.fromOffset(58, 20),
			BackgroundTransparency = 1, ZIndex = frame.ZIndex + 2,
		})
		for i, action in { "Copy", "Paste" } do
			local button = make("TextButton", buttons, action, {
				Position = UDim2.fromOffset(8 + (i - 1) * 24, 0), Size = UDim2.fromOffset(20, 20),
				Text = "", BorderSizePixel = 0, AutoButtonColor = true, ZIndex = frame.ZIndex + 3,
			})
			button:SetAttribute("ThemeBg", "TopBtn")
			make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 2) })
			local icon = make("ImageLabel", button, "Icon", {
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				Image = action == "Copy" and "rbxassetid://139641623684721"
					or "rbxassetid://127903458197090",
				ZIndex = button.ZIndex + 1,
			})
			icon:SetAttribute("ThemeImg", "Txt")
			if State.UIHelpers and State.UIHelpers.hoverDialog then
				State.UIHelpers.hoverDialog:latchToInstance(button, action .. " " .. group)
			end
			button.Activated:Connect(function()
				Values.openClipboard(table.clone(selection()), group, action, function()
					if frame.Parent then session.refresh() end
				end)
			end)
		end
		for i, axis in AXES do
			local y = 26 + (i - 1) * 24
			if column == 1 then
				local label = make("TextLabel", content, axis, {
					Text = axis,
					Position = UDim2.fromOffset(5, y),
					Size = UDim2.fromOffset(16, 20),
					BackgroundTransparency = 1,
					FontFace = font,
					TextSize = 12,
					ZIndex = frame.ZIndex + 2,
				})
				label:SetAttribute("ThemeTxt", "Txt")
			end

			local box = make("Frame", content, group .. axis, {
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(58, 20),
				BorderSizePixel = 0,
				ZIndex = frame.ZIndex + 2,
			})
			box:SetAttribute("ThemeBg", "TopBtn")
			local outline = make(
				"UIStroke",
				box,
				"Outline",
				{ ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1 }
			)
			outline:SetAttribute("ThemeStrk", "Strk")
			make("UICorner", box, "Corner", { CornerRadius = UDim.new(0, 2) })
			local field = make("TextBox", box, "Value", {
				Position = UDim2.fromOffset(4, 0),
				Size = UDim2.new(1, -8, 1, 0),
				BackgroundTransparency = 1,
				FontFace = font,
				TextSize = 12,
				ClearTextOnFocus = false,
				Text = "",
				ZIndex = frame.ZIndex + 3,
			})
			field:SetAttribute("ThemeTxt", "Txt")
			fields[group .. "_" .. axis] = field
			local editing
			field.Focused:Connect(function()
				editing = table.clone(selection())
			end)
			require("NumericInput").connect(field, { step = group == "Rotation" and 1 or 0.1 }, function()
				local value = tonumber(field.Text)
				if editing and finite(value) then
					Values.edit(editing, group, axis, value)
				end

				editing = nil
				session.refresh()
			end
)
		end
	end

	trackRow = make("Frame", content, "TrackTo", {
		Position = UDim2.fromOffset(5, 126),
		Size = UDim2.new(1, -15, 0, 22),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex + 2,
		Visible = false,
	})
	local Tool = require("Tool")
	Tool.label(trackRow, "Label", "Track to", UDim2.new(), UDim2.fromOffset(83, 22))
	trackField =
		Tool.field(trackRow, "Weight", "1.00", UDim2.new(1, -68, 0, 0), UDim2.fromOffset(68, 22))
	local weightKeys
	trackField.Focused:Connect(function()
		weightKeys = table.clone(selection())
	end)
	require("NumericInput").connect(trackField, { step = 0.05, min = 0, max = 1 }, function()
		if weightKeys then
			require("Targets").editWeight(weightKeys, tonumber(trackField.Text))
		end

		weightKeys = nil
		session.refresh()
	end)
	enableRow = make("Frame", content, "TargetEnabled", {
		Position = UDim2.fromOffset(5, 126),
		Size = UDim2.new(1, -15, 0, 22),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex + 2,
		Visible = false,
	})
	Tool.label(enableRow, "Label", "Tracking", UDim2.new(), UDim2.fromOffset(65, 22))
	enableButton = make("TextButton", enableRow, "Toggle", {
		Position = UDim2.new(1, -94, 0, 0),
		Size = UDim2.fromOffset(94, 22),
		Text = "DISABLED",
		FontFace = font,
		TextSize = 10,
		BorderSizePixel = 0,
		ZIndex = frame.ZIndex + 3,
	})
	enableButton:SetAttribute("ThemeBg", "TopBtn")
	enableButton:SetAttribute("ThemeTxt", "Txt")
	enableButton.Activated:Connect(function()
		local keys = selection()
		if #keys > 0 then
			require("Targets").editEnabled(keys, not require("Target").keyEnabled(keys[1]))
			session.refresh()
		end
	end)
	attachmentPanel = make("Frame", content, "AttachmentValues", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex + 2,
		Visible = false,
	})
	local heading = Tool.label(
		attachmentPanel,
		"Heading",
		"Camera source",
		UDim2.fromOffset(8, 4),
		UDim2.new(1, -16, 0, 18)
	)
	attachmentLabel = Tool.label(
		attachmentPanel,
		"Source",
		"Eclipse Camera",
		UDim2.fromOffset(8, 24),
		UDim2.new(1, -16, 0, 20)
	)
	attachmentLabel.TextTruncate = Enum.TextTruncate.AtEnd
	attachmentButton = Tool.button(
		attachmentPanel,
		"ChooseTarget",
		"CHOOSE PART…",
		UDim2.fromOffset(8, 51),
		UDim2.new(1, -16, 0, 24),

		function()
			local keys = selection()
			if #keys ~= 1 or not Target.isAttachment(keys[1].Motor) then
				return
			end

			local key = keys[1]
			require("Targets").openCameraAttachment(CameraRig.owner(key.Motor), key.Frame)
		end
	)
	Tool.label(
		attachmentPanel,
		"Hint",
		"Choose a source, then Apply",
		UDim2.fromOffset(8, 79),
		UDim2.new(1, -16, 0, 18)
	)
	for _, object in attachmentPanel:GetDescendants() do
		if object:IsA("GuiObject") then
			object.ZIndex = frame.ZIndex + 3
		end
	end

	properties = PropertyValues.build(frame, selection)
	Theme.applyTree(frame)
	return session
end

return Values
