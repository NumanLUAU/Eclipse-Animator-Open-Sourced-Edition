--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("ProjectData")
local Codec = require("ValueCodec")
local Http = game:GetService("HttpService")
local Serializer = game:GetService("SerializationService")
local Storage = {}
local KEY = "EclipseLibraryV1"
local listeners = {}

local function read(key)
	local value = Data.getSetting(key)
	if value == nil then
		return nil
	end

	assert(typeof(value) == "string", "Couldn't read the library save.")
	return Http:JSONDecode(value)
end

local function write(key, value)
	local text = Http:JSONEncode(value)
	Data.setSetting(key, text)
	assert(Data.getSetting(key) == text, "Studio couldn't save the library. Please try again.")
end

function Storage.index()
	local value = read(KEY) or { version = 1, entries = {}, rigs = {} }
	assert(
		value.version == 1 and typeof(value.entries) == "table" and typeof(value.rigs) == "table",
		"This library needs a newer version of Eclipse."
	)
	return value
end

local function changed()
	for callback in listeners do
		task.defer(callback)
	end
end

function Storage.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

function Storage.entries(kind)
	local out = {}
	for _, entry in Storage.index().entries do
		if not kind or entry.kind == kind then
			table.insert(out, entry)
		end
	end

	table.sort(out, function(a, b)
		return a.created == b.created and a.id < b.id or a.created > b.created
	end)
	return out
end

function Storage.rig(id)
	return Storage.index().rigs[id]
end

function Storage.saveRig(id, model, name, signature)
	local index = Storage.index()
	if index.rigs[id] and index.rigs[id].signature == signature then
		return id
	end

	local content = Serializer:SerializeInstancesAsync({ model })
	write("EclipseLibraryRig" .. id, content)
	index = Storage.index()
	index.rigs[id] = { id = id, name = name, signature = signature }
	write(KEY, index)
	return id
end

function Storage.loadRig(id)
	local content = assert(read("EclipseLibraryRig" .. id), "The rig for this save is missing.")
	local roots = Serializer:DeserializeInstancesAsync(content)
	local rig = roots[1]
	for i = 2, #roots do
		roots[i]:Destroy()
	end

	assert(rig and rig:IsA("Model"), "Couldn't open the saved rig.")
	return rig
end

function Storage.add(kind, name, rigId, data, duration)
	local id = Http:GenerateGUID(false):gsub("%-", "")
	write("EclipseLibraryItem" .. id, Codec.encode(data))
	local index = Storage.index()
	local entry = {
		id = id,
		kind = kind,
		name = name,
		rig = rigId,
		duration = duration or 0,
		created = DateTime.now().UnixTimestampMillis,
		camera = { 0, 0, 0 },
	}
	table.insert(index.entries, entry)
	write(KEY, index)
	changed()
	return entry
end

function Storage.data(id)
	return Codec.decode(assert(read("EclipseLibraryItem" .. id), "This save is missing."))
end

function Storage.update(id, fields)
	local index = Storage.index()
	for _, entry in index.entries do
		if entry.id == id then
			for key, value in fields do
				if key == "name" or key == "camera" then
					entry[key] = value
				end
			end

			write(KEY, index)
			changed()
			return entry
		end
	end

	error("This save was removed in another Studio window.")
end

function Storage.remove(id)
	local index = Storage.index()
	for i = #index.entries, 1, -1 do
		if index.entries[i].id == id then
			table.remove(index.entries, i)
		end
	end

	write(KEY, index)
	changed()
end

return Storage
