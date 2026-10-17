--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Library = require("ImageLibrary")
local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")
local ImageUpload = {}

function ImageUpload.prompt()
	local file, editable, metadata
	local ok, asset, message = pcall(function()
		file = StudioService:PromptImportFileAsync({ "png", "jpg", "jpeg", "bmp", "tga" })
		if not file then
			return nil
		end

		editable = AssetService:CreateEditableImageAsync(Content.fromUri(file:GetTemporaryId()))
		if not editable then
			return nil, "Could not load this image. Try a smaller image or paste its asset ID."
		end

		local name = file.Name:gsub("%.[^.]+$", "")
		metadata = { name = name, width = editable.Size.X, height = editable.Size.Y }
		local result, id = AssetService:CreateAssetAsync(editable, Enum.AssetType.Image, {
			Name = name,
			Description = "Eclipse image",
		})
		if result ~= Enum.CreateAssetResult.Success then
			return nil,
				"Upload failed: " .. result.Name .. ". You can also paste an image asset ID."
		end

		return "rbxassetid://" .. tostring(id)
	end)
	if editable then
		editable:Destroy()
	end

	if file then
		file:Destroy()
	end

	if not ok then
		warn("Eclipse image upload: " .. tostring(asset))
		return nil,
			"Upload unavailable. Use the local plugin in Studio, or paste an image asset ID."
	end

	if asset then
		Library.add(asset, metadata)
	end

	return asset, message, metadata
end

local localFiles = {}

function ImageUpload.promptLocal()
	local file
	local ok, id = pcall(function()
		file = StudioService:PromptImportFileAsync({ "png", "jpg", "jpeg", "bmp", "tga" })
		if not file then return nil end
		return file:GetTemporaryId()
	end)
	if not ok then
		if file then file:Destroy() end
		warn("Eclipse local image: " .. tostring(id))
		return nil, "Could not open the local image. You can also paste an image ID or rbxasset:// path."
	end
	if not id then return nil end
	localFiles[id] = file
	Library.add(id, { name = file.Name })
	return id, "Local image loaded for this Studio session. Reimport it after restarting Studio."
end

return ImageUpload
