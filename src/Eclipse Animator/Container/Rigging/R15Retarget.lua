--!nocheck
--!native
--// cracked by numan

const TweenService = game:GetService("TweenService")
local R15Retarget = {}

const ROOT = "HumanoidRootPart"
const REQUIRED = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
const OUTPUT = { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
const LIMBS = {
	{ target = "Left Arm", chain = { "LeftUpperArm", "LeftLowerArm", "LeftHand" }, leg = false },
	{ target = "Right Arm", chain = { "RightUpperArm", "RightLowerArm", "RightHand" }, leg = false },
	{ target = "Left Leg", chain = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" }, leg = true },
	{ target = "Right Leg", chain = { "RightUpperLeg", "RightLowerLeg", "RightFoot" }, leg = true },
}
const LEGACY_EASING = { Cubic = true, Elastic = true, Bounce = true }
const ANGLE_TOLERANCE = math.rad(0.2)
const POSITION_TOLERANCE = 0.003
const MAX_SPAN = 90
const PLANT_RANGE = 0.35
const PLANT_ITERATIONS = 4
const SUPPORT_BLEND = 0.08
const TWIST_LIMIT = 0.25

local function frame(up, reference)
	local x = reference - up * reference:Dot(up)
	if x.Magnitude < 1e-6 then
		x = Vector3.xAxis - up * up.X
		if x.Magnitude < 1e-6 then
			x = Vector3.zAxis - up * up.Z
		end
	end

	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, up, x:Cross(up))
end

local function restFrames(up, hinge, look)
	return { hinge = frame(up, hinge):Inverse(), look = frame(up, look):Inverse() }
end

local function aligned(up, hinge, look, rest)
	if (hinge - up * hinge:Dot(up)).Magnitude >= TWIST_LIMIT then
		return frame(up, hinge) * rest.hinge
	end

	return frame(up, look) * rest.look
end

local function liftFor(limb, anchor, height)
	local lift = 0
	for _ = 1, PLANT_ITERATIONS do
		const start = anchor + limb.base + Vector3.yAxis * lift
		const reach = limb.goal - start
		if reach.Magnitude < 1e-4 then
			break
		end

		const miss = height - (start.Y + reach.Unit.Y * limb.length)
		lift += miss
		if math.abs(miss) < 1e-4 then
			break
		end
	end

	return lift
end

local function aboveFloor(limb, start, height, thigh)
	const direction = limb.goal - start
	if direction.Magnitude < 1e-4 or start.Y + direction.Unit.Y * limb.length >= height then
		return direction
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-4 then
		const axis = -thigh.UpVector
		flat = Vector3.new(axis.X, 0, axis.Z)
		if flat.Magnitude < 1e-4 then
			return direction
		end
	end

	const drop = math.clamp((height - start.Y) / limb.length, -1, 1)
	return flat.Unit * math.sqrt(1 - drop * drop) + Vector3.yAxis * drop
end

local function easingDirection(style, direction)
	if LEGACY_EASING[style] then
		return direction == "In" and "Out" or direction == "Out" and "In" or direction
	end

	return direction
end

local function sample(track, time)
	const times, values = track.times, track.values
	const count = #times
	local index = track.cursor
	while index < count and times[index + 1] <= time do
		index += 1
	end

	while index > 1 and times[index] > time do
		index -= 1
	end

	track.cursor = index
	if time <= times[1] then
		return values[1]
	end

	if index >= count then
		return values[count]
	end

	const style = track.styles[index]
	if style == "Constant" then
		return values[index]
	end

	local alpha = (time - times[index]) / (times[index + 1] - times[index])
	if style ~= "Linear" then
		alpha = TweenService:GetValue(
			alpha,
			Enum.EasingStyle[style == "CubicV2" and "Cubic" or style],
			Enum.EasingDirection[easingDirection(style, track.directions[index])]
		)
	end

	return values[index]:Lerp(values[index + 1], alpha)
end

local function buildTracks(keys)
	const tracks = {}
	for _, key in keys do
		for _, pose in key:GetDescendants() do
			if not pose:IsA("Pose") or pose.Weight <= 0 or pose:GetAttribute("EclipseR6Control") then
				continue
			end

			local track = tracks[pose.Name]
			if not track then
				track = { times = {}, values = {}, styles = {}, directions = {}, cursor = 1 }
				tracks[pose.Name] = track
			end

			const value = pose.Weight < 1 and CFrame.identity:Lerp(pose.CFrame, pose.Weight) or pose.CFrame
			local index = #track.times
			if index == 0 or track.times[index] < key.Time then
				index += 1
			end

			track.times[index] = key.Time
			track.values[index] = value
			track.styles[index] = pose.EasingStyle.Name
			track.directions[index] = pose.EasingDirection.Name
		end
	end

	return tracks
end

function R15Retarget.sourceJoints(motors, defaults)
	defaults = defaults or {}
	const joints = {}
	for _, motor in motors do
		const bone = typeof(motor) == "table" and motor.IsEclipseBoneMotor == true
		if not bone and not (typeof(motor) == "Instance" and motor:IsA("Motor6D")) then
			continue
		end

		const part, parent = motor.Part1, motor.Part0
		if not part or not parent or part.Name == ROOT then
			continue
		end

		const existing = joints[part.Name]
		if existing and (not existing.bone or bone) then
			continue
		end

		const c1 = bone and CFrame.identity or motor.C1
		joints[part.Name] = {
			name = part.Name,
			parent = parent.Name,
			parentInstance = bone and motor.RealPart0 or parent,
			part = part,
			bone = bone,
			c0 = defaults[motor] or (bone and part.CFrame or motor.C0),
			c1 = c1,
			c1Inverse = c1:Inverse(),
		}
	end

	return joints
end

local function prepareSource(joints, rootPart)
	for _, name in REQUIRED do
		assert(joints[name], "R15 joint is missing: " .. name)
	end

	const order, visited = {}, {}
	local function visit(name)
		if visited[name] then
			return
		end

		visited[name] = true
		const joint = joints[name]
		if joints[joint.parent] then
			visit(joint.parent)
		end

		table.insert(order, joint)
	end

	for name in joints do
		visit(name)
	end

	const bases = {}
	for _, joint in order do
		const parent = joint.parent
		if not joints[parent] and parent ~= ROOT and not bases[parent] then
			const instance = joint.parentInstance
			bases[parent] = rootPart
					and typeof(instance) == "Instance"
					and instance:IsA("BasePart")
					and rootPart.CFrame:ToObjectSpace(instance.CFrame)
				or CFrame.identity
		end
	end

	return order, bases
end

local function solveSource(world, order, bases, poses, motion)
	world[ROOT] = motion * (poses[ROOT] or CFrame.identity)
	for name, base in bases do
		world[name] = motion * base
	end

	for _, joint in order do
		const parent = world[joint.parent] or motion
		const pose = poses[joint.name]
		world[joint.name] = if pose
			then parent * joint.c0 * pose * joint.c1Inverse
			else parent * joint.c0 * joint.c1Inverse
	end
end

local function socket(world, joint)
	return (world[joint.parent] or world[ROOT]) * joint.c0.Position
end

local function pivot(world, joint)
	return world[joint.name] * joint.c1.Position
end

local function bottom(part)
	return typeof(part) == "Instance" and part:IsA("BasePart") and Vector3.new(0, -part.Size.Y * 0.5, 0)
		or Vector3.zero
end

local function prepareTarget(target)
	const motors = {}
	for _, object in target:GetDescendants() do
		if object:IsA("Motor6D") and object.Part0 and object.Part1 then
			motors[object.Part1.Name] = object
		end
	end

	for _, name in OUTPUT do
		assert(motors[name], "R6 joint is missing: " .. name)
	end

	const rootJoint = motors.Torso
	const torsoRest = rootJoint.C0 * rootJoint.C1:Inverse()
	const rest = { Torso = torsoRest }
	for _, name in OUTPUT do
		if name ~= "Torso" then
			const motor = motors[name]
			assert(motor.Part0 == rootJoint.Part1, "R6 joint is not attached to the Torso: " .. name)
			rest[name] = torsoRest * motor.C0 * motor.C1:Inverse()
		end
	end

	return motors, rest
end

function R15Retarget.convert(sequence, joints, target, options)
	options = options or {}
	const order, bases = prepareSource(joints, options.rootPart)
	const motors, rest6 = prepareTarget(target)
	const rootJoint = motors.Torso
	const torsoRest = rest6.Torso
	const scale6 = target:IsA("Model") and target:GetScale() or 1
	const inverseScale = 1 / scale6

	const restWorld = {}
	solveSource(restWorld, order, bases, {}, CFrame.identity)

	const hipLocal = (motors["Left Leg"].C0.Position + motors["Right Leg"].C0.Position) * 0.5
	const origin6 = torsoRest * hipLocal
	local function hipCenter(world)
		return (socket(world, joints.LeftUpperLeg) + socket(world, joints.RightUpperLeg)) * 0.5
	end

	const origin15 = hipCenter(restWorld)
	const neckRest = socket(restWorld, joints.Head)
	local torsoUp = neckRest - origin15
	torsoUp = torsoUp.Magnitude > 1e-4 and torsoUp.Unit or restWorld.UpperTorso.UpVector
	const torsoFrames = restFrames(torsoUp, restWorld.UpperTorso.RightVector, restWorld.UpperTorso.LookVector)
	const pelvisRest = restWorld.LowerTorso.Rotation:Inverse()
	const headRest = restWorld.Head.Rotation:Inverse()

	const limbs = {}
	local ground15, ground6 = math.huge, math.huge
	for _, definition in LIMBS do
		const chain = {}
		for _, name in definition.chain do
			if joints[name] then
				table.insert(chain, joints[name])
			end
		end

		const upper, last = chain[1], chain[#chain]
		const motor = motors[definition.target]
		const limb = {
			leg = definition.leg,
			name = definition.target,
			motor = motor,
			upper = upper,
			last = last,
			tip = bottom(last.part),
			socket = motor.C0.Position,
			pivot = motor.C1.Position,
			rest = rest6[definition.target].Rotation,
			upperRest = restWorld[upper.name].Rotation:Inverse(),
		}

		const tip15 = restWorld[last.name] * limb.tip
		const hinge, look = restWorld[upper.name].RightVector, restWorld[upper.name].LookVector
		if limb.leg then
			const tip6 = rest6[definition.target] * bottom(motor.Part1)
			const reach = tip6 - torsoRest * limb.socket
			limb.length = reach.Magnitude
			limb.frames = restFrames(-reach.Unit, hinge, look)
			limb.tip15 = tip15
			limb.tip6 = tip6
			ground15 = math.min(ground15, tip15.Y)
			ground6 = math.min(ground6, tip6.Y)
		else
			local reach = tip15 - pivot(restWorld, upper)
			if reach.Magnitude < 1e-4 then
				reach = -restWorld[upper.name].UpVector
			end

			limb.reach = reach.Unit
			limb.frames = restFrames(-limb.reach, hinge, look)
		end

		table.insert(limbs, limb)
	end

	const legLength15 = origin15.Y - ground15
	const legLength6 = origin6.Y - ground6
	const ratio = legLength15 > 0.05 and legLength6 > 0.05 and legLength6 / legLength15 or 1
	for _, limb in limbs do
		if limb.leg then
			limb.correction = limb.tip6 - (origin6 + (limb.tip15 - origin15) * ratio)
		end
	end

	const keys = sequence:GetKeyframes()
	table.sort(keys, function(a, b)
		return a.Time < b.Time
	end)
	assert(#keys > 0, "This animation has no keyframes.")

	const tracks = buildTracks(keys)
	const poses, world = {}, {}
	const results = {}
	for _, name in OUTPUT do
		results[name] = table.create(#keys)
	end

	const rootMotion = options.rootMotion
	const sourceScale = options.sourceScale or 1
	local slice = os.clock()
	for index, key in keys do
		table.clear(poses)
		for name, track in tracks do
			const value = sample(track, key.Time)
			poses[name] = if sourceScale ~= 1 then CFrame.new(value.Position * sourceScale) * value.Rotation else value
		end

		const motion = rootMotion and rootMotion(key.Time) or CFrame.identity
		solveSource(world, order, bases, poses, motion)

		const hip = hipCenter(world)
		const upperTorso = world.UpperTorso
		local up = socket(world, joints.Head) - hip
		up = up.Magnitude > 1e-4 and up.Unit or upperTorso.UpVector
		const torsoRotation = aligned(up, upperTorso.RightVector, upperTorso.LookVector, torsoFrames) * torsoRest.Rotation
		local anchor = origin6 + (hip - origin15) * ratio
		const pelvis = world.LowerTorso.Rotation * pelvisRest

		local lowest = math.huge
		for _, limb in limbs do
			const upper = limb.upper
			limb.offset = (pivot(world, upper) - socket(world, upper)) * ratio
			if limb.leg then
				limb.goal = origin6 + (world[limb.last.name] * limb.tip - origin15) * ratio + pelvis * limb.correction
				limb.base = torsoRotation * (limb.socket - hipLocal) + limb.offset
				lowest = math.min(lowest, limb.goal.Y)
			end
		end

		local support, total = 0, 0
		for _, limb in limbs do
			if not limb.leg then
				continue
			end

			const blend = math.exp((lowest - limb.goal.Y) / (SUPPORT_BLEND * legLength6))
			total += blend
			const weight = math.clamp(1 - (limb.goal.Y - ground6) / (PLANT_RANGE * legLength6), 0, 1)
			if weight <= 0 then
				continue
			end

			support += blend * weight * math.clamp(liftFor(limb, anchor, limb.goal.Y), -legLength6, legLength6)
		end

		anchor += Vector3.yAxis * (total > 0 and support / total or 0)
		const torsoWorld = CFrame.new(anchor - torsoRotation * hipLocal) * torsoRotation
		results.Torso[index] = rootJoint.C0:Inverse() * torsoWorld * rootJoint.C1

		const headMotor = motors.Head
		const headRotation = world.Head.Rotation * headRest * rest6.Head.Rotation
		const headPivot = torsoWorld * headMotor.C0.Position + (pivot(world, joints.Head) - socket(world, joints.Head)) * ratio
		const headWorld = CFrame.new(headPivot - headRotation * headMotor.C1.Position) * headRotation
		results.Head[index] = (torsoWorld * headMotor.C0):Inverse() * headWorld * headMotor.C1

		for _, limb in limbs do
			const upperWorld = world[limb.upper.name]
			local start, direction
			if limb.leg then
				start = anchor + limb.base
				direction = aboveFloor(limb, start, math.min(ground6, limb.goal.Y), upperWorld)
			else
				start = torsoWorld * limb.socket + limb.offset
				direction = world[limb.last.name] * limb.tip - pivot(world, limb.upper)
			end

			if direction.Magnitude < 1e-4 then
				direction = upperWorld.Rotation * limb.upperRest * (limb.reach or -Vector3.yAxis)
			end

			const rotation = aligned(-direction.Unit, upperWorld.RightVector, upperWorld.LookVector, limb.frames)
				* limb.rest
			const partWorld = CFrame.new(start - rotation * limb.pivot) * rotation
			results[limb.name][index] = (torsoWorld * limb.motor.C0):Inverse() * partWorld * limb.motor.C1
		end

		if inverseScale ~= 1 then
			for _, name in OUTPUT do
				const value = results[name][index]
				results[name][index] = CFrame.new(value.Position * inverseScale) * value.Rotation
			end
		end

		if options.yield ~= false and os.clock() - slice > 0.012 then
			task.wait()
			slice = os.clock()
		end
	end

	const kept = R15Retarget.simplify(keys, results, options.simplify ~= false)
	const result = Instance.new("KeyframeSequence")
	result.Name, result.Loop, result.Priority = sequence.Name .. " R6", sequence.Loop, sequence.Priority
	const fps = sequence:GetAttribute("FPS")
	if typeof(fps) == "number" then
		result:SetAttribute("FPS", fps)
	end

	const rootName = rootJoint.Part0.Name
	for _, index in kept do
		const key = keys[index]
		const keyframe = Instance.new("Keyframe")
		keyframe.Name, keyframe.Time = key.Name, key.Time
		const exact = key:GetAttribute("EclipseExactFrame")
		if typeof(exact) == "number" then
			keyframe:SetAttribute("EclipseExactFrame", exact)
		end

		for _, marker in key:GetMarkers() do
			marker:Clone().Parent = keyframe
		end

		const root = Instance.new("Pose")
		root.Name = rootName
		root.Parent = keyframe
		local torso
		for _, name in OUTPUT do
			const pose = Instance.new("Pose")
			pose.Name = name
			pose.CFrame = results[name][index]
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			pose.EasingDirection = Enum.PoseEasingDirection.In
			pose.Parent = torso or root
			torso = torso or pose
		end

		keyframe.Parent = result
	end

	return result, {
		ratio = ratio,
		ground15 = ground15,
		ground6 = ground6,
	}
end

local function fits(times, results, first, last)
	const span = times[last] - times[first]
	for between = first + 1, last - 1 do
		const alpha = span > 0 and (times[between] - times[first]) / span or 0
		for _, values in results do
			const expected = values[first]:Lerp(values[last], alpha)
			const actual = values[between]
			if (expected.Position - actual.Position).Magnitude > POSITION_TOLERANCE then
				return false
			end

			const _, angle = expected:ToObjectSpace(actual):ToAxisAngle()
			if math.abs(angle) > ANGLE_TOLERANCE then
				return false
			end
		end
	end

	return true
end

function R15Retarget.simplify(keys, results, enabled)
	const count = #keys
	const kept = { 1 }
	if count <= 1 then
		return kept
	end

	const times = table.create(count)
	for index, key in keys do
		times[index] = key.Time
	end

	local anchor = 1
	for index = 2, count - 1 do
		const key = keys[index]
		const locked = not enabled
			or key.Name ~= "Keyframe"
			or #key:GetMarkers() > 0
			or index - anchor >= MAX_SPAN
		if locked or not fits(times, results, anchor, index + 1) then
			table.insert(kept, index)
			anchor = index
		end
	end

	table.insert(kept, count)
	return kept
end

return R15Retarget
