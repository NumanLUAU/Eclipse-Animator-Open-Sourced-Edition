--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Dependencies = {}

local function stringLiteral(raw)
	local quote = raw:sub(1, 1)
	if (quote ~= '"' and quote ~= "'") or raw:sub(-1) ~= quote then
		return nil
	end

	local out, index, last = {}, 2, #raw - 1
	local escapes = {
		a = "\a",
		b = "\b",
		f = "\f",
		n = "\n",
		r = "\r",
		t = "\t",
		v = "\v",
		["\\"] = "\\",
		['"'] = '"',
		["'"] = "'",
	}
	while index <= last do
		local ch = raw:sub(index, index)
		if ch ~= "\\" then
			if ch == quote or ch == "\n" or ch == "\r" then
				return nil
			end

			table.insert(out, ch)
			index += 1
		else
			index += 1
			local escape = raw:sub(index, index)
			if escapes[escape] then
				table.insert(out, escapes[escape])
				index += 1
			elseif escape == "z" then
				index += 1
				while index <= last and raw:sub(index, index):match("%s") do
					index += 1
				end
			elseif escape == "x" then
				local hex = raw:sub(index + 1, index + 2)
				if #hex ~= 2 or not hex:match("^%x%x$") or index + 2 > last then
					return nil
				end

				table.insert(out, string.char(tonumber(hex, 16)))
				index += 3
			elseif escape == "u" then
				local hex = raw:sub(index + 1):match("^%{(%x+)%}")
				if not hex or #hex > 6 then
					return nil
				end

				local code = tonumber(hex, 16)
				if code > 0x10ffff or (code >= 0xd800 and code <= 0xdfff) then
					return nil
				end

				table.insert(out, utf8.char(code))
				index += #hex + 3
			elseif escape:match("%d") then
				local digits = raw:sub(index, last):match("^%d%d?%d?")
				local code = tonumber(digits)
				if code > 255 then
					return nil
				end

				table.insert(out, string.char(code))
				index += #digits
			elseif escape == "\n" or escape == "\r" then
				table.insert(out, "\n")
				index += 1
				if escape == "\r" and raw:sub(index, index) == "\n" then
					index += 1
				end
			else
				return nil
			end
		end
	end

	return table.concat(out)
end

local function tokens(source)
	local out = {}
	local i = 1
	while i <= #source do
		local ch = source:sub(i, i)
		if ch:match("%s") then
			i += 1
		elseif source:sub(i, i + 1) == "--" then
			local eq = source:sub(i + 2):match("^%[(=*)%[")
			if eq then
				local finish = source:find("]" .. eq .. "]", i + 4 + #eq, true)
				i = finish and finish + 2 + #eq or #source + 1
			else
				i = (source:find("\n", i + 2, true) or #source) + 1
			end
		elseif ch == '"' or ch == "'" then
			local first = i
			i += 1
			while i <= #source do
				local c = source:sub(i, i)
				if c == "\\" then
					i += 2
				elseif c == ch then
					i += 1
					break
				else
					i += 1
				end
			end

			local raw = source:sub(first, i - 1)
			local literal = stringLiteral(raw)
			table.insert(out, { kind = "string", value = literal or "" })
		else
			local eq = source:sub(i):match("^%[(=*)%[")
			if eq then
				local first = i + 2 + #eq
				local finish = source:find("]" .. eq .. "]", first, true)
				table.insert(
					out,
					{ kind = "string", value = source:sub(first, finish and finish - 1 or #source) }
				)
				i = finish and finish + 2 + #eq or #source + 1
			else
				local word = source:sub(i):match("^[%a_][%w_]*")
				if word then
					table.insert(out, { kind = "name", value = word })
					i += #word
				else
					table.insert(
						out,
						{ kind = ch:match("%d") and "number" or "symbol", value = ch }
					)
					i += 1
				end
			end
		end
	end

	return out
end

function Dependencies.scan(source, context)
	local list = tokens(source)
	local aliases = {
		game = game,
		Game = game,
		workspace = workspace,
		Workspace = workspace,
		rig = context.Rig,
		script = context.Script,
	}
	local found, seen = {}, {}

	local function add(object)
		if
			typeof(object) ~= "Instance"
			or object.Parent == game
			or object == game
			or object == workspace.CurrentCamera
			or object:IsA("Terrain")
		then
			return
		end

		if
			not (
				object:IsDescendantOf(workspace)
				or object:IsDescendantOf(game:GetService("ReplicatedStorage"))
				or object:IsDescendantOf(game:GetService("Lighting"))
				or object:IsDescendantOf(game:GetService("SoundService"))
			)
		then
			return
		end

		if
			object:IsA("ParticleEmitter")
			or object:IsA("Beam")
			or object:IsA("Trail")
			or object:IsA("Attachment")
		then
			local parent = object.Parent
			while parent and parent ~= workspace do
				if parent:IsA("BasePart") then
					object = parent
					break
				end

				parent = parent.Parent
			end
		end

		if not seen[object] then
			seen[object] = true
			table.insert(found, object)
		end
	end

	local function value(index)
		return list[index] and list[index].value
	end

	local function parse(index)
		local object = aliases[value(index)]
		if not object then
			return nil, index
		end

		local cursor = index + 1
		while object do
			local key
			local nextIndex
			if value(cursor) == "." and list[cursor + 1] and list[cursor + 1].kind == "name" then
				key = value(cursor + 1)
				nextIndex = cursor + 2
			elseif
				value(cursor) == "["
				and list[cursor + 1]
				and list[cursor + 1].kind == "string"
				and value(cursor + 2) == "]"
			then
				key = value(cursor + 1)
				nextIndex = cursor + 3
			elseif
				value(cursor) == ":"
				and value(cursor + 2) == "("
				and list[cursor + 3]
				and list[cursor + 3].kind == "string"
			then
				local method, name = value(cursor + 1), value(cursor + 3)
				local target
				if value(cursor + 4) ~= ")" then
					break
				end

				if method == "GetService" and object == game then
					local ok, result = pcall(game.GetService, game, name)
					target = ok and result or nil
				elseif method == "WaitForChild" or method == "FindFirstChild" then
					target = object:FindFirstChild(name)
				else
					break
				end

				if not target then
					break
				end

				object = target
				cursor += 5
				continue
			else
				break
			end

			local ok, result = pcall(function()
				return object[key]
			end)
			if not ok or typeof(result) ~= "Instance" then
				break
			end

			object = result
			cursor = nextIndex
		end

		return object, cursor
	end

	for index, token in list do
		if
			token.value == "require"
			and value(index + 1) == "("
			and list[index + 2]
			and list[index + 2].kind == "string"
			and context.Script
		then
			local path = value(index + 2)
			if path:sub(1, 1) == "." then
				local target = context.Script.Parent
				for name in path:gmatch("[^/]+") do
					if not target then
						break
					end

					if name == ".." then
						target = target.Parent
					elseif name ~= "." then
						target = target:FindFirstChild(name)
					end
				end

				add(target)
			end
		end

		if
			token.kind == "name"
			and aliases[token.value]
			and value(index - 1) ~= "."
			and value(index - 1) ~= ":"
		then
			local object = parse(index)
			add(object)
		end

		if token.kind == "name" and value(index + 1) == "=" then
			local object = parse(index + 2)
			if object then
				aliases[token.value] = object
				add(object)
			end
		end
	end

	return found
end

Dependencies.tokens = tokens
return Dependencies
