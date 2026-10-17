--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Motion = require("Motion")
local Theme = require("Theme")
local KeyColors = require("KeyColors")
local KeyGroups = require("KeyGroups")
local Properties = require("Properties")
local BlenderEdit = require("BlenderEdit")
local CameraRig = require("CameraRig")
local KeyframePolicy = require("Policy")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("RawState")
local motionPath = require("motionPath")
local MainState = require("State")
local MotorMath = require("MotorMath")
local KeyframeMenu = require("KeyframeMenu")
local Assets = require("AssetIds")
local Defaults = require("Defaults")
local GraphCurves = require("GraphCurves")
local KeyframeDefaults = require("KeyframeDefaults")
local Parenting = require("Parenting")
local TimelineState = State.Timeline
local TimelineConfig = State.Config
local PlayheadDrag = State.PlayheadDrag
local KeyframeDrag = State.KeyframeDrag
local SelectionState = State.Selection
local KeyframeTransform = State.KeyframeTransform
local KEYFRAME_SELECTED_COLOR = State.Colors.KEYFRAME_SELECTED_COLOR
local KEYFRAME_HANDLE_DEFAULT = State.Colors.KEYFRAME_HANDLE_DEFAULT
local KEYFRAME_HANDLE_HOVER = State.Colors.KEYFRAME_HANDLE_HOVER
local KEYFRAME_SHAPES = Assets.KeyframeShapes
local FALLBACK_HANDLE = "Automatic"

local CHANNEL_KF_PREFIX = "ChannelKF_"

local DOUBLE_CLICK_THRESHOLD = 0.3
local lastClickTime = 0
local lastClickKey = nil
local selectionAtFirstClick = nil
local buttonKeys = setmetatable({}, { __mode = "k" })
local channelButtons = setmetatable({}, { __mode = "k" })
local hoverButton

local R6Controls = require("R6Controls")

local function resolveKeyframeShape(keyData, motorOverride)
	if keyData then
		if keyData.HeadFollow or keyData.HS then
			return KEYFRAME_SHAPES.HeadFollow
		end

		if keyData.IK then
			return KEYFRAME_SHAPES.IK
		end
	end

	local motor = motorOverride or (keyData and keyData.Motor)
	if motor and motor.Part1 and R6Controls.isControl(motor.Part1) then
		return KEYFRAME_SHAPES.IK
	end

	if
		motor
		and not Parenting.keyIsParented(motor, keyData, TimelineState.ParentingDefaults[motor])
	then
		return KEYFRAME_SHAPES.Unparented
	end

	return KEYFRAME_SHAPES.Default
end

local function normalizeHandleName(name)
	if type(name) ~= "string" then
		return nil
	end

	local stripped = string.gsub(name, "%s+", "")
	if KEYFRAME_HANDLE_DEFAULT[stripped] then
		return stripped
	end

	return nil
end

local function resolveHandleType(keyData)
	local own = keyData and normalizeHandleName(keyData.HandleType)
	if own then
		return own
	end

	return normalizeHandleName(Defaults.HandleType) or FALLBACK_HANDLE
end

local CHANNEL_IDS = {
	"loc_x",
	"loc_y",
	"loc_z",
	"qrot_w",
	"qrot_x",
	"qrot_y",
	"qrot_z",
	"scale_x",
	"scale_y",
	"scale_z",
}

local function cframeToQuaternion(cf)
	local _, _, _, m11, m12, m13, m21, m22, m23, m31, m32, m33 = cf:GetComponents()
	local trace = m11 + m22 + m33
	local w, x, y, z

	if trace > 0 then
		local s = math.sqrt(trace + 1.0) * 2
		w = 0.25 * s
		x = (m32 - m23) / s
		y = (m13 - m31) / s
		z = (m21 - m12) / s
	elseif m11 > m22 and m11 > m33 then
		local s = math.sqrt(1.0 + m11 - m22 - m33) * 2
		w = (m32 - m23) / s
		x = 0.25 * s
		y = (m12 + m21) / s
		z = (m13 + m31) / s
	elseif m22 > m33 then
		local s = math.sqrt(1.0 + m22 - m11 - m33) * 2
		w = (m13 - m31) / s
		x = (m12 + m21) / s
		y = 0.25 * s
		z = (m23 + m32) / s
	else
		local s = math.sqrt(1.0 + m33 - m11 - m22) * 2
		w = (m21 - m12) / s
		x = (m13 + m31) / s
		y = (m23 + m32) / s
		z = 0.25 * s
	end

	return w, x, y, z
end

local function quaternionToCFrame(qw, qx, qy, qz, px, py, pz)
	local mag = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
	if mag > 0 then
		qw, qx, qy, qz = qw / mag, qx / mag, qy / mag, qz / mag
	else
		qw = 1
	end

	local r11 = 1 - 2 * (qy * qy + qz * qz)
	local r12 = 2 * (qx * qy - qz * qw)
	local r13 = 2 * (qx * qz + qy * qw)
	local r21 = 2 * (qx * qy + qz * qw)
	local r22 = 1 - 2 * (qx * qx + qz * qz)
	local r23 = 2 * (qy * qz - qx * qw)
	local r31 = 2 * (qx * qz - qy * qw)
	local r32 = 2 * (qy * qz + qx * qw)
	local r33 = 1 - 2 * (qx * qx + qy * qy)

	return CFrame.new(px, py, pz, r11, r12, r13, r21, r22, r23, r31, r32, r33)
end

local function decomposeC0(cframe)
	local pos = cframe.Position
	local qw, qx, qy, qz = cframeToQuaternion(cframe)
	return {
		loc_x = pos.X,
		loc_y = pos.Y,
		loc_z = pos.Z,
		qrot_w = qw,
		qrot_x = qx,
		qrot_y = qy,
		qrot_z = qz,
		scale_x = 1,
		scale_y = 1,
		scale_z = 1,
	}
end

local function reconstructC0(values)
	return quaternionToCFrame(
		values.qrot_w or 1,
		values.qrot_x or 0,
		values.qrot_y or 0,
		values.qrot_z or 0,
		values.loc_x or 0,
		values.loc_y or 0,
		values.loc_z or 0
	)
end

return function(Timeline)
	function Timeline:InitializeRotationModeForRig(rig)
		local mode = require("Preferences").get("DefaultRotationMode")
		if not GraphCurves.validRotationOrder(mode) then
			return
		end

		for _, motor in Parenting.collectMotors(rig) do
			if
				Properties.is(motor)
				or CameraRig.isFov(motor)
				or require("Target").isAttachment(motor)
			then
				continue
			end

			local bucket = self:GetMotorKeyframeBucket(motor)
			if not bucket then
				continue
			end

			local authored = false
			for frame in bucket do
				if frame ~= 0 then
					authored = true
					break
				end
			end

			if authored then
				continue
			end

			local key = bucket[0]
			if key and (key.GraphCurves or key.GraphOnly) then
				continue
			end

			local rest = TimelineState.DefaultPose[motor] or motor.C0
			key = key or KeyframeDefaults.new(bucket, 0)
			key.C0, key.Position, key.Rotation = rest, rest.Position, rest.Rotation
			key.Frame, key.Time, key.Motor, key.Part = 0, 0, motor, motor.Part1
			key.Parented = TimelineState.ParentingDefaults[motor] ~= false
			if not key.Parented then
				key.WorldCFrame = TimelineState.DefaultWorldPose[motor]
			end

			local values = { GraphCurves.euler(rest, mode) }
			key.GraphCurves = {}
			for i, id in { "rot_x", "rot_y", "rot_z" } do
				local p = GraphCurves.newPoint(key, id)
				p.Value = values[i]
				p.RotationOrder = mode
				key.GraphCurves[id] = p
			end

			bucket[0] = key
			GraphCurves.invalidate(bucket)
		end
	end

	function Timeline:DecomposeC0(cframe)
		return decomposeC0(cframe)
	end

	function Timeline:ReconstructC0(values)
		return reconstructC0(values)
	end

	function Timeline:GetChannelIds()
		return CHANNEL_IDS
	end

	function Timeline:EnsureChannelsPopulated(keyData)
		if not keyData then
			return
		end

		if Properties.is(keyData.Motor) then
			return
		end

		if keyData.Channels ~= nil then
			return
		end

		if keyData.GraphOnly then
			keyData.Channels = {}
			return
		end

		if not keyData.C0 then
			return
		end

		local decomposed = decomposeC0(keyData.C0)
		const whole = keyData.WholePoseScale or {}
		keyData.Channels = {}
		for _, id in ipairs(CHANNEL_IDS) do
			if not KeyframePolicy.channelAvailable(keyData.Motor, id) then
				continue
			end

			keyData.Channels[id] = {
				Value = if typeof(whole[id]) == "number" then whole[id] else decomposed[id],
			}
		end
	end

	function Timeline:RefreshAllTimelineKeyframePositions()
		local positions = {}

		local function position(button, frame)
			local value = positions[frame]
			if not value then
				value = UDim2.new(0, self:FrameToVisibleX(frame), 0.5, 0)
				positions[frame] = value
			end

			if button.Position ~= value then
				button.Position = value
			end
		end

		for button, key in buttonKeys do
			if not button.Parent then
				buttonKeys[button] = nil
				continue
			end

			if key.Button == button then
				position(button, key.Frame)
			end
		end

		for button, entry in channelButtons do
			if not button.Parent then
				channelButtons[button] = nil
				continue
			end

			position(button, tonumber(string.match(button.Name, "^ChannelKF_(.+)$")) or entry.frame)
		end

		if self.RefreshIKEndMarkerPositions then
			self:RefreshIKEndMarkerPositions()
		end
	end

	function Timeline:GetNearestKeyframeFrameForMotor(motor, fromFrame, direction)
		if not motor then
			return nil
		end

		local frames = self:GetSortedMotorKeyframes(motor)
		if not frames or #frames == 0 then
			return nil
		end

		if direction == "Left" then
			local best = nil

			for _, frame in ipairs(frames) do
				if frame < fromFrame then
					best = frame
				else
					break
				end
			end

			return best
		elseif direction == "Right" then
			for _, frame in ipairs(frames) do
				if frame > fromFrame then
					return frame
				end
			end
		end

		return nil
	end

	function Timeline:GetKeyframeImageObject(keyBtn)
		if not keyBtn then
			return nil
		end

		if keyBtn:IsA("ImageButton") or keyBtn:IsA("ImageLabel") then
			return keyBtn
		end

		return keyBtn:FindFirstChildWhichIsA("ImageLabel")
			or keyBtn:FindFirstChildWhichIsA("ImageButton")
	end

	function Timeline:GetKeyframeAppearance(key, lane)
		return {
			Image = resolveKeyframeShape(key, key.Motor),
			ImageColor3 = KeyframePolicy.isDisabled(key, lane) and Color3.fromRGB(100, 106, 108)
				or KeyColors.get(key, lane) or KEYFRAME_HANDLE_DEFAULT[resolveHandleType(key)],
		}
	end

	local function keyTransparency(image, key, selected, hovered)
		local names = {
			Automatic = "KfAuto",
			Aligned = "KfAli",
			AutoClamped = "KfAC",
			Vector = "KfVec",
			Free = "KfFree",
		}
		local override = Theme.getOverride(
			selected and "KfS" or hovered and "KfH" or names[resolveHandleType(key)] or "KfD"
		)
		if not override or override.t == nil then
			override = Theme.getOverride("KfD")
		end

		if image:GetAttribute("EclipseKeyOpacity") == nil then
			image:SetAttribute("EclipseKeyOpacity", image.ImageTransparency)
		end

		image.ImageTransparency = override and override.t or image:GetAttribute("EclipseKeyOpacity")
	end

	function Timeline:ApplyKeyframeVisualState(
		keyData,
		buttonOverride,
		shapeOverride,
		colorOverride,
		hoverOverride
	)
		if not keyData or not (buttonOverride or keyData.Button) then
			return
		end

		local keyBtn = buttonOverride or keyData.Button

		keyBtn.ZIndex = 10 + math.max(0, math.floor(keyData.Frame or 0))
		local imageObj = self:GetKeyframeImageObject(keyBtn)

		local isSelected = self:IsKeyframeSelected(keyData)
			or TimelineState.SelectedKeyframe == keyData
			or self:HasAnyChannelSelectedForKeyData(keyData)
		local isHovered = KeyframeDrag.hoveringKeyframe == keyData
		local isDragging = KeyframeDrag.draggingKeyframe
			and (
				KeyframeDrag.draggingKeyframe.KeyData == keyData
				or KeyframeDrag.draggingKeyframe.SummaryScope
					and KeyframeDrag.groupDragOriginals[keyData] ~= nil
			)

		if imageObj then
			keyTransparency(imageObj, keyData, isSelected or isDragging, isHovered)
			local motor = keyData.Motor
			imageObj.Image = shapeOverride or resolveKeyframeShape(keyData, motor)
			if KeyframePolicy.isDisabled(keyData) then
				imageObj.ImageColor3 = (isSelected or isDragging)
						and State.Colors.KEYFRAME_SELECTED_COLOR:Lerp(
							Color3.fromRGB(100, 106, 108),
							0.4
						)
					or Color3.fromRGB(100, 106, 108)
			elseif isSelected or isDragging then
				imageObj.ImageColor3 = State.Colors.KEYFRAME_SELECTED_COLOR
			else
				local handleType = resolveHandleType(keyData)
				if isHovered then
					imageObj.ImageColor3 = hoverOverride or KeyColors.get(keyData, nil, true) or KEYFRAME_HANDLE_HOVER[handleType]
				else
					imageObj.ImageColor3 = colorOverride or KeyColors.get(keyData) or KEYFRAME_HANDLE_DEFAULT[handleType]
				end
			end
		end

		if isDragging then
			keyBtn.Size = UDim2.new(0, 22, 0, 22)
		elseif isSelected then
			keyBtn.Size = UDim2.new(0, 18, 0, 18)
		else
			keyBtn.Size = UDim2.new(0, 16, 0, 16)
		end
	end

	const snapshotRuntimeFields = { Button = true }

	local function copySnapshotField(value, budget, seen)
		if type(value) ~= "table" then
			return value
		end

		seen = seen or {}
		if seen[value] then
			return seen[value]
		end

		if budget then
			budget()
		end

		const out = {}
		seen[value] = out
		for key, item in value do
			out[key] = copySnapshotField(item, budget, seen)
		end

		return out
	end

	local function copyRemainingFields(source, target, budget)
		for field, value in source do
			if
				target[field] == nil
				and type(field) == "string"
				and not snapshotRuntimeFields[field]
				and string.byte(field, 1) ~= 95
			then
				target[field] = copySnapshotField(value, budget)
			end
		end

		return target
	end

	function Timeline:_snapshotMotorBucket(motor, budget, onlyFrame)
		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return {}
		end

		local snap = {}
		for frame, kd in pairs(onlyFrame ~= nil and { [onlyFrame] = bucket[onlyFrame] } or bucket) do
			if budget then
				budget()
			end

			if type(kd) == "table" then
				local channelsCopy = nil
				if kd.Channels then
					channelsCopy = {}
					for chId, ch in pairs(kd.Channels) do
						if type(ch) == "table" then
							channelsCopy[chId] = GraphCurves.clone(ch)
						end
					end
				end

				local bezCopy = nil
				if kd.BezierPoints then
					bezCopy = {
						kd.BezierPoints[1],
						kd.BezierPoints[2],
						kd.BezierPoints[3],
						kd.BezierPoints[4],
					}
				end

				snap[frame] = {
					Frame = frame,
					Time = kd.Time,
					Disabled = kd.Disabled,
					KeyGroups = KeyGroups.clone(kd.KeyGroups),
					WholePoseScale = GraphCurves.clone(kd.WholePoseScale),
					PhysicsLead = GraphCurves.clone(kd.PhysicsLead),
					PhysicsTail = kd.PhysicsTail,
					ChannelPoseC0 = kd.ChannelPoseC0,
					BlenderCurve = GraphCurves.clone(kd.BlenderCurve, budget),
					BlenderSource = kd.BlenderSource,
					C0 = kd.C0,
					PropertyValue = kd.PropertyValue,
					Position = kd.Position,
					Rotation = kd.Rotation,
					WorldCFrame = kd.WorldCFrame,
					MasterWorld = kd.MasterWorld,
					Parented = kd.Parented,
					PathTangentIn = kd.PathTangentIn,
					PathTangentOut = kd.PathTangentOut,
					HeadFollow = kd.HeadFollow,
					HS = kd.HS,
					HSRestoreParented = kd.HSRestoreParented,
					HSRotation = kd.HSRotation,
					HSLocalRotation = kd.HSLocalRotation,
					IK = kd.IK,
					IKTarget = kd.IKTarget,
					IKPole = kd.IKPole,
					IKBaseC0 = kd.IKBaseC0,
					IKBaseWorld = kd.IKBaseWorld,
					IKAnchor = kd.IKAnchor,
					IKRigWorld = kd.IKRigWorld,
					CamTrackTo = kd.CamTrackTo,
					CamTargetEnabled = kd.CamTargetEnabled,
					CamAttachTarget = require("GraphCurves").clone(kd.CamAttachTarget),
					FovFollowAnchor = kd.FovFollowAnchor,
					CamTargetParent = kd.CamTargetParent,
					CamTargetAnchor = kd.CamTargetAnchor,
					IKRoot = kd.IKRoot,
					IKPoleFollowsTarget = kd.IKPoleFollowsTarget,
					IKRestoreParented = kd.IKRestoreParented,
					Motor = kd.Motor,
					Part = kd.Part,
					SanitizeName = kd.SanitizeName,
					Template = kd.Template,
					HandleType = kd.HandleType,
					EasingStyle = kd.EasingStyle,
					QuaternionInterpolationVersion = kd.QuaternionInterpolationVersion,
					EasingDirection = kd.EasingDirection,
					BezierPoints = bezCopy,
					Overshoot = kd.Overshoot,
					Amplitude = kd.Amplitude,
					Period = kd.Period,
					MoonEasing = kd.MoonEasing,
					Channels = channelsCopy,
					GraphOnly = kd.GraphOnly,
					GraphCurves = GraphCurves.clone(kd.GraphCurves),
				}
				copyRemainingFields(kd, snap[frame], budget)
			end
		end

		return snap
	end

	function Timeline:_applyLiveKeyPatch(motor, patch, targetBucket)
		local bucket = targetBucket or self:GetMotorKeyframeBucket(motor)
		if not bucket then
			return
		end

		for frame, value in patch do
			local old = bucket[frame]
			if old then
				if old.Button then
					old.Button:Destroy()
					old.Button = nil
				end

				if TimelineState.SelectedKeyframes then
					local selected = TimelineState.SelectedKeyframes[old]
					TimelineState.SelectedKeyframes[old] = nil
					if value and selected then
						TimelineState.SelectedKeyframes[value] = selected
					end
				end

				if TimelineState.SelectedChannelKeyframes then
					local selected = TimelineState.SelectedChannelKeyframes[old]
					TimelineState.SelectedChannelKeyframes[old] = nil
					if value and selected then
						TimelineState.SelectedChannelKeyframes[value] = selected
					end
				end

				if TimelineState.SelectedKeyframe == old then
					TimelineState.SelectedKeyframe = value or nil
				end
			end

			bucket[frame] = value or nil
		end

		GraphCurves.invalidate(bucket)
		TimelineState._motorUniform[motor] = nil
		TimelineState._motorHasScale[motor] = nil
		motionPath.markDirty()
	end

	function Timeline:_restoreMotorBucket(motor, snap, deferVisuals, budget)
		local bucket = self:GetMotorKeyframeBucket(motor)
		if not bucket then
			return
		end

		local replacement = {}
		for frame, entry in pairs(snap) do
			if budget then
				budget()
			end

			local newKd = {
				Frame = frame,
				Time = frame / TimelineState.FPS,
				Disabled = entry.Disabled,
				KeyGroups = KeyGroups.clone(entry.KeyGroups),
				WholePoseScale = GraphCurves.clone(entry.WholePoseScale),
				PhysicsLead = GraphCurves.clone(entry.PhysicsLead),
				PhysicsTail = entry.PhysicsTail,
				ChannelPoseC0 = entry.ChannelPoseC0,
				BlenderCurve = GraphCurves.clone(entry.BlenderCurve, budget),
				BlenderSource = entry.BlenderSource,
				C0 = entry.C0,
				PropertyValue = entry.PropertyValue,
				Position = entry.Position,
				Rotation = entry.Rotation,
				WorldCFrame = entry.WorldCFrame,
				MasterWorld = entry.MasterWorld,
				Parented = entry.Parented,
				PathTangentIn = entry.PathTangentIn,
				PathTangentOut = entry.PathTangentOut,
				HeadFollow = entry.HeadFollow,
				HS = entry.HS,
				HSRestoreParented = entry.HSRestoreParented,
				HSRotation = entry.HSRotation,
				HSLocalRotation = entry.HSLocalRotation,
				IK = entry.IK,
				IKTarget = entry.IKTarget,
				IKPole = entry.IKPole,
				IKBaseC0 = entry.IKBaseC0,
				IKBaseWorld = entry.IKBaseWorld,
				IKAnchor = entry.IKAnchor,
				IKRigWorld = entry.IKRigWorld,
				CamTrackTo = entry.CamTrackTo,
				CamTargetEnabled = entry.CamTargetEnabled,
				CamAttachTarget = require("GraphCurves").clone(entry.CamAttachTarget),
				FovFollowAnchor = entry.FovFollowAnchor,
				CamTargetParent = entry.CamTargetParent,
				CamTargetAnchor = entry.CamTargetAnchor,
				IKRoot = entry.IKRoot,
				IKPoleFollowsTarget = entry.IKPoleFollowsTarget,
				IKRestoreParented = entry.IKRestoreParented,
				Motor = entry.Motor,
				Part = entry.Part,
				SanitizeName = entry.SanitizeName,
				Template = entry.Template,
				HandleType = entry.HandleType,
				EasingStyle = entry.EasingStyle,
				QuaternionInterpolationVersion = entry.QuaternionInterpolationVersion,
				EasingDirection = entry.EasingDirection,
				BezierPoints = entry.BezierPoints and {
					entry.BezierPoints[1],
					entry.BezierPoints[2],
					entry.BezierPoints[3],
					entry.BezierPoints[4],
				} or nil,
				Overshoot = entry.Overshoot,
				Amplitude = entry.Amplitude,
				Period = entry.Period,
				MoonEasing = entry.MoonEasing,
				GraphOnly = entry.GraphOnly,
				GraphCurves = GraphCurves.clone(entry.GraphCurves),
			}
			if entry.Channels then
				newKd.Channels = {}
				for chId, ch in pairs(entry.Channels) do
					newKd.Channels[chId] = GraphCurves.clone(ch)
				end
			end

			copyRemainingFields(entry, newKd, budget)
			replacement[frame] = newKd
		end

		assert(
			TimelineState.Keyframes[motor] == bucket,
			"The animation changed while restoring keys"
		)
		GraphCurves.invalidate(bucket)
		for _, kd in pairs(bucket) do
			if type(kd) == "table" and kd.Button then
				kd.Button:Destroy()
				kd.Button = nil
			end
		end

		for f in pairs(bucket) do
			bucket[f] = nil
		end

		TimelineState.SelectedKeyframes = TimelineState.SelectedKeyframes or {}
		for kd in pairs(TimelineState.SelectedKeyframes) do
			if kd.Motor == motor then
				TimelineState.SelectedKeyframes[kd] = nil
			end
		end

		if TimelineState.SelectedKeyframe and TimelineState.SelectedKeyframe.Motor == motor then
			TimelineState.SelectedKeyframe = nil
		end

		for kd in pairs(TimelineState.SelectedChannelKeyframes) do
			if kd.Motor == motor then
				TimelineState.SelectedChannelKeyframes[kd] = nil
			end
		end

		for frame, entry in replacement do
			bucket[frame] = entry
		end

		GraphCurves.invalidate(bucket)
		require("cache").invalidate()
		if not deferVisuals then
			for frame, key in pairs(bucket) do
				if key.Part and GraphCurves.hasVisibleKey(bucket, key) then
					self:CreateOrUpdateTimelineKeyframeButton(
						key.Part,
						motor,
						frame,
						key.Template,
						key.SanitizeName
					)
				end
			end

			self:RefreshAllChannelDiamondsForMotor(motor)
		end

		TimelineState._motorUniform[motor] = nil
		TimelineState._motorHasScale[motor] = nil
		if not deferVisuals and self.RefreshIKEndMarkers then
			self:RefreshIKEndMarkers()
		end

		motionPath.markDirty()
	end

	function Timeline:_initiateKeyframeDrag(keyData, preserveSelection)
		if BlenderEdit.blocked() then
			return
		end

		if not keyData then
			return
		end

		if PlayheadDrag.draggingPlayhead then
			return
		end

		if KeyframeTransform.active then
			return
		end

		KeyframeDrag.hoveringKeyframe = keyData

		local modified = self:IsSelectionModifierDown()
		if modified and not preserveSelection and self:IsKeyframeSelected(keyData) then
			self:ToggleSelectedKeyframe(keyData)
			return
		end

		if modified then
			self:AddSelectedKeyframe(keyData)
		else
			if not self:IsKeyframeSelected(keyData) then
				self:SetSelectedKeyframe(keyData)
			end
		end

		KeyframeDrag.groupDragSelected = self:GetSelectedKeyframesList()
		KeyframeDrag.groupDragOriginals = {}

		for _, selectedKey in ipairs(KeyframeDrag.groupDragSelected) do
			KeyframeDrag.groupDragOriginals[selectedKey] = selectedKey.Frame
		end

		local dragMotorSet = {}
		dragMotorSet[keyData.Motor] = true
		for _, selectedKey in ipairs(KeyframeDrag.groupDragSelected) do
			if selectedKey.Motor then
				dragMotorSet[selectedKey.Motor] = true
			end
		end

		KeyframeDrag.dragBucketSnapshotsBefore = {}
		for motor in pairs(dragMotorSet) do
			KeyframeDrag.dragBucketSnapshotsBefore[motor] = self:_snapshotMotorBucket(motor)
		end

		PlayheadDrag.draggingPlayhead = false

		KeyframeDrag.draggingKeyframe = {
			KeyData = keyData,
			Motor = keyData.Motor,
			Part = keyData.Part,
			Template = keyData.Template,
			SanitizeName = keyData.SanitizeName,
			IsRealDrag = false,
			OriginalFrame = keyData.Frame,
		}

		PlayheadDrag.dragStartMouseX = UserInputService:GetMouseLocation().X
		PlayheadDrag.dragStartFrame = keyData.Frame

		local scaleGui = self.refs.Scale
		if scaleGui then
			local mouseTimelineX = (PlayheadDrag.dragStartMouseX - self:GetClickReferenceX())
				/ Motion.scale(scaleGui)
			local mouseFrame = self:PixelToFrame(mouseTimelineX)
			KeyframeDrag.dragMouseFrameOffset = mouseFrame - keyData.Frame
		else
			KeyframeDrag.dragMouseFrameOffset = 0
		end

		self:RefreshAllKeyframeVisuals()
	end

	function Timeline:_initiateChannelKeyframeDrag(keyData, channelId, preserveSelection)
		if BlenderEdit.blocked() then
			return
		end

		if not keyData or not channelId then
			return
		end

		if PlayheadDrag.draggingPlayhead then
			return
		end

		if KeyframeTransform.active then
			return
		end

		KeyframeDrag.hoveringKeyframe = keyData
		KeyframeDrag.hoveringChannelId = channelId

		local modified = self:IsSelectionModifierDown()
		if
			modified
			and not preserveSelection
			and self:IsChannelKeyframeSelected(keyData, channelId)
		then
			self:ToggleSelectedChannelKeyframe(keyData, channelId)
			return
		end

		if modified then
			self:AddSelectedChannelKeyframe(keyData, channelId)
		else
			if not self:IsChannelKeyframeSelected(keyData, channelId) then
				self:SetSelectedChannelKeyframe(keyData, channelId)
			end
		end

		KeyframeDrag.groupDragSelected = { keyData }
		KeyframeDrag.groupDragOriginals = { [keyData] = keyData.Frame }

		local groupChannels = {}
		for kd, channels in pairs(TimelineState.SelectedChannelKeyframes) do
			for chId in pairs(channels) do
				table.insert(groupChannels, {
					keyData = kd,
					channelId = chId,
					originalFrame = kd.Frame,
					motor = kd.Motor,
					part = kd.Part,
					sanitizeName = kd.SanitizeName,
				})
			end
		end

		KeyframeDrag.groupDragSelectedChannels = groupChannels

		local dragMotorSet = {}
		if keyData.Motor then
			dragMotorSet[keyData.Motor] = true
		end

		for _, entry in ipairs(groupChannels) do
			if entry.motor then
				dragMotorSet[entry.motor] = true
			end
		end

		KeyframeDrag.dragBucketSnapshotsBefore = {}
		for motor in pairs(dragMotorSet) do
			KeyframeDrag.dragBucketSnapshotsBefore[motor] = self:_snapshotMotorBucket(motor)
		end

		PlayheadDrag.draggingPlayhead = false

		KeyframeDrag.draggingKeyframe = {
			KeyData = keyData,
			Motor = keyData.Motor,
			Part = keyData.Part,
			Template = keyData.Template,
			SanitizeName = keyData.SanitizeName,
			IsRealDrag = false,
			OriginalFrame = keyData.Frame,
			ChannelId = channelId,
		}

		PlayheadDrag.dragStartMouseX = UserInputService:GetMouseLocation().X
		PlayheadDrag.dragStartFrame = keyData.Frame

		local scaleGui = self.refs.Scale
		if scaleGui then
			local mouseTimelineX = (PlayheadDrag.dragStartMouseX - self:GetClickReferenceX())
				/ Motion.scale(scaleGui)
			local mouseFrame = self:PixelToFrame(mouseTimelineX)
			KeyframeDrag.dragMouseFrameOffset = mouseFrame - keyData.Frame
		else
			KeyframeDrag.dragMouseFrameOffset = 0
		end

		self:RefreshAllKeyframeVisuals()
	end

	function Timeline:PruneOrphanKeyframeButtons(budget)
		for _, row in TimelineState.TrackRows do
			local container = self:GetTrackKeyframesContainer(row)
			for _, button in container and container:GetChildren() or {} do
				if button:IsA("GuiButton") and button.Name:find("_KF_", 1, true) then
					local key = buttonKeys[button]
					local bucket = key and TimelineState.Keyframes[key.Motor]
					if
						not key
						or key.Button ~= button
						or not bucket
						or bucket[key.Frame] ~= key
					then
						buttonKeys[button] = nil
						if key and key.Button == button then
							key.Button = nil
						end

						button:Destroy()
					end
				end

				if budget then
					budget()
				end
			end
		end
	end

	function Timeline:RefreshAllKeyframeVisuals(budget)
		if TimelineState._ImportingKeyframes then
			return
		end

		self:PruneOrphanKeyframeButtons(budget)

		for button, keyData in buttonKeys do
			local bucket = TimelineState.Keyframes[keyData.Motor]
			if keyData.Button ~= button or not bucket or bucket[keyData.Frame] ~= keyData then
				buttonKeys[button] = nil
				if keyData.Button == button then
					keyData.Button = nil
				end

				button:Destroy()
			end

			if budget then
				budget()
			end
		end

		for button, keyData in buttonKeys do
			if not button.Parent then
				buttonKeys[button] = nil
				continue
			end

			if keyData.Button == button then
				self:ApplyKeyframeVisualState(keyData)
			end

			if budget then
				budget()
			end
		end

		self:RefreshAllChannelDiamondColors(budget)
		if self.RefreshIKEndMarkers then
			self:RefreshIKEndMarkers()
		end
	end

	function Timeline:RegisterChannelTracksForMotor(motor, rows)
		if not motor then
			return
		end

		TimelineState.ChannelTracks[motor] = rows
		self:InvalidateKeyframeViewportLayout()
		self:RefreshAllChannelDiamondsForMotor(motor)
	end

	function Timeline:UnregisterChannelTracksForMotor(motor)
		if not motor then
			return
		end

		local rows = TimelineState.ChannelTracks[motor]
		if rows then
			for _, row in pairs(rows) do
				local container = self:GetTrackKeyframesContainer(row)
				if container then
					for _, child in ipairs(container:GetChildren()) do
						if string.sub(child.Name, 1, #CHANNEL_KF_PREFIX) == CHANNEL_KF_PREFIX then
							child:Destroy()
						end
					end
				end
			end
		end

		TimelineState.ChannelTracks[motor] = nil
	end

	function Timeline:_paintChannelDiamond(kfBtn, motor, frameNumber, channelId)
		kfBtn.ZIndex = 10 + math.max(0, math.floor(frameNumber))
		local imgObj = self:GetKeyframeImageObject(kfBtn)
		if not imgObj then
			return
		end

		local bucket = TimelineState.Keyframes[motor]
		local keyData = bucket and bucket[frameNumber]

		if keyData and channelId then
			local isSelected = self:IsChannelKeyframeSelected(keyData, channelId)
			local draggingInfo = KeyframeDrag.draggingKeyframe
			local isDragging = draggingInfo
				and (draggingInfo.KeyData == keyData or draggingInfo.SummaryScope and KeyframeDrag.groupDragOriginals[keyData] ~= nil)
				and (draggingInfo.ChannelId == nil or draggingInfo.ChannelId == channelId)
			local isHovered = KeyframeDrag.hoveringKeyframe == keyData
				and (
					KeyframeDrag.hoveringChannelId == nil
					or KeyframeDrag.hoveringChannelId == channelId
				)

			keyTransparency(imgObj, keyData, isSelected or isDragging, isHovered)
			imgObj.Image = resolveKeyframeShape(keyData, motor)

			if KeyframePolicy.isDisabled(keyData, channelId) then
				imgObj.ImageColor3 = (isSelected or isDragging)
						and State.Colors.KEYFRAME_SELECTED_COLOR:Lerp(
							Color3.fromRGB(100, 106, 108),
							0.4
						)
					or Color3.fromRGB(100, 106, 108)
			elseif isSelected or isDragging then
				imgObj.ImageColor3 = State.Colors.KEYFRAME_SELECTED_COLOR
			else
				local handleType = resolveHandleType(keyData)
				if isHovered then
					imgObj.ImageColor3 = KeyColors.get(keyData, channelId, true) or KEYFRAME_HANDLE_HOVER[handleType]
				else
					imgObj.ImageColor3 = KeyColors.get(keyData, channelId) or KEYFRAME_HANDLE_DEFAULT[handleType]
				end
			end

			if isDragging then
				kfBtn.Size = UDim2.new(0, 22, 0, 22)
			elseif isSelected then
				kfBtn.Size = UDim2.new(0, 18, 0, 18)
			else
				kfBtn.Size = UDim2.new(0, 16, 0, 16)
			end
		else
			keyTransparency(imgObj, nil, false, false)
			imgObj.Image = resolveKeyframeShape(nil, motor)
			imgObj.ImageColor3 = KEYFRAME_HANDLE_DEFAULT[resolveHandleType(nil)]
		end
	end

	function Timeline:_addChannelDiamondAtFrame(motor, frameNumber)
		if TimelineState._ImportingKeyframes then
			return
		end

		self:EnsureTimelineScaleCurrent()
		local channelRows = TimelineState.ChannelTracks[motor]
		if not channelRows then
			return
		end

		local bucket = TimelineState.Keyframes[motor]
		local keyData = bucket and bucket[frameNumber]
		if not keyData then
			return
		end

		self:EnsureChannelsPopulated(keyData)
		if not keyData.Channels then
			return
		end

		local name = CHANNEL_KF_PREFIX .. frameNumber
		local x = self:FrameToVisibleX(frameNumber)

		for channelId, row in pairs(channelRows) do
			local container = self:GetTrackKeyframesContainer(row)
			if container then
				local channelKf = keyData.Channels[channelId]
				local graphChannel = GraphCurves.compile(bucket).channels[channelId]
				if graphChannel then
					local point = keyData.GraphCurves and keyData.GraphCurves[channelId]
					channelKf = point and not point.Empty and point or nil
				end

				local kfBtn = container:FindFirstChild(name)
				if not self:KeyframeInViewport(keyData, channelId) then
					if kfBtn then
						kfBtn:Destroy()
					end

					continue
				end

				if self.IsKeyGroupCollapsed and self:IsKeyGroupCollapsed(keyData, channelId) then
					if kfBtn then
						kfBtn:Destroy()
					end

					continue
				end

				if channelKf then
					local freshlyCreated = false
					if not kfBtn then
						local template = container:FindFirstChild("KeyframeTemplate")
						if template then
							kfBtn = template:Clone()
							kfBtn.Name = name
							kfBtn.AnchorPoint = Vector2.new(0.5, 0.5)
							kfBtn.Visible = true
							kfBtn.Size = UDim2.new(0, 16, 0, 16)
							if kfBtn:IsA("GuiButton") then
								kfBtn.AutoButtonColor = false
								kfBtn.Active = true
								kfBtn.Selectable = true
							end

							kfBtn.Parent = container
							freshlyCreated = true
						end
					end

					if kfBtn then
						if freshlyCreated then
							self:_attachChannelDiamondInteraction(
								kfBtn,
								motor,
								frameNumber,
								channelId
							)
						end

						self:_paintChannelDiamond(kfBtn, motor, frameNumber, channelId)
						kfBtn.Position = UDim2.new(0, x, 0.5, 0)
					end
				else
					if kfBtn then
						kfBtn:Destroy()
					end
				end
			end
		end
	end

	function Timeline:_attachChannelDiamondInteraction(kfBtn, motor, frameNumber, channelId)
		local lastTime, lastKey = 0, nil
		channelButtons[kfBtn] = { frame = frameNumber, motor = motor, lane = channelId }

		local function resolveKeyData()
			local bucket = TimelineState.Keyframes[motor]
			return bucket and bucket[frameNumber] or nil
		end

		kfBtn.MouseEnter:Connect(function()
			local keyData = resolveKeyData()
			if not keyData then
				return
			end

			self:SetKeyframeHover(keyData, channelId, kfBtn)
		end)

		kfBtn.MouseLeave:Connect(function()
			self:ClearKeyframeHover(kfBtn)
		end)

		if kfBtn:IsA("GuiButton") then
			kfBtn.MouseButton2Click:Connect(function()
				local key = resolveKeyData()
				if not key then
					return
				end

				if not self:IsChannelKeyframeSelected(key, channelId) then
					self:SetSelectedChannelKeyframe(key, channelId)
				end

				KeyframeMenu.open(UserInputService:GetMouseLocation())
			end)
			kfBtn.MouseButton1Down:Connect(function()
				local keyData = resolveKeyData()
				if not keyData then
					return
				end

				if self:SelectRigFrame(keyData) then
					return
				end

				local now = os.clock()
				if
					not self:IsSelectionModifierDown()
					and lastKey == keyData
					and now - lastTime <= DOUBLE_CLICK_THRESHOLD
					and self:IsChannelKeyframeSelected(keyData, channelId)
				then
					lastTime, lastKey = 0, nil
					KeyframeMenu.open(UserInputService:GetMouseLocation())
					return
				end

				lastTime, lastKey = now, keyData
				self:_initiateChannelKeyframeDrag(keyData, channelId)
			end)
		end
	end

	function Timeline:_removeChannelDiamondAtFrame(motor, frameNumber)
		local channelRows = TimelineState.ChannelTracks[motor]
		if not channelRows then
			return
		end

		local name = CHANNEL_KF_PREFIX .. frameNumber
		for _, row in pairs(channelRows) do
			local container = self:GetTrackKeyframesContainer(row)
			if container then
				local kfBtn = container:FindFirstChild(name)
				if kfBtn then
					kfBtn:Destroy()
				end
			end
		end
	end

	function Timeline:RefreshAllChannelDiamondsForMotor(motor, budget)
		if TimelineState._ImportingKeyframes then
			return
		end

		local channelRows = TimelineState.ChannelTracks[motor]
		if not channelRows then
			return
		end

		for _, row in pairs(channelRows) do
			local container = self:GetTrackKeyframesContainer(row)
			if container then
				for _, child in ipairs(container:GetChildren()) do
					if budget then
						budget()
					end

					if string.sub(child.Name, 1, #CHANNEL_KF_PREFIX) == CHANNEL_KF_PREFIX then
						child:Destroy()
					end
				end
			end
		end

		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return
		end

		for frameNumber in pairs(bucket) do
			self:_addChannelDiamondAtFrame(motor, frameNumber)
			if budget then
				budget()
			end
		end
	end

	function Timeline:RefreshAllChannelDiamondColors(budget)
		for motor, channelRows in pairs(TimelineState.ChannelTracks) do
			for channelId, row in pairs(channelRows) do
				local container = self:GetTrackKeyframesContainer(row)
				if container then
					for _, child in ipairs(container:GetChildren()) do
						if budget then
							budget()
						end

						if string.sub(child.Name, 1, #CHANNEL_KF_PREFIX) == CHANNEL_KF_PREFIX then
							local frameStr = string.sub(child.Name, #CHANNEL_KF_PREFIX + 1)
							local frameNumber = tonumber(frameStr)
							if frameNumber then
								self:_paintChannelDiamond(child, motor, frameNumber, channelId)
							end
						end
					end
				end
			end
		end
	end

	function Timeline:CancelTimelineKeyframeDrag()
		if not KeyframeDrag.draggingKeyframe then
			return false
		end

		KeyframeDrag.draggingKeyframe = nil
		KeyframeDrag.dragCurrentFrame = nil
		KeyframeDrag.dragHoverReplaceTarget = nil
		KeyframeDrag.dragBucketSnapshotsBefore = nil
		KeyframeDrag.groupDragOriginals = {}
		KeyframeDrag.groupDragSelected = {}
		KeyframeDrag.groupDragSelectedChannels = {}
		self._compactKeyDrag = nil
		self:RefreshAllTimelineKeyframePositions()
		self:RefreshAllKeyframeVisuals()
		return true
	end

	function Timeline:DeleteKeyframe(keyData)
		if BlenderEdit.blocked() then
			return
		end

		if not keyData or not keyData.Motor or keyData.Frame == nil then
			return
		end

		local motor = keyData.Motor
		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return
		end

		self:CancelTimelineKeyframeDrag()
		local deletedFrame = keyData.Frame
		local existing = bucket[deletedFrame]
		if existing and existing.Button then
			existing.Button:Destroy()
		end

		bucket[deletedFrame] = nil

		GraphCurves.invalidate(bucket)

		TimelineState.SelectedKeyframes[keyData] = nil
		TimelineState.SelectedChannelKeyframes[keyData] = nil
		if TimelineState.SelectedKeyframe == keyData then
			TimelineState.SelectedKeyframe = nil
		end

		if KeyframeDrag.hoveringKeyframe == keyData then
			KeyframeDrag.hoveringKeyframe = nil
			KeyframeDrag.hoveringChannelId = nil
		end

		if KeyframeDrag.draggingKeyframe and KeyframeDrag.draggingKeyframe.KeyData == keyData then
			KeyframeDrag.draggingKeyframe = nil
		end

		local previousFrame = nil
		for frameNumber in pairs(bucket) do
			if
				frameNumber < deletedFrame
				and (not previousFrame or frameNumber > previousFrame)
			then
				previousFrame = frameNumber
			end
		end

		local lockedDescendants =
			MotorMath.collectTrackParentLockedDescendants(MainState.currentRig, motor)

		local isDetached = motor:GetAttribute("TrackParent") == false

		if isDetached then
			if previousFrame and bucket[previousFrame] and motor.Part0 then
				local prevKd = bucket[previousFrame]
				if prevKd.WorldCFrame then
					motor.C0 = motor.Part0.CFrame:Inverse() * prevKd.WorldCFrame * motor.C1
				elseif prevKd.C0 then
					motor.C0 = prevKd.C0
				end
			end
		else
			if previousFrame and bucket[previousFrame] and bucket[previousFrame].C0 then
				motor.C0 = bucket[previousFrame].C0
			else
				local defaultC0 = TimelineState.DefaultPose[motor]
				if defaultC0 then
					motor.C0 = defaultC0
				end
			end
		end

		MotorMath.restoreTrackParentLockedDescendants(lockedDescendants)

		self:UpdateDeleteButtonState()
		self:RefreshAllKeyframeVisuals()
		self:_removeChannelDiamondAtFrame(motor, deletedFrame)
		motionPath.markDirty()
	end

	function Timeline:PeelOffChannelKeyframe(motor, sourceFrame, destFrame, channelId)
		if BlenderEdit.blocked() then
			return
		end

		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		if sourceFrame == destFrame then
			return nil
		end

		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return nil
		end

		local sourceKeyData = bucket[sourceFrame]
		if not sourceKeyData or not sourceKeyData.Channels then
			return nil
		end

		local graph = sourceKeyData.GraphCurves and sourceKeyData.GraphCurves[channelId]
		if graph and not graph.Empty then
			local target = bucket[destFrame]
			if not target then
				target = {
					Frame = destFrame,
					Time = destFrame / TimelineState.FPS,
					Motor = motor,
					Part = sourceKeyData.Part or motor.Part1,
					C0 = sourceKeyData.C0,
					Position = sourceKeyData.Position,
					Rotation = sourceKeyData.Rotation,
					SanitizeName = sourceKeyData.SanitizeName,
					Channels = {},
					GraphOnly = true,
				}
				bucket[destFrame] = target
			end

			target.GraphCurves = target.GraphCurves or {}
			graph.Disabled = graph.Disabled or sourceKeyData.Disabled
			target.GraphCurves[channelId] = graph
			KeyGroups.transfer(sourceKeyData, target, channelId)
			sourceKeyData.GraphCurves[channelId] = nil
			if not next(sourceKeyData.GraphCurves) then
				sourceKeyData.GraphCurves = nil
			end

			GraphCurves.invalidate(bucket)
			self:CreateOrUpdateTimelineKeyframeButton(
				sourceKeyData.Part,
				motor,
				sourceFrame,
				nil,
				sourceKeyData.SanitizeName
			)
			self:_addChannelDiamondAtFrame(motor, sourceFrame)
			self:CreateOrUpdateTimelineKeyframeButton(
				target.Part,
				motor,
				destFrame,
				nil,
				target.SanitizeName
			)
			self:_addChannelDiamondAtFrame(motor, destFrame)
			if MainState.GraphEditor then
				MainState.GraphEditor.invalidate()
			end

			motionPath.markDirty()
			return target
		end

		local sourceChannel = sourceKeyData.Channels[channelId]
		if not sourceChannel then
			return nil
		end

		TimelineState._motorUniform[motor] = false

		local peeledValue = sourceChannel.Value
		local partRef = sourceKeyData.Part or motor.Part1
		local sanitizeNameRef = sourceKeyData.SanitizeName

		sourceKeyData.Channels[channelId] = nil

		if next(sourceKeyData.Channels) == nil then
			if sourceKeyData.Button then
				sourceKeyData.Button:Destroy()
			end

			bucket[sourceFrame] = nil
			self:_removeChannelDiamondAtFrame(motor, sourceFrame)
		else
			self:_addChannelDiamondAtFrame(motor, sourceFrame)
		end

		bucket[destFrame] = bucket[destFrame]
			or {
				Frame = destFrame,
				Time = destFrame / TimelineState.FPS,
				Motor = motor,
				Part = partRef,
				SanitizeName = sanitizeNameRef,
				Parented = sourceKeyData.Parented,
				WorldCFrame = sourceKeyData.WorldCFrame,
				MasterWorld = sourceKeyData.MasterWorld,
				Channels = {},
			}
		local destKeyData = bucket[destFrame]
		KeyGroups.transfer(sourceKeyData, destKeyData, channelId)
		destKeyData.Channels = destKeyData.Channels or {}
		destKeyData.Channels[channelId] = GraphCurves.clone(sourceChannel)
		destKeyData.Channels[channelId].Value = peeledValue
		destKeyData.Channels[channelId].Disabled = sourceChannel.Disabled or sourceKeyData.Disabled
		destKeyData.Frame = destFrame
		destKeyData.Time = destFrame / TimelineState.FPS
		destKeyData.Motor = motor
		destKeyData.Part = destKeyData.Part or partRef
		destKeyData.SanitizeName = destKeyData.SanitizeName or sanitizeNameRef

		destKeyData.C0 = self:_reconstructC0FromKeyData(destKeyData) or destKeyData.C0
		if destKeyData.C0 then
			destKeyData.Position = destKeyData.C0.Position
			destKeyData.Rotation = destKeyData.C0 - destKeyData.C0.Position
		end

		self:CreateOrUpdateTimelineKeyframeButton(
			destKeyData.Part,
			motor,
			destFrame,
			nil,
			destKeyData.SanitizeName
		)
		self:_addChannelDiamondAtFrame(motor, destFrame)

		motionPath.markDirty()
		return destKeyData
	end

	function Timeline:MoveKeyframe(
		part,
		motor,
		oldFrame,
		newFrame,
		keyframeTemplate,
		sanitizeName,
		allowReplace
	)
		if BlenderEdit.blocked() then
			return
		end

		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		if not motor or oldFrame == nil or newFrame == nil then
			return nil
		end

		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return nil
		end

		local keyData = bucket[oldFrame]
		if not keyData then
			return nil
		end

		allowReplace = allowReplace == true

		if oldFrame == newFrame then
			keyData.Time = self:FrameToTime(newFrame)
			keyData.Frame = newFrame
			self:CreateOrUpdateTimelineKeyframeButton(
				part,
				motor,
				newFrame,
				keyframeTemplate,
				sanitizeName
			)
			self:_addChannelDiamondAtFrame(motor, newFrame)
			if self.RefreshIKEndMarkers then
				self:RefreshIKEndMarkers()
			end

			return bucket[newFrame]
		end

		local occupied = bucket[newFrame]
		if occupied and occupied ~= keyData then
			if not allowReplace then
				return keyData
			end

			if occupied.Button then
				occupied.Button:Destroy()
			end

			bucket[newFrame] = nil

			if TimelineState.SelectedKeyframe == occupied then
				TimelineState.SelectedKeyframe = nil
			end

			TimelineState.SelectedKeyframes[occupied] = nil
			TimelineState.SelectedChannelKeyframes[occupied] = nil

			if KeyframeDrag.hoveringKeyframe == occupied then
				KeyframeDrag.hoveringKeyframe = nil
			end
		end

		bucket[oldFrame] = nil
		bucket[newFrame] = keyData
		keyData.Frame = newFrame
		keyData.Time = self:FrameToTime(newFrame)

		self:CreateOrUpdateTimelineKeyframeButton(
			part,
			motor,
			newFrame,
			keyframeTemplate,
			sanitizeName
		)

		self:_removeChannelDiamondAtFrame(motor, oldFrame)
		self:_addChannelDiamondAtFrame(motor, newFrame)
		if self.RefreshIKEndMarkers then
			self:RefreshIKEndMarkers()
		end

		motionPath.markDirty()
		return bucket[newFrame]
	end

	function Timeline:GetKeyframeAtFrame(motor, frameNumber, ignoreKeyData)
		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return nil
		end

		local keyData = bucket[frameNumber]
		if keyData and keyData ~= ignoreKeyData then
			return keyData
		end

		return nil
	end

	function Timeline:IsMouseDirectlyOverKeyframeButton(keyData, mousePos)
		if not keyData then
			return false
		end

		local function hit(button)
			if not button or not button.Parent or not button.Visible then
				return false
			end

			local ancestor = button.Parent
			while ancestor do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then
					return false
				end

				ancestor = ancestor.Parent
			end

			local pos, size = button.AbsolutePosition, button.AbsoluteSize
			return mousePos.X >= pos.X
				and mousePos.X <= pos.X + size.X
				and mousePos.Y >= pos.Y
				and mousePos.Y <= pos.Y + size.Y
		end

		if hit(keyData.Button) then
			return true
		end

		if self.GetIKEndMarkerButtons then
			for _, button in self:GetIKEndMarkerButtons(keyData) do
				if hit(button) then
					return true
				end
			end
		end

		return false
	end

	function Timeline:FindNearestKeyframeWithinPixelTolerance(motor, mousePos, ignoreSet, tolerance)
		local bucket = TimelineState.Keyframes[motor]
		if not bucket or not mousePos or not tolerance then
			return nil
		end

		local best = nil
		local bestDistance = tolerance + 1

		for _, keyData in pairs(bucket) do
			if keyData and keyData.Button and keyData.Button.Visible then
				local skip = false
				if ignoreSet then
					if type(ignoreSet) == "table" and ignoreSet[keyData] then
						skip = true
					elseif ignoreSet == keyData then
						skip = true
					end
				end

				if not skip then
					local pos = keyData.Button.AbsolutePosition
					local size = keyData.Button.AbsoluteSize
					local centerX = pos.X + size.X * 0.5
					local distance = math.abs(mousePos.X - centerX)

					if distance <= tolerance and distance < bestDistance then
						best = keyData
						bestDistance = distance
					end
				end
			end
		end

		return best
	end

	function Timeline:_repaintHoveredKey(keyData)
		if not keyData then
			return
		end

		self:ApplyKeyframeVisualState(keyData)
		local rows = TimelineState.ChannelTracks[keyData.Motor]
		if not rows then
			return
		end

		for channelId, row in pairs(rows) do
			local container = self:GetTrackKeyframesContainer(row)
			local diamond = container
				and container:FindFirstChild(CHANNEL_KF_PREFIX .. keyData.Frame)
			if diamond then
				self:_paintChannelDiamond(diamond, keyData.Motor, keyData.Frame, channelId)
			end
		end
	end

	function Timeline:SetKeyframeHover(keyData, channelId, button)
		local previous = KeyframeDrag.hoveringKeyframe
		KeyframeDrag.hoveringKeyframe = keyData
		KeyframeDrag.hoveringChannelId = channelId
		hoverButton = button
		if previous and previous ~= keyData then
			self:_repaintHoveredKey(previous)
		end

		self:_repaintHoveredKey(keyData)
	end

	function Timeline:ClearKeyframeHover(button)
		if button and hoverButton ~= button then
			return
		end

		self:SetKeyframeHover(nil, nil, nil)
	end

	function Timeline:UpdateKeyframeHover()
		local button = hoverButton
		if not button then
			return
		end

		local visible = button.Parent ~= nil
		local node = button
		while node and visible do
			if
				node:IsA("GuiObject") and not node.Visible
				or node:IsA("LayerCollector") and not node.Enabled
			then
				visible = false
			end

			node = node.Parent
		end

		local point = UserInputService:GetMouseLocation()
		local p, size = button.AbsolutePosition, button.AbsoluteSize
		if
			not visible
			or point.X < p.X
			or point.Y < p.Y
			or point.X > p.X + size.X
			or point.Y > p.Y + size.Y
		then
			self:ClearKeyframeHover(button)
		end
	end

	function Timeline:_attachKeyframeInteraction(keyBtn, keyData)
		buttonKeys[keyBtn] = keyData

		local function currentKey()
			local key = buttonKeys[keyBtn]
			local bucket = key and TimelineState.Keyframes[key.Motor]
			return key and key.Button == keyBtn and bucket and bucket[key.Frame] == key and key
				or nil
		end

		keyBtn.MouseEnter:Connect(function()
			local keyData = currentKey()
			if not keyData then
				return
			end

			self:SetKeyframeHover(keyData, nil, keyBtn)
		end)
		keyBtn.MouseLeave:Connect(function()
			self:ClearKeyframeHover(keyBtn)
		end)
		keyBtn.Destroying:Connect(function()
			self:ClearKeyframeHover(keyBtn)
			buttonKeys[keyBtn] = nil
		end)
		if keyBtn:IsA("GuiButton") then
			keyBtn.MouseButton2Click:Connect(function()
				local keyData = currentKey()
				if not keyData then
					return
				end

				if not self:IsKeyframeSelected(keyData) then
					self:SetSelectedKeyframes({ keyData })
				end

				KeyframeMenu.open(UserInputService:GetMouseLocation())
			end)
			keyBtn.MouseButton1Down:Connect(function()
				local keyData = currentKey()
				if not keyData then
					return
				end

				if self:SelectRigFrame(keyData) then
					return
				end

				local now = os.clock()
				if
					not self:IsSelectionModifierDown()
					and lastClickKey == keyData
					and now - lastClickTime <= DOUBLE_CLICK_THRESHOLD
					and self:IsKeyframeSelected(keyData)
				then
					if selectionAtFirstClick then
						local hadKeyData = false
						for _, kd in ipairs(selectionAtFirstClick) do
							if kd == keyData then
								hadKeyData = true
								break
							end
						end

						if hadKeyData and #selectionAtFirstClick > 1 then
							self:SetSelectedKeyframes(selectionAtFirstClick)
						end
					end

					lastClickTime, lastClickKey, selectionAtFirstClick = 0, nil, nil
					KeyframeMenu.open(UserInputService:GetMouseLocation())
					return
				end

				selectionAtFirstClick = self:GetSelectedKeyframesList()
				lastClickTime, lastClickKey = now, keyData
				self:_initiateKeyframeDrag(keyData)
			end)
		end
	end

	function Timeline:CreateOrUpdateTimelineKeyframeButton(
		part,
		motor,
		frameNumber,
		_,
		sanitizeName
	)
		if TimelineState._ImportingKeyframes then
			return
		end

		self:EnsureTimelineScaleCurrent()
		self:PrepareKeyframeViewport()
		local existingBucket = TimelineState.Keyframes[motor]
		local existing = existingBucket and existingBucket[frameNumber]
		if existing and not self:KeyframeInViewport(existing, "Pose") then
			if existing.Button then
				existing.Button:Destroy()
				existing.Button = nil
			end

			return
		end

		if existing and self.IsKeyGroupCollapsed and self:IsKeyGroupCollapsed(existing, "Pose") then
			if existing.Button then
				existing.Button:Destroy()
				existing.Button = nil
			end

			return
		end

		if existing and not GraphCurves.hasVisibleKey(existingBucket, existing) then
			if existing.Button then
				existing.Button:Destroy()
				existing.Button = nil
			end

			self:_removeChannelDiamondAtFrame(motor, frameNumber)
			return
		end

		if not part or not motor then
			return
		end

		local bucket = self:GetMotorKeyframeBucket(motor)
		if not bucket then
			return
		end

		local keyData = bucket[frameNumber]
		if not keyData then
			return
		end

		part = motor.Part1
		local row = TimelineState.TrackRows[part]
		if not row then
			return
		end

		local keyframesContainer = self:GetTrackKeyframesContainer(row)
		if not keyframesContainer then
			return
		end

		local template = keyframesContainer:FindFirstChild("KeyframeTemplate")
		if not template then
			warn("No keyframe template inside row for part:", part:GetFullName())
			return
		end

		keyData.Motor = motor
		keyData.Part = part
		keyData.Frame = frameNumber
		keyData.Template = template
		keyData.SanitizeName = sanitizeName

		if keyData.Button and keyData.Button.Parent ~= keyframesContainer then
			local button = keyData.Button
			if
				button.Parent ~= nil
				or not pcall(function()
					button.Parent = keyframesContainer
				end)
			then
				button:Destroy()
				keyData.Button = nil
			else
				button.Visible = true
			end
		end

		if not keyData.Button or not keyData.Button.Parent then
			local keyBtn = template:Clone()
			keyBtn.Visible = true
			keyBtn.Parent = keyframesContainer
			keyBtn.AnchorPoint = Vector2.new(0.5, 0.5)
			keyBtn.ZIndex = math.max(template.ZIndex, 10)

			if keyBtn:IsA("GuiButton") then
				keyBtn.AutoButtonColor = false
				keyBtn.Active = true
				keyBtn.Selectable = true
			end

			keyData.Button = keyBtn

			self:_attachKeyframeInteraction(keyBtn, keyData)
		end

		buttonKeys[keyData.Button] = keyData
		local x = self:FrameToVisibleX(frameNumber)
		keyData.Button.Name = ((sanitizeName and sanitizeName(part.Name)) or part.Name)
			.. "_KF_"
			.. tostring(frameNumber)
		keyData.Button.Position = UDim2.new(0, x, 0.5, 0)

		self:ApplyKeyframeVisualState(keyData)
	end

	function Timeline:GetChangedPoseChannels(motor, c0, time, baselineC0)
		local before = self:DecomposeC0(baselineC0 or self:EvaluateMotorC0(motor, time))
		local after = self:DecomposeC0(c0)
		local scale = self:EvaluateMotorScale(motor, time)
		for _, id in { "scale_x", "scale_y", "scale_z" } do
			before[id] = scale and scale[id] or 1
		end

		local part = motor.Part1
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			local value = motor.InputScale
			after.scale_x, after.scale_y, after.scale_z = value.X, value.Y, value.Z
		elseif part and part:IsA("BasePart") and TimelineState.DefaultSize[part] then
			local base = TimelineState.DefaultSize[part]
			local value = part.Size / Properties.scaleFactor(motor)
			after.scale_x, after.scale_y, after.scale_z =
				value.X / math.max(base.X, 1e-5),
				value.Y / math.max(base.Y, 1e-5),
				value.Z / math.max(base.Z, 1e-5)
		end

		local changed = {}
		for _, id in { "loc_x", "loc_y", "loc_z", "scale_x", "scale_y", "scale_z" } do
			if
				KeyframePolicy.channelAvailable(motor, id)
				and math.abs(after[id] - before[id]) > 1e-3
			then
				table.insert(changed, id)
			end
		end

		local order = GraphCurves.rotationOrder(TimelineState.Keyframes[motor])
		if order then
			local x, y, z =
				GraphCurves.euler(baselineC0 or self:EvaluateMotorC0(motor, time), order)
			local a = { x, y, z }
			local nx, ny, nz = GraphCurves.euler(c0, order, a)
			local b = { nx, ny, nz }
			for i, id in { "rot_x", "rot_y", "rot_z" } do
				if math.abs(b[i] - a[i]) > math.deg(1e-3) then
					table.insert(changed, id)
				end
			end

			return changed
		end

		local dot = 0
		for _, id in { "qrot_w", "qrot_x", "qrot_y", "qrot_z" } do
			dot += before[id] * after[id]
		end

		for _, id in { "qrot_w", "qrot_x", "qrot_y", "qrot_z" } do
			if math.abs(after[id] - before[id] * (dot < 0 and -1 or 1)) > 1e-3 then
				for _, q in { "qrot_w", "qrot_x", "qrot_y", "qrot_z" } do
					table.insert(changed, q)
				end

				break
			end
		end

		return changed
	end

	function Timeline:ResetDeletedFirstTransformKey(motor, key, selected)
		if
			not key
			or key.Frame ~= 0
			or not KeyframePolicy.channelsEnabled()
			or Properties.is(motor)
			or CameraRig.isFov(motor)
		then
			return nil
		end

		local rest = TimelineState.DefaultPose[motor]
		if not rest then
			return nil
		end

		local copy = table.clone(key)
		copy.Channels = GraphCurves.clone(key.Channels or {})
		copy.GraphCurves = GraphCurves.clone(key.GraphCurves)
		copy.WholePoseScale = GraphCurves.clone(key.WholePoseScale)
		local defaults = decomposeC0(rest)
		local order = GraphCurves.rotationOrder(TimelineState.Keyframes[motor])
		local ex, ey, ez = GraphCurves.euler(rest, order)
		local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
		defaults.rot_x, defaults.rot_y, defaults.rot_z = math.deg(x), math.deg(y), math.deg(z)
		for id, value in defaults do
			if
				(not selected or selected[id])
				and KeyframePolicy.channelAvailable(motor, id)
				and (
					id:sub(1, 4) ~= "rot_"
					or (key.Channels and key.Channels[id])
					or (key.GraphCurves and key.GraphCurves[id])
				)
			then
				copy.Channels[id] = { Value = value }
				if copy.GraphCurves and copy.GraphCurves[id] then
					local point = GraphCurves.newPoint(copy, id)
					point.Value = value
					point.RotationOrder = id:sub(1, 4) == "rot_" and order or nil
					copy.GraphCurves[id] = point
				end

				if copy.WholePoseScale and id:sub(1, 6) == "scale_" then
					copy.WholePoseScale[id] = value
				end
			end
		end

		if not selected then
			copy.C0, copy.ChannelPoseC0, copy.Position, copy.Rotation =
				rest, rest, rest.Position, rest.Rotation
			copy.WholePoseScale = { scale_x = 1, scale_y = 1, scale_z = 1 }
			copy.Parented = TimelineState.ParentingDefaults[motor] ~= false
			copy.WorldCFrame = not copy.Parented and TimelineState.DefaultWorldPose[motor] or nil
			copy.MasterWorld = nil
			copy.PhysicsLead, copy.PhysicsTail = nil, nil

			for _, field in
				{
					"CamTargetParent",
					"CamTargetAnchor",
					"CamAttachTarget",
					"CamTargetEnabled",
					"CamTrackTo",
					"IK",
					"IKTarget",
					"IKPole",
					"IKBaseC0",
					"IKBaseWorld",
					"IKAnchor",
					"IKRigWorld",
					"IKRoot",
					"IKPoleFollowsTarget",
					"IKRestoreParented",
					"HeadFollow",
					"HS",
					"HSRestoreParented",
					"HSRotation",
					"HSLocalRotation",
					"PathTangentIn",
					"PathTangentOut",
					"BlenderCurve",
					"BlenderSource",
				}
			do
				copy[field] = nil
			end
		else
			local cf = self:_reconstructC0FromKeyData(copy)
			if cf then
				copy.C0, copy.ChannelPoseC0, copy.Position, copy.Rotation =
					cf, cf, cf.Position, cf.Rotation
			end
		end

		copy.Disabled, copy.GraphOnly = nil, nil
		return copy
	end

	local function resolveLegacyPoses(bucket)
		local dirty = false
		for _, key in bucket do
			if typeof(key) ~= "table" or not key.Motor or Properties.is(key.Motor) then
				continue
			end

			const pose = typeof(key.C0) == "CFrame" and key.C0 or nil
			if key.ChannelPoseC0 ~= nil then
				const legacy = key.ChannelPoseC0
				key.ChannelPoseC0 = nil
				dirty = true
				if pose and legacy ~= pose then
					key.Channels = KeyframePolicy.poseChannels(key, pose)
				end

				for id, value in key.WholePoseScale or {} do
					const channel = key.Channels and key.Channels[id]
					if channel and typeof(value) == "number" then
						channel.Value = value
					end
				end

				if pose then
					GraphCurves.recordPose(bucket, key, pose)
				end
			elseif key.WholePoseScale and key.Channels then
				local moved
				for id, value in key.WholePoseScale do
					const channel = key.Channels[id]
					if
						channel
						and typeof(channel.Value) == "number"
						and typeof(value) == "number"
						and math.abs(channel.Value - value) > 1e-6
					then
						dirty = true
						if KeyframePolicy.channelsEnabled() then
							key.WholePoseScale[id] = channel.Value
						else
							channel.Value = value
							moved = moved or {}
							table.insert(moved, id)
						end
					end
				end

				if moved and pose then
					GraphCurves.recordPose(bucket, key, pose, moved)
				end
			end
		end

		if dirty then
			GraphCurves.invalidate(bucket)
		end

		return dirty
	end

	function Timeline:EnsureTransformChannelStarts(onlyMotor, evaluationState)
		local TimelineState = evaluationState or TimelineState
		local Layers = require("Layers")
		const authoring = evaluationState == nil and KeyframePolicy.channelsEnabled()
		local changed = 0
		local poses = onlyMotor and { [onlyMotor] = TimelineState.DefaultPose[onlyMotor] }
			or TimelineState.DefaultPose
		for motor, rest in poses do
			if not evaluationState and MainState.ProjectWorkStep then
				MainState.ProjectWorkStep()
			end

			if
				TimelineState.AnimationLayers
				and Layers.active(TimelineState, motor).id ~= "base"
			then
				continue
			end

			if
				not motor.Parent
				or not motor.Part1
				or Properties.is(motor)
				or CameraRig.isFov(motor)
			then
				continue
			end

			const attachment = require("Target").isAttachment(motor)
			local bucket = evaluationState and evaluationState.Keyframes[motor]
				or (attachment or authoring) and self:GetMotorKeyframeBucket(motor)
				or TimelineState.Keyframes[motor]
			if not bucket then
				continue
			end

			if attachment then
				if not bucket[0] then
					bucket[0] = {
						Frame = 0,
						Time = 0,
						Motor = motor,
						Part = motor.Part1,
						C0 = CFrame.identity,
						Position = Vector3.zero,
						Rotation = CFrame.identity,
						Parented = true,
						CamAttachTarget = false,
						EasingStyle = "Constant",
					}
					if not evaluationState then
						self:CreateOrUpdateTimelineKeyframeButton(
							motor.Part1,
							motor,
							0,
							nil,
							tostring
						)
					end

					changed += 1
				end

				continue
			end

			if (onlyMotor == nil or not authoring) and resolveLegacyPoses(bucket) then
				TimelineState._motorUniform[motor] = nil
				TimelineState._motorHasScale[motor] = nil
				changed += 1
			end

			if not authoring then
				continue
			end

			if typeof(motor) == "table" and motor.IsEclipseR6Control and not next(bucket) then
				continue
			end

			local key = bucket[0]
			local incomplete = not key or not key.Channels
			for _, id in CHANNEL_IDS do
				if incomplete then
					break
				end

				incomplete = KeyframePolicy.channelAvailable(motor, id) and not key.Channels[id]
			end

			local start, scale = rest, nil
			if incomplete and next(bucket) then
				start = self:EvaluateMotorJointC0(motor, 0, bucket) or rest
				scale = self:EvaluateMotorScale(motor, 0, bucket)
			end

			local dirty = false
			if not key then
				local earliest
				for _, other in bucket do
					if
						not other.Disabled
						and type(other.Time) == "number"
						and (not earliest or other.Time < earliest.Time)
					then
						earliest = other
					end
				end

				local first = bucket[1]
				local lead = first and not first.Disabled and first.PhysicsLead
				if lead and typeof(lead.C0) == "CFrame" then
					key = GraphCurves.clone(lead)
					key.Button, key.KeyGroups, key.PhysicsLead, key.PhysicsTail = nil, nil, nil, nil
				else
					key = KeyframeDefaults.new(bucket, 0)
					key.C0, key.Position, key.Rotation = start, start.Position, start.Rotation
					if earliest then
						key.Parented, key.WorldCFrame, key.MasterWorld =
							earliest.Parented, earliest.WorldCFrame, earliest.MasterWorld
					else
						key.Parented = TimelineState.ParentingDefaults[motor] ~= false
						if not key.Parented then
							key.WorldCFrame = TimelineState.DefaultWorldPose[motor]
						end
					end

					key.WholePoseScale = {
						scale_x = scale and scale.scale_x or 1,
						scale_y = scale and scale.scale_y or 1,
						scale_z = scale and scale.scale_z or 1,
					}
				end

				key.Frame, key.Time, key.Motor, key.Part = 0, 0, motor, motor.Part1
				key.Channels = key.Channels or {}
				bucket[0] = key
				dirty = true
			end

			if not key.Channels and not key.GraphOnly then
				self:EnsureChannelsPopulated(key)
				for id, value in key.WholePoseScale or {} do
					key.Channels[id] = { Value = value }
				end

				dirty = true
			end

			key.Channels = key.Channels or {}
			local defaults = decomposeC0(start)
			for id, value in scale or {} do
				defaults[id] = value
			end

			local graphChannels = GraphCurves.compile(bucket).channels
			for _, id in CHANNEL_IDS do
				if not KeyframePolicy.channelAvailable(motor, id) then
					continue
				end

				if not key.Channels[id] then
					local point = key.GraphCurves and key.GraphCurves[id]
					key.Channels[id] = { Value = point and point.Value or defaults[id] }
					dirty = true
				end
			end

			local order = GraphCurves.rotationOrder(bucket)
			local ex, ey, ez = GraphCurves.euler(key.C0 or rest, order)
			local x, y, z = math.rad(ex), math.rad(ey), math.rad(ez)
			local rotation = { rot_x = math.deg(x), rot_y = math.deg(y), rot_z = math.deg(z) }
			for id in graphChannels do
				if not (key.GraphCurves and key.GraphCurves[id]) then
					local scalar = key.Channels[id]
					local value = scalar and scalar.Value or rotation[id]
					if value ~= nil then
						key.GraphCurves = key.GraphCurves or {}
						local point = GraphCurves.newPoint(key, id)
						point.Value = value
						point.RotationOrder = id:sub(1, 4) == "rot_" and order or nil
						key.GraphCurves[id] = point
						dirty = true
					end
				end
			end

			if key.GraphOnly then
				key.GraphOnly = nil
				dirty = true
			end

			if dirty then
				GraphCurves.invalidate(bucket)
				TimelineState._motorUniform[motor] = nil
				TimelineState._motorHasScale[motor] = nil
				if not evaluationState then
					self:CreateOrUpdateTimelineKeyframeButton(motor.Part1, motor, 0, nil, tostring)
					self:_addChannelDiamondAtFrame(motor, 0)
				end

				changed += 1
			end
		end

		if changed > 0 then
			TimelineState.LastPlaybackFrame = nil
			if not evaluationState then
				MainState.currentProjectSaved = false
			end
		end

		return changed
	end

	function Timeline:RecordChangedKeyframeForMotorAtCurrentTime(
		part,
		motor,
		c0,
		baselineC0,
		sanitizeName
	)
		c0 = Properties.basePose(motor, c0)
		baselineC0 = Properties.basePose(motor, baselineC0)
		local channels =
			self:GetChangedPoseChannels(motor, c0, TimelineState.CurrentTime, baselineC0)
		if #channels == 0 then
			return
		end

		return self:RecordPartialKeyframeForMotorAtCurrentTime(
			part,
			motor,
			c0,
			channels,
			sanitizeName
		)
	end

	function Timeline:RecordKeyframeForMotorAtCurrentTime(part, motor, c0, options, sanitizeName)
		if BlenderEdit.blocked() then
			return
		end

		options = typeof(options) == "table" and options or nil
		if
			not TimelineState._ImportingKeyframes
			and not TimelineState._LayerLoading
			and not (options and (options.ImportRaw or options.LayerRaw))
		then
			c0 = require("Mods").preparePoleRecord(
				motor,
				c0,
				options and options.Frame or self:TimeToFrame(TimelineState.CurrentTime)
			)
		end

		c0, options = require("Layers").prepareRecord(self, motor, c0, options)
		if not c0 then
			return
		end

		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		if not part or not motor or not c0 then
			return
		end

		local frameNumber = options and options.Frame or self:TimeToFrame(TimelineState.CurrentTime)
		const existing = TimelineState.Keyframes[motor]
		if
			frameNumber ~= 0
			and not (existing and existing[0])
			and KeyframePolicy.channelsEnabled()
			and not TimelineState._ImportingKeyframes
			and not TimelineState._LayerLoading
			and not (options and (options.ImportRaw or options.LayerRaw or options.PreserveGraph))
		then
			self:EnsureTransformChannelStarts(motor)
		end

		local bucket = self:GetMotorKeyframeBucket(motor)
		if not bucket then
			return
		end

		local order = GraphCurves.rotationOrder(bucket)
		local previousKey = bucket[frameNumber]
		bucket[frameNumber] = previousKey or KeyframeDefaults.new(bucket, frameNumber, options)

		local keyData = bucket[frameNumber]
		keyData.ChannelPoseC0 = nil

		keyData.Time = frameNumber / TimelineState.FPS
		keyData.C0 = c0
		keyData.Position = c0.Position
		keyData.Rotation = c0 - c0.Position
		keyData.Motor = motor
		keyData.Part = part
		keyData.Frame = frameNumber
		keyData.SanitizeName = sanitizeName
		if keyData.EasingStyle == nil then
			keyData.EasingStyle = Defaults.EasingStyle
		end

		if keyData.EasingDirection == nil then
			keyData.EasingDirection = Defaults.EasingDirection
		end

		if keyData.HandleType == nil then
			keyData.HandleType = Defaults.HandleType
		end

		if
			keyData.EasingStyle == "Bezier"
			and keyData.BezierPoints == nil
			and Defaults.BezierPoints
		then
			keyData.BezierPoints = {
				Defaults.BezierPoints[1],
				Defaults.BezierPoints[2],
				Defaults.BezierPoints[3],
				Defaults.BezierPoints[4],
			}
		end

		if require("Target").isAttachment(motor) then
			if keyData.CamAttachTarget == nil then
				local prior
				for _, candidate in bucket do
					if
						candidate ~= keyData
						and not candidate.Disabled
						and candidate.Time <= keyData.Time
						and (not prior or candidate.Time > prior.Time)
					then
						prior = candidate
					end
				end

				keyData.CamAttachTarget =
					GraphCurves.clone(prior and prior.CamAttachTarget or false)
			end

			keyData.EasingStyle = "Constant"
			keyData.Parented = true
			keyData.Channels, keyData.GraphCurves, keyData.WholePoseScale, keyData.ChannelPoseC0 =
				nil, nil, nil, nil
			TimelineState._motorUniform[motor] = nil
			self:CreateOrUpdateTimelineKeyframeButton(part, motor, frameNumber, nil, sanitizeName)
			return
		end

		if Properties.is(motor) then
			keyData.PropertyValue = options and options.PropertyValue
			if keyData.PropertyValue == nil then
				keyData.PropertyValue = Properties.decode(
					motor,
					c0,
					motor.Definition.kind ~= "CFrame"
							and Properties.readValue(motor.Rig, motor.PropertyId)
						or nil
				)
			end

			keyData.Channels, keyData.GraphCurves, keyData.WholePoseScale, keyData.ChannelPoseC0 =
				nil, nil, nil, nil
			keyData.Parented = true
			if motor.PropertyId == "CFrame" then
				require("Target").captureProperty(motor, keyData)
			end

			TimelineState._motorUniform[motor] = nil
			self:CreateOrUpdateTimelineKeyframeButton(part, motor, frameNumber, nil, sanitizeName)
			return
		end

		local decomposed = decomposeC0(c0)
		if order then
			decomposed.rot_x, decomposed.rot_y, decomposed.rot_z = GraphCurves.euler(c0, order)
		end

		local defaultSize = TimelineState.DefaultSize[part]
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			local scale = motor.InputScale
			decomposed.scale_x, decomposed.scale_y, decomposed.scale_z = scale.X, scale.Y, scale.Z
		elseif defaultSize and part:IsA("BasePart") then
			local currentSize = part.Size / Properties.scaleFactor(motor)
			decomposed.scale_x = currentSize.X / math.max(defaultSize.X, 1e-5)
			decomposed.scale_y = currentSize.Y / math.max(defaultSize.Y, 1e-5)
			decomposed.scale_z = currentSize.Z / math.max(defaultSize.Z, 1e-5)
		end

		require("Layers").recordScale(self, motor, decomposed, frameNumber, options)
		keyData.Channels = keyData.Channels or {}
		for _, id in ipairs(CHANNEL_IDS) do
			if not KeyframePolicy.channelAvailable(motor, id) then
				continue
			end

			keyData.Channels[id] = keyData.Channels[id] or {}
			keyData.Channels[id].Value = decomposed[id]
		end

		keyData.WholePoseScale = {
			scale_x = decomposed.scale_x,
			scale_y = decomposed.scale_y,
			scale_z = decomposed.scale_z,
		}

		if options and options.LayerParented ~= nil then
			keyData.Parented = options.LayerParented
		end

		if options and options.ImportRaw and TimelineState._ImportingKeyframes then
			keyData.Parented, keyData.WorldCFrame = true, nil
		else
			self:CaptureKeyframeParenting(motor, keyData, c0, options and options.SkipChildCapture)
		end

		if options and options.LayerWorldCFrame then
			keyData.WorldCFrame = options.LayerWorldCFrame
			keyData.MasterWorld = options.LayerMasterWorld
		end

		if not (options and options.PreserveGraph) then
			GraphCurves.recordPose(bucket, keyData, c0)
		end

		TimelineState._motorUniform[motor] = nil
		TimelineState._motorHasScale[motor] = true

		self:CreateOrUpdateTimelineKeyframeButton(part, motor, frameNumber, nil, sanitizeName)
		self:_addChannelDiamondAtFrame(motor, frameNumber)
		motionPath.markDirty()
	end

	function Timeline:RecordPartialKeyframeForMotorAtCurrentTime(
		part,
		motor,
		c0,
		channelIds,
		sanitizeName,
		options
	)
		if BlenderEdit.blocked() then
			return
		end

		if
			Properties.is(motor)
			or CameraRig.isTransform(motor)
			or not KeyframePolicy.channelsEnabled()
		then
			return self:RecordKeyframeForMotorAtCurrentTime(part, motor, c0, options, sanitizeName)
		end

		options = typeof(options) == "table" and options or nil
		if
			not TimelineState._ImportingKeyframes
			and not TimelineState._LayerLoading
			and not (options and (options.ImportRaw or options.LayerRaw))
		then
			c0 = require("Mods").preparePoleRecord(
				motor,
				c0,
				options and options.Frame or self:TimeToFrame(TimelineState.CurrentTime)
			)
		end

		c0, options = require("Layers").prepareRecord(self, motor, c0, options)
		if not c0 then
			return
		end

		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		if not part or not motor or not c0 or not channelIds then
			return
		end

		if require("Layers").has(TimelineState) and not (options and options.LayerRaw) then
			local transform = false
			for _, id in channelIds do
				if id:sub(1, 6) ~= "scale_" then
					transform = true
					break
				end
			end

			if transform then
				local expanded = {}
				for _, id in CHANNEL_IDS do
					if id:sub(1, 6) ~= "scale_" or table.find(channelIds, id) then
						table.insert(expanded, id)
					end
				end

				channelIds = expanded
			end
		end

		local available = {}
		for _, id in channelIds do
			if KeyframePolicy.channelAvailable(motor, id) then
				table.insert(available, id)
			end
		end

		channelIds = available
		if #channelIds == 0 then
			return
		end

		self:EnsureTransformChannelStarts(motor)

		local frameNumber = options and options.Frame or self:TimeToFrame(TimelineState.CurrentTime)
		local bucket = self:GetMotorKeyframeBucket(motor)
		if not bucket then
			return
		end

		bucket[frameNumber] = bucket[frameNumber]
			or KeyframeDefaults.new(bucket, frameNumber, options)
		local keyData = bucket[frameNumber]
		if
			keyData.ChannelPoseC0 ~= nil
			and typeof(keyData.C0) == "CFrame"
			and keyData.ChannelPoseC0 ~= keyData.C0
		then
			keyData.Channels = KeyframePolicy.poseChannels(keyData, keyData.C0)
		end

		keyData.C0 = keyData.C0 or c0
		keyData.ChannelPoseC0 = nil
		keyData.Time = frameNumber / TimelineState.FPS
		keyData.Motor = motor
		keyData.Part = part
		keyData.Frame = frameNumber
		keyData.SanitizeName = sanitizeName
		keyData.Channels = keyData.Channels or {}
		if keyData.EasingStyle == nil then
			keyData.EasingStyle = Defaults.EasingStyle
		end

		if keyData.EasingDirection == nil then
			keyData.EasingDirection = Defaults.EasingDirection
		end

		if keyData.HandleType == nil then
			keyData.HandleType = Defaults.HandleType
		end

		if
			keyData.EasingStyle == "Bezier"
			and keyData.BezierPoints == nil
			and Defaults.BezierPoints
		then
			keyData.BezierPoints = {
				Defaults.BezierPoints[1],
				Defaults.BezierPoints[2],
				Defaults.BezierPoints[3],
				Defaults.BezierPoints[4],
			}
		end

		local decomposed = decomposeC0(c0)
		local order = GraphCurves.rotationOrder(bucket)
		if order then
			decomposed.rot_x, decomposed.rot_y, decomposed.rot_z = GraphCurves.euler(c0, order)
		end

		local defaultSize = TimelineState.DefaultSize[part]
		if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
			local scale = motor.InputScale
			decomposed.scale_x, decomposed.scale_y, decomposed.scale_z = scale.X, scale.Y, scale.Z
		elseif defaultSize and part then
			local cs = part.Size / Properties.scaleFactor(motor)
			decomposed.scale_x = cs.X / math.max(defaultSize.X, 1e-5)
			decomposed.scale_y = cs.Y / math.max(defaultSize.Y, 1e-5)
			decomposed.scale_z = cs.Z / math.max(defaultSize.Z, 1e-5)
		end

		require("Layers").recordScale(self, motor, decomposed, frameNumber, options)
		local touchedScale = false
		for _, id in ipairs(channelIds) do
			keyData.Channels[id] = keyData.Channels[id] or {}
			keyData.Channels[id].Value = decomposed[id]
			if id == "scale_x" or id == "scale_y" or id == "scale_z" then
				touchedScale = true
				if keyData.WholePoseScale then
					keyData.WholePoseScale[id] = decomposed[id]
				end
			end
		end

		keyData.C0 = self:_reconstructC0FromKeyData(keyData) or keyData.C0
		if options and options.LayerParented ~= nil then
			keyData.Parented = options.LayerParented
		end

		self:CaptureKeyframeParenting(motor, keyData, c0)
		if options and options.LayerWorldCFrame then
			keyData.WorldCFrame = options.LayerWorldCFrame
			keyData.MasterWorld = options.LayerMasterWorld
		end

		if
			(KeyframePolicy.channelsEnabled() or order)
			and not (options and options.PreserveGraph)
		then
			GraphCurves.recordPose(bucket, keyData, c0, channelIds)
		end

		TimelineState._motorUniform[motor] = false
		if touchedScale then
			TimelineState._motorHasScale[motor] = true
		end

		self:CreateOrUpdateTimelineKeyframeButton(part, motor, frameNumber, nil, sanitizeName)
		self:_addChannelDiamondAtFrame(motor, frameNumber)
		motionPath.markDirty()
	end

	function Timeline:_reconstructC0FromKeyData(keyData)
		if not keyData or not keyData.Channels then
			return nil
		end

		local vals =
			decomposeC0(keyData.C0 or TimelineState.DefaultPose[keyData.Motor] or keyData.Motor.C0)
		for _, id in ipairs(CHANNEL_IDS) do
			local c = keyData.Channels[id]
			if c and c.Value ~= nil then
				vals[id] = c.Value
			end
		end

		local cf = reconstructC0(vals)
		local own = { [keyData.Frame or 0] = keyData }
		if GraphCurves.rotationOrder(own) then
			cf = GraphCurves.cframe(own, keyData.Time or 0, cf, keyData.Motor)
		end

		return cf
	end

	function Timeline:RebuildKeyframesForPart(part, motor, sanitizeName)
		if not part or not motor then
			return
		end

		local bucket = TimelineState.Keyframes[motor]
		if not bucket then
			return
		end

		for frameNumber in pairs(bucket) do
			self:CreateOrUpdateTimelineKeyframeButton(part, motor, frameNumber, nil, sanitizeName)
		end
	end

	local detachedKeyframeContainers = {}

	function Timeline:IsRetainedKeyframeButton(key)
		return key.Button
			and key.Button.Parent == detachedKeyframeContainers[key.Part]
			and key.Button.Parent ~= nil
	end

	local function releaseDetachedContainers()
		for _, bucket in TimelineState.Keyframes do
			for _, key in bucket do
				local button = key.Button
				if
					button
					and button.Parent
					and detachedKeyframeContainers[key.Part] == button.Parent
				then
					button.Parent = nil
				end
			end
		end

		for _, container in detachedKeyframeContainers do
			container:Destroy()
		end

		table.clear(detachedKeyframeContainers)
	end

	function Timeline:DetachKeyframeButtons()
		if next(detachedKeyframeContainers) then
			releaseDetachedContainers()
		end

		for part, row in TimelineState.TrackRows do
			local container = self:GetTrackKeyframesContainer(row)
			if container and container.Parent then
				detachedKeyframeContainers[part] = container
				container.Parent = nil
			end
		end

		for _, bucket in TimelineState.Keyframes do
			for _, key in bucket do
				local button = key.Button
				if
					button
					and button.Parent
					and button.Parent ~= detachedKeyframeContainers[key.Part]
				then
					button.Parent = nil
				end
			end
		end
	end

	function Timeline:RebuildAllTimelineKeyframeButtons(keyframeTemplate, sanitizeName)
		local retained, positions = {}, {}
		for part, container in detachedKeyframeContainers do
			local row = TimelineState.TrackRows[part]
			local content = row and row:FindFirstChild("Content")
			if content then
				local replacement = content:FindFirstChild("Keyframes")
				if replacement then
					replacement:Destroy()
				end

				container.Parent = content
				retained[part] = {
					container = container,
					template = container:FindFirstChild("KeyframeTemplate"),
				}
				detachedKeyframeContainers[part] = nil
			end
		end

		if next(detachedKeyframeContainers) then
			releaseDetachedContainers()
		end

		for motor, bucket in pairs(TimelineState.Keyframes) do
			if motor and motor.Parent and motor.Part1 then
				for frameNumber, keyData in pairs(bucket) do
					keyData.Frame = frameNumber
					keyData.Motor = motor
					keyData.Part = motor.Part1
					keyData.SanitizeName = sanitizeName

					local saved = retained[motor.Part1]
					local button = keyData.Button
					if
						saved
						and saved.template
						and button
						and button.Parent == saved.container
						and self:KeyframeInViewport(keyData, "Pose")
						and GraphCurves.hasVisibleKey(bucket, keyData)
						and not (
							self.IsKeyGroupCollapsed
							and self:IsKeyGroupCollapsed(keyData, "Pose")
						)
					then
						keyData.Template = saved.template
						buttonKeys[button] = keyData
						local x = positions[frameNumber]
						if x == nil then
							x = self:FrameToVisibleX(frameNumber)
							positions[frameNumber] = x
						end

						local position = UDim2.new(0, x, 0.5, 0)
						if button.Position ~= position then
							button.Position = position
						end

						local name = (
							(sanitizeName and sanitizeName(motor.Part1.Name)) or motor.Part1.Name
						)
							.. "_KF_"
							.. tostring(frameNumber)
						if button.Name ~= name then
							button.Name = name
						end
					else
						self:CreateOrUpdateTimelineKeyframeButton(
							motor.Part1,
							motor,
							frameNumber,
							nil,
							sanitizeName
						)
					end
				end
			end
		end

		for _, bucket in TimelineState.Keyframes do
			for _, keyData in bucket do
				if keyData.Button and not keyData.Button.Parent then
					keyData.Button:Destroy()
					keyData.Button = nil
				end
			end
		end

		self:RefreshAllKeyframeVisuals()
		self:UpdateDeleteButtonState()
	end
end
