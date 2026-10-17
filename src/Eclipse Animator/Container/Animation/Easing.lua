--!nocheck
--!native
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Easing = {}

local Defaults = require("Defaults")
local Bezier = require("Bezier")

local PI = math.pi
local TAU = math.pi * 2
local DEFAULT_OVERSHOOT = 1.70158

local DYNAMIC_STYLES = {
	Back = true,
	Bounce = true,
	Elastic = true,
}

local function finite(value, fallback)
	return type(value) == "number" and value == value and math.abs(value) < 1e4 and value or fallback
end

local function bezierAlpha(t, x1, y1, x2, y2)
	if t <= 0 then
		return 0
	end

	if t >= 1 then
		return 1
	end

	x1, y1, x2, y2 = finite(x1, 0.42), finite(y1, 0), finite(x2, 0.58), finite(y2, 1)

	x1, x2 = math.clamp(x1, 0, 1), math.clamp(x2, 0, 1)
	if x1 == y1 and x2 == y2 then
		return t
	end

	local u = Bezier.parameter(t, x1, x2)
	return Bezier.cubic(0, y1, y2, 1, u)
end

local FNS = {}

function FNS.SineIn(t)
	return 1 - math.cos(t * PI * 0.5)
end

function FNS.SineOut(t)
	return math.sin(t * PI * 0.5)
end

function FNS.SineInOut(t)
	return -(math.cos(PI * t) - 1) * 0.5
end

function FNS.SineOutIn(t)
	if t < 0.5 then
		return FNS.SineOut(t * 2) * 0.5
	end

	return FNS.SineIn(t * 2 - 1) * 0.5 + 0.5
end

local function makePoly(power)
	local pIn = function(t)
		return math.pow(t, power)
	end

	local pOut = function(t)
		return 1 - math.pow(1 - t, power)
	end

	local pInOut = function(t)
		if t < 0.5 then
			return math.pow(2 * t, power) * 0.5
		end

		return 1 - math.pow(2 - 2 * t, power) * 0.5
	end

	local pOutIn = function(t)
		if t < 0.5 then
			return pOut(t * 2) * 0.5
		end

		return pIn(t * 2 - 1) * 0.5 + 0.5
	end

	return pIn, pOut, pInOut, pOutIn
end

for name, power in pairs({ Quad = 2, Cubic = 3, Quart = 4, Quint = 5, Sextic = 6 }) do
	local pIn, pOut, pInOut, pOutIn = makePoly(power)
	FNS[name .. "In"] = pIn
	FNS[name .. "Out"] = pOut
	FNS[name .. "InOut"] = pInOut
	FNS[name .. "OutIn"] = pOutIn
end

local EXPO_MIN = 2 ^ -10
local EXPO_SCALE = 1 / (1 - EXPO_MIN)

function FNS.ExpoIn(t)
	return (2 ^ (10 * (t - 1)) - EXPO_MIN) * EXPO_SCALE
end

function FNS.ExpoOut(t)
	return 1 - FNS.ExpoIn(1 - t)
end

function FNS.ExpoInOut(t)
	if t < 0.5 then
		return FNS.ExpoIn(t * 2) * 0.5
	end

	return FNS.ExpoOut(t * 2 - 1) * 0.5 + 0.5
end

function FNS.ExpoOutIn(t)
	if t < 0.5 then
		return FNS.ExpoOut(t * 2) * 0.5
	end

	return FNS.ExpoIn(t * 2 - 1) * 0.5 + 0.5
end

function FNS.CircIn(t)
	return 1 - math.sqrt(1 - t * t)
end

function FNS.CircOut(t)
	local s = t - 1
	return math.sqrt(1 - s * s)
end

function FNS.CircInOut(t)
	if t < 0.5 then
		local x = 2 * t
		return (1 - math.sqrt(1 - x * x)) * 0.5
	end

	local x = 2 * t - 2
	return (math.sqrt(1 - x * x) + 1) * 0.5
end

function FNS.CircOutIn(t)
	if t < 0.5 then
		return FNS.CircOut(t * 2) * 0.5
	end

	return FNS.CircIn(t * 2 - 1) * 0.5 + 0.5
end

local function backIn(t, s)
	s = s or DEFAULT_OVERSHOOT
	return t * t * ((s + 1) * t - s)
end

local function backOut(t, s)
	s = s or DEFAULT_OVERSHOOT
	local x = t - 1
	return x * x * ((s + 1) * x + s) + 1
end

local function backInOut(t, s)
	s = (s or DEFAULT_OVERSHOOT) * 1.525
	if t < 0.5 then
		local x = 2 * t
		return (x * x * ((s + 1) * x - s)) * 0.5
	end

	local x = 2 * t - 2
	return (x * x * ((s + 1) * x + s) + 2) * 0.5
end

local function backOutIn(t, s)
	if t < 0.5 then
		return backOut(t * 2, s) * 0.5
	end

	return backIn(t * 2 - 1, s) * 0.5 + 0.5
end

function FNS.BackIn(t, params)
	return backIn(t, params and params.Overshoot)
end

function FNS.BackOut(t, params)
	return backOut(t, params and params.Overshoot)
end

function FNS.BackInOut(t, params)
	return backInOut(t, params and params.Overshoot)
end

function FNS.BackOutIn(t, params)
	return backOutIn(t, params and params.Overshoot)
end

local function bounceOut(t)
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	end

	if t < 2 / 2.75 then
		local x = t - 1.5 / 2.75
		return 7.5625 * x * x + 0.75
	end

	if t < 2.5 / 2.75 then
		local x = t - 2.25 / 2.75
		return 7.5625 * x * x + 0.9375
	end

	local x = t - 2.625 / 2.75
	return 7.5625 * x * x + 0.984375
end

local function bounceIn(t)
	return 1 - bounceOut(1 - t)
end

local function bounceInOut(t)
	if t < 0.5 then
		return bounceIn(t * 2) * 0.5
	end

	return bounceOut(t * 2 - 1) * 0.5 + 0.5
end

local function bounceOutIn(t)
	if t < 0.5 then
		return bounceOut(t * 2) * 0.5
	end

	return bounceIn(t * 2 - 1) * 0.5 + 0.5
end

FNS.BounceIn = bounceIn
FNS.BounceOut = bounceOut
FNS.BounceInOut = bounceInOut
FNS.BounceOutIn = bounceOutIn

local function elasticBlend(t, c, a, s, f)
	local cAbs = math.abs(c)
	local sAbs = math.abs(s)
	if a ~= 0 then
		f = f * (a / cAbs)
	else
		f = 0
	end

	if math.abs(t) < sAbs then
		local l = math.abs(t) / sAbs
		f = f * l + (1 - l)
	end

	return f
end

local function elasticInScaled(t, c, a, p)
	if t == 0 then
		return 0
	end

	if t == 1 then
		return c
	end

	a = a or 1
	p = (p and p ~= 0) and p or 0.3
	t = t - 1
	local s, f = nil, 1
	local cAbs = math.abs(c)
	if a < cAbs then
		s = p / 4
		f = elasticBlend(t, c, a, s, f)
		a = c
	else
		s = p / TAU * math.asin(c / a)
	end

	return -f * (a * math.pow(2, 10 * t) * math.sin((t - s) * TAU / p))
end

local function elasticOutScaled(t, c, a, p)
	if t == 0 then
		return 0
	end

	if t == 1 then
		return c
	end

	a = a or 1
	p = (p and p ~= 0) and p or 0.3
	local nt = -t
	local s, f = nil, 1
	local cAbs = math.abs(c)
	if a < cAbs then
		s = p / 4
		f = elasticBlend(nt, c, a, s, f)
		a = c
	else
		s = p / TAU * math.asin(c / a)
	end

	return f * (a * math.pow(2, 10 * nt) * math.sin((nt - s) * TAU / p)) + c
end

local function elasticIn(t, a, p)
	return elasticInScaled(t, 1, a, p)
end

local function elasticOut(t, a, p)
	return elasticOutScaled(t, 1, a, p)
end

local function elasticInOut(t, a, p)
	if t == 0 then
		return 0
	end

	a = a or 1
	p = (p and p ~= 0) and p or 0.45
	t = t * 2
	if t == 2 then
		return 1
	end

	t = t - 1
	local s, f = nil, 1
	if a < 1 then
		s = p / 4
		f = elasticBlend(t, 1, a, s, f)
		a = 1
	else
		s = p / TAU * math.asin(1 / a)
	end

	if t < 0 then
		f = f * -0.5
		return f * (a * math.pow(2, 10 * t) * math.sin((t - s) * TAU / p))
	end

	local nt = -t
	f = f * 0.5
	return f * (a * math.pow(2, 10 * nt) * math.sin((nt - s) * TAU / p)) + 1
end

local function elasticOutIn(t, a, p)
	if t < 0.5 then
		return elasticOutScaled(t * 2, 0.5, a, p)
	end

	return elasticInScaled(t * 2 - 1, 0.5, a, p) + 0.5
end

function FNS.ElasticIn(t, params)
	return elasticIn(t, params and params.Amplitude, params and params.Period)
end

function FNS.ElasticOut(t, params)
	return elasticOut(t, params and params.Amplitude, params and params.Period)
end

function FNS.ElasticInOut(t, params)
	return elasticInOut(t, params and params.Amplitude, params and params.Period)
end

function FNS.ElasticOutIn(t, params)
	return elasticOutIn(t, params and params.Amplitude, params and params.Period)
end

local function resolveStyleName(style)
	local name
	if type(style) == "string" then
		name = style
	elseif typeof(style) == "EnumItem" then
		name = style.Name
	end

	if name == "Quadratic" then
		return "Quad"
	end

	if name == "Quartic" then
		return "Quart"
	end

	if name == "Quintic" then
		return "Quint"
	end

	if name == "Sinusoidal" then
		return "Sine"
	end

	if name == "Exponential" then
		return "Expo"
	end

	if name == "Circular" then
		return "Circ"
	end

	if name == "CubicV2" then
		return "Cubic"
	end

	return name
end

Easing.styleName = resolveStyleName

local function resolveDirName(dir)
	if type(dir) == "string" then
		return dir
	end

	if typeof(dir) == "EnumItem" then
		return dir.Name
	end

	return nil
end

local function evaluate(alpha, keyData, unreversed)
	if keyData and keyData.Reversed and not unreversed then
		return 1 - Easing.apply(1 - alpha, keyData, true)
	end

	if alpha <= 0 then
		return 0
	end

	if alpha >= 1 then
		return 1
	end

	local style = (keyData and keyData.EasingStyle) or Defaults.EasingStyle
	if not style then
		return alpha
	end

	local styleName = resolveStyleName(style)
	if not styleName or styleName == "Linear" then
		return alpha
	end

	local nativePose = (keyData and keyData.NativePose)
		or typeof(style) == "EnumItem" and style.EnumType == Enum.PoseEasingStyle
	local direction = resolveDirName(keyData and keyData.EasingDirection) or "In"
	if styleName == "Constant" then
		if nativePose then
			if direction == "In" then
				return 1
			end

			if direction == "InOut" then
				return alpha >= 0.5 and 1 or 0
			end
		end

		return 0
	end

	if styleName == "Bezier" then
		local pts = (keyData and keyData.BezierPoints)
			or Defaults.BezierPoints
			or { 0, 0.5, 0.5, 1 }
		return bezierAlpha(alpha, pts[1] or 0, pts[2] or 0.5, pts[3] or 0.5, pts[4] or 1)
	end

	local dir = (keyData and keyData.EasingDirection) or Defaults.EasingDirection
	local dirName = resolveDirName(dir) or "In"

	if dirName == "Automatic" then
		dirName = DYNAMIC_STYLES[styleName] and "Out" or "In"
	end

	if nativePose and styleName == "Cubic" then
		if dirName == "In" then
			dirName = "Out"
		elseif dirName == "Out" then
			dirName = "In"
		end
	end

	if nativePose and styleName == "Bounce" and dirName == "InOut" then
		return alpha < 0.5 and bounceIn(alpha * 2) * 0.5 or bounceIn(alpha * 2 - 1) * 0.5 + 0.5
	end

	if keyData and keyData.MoonEasing and styleName == "Expo" then
		local function incoming(t)
			return t == 0 and 0 or 2 ^ (10 * (t - 1)) - 0.001
		end

		local function outgoing(t)
			return t == 1 and 1 or 1.001 * (1 - 2 ^ (-10 * t))
		end

		if dirName == "In" then
			return incoming(alpha)
		end

		if dirName == "Out" then
			return outgoing(alpha)
		end

		if dirName == "OutIn" then
			return alpha < 0.5 and outgoing(alpha * 2) * 0.5 or incoming(alpha * 2 - 1) * 0.5 + 0.5
		end

		if dirName == "InOut" then
			return alpha < 0.5 and 0.5 * 2 ^ (10 * (alpha * 2 - 1)) - 0.0005
				or 0.50025 * (2 - 2 ^ (-10 * (alpha * 2 - 1)))
		end
	end

	local fn = FNS[styleName .. dirName]
	if not fn then
		return alpha
	end

	return fn(alpha, keyData)
end

function Easing.apply(alpha, keyData, unreversed)
	if type(alpha) ~= "number" or alpha ~= alpha then
		return 0
	end

	const value = evaluate(alpha, keyData, unreversed)
	if type(value) ~= "number" or value ~= value or math.abs(value) > 1e4 then
		return math.clamp(alpha, 0, 1)
	end

	return value
end

return Easing
