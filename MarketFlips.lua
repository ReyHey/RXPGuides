local addonName, addon = ...

if addon.gameVersion > 20000 then return end

local fmt, tinsert, ipairs, pairs, next, type, wipe, tonumber, strlower =
    string.format, table.insert, ipairs, pairs, next, type, wipe, tonumber,
    strlower

addon.marketFlips = addon:NewModule("MarketFlips", "AceEvent-3.0")

local session = {shoppingList = {}}

function addon.marketFlips:Setup()
    -- Toggle functionality off
    if not addon.settings.profile.marketFlips or
        not addon.settings.profile.enableTips then return end

    if not addon.settings.profile.enableBetaFeatures then return end

    session.shoppingList = {}

end
