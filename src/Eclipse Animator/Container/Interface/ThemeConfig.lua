--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local ThemeConfig = {}

ThemeConfig.version = 1
ThemeConfig.settingKey = "EclipseThemeV1"

local legacyDefault = {

	Bg = "#210031>#0a0a0a@90",
	Top = "#210031",
	TopBtn = "#33004d",
	TopT = "#ffffff",
	Ctrl = "#ac9bc3>#675680@90",
	CtrlIc = "#261a34",
	Pnl = "#160020",
	Txt = "#ebe4f2",
	Menu = "#3a2154>#1c0a2a>#0d0414@90",
	MenuHov = "#220034",
	MenuSel = "#640097",
	Tip = "#ffffff",
	TipT = "#1f1f1f",
	Scr = "#b271e5",
	AddBtn = "#85153b>#55ff00@90",
	Div = "#30103a",
	Loop = "#85153b>#ffaa00@90",
	M = "A",
	Ph = "#c5426e",
	Rec = "#85153b>#9c0000@90",
	Strk = "#45295d",
	TopStrk = "#45295d",
	Trk = "#321040",
	V = 1,
}

ThemeConfig.settings = {
	{
		key = "Img",
		label = "Background Image",
		desc = "Image shown behind the timeline content.",
		cat = "Core",
		kind = "image",
	},
	{
		key = "Bg",
		label = "Window Background",
		desc = "Backdrop of the animator and menu windows.",
		cat = "Core",
	},
	{ key = "Top", label = "Topbar Color", desc = "Background of the top bars.", cat = "Core" },
	{
		key = "TopBtn",
		label = "Topbar Buttons",
		desc = "File/Edit/Tools button backgrounds.",
		cat = "Core",
	},
	{ key = "TopT", label = "Topbar Text", desc = "Text on the top bars.", cat = "Core" },
	{
		key = "TopStrk",
		label = "Topbar Outline",
		desc = "Outline around the top bars.",
		cat = "Core",
	},
	{
		key = "Ctrl",
		label = "Control Buttons",
		desc = "Save, export and exit buttons.",
		cat = "Core",
	},
	{
		key = "CtrlIc",
		label = "Control Icons",
		desc = "Icons inside the control buttons.",
		cat = "Core",
	},
	{ key = "Pnl", label = "Panel Color", desc = "Inner panels and containers.", cat = "Core" },
	{
		key = "Div",
		label = "Divider Color",
		desc = "Editor separators and the line under frame numbers.",
		cat = "Core",
	},
	{
		key = "Strk",
		label = "Panel Outlines",
		desc = "Borders around the timeline, panels and editors.",
		cat = "Core",
	},
	{
		key = "Scr",
		label = "Scroll Bar Color",
		desc = "Color of all scroll bars.",
		cat = "Core",
	},
	{
		key = "Txt",
		label = "Text Color",
		desc = "General text and editable values, including RGB and hex fields.",
		cat = "Core",
	},
	{ key = "Tip", label = "Tooltip Color", desc = "Hover tooltip background.", cat = "Core" },
	{ key = "TipT", label = "Tooltip Text", desc = "Hover tooltip text.", cat = "Core" },

	{
		key = "Menu",
		label = "Dropdown Color",
		desc = "Dropdown panel backdrop.",
		cat = "Menus",
	},
	{
		key = "MenuHov",
		label = "Dropdown Hover",
		desc = "Dropdown row hover color.",
		cat = "Menus",
		kind = "script",
	},
	{
		key = "MenuSel",
		label = "Dropdown Selected",
		desc = "Dropdown row selected color.",
		cat = "Menus",
		kind = "script",
	},

	{
		key = "Slider",
		label = "Timeline Sliders",
		desc = "The zoom/scroll slider bars.",
		cat = "Timeline",
	},
	{
		key = "Ph",
		label = "Playhead",
		desc = "The playhead line and frame chip.",
		cat = "Timeline",
	},
	{
		key = "Trk",
		label = "Track Lines",
		desc = "The bone track rows in the timeline.",
		cat = "Timeline",
	},
	{
		key = "TrackOn",
		label = "Track Enabled Icon",
		desc = "Color and transparency of enabled track checkboxes.",
		cat = "Timeline",
	},
	{
		key = "TrackOff",
		label = "Track Disabled Icon",
		desc = "Color and transparency of disabled track checkboxes.",
		cat = "Timeline",
	},
	{
		key = "Sel",
		label = "Selection Highlight",
		desc = "Selected bones and rig list items.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "Tick",
		label = "Tick Text",
		desc = "Frame numbers along the timeline.",
		cat = "Timeline",
	},
	{
		key = "KfD",
		label = "Keyframe Default",
		desc = "Default keyframe color.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "KfH",
		label = "Keyframe Hover",
		desc = "Hovered keyframe color.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "KfS",
		label = "Keyframe Selected",
		desc = "Selected keyframe color.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "KfAuto",
		label = "Key: Automatic",
		desc = "Automatic handle keyframes.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "KfAli",
		label = "Key: Aligned",
		desc = "Aligned handle keyframes.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "KfAC",
		label = "Key: Auto Clamped",
		desc = "Auto clamped handle keyframes.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "KfVec",
		label = "Key: Vector",
		desc = "Vector handle keyframes.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "AddBtn",
		label = "Add Button",
		desc = "The add rig/object button.",
		cat = "Timeline",
	},
	{
		key = "KfFree",
		label = "Key: Free",
		desc = "Free handle keyframes.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "Loop",
		label = "Loop Button",
		desc = "Loop button while active.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "LoopOff",
		label = "Loop Inactive",
		desc = "Loop button while off.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "Rec",
		label = "Record Button",
		desc = "Record button while active.",
		cat = "Timeline",
		kind = "script",
	},
	{
		key = "RecOff",
		label = "Record Inactive",
		desc = "Record button while off.",
		cat = "Timeline",
		kind = "script",
	},
}

ThemeConfig.scriptColorMap = {
	KfD = "KEYFRAME_DEFAULT_COLOR",
	KfH = "KEYFRAME_HOVER_COLOR",
	KfS = "KEYFRAME_SELECTED_COLOR",
	Loop = "LOOP_ACTIVE_COLOR",
	LoopOff = "LOOP_INACTIVE_COLOR",
	Rec = "RECORD_ACTIVE_COLOR",
	RecOff = "RECORD_INACTIVE_COLOR",
}

ThemeConfig.scriptDefaults = {
	TrackOn = "#71ff3d",
	TrackOff = "#3a3a3a",
	Sel = "#680aff",
	MenuHov = "#220034",
	MenuSel = "#640097",
}

ThemeConfig.scriptHandleMap = {
	KfAuto = "Automatic",
	KfAli = "Aligned",
	KfAC = "AutoClamped",
	KfVec = "Vector",
	KfFree = "Free",
}

ThemeConfig.simpleSettings = {
	{
		key = "Img",
		label = "Background Image",
		desc = "Image shown behind the timeline content.",
		cat = "Simple",
		kind = "image",
	},
	{
		key = "SBg",
		label = "Background",
		desc = "Base color for every surface.",
		cat = "Simple",
	},
	{
		key = "SAcc",
		label = "Accent",
		desc = "Selections, controls and highlights.",
		cat = "Simple",
	},
	{
		key = "SBtn",
		label = "Buttons",
		desc = "Buttons, strokes and scroll bars.",
		cat = "Simple",
	},
	{ key = "STxt", label = "Text", desc = "All text.", cat = "Simple" },
	{ key = "SKey", label = "Keyframes", desc = "All keyframe colors.", cat = "Simple" },
}

ThemeConfig.simpleExpand = {
	SBg = {
		{ target = "Bg" },
		{ target = "Top", mod = "darken", amt = 0.35 },
		{ target = "Pnl", mod = "lighten", amt = 0.06 },
		{ target = "Menu" },
		{ target = "Div", mod = "lighten", amt = 0.18 },
		{ target = "Trk", mod = "lighten", amt = 0.22 },
		{ target = "Tip", mod = "darken", amt = 0.2 },
	},
	SAcc = {
		{ target = "KfS" },
		{ target = "MenuSel" },
		{ target = "Ctrl" },
		{ target = "Loop" },
		{ target = "Ph" },
		{ target = "Slider" },
		{ target = "Sel" },
	},
	SBtn = {
		{ target = "TopBtn" },
		{ target = "TopStrk", mod = "lighten", amt = 0.15 },
		{ target = "AddBtn" },
		{ target = "MenuHov", mod = "darken", amt = 0.3 },
		{ target = "Strk", mod = "lighten", amt = 0.15 },
		{ target = "Scr" },
		{ target = "CtrlIc", mod = "darken", amt = 0.45 },
	},
	STxt = {
		{ target = "Txt" },
		{ target = "TopT" },
		{ target = "Tick" },
		{ target = "TipT" },
	},
	SKey = {
		{ target = "KfD" },
		{ target = "KfH", mod = "darken", amt = 0.35 },
		{ target = "KfAuto" },
		{ target = "KfAli" },
		{ target = "KfAC" },
		{ target = "KfVec" },
		{ target = "KfFree" },
	},
}

ThemeConfig.presetsKey = "EclipseThemePresetsV1"
ThemeConfig.maxUserPresets = 6

ThemeConfig.builtinPresets = {
	{ name = "Eclipse", desc = "The stock Eclipse look.", data = legacyDefault },
	{
		name = "Midnight",
		desc = "Deep blue nights.",
		data = {
			V = 1,
			M = "A",
			Bg = "#101832>#05070f@90",
			Top = "#0d1326",
			TopBtn = "#16204a",
			TopT = "#dbe6ff",
			TopStrk = "#31437e",
			Ctrl = "#9fb4e8>#5a6b9e@90",
			CtrlIc = "#131c38",
			Pnl = "#0e1428",
			Div = "#2a3a6e",
			Strk = "#31437e",
			Scr = "#4d6ac2",
			Txt = "#dbe6ff",
			Tick = "#8fa5e0",
			Menu = "#1c2850>#080b18@90",
			MenuHov = "#101b3d",
			MenuSel = "#2f4ecc",
			KfS = "#4d8dff",
			Loop = "#7fb2ff>#3f6ecc@90",
			Rec = "#4d7dff>#2848a8@90",
			AddBtn = "#6ea0e8>#3f6db8@90",
			Slider = "#31437e",
			Ph = "#7fb2ff",
			Trk = "#22304f",
			Trkt = 0.2,
			Tip = "#101b3d",
			TipT = "#dbe6ff",
			Sel = "#2f4ecc",
		},
	},
	{
		name = "Bloodmoon",
		desc = "Crimson and ash.",
		data = {
			V = 1,
			M = "A",
			Bg = "#2b070d>#0f0203@90",
			Top = "#33070d",
			TopBtn = "#571018",
			TopT = "#ffdbe0",
			TopStrk = "#7e3140",
			Ctrl = "#e89fa9>#9e5a68@90",
			CtrlIc = "#38101a",
			Pnl = "#240609",
			Div = "#6e2a35",
			Strk = "#7e3140",
			Scr = "#c24d5e",
			Txt = "#ffdbe0",
			Tick = "#e08f9c",
			Menu = "#501c26>#180408@90",
			MenuHov = "#3d1018",
			MenuSel = "#cc2f4a",
			KfS = "#ff4d6a",
			Loop = "#ff7a5e>#c24a35@90",
			Rec = "#ff5470>#b32546@90",
			AddBtn = "#c2455a>#8a2e40@90",
			Slider = "#6e2a35",
			Ph = "#ff9d4d",
			Trk = "#4a1620",
			Trkt = 0.2,
			Tip = "#3d1018",
			TipT = "#ffdbe0",
			Sel = "#cc2f4a",
		},
	},
	{
		name = "Moonlight",
		desc = "Sleek silver with an orange bite.",
		data = {
			V = 1,
			M = "A",
			Bg = "#47474e>#232327@90",
			Top = "#333338",
			TopBtn = "#4a4a52",
			TopT = "#ececec",
			TopStrk = "#60606a",
			Ctrl = "#b8b8c0>#70707a@90",
			CtrlIc = "#26262a",
			Pnl = "#2e2e33",
			Div = "#56565e",
			Strk = "#60606a",
			Scr = "#94949e",
			Txt = "#ececec",
			Tick = "#a2a2ac",
			Menu = "#414147>#1e1e22@90",
			MenuHov = "#2e2e33",
			MenuSel = "#c26a2f",
			KfS = "#e07a35",
			Loop = "#e0812f>#a8571c@90",
			Rec = "#d4622e>#9c4218@90",
			AddBtn = "#e09a45>#a86a24@90",
			Slider = "#c26a2f",
			Ph = "#e07a35",
			Trk = "#8a5a34",
			Trkt = 0.2,
			Tip = "#2e2e33",
			TipT = "#ececec",
			Sel = "#c26a2f",
		},
	},
}

table.insert(ThemeConfig.builtinPresets, {
	name = "Koi [GIF]",
	desc = "Koi in deep teal water, with pearl and rose accents.",
	data = {
		["V"] = 1,
		["M"] = "A",
		["Bg"] = "#102e36>#06181f@90",
		["Top"] = "#0d262d",
		["TopBtn"] = "#193c43",
		["TopT"] = "#e1f3ee",
		["TopStrk"] = "#37636a",
		["Ctrl"] = "#c2ddd1>#63948f@90",
		["CtrlIc"] = "#102c32",
		["Pnl"] = "#10272e",
		["Div"] = "#284a52",
		["Strk"] = "#37636a",
		["Scr"] = "#589895",
		["Txt"] = "#e1f3ee",
		["Tick"] = "#93b6b7",
		["Menu"] = "#14383f>#081b24@90",
		["MenuHov"] = "#22444b",
		["MenuSel"] = "#93485f",
		["KfS"] = "#df93ab",
		["Loop"] = "#dba0b0>#407e77@90",
		["Rec"] = "#dba0b0>#96516a@90",
		["AddBtn"] = "#8bbeb1>#467f7c@90",
		["Slider"] = "#386c71",
		["Ph"] = "#e6a2b6",
		["Trk"] = "#29494f",
		["Trkt"] = 0.2,
		["Tip"] = "#102c33",
		["TipT"] = "#e1f3ee",
		["Sel"] = "#93485f",
		["Gif"] = require("KoiImages").frames(),
		["KoiFrames"] = 3,
		["Imgt"] = 0.85,
	},
})

table.insert(ThemeConfig.builtinPresets, {
	["name"] = "Cosmic Flowers [GIF]",
	["desc"] = "Midnight blue stars, luminous pink petals, and icy cyan highlights.",
	["data"] = {
		["V"] = 1,
		["M"] = "A",
		["Bg"] = "#111633>#06091c@90",
		["Top"] = "#10162d",
		["TopBtn"] = "#272a4c",
		["TopT"] = "#f3f2fc",
		["TopStrk"] = "#515b87",
		["Ctrl"] = "#f3dafa>#a595ce@90",
		["CtrlIc"] = "#19172f",
		["Pnl"] = "#131a35",
		["Div"] = "#343e68",
		["Strk"] = "#515b87",
		["Scr"] = "#999cd6",
		["Txt"] = "#edf0fb",
		["Tick"] = "#a6b7d9",
		["Menu"] = "#1a2345>#0b1027@90",
		["MenuHov"] = "#2c3559",
		["MenuSel"] = "#62518f",
		["Tip"] = "#0d142d",
		["TipT"] = "#edf0fb",
		["KfD"] = "#c3d0f2",
		["KfH"] = "#fff0fd",
		["KfS"] = "#f3b2ed",
		["KfAuto"] = "#b5cef5",
		["KfAli"] = "#bbabef",
		["KfAC"] = "#a8e0ee",
		["KfVec"] = "#e7b3e9",
		["KfFree"] = "#d8c3f3",
		["Loop"] = "#b8e7f2>#667fd1@90",
		["LoopOff"] = "#364566>#232c48@90",
		["Rec"] = "#edb3e6>#a663ae@90",
		["RecOff"] = "#513750>#30263f@90",
		["AddBtn"] = "#c6d7f5>#798fbf@90",
		["Slider"] = "#6476a8",
		["Ph"] = "#f4b8ed",
		["Trk"] = "#303e61",
		["Trkt"] = 0.2,
		["Sel"] = "#62518f",
		["Imgt"] = 0.7,
		["Gif"] = {
			{ ["id"] = "107203702468968", ["ms"] = 100 },
			{ ["id"] = "96231907856199", ["ms"] = 100 },
			{ ["id"] = "119301945436918", ["ms"] = 100 },
			{ ["id"] = "84476356001009", ["ms"] = 100 },
			{ ["id"] = "135587076620581", ["ms"] = 100 },
			{ ["id"] = "128919015375059", ["ms"] = 100 },
			{ ["id"] = "138941023710471", ["ms"] = 100 },
			{ ["id"] = "131857281510069", ["ms"] = 100 },
			{ ["id"] = "74656157373794", ["ms"] = 100 },
			{ ["id"] = "138866167158457", ["ms"] = 100 },
			{ ["id"] = "126619255045830", ["ms"] = 100 },
			{ ["id"] = "78886804469272", ["ms"] = 100 },
			{ ["id"] = "132065465480874", ["ms"] = 100 },
			{ ["id"] = "137287040910958", ["ms"] = 100 },
			{ ["id"] = "94446766202270", ["ms"] = 100 },
			{ ["id"] = "96737462198288", ["ms"] = 100 },
			{ ["id"] = "138261525677659", ["ms"] = 100 },
			{ ["id"] = "136401962658221", ["ms"] = 100 },
			{ ["id"] = "121952043706882", ["ms"] = 100 },
			{ ["id"] = "93202112710501", ["ms"] = 100 },
			{ ["id"] = "103248339724565", ["ms"] = 100 },
			{ ["id"] = "90664192071277", ["ms"] = 100 },
			{ ["id"] = "132861266761966", ["ms"] = 100 },
			{ ["id"] = "104177654467050", ["ms"] = 100 },
			{ ["id"] = "93027079673071", ["ms"] = 100 },
			{ ["id"] = "99776897758869", ["ms"] = 100 },
			{ ["id"] = "70504190842821", ["ms"] = 100 },
		},
	},
})

local previousNew = {
	name = "New Eclipse",
	desc = "Soft lavender, deep plum panels, and warm rose highlights.",
	data = {
		V = 1,
		M = "A",
		Bg = "#29243c>#151321@90",
		Top = "#201c30",
		TopBtn = "#393148",
		TopT = "#f2eafa",
		TopStrk = "#746080",
		Ctrl = "#dfcde9>#a88cbd@90",
		CtrlIc = "#2b2039",
		Pnl = "#221e31",
		Div = "#665477",
		Strk = "#746080",
		Scr = "#a992bf",
		Txt = "#ece5f3",
		Tick = "#b4a3c4",
		Menu = "#332b46>#201b30@90",
		MenuHov = "#483956",
		MenuSel = "#775b8f",
		Sel = "#775b8f",
		KfD = "#e6daef",
		KfH = "#ffffff",
		KfS = "#dfadc7",
		Ph = "#e9adc9",
		Trk = "#5b496d",
		Trkt = 0.22,
		Loop = "#d7badf>#85719f@90",
		Rec = "#e6aec7>#a36385@90",
		AddBtn = "#d3bddf>#947aab@90",
		LoopOff = "#473950",
		RecOff = "#47303f",
		Slider = "#77618e",
		Tip = "#292237",
		TipT = "#f0e8f7",
	},
}

local newPalette = table.clone(previousNew.data)
newPalette.Ctrl = "#d8cef0>#9788bd@90"
newPalette.MenuSel = "#6e5a98"
newPalette.Sel = newPalette.MenuSel
newPalette.KfS = "#c5b1ec"
newPalette.Ph = "#c7b3ef"
newPalette.Loop = "#d4b5f0>#7279b8@90"
newPalette.LoopOff = "#655276>#363b64@90"
newPalette.Rec = "#cab3e8>#84639f@90"
newPalette.RecOff = "#49365d"
newPalette.AddBtn = "#cec0ec>#8876af@90"
ThemeConfig.defaultTheme = newPalette
ThemeConfig.builtinPresets[1] = {
	name = "New Eclipse",
	desc = "Soft lavender and deep purple, with periwinkle accents.",
	data = newPalette,
}

function ThemeConfig.migratePreset(data)
	data = require("KoiImages").migrate(data)
	if data.OldEclipse == true then
		return data
	end

	for _, old in { legacyDefault, previousNew.data } do
		local same = true
		for key, value in old do
			if data[key] ~= value then
				same = false
				break
			end
		end

		if same then
			for key in data do
				if old[key] == nil then
					same = false
					break
				end
			end
		end

		if same then
			return table.clone(newPalette)
		end
	end

	return data
end

function ThemeConfig.isKoiFrames(frames)
	return require("KoiImages").isSequence(frames)
end

ThemeConfig.oldTheme = legacyDefault
local oldPreset = table.clone(legacyDefault)
oldPreset.OldEclipse = true
ThemeConfig.communityPresets = {
	{
		name = "AMOLED",
		desc = "Nicole's pure-black theme, with clear blue selections.",
		data = {
			TipT = "#f0e8f7",
			Trk = "#383838",
			MenuHov = "#2d2d2d",
			Ph = "#ffffff",
			Rec = "#ffffff",
			CtrlIc = "#ffffff",
			TopT = "#f2eafa",
			Sel = "#263c56",
			Top = "#000000",
			Ctrl = "#000000",
			Menu = "#000000",
			TopBtn = "#131313",
			TrackOn = "#ffffff",
			MenuSel = "#263c56",
			KfAC = "#e4e4e4",
			Tick = "#b8b8b8",
			M = "A",
			Pnl = "#101010",
			Bg = "#000000",
			KfD = "#cacaca",
			Txt = "#ece5f3",
			Tip = "#050505",
			Strk = "#404040",
			Div = "#404040",
			RecOff = "#292929",
			TopStrk = "#303030",
			KfH = "#ffffff",
			V = 1,
			KfS = "#77b7ff",
			Loop = "#eaeaea",
			Scr = "#ffffff",
			LoopOff = "#292929",
			AddBtn = "#eaeaea",
			KfAuto = "#80d6a3",
			TrackOff = "#7d7d7d",
			Slider = "#b2b2b2",
			KfAli = "#c59aff",
			KfVec = "#edc66c",
			KfFree = "#ee95c0",
		},
	},
	{ name = "Old Eclipse", desc = "Original Eclipse theme.", data = oldPreset },
}
return ThemeConfig
