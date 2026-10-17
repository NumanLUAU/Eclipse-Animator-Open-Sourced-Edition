local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

if typeof(plugin) ~= "Instance" or not plugin:IsA("Plugin") then
	return
end

-- boot her up ahahhaha........

require(script.Container.Require)("Boot").start(plugin, script)
