--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = {}
State.PresentationHidden = false

State.currentRig = nil :: Instance?
State.extraRigs = {} :: { Instance }
State.activeObjectMotors = {} :: { [Instance]: boolean }
State.currentAnimations = {} :: { [Instance]: any }
State.animButtons = {} :: { Instance }
State.lastCFrames = {} :: { [Instance]: CFrame }

State.GizmoMode = "Position" :: string
State.manipulationStartC0 = nil :: CFrame?
State.manipulationMotor = nil :: Instance?
State.manipulationMotors = nil :: any
State.ignoreSelectionChanged = false
State.currentProjectSaved = false
State.currentProjectSave = nil :: Instance?
State.currentProjectSequence = nil :: Instance?
State.exportSequences = {} :: { [Instance]: KeyframeSequence }

State.currentPlayButton = nil :: Instance?
State.currentPlayingTrack = nil :: any
State.currentPlayingRig = nil :: Instance?

State.PreviewWorldModel = nil :: Instance?
State.PreviewCamera = nil :: Instance?

State.mouseDownTime = 0
State.mouseDownAxisPart = nil :: Instance?
State.mouseDownSelectedBone = nil :: Instance?
State.mouseDownMousePos = nil :: Vector2?
State.pendingScoreHoldConnection = nil :: RBXScriptConnection?
State.scoreDragStarted = false

State.UIHelpers = nil :: any
State.Timeline = nil :: any
State.Rig = nil :: any
State.Axis = nil :: any
State.OnionSkin = nil :: any
State.mouse = nil :: any

local function getRig(): Instance?
	return State.currentRig
end

local function getAllRigs(): { Instance }
	local rigs = {}
	if State.currentRig then
		table.insert(rigs, State.currentRig)
	end

	for _, rig in ipairs(State.extraRigs) do
		if rig and rig.Parent and rig ~= State.currentRig then
			table.insert(rigs, rig)
		end
	end

	return rigs
end

function State.getProjectRigs(): { Instance }
	local rigs = {}
	if State.currentRig then
		table.insert(rigs, State.currentRig)
	end

	for _, rig in State.extraRigs do
		if rig and not table.find(rigs, rig) then
			table.insert(rigs, rig)
		end
	end

	return rigs
end

State.getRig = getRig
State.getAllRigs = getAllRigs

return State
