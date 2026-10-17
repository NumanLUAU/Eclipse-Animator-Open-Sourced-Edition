--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Rig = require("Rig")
local Interp = require("Interp")
local Paths = require("Paths")
local Preview = {}

local function sample(keys, time)
	if not keys or #keys == 0 then
		return nil
	end

	local lo, hi = 1, #keys
	while lo <= hi do
		local mid = math.floor((lo + hi) * 0.5)
		if keys[mid].Time <= time then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end

	local before = keys[math.max(1, hi)]
	local after = keys[lo]
	if not after or before == after then
		return before.C0
	end

	return Interp.cframe(
		keys,
		before,
		after,
		math.clamp((time - before.Time) / (after.Time - before.Time), 0, 1),
		"C0"
	)
end

function Preview.attach(view, entry, data)
	local model = Rig.preview(entry.rig)
	local world = Instance.new("WorldModel")
	local camera = Instance.new("Camera")
	local ok, result = xpcall(function()
		world.Name = "PreviewWorld"
		world.Parent = view
		model.Parent = world
		camera.FieldOfView = 35
		camera.Parent = view
		view.CurrentCamera = camera
		local parts, bones, joints, incoming = {}, {}, {}, {}
		for _, object in model:GetDescendants() do
			local path = object:GetAttribute("EclipseLibraryPath")
			if object:IsA("BasePart") and path then
				parts[path] = object
			elseif object:IsA("Bone") and path then
				bones[path] = object
			elseif object:IsA("JointInstance") and object.Part0 and object.Part1 then
				object.Enabled = false
				local row = {
					joint = object,
					path = object.Part1:GetAttribute("EclipseLibraryPath"),
					rest = object:GetAttribute("EclipseLibraryRestC0") or object.C0,
				}
				table.insert(joints, row)
				incoming[object.Part1] = row
			end
		end

		local function depth(row, seen)
			if row.depth then
				return row.depth
			end

			seen = seen or {}
			if seen[row] then
				return 0
			end

			seen[row] = true
			local parent = incoming[row.joint.Part0]
			row.depth = parent and depth(parent, seen) + 1 or 0
			return row.depth
		end

		table.sort(joints, function(a, b)
			return depth(a) < depth(b)
		end)
		for path, values in data.appearance or {} do
			local object = Paths.resolve(model, path)
			if object then
				for key, value in values do
					object[key] = value
				end
			end
		end

		local self = {
			model = model,
			world = world,
			camera = camera,
			entry = entry,
			data = data,
			disposed = false,
		}

		function self:pose(time, animated)
			if self.disposed then
				return
			end

			for path, part in parts do
				local value = data.native[path]
				if value then
					part.CFrame = value.frame
					part.Size = value.size
				end
			end

			for path, bone in bones do
				local value = data.native[path]
				bone.Transform = value and value.transform or CFrame.identity
			end

			if animated then
				for _, row in joints do
					local joint = row.joint
					joint.Part1.CFrame = joint.Part0.CFrame
						* (sample(data.preview[row.path], time) or row.rest)
						* joint.C1:Inverse()
				end

				for path, bone in bones do
					local value = sample(data.preview[path], time)
					if value then
						bone.Transform = bone.CFrame:Inverse() * value
					end
				end
			end
		end

		self:pose(0, entry.kind == "Animations")
		local frame, size = model:GetBoundingBox()
		self.center = frame.Position
		self.radius = math.max(size.X, size.Y, size.Z, 1)

		function self:setCamera(values)
			if self.disposed then
				return
			end

			local aspect = math.max(0.1, view.AbsoluteSize.X / math.max(1, view.AbsoluteSize.Y))
			local distance = self.radius
				* 0.65
				/ math.tan(math.rad(camera.FieldOfView * 0.5))
				/ math.min(1, aspect)
			local position = self.center
				+ Vector3.new(values[1], self.radius * 0.12 + values[2], -distance + values[3])
			if (position - self.center).Magnitude < 0.05 then
				position += Vector3.new(0, 0, -0.1)
			end

			camera.CFrame = CFrame.lookAt(position, self.center)
		end

		self:setCamera(entry.camera or { 0, 0, 0 })

		function self:destroy()
			if self.disposed then
				return
			end

			self.disposed = true
			view.CurrentCamera = nil
			world:Destroy()
			camera:Destroy()
			self.data = nil
		end

		return self
	end, debug.traceback)
	if not ok then
		model:Destroy()
		world:Destroy()
		camera:Destroy()
		error(result, 0)
	end

	return result
end

return Preview
