--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local Input = require("UserInputService")
local UI = require("UI")
local Organization = require("Organization")
local Hierarchy = require("Hierarchy")
local Selection = {}
local gesture

local function down(a, b)
	return Input:IsKeyDown(a) or Input:IsKeyDown(b)
end

function Selection.items(camera, first, last)
	local rig = State.Rig
	local members, visited, found, seenMotors = {}, {}, {}, {}
	for _, owner in State.getAllRigs() do
		members[owner] = true
	end

	local x0, x1 = math.min(first.X, last.X), math.max(first.X, last.X)
	local y0, y1 = math.min(first.Y, last.Y), math.max(first.Y, last.Y)

	local function visit(item)
		if visited[item] or item._destroyed or item.disabled then
			return
		end

		visited[item] = true
		local owner = (item.grandpa or item).linkedRigInstance
		local kind = item.itemKind
		if
			members[owner]
			and owner.Parent
			and not item.trackIsMaster
			and kind ~= "channel"
			and kind ~= "origin"
			and kind ~= "events"
			and kind ~= "faces"
			and kind ~= "subtitles"
			and kind ~= "folder"
			and kind ~= "properties"
			and kind ~= "armature"
			and kind ~= "cameraattach"
		then
			local motor = item:fetchMotor()
			local position
			if motor and motor.Parent and not seenMotors[motor] then
				if kind == "property" then
					if motor.PropertyId == "CFrame" then
						local target = motor.Rig
						if typeof(target) == "Instance" and target.Parent then
							if target:IsA("BasePart") then
								position = target.Position
							elseif target:IsA("Model") then
								position = target:GetPivot().Position
							end
						end
					end
				else
					local bone = item:fetchBone()
					local shown = true
					if kind == "ikcontrol" then
						shown = require("LimbIK").controlsVisible(motor.Owner)
							and require("R6Controls").visible(motor)
					end

					if
						shown
						and bone
						and bone.Parent
						and Organization.isBoneVisible(motor.Part1)
						and #Organization.filterCollectionSelection({ bone }, owner, rig) > 0
					then
						position = bone.Position
					end
				end

				if position then
					seenMotors[motor] = true
					local screen, onScreen = camera:WorldToViewportPoint(position)
					local point = Vector2.new(screen.X, screen.Y)
					if
						onScreen
						and screen.Z > 0
						and point.X >= x0
						and point.X <= x1
						and point.Y >= y0
						and point.Y <= y1
						and not Input.pointerOverUI(point)
					then
						table.insert(found, item)
					end
				end
			end
		end

		for _, child in item.childItems or {} do
			visit(child)
		end
	end

	for _, root in rig._rootItems or rig._masterItems or {} do
		visit(root)
	end

	return found
end

function Selection.apply(items, mode)
	local rig = State.Rig
	local selected = mode == "replace" and {} or table.clone(rig._selectedItems or {})
	local primary = mode ~= "replace" and rig._lastClickedItem or nil
	for _, item in items do
		if mode == "subtract" then
			selected[item] = nil
		else
			selected[item] = true
			primary = item
		end
	end

	if not selected[primary] then
		primary = next(selected)
	end

	local explicit = {}
	for item in selected do
		local key = Hierarchy.key(item)
		if key then
			explicit[key] = true
		end
	end

	rig._selectedItems, rig._lastClickedItem = selected, primary
	rig._explicitSelectedKeys, rig._selectedChannels = explicit, {}
	rig:_SyncAxisToPrimary()
	rig:SelectKeysForSelectedParts()
	rig:RefreshHierarchySelectionVisuals()
end

function Selection.cancel()
	if gesture then
		if gesture.layer then
			gesture.layer:Destroy()
		end

		gesture = nil
	end

	State.ViewportBoxSelecting = false
end

function Selection.active()
	return gesture ~= nil
end

function Selection.validate()
	if not gesture then
		return false
	end

	local raw = State.Timeline and State.Timeline:GetState()
	if
		State.Rig ~= gesture.rig
		or State.currentRig ~= gesture.owner
		or (State.Rig._rootItems or State.Rig._masterItems) ~= gesture.roots
		or workspace.CurrentCamera ~= gesture.camera
		or not raw
		or State.Timeline:IsExportLocked()
		or (raw.Playing and not raw.Recording)
		or State.LoadingProject
		or State.WorkspaceSelection
		or not UI.isAnimatorActive()
		or require("Visibility").bonesHidden()
		or Input:GetFocusedTextBox()
	then
		Selection.cancel()
		return false
	end

	return true
end

function Selection.begin(point)
	Selection.cancel()
	if
		not point
		or not State.Rig
		or not workspace.CurrentCamera
		or #State.getAllRigs() == 0
		or Input.pointerOverUI(point)
	then
		return false
	end

	gesture = {
		first = point,
		last = point,
		rig = State.Rig,
		owner = State.currentRig,
		camera = workspace.CurrentCamera,
		roots = State.Rig._rootItems or State.Rig._masterItems,
		mode = down(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl) and "subtract"
			or down(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift) and "add"
			or "replace",
	}
	if not Selection.validate() then
		return false
	end

	State.ViewportBoxSelecting = true
	return true
end

function Selection.move(point)
	if not Selection.validate() or not point then
		return
	end

	local size = gesture.camera.ViewportSize
	point = Vector2.new(math.clamp(point.X, 0, size.X), math.clamp(point.Y, 0, size.Y))
	gesture.last = point
	if not gesture.layer and (point - gesture.first).Magnitude >= 5 then
		local layer = Instance.new("ScreenGui")
		layer.Name = "EclipseViewportSelection"
		layer.ResetOnSpawn = false
		layer.IgnoreGuiInset = true
		layer.DisplayOrder = -1001
		layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		local rectangle = Instance.new("Frame")
		rectangle.Name = "Selection"
		rectangle.Active = false
		rectangle.ZIndex = 0
		rectangle.BorderSizePixel = 0
		rectangle.BackgroundColor3 = require("Theme").get("Txt", Color3.fromRGB(190, 220, 230))
		rectangle.BackgroundTransparency = 0.9
		rectangle.Parent = layer
		local border = Instance.new("UIStroke")
		border.Color = rectangle.BackgroundColor3
		border.Thickness = 1
		border.Parent = rectangle
		gesture.layer, gesture.rectangle = layer, rectangle
		layer.Parent = game:GetService("CoreGui")
	end

	if gesture.rectangle then
		local first = gesture.first
		gesture.rectangle.Position =
			UDim2.fromOffset(math.min(first.X, point.X), math.min(first.Y, point.Y))
		gesture.rectangle.Size =
			UDim2.fromOffset(math.abs(first.X - point.X), math.abs(first.Y - point.Y))
	end
end

function Selection.finish(cancelled)
	if cancelled or not Selection.validate() then
		Selection.cancel()
		return false
	end

	local current = gesture
	if not current.layer then
		Selection.cancel()
		return not Input.pointerOverUI()
	end

	local items = Selection.items(current.camera, current.first, current.last)
	Selection.cancel()
	Selection.apply(items, current.mode)
	return false
end

return Selection
