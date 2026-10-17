--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Motion = require("Motion")
local Drag = {}

function Drag.makeDraggable(dragSources, mainFrame, followers, options)
	Motion.resetOnOpen(mainFrame)
	options = options or {}
	local sources = typeof(dragSources) == "Instance" and { dragSources } or dragSources
	local connections = {}
	local gesture
	for _, source in sources do
		if source:IsA("Frame") then
			source.Active = true
		end

		table.insert(
			connections,
			source.InputBegan:Connect(function(input)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end

				if mainFrame:GetAttribute("EclipseDocked") then
					return
				end

				local start, position, scale =
					input.Position, mainFrame.Position, Motion.scale(mainFrame)
				local followerStarts = {}
				local moved = false
				local originalActive
				for _, frame in followers or {} do
					followerStarts[frame] = frame.Position
				end

				gesture = Motion.begin(mainFrame, input, function(point)
					local pixels = point - start
					if not moved then
						if pixels.Magnitude < (options.dragThreshold or 0) then
							return
						end

						moved = true
						if options.suppressClickAfterDrag and source:IsA("GuiButton") then
							originalActive = source.Active
							source.Active = false
						end
					end

					local desired = position + UDim2.fromOffset(pixels.X / scale, pixels.Y / scale)
					local delta = Motion.constrain(mainFrame, desired) - position
					if mainFrame.Position ~= position + delta then
						mainFrame.Position = position + delta
					end

					for frame, origin in followerStarts do
						if frame.Parent then
							frame.Position = origin + delta
						end
					end
				end, function()
					gesture = nil
					if originalActive ~= nil then
						task.defer(function()
							if source.Parent then
								source.Active = originalActive
							end
						end)
					end

					if moved and mainFrame.Parent and options.onFinished then
						options.onFinished()
					end
				end)
			end)
		)
	end

	mainFrame.Destroying:Once(function()
		for _, connection in connections do
			connection:Disconnect()
		end

		if gesture then
			gesture.finish(true)
		end
	end)
end

return Drag
