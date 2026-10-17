--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local Drivers = {}

local functions = {
	min = math.min,
	max = math.max,
	abs = math.abs,
	fabs = math.abs,
	floor = math.floor,
	ceil = math.ceil,
	trunc = function(x)
		return x >= 0 and math.floor(x) or math.ceil(x)
	end,
	int = function(x)
		return x >= 0 and math.floor(x) or math.ceil(x)
	end,
	round = function(x, digits)
		local m = 10 ^ (digits or 0)
		return math.round(x * m) / m
	end,
	sin = math.sin,
	cos = math.cos,
	tan = math.tan,
	asin = math.asin,
	acos = math.acos,
	atan = math.atan,
	atan2 = math.atan2,
	sqrt = math.sqrt,
	pow = math.pow,
	exp = math.exp,
	log10 = math.log10,
	ln = math.log,
	fmod = math.fmod,
	log = function(x, base)
		return base and math.log(x) / math.log(base) or math.log(x)
	end,
	sinc = function(x)
		return math.abs(x) < 1e-12 and 1 or math.sin(x) / x
	end,
	radians = math.rad,
	degrees = math.deg,
	hypot = function(a, b)
		return math.sqrt(a * a + b * b)
	end,
	lerp = function(a, b, t)
		return a + (b - a) * t
	end,
	clamp = function(x, low, high)
		return math.clamp(x, low or 0, high or 1)
	end,
	smoothstep = function(a, b, x)
		local t = math.clamp((x - a) / (b - a), 0, 1)
		return t * t * (3 - 2 * t)
	end,
}
local constants = { pi = math.pi, True = 1, False = 0 }
local comparisons =
	{ ["<"] = true, [">"] = true, ["<="] = true, [">="] = true, ["=="] = true, ["!="] = true }

function Drivers.compile(expression)
	local tokens = {}
	local cursor = 1
	while cursor <= #expression do
		local tail = expression:sub(cursor)
		local whitespace = tail:match("^%s+")
		if whitespace then
			cursor += #whitespace
			continue
		end

		local token = tail:match("^%d+%.?%d*[eE][%+%-]?%d+")
			or tail:match("^%.%d+[eE][%+%-]?%d+")
			or tail:match("^%d+%.?%d*")
			or tail:match("^%.%d+")
			or tail:match("^[%a_][%w_]*")
		if not token then
			local pair = tail:sub(1, 2)
			if pair == "**" or pair == "//" or comparisons[pair] then
				token = pair
			elseif tail:sub(1, 1):match("^[%+%-%*/%%%(%)%,<>]$") then
				token = tail:sub(1, 1)
			else
				return nil, "Unsupported driver expression"
			end
		end

		table.insert(tokens, token)
		cursor += #token
	end

	local index = 1
	local ternary

	local function peek()
		return tokens[index]
	end

	local function take()
		local token = tokens[index]
		index += 1
		return token
	end

	local function expect(token)
		if take() ~= token then
			error("Expected " .. token .. " in driver expression")
		end
	end

	local function binary(op, left, right)
		return function(vars)
			local a, b = left(vars), right(vars)
			if op == "+" then
				return a + b
			elseif op == "-" then
				return a - b
			elseif op == "*" then
				return a * b
			elseif op == "/" then
				if b == 0 then
					error("division by zero")
				end

				return a / b
			elseif op == "//" then
				if b == 0 then
					error("division by zero")
				end

				return math.floor(a / b)
			elseif op == "%" then
				if b == 0 then
					error("modulo by zero")
				end

				return a % b
			else
				return a ^ b
			end
		end
	end

	local factor

	local function atom()
		local token = take()
		if not token then
			error("Missing expression operand")
		end

		local number = tonumber(token)
		if number then
			return function()
				return number
			end
		end

		if token == "(" then
			local value = ternary()
			expect(")")
			return value
		end

		if not token:match("^[%a_][%w_]*$") then
			error("Invalid expression token " .. token)
		end

		if peek() == "(" then
			take()
			local fn = functions[token]
			if not fn then
				error("Unsupported driver function " .. token)
			end

			local arguments = {}
			if peek() ~= ")" then
				repeat
					table.insert(arguments, ternary())
				until peek() ~= "," or not take()
			end

			expect(")")
			return function(vars)
				local values = {}
				for i, arg in arguments do
					values[i] = arg(vars)
				end

				return fn(table.unpack(values))
			end
		end

		local constant = constants[token]
		return function(vars)
			local value = vars[token]
			if value == nil then
				value = constant
			end

			if value == nil then
				error("Unknown driver variable " .. token)
			end

			return value
		end
	end

	local function power()
		local base = atom()
		if peek() == "**" then
			take()
			return binary("**", base, factor())
		end

		return base
	end

	factor = function()
		if peek() == "-" or peek() == "+" then
			local sign = take()
			local operand = factor()
			return if sign == "-"
				then function(vars)
					return -operand(vars)
				end
				else operand
		end

		return power()
	end

	local function term()
		local lhs = factor()
		while peek() == "*" or peek() == "/" or peek() == "//" or peek() == "%" do
			local op = take()
			lhs = binary(op, lhs, factor())
		end

		return lhs
	end

	local function sum()
		local lhs = term()
		while peek() == "+" or peek() == "-" do
			local op = take()
			lhs = binary(op, lhs, term())
		end

		return lhs
	end

	local function comparison()
		local first = sum()
		if not comparisons[peek()] then
			return first
		end

		local ops, operands = {}, { first }
		while comparisons[peek()] do
			table.insert(ops, take())
			table.insert(operands, sum())
		end

		return function(vars)
			local left = operands[1](vars)
			for i, op in ops do
				local right = operands[i + 1](vars)
				local ok
				if op == "<" then
					ok = left < right
				elseif op == ">" then
					ok = left > right
				elseif op == "<=" then
					ok = left <= right
				elseif op == ">=" then
					ok = left >= right
				elseif op == "==" then
					ok = left == right
				else
					ok = left ~= right
				end

				if not ok then
					return 0
				end

				left = right
			end

			return 1
		end
	end

	local function negation()
		if peek() == "not" then
			take()
			local operand = negation()
			return function(vars)
				return operand(vars) == 0 and 1 or 0
			end
		end

		return comparison()
	end

	local function conjunction()
		local lhs = negation()
		while peek() == "and" do
			take()
			local left, right = lhs, negation()
			lhs = function(vars)
				local a = left(vars)
				if a == 0 then
					return a
				end

				return right(vars)
			end
		end

		return lhs
	end

	local function disjunction()
		local lhs = conjunction()
		while peek() == "or" do
			take()
			local left, right = lhs, conjunction()
			lhs = function(vars)
				local a = left(vars)
				if a ~= 0 then
					return a
				end

				return right(vars)
			end
		end

		return lhs
	end

	ternary = function()
		local value = disjunction()
		if peek() ~= "if" then
			return value
		end

		take()
		local condition = disjunction()
		expect("else")
		local other = ternary()
		return function(vars)
			if condition(vars) ~= 0 then
				return value(vars)
			end

			return other(vars)
		end
	end

	local ok, result = pcall(ternary)
	if not ok then
		return nil, result
	end

	if index <= #tokens then
		return nil, "Unsupported driver syntax"
	end

	return result
end

function Drivers.prepare(driver)
	local out = table.clone(driver)
	if driver.type == "SCRIPTED" then
		out.run, out.error = Drivers.compile(driver.expression or "0")
	end

	return out
end

local function rawValue(driver, read, frame)
	local values, variables = {}, {}
	for _, variable in driver.variables or {} do
		local value = read(variable, driver)
		if typeof(value) == "boolean" then
			value = value and 1 or 0
		end

		value = tonumber(value)
		if not value then
			return nil, "Unresolved driver variable " .. variable.name
		end

		variables[variable.name] = value
		table.insert(values, value)
	end

	if driver.type == "SCRIPTED" then
		if not driver.run then
			return nil, driver.error
		end

		if variables.frame == nil then
			variables.frame = frame or 0
		end

		local ok, result = pcall(driver.run, variables)
		if not ok then
			return nil, result
		end

		return result
	end

	local result = driver.type == "MIN" and math.huge or driver.type == "MAX" and -math.huge or 0
	for _, value in values do
		if driver.type == "MIN" then
			result = math.min(result, value)
		elseif driver.type == "MAX" then
			result = math.max(result, value)
		else
			result += value
		end
	end

	if driver.type == "AVERAGE" and #values > 0 then
		result /= #values
	end

	return result
end

local function bezier(a, b, c, d, t)
	local u = 1 - t
	return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
end

local function curveValue(curve, input)
	local points = curve.keyframes or {}
	local samples = curve.samples or {}
	local x, cycleOffset = input, 0
	if #points >= 2 then
		local first, last = points[1].co, points[#points].co
		local width = last[1] - first[1]
		if width > 1e-10 then
			for _, modifier in curve.modifiers or {} do
				if
					modifier.type == "CYCLES"
					and not modifier.mute
					and (x < first[1] or x > last[1])
				then
					local before = x < first[1]
					local mode = before and modifier.mode_before or modifier.mode_after
					local limit = before and modifier.cycles_before or modifier.cycles_after
					local cycle = math.floor((x - first[1]) / width)
					if mode ~= "NONE" and (not limit or limit == 0 or math.abs(cycle) <= limit) then
						x -= cycle * width
						if mode == "MIRROR" and cycle % 2 ~= 0 then
							x = last[1] - (x - first[1])
						end

						if mode == "REPEAT_OFFSET" then
							cycleOffset = cycle * (last[2] - first[2])
						end
					end
				end
			end
		end
	end

	local result = x
	if #points == 1 then
		result = points[1].co[2]
	elseif #points >= 2 then
		local a, b = points[1], points[#points]
		if x < a.co[1] or x > b.co[1] then
			local before = x < a.co[1]
			local endpoint = before and a or b
			result = endpoint.co[2]
			if curve.extrapolation == "LINEAR" and endpoint.interpolation ~= "CONSTANT" then
				local other = before and points[2] or points[#points - 1]
				local handle = before and endpoint.handle_left or endpoint.handle_right
				if endpoint.interpolation ~= "BEZIER" or not handle then
					handle = other.co
				end

				local dx = endpoint.co[1] - handle[1]
				if math.abs(dx) > 1e-10 then
					result += (x - endpoint.co[1]) * (endpoint.co[2] - handle[2]) / dx
				end
			end
		else
			for i = 2, #points do
				if x <= points[i].co[1] then
					a, b = points[i - 1], points[i]
					break
				end
			end

			local width = b.co[1] - a.co[1]
			local t = width > 1e-10 and math.clamp((x - a.co[1]) / width, 0, 1) or 0
			local interpolation = a.interpolation or "BEZIER"
			if x == a.co[1] then
				result = a.co[2]
			elseif x == b.co[1] then
				result = b.co[2]
			elseif interpolation == "CONSTANT" then
				result = a.co[2]
			elseif interpolation == "LINEAR" then
				result = a.co[2] + (b.co[2] - a.co[2]) * t
			elseif interpolation == "BEZIER" then
				local left, right = a.handle_right or a.co, b.handle_left or b.co
				local ldx, rdx = math.abs(left[1] - a.co[1]), math.abs(b.co[1] - right[1])
				local factor = ldx + rdx > width and width / (ldx + rdx) or 1
				local lx = a.co[1] + (left[1] - a.co[1]) * factor
				local ly = a.co[2] + (left[2] - a.co[2]) * factor
				local rx = b.co[1] + (right[1] - b.co[1]) * factor
				local ry = b.co[2] + (right[2] - b.co[2]) * factor
				local lo, hi = 0, 1
				for _ = 1, 35 do
					local mid = (lo + hi) * 0.5
					if bezier(a.co[1], lx, rx, b.co[1], mid) < x then
						lo = mid
					else
						hi = mid
					end
				end

				result = bezier(a.co[2], ly, ry, b.co[2], (lo + hi) * 0.5)
			else
				return nil, "Unsupported driver interpolation " .. interpolation
			end
		end
	elseif #samples > 0 then
		local a, b = samples[1].co or samples[1], samples[#samples].co or samples[#samples]
		if x <= a[1] then
			result = a[2]
		elseif x >= b[1] then
			result = b[2]
		else
			for i = 2, #samples do
				local point = samples[i].co or samples[i]
				if x <= point[1] then
					a, b = samples[i - 1].co or samples[i - 1], point
					break
				end
			end

			result = a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end

	result += cycleOffset
	for _, modifier in curve.modifiers or {} do
		if not modifier.mute and modifier.type ~= "CYCLES" then
			local value = result
			if modifier.type == "GENERATOR" then
				local coefficients = modifier.coefficients or {}
				if modifier.mode == "POLYNOMIAL_FACTORISED" then
					value = 1
					for i = 1, #coefficients, 2 do
						value *= coefficients[i] * x + (coefficients[i + 1] or 0)
					end
				else
					value = 0
					for i = #coefficients, 1, -1 do
						value = value * x + coefficients[i]
					end
				end

				if modifier.use_additive then
					value += result
				end
			elseif modifier.type == "FNGENERATOR" then
				local fn = functions[(modifier.function_type or "SIN"):lower()]
				if not fn then
					return nil, "Unsupported driver function modifier"
				end

				value = (modifier.amplitude or 1)
						* fn((modifier.phase_multiplier or 1) * x + (modifier.phase_offset or 0))
					+ (modifier.value_offset or 0)
				if modifier.use_additive then
					value += result
				end
			elseif modifier.type == "LIMITS" then
				if modifier.use_min_y then
					value = math.max(value, modifier.min_y)
				end

				if modifier.use_max_y then
					value = math.min(value, modifier.max_y)
				end
			else
				return nil, "Unsupported driver modifier " .. tostring(modifier.type)
			end

			local influence = modifier.use_influence and modifier.influence or 1
			result += (value - result) * influence
		end
	end

	return result
end

function Drivers.usesFrame(driver)
	if driver.type ~= "SCRIPTED" then
		return false
	end

	for token in (driver.expression or ""):gmatch("[%a_][%w_]*") do
		if token == "frame" then
			return true
		end
	end

	return false
end

function Drivers.evaluate(driver, read, frame)
	local value, err = rawValue(driver, read, frame)
	if value == nil then
		return nil, err
	end

	if driver.curve then
		return curveValue(driver.curve, value)
	end

	return value
end

Drivers.curveValue = curveValue
return Drivers
