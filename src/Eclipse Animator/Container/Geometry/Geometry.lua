--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Camera = require("CameraRig")
local Display = require("CameraDisplay")
local Ghost = {}
local padding = 1.01

local function paddedFrame(frame)
	return CFrame.new(frame.Position * padding) * frame.Rotation
end

function Ghost.scope(object)
	if Camera.isRig(object) or object:IsA("Camera") then
		return object
	end

	if object.Parent == game or object:IsA("Terrain") then
		return nil
	end

	if object:IsA("Model") or object:IsA("BasePart") then
		return object
	end

	if object:IsA("Attachment") then
		return object
	end

	local parent = object.Parent
	while parent and parent ~= workspace do
		if parent:IsA("BasePart") or parent:IsA("Model") or parent:IsA("Attachment") then
			return parent
		end

		parent = parent.Parent
	end

	return nil
end

local function anchor(parent, frame)
	local p = Instance.new("Part")
	p.Name = "Pose"
	p.Size = Vector3.one * 0.25
	p.CFrame = frame
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Locked = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

function Ghost.capture(object, scope, color, transparency)
	local model = Instance.new("Model")
	if Camera.isRig(object) or object:IsA("Camera") then
		local isRig = Camera.isRig(object)
		local part = anchor(model, isRig and Camera.displayFrame(object) or object.CFrame)
		local fov = isRig and Camera.fov(object) or object.FieldOfView
		for i, pair in Display.segments(fov) do
			local line = Instance.new("LineHandleAdornment")
			line.Name = "Frustum" .. i
			line.Adornee = part
			line.CFrame = CFrame.lookAt(pair[1], pair[2])
			line.Length = (pair[2] - pair[1]).Magnitude
			line.Thickness = 3
			line.Color3 = color
			line.Transparency = transparency
			line.AlwaysOnTop = true
			line.Parent = part
		end

		return model
	end

	if scope:IsA("Attachment") then
		local part =
			anchor(model, scope:IsA("Bone") and scope.TransformedWorldCFrame or scope.WorldCFrame)
		local sphere = Instance.new("SphereHandleAdornment")
		sphere.Adornee = part
		sphere.Radius = 0.18
		sphere.Color3 = color
		sphere.Transparency = transparency
		sphere.AlwaysOnTop = true
		sphere.Parent = part
		for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
			local line = Instance.new("LineHandleAdornment")
			line.Adornee = part
			line.CFrame = CFrame.lookAt(Vector3.zero, axis)
			line.Length = 0.6
			line.Thickness = 2
			line.Color3 = color
			line.Transparency = transparency
			line.AlwaysOnTop = true
			line.Parent = part
		end

		return model
	end

	local copies = {}
	local objects = { scope }
	if scope:IsA("Model") then
		copies[scope] = model
		objects = {}
	end

	for _, v in scope:GetDescendants() do
		table.insert(objects, v)
	end

	local links = {}
	for _, source in objects do
		local parent = source == scope and model or copies[source.Parent]
		if
			not parent
			or source.ClassName == "Status"
			or source:GetAttribute("EclipseArmatureBone")
			or source:GetAttribute("EclipseAnimator_BonesFolder")
		then
			continue
		end

		if
			source:IsA("Model")
			or source:IsA("Folder")
			or source:IsA("Accessory")
			or source:IsA("BasePart")
			or source:IsA("Attachment")
			or source:IsA("DataModelMesh")
			or source:IsA("Humanoid")
			or source:IsA("CharacterMesh")
			or source:IsA("Beam")
		then
			local copy = Instance.fromExisting(source)
			copies[source] = copy
			if copy:IsA("BasePart") then
				copy.Anchored = true
				copy.CanQuery = false
				copy.CanTouch = false
				copy.CanCollide = false
				copy.Locked = true
				copy.CastShadow = false
				copy.Size = source.Size * padding
				copy.Color = color
				copy.Material = Enum.Material.SmoothPlastic
				copy.MaterialVariant = ""
				copy:SetAttribute("EclipseGhostSourceTransparency", source.Transparency)
				copy.Transparency = 1 - (1 - source.Transparency) * (1 - transparency)
				if copy:IsA("MeshPart") then
					copy.TextureID = ""
				end
			elseif copy:IsA("Bone") then
				copy.CFrame = paddedFrame(source.CFrame)
				copy.Transform = paddedFrame(source.Transform)
			elseif copy:IsA("FileMesh") then
				copy.TextureId = ""
				if not copy:IsA("SpecialMesh") or copy.MeshType == Enum.MeshType.FileMesh then
					copy.Scale = source.Scale * padding
				end
			elseif copy:IsA("CharacterMesh") then
				copy.BaseTextureId = 0
				copy.OverlayTextureId = 0
			elseif copy:IsA("Beam") then
				copy.Color = ColorSequence.new(color)
				copy.Transparency = NumberSequence.new(transparency)
				table.insert(links, { source, copy })
			elseif copy:IsA("Humanoid") then
				copy.EvaluateStateMachine = false
				copy.AutoRotate = false
				copy.RequiresNeck = false
				copy.BreakJointsOnDeath = false
				copy.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end

			copy.Parent = parent
		end
	end

	for _, pair in links do
		for _, key in { "Attachment0", "Attachment1" } do
			local source = pair[1][key]
			local copy = source and copies[source]
			if source and not copy then
				copy = Instance.new("Attachment")
				copy.Parent = anchor(model, source.WorldCFrame)
			end

			pair[2][key] = copy
		end
	end

	return model
end

function Ghost.opacity(model, transparency)
	for _, object in model:GetDescendants() do
		if object:IsA("BasePart") then
			local source = object:GetAttribute("EclipseGhostSourceTransparency")
			if source ~= nil then
				object.Transparency = 1 - (1 - source) * (1 - transparency)
			end
		elseif object:IsA("HandleAdornment") then
			object.Transparency = transparency
		elseif object:IsA("Beam") then
			object.Transparency = NumberSequence.new(transparency)
		end
	end
end

function Ghost.tint(model, color, targets)
	if not targets then
		targets = { parts = {}, adornments = {}, beams = {} }
		for _, object in model:GetDescendants() do
			if object:IsA("BasePart") then
				table.insert(targets.parts, object)
			elseif object:IsA("HandleAdornment") then
				table.insert(targets.adornments, object)
			elseif object:IsA("Beam") then
				table.insert(targets.beams, object)
			end
		end
	end

	for _, object in targets.parts do
		object.Color = color
	end

	for _, object in targets.adornments do
		object.Color3 = color
	end

	if #targets.beams > 0 then
		local sequence = ColorSequence.new(color)
		for _, object in targets.beams do
			object.Color = sequence
		end
	end

	return targets
end

return Ghost
