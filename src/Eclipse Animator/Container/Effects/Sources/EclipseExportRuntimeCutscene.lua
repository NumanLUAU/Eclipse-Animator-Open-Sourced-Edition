--!nocheck
--// cracked by numan

return function(require)
	local Player = require("@self/Runtime/Player")
	local Subtitle = require("@self/Helpers/SubtitleData")
	local Eclipse = {}

	local function subtitle(row, index)
		local base = table.clone(row.Style or {})

		base.Text = row.Text
		base.Speaker = row.Speaker

		local keys = {}
		for i, key in row.Keys or {} do
			local value = table.clone(key.Value or {})
			if value.Text == nil then value.Text = row.Text end
			if value.Speaker == nil then value.Speaker = row.Speaker end
			keys[i] = { Frame = key.Frame, Ease = key.Ease, Value = value }
		end

		local cue = Subtitle.copy({
			Duration = row.Duration,
			Base = base,
			Keys = keys,
			Entrance = row.Entrance,
			Exit = row.Exit,
			InFrames = row.InFrames,
			OutFrames = row.OutFrames,
			Order = row.Order,
			Preset = row.Preset,
		})

		return {
			id = `Subtitle{index}`,
			order = index,
			event = { Frame = row.Frame, Subtitle = cue },
		}
	end

	local function event(row, index, rigs, factories)
		local id = `Event{index}`
		local data = table.clone(row.Data or {})

		data.Id = id
		data.Name = row.Name or id
		data.Frame = row.Frame
		data.Duration = row.Duration or 0
		data.Speed = row.Speed or 1
		data.Parameter = row.Parameter or ""
		data.Sounds = row.Sounds or {}
		data.Markers = row.Markers or {}
		data.Enabled = true

		local entry = {
			Id = id,
			Rig = row.Rig and rigs[row.Rig],
			Frame = row.Frame,
			Speed = data.Speed,
			Data = data,
			Markers = data.Markers,
		}

		assert(not row.Rig or entry.Rig, `theres no rig named {row.Rig} in this export`)

		for _, phase in { "Begin", "End" } do
			local fn = row[phase]
			if fn then
				assert(type(fn) == "function", `{phase} of event {data.Name} must be a function`)
				local key = `{id}:{phase}`
				factories[key] = function()
					return fn
				end
				entry[phase] = key
			end
		end

		return entry
	end

	local function assemble(root, config)
		local baked = require(root:FindFirstChild("Baked") or error(`{root.Name} has no Baked module`))
		local factories = {}
		local data = table.clone(baked)

		assert(config.Camera ~= "Authored" or baked.Authored, `{root.Name} was exported without an authored camera`)

		data.Version = 2
		data.FPS = config.FPS
		data.LastFrame = config.LastFrame
		data.ContentLastFrame = math.min(baked.ContentLastFrame or config.LastFrame, config.LastFrame)
		data.CameraMode = config.Camera or "Game"
		data.Loop = config.Loop == true
		data.Events = {}
		data.Subtitles = {}

		for index, row in config.Events or {} do
			if row.Enabled ~= false then
				table.insert(data.Events, event(row, index, baked.Rigs or {}, factories))
			end
		end

		for index, row in config.Subtitles or {} do
			if row.Enabled ~= false then
				table.insert(data.Subtitles, subtitle(row, index))
			end
		end

		table.sort(data.Subtitles, function(a, b)
			if a.event.Subtitle.Order ~= b.event.Subtitle.Order then
				return a.event.Subtitle.Order < b.event.Subtitle.Order
			end
			return a.order < b.order
		end)

		return { data = data, factories = factories }
	end

	function Eclipse.build(root, config)
		assert(typeof(root) == "Instance" and root:IsA("ModuleScript"), "build expects the cutscene module as its first argument")
		assert(type(config) == "table", "build expects the cutscene table as its second argument")
		assert(type(config.FPS) == "number" and config.FPS > 0, "cutscene FPS must be a positive number")
		assert(type(config.LastFrame) == "number" and config.LastFrame >= 1, "cutscene LastFrame must be at least 1")

		local camera = config.Camera or "Game"
		assert(camera == "Game" or camera == "Authored" or camera == "Studio", `unknown camera mode {camera}`)

		local settings = {
			CameraMode = camera,
			Interpolate = config.Interpolate ~= false,
			HideOriginals = config.HideOriginals ~= false,
		}

		local api = Player(root, settings, config.FPS, config.LastFrame, function()
			return assemble(root, config)
		end)

		api.Name = root.Name
		api.Button = config.Button

		return api
	end

	return Eclipse
end
