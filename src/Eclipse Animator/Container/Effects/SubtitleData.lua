--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = {}
Data.motions = {
	"None",
	"Fade",
	"Slide up",
	"Slide down",
	"Slide left",
	"Slide right",
	"Pop",
	"Zoom",
	"Spin",
	"Typewriter",
	"Word by word",
	"Wipe",
	"Letter pop",
	"Letter slide",
	"Letter drop",
	"Word spring",
}
Data.fonts = {
	"Gotham",
	"SourceSans",
	"BuilderSans",
	"Arial",
	"Arimo",
	"Roboto",
	"RobotoCondensed",
	"RobotoMono",
	"Ubuntu",
	"Nunito",
	"Oswald",
	"TitilliumWeb",
	"JosefinSans",
	"Jura",
	"Michroma",
	"Sarpanch",
	"Highway",
	"Code",
	"Bodoni",
	"Garamond",
	"Merriweather",
	"Antique",
	"AmaticSC",
	"Bangers",
	"Cartoon",
	"Creepster",
	"DenkOne",
	"Fantasy",
	"Fondamento",
	"FredokaOne",
	"GrenzeGotisch",
	"IndieFlower",
	"Kalam",
	"LuckiestGuy",
	"PatrickHand",
	"PermanentMarker",
	"SciFi",
	"SpecialElite",
	"Arcade",
}
Data.defaults = {
	Text = "Your subtitle",
	Speaker = "",
	Image = "",
	ImageSide = "Left",
	ImageShape = "Circle",
	ImageSize = 64,
	Size = 28,
	Font = "Gotham",
	Bold = true,
	Italic = false,
	Underline = false,
	Color = "FFFFFF",
	NameColor = "FFFFFF",
	NameBold = true,
	NameItalic = false,
	NameSize = 21,
	NameOffset = 4,
	NameOutline = 1,
	NameOutlineColor = "000000",
	NameFont = "Gotham",
	OutlineColor = "15111D",
	Outline = 1,
	Background = "15111D",
	BackgroundOpacity = 0,
	Padding = 12,
	Radius = 8,
	Width = 0.65,
	Position = "Bottom",
	Align = "Center",
	X = 0,
	Y = 0,
	Scale = 1,
	Rotation = 0,
	Opacity = 1,
	Rainbow = false,
	RainbowSpeed = 0.2,
	RainbowSpread = 0.05,
	Gradient = false,
	GradientColor = "A7C8FF",
	GradientAngle = 90,
	Jitter = 0,
	JitterSpeed = 18,
	JitterDecay = 0,
	Wave = 0,
	Pulse = 0,
	Words = {},
}
local ranges = {
	NameOffset = { -20, 30 },
	NameOutline = { 0, 5 },
	JitterDecay = { 0, 10 },
	NameSize = { 12, 72 },
	RainbowSpread = { 0, 2 },
	GradientAngle = { 0, 360 },
	Size = { 12, 96 },
	ImageSize = { 24, 160 },
	Outline = { 0, 5 },
	BackgroundOpacity = { 0, 1 },
	Padding = { 0, 40 },
	Radius = { 0, 32 },
	Width = { 0.2, 0.95 },
	X = { -0.4, 0.4 },
	Y = { -0.4, 0.4 },
	Scale = { 0.4, 2 },
	Rotation = { -45, 45 },
	Opacity = { 0, 1 },
	RainbowSpeed = { 0, 3 },
	Jitter = { 0, 20 },
	JitterSpeed = { 1, 60 },
	Wave = { 0, 20 },
	Pulse = { 0, 0.4 },
}
local colors = {
	NameOutlineColor = true,
	GradientColor = true,
	Color = true,
	NameColor = true,
	OutlineColor = true,
	Background = true,
}
local choices = {
	NameFont = Data.fonts,
	Font = Data.fonts,
	ImageSide = { "Left", "Right", "Above" },
	ImageShape = { "Circle", "Square" },
	Position = { "Bottom", "Center", "Top" },
	Align = { "Center", "Left", "Right" },
}

local function number(v, fallback, lo, hi)
	v = tonumber(v)
	if not v or v ~= v or math.abs(v) == math.huge then
		return fallback
	end

	return math.clamp(v, lo, hi)
end

function Data.rescale(value, ratio)
	local cue = Data.copy(value)
	if not cue then
		return nil
	end

	for _, field in { "Duration", "InFrames", "OutFrames" } do
		cue[field] = math.round(cue[field] * ratio)
	end

	for _, key in cue.Keys do
		key.Frame = math.round(key.Frame * ratio)
	end

	return Data.copy(cue)
end

function Data.hex(value, fallback)
	value = tostring(value or ""):gsub("#", ""):upper()
	return value:match("^%x%x%x%x%x%x$") and value or fallback or "FFFFFF"
end

function Data.color(value)
	return Color3.fromHex(Data.hex(value))
end

function Data.clone(value)
	if type(value) ~= "table" then
		return value
	end

	local out = {}
	for k, v in value do
		out[k] = Data.clone(v)
	end

	return out
end

local function text(value, limit)
	local s = value:sub(1, limit)
	while #s > 0 and not utf8.len(s) do
		s = s:sub(1, -2)
	end

	return s
end

function Data.style(value)
	value = type(value) == "table" and value or {}
	local out = Data.clone(Data.defaults)
	for key, default in Data.defaults do
		local v = value[key]
		if ranges[key] then
			out[key] = number(v, default, ranges[key][1], ranges[key][2])
		elseif colors[key] then
			out[key] = Data.hex(v, default)
		elseif choices[key] then
			out[key] = table.find(choices[key], v) and v or default
		elseif type(default) == "boolean" then
			out[key] = v == nil and default or v == true
		elseif type(default) == "string" then
			out[key] = type(v) == "string" and text(v, key == "Text" and 2000 or 160) or default
		end
	end

	if value.NameBold == nil and value.NameColor == "CBB5FF" then
		out.NameColor = "FFFFFF"
	end

	out.Image = out.Image:gsub("rbxassetid://", "")
	if not out.Image:match("^%d+$") then
		out.Image = ""
	end

	for index, word in type(value.Words) == "table" and value.Words or {} do
		local i = tonumber(index)
		if i and i % 1 == 0 and i >= 1 and i <= 300 and type(word) == "table" then
			local w = {}
			if word.Color then
				w.Color = Data.hex(word.Color)
			end

			for _, key in { "Bold", "Italic", "Underline", "Rainbow" } do
				if type(word[key]) == "boolean" then
					w[key] = word[key]
				end
			end

			if word.Jitter ~= nil then
				w.Jitter = number(word.Jitter, 0, 0, 20)
			end

			out.Words[tostring(i)] = w
		end
	end

	return out
end

function Data.copy(value)
	if type(value) ~= "table" then
		return nil
	end

	local out = {
		Version = 1,
		Duration = math.floor(number(value.Duration, 180, 1, 1000000)),
		Base = Data.style(value.Base),
		Keys = {},
		Entrance = table.find(Data.motions, value.Entrance) and value.Entrance or "Fade",
		Exit = table.find(Data.motions, value.Exit) and value.Exit or "Fade",
		InFrames = math.floor(number(value.InFrames, 12, 0, 100000)),
		OutFrames = math.floor(number(value.OutFrames, 12, 0, 100000)),
		Order = math.floor(number(value.Order, 0, -1000, 1000)),
		Preset = tostring(value.Preset or "Clean"),
	}
	local byFrame = {}
	for _, key in type(value.Keys) == "table" and value.Keys or {} do
		if type(key) == "table" and tonumber(key.Frame) then
			local frame = math.floor(number(key.Frame, 0, 0, 1000000))
			if frame > 0 and frame < out.Duration then
				byFrame[frame] = {
					Frame = frame,
					Value = Data.style(key.Value),
					Ease = key.Ease == "Hold" and "Hold"
						or key.Ease == "Linear" and "Linear"
						or "Smooth",
				}
			end
		end
	end

	for _, key in byFrame do
		table.insert(out.Keys, key)
	end

	table.sort(out.Keys, function(a, b)
		return a.Frame < b.Frame
	end)
	while #out.Keys > 128 do
		table.remove(out.Keys)
	end

	local total = out.InFrames + out.OutFrames
	if total > out.Duration then
		out.InFrames = math.floor(out.InFrames * out.Duration / total)
		out.OutFrames = out.Duration - out.InFrames
	end

	return out
end

function Data.sample(cue, frame)
	local left = { Frame = 0, Value = cue.Base, Ease = "Smooth" }
	local right
	for _, key in cue.Keys do
		if key.Frame <= frame then
			left = key
		else
			right = key
			break
		end
	end

	local out = Data.clone(left.Value)
	if right and right.Ease ~= "Hold" then
		local alpha = math.clamp((frame - left.Frame) / (right.Frame - left.Frame), 0, 1)
		if right.Ease ~= "Linear" then
			alpha = alpha * alpha * (3 - 2 * alpha)
		end

		for key in ranges do
			out[key] = left.Value[key] + (right.Value[key] - left.Value[key]) * alpha
		end

		for key in colors do
			out[key] = Data.color(left.Value[key]):Lerp(Data.color(right.Value[key]), alpha):ToHex()
		end
	end

	return out
end

function Data.key(cue, frame)
	frame = math.clamp(math.floor(frame + 0.5), 0, cue.Duration - 1)
	if frame == 0 then
		return { Frame = 0, Value = cue.Base }, false
	end

	for _, key in cue.Keys do
		if key.Frame == frame then
			return key, false
		end
	end

	if #cue.Keys >= 128 then
		return nil, false
	end

	local key = { Frame = frame, Value = Data.sample(cue, frame), Ease = "Smooth" }
	table.insert(cue.Keys, key)
	table.sort(cue.Keys, function(a, b)
		return a.Frame < b.Frame
	end)
	return key, true
end

function Data.spring(t)
	if t <= 0 then
		return 0
	end

	if t >= 1 then
		return 1
	end

	local damping, frequency = 7.5, 10
	local value = 1
		- math.exp(-damping * t)
			* (math.cos(frequency * t) + damping / frequency * math.sin(frequency * t))
	local endpoint = 1
		- math.exp(-damping) * (math.cos(frequency) + damping / frequency * math.sin(frequency))
	return value / endpoint
end

local function classify(code)
	if code < 0x80 then
		if code >= 65 and code <= 90 or code >= 97 and code <= 122 then
			return "L"
		end

		return code >= 48 and code <= 57 and "N" or "O"
	end

	if code == 0x200F then
		return "R"
	elseif code == 0x200E then
		return "L"
	end

	if
		code >= 0x0590 and code <= 0x08FF
		or code >= 0xFB1D and code <= 0xFDFF
		or code >= 0xFE70 and code <= 0xFEFE
		or code >= 0x10800 and code <= 0x10FFF
		or code >= 0x1E800 and code <= 0x1EFFF
	then
		return (code >= 0x0660 and code <= 0x066C or code >= 0x06F0 and code <= 0x06F9) and "N"
			or "R"
	end

	if
		code <= 0xBF
		or code == 0xD7
		or code == 0xF7
		or code == 0xFEFF
		or code >= 0x0300 and code <= 0x036F
		or code >= 0x2000 and code <= 0x2BFF
		or code >= 0x2E00 and code <= 0x2E7F
		or code >= 0x3000 and code <= 0x303F
		or code >= 0xFE00 and code <= 0xFE6F
		or code >= 0xFF00 and code <= 0xFF20
		or code >= 0xFFF0 and code <= 0xFFFF
		or code >= 0x1F000 and code <= 0x1FBFF
		or code >= 0xE0000
	then
		return code >= 0xFF10 and code <= 0xFF19 and "N" or "O"
	end

	return "L"
end

function Data.script(value)
	if not utf8.len(value) then
		value = value:gsub("[\128-\255]", "")
	end

	local strong, digit, rtl = nil, false, false
	for _, code in utf8.codes(value) do
		const kind = classify(code)
		rtl = rtl or kind == "R"
		digit = digit or kind == "N"
		if not strong and (kind == "R" or kind == "L") then
			strong = kind
		end
	end

	return strong or digit and "N" or "O", rtl
end

function Data.levels(classes, rtl)
	const base = rtl and "R" or "L"
	const types = {}
	local strong = base
	for i, class in classes do
		if i > 1 then
			table.insert(types, "O")
		end

		if class == "R" or class == "L" then
			strong = class
		elseif class == "N" then
			class = strong == "L" and "L" or "D"
		end

		table.insert(types, class)
	end

	const count = #types
	local i = 1
	while i <= count do
		if types[i] == "O" then
			local j = i
			while j < count and types[j + 1] == "O" do
				j += 1
			end

			const left = (i > 1 and types[i - 1] or base) == "L" and "L" or "R"
			const right = (j < count and types[j + 1] or base) == "L" and "L" or "R"
			const kind = left == right and left or base
			for k = i, j do
				types[k] = kind
			end

			i = j + 1
		else
			i += 1
		end
	end

	const levels = table.create(count)
	for k, kind in types do
		levels[k] = kind == "D" and 2 or kind == "R" and 1 or rtl and 2 or 0
	end

	return levels
end

function Data.reorder(levels, first, last)
	const order = {}
	local high = 0
	for k = first * 2 - 1, last * 2 - 1 do
		table.insert(order, k)
		high = math.max(high, levels[k] or 0)
	end

	const count = #order
	for level = high, 1, -1 do
		local k = 1
		while k <= count do
			if (levels[order[k]] or 0) >= level then
				local j = k
				while j < count and (levels[order[j + 1]] or 0) >= level do
					j += 1
				end

				for n = 0, (j - k - 1) // 2 do
					order[k + n], order[j - n] = order[j - n], order[k + n]
				end

				k = j + 1
			else
				k += 1
			end
		end
	end

	const words = {}
	for _, k in order do
		if k % 2 == 1 then
			table.insert(words, (k + 1) // 2)
		end
	end

	return words
end

function Data.letters(kind)
	return kind == "Letter pop"
		or kind == "Letter slide"
		or kind == "Letter drop"
		or kind == "Word spring"
end

function Data.motion(cue, frame)
	local result =
		{ alpha = 1, x = 0, y = 0, scale = 1, rotation = 0, reveal = 1, words = false, wipe = 1 }

	local function apply(kind, progress, enter)
		if kind == "None" or Data.letters(kind) then
			return
		end

		local spring = enter and Data.spring(progress) or 1 - (1 - progress) ^ 2
		local remaining = 1 - spring
		if kind == "Wipe" then
			result.wipe = math.min(result.wipe, progress)
		elseif kind == "Typewriter" or kind == "Word by word" then
			result.reveal = math.min(result.reveal, progress)
			result.words = kind == "Word by word"
		else
			result.alpha *= math.clamp(progress * 2, 0, 1)
		end

		if kind == "Slide up" then
			result.y += (enter and 1 or -1) * remaining * 42
		elseif kind == "Slide down" then
			result.y += (enter and -1 or 1) * remaining * 42
		elseif kind == "Slide left" then
			result.x += (enter and 1 or -1) * remaining * 72
		elseif kind == "Slide right" then
			result.x += (enter and -1 or 1) * remaining * 72
		elseif kind == "Pop" then
			result.scale *= math.max(0.01, 0.55 + 0.45 * spring)
		elseif kind == "Zoom" then
			result.scale *= 0.75 + 0.25 * spring
		elseif kind == "Spin" then
			result.rotation += remaining * (enter and -12 or 12)
			result.scale *= 0.8 + 0.2 * spring
		end
	end

	if cue.InFrames > 0 and frame < cue.InFrames then
		apply(cue.Entrance, math.clamp(frame / cue.InFrames, 0, 1), true)
	end

	if cue.OutFrames > 0 and frame > cue.Duration - cue.OutFrames then
		apply(cue.Exit, math.clamp((cue.Duration - frame) / cue.OutFrames, 0, 1), false)
	end

	return result
end

function Data.glyph(cue, frame, index, count, word, wordCount, fps, style, clock)
	local out = { alpha = 1, scale = 1, x = 0, y = 0, rotation = 0 }
	local born = 0

	local function apply(kind, age, duration, enter)
		if not Data.letters(kind) or duration <= 0 then
			return
		end

		local rank = kind == "Word spring" and word or index
		local total = kind == "Word spring" and wordCount or count
		local delay = (rank - 1) / math.max(1, total - 1) * duration * 0.6
		local span = math.max(1, duration * 0.4)
		local p = math.clamp((age - delay) / span, 0, 1)
		if enter then
			born = delay
		end

		local value = enter and Data.spring(p) or p * p
		local remaining = enter and 1 - value or value
		out.alpha *= enter and math.clamp(p * 2, 0, 1) or 1 - p
		if kind == "Letter pop" then
			out.scale *= math.max(0.01, 1 + remaining * 0.65)
		elseif kind == "Letter drop" then
			out.y += remaining * (enter and -26 or 42)
			out.rotation += remaining * ((index % 3) - 1) * 7
		else
			out.y += remaining * 18
		end
	end

	apply(cue.Entrance, frame, cue.InFrames, true)
	apply(cue.Exit, frame - (cue.Duration - cue.OutFrames), cue.OutFrames, false)
	local time = clock or frame / fps
	local tick = math.floor(time * style.JitterSpeed)
	local decay = style.JitterDecay > 0
			and math.clamp(1 - math.max(0, frame - born) / fps / style.JitterDecay, 0, 1)
		or 1
	local strength = style.Jitter * decay
	out.x += math.sin(tick * 127.1 + index * 311.7) * strength
	out.y += math.sin(tick * 269.5 + index * 183.3) * strength
	return out
end

Data.presets = {}

local function preset(name, style, entrance, exit)
	table.insert(
		Data.presets,
		{ Name = name, Style = style, Entrance = entrance or "Fade", Exit = exit or "Fade" }
	)
end

preset("Clean", { Size = 28, Bold = true })
preset("Outlined", { Size = 34, Outline = 3 })
preset("Dialogue", {
	Font = "SourceSans",
	BackgroundOpacity = 0,
	Align = "Center",
	Width = 0.6,
	ImageSide = "Above",
	Size = 28,
	Jitter = 3,
	JitterDecay = 0.5,
}, "Letter pop", "Letter drop")
preset(
	"Portrait",
	{ BackgroundOpacity = 0.65, ImageSide = "Above", ImageSize = 72, Width = 0.5 },
	"Pop"
)
preset("Whisper", { Italic = true, Bold = false, Size = 24, Opacity = 0.85 }, "Fade")
preset("Comic", { Font = "Cartoon", Color = "FFDC54", Outline = 3, Size = 38 }, "Pop", "Spin")
preset("Typewriter", { Font = "RobotoMono", Size = 28, Bold = false }, "Typewriter")
preset("Word reveal", { Size = 34 }, "Word by word")
preset("Rainbow", { Rainbow = true, Size = 34 }, "Fade")
preset(
	"Unhinged",
	{ Jitter = 7, JitterSpeed = 24, Rotation = -2, Size = 36, Color = "FF7878" },
	"Spin",
	"Pop"
)
preset("Letter pop", { Font = "SourceSans", Size = 28 }, "Letter pop", "Letter drop")
preset("Letter slide", {}, "Letter slide", "Fade")
preset("Word spring", { Size = 32 }, "Word spring", "Slide down")
preset("Tremble", { Jitter = 2, JitterSpeed = 12, Italic = true }, "Fade")
preset("Wave", { Wave = 5, Color = "A1E7FF" }, "Slide up", "Slide down")
preset("Pulse", { Pulse = 0.08, Color = "FFD2EB" }, "Pop")
preset("Film", { Font = "Garamond", Size = 34, Bold = false, Color = "FFF1DA" }, "Fade")
preset(
	"Top caption",
	{ Position = "Top", Size = 42, Outline = 3, Width = 0.9, Align = "Left" },
	"None",
	"None"
)
preset(
	"Lower third",
	{ Align = "Left", BackgroundOpacity = 0.85, Width = 0.75, Size = 28, ImageShape = "Square" },
	"Slide right",
	"Slide left"
)
preset(
	"News",
	{ Background = "143254", BackgroundOpacity = 0.95, Align = "Left", Width = 0.85, Size = 28 },
	"Slide left"
)
preset(
	"Retro",
	{ Font = "Code", Color = "7EFF99", BackgroundOpacity = 0.8, Radius = 0 },
	"Typewriter",
	"Wipe"
)
preset("Horror", { Font = "Garamond", Color = "E94545", Jitter = 1.5, Size = 38 }, "Fade", "Fade")
preset("Dreamy", { Color = "D4C4FF", Italic = true, Wave = 2, Size = 32 }, "Zoom")
preset("Neon", { Color = "7CF7FF", OutlineColor = "7138BA", Outline = 3, Size = 36 }, "Pop")
preset(
	"Bold card",
	{ BackgroundOpacity = 0.95, Size = 36, Padding = 20, Radius = 16 },
	"Zoom",
	"Zoom"
)
preset("Minimal", { Size = 24, Bold = false, Outline = 0, BackgroundOpacity = 0.55 }, "Fade")
preset("Slide up", {}, "Slide up", "Slide up")
preset("Slide down", {}, "Slide down", "Slide down")
preset("Slide left", {}, "Slide left", "Slide left")
preset("Slide right", {}, "Slide right", "Slide right")
preset("Spin", { Size = 36 }, "Spin", "Spin")
preset(
	"Center title",
	{ Position = "Center", Size = 52, Width = 0.85, Outline = 2 },
	"Zoom",
	"Fade"
)
preset(
	"Handwritten",
	{ Font = "Kalam", Size = 30, Bold = false, Outline = 1, Color = "FFF1DA" },
	"Letter slide",
	"Fade"
)
preset("Shout", { Size = 48, Font = "Bangers", Outline = 3, Jitter = 2 }, "Pop", "Zoom")

function Data.preset(name, previous)
	local cue = Data.copy(previous or {})
	local row
	for _, v in Data.presets do
		if v.Name == name then
			row = v
			break
		end
	end

	if not row then
		return cue
	end

	local style = Data.clone(Data.defaults)
	for _, key in { "Text", "Speaker", "Image", "Words" } do
		style[key] = Data.clone(cue.Base[key])
	end

	for key, value in row.Style do
		style[key] = value
	end

	cue.Base = Data.style(style)
	cue.Preset = name
	cue.Entrance = row.Entrance
	cue.Exit = row.Exit
	if Data.letters(cue.Entrance) then
		cue.InFrames = math.min(42, math.floor(cue.Duration * 0.4))
	end

	if Data.letters(cue.Exit) then
		cue.OutFrames = math.min(30, math.floor(cue.Duration * 0.3))
	end

	return cue
end

return Data
