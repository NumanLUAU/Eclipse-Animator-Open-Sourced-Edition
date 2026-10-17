--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Events = require("Events")
local Preferences = require("Preferences")
local Organization = require("Organization")
local Sounds = require("Sounds")
local StudioAudio = require("StudioAudio")
local LibraryAudio = require("Audio")
local Playback = {}
local playing = false
local normalActive = false
local closed = false
local preparationVersion = 0
local scrubRequest, scrubWorker
local scrubSerial = 0

local function cancelScrub()
	scrubSerial += 1
	scrubRequest = nil
end

function Playback.scrub(timeline, time)
	if closed or timeline:GetState().Playing or timeline:IsExportLocked() then
		return
	end

	Playback.pause()
	LibraryAudio.stop()
	scrubSerial += 1
	local request = {
		timeline = timeline,
		time = time,
		at = os.clock(),
		serial = scrubSerial,
		version = preparationVersion,
	}
	scrubRequest = request

	local function playLatest()
		local latest = scrubRequest
		if
			not latest
			or latest.version ~= preparationVersion
			or closed
			or playing
			or latest.timeline:GetState().Playing
			or os.clock() - latest.at > 0.2
		then
			return
		end

		Sounds.scrub(latest.timeline, latest.time)
		task.delay(0.12, function()
			if
				scrubRequest == latest
				and not playing
				and not latest.timeline:GetState().Playing
			then
				Sounds.stop()
			end
		end)
	end

	if Sounds.isPrepared() then
		playLatest()
		return
	end

	if scrubWorker then
		return
	end

	local worker = {}
	scrubWorker = worker
	task.spawn(function()
		local ok, ready = pcall(Sounds.prepare, timeline, function()
			return not closed
				and request.version == preparationVersion
				and not playing
				and not timeline:GetState().Playing
		end)
		if scrubWorker == worker then
			scrubWorker = nil
		end

		if not ok then
			warn("Eclipse audio scrub: " .. tostring(ready))
			return
		end

		if ready then
			playLatest()
		end
	end)
end

local lifecycleConnections = {}
local unsubscribe, unsubscribeOrganization, unsubscribeEvents
local enabledTracks = {}
local soundSignature

local function contentSignature(sounds)
	local parts = {}
	for rig, track in Events.all() do
		local content = Events.runtimeSignature(track, sounds)
		if content ~= "" and rig.Parent and Events.isEnabled(track) then
			table.insert(parts, tostring(rig) .. content)
		end
	end

	table.sort(parts)
	return table.concat(parts, "|")
end

local function rememberEnabledTracks()
	for rig, track in Events.all() do
		enabledTracks[rig] = Events.isEnabled(track)
	end
end

function Playback.attach(plugin, gui)
	StudioAudio.attach(plugin)

	local function close()
		closed = true
		Playback.clear()
		LibraryAudio.stop()
		StudioAudio.destroy()
		for _, connection in lifecycleConnections do
			connection:Disconnect()
		end

		table.clear(lifecycleConnections)
		if unsubscribe then
			unsubscribe()
			unsubscribe = nil
		end

		if unsubscribeOrganization then
			unsubscribeOrganization()
			unsubscribeOrganization = nil
		end

		if unsubscribeEvents then
			unsubscribeEvents()
			unsubscribeEvents = nil
		end
	end

	table.insert(lifecycleConnections, plugin.Unloading:Connect(close))
	table.insert(lifecycleConnections, gui.Destroying:Connect(close))
	table.insert(
		lifecycleConnections,
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not gui.Enabled then
				Playback.clear()
			end
		end)
	)
end

local reached = Instance.new("BindableEvent")
Playback.MarkerReached = reached.Event

function Playback.pause()
	if not normalActive then
		return
	end

	normalActive = false
	playing = false
	preparationVersion += 1
	cancelScrub()
	Sounds.stop()
end

function Playback.stop()
	cancelScrub()
	normalActive = false
	playing = false
	preparationVersion += 1
	Sounds.clear()
end

function Playback.disable()
	cancelScrub()
	preparationVersion += 1
	Sounds.clear()
end

function Playback.suspend()
	Playback.clear()
end

function Playback.preview(timeline, time, isPlaying, continuous, posedRig, posedTime)
	if closed then
		return
	end

	if soundSignature == nil then
		soundSignature = contentSignature(true)
	end

	rememberEnabledTracks()
	return true
end

function Playback.prepare(timeline, time, posedRig, posedTime, isCurrent)
	cancelScrub()
	normalActive = true
	LibraryAudio.stop()
	rememberEnabledTracks()
	local version = preparationVersion
	if
		not Sounds.prepare(timeline, function()
			return not closed and version == preparationVersion and isCurrent()
		end)
	then
		return false
	end

	return not closed and version == preparationVersion and isCurrent()
end

local function process(timeline, first, last, inclusive)
	local fps = timeline:GetState().FPS
	local due = {}
	for _, track in Events.all() do
		if not Events.isEnabled(track) or not track.Rig.Parent then
			continue
		end

		for _, entry in Events.range(track, first, last, inclusive, fps, false) do
			table.insert(due, entry)
		end
	end

	table.sort(due, function(a, b)
		return a.time < b.time or a.time == b.time and a.event.Id < b.event.Id
	end)
	Playback.didFire = #due > 0 or Playback.didFire
	for _, entry in due do
		const event = entry.event
		if type(event.CodeBegin) == "string" and event.CodeBegin:match("%S") or type(event.CodeEnd) == "string" and event.CodeEnd:match("%S") then
			require("Notification").showOnce("LUA PREVIEW UNAVAILABLE", "Custom Lua event previews are temporarily unavailable. Your code is still saved and included in module exports.", 7, "EclipseLuaPreviewUnavailable")
		end

		Sounds.play(entry.rig, entry.event, math.max(0, last - entry.time), timeline)
		for _, marker in Events.markers(entry.event) do
			if marker.Name ~= "" then
				reached:Fire(entry.rig, marker.Name, marker.Parameter)
			end
		end
	end
end

function Playback.advance(timeline, startTime, dt, finish, looping, first)
	first = math.clamp(first or 0, 0, math.max(0, finish - 1e-6))
	normalActive = true
	Playback.didFire = false
	local inclusive = not playing
	if inclusive then
		Sounds.resume(timeline, startTime)
	end

	playing = true
	local stop = startTime + dt
	if not looping or finish <= 0 then
		process(timeline, startTime, math.min(stop, finish), inclusive)
		if stop >= finish then
			playing = false
		end

		return
	end

	local from = startTime
	while stop >= finish do
		process(timeline, from, finish, inclusive)
		Sounds.stop()
		stop -= finish - first
		from = first
		inclusive = true
	end

	process(timeline, from, stop, inclusive)
end

function Playback.clear()
	cancelScrub()
	normalActive = false
	playing = false
	preparationVersion += 1
	Sounds.clear()
end

unsubscribeEvents = Events.subscribe(function()
	if closed then
		return
	end

	local sounds = contentSignature(true)
	if soundSignature ~= nil and sounds ~= soundSignature then
		preparationVersion += 1
		Sounds.clear()
	end

	soundSignature = sounds
end)
unsubscribe = Preferences.subscribe(function(key)
	if
		closed
		or (key ~= "VFXFollowsFPS" and key ~= "DefaultFPS")
	then
		return
	end

	playing = false
	preparationVersion += 1
	Sounds.clear()
end)
unsubscribeOrganization = Organization.subscribe(function()
	local nextEnabled, changed = {}, false
	for rig, track in Events.all() do
		local enabled = Events.isEnabled(track)
		nextEnabled[rig] = enabled
		local previous = enabledTracks[rig]
		if previous == nil then
			previous = track.Enabled ~= false
		end

		if previous ~= enabled then
			changed = true
		end
	end

	for rig, enabled in enabledTracks do
		if enabled and nextEnabled[rig] == nil then
			changed = true
		end
	end

	enabledTracks = nextEnabled
	if changed and not closed then
		preparationVersion += 1
		Sounds.clear()
	end
end)
return Playback
