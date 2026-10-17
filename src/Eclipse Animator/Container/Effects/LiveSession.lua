--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Studio = game:GetService("StudioService")
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local Storage = game:GetService("ServerStorage")
local Document = require("Document")
local Adapter = require("Adapter")
local Chunks = require("ChunkStore")
local Tool = require("Tool")
local History = require("History")
local Raw = require("RawState")
local Policy = require("Policy")
local Confirm = require("Confirm")
local Notification = require("Notification")
local Preview = require("rig")
local Presence = require("Presence")
local Run = game:GetService("RunService")
local Theme = require("Theme")
local Live = {}
local presence, following, renderConnection, joiningFollow
local joinAttempt
local observed, controlNumber, lastSent, remoteSource, remoteRevision
local transportDirty = false
local sessionConnections = {}
local lastCapture = 0
local editVersion = 0
local sharedVersion = 0
local leaving = false
local stream, previewShown, streamEditing
local synchronizing = false
local liveUndo, liveRedo = {}, {}
local stepping = false
local RETRY = "Eclipse Live retry"
const REMOTE_GRACE = 0.5
local remoteDrivenAt = -math.huge

local function now()
	return DateTime.now().UnixTimestampMillis / 1000
end

local invitation, invitedRoom
local dismissed = {}
local lifetime = 0
local refs, window, session, actor, document, adapter, unsubscribe
local changed = false
local applying = false
local pendingSince
local generation = 0
local status
local consumed = {}
local tick = 0
local userId, userName
local lastDiscoveryWarning

local function projectId()
	local save = refs.State.currentProjectSave
	return save and save:GetAttribute("EclipseProjectId")
end

local function directory(create)
	local root = require("root").get("EclipseAnimator_Live", false)
	if root then
		assert(
			root:GetAttribute("EclipseLiveVersion") == 1,
			"The Live folder belongs to a different version"
		)
	end

	if not root and create then
		root = require("root").get("EclipseAnimator_Live", true)
		root.Archivable = false
		root:SetAttribute("EclipseLiveVersion", 1)
	end

	return root
end

local PROTOCOL = 35

local function members(room)
	local result = {}
	if room and room:GetAttribute("Closed") then
		return result
	end

	local peers = room and room:FindFirstChild("Peers")
	if room and room:GetAttribute("Host") then
		local host = peers and peers:FindFirstChild(room:GetAttribute("Host"))
		if not host or not Presence.alive(host) then
			return result
		end
	end

	if peers then
		for _, peer in Presence.current(peers) do
			if peer:IsA("Folder") and Presence.alive(peer) then
				local source = Presence.target(peers, peer.Name, "") or peer
				local data = Presence.read(source)
				table.insert(result, {
					playing = data and data.playing,
					id = peer.Name,
					name = peer:GetAttribute("UserName") or "Creator",
					user = peer:GetAttribute("UserId") or 0,
					color = peer:GetAttribute("Color") or Presence.color(peer.Name),
					frame = Presence.sample(source, now()),
					peer = peer,
				})
			end
		end
	end

	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

local function cleanupRooms(root)
	if not root then
		return
	end

	local stamp = os.time()
	for _, room in root:GetChildren() do
		if room:IsA("Folder") and room:GetAttribute("Protocol") == PROTOCOL and room ~= session then
			local peers = room:FindFirstChild("Peers")
			local newest = 0
			for _, peer in peers and peers:GetChildren() or {} do
				local seen = peer:GetAttribute("Seen")
				if type(seen) == "number" and seen == seen then
					newest = math.max(newest, seen)
				end
			end

			local closed = room:GetAttribute("Closed") == true
			local closedAt = room:GetAttribute("ClosedAt")
			if closed and type(closedAt) ~= "number" then
				room:SetAttribute("ClosedAt", stamp)
				closedAt = stamp
			end

			if
				(closed and stamp - closedAt >= 15)
				or (not closed and newest > 0 and stamp - newest > 300)
			then
				room:Destroy()
			end
		end
	end
end

local function availableRooms()
	local rooms = {}
	local root = directory(false)
	cleanupRooms(root)
	if root then
		for _, room in root:GetChildren() do
			if room:GetAttribute("Protocol") == PROTOCOL and #members(room) > 0 then
				table.insert(rooms, room)
			end
		end
	end

	table.sort(rooms, function(a, b)
		return a.Name < b.Name
	end)
	return rooms
end

local function closeInvitation()
	if invitation then
		local old = invitation
		invitation = nil
		invitedRoom = nil
		old:close(true)
	end
end

local function findRoom()
	local root = directory(false)
	cleanupRooms(root)
	local found
	if root then
		for _, room in root:GetChildren() do
			if
				room:GetAttribute("Protocol") == PROTOCOL
				and room:GetAttribute("ProjectId") == projectId()
				and #members(room) > 0
				and (
					not found
					or (room:GetAttribute("StartedAt") or 0) > (found:GetAttribute("StartedAt") or 0)
					or (room:GetAttribute("StartedAt") or 0)
							== (found:GetAttribute("StartedAt") or 0)
						and room.Name > found.Name
				)
			then
				found = room
			end
		end
	end

	return found
end

local refresh, busy

function Live.isExporting()
	if refs and refs.State.Timeline:GetState().Exporting then
		return true
	end

	if session then
		for _, peer in Presence.current(session.Peers) do
			if peer:GetAttribute("Exporting") and Presence.alive(peer) then
				return true
			end
		end
	end

	return false
end

local function detachSync()
	if not actor or not session then
		return
	end

	local group = Presence.group(session.Peers, actor.Name)
	local count = 0
	for _ in group do
		count += 1
	end

	if count > 1 then
		actor:SetAttribute("SyncWith", "solo:" .. actor.Name)
	end
end

local function emitTransport()
	if not actor then
		return
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local revision = controlNumber or 0
	for _, peer in session.Peers:GetChildren() do
		local packet = Presence.read(peer)
		if packet then
			revision = math.max(revision, packet.n)
		end
	end

	controlNumber = revision + 1
	actor:SetAttribute(
		"Transport",
		Http:JSONEncode({
			n = controlNumber,
			frame = raw.CurrentTime * raw.FPS,
			fps = raw.FPS,
			at = now(),
			playing = raw.Playing == true,
			finish = timeline:GetPlaybackEndTime() * raw.FPS,
			first = timeline:GetPlaybackStartTime() * raw.FPS,
			loop = timeline:IsLooping(),
		})
	)
	Presence.read(actor)
	lastSent = os.clock()
	transportDirty = false
end

function Live.beginExport()
	if actor then
		actor:SetAttribute("Exporting", true)
	end

	while synchronizing do
		task.wait()
	end

	if actor then
		emitTransport()
	end
end

function Live.endExport(restore)
	if actor then
		actor:SetAttribute("Exporting", nil)
	end

	observed = nil
	remoteSource = nil
	remoteRevision = nil
	if restore and actor then
		emitTransport()
		Live.afterAdvance()
	end
end

function Live.followPlayhead(id)
	if Live.isExporting() then
		return
	end

	if not actor then
		return
	end

	detachSync()
	following = following ~= id and id or nil
	joiningFollow = following ~= nil
	actor:SetAttribute("Following", following)
	refs.State.Timeline:GetState().Playing = false
	observed = nil
	remoteSource = nil
	remoteRevision = nil
	emitTransport()
end

function Live.syncPlayhead(id)
	if Live.isExporting() then
		return
	end

	if not actor or not session then
		return
	end

	local group = Presence.group(session.Peers, actor.Name)
	if not id or group[id] then
		detachSync()
		emitTransport()
		return
	end

	local peer = session.Peers:FindFirstChild(id)
	if not peer or not Presence.alive(peer) then
		return
	end

	following = nil
	joiningFollow = nil
	actor:SetAttribute("Following", nil)
	local source = Presence.target(session.Peers, id, actor.Name) or peer
	local data = Presence.read(source)
	local frame = Presence.sample(source, now())
	local raw = refs.State.Timeline:GetState()
	if frame then
		raw.CurrentTime = frame / raw.FPS
		raw.Playing = data and data.playing == true or false
	end

	actor:SetAttribute("SyncWith", Presence.groupKey(peer))
	observed = nil
	remoteSource = nil
	remoteRevision = nil
	emitTransport()

	refs.State.Timeline.LastLiveFrame = nil
	if refs.State.currentRig then
		refs.State.Timeline:ApplyPoseAtTime(refs.State.currentRig, raw.CurrentTime)
	end

	refs.State.Timeline:UpdatePlayhead()
end

function Live.afterAdvance()
	if refs.State.Timeline:GetState().Exporting then
		return
	end

	if not session or refs.State.Timeline._playbackPreparation then
		return
	end

	local raw = refs.State.Timeline:GetState()
	observed = {
		time = raw.CurrentTime,
		playing = raw.Playing,
		fps = raw.FPS,
		loop = refs.State.Timeline:IsLooping(),
		finish = refs.State.Timeline:GetPlaybackEndTime(),
		first = refs.State.Timeline:GetPlaybackStartTime(),
	}
end

function Live.advance(dt)
	if Live.isExporting() then
		refs.State.Timeline:GetState().Playing = false
		if not refs.State.Timeline:GetState().Exporting then
			require("EventPlayback").stop()
		end

		return true
	end

	if not session then
		return false
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	if timeline._playbackPreparation then
		return true
	end

	if timeline._playbackReadyAt and os.clock() < timeline._playbackReadyAt then
		return true
	end

	local manual = observed
		and (
			math.abs(raw.CurrentTime - observed.time) > 1e-7
			or raw.Playing ~= observed.playing
			or raw.FPS ~= observed.fps
			or timeline:IsLooping() ~= observed.loop
			or timeline:GetPlaybackEndTime() ~= observed.finish
			or timeline:GetPlaybackStartTime() ~= observed.first
		)
	local group = Presence.group(session.Peers, actor.Name)
	local shared
	local count = 0
	for _ in group do
		count += 1
	end

	shared = count > 1
	if shared and following then
		following = nil
		actor:SetAttribute("Following", nil)
		refresh()
	end

	if manual then
		if following then
			following = nil
			actor:SetAttribute("Following", nil)
			refresh()
		end

		transportDirty = true
	end

	if
		transportDirty
		and (
			not Raw.PlayheadDrag.draggingPlayhead
			or not lastSent
			or os.clock() - lastSent >= 1 / 30
		)
	then
		emitTransport()
	end

	local target
	if following then
		target = Presence.target(session.Peers, following, actor.Name)
		if not target then
			following = nil
			actor:SetAttribute("Following", nil)
			raw.Playing = false
			emitTransport()
			refresh()
		end
	elseif shared then
		target = Presence.source(session.Peers, actor.Name)
	end

	if target and (target ~= actor or shared) and not Raw.PlayheadDrag.draggingPlayhead then
		local data = Presence.read(target)
		if data then
			if busy() then
				return true
			end

			local commandChanged = remoteSource ~= target or remoteRevision ~= data.n
			local frame = Presence.position(data, os.clock())
			local before = raw.CurrentTime

			if commandChanged and data.playing and not data.sampleFrame and not joiningFollow then
				data.receivedAt = os.clock()
				frame = data.frame
			end

			timeline:ApplyLivePlayhead(
				frame,
				data.playing,
				dt,
				data.loop,
				data.finish,
				commandChanged,
				data.first
			)
			local shown = target ~= actor
				and not data.playing
				and stream
				and stream:apply(target, consumed[target], dt)
			if previewShown and not shown and refs.State.currentRig then
				timeline:ApplyPoseAtTime(refs.State.currentRig, raw.CurrentTime)
			end

			if target ~= actor or shown or previewShown or math.abs(raw.CurrentTime - before) > 1e-7 then
				remoteDrivenAt = os.clock()
			end

			previewShown = shown
			remoteSource, remoteRevision = target, data.n
			joiningFollow = nil
			return true
		end
	end

	if previewShown and refs.State.currentRig then
		timeline:ApplyPoseAtTime(refs.State.currentRig, raw.CurrentTime)
		remoteDrivenAt = os.clock()
	end

	previewShown = nil
	remoteSource = nil
	remoteRevision = nil
	return false
end

refresh = function()
	if refs and refs.State.Timeline then
		refs.State.Timeline:RefreshNavigation()
	end

	if not window then
		return
	end

	local room = session or findRoom()
	local people = members(room)
	local rooms = not session and availableRooms() or {}
	window.count.Text = if session or room
		then tostring(#people) .. (#people == 1 and " creator in this file" or " creators in this file")
		else (
			#rooms == 0 and "No Live sessions right now"
			or tostring(#rooms)
				.. (#rooms == 1 and " Live session open" or " Live sessions open")
		)
	window.file.Text = refs.State.currentProjectSave and refs.State.currentProjectSave.Name
		or "Unsaved file"
	local color = session and Color3.fromRGB(108, 213, 160) or Color3.fromRGB(153, 147, 161)
	window.status.Text = session and (Live.isExporting() and "EXPORTING" or "ONLINE") or "OFFLINE"
	window.status:SetAttribute("ThemeTxt", nil)
	window.status.TextColor3 = color
	window.dot.BackgroundColor3 = color
	window.error.Text = status or ""
	window.error.Visible = status ~= nil
	window.list.Size = UDim2.new(1, -24, 1, status and -264 or -226)
	local group = session and Presence.group(session.Peers, actor.Name) or {}
	local roomRows = window.roomRows
	local listed = {}
	if not session then
		for index, other in rooms do
			listed[other] = true
			local row = roomRows[other]
			if not row then
				row = Tool.make(
					"Frame",
					window.list,
					"Room",
					{ Size = UDim2.new(1, -12, 0, 44), BackgroundTransparency = 1 }
				)
				Tool.label(row, "FileName", "", UDim2.fromOffset(12, 4), UDim2.new(1, -110, 0, 20))
				local who =
					Tool.label(row, "Who", "", UDim2.fromOffset(12, 22), UDim2.new(1, -110, 0, 18))
				who.TextSize = 11
				who.TextTransparency = 0.35
				local button = Tool.button(
					row,
					"JoinRoom",
					"JOIN",
					UDim2.new(1, -86, 0, 10),
					UDim2.fromOffset(80, 24),

					function()
						Live.requestJoin(other)
					end
				)
				button:SetAttribute("ThemeBg", "Sel")
				Theme.applyTree(button)
				roomRows[other] = row
			end

			row.LayoutOrder = -100 + index
			local inRoom = members(other)
			row.FileName.Text = (other:GetAttribute("FileName") or "Animation")
				.. (other:GetAttribute("ProjectId") == projectId() and "  (your file)" or "")
			local names = {}
			for i, person in inRoom do
				if i <= 3 then
					table.insert(names, person.name)
				end
			end

			row.Who.Text = table.concat(names, ", ")
				.. (#inRoom > 3 and " +" .. (#inRoom - 3) or "")
		end
	end

	for other, row in roomRows do
		if not listed[other] then
			row:Destroy()
			roomRows[other] = nil
		end
	end

	local count = 0
	for _ in group do
		count += 1
	end

	window.followText.Text = following and "FOLLOW: ON" or "FOLLOW: OFF"
	window.syncText.Text = count > 1 and "SYNC: ON" or "SYNC: OFF"
	window.follow:SetAttribute("ThemeBg", following and "Sel" or "TopBtn")
	window.sync:SetAttribute("ThemeBg", count > 1 and "Sel" or "TopBtn")
	Theme.applyTree(window.follow)
	Theme.applyTree(window.sync)
	window.actionText.Text = session and "SAVE & LEAVE"
		or room and "JOIN LIVE"
		or "START LIVE FOR THIS FILE"
	local present = {}
	for i, person in people do
		present[person.id] = true
		local row = window.rows[person.id]
		if not row then
			row = Tool.make(
				"Frame",
				window.list,
				person.id,
				{ Size = UDim2.new(1, -12, 0, 52), BackgroundTransparency = 1 }
			)
			local avatar = Tool.make("ImageLabel", row, "Avatar", {
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = Color3.fromRGB(44, 34, 54),
				BorderSizePixel = 0,
				ScaleType = Enum.ScaleType.Crop,
			})
			Tool.make("UICorner", avatar, "Round", { CornerRadius = UDim.new(1, 0) })
			Tool.make(
				"UIStroke",
				avatar,
				"Ring",
				{ Thickness = 1, Transparency = 0.25, Color = person.color }
			)
			Tool.button(
				row,
				"Follow",
				"FOLLOW",
				UDim2.new(1, -124, 0, 14),
				UDim2.fromOffset(62, 24),

				function()
					Live.followPlayhead(person.id)
					refresh()
				end
			)
			Tool.button(row, "Sync", "SYNC", UDim2.new(1, -58, 0, 14), UDim2.fromOffset(54, 24), function()
				Live.syncPlayhead(person.id)
				refresh()
			end
)
			Tool.label(row, "Creator", "", UDim2.fromOffset(62, 6), UDim2.new(1, -194, 0, 22))
			local joined = Tool.label(
				row,
				"Joined",
				"Joined",
				UDim2.fromOffset(62, 28),
				UDim2.new(1, -194, 0, 18)
			)
			joined.TextSize = 11
			joined.TextTransparency = 0.35
			window.rows[person.id] = row
		end

		row.LayoutOrder = i
		row.Joined.Text = person.peer:GetAttribute("Exporting") and "Exporting module…"
			or "Joined"
		row.Avatar.Ring.Color = person.color
		row.Follow.Visible = person.id ~= (actor and actor.Name)
		row.Sync.Visible = row.Follow.Visible
		row.Follow:SetAttribute("ThemeBg", following == person.id and "Sel" or "TopBtn")
		row.Sync:SetAttribute("ThemeBg", count > 1 and group[person.id] and "Sel" or "TopBtn")
		Theme.applyTree(row.Follow)
		Theme.applyTree(row.Sync)
		row.Creator.Text = person.name .. (person.id == (actor and actor.Name) and " (you)" or "")
		row.Avatar.Image = person.user > 0
				and "rbxthumb://type=AvatarHeadShot&id=" .. person.user .. "&w=150&h=150"
			or ""
	end

	for id, row in window.rows do
		if not present[id] then
			row:Destroy()
			window.rows[id] = nil
		end
	end

	window.empty.Visible = #people == 0 and next(listed) == nil
	window.empty.Text = if session
		then "No creators connected"
		else "Nobody is live yet. Start one for your file below."
end

local function focusedEdit()
	local box = Input:GetFocusedTextBox()
	if not box then return nil end
	if box:IsDescendantOf(refs.ScreenGui) then return box end
	local owner = box:FindFirstAncestorWhichIsA("LayerCollector")
	if owner and owner:GetAttribute("EclipseOwnedUI") then return box end
	return nil
end

busy = function()
	if refs.State.PoseSliders and refs.State.PoseSliders.isEditing() then return "Finish the pose slider edit." end
	local state = refs.State
	local axis = state.Axis
	if not synchronizing and Live.isExporting() then return "Wait for module export to finish." end
	if state.PhysicsSimulating then return "Wait for physics to finish or cancel it." end
	if state.PresentationHidden then return "Show Eclipse before joining Live." end
	if not refs.Active() then return "Open an Eclipse file and close any confirmation dialog." end
	if focusedEdit() then return "Finish typing in the Eclipse text field." end
	if state.Timeline._eventDrag then return "Finish dragging the event on the timeline." end
	if state.GraphEditor and state.GraphEditor.isInteracting() then return "Confirm or cancel the current graph edit." end
	if Raw.KeyframeDrag.draggingKeyframe then return "Finish dragging the keyframe." end
	if Raw.KeyframeTransform.active then return "Confirm or cancel the keyframe transform." end
	if Raw.PlayheadDrag.draggingPlayhead then return "Release the playhead before joining Live." end
	if axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode()) then
		return "Confirm or cancel the rig transform."
	end
	for _, name in { "PropertyGizmo", "EffectHandles", "CameraControls", "PoseSliders" } do
		if state[name] and state[name].isEditing() then return "Finish the active property, effect, or camera edit." end
	end
	if state.GreasePencil and state.GreasePencil.isStrokeActive() then return "Finish the grease pencil stroke." end
	return nil
end

local function finishForLive()
	assert(not refs.State.Timeline:GetState().Playing, "Pause playback before joining or saving Live.")
	local box = focusedEdit()
	if box then
		box:ReleaseFocus()
		task.wait()
	end
	local state = refs.State
	for _, name in { "PropertyGizmo", "EffectHandles", "CameraControls", "PoseSliders" } do
		local control = state[name]
		if control and control.isEditing() then control.finish(false) end
	end
	if Raw.KeyframeTransform.active then state.Timeline:ConfirmBlenderKeyframeTransform() end
	refs.Finalize()
	local reason = busy()
	assert(not reason, reason)
end

local function readPacket(peer, budget)
	local records, revision = Document.receive(peer, consumed[peer], budget)
	if not records then
		return nil
	end

	for _, record in records do
		assert(record.a == peer.Name, "Invalid Live author")
	end

	return records, revision
end

local function remember(before, after)
	local entry = {}
	local any = false
	for key, value in after do
		if before[key] ~= value then
			entry[key] = { old = before[key], new = value }
			any = true
		end
	end

	for key, value in before do
		if after[key] == nil then
			entry[key] = { old = value, new = nil }
			any = true
		end
	end

	if not any then
		return
	end

	table.insert(liveUndo, entry)
	if #liveUndo > 100 then
		table.remove(liveUndo, 1)
	end

	table.clear(liveRedo)
end

local function ownerResolved(key)
	const motorId = key:match("^k|(.*)|[^|]+$")
	if motorId then
		return adapter.motors[motorId] ~= nil
	end

	const rigId = key:match("^e|(.*)|[^|]+$") or key:match("^faces|(.*)$") or key:match("^enabled|(.*)$")
	if rigId then
		return adapter.rigs[rigId] ~= nil
	end

	return true
end

local function retainUnresolved(captured)
	for key, value in document.observed do
		if captured[key] == nil and not ownerResolved(key) then
			captured[key] = value
		end
	end

	return captured
end

local function publish(budget)
	assert(session and not session:GetAttribute("Closed"), "The host closed this Live session")
	Document.publish(actor, document.published, document.dirty, budget)
	table.clear(document.dirty)
	if stream then
		stream:commit(actor)
	end
end

local function applyShared(values, previous, budget)
	sharedVersion += 1
	applying = true
	local ok, err = pcall(function()
		adapter:apply(values, previous, budget)
	end)
	applying = false
	remoteDrivenAt = os.clock()
	if not ok then
		error(err, 0)
	end
end

local function synchronizeOnce(forceCapture)
	local token, version = generation, editVersion
	local deadline = os.clock() + 0.004

	local function budget()
		if leaving or token ~= generation or not session or session:GetAttribute("Closed") then
			error(RETRY, 0)
		end

		if os.clock() >= deadline then
			task.wait()
			deadline = os.clock() + 0.004
			if token ~= generation or version ~= editVersion or busy() then
				error(RETRY, 0)
			end
		end
	end

	local incoming, revisions = {}, {}
	for _, other in session.Peers:GetChildren() do
		if other ~= actor then
			local packet, revision = readPacket(other, budget)
			if packet then
				table.insert(incoming, packet)
				revisions[other] = revision
			end
		end
	end

	local raw = refs.State.Timeline:GetState()
	if
		forceCapture
		or changed and (#incoming > 0 or pendingSince ~= nil or os.clock() - lastCapture >= 0.2)
		or (not raw.Playing and os.clock() - lastCapture >= 10)
	then
		local captured = adapter:capture(budget)
		if version ~= editVersion or busy() then
			return
		end

		retainUnresolved(captured)
		local before, userEdit = document.observed, changed
		lastCapture = os.clock()
		changed = false
		if document:edit(captured) and userEdit and not stepping then
			remember(before, captured)
		end
	end

	if next(document.dirty) then
		publish(budget)
	elseif stream and stream.active and not streamEditing then
		stream:commit(actor)
	end

	local remote = false
	for _, packet in incoming do
		local updated = document:merge(packet)
		remote = remote or updated
	end

	if remote then
		pendingSince = pendingSince or os.clock()
	end

	if remote or pendingSince then
		local values = document:values()
		if not Document.equal(values, document.observed) then
			applyShared(values, document.observed, budget)

			document.observed = values
		end

		local shown = adapter:capture(budget)
		if version ~= editVersion then
			error(RETRY, 0)
		end

		document.observed = retainUnresolved(shown)
		lastCapture = os.clock()
		changed = false
		status = nil
		pendingSince = nil
		Live.afterAdvance()
		refresh()
	end

	for peer, revision in revisions do
		consumed[peer] = revision
	end
end

local function synchronize(forceCapture)
	if Live.isExporting() then
		return
	end

	if synchronizing then
		return
	end

	synchronizing = true
	local ok, err = xpcall(function()
		synchronizeOnce(forceCapture)
	end, debug.traceback)
	synchronizing = false
	if not ok then
		error(err, 0)
	end
end

local function step(from, into, back, forward)
	if not session or stepping then
		return false
	end

	stepping = true
	local ok, result = pcall(function()
		refs.Finalize()
		while synchronizing do
			task.wait()
		end

		if changed then
			lastCapture = -math.huge
			stepping = false
			pcall(synchronize)
			stepping = true
			while synchronizing do
				task.wait()
			end
		end

		local reason = busy()
		assert(not reason, reason)
		while #from > 0 do
			local entry = table.remove(from)
			local observed = document.observed
			local target = table.clone(observed)
			local applied = {}
			for key, change in entry do
				if observed[key] == change[forward] then
					target[key] = change[back]
					applied[key] = change
				end
			end

			if next(applied) then
				synchronizing = true
				local done, err = pcall(function()
					applyShared(target, observed)
					document:edit(target)
					publish()
				end)
				synchronizing = false
				if not done then
					error(err, 0)
				end

				lastCapture = os.clock()
				changed = false
				table.insert(into, applied)
				Live.afterAdvance()
				return true
			end
		end

		return false
	end)
	stepping = false
	if not ok then
		Notification.show("LIVE", (tostring(result):gsub("^.-:%d+: ", "")))
		return false
	end

	return result
end

function Live.undo()
	return step(liveUndo, liveRedo, "old", "new")
end

function Live.redo()
	return step(liveRedo, liveUndo, "new", "old")
end

function Live.prepareSave()
	if not session then
		return
	end

	finishForLive()
	while synchronizing do
		task.wait()
	end

	local expected = session
	local deadline = os.clock() + 10
	repeat
		assert(
			session == expected and actor and actor.Parent,
			"Live ended before the save completed"
		)
		assert(os.clock() < deadline, "Live is still receiving edits. Retry Save.")
		changed = true
		local ok, err = pcall(synchronize, true)
		if not ok and not tostring(err):find(RETRY, 1, true) then
			error(err, 0)
		end

		if not ok then
			task.wait()
		end
	until not changed and not pendingSince and not next(document.dirty)
end

function Live.saveAndLeave()
	if not session then
		return true
	end

	local ok, err = pcall(function()
		assert(
			refs.Save(true),
			"Could not save the shared file. You are still connected; retry Save and Leave."
		)
	end)
	if not ok then
		status = tostring(err):gsub("^.-:%d+: ", "")
		refresh()
		return false
	end

	Live.leave(true)
	return true
end

function Live.leave(saved)
    if leaving then return end
    leaving = true
    generation += 1
    while synchronizing do task.wait() end
    local raw = refs and refs.State and refs.State.Timeline and refs.State.Timeline:GetState()
    if session and adapter and document and raw and not raw.Exporting then
        local ok, issue = pcall(function()
            refs.Finalize()
            document:edit(adapter:capture())
            if actor and actor.Parent and not session:GetAttribute("Closed") then
                publish()
            end
            local peers = session:FindFirstChild("Peers")
            for _, peer in peers and peers:GetChildren() or {} do
                if peer ~= actor then
                    local packet = readPacket(peer)
                    if packet then document:merge(packet) end
                end
            end
            local values = document:values()
            if not Document.equal(values, document.observed) then
                applyShared(values, document.observed)
                document.observed = values
                refs.State.currentProjectSaved = false
            end
        end)
        if not ok then
            warn("[Eclipse Live] Final synchronization: " .. tostring(issue))
            Notification.show("LIVE", "Live ended with unsynchronized edits. Your loaded animation is retained; save a recovery copy before closing.")
        end
    end
	if session and refs and refs.State and refs.State.Timeline then
		local raw = refs.State.Timeline:GetState()
		raw.Playing = false
		if raw.Exporting then
			raw.Exporting.Cancelled = true
		end

		require("EventPlayback").stop()
	end

	if joinAttempt then
		joinAttempt.cancelled = true
	end

	for _, connection in sessionConnections do
		connection:Disconnect()
	end

	sessionConnections = {}
	if
		not saved
		and session
		and not session:GetAttribute("Closed")
		and actor
		and document
		and adapter
		and not refs.State.Timeline:GetState().Exporting
	then
		pcall(function()
			document:edit(adapter:capture())
			if next(document.dirty) then
				publish()
			end
		end)
	end

	if actor and session and session:GetAttribute("Host") == actor.Name then
		session:SetAttribute("Closed", true)
		session:SetAttribute("ClosedAt", os.time())
	end

	detachSync()
	generation += 1
	if actor then
		actor:SetAttribute("Exporting", nil)
		actor:SetAttribute("Seen", 0)
		actor:SetAttribute("PoseActive", false)
	end

	actor, session, document, adapter = nil, nil, nil, nil
	following = nil
	joiningFollow = nil
	observed = nil
	controlNumber = nil
	transportDirty = false
	remoteSource = nil
	remoteRevision = nil
	stream = nil
	previewShown = nil
	streamEditing = nil
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if presence then
		presence:clear()
		presence = nil
	end

	local previewOk, previewError = pcall(Preview.finish)
	leaving = false
	History.clear()
	Policy.setLiveChannels(nil)
	consumed = {}
	changed = false
	status = nil
	pendingSince = nil
	table.clear(liveUndo)
	table.clear(liveRedo)
	refresh()
	if not previewOk then
		warn("[Eclipse Live] Preview restoration: " .. tostring(previewError))
	end
end

function Live.recoveryToken()
    if leaving or synchronizing or applying or pendingSince or streamEditing or previewShown then return nil end
    return tostring(generation) .. ":" .. tostring(editVersion) .. ":" .. tostring(sharedVersion)
end

function Live.isApplying()
	return applying or previewShown == true or os.clock() - remoteDrivenAt < REMOTE_GRACE
end

local function endClosedSession()
	if not session then
		return false
	end

	local host = session.Peers:FindFirstChild(session:GetAttribute("Host") or "")
	local closed = session:GetAttribute("Closed")
	if closed or not host or not Presence.alive(host) then
		Live.leave(true)
		status = closed and "The host ended Live. Your current animation remains open."
			or "The Live host disconnected. Your current animation remains open."
		refresh()
		return true
	end

	return false
end

function Live.isJoined()
	return session ~= nil
end

function Live.isOpen()
	return window ~= nil
end

function Live.isBusy()
	return busy() ~= nil
end

function Live.presentationWidget()
	return window and window.docked and window.widget or nil
end

local function join(selectedRoom, attempt)
	local function checkJoin()
		assert(joinAttempt == attempt and not attempt.cancelled, "Live connection was cancelled")
	end

	assert(not session, "Already joined this Live file")
	assert(refs.Active(), "Open an Eclipse file first")
	assert(
		not refs.State.BlenderBridge or not refs.State.BlenderBridge.isLive(),
		"Turn Blender Live off before joining Eclipse Live"
	)
	finishForLive()
	checkJoin()
	local room = selectedRoom or findRoom()
	local created = room == nil
	if room then
		assert(room.Parent and #members(room) > 0, "This Live session has closed")
		assert(
			room:GetAttribute("ProjectId") == projectId(),
			"Open the shared file before joining Live"
		)
	end

	if room then
		assert(
			room:GetAttribute("Protocol") == PROTOCOL,
			"Everyone in this Live file must update and restart Eclipse Live"
		)
		assert(
			refs.State.currentProjectSaved or not History.canUndo(),
			"Save or reopen this file before joining Live"
		)
	else
		assert(refs.Save(), "Save the file before starting Live")
	end

	checkJoin()
	adapter = Adapter.new(refs.State)
	local current = adapter:capture()
	checkJoin()
	if not room then
		room = Instance.new("Folder")
		room.Name = Http:GenerateGUID(false)
		room.Archivable = false
		room:SetAttribute("Protocol", PROTOCOL)
		room:SetAttribute("StartedAt", now())
		room:SetAttribute("ProjectId", projectId())
		room:SetAttribute("FileName", refs.State.currentProjectSave.Name)
		room:SetAttribute("Layout", adapter.signature)
		local seedFolder = Instance.new("Folder")
		seedFolder.Name = "Seed"
		seedFolder.Parent = room
		local records = {}
		for key, value in current do
			records[key] = { n = 0, a = "", v = value }
		end

		Document.publish(seedFolder, records)
		local peers = Instance.new("Folder")
		peers.Name = "Peers"
		peers.Parent = room
		room.Parent = directory(true)
	end

	local seedFolder = room:FindFirstChild("Seed")
	assert(seedFolder, "File is still arriving. Try joining again")
	local seedRecords = Document.receive(seedFolder)
	assert(seedRecords, "File is still arriving. Try joining again")
	checkJoin()
	local seedValues = {}
	for key, record in seedRecords do
		seedValues[key] = record.v
	end

	local peer = Instance.new("Folder")
	peer.Name = Http:GenerateGUID(false)
	peer.Archivable = false
	peer:SetAttribute("Color", Presence.color(tostring(userId) .. ":" .. peer.Name))
	peer:SetAttribute("UserId", userId)
	peer:SetAttribute("UserName", userName)
	peer:SetAttribute("Seen", os.time())
	Preview.begin(refs.State, refs)
	checkJoin()
	History.clear()
	adapter:refresh()
	document = Document.new(peer.Name, seedValues)
	consumed = {}
	for _, other in room.Peers:GetChildren() do
		local packet = readPacket(other)
		if packet then
			document:merge(packet)
		end
	end

	local values = document:values()
	if not Document.equal(values, current) then
		applyShared(values, current)
	end

	checkJoin()
	document.observed = values
	Policy.setLiveChannels(Document.unpack(values.project).channels)
	Presence.claim(peer, room.Peers)
	actor, session = peer, room
	if created then
		room:SetAttribute("Host", peer.Name)
	end

	peer.Parent = room.Peers
	table.insert(sessionConnections, actor:GetAttributeChangedSignal("SyncWith"):Connect(refresh))
	table.insert(sessionConnections, room.Peers.ChildAdded:Connect(refresh))
	table.insert(sessionConnections, room.Peers.ChildRemoved:Connect(refresh))
	generation += 1
	changed = false
	status = nil
	publish()
	refresh()
	stream = Preview.stream(adapter)
	presence = Presence.new(refs.State.Timeline)
	emitTransport()
	Live.afterAdvance()
	local presenceAt, seenAt, validateAt = 0, 0, 0
	renderConnection = Run.RenderStepped:Connect(function(dt)
		if session and not session:GetAttribute("Closed") then
			local stamp = os.clock()
			if Live.isExporting() then
				if stamp - seenAt >= 5 then
					actor:SetAttribute("Seen", os.time())
					seenAt = stamp
				end

				return
			end

			if stamp - presenceAt >= 0.2 then
				local raw = refs.State.Timeline:GetState()
				actor:SetAttribute(
					"Progress",
					Http:JSONEncode({ n = controlNumber, frame = raw.CurrentTime * raw.FPS })
				)
				presenceAt = stamp
			end

			if stamp - seenAt >= 5 then
				actor:SetAttribute("Seen", os.time())
				seenAt = stamp
			end

			presence:update(members(session), actor.Name, actor:GetAttribute("Color"), dt)
			local state = refs.State
			local axis = state.Axis
			local editing = not state.PhysicsSimulating
					and not state.Timeline:GetState().Playing
					and (axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode()) or state.PropertyGizmo and state.PropertyGizmo.isEditing() or state.EffectHandles and state.EffectHandles.isEditing() or state.CameraControls and state.CameraControls.isEditing())
				or false
			if editing and not streamEditing then
				transportDirty = true
			end

			if streamEditing and not editing then
				if not state.PhysicsSimulating and stream then
					stream:publish(actor, true, true)
				end

				changed = true
				editVersion += 1
			end

			streamEditing = editing
			if stream then
				stream:publish(actor, editing)
			end
		end
	end)
	local token = generation
	task.spawn(function()
		while token == generation and session do
			task.wait(1 / 30)
			if token ~= generation then
				break
			end

			local ok, err = pcall(function()
				if endClosedSession() then
					return
				end

				assert(session.Parent and actor.Parent, "Live session closed")
				if not Presence.isCurrent(actor) then
					Live.leave(true)
					status = "This account rejoined Live elsewhere."
					refresh()
					return
				end

				assert(projectId() == session:GetAttribute("ProjectId"), "You switched files")
				assert(
					not refs.State.BlenderBridge or not refs.State.BlenderBridge.isLive(),
					"Blender Live started. Eclipse Live stopped."
				)
				local timeline = refs.State.Timeline
				local raw = timeline:GetState()

				if os.clock() - seenAt >= 5 then
					actor:SetAttribute("Seen", os.time())
					seenAt = os.clock()
				end

				if os.clock() - validateAt >= 5 then
					validateAt = os.clock()

					refresh()
				end

				if busy() then
					return
				end

				synchronize()
			end)
			if not ok then
				local message = tostring(err):gsub("^.-:%d+: ", "")
				if message:find(RETRY, 1, true) then
					continue
				end

				if message:find("Waiting for shared", 1, true) then
					pendingSince = pendingSince or os.clock()
					status = "Waiting for shared rigs / bones..."
					refresh()
					continue
				end

				Live.leave()
				status = message
				refresh()
				break
			end
		end
	end)
end

function Live.join(room)
	assert(not Live.isExporting(), "Wait for module export to finish before joining Live")
	closeInvitation()
	assert(not session, "Already joined this Live file")
	assert(not joinAttempt, "Already connecting to this Live file")
	local attempt = {}
	joinAttempt = attempt
	local ok, err = pcall(join, room, attempt)
	if not ok then
		Live.leave(true)
	end

	if joinAttempt == attempt then
		joinAttempt = nil
	end

	if not ok then
		error(err, 0)
	end
end

local prompt

local function closePrompt()
	if prompt then
		local old = prompt
		prompt = nil
		old:close(true)
	end
end

local function hasUnsavedWork()
	return refs.Active() and not refs.State.currentProjectSaved and History.canUndo()
end

local function besideLive(frame)
	local anchor = window and not window.docked and window.frame
	if not anchor or not anchor.Parent then
		return
	end

	local size = frame.AbsoluteSize
	local screen = anchor.Parent.AbsoluteSize
	local x = anchor.AbsolutePosition.X + anchor.AbsoluteSize.X + 12
	if x + size.X > screen.X - 8 then
		x = anchor.AbsolutePosition.X - size.X - 12
	end

	frame.AnchorPoint = Vector2.zero
	frame.Position = UDim2.fromOffset(
		math.max(8, x),
		math.clamp(anchor.AbsolutePosition.Y, 8, math.max(8, screen.Y - size.Y - 8))
	)
end

local joining = false

function Live.requestJoin(room)
	if session or joining or not room or not room.Parent then
		return
	end

	closePrompt()

	local function enter(saveFirst)
		closePrompt()
		if joining then
			return
		end

		joining = true
		local ok, err = pcall(function()
			refs.Finalize()
			if saveFirst then
				assert(refs.Save(), "Could not save your animation. Try again.")
			end

			if projectId() ~= room:GetAttribute("ProjectId") then
				local saves = require("root").get("EclipseAnimator_Saves", false)
				local save
				for _, candidate in saves and saves:GetChildren() or {} do
					if
						candidate:GetAttribute("EclipseProjectId")
						== room:GetAttribute("ProjectId")
					then
						save = candidate
						break
					end
				end

				assert(save, "The shared file is still arriving. Try joining again.")
				assert(refs.OpenSave, "Update Eclipse to join this file")
				refs.OpenSave(save)
				local deadline = os.clock() + 30
				while
					(
						refs.State.LoadingProject
						or projectId() ~= room:GetAttribute("ProjectId")
						or not refs.Active()
					) and os.clock() < deadline
				do
					task.wait(0.1)
				end

				assert(
					projectId() == room:GetAttribute("ProjectId"),
					"The shared file took too long to open. Try joining again."
				)
			end

			Live.join(room)
			Live.open()
		end)
		joining = false
		if not ok then
			status = (tostring(err):gsub("^.-:%d+: ", ""))
			Notification.show("LIVE", status)
			refresh()
		end
	end

	if not hasUnsavedWork() then
		enter(false)
		return
	end

	prompt = Tool.new(refs, "EclipseLiveSave", "JOIN LIVE", Vector2.new(340, 150), false, function()
		prompt = nil
	end)
	local frame = prompt.frame
	local message = Tool.label(
		frame,
		"Message",
		"You have unsaved changes. Save them before joining "
			.. (room:GetAttribute("FileName") or "this file")
			.. "?",
		UDim2.fromOffset(12, 38),
		UDim2.new(1, -24, 0, 50)
	)
	message.TextWrapped = true
	Tool.button(
		frame,
		"Discard",
		"DON'T SAVE",
		UDim2.new(0, 12, 1, -40),
		UDim2.new(1 / 3, -12, 0, 26),

		function()
			enter(false)
		end
	)
	Tool.button(
		frame,
		"Cancel",
		"CANCEL",
		UDim2.new(1 / 3, 4, 1, -40),
		UDim2.new(1 / 3, -8, 0, 26),
		closePrompt
	)
	local save = Tool.button(
		frame,
		"SaveJoin",
		"SAVE & JOIN",
		UDim2.new(2 / 3, 0, 1, -40),
		UDim2.new(1 / 3, -12, 0, 26),

		function()
			enter(true)
		end
	)
	save:SetAttribute("ThemeBg", "Sel")
	Theme.applyTree(save)
	task.defer(besideLive, frame)
end

local function discover(manual)
	if session or not refs.ScreenGui.Enabled or refs.State.PresentationHidden then
		closeInvitation()
		return
	end

	local rooms = availableRooms()
	if invitation then
		if not invitedRoom or not table.find(rooms, invitedRoom) then
			closeInvitation()
		else
			return
		end
	end

	local room
	for _, candidate in rooms do
		if manual or not dismissed[candidate.Name] then
			room = candidate
			break
		end
	end

	if not room then
		if manual then
			local root = directory(false)
			local incompatible = false
			if root then
				for _, candidate in root:GetChildren() do
					if
						candidate:GetAttribute("Protocol") ~= PROTOCOL
						and #members(candidate) > 0
					then
						incompatible = true
						break
					end
				end
			end

			status = incompatible
					and "Live versions differ. Both creators must update and restart Live."
				or "No sessions found. Both creators must share one Team Create session."
			refresh()
		end

		return
	end

	if manual then
		status = nil
		refresh()
	end

	dismissed[room.Name] = true
	invitedRoom = room
	invitation = Tool.new(refs, "EclipseLiveInvite", "JOIN LIVE", Vector2.new(360, 158), false, function()
		invitation = nil
		invitedRoom = nil
	end
)
	local people = members(room)
	local text = (people[1] and people[1].name or "Someone")
		.. " is editing "
		.. (room:GetAttribute("FileName") or "an animation")
		.. "."
	local label = Tool.label(
		invitation.frame,
		"Message",
		text,
		UDim2.fromOffset(12, 40),
		UDim2.new(1, -24, 0, 50)
	)
	label.TextWrapped = true
	Tool.button(
		invitation.frame,
		"Later",
		"LATER",
		UDim2.new(0, 12, 1, -40),
		UDim2.new(0.5, -18, 0, 26),
		closeInvitation
	)
	local joinButton = Tool.button(
		invitation.frame,
		"Join",
		"JOIN LIVE",
		UDim2.new(0.5, 6, 1, -40),
		UDim2.new(0.5, -18, 0, 26),

		function()
			closeInvitation()
			Live.open()
			Live.requestJoin(room)
		end
	)
	joinButton:SetAttribute("ThemeBg", "Sel")
end

function Live.close()
	if window then
		local old = window
		window = nil
		old:close()
	end

	refresh()
end

function Live.open()
	if window then
		return
	end

	window = Tool.new(refs, "EclipseLive", "LIVE", Vector2.new(440, 350), true, function()
		window = nil
		refresh()
	end)
	local frame = window.frame
	window.file = Tool.label(frame, "File", "", UDim2.fromOffset(12, 38), UDim2.new(1, -24, 0, 24))
	window.file.TextSize = 13
	window.count =
		Tool.label(frame, "Count", "", UDim2.fromOffset(12, 68), UDim2.new(1, -24, 0, 20))
	window.count.TextTransparency = 0.3
	window.list = Tool.make("ScrollingFrame", frame, "Creators", {
		Position = UDim2.fromOffset(12, 156),
		Size = UDim2.new(1, -24, 1, -226),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BackgroundColor3 = Color3.fromRGB(18, 8, 26),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ClipsDescendants = true,
	})
	window.list:SetAttribute("ThemeBg", "Top")
	Tool.make(
		"UIStroke",
		window.list,
		"Outline",
		{ Color = Color3.fromRGB(69, 41, 93), Transparency = 0.4 }
	)
		:SetAttribute("ThemeStrk", "Strk")
	Tool.make(
		"UIListLayout",
		window.list,
		"Rows",
		{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }
	)
	window.empty = Tool.label(
		window.list,
		"Empty",
		"No creators connected",
		UDim2.new(),
		UDim2.new(1, -8, 0, 74)
	)
	window.empty.TextXAlignment = Enum.TextXAlignment.Center
	window.empty.TextTransparency = 0.4
	Tool.button(
		frame,
		"FindLive",
		"FIND LIVE SESSIONS",
		UDim2.fromOffset(12, 94),
		UDim2.new(1, -24, 0, 24),

		function()
			discover(true)
		end
	)
	window.follow, window.followText = Tool.button(
		frame,
		"FollowPlayhead",
		"FOLLOW: OFF",
		UDim2.fromOffset(12, 124),
		UDim2.new(0.5, -18, 0, 24),

		function()
			if following then
				Live.followPlayhead(following)
			elseif session then
				for _, person in members(session) do
					if person.id ~= actor.Name then
						Live.followPlayhead(person.id)
						break
					end
				end
			end

			refresh()
		end
	)
	window.sync, window.syncText = Tool.button(
		frame,
		"SyncPlayhead",
		"SYNC: OFF",
		UDim2.new(0.5, 6, 0, 124),
		UDim2.new(0.5, -18, 0, 24),

		function()
			if session then
				local group = Presence.group(session.Peers, actor.Name)
				local count = 0
				for _ in group do
					count += 1
				end

				if count > 1 then
					Live.syncPlayhead(nil)
				else
					for _, person in members(session) do
						if person.id ~= actor.Name then
							Live.syncPlayhead(person.id)
							break
						end
					end
				end
			end

			refresh()
		end
	)
	window.rows = {}
	window.roomRows = {}
	window.dot = Tool.make(
		"Frame",
		frame,
		"ConnectionDot",
		{ Position = UDim2.new(0, 14, 1, -57), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0 }
	)
	Tool.make("UICorner", window.dot, "Round", { CornerRadius = UDim.new(1, 0) })
	window.status =
		Tool.label(frame, "Status", "OFFLINE", UDim2.new(0, 28, 1, -65), UDim2.new(1, -40, 0, 22))
	window.status.TextSize = 11
	window.error =
		Tool.label(frame, "Error", "", UDim2.new(0, 12, 1, -104), UDim2.new(1, -24, 0, 32))
	window.error:SetAttribute("ThemeTxt", nil)
	window.error.TextColor3 = Color3.fromRGB(239, 145, 156)
	window.error.TextSize = 11
	window.error.TextWrapped = true

	window.action, window.actionText = Tool.button(
		frame,
		"Connect",
		"START LIVE",
		UDim2.new(0, 12, 1, -38),
		UDim2.new(1, -24, 0, 26),

		function()
			if session then
				Live.saveAndLeave()
			else
				local room = findRoom()
				if room then
					Live.requestJoin(room)
					return
				end

				local ok, err = pcall(Live.join)
				if not ok then
					status = tostring(err):gsub("^.-:%d+: ", "")
					refresh()
				end
			end
		end
	)
	refresh()
	local opened = window
	task.spawn(function()
		while window == opened and not opened.closed do
			task.wait(1)
			if window == opened then
				refresh()
			end
		end
	end)
end

function Live.toggle()
	if window then
		Live.close()
	else
		Live.open()
	end
end

function Live.destroy()
	lifetime += 1
	closeInvitation()
	closePrompt()
	Live.leave()
	if window then
		local old = window
		window = nil
		old:close(true)
	end

	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
end

function Live.init(options)
	refs = options
	refs.State.LiveSession = Live
	refs.State.LiveProject = options
	lifetime += 1
	local token = lifetime
	task.spawn(function()
		while token == lifetime do
			task.wait(2)
			if token ~= lifetime then
				break
			end

			local ok, err = pcall(discover, false)
			if not ok and os.clock() - (lastDiscoveryWarning or -math.huge) > 60 then
				lastDiscoveryWarning = os.clock()
				warn("Eclipse Live discovery: " .. tostring(err))
			end
		end
	end)
	userId = 0
	pcall(function()
		userId = Studio:GetUserId()
	end)
	userName = "Creator " .. userId
	task.spawn(function()
		pcall(function()
			userName = Players:GetNameFromUserIdAsync(userId)
		end)
	end)
	unsubscribe = History.subscribe(function()
		if session then
			changed = true
			editVersion += 1
		end
	end)
	refs.ScreenGui.Destroying:Once(Live.destroy)
	refs.Plugin.Unloading:Once(Live.destroy)
	refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not refs.ScreenGui.Enabled then
			Live.leave()
			Live.close()
			closeInvitation()
		end
	end)
	refs.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not refs.AnimatorFrame.Visible and not refs.State.PresentationHidden then
			Live.leave()
			Live.close()
		end
	end)
end

return Live

