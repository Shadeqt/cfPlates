local _, addon = ...
local hooked = false

local RARE_ELITE_ICON = "Interface\\Tooltips\\RareEliteNameplateIcon"
local ELITE_ICON      = "Interface\\Tooltips\\EliteNameplateIcon"

local function UpdateClassification(nameplate, unit)
	if not nameplate.cfClassIcon then
		local healthBar = nameplate.UnitFrame.healthBar
		local icon = healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
		icon:SetSize(64, 32)
		icon:SetPoint("LEFT", healthBar, "RIGHT", -6, -3)
		nameplate.cfClassIcon = icon
	end

	local classification = UnitClassification(unit)
	local isElite = classification == "worldboss" or classification == "elite" or classification == "rareelite"
	local isRare = classification == "rare" or classification == "rareelite"

	if isElite or isRare then
		nameplate.cfClassIcon:SetTexture(isRare and RARE_ELITE_ICON or ELITE_ICON)
		nameplate.cfClassIcon:Show()
	else
		nameplate.cfClassIcon:Hide()
	end
end

local function HideClassification(nameplate)
	if nameplate.cfClassIcon then
		nameplate.cfClassIcon:Hide()
	end
end

function addon.SetupNameplateClassification()
	if not cfPlatesDB.NameplateClassification then return end

	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken
		if unit then UpdateClassification(plate, unit) end
	end

	if hooked then return end
	hooked = true

	-- Installed only when enabled; off is reload-gated, so no in-handler enabled check is needed.
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	frame:SetScript("OnEvent", function(_, event, unit)
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if not plate then return end
		if event == "NAME_PLATE_UNIT_ADDED" then
			UpdateClassification(plate, unit)
		else
			HideClassification(plate)
		end
	end)
end
