--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local ContentProvider = game:GetService("ContentProvider")
local Audio = {}
local PRELOAD_TIMEOUT = 12
local widget

function Audio.attach(plugin)
	if widget then
		return
	end

	local info =
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 10, 10, 10, 10)
	local ok, result =
		pcall(plugin.CreateDockWidgetPluginGuiAsync, plugin, "EclipseAnimatorAudio", info)
	if not ok then
		warn("couldnt start eclipse audio: " .. tostring(result))
		return
	end

	widget = result
	widget.Name = "EclipseAnimatorAudio"
	widget.Title = "Eclipse Audio"
	widget.Enabled = false
	widget.Archivable = false
end

function Audio.parent()
	return widget
end

function Audio.preload(sounds, isCurrent)
	if not isCurrent() then
		return false
	end

	if #sounds == 0 then
		return true
	end

	local done, failure = false, nil
	task.spawn(function()
		local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, sounds)
		if not ok then
			failure = err
		end

		done = true
	end)
	local deadline = os.clock() + PRELOAD_TIMEOUT
	while not done and isCurrent() and os.clock() < deadline do
		task.wait()
	end

	if not isCurrent() then
		return false
	end

	if failure then
		warn("couldnt preload audio: " .. tostring(failure))
		return false
	end

	for _, sound in sounds do
		if not sound.IsLoaded then
			warn("couldnt preload audio " .. sound.SoundId)
			return false
		end
	end

	return true
end

function Audio.destroy()
	require("LocalAudio").clear()
	local previous = widget
	widget = nil
	if not previous then
		return
	end

	for _, sound in previous:GetChildren() do
		if sound:IsA("Sound") then
			sound:Stop()
		end
	end

	previous:Destroy()
end

return Audio
