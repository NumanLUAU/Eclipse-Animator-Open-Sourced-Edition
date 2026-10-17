--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Theme = require("Theme")
local Camera = require("CameraRig")
local Organization = require("Organization")
local Package = require("Package")
local Exporter = {}
local refs, current
local Selection = game:GetService("Selection")

function Exporter.errorMessage(message)
	for line in tostring(message):gmatch("[^\r\n]+") do
		local text = line
		repeat
			local stripped, count = text:gsub("^.-:%d+:%s*", "", 1)
			text = stripped
		until count == 0
		text = text:match("^%s*(.-)%s*$")
		if text ~= "" and text ~= "stack traceback:" and not text:match("^%[C%]") then
			return text
		end
	end

	return "Export could not finish. See Output for details."
end

function Exporter.close()
	if current then
		local old = current
		current = nil
		old:close()
	end
end

function Exporter.open()
	if current then
		return current
	end

	if not refs or not refs.Active() then
		return
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	local window = Tool.new(
		refs,
		"EclipseModuleExporter",
		"MODULE EXPORTER",
		Vector2.new(510, 466),
		false,

		function()
			current = nil
		end
	)
	current = window
	local body = Tool.make("Frame", window.frame, "Body", {
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 1, -56),
		BackgroundTransparency = 1,
		ZIndex = 11,
	})

	local function label(name, text, x, y, w, h)
		local object = Tool.label(body, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h))
		object.ZIndex = 12
		return object
	end

	local function button(name, text, x, y, w, fn)
		return Tool.button(body, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, 28), fn)
	end

	local function field(name, text, x, y, w)
		return Tool.field(body, name, text, UDim2.fromOffset(x, y), UDim2.fromOffset(w, 28))
	end

	local mode = "Button"
	local dependencies = {}
	local modeLabels = {}
	local relayout
	local popup
	local expanded = false
	label("Introduction", "Play this project in your game", 0, 0, 478, 24).TextSize = 16
	label("ModeLabel", "START WITH", 0, 32, 478, 18).TextTransparency = 0.4
	local descriptions = {
		Scripting = "Exports only a module so you, or your scripter can hook it to your systems.",
		Button = "Adds a game button to start or stop the cutscene for the player who clicks it.",
	}
	local description = label("ModeDescription", "", 0, 84, 478, 35)
	description.TextTransparency = 0.2
	local name = field("ExportName", refs.Name(), 148, 126, 330)
	label("NameLabel", "Export name", 0, 126, 135, 28)
	local trigger = field("Trigger", "Play cutscene", 148, 163, 330)
	local triggerLabel = label("TriggerLabel", "Button label", 0, 163, 135, 28)
	for i, item in { { "Button", "BUTTONS" }, { "Scripting", "SCRIPTING" } } do
		local b, l = button(item[1], item[2], (i - 1) * 243, 50, 235, function()
			if window.busy then
				return
			end

			mode = item[1]
			description.Text = "> " .. descriptions[mode]
			trigger.Parent.Visible = mode ~= "Scripting"
			triggerLabel.Visible = mode ~= "Scripting"
			triggerLabel.Text = "Button label"
			for id, row in modeLabels do
				row.TextTransparency = id == mode and 0 or 0.55
				row.Parent:SetAttribute("ThemeBg", id == mode and "MenuSel" or "TopBtn")
			end

			if relayout then
				relayout()
			end

			Theme.applyTree(body)
		end)
		modeLabels[item[1]] = l
	end

	description.Text = "> " .. descriptions[mode]
	for id, row in modeLabels do
		row.TextTransparency = id == mode and 0 or 0.55
		row.Parent:SetAttribute("ThemeBg", id == mode and "MenuSel" or "TopBtn")
	end

	label("CameraLabel", "Camera view", 0, 200, 135, 28)
	local cameras = { { Name = "Outside view", Mode = "Game" } }
	for _, rig in refs.State.getAllRigs() do
		if (Camera.isRig(rig) or rig:IsA("Camera")) and Organization.isEnabled(rig) then
			table.insert(cameras, { Name = rig.Name, Mode = "Authored", Rig = rig })
		end
	end

	local cameraIndex
	if #cameras == 1 then
		cameraIndex = 1
	elseif #cameras == 2 then
		cameraIndex = 2
	end

	local cameraHelp = label("CameraHelp", "", 148, 231, 330, 26)
	cameraHelp.TextTransparency = 0.35
	local cameraButton, cameraText

	local function refreshCamera()
		local choice = cameraIndex and cameras[cameraIndex]
		cameraText.Text = (
			choice and (choice.Mode == "Authored" and "Camera: " .. choice.Name or choice.Name)
			or "Select a camera\u{2026}"
		) .. "  \u{25be}"
		cameraHelp.Text = not choice and "Choose an animation camera or Outside view."
			or choice.Mode == "Game" and "Watch with the player\u{2019}s normal game camera."
			or "View through this animation camera."
	end

	cameraButton, cameraText = button("Camera", "", 148, 200, 330, function()
		if window.busy then
			return
		end

		if popup then
			popup:Destroy()
			popup = nil
			return
		end

		popup = Tool.make("ScrollingFrame", body, "CameraChoices", {
			Position = cameraButton.Position + UDim2.fromOffset(0, 30),
			Size = UDim2.fromOffset(330, math.min(180, #cameras * 30)),
			CanvasSize = UDim2.fromOffset(0, #cameras * 30),
			ScrollBarThickness = 4,
			BorderSizePixel = 0,
			ZIndex = 30,
			BackgroundColor3 = Theme.get("Pnl", Color3.fromRGB(20, 34, 40)),
		})
		for index, choice in cameras do
			local pick, text = Tool.button(
				popup,
				"Choice" .. index,
				choice.Mode == "Authored" and "Camera: " .. choice.Name or choice.Name,
				UDim2.fromOffset(0, (index - 1) * 30),
				UDim2.new(1, -4, 0, 30),

				function()
					cameraIndex = index
					refreshCamera()
					popup:Destroy()
					popup = nil
				end
			)
			pick.ZIndex = 31
			for _, child in pick:GetDescendants() do
				if child:IsA("GuiObject") then
					child.ZIndex = 32
				end
			end

			pick:SetAttribute("ThemeBg", index == cameraIndex and "MenuSel" or "Pnl")
		end

		Theme.applyTree(popup)
	end)
	refreshCamera()
	label("FrameLabel", "End frame", 0, 264, 135, 28)
	local last = field("EndFrame", math.max(1, timeline:GetMaxFrame()), 148, 264, 106)
	local timing = label("Timing", raw.FPS .. " FPS \u{00B7} from frame 0", 266, 264, 212, 28)
	timing.TextTransparency = 0.3
	local extraButton, extraLabel = button("ExtraFiles", "EXTRA FILES\u{2026}", 0, 302, 170, function()
		if window.busy then
			return
		end

		expanded = not expanded
		relayout()
	end
)
	local extras = Tool.make("Frame", body, "ExtraFilesPanel", {
		Position = UDim2.fromOffset(0, 338),
		Size = UDim2.fromOffset(478, 108),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 12,
	})
	local help = Tool.label(
		extras,
		"Help",
		"Optional: for event scripts that use files outside this animation. Select those objects in Studio\u{2019}s Explorer, then include them.",
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(478, 36)
	)
	help.TextTransparency = 0.3
	help.ZIndex = 12
	local dependencyText = Tool.label(
		extras,
		"IncludedFiles",
		"No extra files. Actors and referenced modules are included automatically.",
		UDim2.fromOffset(0, 74),
		UDim2.fromOffset(478, 32)
	)
	dependencyText.TextTransparency = 0.3
	dependencyText.ZIndex = 12
	Tool.button(
		extras,
		"Dependencies",
		"INCLUDE EXPLORER SELECTION",
		UDim2.fromOffset(0, 42),
		UDim2.fromOffset(280, 28),

		function()
			if window.busy then
				return
			end

			local added = 0
			for _, object in Selection:Get() do
				if
					not table.find(dependencies, object)
					and object ~= workspace
					and (
						object:IsDescendantOf(workspace)
						or object:IsDescendantOf(game:GetService("ReplicatedStorage"))
					)
				then
					table.insert(dependencies, object)
					added += 1
				end
			end

			local names = {}
			for _, object in dependencies do
				table.insert(names, object.Name)
			end

			dependencyText.Text = added == 0
					and "Select extra objects in Workspace or ReplicatedStorage in Explorer first."
				or (#names .. " included: " .. table.concat(names, ", "))
			extraLabel.Text = "EXTRA FILES (" .. #dependencies .. ")  \u{25b4}"
		end
	)
	Tool.button(
		extras,
		"ClearDependencies",
		"CLEAR",
		UDim2.fromOffset(290, 42),
		UDim2.fromOffset(90, 28),

		function()
			if not window.busy then
				table.clear(dependencies)
				dependencyText.Text =
					"No extra files. Actors and referenced modules are included automatically."
				extraLabel.Text = "EXTRA FILES  \u{25b4}"
			end
		end
	)
	local status = label(
		"Status",
		"Creates a new package in ReplicatedStorage \u{2192} EclipseCutscenes.",
		0,
		340,
		478,
		40
	)
	status.TextSize = 11
	local exportButton, exportText
	exportButton, exportText = button("Export", "EXPORT CUTSCENE", 295, 386, 183, function()
		if window.busy then
			return
		end

		local exportName = name.Text:match("^%s*(.-)%s*$")
		local finish = tonumber(last.Text)
		if exportName == "" or #exportName > 80 or exportName:find("[%c]") then
			status.Text = "Use an export name between 1 and 80 characters."
			return
		end

		if not finish or finish % 1 ~= 0 or finish < 1 then
			status.Text = "End frame must be a positive whole number."
			return
		end

		if mode == "Button" and not trigger.Text:find("%S") then
			status.Text = "Enter a label for the game button."
			return
		end

		if not cameraIndex then
			status.Text = "Choose a camera or Outside view before exporting."
			return
		end

		if timeline:IsExportLocked() then
			status.Text = "A module export is already running. Wait for it to finish."
			return
		end

		if refs.State.PhysicsSimulating then
			status.Text = "Wait for the physics simulation to finish before exporting."
			return
		end

		local existing = game:GetService("ReplicatedStorage"):FindFirstChild("EclipseCutscenes")
		if existing and existing:FindFirstChild(exportName) then
			status.Text = "That export already exists. Change the name to keep both versions."
			return
		end

		window.busy = true
		exportText.Text = "EXPORTING\u{2026}"
		if popup then
			popup:Destroy()
			popup = nil
		end

		local choice = cameras[cameraIndex]
		local options = {
			Name = exportName,
			LastFrame = finish,
			Mode = mode,
			CameraMode = choice.Mode,
			Camera = choice.Rig,
			ButtonLabel = trigger.Text,
			Dependencies = table.clone(dependencies),
			IsCancelled = function()
				return window.closed
			end,
		}
		local shield = Tool.make("TextButton", window.gui, "ExportInputShield", {
			Size = UDim2.fromScale(1, 1),
			Text = "",
			BackgroundTransparency = 1,
			Modal = true,
			Active = true,
			ZIndex = 1,
		})
		local Input = require("UserInputService")
		local captured = not Input.isCapturingKeys()
		if captured then
			Input.setKeyCapture(function(input)
				if input.KeyCode == Enum.KeyCode.Escape then
					Exporter.close()
				end
			end)
		end

		task.defer(function()
			local root, launcher
			local ok, message = xpcall(function()
				require("Bake").withExportLock(refs, options, function()
					root, launcher = Package.build(refs, options, function(text)
						if not window.closed then
							status.Text = text
						end
					end)
					assert(not window.closed, "Export cancelled because the window was closed")
					Package.install(root, launcher)
				end)
			end, debug.traceback)
			window.busy = false
			shield:Destroy()
			if captured then
				Input.setKeyCapture(nil)
			end

			if not ok then
				if root then
					root:Destroy()
				end

				if launcher then
					launcher:Destroy()
				end
			end

			if not window.closed then
				exportText.Text = "EXPORT CUTSCENE"
				status.Text = ok
						and ("Exported " .. exportName .. " to EclipseCutscenes. " .. (mode == "Scripting" and "Open its README for the scripting API." or "Press Play in Studio to try " .. "the game button" .. "."))
					or Exporter.errorMessage(message)
				if not ok then
					warn("Eclipse Module Exporter: " .. tostring(message))
				end
			end

			if ok then
				local previous = refs.State.ignoreSelectionChanged
				refs.State.ignoreSelectionChanged = true
				Selection:Set({ root })
				refs.State.ignoreSelectionChanged = previous
			end
		end)
	end)
	button("Close", "CLOSE", 0, 386, 100, Exporter.close)
	local positions = {}
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") and child.Position.Y.Offset >= 200 then
			positions[child] = child.Position
		end
	end

	relayout = function()
		if popup then
			popup:Destroy()
			popup = nil
		end

		local shift = mode == "Scripting" and -38 or 0
		for child, position in positions do
			local extra = (child == status or child == exportButton or child.Name == "Close")
					and expanded
					and 112
				or 0
			child.Position = position + UDim2.fromOffset(0, shift + extra)
		end

		extras.Visible = expanded
		extraLabel.Text = "EXTRA FILES"
			.. (#dependencies > 0 and " (" .. #dependencies .. ")" or "")
			.. (expanded and "  \u{25b4}" or "\u{2026}")
		local height = 466 + shift + (expanded and 112 or 0)
		local minimum = window.frame:FindFirstChildOfClass("UISizeConstraint")
		if minimum then
			minimum.MinSize = Vector2.new(510, height)
		end

		window.frame.Size = UDim2.fromOffset(510, height)
	end

	relayout()
	Theme.applyTree(body)
	return window
end

function Exporter.init(options)
	Exporter.close()
	refs = options
	options.Plugin.Unloading:Connect(Exporter.close)
	options.ScreenGui.Destroying:Once(Exporter.close)
end

return Exporter
