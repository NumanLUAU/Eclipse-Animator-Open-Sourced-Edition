--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

return {
	SelectedColor = Color3.fromRGB(138, 20, 255),
	DefaultColor = Color3.fromRGB(255, 255, 255),
	SecondaryDefaultColor = Color3.fromRGB(115, 115, 115),
	RigSelectedColor = Color3.fromRGB(173, 216, 255),
	KeyframeDefaultColor = Color3.fromRGB(255, 255, 255),

	Descriptions = {
		MasterRig = "Master rig",
		TransformChannels = "Transform channels",
		TransformChannelClass = "Transform channel class",
		Disable = "Toggle enabling track",
		More = "More options",
		MotionPath = "Toggle Motion Path",
		AddRig = "Add Rig",
		AddObject = "Add Object",
		LoopOn = "Disable Loop",
		LoopOff = "Enable Loop",
		RecordOn = "Disable Live Recording",
		RecordOff = "Enable Live Recording",
		Save = "Save Project",
		Export = "Export Animation",
		Close = "Close Animation",
	},
}
