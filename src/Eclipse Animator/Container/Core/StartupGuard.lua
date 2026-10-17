--!nocheck
--// cracked by numan

const StartupGuard = {}
const failures = {}

function StartupGuard.run(name, callback, ...)
	const result = table.pack(xpcall(callback, debug.traceback, ...))
	if not result[1] then
		table.insert(failures, name)
		warn("[Eclipse startup] " .. name .. " could not start. The rest of Eclipse keeps working.\n" .. tostring(result[2]))
	end

	return table.unpack(result, 1, result.n)
end

function StartupGuard.failures()
	return table.clone(failures)
end

function StartupGuard.report(notify)
	if #failures == 0 then
		return
	end

	notify(
		"SOME TOOLS DID NOT LOAD",
		table.concat(failures, ", ") .. " could not start. Everything else works. Send the Output log to the Eclipse team.",
		10
	)
end

return StartupGuard
