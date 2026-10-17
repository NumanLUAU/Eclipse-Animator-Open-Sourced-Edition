--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local CameraRig = {}
CameraRig.DEFAULT_FOV = 70
CameraRig.DEPTH = 1.2
CameraRig.ASPECT = 16 / 9
CameraRig.ICON = "rbxassetid://132110507088694"

function CameraRig.isRig(rig)
	if typeof(rig) ~= "Instance" or not rig:IsA("Model") then
		return false
	end

	local root = rig:FindFirstChild("RootPart")
	return root ~= nil
		and root:IsA("BasePart")
		and root:FindFirstChild("CamPart") ~= nil
		and root:FindFirstChild("FovPart") ~= nil
		and rig:FindFirstChild("CamPart") ~= nil
		and rig:FindFirstChild("FovPart") ~= nil
		and rig:FindFirstChild("FieldOfView") ~= nil
end

function CameraRig.owner(object)
	if typeof(object) ~= "Instance" then
		return nil
	end

	while object and object ~= workspace do
		if CameraRig.isRig(object) then
			return object
		end

		object = object.Parent
	end

	return nil
end

function CameraRig.motor(rig, name)
	local root = rig and rig:FindFirstChild("RootPart")
	local motor = root and root:FindFirstChild(name)
	return motor and motor:IsA("Motor6D") and motor.Part0 and motor.Part1 and motor or nil
end

function CameraRig.isFov(motor)
	return typeof(motor) == "Instance"
		and motor:IsA("Motor6D")
		and motor.Name == "FovPart"
		and CameraRig.owner(motor) ~= nil
end

function CameraRig.isTransform(motor)
	return typeof(motor) == "Instance"
		and motor:IsA("Motor6D")
		and motor.Name == "CamPart"
		and CameraRig.owner(motor) ~= nil
end

function CameraRig.displayDepth(fov)
	return math.tan(math.rad(CameraRig.DEFAULT_FOV) * 0.5)
		* CameraRig.DEPTH
		/ math.tan(math.rad(CameraRig.clamp(fov)) * 0.5)
end

function CameraRig.gizmoFrame(rig)
	return CameraRig.viewFrame(rig)
end

function CameraRig.clamp(value)
	return typeof(value) == "number"
			and value == value
			and math.abs(value) < math.huge
			and math.clamp(value, 1, 120)
		or 70
end

function CameraRig.default(rig)
	local folder = rig and rig:FindFirstChild("FieldOfView")
	local value = folder and folder:FindFirstChild("default")
	return CameraRig.clamp(value and value:IsA("NumberValue") and value.Value or 70)
end

function CameraRig.decode(motor, c0)
	return CameraRig.clamp(CameraRig.default(CameraRig.owner(motor)) + c0.Y)
end

function CameraRig.encode(motor, value)
	return CFrame.new(0, CameraRig.clamp(value) - CameraRig.default(CameraRig.owner(motor)), 0)
end

function CameraRig.attachedImportedFov(target, time)
	if not target or not target:IsA("BasePart") or target.Name ~= "Camera" then
		return nil
	end

	local rig = target.Parent
	local root = rig and rig:IsA("Model") and rig:FindFirstChild("HumanoidRootPart")
	local view = root and root:FindFirstChild("Camera")
	local motor = root and root:FindFirstChild("FovPart")
	local part = rig and rig:FindFirstChild("FovPart")
	if
		not root
		or not root:IsA("BasePart")
		or not view
		or not view:IsA("Motor6D")
		or view.Part0 ~= root
		or view.Part1 ~= target
		or not motor
		or not motor:IsA("Motor6D")
		or motor.Part0 ~= root
		or motor.Part1 ~= part
		or not part
		or not part:IsA("BasePart")
		or motor:GetAttribute("EclipseDisabled")
	then
		return nil
	end

	local raw = require("RawState").Timeline
	local state = require("State")
	local layers = require("Layers")
	local value = motor.C0
	if time ~= nil and state.Timeline then
		value = layers.has(raw) and layers.c0(state.Timeline, motor, time)
			or state.Timeline:EvaluateMotorC0(motor, time, raw.Keyframes[motor])
	end

	local rest = raw.DefaultPose[motor]
		or motor:GetAttribute("EclipseAnimatorDefaultC0")
		or CFrame.identity
	local degrees = -(rest:ToObjectSpace(value)).Y
	if degrees <= 0 or degrees ~= degrees or degrees == math.huge then
		return nil
	end

	return CameraRig.clamp(degrees)
end

function CameraRig.fov(rig, time, visited)
	visited = visited or {}
	if visited[rig] then
		return CameraRig.default(rig)
	end

	visited[rig] = true
	local Raw = require("RawState").Timeline
	local State = require("State")
	local motor = CameraRig.motor(rig, "FovPart")
	local Layers = require("Layers")
	local bucket = motor and Raw.Keyframes[motor]
	local authored = false
	local buckets = { bucket or {} }
	if motor and Layers.has(Raw) then
		buckets = {}
		for _, layer in Layers.stack(Raw, rig) do
			if not layer.muted then
				table.insert(buckets, layer.keys[motor] or {})
			end
		end
	end

	for _, keys in buckets do
		for _, key in keys do
			if not key.Disabled and (key.Frame ~= 0 or key.C0 ~= CFrame.identity) then
				authored = true
				break
			end
		end
	end

	if not authored then
		local target = require("Target").attachmentObject(rig, time)
		local source = target and CameraRig.owner(target)
		if source and source ~= rig then
			return CameraRig.fov(source, time, visited)
		end

		local imported = CameraRig.attachedImportedFov(target, time)
		if imported then
			return imported
		end
	end

	if time ~= nil and motor and State.Timeline then
		local value = Layers.has(Raw) and Layers.c0(State.Timeline, motor, time)
			or State.Timeline:EvaluateMotorC0(motor, time, bucket)
		return CameraRig.decode(motor, value)
	end

	local motor = CameraRig.motor(rig, "FovPart")
	return motor and CameraRig.decode(motor, motor.C0) or CameraRig.default(rig)
end

function CameraRig.poseFrame(rig)
	local motor = CameraRig.motor(rig, "CamPart")
	return motor and motor.Part0.CFrame * motor.C0 * motor.C1:Inverse() or CFrame.identity
end

function CameraRig.frame(rig)
	return require("Target").frame(rig, CameraRig.poseFrame(rig))
end

function CameraRig.viewFrame(rig, fov, time)
	local depth = rig:GetAttribute("EclipseCameraTransferRig") and 0 or CameraRig.DEPTH
	local front = CameraRig.poseFrame(rig) * CFrame.new(0, 0, -depth)
	return require("Target").frame(rig, front, time)
end

function CameraRig.displayFrame(rig, fov)
	return CameraRig.viewFrame(rig, fov)
end

function CameraRig.authoredFromView(view, fov)
	return view * CFrame.new(0, 0, CameraRig.DEPTH)
end

function CameraRig.renderFrame(rig, fov, unshaken, time)
	local timeline = require("State").Timeline
	if timeline and timeline.GetPoseTime then
		time = timeline:GetPoseTime(time or timeline:GetState().CurrentTime)
	end

	local view = CameraRig.viewFrame(rig, nil, time)
	if not unshaken and CameraRig.viewOffset then
		view *= CameraRig.viewOffset(rig, time)
	end

	return require("fov").render(
		view,
		CameraRig.clamp(fov or CameraRig.fov(rig, time)),
		rig:GetAttribute("EclipseOrthographic") == true
	)
end

function CameraRig.spawnTarget(state)
	local selected = require("SelectedRig").resolve(state)

	local function usable(rig)
		return typeof(rig) == "Instance"
			and rig.Parent
			and (rig:IsA("Model") or rig:IsA("BasePart"))
			and not CameraRig.owner(rig)
	end

	if usable(selected) then
		return selected
	end

	for _, rig in state.getAllRigs() do
		if usable(rig) then
			return rig
		end
	end

	return nil
end

function CameraRig.spawnFrame(scope, view)
	if
		typeof(scope) == "Instance"
		and scope ~= workspace
		and not CameraRig.owner(scope)
		and (scope:IsA("Model") or scope:IsA("BasePart"))
	then
		local root = scope:IsA("BasePart") and scope
			or scope:FindFirstChild("HumanoidRootPart")
			or scope.PrimaryPart
		local pivot = root and root:IsA("BasePart") and root.CFrame or scope:GetPivot()
		local forward = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
		if forward.Magnitude < 0.001 then
			forward = Vector3.yAxis:Cross(pivot.RightVector)
		end

		if forward.Magnitude < 0.001 then
			forward = Vector3.new(0, 0, -1)
		end

		forward = forward.Unit
		local basis = CFrame.lookAt(pivot.Position, pivot.Position + forward, Vector3.yAxis)
		local low, high

		local function include(part)
			if not part:IsA("BasePart") or part.Transparency >= 1 then
				return
			end

			local frame = basis:ToObjectSpace(part.CFrame)
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local point =
							frame:PointToWorldSpace(part.Size * Vector3.new(x, y, z) * 0.5)
						low = low and low:Min(point) or point
						high = high and high:Max(point) or point
					end
				end
			end
		end

		if scope:IsA("BasePart") then
			include(scope)
		end

		for _, part in require("RigTraversal").rigDescendants(scope) do
			include(part)
		end

		if low then
			local size = high - low
			local center = basis:PointToWorldSpace((low + high) * 0.5)
			local halfFrame = math.max(size.Y * 0.5, size.X * 0.5 / CameraRig.ASPECT)
			local distance = math.max(
				6,
				size.Z * 0.5
					+ halfFrame / math.tan(math.rad(CameraRig.DEFAULT_FOV) * 0.5) * 1.15
					+ CameraRig.DEPTH
			)
			local position = center + forward * distance
			return CFrame.lookAt(position, center, Vector3.yAxis)
		end
	end

	local direction = Vector3.new(view.LookVector.X, 0, view.LookVector.Z)
	if direction.Magnitude < 0.001 then
		direction = Vector3.yAxis:Cross(view.RightVector)
	end

	if direction.Magnitude < 0.001 then
		direction = Vector3.new(0, 0, -1)
	end

	direction = direction.Unit
	local position = view.Position + view.LookVector * 12
	return CFrame.lookAt(position, position + direction, Vector3.yAxis)
end

function CameraRig.timelineName(rig)
	if not CameraRig.isRig(rig) then
		return rig.Name
	end

	local index = rig:GetAttribute("EclipseCameraIndex")
	if typeof(index) == "number" and index >= 1 then
		return index == 1 and "Camera" or "Camera " .. index
	end

	return (rig.Name:gsub(" %- .*$", ""))
end

function CameraRig.nextName(rigs)
	local used = {}
	for _, rig in rigs do
		if rig.Parent then
			local name = string.lower(rig.Name)
			local index = rig:GetAttribute("EclipseCameraIndex")
				or (name == "camera" and 1 or tonumber(string.match(name, "^camera (%d+)$")))
			if index then
				used[index] = true
			end
		end
	end

	local index = 1
	while used[index] do
		index += 1
	end

	return index == 1 and "Camera" or "Camera " .. index
end

function CameraRig.create(cf, name)
	local model = Instance.new("Model")

	model.Name = name or "Camera"
	model:SetAttribute("EclipseCamera", true)

	local function part(name)
		local item = Instance.new("Part")

		item.Name, item.CFrame = name, cf
		item.Size = Vector3.new(0.35, 0.35, 0.35)
		item.Anchored = name == "RootPart"
		item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
		item.Transparency = 1
		item.CastShadow = false
		item.Parent = model
		return item
	end

	local root = part("RootPart")
	model.PrimaryPart = root
	for _, name in { "CamPart", "FovPart" } do
		local target = part(name)
		local motor = Instance.new("Motor6D")

		motor.Name, motor.Part0, motor.Part1 = name, root, target
		motor.Parent = root
	end

	local values = Instance.new("Folder")

	values.Name, values.Parent = "FieldOfView", model
	local default = Instance.new("NumberValue")

	default.Name, default.Value, default.Parent = "default", 70, values
	local controller = Instance.new("AnimationController")

	controller.Parent = model
	local animator = Instance.new("Animator")

	animator.Parent = controller
	local saves = Instance.new("ObjectValue")

	saves.Name, saves.Parent = "AnimSaves", model
	require("Target").ensure(model)
	model:SetAttribute("EclipseTrackTarget", true)
	model:SetAttribute("EclipseCamTargetDefaultEnabled", false)
	return model
end

function CameraRig.createTransfer(view, name)
	local model = CameraRig.create(view, name or "Camera Rig")
	model:SetAttribute("EclipseCameraTransferRig", true)
	model:SetAttribute("EclipseTrackTarget", false)
	local body = model.CamPart
	body.Size = Vector3.new(1.1, 0.7, 0.65)
	body.Color = Color3.fromRGB(62, 64, 74)
	body.Material = Enum.Material.SmoothPlastic
	body.Transparency = 0
	body.CanQuery = true
	model.FovPart.Size = Vector3.new(0.22, 0.22, 0.22)
	model.FovPart.Color = Color3.fromRGB(168, 108, 255)
	model.FovPart.Transparency = 0.3
	model.FovPart.CanQuery = true
	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Size = Vector3.new(0.55, 0.4, 0.15)
	lens.Color = Color3.fromRGB(81, 185, 210)
	lens.Material = Enum.Material.Glass
	lens.CanCollide, lens.CanTouch, lens.CanQuery = false, false, false
	lens.Massless = true
	lens.CFrame = view * CFrame.new(0, 0, -0.4)
	lens.Parent = model
	local weld = Instance.new("Weld")
	weld.Name = "LensWeld"
	weld.Part0 = body
	weld.Part1 = lens
	weld.C0 = CFrame.new(0, 0, -0.4)
	weld.Parent = lens
	return model
end

function CameraRig.write(entry, rig)
	if not CameraRig.isRig(rig) then
		return
	end

	entry:SetAttribute("EclipseCamera", true)
	entry:SetAttribute("EclipseCameraTransferRig", rig:GetAttribute("EclipseCameraTransferRig"))
	entry:SetAttribute("CameraRoot", rig.RootPart.CFrame)
	entry:SetAttribute("CameraDefaultFOV", CameraRig.default(rig))
	entry:SetAttribute("CameraProject", rig:GetAttribute("EclipseCameraProject"))
	entry:SetAttribute("CameraIndex", rig:GetAttribute("EclipseCameraIndex"))
	entry:SetAttribute("CameraTrackTarget", rig:GetAttribute("EclipseTrackTarget") == true)
	entry:SetAttribute(
		"CameraTargetDefaultEnabled",
		rig:GetAttribute("EclipseCamTargetDefaultEnabled")
	)
	entry:SetAttribute("CameraHideTarget", rig:GetAttribute("EclipseHideCamTarget") == true)
	entry:SetAttribute("CameraOrthographic", rig:GetAttribute("EclipseOrthographic") == true)
	entry:SetAttribute("CameraFPV", rig:GetAttribute("EclipseFPV"))
	entry:SetAttribute("CameraFPVHead", rig:GetAttribute("EclipseFPVHead"))
	local target = CameraRig.motor(rig, "CamTarget")
	if target then
		entry:SetAttribute(
			"CameraTargetDefault",
			target:GetAttribute("EclipseAnimatorDefaultC0") or target.C0
		)
	end
end

local CAMERA_STORAGE = "EclipseCameras"
local PARKED_PARENT = "EclipseCameraParkedParent"

function CameraRig.park(rig)
	return false
end

function CameraRig.resume(rig, scope)
	if not CameraRig.isRig(rig) or rig:GetAttribute("EclipseCameraParked") ~= true then
		return rig
	end

	local storage = require("root").get(CAMERA_STORAGE, false)
	if not storage or rig.Parent ~= storage then
		return rig
	end

	local reference = rig:FindFirstChild(PARKED_PARENT)
	local parent = reference and reference:IsA("ObjectValue") and reference.Value
	if not parent or parent ~= workspace and not parent:IsDescendantOf(workspace) then
		parent = workspace
	end

	rig.Parent = scope or parent
	rig:SetAttribute("EclipseCameraParked", nil)
	if reference and reference:IsA("ObjectValue") then
		reference:Destroy()
	end

	return rig
end

function CameraRig.restore(entry, scope)
	if entry:GetAttribute("EclipseCamera") ~= true then
		return nil
	end

	local storage = require("root").get(CAMERA_STORAGE, false)
	local id = entry:GetAttribute("RigId")
	local found
	if storage and type(id) == "string" and id ~= "" then
		for _, candidate in storage:GetChildren() do
			if
				CameraRig.isRig(candidate)
				and candidate:GetAttribute("EclipseCameraParked") == true
				and candidate:GetAttribute("EclipseTrackId") == id
			then
				if found then
					found = nil
					break
				end

				found = candidate
			end
		end
	end

	if found then
		return CameraRig.resume(found, scope ~= workspace and scope or nil)
	end

	local cf = entry:GetAttribute("CameraRoot")
	local create = entry:GetAttribute("EclipseCameraTransferRig") and CameraRig.createTransfer
		or CameraRig.create
	local rig = create(
		typeof(cf) == "CFrame" and cf or CFrame.identity,
		entry:GetAttribute("RigName") or entry.Name
	)
	rig.FieldOfView.default.Value = CameraRig.clamp(entry:GetAttribute("CameraDefaultFOV"))
	rig:SetAttribute("EclipseTrackId", entry:GetAttribute("RigId"))
	rig:SetAttribute("EclipseCameraProject", entry:GetAttribute("CameraProject"))
	rig:SetAttribute("EclipseCameraIndex", entry:GetAttribute("CameraIndex"))
	rig:SetAttribute("EclipseTrackTarget", entry:GetAttribute("CameraTrackTarget") == true)
	rig:SetAttribute(
		"EclipseCamTargetDefaultEnabled",
		entry:GetAttribute("CameraTargetDefaultEnabled")
	)
	rig:SetAttribute("EclipseHideCamTarget", entry:GetAttribute("CameraHideTarget") == true)
	rig:SetAttribute("EclipseOrthographic", entry:GetAttribute("CameraOrthographic") == true)
	rig:SetAttribute("EclipseFPV", entry:GetAttribute("CameraFPV"))
	rig:SetAttribute("EclipseFPVHead", entry:GetAttribute("CameraFPVHead"))
	local target = CameraRig.motor(rig, "CamTarget")
	local targetDefault = entry:GetAttribute("CameraTargetDefault")
	if typeof(targetDefault) == "CFrame" then
		target.C0 = targetDefault
		target:SetAttribute("EclipseAnimatorDefaultC0", targetDefault)
	end

	local animation = entry:FindFirstChild("Animation")
	if animation and animation:IsA("KeyframeSequence") then
		local copy = animation:Clone()
		local project = entry.Parent and entry.Parent.Parent
		copy.Name = project and project:GetAttribute("EclipseSave") == true and project.Name
			or animation.Name
		copy.Parent = rig.AnimSaves
	end

	rig.Parent = scope or workspace
	local project = entry.Parent and entry.Parent.Parent
	CameraRig.organize(
		rig,
		project and project:GetAttribute("EclipseSave") and project.Name or nil,
		scope
	)
	return rig
end

const CAMERA_MARKS = {
	"EclipseCameraOwned",
	"EclipseCameraTypeBeforeControl",
	"EclipseCameraFOVBeforeControl",
	"EclipseCameraFOVModeBeforeControl",
	"EclipseCameraLease",
}

local function enumNamed(enum, name, fallback)
	for _, value in enum:GetEnumItems() do
		if value.Name == name then
			return value
		end
	end

	return fallback
end

local function leased(camera)
	const folder = game:GetService("CoreGui"):FindFirstChild("EclipseCameraLeases")
	for _, lease in folder and folder:GetChildren() or {} do
		if lease:IsA("ObjectValue") and lease.Value == camera then
			return true
		end
	end

	return false
end

function CameraRig.releaseCamera(camera)
	if
		typeof(camera) ~= "Instance"
		or not camera:IsA("Camera")
		or not camera.Parent
		or camera.CameraType ~= Enum.CameraType.Scriptable
	then
		return false
	end

	if require("Recovery").owns(camera) or leased(camera) then
		return false
	end

	const kind = enumNamed(
		Enum.CameraType,
		camera:GetAttribute("EclipseCameraTypeBeforeControl"),
		Enum.CameraType.Custom
	)
	camera.CameraType = kind == Enum.CameraType.Scriptable and Enum.CameraType.Custom or kind
	const fov = camera:GetAttribute("EclipseCameraFOVBeforeControl")
	if typeof(fov) == "number" and fov == fov and fov >= 1 and fov <= 120 then
		camera.FieldOfViewMode = enumNamed(
			Enum.FieldOfViewMode,
			camera:GetAttribute("EclipseCameraFOVModeBeforeControl"),
			camera.FieldOfViewMode
		)
		camera.FieldOfView = fov
	end

	for _, name in CAMERA_MARKS do
		camera:SetAttribute(name, nil)
	end

	return true
end

function CameraRig.startView(rig, getCamera)
	getCamera = getCamera or function()
		return workspace.CurrentCamera
	end

	local saved = {}
	local live = true
	local session = {}

	function session.setRig(nextRig)
		if not live or not CameraRig.isRig(nextRig) or not nextRig.Parent then
			return false
		end

		rig = nextRig
		return true
	end

	function session.step(fov)
		if not live or not rig.Parent then
			return false
		end

		local camera = getCamera()
		if not camera then
			return false
		end

		if not saved[camera] then
			const Recovery = require("Recovery")
			if camera.CameraType == Enum.CameraType.Scriptable and not Recovery.owns(camera) then
				CameraRig.releaseCamera(camera)
				if camera.CameraType == Enum.CameraType.Scriptable and not Recovery.owns(camera) then
					camera.CameraType = Enum.CameraType.Custom
				end
			end

			local release = Recovery.acquire(camera)
			saved[camera] = {
				release = release,
				CameraType = camera.CameraType,
				CFrame = camera.CFrame,
				Focus = camera.Focus,
				FieldOfView = camera.FieldOfView,
				FieldOfViewMode = camera.FieldOfViewMode,
				CameraSubject = camera.CameraSubject,
			}
		end

		local cf, renderFov, focus = CameraRig.renderFrame(rig, fov)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
		camera.CFrame, camera.Focus = cf, focus
		camera.FieldOfView = renderFov
		local Projection = require("fov")
		Projection.setViewing(camera, rig, fov)
		if rig:GetAttribute("EclipseOrthographic") == true then
			local view = CameraRig.viewFrame(rig)
			Projection.cullBehind(view, (cf.Position - view.Position).Magnitude)
		else
			Projection.cullBehind(nil)
		end

		return true
	end

	function session.stop()
		if not live then
			return
		end

		live = false
		require("fov").cullBehind(nil)
		for camera, values in saved do
			require("fov").setViewing(camera, nil)
			pcall(function()
				camera.CFrame, camera.Focus = values.CFrame, values.Focus
				camera.FieldOfViewMode, camera.FieldOfView =
					values.FieldOfViewMode, values.FieldOfView
				camera.CameraSubject, camera.CameraType = values.CameraSubject, values.CameraType
			end)
			values.release()
			pcall(CameraRig.releaseCamera, camera)
		end

		table.clear(saved)
	end

	return session
end

local CAMERA_FOLDER = "Eclipse Cameras"
function CameraRig.organize(rig, projectName, scope)
	scope = scope or workspace
	if not CameraRig.isRig(rig) or rig:GetAttribute("EclipseCamera") ~= true then
		return rig
	end

	if rig.Parent and not rig:IsDescendantOf(scope) then
		return rig
	end

	local folder = scope:FindFirstChild(CAMERA_FOLDER)
	if folder and not folder:IsA("Folder") then
		return rig
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CAMERA_FOLDER
		folder.Parent = scope
	end

	local source = rig:FindFirstChild("EclipseCameraSource")
	source = source and source:IsA("ObjectValue") and source.Value
	local linkedName = CameraRig.isRig(source) and source:GetAttribute("EclipseCameraProject")
	projectName = type(projectName) == "string" and projectName:match("%S") and projectName
		or linkedName
		or rig:GetAttribute("EclipseCameraProject")
	if type(projectName) ~= "string" or not projectName:match("%S") then
		projectName = nil
	end

	if not projectName then
		local names = {}
		local saves = rig:FindFirstChild("AnimSaves")
		for _, s in saves and saves:GetChildren() or {} do
			if s:IsA("KeyframeSequence") then
				table.insert(names, s.Name)
			end
		end

		table.sort(names)
		projectName = names[1] or "Eclipse Project"
	end

	local index = rig:GetAttribute("EclipseCameraProject") == projectName
			and rig:GetAttribute("EclipseCameraIndex")
		or nil
	local used = {}
	for _, other in folder:GetChildren() do
		if other ~= rig and other:GetAttribute("EclipseCameraProject") == projectName then
			local i = other:GetAttribute("EclipseCameraIndex")
			if i then
				used[i] = true
			end
		end
	end

	if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or used[index] then
		index = 1
		while used[index] do
			index += 1
		end
	end

	if not rig:GetAttribute("EclipseCameraOriginalName") then
		rig:SetAttribute("EclipseCameraOriginalName", rig.Name)
	end

	rig:SetAttribute("EclipseCameraProject", projectName)
	rig:SetAttribute("EclipseCameraIndex", index)
	rig.Name = (index == 1 and "Camera" or "Camera " .. index) .. " - " .. projectName
	rig.Parent = folder

	return rig
end

function CameraRig.organizeAll(scope)
	scope = scope or workspace
	local names = {}
	if scope == workspace then
		local storage = game:GetService("ServerStorage")
		local root = storage:FindFirstChild("Eclipse Animator Saves")
		local saves = root and root:FindFirstChild("EclipseAnimator_Saves")
			or storage:FindFirstChild("EclipseAnimator_Saves")
		for _, entry in saves and saves:GetDescendants() or {} do
			local id = entry:GetAttribute("RigId")
			local project = entry.Parent and entry.Parent.Parent
			if
				id
				and entry:GetAttribute("EclipseCamera")
				and project
				and project:GetAttribute("EclipseSave")
			then
				if names[id] == nil then
					names[id] = project.Name
				elseif names[id] ~= project.Name then
					names[id] = false
				end
			end
		end
	end

	local count = 0
	for _, rig in scope:GetDescendants() do
		if CameraRig.isRig(rig) and rig:GetAttribute("EclipseCamera") == true then
			local source = rig:FindFirstChild("EclipseCameraSource")
			source = source and source:IsA("ObjectValue") and source.Value
			CameraRig.organize(
				rig,
				names[rig:GetAttribute("EclipseTrackId")]
					or source and names[source:GetAttribute("EclipseTrackId")],
				scope
			)
			count += 1
		end
	end

	return count
end

function CameraRig.nativeCopy(sequence, rig, defaults, budget)
	local origin = sequence:GetAttribute("EclipseCameraRoot")
	assert(typeof(origin) == "CFrame", "Export the evaluated camera first")
	local motor = assert(CameraRig.motor(rig, "CamPart"))
	local rest = defaults and defaults[motor]
		or motor:GetAttribute("EclipseRigRestC0")
		or CFrame.identity
	local base = motor.Part0.CFrame * rest
	local copy = sequence:Clone()
	copy:SetAttribute("EclipseCameraRoot", base)
	copy:SetAttribute("EclipseCameraNativeC1", motor.C1)
	copy:SetAttribute("EclipseCameraExportVersion", 2)
	for _, frame in copy:GetKeyframes() do
		for _, pose in frame:GetDescendants() do
			if pose:IsA("Pose") and pose.Name == "CamPart" then
				pose.CFrame = (base:ToObjectSpace(origin * pose.CFrame) * motor.C1):Orthonormalize()
			end
		end

		if budget then
			budget()
		end
	end

	return copy
end

return CameraRig
