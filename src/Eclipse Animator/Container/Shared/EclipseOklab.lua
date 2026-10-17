--// cracked by numan

return function(env, libraries)
	local game, task, os, math, Random, coroutine, type, warn =
		env.game, env.task, env.os, env.math, env.Random, env.coroutine, env.type, env.warn
	local task = nil

	local EclipseRGB = libraries.EclipseRGB(env, libraries)

	type Matrix = { Vector3 }

	local RGB_TO_LMS: Matrix = {
		Vector3.new(0.4122214708, 0.5363325363, 0.0514459929),
		Vector3.new(0.2119034982, 0.6806995451, 0.1073969566),
		Vector3.new(0.0883024619, 0.2817188376, 0.6299787005),
	}

	local LMS_TO_LAB: Matrix = {
		Vector3.new(0.2104542553, 0.7936177850, -0.0040720468),
		Vector3.new(1.9779984951, -2.4285922050, 0.4505937099),
		Vector3.new(0.0259040371, 0.7827717662, -0.8086757660),
	}

	local LAB_TO_LMS: Matrix = {
		Vector3.new(1, 0.3963377774, 0.2158037573),
		Vector3.new(1, -0.1055613458, -0.0638541728),
		Vector3.new(1, -0.0894841775, -1.2914855480),
	}

	local LMS_TO_RGB: Matrix = {
		Vector3.new(4.0767416621, -3.3077115913, 0.2309699292),
		Vector3.new(-1.2684380046, 2.6097574011, -0.3413193965),
		Vector3.new(-0.0041960863, -0.7034186147, 1.7076147010),
	}

	local function multiply(matrix: Matrix, vector: Vector3): Vector3
		return Vector3.new(matrix[1]:Dot(vector), matrix[2]:Dot(vector), matrix[3]:Dot(vector))
	end

	local function mapAxes(vector: Vector3, fn: (number) -> number): Vector3
		return Vector3.new(fn(vector.X), fn(vector.Y), fn(vector.Z))
	end

	local function cubeRoot(x: number): number
		return x ^ (1 / 3)
	end

	local function cube(x: number): number
		return x * x * x
	end

	local EclipseOklab = {}

	function EclipseOklab.fromLinear(rgb: Color3): Vector3
		local lms = multiply(RGB_TO_LMS, Vector3.new(rgb.R, rgb.G, rgb.B))
		return multiply(LMS_TO_LAB, mapAxes(lms, cubeRoot))
	end

	function EclipseOklab.fromSRGB(srgb: Color3): Vector3
		return EclipseOklab.fromLinear(EclipseRGB.toLinear(srgb))
	end

	function EclipseOklab.toLinear(lab: Vector3, unclamped: boolean?): Color3
		local rgb = multiply(LMS_TO_RGB, mapAxes(multiply(LAB_TO_LMS, lab), cube))

		if unclamped then
			return Color3.new(rgb.X, rgb.Y, rgb.Z)
		end

		return Color3.new(math.clamp(rgb.X, 0, 1), math.clamp(rgb.Y, 0, 1), math.clamp(rgb.Z, 0, 1))
	end

	function EclipseOklab.toSRGB(lab: Vector3, unclamped: boolean?): Color3
		return EclipseRGB.fromLinear(EclipseOklab.toLinear(lab, unclamped))
	end

	return EclipseOklab
end
