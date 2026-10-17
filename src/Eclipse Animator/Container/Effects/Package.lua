--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Codec = require("Codec")
local Sources = require("Sources")
local Bake = require("Bake")
local SubtitleData = require("SubtitleData")
local Theme = require("Theme")
local Package = {}
local Editor = game:GetService("ScriptEditorService")
local HEADER = "--// cracked by numan | Eclipse Animator"
local RUNTIME_NAME = "EclipseCutsceneRuntime"
local RUNTIME_ENTRY = "Runtime/Cutscene"
local runtimeVersion

local function module(parent, name, source, class)
	if not source:match("^%-%-") then
		source = HEADER .. "\n\n" .. source
	end

	local object = Instance.new(class or "ModuleScript")
	object.Name = name
	local ok, err = pcall(function()
		Editor:UpdateSourceAsync(object, function()
			return source
		end)
	end)
	if not ok then
		object:Destroy()
		error(err)
	end

	assert(object.Source == source, "Could not write export source " .. name)
	object.Parent = parent
	return object
end

local function unique(parent, name)
	name = tostring(name):gsub("[^%w_ %-]", "_"):sub(1, 72)
	if name == "" then
		name = "Item"
	end

	local result = name
	local index = 2
	while parent:FindFirstChild(result) do
		result = name .. "_" .. index
		index += 1
	end

	return result
end

local keywords = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
	["const"] = true,
}

local function field(key)
	if type(key) == "string" and key:match("^[%a_][%w_]*$") and not keywords[key] then
		return key
	end

	return "[" .. Codec.encode(key) .. "]"
end

local function scalar(value)
	if type(value) == "number" then
		for precision = 6, 17 do
			local text = string.format("%." .. precision .. "g", value)
			if tonumber(text) == value then
				return text
			end
		end
	elseif typeof(value) == "Color3" then
		local r, g, b = value.R * 255, value.G * 255, value.B * 255
		if
			math.abs(r - math.round(r)) < 1e-3
			and math.abs(g - math.round(g)) < 1e-3
			and math.abs(b - math.round(b)) < 1e-3
		then
			return string.format(
				"Color3.fromRGB(%d, %d, %d)",
				math.round(r),
				math.round(g),
				math.round(b)
			)
		end
	end

	return Codec.encode(value)
end

local function pretty(value, depth)
	if type(value) ~= "table" then
		return scalar(value)
	end

	depth = depth or 0
	local keys = {}
	local flat = true
	for key, item in value do
		table.insert(keys, key)
		if type(item) == "table" then
			flat = false
		end
	end

	if #keys == 0 then
		return "{}"
	end

	local array = #value == #keys
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
			return a < b
		end

		return Codec.encode(a) < Codec.encode(b)
	end)
	if flat and (array or #keys <= 4) then
		local parts = {}
		for _, key in keys do
			table.insert(
				parts,
				array and scalar(value[key]) or field(key) .. " = " .. scalar(value[key])
			)
		end

		local line = "{ " .. table.concat(parts, ", ") .. " }"
		if #line <= 100 then
			return line
		end
	end

	local indent = string.rep("\t", depth + 1)
	local rows = {}
	for _, key in keys do
		local item = pretty(value[key], depth + 1)
		table.insert(rows, indent .. (array and item or field(key) .. " = " .. item) .. ",")
	end

	return "{\n" .. table.concat(rows, "\n") .. "\n" .. string.rep("\t", depth) .. "}"
end

local function indented(source, depth)
	source = source:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%s+$", "")
	if source == "" or source:find("%[=*%[") then
		return source
	end

	local indent = string.rep("\t", depth)
	return indent .. source:gsub("\n", "\n" .. indent):gsub("\n" .. indent .. "\n", "\n\n")
end

local function storeData(folder, value, label)
	label = label or "Layout"

	local function write(source, final)
		local name = unique(folder, final and label or label .. "_Part")
		module(folder, name, source)
		return name
	end

	local literal = pretty(value)
	if #literal <= 80000 then
		return write("return " .. literal, true)
	end

	assert(type(value) == "table", "An individual export value is too large")
	local parts, rows, size = {}, {}, 0

	local function flush()
		if #rows > 0 then
			table.insert(parts, write("return {\n\t" .. table.concat(rows, ",\n\t") .. ",\n}\n"))
			rows = {}
			size = 0
		end
	end

	for key, entry in value do
		local encoded = Codec.encode(entry, nil, 1)
		if #encoded > 20000 and type(entry) == "table" then
			encoded = "require("
				.. string.format(
					"%q",
					"./" .. storeData(folder, entry, label .. "_" .. tostring(key))
				)
				.. ")"
		end

		local row = "[" .. Codec.encode(key) .. "] = " .. encoded
		if size + #row > 80000 then
			flush()
		end

		table.insert(rows, row)
		size += #row
	end

	flush()
	if #parts == 1 then
		return parts[1]
	end

	return write(
		"local value = {}\nlocal parts = "
			.. Codec.encode(parts)
			.. "\n\nfor _, name in parts do\n\tlocal chunk = require(`./{name}`)\n\n\tfor key, item in chunk do\n\t\tvalue[key] = item\n\tend\nend\n\nreturn value\n",
		true
	)
end

local function scan(line, long)
	local i, n = 1, #line
	while i <= n do
		if long then
			local s, e = line:find("]" .. string.rep("=", long) .. "]", i, true)
			if not s then
				return long
			end

			long = nil
			i = e + 1
		else
			local c = line:sub(i, i)
			if c == '"' or c == "'" or c == "`" then
				local j = i + 1
				while j <= n do
					local d = line:sub(j, j)
					if d == "\\" then
						j += 2
					elseif d == c then
						break
					else
						j += 1
					end
				end

				i = j + 1
			elseif c == "-" and line:sub(i + 1, i + 1) == "-" then
				local eq = line:match("^%[(=*)%[", i + 2)
				if eq then
					long = #eq
					i = i + 4 + #eq
				else
					return long
				end
			elseif c == "[" then
				local eq = line:match("^%[(=*)%[", i)
				if eq then
					long = #eq
					i = i + 2 + #eq
				else
					i += 1
				end
			else
				i += 1
			end
		end
	end

	return long
end

local function split(source)
	local lines = {}
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end

	if lines[#lines] == "" then
		table.remove(lines)
	end

	return lines
end

local function mark(lines)
	local inside = {}
	local long = nil
	for index, line in lines do
		inside[index] = long ~= nil
		long = scan(line, long)
	end

	return inside
end

local function dedent(source)
	local lines = split(source)
	local inside = mark(lines)
	for index, line in lines do
		if not inside[index] and line:sub(1, 1) == "\t" then
			lines[index] = line:sub(2)
		end
	end

	return table.concat(lines, "\n")
end

local function trim(line)
	return line:match("^%s*(.-)%s*$")
end

local function indentOf(line)
	return #line:match("^\t*")
end

local closers = {
	["end"] = true,
	["else"] = true,
	["elseif"] = true,
	["until"] = true,
	["}"] = true,
	[")"] = true,
	["]"] = true,
}

local function opensBlock(text)
	return text:match("[{(,]$")
		or text:match("then$")
		or text:match("do$")
		or text:match("else$")
		or text:find("function", 1, true)
		or text:match("^%-%-")
end

local function startsClose(text)
	return closers[text:match("^[%w_]+") or ""] or closers[text:sub(1, 1)]
end

local function space(source)
	local lines = split(source)
	local inside = mark(lines)
	local out = {}
	for index, line in lines do
		local text = trim(line)
		local previous = out[#out]
		local prevText = previous and trim(previous) or ""
		if not inside[index] and previous ~= nil and prevText ~= "" then
			local wantBlank = false
			if text:match("^function[%s(]") or text:match("^local function[%s(]") then
				wantBlank = not opensBlock(prevText)
			elseif
				prevText == "end"
				and not startsClose(text)
				and indentOf(line) <= indentOf(previous)
			then
				wantBlank = true
			elseif
				prevText:match("^local [%w_]+ = Instance%.new%(") and not text:match("^%-%-")
			then
				wantBlank = true
			elseif text:match("^return ") and indentOf(line) == 0 then
				wantBlank = true
			end

			if wantBlank then
				table.insert(out, "")
			end
		end

		table.insert(out, line)
	end

	local result = {}
	local blank = false
	local marks = mark(out)
	for index, line in out do
		if line == "" and not marks[index] then
			if not blank then
				table.insert(result, line)
			end

			blank = true
		else
			table.insert(result, line)
			blank = false
		end
	end

	return table.concat(result, "\n")
end

local function json(text)
	local out = {}
	local depth = 0
	local i, n = 1, #text

	local function newline()
		table.insert(out, "\n" .. string.rep("\t", depth))
	end

	while i <= n do
		local c = text:sub(i, i)
		if c == '"' then
			local j = i + 1
			while j <= n do
				local d = text:sub(j, j)
				if d == "\\" then
					j += 2
				elseif d == '"' then
					break
				else
					j += 1
				end
			end

			table.insert(out, text:sub(i, j))
			i = j + 1
		elseif c == "{" or c == "[" then
			local close = c == "{" and "}" or "]"
			if text:sub(i + 1, i + 1) == close then
				table.insert(out, c .. close)
				i += 2
			else
				table.insert(out, c)
				depth += 1
				newline()
				i += 1
			end
		elseif c == "}" or c == "]" then
			depth -= 1
			newline()
			table.insert(out, c)
			i += 1
		elseif c == "," then
			table.insert(out, ",")
			newline()
			i += 1
		elseif c == ":" then
			table.insert(out, ": ")
			i += 1
		elseif c:match("%s") then
			i += 1
		else
			table.insert(out, c)
			i += 1
		end
	end

	return table.concat(out)
end

local function unwrap(name, source)
	local body = source:match("^%s*return function%(require%)\n(.*)\nend%s*$")
		or source:match("^%-%-[^\n]*\n\nreturn function%(require%)\n(.*)\nend\n?$")
	assert(body, "Unexpected runtime module shape: " .. name)
	body = space(dedent(body))
	if name == "Resources/EffectAssets" then
		local a, b = body:find("%[==%[.-%]==%]")
		if a then
			body = body:sub(1, a + 3) .. json(body:sub(a + 4, b - 4)) .. body:sub(b - 3)
		end
	end

	return HEADER .. "\n\n" .. body .. "\n"
end

local function version()
	if runtimeVersion then
		return runtimeVersion
	end

	local names = {}
	for name in Sources do
		table.insert(names, name)
	end

	table.sort(names)
	local hash = 7
	for _, name in names do
		local source = name .. "\0" .. Sources[name]
		for index = 1, #source do
			hash = (hash * 31 + source:byte(index)) % 4294967296
		end
	end

	runtimeVersion = string.format("2.%08x", hash)
	return runtimeVersion
end

function Package.installRuntime(folder)
	local current = version()
	local existing = folder:FindFirstChild(RUNTIME_NAME)
	if
		existing
		and existing:IsA("ModuleScript")
		and existing:GetAttribute("EclipseRuntime") == current
	then
		return existing, false
	end

	assert(
		not existing or existing:GetAttribute("EclipseRuntime"),
		"ReplicatedStorage.EclipseCutscenes."
			.. RUNTIME_NAME
			.. " is taken by something that is not the Eclipse runtime. Move it and export again."
	)
	assert(Sources[RUNTIME_ENTRY], "The runtime entry module is missing")
	local entry = module(nil, RUNTIME_NAME, unwrap(RUNTIME_ENTRY, Sources[RUNTIME_ENTRY]))
	local ok, message = xpcall(function()
		for name, source in Sources do
			if name == RUNTIME_ENTRY then
				continue
			end

			local pieces = string.split(name, "/")
			local parent = entry
			for index = 1, #pieces - 1 do
				local child = parent:FindFirstChild(pieces[index])
				if not child then
					child = Instance.new("Folder")

					child.Name = pieces[index]
					child.Parent = parent
				end

				parent = child
			end

			module(parent, pieces[#pieces], unwrap(name, source))
		end

		entry:SetAttribute("EclipseRuntime", current)
	end, debug.traceback)
	if not ok then
		entry:Destroy()
		error(message, 2)
	end

	if existing then
		local backup = Instance.new("Folder")

		backup.Name = unique(game:GetService("ServerStorage"), "Eclipse Runtime Backups")
		backup:SetAttribute("EclipseRuntimeBackup", true)
		backup.Parent = game:GetService("ServerStorage")
		existing.Parent = backup
	end

	entry.Parent = folder
	return entry, true
end

local HandlerTemplate = script.Parent.Sources.EclipseExportCutsceneHandler

local function handler()
	local object = HandlerTemplate:Clone()
	object.Name = "EclipseCutsceneHandler"
	object.Enabled = true
	return object
end

local subtitleDefaults =
	{ Entrance = "Fade", Exit = "Fade", InFrames = 12, OutFrames = 12, Order = 0, Preset = "Clean" }

local function style(base, reference)
	local out = {}
	for key, default in SubtitleData.defaults do
		if key == "Words" then
			continue
		end

		if key == "Text" or key == "Speaker" then
			if reference and base[key] ~= reference[key] then
				out[key] = base[key]
			end

			continue
		end

		if base[key] ~= default then
			out[key] = base[key]
		end
	end

	if next(base.Words or {}) then
		out.Words = base.Words
	end

	return out
end

local function subtitleRows(entries)
	local rows = {}
	for _, entry in entries do
		local cue = SubtitleData.copy(entry.event.Subtitle)
		local row = {
			{ "Frame", entry.event.Frame },
			{ "Duration", cue.Duration },
		}
		if cue.Base.Speaker ~= "" then
			table.insert(row, { "Speaker", cue.Base.Speaker })
		end

		table.insert(row, { "Text", cue.Base.Text })
		local look = style(cue.Base)
		if next(look) then
			table.insert(row, { "Style", look })
		end

		for _, key in { "Entrance", "Exit", "InFrames", "OutFrames", "Order", "Preset" } do
			if cue[key] ~= subtitleDefaults[key] then
				table.insert(row, { key, cue[key] })
			end
		end

		if #cue.Keys > 0 then
			local keys = {}
			for _, key in cue.Keys do
				table.insert(
					keys,
					{ Frame = key.Frame, Ease = key.Ease, Value = style(key.Value, cue.Base) }
				)
			end

			table.insert(row, { "Keys", keys })
		end

		table.insert(rows, row)
	end

	return rows
end

local function eventRows(events, rigNames, sources)
	local rows = {}
	for _, event in events do
		local data = event.Data
		local row = {}
		if data.Name and data.Name ~= "" then
			table.insert(row, { "Name", data.Name })
		end

		table.insert(row, { "Frame", event.Frame })
		if event.Rig then
			table.insert(row, { "Rig", rigNames[event.Rig] })
		end

		if (data.Duration or 0) > 0 then
			table.insert(row, { "Duration", data.Duration })
		end

		if event.Speed and event.Speed ~= 1 then
			table.insert(row, { "Speed", event.Speed })
		end

		if data.Parameter and data.Parameter ~= "" then
			table.insert(row, { "Parameter", data.Parameter })
		end

		if #(data.Sounds or {}) > 0 then
			table.insert(row, { "Sounds", data.Sounds })
		end

		if #(event.Markers or {}) > 0 then
			table.insert(row, { "Markers", event.Markers })
		end

		local extra = {}
		for key, value in data do
			if
				key ~= "Id"
				and key ~= "Name"
				and key ~= "Frame"
				and key ~= "Duration"
				and key ~= "Speed"
				and key ~= "Parameter"
				and key ~= "Sounds"
				and key ~= "Emits"
				and key ~= "Markers"
				and key ~= "Enabled"
			then
				extra[key] = value
			end
		end

		if next(extra) then
			table.insert(row, { "Data", extra })
		end

		for _, phase in { "Begin", "End" } do
			local id = event[phase]
			if id then
				local source = sources[id]
				assert(source, "Missing event code " .. tostring(id))
				table.insert(row, { phase, { code = source } })
			end
		end

		table.insert(rows, row)
	end

	return rows
end

local function renderRows(rows)
	local out = {}
	for _, row in rows do
		local lines = { "\t{" }
		for _, pair in row do
			local key, value = pair[1], pair[2]
			if type(value) == "table" and value.code then
				table.insert(lines, "\t\t" .. key .. " = function(rig, event, parameter, context)")
				local body = indented(value.code, 3)
				if body ~= "" then
					table.insert(lines, body)
				end

				table.insert(lines, "\t\tend,")
			else
				table.insert(lines, "\t\t" .. key .. " = " .. pretty(value, 2) .. ",")
			end
		end

		table.insert(lines, "\t},")
		table.insert(out, table.concat(lines, "\n"))
	end

	if #out == 0 then
		return "{}"
	end

	return "{\n" .. table.concat(out, "\n") .. "\n}"
end

local function cutsceneSource(options, data, subtitles, events, rigNames, sources)
	local lines = {
		HEADER,
		"",
		'local Eclipse = require("./' .. RUNTIME_NAME .. '")',
		"",
		"local Cutscene = {}",
		"",
		"Cutscene.FPS = " .. scalar(data.FPS),
		"Cutscene.LastFrame = " .. scalar(data.LastFrame),
		"Cutscene.Camera = " .. Codec.encode(data.CameraMode),
		"Cutscene.Loop = false",
		"Cutscene.Interpolate = true",
		"Cutscene.HideOriginals = true",
		"",
	}
	if options.Mode == "Button" then
		table.insert(lines, "Cutscene.Button = " .. pretty({
			Label = options.ButtonLabel,
			Theme = {
				Background = Theme.get("TopBtn", Color3.fromRGB(28, 30, 35)),
				Foreground = Theme.get("TopT", Color3.new(1, 1, 1)),
			},
		}))
		table.insert(lines, "")
	end

	table.insert(lines, "Cutscene.Subtitles = " .. renderRows(subtitleRows(subtitles)))
	table.insert(lines, "")
	table.insert(lines, "Cutscene.Events = " .. renderRows(eventRows(events, rigNames, sources)))
	table.insert(lines, "")
	table.insert(lines, "return Eclipse.build(script, Cutscene)")
	table.insert(lines, "")
	return table.concat(lines, "\n")
end
local guide = [====[
Eclipse cutscene

This module is yours. Edit it like any other script!! the plugin only reads Baked when you export again.

----PLAY IT

local Cutscene = require("./%s")
local player = Cutscene.new()

player:Play()
player:Pause()
player:Play()           -- resumes after Pause
player:Seek(1.5)        -- seconds
player:Stop()           -- restores the scene
player:Destroy()

Cutscene.new({ Loop = true, CameraMode = "Game", Interpolate = true, HideOriginals = true, ParentGui = yourGui })
Cutscene.FPS and Cutscene.Duration describe the export. player.Status is Stopped, Loading, Playing or Paused.

player.MarkerReached:Connect(function(name, parameter, frame) end)
player.Completed:Connect(function() end)
player.Stopped:Connect(function(reason) end)
player.Failed:Connect(function(message) end)

Cutscenes play on the client. Require the module from a LocalScript during Play.

----EDIT IT

Frame values are frames at Cutscene.FPS. Move them, and the cutscene follows.

Events      Begin runs at Frame, End runs at Frame + Duration. Both get rig, event, parameter
            and context. Custom code uses normal Roblox globals and receives the real rig instance.
            Native waits/tweens use real time; custom code owns cleanup for objects and tasks it creates.
            Use the built-in Sounds and Markers tracks for cutscene timing and seeking.
            Delete a row or add Enabled = false to skip it.
Subtitles   Text, Speaker, Frame and Duration. Style holds whatever you changed from the default
            look. Entrance, Exit, InFrames, OutFrames and Keys appear only when they differ.
Camera      "Authored" plays the exported camera, "Game" leaves your camera alone.
LastFrame   Trims the cutscene. Baked motion past it is ignored.
Button      Label and Theme for the shared button handler. Remove it to drop the button.

----PACKAGE

Baked            Sampled motion, scene links and geometry. Export again instead of editing it.
Scene            Actor and VFX copies. Leave their scripts disabled.
Meshes           Mesh variants used by ApplyMesh tracks.
Originals        References back to the original actors.
ProjectArchive   Authoring keyframes so the plugin can re-import this cutscene.
Scene/Assets     Local module dependencies, kept as normal readable ModuleScripts.
EclipseCutsceneRuntime   The shared runtime beside your cutscenes. One copy serves every export.
                         Do not delete it.

Move the cutscene wherever you like. Keep EclipseCutsceneRuntime next to it, or point the
require at the top of the module at the new spot.

----ANOTHER PLACE

Copy the whole EclipseCutscenes folder (cutscenes plus EclipseCutsceneRuntime) into the other
place's ReplicatedStorage, and EclipseCutsceneHandler into StarterPlayerScripts if you use the
buttons. Originals links will not resolve there, so actors are not hidden, but everything the
cutscene needs is inside the package.

----EXPERIENCE SETUP

Audio, image, mesh and animation IDs need permission in your experience. Editable meshes need
the Mesh & Image APIs setting. Restart Play after changing exported ModuleScripts.

----REMOVING CUTSCENES

Eclipse only adds runtime objects when you export a cutscene. If you no longer use cutscenes,
delete all of these and nothing from Eclipse runs in your game:
  ReplicatedStorage.EclipseCutscenes (every cutscene and EclipseCutsceneRuntime)
  StarterPlayer.StarterPlayerScripts.EclipseCutsceneHandler
The handler only builds its button panel when a Buttons cutscene exists, and it only hides
the Roblox top bar and core UI while a cutscene plays and you press ctrl + H. It restores
them when the cutscene stops. Eclipse never changes StarterGui or other place settings.
]====]

function Package.build(refs, options, progress)
	assert(options.Mode == "Button" or options.Mode == "Scripting", "Choose Buttons or Scripting")
	assert(
		options.Name ~= RUNTIME_NAME,
		RUNTIME_NAME .. " is reserved for the shared runtime. Choose another export name."
	)
	require("HumanoidScale").warnExport(refs.State.Timeline:GetState())
	local root, data, code = Bake.build(refs, options, progress)
	local launcherObject
	local ok, message = xpcall(function()
		if progress then
			progress("Packaging cutscene, baked data and launch controls…")
		end

		local sources = {}
		local assets, seenAssets = {}, {}
		for _, entry in code do
			sources[entry.Id] = entry.Source
			for asset in entry.Source:gmatch("rbxassetid://%d+") do
				if not seenAssets[asset] then
					seenAssets[asset] = true
					table.insert(assets, asset)
				end
			end
		end


		local names = {}
		for _, object in root.Scene:GetDescendants() do
			local id = object:GetAttribute("EclipseExportId")
			if id then
				names[id] = object.Name
			end
		end

		for _, global in data.Globals do
			names[global.Id] = names[global.Id] or global.Path[#global.Path]
		end

		local rigNames, rigs, taken = {}, {}, {}

		local function label(id)
			if rigNames[id] then
				return
			end

			local base = tostring(names[id] or ("Rig" .. id)):gsub("^%s+", ""):gsub("%s+$", "")
			if base == "" then
				base = "Rig" .. id
			end

			local name = base
			local index = 2
			while taken[name] do
				name = base .. " " .. index
				index += 1
			end

			taken[name] = true
			rigNames[id] = name
			rigs[name] = id
		end

		for _, record in data.Roots do
			if record.Kind == "Actor" or record.Kind == "Camera" then
				label(record.Id)
			end
		end

		for _, event in data.Events do
			if event.Rig then
				label(event.Rig)
			end
		end

		local baked = module(root, "Baked", "return {}")
		local chunkNames = {}
		local rows = {}
		local size = 0

		local function flush()
			if #rows == 0 then
				return
			end

			local name = string.format("Chunk_%03d", #chunkNames + 1)
			module(baked, name, "return {\n\t" .. table.concat(rows, ",\n\t") .. ",\n}\n")
			table.insert(chunkNames, name)
			rows = {}
			size = 0
		end

		for _, track in data.Tracks do
			local batch = {}
			local bytes = 0

			local function part()
				local copy = table.clone(track)
				copy.Samples = batch
				local source = Codec.encode(copy, nil, 1, true)
				if size + #source > 180000 then
					flush()
				end

				table.insert(rows, source)
				size += #source
				batch = {}
				bytes = 0
			end

			for _, sample in track.Samples do
				local encoded = Codec.encode(sample, nil, nil, true)
				if bytes + #encoded > 90000 and #batch > 0 then
					part()
				end

				table.insert(batch, sample)
				bytes += #encoded
			end

			if #batch > 0 then
				part()
			end
		end

		flush()
		local layout = storeData(baked, {
			Bindings = data.Bindings,
			Roots = data.Roots,
			Globals = data.Globals,
			Effects = data.Effects,
			EffectCameras = data.EffectCameras,
			Geometry = data.Geometry,
			Rigs = rigs,
			Assets = assets,
			Authored = data.CameraMode ~= "Game",
			ContentLastFrame = data.ContentLastFrame,
			SkipFrames = data.SkipFrames or 0,
			GreaseDrawings = data.GreaseDrawings,
		}, "Layout")
		Editor:UpdateSourceAsync(baked, function()
			return string.format(
				[====[%s

local baked = require(%q)
local chunks = %s
local tracks = {}

baked.Tracks = {}

for _, name in chunks do
	for _, track in require(`@self/{name}`) do
		local key = `{track.Target}:{track.Kind}:{track.Property}`
		local previous = tracks[key]

		if previous then
			for _, sample in track.Samples do
				table.insert(previous.Samples, sample)
			end
		else
			tracks[key] = track
			table.insert(baked.Tracks, track)
		end
	end
end

return baked
]====],
				HEADER,
				"@self/" .. layout,
				pretty(chunkNames)
			)
		end)
		local source = cutsceneSource(options, data, data.Subtitles, data.Events, rigNames, sources)
		Editor:UpdateSourceAsync(root, function()
			return source
		end)
		assert(root.Source == source, "Cannot write cutscene entry point")
		root:SetAttribute("EclipseCutscene", 2)
		root:SetAttribute("FPS", data.FPS)
		root:SetAttribute("EndFrame", data.LastFrame)
		root:SetAttribute("RequiresEditableMesh", next(data.Geometry) ~= nil)
		local text = string.format(guide, options.Name)
		local fence = "="
		while text:find("]" .. fence .. "]", 1, true) do
			fence ..= "="
		end

		module(
			root,
			"README",
			HEADER .. "\n\n--[" .. fence .. "[\n" .. text .. "]" .. fence .. "]\n\nreturn {}\n"
		)
		if options.Mode == "Button" then
			root:SetAttribute("EclipseLaunchMode", options.Mode)
			launcherObject = handler()
			launcherObject:SetAttribute("EclipseCutsceneHandler", 1)
			launcherObject:SetAttribute("Cutscene", options.Name)
			launcherObject:SetAttribute("Mode", options.Mode)
			launcherObject:SetAttribute("ButtonLabel", options.ButtonLabel)
			launcherObject:SetAttribute("EclipseHandlerVersion", 5)
		end
	end, debug.traceback)
	if not ok then
		root:Destroy()
		if launcherObject then
			launcherObject:Destroy()
		end

		error(message, 2)
	end

	return root, launcherObject
end

local function fingerprint(text)
	local a, b = 7, 11
	for index = 1, #text do
		local byte = text:byte(index)
		a = (a * 31 + byte) % 4294967296
		b = (b * 131 + byte) % 4294967296
	end

	return string.format("%08x%08x", a, b)
end

local generatedHandlers = {
	["3a5ef365a9e42dbd"] = true,
	["c606d6ddd69c8f5d"] = true,
	["c4fa40b91bd3be65"] = true,
	["21019d6f55159673"] = true,
}

local replacedHandlers = {
	["2385fc3ce22c2b60"] = true,
	["96cccde649fe6596"] = true,
	["8f83073bbcd7000b"] = true,
	["98d9c1cd71a93c8d"] = true,
	["78b505c570beeae9"] = true,
	["d56cbb750e927ad9"] = true,
	["3b97cf45da39e009"] = true,
}

local function isGenerated(source)
	return generatedHandlers[fingerprint(source)] == true
end

local function isReplaceable(source)
	return replacedHandlers[fingerprint(source)] == true
end

function Package.refreshHandlers()
	const starter = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
	if not starter then
		return 0
	end

	const source = HandlerTemplate.Source
	local count = 0
	for _, object in starter:GetChildren() do
		if
			object:IsA("LocalScript")
			and object:GetAttribute("EclipseCutsceneHandler") == 1
			and object.Source ~= source
			and isReplaceable(object.Source)
		then
			const ok = pcall(function()
				Editor:UpdateSourceAsync(object, function()
					return source
				end)
			end)
			if ok and object.Source == source then
				count += 1
			end
		end
	end

	return count
end
function Package.installHandler(proposed)
	local starter = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
	assert(starter, "StarterPlayerScripts is missing")
	local storage = game:GetService("ReplicatedStorage"):FindFirstChild("EclipseCutscenes")
	assert(storage and storage:IsA("Folder"), "EclipseCutscenes is missing")

	local existing
	local legacy = {}

	for _, object in starter:GetChildren() do
		if object:GetAttribute("EclipseCutsceneHandler") == 1 then
			assert(object:IsA("LocalScript") and not existing, "Multiple Eclipse handlers found")
			existing = object
		elseif object:IsA("LocalScript") and object:GetAttribute("EclipseCutsceneLauncher") then
			local package = storage:FindFirstChild(tostring(object:GetAttribute("Cutscene")))
			if
				package
				and package:IsA("ModuleScript")
				and package:GetAttribute("EclipseCutscene") == 1
			then
				assert(
					isGenerated(object.Source),
					"The handler "
						.. object.Name
						.. " has custom edits. Keep a copy and remove it from StarterPlayerScripts before consolidating."
				)
				table.insert(legacy, {
					script = object,
					package = package,
					source = object.Source,
					enabled = object.Enabled,
				})
			end
		end
	end

	local replaced = existing
			and isReplaceable(existing.Source)
			and existing
		or nil
	local replacedEnabled = replaced and replaced.Enabled
	if replaced then
		existing = nil
	end

	local target = existing
		or proposed
		or handler()
	if not existing then
		target.Name = "EclipseCutsceneHandler"
		target:SetAttribute("EclipseCutsceneHandler", 1)
		target:SetAttribute("EclipseHandlerVersion", 5)
		target:SetAttribute("Cutscene", nil)
		target:SetAttribute("Mode", nil)
		target:SetAttribute("Command", nil)
		target:SetAttribute("ButtonLabel", nil)
	end

	local backup
	local configs = {}
	local attributes = {}
	local moved = {}
	local ok, message = xpcall(function()
		for _, record in legacy do
			local object = record.script
			assert(
				object.Source == record.source and object.Parent == starter,
				"Legacy handler changed during migration"
			)
			if not record.package:FindFirstChild("Launch") then
				local config = module(record.package, "Launch", "return " .. Codec.encode({
					Mode = object:GetAttribute("Mode"),
					ButtonLabel = object:GetAttribute("ButtonLabel"),
					Command = object:GetAttribute("Command"),
				}))
				table.insert(configs, config)
				table.insert(attributes, {
					package = record.package,
					mode = record.package:GetAttribute("EclipseLaunchMode"),
					command = record.package:GetAttribute("EclipseCommand"),
				})
				record.package:SetAttribute("EclipseLaunchMode", object:GetAttribute("Mode"))
				record.package:SetAttribute("EclipseCommand", object:GetAttribute("Command"))
			end
		end

		if #legacy > 0 or replaced then
			backup = Instance.new("Folder")

			backup.Name =
				unique(game:GetService("ServerStorage"), "Eclipse Cutscene Handler Backups")
			backup:SetAttribute("EclipseHandlerBackup", true)
			backup.Parent = game:GetService("ServerStorage")
		end

		for _, record in legacy do
			table.insert(moved, record)
			record.script.Enabled = false
			record.script.Parent = backup
		end

		if replaced then
			assert(
				replaced.Parent == starter and isReplaceable(replaced.Source),
				"Shared handler changed during upgrade"
			)
			replaced.Enabled = false
			replaced.Parent = backup
		end

		if not existing then
			target.Parent = starter
		end
	end, debug.traceback)

	if not ok then
		if replaced and replaced.Parent == backup then
			replaced.Parent = starter
			replaced.Enabled = replacedEnabled
		end

		for _, record in moved do
			record.script.Parent = starter
			record.script.Enabled = record.enabled
		end

		for _, config in configs do
			config:Destroy()
		end

		for _, record in attributes do
			record.package:SetAttribute("EclipseLaunchMode", record.mode)
			record.package:SetAttribute("EclipseCommand", record.command)
		end

		if backup then
			backup:Destroy()
		end

		if not existing then
			target:Destroy()
		end

		error(message, 2)
	end

	if proposed and proposed ~= target then
		proposed:Destroy()
	end

	return target, #moved
end

function Package.install(root, proposed)
	local storage = game:GetService("ReplicatedStorage")
	local folder = storage:FindFirstChild("EclipseCutscenes")
	assert(
		not folder or folder:IsA("Folder"),
		"ReplicatedStorage.EclipseCutscenes must be a Folder"
	)
	assert(
		not folder or not folder:FindFirstChild(root.Name),
		"An export named " .. root.Name .. " already exists. Choose another name to preserve it."
	)

	local created
	local handler
	local ok, message = xpcall(function()
		if not folder then
			folder = Instance.new("Folder")

			folder.Name = "EclipseCutscenes"
			folder.Parent = storage
			created = folder
		end

		Package.installRuntime(folder)
		root.Parent = folder
		if proposed then
			handler = Package.installHandler(proposed)
		end
	end, debug.traceback)

	if not ok then
		root.Parent = nil
		if created then
			created:Destroy()
		end

		error(message, 2)
	end

	return root, handler
end

return Package
