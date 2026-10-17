--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")
local Parenting = require("Parenting")
local TimelineState = require("RawState").Timeline
local MotorMath = require("MotorMath")
local Interp = require("Interp")
local Solver = require("LimbSolver")
local R6Controls = require("R6Controls")
local TorsoSolver = require("TorsoSolver")
local HeadStabilizer = require("HeadStabilizer")
local Preferences = require("Preferences")

local LimbIK = {}
local cache = setmetatable({}, { __mode = "k" })
local live = setmetatable({}, { __mode = "k" })
local memberChains = setmetatable({}, { __mode = "k" })
local legacyRigFrames = setmetatable({}, { __mode = "k" })
local legacyAnchors = setmetatable({}, { __mode = "k" })
local anchorPoseAttributes = {
	"EclipseFollowOffset",
	"EclipseIKEndRot",
	"EclipseIKEndOffset",
	"EclipseIKGoalOffset",
	"EclipseIKAimParentRotation",
}

local function valid(entry)
	for _, chain in entry.chains do
		for i, motor in chain.motors do
			local edge = chain.topology and chain.topology[i]
			if
				not motor.Parent
				or not motor.Part0
				or not motor.Part1
				or edge and (edge[1] ~= Parenting.realPart0(motor) or edge[2] ~= motor.Part1)
			then
				return false
			end
		end
	end

	return true
end

local function virtualTip(upper, lower)
	local rest = lower:GetAttribute("EclipseAutoIKRest2")
	if typeof(rest) ~= "CFrame" then
		rest = TimelineState.DefaultPose[lower] or lower.C0
	end

	const bone = rest.Position - upper.C1.Position
	const joint = lower.C1.Position
	local direction = -joint
	if direction.Magnitude < 1e-3 then
		direction = (rest * lower.C1:Inverse()):VectorToObjectSpace(bone)
	end

	direction = if direction.Magnitude > 1e-6 then direction.Unit else -Vector3.yAxis
	const part = lower.Part1
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		const half = part.Size * 0.5
		local reach = math.huge
		for _, axis in { "X", "Y", "Z" } do
			const component = math.abs(direction[axis])
			if component > 1e-6 then
				reach = math.min(reach, half[axis] / component)
			end
		end

		const tip = direction * reach
		if reach < math.huge and (tip - joint).Magnitude > 1e-3 then
			return tip
		end
	end

	return joint + direction * math.max(bone.Magnitude, 0.1)
end

function LimbIK.getRig(rig)
	if not rig then
		return nil
	end

	if rig:GetAttribute("EclipseIKSettingsVersion") ~= 2 then
		if rig:GetAttribute("EclipseR6BendPercent") == 74.2 then
			rig:SetAttribute("EclipseR6BendPercent", 65)
		end

		rig:SetAttribute("EclipseIKSettingsVersion", 2)
	end

	local entry = cache[rig]
	if entry and valid(entry) then
		return entry
	end

	if entry then
		LimbIK.invalidate(rig)
	end

	local motors = Parenting.collectMotors(rig)
	local map = Parenting.buildMotorMap(motors)
	local named = {}
	for _, motor in motors do
		if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local name = motor.Part1.Name
			if named[name] ~= nil then
				named[name] = false
			else
				named[name] = motor
			end
		end
	end

	entry = { rig = rig, motors = motors, map = map, chains = {}, owners = {}, members = {} }
	for _, side in { "Left", "Right" } do
		for _, limb in { "Arm", "Leg" } do
			local terminal = limb == "Arm" and "Hand" or "Foot"
			local upper, lower, endpoint =
				named[side .. "Upper" .. limb],
				named[side .. "Lower" .. limb],
				named[side .. terminal]
			local chain
			if
				upper
				and lower
				and endpoint
				and lower.Part0 == upper.Part1
				and endpoint.Part0 == lower.Part1
			then
				chain = {
					owner = endpoint,
					motors = { upper, lower, endpoint },
					kind = "R15",
					limb = limb,
				}
			else
				local motor = named[side .. " " .. limb]
				if motor and motor.Part0.Name == "Torso" and motor.Part1:IsA("BasePart") then
					chain = { owner = motor, motors = { motor }, kind = "R6", limb = limb }
				end
			end

			if chain then
				chain.entry = entry
				table.insert(entry.chains, chain)
				entry.owners[chain.owner] = chain
				R6Controls.rememberRig(chain.owner, rig)
				for _, member in chain.motors do
					entry.members[member] = chain
					memberChains[member] = chain
				end
			end
		end
	end

	if named.Torso and #entry.chains > 0 and entry.chains[1].kind == "R6" then
		local torso = {
			owner = named.Torso,
			motors = { named.Torso },
			kind = "Torso",
			limb = "Torso",
			entry = entry,
		}
		entry.torso = torso
		table.insert(entry.chains, 1, torso)
		entry.owners[torso.owner], entry.members[torso.owner], memberChains[torso.owner] =
			torso, torso, torso
	end

	local auto = require("customRest")
	local autoParents
	for _, owner in motors do
		if
			require("customRest").isJoint(owner)
			and owner:GetAttribute("EclipseAutoIK") == true
			and not entry.owners[owner]
		then
			autoParents = autoParents or auto.index(motors)
			local members = auto.chain(rig, owner, motors, autoParents)
			local free = members ~= nil
			for _, member in members or {} do
				if entry.members[member] then
					free = false
				end
			end

			if free then
				local chain = {
					owner = owner,
					motors = members,
					kind = "R15",
					limb = require("customRest").limbKind(owner),
					custom = true,
					tip = #members == 2 and virtualTip(members[1], owner) or nil,
					entry = entry,
				}
				table.insert(entry.chains, chain)
				entry.owners[owner] = chain
				R6Controls.rememberRig(owner, rig)
				for _, member in members do
					entry.members[member] = chain
					memberChains[member] = chain
				end
			end
		end
	end

	for _, chain in entry.chains do
		chain.topology = {}
		for i, motor in chain.motors do
			chain.topology[i] = { Parenting.realPart0(motor), motor.Part1 }
		end
	end

	cache[rig] = entry
	return entry
end

function LimbIK.cachedControlAnchor(owner)
	local chain = memberChains[owner]
	if
		not chain
		or chain.owner ~= owner
		or chain.kind ~= "R15"
		or cache[chain.entry.rig] ~= chain.entry
	then
		return nil
	end

	const motors = chain.motors
	const upper = motors[1]
	if
		not upper.Part0
		or not chain.owner.Part1
		or not chain.owner.Part1:IsDescendantOf(chain.entry.rig)
	then
		return nil
	end

	for i, motor in motors do
		if not motor.Parent or i > 1 and Parenting.realPart0(motor) ~= motors[i - 1].Part1 then
			return nil
		end
	end

	return upper.Part0, chain.entry.rig, chain.entry.map
end

function LimbIK.cachedCustomAnchor(owner)
	local chain = memberChains[owner]
	if not chain or not chain.custom then
		return nil
	end

	return LimbIK.cachedControlAnchor(owner)
end

function LimbIK.chain(rig, motor)
	local entry = LimbIK.getRig(rig)
	return entry and entry.owners[motor]
end

function LimbIK.drivingChain(motor, time)
	local chain = memberChains[motor]
	return chain and LimbIK.isEnabled(chain.owner, time) and chain or nil
end

function LimbIK.isDriven(motor, time)
	local chain = memberChains[motor]
	return chain ~= nil and LimbIK.isEnabled(chain.owner, time)
end

function LimbIK.restoreParented(chain, motor, time, source)
	local lastFK = -math.huge
	for _, key in source or TimelineState.Keyframes[chain.owner] or {} do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.IK == false and key.Time <= time then
			lastFK = math.max(lastFK, key.Time)
		end
	end

	local startTime = math.huge
	for _, key in source or TimelineState.Keyframes[chain.owner] or {} do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.IK == true and key.Time > lastFK and key.Time <= time then
			startTime = math.min(startTime, key.Time)
		end
	end

	local previous, saved
	for _, key in (motor == chain.owner and source) or TimelineState.Keyframes[motor] or {} do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.Time <= startTime and (not previous or key.Time > previous.Time) then
			previous = key
		end

		if
			key.Time >= startTime
			and key.Time <= time
			and typeof(key.IKRestoreParented) == "boolean"
			and (not saved or key.Time > saved.Time)
		then
			saved = key
		end
	end

	return saved and saved.IKRestoreParented
		or (
			not saved
			and Parenting.keyIsParented(motor, previous, TimelineState.ParentingDefaults[motor])
		)
end

function LimbIK.rootControl(chain)
	local upper = chain.motors[1]
	if chain.kind == "R15" then
		return Parenting.worldOf(upper, chain.entry.map) * upper.C1
	end

	return Parenting.worldOf(upper, chain.entry.map) * CFrame.new(0, upper.Part1.Size.Y * 0.5, 0)
end

function LimbIK.anchor(chain)
	local upper = chain.motors[1]
	if
		chain.entry.torsoBaseWorld
		and chain.entry.torso
		and upper.Part0 == chain.entry.torso.owner.Part1
	then
		return chain.entry.torsoBaseWorld
	end

	local parent = chain.entry.map[Parenting.realPart0(upper)]
	return parent and Parenting.worldOf(parent, chain.entry.map) or upper.Part0.CFrame
end

local switchIndices = setmetatable({}, { __mode = "k" })

local function switchesFor(motor, source)
	local bucket = require("Policy").activeBucket(source or TimelineState.Keyframes[motor])
	local revision = require("cache").revision()
	local cached = not source and switchIndices[motor]
	if cached and cached.bucket == bucket and cached.revision == revision then
		return cached.keys
	end
	local keys = {}
	for _, key in bucket or {} do
		if not key.GraphOnly and not key.Disabled and typeof(key.IK) == "boolean" then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b) return a.Time < b.Time end)
	if not source then
		switchIndices[motor] = { bucket = bucket, revision = revision, keys = keys }
	end
	return keys
end

function LimbIK.isEnabled(motor, time, source)
	local switches = switchesFor(motor, source)
	local low, high, found = 1, #switches, 0
	while low <= high do
		local middle = (low + high) // 2
		if switches[middle].Time <= time then
			found = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end
	return found > 0 and switches[found].IK == true, switches
end

local controlSections = setmetatable({}, { __mode = "k" })

function LimbIK.controlBucket(motor, time, bucket, tracks)
	if typeof(motor) ~= "table" or not motor.IsEclipseR6Control or not bucket then
		return bucket
	end

	local Policy = require("Policy")
	local ownerBucket = Policy.activeBucket((tracks or TimelineState.Keyframes)[motor.Owner])
	if not ownerBucket then
		return bucket
	end

	local revision = require("cache").revision()
	local cached = controlSections[bucket]
	if not cached or cached.owner ~= ownerBucket or cached.revision ~= revision then
		local boundaries = {}
		for _, key in ownerBucket do
			if not key.GraphOnly and not key.Disabled and key.IK == false then
				table.insert(boundaries, key.Time)
			end
		end

		table.sort(boundaries)
		cached =
			{ owner = ownerBucket, revision = revision, boundaries = boundaries, sections = {} }
		controlSections[bucket] = cached
	end

	local boundaries = cached.boundaries
	if #boundaries == 0 then
		return bucket
	end

	local low, high, index = 1, #boundaries, 0
	while low <= high do
		local middle = (low + high) // 2
		if boundaries[middle] <= time then
			index = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end

	local section = cached.sections[index]
	if not section then
		section = {}
		local first, last = boundaries[index] or -math.huge, boundaries[index + 1] or math.huge
		for frame, key in bucket do
			if key.Time > first and key.Time < last then
				section[frame] = key
			end
		end

		cached.sections[index] = section
	end

	return section
end

function LimbIK.transition(motor, time)
	if not Preferences.get("SmoothIKTransitions") then
		return nil
	end

	local switches = switchesFor(motor)

	local low, high, index = 1, #switches, 0
	while low <= high do
		local middle = (low + high) // 2
		if switches[middle].Time <= time then
			index = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end

	local a, b = switches[index], switches[index + 1]
	if not a or not b or a.IK == b.IK or time <= a.Time or time >= b.Time then
		return nil
	end

	if not a.IK then
		return nil
	end

	local ik = a.IK and a or b
	if not ik.IKTarget or not ik.IKPole then
		return nil
	end

	local fk = a.IK and b or a
	local chain = memberChains[motor]

	if not Parenting.keyIsParented(motor, fk, TimelineState.ParentingDefaults[motor]) then
		return nil
	end

	if chain then
		for _, member in chain.motors do
			if
				not Parenting.isParentedAt(
					member,
					TimelineState.Keyframes[member],
					fk.Time,
					TimelineState.ParentingDefaults[member]
				)
			then
				return nil
			end
		end
	end

	local alpha = math.clamp(require("Easing").apply((time - a.Time) / (b.Time - a.Time), a), 0, 1)
	return a.IK and 1 - alpha or alpha, ik.Time
end

function LimbIK.controlsVisible(motor, time)
	return LimbIK.hasAnimation(motor)
end

function LimbIK.hasAnimation(motor)
	local cache = require("cache").poseCache()
	if cache then
		cache.animated = cache.animated or setmetatable({}, { __mode = "k" })
		local value = cache.animated[motor]
		if value == nil then
			value = LimbIK.hasAnimationUncached(motor)
			cache.animated[motor] = value
		end

		return value
	end

	return LimbIK.hasAnimationUncached(motor)
end

function LimbIK.hasAnimationUncached(motor)
	for _, key in TimelineState.Keyframes[motor] or {} do
		if key.IK == true then
			return true
		end
	end

	for _, control in R6Controls.forOwner(motor) do
		if next(TimelineState.Keyframes[control] or {}) then
			return true
		end
	end

	return false
end

local function jointWorld(motor, map)
	local parent = map[Parenting.realPart0(motor)]
	return (parent and Parenting.worldOf(parent, map) or motor.Part0.CFrame) * motor.C0
end

local function segmentRotation(up, bend)
	up = up.Unit
	local side = bend - up * bend:Dot(up)
	if side.Magnitude < 1e-6 then
		local basis = math.abs(up.X) < 0.8 and Vector3.xAxis or Vector3.zAxis
		side = basis - up * basis:Dot(up)
	end

	local back = -side.Unit
	return CFrame.fromMatrix(Vector3.zero, up:Cross(back), up, back)
end

local function restFor(chain)
	local pose = TimelineState.DefaultPose
	local upper, lower, owner = chain.motors[1], chain.motors[2], chain.owner
	local upperRest = pose[upper] or upper.C0
	local kneeRest = upperRest * upper.C1:Inverse() * (pose[lower] or lower.C0)
	local ankleRest = kneeRest * lower.C1:Inverse() * (pose[owner] or owner.C0)
	local hip, knee, ankle = upperRest.Position, kneeRest.Position, ankleRest.Position
	local direction = ankle - hip
	direction = direction.Magnitude > 1e-6 and direction.Unit or Vector3.new(0, -1, 0)
	local frame = segmentRotation(
		-direction,
		chain.limb == "Leg" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
	)
	return {
		upperLength = math.max((knee - hip):Dot(direction), 1e-3),
		lowerLength = math.max((ankle - knee):Dot(direction), 1e-3),
		upperVector = frame:VectorToObjectSpace(knee - hip),
		lowerVector = frame:VectorToObjectSpace(ankle - knee),
		upper = frame:Inverse() * upperRest.Rotation,
		lower = frame:Inverse() * kneeRest.Rotation,
	}
end

local function solveSegments(chain, rest, hip, kneeNow, goal, pole, fallback)
	local scale = (kneeNow - hip).Magnitude / math.max(rest.upperVector.Magnitude, 1e-6)
	local upperLength, lowerLength = rest.upperLength * scale, rest.lowerLength * scale
	local soft = Preferences.get("SoftIKPercent")
	local correction = Vector3.zero
	local upperFrame, lowerFrame
	for _ = 1, 4 do
		local aim = goal + correction
		local reach = aim - hip
		local axis = reach.Magnitude > 1e-6 and reach.Unit or Vector3.new(0, -1, 0)
		local bend = pole - hip
		bend -= axis * bend:Dot(axis)
		if bend.Magnitude < 1e-6 then
			bend = fallback - axis * fallback:Dot(axis)
		end

		local knee, tip = Solver.twoLink(
			hip,
			hip + axis * upperLength,
			hip + axis * (upperLength + lowerLength),
			aim,
			hip + bend,
			fallback,
			soft
		)
		if not knee then
			break
		end

		upperFrame, lowerFrame =
			segmentRotation(hip - knee, bend), segmentRotation(knee - tip, bend)
		local actual = hip
			+ upperFrame * (rest.upperVector * scale)
			+ lowerFrame * (rest.lowerVector * scale)
		local miss = tip - actual
		if miss.Magnitude < 1e-4 then
			break
		end

		correction += miss
	end

	return upperFrame, lowerFrame
end

function LimbIK.geometry(chain)
	local map = chain.entry.map
	local upper = chain.motors[1]
	local upperWorld = Parenting.worldOf(upper, map)
	local root, middle, tip, target
	if chain.kind == "R6" then
		local half = upper.Part1.Size.Y * 0.5
		root = upperWorld:PointToWorldSpace(Vector3.new(0, half, 0))
		local bend = chain.entry.rig:GetAttribute("EclipseR6BendPercent")
		if typeof(bend) ~= "number" then
			bend = Preferences.get("R6BendPercent")
		end

		local fraction = math.clamp(bend / 200, 0.001, 0.5)
		middle =
			upperWorld:PointToWorldSpace(Vector3.new(0, half - upper.Part1.Size.Y * fraction, 0))
		tip = upperWorld:PointToWorldSpace(Vector3.new(0, -half, 0))
		target = CFrame.new(tip) * upperWorld.Rotation
	else
		root = jointWorld(upper, map).Position
		const motors = chain.motors
		if #motors > 3 then
			const line = jointWorld(chain.owner, map).Position - root
			local distance = -1
			for i = 2, #motors - 1 do
				const point = jointWorld(motors[i], map).Position
				local offset = point - root
				if line.Magnitude > 1e-6 then
					offset -= line.Unit * offset:Dot(line.Unit)
				end

				if offset.Magnitude > distance then
					middle, distance = point, offset.Magnitude
				end
			end
		else
			middle = jointWorld(motors[2], map).Position
		end
		if chain.tip then
			const ownerWorld = Parenting.worldOf(chain.owner, map)
			tip = ownerWorld:PointToWorldSpace(chain.tip)
			target = CFrame.new(tip) * ownerWorld.Rotation
		else
			target = jointWorld(chain.owner, map)
			tip = target.Position
		end
	end

	local parent = map[Parenting.realPart0(upper)]
	local parentWorld = parent and Parenting.worldOf(parent, map) or upper.Part0.CFrame
	local fallback = parentWorld.LookVector * (chain.limb == "Leg" and 1 or -1)
	return root, middle, tip, target, fallback
end

function LimbIK.controlMotor(chain, kind)
	local bone = R6Controls.find(chain.owner, kind)
	return bone and R6Controls.get(bone)
end

function LimbIK.defaultLegPole(chain, target)
	return target
		* CFrame.new(
			0,
			0.276338875 * chain.owner.Part1.Size.Y,
			-0.63667137 * chain.owner.Part1.Size.Y
		)
end

function LimbIK.legPoleWorld(owner, relative)
	local chain = LimbIK.chain(owner.Part1.Parent, owner)
	if not chain then
		return owner.Part0.CFrame * relative
	end

	local state = LimbIK.state(chain)
	local target = state and state.target or select(1, LimbIK.capturePose(chain))
	return target * relative
end

function LimbIK.controlWorld(chain, kind, fallback)
	local motor = LimbIK.controlMotor(chain, kind)
	if not motor then
		return fallback
	end

	if motor.IsFootRelativePole then
		return LimbIK.legPoleWorld(chain.owner, R6Controls.value(motor, TimelineState.DefaultPose))
	end

	local parent = chain.entry.map[motor.RealPart0]
	local anchor = parent and Parenting.worldOf(parent, chain.entry.map) or motor.Part0.CFrame
	return anchor * R6Controls.value(motor, TimelineState.DefaultPose)
end

function LimbIK.torsoDelta(chain, baseC0, reference, parentWorld)
	local anchor = parentWorld or LimbIK.anchor(chain)
	local base = anchor * baseC0 * chain.owner.C1:Inverse()
	return reference and base * reference:Inverse() or CFrame.identity
end

local function footRollOffset(chain, display, pitch)
	local foot = chain.owner.Part1
	if foot and foot:IsA("BasePart") then
		return Vector3.new(0, chain.tip and 0 or -foot.Size.Y * 0.5 - chain.owner.C1.Position.Y,
			display and foot.Size.Z * 0.6 + 0.2 or (pitch >= 0 and foot.Size.Z * 0.5 or -foot.Size.Z * 0.5))
	end
	if display then
		local length = (chain.owner.C0.Position - chain.owner.C1.Position).Magnitude
		return Vector3.new(0, 0, math.max(length * 0.35, 0.2))
	end
	return Vector3.zero
end

function LimbIK.baseControlFrame(chain, kind, state)
	state = state or LimbIK.state(chain)
	if not state then
		return nil
	end

	if chain.kind == "R15" and kind == "upperFK" then
		return jointWorld(chain.motors[1], chain.entry.map)
	end

	if chain.kind == "Torso" then
		if kind == "fk" then
			return Parenting.worldOf(chain.owner, chain.entry.map)
		end

		local base = LimbIK.anchor(chain) * state.baseC0 * chain.owner.C1:Inverse()
		return TorsoSolver.controlFrame(
			base,
			chain.owner.Part1.Size.Y,
			state.root,
			state.target,
			kind
		)
	end

	if chain.kind == "R15" and kind == "roll" then
		local control = LimbIK.controlMotor(chain, "roll")
		local roll = state.roll or LimbIK.controlWorld(chain, "roll", state.target)
		local parent = control and chain.entry.map[Parenting.realPart0(control)]
		local anchor = control
			and (parent and Parenting.worldOf(parent, chain.entry.map) or control.Part0.CFrame)
		local rest = control and (TimelineState.DefaultPose[control] or control.Bone.CFrame)
		local delta = anchor and (anchor * rest):ToObjectSpace(roll) or CFrame.identity
		return state.target
			* CFrame.new(footRollOffset(chain, true))
			* delta.Rotation
	end

	if kind == "pole" and state.pole then
		local control = LimbIK.controlMotor(chain, kind)
		local offset = control and control:GetAttribute("EclipsePoleDisplayOffset")
		local pivot = control and control:GetAttribute("EclipsePolePivotOffset")
		if typeof(pivot) == "Vector3" then
			offset = (typeof(offset) == "Vector3" and offset or Vector3.zero) + pivot
		end
		if typeof(offset) == "Vector3" then
			return state.pole * CFrame.new(offset)
		end
	end

	return state[kind] or LimbIK.rootControl(chain)
end

const GRAB_KINDS = { target = true, root = true, roll = true }

local function grabAnchor(chain, control)
	const parent = chain.entry.map[control.RealPart0]
	return parent and Parenting.worldOf(parent, chain.entry.map) or control.Part0.CFrame
end

function LimbIK.canGrab(chain, kind)
	return chain.kind ~= "Torso" and GRAB_KINDS[kind] == true and LimbIK.controlMotor(chain, kind) ~= nil
end

local function grabOffset(chain, kind)
	if chain.kind == "Torso" or not GRAB_KINDS[kind] then
		return nil
	end

	const control = LimbIK.controlMotor(chain, kind)
	const offset = control and control:GetAttribute("EclipseGrabOffset")
	if
		typeof(offset) ~= "Vector3"
		or not (offset.Magnitude >= 1e-6 and offset.Magnitude < math.huge)
	then
		return nil
	end

	return grabAnchor(chain, control):VectorToWorldSpace(offset)
end

function LimbIK.controlFrame(chain, kind, state)
	const frame = LimbIK.baseControlFrame(chain, kind, state)
	const offset = frame and grabOffset(chain, kind)
	return if offset then frame + offset else frame
end

function LimbIK.grabOffsetFor(chain, kind, world)
	const control = LimbIK.canGrab(chain, kind) and LimbIK.controlMotor(chain, kind)
	const frame = control and LimbIK.baseControlFrame(chain, kind)
	if not frame then
		return nil
	end

	return grabAnchor(chain, control):VectorToObjectSpace(world - frame.Position)
end

local function writeControlWorld(chain, kind, value)
	local control = LimbIK.controlMotor(chain, kind)
	if not control or control:GetAttribute("EclipseDisabled") then
		return false
	end

	if control.IsFootRelativePole then
		local state = LimbIK.state(chain)
		if not state then
			return false
		end

		control.C0 = state.target:ToObjectSpace(value)
		return true
	end

	local parent = chain.entry.map[control.RealPart0]
	local anchor = parent and Parenting.worldOf(parent, chain.entry.map) or control.Part0.CFrame
	local torsoState = chain.kind == "Torso" and LimbIK.state(chain)
	if torsoState then
		value = LimbIK.torsoDelta(chain, torsoState.baseC0, torsoState.baseWorld)
			:ToObjectSpace(value)
	end

	control.C0 = anchor:ToObjectSpace(value)
	if torsoState then
		torsoState[kind == "spine" and "torsoSpineEdited" or "torsoUpperEdited"] = true
	end

	return true
end

function LimbIK.setDisplayControl(chain, kind, value)
	const grab = grabOffset(chain, kind)
	if grab then
		value -= grab
	end

	if chain.kind == "R15" and kind == "upperFK" then
		local state = LimbIK.state(chain)
		if not state or chain.owner:GetAttribute("EclipseDisabled") then
			return
		end

		local current = LimbIK.controlFrame(chain, kind, state)
		local delta = value * current:Inverse()

		local values = {}
		for _, controlKind in { "root", "target", "pole" } do
			local control = LimbIK.controlMotor(chain, controlKind)
			if control then
				if control:GetAttribute("EclipseDisabled") then
					return
				end

				local previous = state[controlKind]
					or LimbIK.controlWorld(chain, controlKind, state.target)
				values[controlKind] = delta * previous
			end
		end

		for controlKind, world in values do
			writeControlWorld(chain, controlKind, world)
			state[controlKind] = world
		end

		state.dirty = true
		LimbIK.apply(chain.entry.rig, TimelineState.CurrentTime, false)
		return
	end

	if chain.kind == "R15" and kind == "roll" then
		local state = LimbIK.state(chain)
		if not state then
			return
		end

		local current = state.roll or LimbIK.controlWorld(chain, "roll", state.target)
		local display = LimbIK.controlFrame(chain, kind, state)
		LimbIK.setControl(
			chain,
			kind,
			(current.Rotation * display.Rotation:Inverse() * value.Rotation) + current.Position
		)
		return
	end

	if chain.kind ~= "Torso" then
		if kind == "pole" then
			local control = LimbIK.controlMotor(chain, kind)
			local offset = control and control:GetAttribute("EclipsePoleDisplayOffset")
			local pivot = control and control:GetAttribute("EclipsePolePivotOffset")
			if typeof(pivot) == "Vector3" then
				offset = (typeof(offset) == "Vector3" and offset or Vector3.zero) + pivot
			end
			if typeof(offset) == "Vector3" then
				value = value * CFrame.new(-offset)
			end
		end

		LimbIK.setControl(chain, kind, value)
		return
	end

	local state = LimbIK.state(chain)
	if not state or chain.owner:GetAttribute("EclipseDisabled") then
		return
	end

	local anchor = LimbIK.anchor(chain)
	local base = anchor * state.baseC0 * chain.owner.C1:Inverse()
	if kind == "fk" then
		local delta = value * Parenting.worldOf(chain.owner, chain.entry.map):Inverse()
		state.baseC0 = anchor:ToObjectSpace(delta * base) * chain.owner.C1
		state.dirty = true
		LimbIK.apply(chain.entry.rig, TimelineState.CurrentTime, false)
	else
		local display =
			TorsoSolver.controlFrame(base, chain.owner.Part1.Size.Y, state.root, state.target, kind)
		local delta = value * display:Inverse()
		local _, angle = delta:ToAxisAngle()
		if math.abs(angle) > 1e-6 then
			local root, target = delta * state.root, delta * state.target
			writeControlWorld(chain, "spine", root)
			writeControlWorld(chain, "upper", target)
			state.dirty = true
			LimbIK.apply(chain.entry.rig, TimelineState.CurrentTime, false)
		else
			LimbIK.setControl(
				chain,
				kind,
				TorsoSolver.controlValue(
					base,
					chain.owner.Part1.Size.Y,
					state.root,
					state.target,
					kind,
					value
				)
			)
		end
	end
end

function LimbIK.prepare(chain)
	if chain.custom then
		for i, motor in chain.motors do
			local name = "EclipseAutoIKRest" .. i
			if typeof(chain.owner:GetAttribute(name)) ~= "CFrame" then
				chain.owner:SetAttribute(name, TimelineState.DefaultPose[motor] or motor.C0)
			end
		end
	end

	if chain.kind == "R15" then
		local target, pole, _, _, root = LimbIK.capturePose(chain)
		for kind, world in { root = root, target = target, pole = pole, roll = target } do
			if kind == "roll" and chain.limb ~= "Leg" then
				continue
			end

			local part = R6Controls.anchor(chain.owner, kind)
			local parent = chain.entry.map[part]
			local anchor = parent and Parenting.worldOf(parent, chain.entry.map) or part.CFrame
			R6Controls.ensure(chain.owner, kind, anchor:ToObjectSpace(world))
		end

		chain.entry.motors = Parenting.collectMotors(chain.entry.rig)
		chain.entry.map = Parenting.buildMotorMap(chain.entry.motors)
		return R6Controls.forOwner(chain.owner)
	end

	if chain.kind ~= "R6" and chain.kind ~= "Torso" then
		return {}
	end

	local anchor = LimbIK.anchor(chain)
	local world = Parenting.worldOf(chain.owner, chain.entry.map)
	if chain.entry.rig:GetAttribute("EclipseR6BendPercent") == nil then
		chain.entry.rig:SetAttribute("EclipseR6BendPercent", Preferences.get("R6BendPercent"))
	end

	if chain.kind == "Torso" then
		local height = chain.owner.Part1.Size.Y
		R6Controls.ensure(
			chain.owner,
			"spine",
			anchor:ToObjectSpace(world * CFrame.new(0, -height * 0.5, 0))
		)
		R6Controls.ensure(
			chain.owner,
			"upper",
			anchor:ToObjectSpace(world * CFrame.new(0, height * 0.45, 0))
		)
	else
		R6Controls.ensure(chain.owner, "root", anchor:ToObjectSpace(LimbIK.rootControl(chain)))
		if chain.limb == "Leg" then
			local target = LimbIK.capturePose(chain)
			R6Controls.ensure(
				chain.owner,
				"pole",
				target:ToObjectSpace(LimbIK.defaultLegPole(chain, target))
			)
		end
	end

	chain.entry.motors = Parenting.collectMotors(chain.entry.rig)
	chain.entry.map = Parenting.buildMotorMap(chain.entry.motors)
	return R6Controls.forOwner(chain.owner)
end

local r15Rest, r15ArmAngle, r15ArmRotation
local R15_LEG_BEND_EPSILON = 0.001

function LimbIK.capturePose(chain)
	if chain.kind == "Torso" then
		local world = Parenting.worldOf(chain.owner, chain.entry.map)
		local height = chain.owner.Part1.Size.Y
		return world * CFrame.new(0, height * 0.45, 0),
			world,
			chain.owner.C0,
			world,
			world * CFrame.new(0, -height * 0.5, 0)
	end

	local root, middle, tip, target, fallback = LimbIK.geometry(chain)

	local direction = tip - root
	local bend = middle - root
	if chain.kind == "R15" and chain.limb == "Arm" and not chain.custom then
		local upper = chain.motors[1]
		local rest = r15Rest(chain)
		local rotation, reference = r15ArmRotation(rest, r15ArmAngle(rest, direction.Magnitude))
		bend = jointWorld(upper, chain.entry.map):VectorToWorldSpace(rotation:VectorToObjectSpace(reference))
	end
	if direction.Magnitude > 1e-6 then
		bend -= direction.Unit * bend:Dot(direction.Unit)
	end

	local length = (middle - root).Magnitude + (tip - middle).Magnitude
	local tolerance = chain.kind == "R15" and (chain.limb == "Leg" and R15_LEG_BEND_EPSILON or 1e-4)
		or 1e-5
	if bend.Magnitude < tolerance then
		bend = fallback
		if direction.Magnitude > 1e-6 then
			const axis = direction.Unit
			bend -= axis * bend:Dot(axis)
			if bend.Magnitude < 1e-3 then
				const basis = if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
				bend = basis - axis * basis:Dot(axis)
			end
		end
	end

	return target,
		CFrame.new(root + bend.Unit * math.max(length * 0.6, 0.2)),
		chain.owner.C0,
		Parenting.worldOf(chain.owner, chain.entry.map),
		LimbIK.rootControl(chain)
end

function LimbIK.keyAnchor(key)
	return key.IKAnchor or legacyAnchors[key]
end

function LimbIK.feetPlanted(chain)
	if chain.limb ~= "Leg" then
		return false
	end

	local value = chain.entry.rig:GetAttribute("EclipseIKFeetPlanted")
	if value == nil then
		value = Preferences.get("IKFeetPlanted")
	end

	return value == true
end

function LimbIK.rigFrame(chain)
	local rig = chain.entry.rig
	local root = rig and rig:FindFirstChild("HumanoidRootPart")
	if not root then
		return CFrame.identity
	end

	local motor = chain.entry.map[root]
	return motor and Parenting.worldOf(motor, chain.entry.map) or root.CFrame
end

local function keyRigFrame(chain, key, worldAt)
	if key.IKRigWorld then
		return key.IKRigWorld
	end

	if legacyRigFrames[key] then
		return legacyRigFrames[key]
	end

	local frame = LimbIK.rigFrame(chain)
	local parent = chain.entry.map[Parenting.realPart0(chain.motors[1])]
	local root = chain.entry.rig and chain.entry.rig:FindFirstChild("HumanoidRootPart")
	local rootMotor = root and chain.entry.map[root]
	if worldAt and key.IKAnchor and parent then
		local parentFrame = worldAt(parent, key.Time)
		local rootFrame = rootMotor and worldAt(rootMotor, key.Time) or frame
		frame = key.IKAnchor * parentFrame:Inverse() * rootFrame
	end

	legacyRigFrames[key] = frame
	return frame
end

local function sampleTargets(chain, time, worldAt, source, forceFollow)
	local motor = chain.owner
	local previous, following
	local leftBoundary, rightBoundary = -math.huge, math.huge
	for _, key in source or TimelineState.Keyframes[motor] or {} do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.IK == false then
			if key.Time <= time then
				leftBoundary = math.max(leftBoundary, key.Time)
			else
				rightBoundary = math.min(rightBoundary, key.Time)
			end
		end
	end

	local candidates = {}
	for frame, key in source or TimelineState.Keyframes[motor] or {} do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if
			key.IK == true
			and key.IKTarget
			and key.IKPole
			and key.Time > leftBoundary
			and key.Time < rightBoundary
		then
			candidates[frame] = key
			if key.Time <= time and (not previous or key.Time > previous.Time) then
				previous = key
			end

			if key.Time >= time and (not following or key.Time < following.Time) then
				following = key
			end
		end
	end

	if not previous then
		return nil
	end

	local follows = chain.kind == "R15" and previous.IKPoleFollowsTarget == true
	if forceFollow ~= nil then
		follows = forceFollow
	end

	local parented = chain.kind ~= "R6" and not LimbIK.feetPlanted(chain)
	local anchor = LimbIK.anchor(chain)
	local rigFrame = LimbIK.rigFrame(chain)

	local function convert(key)
		local entry = table.clone(key)
		entry.PathTangentIn, entry.PathTangentOut = nil, nil
		local reference = key.IKAnchor
		if not reference then
			local parent = chain.entry.map[Parenting.realPart0(chain.motors[1])]
			if worldAt and parent then
				legacyAnchors[key] = worldAt(parent, key.Time)
			end

			reference = legacyAnchors[key] or anchor
		end

		if not parented then
			local reference = keyRigFrame(chain, key, worldAt)
			if rigFrame ~= reference then
				local delta = rigFrame * reference:Inverse()
				entry.IKTarget = delta * key.IKTarget
				entry.IKPole = delta * key.IKPole
			end
		end

		if parented then
			entry.IKTarget = reference:ToObjectSpace(key.IKTarget)
			entry.IKPole = reference:ToObjectSpace(key.IKPole)
			if chain.kind == "Torso" and key.IKBaseWorld then
				entry.IKBaseWorld = reference:ToObjectSpace(key.IKBaseWorld)
			end
		end

		if follows then
			entry.IKPole = key.IKTarget:ToObjectSpace(key.IKPole)
		end

		if key.IKRoot then
			entry.IKRoot = reference:ToObjectSpace(key.IKRoot)
		end

		return entry
	end

	if not following or following == previous then
		local a = convert(previous)
		local target, pole, baseWorld, rootControl = a.IKTarget, a.IKPole, a.IKBaseWorld, a.IKRoot
		if parented then
			target, pole = anchor * target, follows and pole or anchor * pole
			if chain.kind == "Torso" and baseWorld then
				baseWorld = anchor * baseWorld
			end
		end

		if rootControl then
			rootControl = anchor * rootControl
		end

		if follows then
			pole = target * pole
		end

		return target, pole, a.IKBaseC0, baseWorld, parented, rootControl, follows
	end

	local bucket = {}
	local a, z = convert(previous), following and convert(following)
	bucket[a.Time] = a
	if z then
		bucket[z.Time] = z
	end

	local before, after
	for _, key in candidates do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.Time <= leftBoundary or key.Time >= rightBoundary then
			continue
		end

		if key.Time < previous.Time and (not before or key.Time > before.Time) then
			before = key
		end

		if following and key.Time > following.Time and (not after or key.Time < after.Time) then
			after = key
		end
	end

	if before then
		bucket[before.Time] = convert(before)
	end

	if after then
		bucket[after.Time] = convert(after)
	end

	local target, pole, baseC0, baseWorld = a.IKTarget, a.IKPole, a.IKBaseC0, a.IKBaseWorld
	local rootControl = a.IKRoot
	if z and following ~= previous then
		local alpha = (time - previous.Time) / (following.Time - previous.Time)
		target = Interp.cframe(bucket, a, z, alpha, "IKTarget")
		pole = Interp.cframe(bucket, a, z, alpha, "IKPole")
		if a.IKRoot and z.IKRoot then
			rootControl = Interp.cframe(bucket, a, z, alpha, "IKRoot")
		end

		baseC0 = Interp.cframe(bucket, a, z, alpha, "IKBaseC0")
		baseWorld = Interp.cframe(bucket, a, z, alpha, "IKBaseWorld")
	end

	if parented then
		target, pole = anchor * target, follows and pole or anchor * pole
		if chain.kind == "Torso" and baseWorld then
			baseWorld = anchor * baseWorld
		end
	end

	if rootControl then
		rootControl = anchor * rootControl
	end

	if follows then
		pole = target * pole
	end

	return target, pole, baseC0, baseWorld, parented, rootControl, follows
end

function LimbIK.keyStateAt(chain, time, source)
	local enabled = LimbIK.isEnabled(chain.owner, time, source)
	local result = { IK = enabled }
	if enabled then
		local target, pole, baseC0, baseWorld, _, root, follow =
			sampleTargets(chain, time, nil, source)
		result.IKTarget, result.IKPole, result.IKBaseC0, result.IKBaseWorld =
			target, pole, baseC0, baseWorld
		result.IKRoot, result.IKAnchor = root, LimbIK.anchor(chain)
		result.IKPoleFollowsTarget = follow
		result.IKRigWorld = LimbIK.rigFrame(chain)
		result.IKRestoreParented = LimbIK.restoreParented(chain, chain.owner, time, source)
	end

	return result
end

function LimbIK.state(chain, time, resample, worldAt)
	if time == nil then
		time = TimelineState.CurrentTime
		if TimelineState.Playing then
			time = math.floor(time * TimelineState.FPS + 1e-6) / TimelineState.FPS
		end
	end

	local enabled, switches = LimbIK.isEnabled(chain.owner, time)
	if not enabled and switches and #switches < 2 then
		live[chain.owner] = nil
		return nil
	end

	local blend, sampleTime
	if not switches or #switches >= 2 then
		blend, sampleTime = LimbIK.transition(chain.owner, time)
	end

	if not enabled and not blend then
		live[chain.owner] = nil
		return nil
	end

	local state = live[chain.owner]
	if not state or state.time ~= time or resample then
		local target, pole, baseC0, baseWorld, targetParented, rootControl, follow =
			sampleTargets(chain, sampleTime or time, worldAt)
		if not target then
			target, pole, baseC0, baseWorld, rootControl = LimbIK.capturePose(chain)
		end

		state = {
			poleFollowsTarget = follow == true,
			chain = chain,
			time = time,
			target = target,
			pole = pole,
			baseC0 = baseC0,
			baseWorld = baseWorld,
			rigFrame = LimbIK.rigFrame(chain),
			anchor = LimbIK.anchor(chain),
			targetParented = targetParented,
			root = rootControl,
			parented = Parenting.isParentedAt(
				chain.owner,
				TimelineState.Keyframes[chain.owner],
				time,
				TimelineState.ParentingDefaults[chain.owner]
			),
		}
		if chain.kind == "Torso" then
			local base = (LimbIK.anchor(chain) * state.baseC0 * chain.owner.C1:Inverse()):Orthonormalize()
			state.torsoSpineInput = base:ToObjectSpace(state.root):Orthonormalize()
			state.torsoUpperInput = base:ToObjectSpace(state.target):Orthonormalize()
		end

		if follow then
			state.referenceTarget, state.referencePole =
				sampleTargets(chain, sampleTime or time, worldAt, nil, false)
			state.followFresh = true
		end

		live[chain.owner] = state
	else
		local frame = LimbIK.rigFrame(chain)
		if not state.targetParented and frame ~= state.rigFrame then
			local delta = frame * state.rigFrame:Inverse()
			state.target, state.pole = delta * state.target, delta * state.pole
		end

		state.rigFrame = frame
		if state.targetParented or chain.kind == "R6" then
			local anchor = LimbIK.anchor(chain)
			if anchor ~= state.anchor then
				local delta = anchor * state.anchor:Inverse()
				if state.targetParented then
					state.target, state.pole = delta * state.target, delta * state.pole
				end

				if state.root then
					state.root = delta * state.root
				end

				if chain.kind == "Torso" and state.baseWorld then
					state.baseWorld = delta * state.baseWorld
				end

				state.anchor = anchor
			end
		end
	end

	state.blend = blend
	if chain.kind == "R15" then
		local previousTarget = state.target
		local freshFollow = state.followFresh
		local relative
		if freshFollow then
			relative = previousTarget:Orthonormalize():ToObjectSpace(state.pole):Orthonormalize()
		end

		if state.followFresh then
			local control = LimbIK.controlMotor(chain, "pole")
			if
				control
				and Parenting.bounds(TimelineState.Keyframes[control], time)
				and state.referenceTarget
				and state.referencePole
			then
				local helper = LimbIK.controlWorld(chain, "pole", state.referencePole)
				relative = state.referenceTarget:ToObjectSpace(helper)
					* state.referenceTarget:ToObjectSpace(state.referencePole):Inverse()
					* relative
			end

			state.followFresh = nil
		end

		for _, kind in { "root", "target", "pole", "roll" } do
			local control = LimbIK.controlMotor(chain, kind)
			if
				control
				and not (kind == "pole" and state.poleFollowsTarget)
				and Parenting.bounds(
					TimelineState.Keyframes[control],
					time or TimelineState.CurrentTime
				)
			then
				state[kind] = LimbIK.controlWorld(chain, kind, state[kind])
			end
		end

		if state.poleFollowsTarget and (freshFollow or state.target ~= previousTarget) then
			relative = relative
				or previousTarget:Orthonormalize():ToObjectSpace(state.pole):Orthonormalize()
			state.pole = state.target:Orthonormalize() * relative
		end
	elseif chain.kind == "R6" then
		state.root = LimbIK.controlWorld(chain, "root", state.root)
		local control = chain.limb == "Leg" and LimbIK.controlMotor(chain, "pole")
		if control then
			state.pole = state.target * R6Controls.value(control, TimelineState.DefaultPose)
		end
	elseif chain.kind == "Torso" then
		local reference = (
			state.baseWorld or LimbIK.anchor(chain) * state.baseC0 * chain.owner.C1:Inverse()
		):Orthonormalize()

		local function input(kind, field, edited, fallback)
			local control = LimbIK.controlMotor(chain, kind)

			if
				control
				and (state[edited] or Parenting.bounds(TimelineState.Keyframes[control], time))
			then
				local value = LimbIK.controlWorld(chain, kind, fallback)
				state[field] = reference:ToObjectSpace(value):Orthonormalize()
				return value
			end

			state[field] = state[field] or reference:ToObjectSpace(fallback):Orthonormalize()
			return reference * state[field]
		end

		local delta = LimbIK.torsoDelta(chain, state.baseC0, state.baseWorld)
		state.root = delta * input("spine", "torsoSpineInput", "torsoSpineEdited", state.root)
		state.target = delta * input("upper", "torsoUpperInput", "torsoUpperEdited", state.target)
	end

	return state
end

local function r15Basis(direction, bend)
	local x = direction.Unit
	local y = bend - x * bend:Dot(x)
	if y.Magnitude < 1e-6 then
		local v = math.abs(x.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
		y = v - x * v:Dot(x)
	end

	y = y.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

local function restForward(chain, pose)
	const upper = chain.motors[1]
	const entry = chain.entry
	const root = entry.rig and entry.rig:FindFirstChild("HumanoidRootPart")
	const body = Parenting.realPart0(upper)
	local forward = -Vector3.zAxis
	if root and root:IsA("BasePart") and typeof(body) == "Instance" and body:IsA("BasePart") then
		const parent = entry.map[body]
		const world = parent and TimelineState.DefaultWorldPose[parent] or body.CFrame
		forward = world:VectorToObjectSpace(root.CFrame.LookVector)
	end

	return pose:VectorToObjectSpace(forward)
end

local function armHinge(chain, pose, link, vector)
	const current = link.RightVector
	const a, b = link.Position, link:VectorToWorldSpace(vector)
	if b.Magnitude < 1e-6 then
		return current
	end

	const forward = restForward(chain, pose)
	local natural = b.Unit:Cross(forward)
	if natural.Magnitude < 0.3 or math.abs(current:Dot(natural.Unit)) >= 0.7 then
		return current
	end

	natural = natural.Unit
	const sum = a + b
	const direction = if sum.Magnitude > 1e-6 then sum.Unit else b.Unit
	local reference = -forward - direction * (-forward):Dot(direction)
	if reference.Magnitude < 1e-3 then
		reference = natural
	end

	return natural, link:VectorToObjectSpace(natural), reference.Unit
end

r15Rest = function(chain)
	local upper, lower, tip = chain.motors[1], chain.motors[2], chain.owner
	local defaults = TimelineState.DefaultPose

	local function rest(motor, index)
		local saved = chain.custom and chain.owner:GetAttribute("EclipseAutoIKRest" .. index)
		return typeof(saved) == "CFrame" and saved or defaults[motor] or motor.C0
	end

	local upperPose, lowerPose, tipPose =
		rest(upper, 1), rest(lower, 2), chain.tip and CFrame.new(chain.tip) or rest(tip, 3)
	local upperC1, lowerC1 = upper.C1, lower.C1
	local cached = chain._r15Rest
	if
		cached
		and cached.upperPose == upperPose
		and cached.lowerPose == lowerPose
		and cached.tipPose == tipPose
		and cached.upperC1 == upperC1
		and cached.lowerC1 == lowerC1
		and cached.limb == chain.limb
	then
		return cached.value
	end

	local u = upperPose
	local l = u * upper.C1:Inverse() * lowerPose
	local t = l * lower.C1:Inverse() * tipPose
	local uv = (upper.C1:Inverse() * lowerPose).Position
	local lv = (lower.C1:Inverse() * tipPose).Position
	local direction = t.Position - u.Position
	if direction.Magnitude < 1e-6 then
		direction = l.Position - u.Position
	end

	local axis = direction.Magnitude > 1e-6 and direction.Unit or Vector3.yAxis
	local bend = l.Position - u.Position
	bend -= axis * bend:Dot(axis)
	if bend.Magnitude < 0.001 then
		bend = Vector3.new(0, 0, chain.limb == "Leg" and -1 or 1)
	end

	local value = {
		armLink = upper.C1:Inverse() * lowerPose,
		armVector = lv,
		a = uv.Magnitude,
		b = lv.Magnitude,
		upper = r15Basis(uv, u:VectorToObjectSpace(bend)),
		lower = r15Basis(lv, l:VectorToObjectSpace(bend)),
		bend = bend,
	}
	if chain.limb == "Arm" and not chain.custom then
		value.armHinge, value.armHingeLocal, value.armReference =
			armHinge(chain, u, value.armLink, lv)
	end

	chain._r15Rest = {
		upperPose = upperPose,
		lowerPose = lowerPose,
		tipPose = tipPose,
		upperC1 = upperC1,
		lowerC1 = lowerC1,
		limb = chain.limb,
		value = value,
	}
	return value
end

r15ArmAngle = function(rest, distance)
	local link, vector = rest.armLink, rest.armVector
	local a, b = link.Position, link:VectorToWorldSpace(vector)
	local hinge = rest.armHinge or link.RightVector
	local parallel = hinge * b:Dot(hinge)
	local perpendicular = b - parallel
	local cosine, sine = a:Dot(perpendicular), a:Dot(hinge:Cross(perpendicular))
	local radius = math.sqrt(cosine * cosine + sine * sine)
	local center = a:Dot(a) + b:Dot(b) + 2 * a:Dot(parallel)
	local minimum = math.sqrt(math.max(0, center - 2 * radius))
	local maximum = math.sqrt(math.max(0, center + 2 * radius))
	local length = math.clamp(distance, math.max(minimum, 1e-6), math.max(maximum, 1e-6))
	local angle = 0
	if radius > 1e-8 then
		angle = math.atan2(sine, cosine) + math.acos(math.clamp((length * length - center) / (2 * radius), -1, 1))
	end
	return angle, length
end

r15ArmRotation = function(rest, angle)
	local link, vector = rest.armLink, rest.armVector
	local hinge = rest.armHinge or link.RightVector
	local reference = rest.armReference or hinge * (link.Position:Dot(hinge) >= 0 and 1 or -1)
	if rest.armAngle == angle then
		return rest.armRotation, reference
	end

	local direction = link.Position + link:VectorToWorldSpace(vector)
	local rotation = CFrame.identity
	for i = 1, 16 do
		local tip = link.Position
			+ link:VectorToWorldSpace(
				(
					if rest.armHingeLocal
						then CFrame.fromAxisAngle(rest.armHingeLocal, angle * i / 16)
						else CFrame.Angles(angle * i / 16, 0, 0)
				):VectorToWorldSpace(vector)
			)
		rotation = Solver.rotationBetween(rotation:VectorToWorldSpace(tip), direction) * rotation
	end
	rest.armAngle, rest.armRotation = angle, rotation
	return rotation, reference
end

function LimbIK.r15RollTarget(chain, target, roll, sampleMap)
	if not roll or chain.limb ~= "Leg" then
		return target
	end

	local control = LimbIK.controlMotor(chain, "roll")
	if not control then
		return target
	end

	local map = sampleMap or chain.entry.map
	local parent = map[Parenting.realPart0(control)]
	local anchor = parent and Parenting.worldOf(parent, map) or control.Part0.CFrame
	local rest = TimelineState.DefaultPose[control] or control.Bone.CFrame
	local delta = (anchor * rest):ToObjectSpace(roll)
	local pitch = select(1, delta:ToOrientation())
	local pivot = footRollOffset(chain, false, pitch)
	return target * CFrame.new(pivot) * delta.Rotation * CFrame.new(-pivot)
end

local function chainRest(chain)
	const motors = chain.motors
	const count = #motors
	const poses, c1s = table.create(count), table.create(count)
	for i, motor in motors do
		const saved = chain.custom and chain.owner:GetAttribute("EclipseAutoIKRest" .. i)
		poses[i] = if typeof(saved) == "CFrame" then saved else TimelineState.DefaultPose[motor] or motor.C0
		c1s[i] = motor.C1
	end

	const cached = chain._chainRest
	if cached and cached.limb == chain.limb and #cached.poses == count then
		local same = true
		for i = 1, count do
			if cached.poses[i] ~= poses[i] or cached.c1s[i] ~= c1s[i] then
				same = false
				break
			end
		end

		if same then
			return cached.value
		end
	end

	const joints = table.create(count)
	joints[1] = poses[1]
	for i = 2, count do
		joints[i] = joints[i - 1] * c1s[i - 1]:Inverse() * poses[i]
	end

	const origin = joints[1].Position
	local axis = joints[count].Position - origin
	if axis.Magnitude < 1e-6 then
		axis = joints[2].Position - origin
	end

	axis = if axis.Magnitude > 1e-6 then axis.Unit else -Vector3.yAxis
	local bend, distance = Vector3.zero, -1
	for i = 2, count - 1 do
		local offset = joints[i].Position - origin
		offset -= axis * offset:Dot(axis)
		if offset.Magnitude > distance then
			bend, distance = offset, offset.Magnitude
		end
	end

	if bend.Magnitude < 1e-3 then
		bend = Vector3.new(0, 0, chain.limb == "Leg" and -1 or 1)
		bend -= axis * bend:Dot(axis)
		if bend.Magnitude < 1e-3 then
			bend = r15Basis(axis, Vector3.xAxis).UpVector
		end
	end

	bend = bend.Unit
	const normal = axis:Cross(bend).Unit
	const lengths, shape, offsets = table.create(count - 1), table.create(count), table.create(count - 1)
	local total, straight = 0, true
	for i = 1, count do
		const point = joints[i].Position - origin
		shape[i] = Vector2.new(point:Dot(axis), point:Dot(bend))
		if math.abs(shape[i].Y) > 1e-3 then
			straight = false
		end
	end

	for i = 1, count - 1 do
		local direction = joints[i + 1].Position - joints[i].Position
		lengths[i] = direction.Magnitude
		total += lengths[i]
		if direction.Magnitude < 1e-6 then
			direction = axis
		end

		offsets[i] = r15Basis(direction, normal:Cross(direction)):Inverse() * joints[i].Rotation
	end

	if straight and total > 1e-6 then
		local along = 0
		for i = 2, count - 1 do
			along += lengths[i - 1]
			shape[i] = Vector2.new(shape[i].X, total * 0.08 * math.sin(math.pi * along / total))
		end
	end

	const value = { lengths = lengths, shape = shape, offsets = offsets, bend = bend, reach = total }
	chain._chainRest = { poses = poses, c1s = c1s, limb = chain.limb, value = value }
	return value
end

local function settle(points, lengths, count, goal)
	for _ = 1, 48 do
		points[count] = goal
		for i = count - 1, 1, -1 do
			local direction = points[i] - points[i + 1]
			if direction.Magnitude < 1e-9 then
				direction = Vector2.new(-1, 0)
			end

			points[i] = points[i + 1] + direction.Unit * lengths[i]
		end

		points[1] = Vector2.zero
		for i = 2, count do
			local direction = points[i] - points[i - 1]
			if direction.Magnitude < 1e-9 then
				direction = Vector2.new(1, 0)
			end

			points[i] = points[i - 1] + direction.Unit * lengths[i - 1]
		end

		if (points[count] - goal).Magnitude < 1e-5 then
			break
		end
	end
end

local function solveChain(chain, target, pole, state, map)
	const motors = chain.motors
	const count = #motors
	const rest = chain.chainRest or chainRest(chain)
	const origin = (state and state.root or LimbIK.rootControl(chain)).Position
	const delta = target.Position - origin
	const axis = if delta.Magnitude > 1e-7 then delta.Unit else -Vector3.yAxis
	local plane = pole.Position - origin
	plane -= axis * plane:Dot(axis)
	if plane.Magnitude < 1e-6 then
		const fallback = LimbIK.anchor(chain):VectorToWorldSpace(rest.bend)
		plane = fallback - axis * fallback:Dot(axis)
	end

	if plane.Magnitude < 1e-6 then
		plane = r15Basis(axis, Vector3.xAxis).UpVector
	end

	plane = plane.Unit
	const normal = axis:Cross(plane).Unit
	const lengths = rest.lengths
	const distance = math.min(delta.Magnitude, rest.reach)
	const points = table.clone(rest.shape)
	if distance >= rest.reach - 1e-6 then
		local along = 0
		points[1] = Vector2.zero
		for i = 2, count do
			along += lengths[i - 1]
			points[i] = Vector2.new(along, 0)
		end
	else
		settle(points, lengths, count, Vector2.new(distance, 0))
	end

	const world = table.create(count)
	for i = 1, count do
		world[i] = origin + axis * points[i].X + plane * points[i].Y
	end

	for i = 1, count - 1 do
		local direction = world[i + 1] - world[i]
		if direction.Magnitude < 1e-6 then
			direction = axis
		end

		const frame = CFrame.new(world[i]) * r15Basis(direction, normal:Cross(direction)) * rest.offsets[i]
		MotorMath.solveMotorC0ForWorldCFrame(motors[i], frame * motors[i].C1:Inverse(), map)
	end

	MotorMath.solveMotorC0ForWorldCFrame(
		chain.owner,
		CFrame.new(world[count]) * target.Rotation * chain.owner.C1:Inverse(),
		map
	)
end

local function solveR15(chain, target, pole, state, map)
	if #chain.motors > 3 then
		solveChain(chain, target, pole, state, map)
		return
	end

	local upper, lower, tip = chain.motors[1], chain.motors[2], chain.owner
	local rest = chain.r15Rest or r15Rest(chain)
	local origin = state and state.root or LimbIK.rootControl(chain)
	local goal = target
	local fallback = LimbIK.anchor(chain):VectorToWorldSpace(rest.bend)
	local delta = goal.Position - origin.Position
	local axis = delta.Magnitude > 1e-7 and delta.Unit or Vector3.new(0, -1, 0)
	local reach = rest.a + rest.b
	local distance = math.clamp(delta.Magnitude, math.max(math.abs(rest.a - rest.b), 1e-6), reach)
	if reach - distance < math.max(1e-5, reach * 1e-5) then
		distance = reach
	end

	local plane = pole.Position - origin.Position
	plane -= axis * plane:Dot(axis)
	if plane.Magnitude < 1e-6 then
		plane = fallback - axis * fallback:Dot(axis)
	end

	if plane.Magnitude < 1e-6 then
		plane = r15Basis(axis, Vector3.xAxis).UpVector
	end

	plane = plane.Unit
	if chain.limb == "Arm" and not chain.custom then
		local link, vector = rest.armLink, rest.armVector
		local a, b = link.Position, link:VectorToWorldSpace(vector)
		local angle, length = r15ArmAngle(rest, delta.Magnitude)
		local elbow = if rest.armHingeLocal
			then CFrame.fromAxisAngle(rest.armHingeLocal, angle)
			else CFrame.Angles(angle, 0, 0)
		local rotation, reference = r15ArmRotation(rest, angle)
		local upperFrame = CFrame.new(origin.Position)
			* r15Basis(axis, plane)
			* r15Basis(a + b, reference):Inverse()
			* rotation
		local lowerFrame = upperFrame * link * elbow
		MotorMath.solveMotorC0ForWorldCFrame(upper, upperFrame * upper.C1:Inverse(), map)
		MotorMath.solveMotorC0ForWorldCFrame(lower, lowerFrame * lower.C1:Inverse(), map)
		MotorMath.solveMotorC0ForWorldCFrame(tip, CFrame.new(origin.Position + axis * length) * goal.Rotation * tip.C1:Inverse(), map)
		return
	end

	local along = (rest.a * rest.a - rest.b * rest.b + distance * distance) / (2 * distance)
	local height = math.sqrt(math.max(0, rest.a * rest.a - along * along))
	local knee = origin.Position + axis * along + plane * height
	local endpoint = origin.Position + axis * distance

	local normal = axis:Cross(plane).Unit

	local function segmentFrame(direction)
		return r15Basis(direction, normal:Cross(direction))
	end

	local upperFrame = CFrame.new(origin.Position)
		* segmentFrame(knee - origin.Position)
		* rest.upper:Inverse()
	local lowerFrame = CFrame.new(knee) * segmentFrame(endpoint - knee) * rest.lower:Inverse()
	MotorMath.solveMotorC0ForWorldCFrame(upper, upperFrame * upper.C1:Inverse(), map)
	MotorMath.solveMotorC0ForWorldCFrame(lower, lowerFrame * lower.C1:Inverse(), map)
	if not chain.tip then
		MotorMath.solveMotorC0ForWorldCFrame(
			tip,
			(CFrame.new(endpoint) * goal.Rotation) * tip.C1:Inverse(),
			map
		)
	end
end

local function solveUnblended(chain, target, pole, state, evaluateC0)
	local entry, map = chain.entry, chain.entry.map
	local members, locked = {}, { MotorByPart = map }
	for _, motor in chain.motors do
		members[motor] = true
	end

	for _, motor in entry.motors do
		if not members[motor] and motor:GetAttribute("TrackParent") == false then
			table.insert(locked, { Motor = motor, WorldCF = Parenting.worldOf(motor, map) })
		end
	end

	for _, motor in chain.motors do
		if typeof(motor) == "Instance" then
			motor:SetAttribute("TrackParent", true)
		end
	end

	local upper = chain.motors[1]
	if chain.kind == "Torso" then
		local base = LimbIK.anchor(chain) * state.baseC0 * upper.C1:Inverse()
		local desired = TorsoSolver.solve(base, upper.Part1.Size.Y, state.root, target)
		MotorMath.solveMotorC0ForWorldCFrame(upper, desired, map)
		MotorMath.restoreTrackParentLockedDescendants(locked)
		return true
	end

	if evaluateC0 then
		for _, motor in chain.motors do
			if motor ~= chain.owner then
				motor.C0 = evaluateC0(motor)
			end
		end
	end

	if state and state.baseC0 then
		chain.owner.C0 = state.baseC0
	end

	if state and state.root and chain.kind == "R6" then
		local world = state.root * CFrame.new(0, -upper.Part1.Size.Y * 0.5, 0)
		MotorMath.solveMotorC0ForWorldCFrame(upper, world, map)
	end

	if chain.kind == "R6" and LimbIK.feetPlanted(chain) then
		local bend = entry.rig:GetAttribute("EclipseR6BendPercent")
			or Preferences.get("R6BendPercent")
		local rootFrame = state and state.root or LimbIK.rootControl(chain)
		local desired = Solver.plantedR6(rootFrame, target, pole.Position, upper.Part1.Size, bend)
		MotorMath.solveMotorC0ForWorldCFrame(upper, desired, map)
		MotorMath.restoreTrackParentLockedDescendants(locked)
		return true
	end

	if chain.kind == "R15" then
		target = LimbIK.r15RollTarget(chain, target, state and state.roll)
		solveR15(chain, target, pole, state, map)
		MotorMath.restoreTrackParentLockedDescendants(locked)
		return true
	end

	local root, middle, tip, _, fallback = LimbIK.geometry(chain)
	local knee, endpoint = Solver.twoLink(
		root,
		middle,
		tip,
		target.Position,
		pole.Position,
		fallback,
		Preferences.get("SoftIKPercent")
	)
	if not knee then
		MotorMath.restoreTrackParentLockedDescendants(locked)
		return false
	end

	local planted = LimbIK.feetPlanted(chain)
	if planted then
		endpoint = target.Position
	end

	if chain.kind == "R6" then
		local referenceDirection = target:VectorToWorldSpace(Vector3.new(0, -1, 0))
		local rotation = Solver.rotationBetween(referenceDirection, endpoint - knee)
			* target.Rotation
		local desired = CFrame.new(endpoint) * rotation * CFrame.new(0, upper.Part1.Size.Y * 0.5, 0)
		MotorMath.solveMotorC0ForWorldCFrame(upper, desired, map)
	else
		local rest = chain.rest or restFor(chain)
		local lower = chain.motors[2]
		local upperFrame, lowerFrame =
			solveSegments(chain, rest, root, middle, target.Position, pole.Position, fallback)
		if upperFrame then
			MotorMath.solveMotorC0ForWorldCFrame(
				upper,
				CFrame.new(root) * upperFrame * rest.upper * upper.C1:Inverse(),
				map
			)
			local kneeNow = jointWorld(lower, map).Position
			MotorMath.solveMotorC0ForWorldCFrame(
				lower,
				CFrame.new(kneeNow) * lowerFrame * rest.lower * lower.C1:Inverse(),
				map
			)
		end

		local lowerWorld = Parenting.worldOf(lower, map)
		chain.owner.C0 = CFrame.new(chain.owner.C0.Position)
			* (lowerWorld.Rotation:Inverse() * target.Rotation)
	end

	MotorMath.restoreTrackParentLockedDescendants(locked)
	return true
end

function LimbIK.solve(chain, target, pole, state, evaluateC0)
	local offset = chain.poleOffset
	if offset == nil and chain.kind ~= "Torso" then
		local control = LimbIK.controlMotor(chain, "pole")
		offset = control and control:GetAttribute("EclipsePoleDisplayOffset")
	end
	if pole and typeof(offset) == "Vector3" then
		pole = pole * CFrame.new(offset)
	end
	local weight = state and state.blend
	if weight == nil or weight >= 1 then
		return solveUnblended(chain, target, pole, state, evaluateC0)
	end

	if weight <= 0 then
		return true
	end

	local before, members, locked = {}, {}, { MotorByPart = chain.entry.map }
	state.blendInput = state.blendInput or {}
	state.blendOutput = state.blendOutput or {}
	for _, motor in chain.motors do
		if state.blendOutput[motor] ~= motor.C0 then
			state.blendInput[motor] = motor.C0
		end

		before[motor] = state.blendInput[motor] or motor.C0
		members[motor] = true
	end

	for _, motor in chain.entry.motors do
		if not members[motor] and motor:GetAttribute("TrackParent") == false then
			table.insert(
				locked,
				{ Motor = motor, WorldCF = Parenting.worldOf(motor, chain.entry.map) }
			)
		end
	end

	local result = solveUnblended(chain, target, pole, state, evaluateC0)
	for motor, pose in before do
		motor.C0 = pose:Lerp(motor.C0, weight)
		state.blendOutput[motor] = motor.C0
	end

	MotorMath.restoreTrackParentLockedDescendants(locked)
	return result
end

function LimbIK.apply(rig, time, resample, evaluateC0, worldAt)
	local entry = LimbIK.getRig(rig)
	if not entry then
		return
	end

	entry.torsoBaseWorld = nil
	HeadStabilizer.apply(rig, time, resample, entry.motors, entry.map)
	if
		entry.torso
		and (LimbIK.isEnabled(entry.torso.owner, time) or LimbIK.transition(entry.torso.owner, time))
		and not entry.torso.owner:GetAttribute("EclipseDisabled")
	then
		local torsoState = LimbIK.state(entry.torso, time, resample, worldAt)
		entry.torsoBaseWorld = LimbIK.anchor(entry.torso)
			* torsoState.baseC0
			* entry.torso.owner.C1:Inverse()
	end

	for _, chain in entry.chains do
		local state = LimbIK.state(chain, time, resample, worldAt)
		if state and not chain.owner:GetAttribute("EclipseDisabled") then
			LimbIK.solve(chain, state.target, state.pole, state, evaluateC0 and function(motor)
				return evaluateC0(motor, time)
			end)
		end
	end

	HeadStabilizer.apply(rig, time, resample, entry.motors, entry.map)
end

function LimbIK.setControl(chain, kind, value)
	local before = LimbIK.state(chain)
	local movedPole = before
		and chain.kind == "R15"
		and kind == "target"
		and before.poleFollowsTarget
		and (
			value == before.target and before.pole
			or value:Orthonormalize()
				* before.target:Orthonormalize():ToObjectSpace(before.pole):Orthonormalize()
		)
	if movedPole then
		local poleControl = LimbIK.controlMotor(chain, "pole")
		if poleControl and poleControl:GetAttribute("EclipseDisabled") then
			movedPole = nil
		end
	end

	local control = LimbIK.controlMotor(chain, kind)
	if control then
		if not writeControlWorld(chain, kind, value) then
			return
		end

		if chain.kind == "R15" then
			local state = before
			if state then
				state[kind] = value
				if movedPole then
					writeControlWorld(chain, "pole", movedPole)
					state.pole = movedPole
				end

				state.dirty = true
			end
		end

		LimbIK.apply(chain.entry.rig, TimelineState.CurrentTime, false)
		return
	end

	local state = LimbIK.state(chain)
	if not state then
		return
	end

	state[kind] = value
	if chain.kind == "R6" and chain.limb == "Leg" then
		local pole = LimbIK.controlMotor(chain, "pole")
		if pole then
			state.pole = state.target * R6Controls.value(pole, TimelineState.DefaultPose)
		end
	end

	state.dirty = true
	LimbIK.solve(chain, state.target, state.pole, state)
end

function LimbIK.resetSelected(rig, list, component, scaleFactor)
	local entry = LimbIK.getRig(rig)
	if not entry then
		return
	end

	local selected, present, controls = {}, {}, {}
	for _, info in list do
		present[info.motor] = info
		local motor = info.motor
		if typeof(motor) == "table" and motor.IsEclipseR6Control then
			motor = motor.Owner
		end

		local chain = entry.members[motor]
		if chain and LimbIK.isEnabled(chain.owner, TimelineState.CurrentTime) then
			if typeof(info.motor) == "table" and info.motor.IsEclipseR6Control then
				table.insert(controls, { chain = chain, info = info })
			elseif chain.kind == "R6" and info.ikControl == "target" then
				table.insert(controls, { chain = chain, info = info, target = true })
			else
				selected[chain] = true
			end
		end
	end

	for _, selection in controls do
		local chain, info = selection.chain, selection.info
		info.ikReset = true
		if selection.target then
			local state = LimbIK.state(chain)
			local parent = entry.map[Parenting.realPart0(chain.owner)]
			local anchor = parent and Parenting.worldOf(parent, entry.map)
				or chain.owner.Part0.CFrame
			local current = anchor:ToObjectSpace(state.target)
			local rest = info.defaultC0.Rotation + info.defaultC0.Position * scaleFactor(info.motor)
			rest = rest
				* chain.owner.C1:Inverse()
				* CFrame.new(0, -chain.owner.Part1.Size.Y * 0.5, 0)
			local value = component == "Position" and current.Rotation + rest.Position
				or rest.Rotation + current.Position
			state.target = anchor * value
			state.dirty = true
		else
			local motor = info.motor
			motor.C0 = component == "Position"
					and motor.C0.Rotation + info.defaultC0.Position * scaleFactor(motor)
				or info.defaultC0.Rotation + motor.C0.Position
		end
	end

	if #controls > 0 then
		LimbIK.apply(rig, TimelineState.CurrentTime, false)
	end

	local function include(motor)
		local info = present[motor]
		if not info then
			info = {
				motor = motor,
				part = motor.Part1,
				startC0 = motor.C0,
				defaultC0 = TimelineState.DefaultPose[motor] or motor.C0,
				authoredReset = true,
			}
			present[motor] = info
			table.insert(list, info)
		end

		info.ikReset = true
	end

	for _, chain in entry.chains do
		if selected[chain] then
			for _, motor in chain.motors do
				include(motor)
			end

			for _, motor in R6Controls.forOwner(chain.owner) do
				include(motor)
			end
		end
	end

	for _, chain in entry.chains do
		if selected[chain] then
			local state = LimbIK.state(chain)
			local locked = MotorMath.collectTrackParentLockedDescendants(rig, chain.motors[1])
			for _, motor in chain.motors do
				local rest = TimelineState.DefaultPose[motor]
				if rest then
					if component == "Position" then
						motor.C0 = motor.C0.Rotation + rest.Position * scaleFactor(motor)
					else
						motor.C0 = rest.Rotation + motor.C0.Position
					end
				end
			end

			local target, pole, baseC0, baseWorld, root = LimbIK.capturePose(chain)
			state.target, state.pole, state.baseC0, state.baseWorld, state.root =
				target, pole, baseC0, baseWorld, root
			state.anchor = LimbIK.anchor(chain)
			state.dirty = true
			if chain.kind == "R15" then
				for kind, value in { root = root, target = target, pole = pole } do
					writeControlWorld(chain, kind, value)
				end

				local roll = LimbIK.controlMotor(chain, "roll")
				if roll then
					roll.C0 = TimelineState.DefaultPose[roll] or roll.Bone.CFrame
				end

				state.roll = LimbIK.controlWorld(chain, "roll", nil)
			elseif chain.kind == "R6" then
				writeControlWorld(chain, "root", root)
				local control = chain.limb == "Leg" and LimbIK.controlMotor(chain, "pole")
				if control then
					control.C0 = TimelineState.DefaultPose[control] or control.Bone.CFrame
					pole = target * control.C0
					state.pole = pole
				end
			elseif chain.kind == "Torso" then
				writeControlWorld(chain, "spine", root)
				writeControlWorld(chain, "upper", target)
			end

			LimbIK.solve(chain, target, pole, state)
			if chain.kind == "R6" and LimbIK.feetPlanted(chain) then
				local actual = Parenting.worldOf(chain.owner, entry.map)
				local delta = baseWorld * actual:Inverse()
				target, pole, root = delta * target, delta * pole, delta * root
				state.target, state.pole, state.root = target, pole, root
				writeControlWorld(chain, "root", root)
				LimbIK.solve(chain, target, pole, state)
			end

			MotorMath.restoreTrackParentLockedDescendants(locked)
		end
	end
end

function LimbIK.isDirty(motor)
	return (live[motor] ~= nil and live[motor].dirty == true) or HeadStabilizer.isDirty(motor)
end

function LimbIK.markRecorded(motor)
	if live[motor] then
		live[motor].dirty = false
	end

	HeadStabilizer.markRecorded(motor)
end

function LimbIK.captureKey(motor, key)
	local chain = memberChains[motor]
	if chain and LimbIK.isEnabled(chain.owner, key.Time) then
		key.IKRestoreParented = LimbIK.restoreParented(chain, motor, key.Time)
		key.Parented, key.WorldCFrame = true, nil
	end

	local state = live[motor]
	if not state or not LimbIK.isEnabled(motor, key.Time) then
		return
	end

	if
		state.time ~= key.Time
		and (
			state.time ~= TimelineState.CurrentTime
			or math.floor(state.time * TimelineState.FPS + 0.5)
				~= math.floor(key.Time * TimelineState.FPS + 0.5)
		)
	then
		return
	end

	key.IK, key.IKTarget, key.IKPole = true, state.target, state.pole
	key.IKRoot = state.root
	key.IKPoleFollowsTarget = state.poleFollowsTarget == true
	key.IKAnchor = LimbIK.anchor(state.chain)
	key.IKRigWorld = LimbIK.rigFrame(state.chain)
	key.IKBaseC0, key.IKBaseWorld = state.baseC0, state.baseWorld
	if state.baseC0 and state.chain.kind ~= "Torso" then
		local map = state.chain.entry.map
		local parent = map[Parenting.realPart0(motor)]
		local world = parent and Parenting.worldOf(parent, map) or motor.Part0.CFrame
		key.IKBaseWorld = world * state.baseC0 * motor.C1:Inverse()
	end
end

function LimbIK.appendManipulation(rig, list)
	local entry = LimbIK.getRig(rig)
	if not entry then
		return
	end

	local present, controlSelected = {}, false
	for _, info in list do
		present[info.motor] = true
		controlSelected = controlSelected
			or (typeof(info.motor) == "table" and info.motor.IsEclipseR6Control == true)
	end

	for _, chain in entry.chains do
		if LimbIK.state(chain) then
			if
				chain.kind == "Torso"
				or chain.kind == "R15"
				or (chain.kind == "R6" and chain.limb == "Leg")
			then
				for _, control in R6Controls.forOwner(chain.owner) do
					if not present[control] then
						present[control] = true
						table.insert(
							list,
							{ motor = control, part = control.Part1, startC0 = control.C0 }
						)
					end
				end
			end

			for _, motor in chain.motors do
				if not present[motor] then
					present[motor] = true
					table.insert(list, {
						motor = motor,
						part = motor.Part1,
						startC0 = motor.C0,
						ikFollower = true,
						skipIKRecord = controlSelected and chain.kind ~= "R15",
					})
				end
			end
		end
	end
end

function LimbIK.snapshot(rig)
	if not rig then
		return nil
	end

	local entry = LimbIK.getRig(rig)
	if not entry then
		return nil
	end

	for _, motor in entry.motors do
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			return nil
		end
	end

	local snapshot = {
		states = {},
		motors = {},
		bones = {},
		anchors = {},
		torsoBaseWorld = entry.torsoBaseWorld,
	}
	for _, chain in entry.chains do
		if live[chain.owner] then
			local state = table.clone(live[chain.owner])
			state.chain = nil
			snapshot.states[chain.owner] = state
		end
	end

	for _, motor in Parenting.collectMotors(rig) do
		snapshot.motors[motor] = motor.C0
	end

	for _, item in RigTraversal.rigDescendants(rig) do
		if item:IsA("Bone") and not item:GetAttribute("EclipseArmatureSkinningHelper") then
			snapshot.bones[item] = item.Transform
		elseif
			item:IsA("BasePart") and typeof(item:GetAttribute("EclipseIKEffector")) == "string"
		then
			local attributes = {}
			for _, name in anchorPoseAttributes do
				attributes[name] = item:GetAttribute(name)
			end

			snapshot.anchors[item] = { cframe = item.CFrame, attributes = attributes }
		end
	end

	return snapshot
end

function LimbIK.restore(rig, snapshot)
	local entry = rig and LimbIK.getRig(rig)
	if not entry or not snapshot then
		return false
	end

	for _, chain in entry.chains do
		local state = snapshot.states[chain.owner]
		live[chain.owner] = state and table.clone(state) or nil
		if live[chain.owner] then
			live[chain.owner].chain = chain
		end
	end

	entry.torsoBaseWorld = snapshot.torsoBaseWorld
	for motor, c0 in snapshot.motors do
		if motor.Parent then
			motor.C0 = c0
		end
	end

	for bone, transform in snapshot.bones do
		if bone.Parent then
			bone.Transform = transform
		end
	end

	for anchor, data in snapshot.anchors do
		if anchor.Parent then
			anchor.CFrame = data.cframe
			for _, name in anchorPoseAttributes do
				anchor:SetAttribute(name, data.attributes[name])
			end
		end
	end

	return true
end

function LimbIK.evaluate(rig, time, evaluateC0, requestedMotor)
	local source = LimbIK.getRig(rig)
	if not source then
		return nil
	end

	local enabled = false
	for _, chain in source.chains do
		if LimbIK.isEnabled(chain.owner, time) or LimbIK.transition(chain.owner, time) then
			enabled = true
			break
		end
	end

	if not enabled then
		for _, motor in source.motors do
			if HeadStabilizer.isEnabled(motor, time) then
				enabled = true
				break
			end
		end
	end

	if not enabled then
		return nil
	end

	local sampledMotors = source.motors
	local sampledChains = source.chains
	if requestedMotor then
		local needed, included = {}, {}

		local function include(motor)
			while motor and not needed[motor] do
				needed[motor] = true
				motor = source.map[Parenting.realPart0(motor)]
			end
		end

		include(requestedMotor)
		local changed = true
		while changed do
			changed = false
			for _, chain in source.chains do
				if included[chain] then
					continue
				end

				local relevant = false
				for _, motor in chain.motors do
					if needed[motor] then
						relevant = true
					end
				end

				for _, kind in { "root", "spine", "upper", "target", "pole", "roll" } do
					local control = LimbIK.controlMotor(chain, kind)
					if control and needed[control] then
						relevant = true
					end
				end

				if relevant then
					included[chain] = true
					changed = true
					for _, motor in chain.motors do
						include(motor)
					end

					for _, kind in { "root", "spine", "upper", "target", "pole", "roll" } do
						include(LimbIK.controlMotor(chain, kind))
					end
				end
			end
		end

		sampledMotors, sampledChains = {}, {}
		for _, motor in source.motors do
			if needed[motor] then
				table.insert(sampledMotors, motor)
			end
		end

		for _, chain in source.chains do
			if included[chain] then
				table.insert(sampledChains, chain)
			end
		end
	end

	local evaluator = Parenting.newEvaluator(
		sampledMotors,
		TimelineState.Keyframes,
		TimelineState.DefaultPose,
		TimelineState.DefaultWorldPose,
		TimelineState.ParentingDefaults,

		function(motor, sampleTime)
			return evaluateC0(motor, sampleTime), true
		end
	)
	local entry = { rig = rig, motors = {}, map = {} }
	local proxies, originals, controlFrames = {}, {}, {}
	for _, motor in sampledMotors do
		local proxy = {
			C0 = evaluator.localAt(motor, time),
			C1 = motor.C1,
			Part0 = motor.Part0,
			RealPart0 = Parenting.realPart0(motor),
			Part1 = motor.Part1,
			Parent = motor.Parent,
			GetAttribute = function(_, name)
				if name == "TrackParent" then
					return evaluator.isParentedAt(motor, time)
				end

				return motor:GetAttribute(name)
			end,
		}
		local anchor = motor.Part0
		if typeof(anchor) == "table" and anchor.AnchorRoot then
			local rootMotor = source.map[anchor.AnchorRoot]
			local world = rootMotor and evaluator.worldAt(rootMotor, time)
				or anchor.AnchorRoot.CFrame
			proxy.Part0 = { CFrame = world * anchor.AnchorOffset }
			proxy.RealPart0 = nil
		end

		proxies[motor] = proxy
		originals[proxy] = motor
		entry.map[motor.Part1] = proxy
		table.insert(entry.motors, proxy)
	end

	for _, proxy in HeadStabilizer.ordered(entry.motors, entry.map) do
		local motor = originals[proxy]
		if not LimbIK.isDriven(motor, time) then
			HeadStabilizer.solve(
				proxy,
				HeadStabilizer.rotationAt(motor, time, proxy.C0),
				entry.motors,
				entry.map
			)
		end
	end

	if
		source.torso
		and proxies[source.torso.owner]
		and (LimbIK.isEnabled(source.torso.owner, time) or LimbIK.transition(
			source.torso.owner,
			time
		))
		and not source.torso.owner:GetAttribute("EclipseDisabled")
	then
		entry.torso = { owner = proxies[source.torso.owner] }
		local _, sampleTime = LimbIK.transition(source.torso.owner, time)
		local _, _, baseC0 = sampleTargets(source.torso, sampleTime or time, evaluator.worldAt)
		entry.torsoBaseWorld = source.torso.owner.Part0.CFrame
			* baseC0
			* source.torso.owner.C1:Inverse()
	end

	for _, chain in sampledChains do
		local blend, sampleTime = LimbIK.transition(chain.owner, time)
		if
			(not LimbIK.isEnabled(chain.owner, time) and not blend)
			or chain.owner:GetAttribute("EclipseDisabled")
		then
			continue
		end

		local sampleChain = {
			owner = chain.owner,
			motors = {},
			entry = entry,
			kind = chain.kind,
			custom = chain.custom,
			tip = chain.tip,
			limb = chain.limb,
		}
		for _, motor in chain.motors do
			table.insert(sampleChain.motors, proxies[motor])
		end

		local target, pole, baseC0, baseWorld, _, rootControl, follow = sampleTargets(
			sampleChain,
			sampleTime or time,

			function(proxy, sampleTime)
				return evaluator.worldAt(originals[proxy], sampleTime)
			end
		)
		if not target then
			continue
		end

		local function controlAt(kind, fallback)
			local control = LimbIK.controlMotor(chain, kind)
			local proxy = control and proxies[control]
			if
				not proxy
				or (
					chain.kind == "R15"
					and not Parenting.bounds(TimelineState.Keyframes[control], time)
				)
			then
				return fallback
			end

			local parent = entry.map[proxy.RealPart0]
			local anchor = parent and Parenting.worldOf(parent, entry.map) or proxy.Part0.CFrame
			return anchor * proxy.C0
		end

		local roll
		if chain.kind == "R15" then
			local relative = target:ToObjectSpace(pole)
			if follow then
				local referenceTarget, referencePole = sampleTargets(
					sampleChain,
					sampleTime or time,

					function(proxy, t)
						return evaluator.worldAt(originals[proxy], t)
					end,
					nil,
					false
				)
				local helper = controlAt("pole", referencePole)
				relative = referenceTarget:ToObjectSpace(helper)
					* referenceTarget:ToObjectSpace(referencePole):Inverse()
					* relative
			end

			rootControl, target = controlAt("root", rootControl), controlAt("target", target)
			pole = follow and target * relative or controlAt("pole", pole)
			roll = controlAt("roll", nil)
			target = LimbIK.r15RollTarget(chain, target, roll, entry.map)
		elseif chain.kind == "R6" then
			rootControl = controlAt("root", rootControl)
			local control = chain.limb == "Leg" and LimbIK.controlMotor(chain, "pole")
			local proxy = control and proxies[control]
			if proxy then
				pole = target * proxy.C0
				controlFrames[control] = pole
			end
		elseif chain.kind == "Torso" then
			local anchor = LimbIK.anchor(sampleChain)
			local delta = LimbIK.torsoDelta(chain, baseC0, baseWorld, anchor)
			rootControl, target =
				delta * controlAt("spine", rootControl), delta * controlAt("upper", target)
			local base = anchor * baseC0 * chain.owner.C1:Inverse()
			for _, kind in { "spine", "upper" } do
				local control = LimbIK.controlMotor(chain, kind)
				if control then
					controlFrames[control] = TorsoSolver.controlFrame(
						base,
						chain.owner.Part1.Size.Y,
						rootControl,
						target,
						kind
					)
				end
			end
		end

		local poleControl = LimbIK.controlMotor(chain, "pole")
		LimbIK.solve(
			{
				poleOffset = poleControl and poleControl:GetAttribute("EclipsePoleDisplayOffset") or false,
				owner = proxies[chain.owner],
				motors = sampleChain.motors,
				kind = chain.kind,
				custom = chain.custom,
				tip = chain.tip,
				limb = chain.limb,
				entry = entry,
				rest = chain.kind == "R15" and restFor(chain) or nil,
				r15Rest = chain.kind == "R15" and #chain.motors <= 3 and r15Rest(chain) or nil,
				chainRest = chain.kind == "R15" and #chain.motors > 3 and chainRest(chain) or nil,
			},
			target,
			pole,
			{
				baseC0 = baseC0,
				baseWorld = baseWorld,
				root = rootControl,
				parented = true,
				blend = blend,
			},

			function(proxy)
				return evaluateC0(originals[proxy], time)
			end
		)
	end

	for _, proxy in HeadStabilizer.ordered(entry.motors, entry.map) do
		local motor = originals[proxy]
		if not LimbIK.isDriven(motor, time) then
			HeadStabilizer.solve(
				proxy,
				HeadStabilizer.rotationAt(motor, time, proxy.C0),
				entry.motors,
				entry.map
			)
		end
	end

	local result = {}
	for motor, proxy in proxies do
		result[motor] = controlFrames[motor] or Parenting.worldOf(proxy, entry.map)
	end

	return result
end

function LimbIK.clearLive()
	table.clear(live)
	HeadStabilizer.clearLive()
end

function LimbIK.invalidate(rig)
	local entry = cache[rig]
	if entry then
		for _, chain in entry.chains do
			live[chain.owner] = nil
			for _, motor in chain.motors do
				if memberChains[motor] == chain then
					memberChains[motor] = nil
				end
			end
		end
	end

	cache[rig] = nil
end

return LimbIK
