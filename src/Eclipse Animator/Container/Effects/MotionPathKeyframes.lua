--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("RawState")
local History = require("History")
local EventPlayback = require("EventPlayback")
local Preferences = require("Preferences")
local motionPath = require("motionPath")
local GraphCurves = require("GraphCurves")
local MainState = require("State")

local TimelineState = State.Timeline
local TimelineConfig = State.Config

local function validFPS(value)
	return typeof(value) == "number"
		and value == value
		and value >= 1
		and value <= 1000
		and value % 1 == 0
end

local function playbackFailure(self, issue)
	self._playbackPreparation = nil
	self._playbackReadyAt = nil
	TimelineState.Playing = false
	TimelineState.LastPlaybackFrame = nil
	pcall(EventPlayback.stop)
	local message = tostring(issue)
	if self._lastPlaybackFailure ~= message then
		self._lastPlaybackFailure = message
		warn("[Eclipse Playback] " .. message)
		pcall(function()
			require("Notification").show(
				"PLAYBACK STOPPED",
				"Playback could not continue. Your animation is still open. See Output for details.",
				6
			)
		end)
	end

	return false, issue
end

return function(Timeline)
	function Timeline:GetPlaybackStartTime()
		return math.clamp(
			TimelineState.PlaybackStartFrame or 0,
			0,
			math.max(0, self:GetPlaybackEndTime() * TimelineState.FPS - 1)
		) / TimelineState.FPS
	end

	function Timeline:GetPoseTime(time)
		local skip = TimelineState.SkipFrames or 0
		if skip <= 0 and not TimelineState.Playing then
			return time
		end

		local step = skip + 1
		return math.floor((math.max(0, time) * TimelineState.FPS + 1e-7) / step)
			* step
			/ TimelineState.FPS
	end

	function Timeline:IsExportLocked()
		local live = MainState.LiveSession
		return TimelineState.Exporting ~= nil
			or (live and live.isExporting and live.isExporting())
			or false
	end

	function Timeline:SetFPS(value, loading)
		if not validFPS(value) then
			return false
		end

		local previous = TimelineState.FPS
		if previous == value then
			return true
		end

		local function apply(fps)
			local oldFPS = TimelineState.FPS
			local frame = self:TimeToFrame(TimelineState.CurrentTime)
			local lastFrame = self:GetMaxFrame()
			TimelineState.Playing = false
			TimelineState.FPS = fps
			EventPlayback.clear()
			TimelineState.CurrentTime = frame / fps
			TimelineState.LastPlaybackFrame = nil
			TimelineConfig.Length = lastFrame / fps
			for _, bucket in require("Layers").buckets(TimelineState) do
				for frameNumber, key in pairs(bucket) do
					key.Time = frameNumber / fps
					for _, point in pairs(key.GraphCurves or {}) do
						if point.In then
							point.In[1] *= oldFPS / fps
						end

						if point.Out then
							point.Out[1] *= oldFPS / fps
						end
					end
				end

				GraphCurves.invalidate(bucket)
			end

			self:RefreshTimelineScale()
			if MainState.GraphEditor then
				MainState.GraphEditor.invalidate()
			end

			local rig = self.refs.GetCurrentRig and self.refs.GetCurrentRig()
			if rig then
				self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			end

			motionPath.markDirty()
			if not loading then
				if self.refs.SetSetting then
					self.refs.SetSetting("TimelineFPS", fps)
				end

				if self.refs.SetCurrentRigUnsaved then
					self.refs.SetCurrentRigUnsaved()
				end
			end
		end

		apply(value)
		if not loading then
			History.record(function()
				apply(previous)
			end, function()
				apply(value)
			end, "Change FPS")
		end

		return true
	end

	function Timeline:LoadProjectSettings(sequence, settings)
		local priority = settings and settings:GetAttribute("AnimationPriority")
			or sequence and sequence.Priority.Name
		TimelineState.AnimationPriority = Enum.AnimationPriority.Action
		if type(priority) == "string" then
			pcall(function()
				TimelineState.AnimationPriority = Enum.AnimationPriority[priority]
			end)
		end

		local fps = settings and settings:GetAttribute("FPS")
			or sequence and sequence:GetAttribute("FPS")
		if not validFPS(fps) then
			fps = not sequence and not settings and Preferences.get("DefaultFPS") or 60
		end

		TimelineState.FPS = validFPS(fps) and fps or 60
		local skip = settings and settings:GetAttribute("EclipseSkipFrames")
			or sequence and sequence:GetAttribute("EclipseSkipFrames")
		TimelineState.SkipFrames = type(skip) == "number"
				and skip == skip
				and skip >= 0
				and skip <= 120
				and skip % 1 == 0
				and skip
			or 0
		local start = settings and settings:GetAttribute("EclipsePlaybackStartFrame")
			or sequence and sequence:GetAttribute("EclipsePlaybackStartFrame")
		TimelineState.PlaybackStartFrame = type(start) == "number"
				and start == start
				and start >= 0
				and start <= 1000000
				and start % 1 == 0
				and start
			or 0
		TimelineState.CurrentTime = 0
		TimelineState.Playing = false
		TimelineState.LastPlaybackFrame = nil
		TimelineState.ScrollOffset = 0
		local lastFrame = settings and settings:GetAttribute("EclipseTimelineEnd")
			or sequence and sequence:GetAttribute("EclipseTimelineEnd")
		if
			typeof(lastFrame) ~= "number"
			or lastFrame ~= lastFrame
			or math.abs(lastFrame) == math.huge
			or lastFrame < 1
		then
			lastFrame = not sequence and not settings and Preferences.get("DefaultTrackLength")
				or TimelineConfig.DefaultFrames
		end

		lastFrame = math.max(1, math.floor(lastFrame))
		if sequence then
			for _, key in ipairs(sequence:GetKeyframes()) do
				lastFrame = math.max(lastFrame, self:TimeToFrame(key.Time))
			end
		end

		TimelineState.PlaybackStartFrame = math.min(TimelineState.PlaybackStartFrame, lastFrame - 1)
		TimelineConfig.Length = lastFrame / TimelineState.FPS
		if self.timelineZoom then
			self.timelineZoom.zoomScale = 1
		end

		require("Origin").read(settings or sequence, self)
		self:RefreshTimelineScale()
	end

	function Timeline:WriteProjectSettings(target)
		local priority = TimelineState.AnimationPriority or Enum.AnimationPriority.Action
		target:SetAttribute("AnimationPriority", priority.Name)
		if target:IsA("KeyframeSequence") then
			target.Priority = priority
		end

		target:SetAttribute("FPS", TimelineState.FPS)
		target:SetAttribute("EclipseSkipFrames", TimelineState.SkipFrames or 0)
		target:SetAttribute("EclipsePlaybackStartFrame", TimelineState.PlaybackStartFrame or 0)
		target:SetAttribute("EclipseTimelineEnd", self:GetMaxFrame())
		if not target:IsA("KeyframeSequence") then
			require("Origin").write(target, self)
		end
	end

	function Timeline:EnsureTimelineEnd(frame)
		if frame <= self:GetMaxFrame() then
			return
		end

		TimelineConfig.Length = math.ceil(frame) / TimelineState.FPS
		self:RefreshTimelineScale()
	end

	function Timeline:CaptureTimelineEnd()
		return {
			frame = self:GetMaxFrame(),
			time = TimelineState.CurrentTime,
			scroll = TimelineState.ScrollOffset,
		}
	end

	function Timeline:ApplyTimelineEnd(value, dirty)
		TimelineState.Playing = false
		EventPlayback.clear()
		TimelineConfig.Length = value.frame / TimelineState.FPS
		TimelineState.CurrentTime = value.time
		TimelineState.LastPlaybackFrame = nil
		self._playbackEndAt = nil
		self:RefreshTimelineScale()
		self:SetTimelineScroll(value.scroll)
		self:UpdatePlayhead()
		local rig = self.refs.GetCurrentRig and self.refs.GetCurrentRig()
		if rig then
			self:ApplyPoseAtTime(rig, value.time)
		end

		if dirty and self.refs.SetCurrentRigUnsaved then
			self.refs.SetCurrentRigUnsaved()
		end
	end

	function Timeline:SetTimelineEnd(frame, before, preview, followEnd)
		if self:IsExportLocked() then
			return false
		end

		frame = tonumber(frame)
		if not frame or frame ~= frame or math.abs(frame) == math.huge then
			return false
		end

		frame = math.max(1, math.floor(frame + 0.5))
		before = before or self:CaptureTimelineEnd()
		local after = {
			frame = frame,
			time = math.min(before.time, frame / TimelineState.FPS),
			scroll = before.scroll,
		}
		if followEnd then
			local viewport = self:GetTimelineViewportWidth()
			local width = viewport
				* math.max(1, frame / TimelineConfig.DefaultFrames)
				* self:GetZoomScale()
			after.scroll = math.max(0, math.floor(width + 0.5) - viewport)
		end

		if preview then
			if frame ~= self:GetMaxFrame() or after.time ~= TimelineState.CurrentTime then
				self:ApplyTimelineEnd(after, false)
			end

			return true
		end

		if frame == before.frame then
			self:ApplyTimelineEnd(before, false)
			return false
		end

		local function apply(value)
			self:ApplyTimelineEnd(value, true)
		end

		apply(after)
		History.record(function()
			apply(before)
		end, function()
			apply(after)
		end, "Animation length")
		return true
	end

	function Timeline:FitTimeline()
		if self:IsExportLocked() then
			return false
		end

		local last = self:GetLastKeyframeFrame()
		if last == nil then
			return false
		end

		local target = math.max(1, math.ceil(last))
		local before = {
			frame = self:GetMaxFrame(),
			time = TimelineState.CurrentTime,
			scroll = TimelineState.ScrollOffset,
		}
		if target == before.frame then
			return false
		end

		local after = {
			frame = target,
			time = math.min(before.time, target / TimelineState.FPS),
			scroll = before.scroll,
		}

		local function apply(snapshot)
			TimelineState.Playing = false
			EventPlayback.clear()
			TimelineConfig.Length = snapshot.frame / TimelineState.FPS
			TimelineState.CurrentTime = snapshot.time
			TimelineState.LastPlaybackFrame = nil
			self:RefreshTimelineScale()
			self:SetTimelineScroll(snapshot.scroll)
			self:UpdatePlayhead()
			local rig = self.refs.GetCurrentRig and self.refs.GetCurrentRig()
			if rig then
				self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			end

			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		apply(after)
		History.record(function()
			apply(before)
		end, function()
			apply(after)
		end, "Fit timeline")
		return true
	end

	function Timeline:ExtendTimeline()
		if self:IsExportLocked() then
			return false
		end

		local previous = self:GetMaxFrame()
		local nextFrame = previous + TimelineState.FPS

		local function apply(frame)
			TimelineConfig.Length = math.max(frame, self:GetLastKeyframeFrame() or 0)
				/ TimelineState.FPS
			TimelineState.CurrentTime = math.min(TimelineState.CurrentTime, TimelineConfig.Length)
			self:RefreshTimelineScale()
			self:SetTimelineScroll(self:GetTimelineScrollLimit())
			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		apply(nextFrame)
		History.record(function()
			apply(previous)
		end, function()
			apply(nextFrame)
		end, "Extend timeline")
	end

	function Timeline:StartPlayback(restartAtEnd)
		if MainState.LoadingProject and MainState.ProjectLoadThread ~= coroutine.running() then
			return false
		end

		if self:IsExportLocked() then
			TimelineState.Playing = false
			return false
		end

		if MainState.BlenderBridge and MainState.BlenderBridge.isFollowing() then
			return false
		end

		if TimelineState.Playing then
			return false
		end

		if self.refs.BeforePlayback then
			self.refs.BeforePlayback()
		end

		if
			TimelineState.CurrentTime < self:GetPlaybackStartTime()
			or restartAtEnd and TimelineState.CurrentTime >= self:GetPlaybackEndTime()
		then
			TimelineState.CurrentTime = self:GetPlaybackStartTime()
			self:UpdatePlayhead()
		end

		local time = TimelineState.CurrentTime
		local token = {}
		self._playbackPreparation = token
		self._playbackReadyAt = nil
		self._videoSampleAt = nil
		TimelineState.Playing = true
		local ok, result = xpcall(function()
			local rig = self.refs.GetCurrentRig and self.refs.GetCurrentRig()
			if rig then
				self:ApplyPoseAtTime(rig, time)
			end

			if MainState.ScreenEffects and MainState.ScreenEffects.prepare then
				local loaded = MainState.ScreenEffects.prepare(function()
					return self._playbackPreparation == token
						and TimelineState.Playing
						and TimelineState.CurrentTime == time
				end)
				if self._playbackPreparation ~= token then
					return false
				end

				if not loaded then
					self._playbackPreparation = nil
					TimelineState.Playing = false
					return false
				end
			end

			local ready = EventPlayback.prepare(self, time, rig, time, function()
				return self._playbackPreparation == token
					and TimelineState.Playing
					and TimelineState.CurrentTime == time
			end)
			if self._playbackPreparation ~= token then
				return false
			end

			if not ready then
				self._playbackPreparation = nil
				TimelineState.Playing = false
				return false
			end

			local deadline
			if MainState.VideoBridge then
				deadline = MainState.VideoBridge.prepare(self, time, function()
					return TimelineState.Playing
						and TimelineState.CurrentTime == time
						and self._playbackPreparation == token
				end)
			end

			if
				self._playbackPreparation ~= token
				or not TimelineState.Playing
				or TimelineState.CurrentTime ~= time
			then
				if self._playbackPreparation == token then
					self._playbackPreparation = nil
				end

				return false
			end

			self._playbackPreparation = nil
			self._playbackReadyAt = deadline or os.clock()
			self._lastPlaybackFailure = nil
			return true
		end, debug.traceback)
		if not ok then
			if self._playbackPreparation == token then
				return playbackFailure(self, result)
			end

			return false, result
		end

		return result
	end

	function Timeline:AdvanceLocalPlayback(dt)
		if self:IsExportLocked() then
			TimelineState.Playing = false
			return false
		end

		if
			MainState.BlenderSampling
			or (MainState.BlenderBridge and MainState.BlenderBridge.advance(dt))
		then
			return
		end

		if self._playbackPreparation then
			return
		end

		if not TimelineState.Playing then
			self._playbackReadyAt = nil
			if MainState.VideoBridge then
				MainState.VideoBridge.push(true)
			end

			EventPlayback.pause()
			EventPlayback.preview(self, TimelineState.CurrentTime, false)
			TimelineState.LastPlaybackFrame = nil
			return
		end

		if self._playbackReadyAt then
			local now = os.clock()
			if now < self._playbackReadyAt then
				return
			end

			dt = math.min(dt, now - self._playbackReadyAt)
			self._playbackReadyAt = nil
		end

		local finish = self:GetPlaybackEndTime()
		EventPlayback.advance(
			self,
			TimelineState.CurrentTime,
			dt,
			finish,
			self:IsLooping(),
			self:GetPlaybackStartTime()
		)
		local previousTime = TimelineState.CurrentTime
		local time = previousTime + dt
		if time >= finish then
			if self:IsLooping() and finish > 0 then
				local first = self:GetPlaybackStartTime()
				time = first + (time - first) % (finish - first)
			else
				time = finish
				TimelineState.Playing = false
			end
		end

		TimelineState.CurrentTime = time
		self._videoSampleAt = os.clock()
		local frame = math.floor(time * TimelineState.FPS + 1e-6)
		local frameChanged = frame ~= TimelineState.LastPlaybackFrame
		if
			frameChanged
			or not TimelineState.Playing
			or EventPlayback.didFire
		then
			TimelineState.LastPlaybackFrame = frame
			local rig = self.refs.GetCurrentRig and self.refs.GetCurrentRig()
			if rig then
				self:ApplyPoseAtTime(rig, time)
			end

			if frameChanged or not TimelineState.Playing then
				self:UpdatePlayhead()
			end
		end

		EventPlayback.preview(
			self,
			time,
			TimelineState.Playing,
			true,
			self.refs.GetCurrentRig and self.refs.GetCurrentRig(),
			time
		)
	end

	function Timeline:ApplyLivePlayhead(
		frame,
		playing,
		dt,
		looping,
		finish,
		commandChanged,
		startFrame
	)
		if self:IsExportLocked() then
			TimelineState.Playing = false
			return false
		end

		local time = math.clamp(frame, 0, self:GetMaxFrame()) / TimelineState.FPS
		local previous = TimelineState.CurrentTime
		playing = playing == true and (looping == true or frame < finish)
		if TimelineState.Playing and not playing and not commandChanged and time >= previous then
			EventPlayback.advance(self, previous, time - previous, finish / TimelineState.FPS, false, (startFrame or 0) / TimelineState.FPS)
		end
		if commandChanged or TimelineState.Playing and not playing then
			EventPlayback.stop()
			if playing then
				EventPlayback.advance(
					self,
					time,
					0,
					finish / TimelineState.FPS,
					looping == true,
					(startFrame or 0) / TimelineState.FPS
				)
			end
		end

		if playing and not commandChanged then
			EventPlayback.advance(
				self,
				previous,
				math.max(0, dt),
				finish / TimelineState.FPS,
				looping == true,
				(startFrame or 0) / TimelineState.FPS
			)
		end

		TimelineState.CurrentTime = time
		TimelineState.Playing = playing == true
		local poseFrame = math.floor(time * TimelineState.FPS + 1e-6)
		if
			poseFrame ~= TimelineState.LastPlaybackFrame
			or commandChanged
			or EventPlayback.didFire
		then
			TimelineState.LastPlaybackFrame = poseFrame
			local rig = self.refs.GetCurrentRig and self.refs.GetCurrentRig()
			if rig then
				self:ApplyPoseAtTime(rig, time)
			end
		end

		self:UpdatePlayhead()
		self._videoSampleAt = os.clock()
		EventPlayback.preview(
			self,
			time,
			playing == true,
			true,
			self.refs.GetCurrentRig and self.refs.GetCurrentRig(),
			time
		)
	end

	function Timeline:AdvancePlayback(dt)
		if MainState.LoadingProject and MainState.ProjectLoadThread ~= coroutine.running() then
			return
		end

		if TimelineState.Exporting then
			TimelineState.Playing = false
			return
		end

		if self._playbackAdvancing then
			return
		end

		self._playbackAdvancing = true
		local ok, issue = xpcall(function()
			local live = MainState.LiveSession
			if not (live and live.advance and live.advance(dt)) then
				self:AdvanceLocalPlayback(dt)
			end

			if live and live.afterAdvance then
				live.afterAdvance()
			end
		end, debug.traceback)
		self._playbackAdvancing = nil
		if not ok then
			return playbackFailure(self, issue)
		end
	end
end
