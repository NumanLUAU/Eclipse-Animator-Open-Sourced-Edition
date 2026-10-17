--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

const ID = "Emit"
const LIMIT = 100000
local EmitKeys = {}

EmitKeys.ID = ID
EmitKeys.LIMIT = LIMIT

function EmitKeys.supports(rig, id)
	return id == ID and typeof(rig) == "Instance" and rig:IsA("ParticleEmitter")
end

function EmitKeys.count(value)
	value = tonumber(value)
	if not value or value ~= value then
		return 0
	end

	return math.clamp(math.floor(value + 1e-6), 0, LIMIT)
end

function EmitKeys.default(rig)
	const count = tonumber(rig:GetAttribute("EmitCount"))
	return count and count == count and EmitKeys.count(count) or 1
end

return EmitKeys
