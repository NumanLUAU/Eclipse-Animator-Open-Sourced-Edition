--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = {}

function Data.copy(rows)
	local out = {}
	for _, row in type(rows) == "table" and rows or {} do
		if
			type(row) == "table"
			and (row.Mode == "All" or row.Mode == "Selected" or row.Mode == "Exact")
			and type(row.Path) == "table"
		then
			local path = {}
			local valid = #row.Path <= 128
			for _, step in row.Path do
				if
					type(step) ~= "table"
					or type(step.Name) ~= "string"
					or type(step.Class) ~= "string"
					or type(step.Index) ~= "number"
					or step.Index < 1
					or step.Index % 1 ~= 0
				then
					valid = false
					break
				end

				table.insert(path, { Name = step.Name, Class = step.Class, Index = step.Index })
			end

			if valid then
				local action = row.Action
				if
					action == nil
					or action == "Emit"
					or action == "Enable"
					or action == "Disable"
				then
					local count = tonumber(row.Count)
					if count and (count ~= count or math.abs(count) == math.huge) then count = nil end
					table.insert(out, { Mode = row.Mode, Path = path, Action = action, Count = count and math.clamp(math.floor(count), 0, 100000) })
				end
			end
		end
	end

	return out
end

function Data.path(root, target)
	local path = {}
	local cursor = target
	while cursor ~= root do
		if not cursor or not cursor.Parent then
			return nil
		end

		local index = 0
		for _, child in cursor.Parent:GetChildren() do
			if child.Name == cursor.Name and child.ClassName == cursor.ClassName then
				index += 1
			end

			if child == cursor then
				break
			end
		end

		table.insert(path, 1, { Name = cursor.Name, Class = cursor.ClassName, Index = index })
		cursor = cursor.Parent
	end

	return path
end

function Data.resolve(root, path)
	local cursor = root
	for _, step in path do
		local count = 0
		local found
		for _, child in cursor:GetChildren() do
			if child.Name == step.Name and child.ClassName == step.Class then
				count += 1
				if count == step.Index then
					found = child
					break
				end
			end
		end

		if not found then
			return nil
		end

		cursor = found
	end

	return cursor
end

function Data.id(path)
	return game:GetService("HttpService"):JSONEncode(path)
end

return Data
