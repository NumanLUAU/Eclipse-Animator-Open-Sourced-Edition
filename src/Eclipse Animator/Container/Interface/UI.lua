--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local CoreGui = game:GetService("CoreGui")

local Config = require("Config")

local UI = {}

local resolved = false

local function resolve(eclipseScript: Instance)
	if resolved then
		return UI
	end

	resolved = true

	local ServerScript = eclipseScript
	local Values = ServerScript.Values

	UI.PluginActiveBool = Values.PluginActive
	UI.ClosingEvent = Values.Closing

	UI.RequestEvent = ServerScript:WaitForChild("Players"):WaitForChild("RequestEvent")
	UI.AnimSavesTemplate = ServerScript:WaitForChild("Players"):WaitForChild("AnimSaves")

	local EclipseGUI, MiscGUI = require("PluginShell").getUI(eclipseScript)
	UI.MiscGUI = MiscGUI
	UI.EclipseGUI = EclipseGUI

	local floating = EclipseGUI:FindFirstChild("EclipseFloatingVisibility")
	UI.RootFrame = EclipseGUI:FindFirstChild("Frame")
		or floating and floating:FindFirstChild("Frame")
	UI.Dropdowns = EclipseGUI:FindFirstChild("Dropdowns")
		or floating and floating:FindFirstChild("Dropdowns")
	local Tabs = UI.RootFrame.Tabs
	local Components = UI.RootFrame.Components
	UI.Tabs = Tabs
	UI.Components = Components

	local PrimaryFrame = Tabs:WaitForChild("Primary")
	local FramesFolder = PrimaryFrame:WaitForChild("Frames")
	local MainFrame = FramesFolder.MainSurface

	UI.PrimaryFrame = PrimaryFrame
	UI.FramesFolder = FramesFolder
	UI.MainFrame = MainFrame

	local connectionFrame = Tabs:FindFirstChild("Connection")
	if connectionFrame then
		connectionFrame:Destroy()
	end

	local PrimaryDragFrame = PrimaryFrame:FindFirstChild("Drag")
	if PrimaryDragFrame then
		UI.PrimaryDragFrame = PrimaryDragFrame
		UI.PrimaryDragButton = PrimaryDragFrame:FindFirstChild("DragButton")
	end

	local CenterFrame = MainFrame.Center
	local RightFrame = MainFrame.Right
	UI.CenterFrame = CenterFrame
	UI.RightFrame = RightFrame
	UI.ProjectCreator_BTN = CenterFrame.ProjectCreator
	UI.Label1_LBL = CenterFrame.Label1
	UI.Label2_LBL = CenterFrame.Label2

	local AlertFrame = Components.Alert
	UI.AlertFrame = AlertFrame
	UI.AgreeButton = AlertFrame.Buttons.Agree
	UI.DisagreeButton = AlertFrame.Buttons.Disagree
	UI.HeaderLabel = AlertFrame.Information.Header.Header
	UI.DescriptionLabel = AlertFrame.Information.Description

	UI.NotificationFrame = Components.Notification.Main

	UI.FrameButton = RightFrame.ScrollingFrame
	UI.TemplateButton = RightFrame.ScrollingFrame.Template

	local AnimatorFrame = Tabs:WaitForChild("Animator")
	local AnimatorFrames = AnimatorFrame:WaitForChild("Frames")
	UI.AnimatorFrame = AnimatorFrame
	UI.AnimatorFrames = AnimatorFrames

	local AnimatorDragFrame = AnimatorFrame:FindFirstChild("Drag")
	if AnimatorDragFrame then
		UI.AnimatorDragFrame = AnimatorDragFrame
		UI.AnimatorDragButton = AnimatorDragFrame:FindFirstChild("DragButton")
	end

	local AnimatorBarFrame = AnimatorFrame:WaitForChild("Bar")
	UI.AnimatorBarFrame = AnimatorBarFrame

	UI.ReturnButton = AnimatorFrame.Bar.ControlButtons.ExitButton
	UI.ExportButton = AnimatorFrame.Bar.ControlButtons.ExportButton
	UI.SaveButton = AnimatorFrame.Bar.ControlButtons:FindFirstChild("SaveButton")
	UI.LoopButton = AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv.Loop
	UI.AddRigButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("AddRig")
	UI.RecordButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("Record")

	UI.FPSLabel = AnimatorFrames.Main.Content.LeftDiv.TopContainer.RightDiv.Time.FramesPerSecond
	UI.TimeLabel = AnimatorFrames.Main.Content.LeftDiv.TopContainer.RightDiv.Time.Time
	UI.ProjectNameTextBox =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.RightDiv.ProjectName.Edit
	UI.ProjectNameTextBox.PlaceholderText = "Eclipse Animation"
	UI.ProjectNameTextBox.ClearTextOnFocus = false

	local header = AnimatorFrames.Main.Content.LeftDiv.TopContainer
	header.LeftDiv.AutomaticSize = Enum.AutomaticSize.None
	header.LeftDiv.Size = UDim2.new(0, 80, 1, 0)
	for _, button in { UI.AddRigButton, UI.LoopButton, UI.RecordButton } do
		if button then
			button.Size = UDim2.fromOffset(24, 24)
		end
	end

	header.RightDiv.AutomaticSize = Enum.AutomaticSize.None
	header.RightDiv.Size = UDim2.new(1, -84, 1, 0)
	header.RightDiv.ClipsDescendants = true
	header.RightDiv.ProjectName.Size = UDim2.new(1, 0, 0, 14)
	header.RightDiv.Time.Size = UDim2.new(1, 0, 0, 16)
	for _, label in { UI.TimeLabel, UI.FPSLabel } do
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.TextSize = 10
		label.TextYAlignment = Enum.TextYAlignment.Center
	end

	local headerLayout = header.RightDiv:FindFirstChildOfClass("UIListLayout")
	if headerLayout then
		headerLayout.Padding = UDim.new(0, 0)
	end

	UI.ProjectNameTextBox.AutomaticSize = Enum.AutomaticSize.None
	UI.ProjectNameTextBox.Position = UDim2.fromOffset(0, 0)
	UI.ProjectNameTextBox.Size = UDim2.fromScale(1, 1)
	UI.ProjectNameTextBox.TextTruncate = Enum.TextTruncate.AtEnd

	local TopSlider = AnimatorFrames.Main.BottomContainer.TopSlider.Drag
	UI.TopSlider = TopSlider
	UI.LeftDrag = TopSlider.LeftDrag
	UI.RightDrag = TopSlider.RightDrag

	local AnimatorMain = AnimatorFrames.Main
	local LeftDiv = AnimatorMain.Content.LeftDiv
	local RightDiv = AnimatorMain.Content.RightDiv
	UI.AnimatorMain = AnimatorMain
	UI.LeftDiv = LeftDiv
	UI.RightDiv = RightDiv

	local TimelineContainer = RightDiv.TimelineContainer
	local Scale = TimelineContainer.Scale
	local Fit = Scale.Fit
	local KeysRoot = Scale.Keys
	local Misc = Scale.Misc
	UI.TimelineContainer = TimelineContainer
	UI.Scale = Scale
	UI.SelectionBox = Scale:FindFirstChild("SelectionBox")
	UI.Fit = Fit
	UI.KeysRoot = KeysRoot
	UI.Misc = Misc

	local GuidesFolder = Misc.Guides
	UI.GuidesFolder = GuidesFolder
	UI.GuideTemplate = GuidesFolder.Guide0

	local TickFrame = Misc.TickFrame
	TickFrame:WaitForChild("Position"):WaitForChild("Line"):SetAttribute("ThemeBg", "Div")
	local TickNumberContainer = TickFrame.Number
	UI.TickFrame = TickFrame
	UI.TickNumberContainer = TickNumberContainer
	UI.TickTemplate = TickNumberContainer.Tick0

	local TopSelector = TickNumberContainer.TopSelector
	UI.TopSelector = TopSelector
	UI.TopSelectorLabel = TopSelector.TextLabel
	UI.DragBarHitbox = TimelineContainer.DragBarHitbox

	local SelectorContainer = Scale.SelectorContainer
	UI.SelectorContainer = SelectorContainer
	UI.Selector = SelectorContainer.Selector

	local TrackContainer = KeysRoot.TemplateFrame
	UI.TrackContainer = TrackContainer
	UI.TrackTemplate = TrackContainer:FindFirstChild("TrackContainers")
		:FindFirstChild("TrackTemplate")

	local RigListScroll = LeftDiv.RigListContainer.RigContainerScroll
	UI.RigListScroll = RigListScroll
	UI.RigItemTemplate = RigListScroll.ItemTemplate

	local BarFrame = PrimaryFrame:WaitForChild("Bar")
	UI.BarFrame = BarFrame

	local MenuButtons = BarFrame:WaitForChild("MenuButtons")
	UI.MenuButtons = MenuButtons
	local riggingButton = MenuButtons:FindFirstChild("RiggingButton")
	if riggingButton then
		riggingButton:Destroy()
	end

	UI.ArmatureButton = MenuButtons:FindFirstChild("ArmatureButton")

	local ControlButtons = BarFrame:WaitForChild("ControlButtons")
	UI.ControlButtons = ControlButtons
	UI.ExitButton = ControlButtons:WaitForChild("ExitButton")

	UI.AxisPackage = {
		PositionAxis = EclipseGUI.Axis.Position,
		RotationAxis = EclipseGUI.Axis.Rotation,
	}

	return UI
end

local function isAnimatorActive(loading, transport)
	local state = require("State")
	if
		state.LoadingProject
		and not (loading == true and state.ProjectLoadThread == coroutine.running())
	then
		return false
	end

	return UI.EclipseGUI ~= nil
		and UI.EclipseGUI.Parent ~= nil
		and UI.EclipseGUI.Enabled == true
		and UI.EclipseGUI:GetAttribute("EclipseConfirmationOpen") ~= true
		and UI.AnimatorFrame ~= nil
		and (UI.AnimatorFrame.Visible == true or state.CameraPoseMode == true or transport and state.PresentationHidden == true)
end

UI.resolve = resolve
UI.isAnimatorActive = isAnimatorActive
UI.isTransportActive = function() return isAnimatorActive(false, true) end

return UI
