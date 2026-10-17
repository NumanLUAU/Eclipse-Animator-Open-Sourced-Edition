--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local R6Controls = require("R6Controls")
local Activity = {}

function Activity.forMotor(timeline, motor, cache)
	if not R6Controls.isControl(motor.Part1) then
		return nil
	end

	local owner = motor.Owner
	if cache and cache[owner] then
		return cache[owner]
	end

	local state = timeline:GetState()
	local changes = {}
	for frame, key in state.Keyframes[owner] or {} do
		if not key.GraphOnly and type(key.IK) == "boolean" then
			table.insert(
				changes,
				{ frame = key.Time and key.Time * state.FPS or frame, enabled = key.IK }
			)
		end
	end

	table.sort(changes, function(a, b)
		return a.frame < b.frame
	end)
	local ranges = {}
	local start
	for _, change in changes do
		if change.enabled then
			if not start then
				start = change.frame
			end
		elseif start then
			table.insert(ranges, { start, change.frame })
			start = nil
		end
	end

	if start then
		table.insert(ranges, { start, math.huge })
	end

	if cache then
		cache[owner] = ranges
	end

	return ranges
end

function Activity.contains(ranges, frame)
	if not ranges then
		return true
	end

	for _, interval in ranges do
		if frame >= interval[1] and frame <= interval[2] then
			return true
		end
	end

	return false
end

return Activity
