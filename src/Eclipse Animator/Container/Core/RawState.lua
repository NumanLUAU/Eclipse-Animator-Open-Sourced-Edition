--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Timeline = {
	CurrentTime = 0,
	Playing = false,
	Recording = false,
	Keyframes = {},
	FPS = 60,
	SkipFrames = 0,
	PlaybackStartFrame = 0,
	ScrollOffset = 0,
	OnlyShowSelected = false,
	DefaultPose = {},
	DefaultWorldPose = {},
	ParentingDefaults = {},
	MotorByPart = {},
	DefaultSize = {},
	TrackRows = {},
	ChannelTracks = {},
	ContentWidth = 0,
	TrackHeight = 24,
	Ruler = nil,
	TracksRoot = nil,
	SelectedKeyframe = nil,
	SelectedKeyframes = {},
	SelectedChannelKeyframes = {},
	CopiedKeyframes = {},
	_GlobalUnselectBound = false,
	_motorUniform = {},
	_motorHasScale = {},
}

local Config = {
	Length = 4.5,
	DefaultFrames = 270,
	PixelsPerSecond = 100,
	RulerHeight = 20,
}

local State = {
	Timeline = Timeline,
	Config = Config,
	PlayheadDrag = {
		draggingPlayhead = false,
		playhead = nil,
		playheadMouseOffsetX = 0,
		dragStartMouseX = 0,
		dragStartFrame = 0,
	},
	KeyframeDrag = {
		draggingKeyframe = nil,
		hoveringKeyframe = nil,
		hoveringChannelId = nil,
		dragMouseFrameOffset = 0,
		keyframeDragThreshold = 4,
		dragCurrentFrame = nil,
		dragHoverReplaceTarget = nil,
		groupDragOriginals = {},
		groupDragSelected = {},
		groupDragSelectedChannels = {},
	},
	Selection = {
		selectionBox = nil,
		selectionDragging = false,
		selectionStartMouse = nil,
		selectionStartTimelinePoint = nil,
	},
	KeyframeTransform = {
		active = false,
		mode = nil,
		frozen = false,
		startMouseX = 0,
		pivotFrame = 0,
		pivotPixelX = 0,
		originals = {},
		liveFrames = {},
	},
	timelineUI = nil,
	Colors = {
		KEYFRAME_DEFAULT_COLOR = Color3.fromRGB(255, 255, 255),
		KEYFRAME_HOVER_COLOR = Color3.fromRGB(158, 158, 158),
		KEYFRAME_SELECTED_COLOR = Color3.fromRGB(145, 90, 255),
		LOOP_ACTIVE_COLOR = Color3.fromRGB(255, 222, 114),
		LOOP_INACTIVE_COLOR = Color3.fromRGB(108, 104, 94),
		RECORD_ACTIVE_COLOR = Color3.fromRGB(255, 84, 84),
		RECORD_INACTIVE_COLOR = Color3.fromRGB(112, 94, 94),

		KEYFRAME_HANDLE_DEFAULT = {
			Automatic = Color3.fromRGB(255, 178, 120),
			Aligned = Color3.fromRGB(255, 128, 141),
			AutoClamped = Color3.fromRGB(255, 255, 255),
			Vector = Color3.fromRGB(175, 230, 160),
			Free = Color3.fromRGB(140, 178, 255),
		},
		KEYFRAME_HANDLE_HOVER = {
			Automatic = Color3.fromRGB(180, 158, 130),
			Aligned = Color3.fromRGB(180, 135, 140),
			AutoClamped = Color3.fromRGB(158, 158, 158),
			Vector = Color3.fromRGB(155, 175, 148),
			Free = Color3.fromRGB(138, 158, 180),
		},
	},
}

return State
