--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local SubtitleData = require("SubtitleData")
local EmitData = require("ClipboardRows")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local State = require("State")
local Preferences = require("Preferences")
local TrackOrganization = require("Organization")

local SoundData = require("SoundData")

local Events = {}
local runtimeCache = setmetatable({}, { __mode = "k" })

local function trackCache(track)
	local cache = runtimeCache[track]
	if not cache or cache.revision ~= track.Revision or cache.events ~= track.Events then
		cache = { revision = track.Revision, events = track.Events }
		runtimeCache[track] = cache
	end

	return cache
end

function Events.range(track, first, last, inclusive, fps, phases)
	local cache = trackCache(track)
	local kind = phases and "phaseIndex" or "frameIndex"
	local index = cache[kind]
	if not index then
		index = {}
		for _, event in track.Events do
			if event.Enabled ~= false then
				if phases then
					if event.CodeBegin ~= "" then
						table.insert(index, { frame = event.Frame, event = event, phase = "begin" })
					end

					if event.CodeEnd ~= "" then
						table.insert(
							index,
							{ frame = event.Frame + event.Duration, event = event, phase = "end" }
						)
					end
				else
					table.insert(index, { frame = event.Frame, event = event })
				end
			end
		end

		table.sort(index, function(a, b)
			return a.frame < b.frame
		end)
		cache[kind] = index
	end

	local low, high = 1, #index
	while low <= high do
		local mid = (low + high) // 2
		local time = index[mid].frame / fps
		if time > first or inclusive and time == first then
			high = mid - 1
		else
			low = mid + 1
		end
	end

	local result = {}
	for i = low, #index do
		local row = index[i]
		local time = row.frame / fps
		if time > last then
			break
		end

		table.insert(
			result,
			{ time = time, event = row.event, phase = row.phase, track = track, rig = track.Rig }
		)
	end

	return result
end

function Events.vfxDisabled()
	require("Notification").show("VFX DISABLED", "Event VFX is temporarily disabled.")
end

local function stable(value)
	if type(value) ~= "table" then
		return HttpService:JSONEncode(value)
	end

	local keys, parts = {}, {}
	for key in value do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, key in keys do
		table.insert(parts, stable(key) .. ":" .. stable(value[key]))
	end

	return "{" .. table.concat(parts, ",") .. "}"
end

function Events.runtimeSignature(track, sounds)
	local cache = trackCache(track)
	local kind = sounds and "sounds" or "vfx"
	if cache[kind] then
		return cache[kind]
	end

	local entries = {}
	for id, event in track.Events do
		local active = sounds and SoundData.has(event.Sounds)
			or not sounds
				and (event.CodeBegin ~= "" or event.CodeEnd ~= "")
		if event.Enabled == false or not active then
			continue
		end

		local content
		if sounds then
			content = SoundData.copy(event.Sounds)

			for _, sound in content do
				sound.Duration = nil
				sound.LocalName = nil
			end
		else
			content = { event.CodeBegin, event.CodeEnd }
		end

		table.insert(
			entries,
			stable({
				id,
				event.Frame,
				event.Duration,
				Events.normalizeSpeed(event.Speed),
				event.Name,
				event.Parameter,
				Events.markers(event),
				content,
			})
		)
	end

	table.sort(entries)
	cache[kind] = table.concat(entries, "|")
	return cache[kind]
end

local listeners = {}

function Events.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

local function notifyChanged()
	for callback in listeners do
		callback()
	end
end

local tracks = {}
local documentId
local subtitleOwner
local FOLDER_NAME = "EclipseEvents"
local RECOVERY_NAME = "EclipseEventRecovery"

local function frameNumber(value)
	value = tonumber(value)
	if not value or value ~= value or math.abs(value) == math.huge then
		return 0
	end

	return math.max(0, math.floor(value + 0.5))
end

local function separate(track)
	if track.ProjectSubtitles then
		return false
	end

	local entries, occupied, duplicates = {}, {}, {}
	for _, event in track.Events do
		table.insert(entries, event)
	end

	table.sort(entries, function(a, b)
		return a.Frame < b.Frame or a.Frame == b.Frame and a.Id < b.Id
	end)
	for _, event in entries do
		if occupied[event.Frame] then
			table.insert(duplicates, event)
		else
			occupied[event.Frame] = true
		end
	end

	for _, event in duplicates do
		local frame = event.Frame + 1
		while occupied[frame] do
			frame += 1
		end

		event.Frame = frame
		occupied[frame] = true
	end

	return #duplicates > 0
end

function Events.nextFrame(track, frame, except)
	frame = frameNumber(frame)
	if track.ProjectSubtitles then
		return frame
	end

	local occupied = {}
	for id, event in track.Events do
		if id ~= except then
			occupied[event.Frame] = true
		end
	end

	while occupied[frame] do
		frame += 1
	end

	return frame
end

function Events.move(track, entries, offset)
	local moving, occupied, ordered = {}, {}, {}
	for _, entry in entries do
		if entry.track == track then
			moving[entry.event.Id] = true
			table.insert(ordered, entry)
		end
	end

	for id, event in track.Events do
		if not moving[id] then
			occupied[event.Frame] = true
		end
	end

	table.sort(ordered, function(a, b)
		return a.frame < b.frame or a.frame == b.frame and a.event.Id < b.event.Id
	end)
	for _, entry in ordered do
		local frame = frameNumber(entry.frame + offset)
		while occupied[frame] do
			frame += 1
		end

		if entry.event.Frame ~= frame then
			track.Revision = (track.Revision or 0) + 1
		end

		entry.event.Frame = frame
		occupied[frame] = true
	end
end

local function textValue(parent, name, value)
	value = value or ""
	if #value < 190000 then
		local item = Instance.new("StringValue")
		item.Name, item.Value, item.Parent = name, value, parent
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	local first, index = 1, 1
	while first <= #value do
		local last = math.min(first + 99999, #value)
		while
			last < #value
			and string.byte(value, last + 1) >= 128
			and string.byte(value, last + 1) < 192
		do
			last -= 1
		end

		local item = Instance.new("StringValue")
		item.Name = string.format("%06d", index)
		item.Value = string.sub(value, first, last)
		item.Parent = folder
		first, index = last + 1, index + 1
	end

	folder.Parent = parent
end

local function readText(parent, name)
	local item = parent:FindFirstChild(name)
	if not item then
		return ""
	end

	if item:IsA("StringValue") then
		return item.Value
	end

	local chunks = item:GetChildren()
	table.sort(chunks, function(a, b)
		return a.Name < b.Name
	end)
	local result = {}
	for _, chunk in chunks do
		if chunk:IsA("StringValue") then
			table.insert(result, chunk.Value)
		end
	end

	return table.concat(result)
end

local function identity(rig)
	local id = rig:GetAttribute("EclipseEventRigId")
	if not id then
		id = HttpService:GenerateGUID(false)
		rig:SetAttribute("EclipseEventRigId", id)
	end

	return id
end

local function getDocument(sequence)
	local id = sequence and sequence:GetAttribute("EclipseEventDocumentId")
	if not id then
		id = documentId or HttpService:GenerateGUID(false)
		if sequence then
			sequence:SetAttribute("EclipseEventDocumentId", id)
		end
	end

	documentId = id
	return id
end

function Events.normalizeSpeed(value)
	value = tonumber(value)
	if not value or value ~= value or math.abs(value) == math.huge then
		return 1
	end

	return math.clamp(value, 0.01, 100)
end

function Events.speed(event, fps)
	local basis = Preferences.get("VFXFollowsFPS") and fps / Preferences.get("DefaultFPS") or 1
	return Events.normalizeSpeed(event.Speed) * basis
end

function Events.markers(event)
	local result = {}
	if type(event.Markers) == "table" then
		for _, marker in event.Markers do
			table.insert(
				result,
				{ Name = tostring(marker.Name or ""), Parameter = tostring(marker.Parameter or "") }
			)
		end
	else
		table.insert(result, { Name = event.Name or "", Parameter = event.Parameter or "" })
	end

	return result
end

function Events.setMarkers(event, markers)
	event.Markers = Events.markers({ Markers = markers })
	local first = event.Markers[1]
	event.Name = first and first.Name or ""
	event.Parameter = first and first.Parameter or ""
end

function Events.copyFaces(keys)
	local result = {}
	for id, key in keys or {} do
		if
			type(key) == "table"
			and type(key.Frame) == "number"
			and key.Frame == key.Frame
			and key.Frame < math.huge
			and type(key.Image) == "string"
		then
			result[tostring(id)] =
				{ Id = tostring(id), Frame = frameNumber(key.Frame), Image = key.Image }
		end
	end

	return result
end

function Events.snapshot(track)
	local result = {
		Enabled = track.Enabled,
		FacesEnabled = track.FacesEnabled == true,
		FaceKeys = Events.copyFaces(track.FaceKeys),
		Revision = track.Revision or 0,
		Events = {},
	}
	for id, event in track.Events do
		result.Events[id] = {
			Id = id,
			Frame = event.Frame,
			Duration = event.Duration,
			Name = event.Name,
			Speed = Events.normalizeSpeed(event.Speed),
			Markers = Events.markers(event),
			Parameter = event.Parameter,
			CodeBegin = event.CodeBegin,
			CodeEnd = event.CodeEnd,
			Sounds = SoundData.copy(event.Sounds),
			Emits = EmitData.copy(event.Emits),
			Subtitle = SubtitleData.copy(event.Subtitle),
			Enabled = event.Enabled ~= false,
		}
	end

	return result
end

function Events.write(target, track)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder:SetAttribute("Version", 8)
	folder:SetAttribute("ProjectSubtitles", track.ProjectSubtitles == true)
	folder:SetAttribute("FacesEnabled", track.FacesEnabled == true)
	textValue(folder, "FaceKeys", HttpService:JSONEncode(Events.copyFaces(track.FaceKeys)))
	folder:SetAttribute(
		"FPS",
		State.Timeline and State.Timeline:GetState().FPS or Preferences.get("DefaultFPS")
	)
	folder:SetAttribute("DefaultFPS", Preferences.get("DefaultFPS"))
	folder:SetAttribute("VFXFollowsFPS", Preferences.get("VFXFollowsFPS"))
	folder:SetAttribute("Enabled", track.Enabled ~= false)
	folder:SetAttribute("Revision", track.Revision or 0)
	for id, event in track.Events do
		local item = Instance.new("Folder")
		item.Name = id
		item:SetAttribute("Frame", event.Frame)
		item:SetAttribute("Duration", event.Duration or 0)
		item:SetAttribute("Speed", Events.normalizeSpeed(event.Speed))
		item:SetAttribute("EventName", event.Name or "")
		item:SetAttribute("Parameter", event.Parameter or "")
		item:SetAttribute("Enabled", event.Enabled ~= false)
		textValue(item, "Markers", HttpService:JSONEncode(Events.markers(event)))
		textValue(item, "CodeBegin", event.CodeBegin)
		textValue(item, "CodeEnd", event.CodeEnd)
		SoundData.write(item, event.Sounds)
		textValue(item, "Emits", HttpService:JSONEncode(EmitData.copy(event.Emits)))
		if event.Subtitle then
			textValue(item, "Subtitle", HttpService:JSONEncode(SubtitleData.copy(event.Subtitle)))
		end

		item.Parent = folder
	end

	local previous = target:FindFirstChild(FOLDER_NAME)
	folder.Parent = target
	if previous then
		previous:Destroy()
	end

	target:SetAttribute("EclipseEventDocumentId", track.DocumentId)
	return folder
end

local function read(folder)
	local track = {
		Enabled = folder:GetAttribute("Enabled") ~= false,
		FacesEnabled = folder:GetAttribute("FacesEnabled") == true,
		Revision = folder:GetAttribute("Revision") or 0,
		Events = {},
	}
	local ok, keys = pcall(HttpService.JSONDecode, HttpService, readText(folder, "FaceKeys"))
	track.FaceKeys = Events.copyFaces(ok and type(keys) == "table" and keys or {})
	if
		folder:GetAttribute("FacesEnabled") == nil
		or (folder:GetAttribute("Version") or 0) < 6
			and track.FacesEnabled
			and not next(track.FaceKeys)
	then
		track.FacesEnabled = Preferences.get("FacesByDefault") == true
	end

	for _, item in folder:GetChildren() do
		if not item:IsA("Folder") then
			continue
		end

		local subtitleOK, subtitle =
			pcall(HttpService.JSONDecode, HttpService, readText(item, "Subtitle"))
		local emitOK, emitRows = pcall(HttpService.JSONDecode, HttpService, readText(item, "Emits"))
		local frame = item:GetAttribute("Frame")
		if typeof(frame) ~= "number" then
			continue
		end

		track.Events[item.Name] = {
			Id = item.Name,
			Frame = frameNumber(frame),
			Duration = frameNumber(item:GetAttribute("Duration")),
			Speed = Events.normalizeSpeed(item:GetAttribute("Speed")),
			Name = item:GetAttribute("EventName") or "",
			Parameter = item:GetAttribute("Parameter") or "",
			Enabled = item:GetAttribute("Enabled") ~= false,
			CodeBegin = readText(item, "CodeBegin"),
			CodeEnd = readText(item, "CodeEnd"),
			Sounds = SoundData.read(item),
			Emits = EmitData.copy(emitOK and emitRows or nil),
			Subtitle = SubtitleData.copy(subtitleOK and subtitle or nil),
		}
	end

	for _, item in folder:GetChildren() do
		local event = track.Events[item.Name]
		local encoded = readText(item, "Markers")
		if event and encoded ~= "" then
			local ok, markers = pcall(HttpService.JSONDecode, HttpService, encoded)
			if ok and type(markers) == "table" then
				Events.setMarkers(event, markers)
			end
		end
	end

	track.ProjectSubtitles = folder:GetAttribute("ProjectSubtitles") == true
	track.Relocated = separate(track)
	return track
end

local function recovery(track, create)
	local rigObject = require("rig").original(track.Rig)
	local root = require("root").get(RECOVERY_NAME, create)
	if not root then
		return nil
	end

	local key = track.DocumentId .. "_" .. identity(rigObject)
	local entry = root:FindFirstChild(key)
	if
		entry
		and entry:FindFirstChild("Rig")
		and entry.Rig.Value
		and entry.Rig.Value ~= rigObject
	then
		rigObject:SetAttribute("EclipseEventRigId", HttpService:GenerateGUID(false))
		key = track.DocumentId .. "_" .. identity(rigObject)
		entry = root:FindFirstChild(key)
	end

	if not entry and create then
		entry = Instance.new("Folder")
		entry.Name = key
		local rig = Instance.new("ObjectValue")
		rig.Name, rig.Value, rig.Parent = "Rig", rigObject, entry
		entry.Parent = root
	end

	return entry
end

function Events.get(rig)
	if tracks[rig] then
		return tracks[rig]
	end

	local sequence = State.currentProjectSequence
	if not sequence then
		local root = require("root").get(RECOVERY_NAME, false)
		local latest
		for _, entry in root and root:GetChildren() or {} do
			local ref, data = entry:FindFirstChild("Rig"), entry:FindFirstChild(FOLDER_NAME)
			if
				ref
				and ref.Value == require("rig").original(rig)
				and data
				and entry:GetAttribute("Active")
				and entry:GetAttribute("Unsaved")
				and (not documentId or entry:GetAttribute("EclipseEventDocumentId") == documentId)
				and (
					not latest
					or (data:GetAttribute("Revision") or 0)
						> (latest.EclipseEvents:GetAttribute("Revision") or 0)
				)
			then
				latest = entry
			end
		end

		if latest then
			local restored = read(latest.EclipseEvents)
			restored.Rig, restored.DocumentId = rig, getDocument(latest)
			tracks[rig] = restored
			State.currentProjectSaved = false
			return restored
		end
	end

	local track = {
		Rig = rig,
		Enabled = not require("CameraRig").isRig(rig)
			and rig:GetAttribute("EclipseEffectObject") ~= 1,
		FacesEnabled = Preferences.get("FacesByDefault") == true,
		Events = {},
		Revision = 0,
		DocumentId = getDocument(sequence),
		Saved = sequence ~= nil,
	}
	tracks[rig] = track
	return track
end

function Events.subtitleTrack()
	if not subtitleOwner or not subtitleOwner.Parent then
		subtitleOwner = require("root").get("EclipseSubtitleTrack", true)
	end

	local track = Events.get(subtitleOwner)
	track.ProjectSubtitles = true
	track.Enabled = true
	track.FacesEnabled = false
	track.FaceKeys = {}
	return track
end

function Events.migrateSubtitles(source)
	if source.ProjectSubtitles then
		return
	end

	local target
	for id, event in table.clone(source.Events) do
		if not event.Subtitle then
			continue
		end

		target = target or Events.subtitleTrack()
		local cueId = identity(source.Rig) .. ":" .. id
		if not target.Events[cueId] then
			target.Events[cueId] = {
				Id = cueId,
				Frame = event.Frame,
				Duration = 0,
				Speed = 1,
				Name = "Subtitle",
				Parameter = "",
				Markers = {},
				Sounds = {},
				Emits = {},
				CodeBegin = "",
				CodeEnd = "",
				Enabled = event.Enabled ~= false,
				Subtitle = SubtitleData.copy(event.Subtitle),
			}
		end

		event.Subtitle = nil
		if
			#Events.markers(event) == 0
			and #(event.Emits or {}) == 0
			and not SoundData.has(event.Sounds)
			and event.CodeBegin == ""
			and event.CodeEnd == ""
		then
			source.Events[id] = nil
		end
	end

	if target then
		source.Revision = (source.Revision or 0) + 1
		target.Revision = (target.Revision or 0) + 1
	end
end

function Events.loadSubtitles(sequence, options)
	local folder = sequence and sequence:FindFirstChild("EclipseSubtitles")
	if not folder or not folder:FindFirstChild(FOLDER_NAME) then
		return
	end

	local current = Events.subtitleTrack()
	local loaded = Events.load(current.Rig, folder, State.Timeline:GetState().FPS, options)
	loaded.ProjectSubtitles = true
	for id, event in current.Events do
		if not loaded.Events[id] then
			loaded.Events[id] = event
			loaded.Revision = (loaded.Revision or 0) + 1
		end
	end

	return loaded
end

function Events.writeSubtitles(target)
	local track = Events.subtitleTrack()
	local folder = Instance.new("Folder")
	folder.Name = "EclipseSubtitles"
	Events.write(folder, track)
	local previous = target:FindFirstChild(folder.Name)
	folder.Parent = target
	if previous then
		previous:Destroy()
	end

	if not target:IsA("KeyframeSequence") then
		return
	end

	local fps = State.Timeline:GetState().FPS
	local keys = {}
	for _, key in target:GetKeyframes() do
		keys[math.round(key.Time * fps)] = key
	end

	for _, event in track.Events do
		if event.Enabled == false or not event.Subtitle then
			continue
		end

		local key = keys[event.Frame]
		if not key then
			key = Instance.new("Keyframe")
			key.Time = event.Frame / fps
			key.Parent = target
			keys[event.Frame] = key
		end

		local marker = Instance.new("KeyframeMarker")
		marker.Name = "EclipseSubtitle"
		marker.Value = HttpService:JSONEncode({
			Version = 1,
			FPS = fps,
			Cue = SubtitleData.copy(event.Subtitle),
		})
		marker.Parent = key
	end
end

function Events.all()
	return tracks
end

function Events.isEnabled(track)
	return track.Enabled ~= false and TrackOrganization.isEnabled(track.Rig)
end

function Events.detach(rig)
	local track = tracks[rig]
	if not track then
		return nil
	end

	tracks[rig] = nil
	notifyChanged()
	local draft = recovery(track, false)
	if draft then
		draft:SetAttribute("Active", false)
	end

	return track
end

function Events.attach(rig, track)
	if not track then
		return nil
	end

	track.Rig = rig
	tracks[rig] = track
	notifyChanged()
	local draft = recovery(track, false)
	if draft then
		draft:SetAttribute("Active", true)
	end

	return track
end

function Events.changed(track)
	separate(track)
	track.Revision = math.max((track.Revision or 0) + 1, DateTime.now().UnixTimestampMillis)
	local draft = recovery(track, true)
	Events.write(draft, track)
	draft:SetAttribute("Active", true)
	draft:SetAttribute("Unsaved", track.Saved ~= true)
	State.currentProjectSaved = false
	notifyChanged()
end

function Events.restore(track, snapshot)
	track.Enabled, track.Revision = snapshot.Enabled, snapshot.Revision
	track.Events = Events.snapshot(snapshot).Events
	track.FaceKeys, track.FacesEnabled =
		Events.copyFaces(snapshot.FaceKeys), snapshot.FacesEnabled == true
	Events.changed(track)
end

function Events.create(track, frame)
	local event = {
		Id = HttpService:GenerateGUID(false),
		Frame = Events.nextFrame(track, frame),
		Duration = 0,
		Speed = 1,
		Sounds = {},
		Name = "Event",
		Parameter = "",
		Enabled = true,
		CodeBegin = "",
		CodeEnd = "",
	}
	track.Events[event.Id] = event
	Events.changed(track)
	return event
end

function Events.load(rig, sequence, fps, options)
	local id = options and options.DocumentId or getDocument(sequence)
	local folder = sequence:FindFirstChild(FOLDER_NAME)
	local track = folder and read(folder)
		or {
			Enabled = not require("CameraRig").isRig(rig)
				and rig:GetAttribute("EclipseEffectObject") ~= 1,
			FacesEnabled = Preferences.get("FacesByDefault") == true,
			FaceKeys = {},
			Events = {},
			Revision = 0,
		}
	track.Rig, track.DocumentId, track.Saved = rig, id, true
	if not folder then
		local byFrame = {}
		for _, key in sequence:GetKeyframes() do
			local frame = frameNumber(key.Time * fps)
			for _, marker in key:GetMarkers() do
				local event = byFrame[frame]
				if not event then
					local eventId = HttpService:GenerateGUID(false)
					event = {
						Id = eventId,
						Frame = frame,
						Duration = 0,
						Speed = 1,
						Sounds = {},
						Markers = {},
						Enabled = true,
						CodeBegin = "",
						CodeEnd = "",
					}
					track.Events[eventId] = event
					byFrame[frame] = event
				end

				table.insert(event.Markers, { Name = marker.Name, Parameter = marker.Value })
			end
		end

		for _, event in byFrame do
			Events.setMarkers(event, event.Markers)
		end
	end

	local draft = recovery(track, false)
	local draftFolder = not (options and options.IgnoreRecovery)
		and draft
		and draft:FindFirstChild(FOLDER_NAME)
	if draftFolder and (draftFolder:GetAttribute("Revision") or 0) > track.Revision then
		local restored = read(draftFolder)
		track.Enabled, track.Events, track.Revision =
			restored.Enabled, restored.Events, restored.Revision
		track.FaceKeys, track.FacesEnabled = restored.FaceKeys, restored.FacesEnabled
		track.Relocated = restored.Relocated
		State.currentProjectSaved = false
		track.Recovered = true
	end

	if track.Relocated then
		track.Recovered = true
		Events.changed(track)
	end

	tracks[rig] = track
	if not track.ProjectSubtitles then
		Events.migrateSubtitles(track)
	end

	return track
end

function Events.export(rig, sequence, fps)
	local track = Events.get(rig)
	local folder = Events.write(sequence, track)
	folder:SetAttribute("FPS", fps)
	if not Events.isEnabled(track) then
		return
	end

	local byFrame = {}
	for _, key in sequence:GetKeyframes() do
		byFrame[math.floor(key.Time * fps + 0.5)] = key
	end

	for _, event in track.Events do
		if event.Enabled == false then
			continue
		end

		local key = byFrame[event.Frame]
		if not key then
			key = Instance.new("Keyframe")
			key.Name, key.Time, key.Parent = "Keyframe", event.Frame / fps, sequence
			byFrame[event.Frame] = key
		end

		if event.Subtitle then
			local subtitleMarker = Instance.new("KeyframeMarker")
			subtitleMarker.Name = "EclipseSubtitle"
			subtitleMarker.Value = HttpService:JSONEncode({
				Version = 1,
				FPS = fps,
				Cue = SubtitleData.copy(event.Subtitle),
			})
			subtitleMarker.Parent = key
		end

		for _, value in Events.markers(event) do
			if value.Name == "" then
				continue
			end

			local marker = Instance.new("KeyframeMarker")
			marker.Name, marker.Value, marker.Parent = value.Name, value.Parameter, key
		end

		if event.Duration > 0 and event.CodeEnd ~= "" then
			local finish = event.Frame + event.Duration
			if not byFrame[finish] then
				local ending = Instance.new("Keyframe")
				ending.Name, ending.Time, ending.Parent = "Keyframe", finish / fps, sequence
				byFrame[finish] = ending
			end
		end
	end
end

function Events.lastFrame(enabledOnly, keysOnly)
	local last
	for _, track in tracks do
		for _, key in track.FaceKeys or {} do
			if
				not enabledOnly
				or track.FacesEnabled == true and TrackOrganization.isEnabled(track.Rig)
			then
				last = math.max(last or 0, key.Frame)
			end
		end

		if enabledOnly and not Events.isEnabled(track) then
			continue
		end

		for _, event in track.Events do
			if enabledOnly and event.Enabled == false then
				continue
			end

			local fps = State.Timeline and State.Timeline:GetState().FPS
				or Preferences.get("DefaultFPS")
			local frame = event.Frame
				+ math.max(
					event.CodeEnd ~= "" and event.Duration or 0,
					keysOnly and 0 or SoundData.frames(event.Sounds, fps),
					event.Subtitle and event.Subtitle.Duration or 0
				)
			last = math.max(last or 0, frame)
		end
	end

	return last
end

function Events.hasRecovered()
	for _, track in tracks do
		if track.Recovered then
			return true
		end
	end

	return false
end

function Events.forkDocument()
	local previousDocument = documentId
	local previous = {}
	local drafts = {}
	for _, track in tracks do
		previous[track] = track.DocumentId
		if track.Rig and track.Rig.Parent then
			local ok, draft = pcall(recovery, track, false)
			if ok and draft and draft:GetAttribute("Unsaved") then
				draft:SetAttribute("Unsaved", false)
				table.insert(drafts, draft)
			end
		end
	end

	documentId = HttpService:GenerateGUID(false)
	for track in previous do
		track.DocumentId = documentId
	end

	return function()
		documentId = previousDocument
		for track, id in previous do
			track.DocumentId = id
		end

		for _, draft in drafts do
			if draft.Parent then
				draft:SetAttribute("Unsaved", true)
			end
		end
	end
end

function Events.saved(rigs)
	rigs = table.clone(rigs)
	if subtitleOwner then
		table.insert(rigs, subtitleOwner)
	end

	for _, rig in rigs do
		local track = tracks[rig]
		if track then
			track.Saved = true
			track.Recovered = false
			local draft = recovery(track, false)
			if draft then
				draft:SetAttribute("Unsaved", false)
			end
		end
	end
end

function Events.clear()
	for _, track in tracks do
		local draft = recovery(track, false)
		if draft then
			draft:SetAttribute("Active", false)
		end
	end

	table.clear(tracks)

	documentId = HttpService:GenerateGUID(false)
	table.clear(runtimeCache)
	notifyChanged()
end

return Events
