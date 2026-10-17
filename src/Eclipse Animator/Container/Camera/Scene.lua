--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Timing = require("Timing")

local Selection = game:GetService("Selection")
local Parenting = require("Parenting")
local SelectedRig = require("SelectedRig")
local CameraRig = require("CameraRig")
local Armature = require("ArmatureRuntime")
local Document = require("Document")
local Data = require("ChunkStore")
local History = require("History")
local Properties = require("Properties")
local Scene = {}
local sessions = setmetatable({}, { __mode = "k" })
local refs

function Scene.get()
	local raw = refs.State.Timeline:GetState()
	local session = sessions[raw.Keyframes]
	if not session then
		session = { entries = {}, forces = {} }
		sessions[raw.Keyframes] = session
	end

	return session
end

local function changed()
	refs.State.currentProjectSaved = false
end

function Scene.part(motor)
	if Properties.is(motor) and motor.PropertyId == "CFrame" and motor.Rig:IsA("BasePart") then
		return motor.Rig
	end

	return motor.Part1
end

function Scene.name(motor)
	return Scene.part(motor):GetFullName()
end

function Scene.world(part)
	return part:IsA("Bone") and part.TransformedWorldCFrame or part.CFrame
end

function Scene.size(part)
	if part:IsA("BasePart") then
		return part.Size
	end

	local length = part.CFrame.Position.Magnitude
	for _, child in part:GetChildren() do
		if child:IsA("Bone") then
			length = child.CFrame.Position.Magnitude
			break
		end
	end

	local diameter = math.clamp(length * 0.3, 0.15, 2)
	return Vector3.new(diameter, diameter, diameter)
end

function Scene.all()
	local result = {}
	for _, rig in refs.State.getAllRigs() do
		if CameraRig.isRig(rig) or Armature.isRig(rig) then
			continue
		end

		if rig:IsA("BasePart") and not rig:FindFirstChildWhichIsA("Bone", true) then
			for _, motor in Properties.list(rig) do
				if motor.PropertyId == "CFrame" and not motor:GetAttribute("EclipseDisabled") then
					table.insert(result, { rig = rig, motor = motor, ragdoll = false })
				end
			end
		end

		for _, motor in Parenting.collectMotors(rig) do
			if
				typeof(motor) == "Instance"
				and motor:IsA("Motor6D")
				and motor.Part1
				and motor.Part1:IsA("BasePart")
			then
				if
					motor:GetAttribute("EclipsePartTrackEnabled") ~= false
					and (
						not motor:GetAttribute("EclipseAddedObject")
						or refs.State.activeObjectMotors[motor]
					)
				then
					table.insert(result, {
						rig = rig,
						motor = motor,
						ragdoll = not motor:GetAttribute("EclipseAddedObject"),
					})
				end
			end
		end

		for _, bone in require("RigTraversal").rigDescendants(rig) do
			if
				bone:IsA("Bone")
				and not bone:GetAttribute("EclipseArmatureSkinningHelper")
				and not require("R6Controls").isControl(bone)
			then
				local motor = require("BoneMotor").get(bone)
				if motor and not bone:GetAttribute("EclipseDisabled") then
					table.insert(result, { rig = rig, motor = motor, ragdoll = true })
				end
			end
		end
	end

	return result
end

local function ownerRig(part)
	const rigs = refs.State.getAllRigs()
	if table.find(rigs, part) then
		return nil
	end

	local limb = false
	for _, joint in part:GetJoints() do
		if joint:IsA("Motor6D") then
			if joint.Part1 == part and joint:GetAttribute("EclipseAddedObject") then
				return nil
			end

			limb = true
		end
	end

	local nearest
	local current = part.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			if
				table.find(rigs, current)
				or current:FindFirstChildOfClass("Humanoid")
				or current:FindFirstChildOfClass("AnimationController")
			then
				return current
			end

			nearest = nearest or current
		end

		current = current.Parent
	end

	return limb and nearest or nil
end

function Scene.add(mode, objects)
	assert(not refs.State.Timeline:GetState().Playing, "pause the animation first")
	local picked, seen = {}, {}

	local function add(object)
		if typeof(object) ~= "Instance" then
			return
		end

		object = Properties.owner(object) or object
		local source = object:FindFirstChild("EclipseSourcePart")
		if source and source:IsA("ObjectValue") and source.Value then
			object = source.Value
		end

		if object:IsA("Motor6D") then
			object = object.Part1
		end

		if mode == "Ragdoll" and object and object:IsA("BasePart") then
			object = ownerRig(object) or object
		end

		if not object or seen[object] or object:GetAttribute("EclipsePhysicsForce") then
			return
		end

		if
			not (object:IsA("Model") or object:IsA("BasePart") or object:IsA("Bone"))
			or not object:IsDescendantOf(workspace)
		then
			return
		end

		seen[object] = true
		table.insert(picked, object)
	end

	if objects then
		for _, object in objects do
			add(object)
		end
	else
		for _, object in Selection:Get() do
			add(object)
		end

		if #picked == 0 then
			for item, selected in refs.State.Rig and refs.State.Rig._selectedItems or {} do
				if selected then
					add(item.linkedRigInstance)
				end
			end
		end
	end

	objects = picked
	assert(#objects > 0, "select a rig, model or parts first")
	local session = Scene.get()
	local before = table.clone(session.entries)
	local pending = {}
	local available = Scene.all()
	for _, object in objects do
		assert(
			typeof(object) == "Instance" and object:IsDescendantOf(workspace),
			"select a rig, model or parts in Workspace"
		)
		local matched = false
		for _, entry in available do
			if
				object == entry.rig
				or object == Scene.part(entry.motor)
				or Scene.part(entry.motor):IsDescendantOf(object)
			then
				matched = true
				break
			end
		end

		if not matched then
			assert(refs.AddObject and refs.AddRig, "add this object to the timeline first")
			if object:IsA("Bone") then
				refs.AddRig(
					object:FindFirstAncestorOfClass("Model")
						or object:FindFirstAncestorWhichIsA("BasePart")
				)
			elseif
				object:IsA("BasePart")
				or object:IsA("Model")
					and (object:FindFirstChildOfClass("Humanoid") or #Parenting.collectMotors(
						object
					) > 0)
			then
				refs.AddRig(object)
			else
				local owner = refs.State.currentRig
				assert(
					owner and not CameraRig.isRig(owner) and not Armature.isRig(owner),
					"select a Motor6D rig in Eclipse before adding objects"
				)
				refs.AddObject(object, { Physics = true })
			end

			available = Scene.all()
		end

		local count = 0
		for _, entry in available do
			local belongs = Scene.part(entry.motor) == object
				or Scene.part(entry.motor):IsDescendantOf(object)
			if
				belongs
				or mode == "Ragdoll"
					and entry.ragdoll
					and object == entry.rig
			then
				pending[entry.motor] = {
					rig = entry.rig,
					motor = entry.motor,
					ragdoll = mode == "Ragdoll" and entry.ragdoll,
				}
				count += 1
			end
		end

		assert(count > 0, "add a Motor6D rig to the timeline before adding objects")
	end

	local after = table.clone(before)
	for motor, entry in pending do
		after[motor] = entry
	end

	local count = 0
	for _ in after do
		count += 1
	end

	if count > 150 then
		require("Notification").show(
			"PHYSICS",
			tostring(count) .. " parts. Big simulations work, they just take longer to finish.",
			6
		)
	end

	local function apply(entries)
		session.entries = table.clone(entries)
		changed()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Add physics participants")
	return count
end

function Scene.clear()
	local session = Scene.get()
	local before, guide, paths = session.entries, session.guide, session.guides

	local function apply(entries, path, guides)
		session.entries = entries
		session.guide = path
		session.guides = guides
		changed()
	end

	apply({}, nil, {})
	History.record(function()
		apply(before, guide, paths)
	end, function()
		apply({}, nil, {})
	end, "Clear physics participants")
end

function Scene.setMode(mode)
	local available = {}
	for _, entry in Scene.all() do
		available[entry.motor] = entry
	end

	for motor, entry in Scene.get().entries do
		entry.ragdoll = mode == "Ragdoll" and available[motor] and available[motor].ragdoll or false
	end
end

function Scene.entries()
	local result = {}
	for motor, entry in Scene.get().entries do
		assert(
			motor.Parent and motor.Part1 and motor.Part1.Parent and entry.rig.Parent,
			"a registered physics part was removed; clear the list and add it again"
		)
		table.insert(result, entry)
	end

	table.sort(result, function(a, b)
		return Scene.name(a.motor) < Scene.name(b.motor)
	end)
	return result
end

function Scene.useClip(clip)
	local session = Scene.get()
	session.entries = {}
	session.guide = nil
	session.guides = {}
	for motor in clip.tracks do
		local ragdoll = clip.ragdolls and clip.ragdolls[motor]
		session.entries[motor] = {
			motor = motor,
			rig = clip.owners and clip.owners[motor] or clip.rig,
			ragdoll = ragdoll == true
				or ragdoll == nil
					and clip.settings.mode == "Ragdoll"
					and not motor:GetAttribute("EclipseAddedObject"),
		}
	end

	local entries = Scene.entries()
	for _, saved in clip.settings.guides or (clip.settings.guide and { clip.settings.guide } or {}) do
		local guide = table.clone(saved)
		if clip.guideMotors then
			guide.motor = clip.guideMotors[guide.index]
		else
			guide.motor = clip.guideMotor or entries[guide.index] and entries[guide.index].motor
		end

		if guide.motor and session.entries[guide.motor] then
			session.guides[guide.motor] = guide
			session.guide = guide
		end
	end
end

function Scene.guideMotor()
	local entries = Scene.entries()
	local rig = SelectedRig.resolve(refs.State)
	for _, entry in entries do
		if
			entry.rig == rig
			and entry.ragdoll
			and (
				Scene.part(entry.motor).Name == "Torso"
				or Scene.part(entry.motor).Name == "LowerTorso"
			)
		then
			return entry.motor
		end
	end

	for _, entry in entries do
		if entry.rig == rig then
			return entry.motor
		end
	end

	return entries[1] and entries[1].motor
end

function Scene.paths()
	local session = Scene.get()
	local paths = table.clone(session.guides or {})
	if session.guide then
		paths[session.guide.motor] = session.guide
	end

	local result = {}
	for motor, guide in paths do
		if session.entries[motor] and motor.Parent and motor.Part1 and motor.Part1.Parent then
			table.insert(result, guide)
		end
	end

	table.sort(result, function(a, b)
		return Scene.name(a.motor) < Scene.name(b.motor)
	end)
	return result
end

function Scene.selectedGuideMotors()
	local chosen, objects = {}, {}
	for item, active in refs.State.Rig and refs.State.Rig._selectedItems or {} do
		if active then
			local motor = item.fetchMotor and item:fetchMotor()
			if motor then
				chosen[motor] = true
			end

			if typeof(item.linkedRigInstance) == "Instance" then
				table.insert(objects, item.linkedRigInstance)
			end
		end
	end

	for _, object in Selection:Get() do
		table.insert(objects, object)
	end

	local raw = refs.State.Timeline:GetState()
	for key in raw.SelectedKeyframes or {} do
		chosen[key.Motor] = true
	end

	for key in raw.SelectedChannelKeyframes or {} do
		chosen[key.Motor] = true
	end

	local result = {}
	for _, entry in Scene.entries() do
		local include = chosen[entry.motor]
		for _, object in objects do
			if
				object == entry.rig
				or object == entry.motor
				or object == Scene.part(entry.motor)
				or Scene.part(entry.motor):IsDescendantOf(object)
			then
				include = true
				break
			end
		end

		if include then
			table.insert(result, entry.motor)
		end
	end

	return result
end

function Scene.setGuides(motors, points, easing)
	Timing.validate(easing)
	require("Path").validate({ guide = { points = points, smoothing = 0 } })
	assert(#motors > 0, "select parts for this path first")
	local session = Scene.get()
	for _, motor in motors do
		assert(session.entries[motor], "add these parts to Physics first")
	end

	local before = {}
	for _, guide in Scene.paths() do
		before[guide.motor] = guide
	end

	local after = table.clone(before)
	local origin = Scene.world(Scene.part(motors[1])).Position
	for _, motor in motors do
		local shifted = {}
		local offset = Scene.world(Scene.part(motor)).Position - origin
		for i, point in points do
			shifted[i] = point + offset
		end

		after[motor] = {
			motor = motor,
			points = shifted,
			strength = 35,
			easing = easing and Timing.copy(easing),
		}
	end

	local function apply(paths)
		session.guides = table.clone(paths)
		session.guide = select(2, next(paths))
		changed()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Set physics paths")
end

function Scene.setGuide(motor, points, easing)
	Scene.setGuides({ motor }, points, easing)
end

function Scene.clearGuide(motor)
	local session = Scene.get()
	local before = {}
	for _, guide in Scene.paths() do
		before[guide.motor] = guide
	end

	local after = motor and table.clone(before) or {}
	if motor then
		after[motor] = nil
	end

	local function apply(paths)
		session.guides = table.clone(paths)
		session.guide = select(2, next(paths))
		changed()
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Clear physics guide")
end

function Scene.addForce()
	local session = Scene.get()
	assert(#session.forces < 16, "use up to 16 blast forces")
	local motor = Scene.guideMotor()
	local camera = workspace.CurrentCamera
	local position = motor and Scene.world(Scene.part(motor)).Position
		or camera.CFrame.Position + camera.CFrame.LookVector * 10
	local part = Instance.new("Part")

	local number = 1
	local names = {}
	for _, force in session.forces do
		names[force.Name] = true
	end

	while names["Blast " .. number] do
		number += 1
	end

	part.Name = "Blast " .. number
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, true
	part.Transparency = 0.35
	part.Color = Color3.fromRGB(242, 171, 196)
	part.Material = Enum.Material.Neon
	part:SetAttribute("EclipsePhysicsForce", true)
	part:SetAttribute(
		"Frame",
		math.floor(
			refs.State.Timeline:GetState().CurrentTime * refs.State.Timeline:GetState().FPS + 0.5
		)
	)
	part:SetAttribute("Radius", 5)
	part:SetAttribute("Power", 60)
	part:SetAttribute("ForceType", "Blast")
	part:SetAttribute("Duration", 60)
	part:SetAttribute("Spin", 1)
	part:SetAttribute("Launch", 0)
	part.Parent = workspace

	local function add()
		part.Parent = workspace
		if not table.find(session.forces, part) then
			table.insert(session.forces, part)
		end

		changed()
	end

	local function remove()
		local at = table.find(session.forces, part)
		if at then
			table.remove(session.forces, at)
		end

		part.Parent = nil
		changed()
	end

	add()
	History.record(remove, add, "Add blast force")
	return part
end

function Scene.registerForce(part)
	assert(
		part and part:IsA("BasePart") and part:GetAttribute("EclipsePhysicsForce"),
		"select an Eclipse Blast part first"
	)
	local forces = Scene.get().forces
	if not table.find(forces, part) then
		assert(#forces < 16, "use up to 16 blast forces")
		table.insert(forces, part)
		changed()
	end
end

function Scene.removeForce(part)
	local session = Scene.get()
	local before = table.clone(session.forces)
	local at = table.find(before, part)
	assert(at, "This blast was already removed")
	local after = table.clone(before)
	table.remove(after, at)
	local parent = part.Parent

	local function apply(forces, location)
		session.forces = table.clone(forces)
		part.Parent = location
		changed()
	end

	apply(after, nil)
	History.record(function()
		apply(before, parent)
	end, function()
		apply(after, nil)
	end, "Remove blast")
end

function Scene.setForcePath(part, points, easing)
	Timing.validate(easing)
	assert(part and table.find(Scene.get().forces, part), "Select a force first")
	require("Path").validate({ force = { points = points, smoothing = 0 } })
	local offsets = {}
	for _, point in points do
		table.insert(offsets, point - points[1])
	end

	local before = part:GetAttribute("ForcePath")
	local beforeFrame = part.CFrame
	local afterFrame = CFrame.new(points[1]) * beforeFrame.Rotation
	local after = Document.pack({ points = offsets, easing = easing and Timing.copy(easing) })

	local function apply(value, frame)
		part:SetAttribute("ForcePath", value)
		part.CFrame = frame
		changed()
	end

	apply(after, afterFrame)
	History.record(function()
		apply(before, beforeFrame)
	end, function()
		apply(after, afterFrame)
	end, "Draw force path")
end

function Scene.clearForcePath(part)
	local before = part:GetAttribute("ForcePath")

	local function apply(value)
		part:SetAttribute("ForcePath", value)
		changed()
	end

	apply(nil)
	History.record(function()
		apply(before)
	end, function()
		apply(nil)
	end, "Clear force path")
end

function Scene.guideChanged(clip)
	local guides = Scene.paths()
	local saved = clip.settings.guides or (clip.settings.guide and { clip.settings.guide } or {})
	if #guides ~= #saved then
		return true
	end

	for i, guide in guides do
		local old = saved[i]
		if not Timing.equal(guide.easing, old.easing) then
			return true
		end

		local motor = clip.guideMotors and clip.guideMotors[old.index] or clip.guideMotor
		if motor and motor ~= guide.motor or #guide.points ~= #old.points then
			return true
		end

		for j, point in guide.points do
			if point ~= old.points[j] then
				return true
			end
		end
	end

	return false
end

function Scene.forcesChanged(clip)
	if not clip then
		return false
	end

	local saved = clip.settings.forces or {}
	local forces = Scene.get().forces
	if #saved ~= #forces then
		return true
	end

	for i, part in forces do
		local old = saved[i]
		if
			(part:GetAttribute("ForceType") == "BlackHole" or part:GetAttribute("ForcePath"))
			and (old.duration or 60) ~= (part:GetAttribute("Duration") or 60)
		then
			return true
		end

		if (old.kind or "Blast") ~= (part:GetAttribute("ForceType") or "Blast") then
			return true
		end

		if
			(old.spin or 1) ~= (part:GetAttribute("Spin") or 1)
			or (old.launch or 0) ~= (part:GetAttribute("Launch") or 0)
			or old.pathSource ~= part:GetAttribute("ForcePath")
		then
			return true
		end

		if
			not part.Parent
			or old.position ~= part.Position
			or old.frame ~= part:GetAttribute("Frame")
			or old.radius ~= part:GetAttribute("Radius")
			or old.power ~= part:GetAttribute("Power")
		then
			return true
		end
	end

	return false
end

function Scene.snapshot(settings, entries)
	local session = Scene.get()
	settings.forces = {}
	for _, part in session.forces do
		assert(part.Parent, "a blast part was removed; remove it from Forces too")
		local pathData = part:GetAttribute("ForcePath")
			and Document.unpack(part:GetAttribute("ForcePath"))
		table.insert(settings.forces, {
			easing = pathData and pathData.easing,
			kind = part:GetAttribute("ForceType") or "Blast",
			duration = part:GetAttribute("Duration") or 60,
			spin = part:GetAttribute("Spin") or 1,
			launch = part:GetAttribute("Launch") or 0,
			pathSource = part:GetAttribute("ForcePath"),
			path = pathData and pathData.points,
			position = part.Position,
			frame = part:GetAttribute("Frame"),
			radius = part:GetAttribute("Radius"),
			power = part:GetAttribute("Power"),
		})
	end

	settings.guide = nil
	settings.guides = {}
	for _, guide in Scene.paths() do
		local index
		for i, entry in entries do
			if entry.motor == guide.motor then
				index = i
				break
			end
		end

		assert(index, "the guided bone is no longer in this simulation")
		table.insert(settings.guides, {
			index = index,
			points = table.clone(guide.points),
			strength = guide.strength or 35,
			easing = guide.easing and Timing.copy(guide.easing),
		})
	end

	return settings
end

function Scene.write(save)
	local session = Scene.get()
	local old = save:FindFirstChild("EclipsePhysicsSetup")
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")

	folder.Name = "EclipsePhysicsSetup"
	local functionRef = function(name, value)
		local ref = Instance.new("ObjectValue")

		ref.Name, ref.Value, ref.Parent = name, value, folder
		return ref
	end

	for _, entry in Scene.entries() do
		local ref = functionRef("Participant", Scene.part(entry.motor))
		ref:SetAttribute("Ragdoll", entry.ragdoll)
	end

	for _, part in session.forces do
		if part.Parent then
			functionRef("Force", part)
		end
	end

	for _, guide in Scene.paths() do
		local object = functionRef("Guide", Scene.part(guide.motor))
		Data.write(
			object,
			"Path",
			Document.pack({
				points = guide.points,
				strength = guide.strength,
				easing = guide.easing,
			})
		)
	end

	folder.Parent = save
end

function Scene.load(save)
	local session = Scene.get()
	session.entries, session.forces, session.guide, session.guides = {}, {}, nil, {}
	local folder = save and save:FindFirstChild("EclipsePhysicsSetup")
	if not folder then
		return
	end

	local byPart = {}
	for _, entry in Scene.all() do
		byPart[Scene.part(entry.motor)] = entry
	end

	for _, ref in folder:GetChildren() do
		if not ref:IsA("ObjectValue") or not ref.Value then
			continue
		end

		if ref.Name == "Participant" then
			local entry = byPart[ref.Value]
			if entry then
				entry.ragdoll = ref:GetAttribute("Ragdoll") == true
				session.entries[entry.motor] = entry
			end
		elseif ref.Name == "Force" and ref.Value.Parent then
			table.insert(session.forces, ref.Value)
		elseif ref.Name == "Guide" and byPart[ref.Value] and ref:FindFirstChild("Path") then
			local guide = Document.unpack(Data.read(ref.Path))
			require("Path").validate({
				guide = { points = guide.points, smoothing = 0, easing = guide.easing },
			})
			guide.motor = byPart[ref.Value].motor
			session.guides[guide.motor] = guide
			session.guide = guide
		elseif ref.Name == "GuidePart" and byPart[ref.Value] and folder:FindFirstChild("Guide") then
			local guide = Document.unpack(Data.read(folder.Guide))
			require("Path").validate({
				guide = { points = guide.points, smoothing = 0, easing = guide.easing },
			})
			guide.motor = byPart[ref.Value].motor
			session.guide = guide
			session.guides[guide.motor] = guide
		end
	end
end

function Scene.remapLive(state, mapping)
	local session = sessions[state.Timeline:GetState().Keyframes]
	if not session then
		return
	end

	local entries, guides = {}, {}
	for motor, entry in session.entries do
		local copy = table.clone(entry)
		copy.motor = mapping[motor] or motor
		copy.rig = mapping[entry.rig] or entry.rig
		entries[copy.motor] = copy
	end

	for motor, guide in session.guides or {} do
		local copy = table.clone(guide)
		copy.motor = mapping[motor] or motor
		guides[copy.motor] = copy
	end

	if session.guide then
		local copy = table.clone(session.guide)
		copy.motor = mapping[copy.motor] or copy.motor
		session.guide = copy
	end

	session.entries, session.guides = entries, guides
	for i, force in session.forces do
		session.forces[i] = mapping[force] or force
	end
end

function Scene.liveSnapshot(state, motorIds, rigIds)
	local session = sessions[state.Timeline:GetState().Keyframes]
	local value = { participants = {}, guides = {}, forces = {} }
	if not session then
		return value
	end

	for motor, entry in session.entries do
		local id = motorIds[motor]
		if id then
			value.participants[id] = { rig = rigIds[entry.rig], ragdoll = entry.ragdoll == true }
		end
	end

	for motor, guide in session.guides or {} do
		local id = motorIds[motor]
		if id then
			local copy = table.clone(guide)
			copy.motor = nil
			value.guides[id] = copy
		end
	end

	for _, force in session.forces do
		local path = force.Parent and require("Paths").of(force, game)
		if path then
			table.insert(value.forces, path)
		end
	end

	return value
end

function Scene.prepareLive(state, value, motors, rigs)
	local entries, guides, forces = {}, {}, {}
	for id, saved in value.participants or {} do
		local motor = motors[id]
		if not motor or not rigs[saved.rig] then
			continue
		end

		entries[motor] = {
			motor = motor,
			rig = assert(rigs[saved.rig], "Waiting for shared physics rig"),
			ragdoll = saved.ragdoll == true,
		}
	end

	for id, saved in value.guides or {} do
		local motor = motors[id]
		if not motor then
			continue
		end

		require("Path").validate({
			guide = { points = saved.points, smoothing = 0, easing = saved.easing },
		})
		local guide = table.clone(saved)
		guide.motor = motor
		guides[motor] = guide
	end

	for _, path in value.forces or {} do
		local force = require("Paths").resolve(game, path)
		assert(force and force:IsA("BasePart"), "Waiting for shared physics force")
		table.insert(forces, force)
	end

	return function()
		local raw = state.Timeline:GetState()
		sessions[raw.Keyframes] =
			{ entries = entries, guides = guides, guide = nil, forces = forces }
	end
end

function Scene.init(options)
	refs = options
end

return Scene
