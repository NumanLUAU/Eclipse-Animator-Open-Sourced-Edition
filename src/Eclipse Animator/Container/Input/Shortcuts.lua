--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Config = require("Bindings")
local Input = require("UserInputService")
local Http = game:GetService("HttpService")
local Shortcuts = {}
local groups = {
	Ctrl = { "LeftControl", "RightControl" },
	Shift = { "LeftShift", "RightShift" },
	Alt = { "LeftAlt", "RightAlt" },
	Meta = { "LeftMeta", "RightMeta", "LeftSuper", "RightSuper" },
}
local order = { "Ctrl", "Shift", "Alt", "Meta" }
local byId, values, listeners = {}, {}, {}
local writer
local initialized = false
local missingReads = 0
local setting = "EclipseAnimator_Keybinds_v1"

local function copy(value)
	return { Key = value.Key, Modifiers = table.clone(value.Modifiers or {}) }
end

for _, row in Config do
	byId[row.Action] = row
	values[row.Action] = copy(row)
end

local function normalize(value)
	if type(value) ~= "table" then
		return nil
	end

	if value.Key == false then
		return { Key = false, Modifiers = {} }
	end

	if type(value.Key) ~= "string" or type(value.Modifiers or {}) ~= "table" then
		return nil
	end

	local ok, key = pcall(function()
		return Enum.KeyCode[value.Key]
	end)
	if
		not ok
		or typeof(key) ~= "EnumItem"
		or key.EnumType ~= Enum.KeyCode
		or key == Enum.KeyCode.Unknown
	then
		return nil
	end

	for _, keys in groups do
		if table.find(keys, value.Key) then
			return nil
		end
	end

	local required = {}
	for _, name in value.Modifiers or {} do
		if not groups[name] then
			return nil
		end

		required[name] = true
	end

	local result = { Key = value.Key, Modifiers = {} }
	for _, name in order do
		if required[name] then
			table.insert(result.Modifiers, name)
		end
	end

	return result
end

local function signature(value)
	if not value.Key then
		return nil
	end

	return table.concat(value.Modifiers, "+") .. "/" .. value.Key
end

local function encodeBindings(candidate)
	local saved = table.clone(candidate)
	saved._Version = 10
	return Http:JSONEncode(saved)
end

local function notify(changed)
	for _, entry in table.clone(listeners) do
		if not changed or not entry.id or changed[entry.id] then
			local ok, err = pcall(entry.callback)
			if not ok then
				warn("Eclipse shortcut listener: " .. tostring(err))
			end
		end
	end
end

function Shortcuts.init(refs)
	if initialized then
		return
	end

	initialized = true
	writer = refs.SetSetting
	local ok, saved = pcall(refs.GetSetting, setting)
	if ok and type(saved) == "string" then
		ok, saved = pcall(Http.JSONDecode, Http, saved)
	end

	if ok and saved == nil and refs.CanRetry then
		missingReads += 1
		task.delay(missingReads <= 5 and 1 or 30, function()
			if not refs.CanRetry() then
				return
			end

			initialized = false
			Shortcuts.init(refs)
		end)
	end

	if not ok then
		task.delay(1, function()
			if refs.CanRetry and not refs.CanRetry() then
				return
			end

			initialized = false
			Shortcuts.init(refs)
		end)
		return
	end

	if
		saved ~= nil
		and (
			type(saved) ~= "table"
			or saved._Version ~= nil
				and (type(saved._Version) ~= "number" or saved._Version % 1 ~= 0 or saved._Version < 0 or saved._Version > 10)
		)
	then
		writer = function()
			error("Reopen Eclipse to reload saved shortcuts.")
		end

		warn("Eclipse shortcuts could not be read; saved data was retained.")
		return
	end

	if ok and type(saved) == "table" then
		for id, value in saved do
			if byId[id] and type(value) == "table" and (value.Key == "LeftSuper" or value.Key == "RightSuper") then
				saved[id] = { Key = false, Modifiers = {} }
			end
		end

		for id, value in saved do
			if byId[id] and not normalize(value) then
				writer = function()
					error("Reopen Eclipse to reload saved shortcuts.")
				end

				warn("Eclipse shortcuts contain an invalid binding; saved data was retained.")
				return
			end
		end

		for id, value in saved do
			local normalized = normalize(value)
			if byId[id] and normalized then
				values[id] = normalized
			end
		end

		local graph = values.ToggleGraphEditor
		if (tonumber(saved._Version) or 0) < 2 and graph.Key == "F3" and #graph.Modifiers == 0 then
			values.ToggleGraphEditor = { Key = false, Modifiers = {} }
		end
	end

	if not ok or type(saved) ~= "table" then
		saved = {}
	end

	if (tonumber(saved._Version) or 0) < 7 then
		local reset = values.ResetMotorPosition
		if reset.Key == "H" and #reset.Modifiers == 0 then
			local candidate = { Key = "I", Modifiers = {} }
			values.ResetMotorPosition = #Shortcuts.conflicts(
							"ResetMotorPosition",
							candidate
						)
						== 0
					and candidate
				or { Key = false, Modifiers = {} }
		end
	end

	local fit, jump = values.FitTimeline, values.JumpKeyframeLeft
	if
		fit
		and jump
		and fit.Key == "F"
		and #fit.Modifiers == 1
		and fit.Modifiers[1] == "Shift"
		and signature(fit) == signature(jump)
	then
		values.FitTimeline = { Key = "F", Modifiers = { "Ctrl", "Shift" } }
		if #Shortcuts.conflicts("FitTimeline", values.FitTimeline) > 0 then
			values.FitTimeline = { Key = false, Modifiers = {} }
		end
	end

	if (tonumber(saved._Version) or 0) < 4 then
		for _, row in { { "JumpKeyframeLeft", "F", "Four" }, { "JumpKeyframeRight", "G", "Six" } } do
			local value = values[row[1]]
			if value.Key == row[2] and #value.Modifiers == 1 and value.Modifiers[1] == "Shift" then
				local candidate = { Key = row[3], Modifiers = {} }
				if #Shortcuts.conflicts(row[1], candidate) == 0 then
					values[row[1]] = candidate
				end
			end
		end
	end

	if (tonumber(saved._Version) or 0) < 5 then
		for _, row in
			{
				{ "JumpKeyframeLeft", "Four", "F", "StepFrameLeft" },
				{ "JumpKeyframeRight", "Six", "G", "StepFrameRight" },
			}
		do
			local value = values[row[1]]
			if value.Key == row[2] and #value.Modifiers == 0 then
				local candidate = { Key = row[3], Modifiers = { "Shift" } }
				values[row[1]] = #Shortcuts.conflicts(row[1], candidate) == 0 and candidate
					or { Key = false, Modifiers = {} }
			end

			if saved[row[4]] == nil and #Shortcuts.conflicts(row[4], values[row[4]]) > 0 then
				values[row[4]] = { Key = false, Modifiers = {} }
			end
		end
	end

	if (tonumber(saved._Version) or 0) < 6 then
		local left, right = values.StepFrameLeft, values.StepFrameRight
		local oldLeft = saved.StepFrameLeft and left.Key == "Four" and #left.Modifiers == 0
		local oldRight = saved.StepFrameRight and right.Key == "Six" and #right.Modifiers == 0
		if oldLeft then
			values.StepFrameLeft = { Key = false, Modifiers = {} }
		end

		if oldRight then
			values.StepFrameRight = { Key = false, Modifiers = {} }
		end

		if oldRight then
			local nextBinding = { Key = "Seven", Modifiers = {} }
			values.StepFrameRight = #Shortcuts.conflicts("StepFrameRight", nextBinding) == 0
					and nextBinding
				or right
		end

		if oldLeft then
			local previousBinding = { Key = "Six", Modifiers = {} }
			values.StepFrameLeft = #Shortcuts.conflicts(
							"StepFrameLeft",
							previousBinding
						)
						== 0
					and previousBinding
				or left
		end
	end

	for _, id in { "ReverseKeys", "ReversePaste" } do
		if
			saved[id] == nil
			or id == "ReverseKeys"
				and (tonumber(saved._Version) or 0) < 3
				and values[id].Key == false
		then
			values[id] = { Key = false, Modifiers = {} }
			local candidates = id == "ReverseKeys"
					and {
						{ "R", { "Ctrl" } },
						{ "R", { "Ctrl", "Alt" } },
						{ "K", { "Ctrl" } },
						{ "K", { "Ctrl", "Alt" } },
					}
				or {
					{ "R", { "Ctrl", "Shift" } },
					{ "R", { "Ctrl", "Shift", "Alt" } },
					{ "K", { "Ctrl", "Shift" } },
					{ "K", { "Ctrl", "Shift", "Alt" } },
				}
			for _, candidate in candidates do
				local value = { Key = candidate[1], Modifiers = candidate[2] }
				if #Shortcuts.conflicts(id, value) == 0 then
					values[id] = value
					break
				end
			end
		end
	end

	if
		saved.StudioSelection == nil
		and #Shortcuts.conflicts("StudioSelection", values.StudioSelection) > 0
	then
		values.StudioSelection = { Key = false, Modifiers = {} }
	end

	if (saved._Version or 0) < 8 then
		local reset = values.ResetMotorPosition
		if
			reset.Key == "H"
			and (
				#reset.Modifiers == 1 and reset.Modifiers[1] == "Shift"
				or #reset.Modifiers == 0 and (saved._Version or 0) < 7
			)
		then
			local candidate = { Key = "I", Modifiers = {} }
			if #Shortcuts.conflicts("ResetMotorPosition", candidate) == 0 then
				values.ResetMotorPosition = candidate
			end
		end

		if saved.ToggleHUD == nil and #Shortcuts.conflicts("ToggleHUD", values.ToggleHUD) > 0 then
			values.ToggleHUD = { Key = false, Modifiers = {} }
		end
	end

	if
		saved.CutKeyframes == nil
		and #Shortcuts.conflicts("CutKeyframes", values.CutKeyframes) > 0
	then
		values.CutKeyframes = { Key = false, Modifiers = {} }
	end

	for _, row in
		{
			{ "ResetMotorPosition", "P", "K", "Z", "C" },
			{ "JumpToStart", "K", "P", "Z", "C" },
		}
	do
		local id, value = row[1], values[row[1]]
		if
			saved[id] == nil
			or (saved._Version or 0) < 9
				and (value.Key == "I" or value.Key == "O")
				and #value.Modifiers == 0
		then
			values[id] = { Key = false, Modifiers = {} }
			local keys = {
				row[2],
				row[3],
				row[4],
				row[5],
				"Home",
				"F4",
				"F5",
				"F6",
				"F7",
				"F8",
				"F9",
				"F10",
				"F11",
				"F12",
			}
			for _, modifiers in { {}, { "Shift" }, { "Ctrl", "Alt" } } do
				for _, key in keys do
					local candidate = { Key = key, Modifiers = table.clone(modifiers) }
					if #Shortcuts.conflicts(id, candidate) == 0 then
						values[id] = candidate
						break
					end
				end

				if values[id].Key then
					break
				end
			end
		end
	end

	if (saved._Version or 0) < 10 then
		local paste, record = values.PasteKeyframes, values.RecordAllTracks
		if
			paste.Key == "V"
			and #paste.Modifiers == 1
			and paste.Modifiers[1] == "Shift"
			and signature(paste) == signature(record)
		then
			values.PasteKeyframes = { Key = false, Modifiers = {} }
		end
	end

	notify()
end

function Shortcuts.list()
	return Config
end

function Shortcuts.get(id)
	return values[id] and copy(values[id])
end

function Shortcuts.label(id)
	local row = byId[id]
	return row and row.Label or id
end

function Shortcuts.format(id)
	return Shortcuts.describe(values[id])
end

function Shortcuts.describe(value)
	if type(value) ~= "table" or not value.Key then
		return "Unbound"
	end

	local digits = {
		Zero = "0",
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
		Nine = "9",
	}
	local parts = table.clone(value.Modifiers or {})
	table.insert(parts, digits[value.Key] or value.Key)
	return table.concat(parts, " + ")
end

local shared = {
	OpenKeyframeMenu = true,
	Undo = true,
	UndoAlternate = true,
	Redo = true,
	RedoAlternate = true,
	RedoShift = true,
	Copy = true,
	Paste = true,
	TogglePlayback = true,
	ToggleGraphEditor = true,
}

local function overlap(id, other)
	if
		id == "ResetMotorPosition" and other == "ResetMotorOrientation"
		or id == "ResetMotorOrientation" and other == "ResetMotorPosition"
	then
		return false
	end

	local a, b = byId[id].Context, byId[other].Context
	if a == b or a == "Global" or b == "Global" or a == "Modal" or b == "Modal" then
		return true
	end

	return (shared[id] and b == "Graph") or (shared[other] and a == "Graph") or false
end

function Shortcuts.conflicts(id, value)
	local normalized = normalize(value)
	local found = {}
	if not byId[id] or not normalized or not normalized.Key then
		return found
	end

	for other, row in byId do
		if
			other ~= id
			and overlap(id, other)
			and signature(values[other]) == signature(normalized)
		then
			table.insert(found, other)
		end
	end

	table.sort(found)
	return found
end

function Shortcuts.setMany(changes, replace)
	local candidate = {}
	for id, value in values do
		candidate[id] = copy(value)
	end

	for id, value in changes do
		if not byId[id] then
			return false, "Unknown action"
		end

		local normalized = normalize(value)
		if not normalized then
			return false, "Choose a keyboard key with optional modifiers."
		end

		candidate[id] = normalized
	end

	for id in changes do
		local sig = signature(candidate[id])
		for other in byId do
			if
				sig
				and other ~= id
				and overlap(id, other)
				and signature(candidate[other]) == sig
			then
				if changes[other] or not replace then
					return false, "Used by " .. Shortcuts.label(other)
				end

				candidate[other] = { Key = false, Modifiers = {} }
			end
		end
	end

	local changed = {}
	for id, value in candidate do
		if signature(value) ~= signature(values[id]) then
			changed[id] = true
		end
	end

	if not next(changed) then
		return true
	end

	if writer then
		local ok = pcall(writer, setting, encodeBindings(candidate), encodeBindings(values))
		if not ok then
			return false, "Could not save keybinds. Try again."
		end
	end

	values = candidate
	notify(changed)
	return true
end

function Shortcuts.set(id, value, replace)
	if not byId[id] then
		return false, "Unknown action"
	end

	local normalized = normalize(value)
	if not normalized then
		return false, "Choose a keyboard key with optional modifiers."
	end

	local conflicts = Shortcuts.conflicts(id, normalized)
	if #conflicts > 0 and not replace then
		return false, "Used by " .. Shortcuts.label(conflicts[1]), conflicts
	end

	local candidate = {}
	for key, item in values do
		candidate[key] = copy(item)
	end

	candidate[id] = normalized
	for _, other in conflicts do
		candidate[other] = { Key = false, Modifiers = {} }
	end

	local changed = {}
	for key, item in candidate do
		if signature(item) ~= signature(values[key]) then
			changed[key] = true
		end
	end

	if not next(changed) then
		return true
	end

	if writer then
		local ok = pcall(writer, setting, encodeBindings(candidate), encodeBindings(values))
		if not ok then
			return false, "Could not save keybinds. Try again."
		end
	end

	values = candidate
	notify(changed)
	return true
end

function Shortcuts.reset(id, replace)
	return Shortcuts.set(id, byId[id], replace)
end

function Shortcuts.resetAll()
	local candidate = {}
	for id, row in byId do
		candidate[id] = copy(row)
	end

	if writer then
		local ok = pcall(writer, setting, encodeBindings(candidate), encodeBindings(values))
		if not ok then
			return false
		end
	end

	values = candidate
	notify()
	return true
end

function Shortcuts.subscribe(callback, id)
	local entry = { callback = callback, id = id }
	table.insert(listeners, entry)
	return function()
		local i = table.find(listeners, entry)
		if i then
			table.remove(listeners, i)
		end
	end
end

function Shortcuts.aliasKey(id, key)
	if id == "DeleteKeys" and key == "X" then
		return "Delete"
	end

	if id ~= "StepFrameLeft" and id ~= "StepFrameRight" then
		return nil
	end

	local name = key == "Four" and "KeypadFour"
		or key == "Six" and "KeypadSix"
		or key == "Seven" and "KeypadSeven"
		or nil
	if not name then
		return nil
	end

	local candidate = { Key = name, Modifiers = values[id].Modifiers }
	if #Shortcuts.conflicts(id, candidate) > 0 then
		return nil
	end

	return name
end

local function groupHeld(keys, heldKeys)
	for _, name in keys do
		const key = Enum.KeyCode[name]
		if Input:IsKeyDown(key) or heldKeys and heldKeys[key] then
			return true
		end
	end

	return false
end

function Shortcuts.matches(id, input, heldKeys)
	if Input.isCapturedKey and Input.isCapturedKey(input.KeyCode) then
		return false
	end

	if
		Input.isCapturingKeys and Input.isCapturingKeys()
		or Input.isCapturedInput and Input.isCapturedInput(input)
	then
		return false
	end

	local value = values[id]
	if
		not value
		or not value.Key
		or input.UserInputType ~= Enum.UserInputType.Keyboard
		or (
			input.KeyCode.Name ~= value.Key
			and input.KeyCode.Name ~= Shortcuts.aliasKey(id, value.Key)
		)
	then
		return false
	end

	local ctrl, meta = false, false
	for name, keys in groups do
		local held = groupHeld(keys, heldKeys)
		local ok, down = pcall(function()
			return input:IsModifierKeyDown(Enum.ModifierKey[name])
		end)
		if ok then
			held = down
		end

		if name == "Ctrl" then
			ctrl = held
		elseif name == "Meta" then
			meta = held
		elseif held ~= (table.find(value.Modifiers, name) ~= nil) then
			return false
		end
	end

	const wantsCtrl = table.find(value.Modifiers, "Ctrl") ~= nil
	const wantsMeta = table.find(value.Modifiers, "Meta") ~= nil
	if wantsCtrl and not wantsMeta and meta then
		ctrl, meta = true, false
	end

	return ctrl == wantsCtrl and meta == wantsMeta
end

function Shortcuts.isDown(id)
	local value = values[id]
	if not value or not value.Key then
		return false
	end

	return Input:IsKeyDown(Enum.KeyCode[value.Key])
		and Shortcuts.matches(
			id,
			{ KeyCode = Enum.KeyCode[value.Key], UserInputType = Enum.UserInputType.Keyboard }
		)
end

function Shortcuts.isKey(id, key)
	local value = values[id]
	return value and value.Key == key.Name
end

function Shortcuts.chord(input)
	local value = { Key = input.KeyCode.Name, Modifiers = {} }
	for name, keys in groups do
		for _, key in keys do
			if input.KeyCode.Name == key then
				return nil
			end
		end
	end

	for _, name in order do
		local keys = groups[name]
		local ok, down = pcall(function()
			return input:IsModifierKeyDown(Enum.ModifierKey[name])
		end)
		if ok and down or groupHeld(keys) then
			table.insert(value.Modifiers, name)
		end
	end

	return normalize(value)
end

local legacyBindings = {
	ToggleGizmoMode = { Key = "R", Modifiers = {} },
	ToggleAxisSpace = { Key = "Y", Modifiers = {} },
	RecordKeyframe = { Key = "Equals", Modifiers = {} },
	ResetMotorPosition = { Key = "G", Modifiers = {} },
	FitTimeline = { Key = "F", Modifiers = { "Shift" } },
	GroupKeyframes = { Key = "G", Modifiers = { "Ctrl" } },
	UngroupAllKeyframes = { Key = "U", Modifiers = { "Ctrl", "Shift" } },
	Undo = { Key = "Z", Modifiers = { "Ctrl" } },
	UndoAlternate = { Key = "Z", Modifiers = { "Shift" } },
	Redo = { Key = "Z", Modifiers = { "Ctrl", "Shift" } },
	RedoAlternate = { Key = "Y", Modifiers = { "Ctrl" } },
	RedoShift = { Key = "Y", Modifiers = { "Shift" } },
	CutKeyframes = { Key = "X", Modifiers = { "Ctrl" } },
	Copy = { Key = "C", Modifiers = { "Ctrl" } },
	CopyKeyframes = { Key = "C", Modifiers = { "Shift" } },
	Paste = { Key = "V", Modifiers = { "Ctrl" } },
	PasteKeyframes = { Key = "V", Modifiers = { "Shift" } },
	PasteFlipped = { Key = "V", Modifiers = { "Ctrl", "Shift" } },
	ApplyOnionSkin = { Key = "N", Modifiers = {} },
	ToggleOnionSkin = { Key = "B", Modifiers = {} },
	ClearOnionSkin = { Key = "B", Modifiers = { "Alt" } },
	FocusSelection = { Key = "F", Modifiers = {} },
	JumpKeyframeLeft = { Key = "J", Modifiers = {} },
	JumpKeyframeRight = { Key = "K", Modifiers = {} },
	SplitKeyframes = { Key = "M", Modifiers = {} },
	SplitStride = { Key = "M", Modifiers = { "Shift" } },
	UngroupKeyframes = { Key = "U", Modifiers = { "Ctrl" } },
	AnimationSettings = { Key = "Eight", Modifiers = {} },
	OpenKeyframeMenu = { Key = "Seven", Modifiers = {} },
	AddObject = { Key = "Nine", Modifiers = {} },
	ImportToRig = { Key = "I", Modifiers = { "Shift" } },
	FlipPose = { Key = "R", Modifiers = { "Ctrl" } },
	HideSelectedBones = { Key = "B", Modifiers = { "Ctrl" } },
	FillFrames = { Key = "K", Modifiers = { "Shift" } },
	StretchFrames = { Key = "Three", Modifiers = {} },
	CaptureOnionSkin = { Key = "B", Modifiers = { "Shift" } },
	RotateCameraGrid = { Key = "C", Modifiers = {} },
	JumpToStart = { Key = "One", Modifiers = {} },
	StepFrameLeft = { Key = "Four", Modifiers = {} },
	StepFrameRight = { Key = "Six", Modifiers = {} },
	ExportAnimation = { Key = "Five", Modifiers = {} },
	SaveProject = { Key = "Zero", Modifiers = {} },
	SaveAndCloseProject = { Key = "Slash", Modifiers = {} },
	TogglePresentation = { Key = "H", Modifiers = { "Ctrl" } },
	SelectAll = { Key = "F", Modifiers = { "Alt" } },
	TogglePlayback = { Key = "Space", Modifiers = {} },
}

function Shortcuts.applyLegacy()
    local changes = {}
    for id, chord in legacyBindings do
        if byId[id] then changes[id] = copy(chord) end
    end
    return Shortcuts.setMany(changes, true)
end

return Shortcuts
