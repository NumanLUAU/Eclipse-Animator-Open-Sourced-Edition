--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("ProjectData")
local UI = require("UI")
local Tool = require("Tool")
local Notification = require("Notification")
local Provider = game:GetService("KeyframeSequenceProvider")
local Marketplace = game:GetService("MarketplaceService")
local Selection = game:GetService("Selection")
local Import = {}
local busy = false
local prompt

function Import.assetId(value)
	local text = tostring(value or ""):match("^%s*(.-)%s*$")
	local id = tonumber(text)
		or tonumber(text:match("rbxassetid://(%d+)"))
		or tonumber(text:match("/catalog/(%d+)"))
		or tonumber(text:match("/library/(%d+)"))
		or tonumber(text:match("/store/asset/(%d+)"))
		or tonumber(text:match("/animations/(%d+)"))
		or tonumber(text:match("[?&]id=(%d+)"))
	assert(id and id > 0 and id % 1 == 0 and id < 2 ^ 53, "Enter a valid Roblox asset ID or link.")
	return id
end

function Import.sortSequences(animations)
	local insertion = {}
	for i, animation in animations do
		insertion[animation] = i
	end

	local function modified(animation)
		local value = animation:GetAttribute("EclipseAnimationModified")
		return typeof(value) == "number" and value == value and value < math.huge and value or 0
	end

	table.sort(animations, function(a, b)
		local am, bm = modified(a), modified(b)
		return am > bm or am == bm and insertion[a] > insertion[b]
	end)
	return animations
end

function Import.selectedSequences(selected)
	local result, seen, visited = {}, {}, {}
	local slice = os.clock()

	local function visit(object)
		if visited[object] then
			return
		end

		visited[object] = true
		if os.clock() - slice >= 0.012 then
			task.wait()
			slice = os.clock()
		end

		if object:IsA("KeyframeSequence") then
			if not seen[object] then
				seen[object] = true
				table.insert(result, object)
			end

			return
		end

		for _, child in object:GetChildren() do
			visit(child)
		end

		if object:IsA("ObjectValue") and object.Name == "AnimSaves" and object.Value then
			visit(object.Value)
		end
	end

	for _, object in selected or Selection:Get() do
		visit(object)
	end

	Import.sortSequences(result)
	return result
end

function Import.load(id, emote)
	id = Import.assetId(id)
	local sequence
	local ok, err = pcall(function()
		local fetched, result =
			pcall(Provider.GetKeyframeSequenceAsync, Provider, "rbxassetid://" .. id)
		assert(
			fetched,
			"Could not read this animation ID. Use the underlying animation ID or insert the animation in Studio and import the selected KeyframeSequence. "
				.. tostring(result)
		)
		sequence = result

		assert(
			sequence and sequence:IsA("KeyframeSequence"),
			"Roblox did not return an editable keyframe sequence."
		)
		assert(#sequence:GetKeyframes() > 0, "This animation has no keyframes.")
		local found, info = pcall(Marketplace.GetProductInfoAsync, Marketplace, id)
		sequence.Name = found and info.Name or "Imported Animation " .. id
	end)

	if not ok then
		if sequence then
			sequence:Destroy()
		end

		error(err, 0)
	end

	return sequence
end

function Import.store(rig, sequence)
	assert(rig and rig.Parent, "The selected rig was removed while importing.")
	assert(sequence and sequence:IsA("KeyframeSequence"), "No keyframe sequence was returned.")
	local saves = Data.ensureAnimSaves(rig)
	local target = saves:IsA("ObjectValue") and saves.Value or saves
	assert(target, "This rig's animation folder is unavailable.")
	sequence.Name = Data.getUniqueExportName(saves, sequence.Name)

	sequence:SetAttribute("EclipseAnimationModified", DateTime.now().UnixTimestampMillis)
	sequence.Parent = target
	return sequence
end

function Import.run(rig, kind, id, done)
	if busy then
		return
	end

	if not rig or not rig.Parent then
		Notification.show("Import animation", "Select a rig first.")
		return
	end

	busy = true
	task.spawn(function()
		local sequence
		local ok, err = pcall(function()
			local plugin = assert(Data.getPlugin(), "Eclipse is not ready.")
			if kind == "Roblox" then
				local asset = plugin:PromptForExistingAssetIdAsync("Animation")
				if not asset or asset <= 0 then
					return
				end

				sequence = Import.load(asset, false)
			elseif kind == "FBX" then
				local humanoid = rig:FindFirstChildOfClass("Humanoid")
				sequence = plugin:ImportFbxAnimationAsync(
					rig,
					humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
				)
				if not sequence then
					return
				end
			else
				sequence = Import.load(id, true)
			end

			Import.store(rig, sequence)
		end)
		busy = false
		if not ok then
			if sequence then
				sequence:Destroy()
			end

			Notification.show("Couldn't import animation", (tostring(err):gsub("^.-:%d+: ", "")))
		elseif sequence then
			Notification.show(
				"Animation imported",
				sequence.Name .. " is in this rig's animation list."
			)
			if done then
				done(sequence)
			end
		end
	end)
end

function Import.open(rig, kind, done)
	if kind ~= "Avatar Shop" then
		Import.run(rig, kind, nil, done)
		return
	end

	if not rig then
		Notification.show("Import animation", "Select a rig first.")
		return
	end

	if prompt then
		prompt:close(true)
	end

	local window = Tool.new(
		{ ScreenGui = UI.EclipseGUI, Plugin = Data.getPlugin() },
		"EclipseEmoteImport",
		"AVATAR SHOP",
		Vector2.new(360, 134),
		false,

		function()
			prompt = nil
		end
	)
	prompt = window
	Tool.label(
		window.frame,
		"Label",
		"Emote ID or Avatar Shop link",
		UDim2.fromOffset(12, 38),
		UDim2.fromOffset(336, 18)
	)
	local field =
		Tool.field(window.frame, "Emote", "", UDim2.fromOffset(12, 60), UDim2.fromOffset(336, 26))

	local function submit()
		local ok, id = pcall(Import.assetId, field.Text)
		if not ok then
			field.PlaceholderText = "Enter an emote ID or link"
			field.Text = ""
			return
		end

		window:close()
		Import.run(rig, kind, id, done)
	end

	Tool.button(
		window.frame,
		"Import",
		"IMPORT",
		UDim2.fromOffset(236, 98),
		UDim2.fromOffset(112, 26),
		submit
	)
	field.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
end

function Import.isR15(rig)
    if not rig or not rig:IsA("Model") then return false end
    local human = rig:FindFirstChildOfClass("Humanoid")
    return rig:FindFirstChild("UpperTorso") ~= nil and rig:FindFirstChild("LowerTorso") ~= nil
        and (not human or human.RigType == Enum.HumanoidRigType.R15)
end

function Import.r15Rigs(state)
    local result = {}
    for _, rig in state.getAllRigs() do
        if Import.isR15(rig) then table.insert(result, rig) end
    end
    return result
end

function Import.nativeR15(sequence)
    local lower, upper = false, false
    for _, pose in sequence:GetDescendants() do
        if pose:IsA("Pose") then
            lower = lower or pose.Name == "LowerTorso"
            upper = upper or pose.Name == "UpperTorso"
        end
    end
    if not lower or not upper then return nil end
    local copy = Instance.new("KeyframeSequence")
    copy.Name, copy.Loop, copy.Priority = sequence.Name, sequence.Loop, sequence.Priority
    for _, key in sequence:GetKeyframes() do
        local cloned = key:Clone()
        for _, object in cloned:GetDescendants() do
            if object:IsA("Pose") and object:GetAttribute("EclipseR6Control") then
                object:Destroy()
            else
                for name in object:GetAttributes() do object:SetAttribute(name, nil) end
            end
        end
        cloned.Parent = copy
    end
    return copy
end

function Import.convertR15Sequence(sequence, sourceRig, targetRig, defaults, rootMotion)
    assert(Import.isR15(sourceRig), "Choose an R15 rig.")
    const R15Retarget = require("R15Retarget")
    const joints = R15Retarget.sourceJoints(require("Parenting").collectMotors(sourceRig), defaults)
    return R15Retarget.convert(sequence, joints, targetRig, {
        rootPart = sourceRig:FindFirstChild("HumanoidRootPart"),
        rootMotion = rootMotion,
        sourceScale = require("PoseSpace").getRigScale(sourceRig),
    })
end

local function rigMotion(rig, timeline)
    const Properties = require("Properties")
    if not rig:IsA("Model") or Properties.inheritedTransform(rig) then return nil end
    const raw = timeline:GetState()
    local track
    for _, motor in Properties.list(rig, false, true) do
        if motor.PropertyId == "CFrame" and not motor:GetAttribute("EclipseDisabled") and next(raw.Keyframes[motor] or {}) then track = motor end
    end
    if not track then return nil end
    const Target = require("Target")
    local function pivotAt(time)
        const bucket = raw.Keyframes[track]
        const value = Target.hasChild(bucket) and Target.childWorld(time, bucket, function(key)
            return Properties.decode(track, key.C0, key.PropertyValue)
        end) or Properties.evaluate(track, bucket, time)
        return typeof(value) == "CFrame" and value or nil
    end
    const root = rig:FindFirstChild("HumanoidRootPart")
    const offset = root and rig:GetPivot():ToObjectSpace(root.CFrame) or CFrame.identity
    const start = pivotAt(timeline:GetPoseTime(0))
    if not start then return nil end
    return function(time)
        const value = pivotAt(timeline:GetPoseTime(time))
        return value and offset:Inverse() * start:ToObjectSpace(value) * offset or CFrame.identity
    end, start * offset
end

function Import.convertR15(rig)
    local State = require("State")
    assert(table.find(Import.r15Rigs(State), rig), "Choose an R15 rig in this file.")
    assert(not require("BlenderEdit").blocked(), "Finish the current edit before converting.")
    assert(not State.LiveSession or not State.LiveSession.isJoined(), "Leave Live before converting a rig.")
    local timeline, project = State.Timeline, State.currentRig
    local copy, baked, converted
    local ok, issue = xpcall(function()
        local description = Instance.new("HumanoidDescription")
        local human = rig:FindFirstChildOfClass("Humanoid")
        if human then
            local success, applied = pcall(human.GetAppliedDescription, human)
            if success then description:Destroy() description = applied end
        end
        local created, model = pcall(game:GetService("Players").CreateHumanoidModelFromDescriptionAsync, game:GetService("Players"), description, Enum.HumanoidRigType.R6)
        description:Destroy()
        assert(created, "Roblox could not create the R6 copy: " .. tostring(model))
        copy = model
        assert(State.currentRig == project and State.Timeline == timeline and table.find(State.getAllRigs(), rig), "The open project changed; retry conversion.")
        local baseName, suffix = rig.Name .. " R6", 1
        copy.Name = baseName
        while workspace:FindFirstChild(copy.Name) do suffix += 1 copy.Name = baseName .. " (" .. suffix .. ")" end
        for _, object in copy:GetDescendants() do
            if object:IsA("BaseScript") then object:Destroy()
            elseif object:IsA("BasePart") then object.Anchored = true end
        end
        baked = require("Export").bakeAnimation(rig, false)
        const moved, motion, start = pcall(rigMotion, rig, timeline)
        local placement
        converted, placement = Import.convertR15Sequence(baked, rig, copy, timeline:GetState().DefaultPose, moved and motion or nil)
        const sourceRoot, targetRoot = rig:FindFirstChild("HumanoidRootPart"), copy:FindFirstChild("HumanoidRootPart")
        if sourceRoot and targetRoot then
            const base = (moved and start or sourceRoot.CFrame) * CFrame.new(5, placement.ground15 - placement.ground6, 0)
            copy:PivotTo(base * targetRoot.CFrame:ToObjectSpace(copy:GetPivot()))
        else
            copy:PivotTo(rig:GetPivot() * CFrame.new(5, 0, 0))
        end
        copy.Parent = workspace
        Import.store(copy, converted)
        copy:SetAttribute("EclipseConvertedFrom", rig.Name)

    end, debug.traceback)
    if baked then baked:Destroy() end
    if not ok then
        if copy then copy:Destroy() end
        error(issue, 0)
    end
    return copy
end

function Import.selectedR15(state, selection, includeTimeline)
    local rigs = Import.r15Rigs(state)
    if #rigs == 1 then return rigs[1] end
    local found = {}
    local function add(object)
        if typeof(object) ~= "Instance" then return end
        for _, rig in rigs do
            if object == rig or object:IsDescendantOf(rig) then found[rig] = true end
        end
        while object do
            local source = object:FindFirstChild("EclipseSourceRig")
            if source and source:IsA("ObjectValue") and table.find(rigs, source.Value) then found[source.Value] = true end
            object = object.Parent
        end
    end
    for _, object in selection do add(object) end
    if #selection == 0 and includeTimeline then
        for item in state.Rig and state.Rig._selectedItems or {} do
            add(item.linkedRigInstance)
            add(item.grandpa and item.grandpa.linkedRigInstance)
        end
        if not next(found) and state.Axis then add(state.Axis:GetSelectedBone()) end
    end
    local rig
    for candidate in found do
        if rig then return nil end
        rig = candidate
    end
    return rig
end

function Import.openR15Converter()
    if busy then return end
    local State = require("State")
    local rig = Import.selectedR15(State, Selection:Get(), true)
    if not rig then
        Notification.show("SELECT AN R15 RIG", "Select one R15 rig in this file before choosing R15 to R6.")
        return
    end
    busy = true
    task.spawn(function()
        local ok, result = pcall(Import.convertR15, rig)
        busy = false
        Notification.show(ok and "R6 COPY CREATED" or "CONVERSION NEEDS ATTENTION", ok and "The animation is saved in the R6 copy's AnimSaves. Exit the R15 file, then select the R6 copy to preview it. R6 has no elbows or knees." or tostring(result))
    end)
end

return Import
