--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Input = require("UserInputService")
local Shortcuts = require("Shortcuts")
local Objects = require("Objects")
local Properties = require("Properties")
local Edit = require("BlenderEdit")
local History = require("History")
local Cursor = require("RotateCursor")
local Run = game:GetService("RunService")
local Handles = {}
local refs, target, drag, resize, hovered, proxy
local connections, points = {}, {}

local function active()
	return refs
		and refs.ScreenGui.Enabled
		and refs.AnimatorFrame.Visible
		and not refs.State.PresentationHidden
		and refs.Active()
		and not refs.State.Timeline:GetState().Playing
		and not Edit.blocked()
end

local function owner(part)
	local m = part and part.Parent
	return Objects.kind(m) == "Letterbox"
			and m:GetAttribute("EffectStyle") == "Solid"
			and (part.Name == "Top" or part.Name == "Bottom")
			and m
		or nil
end

local function valid(part)
	local m = owner(part)
	return m
		and table.find(refs.State.getAllRigs(), m)
		and m:IsDescendantOf(workspace)
		and part:GetAttribute("EclipseEffectVisible") == true
end

local function joint(part)
	local m = owner(part)
	local root = m and m:FindFirstChild("EclipseRigRoot")
	return root and root:FindFirstChild(part.Name)
end

function Handles.isEditing()
	return drag ~= nil
end

function Handles.select(part)
	if target == part then
		return
	end

	Handles.finish(true)
	target = part
	if part then
		if refs.State.PropertyGizmo then
			refs.State.PropertyGizmo.select(nil)
		end

		if refs.State.Axis then
			refs.State.Axis:SelectBone(nil)
		end
	end
end

function Handles.begin(part, mode, point)
	part = part or target
	if drag or not active() or not valid(part) or Input:GetFocusedTextBox() or Input.inWidget() then
		return false
	end

	local motor = joint(part)
	if not motor then
		return false
	end

	if refs.Finalize then
		refs.Finalize()
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local model = owner(part)
	local legacy = Properties.enabled(model, part.Name .. "Size")
			and Properties.enable(model, part.Name .. "Size", true)
		or nil
	target = part
	drag = {
		part = part,
		motor = motor,
		legacy = legacy,
		model = model,
		size = part.Size,
		mode = mode or "pointer",
		point = point or Input:GetMouseLocation(),
		frame = timeline:TimeToFrame(raw.CurrentTime),
		before = timeline:_snapshotMotorBucket(motor),
		legacyBefore = legacy and timeline:_snapshotMotorBucket(legacy),
	}
	if mode ~= "handles" then
		Cursor.start(
			(part.CFrame * CFrame.new(0, (part.Name == "Top" and -1 or 1) * part.Size.Y * 0.5, 0)).Position,
			true
		)
	end

	return true
end

function Handles.change(factor, axis)
	if not drag or not drag.part.Parent then
		return
	end

	local s = drag.size
	factor = math.clamp(factor, 0.01, 100)
	drag.part.Size = Vector3.new(
		axis == "Y" and s.X or math.max(0.001, s.X * factor),
		axis == "X" and s.Y or math.max(0.001, s.Y * factor),
		s.Z
	)
end

function Handles.finish(cancel)
	if not drag then
		return false
	end

	local d = drag
	drag = nil
	Cursor.stop()
	if not d.part.Parent then
		return true
	end

	if cancel then
		d.part.Size = d.size
		return true
	end

	local size = d.part.Size
	if size == d.size then
		return true
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	if timeline:IsRecording() then
		timeline:RecordPartialKeyframeForMotorAtCurrentTime(
			d.part,
			d.motor,
			d.motor.C0,
			{ "scale_x", "scale_y" },
			refs.State.UIHelpers.SanitizeName,
			{ Frame = d.frame }
		)
		if d.legacy then
			timeline:RecordKeyframeForMotorAtCurrentTime(
				d.legacy.Part1,
				d.legacy,
				Properties.encode(size),
				{ Frame = d.frame, PropertyValue = size },
				refs.State.UIHelpers.SanitizeName
			)
		end

		local after = timeline:_snapshotMotorBucket(d.motor)
		local legacyAfter = d.legacy and timeline:_snapshotMotorBucket(d.legacy)

		local function apply(bucket, legacy, value)
			if not d.part.Parent then
				return
			end

			timeline:_restoreMotorBucket(d.motor, bucket)
			if d.legacy then
				timeline:_restoreMotorBucket(d.legacy, legacy)
			end

			timeline:ApplyPoseAtTime(d.model, raw.CurrentTime, { OnlyRig = true })
			if timeline:TimeToFrame(raw.CurrentTime) == d.frame then
				d.part.Size = value
			end

			refs.State.currentProjectSaved = false
		end

		History.record(function()
			apply(d.before, d.legacyBefore, d.size)
		end, function()
			apply(after, legacyAfter, size)
		end, "Resize " .. d.part.Name .. " bar")
	else
		History.record(function()
			if d.part.Parent then
				d.part.Size = d.size
			end
		end, function()
			if d.part.Parent then
				d.part.Size = size
			end
		end, "Resize " .. d.part.Name .. " bar")
	end

	refs.State.currentProjectSaved = false
	return true
end

function Handles.start()
	if not target then
		return false
	end

	return Handles.begin(target, "pointer")
end

local function hit(point)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local best, distance
	for part, adornment in points do
		if adornment.Visible then
			local screen, visible =
				camera:WorldToViewportPoint((part.CFrame * adornment.CFrame).Position)
			local gap = (Vector2.new(screen.X, screen.Y) - Vector2.new(point.X, point.Y)).Magnitude
			if visible and gap <= 13 and (not distance or gap < distance) then
				best, distance = part, gap
			end
		end
	end

	return best
end

function Handles.input(input, processed)
	if drag then
		if
			Shortcuts.matches("Cancel", input)
			or input.UserInputType == Enum.UserInputType.MouseButton2
		then
			Handles.finish(true)
		elseif
			drag.mode == "pointer"
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or Shortcuts.matches("ConfirmTransform", input)
				or Shortcuts.matches("ConfirmTransformAlternate", input)
			)
		then
			Handles.finish(false)
		end

		return true
	end

	if processed or not active() or Input:GetFocusedTextBox() or Input.inWidget() then
		return false
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if hovered and target then
			return true
		end

		local part = hit(Input:GetMouseLocation())
		if part then
			Handles.select(part)
			return true
		end

		Handles.select(nil)
	end

	return false
end

function Handles.step()
	local shown = active()
	local keep = {}
	local camera = workspace.CurrentCamera
	if not shown then
		Handles.finish(true)
		target = nil
	end

	if target and not valid(target) then
		Handles.select(nil)
	end

	if shown then
		for _, model in refs.State.getAllRigs() do
			if
				Objects.kind(model) == "Letterbox"
				and model:GetAttribute("EffectStyle") == "Solid"
			then
				for _, name in { "Top", "Bottom" } do
					local part = model:FindFirstChild(name)
					if part and valid(part) then
						keep[part] = true
						local point = points[part]
						if not point then
							point = Instance.new("SphereHandleAdornment")
							point.Name = name .. "ResizeHandle"
							point.Adornee = part
							point.AlwaysOnTop = true
							point.ZIndex = 5
							point.Parent = refs.ScreenGui
							points[part] = point
						end

						point.CFrame =
							CFrame.new(0, (name == "Top" and -1 or 1) * part.Size.Y * 0.5, 0.025)
						local distance = camera
								and (camera.CFrame.Position - (part.CFrame * point.CFrame).Position).Magnitude
							or 1
						point.Radius = math.clamp(distance * 0.008, 0.018, 0.5)
						point.Visible = true
						point.Transparency = 0.05
						point.Color3 = target == part and Color3.fromRGB(255, 211, 95)
							or Color3.fromRGB(242, 171, 196)
					end
				end
			end
		end
	end

	for part, point in points do
		if not keep[part] then
			point:Destroy()
			points[part] = nil
		end
	end

	if drag then
		if not valid(drag.part) then
			Handles.finish(true)
		elseif drag.mode == "pointer" then
			Handles.change(math.exp((drag.point.Y - Input:GetMouseLocation().Y) / 180))
		end
	end

	if proxy and shown and target and points[target] then
		local point = points[target]
		proxy.Size = Vector3.one * math.max(0.01, point.Radius * 2)
		proxy.CFrame = target.CFrame * point.CFrame
	end

	if resize then
		resize.Adornee = shown and target and proxy or nil
		resize.Visible = shown and target ~= nil and not (drag and drag.mode == "pointer")
	end

	if proxy then
		proxy.Parent = shown and target and workspace.CurrentCamera or nil
	end
end

function Handles.destroy()
	Handles.finish(true)
	for _, c in connections do
		c:Disconnect()
	end

	connections = {}
	for _, p in points do
		p:Destroy()
	end

	points = {}
	if resize then
		resize:Destroy()
		resize = nil
	end

	if proxy then
		proxy:Destroy()
		proxy = nil
	end

	target = nil
	hovered = nil
end

function Handles.init(options)
	Handles.destroy()
	refs = options
	refs.State.EffectHandles = Handles
	for _, camera in workspace:GetChildren() do
		if camera:IsA("Camera") then
			for _, old in camera:GetChildren() do
				if old:GetAttribute("EclipseEffectResizeProxy") then
					old:Destroy()
				end
			end
		end
	end

	proxy = Instance.new("Part")
	proxy.Name = "EclipseBarResizeProxy"
	proxy.Archivable = false
	proxy.Anchored = true
	proxy.Transparency = 1
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = false
	proxy.Locked = true
	proxy:SetAttribute("EclipseEffectResizeProxy", true)
	resize = Instance.new("Handles")
	resize.Name = "EclipseBarResize"
	resize.Style = Enum.HandlesStyle.Resize
	resize.Faces =
		Faces.new(Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom)
	resize.Color3 = Color3.fromRGB(255, 211, 95)
	resize.Visible = false
	resize.Parent = refs.ScreenGui

	local function on(signal, f)
		table.insert(connections, signal:Connect(f))
	end

	on(resize.MouseEnter, function(face)
		hovered = face
	end)
	on(resize.MouseLeave, function()
		hovered = nil
	end)
	on(resize.MouseButton1Down, function()
		Handles.begin(target, "handles")
	end)
	on(resize.MouseDrag, function(face, distance)
		if not drag then
			return
		end

		local axis = (face == Enum.NormalId.Left or face == Enum.NormalId.Right) and "X" or "Y"
		Handles.change(1 + distance * 2 / math.max(0.001, drag.size[axis]), axis)
	end)
	on(resize.MouseButton1Up, function()
		Handles.finish(false)
	end)
	on(Input.InputEnded, function(input)
		if
			drag
			and drag.mode == "handles"
			and input.UserInputType == Enum.UserInputType.MouseButton1
		then
			Handles.finish(false)
		end
	end)
	on(Input.WindowFocusReleased, function()
		Handles.finish(true)
	end)
	on(Run.RenderStepped, Handles.step)
	on(refs.ScreenGui.Destroying, Handles.destroy)
	on(refs.Plugin.Unloading, Handles.destroy)
end

return Handles
