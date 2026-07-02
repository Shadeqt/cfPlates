-- cfPlates ThreatGlow: an aggro-warning glow behind enemy nameplate health bars, keyed by YOUR threat
-- status on each mob. It's silent while you're in a safe spot and escalates as that erodes. The scale
-- flips by role:
--   TANK  -- danger is LOSING aggro:  yellow = catching up on you, orange = lost it (top threat),
--            red = lost it (behind). Securely tanking shows no glow. Works solo or grouped.
--   other -- danger is GAINING aggro: yellow = top threat (about to pull), orange = pulled (unstable),
--            red = securely tanking the mob. Sitting safely behind the tank shows no glow. Group only,
--            since solo you always hold aggro.
-- Plates of mobs we're not engaged with are left untouched. A numeric threat delta can ride beside the
-- plate (its own ThreatNumber sub-toggle). Toggle via the cfPlates GUI (reload).
--
-- Role gate: TANK mode runs whenever your assigned role is TANK; the GAINING-aggro mode runs for any
-- other role (DAMAGER/HEALER/unset) while you're in a group. Note Era reports a role only when one is
-- actually set, so a solo player with no role set sees nothing.
--
-- Scope: default Blizzard nameplates only. If you run Plater/TidyPlates/etc. they own the frame and
-- this feature does nothing useful. The Era client (1.15.x) exposes a real threat API --
-- UnitDetailedThreatSituation -- which 1.12 vanilla never had; that's what makes this possible.
--
-- Mechanism: we hooksecurefunc Blizzard's CompactUnitFrame_UpdateHealthColor (a convenient, frequent
-- tick) and show/hide a colored glow behind the health bar by threat status. We don't touch the health
-- bar's own color. Blizzard calls that on every health change; to catch threat-only changes (no health
-- change) we register each nameplate frame for its own unit's threat events and re-run UpdateHealthColor
-- from the frame's OnEvent. No polling.

local _, addon = ...

-- ---------------------------------------------------------------------------------------------------
-- Glow palettes, keyed by threat status from UnitDetailedThreatSituation("player", unit). Each is a
-- WARNING scale with no entry for its "safe" status, so safe yields no glow. A nil status means we're
-- not on the mob's threat table; nil and the omitted safe status both yield "no glow".
--
-- TANK -- escalates as you LOSE aggro; status 3 (securely tanking) is safe and omitted:
--   2 = tanking but NOT secure (someone's catching up)      -> yellow  (about to lose aggro)
--   1 = not tanking but still higher threat than the tank   -> orange  (just lost it, top threat)
--   0 = not tanking and behind                              -> red     (aggro lost)
local GLOW_COLORS_TANK = {
	[2] = { r = 1, g = 1,   b = 0 }, -- yellow
	[1] = { r = 1, g = 0.5, b = 0 }, -- orange
	[0] = { r = 1, g = 0,   b = 0 }, -- red
}

-- OTHER -- escalates as you GAIN aggro; status 0 (behind, safe) is omitted:
--   1 = not tanking but higher threat than the tank         -> yellow  (about to pull)
--   2 = tanking but NOT secure                              -> orange  (pulled, unstable)
--   3 = securely tanking the mob                            -> red     (firmly pulled)
local GLOW_COLORS_DPS = {
	[1] = { r = 1, g = 1,   b = 0 }, -- yellow
	[2] = { r = 1, g = 0.5, b = 0 }, -- orange
	[3] = { r = 1, g = 0,   b = 0 }, -- red
}

-- Number color in the safe status (no glow): green reads as "you're fine, here's your lead/gap".
local SAFE_NUMBER_COLOR = { r = 0, g = 1, b = 0 }

-- ---------------------------------------------------------------------------------------------------
-- Threat delta number. The highest threat held by anyone OTHER than us on this mob: when we're
-- tanking that's second place (our lead), when we're not it's the leader (our gap). Subtracting it
-- from our own threat yields a signed value with no need to branch on whether we're tanking.
-- Threat values from the API are stored x100; callers divide once at the end.
-- ---------------------------------------------------------------------------------------------------
local function HigherThreat(top, unit, mob)
	if UnitExists(unit) and not UnitIsUnit(unit, "player") then
		local v = select(5, UnitDetailedThreatSituation(unit, mob))
		if v and v > top then return v end
	end
	return top
end

local function MaxOtherThreat(mob)
	local top = HigherThreat(0, "pet", mob)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			top = HigherThreat(top, "raid" .. i, mob)
			top = HigherThreat(top, "raidpet" .. i, mob)
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			top = HigherThreat(top, "party" .. i, mob)
			top = HigherThreat(top, "partypet" .. i, mob)
		end
	end
	return top
end

local function FormatDelta(value)
	local n = math.floor(math.abs(value) + 0.5)
	if n == 0 then return "0" end
	return (value > 0 and "+" or "-") .. n
end

-- A frame's nameplate unit token ("nameplateN"), or nil if it isn't a live, non-forbidden nameplate.
-- Shared guard for the health-color hook and the two event hooks below.
local function NameplateUnit(frame)
	if not frame or frame:IsForbidden() then return end
	local unit = frame.unit
	if unit and strmatch(unit, "^nameplate%d") then return unit end
end

local function RefreshAll()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local f = plate.UnitFrame
		if f and not f:IsForbidden() then CompactUnitFrame_UpdateHealthColor(f) end
	end
end

-- ---------------------------------------------------------------------------------------------------
-- Glow. We own a dedicated flash texture per plate (a copy of PhantomPlates' NamePlateFlash, which does
-- this exact job), parented behind the health bar. We control its Show/Hide and color; Blizzard never
-- touches it. The texture's glow art occupies the left 144px of the 256-wide file, so we mirror
-- PhantomPlates' TexCoord. Width/height follow the bar (anchored to both its corners); the halo
-- thickness is expressed as a MULTIPLE of bar height, so it stays proportional if the bar is resized.
-- The factors below were the px insets tuned at a 10px bar height (-12, 13, 28, -11), divided by 10.
-- The right overhang is larger than the left because the art isn't centered in the file.
-- ---------------------------------------------------------------------------------------------------
local GLOW_TEXTURE = "Interface\\AddOns\\cfPlates\\_Media\\ThreatGlow"

local GLOW_LEFT, GLOW_TOP, GLOW_RIGHT, GLOW_BOTTOM = -1.2, 1.3, 2.8, -1.1

local function EnsureGlow(frame)
	local g = frame.cfGlow
	if g then return g end
	g = frame.healthBar:CreateTexture(nil, "BACKGROUND")
	g:SetTexture(GLOW_TEXTURE)
	g:SetTexCoord(0, 144 / 256, 0, 1)
	g:Hide()
	frame.cfGlow = g
	return g
end

local function SetGlow(frame, c)
	if not c then
		if frame.cfGlow then frame.cfGlow:Hide() end
		return
	end
	local g = EnsureGlow(frame)
	-- Re-fit each show: scale the inset factors by the bar's live height so the glow tracks any resize.
	local hp = frame.healthBar
	local h = hp:GetHeight()
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", hp, GLOW_LEFT * h, GLOW_TOP * h)
	g:SetPoint("BOTTOMRIGHT", hp, GLOW_RIGHT * h, GLOW_BOTTOM * h)
	g:SetVertexColor(c.r, c.g, c.b)
	g:Show()
end

-- ---------------------------------------------------------------------------------------------------
-- Override hook: runs after every Blizzard health-color update. For attackable plates of mobs whose
-- threat table we're on, show the glow by warning status and (optionally) our threat delta; everything
-- else clears our glow and hides our number.
-- ---------------------------------------------------------------------------------------------------
local function UpdateThreatVisuals(frame)
	local unit = NameplateUnit(frame)
	if not unit or not frame.healthBar then return end

	-- Pick the warning scale by role (Era reports a role only when one is set), only on enemies.
	-- TANK warns as you LOSE aggro (solo or grouped); any other role warns as you GAIN it, but only
	-- in a group (solo you always hold aggro, so every plate would light up red).
	local colors, status, mine
	if UnitCanAttack("player", unit) then
		if UnitGroupRolesAssigned("player") == "TANK" then
			colors = GLOW_COLORS_TANK
		elseif IsInGroup() then
			colors = GLOW_COLORS_DPS
		end
		if colors then
			local _
			_, status, _, _, mine = UnitDetailedThreatSituation("player", unit)
		end
	end

	-- Wrong role / not attackable, or not on this mob's threat table (nil): nothing to show. The
	-- safe status for the active scale also yields a nil glow below.
	if not colors or status == nil then
		SetGlow(frame, nil)
		if frame.cfThreatNumber then frame.cfThreatNumber:Hide() end
		return
	end

	SetGlow(frame, colors[status]) -- nil for the safe status -> clears any glow (safe = none)

	if cfPlatesDB.ThreatNumber then
		local fs = frame.cfThreatNumber
		if not fs then
			fs = frame:CreateFontString(nil, "OVERLAY")
			fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
			fs:SetPoint("LEFT", frame.healthBar, "RIGHT", 30, 0)
			frame.cfThreatNumber = fs
		end
		local c = colors[status] or SAFE_NUMBER_COLOR
		fs:SetText(FormatDelta(((mine or 0) - MaxOtherThreat(unit)) / 100))
		fs:SetTextColor(c.r, c.g, c.b)
		fs:Show()
	elseif frame.cfThreatNumber then
		frame.cfThreatNumber:Hide()
	end
end

-- ---------------------------------------------------------------------------------------------------
-- Event-driven refresh. Blizzard's own nameplate frames listen for their unit's events via
-- CompactUnitFrame_UpdateUnitEvents/_OnEvent; we piggyback on that. We register each plate for its
-- own unit's threat events, then re-run Blizzard's UpdateHealthColor when one fires -- our hook rides
-- on that tick and re-evaluates the border glow. No polling, no active-plate table.
--
-- Installed only when enabled; off is reload-gated, so no in-hook enabled check is needed.
-- ---------------------------------------------------------------------------------------------------
local hooked = false
function addon.SetupThreatGlow()
	if not cfPlatesDB.ThreatGlow then return end
	if hooked then return end
	hooked = true

	hooksecurefunc("CompactUnitFrame_UpdateHealthColor", UpdateThreatVisuals)

	hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
		local unit = NameplateUnit(frame)
		if not unit then return end
		local other = unit ~= frame.displayedUnit and frame.displayedUnit or nil
		frame:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit, other)
		frame:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", unit, other)
	end)

	hooksecurefunc("CompactUnitFrame_OnEvent", function(frame, event, eventUnit)
		local unit = NameplateUnit(frame)
		if not unit then return end
		if (event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE")
			and (eventUnit == unit or eventUnit == frame.displayedUnit) then
			CompactUnitFrame_UpdateHealthColor(frame)
		end
	end)

	-- Re-evaluate the role/group gate when either changes, so the glow applies/clears (and the scale
	-- flips between losing- and gaining-aggro) at once.
	local state = CreateFrame("Frame")
	state:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	state:RegisterEvent("PLAYER_ENTERING_WORLD")
	state:RegisterEvent("GROUP_ROSTER_UPDATE")
	state:SetScript("OnEvent", RefreshAll)
end
