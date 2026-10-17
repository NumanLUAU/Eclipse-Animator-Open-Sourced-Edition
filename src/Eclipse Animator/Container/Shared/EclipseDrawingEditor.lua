--// cracked by numan

local Drawing = require(script.Parent.EclipseDrawing)
local Editor = {}

function Editor.new(deps)
	local refs, Tool, History, Picker, Path =
		deps.refs, deps.Tool, deps.History, deps.Picker, deps.Path
	local Input = game:GetService("UserInputService")
	local Http = game:GetService("HttpService")
	local self = {
		brush = Drawing.style(),
		mode = "Select",
		shape = "Brush",
		depth = 12,
		smoothing = 35,
		duration = 12,
		onion = false,
		visible = false,
		advanced = false,
		layer = nil,
		selected = nil,
		stop = 1,
		connections = {},
		revision = 0,
	}
	self.brush.stops[2].color = self.brush.stops[1].color
	self.brush.gradient = "Linear"

	local function raw()
		return refs.State.Timeline:GetState()
	end

	local emptyDocument = Drawing.empty()

	local function get()
		return raw().GreaseDrawings or emptyDocument
	end

	local function frame()
		return math.max(0, math.round(raw().CurrentTime * raw().FPS))
	end

	local function editable()
		assert(
			refs.Active()
				and not raw().Exporting
				and not raw().Playing
				and not refs.State.PhysicsSimulating,
			"Pause playback or simulation before editing drawings"
		)
	end

	local function layerOf(doc)
		for _, layer in doc.layers do
			if layer.id == self.layer then
				return layer
			end
		end

		return doc.layers[1]
	end

	local function ensure(doc)
		local layer = layerOf(doc)
		if not layer then
			layer = {
				id = Http:GenerateGUID(false),
				name = "Layer 1",
				visible = true,
				locked = false,
				opacity = 1,
				keys = {},
			}
			table.insert(doc.layers, layer)
		end

		self.layer = layer.id
		assert(not layer.locked, "Unlock this drawing layer first")
		return layer
	end

	local function current(layer, create)
		local at = frame()
		for _, key in layer.keys do
			if key.frame == at then
				return key
			end
		end

		if not create then
			return Drawing.keyAt(layer, at)
		end

		local key = { frame = at, duration = self.duration, strokes = {} }
		table.insert(layer.keys, key)
		table.sort(layer.keys, function(a, b)
			return a.frame < b.frame
		end)
		return key
	end

	function self:status(message)
		self.message = tostring(message):gsub("^.-:%d+: ", "")
		if self.statusLabel then
			self.statusLabel.Text = self.message
		end
	end

	function self:run(callback)
		local ok, err = xpcall(callback, debug.traceback)
		if not ok then
			self:cancel()
			self:status(tostring(err):match("^[^\n]+") or err)
			if deps.notify then
				deps.notify(self.message)
			end
		end

		return ok
	end

	function self:commit(label, mutate)
		editable()
		local state = raw()
		local before = Drawing.copy(get())
		local after = Drawing.copy(before)
		mutate(after)
		Drawing.validate(after)

		local function restore(value)
			if raw() ~= state then
				return
			end

			state.GreaseDrawings = Drawing.copy(value)
			refs.State.currentProjectSaved = false
			refs.State.Timeline._playbackEndAt = nil
			self.revision += 1
			self:refresh()
			self:step()
		end

		restore(after)
		History.record(function()
			restore(before)
		end, function()
			restore(after)
		end, label)
	end

	function self:addLayer()
		self:commit("Add drawing layer", function(doc)
			self.layer = Http:GenerateGUID(false)
			table.insert(doc.layers, {
				id = self.layer,
				name = "Layer " .. (#doc.layers + 1),
				visible = true,
				locked = false,
				opacity = 1,
				keys = {},
			})
		end)
	end

	function self:newKey(duplicate)
		self:commit(duplicate and "Duplicate drawing" or "Add blank drawing", function(doc)
			local layer = ensure(doc)
			for _, key in layer.keys do
				assert(key.frame ~= frame(), "A drawing already starts at this frame")
			end

			local previous = Drawing.keyAt(layer, frame())
			if duplicate and not previous then
				for _, key in layer.keys do
					if key.frame < frame() then
						previous = key
					end
				end
			end

			local key = current(layer, true)
			if duplicate and previous then
				key.strokes = Drawing.copy(previous.strokes)
				for _, stroke in key.strokes do
					stroke.id = Http:GenerateGUID(false)
				end
			end
		end)
	end

	function self:deleteKey()
		self:commit("Delete drawing", function(doc)
			local layer = ensure(doc)
			local key = current(layer, false)
			assert(key, "No drawing at the playhead")
			table.remove(layer.keys, table.find(layer.keys, key))
		end)
	end

	function self:seek(at)
		editable()
		self:cancel()
		raw().CurrentTime = at / raw().FPS
		refs.State.Timeline:UpdatePlayhead()
		self:refresh()
		self:step()
	end

	function self:applyBrush(all)
		self:commit("Change drawing brush", function(doc)
			local key = current(ensure(doc), false)
			assert(key, "Select a drawing first")
			local found = false
			for _, stroke in key.strokes do
				if all or stroke.id == self.selected then
					local space = stroke.style.space
					stroke.style = Drawing.copy(self.brush)
					stroke.style.space = space
					found = true
				end
			end

			assert(found, "Select a stroke in the viewport first")
		end)
	end

	function self:cancel()
		self.pending = nil
		if self.releaseCamera then
			self.releaseCamera()
			self.releaseCamera, self.holdCamera = nil, nil
		end
		if self.preview then
			self.preview:destroy()
			self.preview = nil
		end
	end

	function self:setVisible(visible)
		self.visible = visible
		self:cancel()
		if not visible then
			self.mode = "Select"
			if
				self.colorAnchor and Picker.isOpen(self.colorAnchor)
				or self.stopColorAnchor and Picker.isOpen(self.stopColorAnchor)
			then
				Picker.close(true)
			end
		end

		if self.panel then
			self.panel.Visible = visible
		end

		self:refresh()
	end

	function self:isDrawing()
		return self.visible or self.pending ~= nil
	end

	local function mousePoint()
		return Input:GetMouseLocation()
	end

	local function worldPoint(camera, point, origin, normal)
		return Path.intersect(camera:ScreenPointToRay(point.X, point.Y), origin, normal)
	end

	function self:pick(point)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local layer = layerOf(get())
		if not layer or not layer.visible then
			return
		end

		local key = current(layer, false)
		if not key then
			return
		end

		local best, distance = nil, 14
		for _, stroke in key.strokes do
			for i = 2, #stroke.points do
				local cf = stroke.style.space == "Camera" and camera.CFrame or CFrame.identity
				local a = camera:WorldToScreenPoint(cf:PointToWorldSpace(stroke.points[i - 1]))
				local b = camera:WorldToScreenPoint(cf:PointToWorldSpace(stroke.points[i]))
				if a.Z <= 0 or b.Z <= 0 then
					continue
				end

				local av, bv = Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y)
				local delta = bv - av
				local t = delta:Dot(delta) > 1e-8
						and math.clamp((point - av):Dot(delta) / delta:Dot(delta), 0, 1)
					or 0
				local d = (point - av - delta * t).Magnitude
				if d < distance then
					distance = d
					best = stroke
				end
			end
		end

		return best
	end

	function self:begin(point)
		if
			not self.visible
			or not refs.Active()
			or raw().Playing
			or raw().Exporting
			or Input:GetFocusedTextBox()
			or Picker.isOpen()
		then
			return
		end

		point = point or mousePoint()
		if deps.overUI(point) then
			return
		end

		self:run(function()
			editable()
			self:cancel()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end

			local layer = layerOf(get())
			assert(not layer or not layer.locked, "Unlock this drawing layer first")
			assert(not layer or layer.visible, "Show this drawing layer before editing it")
			local picked = self:pick(point)
			if self.mode == "Erase" then
				if picked then
					self:commit("Erase drawing stroke", function(doc)
						local key = current(ensure(doc), false)
						for i, stroke in key.strokes do
							if stroke.id == picked.id then
								table.remove(key.strokes, i)
								break
							end
						end
					end)
				end

				return
			end

			local cameraFrame = camera.CFrame
			if self.mode == "Select" then
				self.selected = picked and picked.id or nil
				if picked then
					self.brush = Drawing.copy(picked.style)
					self.stop = 1
					local cf = picked.style.space == "Camera" and cameraFrame or CFrame.identity
					local origin = cf:PointToWorldSpace(picked.points[1])
					local hit = worldPoint(camera, point, origin, cameraFrame.LookVector)
					if hit then
						self.pending = {
							kind = "Move",
							camera = camera,
							view = cameraFrame,
							origin = origin,
							normal = cameraFrame.LookVector,
							start = hit,
							last = point,
							original = picked,
							points = Drawing.copy(picked.points),
							at = frame(),
							state = raw(),
							document = get(),
						}
						self.releaseCamera, self.holdCamera = deps.lockCamera(camera)
					end

					self:status(
						"Stroke selected. Drag to move; change the brush, then Apply to stroke."
					)
				end

				self:refresh()
				return
			end

			local origin = cameraFrame.Position + cameraFrame.LookVector * self.depth
			local hit = worldPoint(camera, point, origin, cameraFrame.LookVector)
			if not hit then
				return
			end

			self.pending = {
				kind = "Draw",
				camera = camera,
				view = cameraFrame,
				origin = origin,
				normal = cameraFrame.LookVector,
				start = hit,
				points = { hit },
				last = point,
				at = frame(),
				state = raw(),
				document = get(),
				style = Drawing.copy(self.brush),
			}
			self.releaseCamera, self.holdCamera = deps.lockCamera(camera)
		end)
	end

	function self:move(point)
		if self.holdCamera then
			self.holdCamera()
		end
		local p = self.pending
		if not p then
			return
		end

		if
			raw() ~= p.state
			or get() ~= p.document
			or frame() ~= p.at
			or workspace.CurrentCamera ~= p.camera
			or raw().Playing
			or raw().Exporting
			or p.camera.CFrame ~= p.view
		then
			self:cancel()
			return
		end

		point = point or mousePoint()
		if (point - p.last).Magnitude < 2 then
			return
		end

		local hit = worldPoint(p.camera, point, p.origin, p.normal)
		if not hit then
			return
		end

		if p.kind == "Move" then
			local delta = hit - p.start
			if p.original.style.space == "Camera" then
				delta = p.view:VectorToObjectSpace(delta)
			end

			for i, v in p.original.points do
				p.points[i] = v + delta
			end
		elseif self.shape == "Line" then
			p.points = { p.start, hit }
		elseif self.shape == "Circle" then
			local radius = (hit - p.start).Magnitude
			p.points = {}
			for i = 0, 64 do
				local a = i / 64 * math.pi * 2
				table.insert(
					p.points,
					p.start
						+ (p.view.RightVector * math.cos(a) + p.view.UpVector * math.sin(a))
							* radius
				)
			end
		else
			if #p.points >= 512 then
				p.points = Path.resample(p.points, 256)
			end

			table.insert(p.points, hit)
		end

		p.last = point
		p.moved = true
		self.previewDirty = true
	end

	function self:previewStroke()
		local p = self.pending
		if not p or #p.points < 2 then
			return
		end

		if not self.preview then
			self.preview = Drawing.new(workspace.CurrentCamera)
		end

		local style = Drawing.copy(p.style or p.original.style)
		if p.kind == "Draw" then
			style.space = "World"
		end

		style.reveal = 0
		style.fadeIn = 0
		style.fadeOut = 0
		self.preview:step({
			layers = {
				{
					id = "preview",
					visible = true,
					opacity = 0.85,
					keys = {
						{
							frame = 0,
							duration = 1,
							strokes = { { id = "preview", points = p.points, style = style } },
						},
					},
				},
			},
		}, 0, p.view, true)
	end

	function self:finish()
		if self.holdCamera then
			self.holdCamera()
		end
		local p = self.pending
		if not p then
			return
		end

		self:cancel()
		if
			raw() ~= p.state
			or get() ~= p.document
			or frame() ~= p.at
			or workspace.CurrentCamera ~= p.camera
			or p.camera.CFrame ~= p.view
			or not p.moved
			or #p.points < 2
		then
			return
		end

		self:run(function()
			self:commit(
				p.kind == "Move" and "Move drawing stroke" or "Draw Grease Pencil stroke",
				function(doc)
					local layer = ensure(doc)
					if p.kind == "Move" then
						local key = current(layer, false)
						assert(key, "Drawing changed while dragging")
						for _, s in key.strokes do
							if s.id == p.original.id then
								s.points = p.points
								return
							end
						end

						error("Stroke changed while dragging")
					end

					local points = self.shape == "Brush" and Path.smooth(p.points, self.smoothing)
						or p.points
					if p.style.space == "Camera" then
						for i, v in points do
							points[i] = p.view:PointToObjectSpace(v)
						end
					end

					local key = current(layer, true)
					self.selected = Http:GenerateGUID(false)
					table.insert(key.strokes, {
						id = self.selected,
						points = points,
						style = p.style,
						plane = p.style.space == "Camera" and CFrame.identity or p.view,
					})
				end
			)
			self:status("Drawing saved in the project. It will appear in cutscene exports.")
		end)
	end

	function self:step()
		if self.previewDirty then
			self.previewDirty = false
			self:previewStroke()
		end

		if self.destroyed then
			return
		end

		local camera = workspace.CurrentCamera
		local enabled = refs.Active()
			and refs.ScreenGui.Enabled
			and refs.AnimatorFrame.Visible
			and not raw().Exporting
		if not camera or not enabled then
			if self.renderer then
				self.renderer:destroy()
				self.renderer = nil
			end

			self:cancel()
			return
		end

		if self.renderer and self.renderer.root.Parent ~= camera then
			self.renderer:destroy()
			self.renderer = nil
		end

		if not self.renderer then
			self.renderer = Drawing.new(camera)
		end

		self.renderer:step(
			get(),
			raw().CurrentTime * raw().FPS,
			camera.CFrame,
			true,
			self.visible and self.onion and not raw().Playing and self.layer or nil
		)
		if self.lastFrame ~= frame() or self.lastDocument ~= get() then
			self.lastDocument = get()
			self.lastFrame = frame()
			if self.visible then
				self:refresh()
			end
		end
	end

	function self:refresh()
		if not self.panel then
			return
		end

		local layer = layerOf(get())
		self.layer = layer and layer.id or nil
		local key = layer and current(layer, false)

		local function set(name, value)
			local v = self.fields and self.fields[name]
			if v and not v:IsFocused() then
				v.Text = tostring(value)
			end
		end

		set("LayerName", layer and layer.name or "Layer 1")
		set("LayerOpacity", layer and math.round(layer.opacity * 100) or 100)
		set("Duration", key and key.duration or self.duration)
		set("StartFrame", key and key.frame or frame())
		set("Width", self.brush.width)
		set("Opacity", math.round(self.brush.opacity * 100))
		set("Depth", self.depth)
		set("Smooth", self.smoothing)
		set("TaperStart", math.round(self.brush.taperStart * 100))
		set("TaperEnd", math.round(self.brush.taperEnd * 100))
		set("Angle", self.brush.angle)
		set("Reveal", self.brush.reveal)
		set("FadeIn", self.brush.fadeIn)
		set("FadeOut", self.brush.fadeOut)
		self.stop = math.clamp(self.stop, 1, #self.brush.stops)
		local stop = self.brush.stops[self.stop]
		set("StopPosition", math.round(stop.at * 1000) / 10)
		set("StopOpacity", math.round(stop.alpha * 100))
		for _, m in { "Select", "Draw", "Erase" } do
			if self.labels[m] then
				self.labels[m].TextTransparency = self.mode == m and 0 or 0.5
			end
		end

		self.labels.Shape.Text = self.shape:upper()
		self.labels.Space.Text = self.brush.space:upper()

		self.labels.Onion.Text = self.onion and "ONION ON" or "ONION OFF"
		self.labels.Visibility.Text = layer and not layer.visible and "HIDDEN" or "VISIBLE"
		self.labels.Lock.Text = layer and layer.locked and "LOCKED" or "UNLOCKED"

		self.playhead.Text = "FRAME "
			.. frame()
			.. "  ·  "
			.. (key and #key.strokes .. " strokes" or "No drawing")
		local colors, alphas = {}, {}
		for _, s in self.brush.stops do
			table.insert(colors, ColorSequenceKeypoint.new(s.at, s.color))
			table.insert(alphas, NumberSequenceKeypoint.new(s.at, 1 - s.alpha))
		end

		if colors[1].Time > 0 then
			table.insert(colors, 1, ColorSequenceKeypoint.new(0, colors[1].Value))
			table.insert(alphas, 1, NumberSequenceKeypoint.new(0, alphas[1].Value))
		end

		if colors[#colors].Time < 1 then
			table.insert(colors, ColorSequenceKeypoint.new(1, colors[#colors].Value))
			table.insert(alphas, NumberSequenceKeypoint.new(1, alphas[#alphas].Value))
		end

		self.gradient.Color = ColorSequence.new(colors)
		self.gradient.Transparency = NumberSequence.new(alphas)
		if self.exposureDocument ~= get() then
			self.exposureDocument = get()
			self.drawingRows = {}
			for _, child in self.exposures:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end

			local rows = {}
			for _, l in get().layers do
				for _, k in l.keys do
					table.insert(rows, { layer = l, key = k })
				end
			end

			table.sort(rows, function(a, b)
				if a.key.frame == b.key.frame then
					return a.layer.name < b.layer.name
				end

				return a.key.frame < b.key.frame
			end)
			for i, row in rows do
				local title = (#row.key.strokes == 0 and "Blank " or "Drawing ")
					.. i
					.. "    Frame "
					.. row.key.frame
				local _, label = Tool.button(
					self.exposures,
					"Drawing" .. i,
					title,
					UDim2.fromOffset(2, (i - 1) * 28 + 2),
					UDim2.new(1, -8, 0, 26),

					function()
						self:run(function()
							self.layer = row.layer.id
							self:seek(row.key.frame)
							self:refresh()
						end)
					end
				)
				label.TextSize = 11
				table.insert(
					self.drawingRows,
					{ label = label, title = title, layer = row.layer, key = row.key }
				)
			end

			self.exposures.CanvasSize = UDim2.fromOffset(0, #rows * 28 + 4)
		end

		for _, row in self.drawingRows or {} do
			row.label.Text = (row.layer == layer and row.key == key and "● " or "   ")
				.. row.title
		end
	end

	function self:layout()
		if not self.panel then
			return
		end

		local panel = self.panel
		for _, object in panel:GetChildren() do
			if object:IsA("GuiObject") then
				object.Visible = false
			end
		end

		local function place(name, x, y, width, height)
			local object = assert(panel:FindFirstChild(name), name)
			object.Visible = true
			object.Position = UDim2.fromOffset(x, y >= 450 and y - 36 or y)
			object.Size = UDim2.fromOffset(width, height)
		end

		local function field(name, title, x, y, width)
			panel[name .. "Label"].Text = title
			place(name .. "Label", x, y, width, 18)
			place(name, x, y + 20, width, 25)
		end

		place("ModeTabs", 12, 0, 388, 28)
		for _, name in { "Simple", "Advanced" } do
			local active = (name == "Advanced") == self.advanced
			panel.ModeTabs[name]:SetAttribute("ThemeBgTransparency", active and 0 or 1)
			panel.ModeTabs[name]:SetAttribute("Primary", active)
			panel.ModeTabs[name].TextLabel:SetAttribute(
				"ThemeTxtTransparency",
				active and 0 or 0.35
			)
			panel.ModeTabs[name].BackgroundTransparency = active and 0 or 1
			panel.ModeTabs[name].TextLabel.TextTransparency = active and 0 or 0.35
		end

		for i, name in { "Select", "Draw", "Erase", "Shape" } do
			place(name, 12 + (i - 1) * 99, 34, 91, 26)
		end

		field("Width", "Brush width", 12, 72, 190)
		field("Opacity", "Opacity %", 210, 72, 190)
		place("GradientPreview", 12, 126, 388, 16)
		place("Playhead", 12, 148, 250, 22)
		place("Onion", 276, 148, 124, 24)
		place("DrawingFrames", 12, 180, 388, 96)
		place("Blank", 12, 284, 124, 26)
		place("Duplicate", 144, 284, 124, 26)
		place("DeleteDrawing", 276, 284, 124, 26)
		field("StartFrame", "Start frame", 12, 322, 124)
		field("Duration", "Duration (frames)", 144, 322, 124)
		place("Space", 276, 342, 124, 25)
		place("ApplyStroke", 12, 378, 190, 26)
		place("ApplyDrawing", 210, 378, 190, 26)
		local height = 414
		if self.advanced then
			place("LayersHeading", 12, 460, 220, 22)
			place("PreviousLayer", 292, 460, 30, 26)
			place("NextLayer", 328, 460, 30, 26)
			place("AddLayer", 364, 460, 36, 26)
			place("LayerName", 12, 494, 250, 25)
			place("DeleteLayer", 270, 494, 130, 25)
			place("Visibility", 12, 532, 100, 26)
			place("Lock", 120, 532, 116, 26)
			field("LayerOpacity", "Layer opacity %", 248, 526, 152)
			field("Depth", "Drawing depth", 12, 582, 124)
			field("Smooth", "Smoothing %", 144, 582, 124)
			field("TaperStart", "Start taper %", 12, 642, 190)
			field("TaperEnd", "End taper %", 210, 642, 190)
			field("Reveal", "Draw-on (frames)", 12, 702, 124)
			field("FadeIn", "Fade in (frames)", 144, 702, 124)
			field("FadeOut", "Fade out (frames)", 276, 702, 124)
			place("FitTimeline", 12, 760, 388, 26)
			height = 762
		end

		panel.CanvasSize = UDim2.fromOffset(0, height)
		panel.CanvasPosition = Vector2.zero
		if self.onLayout then
			self.onLayout()
		end
	end

	function self:mount(parent)
		self:unmount()
		self.panel = Tool.make("ScrollingFrame", parent, "GreasePencil", {
			Position = UDim2.fromOffset(0, 68),
			Size = UDim2.new(1, 0, 1, -68),
			CanvasSize = UDim2.fromOffset(0, 928),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			Visible = self.visible,
		})
		local panel = self.panel
		self.fields = {}
		self.labels = {}

		local function label(name, title, x, y, w, h)
			return Tool.label(
				panel,
				name,
				title,
				UDim2.fromOffset(x, y),
				UDim2.fromOffset(w, h or 22)
			)
		end

		local function button(name, title, x, y, w, fn)
			local b, l = Tool.button(
				panel,
				name,
				title,
				UDim2.fromOffset(x, y),
				UDim2.fromOffset(w, 26),

				function()
					self:run(fn)
					self:refresh()
				end
			)
			self.labels[name] = l
			return b
		end

		local function field(name, title, x, y, w, value, low, high, fn, integer)
			label(name .. "Label", title, x, y, w, 18)
			local box = Tool.field(
				panel,
				name,
				value,
				UDim2.fromOffset(x, y + 20),
				UDim2.fromOffset(w, 25),
				{
					min = low,
					max = high,
					step = integer and 1 or (high == 100 and 1 or 0.1),
					integer = integer,
				}
			)
			self.fields[name] = box
			table.insert(
				self.connections,
				box.FocusLost:Connect(function()
					self:run(function()
						local n = tonumber(box.Text)
						assert(
							n and n == n and n >= low and n <= high,
							"Enter " .. low .. "–" .. high .. " for " .. title
						)
						if integer then
							n = math.round(n)
						end

						fn(n)
					end)
					self:refresh()
				end)
			)
			return box
		end

		local function cycle(list, value)
			return list[(table.find(list, value) or 0) % #list + 1]
		end

		local modes = Tool.make(
			"Frame",
			panel,
			"ModeTabs",
			{ BackgroundTransparency = 0.5, BorderSizePixel = 0 }
		)
		modes:SetAttribute("ThemeBg", "Top")
		modes:SetAttribute("EclipseTabBar", true)
		Tool.make("UICorner", modes, "Corner", { CornerRadius = UDim.new(0, 5) })
		local outline = Tool.make("UIStroke", modes, "Outline", { Thickness = 1 })
		outline:SetAttribute("ThemeStrk", "Strk")
		for i, name in { "Simple", "Advanced" } do
			Tool.button(
				modes,
				name,
				name:upper(),
				UDim2.fromOffset(3 + (i - 1) * 191, 3),
				UDim2.fromOffset(191, 22),

				function()
					self.advanced = name == "Advanced"
					self:layout()
				end
			)
		end

		for i, mode in { "Select", "Draw", "Erase" } do
			button(mode, mode:upper(), 12 + (i - 1) * 92, 32, 84, function()
				self:cancel()
				editable()
				self.mode = mode
				self:status(
					mode == "Draw" and "Drag in the viewport. Escape returns to Select."
						or mode == "Erase" and "Click a stroke to erase. Undo restores it."
						or "Click a stroke, then drag to move it."
				)
			end)
		end

		button("Shape", "BRUSH", 288, 32, 112, function()
			self.shape = cycle({ "Brush", "Line", "Circle" }, self.shape)
		end)
		button("Onion", "ONION OFF", 154, 68, 128, function()
			self.onion = not self.onion
		end)
		label("LayersHeading", "LAYERS", 12, 70, 180)
		button("PreviousLayer", "‹", 292, 68, 30, function()
			local ls = get().layers
			local l = layerOf(get())
			if l then
				self.layer = ls[(table.find(ls, l) - 2) % #ls + 1].id
			end
		end)
		button("NextLayer", "›", 328, 68, 30, function()
			local ls = get().layers
			local l = layerOf(get())
			if l then
				self.layer = ls[table.find(ls, l) % #ls + 1].id
			end
		end)
		button("AddLayer", "+", 364, 68, 36, function()
			self:addLayer()
		end)
		local name = Tool.field(
			panel,
			"LayerName",
			"Layer 1",
			UDim2.fromOffset(12, 100),
			UDim2.fromOffset(250, 25)
		)
		self.fields.LayerName = name
		table.insert(
			self.connections,
			name.FocusLost:Connect(function()
				self:run(function()
					self:commit("Rename drawing layer", function(doc)
						local l = ensure(doc)
						l.name = name.Text
					end)
				end)
				self:refresh()
			end)
		)
		button("DeleteLayer", "DELETE LAYER", 270, 100, 130, function()
			self:commit("Delete drawing layer", function(doc)
				local l = ensure(doc)
				table.remove(doc.layers, table.find(doc.layers, l))
			end)
		end)
		button("Visibility", "VISIBLE", 12, 134, 100, function()
			self:commit("Toggle drawing visibility", function(doc)
				local l = layerOf(doc)
				assert(l, "Add a layer first")
				l.visible = not l.visible
			end)
		end)
		button("Lock", "UNLOCKED", 120, 134, 116, function()
			self:commit("Toggle drawing lock", function(doc)
				local l = layerOf(doc)
				assert(l, "Add a layer first")
				l.locked = not l.locked
			end)
		end)
		field("LayerOpacity", "Layer opacity %", 248, 132, 152, 100, 0, 100, function(n)
			self:commit("Drawing layer opacity", function(doc)
				ensure(doc).opacity = n / 100
			end)
		end)
		self.playhead = label("Playhead", "", 12, 184, 388)
		self.exposures = Tool.make("ScrollingFrame", panel, "DrawingFrames", {
			Position = UDim2.fromOffset(12, 212),
			Size = UDim2.fromOffset(388, 34),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 3,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		})
		self.exposures:SetAttribute("ThemeBg", "Top")
		local drawingBorder = Tool.make("UIStroke", self.exposures, "Outline", { Thickness = 1 })
		drawingBorder:SetAttribute("ThemeStrk", "Strk")
		button("Blank", "+ BLANK", 12, 254, 124, function()
			self:newKey(false)
		end)
		button("Duplicate", "DUPLICATE", 144, 254, 124, function()
			self:newKey(true)
		end)
		button("DeleteDrawing", "DELETE DRAWING", 276, 254, 124, function()
			self:deleteKey()
		end)
		field("StartFrame", "Start frame", 12, 290, 124, 0, 0, 1000000, function(n)
			self:commit("Move drawing frame", function(doc)
				local l = ensure(doc)
				local k = current(l, false)
				assert(k, "No drawing selected")
				k.frame = n
				table.sort(l.keys, function(a, b)
					return a.frame < b.frame
				end)
			end)
			self:seek(n)
		end, true)
		field("Duration", "Duration (frames)", 144, 290, 124, 12, 1, 1000000, function(n)
			self.duration = n
			local l = layerOf(get())
			if l and current(l, false) then
				self:commit("Drawing duration", function(doc)
					current(ensure(doc), false).duration = n
				end)
			end
		end, true)
		button("Space", "WORLD", 276, 310, 124, function()
			self.brush.space = cycle({ "World", "Camera" }, self.brush.space)
			self:status(
				"Placement affects new strokes. Camera drawings follow the cutscene camera."
			)
		end)
		field("Depth", "Drawing depth", 12, 348, 124, self.depth, 0.1, 10000, function(n)
			self.depth = n
		end)
		field("Width", "Width (studs)", 144, 348, 124, self.brush.width, 0.001, 100, function(n)
			self.brush.width = n
		end)
		field("Opacity", "Opacity %", 276, 348, 124, 100, 0, 100, function(n)
			self.brush.opacity = n / 100
		end)
		field("Smooth", "Smoothing %", 12, 404, 124, 35, 0, 100, function(n)
			self.smoothing = n
		end)
		field("TaperStart", "Start taper %", 144, 404, 124, 0, 0, 100, function(n)
			self.brush.taperStart = n / 100
		end)
		field("TaperEnd", "End taper %", 276, 404, 124, 0, 0, 100, function(n)
			self.brush.taperEnd = n / 100
		end)
		local ramp = Tool.make("TextButton", panel, "GradientPreview", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		})
		self.gradient = Tool.make("UIGradient", ramp, "Gradient", {})
		self.colorAnchor = ramp
		table.insert(
			self.connections,
			ramp.Activated:Connect(function()
				local brush = self.brush
				local value = {
					stops = {},
					positions = {},
					alphas = {},
					rot = brush.angle,
					mode = brush.gradient,
				}
				for _, stop in brush.stops do
					table.insert(value.stops, stop.color)
					table.insert(value.positions, stop.at)
					table.insert(value.alphas, stop.alpha)
				end

				if
					#value.stops == 2
					and value.stops[1] == value.stops[2]
					and value.alphas[1] == value.alphas[2]
				then
					value.stops = { value.stops[1] }
					value.positions = { 0 }
					value.alphas = { value.alphas[1] }
				end

				Picker.open(refs, ramp, value, function(result)
					if self.brush ~= brush then
						return
					end

					local stops = {}
					for i, c in result.stops do
						table.insert(
							stops,
							{ at = result.positions[i], color = c, alpha = result.alphas[i] }
						)
					end

					if #stops == 1 then
						table.insert(
							stops,
							{ at = 1, color = stops[1].color, alpha = stops[1].alpha }
						)
					end

					brush.stops = stops
					brush.angle = result.rot or 0
					brush.gradient = result.mode or "Path"
					self.stop = 1
					self:refresh()
				end, {
					drawing = true,
					commitOnDone = true,
					alive = function()
						return self.visible and self.panel ~= nil and self.brush == brush
					end,
				})
			end)
		)
		field("Reveal", "Draw-on (frames)", 12, 648, 124, 0, 0, 1000000, function(n)
			self.brush.reveal = n
		end, true)
		field("FadeIn", "Fade in (frames)", 144, 648, 124, 0, 0, 1000000, function(n)
			self.brush.fadeIn = n
		end, true)
		field("FadeOut", "Fade out (frames)", 276, 648, 124, 0, 0, 1000000, function(n)
			self.brush.fadeOut = n
		end, true)
		button("ApplyStroke", "APPLY TO STROKE", 12, 708, 190, function()
			self:applyBrush(false)
		end)
		button("ApplyDrawing", "APPLY TO DRAWING", 210, 708, 190, function()
			self:applyBrush(true)
		end)
		button("FitTimeline", "FIT TIMELINE TO CONTENT", 12, 784, 388, function()
			if refs.State.Timeline.FitTimeline then
				refs.State.Timeline:FitTimeline()
			end
		end)
		self.statusLabel = label(
			"Status",
			self.message or "Choose Draw, then drag in the viewport. All edits support Undo.",
			12,
			824,
			388,
			48
		)

		self:refresh()
		self:layout()
	end

	function self:unmount()
		self.onLayout = nil
		self:cancel()
		if
			self.colorAnchor and Picker.isOpen(self.colorAnchor)
			or self.stopColorAnchor and Picker.isOpen(self.stopColorAnchor)
		then
			Picker.close(true)
		end

		for _, c in self.connections do
			c:Disconnect()
		end

		table.clear(self.connections)
		if self.panel then
			self.panel:Destroy()
			self.panel = nil
		end

		self.exposureDocument = nil
		self.drawingRows = nil
		self.exposureLayer = nil
		self.exposureKey = nil
		self.fields = nil
		self.labels = nil
		self.statusLabel = nil
		self.colorAnchor = nil
	end

	function self:destroy()
		self.destroyed = true
		self:unmount()
		if self.renderer then
			self.renderer:destroy()
			self.renderer = nil
		end
	end

	return self
end

return Editor
