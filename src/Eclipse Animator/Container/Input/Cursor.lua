--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Cursor = {}
local Input = game:GetService("UserInputService")
local BLANK = "rbxasset://textures/Blank.png"
local owners = {}
local mice = {}
local previousVisible

function Cursor.snapshot(mouse)
	local visible = previousVisible
	if visible == nil then
		visible = Input.MouseIconEnabled
	end
	local entry = mouse and mice[mouse]
	local icon = entry and entry.icon or mouse and mouse.Icon
	return visible, icon
end

function Cursor.hide(owner, mouse)
	if not owners[owner] then
		if next(owners) == nil then
			previousVisible = Input.MouseIconEnabled
		end
		owners[owner] = { mouse = mouse }
		if mouse then
			local entry = mice[mouse]
			if not entry then
				entry = { icon = mouse.Icon, count = 0 }
				mice[mouse] = entry
			end
			entry.count += 1
		end
	end
	local ok = pcall(function()
		Input.MouseIconEnabled = false
		if mouse then
			mouse.Icon = BLANK
		end
	end)
	if not ok then
		Cursor.release(owner)
	end
	return ok
end

function Cursor.release(owner)
	local entry = owners[owner]
	if not entry then
		return
	end
	owners[owner] = nil
	local mouse = entry.mouse
	local saved = mouse and mice[mouse]
	if saved then
		saved.count -= 1
		if saved.count == 0 then
			mice[mouse] = nil
			pcall(function()
				if mouse.Icon == BLANK then
					mouse.Icon = saved.icon
				end
			end)
		end
	end
	if next(owners) == nil then
		local visible = previousVisible
		previousVisible = nil
		pcall(function()
			Input.MouseIconEnabled = visible
		end)
	end
end

function Cursor.isReady(cursor, pan)
	local image = pan and cursor.pan or cursor.orbit
	return image and image.IsLoaded
end

local function icon(name, image, parent)
	local object = Instance.new("ImageLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Size = UDim2.fromOffset(27, 27)
	object.Image = image
	object.ImageColor3 = Color3.new(1, 1, 1)
	object.ScaleType = Enum.ScaleType.Fit
	object.Active = false
	object.Interactable = false
	object.ZIndex = 4
	object.Parent = parent
	return object
end

function Cursor.create(parent)
	local root = Instance.new("Frame")
	root.Name = "NavigationCursor"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(0, 0)
	root.Active = false
	root.Interactable = false
	root.Parent = parent
	local orbit = icon("Orbit", "rbxassetid://85812029222497", root)
	local pan = icon("Pan", "rbxassetid://123202248396351", root)
	pan.Visible = false
	return { root = root, pan = pan, orbit = orbit }
end

function Cursor.setPan(cursor, pan)
	cursor.pan.Visible = pan
	cursor.orbit.Visible = not pan
end

return Cursor
