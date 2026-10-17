--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Layer = {}
local carriers = setmetatable({}, { __mode = "k" })
local destroying = setmetatable({}, { __mode = "k" })

function Layer.cleanupStale()
	local camera = workspace.CurrentCamera
	if camera then
		for _, part in camera:GetChildren() do
			if part:GetAttribute("EclipseEffectLayerProxy") then
				part:Destroy()
			end
		end
	end
end

function Layer.clear(part)
	local proxy = carriers[part]
	carriers[part] = nil
	local connection = destroying[part]
	destroying[part] = nil
	if connection then
		connection:Disconnect()
	end

	for _, surface in part:GetChildren() do
		if surface:IsA("SurfaceGui") and surface:GetAttribute("EclipseEffectSurface") then
			surface.Adornee = nil
		end
	end

	if proxy then
		proxy:Destroy()
	end
end

function Layer.project(cf, size, view, z, authoredView, authoredFov, renderFov, planar, depth, widthScale)
	local localCF = (authoredView or view):ToObjectSpace(cf)
	if localCF.Z >= -0.01 then
		return nil
	end

	local distance = depth and math.max(0.05, depth) or 100 - math.clamp(z, -100, 100) * 0.4
	local factor = distance / -localCF.Z

	local function dimensions(scale)
		local result = size * scale * Vector3.new(widthScale or 1, 1, 1)
		if
			planar
			and math.abs(localCF.LookVector.X) < 1e-5
			and math.abs(localCF.LookVector.Y) < 1e-5
		then
			result = Vector3.new(result.X, result.Y, 0.001)
		end

		return result
	end

	if authoredView then
		factor *= math.tan(math.rad(renderFov) * 0.5) / math.tan(math.rad(authoredFov) * 0.5)
		return view
			* CFrame.new(localCF.X * factor, localCF.Y * factor, -distance)
			* localCF.Rotation,
			dimensions(factor)
	end

	return view * CFrame.new(localCF.Position * factor) * localCF.Rotation, dimensions(factor)
end

function Layer.update(part, enabled, z, planar, depth, referenceAspect)
	local camera = workspace.CurrentCamera
	if not enabled or not camera or not part:IsDescendantOf(workspace) then
		Layer.clear(part)
		return
	end

	local view, fov = require("fov").viewing(camera)
	local cf, size = Layer.project(
		part.CFrame,
		part.Size,
		camera.CFrame,
		z,
		view,
		fov,
		camera.FieldOfView,
		planar, depth, referenceAspect and math.max(1, camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y) / referenceAspect) or 1
	)
	if not cf then
		Layer.clear(part)
		return
	end

	local proxy = carriers[part]
	if not proxy or not proxy.Parent then
		local previous = destroying[part]
		if previous then
			previous:Disconnect()
			destroying[part] = nil
		end

		proxy = Instance.new("Part")
		proxy.Name = "EclipseEffectLayer"
		proxy:SetAttribute("EclipseEffectLayerProxy", true)
		proxy.Anchored = true
		proxy.Transparency = 1
		proxy.CanCollide = false
		proxy.CanTouch = false
		proxy.CanQuery = false
		proxy.Locked = true
		proxy.CastShadow = false
		proxy.Archivable = false
		carriers[part] = proxy
		destroying[part] = part.Destroying:Once(function()
			Layer.clear(part)
		end)
	end

	proxy.Parent = camera
	proxy.Size = size
	proxy.CFrame = cf
	for _, surface in part:GetChildren() do
		if surface:IsA("SurfaceGui") and surface:GetAttribute("EclipseEffectSurface") then
			surface.Adornee = proxy
			surface.ZOffset = z
			surface.AlwaysOnTop = depth == nil
			surface.MaxDistance = 0
		end
	end
end

return Layer
