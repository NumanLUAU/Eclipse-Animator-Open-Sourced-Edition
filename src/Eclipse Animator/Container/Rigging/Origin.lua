--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preferences = require("Preferences")
local SelectedRig = require("SelectedRig")
local Focus = require("Focus")
local Parenting = require("Parenting")
local History = require("History")
local Storage = require("KeyframeStorage")
local Data = require("ChunkStore")
local Http = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local Origin = {}
local refs, root, part, base, motor, source, target, window, drag
local follow = true
local located = false
local rest = CFrame.identity
local selectionTarget, lastItem, lastBone
local connections = {}
local generation = 0
local NAME = "EclipseNavigationOrigin"

function Origin.ensure(timeline)
	if not root then
		root = Instance.new("Folder")
		root.Name = NAME
		require("Recovery").mark(root)
		base = Instance.new("Part")
		base.Name = "OriginBase"
		base.Anchored = true
		base.Transparency = 1
		base.CanCollide = false
		base.CanTouch = false
		base.CanQuery = false
		base.Locked = true
		base.Size = Vector3.one
		base.Parent = root
		part = base:Clone()
		part.Name = "Origin"
		part.Size = Vector3.one * 0.4
		part.Parent = root
		part:SetAttribute("EclipseNavigationOrigin", true)
		source = Instance.new("ObjectValue")
		source.Name = "EclipseSourceRig"
		source.Parent = root
		motor = Instance.new("Motor6D")
		motor.Name = "Origin"
		motor.Part0 = base
		motor.Part1 = part
		motor.Parent = base
		local sphere = Instance.new("SphereHandleAdornment")
		sphere.Name = "Center"
		sphere.Adornee = part
		sphere.Radius = 0.12
		sphere.AlwaysOnTop = true
		sphere.ZIndex = 4
		sphere.Color3 = Color3.fromRGB(184, 142, 239)
		sphere.Parent = part
		for _, rotation in
			{
				CFrame.identity,
				CFrame.Angles(math.pi / 2, 0, 0),
				CFrame.Angles(0, math.pi / 2, 0),
			}
		do
			local ring = Instance.new("CylinderHandleAdornment")
			ring.Name = "Ring"
			ring.Adornee = part
			ring.Radius = 0.34
			ring.InnerRadius = 0.30
			ring.Height = 0.025
			ring.CFrame = rotation
			ring.AlwaysOnTop = true
			ring.ZIndex = 3
			ring.Color3 = Color3.fromRGB(184, 142, 239)
			ring.Parent = part
		end

		table.insert(
			connections,
			motor:GetPropertyChangedSignal("C0"):Connect(function()
				part.CFrame = base.CFrame * motor.C0
			end)
		)
	end

	if timeline then
		local raw = timeline:GetState()
		rest = raw.DefaultPose[motor] or rest
		raw.DefaultPose[motor] = rest
		raw.MotorByPart[part] = motor
		raw.ParentingDefaults[motor] = true
	end

	return part, motor
end

function Origin.is(object)
	return object ~= nil and object == part
end

function Origin.motor(object)
	return Origin.is(object) and motor or nil
end

function Origin.selected()
	if not refs or not part then
		return false
	end

	local state = refs.State
	if state.Axis and state.Axis:GetSelectedBone() == part then
		return true
	end

	for item in state.Rig and state.Rig._selectedItems or {} do
		if item.linkedRigInstance == part then
			return true
		end
	end

	return false
end

function Origin.visible()
	return refs ~= nil
		and refs.State.currentRig ~= nil
		and Preferences.get("BlenderCameraBeta") == true
		and Preferences.get("HideOriginBone") ~= true
		and (Preferences.get("OriginAlwaysShowing") == true or Origin.selected())
		and refs.ScreenGui.Enabled
		and refs.Active()
		and not refs.State.PresentationHidden
end

function Origin.center(rig)
	if not rig then
		return CFrame.identity, 4
	end

	local map = refs and refs.State.Timeline and refs.State.Timeline:GetState().MotorByPart or {}

	local function world(object)
		local joint = map[object]
		return joint and Parenting.worldOf(joint, map) or object.CFrame
	end

	local function foot(names)
		for _, name in names do
			local object = rig:FindFirstChild(name, true)
			if object and object:IsA("BasePart") then
				return world(object):PointToWorldSpace(Vector3.new(0, -object.Size.Y * 0.5, 0))
			end
		end
	end

	local left = foot({ "LeftFoot", "Left Leg", "LeftLowerLeg" })
	local right = foot({ "RightFoot", "Right Leg", "RightLowerLeg" })
	if left and right then
		local torso = rig:FindFirstChild("Torso", true) or rig:FindFirstChild("UpperTorso", true)
		local position = (left + right) * 0.5
		local radius = torso
				and torso:IsA("BasePart")
				and (world(torso).Position - position).Magnitude
			or 4
		return CFrame.new(position), math.max(1, radius)
	end

	local bounds, size = Focus.bounds({ rig })
	if rig:IsA("BasePart") then
		return world(rig), math.max(0.05, rig.Size.Magnitude * 0.5)
	end

	local rootPart = rig:IsA("Model") and rig.PrimaryPart
	return CFrame.new(
		rootPart and world(rootPart).Position or bounds and bounds.Position or Vector3.zero
	),
		size and math.max(0.05, size.Magnitude * 0.5) or 4
end

local function selected()
	local state = refs.State
	local item = state.Rig and state.Rig._lastClickedItem
	local bone = state.Axis and state.Axis:GetSelectedBone()
	if item ~= lastItem or bone ~= lastBone then
		if item and item.linkedRigInstance ~= part or bone and bone ~= part then
			selectionTarget = nil
		end

		lastItem, lastBone = item, bone
	end

	local rigs = state.getAllRigs and state.getAllRigs() or { state.currentRig }
	if selectionTarget and table.find(rigs, selectionTarget) then
		return selectionTarget
	end

	local result = SelectedRig.resolve(state)
	return result and table.find(rigs, result) and result or state.currentRig or rigs[1]
end

function Origin.sync()
	if not refs then
		return
	end

	if
		not refs.State.currentRig
		or Preferences.get("BlenderCameraBeta") ~= true
		or not refs.ScreenGui.Enabled
		or not refs.Active()
	then
		if root then
			root.Parent = nil
		end

		return false
	end

	Origin.ensure(refs.State.Timeline)
	local nextTarget = selected()
	local changed = false
	if not target or not target.Parent or follow and nextTarget ~= target then
		target = nextTarget
		changed = true
	end

	if follow or not located then
		base.CFrame = Origin.center(target)
		located = target ~= nil
	end

	source.Value = target
	part.CFrame = base.CFrame * motor.C0
	root.Parent = Origin.visible() and workspace.CurrentCamera or nil
	return changed
end

function Origin.pivot()
	Origin.sync()
	local _, size = Origin.center(target)
	return part and part.Position, size
end

function Origin.apply(timeline, time)
	if not root then
		return
	end

	Origin.ensure(timeline)
	if not drag and motor:GetAttribute("EclipseDisabled") ~= true then
		motor.C0 = timeline:EvaluateMotorC0(motor, time)
	end

	Origin.sync()
end

local function snapshot(timeline)
	return {
		bucket = timeline:_snapshotMotorBucket(motor),
		rest = timeline:GetState().DefaultPose[motor],
		pose = motor.C0,
		follow = follow,
		base = base.CFrame,
	}
end

local function restore(timeline, value)
	timeline:_restoreMotorBucket(motor, value.bucket)
	timeline:GetState().DefaultPose[motor] = value.rest
	rest = value.rest
	follow = value.follow
	base.CFrame = value.base
	located = true
	motor.C0 = value.pose
	Origin.sync()
	if refs then
		refs.State.currentProjectSaved = false
	end
end

function Origin.commit(value, description, changeFollow)
	if not refs or not refs.State.Timeline then
		return
	end

	local timeline = refs.State.Timeline
	Origin.ensure(timeline)
	local before = snapshot(timeline)
	if changeFollow ~= nil then
		follow = changeFollow
	end

	if value then
		motor.C0 = value
		if timeline:GetState().Recording then
			timeline:RecordKeyframeForMotorAtCurrentTime(part, motor, value)
		else
			timeline:GetState().DefaultPose[motor] = value
			rest = value
		end
	end

	Origin.sync()
	local after = snapshot(timeline)
	local current = generation
	History.record(function()
		if generation == current then
			restore(timeline, before)
		end
	end, function()
		if generation == current then
			restore(timeline, after)
		end
	end, description or "Move origin")
	refs.State.currentProjectSaved = false
end

function Origin.reset()
	generation += 1
	if window then
		window:close(true)
		window = nil
	end

	drag = nil
	target = nil
	selectionTarget = nil
	lastItem = nil
	lastBone = nil
	follow = true
	located = false
	rest = CFrame.identity
	if motor then
		motor.C0 = CFrame.identity
		motor:SetAttribute("EclipseDisabled", nil)
		base.CFrame = CFrame.identity
		part.CFrame = CFrame.identity
	end
end

function Origin.shared(timeline)
	Origin.ensure(timeline)
	return {
		follow = follow,
		base = follow and CFrame.identity or base.CFrame,
		rest = timeline:GetState().DefaultPose[motor] or rest,
		disabled = motor:GetAttribute("EclipseDisabled") == true,
	}
end

function Origin.applyShared(timeline, value)
	assert(
		typeof(value.base) == "CFrame" and typeof(value.rest) == "CFrame",
		"Invalid shared origin"
	)
	Origin.ensure(timeline)
	follow = value.follow ~= false
	base.CFrame = value.base
	located = true
	rest = value.rest
	timeline:GetState().DefaultPose[motor] = rest
	motor:SetAttribute("EclipseDisabled", value.disabled == true and true or nil)
end

function Origin.write(container, timeline)
	if not root then
		return
	end

	local old = container:FindFirstChild(NAME)
	if old then
		old:Destroy()
	end

	local raw = timeline:GetState()
	Data.write(
		container,
		NAME,
		Http:JSONEncode({
			version = 1,
			follow = follow,
			base = Storage.encode(base.CFrame),
			pose = Storage.encode(motor.C0),
			rest = Storage.encode(raw.DefaultPose[motor] or motor.C0),
			keys = Storage.encode(raw.Keyframes[motor] or {}),
		})
	)
end

function Origin.read(container, timeline)
	Origin.reset()
	Origin.ensure(timeline)
	timeline:GetState().Keyframes[motor] = nil
	timeline:GetState().DefaultPose[motor] = CFrame.identity
	local saved = container and container:FindFirstChild(NAME)
	if not saved then
		return
	end

	local value = Http:JSONDecode(Data.read(saved))
	assert(value.version == 1, "Unsupported origin data")
	follow = value.follow ~= false
	base.CFrame = Storage.decode(value.base)
	located = true
	local raw = timeline:GetState()
	rest = Storage.decode(value.rest)
	raw.DefaultPose[motor] = rest
	local bucket = Storage.decode(value.keys)
	for frame, key in bucket do
		key.Frame = frame
		key.Time = frame / raw.FPS
		key.Motor = motor
		key.Part = part
	end

	timeline:_restoreMotorBucket(motor, bucket)
	motor.C0 = Storage.decode(value.pose)
end

function Origin.destroyItem(rig)
	local item = rig._originItem
	rig._originItem = nil
	if not item then
		return
	end

	local ui, track = item.uiElement, item.trackElement
	if item.destroy then
		pcall(function()
			item:destroy()
		end)
	end

	if ui then
		ui:Destroy()
	end

	if track then
		track:Destroy()
	end
end

function Origin.createItem(rig, baseItem)
	Origin.destroyItem(rig)

	for _, container in { rig.refs.RigListScroll, rig.refs.KeysRoot } do
		for _, child in container:GetDescendants() do
			if child:GetAttribute("EclipseOriginRow") == true then
				child:Destroy()
			end
		end
	end

	if not rig._primaryRigInstance or Preferences.get("BlenderCameraBeta") ~= true then
		return
	end

	Origin.ensure(rig.refs.Timeline)
	Origin.sync()
	local row = rig.refs.Timeline:CreateTrackRow(part, 0, rig.refs.UIHelpers.SanitizeName)
	local item = baseItem.initialize(
		rig.refs.RigItemTemplate:Clone(),
		"ORIGIN",
		nil,
		row,
		false,
		part,
		"origin"
	)
	item.linkedMotor = motor
	item.linkedBone = part
	item.grandpa = item
	item.uiElement.Parent = rig.refs.RigListScroll
	item.trackElement.Parent = rig.refs.KeysRoot
	item.openedState = true
	motor:SetAttribute("EclipseTransformChannelsOpen", nil)
	item.uiElement:SetAttribute("EclipseOriginRow", true)
	item.trackElement:SetAttribute("EclipseOriginRow", true)
	rig._originItem = item
	return item
end

function Origin.hit(camera, point)
	if not Origin.visible() or not part or not camera then
		return nil
	end

	local screen, onScreen = camera:WorldToViewportPoint(part.Position)
	if onScreen and (Vector2.new(screen.X, screen.Y) - point).Magnitude <= 11 then
		return part
	end

	return nil
end

function Origin.beginDrag(point)
	if not refs or not Origin.hit(workspace.CurrentCamera, point) then
		return false
	end

	local camera = workspace.CurrentCamera
	if refs.State.Rig and refs.State.Rig._originItem then
		refs.State.Rig:SetSingleItemSelection(refs.State.Rig._originItem)
	end

	drag = {
		start = point,
		pose = motor.C0,
		world = part.CFrame,
		camera = camera.CFrame,
		depth = math.max(
			0.05,
			(part.Position - camera.CFrame.Position):Dot(camera.CFrame.LookVector)
		),
		fov = camera.FieldOfView,
		height = camera.ViewportSize.Y,
	}
	return true
end

function Origin.moveDrag(point)
	if not drag then
		return false
	end

	local delta = point - drag.start
	local unit = 2 * drag.depth * math.tan(math.rad(drag.fov) * 0.5) / math.max(1, drag.height)
	local world = drag.world
		+ (drag.camera.RightVector * delta.X - drag.camera.UpVector * delta.Y) * unit
	motor.C0 = base.CFrame:ToObjectSpace(world)
	return true
end

function Origin.endDrag(cancel)
	if not drag then
		return false
	end

	local value = motor.C0
	local before = drag.pose
	drag = nil
	motor.C0 = before
	if not cancel and value ~= before then
		Origin.commit(value)
	end

	return true
end

function Origin.isDragging()
	return drag ~= nil
end

function Origin.openSettings()
	if not refs then
		return
	end

	if window then
		window:close(true)
	end

	local Tool = require("Tool")
	window = Tool.new(
		refs,
		"EclipseOriginSettings",
		"ORIGIN SETTINGS",
		Vector2.new(290, 76),
		false,

		function()
			window = nil
		end
	)
	local frame = window.frame
	local toggle = Tool.make("TextButton", frame, "Follow", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(12, 37),
		ZIndex = 13,
	})
	toggle:SetAttribute("ThemeBg", "TopBtn")
	local box = Tool.make("Frame", toggle, "Checkbox", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 1, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BorderSizePixel = 0,
	})
	box:SetAttribute("ThemeBg", "TopBtn")
	local stroke = Tool.make(
		"UIStroke",
		box,
		"Outline",
		{ Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	)
	stroke:SetAttribute("ThemeStrk", "Strk")
	local check = Tool.label(box, "Check", "✓", UDim2.fromOffset(0, -1), UDim2.fromScale(1, 1))
	check.TextXAlignment = Enum.TextXAlignment.Center
	check.TextSize = 14
	check.Visible = follow
	Tool.label(
		toggle,
		"Label",
		"Follow selected rig",
		UDim2.fromOffset(26, 0),
		UDim2.new(1, -26, 1, 0)
	)
	toggle.MouseEnter:Connect(function()
		toggle.BackgroundTransparency = 0.5
	end)
	toggle.MouseLeave:Connect(function()
		toggle.BackgroundTransparency = 1
	end)
	toggle.Activated:Connect(function()
		Origin.commit(nil, "Origin follow rig", not follow)
		check.Visible = follow
	end)
	require("Theme").applyTree(frame)
end

function Origin.destroy()
	Origin.endDrag(true)
	if window then
		window:close(true)
		window = nil
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	if root then
		root:Destroy()
	end

	refs, root, part, base, motor, source, target = nil, nil, nil, nil, nil, nil, nil
end

function Origin.init(options)
	refs = options
	refs.State.NavigationOrigin = Origin
	table.insert(
		connections,
		Selection.SelectionChanged:Connect(function()
			local rigs = refs.State.getAllRigs and refs.State.getAllRigs() or {}
			for _, object in Selection:Get() do
				for _, rig in rigs do
					if object == rig or object:IsDescendantOf(rig) then
						selectionTarget = rig
						return
					end
				end
			end
		end)
	)
end

return Origin
