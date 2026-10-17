--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Chrome = require("Chrome")
local FX = require("WindowFX")
local Target = require("SelectedRig")
local Import = require("Import")
local History = require("History")
local Raw = require("RawState")
local Events = require("Events")
local EventPlayback = require("EventPlayback")
local Scale = require("TimeScale")
local Groups = require("KeyGroups")
local Http = game:GetService("HttpService")
local Theme = require("Theme")
local Files = {}
local refs, window, staged
local lifetime = {}

local function close()
	if window then
		window:close(true)
		window = nil
	end

	if staged then
		staged:Destroy()
		staged = nil
	end
end

local function create(name, title, size)
	close()
	window = Tool.new(
		{ ScreenGui = refs.UI.EclipseGUI, Plugin = refs.Plugin },
		name,
		title,
		size,
		false,

		function()
			window = nil
			if staged then
				staged:Destroy()
				staged = nil
			end
		end
	)
	return window
end

local function label(parent, name, text, x, y, w)
	local l = Tool.label(parent, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, 24))
	l.ZIndex = parent.ZIndex + 3
	return l
end

local function panel(parent, name, x, y, width, height)
	local f = Tool.make("Frame", parent, name, {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.fromRGB(17, 38, 44),
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex + 1,
	})
	f:SetAttribute("ThemeBg", "Pnl")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke:SetAttribute("ThemeStrk", "Strk")
	stroke.Parent = f
	return f
end

local function checkbox(parent, name, text, x, y, value, width, onChange)
	local button = Tool.make("TextButton", parent, name, {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width or 108, 24),
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ZIndex = parent.ZIndex + 3,
	})
	local title = label(button, "Title", text, 23, 0, (width or 108) - 23)
	local box = Tool.make("Frame", button, "Check", {
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex + 1,
	})
	local fill = Tool.make("Frame", box, "Fill", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BorderSizePixel = 0,
		ZIndex = box.ZIndex + 1,
	})
	fill:SetAttribute("ThemeBg", "Txt")
	for _, object in { box, fill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = object
	end

	box:SetAttribute("ThemeBg", "TopBtn")
	box:SetAttribute("ThemeTxt", "Txt")
	local border = Instance.new("UIStroke")
	border.Thickness = 1
	border:SetAttribute("ThemeStrk", "Strk")
	border.Parent = box

	local function set(nextValue)
		value = nextValue
		fill.Visible = value
	end

	button.Activated:Connect(function()
		if onChange then
			onChange(not value)
		else
			set(not value)
		end
	end)
	set(value)
	return function()
		return value
	end, set, button
end

local function segments(parent)
	local bar = panel(parent, "Options", 12, 238, 336, 30)
	local getters = {}
	for index, option in { { "Group", false }, { "Events", true }, { "Faces", true } } do
		local value = option[2]
		local button = Tool.make("TextButton", bar, option[1], {
			Text = option[1],
			Position = UDim2.new((index - 1) / 3, 2, 0, 2),
			Size = UDim2.new(1 / 3, -4, 0, 26),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			FontFace = Chrome.FONT,
			TextSize = 11,
			ZIndex = bar.ZIndex + 2,
		})
		button:SetAttribute("ThemeTxt", "Txt")
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = button

		local function paint()
			button.BackgroundColor3 = Theme.get("TopBtn", Color3.fromRGB(30, 60, 65))
			FX.setRestingProperty(button, "BackgroundTransparency", value and 0 or 1)
		end

		local unsubscribe = Theme.onChanged(paint)
		button.Destroying:Once(unsubscribe)
		button.Activated:Connect(function()
			value = not value
			paint()
		end)
		paint()
		getters[index] = function()
			return value
		end
	end

	return table.unpack(getters)
end

local function belongs(motor, rig)
	if require("Properties").is(motor) then
		local owner = motor.Rig
		return owner == rig or owner and owner:IsDescendantOf(rig)
	end

	local part = motor and motor.Part1
	return typeof(part) == "Instance" and (part == rig or part:IsDescendantOf(rig))
end

local function snapshot(rigs)
	local state = refs.State
	local tl = state.Timeline
	local result = {
		buckets = {},
		events = {},
		rigs = rigs,
		endFrame = tl:GetMaxFrame(),
		fps = tl:GetState().FPS,
		skipFrames = tl:GetState().SkipFrames or 0,
		startFrame = tl:GetState().PlaybackStartFrame or 0,
		time = tl:GetState().CurrentTime,
		priority = tl:GetState().AnimationPriority or Enum.AnimationPriority.Action,
		name = refs.Project.getProjectExportName(),
	}
	for motor in tl:GetState().Keyframes do
		for _, rig in rigs do
			if belongs(motor, rig) then
				result.buckets[motor] = tl:_snapshotMotorBucket(motor)
				break
			end
		end
	end

	for _, rig in rigs do
		result.events[rig] = Events.snapshot(Events.get(rig))
	end

	result.subtitles = Events.snapshot(Events.subtitleTrack())
	return result
end

local function refresh()
	local state = refs.State
	local tl = state.Timeline
	tl:GetState().SelectedKeyframes = {}
	tl:GetState().SelectedChannelKeyframes = {}
	tl:GetState().SelectedKeyframe = nil
	if state.Rig then
		state.Rig:BuildRigHierarchy(state.currentRig)
	end

	tl:RefreshTimelineScale()
	tl:RefreshAllKeyframeVisuals()
	tl:RefreshAllTimelineKeyframePositions()
	tl:RefreshEventRows()
	if state.currentRig then
		tl:ApplyPoseAtTime(state.currentRig, tl:GetState().CurrentTime)
	end

	if state.GraphEditor then
		state.GraphEditor.invalidate()
	end

	state.currentProjectSaved = false
end

local function restore(value)
	local tl = refs.State.Timeline
	local raw = tl:GetState()
	raw.Playing = false
	raw.LastPlaybackFrame = nil
	EventPlayback.clear()
	raw.FPS = value.fps
	local motors = {}
	for motor in raw.Keyframes do
		for _, rig in value.rigs do
			if belongs(motor, rig) then
				motors[motor] = true
				break
			end
		end
	end

	for motor in value.buckets do
		motors[motor] = true
	end

	for motor in motors do
		tl:_restoreMotorBucket(motor, value.buckets[motor] or {})
	end

	raw.FPS = value.fps
	raw.CurrentTime = value.time
	raw.AnimationPriority = value.priority
	raw.SkipFrames = value.skipFrames or 0
	raw.PlaybackStartFrame = value.startFrame or 0
	Raw.Config.Length = value.endFrame / value.fps
	for _, track in Events.all() do
		if value.events[track.Rig] then
			Events.restore(track, value.events[track.Rig])
		end
	end

	Events.restore(Events.subtitleTrack(), value.subtitles)
	refs.Project.setProjectName(value.name)
	refresh()
end

function Files.parseEnd(text, fps)
	local seconds, frames = tostring(text):match("^%s*(%d+):(%d+)%s*$")
	local value = seconds and tonumber(seconds) * fps + tonumber(frames) or tonumber(text)
	assert(
		value and value == value and value >= 1 and value <= 1000000 and value % 1 == 0,
		"Enter an end frame or seconds:frames, such as 4:30."
	)
	if seconds then
		assert(tonumber(frames) < fps, "Frames after the colon must be less than FPS.")
	end

	return value
end

function Files.applySettings(name, endFrame, fps, priority, stretch, skipFrames, startFrame)
	assert(type(name) == "string" and name:match("%S"), "Enter an animation name.")
	assert(
		fps and fps % 1 == 0 and fps >= 1 and fps <= 1000,
		"FPS must be a whole number from 1 to 1000."
	)
	assert(
		endFrame and endFrame % 1 == 0 and endFrame >= 1 and endFrame <= 1000000,
		"Invalid timeline end."
	)
	assert(
		typeof(priority) == "EnumItem" and priority.EnumType == Enum.AnimationPriority,
		"Choose an animation priority."
	)
	local state = refs.State
	local tl = state.Timeline
	skipFrames = skipFrames == nil and (tl:GetState().SkipFrames or 0) or skipFrames
	assert(
		type(skipFrames) == "number"
			and skipFrames == skipFrames
			and skipFrames % 1 == 0
			and skipFrames >= 0
			and skipFrames <= 120,
		"Skip frames must be a whole number from 0 to 120."
	)
	startFrame = startFrame == nil and (tl:GetState().PlaybackStartFrame or 0) or startFrame
	assert(
		type(startFrame) == "number"
			and startFrame == startFrame
			and startFrame % 1 == 0
			and startFrame >= 0
			and startFrame < endFrame,
		"Playback start must be a whole frame before the timeline end."
	)
	local before = snapshot(state.getAllRigs())
	local after = snapshot(state.getAllRigs())
	local ratio = stretch and endFrame / before.endFrame or 1
	for motor, bucket in after.buckets do
		local moved = {}
		for frame, key in bucket do
			local target = frame * ratio
			assert(
				target <= endFrame,
				"The timeline end is before existing keys. Enable Stretch or use a later end."
			)
			key.Frame, key.Time = target, target / fps
			for _, point in key.GraphCurves or {} do
				if point.In then
					point.In[1] *= ratio * before.fps / fps
				end

				if point.Out then
					point.Out[1] *= ratio * before.fps / fps
				end
			end

			moved[target] = key
		end

		after.buckets[motor] = moved
	end

	for _, track in after.events do
		for _, collection in { track.Events, track.FaceKeys or {} } do
			for _, key in collection do
				key.Frame = math.floor(key.Frame * ratio + 0.5)
				if key.Duration then
					key.Duration *= ratio
				end

				assert(key.Frame <= endFrame, "The timeline end is before an event or face key.")
			end
		end

		local occupied = {}
		for _, event in track.Events do
			assert(
				not occupied[event.Frame],
				"Stretch would overlap events. Choose a longer timeline end."
			)
			occupied[event.Frame] = true
		end
	end

	for _, event in after.subtitles.Events do
		event.Frame = math.round(event.Frame * ratio)
		event.Subtitle = require("SubtitleData").rescale(event.Subtitle, ratio)
		assert(event.Frame <= endFrame, "The timeline end is before a subtitle.")
	end

	after.name = name:match("^%s*(.-)%s*$")
	after.endFrame = endFrame
	after.fps = fps
	after.priority = priority
	after.skipFrames = skipFrames
	after.startFrame = startFrame
	after.time = math.min(endFrame, before.time * before.fps * ratio) / fps
	local ok, err = pcall(restore, after)
	if not ok then
		restore(before)
		error(err, 0)
	end

	if after.name ~= before.name then
		refs.Export.requestRename(after.name)
	end

	History.record(function()
		restore(before)
	end, function()
		restore(after)
	end, "Animation settings")
end

function Files.openSettings()
	if not refs.State.Timeline or not refs.UI.AnimatorFrame.Visible then
		return
	end

	local w = create("EclipseAnimationSettings", "ANIMATION SETTINGS", Vector2.new(360, 246))
	local f = w.frame
	local raw = refs.State.Timeline:GetState()
	local endFrame = refs.State.Timeline:GetMaxFrame()
	label(f, "NameLabel", "Name", 12, 38, 86)
	local name = Tool.field(
		f,
		"Name",
		refs.Project.getProjectExportName(),
		UDim2.fromOffset(100, 38),
		UDim2.fromOffset(248, 26)
	)
	label(f, "EndLabel", "Timeline end", 12, 72, 86)
	local ending = Tool.field(
		f,
		"End",
		string.format("%d:%02d", math.floor(endFrame / raw.FPS), endFrame % raw.FPS),
		UDim2.fromOffset(100, 72),
		UDim2.fromOffset(108, 26)
	)
	label(f, "FPSLabel", "FPS", 222, 72, 34)
	local fps = Tool.field(f, "FPS", raw.FPS, UDim2.fromOffset(264, 72), UDim2.fromOffset(84, 26))
	require("NumericInput").bind(ending, {
		step = 1,
		min = 1,
		integer = true,
		read = function()
			local rate = tonumber(fps.Text)
			if not rate or rate < 1 then
				return nil
			end

			local ok, value = pcall(Files.parseEnd, ending.Text, rate)
			return ok and value or nil
		end,
		change = function(value)
			local rate = tonumber(fps.Text)
			if not rate or rate < 1 then
				return
			end

			ending.Text = string.format("%d:%02d", math.floor(value / rate), value % rate)
		end,
	})
	local stretch = checkbox(f, "Stretch", "Stretch keys", 100, 104, false, 180)
	label(f, "PriorityLabel", "Priority", 12, 134, 86)
	local priority = raw.AnimationPriority or Enum.AnimationPriority.Action
	local options = {
		Enum.AnimationPriority.Core,
		Enum.AnimationPriority.Idle,
		Enum.AnimationPriority.Movement,
		Enum.AnimationPriority.Action,
		Enum.AnimationPriority.Action2,
		Enum.AnimationPriority.Action3,
		Enum.AnimationPriority.Action4,
	}
	local priorityText
	local priorityButton
	local choices
	priorityButton, priorityText = Tool.button(
		f,
		"Priority",
		priority.Name .. "  \u{25be}",
		UDim2.fromOffset(100, 134),
		UDim2.fromOffset(248, 26),

		function()
			choices.Visible = not choices.Visible
		end
	)
	choices = Tool.make("Frame", f, "PriorityChoices", {
		Position = UDim2.fromOffset(100, 164),
		Size = UDim2.fromOffset(248, 182),
		Visible = false,
		BorderSizePixel = 0,
		ZIndex = 40,
	})
	choices:SetAttribute("ThemeBg", "Pnl")
	local border = Instance.new("UIStroke")
	border:SetAttribute("ThemeStrk", "Strk")
	border.Parent = choices
	for i, option in options do
		Tool.button(
			choices,
			option.Name,
			option.Name,
			UDim2.fromOffset(4, 4 + (i - 1) * 25),
			UDim2.new(1, -8, 0, 24),

			function()
				priority = option
				priorityText.Text = option.Name .. "  \u{25be}"
				choices.Visible = false
			end
		)
	end

	label(f, "SkipLabel", "Skip frames", 12, 168, 86)
	local skip = Tool.field(
		f,
		"SkipFrames",
		raw.SkipFrames or 0,
		UDim2.fromOffset(100, 168),
		UDim2.fromOffset(56, 26)
	)
	require("NumericInput").bind(skip, { step = 1, min = 0, max = 120, integer = true })
	label(f, "StartLabel", "Playback start", 166, 168, 100)
	local start = Tool.field(
		f,
		"PlaybackStartFrame",
		raw.PlaybackStartFrame or 0,
		UDim2.fromOffset(272, 168),
		UDim2.fromOffset(76, 26)
	)
	require("NumericInput").bind(start, { step = 1, min = 0, max = 1000000, integer = true })
	local status = label(f, "Status", "", 12, 198, 336)
	status.TextSize = 11
	status.Visible = false
	local footer = panel(f, "Footer", 12, 198, 336, 36)
	footer.BackgroundTransparency = 1
	footer:FindFirstChildOfClass("UIStroke").Enabled = false
	Tool.button(footer, "Cancel", "CANCEL", UDim2.fromOffset(128, 4), UDim2.fromOffset(96, 28), function()
		w:close()
	end
)
	Tool.button(footer, "Apply", "APPLY", UDim2.fromOffset(232, 4), UDim2.fromOffset(104, 28), function()
		local ok, err = pcall(function()
			local rate = tonumber(fps.Text)
			assert(tonumber(skip.Text), "Enter a whole number for Skip frames.")
			assert(rate and rate >= 1, "Enter a valid FPS.")
			Files.applySettings(
				name.Text,
				Files.parseEnd(ending.Text, rate),
				rate,
				priority,
				stretch(),
				tonumber(skip.Text),
				assert(tonumber(start.Text), "Enter a whole number for Playback start.")
			)
		end)
		if ok then
			w:close()
		else
			status.Text = tostring(err):gsub("^.-:%d+: ", "")
			status.Visible = true
			f.Size = UDim2.fromOffset(360, 272)
			footer.Position = UDim2.fromOffset(12, 224)
		end
	end
)
	local cancel = f:FindFirstChild("Cancel", true)
	if cancel then
		cancel.BackgroundTransparency = 1
		cancel:SetAttribute("ThemeBg", nil)
	end

	local commit = f:FindFirstChild("Apply", true) or f:FindFirstChild("Import", true)
	if commit then
		commit:SetAttribute("ThemeBg", "MenuSel")
		commit:SetAttribute("Primary", true)
		Theme.applyTree(commit)
	end

	return w
end

local function applyImport(rig, sequence, options)
	assert(
		rig and rig.Parent and table.find(refs.State.getAllRigs(), rig),
		"Choose a rig already in this animation."
	)
	assert(
		sequence and sequence:IsA("KeyframeSequence") and #sequence:GetKeyframes() > 0,
		"Choose an animation to import."
	)
	local state = refs.State
	local tl = state.Timeline
	local before = snapshot({ rig })
	local documentId = Events.get(rig).DocumentId
	local oldExport = state.exportSequences[rig]

	local keepProperties = sequence:FindFirstChild("EclipseProperties") == nil
	local keepMaster = sequence:GetAttribute("EclipseMasterControl") == nil
	local protected = {}
	local Properties = require("Properties")
	local master = keepMaster and require("MasterControl").get(rig, true)
	for motor, bucket in before.buckets do
		if keepProperties and Properties.is(motor) or motor == master then
			protected[motor] = bucket
		end
	end

	local offset = options.paste and tl:TimeToFrame(before.time) or 0
	local ok, err = pcall(function()
		for motor in before.buckets do
			if not protected[motor] then
				tl:_restoreMotorBucket(motor, {})
			end
		end

		Events.restore(Events.subtitleTrack(), { Events = {} })
		Events.loadSubtitles(sequence, { DocumentId = documentId, IgnoreRecovery = true })
		refs.Project.importKeyframesFromSequence(rig, sequence, {
			KeepPropertyTracks = keepProperties,
			KeepMasterControl = keepMaster,
			KeepImportMotors = protected,
			EventOptions = { DocumentId = documentId, IgnoreRecovery = true },
		})
		local incoming = snapshot({ rig })
		for motor in protected do
			incoming.buckets[motor] = nil
		end

		local hasData = false
		for _, bucket in incoming.buckets do
			if next(bucket) then
				hasData = true
				break
			end
		end

		for _, track in incoming.events do
			if
				options.events and next(track.Events)
				or options.faces and next(track.FaceKeys or {})
			then
				hasData = true
			end
		end

		if options.events and next(incoming.subtitles.Events) then
			hasData = true
		end

		assert(hasData, "This animation has no matching tracks for the chosen rig.")
		incoming.name = before.name
		incoming.priority = before.priority
		incoming.time = before.time
		incoming.endFrame = before.endFrame
		for motor, bucket in incoming.buckets do
			local merged = options.paste and Scale.copyBucket(before.buckets[motor] or {}) or {}
			local group = options.group and Http:GenerateGUID(false)
			for frame, key in bucket do
				local target = frame + offset
				key.Frame, key.Time = target, target / before.fps
				if group then
					Groups.set(key, Groups.POSE, group)
				end

				merged[target] = key
				incoming.endFrame = math.max(incoming.endFrame, math.ceil(target))
			end

			incoming.buckets[motor] = merged
		end

		if options.paste then
			for motor, bucket in before.buckets do
				if not incoming.buckets[motor] then
					incoming.buckets[motor] = bucket
				end
			end
		end

		for motor, bucket in protected do
			incoming.buckets[motor] = bucket
		end

		for target, track in incoming.events do
			local previous = before.events[target] or { Events = {}, FaceKeys = {} }
			for field, enabled in { Events = options.events, FaceKeys = options.faces } do
				local keys = track[field] or {}
				local merged = {}
				if not enabled or options.paste then
					for id, key in previous[field] or {} do
						merged[id] = key
					end
				end

				if enabled then
					for _, key in keys do
						key.Frame += offset
						key.Id = Http:GenerateGUID(false)
						for id, old in merged do
							if old.Frame == key.Frame then
								merged[id] = nil
							end
						end

						merged[key.Id] = key
						incoming.endFrame = math.max(incoming.endFrame, key.Frame)
					end
				end

				track[field] = merged
			end

			track.Enabled = previous.Enabled ~= false
			track.FacesEnabled = options.faces
					and (track.FacesEnabled == true or next(track.FaceKeys) ~= nil)
				or previous.FacesEnabled == true
		end

		local captions = {}
		if not options.events or options.paste then
			for id, event in before.subtitles.Events do
				captions[id] = event
			end
		end

		if options.events then
			for _, event in incoming.subtitles.Events do
				event.Id = Http:GenerateGUID(false)
				event.Frame += offset
				captions[event.Id] = event
				incoming.endFrame =
					math.max(incoming.endFrame, event.Frame + event.Subtitle.Duration)
			end
		end

		incoming.subtitles.Events = captions
		restore(incoming)
		state.exportSequences[rig] = oldExport
		History.record(function()
			restore(before)
		end, function()
			restore(incoming)
		end, "Import to " .. rig.Name)
	end)
	state.exportSequences[rig] = oldExport
	if not ok then
		restore(before)
		error(err, 0)
	end
end

function Files.applyImport(rig, sequence, options)
    local native = Import.isR15(rig) and Import.nativeR15(sequence)
    local result = table.pack(pcall(applyImport, rig, native or sequence, options))
    if native then native:Destroy() end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

function Files.openImport()
	if not refs.State.Timeline or not refs.UI.AnimatorFrame.Visible then
		return
	end

	local w = create("EclipseImportToRig", "IMPORT TO RIG", Vector2.new(360, 466))
	local f = w.frame
	local target = Target.resolve(refs.State)
	local status = label(f, "Source", "Choose an animation", 12, 34, 336)
	local busy = false
	local selectedSource, sourceRows = nil, {}

	local function paintSources()
		for sequence, button in sourceRows do
			local active = sequence == selectedSource
			button:SetAttribute("ThemeBg", active and "MenuSel" or "TopBtn")
			button:SetAttribute("Primary", active)
			button:SetAttribute("Selected", active)
			Theme.applyTree(button)
		end
	end

	local function choose(kind, id)
		if busy then
			return
		end

		busy = true
		status.Text = "Loading animation..."
		task.spawn(function()
			local ok, result = pcall(function()
				if kind == "Roblox" then
					id = refs.Plugin:PromptForExistingAssetIdAsync("Animation")
					if not id or id <= 0 then
						return nil
					end
				end

				return Import.load(id, kind == "Avatar Shop")
			end)
			busy = false
			if w.closed then
				if ok and result then
					result:Destroy()
				end

				return
			end

			if ok and result then
				if staged then
					staged:Destroy()
				end

				staged = result
				status.Text = result.Name
				selectedSource = nil
				paintSources()
			elseif not ok then
				status.Text = tostring(result):gsub("^.-:%d+: ", "")
			else
				status.Text = staged and staged.Name or "Choose an animation"
			end
		end)
	end

	Tool.button(
		f,
		"Roblox",
		"CHOOSE ROBLOX ANIMATION...",
		UDim2.fromOffset(12, 62),
		UDim2.fromOffset(336, 26),

		function()
			choose("Roblox")
		end
	)
	local shop = Tool.field(f, "AssetId", "", UDim2.fromOffset(12, 96), UDim2.fromOffset(214, 26))
	shop.PlaceholderText = "Animation / emote ID or link"
	Tool.button(
		f,
		"AvatarShop",
		"LOAD ASSET",
		UDim2.fromOffset(234, 96),
		UDim2.fromOffset(114, 26),

		function()
			choose("Asset", shop.Text)
		end
	)
	local sources = panel(f, "SourcePanel", 12, 132, 336, 106)
	label(sources, "LocalLabel", "LOCAL ANIMATIONS \u{00B7} SELECT IN EXPLORER", 8, 3, 320).TextSize =
		10
	local sourceList = Tool.make("ScrollingFrame", sources, "Sequences", {
		Position = UDim2.fromOffset(5, 29),
		Size = UDim2.new(1, -10, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = f.ZIndex + 2,
	})
	Tool.make(
		"UIListLayout",
		sourceList,
		"Layout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	local revision = 0

	local function selectionChanged()
		revision += 1
		local request = revision
		task.spawn(function()
			local choices = Import.selectedSequences()
			if w.closed or request ~= revision then
				return
			end

			table.clear(sourceRows)
			for _, row in sourceList:GetChildren() do
				if row:IsA("GuiObject") then
					row:Destroy()
				end
			end

			local function selectSequence(sequence)
				if busy or w.closed then
					return
				end

				if not sequence.Parent then
					status.Text = "That sequence was removed."
					return
				end

				if staged then
					staged:Destroy()
				end

				staged = sequence:Clone()
				status.Text = sequence.Name
				selectedSource = sequence
				paintSources()
			end

			if #choices == 0 then
				label(
					sourceList,
					"Empty",
					"Select a sequence, rig, or animation folder.",
					4,
					0,
					312
				).TextSize =
					10
			end

			for i, sequence in choices do
				local button, title = Tool.button(
					sourceList,
					"Sequence" .. i,
					sequence.Name,
					UDim2.new(),
					UDim2.new(1, -8, 0, 25),

					function()
						selectSequence(sequence)
					end
				)
				button.LayoutOrder = i
				title.TextTruncate = Enum.TextTruncate.AtEnd
				sourceRows[sequence] = button
			end

			paintSources()
			if #choices == 1 then
				selectSequence(choices[1])
			end
		end)
	end

	table.insert(
		w.connections,
		game:GetService("Selection").SelectionChanged:Connect(selectionChanged)
	)
	selectionChanged()
	local targetPanel = panel(f, "TargetPanel", 12, 248, 336, 96)
	label(targetPanel, "TargetLabel", "TARGET RIG", 8, 3, 320)
	local list = Tool.make("ScrollingFrame", targetPanel, "Rigs", {
		Position = UDim2.fromOffset(5, 29),
		Size = UDim2.new(1, -10, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = f.ZIndex + 2,
	})
	Tool.make(
		"UIListLayout",
		list,
		"Layout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	local rows = {}

	local function paint()
		for rig, title in rows do
			title.Text = rig.Name
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Position = UDim2.fromOffset(8, 0)
			title.AnchorPoint = Vector2.zero
			title.Size = UDim2.new(1, -16, 1, 0)
			local button = title.Parent
			button.AutoButtonColor = false
			button.BackgroundTransparency = rig == target and 0 or 1
			button:SetAttribute("ThemeBg", rig == target and "MenuSel" or "Pnl")
			Theme.applyTree(button)
		end
	end

	for _, rig in refs.State.getAllRigs() do
		local _, title = Tool.button(list, rig.Name, "", UDim2.new(), UDim2.new(1, -8, 0, 28), function()
			target = rig
			paint()
		end
)
		rows[rig] = title
	end

	paint()
	local group, events, faces = segments(f)
	f.Options.Position = UDim2.fromOffset(12, 354)
	local paste = false
	local setReplace
	local setPaste

	local function mode(value)
		paste = value
		setReplace(not value)
		setPaste(value)
	end

	local getReplace
	local getPaste
	getReplace, setReplace = checkbox(f, "Replace", "Replace keys", 12, 392, true, 152, function()
		mode(false)
	end)
	getPaste, setPaste = checkbox(f, "Paste", "Paste at playhead", 174, 392, false, 174, function()
		mode(true)
	end)
	Tool.button(f, "Cancel", "CANCEL", UDim2.fromOffset(140, 426), UDim2.fromOffset(96, 28), function()
		w:close()
	end
)
	Tool.button(f, "Import", "IMPORT", UDim2.fromOffset(244, 426), UDim2.fromOffset(104, 28), function()
		if busy then
			return
		end

		busy = true
		local ok, err = pcall(
			Files.applyImport,
			target,
			staged,
			{ paste = paste, group = group(), events = events(), faces = faces() }
		)
		busy = false
		if ok then
			w:close()
			local previous = refs.State.ignoreSelectionChanged
			refs.State.ignoreSelectionChanged = true
			local cleared, selectionError = pcall(function()
				game:GetService("Selection"):Set({})
			end)
			refs.State.ignoreSelectionChanged = previous
			if not cleared then
				warn("Eclipse could not clear the import source: " .. tostring(selectionError))
			end

			require("UserInputService").focusEditor()
		else
			status.Text = tostring(err):gsub("^.-:%d+: ", "")
		end
	end
)
	local cancel = f:FindFirstChild("Cancel", true)
	if cancel then
		cancel.BackgroundTransparency = 1
		cancel:SetAttribute("ThemeBg", nil)
	end

	local commit = f:FindFirstChild("Apply", true) or f:FindFirstChild("Import", true)
	if commit then
		commit:SetAttribute("ThemeBg", "MenuSel")
		commit:SetAttribute("Primary", true)
		Theme.applyTree(commit)
	end

	return w
end

function Files.openSaveAs()
	if not refs.State.Timeline or not refs.UI.AnimatorFrame.Visible then
		return
	end

	local w = create(
		"EclipseSaveAs",
		"SAVE " .. string.upper(refs.Export.documentKind()) .. " AS",
		Vector2.new(360, 150)
	)
	local f = w.frame
	label(f, "NameLabel", "Name", 12, 38, 86)
	local name = Tool.field(
		f,
		"Name",
		refs.Export.resolveSaveName(refs.Project.getProjectExportName()),
		UDim2.fromOffset(100, 38),
		UDim2.fromOffset(248, 26)
	)
	local status = label(f, "Status", "", 100, 68, 248)
	status.TextSize = 11
	status.TextTransparency = 0.3
	status.Size = UDim2.fromOffset(248, 30)
	status.TextYAlignment = Enum.TextYAlignment.Top
	local saving = false

	local function preview()
		local typed = name.Text:match("^%s*(.-)%s*$")
		if typed == "" then
			status.Text = "Type a name for the copy."
			return
		end

		local resolved = refs.Export.resolveSaveName(typed)
		status.Text = if resolved ~= typed
			then 'That name is taken, so it will save as "' .. resolved .. '".'
			else "Saves a new copy. The original save stays as it is."
	end

	local function commit()
		if saving then
			return
		end

		if not name.Text:match("%S") then
			preview()
			return
		end

		saving = true
		local save = refs.Export.saveProjectAs(name.Text)
		saving = false
		if save then
			w:close()
		end
	end

	name:GetPropertyChangedSignal("Text"):Connect(preview)
	name.FocusLost:Connect(function(enter)
		if enter then
			commit()
		end
	end)
	preview()
	local footer = panel(f, "Footer", 12, 104, 336, 36)
	footer.BackgroundTransparency = 1
	footer:FindFirstChildOfClass("UIStroke").Enabled = false
	Tool.button(footer, "Cancel", "CANCEL", UDim2.fromOffset(128, 4), UDim2.fromOffset(96, 28), function()
		w:close()
	end
)
	Tool.button(footer, "Save", "SAVE", UDim2.fromOffset(232, 4), UDim2.fromOffset(104, 28), commit)
	local cancel = f:FindFirstChild("Cancel", true)
	if cancel then
		cancel.BackgroundTransparency = 1
		cancel:SetAttribute("ThemeBg", nil)
	end

	local primary = f:FindFirstChild("Save", true)
	if primary then
		primary:SetAttribute("ThemeBg", "MenuSel")
		primary:SetAttribute("Primary", true)
		Theme.applyTree(primary)
	end

	task.defer(function()
		if not name.Parent then
			return
		end

		name:CaptureFocus()
		name.SelectionStart = 1
		name.CursorPosition = #name.Text + 1
	end)
	return w
end

function Files.init(options)
	close()
	for _, c in lifetime do
		c:Disconnect()
	end

	table.clear(lifetime)
	refs = options

	local function watch(object, property, predicate)
		table.insert(
			lifetime,
			object:GetPropertyChangedSignal(property):Connect(function()
				if predicate() then
					close()
				end
			end)
		)
	end

	watch(refs.UI.AnimatorFrame, "Visible", function()
		return not refs.UI.AnimatorFrame.Visible
	end)
	watch(refs.UI.EclipseGUI, "Enabled", function()
		return not refs.UI.EclipseGUI.Enabled
	end)
	table.insert(lifetime, refs.UI.EclipseGUI.Destroying:Connect(close))
	if refs.Plugin then
		table.insert(lifetime, refs.Plugin.Unloading:Connect(close))
	end
end

Files.close = close
return Files
