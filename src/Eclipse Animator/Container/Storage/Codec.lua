--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Codec = {}

local function number(value)
	assert(value == value and math.abs(value) < math.huge, "Cannot export a non-finite number")
	return string.format("%.17g", value)
end

function Codec.encode(value, seen, depth, compact)
	local kind = typeof(value)
	if kind == "nil" then
		return "nil"
	end

	if kind == "string" then
		return string.format("%q", value)
	end

	if kind == "number" then
		return number(value)
	end

	if kind == "boolean" then
		return tostring(value)
	end

	if kind == "EnumItem" then
		return tostring(value)
	end

	local function call(name, values)
		local parts = {}
		for _, v in values do
			table.insert(parts, Codec.encode(v, seen, depth, compact))
		end

		return name .. "(" .. table.concat(parts, ", ") .. ")"
	end

	if kind == "CFrame" then
		return call("CFrame.new", { value:GetComponents() })
	end

	if kind == "Vector3" then
		return call("Vector3.new", { value.X, value.Y, value.Z })
	end

	if kind == "Vector2" then
		return call("Vector2.new", { value.X, value.Y })
	end

	if kind == "Color3" then
		return call("Color3.new", { value.R, value.G, value.B })
	end

	if kind == "NumberRange" then
		return call("NumberRange.new", { value.Min, value.Max })
	end

	if kind == "UDim" then
		return call("UDim.new", { value.Scale, value.Offset })
	end

	if kind == "UDim2" then
		return call("UDim2.new", { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset })
	end

	if kind == "Rect" then
		return call("Rect.new", { value.Min, value.Max })
	end

	if kind == "BrickColor" then
		return call("BrickColor.new", { value.Number })
	end

	if kind == "ColorSequenceKeypoint" then
		return call("ColorSequenceKeypoint.new", { value.Time, value.Value })
	end

	if kind == "NumberSequenceKeypoint" then
		return call("NumberSequenceKeypoint.new", { value.Time, value.Value, value.Envelope })
	end

	if kind == "ColorSequence" or kind == "NumberSequence" then
		return call(kind .. ".new", { value.Keypoints })
	end

	if kind == "Font" then
		return call("Font.new", { value.Family, value.Weight, value.Style })
	end

	if kind == "Content" then
		assert(
			value.SourceType == Enum.ContentSourceType.Uri,
			"Editable asset content must be published before export"
		)
		return call("Content.fromUri", { value.Uri })
	end

	assert(kind == "table", "Cannot serialize " .. kind)
	seen = seen or {}
	assert(not seen[value], "Cyclic export data")
	seen[value] = true
	depth = depth or 0
	local indent = string.rep("\t", depth + 1)
	local rows = {}
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
			return a < b
		end

		return Codec.encode(a) < Codec.encode(b)
	end)
	if compact and #keys > 0 and #keys == #value then
		local array = true
		for i, key in keys do
			if key ~= i then
				array = false
				break
			end
		end
		if array then
			local flat = true
			for i, item in value do
				rows[i] = Codec.encode(item, seen, depth + 1, compact)
				if type(item) == "table" or rows[i]:find("\n", 1, true) then
					flat = false
				end
			end
			seen[value] = nil
			if flat then
				return "{ " .. table.concat(rows, ", ") .. " }"
			end
			return "{\n" .. indent .. table.concat(rows, ",\n" .. indent) .. ",\n" .. string.rep("\t", depth) .. "}"
		end
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
	for _, key in keys do
		local name = type(key) == "string"
				and key:match("^[%a_][%w_]*$")
				and not keywords[key]
				and key
			or "[" .. Codec.encode(key, seen, depth + 1, compact) .. "]"
		table.insert(
			rows,
			indent .. name .. " = " .. Codec.encode(value[key], seen, depth + 1, compact) .. ","
		)
	end

	seen[value] = nil
	if #rows == 0 then
		return "{}"
	end

	return "{\n" .. table.concat(rows, "\n") .. "\n" .. string.rep("\t", depth) .. "}"
end

function Codec.path(object)
	local path = {}
	while object and object ~= game do
		local parent = object.Parent
		assert(parent, "Object is not in the place: " .. object.Name)
		table.insert(path, 1, object.Name)
		object = parent
	end

	return path
end

function Codec.selector(object)
	local path = {}
	while object and object ~= game do
		assert(object.Parent, "Object is not in the place: " .. object.Name)
		table.insert(path, 1, {
			Name = object.Name,
			Class = object.ClassName,
			TrackId = object:GetAttribute("EclipseTrackId"),
		})
		object = object.Parent
	end

	return path
end

return Codec
