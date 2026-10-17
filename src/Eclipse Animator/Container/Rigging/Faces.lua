--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Events = require("Events")
local State = require("State")
local History = require("History")
local Organization = require("Organization")
local CameraRig = require("CameraRig")
local Tool = require("Tool")
local Theme = require("Theme")
local Input = require("UserInputService")
local Http = game:GetService("HttpService")
local Motion = require("Motion")
local Faces = { ICON = "" }

function Faces.attach(image, key)
	return require("EventIcons").attach(image, key and "facekey" or "face")
end

local rows, originals = {}, {}
local clipboard, editor, drag, refs
local selection = {}
local Shortcuts = require("Shortcuts")

local function modified()
	return Input:IsKeyDown(Enum.KeyCode.LeftControl)
		or Input:IsKeyDown(Enum.KeyCode.RightControl)
		or Input:IsKeyDown(Enum.KeyCode.LeftShift)
		or Input:IsKeyDown(Enum.KeyCode.RightShift)
end

local function isSelected(rig, id)
	const ids = selection[rig]
	return ids ~= nil and ids[id] == true
end

local function setSelected(rig, id, value)
	local ids = selection[rig]
	if value then
		if not ids then
			ids = {}
			selection[rig] = ids
		end

		ids[id] = true
	elseif ids then
		ids[id] = nil
		if next(ids) == nil then
			selection[rig] = nil
		end
	end
end

local function cloneSelection(source)
	const copy = {}
	for rig, ids in source do
		copy[rig] = table.clone(ids)
	end

	return copy
end

local function selectedKeys()
	const result = {}
	for rig, ids in selection do
		const track = rig.Parent and Events.all()[rig]
		const keys = track and track.FaceKeys
		for id in ids do
			const key = keys and keys[id]
			if key then
				table.insert(result, { rig = rig, id = id, key = key })
			end
		end
	end

	return result
end

function Faces.supports(rig)
	local head = rig
		and rig.Parent ~= game
		and rig:IsA("Model")
		and not CameraRig.isRig(rig)
		and rig:FindFirstChild("Head", true)
	return typeof(head) == "Instance" and head:IsA("BasePart")
end

local faceIndexes = setmetatable({}, { __mode = "k" })

function Faces.sample(track, frame)
	if track.FacesEnabled ~= true then
		return nil
	end

	local entry = faceIndexes[track]
	if not entry or entry.revision ~= track.Revision or entry.source ~= track.FaceKeys then
		entry = { revision = track.Revision, source = track.FaceKeys, keys = {} }
		local frames = {}
		for _, key in track.FaceKeys or {} do
			if type(key.Frame) ~= "number" or key.Frame ~= key.Frame then
				entry.invalid = true
				break
			end

			local old = frames[key.Frame]
			if not old or key.Id < old.Id then
				frames[key.Frame] = key
			end
		end

		for _, key in frames do
			table.insert(entry.keys, key)
		end

		table.sort(entry.keys, function(a, b)
			return a.Frame < b.Frame
		end)
		faceIndexes[track] = entry
	end

	if not entry.invalid then
		local low, high = 1, #entry.keys
		while low <= high do
			local mid = (low + high) // 2
			if entry.keys[mid].Frame <= frame then
				low = mid + 1
			else
				high = mid - 1
			end
		end

		return entry.keys[high] and entry.keys[high].Image or nil
	end

	local found
	for _, key in track.FaceKeys or {} do
		if
			key.Frame <= frame
			and (
				not found
				or key.Frame > found.Frame
				or key.Frame == found.Frame and key.Id < found.Id
			)
		then
			found = key
		end
	end

	return found and found.Image or nil
end

function Faces.originalPresentation(rig, decal)
	local saved = originals[rig]
	if saved and saved.decal == decal then
		return {
			Texture = saved.created and "" or saved.texture,
			Transparency = saved.transparency,
			LocalTransparencyModifier = saved.localTransparency,
			Face = saved.face,
		}
	end

	return {
		Texture = decal and decal.Texture or "",
		Transparency = decal and decal.Transparency or 0,
		LocalTransparencyModifier = decal and decal.LocalTransparencyModifier or 0,
		Face = decal and decal.Face or Enum.NormalId.Front,
	}
end

function Faces.restore(rig)
	local saved = originals[rig]
	if not saved then
		return
	end

	originals[rig] = nil
	if saved.created then
		saved.decal:Destroy()
	else
		saved.decal.Texture = saved.texture
		saved.decal.Transparency = saved.transparency
		saved.decal.LocalTransparencyModifier = saved.localTransparency
		saved.decal.Face = saved.face
		saved.decal:SetAttribute("EclipseFaceOriginalTexture", nil)
	end
end

function Faces.apply(rig, time, fps)
	local track = Events.all()[rig]
	local image = track and Organization.isEnabled(rig) and Faces.sample(track, time * fps + 1e-6)
		or nil
	if not image or image == "" then
		Faces.restore(rig)
		return
	end

	local saved = originals[rig]
	if saved and (saved.decal.Parent ~= saved.head or not saved.head:IsDescendantOf(rig)) then
		Faces.restore(rig)
		saved = nil
		originals[rig] = nil
	end

	if not saved and not Faces.supports(rig) then
		Faces.restore(rig)
		return
	end

	if not saved then
		local head = rig:FindFirstChild("Head", true)
		local decal = head:FindFirstChild("face")
		if not decal or not decal:IsA("Decal") then
			decal = nil
			for _, v in head:GetChildren() do
				if v:IsA("Decal") and v.Face == Enum.NormalId.Front then
					decal = v
					break
				end
			end
		end

		local created = decal == nil
		if created then
			decal = Instance.new("Decal")
			decal.Name = "face"
			decal.Face = Enum.NormalId.Front
			decal.Parent = head
		end

		if created then
			decal:SetAttribute("EclipseFaceCreated", true)
		else
			decal:SetAttribute("EclipseFaceOriginalTexture", decal.Texture)
		end

		saved = {
			decal = decal,
			head = head,
			texture = decal.Texture,
			created = created,
			transparency = decal.Transparency,
			localTransparency = decal.LocalTransparencyModifier,
			face = decal.Face,
		}
		originals[rig] = saved
	end

	saved.decal.Transparency = 0
	saved.decal.LocalTransparencyModifier = 0
	saved.decal.Face = Enum.NormalId.Front
	if saved.decal.Texture ~= image then
		saved.decal.Texture = image
	end
end

function Faces.closeEditor()
	if State.Library then
		State.Library.closeSounds(Faces)
	end

	if editor then
		local old = editor
		editor = nil
		old:close()
	end
end

local function commit(timeline, rig, mutate, label)
	local track = Events.get(rig)
	local before = Events.snapshot(track)
	track.FaceKeys = track.FaceKeys or {}
	mutate(track.FaceKeys, track)
	Events.changed(track)
	local after = Events.snapshot(track)

	local function show()
		Faces.refresh(timeline)
		Faces.apply(rig, timeline:GetState().CurrentTime, timeline:GetState().FPS)
		timeline:UpdateDeleteButtonState()
	end

	show()

	local function restore(value)
		Faces.closeEditor()
		Events.restore(track, value)
		table.clear(selection)
		show()
	end

	History.record(function()
		restore(before)
	end, function()
		restore(after)
	end, label)
end

function Faces.set(timeline, rig, frame, image, id)
	frame = math.max(0, math.floor(frame + 0.5))
	id = id or Http:GenerateGUID(false)
	commit(timeline, rig, function(keys, track)
		track.FacesEnabled = true
		for old, key in keys do
			if old ~= id and key.Frame == frame then
				keys[old] = nil
			end
		end

		keys[id] = { Id = id, Frame = frame, Image = image }
	end, "Set face")
	timeline:EnsureTimelineEnd(frame)
	return id
end

function Faces.delete(timeline, rig, id)
	if not (Events.get(rig).FaceKeys or {})[id] then
		return
	end

	Faces.closeEditor()
	setSelected(rig, id, false)
	commit(timeline, rig, function(keys)
		keys[id] = nil
	end, "Delete face key")
end

local function deleteSelected(timeline)
	const byRig = {}
	for _, entry in selectedKeys() do
		byRig[entry.rig] = byRig[entry.rig] or {}
		table.insert(byRig[entry.rig], entry.id)
	end

	table.clear(selection)
	if next(byRig) == nil then
		return false
	end

	Faces.closeEditor()
	for rig, ids in byRig do
		commit(timeline, rig, function(keys)
			for _, id in ids do
				keys[id] = nil
			end
		end, #ids > 1 and "Delete face keys" or "Delete face key")
	end

	return true
end

function Faces.move(timeline, moving, offset)
	const byRig = {}
	for _, item in moving do
		byRig[item.rig] = byRig[item.rig] or {}
		table.insert(byRig[item.rig], item)
	end

	local last = 0
	History.batch("Move face keys", function()
		for rig, items in byRig do
			commit(timeline, rig, function(keys)
				const targets = {}
				const movingIds = {}
				for _, item in items do
					targets[item.frame + offset] = true
					movingIds[item.id] = true
				end

				for other, key in keys do
					if not movingIds[other] and targets[key.Frame] then
						keys[other] = nil
					end
				end

				for _, item in items do
					const key = keys[item.id]
					if key then
						const moved = table.clone(key)
						moved.Frame = item.frame + offset
						keys[item.id] = moved
						last = math.max(last, moved.Frame)
					end
				end
			end, #items > 1 and "Move face keys" or "Move face key")
		end
	end)
	timeline:EnsureTimelineEnd(last)
end

local function pasteFaces(timeline, anchor, reverse)
	const rigs = State.getAllRigs()
	local span = 0
	if reverse then
		for _, entry in clipboard do
			span = math.max(span, entry.offset)
		end

		for _, entry in timeline:GetState()._KeyframeClipboard or {} do
			span = math.max(span, entry.offsetFrame or 0)
		end
	end

	const byRig = {}
	for _, entry in clipboard do
		if entry.rig.Parent and table.find(rigs, entry.rig) then
			const frame = anchor + (if reverse then span - entry.offset else entry.offset)
			if frame >= 0 then
				byRig[entry.rig] = byRig[entry.rig] or {}
				table.insert(byRig[entry.rig], { frame = frame, image = entry.image })
			end
		end
	end

	if next(byRig) == nil then
		return false
	end

	Faces.closeEditor()
	const pasted = {}
	local last = 0
	for rig, items in byRig do
		const ids = {}
		commit(timeline, rig, function(keys, track)
			track.FacesEnabled = true
			for _, item in items do
				for old, key in keys do
					if key.Frame == item.frame then
						keys[old] = nil
					end
				end

				const id = Http:GenerateGUID(false)
				keys[id] = { Id = id, Frame = item.frame, Image = item.image }
				table.insert(ids, id)
				last = math.max(last, item.frame)
			end
		end, #items > 1 and "Paste face keys" or "Paste face key")
		pasted[rig] = ids
	end

	timeline:EnsureTimelineEnd(last)
	table.clear(selection)
	for rig, ids in pasted do
		for _, id in ids do
			setSelected(rig, id, true)
		end
	end

	Faces.refresh(timeline)
	timeline:UpdateDeleteButtonState()
	return true
end

function Faces.pick(timeline, rig, frame, id)
	if not State.Library or not rig.Parent then
		return
	end

	State.Library.openFaces(Faces, function(image)
		if rig.Parent and table.find(State.getAllRigs(), rig) then
			Faces.set(timeline, rig, frame, image, id)
		end
	end)
end

function Faces.open(timeline, rig, id)
	Faces.closeEditor()
	local key = (Events.get(rig).FaceKeys or {})[id]
	if not key then
		return
	end

	if not refs then
		Faces.pick(timeline, rig, key.Frame, id)
		return
	end

	editor = Tool.new(refs, "EclipseFaceKey", "FACE KEY", Vector2.new(264, 158), false, function()
		editor = nil
	end)
	local frame = editor.frame
	Tool.label(frame, "FrameLabel", "Frame", UDim2.fromOffset(12, 40), UDim2.fromOffset(56, 24))
	local number =
		Tool.field(frame, "Frame", key.Frame, UDim2.fromOffset(76, 40), UDim2.new(1, -88, 0, 24))
	require("NumericInput").connect(number, { step = 1, min = 0, integer = true }, function()
		local value = tonumber(number.Text)
		if value and value == value and value >= 0 and value < math.huge then
			Faces.set(timeline, rig, value, key.Image, id)
			key = (Events.get(rig).FaceKeys or {})[id]
		end

		number.Text = tostring(key.Frame)
	end)
	Tool.button(
		frame,
		"Choose",
		"LIBRARY / UPLOAD",
		UDim2.fromOffset(12, 76),
		UDim2.new(1, -24, 0, 28),

		function()
			Faces.pick(timeline, rig, key.Frame, id)
		end
	)
	Tool.button(frame, "Delete", "DELETE KEY", UDim2.fromOffset(12, 116), UDim2.new(1, -24, 0, 26), function()
		Faces.delete(timeline, rig, id)
	end
)
	Theme.applyTree(frame)
end

local function inside(gui, point)
	if not gui or not gui.Parent then
		return false
	end

	if not Input.isGuiPointCompatible(gui) then
		return false
	end

	local node = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end

		node = node.Parent
	end

	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y
end

function Faces.contains(point, allowEmptyLane)
	if drag or editor and inside(editor.frame, point) then
		return true
	end

	for _, row in rows do
		if inside(row.item.uiElement, point) then
			return true
		end

		if inside(row.container, point) then
			if not allowEmptyLane then
				return true
			end

			for _, button in row.buttons do
				if inside(button, point) then
					return true
				end
			end
		end
	end

	return false
end

function Faces.unbind(rig)
	local row = rows[rig]
	if not row then
		return
	end

	if drag and drag.rigs[rig] then
		drag.cancel()
	end

	for _, c in row.connections do
		c:Disconnect()
	end

	for _, b in row.buttons do
		b:Destroy()
	end

	row.hit:Destroy()
	row.add:Destroy()
	rows[rig] = nil
	selection[rig] = nil
end

function Faces.refresh(timeline)
	for rig, row in rows do
		local track = Events.get(rig)
		local keys = track.FaceKeys or {}
		if row.item.disableButton then
			row.item.disableButton.ImageColor3 = track.FacesEnabled == true
					and Color3.fromRGB(113, 255, 61)
				or Color3.fromRGB(80, 80, 80)
		end

		for id, b in row.buttons do
			if not keys[id] then
				b:Destroy()
				row.buttons[id] = nil
			end
		end

		for id, key in keys do
			local b = row.buttons[id]
			if not b then
				b = Instance.new("ImageButton")
				b.Name = "Face_" .. id
				b.Image = Faces.ICON
				b.BackgroundTransparency = 1
				b.Size = UDim2.fromOffset(16, 16)
				b.AnchorPoint = Vector2.new(0.5, 0.5)
				b.AutoButtonColor = false
				b.Parent = row.container
				row.buttons[id] = b
				Faces.attach(b, true)
				b.InputBegan:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
						return
					end

					Faces.beginDrag(timeline, rig, id, Input:GetMouseLocation())
				end)
			end

			b.Position = UDim2.new(0, timeline:FrameToVisibleX(key.Frame), 0.5, 0)
			b.ZIndex = 10 + key.Frame
			b.ImageTransparency = track.FacesEnabled == true and 0 or 0.6
			b.ImageColor3 = Theme.get(
				isSelected(rig, id) and "KfS" or "KfD",
				Color3.new(1, 1, 1)
			)
			if key.Frame > timeline:GetMaxFrame() then
				timeline:EnsureTimelineEnd(key.Frame)
			end
		end
	end
end

function Faces.bind(timeline, item)
	local rig = item.grandpa.linkedRigInstance
	Faces.unbind(rig)
	local container = timeline:GetTrackKeyframesContainer(item.trackElement)
	if not container then
		return
	end

	local template = container:FindFirstChild("KeyframeTemplate")
	if template then
		template.Visible = false
	end

	local right = item.appearDetails.RightDiv
	local enabled = right:FindFirstChild("Disable")
	for _, button in right:GetChildren() do
		if button:IsA("GuiButton") then
			button.Visible = button == enabled
		end
	end

	local add = Instance.new("TextButton")
	add.Name = "AddFace"
	add.Text = "+"
	add.TextSize = 17
	add.Font = Enum.Font.GothamMedium
	add.TextColor3 = Theme.get("Txt", Color3.new(1, 1, 1))
	add.BackgroundTransparency = 1
	add.BorderSizePixel = 0
	add.Size = enabled and enabled.Size or UDim2.fromOffset(18, 18)
	add.LayoutOrder = -2
	add.Parent = right
	add:SetAttribute("ThemeTxt", "Txt")
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = add
	item.disableButton = enabled
	item.addFaceButton = add
	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.Name = "FaceHitbox"
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = container
	local row = {
		item = item,
		container = container,
		hit = hit,
		add = add,
		buttons = {},
		connections = {},
		lastClick = 0,
	}
	rows[rig] = row
	if enabled then
		table.insert(
			row.connections,
			enabled.MouseButton1Click:Connect(function()
				Faces.closeEditor()
				commit(timeline, rig, function()
					local track = Events.get(rig)
					track.FacesEnabled = track.FacesEnabled ~= true
				end, "Toggle faces")
			end)
		)
	end

	table.insert(
		row.connections,
		add.MouseButton1Click:Connect(function()
			local frame = timeline:TimeToFrame(timeline:GetState().CurrentTime)
			Faces.pick(timeline, rig, frame)
		end)
	)
	table.insert(
		row.connections,
		hit.MouseButton1Click:Connect(function()
			local now = os.clock()
			local frame = timeline:EventFrameAtPoint(Input:GetMouseLocation())
			if now - row.lastClick < 0.32 and frame == row.lastFrame then
				Faces.pick(timeline, rig, frame)
				row.lastClick = 0
			else
				row.lastClick = now
				row.lastFrame = frame
			end
		end)
	)
	Faces.refresh(timeline)
end

function Faces.clear()
	if drag then
		drag.cancel()
	end

	Faces.closeEditor()
	table.clear(selection)
	clipboard = nil
	for rig in originals do
		Faces.restore(rig)
	end

	for rig in rows do
		Faces.unbind(rig)
	end
end

function Faces.captureCopy()
	const result = {}
	for _, entry in selectedKeys() do
		table.insert(result, { rig = entry.rig, frame = entry.key.Frame, image = entry.key.Image })
	end

	return result
end

function Faces.setClipboard(entries, base)
	if not entries or #entries == 0 then
		clipboard = nil
		return
	end

	clipboard = {}
	for _, entry in entries do
		table.insert(clipboard, { rig = entry.rig, offset = entry.frame - base, image = entry.image })
	end
end

function Faces.install(timeline)
	local positions = timeline.RefreshAllTimelineKeyframePositions

	function timeline:RefreshAllTimelineKeyframePositions(...)
		local result = positions(self, ...)
		Faces.refresh(self)
		return result
	end

	local update = timeline.UpdateDeleteButtonState

	function timeline:UpdateDeleteButtonState(...)
		update(self, ...)
		local button = self:GetDeleteButton()
		if button and next(selection) then
			button.Visible = true
		end
	end

	for _, name in
		{
			"SetSelectedKeyframe",
			"SetSelectedKeyframes",
			"SetSelectedChannelKeyframe",
		}
	do
		local original = timeline[name]
		if original then
			timeline[name] = function(self, ...)
				table.clear(selection)
				local result = original(self, ...)
				Faces.refresh(self)
				return result
			end
		end
	end

	local clear = timeline.ClearSelectedKeyframes

	function timeline:ClearSelectedKeyframes(...)
		table.clear(selection)
		return clear(self, ...)
	end

	local selectAll = timeline.SelectAllKeyframes
	if selectAll then
		function timeline:SelectAllKeyframes(...)
			local result = selectAll(self, ...)
			for rig, track in Events.all() do
				if rows[rig] then
					for id in track.FaceKeys or {} do
						setSelected(rig, id, true)
					end
				end
			end

			Faces.refresh(self)
			self:UpdateDeleteButtonState()
			return result
		end
	end

	local boxBase = {}
	local beginBox = timeline.BeginKeyframeBoxSelection
	if beginBox then
		function timeline:BeginKeyframeBoxSelection(additive, ...)
			boxBase = additive and cloneSelection(selection) or {}
			local result = beginBox(self, additive, ...)
			selection = cloneSelection(boxBase)
			Faces.refresh(self)
			return result
		end
	end

	local boxSelect = timeline.SelectKeyframesInSelectionBox
	if boxSelect then
		function timeline:SelectKeyframesInSelectionBox(point, ...)
			local result = boxSelect(self, point, ...)
			const chosen = cloneSelection(boxBase)
			local minX, minY, maxX, maxY = self:GetSelectionBounds(point)
			const scale = self.refs and self.refs.Scale
			if minX and scale then
				const factor = Motion.scale(scale)
				for rig, row in rows do
					for id, button in row.buttons do
						const center = button.AbsolutePosition + button.AbsoluteSize * 0.5
						const p = (center - scale.AbsolutePosition) / factor
						if
							inside(button, center)
							and p.X >= minX
							and p.X <= maxX
							and p.Y >= minY
							and p.Y <= maxY
						then
							chosen[rig] = chosen[rig] or {}
							chosen[rig][id] = true
						end
					end
				end
			end

			selection = chosen
			Faces.refresh(self)
			self:UpdateDeleteButtonState()
			return result
		end
	end

	local has = timeline.HasAnySelectedKeyframes
	if has then
		function timeline:HasAnySelectedKeyframes(...)
			return next(selection) ~= nil or has(self, ...)
		end
	end

	local delete = timeline.DeleteSelectedKeyframes

	function timeline:DeleteSelectedKeyframes(...)
		if next(selection) == nil then
			return delete(self, ...)
		end

		local args = table.pack(...)
		return History.batch("Delete keys", function()
			deleteSelected(self)
			local result = delete(self, table.unpack(args, 1, args.n))
			self:UpdateDeleteButtonState()
			return result
		end)
	end

	local paste = timeline.PasteKeyframes

	function timeline:PasteKeyframes(reverse, ...)
		if not clipboard then
			return paste(self, reverse, ...)
		end

		const anchor = self:TimeToFrame(self:GetState().CurrentTime)
		local args = table.pack(...)
		return History.batch(reverse and "Paste reversed" or "Paste keys", function()
			local pasted = paste(self, reverse, table.unpack(args, 1, args.n))
			return pasteFaces(self, anchor, reverse) or pasted
		end)
	end

	local pasteFlipped = timeline.PasteKeyframesFlipped
	if pasteFlipped then
		function timeline:PasteKeyframesFlipped(...)
			if not clipboard then
				return pasteFlipped(self, ...)
			end

			const anchor = self:TimeToFrame(self:GetState().CurrentTime)
			local args = table.pack(...)
			return History.batch("Paste flipped", function()
				local pasted = pasteFlipped(self, table.unpack(args, 1, args.n))
				return pasteFaces(self, anchor, false) or pasted
			end)
		end
	end
end

function Faces.beginDrag(timeline, rig, id, point)
	if drag then
		drag.cancel()
	end

	local track = Events.get(rig)
	local key = (track.FaceKeys or {})[id]
	if not key then
		return
	end

	if refs and refs.Finalize then
		refs.Finalize()
	end

	Faces.closeEditor()
	if modified() then
		setSelected(rig, id, not isSelected(rig, id))
		timeline:UpdateDeleteButtonState()
		Faces.refresh(timeline)
		return
	end

	if not isSelected(rig, id) then
		timeline:ClearSelectedKeyframes()
		setSelected(rig, id, true)
	end

	timeline:UpdateDeleteButtonState()
	Faces.refresh(timeline)
	const moving = {}
	const rigs = {}
	local minimum = math.huge
	for _, entry in selectedKeys() do
		table.insert(moving, {
			rig = entry.rig,
			id = entry.id,
			key = entry.key,
			track = Events.get(entry.rig),
			frame = entry.key.Frame,
		})
		rigs[entry.rig] = true
		minimum = math.min(minimum, entry.key.Frame)
	end

	local offset = 0
	local changed = false
	local connections = {}

	local function place(value)
		for _, item in moving do
			item.key.Frame = item.frame + value
			faceIndexes[item.track] = nil
		end

		Faces.refresh(timeline)
	end

	local function stop()
		for _, connection in connections do
			connection:Disconnect()
		end

		drag = nil
		place(0)
	end

	drag = { rigs = rigs, cancel = stop }
	table.insert(
		connections,
		Input.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end

			local now = Input:GetMouseLocation()
			if not changed and (now - point).Magnitude < 3 then
				return
			end

			local width = timeline:GetVisibleTimelineWidth()
			local scale = timeline.refs.Scale.AbsoluteSize.X / math.max(1, width + 40)
			offset = math.max(
				-minimum,
				math.floor(
					(now.X - point.X) / math.max(1, width * scale) * timeline:GetMaxFrame() + 0.5
				)
			)
			changed = true
			place(offset)
		end)
	)
	table.insert(
		connections,
		Input.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			stop()
			if changed then
				if offset ~= 0 then
					Faces.move(timeline, moving, offset)
				end
			else
				if #moving > 1 then
					timeline:ClearSelectedKeyframes()
					setSelected(rig, id, true)
					timeline:UpdateDeleteButtonState()
					Faces.refresh(timeline)
				end

				Faces.open(timeline, rig, id)
			end
		end)
	)
	table.insert(connections, Input.WindowFocusReleased:Connect(stop))
end

function Faces.init(options)
	refs = options
	local connection = Input.InputBegan:Connect(function(input, processed)
		if processed or not refs.Active() or Input:GetFocusedTextBox() then
			return
		end

		if drag and Shortcuts.matches("Cancel", input) then
			drag.cancel()
			return
		end

		if next(selection) and Shortcuts.matches("DeleteKeys", input) then
			refs.State.Timeline:DeleteSelectedKeyframes()
		end
	end)

	local function close()
		connection:Disconnect()
		Faces.clear()
	end

	options.ScreenGui.Destroying:Once(close)
	options.Plugin.Unloading:Once(close)
end

return Faces
