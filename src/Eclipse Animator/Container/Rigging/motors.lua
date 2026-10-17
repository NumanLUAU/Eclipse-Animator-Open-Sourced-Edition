--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Properties = require("Properties")
local Document = require("Document")
local Paths = require("Paths")
local Parenting = require("Parenting")
local Master = require("MasterControl")
local Organization = require("Organization")
local Animation = require("ArmatureAnimation")
local Runtime = require("ArmatureRuntime")
local Policy = require("Policy")
local Curves = require("GraphCurves")
local BoneMotor = require("BoneMotor")
local Origin = require("Origin")
local Preferences = require("Preferences")
local Controls = require("R6Controls")
local Scene = {}

local function objectPath(object, state)
	local path = Paths.of(object, state.LiveProject and state.LiveProject.Scope or workspace)
	if path then
		return { path = path }
	end

	if object:IsDescendantOf(game) and not object:IsDescendantOf(game:GetService("CoreGui")) then
		return { gamePath = Paths.of(object, game) }
	end

	return nil
end

local function resolveObject(value, state)
	return value.gamePath and Paths.resolve(game, value.gamePath)
		or value.path
			and Paths.resolve(
				state.LiveProject and state.LiveProject.Scope or workspace,
				value.path
			)
end

local function scope(state)
	return state.LiveProject and state.LiveProject.Scope or workspace
end

local function rigId(rig, state)
	return rig:GetAttribute("EclipseTrackId")
		or assert(
			Paths.of(rig, scope(state)) or Paths.of(rig, game),
			"The Live object must be in the shared place"
		)
end

local function belongs(motor, rig)
	if Properties.is(motor) then
		return motor.Rig == rig
	end

	local parent = motor.Parent
	return parent and (parent == rig or typeof(parent) == "Instance" and parent:IsDescendantOf(rig))
		or typeof(motor.Part1) == "Instance" and motor.Part1:IsDescendantOf(rig)
end

local function collect(rig, raw, archivePaths)
	local result = {}
	local membership = archivePaths and require("Membership")
	local owned = membership and membership.ownedKeys(raw, rig)
	for _, motor in Parenting.collectMotors(rig) do
		result[motor] = true
	end

	for _, motor in Properties.list(rig, true) do
		result[motor] = true
	end

	for _, part in require("RigTraversal").descendants(rig) do
		if part:IsA("BasePart") and part:GetAttribute("EclipseArmatureBone") then
			local motor = BoneMotor.getIKHandle(part, rig)
			if motor then
				result[motor] = true
			end
		end
	end

	local master = Master.get(rig, true)
	if master then
		result[master] = true
	end

	for motor in raw.DefaultPose do
		if
			motor.Parent
			and (
				membership and membership.belongs(motor, rig, owned)
				or not membership and belongs(motor, rig)
			)
		then
			result[motor] = true
		end
	end

	return result
end

local function motors(rig, raw, archivePaths)
	local seen = {}
	for motor in collect(rig, raw, archivePaths) do
		local id = Paths.motor(motor, rig, not archivePaths)
		assert(id, "Waiting for shared track " .. motor.Name .. " in " .. rig.Name)
		assert(
			not seen[id],
			"Live found two tracks with the same identity in " .. rig.Name .. ": " .. id
		)
		seen[id] = motor
	end

	return seen
end

Scene.motors = motors
Scene.collect = collect

function Scene.index(state)
	local rigs, tracks = {}, {}
	local raw = state.Timeline:GetState()
	for _, rig in state.getAllRigs() do
		local id = rigId(rig, state)
		assert(not rigs[id], "Duplicate Live rig identity")
		rigs[id] = rig
		for name, motor in motors(rig, raw) do
			if raw.DefaultPose[motor] ~= nil then
				tracks[id .. "/" .. name] = motor
			end
		end
	end

	local _, originMotor = Origin.ensure(state.Timeline)
	tracks["$origin"] = originMotor
	return tracks, rigs
end

local function reference(value, state)
	if Origin.is(value) then
		return { origin = true }
	end

	if typeof(value) == "Instance" then
		local owner = Properties.owner(value)
		if owner then
			return {
				propertyOwner = assert(
					objectPath(owner, state),
					"Waiting for shared property owner"
				),
				property = value:GetAttribute("EclipseProperty") or false,
			}
		end
	end

	if typeof(value) == "Instance" then
		if not value.Parent then
			return nil
		end

		return assert(
			objectPath(value, state),
			"Live cannot reference " .. value.Name .. ". Reopen this file to rebuild its controls."
		)
	end

	assert(
		type(value) == "string" or value == false or value == nil,
		"Invalid Live folder reference"
	)
	return { value = value }
end

local function unreference(value, state)
	if not value then
		return nil
	end

	if value.origin then
		return Origin.ensure(state.Timeline)
	end

	if value.propertyRig or value.propertyOwner then
		local owner = assert(
			value.propertyOwner and resolveObject(value.propertyOwner, state)
				or Paths.resolve(scope(state), value.propertyRig),
			"Waiting for shared property owner"
		)
		return value.property and Properties.enable(owner, value.property, true).Part1
			or Properties.folder(owner, true)
	end

	if value.path or value.gamePath then
		return assert(resolveObject(value, state), "Waiting for shared track organization")
	end

	return value.value
end

local function organization(state)
	local old = Organization.snapshot()
	local out = {
		folders = old.folders,
		nextNumber = old.nextNumber,
		placements = {},
		enabled = {},
		removed = {},
	}
	for key, value in old.placements do
		local row = table.clone(value)
		row.parent = reference(value.parent, state)
		local keyRef = reference(key, state)
		if keyRef then
			table.insert(out.placements, { key = keyRef, value = row })
		end
	end

	for key, value in old.enabled do
		local keyRef = reference(key, state)
		if keyRef then
			table.insert(out.enabled, { key = keyRef, value = value })
		end
	end

	for key, value in old.removed or {} do
		local keyRef = reference(key, state)
		if keyRef then
			table.insert(out.removed, { key = keyRef, value = value })
		end
	end

	local function order(a, b)
		return Document.pack(a.key) < Document.pack(b.key)
	end

	table.sort(out.placements, order)
	table.sort(out.enabled, order)
	table.sort(out.removed, order)
	for id, folder in out.folders do
		local copy = table.clone(folder)
		copy.parent = reference(folder.parent, state)
		out.folders[id] = copy
	end

	return out
end

local function resolveOrganization(value, state)
	local out =
		{ folders = {}, placements = {}, enabled = {}, removed = {}, nextNumber = value.nextNumber }
	for id, folder in value.folders do
		local row = table.clone(folder)
		row.parent = unreference(folder.parent, state)
		out.folders[id] = row
	end

	for _, entry in value.placements do
		local row = table.clone(entry.value)
		row.parent = unreference(row.parent, state)
		out.placements[unreference(entry.key, state)] = row
	end

	for _, entry in value.enabled do
		out.enabled[unreference(entry.key, state)] = entry.value
	end

	for _, entry in value.removed or {} do
		out.removed[unreference(entry.key, state)] = entry.value == true
	end

	return out
end

function Scene.capture(state)
	local raw = state.Timeline:GetState()
	local Layers = require("Layers")
	if Layers.has(raw) then
		Layers.ensure(raw)
		Layers.syncProperties(raw)
	end

	local result = {
		version = 2,
		channels = Policy.channelsEnabled(),
		rigs = {},
		organization = organization(state),
		origin = Origin.shared(state.Timeline),
	}
	for _, rig in state.getAllRigs() do
		local planted = rig:GetAttribute("EclipseIKFeetPlanted")
		if planted == nil then
			planted = Preferences.get("IKFeetPlanted")
		end

		local entry = {
			individualParts = rig:GetAttribute("EclipseIndividualParts"),
			feetPlanted = planted,
			id = rigId(rig, state),
			path = Paths.of(rig, scope(state)),
			object = objectPath(rig, state),
			tracks = {},
			r6Bend = rig:GetAttribute("EclipseR6BendPercent") or Preferences.get("R6BendPercent"),
			master = {
				enabled = Master.enabled(rig),
				rest = rig:GetAttribute("EclipseMasterRest"),
				radius = rig:GetAttribute("EclipseMasterRadius"),
			},
			properties = Layers.has(raw) and (raw.AnimationLayers.layers[1].properties[rig] or {
				version = 1,
				tracks = {},
			}) or Animation.propertySnapshot(rig),
			inputs = {},
			itemProperties = Properties.snapshot(rig, raw, false),
		}
		if require("CameraRig").isRig(rig) then
			entry.cameraTarget = {
				enabled = rig:GetAttribute("EclipseTrackTarget"),
				defaultEnabled = rig:GetAttribute("EclipseCamTargetDefaultEnabled"),
			}
			entry.cameraOrthographic = rig:GetAttribute("EclipseOrthographic") == true
		end

		entry.r6Controls = {}
		for _, bone in require("RigTraversal").descendants(rig) do
			if Controls.isControl(bone) then
				local control = Controls.get(bone)
				if control and control.Owner then
					table.insert(entry.r6Controls, {
						owner = assert(
							Paths.motor(control.Owner, rig),
							"Waiting for shared IK owner"
						),
						kind = bone:GetAttribute("EclipseR6Control"),
						customIK = control.Owner:GetAttribute("EclipseAutoIK") == true or nil,
						customRest = require("customRest").rest(control.Owner),
						controlSpace = bone:GetAttribute("EclipseIKControlSpace"),
						anchorOffset = bone:GetAttribute("EclipseIKAnchorOffset"),
						rest = bone.CFrame,
					})
				end
			end
		end

		table.sort(entry.r6Controls, function(a, b)
			return a.owner .. a.kind < b.owner .. b.kind
		end)
		local animated = {}
		for _, track in entry.properties.tracks do
			animated[Document.pack({ track.object, track.bone or "", track.key })] = true
		end

		if Layers.has(raw) then
			for _, layer in raw.AnimationLayers.layers do
				for _, track in layer.properties[rig] and layer.properties[rig].tracks or {} do
					animated[Document.pack({ track.object, track.bone or "", track.key })] = true
				end
			end
		end

		for _, property in Runtime.properties(rig) do
			if
				not animated[Document.pack({ property.object, property.bone or "", property.key })]
			then
				table.insert(entry.inputs, property)
			end
		end

		for id, motor in motors(rig, raw) do
			if raw.DefaultPose[motor] == nil then
				continue
			end

			entry.tracks[id] = {
				partEnabled = motor:GetAttribute("EclipsePartTrackEnabled"),
				default = raw.DefaultPose[motor],
				world = raw.DefaultWorldPose[motor],
				parented = raw.ParentingDefaults[motor] ~= false,
				size = raw.DefaultSize[motor.Part1],
				c1 = motor.C1,
				disabled = motor:GetAttribute("EclipseDisabled") == true,
				active = state.activeObjectMotors and state.activeObjectMotors[motor] == true,
				channels = {},
			}
			for _, channel in Curves.ids do
				if motor:GetAttribute("EclipseChannelDisabled_" .. channel) then
					entry.tracks[id].channels[channel] = true
				end
			end
		end

		table.insert(result.rigs, entry)
	end

	return result
end

function Scene.writeProject(values, project)
	local header = table.clone(project)
	header.rigs = nil
	values.project = Document.pack(header)
	for order, entry in project.rigs do
		local setup = table.clone(entry)
		setup.tracks = nil
		setup.itemProperties = nil
		values["rig|" .. entry.id] = Document.pack(setup)
		local properties = table.clone(entry.itemProperties or { version = 1, tracks = {} })
		properties.tracks = nil
		values["propertySetup|" .. entry.id] = Document.pack(properties)
		for _, row in (entry.itemProperties and entry.itemProperties.tracks or {}) do
			local key = Document.pack({ entry.id, row.id })
			values["property|" .. key] = Document.pack(row)
			values["propertyMember|" .. key] = "true"
		end

		for id, track in entry.tracks do
			local key = Document.pack({ entry.id, id })
			values["track|" .. key] = Document.pack(track)
			values["trackMember|" .. key] = "true"
		end

		values["member|" .. entry.id] = "true"
		values["order|" .. entry.id] = Document.pack(order)
	end
end

function Scene.readProject(values)
	local project = Document.unpack(assert(values.project, "Missing Live project"))
	local rows, rigs = {}, {}
	for key, value in values do
		if key:sub(1, 7) == "member|" then
			local id = key:sub(8)
			local encoded = values["rig|" .. id]
			assert(encoded, "Waiting for shared rig setup")
			local entry = Document.unpack(encoded)
			local order =
				Document.unpack(assert(values["order|" .. id], "Waiting for shared rig order"))
			assert(
				entry.id == id and type(order) == "number" and order >= 1 and order % 1 == 0,
				"Invalid shared rig membership"
			)
			entry.tracks = {}
			rigs[id] = entry
			entry.itemProperties = Document.unpack(
				assert(values["propertySetup|" .. id], "Waiting for shared property setup")
			)
			entry.itemProperties.tracks = {}
			table.insert(rows, { entry = entry, order = order })
		end
	end

	for key in values do
		if key:sub(1, 12) == "trackMember|" then
			local identity = key:sub(13)
			local ids = Document.unpack(identity)
			assert(
				type(ids) == "table" and type(ids[1]) == "string" and type(ids[2]) == "string",
				"Invalid shared track membership"
			)
			local rig = rigs[ids[1]]
			if rig then
				rig.tracks[ids[2]] = Document.unpack(
					assert(values["track|" .. identity], "Waiting for shared track setup")
				)
			end
		end
	end

	for key in values do
		if key:sub(1, 15) == "propertyMember|" then
			local identity = key:sub(16)
			local ids = Document.unpack(identity)
			assert(
				type(ids) == "table" and type(ids[1]) == "string" and type(ids[2]) == "string",
				"Invalid shared property membership"
			)
			local rig = rigs[ids[1]]
			if rig then
				local row = Document.unpack(
					assert(values["property|" .. identity], "Waiting for shared property track")
				)
				assert(type(row) == "table" and row.id == ids[2], "Invalid shared property track")
				table.insert(rig.itemProperties.tracks, row)
			end
		end
	end

	for _, rig in rigs do
		table.sort(rig.itemProperties.tracks, function(a, b)
			return a.id < b.id
		end)
	end

	table.sort(rows, function(a, b)
		return a.order == b.order and a.entry.id < b.entry.id or a.order < b.order
	end)
	project.rigs = {}
	for _, row in rows do
		table.insert(project.rigs, row.entry)
	end

	return project
end

function Scene.projectChanged(values, previous)
	if values.project ~= previous.project then
		return true
	end

	for _, side in { values, previous } do
		for key in side do
			if
				(
					key:sub(1, 4) == "rig|"
					or key:sub(1, 7) == "member|"
					or key:sub(1, 6) == "order|"
					or key:sub(1, 6) == "track|"
					or key:sub(1, 12) == "trackMember|"
					or key:sub(1, 9) == "property|"
					or key:sub(1, 15) == "propertyMember|"
					or key:sub(1, 14) == "propertySetup|"
				) and values[key] ~= previous[key]
			then
				return true
			end
		end
	end

	return false
end

function Scene.prepare(state, value)
	assert(
		type(value) == "table"
			and value.version == 2
			and type(value.channels) == "boolean"
			and type(value.rigs) == "table"
			and #value.rigs <= 100,
		"Invalid Live project setup"
	)
	local targets = {}
	local used = {}
	local sharedById

	local function sharedRig(id)
		if not sharedById then
			sharedById = {}

			local function visit(parent)
				for _, child in parent:GetChildren() do
					if
						child:GetAttribute("EclipseLocalLivePreview")
						or child.Name == "AnimSaves"
						or child:IsA("KeyframeSequence")
						or child:IsA("LuaSourceContainer")
					then
						continue
					end

					local key = child:GetAttribute("EclipseTrackId")
					if key then
						sharedById[key] = sharedById[key] == nil and child or false
					end

					visit(child)
				end
			end

			visit(scope(state))
		end

		assert(
			sharedById[id] ~= false,
			"Waiting for shared rig: duplicate ID on scene objects " .. id
		)
		return sharedById[id]
	end

	for _, entry in value.rigs do
		assert(type(entry.id) == "string" and not used[entry.id], "Duplicate Live rig")
		used[entry.id] = true
		local rig = entry.object and resolveObject(entry.object, state)
			or Paths.resolve(scope(state), entry.path)
		if rig then
			rig = require("rig").localize(rig)
		end

		if not rig or rigId(rig, state) ~= entry.id then
			rig = sharedRig(entry.id)
		end

		assert(rig and rig.Parent, "Waiting for shared rig " .. entry.id)
		rig = require("rig").localize(rig)
		local available = motors(rig, state.Timeline:GetState())
		for _, control in entry.r6Controls or {} do
			assert(
				control.kind == "root"
					or control.kind == "spine"
					or control.kind == "upper"
					or control.kind == "target"
					or control.kind == "pole"
					or control.kind == "roll",
				"Invalid shared IK control"
			)
			assert(typeof(control.rest) == "CFrame", "Invalid shared IK rest pose")
			local owner = assert(available[control.owner], "Waiting for shared IK owner")
			assert(require("customRest").isJoint(owner), "Invalid shared IK owner")
			if control.customIK == true then
				assert(
					require("customRest").chain(rig, owner, require("Parenting").collectMotors(rig)),
					"Shared custom IK chain is no longer connected"
				)
				owner:SetAttribute("EclipseAutoIK", true)
				require("customRest").restoreRest(owner, control.customRest)
				require("LimbIK").invalidate(rig)
			end

			local bone = Controls.ensure(owner, control.kind, control.rest)
			if control.customIK then
				bone:SetAttribute("EclipseIKControlSpace", control.controlSpace)
				bone:SetAttribute("EclipseIKAnchorOffset", control.anchorOffset)
			end
		end

		available = motors(rig, state.Timeline:GetState())
		local propertyIds = {}
		for _, row in entry.itemProperties and entry.itemProperties.tracks or {} do
			assert(Properties.definition(rig, row.id), "Unsupported shared property")
			propertyIds["property:" .. row.id] = true
		end

		for id, track in entry.tracks do
			assert(
				typeof(track.default) == "CFrame"
					and typeof(track.c1) == "CFrame"
					and type(track.parented) == "boolean",
				"Invalid Live track defaults"
			)
			assert(
				track.world == nil or typeof(track.world) == "CFrame",
				"Invalid Live world default"
			)
			assert(
				track.size == nil
					or typeof(track.size) == "Vector3"
						and track.size.X > 0
						and track.size.Y > 0
						and track.size.Z > 0,
				"Invalid Live size"
			)
			assert(
				available[id] or propertyIds[id] or id == "master" and Master.root(rig),
				"Waiting for shared bone " .. id
			)
			if available[id] and id ~= "master" then
				assert(available[id].C1 == track.c1, "Waiting for shared joint rest pose " .. id)
			end
		end

		local properties = {}
		for _, property in Runtime.properties(rig) do
			properties[Document.pack({ property.object, property.bone or "", property.key })] = true
		end

		for _, property in entry.inputs do
			assert(
				properties[Document.pack({ property.object, property.bone or "", property.key })],
				"Waiting for shared armature property " .. property.key
			)
		end

		table.insert(targets, { rig = rig, data = entry })
	end

	local function apply()
		local raw = state.Timeline:GetState()
		local refs = assert(state.LiveProject, "Live project hooks unavailable")
		Policy.setLiveChannels(value.channels)
		if value.origin then
			Origin.applyShared(state.Timeline, value.origin)
		end

		local wanted = {}
		for _, target in targets do
			wanted[target.rig] = true
		end

		for _, target in targets do
			if not table.find(state.getAllRigs(), target.rig) then
				refs.AddRig(target.rig, { Loading = true })
			end

			assert(
				table.find(state.getAllRigs(), target.rig),
				"Could not add shared rig " .. target.rig.Name
			)
		end

		for _, rig in table.clone(state.getAllRigs()) do
			if not wanted[rig] then
				refs.RemoveRig(rig)
			end
		end

		state.activeObjectMotors = state.activeObjectMotors or {}
		for _, target in targets do
			local rig, entry = target.rig, target.data
			rig:SetAttribute("EclipseIndividualParts", entry.individualParts)
			if entry.cameraTarget and require("CameraRig").isRig(rig) then
				assert(
					type(entry.cameraTarget.enabled) == "boolean"
						and (
							entry.cameraTarget.defaultEnabled == nil
							or type(entry.cameraTarget.defaultEnabled) == "boolean"
						),
					"Invalid camera tracking state"
				)
				rig:SetAttribute("EclipseTrackTarget", entry.cameraTarget.enabled)
				rig:SetAttribute(
					"EclipseCamTargetDefaultEnabled",
					entry.cameraTarget.defaultEnabled
				)
				assert(
					entry.cameraOrthographic == nil or type(entry.cameraOrthographic) == "boolean",
					"Invalid camera projection"
				)
				rig:SetAttribute("EclipseOrthographic", entry.cameraOrthographic == true)
			end

			if type(entry.feetPlanted) == "boolean" then
				rig:SetAttribute("EclipseIKFeetPlanted", entry.feetPlanted)
			end

			if entry.r6Bend ~= nil then
				assert(
					type(entry.r6Bend) == "number" and entry.r6Bend >= 0 and entry.r6Bend <= 100,
					"Invalid R6 bend"
				)
				rig:SetAttribute("EclipseR6BendPercent", entry.r6Bend)
			end

			Properties.restore(
				rig,
				entry.itemProperties or { version = 1, tracks = {} },
				state.Timeline,
				state.UIHelpers.SanitizeName
			)
			local sequence = Instance.new("Folder")
			sequence:SetAttribute("EclipseMasterControl", entry.master.enabled)
			sequence:SetAttribute("EclipseMasterRest", entry.master.rest)
			sequence:SetAttribute("EclipseMasterRadius", entry.master.radius)
			Master.read(sequence, rig)
			sequence:Destroy()
			local available = motors(rig, raw)
			for id, track in entry.tracks do
				local motor = assert(available[id], "Shared control is unavailable")
				raw.DefaultPose[motor] = track.default
				raw.DefaultWorldPose[motor] = track.world
				raw.ParentingDefaults[motor] = track.parented
				raw.DefaultSize[motor.Part1] = track.size
				raw.MotorByPart[motor.Part1] = motor
				motor:SetAttribute("EclipseParentingDefault", track.parented)
				motor:SetAttribute("EclipsePartTrackEnabled", track.partEnabled)
				motor:SetAttribute("EclipseDisabled", track.disabled and true or nil)
				for _, channel in Curves.ids do
					motor:SetAttribute(
						"EclipseChannelDisabled_" .. channel,
						track.channels[channel] and true or nil
					)
				end

				motor:SetAttribute(
					"EclipseChannelDisabledAny",
					next(track.channels) and true or nil
				)
				state.activeObjectMotors[motor] = track.active and true or nil
			end

			for id, motor in available do
				if not entry.tracks[id] then
					raw.DefaultPose[motor], raw.DefaultWorldPose[motor], raw.ParentingDefaults[motor], raw.Keyframes[motor] =
						nil, nil, nil, nil
					if raw.MotorByPart[motor.Part1] == motor then
						raw.MotorByPart[motor.Part1] = nil
					end
				end
			end

			Animation.restoreProperties(rig, entry.properties)
			for _, property in entry.inputs do
				assert(
					Runtime.setProperty(
						rig,
						property.object,
						property.key,
						property.value,
						property.bone,
						false
					),
					"Could not apply shared armature property"
				)
			end
		end

		refs.RefreshStructure()
		Organization.restore(resolveOrganization(value.organization, state), "live")
	end

	return function()
		local refs = assert(state.LiveProject, "Live project hooks unavailable")
		if refs.Batch then
			return refs.Batch(apply)
		end

		return apply()
	end
end

return Scene
