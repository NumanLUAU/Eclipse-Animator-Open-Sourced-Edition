--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local function source(module)
	local text = module.Source
	local start = text:find("return function(require)", 1, true)
	assert(start, "Unexpected export module shape: " .. module.Name)
	return text:sub(start)
end

local sources = {
	["Helpers/CameraProjection"] = source(script.EclipseExportHelpersCameraProjection),
	["Helpers/EffectLayer"] = source(script.EclipseExportHelpersEffectLayer),
	["Helpers/EffectObjects"] = source(script.EclipseExportHelpersEffectObjects),
	["Helpers/EffectVFXSurface"] = source(script.EclipseExportHelpersEffectVFXSurface),
	["Helpers/EmitData"] = source(script.EclipseExportHelpersEmitData),
	["Helpers/SubtitleData"] = source(script.EclipseExportHelpersSubtitleData),
	["Resources/EffectAssets"] = require(script.EclipseExportResourcesEffectAssets),
	["Runtime/Geometry"] = source(script.EclipseExportRuntimeGeometry),
	["Runtime/Letterbox"] = source(script.EclipseExportRuntimeLetterbox),
	["Runtime/Player"] = source(script.EclipseExportRuntimePlayer),
	["Runtime/Cutscene"] = source(script.EclipseExportRuntimeCutscene),
	["Runtime/Preload"] = source(script.EclipseExportRuntimePreload),
	["Subsystems/SubtitleRenderer"] = source(script.EclipseExportSubsystemsSubtitleRenderer),
}

for _, name in { "EclipseRGB", "EclipseOklab", "EclipsePromise", "EclipseShake", "EclipseDrawing" } do
	local library = script:FindFirstAncestor("Container").Shared[name]
	sources["Shared/" .. name] = "return function(require)\n" .. library.Source .. "\nend\n"
end

return sources
