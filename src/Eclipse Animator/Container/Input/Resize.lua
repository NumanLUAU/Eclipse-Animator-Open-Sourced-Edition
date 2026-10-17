--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tracks = require("Properties")
local Document = require("Document")
local History = require("History")
local Scale = {}
local meshSizes = setmetatable({}, { __mode = "k" })

function Scale.prepare(mesh)
	if not mesh:IsA("SpecialMesh") or mesh.MeshType ~= Enum.MeshType.FileMesh then
		return
	end

	local id = mesh.MeshId
	if meshSizes[mesh] and meshSizes[mesh].id == id then
		return
	end

	local result = { id = id }
	meshSizes[mesh] = result
	if id == "" then
		return
	end

	local ok, size = pcall(function()
		local proxy = game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri(id))
		local value = proxy.MeshSize
		proxy:Destroy()
		return value
	end)
	if ok and size.Magnitude > 0 then
		result.size = size
	end
end

function Scale.syncBones(state, target)
	if not state.Rig or not state.getAllRigs then
		return
	end

	for _, rig in state.getAllRigs() do
		if target == rig or target:IsDescendantOf(rig) then
			state.Rig:UpdateBonesFollowRig(rig)
		end
	end
end

function Scale.bounds(rig)
	if rig:IsA("DataModelMesh") then
		local part = rig:FindFirstAncestorWhichIsA("BasePart")
		local cached = meshSizes[rig]
		local size = cached and cached.id == rig.MeshId and cached.size or part.Size
		return part.CFrame * CFrame.new(rig.Offset), size * rig.Scale
	end

	if rig:IsA("Attachment") then
		return rig.WorldCFrame, Vector3.one * 0.2
	end

	if rig:IsA("Model") then
		return rig:GetBoundingBox()
	end

	return rig.CFrame, rig.Size
end

function Scale.resolve(saved, distance, symmetric, uniform)
	local axis = saved.axis
	local extent = math.max(0.001, saved.size[axis])
	local delta = distance * ((symmetric or uniform) and 2 or 1)
	local ratio = math.max(0.001 / extent, 1 + delta / extent)
	local value
	if typeof(saved.value) == "number" then
		value = math.clamp(saved.value * ratio, 0.001, 10000)
		ratio = value / saved.value
	elseif uniform then
		local minimum = math.min(saved.value.X, saved.value.Y, saved.value.Z)
		ratio = math.max(0.001 / math.max(0.001, minimum), ratio)
		value = saved.value * ratio
	else
		local v = saved.value
		local component = math.max(0.001, v[axis] * ratio)
		ratio = component / math.max(0.001, v[axis])
		value = Vector3.new(
			axis == "X" and component or v.X,
			axis == "Y" and component or v.Y,
			axis == "Z" and component or v.Z
		)
	end

	local amount = (symmetric or uniform) and 0 or extent * (ratio - 1) * 0.5 * saved.sign
	local localOffset = (
		axis == "X" and Vector3.xAxis
		or axis == "Y" and Vector3.yAxis
		or Vector3.zAxis
	) * amount
	return value, saved.cf:VectorToWorldSpace(localOffset)
end

function Scale.captureProperty(motor, raw)
	local rig = motor.Rig
	local id = rig:IsA("DataModelMesh") and "Offset" or "CFrame"
	return {
		id = id,
		value = Tracks.readValue(rig, id),
		snapshot = Tracks.snapshot(rig, raw, true),
	}
end

function Scale.placeProperty(motor, saved, offset)
	local rig = motor.Rig
	local placement = saved.placement
	if rig:IsA("DataModelMesh") then
		local part = rig:FindFirstAncestorWhichIsA("BasePart")
		rig.Offset = placement.value + part.CFrame:VectorToObjectSpace(offset)
	elseif rig:IsA("Model") then
		local current = rig:GetBoundingBox()
		rig:PivotTo(rig:GetPivot() + saved.cf.Position + offset - current.Position)
	else
		rig.CFrame = placement.value + offset
	end
end

function Scale.finishProperty(refs, saved, cancel)
	local motor, rig = saved.motor, saved.motor.Rig
	local timeline, raw = refs.State.Timeline, refs.State.Timeline:GetState()
	local value = Tracks.readValue(rig, motor.PropertyId)
	local placement = saved.placement
	local position = Tracks.readValue(rig, placement.id)

	local function writePose(size, pose)
		Tracks.setValue(motor, size)
		if placement.id == "Offset" then
			rig.Offset = pose
		elseif rig:IsA("Model") then
			rig:PivotTo(pose)
		else
			rig.CFrame = pose
		end

		Scale.syncBones(refs.State, rig)
	end

	if cancel then
		writePose(saved.value, placement.value)
		return
	end

	if value == saved.value and position == placement.value then
		return
	end

	local before = placement.snapshot

	local function setDefault(track, v)
		track.Part1:SetAttribute("Default", Document.pack(v))
		raw.DefaultPose[track] = Tracks.encode(v)
	end

	local function record(track, v, frame)
		timeline:RecordKeyframeForMotorAtCurrentTime(
			track.Part1,
			track,
			Tracks.encode(v),
			{ Frame = frame, PropertyValue = v },
			refs.State.UIHelpers.SanitizeName
		)
	end

	local moved = position ~= placement.value
	local positionTrack
	if moved then
		writePose(saved.value, placement.value)
		positionTrack = Tracks.enable(rig, placement.id, true, raw)
		if
			timeline:IsRecording()
			and saved.frame > 0
			and not next(raw.Keyframes[positionTrack] or {})
		then
			record(positionTrack, placement.value, 0)
		end

		writePose(value, position)
	end

	if timeline:IsRecording() then
		if saved.frame > 0 and not next(raw.Keyframes[motor] or {}) then
			record(motor, saved.value, 0)
		end

		record(motor, value, saved.frame)
		if positionTrack then
			record(positionTrack, position, saved.frame)
		end
	else
		setDefault(motor, value)
		if positionTrack then
			setDefault(positionTrack, position)
		end
	end

	local after = Tracks.snapshot(rig, raw, true)

	local function restore(snapshot, size, pose)
		if not rig.Parent then
			return
		end

		local wanted = {}
		for _, row in snapshot.tracks do
			wanted[row.id] = true
		end

		for _, track in Tracks.list(rig, true) do
			if not wanted[track.PropertyId] then
				timeline:_restoreMotorBucket(track, {})
			end
		end

		Tracks.restore(rig, snapshot, timeline, refs.State.UIHelpers.SanitizeName)
		writePose(size, pose)
		refs.State.currentProjectSaved = false
		if refs.RefreshStructure then
			refs.RefreshStructure()
		end
	end

	History.record(function()
		restore(before, saved.value, placement.value)
	end, function()
		restore(after, value, position)
	end, "Scale " .. rig.Name, timeline:IsRecording() and saved.frame or nil)
	require("HumanoidScale").propertyChanged(motor, saved.value, value)
	refs.State.currentProjectSaved = false
	if moved and refs.RefreshStructure then
		refs.RefreshStructure()
	end
end

return Scale
