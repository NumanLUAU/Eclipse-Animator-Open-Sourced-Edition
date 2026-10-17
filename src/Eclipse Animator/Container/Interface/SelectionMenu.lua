--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Outline = require("Outline")
local Model = require("KeyGroups")
local Raw = require("RawState")
local State = require("State")
local History = require("History")
local Menu = require("KeyframeMenu")
local Input = require("UserInputService")
local BlenderEdit = require("BlenderEdit")
local Http = game:GetService("HttpService")
local POSE = Model.POSE
local raw = Raw.Timeline

local function snapshot(motors)
	local result = {}
	for motor in motors do
		local track = {}
		result[motor] = track
		for frame, key in raw.Keyframes[motor] or {} do
			track[frame] = Model.clone(key.KeyGroups) or false
		end
	end

	return result
end

local function restore(self, data)
	for motor, track in data do
		for frame, key in raw.Keyframes[motor] or {} do
			key.KeyGroups = Model.clone(track[frame])
		end
	end

	State.currentProjectSaved = false
	self:RefreshAllKeyframeVisuals()
end

local function selectedTracks()
	local tracks = {}

	local function add(key, lane)
		local motor = key.Motor

		if not motor or not raw.Keyframes[motor] or raw.Keyframes[motor][key.Frame] ~= key then
			return
		end

		tracks[motor] = tracks[motor] or {}
		tracks[motor][lane] = tracks[motor][lane] or {}
		tracks[motor][lane][key] = true
	end

	for key in raw.SelectedKeyframes do
		add(key, POSE)
	end

	for key, lanes in raw.SelectedChannelKeyframes do
		if not raw.SelectedKeyframes[key] then
			for lane in lanes do
				add(key, lane)
			end
		end
	end

	return tracks
end

local function busy(self)
	return BlenderEdit.blocked()
		or Raw.KeyframeDrag.draggingKeyframe ~= nil
		or (self.IsBlenderKeyframeTransformActive and self:IsBlenderKeyframeTransformActive())
end

return function(Timeline)
	local clearTimeline = Timeline.ClearTimelineData

	function Timeline:ClearTimelineData(...)
		local result = clearTimeline(self, ...)
		self._viewportRefreshQueued = nil
		self._keyGroupsRefreshQueued = nil
		if self._viewportLayoutConnection then
			self._viewportLayoutConnection:Disconnect()
		end

		self._viewportLayoutConnection = nil
		self._viewportLayoutPane = nil
		self._keyViewport = nil
		self._keyViewportIndex = nil
		self._viewportBulk = nil
		self:RestoreGroupedButtons()
		for _, groups in self._keyGroupBars or {} do
			for _, entry in groups do
				entry.bar:Destroy()
			end
		end

		self._keyGroupBars = nil
		self._groupsByKey = nil
		self._groupedMotors = nil
		self._expandedKeyGroups = nil
		self._compactKeyDrag = nil
		self._selectionHitTargets = nil
		return result
	end

	function Timeline:InvalidateKeyframeViewportLayout()
		self._keyViewportLayoutRevision = (self._keyViewportLayoutRevision or 0) + 1
		self:QueueKeyframeViewportRefresh()
	end

	function Timeline:PrepareKeyframeViewport(force)
		if not force and (self._refreshingKeyGroups or self._viewportBulk) then
			return
		end

		local pane = self.refs and self.refs.KeysRoot
		if not pane then
			self._keyViewport = nil
			return
		end

		if pane.AbsoluteSize.X <= 0 or pane.AbsoluteSize.Y <= 0 then
			self._keyViewport = { visible = {}, groups = {}, containers = {}, pending = true }
			if self._viewportLayoutConnection and self._viewportLayoutPane ~= pane then
				self._viewportLayoutConnection:Disconnect()
				self._viewportLayoutConnection = nil
			end

			if not self._viewportLayoutConnection then
				self._viewportLayoutPane = pane
				self._viewportLayoutConnection = pane:GetPropertyChangedSignal("AbsoluteSize")
					:Connect(function()
						if pane.AbsoluteSize.X > 0 and pane.AbsoluteSize.Y > 0 then
							self._viewportLayoutConnection:Disconnect()
							self._viewportLayoutConnection = nil
							self:QueueKeyframeViewportRefresh()
						end
					end)
			end

			return
		end

		if busy(self) and self._keyViewport then
			return
		end

		local revision = require("cache").revision()
		local width, maximum = self:GetVisibleTimelineWidth(), self:GetMaxFrame()
		local scale = require("Motion").scale(pane)
		local left, right =
			raw.ScrollOffset - 128, raw.ScrollOffset + self:GetTimelineViewportWidth() + 128
		local top, bottom =
			pane.AbsolutePosition.Y - 96 * scale,
			pane.AbsolutePosition.Y + pane.AbsoluteSize.Y + 96 * scale
		local old = self._keyViewport
		local layoutRevision = self._keyViewportLayoutRevision or 0
		if
			not force
			and old
			and not old.pending
			and old.revision == revision
			and old.keys == raw.Keyframes
			and old.layoutRevision == layoutRevision
			and old.channels == raw.ChannelTracks
			and old.rows == raw.TrackRows
			and old.width == width
			and old.maximum == maximum
			and old.scale == scale
			and old.paneSize == pane.AbsoluteSize
			and old.panePosition == pane.AbsolutePosition
			and math.abs(old.canvas.Y - pane.CanvasPosition.Y) < 48 * scale
			and math.abs(old.left - left) < 64
		then
			return
		end

		local index = self._keyViewportIndex
		if force or not index or index.keys ~= raw.Keyframes or index.revision ~= revision then
			index = { keys = raw.Keyframes, revision = revision, tracks = {} }
			self._keyViewportIndex = index
			for motor, bucket in raw.Keyframes do
				local track = { ordered = {}, authored = {} }
				index.tracks[motor] = track
				for _, key in bucket do
					table.insert(track.ordered, key)
					if key.KeyGroups then
						track.authored[key] = true
					end
				end

				table.sort(track.ordered, function(a, b)
					return a.Frame < b.Frame
				end)
			end
		end

		if
			not force
			and old
			and old.revision == revision
			and old.keys == raw.Keyframes
			and old.width == width
			and old.maximum == maximum
			and old.left == left
			and old.right == right
			and old.top == top
			and old.bottom == bottom
			and old.canvas == pane.CanvasPosition
			and old.rows == raw.TrackRows
			and old.layoutRevision == layoutRevision
			and old.channels == raw.ChannelTracks
		then
			return
		end

		local view = {
			layoutRevision = layoutRevision,
			channels = raw.ChannelTracks,
			revision = revision,
			keys = raw.Keyframes,
			width = width,
			maximum = maximum,
			left = left,
			right = right,
			top = top,
			bottom = bottom,
			canvas = pane.CanvasPosition,
			rows = raw.TrackRows,
			visible = {},
			groups = {},
			containers = {},
			jobs = {},
			scale = scale,
			paneSize = pane.AbsoluteSize,
			panePosition = pane.AbsolutePosition,
		}
		self._keyViewport = view

		local function visibleRow(row)
			if not row or not row.Parent then
				return false
			end

			local node = row
			while node and node ~= pane do
				if node:IsA("GuiObject") and not node.Visible then
					return false
				end

				node = node.Parent
			end

			if node ~= pane then
				return false
			end

			local y = row.AbsolutePosition.Y
			return y + row.AbsoluteSize.Y >= top and y <= bottom
		end

		for motor, bucket in raw.Keyframes do
			local lanes = { [POSE] = raw.TrackRows[motor.Part1] }
			for lane, row in raw.ChannelTracks[motor] or {} do
				lanes[lane] = row
			end

			for lane, row in lanes do
				if not visibleRow(row) then
					continue
				end

				local container = self:GetTrackKeyframesContainer(row)
				if not container then
					continue
				end

				view.containers[container] = true
				local bins = {}
				local ordered = index.tracks[motor].ordered
				local firstFrame = math.floor(left / 64) * 64 / width * maximum
				local lastFrame = math.ceil(right / 64) * 64 / width * maximum
				local lo, hi = 1, #ordered + 1
				while lo < hi do
					local mid = math.floor((lo + hi) / 2)
					if ordered[mid].Frame < firstFrame then
						lo = mid + 1
					else
						hi = mid
					end
				end

				for i = lo, #ordered do
					local key = ordered[i]
					local frame = key.Frame
					if frame >= lastFrame then
						break
					end

					local x = maximum > 0 and frame / maximum * width or 0
					if x < math.floor(left / 64) * 64 or x >= math.ceil(right / 64) * 64 then
						continue
					end

					if
						not Model.hasLane(key, lane)
						or lane == POSE
							and not require("GraphCurves").hasVisibleKey(bucket, key)
					then
						continue
					end

					view.visible[key] = view.visible[key] or {}
					view.visible[key][lane] = true
					view.jobs[motor] = view.jobs[motor] or {}
					view.jobs[motor][key] = true

					if
						Model.get(key, lane)
						and not (
							self._expandedKeyGroups
							and self._expandedKeyGroups[Model.get(key, lane)]
						)
					then
						continue
					end

					local bin = math.floor(x / 64)
					bins[bin] = bins[bin] or {}
					table.insert(bins[bin], key)
				end

				for key in index.tracks[motor].authored do
					view.jobs[motor] = view.jobs[motor] or {}
					view.jobs[motor][key] = true
				end

				for bin, members in bins do
					if #members <= 10 then
						continue
					end

					for _, key in members do
						view.groups[key] = view.groups[key] or {}
						view.groups[key][lane] = "@dense:" .. lane .. ":" .. bin
					end
				end
			end
		end
	end

	function Timeline:KeyframeInViewport(key, lane)
		local view = self._keyViewport
		return not view or view.visible[key] and view.visible[key][lane] == true
	end

	function Timeline:DisplayKeyGroup(key, lane)
		local view = self._keyViewport
		return view and view.groups[key] and view.groups[key][lane] or Model.get(key, lane)
	end

	function Timeline:ZoomDenseKeyGroup(entry)
		local zoom = self.timelineZoom
		if not zoom then
			return
		end

		local first, last = entry.members[1].frame, entry.members[#entry.members].frame
		local span = math.max(1, last - first)
		local desired = self:GetTimelineViewportWidth()
			* 0.75
			* self:GetMaxFrame()
			/ span
			/ self:GetBaseTimelineWidth()
		zoom.zoomScale = math.clamp(
			math.max(zoom:GetZoom() * 2, desired),
			zoom.minimum and zoom.minimum() or 1,
			zoom.maxZoom
		)
		zoom:Apply()
		self:SetTimelineScroll(
			self:FrameToVisibleX((first + last) / 2) - self:GetTimelineViewportWidth() / 2
		)
		self:RefreshKeyframeGroups()
	end

	function Timeline:QueueKeyframeViewportRefresh()
		if self._viewportRefreshQueued then
			return
		end

		local ticket = {}
		self._viewportRefreshQueued = ticket
		task.defer(function()
			while
				self._viewportRefreshQueued == ticket
				and (raw._ImportingKeyframes or self._refreshingKeyGroups)
			do
				task.wait()
			end

			if self._viewportRefreshQueued ~= ticket then
				return
			end

			self._viewportRefreshQueued = nil
			if self.refs and self.refs.KeysRoot and self.refs.KeysRoot.Parent then
				self:RefreshKeyframeGroups(nil, true)
			end
		end)
	end

	function Timeline:IsKeyGroupCollapsed(key, lane)
		local id = self:DisplayKeyGroup(key, lane)
		if id and id:sub(1, 7) == "@dense:" then
			return true
		end

		return id ~= nil and not (self._expandedKeyGroups and self._expandedKeyGroups[id])
	end

	function Timeline:GroupSelectedKeyframes()
		if busy(self) then
			return 0
		end

		local tracks, plans, motors = selectedTracks(), {}, {}
		for motor, lanes in tracks do
			for lane, selected in lanes do
				local members = Model.range(raw.Keyframes[motor], selected, lane)
				if #members > 1 then
					table.insert(plans, { lane = lane, members = members })
					motors[motor] = true
				end
			end
		end

		if #plans == 0 then
			return 0
		end

		local before = snapshot(motors)
		for _, plan in plans do
			local id = Http:GenerateGUID(false)
			for _, member in plan.members do
				Model.set(member.key, plan.lane, id)
			end
		end

		local after = snapshot(motors)
		State.currentProjectSaved = false
		self:RefreshAllKeyframeVisuals()
		History.record(function()
			restore(self, before)
		end, function()
			restore(self, after)
		end, "Group keyframes")
		return #plans
	end

	function Timeline:UngroupSelectedKeyframes(all)
		if busy(self) then
			return 0
		end

		local tracks, wanted, motors = selectedTracks(), {}, {}
		for motor, bucket in raw.Keyframes do
			local lanes = tracks[motor] or {}
			for _, key in bucket do
				for lane, id in key.KeyGroups or {} do
					if all or (lanes[lane] and lanes[lane][key]) then
						wanted[motor] = wanted[motor] or {}
						wanted[motor][lane] = wanted[motor][lane] or {}
						wanted[motor][lane][id] = true
						motors[motor] = true
					end
				end
			end
		end

		if not next(motors) then
			return 0
		end

		local before, count = snapshot(motors), 0
		for motor, lanes in wanted do
			for _, ids in lanes do
				for _ in ids do
					count += 1
				end
			end

			for _, key in raw.Keyframes[motor] do
				for lane, ids in lanes do
					if ids[Model.get(key, lane)] then
						Model.set(key, lane, nil)
					end
				end
			end
		end

		local after = snapshot(motors)
		State.currentProjectSaved = false
		self:RefreshAllKeyframeVisuals()
		History.record(function()
			restore(self, before)
		end, function()
			restore(self, after)
		end, all and "Ungroup all keyframes" or "Ungroup keyframes")
		return count
	end

	function Timeline:ExpandSelectedKeyframeGroups()
		if busy(self) then
			return
		end

		self._expandedKeyGroups = self._expandedKeyGroups or {}
		for _, lanes in selectedTracks() do
			for lane, selected in lanes do
				for key in selected do
					local id = Model.get(key, lane)
					if id then
						self._expandedKeyGroups[id] = true
					end
				end
			end
		end

		self:RefreshAllKeyframeVisuals()
	end

	function Timeline:RegroupKeyframes()
		self._expandedKeyGroups = {}
		self:RefreshAllKeyframeVisuals()
	end

	function Timeline:AdoptKeyIntoGroups(motor, key)
		local bucket = raw.Keyframes[motor]
		if not bucket or not key then
			return
		end

		local lanes = {}
		for _, candidate in bucket do
			for lane in candidate.KeyGroups or {} do
				lanes[lane] = true
			end
		end

		for lane in lanes do
			if Model.get(key, lane) or not Model.hasLane(key, lane) then
				continue
			end

			for id, members in Model.collect(bucket, lane) do
				if key.Frame > members[1].frame and key.Frame < members[#members].frame then
					Model.set(key, lane, id)
					break
				end
			end
		end
	end

	function Timeline:ConstrainGroupedDrag(delta, entries)
		local first, last, grouped = math.huge, -math.huge, false
		for _, entry in entries do
			local key, lane = entry.keyData, entry.channelId or POSE
			local id = Model.get(key, lane)
			grouped = grouped
				or (id ~= nil and not (self._expandedKeyGroups and self._expandedKeyGroups[id]))
			first, last = math.min(first, entry.originalFrame), math.max(last, entry.originalFrame)
		end

		if #entries == 0 then
			return delta
		end

		if not grouped and #entries == 1 then
			return delta
		end

		delta = math.clamp(delta, -first, self:GetMaxFrame() - last)
		return delta
	end

	function Timeline:ExpandGroupedSelection()
		for motor, lanes in selectedTracks() do
			for lane, selected in lanes do
				for id, members in Model.collect(raw.Keyframes[motor], lane) do
					if self._expandedKeyGroups and self._expandedKeyGroups[id] then
						continue
					end

					local hit = false
					for _, member in members do
						if selected[member.key] then
							hit = true
							break
						end
					end

					if not hit then
						continue
					end

					for _, member in members do
						if lane == POSE then
							raw.SelectedKeyframes[member.key] = true
						else
							raw.SelectedChannelKeyframes[member.key] = raw.SelectedChannelKeyframes[member.key]
								or {}
							raw.SelectedChannelKeyframes[member.key][lane] = true
						end
					end
				end
			end
		end
	end

	local function selectGroup(self, entry, additive)
		local first = entry.members[1].key
		local alreadySelected = entry.lane == POSE and raw.SelectedKeyframes[first]
			or entry.lane ~= POSE
				and raw.SelectedChannelKeyframes[first]
				and raw.SelectedChannelKeyframes[first][entry.lane]
		if not additive and not alreadySelected then
			table.clear(raw.SelectedKeyframes)
			table.clear(raw.SelectedChannelKeyframes)
		end

		for _, member in entry.members do
			if entry.lane == POSE then
				raw.SelectedKeyframes[member.key] = true
			else
				raw.SelectedChannelKeyframes[member.key] = raw.SelectedChannelKeyframes[member.key]
					or {}
				raw.SelectedChannelKeyframes[member.key][entry.lane] = true
			end
		end

		raw.SelectedKeyframe = entry.members[1].key
		self:RefreshKeyframeSelectionVisuals()
		self:UpdateDeleteButtonState()
		if self.refs and self.refs.RefreshSelectionFilter then
			self.refs.RefreshSelectionFilter()
		end
	end

	local function createBar(self, container)
		local bar = Instance.new("TextButton")
		bar.Name, bar.Text = "KeyframeGroup", ""
		bar.BackgroundTransparency, bar.BorderSizePixel = 1, 0
		bar.AutoButtonColor, bar.AnchorPoint = false, Vector2.new(0, 0.5)
		bar.Active, bar.Selectable = true, true
		local entry = { bar = bar }
		bar.MouseButton1Down:Connect(function()
			if busy(self) then
				return
			end

			local now = os.clock()
			local modified = self:IsSelectionModifierDown()
			local key = entry.members[1].key
			if modified then
				entry.clicked = nil
				local selected = entry.lane == POSE and raw.SelectedKeyframes[key]
					or entry.lane ~= POSE
						and raw.SelectedChannelKeyframes[key]
						and raw.SelectedChannelKeyframes[key][entry.lane]
				if selected then
					if entry.automatic then
						for _, member in entry.members do
							if entry.lane == POSE then
								raw.SelectedKeyframes[member.key] = nil
							elseif raw.SelectedChannelKeyframes[member.key] then
								raw.SelectedChannelKeyframes[member.key][entry.lane] = nil
								if not next(raw.SelectedChannelKeyframes[member.key]) then
									raw.SelectedChannelKeyframes[member.key] = nil
								end
							end
						end

						self:RefreshKeyframeSelectionVisuals()
						self:UpdateDeleteButtonState()
						return
					end

					if entry.lane == POSE then
						self:ToggleSelectedKeyframe(key)
					else
						self:ToggleSelectedChannelKeyframe(key, entry.lane)
					end

					return
				end
			end

			selectGroup(self, entry, modified)
			if not modified and entry.clicked and now - entry.clicked < 0.3 then
				entry.clicked = nil
				if entry.automatic then
					self:ZoomDenseKeyGroup(entry)
				else
					self:ExpandSelectedKeyframeGroups()
				end

				return
			end

			entry.clicked = now
			if entry.lane == POSE then
				self:_initiateKeyframeDrag(entry.members[1].key, true)
			else
				self:_initiateChannelKeyframeDrag(entry.members[1].key, entry.lane, true)
			end
		end)
		bar.MouseButton2Click:Connect(function()
			if busy(self) then
				return
			end

			local key = entry.members[1].key
			local selected = entry.lane == POSE and raw.SelectedKeyframes[key]
				or entry.lane ~= POSE
					and raw.SelectedChannelKeyframes[key]
					and raw.SelectedChannelKeyframes[key][entry.lane]
			if not selected then
				selectGroup(self, entry, false)
			end

			Menu.open(Input:GetMouseLocation())
		end)
		bar.Parent = container
		return entry
	end

	function Timeline:RestoreGroupedButtons()
		for button, visible in self._groupHiddenButtons or {} do
			if button.Parent then
				button.Visible = visible
			end
		end

		self._groupHiddenButtons = {}
	end

	function Timeline:RefreshKeyframeGroups(budget, viewportOnly)
		if self._refreshingKeyGroups or raw._ImportingKeyframes then
			return
		end

		local previousView = self._keyViewport
		self:PrepareKeyframeViewport(not viewportOnly)
		if viewportOnly and previousView == self._keyViewport then
			return
		end

		local jobs = {}

		local function collectJobs(view)
			for motor, keys in view and view.jobs or {} do
				jobs[motor] = jobs[motor] or {}
				for key in keys do
					jobs[motor][key] = true
				end
			end
		end

		collectJobs(previousView)
		collectJobs(self._keyViewport)

		if not previousView then
			for motor, bucket in raw.Keyframes do
				jobs[motor] = jobs[motor] or {}
				for _, key in bucket do
					if key.Button then
						jobs[motor][key] = true
					end
				end
			end
		end

		self._keyGroupsRefreshQueued = nil
		self._refreshingKeyGroups = true
		self._selectionHitTargets = nil
		self:RestoreGroupedButtons()
		local previous, wanted = self._keyGroupBars or {}, {}
		local byContainer = {}
		self._groupedMotors = {}
		self._groupsByKey = {}

		local function add(key, lane, button, virtualContainer)
			local id = self:DisplayKeyGroup(key, lane)
			if not id or (self._expandedKeyGroups and self._expandedKeyGroups[id]) then
				return
			end

			if not virtualContainer and (not button or not button.Parent or not button.Visible) then
				return
			end

			local image = virtualContainer and self:GetKeyframeAppearance(key, lane)
				or self:GetKeyframeImageObject(button)
			if not image then
				return
			end

			local container = virtualContainer or button.Parent
			byContainer[container] = byContainer[container] or {}
			local token = lane .. ":" .. id
			local group = byContainer[container][token]
			if not group then
				group = { id = id, lane = lane, members = {} }
				byContainer[container][token] = group
			end

			table.insert(
				group.members,
				{ key = key, frame = key.Frame, button = button, image = image }
			)
		end

		for motor, bucket in raw.Keyframes do
			local row = raw.TrackRows[motor.Part1]
			local container = row and self:GetTrackKeyframesContainer(row)
			for key in jobs[motor] or {} do
				local frame = key.Frame
				if bucket[frame] ~= key then
					if key.Button then
						key.Button:Destroy()
						key.Button = nil
					end

					continue
				end

				if budget then
					budget()
				end

				if key.Button and not self:KeyframeInViewport(key, POSE) then
					key.Button:Destroy()
					key.Button = nil
				end

				if key.KeyGroups then
					self._groupedMotors[motor] = true
				end

				local view = self._keyViewport
				if view and not view.visible[key] and not key.KeyGroups then
					for _, channelRow in raw.ChannelTracks[motor] or {} do
						local host = self:GetTrackKeyframesContainer(channelRow)
						local button = host and host:FindFirstChild("ChannelKF_" .. frame)
						if button then
							button:Destroy()
						end
					end

					continue
				end

				if self:IsKeyGroupCollapsed(key, POSE) and container then
					if key.Button then
						key.Button:Destroy()
						key.Button = nil
					end

					add(key, POSE, nil, container)
				elseif key.Part and not key.Button then
					self:CreateOrUpdateTimelineKeyframeButton(
						key.Part,
						motor,
						frame,
						key.Template,
						key.SanitizeName
					)
				end

				if raw.ChannelTracks[motor] then
					self:_addChannelDiamondAtFrame(motor, frame)
				end

				local displayLanes = table.clone(key.KeyGroups or {})
				for lane, id in self._keyViewport and self._keyViewport.groups[key] or {} do
					displayLanes[lane] = id
				end

				if not next(displayLanes) then
					continue
				end

				add(key, POSE, key.Button)
				for lane in displayLanes do
					local row = raw.ChannelTracks[motor] and raw.ChannelTracks[motor][lane]
					local container = row and self:GetTrackKeyframesContainer(row)
					if container then
						if self:IsKeyGroupCollapsed(key, lane) then
							add(key, lane, nil, container)
						end
					end
				end
			end
		end

		for key, buttons in self._ikEndMarkers or {} do
			for _, button in buttons do
				add(key, POSE, button)
			end
		end

		for container, groups in byContainer do
			for token, group in groups do
				local members = group.members
				if #members == 0 then
					continue
				end

				table.sort(members, function(a, b)
					return a.frame < b.frame
				end)
				local view = self._keyViewport
				if
					view
					and (
						view.pending
						or not view.containers[container]
						or self:FrameToVisibleX(members[#members].frame) < view.left
						or self:FrameToVisibleX(members[1].frame) > view.right
					)
				then
					continue
				end

				local entry = previous[container] and previous[container][token]
					or createBar(self, container)
				entry.members, entry.lane, entry.id = members, group.lane, group.id
				entry.automatic = group.id:sub(1, 7) == "@dense:"
				entry.bar:SetAttribute("AutomaticGroup", entry.automatic)
				wanted[container] = wanted[container] or {}
				wanted[container][token] = entry
				local shape = Model.majority(members, function(member)
					return member.image.Image
				end)
				local color = members[1].image.ImageColor3
				for _, member in members do
					if member.image.Image == shape then
						color = member.image.ImageColor3
						break
					end
				end

				entry.baseColor = color
				for _, member in members do
					local selected = group.lane == POSE and raw.SelectedKeyframes[member.key]
						or group.lane ~= POSE
							and raw.SelectedChannelKeyframes[member.key]
							and raw.SelectedChannelKeyframes[member.key][group.lane]
					if selected then
						color = Raw.Colors.KEYFRAME_SELECTED_COLOR
						break
					end
				end

				entry.bar.ZIndex = 10 + math.max(0, math.floor(members[1].frame))
				entry.bar:SetAttribute("GroupShape", shape)
				entry.bar:SetAttribute("GroupCount", #members)
				entry.shape, entry.color = shape, color
				for _, member in members do
					self._groupsByKey[member.key] = self._groupsByKey[member.key] or {}
					table.insert(self._groupsByKey[member.key], entry)
					if member.button then
						self._groupHiddenButtons[member.button] = member.button.Visible
						member.button.Visible = false
					end
				end
			end
		end

		for container, groups in previous do
			for token, entry in groups do
				if not wanted[container] or not wanted[container][token] then
					entry.bar:Destroy()
				end
			end
		end

		self._keyGroupBars = wanted
		self._refreshingKeyGroups = false
		self:RefreshKeyframeGroupPositions()
	end

	const refreshKeyframeGroups = Timeline.RefreshKeyframeGroups

	function Timeline:RefreshKeyframeGroups(...)
		const refreshing = self._refreshingKeyGroups
		const ok, err = pcall(refreshKeyframeGroups, self, ...)
		if not ok then
			self._refreshingKeyGroups = refreshing
			error(err, 0)
		end
	end

	function Timeline:RefreshKeyframeGroupSelection(entries)
		for entry in entries do
			local selected = false
			for _, member in entry.members do
				if
					(entry.lane == POSE and raw.SelectedKeyframes[member.key])
					or (
						entry.lane ~= POSE
						and raw.SelectedChannelKeyframes[member.key]
						and raw.SelectedChannelKeyframes[member.key][entry.lane]
					)
				then
					selected = true
					break
				end
			end

			local color = selected and Raw.Colors.KEYFRAME_SELECTED_COLOR or entry.baseColor
			Outline.update(entry, entry.shape, entry.bar.Size.X.Offset, color)
		end
	end

	function Timeline:RefreshKeyframeGroupPositions()
		local drag = Raw.KeyframeDrag
		local info = drag.draggingKeyframe
		if not info then
			self._compactKeyDrag = nil
		end

		local delta = info and drag.dragCurrentFrame and drag.dragCurrentFrame - info.OriginalFrame
			or 0

		local function position(member, lane)
			if member.button then
				return member.button.Position.X.Offset
			end

			local frame = member.key.Frame
			if info then
				if not info.ChannelId and drag.groupDragOriginals[member.key] ~= nil then
					frame = drag.groupDragOriginals[member.key] + delta
				elseif
					info.ChannelId
					and raw.SelectedChannelKeyframes[member.key]
					and raw.SelectedChannelKeyframes[member.key][lane]
				then
					frame += delta
				end
			end

			return self:FrameToVisibleX(frame)
		end

		for _, groups in self._keyGroupBars or {} do
			for _, entry in groups do
				local a, b = entry.members[1], entry.members[#entry.members]
				local x, y = position(a, entry.lane), position(b, entry.lane)
				local first, last = math.min(x, y), math.max(x, y)
				local width = math.max(Outline.Height, last - first + Outline.Height)
				entry.bar.Position = UDim2.new(0, first - Outline.Height / 2, 0.5, 0)
				entry.bar.Size = UDim2.fromOffset(width, Outline.Height)
				Outline.update(entry, entry.shape, width, entry.color)
			end
		end
	end

	function Timeline:PreviewCompactKeyframeDrag(delta)
		local drag = Raw.KeyframeDrag
		local info = drag.draggingKeyframe
		if not info then
			self._compactKeyDrag = nil
			return false
		end

		local revision = require("cache").revision()
		local cached = self._compactKeyDrag
		if
			not cached
			or cached.info ~= info
			or cached.bars ~= self._keyGroupBars
			or cached.revision ~= revision
		then
			cached = {
				info = info,
				bars = self._keyGroupBars,
				revision = revision,
				buttons = {},
				compact = false,
			}
			local added = {}

			local function add(button, frame)
				if button and not added[button] then
					added[button] = true
					table.insert(cached.buttons, { button = button, frame = frame })
				end
			end

			local function collect(key, frame, lane)
				cached.compact = cached.compact or self:IsKeyGroupCollapsed(key, lane or POSE)
				add(key.Button, frame)
				for id, row in raw.ChannelTracks[key.Motor] or {} do
					if lane and lane ~= id then
						continue
					end

					local container = self:GetTrackKeyframesContainer(row)
					add(container and container:FindFirstChild("ChannelKF_" .. frame), frame)
				end
			end

			if info.ChannelId then
				for _, entry in drag.groupDragSelectedChannels or {} do
					collect(entry.keyData, entry.originalFrame, entry.channelId)
				end
			else
				for _, key in drag.groupDragSelected or {} do
					collect(key, drag.groupDragOriginals[key] or key.Frame)
				end
			end

			self._compactKeyDrag = cached
		end

		if not cached.compact then
			return false
		end

		for _, entry in cached.buttons do
			if entry.button.Parent then
				entry.button.Position =
					UDim2.new(0, self:FrameToVisibleX(entry.frame + delta), 0.5, 0)
			end
		end

		self:RefreshKeyframeGroupPositions()
		return true
	end

	local function visible(bar)
		local object = bar
		while object do
			if object:IsA("GuiObject") and not object.Visible then
				return false
			end

			object = object.Parent
		end

		return bar.Parent ~= nil
	end

	function Timeline:AddGroupsInSelectionBox(minX, minY, maxX, maxY, origin, keys, channels)
		for _, groups in self._keyGroupBars or {} do
			for _, entry in groups do
				local bar = entry.bar
				local pos, size = bar.AbsolutePosition - origin, bar.AbsoluteSize
				if
					visible(bar)
					and pos.X <= maxX
					and pos.X + size.X >= minX
					and pos.Y <= maxY
					and pos.Y + size.Y >= minY
				then
					for _, member in entry.members do
						if entry.lane == POSE then
							table.insert(keys, member.key)
						else
							table.insert(channels, { keyData = member.key, channelId = entry.lane })
						end
					end
				end
			end
		end
	end

	local originalHit = Timeline.IsMouseDirectlyOverKeyframeButton

	function Timeline:IsMouseDirectlyOverKeyframeButton(key, point)
		if originalHit(self, key, point) then
			return true
		end

		for _, entry in self._groupsByKey and self._groupsByKey[key] or {} do
			local bar = entry.bar
			local pos, size = bar.AbsolutePosition, bar.AbsoluteSize
			if
				visible(bar)
				and point.X >= pos.X
				and point.X <= pos.X + size.X
				and point.Y >= pos.Y
				and point.Y <= pos.Y + size.Y
			then
				return true
			end
		end

		return false
	end

	local originalRefresh = Timeline.RefreshAllKeyframeVisuals

	function Timeline:RefreshKeyframeSelectionVisuals()
		if raw._ImportingKeyframes then
			return
		end

		if not self._keyGroupBars or self._keyGroupsRefreshQueued then
			self:RefreshAllKeyframeVisuals()
			return
		end

		local entries, wanted = {}, {}
		for _, lanes in selectedTracks() do
			for lane, selected in lanes do
				for key in selected do
					for _, entry in self._groupsByKey and self._groupsByKey[key] or {} do
						if entry.lane == lane then
							wanted[entry] = true
						end
					end
				end
			end
		end

		for _, groups in self._keyGroupBars do
			for _, entry in groups do
				entries[entry] = true
				if wanted[entry] then
					for _, member in entry.members do
						if entry.lane == POSE then
							raw.SelectedKeyframes[member.key] = true
						else
							raw.SelectedChannelKeyframes[member.key] = raw.SelectedChannelKeyframes[member.key]
								or {}
							raw.SelectedChannelKeyframes[member.key][entry.lane] = true
						end
					end
				end
			end
		end

		local refreshing = self._refreshingKeyGroups
		self._refreshingKeyGroups = true
		local ok, err = pcall(originalRefresh, self)
		self._refreshingKeyGroups = refreshing
		if not ok then
			error(err, 0)
		end

		self:RefreshKeyframeGroupSelection(entries)
	end

	function Timeline:RefreshAllKeyframeVisuals(...)
		if raw._ImportingKeyframes then
			return
		end

		self:RestoreGroupedButtons()
		self:ExpandGroupedSelection()
		local refreshing = self._refreshingKeyGroups
		self._refreshingKeyGroups = true
		local ok, err = pcall(originalRefresh, self, ...)
		self._refreshingKeyGroups = refreshing
		if not ok then
			error(err, 0)
		end

		self:RefreshKeyframeGroups(...)
	end

	for _, name in
		{ "RecordKeyframeForMotorAtCurrentTime", "RecordPartialKeyframeForMotorAtCurrentTime" }
	do
		local original = Timeline[name]
		if original then
			Timeline[name] = function(self, part, motor, ...)
				local result = original(self, part, motor, ...)

				local options =
					select(name == "RecordPartialKeyframeForMotorAtCurrentTime" and 4 or 2, ...)
				local frame = type(options) == "table" and options.Frame
					or self:TimeToFrame(raw.CurrentTime)
				local key = raw.Keyframes[motor] and raw.Keyframes[motor][frame]
				if
					self._groupedMotors
					and self._groupedMotors[motor]
					and not BlenderEdit.blocked()
				then
					self:AdoptKeyIntoGroups(motor, key)
				end

				return result
			end
		end
	end

	for _, name in { "ToggleSelectedKeyframe", "ToggleSelectedChannelKeyframe" } do
		local original = Timeline[name]
		Timeline[name] = function(self, key, lane)
			if not key then
				return original(self, key, lane)
			end

			local groupLane = name == "ToggleSelectedKeyframe" and POSE or lane
			local id = Model.get(key, groupLane)
			local selected = groupLane == POSE and raw.SelectedKeyframes[key]
				or groupLane ~= POSE
					and raw.SelectedChannelKeyframes[key]
					and raw.SelectedChannelKeyframes[key][groupLane]
			if
				id
				and selected
				and not (self._expandedKeyGroups and self._expandedKeyGroups[id])
			then
				for _, member in Model.collect(raw.Keyframes[key.Motor] or {}, groupLane)[id] or {} do
					if member.key == key then
						continue
					end

					if groupLane == POSE then
						raw.SelectedKeyframes[member.key] = nil
						raw.SelectedChannelKeyframes[member.key] = nil
					else
						raw.SelectedKeyframes[member.key] = nil
						local mask = raw.SelectedChannelKeyframes[member.key]
						if mask then
							mask[groupLane] = nil
							if not next(mask) then
								raw.SelectedChannelKeyframes[member.key] = nil
							end
						end
					end
				end

				raw.SelectedKeyframe = key
			end

			local result = original(self, key, lane)
			if
				selected
				and not next(raw.SelectedKeyframes)
				and not next(raw.SelectedChannelKeyframes)
			then
				raw.SelectedKeyframe = nil
				self:RefreshAllKeyframeVisuals()
			end

			return result
		end
	end

	for _, name in { "RefreshAllTimelineKeyframePositions", "ProcessBlenderKeyframeTransform" } do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			local result = original(self, ...)
			self:RefreshKeyframeGroupPositions()
			self:QueueKeyframeViewportRefresh()
			return result
		end
	end

	for _, name in
		{
			"CreateOrUpdateTimelineKeyframeButton",
			"RefreshIKEndMarkers",
			"RefreshChannelDiamondsForMotor",
			"RebuildAllTimelineKeyframeButtons",
			"_restoreMotorBucket",
		}
	do
		local original = Timeline[name]
		if original then
			Timeline[name] = function(self, ...)
				if name == "RebuildAllTimelineKeyframeButtons" then
					self:PrepareKeyframeViewport(true)
					self._viewportBulk = true
				end

				local ok, result = pcall(original, self, ...)
				if name == "RebuildAllTimelineKeyframeButtons" then
					self._viewportBulk = nil
				end

				if not ok then
					error(result, 0)
				end

				if name == "_restoreMotorBucket" and select(3, ...) then
					return result
				end

				if self._refreshingKeyGroups or raw._ImportingKeyframes then
					return result
				end

				if not self._keyGroupsRefreshQueued then
					local queued = {}
					self._keyGroupsRefreshQueued = queued
					task.defer(function()
						if self._keyGroupsRefreshQueued ~= queued then
							return
						end

						self._keyGroupsRefreshQueued = nil
						self:RefreshKeyframeGroups()
					end)
				end

				return result
			end
		end
	end
end
