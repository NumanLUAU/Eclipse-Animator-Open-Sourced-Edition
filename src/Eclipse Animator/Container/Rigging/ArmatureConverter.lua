--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local ArmatureData = require("ChunkStore")
local HttpService = game:GetService("HttpService")
local Binding = require("Binding")
local Geometry = require("distance")
local Visibility = require("ArmatureVisibility")
local Runtime = require("ArmatureRuntime")
local Converter = {}

local function vector(value)
	return Vector3.new(value[1], value[2], value[3])
end

local function color(value, fallback)
	return value and Color3.new(value[1], value[2], value[3]) or fallback
end

local function geometry(bone)
	local display = bone.display
	if not display or not display.vertices then
		return bone.edges or {}, bone.tris or {}, false
	end

	local edges, triangles = {}, {}
	for _, edge in display.edges or {} do
		table.insert(edges, { display.vertices[edge[1] + 1], display.vertices[edge[2] + 1] })
	end

	for _, triangle in display.triangles or {} do
		table.insert(triangles, {
			display.vertices[triangle[1] + 1],
			display.vertices[triangle[2] + 1],
			display.vertices[triangle[3] + 1],
		})
	end

	return edges, triangles, true
end

local function storeRest(reference, target, plan)
	if target:IsA("JointInstance") then
		reference:SetAttribute(
			"EclipseArmatureRestC0",
			plan.restWorlds[target.Part0]:Inverse() * plan.restWorlds[target]
		)
	elseif target:IsA("Bone") then
		reference:SetAttribute("EclipseArmatureRestC0", target.CFrame)
	end
end

function Converter.build(data, rig)
	local plan = Binding.plan(data, rig)
	local visibility = Visibility.classify(data)
	local arm = Instance.new("Model")
	arm.Name = "Armature"
	arm:SetAttribute("EclipseArmature", true)
	arm:SetAttribute("EclipseArmatureVersion", 4)
	arm:SetAttribute("EclipseArmatureFit", plan.frame)
	arm:SetAttribute("EclipseArmatureScale", plan.scale)
	arm:SetAttribute("EclipseArmatureFitError", plan.errorDistance)
	local ok, message = xpcall(function()
		ArmatureData.write(arm, "EclipseArmatureGraph", HttpService:JSONEncode(data))
		local lastYield = os.clock()

		local function point(value)
			return plan.frame * (value * plan.scale)
		end

		for _, bone in data.bones do
			local presentation = visibility[bone.id]
			local edges, triangles, rawDisplay = geometry(bone)
			local emptyDisplay = rawDisplay and #edges == 0 and #triangles == 0
			local entry = plan.entries[bone.id]
			local pose = plan.frame * Binding.matrix(bone.pose_matrix, plan.scale)
			local minimum, maximum

			local function include(raw)
				local localPoint = rawDisplay and vector(raw)
					or pose:PointToObjectSpace(point(vector(raw)))
				minimum = minimum and minimum:Min(localPoint) or localPoint
				maximum = maximum and maximum:Max(localPoint) or localPoint
			end

			for _, edge in edges do
				include(edge[1])
				include(edge[2])
			end

			for _, triangle in triangles do
				for _, v in triangle do
					include(v)
				end
			end

			if not minimum then
				if rawDisplay then
					include({ 0, 0, 0 })
					include({ 0, bone.display.length or 0, 0 })
				else
					include(bone.head)
					include(bone.tail)
				end
			end

			local center, size = (minimum + maximum) * 0.5, maximum - minimum
			local anchor = Instance.new("Part")
			anchor.Name = bone.name
			anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery, anchor.CastShadow =
				true, false, false, not presentation.hidden and not presentation.unselectable, false
			anchor.Transparency = 1
			anchor.Size =
				Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
			anchor.CFrame = pose * CFrame.new(center)
			anchor:SetAttribute("EclipseArmatureVisualRest", anchor.CFrame)
			if rawDisplay then
				anchor:SetAttribute("EclipseArmatureRawDisplay", true)
				anchor:SetAttribute("EclipseArmatureRawCenter", center)
				anchor:SetAttribute("EclipseArmatureRawSize", size)
			end

			anchor.PivotOffset = CFrame.new(-center)
			anchor:SetAttribute("EclipseArmatureBone", true)
			anchor:SetAttribute("EclipseArmatureControl", presentation.control)
			if emptyDisplay then
				anchor:SetAttribute("EclipseArmatureEmptyDisplay", true)
			end

			anchor:SetAttribute("EclipseArmatureBoneId", bone.id)
			anchor:SetAttribute("EclipseArmatureVisualOffset", CFrame.new(center))
			anchor:SetAttribute("EclipseDesignRot", pose.Rotation)
			anchor:SetAttribute("ParentBone", bone.parent)
			anchor:SetAttribute("Head", point(vector(bone.head)))
			anchor:SetAttribute("Tail", point(vector(bone.tail)))
			anchor:SetAttribute("Hidden", presentation.hidden)
			anchor:SetAttribute("Solid", Geometry.isSolid(bone))
			anchor:SetAttribute("EclipseDeform", bone.deform == true)
			anchor:SetAttribute("BoneColor", color(bone.color, Color3.new(0.5, 0.5, 0.5)))
			anchor:SetAttribute("SelectColor", color(bone.select, Color3.new(1, 1, 1)))
			anchor:SetAttribute("ActiveColor", color(bone.active, Color3.new(1, 1, 1)))
			anchor.Parent = arm
			if entry.targets then
				local rest = plan.frame * Binding.matrix(bone.rest_matrix, plan.scale)
				local first = entry.targets[1]
				local target = Instance.new("ObjectValue")
				target.Name, target.Value, target.Parent = "EclipseArmatureTarget", first, anchor
				storeRest(target, first, plan)
				anchor:SetAttribute(
					"EclipseArmatureBindOffset",
					rest:Inverse() * plan.restWorlds[first]
				)
				if #entry.targets > 1 then
					local copies = Instance.new("Folder")
					copies.Name, copies.Parent = "EclipseArmatureTargets", anchor
					for index, object in entry.targets do
						local ref = Instance.new("ObjectValue")
						ref.Name, ref.Value, ref.Parent = tostring(index), object, copies
						ref:SetAttribute("BindOffset", rest:Inverse() * plan.restWorlds[object])
						storeRest(ref, object, plan)
					end
				end
			end

			if presentation.control then
				local lines = {}
				for _, edge in edges do
					table.insert(
						lines,
						rawDisplay and vector(edge[1])
							or anchor.CFrame:PointToObjectSpace(point(vector(edge[1])))
					)
					table.insert(
						lines,
						rawDisplay and vector(edge[2])
							or anchor.CFrame:PointToObjectSpace(point(vector(edge[2])))
					)
				end

				for _, selected in { false, true } do
					local wire = Instance.new("WireframeHandleAdornment")
					wire.Name = selected and "XRayEdgesSelect" or "XRayEdges"
					wire.Adornee, wire.AlwaysOnTop, wire.ZIndex, wire.Visible =
						anchor, true, 1, not selected
					wire.Color3 = anchor:GetAttribute(selected and "SelectColor" or "BoneColor")
					wire.Parent = anchor
				end

				Geometry.setLines(anchor, lines)
				if Geometry.isSolid(bone) and #triangles > 0 then
					Geometry.solid(anchor, triangles, point, rawDisplay)
				end

				Geometry.setVisible(anchor, not presentation.hidden)
			end

			if os.clock() - lastYield > 0.012 then
				task.wait()
				lastYield = os.clock()
			end
		end
	end, debug.traceback)
	if not ok then
		for _, anchor in arm:GetChildren() do
			if anchor:IsA("BasePart") then
				Geometry.clear(anchor)
			end
		end

		arm:Destroy()
		error(message, 0)
	end

	return arm, plan
end

function Converter.attach(arm, rig, data)
	data = data or HttpService:JSONDecode(ArmatureData.read(arm.EclipseArmatureGraph))
	local needsRebind = false
	for _, anchor in arm:GetChildren() do
		local ref = anchor:FindFirstChild("EclipseArmatureTarget")
		if ref and (not ref.Value or not ref.Value:IsDescendantOf(rig)) then
			needsRebind = true
			break
		end
	end

	if needsRebind then
		local plan = Binding.plan(data, rig)
		local ratio = plan.scale / (arm:GetAttribute("EclipseArmatureScale") or plan.scale)
		arm:SetAttribute("EclipseArmatureFit", plan.frame)
		arm:SetAttribute("EclipseArmatureScale", plan.scale)
		for _, anchor in arm:GetChildren() do
			local id = anchor:GetAttribute("EclipseArmatureBoneId")
			local entry = id and plan.entries[id]
			if entry then
				local offset = anchor:GetAttribute("EclipseArmatureVisualOffset")
				offset = CFrame.new(offset.Position * ratio) * offset.Rotation
				anchor:SetAttribute("EclipseArmatureVisualOffset", offset)
				anchor.Size *= ratio
				anchor.PivotOffset = CFrame.new(anchor.PivotOffset.Position * ratio)
					* anchor.PivotOffset.Rotation
				anchor.CFrame = plan.frame
					* Binding.matrix(entry.data.pose_matrix, plan.scale)
					* offset
				anchor:SetAttribute("EclipseArmatureVisualRest", anchor.CFrame)
				Geometry.clear(anchor)
				local old = anchor:FindFirstChild("EclipseArmatureTarget")
				if old then
					old:Destroy()
				end

				local copies = anchor:FindFirstChild("EclipseArmatureTargets")
				if copies then
					copies:Destroy()
				end

				if entry.targets then
					local rest = plan.frame * Binding.matrix(entry.data.rest_matrix, plan.scale)
					local target = Instance.new("ObjectValue")
					target.Name, target.Value, target.Parent =
						"EclipseArmatureTarget", entry.targets[1], anchor
					storeRest(target, entry.targets[1], plan)
					anchor:SetAttribute(
						"EclipseArmatureBindOffset",
						rest:Inverse() * plan.restWorlds[entry.targets[1]]
					)
					if #entry.targets > 1 then
						copies = Instance.new("Folder")
						copies.Name, copies.Parent = "EclipseArmatureTargets", anchor
						for index, object in entry.targets do
							local ref = Instance.new("ObjectValue")
							ref.Name, ref.Value, ref.Parent = tostring(index), object, copies
							ref:SetAttribute("BindOffset", rest:Inverse() * plan.restWorlds[object])
							storeRest(ref, object, plan)
						end
					end
				end
			end
		end
	end

	Converter.restoreShapes(arm, data)
	local entry = Runtime.attach(arm, rig, data)
	assert(Runtime.evaluate(rig, true), "The armature could not be evaluated")
	return entry
end

function Converter.restoreShapes(arm, data)
	data = data or HttpService:JSONDecode(ArmatureData.read(arm.EclipseArmatureGraph))
	local visibility = Visibility.classify(data)
	local fit, scale =
		arm:GetAttribute("EclipseArmatureFit"), arm:GetAttribute("EclipseArmatureScale")
	local byId = {}
	for _, anchor in arm:GetChildren() do
		if anchor:IsA("BasePart") then
			byId[anchor:GetAttribute("EclipseArmatureBoneId")] = anchor
		end
	end

	for _, bone in data.bones do
		local anchor = byId[bone.id]
		if anchor then
			local solid = Geometry.isSolid(bone)
			if anchor:GetAttribute("Solid") ~= solid then
				Geometry.clear(anchor)
				anchor:SetAttribute("Solid", solid)
			end

			local presentation = visibility[bone.id]
			anchor:SetAttribute("EclipseArmatureControl", presentation.control)
			if not presentation.control then
				anchor:SetAttribute("Hidden", true)
				anchor.CanQuery = false
				Geometry.clear(anchor)
				Geometry.setVisible(anchor, false)
				continue
			end

			local current = anchor.CFrame
			local original = anchor:GetAttribute("EclipseArmatureVisualRest")
				or fit
					* Binding.matrix(bone.pose_matrix, scale)
					* anchor:GetAttribute("EclipseArmatureVisualOffset")
			if not Geometry.has(anchor) then
				anchor:SetAttribute("Hidden", true)
				anchor.CanQuery = false
				Geometry.setVisible(anchor, false)
				local edges, triangles, rawDisplay = geometry(bone)
				local lines = {}
				for _, edge in edges do
					table.insert(
						lines,
						rawDisplay and vector(edge[1])
							or original:PointToObjectSpace(fit * (vector(edge[1]) * scale))
					)
					table.insert(
						lines,
						rawDisplay and vector(edge[2])
							or original:PointToObjectSpace(fit * (vector(edge[2]) * scale))
					)
				end

				Geometry.setLines(anchor, lines)
				if solid and #triangles > 0 then
					Geometry.solid(anchor, triangles, function(point)
						return current * original:PointToObjectSpace(fit * (point * scale))
					end, rawDisplay)
				end
			end
		end
	end
end

return Converter
