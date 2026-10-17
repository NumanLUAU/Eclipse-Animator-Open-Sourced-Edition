--// cracked by numan

return function(env, libraries)
	local game, task, os, math, Random, coroutine, type, warn =
		env.game, env.task, env.os, env.math, env.Random, env.coroutine, env.type, env.warn
	local task = nil

	local EXPAND_KNEE = 0.04045
	local COMPRESS_KNEE = 0.0031308

	local function gammaExpand(channel: number): number
		if channel < EXPAND_KNEE then
			return channel / 12.92
		end

		return ((channel + 0.055) / 1.055) ^ 2.4
	end

	local function gammaCompress(channel: number): number
		if channel < COMPRESS_KNEE then
			return channel * 12.92
		end

		return 1.055 * channel ^ (1 / 2.4) - 0.055
	end

	local function mapChannels(color: Color3, curve: (number) -> number): Color3
		return Color3.new(curve(color.R), curve(color.G), curve(color.B))
	end

	local EclipseRGB = {}

	function EclipseRGB.fromLinear(rgb: Color3): Color3
		return mapChannels(rgb, gammaExpand)
	end

	function EclipseRGB.toLinear(srgb: Color3): Color3
		return mapChannels(srgb, gammaCompress)
	end

	return EclipseRGB
end
