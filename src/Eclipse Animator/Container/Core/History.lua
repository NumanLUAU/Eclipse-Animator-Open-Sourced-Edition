--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Shortcuts = require("Shortcuts")
local BlenderEdit = require("BlenderEdit")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local GraphRootState = require("State")
local History = {}

local undoStack = {}
local redoStack = {}
local maxSize = 1000

local applyingUndoRedo = false
local connections = {}
local onNotify = nil
local listeners = {}
local batches = setmetatable({}, { __mode = "k" })

local function changed()
	for callback in listeners do
		task.defer(callback)
	end
end

function History.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

local jumpToFrameCallback = nil
local activeCheckFn = nil
local beforeUndoRedo = nil
local shortcutHeld = {}

function History.isApplying()
	return applyingUndoRedo
end

local guardCallbacks = {}
local guardCleanupCallback = nil

local function push(stack, item)
	table.insert(stack, item)
	if #stack > maxSize then
		table.remove(stack, 1)
	end
end

local function isActive()
	if GraphRootState.WorkspaceSelection then
		return false
	end

	if GraphRootState.GraphEditor and GraphRootState.GraphEditor.hasFocus() then
		return false
	end

	if GraphRootState.CameraPreview and GraphRootState.CameraPreview.isFull() then
		return true
	end

	if not activeCheckFn then
		return true
	end

	local ok, result = pcall(activeCheckFn)
	return ok and result == true
end

local externalRecordings = {}
local externalBefore = nil
local externalLabel = nil
local placement = { parts = {}, scales = {}, pivots = {} }
local placementParts = {}
local placementModels = {}
local placementRefreshAt = 0
const PLACEMENT_REFRESH = 2
const SELECTION_LIMIT = 512
const RECORDING_TIMEOUT = 30
const PLACEMENT_LIMIT = 2048
const PLACEMENT_FULL_REFRESH = 10
const ownLabels = {}
const rigCandidates = setmetatable({}, { __mode = "k" })
const watchedParts = {}
const movedParts = {}
const knownRigs = {}
const NativeInput = game:GetService("UserInputService")
local placementLive = false
local placementDirty = true
local placementFullAt = 0
const studioBase = { undo = nil, redo = nil }
const trackedParents = setmetatable({}, { __mode = "k" })
const trackedLinks = {}
const probeParent = Instance.new("Folder")
const PARENT_LIMIT = 256
const REVERT_TIMEOUT = 1
const SENTINEL = "EclipseAnimator_Session"
const NATIVE_ECHO = 0.5
const ARM_ECHO = 0.25
const SHORTCUT_ECHO = 0.5
const ARM_RETRY = 1
const armSelection = {}
const shortcutRoutes = { undo = { source = nil, at = -math.huge }, redo = { source = nil, at = -math.huge } }
local armed = false
local armPending = false
local armForce = false
local armEchoes = 0
local armEchoAt = -math.huge
local armRetryAt = 0
local armSelectionCount = 0
local nativeChangedAt = -math.huge
local studioEdited = false
local sessionDirty = false
local sessionWasOpen = false
local selectionDirty = false
local uiModule = nil

local function studioTop()
	local undoName, redoName = nil, nil
	const okUndo, canUndo, nameUndo = pcall(ChangeHistoryService.GetCanUndo, ChangeHistoryService)
	if okUndo and canUndo then
		undoName = nameUndo or ""
	end

	const okRedo, canRedo, nameRedo = pcall(ChangeHistoryService.GetCanRedo, ChangeHistoryService)
	if okRedo and canRedo then
		redoName = nameRedo or ""
	end

	return undoName, redoName
end

local function sameSelection()
	const current = Selection:Get()
	if #current ~= armSelectionCount then
		return false
	end

	for _, object in current do
		if not armSelection[object] then
			return false
		end
	end

	return true
end

local function untrackObject(object)
	trackedParents[object] = nil
	const link = trackedLinks[object]
	if link then
		trackedLinks[object] = nil
		link:Disconnect()
	end
end

local function trackObject(object, parent)
	trackedParents[object] = parent
	if not trackedLinks[object] then
		const ok, link = pcall(function()
			return object.Destroying:Connect(function()
				untrackObject(object)
			end)
		end)
		if ok then
			trackedLinks[object] = link
		else
			trackedParents[object] = nil
		end
	end
end

local function restorable(object, parent)
	if typeof(parent) ~= "Instance" or not parent:IsDescendantOf(game) then
		return false
	end

	return (pcall(function()
		object.Parent = probeParent
		object.Parent = nil
	end))
end

local function recordingOpen()
	if next(externalRecordings) then
		return true
	end

	const ok, open = pcall(ChangeHistoryService.IsRecordingInProgress, ChangeHistoryService)
	return ok and open == true
end

local function trackSelection()
	selectionDirty = true
	if armed and not armPending and not sameSelection() then
		armPending = true
	end

	local count = 0
	for _ in trackedParents do
		count += 1
	end

	const camera = workspace.CurrentCamera
	for _, object in Selection:Get() do
		if count >= PARENT_LIMIT then
			break
		end

		const parent = object.Parent
		if parent and trackedParents[object] == nil and not (camera and object:IsDescendantOf(camera)) then
			trackObject(object, parent)
			count += 1
		end
	end
end

local function pruneSelection(forgetDeleted)
	selectionDirty = false
	const current = {}
	for _, object in Selection:Get() do
		current[object] = true
	end

	for object in trackedParents do
		const parent = object.Parent
		if parent == nil then
			if forgetDeleted then
				untrackObject(object)
			end
		elseif current[object] then
			trackedParents[object] = parent
		else
			untrackObject(object)
		end
	end
end

local function deletionPending()
	for object in trackedParents do
		if object.Parent == nil then
			return true
		end
	end

	return false
end

local function markStudioBase()
	studioBase.undo, studioBase.redo = studioTop()
	studioEdited = false
	pruneSelection(true)
end

local function studioChanged()
	const undoName, redoName = studioTop()
	if undoName == studioBase.undo and redoName == studioBase.redo then
		return undoName ~= nil and (studioEdited or deletionPending())
	end

	if redoName ~= nil and redoName == studioBase.undo or undoName ~= nil and undoName == studioBase.redo then
		return false
	end

	return true
end

local function clearStudioStack()
	ChangeHistoryService:SetWaypoint("EclipseAnimator_Reset_Begin")
	ChangeHistoryService:SetWaypoint("EclipseAnimator_Reset_End")
	ChangeHistoryService:ResetWaypoints()
end

local function projectBusy()
	if GraphRootState.LoadingProject then
		return true
	end

	const timeline = GraphRootState.Timeline
	return timeline ~= nil and timeline.IsExportLocked ~= nil and timeline:IsExportLocked() == true
end

local function sessionOpen()
	if GraphRootState.LoadingProject or isActive() then
		return true
	end

	if activeCheckFn then
		const ok, result = pcall(activeCheckFn)
		if ok and result == true then
			return true
		end
	end

	if uiModule == nil then
		const ok, module = pcall(require, "UI")
		uiModule = ok and module or false
	end

	const gui = uiModule and uiModule.EclipseGUI
	return typeof(gui) == "Instance"
		and gui.Enabled
		and gui:GetAttribute("EclipseConfirmationOpen") == true
		and GraphRootState.currentRig ~= nil
end

local function armStudio()
	armPending, armForce = false, false
	if recordingOpen() then
		armPending, armForce = true, true
		return false
	end

	const current = Selection:GetAttribute(SENTINEL)
	const base = if current == 1 or current == 2 then 3 else 1
	clearStudioStack()
	armed = true
	Selection:SetAttribute(SENTINEL, base)
	ChangeHistoryService:SetWaypoint(SENTINEL)
	Selection:SetAttribute(SENTINEL, base + 1)
	ChangeHistoryService:SetWaypoint(SENTINEL)
	armEchoes += 1
	armEchoAt = os.clock()
	ChangeHistoryService:Undo()
	table.clear(armSelection)
	armSelectionCount = 0
	for _, object in Selection:Get() do
		armSelection[object] = true
		armSelectionCount += 1
	end

	markStudioBase()
	return true
end

local function disarmStudio()
	armPending, armForce = false, false
	const tagged = Selection:GetAttribute(SENTINEL) ~= nil
	if tagged then
		Selection:SetAttribute(SENTINEL, nil)
	end

	if armed or tagged then
		armed = false
		clearStudioStack()
		markStudioBase()
	end
end

local function resetStudioWaypoints(force)
	if force or armed or ChangeHistoryService:GetCanUndo() or ChangeHistoryService:GetCanRedo() then
		clearStudioStack()
	end

	armed = false
	sessionDirty = false
	if not (sessionOpen() and armStudio()) then
		markStudioBase()
	end
end

local function maintainArm(strict)
	if applyingUndoRedo or os.clock() < armRetryAt or recordingOpen() then
		return
	end

	const undoName, redoName = studioTop()
	if undoName == SENTINEL and redoName == SENTINEL and not armPending then
		return
	end

	if
		not strict
		and not armForce
		and (undoName ~= nil and undoName ~= SENTINEL or redoName ~= nil and redoName ~= SENTINEL)
	then
		armPending = false
		return
	end

	const ok, err = pcall(armStudio)
	if not ok then
		armed = false
		armRetryAt = os.clock() + ARM_RETRY
		warn("Eclipse could not route Studio undo to the animator:", err)
		return
	end

	const armedUndo, armedRedo = studioTop()
	if err and not (armedUndo == SENTINEL and armedRedo == SENTINEL) then
		armRetryAt = os.clock() + ARM_RETRY
	end
end

local function bindEntry(undoFn, redoFn, description, contextFrame, redoContextFrame)
	local undoCF, redoCF
	if type(contextFrame) == "table" then
		undoCF = contextFrame.undo
		redoCF = contextFrame.redo
	else
		undoCF = contextFrame
		redoCF = redoContextFrame
	end

	local raw = require("RawState").Timeline
	local layerId = raw.AnimationLayers and raw.AnimationLayers.active
	local master = raw.AnimationLayers and raw.AnimationLayers.master
	local activeByRig = raw.AnimationLayers and table.clone(raw.AnimationLayers.activeByRig or {})

	local function bound(fn)
		return function()
			return require("Layers").history(layerId, fn, master, activeByRig)
		end
	end

	return {
		undo = bound(undoFn),
		redo = bound(redoFn),
		description = description or "Action",
		contextFrame = undoCF,
		undoContextFrame = undoCF,
		redoContextFrame = (redoCF ~= nil) and redoCF or undoCF,
		afterUndo = type(contextFrame) == "table" and contextFrame.afterUndo or nil,
		afterRedo = type(contextFrame) == "table" and contextFrame.afterRedo or nil,
	}
end

local function commit(entry, external)
	push(undoStack, entry)
	table.clear(redoStack)
	armPending, armForce = true, true
	if not external then
		sessionDirty = true
	end

	changed()
end

local function ownWaypoint(name)
	return type(name) ~= "string"
		or name == ""
		or name:find("Eclipse", 1, true) ~= nil
		or name == "Add Armature"
		or ownLabels[name] == true
end

local function placementRoot(part)
	return part:IsA("BasePart") and (part.Anchored or part.AssemblyRootPart == part)
end

local function forgetRigParts(rig)
	const cached = rigCandidates[rig]
	if cached then
		for _, connection in cached.connections do
			connection:Disconnect()
		end

		rigCandidates[rig] = nil
	end
end

local function rigParts(rig)
	const cached = rigCandidates[rig]
	if cached and not cached.dirty then
		return cached.parts
	end

	forgetRigParts(rig)
	const entry = { parts = {}, dirty = false, connections = {} }
	if rig:IsA("BasePart") then
		table.insert(entry.parts, rig)
	end

	for _, object in rig:GetDescendants() do
		if object:IsA("BasePart") then
			table.insert(entry.parts, object)
		end
	end

	local function invalidate(object)
		if object:IsA("BasePart") or object:IsA("JointInstance") then
			entry.dirty = true
			placementDirty = true
		end
	end

	entry.connections[1] = rig.DescendantAdded:Connect(invalidate)
	entry.connections[2] = rig.DescendantRemoving:Connect(invalidate)
	rigCandidates[rig] = entry
	return entry.parts
end

local function unwatchPart(part)
	const links = watchedParts[part]
	if links then
		links:Disconnect()
		watchedParts[part] = nil
	end

	movedParts[part] = nil
	placement.parts[part] = nil
end

local function watchPart(part)
	if watchedParts[part] then
		return
	end

	watchedParts[part] = part:GetPropertyChangedSignal("CFrame"):Connect(function()
		movedParts[part] = true
	end)
	placement.parts[part] = part.CFrame
end

local function rigSetChanged(rigs)
	if #rigs ~= #knownRigs then
		return true
	end

	for index, rig in rigs do
		if knownRigs[index] ~= rig then
			return true
		end
	end

	return false
end

local function refreshPlacementParts(force)
	placementRefreshAt = os.clock() + PLACEMENT_REFRESH
	local ok, rigs = pcall(function()
		return GraphRootState.getAllRigs and GraphRootState.getAllRigs() or {}
	end)
	if not ok then
		return
	end

	if not force and not placementDirty and os.clock() < placementFullAt and not rigSetChanged(rigs) then
		return
	end

	placementDirty = false
	placementFullAt = os.clock() + PLACEMENT_FULL_REFRESH
	table.clear(knownRigs)
	for index, rig in rigs do
		knownRigs[index] = rig
	end

	table.clear(placementParts)
	table.clear(placementModels)
	const animated = require("RawState").Timeline.MotorByPart or {}
	const CameraRig = require("CameraRig")
	const MasterControl = require("MasterControl")
	const current = {}
	for _, rig in rigs do
		if typeof(rig) ~= "Instance" or not rig.Parent or CameraRig.isRig(rig) then
			continue
		end

		current[rig] = true
		const master = MasterControl.get(rig)
		const driven = master and master.Part1
		if rig:IsA("Model") then
			table.insert(placementModels, rig)
		end

		for _, part in rigParts(rig) do
			if #placementParts >= PLACEMENT_LIMIT then
				break
			end

			if part ~= driven and not animated[part] and placementRoot(part) then
				table.insert(placementParts, part)
			end
		end
	end

	for rig in rigCandidates do
		if not current[rig] then
			forgetRigParts(rig)
		end
	end

	const wanted = {}
	for _, part in placementParts do
		wanted[part] = true
		watchPart(part)
		if force and part.Parent then
			placement.parts[part] = part.CFrame
		end
	end

	for part in watchedParts do
		if not wanted[part] then
			unwatchPart(part)
		end
	end

	table.clear(placement.scales)
	table.clear(placement.pivots)
	for _, model in placementModels do
		if model.Parent then
			placement.scales[model] = model:GetScale()
			placement.pivots[model] = model:GetPivot()
		end
	end

	if force then
		table.clear(movedParts)
	end
end

local function settlePlacement()
	if not next(movedParts) then
		return
	end

	for part in movedParts do
		if part.Parent and watchedParts[part] then
			placement.parts[part] = part.CFrame
		end
	end

	table.clear(movedParts)
	for _, model in placementModels do
		if model.Parent then
			placement.scales[model] = model:GetScale()
			placement.pivots[model] = model:GetPivot()
		end
	end
end

local function captureSelection(target)
	const animated = require("RawState").Timeline.MotorByPart or {}
	local count = 0

	local function add(part)
		if
			count < SELECTION_LIMIT
			and not animated[part]
			and not watchedParts[part]
			and target.parts[part] == nil
		then
			count += 1
			target.parts[part] = part.CFrame
		end
	end

	for _, object in Selection:Get() do
		if object:IsA("BasePart") then
			add(object)
		elseif object:IsA("Model") then
			if target.scales[object] == nil and placement.scales[object] == nil then
				target.scales[object] = object:GetScale()
			end

			if target.pivots[object] == nil then
				target.pivots[object] = object:GetPivot()
			end

			for _, part in object:GetDescendants() do
				if count >= SELECTION_LIMIT then
					break
				end

				if placementRoot(part) then
					add(part)
				end
			end
		end
	end
end

local function writeDefault(raw, motor, value)
	const Properties = require("Properties")
	motor.Part1:SetAttribute("Default", require("Document").pack(value))
	raw.DefaultPose[motor] = Properties.encode(value)
	Properties.setValue(motor, value)
end

local function applyPlacement(state)
	local applied = false
	if state.parents then
		for object, parent in state.parents do
			const target = parent or nil
			if object.Parent ~= target and pcall(function()
				object.Parent = target
			end) then
				applied = true
			end
		end
	end

	for model, scale in state.scales do
		if model.Parent and math.abs(model:GetScale() - scale) > 1e-6 and pcall(model.ScaleTo, model, scale) then
			applied = true
		end
	end

	for model in state.rigid do
		const cf = state.pivots[model]
		if model.Parent and not model:GetPivot():FuzzyEq(cf, 1e-5) and pcall(model.PivotTo, model, cf) then
			applied = true
		end
	end

	for part, cf in state.parts do
		if part.Parent and pcall(function()
			part.CFrame = cf
		end) then
			applied = true
		end
	end

	for model, cf in state.pivots do
		if
			model.Parent
			and not model.PrimaryPart
			and not model.WorldPivot:FuzzyEq(cf, 1e-5)
			and pcall(function()
				model.WorldPivot = cf
			end)
		then
			applied = true
		end
	end

	const timeline = GraphRootState.Timeline
	local posed = nil
	if timeline then
		const raw = timeline:GetState()
		for motor, bucket in state.buckets do
			if motor.Parent and pcall(timeline._restoreMotorBucket, timeline, motor, bucket) then
				posed = posed or motor.Rig
				applied = true
			end
		end

		for motor, value in state.defaults do
			if motor.Parent and pcall(writeDefault, raw, motor, value) then
				posed = posed or motor.Rig
				applied = true
			end
		end
	end

	const poseRig = GraphRootState.currentRig or posed
	if timeline and poseRig then
		pcall(function()
			timeline:ApplyPoseAtTime(poseRig, timeline:GetState().CurrentTime)
		end)
	end

	pcall(function()
		require("motionPath").markDirty()
	end)

	return applied
end

local function movedWithin(model, parts)
	for part in parts do
		if part:IsDescendantOf(model) then
			return true
		end
	end

	return false
end

local function keyPropertyMoves(undoState, redoState)
	const timeline = GraphRootState.Timeline
	if not timeline or not next(undoState.pivots) then
		return nil
	end

	const raw = timeline:GetState()
	if raw.Playing or BlenderEdit.blocked() then
		return nil
	end

	const Properties = require("Properties")
	const frame = timeline:TimeToFrame(raw.CurrentTime)
	const recording = timeline:IsRecording()
	const sanitize = GraphRootState.UIHelpers and GraphRootState.UIHelpers.SanitizeName
	local keyed = false
	for model in undoState.pivots do
		if
			not table.find(knownRigs, model)
			or not movedWithin(model, undoState.parts)
			or Properties.inheritedTransform(model)
		then
			continue
		end

		for _, motor in Properties.list(model, false, true) do
			if motor.PropertyId ~= "CFrame" or motor:GetAttribute("EclipseDisabled") then
				continue
			end

			const value = Properties.readValue(model, "CFrame")
			if recording then
				const before = timeline:_snapshotMotorBucket(motor)
				timeline:RecordKeyframeForMotorAtCurrentTime(
					motor.Part1,
					motor,
					Properties.encode(value),
					{ Frame = frame, PropertyValue = value },
					sanitize
				)
				undoState.buckets[motor], redoState.buckets[motor] = before, timeline:_snapshotMotorBucket(motor)
				keyed = true
			else
				undoState.defaults[motor], redoState.defaults[motor] = motor.DefaultValue, value
				writeDefault(raw, motor, value)
			end

			GraphRootState.currentProjectSaved = false
		end
	end

	return keyed and frame or nil
end

local function adoptStudioEdit(name)
	const undoState = { parts = {}, scales = {}, parents = {}, pivots = {}, rigid = {}, buckets = {}, defaults = {} }
	const redoState = { parts = {}, scales = {}, parents = {}, pivots = {}, rigid = {}, buckets = {}, defaults = {} }
	local edited = false

	local function comparePart(part, cf)
		if cf and part.Parent and undoState.parts[part] == nil then
			const now = part.CFrame
			if not now:FuzzyEq(cf, 1e-5) then
				undoState.parts[part], redoState.parts[part] = cf, now
				edited = true
			end
		end
	end

	local function compareScale(model, scale)
		if model.Parent and undoState.scales[model] == nil then
			const now = model:GetScale()
			if math.abs(now - scale) > 1e-6 then
				undoState.scales[model], redoState.scales[model] = scale, now
				edited = true
			end
		end
	end

	for part in movedParts do
		comparePart(part, placement.parts[part])
	end

	for model, scale in placement.scales do
		compareScale(model, scale)
	end

	if externalBefore then
		for part, cf in externalBefore.parts do
			comparePart(part, cf)
		end

		for model, scale in externalBefore.scales do
			compareScale(model, scale)
		end
	end

	const checked = {}
	local function comparePivot(model, cf)
		if cf and model.Parent and not checked[model] then
			checked[model] = true
			const now = model:GetPivot()
			if not now:FuzzyEq(cf, 1e-5) then
				undoState.pivots[model], redoState.pivots[model] = cf, now
				edited = true
			end

			if placement.pivots[model] ~= nil then
				placement.pivots[model] = now
			end
		end
	end

	if externalBefore then
		for model, cf in externalBefore.pivots do
			comparePivot(model, cf)
		end
	end

	for model, cf in placement.pivots do
		if movedWithin(model, undoState.parts) then
			comparePivot(model, cf)
		end
	end

	for model, before in undoState.pivots do
		const delta = redoState.pivots[model] * before:Inverse()
		local rigid = nil
		for part, cf in undoState.parts do
			if part:IsDescendantOf(model) then
				rigid = (delta * cf):FuzzyEq(redoState.parts[part], 1e-3)
				if not rigid then
					break
				end
			end
		end

		if rigid then
			undoState.rigid[model], redoState.rigid[model] = true, true
		end
	end

	for object, parent in trackedParents do
		if object.Parent == nil and undoState.parents[object] == nil then
			if restorable(object, parent) then
				undoState.parents[object], redoState.parents[object] = parent, false
				edited = true
			else
				untrackObject(object)
			end
		end
	end

	if edited then
		const keyed, keyError = pcall(keyPropertyMoves, undoState, redoState)
		if not keyed then
			warn("Eclipse could not key a Studio move:", keyError)
		end

		local entry
		entry = bindEntry(function()
			entry.inert = not applyPlacement(undoState)
		end, function()
			entry.inert = not applyPlacement(redoState)
		end, "Studio: " .. tostring(externalLabel or name), keyed and keyError or nil)
		entry.external = true
		commit(entry, true)
	end

	return edited
end

local function syncStudio()
	if applyingUndoRedo or recordingOpen() then
		return false
	end

	if studioChanged() then
		local ok, canUndo, name = pcall(ChangeHistoryService.GetCanUndo, ChangeHistoryService)
		local mirrored = ok and canUndo and ownWaypoint(name)
		if ok and canUndo and not mirrored and (externalBefore or placementLive) and isActive() then
			local adopted, result = pcall(adoptStudioEdit, name)
			if not adopted then
				warn("Eclipse could not keep a Studio edit undoable:", result)
			end

			mirrored = adopted and result == true
		end

		if not ((mirrored or isActive()) and pcall(resetStudioWaypoints)) then
			markStudioBase()
		end
	elseif selectionDirty then
		pruneSelection(false)
	end

	externalBefore, externalLabel = nil, nil
	return true
end

local function routeShortcut(direction, source)
	const now = os.clock()
	const last = shortcutRoutes[direction]
	if last.source ~= nil and last.source ~= source and now - last.at < SHORTCUT_ECHO then
		last.source = nil
		return false
	end

	last.source, last.at = source, now
	if direction == "redo" then
		return History.redo()
	end

	return History.undo()
end

local function routeNative(redo, name)
	if name == SENTINEL and not redo and armEchoes > 0 and os.clock() - armEchoAt < NATIVE_ECHO then
		armEchoes -= 1
		return
	end

	nativeChangedAt = os.clock()
	if name == SENTINEL then
		armEchoes = 0
	end

	if not sessionOpen() then
		markStudioBase()
		return
	end

	if name ~= SENTINEL then
		return
	end

	armed = false
	armPending, armForce = true, true
	if not applyingUndoRedo then
		routeShortcut(redo and "redo" or "undo", "native")
	end
end

local function beginExternal(name, displayName)
	const own = ownWaypoint(name)
	if own and type(displayName) == "string" and displayName ~= "" then
		ownLabels[displayName] = true
	end

	const entry = externalRecordings[name]
	if entry then
		entry.count += 1
		entry.at = os.clock()
	else
		externalRecordings[name] = { count = 1, at = os.clock() }
	end

	if own or not isActive() then
		return
	end

	externalLabel = externalLabel or displayName or name
	externalBefore = externalBefore or { parts = {}, scales = {}, pivots = {} }
	pcall(captureSelection, externalBefore)
end

local function finishExternal(name, _displayName, _identifier, operation)
	if not ownWaypoint(name) and operation ~= Enum.FinishRecordingOperation.Cancel then
		studioEdited = true
	end

	const entry = externalRecordings[name]
	if entry then
		entry.count -= 1
		if entry.count <= 0 then
			externalRecordings[name] = nil
		end
	end
end

local function pruneExternal()
	if not next(externalRecordings) then
		return
	end

	const now = os.clock()
	for name, entry in externalRecordings do
		if now - entry.at > RECORDING_TIMEOUT then
			if
				NativeInput:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
				or NativeInput:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			then
				entry.at = now
			else
				externalRecordings[name] = nil
			end
		end
	end
end

function History.revertingNative()
	const now = os.clock()
	return now - nativeChangedAt < REVERT_TIMEOUT or now - armEchoAt < ARM_ECHO
end

function History.shortcut(direction)
	return routeShortcut(direction == "redo" and "redo" or "undo", "key")
end

function History.nativeEcho()
	if not armed and armEchoes == 0 then
		return false
	end

	local echo = armEchoes > 0 and os.clock() - armEchoAt < NATIVE_ECHO
	if not echo and armed then
		const undoName, redoName = studioTop()
		echo = undoName == nil and redoName == SENTINEL or undoName == SENTINEL and redoName == nil
	end

	return echo and sameSelection()
end

function History.protectSavedAnimations()
	syncStudio()
	local ok, err = pcall(resetStudioWaypoints, true)
	if not ok then
		warn("Eclipse could not protect saved animations from Studio undo:", err)
	end

	return ok
end

local function jumpIfNeeded(entry, direction)
	if not entry then
		return
	end

	if not jumpToFrameCallback then
		return
	end

	local target = nil
	if direction == "undo" and entry.undoContextFrame ~= nil then
		target = entry.undoContextFrame
	elseif direction == "redo" and entry.redoContextFrame ~= nil then
		target = entry.redoContextFrame
	else
		target = entry.contextFrame
	end

	if target == nil then
		return
	end

	pcall(jumpToFrameCallback, target)
end

function History.record(undoFn, redoFn, description, contextFrame, redoContextFrame)
	if type(undoFn) ~= "function" or type(redoFn) ~= "function" then
		warn("History.record: undoFn and redoFn must be functions")
		return
	end

	if applyingUndoRedo then
		return
	end

	const entry = bindEntry(undoFn, redoFn, description, contextFrame, redoContextFrame)
	const batch = batches[coroutine.running()]
	if batch then
		table.insert(batch, entry)
		return
	end

	syncStudio()
	commit(entry)
end

function History.batch(description, callback)
	local thread = coroutine.running()
	if batches[thread] then
		return callback()
	end
	local entries = {}
	batches[thread] = entries
	local result = table.pack(xpcall(callback, debug.traceback))
	batches[thread] = nil
	if #entries > 0 then
		syncStudio()
		commit({
			description = description or entries[1].description,
			undoContextFrame = entries[1].undoContextFrame,
			redoContextFrame = entries[#entries].redoContextFrame,
			undo = function()
				local done = #entries + 1
				local ok, err = pcall(function()
					for i = #entries, 1, -1 do
						entries[i].undo()
						if entries[i].afterUndo then entries[i].afterUndo() end
						done = i
					end
				end)
				if not ok then
					for i = done, #entries do
						pcall(entries[i].redo)
					end

					error(err, 0)
				end
			end,
			redo = function()
				local done = 0
				local ok, err = pcall(function()
					for i, entry in entries do
						entry.redo()
						if entry.afterRedo then entry.afterRedo() end
						done = i
					end
				end)
				if not ok then
					for i = done, 1, -1 do
						pcall(entries[i].undo)
					end

					error(err, 0)
				end
			end,
		})
	end
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end

local generation = 0

function History.generation()
	return generation
end

function History.capture(entries, callback)
	const thread = coroutine.running()
	const outer = batches[thread]
	batches[thread] = entries
	const result = table.pack(pcall(callback))
	batches[thread] = outer
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

function History.commitGroup(description, entries)
	if #entries == 0 or applyingUndoRedo then
		return nil
	end

	const outer = batches[coroutine.running()]
	if outer then
		table.move(entries, 1, #entries, #outer + 1, outer)
		return nil
	end

	if #entries == 1 then
		syncStudio()
		commit(entries[1])
		return entries[1]
	end

	History.batch(description, function()
		const target = batches[coroutine.running()]
		table.move(entries, 1, #entries, #target + 1, target)
	end)
	return undoStack[#undoStack]
end

function History.merge(description, entries)
	const count = #entries
	if count < 2 or applyingUndoRedo or #redoStack > 0 or count > #undoStack then
		return false
	end

	const offset = #undoStack - count
	for index, entry in entries do
		if undoStack[offset + index] ~= entry then
			return false
		end
	end

	for index = #undoStack, offset + 1, -1 do
		undoStack[index] = nil
	end

	History.commitGroup(description, entries)
	return true
end

function History.revertGroup(entries)
	const applying = applyingUndoRedo
	applyingUndoRedo = true
	const ok, err = pcall(function()
		for index = #entries, 1, -1 do
			entries[index].undo()
			if entries[index].afterUndo then
				entries[index].afterUndo()
			end
		end
	end)
	applyingUndoRedo = applying
	table.clear(entries)
	if not ok then
		error(err, 0)
	end
end

function History.undo()
	local picker = require("Picker")
	if picker.isOpen() then
		if BlenderEdit.blocked(true) then
			return false
		end

		return picker.undo()
	end

	if GraphRootState.PivotEditor and GraphRootState.PivotEditor.isActive() then
		GraphRootState.PivotEditor.undo()
		return
	end

	if
		GraphRootState.LiveSession
		and GraphRootState.LiveSession.isJoined()
		and GraphRootState.LiveSession.undo
	then
		task.spawn(GraphRootState.LiveSession.undo)
		return
	end

	if BlenderEdit.blocked(true) then
		return
	end

	if applyingUndoRedo or projectBusy() then
		return false, nil
	end

	if GraphRootState.GreasePencil and GraphRootState.GreasePencil.isDrawing() then
		GraphRootState.GreasePencil.cancelStroke()
	end

	if beforeUndoRedo then
		beforeUndoRedo()
	end

	syncStudio()
	local action = table.remove(undoStack)
	if not action then
		if guardCleanupCallback then
			pcall(guardCleanupCallback)
		end

		return false, nil
	end

	const undoTimeline = GraphRootState.Timeline
	if undoTimeline and undoTimeline.GetState then
		undoTimeline:GetState().Playing = false
	end

	applyingUndoRedo = true
	local ok, err = pcall(function()
		action.undo()
		jumpIfNeeded(action, "undo")
		if action.afterUndo then
			action.afterUndo()
		end
	end)
	applyingUndoRedo = false

	if not ok then
		warn("History undo failed:", err)
		if action.external then
			changed()
			return History.undo()
		end

		push(undoStack, action)
		return false, nil
	end

	push(redoStack, action)
	pcall(function()
		require("motionPath").markDirty()
	end)

	GraphRootState.currentProjectSaved = false
	if not action.external then
		sessionDirty = true
	end

	changed()
	if action.external and action.inert then
		return History.undo()
	end

	return true, action.description
end

function History.redo()
	local picker = require("Picker")
	if picker.isOpen() then
		if BlenderEdit.blocked(true) then
			return false
		end

		return picker.redo()
	end

	if GraphRootState.PivotEditor and GraphRootState.PivotEditor.isActive() then
		GraphRootState.PivotEditor.redo()
		return
	end

	if
		GraphRootState.LiveSession
		and GraphRootState.LiveSession.isJoined()
		and GraphRootState.LiveSession.redo
	then
		task.spawn(GraphRootState.LiveSession.redo)
		return
	end

	if BlenderEdit.blocked(true) then
		return
	end

	if applyingUndoRedo or projectBusy() then
		return false, nil
	end

	if GraphRootState.GreasePencil and GraphRootState.GreasePencil.isDrawing() then
		GraphRootState.GreasePencil.cancelStroke()
	end

	if beforeUndoRedo then
		beforeUndoRedo()
	end

	syncStudio()
	local action = table.remove(redoStack)
	if not action then
		return false, nil
	end

	const redoTimeline = GraphRootState.Timeline
	if redoTimeline and redoTimeline.GetState then
		redoTimeline:GetState().Playing = false
	end

	applyingUndoRedo = true
	local ok, err = pcall(function()
		action.redo()
		jumpIfNeeded(action, "redo")
		if action.afterRedo then
			action.afterRedo()
		end
	end)
	applyingUndoRedo = false

	if not ok then
		warn("History redo failed:", err)
		if action.external then
			changed()
			return History.redo()
		end

		push(redoStack, action)
		return false, nil
	end

	push(undoStack, action)
	pcall(function()
		require("motionPath").markDirty()
	end)

	GraphRootState.currentProjectSaved = false
	if not action.external then
		sessionDirty = true
	end

	changed()
	if action.external and action.inert then
		return History.redo()
	end

	return true, action.description
end

function History.clear()
	generation += 1
	table.clear(undoStack)
	table.clear(redoStack)
	externalBefore, externalLabel = nil, nil
	table.clear(movedParts)
	placementRefreshAt = 0
	placementLive = false
	if sessionDirty and not next(externalRecordings) then
		local ok, err = pcall(resetStudioWaypoints, true)
		if not ok then
			warn("Eclipse could not protect saved animations from Studio undo:", err)
		end
	else
		markStudioBase()
	end

	changed()
end

function History.hasAnimationEdits()
	for _, entry in undoStack do
		if entry.description ~= "Add rig" then
			return true
		end
	end

	return false
end

function History.canUndo()
	return #undoStack > 0
end

function History.canRedo()
	return #redoStack > 0
end

function History.getStats()
	return {
		undo = #undoStack,
		redo = #redoStack,
		max = maxSize,
		undoTotal = #undoStack,
		redoTotal = #redoStack,
	}
end

function History.setMaxSize(n)
	maxSize = math.max(1, math.floor(n))
end

function History.setNotifyHandler(fn)
	onNotify = fn
end

function History.setJumpToFrame(fn)
	jumpToFrameCallback = fn
end

function History.setGuardCleanup(fn)
	guardCleanupCallback = fn
end

function History.setBeforeUndoRedo(fn)
	beforeUndoRedo = fn
end

function History.setActiveCheck(fn)
	activeCheckFn = fn
end

function History.setGuardCallbacks(cbs)
	guardCallbacks = cbs or {}
end

function History.setGuardExpiry(_seconds) end

function History.armGuard() end

local function isCtrlHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function isShiftHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

function History.init(_markerInst)
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
	table.clear(externalRecordings)
	for _, pair in { { "OnRecordingStarted", beginExternal }, { "OnRecordingFinished", finishExternal } } do
		local ok, signal = pcall(function()
			return ChangeHistoryService[pair[1]]
		end)
		if ok and signal then
			table.insert(connections, signal:Connect(pair[2]))
		end
	end

	for _, pair in { { "OnUndo", false }, { "OnRedo", true } } do
		local ok, signal = pcall(function()
			return ChangeHistoryService[pair[1]]
		end)
		if ok and signal then
			table.insert(connections, signal:Connect(function(name)
				routeNative(pair[2], name)
			end))
		end
	end

	table.insert(connections, Selection.SelectionChanged:Connect(trackSelection))
	sessionWasOpen = false
	armed, armPending, armForce, armEchoes = false, false, false, 0
	markStudioBase()

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			if UserInputService:GetFocusedTextBox() then
				return
			end

			if not isActive() then
				return
			end

			local direction
			if
				Shortcuts.matches("Redo", input)
				or Shortcuts.matches("RedoAlternate", input)
				or Shortcuts.matches("RedoShift", input)
			then
				direction = "redo"
			elseif
				Shortcuts.matches("Undo", input) or Shortcuts.matches("UndoAlternate", input)
			then
				direction = "undo"
			end

			if direction and not shortcutHeld[input.KeyCode] then
				shortcutHeld[input.KeyCode] = true
				routeShortcut(direction, "key")
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			shortcutHeld[input.KeyCode] = nil
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			table.clear(shortcutHeld)
		end)
	)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			for key in shortcutHeld do
				if not UserInputService:IsKeyDown(key) then
					shortcutHeld[key] = nil
				end
			end

			pruneExternal()
			const open = sessionOpen()
			if open ~= sessionWasOpen then
				sessionWasOpen = open
				if open then
					armPending, armForce = true, true
					if not (not applyingUndoRedo and not recordingOpen() and pcall(resetStudioWaypoints)) then
						markStudioBase()
					end
				else
					pcall(disarmStudio)
					markStudioBase()
				end
			end

			if not open and sessionDirty and not applyingUndoRedo and not next(externalRecordings) then
				pcall(resetStudioWaypoints, true)
			end

			if not isActive() then
				placementLive = false
				externalBefore, externalLabel = nil, nil
				if open then
					maintainArm(false)
				end

				return
			end

			if not placementLive then
				if next(externalRecordings) then
					return
				end

				pcall(refreshPlacementParts, true)
				markStudioBase()
			end

			if syncStudio() then
				if os.clock() >= placementRefreshAt then
					pcall(refreshPlacementParts)
				end

				settlePlacement()
				placementLive = true
			end

			maintainArm(true)
		end)
	)
end

function History.disconnect()
	if not next(externalRecordings) then
		pcall(disarmStudio)
		if sessionDirty then
			sessionDirty = false
			pcall(clearStudioStack)
		end
	end

	armed = false

	table.clear(shortcutHeld)
	table.clear(externalRecordings)
	placementLive = false
	for rig in rigCandidates do
		forgetRigParts(rig)
	end

	for part in watchedParts do
		unwatchPart(part)
	end

	table.clear(knownRigs)
	for object in trackedLinks do
		untrackObject(object)
	end

	placementDirty = true
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
end

return History
