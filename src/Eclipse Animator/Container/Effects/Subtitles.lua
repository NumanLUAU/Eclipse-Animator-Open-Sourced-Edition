--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("SubtitleData")
local Events = require("Events")
local Renderer = require("Renderer")
local Raw = require("RawState")
local Subtitles = {}
local refs, gui, renderer, cameraRenderer, cameraSurface
local connections = {}
local unsubscribe
local membership
local appliedOrder
local rebuilding = false
local refreshToken
local entryCache, entryTracks, entryStarts, entryMembership

local function sortedEntries()
	local tracks = Events.all()
	local changed = not entryCache
	local count = 0
	for rig, track in tracks do
		count += 1
		local old = entryTracks and entryTracks[track]
		if
			not old
			or old.rig ~= rig
			or old.parent ~= rig.Parent
			or old.revision ~= track.Revision
			or old.events ~= track.Events
			or old.id ~= track.DocumentId
		then
			changed = true
		end
	end

	if entryTracks and count ~= entryTracks.count then
		changed = true
	end

	if changed then
		entryCache = {}
		entryTracks = { count = count }
		for rig, track in tracks do
			entryTracks[track] = {
				rig = rig,
				parent = rig.Parent,
				revision = track.Revision,
				events = track.Events,
				id = track.DocumentId,
			}
			if not rig.Parent then
				continue
			end

			for id, event in track.Events do
				if event.Subtitle then
					table.insert(entryCache, {
						id = track.DocumentId .. ":" .. id,
						track = track,
						event = event,
						rig = rig,
					})
				end
			end
		end

		table.sort(entryCache, function(a, b)
			if a.event.Subtitle.Order ~= b.event.Subtitle.Order then
				return a.event.Subtitle.Order < b.event.Subtitle.Order
			end

			if a.event.Frame ~= b.event.Frame then
				return a.event.Frame < b.event.Frame
			end

			return a.id < b.id
		end)
		local ids = {}
		entryStarts = {}
		for order, entry in entryCache do
			ids[order] = entry.id
			entryStarts[order] = {
				entry = entry,
				order = order,
				first = entry.event.Frame,
				last = entry.event.Frame + entry.event.Subtitle.Duration,
			}
		end

		table.sort(ids)
		entryMembership = table.concat(ids, "|")
		table.sort(entryStarts, function(a, b)
			return a.first < b.first
		end)
		local last = -math.huge
		for _, row in entryStarts do
			last = math.max(last, row.last)
			row.maxEnd = last
		end
	end

	return entryCache
end

local function activeEntries(frame)
	local low, high = 1, #entryStarts
	while low <= high do
		local mid = (low + high) // 2
		if entryStarts[mid].first <= frame then
			low = mid + 1
		else
			high = mid - 1
		end
	end

	local rows = {}
	local Organization = require("Organization")
	for i = high, 1, -1 do
		local row = entryStarts[i]
		if row.maxEnd <= frame then
			break
		end

		local entry = row.entry
		if
			row.last > frame
			and entry.event.Enabled ~= false
			and Organization.isEnabled(entry.rig)
		then
			table.insert(rows, row)
		end
	end

	table.sort(rows, function(a, b)
		return a.order < b.order
	end)
	local entries = {}
	for i, row in rows do
		entries[i] = row.entry
	end

	return entries
end

function Subtitles.entries(enabledOnly)
	local entries = {}
	for _, entry in sortedEntries() do
		if
			not enabledOnly
			or entry.event.Enabled ~= false and require("Organization").isEnabled(entry.rig)
		then
			table.insert(entries, table.clone(entry))
		end
	end

	return entries
end

function Subtitles.getRefs()
	return refs
end

function Subtitles.buildRows(rig, baseItem)
	for _, track in table.clone(Events.all()) do
		Events.migrateSubtitles(track)
	end

	local items = {}
	for i, entry in Subtitles.entries(false) do
		local row = rig.refs.Timeline:GetTrackTemplate():Clone()
		row.Name = "Subtitle_Track"
		local item = baseItem.initialize(
			rig.refs.RigItemTemplate:Clone(),
			"SUBTITLE",
			nil,
			row,
			false,
			entry.rig,
			"subtitles"
		)
		item.subtitleId = entry.event.Id
		item.subtitleIndex = i
		item.grandpa = item
		item.uiElement.Parent = rig.refs.RigListScroll
		item.uiElement.LayoutOrder = -1000 + i
		row.Parent = rig.refs.KeysRoot
		require("EventTrackList").bind(rig.refs.Timeline, item)
		table.insert(items, item)
	end

	rig._subtitleItems = items

	membership = entryMembership
	appliedOrder = entryCache
end

function Subtitles.edit(track, id, callback, description, transient)
	local event = track and track.Events[id]
	if not event or not refs then
		return false
	end

	local before = Events.snapshot(track)
	local draft = Data.copy(event.Subtitle or {})
	callback(draft, event)
	event.Subtitle = Data.copy(draft)
	if transient then
		track.Revision = (track.Revision or 0) + 1
		refs.State.currentProjectSaved = false
	else
		Events.changed(track)
		refs.State.Timeline:RecordEventEdit(track, before, description or "Edit subtitle")
	end

	refs.State.Timeline:RefreshEventRows()
	Subtitles.step()
	return true
end

function Subtitles.add(rig, frame, preset)
	if not refs then
		return
	end

	if refs.Finalize then
		refs.Finalize()
	end

	local track = Events.subtitleTrack()
	local before = Events.snapshot(track)
	local event = Events.create(track, frame)
	event.Name = "Subtitle"
	event.Markers = {}
	event.Subtitle = Data.preset(preset or "Clean")
	event.Subtitle.Duration = Raw.Timeline.FPS * 3
	track.Enabled = true
	Events.changed(track)
	refs.State.Timeline:RecordEventEdit(track, before, "Add subtitle")
	if refs.RefreshStructure then
		refs.RefreshStructure()
	end

	refs.State.Timeline:RefreshEventRows()
	Subtitles.step()
	return track, event
end

function Subtitles.duplicate(track, id)
	local event = track.Events[id]
	if not event or not event.Subtitle then
		return
	end

	local before = Events.snapshot(track)
	local new = Events.create(track, event.Frame + event.Subtitle.Duration)
	new.Name = "Subtitle"
	new.Markers = {}
	new.Subtitle = Data.copy(event.Subtitle)
	Events.changed(track)
	refs.State.Timeline:RecordEventEdit(track, before, "Duplicate subtitle")
	if refs.RefreshStructure then
		refs.RefreshStructure()
	end

	refs.State.Timeline:RefreshEventRows()
	return new
end

function Subtitles.remove(track, id)
	local event = track and track.Events[id]
	if not event or not refs then
		return
	end

	local only = #Events.markers(event) == 0
		and #(event.Emits or {}) == 0
		and not require("SoundData").has(event.Sounds)
		and event.CodeBegin == ""
		and event.CodeEnd == ""
	if only then
		refs.State.Timeline:DeleteEvent(track, id)
	else
		local before = Events.snapshot(track)
		event.Subtitle = nil
		Events.changed(track)
		refs.State.Timeline:RecordEventEdit(track, before, "Remove subtitle")
		refs.State.Timeline:RefreshEventRows()
	end

	Subtitles.step()
end

function Subtitles.commitInput(track, before)
	if not refs or Events.all()[track.Rig] ~= track then
		return
	end

	Events.changed(track)
	refs.State.Timeline:RecordEventEdit(track, before, "Edit subtitle")
end

function Subtitles.jump(frame)
	if not refs then
		return
	end

	local timeline = refs.State.Timeline
	Raw.Timeline.Playing = false
	Raw.Timeline.CurrentTime = math.max(0, frame) / Raw.Timeline.FPS
	if refs.State.currentRig then
		timeline:ApplyPoseAtTime(refs.State.currentRig, Raw.Timeline.CurrentTime)
	end

	timeline:UpdatePlayhead()
	Subtitles.step()
end

function Subtitles.clear()
	if renderer then
		renderer:clear()
	end

	if cameraRenderer then
		cameraRenderer:clear()
	end
end

function Subtitles.step()
	if not refs then
		return
	end

	local owner = refs
	local Camera = require("CameraPreview")
	if refs ~= owner then return end
	local active = refs.ScreenGui.Parent
		and refs.ScreenGui.Enabled
		and (refs.Active() or Camera.isFull())
	sortedEntries()
	local signature = entryMembership
	if active and membership == signature and refs.State.Rig and appliedOrder ~= entryCache then
		appliedOrder = entryCache
		local indices = {}
		for index, entry in sortedEntries() do indices[entry.id] = index end
		local changed = false
		for _, item in refs.State.Rig._subtitleItems or {} do
			local track = Events.get(item.linkedRigInstance)
			local index = indices[track.DocumentId .. ":" .. item.subtitleId]
			if index and item.subtitleIndex ~= index then
				item.subtitleIndex = index
				item.uiElement.LayoutOrder = -1000 + index
				changed = true
			end
		end
		if changed then
			table.sort(refs.State.Rig._subtitleItems, function(a, b) return a.subtitleIndex < b.subtitleIndex end)
			require("Hierarchy").refreshDynamic(refs.State.Rig)
		end
	end
	if
		active
		and membership ~= signature
		and not require("EventTrackList").isDragging()
		and not rebuilding
		and not refs.State.LoadingProject
		and refs.RefreshStructure
	then
		rebuilding = true
		local owner, token = refs, {}
		local project = owner.State.currentProjectSequence
		refreshToken = token
		task.defer(function()
			if refreshToken ~= token then
				return
			end

			local ok, issue = true, nil
			if
				refs == owner
				and owner.Active()
				and not require("EventTrackList").isDragging()
				and not owner.State.LoadingProject
				and owner.State.currentProjectSequence == project
			then
				sortedEntries()
				if membership ~= entryMembership then
					ok, issue = pcall(owner.RefreshStructure)
				end
			end

			if refreshToken == token then
				refreshToken = nil
				rebuilding = false
			end

			if not ok then
				warn("[Eclipse subtitles] " .. tostring(issue))
			end
		end)
	end

	local frame = Raw.Timeline.CurrentTime * Raw.Timeline.FPS
	local entries = active and activeEntries(frame) or {}
	if #entries == 0 then
		Subtitles.clear()
		return
	end

	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "EclipseSubtitleOverlay"
		gui:SetAttribute("EclipseOwnedUI", true)
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = refs.ScreenGui.DisplayOrder - 1
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = refs.ScreenGui.Parent
		renderer = Renderer.new(gui)
	end

	renderer:step(
		entries,
		frame,
		Raw.Timeline.FPS,
		not Raw.Timeline.Playing and require("SubtitleEditor").isOpen() and os.clock() or nil
	)
	local surface = Camera.subtitleSurface()
	if surface ~= cameraSurface then
		if cameraRenderer then
			cameraRenderer:destroy()
			cameraRenderer = nil
		end

		cameraSurface = surface
		if surface then
			cameraRenderer = Renderer.new(surface)
		end
	end

	if cameraRenderer then
		cameraRenderer:step(entries, frame, Raw.Timeline.FPS)
	end
end

function Subtitles.destroy()
	refreshToken = nil
	rebuilding = false
	require("EventTrackList").clear()
	require("SubtitleEditor").close(true)
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end

	if renderer then
		renderer:destroy()
		renderer = nil
	end

	if cameraRenderer then
		cameraRenderer:destroy()
		cameraRenderer = nil
	end

	if gui then
		gui:Destroy()
		gui = nil
	end

	cameraSurface = nil
	refs = nil
	membership = nil
	appliedOrder = nil
	entryCache = nil
	entryTracks = nil
	entryStarts = nil
	entryMembership = nil
end

function Subtitles.init(options)
	Subtitles.destroy()
	refs = options
	options.State.Subtitles = Subtitles
	local Input = require("UserInputService")
	table.insert(
		connections,
		Input.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape and not Input:GetFocusedTextBox() then
				require("EventTrackList").escape(options.State.Timeline)
			end
		end)
	)
	table.insert(connections, game:GetService("RunService").RenderStepped:Connect(Subtitles.step))
	table.insert(connections, options.ScreenGui.Destroying:Once(Subtitles.destroy))
	table.insert(connections, options.Plugin.Unloading:Once(Subtitles.destroy))
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				require("SubtitleEditor").close(true)
				Subtitles.clear()
			end
		end)
	)
	unsubscribe = Events.subscribe(Subtitles.step)
end

return Subtitles
