--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local Mode = require("cache")
local IK = require("LimbIK")
local Tool = require("Tool")
local Theme = require("Theme")
local Panel = {}
local window
local rowCache = setmetatable({}, { __mode = "k" })

function Panel.selection()
	local rigModule = State.Rig
	if not rigModule then
		return
	end

	local bone = State.Axis and State.Axis:GetSelectedBone()
	local rig = State.currentRig
	local source = bone and bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
	if source and source.Value then
		rig = source.Value
	end

	local part = bone and rig and rigModule:GetPartFromBone(rig, bone)
	local motor = part and rigModule:GetMotorForPart(rig, part)
	local cached = motor and rowCache[motor]
	local row = cached
			and cached.rigModule == rigModule
			and cached.row.uiElement
			and cached.row.uiElement.Parent
			and cached.row
		or nil
	if not row and motor then
		for _, candidate in rigModule._orderedItems or {} do
			if
				candidate.itemKind ~= "channel"
				and candidate.fetchMotor
				and candidate:fetchMotor() == motor
			then
				row = candidate
				rowCache[motor] = { rigModule = rigModule, row = row }
				break
			end
		end
	end

	if not motor then
		local selected = rigModule._lastClickedItem
		if selected and (rigModule._selectedItems or {})[selected] then
			row = selected.parentBoneItem or selected
			motor = row.fetchMotor and row:fetchMotor()
			rig = row.grandpa and row.grandpa.linkedRigInstance or rig
		end
	end

	return motor, rig, row
end

function Panel.close()
	if window then
		window:close(true)
	end
end

function Panel.open()
	Panel.close()
	local timeline = State.Timeline
	local UI = require("UI")
	if
		not timeline
		or not UI.EclipseGUI
		or not UI.AnimatorFrame
		or not UI.AnimatorFrame.Visible
		or not UI.EclipseGUI.Enabled
	then
		return
	end

	local refs = { ScreenGui = UI.EclipseGUI, Plugin = require("ProjectData").getPlugin() }
	local session
	session = Tool.new(refs, "EclipseBoneSettings", "BONE SETTINGS", Vector2.new(350, 284), false, function()
		if window == session then
			window = nil
		end
	end
)
	window = session
	local title = Tool.label(
		session.frame,
		"SelectedBone",
		"Select a bone",
		UDim2.fromOffset(16, 42),
		UDim2.fromOffset(318, 28)
	)
	local controls = {}
	local selection = Panel.selection

	local function alive()
		return State.Timeline == timeline
			and refs.ScreenGui.Parent ~= nil
			and refs.ScreenGui.Enabled
			and UI.AnimatorFrame.Parent ~= nil
			and UI.AnimatorFrame.Visible
			and (not UI.PluginActiveBool or UI.PluginActiveBool.Value)
	end

	local refresh

	local function checkbox(name, text, action)
		local button = Tool.make("TextButton", session.frame, name, {
			Text = "",
			Size = UDim2.fromOffset(318, 26),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = session.frame.ZIndex + 3,
		})
		local label =
			Tool.label(button, "Title", text, UDim2.fromOffset(26, 0), UDim2.fromOffset(292, 26))
		label.ZIndex = button.ZIndex + 1
		local box = Tool.make("Frame", button, "Check", {
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = button.ZIndex + 1,
		})
		box:SetAttribute("ThemeBg", "TopBtn")
		local fill = Tool.make("Frame", box, "Fill", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			ZIndex = box.ZIndex + 1,
		})
		fill:SetAttribute("ThemeBg", "Txt")
		for _, object in { box, fill } do
			Tool.make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, 2) })
		end

		local border = Tool.make("UIStroke", box, "Outline", { Thickness = 1 })
		border:SetAttribute("ThemeStrk", "Strk")
		local control =
			{ button = button, label = label, fill = fill, border = border, enabled = false }
		controls[name] = control
		table.insert(
			session.connections,
			button.Activated:Connect(function()
				if not alive() then
					Panel.close()
					return
				end

				if timeline:IsExportLocked() or require("BlenderEdit").blocked() then
					return
				end

				refresh()
				if not control.enabled then
					return
				end

				local motor, rig, row = selection()
				if motor and rig then
					action(motor, rig, row)
					refresh()
				end
			end)
		)
		return button
	end

	local function chainFor(motor, rig)
		if not motor or not rig then
			return
		end

		local owner = typeof(motor) == "table" and motor.IsEclipseR6Control and motor.Owner or motor
		local entry = IK.getRig(rig)
		return entry and entry.members[owner]
	end

	checkbox("TrackEnabled", "Track Enabled", function(motor, rig, row)
		local disabled = not row:isDisabled()
		row:setDisabled(disabled, false)
	end)
	checkbox("MotionPath", "Motion Path", function(_, _, row)
		row:setMotionPath(not row:isMotionPathEnabled(), false)
	end)
	checkbox("InverseKinematics", "Inverse Kinematics (IK)", function(motor, rig)
		local chain = chainFor(motor, rig)
		if chain then
			timeline:SwitchIKAtCurrentTime(chain.owner, rig)
		end
	end)
	local parent = checkbox("FollowParent", "Follow Parent (P / W)", function(motor, rig)
		timeline:SwitchParentingAtCurrentTime(motor, rig)
	end)
	table.insert(
		session.connections,
		parent.MouseButton2Click:Connect(function()
			if not alive() or timeline:IsExportLocked() or require("BlenderEdit").blocked() then
				return
			end

			local motor, rig = selection()
			if motor and controls.FollowParent.button.Visible and controls.FollowParent.enabled then
				require("Targets").openChild(motor, rig)
			end
		end)
	)
	checkbox("InheritRotation", "Inherit Rotation (IR)", function(motor, rig)
		timeline:SwitchHeadStabilizerAtCurrentTime(motor, rig)
	end)
	checkbox("PoleFollowsIK", "Pole Follows IK", function(motor, rig)
		local chain = chainFor(motor, rig)
		if chain then
			timeline:SwitchPoleFollowAtCurrentTime(chain.owner, rig)
		end
	end)
	refresh = function()
		local motor, rig, row = selection()
		local time = timeline:GetState().CurrentTime
		local chain = chainFor(motor, rig)
		local disabled = motor and motor:GetAttribute("EclipseDisabled") == true
		local helper = motor and typeof(motor) == "table" and motor.IsEclipseIKHandle
		local rotation = Mode.isEligible(motor)
			and not (typeof(motor) == "table" and motor.IsEclipseR6Control)
		local parenting = motor ~= nil and not helper and (not row or row.parentingButton ~= nil)
		local ik = chain and IK.isEnabled(chain.owner, time)
		local follow = ik and chain.kind == "R15" and IK.state(chain, time)
		title.Text = motor
				and (row and row.linkedRigInstance and row.linkedRigInstance.Name or motor.Part1.Name)
			or "Select a bone"
		local y = 78

		local function paint(name, visible, checked, enabled)
			local c = controls[name]
			c.button.Visible = visible == true
			c.enabled = visible == true and enabled == true
			c.button.Active = c.enabled
			c.button.Selectable = c.enabled
			c.fill.Visible = checked == true
			c.label.TextTransparency = c.enabled and 0 or 0.55
			c.fill.BackgroundTransparency = c.enabled and 0 or 0.55
			c.border.Transparency = c.enabled and 0 or 0.55
			if visible then
				c.button.Position = UDim2.fromOffset(16, y)
				y += 32
			end
		end

		paint(
			"TrackEnabled",
			row ~= nil and row.disableButton ~= nil,
			row ~= nil and not row:isDisabled(),
			true
		)
		paint(
			"MotionPath",
			row ~= nil and row.motionPathButton ~= nil,
			row ~= nil and row:isMotionPathEnabled(),
			true
		)
		paint(
			"InverseKinematics",
			chain ~= nil,
			ik == true,
			not disabled and chain ~= nil and not chain.owner:GetAttribute("EclipseDisabled")
		)
		paint(
			"FollowParent",
			parenting,
			parenting and timeline:IsParentedAtTime(motor, time),
			not disabled and (not rotation or Mode.inherits(motor, time))
		)
		paint(
			"InheritRotation",
			rotation == true,
			rotation and Mode.inherits(motor, time),
			not disabled
		)
		paint(
			"PoleFollowsIK",
			chain ~= nil and chain.kind == "R15",
			follow and follow.poleFollowsTarget == true,
			not disabled and follow ~= nil and follow ~= false
		)
		local height = math.max(110, y + 10)
		local minimum = session.frame:FindFirstChild("MinimumSize")
		if minimum then
			minimum.MinSize = Vector2.new(350, height)
		end

		session.frame.Size = UDim2.fromOffset(350, height)
	end

	local function closeWhenHidden()
		if not alive() then
			session:close(true)
		end
	end

	for _, pair in { { refs.ScreenGui, "Enabled" }, { UI.AnimatorFrame, "Visible" } } do
		table.insert(
			session.connections,
			pair[1]:GetPropertyChangedSignal(pair[2]):Connect(closeWhenHidden)
		)
	end

	if UI.PluginActiveBool then
		table.insert(session.connections, UI.PluginActiveBool.Changed:Connect(closeWhenHidden))
	end

	if UI.ClosingEvent then
		table.insert(
			session.connections,
			UI.ClosingEvent.Event:Connect(function()
				session:close(true)
			end)
		)
	end

	table.insert(
		session.connections,
		refs.ScreenGui.Destroying:Connect(function()
			session:close(true)
		end)
	)
	local elapsed = 0
	table.insert(
		session.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			if not alive() then
				session:close(true)
				return
			end

			elapsed += dt
			if elapsed < 0.15 then
				return
			end

			elapsed = 0
			refresh()
		end)
	)
	refresh()
	Theme.applyTree(session.frame)
end

return Panel
