-- cfPlates ThreatPlates: tint enemy nameplate health bars by YOUR threat on each mob, from a tank's
-- perspective, using WoW's quest-difficulty colors. green = securely tanking, yellow = tanking but
-- someone's catching up, orange = not tanking but ahead of the mob's target, red = no aggro. Plates
-- of mobs we're not engaged with keep Blizzard's default color. Toggle via the cfPlates GUI (reload).
--
-- Scope: default Blizzard nameplates only. If you run Plater/TidyPlates/etc. they own the health bar
-- and this feature does nothing useful. The Era client (1.15.x) exposes a real threat API --
-- UnitDetailedThreatSituation -- which 1.12 vanilla never had; that's what makes this possible.
--
-- Mechanism: we hooksecurefunc Blizzard's CompactUnitFrame_UpdateHealthColor and override the color
-- for attackable nameplates with Blizzard's own quest-difficulty colors, keyed by your threat status.
-- Blizzard calls that on every health change; to catch threat-only changes (no health change) we
-- register each nameplate frame for its own unit's threat events and re-run UpdateHealthColor from
-- the frame's OnEvent. No polling.

local _, addon = ...

-- ---------------------------------------------------------------------------------------------------
-- Two interchangeable status -> color palettes, both keyed by threat status from
-- UnitDetailedThreatSituation("player", unit). Same hues, different source/saturation:
--   3 = securely tanking (highest threat)                 -> green
--   2 = tanking but NOT highest (insecure)                -> yellow
--   1 = not tanking but higher threat than the mob's target -> orange
--   0 = no aggro                                          -> red
-- A nil status means we're not on the mob's threat table -- we leave Blizzard's color alone.
-- STATUS_COLOR picks the active palette; swap that one line to test the other.
-- ---------------------------------------------------------------------------------------------------
local QUEST_COLORS = {
	[3] = QuestDifficultyColors.standard,      -- green
	[2] = QuestDifficultyColors.difficult,     -- yellow
	[1] = QuestDifficultyColors.verydifficult, -- orange
	[0] = QuestDifficultyColors.impossible,    -- red
}

-- Muted reputation-standing palette (FACTION_BAR_COLORS). NOTE: this is NOT what nameplates paint --
-- it's the faction/rep-bar palette. Kept only for comparison; REACTION_COLORS is the real plate match.
local FACTION_COLORS = {
	[3] = FACTION_BAR_COLORS[5], -- green  (Friendly)
	[2] = FACTION_BAR_COLORS[4], -- yellow (Neutral)
	[1] = FACTION_BAR_COLORS[3], -- orange (Unfriendly)
	[0] = FACTION_BAR_COLORS[2], -- red    (Hostile)
}

-- The colors nameplates actually display, i.e. what UnitSelectionColor returns (bright primaries).
-- Verified in-game: friendly 0,1,0 / neutral 1,1,0 / hostile 1,0,0. Unfriendly orange is inferred.
local REACTION_COLORS = {
	[3] = { r = 0, g = 1,   b = 0 }, -- green  (friendly)
	[2] = { r = 1, g = 1,   b = 0 }, -- yellow (neutral)
	[1] = { r = 1, g = 0.5, b = 0 }, -- orange (unfriendly)
	[0] = { r = 1, g = 0,   b = 0 }, -- red    (hostile)
}

local STATUS_COLOR = REACTION_COLORS -- swap to QUEST_COLORS or FACTION_COLORS to test

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

-- ---------------------------------------------------------------------------------------------------
-- Gate: in a group/raid our role MUST be TANK; solo, we run only if we have a pet (pet classes still
-- want threat relative to their pet). UnitGroupRolesAssigned returns "TANK"/"HEALER"/"DAMAGER"/"NONE".
-- IsInGroup() is true in a raid too. RefreshAll on the events that change either condition makes the
-- coloring apply/clear at once, not on the next threat tick.
-- ---------------------------------------------------------------------------------------------------
local function ShouldRun()
	if IsInGroup() then
		return UnitGroupRolesAssigned("player") == "TANK"
	end
	return UnitExists("pet")
end

local function RefreshAll()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local f = plate.UnitFrame
		if f and not f:IsForbidden() then CompactUnitFrame_UpdateHealthColor(f) end
	end
end

-- ---------------------------------------------------------------------------------------------------
-- Override hook: runs after every Blizzard health-color update. Re-tint only attackable nameplates of
-- mobs whose threat table we're on (and show our threat delta beside them); everything else keeps
-- Blizzard's default coloring and hides our number.
-- ---------------------------------------------------------------------------------------------------
local function ColorHealthBar(frame)
	if not frame or frame:IsForbidden() or not frame.healthBar then return end
	local unit = frame.unit or frame.displayedUnit
	if not unit or not strmatch(unit, "^nameplate%d") then return end

	if not ShouldRun() then
		if frame.cfThreatNumber then frame.cfThreatNumber:Hide() end
		return
	end

	local status, mine
	if UnitCanAttack("player", unit) then
		local _
		_, status, _, _, mine = UnitDetailedThreatSituation("player", unit)
	end
	local c = STATUS_COLOR[status]
	if not c then
		if frame.cfThreatNumber then frame.cfThreatNumber:Hide() end
		return
	end
	frame.healthBar:SetStatusBarColor(c.r, c.g, c.b)
	-- Keep Blizzard's color cache in sync with what we actually painted. Its
	-- UpdateHealthColor skips the repaint when this cache matches the color it
	-- wants; if we leave the cache holding the prior unit's color, a recycled
	-- nameplate (new mob, off our threat table) keeps our leftover tint instead
	-- of getting Blizzard's default. Syncing it lets that default repaint fire.
	frame.healthBar.r, frame.healthBar.g, frame.healthBar.b = c.r, c.g, c.b

	local fs = frame.cfThreatNumber
	if not fs then
		fs = frame:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
		fs:SetPoint("LEFT", frame.healthBar, "RIGHT", 30, 0)
		frame.cfThreatNumber = fs
	end
	fs:SetText(FormatDelta(((mine or 0) - MaxOtherThreat(unit)) / 100))
	fs:SetTextColor(c.r, c.g, c.b)
	fs:Show()
end

-- ---------------------------------------------------------------------------------------------------
-- Event-driven refresh. Blizzard's own nameplate frames listen for their unit's events via
-- CompactUnitFrame_UpdateUnitEvents/_OnEvent; we piggyback on that. We register each plate for its
-- own unit's threat events, then re-run Blizzard's UpdateHealthColor when one fires -- that resets the
-- bar to the default color, and our hook re-applies ours on top. No polling, no active-plate table.
--
-- Installed only when enabled; off is reload-gated, so no in-hook enabled check is needed.
-- ---------------------------------------------------------------------------------------------------
local hooked = false
function addon.SetupThreatPlates()
	if not cfPlatesDB.ThreatPlates then return end
	if hooked then return end
	hooked = true

	hooksecurefunc("CompactUnitFrame_UpdateHealthColor", ColorHealthBar)

	hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
		if frame:IsForbidden() then return end
		local unit = frame.unit
		if not unit or not strmatch(unit, "^nameplate%d") then return end
		local other = frame.unit ~= frame.displayedUnit and frame.displayedUnit or nil
		frame:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit, other)
		frame:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", unit, other)
	end)

	hooksecurefunc("CompactUnitFrame_OnEvent", function(frame, event, eventUnit)
		if frame:IsForbidden() then return end
		local unit = frame.unit
		if not unit or not strmatch(unit, "^nameplate%d") then return end
		if (event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE")
			and (eventUnit == unit or eventUnit == frame.displayedUnit) then
			CompactUnitFrame_UpdateHealthColor(frame)
		end
	end)

	-- Re-evaluate the gate when our role, group, or pet changes, so plates recolor/revert immediately.
	local state = CreateFrame("Frame")
	state:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	state:RegisterEvent("PLAYER_ENTERING_WORLD")
	state:RegisterEvent("GROUP_ROSTER_UPDATE")
	state:RegisterUnitEvent("UNIT_PET", "player")
	state:SetScript("OnEvent", RefreshAll)
end
