--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local Tracks = require("Properties")
local Camera = require("CameraRig")
local History = require("History")
local Tool = require("Tool")
local Theme = require("Theme")
local Notification = require("Notification")
local Edit = require("BlenderEdit")
local Values = {}

function Values.definition(key)
	if Tracks.is(key.Motor) then
		return key.Motor.Definition
	end

	if Camera.isFov(key.Motor) then
		return { id = "FieldOfView", label = "FOV", kind = "number" }
	end
end

function Values.value(key)
	if Camera.isFov(key.Motor) then
		return Camera.decode(key.Motor, key.C0)
	end

	return Tracks.decode(key.Motor, key.C0, key.PropertyValue)
end

function Values.components(kind, value)
	if kind == "number" or kind == "string" or kind == "boolean" then
		return { value }
	end

	if kind == "EnumItem" then
		return { value.Name }
	end

	if kind == "Vector3" then
		return { value.X, value.Y, value.Z }
	end

	if kind == "Vector2" then
		return { value.X, value.Y }
	end

	if kind == "Color3" then
		return { value.R * 255, value.G * 255, value.B * 255 }
	end

	if kind == "NumberRange" then
		return { value.Min, value.Max }
	end

	if kind == "UDim" then
		return { value.Scale, value.Offset }
	end

	if kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	end

	if kind == "Rect" then
		return { value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
	end

	if kind == "BrickColor" then
		return { value.Number }
	end

	if kind == "NumberSequence" or kind == "ColorSequence" then
		local keys = {}
		for _, key in value.Keypoints do
			table.insert(
				keys,
				kind == "NumberSequence"
						and string.format("%.9g:%.9g:%.9g", key.Time, key.Value, key.Envelope)
					or string.format(
						"%.9g:%.9g:%.9g:%.9g",
						key.Time,
						key.Value.R * 255,
						key.Value.G * 255,
						key.Value.B * 255
					)
			)
		end

		return { table.concat(keys, "; ") }
	end

	if kind == "CFrame" then
		local x, y, z = value:ToEulerAnglesXYZ()
		return { value.X, value.Y, value.Z, math.deg(x), math.deg(y), math.deg(z) }
	end
end

function Values.compose(def, values)
	local kind = def.kind
	if kind == "number" or kind == "string" or kind == "boolean" then
		return values[1]
	end

	if kind == "EnumItem" then
		for _, value in def.enum:GetEnumItems() do
			if value.Name:lower() == tostring(values[1]):lower() then
				return value
			end
		end

		error("Choose a valid " .. def.label)
	end

	if kind == "Vector3" then
		return Vector3.new(table.unpack(values))
	end

	if kind == "Vector2" then
		return Vector2.new(table.unpack(values))
	end

	if kind == "Color3" then
		for _, v in values do
			assert(v >= 0 and v <= 255, "RGB values must be 0–255")
		end

		return Color3.fromRGB(table.unpack(values))
	end

	if kind == "UDim" then
		return UDim.new(table.unpack(values))
	end

	if kind == "UDim2" then
		return UDim2.new(table.unpack(values))
	end

	if kind == "Rect" then
		return Rect.new(table.unpack(values))
	end

	if kind == "BrickColor" then
		return BrickColor.new(values[1])
	end

	if kind == "NumberSequence" or kind == "ColorSequence" then
		local keys = {}
		for _, text in string.split(values[1], ";") do
			local v = {}
			for _, component in string.split(text, ":") do
				local number =
					assert(tonumber(component), "Enter numeric keypoint values separated by :")
				table.insert(v, number)
			end

			assert(
				#v == (kind == "NumberSequence" and 3 or 4),
				kind == "NumberSequence" and "Use time:value:envelope; time:value:envelope"
					or "Use time:red:green:blue; time:red:green:blue"
			)
			if kind == "ColorSequence" then
				for i = 2, 4 do
					assert(v[i] >= 0 and v[i] <= 255, "RGB values must be 0–255")
				end
			end

			table.insert(
				keys,
				kind == "NumberSequence" and NumberSequenceKeypoint.new(v[1], v[2], v[3])
					or ColorSequenceKeypoint.new(v[1], Color3.fromRGB(v[2], v[3], v[4]))
			)
		end

		return kind == "NumberSequence" and NumberSequence.new(keys) or ColorSequence.new(keys)
	end

	if kind == "NumberRange" then
		assert(values[1] <= values[2], "Minimum must not exceed maximum")
		return NumberRange.new(table.unpack(values))
	end

	if kind == "CFrame" then
		return CFrame.new(values[1], values[2], values[3])
			* CFrame.Angles(math.rad(values[4]), math.rad(values[5]), math.rad(values[6]))
	end
end

function Values.edit(keys, index, value)
	assert(not Edit.blocked(), "Finish the current edit before changing values")
	if #keys == 0 then
		return false
	end

	local timeline = State.Timeline
	local raw = timeline:GetState()
	local before, after, updates = {}, {}, {}
	for _, key in keys do
		local def = Values.definition(key)
		assert(def, "Select property keys of the same type")
		assert(
			raw.Keyframes[key.Motor] and raw.Keyframes[key.Motor][key.Frame] == key,
			"These keyframes changed; select them again"
		)
		local components = Values.components(def.kind, Values.value(key))
		components[index] = value
		local updated
		if index == 0 and def.kind == "ColorSequence" then
			assert(
				type(value) == "table"
					and typeof(value.Color) == "Color3"
					and type(value.StopTime) == "number",
				"Choose a color stop"
			)
			local points, found = {}, false
			for _, point in Values.value(key).Keypoints do
				local selected = math.abs(point.Time - value.StopTime) < 1e-6
				found = found or selected
				table.insert(
					points,
					ColorSequenceKeypoint.new(point.Time, selected and value.Color or point.Value)
				)
			end

			if not found then
				table.insert(points, ColorSequenceKeypoint.new(value.StopTime, value.Color))
				table.sort(points, function(a, b)
					return a.Time < b.Time
				end)
			end

			updated = ColorSequence.new(points)
		elseif index == 0 and def.kind == "BrickColor" then
			updated = BrickColor.new(value)
		elseif index == 0 and def.kind == "Color3" then
			updated = value
		else
			updated = Values.compose(def, components)
		end

		assert(
			Camera.isFov(key.Motor)
					and typeof(updated) == "number"
					and updated >= 1
					and updated <= 120
				or Tracks.is(key.Motor) and Tracks.validate(key.Motor, updated),
			"Invalid " .. def.label .. " value"
		)
		if Tracks.is(key.Motor) then
			Tracks.prepare(key.Motor, updated)
		end

		updates[key] = updated
		if not before[key.Motor] then
			before[key.Motor] = timeline:_snapshotMotorBucket(key.Motor)
		end
	end

	local function refresh()
		State.currentProjectSaved = false
		for _, rig in State.getAllRigs() do
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
		end

		timeline:RefreshAllKeyframeVisuals()
	end

	local function restore(snapshot)
		for motor, bucket in snapshot do
			timeline:_restoreMotorBucket(motor, bucket)
		end

		refresh()
	end

	local ok, err = pcall(function()
		for key, updated in updates do
			assert(
				raw.Keyframes[key.Motor] and raw.Keyframes[key.Motor][key.Frame] == key,
				"These keyframes changed; select them again"
			)
			if Tracks.is(key.Motor) then
				key.PropertyValue = updated
			else
				key.PropertyValue = nil
			end

			key.C0 = Camera.isFov(key.Motor) and Camera.encode(key.Motor, updated)
				or Tracks.encode(updated)
			key.Position, key.Rotation = key.C0.Position, key.C0.Rotation
			key.Channels = nil
			key.GraphCurves = nil
			key.ChannelPoseC0 = nil
			raw._motorUniform[key.Motor] = nil
		end

		for motor in before do
			require("GraphCurves").invalidate(raw.Keyframes[motor])
		end

		refresh()
	end)
	if not ok then
		restore(before)
		error(err, 0)
	end

	for motor in before do
		after[motor] = timeline:_snapshotMotorBucket(motor)
		require("HumanoidScale").bucketsChanged(motor, before[motor], after[motor])
	end

	History.record(function()
		restore(before)
	end, function()
		restore(after)
	end, "Edit property value")
	return true
end

function Values.build(frame, selection)
	local panel = Tool.make("Frame", frame.Content, "PropertyValues", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex + 2,
		Visible = false,
	})
	local signature
	local colorButton
	local fields = {}
	local def
	local editor = { panel = panel }

	local function commit(index, value, keys)
		local ok, err = pcall(Values.edit, keys or selection(), index, value)
		if not ok then
			Notification.show("PROPERTY VALUE", (tostring(err):gsub("^.-:%d+: ", "")))
		end

		editor.refresh()
	end

	function editor.refresh()
		local keys = selection()
		def = keys[1] and Values.definition(keys[1])
		for _, key in keys do
			local other = Values.definition(key)
			if not def or not other or other.kind ~= def.kind or other.enum ~= def.enum then
				def = nil
				break
			end
		end

		if not def then
			local typed = false
			for _, key in keys do
				if Values.definition(key) then
					typed = true
					break
				end
			end

			panel.Visible = typed
			if typed then
				for _, child in panel:GetChildren() do
					child:Destroy()
				end

				signature = nil
				fields = {}
				frame.Size = UDim2.fromOffset(214, 48)
				Tool.label(
					panel,
					"Mixed",
					"Select keys of one value type",
					UDim2.fromOffset(8, 4),
					UDim2.new(1, -16, 1, -8)
				)
				Theme.applyTree(panel)
			end

			return typed
		end

		panel.Visible = true
		local nextSignature = def.kind .. ":" .. def.label
		if signature ~= nextSignature then
			signature = nextSignature
			for _, child in panel:GetChildren() do
				child:Destroy()
			end

			fields = {}
			colorButton = nil
			local labels = ({
				Vector3 = { "X", "Y", "Z" },
				Vector2 = { "X", "Y" },
				Color3 = { "R", "G", "B" },
				NumberRange = { "Min", "Max" },
				UDim = { "Scale", "Offset" },
				UDim2 = { "X Scale", "X Offset", "Y Scale", "Y Offset" },
				Rect = { "Min X", "Min Y", "Max X", "Max Y" },
				BrickColor = { "Color number" },
				CFrame = { "X", "Y", "Z", "RX °", "RY °", "RZ °" },
			})[def.kind] or { def.label }
			local labelWidth = 64
			for _, label in labels do
				labelWidth = math.max(labelWidth, #label * 8 + 4)
			end

			local fieldX = labelWidth + 21
			local width = math.max(
				def.kind == "CFrame" and 214
					or (def.kind == "NumberSequence" or def.kind == "ColorSequence") and 420
					or def.kind == "string" and 240
					or 178,
				fieldX + 108
			)
			frame.Size = UDim2.fromOffset(width, 12 + #labels * 27)
			for index, label in labels do
				Tool.label(
					panel,
					"Label" .. index,
					label,
					UDim2.fromOffset(8, 6 + (index - 1) * 27),
					UDim2.fromOffset(labelWidth, 22)
				)
				if def.kind == "boolean" then
					local button, text = Tool.button(
						panel,
						"Toggle",
						"",
						UDim2.fromOffset(fieldX, 6),
						UDim2.new(1, -fieldX - 8, 0, 22),

						function()
							commit(1, not Values.value(selection()[1]))
						end
					)
					fields[index] = text
				elseif def.kind == "EnumItem" then
					local button, text = Tool.button(
						panel,
						"Choice",
						"",
						UDim2.fromOffset(fieldX, 6),
						UDim2.new(1, -fieldX - 8, 0, 22)
					)
					fields[index] = text
					button.Activated:Connect(function()
						local old = panel:FindFirstChild("Choices")
						if old then
							old:Destroy()
							signature = nil
							editor.refresh()
							return
						end

						local list = Tool.make("ScrollingFrame", panel, "Choices", {
							Position = UDim2.fromOffset(8, 34),
							Size = UDim2.new(
								1,
								-16,
								0,
								math.min(180, #def.enum:GetEnumItems() * 24)
							),
							CanvasSize = UDim2.new(),
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							ScrollBarThickness = 3,
							BorderSizePixel = 0,
							ZIndex = panel.ZIndex + 8,
							BackgroundColor3 = Color3.fromRGB(40, 20, 55),
						})
						list:SetAttribute("ThemeBg", "Top")
						Tool.make("UIListLayout", list, "Rows", {})
						frame.Size = UDim2.fromOffset(math.max(200, width), 42 + list.Size.Y.Offset)
						for _, choice in def.enum:GetEnumItems() do
							Tool.button(
								list,
								choice.Name,
								choice.Name,
								UDim2.new(),
								UDim2.new(1, -4, 0, 24),

								function()
									list:Destroy()
									signature = nil
									commit(1, choice.Name)
								end
							)
						end

						Theme.applyTree(list)
					end)
				else
					local field = Tool.field(
						panel,
						"Field" .. index,
						"",
						UDim2.fromOffset(fieldX, 6 + (index - 1) * 27),
						UDim2.new(1, -fieldX - 8, 0, 22)
					)
					fields[index] = field
					local editing
					local kind = (def.kind == "NumberSequence" or def.kind == "ColorSequence")
							and "string"
						or def.kind
					field.Focused:Connect(function()
						editing = table.clone(selection())
					end)
					require("NumericInput").connect(field, {
						step = def.facial and 0.05 or kind == "Color3" and 1 or 0.1,
						min = def.facial and 0 or nil,
						max = def.facial and 1 or nil,
						enabled = function()
							return kind ~= "string"
						end,
					}, function()
						local value = kind == "string" and field.Text or tonumber(field.Text)
						if value ~= nil and editing then
							commit(index, value, editing)
						else
							editor.refresh()
						end

						editing = nil
					end)
				end
			end

			if def.kind == "Color3" or def.kind == "BrickColor" or def.kind == "ColorSequence" then
				local isSequence = def.kind == "ColorSequence"
				local y = 12 + #labels * 27
				frame.Size = UDim2.fromOffset(width, y + 30)
				local stop = 1
				local stopText

				local function chosen()
					local value = Values.value(selection()[1])
					if isSequence then
						stop = math.clamp(stop, 1, #value.Keypoints)
						return value.Keypoints[stop]
					end
				end

				local function showStop()
					if stopText then
						local point = chosen()
						stopText.Text = string.format(
							"STOP %d / %d - %.2f",
							stop,
							#Values.value(selection()[1]).Keypoints,
							point.Time
						)
					end
				end

				if isSequence then
					local button, label = Tool.button(
						panel,
						"ColorStop",
						"",
						UDim2.fromOffset(8, y),
						UDim2.new(0.5, -12, 0, 22),

						function()
							stop = stop % #Values.value(selection()[1]).Keypoints + 1
							showStop()
						end
					)
					stopText = label
					showStop()
				end

				colorButton = Tool.button(
					panel,
					"PickColor",
					"PICK COLOR",
					isSequence and UDim2.new(0.5, 4, 0, y) or UDim2.fromOffset(8, y),
					isSequence and UDim2.new(0.5, -12, 0, 22) or UDim2.new(1, -16, 0, 22),

					function()
						local keys = table.clone(selection())
						if #keys == 0 then
							return
						end

						local timeline = State.Timeline
						local ui = require("UI")
						local gui = ui.EclipseGUI or frame:FindFirstAncestorWhichIsA("ScreenGui")
						if not gui then
							return
						end

						local value = Values.value(keys[1])
						local point = isSequence and chosen()
						local color = point and point.Value
							or typeof(value) == "BrickColor" and value.Color
							or value
						require("Picker").open(
							{ ScreenGui = gui },
							colorButton,
							{ stops = { color } },

							function(picked)
								commit(
									0,
									point and { StopTime = point.Time, Color = picked.stops[1] }
										or picked.stops[1],
									keys
								)
								showStop()
							end,
							{
								solid = true,
								commitOnDone = true,
								alive = function()
									return State.Timeline == timeline
										and not State.LoadingProject
										and gui.Enabled
										and (not ui.AnimatorFrame or ui.AnimatorFrame.Visible)
								end,
							}
						)
					end
				)
			end

			Theme.applyTree(panel)
		end

		for index, field in fields do
			if field:IsA("TextBox") and field:IsFocused() then
				continue
			end

			local value = Values.components(def.kind, Values.value(keys[1]))[index]
			for _, key in keys do
				if Values.components(def.kind, Values.value(key))[index] ~= value then
					value = nil
					break
				end
			end

			field.Text = value == nil and "Mixed"
				or typeof(value) == "boolean" and (value and "ON" or "OFF")
				or typeof(value) == "number" and string.format("%.4f", value):gsub("%.?0+$", "")
				or tostring(value)
		end

		return true
	end

	return editor
end

return Values
