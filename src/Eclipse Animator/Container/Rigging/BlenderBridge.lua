--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local Codec = require("SceneCodec")
local Bones = require("Bones")
local RigExport = require("RigExport")
local Bridge = { ICON = "rbxassetid://83623854422962" }
local URL = "http://127.0.0.1:49186"
local listeners = {}
local refs, token, session, manifest, bindings, context, connection
local pairs, objects = {}, {}
local direction, live, busy, message, ack =
	"blender", false, false, "Start the server in the Eclipse tab in Blender.", 0
local nextPoll, requested = 0, 0
local polling = false
local importing = false
local version = 0
local failure, signature
local retryAt, retries, followUntil, requestAt = 0, 0, 0, 0
local playback, sentPose, sentKeys, pendingTake, pendingKeys
local pendingParts, pendingTransfer, partIndex
local takeRevision = 0
local groupImportedKeys = false
local CHUNK = 600000

local function chunks(take)
	local parts = {}
	local current, size = {}, 0
	for _, frame in take.frames do
		local cost = #Http:JSONEncode(frame)
		if size + cost > CHUNK and #current > 0 then
			table.insert(parts, current)
			current, size = {}, 0
		end

		table.insert(current, frame)
		size += cost
	end

	if #current > 0 or #parts == 0 then
		table.insert(parts, current)
	end

	return parts
end

local pullPending, importNotice = false, nil
local accessory, accessoryRig
local sourcePose
local closing = false
local memberCount = 0
local INTERVAL = 0.2

local function changed()
	if closing then
		return
	end

	local value = table.concat({
		tostring(session),
		tostring(busy or importing),
		tostring(live),
		direction,
		failure or message,
		tostring(version),
		tostring(Bridge.available()),
		tostring(groupImportedKeys),
	}, "|")
	if signature == value then
		return
	end

	signature = value
	for callback in listeners do
		callback()
	end
end

local function clean(errorValue)
	return tostring(errorValue):gsub("^.-:%d+:%s*", "")
end

local function current()
	if closing or not refs then
		return
	end

	local state = refs.State

	return refs.Active(true)
		and state.currentRig
		and (
			state.currentProjectSave
			or state.currentProjectSequence
			or state.currentAnimations[state.currentRig]
			or state.currentRig
		)
end

function Bridge.available()
	return current() ~= nil and current() ~= false
end

function Bridge.isLive()
	return session ~= nil and live
end

function Bridge.isLocked()
	return session ~= nil and live and direction == "blender"
end

function Bridge.isFollowing()
	return false
end

function Bridge.advance(dt)
	return false
end

local function valid(owner)
	if session ~= owner or not context or current() ~= context then
		return false
	end

	local members = refs.State.getAllRigs()
	if #members ~= memberCount or refs.State.Timeline:GetState().FPS ~= manifest.fps then
		return false
	end

	for _, entry in bindings do
		if not entry.rig.Parent or not table.find(members, entry.rig) then
			return false
		end
	end

	return true
end

local function request(path, data)
	local now = os.clock()
	local at = math.max(now, requestAt)
	requestAt = at + INTERVAL
	if at > now then
		task.wait(at - now)
	end

	local headers = {}
	if data then
		headers["Content-Type"], headers["X-Eclipse-Token"] = "application/json", token
	end

	local response = Http:RequestAsync({
		Url = URL .. path,
		Method = data and "POST" or "GET",
		Headers = headers,
		Body = data and Http:JSONEncode(data) or nil,
	})
	local result = Http:JSONDecode(response.Body)
	if not response.Success or result.error then
		local detail = tostring(
			result.error
				or ("Blender request failed (HTTP " .. tostring(response.StatusCode) .. ").")
		)
		if path == "/pair" then
			local rigName = tostring(data.rig)
			for _, rig in manifest and manifest.rigs or {} do
				if rig.id == data.rig then
					rigName = rig.name
					break
				end
			end

			if detail:find("More than one rig matches", 1, true) then
				detail = "Several Blender objects match. Choose a Blender Object, then click PAIR SELECTED."
					.. "\nThis is an ambiguity between Blender objects, not Eclipse timeline rigs."
			end

			local names = {}
			for _, object in objects do
				table.insert(names, object.name .. " (" .. object.kind .. ")")
			end

			detail ..= "\nEclipse rig: " .. rigName .. "\nBlender object: " .. tostring(
				data.object or "Auto search"
			) .. "\nObjects reported by Blender: " .. (#names > 0 and table.concat(names, ", ") or "none")
		end

		error(detail, 0)
	end

	return result
end

local function sendTake(owner, take)
	local parts = chunks(take)
	local transfer = Http:GenerateGUID(false)
	local result
	for index, frames in parts do
		local body = table.clone(take)
		body.frames = frames
		result = request(
			"/take",
			{ session = owner, take = body, transfer = transfer, part = index, parts = #parts }
		)
	end

	return result
end

local function allowed()
	local selected = {}
	for _, pair in pairs do
		selected[pair.rig] = true
	end

	return selected
end

function Bridge.status()
	return {
		connected = session ~= nil,
		available = Bridge.available(),
		message = importing and "Importing Blender animation..." or failure or message,
		error = failure ~= nil or importNotice ~= nil,
		busy = busy or importing,
		live = live,
		groupImportedKeys = groupImportedKeys,
		direction = direction,
		pairs = pairs,
		objects = objects,
		rigs = manifest and manifest.rigs or {},
	}
end

function Bridge.ensureConnected()
	if not session and not busy and Bridge.available() then
		Bridge.connect()
	end
end

function Bridge.setGroupImportedKeys(enabled)
	groupImportedKeys = enabled == true
	changed()
end

function Bridge.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

function Bridge.disconnect(reason)
	local owner = session
	failure = nil
	if Bridge.isFollowing() then
		refs.State.Timeline:GetState().Playing = false
	end

	session, live, context = nil, false, nil
	playback, pendingTake, pendingKeys, sentKeys, sentPose = nil, nil, nil, nil, nil
	pendingParts, pendingTransfer, partIndex = nil, nil, nil
	pullPending, importNotice = false, nil
	sourcePose = nil
	accessory, accessoryRig = nil, nil
	followUntil, retries, retryAt = 0, 0, 0
	requested += 1
	message = reason or "Disconnected"
	if not closing and refs.State.currentRig and refs.State.Timeline then
		refs.State.Timeline:ApplyPoseAtTime(
			refs.State.currentRig,
			refs.State.Timeline:GetState().CurrentTime
		)
	end

	if owner then
		task.spawn(function()
			pcall(request, "/disconnect", { session = owner })
		end)
	end

	changed()
end

local function operation(callback)
	if refs.State.Timeline:GetState().Exporting or refs.State.LoadingProject then
		return
	end

	if busy then
		return
	end

	busy = true
	failure = nil
	local ticket = requested
	changed()
	task.spawn(function()
		local ok, err = pcall(callback)
		if ticket == requested and not ok then
			failure = clean(err)
		end

		busy = false
		changed()
	end)
end

function Bridge.connect()
	if session then
		Bridge.disconnect()
		return
	end

	if not Bridge.available() then
		message = "Open an Eclipse file first."
		changed()
		return
	end

	operation(function()
		local owner = Http:GenerateGUID(false)
		local ticket = requested
		local start = current()
		local hello = request("/hello")
		assert(
			hello.app == "Eclipse Blender" and hello.protocol == 1,
			"this is not the Eclipse Blender server"
		)
		if (hello.revision or 0) < 8 then
			error("Update the Eclipse Blender add-on, then restart Blender.", 0)
		end

		token = hello.token
		assert(hello.authorization ~= 1, "This Blender companion needs an update for this Eclipse build.")

		local data, targets = Codec.capture(refs)
		local result = request("/connect", { session = owner, manifest = data })
		assert(start == current() and ticket == requested, "file changed while connecting")
		session, context, manifest, bindings, ack = owner, start, data, targets, 0
		memberCount = #refs.State.getAllRigs()
		objects, pairs = result.objects or {}, result.pairs or {}
		message = "Connected - Blender " .. (result.version or "")
	end)
end

function Bridge.pair(rig, object, mapping, units, automatic)
	if busy or importing then
		return
	end

	version += 1
	local owner = session
	operation(function()
		assert(valid(owner), "reconnect from the current file")
		if not rig then
			error("Choose an Eclipse rig first.", 0)
		end

		if not automatic and not object then
			error("Choose a Blender object first, or click Auto.", 0)
		end

		local result = request("/pair", {
			session = owner,
			rig = rig,
			object = object,
			mapping = mapping,
			units = units,
			auto = automatic == true and object == nil,
		})
		if not valid(owner) then
			return
		end

		pairs = result.pairs
		objects = result.objects or objects
		for _, paired in pairs do
			if paired.rig == rig then
				message = "Paired " .. paired.object
			end
		end
	end)
end

function Bridge.unpair(rig)
	if busy or importing then
		return
	end

	version += 1
	local owner = session
	operation(function()
		assert(valid(owner), "reconnect from the current file")
		local result = request("/unpair", { session = owner, rig = rig })
		if valid(owner) then
			pairs = result.pairs
			message = "Pair removed"
		end
	end)
end

function Bridge.mode(value, enabled)
	if busy or importing then
		return
	end

	version += 1
	local owner = session
	operation(function()
		assert(valid(owner), "reconnect from the current file")
		assert(
			not enabled or not refs.State.LiveSession or not refs.State.LiveSession.isJoined(),
			"Leave Eclipse Live before enabling Blender Live."
		)
		assert(#pairs > 0 or not enabled, "pair a rig or camera first")
		refs.Finalize()
		if Bridge.isFollowing() and (not enabled or value ~= "blender") then
			refs.State.Timeline:GetState().Playing = false
		end

		direction, live = value, enabled
		playback, sentPose, sentKeys, pendingTake, pendingKeys = nil, nil, nil, nil, nil
		pendingParts, pendingTransfer, partIndex = nil, nil, nil
		followUntil = 0
		pullPending, importNotice = false, nil
		sourcePose = nil
		message = enabled and "Live sync on" or "Live sync paused"
		changed()
		request("/mode", { session = owner, direction = value, live = enabled })
	end)
end

function Bridge.pull()
	local owner = session
	operation(function()
		assert(valid(owner), "reconnect from the current file")
		pullPending = true
		request("/bake", { session = owner })
		if valid(owner) then
			message = "Sampling Blender animation..."
		end
	end)
end

function Bridge.push()
	local owner = session
	operation(function()
		assert(valid(owner) and #pairs > 0, "pair a rig or camera first")
		message = "Sampling Eclipse animation..."
		changed()
		refs.Finalize()
		local take = Codec.take(refs, bindings, allowed(), function()
			return valid(owner)
		end)
		assert(valid(owner), "file changed while sampling")
		sendTake(owner, take)
		if valid(owner) then
			message = "Sent a new Blender take"
		end
	end)
end

function Bridge.exportRigs(options)
	operation(function()
		assert(Bridge.available(), "open an Eclipse file first")
		local members, selected = refs.State.getAllRigs(), Selection:Get()
		local export = {}
		for _, rig in members do
			for _, object in selected do
				if object == rig or object:IsDescendantOf(rig) then
					table.insert(export, rig)
					break
				end
			end
		end

		if #export == 0 then
			export = members
		end

		local chosen = {}
		for _, rig in export do
			chosen[rig] = true
		end

		RigExport.save(refs, chosen, options)
		message =
			"Import the OBJ from the Eclipse tab in Blender. Keep its MTL and textures beside it."
	end)
end

function Bridge.syncBones(id)
	local owner = session
	operation(function()
		assert(valid(owner) and bindings[id], "Choose a paired rig first.")
		version += 1
		live = false
		request("/mode", { session = owner, direction = direction, live = false })
		local packet = request("/bones", { session = owner, rig = id })
		assert(valid(owner), "File changed during bone sync.")
		local count, added = Bones.apply(refs, bindings[id], packet, function()
			Bridge.disconnect("Rig structure changed. Reconnect to sync.")
		end)
		manifest, bindings = Codec.capture(refs)
		local result = request(
			"/refresh",
			{ session = owner, manifest = manifest, additions = { [id] = added } }
		)
		if not valid(owner) then
			return
		end

		pairs, objects = result.pairs, result.objects
		message = count > 0
				and ("Added " .. count .. " output bones. Pairing updated; Live is off.")
			or "Output bones are already in sync."
	end)
end

function Bridge.pickAccessory(id)
	if accessory then
		accessory, accessoryRig = nil, nil
		return "Select a weapon or accessory in Explorer.", false
	end

	local rig = bindings and bindings[id] and bindings[id].rig
	if not rig then
		return "Connect and choose a project rig first."
	end

	local selected = Selection:Get()
	if
		#selected ~= 1
		or selected[1] == rig
		or not (
			selected[1]:IsA("Model")
			or selected[1]:IsA("BasePart")
			or selected[1]:IsA("Accessory")
		)
	then
		return "Select one weapon, accessory, or part in Explorer."
	end

	accessory, accessoryRig = selected[1], rig
	return accessory.Name .. " - " .. RigExport.connection(rig, accessory), true
end

function Bridge.exportAccessory(id, options)
	operation(function()
		local rig = bindings and bindings[id] and bindings[id].rig
		assert(
			rig and accessoryRig == rig and accessory and accessory.Parent,
			"Choose a rig and use the weapon selection first."
		)
		options = table.clone(options or {})
		options.accessory = accessory
		RigExport.save(refs, { [rig] = true }, options)
		message =
			"Accessory OBJ exported with its bone connection. Import it using Eclipse in Blender."
	end)
end

local function poll()
	if refs.State.Timeline:GetState().Exporting or refs.State.LoadingProject then
		return
	end

	local owner = session
	if not owner then
		return
	end

	if not valid(owner) then
		Bridge.disconnect("File changed. Reconnect to pair its rigs.")
		return
	end

	if busy or polling or os.clock() < retryAt then
		return
	end

	polling = true
	local revision = version
	task.spawn(function()
		local ok, err = xpcall(function()
			local outgoing, poseKey
			if live and direction == "eclipse" then
				local selected = allowed()
				local keys = Codec.keyState(refs, bindings, selected)
				if keys ~= sentKeys and not refs.State.Timeline:GetState().Playing then
					if pendingKeys == keys and not pendingTake then
						pendingTake = Codec.take(refs, bindings, selected, function()
							return valid(owner) and revision == version
						end)
						local after = Codec.keyState(refs, bindings, selected)
						if after ~= keys then
							pendingKeys, pendingTake = after, nil
						else
							takeRevision += 1
							pendingParts, pendingTransfer, partIndex =
								chunks(pendingTake), Http:GenerateGUID(false), 1
						end
					elseif pendingKeys ~= keys then
						pendingKeys, pendingTake, pendingParts = keys, nil, nil
					end
				end

				outgoing = Codec.pose(refs, bindings, selected)
				poseKey = Http:JSONEncode(outgoing)
				if poseKey == sentPose then
					outgoing = nil
				end
			end

			local part
			if pendingTake and pendingParts then
				part = table.clone(pendingTake)
				part.frames = pendingParts[partIndex]
			end

			local result = request("/poll", {
				session = owner,
				ack = ack,
				pose = outgoing,
				take = part,
				takeRevision = pendingTake and takeRevision,
				transfer = part and pendingTransfer,
				part = part and partIndex,
				parts = part and #pendingParts,
				mode = { direction = direction, live = live },
			})
			if not valid(owner) or result.session ~= owner or revision ~= version then
				return
			end

			retries, retryAt = 0, 0
			if sentPose ~= poseKey then
				sentPose = poseKey
			end

			if pendingTake and result.takeAck == takeRevision then
				sentKeys, pendingKeys, pendingTake, pendingParts = pendingKeys, nil, nil, nil
			elseif pendingParts and result.takePart == partIndex then
				partIndex = math.min(partIndex + 1, #pendingParts)
			end

			if result.resumed then
				sentKeys, sentPose = nil, nil
				if pendingParts then
					partIndex = 1
				end
			end

			if refs.State.Timeline:GetState().Exporting or refs.State.LoadingProject then
				return
			end

			local notice
			if
				result.take
				and (result.take.manual or pullPending or (live and direction == "blender"))
				and result.take.revision > ack
			then
				local take = result.take
				assert(take.session == owner, "animation came from another file")
				importing = true
				changed()
				local _, warning = Codec.import(refs, bindings, take, {
					groupKeys = groupImportedKeys,
					valid = function()
						return valid(owner) and revision == version
					end,
				})
				if not valid(owner) or revision ~= version then
					return
				end

				notice = warning
				importNotice, pullPending = warning, false
				ack = take.revision
			end

			message = notice or importNotice or result.status or message
		end, debug.traceback)
		polling, importing = false, false
		if not ok and session == owner then
			retries += 1
			retryAt = os.clock() + math.min(8, INTERVAL * 2 ^ math.min(retries, 4))
			failure = clean(err) .. " - retrying automatically"
			if playback then
				refs.State.Timeline:GetState().Playing = false
			end

			playback, followUntil = nil, 0
		elseif
			ok
			and retries == 0
			and failure
			and failure:find("retrying automatically", 1, true)
		then
			failure = nil
		end

		changed()
	end)
end

function Bridge.waitForExport(cancelled)
	while busy or polling do
		assert(not cancelled or not cancelled(), "Export cancelled")
		task.wait()
	end
end

function Bridge.destroy()
	if closing then
		return
	end

	closing = true
	if connection then
		connection:Disconnect()
		connection = nil
	end

	Bridge.disconnect()
	table.clear(listeners)
end

function Bridge.init(options)
	closing = false
	refs = options
	refs.State.BlenderBridge = Bridge
	connection = RunService.Heartbeat:Connect(function()
		if not session then
			return
		end

		if os.clock() < nextPoll then
			return
		end

		nextPoll = os.clock() + INTERVAL
		poll()
	end)
	refs.ScreenGui.Destroying:Once(Bridge.destroy)
end

return Bridge
