--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local TweenService = game:GetService("TweenService")

local OPEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FADE_IN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_FADE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local CLOSE_SCALE = 0.95

local WindowFX = {}

local activeTweens = {}
local batchFades = {}
local fadeCache = {}
local fadeIndex = setmetatable({}, { __mode = "k" })
local operations = setmetatable({}, { __mode = "k" })

local function cancelActive(frame)
	local batch = batchFades[frame]
	if batch then
		batchFades[frame] = nil
		batch.connection:Disconnect()
		for _, target in batch.targets do
			if target.batch == batch then
				target.batch = nil
			end
		end

		batch.value:Destroy()
	end

	if activeTweens[frame] then
		for _, t in ipairs(activeTweens[frame]) do
			t:Cancel()
		end
	end

	activeTweens[frame] = {}
end

local function track(frame, tween)
	table.insert(activeTweens[frame], tween)
	tween:Play()
end

local function getScale(frame)
	local s = frame:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "EclipseWindowScale"
		s.Parent = frame
	end

	return s
end

local function considerFadeTarget(targets, inst)
	if inst:IsA("GuiObject") and inst.BackgroundTransparency < 1 then
		table.insert(
			targets,
			{ inst = inst, prop = "BackgroundTransparency", value = inst.BackgroundTransparency }
		)
	end

	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") or inst:IsA("ViewportFrame") then
		if inst.ImageTransparency < 1 and not inst:GetAttribute("EclipseGifManaged") then
			table.insert(
				targets,
				{ inst = inst, prop = "ImageTransparency", value = inst.ImageTransparency }
			)
		end
	end

	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		if inst.TextTransparency < 1 then
			table.insert(
				targets,
				{ inst = inst, prop = "TextTransparency", value = inst.TextTransparency }
			)
		end
	end

	if inst:IsA("UIStroke") then
		if inst.Transparency < 1 then
			table.insert(targets, { inst = inst, prop = "Transparency", value = inst.Transparency })
		end
	end

	if inst:IsA("ScrollingFrame") then
		if inst.ScrollBarImageTransparency < 1 then
			table.insert(targets, {
				inst = inst,
				prop = "ScrollBarImageTransparency",
				value = inst.ScrollBarImageTransparency,
			})
		end
	end
end

local function collectFadeTargets(frame)
	if fadeCache[frame] then
		return fadeCache[frame]
	end

	local targets = {}
	considerFadeTarget(targets, frame)
	for _, inst in ipairs(frame:GetDescendants()) do
		local visible, ancestor = true, inst
		while ancestor and ancestor ~= frame do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				visible = false
				break
			end

			ancestor = ancestor.Parent
		end

		if visible then
			considerFadeTarget(targets, inst)
		end
	end

	fadeCache[frame] = targets
	for _, target in targets do
		target.frame = frame
		local byProperty = fadeIndex[target.inst] or {}
		fadeIndex[target.inst] = byProperty
		local entries = byProperty[target.prop] or {}
		byProperty[target.prop] = entries
		entries[target] = true
	end

	return targets
end

local function restoreFade(frame)
	local targets = fadeCache[frame]
	if not targets then
		return
	end

	fadeCache[frame] = nil
	for _, t in ipairs(targets) do
		local byProperty = fadeIndex[t.inst]
		local entries = byProperty and byProperty[t.prop]
		if entries then
			entries[t] = nil
			if not next(entries) then
				byProperty[t.prop] = nil
			end

			if not next(byProperty) then
				fadeIndex[t.inst] = nil
			end
		end

		pcall(function()
			t.inst[t.prop] = t.value
		end)
	end
end

function WindowFX.setRestingProperty(object, property, value)
	local displayed = value
	local byProperty = fadeIndex[object]
	for target in byProperty and byProperty[property] or {} do
		target.value = value
		if target.batch then
			displayed = value + (1 - value) * target.batch.value.Value
		end

		if target.tween then
			target.tween:Cancel()
		end
	end

	if object[property] ~= displayed then
		object[property] = displayed
	end
end

local function batchFade(frame, info, from, to)
	local value = Instance.new("NumberValue")
	value.Value = from
	local batch = { value = value, targets = collectFadeTargets(frame) }

	local function apply()
		local alpha = value.Value
		for _, target in batch.targets do
			if target.inst.Parent then
				target.inst[target.prop] = target.value + (1 - target.value) * alpha
			end
		end
	end

	for _, target in batch.targets do
		target.batch = batch
	end

	batch.connection = value.Changed:Connect(apply)
	batchFades[frame] = batch
	apply()
	local tween = TweenService:Create(value, info, { Value = to })
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and batchFades[frame] == batch then
			apply()
			batch.connection:Disconnect()
			for _, target in batch.targets do
				if target.batch == batch then
					target.batch = nil
				end
			end

			batchFades[frame] = nil
			value:Destroy()
		end
	end)
	track(frame, tween)
end

function WindowFX.pop(frame, scaleOnly)
	if not frame then
		return
	end

	require("Motion").watchFloatingGui(frame)
	cancelActive(frame)
	local operation = {}
	operations[frame] = operation
	frame:SetAttribute("EclipseWindowClosing", nil)

	local s = getScale(frame)
	s.Scale = 0.93
	local scaleTween = TweenService:Create(s, OPEN_INFO, { Scale = 1 })
	scaleTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			restoreFade(frame)
		end
	end)
	track(frame, scaleTween)
	if scaleOnly == true then
		return
	end

	if scaleOnly == "batch" then
		batchFade(frame, FADE_IN_INFO, 1, 0)
	elseif frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		track(frame, TweenService:Create(frame, FADE_IN_INFO, { GroupTransparency = 0 }))
	else
		local targets = collectFadeTargets(frame)
		for _, t in ipairs(targets) do
			t.inst[t.prop] = 1
			t.tween = TweenService:Create(t.inst, FADE_IN_INFO, { [t.prop] = t.value })
			track(frame, t.tween)
		end
	end
end

function WindowFX.shrink(frame, done, scaleOnly)
	if not frame then
		if done then
			done()
		end

		return
	end

	local fadeFrom = batchFades[frame] and batchFades[frame].value.Value or 0
	cancelActive(frame)
	local operation = {}
	operations[frame] = operation
	frame:SetAttribute("EclipseWindowClosing", true)
	local s = getScale(frame)
	local scaleTween = TweenService:Create(s, CLOSE_INFO, { Scale = CLOSE_SCALE })
	local finished = false

	local function finish()
		if finished or operations[frame] ~= operation then
			return
		end

		finished = true
		operations[frame] = nil
		cancelActive(frame)
		s.Scale = 1
		restoreFade(frame)
		frame:SetAttribute("EclipseWindowClosing", nil)
		activeTweens[frame] = nil

		if done then
			done()
		else
			frame.Visible = false
		end
	end

	scaleTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			finish()
		end
	end)
	if scaleOnly ~= true then
		if scaleOnly == "batch" then
			batchFade(frame, CLOSE_FADE_INFO, fadeFrom, 1)
		elseif frame:IsA("CanvasGroup") then
			track(frame, TweenService:Create(frame, CLOSE_FADE_INFO, { GroupTransparency = 1 }))
		else
			for _, t in collectFadeTargets(frame) do
				t.tween = TweenService:Create(t.inst, CLOSE_FADE_INFO, { [t.prop] = 1 })
				track(frame, t.tween)
			end
		end
	end

	track(frame, scaleTween)

	task.delay(CLOSE_INFO.Time + 0.05, finish)
end

function WindowFX.clear(frame)
	operations[frame] = nil
	if frame then
		frame:SetAttribute("EclipseWindowClosing", nil)
	end

	cancelActive(frame)
	restoreFade(frame)
	activeTweens[frame] = nil
	fadeCache[frame] = nil
end

function WindowFX.recoverClosingTools(parent)
	for _, gui in parent:GetChildren() do
		if gui:IsA("ScreenGui") and gui:GetAttribute("EclipseOwnedUI") == true then
			local frame = gui:FindFirstChild("Window", true)
			if
				frame
				and frame:IsA("GuiObject")
				and frame:GetAttribute("EclipseWindowClosing") == true
			then
				local changed = false
				local connection = frame
					:GetAttributeChangedSignal("EclipseWindowClosing")
					:Connect(function()
						changed = true
					end)
				task.delay(0.5, function()
					connection:Disconnect()
					if
						not changed
						and gui.Parent == parent
						and frame:IsDescendantOf(gui)
						and frame:GetAttribute("EclipseWindowClosing") == true
					then
						gui:Destroy()
					end
				end)
			end
		end
	end
end

local function isToolWindow(gui)
	if not gui:IsA("ScreenGui") or gui:GetAttribute("EclipseOwnedUI") ~= true then
		return false
	end

	if gui:GetAttribute("EclipseToolWindow") == true then
		return true
	end

	const frame = gui:FindFirstChild("Window", true)
	const header = frame and frame:FindFirstChild("Header")
	return header ~= nil
		and header:FindFirstChild("Close") ~= nil
		and frame:FindFirstChild("MinimumSize") ~= nil
end

function WindowFX.releaseTools(parent, owner)
	for _, gui in parent:GetChildren() do
		if isToolWindow(gui) and gui:GetAttribute("EclipseToolOwner") == owner then
			gui:Destroy()
		end
	end
end

function WindowFX.recoverOrphanedTools(parent)
	const owners = {}
	for _, gui in parent:GetChildren() do
		const token = gui:GetAttribute("EclipseInstance")
		if token ~= nil then
			owners[token] = true
		end
	end

	for _, gui in parent:GetChildren() do
		if isToolWindow(gui) then
			const owner = gui:GetAttribute("EclipseToolOwner")
			if owner == nil or not owners[owner] then
				gui:Destroy()
			end
		end
	end
end

const SOLID_PROPERTIES = {
	"AnchorPoint",
	"Position",
	"Size",
	"SizeConstraint",
	"AutomaticSize",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderColor3",
	"BorderSizePixel",
	"ZIndex",
	"LayoutOrder",
	"Rotation",
	"Active",
	"Interactable",
	"Selectable",
	"Visible",
}

function WindowFX.solidify(group)
	if not group or not group:IsA("CanvasGroup") then
		return group
	end

	const frame = Instance.new("Frame")
	for _, property in SOLID_PROPERTIES do
		frame[property] = group[property]
	end

	frame.Name = group.Name
	frame.ClipsDescendants = true
	for name, value in group:GetAttributes() do
		frame:SetAttribute(name, value)
	end

	for _, child in group:GetChildren() do
		child.Parent = frame
	end

	frame.Parent = group.Parent
	group:Destroy()
	return frame
end

return WindowFX
