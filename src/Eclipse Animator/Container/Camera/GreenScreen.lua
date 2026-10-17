--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Preferences = require("Preferences")
local Environment = require("Environment")
local Green = {}
local refs, gui, viewport, scene, connection
local enabled = false

function Green.color()
	return Color3.fromHex(Preferences.get("GreenScreenColor") or "00FF00")
end

function Green.isEnabled()
	return enabled
end

function Green.projection(cf, fov, width, height, x, y, w, h)
    local tangent = math.tan(math.rad(fov) / 2)
    local desired = tangent * h / height
    local tileFov = math.clamp(math.deg(2 * math.atan(desired)), 1, 120)
    local scale = math.tan(math.rad(tileFov) / 2) / desired
    local cx = (2 * (x + w / 2) / width - 1) * tangent * width / height
    local cy = (1 - 2 * (y + h / 2) / height) * tangent
    return cf * CFrame.new(0, 0, 0, scale, 0, 0, 0, scale, 0, cx * scale, cy * scale, 1), tileFov
end

function Green.attachViewport(target)
    local host = Instance.new("Frame")
    host.Name = "GreenScreenPixels"
    host.AnchorPoint = Vector2.new(0.5, 0.5)
    host.BackgroundTransparency = 1
    host.BorderSizePixel = 0
    host.ClipsDescendants = true
    host.Parent = target.Parent
    local tiles, dimensions = {}, Vector2.zero
    local alive = true
    local hideAccessories = false
    local originalTransparency = target.ImageTransparency
    target.ImageTransparency = 1
    local function clearTiles()
        for _, tile in tiles do tile.scene.destroy() tile.viewport:Destroy() end
        table.clear(tiles)
    end
    local function update(cf, fov, rigs)
        if not alive then return end
        host.AnchorPoint, host.Position, host.Size = target.AnchorPoint, target.Position, target.Size
        host.Visible, host.ZIndex = target.Visible, target.ZIndex + 1
        host.BackgroundColor3 = Green.color()
        local pixels = Vector2.new(math.max(1, math.floor(target.AbsoluteSize.X + 0.5)), math.max(1, math.floor(target.AbsoluteSize.Y + 0.5)))
        if dimensions ~= pixels then
            clearTiles()
            dimensions = pixels
            local columns, rows = math.ceil(pixels.X / 1024), math.ceil(pixels.Y / 1024)
            for row = 0, rows - 1 do
                for column = 0, columns - 1 do
                    local x, y = math.floor(column * pixels.X / columns), math.floor(row * pixels.Y / rows)
                    local w, h = math.floor((column + 1) * pixels.X / columns) - x, math.floor((row + 1) * pixels.Y / rows) - y
                    local view = Instance.new("ViewportFrame")
                    view.Name = "Subjects" .. row .. "_" .. column
                    view.AnchorPoint = Vector2.new(0.5, 0.5)
                    view.Position = UDim2.fromScale((x + w / 2) / pixels.X, (y + h / 2) / pixels.Y)
                    view.Size = UDim2.fromScale(w / pixels.X, h / pixels.Y)
                    view.BorderSizePixel = 0
                    view.Active, view.Interactable = false, false
                    view.ZIndex = host.ZIndex
                    view.Parent = host
                    table.insert(tiles, {viewport = view, scene = Environment.attach(view, nil, { SubjectsOnly = true }), x = x, y = y, width = w, height = h})
                end
            end
        end
        for _, tile in tiles do
            tile.viewport.BackgroundColor3 = Green.color()
            local tileCF, tileFov = Green.projection(cf, fov, pixels.X, pixels.Y, tile.x, tile.y, tile.width, tile.height)
            tile.scene.setHideAccessories(hideAccessories)
            tile.scene.update(tileCF, tileFov, rigs)
        end
    end
    local removed
    local function destroy()
        if not alive then return end
        alive = false
        if removed then removed:Disconnect() end
        clearTiles()
        target.ImageTransparency = originalTransparency
        host:Destroy()
    end
    removed = target.Destroying:Connect(destroy)
    host.Destroying:Once(destroy)
    return {
        update = update,
        setHideAccessories = function(value) hideAccessories = value end,
        destroy = destroy,
    }
end

local function clear()
	if scene then scene.destroy() scene = nil end
	if gui then gui:Destroy() gui, viewport = nil, nil end
end

local function update()
	local active = refs and refs.ScreenGui.Parent and refs.ScreenGui.Enabled
		and (refs.Active() or refs.State.PresentationHidden or refs.State.CameraPreview and refs.State.CameraPreview.isFull())
	local camera = workspace.CurrentCamera
	if not enabled or not active or not camera then clear() return end
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "EclipseGreenScreen"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = refs.ScreenGui.DisplayOrder - 1
		gui:SetAttribute("EclipseOwnedUI", true)
		gui.Parent = refs.ScreenGui.Parent
		viewport = Instance.new("ViewportFrame")
		viewport.Name = "Subjects"
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.5)
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BorderSizePixel = 0
		viewport.Active = false
		viewport.Interactable = false
		viewport.Parent = gui
		scene = Green.attachViewport(viewport)
	end
	viewport.BackgroundColor3 = Green.color()
	scene.update(camera.CFrame, camera.FieldOfView, refs.State.getAllRigs())
end

function Green.set(value)
	enabled = value == true
	update()
	if refs and refs.State.CameraPreview then refs.State.CameraPreview.refresh() end
end

function Green.toggle()
	Green.set(not enabled)
end

function Green.destroy()
	enabled = false
	if connection then connection:Disconnect() connection = nil end
	clear()
	refs = nil
end

function Green.init(options)
	Green.destroy()
	refs = options
	options.State.GreenScreen = Green
	connection = game:GetService("RunService").RenderStepped:Connect(update)
	options.ScreenGui.Destroying:Once(Green.destroy)
	options.Plugin.Unloading:Once(Green.destroy)
end

return Green
