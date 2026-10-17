--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Behavior = require("Behavior")
local WindowFX = require("WindowFX")
local Motion = require("Motion")

local notificationFrame
local Theme = require("Theme")
local State = require("State")
local Notification = {}
local layer, container, dockContainer

local function host()
	local screen = notificationFrame:FindFirstAncestorWhichIsA("ScreenGui")
	if not screen then
		return notificationFrame.Parent
	end

	if not layer or not layer.Parent then
		layer = Instance.new("ScreenGui")
		layer.Name = "EclipseNotifications"
		layer.DisplayOrder = 2147483646
		layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		layer.ResetOnSpawn = false
		layer.IgnoreGuiInset = screen.IgnoreGuiInset
		layer.ScreenInsets = screen.ScreenInsets
		layer:SetAttribute("EclipseOwnedUI", true)
		layer.Parent = screen.Parent
		local scale = screen:FindFirstChildOfClass("UIScale")
		if scale then
			local copy = scale:Clone()
			copy.Parent = layer
			local changed = scale:GetPropertyChangedSignal("Scale"):Connect(function()
				copy.Scale = scale.Scale
			end)
			layer.Destroying:Once(function()
				changed:Disconnect()
			end)
		end

		screen.Destroying:Once(function()
			if layer then
				layer:Destroy()
				layer = nil
			end

			if dockContainer then
				dockContainer:Destroy()
				dockContainer = nil
			end
		end)
		Theme.addRoot(layer)
	end

	local widget = State.AnimatorDock and State.AnimatorDock.presentationWidget()
	local docked = widget and widget.Enabled
	local current = docked and dockContainer or container
	local parent = docked and widget or layer
	if not current or not Motion.isFloatingChildOf(current, parent) then
		if current then
			current:Destroy()
		end

		current = notificationFrame.Parent:Clone()
		for _, child in current:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		current.Name = "EclipseNotificationStack"
		current.BackgroundTransparency = 1
		current.ZIndex = 100000
		current.Visible = true
		current.Active = false
		current.Parent = parent
		if docked then
			dockContainer = current
			Theme.addRoot(current)
		else
			container = current
		end
	end

	return current
end

local active = {}
local closing = {}
local shownOnce = {}

function Notification.showOnce(header, description, duration, category)
	local key = header .. "\0" .. description
	if shownOnce[key] then
		return
	end

	local notice = Notification.show(header, description, duration, category)
	if notice then
		shownOnce[key] = true
	end

	return notice
end

function Notification.setNotificationFrame(frame)
	notificationFrame = frame
end

local function forget(notif)
	local index = table.find(active, notif)
	if index then
		table.remove(active, index)
	end

	closing[notif] = nil
	WindowFX.clear(notif)
end

function Notification.remove(notif)
	if not notif or not notif.Parent or closing[notif] then
		return
	end

	closing[notif] = true
	local dismiss = notif.Content.Buttons.Dismiss
	dismiss.Interactable = false
	WindowFX.shrink(notif, function()
		forget(notif)
		local slot = notif.Parent
		notif:Destroy()
		if slot and slot.Name == "NotificationSlot" then
			slot:Destroy()
		end
	end)
end

local noticePreferences = {
	["AXIS SPACE"] = "NotifyAxisSpace",
	["RIG ADDED"] = "NotifyRigAdded",
	["OBJECT ADDED"] = "NotifyRigAdded",
	["Animation imported"] = "NotifyImportSuccess",
	["ARMATURE ADDED"] = "NotifyImportSuccess",
	["SET UPDATED"] = "NotifyPivotChanges",
	["PIVOTS SAVED"] = "NotifyPivotChanges",
	["PIVOTS LOADED"] = "NotifyPivotChanges",
	["PIVOTS UPDATED"] = "NotifyPivotChanges",
	["PIVOT SET"] = "NotifyPivotChanges",
	["PIVOT RESET"] = "NotifyPivotChanges",
	["BLENDER CAMERA"] = "NotifyCameraTips",
}

function Notification.show(header, description, duration, category)
	local preference = category == "KeyframeAction" and "NotifyKeyframeActions"
		or noticePreferences[header]
	if preference and require("Preferences").get(preference) == false then
		return
	end

	if not notificationFrame or not notificationFrame.Parent then
		return
	end

	local notif = notificationFrame:Clone()
	local offset = Vector2.new(0.5, 0.5) - notif.AnchorPoint
	local size = notif.Size
	notif.Position += UDim2.new(
		size.X.Scale * offset.X,
		size.X.Offset * offset.X,
		size.Y.Scale * offset.Y,
		size.Y.Offset * offset.Y
	)
	notif.AnchorPoint = Vector2.new(0.5, 0.5)
	local information = notif.Content.Information.Container.VerticalContent
	information.Header.Header.Text = header
	information.Description.Text = description
	notif.Visible = true

	local slot = Instance.new("Frame")
	slot.Name = "NotificationSlot"
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Size = size
	slot.ZIndex = 100001
	slot.Parent = host()
	notif.Size = UDim2.new(1, 0, 0, size.Y.Offset)
	notif.Position = UDim2.fromScale(0.5, 0.5)
	notif.Parent = slot

	local function fit()
		if not notif.Parent or not slot.Parent then
			return
		end

		local animation = notif:FindFirstChildOfClass("UIScale")
		local scale = Motion.scale(notif) * (animation and animation.Scale or 1)
		local height = math.max(size.Y.Offset, notif.AbsoluteSize.Y / math.max(0.001, scale))
		if math.abs(slot.Size.Y.Offset - height) > 0.5 or slot.Size.Y.Scale ~= 0 then
			slot.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, height)
		end
	end

	local sizeChanged = notif:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local disposing = false
	slot.Destroying:Once(function()
		disposing = true
	end)
	notif.Destroying:Once(function()
		sizeChanged:Disconnect()
		if not disposing then
			disposing = true
			task.defer(function()
				if slot.Parent then
					slot:Destroy()
				end
			end)
		end
	end)
	task.defer(fit)
	notif.ZIndex = 100001
	Theme.applyTree(notif)
	table.insert(active, notif)
	notif.Destroying:Once(function()
		forget(notif)
	end)
	notif.Content.Buttons.Dismiss.MouseButton1Click:Connect(function()
		Notification.remove(notif)
	end)
	WindowFX.pop(notif)
	local lifetime = type(duration) == "number"
			and duration == duration
			and duration > 0
			and duration < math.huge
			and duration
		or Behavior.NotificationDuration
	task.delay(math.min(lifetime, (category == "GreasePencilFirstOpen" or category == "UpdateAvailable") and 7 or 5), function()
		Notification.remove(notif)
	end)
	return notif
end

return Notification
