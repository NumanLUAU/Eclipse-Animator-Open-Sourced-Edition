--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Preferences = require("Preferences")
local SavedDefaults = require("SavedDefaults")
local Defaults = require("Defaults")
local KeyframeDefaults = {}

local FIELDS = {
	"EasingStyle",
	"EasingDirection",
	"HandleType",
	"Overshoot",
	"Amplitude",
	"Period",
	"MoonEasing",
}

function KeyframeDefaults.new(bucket, frame, options)
	local result = SavedDefaults.get()
	local nearest, distance
	for at, key in bucket do
		if typeof(at) == "number" and (not distance or math.abs(at - frame) < distance) then
			nearest, distance = key, math.abs(at - frame)
		end
	end

	result.QuaternionInterpolationVersion = nearest and nearest.QuaternionInterpolationVersion or 2
	if
		not Preferences.get("UsePreviousEasing")
		or typeof(options) == "table" and options.InheritEasing == false
	then
		return result
	end

	local previous, previousFrame
	for candidateFrame, key in bucket do
		if
			typeof(candidateFrame) == "number"
			and candidateFrame < frame
			and (not previousFrame or candidateFrame > previousFrame)
		then
			previous, previousFrame = key, candidateFrame
		end
	end

	if not previous then
		return result
	end

	for _, field in FIELDS do
		result[field] = previous[field] or Defaults[field]
	end

	result.BezierPoints = table.clone(previous.BezierPoints or Defaults.BezierPoints)
	return result
end

return KeyframeDefaults
