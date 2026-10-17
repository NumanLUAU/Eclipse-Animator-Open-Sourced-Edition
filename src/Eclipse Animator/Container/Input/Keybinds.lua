--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
--!strict
local Shortcuts = require("Shortcuts")

local UserInputService = require("UserInputService")
local NativeInput = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Bindings = require("Bindings")

local GraphRootState = require("State")
local Keybinds = {}

local heldKeys: { [Enum.KeyCode]: boolean } = {}
local firedCombos: { [Enum.KeyCode]: boolean } = {}
local actionCallbacks: { [string]: () -> () } = {}
local connections: { RBXScriptConnection } = {}
local initialized = false
local lifecycle = 0
local polledKeys = {}
local pressInputs = {}
local repeats = {}
local configured = {}

local observedPress = {}
local unsubscribe
local studioActions = {}
local eventOnlyKeys = {
	[Enum.KeyCode.CapsLock] = true,
	[Enum.KeyCode.NumLock] = true,
	[Enum.KeyCode.ScrollLock] = true,
}
local repeatActions = {
	StepSingleFrameLeft = true,
	StepSingleFrameRight = true,
	JumpSingleKeyframeLeft = true,
	JumpSingleKeyframeRight = true,
	StepFrameLeft = true,
	StepFrameRight = true,
	JumpKeyframeLeft = true,
	JumpKeyframeRight = true,
}
local cameraActions = {
	StepSingleFrameLeft = true,
	StepSingleFrameRight = true,
	JumpSingleKeyframeLeft = true,
	JumpSingleKeyframeRight = true,
	JumpToStart = true,
	StepFrameLeft = true,
	StepFrameRight = true,
	JumpKeyframeLeft = true,
	JumpKeyframeRight = true,
	StartBlenderRotate = true,
	ToggleBlenderGrab = true,
	ToggleBlenderScale = true,
	ToggleScaleGizmo = true,
	ToggleGizmoMode = true,
	SetPositionGizmo = true,
	SetRotationGizmo = true,
	ToggleAxisSpace = true,
	ResetScale = true,
	ResetMotorPosition = true,
	ResetMotorOrientation = true,
	RecordKeyframe = true,
	RecordAllTracks = true,
	ToggleCameraGrid = true,
	CycleCameraGrid = true,
	RotateCameraGrid = true,
}
const gridActions = {
	ToggleCameraGrid = true,
	CycleCameraGrid = true,
	RotateCameraGrid = true,
}
local digitNames = {
	Zero = true,
	One = true,
	Two = true,
	Three = true,
	Four = true,
	Five = true,
	Six = true,
	Seven = true,
	Eight = true,
	Nine = true,
}
for n = 0, 9 do
	digitNames["Keypad" .. n] = true
end

local function releaseComboLocksForKey(releasedKey)
	firedCombos[releasedKey] = nil
	repeats[releasedKey] = nil
end

local function bind(action: string, callback: () -> ())
	actionCallbacks[action] = callback
end

local function unbind(action: string)
	actionCallbacks[action] = nil
end

local function isHeld(key: Enum.KeyCode): boolean
	return heldKeys[key] == true
end

local function dispatch(
	input: InputObject,
	gameProcessed: boolean,
	repeating: string?,
	studioAction: string?
): boolean
	if
		GraphRootState.ViewportBoxSelecting
		or GraphRootState.WorkspaceSelection and not Shortcuts.matches("StudioSelection", input)
	then
		return false
	end

	if
		Shortcuts.matches("TogglePresentation", input)
		or Shortcuts.matches("ToggleHUD", input)
		or Shortcuts.matches("CycleCamera", input)
	then
		return false
	end

	local camera = GraphRootState.CameraPreview
	if
		camera
		and camera.isFull()
		and (
			Shortcuts.matches("ToggleBlenderGrab", input)
			or Shortcuts.matches("StartBlenderRotate", input)
		)
	then
		return require("Visibility").input(input, heldKeys)
	end

	local navigation = GraphRootState.BlenderNavigation
	if navigation then
		if navigation.isDragging() and not Shortcuts.matches("TogglePlayback", input) then
			return false
		end

		if
			navigation.isWalkingInput
			and navigation.isWalkingInput(input)
			and not Shortcuts.matches("ToggleCameraWASD", input)
			and not Shortcuts.matches("ToggleCameraQE", input)
		then
			return false
		end
	end

	if GraphRootState.PhysicsDisplay and GraphRootState.PhysicsDisplay.isEditing() then
		return false
	end

	if
		GraphRootState.PropertyGizmo
		and GraphRootState.PropertyGizmo.isEditing()
		and not Shortcuts.matches("StartBlenderRotate", input)
	then
		return false
	end

	if GraphRootState.CameraControls and GraphRootState.CameraControls.isEditing() then
		return false
	end

	if GraphRootState.EffectHandles and GraphRootState.EffectHandles.isEditing() then
		return false
	end

	if GraphRootState.PivotEditor and GraphRootState.PivotEditor.isActive() then
		return false
	end

	if GraphRootState.GraphEditor and GraphRootState.GraphEditor.hasFocus() then
		return false
	end

	if GraphRootState.ImagePreviewer and GraphRootState.ImagePreviewer.hasFocus() then
		return false
	end

	if GraphRootState.ExportResults and GraphRootState.ExportResults.hasFocus() then
		return false
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return false
	end

	if
		gameProcessed
		and not (
			require("UI").isTransportActive()
			and (
				Shortcuts.matches("ToggleCameraWASD", input)
				or Shortcuts.matches("ToggleCameraQE", input)
				or (navigation and navigation.isReservedInput and navigation.isReservedInput(input))
				or (navigation and navigation.isDragging() and Shortcuts.matches(
					"TogglePlayback",
					input
				))
				or Shortcuts.matches("StudioSelection", input)
				or (Shortcuts.matches("ToggleAxisSpace", input) and UserInputService.inWidget())
				or Shortcuts.matches("StepSingleFrameLeft", input)
				or Shortcuts.matches("StepSingleFrameRight", input)
				or Shortcuts.matches("JumpSingleKeyframeLeft", input)
				or Shortcuts.matches("JumpSingleKeyframeRight", input)
				or Shortcuts.matches("StepFrameLeft", input)
				or Shortcuts.matches("StepFrameRight", input)
				or Shortcuts.matches("JumpToStart", input)
				or Shortcuts.matches("JumpKeyframeLeft", input)
				or Shortcuts.matches("JumpKeyframeRight", input)
				or Shortcuts.matches("OpenKeyframeMenu", input)
				or Shortcuts.matches("SetPositionGizmo", input)
				or Shortcuts.matches("SetRotationGizmo", input)
				or Shortcuts.matches("ReverseKeys", input)
				or Shortcuts.matches("ReversePaste", input)
				or Shortcuts.matches("CopyKeyframes", input)
				or Shortcuts.matches("PasteKeyframes", input)
				or Shortcuts.matches("CutKeyframes", input)
			)
		)
	then
		return false
	end

	if UserInputService:GetFocusedTextBox() or UserInputService.isCapturingKeys() then
		return false
	end

	for _, binding in ipairs(Bindings) do
		local cb = (
			not GraphRootState.CameraPoseMode
			or cameraActions[binding.Action]
				and (not GraphRootState.CameraBonesHidden or repeatActions[binding.Action] or binding.Action == "JumpToStart" or gridActions[binding.Action])
		)
			and (not GraphRootState.PresentationHidden or GraphRootState.CameraPoseMode or repeatActions[binding.Action] or binding.Action == "JumpToStart")
			and binding.Dispatch
			and (not repeating or repeating == binding.Action)
			and actionCallbacks[binding.Action]
		if
			cb
			and (studioAction == binding.Action or not studioAction and Shortcuts.matches(
				binding.Action,
				input
			))
			and (repeating or not firedCombos[input.KeyCode])
		then
			firedCombos[input.KeyCode] = true
			if
				not repeating
				and not eventOnlyKeys[input.KeyCode]
				and repeatActions[binding.Action]
			then
				repeats[input.KeyCode] =
					{ action = binding.Action, input = input, remaining = 0.35 }
			end

			if navigation and navigation.finishWheel then
				navigation.finishWheel(true)
			end

			cb()
			local paired = binding.Action == "ResetMotorPosition" and "ResetMotorOrientation"
				or binding.Action == "ResetMotorOrientation" and "ResetMotorPosition"
			if paired and actionCallbacks[paired] and Shortcuts.matches(paired, input) then
				actionCallbacks[paired]()
			end

			return true
		end
	end

	return false
end

function Keybinds.triggerStudioAction(action)
	if not initialized or (action ~= "StepFrameLeft" and action ~= "StepFrameRight") then
		return false
	end

	if not UserInputService.isWindowFocused() or not require("UI").isTransportActive() then
		return false
	end

	local binding = Shortcuts.get(action)
	local key = binding and binding.Key and Enum.KeyCode[binding.Key]
		or (action == "StepFrameLeft" and Enum.KeyCode.Six or Enum.KeyCode.Seven)
	for _, command in { Enum.KeyCode.LeftMeta, Enum.KeyCode.RightMeta, Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper } do
		if UserInputService:IsKeyDown(command) then
			return false
		end
	end
	local alias = binding and binding.Key and Shortcuts.aliasKey(action, binding.Key)
	if not UserInputService:IsKeyDown(key) and not (alias and UserInputService:IsKeyDown(Enum.KeyCode[alias])) then
		return false
	end
	local input = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = key }
	observedPress[key] = true
	return dispatch(input, false, nil, action)
end

local function init()
	if initialized then
		return
	end

	initialized = true
	lifecycle += 1
	local epoch = lifecycle
	local plugin = require("ProjectData").getPlugin()
	if plugin then
		for _, row in { { "StepFrameLeft", "Previous frame" }, { "StepFrameRight", "Next frame" } } do
			local action = plugin:CreatePluginAction(
				"Eclipse" .. row[1],
				"Eclipse: " .. row[2],
				"Step one frame in the active Eclipse animation",
				"",
				true
			)
			table.insert(studioActions, action)
			table.insert(
				connections,
				action.Triggered:Connect(function()
					Keybinds.triggerStudioAction(row[1])
				end)
			)
		end
	end

	table.insert(
		connections,
		NativeInput.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				observedPress[input.KeyCode] = true
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			for key in configured do
				if UserInputService:IsKeyDown(key) then
					observedPress[key] = true
				end
			end

			table.clear(heldKeys)
			table.clear(repeats)
			table.clear(pressInputs)
			for key in configured do
				if UserInputService:IsKeyDown(key) then
					polledKeys[key] = true
					firedCombos[key] = true
				end
			end
		end)
	)

	local function refreshBindings()
		table.clear(configured)
		table.clear(repeats)
		for _, id in
			{
				"StepSingleFrameLeft",
				"StepSingleFrameRight",
				"JumpSingleKeyframeLeft",
				"JumpSingleKeyframeRight",
				"StepFrameLeft",
				"StepFrameRight",
				"JumpToStart",
				"JumpKeyframeLeft",
				"JumpKeyframeRight",
				"OpenKeyframeMenu",
				"ReverseKeys",
				"ReversePaste",
				"SetPositionGizmo",
				"SetRotationGizmo",
			}
		do
			local value = Shortcuts.get(id)
			if value and value.Key and not eventOnlyKeys[Enum.KeyCode[value.Key]] then
				configured[Enum.KeyCode[value.Key]] = true
				local alias = Shortcuts.aliasKey(id, value.Key)
				if alias then
					configured[Enum.KeyCode[alias]] = true
				end
			end
		end
	end

	refreshBindings()
	unsubscribe = Shortcuts.subscribe(refreshBindings)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			for key, state in repeats do
				if not UserInputService:IsKeyDown(key) or not require("UI").isTransportActive() then
					repeats[key] = nil
				else
					state.remaining -= dt
					if state.action == "StepFrameLeft" or state.action == "StepFrameRight"
						or state.action == "StepSingleFrameLeft" or state.action == "StepSingleFrameRight" then
						local emitted = 0
						while state.remaining <= 1e-6 and emitted < 4 and repeats[key] == state do
							state.remaining += 1 / 60
							emitted += 1
							if
								not UserInputService:IsKeyDown(key)
								or not require("UI").isTransportActive()
								or not dispatch(state.input, true, state.action)
							then
								repeats[key] = nil
							end
						end

						if state.remaining <= 0 then
							state.remaining = 1 / 60
						end
					elseif state.remaining <= 0 then
						state.remaining = 0.09
						if not dispatch(state.input, true, state.action) then
							repeats[key] = nil
						end
					end
				end
			end

			for key in polledKeys do
				if not configured[key] then
					polledKeys[key] = nil
				end
			end

			local pressed
			for key in configured do
				if not UserInputService:IsKeyDown(key) then
					polledKeys[key] = nil
					heldKeys[key] = nil
					firedCombos[key] = nil
					repeats[key] = nil
					pressInputs[key] = nil
				elseif not polledKeys[key] then
					polledKeys[key] = true
					observedPress[key] = true
					if not heldKeys[key] then
						pressInputs[key] = nil
					end

					if require("UI").isTransportActive() then
						dispatch(
							{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = key },
							true
						)
					end
				end
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				observedPress[input.KeyCode] = true
				heldKeys[input.KeyCode] = true
				if eventOnlyKeys[input.KeyCode] then
					releaseComboLocksForKey(input.KeyCode)
				end

				pressInputs[input.KeyCode] = input
			end

			dispatch(input, gameProcessed)
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				heldKeys[input.KeyCode] = nil
				pressInputs[input.KeyCode] = nil
				releaseComboLocksForKey(input.KeyCode)
			end
		end)
	)

	table.insert(
		connections,
		NativeInput.InputEnded:Connect(function(input, processed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			task.defer(function()
				if not initialized or lifecycle ~= epoch then
					return
				end

				local key = input.KeyCode
				local observed = observedPress[key]
				observedPress[key] = nil
				if
					observed
					or not configured[key]
					or input.UserInputState == Enum.UserInputState.Cancel
				then
					return
				end

				if
					not UserInputService.isWindowFocused()
					or not require("UI").isTransportActive()
				then
					return
				end

				for _, action in
					{
						"StepSingleFrameLeft",
						"StepSingleFrameRight",
						"JumpSingleKeyframeLeft",
						"JumpSingleKeyframeRight",
						"StepFrameLeft",
						"StepFrameRight",
						"JumpKeyframeLeft",
						"JumpKeyframeRight",
						"JumpToStart",
						"SetPositionGizmo",
						"SetRotationGizmo",
					}
				do
					if Shortcuts.matches(action, input) then
						dispatch(input, processed, action)
						releaseComboLocksForKey(key)
						return
					end
				end
			end)
		end)
	)
end

local function destroy()
	lifecycle += 1
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end

	table.clear(repeats)
	table.clear(configured)
	for _, c in ipairs(connections) do
		c:Disconnect()
	end

	table.clear(connections)
	for _, action in studioActions do
		action:Destroy()
	end

	table.clear(studioActions)
	table.clear(heldKeys)
	table.clear(firedCombos)
	table.clear(polledKeys)
	table.clear(pressInputs)
	table.clear(observedPress)
	table.clear(actionCallbacks)
	initialized = false
end

Keybinds.bind = bind
Keybinds.unbind = unbind
Keybinds.isHeld = isHeld
Keybinds.init = init
Keybinds.destroy = destroy

return Keybinds
