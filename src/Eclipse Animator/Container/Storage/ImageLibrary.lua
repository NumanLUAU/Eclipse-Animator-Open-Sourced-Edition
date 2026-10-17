--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Data = require("ProjectData")
local Http = game:GetService("HttpService")
local Sequence = require("Sequence")
local Library = {}
local KEY = "EclipseRecentImagesV1"
local loaded, entries = false, {}
local listeners = {}

local function validSize(n)
	return type(n) == "number" and n == n and n > 0 and n <= 32768
end

local function ensureLoaded()
	if loaded then
		return
	end

	loaded = true
	local ok, saved = pcall(Data.getSetting, KEY)
	if ok and type(saved) == "string" then
		ok, saved = pcall(Http.JSONDecode, Http, saved)
	end

	if not ok or type(saved) ~= "table" then
		return
	end

	local seen = {}
	for _, entry in ipairs(saved) do
		if type(entry) ~= "table" then
			continue
		end

		local id = Sequence.asset(entry.id)
		if id and not id:match("^rbxtemp://") and not seen[id] then
			seen[id] = true
			table.insert(entries, {
				id = id,
				name = type(entry.name) == "string" and entry.name or "Image",
				width = validSize(entry.width) and entry.width or nil,
				height = validSize(entry.height) and entry.height or nil,
			})
			if #entries == 10 then
				break
			end
		end
	end
end

function Library.recent()
	ensureLoaded()
	local copy = {}
	for i, entry in entries do
		copy[i] = table.clone(entry)
	end

	return copy
end

function Library.add(id, metadata)
	ensureLoaded()
	id = Sequence.asset(id)
	if not id then
		return false
	end

	metadata = metadata or {}
	for i = #entries, 1, -1 do
		if entries[i].id == id then
			table.remove(entries, i)
		end
	end

	table.insert(entries, 1, {
		id = id,
		name = metadata.name or "Image",
		width = validSize(metadata.width) and metadata.width or nil,
		height = validSize(metadata.height) and metadata.height or nil,
	})
	while #entries > 10 do
		table.remove(entries)
	end

	local persistent = {}
	for _, entry in entries do
		if not entry.id:match("^rbxtemp://") then table.insert(persistent, entry) end
	end
	local ok, err = pcall(Data.setSetting, KEY, Http:JSONEncode(persistent))
	if not ok then
		warn("Eclipse recent images: " .. tostring(err))
	end

	for callback in listeners do
		callback()
	end

	return true
end

function Library.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

local resolvedImages = {}

local function canLoad(id)
	local loaded = false
	local probe = Instance.new("ImageLabel")
	probe.Image = id
	local ok = pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ probe }, function(_, status)
			loaded = status == Enum.AssetFetchStatus.Success
		end)
	end)
	probe:Destroy()
	return ok and loaded
end

function Library.resolve(value)
	local id = assert(Sequence.asset(value), "Paste an image or decal asset ID.")
	if resolvedImages[id] then
		return resolvedImages[id]
	end

	if canLoad(id) then
		resolvedImages[id] = id
		return id
	end

	require("Notification").show("TEMPORARILY DOWN", "Decal ID resolution is temporarily down. Use an image asset ID.", 5)
	error(
		"Decal ID resolution is temporarily down. Use an image asset ID.",
		0
	)
end

return Library
