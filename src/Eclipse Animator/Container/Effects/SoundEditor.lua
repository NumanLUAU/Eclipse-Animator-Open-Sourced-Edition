--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("SoundData")
local Audio = require("Audio")
local State = require("State")
local LocalAudio = require("LocalAudio")
local Notification = require("Notification")
local SoundEditor = {}

function SoundEditor.bind(refs)
	local page, label, box, button = refs.page, refs.label, refs.box, refs.button
	local index, painting = 1, false
	local paintedAudioText
	local editor = {}
	local count =
		label(page, "SoundCount", "Sound 1 / 1", UDim2.fromOffset(0, 0), UDim2.fromOffset(110, 24))
	local previous =
		button(page, "PreviousSound", "<", UDim2.fromOffset(112, 0), UDim2.fromOffset(24, 24))
	local nextSound =
		button(page, "NextSound", ">", UDim2.fromOffset(140, 0), UDim2.fromOffset(24, 24))
	local add =
		button(page, "AddSound", "+ Sound", UDim2.fromOffset(170, 0), UDim2.fromOffset(70, 24))
	local remove =
		button(page, "RemoveSound", "-", UDim2.fromOffset(246, 0), UDim2.fromOffset(44, 24))
	label(page, "AudioLabel", "Audio ID", UDim2.fromOffset(0, 30), UDim2.fromOffset(90, 16))
	local audio = box(page, "AudioId", "", UDim2.fromOffset(0, 49), UDim2.new(1, 0, 0, 26))
	audio.PlaceholderText = "Paste audio ID"
	audio.TextTruncate = Enum.TextTruncate.AtEnd
	local volumeLabel = label(
		refs.window,
		"VolumeLabel",
		"Volume",
		UDim2.fromOffset(118, refs.speedY),
		UDim2.fromOffset(42, 26)
	)
	local volume = box(
		refs.window,
		"Volume",
		".5",
		UDim2.fromOffset(164, refs.speedY),
		UDim2.fromOffset(54, 26)
	)
	volume.TextSize = 14
	volume.Position = UDim2.fromOffset(4, 2)
	volume.Size = UDim2.new(1, -8, 1, -4)
	local test =
		button(page, "TestSound", "Test", UDim2.fromOffset(0, 83), UDim2.fromOffset(64, 26))
	volume.TextXAlignment = Enum.TextXAlignment.Center
	volume.ClearTextOnFocus = true
	local library = button(
		page,
		"SoundLibrary",
		"Sound Library",
		UDim2.fromOffset(70, 83),
		UDim2.fromOffset(110, 26)
	)
	local localFile = button(
		page,
		"LocalAudio",
		"Local Audio",
		UDim2.fromOffset(186, 83),
		UDim2.fromOffset(104, 26)
	)

    local loopButton = button(page, "LoopSound", "Loop Off", UDim2.fromOffset(296, 83), UDim2.fromOffset(54, 26))
    loopButton.TextSize = 10
    loopButton:SetAttribute("Tooltip", "Repeat this sound until timeline playback stops")
	local function current()
		local event = refs.event()
		return event and event.Sounds and event.Sounds[index] or Data.new()
	end

	local function edit(field, value)
		if painting or refs.session.closing then
			return
		end

		local event = refs.event()
		if not event then
			return
		end

		local existing = event.Sounds and event.Sounds[index]
		if existing and existing[field] == value or not existing and Data.new()[field] == value then
			return
		end

		local sounds = Data.copy(event.Sounds)
		sounds[index] = sounds[index] or Data.new()
		sounds[index][field] = value
		if field == "AudioId" and (existing and existing.AudioId) ~= value then
			sounds[index].Duration = 0
			sounds[index].LocalName = nil
		end

		refs.change("Sounds", sounds)
	end

	local function paint()
		painting = true
		local sounds = refs.event().Sounds or {}
		index = math.clamp(index, 1, math.max(1, #sounds))
		local sound = current()
		count.Text = string.format("Sound %d / %d", index, math.max(1, #sounds))
		paintedAudioText = LocalAudio.is(sound.AudioId) and (sound.LocalName or "Local audio")
			or sound.AudioId
		audio.Text = paintedAudioText
		volume.Text = tostring(sound.Volume)
        loopButton.Text = sound.Looped and "Loop On" or "Loop Off"
		localFile.Text = LocalAudio.is(sound.AudioId)
				and not LocalAudio.resolve(sound.AudioId)
				and "Reselect Audio"
			or "Local Audio"
		previous.Interactable = index > 1
		nextSound.Interactable = index < #sounds
		remove.Interactable = #sounds > 0
		previous.TextTransparency = index > 1 and 0 or 0.6
		nextSound.TextTransparency = index < #sounds and 0 or 0.6
		remove.TextTransparency = #sounds > 0 and 0 or 0.6
		painting = false
		refs.selected()
	end

	function editor.flush()
		if refs.session.closing then
			return
		end

		local value = tonumber(volume.Text)
		if value and value == value and math.abs(value) < math.huge then
			edit("Volume", Data.volume(value))
		end

		volume.Text = tostring(current().Volume)
		local id = audio.Text ~= paintedAudioText and Data.asset(audio.Text)
		if id then
			edit("AudioId", id)
		end
	end

	function editor.speed()
		return current().Speed
	end

	function editor.setSpeed(value)
		edit("Speed", Data.speed(value))
	end

	function editor.close()
		Audio.stop(refs.session)
		if State.Library then
			State.Library.closeSounds(refs.session)
		end
	end

	function editor.setVisible(visible)
		volumeLabel.Visible = visible
		volume.Parent.Visible = visible
		if not visible then
			editor.close()
		end
	end

    loopButton.Activated:Connect(function()
        edit("Looped", not current().Looped)
        paint()
    end)
	test.Activated:Connect(function()
		if refs.session.closing then
			return
		end

		refs.beforeSelect()
		local sound = current()
		local id = Data.playback(sound)
		if not id then
			if LocalAudio.is(sound.AudioId) then
				Notification.show("LOCAL AUDIO", "Reselect this local audio file to preview it.")
			end

			return
		end

		Audio.toggle(id, function(playing)
			if not refs.session.closing then
				test.Text = playing and "Stop" or "Test"
			end
		end, sound, refs.session)
	end)

	local function select(nextIndex)
		refs.beforeSelect()
		editor.close()
		index = nextIndex
		paint()
	end

	previous.Activated:Connect(function()
		select(math.max(1, index - 1))
	end)
	nextSound.Activated:Connect(function()
		select(math.min(#(refs.event().Sounds or {}), index + 1))
	end)
	add.Activated:Connect(function()
		refs.beforeSelect()
		editor.close()
		local sounds = Data.copy(refs.event().Sounds)
		table.insert(sounds, Data.new())
		index = #sounds
		refs.change("Sounds", sounds)
		paint()
		refs.commit()
	end)
	remove.Activated:Connect(function()
		refs.beforeSelect()
		editor.close()
		local sounds = Data.copy(refs.event().Sounds)
		table.remove(sounds, index)
		refs.change("Sounds", sounds)
		paint()
		refs.commit()
	end)
	audio:GetPropertyChangedSignal("Text"):Connect(function()
		if audio.Text ~= paintedAudioText then
			edit("AudioId", audio.Text)
		end
	end)
	require("NumericInput").connect(volume, { step = 0.1, min = 0, max = 10 }, function()
		editor.flush()
		refs.commit()
	end)
	localFile.Activated:Connect(function()
		if refs.session.closing then
			return
		end

		refs.beforeSelect()
		editor.close()
		local event, selectedIndex = refs.event(), index
		local id, err, name = LocalAudio.prompt(current().AudioId, function()
			return not refs.session.closing
				and refs.timeline._eventEditor == refs.session
				and refs.event() == event
				and index == selectedIndex
		end)
		if
			refs.session.closing
			or refs.timeline._eventEditor ~= refs.session
			or refs.event() ~= event
			or index ~= selectedIndex
		then
			return
		end

		if err then
			Notification.show("LOCAL AUDIO", err)
			return
		end

		if not id then
			return
		end

		edit("AudioId", id)
		edit("LocalName", name)
		edit("Duration", 0)
		paint()
		refs.commit()
	end)
	library.Activated:Connect(function()
		refs.beforeSelect()
		if not State.Library then
			return
		end

		State.Library.openSounds(refs.session, function(id, entry)
			if refs.session.closing or refs.timeline._eventEditor ~= refs.session then
				return
			end

			edit("AudioId", id)
			if entry and entry.duration then
				edit("Duration", entry.duration)
			end

			paint()
			refs.commit()
		end)
	end)
	paint()
	return editor
end

return SoundEditor
