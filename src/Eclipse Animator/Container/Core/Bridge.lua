--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Theme = require("Theme")
local Video = {}
local URL = "http://127.0.0.1:49185"

local listeners = {}
local refs, session, token, response
local accessError
local connected, enabled, busy, closed = false, true, false, true
local ownsSession = false
local companionVersion
local sequence, offset, bestRoundTrip = 0, 0, math.huge
local lastHello = 0
local lastSuccess = 0
local reconnectDelay = 2
local authFailed = false
local lastStart
local themeDirty = true
local unsubscribe
local nextSend = 0
local lastSend, lastPushPosition = 0, nil
local handled = 0
local receiveControl
local generation = 0
local lifetime = {}
local pendingCommand

local function active()
	return refs
		and refs.ScreenGui.Enabled
		and (
			refs.AnimatorFrame.Visible
			or refs.State.CameraPreview and refs.State.CameraPreview.isFull()
		)
end

local function changed()
	for callback in listeners do
		callback()
	end
end

local function request(path, body)
	local requestGeneration = generation
	local began = os.clock()
	local headers = {}
	if body then
		headers["Content-Type"] = "application/json"
		headers["X-Eclipse-Token"] = token
	end

	local ok, result = pcall(Http.RequestAsync, Http, {
		Url = URL .. path,
		Method = body and "POST" or "GET",
		Headers = headers,
		Body = body and Http:JSONEncode(body) or nil,
	})
	if requestGeneration ~= generation then
		return nil
	end

	if not ok or not result.Success then
		if not ok then
			accessError = not Http.HttpEnabled
					and "Enable HTTP Requests in Studio's Experience Settings to connect Eclipse Video."
				or "Cannot reach Eclipse Video on this computer. Open the companion and check its local connection."
		end

		if ok and (result.StatusCode == 403 or result.StatusCode == 401) then
			accessError = "The companion rejected the connection. Update the companion and reconnect."
			local parsed, data = pcall(Http.JSONDecode, Http, result.Body)
			if parsed and typeof(data) == "table" and typeof(data.error) == "string" then
				accessError = data.error
			end
		end

		if not connected or os.clock() - lastSuccess >= 6 or ok and (result.StatusCode == 403 or result.StatusCode == 401) then
			connected = false
			response = nil
			changed()
		end
		return nil
	end

	local parsed, data = pcall(Http.JSONDecode, Http, result.Body)
	if not parsed or typeof(data) ~= "table" then
		connected = false
		return nil
	end

	lastSuccess = os.clock()
	accessError = nil
	local elapsed = os.clock() - began

	if path == "/hello" and typeof(data.now) == "number" then
		if elapsed <= bestRoundTrip * 1.5 or elapsed < 0.01 then
			offset = data.now - (began + elapsed * 0.5)
		end

		bestRoundTrip = math.min(bestRoundTrip, elapsed)
	end

	return data
end

local function hello()
	lastHello = os.clock()
	authFailed = false
	local data = request("/hello")
	if not data then
		return connected and typeof(token) == "string"
	end
	if data.app ~= "Eclipse Video" or data.protocol ~= 1 then
		connected = false
		ownsSession = false
		return false
	end

	if token ~= data.token then
		connected = false
		ownsSession = false
		handled = 0
		bestRoundTrip = math.huge
		themeDirty = true
	end

	token = data.token
	companionVersion = data.version
	if data.authorization == 1 then
		accessError = "This companion needs an update for this Eclipse build."
		connected = false
		authFailed = true
		return false
	end
	accessError = nil

	return typeof(token) == "string"
end

local function state(action, timeline, position)
	sequence += 1
	local current = timeline and timeline:GetState()
	local data = {
		action = action,
		session = session,
		seq = sequence,
		ack = handled,
		controllable = timeline ~= nil and active(),
		at = os.clock() + offset,
		position = position or current and current.CurrentTime or 0,
		playing = current and current.Playing and not timeline._playbackPreparation or false,
		preparing = current and current.Playing and timeline._playbackPreparation ~= nil or false,
		fps = current and current.FPS or 60,
		endTime = timeline and timeline:GetPlaybackEndTime() or 0,
		loop = timeline and timeline:IsLooping() or false,
	}
	if action == "state" and data.playing then
		local sampled = timeline._playbackReadyAt or timeline._videoSampleAt
		if sampled then
			data.at = sampled + offset
		end
	end

	if themeDirty then
		data.theme = Theme.videoPalette()
		themeDirty = false
	end

	return data
end

local function send(data)
	lastSend = os.clock()
	local result = request("/command", data)
	if result and not closed and data.session == session then
		response = result
		connected = not result.error
		ownsSession = connected and data.action ~= "disconnect"
		if receiveControl then
			receiveControl(result.control)
		end

		changed()
	end

	return result
end

receiveControl = function(control)
	if closed or not enabled or typeof(control) ~= "table" then
		return
	end

	local id = control.id
	if typeof(id) ~= "number" or id ~= id or id % 1 ~= 0 or id <= handled or id > 2 ^ 53 then
		return
	end

	handled = id
	local timeline = refs.State.Timeline
	if not timeline or not active() or timeline:IsExportLocked() then
		return
	end

	local current = timeline:GetState()
	if control.action == "play" then
		task.defer(function()
			while timeline._playbackPreparation and not closed and handled == id do
				task.wait()
			end

			if closed or not enabled or handled ~= id or refs.State.Timeline ~= timeline then
				return
			end

			if not active() or timeline:IsExportLocked() then
				return
			end

			timeline:StartPlayback(true)
		end)
	elseif control.action == "pause" or control.action == "seek" then
		current.Playing = false
		if
			control.action == "seek"
			and typeof(control.position) == "number"
			and control.position == control.position
		then
			current.CurrentTime = math.clamp(control.position, 0, timeline:GetPlaybackEndTime())
			local rig = timeline.refs.GetCurrentRig and timeline.refs.GetCurrentRig()
			if rig then
				timeline:ApplyPoseAtTime(rig, current.CurrentTime)
			end

			timeline:UpdatePlayhead()
		end
	end

	nextSend = 0
end

function Video.status()
	return {
		connected = connected,
		enabled = enabled,
		version = companionVersion,
		file = response and response.file or "",
		ready = response and response.ready or false,
		drift = response and response.driftMs or 0,
		error = accessError or response and response.error,
	}
end

function Video.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

function Video.setEnabled(value)
	enabled = value
	if not enabled then
		lastStart = nil
	end

	refs.Plugin:SetSetting("EclipseVideoSync", enabled)
	if not enabled and connected then
		pendingCommand = state("disconnect", refs.State.Timeline)
	end

	nextSend = 0
	changed()
end

function Video.prepare(timeline, position, isCurrent)
	if
		not enabled
		or not connected
		or not response
		or not response.ready
		or response.sync == false
		or not isCurrent()
	then
		return nil
	end

	local trip = bestRoundTrip < 1 and bestRoundTrip or 0.03
	local deadline = os.clock() + math.clamp(trip * 1.5 + 0.02, 0.035, 0.12)
	local command = state("start", timeline, position)
	command.deadline = deadline + offset
	command.playing = true
	command.preparing = false
	local marker = {}
	lastStart = marker
	pendingCommand = command
	nextSend = 0
	return deadline
end

function Video.push(urgent)
	if closed or not enabled then
		return
	end

	local timeline = refs.State.Timeline
	local current = timeline and timeline:GetState()
	if lastStart and current and not current.Playing then
		lastStart = nil
		local command = state("stop", timeline)
		pendingCommand = command
		nextSend = 0
	end

	if urgent and current and lastPushPosition ~= current.CurrentTime then
		lastPushPosition = current.CurrentTime
		nextSend = math.min(nextSend, lastSend + 0.04)
	end
end

function Video.destroy()
	if closed then
		return
	end

	closed = true
	for _, connection in lifetime do
		connection:Disconnect()
	end

	table.clear(lifetime)
	generation += 1
	pendingCommand = nil
	lastStart = nil
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end

	if ownsSession then
		local command = state("disconnect", refs.State.Timeline)
		local savedToken = token
		task.spawn(function()
			pcall(Http.RequestAsync, Http, {
				Url = URL .. "/command",
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["X-Eclipse-Token"] = savedToken,
				},
				Body = Http:JSONEncode(command),
			})
		end)
	end

	connected = false
	ownsSession = false
	changed()
end

function Video.init(options)
	Video.destroy()
	refs = options
	session = Http:GenerateGUID(false)
	handled = 0
	lastStart = nil
	closed = false
	generation += 1
	local currentGeneration = generation
	busy = false
	pendingCommand = nil
	token = nil
	response = nil
	ownsSession = false
	companionVersion = nil
	sequence = 0
	nextSend = 0
	bestRoundTrip = math.huge
	lastSuccess = 0
	enabled = true
	reconnectDelay = 2
	accessError = nil
	refs.State.VideoBridge = Video
	unsubscribe = Theme.onChanged(function()
		themeDirty = true
		nextSend = 0
	end)
	table.insert(lifetime, refs.Plugin.Unloading:Once(Video.destroy))
	table.insert(lifetime, refs.ScreenGui.Destroying:Once(Video.destroy))
	task.spawn(function()
		while not closed and currentGeneration == generation do
			local now = os.clock()
			if not enabled or not active() then
				if ownsSession then
					send(state("disconnect", refs.State.Timeline))
					ownsSession = false
				end
				if connected or response then
					connected = false
					response = nil
					ownsSession = false
					accessError = nil
					changed()
				end
				pendingCommand = nil
				lastStart = nil
				nextSend = 0
				task.wait(0.1)
				continue
			end
			if (enabled or pendingCommand) and not busy and now >= nextSend then
				busy = true
				nextSend = math.huge
				local available = connected
				if not connected or now - lastHello > 4 then
					available = hello()
				end

				if currentGeneration ~= generation then
					return
				end

				if available then
					local timeline = refs.State.Timeline
					local data = pendingCommand or state("state", timeline)
					pendingCommand = nil
					if not active() then
						data.playing = false
						data.preparing = false
					end

					send(data)
				end

				if currentGeneration ~= generation then
					return
				end

				busy = false
				reconnectDelay = connected and 2 or authFailed and 10 or 3
				nextSend = pendingCommand and 0
					or math.min(
						nextSend,
						os.clock() + (connected and (active() and 0.2 or 1) or reconnectDelay)
					)
			end

			task.wait(0.015)
		end
	end)
end

return Video
