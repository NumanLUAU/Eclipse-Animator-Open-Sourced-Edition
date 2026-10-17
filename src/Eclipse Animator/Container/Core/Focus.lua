--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Focus = {}
local RENDER = "EclipseFocusSelection-" .. game:GetService("HttpService"):GenerateGUID(false)
local transition

function Focus.targets(state)
	local targets = {}
	local seen = {}

	local function add(target)
		if typeof(target) == "Instance" and not seen[target] then
			seen[target] = true
			table.insert(targets, target)
		end
	end

	local function fromItem(item)
		local motor = item.fetchMotor and item:fetchMotor()
		if typeof(motor) == "table" and motor.IsEclipseProperty then
			return motor.Rig
		end

		if typeof(motor) == "Instance" then
			if motor:IsA("Motor6D") then
				return motor.Part1 or motor.Part0
			end

			if motor:IsA("Bone") then
				return motor
			end
		end

		return item.linkedRigInstance
	end

	local rig = state.Rig
	if not rig then
		return targets
	end

	for item in rig._selectedItems or {} do
		add(fromItem(item))
	end

	if state.Axis then
		for _, bone in state.Axis:GetSelectedBones() do
			add(rig:GetPartFromBone(state.currentRig, bone))
		end
	end

	if #targets == 0 and rig._lastClickedItem then
		add(fromItem(rig._lastClickedItem))
	end

	return targets
end

function Focus.bounds(targets)
	local minimum, maximum
	for _, target in targets do
		if typeof(target) ~= "Instance" or not target.Parent then
			continue
		end

		local cf, size
		if target:IsA("Model") then
			cf, size = target:GetBoundingBox()
		elseif target:IsA("BasePart") then
			cf, size = target.CFrame, target.Size
		elseif target:IsA("Bone") then
			cf, size = target.TransformedWorldCFrame, Vector3.one
		elseif target:IsA("Attachment") then
			cf, size = target.WorldCFrame, Vector3.one
		end

		if not cf then
			continue
		end

		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local corner = cf:PointToWorldSpace(size * Vector3.new(x, y, z) * 0.5)
					minimum = minimum and minimum:Min(corner) or corner
					maximum = maximum and maximum:Max(corner) or corner
				end
			end
		end
	end

	if minimum then
		return CFrame.new((minimum + maximum) * 0.5), (maximum - minimum):Max(Vector3.one)
	end
end

function Focus.goal(targets, camera)
	local cf, size = Focus.bounds(targets)
	if not cf then
		return
	end

	local rotation = camera.CFrame.Rotation
	local tanY = math.tan(math.rad(camera.FieldOfView) * 0.5)
	local tanX = tanY * math.max(1, camera.ViewportSize.X) / math.max(1, camera.ViewportSize.Y)
	local distance = 0.5
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = rotation:VectorToObjectSpace(size * Vector3.new(x, y, z) * 0.625)
				distance = math.max(
					distance,
					corner.Z + math.abs(corner.X) / tanX,
					corner.Z + math.abs(corner.Y) / tanY,
					corner.Z + 0.5
				)
			end
		end
	end

	return CFrame.new(cf.Position - camera.CFrame.LookVector * distance) * rotation, cf
end

function Focus.isActive()
	return transition ~= nil
end

function Focus.cancel()
	local old = transition
	transition = nil
	Run:UnbindFromRenderStep(RENDER)
	if not old then
		return
	end

	for _, connection in old.connections do
		connection:Disconnect()
	end

	local recovery = require("Recovery")
	local owned = recovery.owns(old.camera)
	local frame, focus = old.camera.CFrame, old.camera.Focus
	old.release()
	if owned and old.camera.Parent and workspace.CurrentCamera == old.camera then
		old.camera.CFrame, old.camera.Focus = frame, focus
	end
end

function Focus.step(dt)
	local current = transition
	if not current then
		return
	end

	local camera = current.camera
	if
		workspace.CurrentCamera ~= camera
		or not camera.Parent
		or (current.allowed and not current.allowed())
	then
		Focus.cancel()
		return
	end

	current.time += math.max(0, dt)
	local t = math.clamp(current.time / 0.14, 0, 1)
	local eased = t * t * (3 - 2 * t)
	camera.CFrame = current.start:Lerp(current.finish, eased)
	camera.Focus = current.startFocus:Lerp(current.finishFocus, eased)
	if t == 1 then
		Focus.cancel()
	end
end

function Focus.focus(targets, camera, allowed)
	if not camera then
		return false
	end

	local finish, finishFocus = Focus.goal(targets, camera)
	if not finish then
		return false
	end

	Focus.cancel()
	local release = require("Recovery").acquire(camera)
	transition = {
		release = release,
		camera = camera,
		cameraType = camera.CameraType,
		start = camera.CFrame,
		startFocus = camera.Focus,
		finish = finish,
		finishFocus = finishFocus,
		time = 0,
		allowed = allowed,
		connections = {},
	}
	camera.CameraType = Enum.CameraType.Scriptable

	local function connect(signal, callback)
		table.insert(transition.connections, signal:Connect(callback))
	end

	connect(Input.InputBegan, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
			or input.UserInputType == Enum.UserInputType.Touch
			or table.find({
				Enum.KeyCode.W,
				Enum.KeyCode.A,
				Enum.KeyCode.S,
				Enum.KeyCode.D,
				Enum.KeyCode.Q,
				Enum.KeyCode.E,
				Enum.KeyCode.Escape,
			}, input.KeyCode)
		then
			Focus.cancel()
		end
	end)
	connect(Input.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			Focus.cancel()
		end
	end)
	connect(Input.WindowFocusReleased, Focus.cancel)
	Run:BindToRenderStep(RENDER, Enum.RenderPriority.Last.Value + 1, function(dt)
		local ok, err = pcall(Focus.step, dt)
		if not ok then
			Focus.cancel()
			warn("Eclipse focus: " .. tostring(err))
		end
	end)
	return true
end

return Focus
