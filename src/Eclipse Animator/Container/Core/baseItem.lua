--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local CameraRig = require("CameraRig")
local item = {}
local KeyframePolicy = require("Policy")
local UserInputService = require("UserInputService")

local ParentingUI = require("ParentingUI")
local LimbIK = require("LimbIK")
local HeadStabilizer = require("HeadStabilizer")
local EventIcons = require("EventIcons")
local Preferences = require("Preferences")
local TrackHierarchy = require("Hierarchy")
local Theme = require("Theme")
local WindowFX = require("WindowFX")
local motionPath = require("motionPath")
local UI_CONFIG = require("UI_CONFIG")
local DESCRIPTIONS = UI_CONFIG.Descriptions or {}

local MOTION_PATH_ON = Color3.fromRGB(101, 180, 244)
local MOTION_PATH_OFF = Color3.fromRGB(185, 185, 185)
local TRACK_ENABLED_COLOR = Color3.fromRGB(113, 255, 61)
local TRACK_DISABLED_COLOR = Color3.fromRGB(58, 58, 58)
local RIGHT_DIV_HOVER_LIGHTEN = 0.35
local RIGHT_DIV_PRESS_BG = Color3.fromRGB(134, 134, 134)

local MASTER_IMG = "rbxassetid://101128690421923"
local BONE_IMG = "rbxassetid://96669723126361"
local CHANNEL_IMG = "rbxassetid://94965188299291"
local MASTER_IMG_COLOR = Color3.fromRGB(180, 215, 255)
local BONE_IMG_COLOR = Color3.fromRGB(97, 255, 197)
local BONE_IMG_OPEN_COLOR = Color3.fromRGB(150, 150, 150)
local CHANNEL_IMG_COLOR = Color3.fromRGB(255, 158, 119)
local ARMATURE_IMG = "rbxassetid://113549029098097"
local ARMATURE_IMG_COLOR = Color3.fromRGB(245, 150, 85)

local TRANSFORM_CHANNELS_ATTR = "EclipseTransformChannelsOpen"

local CHANNELS_DEFINITION = {
	{ name = "X Location", id = "loc_x" },
	{ name = "Y Location", id = "loc_y" },
	{ name = "Z Location", id = "loc_z" },
	{ name = "X Euler Rotation", id = "rot_x" },
	{ name = "Y Euler Rotation", id = "rot_y" },
	{ name = "Z Euler Rotation", id = "rot_z" },
	{ name = "W Quaternion Rotation", id = "qrot_w" },
	{ name = "X Quaternion Rotation", id = "qrot_x" },
	{ name = "Y Quaternion Rotation", id = "qrot_y" },
	{ name = "Z Quaternion Rotation", id = "qrot_z" },
	{ name = "X Scale", id = "scale_x" },
	{ name = "Y Scale", id = "scale_y" },
	{ name = "Z Scale", id = "scale_z" },
}

local function lightenColor(color)
	return Color3.new(
		math.min(color.R + RIGHT_DIV_HOVER_LIGHTEN, 1),
		math.min(color.G + RIGHT_DIV_HOVER_LIGHTEN, 1),
		math.min(color.B + RIGHT_DIV_HOVER_LIGHTEN, 1)
	)
end

local function rightDivHoverProps()
	local props = {}
	props.Hover = {
		ImageColor3 = function(element)
			local idleColor = (props.Idle and props.Idle.ImageColor3) or element.ImageColor3
			if type(idleColor) == "function" then
				idleColor = idleColor(element)
			end

			return lightenColor(idleColor)
		end,
	}
	props.Press = {
		BackgroundColor3 = RIGHT_DIV_PRESS_BG,
	}
	return props
end

local data_debug = {
	flags = {
		trackElementOffset = false,
		trackElementName = false,
		coloredTracks = false,
		infoHover = false,
		trackIfAskedUponHidingContents = false,
	},
	misc = {
		trackElementOffsetAmount = 20,

		lastColoredTrackIndex = 0,
		coloredTracks = {
			Color3.fromRGB(255, 0, 0),
			Color3.fromRGB(0, 255, 0),
			Color3.fromRGB(0, 0, 255),
			Color3.fromRGB(255, 255, 0),
			Color3.fromRGB(0, 255, 255),
			Color3.fromRGB(255, 0, 255),
			Color3.fromRGB(255, 128, 0),
			Color3.fromRGB(128, 0, 255),
			Color3.fromRGB(128, 255, 0),
			Color3.fromRGB(255, 105, 180),
		},
	},
}

local function _debugPickColorFromTrack()
	if data_debug.misc.lastColoredTrackIndex >= #data_debug.misc.coloredTracks then
		data_debug.misc.lastColoredTrackIndex = 0
	end

	data_debug.misc.lastColoredTrackIndex += 1

	return data_debug.misc.coloredTracks[data_debug.misc.lastColoredTrackIndex]
end

function item:setSelected(state)
	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		state = false
	end

	state = state == true
	if self._selectionPainted == state then
		return
	end

	local wasSelected = self._selectionPainted
	self._selectionPainted = state
	local helpers = self.rigModule.refs.UIHelpers
	local opacity = state and 0.15 or 1

	self.appearDetails:SetAttribute("ThemeBgTransparency", opacity)
	WindowFX.setRestingProperty(self.appearDetails, "BackgroundTransparency", opacity)
	if state then
		self.appearDetails.BackgroundColor3 = helpers.coloredButton
	else
		self.appearDetails.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end

	Theme.applyInstance(self.appearDetails)

	local line = self.selectionLine
	if line and (state or wasSelected) then
		line:SetAttribute("ThemeBg", state and "KfS" or self._trackLineTheme)
		line:SetAttribute("ThemeBgTransparency", state and 0.25 or self._trackLineStateTransparency)
		WindowFX.setRestingProperty(
			line,
			"BackgroundTransparency",
			state and 0.25 or self._trackLineTransparency
		)
		Theme.applyInstance(line)
	end
end

function item.initialize(
	uiElement,
	trackName: string,
	trackImage: string?,
	trackElement: GuiObject,
	trackIsMaster: boolean,
	linkedRigInstance: any?,
	itemKind: string?
)
	local self = setmetatable({ connections = {}, childItems = {} }, { __index = item })

	self.appearDetails = uiElement.AppearDetails
	self.selectionLine = trackElement:FindFirstChild("Line")
	if self.selectionLine then
		self._trackLineTheme = self.selectionLine:GetAttribute("ThemeBg")
		self._trackLineStateTransparency = self.selectionLine:GetAttribute("ThemeBgTransparency")
		self._trackLineTransparency = self.selectionLine.BackgroundTransparency
	end

	self.childContainer = uiElement.ChildrenContainer
	local guide = self.childContainer:FindFirstChild("ListMonger")
	if guide then
		guide:SetAttribute("ThemeBg", "Strk")
		guide.BackgroundTransparency = 0.15
		guide:SetAttribute("EOrig_BackgroundTransparency", 0.15)
	end

	self.appearDetails.LayoutOrder = 0
	self.childContainer.LayoutOrder = 1
	self.centerDiv = self.appearDetails.CenterDiv
	self.leftDiv = self.appearDetails.LeftDiv
	self.moreButton = self.leftDiv.More
	self:setMoreButtonVisibility(false)

	self.itemKind = itemKind or (trackIsMaster and "master" or "bone")

	if self.selectionLine then
		local position = self.selectionLine.Position
		self.selectionLine.Position = UDim2.new(
			position.X.Scale,
			position.X.Offset,
			0,
			self.appearDetails.Size.Y.Offset * 0.5
		)
		self.selectionLine.Visible = self.itemKind ~= "armature"
			and self.itemKind ~= "folder"
			and self.itemKind ~= "properties"
	end

	self:setSelected(false)

	uiElement.Visible = true
	if self.itemKind == "channel" then
		trackElement.Visible = false
	else
		trackElement.Visible = true
	end

	if
		self.itemKind == "armature"
		or self.itemKind == "folder"
		or self.itemKind == "properties"
	then
		trackElement.BackgroundTransparency = 1
		for _, child in ipairs(trackElement:GetDescendants()) do
			if child:IsA("GuiObject") then
				child.Visible = false
			end
		end
	end

	self.childContainer.Visible = false

	self.centerDiv.Title.Text = string.upper(trackName)
	local hidden = require("Organization").isBoneHidden(linkedRigInstance)
	self.centerDiv.Title:SetAttribute("ThemeTxtTransparency", hidden and 0.55 or 0)
	self.centerDiv.Title.TextTransparency = hidden and 0.55 or 0

	local img = self.centerDiv.ImgContainer.Img
	local hoverDialog = self.rigModule.refs.UIHelpers.hoverDialog
	if self.itemKind == "property" or self.itemKind == "properties" then
		img.Image = self.itemKind == "properties" and self.rigModule.refs.FolderIcon
			or "rbxassetid://137624247626747"
		img.ImageColor3 = Color3.fromRGB(180, 215, 255)
		img.Active = false
		img.AutoButtonColor = false
	elseif self.itemKind == "master" then
		img.Image = CameraRig.isRig(linkedRigInstance) and CameraRig.ICON or MASTER_IMG
		img.ImageColor3 = MASTER_IMG_COLOR
		img.Active = false
		img.AutoButtonColor = false
		if hoverDialog and DESCRIPTIONS.MasterRig then
			hoverDialog:latchToInstance(img, DESCRIPTIONS.MasterRig)
		end
	elseif self.itemKind == "cameraattach" then
		img.Image = "rbxassetid://104487897747120"
		img.ImageColor3 = BONE_IMG_COLOR
		img.Active = false
		img.AutoButtonColor = false
	elseif self.itemKind == "camtarget" then
		img.Image = "rbxassetid://104487897747120"
		img.ImageColor3 = Color3.fromRGB(184, 142, 239)
		img:SetAttribute("ThemeImg", nil)
		img.Active, img.AutoButtonColor = false, false
		img.ScaleType = Enum.ScaleType.Fit
	elseif self.itemKind == "camerafov" or self.itemKind == "cameracframe" then
		img.Image = self.itemKind == "camerafov" and "rbxassetid://137624247626747"
			or CameraRig.ICON
		img.ImageColor3 = BONE_IMG_COLOR
		img.Active, img.AutoButtonColor = false, false
	elseif self.itemKind == "folder" then
		img.Image = self.rigModule.refs.FolderIcon or ""
		img.ImageColor3 = Color3.fromRGB(255, 190, 151)
		local aspect = img:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect:Destroy()
		end

		img.ScaleType = Enum.ScaleType.Stretch
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.9, 1.1)
		img.Active = false
		img.AutoButtonColor = false
	elseif
		self.itemKind == "events"
		or self.itemKind == "subtitles"
		or self.itemKind == "faces"
	then
		img.Image = self.itemKind == "faces" and require("Faces").ICON
			or "rbxassetid://86922940562132"
		img.ImageColor3 = Color3.fromRGB(255, 208, 97)
		img:SetAttribute("EOrig_ImageColor3", img.ImageColor3)
		img:SetAttribute("ThemeImg", "Ph")
		img:SetAttribute("ThemeShade", 0.2)
		if self.itemKind == "subtitles" then
			img.Image = "rbxassetid://90407998983360"
			img.ScaleType = Enum.ScaleType.Fit
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(1.4, 1.4)
			for _, object in { img.Parent, img } do
				local aspect = object:FindFirstChildOfClass("UIAspectRatioConstraint")
				if aspect then
					aspect.AspectRatio = 1
				end
			end

			img.ImageColor3 = Color3.new(1, 1, 1)
			img:SetAttribute("EOrig_ImageColor3", img.ImageColor3)
			img:SetAttribute("ThemeImg", "Txt")
			img:SetAttribute("ThemeShade", nil)
		elseif self.itemKind == "faces" then
			require("Faces").attach(img)
		else
			EventIcons.attach(img, "track")
		end

		img.Active = false
		img.AutoButtonColor = false
	elseif self.itemKind == "origin" then
		img.Image = "rbxassetid://78509411094647"
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageColor3 = Color3.fromRGB(184, 142, 239)
		img:SetAttribute("ThemeImg", nil)
		img.Active, img.AutoButtonColor = false, false
	elseif self.itemKind == "armature" then
		img.Image = ARMATURE_IMG
		img.ImageColor3 = ARMATURE_IMG_COLOR
		img.Active = false
		img.AutoButtonColor = false
	elseif self.itemKind == "displaybone" then
		img.Image = trackImage or BONE_IMG
		img.ImageColor3 = BONE_IMG_COLOR
		img.Active = true
		img.AutoButtonColor = false
		if hoverDialog and DESCRIPTIONS.TransformChannels then
			hoverDialog:latchToInstance(img, DESCRIPTIONS.TransformChannels)
		end
	elseif self.itemKind == "channel" then
		img.Image = CHANNEL_IMG
		img.ImageColor3 = CHANNEL_IMG_COLOR
		img.Active = false
		img.AutoButtonColor = false
		if hoverDialog and DESCRIPTIONS.TransformChannelClass then
			hoverDialog:latchToInstance(img, DESCRIPTIONS.TransformChannelClass)
		end
	else
		img.Image = trackImage or BONE_IMG
		img.ImageColor3 = BONE_IMG_COLOR
		img.Active = true
		img.AutoButtonColor = false
		if hoverDialog and DESCRIPTIONS.TransformChannels then
			hoverDialog:latchToInstance(img, DESCRIPTIONS.TransformChannels)
		end
	end

	self.trackColor = img.ImageColor3
	self.openedState = false
	self.transformChannelsOpen = false
	self.transformChannelItems = nil

	self.trackName = trackName
	self.uiElement = uiElement
	self.trackElement = trackElement
	self.trackIsMaster = trackIsMaster
	self.linkedRigInstance = linkedRigInstance

	table.insert(
		self.connections,
		self.moreButton.MouseButton1Click:Connect(function()
			if not self.moreButton.Active then
				return
			end

			self:setOpenState(not self.openedState)
		end)
	)

	table.insert(
		self.connections,
		self.centerDiv.MouseButton1Click:Connect(function()
			self:onNameClicked()
		end)
	)

	if
		self.itemKind == "bone"
		or self.itemKind == "displaybone"
		or self.itemKind == "ikcontrol"
		or self.itemKind == "mastercontrol"
	then
		table.insert(
			self.connections,
			img.MouseButton1Click:Connect(function()
				if Preferences.get("TransformChannels") == false then
					require("Notification").show(
						"TRANSFORM CHANNELS",
						"Enable transform channels in Settings > Preferences",
						4
					)
					return
				end

				self:toggleTransformChannels()
			end)
		)
	end

	if self.itemKind == "channel" then
		local rightDiv = self.uiElement.AppearDetails:FindFirstChild("RightDiv")
		if rightDiv then
			for _, btn in rightDiv:GetChildren() do
				if btn:IsA("GuiButton") then
					if btn.Name == "Disable" then
						self.disableButton = btn
						self.disabled = false
						btn.BackgroundTransparency = 1
						self:_repaintDisable()
						self._disableHoverProps = rightDivHoverProps()
						self.rigModule.refs.UIHelpers:bindToUIStates(btn, self._disableHoverProps)
						self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(
							btn,
							DESCRIPTIONS.Disable
						)
						table.insert(
							self.connections,
							btn.MouseButton1Click:Connect(function()
								self:setChannelDisabled(not self.disabled)
							end)
						)
					else
						btn.Visible = false
					end
				end
			end
		end

		self:setupDebug()
		return self
	end

	if self.itemKind == "properties" or self.itemKind == "folder" then
		for _, button in self.appearDetails.RightDiv:GetChildren() do
			if button:IsA("GuiButton") then
				button.Visible = false
			end
		end

		self:setupDebug()
		return self
	end

	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		self:setupDebug()
		return self
	end

	self.motionPathButton = self.itemKind ~= "property"
			and self.uiElement.AppearDetails.RightDiv:FindFirstChild("MotionPath")
		or nil
	self.motionPathEnabled = false
	self.disableButton = self.uiElement.AppearDetails.RightDiv:FindFirstChild("Disable")
	self.disabled = false

	for _, button in self.uiElement.AppearDetails.RightDiv:GetChildren() do
		if not button:IsA("GuiButton") then
			continue
		end

		if self.itemKind == "property" and button.Name ~= "Disable" then
			button.Visible = false
			continue
		end

		if
			(
				self.itemKind == "camtarget"
				or self.itemKind == "camerafov"
				or self.itemKind == "cameracframe"
				or CameraRig.isRig(linkedRigInstance)
			)
			and button.Name ~= "Disable"
			and (button.Name ~= "MotionPath" or self.itemKind == "camerafov")
		then
			button.Visible = false
			continue
		end

		if self.itemKind == "origin" and button.Name ~= "Disable" then
			button.Visible = false
			continue
		end

		if button.Name == "More" then
			button.Visible = false
			continue
		end

		if button == self.motionPathButton then
			continue
		end

		if button == self.disableButton then
			continue
		end

		button.BackgroundTransparency = 1
		self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(
			button,
			DESCRIPTIONS[button.Name] or DESCRIPTIONS.More
		)
		self.rigModule.refs.UIHelpers:bindToUIStates(button, rightDivHoverProps())
	end

	if self.motionPathButton then
		self.motionPathButton.BackgroundTransparency = 1
		self:_repaintMotionPath()
		self._motionPathHoverProps = rightDivHoverProps()
		self.rigModule.refs.UIHelpers:bindToUIStates(
			self.motionPathButton,
			self._motionPathHoverProps
		)
		self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(
			self.motionPathButton,
			DESCRIPTIONS.MotionPath
		)
		table.insert(
			self.connections,
			self.motionPathButton.MouseButton1Click:Connect(function()
				self:setMotionPath(not self.motionPathEnabled, self.trackIsMaster)
			end)
		)
	end

	if self.disableButton then
		self.disableButton.BackgroundTransparency = 1
		self:_repaintDisable()
		self._disableHoverProps = rightDivHoverProps()
		self.rigModule.refs.UIHelpers:bindToUIStates(self.disableButton, self._disableHoverProps)
		self:_repaintDisable()
		self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(
			self.disableButton,
			DESCRIPTIONS.Disable
		)
		table.insert(
			self.connections,
			self.disableButton.MouseButton1Click:Connect(function()
				self:setDisabled(not self.disabled, self.trackIsMaster)
			end)
		)
	end

	if self.trackIsMaster then
		require("Effects").bindFovRow(self)
		require("fov").bindRow(self)
	end

	if self.itemKind == "camtarget" then
		require("Targets").bindRow(self)
	end

	self:refreshDisplayPreferences()
	self:setupDebug()

	return self
end

function item:refreshDisplayPreferences()
	self:refreshTransformChannelPreference()
	if self.motionPathButton then
		self.motionPathButton.Visible = self.itemKind ~= "origin"
			and self.itemKind ~= "camerafov"
			and Preferences.get("ShowMotionPaths")
	end

	if self.ikButton then
		self.ikButton.Visible = Preferences.get("ShowFKIK")
	end

	if self.headStabilizerButton then
		self.headStabilizerButton.Visible = Preferences.get("ShowHeadStabilizer")
	end

	self:paintEventsVisibility()
end

function item:eventsVisible()
	if self.itemKind == "subtitles" then
		local e = require("Events").get(self.linkedRigInstance).Events[self.subtitleId]
		return e ~= nil and e.Subtitle ~= nil
	end

	local track = require("Events").get(self.linkedRigInstance)
	return self.itemKind == "faces" and track.FacesEnabled == true
		or self.itemKind ~= "faces" and track.Enabled ~= false
end

function item:paintEventsVisibility()
	local button = self.eventsVisibilityButton
	if not button then
		return
	end

	local visible = self:eventsVisible()
	local color = Color3.fromRGB(255, 208, 97)
	button:SetAttribute("ThemeImg", visible and "Ph" or nil)
	button:SetAttribute("ThemeShade", visible and 0.2 or nil)
	button:SetAttribute("EOrig_ImageColor3", color)
	if Theme.getOverride("Ph") then
		color = Theme.get("Ph", color):Lerp(Color3.new(1, 1, 1), 0.2)
	end

	button.ImageColor3 = visible and color or Color3.fromRGB(185, 185, 185)
end

function item:setEventsVisible(visible)
	self.linkedRigInstance:SetAttribute("EclipseEventsHidden", visible ~= true)
	self:paintEventsVisibility()
	self.rigModule:RefreshSelectionFilter()
end

function item:bindEventsVisibility() end

function item:bindParentingControl()
	if self.parentingButton or (self.itemKind ~= "bone" and self.itemKind ~= "displaybone") then
		return
	end

	local motor = self:fetchMotor()
	local timeline = self.rigModule.refs.Timeline
	if not motor or not timeline or (typeof(motor) == "table" and motor.IsEclipseIKHandle) then
		return
	end

	local button = ParentingUI.modeButton(self.appearDetails.RightDiv, "Parenting")
	button.LayoutOrder = -1
	self.parentingButton = button
	local rig = self.grandpa and self.grandpa.linkedRigInstance

	local function repaint(parented, driven, child)
		ParentingUI.paint(button, parented)

		button.Active = true
		button.TextTransparency = 0
		button.Visible = true
	end

	timeline:RegisterParentingControl(button, motor, repaint, rig)
	self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(button, function()
		local time = timeline:GetState().CurrentTime
		local parented = timeline:IsParentedAtTime(motor, time)
		if LimbIK.isDriven(motor, time) then
			return "IK follows parent. Click for World and switch this limb to FK."
		end

		if HeadStabilizer.isEnabled(motor, time) then
			return "Rotation inheritance is disabled. Turn IR on in Rig > Bone Settings to change parenting."
		end

		local link = require("Target").childAt(motor, time)
		if link then
			return "Parent: "
				.. tostring(link.label or "part")
				.. ". Click to switch Parent / World."
		end

		return parented
				and "Follows Parent, Toggle for World (unparented). Right-click for Child Of."
			or "Stays in world. Click for Parent. Right-click for Child Of."
	end)
	table.insert(
		self.connections,
		button.MouseButton1Click:Connect(function()
			timeline:SwitchParentingAtCurrentTime(motor, self.grandpa.linkedRigInstance)
		end)
	)
	table.insert(
		self.connections,
		button.MouseButton2Click:Connect(function()
			require("Targets").openChild(motor, self.grandpa.linkedRigInstance)
		end)
	)
end

function item:bindIKControl()
	if self.ikButton or (self.itemKind ~= "bone" and self.itemKind ~= "displaybone") then
		return
	end

	local motor = self:fetchMotor()
	local rig = self.grandpa and self.grandpa.linkedRigInstance
	if not motor or not LimbIK.chain(rig, motor) then
		return
	end

	local timeline = self.rigModule.refs.Timeline
	local button = ParentingUI.modeButton(self.appearDetails.RightDiv, "Kinematics")
	button.LayoutOrder = -2
	button.TextSize = 9
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.TextYAlignment = Enum.TextYAlignment.Center
	self.ikButton = button
	button.Visible = Preferences.get("ShowFKIK")
	timeline:RegisterIKControl(button, motor, function(enabled)
		button.Text = enabled and "IK" or "FK"
		button.LayoutOrder = -2
		button.TextColor3 = enabled and Color3.fromRGB(197, 160, 255)
			or Color3.fromRGB(160, 147, 173)
		button.BackgroundTransparency = enabled and 0.35 or 1
	end)
	self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(button, "FK / IK")
	table.insert(
		self.connections,
		button.MouseButton1Click:Connect(function()
			timeline:SwitchIKAtCurrentTime(motor, rig)
		end)
	)
end

function item:bindHeadStabilizerControl()
	if
		self.headStabilizerButton or (self.itemKind ~= "bone" and self.itemKind ~= "displaybone")
	then
		return
	end

	local motor = self:fetchMotor()
	if not require("cache").isHead(motor) then
		return
	end

	local timeline = self.rigModule.refs.Timeline
	local rig = self.grandpa.linkedRigInstance
	local button = ParentingUI.modeButton(self.appearDetails.RightDiv, "HeadStabilizer")
	button.LayoutOrder = -2
	button.Text, button.TextSize = "IR", 9
	button.TextXAlignment, button.TextYAlignment =
		Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
	self.headStabilizerButton = button
	button.Visible = Preferences.get("ShowHeadStabilizer")
	timeline:RegisterHeadStabilizerControl(button, motor, function(stabilized)
		local enabled = stabilized
		button.LayoutOrder = -2
		button.TextColor3 = enabled and Color3.fromRGB(197, 160, 255)
			or Color3.fromRGB(160, 147, 173)
		button.BackgroundTransparency = enabled and 0.35 or 1
	end)
	self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(button, "Inherit Rotation (IR)")
	table.insert(
		self.connections,
		button.MouseButton1Click:Connect(function()
			timeline:SwitchHeadStabilizerAtCurrentTime(motor, rig)
		end)
	)
end

function item:_repaintMotionPath()
	if not self.motionPathButton then
		return
	end

	local color = self.motionPathEnabled and MOTION_PATH_ON or MOTION_PATH_OFF
	self.motionPathButton.ImageColor3 = color
	if self._motionPathHoverProps and self._motionPathHoverProps.Idle then
		self._motionPathHoverProps.Idle.ImageColor3 = color
	end
end

function item:setMotionPath(enabled, propagate)
	if self.itemKind == "properties" or self.itemKind == "folder" then
		return
	end

	if self.itemKind == "camerafov" then
		return
	end

	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		return
	end

	self.motionPathEnabled = enabled and true or false
	self:_repaintMotionPath()
	if self.motionPathEnabled then
		motionPath.enable(self)
	else
		motionPath.disable(self)
	end

	if propagate then
		for _, child in self.childItems do
			child:setMotionPath(enabled, true)
		end
	end
end

function item:isMotionPathEnabled()
	return self.motionPathEnabled == true
end

function item:_repaintDisable()
	if not self.disableButton then
		return
	end

	local key = self.disabled and "TrackOff" or "TrackOn"
	local color = Theme.get(key, self.disabled and TRACK_DISABLED_COLOR or TRACK_ENABLED_COLOR)
	self.disableButton:SetAttribute("ThemeImg", key)
	self.disableButton:SetAttribute(
		"EOrig_ImageColor3",
		self.disabled and TRACK_DISABLED_COLOR or TRACK_ENABLED_COLOR
	)
	self.disableButton:SetAttribute("EOrig_ImageTransparency", 0)
	Theme.applyInstance(self.disableButton)
	self.disableButton.ImageColor3 = color
	if self._disableHoverProps and self._disableHoverProps.Idle then
		self._disableHoverProps.Idle.ImageColor3 = function()
			return Theme.get(key, self.disabled and TRACK_DISABLED_COLOR or TRACK_ENABLED_COLOR)
		end
	end
end

function item:setDisabled(disabled, propagate)
	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		return
	end

	if self.rigModule.SetHierarchyItemDisabled and self.rigModule._organizationReady then
		self.rigModule:SetHierarchyItemDisabled(self, disabled, propagate)
		return
	end

	local changes = {}
	disabled = disabled == true

	local function collect(row)
		if row.itemKind == "events" or row.itemKind == "subtitles" or row.itemKind == "faces" then
			return
		end

		local motor = row:fetchMotor()
		if
			row.disabled ~= disabled
			or motor and (motor:GetAttribute("EclipseDisabled") == true) ~= disabled
		then
			table.insert(changes, {
				row = row,
				motor = motor,
				before = row.disabled == true,
				attribute = motor and motor:GetAttribute("EclipseDisabled"),
			})
		end

		if propagate then
			for _, child in row.childItems do
				collect(child)
			end
		end
	end

	collect(self)
	if #changes == 0 then
		return
	end

	local function apply(undo)
		for _, change in changes do
			local value = disabled
			if undo then
				value = change.before
			end

			change.row.disabled = value
			change.row:_repaintDisable()
			if change.motor then
				local attribute = value and true or nil
				if undo then
					attribute = change.attribute
				end

				change.motor:SetAttribute("EclipseDisabled", attribute)
			end
		end

		require("State").currentProjectSaved = false
		self:refreshControlPose()
	end

	require("History").record(function()
		apply(true)
	end, function()
		apply(false)
	end, disabled and "Disable tracks" or "Enable tracks")
	apply(false)
end

function item:refreshControlPose()
	local target = self.parentBoneItem or self
	if target.itemKind ~= "ikcontrol" and not HeadStabilizer.isEligible(target:fetchMotor()) then
		return
	end

	local timeline = self.rigModule.refs.Timeline
	timeline:ApplyPoseAtTime(self.grandpa.linkedRigInstance, timeline:GetState().CurrentTime)
end

function item:isDisabled()
	return self.disabled == true
end

function item:setChannelDisabled(disabled)
	local motor = self.parentBoneItem and self.parentBoneItem:fetchMotor()
	if not motor or not self.channelId then
		return
	end

	local id = self.channelId
	local attribute = "EclipseChannelDisabled_" .. id
	local before = motor:GetAttribute(attribute)
	local after = disabled and true or nil
	if before == after then
		return
	end

	local rigModule = self.rigModule

	local function apply(value)
		motor:SetAttribute(attribute, value)
		local anyStill = false
		for _, def in CHANNELS_DEFINITION do
			if motor:GetAttribute("EclipseChannelDisabled_" .. def.id) then
				anyStill = true
				break
			end
		end

		motor:SetAttribute("EclipseChannelDisabledAny", anyStill and true or nil)

		local function refresh(row)
			if row.uiElement and not row.uiElement.Parent then
				return
			end

			if
				row.channelId == id
				and row.parentBoneItem
				and row.parentBoneItem:fetchMotor() == motor
			then
				row.disabled = value == true
				row:_repaintDisable()
			end
		end

		refresh(self)

		for _, row in rigModule._orderedItems or {} do
			refresh(row)
			for _, channel in row.transformChannelItems or {} do
				refresh(channel)
			end
		end

		require("State").currentProjectSaved = false
		local timeline = rigModule.refs.Timeline
		if timeline and self.grandpa and self.grandpa.linkedRigInstance then
			timeline:ApplyPoseAtTime(
				self.grandpa.linkedRigInstance,
				timeline:GetState().CurrentTime
			)
		end
	end

	require("History").record(function()
		apply(before)
	end, function()
		apply(after)
	end, disabled and "Disable channel" or "Enable channel")
	apply(after)
end

function item:onNameClicked()
	if self._destroyed then
		return
	end

	local rig = self.rigModule
	local handled
	if rig.HandleHierarchyClick then
		handled = rig:HandleHierarchyClick(self)
	else
		self:selectBone()
	end

	local session = rig._hierarchyOrganization
	if
		handled ~= nil
		or (session and (session.renameBox or session.drag))
		or (rig._suppressHierarchyClickUntil or 0) > os.clock()
		or UserInputService:GetFocusedTextBox()
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
	then
		rig._keyNameClick = nil
		return
	end

	local kind = self.itemKind
	local motor = kind == "channel" and self.parentBoneItem and self.parentBoneItem:fetchMotor()
		or self:fetchMotor()
	if
		kind == "origin"
		or kind == "folder"
		or kind == "properties"
		or kind == "armature"
		or kind == "faces"
		or kind == "subtitles"
		or (not self.trackIsMaster and not motor and kind ~= "cameraattach" and kind ~= "events")
	then
		rig._keyNameClick = nil
		return
	end

	local now = os.clock()
	local previous = rig._keyNameClick
	if previous and previous.item == self and now - previous.time <= 0.32 then
		rig._keyNameClick = nil
		if self.trackIsMaster then
			require("Project").recordRigTrackKeys(self)
		elseif kind == "events" then
			local timeline = rig.refs.Timeline
			local owner = self.grandpa and self.grandpa.linkedRigInstance
			if owner and owner.Parent and not timeline:IsExportLocked() then
				timeline:AddEvent(
					owner,
					timeline:TimeToFrame(timeline:GetState().CurrentTime),
					true
				)
			end
		elseif kind == "cameraattach" then
			require("Targets").openCameraAttachment(CameraRig.owner(self.linkedRigInstance))
		else
			require("Project").recordTrackKey(self)
		end
	else
		rig._keyNameClick = { item = self, time = now }
	end
end

function item:fetchMotor()
	if self.itemKind == "properties" then
		return nil
	end

	if
		(self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces")
		or self.itemKind == "folder"
		or self.trackIsMaster
	then
		return nil
	end

	if not self.linkedMotor then
		if not self.grandpa then
			return nil
		end

		self.linkedMotor =
			self.rigModule:GetMotorForPart(self.grandpa.linkedRigInstance, self.linkedRigInstance)
	end

	return self.linkedMotor
end

function item:setupDebug()
	if data_debug.flags.coloredTracks and not self.trackIsMaster then
		self.selectedTrackColor = _debugPickColorFromTrack()

		self.uiElement.AppearDetails.BackgroundColor3 = self.selectedTrackColor
		self.uiElement.AppearDetails.BackgroundTransparency = 0

		self.trackElement.BackgroundColor3 = self.selectedTrackColor
		self.trackElement.BackgroundTransparency = 0.1

		self.uiElement.AppearDetails.CenterDiv.Title.TextColor3 = Color3.fromRGB(0, 0, 0)
		self.rigModule.refs.UIHelpers.coloredButton = Color3.fromRGB(156, 156, 156)

		table.insert(
			self.connections,
			self.uiElement.AppearDetails.Changed:Connect(function()
				if self.uiElement.AppearDetails.BackgroundTransparency == 1 then
					self.uiElement.AppearDetails.BackgroundColor3 = self.selectedTrackColor
					self.uiElement.AppearDetails.BackgroundTransparency = 0
				end

				self.trackElement.BackgroundColor3 = self.uiElement.AppearDetails.BackgroundColor3
			end)
		)
	end

	if data_debug.flags.trackElementName then
		local trackNameDebug = Instance.new("TextLabel")
		trackNameDebug.BackgroundTransparency = 1
		trackNameDebug.Text = `<b>{self.trackElement.Name}</b>`
		trackNameDebug.Size = UDim2.fromScale(1, 1)
		trackNameDebug.TextColor3 = data_debug.flags.coloredTracks and Color3.fromRGB(0, 0, 0)
			or Color3.fromRGB(255, 255, 255)
		trackNameDebug.Font = Enum.Font.Roboto
		trackNameDebug.ZIndex = 25
		trackNameDebug.RichText = true
		trackNameDebug.TextScaled = true
		trackNameDebug.Parent = self.trackElement
	end

	if data_debug.flags.infoHover then
		local gatherData = function()
			local result = self.rigModule.refs.UIHelpers:spitData({
				{ "opened", self.openedState },
				{ "isMaster", self.trackIsMaster },
				"_DIV_",
				{ "ask_state", self["trackerAsked_askedState"] },
				{ "ask_output", self["trackerAsked_output"] },
				{ "ask_passed", self["trackerAsked_passed"] },
			})

			return result
		end

		self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(
			self.uiElement.AppearDetails,
			gatherData
		)
		if not self.trackIsMaster then
			self.rigModule.refs.UIHelpers.hoverDialog:latchToInstance(self.trackElement, gatherData)
		end
	end

	if data_debug.flags.trackElementOffset then
		self.chain = 0
	end
end

function item:_debugUpdateChain(chainAmount)
	self.chain = chainAmount
	local pad_Debug = self.trackElement:FindFirstChild("DEBUG_PAD")
	if not pad_Debug then
		return
	end

	pad_Debug.PaddingLeft = UDim.new(0, data_debug.misc.trackElementOffsetAmount * self.chain)
end

function item:setMoreButtonVisibility(active)
	self.moreButton.ActualImage.ImageTransparency = active and 0 or 1
	self.moreButton.Active = active
end

function item:hasExpandableChildren(includeChannels)
	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		return false
	end

	if
		includeChannels ~= false
		and self.transformChannelsOpen
		and self.transformChannelItems
		and #self.transformChannelItems > 0
	then
		return true
	end

	for _, child in self.childItems do
		if TrackHierarchy.flatBone(self) and TrackHierarchy.flatBone(child) then
			continue
		end

		local source = child.linkedRigInstance
		local hidden = typeof(source) == "Instance"
			and source:GetAttribute("EclipseArmatureBone")
			and (
				source:GetAttribute("Hidden") == true
				or source:GetAttribute("EclipseArmatureUnselectable") == true
			)
		if hidden then
			if child:hasExpandableChildren(false) then
				return true
			end
		elseif child.itemKind == "ikcontrol" then
			local motor = child:fetchMotor()
			if motor and LimbIK.controlsVisible(motor.Owner) then
				return true
			end
		elseif
			(
				child.itemKind ~= "events"
				and child.itemKind ~= "subtitles"
				and child.itemKind ~= "faces"
			) or child:eventsVisible()
		then
			return true
		end
	end

	return false
end

function item:refreshMoreButtonVisibility()
	local expandable = self:hasExpandableChildren()
	self:setMoreButtonVisibility(expandable)
	self.childContainer.Visible = expandable and self.openedState
end

function item:fetchBone()
	if
		self.itemKind == "properties"
		or self.itemKind == "folder"
		or self.itemKind == "cameraattach"
	then
		return nil
	end

	if
		(self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces")
		or self.itemKind == "folder"
		or self.trackIsMaster
	then
		return nil
	end

	if not self.linkedBone or not self.linkedBone.Parent then
		self.linkedBone =
			self.rigModule:GetBoneFromPart(self.grandpa.linkedRigInstance, self.linkedRigInstance)
	end

	return self.linkedBone
end

function item:selectBone()
	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		return
	end

	local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	if self.itemKind == "folder" then
		if ctrlHeld then
			self.rigModule:ToggleItemSelection(self)
		elseif shiftHeld then
			self.rigModule:SelectRangeTo(self)
		else
			self.rigModule:SetSingleItemSelection(self)
		end

		return
	end

	if self.trackIsMaster then
		self.rigModule:SelectMaster(self, ctrlHeld, shiftHeld)
		return
	end

	if self.itemKind == "channel" then
		if ctrlHeld or shiftHeld then
			self.rigModule:ToggleChannelSelection(self)
		else
			self.rigModule:SetSingleChannelSelection(self)
		end

		return
	end

	if self.itemKind == "armature" then
		self.rigModule:SelectMaster(self, ctrlHeld, shiftHeld)
		return
	end

	if
		self.itemKind ~= "property"
		and self.itemKind ~= "properties"
		and self.itemKind ~= "cameraattach"
		and not self:fetchBone()
	then
		return
	end

	if ctrlHeld then
		self.rigModule:ToggleItemSelection(self)
	elseif shiftHeld then
		self.rigModule:SelectRangeTo(self)
	else
		self.rigModule:SetSingleItemSelection(self)
	end
end

function item:setOpenParentalState(state)
	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		state = state and self:eventsVisible()
		self.uiElement.Visible = state == true
		self.trackElement.Visible = state == true
		self.childContainer.Visible = false
		return
	end

	if self.itemKind == "ikcontrol" then
		local motor = self:fetchMotor()
		state = state
			and LimbIK.controlsVisible(motor.Owner)
			and require("R6Controls").visible(motor)
		self.uiElement.Visible = state == true
	end

	local hasChildren = #self.childItems > 0
	local passedState = self.openedState and state
	local visibilityState = passedState or (hasChildren and state)
	self.trackElement.Visible = visibilityState

	if self.transformChannelItems then
		local channelVis = passedState and self.transformChannelsOpen and true or false
		for _, channelItem in ipairs(self.transformChannelItems) do
			channelItem.uiElement.Visible = channelVis
			channelItem.trackElement.Visible = channelVis
		end
	end

	if data_debug.flags.trackIfAskedUponHidingContents then
		self.trackerAsked_hadChildren = hasChildren
		self.trackerAsked_askedState = state
		self.trackerAsked_passed = passedState
		self.trackerAsked_output = visibilityState
	end

	for i, child in self.childItems do
		child:setOpenParentalState(passedState)
	end
end

function item:setOpenState(change, ignoreChildState)
	if self.itemKind == "events" or self.itemKind == "subtitles" or self.itemKind == "faces" then
		self:setMoreButtonVisibility(false)
		return
	end

	self.openedState = change
	self.moreButton.ActualImage.Image = change and "rbxassetid://78782944463908"
		or "rbxassetid://71039333513245"

	if not ignoreChildState then
		for i, child in self.childItems do
			child:setOpenParentalState(change)
		end
	end

	if self.trackIsMaster and not self.rigModule._organizationReady then
		self.trackElement.TrackContainers.Visible = change
	end

	if self.transformChannelItems then
		local channelVis = change and self.transformChannelsOpen and true or false
		for _, channelItem in ipairs(self.transformChannelItems) do
			channelItem.uiElement.Visible = channelVis
			channelItem.trackElement.Visible = channelVis
		end
	end

	if self:hasExpandableChildren() then
		self.childContainer.Visible = change
	else
		self.childContainer.Visible = false
	end

	if not self.rigModule._rebuilding then
		self.rigModule:RefreshSelectionFilter()
	end
end

function item:addChild(otherItem)
	table.insert(self.childItems, otherItem)
	otherItem.parentItem = self
	if self.trackIsMaster then
		otherItem.trackElement.Parent = self.trackElement.TrackContainers
		otherItem.grandpa = self
	else
		otherItem.trackElement.Parent = self.trackElement.Parent
		otherItem.grandpa = self.grandpa
	end

	otherItem.uiElement.Parent = self.childContainer.ChildrenContents
	otherItem:bindParentingControl()
	otherItem:bindIKControl()
	otherItem:bindHeadStabilizerControl()
	if otherItem.itemKind == "subtitles" then
		require("EventTrackList").bind(self.rigModule.refs.Timeline, otherItem)
	elseif otherItem.itemKind == "faces" then
		require("Faces").bind(self.rigModule.refs.Timeline, otherItem)
	elseif otherItem.itemKind == "events" then
		self.rigModule.refs.Timeline:BindEventRow(otherItem)
		self:bindEventsVisibility()
	end

	local motor = otherItem:fetchMotor()
	if motor then
		otherItem.disabled = motor:GetAttribute("EclipseDisabled") == true
		otherItem:_repaintDisable()
	end

	self:refreshMoreButtonVisibility()

	if data_debug.flags.trackElementOffset then
		otherItem:_debugUpdateChain(self.chain + 1)
	end
end

function item:changeStateChildren(changeSelf, state, passOn: boolean?)
	if changeSelf then
		self:setOpenState(state, true)
	end

	for _, child in self.childItems do
		child:setOpenState(state, true)
		if passOn then
			child:changeStateChildren(false, state, true)
		end
	end
end

function item:destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true
	if self.rigModule._keyNameClick and self.rigModule._keyNameClick.item == self then
		self.rigModule._keyNameClick = nil
	end

	local timeline = self.rigModule.refs.Timeline
	if self.itemKind == "subtitles" and self.grandpa then
		require("EventTrackList").unbind(self.grandpa.linkedRigInstance, self.subtitleId)
	elseif self.itemKind == "faces" and self.grandpa then
		require("Faces").unbind(self.grandpa.linkedRigInstance)
	elseif self.itemKind == "events" and self.grandpa then
		timeline:UnbindEventRow(self.grandpa.linkedRigInstance)
	end

	if self.parentingButton and timeline._parentingControls then
		timeline._parentingControls[self.parentingButton] = nil
	end

	if self.headStabilizerButton and timeline._headStabilizerControls then
		timeline._headStabilizerControls[self.headStabilizerButton] = nil
	end

	motionPath.disable(self)

	if self.itemKind == "channel" and self.channelId and self.parentBoneItem then
		local motor = self.parentBoneItem:fetchMotor()
		if motor and motor.Parent and not self.rigModule._rebuilding then
			pcall(function()
				motor:SetAttribute("EclipseChannelDisabled_" .. self.channelId, nil)
			end)
		end
	end

	if self.linkedMotor and self.linkedMotor.Parent and not self.rigModule._rebuilding then
		pcall(function()
			self.linkedMotor:SetAttribute("EclipseDisabled", nil)
		end)
	end

	if self.transformChannelItems then
		local motor = self:fetchMotor()
		if motor and self.rigModule and self.rigModule.refs.Timeline then
			self.rigModule.refs.Timeline:UnregisterChannelTracksForMotor(motor)
		end

		if motor and motor.Parent and not self.rigModule._rebuilding then
			local attrs = motor:GetAttributes()
			for attrName in pairs(attrs) do
				if string.sub(attrName, 1, 22) == "EclipseChannelDisabled" then
					pcall(function()
						motor:SetAttribute(attrName, nil)
					end)
				end
			end
		end

		for _, channelItem in ipairs(self.transformChannelItems) do
			channelItem:destroy()
		end

		self.transformChannelItems = nil
	end

	for i, connection in self.connections do
		connection:Disconnect()
	end

	for i, child in self.childItems do
		child:destroy()
	end

	self.uiElement:Destroy()
	self.trackElement:Destroy()
	table.clear(self)
	self._destroyed = true
	self = nil
end

function item:_createTransformChannelItems()
	if self.transformChannelItems then
		return
	end

	if
		self.itemKind ~= "bone"
		and self.itemKind ~= "displaybone"
		and self.itemKind ~= "ikcontrol"
		and self.itemKind ~= "mastercontrol"
	then
		return
	end

	self.transformChannelItems = {}

	local refs = self.rigModule.refs
	local rigTemplate = refs.RigItemTemplate
	local timeline = refs.Timeline
	local sanitize = refs.UIHelpers.SanitizeName
	local baseLayoutOrder = self.trackElement.LayoutOrder

	for i, def in ipairs(CHANNELS_DEFINITION) do
		local motor = self:fetchMotor()
		if not KeyframePolicy.channelAvailable(motor, def.id) then
			continue
		end

		if
			not require("GraphCurves").rotationChannelVisible(
				timeline:GetState().Keyframes[motor],
				def.id
			)
		then
			continue
		end

		if typeof(motor) == "table" and motor.IsTranslationOnly and def.id:sub(1, 4) ~= "loc_" then
			continue
		end

		local uiClone = rigTemplate:Clone()
		local trackClone = timeline:CreateChannelTrackRow(
			self.linkedRigInstance.Name,
			def.id,
			baseLayoutOrder + i,
			sanitize
		)
		trackClone.Parent = self.trackElement.Parent
		local channelItem =
			item.initialize(uiClone, def.name, nil, trackClone, false, nil, "channel")
		channelItem.grandpa = self.grandpa
		channelItem.parentBoneItem = self
		channelItem.channelId = def.id

		local function repaintAxis()
			local native = def.name:sub(1, 1)
			channelItem.centerDiv.Title.Text = string.upper(
				Preferences.axisLabel(native, def.id:sub(1, 6) == "scale_") .. def.name:sub(2)
			)
			local colors = {
				X = Color3.fromRGB(255, 88, 88),
				Y = Color3.fromRGB(92, 220, 92),
				Z = Color3.fromRGB(92, 140, 255),
			}
			local img = channelItem.centerDiv.ImgContainer.Img
			img.ImageColor3 = Preferences.get("BlenderAxes")
					and (Preferences.axisColor(native, colors) or CHANNEL_IMG_COLOR)
				or CHANNEL_IMG_COLOR
		end

		repaintAxis()
		local unsubscribe = Preferences.subscribe(function(key)
			if key == "BlenderAxes" then
				repaintAxis()
			end
		end)
		table.insert(channelItem.connections, { Disconnect = unsubscribe })
		channelItem.disabled = motor
			and motor:GetAttribute("EclipseChannelDisabled_" .. def.id) == true
		channelItem:_repaintDisable()
		uiClone.LayoutOrder = -100 + i
		uiClone.Parent = self.childContainer.ChildrenContents
		uiClone.Visible = false
		trackClone.Visible = false
		table.insert(self.transformChannelItems, channelItem)
	end
end

function item:refreshTransformChannelPreference()
	if
		self.itemKind ~= "bone"
		and self.itemKind ~= "displaybone"
		and self.itemKind ~= "ikcontrol"
		and self.itemKind ~= "mastercontrol"
	then
		return
	end

	local icon = self.centerDiv.ImgContainer.Img
	local enabled = Preferences.get("TransformChannels") ~= false
	if not enabled then
		self:toggleTransformChannels(false)
		self._channelsBeforePreference = nil
	end

	icon.Active = true
	icon.ImageColor3 = enabled
			and (self.transformChannelsOpen and BONE_IMG_OPEN_COLOR or BONE_IMG_COLOR)
		or Color3.fromRGB(100, 106, 108)
end

function item:toggleTransformChannels(force, preservePreference)
	if
		self.itemKind == "cameraattach"
		or self.itemKind == "camtarget"
		or self.itemKind == "camerafov"
		or self.itemKind == "cameracframe"
	then
		return
	end

	if Preferences.get("TransformChannels") == false and force ~= false then
		return
	end

	if
		self.itemKind ~= "bone"
		and self.itemKind ~= "displaybone"
		and self.itemKind ~= "ikcontrol"
		and self.itemKind ~= "mastercontrol"
	then
		return
	end

	local newState
	if force == nil then
		newState = not self.transformChannelsOpen
	else
		newState = force and true or false
	end

	if newState == self.transformChannelsOpen then
		return
	end

	self.transformChannelsOpen = newState

	if newState and not self.transformChannelItems then
		self:_createTransformChannelItems()
	end

	local motor = self:fetchMotor()
	local timeline = self.rigModule.refs.Timeline

	if newState then
		if not self.openedState then
			self:setOpenState(true)
		end

		self.childContainer.Visible = self.openedState

		self.centerDiv.ImgContainer.Img.ImageColor3 = BONE_IMG_OPEN_COLOR

		if self.transformChannelItems then
			for _, channelItem in ipairs(self.transformChannelItems) do
				channelItem.uiElement.Visible = self.openedState
				channelItem.trackElement.Visible = self.openedState
			end
		end

		if motor and timeline then
			local rows = {}
			if self.transformChannelItems then
				for _, ci in ipairs(self.transformChannelItems) do
					rows[ci.channelId] = ci.trackElement
				end
			end

			timeline:RegisterChannelTracksForMotor(motor, rows)
			if not preservePreference then
				pcall(function()
					motor:SetAttribute("EclipseTransformChannelsOpen", true)
				end)
			end
		end
	else
		if self.transformChannelItems then
			for _, channelItem in ipairs(self.transformChannelItems) do
				channelItem.uiElement.Visible = false
				channelItem.trackElement.Visible = false
			end
		end

		self.centerDiv.ImgContainer.Img.ImageColor3 = BONE_IMG_COLOR

		if motor and timeline then
			timeline:UnregisterChannelTracksForMotor(motor)
			if not preservePreference then
				pcall(function()
					motor:SetAttribute("EclipseTransformChannelsOpen", nil)
				end)
			end
		end

		if #self.childItems == 0 then
			self.childContainer.Visible = false
			self.openedState = false
			self.moreButton.ActualImage.Image = "rbxassetid://71039333513245"
		end
	end

	self:refreshMoreButtonVisibility()
	if self.rigModule.onlyShowSelected or self.rigModule._organizationReady then
		self.rigModule:RefreshSelectionFilter()
	end
end

return item
