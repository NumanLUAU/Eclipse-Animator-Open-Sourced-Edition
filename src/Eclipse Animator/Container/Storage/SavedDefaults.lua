--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Defaults = require("Defaults")
local Http = game:GetService("HttpService")
local Saved = {}
local values = {
	HandleType = Defaults.HandleType,
	EasingStyle = Defaults.EasingStyle,
	EasingDirection = Defaults.EasingDirection,
	BezierPoints = table.clone(Defaults.BezierPoints),
	Overshoot = 1.70158,
	Amplitude = 1,
	Period = 0.3,
}
local allowed = {
	HandleType = {
		Free = true,
		Aligned = true,
		Vector = true,
		Automatic = true,
		AutoClamped = true,
	},
	EasingStyle = {
		Constant = true,
		Linear = true,
		Bezier = true,
		Sine = true,
		Quad = true,
		Cubic = true,
		Quart = true,
		Quint = true,
		Sextic = true,
		Expo = true,
		Circ = true,
		Back = true,
		Bounce = true,
		Elastic = true,
	},
	EasingDirection = { Automatic = true, In = true, Out = true, InOut = true, OutIn = true },
}
local writer, initialized
local setting = "EclipseAnimator_AnimationDefaults_v1"

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function normalize(field, value)
	if allowed[field] then
		return allowed[field][value] and value or nil
	end

	if field == "BezierPoints" then
		if type(value) ~= "table" or #value ~= 4 then
			return nil
		end

		for i = 1, 4 do
			if not finite(value[i]) then
				return nil
			end
		end

		return { math.clamp(value[1], 0, 1), value[2], math.clamp(value[3], 0, 1), value[4] }
	end

	if field == "Overshoot" or field == "Amplitude" or field == "Period" then
		if not finite(value) or field == "Period" and value <= 0 then
			return nil
		end

		return value
	end

	return nil
end

Saved.normalize = normalize

function Saved.init(refs)
	if initialized then
		return
	end

	initialized = true
	writer = refs.SetSetting
	local ok, data = pcall(refs.GetSetting, setting)
	if ok and type(data) == "string" then
		ok, data = pcall(Http.JSONDecode, Http, data)
	end

	if not ok or data ~= nil and type(data) ~= "table" then
		writer = function()
			error("Reopen Eclipse to reload saved default easing.")
		end

		warn("Eclipse default easing could not be read; saved data was retained.")
		return
	end

	if ok and type(data) == "table" then
		for field, value in data do
			local normalized = normalize(field, value)
			if normalized ~= nil then
				values[field] = normalized
			end
		end

		if data.HandleDefaultsVersion ~= 2 and values.HandleType == "Automatic" then
			values.HandleType = "AutoClamped"
		end
	end

	if writer then
		local saved = Saved.get()
		saved.HandleDefaultsVersion = 2
		pcall(writer, setting, Http:JSONEncode(saved))
	end
end

function Saved.get()
	local result = table.clone(values)
	result.BezierPoints = table.clone(values.BezierPoints)
	return result
end

function Saved.set(field, value)
	local normalized = normalize(field, value)
	if normalized == nil then
		return false
	end

	local candidate = Saved.get()
	require("ChannelEasing").setOption(candidate, field, normalized)
	candidate.HandleDefaultsVersion = 2
	if writer then
		local ok = pcall(writer, setting, Http:JSONEncode(candidate))
		if not ok then
			return false
		end
	end

	values = candidate
	return true
end

return Saved
