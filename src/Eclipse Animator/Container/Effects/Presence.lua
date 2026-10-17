--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Presence = {}
local Http = game:GetService("HttpService")
local cached = setmetatable({}, { __mode = "k" })

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < 1e15
end

function Presence.read(peer)
	local text = peer:GetAttribute("Transport")
	local old = cached[peer]
	if old and old.text == text then
		return old.value
	end

	local ok, value = pcall(Http.JSONDecode, Http, text or "")
	if
		not ok
		or type(value) ~= "table"
		or not finite(value.frame)
		or not finite(value.at)
		or not finite(value.fps)
		or value.fps < 1
		or value.fps > 1000
		or not finite(value.finish)
		or (value.first ~= nil and (not finite(value.first) or value.first < 0 or value.first >= value.finish))
		or not finite(value.n)
	then
		value = nil
	end

	if value then
		value.receivedAt = os.clock()
		if (not old or not old.value) and value.playing then
			local okProgress, progress =
				pcall(Http.JSONDecode, Http, peer:GetAttribute("Progress") or "")
			if
				okProgress
				and type(progress) == "table"
				and progress.n == value.n
				and finite(progress.frame)
			then
				value.sampleFrame = progress.frame
			end
		end
	end

	cached[peer] = { text = text, value = value }
	return value
end

local observedSeen = setmetatable({}, { __mode = "k" })

function Presence.alive(peer)
	local seen = peer:GetAttribute("Seen")
	if not finite(seen) or seen <= 0 then
		observedSeen[peer] = nil
		return false
	end

	local entry = observedSeen[peer]
	if not entry then
		entry = {
			value = seen,
			changedAt = math.abs(os.time() - seen) <= 120 and os.clock() or -math.huge,
		}
		observedSeen[peer] = entry
	elseif entry.value ~= seen then
		entry.value = seen
		entry.changedAt = os.clock()
	end

	return os.clock() - entry.changedAt < 90
end

local function revision(peer)
	local value = peer:GetAttribute("SessionRevision")
	return finite(value) and value >= 0 and value % 1 == 0 and value or 0
end

local function newer(a, b)
	local ar, br = revision(a), revision(b)
	return ar > br or ar == br and a.Name > b.Name
end

function Presence.claim(peer, peers)
	local user = peer:GetAttribute("UserId")
	if not finite(user) or user <= 0 then
		return
	end

	local latest = 0
	for _, other in peers:GetChildren() do
		if other ~= peer and other:IsA("Folder") and other:GetAttribute("UserId") == user then
			latest = math.max(latest, revision(other))
		end
	end

	peer:SetAttribute("SessionRevision", latest + 1)
end

function Presence.current(peers)
	local winners, anonymous = {}, {}
	for _, peer in peers:GetChildren() do
		if not peer:IsA("Folder") then
			continue
		end

		local user = peer:GetAttribute("UserId")
		if finite(user) and user > 0 then
			if not winners[user] or newer(peer, winners[user]) then
				winners[user] = peer
			end
		else
			table.insert(anonymous, peer)
		end
	end

	local result = {}
	for _, peer in winners do
		if Presence.alive(peer) then
			result[peer.Name] = peer
		end
	end

	for _, peer in anonymous do
		if Presence.alive(peer) then
			result[peer.Name] = peer
		end
	end

	return result
end

function Presence.isCurrent(peer)
	local peers = peer.Parent
	if not peers then
		return false
	end

	local user = peer:GetAttribute("UserId")
	if not finite(user) or user <= 0 then
		return true
	end

	for _, other in peers:GetChildren() do
		if
			other ~= peer
			and other:IsA("Folder")
			and other:GetAttribute("UserId") == user
			and newer(other, peer)
		then
			return false
		end
	end

	return true
end

function Presence.groupKey(peer)
	local key = peer:GetAttribute("SyncWith")
	return if type(key) == "string" and key ~= "" then key else peer.Name
end

function Presence.group(peers, id)
	local current = Presence.current(peers)
	local me = current[id]
	if not me then
		return {}
	end

	local key = Presence.groupKey(me)
	local found = {}
	for _, p in current do
		if Presence.groupKey(p) == key then
			found[p.Name] = p
		end
	end

	found[id] = me
	return found
end

function Presence.source(peers, id)
	local best, bestData
	for name, p in Presence.group(peers, id) do
		local data = Presence.read(p)
		if
			data
			and (not bestData or data.n > bestData.n or data.n == bestData.n and name > best.Name)
		then
			best, bestData = p, data
		end
	end

	return best or Presence.current(peers)[id]
end

function Presence.position(data, now)
	local position = (data.sampleFrame or data.frame)
		+ (data.playing and math.max(0, now - (data.receivedAt or data.at)) * data.fps or 0)
	if data.playing and data.loop and data.finish > 0 then
		local first = type(data.first) == "number"
				and data.first == data.first
				and math.clamp(data.first, 0, math.max(0, data.finish - 1))
			or 0
		position = first + (position - first) % (data.finish - first)
	else
		position = math.min(position, math.max(data.frame, data.finish))
	end

	return math.max(0, position)
end

function Presence.color(id)
	local hash = 0
	for i = 1, #id do
		hash = (hash * 31 + id:byte(i)) % 360
	end

	return Color3.fromHSV(hash / 360, 0.48, 0.95)
end

function Presence.sample(peer, now)
	local data = Presence.read(peer)
	if data then
		return Presence.position(data, os.clock())
	end

	local frame = peer:GetAttribute("Frame")
	if type(frame) ~= "number" or frame ~= frame then
		return nil
	end

	local fps = peer:GetAttribute("FPS") or 60
	local stamp = peer:GetAttribute("FrameAt") or now
	local playing = peer:GetAttribute("Playing") == true
	local advance = playing and math.max(now - stamp, 0) * fps or 0
	local finish = peer:GetAttribute("PlaybackEnd") or frame
	local position = frame + advance
	if playing and peer:GetAttribute("Loop") and finish > 0 then
		position %= finish
	else
		position = math.min(position, math.max(frame, finish))
	end

	return math.max(0, position)
end

function Presence.target(peers, id, selfId)
	local visited = { [selfId] = true }
	while id do
		if visited[id] then
			return nil
		end

		visited[id] = true
		local peer = Presence.current(peers)[id]
		if not peer then
			return nil
		end

		local nextId = peer:GetAttribute("Following")
		if not nextId or nextId == "" then
			return Presence.source(peers, id)
		end

		id = nextId
	end

	return nil
end

local function paint(object, color)
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		object.ImageColor3 = color
	end

	object.BackgroundColor3 = color
end

local function markerClone(template, name)
	local clone = template:Clone()
	clone.Name = name
	local objects = clone:GetDescendants()
	table.insert(objects, clone)
	for _, object in objects do
		if object:IsA("LuaSourceContainer") then
			object:Destroy()
		elseif object:IsA("GuiObject") then
			object.Active = false
			object.Interactable = false
			object.Selectable = false
		end

		for attribute in object:GetAttributes() do
			if attribute:sub(1, 5) == "Theme" then
				object:SetAttribute(attribute, nil)
			end
		end
	end

	return clone
end

function Presence.new(timeline)
	local self = { markers = {}, tints = {} }

	function self:clear()
		for _, mark in self.markers do
			mark.line:Destroy()
			mark.head:Destroy()
		end

		self.markers = {}
		for obj, old in self.tints do
			if obj.Parent then
				obj.BackgroundColor3 = old.bg
				if old.image then
					obj.ImageColor3 = old.image
				end

				obj:SetAttribute("ThemeBg", old.themeBg)
				obj:SetAttribute("ThemeImg", old.themeImg)
			end
		end

		self.tints = {}
	end

	function self:update(people, selfId, ownColor, dt)
		local refs = timeline.refs
		local selector, top = refs.Selector, refs.TopSelector
		if not selector or not top then
			return
		end

		for _, obj in { selector, top } do
			if not self.tints[obj] then
				self.tints[obj] = {
					bg = obj.BackgroundColor3,
					image = (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and obj.ImageColor3
						or nil,
					themeBg = obj:GetAttribute("ThemeBg"),
					themeImg = obj:GetAttribute("ThemeImg"),
				}
			end

			obj:SetAttribute("ThemeBg", nil)
			obj:SetAttribute("ThemeImg", nil)
			paint(obj, ownColor)
		end

		local present = {}
		for _, person in people do
			if person.id ~= selfId and person.frame then
				present[person.id] = true
				local mark = self.markers[person.id]
				if
					not mark
					or mark.line.Parent ~= selector.Parent
					or mark.head.Parent ~= top.Parent
				then
					if mark then
						mark.line:Destroy()
						mark.head:Destroy()
					end

					local line = markerClone(selector, "LivePlayhead")
					local head = markerClone(top, "LiveCreator")
					local label = head:FindFirstChildWhichIsA("TextLabel", true)
					line.Parent = selector.Parent
					head.Parent = top.Parent
					mark = { line = line, head = head, label = label }
					self.markers[person.id] = mark
				end

				local target = person.frame
				mark.frame = target
				local x = timeline:FrameToVisibleX(mark.frame)
				local visible = person.frame <= timeline:GetMaxFrame()
				mark.line.Visible = visible
				mark.head.Visible = visible
				mark.line.Position =
					UDim2.new(0, x, selector.Position.Y.Scale, selector.Position.Y.Offset)
				mark.head.Position = UDim2.new(0, x, top.Position.Y.Scale, top.Position.Y.Offset)
				mark.line.Size = selector.Size
				mark.line.AnchorPoint = selector.AnchorPoint
				mark.head.Size = top.Size
				mark.head.AnchorPoint = top.AnchorPoint
				paint(mark.line, person.color)
				paint(mark.head, person.color)
				if mark.label then
					mark.label.Text = tostring(math.floor(person.frame + 0.5))
				end
			end
		end

		for id, mark in self.markers do
			if not present[id] then
				mark.line:Destroy()
				mark.head:Destroy()
				self.markers[id] = nil
			end
		end
	end

	return self
end

return Presence
