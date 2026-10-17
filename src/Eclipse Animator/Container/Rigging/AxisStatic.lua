--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local BlenderEdit = require("BlenderEdit")
local Theme = require("Theme")
local PivotSpace = require("PivotSpace")
local CameraRig = require("CameraRig")
local CameraTarget = require("Target")
local CameraDisplay = require("CameraDisplay")
local LimbControls = require("LimbControls")
local LimbIK = require("LimbIK")
local RotationInput = require("RotationInput")
local RotationCursor = require("RotateCursor")
local Preferences = require("Preferences")
local PresentationState = require("State")
local PoseCache = require("cache")
local TimelineRaw = require("RawState").Timeline
local Axis = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = require("UserInputService")

local MotorMath = require("MotorMath")
local BoneMotor = require("BoneMotor")
local ArmatureRuntime = require("ArmatureRuntime")
local ArmatureImport = require("ArmatureImport")

local function interactiveC0(motor, value)
	return typeof(motor) == "table"
			and motor.IsEclipseArmatureControl
			and ArmatureRuntime.constrainC0(motor, value)
		or value
end

local function captureMotorSnapshot(motor, rig)
	local imported = typeof(motor) == "table" and motor.IsEclipseArmatureControl
	local edit = imported and ArmatureRuntime.captureEdit(motor) or nil
	local c0 = edit and edit.c0 or motor.C0
	local bridge = edit and edit.bridge or motor.Part0.CFrame
	return {
		motor = motor,
		rig = edit and edit.rig or rig,
		startC0 = c0,
		startC1 = motor.C1,
		startWorldCF = edit and edit.world or bridge * c0,
		startPart0CF = bridge,
		startScale = edit and edit.scale or nil,
		edit = edit,
		rotationPivot = edit and edit.world.Position
			or PivotSpace.world(motor)
			or (bridge * c0).Position,
		rotationFrame = edit and edit.world.Rotation
			or motor.Part1 and motor.Part1.CFrame.Rotation
			or (bridge * c0).Rotation,
		individualRotation = Preferences.get("IndividualRotationPivots") ~= false,
	}
end

local function applySnapshotWorld(info, targetWorld)
	local motor = info.motor
	if info.edit then
		local value = ArmatureRuntime.solveEditC0(motor, targetWorld, info.edit)
		if value then
			motor.C0 = value
		end

		ArmatureRuntime.evaluate(info.rig)
	else
		info.targetWorldCF = targetWorld * motor.C1:Inverse()
		if info.manipulationSnapshot then
			info.manipulationSnapshot.targetWorldCF = info.targetWorldCF
		end

		motor.C0 = interactiveC0(motor, motor.Part0.CFrame:ToObjectSpace(targetWorld))
	end
end

local function linkRotationSnapshots(snapshots, map)
	map = map or {}
	local selected, rigs = {}, {}
	for _, info in snapshots do
		selected[info.motor] = info
		if info.rig and not rigs[info.rig] then
			rigs[info.rig] = true
			for part, motor in MotorMath.buildMotorByPart1(info.rig) do
				map[part] = motor
			end
		end
	end

	for _, info in snapshots do
		info.rotationParent, info.rotationDepth, info.rotationDelta = nil, 0, nil
		local motor, seen = info.motor, {}
		while motor and not seen[motor] and motor:GetAttribute("TrackParent") ~= false do
			seen[motor] = true
			local parent = map[typeof(motor) == "table" and motor.RealPart0 or motor.Part0]
			if parent == info.motor then
				break
			end

			if not info.rotationParent then
				info.rotationParent = selected[parent]
			end

			if parent then
				info.rotationDepth += 1
			end

			motor = parent
		end
	end

	table.sort(snapshots, function(a, b)
		return a.rotationDepth < b.rotationDepth
	end)
end

local function rotatedSnapshot(info, rotation, groupPivot, multiple, localRotation)
	local pivot = groupPivot
	if multiple and info.individualRotation then
		pivot = info.rotationPivot
		if localRotation then
			rotation = info.rotationFrame * localRotation * info.rotationFrame:Inverse()
		end
	end

	local target = CFrame.new(pivot) * rotation * CFrame.new(-pivot) * info.startWorldCF
	local parentDelta = multiple
			and info.individualRotation
			and info.rotationParent
			and info.rotationParent.rotationDelta
		or CFrame.identity
	info.rotationDelta = parentDelta * target * info.startWorldCF:Inverse()

	return info.edit and target or parentDelta * target
end

local function finiteNumber(value)
	return value == value and math.abs(value) < math.huge
end

local function finiteVector(value)
	return value
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and (typeof(value) == "Vector2" or finiteNumber(value.Z))
end

local AXIS_MIN_DISTANCE = 10
local AXIS_MAX_DISTANCE = 120
local AXIS_MIN_SCALE = 0.9
local AXIS_MAX_SCALE = 5.5
local SCORE_ROTATE_SENSITIVITY = 0.01
local ROTATE_DRAG_SENSITIVITY = 0.012
local CONE_CFRAME_BACK_MULT = 0.5
local CONE_CLOSE_FORWARD_DISTANCE = 0.73
local CONE_CLOSE_FORWARD_END = 28

local AXIS_PART_TRANSPARENCY = 1

local ADORNMENT_TRANSPARENCY_DEFAULT = 0.2
local ADORNMENT_TRANSPARENCY_HOVER = 0
local ADORNMENT_TRANSPARENCY_SELECTED = 0
local TRACKBALL_TRANSPARENCY = 0.82

local axisPartToAdornments = {}

local POS_ADORNMENT_SCALE = 0.5
local ROT_ADORNMENT_SCALE = 0.5

local AXIS_NAMES = {
	ViewRot = true,
	XRot = true,
	YRot = true,
	ZRot = true,
	SCore = true,
	["+X"] = true,
	["-X"] = true,
	["+Y"] = true,
	["-Y"] = true,
	["+Z"] = true,
	["-Z"] = true,
	["X"] = true,
	["Y"] = true,
	["Z"] = true,
	PlaneXY = true,
	PlaneXZ = true,
	PlaneYZ = true,
}

local GUIDE_LINE_COLOR = Color3.fromRGB(255, 255, 255)
local GUIDE_LINE_TRANSPARENCY = 0.1
local GUIDE_LINE_LENGTH = 2048
local GUIDE_AXIS_COLORS = {
	X = Color3.fromRGB(255, 88, 88),
	Y = Color3.fromRGB(92, 220, 92),
	Z = Color3.fromRGB(92, 140, 255),
}

local TweenInfo_BoneFade = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local activeAxis = nil
local cachedAxes = {}
local cachedAxisData = {}
local activeAxisPart = nil
local selectedBone = nil
local selectedMotor = nil
local propertyBone, propertyMotor, propertySource
local selectedBones = {}
local axisOriginalTransparency = {}
local axisAdornmentBaseData = {}

local function redrawRotationWire(adornment)
	local data = axisAdornmentBaseData[adornment]
	if data and data.points then
		local camera = data.camera or workspace.CurrentCamera
		local frame = adornment.Adornee.CFrame * adornment.CFrame
		local cameraLocal = frame:PointToObjectSpace(camera.CFrame.Position)
		data.lines = data.lines or {}
		for i = 1, #data.points - 1 do
			local line = data.lines[i]
			if not line or not line.Parent then
				line = Instance.new("BoxHandleAdornment")
				line.Name = "BlenderRotationSegment"
				line.AlwaysOnTop = true
				pcall(function()
					line.Shading = Enum.AdornShading.AlwaysOnTop
				end)
				line.AdornCullingMode = Enum.AdornCullingMode.Never
				line.Parent = adornment.Parent
				data.lines[i] = line
			end

			local a, b = data.points[i], data.points[i + 1]
			line.Adornee = adornment.Adornee
			local center = (a + b) * 0.5
			local facing = cameraLocal - center
			local tangent = (b - a).Unit
			if tangent:Cross(facing).Magnitude < 1e-6 then
				facing = frame:VectorToObjectSpace(camera.CFrame.UpVector)
			end

			line.CFrame = adornment.CFrame * CFrame.lookAt(center, b, facing)
			local depth = -camera.CFrame:PointToObjectSpace(frame:PointToWorldSpace(center)).Z
			local pixel = 2
				* math.max(0.01, depth)
				* math.tan(math.rad(camera.FieldOfView) * 0.5)
				/ math.max(1, camera.ViewportSize.Y)
			line.Size = Vector3.new(pixel * adornment.Thickness, pixel * 0.01, (b - a).Magnitude)
			line.ZIndex = adornment.ZIndex
			line.Color3 = adornment.Color3
			line.Transparency = adornment.Transparency
			line.Visible = adornment.Visible
		end

		for i = #data.points, #data.lines do
			data.lines[i].Visible = false
		end
	end
end

local axisBaseData = {}
local holdingAxis = false
local blenderGrabMode = false

local blenderRotateMode = false
local blenderRotateTrackball = false
local axisSpace = "Local"

local rotateData = {
	startMouse = nil,
	startMotorC0 = nil,
	startMotorC1 = nil,
	motor = nil,
	bone = nil,
	pivotPos = nil,
	screenCenter = nil,
	startScreenVector = nil,
	startCameraCF = nil,
}

local axisRenderConnection = nil

local grabData = {
	startMouse = nil,
	startMotorC0 = nil,
	startMotorC1 = nil,
	motor = nil,
	bone = nil,
	pivotPos = nil,
	depth = nil,
}

local dragData = {
	startMouse = nil,
	startTransform = nil,
	motor = nil,
	axisDir = nil,
	mode = nil,
	worldAxisDir = nil,
	pivotPos = nil,
	startProj = nil,
	startMotorC0 = nil,
	startMotorC1 = nil,
	bone = nil,
	startVec = nil,
	isSpinCore = false,
	startCameraCF = nil,

	screenCenter = nil,
	screenHandle = nil,
	screenTangent = nil,

	planeNormal = nil,
	startPlaneVector = nil,

	tangent = nil,
	bitangent = nil,
	startPlaneVector2D = nil,
}

local currentRig = nil
local manipulationSnapshots = nil
local manipulationArmatureSnapshot = nil
local manipulationRig = nil
local manipulationRigSnapshots = nil
local manipulationIKSnapshots = nil

local function captureManipulation(snapshots)
	manipulationSnapshots = snapshots
	if
		snapshots
		and snapshots[1]
		and typeof(snapshots[1].motor) == "table"
		and snapshots[1].motor.IsEclipsePropertyGizmo
	then
		manipulationRig = nil
		manipulationArmatureSnapshot = nil
		manipulationRigSnapshots = {}
		manipulationIKSnapshots = {}
		return
	end

	manipulationRig = currentRig
	manipulationArmatureSnapshot = currentRig and ArmatureRuntime.snapshot(currentRig) or nil
	manipulationRigSnapshots = {}
	manipulationIKSnapshots = {}
	if currentRig then
		manipulationIKSnapshots[currentRig] = LimbIK.snapshot(currentRig)
	end

	if manipulationArmatureSnapshot then
		manipulationRigSnapshots[currentRig] = manipulationArmatureSnapshot
	end

	for _, info in ipairs(snapshots or {}) do
		local rig = info.rig
		if rig and not manipulationIKSnapshots[rig] then
			manipulationIKSnapshots[rig] = LimbIK.snapshot(rig)
		end

		if rig and not manipulationRigSnapshots[rig] then
			manipulationRigSnapshots[rig] = ArmatureRuntime.snapshot(rig)
		end
	end

	ArmatureRuntime.beginDeferredEdit(snapshots)
end

local GizmoMode = "Position"
local PositionAxis = nil
local RotationAxis = nil
local enabledCheck = nil
local playbackHidden = false
local markersHidden = false

local boneToMotorCache = setmetatable({}, { __mode = "k" })

local function getCamera()
	return workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")
end

local function getBonesFolderName(rig)
	if not rig then
		return "Bones"
	end

	return rig.Name .. "Bones"
end

local function getBonesFolder()
	local cam = getCamera()
	if not cam or not currentRig then
		return nil
	end

	return require("RigTraversal").bonesFolder(currentRig, cam)
end

local function getAllBonesFolders()
	local folders = {}
	local cam = getCamera()
	if not cam then
		return folders
	end

	local tree = require("RigTraversal")
	for _, rig in PresentationState.getAllRigs and PresentationState.getAllRigs() or {} do
		local folder = tree.bonesFolder(rig, cam)
		if folder then
			table.insert(folders, folder)
		end
	end

	return folders
end

local function getMouseAmountOnAxis(mousePos, axisPoint, axisDir)
	local camera = getCamera()
	if
		not camera
		or not finiteVector(mousePos)
		or not finiteVector(axisPoint)
		or not finiteVector(axisDir)
		or axisDir.Magnitude < 1e-6
	then
		return nil
	end

	axisDir = axisDir.Unit
	local facing = camera.CFrame.LookVector:Dot(axisDir)
	if math.abs(facing) > 0.98 then
		local center = camera:WorldToViewportPoint(axisPoint)
		if center.Z <= 0 then
			return nil
		end

		local unitsPerPixel = 2
			* center.Z
			* math.tan(math.rad(camera.FieldOfView * 0.5))
			/ math.max(1, camera.ViewportSize.Y)
		return (mousePos.Y - center.Y) * unitsPerPixel * (facing < 0 and 1 or -1)
	end

	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	if
		not finiteVector(ray.Origin)
		or not finiteVector(ray.Direction)
		or ray.Direction.Magnitude < 1e-6
	then
		return nil
	end

	local rayOrigin = ray.Origin
	local rayDir = ray.Direction.Unit
	axisDir = axisDir.Unit

	local w0 = rayOrigin - axisPoint
	local a = rayDir:Dot(rayDir)
	local b = rayDir:Dot(axisDir)
	local c = axisDir:Dot(axisDir)
	local d = rayDir:Dot(w0)
	local e = axisDir:Dot(w0)

	local denom = a * c - b * b
	if math.abs(denom) < 1e-5 then
		return nil
	end

	local amount = (a * e - b * d) / denom
	return finiteNumber(amount) and amount or nil
end

local function projectMouseToDepth(mousePos, depth)
	local camera = getCamera()
	if not camera or not finiteVector(mousePos) or not finiteNumber(depth) or depth <= 0 then
		return nil
	end

	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local normal = camera.CFrame.LookVector
	local denom = ray.Direction:Dot(normal)
	if not finiteNumber(denom) or denom < 1e-5 then
		return nil
	end

	local planePoint = camera.CFrame.Position + normal * depth
	local distance = (planePoint - ray.Origin):Dot(normal) / denom
	local point = ray.Origin + ray.Direction * distance
	return distance >= 0 and finiteVector(point) and point or nil
end

local function projectMouseToPlane(mousePos, planePoint, planeNormal)
	local camera = getCamera()
	if
		not camera
		or not finiteVector(mousePos)
		or not finiteVector(planePoint)
		or not finiteVector(planeNormal)
	then
		return nil
	end

	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local dir = ray.Direction
	local denom = dir:Dot(planeNormal)

	if not finiteNumber(denom) or math.abs(denom) < 1e-5 then
		return nil
	end

	local t = (planePoint - ray.Origin):Dot(planeNormal) / denom
	local point = ray.Origin + dir * t
	return t >= 0 and finiteVector(point) and point or nil
end

local function projectPointOntoPlane(point, planePoint, planeNormal)
	return point - planeNormal * (point - planePoint):Dot(planeNormal)
end

local function getMouseAxisPlaneVector(mousePos, planePoint, planeNormal)
	local hit = projectMouseToPlane(mousePos, planePoint, planeNormal)
	if not hit then
		return nil
	end

	local vec = projectPointOntoPlane(hit, planePoint, planeNormal) - planePoint
	if vec.Magnitude <= 1e-4 then
		return nil
	end

	return vec.Unit
end

local function rotationDragBasis(mouse, pivot, normal, radius)
	local vector = getMouseAxisPlaneVector(mouse, pivot, normal)
	local camera = getCamera()
	if vector and math.abs(camera.CFrame.LookVector:Dot(normal)) >= 0.15 then
		return vector
	end

	local center = camera:WorldToViewportPoint(pivot)
	local hit = projectMouseToDepth(mouse, center.Z)
	if not hit then
		return nil
	end

	local radial = projectPointOntoPlane(hit, pivot, normal) - pivot
	local view = camera.CFrame.LookVector
	local fallback = view - normal * view:Dot(normal)
	if radial.Magnitude <= 1e-4 then
		radial = fallback
	end

	if radial.Magnitude <= 1e-4 then
		return vector
	end

	local function projectedTangent(v)
		local tangent = normal:Cross(v.Unit)
		local point = camera:WorldToViewportPoint(pivot + tangent * radius)
		return Vector2.new(point.X - center.X, point.Y - center.Y)
	end

	local tangent = projectedTangent(radial)
	if tangent.Magnitude < 1 and fallback.Magnitude > 1e-4 then
		radial = fallback
		tangent = projectedTangent(radial)
	end

	if tangent.Magnitude < 1 then
		return vector
	end

	return radial.Unit, tangent.Unit, math.max(24, tangent.Magnitude)
end

local function signedAngleAroundAxis(fromVec, toVec, axis)
	local cross = fromVec:Cross(toVec)
	local sin = cross:Dot(axis)
	local cos = math.clamp(fromVec:Dot(toVec), -1, 1)
	return math.atan2(sin, cos)
end

local restoreTrackParentLockedDescendants = MotorMath.restoreTrackParentLockedDescendants

local function captureLockedDescendants(motor, movedSnapshots)
	if typeof(motor) == "table" and motor.IsEclipsePropertyGizmo then
		return {}
	end

	local rig = currentRig
	local part = motor and motor.Part1
	if part and not (rig and part:IsDescendantOf(rig)) then
		for _, candidate in PresentationState.getAllRigs and PresentationState.getAllRigs() or {} do
			if part:IsDescendantOf(candidate) then
				rig = candidate
				break
			end
		end
	end

	local result = {
		MotorByPart = {},
		MovedSnapshots = movedSnapshots and #movedSnapshots > 1 and movedSnapshots or nil,
	}
	local rigs = {}
	if rig then
		rigs[rig] = true
	end

	for _, info in movedSnapshots or {} do
		if info.rig then
			rigs[info.rig] = true
		end
	end

	for sourceRig in rigs do
		local map = MotorMath.buildMotorByPart1(sourceRig)
		local motors =
			MotorMath.buildLockedDescendantMotorList(sourceRig, motor, movedSnapshots, map)
		local captured = MotorMath.captureWorldCFForMotorList(motors, sourceRig, map)
		for part, joint in map do
			result.MotorByPart[part] = joint
		end

		for _, item in ipairs(captured) do
			table.insert(result, item)
		end
	end

	return result
end

local function getMotorForBone(bone)
	if bone and bone == propertyBone then
		return propertyMotor
	end

	local rigModule = PresentationState.Rig
	if not bone or not currentRig or not rigModule then
		return nil
	end

	local reference = bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
	local rig = reference and reference.Value or currentRig
	local control = LimbControls.getMotor(rig, bone)
	if control then
		return control
	end

	local part = rigModule:GetPartFromBone(rig, bone)
	local motor = part and rigModule:GetMotorForPart(rig, part)
	return motor and (LimbControls.getMotor(rig, bone, motor) or motor) or nil
end

local function precision(data, name, raw, factor, wrapped)
	data.precision = data.precision or {}
	local entry = data.precision[name] or { raw = raw * 0, value = raw * 0 }
	local delta = raw - entry.raw
	if wrapped then
		delta = math.atan2(math.sin(delta), math.cos(delta))
	end

	local slow = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	entry.value += delta * (slow and factor or 1)
	entry.raw = raw
	data.precision[name] = entry
	return entry.value
end

local function snapMoveAmount(value)
	if
		not (
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		)
	then
		return value
	end

	local fine = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local step = (Preferences.get("MoveSnapIncrement") or 1) * (fine and 0.1 or 1)
	return math.round(value / step) * step
end

local function rotationSnapStep()
	if not (
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	) then
		return nil
	end

	local fine = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	return math.rad(Preferences.get("RotationSnapIncrement") or 5) * (fine and 0.1 or 1)
end

local function snapRotationAmount(value)
	local step = rotationSnapStep()
	return step and math.round(value / step) * step or value
end

local function snapMoveVector(value, frame)
	if
		not (
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		)
	then
		return value
	end

	local localValue = frame and frame:VectorToObjectSpace(value) or value
	local snapped = Vector3.new(
		snapMoveAmount(localValue.X),
		snapMoveAmount(localValue.Y),
		snapMoveAmount(localValue.Z)
	)
	return frame and frame:VectorToWorldSpace(snapped) or snapped
end

local function trackballRotation(cameraCF, delta, sensitivity)
	local vector = (cameraCF.RightVector * delta.Y + cameraCF.UpVector * delta.X)
		* (SCORE_ROTATE_SENSITIVITY * (sensitivity or Preferences.get("TrackballSensitivity")))
	local magnitude = vector.Magnitude
	local angle = snapRotationAmount(magnitude)
	local snapped = magnitude > 1e-9 and vector * (angle / magnitude) or Vector3.zero
	return magnitude > 1e-9 and CFrame.fromAxisAngle(vector.Unit, angle) or CFrame.identity,
		snapped:Dot(cameraCF.UpVector),
		snapped:Dot(cameraCF.RightVector)
end

const selectionMotorMemo = { list = {} }

local function selectionMotors()
	local memo = selectionMotorMemo
	local rigModule = PresentationState.Rig
	local revision = PoseCache.revision()
	local time = TimelineRaw.CurrentTime
	local parts = rigModule and rigModule._partToMotorCache
	if
		memo.bones ~= selectedBones
		or memo.revision ~= revision
		or memo.time ~= time
		or memo.rig ~= currentRig
		or memo.module ~= rigModule
		or memo.parts ~= parts
	then
		memo.bones, memo.revision, memo.time = selectedBones, revision, time
		memo.rig, memo.module, memo.parts = currentRig, rigModule, parts
		table.clear(memo.list)
	end

	return memo.list
end

local function getSelectionCentroid(centerParts)
	if centerParts == nil then
		centerParts = false
	end

	if #selectedBones == 0 then
		return nil
	end

	local sum = Vector3.zero
	local count = 0
	local motors = selectionMotors()
	for index, bone in ipairs(selectedBones) do
		if bone and bone.Parent then
			local motor = motors[index]
			if motor == nil then
				motor = getMotorForBone(bone) or false
				motors[index] = motor
			end

			motor = motor or nil
			local pos
			if CameraRig.isTransform(motor) then
				pos = CameraRig.gizmoFrame(CameraRig.owner(motor)).Position
			elseif CameraTarget.is(motor) then
				pos = (motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()).Position
			elseif
				centerParts
				and typeof(motor) == "Instance"
				and motor:IsA("Motor6D")
				and motor.Part1
			then
				pos = motor.Part1.Position
			elseif motor and motor.Part0 then
				pos = PivotSpace.world(motor) or (motor.Part0.CFrame * motor.C0).Position
			else
				pos = bone.Position
			end

			sum += pos
			count += 1
		end
	end

	if count == 0 then
		return nil
	end

	return sum / count
end

local function getPrimaryPivotCFrame(centerParts)
	if centerParts == nil then
		centerParts = false
	end

	local primary = selectedBones[#selectedBones]
	if not primary or not primary.Parent then
		return nil
	end

	local motor = getMotorForBone(primary)
	if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
		local reference = primary.Parent:FindFirstChild("EclipseSourceRig")
		local rig = reference and reference.Value or currentRig
		ArmatureRuntime.evaluate(rig)
		local world = ArmatureRuntime.worldCFrame(motor.Part1, rig)
		if world then
			return world
		end
	end

	if CameraRig.isTransform(motor) then
		return CameraRig.gizmoFrame(CameraRig.owner(motor))
	end

	if CameraTarget.is(motor) then
		return CFrame.new((motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()).Position)
	end

	if motor and motor.Part0 then
		local joint = motor.Part0.CFrame * motor.C0
		if centerParts and typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part1 then
			return CFrame.new(motor.Part1.Position) * joint.Rotation
		end

		if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part1 then
			return CFrame.new(PivotSpace.world(motor) or joint.Position)
				* motor.Part1.CFrame.Rotation
		end

		return joint
	end

	return primary.CFrame
end

local function getGizmoPivotCFrame()
	local primaryCF = getPrimaryPivotCFrame(false)
	if not primaryCF then
		return nil
	end

	local position
	if #selectedBones <= 1 then
		position = primaryCF.Position
	else
		local centroid = getSelectionCentroid(false)
		position = centroid or primaryCF.Position
	end

	if axisSpace == "Global" then
		return CFrame.new(position)
	end

	return CFrame.new(position) * primaryCF.Rotation
end

local function collectTopLevelMotorSnapshots(rotation)
	if #selectedBones == 0 or not currentRig then
		return nil
	end

	local motorList = {}
	local motorSet = {}
	local motorRigs = {}
	for _, bone in ipairs(selectedBones) do
		local m = getMotorForBone(bone)
		if m and m.Part0 then
			table.insert(motorList, m)
			motorSet[m] = true
			local sourceRig = bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
			motorRigs[m] = sourceRig and sourceRig.Value or currentRig
		end
	end

	if #motorList < 1 then
		return nil
	end

	local motorByPart1 = MotorMath.buildMotorByPart1(currentRig)
	local mappedRigs = { [currentRig] = true }
	for _, rig in motorRigs do
		if not mappedRigs[rig] then
			mappedRigs[rig] = true
			for part, motor in MotorMath.buildMotorByPart1(rig) do
				motorByPart1[part] = motor
			end
		end
	end

	local snapshots = {}
	for _, m in ipairs(motorList) do
		local hasSelectedAncestor = false
		local parentPart = typeof(m) == "table" and m.RealPart0 or m.Part0
		local childMotor = m
		local steps = 0
		while parentPart and steps < 100 do
			steps += 1

			if childMotor:GetAttribute("TrackParent") == false then
				break
			end

			local parentMotor = motorByPart1[parentPart]
			if not parentMotor then
				break
			end

			if motorSet[parentMotor] and parentMotor ~= m then
				hasSelectedAncestor = true
				break
			end

			parentPart = typeof(parentMotor) == "table" and parentMotor.RealPart0
				or parentMotor.Part0
			childMotor = parentMotor
		end

		if
			not hasSelectedAncestor
			or (rotation and Preferences.get("IndividualRotationPivots") ~= false)
		then
			table.insert(snapshots, captureMotorSnapshot(m, motorRigs[m]))
		end
	end

	if #snapshots < 1 then
		return nil
	end

	if rotation then
		linkRotationSnapshots(snapshots, motorByPart1)
	end

	return snapshots
end

local fadeContexts

local function fadeContext(folder)
	if not fadeContexts then
		return nil
	end

	local context = fadeContexts[folder]
	if context then
		return context
	end

	context = { links = {} }
	for _, sibling in ipairs(folder:GetChildren()) do
		local link = sibling:GetAttribute("EclipseBoneLink")
		if link then
			context.links[link] = context.links[link] or {}
			table.insert(context.links[link], sibling)
		end
	end

	if folder:GetAttribute("EclipseArmatureMode") then
		local srcVal = folder:FindFirstChild("EclipseSourceRig")
		local srcRig = srcVal and srcVal.Value
		if srcRig then
			for _, desc in ipairs(require("RigTraversal").descendants(srcRig)) do
				if desc:IsA("Model") and desc:GetAttribute("EclipseArmature") then
					context.armature = desc
					break
				end
			end
		end
	end

	fadeContexts[folder] = context
	return context
end

local function tweenBoneTransparency(bone, value)
	if bone:GetAttribute("EclipsePropertyGizmo") or bone:GetAttribute("EclipseCameraProxy") then
		bone.Transparency = 1
		return
	end

	if markersHidden then
		value = 1
	end

	local fadeInfo = markersHidden and TweenInfo.new(0) or TweenInfo_BoneFade
	if not bone or not bone:IsA("BasePart") then
		return
	end

	if bone:GetAttribute("EclipseMasterMarker") then
		local wire = bone:FindFirstChild("MasterCircle")
		if wire then
			TweenService:Create(wire, fadeInfo, {
				Color3 = value < 1 and Color3.new(1, 1, 1) or Color3.fromRGB(215, 225, 230),
				Transparency = markersHidden and 1 or 0.15,
			}):Play()
		end

		bone.Transparency = 1
		return
	end

	local armatureSource = bone:FindFirstChild("EclipseArmatureSource")
	if armatureSource and armatureSource.Value then
		require("handles").select(bone, value < 1)
		ArmatureImport.setAnchorSelected(armatureSource.Value, value < 1)
		bone.Transparency = 1
		return
	end

	if
		bone:GetAttribute("SourceIsBone")
		or bone:GetAttribute("SourceIsVirtual")
		or bone:GetAttribute("EclipseLimbControl")
	then
		local base = bone:GetAttribute("MarkerColor")
		if typeof(base) == "Color3" then
			local target = (value < 1) and base:Lerp(Color3.new(1, 1, 1), 0.65) or base
			for _, adorn in ipairs(bone:GetChildren()) do
				if adorn:IsA("HandleAdornment") then
					TweenService:Create(adorn, fadeInfo, { Color3 = target }):Play()
				end
			end

			local sourceName = bone:GetAttribute("SourcePartName")
			local folder = bone.Parent
			local context = folder and fadeContext and fadeContext(folder)
			if folder and sourceName and context then
				for _, sibling in context.links[sourceName] or {} do
					for _, adorn in ipairs(sibling:GetChildren()) do
						if adorn:IsA("HandleAdornment") then
							TweenService:Create(adorn, fadeInfo, { Color3 = target }):Play()
						end
					end
				end

				if context.armature then
					local reference = bone:FindFirstChild("EclipseArmatureSource")
					local anchor = reference and reference.Value
						or context.armature:FindFirstChild(sourceName)
					if anchor and anchor:GetAttribute("EclipseArmatureBone") then
						ArmatureImport.setAnchorSelected(anchor, value < 1)
					end
				end
			elseif folder and sourceName then
				for _, sibling in ipairs(folder:GetChildren()) do
					if sibling:GetAttribute("EclipseBoneLink") == sourceName then
						for _, adorn in ipairs(sibling:GetChildren()) do
							if adorn:IsA("HandleAdornment") then
								TweenService:Create(adorn, fadeInfo, { Color3 = target }):Play()
							end
						end
					end
				end

				if folder:GetAttribute("EclipseArmatureMode") then
					local srcVal = folder:FindFirstChild("EclipseSourceRig")
					local srcRig = srcVal and srcVal.Value
					if srcRig then
						for _, desc in ipairs(require("RigTraversal").descendants(srcRig)) do
							if desc:IsA("Model") and desc:GetAttribute("EclipseArmature") then
								local reference = bone:FindFirstChild("EclipseArmatureSource")
								local anchor = reference and reference.Value
									or desc:FindFirstChild(sourceName)
								if anchor and anchor:GetAttribute("EclipseArmatureBone") then
									ArmatureImport.setAnchorSelected(anchor, value < 1)
								end

								break
							end
						end
					end
				end
			end
		end

		return
	end

	require("handles").select(bone, value < 1)
	if Preferences.get("BoneStyle") == 2 then
		value = 1
	end

	TweenService:Create(bone, fadeInfo, { Transparency = value }):Play()
	if markersHidden then
		bone.Transparency = 1
	end
end

local function cacheAxisTransparency()
	axisOriginalTransparency = {}

	if not activeAxis then
		return
	end

	for _, adornments in pairs(axisPartToAdornments) do
		for _, adornment in ipairs(adornments) do
			if adornment and adornment.Parent then
				axisOriginalTransparency[adornment] = adornment.Transparency
			end
		end
	end
end

local function restoreAxisTransparency()
	for adornment, value in pairs(axisOriginalTransparency) do
		if adornment and adornment.Parent then
			adornment.Transparency = value
			redrawRotationWire(adornment)
		end
	end

	axisOriginalTransparency = {}
end

local function setAxisTransparency(value)
	if not activeAxis then
		return
	end

	for _, adornments in pairs(axisPartToAdornments) do
		for _, adornment in ipairs(adornments) do
			if adornment and adornment.Parent then
				adornment.Transparency = value
				redrawRotationWire(adornment)
			end
		end
	end
end

local function setupAxisParts(axis)
	for _, part in ipairs(axis:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("MeshPart") then
			part.CanQuery = true
			part.Locked = true
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.Archivable = false

			if AXIS_NAMES[part.Name] then
				part.Transparency = AXIS_PART_TRANSPARENCY
			end
		end
	end
end

local dragGuidesFolder = nil
local dragGuideLabel = nil
local dragGuideLabelAdorned = false
local dragGuideSegments = {}
local rotationPieAdornment = nil
local rotationPieHolder = nil
local rotationPieBaseX = nil
local rotationPieBaseY = nil

local function destroyDragGuides()
	if dragGuidesFolder then
		pcall(function()
			dragGuidesFolder:Destroy()
		end)
	end

	dragGuidesFolder = nil
	dragGuideLabel = nil
	dragGuideLabelAdorned = false
	dragGuideSegments = {}
	rotationPieAdornment = nil
	rotationPieHolder = nil
	rotationPieBaseX = nil
	rotationPieBaseY = nil
end

local function getMotorPart1WorldPos(motor)
	if motor and motor.Part0 and motor.Part1 then
		return (motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()).Position
	end

	return nil
end

local function raycastMouseToPlane(mousePos, planePoint, planeNormal)
	return projectMouseToPlane(mousePos, planePoint, planeNormal)
end

local function createDragGuides(originPos, dirs, adorneePart, labelExtents)
	destroyDragGuides()

	local camera = getCamera()
	if not camera then
		return
	end

	dragGuidesFolder = Instance.new("Folder")
	dragGuidesFolder.Name = "_EclipseAnimator_DragGuides"
	require("Recovery").mark(dragGuidesFolder)

	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Locked = true
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(originPos)
	anchor.Parent = dragGuidesFolder

	for _, info in ipairs(dirs) do
		local whiteLine = Instance.new("Part")
		whiteLine.Name = "GuideLine"
		whiteLine.Anchored = true
		whiteLine.CanCollide = false
		whiteLine.CanQuery = false
		whiteLine.CanTouch = false
		whiteLine.Locked = true
		whiteLine.CastShadow = false
		whiteLine.Material = Enum.Material.Neon
		whiteLine.Color = info.constraint and info.color or GUIDE_LINE_COLOR
		whiteLine.Transparency = GUIDE_LINE_TRANSPARENCY
		whiteLine.Size = Vector3.new(0.015, 0.015, GUIDE_LINE_LENGTH)
		whiteLine.CFrame = CFrame.lookAt(originPos, originPos + info.dir)
		whiteLine.Parent = dragGuidesFolder
		do
			whiteLine.Transparency = 1
			local line = Instance.new("LineHandleAdornment")
			line.Name = "ConstraintAxis"
			line.Adornee = anchor
			line.AlwaysOnTop = true
			line.ZIndex = 1
			line.Color3 = info.color or GUIDE_LINE_COLOR
			line.Transparency = 0

			line.Thickness = 1.5
			line.Length = GUIDE_LINE_LENGTH
			local first = -info.dir * (GUIDE_LINE_LENGTH * 0.5)
			line.CFrame = CFrame.lookAt(first, first + info.dir)
			line.Parent = dragGuidesFolder
		end

		local progress = Instance.new("BoxHandleAdornment")
		progress.Name = "ProgressLine"
		progress.Shading = Enum.AdornShading.AlwaysOnTop
		progress.Adornee = anchor
		progress.Size = Vector3.new(0.028, 0.028, 0.05)
		progress.Color3 = info.color or GUIDE_LINE_COLOR
		progress.Transparency = 1
		progress.AlwaysOnTop = true
		progress.ZIndex = 2
		progress.Parent = anchor

		table.insert(dragGuideSegments, {
			anchor = anchor,
			dir = info.dir,
			color = info.color or GUIDE_LINE_COLOR,
			origin = originPos,
			progress = progress,
		})
	end

	if #dragGuideSegments == 2 then
		for i = 1, 2 do
			local other = dragGuideSegments[3 - i]
			local connector = Instance.new("Part")
			connector.Name = "ConnectorLine"
			connector.Anchored = true
			connector.CanCollide = false
			connector.CanQuery = false
			connector.CanTouch = false
			connector.Locked = true
			connector.CastShadow = false
			connector.Material = Enum.Material.Neon
			connector.Color = other.color:Lerp(Color3.new(1, 1, 1), 0.4)
			connector.Transparency = 1
			connector.Size = Vector3.new(0.015, 0.015, 0.05)
			connector.CFrame = CFrame.new(originPos)
			connector.Parent = dragGuidesFolder
			dragGuideSegments[i].connector = connector
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DeltaLabel"
	billboard.Enabled = Preferences.get("ShowTransformReadout") ~= false
	local stopReadout = Preferences.subscribe(function(key, value)
		if key == "ShowTransformReadout" then
			billboard.Enabled = value ~= false
		end
	end)
	billboard.Destroying:Once(stopReadout)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Brightness = 1
	billboard.Size = UDim2.fromOffset(230, 30)
	if adorneePart and adorneePart:IsA("BasePart") then
		billboard.Adornee = adorneePart
		billboard.ExtentsOffset = labelExtents or Vector3.new(1.25, 1.25, 0)
		dragGuideLabelAdorned = true
	else
		billboard.Adornee = anchor
		billboard.StudsOffset = Vector3.new(0, 1.6, 0)
		dragGuideLabelAdorned = false
	end

	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.new(0, 0, 1, 0)
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	frame:SetAttribute("ThemeBg", "Bg")
	gradient:SetAttribute("ThemeGrad", "Bg")
	gradient.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Delta"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 17
	label:SetAttribute("ThemeTxt", "Txt")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.Text = ""
	label.Parent = frame

	Theme.applyTree(frame)
	local disconnectTheme = Theme.onChanged(function()
		if frame.Parent then
			Theme.applyTree(frame)
		end
	end)
	frame.Destroying:Once(disconnectTheme)
	dragGuideLabel = label
	dragGuidesFolder.Parent = workspace
end

local function updateDragGuideProgress(deltas)
	for i, segment in ipairs(dragGuideSegments) do
		local delta = deltas[i]
		local active = (delta ~= nil) and math.abs(delta) > 0.01

		if segment.progress and segment.progress.Parent then
			if active then
				local endPos = segment.origin + segment.dir * delta
				local mid = (segment.origin + endPos) / 2
				local worldCF = CFrame.lookAt(mid, endPos)
				segment.progress.Size = Vector3.new(0.028, 0.028, math.abs(delta))
				segment.progress.CFrame = segment.anchor.CFrame:ToObjectSpace(worldCF)
				segment.progress.Transparency = 0.05
			else
				segment.progress.Transparency = 1
			end
		end
	end

	if #dragGuideSegments == 2 and deltas[1] ~= nil and deltas[2] ~= nil then
		for i = 1, 2 do
			local segment = dragGuideSegments[i]
			local other = dragGuideSegments[3 - i]
			local connector = segment.connector
			if connector and connector.Parent then
				local show = math.abs(deltas[i]) > 0.01 and math.abs(deltas[3 - i]) > 0.01
				if show then
					local startPos = segment.origin + segment.dir * deltas[i]
					local endPos = startPos + other.dir * deltas[3 - i]
					local mid = (startPos + endPos) / 2
					connector.Size = Vector3.new(0.015, 0.015, math.abs(deltas[3 - i]))
					connector.CFrame = CFrame.lookAt(mid, endPos)
					connector.Transparency = 0.75
				else
					connector.Transparency = 1
				end
			end
		end
	end
end

local function updateDragGuideLabel(text, worldPos)
	if not dragGuidesFolder then
		return
	end

	if not dragGuideLabelAdorned and worldPos then
		local anchor = dragGuidesFolder:FindFirstChild("LabelAnchor")
		if anchor then
			anchor.Position = worldPos
		end
	end

	if dragGuideLabel then
		dragGuideLabel.Text = text
	end
end

local function createRotationPie(originPos, axisDir, startDir, ringPart)
	if not dragGuidesFolder then
		return
	end

	local sideDir = axisDir:Cross(startDir)
	if sideDir.Magnitude <= 1e-4 then
		return
	end

	local holder = Instance.new("Part")
	holder.Name = "PieHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Locked = true
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.fromMatrix(originPos, startDir, sideDir.Unit)
	holder.Parent = dragGuidesFolder

	local ringColor = Color3.new(1, 1, 1)
	local ringRadius = ringPart and ringPart.Size.X * 0.5 or 3
	local ringAdornment = ringPart and ringPart:FindFirstChildOfClass("CylinderHandleAdornment")
	if ringAdornment then
		ringColor = ringAdornment.Color3
		ringRadius = ringAdornment.Radius
	end

	local pie = Instance.new("CylinderHandleAdornment")
	pie.Name = "Pie"
	pie.Adornee = holder
	pie.Height = 0.05
	pie.Radius = ringRadius
	pie.InnerRadius = 0
	pie.Angle = 0
	pie.Color3 = ringColor
	pie.Transparency = 0.7
	pie.AlwaysOnTop = true
	pie.ZIndex = 0
	pie.Parent = holder

	rotationPieAdornment = pie
	rotationPieHolder = holder
	rotationPieBaseX = startDir
	rotationPieBaseY = sideDir.Unit
end

local function updateRotationPie(angle)
	if not rotationPieAdornment then
		return
	end

	if
		rotationPieHolder
		and rotationPieHolder.Parent
		and activeAxis
		and rotationPieBaseX
		and rotationPieBaseY
	then
		local pivot = activeAxis:GetPivot()
		rotationPieHolder.CFrame =
			CFrame.fromMatrix(pivot.Position, rotationPieBaseX, rotationPieBaseY)
	end

	local degrees = math.deg(angle)
	if degrees >= 0 then
		rotationPieAdornment.CFrame = CFrame.new()
		rotationPieAdornment.Angle = math.min(degrees, 360)
	else
		rotationPieAdornment.CFrame = CFrame.Angles(0, 0, math.rad(degrees))
		rotationPieAdornment.Angle = math.min(-degrees, 360)
	end
end

local function formatStuds(value)
	local rounded = math.round(value * 100) / 100
	if rounded == 0 then
		rounded = 0
	end

	return string.format("%.2f", rounded)
end

function Axis:RefreshAxis()
	if holdingAxis or blenderGrabMode or blenderRotateMode then
		self._axisRefreshPending = true
		return
	end

	self._axisRefreshPending = nil
	if self._pendingGizmoMode then
		self:SetGizmoMode(self._pendingGizmoMode)
	end

	if selectedBone then
		self:ClearAxis()
		self:_spawnAxisForBone(selectedBone)
	end
end

function Axis:IsBlenderGrabMode()
	return blenderGrabMode
end

function Axis:IsBlenderRotateMode()
	return blenderRotateMode
end

function Axis:GetBlenderRotatePivot()
	return blenderRotateMode and rotateData.pivotPos or nil
end

function Axis:IsHoldingAxis()
	return holdingAxis
end

function Axis:GetSelectedBone()
	return selectedBone
end

function Axis:SetCurrentRig(rig)
	if currentRig ~= rig and blenderRotateMode then
		self:StopBlenderRotate(true)
	end

	currentRig = rig
	boneToMotorCache = setmetatable({}, { __mode = "k" })
end

function Axis:SetEnabledCheck(fn)
	enabledCheck = fn
end

local function spaceKey(mode)
	return mode == "Position" and "PositionAxisSpace" or "RotationAxisSpace"
end

local function chosenSpace(mode)
	local key = Preferences.get("SeparateTransformSpaces") and spaceKey(mode) or "PositionAxisSpace"
	return Preferences.get(key) == 2 and "Global" or "Local"
end

function Axis:SetGizmoMode(mode)
	if mode ~= "Position" and mode ~= "Rotation" then
		return false
	end

	if holdingAxis or blenderGrabMode or blenderRotateMode then
		self._pendingGizmoMode = mode
		return false
	end

	self._pendingGizmoMode = nil
	GizmoMode = mode
	axisSpace = chosenSpace(mode)
	self._renderSnapshot = nil
	self._hoverSnapshot = nil
end

function Axis:GetAxisSpace()
	return axisSpace
end

function Axis:SetAxisSpace(space)
	if space ~= "Local" and space ~= "Global" then
		return
	end

	local value = space == "Global" and 2 or 1
	local changes = Preferences.get("SeparateTransformSpaces") and { [spaceKey(GizmoMode)] = value }
		or { PositionAxisSpace = value, RotationAxisSpace = value }
	if not Preferences.setMany(changes) then
		return
	end

	axisSpace = space
	self._renderSnapshot = nil
	self._hoverSnapshot = nil
end

function Axis:ToggleAxisSpace()
	self:SetAxisSpace(axisSpace == "Global" and "Local" or "Global")
	return axisSpace
end

function Axis:Initialize(axisPackage, animatorFrame)
	PositionAxis = axisPackage and axisPackage.PositionAxis
	RotationAxis = axisPackage and axisPackage.RotationAxis

	for _, template in { PositionAxis, RotationAxis } do
		if template then
			for _, object in template:GetDescendants() do
				if object:IsA("HandleAdornment") then
					object.Visible = false
				end
			end
		end
	end

	self:CleanupOrphans()
	self.AnimatorFrame = animatorFrame
	self:_connectInputEvents()

	if axisRenderConnection then
		axisRenderConnection:Disconnect()
	end

	axisRenderConnection = RunService.RenderStepped:Connect(function(dt)
		self:_updateAxisRender(dt)
	end)
end

function Axis:Destroy()
	self:SetPropertyTarget(nil)
	playbackHidden = false
	markersHidden = false
	self:StopBlenderRotate(true)
	self:StopDrag()
	RotationCursor.destroy()
	if axisRenderConnection then
		axisRenderConnection:Disconnect()
		axisRenderConnection = nil
	end

	self:ClearAxis()
	for _, axis in cachedAxes do
		axis:Destroy()
	end

	cachedAxes = {}
	cachedAxisData = {}
	self:CleanupOrphans()
end

function Axis:ClearAxis()
	self._renderSnapshot = nil
	self._hoverSnapshot = nil
	destroyDragGuides()
	if activeAxis then
		for _, obj in ipairs(activeAxis:GetDescendants()) do
			if obj:IsA("HandleAdornment") then
				obj.Visible = false
			end
		end

		pcall(function()
			activeAxis.Parent = nil
		end)
		activeAxis = nil
	end

	activeAxisPart = nil
	axisOriginalTransparency = {}
	axisBaseData = {}
	axisAdornmentBaseData = {}
	axisPartToAdornments = {}
end

function Axis:IsBoneSelectable(bone)
	return bone ~= nil and bone.Parent ~= nil
end

function Axis:SelectBones(bones)
	local allowed = {}
	for _, bone in bones or {} do
		if self:IsBoneSelectable(bone) then
			table.insert(allowed, bone)
		end
	end

	bones = allowed
	bones = require("Organization").filterCollectionSelection(
		bones,
		PresentationState.currentRig,
		PresentationState.Rig
	)

	if #bones == #selectedBones then
		local same = true
		for i, b in ipairs(bones) do
			if selectedBones[i] ~= b then
				same = false
				break
			end
		end

		if same then
			if selectedBone and not activeAxis then
				self:_spawnAxisForBone(selectedBone)
			end

			return
		end
	end

	if blenderRotateMode then
		self:StopBlenderRotate()
	end

	if blenderGrabMode then
		self:StopBlenderGrab()
	end

	local oldSet = {}
	for _, b in ipairs(selectedBones) do
		oldSet[b] = true
	end

	local newSet = {}
	for _, b in ipairs(bones) do
		newSet[b] = true
	end

	for _, b in ipairs(selectedBones) do
		if not newSet[b] and b and b.Parent then
			tweenBoneTransparency(b, 1)
		end
	end

	for _, b in ipairs(bones) do
		if not oldSet[b] and b and b.Parent then
			local target = 0.8
			if b.Name == "Head" or b.Name == "Head_Bone" then
				target = 0.6
			end

			tweenBoneTransparency(b, target)
		end
	end

	selectedBones = {}
	for _, b in ipairs(bones) do
		table.insert(selectedBones, b)
	end

	selectedBone = selectedBones[#selectedBones]
	selectedMotor = selectedBone and getMotorForBone(selectedBone) or nil

	self:ClearAxis()
	if selectedBone then
		self:_spawnAxisForBone(selectedBone)
	end
end

function Axis:GetPropertyTarget()
	return propertySource
end

function Axis:SetPropertyTarget(motor, group, keepSelection)
	self._propertyGroup = group
	if propertySource ~= motor then
		if propertyBone then
			if selectedBone == propertyBone then
				self:SelectBones({})
			end

			propertyBone:Destroy()
		end

		propertyBone, propertyMotor, propertySource = nil, nil, motor
	end

	if not motor then
		return
	end

	if not propertyBone then
		propertyBone = Instance.new("Part")
		propertyBone.Name = "EclipsePropertyTarget"
		require("Recovery").mark(propertyBone)
		propertyBone.Anchored = true
		propertyBone.CanCollide = false
		propertyBone.CanTouch = false
		propertyBone.CanQuery = false
		propertyBone.Transparency = 1
		propertyBone.Size = Vector3.one
		propertyBone:SetAttribute("EclipsePropertyGizmo", true)
		propertyMotor = setmetatable({
			Part1 = propertyBone,
			Part0 = { CFrame = CFrame.identity },
			C1 = CFrame.identity,
			IsEclipsePropertyGizmo = true,
		}, {
			__index = function(_, key)
				if key == "C0" then
					if motor.Rig:IsA("Attachment") then
						return motor.Rig.WorldCFrame
					elseif motor.Rig:IsA("BasePart") then
						return motor.C0 * motor.Rig.PivotOffset
					end
				end

				return motor[key]
			end,
			__newindex = function(_, key, value)
				if key == "C0" and self._propertyGroup and #self._propertyGroup > 1 then
					local current = propertyMotor.C0
					local offset = value * current:Inverse()
					local targets = {}
					for _, member in self._propertyGroup do
						if member.Parent and member.Rig.Parent then
							local frame = member.Rig:IsA("Attachment") and member.Rig.WorldCFrame or member.C0
							table.insert(targets, { motor = member, frame = offset * frame })
						end
					end
					for _, entry in targets do
						local member = entry.motor
						if member.Rig:IsA("Attachment") then
							local parent = member.Rig.WorldCFrame * member.Rig.CFrame:Inverse()
							member.C0 = parent:ToObjectSpace(entry.frame)
						else
							member.C0 = entry.frame
						end
					end
				elseif key == "C0" and motor.Rig:IsA("BasePart") then
					motor.C0 = value * motor.Rig.PivotOffset:Inverse()
				elseif key == "C0" and motor.Rig:IsA("Attachment") then
					local parentFrame = motor.Rig.WorldCFrame * motor.Rig.CFrame:Inverse()
					motor.C0 = parentFrame:ToObjectSpace(value)
				else
					motor[key] = value
				end
			end,
		})
	end

	propertyBone.CFrame = propertyMotor.C0
	propertyBone.Parent = getCamera()
	if keepSelection then
		return
	end

	if selectedBone ~= propertyBone then
		self:SelectBone(propertyBone)
	else
		self:RefreshAxis()
	end
end

local function topLevelProperties(motors)
	local result = {}
	for _, member in motors do
		local nested = false
		for _, parent in motors do
			if
				parent ~= member
				and (parent.Rig:IsA("Model") or parent.Rig:IsA("BasePart"))
				and member.Rig:IsDescendantOf(parent.Rig)
			then
				nested = true
				break
			end
		end

		if not nested then
			table.insert(result, member)
		end
	end

	return result
end

function Axis:SelectBonesWithProperties(bones, motors, lead)
	motors = topLevelProperties(motors)
	if lead and not table.find(motors, lead) then
		lead = nil
	end

	self:SetPropertyTarget(lead or motors[1], motors, true)
	local list = table.clone(bones)
	if propertyBone then
		if lead then
			table.insert(list, propertyBone)
		else
			table.insert(list, 1, propertyBone)
		end
	end

	self:SelectBones(list)
end

function Axis:GetMixedPropertyMotors()
	if not propertyBone or #selectedBones < 2 or not table.find(selectedBones, propertyBone) then
		return nil
	end

	return self._propertyGroup
end

function Axis:SelectBone(bone)
	if bone then
		self:SelectBones({ bone })
	else
		self:SelectBones({})
	end
end

function Axis:ClearSelection()
	self:SelectBones({})
end

function Axis:AddToSelection(bone)
	if not bone then
		return
	end

	local newList = {}
	for _, b in ipairs(selectedBones) do
		if b ~= bone then
			table.insert(newList, b)
		end
	end

	table.insert(newList, bone)
	self:SelectBones(newList)
end

function Axis:RemoveFromSelection(bone)
	if not bone then
		return
	end

	local newList = {}
	for _, b in ipairs(selectedBones) do
		if b ~= bone then
			table.insert(newList, b)
		end
	end

	self:SelectBones(newList)
end

function Axis:ToggleSelection(bone)
	if not bone then
		return
	end

	local found = false
	for _, b in ipairs(selectedBones) do
		if b == bone then
			found = true
			break
		end
	end

	if found then
		self:RemoveFromSelection(bone)
	else
		self:AddToSelection(bone)
	end
end

function Axis:GetPrimaryMotor()
	return getMotorForBone(selectedBones[#selectedBones])
end

function Axis:GetSelectedBones()
	local copy = {}
	for _, b in ipairs(selectedBones) do
		if b and b.Parent then
			table.insert(copy, b)
		end
	end

	return copy
end

function Axis:InvalidateAxisCache()
	self:ClearAxis()
	for _, axis in cachedAxes do
		axis:Destroy()
	end

	cachedAxes = {}
	cachedAxisData = {}
end

function Axis:SetPlaybackHidden(hidden, hideMarkers)
	hidden = hidden == true
	if hideMarkers == nil then
		hideMarkers = hidden
	end

	hideMarkers = hideMarkers == true
	if playbackHidden == hidden and markersHidden == hideMarkers then
		return
	end

	playbackHidden = hidden
	markersHidden = hideMarkers
	if hidden then
		self:ClearAxis()
	end

	self:RefreshBoneFade()
end

local fadeApplied = setmetatable({}, { __mode = "k" })

function Axis:RefreshBoneFade()
	local folders = getAllBonesFolders()
	if #folders == 0 then
		return
	end

	local selectedSet = {}
	for _, b in ipairs(selectedBones) do
		if b and b.Parent then
			selectedSet[b] = true
		end
	end

	fadeContexts = {}
	for _, bonesFolder in ipairs(folders) do
		require("handles").setPlaybackHidden(bonesFolder, false)
		for _, bone in ipairs(bonesFolder:GetChildren()) do
			if bone:IsA("BasePart") then
				local target = 1
				if selectedSet[bone] then
					target = (bone.Name == "Head" or bone.Name == "Head_Bone") and 0.6 or 0.8
				end

				local stamp = tostring(target)
					.. tostring(markersHidden)
					.. tostring(bone:GetAttribute("MarkerColor"))
					.. tostring(Preferences.get("BoneStyle"))
				if fadeApplied[bone] ~= stamp then
					fadeApplied[bone] = stamp
					tweenBoneTransparency(bone, target)
				end
			end
		end

		require("handles").setPlaybackHidden(bonesFolder, markersHidden)
	end

	fadeContexts = nil
end

function Axis:GetBoneUnderMouse()
	local bone = self:_GetBoneUnderMouse()
	return self:IsBoneSelectable(bone) and bone or nil
end

function Axis:_GetBoneUnderMouse()
	if playbackHidden then
		return nil
	end

	local camera = getCamera()
	if not camera then
		return nil
	end

	local mousePos = UserInputService:GetViewportMouseLocation()
	if not mousePos then
		return nil
	end

	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local origin = require("Origin").hit(camera, mousePos)
	if origin then
		return origin
	end

	local folders = getAllBonesFolders()
	if #folders == 0 then
		return nil
	end

	local cameraControl = CameraDisplay.hitTest(camera, mousePos, folders)
	if cameraControl then
		return cameraControl
	end

	local control = LimbControls.hitTest(camera, mousePos, folders)
	if control then
		return control
	end

	local boneList = {}
	for _, bonesFolder in ipairs(folders) do
		for _, child in ipairs(bonesFolder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(boneList, child)
			end
		end

		if bonesFolder:GetAttribute("EclipseArmatureMode") then
			local srcVal = bonesFolder:FindFirstChild("EclipseSourceRig")
			local srcRig = srcVal and srcVal.Value
			if srcRig then
				for _, anchor in ArmatureRuntime.controls(srcRig) do
					if
						anchor.Parent
						and anchor.CanQuery
						and anchor:GetAttribute("Hidden") ~= true
					then
						table.insert(boneList, anchor)
					end
				end
			end
		end
	end

	if #boneList == 0 then
		return nil
	end

	local handles = require("handles")
	local bestHit = handles.pick(ray, boneList, camera, mousePos)
		or handles.assist(camera, mousePos, boneList)

	if bestHit then
		local linkName = bestHit:GetAttribute("EclipseBoneLink")
		if linkName and bestHit.Parent then
			local ownerRef = bestHit:FindFirstChild(
				if bestHit:GetAttribute("EclipseBoneEnd")
					then "EclipseLinkChild"
					else "EclipseLinkParentRef"
			)
			local joint
			if ownerRef then
				for _, candidate in bestHit.Parent:GetChildren() do
					local source = candidate:FindFirstChild("EclipseSourcePart")
					if source and source.Value == ownerRef.Value then
						joint = candidate
						break
					end
				end
			else
				local ownerName = if bestHit:GetAttribute("EclipseBoneEnd")
					then linkName
					else bestHit:GetAttribute("EclipseLinkParent") or linkName
				joint = bestHit.Parent:FindFirstChild(ownerName .. "_Bone")
			end

			if joint then
				if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part1 then
					return CFrame.new(joint.Position) * motor.Part1.CFrame.Rotation
				end

				return joint
			end
		end

		if bestHit:GetAttribute("EclipseArmatureBone") then
			for _, bonesFolder in ipairs(folders) do
				local joint = bonesFolder:FindFirstChild(
					(bestHit:GetAttribute("EclipseArmatureBoneId") or bestHit.Name) .. "_Bone"
				)
				if joint then
					if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part1 then
						return CFrame.new(joint.Position) * motor.Part1.CFrame.Rotation
					end

					return joint
				end
			end
		end

		return bestHit
	end

	return nil
end

local function rotationRingPoints(camera, pivot, normal, radius, frontOnly)
	local view = -camera.CFrame.LookVector
	local front = view - normal * view:Dot(normal)
	local side, up, start, sweep
	if frontOnly and front.Magnitude > 1e-5 then
		up = front.Unit
		side = up:Cross(normal).Unit
		start, sweep = 0, math.pi
	else
		side = normal:Cross(math.abs(normal.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis).Unit
		up = normal:Cross(side).Unit
		start, sweep = 0, math.pi * 2
	end

	local steps = sweep == math.pi and 48 or 96
	local points = table.create(steps + 1)
	for i = 0, steps do
		local angle = start + sweep * i / steps
		points[i + 1] = pivot + radius * (side * math.cos(angle) + up * math.sin(angle))
	end

	return points
end

local rotationPickCache = setmetatable({}, { __mode = "k" })

local function rotationRingHit(camera, point, pivot, normal, radius, frontOnly, part, hotspot)
	local cached = rotationPickCache[part]
	if
		not cached
		or cached.camera ~= camera.CFrame
		or cached.fov ~= camera.FieldOfView
		or cached.viewport ~= camera.ViewportSize
		or cached.pivot ~= pivot
		or cached.normal ~= normal
		or cached.radius ~= radius
		or cached.frontOnly ~= frontOnly
	then
		local projected = {}
		for _, world in rotationRingPoints(camera, pivot, normal, radius, frontOnly) do
			local screen = camera:WorldToViewportPoint(world)
			table.insert(projected, screen)
		end

		cached = {
			camera = camera.CFrame,
			fov = camera.FieldOfView,
			viewport = camera.ViewportSize,
			pivot = pivot,
			normal = normal,
			radius = radius,
			frontOnly = frontOnly,
			points = projected,
		}
		rotationPickCache[part] = cached
	end

	local depth = math.huge
	for i = 2, #cached.points do
		local a, b = cached.points[i - 1], cached.points[i]
		if a.Z > 0 and b.Z > 0 then
			local low, high = 0, 1
			for _, axis in { "X", "Y" } do
				local delta = b[axis] - a[axis]
				local origin = a[axis] - point[axis]
				if math.abs(delta) < 1e-9 then
					if math.abs(origin) > hotspot then
						high = -1
						break
					end
				else
					local t1, t2 = (-hotspot - origin) / delta, (hotspot - origin) / delta
					low = math.max(low, math.min(t1, t2))
					high = math.min(high, math.max(t1, t2))
				end
			end

			if low <= high then
				depth = math.min(depth, a.Z + (b.Z - a.Z) * (b.Z < a.Z and high or low))
			end
		end
	end

	return depth
end

local ringHitCache = setmetatable({}, { __mode = "k" })

local function ringHit(camera, point, pivot, normal, radius, frontOnly, cacheKey)
	local side = normal:Cross(math.abs(normal.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis).Unit
	local up = normal:Cross(side).Unit
	local cached = cacheKey and ringHitCache[cacheKey]
	local valid = cached
		and cached.camera == camera.CFrame
		and cached.fov == camera.FieldOfView
		and cached.viewport == camera.ViewportSize
		and cached.pivot == pivot
		and cached.normal == normal
		and cached.radius == radius
		and cached.frontOnly == frontOnly
	local points = valid and cached.points or {}
	local best = math.huge
	local previous, previousFront
	for i = 0, 96 do
		local sample = points[i + 1]
		if not valid then
			local angle = i * math.pi / 48
			local radial = radius * (side * math.cos(angle) + up * math.sin(angle))
			local projected = camera:WorldToViewportPoint(pivot + radial)
			sample = {
				point = Vector2.new(projected.X, projected.Y),
				z = projected.Z,
				front = not frontOnly or radial:Dot(camera.CFrame.Position - pivot) >= -1e-5,
			}
			points[i + 1] = sample
		end

		local front, p = sample.front, sample.point
		if previous and previousFront and front and sample.z > 0 then
			local segment = p - previous
			local t = segment:Dot(segment) > 0
					and math.clamp((point - previous):Dot(segment) / segment:Dot(segment), 0, 1)
				or 0
			best = math.min(best, (point - (previous + segment * t)).Magnitude)
		end

		previous = p
		previousFront = front
	end

	if cacheKey and not valid then
		ringHitCache[cacheKey] = {
			camera = camera.CFrame,
			fov = camera.FieldOfView,
			viewport = camera.ViewportSize,
			pivot = pivot,
			normal = normal,
			radius = radius,
			frontOnly = frontOnly,
			points = points,
		}
	end

	return best
end

local ROTATION_GRAB_DIRECTIONS =
	{ XRot = Vector3.zAxis, YRot = Vector3.xAxis, ZRot = Vector3.yAxis }

local function rotationGrabPoint(pivot, name, radius, gap, side)
	local direction = ROTATION_GRAB_DIRECTIONS[name]
	return pivot:PointToWorldSpace(direction * (radius + gap) * side)
end

function Axis:GetAxisUnderMouse()
	if not activeAxis then
		return nil
	end

	local camera = getCamera()
	if not camera then
		return nil
	end

	local mousePos = UserInputService:GetViewportMouseLocation()
	if not mousePos then
		return nil
	end

	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	if activeAxis:GetAttribute("EclipseAxisMode") == "Rotation" then
		local pivot = getGizmoPivotCFrame()
		if not pivot then
			return nil
		end

		local best, score = nil, math.huge
		if
			Preferences.get("RotationGrabCircles") ~= false
			and Preferences.get("ShowRotationAxes") ~= false
		then
			for part in axisBaseData do
				for _, grabName in { "RotationGrab", "RotationGrabOpposite" } do
					local grab = part:FindFirstChild(grabName)
					if grab and grab.Visible then
						local world = (part.CFrame * grab.CFrame).Position
						local center = camera:WorldToViewportPoint(world)
						local edge = camera:WorldToViewportPoint(
							world + camera.CFrame.RightVector * grab.Radius
						)
						local radius = (Vector2.new(edge.X, edge.Y) - Vector2.new(
							center.X,
							center.Y
						)).Magnitude
						local distance = (mousePos - Vector2.new(center.X, center.Y)).Magnitude
						if center.Z > 0 and distance <= radius + 2 and distance < score then
							best, score = part, distance
						end
					end
				end
			end

			if best then
				return best
			end
		end

		if Preferences.get("OldRotationGizmo") ~= true then
			for _, hotspot in { 3, 10 } do
				for part in axisBaseData do
					local name = part.Name
					if
						name == "ViewRot"
						or Preferences.get("ShowRotationAxes") ~= false
							and name:match("^[XYZ]Rot$")
					then
						local dir = name == "XRot" and Vector3.xAxis
							or name == "YRot" and Vector3.yAxis
							or Vector3.zAxis
						local depth = rotationRingHit(
							camera,
							mousePos,
							pivot.Position,
							name == "ViewRot" and camera.CFrame.LookVector
								or pivot:VectorToWorldSpace(dir),
							part.Size.X * 0.5,
							name ~= "ViewRot",
							part,
							hotspot + (name == "ViewRot" and 1 or 1.5)
						)
						if depth < score then
							best, score = part, depth
						end
					end
				end

				if best then
					break
				end
			end
		else
			for part in axisBaseData do
				local name = part.Name
				if
					name == "ViewRot"
					or Preferences.get("ShowRotationAxes") ~= false
						and (name == "XRot" or name == "YRot" or name == "ZRot")
				then
					local dir = name == "XRot" and Vector3.xAxis
						or name == "YRot" and Vector3.yAxis
						or Vector3.zAxis
					local distance = ringHit(
						camera,
						mousePos,
						pivot.Position,
						name == "ViewRot" and camera.CFrame.LookVector
							or pivot:VectorToWorldSpace(dir),
						part.Size.X * 0.5,
						name ~= "ViewRot",
						part
					)

					local tolerance = name == "ViewRot" and 7.5 or 5.5
					if distance < tolerance and distance < score then
						best, score = part, distance
					end
				end
			end
		end

		if best then
			return best
		end

		local center = camera:WorldToViewportPoint(pivot.Position)
		local ring = activeAxis:FindFirstChild("ViewRot", true)
		local edge = ring
			and camera:WorldToViewportPoint(
				pivot.Position + camera.CFrame.RightVector * (ring.Size.X * 0.5)
			)
		local radius = edge
				and (Vector2.new(edge.X, edge.Y) - Vector2.new(center.X, center.Y)).Magnitude
			or 0
		if
			not Preferences.get("DisableGizmoTrackball")
			and center.Z > 0
			and (mousePos - Vector2.new(center.X, center.Y)).Magnitude
				<= radius / (Preferences.get("OldRotationGizmo") == true and 1 or 1.2) * (Preferences.get(
					"RotationTrackballSize"
				) or 100) / 100
		then
			return activeAxis:FindFirstChild("SCore", true)
		end

		return nil
	end

	local pivot = getGizmoPivotCFrame()
	if not pivot then
		return nil
	end

	local center = camera:WorldToViewportPoint(pivot.Position)
	local a = Vector2.new(center.X, center.Y)
	local oldPosition = Preferences.get("OldPositionGizmo") == true
	local thickness = Preferences.get("PositionGizmoThickness") or 1
	local nearest, score = nil, math.max(7, thickness * 4.5)
	for part in axisBaseData do
		if
			part.Name:match("^[+-][XYZ]$")
			and (
				oldPosition
				or part.Name:sub(1, 1)
					== (Preferences.axisSign(part.Name:sub(-1)) < 0 and "-" or "+")
			)
		then
			local start = a
			local endpoint = part.Position
			if not oldPosition then
				local head = part:FindFirstChildWhichIsA("ConeHandleAdornment")
				local shaft = part:FindFirstChild("Shaft")
				if head then
					endpoint += part.CFrame.UpVector * head.Height * 0.5
				end

				if shaft then
					local p = camera:WorldToViewportPoint(
						(part.CFrame * shaft.CFrame).Position
							- part.CFrame.UpVector * shaft.Size.Y * 0.5
					)
					start = Vector2.new(p.X, p.Y)
				end
			end

			local projected = camera:WorldToViewportPoint(endpoint)
			local line = Vector2.new(projected.X, projected.Y) - start
			if line.Magnitude > 14 and projected.Z > 0 then
				local t = math.clamp(
					(mousePos - start):Dot(line) / line:Dot(line),
					oldPosition and math.min(22, line.Magnitude) / line.Magnitude or 0,
					1
				)
				local distance = (mousePos - start - line * t).Magnitude
				if distance < score then
					nearest, score = part, distance
				end
			end
		end
	end

	if nearest then
		return nearest
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { activeAxis }
	params.FilterType = Enum.RaycastFilterType.Include
	params.IgnoreWater = true

	local result = workspace:Raycast(ray.Origin, ray.Direction.Unit * 1000, params)

	if result and result.Instance then
		local hitPart = result.Instance
		local partName = hitPart.Name

		if hitPart:IsA("BasePart") or hitPart:IsA("MeshPart") then
			if
				hitPart:IsDescendantOf(activeAxis)
				and (
					partName == "SCore"
					or partName:match("[XYZ]")
					or partName:match("[%+%-][XYZ]")
					or partName:match("XRot")
					or partName:match("YRot")
					or partName:match("ZRot")
				)
			then
				return hitPart
			end
		end
	end

	return nil
end

function Axis:IsAxisUnderMouse()
	return self:GetAxisUnderMouse() ~= nil
end

function Axis:StartBlenderRotate(mousePos, useTrackball, showCircle)
	local primaryPivot = getPrimaryPivotCFrame()
	if not primaryPivot then
		return false
	end

	if BlenderEdit.blocked() then
		return
	end

	if selectedBone and CameraRig.isFov(getMotorForBone(selectedBone)) then
		return false
	end

	if not finiteVector(mousePos) then
		return false
	end

	if blenderRotateMode then
		return false
	end

	if not selectedBone then
		return false
	end

	local camera = getCamera()
	if not camera then
		return false
	end

	local motor = getMotorForBone(selectedBone)
	if not motor or not motor.Part0 or (typeof(motor) == "table" and motor.IsTranslationOnly) then
		return false
	end

	require("UserInputService").beginTransformCamera()
	blenderRotateMode = true
	blenderRotateTrackball = useTrackball == true
	holdingAxis = false
	activeAxisPart = nil

	rotateData.constraint = nil
	rotateData.precision = nil
	rotateData.motor = motor
	rotateData.bone = selectedBone
	rotateData.startMouse = mousePos
	rotateData.startMotorC0 = motor.C0
	rotateData.startMotorC1 = motor.C1
	rotateData.pivotPos = (#selectedBones > 1 and getSelectionCentroid()) or primaryPivot.Position
	rotateData.startCameraCF = camera.CFrame
	rotateData.allMotors = collectTopLevelMotorSnapshots(true)
		or { captureMotorSnapshot(motor, currentRig) }
	captureManipulation(rotateData.allMotors)
	rotateData.lockedDescendants = captureLockedDescendants(motor, rotateData.allMotors)

	local pivotViewport = camera:WorldToViewportPoint(rotateData.pivotPos)
	rotateData.screenCenter = Vector2.new(pivotViewport.X, pivotViewport.Y)

	rotateData.input = RotationInput.begin(rotateData.screenCenter, mousePos)
	rotateData.committedInput = table.clone(rotateData.input)
	rotateData.lastMouse = mousePos
	rotateData.pendingMouse = nil
	rotateData.pendingRotation = nil

	setAxisTransparency(1)
	RotationCursor.start(
		rotateData.pivotPos,
		blenderRotateTrackball,
		showCircle and math.max(24, (mousePos - rotateData.screenCenter).Magnitude) or nil,
		function() return blenderRotateMode end
	)

	return true
end

function Axis:EnterTrackballRotate()
	if not blenderRotateMode then
		return false
	end

	local mouse = UserInputService:GetViewportMouseLocation()
	if not finiteVector(mouse) then
		return false
	end

	self:FlushBlenderRotateInput()

	local snapshots = {}
	for _, info in ipairs(rotateData.allMotors) do
		local motor = info.motor
		if not motor or not motor.Parent or not motor.Part0 then
			return false
		end

		local snapshot = captureMotorSnapshot(motor, info.rig)
		snapshot.manipulationSnapshot = info.manipulationSnapshot or info
		table.insert(snapshots, snapshot)
	end

	linkRotationSnapshots(snapshots)
	rotateData.allMotors = snapshots
	rotateData.startMotorC0 = rotateData.motor.C0
	rotateData.startMotorC1 = rotateData.motor.C1
	rotateData.startMouse = mouse
	rotateData.precision = nil
	rotateData.input = RotationInput.begin(rotateData.screenCenter, mouse)
	rotateData.committedInput = table.clone(rotateData.input)
	rotateData.lastMouse = mouse
	rotateData.pendingMouse = nil
	rotateData.pendingRotation = nil
	blenderRotateTrackball = not blenderRotateTrackball
	destroyDragGuides()
	RotationCursor.setTrackball(blenderRotateTrackball)

	return true
end

function Axis:QueueBlenderRotateInput(mousePos)
	if
		UserInputService.isTransformPointerLookActive
		and UserInputService.isTransformPointerLookActive()
	then
		return false
	end

	if not finiteVector(mousePos) then
		return false
	end

	if not blenderRotateMode then
		return
	end

	if not blenderRotateTrackball then
		local _, changed = RotationInput.advance(rotateData.input, mousePos)
		rotateData.pendingRotation = rotateData.pendingRotation or changed
	end

	rotateData.pendingMouse = mousePos
end

function Axis:ClearBlenderRotateInput()
	rotateData.pendingMouse = nil
	rotateData.pendingRotation = nil
	if rotateData.committedInput then
		rotateData.input = table.clone(rotateData.committedInput)
	end
end

function Axis:FlushBlenderRotateInput()
	local mousePos = rotateData.pendingMouse or rotateData.lastMouse
	rotateData.pendingMouse = nil
	if blenderRotateMode and mousePos then
		return self:ProcessBlenderRotate(mousePos)
	end

	return false
end

function Axis:StopBlenderRotate(discardPending)
	RotationCursor.stop()
	destroyDragGuides()
	if not blenderRotateMode then
		return
	end

	if not discardPending then
		self:FlushBlenderRotateInput()
	end

	ArmatureRuntime.endDeferredEdits()

	blenderRotateMode = false
	require("UserInputService").endTransformCamera(true)
	blenderRotateTrackball = false

	rotateData.startMouse = nil
	rotateData.startMotorC0 = nil
	rotateData.startMotorC1 = nil
	rotateData.motor = nil
	rotateData.bone = nil
	rotateData.pivotPos = nil
	rotateData.screenCenter = nil
	rotateData.startScreenVector = nil
	rotateData.startCameraCF = nil
	rotateData.allMotors = nil
	rotateData.lockedDescendants = nil
	rotateData.input = nil
	rotateData.committedInput = nil
	rotateData.lastMouse = nil
	rotateData.pendingMouse = nil
	rotateData.pendingRotation = nil

	self:UpdateHover()
end

function Axis:ToggleBlenderRotate(mousePos, useTrackball)
	if blenderRotateMode then
		self:StopBlenderRotate()
		return false
	else
		return self:StartBlenderRotate(mousePos, useTrackball)
	end
end

function Axis:ProcessBlenderRotate(mousePos)
	if
		UserInputService.isTransformPointerLookActive
		and UserInputService.isTransformPointerLookActive()
	then
		return false
	end

	if not finiteVector(mousePos) then
		return false
	end

	if not blenderRotateMode then
		return
	end

	local camera = getCamera()
	if not camera then
		self:StopBlenderRotate()
		return
	end

	local motor = rotateData.motor
	if not motor or not motor.Parent or not motor.Part0 or not rotateData.startMotorC0 then
		self:StopBlenderRotate()
		return
	end

	local snapStep = rotationSnapStep()
	local snapChanged = snapStep ~= rotateData.snapStep
	if mousePos == rotateData.lastMouse and not rotateData.pendingRotation and not snapChanged then
		return false
	end

	rotateData.snapStep = snapStep
	rotateData.lastMouse = mousePos
	rotateData.pendingMouse = nil
	local cameraCF = rotateData.startCameraCF
	local rotation, localRotation
	if blenderRotateTrackball then
		local mouseDelta =
			precision(rotateData, "trackball", mousePos - rotateData.startMouse, 1 / 30)
		rotation =
			trackballRotation(cameraCF, mouseDelta, Preferences.get("BlenderTrackballSensitivity"))
	else
		local angle, changed = RotationInput.advance(rotateData.input, mousePos)
		changed = changed or rotateData.pendingRotation or snapChanged
		rotateData.pendingRotation = nil
		rotateData.committedInput = table.clone(rotateData.input)
		if not changed then
			return false
		end

		angle = precision(
			rotateData,
			"angle",
			angle * Preferences.get("BlenderRotateSensitivity"),
			1 / 30
		)
		angle = snapRotationAmount(angle)
		local axis = rotateData.constraint and rotateData.constraint.axis or cameraCF.LookVector
		if rotateData.constraint and axis:Dot(cameraCF.LookVector) < 0 then
			angle = -angle
		end

		rotation = CFrame.fromAxisAngle(axis, angle)
		if rotateData.constraint and rotateData.constraint.localSpace then
			localRotation = CFrame.fromAxisAngle(rotateData.constraint.vector, angle)
		end
	end

	local toPivot = CFrame.new(rotateData.pivotPos)
	local worldDelta = toPivot * rotation * toPivot:Inverse()
	for _, info in ipairs(rotateData.allMotors) do
		local movedMotor = info.motor
		if movedMotor and movedMotor.Parent and movedMotor.Part0 then
			local targetWorld = rotatedSnapshot(
				info,
				rotation,
				rotateData.pivotPos,
				#rotateData.allMotors > 1,
				localRotation
			)
			applySnapshotWorld(info, targetWorld)
		end
	end

	local lockedDescendants = rotateData.lockedDescendants
	if lockedDescendants then
		restoreTrackParentLockedDescendants(lockedDescendants)
	end

	return true
end

function Axis:ConstrainTransform(input)
	if not blenderGrabMode and not blenderRotateMode or blenderRotateTrackball then
		return false
	end

	local data = blenderGrabMode and grabData or rotateData
	local letter = input.KeyCode and input.KeyCode.Name
	local middle = input.UserInputType == Enum.UserInputType.MouseButton3
	if middle then
		if not UserInputService:GetViewportMouseLocation() then
			return false
		end

		local camera = getCamera()
		local center = camera:WorldToViewportPoint(data.pivotPos)
		local delta = UserInputService:GetViewportMouseLocation() - data.startMouse
		local best = -1
		for name, axis in { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis } do
			local endPoint = camera:WorldToViewportPoint(data.pivotPos + axis)
			local projected = Vector2.new(endPoint.X - center.X, endPoint.Y - center.Y)
			local score = projected.Magnitude > 1e-5 and math.abs(projected.Unit:Dot(delta)) or -1
			if score > best then
				best = score
				letter = Preferences.axisName(name)
			end
		end
	end

	if letter ~= "X" and letter ~= "Y" and letter ~= "Z" then
		return false
	end

	local previous = data.constraint
	local preferred = chosenSpace(blenderGrabMode and "Position" or "Rotation")
	local alternate = preferred == "Global" and "Local" or "Global"
	local space = preferred
	if not middle and previous and previous.letter == letter then
		space = (previous.localSpace and "Local" or "Global") == preferred and alternate or "Clear"
	end

	local axis = Preferences.axisVector(letter)
	local localVector = axis
	local constraintFrame = space == "Local" and getPrimaryPivotCFrame().Rotation or CFrame.identity
	axis = constraintFrame:VectorToWorldSpace(axis)
	data.constraint = space ~= "Clear"
			and {
				letter = letter,
				axis = axis,
				vector = localVector,
				frame = constraintFrame,
				localSpace = space == "Local",
				plane = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift),
			}
		or nil
	destroyDragGuides()
	if data.constraint then
		local dirs = {}
		if blenderGrabMode and data.constraint.plane then
			for _, name in { "X", "Y", "Z" } do
				if name ~= letter then
					table.insert(dirs, {
						dir = constraintFrame:VectorToWorldSpace((Preferences.axisVector(name))),
						color = GUIDE_AXIS_COLORS[name],
						constraint = true,
					})
				end
			end
		else
			table.insert(dirs, { dir = axis, color = GUIDE_AXIS_COLORS[letter], constraint = true })
		end

		createDragGuides(data.pivotPos, dirs)
		updateDragGuideLabel(
			letter
				.. (data.constraint.plane and " plane" or " axis")
				.. (space == "Local" and " (local)" or " (global)"),
			data.pivotPos
		)
	end

	if blenderGrabMode then
		self:ProcessBlenderGrab(UserInputService:GetViewportMouseLocation())
	else
		rotateData.lastMouse = nil
		rotateData.pendingRotation = true
		self:ProcessBlenderRotate(UserInputService:GetViewportMouseLocation())
	end

	return true
end

function Axis:StartBlenderGrab(mousePos)
	local primaryPivot = getPrimaryPivotCFrame(false)
	if not primaryPivot then
		return false
	end

	if BlenderEdit.blocked() then
		return
	end

	if selectedBone and CameraRig.isFov(getMotorForBone(selectedBone)) then
		return false
	end

	if not finiteVector(mousePos) then
		return false
	end

	if blenderGrabMode then
		return false
	end

	if not selectedBone then
		return false
	end

	local camera = getCamera()
	if not camera then
		return false
	end

	local motor = getMotorForBone(selectedBone)
	if not motor or not motor.Part0 then
		return false
	end

	require("UserInputService").beginTransformCamera()
	blenderGrabMode = true
	holdingAxis = false
	activeAxisPart = nil

	grabData.motor = motor
	grabData.bone = selectedBone
	grabData.constraint = nil
	grabData.precision = nil
	grabData.startMouse = mousePos
	grabData.startMotorC0 = motor.C0
	grabData.startMotorC1 = motor.C1
	grabData.pivotPos = (#selectedBones > 1 and getSelectionCentroid(false))
		or primaryPivot.Position
	grabData.allMotors = collectTopLevelMotorSnapshots()
		or { captureMotorSnapshot(motor, currentRig) }
	captureManipulation(grabData.allMotors)
	grabData.lockedDescendants = captureLockedDescendants(motor, grabData.allMotors)

	local viewportPoint = camera:WorldToViewportPoint(grabData.pivotPos)
	grabData.depth = viewportPoint.Z

	setAxisTransparency(1)

	return true
end

function Axis:StopBlenderGrab()
	destroyDragGuides()
	if not blenderGrabMode then
		return
	end

	ArmatureRuntime.endDeferredEdits()

	blenderGrabMode = false
	require("UserInputService").endTransformCamera(true)

	grabData.startMouse = nil
	grabData.startMotorC0 = nil
	grabData.startMotorC1 = nil
	grabData.motor = nil
	grabData.bone = nil
	grabData.pivotPos = nil
	grabData.depth = nil
	grabData.allMotors = nil
	grabData.lockedDescendants = nil

	self:UpdateHover()
end

function Axis:ToggleBlenderGrab(mousePos)
	if blenderGrabMode then
		self:StopBlenderGrab()
		return false
	else
		return self:StartBlenderGrab(mousePos)
	end
end

function Axis:ProcessBlenderGrab(mousePos)
	if
		UserInputService.isTransformPointerLookActive
		and UserInputService.isTransformPointerLookActive()
	then
		return false
	end

	if not finiteVector(mousePos) then
		return false
	end

	if not blenderGrabMode then
		return
	end

	local motor = grabData.motor
	if not motor or not motor.Parent or not motor.Part0 then
		self:StopBlenderGrab()
		return
	end

	if not grabData.depth or not grabData.startMotorC0 or not grabData.startMotorC1 then
		return
	end

	local lockedDescendants = grabData.lockedDescendants
		or captureLockedDescendants(motor, grabData.allMotors)

	local startMouseWorld = projectMouseToDepth(grabData.startMouse, grabData.depth)
	local currentMouseWorld = projectMouseToDepth(mousePos, grabData.depth)

	if not startMouseWorld or not currentMouseWorld then
		return
	end

	local moveDelta = precision(
		grabData,
		"move",
		(currentMouseWorld - startMouseWorld) * Preferences.get("BlenderGrabSensitivity"),
		0.1
	)
	if grabData.constraint then
		local c = grabData.constraint
		if c.plane then
			moveDelta -= c.axis * moveDelta:Dot(c.axis)
			moveDelta = snapMoveVector(moveDelta, c.frame)
			moveDelta -= c.axis * moveDelta:Dot(c.axis)
		else
			local a = getMouseAmountOnAxis(grabData.startMouse, grabData.pivotPos, c.axis)
			local b = getMouseAmountOnAxis(mousePos, grabData.pivotPos, c.axis)
			if a and b then
				moveDelta = c.axis
					* snapMoveAmount(
						precision(
							grabData,
							"constraint" .. c.letter .. tostring(c.localSpace),
							(b - a) * Preferences.get("BlenderGrabSensitivity"),
							0.1
						)
					)
			end
		end
	else
		moveDelta = snapMoveVector(moveDelta)
	end

	if grabData.allMotors then
		for _, info in ipairs(grabData.allMotors) do
			local m = info.motor
			if m and m.Part0 then
				local startPart1CF = info.startWorldCF * info.startC1:Inverse()
				local desiredCF = CFrame.new(startPart1CF.Position + moveDelta)
					* startPart1CF.Rotation
				applySnapshotWorld(info, desiredCF * info.startC1)
			end
		end
	else
		local startPart1CF = motor.Part0.CFrame
			* grabData.startMotorC0
			* grabData.startMotorC1:Inverse()
		local desiredCF = CFrame.new(startPart1CF.Position + moveDelta) * startPart1CF.Rotation
		local newC0 = motor.Part0.CFrame:Inverse() * desiredCF * grabData.startMotorC1

		motor.C0 = interactiveC0(motor, newC0)
	end

	restoreTrackParentLockedDescendants(lockedDescendants)
end

function Axis:StartDrag(axis, mousePos)
	if
		axis
		and axis.Name == "SCore"
		and GizmoMode == "Rotation"
		and Preferences.get("DisableGizmoTrackball")
	then
		return false
	end

	local primaryPivot = getPrimaryPivotCFrame(false)
	if not primaryPivot then
		return false
	end

	if BlenderEdit.blocked() then
		return
	end

	if selectedBone and CameraRig.isFov(getMotorForBone(selectedBone)) then
		return false
	end

	if not finiteVector(mousePos) then
		return false
	end

	if not selectedBone then
		return false
	end

	local camera = getCamera()
	if not camera then
		return false
	end

	local motor = getMotorForBone(selectedBone)
	if not motor or not motor.Part0 then
		return false
	end

	dragData.precision = nil
	dragData.mode = typeof(motor) == "table" and motor.IsTranslationOnly and "Position" or GizmoMode

	local function abortStart()
		self:StopDrag()
		self:UpdateHover()
		return false
	end

	require("UserInputService").beginTransformCamera()
	holdingAxis = true
	game:GetService("Selection"):Set({})
	activeAxisPart = axis
	cacheAxisTransparency()

	dragData.startMotorC0 = motor.C0
	dragData.startMotorC1 = motor.C1
	dragData.gizmoStartCF = getGizmoPivotCFrame()
	dragData.startWorldCF = motor.Part0.CFrame * dragData.startMotorC0
	dragData.startMouse = mousePos
	dragData.lastRotationMouse = nil
	dragData.rotationSnapStep = nil
	dragData.motor = motor
	dragData.pivotPos = (#selectedBones > 1 and getSelectionCentroid(false))
		or primaryPivot.Position
	dragData.axisDir = axisBaseData[axis] and axisBaseData[axis].dir or Vector3.zero
	dragData.bone = selectedBone
	dragData.startVec = nil
	dragData.rotationScreenTangent = nil
	dragData.rotationScreenRadius = nil
	dragData.rotationWorldRadius = nil
	dragData.isSpinCore = false
	dragData.startCameraCF = nil
	dragData.worldAxisDir = nil
	dragData.screenCenter = nil
	dragData.screenHandle = nil
	dragData.screenTangent = nil
	dragData.planeNormal = nil
	dragData.startPlaneVector = nil
	dragData.tangent = nil
	dragData.bitangent = nil
	dragData.startPlaneVector2D = nil
	dragData.startProj = nil
	dragData.dragAllMotors = nil
	dragData.lockedDescendants = nil
	dragData.isPlaneDrag = false
	dragData.planeDirA = nil
	dragData.planeDirB = nil
	dragData.planeStartHit = nil
	dragData.planeLetters = nil
	dragData.axisLetter = nil
	dragData.isScreenDrag = false
	dragData.screenDepth = nil
	dragData.rotationLetter = nil
	captureManipulation(
		collectTopLevelMotorSnapshots(dragData.mode == "Rotation")
			or { captureMotorSnapshot(motor, currentRig) }
	)

	for part, adornments in pairs(axisPartToAdornments) do
		local target = (part == axis)
				and (part.Name == "SCore" and dragData.mode == "Rotation" and TRACKBALL_TRANSPARENCY or ADORNMENT_TRANSPARENCY_SELECTED)
			or 1
		for _, adornment in ipairs(adornments) do
			if adornment and adornment.Parent then
				adornment.Transparency = target
				redrawRotationWire(adornment)
			end
		end
	end

	if dragData.mode == "Rotation" and axis.Name == "SCore" then
		dragData.isSpinCore = true
		dragData.startCameraCF = camera.CFrame
		dragData.dragAllMotors = collectTopLevelMotorSnapshots(true)
			or { captureMotorSnapshot(motor, currentRig) }
		dragData.lockedDescendants = captureLockedDescendants(motor, dragData.dragAllMotors)
		createDragGuides(dragData.pivotPos, {}, axis)
		return true
	end

	if dragData.mode == "Position" and axis.Name == "SCore" then
		local viewportPoint = camera:WorldToViewportPoint(dragData.pivotPos)
		dragData.isScreenDrag = true
		dragData.screenDepth = viewportPoint.Z
		dragData.dragAllMotors = collectTopLevelMotorSnapshots()
			or { captureMotorSnapshot(motor, currentRig) }
		dragData.lockedDescendants = captureLockedDescendants(motor, dragData.dragAllMotors)
		createDragGuides(dragData.pivotPos, {}, axis, Vector3.new(2, 2, 0))
		return true
	end

	if not activeAxis then
		return abortStart()
	end

	dragData.worldAxisDir = axis.Name == "ViewRot" and camera.CFrame.LookVector
		or dragData.gizmoStartCF:VectorToWorldSpace(dragData.axisDir)
	if dragData.worldAxisDir.Magnitude <= 0.0001 then
		return abortStart()
	end

	dragData.worldAxisDir = dragData.worldAxisDir.Unit

	if dragData.mode == "Position" and string.sub(axis.Name, 1, 5) == "Plane" then
		local pivotWorld = dragData.gizmoStartCF

		local localA = Vector3.xAxis
		local localB = Vector3.zAxis
		if axis.Name == "PlaneXY" then
			localA, localB = Vector3.xAxis, Vector3.yAxis
		elseif axis.Name == "PlaneYZ" then
			localA, localB = Vector3.yAxis, Vector3.zAxis
		end

		local dirA = pivotWorld:VectorToWorldSpace(localA)
		local dirB = pivotWorld:VectorToWorldSpace(localB)
		if dirA.Magnitude <= 1e-4 or dirB.Magnitude <= 1e-4 then
			return abortStart()
		end

		dragData.planeDirA = dirA.Unit
		dragData.planeDirB = dirB.Unit
		dragData.planeNormal = dragData.planeDirA:Cross(dragData.planeDirB).Unit
		dragData.planeLetters = { string.sub(axis.Name, 6, 6), string.sub(axis.Name, 7, 7) }

		local startHit = raycastMouseToPlane(mousePos, dragData.pivotPos, dragData.planeNormal)
		if not startHit then
			return abortStart()
		end

		dragData.isPlaneDrag = true
		dragData.planeStartHit = startHit
		dragData.dragAllMotors = collectTopLevelMotorSnapshots()
			or { captureMotorSnapshot(motor, currentRig) }
		dragData.lockedDescendants = captureLockedDescendants(motor, dragData.dragAllMotors)

		createDragGuides(dragData.pivotPos, {
			{
				dir = dragData.planeDirA,
				color = Preferences.axisColor(dragData.planeLetters[1], GUIDE_AXIS_COLORS),
			},
			{
				dir = dragData.planeDirB,
				color = Preferences.axisColor(dragData.planeLetters[2], GUIDE_AXIS_COLORS),
			},
		}, axis)
		return true
	end

	if dragData.mode == "Position" then
		local startAmount = getMouseAmountOnAxis(mousePos, dragData.pivotPos, dragData.worldAxisDir)
		if not startAmount then
			return abortStart()
		end

		dragData.startProj = startAmount
		dragData.dragAllMotors = collectTopLevelMotorSnapshots()
			or { captureMotorSnapshot(motor, currentRig) }
		dragData.lockedDescendants = captureLockedDescendants(motor, dragData.dragAllMotors)
		dragData.axisLetter = string.match(axis.Name, "[XYZ]")

		if dragData.axisLetter then
			createDragGuides(dragData.pivotPos, {
				{
					dir = dragData.worldAxisDir,
					color = Preferences.axisColor(dragData.axisLetter, GUIDE_AXIS_COLORS),
				},
			}, axis, Vector3.new(0.75, 0.75, 0))
		end
	end

	if dragData.mode == "Rotation" then
		local pivotPos = dragData.pivotPos
		local axisWorld = dragData.worldAxisDir

		if not axisWorld or axisWorld.Magnitude <= 1e-4 then
			return abortStart()
		end

		axisWorld = axisWorld.Unit

		dragData.rotationWorldRadius = math.max(0.01, axis.Size.X * 0.5)
		local startVec, tangent, radius =
			rotationDragBasis(mousePos, pivotPos, axisWorld, dragData.rotationWorldRadius)
		dragData.rotationScreenTangent = tangent
		dragData.rotationScreenRadius = radius

		if not startVec or startVec.Magnitude <= 1e-4 then
			return abortStart()
		end

		dragData.startVec = startVec.Unit
		dragData.rotationVector = startVec.Unit
		dragData.rotationAngle = 0
		dragData.rotationMouse = mousePos
		dragData.dragAllMotors = collectTopLevelMotorSnapshots(true)
			or { captureMotorSnapshot(motor, currentRig) }
		dragData.lockedDescendants = captureLockedDescendants(motor, dragData.dragAllMotors)
		dragData.rotationLetter = string.match(axis.Name, "^([XYZ])Rot")

		createDragGuides(dragData.pivotPos, dragData.rotationLetter and {
			{
				dir = dragData.worldAxisDir,
				color = Preferences.axisColor(dragData.rotationLetter, GUIDE_AXIS_COLORS),
				constraint = true,
			},
		} or {}, axis, Vector3.new(0.45, 0.45, 0))
		createRotationPie(dragData.pivotPos, dragData.worldAxisDir, dragData.startVec, axis)
		return true
	end

	return true
end

function Axis:ProcessDrag(currentMouse)
	if
		UserInputService.isTransformPointerLookActive
		and UserInputService.isTransformPointerLookActive()
	then
		return false
	end

	if not finiteVector(currentMouse) then
		return false
	end

	if not holdingAxis or not dragData.motor or not dragData.startMotorC0 then
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	local motor = dragData.motor
	local lockedDescendants = dragData.lockedDescendants
		or captureLockedDescendants(motor, dragData.dragAllMotors)
	if dragData.mode == "Rotation" or dragData.isSpinCore then
		dragData.lastRotationMouse = currentMouse
		dragData.rotationSnapStep = rotationSnapStep()
	end

	if dragData.isSpinCore then
		local mouseDelta =
			precision(dragData, "trackball", currentMouse - dragData.startMouse, 1 / 30)
		local cameraCF = dragData.startCameraCF or camera.CFrame

		local rotation, yawAngle, pitchAngle = trackballRotation(cameraCF, mouseDelta)

		if dragData.dragAllMotors then
			local pivotPos = dragData.pivotPos
			local cameraUp = cameraCF.UpVector
			local cameraRight = cameraCF.RightVector

			if cameraUp.Magnitude <= 0.0001 or cameraRight.Magnitude <= 0.0001 then
				return
			end

			cameraUp = cameraUp.Unit
			cameraRight = cameraRight.Unit

			local toPivot = CFrame.new(pivotPos)
			local fromPivot = CFrame.new(-pivotPos)

			local yawWorld = toPivot * CFrame.fromAxisAngle(cameraUp, yawAngle) * fromPivot
			local pitchWorld = toPivot * CFrame.fromAxisAngle(cameraRight, pitchAngle) * fromPivot

			for _, info in ipairs(dragData.dragAllMotors) do
				local m = info.motor
				if m and m.Part0 then
					local newWorldCF = rotatedSnapshot(
						info,
						rotation,
						pivotPos,
						#dragData.dragAllMotors > 1
					)
					applySnapshotWorld(info, newWorldCF)
				end
			end
		else
			local jointCF = dragData.startWorldCF

			local localYawAxis = jointCF:VectorToObjectSpace(cameraCF.UpVector)
			local localPitchAxis = jointCF:VectorToObjectSpace(cameraCF.RightVector)

			if localYawAxis.Magnitude <= 0.0001 or localPitchAxis.Magnitude <= 0.0001 then
				return
			end

			localYawAxis = localYawAxis.Unit
			localPitchAxis = localPitchAxis.Unit

			local rotationDelta = jointCF.Rotation:Inverse()
				* rotation
				* jointCF.Rotation

			motor.C0 =
				interactiveC0(motor, PivotSpace.rotate(motor, dragData.startMotorC0, rotationDelta))
		end

		updateDragGuideLabel(
			"X: "
				.. formatStuds(math.deg(pitchAngle))
				.. "\u{00B0}, Y: "
				.. formatStuds(math.deg(yawAngle))
				.. "\u{00B0}",
			getMotorPart1WorldPos(motor) or dragData.pivotPos
		)

		restoreTrackParentLockedDescendants(lockedDescendants)
		return
	end

	if dragData.isScreenDrag and dragData.mode == "Position" then
		if not dragData.screenDepth or not dragData.startMouse then
			return
		end

		local startWorld = projectMouseToDepth(dragData.startMouse, dragData.screenDepth)
		local currentWorld = projectMouseToDepth(currentMouse, dragData.screenDepth)
		if not startWorld or not currentWorld then
			return
		end

		local moveWorld =
			snapMoveVector(precision(dragData, "move", currentWorld - startWorld, 0.1))

		if dragData.dragAllMotors then
			for _, info in ipairs(dragData.dragAllMotors) do
				local m = info.motor
				if m and m.Part0 then
					local startPart1CF = info.startWorldCF * info.startC1:Inverse()
					local desiredCF = CFrame.new(startPart1CF.Position + moveWorld)
						* startPart1CF.Rotation
					applySnapshotWorld(info, desiredCF * info.startC1)
				end
			end
		else
			local startPart1CF = motor.Part0.CFrame
				* dragData.startMotorC0
				* dragData.startMotorC1:Inverse()
			local desiredCF = CFrame.new(startPart1CF.Position + moveWorld) * startPart1CF.Rotation
			local newC0 = motor.Part0.CFrame:Inverse() * desiredCF * dragData.startMotorC1

			motor.C0 = interactiveC0(motor, newC0)
		end

		updateDragGuideLabel(
			"X: "
				.. formatStuds(moveWorld.X)
				.. ", Y: "
				.. formatStuds(moveWorld.Y)
				.. ", Z: "
				.. formatStuds(moveWorld.Z),
			getMotorPart1WorldPos(motor) or (dragData.pivotPos + moveWorld)
		)

		restoreTrackParentLockedDescendants(lockedDescendants)
		return
	end

	local pivotPos = dragData.pivotPos
	local worldAxisDir = dragData.worldAxisDir

	if not worldAxisDir or worldAxisDir.Magnitude <= 0.0001 then
		return
	end

	worldAxisDir = worldAxisDir.Unit

	if dragData.mode == "Position" and dragData.isPlaneDrag then
		local currentHit = raycastMouseToPlane(currentMouse, pivotPos, dragData.planeNormal)
		if not currentHit then
			return
		end

		if not dragData.planeStartHit then
			dragData.planeStartHit = currentHit
		end

		local rawDelta = precision(dragData, "move", currentHit - dragData.planeStartHit, 0.1)
		local deltaA = snapMoveAmount(rawDelta:Dot(dragData.planeDirA))
		local deltaB = snapMoveAmount(rawDelta:Dot(dragData.planeDirB))
		local moveWorld = dragData.planeDirA * deltaA + dragData.planeDirB * deltaB

		if dragData.dragAllMotors then
			for _, info in ipairs(dragData.dragAllMotors) do
				local m = info.motor
				if m and m.Part0 then
					local startPart1CF = info.startWorldCF * info.startC1:Inverse()
					local desiredCF = CFrame.new(startPart1CF.Position + moveWorld)
						* startPart1CF.Rotation
					applySnapshotWorld(info, desiredCF * info.startC1)
				end
			end
		else
			local startPart1CF = motor.Part0.CFrame
				* dragData.startMotorC0
				* dragData.startMotorC1:Inverse()
			local desiredCF = CFrame.new(startPart1CF.Position + moveWorld) * startPart1CF.Rotation
			local newC0 = motor.Part0.CFrame:Inverse() * desiredCF * dragData.startMotorC1

			motor.C0 = interactiveC0(motor, newC0)
		end

		updateDragGuideProgress({ deltaA, deltaB })
		updateDragGuideLabel(
			Preferences.axisLabel(dragData.planeLetters[1])
				.. ": "
				.. formatStuds(deltaA)
				.. ", "
				.. Preferences.axisLabel(dragData.planeLetters[2])
				.. ": "
				.. formatStuds(deltaB),
			getMotorPart1WorldPos(motor) or (pivotPos + moveWorld)
		)

		restoreTrackParentLockedDescendants(lockedDescendants)
		return
	end

	if dragData.mode == "Position" then
		local currentAmount = getMouseAmountOnAxis(currentMouse, pivotPos, worldAxisDir)
		if not currentAmount then
			return
		end

		if not dragData.startProj then
			dragData.startProj = currentAmount
		end

		local amount =
			snapMoveAmount(precision(dragData, "amount", currentAmount - dragData.startProj, 0.1))
		local moveWorld = worldAxisDir * amount

		if dragData.dragAllMotors then
			for _, info in ipairs(dragData.dragAllMotors) do
				local m = info.motor
				if m and m.Part0 then
					local startPart1CF = info.startWorldCF * info.startC1:Inverse()
					local desiredCF = CFrame.new(startPart1CF.Position + moveWorld)
						* startPart1CF.Rotation
					applySnapshotWorld(info, desiredCF * info.startC1)
				end
			end
		else
			local startPart1CF = motor.Part0.CFrame
				* dragData.startMotorC0
				* dragData.startMotorC1:Inverse()
			local desiredCF = CFrame.new(startPart1CF.Position + moveWorld) * startPart1CF.Rotation
			local newC0 = motor.Part0.CFrame:Inverse() * desiredCF * dragData.startMotorC1

			motor.C0 = interactiveC0(motor, newC0)
		end

		updateDragGuideProgress({ amount })
		if dragData.axisLetter then
			updateDragGuideLabel(
				Preferences.axisLabel(dragData.axisLetter) .. ": " .. formatStuds(amount),
				getMotorPart1WorldPos(motor) or (pivotPos + moveWorld)
			)
		end

		restoreTrackParentLockedDescendants(lockedDescendants)
		return
	end

	if dragData.mode == "Rotation" then
		local startVec = dragData.startVec
		if not startVec or startVec.Magnitude <= 1e-4 then
			return
		end

		local projected = camera:WorldToViewportPoint(pivotPos)
		local center = Vector2.new(projected.X, projected.Y)
		local previousMouse = dragData.rotationMouse
		dragData.rotationMouse = currentMouse
		if dragData.rotationScreenTangent then
			if previousMouse then
				dragData.rotationAngle += (currentMouse - previousMouse):Dot(
					dragData.rotationScreenTangent
				) / dragData.rotationScreenRadius
			end
		else
			local offset = currentMouse - center
			local currentVec = Vector3.new(offset.X, -offset.Y, 0)
			if currentVec.Magnitude <= 6 then
				dragData.rotationVector = nil
				return
			end

			local previousOffset = previousMouse and previousMouse - center
			local previousVec = previousOffset and Vector3.new(previousOffset.X, -previousOffset.Y, 0)
			dragData.rotationVector = currentVec
			if not previousVec or previousVec.Magnitude <= 6 then
				return
			end

			if previousMouse then
				local segment = currentMouse - previousMouse
				local lengthSquared = segment:Dot(segment)
				local t = lengthSquared > 0
						and math.clamp((center - previousMouse):Dot(segment) / lengthSquared, 0, 1)
					or 0
				if (previousMouse + segment * t - center).Magnitude <= 6 then
					return
				end
			end

			local direction = worldAxisDir:Dot(camera.CFrame.LookVector) > 0 and -1 or 1
			dragData.rotationAngle += signedAngleAroundAxis(previousVec.Unit, currentVec.Unit, Vector3.zAxis) * direction
		end

		local angle = snapRotationAmount(precision(dragData, "angle", dragData.rotationAngle, 1 / 30))

		if dragData.dragAllMotors then
			local centroidCF = CFrame.new(pivotPos)
			local rotCF = CFrame.fromAxisAngle(worldAxisDir, angle)
			for _, info in ipairs(dragData.dragAllMotors) do
				local m = info.motor
				if m and m.Part0 then
					local localRotation = axisSpace == "Local"
							and dragData.rotationLetter
							and CFrame.fromAxisAngle(dragData.axisDir, angle)
						or nil
					local newWorldCF = rotatedSnapshot(
						info,
						rotCF,
						pivotPos,
						#dragData.dragAllMotors > 1,
						localRotation
					)
					applySnapshotWorld(info, newWorldCF)
				end
			end
		else
			local jointWorldCF = dragData.startWorldCF
			local localAxis = jointWorldCF:VectorToObjectSpace(worldAxisDir)

			if localAxis.Magnitude <= 1e-4 then
				return
			end

			localAxis = localAxis.Unit
			motor.C0 = interactiveC0(
				motor,
				PivotSpace.rotate(
					motor,
					dragData.startMotorC0,
					CFrame.fromAxisAngle(localAxis, angle)
				)
			)
		end

		updateRotationPie(angle)
		if dragData.rotationLetter then
			updateDragGuideLabel(
				Preferences.axisLabel(dragData.rotationLetter)
					.. ": "
					.. formatStuds(math.deg(angle))
					.. "\u{00B0}",
				getMotorPart1WorldPos(motor) or pivotPos
			)
		end

		restoreTrackParentLockedDescendants(lockedDescendants)
		return
	end
end

function Axis:RefreshRotationModifiers()
	if holdingAxis and dragData.lastRotationMouse and (dragData.mode == "Rotation" or dragData.isSpinCore) and dragData.rotationSnapStep ~= rotationSnapStep() then
		return self:ProcessDrag(dragData.lastRotationMouse)
	end
end

function Axis:RebaseAfterCameraLook(mouse)
	if not finiteVector(mouse) then
		return false
	end

	local camera = getCamera()
	local pivot = getPrimaryPivotCFrame(false)
	local data = blenderRotateMode and rotateData
		or blenderGrabMode and grabData
		or holdingAxis and dragData
	if not data or not camera or not pivot or not data.motor or not data.motor.Parent then
		return false
	end

	local field = holdingAxis and "dragAllMotors" or "allMotors"
	local snapshots = {}
	local originals = {}
	for _, original in manipulationSnapshots or {} do
		originals[original.motor] = original
	end

	for _, info in data[field] or {} do
		if not info.motor.Parent or not info.motor.Part0 then
			return false
		end

		local snapshot = captureMotorSnapshot(info.motor, info.rig)
		snapshot.manipulationSnapshot = originals[info.motor] or info.manipulationSnapshot or info
		table.insert(snapshots, snapshot)
	end

	if blenderRotateMode or (holdingAxis and data.mode == "Rotation") then
		linkRotationSnapshots(snapshots)
	end

	if #snapshots > 0 then
		data[field] = snapshots
	end

	data.startMotorC0, data.startMotorC1 = data.motor.C0, data.motor.C1
	data.startWorldCF = data.motor.Part0.CFrame * data.motor.C0
	data.startMouse, data.precision = mouse, nil
	data.lastRotationMouse, data.rotationSnapStep = nil, nil
	data.pivotPos = (#selectedBones > 1 and getSelectionCentroid(false)) or pivot.Position
	local projected = camera:WorldToViewportPoint(data.pivotPos)
	data.screenCenter = Vector2.new(projected.X, projected.Y)
	data.startCameraCF = camera.CFrame
	if blenderRotateMode then
		data.input = RotationInput.begin(data.screenCenter, mouse)
		data.committedInput = table.clone(data.input)
		data.lastMouse, data.pendingMouse, data.pendingRotation = mouse, nil, nil
	elseif blenderGrabMode then
		data.depth = projected.Z
	elseif data.isScreenDrag then
		data.screenDepth = projected.Z
	elseif data.isPlaneDrag then
		data.planeStartHit = raycastMouseToPlane(mouse, data.pivotPos, data.planeNormal)
	elseif data.worldAxisDir then
		if activeAxisPart and activeAxisPart.Name == "ViewRot" then
			data.worldAxisDir = camera.CFrame.LookVector
		end

		data.startProj = getMouseAmountOnAxis(mouse, data.pivotPos, data.worldAxisDir)
		local vector, tangent, radius = rotationDragBasis(
			mouse,
			data.pivotPos,
			data.worldAxisDir,
			data.rotationWorldRadius or 1
		)
		data.rotationScreenTangent, data.rotationScreenRadius = tangent, radius
		data.rotationVector = vector
		data.startVec = vector or data.startVec
		data.rotationAngle, data.rotationMouse = 0, mouse
	end

	if dragGuidesFolder then
		local dirs = {}
		for _, segment in dragGuideSegments do
			table.insert(
				dirs,
				{ dir = segment.dir, color = segment.color, constraint = data.mode == "Rotation" }
			)
		end

		createDragGuides(data.pivotPos, dirs, holdingAxis and activeAxisPart or nil)
		if holdingAxis and data.mode == "Rotation" and data.worldAxisDir and data.startVec then
			createRotationPie(data.pivotPos, data.worldAxisDir, data.startVec, activeAxisPart)
		end
	end

	return true
end

function Axis:GetManipulationSnapshots()
	return manipulationSnapshots,
		manipulationArmatureSnapshot,
		manipulationRig,
		manipulationRigSnapshots,
		manipulationIKSnapshots
end

function Axis:CancelDrag()
	local snapshots, graphs, ikGraphs =
		manipulationSnapshots, manipulationRigSnapshots, manipulationIKSnapshots
	self:ClearBlenderRotateInput()
	self:StopDrag()
	for rig, graph in pairs(graphs or {}) do
		if rig.Parent then
			ArmatureRuntime.restore(rig, graph)
			ArmatureRuntime.evaluate(rig)
		end
	end

	for rig, snapshot in pairs(ikGraphs or {}) do
		if rig.Parent then
			LimbIK.restore(rig, snapshot)
		end
	end

	for _, info in ipairs(snapshots or {}) do
		local motor = info.motor
		if motor and motor.Parent then
			if info.edit then
				if not (graphs and graphs[info.edit.rig]) then
					ArmatureRuntime.restoreEdit(motor, info.edit)
				end
			elseif not (ikGraphs and ikGraphs[info.rig]) then
				motor.C0 = info.startC0
			end
		end
	end

	self:RefreshAxis()
	return snapshots ~= nil
end

function Axis:StopDrag()
	if blenderRotateMode then RotationCursor.stop() end
	ArmatureRuntime.endDeferredEdits()

	local wasHolding = holdingAxis
	holdingAxis = false
	if wasHolding then
		require("UserInputService").endTransformCamera(true)
	end

	activeAxisPart = nil
	restoreAxisTransparency()
	destroyDragGuides()

	dragData.startMouse = nil
	dragData.lastRotationMouse, dragData.rotationSnapStep = nil, nil
	dragData.startTransform = nil
	dragData.motor = nil
	dragData.planeNormal = nil
	dragData.startPlaneVector = nil
	dragData.axisDir = nil
	dragData.mode = nil
	dragData.pivotPos = nil
	dragData.worldAxisDir = nil
	dragData.startProj = nil
	dragData.startMotorC0 = nil
	dragData.startMotorC1 = nil
	dragData.gizmoStartCF = nil
	dragData.startWorldCF = nil
	dragData.bone = nil
	dragData.startVec = nil
	dragData.rotationScreenTangent = nil
	dragData.rotationScreenRadius = nil
	dragData.rotationWorldRadius = nil
	dragData.isSpinCore = false
	dragData.startCameraCF = nil
	dragData.screenCenter = nil
	dragData.screenHandle = nil
	dragData.screenTangent = nil
	dragData.tangent = nil
	dragData.bitangent = nil
	dragData.startPlaneVector2D = nil
	dragData.dragAllMotors = nil
	dragData.lockedDescendants = nil
	dragData.isPlaneDrag = false
	dragData.planeDirA = nil
	dragData.planeDirB = nil
	dragData.planeStartHit = nil
	dragData.planeLetters = nil
	dragData.axisLetter = nil
	dragData.isScreenDrag = false
	dragData.screenDepth = nil
	dragData.rotationLetter = nil

	if blenderGrabMode then
		self:StopBlenderGrab()
	end

	if blenderRotateMode then
		self:StopBlenderRotate()
	end

	manipulationSnapshots = nil
	manipulationArmatureSnapshot = nil
	manipulationRig = nil
	manipulationRigSnapshots = nil
	manipulationIKSnapshots = nil
end

function Axis:UpdateHover()
	if not activeAxis or holdingAxis or blenderGrabMode or blenderRotateMode then
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	local point = UserInputService:GetViewportMouseLocation()
	if not point then
		return
	end

	local pivot = getGizmoPivotCFrame()
	local showRotationAxes = Preferences.get("ShowRotationAxes") ~= false
	local showGrabCircles = Preferences.get("RotationGrabCircles") ~= false
	local oldPosition = Preferences.get("OldPositionGizmo") == true
	local thickness = Preferences.get("PositionGizmoThickness") or 1
	local previous = self._hoverSnapshot

	if
		previous
		and previous.trackballSize == Preferences.get("RotationTrackballSize")
		and previous.disableTrackball == Preferences.get("DisableGizmoTrackball")
		and previous.axis == activeAxis
		and previous.render == self._renderSnapshot
		and previous.point == point
		and previous.pivot == pivot
		and previous.camera == camera
		and previous.frame == camera.CFrame
		and previous.fov == camera.FieldOfView
		and previous.viewport == camera.ViewportSize
		and previous.selected == activeAxisPart
		and previous.showRotationAxes == showRotationAxes
		and previous.showGrabCircles == showGrabCircles
		and previous.oldPosition == oldPosition
		and previous.thickness == thickness
	then
		return
	end

	self._hoverSnapshot = {
		trackballSize = Preferences.get("RotationTrackballSize"),
		disableTrackball = Preferences.get("DisableGizmoTrackball"),
		axis = activeAxis,
		render = self._renderSnapshot,
		point = point,
		pivot = pivot,
		camera = camera,
		frame = camera.CFrame,
		fov = camera.FieldOfView,
		viewport = camera.ViewportSize,
		selected = activeAxisPart,
		showRotationAxes = showRotationAxes,
		showGrabCircles = showGrabCircles,
		oldPosition = oldPosition,
		thickness = thickness,
	}

	local axisUnderMouse = self:GetAxisUnderMouse()

	for part, adornments in pairs(axisPartToAdornments) do
		local targetTransparency = ADORNMENT_TRANSPARENCY_DEFAULT

		if axisUnderMouse == part then
			targetTransparency = ADORNMENT_TRANSPARENCY_HOVER
		elseif activeAxisPart == part then
			targetTransparency = ADORNMENT_TRANSPARENCY_SELECTED
		end

		for _, adornment in ipairs(adornments) do
			if adornment and adornment.Parent then
				local transparency = adornment.Name == "TrackballHover"
						and (axisUnderMouse == part and TRACKBALL_TRANSPARENCY or 1)
					or targetTransparency
				if adornment.Transparency ~= transparency then
					adornment.Transparency = transparency
					redrawRotationWire(adornment)
				end
			end
		end
	end
end

function Axis:_connectInputEvents() end

local function resolveAdornmentOwnerPart(adornment)
	if not adornment then
		return nil
	end

	local parent = adornment.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("MeshPart")) then
		return parent
	end

	local adornee = adornment.Adornee
	if adornee and adornee:IsDescendantOf(activeAxis) then
		if adornee:IsA("BasePart") or adornee:IsA("MeshPart") then
			return adornee
		end

		local current = adornee
		while current and current ~= activeAxis do
			if current:IsA("BasePart") or current:IsA("MeshPart") then
				return current
			end

			current = current.Parent
		end
	end

	return nil
end

local function getLogicalAxisDir(partName)
	if partName == "XRot" or partName == "X" or partName == "+X" or partName == "-X" then
		return Vector3.xAxis
	elseif partName == "YRot" or partName == "Y" or partName == "+Y" or partName == "-Y" then
		return Vector3.yAxis
	elseif partName == "ZRot" or partName == "Z" or partName == "+Z" or partName == "-Z" then
		return Vector3.zAxis
	end

	return nil
end

function Axis:_spawnAxisForBone(bone)
	if holdingAxis or blenderGrabMode or blenderRotateMode then
		self._axisRefreshPending = true
		return
	end

	self._axisRefreshPending = nil
	if self._pendingGizmoMode then
		self:SetGizmoMode(self._pendingGizmoMode)
	end

	if PresentationState.ScaleGizmo and PresentationState.ScaleGizmo.isActive() then
		self:ClearAxis()
		return
	end

	if playbackHidden or (enabledCheck and not enabledCheck()) then
		return
	end

	self:ClearAxis()

	if not bone or #selectedBones == 0 then
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	local motor = getMotorForBone(bone)
	if CameraRig.isFov(motor) then
		return
	end

	local mode = typeof(motor) == "table" and motor.IsTranslationOnly and "Position" or GizmoMode
	local axisTemplate = nil
	if mode == "Position" then
		axisTemplate = PositionAxis
	else
		axisTemplate = RotationAxis
	end

	if not axisTemplate then
		warn("Axis: No axis template found for mode:", mode)
		return
	end

	local cachedData = cachedAxisData[mode]
	local freshClone = false

	local function trySpawnFromCache()
		local cached = cachedAxes[mode]
		local fresh = false

		if cached then
			local hasHandles = false
			local countOk = pcall(function()
				for _, obj in ipairs(cached:GetDescendants()) do
					if obj:IsA("HandleAdornment") then
						hasHandles = true
						break
					end
				end
			end)
			if not countOk or not hasHandles then
				pcall(function()
					cached:Destroy()
				end)
				cachedAxes[mode] = nil
				cachedAxisData[mode] = nil
				cached = nil
			end
		end

		if not cached then
			local cloneOk = pcall(function()
				cached = axisTemplate:Clone()
			end)
			if not cloneOk or not cached then
				return false, false
			end

			cached.Name = "_EclipseAnimator_Axis"
			cached.Archivable = false
			cached:SetAttribute("EclipseTransientAxis", true)
			cachedAxes[mode] = cached
			fresh = true
		end

		local ok = pcall(function()
			cached.Parent = camera
		end)
		if not ok or not cached.Parent then
			cachedAxes[mode] = nil
			cachedAxisData[mode] = nil
			return false, fresh
		end

		cached:SetAttribute("EclipseAxisMode", mode)
		activeAxis = cached
		Axis:CleanupOrphans(cached)
		return true, fresh
	end

	local ok
	ok, freshClone = trySpawnFromCache()
	if not ok then
		ok, freshClone = trySpawnFromCache()
		if not ok then
			warn("Axis: Failed to spawn axis after retry")
			return
		end
	end

	cachedData = cachedAxisData[mode]
	if mode == "Rotation" and not activeAxis:FindFirstChild("ViewRot") then
		local template = activeAxis:FindFirstChild("ZRot")
		if template then
			local was = template.Archivable
			template.Archivable = true
			local view = template:Clone()
			template.Archivable = was
			view.Name = "ViewRot"
			view.Parent = activeAxis
			for _, adornment in view:GetDescendants() do
				if adornment:IsA("HandleAdornment") then
					adornment.Color3 = Color3.new(0.9, 0.9, 0.9)
				end
			end
		end
	end

	for _, part in activeAxis:GetChildren() do
		if
			part:IsA("BasePart")
			and part.Name:match("^[+-][XYZ]$")
			and not part:FindFirstChild("Shaft")
		then
			local head = part:FindFirstChildWhichIsA("ConeHandleAdornment")
			local shaft = Instance.new("BoxHandleAdornment")
			shaft.Name = "Shaft"
			shaft.Adornee = part
			shaft.AlwaysOnTop = true
			shaft.ZIndex = 2
			shaft.Color3 = head and head.Color3 or Color3.new(1, 1, 1)
			shaft.Parent = part
		end
	end

	if mode == "Rotation" then
		for _, name in { "XRot", "YRot", "ZRot" } do
			local part = activeAxis:FindFirstChild(name)
			for _, grabName in { "RotationGrab", "RotationGrabOpposite" } do
				if part and not part:FindFirstChild(grabName) then
					local ring = part:FindFirstChildWhichIsA("CylinderHandleAdornment")
					local grab = Instance.new("CylinderHandleAdornment")
					grab.Name = grabName
					grab.Adornee = part
					grab.AlwaysOnTop = true
					grab.ZIndex = 4
					grab.Color3 = ring and ring.Color3 or part.Color
					grab.Height = 0.001
					grab.InnerRadius = 0
					grab.Parent = part
				end
			end
		end
	end

	if mode == "Rotation" then
		for _, name in { "XRot", "YRot", "ZRot", "ViewRot" } do
			local part = activeAxis:FindFirstChild(name)
			if part and not part:FindFirstChild("BlenderRotationRing") then
				local wire = Instance.new("WireframeHandleAdornment")
				wire.Name = "BlenderRotationRing"
				wire.Adornee = part
				wire.AlwaysOnTop = true
				wire.ZIndex = 3
				wire.Thickness = name == "ViewRot" and 2 or 3
				wire.Color3 = Color3.new(0.9, 0.9, 0.9)
				wire.Parent = part
			end
		end
	end

	local core = activeAxis:FindFirstChild("SCore")
	if core and mode == "Rotation" then
		if not core:FindFirstChild("TrackballHover") then
			for _, old in core:GetChildren() do
				if old:IsA("HandleAdornment") then
					old:Destroy()
				end
			end

			local disc = Instance.new("CylinderHandleAdornment")
			disc.Name = "TrackballHover"
			disc.Adornee = core
			disc.AlwaysOnTop = true
			disc.ZIndex = 0
			disc.Color3 = Color3.new(0.65, 0.65, 0.65)
			disc.Height = 0.001
			disc.Transparency = 1
			disc.Parent = core
		end
	elseif core and not core:FindFirstChild("CenterRing") then
		for _, old in core:GetChildren() do
			if old:IsA("HandleAdornment") then
				old:Destroy()
			end
		end

		local circle = Instance.new("CylinderHandleAdornment")
		circle.Name = "CenterRing"
		circle.Adornee = core
		circle.AlwaysOnTop = true
		circle.ZIndex = 3
		circle.Color3 = Color3.new(0.9, 0.9, 0.9)
		circle.Height = 0.001
		circle.Parent = core
	end

	setupAxisParts(activeAxis)

	local pivotCF = getGizmoPivotCFrame()
	if pivotCF then
		activeAxis:PivotTo(pivotCF)
	else
		activeAxis:PivotTo(CFrame.new(bone.Position))
	end

	for _, obj in ipairs(activeAxis:GetDescendants()) do
		if obj:IsA("HandleAdornment") then
			obj.Visible = not obj.Parent.Name:match("^%-[XYZ]$")
				or Preferences.get("OldPositionGizmo") == true
			if not obj.Visible then
				obj.Parent.CanQuery = false
			end

			obj.Transparency = obj.Name == "TrackballHover" and 1 or ADORNMENT_TRANSPARENCY_DEFAULT
		end
	end

	if freshClone or not cachedData then
		cachedData = {
			baseData = {},
			adornmentBaseData = {},
			partToAdornments = {},
		}

		for _, obj in ipairs(activeAxis:GetDescendants()) do
			if obj:IsA("BasePart") or obj:IsA("MeshPart") then
				local localOffset = activeAxis:GetPivot():ToObjectSpace(obj.CFrame)

				local dir = getLogicalAxisDir(obj.Name)
				if not dir then
					dir = localOffset.UpVector
					if dir.Magnitude <= 0.0001 then
						dir = Vector3.yAxis
					else
						dir = dir.Unit
					end
				end

				cachedData.baseData[obj] = {
					offset = localOffset,
					size = obj.Size,
					dir = dir,
				}

				cachedData.partToAdornments[obj] = cachedData.partToAdornments[obj] or {}
			elseif obj:IsA("WireframeHandleAdornment") then
				cachedData.adornmentBaseData[obj] = { class = "WireframeHandleAdornment" }
				local owner = resolveAdornmentOwnerPart(obj)
				if owner then
					cachedData.partToAdornments[owner] = cachedData.partToAdornments[owner] or {}
					table.insert(cachedData.partToAdornments[owner], obj)
				end
			elseif obj:IsA("ConeHandleAdornment") then
				obj.Visible = true
				obj.Transparency = obj.Name == "TrackballHover" and 1
					or ADORNMENT_TRANSPARENCY_DEFAULT

				cachedData.adornmentBaseData[obj] = {
					class = "ConeHandleAdornment",
					radius = obj.Radius * POS_ADORNMENT_SCALE,
					height = obj.Height * POS_ADORNMENT_SCALE,
					cframe = obj.CFrame,
				}

				local hitPart = resolveAdornmentOwnerPart(obj)

				if hitPart and (hitPart:IsA("BasePart") or hitPart:IsA("MeshPart")) then
					cachedData.partToAdornments[hitPart] = cachedData.partToAdornments[hitPart]
						or {}
					table.insert(cachedData.partToAdornments[hitPart], obj)
				end
			elseif obj:IsA("CylinderHandleAdornment") then
				obj.Visible = true
				obj.Transparency = obj.Name == "TrackballHover" and 1
					or ADORNMENT_TRANSPARENCY_DEFAULT

				cachedData.adornmentBaseData[obj] = {
					class = "CylinderHandleAdornment",
					radius = obj.Radius * ROT_ADORNMENT_SCALE,
					innerRadius = obj.InnerRadius * ROT_ADORNMENT_SCALE,
					cframe = obj.CFrame,
				}

				local hitPart = resolveAdornmentOwnerPart(obj)

				if hitPart and (hitPart:IsA("BasePart") or hitPart:IsA("MeshPart")) then
					cachedData.partToAdornments[hitPart] = cachedData.partToAdornments[hitPart]
						or {}
					table.insert(cachedData.partToAdornments[hitPart], obj)
				end
			elseif obj:IsA("BoxHandleAdornment") then
				obj.Visible = true
				obj.Transparency = obj.Name == "TrackballHover" and 1
					or ADORNMENT_TRANSPARENCY_DEFAULT

				cachedData.adornmentBaseData[obj] = {
					class = "BoxHandleAdornment",
					size = obj.Size * POS_ADORNMENT_SCALE,
					cframe = obj.CFrame,
				}

				local hitPart = resolveAdornmentOwnerPart(obj)

				if hitPart and (hitPart:IsA("BasePart") or hitPart:IsA("MeshPart")) then
					cachedData.partToAdornments[hitPart] = cachedData.partToAdornments[hitPart]
						or {}
					table.insert(cachedData.partToAdornments[hitPart], obj)
				end
			elseif obj:IsA("SphereHandleAdornment") then
				obj.Visible = true
				obj.Transparency = obj.Name == "TrackballHover" and 1
					or ADORNMENT_TRANSPARENCY_DEFAULT

				cachedData.adornmentBaseData[obj] = {
					class = "SphereHandleAdornment",
					radius = obj.Radius * ROT_ADORNMENT_SCALE,
					cframe = obj.CFrame,
				}

				local hitPart = resolveAdornmentOwnerPart(obj)

				if hitPart and (hitPart:IsA("BasePart") or hitPart:IsA("MeshPart")) then
					cachedData.partToAdornments[hitPart] = cachedData.partToAdornments[hitPart]
						or {}
					table.insert(cachedData.partToAdornments[hitPart], obj)
				end
			end
		end

		cachedAxisData[mode] = cachedData
	end

	axisBaseData = cachedData.baseData
	axisAdornmentBaseData = cachedData.adornmentBaseData
	axisPartToAdornments = cachedData.partToAdornments
end

function Axis:_updateAxisRender(dt)
	if
		not holdingAxis
		and not blenderGrabMode
		and not blenderRotateMode
		and (self._pendingGizmoMode or self._axisRefreshPending)
	then
		self:RefreshAxis()
	end

	axisSpace = chosenSpace(GizmoMode)
	for _, bone in selectedBones do
		if not self:IsBoneSelectable(bone) then
			self:SelectBones(selectedBones)
			break
		end
	end

	if
		PresentationState.PresentationHidden
		and (not PresentationState.CameraPoseMode or PresentationState.CameraBonesHidden)
	then
		return
	end

	if playbackHidden then
		if activeAxis then
			self:ClearAxis()
		end

		return
	end

	if enabledCheck and not enabledCheck() then
		if activeAxis then
			self:ClearAxis()
		end

		return
	end

	if blenderRotateMode then
		return
	end

	if #selectedBones == 0 then
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	if activeAxis and activeAxis.Parent ~= camera then
		self:ClearAxis()
	end

	if not activeAxis and selectedBone then
		self:_spawnAxisForBone(selectedBone)
	end

	if not activeAxis then
		return
	end

	local pivotCF = getGizmoPivotCFrame()
	if not pivotCF then
		return
	end

	local camPos = camera.CFrame.Position
	local pivotPos = pivotCF.Position

	local dist = math.max(0.01, -camera.CFrame:PointToObjectSpace(pivotPos).Z)
	local pixelsToStuds = 2
		* dist
		* math.tan(math.rad(camera.FieldOfView) * 0.5)
		/ math.max(1, camera.ViewportSize.Y)
	local positionMode = activeAxis:GetAttribute("EclipseAxisMode") == "Position"
	local legacy = Preferences.get(positionMode and "OldPositionGizmo" or "OldRotationGizmo")
		== true
	local size = Preferences.get("GizmoSize") or 1
	local sizeMultiplier = 0.7 * size * (positionMode and 1.4 or 1)
	local scale = pixelsToStuds * 32 * sizeMultiplier
	local adornmentScale = scale * 2

	local basis = pixelsToStuds * 75 * size * (Preferences.get("GizmoDistance") or 2.5) / 2.5
	local distance = legacy
			and (Preferences.get("GizmoDistance") or 2.5) * scale / (0.7 * AXIS_MIN_SCALE)
		or basis * (positionMode and 1.125 or 1)

	local showRotationAxes = Preferences.get("ShowRotationAxes") ~= false
	local showGrabCircles = Preferences.get("RotationGrabCircles") ~= false
	local grabCircleSize = Preferences.get("RotationGrabCircleSize") or 18
	local oldRotation = Preferences.get("OldRotationGizmo") == true
	local viewRadius = oldRotation and 1.15 or 1.2
	local oldPosition = Preferences.get("OldPositionGizmo") == true
	local thickness = Preferences.get("PositionGizmoThickness") or 1
	local previous = self._renderSnapshot
	if
		previous
		and previous.blenderAxes == Preferences.get("BlenderAxes")
		and previous.trackballSize == Preferences.get("RotationTrackballSize")
		and previous.disableTrackball == Preferences.get("DisableGizmoTrackball")
		and previous.axis == activeAxis
		and previous.data == axisBaseData
		and previous.adornments == axisAdornmentBaseData
		and previous.pivot == pivotCF
		and previous.camera == camera.CFrame
		and previous.dist == dist
		and previous.size == sizeMultiplier
		and previous.distance == distance
		and previous.showRotationAxes == showRotationAxes
		and previous.oldRotation == oldRotation
		and previous.holding == holdingAxis
		and previous.selected == activeAxisPart
		and previous.oldPosition == oldPosition
		and previous.thickness == thickness
		and previous.showGrabCircles == showGrabCircles
		and previous.grabCircleSize == grabCircleSize
	then
		return
	end

	self._renderSnapshot = {
		blenderAxes = Preferences.get("BlenderAxes"),
		trackballSize = Preferences.get("RotationTrackballSize"),
		disableTrackball = Preferences.get("DisableGizmoTrackball"),
		axis = activeAxis,
		data = axisBaseData,
		adornments = axisAdornmentBaseData,
		pivot = pivotCF,
		camera = camera.CFrame,
		dist = dist,
		size = sizeMultiplier,
		distance = distance,
		showRotationAxes = showRotationAxes,
		oldRotation = oldRotation,
		holding = holdingAxis,
		selected = activeAxisPart,
		oldPosition = oldPosition,
		thickness = thickness,
		showGrabCircles = showGrabCircles,
		grabCircleSize = grabCircleSize,
	}

	for part, data in pairs(axisBaseData) do
		if not part or not part.Parent then
			continue
		end

		if not part:IsA("BasePart") and not part:IsA("MeshPart") then
			continue
		end

		local ring = part.Name == "XRot"
			or part.Name == "YRot"
			or part.Name == "ZRot"
			or part.Name == "ViewRot"
		local ringDistance = distance * (part.Name == "ViewRot" and viewRadius or 1)
		part.Size = ring and Vector3.new(ringDistance * 2, data.size.Y * scale, ringDistance * 2)
			or data.size * scale
		local center = part.Name == "SCore" or part.Name == "Primary"
		local offset = data.offset.Position * (center and scale or distance / 4.25)
		local scaledOffset = CFrame.new(offset) * data.offset.Rotation

		part.CFrame = part.Name == "ViewRot"
				and CFrame.new(pivotPos) * camera.CFrame.Rotation * scaledOffset.Rotation
			or pivotCF * scaledOffset
		if part.Name == "SCore" then
			part.CFrame = CFrame.new(pivotPos) * camera.CFrame.Rotation
			part.Size = Vector3.one * pixelsToStuds * 17
		elseif part.Name:match("^[+-][XYZ]$") then
			local letter = part.Name:sub(-1)
			local axis = letter == "X" and Vector3.xAxis
				or letter == "Y" and Vector3.yAxis
				or Vector3.zAxis
			local direction = pivotCF:VectorToWorldSpace(axis)
				* (part.Name:sub(1, 1) == "-" and -1 or 1)
			local right = (math.abs(direction.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis):Cross(
				direction
			).Unit
			part.CFrame = CFrame.fromMatrix(
				pivotPos + direction * distance,
				right,
				direction,
				right:Cross(direction)
			)
			part.Size = Vector3.new(
				math.max(12, 9 * thickness),
				math.max(16, oldPosition and 16 or basis / pixelsToStuds * 0.25),
				math.max(12, 9 * thickness)
			) * pixelsToStuds
			part.CanQuery = oldPosition
				or part.Name:sub(1, 1)
					== (Preferences.axisSign(part.Name:sub(-1)) < 0 and "-" or "+")
		elseif part.Name:sub(1, 5) == "Plane" then
			local axes = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }
			local a = pivotCF:VectorToWorldSpace(axes[part.Name:sub(6, 6)])
				* Preferences.axisSign(part.Name:sub(6, 6))
			local b = pivotCF:VectorToWorldSpace(axes[part.Name:sub(7, 7)])
				* Preferences.axisSign(part.Name:sub(7, 7))
			local normal = a:Cross(b)
			part.CFrame =
				CFrame.fromMatrix(pivotPos + (a + b) * distance * 0.35, a, normal, a:Cross(normal))
			part.Size = Vector3.new(14, 2, 14) * pixelsToStuds
		end
	end

	for adornment, data in pairs(axisAdornmentBaseData) do
		if adornment.Parent and adornment.Parent:IsA("BasePart") then
			adornment.Adornee = adornment.Parent
		end

		if not adornment or not adornment.Parent then
			continue
		end

		if adornment.Parent.Name:match("^[+-][XYZ]$") then
			local visible = oldPosition
				or adornment.Parent.Name:sub(1, 1)
					== (Preferences.axisSign(adornment.Parent.Name:sub(-1)) < 0 and "-" or "+")
			adornment.Visible = visible
			adornment.Parent.CanQuery = visible
			if not visible then
				continue
			end
		end

		if
			GizmoMode == "Rotation"
			and adornment.Parent.Name == "SCore"
			and (adornment.Name ~= "TrackballHover" or Preferences.get("DisableGizmoTrackball"))
		then
			adornment.Visible = false
			continue
		end

		if adornment.Name == "TrackballHover" then
			adornment.Visible = not Preferences.get("DisableGizmoTrackball")
		end

		local native = adornment.Parent.Name:match("([XYZ])Rot$")
			or adornment.Parent.Name:match("[+-]([XYZ])$")
		if not native and adornment.Parent.Name:sub(1, 5) == "Plane" then
			native = ({ PlaneXY = "Z", PlaneXZ = "Y", PlaneYZ = "X" })[adornment.Parent.Name]
		end

		if native then
			if data.originalColor == nil then
				data.originalColor = adornment.Color3
			end

			adornment.Color3 = Preferences.axisColor(native, GUIDE_AXIS_COLORS)

			if data.class == "ConeHandleAdornment" or data.class == "BoxHandleAdornment" then
				adornment.Shading = Enum.AdornShading.AlwaysOnTop
			end
		end

		if adornment.Parent.Name:match("^[XYZ]Rot$") then
			adornment.Visible = showRotationAxes
		end

		if adornment.Name == "RotationGrab" or adornment.Name == "RotationGrabOpposite" then
			adornment.Visible = showRotationAxes and showGrabCircles
			local point = rotationGrabPoint(
				pivotCF,
				adornment.Parent.Name,
				distance * viewRadius,
				pixelsToStuds * (grabCircleSize * 0.5 + 3),
				adornment.Name == "RotationGrabOpposite" and -1 or 1
			)
			local depth = -camera.CFrame:PointToObjectSpace(point).Z
			if depth <= 0 then
				adornment.Visible = false
			end

			local pixel = 2
				* math.max(0.01, depth)
				* math.tan(math.rad(camera.FieldOfView) * 0.5)
				/ math.max(1, camera.ViewportSize.Y)
			adornment.Radius = pixel * grabCircleSize * 0.5
			adornment.InnerRadius = 0
			adornment.Height = pixel * 0.2
			adornment.CFrame =
				adornment.Adornee.CFrame:ToObjectSpace(CFrame.new(point) * camera.CFrame.Rotation)
			continue
		end

		local ringName = adornment.Parent.Name
		if data.class == "WireframeHandleAdornment" then
			adornment.Visible = not oldRotation and (ringName == "ViewRot" or showRotationAxes)
			if adornment.Visible then
				local axis = ringName == "XRot" and Vector3.xAxis
					or ringName == "YRot" and Vector3.yAxis
					or Vector3.zAxis
				local normal = ringName == "ViewRot" and camera.CFrame.LookVector
					or pivotCF:VectorToWorldSpace(axis)
				local points = rotationRingPoints(
					camera,
					Vector3.zero,
					normal,
					distance * (ringName == "ViewRot" and viewRadius or 1),
					ringName ~= "ViewRot"
						and not (holdingAxis and activeAxisPart == adornment.Parent)
				)
				adornment.CFrame = adornment.Adornee.CFrame:ToObjectSpace(CFrame.new(pivotPos))
				adornment.Scale = Vector3.one
				data.points = points
				data.camera = camera
			end

			redrawRotationWire(adornment)
			continue
		end

		if GizmoMode == "Rotation" and (ringName == "ViewRot" or ringName:match("^[XYZ]Rot$")) then
			adornment.Visible = oldRotation and (ringName == "ViewRot" or showRotationAxes)
		end

		if data.class == "ConeHandleAdornment" then
			adornment.Radius = pixelsToStuds * 4.5 * thickness
			adornment.Height = oldPosition and pixelsToStuds * 14 or basis * 0.25
			adornment.CFrame = data.cframe.Rotation
		elseif data.class == "CylinderHandleAdornment" then
			local ringDistance = adornment.Name == "CenterRing" and pixelsToStuds * 8.5
				or distance * (adornment.Parent.Name == "ViewRot" and viewRadius or 1)
			adornment.Radius = adornment.Name == "TrackballHover"
					and ringDistance * (Preferences.get("RotationTrackballSize") or 100) / 100
				or ringDistance
			adornment.InnerRadius = adornment.Name == "TrackballHover" and 0
				or math.max(
					0,
					ringDistance - pixelsToStuds * (GizmoMode == "Rotation" and 2.5 or 2.5)
				)
			adornment.Height = pixelsToStuds
				* (GizmoMode == "Rotation" and adornment.Name ~= "TrackballHover" and 2.5 or 0.3)
			local name = adornment.Parent.Name
			local axis = name == "XRot" and Vector3.xAxis
				or name == "YRot" and Vector3.yAxis
				or Vector3.zAxis
			local normal = (name == "ViewRot" or name == "SCore") and camera.CFrame.LookVector
				or pivotCF:VectorToWorldSpace(axis)
			adornment.CFrame =
				adornment.Adornee.CFrame:ToObjectSpace(CFrame.lookAt(pivotPos, pivotPos + normal))
		elseif data.class == "BoxHandleAdornment" then
			if adornment.Name == "Shaft" then
				local gap = oldPosition and math.min(pixelsToStuds * 22, distance * 0.45)
					or basis * 0.2
				local tipInset = oldPosition and pixelsToStuds * 7 or basis * 0.125
				adornment.Size = Vector3.new(
					pixelsToStuds * 3 * thickness,
					math.max(pixelsToStuds, distance - tipInset - gap),
					pixelsToStuds * 3 * thickness
				)
				adornment.CFrame = CFrame.new(0, (gap - distance - tipInset) * 0.5, 0)
			else
				adornment.Size = Vector3.new(12, 0.25, 12) * pixelsToStuds
				adornment.CFrame = data.cframe and data.cframe.Rotation or CFrame.identity
			end
		elseif data.class == "SphereHandleAdornment" then
			adornment.Radius = data.radius * adornmentScale

			if data.cframe then
				adornment.CFrame = CFrame.new(data.cframe.Position * sizeMultiplier)
					* data.cframe.Rotation
			end
		end
	end
end

function Axis:CleanupOrphans(keepInstance)
	local containers = { workspace }
	for _, child in workspace:GetChildren() do
		if child:IsA("Camera") then
			table.insert(containers, child)
		end
	end

	for _, container in containers do
		for _, child in container:GetChildren() do
			if child.Name == "_EclipseAnimator_Axis" and child ~= keepInstance then
				child:Destroy()
				for mode, cached in cachedAxes do
					if cached == child then
						cachedAxes[mode] = nil
						cachedAxisData[mode] = nil
					end
				end
			end
		end
	end
end

return Axis
