--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local module = {}
type Settings = {
	["StartsAt"]: number,
	["CanTransformMotor6D"]: boolean | nil,
	["Animate"]: "Animate" | "First" | "Last" | nil,
	["UpsyncThePlaying"]: "Default" | "Ramp" | "SpeedUp" | nil,
}
type Setting = Settings
type AnimationSequance = {
	Looped: boolean,
	TimePosition: number,
	IsPlaying: boolean,
	Speed: number,
	Weight: number,
	WeightCurrent: number,
	WeightTarget: number,
	Priority: Enum.AnimationPriority,
	Name: string,
	Animation: {},
	Motor6D: {},
	Settings: Settings,
	Event: RBXScriptSignal,
	Ended: RBXScriptSignal,
	Stopped: RBXScriptSignal,
	DidLoop: RBXScriptSignal,
	_fireEvent: BindableEvent,
	_fireEnded: BindableEvent,
	_fireStopped: BindableEvent,
	_fireDidLoop: BindableEvent,
	Length: number,
	_debugSpeed: number | nil,
	FadingAnimation: boolean | nil,
	FadeTime: number | nil,
	FadeMax: number | nil,
	FadeDelta: number | nil,
	Task: thread | nil,
	_tempLoop: boolean | nil,
	_Connection: RBXScriptConnection | nil,
	Group: {} | nil,

	Play: (
		self: AnimationSequance,
		FadeTime: number,
		Weight: number,
		TimeStamp: number,
		Speed: number
	) -> nil,
	Stop: (self: AnimationSequance, FadeTime: number) -> nil,
	Destroy: (self: AnimationSequance) -> nil,
	UnFreeze: (self: AnimationSequance) -> nil,
	Freeze: (self: AnimationSequance) -> number,
	Cancel: (self: AnimationSequance, DontResetMotor6D: boolean) -> number,
	StopFading: (self: AnimationSequance) -> nil,
	AdjustWeight: (self: AnimationSequance, weight: number, fadeTime: number) -> nil,
}

return module
