--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Drawings = require(script:FindFirstAncestor("Container").Shared.EclipseDrawing)
local Codec = require("Codec")
local Snapshot = require("snapshot")
local Paths = require("ClipboardRows")
local Camera = require("CameraRig")
local Properties = require("Properties")
local Objects = require("Objects")
local Events = require("Events")
local Cleanup = require("DumpStorage")
local Organization = require("Organization")
local Faces = require("Faces")
local Geometry = require("Geometry")
local Bake = {}

function Bake.withExportLock(refs, options, callback)
	local state = refs.State
	local timeline = state.Timeline
	local raw = timeline:GetState()
	if raw.Exporting and options._ExportToken == raw.Exporting then
		return callback()
	end

	assert(
		not timeline:IsExportLocked(),
		"A module export is already running. Wait for it to finish."
	)
	assert(
		not state.PhysicsSimulating,
		"Wait for the physics simulation to finish before exporting."
	)
	local token = {}
	local playing, time, recording = raw.Playing, raw.CurrentTime, raw.Recording
	local rig, save, sequence =
		state.currentRig, state.currentProjectSave, state.currentProjectSequence
	local active = not refs.Active or refs.Active()
	raw.Exporting = token
	options._ExportToken = token
	raw.Playing = false
	timeline._playbackPreparation = nil
	timeline._playbackReadyAt = nil
	local live = state.LiveSession
	local result = table.pack(xpcall(function()
		if refs.Finalize then
			refs.Finalize()
		end

		raw.Recording = false
		require("EventPlayback").stop()
		if live and live.beginExport then
			live.beginExport()
		end

		if state.BlenderBridge and state.BlenderBridge.waitForExport then
			state.BlenderBridge.waitForExport(options.IsCancelled)
		end

		assert(not options.IsCancelled or not options.IsCancelled(), "Export cancelled")
		assert(
			state.currentRig == rig and state.currentProjectSave == save,
			"The project changed during export"
		)
		return callback()
	end, debug.traceback))
	local sameProject = state.Timeline == timeline
		and state.currentRig == rig
		and state.currentProjectSave == save
		and state.currentProjectSequence == sequence
	local same = sameProject and (not active or not refs.Active or refs.Active())
	if sameProject then
		raw.Recording = recording
	end

	if same then
		raw.CurrentTime = time
		raw.Recording = recording
		raw.Playing = playing
		timeline._playbackReadyAt = os.clock()
		timeline._videoSampleAt = os.clock()
	end

	raw.Exporting = nil
	options._ExportToken = nil
	local restored, restoreError = pcall(function()
		if live and live.endExport then
			live.endExport(same)
		end

		if same then
			timeline:UpdatePlayhead()
		end
	end)
	assert(result[1], result[2])
	assert(restored, restoreError)
	return table.unpack(result, 2, result.n)
end

local function equal(a, b)
	if a == b then
		return true
	end

	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end

	for key, value in a do
		if not equal(value, b[key]) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function build(refs, options, progress)
	local state, timeline = refs.State, refs.State.Timeline
	local raw = timeline:GetState()
	assert(not raw.Playing, "Pause playback before exporting.")
	assert(
		not state.PhysicsSimulating,
		"Wait for the physics simulation to finish before exporting."
	)
	assert(
		not state.BlenderBridge or not state.BlenderBridge.isFollowing(),
		"Disconnect Blender Follow before exporting."
	)
	local shakeTime = raw.CurrentTime
	local fps = raw.FPS
	assert(type(fps) == "number" and fps >= 1 and fps <= 240, "FPS must be between 1 and 240")
	local last = options.LastFrame
	assert(
		type(last) == "number" and last % 1 == 0 and last >= 1 and last <= 144000,
		"End frame must be a whole number between 1 and 144,000"
	)
	local rigs = table.clone(state.getAllRigs())
	local selectedCamera = options.Camera
	if options.CameraMode == "Authored" then
		assert(
			selectedCamera
				and (Camera.isRig(selectedCamera) or selectedCamera:IsA("Camera"))
				and Organization.isEnabled(selectedCamera),
			"Choose an enabled timeline camera."
		)
	end

	local context = require("context").create(options, fps, last)
	local root = context.root
	local scene = context.scene
	local meshFolder = context.meshFolder
	local originals = context.originals
	local data = context.data
	data.GreaseDrawings = Drawings.copy(Drawings.validate(raw.GreaseDrawings or Drawings.empty()))
	data.SkipFrames = raw.SkipFrames or 0
	local surfaces = context.surfaces
	local sourceCode = context.sourceCode
	local ids = context.ids
	local copies = context.copies
	local scanQueue = context.scanQueue
	local rootKinds = context.rootKinds
	local objectQueue = context.objectQueue
	local code = context.code
	local reference = context.reference
	local addRoot = context.addRoot
	local archive
	local channels, channelIndex, meshIds = {}, {}, {}
	local restore
	local projectChanged = false
	local unsubscribe = require("History").subscribe(function()
		projectChanged = true
	end)

	local function checkProject(snapshot, time)
		local reason
		if projectChanged then
			reason = "animation history changed"
		elseif raw.CurrentTime ~= time then
			reason = "playhead changed from " .. tostring(time) .. " to " .. tostring(raw.CurrentTime)
		elseif raw.FPS ~= fps then
			reason = "FPS changed from " .. tostring(fps) .. " to " .. tostring(raw.FPS)
		else
			local matches, detail = snapshot:matches()
			if not matches then reason = detail or "scene properties changed" end
		end
		assert(not reason, "The project changed during export: " .. (reason or "unknown change") .. ". Your edit was kept; export again when ready.")
	end

	local function channel(source, property, kind, getter, smooth, attachmentCamera)
		local id = typeof(source) == "string" and source or ids[source]
		assert(id, "Unmapped animated object " .. tostring(source))
		local key = id .. ":" .. (kind or "Property") .. ":" .. property
		if channelIndex[key] then
			return
		end

		local row = {
			Target = id,
			Property = property,
			Kind = kind or "Property",
			Samples = {},
			Smooth = smooth ~= false,
		}
		table.insert(data.Tracks, row)
		local entry = {
			row = row,
			camera = attachmentCamera,
			get = getter or function()
				return source[property]
			end,
		}
		table.insert(channels, entry)
		channelIndex[key] = entry
	end

	local function mesh(source)
		local key = source.MeshId
		local existing = meshIds[key]
		if existing then
			return existing
		end

		local id = "Mesh" .. tostring(#meshFolder:GetChildren() + 1)
		local copy = Instance.new("MeshPart")
		copy.Name = id
		copy:ApplyMesh(source)
		copy.Parent = meshFolder
		meshIds[key] = id
		return id
	end

	local ok, message = xpcall(function()
		if progress then
			progress("Collecting project and actors…")
		end

		local armature = require("ArmatureRuntime")
		local hasArmature = false
		for _, rig in rigs do
			if Organization.isEnabled(rig) and armature.isRig(rig) then
				hasArmature = true
				break
			end
		end

		if hasArmature then
			if progress then
				progress("Resolving Blender render geometry…")
			end

			restore = Snapshot.new(rigs, raw, {})
			local slice = os.clock()
			local currentTime = raw.CurrentTime
			for frame = 0, last do
				assert(not options.IsCancelled or not options.IsCancelled(), "Export cancelled")
				if rigs[1] then
					timeline:ApplyPoseAtTime(rigs[1], frame / fps, { SkipControls = true })
				end

				if frame < last and os.clock() - slice > 0.08 then
					local snapshot = restore
					restore:restore()
					restore = nil
					if progress then
						progress(
							string.format("Resolving Blender geometry %d / %d", frame + 1, last + 1)
						)
					end

					task.wait()
					checkProject(snapshot, currentTime)
					restore = Snapshot.new(rigs, raw, {})
					slice = os.clock()
				end
			end

			restore:restore()
			restore = nil
		end

		for _, rig in rigs do
			if Organization.isEnabled(rig) then
				for _, surface in require("ArmatureRuntime").exportSurfaces(rig) do
					if not table.find(surfaces, surface) then
						table.insert(surfaces, surface)
					end
				end
			end
		end

		archive = refs.Archive()
		archive.Parent = root

		local ordered = table.clone(rigs)

		local function depth(object)
			local n = 0
			while object.Parent do
				n += 1
				object = object.Parent
			end

			return n
		end

		table.sort(ordered, function(a, b)
			return depth(a) < depth(b)
		end)
		for _, rig in ordered do
			if not Organization.isEnabled(rig) then
				continue
			end

			if rig.Parent == game or rig:IsA("Terrain") then
				context.nextId += 1
				ids[rig] = tostring(context.nextId)
				local record = { Id = ids[rig], Path = Codec.path(rig), Properties = {} }
				record.Reference = reference(rig)
				record.Selector = Codec.selector(rig)
				for _, motor in Properties.list(rig) do
					record.Properties[motor.PropertyId == "TimeOfDay" and "ClockTime" or motor.PropertyId] =
						true
				end

				table.insert(data.Globals, record)
			elseif rig:IsDescendantOf(game:GetService("Lighting")) then
				addRoot(rig, "Lighting")
			else
				addRoot(rig, Camera.isRig(rig) and "Camera" or "Actor")
			end
		end

		local lighting = game:GetService("Lighting")
		local lightingRecord
		for _, record in data.Globals do
			if record.Id == ids[lighting] then
				lightingRecord = record
				break
			end
		end

		if not lightingRecord then
			context.nextId += 1
			ids[lighting] = tostring(context.nextId)
			lightingRecord = { Id = ids[lighting], Path = { "Lighting" }, Properties = {} }
			table.insert(data.Globals, lightingRecord)
		end

		for _, key in
			{
				"Ambient",
				"Brightness",
				"ColorShift_Bottom",
				"ColorShift_Top",
				"EnvironmentDiffuseScale",
				"EnvironmentSpecularScale",
				"ExposureCompensation",
				"ClockTime",
				"GeographicLatitude",
				"GlobalShadows",
				"OutdoorAmbient",
				"FogEnd",
				"FogStart",
				"FogColor",
				"ShadowSoftness",
			}
		do
			lightingRecord.Properties[key] = true
			channel(lighting, key)
		end

		for _, object in lighting:GetChildren() do
			if object:IsA("PostEffect") or object:IsA("Atmosphere") or object:IsA("Sky") then
				if not ids[object] then
					addRoot(object, "Lighting")
				end
			end
		end

		for _, dependency in options.Dependencies or {} do
			if not ids[dependency] then
				assert(
					dependency:IsDescendantOf(workspace)
						or dependency:IsDescendantOf(game:GetService("ReplicatedStorage"))
						or dependency:IsDescendantOf(lighting)
						or dependency:IsDescendantOf(game:GetService("SoundService")),
					"Dependencies must be in Workspace, ReplicatedStorage, Lighting, or SoundService: "
						.. dependency:GetFullName()
				)
				addRoot(dependency, "Dependency")
			end
		end

		for _, surface in surfaces do
			if not ids[surface] then
				addRoot(surface, "Surface")
			end
		end

		for rig, track in Events.all() do
			if Events.isEnabled(track) then
				for _, event in track.Events do
					if event.Enabled ~= false then
						table.insert(scanQueue, { Source = event.CodeBegin or "", Rig = rig })
						table.insert(scanQueue, { Source = event.CodeEnd or "", Rig = rig })
					end
				end
			end
		end

		require("context").dependencies(context)
		local captureRoots = table.clone(rigs)
		for object, kind in rootKinds do
			if kind == "Bound" and not table.find(captureRoots, object) then table.insert(captureRoots, object) end
		end
		local referenceFields = context.referenceFields
		local boundLinks = {}
		local function bound(part)
			while part do
				if rootKinds[part] then return rootKinds[part] == "Bound" end
				part = part.Parent
			end
			return false
		end
		local linked
		repeat
			linked = false
			for source in copies do
				if not (source:IsA("JointInstance") or source:IsA("WeldConstraint")) or not source.Enabled or not source.Part0 or not source.Part1 then continue end
				for _, reverse in { false, true } do
					local parent = reverse and source.Part1 or source.Part0
					local child = reverse and source.Part0 or source.Part1
					if bound(child) and not boundLinks[child] and (not bound(parent) or boundLinks[parent]) then
						boundLinks[child] = { joint = source, parent = parent, reverse = reverse, offset = parent.CFrame:ToObjectSpace(child.CFrame) }
						linked = true
					end
				end
			end
		until not linked
		local function boundWorld(part, visiting)
			local link = boundLinks[part]
			if not link then return part.CFrame end
			visiting = visiting or {}
			assert(not visiting[part], "Cycle in bound export parts: " .. part:GetFullName())
			visiting[part] = true
			local joint = link.joint
			local offset = link.offset
			if joint:IsA("JointInstance") then
				offset = joint.C0 * (joint:IsA("Motor6D") and joint.Transform or CFrame.identity) * joint.C1:Inverse()
				if link.reverse then offset = offset:Inverse() end
			end
			local result = boundWorld(link.parent, visiting) * offset
			visiting[part] = nil
			return result
		end
		for source, copy in copies do
			local dependency = false
			local ancestor = source
			while ancestor do
				if rootKinds[ancestor] then
					dependency = rootKinds[ancestor] == "Dependency"
					break
				end

				ancestor = ancestor.Parent
			end

			if dependency then
				local editable = Geometry.mesh(source)
				if editable then
					data.Geometry[ids[source]] = Geometry.capture(editable)
				end
			end

			if not dependency then
				if source:IsA("BasePart") then
					for _, key in
						{
							"CFrame",
							"Size",
							"Color",
							"Transparency",
							"Reflectance",
							"Material",
							"MaterialVariant",
							"CastShadow",
						}
					do
						channel(source, key, nil, key == "CFrame" and boundLinks[source] and function() return boundWorld(source) end or nil)
					end

					channel(source, "LocalTransparencyModifier", nil, function()
						return table.find(surfaces, source) and source.Parent == nil and 1
							or source.LocalTransparencyModifier
					end, false)
					if source:IsA("MeshPart") then
						local editable = Geometry.mesh(source)
						if editable then
							local geometry = Geometry.capture(editable)
							data.Geometry[ids[source]] = geometry
							Geometry.channels(editable, geometry, function(key, getter, smooth)
								channel("Geometry:" .. ids[source], key, "Geometry", getter, smooth)
							end)
						else
							channel(source, "ApplyMesh", "Mesh", function()
								return mesh(source)
							end, false)
						end

						channel(source, "TextureID", nil, nil, false)
					end
				elseif source:IsA("Bone") then
					channel(source, "Transform")
					channel(source, "CFrame")
				elseif source:IsA("Attachment") then
					channel(source, "CFrame")
				elseif source:IsA("DataModelMesh") then
					for _, key in
						source:IsA("SpecialMesh") and {
							"Scale",
							"Offset",
							"VertexColor",
							"MeshId",
							"TextureId",
							"MeshType",
						} or { "Scale", "Offset", "VertexColor" }
					do
						channel(source, key)
					end
				elseif source:IsA("Decal") then
					for _, key in
						{ "Texture", "Color3", "Transparency", "LocalTransparencyModifier" }
					do
						channel(source, key)
					end
				end
			end

			for _, key in referenceFields(source) do
				local value = source[key]
				if value then
					if
						source:IsA("ObjectValue")
						and source.Name:sub(1, 7) == "Eclipse"
						and not copies[value]
					then
						copy[key] = nil
					elseif not copies[value] and not value:IsDescendantOf(game) then
						copy[key] = nil
					else
						assert(
							copies[value],
							"External reference "
								.. source:GetFullName()
								.. "."
								.. key
								.. " points outside exported actors/dependencies: "
								.. value:GetFullName()
						)
						copy[key] = copies[value]
					end
				end
			end
		end

		local faceRows = {}
		for _, rig in rigs do
			if ids[rig] and copies[rig] and Faces.supports(rig) then
				local track = Events.all()[rig]
				if track and track.FacesEnabled and next(track.FaceKeys or {}) then
					local head = rig:FindFirstChild("Head", true)
					local copyHead = copies[head]
					local face = copyHead and copyHead:FindFirstChild("face")
					if not face or not face:IsA("Decal") then
						face = nil
						for _, candidate in copyHead:GetChildren() do
							if candidate:IsA("Decal") and candidate.Face == Enum.NormalId.Front then
								face = candidate
								break
							end
						end
					end

					if not face then
						face = Instance.new("Decal")
						face.Name = "face"
						face.Face = Enum.NormalId.Front
						face.Parent = copyHead
						context.nextId += 1
						face:SetAttribute("EclipseExportId", tostring(context.nextId))
					end

					local original = head:FindFirstChild(face.Name)
					local base = Faces.originalPresentation(rig, original)
					local id = face:GetAttribute("EclipseExportId")
					local row = { track = track, base = base, values = table.clone(base) }
					table.insert(faceRows, row)
					for property, value in base do
						face[property] = value
						local getter = function()
							return row.values[property]
						end

						local old = channelIndex[id .. ":Property:" .. property]
						if old then
							old.get = getter
							old.row.Smooth = false
						else
							channel(id, property, nil, getter, false)
						end
					end
				end
			end
		end

		for _, rig in rigs do
			if not ids[rig] then
				continue
			end

			local controls = Properties.faceControls(rig)
			if controls and controls ~= rig then
				for _, motor in Properties.list(rig) do
					if motor.Definition.facial then
						local name = motor.PropertyId:sub(14)
						channel(controls, name)
					end
				end
			end
			if Objects.is(rig) then
				table.insert(data.Effects, ids[rig])
				if Objects.kind(rig) == "Letterbox" then
					local target
					for _, camera in rigs do
						if
							Camera.isRig(camera)
							and camera:GetAttribute("EclipseTrackId")
								== rig:GetAttribute("EffectCameraId")
						then
							target = camera
							break
						end
					end

					assert(target, "Letterbox " .. rig.Name .. " has no valid camera binding")
					local cameraId = "EffectCamera:" .. ids[rig]
					data.EffectCameras[ids[rig]] = {
						Target = cameraId,
						Selected = options.CameraMode == "Authored" and selectedCamera == target,
					}
					channel(cameraId, "View", nil, function()
						return Camera.viewFrame(target, nil, shakeTime)
							* (
								state.ScreenEffects
									and state.ScreenEffects.shake(shakeTime, true, target)
								or CFrame.identity
							)
					end, nil, target)
					channel(cameraId, "FOV", nil, function()
						return Camera.fov(target)
					end)
				end

				for _, definition in Objects.catalog(rig) do
					if
						definition.id == "TopSize"
						or definition.id == "BottomSize"
						or definition.id == "VFXSize"
					then
						continue
					end

					local id = definition.id
					channel(rig, "Effect" .. id, "Attribute", function()
						return Objects.read(rig, id)
					end)
				end
			else
				for _, motor in Properties.list(rig) do
					local id = motor.PropertyId
					if rig:IsA("Model") or motor.Definition.facial or motor.Definition.trigger then
						continue
					end

					if id == "ApplyMesh" then
						Properties.prepare(motor, Properties.readValue(rig, id))
						continue
					end

					local key = id == "ApplyTexture" and "TextureID"
						or id == "TimeOfDay" and "ClockTime"
						or id
					channel(rig, key, nil, function()
						return Properties.readValue(rig, id)
					end)
				end
			end
		end

		if state.ScreenEffects then
			local function offset()
				return options.CameraMode == "Authored"
						and state.ScreenEffects.shake(shakeTime, true, selectedCamera)
					or CFrame.identity
			end

			channel("CameraShake", "View", nil, offset)
			channel("CameraShake", "CFrame", nil, function()
				local delta = offset()
				if
					options.CameraMode == "Authored"
					and Camera.isRig(selectedCamera)
					and selectedCamera:GetAttribute("EclipseOrthographic") == true
				then
					local base = Camera.renderFrame(selectedCamera, nil, true, shakeTime)
					local shaken = require("fov").render(
						Camera.viewFrame(selectedCamera, nil, shakeTime) * delta,
						Camera.fov(selectedCamera),
						true
					)
					return base:ToObjectSpace(shaken)
				end

				return delta
			end)
		end

		local projection = {}
		local fixed = workspace.CurrentCamera
		if options.CameraMode == "Studio" then
			assert(fixed, "No Studio camera exists")
			projection.cf, projection.fov, projection.focus =
				fixed.CFrame, fixed.FieldOfView, fixed.Focus
		end

		if options.CameraMode ~= "Game" then
			channel("Camera", "CFrame", nil, function()
				return projection.cf
			end)
			channel("Camera", "FieldOfView", nil, function()
				return projection.fov
			end)
			channel("Camera", "Focus", nil, function()
				return projection.focus
			end)
			channel("Projection", "View", nil, function()
				return projection.view or projection.cf
			end)
			channel("Projection", "FOV", nil, function()
				return projection.authoredFov or projection.fov
			end)
			channel("Projection", "Enabled", nil, function()
				return options.CameraMode == "Authored"
					and selectedCamera:GetAttribute("EclipseOrthographic") == true
			end, false)
		end

		for rig, track in Events.all() do
			if Events.isEnabled(track) then
				for _, event in track.Events do
					if event.Enabled ~= false then
						if event.Subtitle then
							table.insert(data.Subtitles, {
								id = track.DocumentId .. ":" .. event.Id,
								event = { Frame = event.Frame, Subtitle = event.Subtitle },
							})
						end

						if
							event.CodeBegin ~= ""
							or event.CodeEnd ~= ""
							or #(event.Sounds or {}) > 0
							or #Events.markers(event) > 0
						then
							assert(
								ids[rig] or track.ProjectSubtitles,
								"Event rig is not exported: " .. rig.Name
							)
							local copy = table.clone(event)
							copy.Button = nil
							copy.CodeBegin = nil
							copy.CodeEnd = nil
							copy.Subtitle = nil
							copy.Emits = nil
							copy.Sounds = {}
							local SoundData = require("SoundData")
							for _, sound in SoundData.copy(event.Sounds) do
								if sound.AudioId == "" then
									continue
								end

								assert(
									not require("LocalAudio").is(sound.AudioId),
									"Local audio in event "
										.. event.Name
										.. " is for Studio preview. Replace it with a Roblox audio ID before exporting the cutscene."
								)
								local asset = SoundData.asset(sound.AudioId)
								assert(asset, "Invalid audio ID in event " .. event.Name)
								sound.AudioId = asset
								table.insert(copy.Sounds, sound)
							end

							table.insert(data.Events, {
								Id = track.DocumentId .. ":" .. event.Id,
								Rig = ids[rig],
								Frame = event.Frame,
								Speed = Events.speed(event, fps),
								Data = copy,
								Markers = Events.markers(event),
								Begin = code(event.CodeBegin, event.Name .. " begin"),
								End = code(event.CodeEnd, event.Name .. " end"),
							})
						end
					end
				end
			end
		end

		local contentLast =
			math.max(timeline:GetLastKeyframeFrame() or 0, Drawings.lastFrame(data.GreaseDrawings))
		for _, clip in require("Cache").list(raw) do
			contentLast = math.max(contentLast, clip.last)
		end

		for _, rig in rigs do
			local track = Events.all()[rig]
			if track and track.FacesEnabled and Organization.isEnabled(rig) then
				for _, faceKey in track.FaceKeys or {} do
					contentLast = math.max(contentLast, faceKey.Frame)
				end
			end
		end

		for _, event in data.Events do
			contentLast = math.max(contentLast, event.Frame + (event.Data.Duration or 0))
		end

		for _, row in data.Subtitles do
			contentLast = math.max(contentLast, row.event.Frame + row.event.Subtitle.Duration)
		end

		for _, effect in raw.ScreenEffects or {} do
			if effect.enabled ~= false then
				contentLast = math.max(contentLast, effect.start + effect.duration)
			end
		end

		data.ContentLastFrame = math.clamp(contentLast, 0, last)
		table.sort(data.Subtitles, function(a, b)
			if a.event.Subtitle.Order ~= b.event.Subtitle.Order then
				return a.event.Subtitle.Order < b.event.Subtitle.Order
			end

			return a.id < b.id
		end)
		assert(
			#channels * (last + 1) <= 12000000,
			"This export is too large ("
				.. #channels
				.. " channels × "
				.. (last + 1)
				.. " frames). Shorten the range or split the cutscene."
		)
		if progress then
			progress("Baking " .. (last + 1) .. " frames at " .. fps .. " FPS…")
		end

		for motor, bucket in require("Layers").allTracks(raw) do
			if Properties.is(motor) and motor.PropertyId == "ApplyMesh" then
				for _, key in bucket do
					Properties.prepare(
						motor,
						Properties.decode(motor, key.CFrame or key.C0, key.PropertyValue)
					)
				end
			end
		end

		restore = Snapshot.new(captureRoots, raw, surfaces)
		local slice = os.clock()
		local lastTime = raw.CurrentTime
		local frameSet = {}
		for frame = 0, last do
			frameSet[frame] = true
		end

		for motor, bucket in require("Layers").allTracks(raw) do
			require("Mods").bakeBoundaries(motor, bucket, last, function(f)
				frameSet[f] = true
			end)
		end

		local sampleFrames = {}
		for f in frameSet do
			table.insert(sampleFrames, f)
		end

		table.sort(sampleFrames)
		for _, frame in sampleFrames do
			assert(not options.IsCancelled or not options.IsCancelled(), "Export cancelled")
			local time = frame / fps
			shakeTime = time
			if rigs[1] then
				timeline:ApplyPoseAtTime(rigs[1], time, { SkipControls = true })
			end

			for _, rig in rigs do
				if
					rig:IsA("Model")
					and not Camera.isRig(rig)
					and not require("ArmatureRuntime").isRig(rig)
				then
					require("RigPose").assemble(rig)
				end
			end

			for _, rig in rigs do
				if ids[rig] and Objects.kind(rig) == "Letterbox" then
					local target
					for _, camera in rigs do
						if
							Camera.isRig(camera)
							and camera:GetAttribute("EclipseTrackId")
								== rig:GetAttribute("EffectCameraId")
						then
							target = camera
							break
						end
					end

					assert(target, "Letterbox " .. rig.Name .. " has no valid camera binding")
					Objects.follow(rig, {
						cf = Camera.viewFrame(target, nil, shakeTime)
							* (
								state.ScreenEffects
									and state.ScreenEffects.shake(time, true, target)
								or CFrame.identity
							),
						fov = Camera.fov(target),
					}, {
						Playing = true,
						CurrentTime = time,
						Keyframes = raw.Keyframes,
						DefaultPose = raw.DefaultPose,
					})
				end
			end

			if options.CameraMode == "Authored" then
				if selectedCamera:IsA("Camera") then
					projection.cf, projection.fov, projection.focus =
						selectedCamera.CFrame, selectedCamera.FieldOfView, selectedCamera.Focus
				else
					projection.cf, projection.fov, projection.focus =
						Camera.renderFrame(selectedCamera, nil, true, shakeTime)
					projection.view, projection.authoredFov =
						Camera.viewFrame(selectedCamera, nil, shakeTime), Camera.fov(selectedCamera)
				end
			end

			for _, row in faceRows do
				local image = Faces.sample(row.track, frame)
				local active = image ~= nil and image ~= ""
				row.values.Texture = active and image or row.base.Texture
				row.values.Transparency = active and 0 or row.base.Transparency
				row.values.LocalTransparencyModifier = active and 0
					or row.base.LocalTransparencyModifier
				row.values.Face = active and Enum.NormalId.Front or row.base.Face
			end

			for _, entry in channels do
				local value = entry.get()
				assert(value ~= nil, "Cannot sample " .. entry.row.Property)
				local samples = entry.row.Samples
				local n = #samples
				local camera = entry.camera
					or entry.row.Target == "Camera" and entry.row.Property ~= "FieldOfView" and selectedCamera
					or entry.row.Target == "Projection"
						and entry.row.Property == "View"
						and selectedCamera
				if camera and Camera.isRig(camera) and frame > 0 then
					local target = require("Target")
					if
						target.attachmentObject(camera, (frame - 1) / fps)
							~= target.attachmentObject(camera, time)
						and n > 0
						and not equal(samples[n][2], value)
					then
						table.insert(samples, { frame, samples[n][2] })
						table.insert(samples, { frame, value })
						continue
					end
				end

				if n >= 2 and equal(samples[n][2], value) and equal(samples[n - 1][2], value) then
					samples[n][1] = frame
				else
					table.insert(samples, { frame, value })
				end
			end

			if frame < last and os.clock() - slice > 0.08 then
				local snapshot = restore
				restore:restore()
				restore = nil
				if progress then
					progress(
						string.format(
							"Baking %d / %d frames · %d FPS",
							math.floor(frame) + 1,
							last + 1,
							fps
						)
					)
				end

				task.wait()
				checkProject(snapshot, lastTime)
				local present = state.getAllRigs()
				assert(#present == #rigs, "Project membership changed during export")
				for i, rig in rigs do
					assert(present[i] == rig and rig.Parent, "An actor changed during export")
				end

				restore = Snapshot.new(captureRoots, raw, surfaces)
				slice = os.clock()
			end
		end

		assert(raw.CurrentTime == lastTime, "The project playhead changed during export")
		restore:restore()
		restore = nil

		for _, track in data.Tracks do
			if #track.Samples == 2 and equal(track.Samples[1][2], track.Samples[2][2]) then
				table.remove(track.Samples)
			end
		end

		local unused = {}
		for _, surface in surfaces do
			local id = ids[surface]
			local visible = false
			local entry = channelIndex[id .. ":Property:LocalTransparencyModifier"]
			if entry then
				for _, sample in entry.row.Samples do
					if sample[2] < 1 then
						visible = true
						break
					end
				end
			end

			if not visible and copies[surface] then
				local copy = copies[surface]
				unused[id] = true
				for _, child in copy:GetDescendants() do
					local childId = child:GetAttribute("EclipseExportId")
					if childId then
						unused[childId] = true
					end
				end

				copy:Destroy()
			end
		end

		for id in unused do
			data.Geometry[id] = nil
		end

		for i = #data.Tracks, 1, -1 do
			local target = data.Tracks[i].Target
			if unused[target] or unused[target:match("^Geometry:(.+)$")] then
				table.remove(data.Tracks, i)
			end
		end

		for i = #data.Roots, 1, -1 do
			if unused[data.Roots[i].Id] then
				table.remove(data.Roots, i)
			end
		end

		for _, binding in data.Bindings do
			for i = #binding.Nodes, 1, -1 do
				if unused[binding.Nodes[i].Id] then
					table.remove(binding.Nodes, i)
				end
			end
		end

		Codec.encode(data.Events)
		Codec.encode(data.Subtitles)
	end, debug.traceback)
	local restored, restoreError = true, nil
	if restore then
		restored, restoreError = pcall(function()
			restore:restore()
		end)
	end

	unsubscribe()
	if not ok or not restored then
		root:Destroy()
		error(
			(not ok and tostring(message) or "")
				.. (not restored and "\n" .. tostring(restoreError) or ""),
			2
		)
	end

	return root, data, sourceCode
end

function Bake.build(refs, options, progress)
	return Bake.withExportLock(refs, options, function()
		local raw = refs.State.Timeline:GetState()

		local recording = raw.Recording
		raw.Recording = false
		local result = table.pack(xpcall(function()
			return require("Cache").withPreview(raw, function()
				return build(refs, options, progress)
			end)
		end, debug.traceback))
		raw.Recording = recording
		assert(result[1], result[2])
		return table.unpack(result, 2, result.n)
	end)
end

return Bake
