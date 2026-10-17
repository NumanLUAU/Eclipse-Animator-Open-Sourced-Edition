--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")
local PartHandles = require("handles")
local Properties = require("Properties")
local CameraRig = require("CameraRig")
local CameraDisplay = require("CameraDisplay")
local MasterControl = require("MasterControl")
local Rig = {}
local CollectionService = game:GetService("CollectionService")

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local baseItem = require("baseItem")
local BoneMotor = require("BoneMotor")
local BoneIK = require("BoneIK")
local ArmatureRuntime = require("ArmatureRuntime")
local LimbIK = require("LimbIK")
local LimbControls = require("LimbControls")
local R6Controls = require("R6Controls")
local Preferences = require("Preferences")
local TrackOrganization = require("Organization")
local TrackHierarchy = require("Hierarchy")
local WorkBudget = require("WorkBudget")

local GUI_CLASSES = {
	ScreenGui = true,
	SurfaceGui = true,
	BillboardGui = true,
	Frame = true,
	TextButton = true,
	TextLabel = true,
	ImageButton = true,
	ImageLabel = true,
	ViewportFrame = true,
	ScrollingFrame = true,
	UIListLayout = true,
	UIPadding = true,
	UICorner = true,
	UIStroke = true,
	UIGradient = true,
	UIScale = true,
}

Rig._selectionSyncConn = nil
Rig._lastObservedSelectedBone = nil
Rig._refreshHierarchyVisuals = nil
Rig._expandedState = Rig._expandedState or {}
Rig._selectedItems = Rig._selectedItems or {}
Rig._selectedChannels = Rig._selectedChannels or {}
Rig._lastClickedItem = nil
Rig._lastEventRig = nil
Rig._orderedItems = {}
Rig._boneFollowCaches = setmetatable({}, { __mode = "k" })
Rig._partToMotorCache = Rig._partToMotorCache or setmetatable({}, { __mode = "kv" })
Rig._boneToRigPartCache = Rig._boneToRigPartCache or setmetatable({}, { __mode = "kv" })
Rig._cachedRigForBones = nil
Rig._cachedBonesFolder = nil

function Rig.Initialize(data)
	local self = setmetatable({}, { __index = Rig })
	self.refs = data or {}
	self._masterItems = {}
	self._ownedBoneFolders = setmetatable({}, { __mode = "kv" })
	baseItem.rigModule = self
	return self
end

function Rig:GetExtraRigs()
	if self.refs and self.refs.GetExtraRigs then
		return self.refs.GetExtraRigs() or {}
	end

	return {}
end

function Rig:_isObjectMotorActive(motor)
	if motor:GetAttribute("EclipsePartRigJoint") and motor.Part0 and motor.Part0.Parent then
		return motor:GetAttribute("EclipsePartTrackEnabled") ~= false
			and require("PartRig").enabled(
				motor.Part0.Parent,
				self.refs and self.refs.Timeline and self.refs.Timeline:GetState()
			)
	end

	if motor:GetAttribute("EclipseAddedObject") ~= true then
		return true
	end

	local check = self.refs and self.refs.IsObjectMotorActive
	if check then
		return check(motor) == true
	end

	return true
end

function Rig:GetExternalAttachedParts(rig)
	local list = {}
	if not rig then
		return list
	end

	for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			m:IsA("Motor6D")
			and m.Part1
			and not m.Part1:IsDescendantOf(rig)
			and self:_isObjectMotorActive(m)
		then
			table.insert(list, m.Part1)
		end
	end

	return list
end

function Rig:DestroyHierarchyItems(buildToken)
	local active = self._hierarchyBuildToken
	if active and active ~= buildToken then
		active.cancelled = true
		self._hierarchyBuildPending = nil
	end

	local owned, seen = {}, {}

	local function collect(row)
		if not row or seen[row] then
			return
		end

		seen[row] = true
		for _, child in row.childItems or {} do
			collect(child)
		end

		for _, child in row.transformChannelItems or {} do
			collect(child)
		end

		table.insert(owned, {
			item = row,
			ui = row.uiElement,
			track = row.trackElement,
			connections = row.connections,
		})
	end

	for _, list in
		{
			self._hierarchyOwnedItems or {},
			self._rootItems or {},
			self._masterItems or {},
			self._orderedItems or {},
			self._subtitleItems or {},
			self._organizationItems or {},
		}
	do
		for _, row in list do
			collect(row)
		end
	end

	collect(self._originItem)
	local session = self._hierarchyOrganization
	if session then
		for _, row in session.byKey or {} do
			collect(row)
		end

		for row in session.virtual and session.virtual.saved or {} do
			collect(row)
		end
	end

	if self.refs and self.refs.Timeline then
		self.refs.Timeline.refs.RefreshIKHierarchy = nil
		self.refs.Timeline:ClearSummaryTracks()
	end

	for _, entry in owned do
		local row = entry.item
		if row.itemKind == "subtitles" and row.grandpa then
			require("EventTrackList").unbind(row.grandpa.linkedRigInstance, row.subtitleId)
		end
	end
	TrackHierarchy.destroy(self)
	self._originItem = nil
	self:StopSelectionSync()
	if self._preferencesDisconnect then
		self._preferencesDisconnect()
		self._preferencesDisconnect = nil
	end

	for _, entry in owned do
		entry.item.childItems = {}
	end

	for _, entry in owned do
		local row = entry.item
		if row.destroy then
			local ok, err = pcall(row.destroy, row)
			if not ok then
				warn("[Eclipse hierarchy cleanup] " .. tostring(err))
			end
		end

		for _, connection in entry.connections or {} do
			connection:Disconnect()
		end

		if entry.ui then
			entry.ui:Destroy()
		end

		if entry.track then
			entry.track:Destroy()
		end
	end

	self._hierarchyOwnedItems = {}
	self._masterItems = {}
	self._rootItems = nil
	self._subtitleItems = nil
	self._organizationItems = {}
	self.currentRig = nil
	self._orderedItems = {}
	self._selectedItems = {}
	self._selectedChannels = {}
	self._explicitSelectedKeys = {}
	self._lastClickedItem = nil
	self._lastEventRig = nil
	self._refreshHierarchyVisuals = nil
end

function Rig:HandleHierarchyClick(item)
	return TrackHierarchy.click(self, item)
end

function Rig:SetHierarchyItemDisabled(item, disabled, propagate)
	TrackHierarchy.setDisabled(self, item, disabled, propagate)
end

function Rig:CreateFolder(parentKey)
	if parentKey == nil then
		local selected
		for key, value in self._explicitSelectedKeys or {} do
			if value and TrackOrganization.isFolder(key) then
				if selected then
					selected = nil
					break
				end

				selected = key
			end
		end

		parentKey = selected
	end

	return TrackOrganization.create(parentKey)
end

function Rig:DeleteFolder(id)
	return TrackOrganization.remove(id)
end

function Rig:GetCamera()
	return workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")
end

function Rig:GetBonesFolderName(rig)
	if not rig then
		return "Bones"
	end

	return rig.Name .. "Bones"
end

function Rig:GetBonesFolder(rig)
	local cam = self:GetCamera()
	if not cam or not rig then
		return nil
	end

	local owned = self._ownedBoneFolders and self._ownedBoneFolders[rig]
	if not rig.Parent and owned and owned.Parent == cam then
		return owned
	end

	return RigTraversal.bonesFolder(rig, cam)
end

function Rig:GetExpandKey(rig, part)
	if part == rig then
		return rig:GetFullName() .. "::RIG"
	end

	return rig:GetFullName() .. "::" .. part:GetFullName()
end

function Rig:IsExpanded(rig, part)
	local key = self:GetExpandKey(rig, part)
	local value = self._expandedState[key]
	if value == nil then
		return true
	end

	return value
end

function Rig:SetExpanded(rig, part, state)
	local key = self:GetExpandKey(rig, part)
	self._expandedState[key] = state and true or false
end

function Rig:GetLockTag()
	local players = game:GetService("Players")

	if game:GetService("RunService"):IsClient() then
		local player = players.LocalPlayer
		if player and player.UserId then
			return "EclipseLocked-" .. tostring(player.UserId)
		end
	end

	return "EclipseLocked"
end

const ROOT_PRIORITY = "EclipseOriginalRootPriority"

local function holdRootPriority(part)
	if part.Anchored or part:GetAttribute(ROOT_PRIORITY) ~= nil or part.RootPriority >= 127 then
		return
	end

	part:SetAttribute(ROOT_PRIORITY, part.RootPriority)
	part.RootPriority = 127
end

local function releaseRootPriority(part)
	const original = part:GetAttribute(ROOT_PRIORITY)
	if typeof(original) == "number" then
		part.RootPriority = original
	end

	if original ~= nil then
		part:SetAttribute(ROOT_PRIORITY, nil)
	end
end

function Rig:LockRigLimbs(rig, state)
	local lockTag = self:GetLockTag()
	const root = state and rig:IsA("Model") and MasterControl.root(rig)

	for _, inst: Object in ipairs(RigTraversal.rigDescendants(rig)) do
		if not inst:IsA("BasePart") then
			continue
		end

		if rig:GetAttribute("EclipseEffectObject") == 1 then
			inst.Locked = inst:GetAttribute("EclipsePartRigRoot") == true
			continue
		end

		if state then
			if not inst:HasTag(lockTag) then
				inst:SetAttribute("EclipseOriginalLocked", inst.Locked)
				inst:AddTag(lockTag)
			elseif type(inst:GetAttribute("EclipseOriginalLocked")) ~= "boolean" then
				inst:SetAttribute("EclipseOriginalLocked", false)
			end

			inst:RemoveTag("EclipseLockOriginalLock")
			inst.Locked = true
			if inst == root then
				holdRootPriority(inst)
			end
		elseif inst:HasTag(lockTag) then
			inst.Locked = inst:GetAttribute("EclipseOriginalLocked") == true
			inst:SetAttribute("EclipseOriginalLocked", nil)
			releaseRootPriority(inst)
			inst:RemoveTag("EclipseLockOriginalLock")
			inst:RemoveTag(lockTag)
		end
	end
end

function Rig:CleanUpOldLockedRigs()
	local key = self:GetLockTag()

	for _, v in ipairs(CollectionService:GetTagged(key)) do
		v.Locked = v:GetAttribute("EclipseOriginalLocked") == true
		v:SetAttribute("EclipseOriginalLocked", nil)
		releaseRootPriority(v)
		v:RemoveTag("EclipseLockOriginalLock")
		v:RemoveTag(key)
	end
end

function Rig:IsService(instance)
	return instance.Parent == game
end

function Rig:IsGui(instance)
	if instance:IsA("GuiObject") or instance:IsA("LayerCollector") then
		return true
	end

	return GUI_CLASSES[instance.ClassName] == true
end

function Rig:IsAnimatable(instance)
	if not instance or not instance:IsA("Instance") then
		return false
	end

	return #Properties.catalog(instance) > 0
end

function Rig:GetMotorForPart(currentRig, part)
	local origin = require("Origin").motor(part)
	if origin then
		return origin
	end

	if Properties.isNode(part) then
		return Properties.fromNode(part)
	end

	if not currentRig or not part then
		return nil
	end

	local owner = part.Parent
	local master
	while owner and owner ~= workspace do
		master = MasterControl.get(owner)
		if master and master.Part1 == part then
			break
		end

		owner = owner.Parent
	end

	if master and master.Part1 == part then
		return master
	end

	if part:IsA("Bone") then
		return BoneMotor.get(part)
	end

	if part:IsA("BasePart") and part:GetAttribute("EclipseArmatureBone") then
		return BoneMotor.getIKHandle(part, currentRig)
	end

	local passive = RigTraversal.passiveMotors(currentRig)
	local cached = self._partToMotorCache[part]
	if cached and cached.Parent and cached.Part1 == part and not passive[cached] then
		return cached
	end

	local cache, found = self._partToMotorCache, nil
	for _, m in ipairs(RigTraversal.rigDescendants(currentRig)) do
		if m:IsA("Motor6D") and not passive[m] then
			local target = m.Part1
			if target == part and not found then
				found = m
			elseif target and cache[target] == nil then
				cache[target] = m
			end
		end
	end

	if found then
		cache[part] = found
		return found
	end

	for _, extraRig in ipairs(self:GetExtraRigs()) do
		if extraRig ~= currentRig and extraRig.Parent then
			passive = RigTraversal.passiveMotors(extraRig)
			for _, m in ipairs(RigTraversal.rigDescendants(extraRig)) do
				if m:IsA("Motor6D") and not passive[m] then
					local target = m.Part1
					if target == part and not found then
						found = m
					elseif target and cache[target] == nil then
						cache[target] = m
					end
				end
			end

			if found then
				cache[part] = found
				return found
			end
		end
	end

	return nil
end

function Rig:GetPartFromBone(currentRig, bone)
	if ArmatureRuntime.isAnchor(bone) then
		return bone
	end

	if require("Origin").is(bone) then
		return bone
	end

	local limbOwner = bone and bone:FindFirstChild("EclipseLimbOwner")
	if limbOwner and limbOwner.Value then
		return R6Controls.find(
			R6Controls.resolveOwner(limbOwner.Value),
			bone:GetAttribute("EclipseLimbControl")
		) or R6Controls.resolveOwner(limbOwner.Value).Part1
	end

	if not currentRig or not bone then
		return nil
	end

	local reference = bone:FindFirstChild("EclipseSourcePart")
		or bone:FindFirstChild("EclipseArmatureSource")
	if
		reference
		and reference:IsA("ObjectValue")
		and reference.Value
		and reference.Value.Parent
	then
		return reference.Value
	end

	local cached = self._boneToRigPartCache[bone]
	if cached and cached.Parent then
		return cached
	end

	local sourceName = bone:GetAttribute("SourcePartName") or bone:GetAttribute("EclipseBoneLink")
	if not sourceName then
		return nil
	end

	local sourceAnchor = bone:FindFirstChild("EclipseArmatureSource")
	if sourceAnchor and sourceAnchor:IsA("ObjectValue") and sourceAnchor.Value then
		return sourceAnchor.Value
	end

	local searchRig = currentRig
	local folder = bone.Parent
	local sourceRigValue = folder and folder:FindFirstChild("EclipseSourceRig")
	if sourceRigValue and sourceRigValue.Value and sourceRigValue.Value.Parent then
		searchRig = sourceRigValue.Value
	end

	if bone:GetAttribute("SourceIsVirtual") then
		if searchRig then
			for _, desc in ipairs(RigTraversal.rigDescendants(searchRig)) do
				if desc:IsA("Model") and desc:GetAttribute("EclipseArmature") then
					local anchor = desc:FindFirstChild(sourceName)
					if anchor and anchor:IsA("BasePart") then
						self._boneToRigPartCache[bone] = anchor
						return anchor
					end

					break
				end
			end
		end

		return nil
	end

	if bone:GetAttribute("SourceIsBone") or bone:GetAttribute("EclipseBoneLink") then
		if searchRig then
			for _, desc in ipairs(RigTraversal.rigDescendants(searchRig)) do
				if
					desc:IsA("Bone")
					and not desc:GetAttribute("EclipseArmatureSkinningHelper")
					and desc.Name == sourceName
				then
					self._boneToRigPartCache[bone] = desc
					return desc
				end
			end
		end

		return nil
	end

	local found = nil
	if searchRig then
		local direct = searchRig:FindFirstChild(sourceName, true)
		if direct and direct:IsA("BasePart") then
			found = direct
		else
			for _, desc in ipairs(RigTraversal.rigDescendants(searchRig)) do
				if desc:IsA("BasePart") and desc.Name == sourceName then
					found = desc
					break
				end
			end
		end

		if not found then
			for _, part in ipairs(self:GetExternalAttachedParts(searchRig)) do
				if part.Name == sourceName then
					found = part
					break
				end
			end
		end
	end

	if found then
		self._boneToRigPartCache[bone] = found
	end

	return found
end

local function boneSource(bone)
	return bone:FindFirstChild("EclipseSourcePart") or bone:FindFirstChild("EclipseArmatureSource")
end

local function indexedBone(index, part, anchor)
	const byValue = index.values[part]
	if anchor then
		return byValue
	end

	const byName = index.names[part.Name]
	if byValue and byName then
		return if index.order[byValue] < index.order[byName] then byValue else byName
	end

	return byValue or byName
end

local function boneMatches(bone, folder, part, anchor)
	if bone.Parent ~= folder then
		return false
	end

	const source = boneSource(bone)
	if source then
		return source:IsA("ObjectValue") and source.Value == part
	end

	return not anchor
		and bone:IsA("BasePart")
		and not bone:GetAttribute("EclipseLimbControl")
		and bone:GetAttribute("SourcePartName") == part.Name
end

function Rig:GetBoneFromPart(currentRig, part)
	if require("Origin").is(part) then
		return part
	end

	local bonesFolder = self:GetBonesFolder(currentRig)
	if not bonesFolder or not part then
		return nil
	end

	if typeof(part) == "Instance" and not R6Controls.isControl(part) then
		const anchor = ArmatureRuntime.isAnchor(part)
		const bone = indexedBone(self:_BoneIndex(bonesFolder), part, anchor)
		if bone then
			if boneMatches(bone, bonesFolder, part, anchor) then
				return bone
			end

			self:_BoneLookup(bonesFolder).index = nil
		end
	end

	local misses = self:_BoneMisses(bonesFolder)
	if typeof(part) == "Instance" and misses[part] == part.Name then
		return nil
	end

	for _, bone in ipairs(bonesFolder:GetChildren()) do
		local sourceAnchor = bone:FindFirstChild("EclipseSourcePart")
			or bone:FindFirstChild("EclipseArmatureSource")
		if sourceAnchor and sourceAnchor:IsA("ObjectValue") and sourceAnchor.Value == part then
			return bone
		elseif sourceAnchor or ArmatureRuntime.isAnchor(part) then
			continue
		elseif R6Controls.isControl(part) then
			local owner = bone:FindFirstChild("EclipseLimbOwner")
			if
				owner
				and R6Controls.resolveOwner(owner.Value) == R6Controls.get(part).Owner
				and bone:GetAttribute("EclipseLimbControl")
					== part:GetAttribute("EclipseR6Control")
			then
				return bone
			end
		elseif
			bone:IsA("BasePart")
			and not bone:GetAttribute("EclipseLimbControl")
			and bone:GetAttribute("SourcePartName") == part.Name
		then
			return bone
		end
	end

	if
		typeof(part) == "Instance"
		and not ArmatureRuntime.isAnchor(part)
		and not R6Controls.isControl(part)
	then
		misses[part] = part.Name
	end

	return nil
end

function Rig:_BoneLookup(folder)
	self._boneMissCache = self._boneMissCache or setmetatable({}, { __mode = "k" })
	local entry = self._boneMissCache[folder]
	if not entry then
		entry = {}
		local function reset(object)
			entry.misses = nil
			if object:IsA("BasePart") or object:IsA("ObjectValue") then
				entry.index = nil
			end
		end

		folder.DescendantAdded:Connect(reset)
		folder.DescendantRemoving:Connect(reset)
		self._boneMissCache[folder] = entry
	end

	return entry
end

function Rig:_BoneIndex(folder)
	const entry = self:_BoneLookup(folder)
	local index = entry.index
	if index then
		return index
	end

	index = { values = {}, names = {}, order = {} }
	for position, bone in folder:GetChildren() do
		const source = boneSource(bone)
		if source then
			const value = source:IsA("ObjectValue") and source.Value
			if value and index.values[value] == nil then
				index.values[value] = bone
				index.order[bone] = position
			end
		elseif bone:IsA("BasePart") and not bone:GetAttribute("EclipseLimbControl") then
			const name = bone:GetAttribute("SourcePartName")
			if name ~= nil and index.names[name] == nil then
				index.names[name] = bone
				index.order[bone] = position
			end
		end
	end

	entry.index = index
	return index
end

function Rig:_BoneMisses(folder)
	const entry = self:_BoneLookup(folder)
	local count = #folder:GetChildren()
	local misses = entry.misses
	if not misses or entry.count ~= count then
		misses = setmetatable({}, { __mode = "k" })
		entry.misses, entry.count = misses, count
	end

	return misses
end

function Rig:GetMotorGraph(rig)
	local passive = RigTraversal.passiveMotors(rig)
	local outgoing = {}
	local incoming = {}

	for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			m:IsA("Motor6D")
			and m.Part0
			and m.Part1
			and not passive[m]
			and self:_isObjectMotorActive(m)
		then
			outgoing[m.Part0] = (outgoing[m.Part0] or 0) + 1
			incoming[m.Part1] = (incoming[m.Part1] or 0) + 1
		end
	end

	return outgoing, incoming
end

function Rig:IsRigRootPart(part, outgoing, incoming)
	return (outgoing[part] or 0) > 0 and (incoming[part] or 0) == 0
end

function Rig:GetMotorChildrenMap(rig)
	local passive = RigTraversal.passiveMotors(rig)
	local childrenMap = {}
	local partToMotor = {}

	for _, m in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			m:IsA("Motor6D")
			and m.Part0
			and m.Part1
			and not passive[m]
			and self:_isObjectMotorActive(m)
		then
			childrenMap[m.Part0] = childrenMap[m.Part0] or {}
			table.insert(childrenMap[m.Part0], m.Part1)
			partToMotor[m.Part1] = m
		end
	end

	for _, children in pairs(childrenMap) do
		table.sort(children, function(a, b)
			local mA = partToMotor[a]
			local mB = partToMotor[b]
			local nameA = mA and mA.Name or a.Name
			local nameB = mB and mB.Name or b.Name
			return nameA > nameB
		end)
	end

	return childrenMap
end

function Rig:GetRigRoots(rig, outgoing, incoming)
	local roots = {}

	for _, desc in ipairs(RigTraversal.rigDescendants(rig)) do
		if desc:IsA("BasePart") and self:IsRigRootPart(desc, outgoing, incoming) then
			table.insert(roots, desc)
		end
	end

	table.sort(roots, function(a, b)
		return a.Name < b.Name
	end)

	return roots
end

function Rig:CreateBonesForRig(rig)
	if not rig or not rig.Parent then
		return
	end

	if rig and Properties.propertyOnly(rig) then
		return
	end

	require("NativeJoints").prepare(rig)
	LimbIK.invalidate(rig)
	local cam = self:GetCamera()
	if not cam or not rig then
		return
	end

	self._cachedRigForBones = nil
	self._cachedBonesFolder = nil
	self._boneFollowCaches[rig] = nil
	self._partToMotorCache = setmetatable({}, { __mode = "kv" })
	self._boneToRigPartCache = setmetatable({}, { __mode = "kv" })

	local folderName = self:GetBonesFolderName(rig)
	local oldFolder = self:GetBonesFolder(rig)
	if oldFolder then
		oldFolder:Destroy()
	end

	local bonesFolder = Instance.new("Folder")
	bonesFolder.Name = folderName
	require("Recovery").mark(bonesFolder)
	bonesFolder:SetAttribute("EclipseAnimator_BonesFolder", true)

	local sourceRigValue = Instance.new("ObjectValue")
	sourceRigValue.Name = "EclipseSourceRig"
	sourceRigValue.Value = rig
	sourceRigValue.Parent = bonesFolder

	bonesFolder.Parent = cam
	self._ownedBoneFolders[rig] = bonesFolder
	if CameraRig.isRig(rig) then
		bonesFolder:Destroy()
		self._ownedBoneFolders[rig] = CameraDisplay.create(rig, cam, folderName)
		return
	end

	MasterControl.makeMarker(rig, bonesFolder)

	local outgoing, incoming = self:GetMotorGraph(rig)
	local humanoidRoot = MasterControl.enabled(rig) and MasterControl.root(rig)
		or rig:FindFirstChild("HumanoidRootPart")

	local candidateParts = {}
	local explicitArmature = ArmatureRuntime.isRig(rig)
	for _, part in ipairs(RigTraversal.rigDescendants(rig)) do
		if part:IsA("BasePart") and not explicitArmature then
			table.insert(candidateParts, part)
		end
	end

	for _, part in ipairs(self:GetExternalAttachedParts(rig)) do
		table.insert(candidateParts, part)
	end

	local workState = require("State")
	for _, part in ipairs(candidateParts) do
		if workState.ProjectWorkStep then
			workState.ProjectWorkStep()
		end

		if part:IsA("BasePart") then
			if part == humanoidRoot or part:GetAttribute("EclipsePartRigRoot") then
				continue
			end

			if (incoming[part] or 0) == 0 and (outgoing[part] or 0) == 0 then
				continue
			end

			local bone = PartHandles.create(part)
			bone.Name = part.Name .. "_Bone"
			bone.Parent = bonesFolder
			bone:SetAttribute("SourcePartName", part.Name)

			for _, child in ipairs(bone:GetChildren()) do
				if not child:IsA("DataModelMesh") then
					child:Destroy()
				end
			end

			local reference = Instance.new("ObjectValue")
			reference.Name, reference.Value, reference.Parent = "EclipseSourcePart", part, bone
			bone.Size = part.Size * 1.01
			bone.CFrame = part.CFrame
			bone.Transparency = 1
			bone.Color = Color3.fromRGB(93, 131, 165)
			bone.Material = Enum.Material.Neon
			bone.Locked = true
			bone.Anchored = true
			bone.CanCollide = false
			bone.CanQuery = true
			bone.CanTouch = false
			PartHandles.update(bone, part)
		end
	end

	local armaturePresent = self:FindArmatureModel(rig) ~= nil
	bonesFolder:SetAttribute("EclipseArmatureMode", armaturePresent)
	self._cachedArmatureModel = nil
	self._armatureBoneMap = nil
	do
		local markerColor = Color3.fromRGB(138, 20, 255)
		local _, boneChildren = self:GetRobloxBoneTree(rig)
		local allBones = {}
		for _, d in ipairs(RigTraversal.rigDescendants(rig)) do
			if
				d:IsA("Bone")
				and not d:GetAttribute("EclipseArmatureSkinningHelper")
				and not R6Controls.isControl(d)
				and not explicitArmature
			then
				table.insert(allBones, d)
			end
		end

		local function linkDia(parentBone, childBone)
			local mag = (BoneIK.worldOf(childBone).Position - BoneIK.worldOf(parentBone).Position).Magnitude
			return mag / 10
		end

		local function makeLinkPart(name)
			local link = Instance.new("Part")
			link.Name = name
			link.Anchored = true
			link.CanCollide = false
			link.CanTouch = false
			link.CanQuery = true
			link.Locked = true
			link.Transparency = 1
			link.CastShadow = false
			local coneBig = Instance.new("ConeHandleAdornment")
			coneBig.Name = "ConeBig"
			coneBig.Adornee = link
			coneBig.AlwaysOnTop = true
			coneBig.ZIndex = 0
			coneBig.Transparency = 0.6
			coneBig.Color3 = markerColor
			coneBig.SizeRelativeOffset = Vector3.new(0, 0, 0.8)
			coneBig.Parent = link
			local coneSmall = Instance.new("ConeHandleAdornment")
			coneSmall.Name = "ConeSmall"
			coneSmall.Adornee = link
			coneSmall.AlwaysOnTop = true
			coneSmall.ZIndex = 0
			coneSmall.Transparency = 0.2
			coneSmall.Color3 = markerColor
			coneSmall.CFrame = CFrame.Angles(0, math.pi, 0)
			coneSmall.SizeRelativeOffset = Vector3.new(0, 0, 0.8)
			coneSmall.Parent = link
			return link
		end

		for _, boneInst in ipairs(allBones) do
			local parentBone = boneInst.Parent
			local hasParentBone = parentBone ~= nil and parentBone:IsA("Bone")
			local dia = 0.12
			if hasParentBone then
				dia = linkDia(parentBone, boneInst)
			elseif boneChildren[boneInst] and boneChildren[boneInst][1] then
				dia = linkDia(boneInst, boneChildren[boneInst][1])
			end

			local joint = Instance.new("Part")
			joint.Name = boneInst.Name .. "_Bone"
			joint:SetAttribute("SourcePartName", boneInst.Name)
			local reference = Instance.new("ObjectValue")
			reference.Name, reference.Value, reference.Parent = "EclipseSourcePart", boneInst, joint
			joint:SetAttribute("SourceIsBone", true)
			joint:SetAttribute("MarkerColor", markerColor)
			joint.Size = Vector3.one * math.max(dia, 0.1)
			joint.CFrame = BoneIK.worldOf(boneInst)
			joint.Transparency = 1
			joint.Color = markerColor
			joint.Material = Enum.Material.Neon
			joint.Locked = true
			joint.Anchored = true
			joint.CanCollide = false
			joint.CanQuery = not armaturePresent
			joint.CanTouch = false
			if not armaturePresent then
				local handle = Instance.new("SphereHandleAdornment")
				handle.Name = "Handle"
				handle.Adornee = joint
				handle.AlwaysOnTop = true
				handle.ZIndex = 1
				handle.Radius = math.max(dia / 2, 0.04)
				handle.Color3 = markerColor
				handle.Transparency = 0.2
				handle.Parent = joint
			end

			joint.Parent = bonesFolder
			if not armaturePresent and hasParentBone then
				local link = makeLinkPart(boneInst.Name .. "_BoneLink")
				link:SetAttribute("EclipseBoneLink", boneInst.Name)
				link:SetAttribute("EclipseLinkParent", parentBone.Name)
				local childRef, parentRef = Instance.new("ObjectValue"), Instance.new("ObjectValue")
				childRef.Name, childRef.Value, childRef.Parent = "EclipseLinkChild", boneInst, link
				parentRef.Name, parentRef.Value, parentRef.Parent =
					"EclipseLinkParentRef", parentBone, link
				link:SetAttribute("MarkerColor", markerColor)
				link.Parent = bonesFolder
			end

			if not armaturePresent and not boneChildren[boneInst] then
				local endMarker = makeLinkPart(boneInst.Name .. "_BoneEnd")
				endMarker:SetAttribute("EclipseBoneLink", boneInst.Name)
				if hasParentBone then
					endMarker:SetAttribute("EclipseLinkParent", parentBone.Name)
				end

				endMarker:SetAttribute("EclipseBoneEnd", true)
				local childRef, parentRef = Instance.new("ObjectValue"), Instance.new("ObjectValue")
				childRef.Name, childRef.Value, childRef.Parent =
					"EclipseLinkChild", boneInst, endMarker
				parentRef.Name, parentRef.Value, parentRef.Parent =
					"EclipseLinkParentRef", if hasParentBone then parentBone else nil, endMarker
				endMarker:SetAttribute("EndDia", dia)
				endMarker:SetAttribute("MarkerColor", markerColor)
				endMarker.Parent = bonesFolder
			end
		end

		if armaturePresent then
			local armModel = self:FindArmatureModel(rig)
			if armModel then
				local realNames = {}
				for _, b in ipairs(allBones) do
					realNames[b.Name] = true
				end

				for _, anchor in ipairs(armModel:GetChildren()) do
					if
						anchor:IsA("BasePart")
						and anchor:GetAttribute("EclipseArmatureBone")
						and anchor:GetAttribute("EclipseArmatureControl") ~= false
						and (explicitArmature or not realNames[anchor.Name])
					then
						local vjoint = Instance.new("Part")
						vjoint.Name = (anchor:GetAttribute("EclipseArmatureBoneId") or anchor.Name)
							.. "_Bone"
						vjoint:SetAttribute("SourcePartName", anchor.Name)
						if explicitArmature then
							local reference = Instance.new("ObjectValue")
							reference.Name, reference.Value, reference.Parent =
								"EclipseArmatureSource", anchor, vjoint
						end

						vjoint:SetAttribute("SourceIsVirtual", true)
						vjoint:SetAttribute("MarkerColor", markerColor)
						vjoint.Size = Vector3.new(0.2, 0.2, 0.2)
						vjoint.CFrame =
							CFrame.new(anchor.CFrame:PointToWorldSpace(anchor.PivotOffset.Position))
						vjoint.Transparency = 1
						vjoint.Locked = true
						vjoint.Anchored = true
						vjoint.CanCollide = false
						vjoint.CanQuery = false
						vjoint.CanTouch = false
						vjoint.Parent = bonesFolder
					end
				end
			end
		end

		if not explicitArmature then
			LimbControls.create(rig, bonesFolder)
		end

		self:UpdateBonesFollowRig(rig)
	end
end

function Rig:UpdateBonesFollowRig(currentRig, skipMarkers)
	return require("cache").withPose(function()
		self:_UpdateBonesFollowRig(currentRig, skipMarkers)
		require("Organization").applyCollectionVisibility(currentRig, self)
	end)
end

function Rig:_UpdateBonesFollowRig(currentRig, skipMarkers)
	require("PartRig").flush(currentRig)
	require("NativeJoints").flush(currentRig)
	if not currentRig then
		return
	end

	local cache = self._boneFollowCaches[currentRig]
	if
		not cache
		or cache.folder.Parent ~= self:GetCamera()
		or cache.folder.Name ~= self:GetBonesFolderName(currentRig)
	then
		local folder = self:GetBonesFolder(currentRig)
		if not folder then
			return
		end

		cache = { folder = folder, parts = setmetatable({}, { __mode = "k" }) }
		self._boneFollowCaches[currentRig] = cache
	end

	local bonesFolder = cache.folder
	require("handles").bindDepth(bonesFolder)
	if skipMarkers and bonesFolder:GetAttribute("EclipsePlaybackHidden") then
		ArmatureRuntime.evaluate(currentRig)
		return
	end

	if not bonesFolder then
		return
	end

	if CameraRig.isRig(currentRig) then
		CameraDisplay.update(bonesFolder)
		return
	end

	local masterMarker = bonesFolder:FindFirstChild("MasterControl_Bone")
	local masterMotor = masterMarker and MasterControl.get(currentRig)
	if masterMotor then
		local world = masterMotor.Part0.CFrame * masterMotor.C0
		if masterMarker.CFrame ~= world then
			masterMarker.CFrame = world
		end
	end

	if ArmatureRuntime.isRig(currentRig) then
		ArmatureRuntime.evaluate(currentRig)
		local arm = cache.armature
		if not (arm and arm.Parent) then
			if cache.armatureMissAt and os.clock() - cache.armatureMissAt < 1 then
				arm = nil
			else
				arm = self:FindArmatureModel(currentRig)
				cache.armature = arm
				cache.armatureMissAt = not arm and os.clock() or nil
			end
		end

		require("handles").bindDepth(arm)
		local visibility = arm and arm:GetAttribute("EclipseArmatureVisibilityVersion")
		self._armatureVisibilityVersions = self._armatureVisibilityVersions
			or setmetatable({}, { __mode = "k" })
		if self._armatureVisibilityVersions[currentRig] ~= visibility then
			self._armatureVisibilityVersions[currentRig] = visibility
			if self._orderedItems and not self._rebuilding then
				self:RefreshSelectionFilter()
			end
		end

		local revision = ArmatureRuntime.revision(currentRig)
		local presentationRevision = require("Organization").presentationRevision()
		if
			cache.markerRevision == revision
			and cache.presentationRevision == presentationRevision
		then
			return
		end

		for _, marker in bonesFolder:GetChildren() do
			local reference = marker:FindFirstChild("EclipseArmatureSource")
			local anchor = reference and reference.Value
			if anchor and anchor.Parent then
				local world = ArmatureRuntime.worldCFrame(anchor, currentRig)
				if world and marker.CFrame ~= world then
					marker.CFrame = world
				end

				require("handles").updateArmature(marker, anchor)
			end
		end

		cache.markerRevision = revision
		cache.presentationRevision = presentationRevision
		return
	end

	local boneCache = cache.parts
	local nameToPart = nil
	local boneNames

	local function namedBone(name, first)
		if not name then
			return nil
		end

		if not boneNames then
			boneNames = { first = {}, last = {} }
			for _, object in RigTraversal.rigDescendants(currentRig) do
				if
					object:IsA("Bone")
					and not object:GetAttribute("EclipseArmatureSkinningHelper")
				then
					boneNames.first[object.Name] = boneNames.first[object.Name] or object
					boneNames.last[object.Name] = object
				end
			end
		end

		return (first and boneNames.first or boneNames.last)[name]
	end

	cache.worlds = cache.worlds or {}
	local worlds = cache.worlds
	table.clear(worlds)

	local function boneWorld(object)
		local world = worlds[object]
		if world then
			return world
		end

		world = if object:IsA("Bone")
			then boneWorld(object.Parent) * object.CFrame * object.Transform
			else object.CFrame
		worlds[object] = world
		return world
	end

	for _, bone in ipairs(bonesFolder:GetChildren()) do
		if bone:GetAttribute("SourceIsBone") or bone:GetAttribute("EclipseBoneLink") then
			for _, adorn in bone:GetChildren() do
				if adorn:IsA("HandleAdornment") then
					adorn.Transparency = (Preferences.get("CustomBoneTransparency") or 20) / 100
				end
			end
		end

		if bone:GetAttribute("EclipseMasterMarker") then
			local master = MasterControl.get(currentRig)
			if master then
				bone.CFrame = master.Part0.CFrame * master.C0
			end

			continue
		elseif bone:GetAttribute("EclipseLimbControl") then
			continue
		elseif bone:IsA("BasePart") and bone:GetAttribute("EclipseBoneLink") then
			local show = not Preferences.get("HideBoneLines")
				and not bonesFolder:GetAttribute("EclipsePlaybackHidden")
			for _, adorn in bone:GetChildren() do
				if adorn:IsA("HandleAdornment") and adorn.Visible ~= show then
					adorn.Visible = show
				end
			end

			if not show then
				continue
			end

			local refs = boneCache[bone]
			if refs and ((refs.c and not refs.c.Parent) or (refs.p and not refs.p.Parent)) then
				refs = nil
			end

			if not refs then
				local childName = bone:GetAttribute("EclipseBoneLink")
				local parentName = bone:GetAttribute("EclipseLinkParent")
				local childRef = bone:FindFirstChild("EclipseLinkChild")
				local parentRef = bone:FindFirstChild("EclipseLinkParentRef")
				local childBone = if childRef then childRef.Value else namedBone(childName, false)
				local parentBone = if parentRef
					then parentRef.Value
					else namedBone(parentName, false)
				if childBone then
					refs = { c = childBone, p = parentBone }
					boneCache[bone] = refs
				end
			end

			if refs and refs.c then
				local childCF = boneWorld(refs.c)
				if bone:GetAttribute("EclipseBoneEnd") then
					local dia = bone:GetAttribute("EndDia") or 0.1
					local mag = dia * 10
					if refs.p then
						mag = (childCF.Position - boneWorld(refs.p).Position).Magnitude
						dia = mag / 10
					end

					local rad = dia / 2
					local height = dia * 5
					local up = childCF.UpVector
					local endCF = CFrame.new(
						childCF.Position + (dia * 2 + rad) * up,
						childCF.Position + (mag / 2) * up
					)
					if refs.dia ~= dia then
						refs.dia = dia
						local cs = bone:FindFirstChild("ConeSmall")
						local cb = bone:FindFirstChild("ConeBig")
						if cs then
							cs.Radius = rad
							cs.Height = height / 10
						end

						if cb then
							cb.Radius = rad
							cb.Height = height - height / 10
						end

						bone.Size = Vector3.new(dia, dia, height)
					end

					if bone.CFrame ~= endCF then
						bone.CFrame = endCF
					end
				elseif refs.p then
					local parentPos = boneWorld(refs.p).Position
					local diff = childCF.Position - parentPos
					local mag = diff.Magnitude
					if mag > 1e-4 then
						local dia = mag / 10
						if math.abs((refs.mag or 0) - mag) > 1e-5 then
							refs.mag = mag
							local cs = bone:FindFirstChild("ConeSmall")
							local cb = bone:FindFirstChild("ConeBig")
							if cs then
								cs.Radius = dia
								cs.Height = dia
							end

							if cb then
								cb.Radius = dia
								cb.Height = mag - dia
							end

							bone.Size = Vector3.new(0.2 * mag, 0.2 * mag, mag)
						end

						local linkCF = CFrame.new(parentPos + diff * 0.5, childCF.Position)
						if bone.CFrame ~= linkCF then
							bone.CFrame = linkCF
						end
					end
				end
			end
		elseif bone:IsA("BasePart") and bone:GetAttribute("SourceIsBone") then
			local reference = bone:FindFirstChild("EclipseSourcePart")
			local srcBone = reference and reference.Value or boneCache[bone]
			if not srcBone or not srcBone.Parent then
				local sourceName = bone:GetAttribute("SourcePartName")
				if sourceName then
					srcBone = namedBone(sourceName, true)
					if srcBone then
						boneCache[bone] = srcBone
					end
				end
			end

			if srcBone and srcBone.Parent then
				local world = boneWorld(srcBone)
				if bone.CFrame ~= world then
					bone.CFrame = world
				end
				PartHandles.updateFront(bone, world, bone.Size, bone.CanQuery)
			end
		elseif bone:IsA("BasePart") then
			local reference = bone:FindFirstChild("EclipseSourcePart")
			local realPart = reference and reference.Value or boneCache[bone]
			if not realPart or not realPart.Parent then
				local sourceName = bone:GetAttribute("SourcePartName")
				if sourceName then
					if not nameToPart then
						nameToPart = {}
						for _, desc in ipairs(RigTraversal.rigDescendants(currentRig)) do
							if desc:IsA("BasePart") then
								nameToPart[desc.Name] = desc
							end
						end

						for _, extPart in ipairs(self:GetExternalAttachedParts(currentRig)) do
							nameToPart[extPart.Name] = extPart
						end
					end

					realPart = nameToPart[sourceName]
					if realPart then
						boneCache[bone] = realPart
					end
				end
			end

			if realPart and realPart.Parent then
				if bone.CFrame ~= realPart.CFrame then
					bone.CFrame = realPart.CFrame
				end

				PartHandles.update(bone, realPart)
			end
		end
	end

	LimbControls.update(currentRig, bonesFolder, self:GetCamera())

	if bonesFolder:GetAttribute("EclipseArmatureMode") then
		local armatureModel = cache.armature
		if not (armatureModel and armatureModel.Parent) then
			armatureModel = self:FindArmatureModel(currentRig)
			cache.armature = armatureModel
		end

		if armatureModel then
			local nameToBone = cache.boneMap
			if not nameToBone then
				nameToBone = {}
				for _, desc in ipairs(RigTraversal.rigDescendants(currentRig)) do
					if
						desc:IsA("Bone")
						and not desc:GetAttribute("EclipseArmatureSkinningHelper")
					then
						nameToBone[desc.Name] = desc
					end
				end

				cache.boneMap = nameToBone
			end

			for _, anchor in ipairs(armatureModel:GetChildren()) do
				if anchor:IsA("BasePart") and anchor:GetAttribute("EclipseArmatureBone") then
					local offset = anchor:GetAttribute("EclipseBindOffset")
					local srcBone = nameToBone[anchor.Name]
					if typeof(offset) == "CFrame" and srcBone and srcBone.Parent then
						anchor.CFrame = boneWorld(srcBone) * offset
					else
						local followName = anchor:GetAttribute("EclipseFollowBone")
						local followOffset = anchor:GetAttribute("EclipseFollowOffset")
						local followBone = followName and nameToBone[followName]
						if
							typeof(followOffset) == "CFrame"
							and followBone
							and followBone.Parent
						then
							anchor.CFrame = boneWorld(followBone) * followOffset
						end
					end
				end
			end

			for _, folderPart in ipairs(bonesFolder:GetChildren()) do
				if folderPart:IsA("BasePart") and folderPart:GetAttribute("SourceIsVirtual") then
					local anchor =
						armatureModel:FindFirstChild(folderPart:GetAttribute("SourcePartName"))
					if anchor and anchor:IsA("BasePart") then
						folderPart.CFrame =
							CFrame.new(anchor.CFrame:PointToWorldSpace(anchor.PivotOffset.Position))
					end
				end
			end
		end
	end
end

function Rig:FadeSelectionBones(currentRig, selected)
	local bonesFolder = self:GetBonesFolder(currentRig)
	if not bonesFolder then
		return
	end

	for _, bone in ipairs(bonesFolder:GetChildren()) do
		if bone:IsA("BasePart") then
			PartHandles.select(bone, table.find(selected, bone) ~= nil)
			TweenService:Create(
				bone,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			):Play()
		end
	end

	for _, inst in ipairs(selected) do
		if inst:IsDescendantOf(bonesFolder) then
			TweenService
				:Create(
					inst,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Transparency = (
							inst:GetAttribute("EclipseMasterMarker")
							or Preferences.get("BoneStyle") == 2
						)
								and 1
							or (Preferences.get("FullBoneTransparency") or 80) / 100,
					}
				)
				:Play()
		end
	end
end

function Rig:SetSelectionFilter(enabled)
	self.onlyShowSelected = enabled == true
	self:RefreshSelectionFilter()
end

function Rig:RefreshDisplayPreferences()
	for _, master in ipairs(self._masterItems) do
		master:refreshDisplayPreferences()
	end

	for _, listItem in ipairs(self._orderedItems) do
		listItem:refreshDisplayPreferences()
	end

	self:RefreshSelectionFilter()
end

function Rig:BindDisplayPreferences()
	if self._preferencesDisconnect then
		self._preferencesDisconnect()
	end

	self._preferencesDisconnect = Preferences.subscribe(function(key)
		if
			(key == "BoneStyle" or key == "FullBoneTransparency" or key == "HandleBoneTransparency")
			and self.refs.Axis
		then
			self.refs.Axis:RefreshBoneFade()
		end

		if
			key == "ShowFKIK"
			or key == "ShowHeadStabilizer"
			or key == "ShowMotionPaths"
			or key == "TransformChannels"
			or key == "FlatBoneList"
		then
			self:RefreshDisplayPreferences()
		end
	end)
	self:RefreshDisplayPreferences()
end

function Rig:RefreshSelectionFilter()
	if self.refs.Timeline.RefreshJumpPinRows then
		self.refs.Timeline:RefreshJumpPinRows()
	end

	local selected = {}
	for listItem in pairs(self._selectedItems) do
		selected[listItem] = true
	end

	for channel in pairs(self._selectedChannels) do
		if channel.parentBoneItem then
			selected[channel.parentBoneItem] = true
		end
	end

	local timeline = self.refs.Timeline:GetState()
	local motors = {}
	for key in pairs(timeline.SelectedKeyframes) do
		if key.Motor then
			motors[key.Motor] = true
		end
	end

	for key in pairs(timeline.SelectedChannelKeyframes) do
		if key.Motor then
			motors[key.Motor] = true
		end
	end

	for _, listItem in ipairs(self._orderedItems) do
		if motors[listItem:fetchMotor()] then
			selected[listItem] = true
		end
	end

	local filtered = self.onlyShowSelected and next(selected) ~= nil

	local function visit(listItem, parentOpen, hidden)
		local source = listItem.linkedRigInstance
		local controlHidden = source
			and ArmatureRuntime.isAnchor(source)
			and (
				source:GetAttribute("Hidden") == true
				or source:GetAttribute("EclipseArmatureUnselectable") == true
			)
		local show = filtered and selected[listItem] == true or not filtered and parentOpen
		if
			listItem.itemKind == "events"
			or listItem.itemKind == "subtitles"
			or listItem.itemKind == "faces"
		then
			show = parentOpen and listItem:eventsVisible()
		end

		if
			listItem.itemKind == "ikcontrol"
			and (
				not LimbIK.controlsVisible(listItem:fetchMotor().Owner)
				or not R6Controls.visible(listItem:fetchMotor())
			)
		then
			show = false
		end

		if listItem.trackIsMaster then
			show = parentOpen or filtered
		end

		if hidden or controlHidden then
			show = false
		end

		listItem._controlHidden = controlHidden == true
		local contents = listItem.childContainer.ChildrenContents
		listItem._contentsPosition = listItem._contentsPosition or contents.Position
		listItem._contentsSize = listItem._contentsSize or contents.Size
		contents.Position = controlHidden
				and UDim2.new(
					0,
					0,
					listItem._contentsPosition.Y.Scale,
					listItem._contentsPosition.Y.Offset
				)
			or listItem._contentsPosition
		contents.Size = controlHidden
				and UDim2.new(1, 0, listItem._contentsSize.Y.Scale, listItem._contentsSize.Y.Offset)
			or listItem._contentsSize
		local padding = listItem.childContainer.ChildrenContents:FindFirstChildOfClass("UIPadding")
		if padding then
			if not listItem._filterPaddingTop then
				listItem._filterPaddingTop = padding.PaddingTop
			end

			listItem._filterPaddingLeft = listItem._filterPaddingLeft or padding.PaddingLeft
			padding.PaddingLeft = controlHidden and UDim.new() or listItem._filterPaddingLeft
			padding.PaddingTop = (controlHidden or filtered and not show) and UDim.new()
				or listItem._filterPaddingTop
		end

		local childrenShown = false
		local hideChildren = hidden or (self._dragHiddenItems and self._dragHiddenItems[listItem])
		for _, child in ipairs(listItem.childItems) do
			if
				visit(
					child,
					parentOpen
						and (
							listItem.openedState
							or controlHidden
							or TrackHierarchy.flatBone(listItem)
								and TrackHierarchy.flatBone(child)
						),
					hideChildren
				)
			then
				childrenShown = true
			end
		end

		local channelsShown = false
		for _, channel in ipairs(listItem.transformChannelItems or {}) do
			local visible = not hideChildren
				and show
				and listItem.transformChannelsOpen
				and (filtered or listItem.openedState)
			channel.uiElement.Visible = visible == true
			channel.trackElement.Visible = visible == true
			channelsShown = channelsShown or visible
		end

		listItem:setMoreButtonVisibility(listItem:hasExpandableChildren())
		listItem.appearDetails.Visible = show
		local guide = listItem.childContainer:FindFirstChild("ListMonger")
		if guide then
			guide.Visible = show == true
		end

		listItem.uiElement.Visible = show or childrenShown
		listItem.trackElement.Visible = show
		listItem.childContainer.Visible = childrenShown or channelsShown
		if listItem.trackIsMaster then
			listItem.trackElement.TrackContainers.Visible = not self._organizationReady
				and (filtered or listItem.openedState)
		end

		return show or childrenShown
	end

	for _, master in ipairs(self._rootItems or self._masterItems) do
		visit(master, true, false)
	end

	TrackHierarchy.layout(self)
end

function Rig:StopSelectionSync()
	self._revealVersion = (self._revealVersion or 0) + 1
	table.clear(self._boneFollowCaches)
	if self._selectionSyncConn then
		self._selectionSyncConn:Disconnect()
		self._selectionSyncConn = nil
	end

	self._lastObservedSelectedBone = nil
end

function Rig:StartSelectionSync(currentRig)
	self:StopSelectionSync()

	self._lastObservedSelectedBone = self.refs.Axis and self.refs.Axis:GetSelectedBone() or nil

	self._selectionSyncConn = RunService.Heartbeat:Connect(function()
		if not currentRig then
			self:StopSelectionSync()
			return
		end

		if self._primaryRigInstance ~= currentRig then
			return
		end

		self:RefreshIKChildren(currentRig)

		if not self._refreshHierarchyVisuals then
			return
		end

		local selectedBone = self.refs.Axis and self.refs.Axis:GetSelectedBone() or nil
		if selectedBone ~= self._lastObservedSelectedBone then
			self._lastObservedSelectedBone = selectedBone

			if selectedBone then
				local matchingItem = self:_FindItemForBone(selectedBone)
				local matchingKey = matchingItem and TrackHierarchy.key(matchingItem)
				self._explicitSelectedKeys = matchingKey and { [matchingKey] = true } or {}
				if matchingItem then
					if not self._selectedItems[matchingItem] then self._selectedItems = { [matchingItem] = true } end
					self._lastClickedItem = matchingItem
					require("PoseSliders").focus(matchingItem:fetchMotor())
				end
			else
				self._selectedItems = {}
				self._explicitSelectedKeys = {}
				self._lastClickedItem = nil
			end

			self._refreshHierarchyVisuals()
			self:SelectKeysForSelectedParts()
			if selectedBone then
				self:RevealBone(selectedBone)
			end
		end
	end)
end

function Rig:_FindItemForBone(bone)
	if not bone then
		return nil
	end

	for _, item in ipairs(self._orderedItems) do
		if item:fetchBone() == bone then
			return item
		end
	end

	local reference = bone:FindFirstChild("EclipseLimbOwner")
	if
		reference
		and not R6Controls.find(
			R6Controls.resolveOwner(reference.Value),
			bone:GetAttribute("EclipseLimbControl")
		)
	then
		for _, item in self._orderedItems do
			if item.linkedRigInstance == R6Controls.resolveOwner(reference.Value).Part1 then
				return item
			end
		end
	end

	return nil
end

function Rig:ScrollItemIntoView(item)
	local scroll = self.refs.RigListScroll
	local row = item and item.appearDetails
	if not scroll or not scroll.Parent or not row or not row.Parent or not row.Visible then
		return
	end

	local bounds = item._virtualBounds
	local scale = 1
	local ancestor = scroll
	while ancestor do
		local uiScale = ancestor:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end

		ancestor = ancestor.Parent
	end

	local top = bounds and (bounds.top - scroll.CanvasPosition.Y) * scale
		or row.AbsolutePosition.Y - scroll.AbsolutePosition.Y
	local height = scroll.AbsoluteWindowSize.Y
	local bottom = top + (bounds and (bounds.bottom - bounds.top) * scale or row.AbsoluteSize.Y)
	local offset = top < 0 and top or bottom > height and bottom - height or 0
	if math.abs(offset) < 1 then
		return
	end

	local limit = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
	scroll.CanvasPosition = Vector2.new(
		scroll.CanvasPosition.X,
		math.clamp(
			scroll.CanvasPosition.Y + offset / (bounds and scale or 1),
			0,
			limit / (bounds and scale or 1)
		)
	)
end

function Rig:RevealBone(bone)
	local item = self:_FindItemForBone(bone)
	if not item then
		return
	end

	local ancestors = {}
	local parent = item.parentItem
	while parent do
		table.insert(ancestors, parent)
		parent = parent.parentItem
	end

	for i = #ancestors, 1, -1 do
		if
			not ancestors[i].openedState
			and not (
				TrackHierarchy.flatBone(ancestors[i])
				and TrackHierarchy.flatBone(ancestors[i - 1] or item)
			)
		then
			ancestors[i]:setOpenState(true)
		end
	end

	self:RefreshSelectionFilter()
	self._revealVersion = (self._revealVersion or 0) + 1
	local version = self._revealVersion
	task.defer(function()
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		if
			self._revealVersion == version
			and self.refs.Axis
			and self.refs.Axis:GetSelectedBone() == bone
		then
			self:ScrollItemIntoView(item)
		end
	end)
end

function Rig:_GetItemIndex(item)
	for i, it in ipairs(self._orderedItems) do
		if it == item then
			return i
		end
	end

	return nil
end

function Rig:_PickPrimaryBone()
	if self._lastClickedItem and self._selectedItems[self._lastClickedItem] then
		local bone = self._lastClickedItem:fetchBone()
		if bone then
			return bone
		end
	end

	for item in pairs(self._selectedItems) do
		local bone = item:fetchBone()
		if bone then
			return bone
		end
	end

	return nil
end

function Rig:SelectKeysForSelectedParts()
	if not require("Preferences").get("SelectKeysWithRigParts") then return end
	local timeline = self.refs.Timeline
	if not timeline or timeline:IsExportLocked() then return end
	local state = require("State")
	local raw = timeline:GetState()
	if state.LoadingProject or raw.Playing then return end
	local keys, motors = {}, {}
	for item in self._selectedItems do
		local motor = item:fetchMotor()
		if motor and not motors[motor] then
			motors[motor] = true
			for _, key in raw.Keyframes[motor] or {} do table.insert(keys, key) end
		end
	end
	timeline:SetSelectedKeyframes(keys)
end

function Rig:_SyncAxisToPrimary()
	require("SceneSync").deselect()
	local item = self._lastClickedItem
	if item and self._selectedItems[item] then require("PoseSliders").focus(item:fetchMotor()) end
	local owner = item and (item.grandpa or item)
	if owner and owner.itemKind ~= "origin" and typeof(owner.linkedRigInstance) == "Instance" then
		self._lastEventRig = owner.linkedRigInstance
	end

	if not self.refs.Axis then
		return
	end

	local bones = {}
	for item in pairs(self._selectedItems) do
		if item ~= self._lastClickedItem then
			local bone = item:fetchBone()
			if bone then
				table.insert(bones, bone)
			end
		end
	end

	if self._lastClickedItem and self._selectedItems[self._lastClickedItem] then
		local primaryBone = self._lastClickedItem:fetchBone()
		if primaryBone then
			table.insert(bones, primaryBone)
		end
	end

	self.refs.Axis:SelectBones(bones)
	self._lastObservedSelectedBone = self.refs.Axis:GetSelectedBone()
	if self.refs.PropertySelection then
		local selected = nil
		local count = 0
		for item in self._selectedItems do
			count += 1
			selected = item
		end

		local group = {}
		for item in self._selectedItems do
			local motor = item:fetchMotor()
			if not Properties.is(motor) or motor.PropertyId ~= "CFrame" then
				table.clear(group)
				break
			end
			table.insert(group, motor)
		end
		local properties = {}
		for item in self._selectedItems do
			local motor = item:fetchMotor()
			if Properties.is(motor) and motor.PropertyId == "CFrame" then
				table.insert(properties, motor)
			end
		end

		local primary = self._lastClickedItem and self._lastClickedItem:fetchMotor()
		if #properties > 0 and #bones > 0 and self.refs.Axis.SelectBonesWithProperties then
			self.refs.PropertySelection(nil)
			local lead = Properties.is(primary) and primary.PropertyId == "CFrame" and primary or nil
			self.refs.Axis:SelectBonesWithProperties(bones, properties, lead)
		elseif #group > 1 then
			self.refs.PropertySelection(primary or group[1], group)
		else
			self.refs.PropertySelection(count == 1 and selected and selected:fetchMotor() or nil)
		end
		self._lastObservedSelectedBone = self.refs.Axis:GetSelectedBone()
	end
end

function Rig:RefreshHierarchySelectionVisuals()
	if self.refs.Timeline.RefreshJumpPinRows then
		self.refs.Timeline:RefreshJumpPinRows()
	end

	if self._refreshHierarchyVisuals then
		self._refreshHierarchyVisuals()
	end
end

function Rig:PropertyItem(rig, id)
	for _, item in self._orderedItems do
		if item.itemKind == "property" then
			local motor = item:fetchMotor()
			if motor and motor.Rig == rig and motor.PropertyId == id then
				return item
			end
		end
	end
end

function Rig:SelectPropertyPart(part)
	if not part then
		return false
	end

	for _, master in self._masterItems do
		local rig = master.linkedRigInstance
		if rig and (part == rig or part:IsDescendantOf(rig)) then
			if part ~= rig and self:GetMotorForPart(rig, part) then
				return false
			end

			local item = self:PropertyItem(rig, "CFrame")
			if item then
				local input = require("UserInputService")
				if input:IsKeyDown(Enum.KeyCode.LeftControl) or input:IsKeyDown(Enum.KeyCode.RightControl) then
					self:ToggleItemSelection(item)
				else
					self:SetSingleItemSelection(item)
				end
				return true
			end
		end
	end

	return false
end

function Rig:SelectPropertyUnderMouse()
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local include = {}
	for _, master in self._masterItems do
		local rig = master.linkedRigInstance
		if rig and self:PropertyItem(rig, "CFrame") then
			table.insert(include, rig)
		end
	end

	if #include == 0 then
		return false
	end

	local mouse = game:GetService("UserInputService"):GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return hit ~= nil and self:SelectPropertyPart(hit.Instance)
end

function Rig:SetSingleItemSelection(item)
	if item.trackIsMaster then
		item = self:PropertyItem(item.linkedRigInstance, "CFrame") or item
	end

	self._selectedItems = { [item] = true }
	local key = TrackHierarchy.key(item)
	self._explicitSelectedKeys = key and { [key] = true } or {}
	self._lastClickedItem = item
	self._selectedChannels = {}
	self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
	self:RefreshHierarchySelectionVisuals()
end

function Rig:SetSingleChannelSelection(channelItem)
	self._selectedChannels = { [channelItem] = true }
	self:RefreshHierarchySelectionVisuals()
end

function Rig:AddChannelSelection(channelItem)
	self._selectedChannels[channelItem] = true
	self:RefreshHierarchySelectionVisuals()
end

function Rig:ToggleChannelSelection(channelItem)
	if self._selectedChannels[channelItem] then
		self._selectedChannels[channelItem] = nil
	else
		self._selectedChannels[channelItem] = true
	end

	self:RefreshHierarchySelectionVisuals()
end

function Rig:ClearChannelSelection()
	self._selectedChannels = {}
	self:RefreshHierarchySelectionVisuals()
end

function Rig:GetSelectedChannels()
	local list = {}
	for ch in pairs(self._selectedChannels) do
		table.insert(list, ch)
	end

	return list
end

function Rig:IsChannelSelected(channelItem)
	return self._selectedChannels[channelItem] == true
end

function Rig:ToggleItemSelection(item)
	if self._selectedItems[item] then
		self._selectedItems[item] = nil
		if self._lastClickedItem == item then
			self._lastClickedItem = nil
			for it in pairs(self._selectedItems) do
				self._lastClickedItem = it
				break
			end
		end
	else
		self._selectedItems[item] = true
		self._lastClickedItem = item
	end

	self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
	self:RefreshHierarchySelectionVisuals()
end

local function canSelectRangeRow(row)
	if row._virtualized then
		local item = row
		while item do
			if not item.uiElement.Visible or item ~= row and not item.childContainer.Visible then
				return false
			end

			item = item.parentItem
		end
	end

	if row.itemKind == "events" or row.itemKind == "subtitles" or row.itemKind == "faces" then
		return false
	end

	if row.itemKind == "ikcontrol" then
		local motor = row:fetchMotor()
		if not motor or not LimbIK.controlsVisible(motor.Owner) then
			return false
		end
	end

	local cursor = row.uiElement
	while cursor do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end

		cursor = cursor.Parent
	end

	return true
end

function Rig:SelectRangeTo(item)
	local anchor = self._lastClickedItem
	if not anchor or not self:_GetItemIndex(anchor) then
		self:SetSingleItemSelection(item)
		return
	end

	local fromIdx = self:_GetItemIndex(anchor)
	local toIdx = self:_GetItemIndex(item)
	if not fromIdx or not toIdx then
		self:SetSingleItemSelection(item)
		return
	end

	if fromIdx > toIdx then
		fromIdx, toIdx = toIdx, fromIdx
	end

	local newSet = {}
	for i = fromIdx, toIdx do
		local row = self._orderedItems[i]
		if canSelectRangeRow(row) then
			newSet[row] = true
		end
	end

	self._selectedItems = newSet
	self._lastClickedItem = item
	self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
	self:RefreshHierarchySelectionVisuals()
end

function Rig:SelectAllChildren()
	if #self._orderedItems == 0 then
		return
	end

	local allSelected = true
	for _, item in ipairs(self._orderedItems) do
		if
			item.itemKind == "events"
			or item.itemKind == "subtitles"
			or item.itemKind == "faces"
		then
			continue
		end

		if not self._selectedItems[item] then
			allSelected = false
			break
		end
	end

	if allSelected then
		self._selectedItems = {}
		self._lastClickedItem = nil
	else
		local newSet = {}
		for _, item in ipairs(self._orderedItems) do
			if
				item.itemKind ~= "events"
				and item.itemKind ~= "subtitles"
				and item.itemKind ~= "faces"
			then
				newSet[item] = true
				self._lastClickedItem = item
			end
		end

		self._selectedItems = newSet
	end

	self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
	self:RefreshHierarchySelectionVisuals()
end

function Rig:SelectMaster(masterItem, additive, useRange)
	if not masterItem then
		return
	end

	local ordered = {}

	local function walk(item)
		for _, child in ipairs(item.childItems) do
			if
				child.itemKind == "events"
				or child.itemKind == "subtitles"
				or child.itemKind == "faces"
			then
				continue
			end

			table.insert(ordered, child)
			walk(child)
		end
	end

	walk(masterItem)

	if #ordered == 0 then
		if masterItem.linkedRigInstance and not masterItem.linkedRigInstance.Parent then
			self._selectedItems = { [masterItem] = true }
			self._lastClickedItem = masterItem
			self:RefreshHierarchySelectionVisuals()
		end

		return
	end

	if useRange and self._lastClickedItem and self:_GetItemIndex(self._lastClickedItem) then
		local anchorIdx = self:_GetItemIndex(self._lastClickedItem)
		local firstIdx, lastIdx = nil, nil
		for _, item in ipairs(ordered) do
			local idx = self:_GetItemIndex(item)
			if idx then
				if not firstIdx or idx < firstIdx then
					firstIdx = idx
				end

				if not lastIdx or idx > lastIdx then
					lastIdx = idx
				end
			end
		end

		if firstIdx and lastIdx then
			local fromIdx = math.min(anchorIdx, firstIdx)
			local toIdx = math.max(anchorIdx, lastIdx)
			local newSet = {}
			for i = fromIdx, toIdx do
				local row = self._orderedItems[i]
				if canSelectRangeRow(row) then
					newSet[row] = true
				end
			end

			self._selectedItems = newSet
			self._lastClickedItem = ordered[#ordered]
			self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
			self:RefreshHierarchySelectionVisuals()
			return
		end
	end

	if additive then
		local allSelected = true
		for _, item in ipairs(ordered) do
			if not self._selectedItems[item] then
				allSelected = false
				break
			end
		end

		if allSelected then
			for _, item in ipairs(ordered) do
				self._selectedItems[item] = nil
			end

			if self._lastClickedItem and not self._selectedItems[self._lastClickedItem] then
				self._lastClickedItem = nil
				for it in pairs(self._selectedItems) do
					self._lastClickedItem = it
					break
				end
			end
		else
			for _, item in ipairs(ordered) do
				self._selectedItems[item] = true
			end

			self._lastClickedItem = ordered[#ordered]
		end
	else
		local newSet = {}
		for _, item in ipairs(ordered) do
			newSet[item] = true
		end

		self._selectedItems = newSet
		self._lastClickedItem = ordered[#ordered]
	end

	self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
	self:RefreshHierarchySelectionVisuals()
end

function Rig:ClearItemSelection()
	self._selectedItems = {}
	self._explicitSelectedKeys = {}
	self._lastClickedItem = nil
	self:_SyncAxisToPrimary()
	self:SelectKeysForSelectedParts()
	self:RefreshHierarchySelectionVisuals()
end

function Rig:FindArmatureModel(rig)
	if not rig then
		return nil
	end

	for _, desc in ipairs(RigTraversal.rigDescendants(rig)) do
		if desc:IsA("Model") and desc:GetAttribute("EclipseArmature") then
			return desc
		end
	end

	return nil
end

function Rig:GetRobloxBoneTree(rig)
	local roots = {}
	local childrenMap = {}
	for _, b in ipairs(RigTraversal.rigDescendants(rig)) do
		if
			b:IsA("Bone")
			and not b:GetAttribute("EclipseArmatureSkinningHelper")
			and not R6Controls.isControl(b)
		then
			local parentBone = b.Parent
			if parentBone and parentBone:IsA("Bone") then
				childrenMap[parentBone] = childrenMap[parentBone] or {}
				table.insert(childrenMap[parentBone], b)
			else
				table.insert(roots, b)
			end
		end
	end

	local function sortByName(list)
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
	end

	sortByName(roots)
	for _, list in pairs(childrenMap) do
		sortByName(list)
	end

	return roots, childrenMap
end

function Rig:BuildRigHierarchy(rig)
	if self._hierarchyBuildToken then
		self._hierarchyBuildPending = { rig = rig }
		return false
	end

	local request = { rig = rig }
	local passes = 0
	repeat
		self._hierarchyBuildPending = nil
		local token = {}
		self._hierarchyBuildToken = token
		local ok, message = xpcall(function()
			WorkBudget.run(self._BuildRigHierarchy, self, request.rig, token)
			if token.cancelled then
				error(token, 0)
			end
		end, function(problem)
			return problem == token and problem or debug.traceback(tostring(problem), 2)
		end)
		self._hierarchyBuildToken = nil
		self._rebuilding = false
		if not ok then
			self._hierarchyBuildPending = nil
			self:DestroyHierarchyItems()
			self.refs.Timeline:ClearTracks()
			if message ~= token then
				error(message, 0)
			end

			return false
		end

		request = self._hierarchyBuildPending
		if request then
			passes += 1
			if passes >= 8 then
				self._hierarchyBuildPending = nil
				const later = request.rig
				task.defer(function()
					self:BuildRigHierarchy(later)
				end)
				return true
			end

			if coroutine.isyieldable() then
				const waiting = {}
				self._hierarchyBuildToken = waiting
				task.wait()
				if self._hierarchyBuildToken == waiting then
					self._hierarchyBuildToken = nil
				end

				if waiting.cancelled then
					return false
				end

				request = self._hierarchyBuildPending or request
			end
		end
	until not request
	return true
end

function Rig:_BuildRigHierarchy(rig, buildToken)
	local mainState = require("State")

	local function checkpoint()
		if buildToken.cancelled then
			error(buildToken, 0)
		end

		if mainState.ProjectWorkStep then
			mainState.ProjectWorkStep()
			if buildToken.cancelled then
				error(buildToken, 0)
			end
		end
	end

	self._primaryRigInstance = rig

	local previous = {}
	local previousChannels = {}
	local selectedKeys = {}
	for item, selected in self._selectedItems do
		if selected and TrackHierarchy.key(item) then
			selectedKeys[TrackHierarchy.key(item)] = true
		end
	end

	for _, item in self._orderedItems do
		previous[item.linkedRigInstance] =
			{ open = item.openedState, motion = item.motionPathEnabled }
		if item.transformChannelsOpen and item.fetchMotor then
			local motor = item:fetchMotor()
			if motor then
				previousChannels[motor] = true
			end
		end
	end

	for _, master in self._masterItems do
		previous[master.linkedRigInstance] = { open = master.openedState }
	end

	self._rebuilding = true
	if self.refs.Timeline.DetachKeyframeButtons then
		self.refs.Timeline:DetachKeyframeButtons()
	end

	self:DestroyHierarchyItems(buildToken)
	self.refs.Timeline:ClearTracks()

	local rigListScroll = self.refs.RigListScroll
	local rigTemplate = self.refs.RigItemTemplate

	local function initializeItem(...)
		local args = table.pack(...)
		local ok, item = pcall(baseItem.initialize, ...)
		if not ok then
			if args[1] then
				args[1]:Destroy()
			end

			if args[4] then
				args[4]:Destroy()
			end

			error(item, 0)
		end

		table.insert(self._hierarchyOwnedItems, item)
		return item
	end

	local mastersByRig = {}
	local createdItems = {}
	local trackIndexRef = 0
	local maxDepth = 0

	local function buildMasterForRig(targetRig)
		if mastersByRig[targetRig] then
			return mastersByRig[targetRig]
		end

		if targetRig.Parent then
			require("Membership").remember(self.refs.Timeline:GetState(), targetRig)
		end

		local outgoing, incoming = self:GetMotorGraph(targetRig)
		local childrenMap = self:GetMotorChildrenMap(targetRig)
		local roots = self:GetRigRoots(targetRig, outgoing, incoming)

		local rigClone = rigTemplate:Clone()
		local trackMasterClone = self.refs.Timeline:GetTrackContainer():Clone()
		local sanitizedRigName = self.refs.UIHelpers.SanitizeName(targetRig.Name)
		local masterItem = initializeItem(
			rigClone,
			CameraRig.timelineName(targetRig),
			nil,
			trackMasterClone,
			true,
			targetRig
		)
		mastersByRig[targetRig] = masterItem
		rigClone.Name = sanitizedRigName .. "_Rig"
		rigClone.Parent = rigListScroll

		masterItem.trackElement.Parent = self.refs.KeysRoot
		if not targetRig.Parent then
			local folder = self:GetBonesFolder(targetRig)
			if folder then
				folder:Destroy()
			end

			self._ownedBoneFolders[targetRig] = nil
			self._boneFollowCaches[targetRig] = nil
			masterItem.centerDiv.Title.Text = string.upper(targetRig.Name) .. " (MISSING)"
			table.insert(self._masterItems, masterItem)
			return masterItem
		end

		local partItems = {}
		local visitedParts = {}

		local function scanPartsInTable(searchTable, skip, parent, depth, unboundOnly)
			for _, childPart in ipairs(searchTable) do
				if visitedParts[childPart] then
					continue
				end

				visitedParts[childPart] = true
				checkpoint()
				local newChildItem = parent
				partItems[childPart] = { parent, depth }
				if
					not skip
					and (
						not unboundOnly
						or not ArmatureRuntime.isDriven(self:GetMotorForPart(targetRig, childPart))
					)
				then
					trackIndexRef += 1
					if depth > maxDepth then
						maxDepth = depth
					end

					local rowElement = self.refs.Timeline:CreateTrackRow(
						childPart,
						trackIndexRef * 100,
						self.refs.UIHelpers.SanitizeName
					)
					newChildItem = initializeItem(
						rigTemplate:Clone(),
						childPart.Name,
						nil,
						rowElement,
						false,
						childPart
					)
					parent:addChild(newChildItem)
					table.insert(createdItems, newChildItem)
					partItems[childPart] = { newChildItem, depth }

					local motor = self:GetMotorForPart(targetRig, childPart)
					if motor and previousChannels[motor] then
						newChildItem:toggleTransformChannels(true)
					end

					if motor then
						local chain = LimbIK.chain(targetRig, motor)
						if
							chain
							and chain.kind == "R6"
							and chain.limb == "Leg"
							and LimbIK.hasAnimation(motor)
							and not R6Controls.find(motor, "pole")
						then
							LimbIK.prepare(chain)
							self.refs.Timeline:CaptureDefaultPoseAdditive(targetRig)
						end

						for _, control in R6Controls.forOwner(motor) do
							trackIndexRef += 1
							maxDepth = math.max(maxDepth, depth + 1)
							local row = self.refs.Timeline:CreateTrackRow(
								control.Part1,
								trackIndexRef * 100,
								self.refs.UIHelpers.SanitizeName
							)
							local controlItem = initializeItem(
								rigTemplate:Clone(),
								R6Controls.label(control.Part1),
								nil,
								row,
								false,
								control.Part1,
								"ikcontrol"
							)
							newChildItem:addChild(controlItem)
							table.insert(createdItems, controlItem)
							if previousChannels[control] then
								controlItem:toggleTransformChannels(true)
							end
						end
					end
				end

				if childrenMap[childPart] then
					scanPartsInTable(
						childrenMap[childPart],
						false,
						newChildItem,
						newChildItem == parent and depth or depth + 1,
						unboundOnly
					)
				end
			end
		end

		local function addLeafItem(instance, parent, depth, kind, displayName)
			checkpoint()
			trackIndexRef += 1
			if depth > maxDepth then
				maxDepth = depth
			end

			local rowElement = self.refs.Timeline:CreateTrackRow(
				instance,
				trackIndexRef * 100,
				self.refs.UIHelpers.SanitizeName
			)
			local newItem = initializeItem(
				rigTemplate:Clone(),
				displayName or instance.Name,
				nil,
				rowElement,
				false,
				instance,
				kind
			)
			parent:addChild(newItem)
			table.insert(createdItems, newItem)
			return newItem
		end

		local function scanBonesInTable(boneList, boneChildren, parent, depth)
			for _, boneInst in ipairs(boneList) do
				local boneItem = addLeafItem(boneInst, parent, depth, "displaybone")
				local boneMotor = self:GetMotorForPart(targetRig, boneInst)
				if boneMotor and previousChannels[boneMotor] then
					boneItem:toggleTransformChannels(true)
				end

				if boneMotor then
					for _, control in R6Controls.forOwner(boneMotor) do
						local controlItem = addLeafItem(
							control.Part1,
							boneItem,
							depth + 1,
							"ikcontrol",
							R6Controls.label(control.Part1)
						)
						if previousChannels[control] then
							controlItem:toggleTransformChannels(true)
						end
					end
				end

				local kids = boneChildren[boneInst]
				if kids then
					scanBonesInTable(kids, boneChildren, boneItem, depth + 1)
				end
			end
		end

		if CameraRig.isRig(targetRig) then
			local obsolete = Properties.folder(targetRig, false)
			if obsolete and #obsolete:GetChildren() == 0 then
				obsolete:Destroy()
			end
		end

		if
			targetRig:GetAttribute("EffectKind") == "Letterbox"
			and targetRig:GetAttribute("EclipseEffectObject") == 1
		then
			for _, id in { "FollowFOV", "AlwaysOnTop" } do
				local found = false
				for _, motor in Properties.list(targetRig, true) do
					if motor.PropertyId == id then
						found = true
					end
				end

				if not found then
					Properties.enable(targetRig, id, true, self.refs.Timeline:GetState())
				end
			end
		end

		local propertyFolder
		if not CameraRig.isRig(targetRig) and #Properties.list(targetRig) > 0 then
			local storage = Properties.folder(targetRig, true)
			for _, motor in Properties.list(targetRig) do
				if not motor.Definition.hidden and not motor.Definition.facial then
					propertyFolder = addLeafItem(storage, masterItem, 1, "properties", "Properties")
					propertyFolder.centerDiv.Title.Text = "PROPERTIES"
					propertyFolder.openedState = true
					break
				end
			end
			local faceFolder
			for _, motor in Properties.list(targetRig) do
				if motor.Definition.hidden then
					continue
				end

				local raw = self.refs.Timeline:GetState()
				raw.DefaultPose[motor] = Properties.encode(motor.DefaultValue)
				raw.MotorByPart[motor.Part1] = motor
				raw.ParentingDefaults[motor] = true
				local parent = propertyFolder
				if motor.Definition.facial then
					if not faceFolder then
						faceFolder = addLeafItem(Properties.faceControls(targetRig), masterItem, 1, "properties", "Dynamic Head")
						faceFolder.centerDiv.Title.Text = "DYNAMIC HEAD"
						faceFolder.openedState = false
						faceFolder.childContainer.Visible = false
						local right = faceFolder.appearDetails.RightDiv
						local icons = require("LibraryIcons")
						local controls = require("ParentingUI").modeButton(right, "FaceControls")
						controls.Text, controls.LayoutOrder = "", 10
						icons.dynamic(controls, "sliders")
						local eye = require("ParentingUI").modeButton(right, "FaceVisibility")
						eye.Text, eye.LayoutOrder = "", 20
						local eyeIcon = icons.dynamic(eye, "eye", 16)
						for _, button in { controls, eye } do
                            local aspect = button:FindFirstChildOfClass("UIAspectRatioConstraint")
                            if aspect then aspect:Destroy() end
                            button.Size = UDim2.new(0, 17, 1, 0)
                        end
                        local enabled = right:FindFirstChild("Disable")
						enabled.Visible, enabled.LayoutOrder = true, 30
						local titleIcon = faceFolder.centerDiv:FindFirstChild("ImgContainer")
						titleIcon = titleIcon and titleIcon:FindFirstChildWhichIsA("ImageButton")
						if titleIcon then titleIcon.Image = "" icons.dynamic(titleIcon, "controls") end
						local function paint()
							local handles = require("FaceHandles")
							enabled:SetAttribute("ThemeImg", handles.enabled(targetRig) and "TrackOn" or "TrackOff")
							eyeIcon.Visible = true
							eyeIcon:SetAttribute("ThemeImgTransparency", handles.visible(targetRig) and 0 or 0.65)
							require("Theme").applyTree(right)
						end
						controls:SetAttribute("Tooltip", "Open dynamic head sliders")
						eye:SetAttribute("Tooltip", "Show or hide dynamic head handles")
						table.insert(faceFolder.connections, controls.Activated:Connect(function() require("PropertySettings").openFaceControls(targetRig) end))
						table.insert(faceFolder.connections, eye.Activated:Connect(function() local handles = require("FaceHandles") handles.setVisible(targetRig, not handles.visible(targetRig)) paint() end))
						table.insert(faceFolder.connections, enabled.Activated:Connect(function() local handles = require("FaceHandles") handles.setEnabled(targetRig, not handles.enabled(targetRig)) paint() end))
						local unsubscribe = require("History").subscribe(paint)
						table.insert(faceFolder.connections, { Disconnect = unsubscribe })
						paint()
					end
					parent = faceFolder
				end
				local label = motor.Definition.label or motor.PropertyId
				local property = addLeafItem(motor.Part1, parent, 2, "property", label)
				property.linkedMotor = motor
				property.centerDiv.Title.Text = string.upper(label)
				property.disabled = motor:GetAttribute("EclipseDisabled") == true
				property:_repaintDisable()
			end
		end

		local masterControl = MasterControl.get(targetRig)
		if masterControl then
			local controlItem =
				addLeafItem(masterControl.Part1, masterItem, 1, "mastercontrol", "Master Control")
			if previousChannels[masterControl] then
				controlItem:toggleTransformChannels(true)
			end
		end

		local armatureModel = self:FindArmatureModel(targetRig)
		if CameraRig.isRig(targetRig) then
			require("Target").ensure(targetRig)
			if targetRig:GetAttribute("EclipseHideCamTarget") ~= true then
				addLeafItem(targetRig.CamTarget, masterItem, 1, "camtarget", "CamTarget")
			end

			local attachment = require("Target").ensureAttachment(targetRig)
			local attach =
				addLeafItem(attachment.Part1, masterItem, 1, "cameraattach", "AttachToPart")
			attach.centerDiv.Title.Text = "ATTACHTOPART"
			addLeafItem(targetRig.FovPart, masterItem, 1, "camerafov", "FOV")
			local transform =
				addLeafItem(targetRig.CamPart, masterItem, 1, "cameracframe", "CFrame")
			transform.centerDiv.Title.Text = "CFRAME"
		elseif armatureModel then
			local armItem = addLeafItem(armatureModel, masterItem, 1, "armature")
			local anchors = {}
			local byName = {}
			for _, child in ipairs(armatureModel:GetChildren()) do
				if child:GetAttribute("EclipseArmatureBone") then
					table.insert(anchors, child)
					byName[child:GetAttribute("EclipseArmatureBoneId") or child.Name] = child
				end
			end

			table.sort(anchors, function(a, b)
				return a.Name < b.Name
			end)
			local childrenOf = {}
			local armRoots = {}
			for _, anchor in ipairs(anchors) do
				local parentName = anchor:GetAttribute("EclipseArmatureParentId")
					or anchor:GetAttribute("ParentBone")
				local parentAnchor = parentName and byName[parentName]
				if parentAnchor and parentAnchor ~= anchor then
					childrenOf[parentAnchor] = childrenOf[parentAnchor] or {}
					table.insert(childrenOf[parentAnchor], anchor)
				else
					table.insert(armRoots, anchor)
				end
			end

			local nameToBone = {}
			for _, desc in ipairs(RigTraversal.rigDescendants(targetRig)) do
				if desc:IsA("Bone") and not desc:GetAttribute("EclipseArmatureSkinningHelper") then
					nameToBone[desc.Name] = desc
				end
			end

			local function scanArmatureBones(list, parentItem, depth)
				for _, anchor in ipairs(list) do
					if anchor:GetAttribute("EclipseArmatureControl") == false then
						if childrenOf[anchor] then
							scanArmatureBones(childrenOf[anchor], parentItem, depth)
						end

						continue
					end

					local realBone = not ArmatureRuntime.isAnchor(anchor)
							and nameToBone[anchor.Name]
						or nil
					local anchorItem =
						addLeafItem(realBone or anchor, parentItem, depth, "displaybone")
					if realBone then
						local boneMotor = self:GetMotorForPart(targetRig, realBone)
						if boneMotor and previousChannels[boneMotor] then
							anchorItem:toggleTransformChannels(true)
						end
					end

					if childrenOf[anchor] then
						scanArmatureBones(childrenOf[anchor], anchorItem, depth + 1)
					end
				end
			end

			scanArmatureBones(armRoots, armItem, 2)

			scanPartsInTable(roots, true, masterItem, 1, true)
		else
			local countBefore = #masterItem.childItems
			scanPartsInTable(roots, true, masterItem, 1)
			local boneRoots, boneChildren = self:GetRobloxBoneTree(targetRig)
			if #masterItem.childItems == countBefore then
				scanBonesInTable(boneRoots, boneChildren, masterItem, 1)
			else
				for _, boneInst in ipairs(boneRoots) do
					local host = boneInst.Parent
					while host and host ~= targetRig and not partItems[host] do
						host = host.Parent
					end

					local entry = host and partItems[host]
					scanBonesInTable(
						{ boneInst },
						boneChildren,
						entry and entry[1] or masterItem,
						entry and entry[2] + 1 or 1
					)
				end
			end
		end

		do
			local eventsRow = self.refs.Timeline:GetTrackTemplate():Clone()
			eventsRow.Name = "Events_Track"
			eventsRow.LayoutOrder = -100
			local eventsItem = initializeItem(
				rigTemplate:Clone(),
				"EVENTS",
				nil,
				eventsRow,
				false,
				targetRig,
				"events"
			)
			eventsItem.uiElement.LayoutOrder = -100
			masterItem:addChild(eventsItem)
			table.insert(createdItems, eventsItem)
		end

		if require("Faces").supports(targetRig) then
			local faceRow = self.refs.Timeline:GetTrackTemplate():Clone()
			faceRow.Name = "Faces_Track"
			faceRow.LayoutOrder = -99
			local faceItem = initializeItem(
				rigTemplate:Clone(),
				"FACES",
				nil,
				faceRow,
				false,
				targetRig,
				"faces"
			)
			faceItem.uiElement.LayoutOrder = -99
			masterItem:addChild(faceItem)
			table.insert(createdItems, faceItem)
		end

		maxDepth = math.max(maxDepth, 1)
		table.insert(self._masterItems, masterItem)
		masterItem:changeStateChildren(true, true, true)
		return masterItem
	end

	self.currentRig = rig and buildMasterForRig(rig) or nil

	for _, extraRig in ipairs(self:GetExtraRigs()) do
		if extraRig ~= rig then
			buildMasterForRig(extraRig)
		end
	end

	self._orderedItems = createdItems
	for _, item in createdItems do
		local saved = previous[item.linkedRigInstance]
		if saved then
			item:setOpenState(saved.open, true)
			if saved.motion then
				item:setMotionPath(true, false)
			end
		end
	end

	self._r6ControlRevisions = {}
	self._rigPresence = {}
	for _, master in self._masterItems do
		self._rigPresence[master.linkedRigInstance] = master.linkedRigInstance.Parent ~= nil
		self._r6ControlRevisions[master.linkedRigInstance] =
			R6Controls.revision(master.linkedRigInstance)
		local saved = previous[master.linkedRigInstance]
		master:setOpenState(not saved or saved.open)
	end

	require("Origin").createItem(self, baseItem)
	require("Subtitles").buildRows(self, baseItem)
	self.refs.Timeline:RegisterSummaryTracks(self._masterItems)
	maxDepth = math.max(maxDepth, TrackHierarchy.build(self, baseItem, previous))
	self.refs.Timeline:RebindTrackRows(self._organizationItems)
	createdItems = self._organizationItems
	for _, item in createdItems do
		if selectedKeys[TrackHierarchy.key(item)] then
			self._selectedItems[item] = true
			self._lastClickedItem = item
		end
	end

	self._rebuilding = false

	local staleBone = self.refs.Axis and self.refs.Axis:GetSelectedBone()
	if staleBone and not staleBone.Parent then
		self:_SyncAxisToPrimary()
	end

	self.onlyShowSelected = self.refs.Timeline:GetState().OnlyShowSelected
	self:UpdateRigListCanvasWidth(maxDepth)

	self._refreshHierarchyVisuals = function()
		if self.onlyShowSelected then
			self:RefreshSelectionFilter()
		end

		for _, listItem in ipairs(createdItems) do
			if listItem and listItem.uiElement and listItem.uiElement.Parent then
				local isSelected = self._selectedItems[listItem] == true
					or (
						self._explicitSelectedKeys
						and self._explicitSelectedKeys[TrackHierarchy.key(listItem)] == true
					)
				listItem:setSelected(isSelected)

				if listItem.transformChannelItems then
					for _, channelItem in ipairs(listItem.transformChannelItems) do
						local chSelected = self._selectedChannels[channelItem] == true
						channelItem:setSelected(chSelected)
					end
				end
			end
		end
	end

	self.refs.Timeline:RebuildAllTimelineKeyframeButtons(nil, self.refs.UIHelpers.SanitizeName)
	self._refreshHierarchyVisuals()
	if rig then
		self:StartSelectionSync(rig)
	end

	self.refs.Timeline.refs.RefreshIKHierarchy = function()
		self:RefreshIKChildren(rig)
	end

	self:RefreshIKChildren(rig)
	self:BindDisplayPreferences()
	self:RefreshSelectionFilter()
end

function Rig:RefreshIKChildren(rig)
	if self._rebuilding or self._batchHold then
		return
	end

	local scroll = self.refs.RigListScroll
	if not scroll or not scroll.Parent then
		return
	end

	local rigs = { rig }
	for _, extra in self:GetExtraRigs() do
		if extra ~= rig then
			table.insert(rigs, extra)
		end
	end

	for _, target in rigs do
		local present = target.Parent ~= nil
		if
			(self._rigPresence and self._rigPresence[target] ~= present)
			or (present and self._r6ControlRevisions[target] ~= R6Controls.revision(target))
		then
			self:CreateBonesForRig(target)
			self:BuildRigHierarchy(rig)
			return
		end
	end

	local visibilityChanged = false

	if self._ikRowSource ~= self._orderedItems then
		self._ikRowSource = self._orderedItems
		self._ikRows = {}
		for _, item in self._orderedItems do
			if item.itemKind == "ikcontrol" then
				table.insert(self._ikRows, item)
			end
		end
	end

	for _, item in self._ikRows do
		if not item.uiElement or not item.uiElement.Parent then
			continue
		end

		if item.itemKind == "ikcontrol" then
			local motor = item:fetchMotor()
			local enabled = LimbIK.controlsVisible(motor.Owner) and R6Controls.visible(motor)
			if item._ikVisible ~= enabled then
				visibilityChanged = true
				item._ikVisible = enabled
				local open = enabled
				local parent = item.parentItem
				while parent do
					open = open and parent.openedState
					parent = parent.parentItem
				end

				item:setOpenParentalState(open)
				if item.parentItem then
					item.parentItem:refreshMoreButtonVisibility()
				end
			end
		end
	end

	if visibilityChanged then
		self:RefreshSelectionFilter()
	end
end

function Rig:UpdateRigListCanvasWidth(maxDepth)
	local rigListScroll = self.refs.RigListScroll
	if not rigListScroll or not rigListScroll:IsA("ScrollingFrame") then
		return
	end

	local indent = 14
	local template = self.refs.RigItemTemplate
	local childContainer = template and template:FindFirstChild("ChildrenContainer")
	local pad = childContainer and childContainer:FindFirstChildOfClass("UIPadding")
	if pad then
		indent = math.max(pad.PaddingLeft.Offset, 8)
	end

	local needed = 170 + (maxDepth + 1) * indent
	local visibleWidth = rigListScroll.AbsoluteSize.X
	if visibleWidth > 0 and needed > visibleWidth then
		rigListScroll.CanvasSize = UDim2.fromOffset(needed, 0)
	else
		rigListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	end
end

function Rig:GetOrderedAnimPartsExcludingRoots(rig)
	local outgoing, incoming = self:GetMotorGraph(rig)
	local childrenMap = self:GetMotorChildrenMap(rig)
	local roots = self:GetRigRoots(rig, outgoing, incoming)

	local ordered = {}

	local function walk(part)
		table.insert(ordered, part)

		local children = childrenMap[part] or {}
		for _, child in ipairs(children) do
			walk(child)
		end
	end

	for _, rootPart in ipairs(roots) do
		for _, child in ipairs(childrenMap[rootPart] or {}) do
			walk(child)
		end
	end

	return ordered, childrenMap, roots
end

return Rig
