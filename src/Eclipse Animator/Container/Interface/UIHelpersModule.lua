--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Theme = require("Theme")

local UIHelpers = {}
UIHelpers.__index = UIHelpers

function UIHelpers.new(refs)
	local self = setmetatable({}, UIHelpers)

	self.caches = {
		rigListItemList = {},
	}
	self.refs = refs
	self.connections = {}
	self.draggableWindow = require("SizeableWindows")
	self.coloredButton = Theme.get("Sel", Color3.fromRGB(104, 10, 255))
	Theme.onChanged(function()
		self.coloredButton = Theme.get("Sel", Color3.fromRGB(104, 10, 255))
	end)

	self.hoverDialog = require("HoverDialog").initialize(
		self.refs.PluginGui.Hover,
		require("UserInputService").mouse(self.refs.mouse)
	)
	self.zoom = require("Zoom")

	return self
end

function UIHelpers.SanitizeName(str)
	return (tostring(str or ""):gsub("%s+", ""))
end

function UIHelpers:spitData(values)
	local output = ""

	for i, v in values do
		if i ~= 1 then
			output = output .. "\n"
		end

		if v == "_DIV_" then
			output = output .. "----"
			continue
		end

		output = output .. `<i>{v[1]}:  </i><b>{tostring(v[2])}</b>`
	end

	return output
end

function UIHelpers:retrieveIdlePropertiesComparedOthers(element, comparisons)
	local neededProperteies = {}

	for _, comp in comparisons do
		for index, _ in comp do
			neededProperteies[index] = true
		end
	end

	local propertyOutput = {}

	for i, _ in neededProperteies do
		propertyOutput[i] = element[i]
	end

	return propertyOutput
end

function UIHelpers:applyProperties(element, propertyList)
	for i, v in propertyList do
		if typeof(v) == "function" then
			element[i] = v(element)
		else
			element[i] = v
		end
	end
end

function UIHelpers:bindToUIStates(element: GuiObject, guiStateProperties)
	guiStateProperties["Idle"] =
		self:retrieveIdlePropertiesComparedOthers(element, guiStateProperties)

	local connection = element:GetPropertyChangedSignal("GuiState"):Connect(function()
		local propList = guiStateProperties[element.GuiState.Name]
		if not propList then
			return
		end

		self:applyProperties(element, propList)
	end)
	self.connections[connection] = true

	element.Destroying:Once(function()
		connection:Disconnect()
		self.connections[connection] = nil
	end)
end

local function setButtonState(self, button, selected)
	if selected then
		button.BackgroundTransparency = 0.15
		button.BackgroundColor3 = self.coloredButton
	else
		button.BackgroundTransparency = 1
		button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
end

function UIHelpers:SetSelected(button, idName, selected)
	if not button then
		return
	end

	if selected == nil then
		selected = true
	end

	self.caches[idName] = self.caches[idName] or {}

	local previous = self.caches[idName]["selected"]
	local target = button or previous

	if previous ~= target and previous then
		setButtonState(self, previous, false)
	end

	setButtonState(self, target, selected)

	if selected then
		self.caches[idName]["selected"] = target
	end
end

function UIHelpers:Destroy()
	for connection in pairs(self.connections) do
		connection:Disconnect()
	end

	self.connections = {}
end

return UIHelpers
