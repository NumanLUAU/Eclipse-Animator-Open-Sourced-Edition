--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Properties = require("Properties")
local Tree = require("RigTraversal")
local Dependencies = require("EventDependencies")
local Geometry = require("Geometry")
local Armature = require("ArmatureRuntime")
local Snapshot = {}
local fields = {
	Camera = { "CFrame", "Focus", "FieldOfView", "HeadScale", "CameraType", "CameraSubject" },
	BasePart = {
		"CFrame",
		"Size",
		"Color",
		"Transparency",
		"Reflectance",
		"Material",
		"MaterialVariant",
		"Anchored",
		"CastShadow",
		"LocalTransparencyModifier",
	},
	JointInstance = { "C0", "C1", "Part0", "Part1", "Enabled" },
	Motor6D = { "Transform" },
	Bone = { "CFrame", "Transform" },
	Attachment = { "CFrame" },
	AnimationConstraint = { "Transform" },
	SpecialMesh = { "Scale", "Offset", "VertexColor", "MeshId", "TextureId", "MeshType" },
	DataModelMesh = { "Scale", "Offset", "VertexColor" },
	Decal = { "Texture", "Color3", "Transparency", "LocalTransparencyModifier", "Face" },
	SurfaceAppearance = {
		"Color",
		"ColorMap",
		"MetalnessMap",
		"NormalMap",
		"RoughnessMap",
		"AlphaMode",
	},
}

function Snapshot.new(rigs, raw, surfaces)
	local self = {
		rows = {},
		joints = {},
		attributes = {},
		children = {},
		virtual = {},
		models = {},
		closed = false,
		hooks = {},
		geometry = {},
		armatures = {},
	}
	local seen = {}

	function self:remember(object, key)
		local row = self.rows[object]
		if not row then
			row = {}
			self.rows[object] = row
		end

		if row[key] == nil then
			row[key] = { object[key] }
		end
	end

	function self:capture(object)
		if seen[object] or object.ClassName == "Status" then
			return
		end

		seen[object] = true
		self:remember(object, "Parent")
		if object:IsA("JointInstance") and object.Enabled and object.Part0 and object.Part1 then
			self.joints[object.Part1] = self.joints[object.Part1] == nil and object or false
		end
		self.attributes[object] = object:GetAttributes()
		self.children[object] = {}
		for _, child in object:GetChildren() do
			self.children[object][child] = true
		end

		for class, keys in fields do
			if object:IsA(class) then
				for _, key in keys do
					self:remember(object, key)
				end
			end
		end

		if object:IsA("MeshPart") then
			local mesh = Instance.new("MeshPart")
			mesh:ApplyMesh(object)
			self.models[object] = { mesh = mesh }
			local editable = Geometry.mesh(object)
			if editable then
				self.geometry[editable] = Geometry.capture(editable)
			end
		elseif object:IsA("Model") then
			self.models[object] = { scale = object:GetScale() }
			self:remember(object, "WorldPivot")
		end
	end

	for _, rig in rigs do
		self.armatures[rig] = Armature.snapshot(rig)
		self:capture(rig)
		for _, object in Tree.rigDescendants(rig) do
			self:capture(object)
		end

		for _, motor in Properties.list(rig, true) do
			if
				not require("Objects").is(rig)
				and motor.PropertyId ~= "ApplyMesh"
				and not motor.Definition.trigger
				and motor.PropertyId ~= "CFrame"
				and motor.PropertyId ~= "Scale"
				and not rig:IsA("Model")
			then
				self:remember(
					rig,
					motor.PropertyId == "ApplyTexture" and "TextureID"
						or motor.PropertyId == "TimeOfDay" and "ClockTime"
						or motor.PropertyId
				)
			end
		end
	end

	for _, surface in surfaces or {} do
		self:capture(surface)
		self:remember(surface, "Parent")
	end

	for motor in raw.DefaultPose do
		if typeof(motor) == "table" then
			local values = { C0 = motor.C0 }
			if motor.IsEclipseArmatureControl then
				values.InputScale = motor.InputScale
			end

			self.virtual[motor] = values
		end
	end

	for _, name in { "poseWrite", "poseAttribute", "poseModel" } do
		self.hooks[name] = Dependencies[name]
	end

	local Faces = require("Faces")
	local faceApply = Faces.apply
	Faces.apply = function() end
	Dependencies.poseWrite = function(object, key, value)
		self:remember(object, key)
		return self.hooks.poseWrite(object, key, value)
	end

	Dependencies.poseAttribute = function(object, key, value)
		if not self.attributes[object] then
			self.attributes[object] = object:GetAttributes()
		end

		return self.hooks.poseAttribute(object, key, value)
	end

	Dependencies.poseModel = function(object, mode, value)
		self:capture(object)
		for _, child in Tree.rigDescendants(object) do
			self:capture(child)
		end

		return self.hooks.poseModel(object, mode, value)
	end

	local function jointFrame(part, visiting)
		local row = self.rows[part]
		if not row or not row.CFrame or visiting[part] then
			return nil
		end
		local joint = self.joints[part]
		if not joint then
			return row.CFrame[1]
		end
		local values = self.rows[joint]
		if not values or not values.Part0 or not values.Part0[1] then
			return nil
		end
		visiting[part] = true
		local parent = jointFrame(values.Part0[1], visiting)
		visiting[part] = nil
		return parent and parent * values.C0[1] * (values.Transform and values.Transform[1] or CFrame.identity) * values.C1[1]:Inverse()
	end

	function self:matches()
		for object, row in self.rows do
			for key, box in row do
				local ok, value = pcall(function()
					return object[key]
				end)
				if not ok then
					return false, object:GetFullName() .. "." .. key .. " could not be read"
				end

				local before = box[1]
				if value ~= before then
					if typeof(value) == "CFrame" and typeof(before) == "CFrame" then
						local tolerance = 1e-4
						if
							key == "WorldPivot"
							or key == "CFrame"
								and (object:IsA("BasePart") or object:IsA("Camera"))
						then
							local p, q = value.Position, before.Position
							local magnitude = math.max(
								math.abs(p.X),
								math.abs(p.Y),
								math.abs(p.Z),
								math.abs(q.X),
								math.abs(q.Y),
								math.abs(q.Z)
							)
							tolerance = math.max(tolerance, math.min(0.01, magnitude * 2 ^ -22))
						end

						local normalized, previous = value:Orthonormalize(), before:Orthonormalize()
						if
							(value.Position - before.Position).Magnitude > tolerance
							or normalized.LookVector:Dot(previous.LookVector) < 0.999999
							or normalized.UpVector:Dot(previous.UpVector) < 0.999999
						then
							local expected = key == "CFrame" and object:IsA("BasePart") and self.joints[object] and jointFrame(object, {})
							if expected then
								local canonical = expected:Orthonormalize()
								if (value.Position - expected.Position).Magnitude <= tolerance and normalized.LookVector:Dot(canonical.LookVector) >= 0.999999 and normalized.UpVector:Dot(canonical.UpVector) >= 0.999999 then
									continue
								end
							end
							return false, object:GetFullName() .. "." .. key .. " changed"
						end
					else
						return false, object:GetFullName() .. "." .. key .. " changed"
					end
				end
			end
		end

		return true
	end

	function self:restore()
		if self.closed then
			return
		end

		self.closed = true
		for name, fn in self.hooks do
			Dependencies[name] = fn
		end

		Faces.apply = faceApply
		local errors = {}

		local function attempt(fn)
			local ok, err = pcall(fn)
			if not ok then
				table.insert(errors, tostring(err))
			end
		end

		local ordered = {}
		for object in self.models do
			local depth, parent = 0, object.Parent
			while parent do
				depth += 1
				parent = parent.Parent
			end

			table.insert(ordered, { object = object, depth = depth })
		end

		table.sort(ordered, function(a, b)
			return a.depth < b.depth
		end)
		for _, entry in ordered do
			local object = entry.object
			local row = self.models[object]
			attempt(function()
				if row.mesh then
					object:ApplyMesh(row.mesh)
					row.mesh:Destroy()
				elseif object:GetScale() ~= row.scale then
					object:ScaleTo(row.scale)
				end
			end)
		end

		for motor, row in self.virtual do
			for key, value in row do
				attempt(function()
					motor[key] = value
				end)
			end
		end

		for rig, pose in self.armatures do
			attempt(function()
				assert(Armature.restore(rig, pose), "Could not restore imported rig inputs")
				Armature.evaluate(rig, true)
			end)
		end

		for mesh, data in self.geometry do
			attempt(function()
				Geometry.restore(mesh, data)
			end)
		end

		for object, row in self.rows do
			for key, value in row do
				if key ~= "CFrame" and key ~= "WorldPivot" then
					attempt(function()
						object[key] = value[1]
					end)
				end
			end
		end

		local parts, frames = {}, {}
		for object, row in self.rows do
			if row.CFrame then
				if object:IsA("BasePart") then
					table.insert(parts, object)
					table.insert(frames, row.CFrame[1])
				else
					attempt(function()
						object.CFrame = row.CFrame[1]
					end)
				end
			end
		end
		attempt(function()
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end)

		for object, row in self.rows do
			if row.WorldPivot then
				attempt(function()
					object.WorldPivot = row.WorldPivot[1]
				end)
			end
		end

		for object, attributes in self.attributes do
			local current = object:GetAttributes()

			for key in current do
				if key:sub(1, 4) ~= "RBX_" and attributes[key] == nil then
					attempt(function()
						object:SetAttribute(key, nil)
					end)
				end
			end

			for key, value in attributes do
				if key:sub(1, 4) ~= "RBX_" and current[key] ~= value then
					attempt(function()
						object:SetAttribute(key, value)
					end)
				end
			end
		end

		for object, children in self.children do
			for _, child in object:GetChildren() do
				if
					not children[child]
					and (
						child:GetAttribute("EclipseFaceCreated")
						or child:GetAttribute("EclipseEffectSurface")
					)
				then
					child:Destroy()
				end
			end
		end

		assert(#errors == 0, "Pose restoration failed: " .. table.concat(errors, "; "))
	end

	return self
end

return Snapshot
