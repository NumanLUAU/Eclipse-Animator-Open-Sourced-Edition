--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Storage = game:GetService("ServerStorage")
local Cleanup = {}
local Journal = {}
Journal.__index = Journal
local owner
local visuals = setmetatable({}, { __mode = "k" })
local MARK = "EclipseEventRuntimeJournal"

local function ownerFolder()
	if not owner or not owner.Parent then
		owner = require("root").get("_EclipseEventRuntime", true)
		owner.Archivable = true
		owner:SetAttribute(MARK, 1)
	end

	return owner
end

local function releaseOwner()
	if owner and owner.Parent and #owner:GetChildren() == 0 then
		owner:Destroy()
		owner = nil
	end
end

local function reference(parent, name, object)
	local entry = Instance.new("ObjectValue")
	entry.Name = name
	entry.Value = object
	entry.Parent = parent
	return entry
end

function Cleanup.new()
	return setmetatable({ objects = {}, owned = {} }, Journal)
end

function Journal:folder()
	if not self.root then
		self.root = Instance.new("Folder")
		self.root.Name = "Session"
		self.root.Parent = ownerFolder()
	end

	return self.root
end

function Journal:own(object)
	if self.owned[object] then
		return
	end

	self.owned[object] = reference(self:folder(), "Owned", object)
end

local function fieldName(key, kind)
	return (kind == "Attribute" and "a" or kind == "Tag" and "t" or kind == "Scale" and "s" or "p")
		.. key
end

local function clearField(entry, field)
	for _, prefix in { "n", "e", "v" } do
		entry:SetAttribute(prefix .. field, nil)
	end

	for _, child in entry:GetChildren() do
		if child:IsA("ObjectValue") and child.Name == field then
			child:Destroy()
		end
	end
end

function Journal:remember(object, key, value, kind)
	local entry = self.objects[object]
	if not entry then
		entry = reference(self:folder(), "Restore", object)
		self.objects[object] = entry
	end

	local field = fieldName(key, kind)
	if value == nil then
		entry:SetAttribute("n" .. field, true)
	elseif typeof(value) == "Instance" then
		reference(entry, field, value)
	elseif typeof(value) == "EnumItem" then
		entry:SetAttribute("e" .. field, tostring(value))
	else
		local ok = pcall(function()
			entry:SetAttribute("v" .. field, value)
		end)
		if not ok and key == "TextureContent" and field == "pTextureContent" then
			local uri
			if typeof(value) == "Content" then
				local success, result = pcall(function()
					return value.Uri
				end)
				if success and typeof(result) == "string" then
					uri = result
				end
			end

			entry:SetAttribute("vpTexture", uri or object.Texture)
		end
	end
end

function Journal:update(object, key, value, kind)
	local entry = self.objects[object]
	if entry then
		local field = fieldName(key, kind)
		clearField(entry, field)
		if field == "pTextureContent" then
			clearField(entry, "pTexture")
		elseif field == "pTexture" then
			clearField(entry, "pTextureContent")
		end
	end

	self:remember(object, key, value, kind)
end

function Journal:finish()
	if self.root then
		self.root:Destroy()
		self.root = nil
	end

	table.clear(self.objects)
	table.clear(self.owned)
	releaseOwner()
end

function Cleanup.visual(object)
	if visuals[object] then
		return
	end

	local entry = reference(ownerFolder(), "Visual", object)
	visuals[object] = entry
	object.Destroying:Once(function()
		visuals[object] = nil
		entry:Destroy()
		releaseOwner()
	end)
end

function Cleanup.isVisual(object)
	return visuals[object] ~= nil
end

function Cleanup.clearVisuals()
	for object, entry in visuals do
		pcall(function()
			object:Destroy()
		end)
		entry:Destroy()
	end

	table.clear(visuals)
	releaseOwner()
end

local function restore(entry, pass)
	local object = entry.Value
	if not object then
		return
	end

	local function apply(field, value)
		local kind, key = field:sub(1, 1), field:sub(2)
		local stage = kind == "s" and 1 or kind == "p" and key == "Parent" and 3 or 2
		if pass ~= stage then
			return
		end

		pcall(function()
			if kind == "s" then
				object:ScaleTo(value)
			elseif kind == "a" then
				object:SetAttribute(key, value)
			elseif kind == "t" then
				if value then
					object:AddTag(key)
				else
					object:RemoveTag(key)
				end
			else
				object[key] = value
			end
		end)
	end

	for field, value in entry:GetAttributes() do
		local encoded = field:sub(1, 1)
		if encoded == "n" then
			value = nil
		elseif encoded == "e" then
			local enum, item = value:match("^Enum%.([^.]+)%.(.+)$")
			local ok, result = pcall(function()
				return Enum[enum][item]
			end)
			if not ok then
				continue
			end

			value = result
		end

		apply(field:sub(2), value)
	end

	for _, child in entry:GetChildren() do
		if child:IsA("ObjectValue") then
			apply(child.Name, child.Value)
		end
	end
end

function Cleanup.recover(target)
	local roots
	if target then
		roots = { target }
	else
		local root = require("root").migrate()
		roots = Storage:GetChildren()
		if root then
			for _, child in root:GetChildren() do
				table.insert(roots, child)
			end
		end
	end

	for _, root in roots do
		if not root:IsA("Folder") or root:GetAttribute(MARK) ~= 1 then
			continue
		end

		local entries = root:GetDescendants()
		local restores = {}
		for _, entry in entries do
			if entry:IsA("ObjectValue") and entry.Name == "Restore" then
				local depth, object = 0, entry.Value
				while object do
					depth += 1
					object = object.Parent
				end

				table.insert(restores, { entry = entry, depth = depth })
			end
		end

		table.sort(restores, function(a, b)
			return a.depth < b.depth
		end)
		for pass = 1, 3 do
			for _, record in restores do
				restore(record.entry, pass)
			end
		end

		for _, entry in entries do
			if
				entry:IsA("ObjectValue")
				and (entry.Name == "Owned" or entry.Name == "Visual")
				and entry.Value
			then
				pcall(function()
					entry.Value:Destroy()
				end)
			end
		end

		root:Destroy()
	end

	if target then
		return
	end

	for _, object in workspace:GetDescendants() do
		if object.Archivable then
			continue
		end

		local native = object:IsA("ParticleEmitter")
			and object.Name == "EclipseEventPlayback"
			and not object.Enabled
		local particle = object:IsA("Attachment")
			and object.Name == "EclipseEventParticle"
			and object.Parent == workspace.Terrain
		local holder = object:IsA("Folder")
			and object.Name == "EclipseEventHold"
			and object.Parent == workspace
		if native or particle or holder then
			pcall(function()
				object:Destroy()
			end)
		end
	end
end

return Cleanup
