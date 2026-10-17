--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Http = game:GetService("HttpService")
local Document = {}
local omitted = {
	Motor = true,
	Part = true,
	Button = true,
	Template = true,
	SanitizeName = true,
	_EclipseRawStored = true,
	_EclipseRawChannels = true,
}

local function encode(value, depth)
	depth = depth or 0
	assert(depth < 40, "Live data is too deeply nested")
	local kind = typeof(value)
	if kind == "CFrame" or kind == "Vector3" then
		local parts = kind == "CFrame" and { value:GetComponents() }
			or { value.X, value.Y, value.Z }
		for _, number in parts do
			assert(number == number and math.abs(number) < math.huge, "Invalid Live transform")
		end

		return { t = kind == "CFrame" and "cf" or "v3", v = parts }
	end

	if kind == "Color3" or kind == "Vector2" or kind == "NumberRange" then
		local parts = kind == "Color3" and { value.R, value.G, value.B }
			or kind == "Vector2" and { value.X, value.Y }
			or { value.Min, value.Max }
		for _, v in parts do
			assert(v == v and math.abs(v) < math.huge, "Invalid property number")
		end

		return { t = kind, v = parts }
	end

	if kind == "UDim" then
		return { t = kind, v = { encode(value.Scale), encode(value.Offset) } }
	end

	if kind == "UDim2" then
		return {
			t = kind,
			v = {
				encode(value.X.Scale),
				encode(value.X.Offset),
				encode(value.Y.Scale),
				encode(value.Y.Offset),
			},
		}
	end

	if kind == "Rect" then
		return {
			t = kind,
			v = {
				encode(value.Min.X),
				encode(value.Min.Y),
				encode(value.Max.X),
				encode(value.Max.Y),
			},
		}
	end

	if kind == "BrickColor" then
		return { t = kind, v = value.Number }
	end

	if kind == "NumberSequence" or kind == "ColorSequence" then
		local keys = {}
		for _, key in value.Keypoints do
			table.insert(keys, {
				encode(key.Time),
				encode(key.Value),
				kind == "NumberSequence" and encode(key.Envelope) or nil,
			})
		end

		return { t = kind, v = keys }
	end

	if kind == "EnumItem" then
		return { t = "enum", e = tostring(value.EnumType):gsub("Enum%.", ""), v = value.Name }
	end

	if kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "Invalid Live number")
		return value
	end

	if kind == "string" or kind == "boolean" then
		return value
	end

	if kind ~= "table" then
		return nil
	end

	local keys, entries = {}, {}
	for key in value do
		if not omitted[key] and (type(key) == "number" or type(key) == "string") then
			table.insert(keys, key)
		end
	end

	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then
			return type(a) < type(b)
		end

		return a < b
	end)
	for _, key in keys do
		local item = encode(value[key], depth + 1)
		if item ~= nil then
			table.insert(entries, { key, item })
		end
	end

	return { t = "table", v = entries }
end

local function decode(value, depth, budget)
	depth = depth or 0
	assert(depth < 40, "Invalid Live nesting")
	if type(value) ~= "table" then
		if type(value) == "number" then
			assert(value == value and math.abs(value) < math.huge, "Invalid Live number")
		end

		return value
	end

	if value.t == "cf" then
		assert(#value.v == 12)
		for _, v in value.v do
			assert(
				type(v) == "number" and v == v and math.abs(v) < math.huge,
				"Invalid Live transform"
			)
		end

		return CFrame.new(table.unpack(value.v))
	end

	if value.t == "v3" then
		assert(#value.v == 3)
		for _, v in value.v do
			assert(
				type(v) == "number" and v == v and math.abs(v) < math.huge,
				"Invalid Live vector"
			)
		end

		return Vector3.new(table.unpack(value.v))
	end

	if value.t == "Color3" then
		return Color3.new(table.unpack(value.v))
	end

	if value.t == "Vector2" then
		return Vector2.new(table.unpack(value.v))
	end

	if value.t == "NumberRange" then
		return NumberRange.new(table.unpack(value.v))
	end

	if value.t == "UDim" then
		return UDim.new(table.unpack(value.v))
	end

	if value.t == "UDim2" then
		return UDim2.new(table.unpack(value.v))
	end

	if value.t == "Rect" then
		return Rect.new(table.unpack(value.v))
	end

	if value.t == "BrickColor" then
		return BrickColor.new(value.v)
	end

	if value.t == "NumberSequence" or value.t == "ColorSequence" then
		local keys = {}
		for _, key in value.v do
			table.insert(
				keys,
				value.t == "NumberSequence"
						and NumberSequenceKeypoint.new(
							decode(key[1]),
							decode(key[2]),
							decode(key[3])
						)
					or ColorSequenceKeypoint.new(decode(key[1]), decode(key[2]))
			)
		end

		return value.t == "NumberSequence" and NumberSequence.new(keys) or ColorSequence.new(keys)
	end

	if value.t == "enum" then
		return Enum[value.e][value.v]
	end

	assert(value.t == "table" and type(value.v) == "table", "Invalid Live value")
	local result = {}
	for _, entry in value.v do
		assert(type(entry[1]) == "number" or type(entry[1]) == "string")
		result[entry[1]] = decode(entry[2], depth + 1, budget)
		if budget then
			budget()
		end
	end

	return result
end

function Document.pack(value)
	return Http:JSONEncode(encode(value))
end

function Document.unpack(value)
	assert(type(value) == "string" and #value <= 4000000, "Invalid Live payload")
	local result = decode(Http:JSONDecode(value))
	return result
end

function Document.unpackArchive(value, budget)
	assert(type(value) == "string" and #value <= 64000000, "Invalid animation archive")
	return decode(require("ChunkStore").decodeJson(value, budget), nil, budget)
end

function Document.packKey(key)
	local data = table.clone(key)
	local mask = 0
	if typeof(key.C0) == "CFrame" then
		if key.Position == key.C0.Position then
			data.Position = nil
			mask += 1
		end

		if key.Rotation == key.C0.Rotation then
			data.Rotation = nil
			mask += 2
		end

		if key.ChannelPoseC0 == key.C0 then
			data.ChannelPoseC0 = nil
			mask += 4
		end
	end

	data.Frame = nil
	data.Time = nil
	if mask > 0 then
		data._liveDerived = mask
	end

	return Document.pack(data)
end

function Document.unpackKey(value, encoded)
	local data = encoded and decode(encoded) or Document.unpack(value)
	local mask = data._liveDerived
	if mask then
		assert(type(mask) == "number" and typeof(data.C0) == "CFrame", "Invalid Live key")
		if bit32.band(mask, 1) ~= 0 then
			data.Position = data.C0.Position
		end

		if bit32.band(mask, 2) ~= 0 then
			data.Rotation = data.C0.Rotation
		end

		if bit32.band(mask, 4) ~= 0 then
			data.ChannelPoseC0 = data.C0
		end

		data._liveDerived = nil
	end

	return data
end

function Document.unpackKeys(values, budget)
	local result, ids, pieces = {}, {}, {}
	local bytes = 2

	local function flush()
		if #ids == 0 then
			return
		end

		local decoded = Http:JSONDecode("[" .. table.concat(pieces, ",") .. "]")
		assert(#decoded == #ids, "Invalid Live key batch")
		for i, id in ids do
			result[id] = Document.unpackKey(values[id], decoded[i])
			if budget then
				budget()
			end
		end

		ids, pieces = {}, {}
		bytes = 2
	end

	for id, value in values do
		assert(type(value) == "string" and #value <= 4000000, "Invalid Live payload")
		if #ids >= 256 or bytes + #value > 150000 then
			flush()
		end

		table.insert(ids, id)
		table.insert(pieces, value)
		bytes += #value + 1
	end

	flush()
	return result
end

function Document.new(author, seed)
	local self = {
		author = author,
		clock = 0,
		registers = {},
		published = {},
		dirty = {},
		observed = table.clone(seed or {}),
	}
	for key, value in seed or {} do
		self.registers[key] = { n = 0, a = "", v = value }
	end

	function self:edit(nextValues)
		local keys = {}
		for key in self.observed do
			keys[key] = true
		end

		for key in nextValues do
			keys[key] = true
		end

		local changed = false
		for key in keys do
			if nextValues[key] ~= self.observed[key] then
				self.clock += 1
				local register = { n = self.clock, a = self.author, v = nextValues[key] or false }
				self.registers[key], self.published[key] = register, register
				self.dirty[key] = true
				changed = true
			end
		end

		self.observed = table.clone(nextValues)
		return changed
	end

	function self:merge(records)
		local changed, conflicts = false, 0
		for key, incoming in records do
			assert(
				type(key) == "string" and type(incoming) == "table" and type(incoming.a) == "string"
			)
			assert(
				type(incoming.n) == "number"
					and incoming.n >= 0
					and incoming.n % 1 == 0
					and incoming.n < 1e12
			)
			assert(incoming.v == false or type(incoming.v) == "string")
		end

		for key, incoming in records do
			self.clock = math.max(self.clock, incoming.n)
			local old = self.registers[key]
			if not old or incoming.n > old.n or incoming.n == old.n and incoming.a > old.a then
				if old and old.a == self.author and old.v ~= incoming.v then
					conflicts += 1
				end

				self.registers[key] = incoming
				changed = true
			end
		end

		return changed, conflicts
	end

	function self:values()
		local values = {}
		for key, register in self.registers do
			if register.v ~= false then
				values[key] = register.v
			end
		end

		return values
	end

	return self
end

local Chunks = require("ChunkStore")
local wire = setmetatable({}, { __mode = "k" })
local receivedPages = setmetatable({}, { __mode = "k" })

local function shard(key)
	local n = 0
	for i = 1, #key do
		n = (n * 31 + key:byte(i)) % 64
	end

	return tostring(n)
end

function Document.publish(peer, records, dirty, budget)
	local previous = wire[peer] or { shards = {}, index = {} }
	local shards = table.clone(previous.shards)
	local touched = {}
	for key in dirty or records do
		local id = shard(key)
		if not touched[id] then
			shards[id] = table.clone(shards[id] or {})
			touched[id] = true
		end

		shards[id][key] = records[key]
	end

	local revision = (peer:GetAttribute("Revision") or 0) + 1
	local index = table.clone(previous.index)
	local staged = {}
	local retired = {}
	local ok, err = xpcall(function()
		for id in touched do
			local names = {}
			local pieces = {}
			local bytes = 2

			local function flush()
				if #pieces == 0 then
					return
				end

				local text = "{" .. table.concat(pieces, ",") .. "}"
				local name = "Page" .. id .. "_" .. revision .. "_" .. (#names + 1)
				local folder = Chunks.write(nil, name, text)
				folder:SetAttribute("Bytes", #text)
				folder:SetAttribute("Chunks", #folder:GetChildren())
				table.insert(staged, folder)
				table.insert(names, name)
				pieces = {}
				bytes = 2
			end

			for key, record in shards[id] do
				local piece = Http:JSONEncode(key) .. ":" .. Http:JSONEncode(record)
				if bytes + #piece > 400000 then
					flush()
				end

				table.insert(pieces, piece)
				bytes += #piece + 1
				if budget then
					budget()
				end
			end

			flush()
			for _, name in index[id] or {} do
				table.insert(retired, name)
			end

			index[id] = names
		end

		for _, folder in staged do
			folder.Parent = peer
		end

		peer:SetAttribute("Manifest", Http:JSONEncode(index))
		peer:SetAttribute("Revision", revision)
	end, debug.traceback)
	if not ok then
		for _, folder in staged do
			folder:Destroy()
		end

		error(err, 0)
	end

	wire[peer] = { shards = shards, index = index }
	for _, name in retired do
		local old = peer:FindFirstChild(name)
		if old then
			task.delay(2, function()
				old:Destroy()
			end)
		end
	end

	return revision
end

function Document.receive(peer, previous, budget)
	local manifest = peer:GetAttribute("Manifest")
	if not manifest or previous and previous.text == manifest then
		return nil
	end

	local index = Http:JSONDecode(manifest)
	local records = {}
	local pages = receivedPages[peer] or {}
	local retained = {}
	for _, names in index do
		for _, name in names do
			retained[name] = pages[name]
		end
	end

	pages = retained
	receivedPages[peer] = pages
	for id, names in index do
		local old = previous and previous.index[id]
		local equal = old and #old == #names
		if equal then
			for i, name in names do
				if old[i] ~= name then
					equal = false
					break
				end
			end
		end

		if not equal then
			for _, name in names do
				local decoded = pages[name]
				if not decoded then
					local folder = peer:FindFirstChild(name)
					if not folder or #folder:GetChildren() ~= folder:GetAttribute("Chunks") then
						return nil
					end

					local text = Chunks.read(folder)
					if #text ~= folder:GetAttribute("Bytes") then
						return nil
					end

					decoded = Http:JSONDecode(text)
					pages[name] = decoded
					if budget then
						budget()
					end
				end

				for key, record in decoded do
					records[key] = record
				end
			end
		end
	end

	if peer:GetAttribute("Manifest") ~= manifest then
		return nil
	end

	return records, { text = manifest, index = index }
end

function Document.equal(a, b)
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end

	for k in b do
		if a[k] == nil then
			return false
		end
	end

	return true
end

return Document
