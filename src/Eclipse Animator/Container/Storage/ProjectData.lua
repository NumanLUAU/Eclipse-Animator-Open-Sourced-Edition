--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
--!strict

local Data = {}

local pluginRef: Plugin? = nil
local animSavesTemplate: Instance? = nil
local Http = game:GetService("HttpService")
local Encoding = game:GetService("EncodingService")
local PREFIX = "EclipseSettingV1:"
local observed, blocked, writing = {}, {}, {}
local storeWriting = false
local sessionHost
local sessionScope = "Legacy"
local legacySessionScope = "Legacy"
local backupKeys = {
	EclipseAnimator_Preferences = true,
	EclipseAnimator_Keybinds_v1 = true,
	EclipseAnimator_AnimationDefaults_v1 = true,
	EclipseLibraryV1 = true,
	EclipseThemeV1 = true,
}
local BACKUP = "EclipseSettingBackupV1_"
local BACKUP_LIMIT = 262144

local function unsafe(value)
	if type(value) == "string" then
		return value:find("\\", 1, true) ~= nil
	end

	if type(value) == "table" then
		for key, item in value do
			if type(key) == "string" and key:find('[\\\n\r"%.]') or unsafe(item) then
				return true
			end
		end
	end

	return false
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end

	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end

	return out
end

local function equal(a, b)
	if type(a) ~= type(b) then
		return false
	end

	if type(a) ~= "table" then
		return a == b
	end

	for k, v in a do
		if not equal(v, b[k]) then
			return false
		end
	end

	for k in b do
		if a[k] == nil then
			return false
		end
	end

	return true
end

local function unpackSetting(raw)
	if type(raw) ~= "string" or raw:sub(1, #PREFIX) ~= PREFIX then
		return raw
	end

	local text = buffer.tostring(Encoding:Base64Decode(buffer.fromstring(raw:sub(#PREFIX + 1))))
	local decoded = Http:JSONDecode(text)
	assert(
		type(decoded) == "table" and decoded.version == 1 and decoded.value ~= nil,
		"Eclipse setting could not be decoded; saved data was not changed."
	)
	return decoded.value
end

local function packSetting(value)
	if value == nil or type(value) == "number" or type(value) == "boolean" then
		return value
	end

	return PREFIX
		.. buffer.tostring(
			Encoding:Base64Encode(
				buffer.fromstring(Http:JSONEncode({ version = 1, value = value }))
			)
		)
end

local function readRaw(key, noBackup, beforeIO)
	local failed = false
	for attempt = 1, 3 do
		if beforeIO then
			beforeIO()
		end

		local ok, value = pcall(function()
			return pluginRef:GetSetting(key)
		end)
		if ok and value ~= nil then
			return value
		end

		if not ok then
			failed = true
		end

		if attempt < 3 and not beforeIO then
			task.wait(0.05 * attempt)
		end
	end

	assert(
		not failed,
		"Studio settings are temporarily unavailable. Retry without resetting your settings."
	)

	if not noBackup and backupKeys[key] then
		local saved = pluginRef:GetSetting(BACKUP .. key)
		if saved ~= nil then
			assert(type(saved) == "string" and #saved <= BACKUP_LIMIT, "Unreadable settings backup")
			unpackSetting(saved)
			return saved
		end
	end

	return nil
end

local function setPlugin(p: Plugin, host, scope, storageIdentity)
	if pluginRef ~= p then
		table.clear(observed)
		table.clear(blocked)
		table.clear(writing)
	end

	pluginRef = p
	sessionHost = host or game:GetService("CoreGui")
	legacySessionScope = scope or "Legacy"
	sessionScope = (scope or "Legacy") .. "_" .. tostring(storageIdentity or p.Name or "Local")
end

local function setAnimSavesTemplate(t: Instance)
	animSavesTemplate = t
end

local function getSetting(key: string): any
	if pluginRef then
		assert(not writing[key], "This setting is being saved. Retry shortly.")
		local ok, value, raw = pcall(function()
			local stored = readRaw(key)
			assert(
				stored ~= nil or not observed[key] or observed[key].raw == nil,
				"A previously saved setting is temporarily unavailable. Saved data was not changed."
			)
			return unpackSetting(stored), stored
		end)
		if not ok then
			blocked[key] = true
			error(value, 0)
		end

		observed[key] = { raw = copy(raw) }
		blocked[key] = nil

		if unsafe(raw) then
			Data.setSetting(key, value)
		end

		return value
	end

	return nil
end

local function setSetting(key: string, value: any, update)
	if pluginRef then
		assert(not key:find('[\\\n\r"%.]'), "Unsafe Studio setting key")
		assert(
			update or not blocked[key],
			"The saved setting could not be read. Reopen Eclipse before changing it."
		)
		assert(not writing[key], "This setting is already being saved. Retry shortly.")
		local encoded = packSetting(value)
		assert(not storeWriting, "Studio settings are already being saved. Retry shortly.")
		storeWriting = true
		writing[key] = true
		local ok, message = pcall(function()
			local current = readRaw(key)
			unpackSetting(current)
			local previous = observed[key]
			if update then
				assert(
					current ~= nil or not previous or previous.raw == nil,
					"Saved settings are temporarily unavailable; retry without resetting them."
				)
				value = update(copy(unpackSetting(current)))
				encoded = packSetting(value)
			end

			assert(
				update or not previous or equal(current, previous.raw),
				"Settings changed or became unavailable in another Studio window. Reopen Eclipse before saving."
			)
			if equal(current, encoded) then
				observed[key] = { raw = copy(encoded) }
				return
			end

			if backupKeys[key] and type(current) == "string" and #current <= BACKUP_LIMIT then
				local safe = packSetting(unpackSetting(current))
				if #safe <= BACKUP_LIMIT and pluginRef:GetSetting(BACKUP .. key) ~= safe then
					pluginRef:SetSetting(BACKUP .. key, safe)
					assert(
						pluginRef:GetSetting(BACKUP .. key) == safe,
						"Studio could not verify the preceding settings copy"
					)
				end
			end

			assert(equal(readRaw(key), current), "Settings changed while saving. Retry the change.")
			pluginRef:SetSetting(key, encoded)
			assert(
				equal(readRaw(key, true), encoded),
				"Studio could not verify the setting save. Retry after reopening Eclipse."
			)
			observed[key] = { raw = copy(encoded) }
			if backupKeys[key] and type(encoded) == "string" and #encoded <= BACKUP_LIMIT then
				pluginRef:SetSetting(BACKUP .. key, encoded)
				assert(
					pluginRef:GetSetting(BACKUP .. key) == encoded,
					"The setting was saved but its recovery copy could not be verified"
				)
			elseif backupKeys[key] and encoded == nil then
				pluginRef:SetSetting(BACKUP .. key, nil)
			end
		end)
		writing[key] = nil
		storeWriting = false
		if ok then
			blocked[key] = nil
		end

		if not ok then
			error(message, 0)
		end
	end
end

local function ensureAnimSaves(rig: Instance?): Instance?
	rig = require("rig").original(rig)
	if not rig then
		return nil
	end

	local existing = rig:FindFirstChild("AnimSaves")
	if existing then
		return existing
	end

	if animSavesTemplate then
		local clone = animSavesTemplate:Clone()
		clone.Name = "AnimSaves"
		clone.Parent = rig
		return clone
	end

	local folder = Instance.new("Folder")
	folder.Name = "AnimSaves"
	folder.Parent = rig
	return folder
end

local function sanitizeExportName(text: any): string
	local s = tostring(text or ""):gsub("[%c]", " ")
	s = s:match("^%s*(.-)%s*$") or ""
	if s == "" then
		s = "Animation"
	end

	return s
end

local function savedChildren(container: Instance?): { Instance }
	if not container then
		return {}
	end

	local children = container:GetChildren()
	if container:IsA("ObjectValue") and container.Value and container.Value ~= container then
		for _, child in container.Value:GetChildren() do
			table.insert(children, child)
		end
	end

	return children
end

local function hasSavedName(container: Instance, name: string): boolean
	for _, child in savedChildren(container) do
		if child.Name == name then
			return true
		end
	end

	return false
end

local function getUniqueExportName(animSaves: Instance, baseName: string): string
	baseName = sanitizeExportName(baseName)
	if not hasSavedName(animSaves, baseName) then
		return baseName
	end

	local index = 2
	while hasSavedName(animSaves, baseName .. " " .. index) do
		index += 1
	end

	return baseName .. " " .. index
end

local function nextNumberedName(
	container: Instance?,
	base: string,
	excluded: Instance?,
	plain: boolean?
): string
	local highest = 0
	if container then
		for _, child in savedChildren(container) do
			if child == excluded then
				continue
			end

			local name = child.Name
			local number = name:match("^" .. base .. " %((%d+)%)$")
				or name:match("^" .. base .. " (%d+)$")
			if name == base then
				number = "1"
			end

			highest = math.max(highest, tonumber(number) or 0)
		end
	end

	if plain then
		return if highest == 0 then base else base .. " " .. tostring(highest + 1)
	end

	return base .. " (" .. tostring(highest + 1) .. ")"
end

local function isDefaultProjectName(name: string): boolean
	return name == "Eclipse Project"
		or name:match("^Eclipse Project %(%d+%)$") ~= nil
		or name:match("^Eclipse Project %d+$") ~= nil
end

local function isDefaultAnimationName(name: string): boolean
	local clean = sanitizeExportName(name):gsub("^UNSAVED[- ]+", "")
	return clean == "Animation"
		or clean == "Eclipse Animation"
		or clean:match("^Animation%d*$") ~= nil
		or clean:match("^Eclipse Animation %d+$") ~= nil
		or clean:match("^Eclipse Animation %(%d+%)$") ~= nil
		or isDefaultProjectName(clean)
end

local function getNextDefaultExportName(animSaves: Instance?): string
	return nextNumberedName(animSaves, "Eclipse Animation", nil, true)
end

local function getNextDefaultProjectName(saves: Instance?, excluded: Instance?): string
	return nextNumberedName(saves, "Eclipse Project", excluded)
end

local INTERACTIVE = "EclipseInteractiveSettingsV1"
local MIRROR = "EclipseInteractiveSettingsRecoveryV2"
local SESSION = "_EclipseInteractiveSettingsSessionV3_"
local interactiveKeys = { EclipseAnimator_Preferences = true, EclipseAnimator_Keybinds_v1 = true }
local views = {}
local stopped, busy, timer, retries = false, false, 0, 0
local worker = Http:GenerateGUID(false)

local function document(raw)
	local value = unpackSetting(raw)
	if type(value) == "string" then
		value = Http:JSONDecode(value)
	end

	assert(value == nil or type(value) == "table", "Invalid saved settings document")
	return value
end

local function array(t)
	if type(t) ~= "table" then
		return false
	end

	for k in t do
		if type(k) == "number" then
			return true
		end
	end

	return false
end

local function merge(latest, before, after)
	if equal(before, after) then
		return copy(latest)
	end

	if type(before) ~= "table" or type(after) ~= "table" or array(before) or array(after) then
		return copy(after)
	end

	local out = type(latest) == "table" and copy(latest) or {}
	local keys = {}
	for k in before do
		keys[k] = true
	end

	for k in after do
		keys[k] = true
	end

	for k in keys do
		if not equal(before[k], after[k]) then
			out[k] = merge(out[k], before[k], after[k])
		end
	end

	return out
end

local function mergeRaw(latest, before, after)
	local value = merge(document(latest), document(before), document(after))
	return value and packSetting(Http:JSONEncode(value)) or nil
end

local function session()
	local name = SESSION .. sessionScope
	local node = sessionHost:FindFirstChild(name)
	assert(not node or node:IsA("StringValue"), "Invalid settings session")
	if not node then
		node = Instance.new("StringValue")
		node.Name = name
		node.Archivable = false
		node.Parent = sessionHost
	end

	local data
	if node.Value ~= "" then
		local ok, decoded = pcall(unpackSetting, node.Value)
		if
			ok
			and type(decoded) == "table"
			and decoded.version == 3
			and type(decoded.pending) == "table"
			and type(decoded.values) == "table"
		then
			data = decoded
		end
	end

	return node, data or { version = 3, pending = {}, values = {} }
end

local function retain(node, data)
	node.Value = packSetting(data)
end

local function mutex()
	local node = sessionHost:FindFirstChild("_EclipseSettingsWriterV3")
	if not node then
		node = Instance.new("Folder")
		node.Name = "_EclipseSettingsWriterV3"
		node.Archivable = false
		node.Parent = sessionHost
	end

	return node
end

function Data.withSettingsWriter(callback)
	local lock = mutex()
	assert(
		not storeWriting
			and not (
				lock:GetAttribute("Writer")
				and (lock:GetAttribute("WriterUntil") or 0) > os.clock()
			),
		"Local settings are being saved; recovery will retry"
	)
	local lease = Http:GenerateGUID(false)
	storeWriting = true
	lock:SetAttribute("Writer", lease)
	lock:SetAttribute("WriterUntil", os.clock() + 30)
	local results = table.pack(pcall(callback))
	storeWriting = false
	if lock:GetAttribute("Writer") == lease then
		lock:SetAttribute("Writer", nil)
		lock:SetAttribute("WriterUntil", nil)
	end

	assert(results[1], results[2])
	return table.unpack(results, 2, results.n)
end

local function envelope(raw)
	if raw == nil then
		return nil
	end

	local d = unpackSetting(raw)
	assert(
		type(d) == "table" and d.version == 1 and type(d.values) == "table",
		"Invalid settings envelope"
	)
	d.previous = type(d.previous) == "table" and d.previous or {}
	assert(
		d.revision == nil
			or type(d.revision) == "number" and d.revision >= 0 and d.revision < 2 ^ 52,
		"Invalid revision"
	)
	for key, value in d.values do
		assert(interactiveKeys[key] and type(value) == "string")
		document(value)
	end

	return d
end

local function readPersisted(beforeIO)
	local records, failed = {}, false
	for _, key in { INTERACTIVE, MIRROR } do
		local ok, raw = pcall(readRaw, key, true, beforeIO)
		if ok and raw ~= nil then
			local parsed, header = pcall(unpackSetting, raw)
			assert(
				not parsed
					or type(header) ~= "table"
					or header.version == nil
					or header.version == 1,
				"A newer settings format was found; pending edits retained without overwriting it"
			)
			local valid, d = pcall(envelope, raw)
			if valid then
				table.insert(records, d)
			else
				failed = true
			end
		elseif not ok then
			failed = true
		end
	end

	assert(
		#records > 0 or not failed,
		"Studio settings are temporarily unavailable; pending edits retained"
	)
	local d = records[1] or { version = 1, values = {}, previous = {}, revision = 0 }
	local other = records[2]
	if other and (other.revision or 0) > (d.revision or 0) then
		d, other = other, d
	end

	if
		other
		and (other.revision or 0) == (d.revision or 0)
		and not equal(other.values, d.values)
	then
		for key, raw in other.values do
			d.values[key] = mergeRaw(raw, d.previous[key], d.values[key]) or raw
		end
	end

	return d
end

local function savedValue(d, key, beforeIO)
	if d.values[key] ~= nil then
		return d.values[key]
	end

	return packSetting(unpackSetting(readRaw(key, nil, beforeIO)))
end

function Data.getInteractiveSetting(key)
	assert(interactiveKeys[key], "Unknown interactive setting")
	local node, cached = session()
	if cached.pending[key] then
		assert(
			not cached.pending[key].unread,
			"Waiting for saved settings before completing startup"
		)
		views[key] = { raw = cached.pending[key].value }
		return unpackSetting(views[key].raw)
	end

	local ok, raw = pcall(function()
		return savedValue(readPersisted(), key)
	end)
	if not ok then
		if cached.values[key] == nil then
			error(raw, 0)
		end

		raw = cached.values[key]
	end

	if raw == nil and cached.values[key] ~= nil then
		raw = cached.values[key]
	end

	local old = sessionHost:FindFirstChild(
		"_EclipseInteractiveSettingsSessionV2_" .. (legacySessionScope or "Legacy")
	)
	cached.legacyChecked = type(cached.legacyChecked) == "table" and cached.legacyChecked or {}
	if old and old:IsA("StringValue") and old.Value ~= "" and not cached.legacyChecked[key] then
		local valid, previous = pcall(unpackSetting, old.Value)
		if
			valid
			and type(previous) == "table"
			and type(previous.pending) == "table"
			and type(previous.bases) == "table"
		then
			local base = previous.bases[key]
			local good, merged = pcall(function()
				if
					previous.pending[key]
					and type(base) == "table"
					and base.raw ~= nil
					and raw ~= nil
					and equal(document(base.raw), document(raw))
				then
					return mergeRaw(raw, base.raw, previous.pending[key])
				end
			end)
			if good and merged then
				raw = merged
				cached.pending[key] =
					{ base = base.raw, value = raw, token = Http:GenerateGUID(false) }
			end
		end
	end

	cached.legacyChecked[key] = true
	views[key] = { raw = raw }
	cached.values[key] = raw
	retain(node, cached)
	return unpackSetting(raw)
end

function Data.flushInteractiveSettings(cooperative)
	local node, cached = session()
	if not next(cached.pending) then
		return true
	end

	local lock = mutex()
	if
		busy
		or storeWriting
		or lock:GetAttribute("Writer") and (lock:GetAttribute("WriterUntil") or 0) > os.clock()
	then
		return false
	end

	local lease = Http:GenerateGUID(false)
	worker = lease
	busy = true
	storeWriting = true
	lock:SetAttribute("Writer", lease)
	lock:SetAttribute("WriterUntil", os.clock() + 5)

	local function beforeIO()
		if cooperative and not stopped then
			task.wait()
		end

		assert(lock.Parent and lock:GetAttribute("Writer") == lease, "Settings writer interrupted")
		lock:SetAttribute("WriterUntil", os.clock() + 5)
	end

	local pending = copy(cached.pending)
	local ok, result = pcall(function()
		local d = readPersisted(beforeIO)
		for key, edit in pending do
			local latest = savedValue(d, key, beforeIO)

			latest = latest or edit.base
			d.previous[key] = latest
			d.values[key] = mergeRaw(latest, edit.base, edit.value)
		end

		d.revision = (d.revision or 0) + 1
		local encoded = packSetting(d)

		for _, key in { INTERACTIVE, MIRROR } do
			beforeIO()
			pluginRef:SetSetting(key, encoded)
			local verified = false
			for attempt = 1, 3 do
				beforeIO()
				local raw = pluginRef:GetSetting(key)
				if raw == encoded then
					verified = true
					break
				end

				if not stopped then
					task.wait(0.05 * attempt)
				end
			end

			assert(verified, "Studio did not confirm the settings write; pending edits retained")
		end

		beforeIO()
		local primary = pluginRef:GetSetting(INTERACTIVE)
		beforeIO()
		assert(
			primary == encoded and pluginRef:GetSetting(MIRROR) == encoded,
			"Settings changed during verification; merging pending edits again"
		)
		local _, current = session()
		for key, edit in pending do
			local now = current.pending[key]
			if now and now.token == edit.token then
				current.pending[key] = nil
				current.values[key] = d.values[key]
			elseif now then
				now.value = mergeRaw(d.values[key], edit.value, now.value)
				now.base = d.values[key]
				now.unread = nil
				current.values[key] = now.value
			end
		end

		retain(node, current)
		return true
	end)
	if worker == lease then
		busy = false
		storeWriting = false
	end

	if lock:GetAttribute("Writer") == lease then
		lock:SetAttribute("Writer", nil)
		lock:SetAttribute("WriterUntil", nil)
	end

	if not ok then
		error(result, 0)
	end

	return result
end

local function schedule(delaySeconds)
	timer += 1
	local ticket = timer
	task.delay(delaySeconds or 0.15, function()
		if stopped or timer ~= ticket then
			return
		end

		local ok, saved = pcall(Data.flushInteractiveSettings, true)
		if ok and saved then
			retries = 0
		else
			retries += 1

			if not ok and retries == 5 then
				warn("[Eclipse settings] Still retrying native storage: " .. tostring(saved))
			end
		end

		if not stopped and Data.hasPendingInteractiveSettings() then
			schedule(math.min(5, 0.25 * 2 ^ math.min(retries, 4)))
		end
	end)
end

function Data.queueInteractiveSetting(key, value, beforeValue)
	assert(interactiveKeys[key] and pluginRef and not stopped, "Settings session is closed")
	local encoded = packSetting(value)
	document(encoded)
	assert(
		type(encoded) == "string" and #encoded <= BACKUP_LIMIT,
		"Interactive settings are too large"
	)
	if not views[key] and beforeValue == nil then
		Data.getInteractiveSetting(key)
	end

	local before = beforeValue ~= nil and packSetting(beforeValue) or views[key] and views[key].raw
	local node, cached = session()
	local existing = cached.pending[key]
	local base = existing and existing.base or cached.values[key] or before
	local latest = existing and existing.value or cached.values[key] or before
	local desired = mergeRaw(latest, before, encoded)

	cached.pending[key] = {
		base = base,
		value = desired,
		token = Http:GenerateGUID(false),
		unread = existing and existing.unread or views[key] == nil,
	}
	cached.values[key] = desired
	retain(node, cached)
	views[key] = { raw = encoded }
	schedule()
end

function Data.resumeInteractiveSettings()
	if Data.hasPendingInteractiveSettings() then
		schedule()
	end
end

function Data.canRetryInteractiveSettings()
	return not stopped
end

function Data.shutdownInteractiveSettings()
	stopped = true
	timer += 1

	local node = mutex()
	if busy and node:GetAttribute("Writer") == worker then
		node:SetAttribute("Writer", nil)
		node:SetAttribute("WriterUntil", nil)
		busy = false
		storeWriting = false
	end

	local ok, err = pcall(Data.flushInteractiveSettings)
	if not ok then
		warn("[Eclipse settings] Pending edits retained for reload: " .. tostring(err))
	end
end

function Data.hasPendingInteractiveSettings()
	local _, cached = session()
	return next(cached.pending) ~= nil
end

Data.getPlugin = function()
	return pluginRef
end

Data.setPlugin = setPlugin
Data.setAnimSavesTemplate = setAnimSavesTemplate
Data.getSetting = getSetting
Data.setSetting = setSetting
Data.updateSetting = function(key, callback)
	assert(type(callback) == "function", "A settings update callback is required")
	return setSetting(key, nil, callback)
end

Data.ensureAnimSaves = ensureAnimSaves
Data.sanitizeExportName = sanitizeExportName
Data.getUniqueExportName = getUniqueExportName
Data.getNextDefaultExportName = getNextDefaultExportName
Data.getNextDefaultProjectName = getNextDefaultProjectName
Data.isDefaultAnimationName = isDefaultAnimationName
Data.isDefaultProjectName = isDefaultProjectName

return Data
