--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local PartRig = require("PartRig")
local Accessories = require("Accessories")
local SelectedRig = require("SelectedRig")
local Tool = require("Tool")
local Theme = require("Theme")
local History = require("History")
local Notice = require("Notification")
local Membership = require("Membership")
local Rigging = {}
local refs, window

function Rigging.bindTargets(anchor, targets, inPlace, animatable)
	assert(refs and refs.Active(), "Open an animation first")
	assert(not require("BlenderEdit").blocked(), "Finish the current edit first")
	refs.Finalize()
	local state = refs.State
	local timeline = state.Timeline
	local raw = timeline:GetState()
	raw.Playing = false
	local transaction = require("transaction").prepareTimeline(
		anchor,
		targets,
		inPlace,
		raw,
		state.getAllRigs(),
		workspace,
		animatable
	)

	local function refresh()
		timeline:InvalidateMotorListCache()
		require("cache").invalidate()
		refs.RefreshStructure()
		for _, rig in state.getAllRigs() do
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime)
		end

		require("motionPath").markDirty()
		state.currentProjectSaved = false
	end

	local ok, err = xpcall(function()
		transaction.apply(true)
		refresh()
	end, debug.traceback)
	if not ok then
		transaction.apply(false)
		pcall(refresh)
		error(err, 0)
	end

	History.record(function()
		transaction.apply(false)
		refresh()
	end, function()
		transaction.apply(true)
		refresh()
	end, "Bind rig targets")
	return #transaction.entries
end

function Rigging.close()
	if window then
		local old = window
		window = nil
		old:close()
	end
end

local function addAccessories(model, selected)
	refs.Finalize()
	local state = refs.State
	local timeline = state.Timeline
	local raw = timeline:GetState()
	assert(table.find(state.getAllRigs(), model), "Add this rig to the timeline first")
	raw.Playing = false
	local transaction = Accessories.create(model, selected or {})
	local snapshot

	local function detach()
		snapshot = { owned = transaction.owned }
		for _, field in
			{
				"Keyframes",
				"DefaultPose",
				"DefaultWorldPose",
				"ParentingDefaults",
				"MotorByPart",
				"DefaultSize",
				"_motorUniform",
				"_motorHasScale",
			}
		do
			snapshot[field] = {}
			for key, value in raw[field] or {} do
				if snapshot.owned[key] then
					snapshot[field][key] = value
					raw[field][key] = nil
				end
			end
		end
	end

	local function refresh()
		timeline:ClearSelectedKeyframes()
		if state.Axis then
			state.Axis:ClearSelection()
		end

		refs.RefreshStructure()
		state.currentProjectSaved = false
	end

	local function register()
		for _, joint in transaction.joints do
			raw.DefaultPose[joint] = joint.C0
			raw.DefaultWorldPose[joint] = joint.Part1.CFrame
			raw.MotorByPart[joint.Part1] = joint
			raw.ParentingDefaults[joint] = true
		end
	end

	local ok, message = xpcall(function()
		register()
		refresh()
	end, debug.traceback)
	if not ok then
		detach()
		transaction.apply(false)
		error(message, 0)
	end

	History.record(function()
		if not model.Parent then
			return
		end

		detach()
		transaction.apply(false)
		refresh()
	end, function()
		if not model.Parent then
			return
		end

		transaction.apply(true)
		if snapshot then
			Membership.restore(raw, snapshot)
		else
			register()
		end

		refresh()
	end, "Add parts and accessories")
	return #transaction.joints
end

function Rigging.create(model, selected)
	if typeof(model) == "Instance" and model:IsA("BasePart") then
		assert(not selected or selected[model], "Choose the part")
		if not table.find(refs.State.getAllRigs(), model) then
			refs.AddRig(model)
		end

		assert(table.find(refs.State.getAllRigs(), model), "Could not add this part to Eclipse")
		require("Properties").enable(model, "CFrame", true, refs.State.Timeline:GetState())
		refs.RefreshStructure()
		return 1
	end

	if Accessories.supports(model) then
		return addAccessories(model, selected)
	end

	refs.Finalize()
	local state = refs.State
	local timeline = state.Timeline
	local raw = timeline:GetState()
	raw.Playing = false
	local previousParts = model:GetAttribute("EclipseIndividualParts")
	local parts, existing = PartRig.catalog(model)
	if not selected then
		selected = {}
		for _, part in parts do
			selected[part] = true
		end
	end

	selected = table.clone(selected)
	local count = 0
	for part in selected do
		assert(table.find(parts, part), "A selected part was removed")
		count += 1
	end

	local previousChoice = PartRig.choice(model)
	local scene = state.Physics and require("Scene").get()
	local previousEntries = scene and table.clone(scene.entries)
	local previousGuide = scene and scene.guide
	local transaction = PartRig.create(model, selected)

	local function applyChoice(enabled)
		model:SetAttribute("EclipseIndividualParts", if enabled then count > 0 else previousParts)
		if enabled then
			local _, joints = PartRig.catalog(model)
			for part, joint in joints do
				joint:SetAttribute("EclipsePartTrackEnabled", selected[part] == true)
			end
		else
			PartRig.restoreChoice(model, previousChoice)
		end

		if scene then
			scene.entries = table.clone(previousEntries)
			if enabled then
				for motor in scene.entries do
					if motor:GetAttribute("EclipsePartTrackEnabled") == false then
						scene.entries[motor] = nil
					end
				end
			end

			scene.guide = previousGuide and scene.entries[previousGuide.motor] and previousGuide
				or nil
		end
	end

	applyChoice(true)
	local snapshot

	local function detachTracks()
		snapshot = { owned = {} }
		if transaction.createdRoot then
			snapshot.owned[transaction.root] = true
		end

		for _, joint in transaction.joints do
			snapshot.owned[joint] = true
			snapshot.owned[joint.Part1] = true
		end

		for _, field in
			{
				"Keyframes",
				"DefaultPose",
				"DefaultWorldPose",
				"ParentingDefaults",
				"MotorByPart",
				"DefaultSize",
				"_motorUniform",
				"_motorHasScale",
			}
		do
			snapshot[field] = {}
			for key, value in raw[field] or {} do
				if snapshot.owned[key] then
					snapshot[field][key] = value
					raw[field][key] = nil
				end
			end
		end
	end

	local function refresh()
		timeline:ClearSelectedKeyframes()
		if state.Axis then
			state.Axis:ClearSelection()
		end

		refs.RefreshStructure()
		state.currentProjectSaved = false
	end

	local function register()
		for _, joint in transaction.joints do
			raw.DefaultPose[joint] = joint.C0
			raw.DefaultWorldPose[joint] = joint.Part1.CFrame
			raw.MotorByPart[joint.Part1] = joint
			raw.ParentingDefaults[joint] = true
			joint:SetAttribute("EclipseAnimatorDefaultC0", joint.C0)
		end
	end

	local ok, message = xpcall(function()
		register()
		if not table.find(state.getAllRigs(), model) then
			refs.AddRig(model)
		end

		assert(table.find(state.getAllRigs(), model), "Could not add this model to Eclipse")
		refresh()
	end, debug.traceback)
	if not ok then
		detachTracks()
		transaction.apply(false)
		applyChoice(false)
		error(message, 0)
	end

	local functionUndo = function()
		if not model.Parent then
			return
		end

		detachTracks()
		transaction.apply(false)
		applyChoice(false)
		refresh()
	end

	local functionRedo = function()
		if not model.Parent then
			return
		end

		transaction.apply(true)
		applyChoice(true)
		if snapshot then
			Membership.restore(raw, snapshot)
		else
			register()
		end

		refresh()
	end

	History.record(functionUndo, functionRedo, "Rig model parts")
	return count
end

function Rigging.open(model)
	if not refs or not refs.Active() then
		return
	end

	if not model then
		for _, selected in game:GetService("Selection"):Get() do
			for _, rig in refs.State.getAllRigs() do
				if selected == rig or selected:IsDescendantOf(rig) then
					model = rig
					break
				end
			end

			model = model
				or (selected:IsA("Model") and selected or selected:FindFirstAncestorOfClass("Model"))
				or (selected:IsA("BasePart") and selected)
			if model then
				break
			end
		end
	end

	model = model or SelectedRig.resolve(refs.State)
	model = require("rig").localOf(model)
	local accessories = Accessories.supports(model)
	local ok, parts, joints, plans, reasons
	if typeof(model) == "Instance" and model:IsA("BasePart") then
		ok, parts, joints = true, { model }, {}
	else
		ok, parts, joints, plans, reasons =
			pcall(accessories and Accessories.catalog or PartRig.catalog, model)
	end

	if not ok then
		Notice.show("PARTS & ACCESSORIES", (tostring(parts):gsub("^.-:%d+: ", "")))
		return
	end

	if #parts == 0 then
		Notice.show("PARTS & ACCESSORIES", "No additional parts or accessories found")
		return
	end

	Rigging.close()
	local height = math.min(7, #parts) * 28 + 170
	window = Tool.new(
		refs,
		"EclipsePartRigging",
		"PARTS & ACCESSORIES",
		Vector2.new(360, height),
		false,

		function()
			window = nil
		end
	)
	local host, frame = window, window.frame
	local chosen, rows = {}, {}
	local enabled = accessories or PartRig.enabled(model, refs.State.Timeline:GetState())
	for part, joint in joints do
		if enabled and joint:GetAttribute("EclipsePartTrackEnabled") ~= false then
			chosen[part] = true
		end
	end

	local title =
		Tool.label(frame, "Model", model.Name, UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 23))
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local repaint
	Tool.button(
		frame,
		"SelectAll",
		"SELECT ALL",
		UDim2.fromOffset(12, 64),
		UDim2.fromOffset(164, 26),

		function()
			for _, part in parts do
				if not (reasons and reasons[part]) then
					chosen[part] = true
				end
			end

			repaint()
		end
	)
	Tool.button(
		frame,
		"ClearAll",
		"CLEAR ALL",
		UDim2.fromOffset(184, 64),
		UDim2.fromOffset(164, 26),

		function()
			table.clear(chosen)
			if accessories then
				for part in joints do
					chosen[part] = true
				end
			end

			repaint()
		end
	)
	local list = Tool.make("ScrollingFrame", frame, "Parts", {
		Position = UDim2.fromOffset(12, 98),
		Size = UDim2.new(1, -24, 0, height - 170),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	Tool.make(
		"UIListLayout",
		list,
		"Layout",
		{ Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	for i, part in parts do
		local names = part == model and { part.Name } or {}
		local ancestor = part
		while ancestor and ancestor ~= model do
			table.insert(names, 1, ancestor.Name)
			ancestor = ancestor.Parent
		end

		local row = Tool.make("TextButton", list, "Part" .. i, {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -6, 0, 26),
			LayoutOrder = i,
		})
		row:SetAttribute("ThemeBg", "TopBtn")
		local box = Tool.make("Frame", row, "Box", {
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
		})
		box:SetAttribute("ThemeBg", "Pnl")
		local check =
			Tool.label(box, "Check", "✓", UDim2.fromOffset(0, -1), UDim2.fromScale(1, 1))
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.TextSize = 14
		local label = Tool.label(
			row,
			"Name",
			table.concat(names, " / ")
				.. (
					accessories and joints[part] and " (added)"
					or reasons and reasons[part] and " — " .. reasons[part]
					or ""
				),
			UDim2.fromOffset(29, 0),
			UDim2.new(1, -34, 1, 0)
		)
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		rows[part] = check
		row.Interactable = not (accessories and joints[part] or reasons and reasons[part])
		row.Activated:Connect(function()
			if not row.Interactable then
				return
			end

			chosen[part] = not chosen[part] or nil
			repaint()
		end)
	end

	local count = Tool.label(frame, "Count", "", UDim2.new(0, 12, 1, -66), UDim2.new(1, -24, 0, 20))
	Tool.button(
		frame,
		"Cancel",
		"CANCEL",
		UDim2.new(0, 12, 1, -38),
		UDim2.fromOffset(164, 26),
		Rigging.close
	)
	local confirm = Tool.button(
		frame,
		"Confirm",
		accessories and "ADD TO TIMELINE" or "CONFIRM",
		UDim2.new(0, 184, 1, -38),
		UDim2.fromOffset(164, 26),

		function()
			if host.closed or not refs.Active() or not model.Parent then
				return
			end

			local success, result = pcall(Rigging.create, model, chosen)
			if not success then
				Notice.show("PARTS & ACCESSORIES", (tostring(result):gsub("^.-:%d+: ", "")))
				return
			end

			Rigging.close()
		end
	)
	confirm:SetAttribute("ThemeBg", "MenuSel")
	repaint = function()
		local total = 0
		for part, check in rows do
			check.Visible = chosen[part] == true
			if chosen[part] and not (accessories and joints[part]) then
				total += 1
			end
		end

		count.Text = accessories and (total .. " to add • existing tracks are kept")
			or (total .. " / " .. #parts .. " selected")
		confirm.Interactable = total > 0 or not accessories and next(joints) ~= nil
	end

	repaint()
	Theme.applyTree(frame)
	return frame
end

function Rigging.openBoneControls()
	if not refs or not refs.Active() then
		return
	end

	local rig = refs.State.currentRig
	if not rig then
		return
	end

	local runtime = require("ArmatureRuntime")
	local handles = require("handles")
	local org = require("Organization")
	local controls = runtime.controls(rig)
	if #controls == 0 then
		Notice.show("BONE CONTROLS", "Import a Blender armature to choose custom widgets per bone.")
		return
	end

	Rigging.close()
	local height = math.min(10, #controls) * 28 + 110
	local unsubscribe
	window = Tool.new(
		refs,
		"EclipseBoneControls",
		"BONE CONTROLS",
		Vector2.new(390, height),
		false,

		function()
			window = nil
			if unsubscribe then
				unsubscribe()
			end
		end
	)
	local host, frame = window, window.frame
	local painters = {}
	Tool.label(
		frame,
		"Hint",
		"Custom widget / Half bone",
		UDim2.fromOffset(12, 34),
		UDim2.new(1, -24, 0, 24)
	)
	local list = Tool.make("ScrollingFrame", frame, "Bones", {
		Position = UDim2.fromOffset(12, 64),
		Size = UDim2.new(1, -24, 1, -110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	Tool.make(
		"UIListLayout",
		list,
		"Layout",
		{ Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }
	)
	for i, anchor in controls do
		local button, label

		local function paint()
			label.Text = anchor.Name
				.. "  -  "
				.. (org.usesPartWidget(anchor) and "Half bone" or "Custom widget")
		end

		table.insert(painters, paint)
		button, label = Tool.button(list, "Bone" .. i, "", UDim2.new(), UDim2.new(1, -6, 0, 26), function()
			if
				host.closed
				or not refs.Active()
				or not anchor.Parent
				or refs.State.currentRig ~= rig
			then
				return
			end

			refs.Finalize()
			org.setPartWidget(anchor, not org.usesPartWidget(anchor))
			refs.State.currentProjectSaved = false
			paint()
		end
)
		button.LayoutOrder = i
		button.Interactable = true
		label.TextTransparency = 0
		paint()
	end

	unsubscribe = org.subscribe(function()
		if not host.closed then
			for _, paint in painters do
				paint()
			end
		end
	end)
	Tool.button(
		frame,
		"Close",
		"CLOSE",
		UDim2.new(0, 12, 1, -36),
		UDim2.new(1, -24, 0, 24),
		Rigging.close
	)
	Theme.applyTree(frame)
	return frame
end

function Rigging.init(options)
	refs = options
end

return Rigging
