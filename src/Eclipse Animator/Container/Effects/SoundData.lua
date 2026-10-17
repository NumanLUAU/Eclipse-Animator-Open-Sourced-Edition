--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = {}
local LocalAudio = require("LocalAudio")

local function number(value, fallback, minimum, maximum)
	value = tonumber(value)
	if not value or value ~= value or math.abs(value) == math.huge then
		return fallback
	end

	return math.clamp(value, minimum, maximum)
end

function Data.asset(value)
	local text = tostring(value or ""):match("^%s*(.-)%s*$")
	local id = text:match("^rbxassetid://(%d+)$")
		or text:match("^(%d+)$")
		or text:match("^https?://www%.roblox%.com/library/(%d+)")
		or text:match("[?&]id=(%d+)")
	return id and tonumber(id) > 0 and "rbxassetid://" .. id or nil
end

function Data.volume(value)
	return number(value, 0.5, 0, 10)
end

function Data.speed(value)
	return number(value, 1, 0.01, 20)
end

function Data.playback(sound)
	return LocalAudio.is(sound.AudioId) and LocalAudio.resolve(sound.AudioId)
		or Data.asset(sound.AudioId)
end

function Data.new()
	return { AudioId = "", Volume = 0.5, Speed = 1, Duration = 0, Looped = false }
end

function Data.copy(sounds)
	local result = {}
	for _, sound in sounds or {} do
		if typeof(sound) == "table" then
			table.insert(result, {
				AudioId = tostring(sound.AudioId or ""),
				LocalName = LocalAudio.is(sound.AudioId) and tostring(
					sound.LocalName or "Local audio"
				) or nil,
				Volume = Data.volume(sound.Volume),
				Speed = Data.speed(sound.Speed),
				Duration = number(sound.Duration, 0, 0, 86400),
                Looped = sound.Looped == true,
			})
		end
	end

	return result
end

function Data.has(sounds)
	for _, sound in sounds or {} do
		if Data.asset(sound.AudioId) or LocalAudio.is(sound.AudioId) then
			return true
		end
	end

	return false
end

function Data.write(parent, sounds)
	local folder = Instance.new("Folder")

	folder.Name = "Sounds"
	for index, sound in Data.copy(sounds) do
		local item = Instance.new("Folder")

		item.Name = string.format("%06d", index)
		item:SetAttribute("AudioId", sound.AudioId)
		item:SetAttribute("LocalName", sound.LocalName)
		item:SetAttribute("Volume", sound.Volume)
		item:SetAttribute("Speed", sound.Speed)
		item:SetAttribute("Duration", sound.Duration)
        item:SetAttribute("Looped", sound.Looped == true)
		item.Parent = folder
	end

	folder.Parent = parent
end

function Data.read(parent)
	local folder = parent:FindFirstChild("Sounds")
	local items = folder and folder:GetChildren() or {}
	table.sort(items, function(a, b)
		return a.Name < b.Name
	end)
	local result = {}
	for _, item in items do
		table.insert(result, {
			AudioId = item:GetAttribute("AudioId") or "",
			LocalName = item:GetAttribute("LocalName"),
			Volume = Data.volume(item:GetAttribute("Volume")),
			Speed = Data.speed(item:GetAttribute("Speed")),
			Duration = number(item:GetAttribute("Duration"), 0, 0, 86400),
            Looped = item:GetAttribute("Looped") == true,
		})
	end

	return result
end

function Data.frames(sounds, fps)
	local frames = 0
	for _, sound in sounds or {} do
		if Data.asset(sound.AudioId) or LocalAudio.is(sound.AudioId) then
			frames = math.max(
				frames,
				math.ceil(number(sound.Duration, 0, 0, 86400) / Data.speed(sound.Speed) * fps)
			)
		end
	end

	return frames
end

return Data
