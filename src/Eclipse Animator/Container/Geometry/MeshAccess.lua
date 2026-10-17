--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local AssetService = game:GetService("AssetService")
local Access = {}
local denied = {}
local warned = false

function Access.isDenied(message)
	local text = tostring(message):lower()
	return text:find("no permission", 1, true) ~= nil
		or text:find("not allowed to be forked", 1, true) ~= nil
		or text:find("not authorized", 1, true) ~= nil
		or text:find("mesh access denied", 1, true) ~= nil
end

function Access.open(content, options)
	local key = content
	local okUri, uri = pcall(function()
		return content.Uri
	end)
	if okUri and type(uri) == "string" and uri ~= "" then
		key = uri
	end

	if denied[key] then
		error(denied[key], 0)
	end

	local ok, result = pcall(function()
		return AssetService:CreateEditableMeshAsync(content, options)
	end)
	if ok then
		return result
	end

	if not Access.isDenied(result) then
		error(result, 0)
	end

	local asset = type(key) == "string" and key or "this mesh"
	local message = "Mesh access denied: "
		.. asset
		.. ". Ask the asset owner to grant mesh access to your Studio account or the experience owner/group, or use a mesh you own. Reload Eclipse after access is granted. Basic posing can continue; exact mesh deformation is unavailable."
	denied[key] = message
	if not warned then
		warn("[Eclipse Armature] " .. message)
		warned = true
	end

	pcall(function()
		require("Notification").showOnce(
			"MESH ACCESS REQUIRED",
			"Roblox denied mesh access. Use a mesh you own or ask its owner to grant access. Basic posing works, but exact deformation may not.",
			5
		)
	end)
	error(message, 0)
end

function Access.clear()
	table.clear(denied)
end

return Access
