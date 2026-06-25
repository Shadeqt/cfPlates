local _, addon = ...

-- cfPlates settings page: one flat vertical-layout category. Each checkbox writes a cfPlatesDB bool
-- applied at the next reload (the Setup* reads it at load); there's no live lifecycle.

-- Build the settings page. Called explicitly from Init's ADDON_LOADED handler, after InitDB(),
-- so cfPlatesDB is fully populated before any RegisterAddOnSetting reads cfPlatesDB[key]. A
-- freshly-created character has no saved DB yet, and registering a setting against a nil backing
-- value hands back an unusable setting object.
function addon.SetupSettings()
	local category = Settings.RegisterVerticalLayoutCategory("cfPlates")
	local layout = SettingsPanel:GetLayout(category)

	-- Boolean setting bound to cfPlatesDB[key]; reload-gated (no value-changed callback).
	local function Checkbox(key, label, tooltip)
		local setting = Settings.RegisterAddOnSetting(category, "cfPlates_" .. key, key, cfPlatesDB,
			Settings.VarType.Boolean, label, addon.defaults[key])
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	local function Header(name)
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
	end

	Header("Changes apply after /reload.")

	Checkbox("NameplateText", "Nameplate Health Text", "Show a centered current-HP number on hostile nameplate health bars")
	Checkbox("ThreatPlates", "Threat Coloring", "Tint enemy nameplate health bars by your threat (red->orange->yellow->green). Tank/pet perspective")
	Checkbox("NameplateClassification", "Classification Icons", "Show elite and rare icons on nameplates")

	Settings.RegisterAddOnCategory(category)

	-- Raise the panel above high-strata world UI (matches the other cf addons' settings pages).
	SettingsPanel:SetFrameStrata("FULLSCREEN_DIALOG")

	-- Make the panel draggable by its empty areas (child controls still take their own clicks).
	SettingsPanel:SetMovable(true)
	SettingsPanel:EnableMouse(true)
	SettingsPanel:RegisterForDrag("LeftButton")
	SettingsPanel:SetScript("OnDragStart", SettingsPanel.StartMoving)
	SettingsPanel:SetScript("OnDragStop", SettingsPanel.StopMovingOrSizing)

	SLASH_CFP1 = "/cfp"
	SlashCmdList.CFP = function() Settings.OpenToCategory(category:GetID()) end
end
