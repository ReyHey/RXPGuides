-- AutoStarterGuide_Retail.lua
-- Retail-only: Auto-select the correct RXP starter guide based on the zone.

local addonName, addon = ...
if addon.game ~= "RETAIL" then return end

local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetMapInfo = C_Map.GetMapInfo
local UnitLevel = UnitLevel

-- ##############################
-- # SETTINGS (with safe defaults)
-- ##############################

-- Expose a toggle in Settings later; default ON
addon.settings = addon.settings or {}
addon.settings.profile = addon.settings.profile or {}
if addon.settings.profile.autoRetailStarterGuide == nil then
    addon.settings.profile.autoRetailStarterGuide = true
end

-- Only auto-pick if the player hasn't manually picked a guide yet
if addon.settings.profile.autoRetailStarterGuideRespectManual == nil then
    addon.settings.profile.autoRetailStarterGuideRespectManual = true
end

-- Only auto-pick while character is <= this level (10 matches starter flow)
addon.settings.profile.autoRetailStarterMaxLevel = addon.settings.profile.autoRetailStarterMaxLevel or 10

-- Debounce re-checks when zoning (sec)
local CHECK_COOLDOWN = 2.0

-- #####################################
-- # MapID → Guide Name/Key associations
-- #####################################
-- NOTE: Fill these with your *actual* guide keys exactly as they appear in RXP.
-- You can add subzone ids; the search walks up parents (child → continent).
-- Tip: /dump C_Map.GetBestMapForUnit("player") to see your current uiMapID (Retail).

local STARTER_ZONE_TO_GUIDE = {
    -- Exile's Reach
    [1409] = "RXP Retail\\Exile's Reach 1-10",   -- Exile's Reach (island)
    [1726] = "RXP Retail\\Exile's Reach 1-10",   -- Exile's Reach (scenario/phase variant) - keep if applicable

    -- Human
    [37]   = "RXP Retail\\Human 1-10 Elwynn Forest",   -- Elwynn Forest
    -- Dwarf/Gnome
    [27]   = "RXP Retail\\Dwarf & Gnome 1-10 Dun Morogh",
    -- Night Elf
    [57]   = "RXP Retail\\Night Elf 1-10 Teldrassil / Shadowglen",
    [460]  = "RXP Retail\\Night Elf 1-10 Teldrassil / Shadowglen", -- Shadowglen subzone (older clients)
    -- Draenei
    [97]   = "RXP Retail\\Draenei 1-10 Azuremyst Isle",
    -- Worgen (phased starting areas)
    [179]  = "RXP Retail\\Worgen 1-10 Gilneas",
    -- Orc/Troll
    [1]    = "RXP Retail\\Orc & Troll 1-10 Durotar",
    -- Tauren
    [7]    = "RXP Retail\\Tauren 1-10 Mulgore",
    -- Undead
    [18]   = "RXP Retail\\Undead 1-10 Tirisfal Glades",
    -- Blood Elf
    [94]   = "RXP Retail\\Blood Elf 1-10 Eversong Woods",
    -- Pandaren
    [378]  = "RXP Retail\\Pandaren 1-10 The Wandering Isle",

    -- (Optional) Allied races typically start at 10 in capitals; map if you have dedicated guides:
    -- e.g., [84] = "RXP Retail\\Allied Race 10-10 Stormwind Hand-in",      -- Stormwind City
    --       [85] = "RXP Retail\\Allied Race 10-10 Orgrimmar Hand-in",      -- Orgrimmar
}

-- ###########################
-- # Helper: ascend map chain
-- ###########################
local function GetAncestryMapIDs(mapID)
    local chain = {}
    local seen = {}
    local cur = mapID
    while cur and not seen[cur] do
        chain[#chain+1] = cur
        seen[cur] = true
        local info = GetMapInfo(cur)
        cur = info and info.parentMapID
    end
    return chain
end

-- #######################################
-- # Resolve guide from current player's map
-- #######################################
local function ResolveStarterGuideForPlayer()
    local mapID = GetBestMapForUnit("player")
    if not mapID then return nil end

    -- Check this map and all parents
    local chain = GetAncestryMapIDs(mapID)
    for _, id in ipairs(chain) do
        local guide = STARTER_ZONE_TO_GUIDE[id]
        if guide then
            return guide, id
        end
    end
    return nil
end

-- ########################################################
-- # Guard: respect manual choice & don't fight the player
-- ########################################################
local function ShouldAutoPick()
    if not addon.settings.profile.autoRetailStarterGuide then
        return false
    end
    local maxLvl = addon.settings.profile.autoRetailStarterMaxLevel or 10
    if UnitLevel("player") > maxLvl then
        return false
    end
    if addon.settings.profile.autoRetailStarterGuideRespectManual and addon.currentGuide then
        -- A guide is already loaded; don't override a manual pick.
        return false
    end
    return true
end

-- #################################
-- # Core: try to load the guide
-- #################################
local lastAttempt = 0
local function TryAutoPickStarterGuide(reason)
    local t = GetTime()
    if (t - lastAttempt) < CHECK_COOLDOWN then return end
    lastAttempt = t

    if not ShouldAutoPick() then return end

    local guideKey, matchedMapID = ResolveStarterGuideForPlayer()
    if not guideKey then
        if addon.settings.profile.debug then
            print("|cff33ff99[RXP]|r AutoStarter: No mapping for mapID", C_Map.GetBestMapForUnit("player") or "nil")
        end
        return
    end

    -- If the current guide is already this one, do nothing
    if addon.currentGuide and addon.currentGuide.key == guideKey then
        return
    end

    -- Load it
    local ok, err = pcall(function()
        -- Use your real loader:
        -- addon:LoadGuide(guideKey)
        -- or: addon:LoadGuideByName(guideKey)
        -- Depending on RXPGuides API; leaving both examples:
        if addon.LoadGuideByName then
            addon:LoadGuideByName(guideKey)
        else
            addon:LoadGuide(guideKey)
        end
    end)

    if ok then
        if addon.settings.profile.debug then
            print(string.format("|cff33ff99[RXP]|r AutoStarter: Loaded '%s' (mapID %d) [%s]",
                guideKey, matchedMapID, reason or ""))
        end
    else
        print("|cffff5555[RXP]|r AutoStarter: failed to load guide:", err)
    end
end

-- #########################################
-- # Events: first login + zone transitions
-- #########################################
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("NEW_WMO_CHUNK")           -- catches some instance/phase changes
f:RegisterEvent("PLAYER_LEVEL_UP")         -- stop at > max level

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        TryAutoPickStarterGuide("entering world")
    elseif event == "PLAYER_LEVEL_UP" then
        TryAutoPickStarterGuide("level up")
    else
        TryAutoPickStarterGuide(event:lower())
    end
end)

-- #########################################
-- # Optional: a tiny slash to print map id
-- #########################################
SLASH_RXPSTARTER1 = "/rxpstarter"
SlashCmdList.RXPSTARTER = function()
    local id = GetBestMapForUnit("player")
    print("|cff33ff99[RXP]|r uiMapID:", id or "nil")
end
