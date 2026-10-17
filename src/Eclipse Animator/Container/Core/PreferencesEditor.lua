--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local ColorPicker = require("Picker")
local WindowMotion = require("Motion")
local Shortcuts = require("Shortcuts")
local Chrome = require("Chrome")
local Theme = require("Theme")
local Preferences = require("Preferences")
local WindowFX = require("WindowFX")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Editor = {}
local WIDTH, HEIGHT = 600, 480
local RESET_ICON = "rbxassetid://110138249483014"
local OPTIONS = {
	{
		key = "HideAnimatorDuringTransform",
		label = "Hide animator while transforming",
		tip = "Temporarily hide all floating Eclipse windows during selected transform tools. Will not affect docked mode.",
	},
	{
		key = "HideAnimatorForKeyboard",
		label = "R / double R / G",
		dependsOn = "HideAnimatorDuringTransform",
		tip = "Hide while using keyboard rotation, trackball rotation, or movement. Restores after confirm or cancel.",
	},
	{
		key = "HideAnimatorForGizmos",
		label = "Gizmo drags",
		dependsOn = "HideAnimatorDuringTransform",
		tip = "Hide while dragging a viewport transform gizmo. Restores when the drag ends.",
	},
	{
		key = "R15PoleFollowsIK",
		label = "R15 Pole Follows IK",
		tip = "Default for newly enabled R15 IK limbs. Existing animation keys keep their pole mode. Change a current limb in Rig > Bone Settings.",
	},
	{
		key = "RotationTrackballSize",
		label = "Rotation Trackball Size",
		numeric = true,
		unit = "%",
		tip = "Inner rotation ball only: 1–100%. 100% is the default and maximum. Outer rotation handles and the position center keep their size.",
	},
	{
		key = "TimelineScrollSensitivity",
		label = "Timeline Scroll Sensitivity",
		numeric = true,
		tip = "Mouse-wheel speed for timeline zoom and track scrolling. Default: 1 (0.01–10). Below 1, speed decreases exponentially toward 0.01. Above 1, speed increases linearly. 1 is twice the original scroll speed.",
	},
	{
		key = "DefaultAxisSpace",
		label = "Default Alignment",
		choices = { 0, 1, 2 },
		choiceLabels = { "Last", "Local", "World" },
		tip = "Starting alignment for move and rotate when Eclipse loads. Last remembers the last used spaces; Local or World (Global) starts both tools in that space. Choosing a fixed default also applies it now. T still toggles without changing this default.",
	},
	{
		key = "SeparateTransformSpaces",
		label = "Separate Move / Rotate Spaces",
		tip = "Remember Local or Global independently for movement and rotation. Off keeps both tools linked.",
	},
	{
		key = "ActiveToolDrag",
		label = "Active Tool Drag",
		tip = "Select a bone and a move or rotation tool, then click empty viewport space to use it. Drag and release to apply, or click once, move, and click again to apply. Esc cancels. Clicking another bone selects it.",
	},
	{
		key = "NotifyKeyframeActions",
		label = "Keyframe Action Notifications",
		tip = "Show confirmation messages when copying or pasting keyframes.",
	},
	{ key = "NotifyAxisSpace", label = "Global / Local Notifications" },
	{ key = "NotifyRigAdded", label = "Rig / Object Added Notifications" },
	{ key = "NotifyImportSuccess", label = "Import Success Notifications" },
	{ key = "NotifyPivotChanges", label = "Pivot Change Notifications" },
	{ key = "NotifyCameraTips", label = "Camera Control Tips" },
	{
		blenderFeature = true,
		key = "BlenderAxes",
		label = "Blender Axes",
		tip = "Use Blender axis labels, colors and X/Y/Z controls: X right, Y forward, Z up. Existing animation data is unchanged. Native positive Z channels are labeled -Y; scale axes have no sign.",
	},
	{
		key = "DisableGizmoTrackball",
		label = "Disable Gizmo Trackball",
		tip = "Hide and disable the inner rotation trackball. The position center handle, rotation rings and keyboard trackball remain available.",
	},
	{
		key = "DeferredArmatureUpdates",
		label = "Update Rig on Release",
		tip = "Imported armatures only. Move selected controls while dragging; solve the remaining rig on release. Off by default. Useful for rigs with many controls.",
	},
	{
		blenderFeature = true,
		key = "TransformChannels",
		label = "Transform Channels",
		tip = "blender uses transform channels to key location, rotation, and scale separately. other roblox animation tools bake the data into each keyframe so they aren't handled separately. enable to have a more blender-familiar experience",
	},
	{
		blenderFeature = true,
		key = "BlenderCameraBeta",
		label = "Blender Camera",
		tip = "middle mouse to orbit. hold Shift to pan. scroll to zoom.",
	},
	{
		blenderFeature = true,
		key = "DisableCameraWASD",
		label = "Disable WASD Movement",
		tip = "Reserve W/A/S/D for keybinds while Eclipse is active. Mouse look, pan and zoom still work. Q/E is controlled separately. Also available as an unbound toggle in Keybinds.",
	},
	{
		blenderFeature = true,
		key = "DisableCameraQE",
		label = "Disable Q/E Movement",
		tip = "Reserve Q/E for keybinds while Eclipse is active. Mouse look, pan and zoom still work. WASD is controlled separately. Also available as an unbound toggle in Keybinds.",
	},
	{
		blenderFeature = true,
		key = "FlatBoneList",
		label = "Flat Bone List",
		tip = "Align timeline bones in a flat list. Bone dropdowns show their own channels and properties; rig and folder dropdowns still group rows. Rig parenting and animation data stay unchanged.",
	},
	{
		blenderFeature = true,
		key = "MasterKeyframes",
		label = "Master Keyframes",
		tip = "Show summary keyframes on rig and armature tracks. Select or edit all descendant keys at that frame together.",
	},
	{
		blenderFeature = true,
		key = "ContinuousTimeline",
		label = "Continuous Timeline",
		tip = "keeps playing to the end of the track, even after the last key.",
	},
	{
		blenderFeature = true,
		key = "BlenderPanSensitivity",
		label = "Pan Speed",
		numeric = true,
		blenderOnly = true,
	},
	{
		blenderFeature = true,
		key = "BlenderOrbitSensitivity",
		label = "Orbit Speed",
		numeric = true,
		blenderOnly = true,
	},
	{
		blenderFeature = true,
		key = "BlenderZoomToMouse",
		label = "Zoom to Mouse Position",
		blenderOnly = true,
	},
	{
		blenderFeature = true,
		key = "HideOriginBone",
		blenderOnly = true,
		label = "Hide Origin Bone",
	},
	{
		blenderFeature = true,
		key = "OriginAlwaysShowing",
		blenderOnly = true,
		label = "Origin always showing",
	},
	{
		key = "IKFeetPlanted",
		label = "IK Feet Planted",
		tip = "keeps the feet at their IK target while the body moves. move the foot target to take a step.",
	},
	{
		key = "R6IKLegPole",
		label = "R6 IK Leg Pole",
		tip = "Show the foot-relative leg pole. Existing pole animation is retained when hidden.",
	},
	{
		key = "R6BendPercent",
		label = "R6 Bend",
		numeric = true,
		unit = "%",
		tip = "65% is the default. lower = stiffer limbs. 100% is the old bend.",
	},
	{
		key = "SoftIKPercent",
		label = "Soft IK",
		numeric = true,
		unit = "%",
		tip = "softens the last bit of a limb's reach. 90% softens the last 10%. 100% turns it off.",
	},
	{
		key = "GifPlayback",
		label = "GIF Backgrounds",
		choices = { 1, 2, 3 },
		tip = "1: animated. 2: low FPS, fewer frames and updates. 3: still, loads one frame without animation.",
	},
	{
		key = "HideBoneLines",
		label = "Bone circles only",
		tip = "Hide native bone links while keeping the joint circles visible and selectable.",
	},
	{ key = "OnionSkinColor", label = "Onion Skin Color", color = true },
	{
		key = "OnionSkinTransparency",
		label = "Onion Skin Transparency",
		numeric = true,
		unit = "%",
		min = 0,
		max = 100,
		step = 1,
	},
	{ key = "PoseGhostPreviousColor", label = "Previous Pose Color", color = true },
	{ key = "PoseGhostNextColor", label = "Next Pose Color", color = true },
	{
		key = "PoseGhostTransparency",
		label = "Pose Ghost Transparency",
		numeric = true,
		unit = "%",
		tip = "Ghost transparency from 0–100%. Default: 85%. Higher values make the ghosts more transparent.",
	},
	{
		key = "AutomaticOnionSkin",
		label = "Pose Ghosts",
		tip = "Show the selected object at its previous and next keyframes using the chosen pose colors. Includes rigs, cameras and spatial property tracks. Updates while paused.",
	},
	{
		key = "FullBoneTransparency",
		label = "Full Bone Transparency",
		numeric = true,
		unit = "%",
		min = 0,
		max = 100,
		step = 1,
	},
	{
		key = "HandleBoneTransparency",
		label = "Handle Bone Transparency",
		numeric = true,
		unit = "%",
		min = 0,
		max = 100,
		step = 1,
	},
	{
		key = "CustomBoneTransparency",
		label = "Custom Bone Transparency",
		numeric = true,
		unit = "%",
		min = 0,
		max = 100,
		step = 1,
	},
	{
		key = "ArmatureBoneTransparency",
		label = "Blender Bone Transparency",
		numeric = true,
		unit = "%",
		min = 0,
		max = 100,
		step = 1,
	},
	{
		key = "BoneXRay",
		label = "Bone X-Ray",
		tip = "Show bone outlines through the rig. IK handles remain visible when this is off.",
	},
	{ key = "BoneSelectionAssist", label = "Bone Selection Assist" },
	{ key = "BoneFrontIndicators", label = "Bone Front Indicators", tip = "Show a small arrow pointing along each bone or body part's forward direction." },
	{ key = "SelectKeysWithRigParts", label = "Select Keys with Rig Parts", tip = "Selecting a rig part or bone also selects all its timeline keyframes. Off by default." },
	{
		key = "BoneSelectionRadius",
		label = "Bone Selection Radius",
		numeric = true,
		unit = "px",
		min = 2,
		max = 32,
		step = 1,
	},
	{
		key = "BoneStyle",
		label = "Bone Style",
		choices = { 1, 2 },
		choiceLabels = { "Full Bone", "Handle Bones" },
	},
	{
		key = "GreasePencilSmoothing",
		label = "Annotate Smoothing",
		numeric = true,
		unit = "%",
	},
	{ key = "DefaultFPS", label = "Default FPS", numeric = true },
	{
		key = "DefaultRotationMode",
		label = "Default Rotation Mode",
		rotationChoice = true,
		tip = "Quaternion or one of six Euler orders for newly added rigs. Existing tracks and imported animations keep their stored rotation mode.",
	},
	{
		key = "CameraPreviewFPS",
		label = "Camera Preview FPS Limit",
		numeric = true,
		tip = "0 (default) follows Studio's render rate. Set 5–240 to limit preview updates and reduce work. This does not change the animation's FPS.",
	},
	{
		key = "CameraPreviewMaskOpacity",
		label = "Camera Preview Mask Opacity",
		numeric = true,
		unit = "%",
		min = 0,
		max = 100,
		step = 1,
		tip = "Darkness of the area outside the camera frame in the camera previewer. 0% is fully clear, 100% is solid black. Default: 45%.",
	},
	{ key = "GreenScreenColor", label = "Green Screen Color", color = true },
	{ key = "ShowBonesInCamera", label = "Show bones in camera" },
	{ key = "NavigationGizmo", label = "Viewport navigation gizmo" },
	{
		key = "SmoothIKTransitions",
		label = "Smooth IK / FK",
		tip = "Ease out of IK into FK using the outgoing key easing. FK stays unchanged until its next IK switch. Constant keys hold their mode.",
	},
	{
		key = "FrameStep",
		label = "Frame Step",
		numeric = true,
		tip = "Frames moved by the previous / next frame shortcuts (default: 6 / 7, including numpad). Hold to keep stepping.",
	},
	{
		key = "AltScrollFrameStep",
		label = "Alt Scroll Frame Step",
		numeric = true,
		step = 1,
		min = 1,
		max = 1000000,
		tip = "Frames moved per Alt + mouse wheel notch over the timeline. Default: 1, matching Blender. Up goes backward; down goes forward. Independent of Frame Step and timeline scroll speed.",
	},
	{
		key = "KeyframeJumpStep",
		label = "Keyframe Jump Step",
		numeric = true,
		tip = "Number of distinct keyframes moved by Shift+F / Shift+G (or your custom jump shortcuts).",
	},
	{
		key = "JumpKeysOnSelectedRig",
		label = "Jump Keys On Selected Rig",
		tip = "Next / previous keyframe jumps only stop on keys of the selected rig: the rig of the selected track, bone, row or keyframe. With nothing selected, every key in the project is used. Pinned bones and Only Show Selected still take priority. Off by default.",
	},
	{ key = "DefaultTrackLength", label = "Default Track Length", numeric = true },
	{ key = "GizmoSize", label = "Gizmo Size", numeric = true },
	{
		key = "MoveSnapIncrement",
		label = "Move Snap Increment",
		numeric = true,
		tip = "Studs per step while holding Ctrl to move (0.001–1000). Examples: 1, 0.5, 0.25. Ctrl+Shift uses one tenth of this value.",
	},
	{
		key = "RotationSnapIncrement",
		label = "Rotation Snap Increment",
		numeric = true,
		tip = "Degrees per step while holding Ctrl to rotate (0.001–360). Ctrl+Shift uses one tenth of this value.",
	},
	{ key = "OldPositionGizmo", label = "Old Position Gizmo" },
	{
		key = "OldRotationGizmo",
		label = "Old Rotation Gizmo",
		tip = "Use the original full rotation rings and original click area.",
	},
	{ key = "PositionGizmoThickness", label = "Position Gizmo Thickness", numeric = true },
	{
		key = "ShowTransformReadout",
		label = "Transform Readout",
		tip = "shows movement and rotation values beside the gizmo while dragging.",
	},
	{
		key = "ShowRotationAxes",
		label = "Rotation Axis Rings",
		tip = "shows the colored X, Y and Z rotation rings. Turn off to use the inner trackball and white outer ring.",
	},
	{
		key = "IndividualRotationPivots",
		label = "Individual Rotation Pivots",
		tip = "Rotate selected controls around their own pivots. Turn off to rotate them together around the selection center.",
	},
	{
		key = "RotationGrabCircles",
		label = "Rotation Grab Circles",
		tip = "Small grab circles on the colored rotation rings.",
	},
	{
		key = "RotationGrabCircleSize",
		label = "Rotation Grab Circle Size",
		numeric = true,
		unit = "px",
		tip = "Circle diameter in pixels (4–64). Default: 18.",
	},
	{
		key = "TrackballSensitivity",
		label = "Gizmo Trackball Sensitivity",
		numeric = true,
		tip = "Rotation speed for the inner gizmo trackball. Default: 1. Lower is slower (0.01–5).",
	},
	{
		key = "BlenderGrabSensitivity",
		label = "G Move Sensitivity",
		numeric = true,
		tip = "Movement speed when using G. Default: 1. Lower is slower (0.01–5).",
	},
	{
		key = "BlenderRotateSensitivity",
		label = "R Rotate Sensitivity",
		numeric = true,
		tip = "Rotation speed when using R. Default: 1. Lower is slower (0.01–5).",
	},
	{
		key = "BlenderTrackballSensitivity",
		label = "Double-R Trackball Sensitivity",
		numeric = true,
		tip = "Free rotation speed when pressing R twice. Default: 1. Lower is slower (0.01–5).",
	},
	{ key = "GizmoDistance", label = "Gizmo Distance", numeric = true },
	{
		key = "GraphClamp",
		label = "Graph Clamp",
		numeric = true,
		tip = "limits how high and low the graph shows. doesn't change your keys.",
	},
	{
		key = "GraphCompressionPercent",
		label = "Graph Compression",
		numeric = true,
		unit = "%",
		tip = "squishes the graph vertically. at 10%, a value of 10 shows as 1. your keys stay the same.",
	},
	{
		key = "GraphAutoSmoothing",
		label = "Auto Smoothing",
		tip = "Blender's Continuous Acceleration for auto handles. keeps curves smooth through every key. turn off for the old per-key handles.",
	},
	{
		key = "CamTargetParentButton",
		label = "CamTarget parent button",
		tip = "use the P/W button to open Dynamic Parenter. it won't pop up when you select CamTarget.",
	},
	{ key = "TopbarShape", label = "Topbar Shape", choices = { 1, 2, 3 } },
	{ key = "OpenAutomatically", label = "Open Automatically" },
	{ key = "ImagePreviewerNativeImageScale", label = "Image Previewer Native Image Scale" },
	{
		key = "UsePreviousEasing",
		label = "Use Previous Easing/Handle",
		tip = "New keys inherit the preceding key's easing and handles. Turn this off to use Settings > Default Easing. Default Easing applies to new keys; it does not change existing keys.",
	},
	{
		key = "VFXFollowsFPS",
		label = "VFX follows FPS",
		tip = "makes effects speed up with the animation's FPS. double the default FPS = double the effect speed.",
	},
	{
		key = "VFXPausePreview",
		label = "VFX pause preview",
		tip = "Temporarily unavailable. Effects continue in real time instead of freezing when paused.",
	},
	{
		key = "VFXScrubberPreview",
		label = "VFX scrubber preview",
		tip = "Temporarily unavailable. Effects emit during playback; scrubbing does not reconstruct them.",
	},
	{ key = "FacesByDefault", label = "Faces by default" },
	{ key = "ShowFKIK", label = "Show FK/IK" },
	{ key = "ShowHeadStabilizer", label = "Show head IR shortcut" },
	{ key = "ShowMotionPaths", label = "Show motion paths" },
	{
		key = "MotionPathRange",
		label = "Path range",
		choices = { 1, 2, 3, 4 },
		choiceLabels = { "Full", "Keys", "Frames", "Custom" },
		tip = "Full: the entire path. Keys: nearby keyframes before and after the playhead. Frames: a fixed frame range around the playhead.",
	},
	{
		key = "MotionPathStart",
		label = "Start frame",
		numeric = true,
		min = 0,
		max = 144000,
		step = 1,
	},
	{ key = "MotionPathEnd", label = "End frame", numeric = true, min = 0, max = 144000, step = 1 },
	{
		key = "MotionPathEachSide",
		label = "Each side",
		numeric = true,
		min = 1,
		max = 1000,
		step = 1,
		tip = "Keys: this many keyframes on each side, plus a key at the playhead. Frames: this many frames before and after. Full ignores this value.",
	},
	{
		key = "MotionPathNumbers",
		label = "Path Frame Numbers",
		choices = { 1, 2, 3 },
		tip = "1: auto, shows numbers where there is room plus the key under your mouse. 2: always. 3: off.",
	},
	{
		key = "MotionPathEditing",
		label = "Click path points",
		tip = "lets you click the white motion path dots to edit their curve handles. turn it off to just look at your paths.",
	},
	{ key = "ScaleGizmo", label = "Sizing gizmo (Shift + T)" },
	{
		key = "ColorKeysByInterpolation",
		label = "Color Keys by Interpolation",
		tip = "Color timeline and graph keys by interpolation: linear green, constant red, Bezier blue, and easing families in distinct colors. Selection and disabled colors still take priority.",
	},
	{ key = "ShowLoadMessage", label = "Show load message in Output" },
}

local GROUPS = {
	{
		name = "Blender",
		keys = {
			"TransformChannels",
			"BlenderCameraBeta",
			"BlenderPanSensitivity",
			"BlenderOrbitSensitivity",
			"BlenderZoomToMouse",
			"HideOriginBone",
			"OriginAlwaysShowing",
			"DisableCameraWASD",
			"DisableCameraQE",
			"MasterKeyframes",
			"ContinuousTimeline",
			"BlenderAxes",

			"NavigationGizmo",
			"BlenderGrabSensitivity",
			"BlenderRotateSensitivity",
			"BlenderTrackballSensitivity",
			"TrackballSensitivity",
			"IndividualRotationPivots",
			"FlatBoneList",
		},
	},
	{
		name = "Animation",
		keys = {
			"DefaultFPS",
			"DefaultRotationMode",
			"DefaultTrackLength",
			"FrameStep",
			"AltScrollFrameStep",
			"KeyframeJumpStep",
			"JumpKeysOnSelectedRig",
			"UsePreviousEasing",
			"ColorKeysByInterpolation",
		},
	},
	{
		name = "Rig & IK",
		keys = {
			"IKFeetPlanted",
			"R6IKLegPole",
			"R15PoleFollowsIK",
			"R6BendPercent",
			"SoftIKPercent",
			"SmoothIKTransitions",
			"BoneStyle",
			"BoneXRay",
			"BoneFrontIndicators",
			"FullBoneTransparency",
			"HandleBoneTransparency",
			"CustomBoneTransparency",
			"ArmatureBoneTransparency",
			"BoneSelectionAssist",
			"SelectKeysWithRigParts",
			"BoneSelectionRadius",
			"HideBoneLines",
			"AutomaticOnionSkin",
			"PoseGhostTransparency",
			"OnionSkinColor",
			"OnionSkinTransparency",
			"PoseGhostPreviousColor",
			"PoseGhostNextColor",
			"ShowFKIK",
			"ShowHeadStabilizer",
			"FacesByDefault",
		},
	},
	{
		name = "Gizmos",
		keys = {
			"HideAnimatorDuringTransform",
			"HideAnimatorForKeyboard",
			"HideAnimatorForGizmos",
			"ActiveToolDrag",
			"MoveSnapIncrement",
			"RotationSnapIncrement",
			"GizmoSize",
			"GizmoDistance",
			"OldPositionGizmo",
			"OldRotationGizmo",
			"PositionGizmoThickness",
			"ShowTransformReadout",
			"ShowRotationAxes",
			"DisableGizmoTrackball",
			"RotationTrackballSize",
			"DefaultAxisSpace",
			"SeparateTransformSpaces",
			"RotationGrabCircles",
			"RotationGrabCircleSize",
			"ScaleGizmo",
		},
	},
	{
		name = "Camera & Images",
		keys = {
			"ShowBonesInCamera",
			"CameraPreviewFPS",
			"CameraPreviewMaskOpacity",
			"GreenScreenColor",
			"CamTargetParentButton",
			"ImagePreviewerNativeImageScale",
		},
	},
	{
		name = "Motion Paths",
		keys = {
			"ShowMotionPaths",
			"MotionPathRange",
			"MotionPathEachSide",
			"MotionPathStart",
			"MotionPathEnd",
			"MotionPathNumbers",
			"MotionPathEditing",
		},
	},
	{
		name = "Graph & Drawing",
		keys = {
			"GraphClamp",
			"GraphCompressionPercent",
			"GraphAutoSmoothing",
			"GreasePencilSmoothing",
		},
	},
	{ name = "Effects", keys = { "VFXFollowsFPS", "VFXPausePreview", "VFXScrubberPreview" } },
	{
		name = "Interface",
		keys = { "TopbarShape", "OpenAutomatically", "GifPlayback", "TimelineScrollSensitivity" },
	},
	{ name = "Performance", keys = { "DeferredArmatureUpdates" } },
	{
		name = "Notifications",
		keys = {
			"NotifyKeyframeActions",
			"NotifyAxisSpace",
			"NotifyRigAdded",
			"NotifyImportSuccess",
			"NotifyPivotChanges",
			"NotifyCameraTips",
			"ShowLoadMessage",
		},
	},
}
local byKey, ordered = {}, {}
for _, option in OPTIONS do
	byKey[option.key] = option
end

for groupIndex, group in GROUPS do
	for index, key in group.keys do
		local option = assert(byKey[key], key)
		option.group = group.name
		option.order = groupIndex * 100 + index
		table.insert(ordered, option)
		byKey[key] = nil
	end
end

assert(next(byKey) == nil, "Uncategorized preference")
OPTIONS = ordered

local refs = {}
local active
local sessions = {}

local function make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function tag(object, attribute, key)
	object:SetAttribute(attribute, key)
	return object
end

local function round(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius) })
end

local function outline(object, transparency)
	return tag(
		make("UIStroke", object, "Outline", {
			Color = Theme.panelOutlineDefault(),
			Thickness = 1,
			Transparency = transparency or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		"ThemeStrk",
		"Strk"
	)
end

local function connect(session, signal, callback)
	local connection = signal:Connect(callback)
	table.insert(session.connections, connection)
	return connection
end

local function disconnect(session)
	if session.colorAnchor and ColorPicker.isOpen(session.colorAnchor) then
		ColorPicker.close(true)
	end

	for _, connection in session.connections do
		connection:Disconnect()
	end

	table.clear(session.connections)
	for _, cleanup in session.tipCleanups do
		cleanup()
	end

	table.clear(session.tipCleanups)
	if session.unsubscribe then
		session.unsubscribe()
		session.unsubscribe = nil
	end

	if session.flashTweens then
		for tween, stroke in session.flashTweens do
			tween:Cancel()
			stroke:Destroy()
		end

		table.clear(session.flashTweens)
	end
end

local function scaleOf(session)
	local animationScale = session.window:FindFirstChild("EclipseWindowScale")
	local scale = session.window.AbsoluteSize.X
		/ (WIDTH * (animationScale and animationScale.Scale or 1))
	return scale > 0 and scale or 1
end

local function restingPosition(session)
	local window = session.window
	local animationScale = window:FindFirstChild("EclipseWindowScale")
	local scale = animationScale and animationScale.Scale or 1
	return window.AbsolutePosition + window.AbsoluteSize * (0.5 - 0.5 / scale)
end

local function place(session, point)
	local window = session.window
	local parent = window.Parent
	if not parent then
		return
	end

	local scale = scaleOf(session)
	local origin, viewport = parent.AbsolutePosition, parent.AbsoluteSize
	local desired = UDim2.fromOffset(
		(point.X - origin.X) / scale + WIDTH * 0.5,
		(point.Y - origin.Y) / scale + HEIGHT * 0.5
	)
	window.Position = WindowMotion.reachable(
		desired,
		Vector2.new(WIDTH, HEIGHT),
		viewport / scale,
		Vector2.new(0.5, 0.5),
		scale
	)
end

local function hideTip(session)
	if not session.hoverDialog then
		return
	end

	for _, tip in session.tips do
		session.hoverDialog:disappear(tip.button)
	end
end

local function dispose(session, destroyWindow)
	if session.disposed then
		return
	end

	session.disposed = true
	session.closing = true
	hideTip(session)
	disconnect(session)
	if session.hoverDialog then
		session.hoverDialog:Destroy()
		session.hoverDialog = nil
	end

	WindowFX.clear(session.window)
	sessions[session] = nil
	if active == session then
		active = nil
	end

	if destroyWindow then
		session.window:Destroy()
	end
end

local function bindDrag(session, handle)
	WindowMotion.resetOnOpen(session.window)
	Chrome.bindDrag(session.window, handle, {
		disabled = function()
			return session.closing or session.window:GetAttribute("EclipseDocked") == true
		end,
		clamp = true,
		threshold = 3,
		began = function()
			hideTip(session)
		end,
	})
	connect(session, session.window.Parent:GetPropertyChangedSignal("AbsoluteSize"), function()
		if not session.closing and not session.window:GetAttribute("EclipseDocked") then
			hideTip(session)
			place(session, restingPosition(session))
		end
	end)
end

local function bindTip(session, button, text)
	local tooltip = session.hoverDialog
	if not tooltip then
		return
	end

	local options = { maxWidth = 320 }
	table.insert(session.tipCleanups, tooltip:latchToInstance(button, text, options))

	local function show()
		if session.closing or not button.Parent then
			return
		end

		tooltip:popup(text, button, options)
	end

	connect(session, button.SelectionGained, show)
	connect(session, button.SelectionLost, function()
		tooltip:disappear(button)
	end)
	connect(session, button.Activated, function()
		if tooltip.open and tooltip.causedElement == button then
			tooltip:disappear(button)
		else
			show()
		end
	end)
end

function Editor.blenderSuggestion()
	local channels = Preferences.get("TransformChannels") == true
	local continuous = Preferences.get("ContinuousTimeline") == true
	if channels and continuous then
		return nil
	end

	if not channels and not continuous then
		return "To get the full Blender feel, enable transform channels and continuous timeline too."
	end

	if not channels then
		return "To get the full Blender feel, enable transform channels too."
	end

	return "To get the full Blender feel, enable continuous timeline too."
end

function Editor.init(newRefs)
	if refs.ScreenGui ~= newRefs.ScreenGui then
		Editor.destroy()
	end

	refs = newRefs
end

local function highlightRows(session, keys)
	if not session or session.closing then
		return
	end

	if session.flashTweens then
		for tween, stroke in session.flashTweens do
			tween:Cancel()
			stroke:Destroy()
		end
	end

	session.flashTweens = {}
	local first = session.rows and session.rows[keys[1]]
	local last = session.rows and session.rows[keys[#keys]]
	if not first or not last then
		return
	end

	local scroll = first.Parent
	local midpoint = (first.AbsolutePosition.Y + last.AbsolutePosition.Y + last.AbsoluteSize.Y)
		* 0.5
	local target = scroll.CanvasPosition.Y
		+ midpoint
		- scroll.AbsolutePosition.Y
		- scroll.AbsoluteSize.Y * 0.5
	local maximum = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y)
	scroll.CanvasPosition = Vector2.new(0, math.clamp(target, 0, maximum))

	for _, key in keys do
		local row = session.rows[key]
		local stroke = make("UIStroke", row, "GraphPreferenceHighlight", {
			Color = Theme.get("Txt", Color3.new(1, 1, 1)),
			Thickness = 2,
			StrokeSizingMode = Enum.StrokeSizingMode.FixedSize,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
		local tween = TweenService:Create(
			stroke,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true, 0.18),
			{ Transparency = 0.55 }
		)
		session.flashTweens[tween] = stroke
		tween.Completed:Once(function()
			session.flashTweens[tween] = nil
			stroke:Destroy()
		end)
		tween:Play()
	end
end

local function openFocused(keys, group)
	local session = Editor.open()
	if not session then
		return
	end

	session.selectGroup(group or "All")
	local focusVersion = session.focusVersion
	if not session.graphRaised then
		session.graphRaised = true
		for _, object in { session.window, table.unpack(session.window:GetDescendants()) } do
			if object:IsA("GuiObject") then
				object.ZIndex += 200
			end
		end
	end

	task.delay(0.25, function()
		if
			not session.closing
			and session.window.Parent
			and session.focusVersion == focusVersion
		then
			highlightRows(session, keys)
		end
	end)
	return session
end

function Editor.openGraphPreferences()
	return openFocused(
		{ "GraphClamp", "GraphCompressionPercent", "GraphAutoSmoothing" },
		"Graph & Drawing"
	)
end

function Editor.openMotionPathPreferences()
	return openFocused({ "MotionPathRange", "MotionPathEachSide" }, "Motion Paths")
end

function Editor.openImagePreviewerPreferences()
	return openFocused({ "ImagePreviewerNativeImageScale" })
end

function Editor.open()
	if active and not active.closing then
		if active.window.Parent then
			return active
		end

		dispose(active, false)
	end

	local parent = refs.ScreenGui
	if not parent or not parent.Parent then
		return
	end

	local titleTemplate = refs.RigItemTemplate
		and refs.RigItemTemplate:FindFirstChild("Title", true)
	local fontFace = titleTemplate and titleTemplate.FontFace
		or Font.new("rbxasset://fonts/families/RobotoMono.json")
	local window = tag(
		make("Frame", nil, "PreferencesEditor", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(WIDTH, HEIGHT),
			BackgroundColor3 = Color3.fromRGB(22, 16, 28),
			BorderSizePixel = 0,
			Active = true,
			Visible = false,
			ZIndex = 100,
		}),
		"ThemeBg",
		"Bg"
	)
	round(window, 6)
	outline(window)
	local session = {
		window = window,
		connections = {},
		controls = {},
		units = {},
		rows = {},
		flushers = {},
		tips = {},
		tipCleanups = {},
		hoverDialog = nil,
	}

	function session.flush()
		if session.closing then
			return
		end

		for _, flush in session.flushers do
			flush()
		end
	end

	active = session
	sessions[session] = true
	window.Destroying:Once(function()
		dispose(session, false)
	end)

	local function label(parentObject, name, text, position, size)
		return tag(
			make("TextLabel", parentObject, name, {
				Text = text,
				Position = position,
				Size = size,
				BackgroundTransparency = 1,
				FontFace = fontFace,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(230, 223, 238),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 103,
			}),
			"ThemeTxt",
			"Txt"
		)
	end

	local header = tag(
		make("Frame", window, "Header", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(49, 16, 65),
			BorderSizePixel = 0,
			ZIndex = 101,
		}),
		"ThemeBg",
		"Top"
	)
	round(header, 6)
	tag(
		make("Frame", header, "LowerEdge", {
			Position = UDim2.new(0, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = header.BackgroundColor3,
			BorderSizePixel = 0,
			ZIndex = 101,
		}),
		"ThemeBg",
		"Top"
	)
	local title = tag(
		label(header, "Title", "PREFERENCES", UDim2.fromOffset(12, 0), UDim2.new(1, -46, 1, 0)),
		"ThemeTxt",
		"TopT"
	)
	title.TextSize = 15
	local dragHandle = make("TextButton", header, "DragHandle", {
		Text = "",
		Size = UDim2.new(1, -114, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		ZIndex = 104,
	})
	local close = tag(
		make("TextButton", header, "Close", {
			Text = "×",
			Position = UDim2.new(1, -31, 0, 4),
			Size = UDim2.fromOffset(26, 26),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			FontFace = fontFace,
			TextSize = 19,
			TextColor3 = Color3.fromRGB(230, 223, 238),
			ZIndex = 105,
		}),
		"ThemeTxt",
		"TopT"
	)
	local body = tag(
		make("Frame", window, "Body", {
			Position = UDim2.fromOffset(148, 80),
			Size = UDim2.new(1, -158, 1, -90),
			BackgroundColor3 = Color3.fromRGB(15, 12, 19),
			BorderSizePixel = 0,
			ZIndex = 101,
		}),
		"ThemeBg",
		"Pnl"
	)
	round(body, 5)
	outline(body, 0.35)
	local scroll = tag(
		make("ScrollingFrame", body, "Options", {
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarImageColor3 = Color3.fromRGB(111, 78, 130),
			ZIndex = 102,
		}),
		"ThemeScr",
		"Scr"
	)
	make(
		"UIListLayout",
		scroll,
		"Layout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	make("UIPadding", scroll, "Padding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	})
	local search = tag(
		make("TextBox", window, "Search", {
			Position = UDim2.fromOffset(10, 42),
			Size = UDim2.new(1, -20, 0, 28),
			Text = "",
			PlaceholderText = "Search all preferences",
			ClearTextOnFocus = false,
			FontFace = fontFace,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = body.BackgroundColor3,
			BorderSizePixel = 0,
			TextColor3 = Theme.get("Txt", Color3.new(1, 1, 1)),
			ZIndex = 103,
		}),
		"ThemeBg",
		"Pnl"
	)
	tag(search, "ThemeTxt", "Txt")
	round(search, 4)
	outline(search, 0.35)
	make(
		"UIPadding",
		search,
		"Padding",
		{ PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }
	)
	local categories = make("ScrollingFrame", window, "Categories", {
		Position = UDim2.fromOffset(10, 80),
		Size = UDim2.new(0, 128, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 102,
	})
	make(
		"UIListLayout",
		categories,
		"Layout",
		{ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	session.group = "All"
	local groupButtons, sectionHeaders = {}, {}
	local empty = label(
		body,
		"Empty",
		"No matching preferences",
		UDim2.fromOffset(12, 12),
		UDim2.new(1, -24, 0, 24)
	)
	empty.TextSize = 13
	empty.Visible = false

	local function filter()
		hideTip(session)
		local query = search.Text:lower():match("^%s*(.-)%s*$")
		local matches, total = {}, 0
		for _, option in OPTIONS do
			local haystack = (option.label .. " " .. option.group .. " " .. (option.tip or "")):lower()
			local match = (session.group == "All" or option.group == session.group)
				and (not option.blenderOnly or Preferences.get("BlenderCameraBeta") == true)
				and (not option.dependsOn or Preferences.get(option.dependsOn) == true)
			for word in query:gmatch("%S+") do
				if not haystack:find(word, 1, true) then
					match = false
				end
			end

			if option.key == "MotionPathEachSide" then
				local mode = Preferences.get("MotionPathRange")
				match = match and (mode == 2 or mode == 3)
				session.rows[option.key].Label.Text = mode == 2 and "Keys each side"
					or "Frames each side"
			end

			if option.key == "MotionPathStart" or option.key == "MotionPathEnd" then
				match = match and Preferences.get("MotionPathRange") == 4
			end

			session.rows[option.key].Visible = match
			if match then
				matches[option.group] = true
				total += 1
			end
		end

		for name, header in sectionHeaders do
			header.Visible = matches[name] == true
		end

		for name, button in groupButtons do
			button.SelectionHighlight.Visible = name == session.group
		end

		empty.Visible = total == 0
	end

	function session.selectGroup(name)
		if not groupButtons[name] then
			return
		end

		session.flush()
		session.focusVersion = (session.focusVersion or 0) + 1
		session.group = name
		search.Text = ""
		filter()
		scroll.CanvasPosition = Vector2.zero
	end

	local categoryNames = { "All" }
	for _, group in GROUPS do
		table.insert(categoryNames, group.name)
	end

	for index, name in categoryNames do
		local button = tag(
			make("TextButton", categories, name, {
				Size = UDim2.new(1, -4, 0, 30),
				LayoutOrder = index,
				Text = "",
				BackgroundColor3 = body.BackgroundColor3,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				ZIndex = 102,
			}),
			"ThemeBg",
			"Pnl"
		)
		round(button, 4)
		local selected = tag(
			make("Frame", button, "SelectionHighlight", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.get("MenuSel", Color3.fromRGB(45, 27, 56)),
				BorderSizePixel = 0,
				ZIndex = 103,
			}),
			"ThemeBg",
			"MenuSel"
		)
		round(selected, 4)
		local text = label(button, "Label", name, UDim2.fromOffset(8, 0), UDim2.new(1, -12, 1, 0))
		text.TextSize = 11
		text.ZIndex = 104
		groupButtons[name] = button
		connect(session, button.Activated, function()
			if not session.closing then
				session.selectGroup(name)
			end
		end)
	end

	for index, group in GROUPS do
		local header = label(
			scroll,
			"Section" .. index,
			group.name:upper(),
			UDim2.new(),
			UDim2.new(1, 0, 0, 26)
		)
		header.LayoutOrder = index * 100
		header.TextSize = 12
		header.TextTransparency = 0.25
		sectionHeaders[group.name] = header
	end

	connect(session, search:GetPropertyChangedSignal("Text"), function()
		if session.closing then
			return
		end

		if search.Text ~= "" then
			session.focusVersion = (session.focusVersion or 0) + 1
			session.group = "All"
		end

		filter()
		scroll.CanvasPosition = Vector2.zero
	end)

	local function refresh(key, force)
		local control = session.controls[key]
		if not control or session.closing then
			return
		end

		if control:GetAttribute("PreferenceColor") then
			control.BackgroundColor3 = Preferences.color(key)
		elseif key == "DefaultRotationMode" then
			local value = Preferences.get(key)
			control.Text = value == "Quaternion" and value .. "  \u{25BE}"
				or "Euler " .. value .. "  \u{25BE}"
		elseif control:IsA("Frame") then
			for _, button in control:GetChildren() do
				button.Highlight.Visible = tonumber(button.Name) == Preferences.get(key)
			end
		elseif control:IsA("TextBox") then
			if not control:IsFocused() or force then
				control.Text = tostring(Preferences.get(key)) .. (session.units[key] or "")
			end
		else
			control.Mark.Visible = Preferences.get(key) == true
		end
	end

	for index, option in OPTIONS do
		local unavailable = Preferences.unavailableReason(option.key)
		local row = make("Frame", scroll, option.key, {
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = option.order,
			BackgroundTransparency = 1,
			ZIndex = 102,
		})
		session.rows[option.key] = row
		row.Visible = not option.blenderOnly or Preferences.get("BlenderCameraBeta") == true
		local optionLabel = label(
			row,
			"Label",
			option.label,
			UDim2.fromOffset(7, 0),
			UDim2.new(1, option.choices and -170 or option.numeric and -134 or -96, 1, 0)
		)
		optionLabel.TextWrapped = true
		if unavailable then
			optionLabel.TextTransparency = 0.55
			optionLabel.TextSize = 12
			optionLabel.Text = option.label .. " (temporarily unavailable)"
		end
		optionLabel.TextYAlignment = Enum.TextYAlignment.Center
		local dependent = option.dependsOn ~= nil or option.blenderOnly == true
		if dependent then
			optionLabel.Position += UDim2.fromOffset(18, 0)
			optionLabel.Size -= UDim2.fromOffset(18, 0)
			tag(
				make("Frame", row, "DependencyLine", {
					Position = UDim2.fromOffset(12, -3),
					Size = UDim2.new(0, 1, 1, 6),
					BackgroundColor3 = Theme.get("Strk", Theme.panelOutlineDefault()),
					BorderSizePixel = 0,
					Active = false,
					ZIndex = 103,
				}),
				"ThemeBg",
				"Strk"
			)
		end

		if option.blenderFeature then
			make("ImageLabel", row, "BlenderIcon", {
				Image = "rbxassetid://93204150139908",
				BackgroundTransparency = 1,
				Position = UDim2.new(0, dependent and 25 or 7, 0.5, -9),
				Size = UDim2.fromOffset(18, 18),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 103,
			})
			optionLabel.Position += UDim2.fromOffset(23, 0)
			optionLabel.Size -= UDim2.fromOffset(23, 0)
		end

		if option.key == "ImagePreviewerNativeImageScale" then
			optionLabel.TextWrapped = true
			optionLabel.TextSize = 12
		end

		if option.choiceLabels then
			optionLabel.TextSize = 12
			optionLabel.Size = UDim2.new(1, option.tip and -268 or -242, 1, 0)
		end

		if option.color then
			local button = make("TextButton", row, "ColorSwatch", {
				Position = UDim2.new(1, -32, 0.5, -12),
				Size = UDim2.fromOffset(24, 24),
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				ZIndex = 105,
				BackgroundColor3 = Preferences.color(option.key),
			})
			button:SetAttribute("PreferenceColor", true)
			round(button, 4)
			outline(button, 0.2)
			session.controls[option.key] = button
			connect(session, button.Activated, function()
				if session.closing then
					return
				end

				session.colorAnchor = button
				ColorPicker.open(
					refs,
					button,
					{ stops = { Preferences.color(option.key) }, rot = 0 },

					function(value)
						if not session.closing then
							Preferences.set(option.key, value.stops[1])
							refresh(option.key, true)
						end
					end,
					{
						solid = true,
						commitOnDone = true,
						alive = function()
							return not session.closing and button.Parent ~= nil
						end,
					}
				)
			end)
		elseif option.rotationChoice then
			optionLabel.Size = UDim2.new(1, -180, 1, 0)
			optionLabel.TextSize = 12
			local button = tag(
				make("TextButton", row, "RotationChoice", {
					Position = UDim2.new(1, -120, 0.5, -14),
					Size = UDim2.fromOffset(112, 28),
					BackgroundColor3 = body.BackgroundColor3,
					BorderSizePixel = 0,
					FontFace = fontFace,
					TextSize = 12,
					TextColor3 = Theme.get("Txt", Color3.new(1, 1, 1)),
					ZIndex = 105,
				}),
				"ThemeBg",
				"Bg"
			)
			button:SetAttribute("ThemeTxt", "Txt")
			round(button, 4)
			outline(button, 0.35)
			session.controls[option.key] = button
			connect(session, button.Activated, function()
				if session.rotationPopup then
					session.rotationPopup:Destroy()
					session.rotationPopup = nil
					return
				end

				local pos = (button.AbsolutePosition - window.AbsolutePosition) / scaleOf(session)
				local popup = tag(
					make("Frame", window, "RotationModes", {
						Position = UDim2.fromOffset(pos.X, math.min(pos.Y + 28, HEIGHT - 202)),
						Size = UDim2.fromOffset(112, 196),
						BackgroundColor3 = body.BackgroundColor3,
						BorderSizePixel = 0,
						ZIndex = 120,
					}),
					"ThemeBg",
					"Bg"
				)
				session.rotationPopup = popup
				round(popup, 4)
				outline(popup)
				for i, mode in { "Quaternion", "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX" } do
					local item = tag(
						make("TextButton", popup, mode, {
							Position = UDim2.fromOffset(0, (i - 1) * 28),
							Size = UDim2.fromOffset(112, 28),
							Text = mode == "Quaternion" and mode or "Euler " .. mode,
							BackgroundTransparency = 1,
							FontFace = fontFace,
							TextSize = 12,
							TextColor3 = Theme.get("Txt", Color3.new(1, 1, 1)),
							ZIndex = 121,
						}),
						"ThemeTxt",
						"Txt"
					)
					connect(session, item.Activated, function()
						Preferences.set(option.key, mode)
						popup:Destroy()
						session.rotationPopup = nil
						refresh(option.key)
					end)
				end

				Theme.applyTree(popup)
			end)
		elseif option.choices then
			local choiceWidth = option.choiceLabels and 206 or 98
			local buttonWidth = option.choiceLabels
					and (choiceWidth - 4 * (#option.choices - 1)) / #option.choices
				or 30
			local choices = make("Frame", row, "Choices", {
				Position = UDim2.new(1, -choiceWidth - 8, 0.5, -14),
				Size = UDim2.fromOffset(choiceWidth, 28),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 103,
			})
			session.controls[option.key] = choices
			for index, value in option.choices do
				local button = tag(
					make("TextButton", choices, tostring(value), {
						Position = UDim2.fromOffset((index - 1) * (buttonWidth + 4), 0),
						Size = UDim2.fromOffset(buttonWidth, 28),
						Text = "",
						BackgroundColor3 = Color3.fromRGB(45, 27, 56),
						BorderSizePixel = 0,
						AutoButtonColor = true,
						ZIndex = 103,
					}),
					"ThemeBg",
					"TopBtn"
				)
				round(button, 4)
				outline(button, 0.35)
				local highlight = tag(
					make("Frame", button, "Highlight", {
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Color3.fromRGB(100, 0, 151),
						BorderSizePixel = 0,
						ZIndex = 104,
					}),
					"ThemeBg",
					"MenuSel"
				)
				round(highlight, 4)
				outline(highlight, 0)
				local text = label(
					button,
					"Number",
					option.choiceLabels and option.choiceLabels[index] or tostring(value),
					UDim2.new(),
					UDim2.fromScale(1, 1)
				)
				text.TextSize = option.choiceLabels and 11 or 15
				text.TextXAlignment = Enum.TextXAlignment.Center
				text.ZIndex = 105
				connect(session, button.Activated, function()
					if session.closing then
						return
					end

					Preferences.set(option.key, value)
					refresh(option.key)
				end)
			end
		elseif option.numeric then
			local shell = tag(
				make("Frame", row, "Input", {
					Position = UDim2.new(1, -70, 0.5, -14),
					Size = UDim2.fromOffset(62, 28),
					BackgroundColor3 = Color3.fromRGB(22, 16, 28),
					BorderSizePixel = 0,
					ZIndex = 103,
				}),
				"ThemeBg",
				"Bg"
			)
			round(shell, 4)
			outline(shell)
			local box = tag(
				make("TextBox", shell, "Value", {
					Position = UDim2.fromOffset(5, 2),
					Size = UDim2.new(1, -10, 1, -4),
					Text = "",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					FontFace = fontFace,
					TextSize = 15,
					TextColor3 = Color3.fromRGB(230, 223, 238),
					ClearTextOnFocus = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 104,
				}),
				"ThemeTxt",
				"Txt"
			)
			box.TextScaled = true
			make(
				"UITextSizeConstraint",
				box,
				"TextSizeLimit",
				{ MinTextSize = 10, MaxTextSize = 15 }
			)
			session.controls[option.key] = box
			session.units[option.key] = option.unit
			connect(session, box.Focused, function()
				box.Text = ""
			end)

			local function flush()
				if session.closing then
					return
				end

				local text = box.Text:gsub("%%%s*$", ""):gsub("px%s*$", "")
				local value = tonumber(text)
				if value and value == value and math.abs(value) < math.huge then
					Preferences.set(option.key, value)
				end

				refresh(option.key, true)
			end

			table.insert(session.flushers, flush)
			require("NumericInput").bind(box, {
				step = option.step
					or (
						(
								option.unit == "%"
								or option.unit == "px"
								or option.key == "FrameStep"
								or option.key == "KeyframeJumpStep"
								or option.key == "DefaultFPS"
								or option.key == "CameraPreviewFPS"
								or option.key == "DefaultTrackLength"
							)
							and 1
						or 0.1
					),
				min = option.min,
				max = option.max,
			})
			connect(session, box.FocusLost, flush)
		else
			local toggle = tag(
				make("TextButton", row, "Toggle", {
					Position = UDim2.new(1, -32, 0.5, -12),
					Size = UDim2.fromOffset(24, 24),
					Text = "",
					BackgroundColor3 = Color3.fromRGB(45, 27, 56),
					BorderSizePixel = 0,
					AutoButtonColor = true,
					ZIndex = 103,
				}),
				"ThemeBg",
				"TopBtn"
			)
			round(toggle, 4)
			outline(toggle, 0.35)
			local mark = label(toggle, "Mark", "✓", UDim2.new(), UDim2.fromScale(1, 1))
			mark.TextSize = 19
			mark.TextXAlignment = Enum.TextXAlignment.Center
			mark.ZIndex = 104
			session.controls[option.key] = toggle
			if unavailable then
				toggle.Active, toggle.Interactable, toggle.Selectable = false, false, false
				toggle.AutoButtonColor = false
				toggle.BackgroundTransparency = 0.65
			end
			connect(session, toggle.Activated, function()
				if session.closing or unavailable then
					return
				end

				local enabling = Preferences.get(option.key) ~= true
				local saved = Preferences.set(option.key, enabling)
				if saved and enabling and option.key == "HideAnimatorDuringTransform" then
					require("Notification").show(
						"HIDE ANIMATOR",
						"Will not affect docked mode.",
						5
					)
				end

				if saved and enabling and option.key == "AutomaticOnionSkin" then
					require("Notification").show(
						"POSE GHOSTS",
						"May cause performance issues. Disable if on a lower-end device.",
						5
					)
				end

				if saved and enabling and option.key == "BlenderCameraBeta" then
					local tip = Editor.blenderSuggestion()
					if tip then
						require("Notification").show("BLENDER CAMERA", tip, 10)
					end
				end

				refresh(option.key)
			end)
		end

		local reset = tag(
			make("ImageButton", row, "Reset", {
				Position = UDim2.new(
					1,
					option.rotationChoice and -150
						or option.choiceLabels and -240
						or option.choices and -132
						or option.numeric and -96
						or -58,
					0.5,
					-9
				),
				Size = UDim2.fromOffset(18, 18),
				Image = RESET_ICON,
				ImageColor3 = Color3.fromRGB(230, 223, 238),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 104,
			}),
			"ThemeImg",
			"Txt"
		)
		if unavailable then
			reset.Active, reset.Interactable, reset.Selectable = false, false, false
			reset.AutoButtonColor = false
			reset.ImageTransparency = 0.65
		end
		local default = Preferences.defaults()[option.key]
		table.insert(session.tips, {
			button = reset,
			text = "Reset to default: " .. tostring(default) .. (option.unit or ""),
		})
		connect(session, reset.Activated, function()
			if session.closing or unavailable then
				return
			end

			local control = session.controls[option.key]
			if ColorPicker.isOpen(control) then
				ColorPicker.close(true)
			end

			if control:IsA("TextBox") and control:IsFocused() then
				control:ReleaseFocus()
			end

			Preferences.set(option.key, default)
			refresh(option.key, true)
		end)
		if option.tip then
			local info = tag(
				make("TextButton", row, "Info", {
					Position = UDim2.new(
						1,
						option.rotationChoice and -176
							or option.choiceLabels and -266
							or option.choices and -158
							or option.numeric and -122
							or -84,
						0.5,
						-9
					),
					Size = UDim2.fromOffset(18, 18),
					Text = "i",
					FontFace = fontFace,
					TextSize = 13,
					TextColor3 = Color3.fromRGB(230, 223, 238),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 104,
				}),
				"ThemeTxt",
				"Txt"
			)
			round(info, 9)
			outline(info, 0.35)
			table.insert(session.tips, { button = info, text = option.tip })
		end

		if option.blenderFeature then
			for _, text in row:GetDescendants() do
				if text:IsA("TextLabel") or text:IsA("TextButton") or text:IsA("TextBox") then
					text:SetAttribute("ThemeTxt", nil)
					text.TextColor3 = Color3.fromRGB(234, 118, 0)
				end
			end
		end

		refresh(option.key)
	end

	session.unsubscribe = Preferences.subscribe(function(key)
		refresh(key)
		if
			key == "BlenderCameraBeta"
			or key == "HideAnimatorDuringTransform"
			or key == "MotionPathRange"
		then
			hideTip(session)
			filter()
		end
	end)
	filter()
	connect(session, close.Activated, Editor.close)
	connect(session, scroll:GetPropertyChangedSignal("CanvasPosition"), function()
		hideTip(session)
	end)
	connect(session, UserInputService.InputBegan, function(input)
		if Shortcuts.matches("Cancel", input) then
			if session.colorAnchor and ColorPicker.isOpen(session.colorAnchor) then
				ColorPicker.cancel()
				return
			end

			Editor.close()
		end
	end)
	window.Parent = parent
	if refs.HoverDialog and refs.HoverDialog.ui and refs.HoverDialog.mouse then
		local tip = refs.HoverDialog.ui:Clone()
		tip.Name = "PreferenceInformation"
		tip.Visible = false
		local label = tip:FindFirstChild("Information")
		if label then
			local limit = label:FindFirstChild("TooltipSizeLimit")
			if limit then
				limit:Destroy()
			end

			for property, value in refs.HoverDialog.labelDefaults or {} do
				label[property] = value
			end
		end

		tip.Parent = window
		session.hoverDialog = require("HoverDialog").initialize(tip, refs.HoverDialog.mouse)
	end

	require("Tool").attachPopup(window, header, refs, "PreferencesEditor", "PREFERENCES", Vector2.new(WIDTH, 320), Editor.close)
	bindDrag(session, dragHandle)
	for _, tip in session.tips do
		bindTip(session, tip.button, tip.text)
	end

	Theme.applyTree(window)
	task.defer(function()
		if session.closing or not window.Parent then
			return
		end

		place(session, restingPosition(session))
		window.Visible = true
		WindowFX.pop(window, "batch")
	end)
	return session
end

function Editor.close()
	local session = active
	if not session or session.closing then
		return
	end

	session.flush()
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(session.window) then
		focused:ReleaseFocus()
	end

	session.closing = true
	active = nil
	hideTip(session)
	disconnect(session)
	for _, object in session.window:GetDescendants() do
		if object:IsA("GuiButton") then
			object.Interactable = false
		end

		if object:IsA("TextBox") then
			object.TextEditable = false
		end
	end

	WindowFX.shrink(session.window, function()
		dispose(session, true)
	end, "batch")
end

function Editor.destroy()
	local pending = {}
	for session in sessions do
		table.insert(pending, session)
	end

	for _, session in pending do
		if not session.closing and session.flush then
			session.flush()
		end

		dispose(session, true)
	end

	active = nil
end

return Editor
