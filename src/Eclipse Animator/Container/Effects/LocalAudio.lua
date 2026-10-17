--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local LocalAudio = {}
local files = {}
local opening = false
local PREFIX = "eclipse-local-audio:"

function LocalAudio.is(id)
	return type(id) == "string" and id:sub(1, #PREFIX) == PREFIX
end

function LocalAudio.resolve(id)
	local row = files[id]
	return row and row.uri
end

function LocalAudio.prompt(previous, isCurrent)
	if opening then
		return nil
	end

	opening = true
	local ok, file = pcall(function()
		return game:GetService("StudioService"):PromptImportFileAsync({ "mp3", "ogg", "wav" })
	end)
	opening = false
	if not ok then
		return nil, tostring(file)
	end

	if not file then
		return nil
	end

	if isCurrent and not isCurrent() then
		file:Destroy()
		return nil
	end

	local valid, uri = pcall(function()
		return file:GetTemporaryId()
	end)
	if not valid or type(uri) ~= "string" or uri == "" then
		file:Destroy()
		return nil, "Could not load the selected audio file."
	end

	local id = LocalAudio.is(previous) and previous
		or PREFIX .. game:GetService("HttpService"):GenerateGUID(false)
	local old = files[id]
	files[id] = { file = file, uri = uri }
	if old then
		old.file:Destroy()
	end

	return id, nil, file.Name
end

function LocalAudio.clear()
	for id, row in files do
		row.file:Destroy()
		files[id] = nil
	end
end

return LocalAudio
