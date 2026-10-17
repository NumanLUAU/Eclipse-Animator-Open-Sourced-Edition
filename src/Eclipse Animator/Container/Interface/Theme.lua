--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local GifBackground = require("GifBackground")
local GifSequence = require("Sequence")
local presetRevision = 0
local requestRevision = 0
local activeProgress
local HttpService = game:GetService("HttpService")

local ThemeConfig = require("ThemeConfig")

local Theme = {}

local screenGui = nil
local extraRoots = {}
local getSetting = nil
local setSetting = nil
local updateSetting = nil
local persistedTheme = nil
local timelineState = nil
local getTimeline = nil

local mode = "A"
local overrides = {}
local scriptOriginals = nil
local changedCallbacks = {}
local initialized = false
local themeRevision = 0
local appliedRevision = setmetatable({}, { __mode = "k" })
local pendingTheme = setmetatable({}, { __mode = "k" })
local themeQueued = false

local ATTR_PROPS = {
	ThemeBg = { "BackgroundColor3", "BackgroundTransparency" },
	ThemeTxt = { "TextColor3", "TextTransparency" },
	ThemeImg = { "ImageColor3", "ImageTransparency" },
	ThemeStrk = { "Color", "Transparency" },
	ThemeScr = { "ScrollBarImageColor3", "ScrollBarImageTransparency" },
	ThemeGrad = { "Color", nil },
}

local function hexToColor(hex)
	hex = tostring(hex or ""):gsub("#", "")
	if #hex ~= 6 then
		return nil
	end

	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if not r or not g or not b then
		return nil
	end

	return Color3.fromRGB(r, g, b)
end

local function colorToHex(c)
	return string.format(
		"#%02x%02x%02x",
		math.round(c.R * 255),
		math.round(c.G * 255),
		math.round(c.B * 255)
	)
end

function Theme.parseValue(str)
	if typeof(str) ~= "string" or str == "" then
		return nil
	end

	local rot = nil
	local atPos = str:find("@")
	if atPos then
		rot = tonumber(str:sub(atPos + 1))
		str = str:sub(1, atPos - 1)
	end

	local stops = {}
	for part in str:gmatch("[^>]+") do
		local c = hexToColor(part)
		if not c then
			return nil
		end

		table.insert(stops, c)
	end

	if #stops == 0 then
		return nil
	end

	return { stops = stops, rot = rot }
end

function Theme.formatValue(v)
	if not v or not v.stops or #v.stops == 0 then
		return nil
	end

	local parts = {}
	for _, c in ipairs(v.stops) do
		table.insert(parts, colorToHex(c))
	end

	local s = table.concat(parts, ">")
	if v.rot and v.rot ~= 0 and #v.stops > 1 then
		s ..= "@" .. tostring(math.round(v.rot))
	end

	return s
end

local function shade(c, modName, amt)
	if modName == "darken" then
		return c:Lerp(Color3.new(0, 0, 0), amt)
	elseif modName == "lighten" then
		return c:Lerp(Color3.new(1, 1, 1), amt)
	end

	return c
end

local function shadeValue(v, modName, amt)
	if not modName then
		return v
	end

	local stops = {}
	for _, c in ipairs(v.stops) do
		table.insert(stops, shade(c, modName, amt))
	end

	return { stops = stops, rot = v.rot, t = v.t }
end

local oldEclipse = false
local legacyValues = {}
local defaultValues = {}
for _, setting in ipairs(ThemeConfig.settings) do
	local legacy = Theme.parseValue(ThemeConfig.oldTheme[setting.key])
	if legacy then
		legacyValues[setting.key] = legacy
	end

	local value = Theme.parseValue(ThemeConfig.defaultTheme[setting.key])
	if value then
		defaultValues[setting.key] = value
	end
end

local function baseValues()
	return oldEclipse and legacyValues or defaultValues
end

function Theme.panelOutlineDefault()
	if baseValues().Strk then
		return baseValues().Strk.stops[1]
	end

	local node = screenGui
	for _, name in { "Frame", "Tabs", "Animator", "Frames", "Main", "BottomContainer" } do
		node = node and node:FindFirstChild(name)
	end

	local stroke = node and node:FindFirstChildOfClass("UIStroke")
	local original = stroke and stroke:GetAttribute("EOrig_Color")
	return typeof(original) == "Color3" and original
		or stroke and stroke.Color
		or Color3.fromRGB(147, 147, 147)
end

local effectiveCache
local sequenceCache = setmetatable({}, { __mode = "k" })

local function effectiveValues()
	if effectiveCache then
		return effectiveCache
	end

	local values = table.clone(baseValues())
	for key, value in pairs(overrides) do
		values[key] = value
	end

	if not values.Div then
		values.Div = values.Strk or { stops = { Theme.panelOutlineDefault() } }
	end

	effectiveCache = values
	return values
end

local function encodeOrigValue(v)
	if typeof(v) == "ColorSequence" then
		local parts = {}
		for _, kp in ipairs(v.Keypoints) do
			table.insert(parts, colorToHex(kp.Value))
		end

		return "CS:" .. table.concat(parts, ">")
	end

	return v
end

local function decodeOrigValue(v)
	if typeof(v) == "string" and v:sub(1, 3) == "CS:" then
		local parsed = Theme.parseValue(v:sub(4))
		if parsed then
			if #parsed.stops == 1 then
				return ColorSequence.new(parsed.stops[1])
			end

			local kps = {}
			for i, c in ipairs(parsed.stops) do
				table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#parsed.stops - 1), c))
			end

			return ColorSequence.new(kps)
		end

		return nil
	end

	return v
end

local function captureOriginal(inst, prop)
	local attr = "EOrig_" .. prop
	if inst:GetAttribute(attr) == nil then
		local ok, v = pcall(function()
			return inst[prop]
		end)
		if ok and v ~= nil then
			pcall(function()
				inst:SetAttribute(attr, encodeOrigValue(v))
			end)
		end
	end
end

local function getOriginal(inst, prop)
	local v = inst:GetAttribute("EOrig_" .. prop)
	if v == nil then
		return nil
	end

	return decodeOrigValue(v)
end

local buttonText = setmetatable({}, { __mode = "k" })

function Theme.separateButtonText(button)
	if not button:IsA("TextButton") or button.Text == "" then
		return nil
	end

	if buttonText[button] then
		return buttonText[button]
	end

	local label = Instance.new("TextLabel")
	label.Name = "EclipseButtonText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Active = false
	label.Selectable = false
	local properties = {
		"Text",
		"FontFace",
		"TextSize",
		"TextColor3",
		"TextTransparency",
		"TextStrokeColor3",
		"TextStrokeTransparency",
		"TextXAlignment",
		"TextYAlignment",
		"TextWrapped",
		"TextScaled",
		"TextTruncate",
		"RichText",
		"LineHeight",
		"MaxVisibleGraphemes",
	}
	for _, prop in properties do
		label[prop] = button[prop]
	end

	captureOriginal(button, "TextTransparency")
	captureOriginal(button, "TextStrokeTransparency")
	buttonText[button] = label
	label.ZIndex = button.ZIndex + 1
	label.Parent = button
	local connections = {}
	for _, prop in properties do
		table.insert(
			connections,
			button:GetPropertyChangedSignal(prop):Connect(function()
				if prop == "TextTransparency" or prop == "TextStrokeTransparency" then
					if button[prop] ~= 1 then
						label[prop] = button[prop]
						button[prop] = 1
					end
				else
					label[prop] = button[prop]
				end
			end)
		)
	end

	table.insert(
		connections,
		button:GetPropertyChangedSignal("ZIndex"):Connect(function()
			label.ZIndex = button.ZIndex + 1
		end)
	)
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	for _, child in button:GetChildren() do
		if child:IsA("UIPadding") or child:IsA("UITextSizeConstraint") then
			child:Clone().Parent = label
		end
	end

	button.Destroying:Once(function()
		for _, c in connections do
			c:Disconnect()
		end

		buttonText[button] = nil
	end)
	return label
end

local function setProp(inst, prop, value)
	if buttonText[inst] and (prop:sub(1, 4) == "Text" or prop == "FontFace") then
		inst = buttonText[inst]
	end

	pcall(function()
		if
			prop == "BackgroundTransparency"
			or prop == "TextTransparency"
			or prop == "ImageTransparency"
			or prop == "Transparency"
			or prop == "ScrollBarImageTransparency"
		then
			require("WindowFX").setRestingProperty(inst, prop, value)
		elseif inst[prop] ~= value then
			inst[prop] = value
		end
	end)
end

local function restoreProp(inst, prop)
	local v = getOriginal(inst, prop)
	if v ~= nil then
		setProp(inst, prop, v)
	end
end

local function toSequence(v)
	local cached = sequenceCache[v]
	if cached then
		return cached
	end

	if #v.stops == 1 then
		local sequence = ColorSequence.new(v.stops[1])
		sequenceCache[v] = sequence
		return sequence
	end

	local kps = {}
	for i, c in ipairs(v.stops) do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#v.stops - 1), c))
	end

	local sequence = ColorSequence.new(kps)
	sequenceCache[v] = sequence
	return sequence
end

local function hasTaggedGradient(inst, key)
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("UIGradient") and c:GetAttribute("ThemeGrad") == key then
			return true
		end
	end

	return false
end

local function findForeignGradient(inst)
	for _, c in ipairs(inst:GetChildren()) do
		if
			c:IsA("UIGradient")
			and c.Name ~= "EclipseThemeGradient"
			and not c:GetAttribute("ThemeGrad")
		then
			return c
		end
	end

	return nil
end

local function manageGradientChild(inst, v)
	local g = inst:FindFirstChild("EclipseThemeGradient")
	local foreign = findForeignGradient(inst)
	if v and #v.stops > 1 then
		if foreign then
			if g then
				g:Destroy()
			end

			captureOriginal(foreign, "Color")
			captureOriginal(foreign, "Rotation")
			setProp(foreign, "Color", toSequence(v))
			setProp(foreign, "Rotation", v.rot or 90)
		else
			if not g then
				g = Instance.new("UIGradient")
				g.Name = "EclipseThemeGradient"
				g.Parent = inst
			end

			g.Color = toSequence(v)
			g.Rotation = v.rot or 90
			g.Enabled = true
		end
	else
		if g then
			g:Destroy()
		end

		if foreign then
			restoreProp(foreign, "Color")
			restoreProp(foreign, "Rotation")
		end
	end
end

local function applyAttrToInstance(inst, attrName, key, values)
	local props = ATTR_PROPS[attrName]
	if not props then
		return
	end

	local colorProp, transProp = props[1], props[2]
	local v = values[key]

	if attrName == "ThemeGrad" then
		captureOriginal(inst, "Color")
		if v then
			setProp(inst, "Color", toSequence(v))
			if v.rot then
				captureOriginal(inst, "Rotation")
				setProp(inst, "Rotation", v.rot)
			else
				restoreProp(inst, "Rotation")
			end
		else
			restoreProp(inst, "Color")
			restoreProp(inst, "Rotation")
		end

		return
	end

	captureOriginal(inst, colorProp)
	if transProp then
		captureOriginal(inst, transProp)
	end

	local shadeAmt = inst:GetAttribute("ThemeShade")
	if v and typeof(shadeAmt) == "number" and shadeAmt ~= 0 then
		v = shadeValue(v, shadeAmt > 0 and "lighten" or "darken", math.abs(shadeAmt))
	end

	if attrName == "ThemeTxt" and inst:IsA("TextBox") then
		captureOriginal(inst, "PlaceholderColor3")
		if v then
			setProp(inst, "PlaceholderColor3", shade(v.stops[1], "darken", 0.35))
		else
			restoreProp(inst, "PlaceholderColor3")
		end
	end

	if v then
		setProp(inst, colorProp, v.stops[1])
		if attrName == "ThemeBg" or attrName == "ThemeStrk" then
			if hasTaggedGradient(inst, key) then
				manageGradientChild(inst, nil)
				setProp(inst, colorProp, Color3.new(1, 1, 1))
			elseif #v.stops > 1 then
				manageGradientChild(inst, v)
				setProp(inst, colorProp, Color3.new(1, 1, 1))
			else
				manageGradientChild(inst, nil)
			end
		end

		if transProp and v.t ~= nil then
			setProp(inst, transProp, v.t)
		elseif transProp then
			restoreProp(inst, transProp)
		end
	else
		restoreProp(inst, colorProp)
		if transProp then
			restoreProp(inst, transProp)
		end

		if attrName == "ThemeBg" or attrName == "ThemeStrk" then
			manageGradientChild(inst, nil)
		end
	end

	local stateTransparency = (attrName == "ThemeBg" or attrName == "ThemeTxt" or attrName == "ThemeImg")
		and inst:GetAttribute(attrName .. "Transparency")
	if typeof(stateTransparency) == "number" then
		require("WindowFX").setRestingProperty(
			inst,
			attrName == "ThemeTxt" and "TextTransparency" or attrName == "ThemeImg" and "ImageTransparency" or "BackgroundTransparency",
			1 - (1 - stateTransparency) * (1 - (v and v.t or 0))
		)
	end
end

local function backgroundLayout(value)
	local function finite(n, fallback, lo, hi)
		return typeof(n) == "number"
				and n == n
				and math.abs(n) < math.huge
				and math.clamp(n, lo, hi)
			or fallback
	end

	value = type(value) == "table" and value or {}
	return {
		scale = finite(value.scale, 1, 0.25, 2),
		fit = value.fit == "Fit" and "Fit" or value.fit == "Stretch" and "Stretch" or "Crop",
		x = finite(value.x, 0, -1, 1),
		y = finite(value.y, 0, -1, 1),
	}
end

local function applyBackgroundImage(inst, values)
	local v = values.Img
	local stray = inst:FindFirstChild("EclipseThemeBackground")
	if stray then
		stray:Destroy()
	end

	local folder = inst:FindFirstChild("EclipseThemeBackdrop")
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end

	local viewport = folder and folder:FindFirstChild("Viewport")
	local img = viewport and viewport:FindFirstChild("EclipseThemeBackground")
	local frames = v and v.mode ~= "image" and GifBackground.effectiveFrames(v.frames) or nil
	if v and (frames or (v.image and v.image ~= "")) then
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "EclipseThemeBackdrop"
			folder.Parent = inst
		end

		if not viewport then
			local legacy = folder:FindFirstChild("EclipseThemeBackground")
			if legacy then
				GifBackground.bind(legacy, nil)
				legacy:Destroy()
			end

			viewport = Instance.new("Frame")
			viewport.Name = "Viewport"
			viewport.Size = UDim2.fromScale(1, 1)
			viewport.BackgroundTransparency = 1
			viewport.BorderSizePixel = 0
			viewport.ClipsDescendants = true
			viewport.ZIndex = -5
			viewport.Parent = folder
		end

		if not img then
			img = Instance.new("ImageLabel")
			img.Name = "EclipseThemeBackground"
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Position = UDim2.fromScale(0, 0)
			img.ZIndex = -5
			img.ScaleType = Enum.ScaleType.Crop
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = img
			img.Parent = viewport
		end

		local layout = backgroundLayout(v.layout)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.ScaleType = Enum.ScaleType[layout.fit]
		local margin = math.abs(1 - layout.scale) * 0.5
		img.Position = UDim2.fromScale(0.5 + layout.x * margin, 0.5 + layout.y * margin)
		img.Size = UDim2.fromScale(layout.scale, layout.scale)
		GifBackground.bind(img, frames)
		if not frames then
			img.ImageRectOffset = Vector2.zero
			img.ImageRectSize = Vector2.zero
			img.Image = v.image
		end
		GifBackground.setTransparency(img, v.t or 0)
	elseif folder then
		if img then
			GifBackground.bind(img, nil)
		end

		folder:Destroy()
	end
end

function Theme.contrastText(color)
	local function linear(v)
		return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end

	local luminance = 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
	return luminance > 0.179 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
end

local function applyToInstance(inst, values, changedKeys)
	if inst:IsA("TextButton") and inst:GetAttribute("ThemeBg") then
		Theme.separateButtonText(inst)
	end

	if appliedRevision[inst] == nil then
		changedKeys = nil
	end

	appliedRevision[inst] = themeRevision
	for attrName in pairs(ATTR_PROPS) do
		local key = inst:GetAttribute(attrName)
		if key and (not changedKeys or changedKeys[key]) then
			applyAttrToInstance(inst, attrName, key, values)
		end
	end

	if inst:IsA("TextLabel") and inst.Parent and inst.Parent.Name == "TopSelector" then
		setProp(inst, "TextColor3", Theme.contrastText(inst.Parent.BackgroundColor3))
		setProp(inst, "TextTransparency", values.TopT and values.TopT.t or 0)
	end

	if inst:GetAttribute("ThemeBgImage") and (not changedKeys or changedKeys.Img) then
		applyBackgroundImage(inst, values)
	end

	if
		inst:GetAttribute("ThemeStateGrad")
		and (not changedKeys or changedKeys[inst:GetAttribute("ThemeStateGrad")])
	then
		local v = values[inst:GetAttribute("ThemeStateGrad")]
		manageGradientChild(inst, v)
	end
end

local function applyScriptColors(values)
	if not timelineState or not timelineState.Colors then
		return
	end

	local colors = timelineState.Colors
	if not scriptOriginals then
		scriptOriginals = { flat = {}, handleD = {}, handleH = {} }
		for _, field in pairs(ThemeConfig.scriptColorMap) do
			scriptOriginals.flat[field] = colors[field]
		end

		for _, hName in pairs(ThemeConfig.scriptHandleMap) do
			scriptOriginals.handleD[hName] = colors.KEYFRAME_HANDLE_DEFAULT[hName]
			scriptOriginals.handleH[hName] = colors.KEYFRAME_HANDLE_HOVER[hName]
		end
	end

	for key, field in pairs(ThemeConfig.scriptColorMap) do
		local v = values[key]
		if v then
			if #v.stops > 1 and (key == "Loop" or key == "Rec") then
				colors[field] = Color3.new(1, 1, 1)
			else
				colors[field] = v.stops[1]
			end
		else
			colors[field] = scriptOriginals.flat[field]
		end
	end

	for key, hName in pairs(ThemeConfig.scriptHandleMap) do
		local v = values[key]
		if v then
			colors.KEYFRAME_HANDLE_DEFAULT[hName] = v.stops[1]
			colors.KEYFRAME_HANDLE_HOVER[hName] = v.stops[1]:Lerp(Color3.new(0, 0, 0), 0.3)
		else
			colors.KEYFRAME_HANDLE_DEFAULT[hName] = scriptOriginals.handleD[hName]
			colors.KEYFRAME_HANDLE_HOVER[hName] = scriptOriginals.handleH[hName]
		end
	end
end

local function allRoots()
	local roots = {}
	if screenGui then
		table.insert(roots, screenGui)
	end

	for _, r in ipairs(extraRoots) do
		if r and r.Parent then
			table.insert(roots, r)
		end
	end

	return roots
end

function Theme.apply(changedKeys)
	effectiveCache = nil
	sequenceCache = setmetatable({}, { __mode = "k" })
	if not screenGui then
		return
	end

	themeRevision += 1
	local values = effectiveValues()
	for _, root in ipairs(allRoots()) do
		applyToInstance(root, values, changedKeys)
		for _, inst in ipairs(root:GetDescendants()) do
			applyToInstance(inst, values, changedKeys)
		end
	end

	applyScriptColors(values)
	local tl = getTimeline and getTimeline() or nil
	local keyframesChanged = not changedKeys
	for key in changedKeys or {} do
		local field = ThemeConfig.scriptColorMap[key]
		if ThemeConfig.scriptHandleMap[key] or field and field:find("KEYFRAME", 1, true) then
			keyframesChanged = true
			break
		end
	end

	if tl and keyframesChanged then
		pcall(function()
			if tl.RefreshAllKeyframeVisuals then
				tl:RefreshAllKeyframeVisuals()
			end

			if tl.RefreshAllChannelDiamondColors then
				tl:RefreshAllChannelDiamondColors()
			end
		end)
	end

	for _, cb in ipairs(changedCallbacks) do
		pcall(cb, changedKeys)
	end
end

local function persist()
	if not setSetting then
		return
	end

	local encoded = Theme.encode()
	local wanted = HttpService:JSONDecode(encoded)
	local ok, err = pcall(function()
		if updateSetting and persistedTheme then
			local before = persistedTheme
			updateSetting(ThemeConfig.settingKey, function(saved)
				local current = type(saved) == "string" and HttpService:JSONDecode(saved) or saved
				assert(
					current == nil or type(current) == "table" and current.V == ThemeConfig.version,
					"The saved theme cannot be safely updated"
				)
				if current == nil then
					return encoded
				end

				current = table.clone(current)
				local equal = require("ChannelEasing").equal
				local keys = {}
				for k in before do
					keys[k] = true
				end

				for k in wanted do
					keys[k] = true
				end

				for k in keys do
					if not equal(before[k], wanted[k]) then
						current[k] = wanted[k]
					end
				end

				return HttpService:JSONEncode(current)
			end)
		else
			setSetting(ThemeConfig.settingKey, encoded)
		end
	end)
	if not ok then
		require("Notification").show(
			"THEME NOT SAVED",
			tostring(err) .. " Your saved theme has been kept; retry your change.",
			8
		)
		return false
	end

	persistedTheme = wanted
	return true
end

function Theme.get(key, fallback)
	local values = effectiveValues()
	local v = values[key]
	if v and v.stops then
		return v.stops[1]
	end

	return fallback
end

function Theme.videoPalette()
	local values = effectiveValues()
	local result = {}
	for _, key in { "Bg", "Pnl", "TopBtn", "MenuSel", "Txt", "Strk", "Div" } do
		local value = values[key] or Theme.sampleDefaultValue(key)
		local colors = {}
		for _, color in value.stops do
			table.insert(colors, "#" .. color:ToHex())
		end

		result[key] = colors
	end

	return result
end

function Theme.getOverride(key)
	return overrides[key] or baseValues()[key]
end

function Theme.getPresetRevision()
	return presetRevision
end

function Theme.isGradient(key)
	local v = effectiveValues()[key]
	return v ~= nil and #v.stops > 1
end

local function writeKey(key, value)
	local expansions = ThemeConfig.simpleExpand[key]
	if expansions then
		for _, e in ipairs(expansions) do
			overrides[e.target] = value and shadeValue(value, e.mod, e.amt) or nil
		end
	else
		overrides[key] = value
	end
end

local function reportProgress(callback, done, total, state)
	if callback then
		pcall(callback, done, total, state)
	end
end

local function cancelLoad()
	requestRevision += 1
	local previous = activeProgress
	activeProgress = nil
	reportProgress(previous, 0, 1, "cancelled")
end

local function prepareImage(value, title, request, progress)
	if not value or not value.frames then
		return true
	end

	local frames = value.mode == "image"
			and { { image = value.image or value.frames[1].image, delay = 100 } }
		or GifBackground.effectiveFrames(value.frames)
	if not frames then
		return false
	end

	if not GifBackground.needsLoad(frames) then
		reportProgress(progress, 1, 1, "complete")
		return true
	end

	activeProgress = progress
	reportProgress(progress, 0, #frames, "loading")

	local function cancelled()
		return request ~= requestRevision
	end

	local completed, ok, reason, id, details = pcall(GifBackground.preload, frames, function(
		done,
		total
	)
		if not cancelled() then
			reportProgress(progress, done, total, "loading")
		end
	end, cancelled)
	if cancelled() then
		return false
	end

	activeProgress = nil
	if completed and reason == "cancelled" then
		reportProgress(progress, 0, 1, "cancelled")
		return false
	end

	local partial = completed
		and not ok
		and reason ~= "cancelled"
		and details
		and details.loaded > 0
	reportProgress(
		progress,
		ok and completed and 1 or partial and details.loaded or 0,
		partial and details.total or 1,
		ok and completed and "complete" or partial and "partial" or "failed"
	)
	if not completed or not ok then
		if reason == "cancelled" then
			return false
		end

		local message = "GIF image loading failed. Your saved preset has been kept."
		if partial then
			return true
		elseif completed then
			local described, text = pcall(GifBackground.loadMessage, reason, id)
			if described then
				message = text
			end
		end

		require("Notification").show(title or "GIF BACKGROUND", message, 8)
	end

	return completed and (ok or partial) or false
end

function Theme.cancelLoad()
	cancelLoad()
end

function Theme.set(key, value, transient)
	cancelLoad()
	if key == "Img" and not prepareImage(value, "GIF background", requestRevision) then
		return false
	end

	writeKey(key, value)
	local affected = {}
	local expansions = ThemeConfig.simpleExpand[key]
	if expansions then
		for _, entry in expansions do
			affected[entry.target] = true
		end
	else
		affected[key] = true
	end

	if affected.Strk then
		affected.Div = true
	end

	Theme.apply(affected)
	if not transient then
		persist()
	end
end

function Theme.setBackgroundTransparency(value)
	assert(type(value) == "number" and value == value, "Invalid background transparency")
	local previous = Theme.getOverride("Img")
	local image = previous and table.clone(previous)
		or { image = "", stops = { Color3.new(1, 1, 1) } }
	image.t = math.clamp(value, 0, 1)
	writeKey("Img", image)
	Theme.apply({ Img = true })
	persist()
	return true
end

local restingCache

function Theme.restingTransparency(key)
	if not restingCache then
		const tallies = {}
		for _, root in allRoots() do
			for _, inst in root:GetDescendants() do
				const tagged = inst:IsA("GuiObject") and inst:GetAttribute("ThemeBg")
				if tagged then
					const original = getOriginal(inst, "BackgroundTransparency")
					const value = math.round(
						(typeof(original) == "number" and original or inst.BackgroundTransparency) * 100
					) / 100
					const counts = tallies[tagged] or {}
					tallies[tagged] = counts
					counts[value] = (counts[value] or 0) + 1
				end
			end
		end

		restingCache = {}
		for tagged, counts in tallies do
			local best, most = nil, 0
			for value, count in counts do
				if count > most or count == most and value < best then
					best, most = value, count
				end
			end

			restingCache[tagged] = best
		end
	end

	return restingCache[key]
end

function Theme.getBackgroundLayout()
	local image = Theme.getOverride("Img")
	return backgroundLayout(image and image.layout)
end

function Theme.setBackgroundLayout(value)
	local previous = Theme.getOverride("Img")
	local image = previous and table.clone(previous)
		or { image = "", t = 0.85, stops = { Color3.new(1, 1, 1) } }
	image.layout = backgroundLayout(value)
	writeKey("Img", image)
	Theme.apply({ Img = true })
	persist()
	return true
end

function Theme.setBackgroundMode(nextMode)
	if nextMode ~= "image" and nextMode ~= "gif" then
		return false
	end

	local previous = Theme.getOverride("Img")
	if nextMode == "gif" and not (previous and previous.frames) then
		return false
	end

	local value = previous and table.clone(previous)
		or { image = "", t = 0.85, stops = { Color3.new(1, 1, 1) } }
	value.mode = nextMode
	if nextMode == "image" and value.frames and not value.image then
		value.image = value.frames[1].image
	end

	Theme.set("Img", value)
	return true
end

function Theme.clear(key)
	cancelLoad()
	writeKey(key, nil)
	Theme.apply()
	persist()
end

function Theme.getMode()
	return mode
end

function Theme.setMode(m)
	if m ~= "S" and m ~= "A" then
		return
	end

	if mode == m then
		return persist()
	end

	mode = m
	Theme.apply()
	return persist()
end

function Theme.resetAll()
	oldEclipse = false
	cancelLoad()
	presetRevision += 1
	overrides = {}
	Theme.apply()
	persist()
end

function Theme.encode()
	local out = { V = ThemeConfig.version, M = mode, OldEclipse = oldEclipse or nil }
	for key, v in pairs(effectiveValues()) do
		if key == "Img" then
			if v.layout then
				out.ImgLayout = backgroundLayout(v.layout)
			end

			if v.frames then
				out.Gif = GifSequence.encode(v.frames)
				if ThemeConfig.isKoiFrames(v.frames) then
					out.KoiPalette = 2
					out.KoiFrames = 3
				end
			end

			if v.frames then
				out.ImgMode = v.mode == "image" and "image" or "gif"
			end

			if v.image and v.image ~= "" then
				out.Img = v.image:gsub("rbxassetid://", "")
			end

			if v.t then
				out.Imgt = v.t
			end
		else
			local s = Theme.formatValue(v)
			if s then
				out[key] = s
				if v.t then
					out[key .. "t"] = v.t
				end
			end
		end
	end

	return HttpService:JSONEncode(out)
end

local function knownKeys()
	local known = {}
	for _, s in ipairs(ThemeConfig.settings) do
		known[s.key] = true
	end

	for _, s in ipairs(ThemeConfig.simpleSettings) do
		known[s.key] = true
	end

	return known
end

function Theme.load(json, title, progress, transient)
	local data = json
	if typeof(json) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(json)
		end)
		if not ok then
			return false
		end

		data = decoded
	end

	if typeof(data) ~= "table" then
		return false
	end

	local known = knownKeys()
	data = ThemeConfig.migratePreset(data)
	local newOverrides = {}
	for key, raw in pairs(data) do
		if known[key] and key ~= "Img" and typeof(raw) == "string" then
			local v = Theme.parseValue(raw)
			if v then
				local t = tonumber(data[key .. "t"])
				if t then
					v.t = math.clamp(t, 0, 1)
				end

				local expansions = ThemeConfig.simpleExpand[key]
				if expansions then
					for _, e in ipairs(expansions) do
						newOverrides[e.target] = shadeValue(v, e.mod, e.amt)
					end
				else
					newOverrides[key] = v
				end
			end
		end
	end

	if data.Gif ~= nil then
		local frames = GifSequence.normalize(data.Gif)
		if not frames then
			return false
		end

		newOverrides.Img = {
			frames = frames,
			t = math.clamp(tonumber(data.Imgt) or 0.85, 0, 1),
			stops = { Color3.new(1, 1, 1) },
		}
		if
			not data.KoiPalette
			and ThemeConfig.isKoiFrames(frames)
			and data.Loop == "#91c6b4>#407e77@90"
		then
			newOverrides.Loop = Theme.parseValue("#dba0b0>#407e77@90")
		end
	end

	local imgRaw = data.Img
	if typeof(imgRaw) == "number" then
		imgRaw = string.format("%.0f", imgRaw)
	end

	if typeof(imgRaw) == "string" and imgRaw ~= "" then
		if tonumber(imgRaw) then
			imgRaw = "rbxassetid://" .. imgRaw
		end

		local t = tonumber(data.Imgt)
		newOverrides.Img = newOverrides.Img
			or { t = t and math.clamp(t, 0, 1) or 0.85, stops = { Color3.new(1, 1, 1) } }
		newOverrides.Img.image = imgRaw
	end

	if not newOverrides.Img and tonumber(data.Imgt) then
		newOverrides.Img = {
			image = "",
			t = math.clamp(tonumber(data.Imgt), 0, 1),
			stops = { Color3.new(1, 1, 1) },
		}
	end

	if data.ImgLayout ~= nil then
		newOverrides.Img = newOverrides.Img
			or { image = "", t = 0.85, stops = {
				Color3.new(1, 1, 1),
			} }
		newOverrides.Img.layout = backgroundLayout(data.ImgLayout)
	end

	if newOverrides.Img and newOverrides.Img.frames then
		newOverrides.Img.mode = data.ImgMode == "image" and "image" or "gif"
		newOverrides.Img.image = newOverrides.Img.image or newOverrides.Img.frames[1].image
	end

	cancelLoad()
	if not prepareImage(newOverrides.Img, title, requestRevision, progress) then
		return false
	end

	presetRevision += 1
	oldEclipse = data.OldEclipse == true
	overrides = newOverrides
	if data.M == "S" or data.M == "A" then
		mode = data.M
	end

	Theme.apply()
	if not transient then
		persist()
	end

	return true
end

function Theme.resolveInstanceValue(inst, attrName)
	local key = inst:GetAttribute(attrName)
	if not key then
		return nil
	end

	local v = effectiveValues()[key]
	if v then
		local shadeAmt = inst:GetAttribute("ThemeShade")
		if typeof(shadeAmt) == "number" and shadeAmt ~= 0 then
			v = shadeValue(v, shadeAmt > 0 and "lighten" or "darken", math.abs(shadeAmt))
		end

		if attrName == "ThemeGrad" then
			return toSequence(v)
		end

		return v.stops[1]
	end

	local props = ATTR_PROPS[attrName]
	if props then
		local orig = getOriginal(inst, props[1])
		if orig ~= nil then
			return orig
		end
	end

	return nil
end

function Theme.sampleDefaultValue(key)
	local value = baseValues()[key]
	if value then
		return { stops = table.clone(value.stops), rot = value.rot, t = value.t }
	end

	if key == "Strk" or key == "Div" then
		return { stops = { Theme.panelOutlineDefault() } }
	end

	local expansions = ThemeConfig.simpleExpand[key]
	if expansions then
		return Theme.sampleDefaultValue(expansions[1].target)
	end

	if screenGui then
		local fallbackInst = nil
		for _, inst in ipairs(screenGui:GetDescendants()) do
			if inst:GetAttribute("ThemeGrad") == key then
				local orig = getOriginal(inst, "Color")
				local ok, live = pcall(function()
					return inst.Color
				end)
				local seq = (typeof(orig) == "ColorSequence" and orig) or (ok and live) or nil
				if typeof(seq) == "ColorSequence" then
					local kps = seq.Keypoints
					local rotOrig = getOriginal(inst, "Rotation")
					local okR, liveR = pcall(function()
						return inst.Rotation
					end)
					local rot = (typeof(rotOrig) == "number" and rotOrig) or (okR and liveR) or 90
					if #kps > 1 then
						return { stops = { kps[1].Value, kps[#kps].Value }, rot = rot }
					end

					return { stops = { kps[1].Value } }
				end
			elseif not fallbackInst then
				for attrName, props in pairs(ATTR_PROPS) do
					if attrName ~= "ThemeGrad" and inst:GetAttribute(attrName) == key then
						fallbackInst = { inst = inst, prop = props[1] }
						break
					end
				end
			end
		end

		if fallbackInst then
			local orig = getOriginal(fallbackInst.inst, fallbackInst.prop)
			local ok, live = pcall(function()
				return fallbackInst.inst[fallbackInst.prop]
			end)
			local v = (typeof(orig) == "Color3" and orig)
				or (ok and typeof(live) == "Color3" and live)
				or nil
			if v then
				return { stops = { v } }
			end
		end
	end

	return { stops = { Theme.sampleDefault(key) } }
end

function Theme.onChanged(cb)
	table.insert(changedCallbacks, cb)
	local connected = true
	return function()
		if not connected then
			return
		end

		connected = false
		local index = table.find(changedCallbacks, cb)
		if index then
			table.remove(changedCallbacks, index)
		end
	end
end

function Theme.applyTree(root)
	require("Motion").watchFloatingGui(root)
	local values = effectiveValues()
	applyToInstance(root, values)
	for _, inst in root:GetDescendants() do
		applyToInstance(inst, values)
	end
end

function Theme.applyInstance(inst)
	applyToInstance(inst, effectiveValues())
end

local function added(inst)
	if not (inst:IsA("GuiBase") or inst:IsA("UIBase") or inst:IsA("GuiBase3d")) then
		return
	end

	if appliedRevision[inst] == themeRevision then
		return
	end

	pendingTheme[inst] = true
	if themeQueued then
		return
	end

	themeQueued = true
	task.defer(function()
		themeQueued = false
		local batch = pendingTheme
		pendingTheme = setmetatable({}, { __mode = "k" })
		local values = effectiveValues()
		for object in batch do
			if object.Parent and appliedRevision[object] ~= themeRevision then
				applyToInstance(object, values)
			end
		end
	end)
end

function Theme.addRoot(gui)
	require("Motion").watchFloatingGui(gui)
	if not gui then
		return
	end

	for _, r in ipairs(extraRoots) do
		if r == gui then
			return
		end
	end

	table.insert(extraRoots, gui)
	restingCache = nil
	local connection = gui.DescendantAdded:Connect(added)
	gui.Destroying:Once(function()
		connection:Disconnect()
		local index = table.find(extraRoots, gui)
		if index then
			table.remove(extraRoots, index)
		end
	end)
	if initialized then
		local values = effectiveValues()
		applyToInstance(gui, values)
		for _, inst in ipairs(gui:GetDescendants()) do
			applyToInstance(inst, values)
		end
	end
end

function Theme.sampleDefault(key)
	if baseValues()[key] then
		return baseValues()[key].stops[1]
	end

	if key == "Strk" or key == "Div" then
		return Theme.panelOutlineDefault()
	end

	if not screenGui then
		return Color3.fromRGB(128, 128, 128)
	end

	for _, inst in ipairs(screenGui:GetDescendants()) do
		for attrName, props in pairs(ATTR_PROPS) do
			if inst:GetAttribute(attrName) == key then
				local orig = getOriginal(inst, props[1])
				local ok, live = pcall(function()
					return inst[props[1]]
				end)
				local v = orig or (ok and live) or nil
				if typeof(v) == "Color3" then
					return v
				end

				if typeof(v) == "ColorSequence" then
					return v.Keypoints[1].Value
				end
			end
		end
	end

	if timelineState and timelineState.Colors then
		local src = scriptOriginals
		local field = ThemeConfig.scriptColorMap[key]
		if field then
			return (src and src.flat[field])
				or timelineState.Colors[field]
				or Color3.fromRGB(128, 128, 128)
		end

		local hName = ThemeConfig.scriptHandleMap[key]
		if hName then
			return (src and src.handleD[hName])
				or timelineState.Colors.KEYFRAME_HANDLE_DEFAULT[hName]
				or Color3.fromRGB(128, 128, 128)
		end
	end

	local sd = ThemeConfig.scriptDefaults and ThemeConfig.scriptDefaults[key]
	if sd then
		local v = Theme.parseValue(sd)
		if v then
			return v.stops[1]
		end
	end

	return Color3.fromRGB(128, 128, 128)
end

function Theme.init(refs)
	local Preferences = require("Preferences")
	GifBackground.setPlaybackMode(Preferences.get("GifPlayback"))
	if initialized then
		return
	end

	screenGui = refs.ScreenGui
	getSetting = refs.GetSetting
	setSetting = refs.SetSetting
	updateSetting = refs.UpdateSetting
	timelineState = refs.TimelineState
	getTimeline = refs.GetTimeline
	if not screenGui then
		return
	end

	initialized = true

	screenGui.DescendantAdded:Connect(added)

	local read, saved = pcall(function()
		return getSetting and getSetting(ThemeConfig.settingKey)
	end)
	if not read then
		warn("[Eclipse theme] The saved theme could not be read: " .. tostring(saved))
		saved = nil
	end

	local pending
	local pendingRevision = presetRevision

	local function restore(value)
		const ok, issue = pcall(Theme.load, value, nil, nil, true)
		if ok then
			return
		end

		warn("[Eclipse theme] The saved theme could not be applied and was kept unchanged. Default colors are shown.\n" .. tostring(issue))
		pending = nil
		overrides = {}
		pcall(Theme.apply)
	end

	if typeof(saved) == "string" and saved ~= "" then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		if ok and type(data) == "table" and data.Gif then
			pending = saved
			local palette = table.clone(data)
			palette.Gif = nil
			palette.Img = nil
			palette.Imgt = nil
			palette.ImgMode = nil
			restore(palette)
			pendingRevision = presetRevision
		else
			restore(saved)
		end
	else
		Theme.apply()
	end

	persistedTheme = HttpService:JSONDecode(Theme.encode())

	local function opened()
		if not screenGui.Enabled then
			cancelLoad()
			return
		end

		if
			getSetting
			and persistedTheme
			and require("ChannelEasing").equal(
				HttpService:JSONDecode(Theme.encode()),
				persistedTheme
			)
		then
			local read, latest = pcall(getSetting, ThemeConfig.settingKey)
			if read and type(latest) == "string" and latest ~= "" and latest ~= saved then
				local decoded, data = pcall(HttpService.JSONDecode, HttpService, latest)
				if decoded and type(data) == "table" and data.V == ThemeConfig.version then
					if Theme.load(latest, "saved theme", nil, true) then
						saved = latest
						pending = nil
						persistedTheme = HttpService:JSONDecode(Theme.encode())
						return
					end
				end
			end
		end

		if pending and pendingRevision == presetRevision then
			local deferred = HttpService:JSONDecode(pending)
			local current = HttpService:JSONDecode(Theme.encode())
			for k, v in current do
				if k ~= "Gif" and k ~= "Img" and k ~= "Imgt" and k ~= "ImgMode" then
					deferred[k] = v
				end
			end

			if Theme.load(deferred, "saved GIF preset", nil, true) then
				pending = nil
				persistedTheme = HttpService:JSONDecode(Theme.encode())
			end
		else
			pending = nil
			local image = overrides.Img
			if image and image.frames then
				Theme.load(Theme.encode(), "GIF background", nil, true)
			end
		end
	end

	local opening = screenGui:GetPropertyChangedSignal("Enabled"):Connect(opened)
	local preference = Preferences.subscribe(function(key)
		if key == "GifPlayback" then
			GifBackground.setPlaybackMode(Preferences.get("GifPlayback"))
			cancelLoad()
			if pending and pendingRevision == presetRevision then
				task.defer(opened)
				return
			end

			local image = overrides.Img
			if image and image.frames then
				Theme.load(Theme.encode(), "GIF background", nil, true)
			end
		end
	end)
	screenGui.Destroying:Once(function()
		cancelLoad()
		opening:Disconnect()
		preference()
		GifBackground.destroy()
	end)
	task.defer(opened)
end

return Theme
