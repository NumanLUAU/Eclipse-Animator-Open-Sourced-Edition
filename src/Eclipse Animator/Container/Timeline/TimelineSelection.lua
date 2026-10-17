--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local State = require("RawState")
local TimelineState = State.Timeline
local TimelineConfig = State.Config
local PlayheadDrag = State.PlayheadDrag
local KeyframeDrag = State.KeyframeDrag
local SelectionState = State.Selection
local KEYFRAME_DEFAULT_COLOR = State.Colors.KEYFRAME_DEFAULT_COLOR
local KEYFRAME_HOVER_COLOR = State.Colors.KEYFRAME_HOVER_COLOR
local KEYFRAME_SELECTED_COLOR = State.Colors.KEYFRAME_SELECTED_COLOR
local LOOP_ACTIVE_COLOR = State.Colors.LOOP_ACTIVE_COLOR
local LOOP_INACTIVE_COLOR = State.Colors.LOOP_INACTIVE_COLOR

return function(Timeline)
	function Timeline:GetTrackRowForPart(part)
		return TimelineState.TrackRows[part]
	end

	local containerCache = setmetatable({}, { __mode = "k" })

	function Timeline:GetTrackKeyframesContainer(trackClone)
		if not trackClone then
			return nil
		end

		local cached = containerCache[trackClone]
		if cached and cached.Parent and cached.Parent.Parent == trackClone then
			return cached
		end

		local content = trackClone:FindFirstChild("Content")
		if not content then
			return nil
		end

		local container = content:FindFirstChild("Keyframes")
		containerCache[trackClone] = container
		return container
	end

	function Timeline:GetKeyframeTemplateForPart(part)
		local row = self:GetTrackRowForPart(part)
		if not row then
			return nil
		end

		local keyframesContainer = self:GetTrackKeyframesContainer(row)
		if not keyframesContainer then
			return nil
		end

		return keyframesContainer:FindFirstChild("KeyframeTemplate")
	end

	function Timeline:SetTrackCount(trackCount)
		TimelineState.TrackHeight = TimelineState.TrackHeight
		TimelineState.ContentWidth = self:GetTimelineWidth()
		local keysRoot = self.refs.KeysRoot
		if keysRoot and keysRoot:IsA("GuiObject") then
			keysRoot.Size = UDim2.new(
				0,
				TimelineState.ContentWidth,
				keysRoot.Size.Y.Scale,
				keysRoot.Size.Y.Offset
			)
		end
	end

	function Timeline:GetTrackContainer()
		return self.refs.TrackContainer
	end

	function Timeline:GetTrackTemplate()
		return self.refs.TrackTemplate
	end

	function Timeline:ClearTracks()
		local trackContainer = self:GetTrackContainer()
		local trackTemplate = self:GetTrackTemplate()

		if not trackContainer or not trackTemplate then
			TimelineState.TrackRows = {}
			TimelineState.ChannelTracks = {}
			return
		end

		trackTemplate.Visible = false
		TimelineState.TrackRows = {}
		TimelineState.ChannelTracks = {}
	end

	function Timeline:RebindTrackRows(items)
		self:InvalidateKeyframeViewportLayout()
		TimelineState.TrackRows = {}
		TimelineState.ChannelTracks = {}
		for _, item in items do
			if item.itemKind == "channel" then
				continue
			end

			local motor = item:fetchMotor()
			if motor and motor.Part1 and item.trackElement and item.trackElement.Parent then
				TimelineState.TrackRows[motor.Part1] = item.trackElement
				local rows = {}
				for _, channel in item.transformChannelItems or {} do
					if
						channel.channelId
						and channel.trackElement
						and channel.trackElement.Parent
					then
						rows[channel.channelId] = channel.trackElement
					end
				end

				if next(rows) then
					TimelineState.ChannelTracks[motor] = rows
				end
			end
		end

		for _, bucket in TimelineState.Keyframes do
			for _, key in bucket do
				if
					key.Button
					and key.Button.Parent
					and not (self.IsRetainedKeyframeButton and self:IsRetainedKeyframeButton(key))
				then
					key.Button:Destroy()
					key.Button = nil
				end
			end
		end
	end

	function Timeline:CreateTrackRow(part, trackIndex, sanitizeName)
		local trackContainer = self:GetTrackContainer()
		local trackTemplate = self:GetTrackTemplate()

		local clone = trackTemplate:Clone()
		clone.Visible = true
		clone.Name = ((sanitizeName and sanitizeName(part.Name)) or part.Name) .. "_Track"
		clone.Parent = trackContainer
		clone.LayoutOrder = trackIndex

		local keyframesContainer = self:GetTrackKeyframesContainer(clone)
		if keyframesContainer then
			local template = keyframesContainer:FindFirstChild("KeyframeTemplate")
			if template then
				template.Visible = false
			end
		end

		TimelineState.TrackRows[part] = clone
		return clone
	end

	function Timeline:CreateChannelTrackRow(parentName, channelId, layoutOrder, sanitizeName)
		local trackContainer = self:GetTrackContainer()
		local trackTemplate = self:GetTrackTemplate()
		if not trackContainer or not trackTemplate then
			return nil
		end

		local clone = trackTemplate:Clone()
		clone.Visible = false
		local safeName = (sanitizeName and sanitizeName(parentName)) or parentName
		clone.Name = safeName .. "_Channel_" .. channelId
		clone.Parent = trackContainer
		clone.LayoutOrder = layoutOrder

		local keyframesContainer = self:GetTrackKeyframesContainer(clone)
		if keyframesContainer then
			local template = keyframesContainer:FindFirstChild("KeyframeTemplate")
			if template then
				template.Visible = false
			end
		end

		return clone
	end
end
