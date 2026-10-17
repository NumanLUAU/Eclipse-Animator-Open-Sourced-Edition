--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Players = game:GetService("Players")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Appearance = require("Appearance")
local History = require("History")
local RigPose = require("RigPose")
local Layout = require("Layout")
local Avatar = {}

function Avatar.init(options)
	local gui, tab, state = options.Gui, options.Tab, options.State
	local card, panel = tab.AvatarCard, tab.AvatarPanel
	local input, button = panel.UserInput, panel.SpawnAvatarButton
	local label = button:FindFirstChild("Label") or button
	local world = card.Preview:FindFirstChildOfClass("WorldModel")
	local pills = {
		ORIGINAL = panel.BodyPills.ORIGINALPill,
		R6 = panel.BodyPills.R6Pill,
		R15 = panel.BodyPills.R15Pill,
	}
	local connections, cache, names, order = {}, {}, {}, {}
	local target, ambiguous, preview, donor, userId, userName, loadedText, shownName
	local bodyMode, defaultBody = "ORIGINAL", false
	local generation, elapsed, busy, destroyed = 0, 0, false, false
	local unsubscribeTheme
	local controller = {}

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	local function fail(message, detail)
		error({ message = message, detail = detail }, 0)
	end

	local function fetch(message, method, ...)
		const ok, result = pcall(method, Players, ...)
		if not ok then
			fail(message, result)
		end

		return result
	end

	local function reason(err)
		if type(err) == "table" then
			return tostring(err.message), err.detail
		end

		return (tostring(err):gsub("^.-:%d+: ", ""))
	end

	local function active()
		return not destroyed and gui.Enabled and tab.Visible
	end

	local function resolve()
		return Appearance.resolve(Selection:Get(), state.Rig and state.Rig._selectedItems)
	end

	local function paint()
		if destroyed then
			return
		end

		label.Text = busy and "LOADING..." or (target or ambiguous) and "REPLACE" or "SPAWN"
		Layout.enabled(button, not busy and not ambiguous and input.Text:match("%S") ~= nil)
		panel.Title.Text = target and "AVATAR · " .. target.Name or "AVATAR"
		panel.Title.TextTruncate = Enum.TextTruncate.AtEnd

		local selected = target and target:FindFirstChildOfClass("Humanoid")
		for name, pill in pills do
			options.SetButtonSelected(
				pill,
				name == (selected and selected.RigType.Name or bodyMode)
			)
			Layout.enabled(pill, not target and not ambiguous and not busy)
		end

		panel.DefaultBodyRow.Toggle.Fill.Visible = defaultBody
	end

	local function show(model, name)
		shownName = name or model and model.Name or "No avatar loaded"
		if preview then
			preview:Destroy()
			preview = nil
		end

		world:ClearAllChildren()
		if not model then
			options.SetEmptyVisible(card.Preview, true)
			card.TargetName.Text = name or "No avatar loaded"
			return
		end

		RigPose.assemble(model)
		for _, child in model:GetDescendants() do
			if child:IsA("LuaSourceContainer") then
				child:Destroy()
			elseif child:IsA("BasePart") then
				child.Anchored = true
			elseif child:IsA("Humanoid") then
				child.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end

		model:PivotTo(CFrame.new())
		model.Parent = world
		preview = model
		options.FitCamera(card.Preview, model, 0.8)
		options.SetEmptyVisible(card.Preview, false)
		card.TargetName.Text = name or model.Name
	end

	local function clearDonor()
		if donor then
			donor:Destroy()
			donor = nil
		end

		loadedText = nil
	end

	function controller.refresh(force)
		if destroyed then
			return
		end

		local rig, multiple = resolve()
		if not force and rig == target and multiple == ambiguous then
			return
		end

		generation += 1
		busy = false
		target, ambiguous = rig, multiple
		clearDonor()
		if target then
			local ok, model = pcall(Appearance.clone, target)
			show(ok and model or nil, target.Name)
		elseif ambiguous then
			show(nil, "select one rig")
		else
			show(nil)
		end

		paint()
	end

	local function avatarData(id)
		if cache[id] then
			return cache[id]
		end

		const description = fetch(
			"Roblox didn't send this avatar, try again",
			Players.GetHumanoidDescriptionFromUserIdAsync,
			id
		)
		if destroyed then
			description:Destroy()
			error("helpers closed", 0)
		end

		if cache[id] then
			description:Destroy()
			return cache[id]
		end

		local data = { description = description }
		cache[id] = data
		table.insert(order, id)
		if #order > 8 then
			local oldest = table.remove(order, 1)
			if cache[oldest] then
				cache[oldest].description:Destroy()
				cache[oldest] = nil
			end
		end

		return data
	end

	local function build(text, rig)
		local id = tonumber(text)
		if id then
			assert(id > 0 and id % 1 == 0, "enter a username or user id")
		else
			id = names[text:lower()]
				or fetch("no user named " .. text, Players.GetUserIdFromNameAsync, text)
		end

		const name = fetch("no user with id " .. id, Players.GetNameFromUserIdAsync, id)
		names[text:lower()] = id
		local data = avatarData(id)
		local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
		if not humanoid and bodyMode == "ORIGINAL" and not data.rigType then
			const original = fetch(
				"Roblox couldn't build this avatar, try again",
				Players.CreateHumanoidModelFromUserIdAsync,
				id
			)
			data.rigType = original:FindFirstChildOfClass("Humanoid").RigType
			original:Destroy()
		end

		local description = data.description:Clone()
		if defaultBody then
			for _, key in
				{
					"Head",
					"Torso",
					"LeftArm",
					"RightArm",
					"LeftLeg",
					"RightLeg",
					"BodyTypeScale",
					"ProportionScale",
				}
			do
				description[key] = 0
			end
		end

		local kind = humanoid and humanoid.RigType
			or bodyMode == "R6" and Enum.HumanoidRigType.R6
			or bodyMode == "R15" and Enum.HumanoidRigType.R15
			or data.rigType
		local ok, model =
			pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, description, kind)
		description:Destroy()
		if not ok then
			fail("Roblox couldn't build this avatar as " .. kind.Name, model)
		end

		return model, id, name
	end

	local function tracks()
		return state.Timeline and state.Timeline:GetState().Keyframes or {}
	end

	local function displayDonor(model, rig, name, current)
		if not rig then
			show(Appearance.clone(model), name)
			return true
		end

		local candidate = Appearance.clone(rig)
		local ok, err = pcall(function()
			local plan = Appearance.prepare(candidate, model, tracks())
			plan:redo()
			plan:destroy()
		end)
		if not ok then
			candidate:Destroy()
			error(err, 0)
		end

		if not current() then
			candidate:Destroy()
			return false
		end

		show(candidate, name)
		return true
	end

	local function apply(rig, model, id, name)
		if rig ~= target or select(2, resolve()) or resolve() ~= rig then
			return
		end

		if not rig then
			local clone = Appearance.clone(model)
			clone.Name = name
			options.PlaceModel(clone, "Eclipse Spawn Avatar")
			controller.refresh(true)
			return
		end

		local plan = Appearance.prepare(rig, model, tracks())
		if not rig.Parent or resolve() ~= rig then
			plan:destroy()
			return
		end

		local previousId = rig:GetAttribute("EclipseAvatarUserId")
		local inFile = false
		for _, candidate in state.getAllRigs() do
			if candidate == rig then
				inFile = true
				break
			end
		end

		local recording
		if not inFile then
			pcall(function()
				recording = ChangeHistoryService:TryBeginRecording(
					"EclipseReplaceAvatar",
					"Replace avatar"
				)
			end)
			if not recording then
				ChangeHistoryService:SetWaypoint("Before Eclipse Replace Avatar")
			end
		end

		local function refresh()
			if inFile then
				state.currentProjectSaved = false
			end

			if active() then
				controller.refresh(true)
			end
		end

		local ok, err = pcall(function()
			plan:redo()
			rig:SetAttribute("EclipseAvatarUserId", id)
		end)
		if not ok then
			if recording then
				ChangeHistoryService:FinishRecording(
					recording,
					Enum.FinishRecordingOperation.Cancel
				)
			end

			plan:destroy()
			error(err, 0)
		end

		if inFile then
			History.record(function()
				plan:undo()
				rig:SetAttribute("EclipseAvatarUserId", previousId)
				refresh()
			end, function()
				plan:redo()
				rig:SetAttribute("EclipseAvatarUserId", id)
				refresh()
			end, "Replace avatar")
		elseif recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint("Eclipse Replace Avatar")
		end

		refresh()
	end

	function controller.load(commit)
		controller.refresh()
		if busy or ambiguous or not active() then
			return
		end

		local text = input.Text:match("^%s*(.-)%s*$"):gsub("^@", "")
		if text == "" then
			card.TargetName.Text = "enter a username or user id"
			return
		end

		local rig = target
		generation += 1
		local token = generation
		busy = true
		card.TargetName.Text = "loading..."
		paint()
		task.spawn(function()
			local model, id, name
			local ok, err = pcall(function()
				if donor and loadedText == text then
					model, id, name = donor, userId, userName
				else
					model, id, name = (options.Build or build)(text, rig)
				end

				if destroyed or token ~= generation or not active() or resolve() ~= rig then
					if model ~= donor then
						model:Destroy()
					end

					return
				end

				if model ~= donor then
					clearDonor()
					donor = model
				end

				userId, userName, loadedText = id, name, text
				if
					not displayDonor(model, rig, name, function()
						return not destroyed
							and token == generation
							and active()
							and resolve() == rig
					end)
				then
					return
				end

				if commit then
					apply(rig, model, id, name)
				end
			end)
			if token == generation and not destroyed then
				busy = false
				if not ok then
					clearDonor()
					const message, detail = reason(err)
					const action = if not commit then "load" elseif rig then "replace" else "spawn"
					card.TargetName.Text = "couldn't " .. action .. ": " .. message
					warn(
						"couldn't " .. action .. " the avatar: " .. message
							.. (if detail ~= nil then " (" .. reason(detail) .. ")" else "")
					)
				end

				paint()
			end
		end)
	end

	function controller.activate()
		controller.load(true)
	end

	function controller.destroy()
		if destroyed then
			return
		end

		destroyed = true
		generation += 1
		for _, connection in connections do
			connection:Disconnect()
		end

		if unsubscribeTheme then
			unsubscribeTheme()
		end

		clearDonor()
		if preview then
			preview:Destroy()
			preview = nil
		end

		for _, data in cache do
			data.description:Destroy()
		end

		table.clear(cache)
	end

	connect(button.MouseButton1Click, controller.activate)
	connect(input:GetPropertyChangedSignal("Text"), function()
		generation += 1
		busy = false
		clearDonor()
		card.TargetName.Text = shownName or "~ none ~"
		paint()
	end)
	connect(input.FocusLost, function(enter)
		if enter then
			controller.load(false)
		end
	end)
	connect(Selection.SelectionChanged, function()
		if active() then
			controller.refresh()
		end
	end)

	local function visibility()
		generation += 1
		busy = false
		if active() then
			controller.refresh(true)
		else
			paint()
		end
	end

	connect(gui:GetPropertyChangedSignal("Enabled"), visibility)
	connect(tab:GetPropertyChangedSignal("Visible"), visibility)
	connect(tab.Destroying, controller.destroy)
	connect(options.Owner.Destroying, controller.destroy)
	connect(RunService.Heartbeat, function(dt)
		if not active() then
			return
		end

		elapsed += dt
		if elapsed < 0.1 then
			return
		end

		elapsed = 0
		controller.refresh()
	end)
	for mode, pill in pills do
		connect(pill.MouseButton1Click, function()
			if target or ambiguous or busy then
				return
			end

			bodyMode = mode
			clearDonor()
			paint()
			if input.Text ~= "" then
				controller.load(false)
			end
		end)
	end

	connect(panel.DefaultBodyRow.Toggle.MouseButton1Click, function()
		if busy then
			return
		end

		defaultBody = not defaultBody
		clearDonor()
		paint()
		if input.Text ~= "" then
			controller.load(false)
		end
	end)
	input.PlaceholderText = "Username / User ID"
	if not card.TargetName:FindFirstChildOfClass("UITextSizeConstraint") then
		const limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = card.TargetName.TextSize
		limit.MinTextSize = 7
		limit.Parent = card.TargetName
	end

	card.TargetName.TextWrapped = true
	card.TargetName.TextScaled = true
	if options.OnTheme then
		unsubscribeTheme = options.OnTheme(paint)
	end

	if active() then
		controller.refresh(true)
	else
		paint()
	end

	return controller
end

return Avatar
