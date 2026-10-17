--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Storage = require("Storage")
local Rig = require("Rig")
local Animation = require("Animation")
local Resolve = require("Resolve")
local Sequence = require("Sequence")
local History = require("History")
local Selection = game:GetService("Selection")
local Library = {}
local refs = {}
local uploading = false
local Window = require("Window")
local Upload = require("Upload")
local Audio = require("Audio")
local Images = require("ImageLibrary")

local function target()
	local state = refs.State
	local rig =
		Resolve.resolve(state.getAllRigs(), Selection:Get(), state.Rig and state.Rig._selectedItems)
	assert(rig, "Select one rig or master in this file first.")
	return rig
end

local nouns = { Poses = "Pose", Animations = "Animation", Faces = "Face", Sounds = "Sound" }

function Library.nextName(kind)
	local noun = assert(nouns[kind], "Choose a library category.")
	local highest = 0
	for _, entry in Storage.entries(kind) do
		local number = entry.name:match("^" .. noun .. " (%d+)$")
		if number then
			highest = math.max(highest, tonumber(number))
		end
	end

	return noun .. " " .. (highest + 1)
end

local function nameOf(value, kind)
	local text = tostring(value or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
	return text ~= "" and text or Library.nextName(kind)
end

function Library.capture(kind, name, faceId, selectedOnly)
	name = nameOf(name, kind)
	if kind == "Faces" or kind == "Sounds" then
		local id = Sequence.asset(faceId)
		assert(
			id,
			kind == "Sounds" and "Paste an audio asset ID." or "Paste an image or decal asset ID."
		)
		if kind == "Faces" then
			id = Images.resolve(id)
		end

		local metadata = kind == "Sounds" and Audio.metadata(id) or {}
		return Storage.add(kind, name, nil, { id = id }, metadata.duration)
	end

	local rig = target()
	refs.Finalize()
	local timeline = refs.State.Timeline
	local selectedMotors
	if kind == "Poses" and selectedOnly then
		selectedMotors = {}
		for item, enabled in refs.State.Rig._selectedItems or {} do
			local row = item.parentBoneItem or item
			local motor = enabled and row.fetchMotor and row:fetchMotor()
			if motor then
				selectedMotors[motor] = true
			end
		end

		assert(next(selectedMotors), "Select at least one bone to save a partial pose.")
	end

	local data = Animation.capture(rig, timeline, kind, refs.BuildPreview, selectedMotors)
	local id = Rig.save(rig, timeline:GetState())
	return Storage.add(kind, name, id, data, data.duration)
end

function Library.apply(entry)
	local rig = target()
	refs.Finalize()
	local data = Storage.data(entry.id)
	if entry.kind == "Sounds" then
		local parent = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart or rig
		local sound = Instance.new("Sound")
		sound.Name = entry.name
		sound.SoundId = data.id
		sound.Volume = 0.5
		sound.Parent = parent
		History.record(function()
			sound.Parent = nil
		end, function()
			sound.Parent = parent
		end, "Insert sound")
	elseif entry.kind == "Faces" then
		local image = Images.resolve(data.id)
		local faces = require("Faces")
		assert(faces.supports(rig), "Select a rig with a Head part to use this face.")
		local timeline = refs.State.Timeline
		faces.set(timeline, rig, timeline:TimeToFrame(timeline:GetState().CurrentTime), image)
		if refs.RefreshStructure then refs.RefreshStructure() end
	else
		Animation.apply(
			data,
			rig,
			refs.State.Timeline,
			refs.State.UIHelpers.SanitizeName,
			refs.RefreshStructure
		)
	end

	refs.State.currentProjectSaved = false
	return true
end

function Library.insertRig(entry)
	assert(entry.rig, "This save doesn't include a rig.")
	local rig = Storage.loadRig(entry.rig)
	local name = Storage.rig(entry.rig).name
	local used = {}
	for _, other in refs.State.getAllRigs() do
		used[other.Name] = true
	end

	local suffix = 2
	rig.Name = name
	while used[rig.Name] do
		rig.Name = name .. " " .. suffix
		suffix += 1
	end

	rig.Parent = workspace
	local ok, err = pcall(function()
		refs.AddRig(rig)
		assert(
			table.find(refs.State.getAllRigs(), rig),
			"Open an animation file before inserting a rig."
		)
	end)
	if not ok then
		rig:Destroy()
		error(err, 0)
	end

	Selection:Set({ rig })
	return rig
end

function Library.upload(kind)
	if kind == "Sounds" then
		return Audio.upload()
	end

	assert(kind == "Faces", "Choose Faces or Sounds to upload.")
	if uploading then
		return nil, "An image upload is already open."
	end

	uploading = true
	local result = table.pack(pcall(Upload.prompt))
	uploading = false
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

function Library.selectedAsset(kind)
	if kind == "Sounds" then
		for _, object in Selection:Get() do
			if object:IsA("Sound") then
				return object.SoundId
			elseif object:IsA("AudioPlayer") then
				return object.Asset
			end
		end

		return ""
	end

	for _, object in Selection:Get() do
		if object:IsA("Decal") or object:IsA("Texture") then
			return object.Texture
		end

		local head = object:FindFirstChild("Head", true)
		local decal = head and head:FindFirstChildWhichIsA("Decal")
		if decal then
			return decal.Texture
		end
	end

	return ""
end

function Library.rename(entry, name)
	local value = tostring(name or ""):match("^%s*(.-)%s*$")
	return Storage.update(
		entry.id,
		{ name = value == "" and entry.name or nameOf(value, entry.kind) }
	)
end

function Library.camera(entry, values)
	for i = 1, 3 do
		assert(
			typeof(values[i]) == "number"
				and values[i] == values[i]
				and math.abs(values[i]) < math.huge,
			"Use a number for the camera position."
		)
	end

	return Storage.update(entry.id, { camera = values })
end

function Library.init(options)
	refs = options
	Window.init({
		Controller = Library,
		ScreenGui = refs.ScreenGui,
		AnimatorFrame = refs.AnimatorFrame,
		State = refs.State,
		HoverDialog = refs.HoverDialog,
		OnDestroy = function()
			if refs.State then
				refs.State.Library = nil
			end
		end,
	})
	refs.State.Library = Library
end

function Library.isOpen()
	return Window.isOpen()
end

function Library.open()
	return Window.open()
end

function Library.openFaces(owner, pick)
	return Window.open({ owner = owner, pick = pick, kind = "Faces" })
end

function Library.imageEntries()
	local entries = {}
	for _, image in require("ImageLibrary").recent() do
		table.insert(entries, {
			id = "recent:" .. image.id,
			name = image.name,
			kind = "Faces",
			image = image.id,
			readOnly = true,
		})
	end

	for _, entry in Storage.entries("Faces") do
		table.insert(entries, entry)
	end

	return entries
end

function Library.openImages(owner, pick, hostGui)
	return Window.open({
		owner = owner,
		pick = pick,
		kind = "Faces",
		title = "IMAGE LIBRARY",
		includeRecent = true,
		hostGui = hostGui,
	})
end

function Library.openSounds(owner, pick)
	return Window.open({ owner = owner, pick = pick })
end

function Library.closeSounds(owner)
	return Window.closeSounds(owner)
end

function Library.close()
	return Window.close()
end

function Library.toggle()
	if Library.isOpen() then
		Library.close()
	else
		Library.open()
	end
end

function Library.destroy()
	Window.destroy()
	Audio.stop()
	Rig.clear()
	if refs.State then
		refs.State.Library = nil
	end

	refs = {}
end

return Library
