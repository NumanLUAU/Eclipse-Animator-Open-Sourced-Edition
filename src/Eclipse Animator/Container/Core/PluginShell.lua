--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local CoreGui = game:GetService("CoreGui")
local EventPlayback = require("EventPlayback")

local WindowFX = require("WindowFX")

local Visibility = require("Visibility")
local State = require("State")
local PluginShell = {}

local attached = false
local attachedSource, mainGui, helpersGui
local attachedPlugin
local ownedToolbar
const ownedButtons = {}
local ownedConnections = {}
local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(ownedConnections, connection)
	return connection
end

function PluginShell.destroy()
	for _, connection in ownedConnections do
		connection:Disconnect()
	end
	table.clear(ownedConnections)
	local plugin = attachedPlugin
	attachedPlugin = nil
	if plugin then
		pcall(function() plugin:Deactivate() end)
	end
	for _, button in ownedButtons do
		pcall(button.Destroy, button)
	end
	table.clear(ownedButtons)
	local toolbar = ownedToolbar
	ownedToolbar = nil
	if toolbar then
		pcall(toolbar.Destroy, toolbar)
	end
end

function PluginShell.getUI(source)
	assert(
		attachedSource == source and mainGui and helpersGui,
		"Eclipse UI is not attached to this plugin"
	)
	return mainGui, helpersGui
end

local function attach(plugin: any, eclipseScript: Instance)
	if attached then
		return
	end

	attached = true
	attachedPlugin = plugin
	WindowFX.recoverClosingTools(CoreGui)
	pcall(WindowFX.recoverOrphanedTools, CoreGui)

	local EclipseUI = eclipseScript:WaitForChild("Eclipse")
	local MiscUI = eclipseScript:WaitForChild("Miscellaneous")
	local ValuesFolder = eclipseScript:WaitForChild("Values")
	local PlayersFolder = eclipseScript:WaitForChild("Players")

	local RequestEvent = PlayersFolder:WaitForChild("RequestEvent")
	RequestEvent.OnInvoke = function()
		return false
	end
	local PluginActiveBool = ValuesFolder:WaitForChild("PluginActive")
	local ClosingEvent = ValuesFolder:FindFirstChild("Closing")

	local AlertFrame =
		EclipseUI:WaitForChild("Frame"):WaitForChild("Components"):WaitForChild("Alert")

	local token = game:GetService("HttpService"):GenerateGUID(false)
	local edition = eclipseScript.Name:lower():find("experimental", 1, true) and "Experimental" or "Animator"
	local build = "v1.0961-10-17-2026"
	attachedSource, mainGui, helpersGui = eclipseScript, EclipseUI, MiscUI
	for _, gui in { EclipseUI, MiscUI } do
		gui:SetAttribute("EclipseInstance", token)
		gui:SetAttribute("EclipseBuild", build)
		gui:SetAttribute("EclipseBuildId", eclipseScript:GetAttribute("EclipseBuild"))
		gui:SetAttribute("EclipseSource", eclipseScript:GetFullName())
		gui.Enabled = false
	end

	EclipseUI.Name = "Eclipse Editor [" .. edition .. "] " .. token
	MiscUI.Name = "Eclipse Helpers [" .. edition .. "] " .. token
	EclipseUI.Parent = CoreGui
	MiscUI.Parent = CoreGui
	Visibility.init(plugin, EclipseUI, MiscUI)

	local toolbar = plugin:CreateToolbar("Eclipse " .. edition)
	ownedToolbar = toolbar

	local button = toolbar:CreateButton(
		"Eclipse " .. edition,
		"Open Eclipse " .. edition .. " · " .. build,
		"rbxassetid://126656292244944"
	)

	local miscButton = toolbar:CreateButton(
		"Rig Tools",
		"Open " .. edition .. " Rig Tools · " .. build,
		"rbxassetid://93890335549588"
	)

	table.insert(ownedButtons, button)
	table.insert(ownedButtons, miscButton)
	button.ClickableWhenViewportHidden = true
	miscButton.ClickableWhenViewportHidden = true

	local function isAlertOpen(): boolean
		return EclipseUI.Enabled and AlertFrame.Visible
	end

	local activeLock = false

	local function clearNativeSelection()
		local ignore = State.ignoreSelectionChanged
		State.ignoreSelectionChanged = true
		game:GetService("Selection"):Set({})
		State.ignoreSelectionChanged = ignore
	end

	local function updatePluginState()
		local shouldBeActive = PluginActiveBool.Value == true

		pcall(function()
			button:SetActive(shouldBeActive)
		end)

		if shouldBeActive and not State.WorkspaceSelection then
			activeLock = true
			plugin:Activate(true)
		else
			activeLock = false
			plugin:Deactivate()
		end
	end

	local function getVisibleEclipseWindow()
		local floating = EclipseUI:FindFirstChild("EclipseFloatingVisibility")
		local frame = EclipseUI:FindFirstChild("Frame")
			or floating and floating:FindFirstChild("Frame")
		local tabs = frame and frame:FindFirstChild("Tabs")
		if not tabs then
			return nil
		end

		local transformHost = tabs:FindFirstChild("EclipseTransformVisibility")
		local animator = tabs:FindFirstChild("Animator")
			or transformHost and transformHost:FindFirstChild("Animator")
		if animator and animator.Visible then
			return animator
		end

		local primary = tabs:FindFirstChild("Primary")
		if primary and primary.Visible then
			return primary
		end

		return nil
	end

	connect(button.Click, function()
		if State.PresentationHidden then
			Visibility.setHidden(false)
			return
		end

		if isAlertOpen() then
			return
		end

		if EclipseUI.Enabled then
			local inProject = RequestEvent:Invoke("IsInProject")

			if inProject then
				RequestEvent:Invoke("RequestCloseProject")
				return
			end

			WindowFX.shrink(getVisibleEclipseWindow(), function()
				EclipseUI.Enabled = false
			end)
			return
		end

		EclipseUI.Enabled = true
	end)

	connect(miscButton.Click, function()
		if State.PresentationHidden then
			Visibility.setHidden(false)
			return
		end

		if isAlertOpen() then
			return
		end

		if MiscUI.Enabled then
			WindowFX.shrink(MiscUI:FindFirstChild("HelperFrame", true), function()
				MiscUI.Enabled = false
			end)
		else
			if State.HelperMenu then
				State.HelperMenu.captureSelection()
			end

			MiscUI.Enabled = true
		end
	end)

	connect(PluginActiveBool:GetPropertyChangedSignal("Value"), function()
		if PluginActiveBool.Value then
			if State.WorkspaceSelection then
				State.setWorkspaceSelection(false)
				return
			end

			clearNativeSelection()
		end

		updatePluginState()
	end)

	connect(plugin.Unloading, function()
		PluginShell.destroy()
		activeLock = false
		EventPlayback.clear()
		if ClosingEvent then
			ClosingEvent:Fire()
		end

		pcall(WindowFX.releaseTools, CoreGui, token)
		EclipseUI:Destroy()
		MiscUI:Destroy()
	end)

	function State.setWorkspaceSelection(enabled, selectTool, preserveSelection)
		enabled = enabled == true
		if State.WorkspaceSelection == enabled then
			if enabled and selectTool then
				plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())
			end

			return
		end

		local timeline = State.Timeline and State.Timeline:GetState()
		if enabled and (State.LoadingProject or timeline and timeline.Exporting) then
			return
		end

		if enabled then
			require("Project").finalizeCurrentManipulation()
			if timeline and timeline.Playing then
				require("Project").stopAllAnimations()
			end
		end

		if not enabled and not preserveSelection then
			clearNativeSelection()
		end

		State.WorkspaceSelection = enabled
		if State.Axis then
			State.Axis:ClearAxis()
			if not enabled and State.Axis:GetSelectedBone() then
				State.Axis:RefreshAxis()
			end
		end

		if State.Rig then
			for _, rig in State.getAllRigs() do
				State.Rig:LockRigLimbs(rig, not enabled)
			end
		end

		updatePluginState()
		if enabled and selectTool then
			plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())
		end
	end

	function State.claimViewport()
		if not attached or not ownedToolbar or not PluginActiveBool.Value then
			return
		end
		State.setWorkspaceSelection(false, false, true)
		updatePluginState()
		task.defer(function()
			if ownedToolbar and EclipseUI.Parent and EclipseUI.Enabled and PluginActiveBool.Value then
				State.setWorkspaceSelection(false, false, true)
				updatePluginState()
			end
		end)
	end

	local input = require("UserInputService")
	connect(input.InputBegan, function(event)
		if
			State.WorkspaceSelection
			and event.UserInputType == Enum.UserInputType.MouseButton1
			and input.pointerOverUI()
		then
			State.setWorkspaceSelection(false, false, true)
		end
	end)
	connect(plugin.Deactivation, function()
		if activeLock and PluginActiveBool.Value then
			task.defer(function()
				if not (activeLock and PluginActiveBool.Value) or State.WorkspaceSelection then
					return
				end

				if require("History").revertingNative() then
					updatePluginState()
				else
					State.setWorkspaceSelection(true)
				end
			end)
		end
	end)

	updatePluginState()
end

PluginShell.attach = attach

return PluginShell
