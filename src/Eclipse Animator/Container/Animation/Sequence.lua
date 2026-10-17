--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Sequence = {}
Sequence.MAX_FRAMES = 300

function Sequence.asset(value)
	local text = tostring(value or ""):match("^%s*(.-)%s*$")
	if text:match("^rbxasset://[^%c]+$") or text:match("^rbxtemp://[^%s%c]+$") then
		return text
	end
	local id = text:match("^rbxassetid://(%d+)$") or text:match("^(%d+)$")
	if not id or tonumber(id) == 0 then
		return nil
	end

	return "rbxassetid://" .. id
end

function Sequence.normalize(raw)
	if type(raw) ~= "table" or #raw == 0 or #raw > Sequence.MAX_FRAMES then
		return nil, "Add 1–300 image frames."
	end

	local frames = {}
	for i, entry in ipairs(raw) do
		if type(entry) ~= "table" then
			return nil, "Invalid Image " .. i
		end

		local image = Sequence.asset(entry.image or entry.id)
		local delay = tonumber(entry.delay or entry.ms)
		if not image then
			return nil, "Enter an image ID for Image " .. i .. "."
		end

		if not delay or delay ~= delay or delay < 1 or delay > 60000 then
			return nil, "Image " .. i .. " needs a delay from 1 to 60000 ms."
		end

		table.insert(frames, { image = image, delay = delay })
	end

	return frames
end

function Sequence.duration(frames)
	local total = 0
	for _, frame in ipairs(frames) do
		total += frame.delay
	end

	return total
end

function Sequence.retime(frames, duration)
	local total = Sequence.duration(frames)
	if not duration or duration ~= duration or duration <= 0 or total <= 0 then
		return nil, "Enter a positive duration or FPS."
	end

	local output = {}
	for _, frame in ipairs(frames) do
		local delay = frame.delay * duration / total
		if delay < 1 or delay > 60000 then
			return nil, "That timing puts a frame outside the 1–60000 ms range."
		end

		table.insert(output, { image = frame.image, delay = delay })
	end

	return output
end

function Sequence.indexAt(frames, elapsedMs)
	local duration = Sequence.duration(frames)
	if duration <= 0 then
		return 1
	end

	local position = elapsedMs % duration
	local boundary = 0
	for index, frame in ipairs(frames) do
		boundary += frame.delay
		if position < boundary - 1e-7 then
			return index
		end
	end

	return 1
end

function Sequence.encode(frames)
	local out = {}
	for _, frame in ipairs(frames) do
		table.insert(out, { id = frame.image:gsub("rbxassetid://", ""), ms = frame.delay })
	end

	return out
end

function Sequence.signature(frames)
	local out = {}
	for _, frame in ipairs(frames) do
		table.insert(out, frame.image .. ":" .. tostring(frame.delay))
	end

	return table.concat(out, "|")
end

return Sequence
