--!nocheck
--// cracked by numan

return function(require)
	local P = {}
	function P.viewing()
		if P.Enabled then
			return P.View, P.FOV
		end
	end
	return P
end
