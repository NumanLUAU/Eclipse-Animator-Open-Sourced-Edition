--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Properties = require("Properties")
local Membership = {}
local remembered = {}
local Main = require("State")

local function registeredOwner(object)
	if typeof(object) ~= "Instance" then
		return nil
	end

	local rigs = Main.getProjectRigs()
	while object do
		if table.find(rigs, object) then
			return object
		end

		object = object.Parent
	end
end

local function foreign(key, rig)
	local owner
	if typeof(key) == "table" then
		owner = key.Rig or registeredOwner(key.Bone or key.Part1 or key.RealInstance)
	elseif typeof(key) == "Instance" then
		owner = Properties.owner(key)
		if not owner and key:IsA("Motor6D") then
			owner = registeredOwner(key.Part1)
		end

		owner = owner or registeredOwner(key)
	end

	local scope = registeredOwner(rig)
	return owner ~= nil and scope ~= nil and owner ~= scope
end

local mapFields = {
	"Keyframes",
	"DefaultPose",
	"DefaultWorldPose",
	"ParentingDefaults",
	"MotorByPart",
	"DefaultSize",
	"_motorUniform",
	"_motorHasScale",
}

function Membership.belongs(key, rig, owned)
	if foreign(key, rig) then
		return false
	end

	if owned and owned[key] then
		return true
	end

	if Properties.is(key) then
		return key.Rig == rig
	end

	if typeof(key) == "Instance" and Properties.owner(key) == rig then
		return true
	end

	if typeof(key) == "table" then
		key = key.Bone or key.Part1 or key.RealInstance
	end

	if typeof(key) ~= "Instance" then
		return false
	end

	if key == rig or key:IsDescendantOf(rig) then
		return true
	end

	while owned and key do
		if owned[key] then
			return true
		end

		key = key.Parent
	end

	return false
end

function Membership.ownedKeys(state, rig)
	local owned = not rig.Parent and remembered[rig] and table.clone(remembered[rig])
		or { [rig] = true }
	local motors = {}
	for _, field in { "Keyframes", "DefaultPose", "ParentingDefaults" } do
		for motor in state[field] or {} do
			motors[motor] = true
		end
	end

	for _, motor in state.MotorByPart or {} do
		motors[motor] = true
	end

	local changed = true
	while changed do
		changed = false
		for motor in motors do
			if
				not owned[motor]
				and not foreign(motor, rig)
				and (
					Membership.belongs(motor, rig, owned)
					or Membership.belongs(motor.Part0, rig, owned)
				)
			then
				owned[motor] = true
				if motor.Part1 then
					owned[motor.Part1] = true
				end

				changed = true
			end
		end
	end

	return owned
end

function Membership.remember(state, rig)
	if not rig or not rig.Parent then
		return
	end

	local owned = Membership.ownedKeys(state, rig)

	for _, field in mapFields do
		for key in state[field] or {} do
			if Membership.belongs(key, rig, owned) then
				owned[key] = true
			end
		end
	end

	remembered[rig] = owned
end

function Membership.clear()
	table.clear(remembered)
end

function Membership.capture(state, rig)
	local snapshot = { owned = Membership.ownedKeys(state, rig) }
	for _, field in mapFields do
		local values = {}
		for key, value in state[field] or {} do
			if Membership.belongs(key, rig, snapshot.owned) then
				values[key] = value
			end
		end

		snapshot[field] = values
	end

	return snapshot
end

function Membership.remove(state, rig, snapshot)
	local owned = snapshot and snapshot.owned or Membership.ownedKeys(state, rig)
	for _, field in mapFields do
		for key in state[field] or {} do
			if
				snapshot and snapshot[field] and snapshot[field][key] ~= nil
				or Membership.belongs(key, rig, owned)
			then
				state[field][key] = nil
			end
		end
	end
end

function Membership.restore(state, snapshot)
	for _, field in mapFields do
		state[field] = state[field] or {}
		for key, value in snapshot[field] or {} do
			state[field][key] = value
		end
	end
end

function Membership.restoreNativeDefaults(state, rig, snapshot)
	for _, field in { "DefaultPose", "DefaultWorldPose", "DefaultSize", "ParentingDefaults" } do
		state[field] = state[field] or {}
		for key, value in snapshot[field] or {} do
			local object = typeof(key) == "table" and key.Bone or key
			if
				typeof(object) == "Instance"
				and object:IsDescendantOf(rig)
				and (object:IsA("Motor6D") or object:IsA("Bone") or object:IsA("BasePart"))
			then
				state[field][key] = value
			end
		end
	end
end

return Membership
