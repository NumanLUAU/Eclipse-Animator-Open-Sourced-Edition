--!nocheck
--// cracked by numan

return function(require)
	local ContentProvider = game:GetService("ContentProvider")
	local Run = game:GetService("RunService")
	local Preload = {}
	local cache = setmetatable({}, { __mode = "k" })

	function Preload.collect(package, data, temporary)
		temporary = temporary or {}
		local targets, seen, visited, fonts = {}, {}, {}, {}
		local function add(value)
			if value ~= "" and not seen[value] then
				seen[value] = true
				table.insert(targets, value)
			end
		end
		local function font(name)
			if fonts[name] then
				return
			end
			fonts[name] = true
			local ok, face = pcall(function()
				return name == "RobotoMono"
						and Font.new("rbxasset://fonts/families/RobotoMono.json")
					or Font.fromEnum(Enum.Font[name])
			end)
			if not ok then
				return
			end
			for _, weight in { Enum.FontWeight.Regular, Enum.FontWeight.Bold } do
				for _, style in { Enum.FontStyle.Normal, Enum.FontStyle.Italic } do
					local label = Instance.new("TextLabel")

					label.FontFace = Font.new(face.Family, weight, style)
					label.Text = "Aa"
					table.insert(temporary, label)
					add(label)
				end
			end
		end
		local function scan(value, key)
			local kind = typeof(value)
			if kind == "string" then
				if
					value:match("^rbxassetid://%d+$")
					or value:match("^rbxasset://")
					or value:match("^rbxthumb://")
					or (value:match("^https?://[%w%.%-]*roblox%.com/") and value:find("[?&]id=%d+"))
				then
					add(value)
				elseif
					(
						key == "Image"
						or key == "AudioId"
						or key == "SoundId"
						or key == "TextureId"
						or key == "MeshId"
						or key == "AnimationId"
					) and value:match("^%d+$")
				then
					add("rbxassetid://" .. value)
				elseif key == "Font" or key == "NameFont" then
					font(value)
				end
			elseif kind == "Font" then
				local label = Instance.new("TextLabel")

				label.FontFace = value
				table.insert(temporary, label)
				add(label)
			elseif kind == "Content" then
				if value.SourceType == Enum.ContentSourceType.Uri then
					add(value.Uri)
				end
			elseif kind == "table" and not visited[value] then
				visited[value] = true
				for field, child in value do
					scan(child, field)
				end
			end
		end
		for _, name in { "Scene", "Meshes" } do
			local root = package:FindFirstChild(name)
			if root then
				for _, object in root:GetDescendants() do
					if not object:IsA("LuaSourceContainer") then
						add(object)
					end
					scan(object:GetAttributes())
					for _, field in { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" } do
						local ok, value = pcall(function()
							return object[field]
						end)
						if ok then
							scan(value, field)
						end
					end
				end
			end
		end
		scan(data)
		for _, track in data.Tracks or {} do
			for _, sample in track.Samples do
				scan(sample[2], track.Property)
			end
		end
		local manifest = package:FindFirstChild("PreloadAssets")
		if manifest then
			scan(require(manifest))
		end
		return targets, temporary
	end

	function Preload.run(package, data, cancelled)
		if cancelled and cancelled() then
			return false
		end
		local job = cache[package]
		if not job then
			job = { done = false }
			cache[package] = job
			task.spawn(function()
				local temporary = {}
				local ok, message = xpcall(function()
					local targets = Preload.collect(package, data, temporary)
					local failures = {}
					ContentProvider:PreloadAsync(targets, function(id, status)
						if id ~= "" and status ~= Enum.AssetFetchStatus.Success then
							failures[id] = status.Name
						end
					end)
					local issues = {}
					for id, status in failures do
						table.insert(issues, id .. " (" .. status .. ")")
					end
					table.sort(issues)
					if #issues > 0 then
						warn(`eclipse cutscene {package.Name}: some assets could not load, check experience permissions: {table.concat(issues, ", ")}`)
					end
				end, debug.traceback)
				for _, object in temporary do
					object:Destroy()
				end
				job.ok, job.message, job.done = ok, message, true
				if not ok and cache[package] == job then
					cache[package] = nil
				end
			end)
		end
		while not job.done do
			if cancelled and cancelled() then
				return false
			end
			Run.Heartbeat:Wait()
		end
		if cancelled and cancelled() then
			return false
		end
		assert(job.ok, job.message)
		return true
	end

	return Preload
end
