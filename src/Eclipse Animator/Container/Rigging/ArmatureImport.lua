--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local StudioService = game:GetService("StudioService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require("Theme")
local Notification = require("Notification")

local ArmatureConverter = require("ArmatureConverter")
local ArmatureGeometry = require("distance")
local ArmatureRuntime = require("ArmatureRuntime")

local Chrome = require("Chrome")
local ArmatureImport = {}

local LINE_TRANSPARENCY = 0
local SOLID_FILL_TRANSPARENCY = 0.6
local ANCHOR_MIN_SIZE = 0.05
local MAX_PRIMITIVES = 40000
local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local FADE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screenGui = nil
local window = nil
local windowTarget = nil
local importing = false

local function toColor3(v)
	if typeof(v) ~= "table" or #v < 3 then
		return nil
	end

	local r, g, b = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
	if not r or not g or not b then
		return nil
	end

	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

local function distinctSelectColor(normal, sel)
	if not sel then
		return normal:Lerp(Color3.new(1, 1, 1), 0.6)
	end

	local delta = math.abs(sel.R - normal.R)
		+ math.abs(sel.G - normal.G)
		+ math.abs(sel.B - normal.B)
	if delta < 0.25 then
		return sel:Lerp(Color3.new(1, 1, 1), 0.6)
	end

	return sel
end

local function toVector3(v)
	if typeof(v) ~= "table" or #v < 3 then
		return nil
	end

	local x, y, z = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
	if not x or not y or not z then
		return nil
	end

	return Vector3.new(x, y, z)
end

local function boxEdges(size)
	local h = size / 2
	local c = {
		Vector3.new(-h.X, -h.Y, -h.Z),
		Vector3.new(h.X, -h.Y, -h.Z),
		Vector3.new(h.X, h.Y, -h.Z),
		Vector3.new(-h.X, h.Y, -h.Z),
		Vector3.new(-h.X, -h.Y, h.Z),
		Vector3.new(h.X, -h.Y, h.Z),
		Vector3.new(h.X, h.Y, h.Z),
		Vector3.new(-h.X, h.Y, h.Z),
	}
	local idx = {
		{ 1, 2 },
		{ 2, 3 },
		{ 3, 4 },
		{ 4, 1 },
		{ 5, 6 },
		{ 6, 7 },
		{ 7, 8 },
		{ 8, 5 },
		{ 1, 5 },
		{
			2,
			6,
		},
		{
			3,
			7,
		},
		{
			4,
			8,
		},
	}
	local out = {}
	for _, e in ipairs(idx) do
		table.insert(out, { c[e[1]], c[e[2]] })
	end

	return out
end

local function makeAnchor(center, size)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(
		math.max(size.X, ANCHOR_MIN_SIZE),
		math.max(size.Y, ANCHOR_MIN_SIZE),
		math.max(size.Z, ANCHOR_MIN_SIZE)
	)
	part.CFrame = CFrame.new(center)
	return part
end

local function buildRig(data, xform)
	local rigModel = Instance.new("Model")
	rigModel.Name = (typeof(data.name) == "string" and data.name ~= "" and data.name) or "Armature"
	rigModel:SetAttribute("EclipseArmature", true)

	local anchors = {}
	local order = {}

	for _, boneData in ipairs(data.bones) do
		if typeof(boneData.name) ~= "string" then
			continue
		end

		local normal = toColor3(boneData.color) or Color3.fromRGB(120, 120, 120)
		local isSolid = boneData.solid == true and typeof(boneData.tris) == "table"
		local isHidden = boneData.hidden == true

		local mn = nil
		local mx = nil

		local function acc(v)
			if not mn then
				mn = v
				mx = v
			end

			mn = Vector3.new(math.min(mn.X, v.X), math.min(mn.Y, v.Y), math.min(mn.Z, v.Z))
			mx = Vector3.new(math.max(mx.X, v.X), math.max(mx.Y, v.Y), math.max(mx.Z, v.Z))
		end

		local edgeList = {}
		if isSolid then
			for _, tri in ipairs(boneData.tris) do
				for _, pt in ipairs(tri) do
					local v = toVector3(pt)
					if v then
						if xform then
							v = xform(v)
						end

						acc(v)
					end
				end
			end
		else
			for _, edge in ipairs(boneData.edges or {}) do
				local a = toVector3(edge[1])
				local b = toVector3(edge[2])
				if a and b then
					if xform then
						a = xform(a)
						b = xform(b)
					end

					acc(a)
					acc(b)
					table.insert(edgeList, { a, b })
				end
			end
		end

		if mn then
			local center = (mn + mx) / 2
			local size = mx - mn

			local anchor = makeAnchor(center, size)
			anchor.Name = boneData.name
			anchor:SetAttribute("EclipseArmatureBone", true)
			anchor:SetAttribute("Solid", isSolid)
			anchor:SetAttribute("Hidden", isHidden)
			anchor:SetAttribute("BoneColor", normal)
			local sel = toColor3(boneData.select)
			if sel then
				anchor:SetAttribute("SelectColor", sel)
			end

			if boneData.deform == true then
				anchor:SetAttribute("EclipseDeform", true)
			end

			if typeof(boneData.chain_parent) == "string" then
				anchor:SetAttribute("EclipseChainParent", boneData.chain_parent)
			end

			local activeColor = toColor3(boneData.active)
			if activeColor then
				anchor:SetAttribute("ActiveColor", activeColor)
			end

			local head = toVector3(boneData.head)
			local tail = toVector3(boneData.tail)
			if xform then
				if head then
					head = xform(head)
				end

				if tail then
					tail = xform(tail)
				end
			end

			if head then
				anchor:SetAttribute("Head", head)
				anchor.PivotOffset = CFrame.new(head - center)
			end

			if tail then
				anchor:SetAttribute("Tail", tail)
			end

			if boneData.parent ~= nil then
				anchor:SetAttribute("ParentBone", tostring(boneData.parent))
			end

			anchor:SetAttribute("EclipseDesignRot", CFrame.new())
			if not isHidden then
				local selColor = distinctSelectColor(normal, toColor3(boneData.select))
				if isSolid then
					local fill = Instance.new("BoxHandleAdornment")
					fill.Name = "XRayFill"
					fill.Adornee = anchor
					fill.AlwaysOnTop = true
					fill.ZIndex = 0
					fill.Size = size
					fill.Color3 = normal
					fill.Transparency = SOLID_FILL_TRANSPARENCY
					fill.Parent = anchor
					local edges = boxEdges(size)
					local wire = Instance.new("WireframeHandleAdornment")
					wire.Name = "XRayEdges"
					wire.Adornee = anchor
					wire.AlwaysOnTop = true
					wire.ZIndex = 1
					wire.Color3 = normal
					wire.Transparency = LINE_TRANSPARENCY
					local wireSel = Instance.new("WireframeHandleAdornment")
					wireSel.Name = "XRayEdgesSelect"
					wireSel.Adornee = anchor
					wireSel.AlwaysOnTop = true
					wireSel.ZIndex = 1
					wireSel.Color3 = selColor
					wireSel.Transparency = LINE_TRANSPARENCY
					wireSel.Visible = false
					for _, e in ipairs(edges) do
						wire:AddLine(e[1], e[2])
						wireSel:AddLine(e[1], e[2])
					end

					wire.Parent = anchor
					wireSel.Parent = anchor
				else
					local wire = Instance.new("WireframeHandleAdornment")
					wire.Name = "XRayEdges"
					wire.Adornee = anchor
					wire.AlwaysOnTop = true
					wire.ZIndex = 1
					wire.Color3 = normal
					wire.Transparency = LINE_TRANSPARENCY
					local wireSel = Instance.new("WireframeHandleAdornment")
					wireSel.Name = "XRayEdgesSelect"
					wireSel.Adornee = anchor
					wireSel.AlwaysOnTop = true
					wireSel.ZIndex = 1
					wireSel.Color3 = selColor
					wireSel.Transparency = LINE_TRANSPARENCY
					wireSel.Visible = false
					for _, e in ipairs(edgeList) do
						wire:AddLine(e[1] - center, e[2] - center)
						wireSel:AddLine(e[1] - center, e[2] - center)
					end

					wire.Parent = anchor
					wireSel.Parent = anchor
				end
			end

			anchors[boneData.name] = anchor
			table.insert(order, { anchor = anchor, parent = boneData.parent })
		end
	end

	for _, o in ipairs(order) do
		o.anchor.Parent = rigModel
	end

	return rigModel
end

local function findArmature(rig)
	if not rig then
		return nil
	end

	for _, desc in ipairs(require("RigTraversal").descendants(rig)) do
		if desc:IsA("Model") and desc:GetAttribute("EclipseArmature") then
			return desc
		end
	end

	return nil
end

local function rigRootOf(inst)
	local root = inst
	while root.Parent and root.Parent:IsA("Model") and not root.Parent:IsA("WorldRoot") do
		root = root.Parent
	end

	return root
end

ArmatureImport.find = findArmature

function ArmatureImport.setAnchorSelected(anchor, selected)
	if not anchor or not anchor.Parent then
		return
	end

	ArmatureGeometry.select(anchor, selected)
	if anchor:GetAttribute("EclipseArmatureBoneId") then
		ArmatureGeometry.setVisible(
			anchor,
			anchor:GetAttribute("Hidden") ~= true
				and anchor:GetAttribute("EclipseArmatureControl") ~= false
		)
		return
	end

	local visible = anchor:GetAttribute("Hidden") ~= true
		and require("Organization").isBoneVisible(anchor)
	anchor.CanQuery = visible
	local wire = anchor:FindFirstChild("XRayEdges")
	local wireSel = anchor:FindFirstChild("XRayEdgesSelect")
	if wire and wireSel then
		wire.Visible = visible and not selected
		wireSel.Visible = visible and selected
	else
		local glow = anchor:FindFirstChild("EclipseSelectGlow")
		if not glow then
			glow = Instance.new("BoxHandleAdornment")
			glow.Name = "EclipseSelectGlow"
			glow.Adornee = anchor
			glow.AlwaysOnTop = true
			glow.ZIndex = 0
			glow.Size = anchor.Size
			local base = anchor:GetAttribute("BoneColor")
			local sel = anchor:GetAttribute("SelectColor")
			if typeof(base) == "Color3" then
				glow.Color3 = distinctSelectColor(base, typeof(sel) == "Color3" and sel or nil)
			else
				glow.Color3 = Color3.new(1, 1, 1)
			end

			glow.Transparency = 1
			glow.Parent = anchor
		end

		glow.Transparency = visible and selected and 0.5 or 1
	end

	local fill = anchor:FindFirstChild("XRayFill")
	if fill then
		fill.Visible = visible
		local base = anchor:GetAttribute("BoneColor")
		if typeof(base) == "Color3" then
			local sel = anchor:GetAttribute("SelectColor")
			local target = selected
					and distinctSelectColor(base, typeof(sel) == "Color3" and sel or nil)
				or base
			fill.Color3 = target
		end
	end
end

local function aiWorldOf(inst)
	if inst:IsA("Bone") then
		return aiWorldOf(inst.Parent) * inst.CFrame * inst.Transform
	end

	return inst.CFrame
end

local function rotationBetween(a, b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.9999 then
		return CFrame.identity
	end

	if dot < -0.9999 then
		local ortho = math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis
		local axis = a:Cross(ortho).Unit
		return CFrame.fromAxisAngle(axis, math.pi)
	end

	local axis = a:Cross(b).Unit
	return CFrame.fromAxisAngle(axis, math.acos(dot))
end

local function bindAnchors(arm, rig)
	if not arm or not rig then
		return
	end

	if arm:FindFirstChild("EclipseArmatureGraph") then
		ArmatureConverter.attach(arm, rig)
		return
	end

	local nameToBone = {}
	local rootBone = nil
	for _, d in ipairs(require("RigTraversal").descendants(rig)) do
		if d:IsA("Bone") then
			if not nameToBone[d.Name] then
				nameToBone[d.Name] = d
			end

			if not rootBone and not d.Parent:IsA("Bone") then
				rootBone = d
			end
		end
	end

	local anchorByName = {}
	local anyDeform = false
	for _, a in ipairs(arm:GetChildren()) do
		if a:IsA("BasePart") and a:GetAttribute("EclipseArmatureBone") then
			anchorByName[a.Name] = a
			if a:GetAttribute("EclipseDeform") == true then
				anyDeform = true
			end
		end
	end

	arm:SetAttribute("EclipseHasDeformData", anyDeform)
	if anyDeform then
		local deformList = {}
		for _, a in ipairs(arm:GetChildren()) do
			if a:IsA("BasePart") and a:GetAttribute("EclipseDeform") == true then
				table.insert(deformList, a)
			end
		end

		local rawParent = {}
		for _, a in ipairs(deformList) do
			local h = a:GetAttribute("Head")
			local t = a:GetAttribute("Tail")
			a:SetAttribute("EclipseChainParent", nil)
			if typeof(h) == "Vector3" and typeof(t) == "Vector3" then
				local myLen = (t - h).Magnitude
				local best = nil
				local bestD = math.huge
				for _, o in ipairs(deformList) do
					if o ~= a then
						local ot = o:GetAttribute("Tail")
						if typeof(ot) == "Vector3" then
							local dd = (ot - h).Magnitude
							if dd < bestD then
								best = o
								bestD = dd
							end
						end
					end
				end

				if best and myLen > 1e-4 and bestD < 0.5 * math.max(myLen, 0.05) then
					rawParent[a.Name] = best.Name
				end
			end
		end

		for _, a in ipairs(deformList) do
			if not a.Name:lower():find("twist", 1, true) then
				local parent = rawParent[a.Name]
				local guard = 0
				while
					typeof(parent) == "string"
					and parent:lower():find("twist", 1, true)
					and guard < 10
				do
					guard += 1
					parent = rawParent[parent]
				end

				if typeof(parent) == "string" and parent ~= a.Name then
					a:SetAttribute("EclipseChainParent", parent)
				end
			end
		end

		for _, a in ipairs(arm:GetChildren()) do
			if a:IsA("BasePart") and a:GetAttribute("EclipseDeform") == true then
				a:SetAttribute("EclipseSyncFrom", nil)
				a:SetAttribute("EclipseSyncOffset", nil)
				local deformBone = nameToBone[a.Name]
				if deformBone then
					local cursor = a:GetAttribute("ParentBone")
					local guard = 0
					local srcBone = nil
					while typeof(cursor) == "string" and guard < 60 do
						guard += 1
						local candidate = nameToBone[cursor]
						if candidate then
							srcBone = candidate
							break
						end

						local pa = anchorByName[cursor]
						cursor = pa and pa:GetAttribute("ParentBone") or nil
					end

					if
						srcBone
						and srcBone ~= deformBone
						and not srcBone:IsAncestorOf(deformBone)
						and not deformBone:IsAncestorOf(srcBone)
					then
						a:SetAttribute("EclipseSyncFrom", srcBone.Name)
						a:SetAttribute(
							"EclipseSyncOffset",
							aiWorldOf(srcBone):Inverse() * aiWorldOf(deformBone)
						)
					end
				end
			end
		end
	end

	for _, anchor in ipairs(arm:GetChildren()) do
		if anchor:IsA("BasePart") and anchor:GetAttribute("EclipseArmatureBone") then
			local bone = nameToBone[anchor.Name]
			if bone then
				local boneWorld = aiWorldOf(bone)
				local headLocal = anchor.PivotOffset.Position
				local headAttr = anchor:GetAttribute("Head")
				local tailAttr = anchor:GetAttribute("Tail")
				local rot = CFrame.identity
				if typeof(headAttr) == "Vector3" and typeof(tailAttr) == "Vector3" then
					local designDir = tailAttr - headAttr
					if designDir.Magnitude > 1e-4 then
						rot = rotationBetween(designDir.Unit, boneWorld.UpVector)
					end
				end

				local adjusted = CFrame.new(boneWorld.Position) * rot * CFrame.new(-headLocal)
				anchor.CFrame = adjusted
				anchor:SetAttribute("EclipseBindOffset", boneWorld:Inverse() * adjusted)
			else
				anchor:SetAttribute("EclipseIKEffector", nil)
				anchor:SetAttribute("EclipseIKChainKnee", nil)
				anchor:SetAttribute("EclipseIKChainHip", nil)
				anchor:SetAttribute("EclipseIKChainBones", nil)
				anchor:SetAttribute("EclipseIKFollowers", nil)
				anchor:SetAttribute("EclipseIKStiffness", nil)
				anchor:SetAttribute("EclipseIKLocks", nil)
				local lowerName = anchor.Name:lower()
				local hasIKData = arm:GetAttribute("EclipseHasIKData") == true
				local isIKControl = anchor:GetAttribute("EclipseIKConstraint") == true
					or (
						not hasIKData
						and lowerName:find("ik", 1, true)
						and anchor:GetAttribute("Hidden") ~= true
						and not lowerName:find("thigh", 1, true)
						and not lowerName:find("pole", 1, true)
						and not lowerName:find("target", 1, true)
						and not lowerName:find("track", 1, true)
					)
				if isIKControl then
					local head = anchor.CFrame:PointToWorldSpace(anchor.PivotOffset.Position)
					local hasDeformData = arm:GetAttribute("EclipseHasDeformData") == true
					local best = nil
					local bestDist = math.huge
					for _, b in ipairs(require("RigTraversal").descendants(rig)) do
						if b:IsA("Bone") and b.Parent:IsA("Bone") then
							local eligible
							if hasDeformData then
								local boneAnchor = anchorByName[b.Name]
								eligible = boneAnchor ~= nil
									and boneAnchor:GetAttribute("EclipseDeform") == true
									and not b.Name:lower():find("twist", 1, true)
							else
								local lower = b.Name:lower()
								eligible = b.CFrame.Position.Magnitude > 0.02
									and not lower:find("twist", 1, true)
									and not lower:find("stretch", 1, true)
							end

							if eligible then
								local dist = (aiWorldOf(b).Position - head).Magnitude
								if dist < bestDist then
									best = b
									bestDist = dist
								end
							end
						end
					end

					if best then
						anchor:SetAttribute("EclipseIKEffector", best.Name)
						anchor:SetAttribute(
							"EclipseIKEndOffset",
							anchor.CFrame:Inverse() * aiWorldOf(best)
						)
						local bestAnchor = anchorByName[best.Name]
						local kneeName = bestAnchor
							and bestAnchor:GetAttribute("EclipseChainParent")
						if typeof(kneeName) == "string" and nameToBone[kneeName] then
							anchor:SetAttribute("EclipseIKChainKnee", kneeName)
							local kneeAnchor = anchorByName[kneeName]
							local hipName = kneeAnchor
								and kneeAnchor:GetAttribute("EclipseChainParent")
							if typeof(hipName) == "string" and nameToBone[hipName] then
								anchor:SetAttribute("EclipseIKChainHip", hipName)
							end
						end
					end

					local chainDataStr = anchor:GetAttribute("EclipseIKChainData")
					if best and typeof(chainDataStr) == "string" then
						local okDec, chainData =
							pcall(HttpService.JSONDecode, HttpService, chainDataStr)
						if okDec and typeof(chainData) == "table" and #chainData > 0 then
							local effBone = best
							local resolvedNames = {}
							local usedNames = {}
							local segHeads = {}
							local segTails = {}
							local resolvedOk = true
							for ci, cbData in ipairs(chainData) do
								local cHead = toVector3(cbData.head)
								local cTail = toVector3(cbData.tail)
								if not cHead or not cTail then
									resolvedOk = false
									break
								end

								local cLen = (cTail - cHead).Magnitude
								segHeads[ci] = cHead
								segTails[ci] = cTail
								local bestName = nil
								local bestScore = nil
								for aName, cand in pairs(anchorByName) do
									local rigBone = nameToBone[aName]
									if rigBone and rigBone ~= effBone and not usedNames[aName] then
										local h = cand:GetAttribute("Head")
										local t = cand:GetAttribute("Tail")
										if typeof(h) == "Vector3" and typeof(t) == "Vector3" then
											local score = (h - cHead).Magnitude
												+ math.abs((t - h).Magnitude - cLen)
											if rigBone:IsAncestorOf(effBone) then
												score -= cLen * 0.05
											end

											if bestScore == nil or score < bestScore then
												bestScore = score
												bestName = aName
											end
										end
									end
								end

								if bestName and bestScore < cLen * 0.35 then
									resolvedNames[ci] = bestName
									usedNames[bestName] = true
								else
									resolvedOk = false
									break
								end
							end

							if resolvedOk then
								anchor:SetAttribute(
									"EclipseIKChainBones",
									table.concat(resolvedNames, ",")
								)
								local stiff = {}
								local locks = {}
								local haveStiff = false
								local haveLock = false
								for ci, cbData in ipairs(chainData) do
									local sv = cbData.stiffness
									local lk = cbData.lock
									if typeof(sv) == "table" then
										stiff[ci] = {
											tonumber(sv[1]) or 0,
											tonumber(sv[2]) or 0,
											tonumber(sv[3]) or 0,
										}
									else
										stiff[ci] = { 0, 0, 0 }
									end

									if typeof(lk) == "table" then
										locks[ci] = { lk[1] == true, lk[2] == true, lk[3] == true }
									else
										locks[ci] = { false, false, false }
									end

									if stiff[ci][1] > 0 or stiff[ci][2] > 0 or stiff[ci][3] > 0 then
										haveStiff = true
									end

									if locks[ci][1] or locks[ci][2] or locks[ci][3] then
										haveLock = true
									end
								end

								if haveStiff then
									local okE, enc =
										pcall(HttpService.JSONEncode, HttpService, stiff)
									if okE then
										anchor:SetAttribute("EclipseIKStiffness", enc)
									end
								end

								if haveLock then
									local okE, enc =
										pcall(HttpService.JSONEncode, HttpService, locks)
									if okE then
										anchor:SetAttribute("EclipseIKLocks", enc)
									end
								end

								local followers = {}
								for ci = 1, #chainData do
									followers[ci] = {}
								end

								for aName, cand in pairs(anchorByName) do
									local fBone = nameToBone[aName]
									if
										fBone
										and fBone ~= effBone
										and not usedNames[aName]
										and cand:GetAttribute("EclipseDeform") == true
										and not effBone:IsAncestorOf(fBone)
										and not fBone:IsAncestorOf(effBone)
									then
										local underChain = false
										for _, rn in ipairs(resolvedNames) do
											local rb = nameToBone[rn]
											if
												rb
												and (
													rb:IsAncestorOf(fBone)
													or fBone:IsAncestorOf(rb)
												)
											then
												underChain = true
												break
											end
										end

										if not underChain then
											local h = cand:GetAttribute("Head")
											local t = cand:GetAttribute("Tail")
											if
												typeof(h) == "Vector3"
												and typeof(t) == "Vector3"
											then
												local bestSeg = nil
												local bestDist = nil
												for ci = 1, #chainData do
													local sh = segHeads[ci]
													local dirv = segTails[ci] - sh
													local segLen = dirv.Magnitude
													if segLen > 1e-6 then
														local du = dirv / segLen
														local hRel = h - sh
														local tRel = t - sh
														local th = hRel:Dot(du) / segLen
														local tt = tRel:Dot(du) / segLen
														if
															th > -0.2
															and th < 1.2
															and tt > -0.2
															and tt < 1.2
														then
															local dh = (hRel - du * hRel:Dot(du)).Magnitude
															local dt = (tRel - du * tRel:Dot(du)).Magnitude
															local dist = (dh + dt) / segLen
															if
																dist < 0.35
																and (
																	bestDist == nil
																	or dist < bestDist
																)
															then
																bestDist = dist
																bestSeg = ci
															end
														end
													end
												end

												if bestSeg then
													table.insert(followers[bestSeg], aName)
													cand:SetAttribute("EclipseSyncFrom", nil)
													cand:SetAttribute("EclipseSyncOffset", nil)
												end
											end
										end
									end
								end

								local okE, enc =
									pcall(HttpService.JSONEncode, HttpService, followers)
								if okE then
									anchor:SetAttribute("EclipseIKFollowers", enc)
								end
							end
						end
					end
				end

				local followBone = nil
				local cursor = anchor:GetAttribute("ParentBone")
				local guard = 0
				while typeof(cursor) == "string" and guard < 60 do
					guard += 1
					if nameToBone[cursor] then
						followBone = nameToBone[cursor]
						break
					end

					local parentAnchor = anchorByName[cursor]
					cursor = parentAnchor and parentAnchor:GetAttribute("ParentBone") or nil
				end

				if not followBone then
					followBone = rootBone
				end

				if followBone then
					anchor:SetAttribute("EclipseFollowBone", followBone.Name)
					anchor:SetAttribute(
						"EclipseFollowOffset",
						aiWorldOf(followBone):Inverse() * anchor.CFrame
					)
				end
			end
		end
	end
end

ArmatureImport.bind = bindAnchors

local function captureTarget()
	if ArmatureImport.resolveTarget then
		return ArmatureImport.resolveTarget()
	end

	for _, inst in ipairs(Selection:Get()) do
		if inst:IsA("Bone") then
			local top = inst
			while top and top:IsA("Bone") do
				top = top.Parent
			end

			if top then
				return rigRootOf(top)
			end
		end

		if inst:IsA("BasePart") and inst:GetAttribute("SourceIsBone") then
			local folder = inst.Parent
			local srcVal = folder and folder:FindFirstChild("EclipseSourceRig")
			if srcVal and srcVal.Value then
				return srcVal.Value
			end
		end

		if
			(inst:IsA("Model") or inst:IsA("BasePart"))
			and not inst:GetAttribute("EclipseArmature")
			and not inst:GetAttribute("EclipseArmatureBone")
		then
			return inst
		end
	end

	if ArmatureImport.getFallbackTarget then
		local ok, fallback = pcall(ArmatureImport.getFallbackTarget)
		if ok and fallback then
			return fallback
		end
	end

	return nil
end

ArmatureImport.captureTarget = captureTarget

local function targetBounds(inst)
	if inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end

	if inst:IsA("Model") then
		local mn = nil
		local mx = nil

		local function acc(v)
			if not mn then
				mn = v
				mx = v
			end

			mn = Vector3.new(math.min(mn.X, v.X), math.min(mn.Y, v.Y), math.min(mn.Z, v.Z))
			mx = Vector3.new(math.max(mx.X, v.X), math.max(mx.Y, v.Y), math.max(mx.Z, v.Z))
		end

		for _, p in ipairs(inst:GetDescendants()) do
			if p:IsA("BasePart") then
				local h = p.Size / 2
				acc(p.CFrame * Vector3.new(h.X, h.Y, h.Z))
				acc(p.CFrame * Vector3.new(h.X, h.Y, -h.Z))
				acc(p.CFrame * Vector3.new(h.X, -h.Y, h.Z))
				acc(p.CFrame * Vector3.new(h.X, -h.Y, -h.Z))
				acc(p.CFrame * Vector3.new(-h.X, h.Y, h.Z))
				acc(p.CFrame * Vector3.new(-h.X, h.Y, -h.Z))
				acc(p.CFrame * Vector3.new(-h.X, -h.Y, h.Z))
				acc(p.CFrame * Vector3.new(-h.X, -h.Y, -h.Z))
			end
		end

		if not mn then
			return nil, nil
		end

		return (mn + mx) / 2, (mx - mn)
	end

	return nil, nil
end

local function fitRotation(target)
	if target:IsA("Model") and target:FindFirstChildOfClass("Humanoid") then
		local hrp = target:FindFirstChild("HumanoidRootPart")
		local source = (hrp and hrp:IsA("BasePart") and hrp.CFrame) or target:GetPivot()
		local look = source.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local yaw = (flat.Magnitude > 1e-4) and CFrame.lookAt(Vector3.zero, flat.Unit)
			or CFrame.identity
		return yaw * CFrame.Angles(0, math.pi, 0)
	end

	return CFrame.Angles(0, math.pi, 0)
end

local function computeTransform(reference, target)
	if not target or typeof(reference) ~= "table" then
		return nil
	end

	local refSize = toVector3(reference.size)
	local refCenter = toVector3(reference.center) or Vector3.zero
	if not refSize or refSize.Magnitude < 1e-3 then
		return nil
	end

	local tCenter, tSize = targetBounds(target)
	if not tCenter or not tSize then
		return nil
	end

	local ratio = tSize.Magnitude / refSize.Magnitude
	local rot = fitRotation(target)
	local xform = function(p)
		return tCenter + rot * ((p - refCenter) * ratio)
	end

	return xform, tCenter
end

local ARMATURE_STORE = "EclipseArmatures"

local function armatureStore()
	return require("root").get(ARMATURE_STORE, true)
end

local function rigKey(rig)
	local key = rig:GetAttribute("EclipseArmatureKey")
	if typeof(key) ~= "string" then
		key = HttpService:GenerateGUID(false)
		rig:SetAttribute("EclipseArmatureKey", key)
	end

	return key
end

local function purgeStoreKey(key, keep)
	if typeof(key) ~= "string" then
		return
	end

	local store = require("root").get(ARMATURE_STORE, false)
	if not store then
		return
	end

	for _, m in ipairs(store:GetChildren()) do
		if m ~= keep and m:GetAttribute("EclipseArmatureKey") == key then
			m:Destroy()
		end
	end
end

local function stashOne(arm, owningRig)
	if arm:GetAttribute("EclipseArmatureVersion") == 4 and arm.Parent then
		local key = arm:GetAttribute("EclipseArmatureKey")
		local ancestor = arm.Parent
		while not owningRig and ancestor and ancestor ~= workspace do
			if key and ancestor:GetAttribute("EclipseArmatureKey") == key then
				owningRig = ancestor
			end

			ancestor = ancestor.Parent
		end

		ArmatureRuntime.suspend(owningRig or arm.Parent)
	end

	local home = arm:FindFirstChild("EclipseArmatureHome")
	if not home then
		home = Instance.new("ObjectValue")
		home.Name = "EclipseArmatureHome"
		home.Parent = arm
	end

	home.Value = arm.Parent
	purgeStoreKey(arm:GetAttribute("EclipseArmatureKey"), arm)
	arm.Parent = armatureStore()
end

function ArmatureImport.stash(rig)
	if not rig then
		return
	end

	rig = rigRootOf(rig)
	local arm = findArmature(rig)
	if arm then
		stashOne(arm, rig)
	end
end

function ArmatureImport.stashAll()
	local found = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("EclipseArmature") then
			table.insert(found, d)
		end
	end

	for _, arm in ipairs(found) do
		stashOne(arm)
	end
end

function ArmatureImport.restore(rig, backup)
	if not rig then
		return nil
	end

	rig = rigRootOf(rig)
	local existing = findArmature(rig)
	if existing then
		bindAnchors(existing, rig)
		return existing
	end

	local key = rig:GetAttribute("EclipseArmatureKey")
	local store = require("root").get(ARMATURE_STORE, false)
	if store and typeof(key) == "string" then
		for _, m in ipairs(store:GetChildren()) do
			if m:GetAttribute("EclipseArmatureKey") == key then
				m.Name = "Armature"
				local home = m:FindFirstChild("EclipseArmatureHome")
				local homeParent = home and home.Value
				if home then
					home:Destroy()
				end

				if homeParent and (homeParent == rig or homeParent:IsDescendantOf(rig)) then
					m.Parent = homeParent
				else
					m.Parent = rig
				end

				bindAnchors(m, rig)
				return m
			end
		end
	end

	if backup then
		local clone = backup:Clone()
		clone.Name = "Armature"
		clone:SetAttribute("EclipseArmatureKey", rigKey(rig))
		local home = clone:FindFirstChild("EclipseArmatureHome")
		if home then
			home:Destroy()
		end

		clone.Parent = rig
		bindAnchors(clone, rig)
		return clone
	end

	return nil
end

local function importData(data, target)
	if
		typeof(data) ~= "table"
		or data.format ~= "EclipseArmature"
		or typeof(data.bones) ~= "table"
	then
		Notification.show("INVALID FILE", "That doesn't look like an Eclipse armature export.")
		return nil
	end

	target = target or captureTarget()
	if not target then
		Notification.show(
			"SELECT AN OBJECT",
			"Select the rig or object to add the armature to first."
		)
		return nil
	end

	if tonumber(data.version) and tonumber(data.version) >= 4 then
		local rigRoot = rigRootOf(target)
		local primitiveCount = 0
		for _, bone in data.bones do
			primitiveCount += #(bone.edges or {}) + #(bone.tris or {})
		end

		if primitiveCount > MAX_PRIMITIVES then
			Notification.show(
				"ARMATURE TOO LARGE",
				"Reduce custom-shape geometry before exporting."
			)
			return nil
		end

		local ok, candidate, plan = pcall(ArmatureConverter.build, data, rigRoot)
		if not ok then
			Notification.show("IMPORT FAILED", tostring(candidate))
			return nil
		end

		if not rigRoot.Parent then
			candidate:Destroy()
			Notification.show("IMPORT CANCELLED", "The target rig was removed during import.")
			return nil
		end

		if ArmatureImport.onBeforeImport then
			pcall(ArmatureImport.onBeforeImport, rigRoot)
		end

		local existing = findArmature(rigRoot)
		local native = {}
		for _, target in require("RigTraversal").descendants(rigRoot) do
			if target:IsA("Motor6D") then
				native[target] = { C0 = target.C0 }
			elseif target:IsA("Bone") then
				native[target] = { Transform = target.Transform }
			elseif target:IsA("BasePart") then
				native[target] = { CFrame = target.CFrame, Size = target.Size }
			end
		end

		ArmatureRuntime.restoreNativeGeometry(rigRoot)
		ArmatureRuntime.invalidate(rigRoot)
		local oldParent = existing and existing.Parent
		if existing then
			existing.Parent = nil
		end

		local attached, failure = pcall(function()
			candidate:SetAttribute("EclipseArmatureKey", rigKey(rigRoot))
			candidate.Parent = rigRoot
			return ArmatureConverter.attach(candidate, rigRoot, data)
		end)
		if not attached then
			ArmatureRuntime.restoreNativeGeometry(rigRoot)
			ArmatureRuntime.invalidate(rigRoot)
			candidate:Destroy()
			for target, properties in native do
				for key, value in properties do
					pcall(function()
						target[key] = value
					end)
				end
			end

			if existing then
				existing.Parent = oldParent
				pcall(ArmatureConverter.attach, existing, rigRoot)
			end

			Notification.show("IMPORT FAILED", tostring(failure))
			return nil
		end

		if existing then
			existing:Destroy()
		end

		Selection:Set({})
		ChangeHistoryService:SetWaypoint("Add Armature")
		local diagnostics = ArmatureRuntime.diagnostics(rigRoot)
		local controlCount = 0
		for _, anchor in candidate:GetChildren() do
			if
				anchor:GetAttribute("EclipseArmatureBoneId")
				and anchor:GetAttribute("EclipseArmatureControl") ~= false
				and anchor:GetAttribute("Hidden") ~= true
				and anchor.CanQuery
			then
				controlCount += 1
			end
		end

		local linked = tostring(controlCount)
			.. " controls available ("
			.. tostring(#data.bones)
			.. " solver bones). "
		if #diagnostics > 0 then
			Notification.show("ARMATURE IMPORT NOTES", linked .. diagnostics[1])
			warn("[Eclipse Armature] " .. table.concat(diagnostics, "\n"))
		else
			Notification.show("ARMATURE ADDED", linked .. "Linked to " .. rigRoot.Name .. ".")
		end

		if ArmatureImport.onImported then
			pcall(ArmatureImport.onImported, candidate, rigRoot)
		end

		return candidate
	end

	if ArmatureImport.onBeforeImport then
		pcall(ArmatureImport.onBeforeImport, target)
	end

	local totalGeo = 0
	for _, boneData in ipairs(data.bones) do
		totalGeo += typeof(boneData.edges) == "table" and #boneData.edges or 0
		totalGeo += typeof(boneData.tris) == "table" and #boneData.tris or 0
	end

	if totalGeo == 0 then
		Notification.show("EMPTY ARMATURE", "The export contains no bone geometry.")
		return nil
	end

	if totalGeo > MAX_PRIMITIVES then
		Notification.show(
			"TOO DENSE",
			"Armature has " .. totalGeo .. " primitives. Simplify custom shapes and re-export."
		)
		return nil
	end

	local xform, pivotPos = computeTransform(data.reference, target)
	local rigRoot = rigRootOf(target)
	local rigModel = buildRig(data, xform)
	rigModel.Name = "Armature"
	rigModel:SetAttribute("EclipseArmatureKey", rigKey(rigRoot))
	local existing = findArmature(rigRoot)
	if existing then
		existing:Destroy()
	end

	rigModel.Parent = rigRoot
	if pivotPos then
		rigModel.WorldPivot = CFrame.new(pivotPos)
	end

	local sawIKData = false
	for _, boneData in ipairs(data.bones) do
		local ik = boneData.ik
		if typeof(ik) == "table" and typeof(ik.target) == "string" then
			sawIKData = true
			local targetAnchor = rigModel:FindFirstChild("c_" .. ik.target)
			if not targetAnchor or targetAnchor:GetAttribute("Hidden") == true then
				targetAnchor = rigModel:FindFirstChild(ik.target)
				local guard = 0
				while targetAnchor and targetAnchor:GetAttribute("Hidden") == true and guard < 10 do
					guard += 1
					local parentName = targetAnchor:GetAttribute("ParentBone")
					targetAnchor = typeof(parentName) == "string"
							and rigModel:FindFirstChild(parentName)
						or nil
				end
			end

			if targetAnchor then
				local climbGuard = 0
				local cursor = targetAnchor
				while climbGuard < 12 do
					climbGuard += 1
					local parentName = cursor:GetAttribute("ParentBone")
					local pa = typeof(parentName) == "string"
							and rigModel:FindFirstChild(parentName)
						or nil
					if not pa then
						break
					end

					cursor = pa
					if pa:GetAttribute("Hidden") ~= true then
						if pa.Name:lower():find("ik", 1, true) then
							targetAnchor = pa
						end

						break
					end
				end
			end

			if targetAnchor then
				targetAnchor:SetAttribute("EclipseIKConstraint", true)
				if typeof(ik.chain_count) == "number" then
					targetAnchor:SetAttribute("EclipseIKChainCount", ik.chain_count)
				end

				if typeof(ik.pole) == "string" then
					targetAnchor:SetAttribute("EclipseIKPole", ik.pole)
				end

				if typeof(ik.pole_angle) == "number" then
					targetAnchor:SetAttribute("EclipseIKPoleAngle", ik.pole_angle)
				end

				if typeof(ik.iterations) == "number" then
					targetAnchor:SetAttribute("EclipseIKIterations", ik.iterations)
				end

				if typeof(ik.influence) == "number" then
					targetAnchor:SetAttribute("EclipseIKInfluence", ik.influence)
				end

				local targetBoneAnchor = rigModel:FindFirstChild(ik.target)
				local targetHead = targetBoneAnchor and targetBoneAnchor:GetAttribute("Head")
				if typeof(targetHead) == "Vector3" then
					targetAnchor:SetAttribute(
						"EclipseIKGoalOffset",
						targetAnchor.CFrame:PointToObjectSpace(targetHead)
					)
				end

				if typeof(ik.chain) == "table" then
					local fitted = {}
					for ci, cbData in ipairs(ik.chain) do
						local h = toVector3(cbData.head)
						local t = toVector3(cbData.tail)
						if h and t then
							if xform then
								h = xform(h)
								t = xform(t)
							end

							fitted[ci] = {
								name = cbData.name,
								head = { h.X, h.Y, h.Z },
								tail = { t.X, t.Y, t.Z },
								stiffness = cbData.stiffness,
								lock = cbData.lock,
							}
						end
					end

					if #fitted == #ik.chain then
						local okEnc, enc = pcall(HttpService.JSONEncode, HttpService, fitted)
						if okEnc then
							targetAnchor:SetAttribute("EclipseIKChainData", enc)
						end
					end
				end
			end
		end
	end

	rigModel:SetAttribute("EclipseHasIKData", sawIKData)
	bindAnchors(rigModel, rigRoot)
	Selection:Set({})
	ChangeHistoryService:SetWaypoint("Add Armature")
	Notification.show(
		"LEGACY ARMATURE ADDED",
		#data.bones
			.. " bones added. Re-export with the updated Blender addon to preserve the full control and constraint setup."
	)
	if ArmatureImport.onImported then
		pcall(ArmatureImport.onImported, rigModel, rigRoot)
	end

	return rigModel
end

function ArmatureImport.importData(data, target)
	if importing then
		Notification.show("IMPORT IN PROGRESS", "Wait for the current armature import to finish.")
		return nil
	end

	importing = true
	local ok, result = xpcall(importData, debug.traceback, data, target)
	importing = false
	if not ok then
		Notification.show("IMPORT FAILED", tostring(result))
		return nil
	end

	return result
end

local function importFile()
	local target = windowTarget and windowTarget.Parent and windowTarget or nil
	if not target then
		Notification.show(
			"SELECT AN OBJECT",
			"Select the rig or object to add the armature to first."
		)
		return
	end

	local ok, file = pcall(function()
		return StudioService:PromptImportFile({ "json" })
	end)
	if not ok then
		Notification.show("IMPORT FAILED", "Could not open the file picker.")
		return
	end

	if not file then
		return
	end

	local okRead, contents = pcall(function()
		return file:GetBinaryContents()
	end)
	if not okRead then
		Notification.show("IMPORT FAILED", "Could not read the selected file.")
		return
	end

	local okJson, data = pcall(function()
		return HttpService:JSONDecode(contents)
	end)
	if not okJson then
		Notification.show("INVALID FILE", "That doesn't look like an Eclipse armature export.")
		return
	end

	if ArmatureImport.importData(data, target) then
		ArmatureImport.close()
	end
end

local function makeDraggable(frame, handle)
	Chrome.bindDrag(frame, handle)
end

local function styleHoverButton(btn)
	btn.AutoButtonColor = false
	local baseColor = function()
		return Theme.get("TopBtn", Color3.fromRGB(51, 0, 77))
	end

	btn.MouseEnter:Connect(function()
		TweenService
			:Create(
				btn,
				FADE_TWEEN,
				{ BackgroundColor3 = baseColor():Lerp(Color3.new(1, 1, 1), 0.14) }
			)
			:Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, FADE_TWEEN, { BackgroundColor3 = baseColor() }):Play()
	end)
end

local function buildWindow()
	if screenGui then
		local stale = screenGui:FindFirstChild("ArmatureWindow", true)
		if stale then
			stale:Destroy()
		end
	end

	local frame = Instance.new("Frame")
	frame.Name = "ArmatureWindow"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.45)
	frame.Size = UDim2.fromOffset(460, 390)
	frame.BackgroundColor3 = Color3.fromRGB(24, 2, 36)
	frame.BorderSizePixel = 0
	frame.ZIndex = 80
	frame:SetAttribute("ThemeBg", "Bg")

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(96, 48, 134)
	stroke:SetAttribute("ThemeStrk", "Strk")
	stroke.Parent = frame

	local titleBar, _, drag = Chrome.header(frame, "BLENDER ARMATURE", 81, 42)
	Chrome.close(titleBar, function()
		ArmatureImport.close()
	end, 84)

	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(14, 42)
	desc.Size = UDim2.new(1, -28, 1, -98)
	desc.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	desc.TextSize = 16
	desc.RichText = true
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = Color3.new(1, 1, 1)
	desc.TextTransparency = 0.12
	desc.Text =
		"<b>!! VERY experimental</b>\n\nThis will replace your current rig's armature, also removing the keyframes!\n\nIt pairs with our blender plugin to import your blender bones into roblox studio with the same behavior, even if they have IK. Make sure you are using the same rig.\n\nThere's a good chance this may not work, as it is experimental. Please report faults in our Community Server. Find the link on our Creator Store page."
	local textHeight = game:GetService("TextService"):GetTextSize(
		"!! VERY experimental\n\nThis will replace your current rig's armature, also removing the keyframes!\n\nIt pairs with our blender plugin to import your blender bones into roblox studio with the same behavior, even if they have IK. Make sure you are using the same rig.\n\nThere's a good chance this may not work, as it is experimental. Please report faults in our Community Server. Find the link on our Creator Store page.",
		16,
		Enum.Font.RobotoMono,
		Vector2.new(432, 10000)
	).Y
	frame.Size = UDim2.fromOffset(460, textHeight + 108)
	desc.ZIndex = 81
	desc:SetAttribute("ThemeTxt", "Txt")
	desc.Parent = frame

	local importBtn = Instance.new("TextButton")
	importBtn.Name = "ImportButton"
	importBtn.AnchorPoint = Vector2.new(0.5, 1)
	importBtn.Position = UDim2.new(0.5, 0, 1, -14)
	importBtn.Size = UDim2.new(1, -28, 0, 34)
	importBtn.BackgroundColor3 = Color3.fromRGB(51, 0, 77)
	importBtn.BorderSizePixel = 0
	importBtn.FontFace = FONT
	importBtn.TextSize = 14
	importBtn.Text = "IMPORT .JSON"
	importBtn.TextColor3 = Color3.new(1, 1, 1)
	importBtn.TextTransparency = 0.15
	importBtn.ZIndex = 81
	importBtn:SetAttribute("ThemeBg", "TopBtn")
	importBtn:SetAttribute("ThemeTxt", "Txt")
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = importBtn
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Thickness = 1
	btnStroke.Transparency = 0.5
	btnStroke.Color = Color3.fromRGB(96, 48, 134)
	btnStroke:SetAttribute("ThemeStrk", "Strk")
	btnStroke.Parent = importBtn
	importBtn.Parent = frame

	styleHoverButton(importBtn)
	Chrome.bindDrag(frame, drag, { clamp = true, margin = 8 })

	importBtn.MouseButton1Click:Connect(function()
		importFile()
	end)

	Theme.applyTree(frame)
	frame.Parent = screenGui
	return frame
end

function ArmatureImport.open(target)
	if not screenGui then
		return
	end

	target = target or captureTarget()
	if not target then
		Notification.show(
			"SELECT A RIG",
			"Select one rig in the timeline or viewport before importing an armature."
		)
		return
	end

	windowTarget = target
	if not window or not window.Parent then
		window = buildWindow()
	end

	window.Visible = true
	local sc = window:FindFirstChildOfClass("UIScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Parent = window
	end

	sc.Scale = 0.88
	TweenService:Create(
		sc,
		TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

function ArmatureImport.close()
	windowTarget = nil
	if window then
		window.Visible = false
	end
end

function ArmatureImport.toggle()
	if window and window.Parent and window.Visible then
		ArmatureImport.close()
	else
		ArmatureImport.open()
	end
end

local brightened = {}
local watcherConnected = false

local function setAdornColor(anchor, color)
	for _, a in ipairs(anchor:GetChildren()) do
		if a:IsA("HandleAdornment") then
			a.Color3 = color
		end
	end
end

local function refreshBoneSelection()
	for anchor in pairs(brightened) do
		if anchor and anchor.Parent then
			ArmatureImport.setAnchorSelected(anchor, false)
		end

		brightened[anchor] = nil
	end

	for _, inst in ipairs(Selection:Get()) do
		local anchor = nil
		if inst:GetAttribute("EclipseArmatureBone") then
			anchor = inst
		elseif inst.Parent and inst.Parent:GetAttribute("EclipseArmatureBone") then
			anchor = inst.Parent
		end

		if anchor and not anchor:GetAttribute("Hidden") then
			ArmatureImport.setAnchorSelected(anchor, true)
			brightened[anchor] = true
		end
	end
end

function ArmatureImport.init(refs)
	screenGui = refs.ScreenGui
	if not watcherConnected then
		watcherConnected = true
		local watcher = Selection.SelectionChanged:Connect(refreshBoneSelection)
		screenGui.Destroying:Once(function()
			watcher:Disconnect()
			watcherConnected = false
		end)
	end
end

return ArmatureImport
