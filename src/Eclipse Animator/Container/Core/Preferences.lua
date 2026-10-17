--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local HttpService = game:GetService("HttpService")

local Preferences = {}
local UNAVAILABLE = table.freeze({
	VFXPausePreview = "Temporarily unavailable. Effects continue in real time instead of freezing when paused.",
	VFXScrubberPreview = "Temporarily unavailable. Effects emit during playback; scrubbing does not reconstruct them.",
})
local SETTING_KEY = "EclipseAnimator_Preferences"
local TOPBAR_SHAPE_VERSION = 2
local DEFAULTS = table.freeze({
	ShowLoadMessage = true,
	DefaultFPS = 60,
	DefaultRotationMode = "Quaternion",
	CameraPreviewFPS = 0,
	CameraPreviewMaskOpacity = 45,
	GreenScreenColor = "00FF00",
	ShowBonesInCamera = true,
	NavigationGizmo = false,
	NavigationGizmoX = 1,
	NavigationGizmoY = 0,
	DeferredArmatureUpdates = false,
	SmoothIKTransitions = true,
	KeyframeJumpStep = 1,
	JumpKeysOnSelectedRig = false,
	FrameStep = 1,
	AltScrollFrameStep = 1,
	GifPlayback = 1,
	DefaultTrackLength = 270,
	GreasePencilSmoothing = 50,
	BoneStyle = 1,
	BoneXRay = true,
	BoneFrontIndicators = false,
	FullBoneTransparency = 80,
	HandleBoneTransparency = 55,
	CustomBoneTransparency = 20,
	ArmatureBoneTransparency = 65,
	BoneSelectionAssist = true,
	SelectKeysWithRigParts = false,
	BoneSelectionRadius = 10,
	HideBoneLines = false,
	AutomaticOnionSkin = false,
	PoseGhostTransparency = 85,
	OnionSkinColor = "541B9A",
	OnionSkinTransparency = 60,
	PoseGhostPreviousColor = "FF4B4B",
	PoseGhostNextColor = "4BFF7D",
	PhysicsAcknowledged = false,
	GizmoSize = 1,
	HideAnimatorDuringTransform = false,
	HideAnimatorForKeyboard = true,
	HideAnimatorForGizmos = false,
	OldPositionGizmo = false,
	OldRotationGizmo = false,
	PositionGizmoThickness = 1,
	ShowTransformReadout = false,
	ShowRotationAxes = true,
	RotationGrabCircles = true,
	MatchRotationHandles = false,
	IndividualRotationPivots = true,
	RotationGrabCircleSize = 18,
	TrackballSensitivity = 1,
	BlenderGrabSensitivity = 1,
	BlenderRotateSensitivity = 1,
	BlenderTrackballSensitivity = 1,
	DisableGizmoTrackball = false,
	RotationTrackballSize = 100,
	TimelineScrollSensitivity = 1,
	DefaultAxisSpace = 0,
	SeparateTransformSpaces = false,
	PositionAxisSpace = 1,
	RotationAxisSpace = 1,
	ActiveToolDrag = false,
	NotifyKeyframeActions = true,
	NotifyAxisSpace = true,
	NotifyRigAdded = true,
	NotifyImportSuccess = true,
	NotifyPivotChanges = true,
	NotifyCameraTips = true,
	BlenderAxes = false,
	MoveSnapIncrement = 1,
	RotationSnapIncrement = 5,
	GizmoDistance = 2.5,
	VFXFollowsFPS = true,
	SoftIKPercent = 90,
	GraphClamp = 2,
	GraphCompressionPercent = 10,
	GraphAutoSmoothing = true,
	OpenAutomatically = false,
	BlenderCameraBeta = false,
	DisableCameraWASD = false,
	DisableCameraQE = false,
	MasterKeyframes = false,
	FlatBoneList = false,
	BlenderPanSensitivity = 1,
	BlenderOrbitSensitivity = 1,
	BlenderZoomToMouse = false,
	R6BendPercent = 65,
	IKFeetPlanted = true,
	R6IKLegPole = true,
	R15PoleFollowsIK = false,
	ContinuousTimeline = false,
	HideOriginBone = false,
	OriginAlwaysShowing = false,
	CamTargetParentButton = false,
	ImagePreviewerNativeImageScale = true,
	TransformChannels = false,
	ColorKeysByInterpolation = false,
	UsePreviousEasing = false,
	VFXScrubberPreview = true,
	VFXPausePreview = true,
	ShowFKIK = true,
	ShowHeadStabilizer = true,
	EventsByDefault = true,
	FacesByDefault = false,
	ShowMotionPaths = true,
	MotionPathNumbers = 1,
	MotionPathRange = 1,
	MotionPathEachSide = 4,
	MotionPathStart = 0,
	MotionPathEnd = 60,
	MotionPathEditing = true,
	ScaleGizmo = true,
	TopbarShape = 1,
})
local values = table.clone(DEFAULTS)
local stored = {}
local listeners = {}
local initialized = false
local missingReads = 0
local writeSetting

local function normalize(key, value)
	if DEFAULTS[key] == nil then
		return nil
	end

	if
		key == "GreenScreenColor"
		or key == "OnionSkinColor"
		or key == "PoseGhostPreviousColor"
		or key == "PoseGhostNextColor"
	then
		if typeof(value) == "Color3" then
			for _, channel in { value.R, value.G, value.B } do
				if channel ~= channel or channel < 0 or channel > 1 then
					return nil
				end
			end

			return value:ToHex():upper()
		end

		if type(value) ~= "string" then
			return nil
		end

		local hex = value:gsub("^#", "")
		return #hex == 6 and hex:match("^%x+$") and hex:upper() or nil
	end

	if key == "DefaultRotationMode" then
		return table.find({ "Quaternion", "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX" }, value)
				and value
			or nil
	end

	if key == "NavigationGizmoX" or key == "NavigationGizmoY" then
		local n = tonumber(value)
		return n and n == n and math.abs(n) < math.huge and math.clamp(n, 0, 1) or nil
	end

	if key == "GifPlayback" then
		local number = tonumber(value)
		return if number == 1 or number == 2 or number == 3 then number else nil
	end

	if key == "MotionPathEachSide" then
		local n = tonumber(value)
		return n and n == n and math.abs(n) < math.huge and math.clamp(math.floor(n + 0.5), 1, 1000)
			or nil
	end

	if key == "MotionPathStart" or key == "MotionPathEnd" then
		local n = tonumber(value)
		return n
				and n == n
				and math.abs(n) < math.huge
				and math.clamp(math.floor(n + 0.5), 0, 144000)
			or nil
	end

	if key == "MotionPathRange" then
		local n = tonumber(value)
		return n and n >= 1 and n <= 4 and n % 1 == 0 and n or nil
	end

	if key == "MotionPathNumbers" then
		local number = tonumber(value)
		return if number == 1 or number == 2 or number == 3 then number else nil
	end

	if key == "BoneStyle" then
		local number = tonumber(value)
		return if number == 1 or number == 2 then number else nil
	end

	if key == "TopbarShape" then
		local number = tonumber(value)
		return if number == 1 or number == 2 or number == 3 then number else nil
	end

	if key == "GraphClamp" or key == "GraphCompressionPercent" then
		local number = tonumber(value)
		local maximum = key == "GraphClamp" and 1000 or 100
		if not number or number ~= number or number < 0.01 or number > maximum then
			return nil
		end

		return math.floor(number * 100 + 0.5) / 100
	end

	if key == "DefaultAxisSpace" then
		local n = tonumber(value)
		return (n == 0 or n == 1 or n == 2) and n or nil
	end

	if key == "PositionAxisSpace" or key == "RotationAxisSpace" then
		local n = tonumber(value)
		return (n == 1 or n == 2) and n or nil
	end

	if key == "RotationTrackballSize" or key == "TimelineScrollSensitivity" then
		local n = tonumber(value)
		if not n or n ~= n or math.abs(n) == math.huge then
			return nil
		end

		return math.floor(
			math.clamp(
				n,
				key == "RotationTrackballSize" and 1 or 0.01,
				key == "RotationTrackballSize" and 100 or 10
			)
					* 100
				+ 0.5
		) / 100
	end

	if
		key == "OnionSkinTransparency"
		or key == "PoseGhostTransparency"
		or key == "FullBoneTransparency"
		or key == "HandleBoneTransparency"
		or key == "CustomBoneTransparency"
		or key == "ArmatureBoneTransparency"
		or key == "CameraPreviewMaskOpacity"
	then
		local n = tonumber(value)
		if not n or n ~= n or math.abs(n) == math.huge then
			return nil
		end

		return math.floor(math.clamp(n, 0, 100) * 100 + 0.5) / 100
	end

	if key == "BoneSelectionRadius" then
		local n = tonumber(value)
		if not n or n ~= n or math.abs(n) == math.huge then
			return nil
		end

		return math.clamp(math.floor(n + 0.5), 2, 32)
	end

	if key == "RotationGrabCircleSize" then
		local number = tonumber(value)
		if not number or number ~= number or math.abs(number) == math.huge then
			return nil
		end

		return math.clamp(math.floor(number + 0.5), 4, 64)
	end

	if key == "CameraPreviewFPS" then
		local number = tonumber(value)
		if not number or number ~= number or math.abs(number) == math.huge then
			return nil
		end

		if number == 0 then
			return 0
		end

		return math.clamp(math.floor(number + 0.5), 5, 240)
	end

	if key == "RotationSnapIncrement" then
		local number = tonumber(value)
		if not number or number ~= number or number < 0.001 or number > 360 then
			return nil
		end

		return number
	end

	if key == "MoveSnapIncrement" then
		local number = tonumber(value)
		if not number or number ~= number or number < 0.001 or number > 1000 then
			return nil
		end

		return number
	end

	if
		key == "TrackballSensitivity"
		or key == "BlenderGrabSensitivity"
		or key == "BlenderRotateSensitivity"
		or key == "BlenderTrackballSensitivity"
	then
		local number = tonumber(value)
		if not number or number ~= number or math.abs(number) == math.huge then
			return nil
		end

		return math.floor(math.clamp(number, 0.01, 5) * 100 + 0.5) / 100
	end

	if key == "PositionGizmoThickness" then
		local number = tonumber(value)
		if not number or number ~= number or math.abs(number) == math.huge then
			return nil
		end

		return math.floor(math.clamp(number, 0.5, 4) * 100 + 0.5) / 100
	end

	if key == "GizmoSize" or key == "GizmoDistance" then
		local number = tonumber(value)
		if not number or number ~= number or math.abs(number) == math.huge then
			return nil
		end

		number = math.clamp(number, 0.1, key == "GizmoDistance" and 5 or 2)
		return math.floor(number * 100 + 0.5) / 100
	end

	if key == "BlenderPanSensitivity" or key == "BlenderOrbitSensitivity" then
		local number = tonumber(value)
		return number and number == number and math.clamp(number, 0.1, 5) or DEFAULTS[key]
	end

	if key == "R6BendPercent" then
		local number = tonumber(value)
		return number and number == number and math.clamp(number, 0, 100) or DEFAULTS[key]
	end

	if key == "SoftIKPercent" or key == "GreasePencilSmoothing" then
		local number = tonumber(value)
		if
			not number
			or number ~= number
			or math.abs(number) == math.huge
			or number < 0
			or number > 100
		then
			return nil
		end

		return math.floor(number * 10 + 0.5) / 10
	end

	if
		key == "FrameStep"
		or key == "AltScrollFrameStep"
		or key == "KeyframeJumpStep"
		or key == "DefaultFPS"
		or key == "DefaultTrackLength"
	then
		local number = tonumber(value)
		if not number or number ~= number or math.abs(number) == math.huge then
			return nil
		end

		number = math.floor(number + 0.5)
		local maximum = key == "DefaultFPS" and 1000 or 1000000
		if number < 1 or number > maximum then
			return nil
		end

		return number
	end

	if type(value) == "boolean" then
		return value
	end

	return nil
end

local function notify(key, value, previous)
	local pending = table.clone(listeners)
	for connection, callback in pending do
		if listeners[connection] == callback then
			local ok, err = pcall(callback, key, value, previous)
			if not ok then
				warn("Eclipse preferences: " .. tostring(err))
			end
		end
	end
end

function Preferences.init(refs)
	if initialized then
		return
	end

	initialized = true
	refs = refs or {}
	writeSetting = refs.SetSetting
	local ok, saved = pcall(function()
		return refs.GetSetting and refs.GetSetting(SETTING_KEY)
	end)
	if ok and type(saved) == "string" and saved ~= "" then
		ok, saved = pcall(HttpService.JSONDecode, HttpService, saved)
	end

	if ok and saved == nil and refs.CanRetry then
		missingReads += 1
		task.delay(missingReads <= 5 and 1 or 30, function()
			if not refs.CanRetry() then
				return
			end

			initialized = false
			Preferences.init(refs)
		end)
	end

	if not ok then
		task.delay(1, function()
			if refs.CanRetry and not refs.CanRetry() then
				return
			end

			initialized = false
			Preferences.init(refs)
		end)
		return
	end

	if
		saved ~= nil
		and (
			type(saved) ~= "table"
			or saved.values ~= nil and type(saved.values) ~= "table"
			or saved.version ~= nil and saved.version ~= 1
		)
	then
		writeSetting = nil
		warn(
			"Eclipse preferences could not be read. Saved preferences were retained; reopen Eclipse to retry."
		)
		return
	end

	if ok and type(saved) == "table" then
		stored = table.clone(saved)
		local preferences = type(saved.values) == "table" and saved.values or saved

		local oldShape = normalize("TopbarShape", preferences.TopbarShape)
		if saved.topbarShapeVersion == nil and oldShape ~= nil then
			preferences = table.clone(preferences)
			preferences.TopbarShape = 4 - oldShape
			stored.values = preferences
			stored.topbarShapeVersion = TOPBAR_SHAPE_VERSION
			if writeSetting then
				local migrated, err = pcall(function()
					writeSetting(SETTING_KEY, HttpService:JSONEncode(stored))
				end)
				if not migrated then
					warn("Eclipse preferences could not be saved: " .. tostring(err))
				end
			end
		end

		if preferences.BoneStyle == nil then
			preferences = table.clone(preferences)
			preferences.BoneStyle = preferences.PartHandles == true
					and preferences.FullPartHandles ~= true
					and 2
				or 1
		end

		if saved.cameraControlsVersion ~= 2 then
			preferences = table.clone(preferences)
			local pan = tonumber(preferences.BlenderPanSensitivity)
			preferences.BlenderPanSensitivity = if not pan
					or pan == 1.5
					or pan == 3.5
				then 1
				else pan / 3.5
			stored.values = preferences
			stored.cameraControlsVersion = 2
			if writeSetting then
				pcall(writeSetting, SETTING_KEY, HttpService:JSONEncode(stored))
			end
		end

		if saved.ikDefaultsVersion ~= 2 and preferences.R6BendPercent == 74.2 then
			preferences = table.clone(preferences)
			preferences.R6BendPercent = 65
		end

		if preferences.VFXPausePreview == nil then
			preferences = table.clone(preferences)
			preferences.VFXPausePreview = preferences.VFXScrubberPreview ~= false
		end

		if saved.rotationGrabSizeVersion ~= 2 then
			preferences = table.clone(preferences)
			local previousSize =
				normalize("RotationGrabCircleSize", preferences.RotationGrabCircleSize)
			if
				previousSize == 14
				or saved.rotationGrabSizeVersion == nil and previousSize == 12
			then
				preferences.RotationGrabCircleSize = DEFAULTS.RotationGrabCircleSize
			end

			stored.values = preferences
			stored.rotationGrabSizeVersion = 2
			if writeSetting then
				pcall(writeSetting, SETTING_KEY, HttpService:JSONEncode(stored))
			end
		end

		if saved.rotationHandleLayoutVersion ~= 1 then
			preferences = table.clone(preferences)
			preferences.MatchRotationHandles = false
			stored.values = preferences
			stored.rotationHandleLayoutVersion = 1
			if writeSetting then
				local migrated, err =
					pcall(writeSetting, SETTING_KEY, HttpService:JSONEncode(stored))
				if not migrated then
					warn("Eclipse preferences could not be saved: " .. tostring(err))
				end
			end
		end

		if saved.cameraPreviewRateVersion ~= 1 then
			preferences = table.clone(preferences)
			if
				preferences.CameraPreviewFPS == nil
				or tonumber(preferences.CameraPreviewFPS) == 30
			then
				preferences.CameraPreviewFPS = 0
			end

			stored.values = preferences
			stored.cameraPreviewRateVersion = 1
			if writeSetting then
				pcall(writeSetting, SETTING_KEY, HttpService:JSONEncode(stored))
			end
		end

		if preferences.BlenderTrackballSensitivity == nil then
			local previousPreferences = preferences
			preferences = table.clone(preferences)
			preferences.BlenderTrackballSensitivity = normalize(
				"TrackballSensitivity",
				preferences.TrackballSensitivity
			) or 1
			stored.values = preferences
			if writeSetting then
				pcall(
					writeSetting,
					SETTING_KEY,
					HttpService:JSONEncode(stored),
					HttpService:JSONEncode({ values = previousPreferences })
				)
			end
		end

		if saved.transformReadoutVersion ~= 1 then
			preferences = table.clone(preferences)
			preferences.ShowTransformReadout = false
			stored.values = preferences
			stored.transformReadoutVersion = 1
			if writeSetting then
				local migrated, err =
					pcall(writeSetting, SETTING_KEY, HttpService:JSONEncode(stored))
				if not migrated then
					warn("Eclipse preferences could not be saved: " .. tostring(err))
				end
			end
		end

		local defaultSpace = normalize("DefaultAxisSpace", preferences.DefaultAxisSpace)
		if defaultSpace == 1 or defaultSpace == 2 then
			preferences = table.clone(preferences)
			preferences.PositionAxisSpace = defaultSpace
			preferences.RotationAxisSpace = defaultSpace
		end

		for key in DEFAULTS do
			local value = normalize(key, preferences[key])
			if value ~= nil then
				local previous = values[key]
				values[key] = value
				if previous ~= value then
					notify(key, value, previous)
				end
			end
		end
	end
end

function Preferences.unavailableReason(key)
	return UNAVAILABLE[key]
end

function Preferences.get(key)
	if UNAVAILABLE[key] then return false end
	return values[key]
end

function Preferences.color(key)
	return Color3.fromHex(values[key])
end

function Preferences.defaults()
	local defaults = table.clone(DEFAULTS)
	for key in UNAVAILABLE do defaults[key] = false end
	return defaults
end

function Preferences.setMany(changes)
	for key, value in changes do
		if UNAVAILABLE[key] and value ~= false then return false end
	end
	changes = table.clone(changes)
	for key in UNAVAILABLE do changes[key] = nil end
	local defaultSpace = normalize("DefaultAxisSpace", changes.DefaultAxisSpace)
	if defaultSpace == 1 or defaultSpace == 2 then
		changes = table.clone(changes)
		changes.PositionAxisSpace = defaultSpace
		changes.RotationAxisSpace = defaultSpace
	end

	if changes.MotionPathStart ~= nil or changes.MotionPathEnd ~= nil then
		local first = normalize(
			"MotionPathStart",
			changes.MotionPathStart ~= nil and changes.MotionPathStart or values.MotionPathStart
		)
		local last = normalize(
			"MotionPathEnd",
			changes.MotionPathEnd ~= nil and changes.MotionPathEnd or values.MotionPathEnd
		)
		if first == nil or last == nil then
			return false
		end

		if first > last then
			if changes.MotionPathEnd == nil then
				last = first
			elseif changes.MotionPathStart == nil then
				first = last
			else
				first, last = last, first
			end
		end

		changes = table.clone(changes)
		changes.MotionPathStart, changes.MotionPathEnd = first, last
	end

	local nextValues = table.clone(values)
	local changed = {}
	for key, value in changes do
		local normalized = normalize(key, value)
		if normalized == nil then
			return false
		end

		if normalized ~= values[key] then
			nextValues[key] = normalized
			changed[key] = values[key]
		end
	end

	if not next(changed) then
		return true
	end

	if not initialized or not writeSetting then
		return false
	end

	local nextStored = table.clone(stored)
	nextStored.version = 1
	nextStored.transformReadoutVersion = 1
	nextStored.cameraPreviewRateVersion = 1
	nextStored.ikDefaultsVersion = 2
	nextStored.rotationGrabSizeVersion = 2
	nextStored.rotationHandleLayoutVersion = 1
	nextStored.cameraControlsVersion = 2
	nextStored.topbarShapeVersion = TOPBAR_SHAPE_VERSION
	local savedValues = type(stored.values) == "table" and table.clone(stored.values) or {}
	for name, preference in nextValues do
		savedValues[name] = preference
	end

	nextStored.values = savedValues
	local ok, err = pcall(function()
		writeSetting(
			SETTING_KEY,
			HttpService:JSONEncode(nextStored),
			HttpService:JSONEncode({ values = values })
		)
	end)
	if not ok then
		warn("Eclipse preferences could not be saved: " .. tostring(err))
		return false
	end

	stored = nextStored
	values = nextValues
	for key, previous in changed do
		notify(key, values[key], previous)
	end

	return true
end

function Preferences.set(key, value)
	if normalize(key, value) == nil then
		return false, Preferences.get(key)
	end

	local ok = Preferences.setMany({ [key] = value })
	return ok, Preferences.get(key)
end

function Preferences.subscribe(callback)
	assert(type(callback) == "function", "Preference subscriber must be a function")
	local connection = {}
	listeners[connection] = callback
	return function()
		listeners[connection] = nil
	end
end

function Preferences.axisName(native)
	if values.BlenderAxes then
		return native == "Y" and "Z" or native == "Z" and "Y" or native
	end

	return native
end

function Preferences.axisSign(native)
	return values.BlenderAxes and native == "Z" and -1 or 1
end

function Preferences.axisLabel(native, unsigned)
	return (not unsigned and Preferences.axisSign(native) < 0 and "-" or "")
		.. Preferences.axisName(native)
end

function Preferences.axisVector(display)
	local native = Preferences.axisName(display)
	return (native == "X" and Vector3.xAxis or native == "Y" and Vector3.yAxis or Vector3.zAxis)
		* Preferences.axisSign(native),
		native
end

function Preferences.axisColor(native, palette)
	return palette[Preferences.axisName(native)]
end

function Preferences.timelineScrollSpeed()
	local sensitivity = values.TimelineScrollSensitivity
	if sensitivity >= 1 then
		return sensitivity * 2
	end

	return 0.01 * 200 ^ ((sensitivity - 0.01) / 0.99)
end

return Preferences
