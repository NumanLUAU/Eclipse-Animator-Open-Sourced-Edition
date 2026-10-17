--// cracked by numan

return function(env, libraries)
	local game, task, os, math, Random, coroutine, type, warn =
		env.game, env.task, env.os, env.math, env.Random, env.coroutine, env.type, env.warn
	local RunService = game:GetService("RunService")

	type UpdateCallbackFn = () -> (Vector3, Vector3, boolean)

	export type EclipseShake = {
		Amplitude: number,
		Frequency: number,
		FadeInTime: number,
		FadeOutTime: number,
		SustainTime: number,
		Sustain: boolean,
		PositionInfluence: Vector3,
		RotationInfluence: Vector3,
		TimeFunction: () -> number,

		Start: (self: EclipseShake) -> (),
		Stop: (self: EclipseShake) -> (),
		IsShaking: (self: EclipseShake) -> boolean,
		StopSustain: (self: EclipseShake) -> (),
		Update: (self: EclipseShake) -> (Vector3, Vector3, boolean),
		OnSignal: (
			self: EclipseShake,
			signal: RBXScriptSignal,
			callback: (Vector3, Vector3, boolean) -> ()
		) -> RBXScriptConnection,
		BindToRenderStep: (
			self: EclipseShake,
			name: string,
			priority: number,
			callback: (Vector3, Vector3, boolean) -> ()
		) -> (),
		Clone: (self: EclipseShake) -> EclipseShake,
		Destroy: (self: EclipseShake) -> (),
	}

	local seed = Random.new()
	local nameCounter = 0

	local DEFAULTS = {
		Amplitude = 1,
		Frequency = 1,
		FadeInTime = 1,
		FadeOutTime = 1,
		SustainTime = 0,
		Sustain = false,
		PositionInfluence = Vector3.one,
		RotationInfluence = Vector3.one,
	}

	local function envelope(shake, elapsed: number): (number, boolean)
		local fadeIn = shake.FadeInTime
		local hold = shake.SustainTime
		local fadeOut = shake.FadeOutTime

		local gainIn = 1
		local gainOut = 1
		local finished = false

		if elapsed < fadeIn then
			gainIn = elapsed / fadeIn
		end

		if not shake.Sustain and elapsed > fadeIn + hold then
			if fadeOut == 0 then
				finished = true
			else
				gainOut = 1 - (elapsed - fadeIn - hold) / fadeOut
				finished = elapsed >= fadeIn + hold + fadeOut
			end
		end

		return math.min(gainIn, gainOut), finished
	end

	local EclipseShake = {}
	EclipseShake.__index = EclipseShake

	function EclipseShake.new(): EclipseShake
		local self = setmetatable({
			TimeFunction = if RunService:IsRunning() then time else os.clock,
			_timeOffset = seed:NextNumber(-1e6, 1e6),
			_startTime = 0,
			_running = false,
			_teardown = {},
		}, EclipseShake)

		for name, value in DEFAULTS do
			self[name] = value
		end

		return self
	end

	function EclipseShake.InverseSquare(shake: Vector3, distance: number): Vector3
		local reach = math.max(distance, 1)
		return shake / (reach * reach)
	end

	function EclipseShake.NextRenderName(): string
		nameCounter += 1
		return string.format("EclipseShake_%04d", nameCounter)
	end

	function EclipseShake:Start()
		self._startTime = self.TimeFunction()
		self._running = true
	end

	function EclipseShake:Stop()
		self._running = false

		for _, release in self._teardown do
			release()
		end

		table.clear(self._teardown)
	end

	function EclipseShake:IsShaking(): boolean
		return self._running
	end

	function EclipseShake:StopSustain()
		self.Sustain = false
		self.SustainTime = (self.TimeFunction() - self._startTime) - self.FadeInTime
	end

	function EclipseShake:Update(): (Vector3, Vector3, boolean)
		local now = self.TimeFunction()
		local gain, finished = envelope(self, now - self._startTime)
		local phase = ((now + self._timeOffset) / self.Frequency) % 10000

		local offset = Vector3.new(
			math.noise(phase, 0) / 2,
			math.noise(0, phase) / 2,
			math.noise(phase, phase) / 2
		) * self.Amplitude * gain

		if finished then
			self:Stop()
		end

		return self.PositionInfluence * offset, self.RotationInfluence * offset, finished
	end

	function EclipseShake:OnSignal(signal, callbackFn: UpdateCallbackFn)
		local connection = signal:Connect(function()
			callbackFn(self:Update())
		end)

		table.insert(self._teardown, function()
			connection:Disconnect()
		end)

		return connection
	end

	function EclipseShake:BindToRenderStep(
		name: string,
		priority: number,
		callbackFn: UpdateCallbackFn
	)
		RunService:BindToRenderStep(name, priority, function()
			callbackFn(self:Update())
		end)

		table.insert(self._teardown, function()
			RunService:UnbindFromRenderStep(name)
		end)
	end

	function EclipseShake:Clone()
		local copy = EclipseShake.new()

		for name in DEFAULTS do
			copy[name] = self[name]
		end

		copy.TimeFunction = self.TimeFunction

		return copy
	end

	function EclipseShake:Destroy()
		self:Stop()
	end

	return {
		new = EclipseShake.new,
		InverseSquare = EclipseShake.InverseSquare,
		NextRenderName = EclipseShake.NextRenderName,
	}
end
