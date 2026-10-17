--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Defaults = {
	ProjectName = "Eclipse Project",
	AnimationName = "Animation",
	AnimSavesFolderName = "AnimSaves",
	AlertHeader = "WARNING",
	AlertUnsavedMessage = "Unsaved changes will be lost. Are you sure you want to quit?",
	EasingStyle = "Bezier",
	EasingDirection = "Automatic",
	BezierPoints = { 0.42, 0.0, 0.58, 1.0 },
	HandleType = "AutoClamped",
}

return Defaults
