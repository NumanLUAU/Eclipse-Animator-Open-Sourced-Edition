local cache = setmetatable({}, { __mode = "k" })
return function(animation, seconds)
	assert(typeof(animation) == "Instance" and animation:IsA("Folder"), "Pass an exported FOV animation folder")
	assert(type(seconds) == "number" and seconds == seconds, "Time must be in seconds")
	local keys = cache[animation]
	if not keys then
		keys = {}
		for _, value in animation:GetChildren() do
			if value:IsA("NumberValue") and type(value:GetAttribute("Time")) == "number" then
				table.insert(keys, value)
			end
		end
		table.sort(keys, function(a, b) return a:GetAttribute("Time") < b:GetAttribute("Time") end)
		cache[animation] = keys
	end
	assert(#keys > 0, "The FOV export is empty")
	local lo, hi = 1, #keys
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if keys[mid]:GetAttribute("Time") <= seconds then lo = mid else hi = mid - 1 end
	end
	local a, b = keys[lo], keys[math.min(lo + 1, #keys)]
	local start, finish = a:GetAttribute("Time"), b:GetAttribute("Time")
	local alpha = finish > start and math.clamp((seconds - start) / (finish - start), 0, 1) or 0
	return a.Value + (b.Value - a.Value) * alpha
end
