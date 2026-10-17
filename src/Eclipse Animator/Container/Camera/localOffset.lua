--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Math = {}
local TURN_SENSITIVITY = math.rad(0.8)
local cameraFlagOK, cameraFlag = pcall(function() return settings():GetFFlag("NewCameraControls") end)
local smoothKeyboard = cameraFlagOK and cameraFlag == true

function Math.keyboardSpeed(shifted)
	local fallback = shifted and 0.2 or 0.5
	local ok, value = pcall(function()
		return settings().Studio[shifted and "Camera Shift Speed" or "Camera Speed"]
	end)
	if not ok or type(value) ~= "number" or value ~= value or value <= 0 or value >= 1e6 then
		value = fallback
	end
	return 60 * value
end

function Math.keyboardOffset(state, move, speed, dt, disableWASD, disableQE)
	dt = math.clamp(dt or 0, 0, 0.1)
	local velocity = state.keyboardVelocity or Vector3.zero
	local mask = Vector3.new(disableWASD and 0 or 1, disableQE and 0 or 1, disableWASD and 0 or 1)
	velocity *= mask
	move *= mask
	if move.Magnitude > 1 then
		move = move.Unit
	end

	local target = move * speed
	if not smoothKeyboard then
		state.keyboardVelocity = Vector3.zero
		return target * dt
	end

	local function axis(v, t)
		local time = t == 0 and 0.055 or 0.085
		local decay = math.exp(-dt / time)
		return t + (v - t) * decay, t * dt + (v - t) * time * (1 - decay)
	end

	local vx, dx = axis(velocity.X, target.X)
	local vy, dy = axis(velocity.Y, target.Y)
	local vz, dz = axis(velocity.Z, target.Z)
	state.keyboardVelocity = Vector3.new(vx, vy, vz) * mask
	if target.Magnitude == 0 and state.keyboardVelocity.Magnitude < 0.0001 then
		state.keyboardVelocity = Vector3.zero
	end

	return Vector3.new(dx, dy, dz) * mask
end

function Math.capture(camera, pivot, zoomScale)
	local explicit = pivot ~= nil
	local cf = camera.CFrame
	pivot = pivot or camera.Focus.Position
	local depth = (pivot - cf.Position):Dot(cf.LookVector)
	if depth < 0.00001 then
		depth = math.max(0.5, (camera.Focus.Position - cf.Position).Magnitude)
		if depth < 1 then
			depth = 12
		end

		if not explicit then
			pivot = cf.Position + cf.LookVector * depth
		end
	end

	return {
		frame = cf,
		reverse = if cf.UpVector.Y < 0 then -1 else 1,
		pivot = pivot,
		distance = math.max(0.05, (pivot - cf.Position).Magnitude),
		depth = depth,
		zoomScale = math.max(0.05, zoomScale or 4),
	}
end

function Math.zoomRay(pose, point, size, fov)
	local unit = 2 * math.tan(math.rad(fov) * 0.5) / math.max(1, size.Y)
	return (
		pose.frame.LookVector
		+ pose.frame.RightVector * (point.X - size.X * 0.5) * unit
		- pose.frame.UpVector * (point.Y - size.Y * 0.5) * unit
	).Unit
end

function Math.aimZoom(pose, direction, hit)
	local depth = (pose.pivot - pose.frame.Position):Dot(pose.frame.LookVector)
	if depth <= 0.05 then
		depth = math.max(0.5, pose.depth)
	end

	local point = hit
		or pose.frame.Position
			+ direction * (depth / math.max(0.00001, direction:Dot(pose.frame.LookVector)))
	pose.zoomPivot = point
	pose.distance = math.max(0.05, (point - pose.frame.Position).Magnitude)
	pose.depth = math.max(0.05, (point - pose.frame.Position):Dot(pose.frame.LookVector))
end

function Math.clearZoom(pose)
	if not pose.zoomPivot then
		return
	end

	pose.zoomPivot = nil
	pose.distance = math.max(0.05, (pose.pivot - pose.frame.Position).Magnitude)
	pose.depth = math.max(0.05, (pose.pivot - pose.frame.Position):Dot(pose.frame.LookVector))
end

function Math.lookView(frame, delta, sensitivity)
	local look = frame.LookVector
	local yaw = math.atan2(-look.X, -look.Z) - delta.X * sensitivity
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local limit = math.rad(81)
	pitch = math.clamp(pitch - delta.Y * sensitivity, -limit, limit)
	return CFrame.new(frame.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

function Math.rotateView(frame, delta, sensitivity, reverse, previousAxis)
	local right = frame.RightVector
	local horizon = Vector3.yAxis:Cross(-frame.LookVector)
	if horizon.Magnitude > 1e-5 then
		local alignment = horizon:Dot(previousAxis or right) / horizon.Magnitude
		if alignment < -1e-5 or math.abs(alignment) <= 1e-5 and right.Y < 0 then
			horizon = -horizon
		end

		local pole = math.asin(math.clamp(math.abs(frame.LookVector.Y), 0, 1)) / (math.pi * 0.5)
		local blended = horizon:Lerp(right, pole * pole)
		if blended.Magnitude > 1e-5 then
			right = blended.Unit
		end
	end

	local direction = reverse or (if frame.UpVector.Y < 0 then -1 else 1)
	local yaw = CFrame.fromAxisAngle(Vector3.yAxis, -delta.X * sensitivity * direction)
	local pitch = CFrame.fromAxisAngle(right, -delta.Y * sensitivity)
	return (CFrame.new(frame.Position) * yaw * pitch * frame.Rotation):Orthonormalize(),
		yaw:VectorToWorldSpace(right)
end

function Math.move(pose, delta, pan, viewportHeight, fov, panSensitivity, orbitSensitivity)
	if delta.Magnitude == 0 then
		return pose.frame, CFrame.new(pose.pivot)
	end

	Math.clearZoom(pose)
	if pan then
		local unit = 2
			* pose.depth
			* math.tan(math.rad(fov) * 0.5)
			/ math.max(1, viewportHeight)
			* (panSensitivity or 1)
		local offset = (-pose.frame.RightVector * delta.X + pose.frame.UpVector * delta.Y) * unit
		pose.pivot += offset
		pose.frame += offset
	else
		pose.reverse = pose.reverse or (if pose.frame.UpVector.Y < 0 then -1 else 1)
		local before = pose.frame
		local after, axis = Math.rotateView(
			before,
			delta,
			TURN_SENSITIVITY * (orbitSensitivity or 1),
			pose.reverse,
			pose.pitchAxis
		)
		pose.pitchAxis = axis
		local rotation = after.Rotation * before.Rotation:Inverse()
		pose.frame = CFrame.new(
			pose.pivot + rotation:VectorToWorldSpace(before.Position - pose.pivot)
		) * after.Rotation
	end

	return pose.frame, CFrame.new(pose.pivot)
end

function Math.setDistance(pose, distance)
	distance = math.clamp(distance, 0.05, 1000000)
	local ratio = distance / pose.distance
	local center = pose.zoomPivot or pose.pivot
	pose.frame = CFrame.new(center + (pose.frame.Position - center) * ratio) * pose.frame.Rotation
	pose.depth *= ratio
	pose.distance = distance
end

local function zoomGain(pose, distance)
	local depth = pose.depth * distance / pose.distance

	return math.clamp(depth / (depth + (pose.zoomScale or 4) * 0.65), 0.22, 1)
end

function Math.zoom(pose, steps)
	Math.setDistance(pose, pose.distance * 1.2 ^ -steps)
end

function Math.smoothZoom(pose, target, dt)
	local previousFrame = pose.frame
	local nextDistance = target + (pose.distance - target) * math.exp(-24 * math.max(0, dt))
	local settled = math.abs(nextDistance - target) <= math.max(0.000001, target * 0.0001)
	Math.setDistance(pose, if settled then target else nextDistance)
	if not settled and dt > 0 and pose.frame == previousFrame then
		Math.setDistance(pose, target)
		settled = true
	end

	return settled
end

function Math.zoomDrag(pose, startDistance, startY, deltaY)
	local exponent = 2 * zoomGain(pose, startDistance) * deltaY / math.max(5, startY + 5)
	Math.setDistance(pose, startDistance * math.exp(math.clamp(exponent, -50, 50)))
end

function Math.wrap(point, size)
	return Vector2.new(point.X % math.max(1, size.X), point.Y % math.max(1, size.Y))
end

return Math
