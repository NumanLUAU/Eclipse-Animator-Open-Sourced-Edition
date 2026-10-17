--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Drawings = require(script:FindFirstAncestor("Container").Shared.EclipseDrawing)
local Motion = require("Motion")
local UserInputService = require("UserInputService")
local HttpService = game:GetService("HttpService")
local Events = require("Events")
local Playback = require("EventPlayback")
local Editor = require("Editor")
local Icons = require("EventIcons")
local SoundData = require("SoundData")
local LegacyEvents = require("LegacyEvents")
local History = require("History")
local Theme = require("Theme")
local State = require("RawState")
local tl = State.Timeline
local selected, rows, clipboard = {}, {}, {}
local activeTimeline

local function inside(gui, point)
	if not gui or not gui.Parent then
		return false
	end

	if not UserInputService.isGuiPointCompatible(gui) then
		return false
	end

	local current = gui
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end

		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end

		current = current.Parent
	end

	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

local function modified()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

return function(Timeline)
	function Timeline:RecordEventEdit(track, before, description)
		local after = Events.snapshot(track)

		local function apply(snapshot)
			Editor.close(self)
			Events.restore(track, snapshot)
			table.clear(selected)
			self:RefreshEventRows()
			self:UpdateDeleteButtonState()
		end

		History.record(function()
			apply(before)
		end, function()
			apply(after)
		end, description)
	end

	function Timeline:DeleteEvent(track, id)
		Editor.close(self)
		local event = track and track.Events[id]
		if not event then
			return false
		end

		local before = Events.snapshot(track)
		track.Events[id] = nil
		selected[event] = nil
		Events.changed(track)
		self:RecordEventEdit(track, before, "Delete event")
		self:RefreshEventRows()
		self:UpdateDeleteButtonState()
		return true
	end

	function Timeline:GetSelectedEvents()
		local result = {}
		for event, track in selected do
			if track.Events[event.Id] == event then
				table.insert(result, { event = event, track = track })
			end
		end

		return result
	end

	function Timeline:SelectEvent(track, event, additive)
		if not additive then
			self:ClearSelectedKeyframes()
		end

		if additive and selected[event] then
			selected[event] = nil
		else
			selected[event] = track
		end

		self:RefreshEventRows()
		self:UpdateDeleteButtonState()
	end

	function Timeline:AddEvent(rig, frame, openEditor, anchor)
		Editor.close(self)
		local track = Events.get(rig)
		frame = math.max(0, math.round(frame))
		for _, existing in track.Events do
			if existing.Frame == frame then
				self:SelectEvent(track, existing, false)
				if openEditor then
					self:OpenEventEditor(track, existing.Id, anchor)
				end

				return existing
			end
		end

		local before = Events.snapshot(track)
		local event = Events.create(track, frame)
		self:RecordEventEdit(track, before, "Add event")
		self:SelectEvent(track, event, false)
		self:EnsureTimelineEnd(event.Frame)
		if openEditor then
			self:OpenEventEditor(track, event.Id, anchor)
		end

		return event
	end

	function Timeline:ImportLegacyEvents(source, rig)
		if LegacyEvents.isEmitTrack(source) then
			Events.vfxDisabled()
			return false
		end

		local entries = LegacyEvents.read(source, self:GetState().FPS)
		if not entries or not rig or not rig.Parent then
			return false
		end

		Editor.close(self)
		local track = Events.get(rig)
		local before = Events.snapshot(track)
		local existing = {}
		for _, event in track.Events do
			existing[LegacyEvents.fingerprint(event)] = true
		end

		local imported = {}
		local lastFrame = 0
		for _, entry in entries do
			local fingerprint = LegacyEvents.fingerprint(entry)
			if existing[fingerprint] then
				continue
			end

			local event = table.clone(entry)
			event.Id = HttpService:GenerateGUID(false)
			event.Frame = Events.nextFrame(track, event.Frame)
			track.Events[event.Id] = event
			existing[fingerprint] = true
			table.insert(imported, event)
			lastFrame = math.max(lastFrame, event.Frame + event.Duration)
		end

		if #imported == 0 then
			return true, 0
		end

		Playback.disable(rig)
		Events.changed(track)
		self:RecordEventEdit(track, before, "Import Moon events")
		self:ClearSelectedKeyframes()
		for _, event in imported do
			selected[event] = track
		end

		self:EnsureTimelineEnd(lastFrame)
		self:RefreshEventRows()
		self:UpdateDeleteButtonState()
		return true, #imported
	end

	function Timeline:OpenEventEditor(track, id, anchor)
		tl.Playing = false
		Playback.stop()
		local row = rows[track.Rig]
		local button = row and row.buttons[id]
		return Editor.open(self, track, id, anchor or button and button.AbsolutePosition)
	end

	function Timeline:CloseEventEditor()
		Editor.close(self)
	end

	function Timeline:EventFrameAtPoint(point)
		local scale = self.refs.Scale
		if not scale then
			return 0
		end

		local width = self:GetVisibleTimelineWidth()
		local pixelScale = scale.AbsoluteSize.X / math.max(1, width + 40)
		local origin = scale.AbsolutePosition.X + 20 * pixelScale
		const maxFrame = math.max(0, self:GetMaxFrame())
		const frame = math.floor((point.X - origin) / math.max(width * pixelScale, 1) * maxFrame + 0.5)
		if frame ~= frame then
			return 0
		end

		return math.clamp(frame, 0, maxFrame)
	end

	function Timeline:IsPointOverEventUI(point, allowEmptyLane)
		if require("Faces").contains(point, allowEmptyLane) then
			return true
		end

		local editor = require("State").GraphEditor
		if editor and (editor.isInteracting() or editor.containsPoint(point)) then
			return true
		end

		if self._eventEditor and inside(self._eventEditor.window, point) then
			return true
		end

		if self._eventDrag then
			return true
		end

		for _, row in rows do
			if inside(row.item.uiElement, point) then
				return true
			end

			if inside(row.hitbox, point) then
				if not allowEmptyLane then
					return true
				end

				for _, marker in row.buttons do
					if inside(marker, point) then
						return true
					end
				end
			end
		end

		return false
	end

	function Timeline:MoveSelectedEvents(offset)
		local groups, entries = {}, self:GetSelectedEvents()
		local minimum = math.huge
		for _, entry in entries do
			minimum = math.min(minimum, entry.event.Frame)
			entry.frame = entry.event.Frame
		end

		offset = math.max(-minimum, math.floor(offset + 0.5))
		if offset == 0 or minimum == math.huge then
			return
		end

		for _, entry in entries do
			groups[entry.track] = groups[entry.track] or Events.snapshot(entry.track)
		end

		for track, before in groups do
			Events.move(track, entries, offset)
			Events.changed(track)
			Playback.disable()
			self:RecordEventEdit(track, before, "Move events")
		end

		self:RefreshEventRows()
	end

	function Timeline:BindEventRow(item)
		activeTimeline = self
		local rig = item.grandpa.linkedRigInstance
		self:UnbindEventRow(rig)
		local track = Events.get(rig)
		local container = self:GetTrackKeyframesContainer(item.trackElement)
		if not container then
			return
		end

		local template = container:FindFirstChild("KeyframeTemplate")
		if template then
			template.Visible = false
		end

		local hitbox = Instance.new("TextButton")
		hitbox.Name = "EventHitbox"
		hitbox.Text = ""
		hitbox.Size = UDim2.fromScale(1, 1)
		hitbox.BackgroundTransparency = 1
		hitbox.BorderSizePixel = 0
		hitbox.ZIndex = 2
		hitbox.Parent = container
		local row = {
			item = item,
			container = container,
			hitbox = hitbox,
			buttons = {},
			connections = {},
			lastClick = 0,
		}
		rows[rig] = row
		local right = item.appearDetails.RightDiv
		local enabled = right:FindFirstChild("Disable")
		for _, button in right:GetChildren() do
			if button:IsA("GuiButton") then
				button.Visible = button == enabled
			end
		end

		local add = Instance.new("TextButton")
		add.Name = "AddEvent"
		add.Text = "+"
		add.Font = Enum.Font.GothamMedium
		add.TextSize = 17
		add.TextColor3 = Color3.fromRGB(216, 200, 233)
		add.BackgroundTransparency = 1
		add.BorderSizePixel = 0
		add.Size = enabled and enabled.Size or UDim2.fromOffset(18, 18)
		add.LayoutOrder = -2
		add.Parent = right
		add:SetAttribute("ThemeTxt", "Txt")
		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.Parent = add
		item.disableButton, item.addEventButton = enabled, add
		table.insert(
			row.connections,
			add.MouseButton1Click:Connect(function()
				self:AddEvent(rig, self:TimeToFrame(self:GetState().CurrentTime), true)
			end)
		)
		if enabled then
			table.insert(
				row.connections,
				enabled.MouseButton1Click:Connect(function()
					Editor.close(self)
					local current = Events.get(rig)
					local before = Events.snapshot(current)
					current.Enabled = not current.Enabled
					if not current.Enabled then
						Playback.disable(rig)
					end

					Events.changed(current)
					self:RecordEventEdit(current, before, "Toggle events")
					self:RefreshEventRows()
				end)
			)
		end

		table.insert(
			row.connections,
			hitbox.MouseButton1Click:Connect(function()
				if self._selectionDragConsumed then
					row.lastClick = 0
					return
				end

				local now = os.clock()
				local point = UserInputService:GetMouseLocation()
				local frame = self:EventFrameAtPoint(point)
				if
					now - row.lastClick <= 0.32
					and math.abs(frame - (row.lastFrame or -100)) <= 1
				then
					row.lastClick = 0
					self:AddEvent(rig, frame, true, point)
				else
					row.lastClick, row.lastFrame = now, frame
					if not modified() then
						self:ClearSelectedKeyframes()
					end
				end
			end)
		)
		self:RefreshEventRows()
	end

	function Timeline:UnbindEventRow(rig)
		local row = rows[rig]
		if not row then
			return
		end

		for _, connection in row.connections do
			connection:Disconnect()
		end

		rows[rig] = nil
	end

	function Timeline:BeginEventDrag(track, event, point)
		local row = rows[track.Rig]
		local now = os.clock()
		local double = row and row.lastEvent == event.Id and now - (row.lastEventClick or 0) <= 0.32
		if row then
			row.lastEvent, row.lastEventClick = event.Id, now
		end

		if double then
			self:SelectEvent(track, event, false)
			self:OpenEventEditor(track, event.Id)
			return
		end

		if modified() or not selected[event] then
			self:SelectEvent(track, event, modified())
		end

		if not selected[event] then
			return
		end

		local entries, snapshots = {}, {}
		for _, entry in self:GetSelectedEvents() do
			table.insert(
				entries,
				{ event = entry.event, track = entry.track, frame = entry.event.Frame }
			)
			snapshots[entry.track] = snapshots[entry.track] or Events.snapshot(entry.track)
		end

		local minimum, maximum = math.huge, -math.huge
		for _, entry in entries do
			minimum = math.min(minimum, entry.frame)
			maximum = math.max(maximum, entry.frame)
		end

		const limit = math.max(self:GetMaxFrame(), maximum)
		local drag = { point = point, entries = entries, snapshots = snapshots, changed = false }
		self._eventDrag = drag
		local moveConnection, endConnection

		local function finish()
			moveConnection:Disconnect()
			endConnection:Disconnect()
			self._eventDrag = nil
			if drag.changed then
				for current, before in snapshots do
					Events.changed(current)
					self:RecordEventEdit(current, before, "Move events")
				end

				self:RefreshEventRows()
			end
		end

		moveConnection = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end

			local currentPoint = UserInputService:GetMouseLocation()
			if not drag.changed and (currentPoint - point).Magnitude < 3 then
				return
			end

			local scale = self.refs.Scale
			local width = self:GetVisibleTimelineWidth()
			local pixelScale = scale.AbsoluteSize.X / math.max(1, width + 40)
			local offset = math.floor(
				(currentPoint.X - point.X) / math.max(width * pixelScale, 1) * limit
					+ 0.5
			)
			offset = math.max(-minimum, math.min(offset, limit - maximum))
			for current in snapshots do
				Events.move(current, entries, offset)
			end

			Playback.disable()
			drag.changed = true
			self:RefreshEventRows()
		end)
		endConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				finish()
			end
		end)
		drag.finish = finish
	end

	function Timeline:RefreshEventRows()
		require("EventTrackList").refresh(self)
		require("Faces").refresh(self)
		local last = Events.lastFrame(false)
		if last and last > self:GetMaxFrame() then
			self:EnsureTimelineEnd(last)
		end

		for rig, row in rows do
			local track = Events.get(rig)
			local button = row.item.disableButton
			if button then
				row.item.disabled = track.Enabled == false
				row.item:_repaintDisable()
			end

			for id, marker in row.buttons do
				if not track.Events[id] then
					marker:Destroy()
					row.buttons[id] = nil
				end
			end

			for id, event in track.Events do
				if
					event.Subtitle
					and #Events.markers(event) == 0
					and #(event.Emits or {}) == 0
					and not SoundData.has(event.Sounds)
					and event.CodeBegin == ""
					and event.CodeEnd == ""
				then
					if row.buttons[id] then
						row.buttons[id]:Destroy()
						row.buttons[id] = nil
					end

					continue
				end

				local marker = row.buttons[id]
				if not marker then
					marker = Instance.new("ImageButton")
					marker.Name = "Event_" .. id
					marker.Image = ""
					marker.BackgroundTransparency = 1
					marker.Size = UDim2.fromOffset(16, 16)
					marker.AnchorPoint = Vector2.new(0.5, 0.5)
					marker.ZIndex = 4
					marker.AutoButtonColor = false
					Icons.attach(marker, "event")
					marker.Parent = row.container
					row.buttons[id] = marker
					marker.InputBegan:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							and inside(marker, UserInputService:GetMouseLocation())
						then
							local current = Events.get(rig)
							if current.Events[id] then
								self:BeginEventDrag(
									current,
									current.Events[id],
									UserInputService:GetMouseLocation()
								)
							end
						end
					end)
					marker.MouseEnter:Connect(function()
						if not selected[track.Events[id]] then
							marker.ImageColor3 = Theme.get("KfH", State.Colors.KEYFRAME_HOVER_COLOR)
						end
					end)
					marker.MouseLeave:Connect(function()
						self:RefreshEventRows()
					end)
				end

				marker.ZIndex = 10 + math.max(0, math.floor(event.Frame))
				marker.Position = UDim2.new(0, self:FrameToVisibleX(event.Frame), 0.5, 0)
				marker.ImageColor3 = selected[event]
						and Theme.get("KfS", State.Colors.KEYFRAME_SELECTED_COLOR)
					or Theme.get("KfD", State.Colors.KEYFRAME_DEFAULT_COLOR)
				marker.ImageTransparency = track.Enabled and event.Enabled ~= false and 0 or 0.6
			end
		end
	end

	local clearSelection = Timeline.ClearSelectedKeyframes

	function Timeline:ClearSelectedKeyframes()
		table.clear(selected)
		clearSelection(self)
		self:RefreshEventRows()
	end

	for _, name in { "SetSelectedKeyframe", "SetSelectedKeyframes", "SetSelectedChannelKeyframe" } do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			table.clear(selected)
			original(self, ...)
			self:RefreshEventRows()
		end
	end

	local selectAll = Timeline.SelectAllKeyframes

	function Timeline:SelectAllKeyframes()
		selectAll(self)
		table.clear(selected)
		for _, track in Events.all() do
			for _, event in track.Events do
				selected[event] = track
			end
		end

		self:RefreshEventRows()
		self:UpdateDeleteButtonState()
	end

	local updateDelete = Timeline.UpdateDeleteButtonState

	function Timeline:UpdateDeleteButtonState()
		updateDelete(self)
		local button = self:GetDeleteButton()
		if button and next(selected) then
			button.Visible = true
		end
	end

	local deleteKeys = Timeline.DeleteSelectedKeyframes

	function Timeline:DeleteSelectedKeyframes()
		Editor.close(self)
		local targets, snapshots = self:GetSelectedEvents(), {}
		deleteKeys(self)
		for _, entry in targets do
			local track = entry.track
			snapshots[track] = snapshots[track] or Events.snapshot(track)
			Playback.disable(track.Rig)
			track.Events[entry.event.Id] = nil
		end

		table.clear(selected)
		for track, before in snapshots do
			Events.changed(track)
			self:RecordEventEdit(track, before, "Delete events")
		end

		self:RefreshEventRows()
		self:UpdateDeleteButtonState()
	end

	local copiedExtras = false

	local function storeEvents(entries, base)
		table.clear(clipboard)
		for _, entry in entries do
			table.insert(clipboard, {
				rig = entry.track.Rig,
				data = Events.snapshot({ Events = { [entry.event.Id] = entry.event } }).Events[entry.event.Id],
				offset = entry.event.Frame - base,
			})
		end
	end

	local function copyEvents(timeline, entries, motorBase)
		table.clear(clipboard)
		local base = motorBase
		for _, entry in entries do
			base = math.min(base, entry.event.Frame)
		end

		if base == math.huge then
			return false
		end

		for _, copied in tl._KeyframeClipboard or {} do
			copied.offsetFrame += motorBase - base
		end

		storeEvents(entries, base)
		return #clipboard > 0, base
	end

	local copyAll = Timeline.CopyAllKeyframes

	function Timeline:CopyAllKeyframes()
		local minimum, entries = math.huge, {}
		for _, bucket in tl.Keyframes do
			for _, key in bucket do
				minimum = math.min(minimum, key.Frame)
			end
		end

		for _, track in Events.all() do
			for _, event in track.Events do
				table.insert(entries, { track = track, event = event })
			end
		end

		local count = copyAll(self)
		if count == 0 and #entries == 0 then
			return 0
		end

		if count == 0 then
			tl._KeyframeClipboard = {}
		end

		copyEvents(self, entries, minimum)
		return count + #clipboard
	end

	local pasteKeys = Timeline.PasteKeyframes
	local pasteFlipped = Timeline.PasteKeyframesFlipped

	local function paste(self, flipped, reverse, selectedTarget)
		Editor.close(self)
		local span = 0
		for _, entry in tl._KeyframeClipboard or {} do
			span = math.max(span, entry.offsetFrame)
		end
		for _, entry in clipboard do
			span = math.max(span, entry.offset + (entry.data.Duration or 0))
		end
		local result
		if #(tl._KeyframeClipboard or {}) == 0 then
			result = false
			if #clipboard == 0 and not copiedExtras then
				require("Notification").show(
					"PASTE KEYS",
					"Nothing is copied yet. Select keys and press " .. require("Shortcuts").format("Copy") .. " first.",
					3,
					"KeyframeAction"
				)
			end
		elseif flipped then
			result = pasteFlipped(self, selectedTarget)
		else
			result = pasteKeys(self, reverse, selectedTarget, #clipboard > 0 and span or nil)
		end
		local snapshots, pasted = {}, {}
		local anchor = self:TimeToFrame(tl.CurrentTime)
		for _, entry in clipboard do
			local track = Events.all()[entry.rig]
			if not track then
				continue
			end

			snapshots[track] = snapshots[track] or Events.snapshot(track)
			local event = table.clone(entry.data)
			event.Sounds = SoundData.copy(entry.data.Sounds)
			event.Emits = require("ClipboardRows").copy(entry.data.Emits)
			event.Subtitle = require("SubtitleData").copy(entry.data.Subtitle)
			event.Markers = Events.markers(entry.data)
			event.Id, event.Frame =
				HttpService:GenerateGUID(false), Events.nextFrame(track, anchor + (reverse and span - entry.offset - (event.Duration or 0) or entry.offset))
			track.Events[event.Id] = event
			pasted[event] = track
		end

		if next(pasted) then
			table.clear(selected)
			for event, track in pasted do
				selected[event] = track
			end

			for track, before in snapshots do
				Events.changed(track)
				self:RecordEventEdit(track, before, "Paste events")
			end

			self:RefreshEventRows()
			self:UpdateDeleteButtonState()
			return true
		end

		return result
	end

	function Timeline:PasteKeyframes(reverse, selectedTarget)
		return History.batch(reverse and "Paste reversed" or "Paste keys", function()
			return paste(self, false, reverse, selectedTarget)
		end)
	end

	function Timeline:PasteKeyframesFlipped(selectedTarget)
		return History.batch("Paste flipped", function()
			return paste(self, true, false, selectedTarget)
		end)
	end

	local beginBox = Timeline.BeginKeyframeBoxSelection

	function Timeline:BeginKeyframeBoxSelection(additive)
		self._selectionBaseEvents = additive and table.clone(selected) or {}
		if not additive then
			table.clear(selected)
		end

		beginBox(self, additive)
		self:RefreshEventRows()
	end

	local boxSelect = Timeline.SelectKeyframesInSelectionBox

	function Timeline:SelectKeyframesInSelectionBox(point)
		local changed = boxSelect(self, point)
		local previous = selected
		selected = table.clone(self._selectionBaseEvents or {})
		local minX, minY, maxX, maxY = self:GetSelectionBounds(point)
		local scale = self.refs.Scale
		if minX and scale then
			for rig, row in rows do
				local track = Events.get(rig)
				for id, marker in row.buttons do
					local center = marker.AbsolutePosition + marker.AbsoluteSize * 0.5
					local p = (center - scale.AbsolutePosition) / Motion.scale(scale)
					if
						inside(marker, center)
						and p.X >= minX
						and p.X <= maxX
						and p.Y >= minY
						and p.Y <= maxY
					then
						selected[track.Events[id]] = track
					end
				end
			end
		end

		local eventChanged = false
		for event in selected do
			if not previous[event] then
				eventChanged = true
				break
			end
		end

		if not eventChanged then
			for event in previous do
				if not selected[event] then
					eventChanged = true
					break
				end
			end
		end

		if eventChanged then
			self:RefreshEventRows()
		end

		if changed or eventChanged then
			self:UpdateDeleteButtonState()
		end
	end

	for _, name in
		{
			"RefreshTimelineScale",
			"RebuildAllTimelineKeyframeButtons",
			"RefreshAllKeyframeVisuals",
		}
	do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			local result = original(self, ...)
			self:RefreshEventRows()
			return result
		end
	end

	local hasKeys = Timeline.HasAnyKeyframes

	function Timeline:HasAnyKeyframes()
		return hasKeys(self)
			or Events.lastFrame(false) ~= nil
			or tl.GreaseDrawings and #tl.GreaseDrawings.layers > 0
			or false
	end

	local lastFrame = Timeline.GetLastKeyframeFrame

	local function playableEventSpan()
		const Organization = require("Organization")
		local last
		for _, track in Events.all() do
			const trackEnabled = Events.isEnabled(track)
			const rigEnabled = trackEnabled or Organization.isEnabled(track.Rig)
			for _, event in track.Events do
				if event.Enabled == false or not rigEnabled then
					continue
				end

				local span = event.Subtitle and event.Subtitle.Duration or 0
				if trackEnabled then
					span = math.max(span, event.Duration or 0)
				elseif not event.Subtitle then
					continue
				end

				last = math.max(last or 0, event.Frame + span)
			end
		end

		return last
	end

	function Timeline:GetLastKeyframeFrame(playback)
		const playable = playback == true
		local key, event = lastFrame(self), Events.lastFrame(playable, playable)
		if playable then
			const span = playableEventSpan()
			if span then
				event = math.max(event or 0, span)
			end
		end
		if tl.GreaseDrawings and #tl.GreaseDrawings.layers > 0 then
			key = math.max(key or 0, Drawings.lastFrame(tl.GreaseDrawings))
		end

		if key == nil then
			return event
		end

		return math.max(key, event or 0)
	end

	local allFrames = Timeline.GetAllKeyframeFrames

	function Timeline:GetAllKeyframeFrames()
		local result, included = allFrames(self), {}
		for _, frame in result do
			included[frame] = true
		end

		for _, track in Events.all() do
			for _, event in track.Events do
				if not included[event.Frame] then
					table.insert(result, event.Frame)
					included[event.Frame] = true
				end

				for _, key in event.Subtitle and event.Subtitle.Keys or {} do
					local f = event.Frame + key.Frame
					if not included[f] then
						included[f] = true
						table.insert(result, f)
					end
				end
			end
		end

		table.sort(result)
		return result
	end

	local clear = Timeline.ClearTimelineData

	function Timeline:ClearTimelineData()
		require("EventTrackList").clear()
		require("Faces").clear()
		Editor.close(self)
		if self._eventDrag then
			self._eventDrag.finish()
		end

		Playback.clear()
		for rig in rows do
			self:UnbindEventRow(rig)
		end

		table.clear(selected)
		Events.clear()
		clear(self)
	end

	local function groupHistory(action)
		return History.batch(nil, action)
	end

	for _, name in
		{
			"DeleteSelectedKeyframes",
			"CutSelectedKeyframes",
			"PasteKeyframes",
			"MoveSelectedEvents",
		}
	do
		local action = Timeline[name]
		Timeline[name] = function(self, ...)
			Editor.close(self)
			local args = table.pack(...)
			return groupHistory(function()
				return action(self, table.unpack(args, 1, args.n))
			end)
		end
	end

	Theme.onChanged(function()
		if next(rows) and activeTimeline then
			activeTimeline:RefreshEventRows()
		end
	end)

	require("Faces").install(Timeline)
	require("EventTrackList").install(Timeline)

	function Timeline:CopySelectedKeyframes()
		const Faces, Tracks = require("Faces"), require("EventTrackList")
		const keys, keyBase = self:CaptureSelectedKeyframes()
		const events = self:GetSelectedEvents()
		const faces = Faces.captureCopy()
		local base = keys and keyBase or math.huge
		for _, entry in events do
			base = math.min(base, entry.event.Frame)
		end

		for _, entry in faces do
			base = math.min(base, entry.frame)
		end

		if base == math.huge then
			const subtitle = Tracks.captureCopy()
			if not subtitle then
				require("Notification").show(
					"COPY",
					"Nothing is selected to copy. Your previous copy is still on the clipboard.",
					2,
					"KeyframeAction"
				)
				return false
			end

			tl._KeyframeClipboard = nil
			table.clear(clipboard)
			Faces.setClipboard(nil)
			Tracks.setClipboard(subtitle)
			copiedExtras = true
			return true
		end

		for _, entry in keys or {} do
			entry.offsetFrame += keyBase - base
		end

		Tracks.setClipboard(nil)
		tl._KeyframeClipboard = keys or {}
		storeEvents(events, base)
		Faces.setClipboard(faces, base)
		copiedExtras = next(faces) ~= nil
		return true, base
	end
end
