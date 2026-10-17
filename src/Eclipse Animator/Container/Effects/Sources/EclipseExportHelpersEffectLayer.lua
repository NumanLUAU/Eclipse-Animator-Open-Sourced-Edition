--!nocheck
--// cracked by numan

return function(require)
	local Run = game:GetService("RunService")
	local Layer = {}
	local carriers = {}

	local function key(part)
		local id = part:GetAttribute("EclipseExportId")
		if not id then
			return part
		end
		local top = part
		while top.Parent and top.Parent ~= workspace do
			top = top.Parent
		end
		return `{top.Name}/{id}`
	end

	local function surfaces(object)
		local found = {}
		for _, surface in object:GetChildren() do
			if surface:IsA("SurfaceGui") and surface:GetAttribute("EclipseEffectSurface") then
				table.insert(found, surface)
			end
		end
		return found
	end

	local function detach(part)
		for _, surface in surfaces(part) do
			surface.Adornee = nil
		end
	end


	local function sweep(proxy)
		if proxy:GetAttribute("EclipseSweeping") then
			return
		end
		proxy:SetAttribute("EclipseSweeping", true)
		task.spawn(function()
			Run.RenderStepped:Wait()
			Run.RenderStepped:Wait()
			if proxy.Parent then
				for _, surface in proxy:GetChildren() do
					if surface:GetAttribute("EclipseStaleSurface") then
						surface:Destroy()
					end
				end
			end
			proxy:SetAttribute("EclipseSweeping", nil)
		end)
	end

	function Layer.cleanupStale()
		local camera = workspace.CurrentCamera
		if camera then
			for _, part in camera:GetChildren() do
				if part:GetAttribute("EclipseEffectLayerProxy") then
					part:Destroy()
				end
			end
		end
		table.clear(carriers)
	end

	function Layer.keep(part)
		local proxy = carriers[key(part)]
		if not proxy or not proxy.Parent then
			return
		end
		for _, surface in surfaces(part) do
			surface:SetAttribute("EclipseStaleSurface", true)
			surface.Adornee = proxy
			surface.Parent = proxy
		end
	end

	function Layer.clear(part)
		local id = key(part)
		local proxy = carriers[id]
		carriers[id] = nil
		detach(part)
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
		if not camera or not part:IsDescendantOf(workspace) then
			Layer.clear(part)
			return
		end
		if not enabled then
			detach(part)
			return
		end
		local view, fov = require("./CameraProjection").viewing(camera)
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
			detach(part)
			return
		end
		local id = key(part)
		local proxy = carriers[id]
		if not proxy or not proxy.Parent then
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
			carriers[id] = proxy
		end
		proxy.Parent = camera
		proxy.Size = size
		proxy.CFrame = cf
		local stale = false
		for _, surface in proxy:GetChildren() do
			if surface:GetAttribute("EclipseStaleSurface") then
				stale = true
				break
			end
		end
		for _, surface in surfaces(part) do
			surface.Adornee = proxy
			surface.ZOffset = z
			surface.AlwaysOnTop = depth == nil
			surface.MaxDistance = 0
		end
		if stale then
			sweep(proxy)
		end
	end

	return Layer
end
