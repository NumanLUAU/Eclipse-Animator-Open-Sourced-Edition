--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local HttpService = game:GetService("HttpService")
local Legacy = {}

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function document(source, name)
	if typeof(source) ~= "Instance" or not source:IsA("Folder") or source.Name ~= name then
		return
	end

	local item = source.Parent
	local save = item and item.Parent
	if
		not item
		or not item:IsA("Folder")
		or not tonumber(item.Name)
		or not save
		or not save:IsA("StringValue")
	then
		return
	end

	local ok, data = pcall(HttpService.JSONDecode, HttpService, save.Value)
	if
		not ok
		or type(data) ~= "table"
		or type(data.Information) ~= "table"
		or type(data.Items) ~= "table"
	then
		return
	end

	const entry = data.Items[tonumber(item.Name)]
	if not entry then
		return
	end

	return data, entry
end

local function information(source)
	const data = document(source, "MarkerTrack")
	return data and data.Information
end

function Legacy.isEmitTrack(source)
	return document(source, "Emit") ~= nil
end

function Legacy.isTrack(source)
	return information(source) ~= nil or Legacy.isEmitTrack(source)
end

local function text(folder, name, fallback)
	local value = folder:FindFirstChild(name)
	return value and value:IsA("StringValue") and value.Value or fallback or ""
end

local function enabled(folder)
	local flag = folder:FindFirstChild("Enabled") or folder:FindFirstChild("enabled")
	return not flag or not flag:IsA("BoolValue") or flag.Value
end

function Legacy.read(source, fps)
	local info = information(source)
	if not info then
		return
	end

	local sourceFPS = tonumber(info.FPS or info.FramesPerSecond) or 60
	if not finite(sourceFPS) or sourceFPS <= 0 then
		sourceFPS = 60
	end

	fps = finite(fps) and fps > 0 and fps or 60
	local result = {}
	local folders = source:GetChildren()
	table.sort(folders, function(a, b)
		return (tonumber(a.Name) or math.huge) < (tonumber(b.Name) or math.huge)
	end)
	for _, folder in folders do
		local frame = tonumber(folder.Name)
		local width = folder:FindFirstChild("width")
		if
			not folder:IsA("Folder")
			or not finite(frame)
			or frame < 0
			or not width
			or not (width:IsA("IntValue") or width:IsA("NumberValue"))
		then
			continue
		end

		local duration = finite(width.Value) and math.max(0, width.Value) or 0
		local base = {
			Frame = math.floor(frame * fps / sourceFPS + 0.5),
			Duration = math.floor(duration * fps / sourceFPS + 0.5),
			Name = text(folder, "name", "Event"),
			Parameter = "",
			Enabled = enabled(source) and enabled(folder),
			CodeBegin = text(folder, "codeBegin"),
			CodeEnd = text(folder, "codeEnd"),
		}
		local markers = folder:FindFirstChild("KFMarkers")
		local values = markers and markers:GetChildren() or {}
		table.sort(values, function(a, b)
			return (tonumber(a.Name) or math.huge) < (tonumber(b.Name) or math.huge)
		end)
		base.Markers = {}
		for _, marker in values do
			if not marker:IsA("StringValue") then
				continue
			end

			table.insert(base.Markers, { Name = marker.Value, Parameter = text(marker, "Val") })
		end

		if base.Markers[1] then
			base.Name = base.Markers[1].Name
			base.Parameter = base.Markers[1].Parameter
		end

		table.insert(result, base)
	end

	return result
end

function Legacy.fingerprint(event)
	local markers = {}
	for _, marker in event.Markers or { { Name = event.Name, Parameter = event.Parameter } } do
		table.insert(markers, { marker.Name, marker.Parameter })
	end

	return HttpService:JSONEncode({
		event.Frame,
		event.Duration,
		markers,
		event.Enabled,
		event.CodeBegin,
		event.CodeEnd,
	})
end

return Legacy
