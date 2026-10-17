--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Raw = require("RawState")
local raw = Raw.Timeline
local Input = require("UserInputService")
local Mode = require("cache")
local Curves = require("GraphCurves")
local Organization = require("Organization")
local Motion = require("Motion")
local BlenderEdit = require("BlenderEdit")
local Assets = require("AssetIds")
local Theme = require("Theme")
local Preferences = require("Preferences")
local Menu = require("KeyframeMenu")

local function visible(object)
	if not object or not object.Parent then
		return false
	end

	while object do
		if object:IsA("GuiObject") and not object.Visible then
			return false
		end

		if object:IsA("LayerCollector") and not object.Enabled then
			return false
		end

		object = object.Parent
	end

	return true
end

return function(Timeline)
	function Timeline:ClearSummaryTracks()
		if self._summaryUnsubscribe then
			self._summaryUnsubscribe()
			self._summaryUnsubscribe = nil
		end

		self._summaryTicket = nil
		self._summaryClick = nil
		for _, scope in self._summaryTracks or {} do
			if scope.content then
				scope.content:Destroy()
			end

			if scope.line then
				if scope.item.selectionLine == scope.line then
					scope.item.selectionLine = nil
				end

				scope.line:Destroy()
			end

			if scope.existingLine and scope.existingLine.Parent then
				scope.existingLine.Visible = scope.lineVisible
			end
		end

		self._summaryTracks = {}
		self._summaryRevision = nil
		self._summaryKeys = nil
	end

	function Timeline:RegisterSummaryTracks(masters)
		self:ClearSummaryTracks()

		local function register(item, owner)
			local scope = {
				item = item,
				row = item.trackElement,
				motors = {},
				entries = {},
				buttons = {},
				painted = {},
				positions = {},
			}
			local seen = {}

			local function collect(child)
				if seen[child] then
					return
				end

				seen[child] = true
				if child ~= item and child.trackIsMaster then
					return
				end

				local motor = child:fetchMotor()
				if motor and child.itemKind ~= "channel" then
					scope.motors[motor] = child
				end

				for _, descendant in child.childItems or {} do
					collect(descendant)
				end
			end

			collect(item)
			if item.itemKind == "armature" and owner then
				for _, motor in require("ArmatureRuntime").collectMotors(owner) do
					if motor.Part1 and motor.Part1:IsDescendantOf(item.linkedRigInstance) then
						scope.motors[motor] = scope.motors[motor]
							or { linkedRigInstance = motor.Part1 }
					end
				end
			end

			if item.trackIsMaster then
				for _, motor in require("Parenting").collectMotors(item.linkedRigInstance) do
					scope.motors[motor] = scope.motors[motor] or { linkedRigInstance = motor.Part1 }
				end

				for _, child in scope.row:GetChildren() do
					if child:IsA("UIListLayout") or child:IsA("UIPadding") then
						child:Destroy()
					end
				end
			end

			local existingLine = scope.row:FindFirstChild("Line")
			if existingLine then
				scope.existingLine = existingLine
				scope.lineVisible = existingLine.Visible
				existingLine.Visible = true
			else
				local templateLine = self.refs.TrackTemplate
					and self.refs.TrackTemplate:FindFirstChild("Line")
				if templateLine then
					scope.line = templateLine:Clone()
					scope.line.Visible = true
					scope.line.Parent = scope.row
					item.selectionLine = scope.line
					item._trackLineTheme = scope.line:GetAttribute("ThemeBg")
					item._trackLineStateTransparency =
						scope.line:GetAttribute("ThemeBgTransparency")
					item._trackLineTransparency = scope.line.BackgroundTransparency
				end
			end

			local content = Instance.new("Frame")
			content.Name = "SummaryContent"
			content.BackgroundTransparency = 1
			content.Size = UDim2.fromScale(1, 1)
			content.Parent = scope.row
			local templateContent = self.refs.TrackTemplate
				and self.refs.TrackTemplate:FindFirstChild("Content")
			local padding = templateContent and templateContent:FindFirstChildOfClass("UIPadding")
			if padding then
				padding:Clone().Parent = content
			end

			scope.content = content
			local host = Instance.new("Frame")
			host.Name = "SummaryKeyframes"
			host.BackgroundTransparency = 1
			host.Size = UDim2.fromScale(1, 1)
			host.ZIndex = 12
			host.Parent = content
			scope.host = host
			table.insert(self._summaryTracks, scope)
		end

		local seen = {}

		local function walk(item, owner)
			if seen[item] then
				return
			end

			seen[item] = true
			if item.trackIsMaster then
				owner = item.linkedRigInstance
			end

			if item.trackIsMaster or item.itemKind == "armature" then
				register(item, owner)
			end

			for _, child in item.childItems or {} do
				walk(child, owner)
			end
		end

		for _, master in masters do
			walk(master)
		end

		self._summaryUnsubscribe = Preferences.subscribe(function(key)
			if key ~= "MasterKeyframes" then
				return
			end

			if
				not Preferences.get(key)
				and Raw.KeyframeDrag.draggingKeyframe
				and Raw.KeyframeDrag.draggingKeyframe.SummaryScope
			then
				self:CancelTimelineKeyframeDrag()
			end

			self._summaryClick = nil
			self._selectionHitTargets = nil
			self:RefreshSummaryKeys()
		end)
		self:RefreshSummaryKeys()
		self:QueueSummaryRefresh(true)
	end

	function Timeline:QueueSummaryRefresh(invalidate)
		if invalidate then
			self._summaryRevision = nil
		end

		if raw._ImportingKeyframes or self._summaryTicket then
			return
		end

		local ticket = {}
		self._summaryTicket = ticket
		task.defer(function()
			if self._summaryTicket ~= ticket then
				return
			end

			self._summaryTicket = nil
			if self.refs and self.refs.KeysRoot and self.refs.KeysRoot.Parent then
				self:RefreshSummaryKeys()
			end
		end)
	end

	function Timeline:RefreshSummaryIndex()
		if not Preferences.get("MasterKeyframes") then
			return
		end

		local revision = Mode.revision()
		if self._summaryRevision == revision and self._summaryKeys == raw.Keyframes then
			return
		end

		self._summaryRevision, self._summaryKeys = revision, raw.Keyframes
		for _, scope in self._summaryTracks or {} do
			local frames = {}
			if scope.item.linkedRigInstance and scope.item.linkedRigInstance.Parent then
				for motor, item in scope.motors do
					if not motor.Parent or Organization.isRemoved(item.linkedRigInstance) then
						continue
					end

					local bucket = raw.Keyframes[motor]
					for frame, key in bucket or {} do
						if type(frame) ~= "number" or not Curves.hasVisibleKey(bucket, key) then
							continue
						end

						local entry = frames[frame]
						if not entry then
							entry = { frame = frame, members = {}, scope = scope, lane = "Pose" }
							frames[frame] = entry
						end

						table.insert(entry.members, { key = key, frame = frame })
					end
				end
			end

			scope.entries = frames
			scope.frames = {}
			for frame in frames do
				table.insert(scope.frames, frame)
			end

			table.sort(scope.frames)
		end
	end

	function Timeline:ExpandSummaryGroups(entry)
		local changed = false
		for _, member in entry.members do
			for _, id in member.key.KeyGroups or {} do
				self._expandedKeyGroups = self._expandedKeyGroups or {}
				if not self._expandedKeyGroups[id] then
					self._expandedKeyGroups[id] = true
					changed = true
				end
			end
		end

		return changed
	end

	function Timeline:SelectSummaryKey(scope, frame, extend, toggle)
		if
			not Preferences.get("MasterKeyframes")
			or BlenderEdit.blocked()
			or raw.Playing
			or Raw.KeyframeTransform.active
		then
			return nil
		end

		self:RefreshSummaryIndex()
		local entry = scope.entries[frame]
		if not entry or #entry.members == 0 then
			return nil
		end

		local all = true
		for _, member in entry.members do
			if not raw.SelectedKeyframes[member.key] then
				all = false
				break
			end
		end

		if not extend then
			self:ClearSelectedKeyframes()
		end

		local expanded = self:ExpandSummaryGroups(entry)
		local remove = extend and toggle and all
		for _, member in entry.members do
			local key = member.key
			if remove then
				raw.SelectedKeyframes[key] = nil
				raw.SelectedChannelKeyframes[key] = nil
			else
				raw.SelectedKeyframes[key] = true
				self:SelectAllChannelsForKeyData(key)
			end
		end

		raw.SelectedKeyframe = next(raw.SelectedKeyframes) or next(raw.SelectedChannelKeyframes)
		if expanded then
			self:RefreshAllKeyframeVisuals()
		else
			self:RefreshKeyframeSelectionVisuals()
		end

		self:UpdateDeleteButtonState()
		if self.refs.RefreshSelectionFilter then
			self.refs.RefreshSelectionFilter()
		end

		return not remove and entry.members[1].key or nil
	end

	function Timeline:PressSummaryKey(scope, frame, context)
		if
			not Preferences.get("MasterKeyframes")
			or not visible(scope.row)
			or BlenderEdit.blocked()
			or raw.Playing
			or Raw.KeyframeTransform.active
			or Raw.PlayheadDrag.draggingPlayhead
		then
			return
		end

		self:RefreshSummaryIndex()
		local stack = scope.stacks and scope.stacks[frame]
		if stack and #stack > 1 then
			local x = (Input:GetMouseLocation().X - scope.host.AbsolutePosition.X)
				/ Motion.scale(scope.host)
			local at = x * self:GetMaxFrame() / math.max(1, self:GetVisibleTimelineWidth())
			local distance = math.huge
			for _, candidate in stack do
				if math.abs(candidate - at) < distance then
					frame = candidate
					distance = math.abs(candidate - at)
				end
			end
		end

		local entry = scope.entries[frame]
		if not entry or #entry.members == 0 then
			return
		end

		local all = true
		for _, member in entry.members do
			if not raw.SelectedKeyframes[member.key] then
				all = false
				break
			end
		end

		local modified = self:IsSelectionModifierDown()
		local previous = self._summaryClick
		local now = os.clock()
		if
			not context
			and not modified
			and all
			and previous
			and previous.scope == scope
			and previous.frame == frame
			and now - previous.time <= 0.3
		then
			self._summaryClick = nil
			self:SelectSummaryKey(scope, frame, false, false)
			Menu.open(Input:GetMouseLocation())
			return
		end

		self._summaryClick = not context
				and not modified
				and { scope = scope, frame = frame, time = now }
			or nil
		local key
		if all and (context or not modified) then
			key = entry.members[1].key
		else
			key = self:SelectSummaryKey(scope, frame, not context and modified, not context)
		end

		if not key then
			return
		end

		if context then
			Menu.open(Input:GetMouseLocation())
		else
			self:_initiateKeyframeDrag(key, true)
			self:ClearKeyframeHover()
			if Raw.KeyframeDrag.draggingKeyframe then
				Raw.KeyframeDrag.draggingKeyframe.SummaryScope = scope
			end

			self:RefreshKeyframeSelectionVisuals()
		end
	end

	function Timeline:PaintSummaryKeys()
		for _, scope in self._summaryTracks or {} do
			for frame, button in scope.buttons do
				local selected, count = 0, 0
				for _, at in scope.stacks and scope.stacks[frame] or { frame } do
					local entry = scope.entries[at]
					for _, member in entry and entry.members or {} do
						count += 1
						if raw.SelectedKeyframes[member.key] then
							selected += 1
						end
					end
				end

				local full = selected == count and count > 0
				local partial = selected > 0 and selected < count
				local hovered = scope.hovered == frame
				local dragging = Raw.KeyframeDrag.draggingKeyframe
				dragging = dragging and dragging.SummaryScope == scope and full
				local color = selected > 0 and Raw.Colors.KEYFRAME_SELECTED_COLOR
					or hovered and Raw.Colors.KEYFRAME_HANDLE_HOVER.AutoClamped
					or Raw.Colors.KEYFRAME_HANDLE_DEFAULT.AutoClamped
				local override = Theme.getOverride(
					selected > 0 and "KfS" or hovered and "KfH" or "KfAC"
				) or Theme.getOverride("KfD")
				local opacity = override and override.t or scope.opacity or 0
				local size = dragging and 22 or selected > 0 and 18 or 16
				local painted = scope.painted[frame]
				if
					not painted
					or painted.full ~= full
					or painted.partial ~= partial
					or painted.color ~= color
					or painted.opacity ~= opacity
					or painted.size ~= size
				then
					local image = self:GetKeyframeImageObject(button)
					image.ImageColor3 = color
					image.ImageTransparency = opacity
					button.Size = UDim2.fromOffset(size, size)
					button:SetAttribute("SummarySelected", full)
					button:SetAttribute("SummaryPartial", partial)
					scope.painted[frame] = {
						full = full,
						partial = partial,
						color = color,
						opacity = opacity,
						size = size,
					}
				end
			end
		end
	end

	function Timeline:RefreshSummaryPositions()
		local drag = Raw.KeyframeDrag
		local width, maximum = self:GetVisibleTimelineWidth(), self:GetMaxFrame()
		for _, scope in self._summaryTracks or {} do
			for frame, button in scope.buttons do
				local at = frame
				local entry = scope.entries[frame]
				local info = drag.draggingKeyframe
				if info and info.IsRealDrag and drag.dragCurrentFrame and entry then
					local all = true
					for _, m in entry.members do
						if not drag.groupDragOriginals[m.key] then
							all = false
							break
						end
					end

					if all then
						at = frame + drag.dragCurrentFrame - info.OriginalFrame
					end
				end

				if Raw.KeyframeTransform.active and entry then
					local target, all = nil, true
					for _, m in entry.members do
						local value = Raw.KeyframeTransform.liveFrames[m.key]
						if value == nil or target and value ~= target then
							all = false
							break
						end

						target = value
					end

					if all and target then
						at = target
					end
				end

				local x = maximum > 0 and math.floor(at / maximum * width + 0.5) or 0
				if scope.positions[frame] ~= x then
					button.Position = UDim2.new(0, x, 0.5, 0)
					scope.positions[frame] = x
				end
			end
		end
	end

	function Timeline:RefreshSummaryKeys()
		if raw._ImportingKeyframes then
			return
		end

		self:RefreshSummaryIndex()
		local pane = self.refs and self.refs.KeysRoot
		local width = self:GetTimelineViewportWidth()
		local displayWidth, maximum = self:GetVisibleTimelineWidth(), self:GetMaxFrame()
		local scale = pane and Motion.scale(pane) or 1
		for _, scope in self._summaryTracks or {} do
			if not scope.host.Parent then
				continue
			end

			local enabled = Preferences.get("MasterKeyframes")
			scope.content.Visible = enabled
			if scope.line then
				scope.line.Visible = enabled
			end

			if scope.existingLine then
				scope.existingLine.Visible = enabled or scope.lineVisible
			end

			local rowVisible = enabled and visible(scope.row)
			if pane and pane.AbsoluteSize.Y > 0 then
				local y = scope.row.AbsolutePosition.Y
				rowVisible = rowVisible
					and y + scope.row.AbsoluteSize.Y >= pane.AbsolutePosition.Y - 32 * scale
					and y <= pane.AbsolutePosition.Y + pane.AbsoluteSize.Y + 32 * scale
			end

			local stamp = scope.displayStamp
			if
				stamp
				and stamp.entries == scope.entries
				and stamp.visible == rowVisible
				and stamp.width == width
				and stamp.displayWidth == displayWidth
				and stamp.maximum == maximum
				and stamp.scroll == raw.ScrollOffset
			then
				continue
			end

			scope.displayStamp = {
				entries = scope.entries,
				visible = rowVisible,
				width = width,
				displayWidth = displayWidth,
				maximum = maximum,
				scroll = raw.ScrollOffset,
			}
			local wanted = {}
			scope.stacks = {}
			local pixels = {}
			if rowVisible then
				for _, frame in scope.frames or {} do
					local x = maximum > 0 and math.floor(frame / maximum * displayWidth + 0.5) or 0
					if x < raw.ScrollOffset - 16 or x > raw.ScrollOffset + width + 16 then
						continue
					end

					local existing = pixels[x]
					if existing then
						table.insert(scope.stacks[existing], frame)
						continue
					end

					pixels[x] = frame
					scope.stacks[frame] = { frame }
					wanted[frame] = true
					if not scope.buttons[frame] then
						local template = self:GetTrackKeyframesContainer(self.refs.TrackTemplate)
							:FindFirstChild("KeyframeTemplate")
						local button = template:Clone()
						button.Name = "SummaryKF_" .. tostring(frame)
						button.Visible = true
						button.AutoButtonColor = false
						button.Active = true
						button.Selectable = true
						button.Size = UDim2.fromOffset(16, 16)
						button.AnchorPoint = Vector2.new(0.5, 0.5)
						button.ZIndex = 13
						local image = self:GetKeyframeImageObject(button)
						image.Image = Assets.KeyframeShapes.Default
						scope.opacity = image.ImageTransparency
						button.MouseEnter:Connect(function()
							scope.hovered = frame
							self:PaintSummaryKeys()
						end)
						button.MouseLeave:Connect(function()
							if scope.hovered == frame then
								scope.hovered = nil
								self:PaintSummaryKeys()
							end
						end)
						button.Parent = scope.host
						scope.buttons[frame] = button
						button.MouseButton1Down:Connect(function()
							self:PressSummaryKey(scope, frame, false)
						end)
						button.MouseButton2Click:Connect(function()
							self:PressSummaryKey(scope, frame, true)
						end)
					end
				end
			end

			for frame, button in scope.buttons do
				if not wanted[frame] then
					button:Destroy()
					scope.buttons[frame] = nil
					scope.painted[frame] = nil
					scope.positions[frame] = nil
				end
			end
		end

		self:RefreshSummaryPositions()
		self:PaintSummaryKeys()
	end

	function Timeline:IsPointOverSummaryKey(point)
		if not Preferences.get("MasterKeyframes") then
			return false
		end

		for _, scope in self._summaryTracks or {} do
			if not visible(scope.row) then
				continue
			end

			for _, button in scope.buttons do
				local p, s = button.AbsolutePosition, button.AbsoluteSize
				local center = p + s * 0.5
				if
					math.abs(point.X - center.X) <= s.X * 0.5
					and math.abs(point.Y - center.Y) <= s.Y * 0.5
				then
					return true
				end
			end
		end

		return false
	end

	local targets = Timeline.GetSelectionHitTargets

	function Timeline:GetSelectionHitTargets(...)
		local existing = self._selectionHitTargets
		local result = targets(self, ...)
		if existing or not Preferences.get("MasterKeyframes") then
			return result
		end

		self:RefreshSummaryIndex()
		for _, scope in self._summaryTracks or {} do
			for frame, entry in scope.entries do
				table.insert(
					result,
					{ row = scope.host, group = entry, first = frame, last = frame }
				)
			end
		end

		return result
	end

	for _, name in
		{
			"RefreshKeyframeSelectionVisuals",
			"SelectKeyframesInSelectionBox",
			"BeginKeyframeBoxSelection",
		}
	do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			local result = original(self, ...)
			if name == "SelectKeyframesInSelectionBox" then
				local expanded = false
				for target in self._selectionBoxHits or {} do
					if target.group and target.group.scope then
						expanded = self:ExpandSummaryGroups(target.group) or expanded
					end
				end

				if expanded then
					self:RefreshKeyframeGroups()
				end
			end

			self:PaintSummaryKeys()
			return result
		end
	end

	for _, name in
		{ "RefreshKeyframeGroups", "RefreshAllTimelineKeyframePositions", "RebindTrackRows" }
	do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			local result = original(self, ...)
			self:RefreshSummaryKeys()
			return result
		end
	end

	for _, name in { "UpdateKeyframeDragAtPosition", "ProcessBlenderKeyframeTransform" } do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			local result = original(self, ...)
			if
				Raw.KeyframeDrag.draggingKeyframe and Raw.KeyframeDrag.draggingKeyframe.IsRealDrag
			then
				self._summaryClick = nil
			end

			self:RefreshSummaryPositions()
			return result
		end
	end

	for _, name in
		{
			"CreateOrUpdateTimelineKeyframeButton",
			"DeleteKeyframe",
			"MoveKeyframe",
			"_restoreMotorBucket",
			"RebuildAllTimelineKeyframeButtons",
		}
	do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			local result = original(self, ...)
			self:QueueSummaryRefresh(true)
			return result
		end
	end

	local cancelDrag = Timeline.CancelTimelineKeyframeDrag

	function Timeline:CancelTimelineKeyframeDrag(...)
		self._summaryClick = nil
		return cancelDrag(self, ...)
	end

	for _, name in { "ClearTimelineData", "ClearTracks" } do
		local original = Timeline[name]
		Timeline[name] = function(self, ...)
			self:ClearSummaryTracks()
			return original(self, ...)
		end
	end
end
