--!nocheck
--// cracked by numan

local catalog = script.Parent.Parent.EffectCatalog
local parts = { "return function(require)\nreturn {\n" }

for _, group in {
	catalog.EclipseEffectCatalogSingularColors,
	catalog.EclipseEffectCatalogLighting,
	catalog.EclipseEffectCatalogDoubleColors,
	catalog.EclipseEffectCatalogMisc,
} do
	local records = group:GetChildren()
	table.sort(records, function(a, b)
		return a.Name < b.Name
	end)
	for _, record in records do
		local source = record.Source
		local prefix = "--!nocheck\n--// cracked by numan\n\nreturn "
		assert(source:sub(1, #prefix) == prefix, "Invalid bundled effect record")
		table.insert(parts, source:sub(#prefix + 1):gsub("%s+$", "") .. ",\n")
	end
end

table.insert(parts, "}\nend\n")
return table.concat(parts)
