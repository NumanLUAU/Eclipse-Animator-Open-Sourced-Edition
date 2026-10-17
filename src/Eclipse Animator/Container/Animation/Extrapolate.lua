--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

return function(Animation: table, CurrentDelta: number)
	local LastFrame = Animation[#Animation]
	local LastFrame_time = LastFrame.Time
	local Lengh, LastIndex = LastFrame["Time"], #Animation
	local Start, End = Animation[1], LastFrame
	for i, v in Animation do
		local Time = v.Time
		if CurrentDelta == Time or i == LastIndex then
			Start, End = v, v
			break
		end

		if CurrentDelta > Time then
			if i + 1 == LastFrame then
				Start, End = v, v
				break
			end

			if Animation[i + 1].Time > CurrentDelta then
				Start, End = v, Animation[i + 1]
				break
			else
				continue
			end
		end
	end

	return Start, End
end
