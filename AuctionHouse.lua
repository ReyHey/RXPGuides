local addonName, addon = ...

if addon.gameVersion > 20000 then return end

local fmt, tinsert, ipairs, pairs, next, type, wipe, tonumber, strlower =
    string.format, table.insert, ipairs, pairs, next, type, wipe, tonumber,
    strlower

addon.auctionHouse = addon:NewModule("AuctionHouse", "AceEvent-3.0")

local session = {}

function addon.auctionHouse:Setup()
    -- Placeholder, unknown is setup needed
end

-- TODO move ItemUpgrades.AH components here where possible
