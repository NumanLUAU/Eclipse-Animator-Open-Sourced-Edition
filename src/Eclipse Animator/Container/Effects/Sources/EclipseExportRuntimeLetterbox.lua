--!nocheck
--// cracked by numan

return function(require)
	local Letterbox = {}

	function Letterbox.new(data, objects, sample)
		local tracks = {}
		for _, track in data.Tracks do
			if track.Kind == "Property" then
				tracks[track.Target] = tracks[track.Target] or {}
				tracks[track.Target][track.Property] = track
			end
		end
		local cameras = {}
		for _, root in data.Roots do
			if root.Kind == "Camera" and objects[root.Id] then
				table.insert(cameras, objects[root.Id])
			end
		end
		local entries = {}
		for _, id in data.Effects do
			local model = objects[id]
			if not model or model:GetAttribute("EffectKind") ~= "Letterbox" then
				continue
			end
			local binding = data.EffectCameras and data.EffectCameras[id]
			if
				not binding
				and data.CameraMode == "Authored"
				and #cameras == 1
				and cameras[1]:GetAttribute("EclipseTrackId")
					== model:GetAttribute("EffectCameraId")
			then
				binding =
					{ Target = tracks.Projection and "Projection" or "Camera", Selected = true }
			end
			local cameraTracks = binding and tracks[binding.Target]
			local view = cameraTracks and (cameraTracks.View or cameraTracks.CFrame)
			local fov = cameraTracks and (cameraTracks.FOV or cameraTracks.FieldOfView)
			if not view or not fov then
				continue
			end
			local follow
			for _, track in data.Tracks do
				if
					track.Target == id
					and track.Kind == "Attribute"
					and track.Property == "EffectFollowFOV"
				then
					follow = track
				end
			end
			for _, part in model:GetDescendants() do
				local channels = tracks[part:GetAttribute("EclipseExportId")]
				if part:IsA("BasePart") and channels and channels.CFrame then
					table.insert(entries, {
						part = part,
						model = model,
						transform = channels.CFrame,
						view = view,
						fov = fov,
						follow = follow,
						selected = binding.Selected,
					})
				end
			end
		end
		local function value(track, frame)
			return sample(track.Samples, frame, track.Smooth ~= false)
		end
		local function tangent(fov)
			return math.tan(math.rad(math.clamp(fov, 1, 120)) * 0.5)
		end
		local function follows(entry, frame)
			if entry.follow then
				return value(entry.follow, frame) ~= false
			end
			return entry.model:GetAttribute("EffectFollowFOV") ~= false
		end
		local function relative(entry, frame, normalize)
			local cf = value(entry.view, frame):ToObjectSpace(value(entry.transform, frame))
			if normalize then
				cf = CFrame.new(cf.X, cf.Y, cf.Z * tangent(value(entry.fov, frame))) * cf.Rotation
			end
			return cf
		end
		return function(frame, interpolate, camera, projection)
			local first = math.floor(frame)
			local last = math.min(first + 1, data.LastFrame)
			local alpha = interpolate and frame - first or 0
			for _, entry in entries do
				local normalize = follows(entry, first) and follows(entry, last)
				local cf = relative(entry, first, normalize)
				if alpha > 0 then
					cf = cf:Lerp(relative(entry, last, normalize), alpha)
				end
				local view = value(entry.view, interpolate and frame or first)
				local fov = value(entry.fov, interpolate and frame or first)
				if entry.selected and camera then
					if projection.Enabled then
						view = projection.View
						fov = projection.FOV
					else
						view = camera.CFrame
						fov = camera.FieldOfView
					end
				end
				if normalize then
					cf = CFrame.new(cf.X, cf.Y, cf.Z / tangent(fov)) * cf.Rotation
				end
				entry.part.CFrame = view * cf
			end
		end
	end

	return Letterbox
end
