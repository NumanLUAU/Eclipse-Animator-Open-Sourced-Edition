--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local State = require("State")
local Edit = {}

function Edit.blocked(allowDrawing)
	if State.LoadingProject and State.ProjectLoadThread ~= coroutine.running() then
		return true
	end

	if not allowDrawing and State.GreasePencil and State.GreasePencil.isDrawing() then
		return true
	end

	local bridge = State.BlenderBridge
	return bridge and bridge.isLocked and bridge.isLocked() or false
end

return Edit
