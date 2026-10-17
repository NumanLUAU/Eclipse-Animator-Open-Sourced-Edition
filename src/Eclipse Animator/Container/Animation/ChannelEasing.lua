--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Defaults = require("Defaults")
Defaults = table.clone(Defaults)
Defaults.Amplitude = Defaults.Amplitude or 1
Defaults.Period = Defaults.Period or 0.3
Defaults.Overshoot = Defaults.Overshoot or 1.70158
local E = {}
E.fields = {
	"EasingStyle",
	"EasingDirection",
	"HandleType",
	"BezierPoints",
	"Amplitude",
	"Period",
	"MoonEasing",
	"Overshoot",
}

function E.isAutomaticBezier(key)
	local points = key.BezierPoints or Defaults.BezierPoints
	for i, value in { 0.42, 0, 0.58, 1 } do
		if type(points[i]) ~= "number" or math.abs(points[i] - value) > 1e-7 then
			return false
		end
	end
	local handle = key.HandleType or Defaults.HandleType
	return handle == "Automatic" or handle == "AutoClamped" or handle == "Vector"
end

function E.setOption(key, field, value)
	key[field] = value
	if (key.EasingStyle or Defaults.EasingStyle) == "Bezier"
		and (field == "EasingDirection" and value == "Automatic"
			or field == "HandleType" and (value == "Automatic" or value == "AutoClamped"))
	then
		key.BezierPoints = { 0.42, 0, 0.58, 1 }
		if field == "EasingDirection" then
			key.HandleType = "AutoClamped"
		end
	end
end

function E.clone(v)
	if type(v) ~= "table" then
		return v
	end

	local out = {}
	for k, x in v do
		out[k] = E.clone(x)
	end

	return out
end

function E.equal(a, b)
	if typeof(a) == "EnumItem" then
		a = a.Name
	end

	if typeof(b) == "EnumItem" then
		b = b.Name
	end

	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for k, v in a do
		if not E.equal(v, b[k]) then
			return false
		end
	end

	for k in b do
		if a[k] == nil then
			return false
		end
	end

	return true
end

function E.merge(key, override)
	if not override then
		return key
	end

	local result = table.clone(key)
	for field, value in override do
		result[field] = value
	end

	return result
end

function E.resolve(key, id)
	local channel = key and key.Channels and key.Channels[id]
	return E.merge(key, channel and channel.Easing)
end

function E.view(key, id)
	local point = key.GraphCurves and key.GraphCurves[id]
	if not point then
		return E.resolve(key, id)
	end

	if point.ChannelEasing then
		return E.merge(key, point.ChannelEasing)
	end

	local result = table.clone(key)
	if point.Interpolation == "Legacy" then
		for k, v in point.Easing or {} do
			result[k] = v
		end
	elseif point.Interpolation then
		result.EasingStyle = point.Interpolation
	end

	if point.HandleType then
		result.HandleType = point.HandleType
	end

	return result
end

function E.editAll(key, mutate, bucket, handleOnly)
	local drafts = {}

	local function stage(target, field, source)
		local draft = table.clone(source)
		for _, name in E.fields do
			if type(draft[name]) == "table" then
				draft[name] = E.clone(draft[name])
			end
		end

		mutate(draft)
		table.insert(drafts, { target = target, field = field, value = draft, handle = source.HandleType })
	end

	for _, channel in pairs(key.Channels or {}) do
		stage(channel, "Easing", E.merge(key, channel.Easing))
	end

	for id, point in pairs(key.GraphCurves or {}) do
		if not point.Empty then
			stage(point, "ChannelEasing", E.view(key, id))
		end
	end

	mutate(key)
	for _, row in drafts do
		local overrides = {}
		for _, field in E.fields do
			local value = row.value[field] or Defaults[field]
			if not E.equal(value, key[field] or Defaults[field]) then
				overrides[field] = E.clone(value)
			end
		end

		row.target[row.field] = next(overrides) and overrides or nil
		if row.field == "ChannelEasing" and row.handle ~= row.value.HandleType then
			row.target.HandleType = row.value.HandleType
			row.target.BlenderHandles = nil
			row.target.In, row.target.Out = nil, nil
		end
	end

	require("GraphCurves").syncEasing(key, handleOnly, bucket)
	if handleOnly then
		for id, point in pairs(key.GraphCurves or {}) do
			if not point.Empty then
				E.graphChanged(key, id)
			end
		end
	end
end

function E.edit(key, id, mutate, bucket, handleOnly)
	local point = key.GraphCurves and key.GraphCurves[id]
	local channel = key.Channels and key.Channels[id]
	if not point and not channel then
		return false
	end

	local before = E.view(key, id)
	local draft = table.clone(before)
	for _, field in E.fields do
		if type(draft[field]) == "table" then
			draft[field] = E.clone(draft[field])
		end
	end

	mutate(draft)
	local changed = false
	for _, field in E.fields do
		if not E.equal(before[field] or Defaults[field], draft[field] or Defaults[field]) then
			changed = true
			break
		end
	end

	if not changed then
		return false
	end

	local overrides = {}
	for _, field in E.fields do
		local value = draft[field] or Defaults[field]
		if not E.equal(value, key[field] or Defaults[field]) then
			overrides[field] = E.clone(value)
		end
	end

	if not next(overrides) then
		overrides = nil
	end

	if point then
		point.ChannelEasing = overrides
		if before.HandleType ~= draft.HandleType then
			point.HandleType = draft.HandleType
			point.BlenderHandles = nil
			point.In, point.Out = nil, nil
		end
		require("GraphCurves").syncEasing(key, handleOnly, bucket, id)
		if handleOnly then
			E.graphChanged(key, id)
		end
	else
		channel.Easing = overrides
	end

	return true
end

function E.graphChanged(key, id)
	local point = key.GraphCurves and key.GraphCurves[id]
	if not point or not point.ChannelEasing then
		return
	end

	local override = point.ChannelEasing
	local style = point.Interpolation == "Legacy" and point.Easing and point.Easing.EasingStyle
		or point.Interpolation
	for field, value in { EasingStyle = style, HandleType = point.HandleType } do
		override[field] = if E.equal(value, key[field] or Defaults[field]) then nil else value
	end

	if not next(override) then
		point.ChannelEasing = nil
	end
end

return E
