--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = {}
local CHUNK = 150000

function Data.read(value)
	if value:IsA("StringValue") then
		return value.Value
	end

	local chunks = value:GetChildren()
	table.sort(chunks, function(a, b)
		return a.Name < b.Name
	end)
	local text = table.create(#chunks)
	for i, chunk in chunks do
		assert(chunk:IsA("StringValue"), "Invalid armature data chunk")
		text[i] = chunk.Value
	end

	return table.concat(text)
end

function Data.write(parent, name, text)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("Encoding", "json-chunks-v1")
	local written = 0
	for start = 1, #text, CHUNK do
		local chunk = Instance.new("StringValue")
		chunk.Name = string.format("%06d", math.floor((start - 1) / CHUNK) + 1)
		const part = text:sub(start, start + CHUNK - 1)
		chunk.Value = part
		if chunk.Value ~= part then
			folder:Destroy()
			error("Saved data for " .. name .. " could not be verified; the previous save was kept.", 0)
		end

		written += #part
		chunk.Parent = folder
		local step = require("State").ProjectWorkStep
		if step then
			step()
		end
	end

	if written ~= #text then
		folder:Destroy()
		error("Saved data for " .. name .. " is incomplete; the previous save was kept.", 0)
	end

	folder.Parent = parent
	return folder
end

function Data.decodeJson(text, budget, skipTrackKeys)
	local Http = game:GetService("HttpService")
	assert(type(text) == "string" and #text <= 64000000, "Invalid animation archive")

	if not skipTrackKeys and #text <= 8 * 1024 * 1024 then
		if budget then
			budget()
		end

		local decoded = Http:JSONDecode(text)
		if budget then
			budget()
		end

		return decoded
	end

	local at, length, depth = 1, #text, 0
	local escapes = {
		['"'] = '"',
		["\\"] = "\\",
		["/"] = "/",
		n = "\n",
		r = "\r",
		t = "\t",
		b = "\b",
		f = "\f",
	}
	local parse
	local parsed = 0

	local function whitespace()
		local _, last = text:find("^[ \t\r\n]*", at)
		at = (last or at - 1) + 1
	end

	local function stringValue()
		local first = at
		at += 1
		local content = at
		while true do
			local stop = text:find('["\\%z\1-\31]', at)
			assert(stop, "Unterminated JSON string")
			local byte = text:byte(stop)
			if byte == 34 then
				at = stop + 1
				if content == first + 1 then
					return text:sub(content, stop - 1)
				end

				local encoded = text:sub(first + 1, stop - 1)
				if encoded:find("\\u", 1, true) then
					return Http:JSONDecode(text:sub(first, stop))
				end

				return (
					encoded:gsub("\\(.)", function(char)
						return assert(escapes[char], "Invalid JSON escape")
					end)
				)
			elseif byte == 92 then
				at = stop + 2
				content = 0
			else
				error("Control character in JSON string")
			end
		end
	end

	local function skipArray()
		whitespace()
		assert(text:byte(at) == 91, "Invalid archived keys")
		local stack = { 93 }
		at += 1
		local tokens = 0
		while #stack > 0 do
			local stop = text:find('[%[%]{}"]', at)
			assert(stop, "Unterminated archived keys")
			local char = text:byte(stop)
			at = stop + 1
			if char == 34 then
				while true do
					local ending = text:find('["\\%z\1-\31]', at)
					assert(ending, "Unterminated archived string")
					local value = text:byte(ending)
					if value == 34 then
						at = ending + 1
						break
					end

					assert(value == 92, "Control character in archived string")
					at = ending + 2
				end
			elseif char == 91 then
				table.insert(stack, 93)
			elseif char == 123 then
				table.insert(stack, 125)
			else
				assert(char == table.remove(stack), "Unbalanced archived keys")
			end

			tokens += 1
			if budget and tokens % 128 == 0 then
				budget()
			end
		end
	end

	parse = function()
		parsed += 1
		if budget and parsed % 128 == 0 then
			budget()
		end

		whitespace()
		local byte = text:byte(at)
		if byte == 34 then
			return stringValue()
		end

		if byte == 123 or byte == 91 then
			depth += 1
			assert(depth <= 128, "Animation archive is too deeply nested")
			local object = byte == 123
			local close = object and 125 or 93
			local out = {}
			local index = 1
			at += 1
			whitespace()
			if text:byte(at) == close then
				at += 1
				depth -= 1
				return out
			end

			while true do
				local key = index
				if object then
					whitespace()
					assert(text:byte(at) == 34, "Invalid JSON object key")
					key = stringValue()
					whitespace()
					assert(text:byte(at) == 58, "Missing JSON colon")
					at += 1
				end

				if skipTrackKeys and object and depth == 3 and key == "keys" then
					skipArray()
					out[key] = {}
				else
					out[key] = parse()
				end

				index += 1
				whitespace()
				byte = text:byte(at)
				at += 1
				if byte == close then
					break
				end

				assert(byte == 44, "Missing JSON separator")
			end

			depth -= 1
			return out
		end

		if byte == 116 and text:sub(at, at + 3) == "true" then
			at += 4
			return true
		end

		if byte == 102 and text:sub(at, at + 4) == "false" then
			at += 5
			return false
		end

		if byte == 110 and text:sub(at, at + 3) == "null" then
			at += 4
			return nil
		end

		local first = at
		if byte == 45 then
			at += 1
		end

		if text:byte(at) == 48 then
			at += 1
		else
			local a, b = text:find("^[1-9]%d*", at)
			assert(a, "Invalid JSON value")
			at = b + 1
		end

		if text:byte(at) == 46 then
			at += 1
			local a, b = text:find("^%d+", at)
			assert(a, "Invalid JSON fraction")
			at = b + 1
		end

		byte = text:byte(at)
		if byte == 69 or byte == 101 then
			at += 1
			byte = text:byte(at)
			if byte == 43 or byte == 45 then
				at += 1
			end

			local a, b = text:find("^%d+", at)
			assert(a, "Invalid JSON exponent")
			at = b + 1
		end

		local value = tonumber(text:sub(first, at - 1))
		assert(value, "Invalid JSON number")
		return value
	end

	local result = parse()
	whitespace()
	assert(at == length + 1, "Trailing JSON data")
	return result
end

return Data
