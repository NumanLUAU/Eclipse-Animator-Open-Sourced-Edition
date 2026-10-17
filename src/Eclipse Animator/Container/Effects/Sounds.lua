--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local StudioAudio = require("StudioAudio")
local Data = require("SoundData")
local Events = require("Events")
local LocalAudio = require("LocalAudio")
local Sounds = {}
local active = {}
local prepared = {}
local version = 0
local ready = false

function Sounds.isPrepared()
	return ready
end

local function stop(entry)
	active[entry] = nil
	entry.sound:Stop()
end

function Sounds.stop()
	for entry in active do
		stop(entry)
	end
end

function Sounds.clear()
	ready = false
	version += 1
	Sounds.stop()
	for _, entries in prepared do
		for _, entry in entries do
			for _, connection in entry.connections do
				connection:Disconnect()
			end

			entry.sound:Destroy()
		end
	end

	table.clear(prepared)
end

function Sounds.prepare(timeline, isCurrent)
	Sounds.clear()
	local currentVersion = version
	local parent = StudioAudio.parent()
	local pending, updates = {}, {}
	local missingLocal = false

	local function current()
		return currentVersion == version and isCurrent()
	end

	for _, track in Events.all() do
		if not Events.isEnabled(track) or not track.Rig.Parent then
			continue
		end

		for _, event in track.Events do
			if event.Enabled == false then
				continue
			end

			local entries = {}
			prepared[event] = entries
			for index, data in event.Sounds or {} do
				local id = Data.playback(data)
				if not id and LocalAudio.is(data.AudioId) then
					missingLocal = true
				end

				if not id then
					continue
				end

				if not parent then
					Sounds.clear()
					return false
				end

				local sound = Instance.new("Sound")

				sound.Name = "EclipseEventSound"
				sound.SoundId = id
				sound.Looped = data.Looped == true
				sound.Volume = Data.volume(data.Volume)
				sound.PlaybackSpeed = Data.speed(data.Speed)
				sound.Archivable = false
				local entry = { sound = sound, rig = track.Rig, connections = {} }
				entries[index] = entry
				table.insert(
					entry.connections,
					sound.Ended:Connect(function()
						if not sound.Playing then
							stop(entry)
						end
					end)
				)
				table.insert(
					entry.connections,
					track.Rig.AncestryChanged:Connect(function()
						if not track.Rig.Parent then
							stop(entry)
						end
					end)
				)
				sound.Parent = parent
				table.insert(pending, sound)
				table.insert(
					updates,
					{ track = track, event = event, index = index, data = data, sound = sound }
				)
			end
		end
	end

	if missingLocal then
		require("Notification").show(
			"LOCAL AUDIO",
			"Reselect the local audio file in its sound event to hear it in this Studio session."
		)
	end

	if not StudioAudio.preload(pending, current) then
		if currentVersion == version then
			Sounds.clear()
		end

		return false
	end

	local changed = {}
	for _, entry in updates do
		if
			entry.event.Sounds[entry.index] == entry.data
			and entry.sound.TimeLength > 0
			and entry.data.Duration ~= entry.sound.TimeLength
		then
			entry.data.Duration = entry.sound.TimeLength
			changed[entry.track] = true
		end
	end

	for track in changed do
		Events.changed(track)
	end

	if next(changed) then
		timeline:RefreshEventRows()
	end

	ready = current()
	return ready
end

function Sounds.play(rig, event, elapsed, timeline)
	local entries = prepared[event]
	for index, data in event.Sounds or {} do
		local id = Data.playback(data)
		if not id then
			continue
		end

		local entry = entries and entries[index]
		if not entry or entry.sound.SoundId ~= id or not entry.sound.IsLoaded then
			warn("audio wasnt preloaded " .. id)
			continue
		end

		local sound = entry.sound
		local speed = Data.speed(data.Speed)
		local offset = math.max(0, elapsed) * speed
		stop(entry)
		if not rig.Parent or sound.TimeLength <= 0 or not data.Looped and offset >= sound.TimeLength then
			continue
		end

		sound.Looped = data.Looped == true
        if sound.Looped and sound.TimeLength > 0 then offset %= sound.TimeLength end
        sound.Volume = Data.volume(data.Volume)
		sound.PlaybackSpeed = speed
		sound.TimePosition = offset
		active[entry] = true
		sound.Playing = true
	end
end

function Sounds.resume(timeline, time, includeStart)
	Sounds.stop()
	local fps = timeline:GetState().FPS
	for _, track in Events.all() do
		if not Events.isEnabled(track) or not track.Rig.Parent then
			continue
		end

		for _, event in track.Events do
			local start = event.Frame / fps
			if event.Enabled ~= false and (start < time or includeStart and start == time) then
				Sounds.play(track.Rig, event, time - start, timeline)
			end
		end
	end
end

function Sounds.scrub(timeline, time)
	local wanted = {}
	local now = os.clock()
	local fps = timeline:GetState().FPS
	for _, track in Events.all() do
		if not Events.isEnabled(track) or not track.Rig.Parent then
			continue
		end

		for _, event in track.Events do
			local start = event.Frame / fps
			if event.Enabled == false or start > time then
				continue
			end

			for index, data in event.Sounds or {} do
				local entry = prepared[event] and prepared[event][index]
				local id = Data.playback(data)
				if not entry or not id then
					continue
				end

				local sound = entry.sound
				local speed = Data.speed(data.Speed)
				local offset = (time - start) * speed
				if sound.SoundId ~= id or not sound.IsLoaded or sound.TimeLength <= 0 or not data.Looped and offset >= sound.TimeLength then
					continue
				end

				wanted[entry] = true
				sound.Looped = data.Looped == true
        if sound.Looped and sound.TimeLength > 0 then offset %= sound.TimeLength end
        sound.Volume = Data.volume(data.Volume)
				sound.PlaybackSpeed = speed
				if
					not active[entry]
					or not sound.Playing
					or not entry.scrubAt
					or now - entry.scrubAt >= 0.06
				then
					sound.TimePosition = offset
					entry.scrubAt = now
				end

				active[entry] = true
				if not sound.Playing then
					sound.Playing = true
				end
			end
		end
	end

	for entry in active do
		if not wanted[entry] then
			stop(entry)
		end
	end
end

return Sounds
