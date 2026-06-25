local addonName, addon = ...

-- DB schema (the single source of truth for cfPlatesDB keys). All three features are simple bools,
-- default on. InitDB() merges newly-added defaults and prunes any key no longer in the schema.
addon.defaults = {
	NameplateText           = true,  -- centered current-HP number on hostile nameplates
	ThreatPlates            = true,  -- tint enemy nameplate health bars by your threat
	NameplateClassification = true,  -- elite/rare icons on nameplates
}

function addon.InitDB()
	cfPlatesDB = cfPlatesDB or {}
	-- Merge newly-added defaults.
	for key, value in pairs(addon.defaults) do
		if cfPlatesDB[key] == nil then
			cfPlatesDB[key] = value
		end
	end
	-- Prune keys no longer in the schema.
	for key in pairs(cfPlatesDB) do
		if addon.defaults[key] == nil then
			cfPlatesDB[key] = nil
		end
	end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	addon.InitDB()
	addon.SetupSettings()   -- register the GUI now that the DB is populated
	-- Defer feature setup to PLAYER_ENTERING_WORLD (nameplates exist there).
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		addon.SetupNameplateText()
		addon.SetupThreatPlates()
		addon.SetupNameplateClassification()
	end)
end)
