--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local M = require("M")
local Display = {}
local transforms = setmetatable({}, { __mode = "k" })
local fitValue, fitMatrix

local function vector(value, default)
	return value and Vector3.new(value[1], value[2], value[3]) or default
end

function Display.state(bone)
	local d = bone.display
	return d
		and {
			custom_shape_scale_xyz = vector(d.custom_shape_scale_xyz, Vector3.one),
			custom_shape_translation = vector(d.custom_shape_translation, Vector3.zero),
			custom_shape_rotation_euler = vector(d.custom_shape_rotation_euler, Vector3.zero),
		}
end

function Display.matrix(bone, sourcePose, fit, fitScale, exportScale, state)
	local d = bone.display
	if not d then
		return nil
	end

	state = state or Display.state(bone)
	local length = d.use_custom_shape_bone_size and d.length or d.geometry_scale or exportScale or 1

	local pair = transforms[bone]
	if not pair then
		pair = {}
		transforms[bone] = pair
	end

	local prepared
	for _, value in ipairs(pair) do
		if
			value.fitScale == fitScale
			and value.length == length
			and value.translation == state.custom_shape_translation
			and value.rotation == state.custom_shape_rotation_euler
			and value.scale == state.custom_shape_scale_xyz
		then
			prepared = value
			break
		end
	end

	if not prepared then
		local localFrame = CFrame.new(state.custom_shape_translation * fitScale)
			* M.fromEuler(state.custom_shape_rotation_euler, "XYZ")
		prepared = {
			fitScale = fitScale,
			length = length,
			translation = state.custom_shape_translation,
			rotation = state.custom_shape_rotation_euler,
			scale = state.custom_shape_scale_xyz,
			localMatrix = M.compose(localFrame, state.custom_shape_scale_xyz * (length * fitScale)),
		}
		pair[2], pair[1] = pair[1], prepared
	end

	if fitValue ~= fit then
		fitValue = fit
		fitMatrix = M.fromCFrame(fit)
	end

	if pair.worldSource ~= sourcePose or pair.worldFit ~= fit or pair.worldScale ~= fitScale then
		pair.worldSource, pair.worldFit, pair.worldScale = sourcePose, fit, fitScale
		pair.worldMatrix = M.mul(fitMatrix, M.translationScaled(sourcePose, fitScale))
	end

	return M.mul(pair.worldMatrix, prepared.localMatrix)
end

return Display
