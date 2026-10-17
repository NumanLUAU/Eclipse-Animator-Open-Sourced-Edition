--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Shortcuts = require("Shortcuts")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")
local State = require("State")
local Visibility = require("Visibility")
local UI = require("UI")
local GraphModel = require("GraphModel")
local GraphView = require("GraphView")
local History = require("History")
local MotionPath = require("motionPath")

local Preferences = require("Preferences")
local PreferencesEditor = require("PreferencesEditor")
local R6Controls = require("R6Controls")
local LimbIK = require("LimbIK")
local Mods = require("Mods")
local ModifierPanel = require("ModifierPanel")
local PANEL_SETTING = "EclipseAnimator_GraphModifiers"
local Editor = {}
local unsubscribePreferences
local refs, session = {}, nil
local lifetime, hooks = {}, {}
local initialized = false
local step, action, rebuild, endGesture

local function connect(list, signal, fn)
	local connection = signal:Connect(fn)
	table.insert(list, connection)
	return connection
end

local function disconnect(list)
	for _, connection in list do
		connection:Disconnect()
	end

	table.clear(list)
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e12
end

local function held(left, right)
	if session and session.view then
		return session.view:isKeyDown(left) or session.view:isKeyDown(right)
	end

	return UserInputService:IsKeyDown(left) or UserInputService:IsKeyDown(right)
end

local function shift()
	return held(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
end

local function ctrl()
	return held(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
end

local function inside(frame, point)
	if not frame or not frame.Visible or not frame.Parent then
		return false
	end

	local p, z = frame.AbsolutePosition, frame.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + z.X and point.Y <= p.Y + z.Y
end

function Editor.containsPoint(point)
	return session ~= nil
		and session.open
		and not session.view.docked
		and inside(session.view.frame, point)
end

local function mousePosition()
	return session and session.view and session.view:mousePosition()
		or UserInputService:GetMouseLocation()
end

function Editor.hasFocus()
	if not session or not session.open then
		return false
	end

	if session.view.docked then
		return session.view.widgetFocused == true
	end

	return session.gesture ~= nil or Editor.containsPoint(mousePosition())
end

local function refreshToggle()
	if State.Timeline.RefreshNavigation then
		State.Timeline:RefreshNavigation()
	end
end

function Editor.isInteracting()
	return session ~= nil
		and session.open
		and (
			session.gesture ~= nil
			or session.view.drag ~= nil
			or session.model._transaction ~= nil
		)
end

function Editor.isNavigating()
	if not session or not session.open then
		return false
	end

	local g = session.gesture
	return session.view.drag ~= nil
		or (g and (g.kind == "pan" or g.kind == "scroll" or g.kind == "valueScroll" or g.kind == "box"))
		or false
end

function Editor.isOpen()
	return session ~= nil and session.open and session.view ~= nil and session.view:isVisible()
end

local function selectedItems(s)
	local items = {}
	for _, track in s.channels do
		if track.visible ~= false and not track.locked and not track.keysHidden then
			for _, key in track.keys do
				if s.selection[key] and not key.inactive then
					table.insert(items, { track = track, key = key })
				end
			end
		end
	end

	return items
end

local function status(s, text)
	s.status = text
	if s.view.setStatus then
		s.view:setStatus(text)
	end
end

local function currentFrame()
	local t = State.Timeline:GetState()
	return t.CurrentTime * t.FPS
end

local function dataPoint(s, screen, track)
	return s.view:fromScreen(screen - s.view.plot.AbsolutePosition, track)
end

local function updateInspector(s)
	local first = selectedItems(s)[1]
	s.primary = first
	for _, track in s.channels do
		track.selected = track == s.activeTrack
			or (s.focusChannels and s.focusChannels[track.id])
			or false
	end

	s.view:setInspector(first and first.track, first and first.key)
	s.dirty = true
end

local function gatherMotors()
	local out, seen, rigs = {}, {}, {}
	local hadSelection = false

	local function add(motor, rig)
		if motor and R6Controls.isControl(motor.Part1) and not LimbIK.hasAnimation(motor.Owner) then
			return
		end

		if motor and motor.Parent and not seen[motor] then
			seen[motor] = true
			table.insert(out, motor)
			if rig then
				rigs[rig] = true
			end
		end
	end

	if State.Axis and State.Rig then
		for _, bone in State.Axis:GetSelectedBones() do
			hadSelection = true
			local source = bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
			local rig = source and source.Value or State.currentRig
			local part = rig and State.Rig:GetPartFromBone(rig, bone)
			add(part and State.Rig:GetMotorForPart(rig, part), rig)
		end
	end

	if #out == 0 then
		for _, kd in State.Timeline:GetSelectedKeyframesList() do
			hadSelection = true
			add(kd.Motor)
		end
	end

	if #out == 0 and not hadSelection then
		for motor, bucket in State.Timeline:GetState().Keyframes do
			if next(bucket) then
				add(motor)
			end
		end
	end

	for _, motor in table.clone(out) do
		if not R6Controls.isControl(motor.Part1) and LimbIK.hasAnimation(motor) then
			for _, control in R6Controls.forOwner(motor) do
				add(control)
			end
		end
	end

	if not next(rigs) then
		for _, rig in State.getAllRigs() do
			rigs[rig] = true
		end
	end

	table.sort(out, function(a, b)
		local pa, pb = a.Part1, b.Part1
		return tostring(pa and pa.Name or a.Name) .. tostring(a)
			< tostring(pb and pb.Name or b.Name) .. tostring(b)
	end)
	return out, rigs
end

local function sameMotors(a, b)
	if #a ~= #b then
		return false
	end

	for i, motor in a do
		if b[i] ~= motor then
			return false
		end
	end

	return true
end

local function refreshHandles(s)
	for _, track in s.channels do
		if track.visible ~= false then
			for _, key in track.keys do
				if s.selection[key] and key.interpolation ~= "Constant" then
					key.left, key.right = s.model:handles(track, key)
					if key.interpolation ~= "Bezier" then
						key.left = nil
					end
				else
					key.left, key.right = nil, nil
				end
			end
		end
	end
end

local function displayLimit(s)
	local cap = Preferences.get("GraphClamp") or 2
	local height = s and s.view and s.view.plot.AbsoluteSize.Y / s.view:_scale() or 328

	return cap + math.max(cap * 0.07, cap * 24 / math.max(60, height - 24))
end

local function contentRange(s, selectedOnly)
	local lo, hi = math.huge, -math.huge
	for _, track in s.channels do
		if track.visible ~= false then
			for _, key in track.keys do
				if not key.inactive and (not selectedOnly or s.selection[key]) then
					lo = math.min(lo, key.frame)
					hi = math.max(hi, key.frame)
				end
			end
		end
	end

	if lo == math.huge then
		if selectedOnly then
			return
		end

		lo, hi = 0, State.Timeline:GetMaxFrame()
	end

	local pad = math.max(10, hi - lo) * 0.08
	local cap = displayLimit(s)
	return { frameMin = lo - pad, frameMax = hi + pad, valueMin = -cap, valueMax = cap }
end

local function updateValueBounds(s)
	if not s.bounds then
		return
	end

	local cap = displayLimit(s)
	s.bounds.valueMin = -cap
	s.bounds.valueMax = cap
end

local function resizeValueRange(s)
	local height = s.view.plot.AbsoluteSize.Y / s.view:_scale()
	if height < 2 then
		return
	end

	if s.plotHeight and math.abs(height - s.plotHeight) > 0.1 then
		local r = s.range
		local center = (r.valueMin + r.valueMax) * 0.5
		local limit = displayLimit(s)
		local half = math.min(limit, (r.valueMax - r.valueMin) * 0.5 * height / s.plotHeight)
		center = math.clamp(center, -limit + half, limit - half)
		r.valueMin = center - half
		r.valueMax = center + half
		updateValueBounds(s)
		s.dirty = true
	end

	s.plotHeight = height
end

local function updateBounds(s)
	s.content = contentRange(s, false)
	s.bounds = table.clone(s.content)
	local last = math.max(State.Timeline:GetMaxFrame(), s.content.frameMax)
	s.bounds.frameMin = math.min(s.content.frameMin, -last * 0.02)
	s.bounds.frameMax = last + last * 0.02
	updateValueBounds(s)
end

local function clampRange(s)
	local r, b = s.range, s.bounds
	if not b then
		return
	end

	for _, axis in { "frame", "value" } do
		local lo, hi = axis .. "Min", axis .. "Max"
		local width = math.min(r[hi] - r[lo], b[hi] - b[lo])
		r[lo] = math.clamp(r[lo], b[lo], math.max(b[lo], b[hi] - width))
		r[hi] = r[lo] + width
	end
end

local function fit(s, selectedOnly)
	for _, track in s.channels do
		track.plotDirty = true
		s.model:prepareDisplay(track, false)
	end

	updateBounds(s)
	local range = s.content
	if selectedOnly then
		range = contentRange(s, true)
	end

	if not range then
		status(s, "Select keys to frame the selection.")
		return
	end

	s.range = table.clone(range)
	s.plotHeight = nil
	updateValueBounds(s)
	clampRange(s)
	s.dirty = true
end

rebuild = function(s, fitNew)
	local preserve = {}
	local display = {}
	local activeId = s.activeTrack and s.activeTrack.id
	for _, track in s.channels do
		display[track.id] = { offset = track.displayOffset, scale = track.displayScale }
		for _, key in track.keys do
			if s.selection[key] then
				if not key.id then
					preserve[track.id .. ":" .. tostring(key.frame)] = true
				end

				if key.id then
					preserve["id:" .. tostring(key.id)] = true
				end
			end
		end
	end

	s.model:invalidate()
	s.channels = s.model:tracks(s.motors)
	for _, track in s.channels do
		local previous = not fitNew and display[track.id]
		if previous then
			track.displayOffset = previous.offset
			track.displayScale = previous.scale
		end

		s.model:prepareDisplay(track, true)
	end

	s.selection = {}
	s.activeTrack = nil
	local first = s.channels[1]
	local defaultGroup = "Position"
	if first then
		local found = false
		for _, track in s.channels do
			if track.motor == first.motor and #track.keys > 1 then
				local v = track.keys[1].value
				for _, key in track.keys do
					if math.abs(key.value - v) > 1e-4 then
						defaultGroup = track.group
						found = true
						break
					end
				end

				if found then
					break
				end
			end
		end
	end

	for _, track in s.channels do
		if track.id == activeId then
			s.activeTrack = track
		end

		local saved = s.channelState[track.id]
		track.visible = saved and saved.visible
		if track.visible == nil then
			track.visible = first ~= nil and track.group == defaultGroup
		end

		track.locked = saved and saved.locked or false
		track.evaluate = track.evaluate
			or function(frame)
				return s.model:sample(track, frame)
			end

		for _, key in track.keys do
			if
				preserve[track.id .. ":" .. tostring(key.frame)]
				or (key.id and preserve["id:" .. tostring(key.id)])
				or (s.wantSelectIds and s.wantSelectIds[key.id])
				or (
					s.wantSelect
					and s.wantSelect.trackId == track.id
					and s.wantSelect.frame == key.frame
				)
			then
				s.selection[key] = true
			end
		end
	end

	s.wantSelect = nil
	s.wantSelectIds = nil
	s.view:setData({
		channels = s.channels,
		title = "Graph Editor",
		status = s.status,
		emptyText = if Preferences.get("TransformChannels") ~= false
			then "Select a bone"
			else "To use the Graph Editor, enable Transform Channels in Settings > Preferences.",
	})
	updateInspector(s)
	refreshHandles(s)
	if fitNew then
		fit(s, false)
	else
		updateBounds(s)
		clampRange(s)
	end

	s.dataDirty = false
	s.dirty = true
end

local function applyPose(s)
	local timeline = State.Timeline
	local t = timeline:GetState()
	for rig in s.rigs do
		if rig.Parent then
			timeline:ApplyPoseAtTime(rig, t.CurrentTime)
			if State.Rig then
				State.Rig:UpdateBonesFollowRig(rig)
			end
		end
	end

	if State.Axis then
		State.Axis:RefreshAxis()
	end

	t.LastPoseApplyClock = os.clock()
	if State.lastCFrames then
		for _, motor in s.motors do
			if motor.Parent then
				State.lastCFrames[motor] = motor.C0
			end
		end
	end

	s.poseDirty = false
end

local function seek(s, frame)
	if not finite(frame) or State.LoadingProject or State.Timeline:IsExportLocked() then
		return
	end

	frame = math.clamp(
		math.floor(frame + 0.5),
		0,
		math.max(State.Timeline:GetMaxFrame(), State.Timeline:GetLastKeyframeFrame() or 0)
	)
	local t = State.Timeline:GetState()
	t.Playing = false
	t.CurrentTime = State.Timeline:FrameToTime(frame)
	State.Timeline:UpdatePlayhead()
	require("EventPlayback").scrub(State.Timeline, t.CurrentTime)
	s.poseDirty = true
end

local function rememberChannels(s)
	for _, track in s.channels do
		s.channelState[track.id] = { visible = track.visible, locked = track.locked }
	end
end

local function resetSelection(s)
	s.boxArmed = false
	s.zoomArmed = false
	table.clear(s.selection)
	updateInspector(s)
end

local function editable(track)
	return track.visible ~= false and not track.locked and not track.keysHidden
end

local function selectWhere(s, extend, predicate, deselect)
	if not extend and not deselect then
		table.clear(s.selection)
	end

	for _, track in s.channels do
		if editable(track) then
			for _, key in track.keys do
				if not key.inactive and predicate(track, key) then
					if deselect then
						s.selection[key] = nil
					else
						s.selection[key] = true
					end
				end
			end
		end
	end

	updateInspector(s)
	refreshHandles(s)
	s.dirty = true
end

local function selectSide(s, side, extend)
	local frame = currentFrame()
	selectWhere(s, extend, function(_, key)
		if side == "left" then
			return key.frame <= frame + 0.1
		end

		return key.frame >= frame - 0.1
	end)
end

local function curveAt(s, point)
	local at = point - s.view.plot.AbsolutePosition
	local frame = s.view:fromScreen(at)
	local best, distance = nil, 10 * s.view:_scale()
	for _, track in s.channels do
		if track.visible ~= false and not track.locked then
			local value = track.modified and s.model:sampleModified(track, frame)
				or s.model:sample(track, frame)
			if value then
				local d = math.abs(s.view:toScreen(frame, value, track).Y - at.Y)
				if d < distance then
					best, distance = track, d
				end
			end
		end
	end

	return best
end

local function inPolygon(point, polygon)
	local inside = false
	local j = #polygon
	for i = 1, #polygon do
		local a, b = polygon[i], polygon[j]
		if
			(a.Y > point.Y) ~= (b.Y > point.Y)
			and point.X < (b.X - a.X) * (point.Y - a.Y) / (b.Y - a.Y) + a.X
		then
			inside = not inside
		end

		j = i
	end

	return inside
end

local function hintTransform(s)
	local g = s.gesture
	if not g or not g.numeric then
		return
	end

	local n = g.numeric
	local text
	if g.kind == "move" then
		text = "Move  X: "
			.. (n.index == 1 and "[" .. (n.x == "" and "0" or n.x) .. "]" or (n.x == "" and "0" or n.x))
			.. "   Y: "
			.. (
				n.index == 2 and "[" .. (n.y == "" and "0" or n.y) .. "]"
				or (n.y == "" and "0" or n.y)
			)
	else
		text = (g.kind == "rotate" and "Rotate: " or "Scale: ") .. (n.x == "" and "0" or n.x)
	end

	s.view:toast(text)
end

local function numericValue(text)
	if text == "" or text == "-" then
		return 0
	end

	return tonumber(text)
end

local function beginMove(s, point, modal, duplicate)
	local items = selectedItems(s)
	if #items == 0 then
		return
	end

	State.Timeline:GetState().Playing = false
	local tx, err = s.model:begin(duplicate and "Duplicate graph keys" or "Move graph keys", items)
	if not tx then
		status(s, err or "These keys cannot be moved.")
		return
	end

	tx.snap = s.snap
	tx.valueScales = {}
	tx.duplicate = duplicate
	for _, item in items do
		tx.valueScales[item.track.id] = item.track.displayScale or 1
	end

	local frame, value = dataPoint(s, point)
	s.gesture = {
		kind = "move",
		transaction = tx,
		items = items,
		start = point,
		frame = frame,
		value = value,
		modal = modal,
		axis = nil,
	}
	status(s, "Move keys · X time · Y value · Shift precision · Esc cancel")
end

local function beginTransform(s, point, kind)
	local items = selectedItems(s)
	if #items == 0 then
		return
	end

	local tx = s.model:begin(kind == "rotate" and "Rotate graph keys" or "Scale graph keys", items)
	if not tx then
		return
	end

	tx.snap = s.snap
	local pivot = Vector2.zero
	for _, item in items do
		pivot += s.view:toScreen(item.key.frame, item.key.value, item.track)
	end

	pivot /= #items
	local offset = s.view.plot.AbsolutePosition
	s.gesture = {
		kind = kind,
		transaction = tx,
		items = items,
		modal = true,
		start = point,
		pivot = pivot,
		offset = offset,
	}
	State.Timeline:GetState().Playing = false
end

local function processPointer(s, point)
	local g = s.gesture
	if not g then
		return
	end

	if g.kind == "pendingMove" then
		if (point - g.start).Magnitude >= 3 then
			beginMove(s, g.start, false)
			if s.gesture and s.gesture.kind == "move" then
				processPointer(s, point)
			end
		end
	elseif g.kind == "pan" then
		local delta = point - g.start
		local size = s.view.plot.AbsoluteSize
		local x = delta.X / math.max(1, size.X) * (g.range.frameMax - g.range.frameMin)
		local y = delta.Y / math.max(1, size.Y) * (g.range.valueMax - g.range.valueMin)
		s.range = {
			frameMin = g.range.frameMin - x,
			frameMax = g.range.frameMax - x,
			valueMin = g.range.valueMin + y,
			valueMax = g.range.valueMax + y,
		}
		clampRange(s)
		s.dirty = true
	elseif g.kind == "scroll" then
		local delta = (point.X - g.start.X) / math.max(1, s.view.scrollbar.AbsoluteSize.X)
		local span = s.bounds.frameMax - s.bounds.frameMin
		local r = g.range
		if g.side == "left" then
			s.range.frameMin =
				math.clamp(r.frameMin + delta * span, s.bounds.frameMin, r.frameMax - 2)
		elseif g.side == "right" then
			s.range.frameMax =
				math.clamp(r.frameMax + delta * span, r.frameMin + 2, s.bounds.frameMax)
		else
			s.range.frameMin = r.frameMin + delta * span
			s.range.frameMax = r.frameMax + delta * span
		end

		clampRange(s)
		s.dirty = true
	elseif g.kind == "valueScroll" then
		local delta = point.Y - g.start.Y
		if g.side then
			local span = s.bounds.valueMax - s.bounds.valueMin
			delta = delta / math.max(1, s.view.valueScrollbar.AbsoluteSize.Y) * span
			if g.side == "top" then
				s.range.valueMax = math.clamp(
					g.range.valueMax - delta,
					g.range.valueMin + 0.0001,
					s.bounds.valueMax
				)
			else
				s.range.valueMin = math.clamp(
					g.range.valueMin - delta,
					s.bounds.valueMin,
					g.range.valueMax - 0.0001
				)
			end
		else
			delta = delta / g.travelPixels * g.travelValues
			s.range.valueMin = g.range.valueMin - delta
			s.range.valueMax = g.range.valueMax - delta
		end

		clampRange(s)
		s.dirty = true
	elseif g.kind == "scrub" then
		local frame, value = dataPoint(s, point)
		seek(s, frame)
		if g.button == 2 then
			s.cursorValue = value
			s.dirty = true
		end
	elseif g.kind == "box" then
		s.box = {
			from = g.start - s.view.plot.AbsolutePosition,
			to = point - s.view.plot.AbsolutePosition,
		}
		s.dirty = true
	elseif g.kind == "zoomDrag" then
		local delta = (point - g.start) / s.view:_scale()
		local r = g.range
		local fx = math.exp(-delta.X * 0.006)
		local fy = math.exp(delta.Y * 0.006)
		local width =
			math.clamp((r.frameMax - r.frameMin) * fx, 2, s.bounds.frameMax - s.bounds.frameMin)
		local height = math.clamp(
			(r.valueMax - r.valueMin) * fy,
			0.0001,
			s.bounds.valueMax - s.bounds.valueMin
		)
		local ax = (g.anchor.X - r.frameMin) / (r.frameMax - r.frameMin)
		local ay = (g.anchor.Y - r.valueMin) / (r.valueMax - r.valueMin)
		s.range = {
			frameMin = g.anchor.X - width * ax,
			frameMax = g.anchor.X - width * ax + width,
			valueMin = g.anchor.Y - height * ay,
			valueMax = g.anchor.Y - height * ay + height,
		}
		clampRange(s)
		s.dirty = true
	elseif g.kind == "pendingLasso" or g.kind == "lasso" then
		if g.kind == "pendingLasso" and (point - g.start).Magnitude < 4 then
			return
		end

		g.kind = "lasso"
		local last = g.points[#g.points]
		if (point - last).Magnitude >= 3 then
			table.insert(g.points, point)
		end

		s.dirty = true
	elseif g.kind == "circle" then
		g.at = point
		if g.painting then
			local origin = s.view.plot.AbsolutePosition
			for _, track in s.channels do
				if editable(track) then
					for _, key in track.keys do
						if
							not key.inactive
							and (s.view:toScreen(key.frame, key.value, track) + origin - point).Magnitude
								<= g.radius
						then
							if g.painting == "deselect" then
								s.selection[key] = nil
							else
								s.selection[key] = true
							end
						end
					end
				end
			end

			updateInspector(s)
			refreshHandles(s)
		end

		s.dirty = true
	elseif g.kind == "move" then
		local frame, value = dataPoint(s, point)
		local dx, dy = frame - g.frame, value - g.value
		local rawDelta = Vector2.new(dx, dy)
		g.precise = (g.precise or Vector2.zero)
			+ (rawDelta - (g.previousRaw or Vector2.zero)) * (shift() and 0.1 or 1)
		g.previousRaw = rawDelta
		dx, dy = g.precise.X, g.precise.Y
		local snap = s.snap
		if ctrl() then
			snap = not snap
		end

		g.transaction.snap = snap
		if g.numeric then
			local x, y = numericValue(g.numeric.x), numericValue(g.numeric.y)
			if x and y then
				dx, dy = x, y
			end
		end

		if snap then
			dx = math.floor(dx + 0.5)
		end

		if g.axis == "X" then
			dy = 0
		elseif g.axis == "Y" then
			dx = 0
		end

		if g.lastX == dx and g.lastY == dy then
			return
		end

		local ok, err = s.model:updateMove(g.transaction, dx, dy)
		if ok ~= false then
			g.lastX, g.lastY = dx, dy
		else
			status(s, err or "Keys cannot overlap on the same channel.")
		end

		s.dirty = true
		s.poseDirty = true
		updateInspector(s)
		refreshHandles(s)
	elseif g.kind == "rotate" or g.kind == "scale" then
		local a = g.start - g.offset - g.pivot
		local b = point - g.offset - g.pivot
		local angle = math.atan2(a.X * b.Y - a.Y * b.X, a:Dot(b))
		local scale = b.Magnitude / math.max(1, a.Magnitude)
		if a:Dot(b) < 0 then
			scale = -scale
		end

		if shift() then
			angle *= 1 / 30
			scale = 1 + (scale - 1) * 0.1
		end

		g.transaction.snap = ctrl() and not s.snap or (not ctrl() and s.snap)
		if g.numeric and g.numeric.x ~= "" then
			local typed = numericValue(g.numeric.x)
			if typed then
				if g.kind == "rotate" then
					angle = -math.rad(typed)
				else
					scale = typed
				end
			end
		end

		local ok, err = s.model:updateTransform(g.transaction, function(frame, value, track)
			local p = s.view:toScreen(frame, value, track) - g.pivot
			if g.kind == "rotate" then
				p = Vector2.new(
					p.X * math.cos(angle) - p.Y * math.sin(angle),
					p.X * math.sin(angle) + p.Y * math.cos(angle)
				)
			else
				p = Vector2.new(
					p.X * (g.axis == "Y" and 1 or scale),
					p.Y * (g.axis == "X" and 1 or scale)
				)
			end

			return s.view:fromScreen(p + g.pivot, track)
		end)
		if ok == false then
			status(s, err)
		end

		s.dirty = true
		s.poseDirty = true
		updateInspector(s)
		refreshHandles(s)
	elseif g.kind == "handle" then
		local raw = g.handleStart + (point - g.start) / g.displayScale
		local frame, value = s.view:fromScreen(raw, g.item.track)
		local ok, err = s.model:updateHandle(g.transaction, g.item, g.side, frame, value, g.metric)
		if ok == false then
			status(s, err or "This handle cannot be moved.")
		end

		refreshHandles(s)
		s.dirty = true
		s.poseDirty = true
	end
end

endGesture = function(s, cancel)
	local g = s.gesture
	if not g then
		return
	end

	if s.pending and not cancel then
		local p = s.pending
		s.pending = nil
		processPointer(s, p)
	end

	g = s.gesture
	s.pointerInput = nil
	s.gesture = nil
	s.pending = nil
	if g.transaction then
		if cancel then
			s.model:cancel(g.transaction)
		else
			s.model:commit(g.transaction)
		end

		s.dataDirty = true
		s.poseDirty = true
	elseif g.kind == "pendingMove" and not cancel and g.only then
		table.clear(s.selection)
		for _, key in g.only do
			s.selection[key] = true
		end

		updateInspector(s)
		refreshHandles(s)
	elseif g.kind == "pendingLasso" and not cancel then
		local track = s.activeTrack or (s.primary and s.primary.track)
		if not track then
			status(s, "Click a curve first to make it active.")
			s.view:toast("Click a curve first to make it active.")
		elseif track.locked or track.keysHidden then
			s.view:toast(
				"This curve can't take keys right now (locked or a modifier hides its keys)."
			)
		else
			local frame, value = s.view:fromScreen(g.start - s.view.plot.AbsolutePosition, track)
			local at = math.max(0, math.floor(frame + 0.5))
			if not g.extend then
				table.clear(s.selection)
			end

			s.wantSelect = { trackId = track.id, frame = at }
			s.model:insert(track, at, value)
		end
	elseif g.kind == "lasso" and not cancel then
		local origin = s.view.plot.AbsolutePosition
		for _, track in s.channels do
			if editable(track) then
				for _, key in track.keys do
					if
						not key.inactive
						and inPolygon(
							s.view:toScreen(key.frame, key.value, track) + origin,
							g.points
						)
					then
						if g.subtract then
							s.selection[key] = nil
						else
							s.selection[key] = true
						end
					end
				end
			end
		end

		updateInspector(s)
		refreshHandles(s)
	elseif g.kind == "box" and g.zoom and not cancel then
		local box = s.box
		if box and (box.to - box.from).Magnitude > 4 then
			local a, b = s.view:fromScreen(box.from), s.view:fromScreen(box.to)
			local _, va = s.view:fromScreen(box.from)
			local _, vb = s.view:fromScreen(box.to)
			s.range = {
				frameMin = math.min(a, b),
				frameMax = math.max(a, b),
				valueMin = math.min(va, vb),
				valueMax = math.max(va, vb),
			}
			if s.range.frameMax - s.range.frameMin < 2 then
				s.range.frameMax = s.range.frameMin + 2
			end

			clampRange(s)
		end
	elseif
		g.kind == "box"
		and g.subtract
		and not cancel
		and (not s.box or (s.box.to - s.box.from).Magnitude < 3)
	then
		local frame = s.view:fromScreen(g.start - s.view.plot.AbsolutePosition)
		selectSide(s, frame < currentFrame() and "left" or "right", g.extend)
	elseif g.kind == "box" and not cancel then
		local box = s.box
		if not g.additive and not g.subtract then
			table.clear(s.selection)
		end

		if box then
			local lo = Vector2.new(math.min(box.from.X, box.to.X), math.min(box.from.Y, box.to.Y))
			local hi = Vector2.new(math.max(box.from.X, box.to.X), math.max(box.from.Y, box.to.Y))
			for _, track in s.channels do
				if track.visible ~= false and not track.locked and not track.keysHidden then
					for _, key in track.keys do
						local p = s.view:toScreen(key.frame, key.value, track)
						if
							not key.inactive
							and p.X >= lo.X
							and p.Y >= lo.Y
							and p.X <= hi.X
							and p.Y <= hi.Y
						then
							if g.subtract then
								s.selection[key] = nil
							else
								s.selection[key] = true
							end
						end
					end
				end
			end
		end

		updateInspector(s)
	end

	s.box = nil
	s.boxArmed = false
	s.zoomArmed = false
	s.dirty = true
	if s.view.selectionBox then
		s.view.selectionBox.Visible = false
	end

	status(
		s,
		cancel and "Edit cancelled"
			or "MMB pan · Wheel zoom · G move · B box select · Home frame all"
	)
end

local function zoom(s, point, amount)
	if s.gesture then
		if s.gesture.kind == "circle" then
			s.gesture.radius = math.clamp(s.gesture.radius * math.exp(-amount * 0.15), 4, 300)
			s.dirty = true
		end

		return
	end

	local r = s.range
	if ctrl() then
		local shiftBy = -amount
			* 40
			* s.view:_scale()
			/ math.max(1, s.view.plot.AbsoluteSize.X)
			* (r.frameMax - r.frameMin)
		r.frameMin += shiftBy
		r.frameMax += shiftBy
		clampRange(s)
		s.dirty = true
		return
	elseif shift() then
		local shiftBy = amount
			* 40
			* s.view:_scale()
			/ math.max(1, s.view.plot.AbsoluteSize.Y)
			* (r.valueMax - r.valueMin)
		r.valueMin += shiftBy
		r.valueMax += shiftBy
		clampRange(s)
		s.dirty = true
		return
	end

	local frame, value = dataPoint(s, point)
	local factor = math.exp(-amount * 0.15)
	local xOnly, yOnly = false, false
	if not yOnly then
		local width =
			math.clamp((r.frameMax - r.frameMin) * factor, 2, s.bounds.frameMax - s.bounds.frameMin)
		local alpha = (frame - r.frameMin) / (r.frameMax - r.frameMin)
		r.frameMin = frame - width * alpha
		r.frameMax = r.frameMin + width
	end

	if not xOnly then
		local height = math.clamp(
			(r.valueMax - r.valueMin) * factor,
			0.0001,
			s.bounds.valueMax - s.bounds.valueMin
		)
		local alpha = (value - r.valueMin) / (r.valueMax - r.valueMin)
		r.valueMin = value - height * alpha
		r.valueMax = r.valueMin + height
	end

	clampRange(s)
	s.dirty = true
end

local function scrollValues(s, amount)
	if s.gesture then
		return
	end

	local r = s.range
	local delta = (r.valueMax - r.valueMin) * amount
	r.valueMin += delta
	r.valueMax += delta
	clampRange(s)
	s.dirty = true
end

local function valueScrollDown(s, input, side)
	if s.view.menu or s.view.menuDismissInput == input then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if s.gesture then
		if s.gesture.kind == "valueScroll" and side then
			s.gesture.side = side
		end

		return
	end

	local point = mousePosition()
	if side or inside(s.view.valueThumb, point) then
		s.pointerInput = input
		s.gesture = {
			kind = "valueScroll",
			side = side,
			start = point,
			range = table.clone(s.range),
			travelPixels = math.max(
				1,
				s.view.valueScrollbar.AbsoluteSize.Y - s.view.valueThumb.AbsoluteSize.Y
			),
			travelValues = math.max(
				0,
				(s.bounds.valueMax - s.bounds.valueMin) - (s.range.valueMax - s.range.valueMin)
			),
		}
	else
		scrollValues(s, point.Y < s.view.valueThumb.AbsolutePosition.Y and 0.85 or -0.85)
	end
end

local function plotDown(s, input)
	if s.view.menu or s.view.menuDismissInput == input then
		return
	end

	local point = mousePosition()
	local prior = s.pointerInput
	if
		s.gesture
		and not s.gesture.modal
		and prior
		and prior ~= input
		and (
			prior.UserInputState == Enum.UserInputState.End
			or prior.UserInputState == Enum.UserInputState.Cancel
			or prior.UserInputType == input.UserInputType
		)
	then
		endGesture(s, prior.UserInputState == Enum.UserInputState.Cancel)
	end

	if
		not s.gesture
		and (
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
		)
	then
		s.pointerInput = input
	end

	if s.gesture then
		if s.gesture.kind == "circle" then
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				s.gesture.painting = shift() and "deselect" or "select"
				s.pending = point
			elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
				s.gesture.painting = "deselect"
				s.pending = point
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				endGesture(s, false)
			end

			return
		end

		if s.gesture.input == input then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			endGesture(s, true)
		elseif s.gesture.modal and input.UserInputType == Enum.UserInputType.MouseButton1 then
			endGesture(s, false)
		end

		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		if ctrl() then
			local frame, value = dataPoint(s, point)
			s.gesture = {
				kind = "zoomDrag",
				start = point,
				range = table.clone(s.range),
				anchor = Vector2.new(frame, value),
				input = input,
			}
			return
		end

		s.gesture = { kind = "pan", start = point, range = table.clone(s.range), input = input }
		return
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and ctrl() then
		s.gesture = {
			kind = "pendingLasso",
			start = point,
			points = { point },
			subtract = shift(),
			extend = shift(),
			button = 2,
			input = input,
		}
		return
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and shift() then
		s.gesture = { kind = "scrub", button = 2, input = input }
		s.pending = point
		return
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		return
	elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if s.zoomArmed then
		s.gesture = { kind = "box", start = point, zoom = true, input = input }
		s.box = {
			from = point - s.view.plot.AbsolutePosition,
			to = point - s.view.plot.AbsolutePosition,
		}
		s.dirty = true
		return
	end

	local alt = held(Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt)
	local hit = not s.boxArmed and s.view:hitTest(point - s.view.plot.AbsolutePosition)
	if not s.boxArmed and alt and ctrl() then
		local track = hit and hit.channel or curveAt(s, point)
		if track and editable(track) then
			if not shift() then
				table.clear(s.selection)
			end

			for _, key in track.keys do
				if not key.inactive then
					s.selection[key] = true
				end
			end

			s.activeTrack = track
			updateInspector(s)
			refreshHandles(s)
			s.dirty = true
		elseif not shift() then
			resetSelection(s)
		end

		return
	elseif not s.boxArmed and alt then
		if hit and hit.kind == "key" then
			local frame = hit.key.frame
			selectWhere(s, shift(), function(_, key)
				return math.abs(key.frame - frame) < 1e-4
			end)
		elseif not shift() then
			resetSelection(s)
		end

		return
	elseif not s.boxArmed and ctrl() then
		s.gesture =
			{ kind = "box", start = point, subtract = true, extend = shift(), input = input }
		s.box = {
			from = point - s.view.plot.AbsolutePosition,
			to = point - s.view.plot.AbsolutePosition,
		}
		s.dirty = true
		return
	end

	if hit and not hit.channel.locked and hit.kind == "key" and shift() then
		local coincident = s.view:coincidentKeys(hit)
		local selected = s.selection[hit.key]
		for _, entry in coincident do
			if selected then
				s.selection[entry.key] = nil
			else
				s.selection[entry.key] = true
			end
		end

		s.activeTrack = hit.channel
		updateInspector(s)
		refreshHandles(s)
		s.gesture = { kind = "box", start = point, additive = true, input = input }
		s.box = {
			from = point - s.view.plot.AbsolutePosition,
			to = point - s.view.plot.AbsolutePosition,
		}
		s.dirty = true
		return
	end

	if hit and not hit.channel.locked then
		if hit.kind == "handle" then
			local item = { track = hit.channel, key = hit.key }
			local tx = s.model:begin("Edit graph handle", { item })
			if tx then
				State.Timeline:GetState().Playing = false
				local handle = hit.key[hit.side]
				local size = s.view.plot.AbsoluteSize
				s.gesture = {
					kind = "handle",
					transaction = tx,
					item = item,
					side = hit.side,
					start = point,
					handleStart = s.view:toScreen(handle.frame, handle.value, hit.channel),
					displayScale = hit.displayScale or 1,
					metric = {
						frame = (s.range.frameMax - s.range.frameMin) / size.X,
						value = (s.range.valueMax - s.range.valueMin)
							/ size.Y
							* (hit.channel.displayScale or 1),
					},
				}
			end

			return
		end

		local coincident = s.view:coincidentKeys(hit)
		local selected = s.selection[hit.key]
		if not selected then
			table.clear(s.selection)
		end

		for _, entry in coincident do
			s.selection[entry.key] = true
		end

		s.activeTrack = hit.channel
		updateInspector(s)
		refreshHandles(s)
		local last = s.lastKeyClick
		local now = os.clock()
		s.lastKeyClick = { key = hit.key, at = now, point = point }
		if
			last
			and last.key == hit.key
			and now - last.at <= 0.3
			and (point - last.point).Magnitude <= 5
		then
			s.lastKeyClick = nil
			s.view:openMenu(point)
			return
		end

		local only
		if selected then
			only = {}
			for _, entry in coincident do
				table.insert(only, entry.key)
			end
		end

		s.gesture = { kind = "pendingMove", start = point, only = only, input = input }
	else
		s.gesture = { kind = "box", start = point, additive = shift() or s.boxArmed, input = input }
		s.box = {
			from = point - s.view.plot.AbsolutePosition,
			to = point - s.view.plot.AbsolutePosition,
		}
		s.dirty = true
	end
end

local function panelTrack(s)
	local track = s.activeTrack
	if track and track.visible ~= false then
		for _, candidate in s.channels do
			if candidate == track then
				return track
			end
		end
	end

	return s.primary and s.primary.track or nil
end

local function selectedTracks(s)
	local out, seen = {}, {}
	for _, track in s.channels do
		if track.visible ~= false and not track.locked and track.selected then
			seen[track] = true
			table.insert(out, track)
		end
	end

	for _, item in selectedItems(s) do
		if not seen[item.track] then
			seen[item.track] = true
			table.insert(out, item.track)
		end
	end

	return out
end

local function shakeMotors(s)
	local out, seen = {}, {}

	local function add(motor)
		if motor and typeof(motor) == "Instance" and motor.Parent and not seen[motor] then
			seen[motor] = true
			table.insert(out, motor)
		end
	end

	if State.Axis and State.Rig then
		for _, bone in State.Axis:GetSelectedBones() do
			local source = bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
			local rig = source and source.Value or State.currentRig
			local part = rig and State.Rig:GetPartFromBone(rig, bone)
			add(part and State.Rig:GetMotorForPart(rig, part))
		end
	end

	if #out == 0 then
		for _, kd in State.Timeline:GetSelectedKeyframesList() do
			add(kd.Motor)
		end
	end

	return out
end

local function modifiersChanged(s, motors, live)
	for motor in motors do
		Mods.touch(motor)
	end

	s.model:invalidate()
	for _, track in s.channels do
		if motors[track.motor] then
			s.model:syncModifiers(track)
			track.plotDirty = true
		end
	end

	if not live then
		s.dataDirty = true
		State.currentProjectSaved = false
		MotionPath.markDirty()
	end

	s.dirty = true
	s.poseDirty = true
end

local function setPanel(s, open, restoring)
	if not s.panel then
		return
	end

	s.panelOpen = open == true
	s.panel:setOpen(s.panelOpen)
	s.view:setSidebar(s.panelOpen)
	if not restoring and refs.Plugin then
		pcall(function()
			refs.Plugin:SetSetting(PANEL_SETTING, s.panelOpen)
		end)
	end

	s.dirty = true
end

local function panelHost(s)
	return {
		toggle = function(open)
			setPanel(s, open)
		end,
		activeTrack = function()
			return panelTrack(s)
		end,
		selectedTracks = function()
			return selectedTracks(s)
		end,
		changed = function(motors, live)
			modifiersChanged(s, motors, live)
		end,
		status = function(text)
			status(s, text)
			s.view:toast(text)
		end,
		currentFrame = currentFrame,
		keySpan = function()
			local track = panelTrack(s)
			if not track then
				return nil
			end

			local first, last
			for _, key in track.keys do
				if not first or key.frame < first then
					first = key.frame
				end

				if not last or key.frame > last then
					last = key.frame
				end
			end

			return first, last
		end,
		shakeMotors = function()
			return shakeMotors(s)
		end,
		shakeAdded = function(motors)
			local set = {}
			for _, motor in motors do
				set[motor] = true
			end

			s.pendingReveal = set
		end,
	}
end

action = function(name, payload)
	local s = session
	if not s or not s.open then
		return
	end

	if name == "visibility" then
		local current = session
		if
			current
			and current.open
			and current.view
			and current.view.docked
			and not current.view.docking
			and not State.PresentationHidden
			and not current.view.widget.Enabled
		then
			Editor.close()
		else
			refreshToggle()
		end

		return
	end

	if name == "close" then
		Editor.close()
		return
	end

	if name == "resize" then
		s.dirty = true
		return
	end

	if s.gesture then
		endGesture(s, name ~= "play" and name ~= "playPause")
	end

	local channel = type(payload) == "table" and (payload.channel or payload.track) or nil
	if not channel and type(payload) == "table" and payload.keys then
		channel = payload
	end

	if type(payload) == "string" then
		for _, track in s.channels do
			if track.id == payload then
				channel = track
				break
			end
		end
	end

	if name == "modifiers" then
		setPanel(s, not s.panelOpen)
	elseif name == "toggleModifiers" and channel then
		if channel.locked then
			status(s, "Unlock this curve first.")
			s.view:toast("Unlock this curve first.")
		else
			local entry = Mods.get(channel.motor, channel.channelId)
			s.panel:setOff(channel, not (entry and entry.Off))
		end
	elseif name == "fit" or name == "resetView" then
		fit(s, false)
	elseif name == "frameSelection" then
		fit(s, true)
	elseif name == "focusLost" then
		s.playbackKey = nil
		if s.gesture then
			endGesture(s, true)
		end
	elseif name == "dock" then
		if s.gesture then
			endGesture(s, false)
		end

		s.view:setDocked(not s.view.docked)
		s.dirty = true
	elseif name == "preferences" then
		s.view:_hideTips()
		PreferencesEditor.openGraphPreferences()
	elseif name == "search" then
		s.dirty = true
	elseif name == "snap" then
		s.snap = not s.snap
		if s.view.setSnap then
			s.view:setSnap(s.snap)
		end
	elseif name == "selectChannel" and channel then
		local additive = (type(payload) == "table" and payload.shift) or shift()
		s.focusChannels = additive and s.focusChannels or {}
		s.focusChannels[channel.id] = true
		channel.visible = true
		s.activeTrack = channel
		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
		s.view:_refreshRows()
		fit(s, false)
	elseif name == "selectGroup" then
		s.activeTrack = nil
		s.focusChannels = {}
		for _, track in s.channels do
			local match = (
				payload.motor and track.motor == payload.motor
				or not payload.motor and track.bone == payload.bone
			) and (not payload.group or track.group == payload.group)
			if not payload.shift or match then
				track.visible = match
			end

			if match then
				s.focusChannels[track.id] = true
			end
		end

		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
		s.view:_refreshRows()
		fit(s, false)
	elseif name == "rotationMode" then
		local motors = {}
		for _, item in selectedItems(s) do
			motors[item.track.motor] = true
		end

		if not next(motors) and channel then motors[channel.motor] = true end
		if not next(motors) and type(payload) == "table" and payload.motor then motors[payload.motor] = true end
		if not next(motors) then
			for _, track in s.channels do if s.focusChannels[track.id] then motors[track.motor] = true end end
		end
		if not next(motors) and s.activeTrack then
			motors[s.activeTrack.motor] = true
		end

		if not next(motors) then
			status(s, "Select a part's curve or rotation keys first.")
		else
			local mode = type(payload) == "table" and payload.value or payload
			s.model.onRotationChanged = function()
				require("Project").refreshTimelineAfterStructureChange()
			end

			local ok, result = pcall(s.model.setRotationMode, s.model, motors, mode)
			status(
				s,
				not ok and tostring(result)
					or result and ("Rotation: " .. mode .. ". Keyed poses retained; interpolation now uses this mode.")
					or "Already using this rotation mode"
			)
		end
	elseif name == "filterRotation" then
		local motors = {}
		for _, item in selectedItems(s) do
			motors[item.track.motor] = true
		end

		if not next(motors) and channel then motors[channel.motor] = true end
		if not next(motors) and type(payload) == "table" and payload.motor then motors[payload.motor] = true end
		if not next(motors) then
			for _, track in s.channels do if s.focusChannels[track.id] then motors[track.motor] = true end end
		end
		if not next(motors) and s.activeTrack then
			motors[s.activeTrack.motor] = true
		end

		local tracks = {}
		for _, track in s.channels do
			if motors[track.motor] then
				table.insert(tracks, track)
			end
		end

		if #tracks == 0 then
			status(s, "Select rotation keys or a part's curve first.")
		else
			status(
				s,
				s.model:filterRotation(tracks) and "Rotation discontinuities filtered"
					or "No rotation discontinuities found"
			)
		end
	elseif name == "toggleGroupVisible" then
		local show = false
		for _, track in s.channels do
			if
				track.motor == payload.motor
				and (not payload.group or track.group == payload.group)
				and track.visible == false
			then
				show = true
			end
		end

		for _, track in s.channels do
			if
				track.motor == payload.motor
				and (not payload.group or track.group == payload.group)
			then
				track.visible = show
			end
		end

		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
	elseif name == "toggleVisible" and channel then
		channel.visible = not channel.visible
		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
		fit(s, false)
	elseif name == "toggleMute" and channel then
		local muted = not channel.muted
		if s.model:setMuted(channel, muted) then
			status(
				s,
				muted and "Animation axis muted for playback and export" or "Animation axis enabled"
			)
		end
	elseif name == "toggleLock" and channel then
		channel.locked = not channel.locked
		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
	elseif name == "play" or name == "playPause" then
		if State.Timeline:IsExportLocked() then
			return
		end

		local t = State.Timeline:GetState()
		if t.Playing then
			t.Playing = false
		else
			State.Timeline:StartPlayback(true)
		end
	elseif name == "delete" then
		s.model:delete(selectedItems(s))
	elseif name == "copy" then
		local items = selectedItems(s)
		if #items > 0 then
			s.clipboard = s.model:copy(items)
			status(s, "Copied " .. #items .. " graph keys")
		else
			status(s, "Select graph keys to copy.")
		end
	elseif name == "duplicate" then
		beginMove(s, mousePosition(), true, true)
	elseif name == "paste" then
		local ok, items
		if name == "paste" then
			if not s.clipboard then
				status(s, "Copy graph keys before pasting.")
				return
			end

			for _, entry in s.clipboard.entries do
				for _, track in s.channels do
					if
						track.motor == entry.motor
						and track.channelId == entry.channelId
						and track.locked
					then
						status(s, "Unlock the destination channel before pasting.")
						return
					end
				end
			end

			ok, items = s.model:paste(
				s.clipboard,
				s.snap and math.floor(currentFrame() + 0.5) or currentFrame()
			)
		end

		if ok then
			table.clear(s.selection)
			s.wantSelectIds = {}
			for _, item in items or {} do
				if item.key then
					s.wantSelectIds[item.key.id] = true
				end
			end

			s.dataDirty = true
		else
			status(s, type(items) == "string" and items or "These graph keys cannot be pasted.")
		end
	elseif name == "insert" then
		local track = s.primary and s.primary.track or s.activeTrack
		if not track then
			for _, candidate in s.channels do
				if candidate.visible and not candidate.locked then
					track = candidate
					break
				end
			end
		end

		if track and not track.locked then
			local frame = math.floor(currentFrame() + 0.5)
			s.wantSelect = { trackId = track.id, frame = frame }
			s.model:insert(track, frame)
		else
			status(s, "Choose an unlocked channel before inserting a key.")
		end
	elseif name == "curvePicker" then
		local items = selectedItems(s)
		local first = items[1]
		if not first then
			return
		end

		local key = first.key.keyData
		local easing = require("ChannelEasing")
		local source = easing.view(key, first.track.channelId)
		local values = {}
		for _, field in easing.fields do
			values[field] = easing.clone(source[field])
		end

		values.EasingStyle = typeof(values.EasingStyle) == "EnumItem" and values.EasingStyle.Name
			or values.EasingStyle
			or "Bezier"
		values.EasingDirection = typeof(values.EasingDirection) == "EnumItem"
				and values.EasingDirection.Name
			or values.EasingDirection
			or "In"
		local point = key.GraphCurves and key.GraphCurves[first.track.channelId]
		if point and point.Interpolation == "Bezier" then
			local nextKey =
				first.track.keys[(table.find(first.track.keys, first.key) or #first.track.keys) + 1]
			if
				nextKey
				and nextKey.frame > first.key.frame
				and math.abs(nextKey.value - first.key.value) > 1e-9
			then
				local _, outgoing = s.model:handles(first.track, first.key)
				local incoming = s.model:handles(first.track, nextKey)
				local span, delta = nextKey.frame - first.key.frame, nextKey.value - first.key.value
				values.BezierPoints = {
					(outgoing.frame - first.key.frame) / span,
					(outgoing.value - first.key.value) / delta,
					(incoming.frame - first.key.frame) / span,
					(incoming.value - first.key.value) / delta,
				}
			end
		end

		local menu = require("KeyframeMenu")
		menu.openCurvePicker(
			payload.owner,
			values,

			function(value)
				if session ~= s or not s.open then
					return
				end

				s.model:setEasing(items, value)
				s.dataDirty = true
				s.poseDirty = true
				s.dirty = true
			end,
			payload.anchor,
			payload.button,
			{
				graph = true,
				host = s.view.frame,
				mousePosition = function()
					return s.view:mousePosition()
				end,
			}
		)
	elseif name == "interpolation" then
		s.model:setInterpolation(
			selectedItems(s),
			type(payload) == "table" and payload.value or payload
		)
	elseif name == "handleType" then
		s.model:setHandleType(
			selectedItems(s),
			type(payload) == "table" and payload.value or payload
		)
	elseif name == "editFrame" or name == "editValue" then
		local value = tonumber(type(payload) == "table" and payload.value or payload)
		local items = selectedItems(s)
		if not finite(value) or #items == 0 then
			updateInspector(s)
			return
		end

		local tx =
			s.model:begin("Set graph key " .. (name == "editFrame" and "frame" or "value"), items)
		if tx then
			tx.snap = s.snap
			local df = name == "editFrame"
					and (s.snap and math.floor(value + 0.5) or value) - items[1].key.frame
				or 0
			local dv = name == "editValue" and value - items[1].key.value or 0
			local ok, err = s.model:updateMove(tx, df, dv)
			if ok == false then
				s.model:cancel(tx)
				status(s, err or "Invalid key value")
			else
				s.model:commit(tx)
			end
		end
	end
end

local function keyboard(s, input)
	local heldKeys = s.view.heldKeys or {}
	if Visibility.input(input, heldKeys) or State.PresentationHidden then
		return
	end

	if
		input.UserInputType ~= Enum.UserInputType.Keyboard
		or not Editor.hasFocus()
		or s.view.search:IsFocused()
		or UserInputService:GetFocusedTextBox()
	then
		return
	end

	local key = input.KeyCode
	if s.panel and s.panel:isPopupOpen() then
		if Shortcuts.matches("Cancel", input, heldKeys) then
			s.panel:_closePopup()
		end

		return
	end

	if s.view.menu then
		if input.KeyCode == Enum.KeyCode.Escape then
			s.view:closeMenu()
		end

		return
	end

	if Shortcuts.matches("TogglePlayback", input, heldKeys) then
		if not s.playbackKey then
			s.playbackKey = key
			action("playPause")
		end
		return
	end

	if
		s.gesture
		and s.gesture.kind == "pendingMove"
		and (
			Shortcuts.matches("GraphDelete", input, heldKeys)
			or Shortcuts.matches("GraphDeleteAlternate", input, heldKeys)
		)
	then
		endGesture(s, false)
	end

	if s.gesture and s.gesture.kind == "circle" then
		if
			Shortcuts.matches("Cancel", input, heldKeys)
			or key == Enum.KeyCode.Return
			or key == Enum.KeyCode.KeypadEnter
			or key == Enum.KeyCode.Space
		then
			endGesture(s, false)
		elseif key == Enum.KeyCode.KeypadPlus or key == Enum.KeyCode.Equals then
			s.gesture.radius = math.min(300, s.gesture.radius * 1.15)
			s.dirty = true
		elseif key == Enum.KeyCode.KeypadMinus or key == Enum.KeyCode.Minus then
			s.gesture.radius = math.max(4, s.gesture.radius / 1.15)
			s.dirty = true
		end

		return
	end

	if
		s.gesture
		and (s.gesture.kind == "move" or s.gesture.kind == "rotate" or s.gesture.kind == "scale")
	then
		local g = s.gesture
		local digits = {
			[Enum.KeyCode.Zero] = "0",
			[Enum.KeyCode.One] = "1",
			[Enum.KeyCode.Two] = "2",
			[Enum.KeyCode.Three] = "3",
			[Enum.KeyCode.Four] = "4",
			[Enum.KeyCode.Five] = "5",
			[Enum.KeyCode.Six] = "6",
			[Enum.KeyCode.Seven] = "7",
			[Enum.KeyCode.Eight] = "8",
			[Enum.KeyCode.Nine] = "9",
			[Enum.KeyCode.KeypadZero] = "0",
			[Enum.KeyCode.KeypadOne] = "1",
			[Enum.KeyCode.KeypadTwo] = "2",
			[Enum.KeyCode.KeypadThree] = "3",
			[Enum.KeyCode.KeypadFour] = "4",
			[Enum.KeyCode.KeypadFive] = "5",
			[Enum.KeyCode.KeypadSix] = "6",
			[Enum.KeyCode.KeypadSeven] = "7",
			[Enum.KeyCode.KeypadEight] = "8",
			[Enum.KeyCode.KeypadNine] = "9",
			[Enum.KeyCode.Period] = ".",
			[Enum.KeyCode.KeypadPeriod] = ".",
		}

		local function field()
			g.numeric = g.numeric or { x = "", y = "", index = g.axis == "Y" and 2 or 1 }
			return g.numeric.index == 2 and "y" or "x"
		end

		if digits[key] then
			local name = field()
			g.numeric[name] ..= digits[key]
			s.pending = mousePosition()
			hintTransform(s)
			return
		elseif key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus then
			local name = field()
			local text = g.numeric[name]
			g.numeric[name] = string.sub(text, 1, 1) == "-" and string.sub(text, 2) or "-" .. text
			s.pending = mousePosition()
			hintTransform(s)
			return
		elseif key == Enum.KeyCode.Backspace and g.numeric then
			local name = field()
			g.numeric[name] = string.sub(g.numeric[name], 1, -2)
			if g.numeric.x == "" and g.numeric.y == "" and not ctrl() then
				g.numeric = nil
			end

			s.pending = mousePosition()
			if g.numeric then
				hintTransform(s)
			end

			return
		elseif key == Enum.KeyCode.Tab and g.kind == "move" then
			field()
			g.numeric.index = g.numeric.index == 1 and 2 or 1
			s.pending = mousePosition()
			hintTransform(s)
			return
		end
	end

	if s.gesture then
		if Shortcuts.matches("Cancel", input, heldKeys) then
			endGesture(s, true)
		elseif
			Shortcuts.matches("ConfirmTransform", input, heldKeys)
			or Shortcuts.matches("ConfirmTransformAlternate", input, heldKeys)
		then
			endGesture(s, false)
		elseif
			(s.gesture.kind == "move" or s.gesture.kind == "scale")
			and (
				Shortcuts.matches("ConstrainX", input, heldKeys)
				or Shortcuts.matches("ConstrainY", input, heldKeys)
			)
		then
			local axis = Shortcuts.matches("ConstrainX", input, heldKeys) and "X" or "Y"
			s.gesture.axis = s.gesture.axis ~= axis and axis or nil
			s.pending = mousePosition()
			if s.gesture.numeric and s.gesture.kind == "move" then
				s.gesture.numeric.index = s.gesture.axis == "Y" and 2 or 1
				hintTransform(s)
			end
		end

		return
	end

	if Shortcuts.matches("ToggleGraphEditor", input, heldKeys) then
		Editor.close()
	elseif Shortcuts.matches("GraphSidebar", input, heldKeys) then
		setPanel(s, not s.panelOpen)
	elseif Shortcuts.matches("GraphInvertSelection", input, heldKeys) then
		for _, track in s.channels do
			if editable(track) then
				for _, k in track.keys do
					if not k.inactive then
						if s.selection[k] then
							s.selection[k] = nil
						else
							s.selection[k] = true
						end
					end
				end
			end
		end

		updateInspector(s)
		refreshHandles(s)
	elseif Shortcuts.matches("GraphSelectColumn", input, heldKeys) then
		local frames = {}
		for _, item in selectedItems(s) do
			frames[item.key.frame] = true
		end

		selectWhere(s, true, function(_, key)
			return frames[key.frame] == true
		end)
	elseif Shortcuts.matches("GraphSelectCurrentColumn", input, heldKeys) then
		local frame = math.floor(currentFrame() + 0.5)
		selectWhere(s, true, function(_, key)
			return math.abs(key.frame - frame) < 1e-4
		end)
	elseif Shortcuts.matches("GraphSelectLinked", input, heldKeys) then
		local tracks = {}
		for _, item in selectedItems(s) do
			tracks[item.track] = true
		end

		if not next(tracks) then
			local track = curveAt(s, mousePosition())
			if track then
				tracks[track] = true
			end
		end

		selectWhere(s, true, function(track)
			return tracks[track] == true
		end)
	elseif Shortcuts.matches("GraphSelectLeft", input, heldKeys) then
		selectSide(s, "left", false)
	elseif Shortcuts.matches("GraphSelectRight", input, heldKeys) then
		selectSide(s, "right", false)
	elseif Shortcuts.matches("GraphJumpToKeys", input, heldKeys) then
		local items = selectedItems(s)
		if #items == 0 then
			s.view:toast("Select keys to jump to.")
		else
			local total, values = 0, 0
			for _, item in items do
				total += item.key.frame
				values += (item.key.value - (item.track.displayOffset or 0)) / (item.track.displayScale or 1)
			end

			seek(s, total / #items)
			s.cursorValue = values / #items
			s.dirty = true
		end
	elseif Shortcuts.matches("GraphToggleSnap", input, heldKeys) then
		s.snap = not s.snap
		if s.view.setSnap then
			s.view:setSnap(s.snap)
		end

		s.view:toast(s.snap and "Snap to frames on" or "Snap to frames off")
	elseif Shortcuts.matches("GraphToggleLock", input, heldKeys) then
		local tracks = selectedTracks(s)
		if #tracks == 0 then
			for _, track in s.channels do
				if track.selected then
					table.insert(tracks, track)
				end
			end
		end

		local lock = false
		for _, track in tracks do
			if not track.locked then
				lock = true
			end
		end

		for _, track in s.channels do
			if track.selected or table.find(tracks, track) then
				track.locked = lock
			end
		end

		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
	elseif
		Shortcuts.matches("GraphHide", input, heldKeys)
		or Shortcuts.matches("GraphHideUnselected", input, heldKeys)
	then
		local unselected = Shortcuts.matches("GraphHideUnselected", input, heldKeys)
		local chosen = {}
		for _, track in s.channels do
			if track.selected then
				chosen[track] = true
			end
		end

		for _, item in selectedItems(s) do
			chosen[item.track] = true
		end

		for _, track in s.channels do
			if (chosen[track] == true) ~= unselected then
				track.visible = false
			end
		end

		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
	elseif Shortcuts.matches("GraphReveal", input, heldKeys) then
		for _, track in s.channels do
			track.visible = true
		end

		rememberChannels(s)
		s.view:setData({ channels = s.channels })
		updateInspector(s)
	elseif Shortcuts.matches("GraphExtrapolation", input, heldKeys) then
		s.panel:_popup(
			nil,
			{
				{ text = "Constant Extrapolation", value = "Constant" },
				{ text = "Linear Extrapolation", value = "Linear" },
				{ text = "Make Cyclic (F-Modifier)", value = "make" },
				{ text = "Clear Cyclic (F-Modifier)", value = "clear" },
			},
			nil,

			function(choice)
				local tracks = selectedTracks(s)
				if #tracks == 0 then
					s.view:toast("Select curves first.")
					return
				end

				if choice == "Constant" or choice == "Linear" then
					if s.model:setExtrapolation(tracks, choice) == false then
						s.view:toast("Those curves can't be changed right now.")
					end

					return
				end

				local motors = {}
				for _, track in tracks do
					motors[track.motor] = true
				end

				s.panel:_record(choice == "make" and "Make Cyclic" or "Clear Cyclic", motors, function()
					for _, track in tracks do
						local entry = Mods.ensure(track.motor, track.channelId)
						if choice == "make" then
							if not Mods.cycleType(entry) and #entry.Stack == 0 then
								Mods.add(entry, "Cycles")
							end
						else
							for i = #entry.Stack, 1, -1 do
								if entry.Stack[i].Type == "Cycles" then
									table.remove(entry.Stack, i)
								end
							end
						end
					end
				end
)
			end,
			"SET KEYFRAME EXTRAPOLATION"
		)
	elseif Shortcuts.matches("GraphMirror", input, heldKeys) then
		s.panel:_popup(
			nil,
			{
				{ text = "By Times Over Current Frame", value = "cfra" },
				{ text = "By Values Over Cursor Value", value = "cursor" },
				{ text = "By Times Over Zero Time", value = "time0" },
				{ text = "By Values Over Zero Value", value = "value0" },
			},
			nil,

			function(mode)
				local items = selectedItems(s)
				if #items == 0 then
					s.view:toast("Select keys to mirror.")
					return
				end

				local keyMap, pointMap
				if mode == "cfra" or mode == "time0" then
					local pivot = mode == "cfra" and currentFrame() or 0
					keyMap = function(frame, value)
						return 2 * pivot - frame, value
					end

					pointMap = function(point)
						local incoming, outgoing = point.In, point.Out
						point.In = outgoing and { -outgoing[1], outgoing[2] } or nil
						point.Out = incoming and { -incoming[1], incoming[2] } or nil
					end
				else
					keyMap = function(frame, value, track)
						local pivot = mode == "value0" and 0
							or (s.cursorValue or 0) * (track.displayScale or 1)
								+ (track.displayOffset or 0)
						return frame, 2 * pivot - value
					end

					pointMap = function(point)
						for _, side in { "In", "Out" } do
							if point[side] then
								point[side] = { point[side][1], -point[side][2] }
							end
						end
					end
				end

				local ok, err = s.model:remapKeys("Mirror Keys", items, keyMap, pointMap, true)
				if ok == false and err then
					s.view:toast(err)
				end
			end,
			"MIRROR"
		)
	elseif Shortcuts.matches("GraphSnap", input, heldKeys) then
		s.panel:_popup(
			nil,
			{
				{ text = "Selection to Current Frame", value = "cfra" },
				{ text = "Selection to Cursor Value", value = "value" },
				{ text = "Selection to Nearest Frame", value = "frame" },
				{ text = "Selection to Nearest Second", value = "second" },
				{ text = "Flatten Handles", value = "flatten" },
				{ text = "Cursor to Selected", value = "cursor" },
				{ text = "Cursor Value to Selection", value = "cursorValue" },
			},
			nil,

			function(mode)
				local items = selectedItems(s)
				if #items == 0 then
					s.view:toast("Select keys first.")
					return
				end

				if mode == "cursor" or mode == "cursorValue" then
					local total, values = 0, 0
					for _, item in items do
						total += item.key.frame
						values += (item.key.value - (item.track.displayOffset or 0)) / (item.track.displayScale or 1)
					end

					if mode == "cursor" then
						seek(s, total / #items)
					end

					s.cursorValue = values / #items
					s.dirty = true
					return
				end

				if mode == "flatten" then
					s.model:flattenHandles(items)
					return
				end

				local fps = State.Timeline:GetState().FPS
				local frame = math.floor(currentFrame() + 0.5)
				local keyMap = function(f, value, track)
					if mode == "cfra" then
						return frame, value
					elseif mode == "value" then
						return f,
							(s.cursorValue or 0) * (track.displayScale or 1)
								+ (track.displayOffset or 0)
					elseif mode == "frame" then
						return math.floor(f + 0.5), value
					end

					return math.floor(f / fps + 0.5) * fps, value
				end

				local ok, err = s.model:remapKeys("Snap Keys", items, keyMap, function() end, true)
				if ok == false and err then
					s.view:toast(err)
				end
			end,
			"SNAP"
		)
	elseif Shortcuts.matches("GraphZoomBorder", input, heldKeys) then
		s.zoomArmed = true
		s.boxArmed = false
		s.view:toast("Drag a box to zoom into")
	elseif Shortcuts.matches("GraphCircleSelect", input, heldKeys) then
		s.gesture =
			{ kind = "circle", radius = 25 * s.view:_scale(), at = mousePosition(), modal = true }
		s.dirty = true
		s.view:toast(
			"Circle select · LMB select · Shift/MMB deselect · Wheel size · RMB/Esc done"
		)
	elseif Shortcuts.matches("GraphAddModifier", input, heldKeys) then
		if #selectedTracks(s) == 0 then
			s.view:toast("Select curves before adding a modifier.")
		else
			s.panel:openAddMenuAt()
		end
	elseif Shortcuts.matches("Cancel", input, heldKeys) then
		resetSelection(s)
	elseif Shortcuts.matches("GraphRotationFilter", input, heldKeys) then
		action("filterRotation")
	elseif Shortcuts.matches("GraphFitAll", input, heldKeys) then
		fit(s, false)
	elseif
		Shortcuts.matches("GraphFocus", input, heldKeys)
		or Shortcuts.matches("GraphFocusAlternate", input, heldKeys)
	then
		fit(s, true)
	elseif Shortcuts.matches("GraphMove", input, heldKeys) then
		beginMove(s, mousePosition(), true)
	elseif Shortcuts.matches("GraphRotate", input, heldKeys) then
		beginTransform(s, mousePosition(), "rotate")
	elseif Shortcuts.matches("GraphScale", input, heldKeys) then
		beginTransform(s, mousePosition(), "scale")
	elseif Shortcuts.matches("GraphBoxSelect", input, heldKeys) then
		s.boxArmed = true
		status(s, "Drag a box to select keys · Shift to add")
	elseif
		Shortcuts.matches("GraphSelectAll", input, heldKeys)
		or Shortcuts.matches("SelectAll", input, heldKeys)
		or Shortcuts.matches("GraphDeselect", input, heldKeys)
	then
		if Shortcuts.matches("GraphDeselect", input, heldKeys) then
			resetSelection(s)
		else
			for _, track in s.channels do
				if track.visible ~= false and not track.locked and not track.keysHidden then
					for _, k in track.keys do
						if not k.inactive then
							s.selection[k] = true
						end
					end
				end
			end

			updateInspector(s)
			refreshHandles(s)
		end
	elseif
		Shortcuts.matches("Undo", input, heldKeys)
		or Shortcuts.matches("UndoAlternate", input, heldKeys)
	then
		History.shortcut("undo")
		Editor.invalidate()
	elseif
		Shortcuts.matches("Redo", input, heldKeys)
		or Shortcuts.matches("RedoAlternate", input, heldKeys)
		or Shortcuts.matches("RedoShift", input, heldKeys)
	then
		History.shortcut("redo")
		Editor.invalidate()
	elseif Shortcuts.matches("Copy", input, heldKeys) then
		action("copy")
	elseif Shortcuts.matches("Paste", input, heldKeys) then
		action("paste")
	elseif Shortcuts.matches("GraphDuplicate", input, heldKeys) then
		action("duplicate")
	elseif
		Shortcuts.matches("GraphDelete", input, heldKeys)
		or Shortcuts.matches("GraphDeleteAlternate", input, heldKeys)
	then
		action("delete")
	elseif Shortcuts.matches("GraphInsert", input, heldKeys) then
		action("insert")
	elseif Shortcuts.matches("OpenKeyframeMenu", input, heldKeys) then
		updateInspector(s)
		s.view:openMenu(mousePosition())
	elseif Shortcuts.matches("GraphInterpolation", input, heldKeys) then
		s.view:openMenu(mousePosition(), "interpolation")
	elseif Shortcuts.matches("GraphHandles", input, heldKeys) then
		s.view:openMenu(mousePosition(), "handles")

	elseif Shortcuts.matches("GraphPreviousKeyframe", input, heldKeys) then
		local frame = State.Timeline:GetJumpKeyframe(currentFrame(), "Left", 1)
		if frame then
			seek(s, frame)
		end
	elseif Shortcuts.matches("GraphNextKeyframe", input, heldKeys) then
		local frame = State.Timeline:GetJumpKeyframe(currentFrame(), "Right", 1)
		if frame then
			seek(s, frame)
		end
	elseif Shortcuts.matches("GraphPreviousFrame", input, heldKeys) then
		seek(s, currentFrame() - 1)
	elseif Shortcuts.matches("GraphNextFrame", input, heldKeys) then
		seek(s, currentFrame() + 1)
	end
end

local function syncChannelFocus(s)
	if not State.Rig.GetSelectedChannels then
		return
	end

	local selected = State.Rig:GetSelectedChannels()
	local signature = {}
	for _, item in selected do
		table.insert(signature, tostring(item))
	end

	table.sort(signature)
	signature = table.concat(signature, "|")
	if signature == s.timelineChannelSignature then
		return
	end

	s.timelineChannelSignature = signature
	s.focusChannels = {}
	s.activeTrack = nil
	for _, item in selected do
		local bone = item.parentBoneItem
		local motor = bone and bone.fetchMotor and bone:fetchMotor()
		for _, track in s.channels do
			local match = track.channelId == item.channelId
			if motor == track.motor and match then
				s.focusChannels[track.id] = true
				track.visible = true
			end
		end
	end

	rememberChannels(s)
	updateInspector(s)
	s.view:_refreshRows()
	fit(s, false)
end

step = function(s)
	if State.PresentationHidden then
		return
	end

	if s.busy or not s.open or not s.view:isVisible() then
		return
	end

	s.busy = true
	local ok, err = xpcall(function()
		if not UI.isAnimatorActive() then
			return
		end

		local pointer = s.pointerInput
		if
			s.gesture
			and not s.gesture.modal
			and pointer
			and (
				pointer.UserInputState == Enum.UserInputState.End
				or pointer.UserInputState == Enum.UserInputState.Cancel
			)
		then
			endGesture(s, pointer.UserInputState == Enum.UserInputState.Cancel)
		end

		s.view:flushWindowDrag()
		if s.view.docked and s.gesture then
			local p = mousePosition()
			if p ~= s.lastDockPoint then
				s.pending = p
				s.lastDockPoint = p
			end
		end

		if s.pending then
			local point = s.pending
			s.pending = nil
			processPointer(s, point)
		end

		if not s.gesture and not s.view.drag and os.clock() - s.lastSelectionCheck > 0.12 then
			s.lastSelectionCheck = os.clock()
			syncChannelFocus(s)
			local motors, rigs = gatherMotors()
			if not sameMotors(s.motors, motors) then
				s.motors = motors
				s.rigs = rigs
				s.dataDirty = true
				s.fitNext = true
			end
		end

		if s.dataDirty and not s.gesture then
			rebuild(s, s.fitNext)
			s.fitNext = false
		end

		if s.pendingReveal and not s.dataDirty then
			local reveal = s.pendingReveal
			s.pendingReveal = nil
			for _, track in s.channels do
				if reveal[track.motor] and track.modified then
					track.visible = true
				end
			end

			rememberChannels(s)
			s.view:setData({ channels = s.channels })
			updateInspector(s)
			s.dirty = true
		end

		resizeValueRange(s)
		if s.poseDirty and not State.Timeline:GetState().Playing then
			applyPose(s)
		end

		local frame = currentFrame()
		if s.dirty then
			local changed = false
			for _, track in s.channels do
				local previous = track.plotPoints
				s.model:prepareDisplay(track, true)
				if previous ~= track.plotPoints then
					changed = true
				end
			end

			if changed then
				updateValueBounds(s)
			end

			local navigation = s.gesture
				and (
					s.gesture.kind == "pan"
					or s.gesture.kind == "scroll"
					or s.gesture.kind == "valueScroll"
				)
			if not navigation then
				refreshHandles(s)
			end

			local plotWidth = s.view.plot.AbsoluteSize.X / s.view:_scale()
			local perFrame = plotWidth / math.max(1e-6, s.range.frameMax - s.range.frameMin)
			local activeCurve = panelTrack(s)
			for _, track in s.channels do
				track.drawPoints = (track.modified or track.linear)
						and track.visible ~= false
						and s.model:modifiedPoints(
							track,
							s.range.frameMin,
							s.range.frameMax,
							perFrame
						)
					or nil
				local envelope = track.keysHidden
					and track == activeCurve
					and Mods.active(track.modEntry)
				track.envelope = envelope
						and envelope.Type == "Envelope"
						and not envelope.Mute
						and envelope
					or nil
			end

			local range = table.clone(s.range)
			range.bounds = s.bounds
			range.playhead = frame
			range.selection = s.selection
			range.box = s.box and { s.box.from, s.box.to }
			range.lasso = s.gesture and s.gesture.kind == "lasso" and s.gesture.points or nil
			range.cursorValue = s.cursorValue or 0
			range.circle = s.gesture and s.gesture.kind == "circle" and s.gesture or nil
			if not (navigation and s.view:pan(range)) then
				s.view:render(range)
			end

			s.dirty = false
		else
			s.view:setPlayhead(frame)
		end

		if s.view.setPlaying then
			s.view:setPlaying(State.Timeline:GetState().Playing)
		end

		if s.panel and s.panelOpen then
			s.panel:refresh(false)
		end
	end, debug.traceback)
	s.busy = false
	if not ok then
		if s.gesture then
			pcall(endGesture, s, true)
		end

		warn("Eclipse graph editor: " .. tostring(err))
		status(s, "The edit was stopped. Your last committed keys are preserved.")

		s.dirty = false
		s.dataDirty = false
		s.poseDirty = false
	end
end

function Editor.invalidate()
	if session then
		session.dataDirty = true
	end
end

function Editor.open()
	if not initialized or not State.Timeline or not UI.isAnimatorActive() then
		return
	end

	if session and not session.view then
		return
	end

	if session and session.open then
		session.view:setVisible(true)
		refreshToggle()
		return
	end

	if refs.OnOpen then
		refs.OnOpen()
	end

	if not session then
		local s = {
			open = false,
			connections = {},
			channels = {},
			selection = {},
			channelState = {},
			motors = {},
			rigs = {},
			snap = true,
			dirty = true,
			dataDirty = true,
			lastSelectionCheck = 0,
			range = { frameMin = -10, frameMax = 280, valueMin = -1, valueMax = 1 },
			status = "MMB pan · Wheel zoom · G move · B box select · Home frame all",
		}
		session = s
		s.model = GraphModel.new({
			Timeline = State.Timeline,
			History = History,
			onChanged = function(phase)
				if phase == "undo" or phase == "redo" then
					local ids = {}
					for _, item in selectedItems(s) do
						if item.key.id then
							ids[item.key.id] = true
						end
					end

					if next(ids) then
						s.historySelection = ids
					elseif s.historySelection then
						s.wantSelectIds = s.historySelection
					end
				end

				if phase ~= "preview" then
					s.dataDirty = true
					if phase ~= "cancel" then
						State.currentProjectSaved = false
						MotionPath.markDirty()
					end
				end

				s.dirty = true
				s.poseDirty = true
				if not s.open and (phase == "undo" or phase == "redo") then
					task.defer(function()
						if
							session == s
							and not s.open
							and State.Timeline
							and not State.Timeline:GetState().Playing
						then
							local ok, err = pcall(applyPose, s)
							if not ok then
								warn("Eclipse graph history pose: " .. tostring(err))
							end
						end
					end)
				end
			end,
		})
		local customize = UI.EclipseGUI:FindFirstChild("EclipseCustomize")
		s.view = GraphView.create(refs.Parent or UI.RootFrame, action, {
			hoverDialog = refs.HoverDialog,
			plugin = refs.Plugin,
			tickStep = State.Timeline.GetMajorTickStep and function(pixelsPerFrame)
				return State.Timeline:GetMajorTickStep(pixelsPerFrame)
			end,
			templates = {
				Dropdown = UI.Dropdowns and UI.Dropdowns:FindFirstChild("DropdownTemplate"),
				Background = UI.AnimatorFrame,
				Header = customize and customize:FindFirstChild("Bar"),
				Outline = customize and customize:FindFirstChild("Backdrop"),
				Tick = UI.TickTemplate,
				Chip = UI.TopSelector,
				Line = UI.Selector,
				Scroll = UI.TopSlider,
			},
		})
		s.panel = ModifierPanel.new(s.view, panelHost(s), s.view.body)
		s.view:setSidebarFrame(s.panel.frame)
		s.view.onTheme = function()
			if s.panel then
				s.panel:applyTheme()
			end
		end

		local ok, saved = pcall(function()
			return refs.Plugin and refs.Plugin:GetSetting(PANEL_SETTING)
		end)
		if ok and saved == true then
			setPanel(s, true, true)
		end
	end

	local s = session
	s.open = true
	refreshToggle()
	s.motors, s.rigs = gatherMotors()
	rebuild(s, true)
	syncChannelFocus(s)
	s.view:setVisible(true)
	if session ~= s or not s.open then
		return
	end

	refreshToggle()
	connect(s.connections, s.view.plot.InputBegan, function(input)
		plotDown(s, input)
	end)
	connect(s.connections, s.view.plot.InputChanged, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseWheel
			and not require("NumericInput").contains(mousePosition())
		then
			zoom(s, mousePosition(), input.Position.Z)
		end
	end)

	local function scrollDown(input, side)
		if s.view.menu or s.view.menuDismissInput == input then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if s.gesture then
			if s.gesture.kind == "scroll" and side then
				s.gesture.side = side
			end

			return
		end

		s.pointerInput = input
		s.gesture = {
			kind = "scroll",
			side = side,
			start = mousePosition(),
			range = table.clone(s.range),
		}
	end

	connect(s.connections, s.view.scrollThumb.InputBegan, function(input)
		scrollDown(input)
	end)
	connect(s.connections, s.view.scrollLeft.InputBegan, function(input)
		scrollDown(input, "left")
	end)
	connect(s.connections, s.view.scrollRight.InputBegan, function(input)
		scrollDown(input, "right")
	end)
	connect(s.connections, s.view.valueThumb.InputBegan, function(input)
		valueScrollDown(s, input)
	end)
	connect(s.connections, s.view.valueTop.InputBegan, function(input)
		valueScrollDown(s, input, "top")
	end)
	connect(s.connections, s.view.valueBottom.InputBegan, function(input)
		valueScrollDown(s, input, "bottom")
	end)
	connect(s.connections, s.view.valueScrollbar.InputBegan, function(input)
		valueScrollDown(s, input)
	end)
	connect(s.connections, s.view.valueScrollbar.InputChanged, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseWheel
			and not require("NumericInput").contains(mousePosition())
		then
			scrollValues(s, input.Position.Z * 0.15)
		end
	end)

	local function rulerDown(input)
		if s.view.menu or s.view.menuDismissInput == input then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if s.gesture then
				endGesture(s, false)
			end

			s.pointerInput = input
			s.gesture = { kind = "scrub" }
			s.pending = mousePosition()
		end
	end

	connect(s.connections, s.view.ruler.InputBegan, rulerDown)
	if s.view.playheadChip then
		s.view.playheadChip.Active = true
		connect(s.connections, s.view.playheadChip.InputBegan, rulerDown)
	end

	local function changed(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and s.gesture then
			s.pending = mousePosition()
		end
	end

	local function ended(input)
		if input.KeyCode == s.playbackKey then
			s.playbackKey = nil
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			s.view.heldKeys[input.KeyCode] = nil
		end

		Visibility.release(input)
		local g = s.gesture
		if g and g.kind == "circle" then
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton3
			then
				g.painting = nil
			end

			return
		end

		if not g or g.modal then
			return
		end

		local middle = g.kind == "pan" or g.kind == "zoomDrag"
		if
			(middle and input.UserInputType == Enum.UserInputType.MouseButton3)
			or (g.button == 2 and input.UserInputType == Enum.UserInputType.MouseButton2)
			or (
				not middle
				and g.button ~= 2
				and input.UserInputType == Enum.UserInputType.MouseButton1
			)
		then
			s.pending = mousePosition()
			endGesture(s, false)
		end
	end

	local delivered = setmetatable({}, { __mode = "k" })

	local function began(input)
		if delivered[input] then
			return
		end

		delivered[input] = true
		task.defer(function()
			delivered[input] = nil
		end)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			s.view.heldKeys[input.KeyCode] = true
		end

		if
			s.gesture
			and s.gesture.modal
			and input.UserInputType == Enum.UserInputType.MouseButton1
			and not inside(s.view.plot, mousePosition())
		then
			endGesture(s, false)
			return
		end

		if
			s.gesture
			and input.UserInputType == Enum.UserInputType.MouseButton2
			and s.gesture.input ~= input
			and s.gesture.kind ~= "circle"
		then
			endGesture(s, true)
			return
		end

		keyboard(s, input)
	end

	s.inject = function(kind, input)
		if kind == "began" then
			began(input)
		elseif kind == "ended" then
			ended(input)
		else
			changed(input)
		end
	end

	local function watchKeyboard(object)
		if
			not object:IsA("GuiObject")
			or not (object.Active or object:IsA("GuiButton") or object:IsA("TextBox"))
		then
			return
		end

		if
			not object:IsDescendantOf(s.view.frame)
			or s.panel
				and (object:IsDescendantOf(s.panel.list) or s.panel.popup and object:IsDescendantOf(
					s.panel.popup
				))
		then
			return
		end

		connect(s.connections, object.InputBegan, function(input)
			if s.view.docked and input.UserInputType == Enum.UserInputType.Keyboard then
				began(input)
			end
		end)
		connect(s.connections, object.InputEnded, function(input)
			if s.view.docked and input.UserInputType == Enum.UserInputType.Keyboard then
				ended(input)
			end
		end)
	end

	for _, object in s.view.frame:GetDescendants() do
		watchKeyboard(object)
	end

	connect(s.connections, s.view.frame.DescendantAdded, watchKeyboard)
	for _, entry in
		{ { "InputChanged", changed }, { "InputEnded", ended }, { "InputBegan", began } }
	do
		connect(s.connections, UserInputService[entry[1]], function(input)
			if not s.view.docked then
				entry[2](input)
			end
		end)
		connect(s.connections, s.view.frame[entry[1]], function(input)
			if s.view.docked then
				entry[2](input)
			end
		end)
	end

	connect(s.connections, UserInputService.WindowFocusReleased, function()
		s.playbackKey = nil
		if not s.view.docked and s.gesture then
			endGesture(s, true)
		end
	end)
	connect(s.connections, RunService.RenderStepped, function()
		step(s)
	end)
	step(s)
end

function Editor.close()
	local s = session
	if not s or not s.open then
		return
	end

	if s.gesture then
		endGesture(s, true)
	end

	if s.poseDirty and State.Timeline and not State.Timeline:GetState().Playing then
		local ok, err = pcall(applyPose, s)
		if not ok then
			warn("Eclipse graph pose restore: " .. tostring(err))
		end
	end

	s.open = false
	s.pending = nil
	refreshToggle()
	if s.panel then
		s.panel:_closePopup()
	end

	disconnect(s.connections)
	s.view:setVisible(false)
end

function Editor.presentationWidget()
	return session and session.view and session.view.widget
end

function Editor.session()
	return session
end

function Editor.toggle()
	if Editor.isOpen() then
		Editor.close()
	else
		Editor.open()
	end
end

function Editor.init(options)
	if initialized then
		return
	end

	initialized = true
	refs = options or {}
	State.GraphEditor = Editor
	unsubscribePreferences = Preferences.subscribe(function(key)
		if key == "ColorKeysByInterpolation" then
			if State.Timeline then
				State.Timeline:RefreshAllKeyframeVisuals()
				State.Timeline:RefreshAllChannelDiamondColors()
			end
			if session then session.dataDirty = true end
			return
		end
		if key == "GraphAutoSmoothing" then
			require("GraphCurves").resetAll()
			local s = session
			if s then
				s.model:invalidate()
				s.dataDirty = true
				s.poseDirty = true
			end

			if State.Timeline and State.currentRig and not State.Timeline:GetState().Playing then
				pcall(function()
					State.Timeline:ApplyPoseAtTime(
						State.currentRig,
						State.Timeline:GetState().CurrentTime
					)
				end)
			end

			return
		end

		if key ~= "GraphClamp" and key ~= "GraphCompressionPercent" then
			return
		end

		local s = session
		if not s then
			return
		end

		if s.gesture then
			endGesture(s, true)
		end

		updateBounds(s)
		if key == "GraphClamp" then
			s.range.valueMin = s.bounds.valueMin
			s.range.valueMax = s.bounds.valueMax
		end

		clampRange(s)
		s.plotHeight = nil
		s.dirty = true
	end)
	connect(lifetime, UI.EclipseGUI:GetPropertyChangedSignal("Enabled"), function()
		if not UI.EclipseGUI.Enabled then
			Editor.close()
		end
	end)
	connect(lifetime, UI.AnimatorFrame:GetPropertyChangedSignal("Visible"), function()
		if not UI.AnimatorFrame.Visible and not State.PresentationHidden then
			Editor.close()
		end
	end)
	connect(lifetime, UI.EclipseGUI.Destroying, Editor.destroy)

	for _, name in
		{
			"RefreshIKEndMarkers",
			"CreateOrUpdateTimelineKeyframeButton",
			"RefreshAllKeyframeVisuals",
			"RefreshAllChannelDiamondsForMotor",
			"RebuildAllTimelineKeyframeButtons",
			"_restoreMotorBucket",
			"DeleteKeyframe",
			"MoveKeyframe",
		}
	do
		local original = State.Timeline[name]
		if original then
			local wrapper = function(self, ...)
				local results = table.pack(original(self, ...))
				Editor.invalidate()
				return table.unpack(results, 1, results.n)
			end

			hooks[name] = { original = original, wrapper = wrapper }
			State.Timeline[name] = wrapper
		end
	end
end

function Editor.destroy()
	Editor.close()
	if session then
		if session.panel then
			session.panel:destroy()
		end

		session.view:destroy()
		session = nil
	end

	disconnect(lifetime)
	if unsubscribePreferences then
		unsubscribePreferences()
		unsubscribePreferences = nil
	end

	for name, entry in hooks do
		if State.Timeline and State.Timeline[name] == entry.wrapper then
			State.Timeline[name] = entry.original
		end
	end

	table.clear(hooks)
	State.GraphEditor = nil
	initialized = false
end

return Editor
