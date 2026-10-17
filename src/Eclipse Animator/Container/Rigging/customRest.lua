--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Auto = {}
const MAX_JOINTS = 12
const SIDES = { "left", "right" }
Auto.MAX_JOINTS = MAX_JOINTS

local function limbName(motor)
	const name = (motor.Part1.Name:lower():gsub("[^%a]", ""))
	for _, side in SIDES do
		if #name > #side and name:sub(1, #side) == side then
			return side, name:sub(#side + 1)
		end
	end

	for _, side in SIDES do
		const first, last = name:find(side, 1, true)
		if first and #name > #side then
			return side, name:sub(1, first - 1) .. name:sub(last + 1)
		end
	end

	return nil, name
end

function Auto.limbKind(owner)
	local _, name = limbName(owner)
	return (name:find("foot", 1, true) or name:find("ankle", 1, true) or name:find("boot", 1, true) or name:find("pant", 1, true) or name:find("leg", 1, true)) and "Leg" or "Arm"
end

function Auto.limbEndpoint(selected, motors)
	if not Auto.isJoint(selected) then return selected end
	local side, name = limbName(selected)
	if not side then return selected end
	local kind = Auto.limbKind(selected)
	local stem = kind == "Leg" and (name:find("pant", 1, true) and "pant" or "leg") or "arm"
	if kind == "Leg" and name:find("boot", 1, true) then stem = "pant" end
	local upper, lower
	for _, motor in motors do
		if Auto.isJoint(motor) then
			local otherSide, otherName = limbName(motor)
			if otherSide == side then
				if otherName == "upper" .. stem then upper = upper == nil and motor or false end
				if otherName == "lower" .. stem then lower = lower == nil and motor or false end
			end
		end
	end
	if not upper or not lower or lower.Part0 ~= upper.Part1 then return selected end
	local endpoint
	for _, motor in motors do
		if Auto.isJoint(motor) and motor.Part0 == lower.Part1 then
			local otherSide, otherName = limbName(motor)
			if otherSide == side and (otherName == "foot" or otherName == "ankle" or otherName == "bootmain" or kind == "Arm" and otherName == "hand") then
				if endpoint then return selected end
				endpoint = motor
			end
		end
	end
	if not endpoint then return selected end
	if selected == upper or selected == lower or selected == endpoint then return endpoint end
	if kind == "Leg" and name:sub(1, 4) == "boot" then return endpoint end
	return selected
end

function Auto.jointCount(owner)
	const joints = owner:GetAttribute("EclipseAutoIKJoints")
	if type(joints) == "number" and joints >= 2 and joints <= MAX_JOINTS then
		return math.floor(joints)
	end

	return 3
end

function Auto.attributeNames()
	const names = { "EclipseAutoIK", "EclipseAutoIKJoints" }
	for i = 1, MAX_JOINTS do
		table.insert(names, "EclipseAutoIKRest" .. i)
	end

	return names
end

function Auto.rest(owner)
	local result = {}
	const count = Auto.jointCount(owner)
	for i = 1, count do
		local cf = owner:GetAttribute("EclipseAutoIKRest" .. i)
		if typeof(cf) ~= "CFrame" then
			return {}
		end

		result[i] = cf
	end

	return result
end

function Auto.restoreRest(owner, values)
	values = type(values) == "table" and values or {}
	local count = 0
	while count < MAX_JOINTS and values[count + 1] ~= nil do
		count += 1
	end

	for i = 1, count do
		const cf = values[i]
		assert(typeof(cf) == "CFrame", "Invalid custom IK calibration")
		for _, v in { cf:GetComponents() } do
			assert(v == v and math.abs(v) < 1e9, "Invalid custom IK calibration")
		end
	end

	for i = 1, MAX_JOINTS do
		owner:SetAttribute("EclipseAutoIKRest" .. i, if i <= count then values[i] else nil)
	end

	owner:SetAttribute(
		"EclipseAutoIKJoints",
		if count == 2 or count > 3 then count else nil
	)
end

function Auto.isJoint(motor)
	return typeof(motor) == "Instance"
			and motor:IsA("Motor6D")
			and motor.Part0 ~= nil
			and motor.Part1 ~= nil
		or typeof(motor) == "table"
			and rawget(motor, "_bone") ~= nil
			and motor.Parent ~= nil
			and not require("ArmatureRuntime").isDriven(motor.Bone)
end

function Auto.index(motors)
	local parents = {}
	for _, motor in motors do
		if Auto.isJoint(motor) then
			if parents[motor.Part1] ~= nil then
				parents[motor.Part1] = false
			else
				parents[motor.Part1] = motor
			end
		end
	end

	return parents
end

local function parentOf(motor)
	return typeof(motor) == "table" and motor.RealPart0 or motor.Part0
end

const branches = setmetatable({}, { __mode = "k" })

local function isBranch(part, motors, parents)
	local limbs = branches[parents]
	if not limbs then
		const hasChild = {}
		for _, motor in motors do
			if Auto.isJoint(motor) and parentOf(motor) then
				hasChild[parentOf(motor)] = true
			end
		end

		limbs = {}
		for _, motor in motors do
			const parent = Auto.isJoint(motor) and hasChild[motor.Part1] and parentOf(motor)
			if parent then
				limbs[parent] = (limbs[parent] or 0) + 1
			end
		end

		branches[parents] = limbs
	end

	return (limbs[part] or 0) > 1
end

function Auto.depth(endpoint, parents)
	local count, current, seen = 1, endpoint, { [endpoint] = true }
	while count < MAX_JOINTS do
		const parent = parents[parentOf(current)]
		if not parent or seen[parent] then
			break
		end

		seen[parent] = true
		count += 1
		current = parent
	end

	return count
end

function Auto.chain(rig, endpoint, motors, parents, count)
	if not Auto.isJoint(endpoint) then
		return nil, "Select a Motor6D joint or a bone at the end of a limb"
	end

	parents = parents or Auto.index(motors)

	const registered = endpoint:GetAttribute("EclipseAutoIK") == true
	const joints = endpoint:GetAttribute("EclipseAutoIKJoints")
	local wanted = count
	if wanted == nil and registered and type(joints) == "number" and joints > 3 then
		wanted = joints
	end

	local lower = parents[parentOf(endpoint)]
	local upper = lower and parents[parentOf(lower)]
	if lower == endpoint then
		lower, upper = nil, nil
	end

	const three = upper and upper ~= lower and upper ~= endpoint
	local members
	if type(wanted) == "number" then
		wanted = math.floor(wanted)
		if wanted < 2 or wanted > MAX_JOINTS then
			return nil, "Custom IK chains use 2 to " .. MAX_JOINTS .. " joints"
		end

		members = { endpoint }
		for _ = 2, wanted do
			const parent = parents[parentOf(members[1])]
			if not parent or table.find(members, parent) then
				return nil, "The selected end joint needs " .. (wanted - 1) .. " connected parent joints"
			end

			table.insert(members, 1, parent)
		end
	elseif joints == 2 then
		members = lower and { lower, endpoint }
	elseif three and (registered or not isBranch(parentOf(lower), motors, parents)) then
		members = { upper, lower, endpoint }
	elseif not registered then
		members = lower and { lower, endpoint }
	end

	if not members then
		return nil, "The selected end joint needs a connected parent joint"
	end

	local boneChain = typeof(endpoint) == "table"
	for _, motor in members do
		if (typeof(motor) == "table") ~= boneChain then
			return nil, "Choose joints of the same type"
		end

		if
			not motor.Part1:IsDescendantOf(rig)
			or (typeof(motor) == "Instance" and not motor:IsDescendantOf(rig))
		then
			return nil, "All joints must belong to the selected rig"
		end
	end

	for i = 2, #members do
		const a = members[i - 1].Part0.CFrame * members[i - 1].C0
		const b = members[i].Part0.CFrame * members[i].C0
		if (b.Position - a.Position).Magnitude < 0.0001 then
			return nil, "The chain has a zero-length segment"
		end
	end

	return members
end

function Auto.setup(selectedMotor, selectedRig, count)
	local State = require("State")
	local timeline = State.Timeline
	if
		not timeline
		or require("BlenderEdit").blocked()
		or timeline:IsExportLocked()
		or State.PhysicsSimulating
	then
		return
	end

	local motor, rig = selectedMotor, selectedRig
	if not motor then
		motor, rig = require("IKPanel").selection()
	end

	local Notice = require("Notification")
	if not motor or not rig then
		Notice.show("AUTO IK", "Select the end joint of the limb in the timeline")
		return
	end

	if State.getAllRigs and not table.find(State.getAllRigs(), rig) then
		Notice.show("AUTO IK", "This rig is no longer in the active animation.", 4)
		return
	end

	local IK = require("LimbIK")
	local entry = IK.getRig(rig)
	motor = Auto.limbEndpoint(motor, entry.motors)
	if entry.owners[motor] then
		Notice.show("AUTO IK", "This joint already has IK controls. Use its FK / IK toggle.")
		return
	end

	local chain, message = Auto.chain(rig, motor, entry.motors, nil, count)
	if not chain then
		Notice.show("AUTO IK", message)
		return
	end

	for _, member in chain do
		if entry.members[member] then
			Notice.show("AUTO IK", "This chain overlaps another IK limb")
			return
		end
	end

	local previous = motor:GetAttribute("EclipseAutoIK")
	const previousJoints = motor:GetAttribute("EclipseAutoIKJoints")
	local Controls = require("R6Controls")
	local created = {}
	local previousRest, setupRest = {}, {}
	for i = 1, MAX_JOINTS do
		previousRest[i] = motor:GetAttribute("EclipseAutoIKRest" .. i)
		setupRest[i] = chain[i] and (State.Timeline:GetState().DefaultPose[chain[i]] or chain[i].C0)
	end

	local function refresh()
		IK.invalidate(rig)
		require("Project").refreshTimelineAfterStructureChange()
		State.currentProjectSaved = false
	end

	local function apply()
		motor:SetAttribute("EclipseAutoIK", true)
		motor:SetAttribute("EclipseAutoIKJoints", if #chain == 3 then nil else #chain)
		for i = 1, MAX_JOINTS do
			motor:SetAttribute("EclipseAutoIKRest" .. i, setupRest[i])
		end

		IK.invalidate(rig)
		for _, child in created do
			if child.Parent == nil and not Controls.find(motor, child:GetAttribute("EclipseR6Control")) then
				child.Parent = motor.Part1
			end
		end

		local found = assert(IK.chain(rig, motor), "Custom IK chain could not be registered")
		local before = {}
		for _, child in motor.Part1:GetChildren() do
			before[child] = true
		end

		local ok, why = pcall(IK.prepare, found)
		for _, child in motor.Part1:GetChildren() do
			if not before[child] and Controls.isControl(child) then
				table.insert(created, child)
			end
		end

		assert(ok, why)
		refresh()
	end

	local function undo()
		motor:SetAttribute("EclipseAutoIK", previous)
		motor:SetAttribute("EclipseAutoIKJoints", previousJoints)
		for i = 1, MAX_JOINTS do
			motor:SetAttribute("EclipseAutoIKRest" .. i, previousRest[i])
		end

		for _, child in created do
			child.Parent = nil
		end

		refresh()
	end

	local ok, why = pcall(apply)
	if not ok then
		undo()
		Notice.show("AUTO IK", tostring(why))
		return
	end

	require("History").record(undo, apply, "Set up custom IK")
	return motor, rig
end

function Auto.candidates(rig, motors, entry, counts)
	local result, parents = {}, Auto.index(motors)
	for _, motor in motors do
		local registered = entry.owners[motor]
		local chain
		if registered then
			if registered.kind ~= "Torso" then
				chain = registered.motors
			end
		elseif
			Auto.isJoint(motor)
			and (
				motor:GetAttribute("EclipseAutoIK") == true
				or Auto.limbEndpoint(motor, motors) == motor
			)
		then
			const wanted = counts and counts[motor]
			chain = wanted and Auto.chain(rig, motor, motors, parents, wanted)
				or Auto.chain(rig, motor, motors, parents)
		end

		if chain then
			local overlap = false
			for _, member in chain do
				if entry.members[member] and entry.members[member] ~= entry.owners[motor] then
					overlap = true
				end
			end

			if not overlap then
				local names = {}
				for _, member in chain do
					table.insert(names, member.Part1.Name)
				end

				local path = motor:GetFullName()
				local prefix = rig:GetFullName() .. "."
				if path:sub(1, #prefix) == prefix then
					path = path:sub(#prefix + 1)
				end

				table.insert(result, {
					motor = motor,
					chain = chain,
					configured = registered ~= nil,
					limit = if registered then #chain else Auto.depth(motor, parents),
					name = motor.Part1.Name,
					path = path,
					search = (path .. " " .. table.concat(names, " ")):lower(),
				})
			end
		end
	end

	table.sort(result, function(a, b)
		if a.name == b.name then
			return a.path < b.path
		end

		return a.name:lower() < b.name:lower()
	end)
	return result
end

function Auto.pick(candidates, selected)
	local exact, related = {}, {}

	local function matches(motor, object)
		return object == motor
			or object == motor.Part1
			or typeof(motor) == "table" and object == motor.Bone
	end

	for _, item in candidates do
		for _, object in selected do
			if matches(item.motor, object) then
				exact[item.motor] = item
			end

			for _, member in item.chain do
				if matches(member, object) then
					related[item.motor] = item
				end
			end
		end
	end

	local pool = next(exact) and exact or related
	local choice, count = nil, 0
	for _, item in pool do
		choice = item
		count += 1
	end

	return count == 1 and choice or nil, count
end

local refs, host
local connections = {}

function Auto.close()
	if host then
		local old = host
		host = nil
		old:close(true)
	end
end

function Auto.destroy()
	Auto.close()
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
end

function Auto.open()
	if host or not refs or not refs.Active() then
		return
	end

	local State = refs.State
	local timeline = State.Timeline
	local rig = require("SelectedRig").resolve(State)
	local Notice = require("Notification")
	if not rig or not timeline then
		Notice.show("AUTO IK", "Add a rig first.", 4)
		return
	end

	local Tool = require("Tool")
	local IK = require("LimbIK")
	local session
	session = Tool.new(
		refs,
		"EclipseAutoIK",
		"AUTO IK · " .. rig.Name,
		Vector2.new(360, 152),
		false,

		function()
			if host == session then
				host = nil
			end
		end
	)
	host = session
	local frame = session.frame
	local guide = Tool.label(
		frame,
		"Guide",
		"Choose a limb",
		UDim2.fromOffset(14, 34),
		UDim2.fromOffset(232, 22)
	)
	guide.TextSize = 14
	local search =
		Tool.field(frame, "Search", "", UDim2.fromOffset(14, 62), UDim2.fromOffset(332, 28))
	search.PlaceholderText = "Find a limb..."
	local list = Tool.make("ScrollingFrame", frame, "Endpoints", {
		Position = UDim2.fromOffset(14, 62),
		Size = UDim2.fromOffset(332, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
	})
	local selected, candidates, rows = nil, {}, {}
	const counts = setmetatable({}, { __mode = "k" })
	local createButton, createLabel
	local fewerButton, moreButton, jointsLabel
	local refresh, draw, choose
	local lastMotor, lastRig, lastObjects = nil, nil, {}

	local function alive()
		return host == session
			and not session.closed
			and State.Timeline == timeline
			and refs.Active()
			and table.find(State.getAllRigs(), rig) ~= nil
	end

	local function show()
		local item
		for _, v in candidates do
			if v.motor == selected then
				item = v
				break
			end
		end

		if item then
			for _, member in item.chain do
				if not Auto.isJoint(member) or not member.Part1:IsDescendantOf(rig) then
					selected = nil
					item = nil
					break
				end
			end
		end

		for motor, row in rows do
			row.outline.Enabled = motor == selected
			row.label:SetAttribute("AutoIKSelected", motor == selected)
		end

		local configured = item and IK.chain(rig, selected)
		local enabled = configured and IK.isEnabled(selected, timeline:GetState().CurrentTime or 0)
		local ready = item ~= nil
			and not enabled
			and not State.PhysicsSimulating
			and not timeline:IsExportLocked()
			and not require("BlenderEdit").blocked()
		createButton.Active = ready
		createButton:SetAttribute("Ready", ready)
		const editable = item ~= nil and not item.configured and ready
		const joints = item and #item.chain or 0
		jointsLabel.Text = item and (joints .. " JOINTS") or "JOINTS"
		fewerButton.Active = editable and joints > 2
		moreButton.Active = editable and joints < (item.limit or joints)
		fewerButton:SetAttribute("Ready", fewerButton.Active)
		moreButton:SetAttribute("Ready", moreButton.Active)
		createLabel.Text = not item and "SELECT A LIMB"
			or enabled and "IK ENABLED"
			or configured and "ENABLE IK"
			or "CREATE IK"
	end

	draw = function()
		if not alive() then
			return
		end

		for _, child in list:GetChildren() do
			child:Destroy()
		end

		table.clear(rows)
		local query = search.Text:lower():match("^%s*(.-)%s*$")
		local visible, names = {}, {}
		for _, item in candidates do
			names[item.name] = (names[item.name] or 0) + 1
			if query == "" or item.search:find(query, 1, true) then
				table.insert(visible, item)
			end
		end

		local selectedVisible = false
		for _, item in visible do
			if item.motor == selected then
				selectedVisible = true
			end
		end

		if not selectedVisible then
			selected = nil
		end

		for i, item in visible do
			local title = names[item.name] > 1 and item.path or item.name
			local button, text = Tool.button(
				list,
				"Endpoint" .. i,
				title,
				UDim2.fromOffset(0, (i - 1) * 32),
				UDim2.new(1, -6, 0, 28),

				function()
					if not alive() then
						return
					end

					selected = item.motor
					show()
				end
			)
			text.Position = UDim2.fromOffset(8, 0)
			text.Size = UDim2.new(1, -16, 1, 0)
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.TextWrapped = false
			text.TextTruncate = Enum.TextTruncate.AtEnd
			local outline = Tool.make(
				"UIStroke",
				button,
				"Selection",
				{ Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
			)
			outline:SetAttribute("ThemeStrk", "Strk")
			rows[item.motor] = { label = text, outline = outline }
		end

		search.Parent.Visible = #candidates > 6
		local top = #candidates > 6 and 98 or 62
		local height = math.clamp(#visible * 32, 32, 192)
		list.Position = UDim2.fromOffset(14, top)
		list.Size = UDim2.fromOffset(332, height)
		list.CanvasSize = UDim2.fromOffset(0, #visible * 32)
		createButton.Position = UDim2.fromOffset(14, top + height + 10)
		createButton.Visible = #visible > 0
		fewerButton.Position = UDim2.fromOffset(232, top + height + 10)
		jointsLabel.Position = UDim2.fromOffset(260, top + height + 10)
		moreButton.Position = UDim2.fromOffset(320, top + height + 10)
		fewerButton.Visible, jointsLabel.Visible, moreButton.Visible =
			#visible > 0, #visible > 0, #visible > 0
		frame.Size =
			UDim2.fromOffset(360, math.max(152, top + height + (#visible > 0 and 52 or 14)))
		if #visible == 0 then
			Tool.label(
				list,
				"Empty",
				#candidates == 0 and "No supported limbs in this rig." or "No matching limbs.",
				UDim2.fromOffset(4, 2),
				UDim2.new(1, -10, 0, 28)
			)
		end

		show()
		require("Theme").applyTree(frame)
	end

	local function selection()
		local motor, owner = require("IKPanel").selection()
		return motor, owner, game:GetService("Selection"):Get()
	end

	choose = function(motor, owner, objects, preferTimeline)
		lastMotor, lastRig, lastObjects = motor, owner, table.clone(objects)
		local picked
		if preferTimeline then
			picked = Auto.pick(candidates, owner == rig and motor and { motor } or {})
		else
			local count
			picked, count = Auto.pick(candidates, objects)
			if count == 0 then
				picked = Auto.pick(candidates, owner == rig and motor and { motor } or {})
			end
		end

		selected = picked and picked.motor or nil
		search.Text = ""
		draw()
		if selected then
			for i, item in candidates do
				if item.motor == selected then
					list.CanvasPosition = Vector2.new(0, math.max(0, (i - 2) * 32))
					break
				end
			end
		end
	end

	refresh = function()
		if not alive() then
			Auto.close()
			return
		end

		local motors = require("Parenting").collectMotors(rig)
		candidates = Auto.candidates(rig, motors, IK.getRig(rig), counts)
		if #candidates <= 6 then
			search.Text = ""
		end

		local found = false
		for _, v in candidates do
			if v.motor == selected then
				found = true
			end
		end

		if not found then
			selected = nil
		end

		draw()
	end

	Tool.button(
		frame,
		"Refresh",
		"REFRESH",
		UDim2.fromOffset(264, 34),
		UDim2.fromOffset(82, 22),
		refresh
	)
	createButton, createLabel = Tool.button(
		frame,
		"Create",
		"SELECT A LIMB",
		UDim2.fromOffset(14, 104),
		UDim2.fromOffset(332, 30),

		function()
			if not alive() then
				Auto.close()
				return
			end

			if
				not selected
				or State.PhysicsSimulating
				or timeline:IsExportLocked()
				or require("BlenderEdit").blocked()
			then
				return
			end

			local previous
			for _, v in candidates do
				if v.motor == selected then
					previous = v
					break
				end
			end

			local owner = selected
			refresh()
			local current
			for _, v in candidates do
				if v.motor == owner then
					current = v
					break
				end
			end

			local same = current and previous and #current.chain == #previous.chain
			if same then
				for i, member in previous.chain do
					if current.chain[i] ~= member then
						same = false
						break
					end
				end
			end

			if not same then
				selected = nil
				show()
				Notice.show("AUTO IK", "The rig changed. Select the limb again.", 3)
				return
			end

			if not IK.chain(rig, owner) then
				local created = Auto.setup(owner, rig, #current.chain)
				if not created then
					return
				end
			end

			if not IK.isEnabled(owner, timeline:GetState().CurrentTime or 0) then
				timeline:SwitchIKAtCurrentTime(owner, rig)
			end

			refresh()
		end
	)
	createButton:SetAttribute("Primary", true)
	createButton.Size = UDim2.fromOffset(212, 30)

	local function step(delta)
		if not alive() or not selected then
			return
		end

		local item
		for _, v in candidates do
			if v.motor == selected then
				item = v
				break
			end
		end

		if not item or item.configured or IK.chain(rig, selected) then
			return
		end

		const wanted = #item.chain + delta
		if wanted < 2 or wanted > (item.limit or #item.chain) then
			return
		end

		const entry = IK.getRig(rig)
		const chain, message = Auto.chain(rig, selected, entry.motors, nil, wanted)
		if not chain then
			Notice.show("AUTO IK", message or "This chain can't use that many joints.", 3)
			return
		end

		for _, member in chain do
			if entry.members[member] then
				Notice.show("AUTO IK", "A longer chain would overlap another IK limb.", 3)
				return
			end
		end

		counts[selected] = wanted
		refresh()
	end

	fewerButton = Tool.button(
		frame,
		"FewerJoints",
		"-",
		UDim2.fromOffset(232, 104),
		UDim2.fromOffset(26, 30),
		function()
			step(-1)
		end
	)
	jointsLabel = Tool.label(
		frame,
		"Joints",
		"JOINTS",
		UDim2.fromOffset(260, 104),
		UDim2.fromOffset(58, 30)
	)
	jointsLabel.TextXAlignment = Enum.TextXAlignment.Center
	jointsLabel.TextWrapped = false
	jointsLabel.TextSize = 11
	moreButton = Tool.button(
		frame,
		"MoreJoints",
		"+",
		UDim2.fromOffset(320, 104),
		UDim2.fromOffset(26, 30),
		function()
			step(1)
		end
	)
	table.insert(session.connections, search:GetPropertyChangedSignal("Text"):Connect(draw))
	local elapsed = 0
	table.insert(
		session.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.2 then
				return
			end

			elapsed = 0
			if not alive() then
				Auto.close()
				return
			end

			local motor, owner, objects = selection()
			local changed = #objects ~= #lastObjects
			if not changed then
				for i, object in objects do
					if object ~= lastObjects[i] then
						changed = true
						break
					end
				end
			end

			if changed or motor ~= lastMotor or owner ~= lastRig then
				choose(motor, owner, objects, not changed)
			else
				show()
			end
		end)
	)
	refresh()
	local motor, owner, objects = selection()
	choose(motor, owner, objects, false)
end

function Auto.toggle()
	if host then
		Auto.close()
	else
		Auto.open()
	end
end

function Auto.init(options)
	Auto.destroy()
	refs = options
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Auto.close()
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Auto.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Auto.destroy))
end

return Auto
