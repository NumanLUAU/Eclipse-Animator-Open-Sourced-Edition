--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local UserInputService = require("UserInputService")
local NativeInput = game:GetService("UserInputService")
local Selection = game:GetService("Selection")
local State = require("State")
local UI = require("UI")
local EditActions = require("EditActions")
const RawState = require("RawState")

local EditShortcuts = {}
local connections = {}
local actions = {}
local preservedSelection = {}
local restoring = false
local handled = false
local guardUntil = 0
local chordWasDown = false
local owned = false
const DELETE_WINDOW = 0.5
const selectionParents = setmetatable({}, { __mode = "k" })
local keysSelected = false

local function ownsSelection()
	return not State.WorkspaceSelection
		and not State.ViewportBoxSelecting
		and not (State.PresentationHidden and not State.CameraPoseMode)
		and UI.isAnimatorActive()
		and UserInputService.isWindowFocused()
		and not UserInputService.isCapturingKeys()
		and UserInputService:GetFocusedTextBox() == nil
end

local function canSelectKeys()
	return not (State.GraphEditor and State.GraphEditor.hasFocus())
end

local function syncOwnership()
	local active = ownsSelection()
	if active ~= owned then
		owned = active
		handled, guardUntil, chordWasDown = false, 0, false
		preservedSelection = Selection:Get()
	end

	return active
end

local function isStudioSelectAll()
	return (
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftSuper)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightSuper)
	)
		and UserInputService:IsKeyDown(Enum.KeyCode.A)
		and not (
			UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		)
end

local function selectAll()
	if not handled then
		handled = true
		if canSelectKeys() then
			EditActions.SelectAll()
		end
	end

	guardUntil = os.clock() + 0.15
end

local function timelineKeysSelected()
	const raw = RawState.Timeline
	return raw ~= nil
		and (
			raw.SelectedKeyframe ~= nil
			or raw.SelectedKeyframes ~= nil and next(raw.SelectedKeyframes) ~= nil
			or raw.SelectedChannelKeyframes ~= nil and next(raw.SelectedChannelKeyframes) ~= nil
		)
end

local function trackSelectionParents()
	const now = os.clock()
	const current = {}
	for _, instance in Selection:Get() do
		const parent = instance.Parent
		if parent then
			current[instance] = true
			selectionParents[instance] = { parent = parent, left = nil }
		end
	end

	for instance, row in selectionParents do
		if not current[instance] then
			row.left = row.left or now
			if now - row.left > DELETE_WINDOW then
				selectionParents[instance] = nil
			end
		end
	end
end

local function guardStudioDelete(input)
	if not Shortcuts.matches("DeleteKeys", input) or not ownsSelection() then
		return
	end

	if
		not keysSelected
		and not timelineKeysSelected()
		and not (State.GraphEditor and State.GraphEditor.hasFocus())
	then
		return
	end

	const now = os.clock()
	for instance, row in selectionParents do
		if
			instance.Parent == nil
			and (row.left == nil or now - row.left <= DELETE_WINDOW)
			and row.parent:IsDescendantOf(game)
		then
			pcall(function()
				instance.Parent = row.parent
			end)
		end
	end

	table.clear(selectionParents)
	if #Selection:Get() > 0 then
		const previousIgnore = State.ignoreSelectionChanged
		State.ignoreSelectionChanged = true
		pcall(function()
			Selection:Set({})
		end)
		State.ignoreSelectionChanged = previousIgnore
	end

	preservedSelection = {}
end

local function restoreSelection()
	local current = Selection:Get()
	local keep, expected = {}, {}
	for _, instance in preservedSelection do
		if instance.Parent then
			table.insert(keep, instance)
			expected[instance] = true
		end
	end

	local changed = #current ~= #keep
	for _, instance in current do
		if not expected[instance] then
			changed = true
			break
		end
	end

	if not changed then
		return
	end

	restoring = true
	local previousIgnore = State.ignoreSelectionChanged
	State.ignoreSelectionChanged = true
	local ok, err = pcall(function()
		Selection:Set(keep)
	end)
	State.ignoreSelectionChanged = previousIgnore
	restoring = false
	if not ok then
		warn(err)
	end
end

function EditShortcuts.init(plugin)
	if #connections > 0 then
		return
	end

	preservedSelection = Selection:Get()
	owned = ownsSelection()
	trackSelectionParents()

	local function began(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			guardUntil = 0
			return
		end

		if not syncOwnership() then
			return
		end

		guardStudioDelete(input)

		if Shortcuts.matches("SelectAll", input) then
			chordWasDown = true
			selectAll()
			restoreSelection()
		end
	end

	table.insert(connections, NativeInput.InputBegan:Connect(began))
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input)
			began(input)
			if
				input.UserInputType == Enum.UserInputType.Keyboard
				and syncOwnership()
				and canSelectKeys()
				and Shortcuts.matches("FitTimeline", input)
			then
				State.Timeline:FitTimeline()
			end
		end)
	)
	table.insert(
		connections,
		game:GetService("RunService").Heartbeat:Connect(function()
			local active = syncOwnership()
			keysSelected = active and timelineKeysSelected()
			local down = active and Shortcuts.isDown("SelectAll")
			if down and not chordWasDown then
				selectAll()
				restoreSelection()
			elseif not down then
				handled = false
			end

			chordWasDown = down
		end)
	)
	if plugin then
		local action = plugin:CreatePluginAction(
			"EclipseSelectAllKeyframes",
			"Eclipse: Select all keyframes",
			"Select all keyframes in the active Eclipse editor",
			"",
			true
		)
		table.insert(actions, action)
		table.insert(
			connections,
			action.Triggered:Connect(function()
				if syncOwnership() and canSelectKeys() then
					handled = false
					selectAll()
					restoreSelection()
				end
			end)
		)
	end

	table.insert(
		connections,
		Selection.SelectionChanged:Connect(function()
			if restoring then
				return
			end

			trackSelectionParents()
			local active = syncOwnership()
			if State.ignoreSelectionChanged then
				preservedSelection = Selection:Get()
				return
			end

			local chord = Shortcuts.isDown("SelectAll") or isStudioSelectAll()
			if active and (chord or os.clock() < guardUntil) then
				if chord then
					chordWasDown = true
					selectAll()
				end

				restoreSelection()
			else
				preservedSelection = Selection:Get()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if Shortcuts.isKey("SelectAll", input.KeyCode) then
				handled, chordWasDown = false, false
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			handled, guardUntil, chordWasDown, owned = false, 0, false, false
			preservedSelection = Selection:Get()
		end)
	)
end

function EditShortcuts.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end

	for _, action in actions do
		action:Destroy()
	end

	table.clear(connections)
	table.clear(actions)
	table.clear(preservedSelection)
	table.clear(selectionParents)
	keysSelected = false
	handled, guardUntil, restoring, chordWasDown, owned = false, 0, false, false, false
end

return EditShortcuts
