--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Timing = require("Timing")

local RunService = game:GetService("RunService")
local Simulation = {}
local Path = require("Path")
const REST_SPEED = 0.05
const COLLAPSE_SPIN = 1.2
const WARM_STEP = 0.001
const WARM_TIME = 3

local function finite(value, low, high)
	return typeof(value) == "number" and value == value and value >= low and value <= high
end

function Simulation.validate(bodies, settings)
	assert(#bodies > 0, "add at least one physics part")
	assert(
		finite(settings.first, 0, 100000) and settings.first % 1 == 0,
		"start frame needs a whole number"
	)
	assert(
		finite(settings.last, settings.first + 1, settings.first + 2400) and settings.last % 1 == 0,
		"use a range of 1 to 2400 frames"
	)
	assert(finite(settings.speed or 1, 0.1, 4), "speed needs to be between 0.1 and 4")
	assert(finite(settings.fps, 1, 240), "fps needs to be between 1 and 240")
	assert(finite(settings.gravity, 0, 1000), "gravity needs to be between 0 and 1000")
	assert(finite(settings.bounce, 0, 1), "bounce needs to be between 0 and 1")
	assert(finite(settings.friction, 0, 2), "friction needs to be between 0 and 2")
	assert(typeof(settings.velocity) == "Vector3", "enter an X, Y and Z push")
	for _, value in { settings.velocity.X, settings.velocity.Y, settings.velocity.Z } do
		assert(finite(value, -500, 500), "push needs to be between -500 and 500")
	end

	assert(#(settings.forces or {}) <= 16, "use up to 16 blast forces")
	for _, force in settings.forces or {} do
		assert(
			force.kind == nil
				or force.kind == "Blast"
				or force.kind == "Pull"
				or force.kind == "Lift"
				or force.kind == "BlackHole",
			"choose Blast, Pull, Lift or Black Hole"
		)
		if force.path then
			Path.validate({ force = { points = force.path, smoothing = 0, easing = force.easing } })
		end

		if force.kind == "BlackHole" or force.path then
			assert(finite(force.spin or 1, -10, 10), "spin needs -10 to 10 turns per second")
			assert(finite(force.launch or 0, 0, 500), "launch speed needs 0 to 500")
			if force.path then
				Path.validate({
					force = { points = force.path, smoothing = 0, easing = force.easing },
				})
			end

			assert(
				finite(force.duration or 60, 1, 2400) and (force.duration or 60) % 1 == 0,
				"duration needs 1 to 2400 frames"
			)
		end

		assert(
			finite(force.frame, 0, 100000) and force.frame % 1 == 0,
			"blast frame needs a whole number"
		)
		assert(finite(force.radius, 0.1, 1000), "blast radius needs to be between 0.1 and 1000")
		assert(finite(force.power, 0, 500), "blast power needs to be between 0 and 500")
		assert(
			typeof(force.position) == "Vector3" and finite(force.position.Magnitude, 0, 1e7),
			"move the blast to a valid position"
		)
	end

	local guides = settings.guides or (settings.guide and { settings.guide } or {})
	assert(#guides <= #bodies, "use one path per object")
	local guided = {}
	for _, guide in guides do
		assert(not settings.hold, 'Turn "Stay still until hit" off to follow a drawn path')
		assert(finite(settings.pathLaunch or 0, 0, 500), "launch speed needs 0 to 500")
		assert(
			finite(settings.pathEnd or settings.last, settings.first + 1, settings.first + 2400),
			"path end needs to be after the start frame (up to 2400 frames)"
		)
		assert(
			finite(guide.index, 1, #bodies) and guide.index % 1 == 0,
			"the guided bone is missing"
		)
		assert(not guided[guide.index], "use one path per object")
		guided[guide.index] = true
		assert(finite(guide.strength, 0, 100), "guide strength needs to be between 0 and 100")
		Path.validate({ guide = { points = guide.points, smoothing = 0, easing = guide.easing } })
	end

	for _, body in bodies do
		assert(
			body.part and (body.part:IsA("BasePart") or body.part:IsA("Bone")) and body.part.Parent,
			"a physics part was removed"
		)
		for _, value in { body.frame:GetComponents() } do
			assert(finite(value, -1e8, 1e8), "a physics pose has invalid values")
		end
	end
end

function Simulation.run(bodies, links, settings, checkpoint, step, colliders)
	Simulation.validate(bodies, settings)
	assert(not RunService:IsRunning(), "stop the Studio playtest before simulating")
	local folder = Instance.new("Folder")

	folder.Name = "EclipsePhysicsPreview"
	require("Recovery").mark(folder)
	local parts, bySource, poses = {}, {}, {}
	local deadline = os.clock() + 0.006

	local function budget(frame)
		if os.clock() >= deadline then
			RunService.Heartbeat:Wait()
			checkpoint(frame)
			deadline = os.clock() + 0.006
		end
	end

	local held, groups, initialVelocity, bodyFor = {}, {}, {}, {}
	local activeCount = 0
	local retired, lastPose, stepParts, guides = {}, {}, {}, {}
	local released, freed = {}, {}
	const report = { removed = 0, reanchored = 0, held = 0, stepped = 0, frozen = false }
	local sweep
	local dt = (settings.speed or 1) / settings.fps
	local restoreCollide, collisionGroups, movers = {}, {}, {}
	const extras, proxyOwner, proxies = {}, {}, {}
	local PhysicsService = game:GetService("PhysicsService")

	local function apart(a, b)
		const ignore = Instance.new("NoCollisionConstraint")
		ignore.Part0, ignore.Part1, ignore.Parent = a, b, folder
	end

	local ok, result = xpcall(function()
		for _, body in bodies do
			local bone = body.part:IsA("Bone")
			local part = bone and Instance.new("Part") or Instance.fromExisting(body.part)
			if bone then
				part.Shape = Enum.PartType.Ball
			end

			part.Name = body.part.Name
			part.CFrame = body.frame
			part.Size = body.size or (bone and Vector3.new(0.2, 0.2, 0.2) or body.part.Size)
			part.Anchored, part.Transparency, part.Locked = true, 1, true
			part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow =
				true, false, settings.hold == true, false
			part.CollisionGroup = "Default"
			part.Massless = false
			local properties = bone and PhysicalProperties.new(Enum.Material.Plastic)
				or body.part.CurrentPhysicalProperties
			part.CustomPhysicalProperties = PhysicalProperties.new(
				properties.Density,
				settings.friction,
				settings.bounce,
				100,
				100
			)
			part.Parent = folder
			bySource[body.part] = part
			table.insert(parts, part)
			extras[part] = {}
			proxyOwner[part] = part
			table.insert(proxies, part)
			for _, item in body.attached or {} do
				const source = item.part
				if not source.Parent or not source:IsA("BasePart") then
					continue
				end

				const extra = Instance.fromExisting(source)
				extra.Name = source.Name
				extra.Size = source.Size
				extra.CFrame = body.frame * item.offset
				extra.Anchored, extra.Transparency, extra.Locked = false, 1, true
				extra.CanCollide, extra.CanTouch, extra.CanQuery, extra.CastShadow =
					true, false, false, false
				extra.CollisionGroup = "Default"
				extra.Massless = true
				extra.CustomPhysicalProperties = part.CustomPhysicalProperties
				extra.Parent = folder
				const weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1, weld.Parent = part, extra, folder
				table.insert(extras[part], extra)
				proxyOwner[extra] = part
				table.insert(proxies, extra)
			end

			poses[body.part] = { [settings.first] = body.frame }
			lastPose[part] = body.frame
			held[part] = settings.hold == true
			bodyFor[part] = body
			local group = body.group or body.part
			groups[group] = groups[group] or {}
			table.insert(groups[group], part)
			initialVelocity[part] = {
				linear = settings.velocity + (settings.inherit and body.velocity or Vector3.zero),
				angular = settings.inherit and body.angular or Vector3.zero,
			}
			budget(settings.first)
		end

		local excluded = {}
		for _, source in settings.excludeParts or {} do
			excluded[source] = true
		end

		for _, collider in colliders or {} do
			local source = collider.part
			if
				not source.Parent
				or bySource[source]
				or not source.CanCollide
				or excluded[source]
			then
				continue
			end

			local part = Instance.fromExisting(source)
			part.Name = source.Name
			part.Size = source.Size
			part.CFrame = collider.frames[settings.first] or source.CFrame
			part.Anchored, part.Transparency, part.Locked = true, 1, true
			part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow =
				true, false, true, false
			part.CollisionGroup = "Default"
			part.Massless = false
			part.Parent = folder
			table.insert(movers, { part = part, source = source, frames = collider.frames })
		end

		local ignored = {}
		for _, mover in movers do
			if mover.source.CanCollide then
				ignored[mover.source] = true
			end
		end

		for _, body in bodies do
			if body.part:IsA("BasePart") and body.part.CanCollide then
				ignored[body.part] = true
			end
		end

		for _, source in settings.excludeParts or {} do
			ignored[source] = true
		end

		for source in ignored do
			if source.Parent and source.CanCollide then
				restoreCollide[source] = true
				source.CanCollide = false
			end
		end

		for _, link in links do
			local a, b = bySource[link.a], bySource[link.b]
			if not a or not b then
				continue
			end

			local ignore = Instance.new("NoCollisionConstraint")

			ignore.Part0, ignore.Part1, ignore.Parent = a, b, folder
			if link.rigid then
				local weld = Instance.new("WeldConstraint")

				weld.Part0, weld.Part1, weld.Parent = a, b, folder
			elseif not link.loose then
				local aa = Instance.new("Attachment")

				aa.CFrame, aa.Parent = a.CFrame:ToObjectSpace(link.frame), a
				local ab = Instance.new("Attachment")

				ab.CFrame, ab.Parent = b.CFrame:ToObjectSpace(link.frame), b
				local joint = Instance.new("BallSocketConstraint")

				joint.Attachment0, joint.Attachment1 = aa, ab
				joint.LimitsEnabled, joint.UpperAngle = true, link.angle or 75
				joint.TwistLimitsEnabled, joint.TwistLowerAngle, joint.TwistUpperAngle =
					true, -45, 45
				joint.MaxFrictionTorque = 0
				joint.Parent = folder
			end
		end

		if settings.selfCollision == false then
			local pairCount = 0
			local byKey, order = {}, {}
			for index, body in bodies do
				local key = if body.group ~= nil then body.group else false
				if not byKey[key] then
					byKey[key] = {}
					table.insert(order, key)
				end

				table.insert(byKey[key], parts[index])
			end

			for _, key in order do
				local size = #byKey[key]
				pairCount += if key == false then size * (#parts - 1) else size * (size - 1) / 2
			end

			local free = PhysicsService:GetMaxCollisionGroups()
				- #PhysicsService:GetRegisteredCollisionGroups()
			if pairCount > 3000 and #order <= free then
				local tag = string.sub(game:GetService("HttpService"):GenerateGUID(false), 1, 8)
				for index, key in order do
					local name = "EclipseSim" .. index .. "_" .. tag
					PhysicsService:RegisterCollisionGroup(name)
					table.insert(collisionGroups, name)
					for _, part in byKey[key] do
						part.CollisionGroup = name
						for _, extra in extras[part] do
							extra.CollisionGroup = name
						end
					end
				end

				for index, key in order do
					local name = collisionGroups[index]
					PhysicsService:CollisionGroupSetCollidable(name, name, false)
					if key == false then
						for _, other in collisionGroups do
							PhysicsService:CollisionGroupSetCollidable(name, other, false)
						end
					end
				end
			else
				for i, a in parts do
					for j = i + 1, #parts do
						if bodies[i].group ~= nil and bodies[i].group ~= bodies[j].group then
							continue
						end

						local ignore = Instance.new("NoCollisionConstraint")

						ignore.Part0, ignore.Part1, ignore.Parent = a, parts[j], folder
						for _, other in extras[parts[j]] do
							apart(a, other)
						end

						for _, extra in extras[a] do
							apart(extra, parts[j])
							for _, other in extras[parts[j]] do
								apart(extra, other)
							end
						end
					end

					budget(settings.first)
				end
			end
		end

		local function release(part)
			if retired[part] or not part:IsDescendantOf(folder) or not part.Anchored then
				return
			end

			held[part] = nil
			part.Anchored = false
			freed[part] = true
			activeCount += 1
			table.insert(released, part)
			part.AssemblyLinearVelocity = initialVelocity[part].linear
			part.AssemblyAngularVelocity = initialVelocity[part].angular
		end

		local function liveParts()
			assert(folder.Parent == workspace, "simulation was canceled; update it again")
			table.clear(stepParts)
			activeCount = 0
			for _, part in parts do
				if not retired[part] and not part:IsDescendantOf(folder) then
					retired[part] = true
					held[part] = nil
					report.removed += 1
				end

				if not retired[part] then
					if freed[part] and part.Anchored then
						part.Anchored = false
						report.reanchored += 1
					end

					table.insert(stepParts, part)
					for _, extra in extras[part] do
						table.insert(stepParts, extra)
					end

					if not part.Anchored then
						activeCount += 1
					end
				end
			end

			for _, guide in guides do
				if retired[guide.part] and guide.force then
					guide.force:Destroy()
					guide.force = nil
				end
			end
		end

		local function awaken(frame)
			const first = next(freed)
			if step or not first then
				return
			end

			const probe = Instance.new("Part")
			probe.Name = "EclipsePhysicsProbe"
			probe.Size = Vector3.one * 0.2
			probe.CFrame = CFrame.new(first.Position)
			probe.Anchored, probe.Transparency, probe.Locked = false, 1, true
			probe.CanCollide, probe.CanTouch, probe.CanQuery, probe.CastShadow =
				false, false, false, false
			probe.Parent = folder
			probe.AssemblyLinearVelocity = Vector3.yAxis * 50
			const origin = probe.Position
			const deadline = os.clock() + WARM_TIME
			repeat
				RunService.Heartbeat:Wait()
				checkpoint(frame)
				liveParts()
				table.insert(stepParts, probe)
				workspace:StepPhysics(WARM_STEP, stepParts)
			until probe.Position ~= origin or os.clock() >= deadline

			report.frozen = probe.Position == origin
			probe:Destroy()
		end

		folder.Parent = workspace
		if #proxies > #parts then
			const query = OverlapParams.new()
			query.FilterType = Enum.RaycastFilterType.Include
			query.FilterDescendantsInstances = proxies
			query.RespectCanCollide = true
			for _, extra in proxies do
				const holder = proxyOwner[extra]
				if holder == extra then
					continue
				end

				for _, other in workspace:GetPartsInPart(extra, query) do
					if proxyOwner[other] ~= holder then
						apart(extra, other)
					end
				end

				budget(settings.first)
			end
		end

		if settings.selfCollision ~= false then
			local query = OverlapParams.new()
			query.FilterType = Enum.RaycastFilterType.Include
			query.FilterDescendantsInstances = parts
			query.RespectCanCollide = true
			local indices = {}
			for i, part in parts do
				indices[part] = i
			end

			for i, part in parts do
				local group = bodies[i].group
				if group == nil then
					continue
				end

				for _, other in workspace:GetPartsInPart(part, query) do
					local j = indices[other]
					if j and j > i and bodies[j].group == group then
						local ignore = Instance.new("NoCollisionConstraint")
						ignore.Part0, ignore.Part1, ignore.Parent = part, other, folder
					end
				end

				budget(settings.first)
			end
		end

		sweep = RaycastParams.new()
		sweep.FilterType = Enum.RaycastFilterType.Exclude
		sweep.FilterDescendantsInstances = { folder }
		sweep.RespectCanCollide = true
		if not settings.hold then
			const children, steered = {}, {}
			for _, link in links do
				if bySource[link.a] and bySource[link.b] then
					children[bySource[link.b]] = true
				end
			end

			local function bottom(part)
				const frame, size = bodyFor[part].frame, part.Size * 0.5
				return frame.Y
					- math.abs(frame.RightVector.Y) * size.X
					- math.abs(frame.UpVector.Y) * size.Y
					- math.abs(frame.LookVector.Y) * size.Z
			end

			for _, guide in settings.guides or (settings.guide and { settings.guide } or {}) do
				const body = bodies[guide.index]
				steered[body.group or body.part] = true
			end

			for group, members in groups do
				if #members < 2 or steered[group] then
					continue
				end

				local resting = true
				for _, part in members do
					const motion = initialVelocity[part]
					if
						motion.linear.Magnitude > REST_SPEED
						or motion.angular.Magnitude > REST_SPEED
					then
						resting = false
						break
					end
				end

				if resting then
					local root, center, low = members[1], Vector3.zero, math.huge
					for _, part in members do
						if children[root] and not children[part] then
							root = part
						end

						center += bodyFor[part].frame.Position
						low = math.min(low, bottom(part))
					end

					center /= #members
					const pivot = Vector3.new(center.X, low, center.Z)
					const spin = bodyFor[root].frame.RightVector * COLLAPSE_SPIN
					for _, part in members do
						initialVelocity[part] = {
							linear = spin:Cross(bodyFor[part].frame.Position - pivot),
							angular = spin,
						}
					end
				end
			end

			for _, part in parts do
				release(part)
			end
		end

		checkpoint(settings.first)
		if not step then
			RunService.Heartbeat:Wait()
			checkpoint(settings.first)
		end

		liveParts()
		for _, body in bodies do
			local part = bySource[body.part]
			if retired[part] then
				continue
			end

			if not held[part] then
				part.AssemblyLinearVelocity = initialVelocity[part].linear
				part.AssemblyAngularVelocity = initialVelocity[part].angular
			end

			local attachment = Instance.new("Attachment")

			attachment.Parent = part
			local gravity = Instance.new("VectorForce")

			gravity.Attachment0 = attachment
			gravity.RelativeTo, gravity.ApplyAtCenterOfMass = Enum.ActuatorRelativeTo.World, true
			gravity.Force =
				Vector3.new(0, part:GetMass() * (workspace.Gravity - settings.gravity), 0)
			gravity.Parent = part
		end

		local affected, centers, forcePaths = {}, {}, {}
		for _, force in settings.forces or {} do
			if force.path then
				forcePaths[force] = Path.sampler(force.path)
			end
		end

		local function center(force, frame)
			local values = centers[force]
			if not values then
				values = {}
				centers[force] = values
			end

			local value = values[frame]
			if not value then
				local sample = forcePaths[force]
				value = force.position
					+ (
						sample
							and sample(
								Timing.sample(
									force.easing,
									(frame - force.frame) / math.max(1, (force.duration or 60) - 1)
								)
							)
						or Vector3.zero
					)
				values[frame] = value
			end

			return value
		end

		for _, guide in settings.guides or (settings.guide and { settings.guide } or {}) do
			local body = bodies[guide.index]
			local guidePart = bySource[body.part]
			if retired[guidePart] then
				continue
			end

			local guidePoints = table.clone(guide.points)
			guidePoints[1] = body.frame.Position
			local guideForce = Instance.new("AlignPosition")

			local attachment = Instance.new("Attachment")

			attachment.Parent = guidePart
			guideForce.Attachment0 = attachment
			guideForce.Mode = Enum.PositionAlignmentMode.OneAttachment
			guideForce.RigidityEnabled = true
			guideForce.Position = body.frame.Position
			guideForce.ApplyAtCenterOfMass = true
			guideForce.Parent = guidePart
			table.insert(guides, {
				force = guideForce,
				part = guidePart,
				points = guidePoints,
				sample = Path.sampler(guidePoints),
				easing = guide.easing,
			})
		end

		awaken(settings.first)
		table.clear(released)
		local impulses = {}
		for frame = settings.first + 1, settings.last do
			table.clear(centers)
			checkpoint(frame)
			liveParts()
			for _, mover in movers do
				local from, to = mover.frames[frame - 1], mover.frames[frame]
				if from and to then
					mover.part.CFrame = from
					mover.part.AssemblyLinearVelocity = (to.Position - from.Position) / dt
					local axis, angle = from:ToObjectSpace(to):ToAxisAngle()
					mover.part.AssemblyAngularVelocity = from:VectorToWorldSpace(axis)
						* (angle / dt)
				end
			end

			table.clear(impulses)
			for index, force in settings.forces or {} do
				local position = center(force, frame)
				local firstForce = force.frame == settings.first and settings.first + 1
					or force.frame
				if
					force.kind == "BlackHole"
					and frame == firstForce + (force.duration or 60)
					and (force.launch or 0) > 0
				then
					for part in affected[index] or {} do
						if retired[part] then
							continue
						end

						local direction = part.Position - position
						if force.path then
							direction = force.path[#force.path] - force.path[#force.path - 1]
						end

						if direction.Magnitude > 1e-5 then
							table.insert(
								impulses,
								{ part = part, velocity = direction.Unit * force.launch }
							)
						end
					end
				end

				local active = (force.kind == "BlackHole" or force.path ~= nil)
					and frame >= firstForce
					and frame < firstForce + (force.duration or 60)
				if
					active
					or not force.path
						and force.kind ~= "BlackHole"
						and (force.frame == frame or frame == settings.first + 1 and force.frame == settings.first)
				then
					local travelling = force.path ~= nil and force.kind ~= "BlackHole"
					local previous = travelling and center(force, math.max(force.frame, frame - 1))
						or nil
					local travel = travelling and position - previous or nil
					for _, part in parts do
						if retired[part] then
							continue
						end

						local hitPosition = position
						if travelling then
							if travel.Magnitude > 1e-5 then
								hitPosition = previous
									+ travel
										* math.clamp(
											(part.Position - previous):Dot(travel)
												/ travel:Dot(travel),
											0,
											1
										)
							end
						end

						local delta = part.Position - hitPosition
						local distance = delta.Magnitude
						if
							distance < force.radius
							and force.power > 0
							and (
								force.kind == "BlackHole"
								or not (affected[index] and affected[index][part])
							)
						then
							affected[index] = affected[index] or {}
							affected[index][part] = true

							local group = bodyFor[part].group or bodyFor[part].part
							for _, guide in guides do
								local guidedBody = bodyFor[guide.part]
								if
									guide.force
									and (guidedBody.group or guidedBody.part) == group
								then
									guide.force:Destroy()
									guide.force = nil
								end
							end

							if held[part] then
								for _, member in groups[bodyFor[part].group or bodyFor[part].part] do
									release(member)
								end
							end

							local direction = distance > 1e-5 and delta / distance or Vector3.yAxis
							if force.kind == "Pull" then
								direction = -direction
							elseif force.kind == "Lift" then
								direction = Vector3.yAxis
							end

							local falloff = 1 - distance / force.radius
							if force.path and force.kind ~= "BlackHole" then
								falloff = math.max(0.25, falloff)
							end

							table.insert(impulses, {
								part = part,
								velocity = direction * force.power * falloff,
								force = force.kind == "BlackHole" and force or nil,
								position = position,
							})
						end
					end
				end
			end

			if #released > 0 then
				if not step then
					RunService.Heartbeat:Wait()
					checkpoint(frame)
				end

				liveParts()
				for _, part in released do
					if retired[part] then
						continue
					end

					part.AssemblyLinearVelocity = initialVelocity[part].linear
					part.AssemblyAngularVelocity = initialVelocity[part].angular
				end

				table.clear(released)
				awaken(frame)
			end

			for _, impulse in impulses do
				local part = impulse.part
				if retired[part] then
					continue
				end

				local velocity = impulse.velocity
				if impulse.force then
					local force = impulse.force
					local frequency = math.sqrt(force.power / math.max(0.1, force.radius))
					local delta = part.Position - impulse.position
					local angle = math.clamp((force.spin or 1) * math.pi * 2 * dt, -0.35, 0.35)
					local target = CFrame.fromAxisAngle(Vector3.yAxis, angle)
						:VectorToWorldSpace(delta) * math.exp(-frequency * 0.35 * dt)
					local travel = (center(force, frame + 1) - impulse.position) / dt
					velocity = (target - delta) / dt + travel - part.AssemblyLinearVelocity
				end

				part:ApplyImpulse(velocity * part:GetMass())
			end

			for _, guide in guides do
				if guide.force and frame > (settings.pathEnd or settings.last) then
					guide.force:Destroy()
					guide.force = nil
					local launch = settings.pathLaunch or 0
					local delta = guide.points[#guide.points] - guide.points[#guide.points - 1]
					if launch > 0 and delta.Magnitude > 1e-5 then
						guide.part.AssemblyLinearVelocity = delta.Unit * launch
					end
				end

				if guide.force then
					local alpha = math.clamp(
						(frame - settings.first)
							/ ((settings.pathEnd or settings.last) - settings.first),
						0,
						1
					)
					guide.force.Position = guide.sample(Timing.sample(guide.easing, alpha))
				end
			end

			if activeCount > 0 then
				report.stepped += 1
				if step then
					step(dt, stepParts)
				else
					workspace:StepPhysics(dt, stepParts)
				end

				if not step then
					RunService.Heartbeat:Wait()
					checkpoint(frame)
				end

				for _, part in stepParts do
					if
						part.Anchored
						or held[part]
						or retired[part]
						or not part:IsDescendantOf(folder)
					then
						continue
					end

					local before, current = lastPose[part], part.CFrame
					if not before then
						continue
					end

					local travel = current.Position - before.Position
					local thickness = math.min(part.Size.X, part.Size.Y, part.Size.Z)
					if travel.Magnitude < math.max(0.05, thickness * 0.5) then
						continue
					end

					local hit = workspace:Blockcast(
						CFrame.new(before.Position) * current.Rotation,
						part.Size,
						travel,
						sweep
					)
					if not hit then
						continue
					end

					part.CFrame = CFrame.new(
						before.Position + travel.Unit * math.max(0, hit.Distance - 0.01)
					) * current.Rotation
					local velocity = part.AssemblyLinearVelocity
					local into = velocity:Dot(hit.Normal)
					if into < 0 then
						part.AssemblyLinearVelocity = velocity
							- hit.Normal * into * (1 + settings.bounce)
					end
				end
			else
				budget(frame)
			end

			if settings.hold and next(held) then
				for _, mover in movers do
					if mover.frames[frame] then
						mover.part.CFrame = mover.frames[frame]
					end
				end

				local candidates = {}
				for _, part in parts do
					if not held[part] and not retired[part] then
						table.insert(candidates, part)
					end
				end

				for _, mover in movers do
					table.insert(candidates, mover.part)
				end

				if #candidates > 0 then
					local query = OverlapParams.new()
					query.FilterType = Enum.RaycastFilterType.Include
					query.FilterDescendantsInstances = candidates
					local waiting = {}
					for part in held do
						if not retired[part] then
							table.insert(waiting, part)
						end
					end

					for _, part in waiting do
						if not held[part] then
							continue
						end

						for _, other in workspace:GetPartsInPart(part, query) do
							local velocity = other.AssemblyLinearVelocity
							if
								velocity.Magnitude > 0.5
								and velocity:Dot(part.Position - other.Position) > 0
							then
								for _, member in groups[bodyFor[part].group or bodyFor[part].part] do
									release(member)
								end

								break
							end
						end
					end

					local heldQuery = OverlapParams.new()
					heldQuery.FilterType = Enum.RaycastFilterType.Include
					heldQuery.FilterDescendantsInstances = waiting
					local hitters = {}
					for _, part in parts do
						if not held[part] and not retired[part] then
							table.insert(hitters, { part = part, previous = lastPose[part] })
						end
					end

					for _, mover in movers do
						table.insert(
							hitters,
							{ part = mover.part, previous = mover.frames[frame - 1] }
						)
					end

					for _, hitter in hitters do
						local other = hitter.part
						local velocity, spin =
							other.AssemblyLinearVelocity, other.AssemblyAngularVelocity
						if
							velocity.Magnitude + spin.Magnitude * other.Size.Magnitude * 0.5
							<= 0.5
						then
							continue
						end

						local nudge = if velocity.Magnitude > 1e-3
							then velocity.Unit * 0.05
							else Vector3.zero
						local turn = if spin.Magnitude > 1e-3
							then CFrame.fromAxisAngle(spin.Unit, spin.Magnitude * dt * 0.5)
							else CFrame.identity
						local probe = CFrame.new(other.Position + velocity * dt * 0.5 + nudge)
							* turn
							* other.CFrame.Rotation
						local before = {}
						if hitter.previous then
							for _, part in
								workspace:GetPartBoundsInBox(hitter.previous, other.Size, heldQuery)
							do
								before[part] = true
							end
						end

						for _, part in workspace:GetPartBoundsInBox(probe, other.Size, heldQuery) do
							if held[part] and not before[part] then
								for _, member in groups[bodyFor[part].group or bodyFor[part].part] do
									release(member)
								end
							end
						end
					end
				end
			end

			liveParts()
			for source, part in bySource do
				local cf = retired[part] and lastPose[part]
					or held[part] and bodyFor[part].frame
					or part.CFrame
				for _, value in { cf:GetComponents() } do
					assert(
						finite(value, -1e8, 1e8),
						"physics became unstable; lower the push and try again"
					)
				end

				lastPose[part] = cf
				poses[source][frame] = cf
			end
		end

		for _, part in parts do
			if held[part] and not retired[part] then
				report.held += 1
			end
		end

		return poses
	end, debug.traceback)
	folder:Destroy()

	for _, part in parts do
		part:Destroy()
	end

	for source in restoreCollide do
		if source.Parent then
			source.CanCollide = true
		end
	end

	for _, name in collisionGroups do
		pcall(PhysicsService.UnregisterCollisionGroup, PhysicsService, name)
	end

	assert(ok, result)
	return result, report
end

return Simulation
