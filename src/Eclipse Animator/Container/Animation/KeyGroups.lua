--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Groups = {}
Groups.POSE = "Pose"

function Groups.clone(value)
	return type(value) == "table" and table.clone(value) or nil
end

function Groups.get(key, lane)
	local id = type(key.KeyGroups) == "table" and key.KeyGroups[lane]
	return type(id) == "string" and #id > 0 and id or nil
end

function Groups.set(key, lane, id)
	key.KeyGroups = Groups.clone(key.KeyGroups) or {}
	key.KeyGroups[lane] = id
	if not next(key.KeyGroups) then
		key.KeyGroups = nil
	end
end

function Groups.hasLane(key, lane)
	if lane == Groups.POSE then
		for _, point in key.GraphCurves or {} do
			if not point.Empty then
				return true
			end
		end

		return not key.GraphOnly
	end

	local point = key.GraphCurves and key.GraphCurves[lane]
	if point then
		return not point.Empty
	end

	return key.Channels and key.Channels[lane] ~= nil
end

function Groups.collect(bucket, lane)
	local result = {}
	for frame, key in bucket do
		local id = Groups.get(key, lane)
		if id and Groups.hasLane(key, lane) then
			result[id] = result[id] or {}
			table.insert(result[id], { key = key, frame = frame })
		end
	end

	for id, members in result do
		if #members < 2 then
			result[id] = nil
		else
			table.sort(members, function(a, b)
				return a.frame < b.frame
			end)
		end
	end

	return result
end

function Groups.range(bucket, selected, lane)
	local first, last, count = math.huge, -math.huge, 0
	for frame, key in bucket do
		if selected[key] and Groups.hasLane(key, lane) then
			first, last, count = math.min(first, frame), math.max(last, frame), count + 1
		end
	end

	if count < 2 then
		return {}
	end

	local groups = Groups.collect(bucket, lane)
	local growing = true
	while growing do
		growing = false
		for _, members in groups do
			local a, b = members[1].frame, members[#members].frame
			if a <= last and b >= first and (a < first or b > last) then
				first, last, growing = math.min(first, a), math.max(last, b), true
			end
		end
	end

	local result = {}
	for frame, key in bucket do
		if frame >= first and frame <= last and Groups.hasLane(key, lane) then
			table.insert(result, { key = key, frame = frame })
		end
	end

	table.sort(result, function(a, b)
		return a.frame < b.frame
	end)
	return result
end

function Groups.majority(members, shape)
	local counts, best, maximum = {}, nil, 0
	for _, member in members do
		local value = shape(member)
		counts[value] = (counts[value] or 0) + 1
	end

	for _, member in members do
		local value = shape(member)
		if counts[value] > maximum then
			best, maximum = value, counts[value]
		end
	end

	return best
end

function Groups.transfer(source, target, lane)
	Groups.set(target, lane, Groups.get(source, lane))
	Groups.set(source, lane, nil)
end

function Groups.remap(value, ids, newId)
	local result = Groups.clone(value)
	for lane, id in result or {} do
		ids[id] = ids[id] or newId()
		result[lane] = ids[id]
	end

	return result
end

return Groups
