--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tween = game:GetService("TweenService")
local Assets = require("EffectCatalog")
local Model = { MAX_FRAME = 1000000, MAX_EFFECTS = 128 }
Model.kinds = { "Camera Shake", "Vignette", "Letterbox", "Screen Cover", "Impact Frames" }
Model.styles = {
	"Linear",
	"Sine",
	"Quad",
	"Cubic",
	"Quart",
	"Quint",
	"Exponential",
	"Circular",
	"Back",
	"Bounce",
	"Elastic",
	"Custom",
	"Constant",
}
Model.directions = { "In", "Out", "InOut" }
local catalog = { Solid = { id = "Solid", label = "Solid bars", group = "Classic" } }
for _, asset in Assets do
	catalog[asset.id] = asset
end

Model.catalog = catalog

function Model.finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function number(n, lo, hi, label)
	assert(
		Model.finite(n) and n >= lo and n <= hi,
		label .. " must be between " .. lo .. " and " .. hi
	)
	return n
end

function Model.copy(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for k, v in value do
		result[k] = Model.copy(v)
	end

	return result
end

function Model.defaults(kind, frame, fps)
	return {
		kind = kind or "Vignette",
		name = kind or "Vignette",
		style = "Solid",
		start = math.max(0, math.round(frame or 0)),
		duration = math.max(1, math.round((fps or 60) * 2)),
		fadeIn = math.round((fps or 60) * 0.25),
		fadeOut = math.round((fps or 60) * 0.25),
		color = { 0, 0, 0 },
		opacity = 1,
		height = 0.121749409,
		scale = 1,
		enabled = true,
		easeIn = { style = "Sine", direction = "Out", curve = { 0.25, 0.1, 0.25, 1 } },
		easeOut = { style = "Sine", direction = "In", curve = { 0.25, 0.1, 0.25, 1 } },
	}
end

local function easing(value)
	assert(
		type(value) == "table" and table.find(Model.styles, value.style),
		"Choose a valid easing style"
	)
	assert(table.find(Model.directions, value.direction), "Choose a valid easing direction")
	local curve = value.curve or { 0.25, 0.1, 0.25, 1 }
	assert(type(curve) == "table" and #curve == 4, "Custom easing needs four control values")
	for i, n in curve do
		number(n, i % 2 == 1 and 0 or -10, i % 2 == 1 and 1 or 10, "Custom easing control")
	end

	local result = { style = value.style, direction = value.direction, curve = table.clone(curve) }
	for _, id in { "Overshoot", "Amplitude", "Period" } do
		if value[id] ~= nil then
			result[id] = number(value[id], 0, 100, id)
		end
	end

	return result
end

function Model.validate(value)
	assert(type(value) == "table" and table.find(Model.kinds, value.kind), "Choose an effect type")
	local result = {
		kind = value.kind,
		name = tostring(value.name or value.kind):sub(1, 64),
		enabled = value.enabled ~= false,
	}
	if result.name:match("^%s*$") then
		result.name = result.kind
	end

	for _, key in { "start", "duration", "fadeIn", "fadeOut" } do
		result[key] = number(value[key], key == "duration" and 1 or 0, Model.MAX_FRAME, key)
		assert(result[key] % 1 == 0, "Timing values must be whole frames")
	end

	assert(
		result.start + result.duration <= Model.MAX_FRAME,
		"The effect ends beyond the timeline limit"
	)
	assert(
		result.fadeIn + result.fadeOut <= result.duration,
		"Fade in + fade out must fit inside duration"
	)
	assert(type(value.color) == "table" and #value.color == 3, "Choose a valid color")
	result.color = {}
	for i, n in value.color do
		result.color[i] = number(n, 0, 1, "Color")
	end

	result.opacity = number(value.opacity, 0, 1, "Opacity")
	result.height = number(value.height or 0.121749409, 0.01, 0.45, "Bar height")
	result.scale = number(value.scale or 1, 0.25, 3, "VFX scale")
	result.easeIn = easing(value.easeIn)
	result.easeOut = easing(value.easeOut)
	result.style = value.style or "Solid"
	assert(catalog[result.style], "The selected letterbox style is unavailable")
	if value.cameraId ~= nil then
		assert(
			type(value.cameraId) == "string" and #value.cameraId <= 200,
			"Invalid camera identity"
		)
		result.cameraId = value.cameraId
	end

	return result
end

function Model.validateAll(values)
	assert(type(values) == "table", "Invalid effects document")
	local result, count = {}, 0
	for id, value in values do
		count += 1
		assert(count <= Model.MAX_EFFECTS, "Too many effects")
		assert(type(id) == "string" and #id > 0 and #id <= 100, "Invalid effect identity")
		result[id] = Model.validate(value)
	end

	return result
end

local function cubic(t, a, b)
	local u = 1 - t
	return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
end

function Model.ease(value, ease)
	value = math.clamp(value, 0, 1)
	if ease.style == "Constant" then
		return value >= 1 and 1 or 0
	end

	if ease.style == "Custom" then
		local c = ease.curve
		local lo, hi = 0, 1
		for _ = 1, 22 do
			local mid = (lo + hi) * 0.5
			if cubic(mid, c[1], c[3]) < value then
				lo = mid
			else
				hi = mid
			end
		end

		return cubic((lo + hi) * 0.5, c[2], c[4])
	end

	return math.clamp(
		Tween:GetValue(value, Enum.EasingStyle[ease.style], Enum.EasingDirection[ease.direction]),
		0,
		1
	)
end

function Model.alpha(effect, frame)
	if
		effect.enabled == false
		or frame < effect.start
		or frame >= effect.start + effect.duration
	then
		return 0
	end

	local age = frame - effect.start
	if effect.fadeIn > 0 and age < effect.fadeIn then
		return Model.ease(age / effect.fadeIn, effect.easeIn) * effect.opacity
	end

	if effect.fadeOut > 0 and age > effect.duration - effect.fadeOut then
		return (
			1
			- Model.ease((age - effect.duration + effect.fadeOut) / effect.fadeOut, effect.easeOut)
		) * effect.opacity
	end

	return effect.opacity
end

function Model.ordered(values)
	local result = {}
	for id, value in values do
		table.insert(result, { id = id, value = value })
	end

	table.sort(result, function(a, b)
		return a.value.start < b.value.start or a.value.start == b.value.start and a.id < b.id
	end)
	return result
end

return Model
