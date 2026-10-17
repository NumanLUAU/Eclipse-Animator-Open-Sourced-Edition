--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Parenting = require("Parenting")
local ArmatureRuntime = require("ArmatureRuntime")

local MotorMath = {}
local parentCompensation = setmetatable({}, { __mode = "k" })
local parentCompensationStart = setmetatable({}, { __mode = "k" })

function MotorMath.consumeParentCompensation(motor, c0, previous)
	local applied = parentCompensation[motor]
	local start = parentCompensationStart[motor]
	parentCompensation[motor] = nil
	parentCompensationStart[motor] = nil
	return applied ~= nil and applied == c0 and start == previous
end

function MotorMath.buildMotorByPart1(rig)
	return rig and Parenting.buildMotorMap(Parenting.collectMotors(rig)) or {}
end

function MotorMath.getPart1WorldCFrame(motor, motorByPart)
	if not motor or not motor.Part0 or not motor.Part1 then
		return nil
	end

	return Parenting.worldOf(motor, motorByPart)
end

function MotorMath.solveMotorC0ForWorldCFrame(motor, targetWorldCF, motorByPart, skipInputLocks)
	if not motor or not motor.Part0 or not targetWorldCF then
		return
	end

	local imported = typeof(motor) == "table" and motor.IsEclipseArmatureControl
	if imported then
		local edit = ArmatureRuntime.captureEdit(motor)
		local value = edit
			and ArmatureRuntime.solveEditC0(motor, targetWorldCF * motor.C1, edit, skipInputLocks)
		if value then
			motor.C0 = value
		end

		return
	end

	local parent = motorByPart and motorByPart[Parenting.realPart0(motor)]
	local parentWorld = parent and Parenting.worldOf(parent, motorByPart) or motor.Part0.CFrame
	motor.C0 = parentWorld:Inverse() * targetWorldCF * motor.C1
end

function MotorMath.isDescendantMotor(rig, ancestorMotor, testMotor, prebuiltMotorByPart1)
	if not rig or not ancestorMotor or not testMotor then
		return false
	end

	local map = prebuiltMotorByPart1 or MotorMath.buildMotorByPart1(rig)
	local current = map[Parenting.realPart0(testMotor)]
	local visited = {}
	while current and not visited[current] do
		if current == ancestorMotor then
			return true
		end

		visited[current] = true
		current = map[Parenting.realPart0(current)]
	end

	return false
end

function MotorMath.buildLockedDescendantMotorList(rig, movedMotor, movedSnapshots, prebuiltMap)
	local result = {}
	if not rig or not movedMotor then
		return result
	end

	local map = prebuiltMap or MotorMath.buildMotorByPart1(rig)
	local moved = {}
	if movedSnapshots then
		for _, snapshot in ipairs(movedSnapshots) do
			moved[snapshot.motor] = true
		end
	else
		moved[movedMotor] = true
	end

	for _, motor in pairs(map) do
		if moved[motor] or motor:GetAttribute("TrackParent") ~= false then
			continue
		end

		for ancestor in pairs(moved) do
			if typeof(ancestor) == "table" and ancestor.IsEclipseMasterControl then
				continue
			end

			if MotorMath.isDescendantMotor(rig, ancestor, motor, map) then
				table.insert(result, motor)
				break
			end
		end
	end

	return result
end

function MotorMath.captureWorldCFForMotorList(motors, rig, prebuiltMap)
	local result = { MotorByPart = prebuiltMap or MotorMath.buildMotorByPart1(rig) }
	for _, motor in ipairs(motors or {}) do
		if motor.Parent and motor.Part1 and motor.Part1.Parent then
			table.insert(result, {
				Motor = motor,
				WorldCF = Parenting.worldOf(motor, result.MotorByPart),
				ChildLock = require("Target").captureChildLock(
					motor,
					Parenting.worldOf(motor, result.MotorByPart)
				),
			})
		end
	end

	return result
end

function MotorMath.collectTrackParentLockedDescendants(rig, movedMotor)
	return MotorMath.captureWorldCFForMotorList(
		MotorMath.buildLockedDescendantMotorList(rig, movedMotor),
		rig
	)
end

function MotorMath.restoreTrackParentLockedDescendants(cachedList)
	local map = cachedList.MotorByPart or {}
	local targets, restored, held, childLocks = {}, {}, {}, {}
	for _, item in ipairs(cachedList) do
		targets[item.Motor] = item.WorldCF
		held[item.Motor] = true
		childLocks[item.Motor] = item.ChildLock
	end

	for _, info in cachedList.MovedSnapshots or {} do
		if
			not info.edit
			and info.targetWorldCF
			and info.motor.Parent
			and info.motor.Part0
			and map[info.motor.Part1] == info.motor
		then
			targets[info.motor] = info.targetWorldCF
		end
	end

	local function restore(motor)
		if not motor or restored[motor] then
			return
		end

		restored[motor] = true
		restore(map[Parenting.realPart0(motor)])
		local lock = childLocks[motor]
		if lock then
			restore(map[lock.object])
			targets[motor] = require("Target").restoreChildLock(motor, lock) or targets[motor]
		end

		if targets[motor] then
			if held[motor] and parentCompensation[motor] ~= motor.C0 then
				parentCompensationStart[motor] = motor.C0
			end

			MotorMath.solveMotorC0ForWorldCFrame(motor, targets[motor], map, true)
			if held[motor] then
				parentCompensation[motor] = motor.C0
			end
		end
	end

	for motor in pairs(targets) do
		restore(motor)
	end
end

return MotorMath
