--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Marketplace = game:GetService("MarketplaceService")
local Notification = require("Notification")
local Notice = {}
local ASSET_ID = 86116556258301

function Notice.version(text)
	if type(text) ~= "string" then return nil end
	local version = text:match("^%s*[vV](%d+%.%d+[%.%d]*)%s*$")
	if not version or version:find("%.%.") or version:sub(-1) == "." then return nil end
	local parts = {}
	for part in version:gmatch("%d+") do
		local value = tonumber(part)
		if not value or value == math.huge then return nil end
		table.insert(parts, value)
	end
	return parts
end

function Notice.newer(current, info)
	local installed = Notice.version(current)
	if not installed or type(info) ~= "table" or info.AssetId ~= ASSET_ID or info.AssetTypeId ~= 38 then return false end
	if type(info.Description) ~= "string" then return false end
	local published
	for line in info.Description:gmatch("[^\r\n]+") do
		local candidate = Notice.version(line)
		if candidate then
			if published then return false end
			published = candidate
		end
	end
	if not published then return false end
	for i = 1, math.max(#installed, #published) do
		local a, b = installed[i] or 0, published[i] or 0
		if a ~= b then return b > a end
	end
	return false
end

function Notice.start(screen, source)
	--// no update avaliable notification
	if true then return end
	local current = source:GetAttribute("EclipseReleaseVersion") or source:GetAttribute("EclipseBuildVersion")
	if not Notice.version(current) then return end
	local alive, checking = true, false
	local opened, shown = 1, nil
	local last = -math.huge
	local connection
	local function check(force)
		if not alive or not screen.Enabled or checking or shown == opened or not force and os.clock() - last < 900 then return end
		checking, last = true, os.clock()
		task.spawn(function()
			local ok, info = pcall(Marketplace.GetProductInfoAsync, Marketplace, ASSET_ID, Enum.InfoType.Asset)
			checking = false
			if not alive or not screen.Enabled or not ok or not Notice.newer(current, info) then return end
			local notice = Notification.show(
				"NEW UPDATE AVAILABLE!",
				'Go to Plugins > Manage Plugins > find "Eclipse Animator" > Update',
				7,
				"UpdateAvailable"
			)
			if notice then shown = opened end
		end)
	end
	connection = screen:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screen.Enabled then
			opened += 1
			check(true)
		end
	end)
	screen.Destroying:Once(function()
		alive = false
		connection:Disconnect()
	end)
	task.defer(check)
	task.spawn(function()
		while alive do
			task.wait(60)
			if alive and screen.Enabled then check() end
		end
	end)
end

return Notice
