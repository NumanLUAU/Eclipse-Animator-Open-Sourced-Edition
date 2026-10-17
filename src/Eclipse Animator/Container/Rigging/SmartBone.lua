--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Theme = require("Theme")
local Physics = require("Physics")
local Cache = require("Cache")
local Notice = require("Notification")
local Window = {}
local refs, host, busy, revision = nil, nil, false, 0
local connections = {}

function Window.close()
	revision += 1
	if host then
		local old = host
		host = nil
		old:close(true)
	end
end

function Window.destroy()
	Window.close()
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
end

function Window.open()
	if host or not refs or not refs.Active() then
		return
	end

	local state, timeline = refs.State, refs.State.Timeline
	if not timeline or timeline:IsExportLocked() or state.PhysicsSimulating then
		return
	end

	local rig = require("SelectedRig").resolve(state)
	if not rig or not rig:IsA("Model") then
		Notice.show("BONE DYNAMICS", "Select a rig in the timeline first", 4)
		return
	end

	local meshes = require("dynamics").meshes(rig)
	local dynamics = require("dynamics")
	local motors = dynamics.motors(rig)
	if #meshes == 0 and #motors == 0 then
		Notice.show("BONE DYNAMICS", "The selected rig has no Bone or Motor6D chains", 4)
		return
	end

	local raw = timeline:GetState()
	local chosen
	for _, clip in Physics.list() do
		if
			clip.rig == rig
			and (clip.settings.kind == "SmartBone" or clip.settings.kind == "BoneDynamics")
		then
			chosen = clip
		end
	end

	local session
	session = Tool.new(refs, "EclipseBoneDynamics", "BONE DYNAMICS", Vector2.new(460, 682), false, function()
		if host == session then
			host = nil
			revision += 1
		end
	end
)
	host = session
	local frame = session.frame
	Tool.label(
		frame,
		"Rig",
		rig.Name .. " · " .. #meshes .. " meshes · " .. #motors .. " joints",
		UDim2.fromOffset(14, 36),
		UDim2.fromOffset(432, 24)
	)
	local defaults = {
		first = 0,
		last = timeline:GetMaxFrame(),
		Damping = 0.2,
		Stiffness = 0.2,
		Inertia = 0.15,
		Elasticity = 3,
		AnchorDepth = 1,
		gravityY = -25,
		windX = 1,
		windY = 0,
		windZ = 0,
		WindSpeed = 1,
		WindStrength = 1,
		WindInfluence = 1,
		Radius = 0.08,
		RotationLimit = 180,
		substeps = 2,
		warmup = 30,
	}
	local fields = {
		{ "first", "Start frame", 0, 144000 },
		{ "last", "End frame", 1, 144000 },
		{ "Damping", "Damping", 0, 1 },
		{ "Stiffness", "Stiffness", 0, 1 },
		{ "Inertia", "Inertia", 0, 1 },
		{ "Elasticity", "Elasticity", 0, 100 },
		{ "AnchorDepth", "Anchor depth", 0, 50 },
		{ "gravityY", "Gravity Y", -1000, 1000 },
		{ "WindStrength", "Wind strength", 0, 100 },
		{ "WindSpeed", "Wind speed", 0, 100 },
		{ "windX", "Wind X", -1, 1 },
		{ "windY", "Wind Y", -1, 1 },
		{ "windZ", "Wind Z", -1, 1 },
		{ "WindInfluence", "Wind influence", 0, 10 },
		{ "Radius", "Collision radius", 0, 10 },
		{ "RotationLimit", "Rotation limit", 0, 180 },
		{ "substeps", "Substeps", 1, 8 },
		{ "warmup", "Warmup frames", 0, 600 },
	}
	local inputs = {}
	for i, row in fields do
		local col = (i - 1) % 2
		local y = 68 + math.floor((i - 1) / 2) * 34
		local x = 14 + col * 220
		Tool.label(
			frame,
			row[1] .. "Label",
			row[2],
			UDim2.fromOffset(x, y),
			UDim2.fromOffset(126, 26)
		)
		local value = chosen and chosen.settings[row[1]] or defaults[row[1]]
		if chosen then
			if row[1] == "gravityY" then
				value = chosen.settings.Gravity and chosen.settings.Gravity.Y or value
			end

			local axis = ({ windX = "X", windY = "Y", windZ = "Z" })[row[1]]
			if axis then
				value = chosen.settings.WindDirection and chosen.settings.WindDirection[axis]
					or value
			end
		end

		inputs[row[1]] =
			Tool.field(frame, row[1], value, UDim2.fromOffset(x + 128, y), UDim2.fromOffset(84, 26))
	end

	local selectionRoots = chosen and chosen.settings.selectionRoots or ""
	if not chosen then
		const ok, detected = pcall(dynamics.detect, rig)
		if ok and detected then
			selectionRoots = detected
		end
	end
	local loop = chosen and chosen.settings.loop == true or false
	local reverseMotion = chosen and chosen.settings.ReverseMotion == true or false
	local collisions = chosen and chosen.settings.collisions or false
	local meshSettings = chosen and chosen.settings.meshSettings or false
	local status = Tool.label(
		frame,
		"ProgressText",
		chosen and "Cached" or "Ready",
		UDim2.fromOffset(14, 378),
		UDim2.fromOffset(432, 18)
	)
	status.TextSize = 11
	local track = Tool.make("Frame", frame, "ProgressTrack", {
		Position = UDim2.fromOffset(14, 402),
		Size = UDim2.fromOffset(432, 4),
		BorderSizePixel = 0,
	})
	track:SetAttribute("ThemeBg", "TopBtn")
	local fill = Tool.make(
		"Frame",
		track,
		"ProgressFill",
		{ Size = UDim2.fromScale(chosen and 1 or 0, 1), BorderSizePixel = 0 }
	)
	fill:SetAttribute("ThemeBg", "Sel")

	local function progress(text, ratio)
		status.Text = text
		fill.Size = UDim2.fromScale(math.clamp(ratio or 0, 0, 1), 1)
	end

	local function checkbox(name, title, hint, x, value, changed, y)
		y = y or 420
		local button = Tool.make("TextButton", frame, name, {
			Text = "",
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(208, 24),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = 13,
		})
		Tool.label(button, "Label", title, UDim2.fromOffset(23, 0), UDim2.fromOffset(185, 24))
		local box = Tool.make("Frame", button, "Box", {
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
			ZIndex = 14,
		})
		box:SetAttribute("ThemeBg", "TopBtn")
		Tool.make("UIStroke", box, "Outline", { Thickness = 1 }):SetAttribute("ThemeStrk", "Strk")
		local mark = Tool.make("Frame", box, "Fill", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			ZIndex = 15,
			Visible = value,
		})
		mark:SetAttribute("ThemeBg", "Txt")
		for _, object in { box, mark } do
			Tool.make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, 2) })
		end

		local help = Tool.label(
			frame,
			name .. "Hint",
			hint,
			UDim2.fromOffset(x, y + 26),
			UDim2.fromOffset(208, 32)
		)
		help.TextSize = 10
		help.TextTransparency = 0.25
		if name == "Loop" then
			help.Size = UDim2.fromOffset(208, 48)
		end

		button.Activated:Connect(function()
			if not busy then
				value = not value
				mark.Visible = value
				changed(value)
			end
		end)
	end

	checkbox(
		"Collisions",
		"Scene collisions",
		"Lets bones collide with nearby parts.",
		14,
		collisions,

		function(value)
			collisions = value
		end
	)
	checkbox(
		"MeshSettings",
		"Use mesh settings",
		"Uses settings stored on the mesh instead of these values.",
		238,
		meshSettings,

		function(value)
			meshSettings = value
		end
	)
	checkbox(
		"Loop",
		"Loop",
		'loops seamlessly when the animation does as well instead of "restarting" when it goes back to frame 0',
		14,
		loop,

		function(value)
			loop = value
		end,
		480
	)
	checkbox("ReverseMotion", "Reverse motion", "inverts the overall motion", 238, reverseMotion, function(
		value
	)
		reverseMotion = value
	end, 480)
	local selectionButton, selectionText

	local function showSelection()
		local count = selectionRoots ~= "" and #game.HttpService:JSONDecode(selectionRoots) or 0
		selectionText.Text = count > 0 and ("SELECTED CHAINS: " .. count .. " · UPDATE")
			or "USE SELECTED CHAINS"
	end

	selectionButton, selectionText = Tool.button(
		frame,
		"Selection",
		"",
		UDim2.fromOffset(14, 558),
		UDim2.fromOffset(280, 26),

		function()
			if busy then
				return
			end

			local ok, value = pcall(dynamics.selection, rig, state)
			if ok then
				selectionRoots = value
				showSelection()
			else
				Notice.show("BONE DYNAMICS", tostring(value), 4)
			end
		end
	)
	Tool.button(
		frame,
		"AllChains",
		"ALL CHAINS",
		UDim2.fromOffset(302, 558),
		UDim2.fromOffset(144, 26),

		function()
			if not busy then
				selectionRoots = ""
				showSelection()
			end
		end
	)
	showSelection()
	table.insert(session.connections, game:GetService("Selection").SelectionChanged:Connect(function()
		if busy or chosen or host ~= session or session.closed then
			return
		end

		const ok, detected = pcall(dynamics.detect, rig)
		if ok and detected and detected ~= selectionRoots then
			selectionRoots = detected
			showSelection()
		end
	end))

	local function read()
		local settings = {
			ReverseMotion = reverseMotion,
			selectionRoots = selectionRoots,
			loop = loop,
			collisions = collisions,
			meshSettings = meshSettings,
			Seed = chosen and chosen.settings.Seed or 1,
		}
		for _, row in fields do
			local value = tonumber(inputs[row[1]].Text)
			assert(
				value and value == value and math.abs(value) < math.huge,
				row[2] .. " must be a number"
			)
			settings[row[1]] = math.clamp(value, row[3], row[4])
		end

		for _, id in { "first", "last", "AnchorDepth", "substeps", "warmup" } do
			settings[id] = math.floor(settings[id])
		end

		settings.Gravity = Vector3.new(0, settings.gravityY, 0)
		settings.WindDirection = Vector3.new(settings.windX, settings.windY, settings.windZ)
		return settings
	end

	local function notify(message)
		Notice.show("BONE DYNAMICS", message, 4)
	end

	local simulateText, bakeText
	local cancelable, activeBake = false, false

	local function showActions()
		if simulateText then
			simulateText.Text = cancelable and not activeBake and "CANCEL" or "SIMULATE"
		end

		if bakeText then
			bakeText.Text = cancelable and activeBake and "CANCEL" or "BAKE"
		end
	end

	local function resolveChosen()
		local fallback
		for _, clip in Physics.list() do
			if
				clip.rig == rig
				and (clip.settings.kind == "SmartBone" or clip.settings.kind == "BoneDynamics")
			then
				if chosen and clip.id == chosen.id then
					chosen = clip
					return
				end

				fallback = clip
			end
		end

		chosen = fallback
	end

	local function run(bake)
		if busy then
			if cancelable and activeBake == bake then
				revision += 1
				cancelable = false
				showActions()
			end

			return
		end

		resolveChosen()
		if state.PhysicsSimulating or raw.Playing then
			notify("Pause playback and finish the current operation first.")
			return
		end

		if bake and not chosen then
			notify("Simulate before baking.")
			return
		end

		local good, settings = pcall(read)
		if not good then
			notify(tostring(settings):match("^[^\n]+") or "Invalid settings")
			return
		end

		if bake and chosen then
			for k, v in settings do
				local expected = chosen.settings[k]
				if k == "loop" or k == "ReverseMotion" then
					expected = expected == true
				elseif k == "selectionRoots" then
					expected = expected or ""
				end

				if expected ~= v then
					notify("Settings changed. Simulate again before baking.")
					return
				end
			end
		end

		revision += 1
		local token = revision
		busy = true
		state.PhysicsSimulating = true
		activeBake = bake
		cancelable = true
		showActions()

		progress(bake and "Baking · 0%" or "Simulating · 0%", 0)
		task.spawn(function()
			local lastPercent = -1

			local function check(current, total)
				assert(
					host == session and not session.closed and revision == token,
					"simulation canceled"
				)
				local ratio = bake and (total and total > 0 and (current or 0) / total or 0)
					or ((current or settings.first) - settings.first)
						/ math.max(1, settings.last - settings.first)
				local percent = math.floor(math.clamp(ratio, 0, 1) * 100)
				if percent ~= lastPercent then
					lastPercent = percent
					progress((bake and "Baking · " or "Simulating · ") .. percent .. "%", ratio)
				end
			end

			local function committing()
				assert(
					host == session and not session.closed and revision == token,
					"simulation canceled"
				)
				cancelable = false
				showActions()
			end

			local ok, result = pcall(function()
				if bake then
					Physics.bake(chosen, check, committing)
				else
					return Physics.simulateSmartBones(rig, settings, check, chosen, committing)
				end
			end)
			busy = false
			state.PhysicsSimulating = false
			cancelable = false
			if host ~= session or session.closed then
				return
			end

			showActions()
			if ok then
				chosen = not bake and result or nil
				progress(bake and "Baked" or "Cached", 1)
			elseif revision == token then
				progress("Failed", 0)
				notify(tostring(result):match("^[^\n]+") or "Simulation failed.")
			else
				progress("Canceled", 0)
			end
		end)
	end

	local simulateButton
	simulateButton, simulateText = Tool.button(
		frame,
		"Simulate",
		"SIMULATE",
		UDim2.fromOffset(14, 596),
		UDim2.fromOffset(208, 30),

		function()
			run(false)
		end
	)
	local bakeButton
	bakeButton, bakeText = Tool.button(
		frame,
		"Bake",
		"BAKE",
		UDim2.fromOffset(238, 596),
		UDim2.fromOffset(208, 30),

		function()
			run(true)
		end
	)
	local preview = true
	Tool.button(
		frame,
		"Preview",
		"TOGGLE PREVIEW",
		UDim2.fromOffset(14, 636),
		UDim2.fromOffset(208, 30),

		function()
			if not busy then
				preview = not preview
				Physics.preview(preview)
				progress(preview and "Preview on" or "Preview off", chosen and 1 or 0)
			end
		end
	)
	Tool.button(
		frame,
		"Remove",
		"REMOVE CACHE",
		UDim2.fromOffset(238, 636),
		UDim2.fromOffset(208, 30),

		function()
			if busy then
				return
			end

			local ok, err = pcall(Physics.removeBoneDynamics, rig)
			if ok then
				chosen = nil
				progress("Ready", 0)
			else
				notify(tostring(err):match("^[^\n]+") or "Could not remove cache.")
			end
		end
	)
	Cache.preview(raw, true)
	Theme.applyTree(frame)
end

function Window.toggle()
	if host then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(options)
	Window.destroy()
	refs = options
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Window.close()
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Window.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Window.destroy))
end

return Window
