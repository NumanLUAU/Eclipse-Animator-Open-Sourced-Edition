--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Players = game:GetService("Players")
local Selection = game:GetService("Selection")
local Changes = game:GetService("ChangeHistoryService")
local Tool = require("Tool")
local Theme = require("Theme")
local History = require("History")
local Appearance = require("Appearance")
local RigPose = require("RigPose")
local Layout = require("Layout")
local Catalog = {}

local function clean(model)
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.Massless = true
		end
	end
end

const MAX_ASSETS = 10
const CLOTHING = { Shirt = "SHIRT", Pants = "PANTS", ShirtGraphic = "T-SHIRT" }

function Catalog.outfitId(value)
	const text = tostring(value or ""):match("^%s*(.-)%s*$")
	const id = tonumber(text:match("^%d+$"))
		or tonumber(text:match("[Oo]utfits?/(%d+)"))
		or tonumber(text:match("[?&][Oo]utfit[Ii]d=(%d+)"))
		or tonumber(text:match("[?&]id=(%d+)"))
	assert(id and id > 0 and id < 2 ^ 53, "Enter a valid outfit ID or link.")
	return id
end

function Catalog.outfit(id, kind)
	local description = Players:GetHumanoidDescriptionFromOutfitIdAsync(id)
	local ok, model =
		pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, description, kind)
	description:Destroy()
	if not ok then
		error(model, 0)
	end

	clean(model)
	return model
end

function Catalog.kind(item)
	if item:IsA("Accoutrement") then
		return "ACCESSORY"
	elseif CLOTHING[item.ClassName] then
		return CLOTHING[item.ClassName]
	elseif item.ClassName == "Decal" then
		return item:FindFirstChildOfClass("WrapTextureTransfer") and "MAKEUP" or "CLASSIC FACE"
	end

	return nil
end

function Catalog.asset()
	error("Loading accessories by ID is temporarily disabled.", 0)
end

function Catalog.displaced(rig, item)
	const kind = Catalog.kind(item)
	const found = {}
	if kind == "CLASSIC FACE" or kind == "MAKEUP" then
		const head = rig:FindFirstChild("Head")
		if head then
			for _, d in head:GetChildren() do
				if
					d ~= item
					and d.ClassName == "Decal"
					and Catalog.kind(d) == kind
					and (if kind == "MAKEUP" then d.Name == item.Name else d.Face == Enum.NormalId.Front)
				then
					table.insert(found, d)
				end
			end
		end
	elseif CLOTHING[item.ClassName] then
		for _, c in rig:GetChildren() do
			if c ~= item and c.ClassName == item.ClassName then
				table.insert(found, c)
			end
		end
	end

	return found
end

function Catalog.attach(rig, asset)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Select one rig")
	if asset:IsA("Accoutrement") then
		local handle = asset:FindFirstChild("Handle")
		assert(handle and handle:IsA("BasePart"), "This accessory has no handle")
		for _, part in asset:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		humanoid:AddAccessory(asset)
		if not handle:FindFirstChild("AccessoryWeld") then
			local mount = handle:FindFirstChildOfClass("Attachment")
			local socket
			if mount then
				for _, item in rig:GetDescendants() do
					if
						item:IsA("Attachment")
						and item.Name == mount.Name
						and item.Parent:IsA("BasePart")
						and not item:FindFirstAncestorWhichIsA("Accessory")
					then
						socket = item
						break
					end
				end

				assert(socket, "This accessory does not fit the selected rig")
			end

			local body = socket and socket.Parent or rig:FindFirstChild("Head")
			assert(body and body:IsA("BasePart"), "This rig has no accessory mount")
			local weld = Instance.new("Weld")
			weld.Name = "AccessoryWeld"
			weld.Part0 = handle
			weld.Part1 = body
			weld.C0 = mount and mount.CFrame or asset.AttachmentPoint
			weld.C1 = socket and socket.CFrame or CFrame.new(0, 0.5, 0)
			handle.CFrame = body.CFrame * weld.C1 * weld.C0:Inverse()
			weld.Parent = handle
		end
	elseif CLOTHING[asset.ClassName] then
		asset.Name = asset.ClassName
		asset.Parent = rig
	else
		const head = rig:FindFirstChild("Head")
		assert(head and head:IsA("BasePart"), "This rig has no head")
		if Catalog.kind(asset) == "CLASSIC FACE" then
			asset.Name = "face"
			asset.Face = Enum.NormalId.Front
		end

		asset.Parent = head
	end
end

function Catalog.init(options)
	local gui, frame, state = options.Gui, options.Frame, options.State
	local connections = {}
	local destroyed, busy, generation = false, false, 0
	local assets, preview, target, popup
	local tab = Tool.make("Frame", frame, "AccessoriesTab", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 78),
		Size = UDim2.fromOffset(464, 204),
		Visible = false,
	})
	local viewport = Tool.make("ViewportFrame", tab, "Preview", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(128, 166),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
	})
	viewport:SetAttribute("ThemeBg", "Pnl")
	Tool.make("UICorner", viewport, "Corner", { CornerRadius = UDim.new(0, 3) })
	local world = Instance.new("WorldModel", viewport)
	local rigLabel = Tool.label(
		tab,
		"RigName",
		"Select a rig",
		UDim2.fromOffset(0, 174),
		UDim2.fromOffset(128, 30)
	)
	rigLabel.TextXAlignment = Enum.TextXAlignment.Center
	rigLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Tool.label(
		tab,
		"Header",
		"ACCESSORY / FACE / CLOTHING / MAKEUP",
		UDim2.fromOffset(144, 0),
		UDim2.fromOffset(320, 18)
	)
	local input =
		Tool.field(tab, "AssetId", "", UDim2.fromOffset(144, 26), UDim2.fromOffset(230, 28))
	input.PlaceholderText = "Asset IDs / links, comma separated"
	local loadButton, loadLabel =
		Tool.button(tab, "Load", "LOAD", UDim2.fromOffset(382, 26), UDim2.fromOffset(82, 28))
	local name =
		Tool.label(tab, "AssetName", "", UDim2.fromOffset(144, 64), UDim2.fromOffset(320, 40))
	local kind =
		Tool.label(tab, "AssetType", "", UDim2.fromOffset(144, 108), UDim2.fromOffset(320, 20))
	local status =
		Tool.label(tab, "Status", "", UDim2.fromOffset(144, 134), UDim2.fromOffset(320, 34))
	name.TextWrapped = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextWrapped = true
	local insert =
		Tool.button(tab, "Insert", "INSERT", UDim2.fromOffset(144, 174), UDim2.fromOffset(320, 30))

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	local function resolve()
		return Appearance.resolve(Selection:Get(), state.Rig and state.Rig._selectedItems)
	end

	local function active()
		return not destroyed and gui.Enabled and tab.Visible
	end

	local function paint()
		loadLabel.Text = busy and "LOADING..." or "LOAD"
		Layout.enabled(loadButton, not busy)
		Layout.enabled(insert, not busy and target ~= nil and assets ~= nil and preview ~= nil)
	end

	local function release()
		if assets then
			for _, item in assets do
				item:Destroy()
			end

			assets = nil
		end
	end

	local function show()
		world:ClearAllChildren()
		preview = nil
		local rig, multiple = resolve()
		target = not multiple and rig or nil
		rigLabel.Text = target and target.Name or "Select one rig"
		if target then
			local model
			local ok, err = pcall(function()
				model = Appearance.clone(target)
				clean(model)
				RigPose.assemble(model)
				model:PivotTo(CFrame.identity)
				model.Parent = world
				if assets then
					for _, item in assets do
						const copy = item:Clone()
						for _, old in Catalog.displaced(model, copy) do
							old:Destroy()
						end

						Catalog.attach(model, copy)
					end
				end

				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
					end
				end

				options.FitCamera(viewport, model)
			end)
			if ok then
				preview = model
			else
				if model then
					model:Destroy()
				end

				status.Text = "Couldn't preview this item on this rig."
				warn("Eclipse accessory preview: " .. tostring(err))
			end
		end

		paint()
	end

	local controller = {}

	function controller.load()
		if not active() or busy then
			return
		end
		generation += 1
		local request, value = generation, input.Text
		busy = true
		release()
		name.Text, kind.Text, status.Text = "", "", "Loading from Roblox..."
		show()
		task.spawn(function()
			const ok, loaded, failures = pcall(Catalog.asset, value, function()
				return not destroyed and request == generation and active()
			end)
			if destroyed or request ~= generation or not active() then
				if ok and loaded then
					for _, item in loaded do
						item:Destroy()
					end
				end

				return
			end

			busy = false
			if ok then
				assets = loaded
				const names = {}
				for _, item in loaded do
					table.insert(names, item.Name)
				end

				name.Text = table.concat(names, ", ")
				kind.Text = #loaded == 1 and Catalog.kind(loaded[1]) or #loaded .. " ITEMS"
				status.Text = #failures > 0
						and string.format("Loaded %d of %d. %s", #loaded, #loaded + #failures, failures[1])
					or "Loaded. Select a rig to preview and insert."
				if #failures > 0 then
					warn("Eclipse accessories: " .. table.concat(failures, " | "))
				end

				show()
			else
				status.Text = tostring(loaded):gsub("^.-:%d+: ", ""):match("[^\n]+")
				paint()
			end
		end)
	end

	function controller.insert()
		if not active() or busy or not assets or not preview or resolve() ~= target then
			return
		end

		const rig = target
		const items, names = {}, {}
		for i, source in assets do
			items[i] = source:Clone()
			names[i] = source.Name
		end

		const title = table.concat(names, ", ")

		local inFile = false
		for _, r in state.getAllRigs() do
			if r == rig then
				inFile = true
				break
			end
		end

		local recording
		if not inFile then
			recording = Changes:TryBeginRecording("EclipseAccessory", "Insert accessory")
			if not recording then
				for _, item in items do
					item:Destroy()
				end

				return
			end
		end

		local displaced = {}
		local function undo()
			for i = #items, 1, -1 do
				items[i].Parent = nil
				for _, entry in displaced[i] or {} do
					entry[1].Parent = entry[2]
				end
			end

			displaced = {}
			state.currentProjectSaved = false
		end

		local function redo()
			displaced = {}
			for i, item in items do
				const moved = {}
				displaced[i] = moved
				for _, d in Catalog.displaced(rig, item) do
					table.insert(moved, { d, d.Parent })
					d.Parent = nil
				end

				Catalog.attach(rig, item)
			end

			state.currentProjectSaved = false
		end

		const ok, err = pcall(redo)
		if not ok then
			undo()
			for _, item in items do
				item:Destroy()
			end

			status.Text = (#items > 1 and "These items don't fit the selected rig: " or "This item doesn't fit the selected rig: ")
				.. (tostring(err):gsub("^.-:%d+: ", ""):match("[^\n]+") or "unknown error")
			warn(tostring(err))
		end

		if recording then
			Changes:FinishRecording(
				recording,
				ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
			)
		elseif ok then
			History.record(undo, redo, "Insert " .. title)
		end

		if ok then
			status.Text = "Inserted " .. title
			show()
		end
	end

	function controller.outfits()
		if popup then
			popup:close(true)
		end

		const window =
			Tool.new({ ScreenGui = gui }, "EclipseOutfits", "OUTFITS", Vector2.new(422, 288), false)
		popup = window
		const body = window.frame
		const field =
			Tool.field(body, "OutfitId", "", UDim2.fromOffset(16, 40), UDim2.fromOffset(390, 28))
		field.PlaceholderText = "Outfit ID / link"
		const thumbnail = Tool.make("ImageLabel", body, "Thumbnail", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 78),
			Size = UDim2.fromOffset(120, 120),
			Image = "",
		})
		const notice = Tool.label(
			body,
			"Notice",
			"Outfits load by Outfit ID. Paste the ID or link of a saved outfit, pick R6 or R15, then insert. Browsing a user's outfit list isn't available in the plugin.",
			UDim2.fromOffset(146, 78),
			UDim2.fromOffset(260, 80)
		)
		notice.TextYAlignment = Enum.TextYAlignment.Top
		const message =
			Tool.label(body, "Status", "", UDim2.fromOffset(146, 162), UDim2.fromOffset(260, 36))
		message.TextYAlignment = Enum.TextYAlignment.Top
		const r6 =
			Tool.button(body, "R6", "R6", UDim2.fromOffset(16, 208), UDim2.fromOffset(62, 28))
		const r15 =
			Tool.button(body, "R15", "R15", UDim2.fromOffset(86, 208), UDim2.fromOffset(62, 28))
		const add, addText = Tool.button(
			body,
			"Insert",
			"INSERT OUTFIT",
			UDim2.fromOffset(16, 248),
			UDim2.fromOffset(390, 28)
		)
		local mode, outfitId, adding = "R15", nil, false

		local function refresh()
			options.SetButtonSelected(r6, mode == "R6")
			options.SetButtonSelected(r15, mode == "R15")
			Layout.enabled(add, outfitId ~= nil and not adding)
			Layout.enabled(r6, not adding)
			Layout.enabled(r15, not adding)
			addText.Text = adding and "LOADING..." or "INSERT OUTFIT"
		end

		field:GetPropertyChangedSignal("Text"):Connect(function()
			const ok, id = pcall(Catalog.outfitId, field.Text)
			outfitId = ok and id or nil
			thumbnail.Image = outfitId
					and "rbxthumb://type=Outfit&id=" .. string.format("%.0f", outfitId) .. "&w=150&h=150"
				or ""
			message.Text = if outfitId or not field.Text:match("%S") then "" else "Enter a valid outfit ID or link."
			refresh()
		end)
		r6.Activated:Connect(function()
			if not adding then
				mode = "R6"
				refresh()
			end
		end)
		r15.Activated:Connect(function()
			if not adding then
				mode = "R15"
				refresh()
			end
		end)
		add.Activated:Connect(function()
			if adding or not outfitId then
				return
			end

			adding = true
			message.Text = ""
			refresh()
			const id, kind = outfitId, Enum.HumanoidRigType[mode]
			task.spawn(function()
				const ok, model = pcall(options.BuildOutfit or Catalog.outfit, id, kind)
				if window.closed or destroyed then
					if ok then
						model:Destroy()
					end

					return
				end

				adding = false
				if ok then
					model.Name = "Outfit " .. string.format("%.0f", id)
					options.PlaceModel(model, "Eclipse Insert Outfit")
					window:close()
				else
					const text = tostring(model)
					message.Text = if text:find("429", 1, true) or text:lower():find("rate limit", 1, true) or text:lower():find("too many requests", 1, true)
						then "Roblox is rate limiting outfit requests. Try again shortly."
						else "Couldn't load this outfit. Check the ID; the outfit must exist and be public."
					warn(text)
					refresh()
				end
			end)
		end)
		refresh()
		Theme.applyTree(body)
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

		if popup then
			popup:close(true)
		end

		release()
		world:ClearAllChildren()
	end

	connect(loadButton.Activated, controller.load)
	connect(input.FocusLost, function(enter)
		if enter then
			controller.load()
		end
	end)
	connect(input:GetPropertyChangedSignal("Text"), function()
		generation += 1
		busy = false
		release()
		name.Text = ""
		kind.Text = ""
		status.Text = ""
		paint()
	end)
	connect(insert.Activated, controller.insert)
	connect(frame.RigsTab.AvatarPanel.Outfits.Activated, controller.outfits)
	connect(Selection.SelectionChanged, function()
		if active() then
			if not busy then
				status.Text = ""
			end

			show()
		end
	end)
	local elapsed = 0
	connect(game:GetService("RunService").Heartbeat, function(dt)
		if not active() then
			return
		end

		elapsed += dt
		if elapsed < 0.2 then
			return
		end

		elapsed = 0
		if resolve() ~= target then
			if not busy then
				status.Text = ""
			end

			show()
		end
	end)

	local function visibility()
		generation += 1
		busy = false
		if active() then
			show()
		end

		if not gui.Enabled and popup then
			popup:close(true)
		end
	end

	connect(tab:GetPropertyChangedSignal("Visible"), visibility)
	connect(gui:GetPropertyChangedSignal("Enabled"), visibility)
	connect(options.Owner.Destroying, controller.destroy)
	connect(tab.Destroying, controller.destroy)
	Theme.applyTree(tab)
	paint()
	return controller
end

return Catalog
