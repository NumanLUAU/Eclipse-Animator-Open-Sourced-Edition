--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local StudioAudio = require("StudioAudio")
local AssetService = game:GetService("AssetService")
local Audio = {}
local playing

function Audio.stop(owner)
	if owner and (not playing or playing.owner ~= owner) then
		return
	end

	local previous = playing
	playing = nil
	if previous then
		previous.sound:Stop()
		previous.sound:Destroy()
		if previous.changed then
			previous.changed(false)
		end
	end
end

function Audio.toggle(id, changed, options, owner)
	if playing and playing.id == id and playing.owner == owner then
		Audio.stop()
		return
	end

	Audio.stop()
	local parent = StudioAudio.parent()
	if not parent then
		return
	end

	local sound = Instance.new("Sound")

	sound.Name = "EclipseLibraryPreview"
	sound.SoundId = id
	sound.Volume = options and options.Volume or 0.5
	sound.PlaybackSpeed = options and options.Speed or 1
	sound.Looped = options and options.Looped == true or false
	sound.Archivable = false
	local session = { sound = sound, id = id, changed = changed, owner = owner }
	playing = session
	sound.Parent = parent
	sound.Ended:Once(function()
		if playing == session then
			Audio.stop()
		end
	end)
	if changed then
		changed(true)
	end

	if not StudioAudio.preload({ sound }, function()
		return playing == session
	end) then
		if playing == session then
			Audio.stop()
		end

		return
	end

	sound.Playing = true
end

function Audio.metadata(id)
	local ok, rows = pcall(AssetService.GetAudioMetadataAsync, AssetService, { id })
	local row = ok and rows and rows[1]
	return { duration = row and (tonumber(row.Duration) or tonumber(row.TimeLength)) or 0 }
end

function Audio.upload()
	return nil, nil, { url = "https://create.roblox.com/dashboard/creations?activeTab=Audio" }
end

return Audio
