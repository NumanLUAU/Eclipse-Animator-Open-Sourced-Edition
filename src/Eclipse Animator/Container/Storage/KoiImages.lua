--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Images = {}
local replacements = {
	["rbxassetid://105561207315636"] = "rbxassetid://91091098645973",
	["rbxassetid://132536422183741"] = "rbxassetid://121276834142754",
	["rbxassetid://89406536569773"] = "rbxassetid://131860602705174",
	["rbxassetid://72429730662854"] = "rbxassetid://126356592357060",
	["rbxassetid://75361382427064"] = "rbxassetid://140590088106643",
	["rbxassetid://117968822545717"] = "rbxassetid://137569992678849",
	["rbxassetid://102497504077936"] = "rbxassetid://124139772319591",
	["rbxassetid://118369198048768"] = "rbxassetid://139855275109258",
	["rbxassetid://117006925643669"] = "rbxassetid://75136526597344",
	["rbxassetid://113485752313585"] = "rbxassetid://75635778587008",
	["rbxassetid://129326113681487"] = "rbxassetid://112549857601371",
	["rbxassetid://72463095200997"] = "rbxassetid://75941227839628",
	["rbxassetid://133283074505512"] = "rbxassetid://118918493642196",
	["rbxassetid://121132626176993"] = "rbxassetid://81859074506422",
	["rbxassetid://134449038632951"] = "rbxassetid://95141322864439",
	["rbxassetid://80882299030377"] = "rbxassetid://122848153181812",
	["rbxassetid://106779236220813"] = "rbxassetid://71594693282896",
	["rbxassetid://98445082914995"] = "rbxassetid://117065182304413",
	["rbxassetid://131044217708473"] = "rbxassetid://103188490039260",
	["rbxassetid://132430974734326"] = "rbxassetid://115834384175189",
	["rbxassetid://96630624407144"] = "rbxassetid://95956878679536",
	["rbxassetid://123950180236924"] = "rbxassetid://129637775436929",
	["rbxassetid://71440101388823"] = "rbxassetid://117243023904164",
	["rbxassetid://122330179963898"] = "rbxassetid://110713994308804",
	["rbxassetid://104907242874598"] = "rbxassetid://92636239001293",
	["rbxassetid://126702317746647"] = "rbxassetid://77763941450498",
	["rbxassetid://111024214615860"] = "rbxassetid://92458646000071",
	["rbxassetid://134068229209998"] = "rbxassetid://104193885673605",
}
local padded = {}
for _, id in replacements do
	padded[id] = true
end

function Images.resolve(id)
	return replacements[id] or id
end

function Images.crop(label, id, source)
	if replacements[id] or padded[id] then
		label.ImageRectOffset = source and source.ImageRectOffset or Vector2.zero
		local size = source and source.ImageRectSize or Vector2.zero
		label.ImageRectSize = size.Magnitude > 0 and size or Vector2.new(540, 290)
	end
end

local frames = {
	{ id = "118830133500201", ms = 30 },
	{ id = "134822925322635", ms = 30 },
	{ id = "108045000852842", ms = 30 },
	{ id = "136641146244159", ms = 30 },
	{ id = "78190831145070", ms = 30 },
	{ id = "130817966069452", ms = 30 },
	{ id = "114753745396265", ms = 30 },
	{ id = "112656675151882", ms = 30 },
	{ id = "86634276585436", ms = 30 },
	{ id = "70529046775387", ms = 30 },
	{ id = "107513092093602", ms = 30 },
	{ id = "76477960662316", ms = 30 },
	{ id = "97130905670187", ms = 30 },
	{ id = "130138637978643", ms = 30 },
	{ id = "126521298543653", ms = 30 },
	{ id = "107588738360451", ms = 30 },
	{ id = "92088067403952", ms = 30 },
	{ id = "136197456889274", ms = 70 },
	{ id = "103001728107521", ms = 70 },
	{ id = "130115536516334", ms = 70 },
	{ id = "122470453094083", ms = 70 },
	{ id = "88161034329351", ms = 70 },
	{ id = "125045653682588", ms = 70 },
	{ id = "124655823835033", ms = 70 },
	{ id = "108349063102849", ms = 70 },
	{ id = "134497259160433", ms = 70 },
	{ id = "125211950054604", ms = 70 },
	{ id = "117984959414093", ms = 70 },
	{ id = "104430671018982", ms = 70 },
}
local indices = {}
for i, frame in frames do
	indices[frame.id] = i
end

indices["105561207315636"] = 1
indices["91091098645973"] = 1
indices["132536422183741"] = 2
indices["121276834142754"] = 2
indices["89406536569773"] = 3
indices["131860602705174"] = 3
indices["72429730662854"] = 5
indices["126356592357060"] = 5
indices["75361382427064"] = 6
indices["140590088106643"] = 6
indices["117968822545717"] = 7
indices["137569992678849"] = 7
indices["102497504077936"] = 8
indices["124139772319591"] = 8
indices["118369198048768"] = 9
indices["139855275109258"] = 9
indices["117006925643669"] = 10
indices["75136526597344"] = 10
indices["113485752313585"] = 11
indices["75635778587008"] = 11
indices["129326113681487"] = 12
indices["112549857601371"] = 12
indices["72463095200997"] = 13
indices["75941227839628"] = 13
indices["133283074505512"] = 14
indices["118918493642196"] = 14
indices["121132626176993"] = 15
indices["81859074506422"] = 15
indices["134449038632951"] = 16
indices["95141322864439"] = 16
indices["80882299030377"] = 17
indices["122848153181812"] = 17
indices["106779236220813"] = 18
indices["71594693282896"] = 18
indices["98445082914995"] = 19
indices["117065182304413"] = 19
indices["131044217708473"] = 20
indices["103188490039260"] = 20
indices["132430974734326"] = 21
indices["115834384175189"] = 21
indices["96630624407144"] = 22
indices["95956878679536"] = 22
indices["123950180236924"] = 23
indices["129637775436929"] = 23
indices["71440101388823"] = 24
indices["117243023904164"] = 24
indices["122330179963898"] = 25
indices["110713994308804"] = 25
indices["104907242874598"] = 26
indices["92636239001293"] = 26
indices["126702317746647"] = 27
indices["77763941450498"] = 27
indices["111024214615860"] = 28
indices["92458646000071"] = 28
indices["134068229209998"] = 29
indices["104193885673605"] = 29
indices["87450192301308"] = 4

local function assetId(value)
	return tostring(value or ""):gsub("^rbxassetid://", "")
end

function Images.frames()
	local out = {}
	for _, frame in frames do
		table.insert(out, table.clone(frame))
	end

	return out
end

function Images.isSequence(sequence)
	if type(sequence) ~= "table" or (#sequence ~= 28 and #sequence ~= 29) then
		return false
	end

	local missing = #sequence == 28
	for i, frame in sequence do
		local expected = missing and i >= 4 and i + 1 or i
		if type(frame) ~= "table" or indices[assetId(frame.image or frame.id)] ~= expected then
			return false
		end
	end

	return true
end

function Images.migrate(data)
	if not Images.isSequence(data.Gif) then
		return data
	end

	local old = data.Gif
	local current = #old == #frames
	for i, frame in old do
		if assetId(frame.image or frame.id) ~= frames[i].id then
			current = false
			break
		end
	end

	if current then
		return data
	end

	local out = table.clone(data)
	out.Gif = Images.frames()
	out.KoiFrames = 3

	for _, frame in old do
		local index = indices[assetId(frame.image or frame.id)]
		local delay = tonumber(frame.delay or frame.ms)
		if delay then
			out.Gif[index].ms = delay
		end
	end

	local imageIndex = indices[assetId(data.Img)]
	if imageIndex then
		out.Img = frames[imageIndex].id
	end

	return out
end

return Images
