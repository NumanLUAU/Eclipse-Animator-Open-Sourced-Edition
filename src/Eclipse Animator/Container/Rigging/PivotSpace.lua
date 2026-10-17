--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Interp = require("Interp")
local HttpService = game:GetService("HttpService")

local PivotSpace = {}
local ATTRIBUTE = "EclipsePivot"
local SEQUENCE_ATTRIBUTE = "EclipsePivots"
local cache = setmetatable({}, { __mode = "k" })
local Preview, LimbIK

local function shared(motor)
	if not Preview then
		Preview = require("rig")
	end

	local original = Preview.original(motor)
	return if typeof(original) == "Instance"
			and original ~= motor
			and original:IsA("Motor6D")
		then original
		else nil
end

function PivotSpace.get(motor)
	if typeof(motor) ~= "Instance" or not motor:IsA("Motor6D") then
		return nil
	end

	local source = shared(motor) or motor
	local value = source:GetAttribute(ATTRIBUTE)
	if typeof(value) ~= "Vector3" then
		return nil
	end

	return value
end

function PivotSpace.set(motor, value)
	if typeof(motor) ~= "Instance" or not motor:IsA("Motor6D") then
		return
	end

	if value and (value - motor.C1.Position).Magnitude < 1e-4 then
		value = nil
	end

	motor:SetAttribute(ATTRIBUTE, value)
	local original = shared(motor)
	if original then
		original:SetAttribute(ATTRIBUTE, value)
	end
end

function PivotSpace.world(motor)
	local pivot = PivotSpace.get(motor)
	if not pivot or not motor.Part1 then
		return nil
	end

	return motor.Part1.CFrame:PointToWorldSpace(pivot)
end

function PivotSpace.jointOffset(motor)
	local pivot = PivotSpace.get(motor)
	if not pivot then
		return nil
	end

	return motor.C1:PointToObjectSpace(pivot)
end

local function rigMotors(rig)
	local map = {}
	for _, item in require("RigTraversal").descendants(rig) do
		if item:IsA("Motor6D") and item.Part0 and item.Part1 then
			local key = item.Part0.Name .. "/" .. item.Part1.Name
			map[key] = if map[key] == nil then item else false
		end
	end

	return map
end

function PivotSpace.write(sequence, rig)
	if not sequence or not rig then
		return
	end

	local saved = {}
	local any = false
	for key, motor in rigMotors(rig) do
		local value = motor and PivotSpace.get(motor)
		if value then
			saved[key] = { value.X, value.Y, value.Z }
			any = true
		end
	end

	sequence:SetAttribute(SEQUENCE_ATTRIBUTE, if any then HttpService:JSONEncode(saved) else nil)
end

function PivotSpace.read(sequence, rig)
	local encoded = sequence and rig and sequence:GetAttribute(SEQUENCE_ATTRIBUTE)
	if type(encoded) ~= "string" then
		return false
	end

	local ok, saved = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or type(saved) ~= "table" then
		return false
	end

	for key, motor in rigMotors(rig) do
		if not motor then
			continue
		end

		local value = saved[key]
		PivotSpace.set(
			motor,
			if type(value) == "table" and #value == 3
				then Vector3.new(value[1], value[2], value[3])
				else nil
		)
	end

	return true
end

function PivotSpace.blocked(motor, time)
	if not LimbIK then
		LimbIK = require("LimbIK")
	end

	local ok, driven = pcall(LimbIK.isDriven, motor, time)
	return ok and driven == true
end

function PivotSpace.rotate(motor, c0, rotation)
	local offset = PivotSpace.jointOffset(motor)
	if not offset then
		return c0 * rotation
	end

	return c0 * CFrame.new(offset) * rotation * CFrame.new(-offset)
end

local function proxies(bucket, field, offset)
	local entry = cache[bucket]
	if not entry or entry.field ~= field or entry.offset ~= offset then
		entry = { field = field, offset = offset, keys = {} }
		cache[bucket] = entry
	end

	local shifted = CFrame.new(offset)
	local view, seen = {}, {}
	for index, key in bucket do
		if type(key) ~= "table" then
			continue
		end

		local proxy = entry.keys[key]
		local value = key[field]
		if not proxy or proxy.source ~= value then
			proxy = {
				source = value,
				view = setmetatable({ [field] = value and value * shifted }, { __index = key }),
			}
			entry.keys[key] = proxy
		end

		seen[key] = proxy.view
		view[index] = proxy.view
	end

	return view, seen
end

function PivotSpace.skip(previous, following)
	return previous.IK
		or following.IK
		or previous.HS
		or following.HS
		or previous.BlenderCurve
		or following.BlenderCurve
end

function PivotSpace.correct(bucket, previous, following, alpha, field, loopEndTime, offset, base)
	if not offset or not base or not previous or not following or previous == following then
		return base
	end

	if not previous[field] or not following[field] or PivotSpace.skip(previous, following) then
		return base
	end

	local view, seen = proxies(bucket or { [1] = previous, [2] = following }, field, offset)
	local a = seen[previous]
		or setmetatable({ [field] = previous[field] * CFrame.new(offset) }, { __index = previous })
	local b = seen[following]
		or setmetatable(
			{ [field] = following[field] * CFrame.new(offset) },
			{ __index = following }
		)
	local pivoted = Interp.cframe(view, a, b, alpha, field, loopEndTime)
	if not pivoted then
		return base
	end

	return CFrame.new(pivoted.Position - base:VectorToWorldSpace(offset)) * base.Rotation
end

return PivotSpace
