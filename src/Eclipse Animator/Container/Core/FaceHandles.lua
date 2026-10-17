--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Tracks, Theme, Tool = require("Properties"), require("Theme"), require("Tool")
local Handles = {}
local refs, folder, connection
local rigs = {}
local clear
local groups = { "Brows", "Eyes", "Mouth", "Jaw", "Tongue", "Other" }

function Handles.group(motor)
	local name = motor.Definition.label:lower()
	if name:find("brow") or name:find("corrugator") then return "Brows" end
	if name:find("eye") or name:find("lid") then return "Eyes" end
	if name:find("tongue") then return "Tongue" end
	if name:find("jaw") or name:find("chin") then return "Jaw" end
	if name:find("lip") or name:find("mouth") or name:find("smile") or name:find("frown") or name:find("pucker") or name:find("dimpler") then return "Mouth" end
	return "Other"
end

function Handles.enabled(rig)
	local found = false
	for _, motor in Tracks.list(rig, true) do
		if motor.Definition.facial then
			found = true
			if motor:GetAttribute("EclipseDisabled") or not require("Organization").getOwnEnabled(motor.Part1, true) then return false end
		end
	end
	return found
end

function Handles.setEnabled(rig, value)
	local keys = {}
	for _, motor in Tracks.list(rig, true) do if motor.Definition.facial then table.insert(keys, motor.Part1) end end
	require("Organization").setOwnEnabled(keys, value)
end

function Handles.visible(rig) return rig:GetAttribute("EclipseFaceHandlesVisible") ~= false end
function Handles.setVisible(rig, value)
	rig:SetAttribute("EclipseFaceHandlesVisible", value)
	if not value then clear(rig, false) else Handles.refresh() end
end

function Handles.select(motor)
	if not refs or not motor.Parent or require("BlenderEdit").blocked() then return false end
	for _, item in refs.State.Rig._orderedItems or {} do
		if item:fetchMotor() == motor then
			require("ViewportSelection").apply({ item }, "replace")
			if refs.State.PoseSliders then refs.State.PoseSliders.focus(motor) end
			return true
		end
	end
	return false
end

function Handles.hit(point)
	if typeof(point) ~= "Vector2" then return end
	for _, record in rigs do
		if not record.gui.Enabled then continue end
		for _, handle in record.handles do
			local button = handle.visual
			local p, size = button.AbsolutePosition, button.AbsoluteSize
			local a, b = record.list.AbsolutePosition, record.list.AbsoluteSize
			if button.Visible and point.X >= p.X and point.X <= p.X + size.X and point.Y >= p.Y and point.Y <= p.Y + size.Y and point.Y >= a.Y and point.Y <= a.Y + b.Y then return handle end
		end
	end
end

function Handles.input() return false end

clear = function(rig, immediate)
	local record = rigs[rig]
	if record then rigs[rig] = nil record.window:close(immediate ~= false) end
end

function Handles.chooseGroup(rig, group)
	local record = rigs[rig]
	if not record or not table.find(groups, group) then return false end
	record.group = group
	for _, handle in record.handles do handle.visual.Visible = Handles.group(handle.motor) == group end
	for name, button in record.buttons do button:SetAttribute("ThemeBg", name == group and "MenuSel" or "TopBtn") end
	record.list.CanvasPosition = Vector2.zero
	Theme.applyTree(record.gui)
	return true
end

function Handles.refresh()
	if not refs or not refs.State.Rig then return end
	local active = refs.Active() and not refs.State.PresentationHidden
	local item = refs.State.Rig._lastClickedItem
	local selected = item and item:fetchMotor()
	local present = {}
	for _, rig in refs.State.getAllRigs() do
		present[rig] = true
		local face = Tracks.faceControls(rig)
		local head = face and face:FindFirstAncestorWhichIsA("BasePart")
		local record = rigs[rig]
		if record and (not active or not Handles.visible(rig) or record.face ~= face or record.head ~= head) then clear(rig) record = nil end
		if head and not record and active and Handles.visible(rig) then
			local window = Tool.new(refs, "DynamicHeadControls", "FACE CONTROLS", Vector2.new(260, 350), false, function()
                if rigs[rig] then
                    rigs[rig] = nil
                    rig:SetAttribute("EclipseFaceHandlesVisible", false)
                end
            end, {BeforeOpen = function(panel, gui)
                local animator = refs.AnimatorFrame
                if not animator then return end
                local scale = require("Motion").scale(panel)
                local origin = panel.Parent:IsA("GuiBase2d") and panel.Parent.AbsolutePosition or Vector2.zero
                local position, bounds = animator.AbsolutePosition, animator.AbsoluteSize
                local size = panel.AbsoluteSize
                local viewport = gui.AbsoluteSize
                local x, y = position.X + bounds.X + 12 * scale, position.Y
                if x + size.X > viewport.X then x = position.X - size.X - 12 * scale end
                if x < 0 then x, y = position.X, position.Y - size.Y - 12 * scale end
                x = math.clamp(x, 8, math.max(8, viewport.X - size.X - 8))
                y = math.clamp(y, 8, math.max(8, viewport.Y - size.Y - 8))
                panel.AnchorPoint = Vector2.new(0.5, 0.5)
                panel.Position = UDim2.fromOffset((x + size.X * 0.5 - origin.X) / scale, (y + size.Y * 0.5 - origin.Y) / scale)
            end})
            local gui, panel = window.gui, window.frame
			local divider = Tool.make("Frame", panel, "Divider", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.new(1, -12, 0, 1), BorderSizePixel = 0})
			divider:SetAttribute("ThemeBg", "Div")
			local list = Tool.make("ScrollingFrame", panel, "Expressions", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 54), Size = UDim2.new(1, -12, 1, -120), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y })
			Tool.make("UIListLayout", list, "Rows", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
			record = { window = window, face = face, head = head, gui = gui, list = list, handles = {}, buttons = {} }
			rigs[rig] = record
			for index, group in groups do
				local b = Tool.button(panel, group, group, UDim2.new((index - 1) % 2 * 0.5, (index - 1) % 2 == 0 and 6 or 3, 0, 29 + math.floor((index - 1) / 2) * 26), UDim2.new(0.5, -9, 0, 23), function() Handles.chooseGroup(rig, group) end)
				record.buttons[group] = b
			end
			for _, motor in Tracks.list(rig) do
				if not motor.Definition.facial then continue end
				local b, text = Tool.button(list, motor.Definition.label, motor.Definition.label:gsub("(%l)(%u)", "%1 %2"), UDim2.new(), UDim2.new(1, -6, 0, 24), function() Handles.select(motor) end)
                text.TextXAlignment = Enum.TextXAlignment.Left
                text.AnchorPoint = Vector2.new(0.5, 0.5)
                text.Position = UDim2.new(0.5, 5, 0.5, 0)
                text.Size = UDim2.new(1, -22, 1, 0)
                b.BackgroundTransparency = 1
                b:SetAttribute("ThemeBgTransparency", 1)
                local accent = Tool.make("Frame", b, "SelectionMark", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(2, 14), BorderSizePixel = 0, Visible = false})
                accent:SetAttribute("ThemeBg", "Txt")
                local line = Tool.make("Frame", b, "Divider", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -10, 0, 1), BorderSizePixel = 0, BackgroundTransparency = 0.65})
                line:SetAttribute("ThemeBg", "Div")
                line:SetAttribute("ThemeBgTransparency", 0.65)
				b.LayoutOrder = #record.handles
				table.insert(record.handles, { motor = motor, visual = b })
			end
			Handles.chooseGroup(rig, "Eyes")
			require("UserInputService").attachSurface(gui, { panel })
			if refs.RefreshStructure and not refs.State.LoadingProject then
				local found = false
				for _, row in refs.State.Rig._orderedItems or {} do if row.linkedRigInstance == face then found = true break end end
				if not found then task.defer(refs.RefreshStructure) end
			end
		end
		if record then
			record.gui.Enabled = active and Handles.visible(rig)
			if record.selected ~= selected then
				record.selected = selected
				for _, handle in record.handles do
					local chosen = handle.motor == selected
					if chosen then Handles.chooseGroup(rig, Handles.group(handle.motor)) end
					handle.visual:SetAttribute("ThemeBg", chosen and "MenuSel" or "TopBtn")
					handle.visual:SetAttribute("ThemeBgTransparency", chosen and 0.15 or 1)
					handle.visual.SelectionMark.Visible = chosen
					require("WindowFX").setRestingProperty(handle.visual, "BackgroundTransparency", chosen and 0.15 or 1)
				end
				Theme.applyTree(record.gui)
			end
		end
	end
	for rig in rigs do if not present[rig] then clear(rig) end end
end

function Handles.destroy()
	if connection then connection:Disconnect() connection = nil end
	for rig in rigs do clear(rig) end
	if folder then folder:Destroy() folder = nil end
	table.clear(rigs)
end

function Handles.init(options)
	Handles.destroy()
	refs = options
	refs.State.FaceHandles = Handles
	folder = Instance.new("Folder")
	folder.Name = "EclipseDynamicHeadHandles"
	folder.Parent = game:GetService("CoreGui")
	local elapsed = 0
	connection = game:GetService("RunService").Heartbeat:Connect(function(dt) elapsed += dt if elapsed >= 0.05 then elapsed = 0 Handles.refresh() end end)
	options.Plugin.Unloading:Once(Handles.destroy)
	options.ScreenGui.Destroying:Once(Handles.destroy)
end

return Handles
