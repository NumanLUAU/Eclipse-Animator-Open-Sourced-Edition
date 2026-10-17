--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Tracks = require("Properties")
local Layers = require("Layers")
local History = require("History")
local API = {}
local refs, endpoint, registry
local connections = {}
local busy = false
const VERSION = 2
const ACTIONS = { "Add", "AddObject", "ListTracks", "ListProperties", "Select", "SetKeyframe", "SetEasing", "GetCurrentFrame", "GetCurrentTime", "GetFPS", "Batch", "BeginBatch", "EndBatch", "HistoryRecord", "RevertChanges" }
const EDITS = { Add = true, AddObject = true, SetKeyframe = true, SetEasing = true, Batch = true }
const CHANGE_LIMIT = 256
const pending = {}
const pendingOrder = {}
local batch = nil

local function owner(motor)
    return Tracks.is(motor) and motor.Rig or Layers.owner(motor)
end

local function identity(motor)
    return Tracks.is(motor) and motor.Rig or typeof(motor) == "Instance" and motor or motor.Part1
end

local function target(value)
    assert(typeof(value) == "Instance" and value ~= workspace and value:IsDescendantOf(workspace), "Target must be an instance in Workspace")
    return value
end

local function rows(request)
    local found, seen = {}, {}
    for _, item in refs.State.Rig._orderedItems or {} do
        local motor = item:fetchMotor()
        if motor and motor.Parent and not seen[motor] then
            local property = Tracks.is(motor) and motor.PropertyId or nil
            local match = not request.Target or identity(motor) == request.Target or motor.Part1 == request.Target
                or item.linkedRigInstance == request.Target or not request.Property and owner(motor) == request.Target
            if match and (not request.Property or property == request.Property) then
                seen[motor] = true
                table.insert(found, { item = item, motor = motor, property = property })
            end
        end
    end
    return found
end

local function easing(value)
    assert(typeof(value) == "table", "Easing must contain Style and optional Direction")
    local style = typeof(value.Style) == "EnumItem" and value.Style.Name or value.Style
    style = ({ Exponential = "Expo", Circular = "Circ", Sinusoidal = "Sine", Quadratic = "Quad", Quartic = "Quart", Quintic = "Quint" })[style] or style
    local direction = typeof(value.Direction) == "EnumItem" and value.Direction.Name or value.Direction or "InOut"
    local found = style == "Bezier"
    for _, entry in require("EasingStyles") do if entry.Name == style then found = true end end
    assert(found, "Unsupported easing style")
    assert(direction == "In" or direction == "Out" or direction == "InOut", "Unsupported easing direction")
    return { EasingStyle = style, EasingDirection = direction }
end

local function refresh()
    local state = refs.State
    for _, rig in state.getAllRigs() do
        state.Timeline:ApplyPoseAtTime(rig, state.Timeline:GetState().CurrentTime, { OnlyRig = true })
    end
    state.Timeline:RefreshAllKeyframeVisuals()
    state.currentProjectSaved = false
end

local function edit(request, onlyEasing)
    target(request.Target)
    local found = rows(request)
    assert(#found == 1, "Choose one track from ListTracks; specify Property for property tracks")
    local motor = found[1].motor
    local timeline = refs.State.Timeline
    local raw = timeline:GetState()
    local frame = request.Frame
    assert(typeof(frame) == "number" and frame == frame and frame >= 0 and frame <= 1000000 and frame % 1 == 0, "Frame must be an integer from 0 to 1000000")
    assert(not motor:GetAttribute("EclipseDisabled"), "Track is disabled")
    local layer = Layers.active(raw, motor)
    assert(not layer.locked, "Active layer is locked")
    local curve = request.Easing and easing(request.Easing)
    assert(not onlyEasing or curve, "Easing is required")
    local value, cf = request.Value
    if not onlyEasing then
        if value == nil then value = Tracks.is(motor) and Tracks.readValue(motor.Rig, motor.PropertyId) or motor.C0 end
        if Tracks.is(motor) then
            assert(Tracks.validate(motor, value), "Invalid value for this property")
            cf = Tracks.encode(value)
        else
            assert(typeof(value) == "CFrame", "Transform track Value must be a local CFrame")
            for _, component in { value:GetComponents() } do
                assert(component == component and math.abs(component) < math.huge, "CFrame must contain finite numbers")
            end
            cf = value
        end
    end
    local bucket = timeline:GetMotorKeyframeBucket(motor)
    assert(not onlyEasing or bucket and bucket[frame], "No keyframe at the requested frame")
    refs.Finalize()
    local before = timeline:_snapshotMotorBucket(motor)
    local function restore(snapshot)
        Layers.history(layer.id, function()
            timeline:_restoreMotorBucket(motor, snapshot)
            refresh()
        end)
    end
    local ok, issue = xpcall(function()
        if not onlyEasing then
            timeline:RecordKeyframeForMotorAtCurrentTime(motor.Part1, motor, cf, { Frame = frame, PropertyValue = Tracks.is(motor) and value or nil }, refs.State.UIHelpers.SanitizeName)
        end
        bucket = timeline:GetMotorKeyframeBucket(motor)
        local key = bucket and bucket[frame]
        assert(key, "Keyframe could not be created")
        if curve then
            require("ChannelEasing").editAll(key, function(draft)
                draft.EasingStyle, draft.EasingDirection = curve.EasingStyle, curve.EasingDirection
                draft.MoonEasing = nil
            end, bucket)
            require("GraphCurves").invalidate(bucket)
        end
        refresh()
    end, debug.traceback)
    if not ok then restore(before) error(issue, 0) end
    local after = timeline:_snapshotMotorBucket(motor)
    History.record(function() restore(before) end, function() restore(after) end, onlyEasing and "API easing" or "API keyframe", frame)
    return { Target = identity(motor), Property = found[1].property, Frame = frame }
end

local function clean(message)
    return (tostring(message):gsub("^.-:%d+: ", ""))
end

local function label(value, fallback)
    if value == nil then return fallback end
    assert(typeof(value) == "string" and #value > 0 and #value <= 100, "Name must be a string of 1 to 100 characters")
    return value
end

local function placed(object)
    return require("rig").localOf(object)
end

local function onTimeline(object)
    return table.find(refs.State.getAllRigs(), object) ~= nil
end

local function captured(fn)
    const entries = {}
    const ok, result = pcall(History.capture, entries, fn)
    if not ok then
        const reverted, issue = pcall(History.revertGroup, entries)
        if not reverted then warn("Eclipse API could not roll back a failed request:", issue) end
        error(result, 0)
    end
    return entries, result
end

local function commit(name, entries)
    const entry = History.commitGroup(name, entries)
    if batch and entry then table.insert(batch.entries, entry) end
end

local function remember(entries)
    if #entries == 0 then return nil end
    const id = game:GetService("HttpService"):GenerateGUID(false)
    pending[id] = { entries = entries, generation = History.generation() }
    table.insert(pendingOrder, id)
    while #pendingOrder > CHANGE_LIMIT do
        pending[table.remove(pendingOrder, 1)] = nil
    end
    return id
end

local function take(request)
    const ids = request.Changes or { request.Change }
    assert(typeof(ids) == "table" and #ids > 0, "Changes must list Change ids returned by edits made with Record = false")
    const found, seen = {}, {}
    for _, id in ids do
        const change = pending[id]
        assert(change and not seen[id], "Unknown or already used Change id: " .. tostring(id))
        assert(change.generation == History.generation(), "Change " .. tostring(id) .. " belongs to a project that is no longer open")
        seen[id] = true
        table.insert(found, change)
    end
    for id in seen do
        pending[id] = nil
        table.remove(pendingOrder, table.find(pendingOrder, id))
    end
    return found
end

local function property(object, name)
    assert(typeof(name) == "string" and name ~= "", "Property names must be non-empty strings")
    if Tracks.definition(object, name) then return name end
    local hint = ""
    for _, def in Tracks.catalog(object) do
        if def.id:lower() == name:lower() then hint = " Did you mean \"" .. def.id .. "\"?" break end
    end
    error(object.ClassName .. " does not support a \"" .. name .. "\" property track." .. hint .. " Use ListProperties to see supported properties.", 0)
end

local function addObject(request)
    const object = target(request.Target)
    const names = request.Properties or {}
    assert(typeof(names) == "table" and #names <= 200, "Properties must be a list of property names")
    assert(object:IsA("Model") or object:IsA("BasePart") or #Tracks.catalog(object) > 0, "Unsupported timeline object")
    const wanted, list = {}, {}
    for _, name in names do
        if not wanted[property(object, name)] then
            wanted[name] = true
            table.insert(list, name)
        end
    end
    const fresh = Tracks.propertyOnly(object) and #Tracks.list(placed(object), true, true) == 0
    const entries, result = captured(function()
        local rig = placed(object)
        local added = false
        if not onTimeline(rig) then
            assert(refs.AddRig(object), "Object could not be added to the timeline")
            rig = placed(object)
            assert(onTimeline(rig), "Object could not be added to the timeline")
            added = true
        end
        const Settings = require("PropertySettings")
        for _, name in list do
            if not Tracks.enabled(rig, name) then Settings.setEnabled(rig, name, true) end
        end
        const first = added and fresh and #list > 0 and Tracks.catalog(rig)[1]
        if first and not wanted[first.id] and Tracks.enabled(rig, first.id) then
            Settings.setEnabled(rig, first.id, false)
        end
        return { Target = rig, Added = added, Properties = list }
    end)
    History.commitGroup("API add object", entries)
    return result
end

local function perform(action, request)
    if action == "Add" then
        local object = target(request.Target)
        assert(object:IsA("Model") or object:IsA("BasePart") or #Tracks.catalog(object) > 0, "Unsupported timeline object")
        for _, rig in refs.State.getAllRigs() do
            if rig == object then return { Target = object } end
        end
        assert(refs.AddRig(object), "Object could not be added to the timeline")
        return { Target = object }
    elseif action == "AddObject" then
        return addObject(request)
    elseif action == "ListTracks" then
        if request.Target then target(request.Target) end
        local result = {}
        for _, row in rows(request) do
            table.insert(result, { Target = identity(row.motor), Property = row.property, Name = row.item.centerDiv.Title.Text, Rig = owner(row.motor) })
        end
        return result
    elseif action == "ListProperties" then
        const rig = placed(target(request.Target))
        const enabled = {}
        if onTimeline(rig) then
            for _, motor in Tracks.list(rig) do enabled[motor.PropertyId] = true end
        end
        const result = {}
        for _, def in Tracks.catalog(rig) do
            table.insert(result, { Property = def.id, Label = def.label, Kind = def.kind, Enabled = enabled[def.id] == true })
        end
        return result
    elseif action == "Select" then
        target(request.Target)
        local found = rows(request)
        assert(#found > 0, "Target has no timeline tracks")
        local selected = {}
        for _, row in found do table.insert(selected, row.item) end
        require("ViewportSelection").apply(selected, "replace")
        return { Count = #selected }
    elseif action == "SetKeyframe" then
        return edit(request, false)
    elseif action == "SetEasing" then
        return edit(request, true)
    elseif action == "Batch" then
        const name = label(request.Name, "API batch")
        const steps = request.Actions
        assert(typeof(steps) == "table" and #steps > 0 and #steps <= 1000, "Actions must be a list of 1 to 1000 { Action = string, Request = table } steps")
        const entries, results = captured(function()
            const out = {}
            for index, step in steps do
                assert(typeof(step) == "table" and EDITS[step.Action] and step.Action ~= "Batch", "Batch step " .. tostring(index) .. " must be Add, AddObject, SetKeyframe or SetEasing")
                assert(step.Request == nil or typeof(step.Request) == "table", "Batch step " .. tostring(index) .. " Request must be a table")
                const ok, value = pcall(perform, step.Action, step.Request or {})
                if not ok then error("Batch step " .. tostring(index) .. " (" .. step.Action .. ") failed: " .. clean(value), 0) end
                out[index] = value
            end
            return out
        end)
        History.commitGroup(name, entries)
        return { Name = name, Results = results }
    end
    error("Unknown API action: " .. tostring(action), 0)
end

local function dispatch(action, request)
    assert(refs, "Eclipse API is closed")
    if action == "GetInfo" then
        return { Version = VERSION, Build = "v1.0961", Active = refs.Active(), Actions = table.clone(ACTIONS), Batching = batch ~= nil }
    end
    assert(typeof(request) == "table", "Request must be a table")
    if action == "EndBatch" then
        assert(batch, "No batch is open; call BeginBatch first")
        const open = batch
        batch = nil
        const merged = open.generation == History.generation() and History.merge(open.name, open.entries)
        return { Name = open.name, Edits = #open.entries, UndoSteps = merged and 1 or #open.entries }
    end
    assert(refs.Active() and refs.State.Rig and refs.State.Timeline, "Open an animation in Eclipse first")
    if action == "GetCurrentFrame" or action == "GetCurrentTime" or action == "GetFPS" then
        const timeline = refs.State.Timeline
        const raw = timeline:GetState()
        return { Frame = timeline:TimeToFrame(raw.CurrentTime), Time = raw.CurrentTime, FPS = raw.FPS }
    end
    assert(not require("BlenderEdit").blocked() and not refs.State.Timeline:IsExportLocked(), "Eclipse is busy")
    assert(not refs.State.Timeline:GetState().Playing, "Pause playback before editing")
    if action == "BeginBatch" then
        assert(not batch or batch.generation ~= History.generation(), "A batch is already open; call EndBatch first")
        batch = { name = label(request.Name, "API batch"), entries = {}, generation = History.generation() }
        return { Name = batch.name }
    elseif action == "HistoryRecord" then
        const name = label(request.Name, "API edit")
        const changes = take(request)
        const entries = {}
        for _, change in changes do table.move(change.entries, 1, #change.entries, #entries + 1, entries) end
        commit(name, entries)
        return { Name = name, Count = #changes }
    elseif action == "RevertChanges" then
        const changes = take(request)
        for index = #changes, 1, -1 do History.revertGroup(changes[index].entries) end
        return { Count = #changes }
    end
    if EDITS[action] then
        assert(request.Record == nil or typeof(request.Record) == "boolean", "Record must be true or false")
        if request.Record == false or batch then
            const entries, result = captured(function() return perform(action, request) end)
            if request.Record == false then
                result.Change = remember(entries)
            else
                commit(typeof(request.Name) == "string" and request.Name or "API " .. action, entries)
            end
            return result
        end
    end
    return perform(action, request)
end

function API.invoke(action, request)
    if busy then return { ok = false, error = "An Eclipse API request is already running" } end
    busy = true
    local ok, result = pcall(dispatch, action, request or {})
    busy = false
    return ok and { ok = true, result = result } or { ok = false, error = tostring(result):gsub("^.-:%d+: ", "") }
end

function API.destroy()
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
    if endpoint then endpoint:Destroy() endpoint = nil end
    batch = nil
    table.clear(pending)
    table.clear(pendingOrder)
    if registry and registry.Parent and #registry:GetChildren() == 0 then registry:Destroy() end
    registry, refs = nil, nil
end

function API.init(options)
    API.destroy()
    refs = options
    local core = game:GetService("CoreGui")
    registry = core:FindFirstChild("EclipseAnimatorAPI")
    if not registry then registry = Instance.new("Folder") registry.Name = "EclipseAnimatorAPI" registry.Parent = core end
    endpoint = Instance.new("BindableFunction")
    endpoint.Name = "Session-" .. tostring(options.ScreenGui:GetAttribute("EclipseInstance") or game:GetService("HttpService"):GenerateGUID(false))
    endpoint:SetAttribute("APIVersion", VERSION)
    endpoint.OnInvoke = API.invoke
    endpoint.Parent = registry
    table.insert(connections, options.ScreenGui.Destroying:Connect(API.destroy))
    table.insert(connections, options.Plugin.Unloading:Connect(API.destroy))
end

return API
