--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local CoreGui = game:GetService("CoreGui")
local KoiImages = require("KoiImages")
local Sequence = require("Sequence")
local Gif = {}
local playbackMode = 1

function Gif.setPlaybackMode(mode)
	playbackMode = mode
end

local loaded = {}
local loadGeneration = 0
local targets, streams, activeStreams, lifetime = {}, {}, {}, {}
local heartbeat
local presentationTick = 0
local WARM_TRANSPARENCY = 0.99999

local function visible(object, state)
	if (state and state.opacity or object.ImageTransparency) >= 1 then
		return false
	end

	local current = object
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end

		if current:IsA("ScreenGui") and not current.Enabled then
			return false
		end

		if current:IsA("PluginGui") then
			return current.Enabled
		end

		current = current.Parent
	end

	return object:IsDescendantOf(CoreGui)
end

local function frameAt(stream, now)
	local elapsed = (now - stream.started) * 1000
	local phase = elapsed % stream.duration
	local low, high = 1, #stream.frames
	while low < high do
		local middle = math.floor((low + high) / 2)
		if phase < stream.boundaries[middle] - 1e-7 then
			high = middle
		else
			low = middle + 1
		end
	end

	return low, now + (stream.boundaries[low] - phase) / 1000
end

local function stopIfIdle()
	if heartbeat and not next(activeStreams) then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function frameLabel(image, state, id)
	local label = state.images[id]
	if label then
		return label
	end

	label = Instance.new("ImageLabel")
	label.Name = "EclipseGifFrame"
	label:SetAttribute("EclipseGifManaged", true)
	label.BackgroundTransparency = 1
	label.Active = false
	for _, key in
		{
			"Size",
			"Position",
			"AnchorPoint",
			"Rotation",
			"ScaleType",
			"SliceCenter",
			"SliceScale",
			"TileSize",
			"ImageRectOffset",
			"ImageRectSize",
			"ResampleMode",
			"ImageColor3",
		}
	do
		label[key] = image[key]
	end

	label.ZIndex = image.ZIndex + 1
	label.ImageTransparency = WARM_TRANSPARENCY
	label.Visible = true
	label.Image = KoiImages.resolve(id)
	KoiImages.crop(label, id, image)
	local corner = image:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = label
	end

	state.images[id] = label
	label.Parent = image.Parent
	return label
end

local function syncFrames(image, state)
	for id, label in state.images do
		for _, key in
			{
				"Size",
				"Position",
				"AnchorPoint",
				"Rotation",
				"ScaleType",
				"SliceCenter",
				"SliceScale",
				"TileSize",
				"ImageRectOffset",
				"ImageRectSize",
				"ResampleMode",
				"ImageColor3",
			}
		do
			label[key] = image[key]
		end

		KoiImages.crop(label, id, image)
		label.ZIndex = image.ZIndex + 1
		label.Parent = image.Parent
	end
end

local function transparency(image, state, value)
	state.writingOpacity = true
	image.ImageTransparency = value
	state.internalOpacity = image.ImageTransparency
	state.writingOpacity = false
end

local function ready(id)
	if loaded[id] then
		return true
	end

	local ok, status =
		pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, KoiImages.resolve(id))
	return ok and status == Enum.AssetFetchStatus.Success
end

local function requestFrame(image, state, index, now)
	if state.index == index or state.pending == index then
		return
	end

	if state.pending then
		return
	end

	if
		not ready(state.stream.frames[index].image)
		and now < (state.retryAt[state.stream.frames[index].image] or 0)
	then
		return
	end

	local id = state.stream.frames[index].image
	if not ready(id) and not state.loading[id] and now >= (state.retryAt[id] or 0) then
		local worker
		worker = task.defer(function()
			local image = Instance.new("ImageLabel")
			image.Image = KoiImages.resolve(id)
			state.loadObjects[image] = true
			pcall(function()
				ContentProvider:PreloadAsync({ image }, function(_, status)
					if status == Enum.AssetFetchStatus.Success then
						loaded[id] = true
					end
				end)
			end)
			state.loadObjects[image] = nil
			image:Destroy()
			state.loading[id] = nil
			state.retryAt[id] = loaded[id] and nil or os.clock() + 5
		end)
		state.loading[id] = worker
	end

	if not ready(id) then
		return
	end

	local label = frameLabel(image, state, id)
	label.ImageTransparency = label == state.front and state.opacity
		or math.max(state.opacity, WARM_TRANSPARENCY)
	label.Visible = true
	state.pending = index
	state.requestedAt = now
	state.pendingImage = label
	state.readyAfter = presentationTick + 2
end

local function present(image, state, now)
	if not state.pending or now < (state.nextAt or 0) then
		return
	end

	local target = state.pendingImage
	if not target or presentationTick < (state.readyAfter or 0) or not target.IsLoaded then
		return
	end

	target.ImageTransparency = state.opacity
	target.Visible = true
	if state.front and state.front ~= target then
		state.front.Visible = false
	end

	state.front = target
	transparency(image, state, 1)
	state.index = state.pending
	state.cursor = state.index
	state.pending = nil
	state.pendingImage = nil
	state.nextAt = now + state.stream.frames[state.index].delay / 1000
end

function Gif.step(now)
	presentationTick += 1
	now = now or os.clock()
	for stream in activeStreams do
		for image, state in stream.active do
			present(image, state, now)
			if not state.pending then
				local index = (state.cursor or state.index or 0) % #stream.frames + 1
				if #stream.frames > 1 or not state.index then
					local requested = requestFrame(image, state, index, now)
					if requested ~= false and not state.pending and now >= (state.nextAt or 0) then
						state.cursor = index
						state.nextAt = now + stream.frames[index].delay / 1000
					end
				end
			end

			if #stream.frames == 1 and state.index and not state.pending then
				stream.active[image] = nil
			end
		end

		if not next(stream.active) then
			activeStreams[stream] = nil
		end
	end

	stopIfIdle()
end

local function start()
	if heartbeat or not next(activeStreams) then
		return
	end

	heartbeat = RunService.RenderStepped:Connect(function()
		Gif.step()
	end)
end

local function refresh(image, state)
	if targets[image] ~= state then
		return
	end

	local stream = state.stream
	if visible(image, state) then
		if state.front then
			transparency(image, state, 1)
		end

		for _, label in state.images do
			label.ImageTransparency = label == state.front and state.opacity
				or math.max(state.opacity, WARM_TRANSPARENCY)
			label.Visible = label == state.front or label == state.pendingImage
		end

		local now = os.clock()
		local index = (state.cursor or state.index or 0) % #stream.frames + 1
		if not state.index then
			requestFrame(image, state, index, now)
		end

		present(image, state, now)
		if #stream.frames > 1 or state.pending or not state.index then
			stream.active[image] = state
			if not activeStreams[stream] then
				stream.index = index
			end

			activeStreams[stream] = true
		end
	else
		for _, label in state.images do
			label.Visible = false
		end

		stream.active[image] = nil
		if not next(stream.active) then
			activeStreams[stream] = nil
		end
	end

	stopIfIdle()
	start()
end

local function unbind(image)
	local state = targets[image]
	if not state then
		return
	end

	targets[image] = nil
	image:SetAttribute("EclipseGifManaged", nil)
	for _, worker in state.loading do
		pcall(task.cancel, worker)
	end

	table.clear(state.loading)
	for image in state.loadObjects do
		image:Destroy()
	end

	table.clear(state.loadObjects)
	if state.index then
		local id = state.stream.frames[state.index].image
		image.Image = KoiImages.resolve(id)
		KoiImages.crop(image, id)
	end

	for _, label in state.images do
		label:Destroy()
	end

	table.clear(state.images)
	transparency(image, state, state.opacity)
	for _, connection in state.ancestors do
		connection:Disconnect()
	end

	for _, connection in state.connections do
		connection:Disconnect()
	end

	local stream = state.stream
	stream.active[image] = nil
	stream.count -= 1
	if not next(stream.active) then
		activeStreams[stream] = nil
	end

	if stream.count == 0 then
		streams[state.signature] = nil
	end

	stopIfIdle()
end

function Gif.setTransparency(image, value)
	local state = targets[image]
	if not state then
		image.ImageTransparency = value
		return
	end

	state.opacity = value
	transparency(image, state, state.front and 1 or value)
	for _, label in state.images do
		label.ImageTransparency = label == state.front and value
			or math.max(value, WARM_TRANSPARENCY)
	end

	refresh(image, state)
end

function Gif.bind(image, rawFrames)
	local frames = rawFrames and Sequence.normalize(rawFrames)
	if not frames then
		unbind(image)
		return
	end

	local signature = Sequence.signature(frames)
	if targets[image] and targets[image].signature == signature then
		return
	end

	unbind(image)
	local stream = streams[signature]
	if not stream then
		stream = {
			frames = frames,
			started = os.clock(),
			active = {},
			count = 0,
			boundaries = {},
			duration = 0,
		}
		for index, frame in frames do
			stream.duration += frame.delay
			stream.boundaries[index] = stream.duration
		end

		streams[signature] = stream
	end

	local state = {
		signature = signature,
		stream = stream,
		ancestors = {},
		connections = {},
		opacity = image.ImageTransparency,
		loading = {},
		loadObjects = {},
		retryAt = {},
		images = {},
	}
	targets[image] = state
	image:SetAttribute("EclipseGifManaged", true)
	stream.count += 1
	transparency(image, state, 1)

	local function ancestry()
		for _, connection in state.ancestors do
			connection:Disconnect()
		end

		table.clear(state.ancestors)
		local current = image
		while current do
			local property = current:IsA("GuiObject") and "Visible"
				or ((current:IsA("ScreenGui") or current:IsA("PluginGui")) and "Enabled")
			if property then
				table.insert(
					state.ancestors,
					current:GetPropertyChangedSignal(property):Connect(function()
						refresh(image, state)
					end)
				)
			end

			current = current.Parent
		end

		refresh(image, state)
	end

	table.insert(
		state.connections,
		image:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
			if state.writingOpacity or image.ImageTransparency == state.internalOpacity then
				return
			end

			state.opacity = image.ImageTransparency
			refresh(image, state)
		end)
	)
	for _, key in
		{
			"Size",
			"Position",
			"AnchorPoint",
			"Rotation",
			"ScaleType",
			"SliceCenter",
			"SliceScale",
			"TileSize",
			"ImageRectOffset",
			"ImageRectSize",
			"ResampleMode",
			"ImageColor3",
			"ZIndex",
		}
	do
		table.insert(
			state.connections,
			image:GetPropertyChangedSignal(key):Connect(function()
				syncFrames(image, state)
			end)
		)
	end

	table.insert(
		state.connections,
		image.AncestryChanged:Connect(function()
			syncFrames(image, state)
			ancestry()
		end)
	)
	table.insert(
		state.connections,
		image.Destroying:Connect(function()
			unbind(image)
		end)
	)

	requestFrame(image, state, 1, os.clock())
	ancestry()
end

function Gif.effectiveFrames(raw)
	local frames = raw and Sequence.normalize(raw)
	if not frames then
		return nil
	end

	local mode = playbackMode
	if mode == 3 then
		return { { image = frames[1].image, delay = frames[1].delay } }
	end

	if mode ~= 2 then
		return frames
	end

	local duration = Sequence.duration(frames)
	local step = math.max(100, duration / Sequence.MAX_FRAMES)
	local result = {}
	local elapsed = 0
	while elapsed < duration do
		local image = frames[Sequence.indexAt(frames, elapsed)].image
		local delay = math.min(step, duration - elapsed)
		local previous = result[#result]
		if previous and previous.image == image then
			previous.delay += delay
		else
			table.insert(result, { image = image, delay = delay })
		end

		elapsed += delay
	end

	return result
end

local function uniqueImages(frames)
	local ids, seen = {}, {}
	for _, frame in frames or {} do
		if not seen[frame.image] then
			seen[frame.image] = true
			table.insert(ids, frame.image)
		end
	end

	return ids
end

function Gif.needsLoad(frames)
	for _, id in uniqueImages(frames) do
		if not loaded[id] then
			return true
		end
	end

	return false
end

function Gif.preload(frames, progress, cancelled)
	loadGeneration += 1
	local generation = loadGeneration
	local ids = uniqueImages(frames)
	local total = #ids
	local done = 0
	local pending = {}
	for _, id in ids do
		if loaded[id] then
			done += 1
		else
			table.insert(pending, id)
		end
	end

	local function report()
		if progress then
			pcall(progress, done, total)
		end
	end

	report()
	if #pending == 0 then
		return true
	end

	local nextIndex, workers, failed = 1, {}, false
	local failedImage
	local objects = {}
	local active = {}
	local stopped = false

	local function cancelledNow()
		if stopped or generation ~= loadGeneration then
			return true
		end

		if cancelled then
			local ok, value = pcall(cancelled)
			return not ok or value
		end

		return false
	end

	local function finish()
		stopped = true
		for _, worker in workers do
			if coroutine.status(worker) ~= "dead" then
				pcall(task.cancel, worker)
			end
		end

		for object in objects do
			object:Destroy()
		end
	end

	for _ = 1, math.min(4, #pending) do
		table.insert(
			workers,
			task.defer(function()
				while not cancelledNow() do
					local index = nextIndex
					nextIndex += 1
					local id = pending[index]
					if not id then
						return
					end

					active[id] = os.clock()
					local image = Instance.new("ImageLabel")
					image.Image = KoiImages.resolve(id)
					objects[image] = true
					local success = false
					local ok = false
					for attempt = 1, 3 do
						ok = pcall(function()
							ContentProvider:PreloadAsync({ image }, function(_, status)
								success = status == Enum.AssetFetchStatus.Success
							end)
						end)
						if ok and (success or image.IsLoaded) then
							success = true
							break
						end

						if cancelledNow() then
							break
						end

						if attempt < 3 then
							task.wait(attempt * 0.2)
						end
					end

					active[id] = nil
					objects[image] = nil
					image:Destroy()
					if cancelledNow() then
						return
					end

					if ok and success then
						loaded[id] = true
					else
						failed = true
						failedImage = failedImage or id
					end

					done += 1
					report()
					task.wait()
				end
			end)
		)
	end

	local timedOut = false
	while done < total and not cancelledNow() do
		for id, started in active do
			if os.clock() - started >= 30 then
				timedOut = true
				failedImage = id
				break
			end
		end

		if timedOut then
			break
		end

		task.wait(0.03)
	end

	local reason = cancelledNow() and "cancelled"
		or timedOut and "timeout"
		or failed and "failed"
		or nil
	finish()
	local available = 0
	for _, id in ids do
		if loaded[id] then
			available += 1
		end
	end

	return reason == nil, reason, failedImage, { loaded = available, total = total }
end

function Gif.loadMessage(reason, id)
	if reason == "cancelled" then
		return "Image loading was canceled. Your frames are still here."
	end

	if reason == "timeout" then
		return (id and ("Image " .. id:gsub("rbxassetid://", "")) or "An image")
			.. " took too long to load. Your frames have been kept. Press Apply to retry."
	end

	local label = id and ("Image " .. id:gsub("rbxassetid://", "")) or "An image"
	if id then
		local ok, info = pcall(function()
			return game:GetService("MarketplaceService"):GetProductInfo(tonumber(id:match("%d+")))
		end)
		if
			ok
			and info.AssetTypeId ~= Enum.AssetType.Image.Value
			and info.AssetTypeId ~= Enum.AssetType.Decal.Value
		then
			return label
				.. " is not an image or decal. Copy the image ID from the decal's Texture property, not the model or catalog asset ID."
		end
	end

	return label
		.. " could not load. Use an image or decal ID (the decal's Texture), and check its permissions. Your frames have been kept."
end

function Gif.stats()
	local counts = { targets = 0, streams = 0, activeStreams = 0, heartbeat = heartbeat ~= nil }
	for _ in targets do
		counts.targets += 1
	end

	for _ in streams do
		counts.streams += 1
	end

	for _ in activeStreams do
		counts.activeStreams += 1
	end

	return counts
end

function Gif.destroy()
	loadGeneration += 1
	for _, connection in lifetime do
		connection:Disconnect()
	end

	table.clear(lifetime)
	for image in targets do
		unbind(image)
	end

	table.clear(streams)
	table.clear(loaded)
end

return Gif
