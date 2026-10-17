--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local UI = require("UI")
local History = require("History")

local EditActions = {}

local function getTimeline()
	if not UI.isAnimatorActive() then
		return nil
	end

	local timeline = State.Timeline
	if not timeline or timeline:IsBlenderKeyframeTransformActive() then
		return nil
	end

	local axis = State.Axis
	if
		axis and (axis:IsHoldingAxis() or axis:IsBlenderGrabMode() or axis:IsBlenderRotateMode())
	then
		return nil
	end

	return timeline
end

function EditActions.Undo()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:GetState().Playing = false
	local changed = History.undo()
	if changed then
		State.currentProjectSaved = false
	end

	return changed
end

function EditActions.Redo()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:GetState().Playing = false
	local changed = History.redo()
	if changed then
		State.currentProjectSaved = false
	end

	return changed
end

function EditActions.CopyKeys()
	local timeline = getTimeline()
	return timeline ~= nil and timeline:CopySelectedKeyframes()
end

function EditActions.PasteKeys()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:GetState().Playing = false
	local changed = timeline:PasteKeyframes()
	if changed then
		State.currentProjectSaved = false
	end

	return changed
end

function EditActions.PasteFlipped()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:GetState().Playing = false
	local changed = timeline:PasteKeyframesFlipped()
	if changed then
		State.currentProjectSaved = false
	end

	return changed
end

function EditActions.ReverseKeys()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	local changed, reason = timeline:ReverseSelectedKeyframes()
	if reason then
		warn("Eclipse: " .. reason)
	end

	return changed
end

function EditActions.ReversePaste()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:GetState().Playing = false
	local changed = timeline:PasteKeyframes(true)
	if changed then
		State.currentProjectSaved = false
	end

	return changed
end

function EditActions.SelectAll()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:SelectAllKeyframes()
	return true
end

function EditActions.DeselectAll()
	local timeline = getTimeline()
	if not timeline then
		return false
	end

	timeline:ClearSelectedKeyframes()
	return true
end

return EditActions
