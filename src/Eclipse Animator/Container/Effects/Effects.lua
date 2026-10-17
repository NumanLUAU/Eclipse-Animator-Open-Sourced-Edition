--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Run = game:GetService("RunService")
local Model = require("Model")
local Objects = require("Objects")
local Camera = require("CameraRig")
local Properties = require("Properties")
local Organization = require("Organization")
local History = require("History")
local Raw = require("RawState")
local Chunks = require("ChunkStore")
local Effects = {}
local fovButtons = setmetatable({}, { __mode = "k" })
local refs, connection, gui
local lifetime = {}
local suspended = false

local function presentationActive()
	return refs
		and refs.ScreenGui.Enabled
		and (
			refs.AnimatorFrame.Visible
			or refs.State.PresentationHidden and require("Visibility").isPlaybackActive()
		)
end

local overlays = {}
local tracked = {}
local generation = 0
local parkedModels = setmetatable({}, { __mode = "k" })

local function folder()
	if refs.EffectsWorldParent then
		return refs.EffectsWorldParent
	end

	for _, v in workspace:GetChildren() do
		if v:IsA("Folder") and v:GetAttribute("EclipseEffectsFolder") then
			return v
		end
	end

	local f = Instance.new("Folder")
	f.Name = "Eclipse Effects"
	f:SetAttribute("EclipseEffectsFolder", true)
	f.Parent = workspace
	return f
end

local function parked()
	local parent = refs and refs.EffectsWorldParent or game:GetService("ServerStorage")
	local f = require("root").get("EclipseEffectStorage", true, parent)
	f:SetAttribute("EclipseEffectStorage", true)
	return f
end

local stepCount = 0

local function cleanFolders()
	local scope = refs and refs.EffectsWorldParent or workspace
	for _, f in scope:GetChildren() do
		if f:IsA("Folder") and f:GetAttribute("EclipseEffectsFolder") and #f:GetChildren() == 0 then
			f:Destroy()
		end
	end
end

local function park(model)
	if not Objects.is(model) or not model.Parent then
		return
	end

	local storage = parked()

	if parkedModels[model] and model.Parent == storage then
		return false
	end

	Objects.paint(model, false, 0)
	model.Parent = storage
	parkedModels[model] = true
	return true
end

function Effects.parkAll()
	local targets = {}
	for model in tracked do
		targets[model] = true
	end

	local parent = refs and refs.EffectsWorldParent or workspace
	for _, v in parent:GetDescendants() do
		if Objects.is(v) and not v:IsDescendantOf(parked()) then
			targets[v] = true
		end
	end

	for model in targets do
		park(model)
	end

	cleanFolders()
	if gui then
		gui:Destroy()
		gui = nil
	end

	overlays = {}
	tracked = {}
end

function Effects.cameras()
	local result = {}
	if not refs then
		return result
	end

	for _, rig in refs.State.getAllRigs() do
		if rig.Parent and Camera.isRig(rig) then
			local id = rig:GetAttribute("EclipseTrackId")
			if not id then
				id = Http:GenerateGUID(false)
				rig:SetAttribute("EclipseTrackId", id)
			end

			table.insert(
				result,
				{ id = id, rig = rig, name = rig.Name, enabled = Organization.isEnabled(rig) }
			)
		end
	end

	return result
end

function Effects.resolveCamera(id)
	for _, c in Effects.cameras() do
		if c.id == id then
			return c
		end
	end
end

function Effects.validateForProject(value)
	local v = Model.validate(value)
	if v.kind == "Camera Shake" then
		v.shakeEnvelope = value.shakeEnvelope == true
		v.strength = tonumber(value.strength)
		v.speed = tonumber(value.speed)
		assert(
			Model.finite(v.strength) and v.strength > 0 and v.strength <= 100,
			"Strength must be greater than zero, up to 100."
		)
		assert(
			Model.finite(v.speed) and v.speed > 0 and v.speed <= 60,
			"Speed must be greater than zero, up to 60."
		)
	end

	v.gradient = value.gradient == true
	v.color2 = table.clone(value.color2 or value.color)
	assert(#v.color2 == 3, "Choose a valid second color")
	for _, n in v.color2 do
		assert(Model.finite(n) and n >= 0 and n <= 1, "Choose a valid second color")
	end

	v.gradientRotation = value.gradientRotation or 90
	assert(Model.finite(v.gradientRotation), "Enter a valid gradient angle")
	if v.kind == "Impact Frames" then
		v.frames = Effects.validateImpactFrames(value.frames)
		local duration = 0
		for _, row in v.frames do
			duration += row.delay + row.hold
		end

		v.duration = duration
		v.fadeIn = 0
		v.fadeOut = 0
		assert(
			v.start + duration <= Model.MAX_FRAME,
			"The sequence ends beyond the timeline limit."
		)
	end

	if v.kind == "Letterbox" or v.kind == "Camera Shake" then
		local cameras = Effects.cameras()
		assert(#cameras > 0, "Add a camera to this project first.")
		if not v.cameraId and #cameras == 1 then
			v.cameraId = cameras[1].id
		end

		assert(
			v.cameraId and Effects.resolveCamera(v.cameraId),
			"Select the camera for this " .. v.kind:lower() .. "."
		)
	end

	for _, key in { "width", "heightScale", "depth" } do
		local n = value[key] or (key == "depth" and 1.2 or 1)
		assert(
			Model.finite(n) and n >= (key == "depth" and 0.55 or 0.01) and n <= 20,
			"Enter a valid " .. key
		)
		v[key] = n
	end

	v.images = {}
	for i, id in value.images or Objects.images do
		id = tostring(id):gsub("rbxassetid://", "")
		assert(id:match("^%d+$") and #id <= 20, "Enter a numeric image asset ID.")
		v.images[i] = id
	end

	assert(#v.images == 4, "Vignette needs four image tile IDs.")
	return v
end

local function uniqueName(name)
	local names = {}
	for _, r in refs.State.getAllRigs() do
		names[r.Name] = true
	end

	local n = 1
	local result = name
	while names[result] or folder():FindFirstChild(result) do
		n += 1
		result = name .. " " .. n
	end

	return result
end

local function makeKey(motor, value, frame, ease)
	local cf = Properties.is(motor) and Properties.encode(value) or value
	return {
		Motor = motor,
		Part = motor.Part1,
		Frame = frame,
		Time = frame / Raw.Timeline.FPS,
		C0 = cf,
		Position = cf.Position,
		PropertyValue = Properties.is(motor) and value or nil,
		EasingStyle = ease and (ease.style == "Custom" and "Bezier" or ease.style) or "Constant",
		EasingDirection = ease and ease.direction or "Out",
		BezierPoints = ease and ease.curve or nil,
		Overshoot = ease and ease.Overshoot,
		Amplitude = ease and ease.Amplitude,
		Period = ease and ease.Period,
		Parented = true,
		SanitizeName = tostring,
	}
end

function Effects.validateImpactFrames(rows)
	assert(
		type(rows) == "table" and #rows > 0 and #rows <= 256,
		"Add between 1 and 256 impact images."
	)
	local result = {}
	for _, row in rows do
		assert(type(row) == "table", "Invalid impact image.")
		local delay, hold = tonumber(row.delay), tonumber(row.hold)
		assert(
			Model.finite(delay) and delay >= 0 and delay % 1 == 0 and delay <= Model.MAX_FRAME,
			"Delay must be a whole number of frames, zero or more."
		)
		assert(
			Model.finite(hold) and hold >= 1 and hold % 1 == 0 and hold <= Model.MAX_FRAME,
			"Hold must be at least one whole frame."
		)
		local image = Objects.impactImage(row.image)
		assert(image ~= "", "Choose an image for every frame.")
		table.insert(result, { image = image, delay = delay, hold = hold })
	end

	return result
end

function Effects.impactDraft()
	return {
		{ image = "builtin:White", delay = 0, hold = 1 },
		{ image = "builtin:Burst", delay = 0, hold = 1 },
		{ image = "builtin:Inverse", delay = 0, hold = 1 },
		{ image = "builtin:Black", delay = 1, hold = 1 },
	}
end

function Effects.createImpact(rows, start)
	assert(not Raw.Timeline.Exporting, "Wait for the module export to finish.")
	assert(not Raw.Timeline.Playing, "Pause playback before adding impact frames.")
	local frames = Effects.validateImpactFrames(rows)
	local duration = 0
	for _, row in frames do
		duration += row.delay + row.hold
	end

	local value = Model.defaults(
		"Impact Frames",
		start or math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS),
		Raw.Timeline.FPS
	)
	value.color = { 1, 1, 1 }
	value.duration = duration
	value.fadeIn = 0
	value.fadeOut = 0
	value.frames = frames
	return Effects.create(value)
end

function Effects.createShake(strength, speed, start, duration, cameraId, envelope)
	assert(not Raw.Timeline.Exporting, "Wait for the module export to finish.")
	assert(not Raw.Timeline.Playing, "Pause playback before adding camera shake.")
	local value = Model.defaults(
		"Camera Shake",
		start or math.round(Raw.Timeline.CurrentTime * Raw.Timeline.FPS),
		Raw.Timeline.FPS
	)
	value.duration = duration or math.max(1, math.round(Raw.Timeline.FPS * 0.5))
	value.fadeIn = 0
	value.fadeOut = 0
	value.cameraId = cameraId
	value.strength = strength or 1
	value.speed = speed or 12
	if envelope then
		value.shakeEnvelope = true
		value.fadeIn = envelope.fadeIn
		value.fadeOut = envelope.fadeOut
		value.easeIn = envelope.easeIn or value.easeIn
		value.easeOut = envelope.easeOut or value.easeOut
	end

	return Effects.create(value)
end

local phaseCaches = setmetatable({}, { __mode = "k" })

local function shakeSpeed(value)
	return Model.finite(value) and math.clamp(value, 0, 60) or 12
end

function Effects.shakePhase(motor, bucket, time, speed)
	time = math.max(0, time)
	if not motor or motor:GetAttribute("EclipseDisabled") or not bucket or not next(bucket) then
		return time * shakeSpeed(speed)
	end

	local revision = require("cache").revision()
	local cache = phaseCaches[motor]
	if
		not cache
		or cache.bucket ~= bucket
		or cache.revision ~= revision
		or cache.default ~= motor.DefaultValue
	then
		local times = { 0 }
		local seen = { [0] = true }
		for _, key in bucket do
			if
				not key.Disabled
				and Model.finite(key.Time)
				and key.Time > 0
				and not seen[key.Time]
			then
				seen[key.Time] = true
				table.insert(times, key.Time)
			end
		end

		table.sort(times)
		cache = {
			bucket = bucket,
			revision = revision,
			default = motor.DefaultValue,
			times = times,
			sums = { [1] = 0 },
			built = 1,
		}
		phaseCaches[motor] = cache
	end

	local function sample(t)
		return shakeSpeed(Properties.evaluate(motor, bucket, t))
	end

	local function integral(a, b)
		if b <= a then
			return 0
		end

		local epsilon = math.min(1e-8, (b - a) * 1e-6)

		local function refine(lo, hi, fa, fm, fb, area, tolerance, depth)
			local mid = (lo + hi) * 0.5
			local left = sample((lo + mid) * 0.5)
			local right = sample((mid + hi) * 0.5)
			local aa = (mid - lo) * (fa + 4 * left + fm) / 6
			local bb = (hi - mid) * (fm + 4 * right + fb) / 6
			if depth == 0 or math.abs(aa + bb - area) <= 15 * tolerance then
				return aa + bb + (aa + bb - area) / 15
			end

			return refine(lo, mid, fa, left, fm, aa, tolerance * 0.5, depth - 1)
				+ refine(mid, hi, fm, right, fb, bb, tolerance * 0.5, depth - 1)
		end

		local fa, fm, fb = sample(a + epsilon), sample((a + b) * 0.5), sample(b - epsilon)
		return refine(a, b, fa, fm, fb, (b - a) * (fa + 4 * fm + fb) / 6, 1e-5, 10)
	end

	local times = cache.times
	local low, high, index = 1, #times, 1
	while low <= high do
		local mid = (low + high) // 2
		if times[mid] <= time then
			index = mid
			low = mid + 1
		else
			high = mid - 1
		end
	end

	for i = cache.built, index - 1 do
		cache.sums[i + 1] = cache.sums[i] + integral(times[i], times[i + 1])
		cache.built = i + 1
	end

	if index == #times then
		return cache.sums[index] + (time - times[index]) * sample(time)
	end

	return cache.sums[index] + integral(times[index], time)
end

function Effects.shake(time, exporting, camera)
	if not camera or not Camera.isRig(camera) then
		return CFrame.identity
	end

	if not refs or suspended or not exporting and not presentationActive() then
		return CFrame.identity
	end

	time = time or Raw.Timeline.CurrentTime
	local result = CFrame.identity
	for _, model in refs.State.getAllRigs() do
		if
			not model.Parent
			or Objects.kind(model) ~= "Camera Shake"
			or Organization.cameraFor(model) ~= camera
			or not Organization.isEnabled(model)
		then
			continue
		end

		local values = {
			Strength = Objects.read(model, "Strength"),
			Speed = Objects.read(model, "Speed"),
			Enabled = Objects.read(model, "Enabled"),
		}
		local speedMotor
		for _, motor in Properties.list(model) do
			if motor.PropertyId == "Speed" then
				speedMotor = motor
			end

			values[motor.PropertyId] = motor:GetAttribute("EclipseDisabled") and motor.DefaultValue
				or Properties.evaluate(motor, Raw.Timeline.Keyframes[motor], time)
		end

		if values.Enabled == false then
			continue
		end

		local strength = Model.finite(values.Strength) and math.clamp(values.Strength, 0, 100) or 0
		local speed = Model.finite(values.Speed) and math.clamp(values.Speed, 0, 60) or 12
		if strength == 0 then
			continue
		end

		local seed = 0
		for i = 1, #model:GetAttribute("EclipseTrackId") do
			seed = (seed * 31 + model:GetAttribute("EclipseTrackId"):byte(i)) % 65521
		end

		local phase = Effects.shakePhase(
			speedMotor,
			speedMotor and Raw.Timeline.Keyframes[speedMotor],
			time,
			speed
		)

		local function noise(axis)
			return math.noise(phase, seed * 0.017 + axis * 17.1, axis * 0.73) * 2
		end

		local position = Vector3.new(noise(1), noise(2), noise(3)) * (strength * 0.15)
		local rotation = Vector3.new(noise(4), noise(5), noise(6)) * math.rad(strength * 1.5)
		result *= CFrame.new(position) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
	end

	return result
end

function Effects.impactAssets()
	local result, seen = {}, {}

	local function add(value)
		if type(value) == "string" and value:match("^rbxassetid://%d+$") and not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end

	for _, model in refs.State.getAllRigs() do
		if Objects.kind(model) == "Impact Frames" then
			add(Objects.read(model, "Image"))
			for _, motor in Properties.list(model) do
				if motor.PropertyId == "Image" then
					for _, key in Raw.Timeline.Keyframes[motor] or {} do
						add(key.PropertyValue)
					end
				end
			end
		end
	end

	return result
end

local preparedImages = {}
local prepareWarning, prepareWarnedAt

function Effects.prepare(isCurrent)
	if not isCurrent() then
		return false
	end

	local assets = Effects.impactAssets()
	if #assets == 0 then
		return true
	end

	local images = {}
	for _, asset in assets do
		if not preparedImages[asset] then
			local image = Instance.new("ImageLabel")
			image.Image = asset
			table.insert(images, image)
		end
	end

	if #images == 0 then
		return true
	end

	local provider = game:GetService("ContentProvider")
	local done, failed = false, false
	local worker = task.spawn(function()
		local ok = pcall(function()
			provider:PreloadAsync(images, function(_, status)
				if status ~= Enum.AssetFetchStatus.Success then
					failed = true
				end
			end)
		end)
		failed = failed or not ok
		done = true
	end)
	local deadline = os.clock() + 12
	while not done and isCurrent() and os.clock() < deadline do
		task.wait()
	end

	if not done then
		pcall(task.cancel, worker)
	end

	for _, image in images do
		image:Destroy()
	end

	if not isCurrent() then
		return false
	end

	if not done or failed then
		table.sort(assets)
		local signature = table.concat(assets, "|")
		if prepareWarning ~= signature or os.clock() - (prepareWarnedAt or 0) > 10 then
			prepareWarning, prepareWarnedAt = signature, os.clock()
			require("Notification").show(
				"IMPACT FRAMES",
				"An impact image could not load. Use an image or decal ID and check its permissions, then try again.",
				4
			)
		end

		return false
	end

	for _, asset in assets do
		preparedImages[asset] = true
	end

	prepareWarning = nil
	return true
end

function Effects.seed(model, value)
	local raw = Raw.Timeline
	local solid = value.kind == "Letterbox" and value.style == "Solid"
	if solid then
		Objects.write(model, "Transparency", 1 - value.opacity)
	end

	for _, definition in Objects.catalog(model) do
		if
			definition.legacy
			or definition.optional and (definition.id == "ZIndex" or not value.gradient)
		then
			continue
		end

		local motor = Properties.enable(model, definition.id, true, raw)
		local keys = {}
		raw.Keyframes[motor] = keys
		if value.kind == "Camera Shake" and definition.id == "Strength" then
			if value.shakeEnvelope then
				local start, finish = value.start, value.start + value.duration
				keys[0] = makeKey(motor, 0, 0)
				keys[start] = makeKey(
					motor,
					value.fadeIn > 0 and 0 or value.strength,
					start,
					value.fadeIn > 0 and value.easeIn or nil
				)
				if value.fadeIn > 0 then
					keys[start + value.fadeIn] =
						makeKey(motor, value.strength, start + value.fadeIn)
				end

				if value.fadeOut > 0 then
					keys[finish - value.fadeOut] =
						makeKey(motor, value.strength, finish - value.fadeOut, value.easeOut)
				end

				keys[finish] = makeKey(motor, 0, finish)
				for _, key in keys do
					key.HandleType = "Vector"
				end
			else
				keys[0] = makeKey(motor, 0, 0)
				keys[value.start] = makeKey(
					motor,
					value.strength,
					value.start,
					{ style = "Linear", direction = "Out" }
				)
				keys[value.start + value.duration] = makeKey(motor, 0, value.start + value.duration)
			end
		elseif value.kind == "Camera Shake" and definition.id == "Speed" then
			keys[0] = makeKey(motor, value.speed, 0)
		elseif value.kind == "Impact Frames" and definition.id == "Image" then
			keys[0] = makeKey(motor, "", 0)
			local at = value.start
			for _, row in value.frames do
				at += row.delay
				keys[at] = makeKey(motor, row.image, at)
				at += row.hold
				keys[at] = makeKey(motor, "", at)
			end
		elseif value.kind == "Impact Frames" and definition.id == "Transparency" then
			keys[0] = makeKey(motor, 0, 0)
		elseif definition.id == "Transparency" and not solid then
			local start, finish = value.start, value.start + value.duration
			local level = 1 - value.opacity
			keys[0] = makeKey(motor, 1, 0)
			keys[start] = makeKey(
				motor,
				value.fadeIn > 0 and 1 or level,
				start,
				value.fadeIn > 0 and value.easeIn or nil
			)
			if value.fadeIn > 0 then
				keys[start + value.fadeIn] = makeKey(motor, level, start + value.fadeIn)
			end

			if value.fadeOut > 0 then
				keys[finish - value.fadeOut] =
					makeKey(motor, level, finish - value.fadeOut, value.easeOut)
			end

			keys[finish] = makeKey(motor, 1, finish)
		else
			keys[value.start] = makeKey(motor, Objects.read(model, definition.id), value.start)
		end
	end

	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") and joint:GetAttribute("EclipsePartRigJoint") then
			raw.DefaultPose[joint] = joint.C0
			raw.DefaultWorldPose[joint] = joint.Part1.CFrame
			raw.DefaultSize[joint.Part1] = joint.Part1.Size
			raw.ParentingDefaults[joint] = true
			raw.MotorByPart[joint.Part1] = joint
			local key = makeKey(joint, joint.C0, value.start)
			local defaults = require("SavedDefaults").get()
			for id, v in defaults do
				key[id] = v
			end

			key.WholePoseScale = { scale_x = 1, scale_y = 1, scale_z = 1 }
			raw.Keyframes[joint] = { [value.start] = key }
		end
	end
end

function Effects.create(value, options)
	options = options or {}
	value = Effects.validateForProject(value)
	suspended = false
	local oldLength = Raw.Config.Length
	if refs.Finalize and not options.loading then
		refs.Finalize()
	end

	local target = value.kind == "Letterbox" and Effects.resolveCamera(value.cameraId) or nil
	local view = workspace.CurrentCamera
	local size = view and view.ViewportSize or Vector2.new(16, 9)
	local model = Objects.build(
		value,
		target and { cf = Camera.viewFrame(target.rig), fov = Camera.fov(target.rig) },
		size.X / math.max(1, size.Y)
	)
	model.Name = uniqueName(value.name)
	model:SetAttribute("EclipseLegacyEffectId", options.legacyId)
	local parent = folder()
	model.Parent = parent
	Objects.paint(model, false, 0)
	local original = model
	local originalParent = parent
	local ok, err = xpcall(function()
		for _, def in Objects.catalog(model) do
			if not def.legacy and (not def.optional or value.gradient and def.id ~= "ZIndex") then
				Properties.enable(model, def.id, true)
			end
		end

		refs.AddRig(model, { Loading = true })
		if not table.find(refs.State.getAllRigs(), model) then
			for _, candidate in refs.State.getAllRigs() do
				if
					candidate:GetAttribute("EclipseTrackId")
					== model:GetAttribute("EclipseTrackId")
				then
					model = candidate
					parent = model.Parent
					break
				end
			end
		end

		assert(
			table.find(refs.State.getAllRigs(), model),
			"Could not add the effect to the timeline."
		)
		Effects.seed(model, value)
		if value.kind ~= "Letterbox" or value.style ~= "Solid" then
			Raw.Config.Length =
				math.max(Raw.Config.Length, (value.start + value.duration) / Raw.Timeline.FPS)
		end

		refs.RefreshStructure()
		refs.State.currentProjectSaved = false
	end, debug.traceback)
	if not ok then
		if table.find(refs.State.getAllRigs(), model) then
			refs.RemoveRig(model, { Loading = true })
		end

		model:Destroy()
		error(err, 0)
	end

	local epoch = generation
	local snapshot
	if not options.loading then
		History.record(function()
			if epoch ~= generation then
				return
			end

			local _, saved = refs.RemoveRig(model, { Loading = true })
			snapshot = saved
			model.Parent = nil
			if original ~= model then
				original.Parent = nil
			end

			Raw.Config.Length = oldLength
			refs.RefreshStructure()
			Effects.refresh()
		end, function()
			if epoch ~= generation or not snapshot then
				return
			end

			if original ~= model then
				original.Parent = folder()
			end

			model.Parent = folder()
			refs.RestoreRig(snapshot)
			Raw.Config.Length = value.kind == "Letterbox" and value.style == "Solid" and oldLength
				or math.max(oldLength, (value.start + value.duration) / Raw.Timeline.FPS)
			refs.RefreshStructure()
			Effects.refresh()
		end, "Add " .. value.kind)
	end

	Properties.apply(model, Raw.Timeline, Raw.Timeline.CurrentTime)
	Effects.refresh()
	return model
end

function Effects.refresh()
	if not refs then
		return
	end

	local nextTracked = {}
	for _, model in refs.State.getAllRigs() do
		if Objects.is(model) then
			nextTracked[model] = true
		end
	end

	for model in tracked do
		if not nextTracked[model] then
			park(model)
		end
	end

	tracked = nextTracked
	cleanFolders()
	Effects.step()
end

function Effects.updateFovRows()
	for button, model in fovButtons do
		if not button.Parent or not model.Parent then
			fovButtons[button] = nil
			continue
		end

		local follow = Objects.read(model, "FollowFOV") ~= false
		button.Text = follow and "F" or "W"
		button.TextColor3 = follow and Color3.fromRGB(97, 255, 197) or Color3.fromRGB(255, 198, 103)
		button.Active = not Raw.Timeline.Playing
		button.AutoButtonColor = not Raw.Timeline.Playing
	end
end

function Effects.setFovFollow(model, value)
	assert(refs and Objects.kind(model) == "Letterbox", "Select a letterbox")
	assert(not require("BlenderEdit").blocked(), "Finish the current edit first")
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	assert(not raw.Playing, "Pause playback before changing FOV follow")
	if refs.Finalize then
		refs.Finalize()
	end

	local motor = Properties.enable(model, "FollowFOV", true, raw)
	local before = timeline:_snapshotMotorBucket(motor)
	local frame = timeline:TimeToFrame(raw.CurrentTime)
	local camera = Effects.resolveCamera(model:GetAttribute("EffectCameraId"))
	assert(camera, "Letterbox camera is unavailable")
	local fov = Camera.fov(camera.rig)
	Objects.follow(model, { cf = Camera.viewFrame(camera.rig), fov = fov }, raw)
	local anchor = Vector3.new(Objects.followRatio(model), fov, 0)
	timeline:RecordKeyframeForMotorAtCurrentTime(
		motor.Part1,
		motor,
		Properties.encode(value),
		{ Frame = frame, PropertyValue = value },
		refs.State.UIHelpers.SanitizeName
	)
	raw.Keyframes[motor][frame].FovFollowAnchor = anchor
	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(bucket)
		if not model.Parent then
			return
		end

		timeline:_restoreMotorBucket(motor, bucket)
		Properties.apply(model, raw, raw.CurrentTime)
		refs.State.currentProjectSaved = false
		refs.RefreshStructure()
		Effects.step()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Letterbox FOV follow")
	return raw.Keyframes[motor][frame]
end

function Effects.bindFovRow(item)
	local model = item.linkedRigInstance
	if Objects.kind(model) ~= "Letterbox" or item.fovFollowButton then
		return
	end

	local button =
		require("ParentingUI").modeButton(item.appearDetails.RightDiv, "LetterboxFollowFOV")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.LayoutOrder = -2
	item.fovFollowButton = button
	fovButtons[button] = model
	local hover = item.rigModule.refs.UIHelpers.hoverDialog
	if hover then
		hover:latchToInstance(
			button,
			"F: follow camera FOV / W: fixed world sizing. Key at current frame."
		)
	end

	table.insert(
		item.connections,
		button.MouseButton1Click:Connect(function()
			Effects.setFovFollow(model, Objects.read(model, "FollowFOV") == false)
		end)
	)
	Effects.updateFovRows()
end

function Effects.step()
	Effects.updateFovRows()
	if not refs then
		return
	end

	local active = not suspended and presentationActive()
	local present = {}
	for _, model in refs.State.getAllRigs() do
		if Objects.is(model) and model.Parent then
			present[model] = true
		end
	end

	local parkedAny = false
	for model in tracked do
		if not present[model] then
			parkedAny = park(model) or parkedAny
		end
	end

	tracked = present
	for model in present do
		if not active then
			parkedAny = park(model) or parkedAny
			if overlays[model] then
				overlays[model]:Destroy()
				overlays[model] = nil
			end

			continue
		end

		parkedModels[model] = nil
		if model.Parent == parked() then
			model.Parent = folder()
		end

		local enabled = active and Organization.isEnabled(model) and Objects.read(model, "Enabled")
		if Objects.kind(model) == "Camera Shake" then
			continue
		end

		if Objects.kind(model) == "Letterbox" then
			local camera = Effects.resolveCamera(model:GetAttribute("EffectCameraId"))
			if camera then
				Objects.follow(model, {
					cf = Camera.viewFrame(camera.rig, nil, refs.State.Timeline:GetPoseTime(Raw.Timeline.CurrentTime)) * Effects.shake(nil, false, camera.rig),
					fov = Camera.fov(camera.rig, refs.State.Timeline:GetPoseTime(Raw.Timeline.CurrentTime)),
				}, Raw.Timeline)
			end

			Objects.paint(
				model,
				enabled and camera ~= nil and camera.enabled,
				Raw.Timeline.CurrentTime
			)
		else
			local frame = overlays[model]
			if not frame then
				if not gui then
					gui = Instance.new("ScreenGui")
					gui.Name = "EclipseEffectOverlays"
					gui:SetAttribute("EclipseOwnedUI", true)
					gui.IgnoreGuiInset = true
					gui.ResetOnSpawn = false
					gui.DisplayOrder = refs.ScreenGui.DisplayOrder - 1
					gui.Parent = refs.ScreenGui.Parent
				end

				frame = Objects.overlay(model, gui)
				overlays[model] = frame
			end

			Objects.paintOverlay(model, frame, enabled)
		end
	end

	for model, frame in overlays do
		if not present[model] then
			frame:Destroy()
			overlays[model] = nil
		end
	end

	stepCount += 1
	if parkedAny or stepCount % 60 == 0 then
		cleanFolders()
	end
end

function Effects.write(save)
	if next(Raw.Timeline.ScreenEffects or {}) then
		Chunks.write(save, "EclipseScreenEffects", Http:JSONEncode(Raw.Timeline.ScreenEffects))
	end

	local objects = Instance.new("Folder")
	objects.Name = "EclipseEffectObjects"
	for _, model in refs.State.getAllRigs() do
		if Objects.is(model) then
			local clone = model:Clone()
			for _, node in clone:GetDescendants() do
				if node:IsA("LuaSourceContainer") then
					node:Destroy()
				end
			end

			clone.Parent = objects
		end
	end

	if #objects:GetChildren() > 0 then
		objects.Parent = save
	else
		objects:Destroy()
	end
end

function Effects.restoreObjects(save)
	local saved = save and save:FindFirstChild("EclipseEffectObjects")
	if not saved then
		return
	end

	local existing = {}
	for _, scope in { refs.EffectsWorldParent or workspace, parked() } do
		for _, v in scope:GetDescendants() do
			if Objects.is(v) and v:GetAttribute("EclipseTrackId") then
				existing[v:GetAttribute("EclipseTrackId")] = v
			end
		end
	end

	for _, model in saved:GetChildren() do
		if Objects.is(model) then
			local current = existing[model:GetAttribute("EclipseTrackId")]
			if current then
				if current.Parent == parked() then
					current.Parent = folder()
				end

				continue
			end

			local clone = model:Clone()
			for _, node in clone:GetDescendants() do
				if node:IsA("LuaSourceContainer") then
					node:Destroy()
				end
			end

			clone.Parent = folder()
		end
	end
end

function Effects.load(save)
	generation += 1
	if refs and refs.State.EffectsWindow then
		refs.State.EffectsWindow.close(true)
	end

	suspended = save == nil
	if suspended then
		Effects.parkAll()
		Raw.Timeline.ScreenEffects = {}
		return
	end

	Raw.Timeline.ScreenEffects = {}
	local old = save and save:FindFirstChild("EclipseScreenEffects")
	if old then
		local legacy = Model.validateAll(Http:JSONDecode(Chunks.read(old)))
		for id, value in legacy do
			local exists = false
			for _, r in refs.State.getAllRigs() do
				if r:GetAttribute("EclipseLegacyEffectId") == id then
					exists = true
				end
			end

			if not exists then
				local ok, err = pcall(Effects.create, value, { loading = true, legacyId = id })
				if not ok then
					Raw.Timeline.ScreenEffects[id] = value
					warn("Effect migration: " .. tostring(err))
				end
			end
		end
	end

	Effects.refresh()
end

function Effects.setPreview() end

function Effects.destroy()
	phaseCaches = setmetatable({}, { __mode = "k" })
	Camera.viewOffset = nil
	if connection then
		connection:Disconnect()
		connection = nil
	end

	for _, listener in lifetime do
		listener:Disconnect()
	end

	table.clear(lifetime)
	if refs then
		Effects.parkAll()
	end

	if gui then
		gui:Destroy()
		gui = nil
	end
end

function Effects.init(options)
	Effects.destroy()
	refs = options
	refs.State.ScreenEffects = Effects
	Camera.viewOffset = function(camera, time)
		return Effects.shake(time, false, camera)
	end

	if not options.EffectsWorldParent then
		require("layer").cleanupStale()
	end

	suspended = false
	Effects.parkAll()
	connection = Run.RenderStepped:Connect(function()
		if suspended or not presentationActive() then
			Effects.step()
		end
	end)
	table.insert(lifetime, refs.ScreenGui.Destroying:Once(Effects.destroy))
	table.insert(lifetime, refs.Plugin.Unloading:Once(Effects.destroy))
	Effects.refresh()
end

return Effects
