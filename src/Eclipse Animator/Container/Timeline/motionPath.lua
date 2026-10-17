--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local GraphCurves = require("GraphCurves")
local CameraRig = require("CameraRig")
local MotionPath = {}
local heartbeat, update

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local State = require("RawState")
local MainState = require("State")
local Defaults = require("Defaults")
local Interp = require("Interp")
local LimbIK = require("LimbIK")
local Parenting = require("Parenting")
local KeyframePolicy = require("Policy")
local HeadStabilizer = require("HeadStabilizer")
local Preferences = require("Preferences")
local TimelineState = State.Timeline

local TINTS = {
	Past = Color3.fromRGB(255, 0, 0),
	Future = Color3.fromRGB(0, 255, 0),
	Marker = Color3.fromRGB(240, 240, 245),
	Tick = Color3.fromRGB(255, 255, 255),
}

local LINE_THICKNESS = 3
local SMALL_LINE_THICKNESS = 2
local SMALL_PATH_PIXELS = 140
local KEY_PIXELS = 2.5
local BEZIER_KEY_PIXELS = 3
local SELECTED_KEY_PIXELS = 4.5
local HOVER_KEY_PIXELS = 5.5
local SELECTED_TINT = Color3.fromRGB(0, 255, 255)
local HANDLE_TINT = Color3.fromRGB(255, 214, 64)
local HANDLE_PIXELS = 8
local TICK_PIXELS = 1.3
local TICK_SPACING = 9
local TICK_TRANSPARENCY = 0.45
local LABEL_SPACING = 34
local GRAB_PIXELS = 14
local HOST_NAME = "EclipseAnimator_MotionPath"
local SAMPLE_STEP = 1
local TICK_COUNT = 6

local watchers = {}
local plotCache = {}
local trail = nil
local lookahead = nil
local markers = {}
local markerPool = {}
local anchors = {}
local anchorPool = {}
local tickMarkers = {}
local tickPool = {}
local hovered = nil
local labelMode = nil
local host = nil
local lastTrackedTime = nil
local lastRangeMode, lastRangeCount, lastRangeStart, lastRangeEnd
local lastPaintedFrame
local markerRevision = 0
local hoverMemo
local lastEasingStyle = nil
local lastEasingDir = nil
local lastBezierFingerprint = nil
local lastHandleType = nil
local dirty = false
local rebuildJob
local rebuildDeadline = 0
local REBUILD_BUDGET = 0.003

local function checkpoint()
	if rebuildJob and coroutine.running() == rebuildJob and os.clock() >= rebuildDeadline then
		coroutine.yield()
	end
end

local markerBindings = {}
local selected = nil
local selectedBasis = nil
local handleIn = nil
local handleOut = nil
local handleLine = nil
local draggingHandle = nil
local dragContext = nil
local inputHooked = false
local inputConnections = {}
local selectMarkerBinding

local function reattach()
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end

	if host and host.Parent == cam then
		return true
	end

	for _, child in cam:GetChildren() do
		if child.Name == HOST_NAME then
			child:Destroy()
		end
	end

	host = Instance.new("Folder")
	host.Name = HOST_NAME
	host.Parent = cam

	trail = Instance.new("WireframeHandleAdornment")
	trail.Adornee = workspace.Terrain
	trail.Color3 = TINTS.Past
	trail.Thickness = LINE_THICKNESS
	trail.AlwaysOnTop = true
	trail.ZIndex = 0
	trail.Parent = host

	lookahead = Instance.new("WireframeHandleAdornment")
	lookahead.Adornee = workspace.Terrain
	lookahead.Color3 = TINTS.Future
	lookahead.Thickness = LINE_THICKNESS
	lookahead.AlwaysOnTop = true
	lookahead.ZIndex = 0
	lookahead.Parent = host

	return true
end

local function recycleMarkers()
	for _, marker in markers do
		marker.Parent = nil
		table.insert(markerPool, marker)
	end

	table.clear(markers)
	for _, anchor in anchors do
		anchor.Parent = nil
		table.insert(anchorPool, anchor)
	end

	table.clear(anchors)
	for _, marker in tickMarkers do
		marker.Parent = nil
		table.insert(tickPool, marker)
	end

	table.clear(tickMarkers)
end

local function getAnchorPart()
	local anchor = table.remove(anchorPool)
	if not anchor then
		anchor = Instance.new("Part")
		anchor.Name = "EclipseMotionPathAnchor"
		anchor.Size = Vector3.new(0.01, 0.01, 0.01)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Locked = true
		anchor.CastShadow = false
		anchor.Massless = true
	end

	return anchor
end

local function attachBillboard(anchor, frame)
	local billboard = anchor:FindFirstChild("MotionPathBillboard")
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "MotionPathBillboard"
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(34, 14)
		billboard.SizeOffset = Vector2.new(0.62, 0.62)
		billboard.Adornee = anchor
		local label = Instance.new("TextLabel")
		label.Name = "Number"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.TextSize = 12
		label.TextColor3 = Color3.fromRGB(240, 240, 245)
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.25
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = billboard
		billboard.Parent = anchor
	end

	if billboard:GetAttribute("LastFrame") ~= frame then
		local label = billboard:FindFirstChild("Number")
		if label then
			label.Text = string.format("%.1f", math.round(frame * 10) / 10):gsub("%.0$", "")
		end

		billboard:SetAttribute("LastFrame", frame)
	end
end

local function faceCameraCF(position)
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - position).Magnitude > 0.05 then
		return CFrame.lookAt(position, cam.CFrame.Position)
	end

	return CFrame.new(position)
end

local function dropKeyframeMarker(at, frameNumber, motor, item)
	local box = table.remove(markerPool)
	if not box then
		box = Instance.new("SphereHandleAdornment")
		box.Adornee = workspace.Terrain
		box.AlwaysOnTop = true
		box.ZIndex = 1
	end

	markerBindings[box] = { item = item, motor = motor, frame = frameNumber }

	local bucket = motor and TimelineState.Keyframes[motor]
	local kd = bucket and bucket[frameNumber]
	local style = kd and kd.EasingStyle or Defaults.EasingStyle
	if typeof(style) == "EnumItem" then
		style = style.Name
	end

	markerBindings[box].bezier = style == "Bezier"
	box.CFrame = CFrame.new(at)
	box.Radius = 0.02
	box.Color3 = TINTS.Marker
	box.Transparency = 0
	box.Parent = host
	table.insert(markers, box)

	local anchor = getAnchorPart()
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = host
	table.insert(anchors, anchor)
	attachBillboard(anchor, frameNumber)
	markerBindings[box].anchor = anchor
	return box
end

local function dropTickMarker(at)
	local box = table.remove(tickPool)
	if not box then
		box = Instance.new("SphereHandleAdornment")
		box.Adornee = workspace.Terrain
		box.AlwaysOnTop = true
		box.ZIndex = 1
	end

	box.CFrame = CFrame.new(at)
	box.Radius = 0.01
	box.Color3 = TINTS.Tick
	box.Transparency = TICK_TRANSPARENCY
	box.Parent = host
	table.insert(tickMarkers, box)
	return box
end

local CHANNEL_IDS_MP = {
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
local QROT_IDS_MP = { "qrot_w", "qrot_x", "qrot_y", "qrot_z" }

local function decomposeCFrameToChannels(cf)
	local pos = cf.Position
	local _, _, _, m11, m12, m13, m21, m22, m23, m31, m32, m33 = cf:GetComponents()
	local trace = m11 + m22 + m33
	local qw, qx, qy, qz

	if trace > 0 then
		local s = math.sqrt(trace + 1.0) * 2
		qw = 0.25 * s
		qx = (m32 - m23) / s
		qy = (m13 - m31) / s
		qz = (m21 - m12) / s
	elseif m11 > m22 and m11 > m33 then
		local s = math.sqrt(1.0 + m11 - m22 - m33) * 2
		qw = (m32 - m23) / s
		qx = 0.25 * s
		qy = (m12 + m21) / s
		qz = (m13 + m31) / s
	elseif m22 > m33 then
		local s = math.sqrt(1.0 + m22 - m11 - m33) * 2
		qw = (m13 - m31) / s
		qx = (m12 + m21) / s
		qy = 0.25 * s
		qz = (m23 + m32) / s
	else
		local s = math.sqrt(1.0 + m33 - m11 - m22) * 2
		qw = (m21 - m12) / s
		qx = (m13 + m31) / s
		qy = (m23 + m32) / s
		qz = 0.25 * s
	end

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

local function reconstructCFrameFromChannels(values)
	local qw = values.qrot_w or 1
	local qx = values.qrot_x or 0
	local qy = values.qrot_y or 0
	local qz = values.qrot_z or 0
	local mag = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
	if mag > 0 then
		qw, qx, qy, qz = qw / mag, qx / mag, qy / mag, qz / mag
	else
		qw = 1
	end

	local px = values.loc_x or 0
	local py = values.loc_y or 0
	local pz = values.loc_z or 0
	return CFrame.new(
		px,
		py,
		pz,
		1 - 2 * (qy * qy + qz * qz),
		2 * (qx * qy - qz * qw),
		2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw),
		1 - 2 * (qx * qx + qz * qz),
		2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw),
		2 * (qy * qz + qx * qw),
		1 - 2 * (qx * qx + qy * qy)
	)
end

local function evalC0AtTime(motor, time)
	local bucket = TimelineState.Keyframes[motor]
	if MainState.Timeline and MainState.Timeline.EvaluateMotorC0 then
		return (MainState.Timeline:EvaluateMotorC0(motor, time))
	end

	if not bucket or not next(bucket) then
		return TimelineState.DefaultPose[motor] or motor.C0
	end

	local defaultC0 = TimelineState.DefaultPose[motor] or motor.C0 or CFrame.new()
	local defaultDecomposed = nil

	local values = {}
	local prevPickedData = {}
	local nextPickedData = {}

	for _, chId in ipairs(CHANNEL_IDS_MP) do
		local pTime, pValue, pData = nil, nil, nil
		local nTime, nValue, nData = nil, nil, nil

		for _, data in pairs(bucket) do
			if data and data.Time ~= nil and data.Channels then
				local ch = data.Channels[chId]
				if ch and ch.Value ~= nil then
					local t = data.Time
					if t <= time and (not pTime or t > pTime) then
						pTime, pValue, pData = t, ch.Value, data
					end

					if t >= time and (not nTime or t < nTime) then
						nTime, nValue, nData = t, ch.Value, data
					end
				end
			end
		end

		if pData and nData and pTime ~= nTime and nTime > pTime then
			local rawAlpha = math.clamp((time - pTime) / (nTime - pTime), 0, 1)
			values[chId] = Interp.channel(bucket, pData, nData, rawAlpha, chId, pValue, nValue, nil)
		elseif pValue ~= nil then
			values[chId] = pValue
		elseif nValue ~= nil then
			values[chId] = nValue
		elseif string.sub(chId, 1, 6) == "scale_" then
			values[chId] = 1
		else
			if not defaultDecomposed then
				defaultDecomposed = decomposeCFrameToChannels(defaultC0)
			end

			values[chId] = defaultDecomposed[chId] or 0
		end

		prevPickedData[chId] = pData
		nextPickedData[chId] = nData
	end

	do
		local pData = prevPickedData.qrot_w
		local nData = nextPickedData.qrot_w
		if pData and nData and pData ~= nData then
			local pCh = pData.Channels
			local nCh = nData.Channels
			if pCh and nCh then
				local pqw = pCh.qrot_w and pCh.qrot_w.Value or 0
				local pqx = pCh.qrot_x and pCh.qrot_x.Value or 0
				local pqy = pCh.qrot_y and pCh.qrot_y.Value or 0
				local pqz = pCh.qrot_z and pCh.qrot_z.Value or 0
				local nqw = nCh.qrot_w and nCh.qrot_w.Value or 0
				local nqx = nCh.qrot_x and nCh.qrot_x.Value or 0
				local nqy = nCh.qrot_y and nCh.qrot_y.Value or 0
				local nqz = nCh.qrot_z and nCh.qrot_z.Value or 0
				local dot = pqw * nqw + pqx * nqx + pqy * nqy + pqz * nqz
				if dot < 0 then
					local pTime = pData.Time or 0
					local nTime = nData.Time or 0
					if nTime > pTime then
						local rawAlpha = math.clamp((time - pTime) / (nTime - pTime), 0, 1)
						values.qrot_w =
							Interp.channel(bucket, pData, nData, rawAlpha, "qrot_w", pqw, -nqw, nil)
						values.qrot_x =
							Interp.channel(bucket, pData, nData, rawAlpha, "qrot_x", pqx, -nqx, nil)
						values.qrot_y =
							Interp.channel(bucket, pData, nData, rawAlpha, "qrot_y", pqy, -nqy, nil)
						values.qrot_z =
							Interp.channel(bucket, pData, nData, rawAlpha, "qrot_z", pqz, -nqz, nil)
					end
				end
			end
		end
	end

	do
		local pD, nD = nil, nil
		for _, dataK in pairs(bucket) do
			if dataK and dataK.C0 and dataK.Time then
				if dataK.Time <= time and (not pD or dataK.Time > pD.Time) then
					pD = dataK
				end

				if dataK.Time >= time and (not nD or dataK.Time < nD.Time) then
					nD = dataK
				end
			end
		end

		local manual = (pD and pD.PathTangentOut ~= nil) or (nD and nD.PathTangentIn ~= nil)

		if not manual then
			local cpD, cnD = nil, nil
			for _, chId in ipairs(CHANNEL_IDS_MP) do
				cpD = cpD or prevPickedData[chId]
				cnD = cnD or nextPickedData[chId]
			end

			local locConsistent = true
			for _, chId in ipairs({ "loc_x", "loc_y", "loc_z" }) do
				local pp = prevPickedData[chId]
				local nn = nextPickedData[chId]
				if (pp and pp ~= cpD) or (nn and nn ~= cnD) then
					locConsistent = false
					break
				end
			end

			if locConsistent then
				pD, nD = cpD, cnD
			else
				pD, nD = nil, nil
			end
		end

		if
			pD
			and nD
			and pD ~= nD
			and pD.C0
			and nD.C0
			and not Interp.usesAutomaticBezier(pD, nD)
			and pD.Time
			and nD.Time
			and nD.Time > pD.Time
		then
			local rawAlpha = math.clamp((time - pD.Time) / (nD.Time - pD.Time), 0, 1)
			local cf = Interp.cframe(bucket, pD, nD, rawAlpha, "C0", nil)
			if cf then
				values.loc_x = cf.X
				values.loc_y = cf.Y
				values.loc_z = cf.Z
			end
		end
	end

	if
		motor:GetAttribute("EclipseChannelDisabledAny")
		and (
			(typeof(motor) == "table" and motor.IsEclipseR6Control)
			or (HeadStabilizer.isEligible(motor) and HeadStabilizer.isEnabled(motor, time))
		)
	then
		local defaults = decomposeCFrameToChannels(defaultC0)
		for _, channel in CHANNEL_IDS_MP do
			if motor:GetAttribute("EclipseChannelDisabled_" .. channel) then
				values[channel] = defaults[channel]
			end
		end
	end

	return reconstructCFrameFromChannels(values)
end

local function buildMotorMap(rig)
	return Parenting.buildMotorMap(Parenting.collectMotors(rig))
end

local function buildChain(motor, motorMap)
	local chain = { motor }
	local current = motor
	local visited = { [motor] = true }
	while current.Part0 do
		local parent = motorMap[Parenting.realPart0(current)]
		if not parent or visited[parent] then
			break
		end

		visited[parent] = true
		table.insert(chain, parent)
		current = parent
	end

	return chain
end

local function pathFrame(motor, world, time, rig)
	if not world then
		return nil
	end

	if CameraRig.isTransform(motor) then
		local depth = rig:GetAttribute("EclipseCameraTransferRig") and 0 or CameraRig.DEPTH
		return world * CFrame.new(0, 0, -depth)
	end

	local chain = LimbIK.chain(rig, motor)
	if
		not chain
		or chain.owner ~= motor
		or chain.limb ~= "Leg"
		or not (LimbIK.isEnabled(motor, time) or LimbIK.transition(motor, time))
	then
		return world
	end

	if chain.kind == "R6" then
		return world * CFrame.new(0, -motor.Part1.Size.Y * 0.5, 0)
	end

	if chain.kind == "R15" then
		return world * motor.C1
	end

	return world
end

local function evalChainAtTime(chain, time, rig, sampling)
	if sampling then
		checkpoint()
		local poses = sampling.samples[time]
		if not poses then
			local localValues = {}

			local function evaluate(m, t)
				local at = localValues[t]
				if not at then
					at = {}
					localValues[t] = at
				end

				if at[m] == nil then
					at[m] = evalC0AtTime(m, t)
				end

				return at[m]
			end

			local worlds = LimbIK.evaluate(rig, time, evaluate)
			poses = {}
			for motor in sampling.motors do
				poses[motor] = worlds and worlds[motor] or sampling.evaluator.worldAt(motor, time)
			end

			sampling.samples[time] = poses
		end

		return pathFrame(chain[1], poses[chain[1]], time, rig)
	end

	local worlds = LimbIK.evaluate(rig, time, evalC0AtTime)
	if worlds and worlds[chain[1]] then
		return pathFrame(chain[1], worlds[chain[1]], time, rig)
	end

	if not chain[#chain].Part0 then
		return nil
	end

	local evaluator = Parenting.newEvaluator(
		chain,
		KeyframePolicy.activeTracks(TimelineState.Keyframes),
		TimelineState.DefaultPose,
		TimelineState.DefaultWorldPose,
		TimelineState.ParentingDefaults,
		evalC0AtTime
	)
	return pathFrame(chain[1], evaluator.worldAt(chain[1], time), time, rig)
end

local function buildItemEntry(item, motorMap, sampling, previous, changed)
	local motor = item.fetchMotor and item:fetchMotor() or nil
	if not motor or not motor.Part0 then
		return nil
	end

	local bucket = TimelineState.Keyframes[motor]
	if not bucket and not (typeof(motor) == "table" and motor.IsEclipseR6Control) then
		return nil
	end

	local frames = {}
	for f, data in bucket or {} do
		if data and data.C0 and data.Time then
			table.insert(frames, f)
		end
	end

	table.sort(frames)
	local authoredFrames = table.clone(frames)

	if typeof(motor) == "table" and motor.IsEclipseR6Control then
		local present = {}
		for _, f in frames do
			present[f] = true
		end

		local rig = item.grandpa.linkedRigInstance
		for _, dependency in Parenting.collectMotors(rig) do
			for f, data in TimelineState.Keyframes[dependency] or {} do
				if data and data.C0 and data.Time and not present[f] then
					present[f] = true
					table.insert(frames, f)
				end
			end
		end

		table.sort(frames)
	end

	if #frames == 0 then
		return nil
	end

	local chain = buildChain(motor, motorMap)

	local function sample(time)
		return evalChainAtTime(chain, time, item.grandpa.linkedRigInstance, sampling)
	end

	local fps = TimelineState.FPS
	local anchor = chain[#chain].Part0
	local entry = {
		visualMarkers = previous and previous.visualMarkers,
		visualTicks = previous and previous.visualTicks,
		intervals = {},
		segments = {},
		markerPositions = {},
		tickPositions = {},
		anchor = anchor,
		anchorCFrame = anchor and anchor.CFrame or nil,
		motor = motor,
		chain = chain,
		rig = item.grandpa.linkedRigInstance,
	}

	local oldMarkers = {}
	if previous and changed then
		for _, mark in previous.markerPositions do
			oldMarkers[mark.frame] = mark
		end
	end

	for _, f in authoredFrames do
		local old = oldMarkers[f]
		if old and (f < changed[1] or f > changed[2]) then
			table.insert(entry.markerPositions, old)
			continue
		end

		local cf = sample(f / fps)
		if cf then
			table.insert(entry.markerPositions, { pos = cf.Position, frame = f })
		end
	end

	if #frames == 1 then
		return entry
	end

	for i = 1, #frames - 1 do
		checkpoint()
		local fHead, fTail = frames[i], frames[i + 1]
		local interval = previous and previous.intervals and previous.intervals[i]
		if
			not (
				changed
				and interval
				and interval.first == fHead
				and interval.last == fTail
				and (fTail <= changed[1] or fHead >= changed[2])
			)
		then
			interval = { first = fHead, last = fTail, segments = {}, ticks = {} }
			local headCF = sample(fHead / fps)
			if headCF then
				local prev = headCF.Position
				local frame = fHead
				while frame < fTail do
					frame = math.min(fTail, frame + SAMPLE_STEP)
					local cf = sample(frame / fps)
					if cf then
						table.insert(
							interval.segments,
							{ prev, cf.Position, frame, math.max(fHead, frame - SAMPLE_STEP) }
						)
						prev = cf.Position
					end
				end

				for tick = 1, TICK_COUNT - 1 do
					local frame = fHead + (fTail - fHead) * tick / TICK_COUNT
					local cf = sample(frame / fps)
					if cf then
						table.insert(interval.ticks, { pos = cf.Position, frame = frame })
					end
				end
			end
		end

		entry.intervals[i] = interval
		for _, segment in interval.segments do
			table.insert(entry.segments, segment)
			checkpoint()
		end

		for _, pos in interval.ticks do
			table.insert(entry.tickPositions, pos)
		end
	end

	return entry
end

local function rebuildCache(changed)
	local result, rigs = {}, {}
	for item in watchers do
		local rig = item.grandpa and item.grandpa.linkedRigInstance
		local motor = item.fetchMotor and item:fetchMotor()
		if rig and motor then
			local sampling = rigs[rig]
			if not sampling then
				local motors = Parenting.collectMotors(rig)
				sampling = { map = Parenting.buildMotorMap(motors), motors = {}, samples = {} }
				sampling.evaluator = Parenting.newEvaluator(
					motors,
					KeyframePolicy.activeTracks(TimelineState.Keyframes),
					TimelineState.DefaultPose,
					TimelineState.DefaultWorldPose,
					TimelineState.ParentingDefaults,
					evalC0AtTime
				)
				rigs[rig] = sampling
			end

			sampling.motors[motor] = true
		end

		checkpoint()
	end

	for item in watchers do
		local rig = item.grandpa and item.grandpa.linkedRigInstance
		local sampling = rig and rigs[rig]
		if sampling then
			local entry =
				buildItemEntry(item, sampling.map, sampling, changed and plotCache[item], changed)
			if entry then
				result[item] = entry
			end
		end

		checkpoint()
	end

	return result
end

local function manipulating()
	local axis = MainState.Axis
	if draggingHandle then
		return true
	end

	if not axis then
		return false
	end

	return (axis.IsHoldingAxis and axis:IsHoldingAxis())
		or (axis.IsBlenderGrabMode and axis:IsBlenderGrabMode())
		or (axis.IsBlenderRotateMode and axis:IsBlenderRotateMode())
end

local function applyPoseNow(motor)
	if dirty and MainState.Timeline then
		local target = motor or (selected and selected.motor)
		if target then
			GraphCurves.invalidate(TimelineState.Keyframes[target])
		end
	end

	if MainState.Timeline and MainState.currentRig then
		pcall(function()
			MainState.Timeline:ApplyPoseAtTime(MainState.currentRig, TimelineState.CurrentTime)
		end)
	end
end

local function hideHandles()
	if handleIn then
		handleIn.Visible = false
	end

	if handleOut then
		handleOut.Visible = false
	end

	if handleLine then
		handleLine:Clear()
	end
end

local beginHandleDrag

local function resolveKey(motor, frame, original)
	local bucket = TimelineState.Keyframes[motor]
	if not bucket then
		return nil
	end

	for _, key in bucket do
		if key == original then
			return key
		end
	end

	return bucket[frame]
end

local function flushHandleInput()
	local ctx = dragContext
	if not ctx or not ctx.pendingOffset then
		return false
	end

	local value = ctx.parentRot:VectorToObjectSpace(ctx.pendingOffset) * 3
	ctx.pendingOffset = nil
	if draggingHandle == "Out" then
		ctx.kd.PathTangentOut = value
	else
		ctx.kd.PathTangentIn = -value
	end

	ctx.kd.HandleType = "Vector"
	MainState.currentProjectSaved = false
	dirty = true
	applyPoseNow(ctx.motor)
	return true
end

local function commitHandleDrag()
	if not draggingHandle or not dragContext then
		return
	end

	local ctx = dragContext
	rebuildJob = nil
	flushHandleInput()
	dirty = true
	draggingHandle = nil
	dragContext = nil

	local kd = ctx.kd
	local afterOut = kd.PathTangentOut
	local afterIn = kd.PathTangentIn
	local afterHandleType = kd.HandleType
	if
		afterOut == ctx.beforeOut
		and afterIn == ctx.beforeIn
		and afterHandleType == ctx.beforeHandleType
	then
		return
	end

	local function apply(outValue, inValue, handleType)
		local key = resolveKey(ctx.motor, ctx.frame, kd)
		if not key then
			return
		end

		key.PathTangentOut = outValue
		key.PathTangentIn = inValue
		key.HandleType = handleType
		MainState.currentProjectSaved = false
		dirty = true
		applyPoseNow(ctx.motor)
	end

	require("History").record(function()
		apply(ctx.beforeOut, ctx.beforeIn, ctx.beforeHandleType)
	end, function()
		apply(afterOut, afterIn, afterHandleType)
	end, "Adjust motion path handle", ctx.frame)
end

local function ensureHandles()
	if handleIn and handleIn.Parent == host then
		return
	end

	local function makeHandle(name)
		local h = Instance.new("BoxHandleAdornment")
		h.Name = name
		h.Adornee = workspace.Terrain
		h.AlwaysOnTop = true
		h.ZIndex = 2
		h.Size = Vector3.one * 0.03
		h.Color3 = HANDLE_TINT
		h.Transparency = 0
		h.Visible = false
		h.Parent = host
		return h
	end

	handleIn = makeHandle("PathHandleIn")
	handleOut = makeHandle("PathHandleOut")

	handleLine = Instance.new("WireframeHandleAdornment")
	handleLine.Name = "PathHandleLine"
	handleLine.Adornee = workspace.Terrain
	handleLine.Color3 = Color3.fromRGB(235, 235, 235)
	handleLine.Thickness = 3
	handleLine.AlwaysOnTop = true
	handleLine.ZIndex = 2
	handleLine.Parent = host
end

local function findNeighborKeyframes(bucket, frame)
	local prevKd, prevFrame = nil, nil
	local nextKd, nextFrame = nil, nil
	for f, data in pairs(bucket) do
		if data and data.Time and f ~= frame then
			if f < frame and (not prevFrame or f > prevFrame) then
				prevFrame, prevKd = f, data
			end

			if f > frame and (not nextFrame or f < nextFrame) then
				nextFrame, nextKd = f, data
			end
		end
	end

	return prevKd, nextKd
end

local function updateHandles()
	if not selected then
		hideHandles()
		return
	end

	local entry = plotCache[selected.item]
	local bucket = TimelineState.Keyframes[selected.motor]
	local kd = bucket and bucket[selected.frame]
	if not entry or not entry.chain or not kd or not kd.C0 then
		selected = nil
		selectedBasis = nil
		hideHandles()
		return
	end

	local t = selected.frame / TimelineState.FPS
	local partCF = evalChainAtTime(entry.chain, t, entry.rig)
	if not partCF then
		hideHandles()
		return
	end

	local limb = LimbIK.chain(entry.rig, selected.motor)
	if
		limb
		and limb.limb == "Leg"
		and (LimbIK.isEnabled(selected.motor, t) or LimbIK.transition(selected.motor, t))
	then
		selectedBasis = nil
		hideHandles()
		return
	end

	local keyPos = partCF.Position
	local parentCF = partCF * entry.chain[1].C1 * kd.C0:Inverse()
	local parentRot = parentCF.Rotation
	selectedBasis = { keyPos = keyPos, parentRot = parentRot }

	ensureHandles()
	handleLine:Clear()

	local prevKd, nextKd = findNeighborKeyframes(bucket, selected.frame)

	if nextKd and nextKd.C0 then
		local m0 = Interp.tangents(bucket, kd, nextKd, nil)
		local outPos = if draggingHandle == "Out"
				and dragContext
				and dragContext.pendingOffset
			then dragContext.keyPos + dragContext.pendingOffset
			else keyPos + parentRot:VectorToWorldSpace(m0) / 3
		handleOut.CFrame = faceCameraCF(outPos)
		handleOut.Visible = true
		handleLine:AddLine(keyPos, outPos)
	else
		handleOut.Visible = false
	end

	if prevKd and prevKd.C0 then
		local _, m1 = Interp.tangents(bucket, prevKd, kd, nil)
		local inPos = if draggingHandle == "In"
				and dragContext
				and dragContext.pendingOffset
			then dragContext.keyPos + dragContext.pendingOffset
			else keyPos - parentRot:VectorToWorldSpace(m1) / 3
		handleIn.CFrame = faceCameraCF(inPos)
		handleIn.Visible = true
		handleLine:AddLine(keyPos, inPos)
	else
		handleIn.Visible = false
	end
end

local function hookInput()
	if inputHooked then
		return
	end

	inputHooked = true

	local function screenDistance(cam, worldPos, mouse)
		local sp, onScreen = cam:WorldToViewportPoint(worldPos)
		if not onScreen or sp.Z <= 0 then
			return math.huge
		end

		return (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
	end

	inputConnections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if not next(watchers) then
			return
		end

		if Preferences.get("MotionPathEditing") == false then
			if selected then
				selected, selectedBasis, dirty = nil, nil, true
			end

			return
		end

		commitHandleDrag()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		local mp = UserInputService:GetMouseLocation()
		local mouse = Vector2.new(mp.X, mp.Y)

		if selected and selectedBasis then
			if
				handleOut
				and handleOut.Visible
				and screenDistance(cam, handleOut.CFrame.Position, mouse) < 14
			then
				beginHandleDrag("Out")
				return
			end

			if
				handleIn
				and handleIn.Visible
				and screenDistance(cam, handleIn.CFrame.Position, mouse) < 14
			then
				beginHandleDrag("In")
				return
			end
		end

		local best = nil
		local bestDist = 14
		for box, binding in pairs(markerBindings) do
			if box.Parent == host and box.Visible then
				local d = screenDistance(cam, box.CFrame.Position, mouse)
				if d < bestDist then
					bestDist = d
					best = binding
				end
			end
		end

		if best and selectMarkerBinding then
			selectMarkerBinding(best)
		elseif selected then
			selected = nil
			selectedBasis = nil
			dirty = true
		end
	end)

	inputConnections.InputChanged = UserInputService.InputChanged:Connect(function(input)
		if not draggingHandle or not dragContext then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		local mp = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mp.X, mp.Y)
		local planeNormal = cam.CFrame.LookVector
		local denom = ray.Direction:Dot(planeNormal)
		if math.abs(denom) < 1e-6 then
			return
		end

		local dist = (dragContext.keyPos - ray.Origin):Dot(planeNormal) / denom
		local hit = ray.Origin + ray.Direction * dist
		local worldOff = hit - dragContext.keyPos

		dragContext.pendingOffset = worldOff
	end)

	inputConnections.InputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		commitHandleDrag()
	end)

	inputConnections.WindowFocusReleased = UserInputService.WindowFocusReleased:Connect(function()
		commitHandleDrag()
	end)
end

beginHandleDrag = function(which)
	if not selected or not selectedBasis then
		return
	end

	local bucket = TimelineState.Keyframes[selected.motor]
	local kd = bucket and bucket[selected.frame]
	if not kd then
		return
	end

	rebuildJob = nil
	local before, after = findNeighborKeyframes(bucket, selected.frame)
	local changed = {
		before and before.Time * TimelineState.FPS or selected.frame,
		after and after.Time * TimelineState.FPS or selected.frame,
	}

	if next(TimelineState.CurveModifiers or {}) or require("Layers").has(TimelineState) then
		changed = nil
	end

	draggingHandle = which
	dragContext = {
		changed = changed,
		kd = kd,
		keyPos = selectedBasis.keyPos,
		parentRot = selectedBasis.parentRot,
		beforeOut = kd.PathTangentOut,
		beforeIn = kd.PathTangentIn,
		beforeHandleType = kd.HandleType,
		motor = selected.motor,
		frame = selected.frame,
	}
end

selectMarkerBinding = function(binding)
	if draggingHandle then
		return
	end

	if selected and selected.motor == binding.motor and selected.frame == binding.frame then
		selected = nil
		selectedBasis = nil
	else
		selected = { item = binding.item, motor = binding.motor, frame = binding.frame }
	end

	dirty = true
end

local function pixelUnit(cam, position)
	local depth = math.max(0.05, -cam.CFrame:PointToObjectSpace(position).Z)
	return depth * 2 * math.tan(math.rad(cam.FieldOfView) * 0.5) / math.max(1, cam.ViewportSize.Y)
end

local function numbersMode()
	local value = Preferences.get("MotionPathNumbers")
	return if value == 2 or value == 3 then value else 1
end

local function layout(skipKeys)
	local cam = workspace.CurrentCamera
	if not cam or not host then
		return
	end

	labelMode = numbersMode()
	local shown = {}

	local function screen(position)
		local point, visible = cam:WorldToViewportPoint(position)
		return Vector2.new(point.X, point.Y), visible and point.Z > 0
	end

	local function cell(point)
		return math.floor(point.X / LABEL_SPACING), math.floor(point.Y / LABEL_SPACING)
	end

	local function remember(point)
		local x, y = cell(point)
		shown[x] = shown[x] or {}
		shown[x][y] = shown[x][y] or {}
		table.insert(shown[x][y], point)
	end

	local function roomFor(point)
		local x, y = cell(point)
		for dx = -1, 1 do
			local column = shown[x + dx]
			if column then
				for dy = -1, 1 do
					for _, other in column[y + dy] or {} do
						if (other - point).Magnitude < LABEL_SPACING then
							return false
						end
					end
				end
			end
		end

		return true
	end

	if not skipKeys then
		local order = {}
		for _, box in markers do
			local binding = markerBindings[box]
			if not binding or box.Parent ~= host or not box.Visible then
				continue
			end

			local isSelected = selected ~= nil
				and selected.motor == binding.motor
				and selected.frame == binding.frame
			local isHovered = hovered == box
			local unit = pixelUnit(cam, box.CFrame.Position)
			box.Radius = unit
				* (
					isHovered and HOVER_KEY_PIXELS
					or isSelected and SELECTED_KEY_PIXELS
					or binding.bezier and BEZIER_KEY_PIXELS
					or KEY_PIXELS
				)
			box.Color3 = (isSelected or isHovered) and SELECTED_TINT or TINTS.Marker
			table.insert(order, { box = box, binding = binding, forced = isSelected or isHovered })
		end

		table.sort(order, function(a, b)
			if a.forced ~= b.forced then
				return a.forced
			end

			return a.binding.frame < b.binding.frame
		end)
		for _, entry in order do
			local billboard = entry.binding.anchor
				and entry.binding.anchor:FindFirstChild("MotionPathBillboard")
			if not billboard then
				continue
			end

			local point, visible = screen(entry.box.CFrame.Position)
			local show = false
			if labelMode == 2 then
				show = true
			elseif labelMode == 1 then
				show = visible and (entry.forced or roomFor(point))
			end

			if show and visible then
				remember(point)
			end

			billboard.Enabled = show
			local text = billboard:FindFirstChild("Number")
			if text then
				text.TextColor3 = if entry.forced
					then SELECTED_TINT
					else Color3.fromRGB(240, 240, 245)
			end
		end
	end

	local last
	for _, box in tickMarkers do
		local point, visible = screen(box.CFrame.Position)
		box.Radius = pixelUnit(cam, box.CFrame.Position) * TICK_PIXELS
		box.Visible = box:GetAttribute("InPathRange") ~= false
			and visible
			and (not last or (point - last).Magnitude >= TICK_SPACING)
		if box.Visible then
			last = point
		end
	end

	local extent = 0
	for _, entry in plotCache do
		local low, high
		for index, segment in entry.segments do
			if index % 3 ~= 1 then
				continue
			end

			local point = screen(segment[1])
			low = if low then low:Min(point) else point
			high = if high then high:Max(point) else point
		end

		if low then
			extent = math.max(extent, (high - low).Magnitude)
		end
	end

	local thickness = if extent < SMALL_PATH_PIXELS then SMALL_LINE_THICKNESS else LINE_THICKNESS
	if trail then
		trail.Thickness = thickness
	end

	if lookahead then
		lookahead.Thickness = thickness
	end

	for _, handle in { handleIn, handleOut } do
		if handle and handle.Visible then
			handle.CFrame = faceCameraCF(handle.CFrame.Position)
			handle.Size = Vector3.one * pixelUnit(cam, handle.CFrame.Position) * HANDLE_PIXELS
		end
	end
end

local function hoverTarget()
	local cam = workspace.CurrentCamera
	if not cam or draggingHandle then
		return nil
	end

	local mp = UserInputService:GetMouseLocation()
	local memo = hoverMemo
	if
		memo
		and memo.camera == cam
		and memo.cf == cam.CFrame
		and memo.fov == cam.FieldOfView
		and memo.size == cam.ViewportSize
		and memo.mouse == mp
		and memo.revision == markerRevision
	then
		return memo.target
	end

	local best, distance = nil, GRAB_PIXELS
	for _, box in markers do
		if box.Parent ~= host or not box.Visible then
			continue
		end

		local point, visible = cam:WorldToViewportPoint(box.CFrame.Position)
		if not visible or point.Z <= 0 then
			continue
		end

		local gap = (Vector2.new(point.X, point.Y) - mp).Magnitude
		if gap < distance then
			best, distance = box, gap
		end
	end

	hoverMemo = {
		camera = cam,
		cf = cam.CFrame,
		fov = cam.FieldOfView,
		size = cam.ViewportSize,
		mouse = mp,
		revision = markerRevision,
		target = best,
	}
	return best
end

local function pathRange(entry, frame)
	local mode, count =
		Preferences.get("MotionPathRange"), Preferences.get("MotionPathEachSide") or 4
	if mode == 4 then
		local first, last =
			Preferences.get("MotionPathStart") or 0, Preferences.get("MotionPathEnd") or 60
		return math.min(first, last), math.max(first, last)
	end

	if mode == 3 then
		return frame - count, frame + count
	end

	if mode ~= 2 then
		return -math.huge, math.huge
	end

	local marks = entry.markerPositions
	if #marks == 0 then
		return frame, frame
	end

	local before, after = 0, #marks + 1
	for i, mark in marks do
		if mark.frame < frame then
			before = i
		end

		if mark.frame > frame then
			after = i
			break
		end
	end

	return marks[math.max(1, before - count + 1)].frame,
		marks[math.min(#marks, after + count - 1)].frame
end

local pastPoints, futurePoints = {}, {}

local function paint(currentFrame, refreshMarkers)
	if not reattach() then
		return
	end

	local reuse = refreshMarkers and draggingHandle ~= nil
	if reuse then
		for _, entry in plotCache do
			if
				not entry.visualMarkers
				or not entry.visualTicks
				or #entry.visualMarkers ~= #entry.markerPositions
				or #entry.visualTicks ~= #entry.tickPositions
			then
				reuse = false
				break
			end

			for i, mark in entry.markerPositions do
				local box = entry.visualMarkers[i]
				local binding = markerBindings[box]
				if box.Parent ~= host or not binding or binding.frame ~= mark.frame then
					reuse = false
					break
				end
			end

			if not reuse then
				break
			end
		end
	end

	local markersMoved = false
	lastPaintedFrame = currentFrame
	lastRangeMode, lastRangeCount =
		Preferences.get("MotionPathRange"), Preferences.get("MotionPathEachSide")
	lastRangeStart, lastRangeEnd =
		Preferences.get("MotionPathStart"), Preferences.get("MotionPathEnd")
	if refreshMarkers then
		markerRevision += 1
		hoverMemo = nil
	end

	trail:Clear()
	lookahead:Clear()
	if refreshMarkers and not reuse then
		recycleMarkers()
	end

	table.clear(pastPoints)
	table.clear(futurePoints)

	for item, entry in plotCache do
		local low, high = pathRange(entry, currentFrame)
		for _, seg in entry.segments do
			local first, last = seg[4] or seg[3] - SAMPLE_STEP, seg[3]
			if last <= low or first >= high then
				continue
			end

			local a, b = math.max(first, low), math.min(last, high)
			local span = last - first
			if span <= 0 then
				continue
			end

			local points = (last <= currentFrame) and pastPoints or futurePoints
			table.insert(points, seg[1]:Lerp(seg[2], (a - first) / span))
			table.insert(points, seg[1]:Lerp(seg[2], (b - first) / span))
		end

		if refreshMarkers then
			if reuse then
				for i, mark in entry.markerPositions do
					local box = entry.visualMarkers[i]
					if box.CFrame.Position ~= mark.pos then
						box.CFrame = CFrame.new(mark.pos)
						markerBindings[box].anchor.CFrame = box.CFrame
						markersMoved = true
					end
				end

				for i, tick in entry.tickPositions do
					local pos = tick.pos
					local box = entry.visualTicks[i]
					if box.CFrame.Position ~= pos then
						box.CFrame = CFrame.new(pos)
					end
				end
			else
				entry.visualMarkers, entry.visualTicks = {}, {}
				for _, mark in entry.markerPositions do
					table.insert(
						entry.visualMarkers,
						dropKeyframeMarker(mark.pos, mark.frame, entry.motor, item)
					)
				end

				for _, tick in entry.tickPositions do
					table.insert(entry.visualTicks, dropTickMarker(tick.pos))
				end
			end
		end

		for i, box in entry.visualMarkers or {} do
			local frame = entry.markerPositions[i].frame
			box.Visible = frame >= low and frame <= high
			local binding = markerBindings[box]
			if not box.Visible and binding then
				local billboard = binding.anchor
					and binding.anchor:FindFirstChild("MotionPathBillboard")
				if billboard then
					billboard.Enabled = false
				end
			end
		end

		for i, box in entry.visualTicks or {} do
			local frame = entry.tickPositions[i].frame
			box:SetAttribute("InPathRange", frame >= low and frame <= high)
		end

		if
			selected
			and selected.item == item
			and (selected.frame < low or selected.frame > high)
			and not draggingHandle
		then
			selected, selectedBasis = nil, nil
		end
	end

	markerRevision += 1
	hoverMemo = nil

	if #pastPoints > 0 then
		trail:AddLines(pastPoints)
	end

	if #futurePoints > 0 then
		lookahead:AddLines(futurePoints)
	end

	updateHandles()
	layout(reuse and not markersMoved)
end

function MotionPath.enable(item)
	if not item then
		return
	end

	hookInput()
	rebuildJob = nil
	if dragContext then
		dragContext.changed = nil
	end

	watchers[item] = true
	dirty = true
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function()
			update()
		end)
	end
end

function MotionPath.disable(item)
	if not item then
		return
	end

	if selected and selected.item == item then
		commitHandleDrag()
	end

	rebuildJob = nil
	if dragContext then
		dragContext.changed = nil
	end

	watchers[item] = nil
	plotCache[item] = nil
	dirty = true
	if not next(watchers) then
		MotionPath.purge()
	end
end

function MotionPath.markDirty()
	rebuildJob = nil
	if dragContext then
		dragContext.changed = nil
	end

	dirty = true
end

function MotionPath.refresh()
	rebuildJob = nil
	if dragContext then
		dragContext.changed = nil
	end

	dirty = true
	if next(watchers) and not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function()
			update()
		end)
	end
end

function MotionPath.purge()
	commitHandleDrag()
	for _, connection in inputConnections do
		connection:Disconnect()
	end

	table.clear(inputConnections)
	inputHooked = false
	rebuildJob = nil
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end

	if host and host.Parent then
		host:Destroy()
	end

	for _, marker in markerPool do
		if marker.Parent then
			marker:Destroy()
		end
	end

	for _, anchor in anchorPool do
		if anchor.Parent then
			anchor:Destroy()
		end
	end

	for _, anchor in anchors do
		if anchor.Parent then
			anchor:Destroy()
		end
	end

	for _, marker in tickPool do
		if marker.Parent then
			marker:Destroy()
		end
	end

	host = nil
	trail = nil
	lookahead = nil
	handleIn = nil
	handleOut = nil
	handleLine = nil
	selected = nil
	selectedBasis = nil
	draggingHandle = nil
	dragContext = nil
	table.clear(markerBindings)
	table.clear(markers)
	table.clear(markerPool)
	table.clear(anchors)
	table.clear(anchorPool)
	table.clear(tickMarkers)
	table.clear(tickPool)
	table.clear(watchers)
	table.clear(plotCache)
	table.clear(pastPoints)
	table.clear(futurePoints)
	hovered = nil
	labelMode = nil
	dirty = false
	lastTrackedTime = nil
	lastPaintedFrame = nil
	hoverMemo = nil
	markerRevision += 1
	lastEasingStyle = nil
	lastEasingDir = nil
	lastBezierFingerprint = nil
	lastHandleType = nil
end

local function bezierFingerprint()
	local p = Defaults.BezierPoints
	if not p then
		return "nil"
	end

	return string.format("%g,%g,%g,%g", p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0)
end

local function anyAnchorMoved()
	for _, entry in plotCache do
		local a = entry.anchor
		if not a or (typeof(a) == "Instance" and not a.Parent) then
			return true
		end

		if a.CFrame ~= entry.anchorCFrame then
			return true
		end
	end

	return false
end

local lastCameraCF, lastCamera, lastFov, lastViewport = nil, nil, nil, nil

update = function()
	if MainState.PresentationHidden then
		return
	end

	local cam = workspace.CurrentCamera
	local relayout = false
	if
		cam
		and (
			cam ~= lastCamera
			or cam.CFrame ~= lastCameraCF
			or cam.FieldOfView ~= lastFov
			or cam.ViewportSize ~= lastViewport
		)
	then
		lastCameraCF, lastCamera, lastFov, lastViewport =
			cam.CFrame, cam, cam.FieldOfView, cam.ViewportSize
		relayout = true
	end

	local target = next(watchers) and hoverTarget() or nil
	if target ~= hovered then
		hovered = target
		relayout = true
	end

	if numbersMode() ~= labelMode then
		relayout = true
	end

	if relayout then
		layout()
	end

	if not next(watchers) then
		if host and trail and lookahead and host.Parent then
			trail:Clear()
			lookahead:Clear()
			recycleMarkers()
		end

		if selected or (handleIn and handleIn.Visible) or (handleOut and handleOut.Visible) then
			selected = nil
			selectedBasis = nil
			draggingHandle = nil
			dragContext = nil
			hideHandles()
		end

		return
	end

	local fp = bezierFingerprint()
	if
		Defaults.EasingStyle ~= lastEasingStyle
		or Defaults.EasingDirection ~= lastEasingDir
		or fp ~= lastBezierFingerprint
		or Defaults.HandleType ~= lastHandleType
	then
		lastEasingStyle = Defaults.EasingStyle
		lastEasingDir = Defaults.EasingDirection
		lastBezierFingerprint = fp
		lastHandleType = Defaults.HandleType
		dirty = true
	end

	if not dirty and not rebuildJob and not TimelineState.Playing and anyAnchorMoved() then
		dirty = true
	end

	if manipulating() and not draggingHandle then
		if rebuildJob then
			rebuildJob = nil
			dirty = true
		end

		return
	end

	if draggingHandle and dragContext and dragContext.pendingOffset then
		if not rebuildJob then
			flushHandleInput()
		end

		updateHandles()
		for _, handle in { handleIn, handleOut } do
			if cam and handle and handle.Visible then
				handle.Size = Vector3.one * pixelUnit(cam, handle.CFrame.Position) * HANDLE_PIXELS
			end
		end
	end

	if dirty and not rebuildJob then
		dirty = false
		local changed = dragContext and dragContext.changed
		rebuildJob = coroutine.create(function()
			return rebuildCache(changed)
		end)
	end

	if rebuildJob then
		rebuildDeadline = os.clock() + REBUILD_BUDGET
		local ok, result = coroutine.resume(rebuildJob)
		if not ok then
			rebuildJob = nil
			warn("Eclipse motion path: " .. tostring(result))
			return
		end

		if coroutine.status(rebuildJob) == "dead" then
			rebuildJob = nil
			plotCache = result
			lastTrackedTime = TimelineState.CurrentTime
			paint(math.floor(TimelineState.CurrentTime * TimelineState.FPS + 0.5), true)
		end
	elseif
		TimelineState.CurrentTime ~= lastTrackedTime
		or lastRangeMode ~= Preferences.get("MotionPathRange")
		or lastRangeCount ~= Preferences.get("MotionPathEachSide")
		or lastRangeStart ~= Preferences.get("MotionPathStart")
		or lastRangeEnd ~= Preferences.get("MotionPathEnd")
	then
		lastTrackedTime = TimelineState.CurrentTime
		local frame = math.floor(TimelineState.CurrentTime * TimelineState.FPS + 0.5)
		if
			frame ~= lastPaintedFrame
			or lastRangeMode ~= Preferences.get("MotionPathRange")
			or lastRangeCount ~= Preferences.get("MotionPathEachSide")
			or lastRangeStart ~= Preferences.get("MotionPathStart")
			or lastRangeEnd ~= Preferences.get("MotionPathEnd")
			or host and host.Parent ~= cam
		then
			paint(frame, false)
		elseif selected then
			updateHandles()
			layout()
		end
	end
end

function MotionPath.destroy()
	lastCameraCF, lastCamera, lastFov, lastViewport = nil, nil, nil, nil
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end

	MotionPath.purge()
end

return MotionPath
