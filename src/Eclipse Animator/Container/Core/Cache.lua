--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Mode = {}
local revision = 0
local authoredCache = setmetatable({}, { __mode = "k" })

function Mode.revision()
	return revision
end

local poseCache, playCache, timelineState, scrubCache, scrubTracks, scrubLayers, scrubDefaults

local function playing()
	if not timelineState then
		timelineState = require("RawState").Timeline
	end

	return timelineState.Playing == true
end

local frozenCache

local function freshCache(persistent)
	return {
		persistent = persistent,
		bounds = setmetatable({}, { __mode = "k" }),
		ik = setmetatable({}, { __mode = "k" }),
		hs = setmetatable({}, { __mode = "k" }),
	}
end

function Mode.invalidate()
	revision += 1
	table.clear(authoredCache)
	playCache = nil
	scrubCache = nil
	if poseCache then
		poseCache = freshCache(true)
	end

	if frozenCache then
		frozenCache = freshCache(true)
	end
end

function Mode.withFrozen(callback)
	if frozenCache then
		return callback()
	end

	frozenCache = freshCache(true)
	local results = table.pack(pcall(callback))
	frozenCache = nil
	if not results[1] then
		error(results[2], 0)
	end

	return table.unpack(results, 2, results.n)
end

function Mode.poseCache()
	if frozenCache then
		return frozenCache
	end

	if playing() then
		if not playCache then
			playCache = {
				persistent = true,
				bounds = setmetatable({}, { __mode = "k" }),
				ik = setmetatable({}, { __mode = "k" }),
				hs = setmetatable({}, { __mode = "k" }),
			}
		end

		return playCache
	end

	playCache = nil
	return poseCache
end

function Mode.withPose(callback)
	if poseCache then
		return callback()
	end

	playing()
	if
		not scrubCache
		or scrubTracks ~= timelineState.Keyframes
		or scrubLayers ~= timelineState.AnimationLayers
		or scrubDefaults ~= timelineState.DefaultPose
	then
		scrubCache = freshCache(true)
		scrubTracks = timelineState.Keyframes
		scrubLayers = timelineState.AnimationLayers
		scrubDefaults = timelineState.DefaultPose
	end

	poseCache = scrubCache

	poseCache.hs = setmetatable({}, { __mode = "k" })
	poseCache.eligible = setmetatable({}, { __mode = "k" })
	local results = table.pack(pcall(callback))
	poseCache = nil
	if not results[1] then
		error(results[2], 0)
	end

	return table.unpack(results, 2, results.n)
end

function Mode.isHead(motor)
	return typeof(motor) == "Instance"
		and motor:IsA("Motor6D")
		and motor.Part0 ~= nil
		and motor.Part1 ~= nil
		and motor.Part1.Name == "Head"
		and (motor.Part0.Name == "Torso" or motor.Part0.Name == "UpperTorso")
end

local function eligible(motor)
	if typeof(motor) == "Instance" then
		return motor:IsA("Motor6D")
			and motor.Part0 ~= nil
			and motor.Part1 ~= nil
			and not require("CameraRig").isFov(motor)
	end

	if typeof(motor) ~= "table" or not motor.Part0 or not motor.Part1 then
		return false
	end

	return typeof(motor) == "table"
		and (motor.IsEclipseBoneMotor or motor.IsEclipseArmatureControl)
		and not motor.IsTranslationOnly
end

function Mode.isEligible(motor)
	local memo = poseCache and motor ~= nil and poseCache.eligible
	if not memo then
		return eligible(motor)
	end

	local value = memo[motor]
	if value == nil then
		value = eligible(motor)
		memo[motor] = value
	end

	return value
end

function Mode.authored(motor, bucket, time)
	if not bucket then
		return nil, false
	end

	local index = authoredCache[bucket]
	if not index then
		index = {}
		for _, key in bucket do
			if not key.Disabled and not key.GraphOnly and typeof(key.HS) == "boolean" then
				table.insert(index, key)
			end
		end

		table.sort(index, function(a, b)
			return a.Time < b.Time
		end)
		authoredCache[bucket] = index
	end

	local low, high, found = 1, #index, 0
	while low <= high do
		local middle = (low + high) // 2
		if index[middle].Time <= time then
			found = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end

	if found == 0 then
		return nil, false
	end

	return not index[found].HS, true
end

function Mode.inherits(motor, time)
	local raw = require("RawState").Timeline
	local value, found = Mode.authored(motor, raw.Keyframes[motor], time)
	if found then
		return value
	end

	if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
		return require("ArmatureRuntime").inheritsRotation(motor)
	end

	return true
end

local function enabledAt(motor, bucket, time)
	if not Mode.isEligible(motor) then
		return false
	end

	local memo = poseCache and bucket and poseCache.hs[bucket]
	if memo and memo[time] ~= nil then
		return memo[time]
	end

	local source = bucket
	bucket = require("Cache").active(bucket)
	local cache = bucket and Mode.poseCache()
	if cache and cache.persistent then
		cache.hsSwitches = cache.hsSwitches or setmetatable({}, { __mode = "k" })
		local index = cache.hsSwitches[bucket]
		if not index then
			index = {}
			local seen = {}
			for _, key in bucket do
				if
					not key.GraphOnly
					and not key.Disabled
					and typeof(key.HS) == "boolean"
					and not seen[key.Time]
				then
					table.insert(index, key)
					seen[key.Time] = true
				end
			end

			table.sort(index, function(a, b)
				return a.Time < b.Time
			end)
			cache.hsSwitches[bucket] = index
		end

		local low, high, found = 1, #index, 0
		while low <= high do
			local middle = (low + high) // 2
			if index[middle].Time <= time then
				found = middle
				low = middle + 1
			else
				high = middle - 1
			end
		end

		return found > 0 and index[found].HS == true
	end

	local previous
	for _, key in bucket or {} do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if
			typeof(key.HS) == "boolean"
			and key.Time <= time
			and (not previous or key.Time > previous.Time)
		then
			previous = key
		end
	end

	local result = previous ~= nil and previous.HS == true
	if poseCache and source then
		poseCache.hs[source] = poseCache.hs[source] or {}
		poseCache.hs[source][time] = result
	end

	return result
end

function Mode.isEnabled(motor, bucket, time)
	local memo = poseCache and motor ~= nil and poseCache.hs
	local saved = memo and memo[motor]
	if saved and saved.time == time and saved.bucket == bucket then
		return saved.value
	end

	local value = enabledAt(motor, bucket, time)
	if saved then
		saved.time, saved.bucket, saved.value = time, bucket, value
	elseif memo then
		memo[motor] = { time = time, bucket = bucket, value = value }
	end

	return value
end

return Mode
