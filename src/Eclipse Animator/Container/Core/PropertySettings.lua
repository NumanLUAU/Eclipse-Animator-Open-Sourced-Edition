--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Events = require("Events")
local Faces = require("Faces")
local Playback = require("EventPlayback")

local CameraRig = require("CameraRig")
local Tracks = require("Properties")
local PartRig = require("PartRig")
local Tool = require("Tool")
local History = require("History")
local Theme = require("Theme")
local Notification = require("Notification")
local Edit = require("BlenderEdit")
local Settings = {}
local refs, window, owner
local unsubscribe

function Settings.close()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end

	owner = nil
	if window then
		local old = window
		window = nil
		old:close()
	end
end

function Settings.recordSelected()
	if not refs or not refs.Active() or Edit.blocked() then
		return 0
	end

	local motors = {}
	for item in refs.State.Rig._selectedItems do
		local motor = item:fetchMotor()
		if Tracks.is(motor) then
			table.insert(motors, motor)
		end
	end

	if #motors == 0 then
		return 0
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local before, after = {}, {}
	for _, motor in motors do
		before[motor] = timeline:_snapshotMotorBucket(motor)
		local value = Tracks.readValue(motor.Rig, motor.PropertyId)
		timeline:RecordKeyframeForMotorAtCurrentTime(
			motor.Part1,
			motor,
			Tracks.encode(value),
			{ PropertyValue = value },
			refs.State.UIHelpers.SanitizeName
		)
		after[motor] = timeline:_snapshotMotorBucket(motor)
	end

	local function apply(data)
		for motor, bucket in data do
			timeline:_restoreMotorBucket(motor, bucket)
		end

		for _, rig in refs.State.getAllRigs() do
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
		end

		refs.State.currentProjectSaved = false
	end

	refs.State.currentProjectSaved = false
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Record properties")
	return #motors
end

local function addKey(motor, firstFree)
	if
		not refs
		or not refs.Active()
		or Edit.blocked()
		or not Tracks.is(motor)
		or not motor.Parent
		or not Tracks.enabled(motor.Rig, motor.PropertyId)
	then
		return
	end

	refs.Finalize()
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local frame = math.max(0, timeline:TimeToFrame(raw.CurrentTime))
	local bucket = raw.Keyframes[motor] or {}
	while firstFree and bucket[frame] do
		frame += 1
	end

	local value = Tracks.readValue(motor.Rig, motor.PropertyId)
	local before = timeline:_snapshotMotorBucket(motor)
	timeline:EnsureTimelineEnd(frame)
	timeline:RecordKeyframeForMotorAtCurrentTime(
		motor.Part1,
		motor,
		Tracks.encode(value),
		{ Frame = frame, PropertyValue = value },
		refs.State.UIHelpers.SanitizeName
	)
	local after = timeline:_snapshotMotorBucket(motor)

	local function apply(data)
		if not motor.Parent then
			return
		end

		timeline:_restoreMotorBucket(motor, data)
		timeline:ApplyPoseAtTime(motor.Rig, raw.CurrentTime, { OnlyRig = true })
		refs.State.currentProjectSaved = false
	end

	refs.State.currentProjectSaved = false
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Add " .. motor.PropertyId .. " key")
	return frame
end

function Settings.addFirstFreeKey(motor)
	return addKey(motor, true)
end

function Settings.addAtCurrentTime(motor)
	return addKey(motor, false)
end

function Settings.setEnabled(rig, id, enabled)
	assert(not Edit.blocked(), "Finish the current edit before changing properties")
	refs.Finalize()
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local before = Tracks.snapshot(rig, raw, true)
	Tracks.enable(rig, id, enabled, raw)
	local after = Tracks.snapshot(rig, raw, true)

	local function apply(data)
		Tracks.restore(rig, data, timeline, refs.State.UIHelpers.SanitizeName)
		refs.RefreshStructure()
		timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
		refs.State.currentProjectSaved = false
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Toggle " .. id .. " property")
end

function Settings.setTrackEnabled(rig, id, enabled)
	assert(id == "Events" or id == "Faces", "Unknown item track")
	refs.Finalize()
	local track = Events.get(rig)
	local before = Events.snapshot(track)
	local field = id == "Events" and "Enabled" or "FacesEnabled"
	local after = Events.snapshot(track)
	after[field] = enabled ~= false

	local function apply(value)
		Events.restore(track, value)
		if id == "Events" then
			Playback.disable()
		end

		refs.RefreshStructure()
		refs.State.Timeline:ApplyPoseAtTime(rig, refs.State.Timeline:GetState().CurrentTime)
	end

	apply(after)
	History.record(function()
		apply(before)
	end, function()
		apply(after)
	end, "Toggle " .. id)
end

function Settings.setPartTracks(rig, enabled)
	assert(not Edit.blocked(), "Finish the current edit first")
	refs.Finalize()
	local before = rig:GetAttribute("EclipseIndividualParts")

	local function apply(value)
		rig:SetAttribute("EclipseIndividualParts", value)
		refs.RefreshStructure()
		refs.State.currentProjectSaved = false
	end

	apply(enabled)
	History.record(function()
		apply(before)
	end, function()
		apply(enabled)
	end, "Toggle individual parts")
end

local function missing(rig)
	return typeof(rig) == "Instance" and not rig:IsDescendantOf(game)
end

local function placeholder(rig)
	for _, record in refs.State.MissingRigEntries or {} do
		if record.holder == rig then
			return true
		end
	end

	return false
end

local function restoreMissing(rig)
	assert(not Edit.blocked(), "Finish the current edit first")
	assert(missing(rig) and table.find(refs.State.getProjectRigs(), rig), "This item is no longer missing")
	refs.Finalize()
	const before = rig.Parent
	local function place(parent)
		rig.Parent = parent
		if parent and CameraRig.isRig(rig) then
			CameraRig.organize(rig, require("Project").getProjectExportName())
		end

		refs.RefreshStructure()
		const timeline = refs.State.Timeline
		if rig:IsDescendantOf(workspace) then
			timeline:ApplyPoseAtTime(rig, timeline:GetState().CurrentTime)
		end

		refs.State.currentProjectSaved = false
	end

	place(workspace)
	const after = rig.Parent
	History.record(function()
		place(before)
	end, function()
		place(after)
	end, "Restore " .. rig.Name)
end

local function openMissing(rig)
	Settings.close()
	owner = rig
	const restorable = not placeholder(rig)
	window = Tool.new(refs, "EclipseItemSettings", "MISSING ITEM", Vector2.new(290, restorable and 176 or 146), false, function()
		window = nil
		owner = nil
	end)
	const frame = window.frame
	const title = Tool.label(frame, "Item", rig.Name, UDim2.fromOffset(12, 33), UDim2.new(1, -24, 0, 21))
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	const note = Tool.label(
		frame,
		"Note",
		restorable and "This item was deleted from the place. Its keys are kept."
			or "This saved item isn't in the place. Its keys are kept and saved.",
		UDim2.fromOffset(12, 58),
		UDim2.new(1, -24, 0, 34)
	)
	note.TextWrapped = true
	note.TextTransparency = 0.25
	if restorable then
		Tool.button(frame, "RestoreRig", "RESTORE TO WORKSPACE", UDim2.new(0, 12, 1, -66), UDim2.new(1, -24, 0, 24), function()
			Settings.close()
			const ok, err = pcall(restoreMissing, rig)
			if not ok then
				Notification.show("RESTORE", (tostring(err):gsub("^.-:%d+: ", "")))
			end
		end)
	end

	const _, label = Tool.button(frame, "DeleteRig", "REMOVE FROM ANIMATION", UDim2.new(0, 12, 1, -36), UDim2.new(1, -24, 0, 24), function()
		Settings.close()
		refs.Remove(rig)
	end)
	label:SetAttribute("ThemeTxt", nil)
	label.TextColor3 = Color3.fromRGB(245, 135, 148)
	Theme.applyTree(frame)
end

function Settings.open(rig)
	if refs and refs.Active() and refs.Remove and missing(rig) and table.find(refs.State.getProjectRigs(), rig) then
		const ok, err = pcall(openMissing, rig)
		if not ok then
			warn("Eclipse could not open the missing item menu:", err)
			Settings.close()
			refs.Remove(rig)
		end

		return
	end

	if not refs or not refs.Active() or not table.find(refs.State.getAllRigs(), rig) then
		return
	end

	Settings.close()
	owner = rig
	local camera = CameraRig.isRig(rig)
	local definitions = camera
			and {
				{ id = "EclipseTrackTarget", label = "Track CamTarget" },
				{ id = "EclipseHideCamTarget", label = "Hide CamTarget" },
			}
		or Tracks.catalog(rig)
	for i = #definitions, 1, -1 do
		if definitions[i].hidden then
			table.remove(definitions, i)
		end
	end

	table.insert(definitions, 1, { id = "Events", label = "Events" })
	if Faces.supports(rig) then
		table.insert(definitions, 2, { id = "Faces", label = "Faces" })
	end

	local trackCount = Faces.supports(rig) and 2 or 1
	if PartRig.supports(rig) then
		trackCount += 1
		table.insert(
			definitions,
			trackCount,
			{ id = "IndividualParts", label = "Individual parts" }
		)
	end

	local hasProperties = #definitions > trackCount
	local height = 116
		+ math.clamp(#definitions, 1, 9) * 27
		+ 22
		+ (hasProperties and 32 or 0)
		+ (camera and 60 or 0)
	window = Tool.new(
		refs,
		"EclipseItemSettings",
		"ITEM SETTINGS",
		Vector2.new(290, height),
		false,

		function()
			if unsubscribe then
				unsubscribe()
				unsubscribe = nil
			end

			window = nil
			owner = nil
		end
	)
	local frame = window.frame
	local title =
		Tool.label(frame, "Item", rig.Name, UDim2.fromOffset(12, 33), UDim2.new(1, -24, 0, 21))
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local divider = Tool.make("Frame", frame, "Divider", {
		Position = UDim2.fromOffset(12, 61),
		Size = UDim2.new(1, -24, 0, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(69, 41, 93),
	})
	divider:SetAttribute("ThemeBg", "Strk")
	local list = Tool.make("ScrollingFrame", frame, "Properties", {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 1, camera and -176 or -116),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
	})
	Tool.make(
		"UIListLayout",
		list,
		"Rows",
		{ Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	if #definitions == 0 then
		Tool.label(
			list,
			"Empty",
			"No additional properties",
			UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 0, 24)
		)
	end

	local function section(name, order)
		local header = Tool.make(
			"Frame",
			list,
			name .. "Section",
			{ Size = UDim2.new(1, -6, 0, 20), BackgroundTransparency = 1, LayoutOrder = order }
		)
		local label = Tool.label(
			header,
			"Title",
			string.upper(name),
			UDim2.fromOffset(1, 0),
			UDim2.new(1, 0, 1, 0)
		)
		label.TextSize = 10
		label.TextTransparency = 0.35
	end

	section("Tracks", 0)
	if hasProperties then
		local divider = Tool.make("Frame", list, "PropertyDivider", {
			Size = UDim2.new(1, -6, 0, 1),
			BorderSizePixel = 0,
			LayoutOrder = trackCount * 10 + 1,
		})
		divider:SetAttribute("ThemeBg", "Strk")
		section(camera and "Camera target" or "Properties", trackCount * 10 + 2)
	end

	if rig:IsA("ParticleEmitter") then
		local emit = Tool.make("Frame", list, "Emit", { Size = UDim2.new(1, -6, 0, 28), BackgroundTransparency = 1, LayoutOrder = trackCount * 10 + 3 })
		local count = Tool.make("TextBox", emit, "Count", { Text = tostring(rig:GetAttribute("EmitCount") or 1), ClearTextOnFocus = false, Size = UDim2.new(0.4, -4, 1, 0), BackgroundTransparency = 0.5, TextSize = 12 })
		count:SetAttribute("ThemeBg", "TopBtn")
		count:SetAttribute("ThemeTxt", "Txt")
		local button = Tool.make("TextButton", emit, "Add", { Text = "Emit() at playhead", Position = UDim2.fromScale(0.4, 0), Size = UDim2.fromScale(0.6, 1), TextSize = 12 })
		button:SetAttribute("ThemeBg", "TopBtn")
		button:SetAttribute("ThemeTxt", "Txt")
		button.Activated:Connect(Events.vfxDisabled)
	end
	local rows = {}

	local function refresh()
		for id, row in rows do
			local enabled = id == "Events" and Events.get(rig).Enabled ~= false
				or id == "Faces" and Events.get(rig).FacesEnabled == true
				or id ~= "Events"
					and id ~= "Faces"
					and (camera and rig:GetAttribute(id) == true or not camera and Tracks.enabled(
						rig,
						id
					))
			local checked = id == "IndividualParts"
					and PartRig.enabled(rig, refs.State.Timeline:GetState())
				or id ~= "IndividualParts" and enabled
			row.check.Visible = checked
			row.label.TextTransparency = checked and 0 or 0.2
		end
	end

	for index, def in definitions do
		local button = Tool.make("TextButton", list, def.id, {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BackgroundColor3 = Color3.fromRGB(51, 0, 77),
			Size = UDim2.new(1, -6, 0, 24),
			LayoutOrder = index * 10,
		})
		local box = Tool.make("Frame", button, "Checkbox", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 1, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(51, 0, 77),
		})
		box:SetAttribute("ThemeBg", "TopBtn")
		local stroke = Tool.make("UIStroke", box, "Outline", {
			Color = Color3.fromRGB(69, 41, 93),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
		stroke:SetAttribute("ThemeStrk", "Strk")
		local check =
			Tool.label(box, "Check", "✓", UDim2.fromOffset(0, -1), UDim2.fromScale(1, 1))
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.TextSize = 14
		if def.id == "Events" or def.id == "Faces" then
			local icon = Tool.make("ImageLabel", button, "Icon", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(26, 4),
				Size = UDim2.fromOffset(16, 16),
				Image = def.id == "Faces" and Faces.ICON or "",
				ImageColor3 = Theme.get("Txt", Color3.new(1, 1, 1)),
			})
			if def.id == "Events" then
				require("EventIcons").attach(icon, "track")
			else
				Faces.attach(icon)
			end
		end

		local label =
			Tool.label(button, "Label", def.label, UDim2.fromOffset(26, 0), UDim2.new(1, -26, 1, 0))
		label.TextWrapped = false
		if def.id == "Events" or def.id == "Faces" then
			label.Position = UDim2.fromOffset(48, 0)
			label.Size = UDim2.new(1, -48, 1, 0)
		end

		rows[def.id] = { check = check, label = label }
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0.5
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
		end)
		button:SetAttribute("ThemeBg", "TopBtn")
		button.Activated:Connect(function()
			if Tracks.required(rig, def.id) then
				return
			end

			if not rig.Parent or not table.find(refs.State.getAllRigs(), rig) then
				Settings.close()
				return
			end

			local ok, err
			if def.id == "Events" or def.id == "Faces" then
				local track = Events.get(rig)
				local value = if def.id == "Events" then track.Enabled else track.FacesEnabled
				ok, err = pcall(Settings.setTrackEnabled, rig, def.id, value == false)
			elseif def.id == "IndividualParts" then
				ok, err = pcall(function()
					Settings.close()
					require("PartRigging").open(rig)
				end)
			elseif camera then
				ok, err = pcall(
					require("Targets").setOption,
					rig,
					def.id,
					rig:GetAttribute(def.id) ~= true
				)
			else
				ok, err = pcall(Settings.setEnabled, rig, def.id, not Tracks.enabled(rig, def.id))
			end

			if ok then
				refresh()
			else
				Notification.show("PROPERTY", (tostring(err):gsub("^.-:%d+: ", "")))
			end
		end)
	end

	refresh()
	unsubscribe = History.subscribe(function()
		if owner ~= rig then
			return
		end

		if not rig.Parent or not table.find(refs.State.getAllRigs(), rig) then
			Settings.close()
			return
		end

		refresh()
	end)
	if camera then
		Tool.button(
			frame,
			"AttachToPart",
			"ATTACH TO PART…",
			UDim2.new(0, 12, 1, -96),
			UDim2.new(1, -24, 0, 24),

			function()
				Settings.close()
				require("Targets").openCameraAttachment(rig)
			end
		)
	end

	if camera then
		Tool.button(
			frame,
			"ParentTarget",
			"PARENT AT CURRENT FRAME…",
			UDim2.new(0, 12, 1, -66),
			UDim2.new(1, -24, 0, 24),

			function()
				Settings.close()
				require("Targets").openParent(rig)
			end
		)
	end

	local button, label = Tool.button(
		frame,
		"DeleteRig",
		"REMOVE FROM ANIMATION",
		UDim2.new(0, 12, 1, -36),
		UDim2.new(1, -24, 0, 24),

		function()
			Settings.close()
			refs.Remove(rig)
		end
	)
	label:SetAttribute("ThemeTxt", nil)
	label.TextColor3 = Color3.fromRGB(245, 135, 148)
	Theme.applyTree(frame)
end

function Settings.setFaceValue(rig, id, value)
	assert(refs and refs.Active() and not Edit.blocked(), "Finish the current edit first")
	assert(Tracks.faceControls(rig), "This rig has no dynamic head")
	local definition = Tracks.definition(rig, id)
	assert(definition and definition.facial and typeof(value) == "number" and value == value and value >= 0 and value <= 1, "Enter a value from 0 to 1")
	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	assert(not raw.Playing, "Pause playback to edit the face")
	local motor = Tracks.enable(rig, id, true, raw)
	local before = timeline:_snapshotMotorBucket(motor)
	local frame = timeline:TimeToFrame(raw.CurrentTime)
	timeline:RecordKeyframeForMotorAtCurrentTime(motor.Part1, motor, Tracks.encode(value), { Frame = frame, PropertyValue = value }, refs.State.UIHelpers.SanitizeName)
	local after = timeline:_snapshotMotorBucket(motor)
	local function apply(bucket)
		timeline:_restoreMotorBucket(motor, bucket)
		timeline:ApplyPoseAtTime(rig, raw.CurrentTime, { OnlyRig = true })
		refs.State.currentProjectSaved = false
	end
	apply(after)
	History.record(function() apply(before) end, function() apply(after) end, "Edit " .. definition.label, frame)
	return motor
end

function Settings.openFaceControls(rig)
	return require("PoseSliders").toggleFace(rig)
end


function Settings.init(options)
	refs = options
	require("Targets").init(options)
	options.State.PropertySettings = Settings
	options.ScreenGui.Destroying:Once(Settings.close)
	options.Plugin.Unloading:Once(Settings.close)
	options.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not options.AnimatorFrame.Visible then
			Settings.close()
		end
	end)
end

return Settings
