local _, addon = ...

-- cfPlates settings page: one flat vertical-layout category. The feature checkboxes write a
-- cfPlatesDB bool applied at the next reload (the Setup* reads it at load); the only live controls
-- are the two nameplate class-color CVar toggles, which apply immediately.

-- A single-purpose table whose reads/writes proxy a boolean CVar, so a Settings checkbox can be
-- bound directly to the CVar instead of a saved variable. The key is ignored — one proxy per CVar.
local function CVarProxy(cvar)
	return setmetatable({}, {
		__index = function() return GetCVar(cvar) == "1" end,
		__newindex = function(_, _, value) SetCVar(cvar, value and "1" or "0") end,
	})
end

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

	-- Boolean setting bound live to a CVar; applies immediately, no reload.
	local function CVarCheckbox(cvar, label, tooltip)
		local setting = Settings.RegisterAddOnSetting(category, "cfPlates_cvar_" .. cvar, cvar,
			CVarProxy(cvar), Settings.VarType.Boolean, label, GetCVarBool(cvar))
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	local function Header(name)
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
	end

	Header("Some changes apply after /reload.")

	Checkbox("NameplateText", "Nameplate Health Text", "Show a centered current-HP number on hostile nameplate health bars")
	Checkbox("ThreatGlow", "Threat Glow", "Glow behind enemy nameplate health bars to warn about aggro (yellow->orange->red). As Tank it warns when you're losing aggro (silent while securely tanking); in any other role it warns when you're gaining it (group only)")
	Checkbox("ThreatNumber", "Threat Number", "Show a numeric threat delta beside the plate (your lead, or your gap once you've lost aggro). Requires Threat Glow")
	Checkbox("NameplateClassification", "Classification Icons", "Show elite and rare icons on nameplates")

	-- Class Colors (live CVar toggles, no reload)
	Header("Class Colors")
	CVarCheckbox("ShowClassColorInNameplate", "Enemy Nameplate Class Colors", "Color enemy player nameplates by class")
	CVarCheckbox("ShowClassColorInFriendlyNameplate", "Friendly Nameplate Class Colors", "Color friendly player nameplates by class")

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
