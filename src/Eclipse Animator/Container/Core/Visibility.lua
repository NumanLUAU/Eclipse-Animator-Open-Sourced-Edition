--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local State = require("State")
local CameraRig = require("CameraRig")
local CameraDisplay = require("CameraDisplay")
local CoreGui = game:GetService("CoreGui")
local Input = require("UserInputService")
local Motion = require("Motion")
local Visibility = {}
local roots, ledger, connections = {}, {}, {}
local permanent = {}
local boneRoots = {}
local playbackAllowed = false
local ownGui = {}

local dispatching = false
local keyLatch = {}
local Native = game:GetService("UserInputService")
local handled = setmetatable({}, { __mode = "k" })
local visualNames = {
	_EclipseAnimator_Axis = true,
	_EclipseAnimator_DragGuides = true,
	EclipseAnimator_MotionPath = true,
	_EclipseAnimator_OnionLayer = true,
}
local guiNames = {
	["Eclipse Animator"] = true,
	Miscellaneous = true,
	EclipseCameraPreview = true,
	EclipseBlenderImport = true,
	EclipseAnimationCleanup = true,
	EclipseLive = true,
	EclipseGreasePencilWindow = true,
	EclipseCameraGrid = true,
	EclipseWindowMotion = true,
}

local function ownsGui(gui)
	if ownGui[gui] then
		return true
	end

	return gui.Name ~= "Eclipse Animator" and gui.Name ~= "Miscellaneous" and guiNames[gui.Name]
end

local function hideProperty(object, property, hidden)
	local properties = ledger[object]
	if not properties then
		properties = {}
		ledger[object] = properties
	end

	if properties[property] then
		return
	end

	local ok, original = pcall(function()
		return object[property]
	end)
	if not ok then
		return
	end

	properties[property] = { value = original }
	local writing = false

	local function enforce()
		if writing or not State.PresentationHidden then
			return
		end

		writing = true
		pcall(function()
			if object[property] ~= hidden then
				object[property] = hidden
			end
		end)
		writing = false
	end

	table.insert(connections, object:GetPropertyChangedSignal(property):Connect(enforce))
	enforce()
end

local function hideVisual(object)
	if object:IsA("BasePart") then
		hideProperty(object, "LocalTransparencyModifier", 1)
		hideProperty(object, "CanQuery", false)
	elseif
		object:IsA("HandleAdornment")
		or object:IsA("SelectionBox")
		or object:IsA("SelectionSphere")
		or object:IsA("Handles")
		or object:IsA("ArcHandles")
	then
		hideProperty(object, "Visible", false)
	elseif object:IsA("ParticleEmitter") then
		hideProperty(object, "LocalTransparencyModifier", 1)
		hideProperty(object, "TimeScale", 0)
	elseif object:IsA("Beam") or object:IsA("Trail") then
		hideProperty(object, "Transparency", NumberSequence.new(1))
	elseif object:IsA("Highlight") or object:IsA("BillboardGui") or object:IsA("SurfaceGui") then
		hideProperty(object, "Enabled", false)
	elseif object:IsA("Decal") then
		hideProperty(object, "Transparency", 1)
	elseif
		object:IsA("Fire")
		or object:IsA("Smoke")
		or object:IsA("Sparkles")
		or object:IsA("Light")
	then
		hideProperty(object, "Enabled", false)
	elseif object:IsA("Sound") and object.IsPlaying then
		ledger[object] = ledger[object] or {}
		ledger[object]._playing = { value = true }
		object:Pause()
	end
end

function Visibility.bonesHidden()
	return State.PresentationHidden
		and (not State.CameraPoseMode or State.CameraBonesHidden == true)
end

local function posingRoot(root)
	return root.Name == "_EclipseAnimator_Axis"
		or root.Name == "_EclipseAnimator_DragGuides"
		or root:GetAttribute("EclipseAnimator_BonesFolder") == true
		or root:GetAttribute("EclipseArmatureBone") == true
end

function Visibility.watch(root, gui)
	if
		not gui
		and State.CameraPoseMode
		and not State.CameraBonesHidden
		and root
		and posingRoot(root)
	then
		return
	end

	if not State.PresentationHidden or not root or roots[root] then
		return
	end

	roots[root] = true
	if not gui and root:GetAttribute("EclipseAnimator_BonesFolder") == true then
		boneRoots[root] = true
		require("handles").setPlaybackHidden(root, true)
		return
	end

	if gui then
		local function child(item)
			if item:IsA("GuiObject") then
				hideProperty(item, "Visible", false)
			else
				hideVisual(item)
			end
		end

		for _, item in root:GetChildren() do
			child(item)
		end

		table.insert(connections, root.ChildAdded:Connect(child))
	else
		hideVisual(root)
		for _, item in root:GetDescendants() do
			hideVisual(item)
		end

		table.insert(connections, root.DescendantAdded:Connect(hideVisual))
	end
end

function Visibility.isPlaybackActive()
	local UI = require("UI")
	if not State.PresentationHidden then
		return UI.isAnimatorActive()
	end

	return playbackAllowed
		and State.currentRig ~= nil
		and UI.EclipseGUI ~= nil
		and UI.EclipseGUI.Parent ~= nil
		and UI.EclipseGUI.Enabled
		and UI.EclipseGUI:GetAttribute("EclipseConfirmationOpen") ~= true
end

function Visibility.togglePlayback()
	local timeline = State.Timeline
	if
		not timeline
		or timeline:IsExportLocked()
		or not State.currentRig
		or not Visibility.isPlaybackActive()
	then
		return
	end

	local state = timeline:GetState()
	if state.Playing then
		state.Playing = false
	else
		timeline:StartPlayback(true)
	end
end

local function restoreHidden()
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	for object, properties in ledger do
		for property, saved in properties do
			pcall(function()
				if property == "_playing" then
					object:Resume()
				else
					if saved.value == true and object[property] ~= true then
						Motion.preserveNextReveal(object, property)
					end

					object[property] = saved.value
				end
			end)
		end
	end

	table.clear(ledger)
	table.clear(roots)
	for root in boneRoots do
		require("handles").setPlaybackHidden(root, false)
	end

	table.clear(boneRoots)
end

function Visibility.setHidden(hidden, refresh)
	if hidden then
		require("Connections").updateTransformVisibility(true)
	end

	hidden = hidden == true
	if not hidden and State.CameraPreview and State.CameraPreview.isFull() then
		State.CameraPreview.exitFull(true)
	end

	if State.PresentationHidden == hidden and not refresh then
		return
	end

	if refresh then
		restoreHidden()
	end

	if hidden and Visibility.beforeHide then
		Visibility.beforeHide()
	end

	playbackAllowed = hidden and (playbackAllowed or require("UI").isAnimatorActive()) or false
	State.PresentationHidden = hidden
	for _, controller in { State.CameraPreview, State.GraphEditor, State.GreasePencil } do
		if controller and controller.presentationChanged then
			controller.presentationChanged()
		end
	end

	if hidden then
		for _, gui in CoreGui:GetChildren() do
			if ownsGui(gui) then
				Visibility.watch(gui, true)
			end
		end

		local function inspect(item)
			if
				visualNames[item.Name]
				or item:GetAttribute("EclipseAnimator_BonesFolder") == true
				or item:GetAttribute("EclipseCameraDisplay") == true
				or item:GetAttribute("EclipseArmatureBone") == true
				or CameraRig.isRig(item)
			then
				Visibility.watch(item)
				return true
			end

			local marker = item:FindFirstChild("EclipseSourceRig")
			if marker and marker:IsA("ObjectValue") then
				Visibility.watch(item)
				return true
			end

			if item.Name == "EclipseSourceRig" and item:IsA("ObjectValue") then
				Visibility.watch(item.Parent)
			end

			return false
		end

		local function scan(parent)
			for _, item in parent:GetChildren() do
				if
					not inspect(item)
					and (item:IsA("Camera") or item:IsA("Folder") or item:IsA("Model"))
				then
					scan(item)
				end
			end
		end

		scan(workspace)
		table.insert(connections, workspace.DescendantAdded:Connect(inspect))
		table.insert(
			connections,
			CoreGui.ChildAdded:Connect(function(gui)
				if ownsGui(gui) then
					Visibility.watch(gui, true)
				end
			end)
		)
		for _, controller in
			{
				State.GraphEditor,
				State.ImagePreviewer,
				State.CameraPreview,
				State.AnimationCleanup,
				State.LiveSession,
				State.AnimatorDock,
			}
		do
			if controller and controller.presentationWidget then
				local panel = controller.presentationWidget()
				if panel then
					hideProperty(panel, "Enabled", false)
				end
			end
		end
	else
		restoreHidden()
	end

	if State.Axis then
		local hide = Visibility.bonesHidden()
			or (State.PivotEditor ~= nil and State.PivotEditor.isActive())
		local playing = State.Timeline and State.Timeline:GetState().Playing == true and not State.Timeline:GetState().Recording
		State.Axis:SetPlaybackHidden(hide or playing, hide)
	end

	CameraDisplay.refresh()
end

local hudLedger = {}
local hudStrokes = {}
local hudConnections = {}
local hudRoot

function Visibility.setHUDHidden(hidden)
	hidden = hidden == true
	if hidden == State.HUDHidden then
		return
	end

	State.HUDHidden = hidden
	if not hidden then
		for _, c in hudConnections do
			c:Disconnect()
		end

		table.clear(hudConnections)
		for object, value in hudLedger do
			if object.Parent then
				object.Visible = value
			end
		end

		table.clear(hudLedger)
		for object, value in hudStrokes do
			if object.Parent then
				object.Enabled = value
			end
		end

		table.clear(hudStrokes)
		if hudRoot and hudRoot.object.Parent then
			hudRoot.object.BackgroundTransparency = hudRoot.transparency
			hudRoot.object.Active = hudRoot.active
			hudRoot.object:SetAttribute("EclipseHUDHidden", nil)
		end

		hudRoot = nil
		return
	end

	local UI = require("UI")

	local function hide(object)
		if object:IsA("UIStroke") then
			hudStrokes[object] = object.Enabled
			object.Enabled = false
			return
		end

		if object:IsA("Folder") then
			for _, child in object:GetChildren() do
				hide(child)
			end

			table.insert(hudConnections, object.ChildAdded:Connect(hide))
			return
		end

		if not object:IsA("GuiObject") then
			return
		end

		hudLedger[object] = object.Visible
		object.Visible = false
		table.insert(
			hudConnections,
			object:GetPropertyChangedSignal("Visible"):Connect(function()
				if State.HUDHidden and object.Visible then
					object.Visible = false
				end
			end)
		)
	end

	hudRoot = {
		object = UI.AnimatorFrame,
		transparency = UI.AnimatorFrame.BackgroundTransparency,
		active = UI.AnimatorFrame.Active,
	}
	UI.AnimatorFrame.BackgroundTransparency = 1
	UI.AnimatorFrame.Active = false
	UI.AnimatorFrame:SetAttribute("EclipseHUDHidden", true)
	for _, child in UI.AnimatorFrame:GetChildren() do
		hide(child)
	end

	table.insert(hudConnections, UI.AnimatorFrame.ChildAdded:Connect(hide))
end

function Visibility.toggleHUD()
	if State.PresentationHidden then
		Visibility.setHidden(false)
	end

	Visibility.setHUDHidden(not State.HUDHidden)
end

function Visibility.toggle()
	if State.CameraPoseMode then
		if Visibility.beforeHide then
			Visibility.beforeHide()
		end

		State.CameraBonesHidden = not State.CameraBonesHidden
		Visibility.setHidden(true, true)
		if State.Axis then
			State.Axis:SetPlaybackHidden(State.CameraBonesHidden, State.CameraBonesHidden)
		end
	else
		Visibility.setHidden(not State.PresentationHidden)
	end
end

function Visibility.input(input, heldKeys)
	if handled[input] then
		return true
	end

	local UI = require("UI")
	if not UI.EclipseGUI or not UI.EclipseGUI.Parent or not UI.EclipseGUI.Enabled then
		return false
	end

	if not State.PresentationHidden and not UI.isAnimatorActive() then
		return false
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and not Input:GetFocusedTextBox() then
		local camera = State.CameraPreview
		if
			camera
			and camera.isFull()
			and not Input.isUIInput(input)
			and not Input.pointerOverUI()
		then
			return camera.fullInput(input)
		end
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard or Input:GetFocusedTextBox() then
		return false
	end

	local modifiers = table.clone(heldKeys or {})
	for name, key in
		{
			Ctrl = Enum.KeyCode.LeftControl,
			Shift = Enum.KeyCode.LeftShift,
			Alt = Enum.KeyCode.LeftAlt,
			Meta = Enum.KeyCode.LeftMeta,
		}
	do
		local ok, down = pcall(function()
			return input:IsModifierKeyDown(Enum.ModifierKey[name])
		end)
		if ok and down then
			modifiers[key] = true
		end
	end

	local camera = State.CameraPreview
	local action
	if camera and camera.isFull() and Shortcuts.matches("Cancel", input, modifiers) then
		if
			State.Axis
			and (
				State.Axis:IsHoldingAxis()
				or State.Axis:IsBlenderGrabMode()
				or State.Axis:IsBlenderRotateMode()
			)
		then
			return false
		end

		action = camera.isViewRotating() and function()
			camera.finishViewRotation(true)
		end or camera.exitFull
	elseif camera and camera.isFull() and Shortcuts.matches("TogglePlayback", input, modifiers) then
		action = camera.togglePlayback
	elseif State.PresentationHidden and Shortcuts.matches("TogglePlayback", input, modifiers) then
		action = Visibility.togglePlayback
	elseif Shortcuts.matches("CycleCamera", input, modifiers) and camera then
		action = camera.isFull() and camera.exitFull or camera.cycleFull
	elseif
		Shortcuts.matches("ToggleHUD", input, modifiers)
		and not (State.GraphEditor and State.GraphEditor.hasFocus and State.GraphEditor.hasFocus())
	then
		action = Visibility.toggleHUD
	elseif Shortcuts.matches("TogglePresentation", input, modifiers) then
		action = Visibility.toggle
	end

	if not action then
		if camera and camera.fullInput then
			return camera.fullInput(input)
		end

		return false
	end

	if keyLatch[input.KeyCode] then
		return true
	end

	keyLatch[input.KeyCode] = os.clock()
	if handled[input] then
		return true
	end

	handled[input] = true

	task.defer(function()
		handled[input] = nil
	end)
	if not dispatching then
		dispatching = true
		task.defer(function()
			dispatching = false
		end)
		action()
	end

	return true
end

function Visibility.release(input)
	handled[input] = nil
	keyLatch[input.KeyCode] = nil
end

function Visibility.init(plugin, screen, helpers)
	if screen then
		ownGui[screen] = true
	end

	if helpers then
		ownGui[helpers] = true
	end

	if #permanent > 0 then
		return
	end

	table.insert(
		permanent,
		Input.InputBegan:Connect(function(input)
			Visibility.input(input)
		end)
	)
	table.insert(permanent, Input.InputEnded:Connect(Visibility.release))
	table.insert(
		permanent,
		Input.WindowFocusReleased:Connect(function()
			table.clear(handled)
			table.clear(keyLatch)
		end)
	)
	table.insert(
		permanent,
		game:GetService("RunService").Heartbeat:Connect(function()
			for key, since in keyLatch do
				if not Native:IsKeyDown(key) and os.clock() - since > 0.12 then
					keyLatch[key] = nil
				end
			end

			if not (State.PresentationHidden or State.HUDHidden) or Native:GetFocusedTextBox() then
				return
			end

			for _, id in { "TogglePresentation", "ToggleHUD", "CycleCamera", "TogglePlayback" } do
				local binding = Shortcuts.get(id)
				local key = binding and binding.Key and Enum.KeyCode[binding.Key]
				if key and Native:IsKeyDown(key) and not keyLatch[key] then
					local input = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = key }

					function input:IsModifierKeyDown(modifier)
						local keys = {
							Ctrl = { "LeftControl", "RightControl" },
							Shift = { "LeftShift", "RightShift" },
							Alt = { "LeftAlt", "RightAlt" },
							Meta = { "LeftMeta", "RightMeta", "LeftSuper", "RightSuper" },
						}
						local names = keys[modifier.Name]
						if not names then
							return false
						end

						for _, name in names do
							if Native:IsKeyDown(Enum.KeyCode[name]) then
								return true
							end
						end

						return false
					end

					Visibility.input(input)
				end
			end
		end)
	)
	if plugin then
		table.insert(
			permanent,
			plugin.Unloading:Connect(function()
				Visibility.setHUDHidden(false)
				Visibility.setHidden(false)
				for _, connection in permanent do
					connection:Disconnect()
				end

				table.clear(permanent)
			end)
		)
	end
end

return Visibility
