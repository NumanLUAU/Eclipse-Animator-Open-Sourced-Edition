--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local AssetService = game:GetService("AssetService")
local Appearance = {}
local COLORS = { "Color", "Material", "MaterialVariant", "Reflectance" }
local CLOTHING =
	{ Shirt = true, Pants = true, ShirtGraphic = true, BodyColors = true, CharacterMesh = true }
local DESCRIPTION = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
	"Face",
	"Shirt",
	"Pants",
	"GraphicTShirt",
	"HeadColor",
	"TorsoColor",
	"LeftArmColor",
	"RightArmColor",
	"LeftLegColor",
	"RightLegColor",
}

local function applyDescription(target, source)
	for _, key in DESCRIPTION do
		target[key] = source[key]
	end

	target:SetAccessories(source:GetAccessories(true), true)
end

function Appearance.rigOf(object)
	if typeof(object) ~= "Instance" then
		return nil
	end

	local cursor = object
	while cursor and cursor ~= workspace do
		local reference = cursor:FindFirstChild("EclipseSourceRig")
		if reference and reference:IsA("ObjectValue") and reference.Value then
			local rig = reference.Value
			if rig:IsA("Model") and rig:FindFirstChildOfClass("Humanoid") then
				return rig
			end
		end

		if cursor:IsA("Model") and cursor:FindFirstChildOfClass("Humanoid") then
			return cursor
		end

		cursor = cursor.Parent
	end

	return nil
end

function Appearance.resolve(selected, items)
	local chosen = {}
	for _, object in selected do
		local rig = Appearance.rigOf(object)
		if rig and rig:IsDescendantOf(workspace) then
			chosen[rig] = true
		end
	end

	if not next(chosen) then
		for item, enabled in items or {} do
			if enabled then
				local owner = item.grandpa or item
				local rig = Appearance.rigOf(owner.linkedRigInstance or item.linkedRigInstance)
				if rig and rig:IsDescendantOf(workspace) then
					chosen[rig] = true
				end
			end
		end
	end

	local result
	for rig in chosen do
		if result then
			return nil, true
		end

		result = rig
	end

	return result, false
end

function Appearance.clone(model)
	local archivable = model.Archivable
	model.Archivable = true
	local ok, clone = pcall(model.Clone, model)
	model.Archivable = archivable
	assert(ok and clone, "couldn't preview this rig")
	return clone
end

local function visual(object)
	return object:IsA("DataModelMesh")
		or object:IsA("SurfaceAppearance")
		or object:IsA("WrapTarget")
		or object:IsA("Decal") and object.Name:lower() == "face"
end

local function capture(part)
	local entry = { part = part, values = {} }
	for _, key in COLORS do
		entry.values[key] = part[key]
	end

	if part:IsA("MeshPart") then
		entry.mesh = part:Clone()
		entry.mesh:ClearAllChildren()
	end

	return entry
end

local function applyPart(entry)
	local part = entry.part
	if entry.mesh then
		local size, transform = part.Size, part.CFrame
		part:ApplyMesh(entry.mesh)
		part.Size, part.CFrame = size, transform
	end

	for _, key in COLORS do
		part[key] = entry.values[key]
	end
end

local function ratio(size, original)
	return Vector3.new(
		size.X / math.max(original.X, 0.001),
		size.Y / math.max(original.Y, 0.001),
		size.Z / math.max(original.Z, 0.001)
	)
end

local function meshFor(part, source)
	if source:IsA("MeshPart") then
		local mesh = source:Clone()
		mesh:ClearAllChildren()
		return mesh
	end

	local shape = source:FindFirstChildOfClass("SpecialMesh")
	local uri = shape
		and (shape.MeshType == Enum.MeshType.Head and "rbxasset://fonts/head.mesh" or shape.MeshId)
	assert(uri and uri ~= "", "this body shape can't be applied without changing the rig")
	local mesh = AssetService:CreateMeshPartAsync(Content.fromUri(uri), {})
	mesh.TextureID = shape.TextureId
	return mesh
end

local function protected(accessory, tracks)
	if
		accessory:FindFirstChildWhichIsA("Motor6D", true)
		or accessory:FindFirstChildWhichIsA("Bone", true)
	then
		return true
	end

	for motor in tracks or {} do
		if typeof(motor) == "Instance" and motor:IsDescendantOf(accessory) then
			return true
		end

		local ok, part = pcall(function()
			return motor.Part1
		end)
		if ok and typeof(part) == "Instance" and part:IsDescendantOf(accessory) then
			return true
		end
	end

	for _, child in accessory:GetDescendants() do
		if child:GetAttribute("EclipseHelperWeld") then
			return true
		end
	end

	return false
end

function Appearance.prepare(target, donor, tracks)
	local humanoid = assert(target:FindFirstChildOfClass("Humanoid"), "select an R6 or R15 rig")
	local sourceHumanoid = assert(donor:FindFirstChildOfClass("Humanoid"), "the avatar didn't load")
	assert(
		humanoid.RigType == sourceHumanoid.RigType,
		"the avatar must use the selected rig's body type"
	)
	assert(
		donor:FindFirstChild("Head") and donor:FindFirstChild("HumanoidRootPart"),
		"the avatar didn't finish loading"
	)
	local plan =
		{ target = target, before = {}, after = {}, removed = {}, added = {}, active = false }
	local mapped = {}

	local function add(object, parent)
		table.insert(plan.added, { object = object, parent = parent })
		return object
	end

	local function remove(object)
		table.insert(plan.removed, { object = object, parent = object.Parent })
	end

	function plan:undo()
		for _, entry in self.added do
			entry.object.Parent = nil
		end

		for _, entry in self.before do
			applyPart(entry)
		end

		if self.description and self.beforeDescription then
			applyDescription(self.description, self.beforeDescription)
		end

		for _, entry in self.removed do
			entry.object.Parent = entry.parent
		end

		self.active = false
	end

	function plan:redo()
		for _, entry in self.removed do
			entry.object.Parent = nil
		end

		local ok, err = pcall(function()
			for _, entry in self.after do
				applyPart(entry)
			end

			applyDescription(self.description, self.afterDescription)
			for _, entry in self.added do
				entry.object.Parent = entry.parent
			end
		end)
		if not ok then
			self:undo()
			error(err, 0)
		end

		self.active = true
	end

	function plan:destroy()
		if self.beforeDescription then
			self.beforeDescription:Destroy()
		end

		if self.afterDescription then
			self.afterDescription:Destroy()
		end

		for _, entries in { self.before, self.after } do
			for _, entry in entries do
				if entry.mesh then
					entry.mesh:Destroy()
				end
			end
		end

		for _, entry in self.active and self.removed or self.added do
			entry.object:Destroy()
		end
	end

	local ok, err = pcall(function()
		plan.beforeDescription = humanoid:GetAppliedDescription()
		plan.afterDescription = sourceHumanoid:GetAppliedDescription()
		plan.description = humanoid:FindFirstChildOfClass("HumanoidDescription")
		if not plan.description then
			plan.description = add(plan.beforeDescription:Clone(), humanoid)
		end

		for _, source in donor:GetChildren() do
			if not source:IsA("BasePart") then
				continue
			end

			local part = target:FindFirstChild(source.Name)
			assert(part and part:IsA("BasePart"), "this rig is missing " .. source.Name)
			mapped[source] = part
		end

		for source, part in mapped do
			if source == sourceHumanoid.RootPart or source.Name == "HumanoidRootPart" then
				continue
			end

			table.insert(plan.before, capture(part))
			local after = { part = part, values = {} }
			for _, key in COLORS do
				after.values[key] = source[key]
			end

			if part:IsA("MeshPart") then
				after.mesh = meshFor(part, source)
			end

			table.insert(plan.after, after)
			for _, child in part:GetChildren() do
				if visual(child) then
					remove(child)
				end
			end

			for _, child in source:GetChildren() do
				if visual(child) and not (part:IsA("MeshPart") and child:IsA("DataModelMesh")) then
					if
						(child:IsA("SurfaceAppearance") or child:IsA("WrapTarget"))
						and not part:IsA("MeshPart")
					then
						continue
					end

					add(child:Clone(), part)
				elseif
					child:IsA("Attachment")
					and not child:IsA("Bone")
					and not part:FindFirstChild(child.Name)
				then
					local attachment = child:Clone()
					attachment.CFrame = CFrame.new(child.Position * ratio(part.Size, source.Size))
						* child.CFrame.Rotation
					add(attachment, part)
				end
			end

			if not part:IsA("MeshPart") and source:IsA("MeshPart") then
				local mesh = Instance.new("SpecialMesh")

				mesh.MeshType = Enum.MeshType.FileMesh
				mesh.MeshId = source.MeshId
				mesh.TextureId = source.TextureID
				local surface = source:FindFirstChildOfClass("SurfaceAppearance")
				if mesh.TextureId == "" and surface then
					mesh.TextureId = surface.ColorMap
				end

				mesh.Scale = ratio(part.Size, source.MeshSize)
				add(mesh, part)
			end
		end

		for _, child in target:GetChildren() do
			if
				CLOTHING[child.ClassName]
				or child:IsA("Accessory") and not protected(child, tracks)
			then
				remove(child)
			end
		end

		for _, source in donor:GetChildren() do
			if CLOTHING[source.ClassName] then
				add(source:Clone(), target)
			elseif source:IsA("Accessory") then
				local accessory = source:Clone()
				local attached = false
				for _, joint in accessory:GetDescendants() do
					if not joint:IsA("JointInstance") then
						continue
					end

					local body = mapped[joint.Part1]
					if not body or not joint.Part0 then
						continue
					end

					local handle = joint.Part0
					local attachment = handle:FindFirstChildWhichIsA("Attachment")
					local destination = attachment and body:FindFirstChild(attachment.Name)
					if not destination and attachment then
						for _, entry in plan.added do
							if
								entry.parent == body
								and entry.object:IsA("Attachment")
								and entry.object.Name == attachment.Name
							then
								destination = entry.object
								break
							end
						end
					end

					local old = handle.CFrame
					joint.Part1 = body
					joint.C1 = destination and destination.CFrame
						or CFrame.new(
								joint.C1.Position
									* ratio(body.Size, source.Parent:FindFirstChild(body.Name).Size)
							)
							* joint.C1.Rotation
					local placement = body.CFrame * joint.C1 * joint.C0:Inverse()
					for _, part in accessory:GetDescendants() do
						if part:IsA("BasePart") then
							part.CFrame = placement * old:ToObjectSpace(part.CFrame)
							part.Anchored = false
						end
					end

					attached = true
				end

				if attached then
					add(accessory, target)
				else
					accessory:Destroy()
					error("couldn't attach " .. source.Name, 0)
				end
			end
		end
	end)
	if not ok then
		plan:destroy()
		error(err, 0)
	end

	return plan
end

return Appearance
