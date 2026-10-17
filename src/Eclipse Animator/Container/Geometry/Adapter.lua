--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Drawings = require(script:FindFirstAncestor("Container").Shared.EclipseDrawing)
local Properties = require("Properties")
local Document = require("Document")
local Events = require("Events")
local History = require("History")
local Raw = require("RawState")
local Path = require("Path")
local Scene = require("motors")
local Cache = require("Cache")
local PhysicsScene = require("Scene")
local EffectModel = require("Model")
local Adapter = {}

local function retainSelection(state, raw)
	local rig, axis = state.Rig, state.Axis

	local function layerOf(motor)
		local owners = raw.AnimationLayers and raw.AnimationLayers.viewOwners
		return owners and owners[motor] and owners[motor].id or "base"
	end

	local keys, channels = {}, {}

	local function remember(out, key, value)
		out[#out + 1] =
			{ motor = key.Motor, frame = key.Frame, layer = layerOf(key.Motor), value = value }
	end

	for key, value in raw.SelectedKeyframes or {} do
		remember(keys, key, value)
	end

	for key, value in raw.SelectedChannelKeyframes or {} do
		remember(channels, key, table.clone(value))
	end

	local primary = {}
	if raw.SelectedKeyframe then
		remember(primary, raw.SelectedKeyframe, true)
	end

	local identities = {}

	local function identify(row)
		if not row then
			return nil
		end

		if identities[row] then
			return identities[row]
		end

		local identity = {
			row = row,
			kind = row.itemKind,
			source = row.linkedRigInstance,
			motor = row.fetchMotor and row:fetchMotor(),
			channel = row.channelId,
			subtitle = row.subtitleId,
		}
		identities[row] = identity
		identity.parent = identify(row.parentBoneItem)
		return identity
	end

	local selectedRows = rig and table.clone(rig._selectedItems or {}) or {}
	local selectedChannels = rig and table.clone(rig._selectedChannels or {}) or {}
	local last = rig and rig._lastClickedItem
	local bones = axis and axis.GetSelectedBones and table.clone(axis:GetSelectedBones()) or {}
	local boneRows = {}
	for _, item in rig and rig._orderedItems or {} do
		local bone = item.fetchBone and item:fetchBone()
		if bone then
			boneRows[bone] = item
		end
	end

	for row in selectedRows do
		identify(row)
	end

	for row in selectedChannels do
		identify(row)
	end

	for _, row in boneRows do
		identify(row)
	end

	identify(last)
	local explicit = rig and table.clone(rig._explicitSelectedKeys or {}) or {}
	return function()
		local function resolveKey(entry)
			local bucket = raw.Keyframes[entry.motor]
			return layerOf(entry.motor) == entry.layer and bucket and bucket[entry.frame] or nil
		end

		raw.SelectedKeyframes = {}
		raw.SelectedChannelKeyframes = {}
		for _, entry in keys do
			local key = resolveKey(entry)
			if key then
				raw.SelectedKeyframes[key] = entry.value
			end
		end

		for _, entry in channels do
			local key = resolveKey(entry)
			if key then
				raw.SelectedChannelKeyframes[key] = entry.value
			end
		end

		raw.SelectedKeyframe = primary[1] and resolveKey(primary[1])
			or next(raw.SelectedKeyframes)
			or next(raw.SelectedChannelKeyframes)

		local function resolveRow(old)
			if not old or not rig then
				return nil
			end

			local identity = identities[old]
			if not identity then
				return nil
			end

			local parent = identity.parent
			if parent then
				local resolved = resolveRow(parent.row)
				for _, row in resolved and resolved.transformChannelItems or {} do
					if row.channelId == identity.channel then
						return row
					end
				end

				return nil
			end

			local motor = identity.motor
			for _, row in rig._orderedItems or {} do
				if row == old then
					return row
				end

				if
					row.itemKind == identity.kind
					and row.linkedRigInstance == identity.source
					and row.subtitleId == identity.subtitle
					and (not motor or row.fetchMotor and row:fetchMotor() == motor)
				then
					return row
				end
			end

			return nil
		end

		if rig then
			rig._selectedItems = {}
			rig._selectedChannels = {}
			for old, value in selectedRows do
				local row = resolveRow(old)
				if row then
					rig._selectedItems[row] = value
				end
			end

			for old, value in selectedChannels do
				local row = resolveRow(old)
				if row then
					rig._selectedChannels[row] = value
				end
			end

			rig._lastClickedItem = resolveRow(last)
			rig._explicitSelectedKeys = {}
			for _, row in rig._orderedItems or {} do
				local source = row.linkedRigInstance
				if source and explicit[source] then
					rig._explicitSelectedKeys[source] = explicit[source]
				end
			end
		end

		local replacements, changed = {}, false
		for _, bone in bones do
			local row = resolveRow(boneRows[bone])
			local nextBone = row and row.fetchBone and row:fetchBone() or (bone.Parent and bone)
			if nextBone then
				table.insert(replacements, nextBone)
			end

			changed = changed or nextBone ~= bone
		end

		if axis then
			local current = axis:GetSelectedBones()
			changed = changed or #current ~= #replacements
			for i, bone in replacements do
				changed = changed or current[i] ~= bone
			end

			if changed then
				axis:SelectBones(replacements)
			end
		end

		if rig then
			if axis then
				rig._lastObservedSelectedBone = axis:GetSelectedBone()
			end

			if rig.RefreshHierarchySelectionVisuals then
				rig:RefreshHierarchySelectionVisuals()
			end
		end

		if state.Timeline.RefreshKeyframeSelectionVisuals then
			state.Timeline:RefreshKeyframeSelectionVisuals()
		end

		if state.Timeline.UpdateDeleteButtonState then
			state.Timeline:UpdateDeleteButtonState()
		end
	end
end

function Adapter.new(state)
	local self = { state = state, motors = {}, rigs = {}, signature = "" }
	local raw = state.Timeline:GetState()

	function self:refresh()
		self.motors, self.rigs = Scene.index(state)
		local ids = {}
		for id in self.motors do
			table.insert(ids, id)
		end

		table.sort(ids)
		self.signature = table.concat(ids, "\n")
	end

	self:refresh()

	function self:capture(budget)
		self:refresh()
		local values = {}
		Scene.writeProject(values, Scene.capture(state))
		local layered =
			require("layerStorage").captureLive(values, raw, self.motors, self.rigs, budget)
		for id, motor in self.motors do
			if layered then
				continue
			end

			for frame, key in raw.Keyframes[motor] or {} do
				values["k|" .. id .. "|" .. frame] = Document.packKey(key)
				if budget then
					budget()
				end
			end
		end

		for id, rig in self.rigs do
			local track = Events.snapshot(Events.get(rig))
			values["enabled|" .. id] = Document.pack(track.Enabled)
			values["faces|" .. id] =
				Document.pack({ Enabled = track.FacesEnabled, Keys = track.FaceKeys })
			for key, event in track.Events do
				values["e|" .. id .. "|" .. key] = Document.pack(event)
			end
		end

		for id, event in Events.snapshot(Events.subtitleTrack()).Events do
			values["sub|" .. id] = Document.pack(event)
		end

		values["drawing|document"] = Document.pack(raw.GreaseDrawings or Drawings.empty())
		for id, stroke in raw.GreaseStrokes or {} do
			values["p|" .. id] = Document.pack(stroke)
		end

		for id, effect in raw.ScreenEffects or {} do
			values["fx|" .. id] = Document.pack(effect)
		end

		local motorIds, rigIds = {}, {}
		for id, motor in self.motors do
			motorIds[motor] = id
		end

		for id, rig in self.rigs do
			rigIds[rig] = id
		end

		values.physicsSetup = Document.pack(PhysicsScene.liveSnapshot(state, motorIds, rigIds))
		for order, clip in Cache.list(raw) do
			local data = {
				id = clip.id,
				name = clip.name,
				first = clip.first,
				last = clip.last,
				settings = clip.settings,
				order = order,
				tracks = {},
			}
			for motor, keys in clip.tracks do
				local id = assert(motorIds[motor], "Waiting for shared physics track")
				local guides = {}
				for i, m in clip.guideMotors or {} do
					if m == motor then
						table.insert(guides, i)
					end
				end

				data.tracks[id] = {
					owner = rigIds[clip.owners and clip.owners[motor] or clip.rig],
					ragdoll = clip.ragdolls and clip.ragdolls[motor],
					guide = clip.guideMotor == motor,
					guides = guides,
				}
				for frame, key in keys do
					values["b|" .. clip.id .. "|" .. id .. "|" .. frame] = Document.packKey(key)
					if budget then
						budget()
					end
				end
			end

			values["q|" .. clip.id] = Document.pack(data)
		end

		values.settings = Document.pack({
			fps = raw.FPS,
			skipFrames = raw.SkipFrames or 0,
			startFrame = math.floor(state.Timeline:GetPlaybackStartTime() * raw.FPS + 0.5),
			finish = state.Timeline:GetMaxFrame(),
			loop = state.Timeline:IsLooping(),
		})
		return values
	end

	function self:applyKeys(values, previous, force, budget)
		local changedKeys = {}
		for key, value in values do
			if force or value ~= previous[key] then
				changedKeys[key] = true
			end
		end

		for key in previous do
			if values[key] == nil then
				changedKeys[key] = true
			end
		end

		local settings = Document.unpack(assert(values.settings, "Missing Live settings"))
		local layersChanged = force or changedKeys.animationLayers
		for key in changedKeys do
			if key:sub(1, 3) == "ak|" or key:sub(1, 3) == "ap|" then
				layersChanged = true
			end
		end

		local Layers = require("Layers")
		local beforeLayers = raw.AnimationLayers and Layers.snapshot(raw)
		local applyLayers = layersChanged
			and require("layerStorage").prepareLive(
				values,
				raw,
				self.motors,
				self.rigs,
				settings.fps,
				budget,
				not force and values.settings == previous.settings and previous or nil,
				state.Timeline
			)
		assert(
			type(settings.fps) == "number"
				and settings.fps >= 1
				and settings.fps <= 1000
				and settings.fps % 1 == 0,
			"Invalid Live FPS"
		)
		assert(
			type(settings.finish) == "number"
				and settings.finish >= 1
				and settings.finish <= 1000000,
			"Invalid Live duration"
		)
		settings.startFrame = settings.startFrame or 0
		assert(
			type(settings.startFrame) == "number"
				and settings.startFrame >= 0
				and settings.startFrame < settings.finish
				and settings.startFrame % 1 == 0,
			"Invalid Live playback start"
		)
		settings.skipFrames = settings.skipFrames or 0
		assert(
			type(settings.skipFrames) == "number"
				and settings.skipFrames >= 0
				and settings.skipFrames <= 120
				and settings.skipFrames % 1 == 0,
			"Invalid Live frame skip"
		)
		local patches, oldPatches, events, oldEvents = {}, {}, {}, {}
		local subtitleTrack = Events.subtitleTrack()
		local oldSubtitles = Events.snapshot(subtitleTrack)
		local subtitles = Events.snapshot(subtitleTrack)
		local subtitlesChanged = false
		if force then
			subtitles.Events = {}
			subtitlesChanged = true
		end

		for key in changedKeys do
			if key:sub(1, 4) == "sub|" then
				local id = key:sub(5)
				local event = values[key] and Document.unpack(values[key]) or nil
				assert(
					not event
						or type(event) == "table"
							and event.Id == id
							and type(event.Frame) == "number"
							and event.Frame >= 0
							and event.Frame % 1 == 0
							and event.Frame <= 1000000
							and type(event.Subtitle) == "table",
					"Invalid Live subtitle"
				)
				if event then
					event = {
						Id = id,
						Frame = event.Frame,
						Duration = 0,
						Speed = 1,
						Name = "Subtitle",
						Parameter = "",
						Markers = {},
						Sounds = {},
						Emits = {},
						CodeBegin = "",
						CodeEnd = "",
						Enabled = event.Enabled ~= false,
						Subtitle = require("SubtitleData").copy(event.Subtitle),
					}
				end

				subtitles.Events[id] = event
				subtitlesChanged = true
			end
		end

		local effects = table.clone(raw.ScreenEffects or {})
		local effectsChanged = false
		for key in changedKeys do
			if key:sub(1, 3) == "fx|" then
				effectsChanged = true
				effects[key:sub(4)] = values[key] and Document.unpack(values[key]) or nil
			end
		end

		if effectsChanged then
			effects = EffectModel.validateAll(effects)
		end

		local strokes = table.clone(raw.GreaseStrokes or {})
		local pencilChanged = false
		local physicsChanged = force == true
		for key in changedKeys do
			if key:sub(1, 2) == "q|" or key:sub(1, 2) == "b|" then
				physicsChanged = true
			end
		end

		local encodedKeys = {}
		for key in changedKeys do
			if key:sub(1, 2) == "k|" and values[key] then
				encodedKeys[key] = values[key]
			end
		end

		if physicsChanged then
			for key, value in values do
				if key:sub(1, 2) == "b|" then
					encodedKeys[key] = value
				end
			end
		end

		local decodedKeys = Document.unpackKeys(encodedKeys, budget)

		local function keyData(value, motor, frame, id)
			if not value then
				return false
			end

			local data = assert(decodedKeys[id], "Missing Live key")
			assert(type(data) == "table" and typeof(data.C0) == "CFrame", "Invalid Live key")
			data.Frame, data.Time, data.Motor, data.Part =
				frame, frame / settings.fps, motor, motor.Part1
			data.SanitizeName = state.UIHelpers.SanitizeName
			if Properties.is(motor) then
				local decoded = Properties.decode(motor, data.C0, data.PropertyValue)
				assert(Properties.validate(motor, decoded), "Invalid shared property value")
				Properties.prepare(motor, decoded)
				data.Channels = nil
				data.GraphCurves = nil
			end

			return data
		end

		for key in changedKeys do
			local value = values[key]
			local id, frame = key:match("^k|(.*)|([^|]+)$")
			if id then
				if values.animationLayers then
					continue
				end

				frame = tonumber(frame)
				assert(frame and frame >= 0 and frame <= 1000000, "Invalid Live key frame")
				local motor = self.motors[id]
				if motor then
					patches[motor] = patches[motor] or {}
					oldPatches[motor] = oldPatches[motor] or {}
					patches[motor][frame] = keyData(value, motor, frame, key)
					oldPatches[motor][frame] = (raw.Keyframes[motor] or {})[frame] or false
				end
			elseif key:sub(1, 2) == "p|" then
				strokes[key:sub(3)] = value and Document.unpack(value) or nil
				pencilChanged = true
			elseif key:sub(1, 2) == "q|" or key:sub(1, 2) == "b|" then
				physicsChanged = true
			else
				local rigId, eventId = key:match("^e|(.*)|([^|]+)$")
				rigId = rigId or key:match("^faces|(.*)$") or key:match("^enabled|(.*)$")
				if rigId and self.rigs[rigId] then
					if not events[rigId] then
						oldEvents[rigId] = Events.snapshot(Events.get(self.rigs[rigId]))
						events[rigId] = Events.snapshot(Events.get(self.rigs[rigId]))
					end

					local track = events[rigId]
					if eventId then
						local event = value and Document.unpack(value)
						assert(
							not event
								or type(event) == "table"
									and event.Id == eventId
									and type(event.Frame) == "number"
									and event.Frame >= 0
									and event.Frame % 1 == 0
									and event.Frame <= 1000000,
							"Invalid Live event"
						)
						track.Events[eventId] = event
					elseif key:sub(1, 6) == "faces|" then
						local faces = value and Document.unpack(value)
							or { Enabled = true, Keys = {} }
						assert(
							type(faces.Keys) == "table" and type(faces.Enabled) == "boolean",
							"Invalid Live faces"
						)
						for _, face in faces.Keys do
							assert(
								type(face.Image) == "string"
									and type(face.Frame) == "number"
									and face.Frame >= 0
									and face.Frame <= 1000000,
								"Invalid Live face"
							)
						end

						track.FacesEnabled = faces.Enabled
						track.FaceKeys = Events.copyFaces(faces.Keys)
					else
						track.Enabled = value and Document.unpack(value) or false
					end
				end
			end

			if budget then
				budget()
			end
		end

		if pencilChanged then
			Path.validate(strokes)
		end

		local applySetup, restoreSetup
		if values.physicsSetup and (force or values.physicsSetup ~= previous.physicsSetup) then
			local mi, ri = {}, {}
			for id, m in self.motors do
				mi[m] = id
			end

			for id, r in self.rigs do
				ri[r] = id
			end

			restoreSetup = PhysicsScene.prepareLive(
				state,
				PhysicsScene.liveSnapshot(state, mi, ri),
				self.motors,
				self.rigs
			)
			applySetup = PhysicsScene.prepareLive(
				state,
				Document.unpack(values.physicsSetup),
				self.motors,
				self.rigs
			)
		end

		local oldClips = Cache.list(raw)
		local clips = oldClips
		if physicsChanged then
			clips = {}
			local byId = {}
			for key, value in values do
				if key:sub(1, 2) == "q|" then
					local data = Document.unpack(value)
					assert(
						type(data.id) == "string"
							and data.first >= 0
							and data.last >= data.first
							and data.last <= 1000000,
						"Invalid Live physics clip"
					)
					local clip = {
						id = data.id,
						name = data.name,
						first = data.first,
						last = data.last,
						settings = data.settings,
						tracks = {},
						owners = {},
						ragdolls = {},
						guideMotors = {},
						order = data.order,
					}
					for id, descriptor in data.tracks do
						local motor = self.motors[id]
						if not motor or not self.rigs[descriptor.owner] then
							continue
						end

						local rig =
							assert(self.rigs[descriptor.owner], "Waiting for shared physics rig")
						clip.rig = clip.rig or rig
						clip.tracks[motor] = {}
						clip.owners[motor] = rig
						clip.ragdolls[motor] = descriptor.ragdoll
						if descriptor.guide then
							clip.guideMotor = motor
						end

						for _, i in descriptor.guides or {} do
							clip.guideMotors[i] = motor
						end
					end

					if next(clip.tracks) then
						byId[data.id] = clip
						table.insert(clips, clip)
					end
				end
			end

			for key, value in values do
				local clipId, id, frame = key:match("^b|([^|]+)|(.*)|([^|]+)$")
				if clipId and byId[clipId] then
					local motor = self.motors[id]
					local clip = byId[clipId]
					if not motor or not clip.tracks[motor] then
						continue
					end

					frame = tonumber(frame)
					assert(
						motor and clip.tracks[motor] and frame and frame >= 0 and frame <= 1000000,
						"Invalid Live physics track"
					)
					clip.tracks[motor][frame] = keyData(value, motor, frame, key)
					if budget then
						budget()
					end
				end
			end

			table.sort(clips, function(a, b)
				return (a.order or 0) < (b.order or 0)
			end)
		end

		local oldPlaying, oldTime, oldFPS, oldLength, oldLoop, oldSaved =
			raw.Playing,
			raw.CurrentTime,
			raw.FPS,
			Raw.Config.Length,
			state.Timeline:IsLooping(),
			state.currentProjectSaved
		local oldStartFrame = raw.PlaybackStartFrame
		local oldSkipFrames = raw.SkipFrames
		local oldDrawings = raw.GreaseDrawings
		local newDrawings = changedKeys["drawing|document"]
				and Drawings.validate(
					values["drawing|document"] and Document.unpack(values["drawing|document"])
						or Drawings.empty()
				)
			or nil
		local oldStrokes = raw.GreaseStrokes
		local oldEffects = raw.ScreenEffects

		local function patch(motor, changes)
			if state.Timeline._applyLiveKeyPatch then
				state.Timeline:_applyLiveKeyPatch(motor, changes)
			else
				local bucket = table.clone(raw.Keyframes[motor] or {})
				for frame, value in changes do
					bucket[frame] = value or nil
				end

				state.Timeline:_restoreMotorBucket(motor, bucket, true)
			end
		end

		local restoreSelection = retainSelection(state, raw)
		local ok, err = xpcall(function()
			local scaleChanged = raw.FPS ~= settings.fps
				or Raw.Config.Length ~= settings.finish / settings.fps
			if raw.FPS ~= settings.fps then
				state.Timeline:SetFPS(settings.fps, true)
			end

			Raw.Config.Length = settings.finish / settings.fps
			raw.SkipFrames = settings.skipFrames
			raw.PlaybackStartFrame = settings.startFrame
			state.Timeline:SetLooping(settings.loop == true)
			if layersChanged then
				if applyLayers then
					applyLayers()
				elseif raw.AnimationLayers then
					Layers.reset(raw)
					raw.Keyframes = {}
				end
			end

			for motor, changes in patches do
				patch(motor, changes)
				if state.Timeline.RefreshAllChannelDiamondsForMotor then
					state.Timeline:RefreshAllChannelDiamondsForMotor(motor)
				end
			end

			if physicsChanged then
				Cache.set(raw, clips)
			end

			if applySetup then
				applySetup()
			end

			for id, track in events do
				Events.restore(Events.get(self.rigs[id]), track)
			end

			if subtitlesChanged then
				Events.restore(subtitleTrack, subtitles)
			end

			if newDrawings then
				raw.GreaseDrawings = newDrawings
				state.Timeline._playbackEndAt = nil
			end

			if pencilChanged then
				raw.GreaseStrokes = strokes
				if state.GreasePencil then
					state.GreasePencil.refresh()
				end
			end

			if effectsChanged then
				raw.ScreenEffects = effects
				if state.ScreenEffects then
					state.ScreenEffects.refresh()
				end
			end

			raw.CurrentTime = oldTime * oldFPS / settings.fps
			raw.Playing = oldPlaying
			raw.LastPlaybackFrame = nil
			if scaleChanged and state.Timeline.RefreshTimelineScale then
				state.Timeline:RefreshTimelineScale()
			end

			if state.GraphEditor then
				state.GraphEditor.invalidate()
			end

			if state.currentRig and not oldPlaying then
				state.Timeline:ApplyPoseAtTime(state.currentRig, raw.CurrentTime)
			end

			if (next(events) or subtitlesChanged) and state.Timeline.RefreshEventRows then
				state.Timeline:RefreshEventRows()
			end

			if state.Rig and state.Rig.RefreshSelectionFilter then
				state.Rig:RefreshSelectionFilter()
			end

			if next(patches) or physicsChanged then
				state.Timeline:RefreshAllKeyframeVisuals()
			end

			state.currentProjectSaved = false
		end, debug.traceback)
		if not ok then
			if beforeLayers then
				Layers.restore(beforeLayers)
			else
				Layers.reset(raw)
			end

			raw.SkipFrames = oldSkipFrames
			raw.PlaybackStartFrame = oldStartFrame
			if raw.FPS ~= oldFPS then
				state.Timeline:SetFPS(oldFPS, true)
			end

			Raw.Config.Length = oldLength
			state.Timeline:SetLooping(oldLoop)
			for motor, changes in oldPatches do
				patch(motor, changes)
			end

			Cache.set(raw, oldClips)
			if restoreSetup then
				restoreSetup()
			end

			for id, track in oldEvents do
				Events.restore(Events.get(self.rigs[id]), track)
			end

			if subtitlesChanged then
				Events.restore(subtitleTrack, oldSubtitles)
			end

			raw.GreaseDrawings = oldDrawings
			raw.ScreenEffects = oldEffects
			if state.ScreenEffects then
				state.ScreenEffects.refresh()
			end

			raw.GreaseStrokes = oldStrokes
			raw.CurrentTime = oldTime
			raw.Playing = oldPlaying
			state.currentProjectSaved = oldSaved
			restoreSelection()
			error(err, 0)
		end

		restoreSelection()
		History.clear()
	end

	function self:apply(values, previous, budget)
		assert(values.project, "This Live session needs the current Eclipse version")
		if not Scene.projectChanged(values, previous) then
			return self:applyKeys(values, previous, false, budget)
		end

		local before = Scene.capture(state)
		local apply = Scene.prepare(state, Scene.readProject(values))
		local buckets = {}
		for motor in raw.DefaultPose do
			buckets[motor] = state.Timeline:_snapshotMotorBucket(motor)
		end

		local events = {}
		for _, rig in state.getAllRigs() do
			events[rig] = Events.snapshot(Events.get(rig))
		end

		events[Events.subtitleTrack().Rig] = Events.snapshot(Events.subtitleTrack())
		local restoreSelection = retainSelection(state, raw)
		local oldSaved, oldRig, oldPlaying =
			state.currentProjectSaved, state.currentRig, raw.Playing
		local ok, err = xpcall(function()
			apply()
			restoreSelection()
			self:refresh()
			self:applyKeys(values, previous, true, budget)
			raw.Playing = oldPlaying
		end, debug.traceback)
		if not ok then
			local recovered, failure = pcall(function()
				Scene.prepare(state, before)()
				self:refresh()
				for motor, bucket in buckets do
					if motor.Parent then
						state.Timeline:_restoreMotorBucket(motor, bucket)
					end
				end

				for rig, track in events do
					Events.restore(Events.get(rig), track)
				end

				state.currentProjectSaved, state.currentRig, raw.Playing =
					oldSaved, oldRig, oldPlaying
				if state.currentRig then
					state.Timeline:ApplyPoseAtTime(state.currentRig, raw.CurrentTime)
				end
			end)
			assert(recovered, tostring(err) .. "; project recovery failed: " .. tostring(failure))
			restoreSelection()
			error(err)
		end

		restoreSelection()
	end

	return self
end

return Adapter
