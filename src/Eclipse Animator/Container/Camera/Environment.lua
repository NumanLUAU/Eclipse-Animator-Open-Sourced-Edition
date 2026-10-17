--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CameraRig = require("CameraRig")
local Scene = {}

local CELL, RANGE, CONTACT, ENV_LIMIT, SUBJECT_LIMIT = 64, 256, 24, 2048, 1024
local SLICE, BUILD_LIMIT = 0.001, 24
const SKY_EXTENT = 8
const SKY_FACES = table.freeze({
	{ "SkyboxFt", Vector3.new(0, 0, -1), Vector3.yAxis },
	{ "SkyboxBk", Vector3.new(0, 0, 1), Vector3.yAxis },
	{ "SkyboxLf", Vector3.new(-1, 0, 0), Vector3.yAxis },
	{ "SkyboxRt", Vector3.new(1, 0, 0), Vector3.yAxis },
	{ "SkyboxUp", Vector3.yAxis, Vector3.zAxis },
	{ "SkyboxDn", -Vector3.yAxis, -Vector3.zAxis },
})
const WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
const HORIZON = Color3.fromRGB(255, 176, 120)
const MOONLIGHT = Color3.fromRGB(70, 82, 110)
local defaultSky

local function skySource()
	const sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		return sky
	end

	if not defaultSky then
		defaultSky = Instance.new("Sky")
	end

	return defaultSky
end

local function sunLight()
	const sun = Lighting:GetSunDirection()
	const day = math.clamp(sun.Y * 6 + 0.4, 0, 1)
	const strength = math.clamp(Lighting.Brightness / 2, 0, 1) * day
	const tint = HORIZON:Lerp(WHITE, math.clamp(sun.Y * 3, 0, 1))
	const shift = Lighting.ColorShift_Top
	const night = 1 - day
	return Color3.new(
		math.clamp(tint.R * strength + MOONLIGHT.R * night + shift.R, 0, 1),
		math.clamp(tint.G * strength + MOONLIGHT.G * night + shift.G, 0, 1),
		math.clamp(tint.B * strength + MOONLIGHT.B * night + shift.B, 0, 1)
	), day > 0 and -sun or -Lighting:GetMoonDirection()
end

local function createSky(viewport)
	const view = Instance.new("ViewportFrame")
	view.Name = "EclipseSky"
	view.BackgroundTransparency = 1
	view.BorderSizePixel = 0
	view.Active = false
	view.Interactable = false
	view.Ambient = WHITE
	view.LightColor = BLACK
	const camera = Instance.new("Camera")
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
	camera.Parent = view
	view.CurrentCamera = camera
	const decals = {}
	for index, face in SKY_FACES do
		const panel = Instance.new("Part")
		panel.Name = face[1]
		panel.Anchored = true
		panel.CanCollide = false
		panel.CanTouch = false
		panel.CanQuery = false
		panel.CastShadow = false
		panel.Transparency = 1
		panel.Size = Vector3.new(SKY_EXTENT * 2 + 0.05, SKY_EXTENT * 2 + 0.05, 0.05)
		panel.CFrame = CFrame.lookAt(face[2] * SKY_EXTENT, Vector3.zero, face[3])
		const decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal.Parent = panel
		panel.Parent = view
		decals[index] = decal
	end

	view.Parent = viewport.Parent
	return { view = view, camera = camera, decals = decals }
end

local function appearance(o)
	return o:IsA("Decal")
		or o:IsA("SurfaceAppearance")
		or o:IsA("Shirt")
		or o:IsA("Pants")
		or o:IsA("ShirtGraphic")
		or o:IsA("WrapLayer")
		or o:IsA("WrapTarget")
end

local function subjectRoot(o)
	if o:IsA("DataModelMesh") or appearance(o) then
		return o:FindFirstAncestorWhichIsA("BasePart") or o:FindFirstAncestorWhichIsA("Model") or o
	end

	return o
end

local function allowed(o)
	if
		o.Name == "AnimSaves"
		or o.Name == "_EclipseAnimator_DragGuides"
		or o:GetAttribute("EclipseAnimator_BonesFolder")
		or o:GetAttribute("EclipseSave")
		or o:GetAttribute("EclipseArmatureBone")
		or CameraRig.isRig(o)
	then
		return false
	end

	if
		o.Parent
		and o.Parent:IsA("Camera")
		and o:GetAttribute("EclipseLocalLivePreview") ~= true
	then
		return false
	end

	return o:IsA("Model")
		or o:IsA("Folder")
		or o:IsA("Camera")
		or o:IsA("BasePart")
		or o:IsA("Accessory")
		or o:IsA("DataModelMesh")
		or o:IsA("Bone")
		or o:IsA("BodyColors")
		or o:IsA("Humanoid")
		or o:IsA("FaceControls")
		or o:IsA("CharacterMesh")
		or appearance(o)
end

local function configure(o, textured)
	if o:IsA("BasePart") then
		if not textured then
			o.Material = Enum.Material.SmoothPlastic
			o.MaterialVariant = ""
			o.Reflectance = 0
		end

		o.CastShadow = false
		o.Anchored = true
		o.CanCollide = false
		o.CanTouch = false
		o.CanQuery = false
		o.Locked = true
		if o:IsA("MeshPart") and textured then
            o.RenderFidelity = Enum.RenderFidelity.Precise
        elseif o:IsA("MeshPart") and not textured then
			o.TextureContent = Content.none
			o.RenderFidelity = Enum.RenderFidelity.Performance
		end
	elseif o:IsA("FileMesh") and not textured then
		o.TextureId = ""
	elseif o:IsA("CharacterMesh") and not textured then
		o.BaseTextureId = 0
		o.OverlayTextureId = 0
	elseif o:IsA("Humanoid") then
		o.EvaluateStateMachine = false
		o.AutoRotate = false
		o.BreakJointsOnDeath = false
		o.RequiresNeck = false
		o.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function distance(part, point)
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size * 0.5
	return Vector3.new(
		math.max(0, math.abs(p.X) - h.X),
		math.max(0, math.abs(p.Y) - h.Y),
		math.max(0, math.abs(p.Z) - h.Z)
	).Magnitude
end

function Scene.attach(viewport, sourceRoot, options)
	sourceRoot = sourceRoot or workspace
	local subjectsOnly = options and options.SubjectsOnly == true
	local world = Instance.new("WorldModel")
	world.Name = "Scene"
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local session = {
		world = world,
		camera = camera,
		ready = false,
		copied = 0,
		writes = 0,
		residentParts = 0,
		indexed = 0,
		cycles = 0,
		maxSlice = 0,
	}
	local live, viewCF, viewFov, subjects = true, nil, 70, {}
	local hideAccessories = false

	local function previewTransparency(source)
		return hideAccessories and source:FindFirstAncestorWhichIsA("Accessory") and 1
			or source.LocalTransparencyModifier
	end

	local subjectRoots = {}

	local function textured(o)
		while o and o ~= sourceRoot do
			if subjectRoots[o] then
				return true
			end

			o = o.Parent
		end

		return false
	end

	local records, cells, large, changed, moving = {}, {}, {}, {}, {}
	local copies, original, watchers, written = {}, {}, {}, {}
	local dirty, partCopies, boneCopies, subjectCopies = {}, {}, {}, {}
	local discovery, queued = {}, {}
	const boneHolders = setmetatable({}, { __mode = "k" })
	local discoveryJob
	local movingCursor, movingList = 1, {}
	local spatialRoot = sourceRoot:IsA("WorldRoot") and sourceRoot
		or sourceRoot:FindFirstAncestorWhichIsA("WorldRoot")
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { sourceRoot }
	overlap.MaxParts = 512
	local seeded = {}
	local nextRefresh, forceRefresh, lastUpdate = 0, true, os.clock()
	local viewGeneration, refreshGeneration = 0, nil

	local function valid(o)
		if o == sourceRoot then
			return true
		end

		if not o:IsDescendantOf(sourceRoot) then
			return false
		end

		local a = o
		while a and a ~= sourceRoot do
			if not allowed(a) then
				return false
			end

			a = a.Parent
		end

		return a == sourceRoot
	end

	local function key(x, y, z)
		return x .. ":" .. y .. ":" .. z
	end

	local function unindex(part)
		local r = records[part]
		if not r then
			return
		end

		for _, k in r.keys do
			local c = cells[k]
			if c then
				c[part] = nil
				if next(c) == nil then
					cells[k] = nil
				end
			end
		end

		large[part] = nil
		r.keys = {}
	end

	local function index(part)
		local r = records[part]
		if not r then
			return
		end

		unindex(part)
		local cf, size = part.CFrame, part.Size
		local h = size * 0.5
		local x, y, z = cf.RightVector, cf.UpVector, cf.LookVector
		local extent = Vector3.new(
			math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
			math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
			math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z
		)
		local lo, hi = cf.Position - extent, cf.Position + extent
		local ax, ay, az = math.floor(lo.X / CELL), math.floor(lo.Y / CELL), math.floor(lo.Z / CELL)
		local bx, by, bz = math.floor(hi.X / CELL), math.floor(hi.Y / CELL), math.floor(hi.Z / CELL)
		if (bx - ax + 1) * (by - ay + 1) * (bz - az + 1) > 64 then
			large[part] = true
		else
			for ix = ax, bx do
				for iy = ay, by do
					for iz = az, bz do
						local k = key(ix, iy, iz)
						cells[k] = cells[k] or {}
						cells[k][part] = true
						table.insert(r.keys, k)
					end
				end
			end
		end

		r.cf, r.size = cf, size
		moving[part] = not part.Anchored or nil
	end

	local function forget(o)
		local c = copies[o]
		if not c then
			return
		end

		for _, d in c:GetDescendants() do
			local s = original[d]
			if s then
				if watchers[s] then
					watchers[s]:Disconnect()
					watchers[s] = nil
				end

				if d:IsA("BasePart") then
					session.residentParts -= 1
				end

				copies[s] = nil
				original[d] = nil
				written[d] = nil
				dirty[s] = nil
				partCopies[s] = nil
				boneCopies[s] = nil
				subjectCopies[s] = nil
			end
		end

		if watchers[o] then
			watchers[o]:Disconnect()
			watchers[o] = nil
		end

		if c:IsA("BasePart") then
			session.residentParts -= 1
		end

		copies[o] = nil
		original[c] = nil
		written[c] = nil
		dirty[o] = nil
		partCopies[o] = nil
		boneCopies[o] = nil
		subjectCopies[o] = nil
		c:Destroy()
	end

	local function remove(o)
		table.clear(boneHolders)
		if records[o] then
			unindex(o)
			records[o].connection:Disconnect()
			records[o] = nil
			session.indexed -= 1
		end

		changed[o] = nil
		moving[o] = nil
		queued[o] = nil
		forget(o)
		forceRefresh = true
	end

	local function enqueue(o)
		if not queued[o] then
			queued[o] = true
			table.insert(discovery, o)
		end
	end

	local budget

	local function register(o)
		if not valid(o) then
			return
		end

		if o:IsA("BasePart") and not records[o] then
			records[o] = { keys = {} }
			session.indexed += 1
			index(o)
			records[o].connection = o.Changed:Connect(function(p)
				if p == "CFrame" or p == "Size" or p == "Anchored" or p == "Parent" then
					changed[o] = true
				end
			end)
		end
	end

	local sliceStart, builds = os.clock(), 0
	budget = function()
		if not live or refreshGeneration and refreshGeneration ~= viewGeneration then
			return false
		end

		local spent = os.clock() - sliceStart
		if spent >= SLICE or builds >= BUILD_LIMIT then
			session.maxSlice = math.max(session.maxSlice, spent)
			RunService.Heartbeat:Wait()
			sliceStart = os.clock()
			builds = 0
		end

		return live and (not refreshGeneration or refreshGeneration == viewGeneration)
	end

	local function shallow(source)
		if not live or not valid(source) then
			return nil
		end

		local parent = source.Parent == sourceRoot and world or shallow(source.Parent)
		if not parent or not budget() then
			return nil
		end

		if copies[source] then
			if copies[source].Parent ~= parent then
				copies[source].Parent = parent
			end

			return copies[source]
		end

		local ok, c = pcall(function()
			if source:IsA("Camera") then
				local f = Instance.new("Folder")
				f.Name = source.Name
				return f
			end

			return Instance.fromExisting(source)
		end)
		if not ok or not c then
			return nil
		end

		configure(c, true)
		if c:IsA("BasePart") then
			c.LocalTransparencyModifier = previewTransparency(source)
			session.residentParts += 1
		end

		copies[source] = c
		original[c] = source
		dirty[source] = c
		if textured(source) then
			subjectCopies[source] = c
		end

		if source:IsA("BasePart") then
			partCopies[source] = c
		elseif source:IsA("Bone") then
			boneCopies[source] = c
		end

		c.Parent = parent
		session.copied += 1
		builds += 1
		watchers[source] = source.Changed:Connect(function(p)
			if source:IsA("FaceControls") and p ~= "Parent" then pcall(function() c[p] = source[p] end) end
			if p == "Parent" then
				forceRefresh = true
			end

			if
				copies[source] == c
				and p ~= "CFrame"
				and p ~= "Position"
				and p ~= "Orientation"
				and p ~= "Rotation"
				and p ~= "Transform"
			then
				dirty[source] = c
			end
		end)
		return c
	end

	local function geometry(part)
		local c = shallow(part)
		if not c then
			return
		end

		local stack = part:GetChildren()
		while live and #stack > 0 do
			local o = table.remove(stack)

			if not o:IsA("BasePart") and allowed(o) then
				shallow(o)
				for _, v in o:GetChildren() do
					table.insert(stack, v)
					if not budget() then
						return
					end
				end
			end

			if not budget() then
				return
			end
		end

		local parent = part.Parent
		while parent and parent ~= sourceRoot do
			if parent:IsA("Model") then
				for _, o in parent:GetChildren() do
					if
						o:IsA("Humanoid")
						or o:IsA("BodyColors")
						or o:IsA("CharacterMesh")
						or appearance(o)
					then
						shallow(o)
					end

					if not budget() then
						return
					end
				end
			end

			parent = parent.Parent
		end
	end

	local function inView(part, cf, fov)
		local p = cf:PointToObjectSpace(part.Position)
		local radius = part.Size.Magnitude * 0.5
		local depth = -p.Z
		if depth + radius < 0 then
			return false
		end

		local size = viewport.AbsoluteSize
		local aspect = size.Y > 0 and size.X / size.Y or 16 / 9
		local y = math.tan(math.rad(fov) * 0.5)
		local x = y * aspect
		return math.abs(p.X) <= math.max(depth, 0) * x + radius * math.sqrt(1 + x * x) + 4
			and math.abs(p.Y) <= math.max(depth, 0) * y + radius * math.sqrt(1 + y * y) + 4
	end

	local function visible(part)
		return part.Transparency < 1 and part.LocalTransparencyModifier < 1
	end

	local function addBoneHolders(wanted, scanned)
		const models = {}
		for part in wanted do
			if part:IsA("MeshPart") and part.HasSkinnedMesh then
				const model = part:FindFirstAncestorWhichIsA("Model")
				if model and not scanned[model] and model:IsDescendantOf(sourceRoot) then
					scanned[model] = true
					table.insert(models, model)
				end
			end
		end

		for _, model in models do
			local holders = boneHolders[model]
			if not holders then
				holders = {}
				for _, o in model:GetDescendants() do
					if o:IsA("BasePart") and o:FindFirstChildWhichIsA("Bone") then
						table.insert(holders, o)
					end
				end

				boneHolders[model] = holders
			end

			for _, o in holders do
				if not wanted[o] and valid(o) then
					wanted[o] = true
				end
			end

			if not budget() then
				return false
			end
		end

		return true
	end

	local function refresh()
		if not viewCF then
			return
		end

		local cf, fov = viewCF, viewFov
		local wanted, focus, seen = {}, {}, {}
		const scanned = {}
		local subjectCount = 0

		for _, root in subjects do
			root = typeof(root) == "Instance" and subjectRoot(root) or root
			if typeof(root) == "Instance" and root ~= sourceRoot and valid(root) then
				local center = root:IsA("BasePart") and root.Position
					or root:IsA("Model") and root:GetPivot().Position
				if center and #focus < 16 then
					table.insert(focus, center)
				end

				local stack = { root }
				while live and #stack > 0 do
					local o = table.remove(stack)
					if allowed(o) then
						if o:IsA("BasePart") and visible(o) and (subjectsOnly or subjectCount < SUBJECT_LIMIT) then
							if not wanted[o] then
								wanted[o] = true
								subjectCount += 1
							end
						end

						for _, v in o:GetChildren() do
							if allowed(v) then
								table.insert(stack, v)
							end

							if not budget() then
								return
							end
						end
					end

					if not budget() then
						return
					end
				end
			end
		end

		local ancestors = {}
		for part in wanted do
			local a = part.Parent
			while a and a ~= sourceRoot do
				if a:IsA("BasePart") then
					ancestors[a] = true
				end

				a = a.Parent
			end
		end

		for part in ancestors do
			wanted[part] = true
		end

		if not addBoneHolders(wanted, scanned) then
			return
		end

		local obsolete = {}
		for source, c in copies do
			if c:IsA("BasePart") and textured(source) and not wanted[source] then
				table.insert(obsolete, source)
			end
		end

		for _, source in obsolete do
			forget(source)
		end

		for part in wanted do
			if valid(part) then
				geometry(part)
			end

			if not budget() then
				return
			end
		end

		local heap = {}

		local function offer(part)
			if subjectsOnly then return end
			if seen[part] then
				return
			end

			seen[part] = true
			if wanted[part] or not records[part] or not valid(part) or not visible(part) then
				return
			end

			local d = distance(part, cf.Position)
			local contact = math.huge
			for _, p in focus do
				contact = math.min(contact, distance(part, p))
			end

			if not inView(part, cf, fov) or (d > RANGE and contact > CONTACT) then
				return
			end

			local score = math.min(d, contact <= CONTACT and contact * 0.25 or math.huge)
			if copies[part] then
				score *= 0.85
			end

			local item = { part = part, score = score }
			if #heap < ENV_LIMIT then
				table.insert(heap, item)
				local i = #heap
				while i > 1 do
					local p = math.floor(i / 2)
					if heap[p].score >= score then
						break
					end

					heap[i] = heap[p]
					i = p
				end

				heap[i] = item
			elseif score < heap[1].score then
				local i = 1
				while i * 2 <= #heap do
					local c = i * 2
					if c < #heap and heap[c + 1].score > heap[c].score then
						c += 1
					end

					if heap[c].score <= score then
						break
					end

					heap[i] = heap[c]
					i = c
				end

				heap[i] = item
			end
		end

		local function region(p, r)
			for x = math.floor((p.X - r) / CELL), math.floor((p.X + r) / CELL) do
				for y = math.floor((p.Y - r) / CELL), math.floor((p.Y + r) / CELL) do
					for z = math.floor((p.Z - r) / CELL), math.floor((p.Z + r) / CELL) do
						local bucket = cells[key(x, y, z)]
						if bucket then
							for part in bucket do
								offer(part)
								if not budget() then
									return
								end
							end
						end

						if not budget() then
							return
						end
					end
				end
			end
		end

		local function seed(slot, point, radius)
			if not spatialRoot then
				return
			end

			local cell = key(
				math.floor(point.X / CELL),
				math.floor(point.Y / CELL),
				math.floor(point.Z / CELL)
			)
			if seeded[slot] == cell then
				return
			end

			seeded[slot] = cell
			for _, part in spatialRoot:GetPartBoundsInRadius(point, radius, overlap) do
				if not records[part] then
					register(part)
				end

				if not budget() then
					return
				end
			end
		end

		if not subjectsOnly then
		seed(0, cf.Position, RANGE)
		for i, p in focus do
			seed(i, p, CONTACT)
		end

		region(cf.Position, RANGE)
		for _, p in focus do
			region(p, CONTACT)
		end

		for part in large do
			offer(part)
			if not budget() then
				return
			end
		end

		end
		for _, item in heap do
			wanted[item.part] = true
		end

		if not addBoneHolders(wanted, scanned) then
			return
		end

		local parents = {}
		for part in wanted do
			local a = part.Parent
			while a and a ~= sourceRoot do
				if a:IsA("BasePart") then
					parents[a] = true
				end

				a = a.Parent
			end
		end

		for part in parents do
			wanted[part] = true
		end

		if not budget() then
			return
		end

		for source, c in copies do
			if c:IsA("BasePart") and not wanted[source] then
				forget(source)
			end
		end

		local keep = {}
		for part in wanted do
			local a = part
			while a and a ~= sourceRoot do
				keep[a] = true
				a = a.Parent
			end
		end

		local discard = {}
		for source, c in copies do
			if
				(
					source:IsA("Model")
					or source:IsA("Folder")
					or source:IsA("Accessory")
					or source:IsA("Camera")
				) and not keep[source]
			then
				table.insert(discard, source)
			end
		end

		for _, source in discard do
			forget(source)
			if not budget() then
				return
			end
		end

		local order = {}
		for part in wanted do
			table.insert(order, { part = part, distance = distance(part, cf.Position) })
			if not budget() then
				return
			end
		end

		table.sort(order, function(a, b)
			return a.distance < b.distance
		end)
		for _, row in order do
			if valid(row.part) then
				geometry(row.part)
			end

			if not budget() then
				return
			end
		end

		session.cycles += 1
		session.ready = #discovery == 0 and discoveryJob == nil
	end

	local added = sourceRoot.DescendantAdded:Connect(function(o)
		table.clear(boneHolders)
		if allowed(o) then
			if not subjectsOnly then enqueue(o) end
			forceRefresh = true
		end
	end)
	local removing = sourceRoot.DescendantRemoving:Connect(remove)
	if not subjectsOnly then enqueue(sourceRoot) end
	local resized = viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		forceRefresh = true
	end)
	local lightingDirty = true
	local lightingChanged = Lighting.Changed:Connect(function()
		lightingDirty = true
	end)
	viewport.LightColor = Color3.new(1, 1, 1)
	const sky = not subjectsOnly and createSky(viewport) or nil
	local skyDirty, skyWatched, skyChanged, skyTurn, skyView, reflection = sky ~= nil, nil, nil, CFrame.identity, nil, nil

	local function markSky(child)
		if child:IsA("Sky") then
			skyDirty = true
		end
	end

	const skyAdded = sky and Lighting.ChildAdded:Connect(markSky)
	const skyRemoved = sky and Lighting.ChildRemoved:Connect(markSky)

	local function write(o, p, v)
		local cache = written[o]
		if not cache then
			cache = {}
			written[o] = cache
		end

		if cache[p] ~= v then
			if o[p] ~= v then
				o[p] = v
				session.writes += 1
			end

			cache[p] = v
		end
	end

	local function syncSky()
		skyDirty = false
		const source = skySource()
		const watched = source.Parent and source or nil
		if watched ~= skyWatched then
			if skyChanged then
				skyChanged:Disconnect()
				skyChanged = nil
			end

			if reflection then
				reflection:Destroy()
				reflection = nil
			end

			skyWatched = watched
			if watched then
				skyChanged = watched.Changed:Connect(function()
					skyDirty = true
				end)
				const ok, copy = pcall(Instance.fromExisting, watched)
				if ok and copy then
					reflection = copy
					copy.Parent = viewport
				end
			end
		end

		for index, face in SKY_FACES do
			const texture = source[face[1]]
			write(sky.decals[index], "Texture", texture)
			if reflection then
				write(reflection, face[1], texture)
			end
		end

		const turn = source.SkyboxOrientation
		skyTurn = CFrame.fromEulerAngles(
			math.rad(turn.X),
			math.rad(turn.Y),
			math.rad(turn.Z),
			Enum.RotationOrder.ZXY
		):Inverse()
		skyView = nil
	end

	function session.setHideAccessories(enabled)
		enabled = enabled == true
		if hideAccessories == enabled then
			return
		end

		hideAccessories = enabled
		for source, copy in partCopies do
			write(copy, "LocalTransparencyModifier", previewTransparency(source))
		end
	end

	local parts, frames = {}, {}

	function session.update(cf, fov, rigs)
		if not live then
			return
		end

		if
			viewCF
			and (
				(cf.Position - viewCF.Position).Magnitude > 8
				or cf.LookVector:Dot(viewCF.LookVector) < 0.98
				or math.abs(CameraRig.clamp(fov) - viewFov) >= 5
			)
		then
			forceRefresh = true
			viewGeneration += 1
		end

		lastUpdate = os.clock()
		viewCF, viewFov = cf, CameraRig.clamp(fov)
		subjects = rigs or {}
		local nextRoots = {}
		for _, root in subjects do
			if typeof(root) == "Instance" then
				nextRoots[subjectRoot(root)] = true
			end
		end

		local rootsChanged = false
		for root in nextRoots do
			if not subjectRoots[root] then
				forceRefresh = true
				rootsChanged = true
			end
		end

		for root in subjectRoots do
			if not nextRoots[root] then
				forceRefresh = true
				rootsChanged = true
			end
		end

		subjectRoots = nextRoots
		if rootsChanged then
			table.clear(subjectCopies)
			for source, c in copies do
				if textured(source) then
					subjectCopies[source] = c
				end
			end
		end

		for source, c in subjectCopies do
			dirty[source] = c
		end

		if viewport.CurrentCamera ~= camera then
			viewport.CurrentCamera = camera
		end

		write(camera, "CFrame", cf)
		write(camera, "FieldOfView", viewFov)
		if lightingDirty then
			lightingDirty = false
			const color, direction = sunLight()
			write(viewport, "Ambient", Lighting.Ambient:Lerp(Lighting.OutdoorAmbient, 0.5))
			write(viewport, "LightColor", color)
			write(viewport, "LightDirection", direction)
		end

		if sky then
			if skyDirty then
				syncSky()
			end

			const view = sky.view
			write(view, "AnchorPoint", viewport.AnchorPoint)
			write(view, "Position", viewport.Position)
			write(view, "Size", viewport.Size)
			write(view, "ZIndex", viewport.ZIndex - 1)
			write(view, "Visible", viewport.Visible)
			write(view, "ImageTransparency", viewport.ImageTransparency)
			if skyView ~= cf then
				skyView = cf
				sky.camera.CFrame = skyTurn * cf.Rotation
			end

			write(sky.camera, "FieldOfView", viewFov)
		end

		for source, c in partCopies do
			local frame = source.CFrame
			if frame ~= c.CFrame then
				table.insert(parts, c)
				table.insert(frames, frame)
				session.writes += 1
			end
		end

		for source, c in boneCopies do
			write(c, "Transform", source.Transform)
			write(c, "CFrame", source.CFrame)
		end

		for source, c in dirty do
			dirty[source] = nil
			if copies[source] ~= c then
				continue
			end

			if not valid(source) then
				forget(source)
				continue
			end

			local keepTexture = true
			if source:IsA("BasePart") then
				write(c, "Size", source.Size)
				write(c, "Color", source.Color)
				write(c, "Transparency", source.Transparency)
				write(c, "LocalTransparencyModifier", previewTransparency(source))
				if source:IsA("MeshPart") and c.MeshContent ~= source.MeshContent then
					c:ApplyMesh(source)
					configure(c, true)
					written[c] = nil
				end

				write(c, "Material", keepTexture and source.Material or Enum.Material.SmoothPlastic)
				write(c, "MaterialVariant", keepTexture and source.MaterialVariant or "")
				write(c, "Reflectance", keepTexture and source.Reflectance or 0)
				if source:IsA("MeshPart") then
					write(
						c,
						"TextureContent",
						keepTexture and source.TextureContent or Content.none
					)
					write(
						c,
						"RenderFidelity",
						keepTexture and Enum.RenderFidelity.Precise or Enum.RenderFidelity.Performance
					)
				end
			elseif source:IsA("Bone") then
				write(c, "Transform", source.Transform)
				write(c, "CFrame", source.CFrame)
			elseif source:IsA("DataModelMesh") then
				for _, p in { "Scale", "Offset", "VertexColor" } do
					write(c, p, source[p])
				end

				if source:IsA("SpecialMesh") then
					write(c, "MeshType", source.MeshType)
					write(c, "MeshId", source.MeshId)
				end

				if source:IsA("FileMesh") then
					write(c, "TextureId", keepTexture and source.TextureId or "")
				end
			elseif source:IsA("CharacterMesh") then
				write(c, "MeshId", source.MeshId)
				write(c, "BodyPart", source.BodyPart)
				write(c, "BaseTextureId", keepTexture and source.BaseTextureId or 0)
				write(c, "OverlayTextureId", keepTexture and source.OverlayTextureId or 0)
			elseif source:IsA("Shirt") then
				write(c, "ShirtTemplate", source.ShirtTemplate)
				write(c, "Color3", source.Color3)
			elseif source:IsA("Pants") then
				write(c, "PantsTemplate", source.PantsTemplate)
				write(c, "Color3", source.Color3)
			elseif source:IsA("ShirtGraphic") then
				write(c, "Graphic", source.Graphic)
				write(c, "Color3", source.Color3)
			elseif source:IsA("Decal") then
				for _, p in
					{
						"Texture",
						"Color3",
						"Transparency",
						"LocalTransparencyModifier",
						"Face",
						"ZIndex",
					}
				do
					write(c, p, source[p])
				end

				if source:IsA("Texture") then
					for _, p in { "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV" } do
						write(c, p, source[p])
					end
				end
			elseif source:IsA("SurfaceAppearance") then
				for _, p in
					{
						"ColorMap",
						"MetalnessMap",
						"NormalMap",
						"RoughnessMap",
						"AlphaMode",
						"Color",
					}
				do
					write(c, p, source[p])
				end
			elseif source:IsA("BodyColors") then
				for _, p in
					{
						"HeadColor3",
						"TorsoColor3",
						"LeftArmColor3",
						"RightArmColor3",
						"LeftLegColor3",
						"RightLegColor3",
					}
				do
					write(c, p, source[p])
				end
			end
		end

		if #parts > 0 then
			world:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			table.clear(parts)
			table.clear(frames)
		end
	end

	local worker = task.defer(function()
		while live do
			if os.clock() - lastUpdate > 0.5 then
				RunService.Heartbeat:Wait()
				continue
			end

			sliceStart = os.clock()
			builds = 0

			if viewCF and (forceRefresh or os.clock() >= nextRefresh) then
				forceRefresh = false
				refreshGeneration = viewGeneration
				refresh()
				refreshGeneration = nil
				nextRefresh = os.clock() + 0.2
			end

			local n = 0
			while n < 256 and (#discovery > 0 or discoveryJob) do
				if not discoveryJob then
					local o = table.remove(discovery)
					if valid(o) then
						register(o)
						discoveryJob = { object = o, children = o:GetChildren(), index = 1 }
					else
						queued[o] = nil
					end
				end

				if discoveryJob then
					local job = discoveryJob
					local child = job.children[job.index]
					if child then
						job.index += 1
						if allowed(child) and valid(child) then
							enqueue(child)
						end
					else
						queued[job.object] = nil
						discoveryJob = nil
					end
				end

				n += 1
				if not budget() then
					return
				end
			end

			for o in changed do
				changed[o] = nil
				if records[o] then
					if valid(o) then
						index(o)
					else
						remove(o)
					end
				end

				if not budget() then
					return
				end
			end

			if movingCursor > #movingList then
				movingList = {}
				for o in moving do
					table.insert(movingList, o)
				end

				movingCursor = 1
			end

			for _ = 1, 64 do
				local o = movingList[movingCursor]
				if not o then
					break
				end

				movingCursor += 1
				local r = records[o]
				if r and (o.CFrame ~= r.cf or o.Size ~= r.size) then
					index(o)
				end

				if not budget() then
					return
				end
			end

			session.maxSlice = math.max(session.maxSlice, os.clock() - sliceStart)
			RunService.Heartbeat:Wait()
		end
	end)

	function session.destroy()
		if not live then
			return
		end

		live = false
		added:Disconnect()
		removing:Disconnect()
		lightingChanged:Disconnect()
		resized:Disconnect()
		if sky then
			skyAdded:Disconnect()
			skyRemoved:Disconnect()
			if skyChanged then
				skyChanged:Disconnect()
				skyChanged = nil
			end

			sky.view:Destroy()
		end

		if reflection then
			reflection:Destroy()
			reflection = nil
		end

		pcall(task.cancel, worker)
		for _, r in records do
			r.connection:Disconnect()
		end

		for _, c in watchers do
			c:Disconnect()
		end

		table.clear(records)
		table.clear(cells)
		table.clear(large)
		table.clear(copies)
		table.clear(original)
		table.clear(watchers)
		discoveryJob = nil
		table.clear(changed)
		table.clear(moving)
		table.clear(discovery)
		table.clear(queued)
		table.clear(written)
		table.clear(dirty)
		table.clear(partCopies)
		table.clear(boneCopies)
		table.clear(subjectCopies)
		table.clear(boneHolders)
		if viewport.CurrentCamera == camera then
			viewport.CurrentCamera = nil
		end

		world:Destroy()
		camera:Destroy()
		session.residentParts = 0
	end

	viewport.Destroying:Once(session.destroy)
	return session
end

return Scene
