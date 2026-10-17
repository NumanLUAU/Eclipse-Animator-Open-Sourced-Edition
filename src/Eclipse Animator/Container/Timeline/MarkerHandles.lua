--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local Tracks = require("Properties")
local Handles = {}
local refs, connection, folder
local markers = {}

function Handles.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end

	table.clear(markers)
end

function Handles.available()
	return refs
		and refs.Active()
		and refs.ScreenGui.Enabled
		and refs.AnimatorFrame.Visible
		and not State.PresentationHidden
		and not (State.Timeline and State.Timeline:GetState().Playing)
end

function Handles.step()
	if not Handles.available() then
		Handles.clear()
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		Handles.clear()
		return
	end

	local wanted = {}
	for _, rig in State.getAllRigs() do
		if rig:IsA("Attachment") and not rig:IsA("Bone") and rig:IsDescendantOf(workspace) then
			wanted[rig] = true
		end
	end

	for rig, marker in markers do
		if not wanted[rig] then
			marker.part:Destroy()
			markers[rig] = nil
		end
	end

	if not next(wanted) then
		Handles.clear()
		return
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EclipseAttachmentHandles"
		folder.Archivable = false
		require("Recovery").mark(folder)
	end

	folder.Parent = camera
	local unit = 2
		* math.tan(math.rad(camera.FieldOfView) * 0.5)
		/ math.max(1, camera.ViewportSize.Y)
	for rig in wanted do
		local marker = markers[rig]
		if not marker then
			local part = Instance.new("Part")
			part.Name = "AttachmentCircle"
			part.Anchored = true
			part.Transparency = 1
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Archivable = false
			part.Size = Vector3.one
			part.Parent = folder
			local circle = Instance.new("SphereHandleAdornment")
			circle.Name = "Circle"
			circle.Adornee = part
			circle.AlwaysOnTop = true
			circle.ZIndex = 4
			circle.Transparency = 0.15
			circle.Color3 = Color3.fromRGB(85, 230, 155)
			circle.Parent = part
			marker = { part = part, circle = circle }
			markers[rig] = marker
		end

		marker.part.CFrame = rig.WorldCFrame
		local depth = -camera.CFrame:PointToObjectSpace(rig.WorldPosition).Z
		marker.circle.Radius = math.max(0.005, depth * unit * 5)
		marker.circle.Visible = depth > 0
	end
end

function Handles.hit(camera, mouse)
	if not Handles.available() then
		return nil
	end

	local closest, gap = nil, 9
	for rig, marker in markers do
		if rig.Parent and marker.circle.Visible then
			local p, visible = camera:WorldToViewportPoint(rig.WorldPosition)
			local distance = (Vector2.new(p.X, p.Y) - mouse).Magnitude
			if visible and distance < gap then
				closest, gap = rig, distance
			end
		end
	end

	return closest
end

function Handles.select(camera, mouse, extend)
	local rig = Handles.hit(camera, mouse)
	if not rig then
		return false
	end

	local item = State.Rig:PropertyItem(rig, "CFrame")
	if not item then
		return false
	end

	if extend then
		State.Rig:ToggleItemSelection(item)
	else
		State.Rig:SetSingleItemSelection(item)
	end

	return true
end

function Handles.destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end

	Handles.clear()
end

function Handles.init(options)
	Handles.destroy()
	refs = options
	connection = game:GetService("RunService").RenderStepped:Connect(Handles.step)
	options.Plugin.Unloading:Once(Handles.destroy)
	options.ScreenGui.Destroying:Once(Handles.destroy)
end

return Handles
