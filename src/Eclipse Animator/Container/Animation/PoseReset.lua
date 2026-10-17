--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Pose = require("RigPose")
local Run = game:GetService("RunService")
local Reset = {}

function Reset.refresh(button, selection, state)
	local rig, multiple = Pose.resolve(selection:Get(), state.Rig and state.Rig._selectedItems)
	local enabled = rig ~= nil and rig.Parent ~= nil and not multiple
	button.Interactable = enabled
	local text = button:FindFirstChildOfClass("TextLabel")
	if text then
		text.TextTransparency = enabled and 0 or 0.55
	end

	button:SetAttribute("Ready", enabled)
	return enabled
end

function Reset.attach(frame, selection, state, gui)
	local connections = {}
	local elapsed = 0

	local function refresh()
		Reset.refresh(frame.ResetPose, selection, state)
	end

	table.insert(connections, selection.SelectionChanged:Connect(refresh))
	table.insert(connections, gui:GetPropertyChangedSignal("Enabled"):Connect(refresh))

	table.insert(
		connections,
		Run.Heartbeat:Connect(function(dt)
			elapsed += dt
			if gui.Enabled and elapsed >= 0.15 then
				elapsed = 0
				refresh()
			end
		end)
	)
	frame.Destroying:Once(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	refresh()
end

return Reset
