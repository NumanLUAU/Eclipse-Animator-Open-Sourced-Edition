--!nocheck
--// cracked by numan

local assets = {}

for _, group in {
	script.EclipseEffectCatalogSingularColors,
	script.EclipseEffectCatalogLighting,
	script.EclipseEffectCatalogDoubleColors,
	script.EclipseEffectCatalogMisc,
} do
	for _, asset in require(group) do
		table.insert(assets, asset)
	end
end

return assets
