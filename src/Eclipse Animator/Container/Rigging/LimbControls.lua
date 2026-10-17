--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local R6Controls = require("R6Controls")
local LimbIK = require("LimbIK")

local LimbControls = {}
local displayScales = setmetatable({}, { __mode = "k" })
local proxies = setmetatable({}, { __mode = "k" })
local proxyChains = setmetatable({}, { __mode = "k" })
local ROOT = {
	CFrame = CFrame.identity,
	Name = "IK",
	IsA = function(_, class)
		return class == "BasePart"
	end,
}
local COLOR = Color3.fromRGB(145, 90, 255)
local POLE_COLOR = Color3.fromRGB(255, 170, 60)
local DIAMETER = 22
local HIT_RADIUS = DIAMETER * 0.5 + 4
local MAX_RADIUS = 0.3

local function makeMarker(folder, chain, kind)
	local part = Instance.new("Part")
	part.Name = chain.owner.Part1.Name .. "_IK_" .. kind
	part.Size = Vector3.one * 0.2
	part.Shape = Enum.PartType.Ball
	part.Anchored, part.Locked = true, true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.CastShadow = false
	part.Transparency = 1
	part:SetAttribute("SourcePartName", chain.owner.Part1.Name)
	part:SetAttribute("EclipseLimbControl", kind)
	local color = kind == "roll" and Color3.fromRGB(98, 218, 168)
		or chain.kind == "R15" and kind == "root" and Color3.fromRGB(100, 190, 255)
		or kind == "pole" and POLE_COLOR
		or COLOR
	part:SetAttribute("MarkerColor", color)
	local owner = Instance.new("ObjectValue")
	owner.Name, owner.Value, owner.Parent =
		"EclipseLimbOwner", R6Controls.ownerInstance(chain.owner), part
	local rectangular = chain.kind == "R6" and chain.limb == "Leg" and kind == "pole"
	local handle = Instance.new(rectangular and "BoxHandleAdornment" or "SphereHandleAdornment")
	handle.Name = "Handle"
	handle.Adornee = part
	handle.AlwaysOnTop = true
	handle.ZIndex = 1
	if rectangular then
		handle.Size = Vector3.new(0.16, 0.12, 0.36)
	else
		handle.Radius = 0.1
	end

	handle.Color3 = color
	handle.Transparency = 0.3
	handle.Visible = false
	handle.Parent = part
	if kind == "pole" then
		local link = Instance.new("LineHandleAdornment")
		link.Name = "Link"
		link.Adornee = part
		link.AlwaysOnTop = true
		link.ZIndex = 0
		link.Thickness = 1.5
		link.Color3 = color
		link.Transparency = 0.45
		link.Visible = false
		link.Parent = part
	end

	part.Parent = folder
	return part
end

function LimbControls.create(rig, folder)
	local entry = LimbIK.getRig(rig)
	if not entry then
		return
	end

	for _, chain in entry.chains do
		if chain.kind == "Torso" then
			makeMarker(folder, chain, "spine")
			makeMarker(folder, chain, "upper")
		elseif chain.kind == "R15" then
			makeMarker(folder, chain, "target")
			makeMarker(folder, chain, "pole")
			makeMarker(folder, chain, "root")
			if chain.limb == "Leg" then
				makeMarker(folder, chain, "roll")
			end
		else
			makeMarker(folder, chain, "target")
			makeMarker(folder, chain, chain.kind == "R15" and "pole" or "root")
			if chain.kind == "R6" and chain.limb == "Leg" then
				makeMarker(folder, chain, "pole")
			end
		end
	end
end

function LimbControls.update(rig, folder, camera)
	local entry = LimbIK.getRig(rig)
	if not entry then
		return
	end

	local scale = rig:IsA("Model") and rig:GetScale() or 1
	displayScales[folder] = scale
	local states = {}
	for _, part in folder:GetChildren() do
		local kind = part:GetAttribute("EclipseLimbControl")
		local reference = kind and part:FindFirstChild("EclipseLimbOwner")
		local chain = reference and entry.owners[R6Controls.resolveOwner(reference.Value)]
		if not chain then
			continue
		end

		local state = states[chain]
		if state == nil then
			state = LimbIK.state(chain) or false
			states[chain] = state
		end

		if state == false then
			state = nil
		end

		local handle = part:FindFirstChild("Handle")
		local control = state and LimbIK.controlMotor(chain, kind)
		local visible = state ~= nil
			and LimbIK.isEnabled(chain.owner, state.time)
			and not folder:GetAttribute("EclipsePlaybackHidden")
			and not chain.owner:GetAttribute("EclipseDisabled")
			and not (control and control:GetAttribute("EclipseDisabled"))
			and not (
				chain.kind == "R6"
				and kind == "pole"
				and require("Preferences").get("R6IKLegPole") == false
			)
		part.CanQuery = visible
		if handle then
			handle.Visible = visible
		end

		local link = part:FindFirstChild("Link")
		if link then
			link.Visible = visible
		end

		if visible then
			part.CFrame = LimbIK.controlFrame(chain, kind, state)
			local depth = math.max(1, camera.CFrame:PointToObjectSpace(part.Position).Z * -1)
			local radius = math.max(
				0.01,
				depth
					* math.tan(math.rad(camera.FieldOfView * 0.5))
					* DIAMETER
					/ math.max(camera.ViewportSize.Y, 1)
			)
			radius = math.min(radius, MAX_RADIUS) * scale
			part.Size = Vector3.one * radius * 2.4
			if handle then
				if handle:IsA("BoxHandleAdornment") then
					part.Shape = Enum.PartType.Block
					part.Size = Vector3.new(radius * 1.6, radius * 1.2, radius * 3.6)
					handle.Size = part.Size
				else
					handle.Radius = radius
				end
			end

			if link then
				link.Thickness = 1.5 * scale
				local _, knee = LimbIK.geometry(chain)
				local offset = part.CFrame:PointToObjectSpace(knee)
				link.Visible = offset.Magnitude > 1e-3
				if link.Visible then
					link.CFrame = CFrame.lookAt(Vector3.zero, offset)
					link.Length = offset.Magnitude
				end
			end
		end
	end
end

function LimbControls.hitTest(camera, mouse, folders)
	local nearest, best = nil, math.huge
	for _, folder in folders do
		for _, part in folder:GetChildren() do
			if not part:GetAttribute("EclipseLimbControl") then
				continue
			end

			local handle = part:FindFirstChild("Handle")
			if not handle or not handle.Visible then
				continue
			end

			local point, visible = camera:WorldToViewportPoint(part.Position)
			if not visible then
				continue
			end

			local distance = (Vector2.new(point.X, point.Y) - mouse).Magnitude
			if distance <= HIT_RADIUS * (displayScales[folder] or 1) and distance < best then
				nearest, best = part, distance
			end
		end
	end

	return nearest
end

function LimbControls.getMotor(rig, bone, motor)
	local reference = bone and bone:FindFirstChild("EclipseLimbOwner")
	local r6Control = typeof(motor) == "table" and motor.IsEclipseR6Control
	local chain = LimbIK.chain(
		rig,
		r6Control and motor.Owner or reference and R6Controls.resolveOwner(reference.Value) or motor
	)
	local upperFK = false
	if not chain and motor then
		local driven = LimbIK.drivingChain(motor, require("RawState").Timeline.CurrentTime)
		if driven and driven.kind == "R15" and driven.motors[1] == motor then
			chain, upperFK = driven, true
		end
	end

	local state = chain and LimbIK.state(chain)
	if not state or not LimbIK.isEnabled(chain.owner, state.time) then
		return nil
	end

	local kind = upperFK and "upperFK"
		or r6Control and motor:GetAttribute("EclipseR6Control")
		or bone:GetAttribute("EclipseLimbControl")
		or "target"
	if chain.kind == "Torso" and kind == "target" then
		kind = "fk"
	end

	local proxy = proxies[bone]
	if proxy and proxyChains[proxy] == chain and proxy.ControlKind == kind then
		return proxy
	end

	proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "ControlKind" then
				return kind
			elseif key == "C0" then
				local state = LimbIK.state(chain)
				return state and LimbIK.controlFrame(chain, kind, state) or bone.CFrame
			elseif key == "C1" then
				return CFrame.identity
			elseif key == "Part0" then
				return ROOT
			elseif key == "Part1" then
				return bone
			elseif key == "RealPart0" then
				return nil
			elseif key == "Parent" then
				return chain.owner.Parent
			elseif key == "Name" then
				return bone.Name
			elseif key == "IsTranslationOnly" then
				return kind == "root" or kind == "pole"
			elseif key == "Enabled" or key == "IsEclipseIKHandle" then
				return true
			elseif key == "IsA" then
				return function(_, class)
					return class == "Motor6D"
				end
			elseif key == "GetAttribute" then
				return function(_, attr)
					return chain.owner:GetAttribute(attr)
				end
			elseif key == "SetAttribute" then
				return function(_, attr, value)
					chain.owner:SetAttribute(attr, value)
				end
			elseif key == "GetFullName" then
				return function()
					return bone:GetFullName()
				end
			end
		end,
		__newindex = function(_, key, value)
			if key == "C0" then
				LimbIK.setDisplayControl(chain, kind, value)
			end
		end,
	})
	proxies[bone] = proxy
	proxyChains[proxy] = chain
	return proxy
end

return LimbControls
