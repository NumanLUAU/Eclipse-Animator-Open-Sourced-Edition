--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Events = require("Events")
local Data = require("SubtitleData")
local Theme = require("Theme")
local Input = require("UserInputService")
local Tracks = {}
local rows = {}
local selection
local drag
local clipboard

local function key(rig, id)
	return tostring(rig:GetAttribute("EclipseEventRigId")) .. ":" .. id
end

local function button(parent, name)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.ZIndex = 5
	b.Parent = parent
	return b
end

local function diamond(parent, name)
	local b = Instance.new("ImageButton")

	b.Name = name
	b.Image = "rbxassetid://77657913275528"
	b.BackgroundTransparency = 1
	b.Size = UDim2.fromOffset(12, 12)
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.ZIndex = 8
	b.Parent = parent
	return b
end

local function endpoint(parent, name)
	local hit = button(parent, name)
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(0, 12, 1, 0)
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.ZIndex = 9
	local face = Instance.new("Frame")

	face.Name = "Key"
	face.Size = UDim2.new(0, 8, 1, -2)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.BorderSizePixel = 0
	face.ZIndex = 10
	face.Parent = hit
	local inset = Instance.new("Frame")

	inset.Name = "Inset"
	inset.Position = UDim2.fromOffset(2, 2)
	inset.Size = UDim2.new(1, -4, 1, -4)
	inset.BorderSizePixel = 0
	inset.ZIndex = 11
	inset.Parent = face
	local shading = Instance.new("UIGradient")

	shading.Rotation = 90
	shading.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.49, Color3.fromRGB(240, 240, 240)),
		ColorSequenceKeypoint.new(0.51, Color3.fromRGB(195, 195, 195)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 180)),
	})
	shading.Parent = face
	return hit
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function lastFrame(timeline, start, duration)
	return math.max(timeline:GetMaxFrame(), start + duration)
end

local function startLimit(timeline, start, duration)
	return math.max(start, lastFrame(timeline, start, duration) - duration, 0)
end

function Tracks.unbind(rig, id)
	local k = key(rig, id)
	local row = rows[k]
	if not row then
		return
	end

	rows[k] = nil
	if drag and drag.row == row then
		drag.finish(true)
	end

	if row.unsubscribe then
		row.unsubscribe()
	end

	for _, c in row.connections do
		c:Disconnect()
	end

	for _, o in row.objects do
		o:Destroy()
	end

	rows[k] = nil
end

function Tracks.isDragging()
	return drag ~= nil
end

function Tracks.clear()
	if drag then
		drag.finish(true)
	end

	for _, row in table.clone(rows) do
		Tracks.unbind(row.rig, row.id)
	end

	selection = nil
	clipboard = nil
end

function Tracks.move(timeline, rig, id, offset, frame)
	local track = Events.get(rig)
	local event = track.Events[id]
	if not event or not event.Subtitle or not finite(frame) then
		return false
	end

	local before = Events.snapshot(track)
	if offset == nil then
		event.Frame = Events.nextFrame(
			track,
			math.clamp(
				math.round(frame),
				0,
				startLimit(timeline, event.Frame, event.Subtitle.Duration)
			),
			id
		)
	else
		local nextOffset =
			math.clamp(math.round(frame) - event.Frame, 1, event.Subtitle.Duration - 1)
		for _, k in event.Subtitle.Keys do
			if k.Frame == nextOffset and k.Frame ~= offset then
				return false
			end
		end

		for _, k in event.Subtitle.Keys do
			if k.Frame == offset then
				k.Frame = nextOffset
				break
			end
		end

		table.sort(event.Subtitle.Keys, function(a, b)
			return a.Frame < b.Frame
		end)
	end

	Events.changed(track)
	timeline:RecordEventEdit(track, before, "Move subtitle key")
	timeline:RefreshEventRows()
	return true
end

function Tracks.trim(timeline, rig, id, edge, frame, original)
	local track = Events.get(rig)
	local event = track.Events[id]
	if not event or not event.Subtitle or not finite(frame) then
		return false
	end

	local before = not original and Events.snapshot(track)
	local source = original or { Frame = event.Frame, Subtitle = Data.copy(event.Subtitle) }
	local cue = Data.copy(source.Subtitle)
	if edge == "end" then
		local last = cue.Keys[#cue.Keys]
		const minimum = math.max(1, last and last.Frame + 1 or 1)
		cue.Duration = math.clamp(
			math.round(frame) - source.Frame,
			minimum,
			math.max(minimum, math.min(1000000, lastFrame(timeline, source.Frame, cue.Duration) - source.Frame))
		)
	else
		local finish = source.Frame + cue.Duration
		local at = Events.nextFrame(track, math.clamp(math.round(frame), 0, finish - 1), id)
		if at >= finish then
			return false
		end

		local delta = at - source.Frame
		cue.Base = Data.style(Data.sample(cue, math.max(0, delta)))
		local keys = {}
		for _, k in cue.Keys do
			if k.Frame > delta then
				k.Frame -= delta
				table.insert(keys, k)
			end
		end

		cue.Keys = keys
		cue.Duration = finish - at
		event.Frame = at
	end

	event.Subtitle = Data.copy(cue)
	if before then
		Events.changed(track)
		timeline:RecordEventEdit(track, before, "Trim subtitle")
	else
		track.Revision += 1
	end

	Tracks.refresh(timeline)
	return true
end

local function begin(row, offset, input, edge)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if drag and drag.input == input then
		return
	end

	if drag then
		drag.finish(true)
	end

	local timeline = row.timeline
	local track = Events.get(row.rig)
	local event = track.Events[row.id]
	if not event or not event.Subtitle then
		return
	end

	timeline:ClearSelectedKeyframes()
	selection = { rig = row.rig, id = row.id, offset = offset }
	timeline:UpdateDeleteButtonState()
	Tracks.refresh(timeline)
	local origin = Input:GetMouseLocation()
	local first = timeline:EventFrameAtPoint(origin)
	local original = offset and event.Frame + offset or event.Frame
	local source = { Frame = event.Frame, Subtitle = Data.copy(event.Subtitle) }
	local before = Events.snapshot(track)
	local changed = false
	local moved = false
	local links = {}
	local session = { row = row, input = input }
	drag = session
	session.finish = function(cancel)
		if drag ~= session then
			return
		end

		drag = nil
		for _, c in links do
			c:Disconnect()
		end

		if cancel and changed then
			Events.restore(track, before)
		elseif changed then
			Events.changed(track)
			timeline:RecordEventEdit(track, before, edge and "Trim subtitle" or "Move subtitle")
		elseif not cancel and not moved then
			require("SubtitleEditor").open(track, row.id)
		end

		timeline:RefreshEventRows()
	end

	table.insert(
		links,
		Input.InputChanged:Connect(function(v)
			if v.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end

			local point = Input:GetMouseLocation()
			if (point - origin).Magnitude < 3 and not changed then
				return
			end

			moved = true
			local delta = timeline:EventFrameAtPoint(point) - first
			if delta == 0 and not changed then
				return
			end

			if edge then
				if
					not Tracks.trim(
						timeline,
						row.rig,
						row.id,
						edge,
						source.Frame + (edge == "end" and source.Subtitle.Duration or 0) + delta,
						source
					)
				then
					return
				end
			elseif offset then
				local f = math.clamp(original + delta - event.Frame, 1, event.Subtitle.Duration - 1)
				for _, k in event.Subtitle.Keys do
					if k.Frame == f and k.Frame ~= (session.currentOffset or offset) then
						return
					end
				end

				for _, k in event.Subtitle.Keys do
					if k.Frame == (session.currentOffset or offset) then
						k.Frame = f
						break
					end
				end

				session.currentOffset = f
				selection.offset = f
			else
				event.Frame = Events.nextFrame(
					track,
					math.clamp(
						original + delta,
						0,
						startLimit(timeline, source.Frame, source.Subtitle.Duration)
					),
					row.id
				)
			end

			changed = true
			track.Revision += 1
			Tracks.refresh(timeline)
		end)
	)
	table.insert(
		links,
		Input.InputEnded:Connect(function(v)
			if v.UserInputType == Enum.UserInputType.MouseButton1 then
				session.finish(false)
			end
		end)
	)
	table.insert(
		links,
		Input.InputBegan:Connect(function(v)
			if v.KeyCode == Enum.KeyCode.Escape then
				session.finish(true)
			end
		end)
	)
	table.insert(
		links,
		Input.WindowFocusReleased:Connect(function()
			session.finish(true)
		end)
	)
end

function Tracks.bind(timeline, item)
	local rig = item.grandpa.linkedRigInstance
	local id = item.subtitleId
	Tracks.unbind(rig, id)
	local container = timeline:GetTrackKeyframesContainer(item.trackElement)
	if not container then
		return
	end

	local template = container:FindFirstChild("KeyframeTemplate")
	if template then
		template.Visible = false
	end

	local row = {
		rig = rig,
		id = id,
		item = item,
		timeline = timeline,
		container = container,
		objects = {},
		connections = {},
		keys = {},
	}
	rows[key(rig, id)] = row
	if item.centerDiv then
		table.insert(
			row.connections,
			item.centerDiv.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end

				Tracks.select(timeline, rig, id)
				require("SubtitleEditor").open(Events.get(rig), id)
			end)
		)
	end

	for _, b in item.appearDetails.RightDiv:GetChildren() do
		if b:IsA("GuiButton") then
			b.Visible = false
		end
	end

	local clip = button(container, "SubtitleClip")
	row.clip = clip
	table.insert(row.objects, clip)
	clip.AnchorPoint = Vector2.new(0, 0.5)
	clip.Text = ""
	clip.ClipsDescendants = true
	local title = Instance.new("TextLabel")

	title.Name = "Caption"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(9, 0)
	title.Size = UDim2.new(1, -18, 1, 0)
	title.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 6
	title.Parent = clip
	row.title = title
	table.insert(
		row.connections,
		clip.InputBegan:Connect(function(input)
			begin(row, nil, input)
		end)
	)
	for _, edge in { "start", "end" } do
		local handle = endpoint(container, edge == "start" and "TrimStart" or "TrimEnd")
		row[edge] = handle
		table.insert(row.objects, handle)
		table.insert(
			row.connections,
			handle.InputBegan:Connect(function(input)
				begin(row, nil, input, edge)
			end)
		)
	end

	local disable = item.appearDetails.RightDiv:FindFirstChild("Disable")
	local enable = disable and disable:Clone() or Instance.new("ImageButton")
	enable.Name = "SubtitleEnabled"
	enable.Image = "rbxassetid://129527857019669"
	enable.Visible = true
	enable.BackgroundTransparency = 1
	enable:SetAttribute("ThemeImg", nil)
	if not disable then
		enable.Size = UDim2.fromOffset(14, 14)
	end

	enable.Parent = item.appearDetails.RightDiv
	row.enable = enable
	table.insert(row.objects, enable)
	table.insert(
		row.connections,
		enable.Activated:Connect(function()
			require("Subtitles").edit(Events.get(rig), id, function(_, event)
				event.Enabled = event.Enabled == false
			end, "Toggle subtitle")
		end)
	)
	row.unsubscribe = Theme.onChanged(function()
		Tracks.refresh(timeline)
	end)
	Tracks.refresh(timeline)
end

function Tracks.refresh(timeline)
	for _, row in rows do
		if not row.container.Parent or not row.clip.Parent or not row.start:FindFirstChild("Key") or not row["end"]:FindFirstChild("Key") then
			continue
		end
		local event = Events.get(row.rig).Events[row.id]
		if event and (not finite(event.Frame) or event.Subtitle and not finite(event.Subtitle.Duration)) then
			event = nil
		end

		row.clip.Visible = event ~= nil and event.Subtitle ~= nil
		row.start.Visible = row.clip.Visible
		row["end"].Visible = row.clip.Visible
		if not event or not event.Subtitle then
			for _, b in row.keys do
				b.Visible = false
			end

			continue
		end

		row.clip.Position = UDim2.new(0, timeline:FrameToVisibleX(event.Frame), 0.5, 0)
		local finish = timeline:FrameToVisibleX(event.Frame + event.Subtitle.Duration)
		local width = math.max(0, finish - row.clip.Position.X.Offset)
		row.clip.Size = UDim2.new(0, width, 1, -4)
		row.start.Position = row.clip.Position
		row["end"].Position = UDim2.new(0, finish, 0.5, 0)
		local selected = selection and selection.rig == row.rig and selection.id == row.id
		local accent = Theme.get("KfS", Color3.fromRGB(203, 181, 255))
		local text = Theme.get("Txt", Color3.new(1, 1, 1))
		local color = selected and accent or Theme.get("KfD", text)
		row.clip.BackgroundColor3 = accent
		row.clip.BackgroundTransparency = event.Enabled == false and 0.97
			or selected and 0.88
			or 0.97
		row.title.Text = event.Subtitle.Base.Text:gsub("\n", " ")
		row.title.TextColor3 = text
		row.title.TextTransparency = event.Enabled == false and 0.65 or selected and 0 or 0.2
		row.title.Visible = width >= 38
		for _, handle in { row.start, row["end"] } do
			handle.Key.BackgroundColor3 = color
			handle.Key.Inset.BackgroundColor3 = color:Lerp(Color3.new(), 0.38)
			handle.Key.BackgroundTransparency = event.Enabled == false and 0.6 or 0
			handle.Key.Inset.BackgroundTransparency = event.Enabled == false and 0.6 or 0
		end

		row.enable.ImageColor3 = event.Enabled ~= false and Color3.fromRGB(113, 255, 61)
			or Color3.fromRGB(58, 58, 58)
		local keep = {}
		for _, k in event.Subtitle.Keys do
			local f = k.Frame
			keep[f] = true
			local b = row.keys[f]
			if not b then
				b = diamond(row.container, "SubtitleKey" .. f)
				row.keys[f] = b
				table.insert(row.objects, b)
				b.InputBegan:Connect(function(input)
					begin(row, f, input)
				end)
			end

			b.Visible = true
			b.Position = UDim2.new(0, timeline:FrameToVisibleX(event.Frame + f), 0.5, 0)
			b.ImageColor3 = selection
					and selection.rig == row.rig
					and selection.id == row.id
					and selection.offset == f
					and Theme.get("KfS", Color3.new(1, 1, 1))
				or Theme.get("KfD", Color3.new(1, 1, 1))
		end

		for f, b in row.keys do
			if not keep[f] then
				b:Destroy()
				row.keys[f] = nil
				local index = table.find(row.objects, b)
				if index then
					table.remove(row.objects, index)
				end
			end
		end
	end
end

function Tracks.select(timeline, rig, id, offset)
	timeline:ClearSelectedKeyframes()
	selection = { rig = rig, id = id, offset = offset }
	timeline:UpdateDeleteButtonState()
	Tracks.refresh(timeline)
end

function Tracks.escape(timeline)
	if drag then
		drag.finish(true)
	end

	if selection then
		timeline:ClearSelectedKeyframes()
	end
end

function Tracks.contains(point)
	local function inside(object)
		if not object:IsA("GuiObject") then
			return false
		end

		if not Input.isGuiPointCompatible(object) then
			return false
		end

		local current = object
		while current do
			if current:IsA("GuiObject") then
				if not current.Visible then
					return false
				end

				if current == object or current.ClipsDescendants then
					local p, s = current.AbsolutePosition, current.AbsoluteSize
					if
						point.X < p.X
						or point.Y < p.Y
						or point.X > p.X + s.X
						or point.Y > p.Y + s.Y
					then
						return false
					end
				end
			elseif current:IsA("LayerCollector") and not current.Enabled then
				return false
			end

			current = current.Parent
		end

		return object.Parent ~= nil
	end

	for _, row in rows do
		if row.item.uiElement and inside(row.item.uiElement) then
			return true
		end

		for _, object in row.objects do
			if inside(object) then
				return true
			end
		end
	end

	return false
end

function Tracks.captureCopy()
	const event = selection and selection.rig.Parent and Events.get(selection.rig).Events[selection.id]
	if not event or not event.Subtitle then
		return nil
	end

	return {
		rig = selection.rig,
		id = selection.id,
		offset = selection.offset,
		cue = Data.copy(event.Subtitle),
	}
end

function Tracks.setClipboard(value)
	clipboard = value
end

function Tracks.install(Timeline)
	function Timeline:HasSelectedSubtitle()
		return selection ~= nil
	end

	local over = Timeline.IsPointOverEventUI

	function Timeline:IsPointOverEventUI(point, ...)
		return drag ~= nil or Tracks.contains(point) or over(self, point, ...)
	end

	for _, name in
		{
			"BeginKeyframeBoxSelection",
			"SetSelectedKeyframe",
			"SetSelectedChannelKeyframe",
			"SetSelectedKeyframes",
			"AddSelectedKeyframe",
			"ToggleSelectedKeyframe",
			"AddSelectedChannelKeyframe",
			"ToggleSelectedChannelKeyframe",
			"SelectAllKeyframes",
			"SelectEvent",
		}
	do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			if selection then
				selection = nil
				Tracks.refresh(self)
			end

			return original(self, ...)
		end
	end

	local paste = Timeline.PasteKeyframes

	function Timeline:PasteKeyframes(...)
		if not clipboard then
			return paste(self, ...)
		end

		local target = selection or clipboard
		local track = Events.all()[target.rig]
		if not track then
			require("Notification").show("PASTE SUBTITLE", "The copied subtitle's rig is no longer in this project.", 2, "KeyframeAction")
			return false
		end

		local frame = math.round(self:GetState().CurrentTime * self:GetState().FPS)
		if clipboard.offset then
			local event = track.Events[target.id]
			if not event or not event.Subtitle then
				require("Notification").show("PASTE SUBTITLE", "The subtitle this key was copied from no longer exists.", 2, "KeyframeAction")
				return false
			end

			local relative = frame - event.Frame
			if relative < 0 or relative >= event.Subtitle.Duration then
				require("Notification").show("PASTE SUBTITLE", "Move the playhead inside the subtitle to paste its key.", 2, "KeyframeAction")
				return false
			end

			return require("Subtitles").edit(track, target.id, function(c)
				local k = Data.key(c, relative)
				if k then
					k.Value = Data.style(Data.sample(clipboard.cue, clipboard.offset))
				end
			end, "Paste subtitle key")
		end

		local before = Events.snapshot(track)
		local event = Events.create(track, frame)
		event.Name = "Subtitle"
		event.Markers = {}
		event.Subtitle = Data.copy(clipboard.cue)
		Events.changed(track)
		self:RecordEventEdit(track, before, "Paste subtitle")
		self:RefreshEventRows()
		require("Subtitles").step()
		return true
	end

	local clear = Timeline.ClearSelectedKeyframes

	function Timeline:ClearSelectedKeyframes(...)
		selection = nil
		local result = clear(self, ...)
		Tracks.refresh(self)
		return result
	end

	local delete = Timeline.DeleteSelectedKeyframes

	function Timeline:DeleteSelectedKeyframes(...)
		if not selection then
			return delete(self, ...)
		end

		local s = selection
		selection = nil
		local track = Events.get(s.rig)
		if s.offset then
			require("Subtitles").edit(track, s.id, function(c)
				for i, k in c.Keys do
					if k.Frame == s.offset then
						table.remove(c.Keys, i)
						break
					end
				end
			end, "Delete subtitle key")
		else
			require("Subtitles").remove(track, s.id)
		end
	end

	local update = Timeline.UpdateDeleteButtonState

	function Timeline:UpdateDeleteButtonState(...)
		update(self, ...)
		local b = self:GetDeleteButton()
		if b and selection then
			b.Visible = true
		end
	end
end

return Tracks
