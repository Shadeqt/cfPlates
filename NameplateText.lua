-- cfPlates NameplateText: centered current-HP number on hostile nameplate health bars.
--
-- Blizzard nameplate health bars carry no text and aren't driven by TextStatusBar_UpdateTextString,
-- so we attach our own centered FontString and refresh it from a SetValue hook (which keeps working
-- as Blizzard recycles plates between units).
--
-- Unlike the unit frames, nameplates have no native percent/value choice, so this is NOT gated on
-- NUMERIC: the number shows in every display mode and is hidden only on NONE (the user's global
-- "no bar text" switch, the statusTextDisplay CVar).

local _, addon = ...

local FONT = "Fonts\\FRIZQT__.TTF"

-- Read a bar's current value, rounded. Returns nil when there's nothing to show -- a dead target (0)
-- or a bar with no pool -- so callers can hide the text instead of printing "0".
local function BarValue(bar)
	local value = math.floor((bar:GetValue() or 0) + 0.5)
	local _, max = bar:GetMinMaxValues()
	if value <= 0 or (max or 0) <= 0 then return nil end
	return value
end

-- Format a value (already read + range-checked via BarValue) with thousands separators.
local function FormatValue(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- Create a centered FRIZQT FontString on `parent`, anchored over `anchor`. sizeDelta nudges the font
-- size (nameplate bars run smaller so the longer numbers fit the thinner bar).
local function MakeCenteredText(parent, anchor, sizeDelta)
	local text = parent:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	local _, size, flags = text:GetFont()
	text:SetFont(FONT, size + (sizeDelta or 0), flags)
	text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	return text
end

-- Which nameplates get an HP number: hostile (attackable) units only. Friendly mobs, NPCs, players,
-- and your own pet are skipped.
local function PlateAllowed(unit)
	return unit and UnitCanAttack("player", unit)
end

-- Update one nameplate health bar's HP number for the current display mode.
local function UpdatePlateText(hp)
	local text = hp.cfHpText
	if not text then return end
	if GetCVar("statusTextDisplay") == "NONE" or not PlateAllowed(hp.cfUnit) then
		text:Hide(); return
	end
	local value = BarValue(hp)
	if not value then text:Hide(); return end
	text:SetText(FormatValue(value))
	text:Show()
end

-- Ensure a plate's health bar has our FontString + SetValue hook, then refresh it. Idempotent:
-- safe to call on every NAME_PLATE_UNIT_ADDED for a recycled plate.
local function SetupPlate(plate, unit)
	local hp = plate.UnitFrame and plate.UnitFrame.healthBar
	if not hp then return end
	if not hp.cfHpText then
		hp.cfHpText = MakeCenteredText(hp, hp, -2)
	end
	if not hp.cfHooked then
		hooksecurefunc(hp, "SetValue", UpdatePlateText)
		hp.cfHooked = true
	end
	-- Remember the live unit on this (recycled) plate so the SetValue hook can re-check eligibility.
	hp.cfUnit = unit
	UpdatePlateText(hp)
end

local function RefreshPlates()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		SetupPlate(plate, plate.namePlateUnitToken)
	end
end

-- Installed only when enabled; off is reload-gated, so no in-handler enabled check is needed.
local hooked = false
function addon.SetupNameplateText()
	if not cfPlatesDB.NameplateText then return end

	RefreshPlates()

	if hooked then return end
	hooked = true

	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("CVAR_UPDATE")
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:SetScript("OnEvent", function(_, event, arg1)
		if event == "CVAR_UPDATE" then
			-- Only statusTextDisplay (NONE vs not) changes what we render; ignore unrelated CVar churn.
			if arg1 == "statusTextDisplay" then RefreshPlates() end
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			local plate = C_NamePlate.GetNamePlateForUnit(arg1)
			if plate then SetupPlate(plate, arg1) end
		end
	end)
end
