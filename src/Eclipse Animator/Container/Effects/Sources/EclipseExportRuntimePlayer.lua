--!nocheck
--// cracked by numan

return function(require)
	local Run = game:GetService("RunService")
	local Players = game:GetService("Players")
	local ContentProvider = game:GetService("ContentProvider")
	local Subtitles = require("../Subsystems/SubtitleRenderer")
 local Drawings = require("../Shared/EclipseDrawing")
	local Effects = require("../Helpers/EffectObjects")
	local Layer = require("../Helpers/EffectLayer")
	local Letterbox = require("./Letterbox")
	local Projection = require("../Helpers/CameraProjection")
	local Geometry = require("./Geometry")
	local Preload = require("./Preload")
	local Paths = require("../Helpers/EmitData")
	local Player = {}
	Player.__index = Player
	local function onRender(callback)
		local name = "EclipseCutscene_" .. game:GetService("HttpService"):GenerateGUID(false)
		local connected = true
		Run:BindToRenderStep(name, Enum.RenderPriority.Last.Value + 10, callback)
		return {
			Disconnect = function()
				if connected then
					connected = false
					Run:UnbindFromRenderStep(name)
				end
			end,
		}
	end
	local registry = shared.EclipseCutsceneRuntimeV1
	if not registry then
		registry = {}
		shared.EclipseCutsceneRuntimeV1 = registry
	end
	local function resolve(path)
		local object = game
		for _, name in path do
			object = object:FindFirstChild(name)
			if not object then
				return
			end
		end
		return object
	end
	local function resolveTyped(root, path)
		local object = root
		for _, step in path do
			local found
			for _, child in object:GetChildren() do
				if
					child.Name == step.Name
					and child.ClassName == step.Class
					and (not step.TrackId or child:GetAttribute("EclipseTrackId") == step.TrackId)
				then
					if found then
						return
					end
					found = child
				end
			end
			if not found then
				return
			end
			object = found
		end
		return object
	end
	function Player:_original(id)
		local folder = self.package:FindFirstChild("Originals")
		local reference = id and folder and folder:FindFirstChild(id)
		local object = reference and reference:IsA("ObjectValue") and reference.Value
		if object and object:IsDescendantOf(game) and not object:IsDescendantOf(self.package) then
			return object
		end
	end
	function Player:_resolve(record)
		local object = self:_original(record.Reference)
		if object then
			return object
		end
		if record.Selector then
			return resolveTyped(game, record.Selector)
		end
		return resolve(record.Path)
	end
	local function sample(samples, frame, smooth)
		local low, high = 1, #samples
		while low < high do
			local mid = math.ceil((low + high) / 2)
			if samples[mid][1] <= frame then
				low = mid
			else
				high = mid - 1
			end
		end
		local a, b = samples[low], samples[low + 1]
		if not smooth or not b or frame <= a[1] then
			return a[2]
		end
		local x, y, t = a[2], b[2], math.clamp((frame - a[1]) / (b[1] - a[1]), 0, 1)
		local kind = typeof(x)
		if kind == "number" then
			return x + (y - x) * t
		end
		if
			kind == "CFrame"
			or kind == "Vector3"
			or kind == "Vector2"
			or kind == "Color3"
			or kind == "UDim2"
		then
			return x:Lerp(y, t)
		end
		return x
	end
	local function signal()
		local event = Instance.new("BindableEvent")

		return event, event.Event
	end
	function Player:_remember(object, key)
		local fields = self.saved[object]
		if not fields then
			fields = {}
			self.saved[object] = fields
		end
		if fields[key] == nil then
			fields[key] = { object[key] }
		end
	end
	function Player:_write(object, key, value)
		self:_remember(object, key)
		object[key] = value
	end
	function Player:_hideOriginal(object)
		if object:IsA("BasePart") then
			self:_write(object, "LocalTransparencyModifier", 1)
		elseif object:IsA("Decal") then
			self:_write(object, "Transparency", 1)
		elseif
			object:IsA("ParticleEmitter")
			or object:IsA("Beam")
			or object:IsA("Trail")
			or object:IsA("Light")
			or object:IsA("SurfaceGui")
			or object:IsA("BillboardGui")
			or object:IsA("Highlight")
		then
			self:_write(object, "Enabled", false)
		elseif object:IsA("GuiBase3d") then
			self:_write(object, "Visible", false)
		end
	end
	function Player:_camera()
		if self.data.CameraMode == "Game" then
			return
		end
		local camera = workspace.CurrentCamera
		assert(camera, "The game has no CurrentCamera")
		if camera ~= self.camera then
			self.camera = camera
			for _, key in
				{
					"CameraType",
					"CameraSubject",
					"CFrame",
					"Focus",
					"FieldOfView",
					"FieldOfViewMode",
				}
			do
				self:_remember(camera, key)
			end
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
		return camera
	end
	function Player:_clearShake()
  local previous=self.shakeCamera
  if previous and previous.Parent and previous.CFrame==self.shakeApplied then previous.CFrame=self.shakeBase end
  if self.projection and self.projection.View==self.shakeProjectionApplied then self.projection.View=self.shakeProjectionBase end
  self.shakeProjectionBase=nil;self.shakeProjectionApplied=nil
  self.shakeCamera=nil;self.shakeApplied=nil;self.shakeBase=nil
 end
	function Player:_pose(frame)
		local displayFrame = frame
		local skip = self.data.SkipFrames or 0
		if type(skip) == "number" and skip > 0 and skip <= 120 and skip % 1 == 0 then
			frame = math.floor((math.max(0, frame) + 1e-7) / (skip + 1)) * (skip + 1)
		end
  self:_clearShake()
  self.shake=self.shake or {};self.shake.CFrame=CFrame.identity;self.shake.View=CFrame.identity
		local camera = self:_camera()
		for _, track in self.data.Tracks do
			local object = track.Target=="CameraShake" and self.shake or track.Target == "Camera" and camera or self.objects[track.Target]
			if object then
				if #track.Samples == 1 and self.applied[track] and track.Target ~= "Camera" and track.Target~="CameraShake" then
					continue
				end
				local value = sample(
					track.Samples,
					frame,
					self.options.Interpolate ~= false and track.Smooth ~= false
				)
				if track.Kind == "Geometry" then
					Geometry.apply(object, track.Property, value)
				elseif track.Kind == "Attribute" then
					object:SetAttribute(track.Property, value)
				elseif track.Kind == "Mesh" then
					if self.meshes[object] ~= value then
						local template = self.package.Meshes:FindFirstChild(value)
						assert(template, "Missing baked mesh: " .. value)
						local size, texture = object.Size, object.TextureID
						object:ApplyMesh(template)
						object.Size = size
						object.TextureID = texture
						self.meshes[object] = value
					end
				else
					object[track.Property] = value
				end
				self.applied[track] = true
			end
		end
		local shakeCamera=camera or workspace.CurrentCamera
  local delta=self.data.CameraMode=='Game'and self.shake.View or self.shake.CFrame
  if shakeCamera and delta~=CFrame.identity then
   self.shakeBase=shakeCamera.CFrame;self.shakeCamera=shakeCamera
   shakeCamera.CFrame*=delta;self.shakeApplied=shakeCamera.CFrame
   if self.projection.View then self.shakeProjectionBase=self.projection.View;self.projection.View*=self.shake.View;self.shakeProjectionApplied=self.projection.View end
  end
		Projection.View = self.projection.View
		Projection.FOV = self.projection.FOV
		Projection.Enabled = self.projection.Enabled
		self.Frame = displayFrame
	end
	function Player:_visuals(frame)
		if self.letterbox then
			self.letterbox(frame, self.options.Interpolate ~= false, self.camera, self.projection)
		end
		for _, entry in self.effects do
			local object = entry.object
			if Effects.kind(object)=="Camera Shake"then continue end
			local visible = Effects.read(object, "Enabled") ~= false
			if entry.overlay then
				Effects.paintOverlay(object, entry.overlay, visible)
			else
				Effects.paint(object, visible, frame / self.data.FPS)
			end
		end
		self.subtitles:step(self.data.Subtitles, frame, self.data.FPS)
 if self.drawings then self.drawings:step(self.data.GreaseDrawings or Drawings.empty(), frame, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.identity, true) end
	end
	function Player:_due(target, seeking)
		local generation = self.generation
		while self.due[self.nextEvent] and self.due[self.nextEvent].time <= target + 1e-8 do
			local entry = self.due[self.nextEvent]
			self.nextEvent += 1
			local event = entry.event
			local rig = self.objects[event.Rig]
			local context = self.contexts[event.Id] or {}
			self.contexts[event.Id] = context
			if entry.phase == "Begin" and not seeking then
				for _, marker in event.Markers do
					self.marker:Fire(marker.Name, marker.Parameter, event.Frame)
				end
			end
			if self.generation ~= generation then
				return false
			end
			local factory = event[entry.phase]
			if factory and not seeking then
				local create = self.factories and self.factories[factory]
				assert(create, "Missing exported event " .. tostring(factory))
				task.spawn(create(), rig, table.clone(event.Data), event.Data.Parameter, context)
			end
			if self.generation ~= generation then
				return false
			end
		end
		return true
	end
	function Player:_audio(playing)
		for _, entry in self.sounds do
			local elapsed = self.Time - entry.start
			local sound = entry.sound
			local offset = elapsed * entry.speed
			local present = elapsed >= 0 and sound.TimeLength > 0 and (sound.Looped or offset < sound.TimeLength)
            if sound.Looped and sound.TimeLength > 0 then offset %= sound.TimeLength end
			if not present then
				sound:Stop()
			else
				if math.abs(sound.TimePosition - offset) > 0.12 or not sound.Playing then
					sound.TimePosition = offset
				end
				sound.PlaybackSpeed = entry.speed
				if playing then
					if not sound.Playing then
						sound:Resume()
					end
				else
					sound:Pause()
				end
			end
		end
		for sound, entry in self.soundStates or {} do
			if sound.Parent and entry.playing then
				local offset = entry.offset
					+ math.max(0, self.Time - entry.origin) * entry.speed * entry.rate
				if sound.Looped and sound.TimeLength > 0 then
					offset %= sound.TimeLength
				end
				if sound.TimeLength > 0 and offset < sound.TimeLength then
					sound.PlaybackSpeed = entry.speed * entry.rate
					if math.abs(sound.TimePosition - offset) > 0.12 or not sound.Playing then
						sound.TimePosition = offset
					end
					if playing then
						if not sound.Playing then
							sound:Resume()
						end
					else
						sound:Pause()
					end
				end
			end
		end
	end
	function Player:_advance(target, seeking)
		if not self:_due(target, seeking) then
			return false
		end
		self.Time = target
		if self.Frame ~= target * self.data.FPS then
			self:_pose(target * self.data.FPS)
		end
		self:_visuals(target * self.data.FPS)
		self:_audio(self.Status == "Playing" and not seeking)
		return true
	end
	function Player:_prepare(generation)
		generation = generation or self.generation
		local function current()
			assert(
				self.generation == generation and not self.destroyed,
				"Cutscene preparation cancelled"
			)
		end
		local playerGui = self.options.ParentGui or Players.LocalPlayer:WaitForChild("PlayerGui")
		current()
		local data = self.data
		self.saved = {}
		self.objects = {}
		self.redirect = {}
		self.effects = {}
		self.meshes = {}
		self.sounds = {}
		self.contexts = {}
		self.due = {}
		self.nextEvent = 1
		self.applied = {}
		self.lookups = {}
		self.parents = {}
		self.projection = {}
		self.objects.Projection = self.projection
		self.geometry = {}
		self.virtual = Instance.new("Folder")

		self.virtual.Name = "Namespace"
		self.scene = self.package.Scene:Clone()
		self.scene.Name = "EclipseCutscene_" .. self.package.Name
		self.gui = Instance.new("ScreenGui")

		self.gui.Name = self.scene.Name
		self.gui.IgnoreGuiInset = true
		self.gui.ResetOnSpawn = false
		self.gui.DisplayOrder = 50
		self.gui.Parent = playerGui
		if not self.audioRoot then
			self.audioRoot = Instance.new("Folder")

			self.audioRoot.Name = self.scene.Name
			self.audioRoot.Parent = game:GetService("SoundService")
		end
		self.subtitles = Subtitles.new(self.gui)
 self.drawings = Drawings.new(self.scene)
		for _, object in self.scene:GetDescendants() do
			local id = object:GetAttribute("EclipseExportId")
			if id then
				self.objects[id] = object
			end
			if object:IsA("BaseScript") then
				object.Enabled = false
			elseif object:IsA("BasePart") then
				object.Anchored = true
				object.CanCollide = false
				object.CanTouch = false
			elseif
				object:IsA("JointInstance")
				or object:IsA("Constraint")
				or object:IsA("WeldConstraint")
			then
				object.Enabled = false
			end
		end
		for id, definition in data.Geometry or {} do
			local target = self.objects[id]
			assert(target, "Missing editable mesh target " .. id)
			local geometry = Geometry.create(target, definition)
			if self.generation ~= generation or self.destroyed then
				geometry.mesh:Destroy()
				current()
			end
			self.geometry[id] = geometry
			self.objects["Geometry:" .. id] = geometry
		end
		local bindings = table.clone(data.Bindings)
		table.sort(bindings, function(a, b)
			return #a.Path < #b.Path
		end)
		for _, binding in bindings do
			local root = self:_resolve(binding)
			if root and self.options.HideOriginals ~= false and binding.Visible then
				self:_hideOriginal(root)
				for _, original in root:GetDescendants() do
					self:_hideOriginal(original)
				end
			end
			for _, node in binding.Nodes do
				local original = self:_original(node.Reference)
				if not original and root then
					if node.Reference then
						original = resolveTyped(root, node.Path)
					else
						original = Paths.resolve(root, node.Path)
					end
				end
				local copy = self.objects[node.Id]
				if original and copy then
					self.redirect[original] = copy
					if self.options.HideOriginals ~= false and binding.Visible then
						self:_hideOriginal(original)
					end
				end
			end
			local cursor = game
			for index, name in binding.Path do
				local fields = self.lookups[cursor]
				if not fields then
					fields = {}
					self.lookups[cursor] = fields
				end
				local target
				if index == #binding.Path then
					for _, node in binding.Nodes do
						if #node.Path == 0 then
							target = self.objects[node.Id]
							break
						end
					end
				else
					target = fields[name] or cursor:FindFirstChild(name)
					if not target then
						target = Instance.new("Folder")

						target.Name = name
						target.Parent = self.virtual
					end
				end
				assert(target, "Missing bundled namespace " .. name)
				fields[name] = target
				self.parents[target] = cursor
				cursor = target
			end
		end
		for _, global in data.Globals do
			local object = self:_resolve(global)
			if not object then
				warn(`eclipse cutscene {self.package.Name}: missing global target {table.concat(global.Path, ".")}`)
				continue
			end
			self.objects[global.Id] = object
			for key in global.Properties do
				self:_remember(object, key)
			end
		end
		self.assets = self.scene.Assets
		self.assets.Parent = nil
		for _, root in data.Roots do
			local object = self.objects[root.Id]
			if object and root.Service then
				local original = root.Path and self:_resolve(root)
				if original and original ~= object then
					self:_write(original, "Parent", nil)
				end
				object.Parent = game:GetService(root.Service)
			elseif
				object
				and root.Kind == "Dependency"
				and (object.Parent == self.assets or object.Parent == self.scene)
			then
				object.Parent = root.InWorld and self.scene or self.assets
			elseif object and root.Kind == "Camera" then
				for _, child in object:GetDescendants() do
					if child:IsA("BasePart") then
						child.LocalTransparencyModifier = 1
					end
				end
			end
		end
		for _, id in data.Effects do
			local object = self.objects[id]
			assert(object, "Missing effect " .. id)
			local entry = { object = object }
			if Effects.kind(object) ~= "Letterbox" and Effects.kind(object)~="Camera Shake" then
				entry.overlay = Effects.overlay(object, self.gui)
			end
			table.insert(self.effects, entry)
		end
		self.soundStates = {}
		for _, object in self.scene:GetDescendants() do
			if object:IsA("Sound") and object.Playing then
				self.soundStates[object] = {
					offset = object.TimePosition,
					origin = 0,
					speed = object.PlaybackSpeed,
					rate = 1,
					playing = true,
				}
				object:Pause()
			end
		end
		self.scene.Parent = workspace
		for _, event in data.Events do
			table.insert(
				self.due,
				{ time = event.Frame / data.FPS, event = event, phase = "Begin" }
			)
			if event.End then
				table.insert(
					self.due,
					{
						time = (event.Frame + event.Data.Duration) / data.FPS,
						event = event,
						phase = "End",
					}
				)
			end
			for index, row in event.Data.Sounds or {} do
				local name = event.Id .. ":" .. index
				local sound = self.audioRoot:FindFirstChild(name) or Instance.new("Sound")
				sound.Name = name
				sound.SoundId = row.AudioId
				sound.Volume = row.Volume
				sound.PlaybackSpeed = row.Speed
                sound.Looped = row.Looped == true
				sound.Parent = self.audioRoot
				table.insert(
					self.sounds,
					{ sound = sound, start = event.Frame / data.FPS, speed = row.Speed or 1 }
				)
			end
		end
		table.sort(self.due, function(a, b)
			if a.time ~= b.time then
				return a.time < b.time
			end
			if a.phase ~= b.phase then
				return a.phase == "Begin"
			end
			return a.event.Id < b.event.Id
		end)
		self.letterbox = Letterbox.new(data, self.objects, sample)
		self.loopWait = nil
		self.Time, self.Frame = 0, 0
		self:_pose(0)
		self:_visuals(0)
	end
	function Player:_release(keepAudio)
  self:_clearShake()
		local errors = {}
		local function safely(fn)
			local ok, err = pcall(fn)
			if not ok then
				table.insert(errors, tostring(err))
			end
		end
		local function dispose(key, method)
			local object = self[key]
			self[key] = nil
			if object then
				safely(function()
					object[method](object)
				end)
			end
		end
		dispose("connection", "Disconnect")
		for _, entry in self.effects or {} do
			safely(function()
				for _, object in entry.object:GetDescendants() do
					if object:IsA("BasePart") then
						if keepAudio then
							Layer.keep(object)
						else
							Layer.clear(object)
						end
					end
				end
			end)
		end
		self.effects = {}
		self.letterbox = nil
		dispose("subtitles", "destroy")
 dispose("drawings", "destroy")
		for _, root in self.data.Roots do
			if root.Service and self.objects and self.objects[root.Id] then
				safely(function()
					self.objects[root.Id]:Destroy()
				end)
			end
		end
		for _, key in { "scene", "gui", "assets", "virtual" } do
			dispose(key, "Destroy")
		end
		for _, geometry in self.geometry or {} do
			safely(function()
				geometry.mesh:Destroy()
			end)
		end
		self.geometry = {}
		if self.audioRoot then
			if keepAudio then
				safely(function()
					for _, sound in self.audioRoot:GetChildren() do
						sound:Stop()
					end
				end)
			else
				dispose("audioRoot", "Destroy")
			end
		end
		for object, fields in self.saved or {} do
			for key, box in fields do
				safely(function()
					object[key] = box[1]
				end)
			end
		end
		self.saved = {}
		self.camera = nil
		if #errors > 0 then
			warn("Eclipse cutscene cleanup: " .. table.concat(errors, "; "))
		end
	end
	function Player:Stop(reason)

		self.generation += 1
		local had = self.Status ~= "Stopped"
		self.Status = "Stopped"
		self.loopWait = nil
		self:_release()
		if registry.active == self then
			registry.active = nil
		end
		if had then
			self.stopped:Fire(reason or "Stopped")
		end
		return self
	end
	function Player:_fail(message)
		self:Stop("Error")
		self.LastError = tostring(message)
		self.failed:Fire(self.LastError)
		warn("Eclipse cutscene " .. self.package.Name .. ": " .. self.LastError)
	end
	function Player:Play()
		assert(not self.destroyed, "Cutscene player was destroyed")
		if self.preparing or self.Status == "Playing" or self.Status == "Loading" then
			return self
		end
		if self.Status == "Paused" then
			self.Status = "Playing"
			if self.loopWait == nil then
				self:_audio(true)
			end
			return self
		end
		if registry.active and registry.active ~= self then
			registry.active:Stop("Replaced")
		end
		self:Stop()
		registry.active = self
		self.Status = "Loading"
		local generation = self.generation
		self.preparing = true
		local ok, message = xpcall(function()
			if
				not Preload.run(self.package, self.data, function()
					return self.generation ~= generation or self.destroyed
				end)
			then
				return
			end
			if self.generation ~= generation then
				return
			end
			self:_prepare(generation)
			local assets = { self.scene, self.assets, self.gui, self.audioRoot }
			local failed = {}
			for _, root in self.data.Roots do
				if root.Service and self.objects[root.Id] then
					table.insert(assets, self.objects[root.Id])
				end
			end
			ContentProvider:PreloadAsync(assets, function(id, status)
				if id ~= "" and status ~= Enum.AssetFetchStatus.Success then
					failed[id] = tostring(status)
				end
			end)
			if self.generation ~= generation then
				return
			end
			local issues = {}
			for id, status in failed do
				table.insert(issues, id .. " (" .. status .. ")")
			end
			if #issues > 0 then
				warn(`eclipse cutscene {self.package.Name}: some assets could not load, check experience permissions: {table.concat(issues, ", ")}`)
			end
			for _, entry in self.sounds do
				if not entry.sound.IsLoaded then
					warn(`eclipse cutscene {self.package.Name}: audio could not load: {entry.sound.SoundId}`)
				end
			end
			self.Status = "Playing"
			self:_pose(0)
			if not self:_advance(0, false) then
				return
			end
			self.connection = onRender(function(dt)
				if self.Status == "Paused" then
					local good, err = xpcall(function()
						if
							self.data.CameraMode ~= "Game"
							and workspace.CurrentCamera ~= self.camera
						then
							self:_pose(self.Frame)
						end
						self:_camera()
						self:_visuals(self.Frame)
					end, debug.traceback)
					if not good then
						self:_fail(err)
					end
					return
				end
				if self.Status ~= "Playing" or self.rebuilding then
					return
				end
				local good, err = xpcall(function()
					local looping = self.options.Loop == true
						or self.options.Loop == nil and self.data.Loop
					local finish = self.Duration
					if looping then
						finish = (self.data.ContentLastFrame or self.data.LastFrame) / self.data.FPS
						for _, entry in self.sounds do
							finish = math.max(
								finish,
								entry.start + entry.sound.TimeLength / math.max(0.01, entry.speed)
							)
						end
						finish = math.min(finish, self.Duration)
					end
					if self.loopWait ~= nil then
						if not looping then
							self:Stop("Completed")
							self.completed:Fire()
							return
						end
						self.loopWait += dt
						if self.loopWait < 0.5 then
							self:_camera()
							self:_visuals(self.Frame)
							return
						end
						local connection = self.connection
						self.connection = nil
						self:_release(true)
						self.rebuilding = true
						local ready, issue = pcall(function()
							self:_prepare(generation)
						end)
						self.rebuilding = false
						if self.generation ~= generation then
							if connection then
								connection:Disconnect()
							end
							return
						end
						self.connection = connection
						assert(ready, issue)
						self:_advance(0, false)
						return
					end
					local target = math.max(self.Time, math.min(self.Time + dt, finish))
					if not self:_advance(target, false) then
						return
					end
					if target >= finish then
						if looping then
							self.loopWait = 0
							self:_audio(false)
						else
							self:Stop("Completed")
							self.completed:Fire()
						end
					end
				end, debug.traceback)
				if not good and self.generation == generation then
					self:_fail(err)
				end
			end)
		end, debug.traceback)
		self.preparing = false
		if not ok and self.generation == generation then
			self:_fail(message)
			error(message, 2)
		end
		return self
	end
	function Player:Pause()
		if self.Status ~= "Playing" then
			return self
		end
		self.Status = "Paused"
		self:_audio(false)
		return self
	end
	function Player:Seek(seconds)
		assert(
			type(seconds) == "number" and seconds == seconds and math.abs(seconds) < math.huge,
			"Seek expects finite seconds"
		)
		assert(
			self.Status == "Playing" or self.Status == "Paused",
			"Play the cutscene before seeking"
		)
		assert(not self.rebuilding, "Cutscene is already rebuilding its state")
		local generation = self.generation
		self.loopWait = nil
		local status = self.Status
		local target = math.clamp(seconds, 0, self.Duration)
		local ok, message = xpcall(function()
			if target < self.Time then
				local connection = self.connection
				self.connection = nil
				self:_release(true)
				self.rebuilding = true
				local ready, issue = pcall(function()
					self:_prepare(generation)
				end)
				self.rebuilding = false
				if self.generation ~= generation then
					if connection then
						connection:Disconnect()
					end
					return
				end
				self.connection = connection
				assert(ready, issue)
			end
			if not self:_advance(target, true) then
				return
			end
			self.Status = status
			self:_audio(status == "Playing")
		end, debug.traceback)
		if not ok and self.generation == generation then
			self:_fail(message)
			error(message, 2)
		end
		return self
	end
	function Player:Destroy()
		if self.destroyed then
			return
		end
		self:Stop("Destroyed")
		self.destroyed = true
		for _, event in { self.marker, self.stopped, self.completed, self.failed } do
			event:Destroy()
		end
	end
	return function(package, settings, fps, lastFrame, loader)
		local loaded
		local function state()
			if not loaded then
				loaded = loader()
			end
			return loaded
		end
		local API = {
			FPS = fps,
			Duration = lastFrame / fps,
			Version = 2,
			Settings = settings,
		}
		function API.Preload()
			assert(Run:IsRunning() and Run:IsClient(), "Preload runs on the client during Play.")
			return Preload.run(package, state().data)
		end
		function API.new(options)
			assert(
				Run:IsRunning() and Run:IsClient(),
				"Eclipse cutscenes run on the client. Require this module from a LocalScript during Play."
			)
			local source = state()
			local defaults = table.clone(settings)
			for key, value in options or {} do
				defaults[key] = value
			end
			assert(
				defaults.CameraMode == nil
					or defaults.CameraMode == "Game"
					or defaults.CameraMode == "Authored"
					or defaults.CameraMode == "Studio",
				"Unknown camera mode"
			)
			assert(
				defaults.CameraMode ~= "Authored" or source.data.CameraMode == "Authored",
				"This export does not contain an authored camera"
			)
			local state = table.clone(source.data)
			state.CameraMode = defaults.CameraMode or source.data.CameraMode
			local self = setmetatable({
				package = package,
				data = state,
				factories = source.factories,
				options = defaults,
				Status = "Stopped",
				generation = 0,
				Duration = API.Duration,
				Time = 0,
				Frame = 0,
			}, Player)
			self.marker, self.MarkerReached = signal()
			self.stopped, self.Stopped = signal()
			self.completed, self.Completed = signal()
			self.failed, self.Failed = signal()
			return self
		end
		function API.Play(options)
			local player = API.new(options)
			player:Play()
			return player
		end
		return API
	end
end
