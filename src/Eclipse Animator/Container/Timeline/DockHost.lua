--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Host = {}
local owners = setmetatable({}, { __mode = "k" })
local widgets = setmetatable({}, { __mode = "k" })

function Host.acquire(plugin, id, info)
	local owner = owners[plugin]
	if not owner then
		owner = { slots = {}, closed = false }
		owners[plugin] = owner
		plugin.Unloading:Once(function()
			owner.closed = true
			for _, slot in owner.slots do
				if slot.widget then
					slot.widget:Destroy()
				end
			end

			owners[plugin] = nil
		end)
	end

	assert(not owner.closed, "Plugin is unloading")
	local slot = owner.slots[id]
	if not slot then
		slot = { version = 0 }
		owner.slots[id] = slot
	end

	while slot.creating and not owner.closed do
		task.wait()
	end

	assert(not owner.closed, "Plugin is unloading")
	if not slot.widget then
		slot.creating = true
		local ok, result = pcall(plugin.CreateDockWidgetPluginGuiAsync, plugin, id, info)
		slot.creating = false
		if not ok then
			error(result)
		end

		if owner.closed then
			result:Destroy()
			error("Plugin is unloading")
		end

		slot.widget = result
		widgets[result] = slot
		result.Destroying:Once(function()
			if slot.widget == result then
				slot.widget = nil
			end

			widgets[result] = nil
		end)
	end

	slot.version += 1
	return slot.widget
end

function Host.ready(widget)
	return widget and widget.Enabled and widget.AbsoluteSize.X > 0 and widget.AbsoluteSize.Y > 0
end

function Host.show(widget, current)
	local slot = widgets[widget]
	local version = slot and slot.version

	local function valid()
		return (not slot or slot.widget == widget and slot.version == version)
			and (not current or current())
	end

	for attempt = 1, 2 do
		if not valid() then
			return false
		end

		if attempt == 2 then
			widget.Enabled = false
			task.wait()
		end

		if not valid() then
			return false
		end

		widget.Enabled = true
		pcall(function()
			widget:RequestRaise()
		end)
		local deadline = os.clock() + 0.8
		repeat
			task.wait()
			if not valid() then
				return false
			end

			if Host.ready(widget) then
				return true
			end
		until os.clock() >= deadline
	end

	return false
end

function Host.release(widget)
	if not widget then
		return
	end

	local slot = widgets[widget]
	if not slot then
		return
	end

	slot.version += 1
	widget:BindToClose(function()
		widget.Enabled = false
	end)
	widget.Enabled = false

	for _, child in widget:GetChildren() do
		child:Destroy()
	end
end

return Host
