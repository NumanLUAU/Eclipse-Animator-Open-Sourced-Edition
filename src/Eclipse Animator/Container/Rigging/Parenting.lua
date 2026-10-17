--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")
local BoneMotor = require("BoneMotor")
local Interp = require("Interp")
local PivotSpace = require("PivotSpace")
local GraphCurves = require("GraphCurves")
local HeadStabilizerMode = require("cache")

local ArmatureRuntime = require("ArmatureRuntime")

local MasterControl = require("MasterControl")
local Parenting = {}
local DEFAULT_ATTRIBUTE = "EclipseParentingDefault"

function Parenting.getDefault(motor)
	local value = motor:GetAttribute(DEFAULT_ATTRIBUTE)
	if typeof(value) == "boolean" then
		return value
	end

	return motor:GetAttribute("TrackParent") ~= false
end

function Parenting.captureDefault(motor)
	local value = Parenting.getDefault(motor)
	motor:SetAttribute(DEFAULT_ATTRIBUTE, value)
	return value
end

function Parenting.keyIsParented(motor, keyData, default)
	if keyData and typeof(keyData.Parented) == "boolean" then
		return keyData.Parented
	end

	if typeof(default) == "boolean" then
		return default
	end

	return Parenting.getDefault(motor)
end

function Parenting.bounds(bucket, time)
	local cache = bucket and HeadStabilizerMode.poseCache()
	if cache and cache.persistent then
		local index = cache.bounds[bucket]
		if not index then
			index = {}
			for _, key in pairs(bucket) do
				if not key.GraphOnly and not key.Disabled then
					table.insert(index, key)
				end
			end

			table.sort(index, function(a, b)
				return a.Time < b.Time
			end)
			cache.bounds[bucket] = index
		end

		local low, high, found = 1, #index, 0
		while low <= high do
			local middle = (low + high) // 2
			if index[middle].Time <= time then
				found = middle
				low = middle + 1
			else
				high = middle - 1
			end
		end

		return index[found], index[found + 1]
	end

	local memo = cache and cache.bounds[bucket]
	if memo then
		local hit = memo[time]
		if hit then
			return hit[1], hit[2]
		end
	end

	local previous, following
	for _, key in pairs(bucket or {}) do
		if key.GraphOnly or key.Disabled then
			continue
		end

		if key.Time <= time then
			if not previous or key.Time > previous.Time then
				previous = key
			end
		elseif not following or key.Time < following.Time then
			following = key
		end
	end

	if cache then
		if not memo then
			memo = {}
			cache.bounds[bucket] = memo
		end

		memo[time] = { previous, following }
	end

	return previous, following
end

function Parenting.isParentedAt(motor, bucket, time, default)
	if HeadStabilizerMode.isEnabled(motor, bucket, time) then
		return true
	end

	local previous = Parenting.bounds(bucket, time)
	return Parenting.keyIsParented(motor, previous, default)
end

function Parenting.realPart0(motor)
	if typeof(motor) == "table" then
		return motor.RealPart0
	end

	return motor.Part0
end

function Parenting.collectMotors(rig)
	if rig and require("Properties").propertyOnly(rig) then
		return {}
	end

	require("Target").ensure(rig)
	require("NativeJoints").prepare(rig)
	local passive = RigTraversal.passiveMotors(rig)
	local imported = ArmatureRuntime.isRig(rig)
	local motors = imported and ArmatureRuntime.collectMotors(rig) or {}
	local master = MasterControl.get(rig)
	if master then
		table.insert(motors, master)
	end

	for _, item in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			item:GetAttribute("EclipseArmatureSkinningHelper")
			or item:GetAttribute("EclipseCameraAttachment")
				and not item:GetAttribute("EclipseCameraAttachmentTrack")
		then
			continue
		end

		if imported and ArmatureRuntime.isDriven(item) then
			continue
		end

		if item:IsA("Motor6D") and item.Part0 and item.Part1 and not passive[item] then
			table.insert(motors, item)
		elseif item:IsA("Bone") then
			table.insert(motors, BoneMotor.get(item))
		end
	end

	return motors
end

function Parenting.buildMotorMap(motors)
	local map = {}
	for _, motor in ipairs(motors) do
		map[motor.Part1] = motor
	end

	return map
end

function Parenting.worldOf(motor, motorByPart, visiting)
	if typeof(motor) == "table" and motor.IsFootRelativePole then
		return require("LimbIK").legPoleWorld(motor.Owner, motor.C0)
	end

	if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
		return motor.Part0.CFrame * motor.C0
	end

	visiting = visiting or {}
	if visiting[motor] then
		return motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
	end

	visiting[motor] = true
	local parent = motorByPart and motorByPart[Parenting.realPart0(motor)]
	local parentWorld = parent and Parenting.worldOf(parent, motorByPart, visiting)
		or motor.Part0.CFrame
	visiting[motor] = nil
	return parentWorld * motor.C0 * motor.C1:Inverse()
end

function Parenting.restoreDefaults(rig)
	for _, motor in ipairs(Parenting.collectMotors(rig)) do
		motor:SetAttribute("TrackParent", Parenting.getDefault(motor))
	end
end

function Parenting.newEvaluator(
	motors,
	keys,
	defaults,
	defaultWorld,
	parentingDefaults,
	evaluateC0,
	loopEndTime
)
	local byPart = Parenting.buildMotorMap(motors)
	for part, motor in require("RawState").Timeline.MotorByPart do
		if not byPart[part] then
			byPart[part] = motor
		end
	end

	local Target = require("Target")
	local samples = {}
	local worldAt, localAt, parentAt
	local masters = {}

	local function masterFor(motor, visiting)
		if masters[motor] ~= nil then
			return masters[motor]
		end

		if typeof(motor) == "table" and motor.IsEclipseMasterControl then
			return motor
		end

		visiting = visiting or {}
		if visiting[motor] then
			return false
		end

		visiting[motor] = true
		local parent = byPart[Parenting.realPart0(motor)]
		local master = parent and masterFor(parent, visiting) or false

		if not master then
			local owner = motor.Part1
			while typeof(owner) == "Instance" and owner ~= workspace do
				if owner:IsA("Model") then
					master = MasterControl.get(owner) or false
					if master then
						break
					end
				end

				owner = owner.Parent
			end
		end

		masters[motor] = master
		return master
	end

	local function masterAt(motor, time)
		local master = masterFor(motor)
		if not master or master == motor or not MasterControl.enabled(master.Parent) then
			return CFrame.identity
		end

		local value = localAt(master, time)
		if value == master.C1 then
			return CFrame.identity
		end

		local base = master.Part0.CFrame
		return base * value * master.C1:Inverse() * base:Inverse()
	end

	local childMotors = {}

	local function keyIsParented(motor, key)
		if HeadStabilizerMode.isEnabled(motor, keys[motor], key.Time) then
			return true
		end

		if key and typeof(key.IKRestoreParented) == "boolean" then
			return key.IKRestoreParented
		end

		return Parenting.keyIsParented(motor, key, parentingDefaults[motor])
	end

	local function scan(bucket, time)
		local shared = bucket and HeadStabilizerMode.poseCache()
		if shared and shared.persistent and Interp.index(bucket) then
			shared.parentLinks = shared.parentLinks or setmetatable({}, { __mode = "k" })
			local linked = shared.parentLinks[bucket]
			if linked == nil then
				linked = false
				for _, key in bucket do
					if not key.GraphOnly and not key.Disabled and key.CamTargetParent then
						linked = true
						break
					end
				end

				shared.parentLinks[bucket] = linked
			end

			local previous, following = Parenting.bounds(bucket, time)
			return previous, following, linked
		end

		local previous, following, linked = nil, nil, false
		for _, key in pairs(bucket or {}) do
			if key.GraphOnly or key.Disabled then
				continue
			end

			if key.CamTargetParent then
				linked = true
			end

			if key.Time <= time then
				if not previous or key.Time > previous.Time then
					previous = key
				end
			elseif not following or key.Time < following.Time then
				following = key
			end
		end

		return previous, following, linked
	end

	local function sampleAt(motor, time)
		local atTime = samples[time]
		if not atTime then
			atTime = {}
			samples[time] = atTime
		end

		local sample = atTime[motor]
		if not sample then
			local previous, following, linked = scan(keys[motor], time)
			if childMotors[motor] == nil then
				childMotors[motor] = linked
			end

			sample = {
				previous = previous,
				following = following,
				parented = HeadStabilizerMode.isEnabled(motor, keys[motor], time)
					or Parenting.keyIsParented(motor, previous, parentingDefaults[motor]),
			}
			atTime[motor] = sample
		end

		return sample
	end

	local function childAt(motor, time)
		if Target.is(motor) then
			return false
		end

		local sample = sampleAt(motor, time)
		if not childMotors[motor] then
			return false
		end

		if sample.child == nil then
			local a, b = sample.previous, sample.following
			sample.child = (a and (a.CamTargetParent or b and b.CamTargetParent)) and true or false
		end

		return sample.child
	end

	local function parentWorldAt(motor, time)
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			return motor.Part0.CFrame
		end

		local parent = byPart[Parenting.realPart0(motor)]
		if parent then
			return worldAt(parent, time)
		end

		local anchor = motor.Part0
		if typeof(anchor) == "table" and anchor.AnchorRoot then
			local rootMotor = byPart[anchor.AnchorRoot]
			if rootMotor and rootMotor ~= motor then
				return worldAt(rootMotor, time) * anchor.AnchorOffset
			end
		end

		local frame = motor.Part0.CFrame
		local master = masterFor(motor)
		local part = typeof(anchor) == "table" and anchor.AnchorRoot or Parenting.realPart0(motor)
		if
			master
			and master ~= motor
			and typeof(part) == "Instance"
			and part:IsDescendantOf(master.Parent)
		then
			local base = master.Part0.CFrame
			local live = base * master.C0 * master.C1:Inverse() * base:Inverse()
			frame = masterAt(motor, time) * live:Inverse() * frame
		end

		return frame
	end

	local function keyInSpace(motor, key, parented, neutral)
		local keyParented = keyIsParented(motor, key)
		local localCF = key.C0 or defaults[motor] or motor.C0
		local captured = key.WorldCFrame
		if captured and not key.CamTargetParent and masterFor(motor) then
			captured = (key.MasterWorld or CFrame.identity):Inverse() * captured
			if not neutral then
				captured = masterAt(motor, key.Time) * captured
			end
		end

		if keyParented == parented then
			if parented then
				return localCF
			end

			if captured then
				return captured
			end
		end

		local parentWorld = parentWorldAt(motor, key.Time)
		if parented then
			return captured and parentWorld:Inverse() * captured * motor.C1 or localCF
		end

		local value = parentWorld * evaluateC0(motor, key.Time) * motor.C1:Inverse()
		return neutral and masterAt(motor, key.Time):Inverse() * value or value
	end

	local function spaceNeighbors(motor, bucket, previous, following, parented)
		local shared = HeadStabilizerMode.poseCache()
		local sorted = shared and shared.persistent and Interp.index(bucket)
		if not sorted then
			return nil
		end

		shared.spaceNeighbors = shared.spaceNeighbors or setmetatable({}, { __mode = "k" })
		local default = Parenting.keyIsParented(motor, nil, parentingDefaults[motor])
		local entry = shared.spaceNeighbors[bucket]
		if not entry or entry.motor ~= motor or entry.default ~= default then
			entry = {
				motor = motor,
				default = default,
				keys = {},
				positions = {},
				left = {},
				right = {},
			}
			local lastTrue, lastFalse = 0, 0
			for _, item in sorted do
				local key = item.key
				if key.GraphOnly or key.Disabled then
					continue
				end

				local n = #entry.keys + 1
				entry.keys[n], entry.positions[key] = key, n
				local state = keyIsParented(motor, key)
				entry.left[n] = { lastFalse, lastTrue, state }
				if state then
					lastTrue = n
				else
					lastFalse = n
				end
			end

			local nextTrue, nextFalse = #entry.keys + 1, #entry.keys + 1
			for n = #entry.keys, 1, -1 do
				if entry.left[n][3] then
					nextTrue = n
				else
					nextFalse = n
				end

				entry.right[n] = { nextFalse, nextTrue }
			end

			shared.spaceNeighbors[bucket] = entry
		end

		local p, q = entry.positions[previous], entry.positions[following]
		if not p or not q then
			return nil
		end

		local side = if parented then 1 else 2
		local first = math.min(p, entry.left[p][side] + 1)
		local last = math.max(q, entry.right[p][side] - 1)
		local list = entry.keys
		return true,
			if p > first then list[p - 1] else nil,
			if q < last then list[q + 1] else nil,
			list[first],
			if first < last then list[first + 1] else nil,
			list[last],
			if last > first then list[last - 1] else nil
	end

	local function interpolateSpace(motor, previous, following, time, parented)
		if not previous then
			return following and keyInSpace(motor, following, parented, not parented)
		end

		if not following or time == previous.Time then
			return keyInSpace(motor, previous, parented, not parented)
		end

		local bucket = keys[motor]
		local indexed, before, after, first, second, last, penultimate =
			spaceNeighbors(motor, bucket, previous, following, parented)
		if not indexed then
			local leftBoundary, rightBoundary = -math.huge, math.huge
			for _, key in pairs(bucket) do
				if key.GraphOnly or key.Disabled then
					continue
				end

				if keyIsParented(motor, key) ~= parented then
					if key.Time < previous.Time then
						leftBoundary = math.max(leftBoundary, key.Time)
					else
						rightBoundary = math.min(rightBoundary, key.Time)
					end
				end
			end

			for _, key in pairs(bucket) do
				if key.GraphOnly or key.Disabled then
					continue
				end

				if
					key ~= previous
					and key ~= following
					and (key.Time <= leftBoundary or key.Time >= rightBoundary)
				then
					continue
				end

				if key.Time < previous.Time and (not before or key.Time > before.Time) then
					before = key
				end

				if key.Time > following.Time and (not after or key.Time < after.Time) then
					after = key
				end

				if loopEndTime then
					if not first or key.Time < first.Time then
						second, first = first, key
					elseif not second or key.Time < second.Time then
						second = key
					end

					if not last or key.Time > last.Time then
						penultimate, last = last, key
					elseif not penultimate or key.Time > penultimate.Time then
						penultimate = key
					end
				end
			end
		end

		local converted = {}

		local function convert(key)
			if not key then
				return nil
			end

			if converted[key.Time] then
				return converted[key.Time]
			end

			local entry = table.clone(key)
			entry.C0 = keyInSpace(motor, key, parented, not parented)
			if not parented and key.MasterWorld and masterFor(motor) then
				if entry.PathTangentIn then
					entry.PathTangentIn = key.MasterWorld:VectorToObjectSpace(entry.PathTangentIn)
				end

				if entry.PathTangentOut then
					entry.PathTangentOut = key.MasterWorld:VectorToObjectSpace(entry.PathTangentOut)
				end
			end

			if keyIsParented(motor, key) ~= parented then
				entry.PathTangentIn, entry.PathTangentOut = nil, nil
			end

			converted[key.Time] = entry
			return entry
		end

		local a, b = convert(previous), convert(following)
		convert(before)
		convert(after)
		if loopEndTime then
			convert(first)
			convert(second)
			convert(last)
			convert(penultimate)
		end

		local alpha = math.clamp((time - previous.Time) / (following.Time - previous.Time), 0, 1)
		local value = Interp.cframe(converted, a, b, alpha, "C0", loopEndTime)
		if PivotSpace.blocked(motor, time) then
			return value
		end

		return PivotSpace.correct(
			converted,
			a,
			b,
			alpha,
			"C0",
			loopEndTime,
			if parented then PivotSpace.jointOffset(motor) else PivotSpace.get(motor),
			value
		)
	end

	localAt = function(motor, time)
		local sample = sampleAt(motor, time)
		if sample.localCF then
			return sample.localCF
		end

		local localCF
		if motor:GetAttribute("EclipseDisabled") then
			localCF = defaults[motor] or motor.C0
		elseif Target.is(motor) then
			localCF = motor.Part0.CFrame:Inverse()
				* Target.evaluate(motor, time, keys, defaults, worldAt, parentAt)
				* motor.C1
		elseif sample.parented and not childAt(motor, time) then
			local following = sample.following
			if following and not keyIsParented(motor, following) then
				localCF = interpolateSpace(motor, sample.previous, following, time, true)
			end

			localCF = localCF or evaluateC0(motor, time)
		else
			localCF = parentWorldAt(motor, time):Inverse() * worldAt(motor, time) * motor.C1
		end

		sample.localCF = localCF
		return localCF
	end

	worldAt = function(motor, time)
		local sample = sampleAt(motor, time)
		if sample.world then
			return sample.world
		end

		if sample.evaluating then
			return defaultWorld[motor] or Parenting.worldOf(motor, byPart)
		end

		sample.evaluating = true
		local world
		if childAt(motor, time) and not motor:GetAttribute("EclipseDisabled") then
			world = Target.evaluateChild(
				time,
				keys[motor],

				function(key)
					return keyInSpace(motor, key, false)
				end,
				worldAt,
				parentAt,

				function(at)
					return masterAt(motor, at)
				end,
				motor
			) or parentWorldAt(motor, time) * evaluateC0(motor, time) * motor.C1:Inverse()
		elseif not sample.parented and not motor:GetAttribute("EclipseDisabled") then
			local previous, following = sample.previous, sample.following
			local curveBucket = keys[motor]
			world = interpolateSpace(motor, previous, following, time, false)
				or defaultWorld[motor]
				or Parenting.worldOf(motor, byPart)
			local compiled = GraphCurves.compile(curveBucket)
			local channelEasing = GraphCurves.hasChannelEasing(curveBucket)
			if compiled.hasGraph or channelEasing then
				local key = previous or following
				local reference = key and key.C0 or defaults[motor] or motor.C0
				if previous and following and previous ~= following then
					local alpha =
						math.clamp((time - previous.Time) / (following.Time - previous.Time), 0, 1)
					reference = Interp.cframe(
						curveBucket,
						previous,
						following,
						alpha,
						"C0",
						loopEndTime
					) or reference
				end

				local edited = if channelEasing
					then evaluateC0(motor, time)
					else GraphCurves.cframe(curveBucket, time, reference, motor, loopEndTime)
				world = world * motor.C1 * reference:Inverse() * edited * motor.C1:Inverse()
			end

			if masterFor(motor) then
				world = masterAt(motor, time) * world
			end
		else
			world = parentWorldAt(motor, time) * localAt(motor, time) * motor.C1:Inverse()
		end

		sample.evaluating = nil
		sample.world = world
		return world
	end

	parentAt = Target.parentSampler(worldAt)
	return {
		parentAt = parentAt,
		worldAt = worldAt,
		localAt = localAt,
		parentWorldAt = parentWorldAt,
		childAt = childAt,
		isParentedAt = function(motor, time)
			return sampleAt(motor, time).parented
		end,
	}
end

return Parenting
