--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Dropdowns = {
	MainSelection = {
		width = 145,
		main = true,
		rows = {
			{
				id = "HandleType",
				text = "Handle Type",
				icon = "rbxassetid://85012573369942",
				iconSize = { 0.12, 0.75 },
				submenu = true,
			},
			{
				id = "InterpolationMode",
				text = "Interpolation Mode",
				icon = "rbxassetid://98125898235677",
				iconSize = { 0.1, 0.625 },
				submenu = true,
			},
			{
				id = "EasingMode",
				text = "Easing Mode",
				icon = "rbxassetid://81917993465495",
				iconSize = { 0.094, 0.583 },
				submenu = true,
			},
			"divider",
			{
				id = "Values",
				text = "Values",
				icon = "rbxassetid://88867952645347",
				iconSize = { 0.12, 0.75 },
				submenu = true,
			},
			"divider",
			{
				id = "StretchFrames",
				text = "Stretch Frames",
				action = "StretchFrames",
				icon = "rbxassetid://117361012423316",
				iconSize = { 0.1, 0.625 },
			},
			{
				id = "FillFrames",
				text = "Fill Frames",
				action = "FillFrames",
				icon = "rbxassetid://117089541882269",
				iconSize = { 0.1, 0.625 },
			},
			{
				id = "Copy",
				text = "Copy",
				icon = "rbxassetid://106411377490407",
				iconSize = { 0.1, 0.625 },
				keybind = "Ctrl+C",
				action = "Copy",
			},
			{
				id = "Paste",
				text = "Paste",
				icon = "rbxassetid://135501398209579",
				iconSize = { 0.1, 0.625 },
				keybind = "Ctrl+V",
				action = "Paste",
			},
			{
				id = "PasteFlipped",
				text = "Paste Flipped",
				icon = "rbxassetid://128321208965826",
				iconSize = { 0.12, 0.75 },
				keybind = "Ctrl+Shift+V",
				action = "PasteFlipped",
			},
			"divider",
			{
				id = "ToggleKey",
				text = "Disable Keyframe",
				icon = "rbxassetid://91467782437984",
				iconSize = { 0.12, 0.75 },
				action = "ToggleKey",
			},
			{
				id = "DeleteKey",
				text = "Delete Keyframe",
				icon = "rbxassetid://71537789998060",
				iconSize = { 0.1, 0.625 },
				keybind = "X",
				action = "DeleteKey",
			},
		},
	},

	SecondarySelection = {
		width = 145,
		primary = true,
		rows = {
			{
				id = "Paste",
				text = "Paste",
				icon = "rbxassetid://135501398209579",
				iconSize = { 0.1, 0.625 },
				keybind = "Ctrl+V",
				action = "Paste",
			},
			{
				id = "PasteFlipped",
				text = "Paste Flipped",
				icon = "rbxassetid://128321208965826",
				iconSize = { 0.12, 0.75 },
				keybind = "Ctrl+Shift+V",
				action = "PasteFlipped",
			},
			{
				id = "InsertKey",
				text = "Insert Keyframe",
				icon = "rbxassetid://113995793536843",
				iconSize = { 0.1, 0.625 },
				keybind = "V",
				action = "InsertKey",
			},
		},
	},

	HandleType = {
		width = 144,
		offset = { x = 120.8, y = 20.28 },
		rows = {
			{
				id = "Free",
				text = "Free",
				icon = "rbxassetid://96817013607764",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "HandleType", value = "Free" },
			},
			{
				id = "Aligned",
				text = "Aligned",
				icon = "rbxassetid://96817013607764",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "HandleType", value = "Aligned" },
			},
			{
				id = "Vector",
				text = "Vector",
				icon = "rbxassetid://96817013607764",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "HandleType", value = "Vector" },
			},
			{
				id = "Automatic",
				text = "Automatic",
				icon = "rbxassetid://96817013607764",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "HandleType", value = "Automatic" },
			},
			{
				id = "AutoClamped",
				text = "Auto Clamped",
				icon = "rbxassetid://96817013607764",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "HandleType", value = "AutoClamped" },
			},
		},
	},

	EasingMode = {
		width = 143,
		offset = { x = 122.5, y = 60.88 },
		rows = {
			{
				id = "AutomaticEasing",
				text = "Automatic Easing",
				icon = "rbxassetid://112546020840718",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "EasingDirection", value = "Automatic" },
			},
			{
				id = "EaseIn",
				text = "Ease In",
				icon = "rbxassetid://82490885130603",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "EasingDirection", value = "In" },
			},
			{
				id = "EaseOut",
				text = "Ease Out",
				icon = "rbxassetid://82490885130603",
				iconRotation = 180,
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "EasingDirection", value = "Out" },
			},
			{
				id = "EaseInandOut",
				text = "Ease In and Out",
				icon = "rbxassetid://112546020840718",
				iconSize = { 0.12, 0.75 },
				checkable = true,
				apply = { field = "EasingDirection", value = "InOut" },
			},
		},
	},
}

Dropdowns.MenuFile = {
	width = 205,
	compact = true,
	menubar = "FILE",
	rows = {
		{
			id = "SaveProject",
			text = "Save",
			keybind = "Ctrl+S",
			icon = "rbxassetid://137968069700447",
			iconSize = { 0.12, 0.8 },
			compactIconSize = 20,
		},
		{
			id = "SaveProjectAs",
			text = "Save As...",
			icon = "rbxassetid://88784866386411",
			fallbackVectorIcon = "SaveAs",
			iconSize = { 0.12, 0.8 },
			compactIconSize = 20,
		},
		{
			id = "SaveAndCloseProject",
			text = "Save and Close",
			icon = "rbxassetid://95482577284554",
			iconSize = { 0.12, 0.8 },
			compactIconSize = 20,
		},
		{ id = "Recovery", text = "Recovery...", icon = "rbxassetid://93773231389948" },
		"divider",
		{ id = "ImportToRig", text = "Import to Rig", icon = "rbxassetid://71933542963635" },
		{ id = "R15ToR6", text = "R15 to R6", icon = "rbxassetid://71933542963635" },
		{ id = "ExportResults", text = "Export Results", icon = "rbxassetid://136636358423324" },
		{ id = "ModuleExporter", text = "Module Exporter", icon = "rbxassetid://136636358423324" },
		"divider",
		{
			id = "FitTimeline",
			text = "Fit Timeline",
			keybind = "Ctrl+Shift+F",
			icon = "rbxassetid://96798529843793",
		},
		{
			id = "AnimationSettings",
			text = "Animation Settings",
			icon = "rbxassetid://96798529843793",
		},
		"divider",
		{ id = "Hide", text = "Hide", keybind = "Ctrl+H", icon = "rbxassetid://78750090127892" },
	},
}

Dropdowns.MenuEffects = {
	width = 165,
	menubar = "EFFECTS",
	rows = {
		{
			id = "Subtitles",
			text = "Subtitles",
			icon = "rbxassetid://90407998983360",
			iconSize = {
				0.16,
				1,
			},
		},
		{
			id = "AddVignette",
			text = "Vignette",
			icon = "rbxassetid://130151592782489",
			iconSize = { 0.16, 0.95 },
		},
		{
			id = "AddLetterbox",
			text = "Letterbox",
			icon = "rbxassetid://137970514506278",
			iconSize = { 0.16, 0.95 },
		},
		{
			id = "AddImpactFrames",
			text = "Impact Frames",
			icon = "rbxassetid://129492615507159",
			iconSize = { 0.16, 0.95 },
		},
		{
			id = "AddCameraShake",
			text = "Camera Shake",
			icon = "rbxassetid://77861519861632",
			iconSize = { 0.16, 0.95 },
		},
		{
			id = "AddScreenCover",
			text = "Screen Cover",
			icon = "rbxassetid://125326695431407",
			iconSize = { 0.16, 0.95 },
		},
	},
}

Dropdowns.MenuItem = {
	width = 145,
	menubar = "ITEM",
	rows = {
		{
			id = "DeleteItem",
			text = "Delete Item",
			icon = "rbxassetid://132952049528593",
			iconSize = { 0.13, 0.85 },
			compactIconSize = 16,
		},
		{
			id = "AddFolder",
			text = "Add Folder",
			icon = "rbxassetid://120810204290579",
			iconSize = { 0.1, 0.8 },
		},
		{
			id = "AddCamera",
			text = "Add Camera",
			icon = "rbxassetid://132110507088694",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "AddEffects",
			text = "Add Effects",
			submenu = true,
			icon = "rbxassetid://127108652145286",
			iconSize = { 0.16, 0.95 },
			compactIconSize = 20,
		},
	},
}

Dropdowns.MenuEdit = {
	width = 172,
	compact = true,
	menubar = "EDIT",
	rows = {
		{
			id = "Undo",
			text = "Undo",
			keybind = "Ctrl+Z",
			icon = "rbxassetid://128321208965826",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "Redo",
			text = "Redo",
			keybind = "Ctrl+Y",
			icon = "rbxassetid://109512495328902",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "CopyKeys",
			text = "Copy Keys",
			keybind = "Ctrl+C",
			icon = "rbxassetid://106411377490407",
			iconSize = { 0.1, 0.625 },
		},
		"divider",
		{
			id = "PasteKeys",
			text = "Paste Keys",
			keybind = "Ctrl+V",
			icon = "rbxassetid://135501398209579",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "PasteFlipped",
			text = "Paste Flipped",
			keybind = "Ctrl+Shift+V",
			icon = "rbxassetid://128321208965826",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "BakeAnimation",
			text = "Bake Animation",
			icon = "rbxassetid://117089541882269",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "StretchFrames",
			text = "Stretch Frames",
			icon = "rbxassetid://117361012423316",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "FillFrames",
			text = "Fill Frames",
			icon = "rbxassetid://117089541882269",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "ReverseKeys",
			text = "Reverse Selected",
			keybind = "Ctrl+R",
			icon = "rbxassetid://134768330307517",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "ReversePaste",
			text = "Reverse Paste",
			keybind = "Ctrl+Shift+R",
			icon = "rbxassetid://140621653252675",
			iconSize = { 0.1, 0.625 },
		},
		"divider",
		{
			id = "GroupKeyframes",
			text = "Group",
			keybind = "Ctrl+G",
			icon = "rbxassetid://140449433099996",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "UngroupKeyframes",
			text = "Ungroup",
			keybind = "Ctrl+U",
			icon = "rbxassetid://84848582175830",
			iconSize = { 0.1, 0.625 },
		},
		{
			id = "UngroupAllKeyframes",
			text = "Ungroup All",
			keybind = "Ctrl+Shift+U",
			icon = "rbxassetid://132719312975604",
			iconSize = { 0.1, 0.625 },
		},
		"divider",
		{
			id = "SelectAll",
			text = "Select All",
			keybind = "Ctrl+A",
			icon = "rbxassetid://88867952645347",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "DeselectAll",
			text = "Deselect All",
			icon = "rbxassetid://71537789998060",
			iconSize = { 0.1, 0.625 },
		},
	},
}

Dropdowns.MenuRig = {
	width = 168,
	menubar = "RIG",
	rows = {
		{
			id = "RigParts",
			text = "Parts & Accessories",
			icon = "rbxassetid://101898481170126",
			iconSize = { 0.12, 0.8 },
		},
		{
			id = "BoneCollection",
			text = "Bone Collection",
			icon = "rbxassetid://108243501790371",
			iconSize = { 0.7, 0.7 },
			iconColor = Color3.new(1, 1, 1),
			compactIconSize = 18,
			iconStroke = 2,
		},
		{
			id = "BoneControls",
			text = "Bone Controls",
			icon = "rbxassetid://71105836370568",
			iconSize = { 0.7, 0.7 },
			iconColor = Color3.new(1, 1, 1),
			compactIconSize = 18,
			iconStroke = 2,
		},
		{ id = "BoneSettings", text = "Bone Settings", icon = "rbxassetid://136620194796840" },
		{
			id = "EditPivot",
			text = "Edit Pivot",
			icon = "rbxassetid://126791954484229",
			iconSize = { 0.12, 0.8 },
			compactIconSize = 20,
		},
		{
			id = "AutoIK",
			text = "Auto IK (Custom)",
			icon = "rbxassetid://75402336829835",
			fallbackVectorIcon = "AutoIK",
			iconSize = { 0.8, 0.8 },
		},
		{
			id = "SmartBone",
			text = "Bone Dynamics",
			icon = "rbxassetid://114773386733656",
			fallbackVectorIcon = "BoneDynamics",
			iconSize = { 0.8, 0.8 },
		},
		{
			id = "Physics",
			text = "Physics",
			icon = "rbxassetid://82010316963296",
			iconSize = { 0.12, 0.8 },
		},
		{
			id = "MasterControl",
			text = "Master Control",
			icon = "rbxassetid://80181670424755",
			iconSize = { 0.12, 0.8 },
		},
		{
			id = "AddArmature",
			text = "Add Armature",
			icon = "rbxassetid://116985864465063",
			iconSize = { 0.12, 0.8 },
		},
		{
			id = "RemoveArmature",
			text = "Remove Armature",
			icon = "rbxassetid://133764785545277",
			iconSize = { 0.12, 0.8 },
		},
		{
			id = "ArmatureControls",
			text = "Armature Controls",
			icon = "rbxassetid://119513105993521",
			iconSize = { 0.12, 0.8 },
		},
		"divider",
		{
			id = "ClearTransform",
			text = "Clear Transform",
			vectorIcon = "ClearTransform",
			iconSize = { 0.12, 0.8 },
		},
		{
			id = "AnimationCleanup",
			text = "Animation Cleanup",
			icon = "rbxassetid://132257477539936",
			iconSize = { 0.12, 0.8 },
		},
	},
}

Dropdowns.MenuView = {
	width = 205,
	menubar = "VIEW",
	rows = {
		{
			id = "FullCamera",
			text = "Camera View",
			keybind = "Ctrl+B",
			checkable = true,
			leftCheck = true,
			icon = "rbxassetid://106054188911407",
			iconSize = { 0.16, 1 },
		},
		{
			id = "Grid",
			text = "Grid",
			keybind = "L",
			checkable = true,
			leftCheck = true,
			icon = "rbxassetid://137816284187553",
			iconSize = { 0.16, 1 },
		},
		{
			id = "GridSettings",
			text = "Grid Settings",
			icon = "rbxassetid://76704076101809",
			iconColor = Color3.new(1, 1, 1),
		},
		{ id = "GreenScreen", text = "Green Screen", checkable = true, leftCheck = true, icon = "rbxassetid://116082217161585", iconSize = { 0.12, 0.75 }, iconColor = Color3.new(1, 1, 1) },
		{
			id = "EclipseVideo",
			text = "Eclipse Video",
			icon = "rbxassetid://77526238875485",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "ImagePreviewer",
			text = "Image Previewer",
			icon = require("Chrome").IMAGE_ICON,
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "AnimationLayers",
			text = "Animation Layers",
			icon = "rbxassetid://98169208749035",
			iconSize = { 0.16, 1 },
			compactIconSize = 24,
		},
		{
			id = "PoseSliders",
			text = "Pose Sliders",
			icon = "rbxassetid://73239604571560",

			iconSize = { 0.16, 1 },
		},
		{
			id = "DynamicParenter",
			text = "Dynamic Parenter",
			icon = "rbxassetid://103070248282065",
			iconSize = { 0.16, 1 },
			compactIconSize = 16,
		},
		{
			id = "MotionPaths",
			text = "Motion Paths",
			icon = "rbxassetid://128295275289720",
			fallbackVectorIcon = "MotionPaths",
			iconSize = { 0.8, 0.8 },
		},
		"divider",
		{
			id = "ToggleOnionSkin",
			text = "Toggle Onion Skin",
			keybind = "B",
			icon = "rbxassetid://70800332034072",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "CaptureOnionSkin",
			text = "Capture Onion Skin",
			keybind = "Shift+B",
			icon = "rbxassetid://85316371203399",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "ApplyOnionSkin",
			text = "Apply Onion Skin",
			keybind = "N",
			icon = "rbxassetid://97564997029052",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "ClearOnionSkin",
			text = "Clear Onion Skin",
			keybind = "Shift+N",
			icon = "rbxassetid://74139340263378",
			iconSize = { 0.12, 0.75 },
		},
	},
}

Dropdowns.MenuSettings = {
	width = 145,
	menubar = "SETTINGS",
	rows = {
		{
			id = "Preferences",
			text = "Preferences",
			icon = "rbxassetid://81917993465495",
			iconSize = { 0.094, 0.583 },
		},
		"divider",
		{
			id = "Keybinds",
			text = "Keybinds",
			icon = "rbxassetid://88867952645347",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "DefaultEasing",
			text = "Default Easing",
			icon = "rbxassetid://82490885130603",
			iconSize = { 0.12, 0.75 },
		},
		"divider",
		{
			id = "Customization",
			text = "Customization",
			icon = "rbxassetid://101982488432553",
			iconSize = { 0.12, 0.75 },
		},
		{
			id = "AboutEclipse",
			text = "About Eclipse",
			icon = "rbxassetid://109512495328902",
			iconSize = { 0.12, 0.75 },
		},
	},
}

for _, config in pairs(Dropdowns) do
	if typeof(config) == "table" and config.rows then
		config.rowsById = {}
		for _, row in ipairs(config.rows) do
			if typeof(row) == "table" and row.id then
				config.rowsById[row.id] = row
			end
		end
	end
end

Dropdowns._designOffsets = {
	InterpolationMode = { x = -157.53, y = 1.19 },
}

return Dropdowns
