--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local GraphCurves = require("GraphCurves")
local Shortcuts = require("Shortcuts")
local CameraRig = require("CameraRig")
local BlenderBridge = require("BlenderBridge")
local Motion = require("Motion")
local Chrome = require("Chrome")
local LibraryIcons = require("LibraryIcons")
local UserInputService = require("UserInputService")
local State = require("RawState")
local AppState = require("State")
local Theme = require("Theme")
local TweenService = game:GetService("TweenService")

local PINNED_ICON = "rbxassetid://138733748032846"
local UNPINNED_ICON = "rbxassetid://90969585503067"
local NAVIGATION_INSET = 4

local function styleToggle(button, border, selected)
	button.BackgroundTransparency = selected and 0 or 0.8
	button:SetAttribute("Selected", selected)
	border.Transparency = selected and 0.1 or 0.65
	border.Color = Theme.get("Slider", Color3.fromRGB(85, 0, 127))
		:Lerp(Color3.new(1, 1, 1), selected and 0.2 or 0)
end

local TimelineState = State.Timeline

local function jumpableMotor(motor)
	if typeof(motor) == "Instance" then
		return motor.Parent ~= nil
	end

	if typeof(motor) ~= "table" then
		return false
	end

	if motor.IsEclipseProperty then
		return true
	end

	const part = motor.Part1
	return typeof(part) ~= "Instance" or part.Parent ~= nil
end

local function jumpableKey(bucket, at, key)
	return type(at) == "number"
		and at == at
		and type(key) == "table"
		and GraphCurves.hasKeyContent(bucket, key)
		and GraphCurves.hasVisibleKey(bucket, key)
end

return function(Timeline)
	function Timeline:GetJumpPinSelection()
		local motors = {}

		local function add(motor)
			if
				motor
				and (TimelineState.DefaultPose[motor] ~= nil or TimelineState.Keyframes[motor])
			then
				motors[motor] = true
			end
		end

		local rigApi = AppState.Rig
		for item in rigApi._selectedItems or {} do
			add(item:fetchMotor())
		end

		for channel in rigApi._selectedChannels or {} do
			if channel.parentBoneItem then
				add(channel.parentBoneItem:fetchMotor())
			end
		end

		if not next(motors) then
			for _, bone in AppState.Axis and AppState.Axis:GetSelectedBones() or {} do
				local source = bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
				local rig = source and source.Value or AppState.currentRig
				local part = rigApi:GetPartFromBone(rig, bone) or bone
				add(TimelineState.MotorByPart[part] or rigApi:GetMotorForPart(rig, part))
			end
		end

		if not next(motors) then
			for key in TimelineState.SelectedKeyframes do
				add(key.Motor)
			end

			for key in TimelineState.SelectedChannelKeyframes do
				add(key.Motor)
			end
		end

		return motors
	end

	function Timeline:IsJumpPinSelectionPinned()
		if not self.jumpPin or self.jumpPin.rig ~= AppState.currentRig then
			return false
		end

		local motors = self:GetJumpPinSelection()
		if not next(motors) then
			return false
		end

		for motor in motors do
			if not self.jumpPin.motors[motor] then
				return false
			end
		end

		return true
	end

	function Timeline:RefreshJumpPinButton()
		local navigation = self.navigation
		if not navigation or navigation.destroyed then
			return
		end

		local pin = navigation.pin
		if
			not pin
			or not pin.Parent
			or not pin:FindFirstChild("SelectionBorder")
			or not pin:FindFirstChild("Icon")
		then
			return
		end

		local pinned = self:IsJumpPinSelectionPinned()
		styleToggle(pin, pin.SelectionBorder, pinned)
		pin.Icon.Image = pinned and PINNED_ICON or UNPINNED_ICON
	end

	function Timeline:ToggleJumpPin()
		local motors = self:GetJumpPinSelection()
		if not next(motors) then
			require("Notification").show("PIN BONE", "Select a bone to pin.", 4)
			return
		end

		local remove = self:IsJumpPinSelectionPinned()
		if not self.jumpPin or self.jumpPin.rig ~= AppState.currentRig then
			self.jumpPin = { rig = AppState.currentRig, motors = {} }
		end

		for motor in motors do
			self.jumpPin.motors[motor] = not remove or nil
		end

		if not next(self.jumpPin.motors) then
			self.jumpPin = nil
		end

		self:RefreshNavigation()
		self:RefreshJumpPinRows()
	end

	function Timeline:RefreshJumpPinRows()
		self:RefreshJumpPinButton()
		for _, item in AppState.Rig and AppState.Rig._orderedItems or {} do
			local label = item.centerDiv and item.centerDiv:FindFirstChild("Title")
			if label then
				item._jumpPinFont = item._jumpPinFont or label.FontFace
				local pinned = self.jumpPin
					and self.jumpPin.rig == AppState.currentRig
					and self.jumpPin.motors[item:fetchMotor()] == true
				local font = item._jumpPinFont
				label.FontFace = pinned
						and Font.new(font.Family, font.Weight, Enum.FontStyle.Italic)
					or font
				local marker = item.centerDiv:FindFirstChild("JumpPinMarker")
				if marker then
					marker:Destroy()
				end

				label:SetAttribute("JumpPinned", pinned == true)
			end
		end
	end

	function Timeline:GetJumpRigSelection()
		const rigs = {}
		const all = AppState.getAllRigs()
		local function add(rig)
			if typeof(rig) == "Instance" and table.find(all, rig) then
				rigs[rig] = true
			end
		end

		const owner = require("Layers").owner
		for motor in self:GetJumpPinSelection() do
			add(owner(motor))
		end

		for item in AppState.Rig and AppState.Rig._selectedItems or {} do
			add((item.grandpa or item).linkedRigInstance)
		end

		if not next(rigs) then
			add(require("SelectedRig").resolve(AppState, false))
		end

		return rigs
	end

	function Timeline:GetJumpKeyframe(frame, direction, step)
		if self.jumpPin and self.jumpPin.rig ~= AppState.currentRig then
			self.jumpPin = nil
		end

		step = math.max(1, math.floor(tonumber(step) or 1))
		const filter = self.jumpPin and self.jumpPin.motors
			or TimelineState.OnlyShowSelected and self:GetJumpPinSelection()
			or nil
		const filtered = filter ~= nil and next(filter) ~= nil
		const rigs = not filtered
				and require("Preferences").get("JumpKeysOnSelectedRig") == true
				and self:GetJumpRigSelection()
			or nil
		const scoped = rigs ~= nil and next(rigs) ~= nil
		const owner = require("Layers").owner
		local frames, seen = {}, {}
		local nearest
		for motor, bucket in TimelineState.Keyframes do
			if
				filtered and not filter[motor]
				or type(bucket) ~= "table"
				or not jumpableMotor(motor)
				or scoped and not rigs[owner(motor)]
			then
				continue
			end

			for at, key in bucket do
				if not jumpableKey(bucket, at, key) then
					continue
				end

				at = math.max(0, math.floor(at + 0.5))
				if
					not seen[at]
					and (direction == "Left" and at < frame or direction == "Right" and at > frame)
				then
					if step == 1 then
						if
							not nearest
							or direction == "Left" and at > nearest
							or direction == "Right" and at < nearest
						then
							nearest = at
						end
					else
						seen[at] = true
						table.insert(frames, at)
					end
				end
			end
		end

		if step == 1 then
			return nearest
		end

		table.sort(frames)
		if #frames == 0 then
			return nil
		end

		local count = math.min(step, #frames)
		return frames[direction == "Left" and (#frames - count + 1) or count]
	end

	function Timeline:GetTimelineScrollLimit()
		return math.max(0, self:GetVisibleTimelineWidth() - self:GetTimelineViewportWidth())
	end

	function Timeline:SetTimelineScroll(offset)
		TimelineState.ScrollOffset = math.clamp(offset, 0, self:GetTimelineScrollLimit())
		if self.QueueKeyframeViewportRefresh then
			self:QueueKeyframeViewportRefresh()
		end

		if self.refs.Scale then
			self.refs.Scale.Position = UDim2.fromOffset(-TimelineState.ScrollOffset, 0)
		end

		self:BuildGuidesAndTicks()
		self:RefreshNavigation()
	end

	function Timeline:RefreshNavigation()
		local navigation = self.navigation
		if not navigation or navigation.destroyed then
			return
		end

		local container = self.refs.TimelineContainer
		local bottom = self.refs.BottomContainer

		if bottom ~= navigation.root or not bottom.Parent then
			return
		end

		for _, button in ipairs(navigation.buttons) do
			if button.Parent ~= bottom or not button:FindFirstChild("SelectionBorder") then
				return
			end
		end

		if not navigation.graph:FindFirstChild("Graph") then
			return
		end

		local scale = Motion.scale(bottom)
		local width =
			math.max(0, math.round(container.AbsoluteSize.X / scale) - NAVIGATION_INSET * 2)
		local left = math.round((container.AbsolutePosition.X - bottom.AbsolutePosition.X) / scale)
			- 1
		navigation.divider.Position = UDim2.fromOffset(left - 2, 0)
		navigation.bars.Position = UDim2.fromOffset(left + NAVIGATION_INSET, 4)
		navigation.bars.Size = UDim2.new(0, width, 1, -8)
		if self.jumpPin and self.jumpPin.rig ~= AppState.currentRig then
			self.jumpPin = nil
		end

		navigation.pin.Position = UDim2.fromOffset(30, 4)
		local pinned = self:IsJumpPinSelectionPinned()
		styleToggle(navigation.pin, navigation.pin.SelectionBorder, pinned)
		navigation.pin.Icon.Image = pinned and PINNED_ICON or UNPINNED_ICON
		navigation.pin.Icon.ImageColor3 = navigation.filter.Cursor.ImageColor3
		local full = self:GetVisibleTimelineWidth()
		local view = self:GetTimelineViewportWidth()
		local ratio = math.clamp(view / math.max(1, full), 0, 1)
		local thumb = math.min(width, math.max(18, math.floor(width * ratio + 0.5)))
		local limit = self:GetTimelineScrollLimit()
		local offset = limit > 0
				and math.floor(TimelineState.ScrollOffset / limit * (width - thumb) + 0.5)
			or 0
		self.refs.TopSlider.Size = UDim2.new(0, thumb, 1, 0)
		self.refs.TopSlider.Position = UDim2.fromOffset(offset, 0)

		local lowerStrip = navigation.bars.BottomSlider.Drag
		local fraction = navigation.rangeFraction and navigation.rangeFraction.Value or 1
		local rangeLeft = navigation.rangeSide == "left" and 1 - fraction or 0
		lowerStrip.Size = UDim2.fromScale(fraction, 1)
		lowerStrip.Position = UDim2.fromScale(rangeLeft, 0)
		if navigation.endHandle then
			navigation.endHandle.Position = UDim2.fromScale(rangeLeft + fraction, 0.5)
		end

		if navigation.startHandle then
			navigation.startHandle.Position = UDim2.fromScale(rangeLeft, 0.5)
		end

		navigation.extend.Position = UDim2.fromOffset(
			self:FrameToVisibleX(self:GetMaxFrame()) + 20 - TimelineState.ScrollOffset,
			26
		)
		local graphOpen = AppState.GraphEditor and AppState.GraphEditor.isOpen() or false
		navigation.graph.Position = UDim2.fromOffset(math.max(196, left - 28), 4)
		navigation.live.Position = navigation.graph.Position - UDim2.fromOffset(26, 0)
		navigation.library.Position = navigation.live.Position - UDim2.fromOffset(26, 0)
		navigation.blender.Position = navigation.library.Position - UDim2.fromOffset(26, 0)
		navigation.pencil.Position = navigation.blender.Position - UDim2.fromOffset(26, 0)
		navigation.camera.Position = navigation.pencil.Position - UDim2.fromOffset(26, 0)
		local filterRight = navigation.pin.Position.X.Offset + navigation.pin.Size.X.Offset
		local cameraLeft = navigation.camera.Position.X.Offset
		navigation.filterDivider.Position = UDim2.new(0, (filterRight + cameraLeft) / 2, 0.5, 0)
		local pencilOpen = AppState.GreasePencil and AppState.GreasePencil.isOpen() or false
		navigation.pencil.BackgroundTransparency = pencilOpen and 0 or 0.8
		navigation.pencil.SelectionBorder.Transparency = pencilOpen and 0.1 or 0.65
		navigation.pencil.SelectionBorder.Color = Theme.get("Slider", Color3.fromRGB(85, 0, 127))
		navigation.pencil:SetAttribute("Selected", pencilOpen)
		local blenderOpen = AppState.BlenderImport and AppState.BlenderImport.isOpen() or false
		navigation.blender.BackgroundTransparency = blenderOpen and 0 or 0.8
		navigation.blender.SelectionBorder.Transparency = blenderOpen and 0.1 or 0.65
		navigation.blender.SelectionBorder.Color = Theme.get("Slider", Color3.fromRGB(85, 0, 127))
		navigation.blender:SetAttribute("Selected", blenderOpen)
		local cameraOpen = AppState.CameraPreview and AppState.CameraPreview.isOpen() or false
		navigation.camera.BackgroundTransparency = cameraOpen and 0 or 0.8
		navigation.camera.SelectionBorder.Transparency = cameraOpen and 0.1 or 0.65
		navigation.camera.SelectionBorder.Color = Theme.get("Slider", Color3.fromRGB(85, 0, 127))
		navigation.camera:SetAttribute("Selected", cameraOpen)
		local liveJoined = AppState.LiveSession and AppState.LiveSession.isJoined() or false
		local liveOpen = liveJoined
			or AppState.LiveSession and AppState.LiveSession.isOpen()
			or false
		navigation.live.BackgroundTransparency = liveOpen and 0 or 0.8
		navigation.live.SelectionBorder.Transparency = liveOpen and 0.1 or 0.65
		navigation.live.SelectionBorder.Color = liveJoined and Color3.fromRGB(108, 213, 160)
			or Theme.get("Slider", Color3.fromRGB(85, 0, 127))
		navigation.live:SetAttribute("Selected", liveOpen)
		local libraryOpen = AppState.Library and AppState.Library.isOpen() or false
		navigation.library.BackgroundTransparency = libraryOpen and 0 or 0.8
		navigation.library.SelectionBorder.Transparency = libraryOpen and 0.1 or 0.65
		navigation.library.SelectionBorder.Color = Theme.get("Slider", Color3.fromRGB(85, 0, 127))
		navigation.library:SetAttribute("Selected", libraryOpen)
		navigation.graph.BackgroundTransparency = graphOpen and 0 or 0.8
		navigation.graph:SetAttribute("Selected", graphOpen)
		navigation.graph.Graph.ImageColor3 = Theme.get("Txt", Color3.fromRGB(235, 228, 242))
		local hover = self.refs.UIHelpers and self.refs.UIHelpers.hoverDialog
		if hover and hover.open and hover.causedElement == navigation.graph then
			hover:updateText(graphOpen and "Hide Graph Editor" or "Show Graph Editor")
		end

		navigation.graphBorder.Transparency = graphOpen and 0.1 or 0.65
		navigation.graphBorder.Color = Theme.get("Slider", Color3.fromRGB(85, 0, 127))
			:Lerp(Color3.new(1, 1, 1), graphOpen and 0.2 or 0)
		styleToggle(navigation.filter, navigation.border, TimelineState.OnlyShowSelected == true)
	end

	function Timeline:InitializeNavigation()
		if self.navigation or not self.refs.BottomContainer then
			return
		end

		local refs = self.refs
		local bottom = refs.BottomContainer
		refs.RigListScroll.Parent.LayoutOrder = 0
		local bars = Instance.new("Frame")
		bars.Name = "TimelineNavigation"
		bars.BackgroundTransparency = 1
		bars.BorderSizePixel = 0
		bars.Parent = bottom
		local layout = bottom:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.Parent = bars
		end

		local padding = bottom:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new()
			padding.PaddingRight = UDim.new()
			padding.PaddingTop = UDim.new()
			padding.PaddingBottom = UDim.new()
		end

		local top = refs.TopSlider.Parent
		top.Parent = bars
		top.LayoutOrder = 0
		for _, side in ipairs({ 0, 1 }) do
			local marker = Instance.new("Frame")
			marker.Name = side == 0 and "LeftEndpoint" or "RightEndpoint"
			marker.BorderSizePixel = 0
			marker.BackgroundColor3 = Color3.new(1, 1, 1)
			marker.BackgroundTransparency = 0.88
			marker.Size = UDim2.fromOffset(7, 7)
			marker.AnchorPoint = Vector2.new(side, 0.5)
			marker.Position = UDim2.fromScale(side, 0.5)
			marker.Active = false
			marker.Interactable = false
			marker.ZIndex = top.ZIndex
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = marker
			marker.Parent = top
		end

		bottom.BottomSlider.Parent = bars
		bars.BottomSlider.LayoutOrder = 1
		local divider = Instance.new("Frame")
		divider.Name = "NavigationDivider"
		divider.BorderSizePixel = 0
		divider.ZIndex = bars.ZIndex + 1
		divider.Active = false
		divider.Interactable = false
		divider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		divider:SetAttribute("ThemeBg", "Div")
		divider.Size = UDim2.new(0, 1, 1, 0)
		divider.Parent = bottom
		local filter = Instance.new("TextButton")
		filter.Name = "OnlyShowSelected"
		filter.Text = ""
		filter.BorderSizePixel = 0
		filter.AutoButtonColor = false
		filter.BackgroundTransparency = 0.8
		filter.BackgroundColor3 = Color3.fromRGB(85, 0, 127)
		filter:SetAttribute("ThemeBg", "Slider")
		filter.Size = UDim2.fromOffset(22, 22)
		filter.Position = UDim2.fromOffset(4, 4)
		filter.Parent = bottom
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = filter
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = filter
		local border = Instance.new("UIStroke")
		border.Name = "SelectionBorder"
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Thickness = 1
		border.Parent = filter
		local cursor = Instance.new("ImageLabel")
		cursor.Name = "Cursor"
		cursor.BackgroundTransparency = 1
		cursor.Image =
			"rbxasset://studio_svg_textures/Shared/DraggerTools/Dark/Standard/Select@3x.png"
		cursor.ImageRectOffset = Vector2.new(8, 2)
		cursor.ImageRectSize = Vector2.new(32, 44)
		cursor.ImageColor3 = refs.FPSLabel.TextColor3
		cursor:SetAttribute("ThemeImg", "Txt")
		cursor.Size = UDim2.fromOffset(14, 18)
		cursor.AnchorPoint = Vector2.new(0.5, 0.5)
		cursor.Position = UDim2.new(0.5, 1, 0.5, 2)
		cursor.Parent = filter
		local filterDivider = Instance.new("Frame")
		filterDivider.Name = "ShowSelectedDivider"
		filterDivider.Size = UDim2.fromOffset(14, 22)
		filterDivider.AnchorPoint = Vector2.new(0.5, 0.5)
		filterDivider.BackgroundTransparency = 1
		filterDivider.BorderSizePixel = 0
		filterDivider.Active = false
		filterDivider.Parent = bottom
		local line = Instance.new("Frame")
		line.Name = "Frame"
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.fromOffset(2, 16)
		line.BorderSizePixel = 0
		line.BackgroundTransparency = 0.6
		line:SetAttribute("ThemeBg", "Div")
		line.Parent = filterDivider
		Theme.applyTree(filterDivider)
		local graph = filter:Clone()
		graph.Name = "GraphEditorToggle"
		graph.Parent = bottom
		local graphIcon = graph.Cursor
		graphIcon.Name = "Graph"
		graphIcon.Image = "rbxassetid://115309669017281"
		graphIcon.ImageRectOffset = Vector2.zero
		graphIcon.ImageRectSize = Vector2.zero
		graphIcon:SetAttribute("ThemeImg", "Txt")
		graphIcon.ImageTransparency = 0
		graphIcon.Position = UDim2.fromScale(0.5, 0.5)
		graphIcon.Size = UDim2.fromOffset(20, 20)
		graph.MouseButton1Click:Connect(function()
			if AppState.GraphEditor then
				AppState.GraphEditor.toggle()
			end
		end)
		local image = graph:Clone()
		image.Name = "ImagePreviewerToggle"
		image.Parent = bottom
		local picture = image.Graph
		picture.Name = "Picture"
		picture.Image = Chrome.IMAGE_ICON
		local library = image:Clone()
		library.Name = "LibraryToggle"
		library.Picture:Destroy()
		library.Parent = bottom
		LibraryIcons.book(library)
		local blender = image:Clone()
		blender.Name = "BlenderImportToggle"
		blender.Picture.Image = BlenderBridge.ICON
		blender.Picture:SetAttribute("ThemeImg", "Txt")
		blender.Parent = bottom
		blender.MouseButton1Click:Connect(function()
			if AppState.BlenderImport then
				AppState.BlenderImport.toggle()
			end
		end)
		local pencil = image:Clone()
		pencil.Name = "GreasePencilToggle"
		pencil.Picture.Image = "rbxassetid://115527899313985"
		pencil.Picture.Size = UDim2.fromOffset(22, 22)
		pencil.Picture:SetAttribute("ThemeImg", "Txt")
		pencil.Parent = bottom
		pencil.MouseButton1Click:Connect(function()
			if AppState.GreasePencil then
				AppState.GreasePencil.toggle()
			end
		end)
		local camera = image:Clone()
		camera.Name = "CameraPreviewToggle"
		camera.Picture.Image = CameraRig.ICON
		camera.Picture:SetAttribute("ThemeImg", "Txt")
		camera.Parent = bottom
		camera.MouseButton1Click:Connect(function()
			if AppState.CameraPreview then
				AppState.CameraPreview.toggle()
			end
		end)
		local live = image:Clone()
		live.Name = "EclipseLiveToggle"
		live.Picture.Image = "rbxassetid://114727653642540"
		live.Picture.AnchorPoint = Vector2.new(0.5, 0.5)
		live.Picture.Position = UDim2.fromScale(0.5, 0.5)
		live.Picture.Size = UDim2.fromScale(1.25, 1.25)
		live.Picture:SetAttribute("ThemeImg", "Txt")
		live.Parent = bottom
		live.MouseButton1Click:Connect(function()
			if AppState.LiveSession then
				AppState.LiveSession.toggle()
			end
		end)
		library.MouseButton1Click:Connect(function()
			if AppState.Library then
				AppState.Library.toggle()
			end
		end)

		image:Destroy()
		local extend = Instance.new("ImageButton")
		extend.Name = "ExtendTimeline"
		extend.BackgroundTransparency = 1
		extend.Image = ""
		extend.Size = UDim2.fromOffset(20, 16)
		extend.AnchorPoint = Vector2.new(0.5, 0.5)
		extend.ZIndex = math.max(50, refs.DragBarHitbox.ZIndex + 10)
		extend.Parent = refs.TimelineContainer
		local dot = refs.RightDrag:Clone()
		dot.Name = "Circle"
		dot.Size = UDim2.fromOffset(7, 7)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Active = false
		dot.Interactable = false
		dot.ZIndex = extend.ZIndex
		dot.Parent = extend
		local pin = filter:Clone()
		pin.Name = "PinKeyframeJumps"
		pin.Parent = bottom
		local pinDrawing = pin.Cursor
		pinDrawing.Name = "Icon"
		pinDrawing.ImageRectOffset = Vector2.zero
		pinDrawing.ImageRectSize = Vector2.zero
		pinDrawing.Size = UDim2.fromOffset(20, 20)
		pinDrawing.Position = UDim2.fromScale(0.5, 0.5)
		pinDrawing.Image = UNPINNED_ICON
		pinDrawing.ScaleType = Enum.ScaleType.Fit
		pin.Activated:Connect(function()
			self:ToggleJumpPin()
		end)
		self.navigation = {
			pin = pin,
			root = bottom,
			buttons = { filter, pin, pencil, blender, camera, live, library, graph },
			filterDivider = filterDivider,
			pencil = pencil,
			blender = blender,
			camera = camera,
			live = live,
			library = library,
			graph = graph,
			graphBorder = graph.SelectionBorder,
			bars = bars,
			filter = filter,
			border = border,
			divider = divider,
			extend = extend,
		}
		local navigation = self.navigation
		local disconnectTheme = Theme.onChanged(function()
			if not navigation.destroyed and self.navigation == navigation and bottom.Parent then
				self:RefreshNavigation()
			end
		end)
		local hover = refs.UIHelpers and refs.UIHelpers.hoverDialog
		if hover then
			hover:latchToInstance(pin, function()
				return self:IsJumpPinSelectionPinned() and "Unpin bone" or "Pin bone"
			end)
			hover:latchToInstance(filter, "Only Show Selected")
			hover:latchToInstance(library, "Library")
			hover:latchToInstance(blender, "Blender Import")
			hover:latchToInstance(pencil, "Annotate / Grease Pencil")
			hover:latchToInstance(camera, "Camera Preview")
			hover:latchToInstance(live, "Live")
			hover:latchToInstance(graph, function()
				return AppState.GraphEditor
						and AppState.GraphEditor.isOpen()
						and "Hide Graph Editor"
					or "Show Graph Editor"
			end)
		end

		filter.MouseButton1Click:Connect(function()
			TimelineState.OnlyShowSelected = not TimelineState.OnlyShowSelected
			if refs.SetSelectionFilter then
				refs.SetSelectionFilter(TimelineState.OnlyShowSelected)
			end

			self:RefreshNavigation()
		end)
		extend.MouseButton1Click:Connect(function()
			self:ExtendTimeline()
		end)
		local dragging
		local pan
		local began = UserInputService.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton3
				or not require("UI").isAnimatorActive()
			then
				return
			end

			if AppState.GraphEditor and AppState.GraphEditor.hasFocus() then
				return
			end

			local area = refs.TimelineContainer.Parent.Parent
			local p, z = area.AbsolutePosition, area.AbsoluteSize
			local mouse = UserInputService:GetMouseLocation()
			if
				mouse.X >= p.X
				and mouse.Y >= p.Y
				and mouse.X <= p.X + z.X
				and mouse.Y <= p.Y + z.Y
			then
				pan = {
					mouse = mouse,
					offset = TimelineState.ScrollOffset,
					canvas = refs.RigListScroll.CanvasPosition,
				}
			end
		end)

		local function beginDrag()
			dragging = {
				mouse = UserInputService:GetMouseLocation().X,
				offset = TimelineState.ScrollOffset,
			}
		end

		refs.TopSlider.MouseButton1Down:Connect(beginDrag)
		refs.LeftDrag.MouseButton1Down:Connect(beginDrag)
		refs.RightDrag.MouseButton1Down:Connect(beginDrag)
		local lowerBar = bars.BottomSlider
		for _, object in
			{ lowerBar, lowerBar.Drag, lowerBar.Drag.LeftDrag, lowerBar.Drag.RightDrag }
		do
			object.Active = false
			object.Interactable = false
		end

		lowerBar.Interactable = true
		local endHandle = Instance.new("ImageButton")
		endHandle.Name = "EndHandle"
		endHandle.Image = ""
		endHandle.BackgroundTransparency = 1
		endHandle.Size = UDim2.fromOffset(22, 16)
		endHandle.AnchorPoint = Vector2.new(1, 0.5)
		endHandle.Position = UDim2.fromScale(1, 0.5)
		endHandle.ZIndex = lowerBar.ZIndex + 10
		endHandle.Active = true
		endHandle.Interactable = true
		endHandle.Parent = lowerBar
		navigation.endHandle = endHandle
		local startHandle = endHandle:Clone()
		startHandle.Name = "StartHandle"
		startHandle.AnchorPoint = Vector2.new(0, 0.5)
		startHandle.Position = UDim2.fromScale(0, 0.5)
		startHandle.Parent = lowerBar
		navigation.startHandle = startHandle
		local fraction = Instance.new("NumberValue")
		fraction.Name = "RangeFraction"
		fraction.Value = 1
		fraction.Parent = bottom
		navigation.rangeFraction = fraction
		local fractionChanged = fraction.Changed:Connect(function()
			if not navigation.destroyed then
				self:RefreshNavigation()
			end
		end)

		local function beginEndDrag(side)
			if self:IsExportLocked() or not require("UI").isAnimatorActive() then
				return
			end

			if navigation.endDrag then
				return
			end

			if navigation.returnTween then
				navigation.returnTween:Cancel()
				navigation.returnTween = nil
			end

			navigation.rangeSide = side
			fraction.Value = 1
			navigation.endDrag = {
				before = self:CaptureTimelineEnd(),
				frame = self:GetMaxFrame(),
				ratio = 1,
				side = side,
				width = math.max(1, lowerBar.AbsoluteSize.X),
				mouse = UserInputService:GetMouseLocation().X,
				rig = AppState.currentRig,
			}
		end

		endHandle.MouseButton1Down:Connect(function()
			beginEndDrag("right")
		end)
		startHandle.MouseButton1Down:Connect(function()
			beginEndDrag("left")
		end)

		local function finishEndDrag(commit)
			local drag = navigation.endDrag
			navigation.endDrag = nil
			if not drag then
				return
			end

			if drag.rig == AppState.currentRig then
				if commit and not self:IsExportLocked() and require("UI").isAnimatorActive() then
					if not drag.moved then
						self:ExtendTimeline()
					else
						self:SetTimelineEnd(
							self:GetMaxFrame(),
							drag.before,
							false,
							drag.side == "left"
						)
					end
				else
					self:ApplyTimelineEnd(drag.before, false)
				end
			end

			if commit then
				navigation.returnTween = TweenService:Create(
					fraction,
					TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
					{ Value = 1 }
				)
				navigation.returnTween:Play()
			else
				fraction.Value = 1
				self:RefreshNavigation()
			end
		end

		if hover then
			hover:latchToInstance(endHandle, "Click to add 1 second; drag left to shorten")
		end

		if hover then
			hover:latchToInstance(startHandle, "Click to add 1 second; drag right to lengthen")
		end

		local changed = UserInputService.InputChanged:Connect(function(input)
			if navigation.endDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
				local drag = navigation.endDrag
				if
					drag.rig ~= AppState.currentRig
					or self:IsExportLocked()
					or not require("UI").isAnimatorActive()
				then
					finishEndDrag(false)
					return
				end

				local pixels = UserInputService:GetMouseLocation().X - drag.mouse
				if not drag.moved and math.abs(pixels) < 3 * Motion.scale(bottom) then
					return
				end

				drag.moved = true
				local delta = pixels / drag.width
				drag.ratio = drag.side == "left" and math.clamp(1 - delta, 0.05, 1)
					or math.clamp(1 + delta, 1 / drag.frame, 1)
				fraction.Value = drag.ratio
				local frame = drag.side == "left" and drag.frame / drag.ratio
					or drag.frame * drag.ratio
				self:SetTimelineEnd(frame, drag.before, true, drag.side == "left")
				self:RefreshNavigation()
				return
			end

			if pan and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = UserInputService:GetMouseLocation() - pan.mouse
				self:SetTimelineScroll(pan.offset - delta.X / Motion.scale(bottom))
				refs.RigListScroll.CanvasPosition = Vector2.new(
					pan.canvas.X,
					math.max(0, pan.canvas.Y - delta.Y / Motion.scale(bottom))
				)
				return
			end

			if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end

			local travel = bars.AbsoluteSize.X - refs.TopSlider.AbsoluteSize.X
			if travel > 0 then
				self:SetTimelineScroll(
					dragging.offset
						+ (UserInputService:GetMouseLocation().X - dragging.mouse)
							/ travel
							* self:GetTimelineScrollLimit()
				)
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = nil
				finishEndDrag(true)
			end

			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				pan = nil
			end
		end)
		local focusLost = UserInputService.WindowFocusReleased:Connect(function()
			pan = nil
			dragging = nil
			finishEndDrag(false)
		end)
		local refreshQueued = false

		local function queueRefresh()
			if
				navigation.destroyed
				or self.navigation ~= navigation
				or Motion.isTranslating(bottom)
			then
				return
			end

			if refreshQueued then
				return
			end

			refreshQueued = true
			task.defer(function()
				refreshQueued = false
				if not navigation.destroyed and self.navigation == navigation and bottom.Parent then
					self:RefreshNavigation()
				end
			end)
		end

		local layoutConnections = {
			bottom:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueRefresh),
			bottom:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRefresh),
			refs.TimelineContainer
				:GetPropertyChangedSignal("AbsolutePosition")
				:Connect(queueRefresh),
			refs.TimelineContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRefresh),
			refs.RigListScroll.Parent.Parent:GetPropertyChangedSignal("Size"):Connect(queueRefresh),
		}
		bottom.Destroying:Connect(function()
			finishEndDrag(false)
			if navigation.returnTween then
				navigation.returnTween:Cancel()
			end

			fractionChanged:Disconnect()
			navigation.destroyed = true
			if self.navigation == navigation then
				self.navigation = nil
			end

			disconnectTheme()
			focusLost:Disconnect()
			began:Disconnect()
			changed:Disconnect()
			ended:Disconnect()
			for _, connection in ipairs(layoutConnections) do
				connection:Disconnect()
			end
		end)
		self:InitializeFPSEditor()
		self:RefreshNavigation()
	end

	function Timeline:InitializeFPSEditor()
		local label = self.refs.FPSLabel
		if not label then
			return
		end

		local input = Instance.new("TextBox")
		input.Name = label.Name
		for _, property in ipairs({
			"Size",
			"Position",
			"AnchorPoint",
			"AutomaticSize",
			"LayoutOrder",
			"FontFace",
			"TextSize",
			"TextColor3",
			"TextTransparency",
			"TextXAlignment",
			"TextYAlignment",
			"ZIndex",
			"BackgroundColor3",
			"BackgroundTransparency",
			"BorderSizePixel",
		}) do
			input[property] = label[property]
		end

		for name, value in pairs(label:GetAttributes()) do
			input:SetAttribute(name, value)
		end

		for _, child in ipairs(label:GetChildren()) do
			child:Clone().Parent = input
		end

		input.ClearTextOnFocus = false
		input.Text = tostring(TimelineState.FPS) .. " FPS"
		input.Parent = label.Parent
		label:Destroy()
		self.refs.FPSLabel = input
		local cancelled = false
		input.Focused:Connect(function()
			TimelineState.Playing = false
			cancelled = false
			input.Text = tostring(TimelineState.FPS)
			input.CursorPosition = #input.Text + 1
			input.SelectionStart = 1
		end)
		input.InputBegan:Connect(function(event)
			if Shortcuts.matches("Cancel", event) then
				cancelled = true
				input:ReleaseFocus()
			end
		end)
		require("NumericInput").connect(input, { step = 1, min = 1, integer = true }, function()
			if not cancelled then
				self:SetFPS(tonumber(input.Text))
			end

			input.Text = tostring(TimelineState.FPS) .. " FPS"
		end)
		local hover = self.refs.UIHelpers and self.refs.UIHelpers.hoverDialog
		if hover then
			hover:latchToInstance(input, "Frames per second (1–1000)")
		end
	end
end
