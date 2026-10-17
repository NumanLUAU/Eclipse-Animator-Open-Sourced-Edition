--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("RawState")

local Timeline = {}
Timeline.__index = Timeline

require("GraphPhysics")(Timeline)
require("TimelineScrubbing")(Timeline)
require("TimelinePlayhead")(Timeline)
require("KeyframeBaking")(Timeline)
require("TimelineSelection")(Timeline)
require("CameraKeyframing")(Timeline)
require("PropertyKeyframes")(Timeline)
require("GraphDragging")(Timeline)
require("KeyframeClipboard")(Timeline)
require("ParentingKeyframes")(Timeline)
require("IKKeyframing")(Timeline)
require("TimelineKeyframes")(Timeline)
require("MotionPathKeyframes")(Timeline)
require("CameraGraph")(Timeline)
require("GraphInput")(Timeline)
require("EventPlaybackInput")(Timeline)

require("SelectionMenu")(Timeline)

require("GraphExtras")(Timeline)

return Timeline
