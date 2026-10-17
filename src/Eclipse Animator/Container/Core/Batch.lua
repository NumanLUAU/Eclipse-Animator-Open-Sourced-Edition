--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Batch = {}

function Batch.run(rigs, exportRig)
	local results, seen = {}, {}
	for _, rig in rigs do
		if seen[rig] then
			continue
		end

		seen[rig] = true
		local result = { rig = rig, rigName = rig.Name }
		local ok, sequence = pcall(exportRig, rig)
		if ok and sequence then
			result.sequence = sequence
			result.animationName = sequence.Name
		else
			result.error = ok and "No animation could be built for this rig." or tostring(sequence)
		end

		table.insert(results, result)
	end

	return results
end

function Batch.commit(previous, candidate, parent)
	candidate:SetAttribute("EclipseAnimationModified", DateTime.now().UnixTimestampMillis)
	if not previous or previous.Parent ~= parent then
		candidate.Parent = parent
		require("History").protectSavedAnimations()
		return candidate
	end

	local children, attributes, loop =
		previous:GetChildren(), previous:GetAttributes(), previous.Loop
	local priority = previous.Priority
	local incoming = candidate:GetChildren()
	local ok, err = pcall(function()
		for _, child in children do
			child.Parent = nil
		end

		for _, child in incoming do
			child.Parent = previous
		end

		previous.Loop = candidate.Loop
		previous.Priority = candidate.Priority
		for key in attributes do
			if key:sub(1, 7) == "Eclipse" and key ~= "EclipseProjectId" then
				previous:SetAttribute(key, nil)
			end
		end

		for key, value in candidate:GetAttributes() do
			previous:SetAttribute(key, value)
		end
	end)
	if not ok then
		for _, child in incoming do
			child.Parent = candidate
		end

		for _, child in children do
			child.Parent = previous
		end

		previous.Loop = loop
		previous.Priority = priority
		for key in previous:GetAttributes() do
			previous:SetAttribute(key, nil)
		end

		for key, value in attributes do
			previous:SetAttribute(key, value)
		end

		candidate:Destroy()
		error(err)
	end

	for _, child in children do
		child:Destroy()
	end

	candidate:Destroy()
	require("History").protectSavedAnimations()
	return previous
end

function Batch.rename(result, value)
	local sequence = result.sequence
	if not sequence or not sequence.Parent then
		return false, "The local export was removed. Export this animation again."
	end

	local name = tostring(value or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
	if name == "" then
		name = sequence.Name
	end

	local ok, err = pcall(function()
		sequence.Name = name
		sequence:SetAttribute("EclipseAnimationModified", DateTime.now().UnixTimestampMillis)
	end)
	if not ok then
		return false, "Could not rename this animation. " .. tostring(err)
	end

	result.animationName = sequence.Name
	return true, sequence.Name
end

function Batch.publish(result, plugin, selection)
	local sequence = result.sequence
	if not sequence or not sequence.Parent then
		return false, "The local export was removed. Export this animation again."
	end

	if not plugin then
		return false, "Open Eclipse as a Studio plugin to publish."
	end

	local previous = selection:Get()
	local ok, err = pcall(function()
		selection:Set({ sequence })
		plugin:SaveSelectedToRoblox()
	end)
	if not ok then
		pcall(function()
			selection:Set(previous)
		end)
		return false, "Could not open Roblox's publisher. Please try again. " .. tostring(err)
	end

	result.publisherOpened = true
	return true
end

return Batch
