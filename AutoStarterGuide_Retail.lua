


-- AutoStarterGuide_Retail.lua
-- Retail-only: Auto-select the correct RXP starter guide based on the zone.

local addonName, addon = ...


print("|cff33ff99[RXP]|r File Loaded TS")

if not (addon and (addon.game == "MAINLINE" or addon.game == "RETAIL")) then
    return
end

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


--- TESTING: ---
---
--- -- --- Retail starter guide auto-picker with runtime name discovery ---
-- Put this in AutoStarterGuide_Retail.lua (we already guard for Retail earlier)

-- MapID -> list of aliases expected in the guide name.
-- (Add/adjust aliases freely; we match case-insensitively and allow partials.)
local STARTER_ZONE_ALIASES = {
    -- Exile's Reach variants
    [1409] = {"exile", "reach"},
    [1726] = {"exile", "reach"},

    -- Alliance
    [37]   = {"elwynn","northshire"},            -- Human
    [27]   = {"dun morogh","coldridge","gnome","dwarf"},
    [57]   = {"teldrassil","shadowglen","night elf"},
    [97]   = {"azuremyst","draenei"},
    [179]  = {"gilneas","worgen"},

    -- Horde
    [1]    = {"durotar","valley of trials","orc","troll"},
    [7]    = {"mulgore","red cloud mesa","tauren"},
    [18]   = {"tirisfal","deathknell","undead"},
    [94]   = {"eversong","sunstrider","blood elf"},

    -- Pandaren
    [378]  = {"wandering isle","shen-zin su","pandaren"},
}

-- Helper: fetch *any* of the internal guide registries
local function GetGuideRegistryCandidates()
    local regs = {}
    local R = addon or _G.RXPGuides or _G.RXP or _G.RXPRetail or _G.RestedXP
    if type(R) == "table" then
        for _,k in ipairs({"guides","RegisteredGuides","GuideRegistry","guideList"}) do
            if type(R[k]) == "table" then table.insert(regs, R[k]) end
        end
    end
    -- also scan any obvious global tables left around (some builds do)
    for gk,gv in pairs(_G) do
        if type(gk)=="string" and gk:match("^RXP") and type(gv)=="table" then
            for _,k in ipairs({"guides","RegisteredGuides","GuideRegistry","guideList"}) do
                if type(gv[k])=="table" then table.insert(regs, gv[k]) end
            end
        end
    end
    return regs
end

-- Heuristic: is a guide "starter-ish" (1–12, or contains starter-y words)?
local function IsStartery(name)
    if not name or type(name)~="string" then return false end
    local a,b = name:match("(%d+)%s*%-%s*(%d+)")
    if a and b and tonumber(a) and tonumber(b) and tonumber(b) <= 12 then
        return true
    end
    local n = name:lower()
    local words = {"exile","northshire","elwynn","durotar","mulgore","tirisfal","deathknell","dun morogh","colde?ridge",
                   "shadowglen","teldrassil","azuremyst","gilneas","eversong","wandering isle","shen%-zin"}
    for _,w in ipairs(words) do if n:find(w,1,true) then return true end end
    return false
end

-- From a list of aliases, find the best-matching guide name among all registries
local function FindGuideKeyByAliases(aliases)
    local regs = GetGuideRegistryCandidates()
    if #regs == 0 then return nil end
    local bestName, bestScore

    local function score(name)
        local s = 0
        local low = name:lower()
        for _,a in ipairs(aliases) do
            if low:find(a, 1, true) then s = s + 3 end         -- alias hit
        end
        local a,b = low:match("(%d+)%s*%-%s*(%d+)")
        if a and b then
            local hi = tonumber(b) or 0
            if hi > 0 and hi <= 12 then s = s + 2 end          -- 1–12-ish
        end
        if low:find("starter",1,true) or low:find("1%-10") then s = s + 1 end
        return s
    end

    local function consider(name)
        if not name then return end
        if not IsStartery(name) then return end
        local sc = score(name)
        if sc > 0 and (not bestScore or sc > bestScore) then
            bestName, bestScore = name, sc
        end
    end

    for _,tbl in ipairs(regs) do
        for k,v in pairs(tbl) do
            -- guides may be keyed by name, or be array elements with fields
            local name = (type(k)=="string" and k) or (type(v)=="table" and (v.name or v.title or v.key))
            consider(name)
        end
    end
    return bestName
end

-- Main resolver: figure out current zone and find a matching guide name
local function ResolveStarterGuideKey()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end

    -- Walk parents too
    local function ancestry(id, list)
        list = list or {}
        local cur = id
        local seen = {}
        while cur and not seen[cur] do
            table.insert(list, cur); seen[cur] = true
            local info = C_Map.GetMapInfo(cur); cur = info and info.parentMapID
        end
        return list
    end

    local ids = ancestry(mapID)
    for _,id in ipairs(ids) do
        local aliases = STARTER_ZONE_ALIASES[id]
        if aliases then
            local key = FindGuideKeyByAliases(aliases)
            if key then return key, id end
        end
    end
    return nil
end

-- Swap this into your TryAutoPickStarterGuide() core:
local function TryAutoPickStarterGuide(reason)
    local t = GetTime()
    if (t - (addon._starterLast or 0)) < 2.0 then return end
    addon._starterLast = t

    -- respect settings/level/manual choice (as in previous snippet)
    if not addon.settings.profile.autoRetailStarterGuide then return end
    local maxLvl = addon.settings.profile.autoRetailStarterMaxLevel or 10
    if UnitLevel("player") > maxLvl then return end
    if addon.settings.profile.autoRetailStarterGuideRespectManual and addon.currentGuide then return end

    local key, matchedID = ResolveStarterGuideKey()
    if not key then
        if addon.settings.profile.debug then
            print("|cff33ff99[RXP]|r AutoStarter: no matching guide name found for zone", C_Map.GetBestMapForUnit("player") or "nil")
        end
        return
    end
    if addon.currentGuide and addon.currentGuide.key == key then return end

    local ok, err = pcall(function()
        if addon.LoadGuideByName then addon:LoadGuideByName(key) else addon:LoadGuide(key) end
    end)
    if ok then
        if addon.settings.profile.debug then
            print(("|cff33ff99[RXP]|r AutoStarter: loaded '%s' (mapID %d) %s"):format(key, matchedID or -1, reason or ""))
        end
    else
        print("|cffff5555[RXP]|r AutoStarter: failed to load guide:", err)
    end
end

-- Hook events (as before)
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("NEW_WMO_CHUNK")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, ev) TryAutoPickStarterGuide(ev) end)
