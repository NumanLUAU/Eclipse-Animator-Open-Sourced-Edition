--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Codec = require("ArmatureAnimation")
local LibraryCodec = {}

local function pack(value, seen)
	if typeof(value) == "Color3" then
		return { EclipseLibraryType = "Color3", value = { value.R, value.G, value.B } }
	end

	if typeof(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return nil
	end

	seen[value] = true
	local out = {}
	for key, item in value do
		out[key] = pack(item, seen)
	end

	seen[value] = nil
	return out
end

local function unpackValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	if value.EclipseLibraryType == "Color3" then
		return Color3.new(table.unpack(value.value))
	end

	local out = {}
	for key, item in value do
		out[key] = unpackValue(item)
	end

	return out
end

function LibraryCodec.encode(value)
	return Codec.encode(pack(value))
end

function LibraryCodec.decode(value)
	return unpackValue(Codec.decode(value))
end

return LibraryCodec
